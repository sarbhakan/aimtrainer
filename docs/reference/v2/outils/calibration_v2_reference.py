#!/usr/bin/env python3
"""AIM/LOCAL CAL V2: example plans, descriptive decision, and synthetic QA.

Standard library only. This is a reference calculator, not a Godot runtime and
not a claim of human or statistical validation. Run:
  python calibration_v2_reference.py build --output-dir ./cal_v2_generated
  python calibration_v2_reference.py check
  python calibration_v2_reference.py calculate measurements.json
  python calibration_v2_reference.py simulate --n 20000 --output simulation.json
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import struct
import sys
from functools import lru_cache

HERE = Path(__file__).resolve().parent
for _candidate_tools in (HERE, HERE.parent / "aim_local_v2" / "outils", HERE.parent / "outils"):
    if (_candidate_tools / "mouvements_reference.py").is_file():
        sys.path.insert(0, str(_candidate_tools))
        break
from mouvements_reference import compile_reactive, sample_reactive, COMPILER_VERSION
from empreintes_reference import semantic_sha256, strict_loads, VERSION as HASH_ENCODING

@lru_cache(maxsize=1)
def catalogue():
    candidates=(HERE.parent / "donnees" / "catalogue.v2.json",
                HERE.parent / "aim_local_v2" / "donnees" / "catalogue.v2.json",
                HERE / "catalogue_v2_resolu.json")
    for path in candidates:
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
    raise FileNotFoundError("Shared catalogue.v2.json required; do not invent a CAL-only reactive generator")

def reactive_motion(difficulty):
    for program in catalogue()["programs"]:
        if program["program_id"]=="EX06" and program["difficulty"]==difficulty:
            for phase in program["phases"]:
                if phase["id"]=="reactive":
                    return copy.deepcopy(phase["motion"])
    raise ValueError("SHARED_EX06_RESOURCE_NOT_FOUND")

PROTOCOL_ID = "sustained_blocks_v2"
TASKS = ("CLICK", "SMOOTH", "REACTIVE", "SWITCH")
TASK_IDS = {t: "CAL_" + t + "_R2" for t in TASKS}
DAY1_TASK_ORDER = ("CLICK", "SMOOTH", "SWITCH", "REACTIVE")
DAY2_TASK_ORDER = tuple(reversed(DAY1_TASK_ORDER))
OBJECTIVES = {
    "polyvalent": dict(zip(TASKS, (.25, .25, .25, .25))),
    "acquisition": dict(zip(TASKS, (.45, .15, .15, .25))),
    "tracking": dict(zip(TASKS, (.15, .30, .35, .20))),
}

def sha256(value):
    return semantic_sha256(value)

def f64(value):
    """A readable decimal and its exact IEEE-754 bits, not a rounded UI value."""
    return {"decimal_roundtrip": format(value, ".17g"),
            "ieee754_binary64_big_endian_hex": struct.pack(">d", value).hex()}

def seed_tuple(*parts):
    payload = json.dumps([str(p) for p in parts], separators=(",", ":"),
                         ensure_ascii=True).encode("ascii")
    h = hashlib.sha256(payload).digest()
    seed = int.from_bytes(h[:4], "big") or 0x6D2B79F5
    return seed, payload.decode("ascii"), h.hex()

class XorShift32:
    def __init__(self, seed):
        self.x = seed or 0x6D2B79F5
    def uint32(self):
        x = self.x
        x = (x ^ (x << 13)) & 0xFFFFFFFF
        x = (x ^ (x >> 17)) & 0xFFFFFFFF
        x = (x ^ (x << 5)) & 0xFFFFFFFF
        self.x = x
        return x
    def uniform(self, low=0., high=1.):
        return low + (high-low) * ((self.uint32()+.5)/4294967296.)
    def integer(self, n):
        if not isinstance(n, int) or n <= 0:
            raise ValueError("integer(n): n must be a positive integer")
        ceiling = (4294967296 // n) * n
        while True:
            x = self.uint32()
            if x < ceiling:
                return x % n
    def shuffle(self, values):
        for i in range(len(values)-1, 0, -1):
            j = self.integer(i+1)
            values[i], values[j] = values[j], values[i]

def protocol():
    return {
        "schema_version": "aimlocal.calibration.protocol.v2",
        "protocol_id": PROTOCOL_ID,
        "hash_encoding": HASH_ENCODING,
        "protocol_revision": "2026-10-12-v2.0",
        "design_status": "proposed_protocol_requires_engine_and_human_playtesting",
        "estimation_target": "performance_at_tested_gain_after_fixed_short_acclimation",
        "inference": {
            "method": "predeclared_conservative_descriptive_rules",
            "confirmation_days": 2,
            "periods_per_day": 4,
            "pair_contrasts_per_day": 2,
            "observation_unit": "day_composite_from_two_paired_contrasts",
            "confidence_interval": None,
            "probability_of_optimum": None,
            "statistical_equivalence_claim_allowed": False,
            "frames_targets_tasks_are_not_independent_replications": True,
            "long_term_adaptation_claim_allowed": False,
        },
        "candidate_grid": {
            "scale": "multiplicative_cm_per_360",
            "default_ratio": 1.25,
            "wide_exploration_ratio": 1.50,
            "technical_cm_bounds": [5., 150.],
            "max_challenger_cm_ratio_to_baseline_for_confirmation": 1.50,
            "max_relative_cm_jump_applies_after_quantization_in_express_grid": True,
            "candidate_limit_express": 3,
            "baseline_exact_applied_gain_preserved": True,
            "representability_resolved_before_measurement": True,
            "duplicate_effective_gains": "construction_error",
            "exponents_preference": [-1, 1, -2, 2, -3, 3],
            "finite_exponent_bounds": "ceil(log(5/c0)/log(q))..floor(log(150/c0)/log(q))",
            "cm_formula": "914.4/(declared_DPI*degrees_per_relative_input_unit)",
            "conversion_precision": "freeze_runtime_actual_gain_as_binary64_bits_and_decimal17",
            "automatic_parabolic_interpolation": False,
            "automatic_out_of_grid_recommendation": False,
        },
        "objectives": OBJECTIVES,
        "duration_s": {
            "preflight_baseline": 60,
            "acclimation_per_period": 60,
            "acclimation_per_task": 15,
            "countdown": 3,
            "scored_task": 24,
            "recovery_after_each_scored_task": 6,
            "period_constant_gain": 192,
            "scored_start_offsets_within_period": [63, 96, 129, 162],
            "express_interperiod_rest": 30,
            "confirmation_interperiod_rest": 60,
            "express_three_gains": 696,
            "express_two_gains": 474,
            "confirmation_per_day": 1008,
            "confirmation_two_days": 2016,
            "express_three_plus_confirmation": 2712,
            "confirmation_scored_total": 768,
            "express_scored_total_three_gains": 288,
            "duration_means_programmed_minimum_plus_recorded_waits": True,
        },
        "orders": {
            "express": "one_seeded_permutation_of_distinct_gains_frozen_before_scores",
            "confirmation_first_day": "ABBA_or_BAAB_one_seeded_fair_bit_before_scores",
            "confirmation_second_day": "opposite_sequence",
            "paired_period_indices_zero_based": [[0, 1], [2, 3]],
            "task_order_day_1": list(DAY1_TASK_ORDER),
            "task_order_day_2": list(DAY2_TASK_ORDER),
            "task_order_express": list(DAY1_TASK_ORDER),
            "gain_constant_during_acclimation_countdowns_scores_recoveries": True,
            "gain_retained_during_interperiod_rest": True,
            "adjacent_same_gain_periods_do_not_restore_baseline": True,
            "restore_baseline": ["session_end", "abort", "exception", "process_restart"],
        },
        "days_and_restarts": {
            "accepted_days_must_have_distinct_player_local_dates": True,
            "min_gap_between_accepted_session_starts_h": 12,
            "max_gap_between_accepted_session_starts_h": 168,
            "suggested_gap_h": 24,
            "first_confirmation_not_same_sitting_as_express": True,
            "min_gap_express_end_to_first_confirmation_start_h": 12,
            "max_scheduled_attempts_per_day_role": 2,
            "accepted_epoch": "first_technically_valid_complete_epoch_never_best_score",
            "retry_unit": "whole_day_role_all_four_periods_with_new_shared_decks",
            "retry_partial_cells_or_pair_only_allowed": False,
            "retry_on_low_performance_allowed": False,
            "retry_day_2_window_from_accepted_day_1_h": 168,
            "pause_during_scored_task": "invalidate_whole_day_epoch",
            "focus_or_capture_loss": "invalidate_whole_day_epoch",
            "long_unplanned_interruption_s": 900,
            "long_unplanned_interruption_action": "new_whole_day_epoch",
            "all_actual_waits_and_gains_recorded": True,
            "reported_budget_includes_retries_and_waits": True,
        },
        "quality": {
            "mean_fps_min": 55.,
            "frame_dt_p99_max_ms": 25.,
            "frame_dt_max_ms": 100.,
            "paired_median_fps_relative_difference_max": .10,
            "paired_relative_difference_formula": "(max-min)/((max+min)/2)",
            "mean_fps_formula": "frame_interval_count/sum(frame_dt_seconds)",
            "median_fps_formula": "1/median(frame_dt_seconds)",
            "quantile_definition": "nearest_rank_ceil_q_n_with_1_based_index",
            "invalidating_events": [
                "focus_loss", "capture_loss", "pause_during_score", "input_queue_overflow",
                "clock_discontinuity", "wrong_manifest_hash", "configuration_hash_change",
                "unresolved_integration_error", "fallback_spawn", "unknown_resource_revision"],
            "absence_of_mouse_motion_is_hardware_failure": False,
            "floor_mean_utility_exclusive": .10,
            "ceiling_mean_utility_exclusive": .95,
            "floor_ceiling_action": "undetermined_with_uninformative_task_reason",
            "fatigue_question": "optional_0_to_10_at_long_rest",
            "fatigue_offer_stop_at": 7,
            "fatigue_score_alone_invalidates_human_result": False,
        },
        "geometry": {
            "eye_position_m": [0., 1.6, 0.],
            "player_moves": False,
            "reference_yaw_pitch_deg": [0., 0.],
            "target_shape": "sphere",
            "decorative_back_wall_z_m": -18.,
            "distance_m": 4.,
            "radius_m_formula": "4*sin(angular_diameter_deg*pi/360)",
            "camera_recentering_between_opportunities": False,
            "pre_countdown_voluntary_alignment_max_error_deg": 1.,
            "preview_of_scored_targets_during_countdown": False,
        },
        "tasks": {
            "CLICK": {
                "id": TASK_IDS["CLICK"], "duration_s": 24., "slots": 16,
                "slot_s": 1.5, "onset_delay_s_inclusive_bounds": [.10, .25],
                "onset_delay_us_uniform_integer_inclusive": [100000,250000],
                "active_window_s": 1.20, "yaw_bounds_deg": [-25., 25.],
                "pitch_bounds_deg": [-12., 12.],
                "amplitude_bands_deg": [[4., 8.], [18., 30.]],
                "diameters_deg": {"novice": [1.6, 2.8], "standard": [1., 2.], "advanced": [.7, 1.4]},
                "balanced_size_amplitude_cells": 4, "opportunities_per_cell": 4,
                "reference_for_next_planned_position": "previous_planned_target_even_after_miss",
                "first_press_before_first_visible_frame": "premature_failure_consumes_opportunity",
                "first_press_after_visibility": "hit_or_miss_consumes_opportunity",
                "held_button_does_not_generate_new_press": True,
                "press_after_resolution": "extra_shot_diagnostic_only_until_next_slot",
                "press_after_deadline": "late_shot_diagnostic_only_until_next_slot",
                "no_press_before_deadline": "timeout_zero_utility",
                "utility": "mean((1-tau/1.20) if first_shot_success else 0)",
                "tau_origin": "logical_manifest_onset",
                "eligibility_gate": "first_render_of_visible_target",
                "onset_does_not_move_when_previous_opportunity_resolves": True,
            },
            "SMOOTH": {
                "id": TASK_IDS["SMOOTH"], "duration_s": 24., "pitch_deg": 0.,
                "amplitude_deg": 14.,
                "diameter_deg": {"novice": 3.4, "standard": 2.4, "advanced": 1.6},
                "max_speed_deg_s": {"novice": 12., "standard": 18., "advanced": 24.},
                "trajectory": "yaw=14*sin((max_speed/14)*t+phase)",
                "max_accel_deg_s2": {"novice": 144/14, "standard": 324/14, "advanced": 576/14},
                "click_required": False, "utility": "contact_time/24",
                "initial_acquisition_in_denominator": True,
                "first_render_contact_gate": True,
            },
            "REACTIVE": {
                "id": TASK_IDS["REACTIVE"], "duration_s": 24.,
                "shared_public_program": "EX06", "shared_public_phase": "reactive",
                "shared_motion_kind": "reactive_axis",
                "same_generator_required": True,
                "shared_compiler_version": COMPILER_VERSION,
                "shared_motion_sha256_by_difficulty": {d:sha256(reactive_motion(d)) for d in ("novice","standard","advanced")},
                "diameter_deg": {"novice": 3.4, "standard": 2.6, "advanced": 1.8},
                "yaw_bounds_deg": [-24., 24.], "pitch_deg": 0.,
                "speed_abs_deg_s": {"novice": [12., 18.], "standard": [18., 28.], "advanced": [26., 38.]},
                "plateau_mixture": {
                    "novice": [{"weight": 1., "duration_s": [.65, 1.30]}],
                    "standard": [{"weight": .7, "duration_s": [.70, 1.20]}, {"weight": .3, "duration_s": [.28, .45]}],
                    "advanced": [{"weight": .6, "duration_s": [.45, .90]}, {"weight": .4, "duration_s": [.20, .35]}]},
                "flip_probability": .7,
                "transition_nominal_s": {"novice": .18, "standard": .14, "advanced": .10},
                "accel_max_deg_s2": {"novice": 350., "standard": 700., "advanced": 1200.},
                "transition_duration_rule": "max(nominal,1.5*abs(v1-v0)/accel_max)",
                "boundary_trigger_yaw_deg": 21.,
                "boundary_action": "preempt_preserving_position_velocity_target_inward_latest_sampled_plateau_speed",
                "clamp_or_teleport_allowed": False,
                "utility": "contact_time/24", "first_render_contact_gate": True,
                "initial_acquisition_in_denominator": True,
            },
            "SWITCH": {
                "id": TASK_IDS["SWITCH"], "duration_s": 24., "slots": 12,
                "slot_s": 2., "onset_delay_s_inclusive_bounds": [.10, .25],
                "onset_delay_us_uniform_integer_inclusive": [100000,250000],
                "active_window_s": 1.70,
                "target_count": 3, "yaw_bounds_deg": [-23., 23.], "pitch_bounds_deg": [-10., 10.],
                "min_center_separation_deg": 10.,
                "priority_count_per_target": 4, "adjacent_identical_priority_allowed": False,
                "diameter_deg": {"novice": 3.4, "standard": 2.6, "advanced": 1.8},
                "hp": {"novice": 15., "standard": 20., "advanced": 30.},
                "damage_hp_s": 100.,
                "priority_hp_reset": "logical_onset",
                "damage_eligibility_gate": "first_render_of_new_priority",
                "maintain_button_across_slots_allowed": True,
                "early_button_press_invalidates_opportunity": False,
                "pre_onset_state": "all_positions_neutral_no_damage_no_future_priority_revealed",
                "kill_state": "priority_hidden_until_next_slot_other_positions_neutral",
                "deadline_state": "uncompleted_opportunity_zero_utility_positions_neutral",
                "utility": "mean(clamp((1.70-tau)/(1.70-hp/100),0,1) if killed else 0)",
                "tau_origin": "logical_manifest_onset",
            },
        },
        "randomization": {
            "generator": "xorshift32_v1",
            "uniform_float": "(next_uint32+0.5)/4294967296",
            "seed_bytes": "first_4_big_endian_SHA256",
            "zero_seed_replacement_hex": "6D2B79F5",
            "canonical_seed_input": "ASCII_JSON_array_no_whitespace",
            "calibration_tuple_fields": ["protocol_revision", "plan_seed_hex", "phase", "day_role", "pair", "epoch", "task", "domain"],
            "candidate_id_in_stimulus_seed": False,
            "performance_or_input_in_stimulus_seed": False,
            "scored_vs_warmup_domain_separated": True,
            "store_full_manifest_and_hash_not_seed_only": True,
        },
        "selection": {
            "challenger": "highest_complete_express_composite_nonbaseline",
            "challenger_score_tie_margin_pp": .25,
            "tie_break_1": "smallest_abs_log_effective_cm_ratio_to_baseline",
            "tie_break_2": "lexicographically_smallest_stable_candidate_id",
            "if_baseline_best": "keep_baseline_default_optional_comparison_of_best_alternative",
            "descriptive_candidate_envelope_max_score_gap_pp": 3.,
            "descriptive_candidate_envelope_max_task_loss_pp": 5.,
            "envelope_is_continuous_confidence_interval": False,
            "confirmation_data_include_express": False,
        },
        "decision": {
            "primary_margin_pp": 2., "per_task_guard_margin_pp": 5.,
            "close_observed_pair_abs_max_pp": 3.,
            "click_success_rate_loss_max": .05,
            "switch_completion_rate_loss_max_fraction": {"numerator": 1, "denominator": 12},
            "confirmation_counts_per_gain": {"CLICK": 64, "SWITCH": 48},
            "allowed_success_count_loss": {"CLICK": 3, "SWITCH": 4},
            "threshold_comparisons_use_unrounded_values": True,
            "tolerance_for_numeric_boundary_pp": 1e-9,
            "diagnostic_order_sensitive_pair_span_gt_pp": 6.,
            "priority": ["unstable_conditions", "incomplete", "exploratory_only",
                         "repeated_regression", "repeated_improvement", "mixed_tradeoff",
                         "close_observed", "undetermined"],
            "repeated_regression": "both_day_D<=-2 AND every_pair_C<0",
            "repeated_improvement": "both_day_D>=2 AND every_pair_C>0 AND every_day_task_E>=-5 AND raw_success_loss_guards_pass",
            "mixed_tradeoff": "global_improvement_pattern_with_failed_guard OR a_task_E>=5_both_days_and_another_task_E<=-5_both_days",
            "close_observed": "every_abs_day_D<=2 AND every_abs_pair_C<=3 AND every_abs_day_task_E<=5 AND bidirectional_raw_success_guards_pass",
            "uninformative_task_overrides_all_performance_rules": True,
            "default_action_except_repeated_improvement": "keep_original_setting",
            "application_is_explicit_and_undoable": True,
        },
    }

def make_gain(candidate_id, cm, dpi=800, applied_gain=None):
    g = float(applied_gain) if applied_gain is not None else 914.4/(dpi*cm)
    return {
        "candidate_id": candidate_id, "requested_cm_per_360": cm,
        "effective_cm_per_360": 914.4/(dpi*g), "declared_dpi": dpi,
        "degrees_per_relative_input_unit": f64(g),
        "runtime_gain_precision": "IEEE754_binary64",
        "cm_label_is_nominal_because_dpi_is_declared": True,
    }

@lru_cache(maxsize=1)
def protocol_hash():
    return sha256(protocol())

def require_protocol_snapshot(data):
    if data.get("protocol_sha256")!=protocol_hash():
        raise ValueError("MISSING_OR_INCOMPATIBLE_PROTOCOL_SNAPSHOT_HASH")

def verify_gains(gains, qa_allow_identical=False):
    ids, bits = set(), set()
    for g in gains:
        ident = g["candidate_id"]
        if ident in ids:
            raise ValueError("DUPLICATE_CANDIDATE_ID")
        ids.add(ident)
        value = float(g["degrees_per_relative_input_unit"]["decimal_roundtrip"])
        if not math.isfinite(value) or value <= 0 or g["declared_dpi"] <= 0:
            raise ValueError("INVALID_GAIN")
        bit = struct.pack(">d", value).hex()
        if bit != g["degrees_per_relative_input_unit"]["ieee754_binary64_big_endian_hex"]:
            raise ValueError("GAIN_DECIMAL_BITS_MISMATCH")
        if bit in bits and not qa_allow_identical:
            raise ValueError("DUPLICATE_EFFECTIVE_GAIN")
        bits.add(bit)
        actual_cm = 914.4/(g["declared_dpi"]*value)
        if abs(actual_cm-g["effective_cm_per_360"]) > 1e-10:
            raise ValueError("GAIN_CM_MISMATCH")
        if not 5 <= actual_cm <= 150:
            raise ValueError("GAIN_OUT_OF_SEARCH_BOUNDS")

def candidate_grid(baseline, ratio=1.25, representable_gain=None):
    """Freeze A exactly; construct up to two applicable distinct local gains.

    representable_gain(requested_gain) is supplied by the selected game/profile
    adapter. It returns the gain that will ACTUALLY be applied after quantization.
    Omitting it explicitly selects native binary64-gain storage, not a game export.
    Both the absolute search bounds and <=1.5 relative jump are checked again
    after representation. Near a bound the correct plan can contain just 2 gains.
    """
    if ratio not in (1.25,1.50):
        raise ValueError("UNDECLARED_GRID_RATIO")
    verify_gains([baseline])
    if baseline["candidate_id"]!="A":
        raise ValueError("BASELINE_ID_MUST_BE_A")
    c0=baseline["effective_cm_per_360"]
    dpi=baseline["declared_dpi"]
    jmin=math.ceil(math.log(5/c0)/math.log(ratio)-1e-12)
    jmax=math.floor(math.log(150/c0)/math.log(ratio)+1e-12)
    span=max(abs(jmin),abs(jmax))
    chosen=[copy.deepcopy(baseline)]
    known={baseline["degrees_per_relative_input_unit"]["ieee754_binary64_big_endian_hex"]}
    for mag in range(1,span+1):
        for j in (-mag,mag):
            if not jmin<=j<=jmax:
                continue
            requested=c0*ratio**j
            gain=914.4/(dpi*requested)
            applied=float(representable_gain(gain)) if representable_gain is not None else gain
            if not math.isfinite(applied) or applied<=0:
                raise ValueError("PROFILE_RETURNED_INVALID_EFFECTIVE_GAIN")
            cm=914.4/(dpi*applied)
            if not 5<=cm<=150 or max(cm/c0,c0/cm)>1.50+1e-12:
                continue
            bit=struct.pack(">d",applied).hex()
            if bit in known:
                continue
            ident="C_"+("m" if j<0 else "p")+str(abs(j))
            g=make_gain(ident,requested,dpi,applied)
            g["grid_exponent"]=j
            g["representation_adapter_applied"]=representable_gain is not None
            chosen.append(g);known.add(bit)
            if len(chosen)==3:
                return chosen
    if len(chosen)<2:
        raise ValueError("NO_DISTINCT_REPRESENTABLE_LOCAL_CHALLENGER")
    return chosen

def stream(plan_seed, phase, day, pair, epoch, task, domain):
    tup = ("2026-10-12-v2.0", plan_seed, phase, day, pair, epoch, task, domain)
    seed, encoded, full_hash = seed_tuple(*tup)
    return XorShift32(seed), {"uint32": seed, "tuple_canonical_json": encoded,
                              "sha256": full_hash, "generator": "xorshift32_v1"}

def direction(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    return (math.sin(y)*math.cos(p), math.sin(p), -math.cos(y)*math.cos(p))

def angles(v):
    return math.degrees(math.atan2(v[0], -v[2])), math.degrees(math.asin(max(-1., min(1., v[1]))))

def dot(a, b):
    return sum(x*y for x,y in zip(a,b))

def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])

def norm(v):
    m = math.sqrt(dot(v,v))
    return tuple(x/m for x in v)

def angle_between(a,b):
    return math.degrees(math.acos(max(-1., min(1., dot(a,b)))))

def click_layout(rng, difficulty):
    cells = [(size, amplitude) for size in range(2) for amplitude in range(2)]*4
    rng.shuffle(cells)
    diameters = protocol()["tasks"]["CLICK"]["diameters_deg"][difficulty]
    previous = direction(0.,0.)
    slots = []
    for i,(size,amp) in enumerate(cells):
        lo,hi = ((4.,8.),(18.,30.))[amp]
        # Uniform spherical area in the specified annulus, conditioned on bounds.
        e1 = norm(cross((0.,1.,0.), previous))
        e2 = norm(cross(previous,e1))
        for attempt in range(4096):
            cos_rho = rng.uniform(math.cos(math.radians(hi)), math.cos(math.radians(lo)))
            sin_rho = math.sqrt(max(0.,1-cos_rho*cos_rho))
            bearing = rng.uniform(0., 2*math.pi)
            v = tuple(cos_rho*previous[k] + sin_rho*(math.cos(bearing)*e1[k]+math.sin(bearing)*e2[k]) for k in range(3))
            yaw,pitch = angles(v)
            if -25 <= yaw <= 25 and -12 <= pitch <= 12:
                break
        else:
            raise ValueError("UNSATISFIABLE_CLICK_LAYOUT_NO_FALLBACK_ALLOWED")
        diameter = diameters[size]
        slots.append({"slot_index": i, "slot_start_s": i*1.5,
                      "slot_end_s": (i+1)*1.5, "diameter_deg": diameter,
                      "radius_m": 4*math.sin(math.radians(diameter/2)),
                      "distance_m": 4., "yaw_deg": yaw, "pitch_deg": pitch,
                      "planned_initial_amplitude_deg": angle_between(previous,v),
                      "amplitude_band_deg": [lo,hi],
                      "size_index": size, "amplitude_index": amp,
                      "planned_previous_direction": list(previous),
                      "direction": list(v), "position_draw_attempts": attempt+1})
        previous = v
    return slots

def switch_layout(rng, difficulty):
    positions=[]
    for i in range(3):
        for attempt in range(4096):
            # Uniform in spherical area under the rectangular yaw/pitch envelope.
            yaw=rng.uniform(-23.,23.)
            pitch=math.degrees(math.asin(rng.uniform(math.sin(math.radians(-10)),math.sin(math.radians(10)))))
            v=direction(yaw,pitch)
            if all(angle_between(v,tuple(p["direction"]))>=10 for p in positions):
                break
        else:
            raise ValueError("UNSATISFIABLE_SWITCH_LAYOUT_NO_FALLBACK_ALLOWED")
        diameter=protocol()["tasks"]["SWITCH"]["diameter_deg"][difficulty]
        positions.append({"target_id": i,"yaw_deg":yaw,"pitch_deg":pitch,
                          "direction":list(v),"distance_m":4.,"diameter_deg":diameter,
                          "radius_m":4*math.sin(math.radians(diameter/2))})
    # Rejection from uniformly shuffled multiset. Do not repair by adaptive inputs.
    for _ in range(4096):
        priorities=[0,1,2]*4
        rng.shuffle(priorities)
        if all(a!=b for a,b in zip(priorities,priorities[1:])):
            break
    else:
        raise ValueError("UNSATISFIABLE_SWITCH_PRIORITY_NO_FALLBACK_ALLOWED")
    return positions, priorities

def make_deck(plan_seed, phase, day, pair, epoch, task, difficulty="standard"):
    layout, layout_seed=stream(plan_seed,phase,day,pair,epoch,task,"layout")
    timing, timing_seed=stream(plan_seed,phase,day,pair,epoch,task,"timing")
    motion, motion_seed=stream(plan_seed,phase,day,pair,epoch,task,"motion")
    base={"deck_id":f"{phase}.d{day}.pair{pair}.e{epoch}.{task}","task_id":TASK_IDS[task],
          "hash_encoding":HASH_ENCODING,
          "difficulty":difficulty,"duration_s":24.,
          "rng_seeds":{"layout":layout_seed,"timing":timing_seed,"motion":motion_seed},
          "candidate_id_in_seed":False,"depends_on_player_actions":False}
    if task=="CLICK":
        base["resolution_state"]="resolved_scheduled_opportunities"
        slots=click_layout(layout,difficulty)
        for slot in slots:
            jitter_us=100000+timing.integer(150001)
            onset_us=slot["slot_index"]*1500000+jitter_us
            slot.update(onset_delay_us=jitter_us,onset_delay_s=jitter_us/1e6,
                        onset_us=onset_us,deadline_us=onset_us+1200000,
                        onset_s=onset_us/1e6,deadline_s=(onset_us+1200000)/1e6)
        base["opportunities"]=slots
    elif task=="SWITCH":
        base["resolution_state"]="resolved_scheduled_opportunities"
        positions,priorities=switch_layout(layout,difficulty)
        base["positions"]=positions
        hp=protocol()["tasks"][task]["hp"][difficulty]
        base["opportunities"]=[]
        for i,priority in enumerate(priorities):
            jitter_us=100000+timing.integer(150001)
            onset_us=i*2000000+jitter_us
            base["opportunities"].append({"slot_index":i,"slot_start_s":i*2.,"slot_end_s":(i+1)*2.,
                 "onset_delay_us":jitter_us,"onset_delay_s":jitter_us/1e6,
                 "onset_us":onset_us,"deadline_us":onset_us+1700000,
                 "onset_s":onset_us/1e6,"deadline_s":(onset_us+1700000)/1e6,
                 "priority_target_id":priority,"hp":hp,"damage_hp_s":100.,"ideal_ttk_s":hp/100})
    elif task=="SMOOTH":
        base["resolution_state"]="resolved_analytic_trajectory"
        base["trajectory"]={"kind":"great_circle_horizontal_sine","phase_rad":motion.uniform(0.,2*math.pi),
             "amplitude_deg":14.,"max_speed_deg_s":protocol()["tasks"][task]["max_speed_deg_s"][difficulty],
             "diameter_deg":protocol()["tasks"][task]["diameter_deg"][difficulty],"distance_m":4.}
    else:
        # Resolve with the SAME reference compiler used by public EX06.
        base["resolution_state"]="resolved_shared_EX06_piecewise_trajectory"
        motion_spec=reactive_motion(difficulty)
        base["shared_motion_source"]={"catalogue_revision":"2026-10-12-v2.0",
             "program_id":"EX06","difficulty":difficulty,"phase_id":"reactive",
             "duration_override_s":24.,"motion_kind":"reactive_axis",
             "motion_resource":motion_spec,"motion_resource_sha256":sha256(motion_spec),
             "initial_rng_uint32":motion_seed["uint32"],
             "compiler_version":COMPILER_VERSION}
        base["trajectory_tape"]=compile_reactive(motion_spec,motion_seed["uint32"],horizon_s=24.)
        base["trajectory_tape_sha256"]=sha256(base["trajectory_tape"])
    base["manifest_sha256"]=sha256(base)
    return base

def example_plan():
    p=protocol()
    plan_seed="5a02072603bc40c786d1f934d300005e"
    gains=[make_gain("A",35.,applied_gain=914.4/(800*35.)),make_gain("F",28.),make_gain("S",43.75)]
    verify_gains(gains)
    baseline=gains[0]
    for g in gains:
        g["cm_ratio_to_baseline"]=g["effective_cm_per_360"]/baseline["effective_cm_per_360"]
        g["gain_ratio_to_baseline"]=float(g["degrees_per_relative_input_unit"]["decimal_roundtrip"])/float(baseline["degrees_per_relative_input_unit"]["decimal_roundtrip"])
    order_rng,_=stream(plan_seed,"orders",0,0,0,"ALL","orders")
    express_order=[g["candidate_id"] for g in gains]
    order_rng.shuffle(express_order)
    # The sample assumes express elected F. A real confirmation plan is frozen
    # only after selection, with a fresh seed and its own plan hash.
    confirmation_seed="60f8768b30509bfe1775272a1f248b94"
    confirmation_order_rng,_=stream(confirmation_seed,"orders",0,0,0,"ALL","orders")
    first="ABBA" if confirmation_order_rng.integer(2)==0 else "BAAB"
    orders=[first,"BAAB" if first=="ABBA" else "ABBA"]
    snapshots={"task_revision":"CAL_R2_2026-10-12", "catalogue_revision":"2026-10-12-v2.0",
          "objective":"polyvalent","weights":OBJECTIVES["polyvalent"],
          "difficulty_by_task":{t:"standard" for t in TASKS},
          "declared_dpi":800,"fov_horizontal_deg_at_16_9":103.,
          "render_resolution_px":[1920,1080],"render_scale":1.,"renderer":"example_forward_plus",
          "frame_limit_hz":240,"display_hz_declared":240,"vsync":False,
          "input_convention":"relative_engine_input_linear_gain_no_claim_of_certified_HID",
          "crosshair":{"kind":"dot","core_diameter_px":2,"outline_radial_width_px":1,"outer_diameter_px":4},
          "target_palette":"cyan_on_dark","audio":"short_hit_and_kill_cues",
          "seeded_scored_stimulus_preview":False,"candidate_value_masking":True}
    snapshot_hash=sha256(snapshots)
    plan={"schema_version":"aimlocal.calibration.example_plan.v2","protocol_id":PROTOCOL_ID,
          "hash_encoding":HASH_ENCODING,
          "plan_id":"illustration_cal_v2_001","is_example":True,"contains_real_player_results":False,
          "protocol_sha256":sha256(p),"condition_snapshot":snapshots,"condition_snapshot_sha256":snapshot_hash,
          "candidates":gains,"express_plan_seed_hex":plan_seed,
          "confirmation_plan_seed_hex":confirmation_seed,
          "confirmation_selection_in_example":{"source":"illustrative_express_fixture_not_user_measurement",
                "baseline_candidate_id":"A","challenger_candidate_id":"F","alias_B":"F",
                "selection_scores_excluded_from_confirmation":True},
          "schedule_resolution":"complete_relative_timeline_and_resolved_stimuli",
          "engine_executable":False,
          "reference_stimuli_resolved":True,
          "engine_execution_blockers":["integrate_manifests_with_Godot_runtime",
                 "validate_render_and_input_on_actual_machine",
                 "replace_example_condition_snapshot_and_save_real_plan_before_play"],
          "sessions":[],"decks":{},"programmed_total_s":2712}
    for phase,day,order,rest,duration,seed in [
            ("express",0,express_order,30,696,plan_seed),
            ("confirmation",1,list(orders[0]),60,1008,confirmation_seed),
            ("confirmation",2,list(orders[1]),60,1008,confirmation_seed)]:
        task_order=DAY2_TASK_ORDER if day==2 else DAY1_TASK_ORDER
        session={"session_id":f"{phase}.day{day}.epoch0","phase":phase,"day_role":day,
             "attempt_epoch":0,"planned_duration_s":duration,
             "planned_local_date":None,"actual_start_utc":None,
             "date_note":"day_roles_1_and_2_require_distinct_local_dates_and_12_to_168h_gap",
             "preflight":{"start_s":0,"end_s":60,"gain_candidate_id":"A","tasks":[]},
             "task_order":list(task_order),"order":order,"periods":[],"interperiod_rests":[]}
        for i,t in enumerate(task_order):
            key=f"{phase}_preflight.d{day}.pair0.e0.{t}"
            deck=make_deck(seed,phase+"_preflight",day,0,0,t)
            plan["decks"][key]=deck
            session["preflight"]["tasks"].append({"task":t,"start_s":i*15,"end_s":(i+1)*15,
                  "deck_id":key,"deck_manifest_sha256":deck["manifest_sha256"],
                  "expose_deck_interval_s":[0.,15.],"ignore_partial_final_opportunity_for_familiarization_metric":True,
                  "comparative_utility_included":False})
        for period_index,alias in enumerate(order):
            actual_id="F" if phase=="confirmation" and alias=="B" else alias
            start=60+period_index*(192+rest)
            pair_index=0 if phase=="express" else period_index//2
            period={"period_index":period_index,"comparison_alias":alias,"candidate_id":actual_id,
                    "start_s":start,"end_s":start+192,"pair_index":pair_index,
                    "applied_gain":next(g["degrees_per_relative_input_unit"] for g in gains if g["candidate_id"]==actual_id),
                    "acclimation":{"start_s":start,"end_s":start+60,"score_included":False,
                         "task_segments":[]},"scored_cells":[]}
            for k,t in enumerate(task_order):
                key=f"{phase}_warmup.d{day}.pair{pair_index}.e0.{t}"
                if key not in plan["decks"]:
                    plan["decks"][key]=make_deck(seed,phase+"_warmup",day,pair_index,0,t)
                period["acclimation"]["task_segments"].append({"task":t,"start_s":start+k*15,
                     "end_s":start+(k+1)*15,"deck_id":key,
                     "deck_manifest_sha256":plan["decks"][key]["manifest_sha256"],
                     "expose_deck_interval_s":[0.,15.],"comparative_utility_included":False,
                     "final_partial_opportunity_censored":True})
            for k,t in enumerate(task_order):
                key=f"{phase}.d{day}.pair{pair_index}.e0.{t}"
                if key not in plan["decks"]:
                    plan["decks"][key]=make_deck(seed,phase,day,pair_index,0,t)
                scored_start=start+63+33*k
                period["scored_cells"].append({"cell_id":f"{session['session_id']}.p{period_index}.{t}",
                      "task":t,"task_id":TASK_IDS[t],"candidate_id":actual_id,
                      "deck_id":key,"deck_manifest_sha256":plan["decks"][key]["manifest_sha256"],
                      "countdown_start_s":scored_start-3,"scored_start_s":scored_start,
                      "scored_end_s":scored_start+24,"recovery_end_s":scored_start+30,
                      "duration_s":24,"logical_stimulus_time_origin":"scored_start",
                      "condition_snapshot_sha256":snapshot_hash})
            session["periods"].append(period)
            if period_index<len(order)-1:
                session["interperiod_rests"].append({"start_s":start+192,"end_s":start+192+rest,
                      "gain_candidate_id":actual_id,"restore_baseline":False})
        plan["sessions"].append(session)
    plan["plan_sha256"]=sha256(plan)
    return plan

def close(a,b,tol=1e-9):
    return abs(a-b)<=tol

def validate_plan(plan):
    p=protocol()
    verify_gains(plan["candidates"])
    if plan["protocol_sha256"]!=sha256(p):
        raise ValueError("PROTOCOL_HASH_MISMATCH")
    saved_hash=plan["plan_sha256"]
    without_hash={k:v for k,v in plan.items() if k!="plan_sha256"}
    if sha256(without_hash)!=saved_hash:
        raise ValueError("PLAN_HASH_MISMATCH")
    if sha256(plan["condition_snapshot"])!=plan["condition_snapshot_sha256"]:
        raise ValueError("CONDITION_HASH_MISMATCH")
    gains={g["candidate_id"]:g for g in plan["candidates"]}
    candidate_ids=set(gains)
    selection=plan["confirmation_selection_in_example"]
    aliases={"A":selection["baseline_candidate_id"],"B":selection["challenger_candidate_id"]}
    if aliases["A"]!="A" or aliases["B"]==aliases["A"] or any(v not in gains for v in aliases.values()):
        raise ValueError("INVALID_CONFIRMATION_ALIAS_MAPPING")
    def expected_time(obj,key,expected,code):
        got=obj.get(key)
        if isinstance(got,bool) or not isinstance(got,(int,float)) or not math.isfinite(got) or got!=expected:
            raise ValueError(code)
    def exact_gain_bits(value):
        try:
            n=float(value["decimal_roundtrip"])
            bits=struct.pack(">d",n).hex()
            if not math.isfinite(n) or n<=0 or bits!=value["ieee754_binary64_big_endian_hex"]:
                raise ValueError()
            return bits
        except (KeyError,TypeError,ValueError,OverflowError):
            raise ValueError("MALFORMED_PERIOD_GAIN") from None
    def validate_deck_link(segment,task):
        key=segment.get("deck_id")
        if key not in plan["decks"]:
            raise ValueError("UNDECLARED_DECK_ID")
        deck=plan["decks"][key]
        if segment.get("deck_manifest_sha256")!=deck["manifest_sha256"]:
            raise ValueError("DECK_HASH_LINK_MISMATCH")
        if deck["task_id"]!=TASK_IDS[task]:
            raise ValueError("DECK_TASK_MISMATCH")
        if deck["difficulty"]!=plan["condition_snapshot"]["difficulty_by_task"][task]:
            raise ValueError("DECK_DIFFICULTY_MISMATCH")
    durations=[]
    confirmation_orders={}
    cell_ids=set()
    for sess in plan["sessions"]:
        periods=sess["periods"]
        if sess["phase"]=="express":
            expected_n=len(gains)
            if expected_n not in (2,3) or len(sess["order"])!=expected_n or set(sess["order"])!=candidate_ids:
                raise ValueError("EXPRESS_GAIN_ORDER_NOT_A_PERMUTATION")
            rest_s=30
            expected_order=list(DAY1_TASK_ORDER)
        elif sess["phase"]=="confirmation":
            expected_n=4
            rest_s=60
            day_role=sess["day_role"]
            if day_role not in (1,2) or day_role in confirmation_orders:
                raise ValueError("DUPLICATE_OR_INVALID_CONFIRMATION_DAY_ROLE")
            confirmation_orders[day_role]=sess["order"]
            expected_order=list(DAY1_TASK_ORDER if day_role==1 else DAY2_TASK_ORDER)
        else:
            raise ValueError("UNKNOWN_PLAN_PHASE")
        if len(periods)!=expected_n:
            raise ValueError("WRONG_PERIOD_COUNT")
        expected_budget=60+expected_n*192+(expected_n-1)*rest_s
        expected_time(sess,"planned_duration_s",expected_budget,"BUDGET_MISMATCH")
        if sess["task_order"]!=expected_order:
            raise ValueError("UNDECLARED_TASK_ORDER")
        preflight=sess["preflight"]
        expected_time(preflight,"start_s",0,"PREFLIGHT_START_MISMATCH")
        expected_time(preflight,"end_s",60,"PREFLIGHT_DURATION_MISMATCH")
        if preflight["gain_candidate_id"]!="A" or len(preflight["tasks"])!=4:
            raise ValueError("PREFLIGHT_GAIN_OR_TASK_COUNT_MISMATCH")
        for tidx,segment in enumerate(preflight["tasks"]):
            task=expected_order[tidx]
            if segment["task"]!=task:
                raise ValueError("PREFLIGHT_TASK_ORDER_MISMATCH")
            expected_time(segment,"start_s",tidx*15,"PREFLIGHT_TIMELINE_MISMATCH")
            expected_time(segment,"end_s",(tidx+1)*15,"PREFLIGHT_TIMELINE_MISMATCH")
            if segment.get("expose_deck_interval_s")!=[0.,15.] or segment.get("comparative_utility_included") is not False:
                raise ValueError("PREFLIGHT_COMPARATIVE_EXPOSURE_MISMATCH")
            validate_deck_link(segment,task)
        if len(sess["interperiod_rests"])!=expected_n-1:
            raise ValueError("WRONG_INTERPERIOD_REST_COUNT")
        durations.append(sess["planned_duration_s"])
        for pidx,period in enumerate(periods):
            expected_start=60+pidx*(192+rest_s)
            expected_time(period,"start_s",expected_start,"PERIOD_START_NOT_ON_FROZEN_TIMELINE")
            expected_time(period,"end_s",expected_start+192,"WRONG_PERIOD_DURATION")
            if period.get("period_index")!=pidx:
                raise ValueError("WRONG_PERIOD_INDEX")
            expected_alias=sess["order"][pidx]
            expected_candidate=aliases[expected_alias] if sess["phase"]=="confirmation" else expected_alias
            if period.get("comparison_alias")!=expected_alias or period.get("candidate_id")!=expected_candidate:
                raise ValueError("PERIOD_ALIAS_OR_CANDIDATE_MISMATCH")
            if exact_gain_bits(period.get("applied_gain"))!=gains[expected_candidate]["degrees_per_relative_input_unit"]["ieee754_binary64_big_endian_hex"]:
                raise ValueError("PERIOD_APPLIED_GAIN_MISMATCH")
            expected_pair=0 if sess["phase"]=="express" else pidx//2
            if period.get("pair_index")!=expected_pair:
                raise ValueError("PERIOD_PAIR_INDEX_MISMATCH")
            warmup=period["acclimation"]
            expected_time(warmup,"start_s",expected_start,"WARMUP_START_MISMATCH")
            expected_time(warmup,"end_s",expected_start+60,"WARMUP_DURATION_MISMATCH")
            if warmup.get("score_included") is not False or len(warmup["task_segments"])!=4:
                raise ValueError("WARMUP_SCORE_OR_TASK_COUNT_MISMATCH")
            for tidx,segment in enumerate(warmup["task_segments"]):
                task=expected_order[tidx]
                if segment["task"]!=task:
                    raise ValueError("WARMUP_TASK_ORDER_MISMATCH")
                expected_time(segment,"start_s",expected_start+tidx*15,"WARMUP_TIMELINE_MISMATCH")
                expected_time(segment,"end_s",expected_start+(tidx+1)*15,"WARMUP_TIMELINE_MISMATCH")
                if segment.get("expose_deck_interval_s")!=[0.,15.] or segment.get("comparative_utility_included") is not False:
                    raise ValueError("WARMUP_COMPARATIVE_EXPOSURE_MISMATCH")
                validate_deck_link(segment,task)
            if len(period["scored_cells"])!=4:
                raise ValueError("MISSING_TASK")
            for tidx,cell in enumerate(period["scored_cells"]):
                task=expected_order[tidx]
                if cell["cell_id"] in cell_ids:
                    raise ValueError("DUPLICATE_SCORED_CELL_ID")
                cell_ids.add(cell["cell_id"])
                if cell.get("candidate_id")!=expected_candidate:
                    raise ValueError("CELL_CANDIDATE_MISMATCH")
                if cell.get("task")!=task or cell.get("task_id")!=TASK_IDS[task]:
                    raise ValueError("SCORED_CELL_TASK_ORDER_MISMATCH")
                onset=expected_start+63+33*tidx
                expected_time(cell,"scored_start_s",onset,"WRONG_SCORE_OFFSET")
                expected_time(cell,"countdown_start_s",onset-3,"WRONG_COUNTDOWN_OFFSET")
                expected_time(cell,"scored_end_s",onset+24,"WRONG_SCORED_CELL_DURATION")
                expected_time(cell,"duration_s",24,"WRONG_SCORED_CELL_DURATION")
                expected_time(cell,"recovery_end_s",onset+30,"WRONG_RECOVERY_DURATION")
                if cell.get("condition_snapshot_sha256")!=plan["condition_snapshot_sha256"]:
                    raise ValueError("CELL_CONDITION_SNAPSHOT_MISMATCH")
                validate_deck_link(cell,task)
            if pidx<expected_n-1:
                rest=sess["interperiod_rests"][pidx]
                expected_time(rest,"start_s",expected_start+192,"REST_START_MISMATCH")
                expected_time(rest,"end_s",expected_start+192+rest_s,"REST_DURATION_MISMATCH")
                if rest.get("gain_candidate_id")!=expected_candidate or rest.get("restore_baseline") is not False:
                    raise ValueError("REST_GAIN_CONTINUITY_BROKEN")
        if sess["phase"]=="confirmation":
            if sess["order"] not in [list("ABBA"),list("BAAB")]:
                raise ValueError("WRONG_CONFIRMATION_ORDER")
            for a,b in [(0,1),(2,3)]:
                d1={c["task"]:c["deck_manifest_sha256"] for c in periods[a]["scored_cells"]}
                d2={c["task"]:c["deck_manifest_sha256"] for c in periods[b]["scored_cells"]}
                if d1!=d2:
                    raise ValueError("UNPAIRED_STIMULUS_MANIFEST")
                w1={c["task"]:c["deck_manifest_sha256"] for c in periods[a]["acclimation"]["task_segments"]}
                w2={c["task"]:c["deck_manifest_sha256"] for c in periods[b]["acclimation"]["task_segments"]}
                if w1!=w2:
                    raise ValueError("UNPAIRED_WARMUP_MANIFEST")
    if len(confirmation_orders)==2 and confirmation_orders[1]==confirmation_orders[2]:
        raise ValueError("CONFIRMATION_DAY_ORDERS_NOT_REVERSED")
    if sum(durations)!=plan["programmed_total_s"]:
        raise ValueError("TOTAL_BUDGET_MISMATCH")
    for key,deck in plan["decks"].items():
        if deck.get("deck_id")!=key:
            raise ValueError("DECK_ID_KEY_MISMATCH")
        if sha256({k:v for k,v in deck.items() if k!="manifest_sha256"})!=deck["manifest_sha256"]:
            raise ValueError("DECK_HASH_MISMATCH")
        expected_time(deck,"duration_s",24.,"WRONG_MANIFEST_HORIZON")
        task=deck["task_id"].split("_")[1]
        if task=="CLICK":
            slots=deck["opportunities"]
            if len(slots)!=16:
                raise ValueError("WRONG_CLICK_COUNT")
            counts={(s,a):0 for s in (0,1) for a in (0,1)}
            for slot in slots:
                counts[slot["size_index"],slot["amplitude_index"]]+=1
                if not (.10<=slot["onset_delay_s"]<=.25 and slot["deadline_s"]<slot["slot_end_s"]):
                    raise ValueError("CLICK_TIMING_OUT_OF_BOUNDS")
                if not (-25<=slot["yaw_deg"]<=25 and -12<=slot["pitch_deg"]<=12):
                    raise ValueError("CLICK_GEOMETRY_OUT_OF_BOUNDS")
                lo,hi=slot["amplitude_band_deg"]
                if not lo-1e-8<=slot["planned_initial_amplitude_deg"]<=hi+1e-8:
                    raise ValueError("CLICK_AMPLITUDE_OUT_OF_BOUNDS")
            if set(counts.values())!={4}:
                raise ValueError("CLICK_CELL_BALANCE_BROKEN")
        if task=="SWITCH":
            slots=deck["opportunities"]
            priorities=[s["priority_target_id"] for s in slots]
            if len(slots)!=12 or any(priorities.count(i)!=4 for i in range(3)):
                raise ValueError("SWITCH_PRIORITY_BALANCE_BROKEN")
            if any(a==b for a,b in zip(priorities,priorities[1:])):
                raise ValueError("REPEATED_SWITCH_PRIORITY")
            for slot in slots:
                if not (.10<=slot["onset_delay_s"]<=.25 and slot["deadline_s"]<slot["slot_end_s"]):
                    raise ValueError("SWITCH_TIMING_OUT_OF_BOUNDS")
            pos=deck["positions"]
            for i in range(3):
                for j in range(i):
                    if angle_between(tuple(pos[i]["direction"]),tuple(pos[j]["direction"]))<10-1e-8:
                        raise ValueError("SWITCH_OVERLAPPING_POSITIONS")
        if task=="REACTIVE":
            tape=deck["trajectory_tape"]
            if sha256(tape)!=deck["trajectory_tape_sha256"] or tape["horizon_s"]!=24.:
                raise ValueError("REACTIVE_TAPE_HASH_OR_HORIZON_MISMATCH")
            for tick in range(2401):
                yaw,velocity=sample_reactive(tape,tick/100.)
                speed_max=max(deck["shared_motion_source"]["motion_resource"]["yaw_speed_abs_deg_s"])
                if not (-24.-1e-6<=yaw<=24.+1e-6 and abs(velocity)<=speed_max+1e-6):
                    raise ValueError("REACTIVE_GEOMETRY_OR_SPEED_OUT_OF_BOUNDS")
    return {"ok":True,"scored_cells":sum(len(s["periods"])*4 for s in plan["sessions"]),
            "deck_count":len(plan["decks"]),"programmed_seconds":sum(durations),
            "runtime_ready":plan["engine_executable"],
            "remaining_runtime_blockers":plan["engine_execution_blockers"]}

def explore(data):
    """One complete sustained period per gain: selection is exploratory only."""
    if data.get("protocol_id")!=PROTOCOL_ID or data.get("objective") not in OBJECTIVES:
        raise ValueError("UNKNOWN_PROTOCOL_OR_OBJECTIVE")
    require_protocol_snapshot(data)
    gains=data.get("gains",[])
    verify_gains(gains)
    if len(gains) not in (2,3) or sum(g["candidate_id"]=="A" for g in gains)!=1:
        raise ValueError("EXPRESS_REQUIRES_BASELINE_AND_ONE_OR_TWO_ALTERNATIVES")
    if len({g["declared_dpi"] for g in gains})!=1:
        raise ValueError("DPI_MISMATCH")
    base={"protocol_id":PROTOCOL_ID,"objective":data["objective"],"evidence_method":"exploratory_single_period_per_gain",
          "confidence_interval":None,"equivalence_proven":False,"recommended_action":"keep_original_setting"}
    if data.get("terminal_condition_failures"):
        return dict(base,status="unstable_conditions",reasons=data["terminal_condition_failures"])
    rows=data.get("candidate_results",{})
    if data.get("accepted_conditions_verified") is not True or any(g["candidate_id"] not in rows for g in gains):
        return dict(base,status="incomplete",reasons=["express_conditions_or_candidates_incomplete"])
    if set(rows)!={g["candidate_id"] for g in gains}:
        raise ValueError("UNPLANNED_EXPRESS_CANDIDATE")
    for ident,row in rows.items():
        if row.get("utilities") is None or any(row["utilities"].get(t) is None for t in TASKS):
            return dict(base,status="incomplete",reasons=["missing_express_task"])
        for t in TASKS:
            u=row["utilities"][t]
            if isinstance(u,bool) or not isinstance(u,(int,float)) or not math.isfinite(u) or not 0<=u<=1:
                raise ValueError("UTILITY_OUT_OF_BOUNDS")
        for key,n,t in [("click_successes",16,"CLICK"),("switch_completions",12,"SWITCH")]:
            if not isinstance(row.get(key),int) or not 0<=row[key]<=n or row["utilities"][t]>row[key]/n+1e-9:
                raise ValueError("INVALID_SUCCESS_COUNT_OR_UTILITY")
    weights=OBJECTIVES[data["objective"]]
    scores={ident:100*sum(weights[t]*row["utilities"][t] for t in TASKS) for ident,row in rows.items()}
    lookup={g["candidate_id"]:g for g in gains}
    best_nonbaseline=max(scores[ident] for ident in scores if ident!="A")
    tied=[ident for ident in scores if ident!="A" and best_nonbaseline-scores[ident]<=.25+1e-9]
    baseline_cm=lookup["A"]["effective_cm_per_360"]
    challenger=min(tied,key=lambda ident:(abs(math.log(lookup[ident]["effective_cm_per_360"]/baseline_cm)),ident))
    best=max(scores.values())
    envelope=[ident for ident in scores if best-scores[ident]<=3.+1e-9 and
              all(100*(rows[ident]["utilities"][t]-rows["A"]["utilities"][t])>=-5.-1e-9 for t in TASKS)]
    envelope.sort(key=lambda ident:lookup[ident]["effective_cm_per_360"])
    informational_flags=[]
    uninformative=[t for t in TASKS if statistics.mean(rows[ident]["utilities"][t] for ident in rows)<.10 or
                   statistics.mean(rows[ident]["utilities"][t] for ident in rows)>.95]
    if uninformative:
        informational_flags.append("difficulty_may_be_uninformative_freeze_new_plan_before_confirmation")
    observed_best=[ident for ident in scores if close(scores[ident],best)]
    cm_order=sorted(lookup,key=lambda ident:lookup[ident]["effective_cm_per_360"])
    open_sides=[]
    if cm_order[0] in observed_best: open_sides.append("faster_gain_side_not_explored")
    if cm_order[-1] in observed_best: open_sides.append("slower_gain_side_not_explored")
    return dict(base,status="exploratory_only",scores_pp=scores,
         challenger_candidate_id=challenger,baseline_is_observed_best="A" in observed_best,
         descriptive_envelope_tested_candidate_ids=envelope,envelope_is_continuous_interval=False,
         uninformative_tasks=uninformative,diagnostic_flags=informational_flags,
         unexplored_sides=open_sides,reasons=["fresh_independent_confirmation_required_for_challenger"])

def compare(data):
    """Evaluate prevalidated per-period summaries; targets/frames are NOT n.

    Shape: {phase, objective, gains:[A,B], days:[{day_role,order,periods:[
       {alias,utilities:{CLICK:float,...},click_successes:int,switch_completions:int}
    ]}], terminal_condition_failures:[], qa_only:bool}.
    Each accepted period contains 16 CLICK opportunities / 12 SWITCH ones.
    Full engine event/condition eligibility is upstream and must be retained.
    """
    if data.get("phase")=="express":
        return explore(data)
    if data.get("protocol_id")!=PROTOCOL_ID:
        raise ValueError("UNKNOWN_PROTOCOL")
    require_protocol_snapshot(data)
    if data.get("objective") not in OBJECTIVES:
        raise ValueError("UNKNOWN_OBJECTIVE")
    gains=data.get("gains",[])
    verify_gains(gains,qa_allow_identical=bool(data.get("qa_only",False)))
    if {g["candidate_id"] for g in gains}!={"A","B"}:
        raise ValueError("EXPECTED_A_B_GAIN_IDENTITIES")
    if len({g["declared_dpi"] for g in gains})!=1:
        raise ValueError("DPI_MISMATCH")
    cm={g["candidate_id"]:g["effective_cm_per_360"] for g in gains}
    if max(cm.values())/min(cm.values())>1.50+1e-12:
        raise ValueError("CONFIRMATION_GAIN_CHANGE_EXCEEDS_PROTOCOL_LIMIT")
    base={"protocol_id":PROTOCOL_ID,"objective":data["objective"],
          "evidence_method":"descriptive_two_day_rules",
          "confidence_interval":None,"equivalence_proven":False,
          "qa_only":bool(data.get("qa_only",False)),
          "recommended_action":"keep_original_setting"}
    if data.get("terminal_condition_failures"):
        return dict(base,status="unstable_conditions",reasons=data["terminal_condition_failures"])
    if data.get("phase")!="confirmation":
        raise ValueError("UNKNOWN_PHASE")
    days=data.get("days",[])
    if len(days)<2 or any(len(d.get("periods",[]))<4 for d in days):
        return dict(base,status="incomplete",reasons=["two_complete_days_required"])
    if len(days)!=2 or any(len(d["periods"])!=4 for d in days):
        raise ValueError("EXTRA_ACCEPTED_OBSERVATIONS_NOT_PREDECLARED")
    days=sorted(days,key=lambda d:d["day_role"])
    if [d["day_role"] for d in days]!=[1,2]:
        raise ValueError("WRONG_DAY_ROLES")
    if [d["order"] for d in days] not in [["ABBA","BAAB"],["BAAB","ABBA"]]:
        raise ValueError("ORDERS_NOT_COUNTERBALANCED")
    # A runtime eligibility service checks actual local dates / elapsed time /
    # hashes. The calculator demands its explicit positive result, never guesses.
    if data.get("accepted_conditions_verified") is not True:
        return dict(base,status="incomplete",reasons=["condition_eligibility_not_verified"])
    weights=OBJECTIVES[data["objective"]]
    pair_rows=[]
    day_rows=[]
    totals={a:{"CLICK":0,"SWITCH":0} for a in ("A","B")}
    all_utilities={t:[] for t in TASKS}
    for day in days:
        periods=day["periods"]
        for i,p in enumerate(periods):
            if p.get("alias")!=day["order"][i]:
                raise ValueError("PERIOD_GAIN_ORDER_MISMATCH")
            if p.get("utilities") is None or any(p["utilities"].get(t) is None for t in TASKS):
                return dict(base,status="incomplete",reasons=["missing_required_task"])
            if p.get("click_opportunities") is None or p.get("switch_opportunities") is None:
                return dict(base,status="incomplete",reasons=["missing_opportunity_denominator"])
            if p["click_opportunities"]!=16 or p["switch_opportunities"]!=12:
                raise ValueError("WRONG_OPPORTUNITY_DENOMINATOR")
            for t in TASKS:
                u=p["utilities"][t]
                if isinstance(u,bool) or not isinstance(u,(int,float)) or not math.isfinite(u) or not 0<=u<=1:
                    raise ValueError("UTILITY_OUT_OF_BOUNDS")
                all_utilities[t].append(float(u))
            for key,n,t in [("click_successes",16,"CLICK"),("switch_completions",12,"SWITCH")]:
                count=p.get(key)
                if count is None:
                    return dict(base,status="incomplete",reasons=["missing_success_count"])
                if not isinstance(count,int) or isinstance(count,bool) or not 0<=count<=n:
                    raise ValueError("INVALID_SUCCESS_COUNT")
                # A utility cannot exceed the fraction of successful opportunities.
                if p["utilities"][t]>count/n+1e-9:
                    raise ValueError("UTILITY_EXCEEDS_SUCCESS_FRACTION")
                totals[p["alias"]][t]+=count
        day_pairs=[]
        for pair_index,(i,j) in enumerate(((0,1),(2,3))):
            by_alias={periods[k]["alias"]:periods[k] for k in (i,j)}
            a,b=by_alias["A"],by_alias["B"]
            effects={t:100*(b["utilities"][t]-a["utilities"][t]) for t in TASKS}
            c=sum(weights[t]*effects[t] for t in TASKS)
            row={"day_role":day["day_role"],"pair_index":pair_index,"effects_pp":effects,"composite_pp":c}
            day_pairs.append(row)
            pair_rows.append(row)
        e={t:sum(r["effects_pp"][t] for r in day_pairs)/2 for t in TASKS}
        d=sum(r["composite_pp"] for r in day_pairs)/2
        day_rows.append({"day_role":day["day_role"],"effects_pp":e,"composite_pp":d,
                         "pair_span_pp":abs(day_pairs[0]["composite_pp"]-day_pairs[1]["composite_pp"])})
    dvals=[r["composite_pp"] for r in day_rows]
    cvals=[r["composite_pp"] for r in pair_rows]
    raw_diffs={t:totals["B"][t]-totals["A"][t] for t in ("CLICK","SWITCH")}
    guards={"CLICK":raw_diffs["CLICK"]>=-3,"SWITCH":raw_diffs["SWITCH"]>=-4}
    symmetric_raw=abs(raw_diffs["CLICK"])<=3 and abs(raw_diffs["SWITCH"])<=4
    eps=1e-9  # Only to stabilize arithmetic at predeclared point boundaries.
    task_guard=all(r["effects_pp"][t]>=-5-eps for r in day_rows for t in TASKS)
    global_good=all(d>=2-eps for d in dvals) and all(c>eps for c in cvals)
    global_bad=all(d<=-2+eps for d in dvals) and all(c<-eps for c in cvals)
    strong_positive=[t for t in TASKS if all(r["effects_pp"][t]>=5-eps for r in day_rows)]
    strong_negative=[t for t in TASKS if all(r["effects_pp"][t]<=-5+eps for r in day_rows)]
    uninformative=[t for t in TASKS if statistics.mean(all_utilities[t])<.10-eps or statistics.mean(all_utilities[t])>.95+eps]
    flags=[]
    if any(r["pair_span_pp"]>6+eps for r in day_rows):
        flags.append("order_sensitive_pair_span")
    if dvals[0]*dvals[1]<0:
        flags.append("opposite_day_effect_signs")
    base.update(pair_effects=pair_rows,day_effects=day_rows,
                observed_mean_effect_pp=statistics.mean(dvals),
                observed_day_range_pp=[min(dvals),max(dvals)],
                observed_pair_range_pp=[min(cvals),max(cvals)],
                effective_day_count=2,paired_contrast_count=4,
                success_counts=totals,success_count_difference_B_minus_A=raw_diffs,
                success_rate_difference_B_minus_A={"CLICK":raw_diffs["CLICK"]/64.,"SWITCH":raw_diffs["SWITCH"]/48.},
                per_task_guard_pass=task_guard,raw_success_guards=guards,
                diagnostic_flags=flags,uninformative_tasks=uninformative)
    if uninformative:
        return dict(base,status="undetermined",reasons=["task_floor_or_ceiling_requires_new_frozen_difficulty"])
    if global_bad:
        return dict(base,status="repeated_regression",reasons=["global_loss_repeated_on_both_days"])
    if global_good and task_guard and all(guards.values()):
        return dict(base,status="repeated_improvement",reasons=["global_gain_repeated_with_guards"],
                    recommended_action="offer_saved_challenger_for_explicit_application")
    if (global_good and (not task_guard or not all(guards.values()))) or (strong_positive and strong_negative):
        return dict(base,status="mixed_tradeoff",reasons=["gain_with_skill_or_success_tradeoff"])
    if (all(abs(d)<=2+eps for d in dvals) and all(abs(c)<=3+eps for c in cvals)
        and all(abs(r["effects_pp"][t])<=5+eps for r in day_rows for t in TASKS)
        and symmetric_raw):
        return dict(base,status="close_observed",reasons=["small_observed_differences_not_proven_equivalence"])
    return dict(base,status="undetermined",reasons=["predeclared_repeatability_rules_not_met"])

def measurement_fixture(name,effects,orders=("ABBA","BAAB"),qa_same_gain=False):
    """effects: two days × two paired contrasts × four task differences (points)."""
    a=make_gain("A",35.)
    b=make_gain("B",35. if qa_same_gain else 28.)
    data={"fixture_name":name,"data_origin":"synthetic_illustration_not_measured_player_data",
          "protocol_id":PROTOCOL_ID,"phase":"confirmation","objective":"polyvalent",
          "protocol_sha256":protocol_hash(),
          "qa_only":qa_same_gain,"gains":[a,b],"accepted_conditions_verified":True,
          "eligibility_note":"synthetic_QA_explicitly_assumes_eligible_conditions",
          "terminal_condition_failures":[],"days":[]}
    ref={"CLICK":.565,"SMOOTH":.710,"REACTIVE":.600,"SWITCH":.590}
    for day_idx,order in enumerate(orders):
        day={"day_role":day_idx+1,"order":order,"periods":[]}
        for period_idx,alias in enumerate(order):
            pair=period_idx//2
            u={t:ref[t]+(effects[day_idx][pair][i]/100 if alias=="B" else 0) for i,t in enumerate(TASKS)}
            day["periods"].append({"alias":alias,"utilities":u,"click_opportunities":16,
                      "switch_opportunities":12,"click_successes":15,"switch_completions":11})
        data["days"].append(day)
    return data

def fixture_set():
    benefit=[[[3.,3.,5.,2.],[2.8,2.4,4.2,2.2]],[[3.2,3.2,5.2,2.4],[2.6,2.6,4.6,1.8]]]
    zero=[[[0.]*4,[0.]*4],[[0.]*4,[0.]*4]]
    fixtures={}
    fixtures["repeated_improvement"]=measurement_fixture("repeated_improvement",benefit)
    fixtures["close_observed"]=measurement_fixture("close_observed",zero)
    fixtures["same_gain_null_qa"]=measurement_fixture("same_gain_null_qa",zero,qa_same_gain=True)
    fixtures["repeated_regression"]=measurement_fixture("repeated_regression",[[[-x for x in row] for row in day] for day in benefit])
    fixtures["mixed_tradeoff"]=measurement_fixture("mixed_tradeoff",[[[6.,3.,3.,3.],[6.,3.,3.,3.]],[[6.,3.,3.,3.],[6.,3.,3.,3.]]])
    for day in fixtures["mixed_tradeoff"]["days"]:
        for period in day["periods"]:
            if period["alias"]=="B":
                period["click_successes"]=13
    fixtures["opposite_days"]=measurement_fixture("opposite_days",[[[4.]*4,[4.]*4],[[-4.]*4,[-4.]*4]])
    fixtures["linear_drift_null"]=measurement_fixture("linear_drift_null",[[[-3.]*4,[3.]*4],[[3.]*4,[-3.]*4]])
    reference={"CLICK":.565,"SMOOTH":.710,"REACTIVE":.600,"SWITCH":.590}
    for day in fixtures["linear_drift_null"]["days"]:
        for pidx,period in enumerate(day["periods"]):
            period["utilities"]={t:reference[t]-.03*pidx for t in TASKS}
    fixtures["linear_drift_null"]["injected_linear_period_drift_pp"]=-3.
    fixtures["missing_second_day"]=copy.deepcopy(fixtures["repeated_improvement"])
    fixtures["missing_second_day"]["fixture_name"]="missing_second_day"
    fixtures["missing_second_day"]["days"]=fixtures["missing_second_day"]["days"][:1]
    fixtures["technical_blocker"]=copy.deepcopy(fixtures["repeated_improvement"])
    fixtures["technical_blocker"]["fixture_name"]="technical_blocker"
    fixtures["technical_blocker"]["terminal_condition_failures"]=["retry_exhausted_after_capture_loss"]
    fixtures["exploratory_only"]={"fixture_name":"exploratory_only",
        "data_origin":"synthetic_illustration_not_measured_player_data","protocol_id":PROTOCOL_ID,
        "protocol_sha256":protocol_hash(),
        "phase":"express","objective":"polyvalent","accepted_conditions_verified":True,
        "terminal_condition_failures":[],"gains":[make_gain("A",35.),make_gain("F",28.),make_gain("S",43.75)],
        "candidate_results":{
            "A":{"utilities":dict(zip(TASKS,[.565,.710,.600,.590])),"click_successes":15,"switch_completions":11},
            "F":{"utilities":dict(zip(TASKS,[.580,.735,.652,.612])),"click_successes":15,"switch_completions":11},
            "S":{"utilities":dict(zip(TASKS,[.580,.690,.565,.565])),"click_successes":15,"switch_completions":11}}}
    fixtures["floor_uninformative"]=copy.deepcopy(fixtures["close_observed"])
    fixtures["floor_uninformative"]["fixture_name"]="floor_uninformative"
    for day in fixtures["floor_uninformative"]["days"]:
        for period in day["periods"]:
            period["utilities"]["SMOOTH"]=.02
    return fixtures

def rehash_plan(plan):
    plan["plan_sha256"]=sha256({k:v for k,v in plan.items() if k!="plan_sha256"})

def apply_json_replacements(plan,operations):
    for op in operations:
        if op["op"]!="replace":
            raise ValueError("QA_ONLY_REPLACE_SUPPORTED")
        parts=op["path"].lstrip("/").split("/")
        target=plan
        for part in parts[:-1]:
            key=part.replace("~1","/").replace("~0","~")
            target=target[int(key)] if isinstance(target,list) else target[key]
        key=parts[-1].replace("~1","/").replace("~0","~")
        if isinstance(target,list):target[int(key)]=copy.deepcopy(op["value"])
        else:target[key]=copy.deepcopy(op["value"])
    rehash_plan(plan)
    return plan

def negative_plan_fixtures(plan):
    def replace(path,value):return {"op":"replace","path":path,"value":value}
    # Preserve the internal shape of a moved period: the validator must reject
    # the actual schedule change, not merely an accidentally stale linked time.
    old=plan["sessions"][0]["periods"][1]
    path="/sessions/0/periods/1"
    shift=[replace(path+"/start_s",old["start_s"]-10),replace(path+"/end_s",old["end_s"]-10)]
    for key in ("start_s","end_s"):
        shift.append(replace(path+"/acclimation/"+key,old["acclimation"][key]-10))
    for i,segment in enumerate(old["acclimation"]["task_segments"]):
        for key in ("start_s","end_s"):
            shift.append(replace(path+f"/acclimation/task_segments/{i}/"+key,segment[key]-10))
    for i,cell in enumerate(old["scored_cells"]):
        for key in ("countdown_start_s","scored_start_s","scored_end_s","recovery_end_s"):
            shift.append(replace(path+f"/scored_cells/{i}/"+key,cell[key]-10))
    bindex=next(i for i,p in enumerate(plan["sessions"][1]["periods"]) if p["comparison_alias"]=="B")
    gain_a=next(g for g in plan["candidates"] if g["candidate_id"]=="A")["degrees_per_relative_input_unit"]
    cell=plan["sessions"][0]["periods"][0]["scored_cells"][0]
    prefix="/sessions/0/periods/0/scored_cells/0/"
    fixtures=[
       {"id":"shift_interior_period_minus_10s","expected_error":"PERIOD_START_NOT_ON_FROZEN_TIMELINE","operations":shift},
       {"id":"B_period_applies_A_gain","expected_error":"PERIOD_APPLIED_GAIN_MISMATCH",
        "operations":[replace(f"/sessions/1/periods/{bindex}/applied_gain",gain_a)]},
       {"id":"undeclared_cell_candidate","expected_error":"CELL_CANDIDATE_MISMATCH",
        "operations":[replace(prefix+"candidate_id","UNDECLARED")]},
       {"id":"score_cell_shortened_to_23s","expected_error":"WRONG_SCORED_CELL_DURATION",
        "operations":[replace(prefix+"scored_end_s",cell["scored_end_s"]-1),replace(prefix+"duration_s",23)]},
       {"id":"restore_baseline_between_periods","expected_error":"REST_GAIN_CONTINUITY_BROKEN",
        "operations":[replace("/sessions/0/interperiod_rests/0/restore_baseline",True)]},
       {"id":"shortened_rest","expected_error":"REST_DURATION_MISMATCH",
        "operations":[replace("/sessions/0/interperiod_rests/0/end_s",plan["sessions"][0]["interperiod_rests"][0]["end_s"]-1)]},
       {"id":"cell_uses_other_condition_snapshot","expected_error":"CELL_CONDITION_SNAPSHOT_MISMATCH",
        "operations":[replace(prefix+"condition_snapshot_sha256","0"*64)]},
       {"id":"warmup_included_in_comparison","expected_error":"WARMUP_SCORE_OR_TASK_COUNT_MISMATCH",
        "operations":[replace("/sessions/0/periods/0/acclimation/score_included",True)]},
    ]
    return {"schema_version":"aimlocal.calibration.plan_negative_fixtures.v2",
            "base_plan_sha256":plan["plan_sha256"],"rehash_plan_after_each_fixture":True,
            "rationale":"a_correct_hash_does_not_validate_internal_plan_semantics",
            "fixtures":fixtures}

def example_two_gain_plan(original):
    """Positive shape fixture for a 2-gain express; not a new tested dataset."""
    plan=copy.deepcopy(original)
    plan["plan_id"]="illustration_cal_v2_two_gains_001"
    plan["two_gain_fixture_reason"]="third_alternative_unavailable_in_upstream_profile_adapter"
    plan["candidates"]=[g for g in plan["candidates"] if g["candidate_id"] in ("A","F")]
    sess=plan["sessions"][0]
    sess["order"]=[a for a in sess["order"] if a in ("A","F")]
    kept=[p for p in sess["periods"] if p["candidate_id"] in ("A","F")]
    for i,period in enumerate(kept):
        new_start=60+i*222
        delta=new_start-period["start_s"]
        period["period_index"]=i
        for key in ("start_s","end_s"):period[key]+=delta
        for key in ("start_s","end_s"):period["acclimation"][key]+=delta
        for segment in period["acclimation"]["task_segments"]:
            for key in ("start_s","end_s"):segment[key]+=delta
        for cell in period["scored_cells"]:
            for key in ("countdown_start_s","scored_start_s","scored_end_s","recovery_end_s"):cell[key]+=delta
    sess["periods"]=kept
    sess["interperiod_rests"]=[{"start_s":252,"end_s":282,"gain_candidate_id":kept[0]["candidate_id"],"restore_baseline":False}]
    sess["planned_duration_s"]=474
    plan["programmed_total_s"]=474+2016
    rehash_plan(plan)
    return plan

def run_checks():
    plan=example_plan()
    plan_check=validate_plan(plan)
    two_gain_check=validate_plan(example_two_gain_plan(plan))
    assert two_gain_check["programmed_seconds"]==2490 and two_gain_check["scored_cells"]==40
    negative_checks=[]
    for fixture in negative_plan_fixtures(plan)["fixtures"]:
        corrupted=apply_json_replacements(copy.deepcopy(plan),fixture["operations"])
        try:
            validate_plan(corrupted)
        except ValueError as exc:
            if str(exc)!=fixture["expected_error"]:
                raise AssertionError((fixture["id"],str(exc),fixture["expected_error"])) from exc
            negative_checks.append({"id":fixture["id"],"rejected_with":str(exc)})
        else:
            raise AssertionError("negative plan fixture accepted: "+fixture["id"])
    fixtures=fixture_set()
    expected={"repeated_improvement":"repeated_improvement","close_observed":"close_observed",
       "same_gain_null_qa":"close_observed","repeated_regression":"repeated_regression",
       "mixed_tradeoff":"mixed_tradeoff","opposite_days":"undetermined",
       "linear_drift_null":"close_observed","missing_second_day":"incomplete",
       "technical_blocker":"unstable_conditions","exploratory_only":"exploratory_only",
       "floor_uninformative":"undetermined"}
    results={}
    for name,data in fixtures.items():
        r=compare(data)
        if r["status"]!=expected[name]:
            raise AssertionError((name,r["status"],expected[name]))
        results[name]=r["status"]
    got=compare(fixtures["repeated_improvement"])
    assert close(got["observed_mean_effect_pp"],3.1375)
    assert all(close(a,b) for a,b in zip(got["observed_day_range_pp"],[3.075,3.2]))
    assert got["success_counts"]=={"A":{"CLICK":60,"SWITCH":44},"B":{"CLICK":60,"SWITCH":44}}
    selection=compare(fixtures["exploratory_only"])
    assert selection["challenger_candidate_id"]=="F"
    assert selection["descriptive_envelope_tested_candidate_ids"]==["F","A"]
    # An equal-gain sham is prohibited in a normal user plan, not a recommendation.
    invalid=copy.deepcopy(fixtures["same_gain_null_qa"])
    invalid["qa_only"]=False
    try:
        compare(invalid)
    except ValueError as exc:
        assert str(exc)=="DUPLICATE_EFFECTIVE_GAIN"
    else:
        raise AssertionError("same effective gain accepted in production")
    # Complete zeros are human observations, not missing data; retain then flag floor.
    zeros=copy.deepcopy(fixtures["close_observed"])
    for d in zeros["days"]:
        for per in d["periods"]:
            per["utilities"]={t:0. for t in TASKS}
            per["click_successes"]=0
            per["switch_completions"]=0
    rz=compare(zeros)
    assert rz["status"]=="undetermined" and rz["effective_day_count"]==2
    # Seeds and scored stimuli are independent of candidate identity and inputs.
    assert example_plan()["plan_sha256"]==plan["plan_sha256"]
    grid=candidate_grid(make_gain("A",35.))
    assert len(grid)==3 and all(close(a,b) for a,b in zip(sorted(g["effective_cm_per_360"] for g in grid),[28.,35.,43.75]))
    bounded=candidate_grid(make_gain("A",5.))
    assert len(bounded)==2
    assert bounded[0]["degrees_per_relative_input_unit"]==make_gain("A",5.)["degrees_per_relative_input_unit"]
    quantized=candidate_grid(make_gain("A",35.),representable_gain=lambda g:round(g/.022,3)*.022)
    assert quantized[0]["degrees_per_relative_input_unit"]==make_gain("A",35.)["degrees_per_relative_input_unit"]
    # Seeded sphere geometry and schedule constraints across multiple plans/decks.
    for k in range(50):
        sd=format(k+1,"032x")
        for task in ("CLICK","SWITCH"):
            d=make_deck(sd,"confirmation",1,0,0,task)
            assert d["depends_on_player_actions"] is False
            assert d["candidate_id_in_seed"] is False
    return {"checks_passed":True,"fixture_statuses":results,"plan":plan_check,
            "two_gain_express_plan":two_gain_check,"negative_plan_fixtures":negative_checks,
            "deterministic_example_plan_hash":plan["plan_sha256"],
            "scope":"calculator_schedule_static_geometry_and_shared_reference_motion_not_Godot_or_human_validation"}

def simulate(n=20000,seed=246031):
    """Descriptive Monte Carlo under stated toy models. NO error-control claim.

    Common period disturbances create correlated task scores. Raw success counts
    are fixed (15/16 CLICK, 11/12 SWITCH) to isolate arithmetic decision behavior;
    this DOES NOT validate the success-rate guard or human noise distribution.
    """
    if n<1:
        raise ValueError("n must be positive")
    rng=random.Random(seed)
    scenarios=[
       {"id":"null_iid_period_noise","effect_pp":0.,"linear_pp_per_period":0.,"curvature_pp":0.,"carryover_pp":0.,"rho":0.},
       {"id":"null_linear_drift","effect_pp":0.,"linear_pp_per_period":-1.,"curvature_pp":0.,"carryover_pp":0.,"rho":.60},
       {"id":"null_day_curvature","effect_pp":0.,"linear_pp_per_period":-1.,"curvature_pp":2.,"carryover_pp":0.,"rho":.60},
       {"id":"null_direction_specific_switch_bias","effect_pp":0.,"linear_pp_per_period":-1.,"curvature_pp":0.,"carryover_pp":-4.,"rho":.60},
       {"id":"null_direction_specific_switch_benefit","effect_pp":0.,"linear_pp_per_period":-1.,"curvature_pp":0.,"carryover_pp":4.,"rho":.60},
       {"id":"gain_3pp_drift_noise","effect_pp":3.,"linear_pp_per_period":-1.,"curvature_pp":1.,"carryover_pp":0.,"rho":.60},
       {"id":"gain_5pp_drift_noise","effect_pp":5.,"linear_pp_per_period":-1.,"curvature_pp":1.,"carryover_pp":0.,"rho":.60},
    ]
    counts_out=[]
    for scenario in scenarios:
        counts={}
        clipped_utilities=0
        for _ in range(n):
            first="ABBA" if rng.random()<.5 else "BAAB"
            orders=(first,"BAAB" if first=="ABBA" else "ABBA")
            sample={"fixture_name":"monte_carlo","protocol_id":PROTOCOL_ID,
                "protocol_sha256":protocol_hash(),
                "phase":"confirmation","objective":"polyvalent",
                "gains":[make_gain("A",35.),make_gain("B",28.)],
                "accepted_conditions_verified":True,"terminal_condition_failures":[],"days":[]}
            # Allow curvature to differ by day, rather than magically cancel.
            for day_idx,order in enumerate(orders):
                periods=[]
                noise=rng.gauss(0.,2.)
                curve=scenario["curvature_pp"]*rng.gauss(0.,1.)
                previous="A" # Baseline before each session.
                for period_idx,alias in enumerate(order):
                    rho=scenario["rho"]
                    noise=rho*noise+math.sqrt(1-rho*rho)*rng.gauss(0.,2.)
                    shared=(noise+scenario["linear_pp_per_period"]*period_idx+
                            curve*([1.,-1.,-1.,1.][period_idx]))
                    # A deliberately asymmetric unmodelled adaptation bias;
                    # it penalizes B only immediately after A. Counterbalance
                    # alone cannot turn it into an unbiased long-term effect.
                    carry=scenario["carryover_pp"] if alias=="B" and previous=="A" else 0.
                    utility={}
                    baseline=dict(zip(TASKS,(.565,.710,.600,.590)))
                    for t in TASKS:
                        raw=baseline[t]+(shared+carry+(scenario["effect_pp"] if alias=="B" else 0.)+rng.gauss(0.,3.))/100.
                        upper=(15/16 if t=="CLICK" else 11/12 if t=="SWITCH" else 1.)
                        utility[t]=max(0.,min(upper,raw))
                        if utility[t]!=raw:
                            clipped_utilities+=1
                    periods.append({"alias":alias,"utilities":utility,
                        "click_opportunities":16,"switch_opportunities":12,
                        "click_successes":15,"switch_completions":11})
                    previous=alias
                sample["days"].append({"day_role":day_idx+1,"order":order,"periods":periods})
            status=compare(sample)["status"]
            counts[status]=counts.get(status,0)+1
        promote=counts.get("repeated_improvement",0)/n
        counts_out.append(dict(scenario,simulations=n,counts=counts,clipped_utility_count=clipped_utilities,
              repeated_improvement_fraction=promote,
              monte_carlo_standard_error=math.sqrt(promote*(1-promote)/n)))
    return {"protocol_id":PROTOCOL_ID,"data_origin":"synthetic_model_only",
          "decision_rules_snapshot_sha256":sha256(protocol()["decision"]),
          "hash_encoding":HASH_ENCODING,
          "random_generator":"Python_random_MT19937_for_simulation_only_not_stimulus_generation",
          "seed":seed,"simulations_per_scenario":n,
          "noise_model":{"period_common_noise_sd_pp":2.,"task_residual_sd_pp":3.,
              "within_day_period_AR1":True,"task_noise_correlated_via_period_common_component":True,
              "success_counts_fixed":"15_of_16_CLICK_and_11_of_12_SWITCH_in_each_period",
              "utility_clipped_to_logical_range": "0_to_1_tracking_and_0_to_success_fraction_CLICK_SWITCH",
              "normal_noise_is_an_unvalidated_illustration":True},
          "interpretation":"algorithmic_sensitivity_analysis_not_human_validation_not_probability_of_correct_sensitivity",
          "scenarios":counts_out}

def build(outdir):
    outdir=Path(outdir)
    outdir.mkdir(parents=True,exist_ok=True)
    fixtures=fixture_set()
    artifacts={"calibration_v2_protocol.json":protocol(),
               "calibration_v2_plan_example.json":example_plan(),
               "calibration_v2_plan_negative_fixtures.json":negative_plan_fixtures(example_plan()),
               "calibration_v2_comparison_examples.json":{"fixtures":fixtures,"results":{n:compare(d) for n,d in fixtures.items()}},
               "calibration_v2_checks.json":run_checks()}
    for name,obj in artifacts.items():
        (outdir/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    return {"written":[str(outdir/name) for name in artifacts],"checks":artifacts["calibration_v2_checks.json"]}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest="command",required=True)
    b=sub.add_parser("build"); b.add_argument("--output-dir",default=".")
    sub.add_parser("check")
    c=sub.add_parser("calculate"); c.add_argument("input")
    s=sub.add_parser("simulate");s.add_argument("--n",type=int,default=20000);s.add_argument("--output",default="calibration_v2_simulation.json")
    args=parser.parse_args()
    if args.command=="build":
        result=build(args.output_dir)
    elif args.command=="check":
        result=run_checks()
    elif args.command=="calculate":
        result=compare(strict_loads(Path(args.input).read_text(encoding="utf-8")))
    else:
        result=simulate(args.n)
        Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False))

if __name__=="__main__":
    main()
