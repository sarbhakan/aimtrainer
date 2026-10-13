import argparse
import ast
import bisect
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys

sys.dont_write_bytecode = True


def encode_binary64(value):
    if isinstance(value, float):
        return "f64:" + struct.pack("<d", value).hex()
    if isinstance(value, dict):
        return {key: encode_binary64(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [encode_binary64(item) for item in value]
    return value


def load_reference(kit_root):
    sys.path.insert(0, str(kit_root / "outils"))
    import geometrie_reference
    import mouvements_reference

    catalogue = json.loads((kit_root / "donnees/catalogue.v2.json").read_text())
    source = kit_root / "outils/construire_visuels.py"
    syntax = ast.parse(source.read_text(), filename=str(source))
    definitions = [
        node for node in syntax.body
        if isinstance(node, ast.FunctionDef)
        and node.name in ("make_motion", "serialize_motion")
    ]
    if len(definitions) != 2:
        raise ValueError("REFERENCE_VISUAL_HELPERS_MISSING")
    namespace = dict(vars(geometrie_reference))
    namespace.update(vars(mouvements_reference))
    namespace["CAT"] = catalogue
    exec(compile(ast.Module(body=definitions, type_ignores=[]), str(source), "exec"), namespace)
    return geometrie_reference, mouvements_reference, catalogue, namespace


def motion_rates(reference, motion, time_s):
    definition = motion.m
    kind = motion.kind
    yaw_rate_deg_s = 0.0
    pitch_rate_deg_s = 0.0
    distance_rate_m_s = 0.0
    if kind in ("reactive_axis", "reactive_lanes"):
        yaw_rate_deg_s = reference.sample_reactive(motion.tape, time_s)[1]
        vertical = definition["vertical"]
        omega_rad_s = math.tau / vertical["period_s"]
        pitch_rate_deg_s = vertical["amplitude_deg"] * omega_rad_s * math.cos(
            math.tau * time_s / vertical["period_s"] + motion.phase
        )
    elif kind == "sinusoid_axis":
        rate_deg_s = definition["amplitude_deg"] * definition["omega_rad_s"] * math.cos(
            definition["omega_rad_s"] * time_s + motion.phase
        )
        if definition["axis"] == "yaw":
            yaw_rate_deg_s = rate_deg_s
        else:
            pitch_rate_deg_s = rate_deg_s
    elif kind == "depth_sines":
        yaw_rate_deg_s = definition["yaw_amplitude_deg"] * definition["yaw_omega_rad_s"] * math.cos(
            definition["yaw_omega_rad_s"] * time_s + motion.phases[0]
        )
        pitch_rate_deg_s = definition["pitch_amplitude_deg"] * definition["pitch_omega_rad_s"] * math.cos(
            definition["pitch_omega_rad_s"] * time_s + motion.phases[1]
        )
        distance_rate_m_s = definition["distance_amplitude_m"] * definition["distance_omega_rad_s"] * math.cos(
            definition["distance_omega_rad_s"] * time_s + motion.phases[2]
        )
    elif kind == "angular_ellipse":
        parameter_rad = motion.ellipse.parameter(
            motion.arc0 + motion.sign * math.radians(definition["path_angular_speed_deg_s"]) * time_s
        )
        parameter_rate_rad_s = (
            motion.sign * math.radians(definition["path_angular_speed_deg_s"])
            / motion.ellipse.metric(parameter_rad)
        )
        yaw_rate_deg_s = -definition["yaw_amplitude_deg"] * math.sin(parameter_rad) * parameter_rate_rad_s
        pitch_rate_deg_s = definition["pitch_amplitude_deg"] * math.cos(parameter_rad) * parameter_rate_rad_s
    elif kind == "linear_reflect":
        lower_deg, upper_deg = definition["yaw_bounds_deg"]
        speed_deg_s = definition["yaw_speed_deg_s"]
        if definition["reflection"] == "instantaneous_velocity_sign_change":
            yaw_rate_deg_s = reference.reflected(
                motion.x0, motion.sign * speed_deg_s, time_s, lower_deg, upper_deg
            )[1]
        else:
            straight_s = definition["straight_segment_duration_s"]
            turn_s = definition["turn_duration_s"]
            period_s = 2 * (straight_s + turn_s)
            cycle_s = (time_s + motion.cycle * period_s) % period_s
            if cycle_s < straight_s:
                yaw_rate_deg_s = speed_deg_s
            elif cycle_s < straight_s + turn_s:
                yaw_rate_deg_s = reference.signed_ramp(
                    speed_deg_s, -speed_deg_s, turn_s, cycle_s - straight_s
                )[0]
            elif cycle_s < 2 * straight_s + turn_s:
                yaw_rate_deg_s = -speed_deg_s
            else:
                yaw_rate_deg_s = reference.signed_ramp(
                    -speed_deg_s, speed_deg_s, turn_s, cycle_s - 2 * straight_s - turn_s
                )[0]
            if motion.sign < 0:
                yaw_rate_deg_s = -yaw_rate_deg_s
    elif kind == "angular_bounce":
        record = motion.bounces[min(
            len(motion.bounces) - 1,
            bisect.bisect_right([entry["end"] for entry in motion.bounces], time_s),
        )]
        chamber = definition["chambers"][motion.slot]
        elapsed_s = max(0, time_s - record["start"])
        yaw_rate_deg_s = reference.reflected(
            record["x"], record["v"], elapsed_s, *chamber["yaw_deg"]
        )[1]
        age_s = record["age"] + elapsed_s
        if record["flight"] and 0 <= age_s <= definition["flight_duration_s"]:
            fraction = max(0, min(1, age_s / definition["flight_duration_s"]))
            pitch_rate_deg_s = (
                4 * definition["apex_height_above_baseline_deg"] * (1 - 2 * fraction)
                / definition["flight_duration_s"]
            )
    return yaw_rate_deg_s, pitch_rate_deg_s, distance_rate_m_s


def sample_times(reference, motion, horizon_s, validator_random):
    times_s = {0.0, horizon_s, -0.001, horizon_s + 0.001}
    times_s.update(validator_random.uniform(0, horizon_s) for draw_index in range(16))
    times_s.update(index / 6 for index in range(13) if index / 6 <= horizon_s)
    boundaries_s = []
    if hasattr(motion, "tape"):
        for piece in motion.tape["pieces"]:
            boundaries_s.append(piece["to_s"])
            times_s.add((piece["from_s"] + piece["to_s"]) / 2)
            zero_s = reference._velocity_zero(piece, piece["from_s"], piece["to_s"])
            if zero_s is not None:
                times_s.add(zero_s)
    elif hasattr(motion, "bounces"):
        lower_deg, upper_deg = motion.m["chambers"][motion.slot]["yaw_deg"]
        width_deg = upper_deg - lower_deg
        for record in motion.bounces:
            boundaries_s.append(record["end"])
            times_s.add((record["start"] + record["end"]) / 2)
            if record["flight"]:
                apex_s = record["start"] + motion.m["flight_duration_s"] / 2 - record["age"]
                if record["start"] <= apex_s <= record["end"]:
                    times_s.add(apex_s)
            initial_deg = record["x"] - lower_deg
            final_deg = initial_deg + record["v"] * (record["end"] - record["start"])
            for wall_index in range(math.floor(min(initial_deg, final_deg) / width_deg), math.ceil(max(initial_deg, final_deg) / width_deg) + 1):
                crossing_s = record["start"] + (wall_index * width_deg - initial_deg) / record["v"]
                if record["start"] <= crossing_s <= record["end"]:
                    boundaries_s.append(crossing_s)
    elif motion.kind == "linear_reflect":
        definition = motion.m
        if definition["reflection"] == "instantaneous_velocity_sign_change":
            lower_deg, upper_deg = definition["yaw_bounds_deg"]
            width_deg = upper_deg - lower_deg
            velocity_deg_s = motion.sign * definition["yaw_speed_deg_s"]
            for wall_index in range(-math.ceil(abs(velocity_deg_s) * horizon_s / width_deg) - 2, math.ceil(abs(velocity_deg_s) * horizon_s / width_deg) + 3):
                crossing_s = (wall_index * width_deg - (motion.x0 - lower_deg)) / velocity_deg_s
                if 0 <= crossing_s <= horizon_s:
                    boundaries_s.append(crossing_s)
        else:
            straight_s = definition["straight_segment_duration_s"]
            turn_s = definition["turn_duration_s"]
            period_s = 2 * (straight_s + turn_s)
            for cycle_index in range(-1, math.ceil(horizon_s / period_s) + 2):
                for offset_s in (0, straight_s, straight_s + turn_s / 2, straight_s + turn_s, 2 * straight_s + turn_s, 2 * straight_s + 1.5 * turn_s):
                    crossing_s = cycle_index * period_s + offset_s - motion.cycle * period_s
                    if 0 <= crossing_s <= horizon_s:
                        boundaries_s.append(crossing_s)
    elif motion.kind == "angular_ellipse":
        speed_rad_s = motion.sign * math.radians(motion.m["path_angular_speed_deg_s"])
        for cell_index in range(0, motion.ellipse.n + 1, max(1, motion.ellipse.n // 32)):
            crossing_s = (motion.ellipse.prefix[cell_index] - motion.arc0) / speed_rad_s
            if 0 <= crossing_s <= horizon_s:
                boundaries_s.append(crossing_s)
    for boundary_s in boundaries_s:
        if 0 <= boundary_s <= horizon_s:
            times_s.update((max(0, boundary_s - 0.00000025), boundary_s, min(horizon_s, boundary_s + 0.00000025)))
    return sorted(times_s)


def motion_case(reference, helpers, definition, seed, slot, horizon_s, validator_random, label, origin=None, cycle=None, instance=None, check_default=False):
    motion = instance or reference.Motion(
        definition, seed, slot, horizon_s,
        initial_yaw_deg=origin[0] if origin and definition["kind"] != "static" else None,
    )
    if cycle is not None:
        motion.cycle = cycle
    samples = []
    for time_s in sample_times(reference, motion, horizon_s, validator_random):
        yaw_deg, pitch_deg, distance_m = motion.sample(time_s)
        if origin and motion.kind == "static":
            yaw_deg, pitch_deg = origin
        yaw_rate_deg_s, pitch_rate_deg_s, distance_rate_m_s = motion_rates(reference, motion, time_s)
        samples.append({"time_s": time_s, "expected": {
            "yaw_deg": yaw_deg, "pitch_deg": pitch_deg,
            "distance_m": distance_m if distance_m is not None else definition.get("distance_m", 4.0),
            "yaw_rate_deg_s": yaw_rate_deg_s, "pitch_rate_deg_s": pitch_rate_deg_s,
            "distance_rate_m_s": distance_rate_m_s,
        }})
    return {
        "label": label, "motion": definition, "seed": seed, "slot": slot,
        "horizon_s": horizon_s, "origin": origin, "cycle": cycle,
        "default_build": check_default, "state": helpers["serialize_motion"](motion),
        "samples": samples,
    }


def reactive_case(reference, definition, seed, horizon_s, validator_random, label, initial_yaw_deg=None):
    tape = reference.compile_reactive(definition, seed, horizon_s, initial_yaw_deg)
    motion = reference.Motion.__new__(reference.Motion)
    motion.tape = tape
    samples = [{"time_s": time_s, "expected": reference.sample_reactive(tape, time_s)}
               for time_s in sample_times(reference, motion, horizon_s, validator_random)]
    return {"label": label, "motion": definition, "seed": seed, "horizon_s": horizon_s,
            "initial_yaw_deg": initial_yaw_deg, "tape": tape, "samples": samples}


def reactive_coverage(cases):
    coverage = {"preempted_ramps": 0, "rearms_inside_ramps": 0,
                "rearm_and_control_end": 0, "outward_threshold_starts": 0,
                "boundary_rounding_before_root": 0}
    for case in cases:
        tape = case["tape"]
        definition = case["motion"]
        pieces = tape["pieces"]
        by_end_us = {round(piece["to_s"] * 1e6): index for index, piece in enumerate(pieces)}
        for event in tape["events"]:
            kind = event["kind"]
            if kind == "rearm_and_control_end":
                coverage["rearm_and_control_end"] += 1
            if event["time_us"] == 0 and kind.startswith("boundary_"):
                coverage["outward_threshold_starts"] += 1
            if kind == "boundary_left" and event["yaw_deg"] > definition["yaw_bounds_deg"][0] + definition["boundary"]["trigger_inset_deg"]:
                coverage["boundary_rounding_before_root"] += 1
            elif kind == "boundary_right" and event["yaw_deg"] < definition["yaw_bounds_deg"][1] - definition["boundary"]["trigger_inset_deg"]:
                coverage["boundary_rounding_before_root"] += 1
            index = by_end_us.get(event["time_us"])
            if index is None:
                continue
            piece = pieces[index]
            if piece["shape"] == "ramp" and piece["to_s"] < piece["origin_s"] + piece["duration_s"] - 1e-6:
                if kind.startswith("boundary_"):
                    coverage["preempted_ramps"] += 1
                elif kind == "rearm":
                    coverage["rearms_inside_ramps"] += 1
    return coverage


def generate(kit_root, seed_count, master_seed):
    geometry, reference, catalogue, helpers = load_reference(kit_root)
    validator_random = random.Random(master_seed)
    seeds = [0, 1, 42, 0xffffffff]
    seeds.extend(validator_random.randrange(2, 0xffffffff) for draw_index in range(seed_count))
    cases = []
    reactive_cases = []
    kinds = set()
    levels = set()
    phase_count = 0
    wall_landing_ties = 0
    soft_cycle_fractions = 0
    for program in catalogue["programs"]:
        levels.add(program["difficulty"])
        for phase in program["phases"]:
            phase_count += 1
            definition = phase["motion"]
            kind = definition["kind"]
            kinds.add(kind)
            label = "/".join((program["program_id"], program["difficulty"], phase["id"]))
            horizon_s = phase["duration_s"]
            static_positions = reference.static_layout(catalogue, program, phase) if kind == "static" else None
            for slot in range(phase["target_count"]):
                instance = helpers["make_motion"](program, phase, slot)
                origin = list(static_positions[slot]) if static_positions else None
                cycle = instance.cycle if kind == "linear_reflect" and definition["reflection"] != "instantaneous_velocity_sign_change" else None
                if kind in ("reactive_axis", "reactive_lanes", "angular_bounce") or (kind == "linear_reflect" and cycle is None):
                    origin = list(instance.sample(0)[:2])
                cases.append(motion_case(reference, helpers, definition, instance.seed, slot, horizon_s, validator_random, label + f"/atlas/slot={slot}", origin, cycle, instance))
            for seed_index, seed in enumerate(seeds):
                slot = seed_index % phase["target_count"]
                cases.append(motion_case(reference, helpers, definition, seed, slot, horizon_s, validator_random, label + f"/seed={seed}/slot={slot}"))
            if kind.startswith("reactive"):
                for seed in seeds:
                    reactive_cases.append(reactive_case(reference, definition, seed, 60.0, validator_random, label + f"/compile/seed={seed}"))
                inset_deg = definition["boundary"]["trigger_inset_deg"]
                for yaw_deg in (definition["yaw_bounds_deg"][0] + inset_deg, definition["yaw_bounds_deg"][1] - inset_deg):
                    for seed in (1, 2, 3, 4):
                        reactive_cases.append(reactive_case(reference, definition, seed, 60.0, validator_random, label + f"/threshold={yaw_deg}/seed={seed}", yaw_deg))
                        cases.append(motion_case(reference, helpers, definition, seed, 0, horizon_s, validator_random, label + f"/origin={yaw_deg}/seed={seed}", [yaw_deg, 0.0]))
                first_tape = reactive_cases[-1]["tape"]
                event_s = first_tape["events"][1]["time_us"] / 1e6
                reactive_cases.append(reactive_case(reference, definition, first_tape["seed_u32"], event_s, validator_random, label + "/horizon_at_event", reactive_cases[-1]["initial_yaw_deg"]))
            elif kind == "linear_reflect" and definition["reflection"] != "instantaneous_velocity_sign_change":
                for fraction in (0.0, 0.25, 0.5, 0.75, 4095 / 4096):
                    cases.append(motion_case(reference, helpers, definition, 42, 0, horizon_s, validator_random, label + f"/cycle={fraction}", cycle=fraction))
                    soft_cycle_fractions += 1
            elif kind == "angular_bounce":
                for slot in range(phase["target_count"]):
                    lower_deg, upper_deg = definition["chambers"][slot]["yaw_deg"]
                    for seed in (1, 2, 3, 4):
                        initial = reference.Motion(definition, seed, slot, horizon_s)
                        record = initial.bounces[0]
                        yaw_deg = (upper_deg if record["v"] > 0 else lower_deg) - record["v"] * record["end"]
                        if not lower_deg <= yaw_deg <= upper_deg:
                            continue
                        cases.append(motion_case(reference, helpers, definition, seed, slot, horizon_s, validator_random, label + f"/wall_landing/seed={seed}/slot={slot}", [yaw_deg, 0.0]))
                        wall_landing_ties += 1
            if kind != "static":
                cases.append(motion_case(reference, helpers, definition, 42, 0, 120.0, validator_random, label + "/default_horizon", check_default=True))
    coverage = reactive_coverage(reactive_cases)
    if any(coverage[field] == 0 for field in ("preempted_ramps", "rearms_inside_ramps", "rearm_and_control_end", "outward_threshold_starts")):
        raise ValueError("REACTIVE_EDGE_COVERAGE_INCOMPLETE:" + json.dumps(coverage))
    inputs = ["donnees/catalogue.v2.json", "outils/mouvements_reference.py",
              "outils/geometrie_reference.py", "outils/construire_visuels.py"]
    return {
        "oracle_version": "aimlocal.native_motion_oracle.v2.0",
        "float_encoding": "ieee754_binary64_little_endian_hex",
        "compiler_version": reference.COMPILER_VERSION,
        "catalogue_revision": catalogue["catalogue_revision"],
        "input_sha256": {name: hashlib.sha256((kit_root / name).read_bytes()).hexdigest() for name in inputs},
        "master_seed": master_seed, "random_seeds": seeds, "phase_count": phase_count,
        "kinds": sorted(kinds), "levels": sorted(levels), "coverage": coverage,
        "wall_landing_ties": wall_landing_ties, "soft_cycle_fractions": soft_cycle_fractions,
        "cases": cases, "reactive_cases": reactive_cases,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kit", type=Path, default=Path(__file__).resolve().parents[1] / "docs/reference/v2")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seeds", type=int, default=4)
    parser.add_argument("--master-seed", type=int, default=92221)
    arguments = parser.parse_args()
    if arguments.seeds < 1:
        parser.error("--seeds must be positive")
    fixture = generate(arguments.kit.resolve(), arguments.seeds, arguments.master_seed)
    arguments.output.write_text(json.dumps(encode_binary64(fixture), ensure_ascii=True, separators=(",", ":"), allow_nan=False) + "\n")
    print(json.dumps({"cases": len(fixture["cases"]), "reactive_tapes": len(fixture["reactive_cases"]),
                      "phase_count": fixture["phase_count"], "coverage": fixture["coverage"],
                      "wall_landing_ties": fixture["wall_landing_ties"], "output": str(arguments.output)}))


if __name__ == "__main__":
    main()
