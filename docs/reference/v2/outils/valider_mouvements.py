"""Audit indépendant des primitives Python et des états illustratifs AIM/LOCAL V2.

Usage : python outils/valider_mouvements.py [--seeds 32]
Écrit rapports/mouvements.validation.json, retourne 1 si un invariant échoue.
Standard library uniquement. Aucun moteur Godot, input humain ou score simulé.
Les valeurs attendues viennent du catalogue et de calculs indépendants des
échantillonneurs : extrema analytiques, métrique sphérique, différences centrées.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib
import json
import math
import platform
import random
import sys
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE / "outils"))

import geometrie_reference as geo
import mouvements_reference as mr

DEG = 180.0 / math.pi
EPS_POSITION = 1e-7
EPS_VELOCITY = 1e-7


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def independent_piece(piece, t):
    """Position, vitesse, accélération : pas d'appel à evaluate_piece/signed_ramp."""
    dt = max(0.0, t - piece["origin_s"])
    v0 = piece["v0_deg_s"]
    if piece["shape"] == "constant":
        return piece["x_origin_deg"] + v0 * dt, v0, 0.0
    duration = piece["duration_s"]
    u = max(0.0, min(1.0, dt / duration))
    delta = piece["v1_deg_s"] - v0
    x = piece["x_origin_deg"] + v0 * min(dt, duration) + delta * duration * (u**3 - 0.5 * u**4)
    v = v0 + delta * (3 * u**2 - 2 * u**3)
    a = delta * 6 * u * (1 - u) / duration
    return x, v, a


def zero_of_velocity(piece, a, b):
    va = independent_piece(piece, a)[1]
    vb = independent_piece(piece, b)[1]
    if va * vb >= 0:
        return None
    for _ in range(64):
        mid = (a + b) / 2
        vm = independent_piece(piece, mid)[1]
        if va * vm <= 0:
            b = mid
        else:
            a, va = mid, vm
    return (a + b) / 2


def unit_direction(yaw, pitch):
    h, p = math.radians(yaw), math.radians(pitch)
    return math.cos(p) * math.sin(h), math.sin(p), -math.cos(p) * math.cos(h)


def distance_deg(a, b):
    cross = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    return math.atan2(math.sqrt(sum(x*x for x in cross)), sum(x*y for x, y in zip(a, b))) * DEG


def derivative_vector(motion, t, step):
    before = unit_direction(*motion.sample(t-step)[:2])
    center = unit_direction(*motion.sample(t)[:2])
    after = unit_direction(*motion.sample(t+step)[:2])
    velocity = tuple((c-a)/(2*step) for a, c in zip(before, after))
    acceleration = tuple((a-2*b+c)/(step*step) for a, b, c in zip(before, center, after))
    return math.sqrt(sum(x*x for x in velocity))*DEG, math.sqrt(sum(x*x for x in acceleration))*DEG


def independent_metric(a_deg, b_deg, q):
    a, b = math.radians(a_deg), math.radians(b_deg)
    pitch = b * math.sin(q)
    dh, dp = -a * math.sin(q), b * math.cos(q)
    return math.sqrt(math.cos(pitch)**2 * dh**2 + dp**2)


def composite_simpson_metric(a, b, cells):
    h = 2 * math.pi / cells
    total = independent_metric(a, b, 0) + independent_metric(a, b, 2*math.pi)
    total += 4 * sum(independent_metric(a, b, i*h) for i in range(1, cells, 2))
    total += 2 * sum(independent_metric(a, b, i*h) for i in range(2, cells, 2))
    return total * h / 3


class Audit:
    def __init__(self):
        self.checks = 0
        self.failure_count = 0
        self.failures = []
        self.failure_codes = {}
        self.groups = []

    def check(self, condition, code, context=None, observed=None, expected=None):
        self.checks += 1
        if not condition:
            self.failure_count += 1
            self.failure_codes[code] = self.failure_codes.get(code, 0) + 1
            if len(self.failures) < 100:
                item = {"code": code}
                if context is not None: item["context"] = context
                if observed is not None: item["observed"] = observed
                if expected is not None: item["expected"] = expected
                self.failures.append(item)
        return bool(condition)

    def run(self, name, function):
        start = time.perf_counter()
        before_checks, before_failures = self.checks, self.failure_count
        metrics = {}
        try:
            metrics = function() or {}
        except Exception as exc:
            self.check(False, "UNEXPECTED_EXCEPTION", name, repr(exc))
            metrics = {"traceback": traceback.format_exc(limit=5)}
        self.groups.append({"id": name, "status": "pass" if self.failure_count == before_failures else "fail",
                            "checks": self.checks-before_checks, "failures": self.failure_count-before_failures,
                            "elapsed_s": round(time.perf_counter()-start, 3), "metrics": metrics})


def audit_reactive_tape(audit, motion, tape, context):
    pieces = tape["pieces"]
    lo, hi = motion["yaw_bounds_deg"]
    minimum, maximum = motion["yaw_speed_abs_deg_s"]
    acceleration_limit = motion["velocity_transition"]["acceleration_limit_deg_s2"]
    quantum_position_tolerance = maximum * 0.5e-6 + 1e-7
    observed = {"min_yaw_deg": math.inf, "max_yaw_deg": -math.inf,
                "max_abs_speed_deg_s": 0.0, "max_abs_acceleration_deg_s2": 0.0,
                "max_position_join_error_deg": 0.0, "max_velocity_join_error_deg_s": 0.0,
                "boundary_events": 0, "rearm_events": 0, "ramps_preempted_by_boundary": 0,
                "rearms_inside_ramp": 0, "pieces": len(pieces)}
    audit.check(bool(pieces), "EMPTY_REACTIVE_TAPE", context)
    if not pieces:
        return observed
    audit.check(abs(pieces[0]["from_s"]) < 1e-12, "TAPE_NOT_STARTING_AT_ZERO", context)
    audit.check(abs(pieces[-1]["to_s"] - tape["horizon_s"]) < 1e-9, "TAPE_NOT_ENDING_AT_HORIZON", context)
    audit.check(abs(tape["initial_state"]["velocity_deg_s"]) >= minimum-1e-9, "INITIAL_SPEED_BELOW_PLATEAU_MINIMUM", context)
    for index, piece in enumerate(pieces):
        where = dict(context, piece=index)
        begin, end = piece["from_s"], piece["to_s"]
        audit.check(end > begin, "ZERO_OR_NEGATIVE_PIECE", where, [begin, end])
        audit.check(piece["origin_s"] <= begin+1e-9, "PIECE_ORIGIN_AFTER_SUBSEGMENT", where)
        audit.check(end <= piece["origin_s"]+piece["duration_s"]+1e-9, "PIECE_AFTER_PRIMITIVE_END", where)
        audit.check(abs(begin*1e6-round(begin*1e6)) < 1e-5 and abs(end*1e6-round(end*1e6)) < 1e-5, "NON_QUANTIZED_EVENT_TIME", where)
        candidates = [begin, end, (begin+end)/2]
        if piece["shape"] == "ramp":
            mid = piece["origin_s"] + piece["duration_s"]/2
            if begin <= mid <= end: candidates.append(mid)
            zero = zero_of_velocity(piece, begin, end)
            if zero is not None: candidates.append(zero)
        else:
            audit.check(abs(piece["v0_deg_s"]) >= minimum-1e-7, "UNDECLARED_NEAR_ZERO_PLATEAU", where, piece["v0_deg_s"], minimum)
        for t in candidates:
            x, v, acceleration = independent_piece(piece, t)
            observed["min_yaw_deg"] = min(observed["min_yaw_deg"], x)
            observed["max_yaw_deg"] = max(observed["max_yaw_deg"], x)
            observed["max_abs_speed_deg_s"] = max(observed["max_abs_speed_deg_s"], abs(v))
            observed["max_abs_acceleration_deg_s2"] = max(observed["max_abs_acceleration_deg_s2"], abs(acceleration))
            audit.check(lo-quantum_position_tolerance <= x <= hi+quantum_position_tolerance, "REACTIVE_YAW_OUTSIDE_HARD_BOUNDS", where, x, [lo, hi])
            audit.check(abs(v) <= maximum+1e-7, "REACTIVE_SPEED_CAP_EXCEEDED", where, abs(v), maximum)
            audit.check(abs(acceleration) <= acceleration_limit*(1+1e-8), "REACTIVE_ACCELERATION_CAP_EXCEEDED", where, abs(acceleration), acceleration_limit)
            actual = mr.evaluate_piece(piece, t)
            audit.check(abs(actual[0]-x) <= 1e-9 and abs(actual[1]-v) <= 1e-9, "PRIMITIVE_DISAGREES_WITH_INDEPENDENT_INTEGRAL", where, actual, [x, v])
        if index:
            previous = pieces[index-1]
            audit.check(abs(previous["to_s"]-begin) < 1e-9, "GAP_OR_OVERLAP_BETWEEN_PIECES", where)
            before = independent_piece(previous, begin)
            after = independent_piece(piece, begin)
            dx, dv = abs(before[0]-after[0]), abs(before[1]-after[1])
            observed["max_position_join_error_deg"] = max(observed["max_position_join_error_deg"], dx)
            observed["max_velocity_join_error_deg_s"] = max(observed["max_velocity_join_error_deg_s"], dv)
            audit.check(dx <= EPS_POSITION, "REACTIVE_POSITION_DISCONTINUITY", where, dx, EPS_POSITION)
            audit.check(dv <= EPS_VELOCITY, "REACTIVE_VELOCITY_DISCONTINUITY", where, dv, EPS_VELOCITY)
    prior_boundary = None
    events = tape["events"]
    end_index = {round(p["to_s"]*1e6): i for i, p in enumerate(pieces)}
    for i, event in enumerate(events):
        kind, t = event["kind"], event["time_us"]/1e6
        where = dict(context, event=i, kind=kind, t_s=t)
        if i:
            audit.check(event["time_us"] > events[i-1]["time_us"], "DUPLICATE_OR_REVERSED_EVENT_TIMESTAMP", where)
        if kind.startswith("boundary_"):
            observed["boundary_events"] += 1
            threshold = lo+motion["boundary"]["trigger_inset_deg"] if kind == "boundary_left" else hi-motion["boundary"]["trigger_inset_deg"]
            outgoing = -1 if kind == "boundary_left" else 1
            audit.check(abs(event["yaw_deg"]-threshold) <= quantum_position_tolerance, "BOUNDARY_TRIGGER_NOT_AT_THRESHOLD", where, event["yaw_deg"], threshold)
            audit.check(outgoing*event["velocity_deg_s"] > 0, "BOUNDARY_TRIGGER_NOT_OUTGOING", where)
            if prior_boundary is not None:
                earlier = prior_boundary
                # Une frontière ne peut être réarmée tant que sa vitesse n'a pas
                # été réellement inversée : contrôle direct des signes sur l'intervalle.
                between = [p for p in pieces if p["to_s"] > earlier["time_us"]/1e6 and p["from_s"] < t]
                entering_sign = 1 if earlier["kind"] == "boundary_left" else -1
                was_entering = any(entering_sign*independent_piece(p, min(p["to_s"],t))[1] > 1e-7 for p in between)
                audit.check(was_entering, "BOUNDARY_RETRIGGERED_WITHOUT_INWARD_RETURN", where, {"previous_time_us": earlier["time_us"], "current_time_us": event["time_us"]})
            prior_boundary = event
            if event["time_us"] != 0 and event["time_us"] in end_index:
                before = pieces[end_index[event["time_us"]]]
                if before["shape"] == "ramp" and t < before["origin_s"]+before["duration_s"]-1e-6:
                    observed["ramps_preempted_by_boundary"] += 1
        elif kind == "rearm":
            observed["rearm_events"] += 1
            audit.check(prior_boundary is not None, "REARM_WITHOUT_PRIOR_BOUNDARY", where)
            if prior_boundary:
                inward = 1 if prior_boundary["kind"] == "boundary_left" else -1
                audit.check(inward*event["velocity_deg_s"] > 0, "REARM_WHILE_STILL_OUTGOING", where, event["velocity_deg_s"])
            ix = end_index.get(event["time_us"])
            if ix is not None and ix+1 < len(pieces):
                before, after = pieces[ix], pieces[ix+1]
                if before["shape"] == "ramp" and t < before["origin_s"]+before["duration_s"]-1e-6:
                    observed["rearms_inside_ramp"] += 1
                    keys = ("shape", "origin_s", "x_origin_deg", "v0_deg_s", "v1_deg_s", "duration_s")
                    audit.check(all(before[k] == after[k] for k in keys), "REARM_REBASED_EXISTING_PRIMITIVE", where)
    return observed


def run(catalogue_path, atlas_path, report_path, seed_count):
    started = time.perf_counter()
    audit = Audit()
    catalogue = json.loads(catalogue_path.read_text())
    atlas = json.loads(atlas_path.read_text())
    inputs = {str(p.relative_to(BASE)): sha256(p) for p in [catalogue_path, atlas_path, BASE/"outils/mouvements_reference.py", BASE/"outils/construire_visuels.py", BASE/"outils/geometrie_reference.py"]}
    source_catalogue = BASE.parent / "analyse/catalogue_v2_resolu.json"
    conditions = {}
    for program in catalogue["programs"]:
        for phase in program["phases"]:
            conditions[(program["program_id"],program["difficulty"],phase["id"])] = (program,phase)
    reactive_conditions = [(key,p) for key,(_,p) in conditions.items() if p["motion"]["kind"].startswith("reactive")]
    visuals = importlib.import_module("construire_visuels")
    state_motions = []

    def provenance():
        audit.check(len(catalogue["programs"]) == 24, "EXPECTED_24_CONFIGURATIONS")
        audit.check(len(conditions) == 54, "EXPECTED_54_PHASES")
        audit.check(len(atlas["configs"]) == 24, "ATLAS_CONFIG_COUNT")
        audit.check(atlas["compiler_version"] == mr.COMPILER_VERSION, "ATLAS_COMPILER_VERSION_MISMATCH")
        if source_catalogue.exists():
            audit.check(json.loads(source_catalogue.read_text()) == catalogue, "SOURCE_AND_DELIVERY_CATALOGUE_DIVERGE")
        current = json.loads(json.dumps(visuals.CONFIGS, ensure_ascii=False, allow_nan=False))
        audit.check(current == atlas["configs"], "ATLAS_STATES_NOT_REBUILT_FROM_CURRENT_SOURCES", observed="serialized CONFIGS differ" if current != atlas["configs"] else "identical")
        for config in atlas["configs"]:
            for entry in config["phases"]:
                key = (config["program_id"],config["difficulty"],entry["id"])
                audit.check(entry["definition"] == conditions[key][1], "ATLAS_PHASE_DEFINITION_DIFFERS_FROM_CATALOGUE", key)
                for state in entry["states"]:
                    state_motions.append((key,entry,visuals.rebuild_motion(state)))
        return {"configuration_count":24,"phase_count":54,"serialized_motion_instances":len(state_motions),"compiler_version":mr.COMPILER_VERSION}
    audit.run("provenance_and_atlas_freshness", provenance)

    def reactive():
        totals = {"tapes":0,"stress_horizon_s":60,"pieces":0,"boundary_events":0,"rearm_events":0,"ramps_preempted_by_boundary":0,"rearms_inside_ramp":0,
                  "maximum_position_join_error_deg":0.,"maximum_velocity_join_error_deg_s":0.}
        cases = []
        for key, phase in reactive_conditions:
            maxima = {"min_yaw_deg":math.inf,"max_yaw_deg":-math.inf,"max_abs_speed_deg_s":0.,"max_abs_acceleration_deg_s2":0.}
            for seed in range(1,seed_count+1):
                tape = mr.compile_reactive(phase["motion"], seed, 60)
                stats = audit_reactive_tape(audit, phase["motion"], tape, {"condition":"/".join(key),"seed":seed})
                totals["tapes"] += 1
                for field in ("pieces","boundary_events","rearm_events","ramps_preempted_by_boundary","rearms_inside_ramp"):
                    totals[field] += stats[field]
                totals["maximum_position_join_error_deg"] = max(totals["maximum_position_join_error_deg"],stats["max_position_join_error_deg"])
                totals["maximum_velocity_join_error_deg_s"] = max(totals["maximum_velocity_join_error_deg_s"],stats["max_velocity_join_error_deg_s"])
                maxima["min_yaw_deg"] = min(maxima["min_yaw_deg"],stats["min_yaw_deg"])
                for field in ("max_yaw_deg","max_abs_speed_deg_s","max_abs_acceleration_deg_s2"):
                    maxima[field] = max(maxima[field],stats[field])
            cases.append({"condition":"/".join(key), **maxima})
        # Les fixtures ciblent les deux défauts trouvés par cet audit et les
        # deux côtés, même si les tirages aléatoires n'atteignent jamais le bord exact.
        threshold_cases = 0
        for key, phase in reactive_conditions:
            m = phase["motion"];lo,hi=m["yaw_bounds_deg"];inset=m["boundary"]["trigger_inset_deg"]
            for x in (lo+inset,hi-inset):
                for seed in (1,2,3,4):
                    tape = mr.compile_reactive(m,seed,60,initial_yaw_deg=x)
                    stats = audit_reactive_tape(audit,m,tape,{"condition":"/".join(key),"seed":seed,"initial_yaw_deg":x})
                    velocity = tape["initial_state"]["velocity_deg_s"]
                    outward = (x == hi-inset and velocity > 0) or (x == lo+inset and velocity < 0)
                    if outward:
                        audit.check(tape["events"][0]["time_us"] == 0 and tape["events"][0]["kind"].startswith("boundary_"),"OUTWARD_THRESHOLD_START_NOT_TURNED_AT_ZERO",{"condition":"/".join(key),"seed":seed,"initial_yaw_deg":x})
                    threshold_cases += 1
        totals["exact_threshold_initialization_cases"] = threshold_cases
        audit.check(totals["ramps_preempted_by_boundary"] > 0,"NO_RAMP_PREEMPTION_CASE_COVERED")
        audit.check(totals["rearms_inside_ramp"] > 0,"NO_REARM_SUBSEGMENT_CASE_COVERED")
        totals["conditions"] = cases
        return totals
    audit.run("reactive_analytic_extrema_continuity_and_rearming", reactive)

    def ellipses():
        cases=[];max_metric_error=0.;max_length_error=0.
        for level in ("novice","standard","advanced"):
            _,phase=conditions[("EX05",level,"ellipse")];m=phase["motion"]
            mo=mr.Motion(m,42,0,20);e=mo.ellipse
            fine_length=composite_simpson_metric(m["yaw_amplitude_deg"],m["pitch_amplitude_deg"],32768)
            length_error=abs(e.length-fine_length)/fine_length;max_length_error=max(max_length_error,length_error)
            audit.check(length_error <= 1e-9,"ELLIPSE_ARC_LENGTH_ERROR",level,length_error,1e-9)
            speed_error=0.;max_acceleration=0.;inverse_residual=0.
            for i in range(1025):
                q=2*math.pi*i/1024
                metric_error=abs(e.metric(q)-independent_metric(m["yaw_amplitude_deg"],m["pitch_amplitude_deg"],q))
                max_metric_error=max(max_metric_error,metric_error)
                audit.check(metric_error <= 1e-12,"ELLIPSE_NOT_USING_SPHERICAL_METRIC",level)
                arc=e.length*i/1025
                qq=e.parameter(arc)
                cell=min(e.n-1,int(qq/e.h));recovered=e.prefix[cell]+e.integral(cell*e.h,qq)
                residual=abs(recovered-arc);inverse_residual=max(inverse_residual,residual)
                audit.check(residual <= m["arc_length_solver"]["absolute_arc_error_rad"],"ELLIPSE_INVERSE_RESIDUAL",level,residual)
                t=.002+(20-.004)*i/1024
                measured_speed,measured_acceleration=derivative_vector(mo,t,.001)
                relative=abs(measured_speed/m["path_angular_speed_deg_s"]-1)
                speed_error=max(speed_error,relative);max_acceleration=max(max_acceleration,measured_acceleration)
                audit.check(relative <= m["arc_length_solver"]["relative_speed_error_validation_limit"],"ELLIPSE_TRUE_SPEED_NOT_CONSTANT",{"level":level,"t":t},relative)
                audit.check(measured_acceleration <= m["acceleration_validation_limit_deg_s2"]*(1+1e-4),"ELLIPSE_VECTOR_ACCELERATION_CAP",{"level":level,"t":t},measured_acceleration)
            period=e.length/math.radians(m["path_angular_speed_deg_s"])
            for t in (0,.1,1,5):
                audit.check(distance_deg(unit_direction(*mo.sample(t)[:2]),unit_direction(*mo.sample(t+period)[:2])) <= 1e-8,"ELLIPSE_PERIODIC_CLOSURE",level)
            cases.append({"difficulty":level,"length_rad":e.length,"relative_length_error":length_error,"maximum_relative_speed_error":speed_error,
                          "maximum_vector_acceleration_deg_s2":max_acceleration,"maximum_inverse_residual_rad":inverse_residual})
        return {"samples_per_difficulty":1025,"centered_difference_step_s":.001,"independent_length_cells":32768,
                "maximum_metric_absolute_error":max_metric_error,"maximum_length_relative_error":max_length_error,"conditions":cases}
    audit.run("ellipse_spherical_metric_inverse_speed_and_curvature",ellipses)

    def smooth_and_bounce():
        cases=[];impulse_cases=0;seam_cases=0
        for key,(program,phase) in conditions.items():
            m=phase["motion"];kind=m["kind"]
            if kind not in ("sinusoid_axis","linear_reflect","angular_bounce","depth_sines"):continue
            mo=mr.Motion(m,42,0,phase["duration_s"])
            max_speed=0.;max_acceleration=0.;max_radial_speed=0.;max_radial_acceleration=0.
            for i in range(801):
                t=.002+(phase["duration_s"]-.004)*i/800;step=.0001
                if kind=="sinusoid_axis":
                    axis=0 if m["axis"]=="yaw" else 1
                    before,center,after=(mo.sample(t+d)[axis] for d in (-step,0,step))
                    speed=abs((after-before)/(2*step));acceleration=abs((after-2*center+before)/step**2)
                    max_speed=max(max_speed,speed);max_acceleration=max(max_acceleration,acceleration)
                    audit.check(speed<=m["peak_angular_speed_deg_s"]*(1+1e-6),"SINUSOID_SPEED_CAP",key)
                    audit.check(acceleration<=m["peak_angular_acceleration_deg_s2"]*(1+1e-5),"SINUSOID_ACCELERATION_CAP",key)
                elif kind=="depth_sines":
                    speed,_=derivative_vector(mo,t,.001);max_speed=max(max_speed,speed)
                    before,center,after=(mo.sample(t+d)[2] for d in (-step,0,step))
                    radial_speed=abs((after-before)/(2*step));radial_acceleration=abs((after-2*center+before)/step**2)
                    max_radial_speed=max(max_radial_speed,radial_speed);max_radial_acceleration=max(max_radial_acceleration,radial_acceleration)
                    audit.check(speed<=m["angular_speed_upper_bound_deg_s"]*(1+1e-6),"DEPTH_ANGULAR_SPEED_CAP",key)
                    audit.check(radial_speed<=m["radial_speed_max_m_s"]*(1+1e-6),"DEPTH_RADIAL_SPEED_CAP",key)
                    audit.check(radial_acceleration<=m["radial_acceleration_max_m_s2"]*(1+1e-5),"DEPTH_RADIAL_ACCELERATION_CAP",key)
                elif kind=="linear_reflect":
                    before,center,after=(mo.sample(t+d)[0] for d in (-step,0,step))
                    speed=abs((after-before)/(2*step));max_speed=max(max_speed,speed)
                    audit.check(speed<=m["yaw_speed_deg_s"]*(1+1e-6),"LINEAR_SPEED_CAP",key)
                    if m["finite_acceleration_limit_applies"]:
                        acceleration=abs((after-2*center+before)/step**2);max_acceleration=max(max_acceleration,acceleration)
                        audit.check(acceleration<=m["peak_yaw_acceleration_deg_s2"]*(1+1e-5),"SOFT_REFLECTION_ACCELERATION_CAP",key)
                elif kind=="angular_bounce":
                    speed,_=derivative_vector(mo,t,.001);max_speed=max(max_speed,speed)
                    bound=math.hypot(m["yaw_speed_deg_s"],m["launch_pitch_velocity_deg_s"])
                    audit.check(speed<=bound*(1+1e-6),"BOUNCE_ANGULAR_SPEED_ABOVE_COMPONENT_BOUND",key,speed,bound)
                # Pour l'accélération des rebonds, éviter les impulsions et
                # contrôler l'intérieur de chaque vol, puis ses événements.
            if kind=="linear_reflect" and m["finite_acceleration_limit_applies"]:
                straight=m["straight_segment_duration_s"];turn=m["turn_duration_s"];period=2*(straight+turn)
                audit.check(abs(period-m["period_s"])<=1e-8,"SOFT_CYCLE_PERIOD_CONSISTENCY",key)
                audit.check(abs(m["turn_entry_inset_deg"]-5*m["yaw_speed_deg_s"]*turn/16)<=1e-8,"SOFT_TURN_INSET_CONSISTENCY",key)
                for raw in (0,straight,straight+turn,2*straight+turn,period):
                    t=(raw-mo.cycle*period)%period;step=1e-5
                    left=(mo.sample(t)[0]-mo.sample(t-step)[0])/step
                    right=(mo.sample(t+step)[0]-mo.sample(t)[0])/step
                    audit.check(abs(left-right)<=1e-3,"SOFT_REFLECTION_NOT_C1_AT_SEAM",{"condition":key,"t":t},abs(left-right))
                    audit.check(abs(mo.sample(t+period)[0]-mo.sample(t)[0])<=1e-7,"SOFT_REFLECTION_PERIODIC_POSITION",key)
                    seam_cases+=1
            if kind=="angular_bounce":
                for index,rec in enumerate(mo.bounces):
                    if rec["flight"] and rec["end"]-rec["start"] > .001:
                        for fraction in (.25,.5,.75):
                            t=rec["start"]+fraction*(rec["end"]-rec["start"])
                            step=min(.0001,(rec["end"]-rec["start"])/16)
                            before,center,after=(mo.sample(t+d)[1] for d in (-step,0,step))
                            acceleration=(after-2*center+before)/step**2
                            max_acceleration=max(max_acceleration,abs(acceleration))
                            audit.check(abs(acceleration-m["pitch_acceleration_deg_s2"])<=abs(m["pitch_acceleration_deg_s2"])*1e-5,"BOUNCE_FLIGHT_ACCELERATION_DOES_NOT_MATCH_PARAMETERS",{"condition":key,"t":t},acceleration,m["pitch_acceleration_deg_s2"])
                    if index==len(mo.bounces)-1:break
                    t=rec["end"];step=1e-7
                    left=mo.sample(t-step);right=mo.sample(t+step)
                    bound=max(m["yaw_speed_deg_s"],m["launch_pitch_velocity_deg_s"])*2*step+1e-7
                    audit.check(abs(left[0]-right[0])<=bound and abs(left[1]-right[1])<=bound,"BOUNCE_POSITION_DISCONTINUITY",{"condition":key,"t":t})
                    audit.check(abs(mo.sample(t)[1]-m["chambers"][0]["baseline_pitch_deg"])<=1e-8,"BOUNCE_NOT_AT_BASELINE_AT_EVENT",{"condition":key,"t":t})
                    if rec["flight"]:
                        audit.check(abs((rec["end"]-rec["start"])+rec["age"]-m["flight_duration_s"])<=1e-8,"BOUNCE_FLIGHT_DURATION_CHANGED",key)
                    else:
                        duration=rec["end"]-rec["start"]
                        audit.check(m["ground_rest_uniform_s"][0]-1e-8<=duration<=m["ground_rest_uniform_s"][1]+1e-8,"BOUNCE_REST_OUTSIDE_RANGE",key)
                    impulse_cases+=1
            cases.append({"condition":"/".join(key),"speed_measure":"true_spherical" if kind in ("depth_sines","angular_bounce") else "active_axis_coordinate",
                          "maximum_measured_speed_deg_s":max_speed,
                          "maximum_measured_scalar_acceleration_deg_s2":max_acceleration,
                          "maximum_measured_radial_speed_m_s":max_radial_speed,"maximum_measured_radial_acceleration_m_s2":max_radial_acceleration})
        # Collision mur/atterrissage exactement simultanée, avec positions
        # initiales construites depuis l'âge tiré : le bord doit imposer l'intérieur.
        _,phase=conditions[("EX04","standard","arcs")];m=phase["motion"]
        wall_ties=0
        for seed in range(1,9):
            initial=mr.Motion(m,seed,0,20);rec=initial.bounces[0]
            lo,hi=m["chambers"][0]["yaw_deg"];v=rec["v"];duration=rec["end"]
            x0=hi-v*duration if v>0 else lo-v*duration
            audit.check(lo<=x0<=hi,"WALL_TIE_FIXTURE_OUTSIDE_CHAMBER",seed)
            test=mr.Motion(m,seed,0,20,initial_yaw_deg=x0)
            rest=test.bounces[1];wall=hi if v>0 else lo
            audit.check(abs(rest["x"]-wall)<1e-8,"WALL_TIE_POSITION",seed)
            audit.check(rest["v"]<0 if v>0 else rest["v"]>0,"WALL_TIE_NOT_INWARD_AFTER_LANDING_FLIP",seed,rest["v"])
            wall_ties+=1
        return {"conditions":cases,"soft_cycle_seams":seam_cases,"flight_rest_boundaries":impulse_cases,"exact_wall_landing_ties":wall_ties,
                "impulsive_reflections_have_no_finite_acceleration_assertion":True}
    audit.run("smooth_axes_soft_cycles_depth_and_angular_bounces",smooth_and_bounce)

    def atlas_geometry():
        instances=0;positions=0;pair_checks=0;minimum_observed_gap=math.inf
        for config in atlas["configs"]:
            for entry in config["phases"]:
                p=entry["definition"];key=(config["program_id"],config["difficulty"],p["id"])
                mo=[visuals.rebuild_motion(s) for s in entry["states"]];instances+=len(mo)
                if mo:
                    samples=[i/60 for i in range(round(p["duration_s"]*60)+1)]
                else:samples=[0]
                for t in samples:
                    points=[]
                    if mo:
                        for slot,motion in enumerate(mo):
                            h,v,dd=motion.sample(t);d=dd if dd is not None else p["distance_m"]
                            points.append((h,v,d))
                            if t==0 and p["spawn"]["kind"] in ("one_target_per_lane","one_target_per_chamber"):
                                anchor=p["spawn"]["initial_reference_yaw_pitch_deg"]
                                angle=distance_deg(unit_direction(h,v),unit_direction(*anchor))
                                audit.check(angle>=p["spawn"]["transition_angle_deg"][0]-1e-8,"ATLAS_INITIAL_TRANSITION_TOO_SHORT",{"condition":key,"slot":slot},angle)
                            if p["spawn"]["kind"]=="one_target_per_chamber":
                                bounds=p["motion"]["chambers"][slot]["yaw_deg"]
                                audit.check(bounds[0]-1e-7<=h<=bounds[1]+1e-7,"ATLAS_TARGET_LEFT_ITS_CHAMBER",{"condition":key,"slot":slot,"t":t})
                    elif entry["static_positions"]:
                        points=[(*pos,p["distance_m"]) for pos in entry["static_positions"]]
                    for slot,(h,v,d) in enumerate(points):
                        where={"condition":key,"slot":slot,"t":t}
                        r=p["size"]["world_radius_m"];D=math.degrees(2*math.asin(r/d));env=p["envelope"]
                        audit.check(all(math.isfinite(x) for x in (h,v,d,r)),"NONFINITE_POSE",where)
                        audit.check(env["center_yaw_deg"][0]-1e-6<=h<=env["center_yaw_deg"][1]+1e-6 and env["center_pitch_deg"][0]-1e-6<=v<=env["center_pitch_deg"][1]+1e-6,"ATLAS_POSE_OUTSIDE_ENVELOPE",where,[h,v])
                        audit.check(env["center_distance_m"][0]-1e-9<=d<=env["center_distance_m"][1]+1e-9,"ATLAS_DISTANCE_OUTSIDE_ENVELOPE",where,d)
                        audit.check(geo.visible_sphere(h,v,d,r),"ATLAS_SPHERE_CLIPPED_OR_UNDER_FLOOR",where)
                        if p["size"]["mode"]=="world_radius_constant":
                            audit.check(p["size"]["minimum_apparent_diameter_deg"]-1e-7<=D<=p["size"]["maximum_apparent_diameter_deg"]+1e-7,"DEPTH_APPARENT_DIAMETER_RANGE",where,D)
                        positions+=1
                    for j,a in enumerate(points):
                        for b in points[j+1:]:
                            angle=distance_deg(unit_direction(*a[:2]),unit_direction(*b[:2]))
                            gap=angle-p["diameter_deg"]
                            minimum_observed_gap=min(minimum_observed_gap,gap)
                            audit.check(gap>=p["spawn"]["minimum_silhouette_gap_deg"]-1e-6,"ATLAS_TARGET_SILHOUETTES_OVERLAP",{"condition":key,"t":t},gap)
                            pair_checks+=1
                if p["motion"]["kind"]=="reactive_lanes":
                    lanes=sorted(p["motion"]["lanes_pitch_deg"]);amplitude=p["motion"]["vertical"]["amplitude_deg"]
                    guaranteed=min(b-a-2*amplitude for a,b in zip(lanes,lanes[1:]))-p["diameter_deg"]
                    audit.check(guaranteed>=p["spawn"]["minimum_silhouette_gap_deg"]-1e-9,"LANE_ANTIOCCLUSION_ANALYTIC_BOUND",key,guaranteed)
                if p["motion"]["kind"] in ("reactive_axis","reactive_lanes"):
                    for motion in mo:
                        for i in range(101):
                            t=.002+(p["duration_s"]-.004)*i/100
                            speed,_=derivative_vector(motion,t,.001)
                            audit.check(speed<=p["motion"]["nominal_full_angular_speed_upper_bound_deg_s"]*(1+1e-5),"REACTIVE_LANE_TRUE_ANGULAR_SPEED_BOUND",{"condition":key,"t":t},speed)
        return {"serialized_instances":instances,"pose_samples":positions,"simultaneous_pairs":pair_checks,"sample_rate_hz":60,
                "minimum_observed_silhouette_gap_deg":minimum_observed_gap,"reactive_lane_vertical_gap_checked_analytically":True}
    audit.run("atlas_initial_states_envelopes_lanes_chambers_and_sizes",atlas_geometry)

    def opportunities():
        count=0;max_ttl_error=0.;minimum_slot_slack=math.inf
        for config in atlas["configs"]:
            if config["program_id"]!="EX03":continue
            for entry in config["phases"]:
                p=entry["definition"];schedule=p["spawn"]["schedule"];ops=entry["opportunities"]
                key=(config["difficulty"],entry["id"])
                audit.check(len(ops)==10,"EX03_NOT_TEN_OPPORTUNITIES",key)
                previous=p["spawn"]["initial_reference_yaw_pitch_deg"]
                for op in ops:
                    onset,deadline=op["onset_s"],op["deadline_s"];slot=op["slot"]
                    where={"condition":key,"slot":slot};delay=onset-slot*3;ttl=deadline-onset
                    max_ttl_error=max(max_ttl_error,abs(ttl-p["lifecycle"]["ttl_s"]))
                    minimum_slot_slack=min(minimum_slot_slack,(slot+1)*3-deadline)
                    audit.check(schedule["onset_delay_uniform_s"][0]-1e-6<=delay<=schedule["onset_delay_uniform_s"][1]+1e-6,"EX03_ONSET_DELAY_RANGE",where)
                    audit.check(abs(ttl-p["lifecycle"]["ttl_s"])<=1e-6,"EX03_TTL_CHANGED_BY_QUANTIZATION",where)
                    audit.check(onset<deadline<=(slot+1)*3 and deadline<=p["duration_s"],"EX03_WINDOW_OUTSIDE_ITS_SLOT",where)
                    angle=distance_deg(unit_direction(*previous),unit_direction(*op["yaw_pitch_deg"]))
                    lower,upper=p["spawn"]["transition_angle_deg"]
                    audit.check(lower-1e-8<=angle<=upper+1e-8,"EX03_PROGRAMMED_CENTER_TRANSITION",where,angle)
                    previous=op["yaw_pitch_deg"]
                    for t,expected in ((onset-1e-7,0),(onset,1),((onset+deadline)/2,1),(deadline-1e-7,1),(deadline,0),(deadline+1e-7,0)):
                        targets=visuals.targets_at(entry,t)
                        audit.check(len(targets)==expected,"EX03_ENDPOINT_WINDOW_SEMANTICS",dict(where,t=t),len(targets),expected)
                    for fraction in (0,.5,.999999):
                        targets=visuals.targets_at(entry,onset+fraction*ttl)
                        if targets:
                            expectedD=p["size"]["diameter_start_deg"]+(p["size"]["diameter_end_deg"]-p["size"]["diameter_start_deg"])*fraction
                            actualD=math.degrees(2*math.asin(targets[0][3]/targets[0][2]))
                            audit.check(abs(actualD-expectedD)<1e-7,"EX03_SHRINK_NOT_LINEAR_IN_ANGULAR_DIAMETER",dict(where,fraction=fraction),actualD,expectedD)
                    count+=1
                audit.check(not visuals.targets_at(entry,p["duration_s"]),"EX03_VISIBLE_AFTER_PHASE_END",key)
        for key,(_,p) in conditions.items():
            if p["mechanic"]=="switching" and p["motion"]["kind"]=="static":
                label=visuals.phase_summary(p)
                audit.check("impact" not in label and ("PV" in label or "destruction" in label),"SWITCHING_STATIC_LABEL_SUGGESTS_ONE_SHOT",key,label)
        return {"opportunities":count,"maximum_ttl_difference_s":max_ttl_error,"minimum_deadline_to_slot_end_s":minimum_slot_slack,
                "onset_inclusive_deadline_exclusive_checked":True,"render_proxy_and_human_input_not_simulated":True}
    audit.run("ex03_calendar_deadlines_shrink_and_switching_label",opportunities)

    def stateless():
        sample_count=0;unchanged_states=0;matched_rates=0
        validator_rng=random.Random(92221)
        original_rng_next=geo.XorShift32.next_u32
        def forbidden_rng(self):raise RuntimeError("RNG_CALLED_DURING_SAMPLING")
        for key,entry,motion in state_motions:
            duration=entry["definition"]["duration_s"]
            times=sorted([0,duration]+[validator_rng.uniform(0,duration) for _ in range(64)])
            saved=copy.deepcopy(visuals.serialize_motion(motion))
            expected={t:motion.sample(t) for t in times}
            geo.XorShift32.next_u32=forbidden_rng
            try:
                shuffled=times.copy();validator_rng.shuffle(shuffled)
                for t in shuffled:
                    actual=motion.sample(t);reference=expected[t]
                    audit.check(actual==reference,"POSE_DEPENDS_ON_SAMPLING_ORDER",{"condition":key,"t":t})
                    sample_count+=1
                # Les instants communs sont 0,1/6,2/6,... puisque 60,144,240
                # ont pour PGCD12 ; 1/6 est donc commun aux trois fréquences.
                for k in range(int(duration*6)+1):
                    t=k/6
                    samples=[motion.sample(round(t*rate)/rate) for rate in (60,144,240)]
                    audit.check(samples[0]==samples[1]==samples[2],"POSE_DEPENDS_ON_REFERENCE_FRAME_RATE",{"condition":key,"t":t})
                    matched_rates+=1
            finally:
                geo.XorShift32.next_u32=original_rng_next
            audit.check(saved==visuals.serialize_motion(motion),"SAMPLING_MUTATES_MOTION_STATE",key)
            unchanged_states+=1
        return {"motion_instances":unchanged_states,"random_order_queries":sample_count,"shared_timestamp_rate_triplets":matched_rates,
                "reference_rates_hz":[60,144,240],"rng_calls_during_sample_forbidden":True}
    audit.run("stateless_random_access_no_rng_and_frame_rate_independence",stateless)

    def detector_canaries():
        _,phase=conditions[("EX06","standard","reactive")];m=phase["motion"]
        tape=mr.compile_reactive(m,17,5)
        corrupt=copy.deepcopy(tape);corrupt["pieces"][1]["x_origin_deg"]+=.25
        probe=Audit();audit_reactive_tape(probe,m,corrupt,{"canary":"position_jump"})
        audit.check(any(e["code"]=="REACTIVE_POSITION_DISCONTINUITY" for e in probe.failures),"VALIDATOR_DID_NOT_CATCH_POSITION_JUMP")
        corrupt=copy.deepcopy(tape)
        for p in corrupt["pieces"]:
            if p["shape"]=="ramp":
                p["v1_deg_s"]*=4;break
        probe=Audit();audit_reactive_tape(probe,m,corrupt,{"canary":"speed_and_acceleration"})
        audit.check(any(e["code"] in ("REACTIVE_SPEED_CAP_EXCEEDED","REACTIVE_ACCELERATION_CAP_EXCEEDED") for e in probe.failures),"VALIDATOR_DID_NOT_CATCH_CAP_VIOLATION")
        class EuclideanEllipse(mr.Ellipse):
            def metric(self,q):return math.hypot(-self.a*math.sin(q),self.b*math.cos(q))
        _,phase=conditions[("EX05","standard","ellipse")];m=phase["motion"]
        wrong=mr.Motion(m,42,0,20);wrong.ellipse=EuclideanEllipse(16,10);wrong.arc0=.2*wrong.ellipse.length
        error=max(abs(derivative_vector(wrong,.01+i*19.98/200,.001)[0]/m["path_angular_speed_deg_s"]-1) for i in range(201))
        audit.check(error>m["arc_length_solver"]["relative_speed_error_validation_limit"],"ELLIPSE_TEST_WOULD_ACCEPT_WRONG_EUCLIDEAN_METRIC",observed=error)
        return {"deliberately_corrupted_objects_detected":3,"wrong_euclidean_metric_relative_speed_error":error,
                "production_sources_never_modified_by_canaries":True}
    audit.run("negative_controls_for_independent_detectors",detector_canaries)

    unchanged_inputs={name:sha256(BASE/name)==digest for name,digest in inputs.items()}
    for name,unchanged in unchanged_inputs.items():
        audit.check(unchanged,"AUDITED_INPUT_CHANGED_DURING_RUN",name)
    report={
        "report_version":"aimlocal.motion_validation.v2.0",
        "generated_at_utc":datetime.now(timezone.utc).isoformat(),
        "status":"pass" if audit.failure_count==0 else "fail",
        "scope":"Python design reference and serialized illustrative atlas states only",
        "python_version":platform.python_version(),"compiler_version":mr.COMPILER_VERSION,
        "catalogue_revision":catalogue["catalogue_revision"],"seeds_per_reactive_condition":seed_count,
        "checks":audit.checks,"failure_count":audit.failure_count,"failure_code_counts":audit.failure_codes,"failures":audit.failures,
        "input_sha256":inputs,"audited_inputs_unchanged_during_run":all(unchanged_inputs.values()),
        "groups":audit.groups,"elapsed_s":round(time.perf_counter()-started,3),
        "coverage_limits":[
            "Not an audit of the existing Godot application; no Godot project was supplied or executed.",
            "No mouse-event ordering, rendering latency, photon timing, hit detection, contact integration, scoring or human performance is simulated.",
            "Reactive extrema and ramp caps are analytic within the compiled finite tapes; finite seed coverage is not a proof for every possible seed or arbitrary future parameters.",
            "Ellipse speed and vector acceleration are independently sampled with centered differences; length and metric checks are independent of the production lookup inversion.",
            "Finite acceleration assertions exclude explicitly impulsive wall reflections, launches and landings.",
            "Atlas checks cover initial generation and no-input trajectories, not arbitrary hit-driven replacement histories or every fallback candidate.",
            "Javascript/Python equivalence, SVG pixel rendering, UI text clipping and browser interaction are checked separately by the parent workflow.",
        ],
        "regressions_found_and_protected":[
            "An outward start exactly on a soft threshold must create a boundary event at t=0 without a zero-duration piece.",
            "A boundary rounded below its exact root must not rearm while velocity still points outward.",
            "A rearm splitting an existing ramp must preserve the original polynomial coefficients and origin.",
            "The static switching label must describe depletion of HP rather than one-shot replacement.",
        ],
    }
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps({"status":report["status"],"checks":audit.checks,"failures":audit.failure_count,"report":str(report_path),"elapsed_s":report["elapsed_s"]},ensure_ascii=False))
    for group in audit.groups:
        if group["status"]!="pass":print(json.dumps({"failed_group":group["id"],"failures":group["failures"]}))
    return 0 if report["status"]=="pass" else 1


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds",type=int,default=32)
    parser.add_argument("--catalogue",type=Path,default=BASE/"donnees/catalogue.v2.json")
    parser.add_argument("--atlas",type=Path,default=BASE/"donnees/atlas.etats.json")
    parser.add_argument("--report",type=Path,default=BASE/"rapports/mouvements.validation.json")
    args=parser.parse_args()
    if args.seeds<1:parser.error("--seeds must be positive")
    raise SystemExit(run(args.catalogue.resolve(),args.atlas.resolve(),args.report.resolve(),args.seeds))
