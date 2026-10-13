#!/usr/bin/env python3
"""Validate the frozen AIM/LOCAL V2 catalogue with the Python standard library.

Development/CI tool, not a player-side dependency or a general JSON Schema engine.
Supported schema keywords are listed in SUPPORTED_SCHEMA_KEYWORDS. Unknown schema
keywords fail closed. Semantic checks and negative fixtures complement structure.
No Godot runtime, Windows export, device latency or human performance is tested.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOGUE = ROOT / "donnees/catalogue.v2.json"
DEFAULT_SCHEMA = ROOT / "schemas/catalogue.schema.json"
SUPPORTED_SCHEMA_KEYWORDS = {
    "$schema", "$id", "$comment", "$defs", "$ref", "title", "description",
    "type", "const", "enum", "properties", "required", "additionalProperties",
    "items", "minItems", "maxItems", "uniqueItems", "oneOf", "anyOf", "allOf",
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
    "minLength", "maxLength", "pattern",
}
EXPECTED_PHASES = {
    "EX01": [("micro", 20, "click", "static"), ("general", 20, "click", "static"),
             ("amplitude", 20, "click", "static")],
    "EX02": [("grid", 20, "click", "static"), ("precision", 40, "click", "static")],
    "EX03": [("fixed_window", 30, "opportunity", "static"),
             ("shrinking_window", 30, "opportunity", "static")],
    "EX04": [("linear", 20, "click", "linear_reflect"),
             ("evasive", 20, "click", "reactive_lanes"),
             ("arcs", 20, "click", "angular_bounce")],
    "EX05": [("horizontal", 20, "tracking", "sinusoid_axis"),
             ("vertical", 20, "tracking", "sinusoid_axis"),
             ("ellipse", 20, "tracking", "angular_ellipse")],
    "EX06": [("reactive", 60, "tracking", "reactive_axis")],
    "EX07": [("depth", 60, "tracking", "depth_sines")],
    "EX08": [("static", 20, "switching", "static"),
             ("mobile", 20, "switching", "linear_reflect"),
             ("evasive", 20, "switching", "reactive_lanes")],
}
SCORE_IDS = {
    "click": "click_v3", "opportunity": "opportunities_v2",
    "tracking": "contact_v2", "switching": "switch_work_v3",
}
FIRE_MODES = {
    "click": "press_edge", "opportunity": "press_edge",
    "tracking": "automatic_contact_measurement", "switching": "hold_continuous_damage",
}
RANGE_KEYS = {
    "center_yaw_deg", "center_pitch_deg", "center_distance_m", "yaw_deg", "pitch_deg",
    "transition_angle_deg", "onset_delay_uniform_s", "candidate_yaw_deg",
    "yaw_bounds_deg", "yaw_speed_abs_deg_s", "uniform_duration_s",
    "phase_rad_distribution", "ground_rest_uniform_s", "initial_flight_age_uniform_s",
    "initial_yaw_uniform_deg", "initial_cycle_fraction_uniform",
    "initial_phase_rad_uniform", "initial_arc_fraction_uniform",
    "annulus_azimuth_rad_uniform", "angle_deg",
}


class StrictJSONError(ValueError):
    pass


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise StrictJSONError(f"Duplicate object key: {key!r}")
        result[key] = value
    return result


def _finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise StrictJSONError(f"Non-finite or overflowing JSON number: {text}")
    return value


def _safe_int(text):
    value = int(text)
    if abs(value) > 2**53 - 1:
        raise StrictJSONError("Integer exceeds the exact JSON interchange range, 2^53-1")
    return value


def strict_loads(raw: str | bytes):
    if isinstance(raw, bytes):
        try:
            raw = raw.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            raise StrictJSONError(str(exc)) from exc
    if raw.startswith("\ufeff"):
        raise StrictJSONError("UTF-8 BOM is not accepted by this contract")
    try:
        value = json.loads(
            raw, object_pairs_hook=_pairs, parse_float=_finite_float, parse_int=_safe_int,
            parse_constant=lambda value: (_ for _ in ()).throw(
                StrictJSONError(f"Forbidden JSON numeric constant: {value}")
            ),
        )
    except (ValueError, RecursionError) as exc:
        raise StrictJSONError(str(exc)) from exc
    # Python accepts escaped lone surrogates; the interchange contract does not.
    def check_unicode(v):
        if isinstance(v, str):
            if any(0xD800 <= ord(ch) <= 0xDFFF for ch in v):
                raise StrictJSONError("Unpaired Unicode surrogate")
        elif isinstance(v, list):
            for x in v:
                check_unicode(x)
        elif isinstance(v, dict):
            for k, x in v.items():
                check_unicode(k)
                check_unicode(x)
    check_unicode(value)
    return value


def issue(path: str, code: str, message: str):
    return {"path": path or "$", "code": code, "message": message}


def number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def json_equal(a, b):
    if number(a) and number(b):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    return a == b


def check_schema_subset(schema, path="$schema"):
    if isinstance(schema, bool):
        return
    if not isinstance(schema, dict):
        raise ValueError(f"{path}: schema must be an object or boolean")
    unknown = set(schema) - SUPPORTED_SCHEMA_KEYWORDS
    if unknown:
        raise ValueError(f"{path}: unsupported schema keywords {sorted(unknown)}")
    for group in ("$defs", "properties"):
        for name, sub in schema.get(group, {}).items():
            check_schema_subset(sub, f"{path}.{group}.{name}")
    for group in ("oneOf", "anyOf", "allOf"):
        for index, sub in enumerate(schema.get(group, [])):
            check_schema_subset(sub, f"{path}.{group}[{index}]")
    for group in ("items", "additionalProperties"):
        if isinstance(schema.get(group), (dict, bool)):
            check_schema_subset(schema[group], f"{path}.{group}")
    ref = schema.get("$ref")
    if ref is not None and not ref.startswith("#/"):
        raise ValueError(f"{path}: only local JSON Pointer references are supported")


def _resolve_ref(root, ref):
    value = root
    for item in ref[2:].split("/"):
        value = value[item.replace("~1", "/").replace("~0", "~")]
    return value


def validate_structure(value, schema, root=None, path="$"):
    root = schema if root is None else root
    errors = []
    if schema is True:
        return errors
    if schema is False:
        return [issue(path, "false_schema", "Value is forbidden")]
    if "$ref" in schema:
        errors.extend(validate_structure(value, _resolve_ref(root, schema["$ref"]), root, path))
    for combiner in ("oneOf", "anyOf", "allOf"):
        if combiner not in schema:
            continue
        branches = [validate_structure(value, sub, root, path) for sub in schema[combiner]]
        good = sum(not branch for branch in branches)
        valid = (good == 1 if combiner == "oneOf" else good >= 1 if combiner == "anyOf" else good == len(branches))
        if not valid:
            errors.append(issue(path, combiner, f"{good} matching branches among {len(branches)}"))
            if good == 0 and branches:
                errors.extend(min(branches, key=len)[:8])
    if "const" in schema and not json_equal(value, schema["const"]):
        errors.append(issue(path, "const", f"Expected fixed value {schema['const']!r}"))
    if "enum" in schema and not any(json_equal(value, x) for x in schema["enum"]):
        errors.append(issue(path, "enum", "Value is outside the declared enumeration"))
    if "type" in schema:
        typ = schema["type"]
        matches = {
            "null": value is None,
            "boolean": isinstance(value, bool),
            "number": number(value),
            "integer": number(value) and math.isfinite(value) and value == math.floor(value),
            "string": isinstance(value, str),
            "array": isinstance(value, list),
            "object": isinstance(value, dict),
        }
        if typ not in matches:
            raise ValueError(f"Unsupported schema type {typ!r}")
        if not matches[typ]:
            return errors + [issue(path, "type", f"Expected {typ}, received {type(value).__name__}")]
    if number(value):
        if not math.isfinite(value):
            errors.append(issue(path, "finite", "All numbers must be finite"))
        for key, fn in (
            ("minimum", lambda a, b: a >= b), ("maximum", lambda a, b: a <= b),
            ("exclusiveMinimum", lambda a, b: a > b), ("exclusiveMaximum", lambda a, b: a < b),
        ):
            if key in schema and not fn(value, schema[key]):
                errors.append(issue(path, key, f"{value} violates {key}={schema[key]}"))
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(issue(path, "minLength", "String is too short"))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(issue(path, "maxLength", "String is too long"))
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            errors.append(issue(path, "pattern", "String does not match the declared pattern"))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(issue(path, "minItems", "Array has too few entries"))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(issue(path, "maxItems", "Array has too many entries"))
        if schema.get("uniqueItems") and any(json_equal(value[i], value[j]) for i in range(len(value)) for j in range(i)):
            errors.append(issue(path, "uniqueItems", "Array entries must be unique"))
        if "items" in schema:
            for i, child in enumerate(value):
                errors.extend(validate_structure(child, schema["items"], root, f"{path}[{i}]"))
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(issue(f"{path}.{key}", "required", "Required field is missing"))
        properties = schema.get("properties", {})
        for key, child in value.items():
            if key in properties:
                errors.extend(validate_structure(child, properties[key], root, f"{path}.{key}"))
            elif schema.get("additionalProperties") is False:
                errors.append(issue(f"{path}.{key}", "additionalProperties", "Unknown field"))
            elif isinstance(schema.get("additionalProperties"), dict):
                errors.extend(validate_structure(child, schema["additionalProperties"], root, f"{path}.{key}"))
    return errors


def close(a, b, abs_tol=1e-8, rel_tol=1e-8):
    return math.isclose(a, b, abs_tol=abs_tol, rel_tol=rel_tol)


def direction(yaw_deg, pitch_deg):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    return math.cos(pitch) * math.sin(yaw), math.sin(pitch), -math.cos(pitch) * math.cos(yaw)


def angle_deg(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    cross = (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    return math.degrees(math.atan2(math.sqrt(sum(x*x for x in cross)), dot))


def interval_mul(a, b):
    values = [x*y for x in a for y in b]
    return min(values), max(values)


def trig_interval(lo_deg, hi_deg, cosine=False):
    lo, hi = math.radians(lo_deg), math.radians(hi_deg)
    fn = math.cos if cosine else math.sin
    points = [lo, hi]
    base = 0.0 if cosine else math.pi/2
    for k in range(math.ceil((lo-base)/math.pi), math.floor((hi-base)/math.pi)+1):
        points.append(base + k*math.pi)
    values = [fn(x) for x in points]
    return min(values), max(values)


def geometry_certificate(arena, phase):
    env, size = phase["envelope"], phase["size"]
    yaw, pitch, dist = env["center_yaw_deg"], env["center_pitch_deg"], env["center_distance_m"]
    sx, cx = trig_interval(*yaw), trig_interval(*yaw, cosine=True)
    sy, cy = trig_interval(*pitch), trig_interval(*pitch, cosine=True)
    x = interval_mul(dist, interval_mul(cy, sx))
    y = interval_mul(dist, sy)
    forward = interval_mul(dist, interval_mul(cy, cx))
    z = (-forward[1], -forward[0])
    dmax = max(phase["diameter_deg"], size.get("diameter_start_deg", phase["diameter_deg"]),
               size.get("diameter_end_deg", phase["diameter_deg"]))
    r = size["world_radius_m"] if size["mode"] == "world_radius_constant" else dist[1]*math.sin(math.radians(dmax/2))
    hf, vf = math.radians(arena["fov_horizontal_deg_at_16_9"]/2), math.radians(arena["fov_vertical_deg"]/2)
    planes = {
        "left": math.cos(hf)*x[0] - math.sin(hf)*z[1] - r,
        "right": -math.cos(hf)*x[1] - math.sin(hf)*z[1] - r,
        "top": -math.cos(vf)*y[1] - math.sin(vf)*z[1] - r,
        "bottom": math.cos(vf)*y[0] - math.sin(vf)*z[1] - r,
        "near": forward[0] - arena["near_m"] - r,
        "far": arena["far_m"] - forward[1] - r,
    }
    floor = arena["eye_position_m"][1] + y[0] - r - arena["floor_y_m"]
    wall = arena["wall_reference_distance_m"] - forward[1] - r
    return {
        "method": "conservative_interval_AABB_of_nominal_spherical_envelope",
        "maximum_world_radius_m": r,
        "minimum_floor_clearance_m": floor,
        "frustum_plane_lower_bounds_m": planes,
        "minimum_wall_clearance_m": wall,
    }


def stopping_distance_upper_bound(vmax, vmin, nominal_duration, accel):
    # Bound any outward v0 in [0,vmax] and inward speed w in [vmin,vmax].
    # Actual T <= Tmax. At any normalized time, v0*(1-h)-w*h is maximized
    # by v0=vmax,w=vmin; integrating its positive part gives a safe bound.
    duration = max(nominal_duration, 3*vmax/accel)
    lo, hi = 0.0, 1.0
    for _ in range(64):
        u = (lo+hi)/2
        if vmax - (vmax+vmin)*(3*u*u-2*u*u*u) > 0:
            lo = u
        else:
            hi = u
    u = (lo+hi)/2
    return duration*(vmax*u-(vmax+vmin)*(u**3-u**4/2))


def ellipse_peak_sample(motion, samples=8192):
    # Analytic derivatives evaluated on a fixed q grid; a numerical check,
    # not a continuous interval certificate of the acceleration maximum.
    a, b = map(math.radians, (motion["yaw_amplitude_deg"], motion["pitch_amplitude_deg"]))
    speed = math.radians(motion["path_angular_speed_deg_s"])
    peak = 0.0
    for i in range(samples):
        q = 2*math.pi*i/samples
        yaw, pitch = a*math.cos(q), b*math.sin(q)
        dy, dp = -a*math.sin(q), b*math.cos(q)
        ddy, ddp = -a*math.cos(q), -b*math.sin(q)
        sy, cy, sp, cp = math.sin(yaw), math.cos(yaw), math.sin(pitch), math.cos(pitch)
        uy = (cp*cy, 0.0, cp*sy)
        up = (-sp*sy, cp, sp*cy)
        uyy = (-cp*sy, 0.0, cp*cy)
        uyp = (-sp*cy, 0.0, -sp*sy)
        upp = (-cp*sy, -sp, cp*cy)
        uq = tuple(uy[k]*dy+up[k]*dp for k in range(3))
        uqq = tuple(uy[k]*ddy+up[k]*ddp+uyy[k]*dy*dy+2*uyp[k]*dy*dp+upp[k]*dp*dp for k in range(3))
        sigma2 = sum(x*x for x in uq)
        projection = sum(x*y for x, y in zip(uq, uqq))/sigma2
        accel = tuple(speed*speed/sigma2*(uqq[k]-uq[k]*projection) for k in range(3))
        peak = max(peak, math.degrees(math.sqrt(sum(x*x for x in accel))))
    return peak


def validate_semantics(catalogue):
    """Cross-field checks for this contract, after successful structural validation."""
    errors, certificates, motion_checks = [], [], []

    def require(condition, path, code, message):
        if not condition:
            errors.append(issue(path, code, message))

    def eq(actual, expected, path, code="derived_value"):
        require(close(actual, expected), path, code,
                f"Expected {expected:.12g}, received {actual:.12g}")

    def contained(inner, outer):
        return outer[0]-1e-8 <= inner[0] <= inner[1] <= outer[1]+1e-8

    def range_checks(value, path="$"):
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}.{key}"
                if key in RANGE_KEYS and isinstance(child, list) and len(child) == 2 and all(number(x) for x in child):
                    require(child[0] <= child[1], child_path, "range_order",
                            "Interval minimum must not exceed its maximum")
                range_checks(child, child_path)
        elif isinstance(value, list):
            for i, child in enumerate(value):
                range_checks(child, f"{path}[{i}]")

    range_checks(catalogue)
    # A malformed interval can invalidate later trigonometric assumptions.
    if errors:
        return errors, {"geometry": [], "motion": [], "scope": "blocked_by_invalid_ranges"}
    programs = catalogue["programs"]
    expected_keys = {(f"EX{i:02d}", level) for i in range(1, 9)
                     for level in ("novice", "standard", "advanced")}
    actual_keys = [(p["program_id"], p["difficulty"]) for p in programs]
    require(len(programs) == catalogue["configuration_count"] == 24,
            "$.programs", "configuration_count", "Exactly 24 resolved configurations are required")
    require(len(actual_keys) == len(set(actual_keys)), "$.programs", "duplicate_configuration",
            "Program/difficulty keys must be unique")
    require(set(actual_keys) == expected_keys, "$.programs", "configuration_set",
            "Expected EX01 through EX08, each at novice, standard and advanced")
    require(len({key[0] for key in actual_keys}) == catalogue["public_program_count"] == 8,
            "$.public_program_count", "public_program_count", "Exactly eight public programs are required")
    require(sum(len(p["phases"]) for p in programs) == 54,
            "$.programs", "phase_count", "The catalogue must contain 54 resolved phases")

    for pi, program in enumerate(programs):
        pp = f"$.programs[{pi}]"
        program_id = program["program_id"]
        require(close(program["duration_s"], 60), pp+".duration_s", "program_duration",
                "Public programs last exactly 60 scheduled seconds")
        expected = EXPECTED_PHASES[program_id]
        require(len(program["phases"]) == len(expected), pp+".phases", "program_phase_count",
                "Unexpected number of phases for this public program")
        arena = program["arena"]
        h, v = arena["fov_horizontal_deg_at_16_9"], arena["fov_vertical_deg"]
        aw, ah = arena["reference_aspect_ratio"]
        basic_arena_valid = 0 < h < 180 and 0 < v < 180 and aw > 0 and ah > 0 and 0 < arena["near_m"] < arena["far_m"]
        require(basic_arena_valid, pp+".arena", "camera_domain",
                "Perspective FOV, aspect and clip distances must be in their valid domains")
        if not basic_arena_valid:
            continue
        eq(h, 103, pp+".arena.fov_horizontal_deg_at_16_9", "reference_fov")
        require(arena["reference_aspect_ratio"] == [16, 9], pp+".arena.reference_aspect_ratio",
                "reference_aspect", "Reference aspect ratio is 16:9")
        eq(arena["floor_y_m"], 0, pp+".arena.floor_y_m", "reference_floor")
        eq(arena["wall_reference_distance_m"], 18, pp+".arena.wall_reference_distance_m", "reference_wall")
        eq(v, math.degrees(2*math.atan(math.tan(math.radians(h)/2)*ah/aw)),
           pp+".arena.fov_vertical_deg", "fov_relation")
        require(all(close(a, b) for a, b in zip(arena["eye_position_m"], (0, 1.6, 0))),
                pp+".arena.eye_position_m", "reference_eye", "Reference eye must be (0,1.6,0) m")
        require(arena["reference_look_yaw_pitch_deg"] == [0, 0] and close(arena["roll_deg"], 0),
                pp+".arena", "reference_orientation", "Reference camera has zero yaw, pitch and roll")
        aggregate_kind = ("descriptive_only" if program_id in ("EX01", "EX02", "EX03", "EX04")
                          else "sum_credited_switch_work_per_program_time" if program_id == "EX08"
                          else "time_weighted_contact")
        require(program["aggregate"]["kind"] == aggregate_kind,
                pp+".aggregate.kind", "aggregate_kind", "Aggregate is inconsistent with the program")
        elapsed = 0.0
        for fi, phase in enumerate(program["phases"]):
            path = f"{pp}.phases[{fi}]"
            tag = f"{program_id}/{program['difficulty']}/{phase['id']}"
            eq(phase["start_s"], elapsed, path+".start_s", "phase_contiguity")
            elapsed += phase["duration_s"]
            if fi < len(expected):
                phase_id, duration, mechanic, motion_kind = expected[fi]
                require((phase["id"], phase["mechanic"], phase["motion"]["kind"]) ==
                        (phase_id, mechanic, motion_kind), path, "phase_identity",
                        f"Expected {phase_id}/{mechanic}/{motion_kind} at this position")
                eq(phase["duration_s"], duration, path+".duration_s", "phase_duration")
            size, spawn, life = phase["size"], phase["spawn"], phase["lifecycle"]
            motion, score, env = phase["motion"], phase["scoring"], phase["envelope"]
            diameter, distance = phase["diameter_deg"], phase["distance_m"]
            require(0 < diameter < 180, path+".diameter_deg", "diameter_domain",
                    "Angular diameter must be strictly between 0 and 180 degrees")
            require(env["center_distance_m"][0] > 0 and distance > 0,
                    path+".envelope.center_distance_m", "distance_domain", "Target centres must be in front of the eye at positive radial distance")
            require(-89 < env["center_pitch_deg"][0] <= env["center_pitch_deg"][1] < 89,
                    path+".envelope.center_pitch_deg", "pitch_domain", "The supported reference envelope excludes poles")
            require(phase["target_count"] == spawn["target_slots"],
                    path+".target_count", "slot_count", "Target count and spawn slot capacity must agree")
            require(score["id"] == SCORE_IDS[phase["mechanic"]],
                    path+".scoring.id", "score_kind", "Score does not match the mechanic")
            require(phase["fire"]["mode"] == FIRE_MODES[phase["mechanic"]],
                    path+".fire.mode", "fire_kind", "Input mode does not match the mechanic")
            eq(score["phase_duration_s"], phase["duration_s"],
               path+".scoring.phase_duration_s", "score_duration")
            require(contained(spawn["yaw_deg"], env["center_yaw_deg"]) and
                    contained(spawn["pitch_deg"], env["center_pitch_deg"]),
                    path+".spawn", "spawn_envelope", "Spawn bounds must lie in the declared centre envelope")
            require(0 <= spawn["transition_angle_deg"][0] <= spawn["transition_angle_deg"][1] <= 180,
                    path+".spawn.transition_angle_deg", "transition_domain", "Geodesic transition angles must lie between 0 and 180 degrees")
            require(env["minimum_floor_clearance_m"] >= 0.05-1e-9,
                    path+".envelope.minimum_floor_clearance_m", "minimum_floor_requirement", "The reference profile requires at least 0.05 m full-sphere floor clearance")
            if "candidate_yaw_deg" in spawn:
                require(contained(spawn["candidate_yaw_deg"], spawn["yaw_deg"]),
                        path+".spawn.candidate_yaw_deg", "candidate_envelope", "Candidate yaw interval must lie inside the spawn domain")
            eq(size["reference_distance_m"], distance, path+".size.reference_distance_m", "reference_distance")
            if not (0 < diameter < 180 and env["center_distance_m"][0] > 0 and
                    -89 < env["center_pitch_deg"][0] <= env["center_pitch_deg"][1] < 89):
                continue
            eq(size["world_radius_m"], distance*math.sin(math.radians(diameter)/2),
               path+".size.world_radius_m", "sphere_radius")
            if size["mode"] == "world_radius_constant":
                dmin, dmax = env["center_distance_m"]
                radius = size["world_radius_m"]
                require(0 < radius < dmin, path+".size.world_radius_m", "sphere_eye_outside",
                        "The eye must remain strictly outside each target sphere")
                eq(size["reference_angular_diameter_deg"], diameter,
                   path+".size.reference_angular_diameter_deg", "reference_diameter")
                if 0 < radius < dmin:
                    eq(size["minimum_apparent_diameter_deg"], math.degrees(2*math.asin(radius/dmax)),
                       path+".size.minimum_apparent_diameter_deg", "apparent_diameter")
                    eq(size["maximum_apparent_diameter_deg"], math.degrees(2*math.asin(radius/dmin)),
                       path+".size.maximum_apparent_diameter_deg", "apparent_diameter")
            else:
                require(all(close(d, distance) for d in env["center_distance_m"]),
                        path+".envelope.center_distance_m", "fixed_distance", "This catalogue phase uses constant radial distance")
            certificate = {"phase": tag, **geometry_certificate(arena, phase)}
            certificates.append(certificate)
            require(certificate["minimum_floor_clearance_m"]+1e-9 >= env["minimum_floor_clearance_m"],
                    path+".envelope", "floor_clearance",
                    f"Conservative full-sphere clearance {certificate['minimum_floor_clearance_m']:.9g} m is below the minimum")
            require(min(certificate["frustum_plane_lower_bounds_m"].values()) >= -1e-9,
                    path+".envelope", "frustum_clearance", "Full-sphere envelope cannot be certified inside every reference frustum plane")
            require(certificate["minimum_wall_clearance_m"] >= 0,
                    path+".envelope", "wall_clearance", "Target envelope extends through the reference wall")
            maximum_diameter = max(diameter, size.get("diameter_start_deg", diameter),
                                   size.get("diameter_end_deg", diameter))
            gap = spawn["minimum_silhouette_gap_deg"]
            require(gap >= 0.75-1e-8, path+".spawn.minimum_silhouette_gap_deg", "silhouette_gap",
                    "Resolved V2 catalogue requires at least 0.75 degree silhouette clearance")
            if "minimum_equal_size_center_separation_deg" in spawn:
                require(spawn["minimum_equal_size_center_separation_deg"]+1e-8 >= maximum_diameter+gap,
                        path+".spawn.minimum_equal_size_center_separation_deg", "centre_separation",
                        "Centre separation must include both angular radii and the silhouette gap")
            if "transition_band_bag" in spawn:
                bag = spawn["transition_band_bag"]
                require(sum(b["copies"] for b in bag["bands"]) == bag["draw_count"],
                        path+".spawn.transition_band_bag", "bag_count", "Bag copies must sum to draw_count")
                last = spawn["transition_angle_deg"][0]
                for band in bag["bands"]:
                    eq(band["angle_deg"][0], last, path+".spawn.transition_band_bag", "bag_contiguity")
                    last = band["angle_deg"][1]
                eq(last, spawn["transition_angle_deg"][1], path+".spawn.transition_band_bag", "bag_coverage")

            if phase["mechanic"] == "opportunity":
                schedule = spawn["schedule"]
                eq(schedule["slots"]*schedule["slot_duration_s"], phase["duration_s"],
                   path+".spawn.schedule", "window_schedule_duration")
                require(schedule["onset_delay_uniform_s"][0] >= 0 and
                        schedule["onset_delay_uniform_s"][1]+life["ttl_s"] <= schedule["slot_duration_s"]+1e-8,
                        path+".spawn.schedule", "window_overflow", "Latest onset plus TTL must fit entirely inside its slot")
                eq(size["progress_duration_s"], life["ttl_s"], path+".size.progress_duration_s", "window_size_duration")
                eq(size["diameter_start_deg"], diameter, path+".size.diameter_start_deg", "window_start_size")
                ratio = 0.6 if size["shrink"] else 1.0
                eq(size["diameter_end_deg"], ratio*diameter, path+".size.diameter_end_deg", "shrink_ratio")
                if size["shrink"]:
                    eq(size["world_radius_end_m"], distance*math.sin(math.radians(size["diameter_end_deg"])/2),
                       path+".size.world_radius_end_m", "shrink_radius")
            if phase["mechanic"] == "switching":
                hp, dps = life["hp_max"], phase["fire"]["damage_per_s"]
                require(hp > 0 and dps > 0, path+".lifecycle", "switch_domain", "HP and damage rate must be positive")
                eq(dps, 100, path+".fire.damage_per_s", "damage_rate")
                eq(life["hp_regeneration_per_s"], 0, path+".lifecycle.hp_regeneration_per_s", "hp_regeneration")
                eq(score["hp_max"], hp, path+".scoring.hp_max", "score_hp")
                if hp > 0 and dps > 0:
                    eq(life["ideal_contact_time_to_kill_s"], hp/dps,
                       path+".lifecycle.ideal_contact_time_to_kill_s", "ideal_ttk")
            if phase["mechanic"] == "tracking":
                require(score["exposure_denominator"] ==
                        "full_scheduled_phase_duration_including_initial_acquisition_and_user_look_away" and
                        score["exposure_never_retimed"] is True and
                        score["exposure_stops_when_player_looks_away"] is False,
                        path+".scoring", "fixed_tracking_exposure",
                        "Exposure equals the full scheduled phase duration; first-render gating affects only contact numerator")
                motion_checks.append({"phase": tag, "check": "tracking_fixed_exposure",
                                      "exposure_s": phase["duration_s"], "first_rendered_frame_gates": "numerator_only"})
            if spawn["kind"] == "grid_without_overlap":
                nodes = spawn["nodes_yaw_pitch_deg"]
                require(len(nodes) == 9 and len({tuple(n) for n in nodes}) == 9,
                        path+".spawn.nodes_yaw_pitch_deg", "grid_nodes", "Nine unique grid nodes are required")
                for node in nodes:
                    require(contained([node[0], node[0]], env["center_yaw_deg"]) and
                            contained([node[1], node[1]], env["center_pitch_deg"]),
                            path+".spawn.nodes_yaw_pitch_deg", "grid_envelope", "Grid node lies outside the declared envelope")
                if len(nodes) > 1:
                    sep = min(angle_deg(direction(*nodes[i]), direction(*nodes[j]))
                              for i in range(len(nodes)) for j in range(i))
                    require(sep+1e-8 >= maximum_diameter+gap, path+".spawn.nodes_yaw_pitch_deg",
                            "grid_separation", "Grid silhouettes could overlap")
                    motion_checks.append({"phase": tag, "check": "grid_minimum_angular_separation_deg", "value": sep})
            if spawn["kind"] == "one_target_per_lane":
                lanes = motion["lanes_pitch_deg"]
                require(spawn["lane_pitch_deg"] == lanes and len(lanes) == phase["target_count"],
                        path+".spawn.lane_pitch_deg", "lane_identity", "One identical declared lane per target slot is required")
                amplitude = motion.get("vertical", {}).get("amplitude_deg", 0)
                require(contained([min(lanes)-amplitude, max(lanes)+amplitude], env["center_pitch_deg"]),
                        path+".motion", "lane_envelope", "Lane oscillation exceeds the pitch envelope")
                if len(lanes) > 1:
                    separation = min(abs(a-b) for i, a in enumerate(lanes) for b in lanes[:i])-2*amplitude
                    require(separation+1e-8 >= maximum_diameter+gap,
                            path+".motion.lanes_pitch_deg", "lane_separation", "Lane motion envelopes permit silhouette overlap")
                    motion_checks.append({"phase": tag, "check": "lane_minimum_angular_separation_deg", "value": separation})
            kind = motion["kind"]
            if "yaw_bounds_deg" in motion:
                require(contained(motion["yaw_bounds_deg"], env["center_yaw_deg"]),
                        path+".motion.yaw_bounds_deg", "motion_envelope", "Yaw trajectory bounds exceed the envelope")
            if kind in ("reactive_axis", "reactive_lanes"):
                vmin, vmax = motion["yaw_speed_abs_deg_s"]
                ramp, boundary, vertical = motion["velocity_transition"], motion["boundary"], motion["vertical"]
                mixture = motion["plateau_duration_mixture"]
                eq(sum(c["weight"] for c in mixture), 1, path+".motion.plateau_duration_mixture", "mixture_weights")
                require(all(c["weight"] > 0 and c["uniform_duration_s"][0] > 0 for c in mixture),
                        path+".motion.plateau_duration_mixture", "plateau_domain", "All mixture components need positive weight and duration")
                accel, nominal = ramp["acceleration_limit_deg_s2"], ramp["nominal_duration_s"]
                inset = boundary["trigger_inset_deg"]
                require(0 < vmin <= vmax and accel > 0 and nominal > 0 and vertical["period_s"] > 0,
                        path+".motion", "reactive_domain", "Reactive speeds, acceleration, ramp and vertical period must be positive")
                require(0 < inset < (motion["yaw_bounds_deg"][1]-motion["yaw_bounds_deg"][0])/2,
                        path+".motion.boundary.trigger_inset_deg", "brake_inset_domain", "Braking inset must fit inside the yaw interval")
                if 0 < vmin <= vmax and accel > 0 and nominal > 0 and vertical["period_s"] > 0:
                    stop = stopping_distance_upper_bound(vmax, vmin, nominal, accel)
                    require(stop <= inset+1e-8, path+".motion.boundary.trigger_inset_deg",
                            "braking_distance", f"Conservative outward excursion {stop:.9g} degrees exceeds inset")
                    upper = math.hypot(vmax, vertical["amplitude_deg"]*2*math.pi/vertical["period_s"])
                    eq(motion["nominal_full_angular_speed_upper_bound_deg_s"], upper,
                       path+".motion.nominal_full_angular_speed_upper_bound_deg_s", "reactive_speed_bound")
                    motion_checks.append({"phase": tag, "check": "reactive_conservative_braking_distance_deg",
                                          "upper_bound": stop, "available_inset": inset})
                if kind == "reactive_lanes":
                    expected_candidates = [motion["yaw_bounds_deg"][0]+inset, motion["yaw_bounds_deg"][1]-inset]
                    require(all(close(a, b) for a, b in zip(spawn["candidate_yaw_deg"], expected_candidates)),
                            path+".spawn.candidate_yaw_deg", "reactive_spawn_thresholds", "Initial candidate domain must lie inside both soft-turn thresholds")
                require(motion["event_tape"]["horizon_s"] >= phase["duration_s"],
                        path+".motion.event_tape.horizon_s", "event_horizon", "Precompiled event tape must cover the phase")
            elif kind == "sinusoid_axis":
                a, omega = motion["amplitude_deg"], motion["omega_rad_s"]
                require(a > 0 and omega > 0, path+".motion", "sinusoid_domain", "Sine amplitude and omega must be positive")
                if a > 0 and omega > 0:
                    eq(motion["peak_angular_speed_deg_s"], a*omega, path+".motion.peak_angular_speed_deg_s", "sinusoid_speed")
                    eq(motion["peak_angular_acceleration_deg_s2"], a*omega*omega,
                       path+".motion.peak_angular_acceleration_deg_s2", "sinusoid_acceleration")
                    eq(motion["period_s"], 2*math.pi/omega, path+".motion.period_s", "sinusoid_period")
                bounds = env["center_yaw_deg" if motion["axis"] == "yaw" else "center_pitch_deg"]
                require(contained([-a, a], bounds), path+".motion.amplitude_deg", "sinusoid_envelope",
                        "Sine amplitude exceeds the envelope")
            elif kind == "linear_reflect" and motion["reflection"] == "symmetric_cubic_smoothstep_velocity":
                speed, duration = motion["yaw_speed_deg_s"], motion["turn_duration_s"]
                require(speed > 0 and duration > 0, path+".motion", "soft_reflect_domain", "Speed and turn duration must be positive")
                if speed > 0 and duration > 0:
                    inset = 5*speed*duration/16
                    straight = (motion["yaw_bounds_deg"][1]-motion["yaw_bounds_deg"][0]-2*inset)/speed
                    require(straight > 0, path+".motion", "soft_reflect_space", "Soft turns must leave a positive straight section")
                    eq(motion["turn_entry_inset_deg"], inset, path+".motion.turn_entry_inset_deg", "soft_reflect_inset")
                    eq(motion["straight_segment_duration_s"], straight, path+".motion.straight_segment_duration_s", "soft_reflect_straight")
                    eq(motion["period_s"], 2*straight+2*duration, path+".motion.period_s", "soft_reflect_period")
                    eq(motion["peak_yaw_acceleration_deg_s2"], 3*speed/duration,
                       path+".motion.peak_yaw_acceleration_deg_s2", "soft_reflect_acceleration")
            elif kind == "angular_bounce":
                height, flight = motion["apex_height_above_baseline_deg"], motion["flight_duration_s"]
                require(height > 0 and flight > 0, path+".motion", "bounce_domain", "Arc height and flight duration must be positive")
                if height > 0 and flight > 0:
                    eq(motion["launch_pitch_velocity_deg_s"], 4*height/flight,
                       path+".motion.launch_pitch_velocity_deg_s", "bounce_launch")
                    eq(motion["pitch_acceleration_deg_s2"], -8*height/flight**2,
                       path+".motion.pitch_acceleration_deg_s2", "bounce_gravity")
                    require(close(motion["initial_flight_age_uniform_s"][0], 0) and
                            close(motion["initial_flight_age_uniform_s"][1], flight),
                            path+".motion.initial_flight_age_uniform_s", "bounce_initial_age", "Initial age interval must match the flight interval")
                chambers = motion["chambers"]
                require(chambers == spawn["chambers"] and len(chambers) == phase["target_count"] and
                        sorted(c["slot"] for c in chambers) == list(range(int(phase["target_count"]))),
                        path+".motion.chambers", "chamber_identity", "Spawn and motion require one matching chamber per slot")
                for chamber in chambers:
                    require(contained(chamber["yaw_deg"], env["center_yaw_deg"]) and
                            contained([chamber["baseline_pitch_deg"], chamber["baseline_pitch_deg"]+height], env["center_pitch_deg"]),
                            path+".motion.chambers", "chamber_envelope", "Chamber arc exceeds the declared envelope")
                    max_pitch = max(abs(chamber["baseline_pitch_deg"]), abs(chamber["baseline_pitch_deg"]+height))
                    width = chamber["yaw_deg"][1]-chamber["yaw_deg"][0]
                    worst_endpoint = math.degrees(2*math.asin(math.cos(math.radians(max_pitch))*math.sin(math.radians(width/2)/2)))
                    require(worst_endpoint+1e-8 >= spawn["transition_angle_deg"][0],
                            path+".spawn.transition_angle_deg", "chamber_respawn_feasibility",
                            "Even a chamber-centred prior target must leave a valid endpoint respawn")
                ordered = sorted(chambers, key=lambda c: c["yaw_deg"][0])
                max_pitch = max(abs(x) for x in env["center_pitch_deg"])
                for left, right in zip(ordered, ordered[1:]):
                    yaw_gap = right["yaw_deg"][0]-left["yaw_deg"][1]
                    require(yaw_gap >= 0, path+".motion.chambers", "chamber_overlap", "Chamber yaw intervals overlap")
                    if yaw_gap >= 0:
                        angular_gap = math.degrees(2*math.asin(math.cos(math.radians(max_pitch))*math.sin(math.radians(yaw_gap)/2)))
                        require(angular_gap+1e-8 >= maximum_diameter+gap,
                                path+".motion.chambers", "chamber_separation", "Chamber silhouettes could overlap")
                require(motion["event_tape_horizon_s"] >= phase["duration_s"],
                        path+".motion.event_tape_horizon_s", "event_horizon", "Bounce event tape must cover the phase")
            elif kind == "depth_sines":
                centre, amplitude, omega = motion["distance_center_m"], motion["distance_amplitude_m"], motion["distance_omega_rad_s"]
                require(centre > amplitude >= 0 and omega > 0,
                        path+".motion", "depth_domain", "Depth centre must exceed amplitude and omega must be positive")
                require(all(close(a, b) for a, b in zip(env["center_distance_m"], [centre-amplitude, centre+amplitude])),
                        path+".envelope.center_distance_m", "depth_envelope", "Depth envelope must match centre plus/minus amplitude")
                for axis in ("yaw", "pitch"):
                    require(contained([-motion[f"{axis}_amplitude_deg"], motion[f"{axis}_amplitude_deg"]], env[f"center_{axis}_deg"]),
                            path+".motion", "depth_angular_envelope", "Angular oscillation exceeds the envelope")
                eq(motion["angular_speed_upper_bound_deg_s"],
                   math.hypot(motion["yaw_amplitude_deg"]*motion["yaw_omega_rad_s"],
                              motion["pitch_amplitude_deg"]*motion["pitch_omega_rad_s"]),
                   path+".motion.angular_speed_upper_bound_deg_s", "depth_angular_speed")
                eq(motion["radial_speed_max_m_s"], amplitude*omega, path+".motion.radial_speed_max_m_s", "depth_radial_speed")
                eq(motion["radial_acceleration_max_m_s2"], amplitude*omega*omega,
                   path+".motion.radial_acceleration_max_m_s2", "depth_radial_acceleration")
                require(size["mode"] == "world_radius_constant" and motion["no_screen_size_compensation"],
                        path+".size.mode", "depth_size_mode", "Depth phase must preserve physical radius")
            elif kind == "angular_ellipse":
                for axis in ("yaw", "pitch"):
                    amplitude = motion[f"{axis}_amplitude_deg"]
                    require(amplitude > 0 and contained([-amplitude, amplitude], env[f"center_{axis}_deg"]),
                            path+".motion", "ellipse_domain", "Ellipse amplitudes must be positive and inside the envelope")
                if motion["yaw_amplitude_deg"] > 0 and motion["pitch_amplitude_deg"] > 0:
                    peak = ellipse_peak_sample(motion)
                    require(peak <= motion["acceleration_validation_limit_deg_s2"]+1e-8,
                            path+".motion.acceleration_validation_limit_deg_s2", "ellipse_acceleration_sample",
                            "Sampled exact derivative exceeds the declared acceleration limit")
                    motion_checks.append({"phase": tag, "check": "ellipse_acceleration_exact_derivatives_sampled",
                                          "sample_count": 8192, "peak_deg_s2": peak,
                                          "limit_deg_s2": motion["acceleration_validation_limit_deg_s2"],
                                          "continuous_certificate": False})
        eq(elapsed, program["duration_s"], pp+".phases", "program_phase_total")
    metrics = {
        "configuration_count": len(programs),
        "phase_count": sum(len(p["phases"]) for p in programs),
        "geometry": certificates, "motion": motion_checks,
        "scope": {
            "geometry": "Conservative closed-form interval envelope at the neutral reference camera, including full target spheres; passing lower bounds certify the declared envelopes.",
            "movement": "Cross-field formulas and conservative reactive stopping bounds; ellipse acceleration uses an explicitly sampled numerical check.",
            "not_demonstrated": ["All random spawn histories", "Every runtime event-tape trajectory",
                                 "Godot rendering and input behavior", "Windows executable packaging",
                                 "Human playability or calibration validity"],
        },
    }
    if certificates:
        metrics["minimum_certified_floor_clearance_m"] = min(c["minimum_floor_clearance_m"] for c in certificates)
        metrics["minimum_certified_frustum_clearance_m"] = min(min(c["frustum_plane_lower_bounds_m"].values()) for c in certificates)
        metrics["minimum_certified_wall_clearance_m"] = min(c["minimum_wall_clearance_m"] for c in certificates)
    return errors, metrics


def validate_bytes(raw, schema):
    """Return a JSON-serializable result; programming errors are not reclassified as bad data."""
    try:
        catalogue = strict_loads(raw)
    except StrictJSONError as exc:
        return {"valid": False, "failed_stage": "strict_json",
                "errors": [issue("$", "strict_json", str(exc))], "metrics": None}, None
    structural = validate_structure(catalogue, schema)
    if structural:
        return {"valid": False, "failed_stage": "structure",
                "errors": structural, "metrics": None}, catalogue
    errors, metrics = validate_semantics(catalogue)
    return {"valid": not errors, "failed_stage": "semantics" if errors else None,
            "errors": errors, "metrics": metrics}, catalogue


def phase_at(catalogue, program_id, phase_id, difficulty="standard"):
    program = next(p for p in catalogue["programs"] if p["program_id"] == program_id and p["difficulty"] == difficulty)
    return next(p for p in program["phases"] if p["id"] == phase_id)


def negative_fixture_tests(base, schema):
    """Mutations of an independently valid fixture, with expected rejection stage and code.

    Full 320 kB catalogue copies are made only in memory. Each mutation is named
    and its relevant evidence is retained in the report, rather than shipping
    dozens of near-identical JSON files.
    """
    tests = []
    encoding_fixtures = [
        ("duplicate_key", b'{"a":1,"a":2}'),
        ("nan_literal", b'{"a":NaN}'),
        ("infinity_literal", b'{"a":Infinity}'),
        ("overflowing_exponent", b'{"a":1e9999}'),
        ("unsafe_integer", b'{"a":9007199254740992}'),
        ("trailing_comma", b'{"a":1,}'),
        ("invalid_utf8", b'{"a":"\xff"}'),
        ("lone_surrogate", b'{"a":"\\ud800"}'),
        ("utf8_bom", b'\xef\xbb\xbf{}'),
    ]
    for name, raw in encoding_fixtures:
        result, _ = validate_bytes(raw, schema)
        tests.append({"id": name, "expected_stage": "strict_json", "expected_code": "strict_json",
                      "passed": not result["valid"] and result["failed_stage"] == "strict_json",
                      "observed_stage": result["failed_stage"], "evidence": result["errors"][:2]})

    def mutate(name, stage, code, fn):
        candidate = copy.deepcopy(base)
        fn(candidate)
        raw = json.dumps(candidate, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
        result, _ = validate_bytes(raw, schema)
        matching = [error for error in result["errors"] if error["code"] == code]
        tests.append({"id": name, "expected_stage": stage, "expected_code": code,
                      "passed": not result["valid"] and result["failed_stage"] == stage and bool(matching),
                      "observed_stage": result["failed_stage"],
                      "evidence": matching[:2] or result["errors"][:3]})

    mutate("unknown_root_field", "structure", "additionalProperties",
           lambda c: c.update(unreviewed_runtime_override=True))
    mutate("missing_required_motion_field", "structure", "required",
           lambda c: phase_at(c, "EX04", "linear")["motion"].pop("yaw_speed_deg_s"))
    mutate("extra_field_on_static_discriminant", "structure", "additionalProperties",
           lambda c: phase_at(c, "EX01", "micro")["motion"].update(yaw_speed_deg_s=10))
    mutate("boolean_is_not_integer_count", "structure", "type",
           lambda c: phase_at(c, "EX01", "micro").update(target_count=True))
    mutate("unknown_motion_discriminant", "structure", "oneOf",
           lambda c: phase_at(c, "EX01", "micro")["motion"].update(kind="unversioned_teleport"))
    mutate("zero_ttl_is_not_inapplicable_null", "structure", "oneOf",
           lambda c: phase_at(c, "EX01", "micro")["lifecycle"].update(ttl_s=0))
    mutate("render_gate_removed", "structure", "const",
           lambda c: phase_at(c, "EX01", "micro")["lifecycle"].update(spawn_is_hittable_after="logical_birth"))
    mutate("runtime_debug_overlay_enabled", "structure", "const",
           lambda c: phase_at(c, "EX01", "micro")["visual"].update(runtime_debug_overlay=True))
    mutate("tracking_denominator_retimed", "structure", "const",
           lambda c: phase_at(c, "EX05", "horizontal")["scoring"].update(exposure_never_retimed=False))
    mutate("tracking_old_exposure_contract", "structure", "const",
           lambda c: phase_at(c, "EX05", "horizontal")["scoring"].update(
               exposure_denominator="scheduled_target_exposure_after_first_rendered_frame_including_user_look_away"))
    mutate("duplicate_program_difficulty", "semantics", "duplicate_configuration",
           lambda c: c["programs"][1].update(difficulty=c["programs"][0]["difficulty"]))
    mutate("overlapping_phase_timestamps", "semantics", "phase_contiguity",
           lambda c: phase_at(c, "EX01", "general").update(start_s=19))
    mutate("wrong_program_total", "semantics", "program_phase_total",
           lambda c: phase_at(c, "EX01", "amplitude").update(duration_s=19))
    mutate("reversed_spawn_interval", "semantics", "range_order",
           lambda c: phase_at(c, "EX01", "micro")["spawn"].update(yaw_deg=[6, -6]))
    mutate("incoherent_vertical_fov", "semantics", "fov_relation",
           lambda c: c["programs"][0]["arena"].update(fov_vertical_deg=60))

    def bad_envelope(c, axis, values):
        phase = phase_at(c, "EX01", "micro")
        phase["envelope"][f"center_{axis}_deg"] = values
        phase["spawn"][f"{axis}_deg"] = values
    mutate("sphere_floor_intersection", "semantics", "floor_clearance",
           lambda c: bad_envelope(c, "pitch", [-40, -30]))
    mutate("sphere_outside_reference_frustum", "semantics", "frustum_clearance",
           lambda c: bad_envelope(c, "yaw", [60, 75]))
    mutate("radius_uses_wrong_projection_formula", "semantics", "sphere_radius",
           lambda c: phase_at(c, "EX01", "micro")["size"].update(world_radius_m=0.09))
    mutate("window_extends_past_next_slot", "semantics", "window_overflow",
           lambda c: phase_at(c, "EX03", "fixed_window")["lifecycle"].update(ttl_s=2.5))
    mutate("shrink_end_ratio_wrong", "semantics", "shrink_ratio",
           lambda c: phase_at(c, "EX03", "shrinking_window")["size"].update(diameter_end_deg=1.9))
    mutate("grid_duplicate_node", "semantics", "grid_nodes",
           lambda c: phase_at(c, "EX02", "grid")["spawn"]["nodes_yaw_pitch_deg"].__setitem__(1, [-10, -7]))
    mutate("precision_separation_omits_radii", "semantics", "centre_separation",
           lambda c: phase_at(c, "EX02", "precision")["spawn"].update(minimum_equal_size_center_separation_deg=0.75))
    mutate("negative_geodesic_transition", "semantics", "transition_domain",
           lambda c: phase_at(c, "EX01", "micro")["spawn"].update(transition_angle_deg=[-1, 6]))
    mutate("negative_floor_requirement_cannot_bypass_clearance", "semantics", "minimum_floor_requirement",
           lambda c: phase_at(c, "EX01", "micro")["envelope"].update(minimum_floor_clearance_m=-1))
    mutate("candidate_yaw_exceeds_spawn_domain", "semantics", "candidate_envelope",
           lambda c: phase_at(c, "EX04", "linear")["spawn"].update(candidate_yaw_deg=[-30, 30]))

    def collapsed_lanes(c):
        phase = phase_at(c, "EX04", "evasive")
        phase["spawn"]["lane_pitch_deg"] = [-3, -1, 1, 3]
        phase["motion"]["lanes_pitch_deg"] = [-3, -1, 1, 3]
    mutate("moving_lanes_can_overlap", "semantics", "lane_separation", collapsed_lanes)

    def overlapping_chambers(c):
        phase = phase_at(c, "EX04", "arcs")
        phase["motion"]["chambers"][1]["yaw_deg"][0] = -15
        phase["spawn"]["chambers"][1]["yaw_deg"][0] = -15
    mutate("arc_chambers_overlap", "semantics", "chamber_overlap", overlapping_chambers)
    mutate("impossible_chamber_respawn_minimum", "semantics", "chamber_respawn_feasibility",
           lambda c: phase_at(c, "EX04", "arcs")["spawn"].update(transition_angle_deg=[4, 180]))
    mutate("reactive_mixture_not_normalized", "semantics", "mixture_weights",
           lambda c: phase_at(c, "EX06", "reactive")["motion"]["plateau_duration_mixture"][0].update(weight=0.6))
    mutate("insufficient_reactive_braking_room", "semantics", "braking_distance",
           lambda c: phase_at(c, "EX06", "reactive")["motion"]["boundary"].update(trigger_inset_deg=0.1))
    mutate("reactive_speed_bound_ignores_vertical", "semantics", "reactive_speed_bound",
           lambda c: phase_at(c, "EX04", "evasive")["motion"].update(nominal_full_angular_speed_upper_bound_deg_s=12))
    mutate("event_tape_too_short", "semantics", "event_horizon",
           lambda c: phase_at(c, "EX06", "reactive")["motion"]["event_tape"].update(horizon_s=10))
    mutate("sine_omega_wrong", "semantics", "sinusoid_speed",
           lambda c: phase_at(c, "EX05", "horizontal")["motion"].update(omega_rad_s=2))
    mutate("soft_turn_wrong_inset", "semantics", "soft_reflect_inset",
           lambda c: phase_at(c, "EX08", "mobile")["motion"].update(turn_entry_inset_deg=0.1))
    mutate("bounce_wrong_gravity", "semantics", "bounce_gravity",
           lambda c: phase_at(c, "EX04", "arcs")["motion"].update(pitch_acceleration_deg_s2=-9.81))
    mutate("ellipse_acceleration_limit_exceeded", "semantics", "ellipse_acceleration_sample",
           lambda c: phase_at(c, "EX05", "ellipse")["motion"].update(acceleration_validation_limit_deg_s2=1))
    mutate("switch_ttk_wrong", "semantics", "ideal_ttk",
           lambda c: phase_at(c, "EX08", "static")["lifecycle"].update(ideal_contact_time_to_kill_s=0.2))
    mutate("depth_envelope_does_not_cover_motion", "semantics", "depth_envelope",
           lambda c: phase_at(c, "EX07", "depth")["envelope"].update(center_distance_m=[4, 4]))

    # Acceptances guard against over-restricting valid JSON number semantics and
    # against falsely treating whitespace or object-key order as mechanics.
    positive = []
    for name, raw in (
        ("baseline", json.dumps(base, ensure_ascii=False, allow_nan=False).encode("utf-8")),
        ("object_key_order_and_whitespace", json.dumps(base, sort_keys=True, indent=1,
                                                      ensure_ascii=False, allow_nan=False).encode("utf-8")),
    ):
        result, _ = validate_bytes(raw, schema)
        positive.append({"id": name, "passed": result["valid"], "errors": result["errors"][:3]})
    floats = copy.deepcopy(base)
    for program in floats["programs"]:
        for phase in program["phases"]:
            phase["target_count"] = float(phase["target_count"])
            phase["spawn"]["target_slots"] = float(phase["spawn"]["target_slots"])
            if "chambers" in phase["motion"]:
                for chamber in phase["motion"]["chambers"]:
                    chamber["slot"] = float(chamber["slot"])
                for chamber in phase["spawn"]["chambers"]:
                    chamber["slot"] = float(chamber["slot"])
    result, _ = validate_bytes(json.dumps(floats, allow_nan=False).encode(), schema)
    positive.append({"id": "integral_numbers_may_use_decimal_json_notation",
                     "passed": result["valid"], "errors": result["errors"][:3]})
    # A future keyword cannot be silently ignored by this subset validator.
    unsupported = copy.deepcopy(schema)
    unsupported["unevaluatedProperties"] = False
    try:
        check_schema_subset(unsupported)
        keyword_rejected = False
    except ValueError:
        keyword_rejected = True
    positive.append({"id": "unsupported_schema_keyword_fails_closed", "passed": keyword_rejected})
    return {
        "negative_count": len(tests),
        "negative_passed": sum(test["passed"] for test in tests),
        "positive_count": len(positive),
        "positive_passed": sum(test["passed"] for test in positive),
        "all_passed": all(test["passed"] for test in tests+positive),
        "negative_fixtures": tests, "positive_fixtures": positive,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalogue", nargs="?", type=Path, default=DEFAULT_CATALOGUE)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--self-test", action="store_true",
                        help="Also verify valid variants and meaningful invalid mutations")
    parser.add_argument("--report", type=Path, help="Write the full reproducible JSON report")
    args = parser.parse_args(argv)
    raw = args.catalogue.read_bytes()
    schema_raw = args.schema.read_bytes()
    schema = strict_loads(schema_raw)
    check_schema_subset(schema)
    result, parsed = validate_bytes(raw, schema)
    report = {
        "report_version": "aimlocal.catalogue.validation.v1",
        "validator": "valider_catalogue.py",
        "schema_dialect": "https://json-schema.org/draft/2020-12/schema",
        "schema_validator_scope": "Only the explicitly listed subset used by the delivered frozen schema; not a general JSON Schema implementation.",
        "supported_schema_keywords": sorted(SUPPORTED_SCHEMA_KEYWORDS),
        "catalogue_file_sha256": hashlib.sha256(raw).hexdigest(),
        "schema_file_sha256": hashlib.sha256(schema_raw).hexdigest(),
        "validator_file_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        **result,
    }
    if parsed is not None:
        from empreintes_reference import VERSION, semantic_sha256
        report["semantic_hash_contract"] = VERSION
        report["catalogue_semantic_sha256"] = semantic_sha256(parsed)
    if args.self_test and result["valid"]:
        report["self_tests"] = negative_fixture_tests(parsed, schema)
    elif args.self_test:
        report["self_tests"] = {"skipped": "Baseline catalogue is invalid; mutation tests require a valid baseline."}
    success = result["valid"] and report.get("self_tests", {}).get("all_passed", True)
    report["success"] = success
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    summary = {
        "success": success, "catalogue_valid": result["valid"],
        "failed_stage": result["failed_stage"],
        "error_count": len(result["errors"]),
        "configurations": (result["metrics"] or {}).get("configuration_count"),
        "phases": (result["metrics"] or {}).get("phase_count"),
        "self_tests": {k: v for k, v in report.get("self_tests", {}).items()
                       if k not in ("negative_fixtures", "positive_fixtures")},
        "report": str(args.report) if args.report else None,
    }
    if not result["valid"]:
        summary["errors"] = result["errors"][:12]
    if report.get("self_tests", {}).get("all_passed") is False:
        summary["failed_self_tests"] = [x for group in ("negative_fixtures", "positive_fixtures")
                                       for x in report["self_tests"][group] if not x["passed"]]
    print(json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False))
    return 0 if success else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, StrictJSONError, ValueError) as exc:
        print(json.dumps({"success": False, "tool_error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)
