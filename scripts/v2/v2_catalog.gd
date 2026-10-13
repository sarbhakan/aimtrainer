class_name V2Catalog
extends RefCounted

const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const Geometry := preload("res://scripts/v2/v2_geometry.gd")
const REVISION: String = "2026-10-12-v2.0"
const CATALOGUE_PATH: String = "res://content/v2/catalogue.v2.json"
const CATALOGUE_SHA256: String = "b72277ca6ac33b93aa38ac73092c529f2152c2ab88199fa0fcaea3ee93154781"
const SCHEMA_SOURCE_SHA256: String = "211563525acb4c23dada3351386cb84f2b6f59bb6761ea7b0f8bee82186743e6"
const VALIDATION_SCOPE: String = "Pinned original catalogue bytes; supplied frozen schema subset and native public-program semantic checks, including sampled ellipse acceleration. Importer retains the complete supplied Python checks."
const MAX_SAFE_INTEGER: int = 9007199254740991
const ELLIPSE_ACCELERATION_SAMPLES: int = 8192
const SUPPORTED_SCHEMA_KEYWORDS: Array[String] = [
	"$schema", "$id", "$comment", "$defs", "$ref", "title", "description", "type", "const", "enum",
	"properties", "required", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems",
	"oneOf", "anyOf", "allOf", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
	"minLength", "maxLength", "pattern"
]
const PHASE_LAYOUT: Dictionary = {
	"EX01": [["micro", 20, "click", "static", 1], ["general", 20, "click", "static", 1], ["amplitude", 20, "click", "static", 1]],
	"EX02": [["grid", 20, "click", "static", 3], ["precision", 40, "click", "static", 6]],
	"EX03": [["fixed_window", 30, "opportunity", "static", 1], ["shrinking_window", 30, "opportunity", "static", 1]],
	"EX04": [["linear", 20, "click", "linear_reflect", 4], ["evasive", 20, "click", "reactive_lanes", 4], ["arcs", 20, "click", "angular_bounce", 4]],
	"EX05": [["horizontal", 20, "tracking", "sinusoid_axis", 1], ["vertical", 20, "tracking", "sinusoid_axis", 1], ["ellipse", 20, "tracking", "angular_ellipse", 1]],
	"EX06": [["reactive", 60, "tracking", "reactive_axis", 1]],
	"EX07": [["depth", 60, "tracking", "depth_sines", 1]],
	"EX08": [["static", 20, "switching", "static", 4], ["mobile", 20, "switching", "linear_reflect", 4], ["evasive", 20, "switching", "reactive_lanes", 4]]
}
const SCORE_IDS: Dictionary = {"click": "click_v3", "opportunity": "opportunities_v2", "tracking": "contact_v2", "switching": "switch_work_v3"}
const FIRE_MODES: Dictionary = {"click": "press_edge", "opportunity": "press_edge", "tracking": "automatic_contact_measurement", "switching": "hold_continuous_damage"}
const RANGE_KEYS: Array[String] = [
	"center_yaw_deg", "center_pitch_deg", "center_distance_m", "yaw_deg", "pitch_deg", "transition_angle_deg",
	"onset_delay_uniform_s", "candidate_yaw_deg", "yaw_bounds_deg", "yaw_speed_abs_deg_s", "uniform_duration_s",
	"phase_rad_distribution", "ground_rest_uniform_s", "initial_flight_age_uniform_s", "initial_yaw_uniform_deg",
	"initial_cycle_fraction_uniform", "initial_phase_rad_uniform", "initial_arc_fraction_uniform", "annulus_azimuth_rad_uniform", "angle_deg"
]
const CATALOGUE_SCHEMA_JSON: String = (
	"{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$id\":\"urn:aimlocal:catalogue:v2\",\"title\":\"AIM/LOCAL"
	+ " V2 catalogue — closed resolved structural contract\",\"$comment\":\"Structural JSON Schema 2020-12; geometry and "
	+ "cross-field semantics are checked by outils/valider_catalogue.py. The bundled evaluator implements only the ex"
	+ "plicitly listed keywords of this schema, not general JSON Schema.\",\"type\":\"object\",\"additionalProperties\":fals"
	+ "e,\"required\":[\"schema_version\",\"catalogue_revision\",\"design_status\",\"configuration_count\",\"public_program_coun"
	+ "t\",\"laboratory_extensions_enabled\",\"sensitivity_calibration_uses_separate_tasks\",\"randomization\",\"programs\"],\""
	+ "properties\":{\"schema_version\":{\"type\":\"string\",\"const\":\"aimlocal.catalogue.v2\"},\"catalogue_revision\":{\"type\":\""
	+ "string\",\"pattern\":\"^[0-9]{4}-[0-9]{2}-[0-9]{2}-v2\\\\.[0-9]+$\"},\"design_status\":{\"type\":\"string\",\"const\":\"origin"
	+ "al_proposed_parameters_require_local_playtesting\"},\"configuration_count\":{\"type\":\"integer\",\"const\":24},\"public"
	+ "_program_count\":{\"type\":\"integer\",\"const\":8},\"laboratory_extensions_enabled\":{\"type\":\"boolean\",\"const\":false},"
	+ "\"sensitivity_calibration_uses_separate_tasks\":{\"type\":\"boolean\",\"const\":true},\"randomization\":{\"$ref\":\"#/$defs"
	+ "/Randomization\"},\"programs\":{\"type\":\"array\",\"minItems\":24,\"maxItems\":24,\"items\":{\"$ref\":\"#/$defs/Program\"}}},\""
	+ "$defs\":{\"Randomization\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"generator\",\"integer_storage"
	+ "\",\"steps\",\"zero_seed_replacement_hex\",\"uniform_float_formula\",\"uniform_integer_method\",\"substream_seed\",\"tuple"
	+ "_fields\",\"canonical_json\",\"session_seed_hex_characters\",\"stream_name_grammar\",\"domains\",\"decimal_indices\",\"con"
	+ "tinuous_distributions\",\"cosmetics_cannot_consume_motion_layout_or_timing_streams\",\"per_frame_random_draws_allo"
	+ "wed\",\"illustrative_atlas_session_seed_hex\",\"determinism_scope\",\"different_inputs_may_change_hit_driven_spawns\""
	+ "],\"properties\":{\"generator\":{\"type\":\"string\",\"const\":\"xorshift32_v1\"},\"integer_storage\":{\"type\":\"string\",\"cons"
	+ "t\":\"nonnegative_int64_masked_to_32_bits\"},\"steps\":{\"type\":\"array\",\"const\":[\"x = (x ^ (x << 13)) & 0xffffffff\","
	+ "\"x = (x ^ (x >> 17)) & 0xffffffff\",\"x = (x ^ (x << 5)) & 0xffffffff\"]},\"zero_seed_replacement_hex\":{\"type\":\"st"
	+ "ring\",\"const\":\"6D2B79F5\"},\"uniform_float_formula\":{\"type\":\"string\",\"const\":\"(next_uint32 + 0.5) / 4294967296\"}"
	+ ",\"uniform_integer_method\":{\"type\":\"string\",\"const\":\"reject_uint32_ge_floor_4294967296_div_n_times_n_then_mod_n"
	+ "\"},\"substream_seed\":{\"type\":\"string\",\"const\":\"first_4_bytes_big_endian_sha256_utf8_canonical_json_tuple\"},\"tup"
	+ "le_fields\":{\"type\":\"array\",\"const\":[\"catalogue_revision\",\"session_seed_hex\",\"program_id\",\"difficulty\",\"phase_i"
	+ "d\",\"stream_name\"]},\"canonical_json\":{\"type\":\"string\",\"const\":\"JSON_array_of_ASCII_strings_no_spaces_no_BOM_no_"
	+ "trailing_newline\"},\"session_seed_hex_characters\":{\"type\":\"integer\",\"const\":32},\"stream_name_grammar\":{\"type\":\""
	+ "string\",\"const\":\"domain/slot_decimal/generation_decimal/purpose\"},\"domains\":{\"type\":\"array\",\"const\":[\"layout\","
	+ "\"timing\",\"motion\",\"diagnostic\",\"cosmetic\"]},\"decimal_indices\":{\"type\":\"string\",\"const\":\"nonnegative_base10_no_"
	+ "leading_zero_except_0\"},\"continuous_distributions\":{\"type\":\"string\",\"const\":\"open_interval_uniform\"},\"cosmetic"
	+ "s_cannot_consume_motion_layout_or_timing_streams\":{\"type\":\"boolean\",\"const\":true},\"per_frame_random_draws_allo"
	+ "wed\":{\"type\":\"boolean\",\"const\":false},\"illustrative_atlas_session_seed_hex\":{\"type\":\"string\",\"pattern\":\"^[0-9a"
	+ "-f]{32}$\"},\"determinism_scope\":{\"type\":\"string\",\"const\":\"same_revision_seed_configuration_and_timestamped_inpu"
	+ "ts\"},\"different_inputs_may_change_hit_driven_spawns\":{\"type\":\"boolean\",\"const\":true}}},\"Arena\":{\"type\":\"object"
	+ "\",\"additionalProperties\":false,\"required\":[\"eye_position_m\",\"player_movement_enabled\",\"reference_look_yaw_pitc"
	+ "h_deg\",\"forward_axis\",\"right_axis\",\"up_axis\",\"roll_deg\",\"fov_horizontal_deg_at_16_9\",\"reference_aspect_ratio\","
	+ "\"fov_vertical_deg\",\"near_m\",\"far_m\",\"floor_y_m\",\"target_shape\",\"collider_matches_visual_sphere\",\"wall_referenc"
	+ "e_distance_m\",\"world_art_geometry_noncolliding\"],\"properties\":{\"eye_position_m\":{\"type\":\"array\",\"minItems\":3,\""
	+ "maxItems\":3,\"items\":{\"type\":\"number\",\"minimum\":-1000,\"maximum\":1000}},\"player_movement_enabled\":{\"type\":\"boole"
	+ "an\",\"const\":false},\"reference_look_yaw_pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"n"
	+ "umber\",\"minimum\":-180,\"maximum\":180}},\"forward_axis\":{\"type\":\"string\",\"const\":\"negative_z\"},\"right_axis\":{\"typ"
	+ "e\":\"string\",\"const\":\"positive_x\"},\"up_axis\":{\"type\":\"string\",\"const\":\"positive_y\"},\"roll_deg\":{\"type\":\"number\""
	+ ",\"const\":0},\"fov_horizontal_deg_at_16_9\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"reference_aspect_rati"
	+ "o\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-1000000000000.0,\"maximum\":100"
	+ "0000000000.0}},\"fov_vertical_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"near_m\":{\"type\":\"number\",\"ma"
	+ "ximum\":1000,\"exclusiveMinimum\":0},\"far_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0},\"floor_y_m\":{\""
	+ "type\":\"number\",\"minimum\":-1000,\"maximum\":1000},\"target_shape\":{\"type\":\"string\",\"const\":\"sphere\"},\"collider_mat"
	+ "ches_visual_sphere\":{\"type\":\"boolean\",\"const\":true},\"wall_reference_distance_m\":{\"type\":\"number\",\"minimum\":-10"
	+ "00,\"maximum\":1000},\"world_art_geometry_noncolliding\":{\"type\":\"boolean\",\"const\":true}}},\"PhaseTransition\":{\"typ"
	+ "e\":\"object\",\"additionalProperties\":false,\"required\":[\"extra_time_s\",\"fade_s\",\"freeze_s\",\"preview_notice_s_befo"
	+ "re_boundary\",\"cursor_orientation\",\"boundary_contact_end_inclusive\",\"events_order\",\"kill_at_boundary_spawns_old"
	+ "_phase_replacement\",\"incomplete_phase_policy\"],\"properties\":{\"extra_time_s\":{\"type\":\"number\",\"const\":0},\"fade_"
	+ "s\":{\"type\":\"number\",\"const\":0},\"freeze_s\":{\"type\":\"number\",\"const\":0},\"preview_notice_s_before_boundary\":{\"typ"
	+ "e\":\"number\",\"minimum\":0,\"maximum\":3600},\"cursor_orientation\":{\"type\":\"string\",\"const\":\"preserve\"},\"boundary_co"
	+ "ntact_end_inclusive\":{\"type\":\"boolean\",\"const\":true},\"events_order\":{\"type\":\"array\",\"const\":[\"integrate_old_ph"
	+ "ase_contact_to_boundary\",\"apply_old_phase_kill_if_hp_reaches_zero_at_boundary\",\"close_old_phase_contact_metric"
	+ "s\",\"credit_old_phase_living_switch_partials\",\"censor_old_phase_unresolved_targets\",\"close_old_phase\",\"spawn_ne"
	+ "w_phase\",\"route_press_at_exact_boundary_to_new_phase\"]},\"kill_at_boundary_spawns_old_phase_replacement\":{\"type"
	+ "\":\"boolean\",\"const\":false},\"incomplete_phase_policy\":{\"type\":\"string\",\"const\":\"keep_descriptive_diagnostics_no"
	+ "_ranked_score\"}}},\"Aggregate\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"rank"
	+ "ed_program_score\",\"phase_scores_required\",\"fields\",\"do_not_average_phase_scores\"],\"properties\":{\"kind\":{\"type\""
	+ ":\"string\",\"const\":\"descriptive_only\"},\"ranked_program_score\":{\"type\":\"boolean\",\"const\":false},\"phase_scores_re"
	+ "quired\":{\"type\":\"boolean\",\"const\":true},\"fields\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":7,\"items\":{\"type\":\"st"
	+ "ring\",\"enum\":[\"accuracy\",\"censored\",\"completed_s\",\"expired\",\"hits\",\"misses\",\"opportunities\",\"shots\"]},\"uniqueI"
	+ "tems\":true},\"do_not_average_phase_scores\":{\"type\":\"boolean\",\"const\":true}}},{\"type\":\"object\",\"additionalProper"
	+ "ties\":false,\"required\":[\"kind\",\"ranked_program_score\",\"formula\",\"denominator_s\",\"phase_scores_required\",\"scale"
	+ "\",\"rank_key_suffix\",\"comparison_context_required\",\"invalid_if_any_phase_invalid\",\"partial_credit_at_every_phas"
	+ "e_boundary\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"sum_credited_switch_work_per_program_time\"},\"ranke"
	+ "d_program_score\":{\"type\":\"boolean\",\"const\":true},\"formula\":{\"type\":\"string\",\"const\":\"1000 * sum(phase.kills + "
	+ "phase.final_living_damage_fractions) / 60\"},\"denominator_s\":{\"type\":\"number\",\"const\":60},\"phase_scores_require"
	+ "d\":{\"type\":\"boolean\",\"const\":true},\"scale\":{\"type\":\"integer\",\"const\":1000},\"rank_key_suffix\":{\"type\":\"array\",\""
	+ "const\":[\"catalogue_revision\",\"program_id\",\"difficulty\"]},\"comparison_context_required\":{\"type\":\"boolean\",\"cons"
	+ "t\":true},\"invalid_if_any_phase_invalid\":{\"type\":\"boolean\",\"const\":true},\"partial_credit_at_every_phase_boundar"
	+ "y\":{\"type\":\"boolean\",\"const\":true}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"ranked_"
	+ "program_score\",\"formula\",\"nominal_denominator_s\",\"phase_scores_required\",\"scale\",\"rank_key_suffix\",\"comparison"
	+ "_context_required\",\"invalid_if_any_phase_invalid\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"time_weighte"
	+ "d_contact\"},\"ranked_program_score\":{\"type\":\"boolean\",\"const\":true},\"formula\":{\"type\":\"string\",\"const\":\"1000 * "
	+ "sum(phase.contact_s) / sum(phase.exposure_s)\"},\"nominal_denominator_s\":{\"type\":\"number\",\"const\":60},\"phase_sco"
	+ "res_required\":{\"type\":\"boolean\",\"const\":true},\"scale\":{\"type\":\"integer\",\"const\":1000},\"rank_key_suffix\":{\"type"
	+ "\":\"array\",\"const\":[\"catalogue_revision\",\"program_id\",\"difficulty\"]},\"comparison_context_required\":{\"type\":\"boo"
	+ "lean\",\"const\":true},\"invalid_if_any_phase_invalid\":{\"type\":\"boolean\",\"const\":true}}}]},\"Size\":{\"oneOf\":[{\"oneO"
	+ "f\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"mode\",\"reference_distance_m\",\"world_radius_m\",\""
	+ "shrink\",\"diameter_start_deg\",\"diameter_end_deg\",\"progress_curve\",\"progress_duration_s\"],\"properties\":{\"mode\":{"
	+ "\"type\":\"string\",\"const\":\"angular_diameter_constant\"},\"reference_distance_m\":{\"type\":\"number\",\"maximum\":1000,\"e"
	+ "xclusiveMinimum\":0},\"world_radius_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0},\"shrink\":{\"type\":\"b"
	+ "oolean\",\"const\":false},\"diameter_start_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"diameter_end_deg\":"
	+ "{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"progress_curve\":{\"type\":\"string\",\"const\":\"constant\"},\"progress"
	+ "_duration_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0}}},{\"type\":\"object\",\"additionalProperties\":f"
	+ "alse,\"required\":[\"mode\",\"reference_distance_m\",\"world_radius_m\",\"shrink\"],\"properties\":{\"mode\":{\"type\":\"string"
	+ "\",\"const\":\"angular_diameter_constant\"},\"reference_distance_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimu"
	+ "m\":0},\"world_radius_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0},\"shrink\":{\"type\":\"boolean\",\"const"
	+ "\":false}}}]},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"mode\",\"reference_distance_m\",\"world_ra"
	+ "dius_m\",\"shrink\",\"diameter_start_deg\",\"diameter_end_deg\",\"progress_curve\",\"progress_duration_s\",\"world_radius_"
	+ "end_m\"],\"properties\":{\"mode\":{\"type\":\"string\",\"const\":\"angular_diameter_linear_over_window\"},\"reference_distan"
	+ "ce_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0},\"world_radius_m\":{\"type\":\"number\",\"maximum\":1000,\""
	+ "exclusiveMinimum\":0},\"shrink\":{\"type\":\"boolean\",\"const\":true},\"diameter_start_deg\":{\"type\":\"number\",\"minimum\":"
	+ "-180,\"maximum\":180},\"diameter_end_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"progress_curve\":{\"type\""
	+ ":\"string\",\"const\":\"linear_in_angular_diameter\"},\"progress_duration_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusi"
	+ "veMinimum\":0},\"world_radius_end_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0}}},{\"type\":\"object\",\"a"
	+ "dditionalProperties\":false,\"required\":[\"mode\",\"reference_distance_m\",\"world_radius_m\",\"shrink\",\"reference_angu"
	+ "lar_diameter_deg\",\"minimum_apparent_diameter_deg\",\"maximum_apparent_diameter_deg\"],\"properties\":{\"mode\":{\"type"
	+ "\":\"string\",\"const\":\"world_radius_constant\"},\"reference_distance_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveM"
	+ "inimum\":0},\"world_radius_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0},\"shrink\":{\"type\":\"boolean\",\""
	+ "const\":false},\"reference_angular_diameter_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"minimum_apparen"
	+ "t_diameter_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"maximum_apparent_diameter_deg\":{\"type\":\"number"
	+ "\",\"minimum\":-180,\"maximum\":180}}}]},\"Envelope\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"cent"
	+ "er_yaw_deg\",\"center_pitch_deg\",\"center_distance_m\",\"minimum_floor_clearance_m\"],\"properties\":{\"center_yaw_deg\""
	+ ":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"center_pit"
	+ "ch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"cen"
	+ "ter_distance_m\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-1000,\"maximum\":1"
	+ "000}},\"minimum_floor_clearance_m\":{\"type\":\"number\",\"minimum\":-1000,\"maximum\":1000}}},\"Spawn\":{\"oneOf\":[{\"type\""
	+ ":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"tar"
	+ "get_slots\",\"minimum_silhouette_gap_deg\",\"initial_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angl"
	+ "e_deg\",\"exclude_live_reticle_on_initial_spawn\",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_limit\","
	+ "\"fallback\",\"nodes_yaw_pitch_deg\",\"initial_selection\",\"respawn_excludes_occupied_nodes\",\"respawn_excludes_just_"
	+ "hit_node\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"grid_without_overlap\"},\"coordinate_distribution\":{\"t"
	+ "ype\":\"string\",\"const\":\"uniform_eligible_grid_node\"},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items"
	+ "\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items"
	+ "\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\""
	+ "minimum_silhouette_gap_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{"
	+ "\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_a"
	+ "nchor\":{\"type\":\"string\",\"const\":\"previous_center_of_same_target_slot\"},\"transition_angle_deg\":{\"type\":\"array\","
	+ "\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_ini"
	+ "tial_spawn\":{\"type\":\"boolean\",\"const\":false},\"exclude_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":f"
	+ "alse},\"random_candidate_limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"a"
	+ "dditionalProperties\":false,\"required\":[\"kind\",\"no_candidate_policy\",\"relax_constraints\"],\"properties\":{\"kind\":"
	+ "{\"type\":\"string\",\"const\":\"not_needed_finite_eligible_nodes\"},\"no_candidate_policy\":{\"type\":\"string\",\"const\":\"i"
	+ "nvalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":false}}},\"nodes_yaw_pit"
	+ "ch_deg\":{\"type\":\"array\",\"minItems\":9,\"maxItems\":9,\"items\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\""
	+ "type\":\"number\",\"minimum\":-180,\"maximum\":180}}},\"initial_selection\":{\"type\":\"string\",\"const\":\"first_three_nodes"
	+ "_of_fisher_yates_permutation\"},\"respawn_excludes_occupied_nodes\":{\"type\":\"boolean\",\"const\":true},\"respawn_excl"
	+ "udes_just_hit_node\":{\"type\":\"boolean\",\"const\":true}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\""
	+ ":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"target_slots\",\"minimum_silhouette_gap_deg\",\"initial_"
	+ "reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angle_deg\",\"exclude_live_reticle_on_initial_spawn\",\"e"
	+ "xclude_live_reticle_on_hit_respawn\",\"random_candidate_limit\",\"fallback\",\"chambers\",\"motion_state_sampled_once_"
	+ "before_position_search\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"one_target_per_chamber\"},\"coordinate_d"
	+ "istribution\":{\"type\":\"string\",\"const\":\"sample_initial_flight_age_and_direction_once_then_uniform_chamber_yaw\"}"
	+ ",\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\""
	+ "pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\""
	+ "target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"minimum_silhouette_gap_deg\":{\"type\":\"number\",\"minim"
	+ "um\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\""
	+ "type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_anchor\":{\"type\":\"string\",\"const\":\"previous_center_of"
	+ "_same_target_slot\"},\"transition_angle_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\","
	+ "\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_initial_spawn\":{\"type\":\"boolean\",\"const\":false},\"exclu"
	+ "de_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":false},\"random_candidate_limit\":{\"type\":\"integer\",\"m"
	+ "inimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"yaw_"
	+ "step_deg\",\"no_candidate_policy\",\"relax_constraints\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_yaw_"
	+ "lattice_minimum_hash\"},\"yaw_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"no_candidate_policy\":{\"t"
	+ "ype\":\"string\",\"const\":\"invalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\""
	+ ":false}}},\"chambers\":{\"type\":\"array\",\"minItems\":4,\"maxItems\":4,\"items\":{\"type\":\"object\",\"additionalProperties\""
	+ ":false,\"required\":[\"slot\",\"yaw_deg\",\"baseline_pitch_deg\"],\"properties\":{\"slot\":{\"type\":\"integer\",\"minimum\":0,\""
	+ "maximum\":15},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maxi"
	+ "mum\":180}},\"baseline_pitch_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}}}},\"motion_state_sampled_once_b"
	+ "efore_position_search\":{\"type\":\"boolean\",\"const\":true}}},{\"type\":\"object\",\"additionalProperties\":false,\"requir"
	+ "ed\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"target_slots\",\"minimum_silhouette_gap_deg\",\"initi"
	+ "al_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angle_deg\",\"exclude_live_reticle_on_initial_spawn\""
	+ ",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_limit\",\"fallback\",\"lane_pitch_deg\",\"motion_state_samp"
	+ "led_once_before_position_search\",\"candidate_yaw_deg\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"one_targe"
	+ "t_per_lane\"},\"coordinate_distribution\":{\"type\":\"string\",\"enum\":[\"sample_cycle_fraction_conditioned_on_spawn_co"
	+ "nstraints\",\"sample_motion_state_then_condition_initial_yaw_on_spawn_constraints\"]},\"yaw_deg\":{\"type\":\"array\",\""
	+ "minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\""
	+ "minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"target_slots\":{\"type\":\"integ"
	+ "er\",\"minimum\":1,\"maximum\":16},\"minimum_silhouette_gap_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"ini"
	+ "tial_reference_yaw_pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-18"
	+ "0,\"maximum\":180}},\"transition_anchor\":{\"type\":\"string\",\"const\":\"previous_center_of_same_target_slot\"},\"transit"
	+ "ion_angle_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180"
	+ "}},\"exclude_live_reticle_on_initial_spawn\":{\"type\":\"boolean\",\"const\":false},\"exclude_live_reticle_on_hit_respa"
	+ "wn\":{\"type\":\"boolean\",\"const\":false},\"random_candidate_limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000}"
	+ ",\"fallback\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"fraction_bins\",\"no_can"
	+ "didate_policy\",\"relax_constraints\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_cycle_fraction_lattic"
	+ "e_minimum_hash\"},\"fraction_bins\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"no_candidate_policy\":{\"type"
	+ "\":\"string\",\"const\":\"invalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":fa"
	+ "lse}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"yaw_step_deg\",\"no_candidate_policy\",\""
	+ "relax_constraints\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_yaw_lattice_minimum_hash\"},\"yaw_step_"
	+ "deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"no_candidate_policy\":{\"type\":\"string\",\"const\":\"invalidate"
	+ "_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":false}}}]},\"lane_pitch_deg\":{\"ty"
	+ "pe\":\"array\",\"minItems\":4,\"maxItems\":4,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"motion_state_sa"
	+ "mpled_once_before_position_search\":{\"type\":\"boolean\",\"const\":true},\"candidate_yaw_deg\":{\"type\":\"array\",\"minIte"
	+ "ms\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}}}},{\"oneOf\":[{\"type\":\"object\",\"addit"
	+ "ionalProperties\":false,\"required\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"target_slots\",\"mini"
	+ "mum_silhouette_gap_deg\",\"initial_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angle_deg\",\"exclude_"
	+ "live_reticle_on_initial_spawn\",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_limit\",\"fallback\",\"tran"
	+ "sition_band_bag\",\"annulus_azimuth_rad_uniform\",\"annulus_radial_distribution\"],\"properties\":{\"kind\":{\"type\":\"st"
	+ "ring\",\"const\":\"replace_on_hit\"},\"coordinate_distribution\":{\"type\":\"string\",\"const\":\"uniform_solid_angle_spheri"
	+ "cal_annulus_then_envelope_rejection\"},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"num"
	+ "ber\",\"minimum\":-180,\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"num"
	+ "ber\",\"minimum\":-180,\"maximum\":180}},\"target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"minimum_silhou"
	+ "ette_gap_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{\"type\":\"array\""
	+ ",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_anchor\":{\"type\""
	+ ":\"string\",\"const\":\"previous_center_of_same_target_slot\"},\"transition_angle_deg\":{\"type\":\"array\",\"minItems\":2,\""
	+ "maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_initial_spawn\":{\""
	+ "type\":\"boolean\",\"const\":false},\"exclude_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":false},\"random_"
	+ "candidate_limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"additionalPrope"
	+ "rties\":false,\"required\":[\"kind\",\"yaw_step_deg\",\"pitch_step_deg\",\"enumeration\",\"no_candidate_policy\",\"relax_con"
	+ "straints\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_lattice_minimum_hash\"},\"yaw_step_deg\":{\"type\":"
	+ "\"number\",\"minimum\":-180,\"maximum\":180},\"pitch_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"enumer"
	+ "ation\":{\"type\":\"string\",\"const\":\"ascending_yaw_then_ascending_pitch\"},\"no_candidate_policy\":{\"type\":\"string\",\""
	+ "const\":\"invalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":false}}},\"tran"
	+ "sition_band_bag\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"draw_count\",\"bands\",\"interval_rule"
	+ "\",\"shuffle\",\"refill\"],\"properties\":{\"draw_count\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"bands\":{\"ty"
	+ "pe\":\"array\",\"minItems\":3,\"maxItems\":3,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"angle"
	+ "_deg\",\"copies\"],\"properties\":{\"angle_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\""
	+ "minimum\":-180,\"maximum\":180}},\"copies\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000}}}},\"interval_rule\":{\"t"
	+ "ype\":\"string\",\"const\":\"lower_inclusive_upper_exclusive_except_final_upper_inclusive\"},\"shuffle\":{\"type\":\"strin"
	+ "g\",\"const\":\"fisher_yates_unbiased\"},\"refill\":{\"type\":\"string\",\"const\":\"only_when_empty\"}}},\"annulus_azimuth_ra"
	+ "d_uniform\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6.28318530"
	+ "73}},\"annulus_radial_distribution\":{\"type\":\"string\",\"const\":\"uniform_cosine_of_angular_distance\"}}},{\"type\":\"o"
	+ "bject\",\"additionalProperties\":false,\"required\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"target"
	+ "_slots\",\"minimum_silhouette_gap_deg\",\"initial_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angle_d"
	+ "eg\",\"exclude_live_reticle_on_initial_spawn\",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_limit\",\"fa"
	+ "llback\",\"annulus_azimuth_rad_uniform\",\"annulus_radial_distribution\"],\"properties\":{\"kind\":{\"type\":\"string\",\"co"
	+ "nst\":\"replace_on_hit\"},\"coordinate_distribution\":{\"type\":\"string\",\"const\":\"uniform_solid_angle_spherical_annul"
	+ "us_then_envelope_rejection\"},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"min"
	+ "imum\":-180,\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"min"
	+ "imum\":-180,\"maximum\":180}},\"target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"minimum_silhouette_gap_"
	+ "deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{\"type\":\"array\",\"minItem"
	+ "s\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_anchor\":{\"type\":\"string\""
	+ ",\"const\":\"previous_center_of_same_target_slot\"},\"transition_angle_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\""
	+ ":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_initial_spawn\":{\"type\":\"bo"
	+ "olean\",\"const\":false},\"exclude_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":false},\"random_candidate"
	+ "_limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"additionalProperties\":fa"
	+ "lse,\"required\":[\"kind\",\"yaw_step_deg\",\"pitch_step_deg\",\"enumeration\",\"no_candidate_policy\",\"relax_constraints\""
	+ "],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_lattice_minimum_hash\"},\"yaw_step_deg\":{\"type\":\"number\","
	+ "\"minimum\":-180,\"maximum\":180},\"pitch_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"enumeration\":{\""
	+ "type\":\"string\",\"const\":\"ascending_yaw_then_ascending_pitch\"},\"no_candidate_policy\":{\"type\":\"string\",\"const\":\"i"
	+ "nvalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":false}}},\"annulus_azimu"
	+ "th_rad_uniform\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6.283"
	+ "1853073}},\"annulus_radial_distribution\":{\"type\":\"string\",\"const\":\"uniform_cosine_of_angular_distance\"}}},{\"typ"
	+ "e\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"t"
	+ "arget_slots\",\"minimum_silhouette_gap_deg\",\"initial_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_an"
	+ "gle_deg\",\"exclude_live_reticle_on_initial_spawn\",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_limit"
	+ "\",\"fallback\",\"minimum_equal_size_center_separation_deg\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"replac"
	+ "e_on_hit\"},\"coordinate_distribution\":{\"type\":\"string\",\"const\":\"uniform_solid_angle_within_yaw_pitch_rectangle\""
	+ "},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},"
	+ "\"pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},"
	+ "\"target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"minimum_silhouette_gap_deg\":{\"type\":\"number\",\"mini"
	+ "mum\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{"
	+ "\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_anchor\":{\"type\":\"string\",\"const\":\"previous_center_o"
	+ "f_same_target_slot\"},\"transition_angle_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\""
	+ ",\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_initial_spawn\":{\"type\":\"boolean\",\"const\":false},\"excl"
	+ "ude_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":false},\"random_candidate_limit\":{\"type\":\"integer\",\""
	+ "minimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"yaw"
	+ "_step_deg\",\"pitch_step_deg\",\"enumeration\",\"no_candidate_policy\",\"relax_constraints\"],\"properties\":{\"kind\":{\"ty"
	+ "pe\":\"string\",\"const\":\"valid_lattice_minimum_hash\"},\"yaw_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":18"
	+ "0},\"pitch_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"enumeration\":{\"type\":\"string\",\"const\":\"asc"
	+ "ending_yaw_then_ascending_pitch\"},\"no_candidate_policy\":{\"type\":\"string\",\"const\":\"invalidate_run_spawn_constra"
	+ "int_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":false}}},\"minimum_equal_size_center_separation_deg"
	+ "\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}}}]},{\"type\":\"object\",\"additionalProperties\":false,\"required\":"
	+ "[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"target_slots\",\"minimum_silhouette_gap_deg\",\"initial_r"
	+ "eference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angle_deg\",\"exclude_live_reticle_on_initial_spawn\",\"ex"
	+ "clude_live_reticle_on_hit_respawn\",\"random_candidate_limit\",\"fallback\"],\"properties\":{\"kind\":{\"type\":\"string\","
	+ "\"const\":\"replace_on_kill\"},\"coordinate_distribution\":{\"type\":\"string\",\"const\":\"uniform_solid_angle_within_yaw_"
	+ "pitch_rectangle\"},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,"
	+ "\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,"
	+ "\"maximum\":180}},\"target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"minimum_silhouette_gap_deg\":{\"type"
	+ "\":\"number\",\"minimum\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxIt"
	+ "ems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_anchor\":{\"type\":\"string\",\"const\":\"p"
	+ "revious_center_of_same_target_slot\"},\"transition_angle_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":"
	+ "{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_initial_spawn\":{\"type\":\"boolean\",\"con"
	+ "st\":false},\"exclude_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":false},\"random_candidate_limit\":{\"t"
	+ "ype\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"additionalProperties\":false,\"requir"
	+ "ed\":[\"kind\",\"yaw_step_deg\",\"pitch_step_deg\",\"enumeration\",\"no_candidate_policy\",\"relax_constraints\"],\"properti"
	+ "es\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_lattice_minimum_hash\"},\"yaw_step_deg\":{\"type\":\"number\",\"minimum\":-"
	+ "180,\"maximum\":180},\"pitch_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"enumeration\":{\"type\":\"stri"
	+ "ng\",\"const\":\"ascending_yaw_then_ascending_pitch\"},\"no_candidate_policy\":{\"type\":\"string\",\"const\":\"invalidate_r"
	+ "un_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":false}}}}},{\"type\":\"object\",\"addit"
	+ "ionalProperties\":false,\"required\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\",\"target_slots\",\"mini"
	+ "mum_silhouette_gap_deg\",\"initial_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition_angle_deg\",\"exclude_"
	+ "live_reticle_on_initial_spawn\",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_limit\",\"fallback\",\"sche"
	+ "dule\",\"annulus_azimuth_rad_uniform\",\"annulus_radial_distribution\"],\"properties\":{\"kind\":{\"type\":\"string\",\"cons"
	+ "t\":\"scheduled_single\"},\"coordinate_distribution\":{\"type\":\"string\",\"const\":\"uniform_solid_angle_spherical_annul"
	+ "us_then_envelope_rejection\"},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"min"
	+ "imum\":-180,\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"min"
	+ "imum\":-180,\"maximum\":180}},\"target_slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"minimum_silhouette_gap_"
	+ "deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"initial_reference_yaw_pitch_deg\":{\"type\":\"array\",\"minItem"
	+ "s\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"transition_anchor\":{\"type\":\"string\""
	+ ",\"const\":\"previous_scheduled_opportunity_center_or_neutral_reference\"},\"transition_angle_deg\":{\"type\":\"array\","
	+ "\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"exclude_live_reticle_on_ini"
	+ "tial_spawn\":{\"type\":\"boolean\",\"const\":false},\"exclude_live_reticle_on_hit_respawn\":{\"type\":\"boolean\",\"const\":f"
	+ "alse},\"random_candidate_limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"fallback\":{\"type\":\"object\",\"a"
	+ "dditionalProperties\":false,\"required\":[\"kind\",\"yaw_step_deg\",\"pitch_step_deg\",\"enumeration\",\"no_candidate_poli"
	+ "cy\",\"relax_constraints\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"valid_lattice_minimum_hash\"},\"yaw_step"
	+ "_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"pitch_step_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum"
	+ "\":180},\"enumeration\":{\"type\":\"string\",\"const\":\"ascending_yaw_then_ascending_pitch\"},\"no_candidate_policy\":{\"ty"
	+ "pe\":\"string\",\"const\":\"invalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boolean\",\"const\":"
	+ "false}}},\"schedule\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"slots\",\"slot_duration_s\",\"first"
	+ "_slot_start_s\",\"onset_delay_uniform_s\",\"schedule_depends_on_hits\",\"generation_rule\",\"precompile_all_positions_"
	+ "and_onsets\"],\"properties\":{\"slots\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"slot_duration_s\":{\"type\":"
	+ "\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"first_slot_start_s\":{\"type\":\"number\",\"const\":0},\"onset_delay_un"
	+ "iform_s\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}},\"sche"
	+ "dule_depends_on_hits\":{\"type\":\"boolean\",\"const\":false},\"generation_rule\":{\"type\":\"string\",\"const\":\"opportunity"
	+ "_index_equals_slot_index\"},\"precompile_all_positions_and_onsets\":{\"type\":\"boolean\",\"const\":true}}},\"annulus_az"
	+ "imuth_rad_uniform\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6."
	+ "2831853073}},\"annulus_radial_distribution\":{\"type\":\"string\",\"const\":\"uniform_cosine_of_angular_distance\"}}},{\""
	+ "type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"coordinate_distribution\",\"yaw_deg\",\"pitch_deg\""
	+ ",\"target_slots\",\"minimum_silhouette_gap_deg\",\"initial_reference_yaw_pitch_deg\",\"transition_anchor\",\"transition"
	+ "_angle_deg\",\"exclude_live_reticle_on_initial_spawn\",\"exclude_live_reticle_on_hit_respawn\",\"random_candidate_li"
	+ "mit\",\"fallback\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"trajectory_initial_state\"},\"coordinate_distrib"
	+ "ution\":{\"type\":\"string\",\"const\":\"sample_initial_state_of_motion_model\"},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2"
	+ ",\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"pitch_deg\":{\"type\":\"array\",\"minItems\":2"
	+ ",\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"target_slots\":{\"type\":\"integer\",\"minimu"
	+ "m\":1,\"maximum\":16},\"minimum_silhouette_gap_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"initial_refere"
	+ "nce_yaw_pitch_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\""
	+ ":180}},\"transition_anchor\":{\"type\":\"string\",\"const\":\"previous_center_of_same_target_slot\"},\"transition_angle_d"
	+ "eg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"exclude"
	+ "_live_reticle_on_initial_spawn\":{\"type\":\"boolean\",\"const\":false},\"exclude_live_reticle_on_hit_respawn\":{\"type\""
	+ ":\"boolean\",\"const\":false},\"random_candidate_limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"fallback\""
	+ ":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"no_candidate_policy\",\"relax_constraints\"],\""
	+ "properties\":{\"kind\":{\"type\":\"string\",\"const\":\"not_needed_unconstrained_trajectory_initial_state\"},\"no_candidat"
	+ "e_policy\":{\"type\":\"string\",\"const\":\"invalidate_run_spawn_constraint_failure\"},\"relax_constraints\":{\"type\":\"boo"
	+ "lean\",\"const\":false}}}}}]},\"Lifecycle\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"ki"
	+ "nd\",\"ttl_s\",\"respawn_delay_s\",\"phase_end_outcome\",\"generation_index_starts_at\",\"spawn_is_hittable_after\",\"on_h"
	+ "it\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"persistent\"},\"ttl_s\":{\"type\":\"null\"},\"respawn_delay_s\":{\"t"
	+ "ype\":\"number\",\"const\":0},\"phase_end_outcome\":{\"type\":\"string\",\"const\":\"censored_phase\"},\"generation_index_star"
	+ "ts_at\":{\"type\":\"integer\",\"const\":0},\"spawn_is_hittable_after\":{\"type\":\"string\",\"const\":\"first_rendered_frame\"}"
	+ ",\"on_hit\":{\"type\":\"string\",\"const\":\"continue\"}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"ki"
	+ "nd\",\"ttl_s\",\"respawn_delay_s\",\"phase_end_outcome\",\"generation_index_starts_at\",\"spawn_is_hittable_after\",\"on_h"
	+ "it\",\"ttl_origin\",\"on_expiry\",\"exclusive_final_outcomes\",\"shot_at_exact_expiry\",\"unsuccessful_window_counts_onc"
	+ "e\",\"first_rendered_frame_at_or_after_deadline\",\"human_miss_on_nonpresented_opportunity\"],\"properties\":{\"kind\":"
	+ "{\"type\":\"string\",\"const\":\"scheduled_window\"},\"ttl_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"re"
	+ "spawn_delay_s\":{\"type\":\"number\",\"const\":0},\"phase_end_outcome\":{\"type\":\"string\",\"const\":\"censored_phase\"},\"gen"
	+ "eration_index_starts_at\":{\"type\":\"integer\",\"const\":0},\"spawn_is_hittable_after\":{\"type\":\"string\",\"const\":\"firs"
	+ "t_rendered_frame\"},\"on_hit\":{\"type\":\"string\",\"const\":\"remove_until_next_scheduled_slot\"},\"ttl_origin\":{\"type\":"
	+ "\"string\",\"const\":\"scheduled_spawn_time\"},\"on_expiry\":{\"type\":\"string\",\"const\":\"remove_until_next_scheduled_slo"
	+ "t\"},\"exclusive_final_outcomes\":{\"type\":\"array\",\"const\":[\"hit\",\"expired\",\"censored_phase\",\"censored_technical\"]"
	+ "},\"shot_at_exact_expiry\":{\"type\":\"string\",\"const\":\"not_eligible\"},\"unsuccessful_window_counts_once\":{\"type\":\"b"
	+ "oolean\",\"const\":true},\"first_rendered_frame_at_or_after_deadline\":{\"type\":\"string\",\"const\":\"render_failure_non"
	+ "rendered_opportunity_invalid_for_comparison\"},\"human_miss_on_nonpresented_opportunity\":{\"type\":\"boolean\",\"cons"
	+ "t\":false}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"ttl_s\",\"respawn_delay_s\",\"phase_"
	+ "end_outcome\",\"generation_index_starts_at\",\"spawn_is_hittable_after\",\"on_hit\",\"hp_max\",\"hp_regeneration_per_s\","
	+ "\"partial_hp_persists_until\",\"ideal_contact_time_to_kill_s\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"unt"
	+ "il_contact_kill\"},\"ttl_s\":{\"type\":\"null\"},\"respawn_delay_s\":{\"type\":\"number\",\"const\":0},\"phase_end_outcome\":{\""
	+ "type\":\"string\",\"const\":\"censored_phase\"},\"generation_index_starts_at\":{\"type\":\"integer\",\"const\":0},\"spawn_is_h"
	+ "ittable_after\":{\"type\":\"string\",\"const\":\"first_rendered_frame\"},\"on_hit\":{\"type\":\"string\",\"const\":\"remove_and_"
	+ "replace_same_slot\"},\"hp_max\":{\"type\":\"number\",\"minimum\":-1000000000000.0,\"maximum\":1000000000000.0},\"hp_regene"
	+ "ration_per_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"partial_hp_persists_until\":{\"type\":\"string\",\"const"
	+ "\":\"kill_or_phase_close\"},\"ideal_contact_time_to_kill_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}}},{\"type\""
	+ ":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"ttl_s\",\"respawn_delay_s\",\"phase_end_outcome\",\"gener"
	+ "ation_index_starts_at\",\"spawn_is_hittable_after\",\"on_hit\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"unti"
	+ "l_hit\"},\"ttl_s\":{\"type\":\"null\"},\"respawn_delay_s\":{\"type\":\"number\",\"const\":0},\"phase_end_outcome\":{\"type\":\"str"
	+ "ing\",\"const\":\"censored_phase\"},\"generation_index_starts_at\":{\"type\":\"integer\",\"const\":0},\"spawn_is_hittable_af"
	+ "ter\":{\"type\":\"string\",\"const\":\"first_rendered_frame\"},\"on_hit\":{\"type\":\"string\",\"const\":\"remove_and_replace_sa"
	+ "me_slot\"}}}]},\"Fire\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"mode\",\"max_targets_p"
	+ "er_press\",\"press_cooldown_s\",\"hold_repeat_for_click\",\"damage_per_s\"],\"properties\":{\"mode\":{\"type\":\"string\",\"co"
	+ "nst\":\"automatic_contact_measurement\"},\"max_targets_per_press\":{\"type\":\"integer\",\"const\":1},\"press_cooldown_s\":"
	+ "{\"type\":\"number\",\"const\":0},\"hold_repeat_for_click\":{\"type\":\"boolean\",\"const\":false},\"damage_per_s\":{\"type\":\"n"
	+ "umber\",\"minimum\":0,\"maximum\":3600}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"mode\",\"max_tar"
	+ "gets_per_press\",\"press_cooldown_s\",\"hold_repeat_for_click\",\"damage_per_s\"],\"properties\":{\"mode\":{\"type\":\"strin"
	+ "g\",\"const\":\"hold_continuous_damage\"},\"max_targets_per_press\":{\"type\":\"integer\",\"const\":1},\"press_cooldown_s\":{"
	+ "\"type\":\"number\",\"const\":0},\"hold_repeat_for_click\":{\"type\":\"boolean\",\"const\":false},\"damage_per_s\":{\"type\":\"nu"
	+ "mber\",\"minimum\":0,\"maximum\":3600}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"mode\",\"max_targ"
	+ "ets_per_press\",\"press_cooldown_s\",\"hold_repeat_for_click\",\"damage_per_s\"],\"properties\":{\"mode\":{\"type\":\"string"
	+ "\",\"const\":\"press_edge\"},\"max_targets_per_press\":{\"type\":\"integer\",\"const\":1},\"press_cooldown_s\":{\"type\":\"numbe"
	+ "r\",\"const\":0},\"hold_repeat_for_click\":{\"type\":\"boolean\",\"const\":false},\"damage_per_s\":{\"type\":\"number\",\"minimu"
	+ "m\":0,\"maximum\":3600}}}]},\"Motion\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\""
	+ "chambers\",\"apex_height_above_baseline_deg\",\"flight_duration_s\",\"launch_pitch_velocity_deg_s\",\"pitch_accelerati"
	+ "on_deg_s2\",\"yaw_speed_deg_s\",\"ground_rest_uniform_s\",\"yaw_continues_during_ground_rest\",\"initial_flight_age_un"
	+ "iform_s\",\"initial_direction_prob_positive\",\"landing_flip_probability\",\"wall_reflection\",\"simultaneous_wall_and"
	+ "_landing\",\"finite_acceleration_limit_applies_at_impulse\",\"no_rng_in_frame_loop\",\"event_tape_horizon_s\"],\"prope"
	+ "rties\":{\"kind\":{\"type\":\"string\",\"const\":\"angular_bounce\"},\"chambers\":{\"type\":\"array\",\"minItems\":4,\"maxItems\":4"
	+ ",\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"slot\",\"yaw_deg\",\"baseline_pitch_deg\"],\"pro"
	+ "perties\":{\"slot\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":15},\"yaw_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\""
	+ ":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"baseline_pitch_deg\":{\"type\":\"number\",\"minimum\":-18"
	+ "0,\"maximum\":180}}}},\"apex_height_above_baseline_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"flight_du"
	+ "ration_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"launch_pitch_velocity_deg_s\":{\"type\":\"number\""
	+ ",\"minimum\":0,\"maximum\":3600},\"pitch_acceleration_deg_s2\":{\"type\":\"number\",\"minimum\":-100000,\"maximum\":100000},"
	+ "\"yaw_speed_deg_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"ground_rest_uniform_s\":{\"type\":\"array"
	+ "\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}},\"yaw_continues_during_ground"
	+ "_rest\":{\"type\":\"boolean\",\"const\":true},\"initial_flight_age_uniform_s\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":"
	+ "2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}},\"initial_direction_prob_positive\":{\"type\":\"number\",\"mi"
	+ "nimum\":0,\"maximum\":1},\"landing_flip_probability\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"wall_reflection\":{"
	+ "\"type\":\"string\",\"const\":\"instantaneous_inward_yaw_velocity\"},\"simultaneous_wall_and_landing\":{\"type\":\"string\","
	+ "\"const\":\"draw_landing_flip_then_enforce_inward_wall_direction\"},\"finite_acceleration_limit_applies_at_impulse\""
	+ ":{\"type\":\"boolean\",\"const\":false},\"no_rng_in_frame_loop\":{\"type\":\"boolean\",\"const\":true},\"event_tape_horizon_s"
	+ "\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"ki"
	+ "nd\",\"yaw_amplitude_deg\",\"pitch_amplitude_deg\",\"formula\",\"path_angular_speed_deg_s\",\"initial_arc_fraction_unifo"
	+ "rm\",\"direction_prob_positive\",\"acceleration_validation_limit_deg_s2\",\"arc_length_solver\"],\"properties\":{\"kind\""
	+ ":{\"type\":\"string\",\"const\":\"angular_ellipse\"},\"yaw_amplitude_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180"
	+ "},\"pitch_amplitude_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"formula\":{\"type\":\"string\",\"const\":\"yaw"
	+ "_deg = 16 * cos(q); pitch_deg = 10 * sin(q)\"},\"path_angular_speed_deg_s\":{\"type\":\"number\",\"maximum\":3600,\"excl"
	+ "usiveMinimum\":0},\"initial_arc_fraction_uniform\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"num"
	+ "ber\",\"minimum\":0,\"maximum\":1}},\"direction_prob_positive\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"accelerati"
	+ "on_validation_limit_deg_s2\":{\"type\":\"number\",\"minimum\":-100000,\"maximum\":100000},\"arc_length_solver\":{\"type\":\""
	+ "object\",\"additionalProperties\":false,\"required\":[\"metric\",\"lut_cells\",\"cell_quadrature\",\"inverse\",\"absolute_ar"
	+ "c_error_rad\",\"max_inverse_iterations\",\"relative_speed_error_validation_limit\"],\"properties\":{\"metric\":{\"type\":"
	+ "\"string\",\"const\":\"sqrt(cos(pitch_rad)^2 * dyaw_rad_dq^2 + dpitch_rad_dq^2)\"},\"lut_cells\":{\"type\":\"integer\",\"mi"
	+ "nimum\":1,\"maximum\":1000000},\"cell_quadrature\":{\"type\":\"string\",\"const\":\"simpson_three_points\"},\"inverse\":{\"typ"
	+ "e\":\"string\",\"const\":\"bracketed_newton\"},\"absolute_arc_error_rad\":{\"type\":\"number\",\"minimum\":-1000000000000.0,\""
	+ "maximum\":1000000000000.0},\"max_inverse_iterations\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"relative_"
	+ "speed_error_validation_limit\":{\"type\":\"number\",\"minimum\":-1000000000000.0,\"maximum\":1000000000000.0}}}}},{\"typ"
	+ "e\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"yaw_amplitude_deg\",\"yaw_omega_rad_s\",\"pitch_ampli"
	+ "tude_deg\",\"pitch_omega_rad_s\",\"distance_center_m\",\"distance_amplitude_m\",\"distance_omega_rad_s\",\"initial_phase"
	+ "_rad_uniform\",\"phase_count\",\"phases_independent\",\"angular_speed_upper_bound_deg_s\",\"radial_speed_max_m_s\",\"rad"
	+ "ial_acceleration_max_m_s2\",\"no_respawn_during_phase\",\"no_screen_size_compensation\"],\"properties\":{\"kind\":{\"typ"
	+ "e\":\"string\",\"const\":\"depth_sines\"},\"yaw_amplitude_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"yaw_ome"
	+ "ga_rad_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"pitch_amplitude_deg\":{\"type\":\"number\",\"minimu"
	+ "m\":-180,\"maximum\":180},\"pitch_omega_rad_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"distance_cen"
	+ "ter_m\":{\"type\":\"number\",\"minimum\":-1000,\"maximum\":1000},\"distance_amplitude_m\":{\"type\":\"number\",\"minimum\":-100"
	+ "0,\"maximum\":1000},\"distance_omega_rad_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"initial_phase_"
	+ "rad_uniform\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6.283185"
	+ "3073}},\"phase_count\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000000},\"phases_independent\":{\"type\":\"boolean\",\""
	+ "const\":true},\"angular_speed_upper_bound_deg_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"radial_speed_max_"
	+ "m_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"radial_acceleration_max_m_s2\":{\"type\":\"number\",\"minimum\":-1"
	+ "000000000000.0,\"maximum\":1000000000000.0},\"no_respawn_during_phase\":{\"type\":\"boolean\",\"const\":true},\"no_screen"
	+ "_size_compensation\":{\"type\":\"boolean\",\"const\":true}}},{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,"
	+ "\"required\":[\"kind\",\"yaw_bounds_deg\",\"lanes_pitch_deg\",\"yaw_speed_deg_s\",\"initial_yaw_uniform_deg\",\"initial_dir"
	+ "ection_prob_positive\",\"reflection\",\"vertical_motion\",\"finite_acceleration_limit_applies\"],\"properties\":{\"kind\""
	+ ":{\"type\":\"string\",\"const\":\"linear_reflect\"},\"yaw_bounds_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\""
	+ ":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"lanes_pitch_deg\":{\"type\":\"array\",\"minItems\":4,\"maxItems\":4,\""
	+ "items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"yaw_speed_deg_s\":{\"type\":\"number\",\"maximum\":3600,\"excl"
	+ "usiveMinimum\":0},\"initial_yaw_uniform_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\","
	+ "\"minimum\":-180,\"maximum\":180}},\"initial_direction_prob_positive\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"re"
	+ "flection\":{\"type\":\"string\",\"const\":\"instantaneous_velocity_sign_change\"},\"vertical_motion\":{\"type\":\"string\",\"c"
	+ "onst\":\"none\"},\"finite_acceleration_limit_applies\":{\"type\":\"boolean\",\"const\":false}}},{\"type\":\"object\",\"additio"
	+ "nalProperties\":false,\"required\":[\"kind\",\"reflection\",\"yaw_bounds_deg\",\"lanes_pitch_deg\",\"yaw_speed_deg_s\",\"tur"
	+ "n_duration_s\",\"turn_entry_inset_deg\",\"straight_segment_duration_s\",\"period_s\",\"peak_yaw_acceleration_deg_s2\",\""
	+ "initial_cycle_fraction_uniform\",\"initial_direction_prob_positive\",\"vertical_motion\",\"finite_acceleration_limit"
	+ "_applies\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"linear_reflect\"},\"reflection\":{\"type\":\"string\",\"cons"
	+ "t\":\"symmetric_cubic_smoothstep_velocity\"},\"yaw_bounds_deg\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{"
	+ "\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"lanes_pitch_deg\":{\"type\":\"array\",\"minItems\":4,\"maxItems\":4,\"it"
	+ "ems\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"yaw_speed_deg_s\":{\"type\":\"number\",\"maximum\":3600,\"exclus"
	+ "iveMinimum\":0},\"turn_duration_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"turn_entry_inset_deg\":{\"type\":\""
	+ "number\",\"minimum\":-180,\"maximum\":180},\"straight_segment_duration_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":360"
	+ "0},\"period_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"peak_yaw_acceleration_deg_s2\":{\"type\":\"nu"
	+ "mber\",\"minimum\":-100000,\"maximum\":100000},\"initial_cycle_fraction_uniform\":{\"type\":\"array\",\"minItems\":2,\"maxIt"
	+ "ems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1}},\"initial_direction_prob_positive\":{\"type\":\"number\",\""
	+ "minimum\":0,\"maximum\":1},\"vertical_motion\":{\"type\":\"string\",\"const\":\"none\"},\"finite_acceleration_limit_applies\""
	+ ":{\"type\":\"boolean\",\"const\":true}}}]},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"axis\",\""
	+ "yaw_bounds_deg\",\"lanes_pitch_deg\",\"yaw_speed_abs_deg_s\",\"initial_yaw_distribution\",\"initial_direction_prob_pos"
	+ "itive\",\"initial_velocity\",\"direction_flip_probability\",\"plateau_duration_mixture\",\"plateau_begins\",\"velocity_t"
	+ "ransition\",\"boundary\",\"vertical\",\"nominal_full_angular_speed_upper_bound_deg_s\",\"event_tape\"],\"properties\":{\"k"
	+ "ind\":{\"type\":\"string\",\"const\":\"reactive_axis\"},\"axis\":{\"type\":\"string\",\"const\":\"yaw\"},\"yaw_bounds_deg\":{\"type\""
	+ ":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"lanes_pitch_deg\":{"
	+ "\"type\":\"array\",\"minItems\":1,\"maxItems\":1,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"yaw_speed_ab"
	+ "s_deg_s\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}},\"init"
	+ "ial_yaw_distribution\":{\"type\":\"string\",\"const\":\"uniform_inside_soft_turn_thresholds\"},\"initial_direction_prob_"
	+ "positive\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"initial_velocity\":{\"type\":\"string\",\"const\":\"sampled_full_"
	+ "signed_speed\"},\"direction_flip_probability\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"plateau_duration_mixtur"
	+ "e\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":2,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":"
	+ "[\"weight\",\"uniform_duration_s\"],\"properties\":{\"weight\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"uniform_dura"
	+ "tion_s\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}}}}},\"pl"
	+ "ateau_begins\":{\"type\":\"string\",\"const\":\"after_velocity_transition_finishes\"},\"velocity_transition\":{\"type\":\"ob"
	+ "ject\",\"additionalProperties\":false,\"required\":[\"kind\",\"nominal_duration_s\",\"duration_formula\",\"acceleration_li"
	+ "mit_deg_s2\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"cubic_smoothstep_velocity\"},\"nominal_duration_s\":{"
	+ "\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"duration_formula\":{\"type\":\"string\",\"const\":\"max(nominal_"
	+ "duration_s, 1.5 * abs(v1 - v0) / acceleration_limit_deg_s2)\"},\"acceleration_limit_deg_s2\":{\"type\":\"number\",\"ma"
	+ "ximum\":100000,\"exclusiveMinimum\":0}}},\"boundary\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"ki"
	+ "nd\",\"trigger_inset_deg\",\"inward_speed_rule\",\"preempted_timer\",\"same_time_priority\",\"preserve_position_and_velo"
	+ "city\",\"rearm_condition\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"soft_turn_preempts_event\"},\"trigger_in"
	+ "set_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"inward_speed_rule\":{\"type\":\"string\",\"const\":\"use_most"
	+ "_recent_sampled_plateau_speed\"},\"preempted_timer\":{\"type\":\"string\",\"const\":\"discard_then_draw_new_plateau_afte"
	+ "r_boundary_ramp\"},\"same_time_priority\":{\"type\":\"string\",\"const\":\"boundary_before_spontaneous\"},\"preserve_posit"
	+ "ion_and_velocity\":{\"type\":\"boolean\",\"const\":true},\"rearm_condition\":{\"type\":\"string\",\"const\":\"return_inside_bo"
	+ "th_soft_turn_thresholds\"}}},\"vertical\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"ampli"
	+ "tude_deg\",\"period_s\",\"phase_rad_distribution\",\"initial_phase_independent_per_target\"],\"properties\":{\"kind\":{\"t"
	+ "ype\":\"string\",\"const\":\"sine_about_lane_center\"},\"amplitude_deg\":{\"type\":\"number\",\"maximum\":180,\"minimum\":0},\"p"
	+ "eriod_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"phase_rad_distribution\":{\"type\":\"array\",\"minIt"
	+ "ems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6.2831853073}},\"initial_phase_independent_p"
	+ "er_target\":{\"type\":\"boolean\",\"const\":true}}},\"nominal_full_angular_speed_upper_bound_deg_s\":{\"type\":\"number\",\""
	+ "minimum\":0,\"maximum\":3600},\"event_tape\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"compiled_be"
	+ "fore_first_rendered_frame\",\"horizon_s\",\"event_time_rounding\",\"boundary_root_tolerance_s\",\"minimum_distinct_eve"
	+ "nt_spacing_s\",\"no_rng_in_frame_loop\"],\"properties\":{\"compiled_before_first_rendered_frame\":{\"type\":\"boolean\",\""
	+ "const\":true},\"horizon_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"event_time_rounding\":{\"type\":\"string\",\""
	+ "const\":\"nearest_integer_microsecond_half_up\"},\"boundary_root_tolerance_s\":{\"type\":\"number\",\"minimum\":0,\"maximu"
	+ "m\":3600},\"minimum_distinct_event_spacing_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"no_rng_in_frame_loop"
	+ "\":{\"type\":\"boolean\",\"const\":true}}}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"axis\","
	+ "\"yaw_bounds_deg\",\"lanes_pitch_deg\",\"yaw_speed_abs_deg_s\",\"initial_yaw_distribution\",\"initial_direction_prob_po"
	+ "sitive\",\"initial_velocity\",\"direction_flip_probability\",\"plateau_duration_mixture\",\"plateau_begins\",\"velocity_"
	+ "transition\",\"boundary\",\"vertical\",\"nominal_full_angular_speed_upper_bound_deg_s\",\"event_tape\"],\"properties\":{\""
	+ "kind\":{\"type\":\"string\",\"const\":\"reactive_lanes\"},\"axis\":{\"type\":\"string\",\"const\":\"yaw\"},\"yaw_bounds_deg\":{\"typ"
	+ "e\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"lanes_pitch_deg\""
	+ ":{\"type\":\"array\",\"minItems\":4,\"maxItems\":4,\"items\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180}},\"yaw_speed_"
	+ "abs_deg_s\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}},\"in"
	+ "itial_yaw_distribution\":{\"type\":\"string\",\"const\":\"uniform_inside_soft_turn_thresholds\"},\"initial_direction_pro"
	+ "b_positive\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"initial_velocity\":{\"type\":\"string\",\"const\":\"sampled_ful"
	+ "l_signed_speed\"},\"direction_flip_probability\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"plateau_duration_mixt"
	+ "ure\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":1,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required"
	+ "\":[\"weight\",\"uniform_duration_s\"],\"properties\":{\"weight\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"uniform_du"
	+ "ration_s\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600}}}}},\""
	+ "plateau_begins\":{\"type\":\"string\",\"const\":\"after_velocity_transition_finishes\"},\"velocity_transition\":{\"type\":\""
	+ "object\",\"additionalProperties\":false,\"required\":[\"kind\",\"nominal_duration_s\",\"duration_formula\",\"acceleration_"
	+ "limit_deg_s2\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"cubic_smoothstep_velocity\"},\"nominal_duration_s\""
	+ ":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"duration_formula\":{\"type\":\"string\",\"const\":\"max(nomina"
	+ "l_duration_s, 1.5 * abs(v1 - v0) / acceleration_limit_deg_s2)\"},\"acceleration_limit_deg_s2\":{\"type\":\"number\",\""
	+ "maximum\":100000,\"exclusiveMinimum\":0}}},\"boundary\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\""
	+ "kind\",\"trigger_inset_deg\",\"inward_speed_rule\",\"preempted_timer\",\"same_time_priority\",\"preserve_position_and_ve"
	+ "locity\",\"rearm_condition\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"soft_turn_preempts_event\"},\"trigger_"
	+ "inset_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"inward_speed_rule\":{\"type\":\"string\",\"const\":\"use_mo"
	+ "st_recent_sampled_plateau_speed\"},\"preempted_timer\":{\"type\":\"string\",\"const\":\"discard_then_draw_new_plateau_af"
	+ "ter_boundary_ramp\"},\"same_time_priority\":{\"type\":\"string\",\"const\":\"boundary_before_spontaneous\"},\"preserve_pos"
	+ "ition_and_velocity\":{\"type\":\"boolean\",\"const\":true},\"rearm_condition\":{\"type\":\"string\",\"const\":\"return_inside_"
	+ "both_soft_turn_thresholds\"}}},\"vertical\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"amp"
	+ "litude_deg\",\"period_s\",\"phase_rad_distribution\",\"initial_phase_independent_per_target\"],\"properties\":{\"kind\":{"
	+ "\"type\":\"string\",\"const\":\"sine_about_lane_center\"},\"amplitude_deg\":{\"type\":\"number\",\"maximum\":180,\"exclusiveMin"
	+ "imum\":0},\"period_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"phase_rad_distribution\":{\"type\":\"ar"
	+ "ray\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6.2831853073}},\"initial_phase_in"
	+ "dependent_per_target\":{\"type\":\"boolean\",\"const\":true}}},\"nominal_full_angular_speed_upper_bound_deg_s\":{\"type\""
	+ ":\"number\",\"minimum\":0,\"maximum\":3600},\"event_tape\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\""
	+ "compiled_before_first_rendered_frame\",\"horizon_s\",\"event_time_rounding\",\"boundary_root_tolerance_s\",\"minimum_d"
	+ "istinct_event_spacing_s\",\"no_rng_in_frame_loop\"],\"properties\":{\"compiled_before_first_rendered_frame\":{\"type\":"
	+ "\"boolean\",\"const\":true},\"horizon_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"event_time_rounding\":{\"type\""
	+ ":\"string\",\"const\":\"nearest_integer_microsecond_half_up\"},\"boundary_root_tolerance_s\":{\"type\":\"number\",\"minimum"
	+ "\":0,\"maximum\":3600},\"minimum_distinct_event_spacing_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"no_rng_in"
	+ "_frame_loop\":{\"type\":\"boolean\",\"const\":true}}}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"ki"
	+ "nd\",\"axis\",\"amplitude_deg\",\"orthogonal_coordinate_deg\",\"omega_rad_s\",\"period_s\",\"peak_angular_speed_deg_s\",\"pe"
	+ "ak_angular_acceleration_deg_s2\",\"initial_phase_rad_uniform\",\"formula\"],\"properties\":{\"kind\":{\"type\":\"string\",\""
	+ "const\":\"sinusoid_axis\"},\"axis\":{\"type\":\"string\",\"enum\":[\"pitch\",\"yaw\"]},\"amplitude_deg\":{\"type\":\"number\",\"maxi"
	+ "mum\":180,\"exclusiveMinimum\":0},\"orthogonal_coordinate_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":180},\"ome"
	+ "ga_rad_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"period_s\":{\"type\":\"number\",\"maximum\":3600,\"ex"
	+ "clusiveMinimum\":0},\"peak_angular_speed_deg_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"peak_angular_accel"
	+ "eration_deg_s2\":{\"type\":\"number\",\"minimum\":-100000,\"maximum\":100000},\"initial_phase_rad_uniform\":{\"type\":\"arra"
	+ "y\",\"minItems\":2,\"maxItems\":2,\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":6.2831853073}},\"formula\":{\"type\":\""
	+ "string\",\"const\":\"coordinate_deg = amplitude_deg * sin(omega_rad_s * t_s + phase_rad)\"}}},{\"type\":\"object\",\"add"
	+ "itionalProperties\":false,\"required\":[\"kind\"],\"properties\":{\"kind\":{\"type\":\"string\",\"const\":\"static\"}}}]},\"Scor"
	+ "ing\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"id\",\"formula\",\"unit\",\"accuracy_expon"
	+ "ent\",\"scale\",\"shot_denominator\",\"secondary\",\"phase_duration_s\",\"rank_key_suffix\",\"comparison_context_required\""
	+ "],\"properties\":{\"id\":{\"type\":\"string\",\"const\":\"click_v3\"},\"formula\":{\"type\":\"string\",\"const\":\"1000 * hits / ph"
	+ "ase_duration_s * hits / max(shots, 1)\"},\"unit\":{\"type\":\"string\",\"const\":\"points\"},\"accuracy_exponent\":{\"type\":"
	+ "\"integer\",\"const\":1},\"scale\":{\"type\":\"integer\",\"const\":1000},\"shot_denominator\":{\"type\":\"string\",\"const\":\"all_"
	+ "press_edges_in_phase_including_empty_arena\"},\"secondary\":{\"type\":\"array\",\"const\":[\"hits\",\"misses\",\"shots\",\"acc"
	+ "uracy\",\"hits_per_s\",\"acquisition_p50_ms\",\"acquisition_p90_ms\"]},\"phase_duration_s\":{\"type\":\"number\",\"minimum\":"
	+ "0,\"maximum\":3600},\"rank_key_suffix\":{\"type\":\"array\",\"const\":[\"catalogue_revision\",\"program_id\",\"difficulty\",\"p"
	+ "hase_id\"]},\"comparison_context_required\":{\"type\":\"boolean\",\"const\":true}}},{\"oneOf\":[{\"type\":\"object\",\"additio"
	+ "nalProperties\":false,\"required\":[\"id\",\"formula\",\"unit\",\"scale\",\"contact_requires_fire\",\"exposure_denominator\","
	+ "\"exposure_never_retimed\",\"exposure_stops_when_player_looks_away\",\"secondary\",\"phase_duration_s\",\"rank_key_suff"
	+ "ix\",\"comparison_context_required\",\"reacquisition\"],\"properties\":{\"id\":{\"type\":\"string\",\"const\":\"contact_v2\"},\""
	+ "formula\":{\"type\":\"string\",\"const\":\"1000 * contact_s / exposure_s\"},\"unit\":{\"type\":\"string\",\"const\":\"points\"},\""
	+ "scale\":{\"type\":\"integer\",\"const\":1000},\"contact_requires_fire\":{\"type\":\"boolean\",\"const\":false},\"exposure_deno"
	+ "minator\":{\"type\":\"string\",\"const\":\"full_scheduled_phase_duration_including_initial_acquisition_and_user_look_a"
	+ "way\"},\"exposure_never_retimed\":{\"type\":\"boolean\",\"const\":true},\"exposure_stops_when_player_looks_away\":{\"type\""
	+ ":\"boolean\",\"const\":false},\"secondary\":{\"type\":\"array\",\"const\":[\"contact_s\",\"exposure_s\",\"contact_fraction\",\"an"
	+ "gular_error_mean_deg\",\"angular_error_p90_deg\",\"post_reversal_contact_fraction_250_ms\",\"stable_reacquisition_p5"
	+ "0_ms\",\"stable_reacquisition_p90_ms\"]},\"phase_duration_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"rank_ke"
	+ "y_suffix\":{\"type\":\"array\",\"const\":[\"catalogue_revision\",\"program_id\",\"difficulty\",\"phase_id\"]},\"comparison_con"
	+ "text_required\":{\"type\":\"boolean\",\"const\":true},\"reacquisition\":{\"type\":\"object\",\"additionalProperties\":false,\""
	+ "required\":[\"window_s\",\"stable_raw_contact_s\",\"diagnostic_gap_merge_s\",\"latency_timestamp\",\"next_reversal_polic"
	+ "y\"],\"properties\":{\"window_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"stable_raw_contact_s\":{\"type\":\"numb"
	+ "er\",\"minimum\":0,\"maximum\":3600},\"diagnostic_gap_merge_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"latency"
	+ "_timestamp\":{\"type\":\"string\",\"const\":\"start_of_first_qualifying_raw_contact_interval\"},\"next_reversal_policy\":"
	+ "{\"type\":\"string\",\"const\":\"censor_previous_window_at_next_reversal\"}}}}},{\"type\":\"object\",\"additionalProperties"
	+ "\":false,\"required\":[\"id\",\"formula\",\"unit\",\"scale\",\"contact_requires_fire\",\"exposure_denominator\",\"exposure_nev"
	+ "er_retimed\",\"exposure_stops_when_player_looks_away\",\"secondary\",\"phase_duration_s\",\"rank_key_suffix\",\"comparis"
	+ "on_context_required\"],\"properties\":{\"id\":{\"type\":\"string\",\"const\":\"contact_v2\"},\"formula\":{\"type\":\"string\",\"co"
	+ "nst\":\"1000 * contact_s / exposure_s\"},\"unit\":{\"type\":\"string\",\"const\":\"points\"},\"scale\":{\"type\":\"integer\",\"con"
	+ "st\":1000},\"contact_requires_fire\":{\"type\":\"boolean\",\"const\":false},\"exposure_denominator\":{\"type\":\"string\",\"co"
	+ "nst\":\"full_scheduled_phase_duration_including_initial_acquisition_and_user_look_away\"},\"exposure_never_retimed"
	+ "\":{\"type\":\"boolean\",\"const\":true},\"exposure_stops_when_player_looks_away\":{\"type\":\"boolean\",\"const\":false},\"se"
	+ "condary\":{\"type\":\"array\",\"const\":[\"contact_s\",\"exposure_s\",\"contact_fraction\",\"angular_error_mean_deg\",\"angula"
	+ "r_error_p90_deg\"]},\"phase_duration_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"rank_key_suffix\":{\"type\":\""
	+ "array\",\"const\":[\"catalogue_revision\",\"program_id\",\"difficulty\",\"phase_id\"]},\"comparison_context_required\":{\"ty"
	+ "pe\":\"boolean\",\"const\":true}}}]},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"id\",\"formula\",\"unit"
	+ "\",\"scale\",\"shot_denominator\",\"opportunity_denominator\",\"secondary\",\"phase_duration_s\",\"rank_key_suffix\",\"compa"
	+ "rison_context_required\"],\"properties\":{\"id\":{\"type\":\"string\",\"const\":\"opportunities_v2\"},\"formula\":{\"type\":\"st"
	+ "ring\",\"const\":\"1000 * hits / opportunities * hits / max(shots, 1)\"},\"unit\":{\"type\":\"string\",\"const\":\"points\"},"
	+ "\"scale\":{\"type\":\"integer\",\"const\":1000},\"shot_denominator\":{\"type\":\"string\",\"const\":\"all_press_edges_in_phase_"
	+ "including_empty_arena\"},\"opportunity_denominator\":{\"type\":\"string\",\"const\":\"scheduled_opportunities_in_complet"
	+ "ed_phase\"},\"secondary\":{\"type\":\"array\",\"const\":[\"hits\",\"expired\",\"censored\",\"shots\",\"accuracy\",\"response_p50_m"
	+ "s\",\"response_p90_ms\"]},\"phase_duration_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"rank_key_suffix\":{\"typ"
	+ "e\":\"array\",\"const\":[\"catalogue_revision\",\"program_id\",\"difficulty\",\"phase_id\"]},\"comparison_context_required\":"
	+ "{\"type\":\"boolean\",\"const\":true}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"id\",\"formula\",\"un"
	+ "it\",\"scale\",\"partial_credit\",\"damage_overflow\",\"secondary\",\"phase_duration_s\",\"rank_key_suffix\",\"comparison_co"
	+ "ntext_required\",\"hp_max\"],\"properties\":{\"id\":{\"type\":\"string\",\"const\":\"switch_work_v3\"},\"formula\":{\"type\":\"str"
	+ "ing\",\"const\":\"1000 * (kills + sum(final_living_damage / hp_max)) / phase_duration_s\"},\"unit\":{\"type\":\"string\","
	+ "\"const\":\"points\"},\"scale\":{\"type\":\"integer\",\"const\":1000},\"partial_credit\":{\"type\":\"string\",\"const\":\"sum_damag"
	+ "e_fraction_of_all_living_targets_at_phase_close\"},\"damage_overflow\":{\"type\":\"string\",\"const\":\"discard_after_cu"
	+ "rrent_target_hp_zero\"},\"secondary\":{\"type\":\"array\",\"const\":[\"kills\",\"credited_work\",\"useful_damage\",\"contact_s"
	+ "\",\"switch_latency_p50_ms\",\"switch_latency_p90_ms\"]},\"phase_duration_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":"
	+ "3600},\"rank_key_suffix\":{\"type\":\"array\",\"const\":[\"catalogue_revision\",\"program_id\",\"difficulty\",\"phase_id\"]},\""
	+ "comparison_context_required\":{\"type\":\"boolean\",\"const\":true},\"hp_max\":{\"type\":\"number\",\"minimum\":-100000000000"
	+ "0.0,\"maximum\":1000000000000.0}}}]},\"Visual\":{\"oneOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\""
	+ ":[\"diagram\",\"diagram_show_envelope\",\"diagram_show_exact_angular_diameter\",\"diagram_show_target_slot_numbers\",\""
	+ "runtime_debug_overlay\",\"illustrative_route_is_not_extra_runtime_constraint\",\"hp_display\"],\"properties\":{\"diagr"
	+ "am\":{\"type\":\"string\",\"const\":\"angular_front_view\"},\"diagram_show_envelope\":{\"type\":\"boolean\",\"const\":true},\"di"
	+ "agram_show_exact_angular_diameter\":{\"type\":\"boolean\",\"const\":true},\"diagram_show_target_slot_numbers\":{\"type\":"
	+ "\"boolean\",\"const\":true},\"runtime_debug_overlay\":{\"type\":\"boolean\",\"const\":false},\"illustrative_route_is_not_ex"
	+ "tra_runtime_constraint\":{\"type\":\"boolean\",\"const\":true},\"hp_display\":{\"type\":\"string\",\"const\":\"outer_progress_"
	+ "ring_same_geometry_no_size_change\"}}},{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"diagram\",\"dia"
	+ "gram_show_envelope\",\"diagram_show_exact_angular_diameter\",\"diagram_show_target_slot_numbers\",\"runtime_debug_ov"
	+ "erlay\",\"illustrative_route_is_not_extra_runtime_constraint\"],\"properties\":{\"diagram\":{\"type\":\"string\",\"enum\":["
	+ "\"angular_front_view\",\"angular_front_view_and_slot_timeline\",\"angular_route_and_depth_size_profile\",\"four_angul"
	+ "ar_chambers_with_parabolic_routes\"]},\"diagram_show_envelope\":{\"type\":\"boolean\",\"const\":true},\"diagram_show_exa"
	+ "ct_angular_diameter\":{\"type\":\"boolean\",\"const\":true},\"diagram_show_target_slot_numbers\":{\"type\":\"boolean\",\"con"
	+ "st\":true},\"runtime_debug_overlay\":{\"type\":\"boolean\",\"const\":false},\"illustrative_route_is_not_extra_runtime_co"
	+ "nstraint\":{\"type\":\"boolean\",\"const\":true}}}]},\"Phase\":{\"type\":\"object\",\"additionalProperties\":false,\"required\""
	+ ":[\"id\",\"title\",\"start_s\",\"duration_s\",\"mechanic\",\"target_count\",\"diameter_deg\",\"distance_m\",\"size\",\"envelope\","
	+ "\"spawn\",\"lifecycle\",\"fire\",\"motion\",\"scoring\",\"visual\"],\"properties\":{\"id\":{\"type\":\"string\",\"enum\":[\"amplitude"
	+ "\",\"arcs\",\"depth\",\"ellipse\",\"evasive\",\"fixed_window\",\"general\",\"grid\",\"horizontal\",\"linear\",\"micro\",\"mobile\",\"p"
	+ "recision\",\"reactive\",\"shrinking_window\",\"static\",\"vertical\"]},\"title\":{\"type\":\"string\",\"minLength\":1,\"maxLengt"
	+ "h\":160},\"start_s\":{\"type\":\"number\",\"minimum\":0,\"maximum\":3600},\"duration_s\":{\"type\":\"number\",\"maximum\":3600,\"e"
	+ "xclusiveMinimum\":0},\"mechanic\":{\"type\":\"string\",\"enum\":[\"click\",\"opportunity\",\"switching\",\"tracking\"]},\"target"
	+ "_count\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"diameter_deg\":{\"type\":\"number\",\"minimum\":-180,\"maximum\":1"
	+ "80},\"distance_m\":{\"type\":\"number\",\"maximum\":1000,\"exclusiveMinimum\":0},\"size\":{\"$ref\":\"#/$defs/Size\"},\"envelop"
	+ "e\":{\"$ref\":\"#/$defs/Envelope\"},\"spawn\":{\"$ref\":\"#/$defs/Spawn\"},\"lifecycle\":{\"$ref\":\"#/$defs/Lifecycle\"},\"fire"
	+ "\":{\"$ref\":\"#/$defs/Fire\"},\"motion\":{\"$ref\":\"#/$defs/Motion\"},\"scoring\":{\"$ref\":\"#/$defs/Scoring\"},\"visual\":{\"$"
	+ "ref\":\"#/$defs/Visual\"}}},\"Program\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_id\",\"dif"
	+ "ficulty\",\"title\",\"duration_s\",\"public_mode_selector\",\"difficulty_locked_for_run\",\"arena\",\"phase_transition\",\"a"
	+ "ggregate\",\"phases\"],\"properties\":{\"program_id\":{\"type\":\"string\",\"enum\":[\"EX01\",\"EX02\",\"EX03\",\"EX04\",\"EX05\",\"EX"
	+ "06\",\"EX07\",\"EX08\"]},\"difficulty\":{\"type\":\"string\",\"enum\":[\"advanced\",\"novice\",\"standard\"]},\"title\":{\"type\":\"st"
	+ "ring\",\"minLength\":1,\"maxLength\":160},\"duration_s\":{\"type\":\"number\",\"maximum\":3600,\"exclusiveMinimum\":0},\"publi"
	+ "c_mode_selector\":{\"type\":\"boolean\",\"const\":false},\"difficulty_locked_for_run\":{\"type\":\"boolean\",\"const\":true},"
	+ "\"arena\":{\"$ref\":\"#/$defs/Arena\"},\"phase_transition\":{\"$ref\":\"#/$defs/PhaseTransition\"},\"aggregate\":{\"$ref\":\"#/"
	+ "$defs/Aggregate\"},\"phases\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":3,\"items\":{\"$ref\":\"#/$defs/Phase\"}}}}}}"
)

static var last_error: String = ""
static var _schema: Dictionary = {}


static func _success() -> Dictionary:
	return {"ok": true, "error": "", "code": "", "path": ""}


static func _failure(code: String, path: String, message: String = "") -> Dictionary:
	return {"ok": false, "error": message if not message.is_empty() else code, "code": code, "path": path}


static func _raw_sha256(raw: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not raw.is_empty():
		context.update(raw)
	return context.finish().hex_encode()


static func validate_catalogue_bytes(raw: PackedByteArray) -> Dictionary:
	if _raw_sha256(raw) != CATALOGUE_SHA256:
		return _failure("CATALOGUE_SHA256", "$", "Catalogue bytes differ from the original V2 kit.")
	var parser := JSON.new()
	if parser.parse(raw.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return _failure("CATALOGUE_JSON", "$")
	var root: Dictionary = parser.data
	if root.get("catalogue_revision") != REVISION or root.get("schema_version") != "aimlocal.catalogue.v2":
		return _failure("CATALOGUE_VERSION", "$.catalogue_revision")
	if not root.get("programs") is Array or root.programs.size() != 24:
		return _failure("CATALOGUE_COUNT", "$.programs")
	var result := _success()
	result["catalogue"] = root
	return result


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOGUE_PATH):
		last_error = "CATALOGUE_MISSING"
		return {}
	var result := validate_catalogue_bytes(FileAccess.get_file_as_bytes(CATALOGUE_PATH))
	last_error = "" if result.ok else String(result.code)
	return result.catalogue.duplicate(true) if result.ok else {}


static func programs() -> Array:
	var catalogue := load_catalog()
	return catalogue.programs.duplicate(true) if not catalogue.is_empty() else []


static func find(program_id: String, difficulty: String) -> Dictionary:
	for program in programs():
		if program.program_id == program_id and program.difficulty == difficulty:
			return program.duplicate(true)
	return {}


static func fingerprint(config: Dictionary) -> String:
	return Canonical.semantic_sha256(config)


static func catalogue_schema() -> Dictionary:
	if _schema.is_empty():
		var parsed: Variant = JSON.parse_string(CATALOGUE_SCHEMA_JSON)
		if not parsed is Dictionary:
			return {}
		var support := _check_schema_subset(parsed)
		if not support.ok:
			last_error = String(support.code)
			return {}
		_schema = parsed
	return _schema.duplicate(true)


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum and float(value) == floor(float(value))


static func _close(actual: float, expected: float) -> bool:
	if not is_finite(actual) or not is_finite(expected):
		return false
	return absf(actual - expected) <= maxf(0.00000001, 0.00000001 * maxf(absf(actual), absf(expected)))


static func _json_equal(first: Variant, second: Variant) -> bool:
	if _number(first) and _number(second):
		return float(first) == float(second)
	if typeof(first) != typeof(second):
		return false
	if first is Array:
		if first.size() != second.size():
			return false
		for index in first.size():
			if not _json_equal(first[index], second[index]):
				return false
		return true
	if first is Dictionary:
		if first.size() != second.size():
			return false
		for key in first:
			if not second.has(key) or not _json_equal(first[key], second[key]):
				return false
		return true
	return first == second


static func _validate_json(value: Variant, path: String = "$", depth: int = 0) -> Dictionary:
	if depth > 128:
		return _failure("JSON_DEPTH", path)
	match typeof(value):
		TYPE_INT:
			if value < -MAX_SAFE_INTEGER or value > MAX_SAFE_INTEGER:
				return _failure("JSON_UNSAFE_INTEGER", path)
		TYPE_FLOAT:
			if not is_finite(value):
				return _failure("JSON_NONFINITE", path)
		TYPE_STRING:
			for index in value.length():
				var codepoint: int = value.unicode_at(index)
				if codepoint >= 55296 and codepoint <= 57343:
					return _failure("JSON_SURROGATE", path)
		TYPE_ARRAY:
			for index in value.size():
				var result := _validate_json(value[index], "%s[%d]" % [path, index], depth + 1)
				if not result.ok:
					return result
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING:
					return _failure("JSON_NONSTRING_KEY", path)
				var result := _validate_json(value[key], path + "." + key, depth + 1)
				if not result.ok:
					return result
		TYPE_NIL, TYPE_BOOL:
			pass
		_:
			return _failure("JSON_TYPE", path)
	return _success()


static func _check_schema_subset(schema: Variant, path: String = "$schema") -> Dictionary:
	if schema is bool:
		return _success()
	if not schema is Dictionary:
		return _failure("SCHEMA_DEFINITION", path)
	for key in schema:
		if not key in SUPPORTED_SCHEMA_KEYWORDS:
			return _failure("SCHEMA_UNSUPPORTED_KEYWORD", path + "." + String(key))
	for group in ["$defs", "properties"]:
		for key in schema.get(group, {}):
			var result := _check_schema_subset(schema[group][key], path + "." + group + "." + key)
			if not result.ok:
				return result
	for group in ["items", "additionalProperties"]:
		if schema.get(group) is Dictionary or schema.get(group) is bool:
			var result := _check_schema_subset(schema[group], path + "." + group)
			if not result.ok:
				return result
	for group in ["oneOf", "anyOf", "allOf"]:
		for branch in schema.get(group, []):
			var result := _check_schema_subset(branch, path + "." + group)
			if not result.ok:
				return result
	if schema.has("$ref") and (not schema["$ref"] is String or not String(schema["$ref"]).begins_with("#/")):
		return _failure("SCHEMA_NONLOCAL_REFERENCE", path)
	return _success()


static func _type_matches(value: Variant, schema_type: String) -> bool:
	match schema_type:
		"null": return value == null
		"boolean": return typeof(value) == TYPE_BOOL
		"number": return _number(value)
		"integer": return _number(value) and float(value) == floor(float(value))
		"string": return typeof(value) == TYPE_STRING
		"array": return typeof(value) == TYPE_ARRAY
		"object": return typeof(value) == TYPE_DICTIONARY
	return false


static func _validate_schema(value: Variant, schema: Variant, root: Dictionary, path: String) -> Dictionary:
	if schema is bool:
		return _success() if schema else _failure("SCHEMA_FORBIDDEN", path)
	if schema.has("$ref"):
		var referenced: Variant = root
		for part in String(schema["$ref"]).substr(2).split("/"):
			var key := part.replace("~1", "/").replace("~0", "~")
			if not referenced is Dictionary or not referenced.has(key):
				return _failure("SCHEMA_REFERENCE", path)
			referenced = referenced[key]
		var result := _validate_schema(value, referenced, root, path)
		if not result.ok:
			return result
	for combiner in ["oneOf", "anyOf", "allOf"]:
		if not schema.has(combiner):
			continue
		var matching: int = 0
		for branch in schema[combiner]:
			if _validate_schema(value, branch, root, path).ok:
				matching += 1
		if (combiner == "oneOf" and matching != 1) or (combiner == "anyOf" and matching == 0) or (combiner == "allOf" and matching != schema[combiner].size()):
			return _failure("SCHEMA_" + String(combiner).to_upper(), path)
	if schema.has("type") and not _type_matches(value, String(schema.type)):
		return _failure("SCHEMA_TYPE", path)
	if schema.has("const") and not _json_equal(value, schema["const"]):
		return _failure("SCHEMA_CONST", path)
	if schema.has("enum"):
		var found: bool = false
		for option in schema["enum"]:
			found = found or _json_equal(value, option)
		if not found:
			return _failure("SCHEMA_ENUM", path)
	if _number(value):
		for bound in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"]:
			if not schema.has(bound):
				continue
			var limit: float = float(schema[bound])
			if (bound == "minimum" and value < limit) or (bound == "maximum" and value > limit) or (bound == "exclusiveMinimum" and value <= limit) or (bound == "exclusiveMaximum" and value >= limit):
				return _failure("SCHEMA_NUMBER_RANGE", path)
	if value is String:
		if value.length() < int(schema.get("minLength", 0)) or (schema.has("maxLength") and value.length() > int(schema.maxLength)):
			return _failure("SCHEMA_STRING_LENGTH", path)
		if schema.has("pattern"):
			var pattern := RegEx.new()
			if pattern.compile(String(schema.pattern)) != OK or pattern.search(value) == null:
				return _failure("SCHEMA_PATTERN", path)
	if value is Array:
		if value.size() < int(schema.get("minItems", 0)) or (schema.has("maxItems") and value.size() > int(schema.maxItems)):
			return _failure("SCHEMA_ARRAY_LENGTH", path)
		for index in value.size():
			if schema.get("uniqueItems", false):
				for previous_index in index:
					if _json_equal(value[index], value[previous_index]):
						return _failure("SCHEMA_UNIQUE_ITEMS", path)
			if schema.has("items"):
				var result := _validate_schema(value[index], schema["items"], root, "%s[%d]" % [path, index])
				if not result.ok:
					return result
	if value is Dictionary:
		for key in schema.get("required", []):
			if not value.has(key):
				return _failure("SCHEMA_REQUIRED", path + "." + key)
		var properties: Dictionary = schema.get("properties", {})
		for key in value:
			var child_path: String = path + "." + key
			if properties.has(key):
				var result := _validate_schema(value[key], properties[key], root, child_path)
				if not result.ok:
					return result
			elif schema.get("additionalProperties") is bool and not schema.additionalProperties:
				return _failure("SCHEMA_ADDITIONAL_PROPERTY", child_path)
			elif schema.get("additionalProperties") is Dictionary:
				var result := _validate_schema(value[key], schema.additionalProperties, root, child_path)
				if not result.ok:
					return result
	return _success()


static func _validate_ranges(value: Variant, path: String = "$") -> Dictionary:
	if value is Dictionary:
		for key in value:
			var child: Variant = value[key]
			var child_path: String = path + "." + key
			if key in RANGE_KEYS and child is Array and child.size() == 2 and _number(child[0]) and _number(child[1]) and float(child[0]) > float(child[1]):
				return _failure("RANGE_ORDER", child_path)
			var result := _validate_ranges(child, child_path)
			if not result.ok:
				return result
	elif value is Array:
		for index in value.size():
			var result := _validate_ranges(value[index], "%s[%d]" % [path, index])
			if not result.ok:
				return result
	return _success()


static func _contained(inner: Array, outer: Array) -> bool:
	return float(inner[0]) >= float(outer[0]) - 0.00000001 and float(inner[1]) <= float(outer[1]) + 0.00000001 and float(inner[0]) <= float(inner[1])


static func validate_program(config: Dictionary) -> Dictionary:
	var result := _validate_json(config)
	if not result.ok:
		return result
	var schema := catalogue_schema()
	if schema.is_empty():
		return _failure("SCHEMA_MISSING", "$")
	result = _validate_schema(config, schema["$defs"].Program, schema, "$")
	if not result.ok:
		return result
	result = _validate_ranges(config)
	if not result.ok:
		return result
	if float(config.duration_s) != 60.0:
		return _failure("PROGRAM_DURATION", "$.duration_s")
	var expected: Array = PHASE_LAYOUT[config.program_id]
	if config.phases.size() != expected.size():
		return _failure("PHASE_COUNT", "$.phases")
	var arena: Dictionary = config.arena
	var horizontal_fov_deg: float = float(arena.fov_horizontal_deg_at_16_9)
	var expected_vertical_deg: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_fov_deg * 0.5)) * 9.0 / 16.0))
	if not _close(horizontal_fov_deg, 103.0) or not _close(float(arena.fov_vertical_deg), expected_vertical_deg) or not _json_equal(arena.reference_aspect_ratio, [16, 9]):
		return _failure("REFERENCE_FOV", "$.arena")
	if not _json_equal(arena.eye_position_m, [0, 1.6, 0]) or not _close(float(arena.floor_y_m), 0.0):
		return _failure("REFERENCE_EYE", "$.arena")
	var expected_aggregate: String = "descriptive_only" if config.program_id in ["EX01", "EX02", "EX03", "EX04"] else ("sum_credited_switch_work_per_program_time" if config.program_id == "EX08" else "time_weighted_contact")
	if config.aggregate.kind != expected_aggregate:
		return _failure("AGGREGATE_KIND", "$.aggregate.kind")
	var elapsed_s: float = 0.0
	var switch_hp: float = -1.0
	var switch_diameter_deg: float = -1.0
	for index in config.phases.size():
		var phase: Dictionary = config.phases[index]
		var path: String = "$.phases[%d]" % index
		var layout: Array = expected[index]
		if phase.id != layout[0] or phase.mechanic != layout[2] or phase.motion.kind != layout[3]:
			return _failure("PHASE_IDENTITY", path)
		if float(phase.start_s) != elapsed_s:
			return _failure("PHASE_CONTIGUITY", path + ".start_s")
		if float(phase.duration_s) != float(layout[1]):
			return _failure("PHASE_DURATION", path + ".duration_s")
		elapsed_s += float(phase.duration_s)
		if not _integer(phase.target_count, 1, 6) or int(phase.target_count) != int(layout[4]) or not _json_equal(phase.target_count, phase.spawn.target_slots):
			return _failure("TARGET_COUNT", path + ".target_count")
		if phase.scoring.id != SCORE_IDS[phase.mechanic] or phase.fire.mode != FIRE_MODES[phase.mechanic]:
			return _failure("MECHANIC_CONTRACT", path)
		if float(phase.scoring.phase_duration_s) != float(phase.duration_s):
			return _failure("SCORE_DURATION", path + ".scoring.phase_duration_s")
		result = _validate_size_lifecycle(phase, String(config.program_id), path)
		if not result.ok:
			return result
		if phase.mechanic == "switching":
			var life: Dictionary = phase.lifecycle
			if switch_hp >= 0.0 and (not _close(float(life.hp_max), switch_hp) or not _close(float(phase.diameter_deg), switch_diameter_deg)):
				return _failure("SWITCH_PHASE_CONDITIONS", path + ".lifecycle.hp_max")
			switch_hp = float(life.hp_max)
			switch_diameter_deg = float(phase.diameter_deg)
		result = _validate_geometry(phase, arena, path)
		if not result.ok:
			return result
		result = _validate_motion(phase, path)
		if not result.ok:
			return result
	if elapsed_s != 60.0:
		return _failure("PROGRAM_PHASE_TOTAL", "$.phases")
	result = _success()
	result["definition_sha256"] = fingerprint(config)
	return result


static func _validate_size_lifecycle(phase: Dictionary, program_id: String, path: String) -> Dictionary:
	var size: Dictionary = phase.size
	var life: Dictionary = phase.lifecycle
	var diameter_deg: float = float(phase.diameter_deg)
	var distance_m: float = float(phase.distance_m)
	if diameter_deg <= 0.0 or diameter_deg >= 180.0 or not _close(distance_m, 4.0):
		return _failure("TARGET_GEOMETRY", path)
	if not _close(float(size.reference_distance_m), distance_m) or not _close(float(size.world_radius_m), distance_m * sin(deg_to_rad(diameter_deg * 0.5))):
		return _failure("SPHERE_RADIUS", path + ".size.world_radius_m")
	var shrinking: bool = program_id == "EX03" and phase.id == "shrinking_window"
	var size_mode: String = "world_radius_constant" if program_id == "EX07" else ("angular_diameter_linear_over_window" if shrinking else "angular_diameter_constant")
	if size.mode != size_mode or size.shrink != shrinking:
		return _failure("SIZE_BEHAVIOR", path + ".size")
	var expected_lifecycle: String = "scheduled_window" if program_id == "EX03" else ("persistent" if phase.mechanic == "tracking" else ("until_contact_kill" if phase.mechanic == "switching" else "until_hit"))
	if life.kind != expected_lifecycle:
		return _failure("LIFECYCLE_KIND", path + ".lifecycle.kind")
	if program_id != "EX03" and life.ttl_s != null:
		return _failure("TTL_ONLY_EX03", path + ".lifecycle.ttl_s")
	if program_id == "EX03":
		var schedule: Dictionary = phase.spawn.schedule
		var ttl_s: float = float(life.ttl_s)
		if ttl_s <= 0.0 or not _integer(schedule.slots, 10, 10) or not _close(float(schedule.slot_duration_s), 3.0) or not _close(float(schedule.first_slot_start_s), 0.0):
			return _failure("WINDOW_SCHEDULE", path + ".spawn.schedule")
		if float(schedule.onset_delay_uniform_s[0]) < 0.0 or float(schedule.onset_delay_uniform_s[1]) + ttl_s > float(schedule.slot_duration_s):
			return _failure("WINDOW_OVERFLOW", path + ".lifecycle.ttl_s")
		if not _close(float(size.progress_duration_s), ttl_s) or not _close(float(size.diameter_start_deg), diameter_deg) or not _close(float(size.diameter_end_deg), diameter_deg * (0.6 if shrinking else 1.0)):
			return _failure("WINDOW_SIZE", path + ".size")
		if shrinking and not _close(float(size.world_radius_end_m), distance_m * sin(deg_to_rad(float(size.diameter_end_deg) * 0.5))):
			return _failure("SHRINK_RADIUS", path + ".size.world_radius_end_m")
	if phase.mechanic == "switching":
		if float(life.hp_max) <= 0.0 or not _close(float(phase.fire.damage_per_s), 100.0) or not _close(float(life.hp_regeneration_per_s), 0.0):
			return _failure("SWITCH_DAMAGE", path + ".lifecycle")
		if not _close(float(life.ideal_contact_time_to_kill_s), float(life.hp_max) / 100.0) or not _close(float(phase.scoring.hp_max), float(life.hp_max)):
			return _failure("SWITCH_HP", path + ".lifecycle.hp_max")
	if program_id == "EX07":
		var distances: Array = phase.envelope.center_distance_m
		var radius_m: float = float(size.world_radius_m)
		if radius_m <= 0.0 or radius_m >= float(distances[0]):
			return _failure("DEPTH_RADIUS", path + ".size.world_radius_m")
		if not _close(float(size.reference_angular_diameter_deg), diameter_deg) or not _close(float(size.minimum_apparent_diameter_deg), rad_to_deg(2.0 * asin(radius_m / float(distances[1])))) or not _close(float(size.maximum_apparent_diameter_deg), rad_to_deg(2.0 * asin(radius_m / float(distances[0])))):
			return _failure("DEPTH_APPARENT_DIAMETER", path + ".size")
	return _success()


static func _interval_product(first: Array, second: Array) -> Array[float]:
	var products: Array[float] = [float(first[0]) * float(second[0]), float(first[0]) * float(second[1]), float(first[1]) * float(second[0]), float(first[1]) * float(second[1])]
	return [products.min(), products.max()]


static func _trig_interval(bounds_deg: Array, cosine: bool = false) -> Array[float]:
	var lower_rad: float = deg_to_rad(float(bounds_deg[0]))
	var upper_rad: float = deg_to_rad(float(bounds_deg[1]))
	var values: Array[float] = [cos(lower_rad) if cosine else sin(lower_rad), cos(upper_rad) if cosine else sin(upper_rad)]
	var offset_rad: float = 0.0 if cosine else PI * 0.5
	var first_extremum: int = int(ceil((lower_rad - offset_rad) / PI))
	var last_extremum: int = int(floor((upper_rad - offset_rad) / PI))
	for extremum in range(first_extremum, last_extremum + 1):
		values.append(1.0 if extremum % 2 == 0 else -1.0)
	return [values.min(), values.max()]


static func _validate_geometry(phase: Dictionary, arena: Dictionary, path: String) -> Dictionary:
	var envelope: Dictionary = phase.envelope
	var spawn: Dictionary = phase.spawn
	var distances: Array = envelope.center_distance_m
	if float(distances[0]) <= 0.0 or float(envelope.center_pitch_deg[0]) <= -89.0 or float(envelope.center_pitch_deg[1]) >= 89.0 or float(envelope.center_yaw_deg[0]) <= -90.0 or float(envelope.center_yaw_deg[1]) >= 90.0:
		return _failure("ENVELOPE_DOMAIN", path + ".envelope")
	if not _contained(spawn.yaw_deg, envelope.center_yaw_deg) or not _contained(spawn.pitch_deg, envelope.center_pitch_deg):
		return _failure("SPAWN_ENVELOPE", path + ".spawn")
	if float(spawn.transition_angle_deg[0]) < 0.0 or float(spawn.transition_angle_deg[1]) > 180.0:
		return _failure("TRANSITION_DOMAIN", path + ".spawn.transition_angle_deg")
	if spawn.has("candidate_yaw_deg") and not _contained(spawn.candidate_yaw_deg, spawn.yaw_deg):
		return _failure("CANDIDATE_ENVELOPE", path + ".spawn.candidate_yaw_deg")
	if phase.size.mode != "world_radius_constant" and not _json_equal(distances, [phase.distance_m, phase.distance_m]):
		return _failure("FIXED_DISTANCE", path + ".envelope.center_distance_m")
	var cosine_pitch := _trig_interval(envelope.center_pitch_deg, true)
	var horizontal := _interval_product(distances, _interval_product(cosine_pitch, _trig_interval(envelope.center_yaw_deg)))
	var vertical := _interval_product(distances, _trig_interval(envelope.center_pitch_deg))
	var forward := _interval_product(distances, _interval_product(cosine_pitch, _trig_interval(envelope.center_yaw_deg, true)))
	var maximum_diameter_deg: float = maxf(float(phase.diameter_deg), maxf(float(phase.size.get("diameter_start_deg", phase.diameter_deg)), float(phase.size.get("diameter_end_deg", phase.diameter_deg))))
	var radius_m: float = float(phase.size.world_radius_m) if phase.size.mode == "world_radius_constant" else float(distances[1]) * sin(deg_to_rad(maximum_diameter_deg * 0.5))
	var floor_clearance_m: float = float(arena.eye_position_m[1]) + vertical[0] - radius_m - float(arena.floor_y_m)
	if float(envelope.minimum_floor_clearance_m) < 0.05 - 0.000000001 or floor_clearance_m + 0.000000001 < float(envelope.minimum_floor_clearance_m):
		return _failure("FLOOR_CLEARANCE", path + ".envelope")
	var horizontal_half_rad: float = deg_to_rad(float(arena.fov_horizontal_deg_at_16_9) * 0.5)
	var vertical_half_rad: float = deg_to_rad(float(arena.fov_vertical_deg) * 0.5)
	var planes: Array[float] = [
		cos(horizontal_half_rad) * horizontal[0] + sin(horizontal_half_rad) * forward[0] - radius_m,
		-cos(horizontal_half_rad) * horizontal[1] + sin(horizontal_half_rad) * forward[0] - radius_m,
		-cos(vertical_half_rad) * vertical[1] + sin(vertical_half_rad) * forward[0] - radius_m,
		cos(vertical_half_rad) * vertical[0] + sin(vertical_half_rad) * forward[0] - radius_m,
		forward[0] - float(arena.near_m) - radius_m, float(arena.far_m) - forward[1] - radius_m
	]
	if planes.min() < -0.000000001 or float(arena.wall_reference_distance_m) - forward[1] - radius_m < 0.0:
		return _failure("FRUSTUM_CLEARANCE", path + ".envelope")
	var gap_deg: float = float(spawn.minimum_silhouette_gap_deg)
	if gap_deg < 0.75 - 0.00000001:
		return _failure("SILHOUETTE_GAP", path + ".spawn.minimum_silhouette_gap_deg")
	if spawn.has("minimum_equal_size_center_separation_deg") and float(spawn.minimum_equal_size_center_separation_deg) + 0.00000001 < maximum_diameter_deg + gap_deg:
		return _failure("CENTER_SEPARATION", path + ".spawn.minimum_equal_size_center_separation_deg")
	if spawn.has("transition_band_bag"):
		var copies: int = 0
		var previous_end_deg: float = float(spawn.transition_angle_deg[0])
		for band in spawn.transition_band_bag.bands:
			copies += int(band.copies)
			if not _close(float(band.angle_deg[0]), previous_end_deg):
				return _failure("BAG_CONTIGUITY", path + ".spawn.transition_band_bag")
			previous_end_deg = float(band.angle_deg[1])
		if copies != int(spawn.transition_band_bag.draw_count) or not _close(previous_end_deg, float(spawn.transition_angle_deg[1])):
			return _failure("BAG_COUNT", path + ".spawn.transition_band_bag")
	if spawn.kind == "grid_without_overlap":
		var nodes: Array = spawn.nodes_yaw_pitch_deg
		if nodes.size() != 9:
			return _failure("GRID_NODES", path + ".spawn.nodes_yaw_pitch_deg")
		for index in nodes.size():
			if not _contained([nodes[index][0], nodes[index][0]], envelope.center_yaw_deg) or not _contained([nodes[index][1], nodes[index][1]], envelope.center_pitch_deg):
				return _failure("GRID_ENVELOPE", path + ".spawn.nodes_yaw_pitch_deg")
			for previous_index in index:
				var separation_deg: float = Geometry.separation_deg(Geometry.direction_deg(float(nodes[index][0]), float(nodes[index][1])), Geometry.direction_deg(float(nodes[previous_index][0]), float(nodes[previous_index][1])))
				if separation_deg + 0.00000001 < maximum_diameter_deg + gap_deg:
					return _failure("GRID_SEPARATION", path + ".spawn.nodes_yaw_pitch_deg")
	return _success()


static func _validate_motion(phase: Dictionary, path: String) -> Dictionary:
	var motion: Dictionary = phase.motion
	var spawn: Dictionary = phase.spawn
	var envelope: Dictionary = phase.envelope
	var kind: String = motion.kind
	if motion.has("yaw_bounds_deg") and not _contained(motion.yaw_bounds_deg, envelope.center_yaw_deg):
		return _failure("MOTION_ENVELOPE", path + ".motion.yaw_bounds_deg")
	if spawn.kind == "one_target_per_lane":
		var lanes: Array = motion.lanes_pitch_deg
		var vertical_amplitude_deg: float = float(motion.get("vertical", {}).get("amplitude_deg", 0))
		if not _json_equal(spawn.lane_pitch_deg, lanes) or lanes.size() != int(phase.target_count):
			return _failure("LANE_IDENTITY", path + ".motion.lanes_pitch_deg")
		if not _contained([float(lanes.min()) - vertical_amplitude_deg, float(lanes.max()) + vertical_amplitude_deg], envelope.center_pitch_deg):
			return _failure("LANE_ENVELOPE", path + ".motion")
		for index in lanes.size():
			for previous_index in index:
				if absf(float(lanes[index]) - float(lanes[previous_index])) - 2.0 * vertical_amplitude_deg + 0.00000001 < float(phase.diameter_deg) + float(spawn.minimum_silhouette_gap_deg):
					return _failure("LANE_SEPARATION", path + ".motion.lanes_pitch_deg")
	if kind in ["reactive_axis", "reactive_lanes"]:
		var weight_sum: float = 0.0
		for component in motion.plateau_duration_mixture:
			if float(component.weight) <= 0.0 or float(component.uniform_duration_s[0]) <= 0.0:
				return _failure("PLATEAU_DOMAIN", path + ".motion.plateau_duration_mixture")
			weight_sum += float(component.weight)
		if not _close(weight_sum, 1.0):
			return _failure("MIXTURE_WEIGHTS", path + ".motion.plateau_duration_mixture")
		var minimum_speed_deg_s: float = float(motion.yaw_speed_abs_deg_s[0])
		var maximum_speed_deg_s: float = float(motion.yaw_speed_abs_deg_s[1])
		var nominal_s: float = float(motion.velocity_transition.nominal_duration_s)
		var acceleration_deg_s2: float = float(motion.velocity_transition.acceleration_limit_deg_s2)
		var inset_deg: float = float(motion.boundary.trigger_inset_deg)
		var period_s: float = float(motion.vertical.period_s)
		if minimum_speed_deg_s <= 0.0 or maximum_speed_deg_s <= 0.0 or nominal_s <= 0.0 or acceleration_deg_s2 <= 0.0 or period_s <= 0.0 or inset_deg <= 0.0 or inset_deg >= (float(motion.yaw_bounds_deg[1]) - float(motion.yaw_bounds_deg[0])) * 0.5:
			return _failure("REACTIVE_DOMAIN", path + ".motion")
		if _stopping_distance_bound(maximum_speed_deg_s, minimum_speed_deg_s, nominal_s, acceleration_deg_s2) > inset_deg + 0.00000001:
			return _failure("BRAKING_DISTANCE", path + ".motion.boundary.trigger_inset_deg")
		var vertical_speed_deg_s: float = float(motion.vertical.amplitude_deg) * TAU / period_s
		if not _close(float(motion.nominal_full_angular_speed_upper_bound_deg_s), sqrt(maximum_speed_deg_s * maximum_speed_deg_s + vertical_speed_deg_s * vertical_speed_deg_s)):
			return _failure("REACTIVE_SPEED_BOUND", path + ".motion.nominal_full_angular_speed_upper_bound_deg_s")
		if float(motion.event_tape.horizon_s) < float(phase.duration_s):
			return _failure("EVENT_HORIZON", path + ".motion.event_tape.horizon_s")
		if kind == "reactive_lanes" and (not _close(float(spawn.candidate_yaw_deg[0]), float(motion.yaw_bounds_deg[0]) + inset_deg) or not _close(float(spawn.candidate_yaw_deg[1]), float(motion.yaw_bounds_deg[1]) - inset_deg)):
			return _failure("REACTIVE_SPAWN_THRESHOLDS", path + ".spawn.candidate_yaw_deg")
	elif kind == "sinusoid_axis":
		var amplitude_deg: float = float(motion.amplitude_deg)
		var omega_rad_s: float = float(motion.omega_rad_s)
		if amplitude_deg <= 0.0 or omega_rad_s <= 0.0:
			return _failure("SINUSOID_DOMAIN", path + ".motion")
		if not _close(float(motion.peak_angular_speed_deg_s), amplitude_deg * omega_rad_s) or not _close(float(motion.peak_angular_acceleration_deg_s2), amplitude_deg * omega_rad_s * omega_rad_s) or not _close(float(motion.period_s), TAU / omega_rad_s):
			return _failure("SINUSOID_DERIVED", path + ".motion")
		if not _contained([-amplitude_deg, amplitude_deg], envelope["center_yaw_deg" if motion.axis == "yaw" else "center_pitch_deg"]):
			return _failure("SINUSOID_ENVELOPE", path + ".motion.amplitude_deg")
	elif kind == "linear_reflect" and motion.reflection == "symmetric_cubic_smoothstep_velocity":
		var speed_deg_s: float = float(motion.yaw_speed_deg_s)
		var turn_s: float = float(motion.turn_duration_s)
		if speed_deg_s <= 0.0 or turn_s <= 0.0:
			return _failure("SOFT_REFLECT_DOMAIN", path + ".motion")
		var inset_deg: float = 5.0 * speed_deg_s * turn_s / 16.0
		var straight_s: float = (float(motion.yaw_bounds_deg[1]) - float(motion.yaw_bounds_deg[0]) - 2.0 * inset_deg) / speed_deg_s
		if straight_s <= 0.0 or not _close(float(motion.turn_entry_inset_deg), inset_deg) or not _close(float(motion.straight_segment_duration_s), straight_s) or not _close(float(motion.period_s), 2.0 * straight_s + 2.0 * turn_s) or not _close(float(motion.peak_yaw_acceleration_deg_s2), 3.0 * speed_deg_s / turn_s):
			return _failure("SOFT_REFLECT_DERIVED", path + ".motion")
	elif kind == "angular_bounce":
		var height_deg: float = float(motion.apex_height_above_baseline_deg)
		var flight_s: float = float(motion.flight_duration_s)
		if height_deg <= 0.0 or flight_s <= 0.0 or not _close(float(motion.launch_pitch_velocity_deg_s), 4.0 * height_deg / flight_s) or not _close(float(motion.pitch_acceleration_deg_s2), -8.0 * height_deg / (flight_s * flight_s)):
			return _failure("BOUNCE_DERIVED", path + ".motion")
		if not _json_equal(motion.chambers, spawn.chambers) or motion.chambers.size() != int(phase.target_count):
			return _failure("CHAMBER_IDENTITY", path + ".motion.chambers")
		if not _close(float(motion.initial_flight_age_uniform_s[0]), 0.0) or not _close(float(motion.initial_flight_age_uniform_s[1]), flight_s) or float(motion.event_tape_horizon_s) < float(phase.duration_s):
			return _failure("BOUNCE_INITIAL_STATE", path + ".motion")
		var slots: Dictionary = {}
		var previous_end_deg: float = -INF
		for chamber in motion.chambers:
			if slots.has(int(chamber.slot)) or not _integer(chamber.slot, 0, int(phase.target_count) - 1):
				return _failure("CHAMBER_SLOT", path + ".motion.chambers")
			slots[int(chamber.slot)] = true
			if float(chamber.yaw_deg[0]) < previous_end_deg or not _contained(chamber.yaw_deg, envelope.center_yaw_deg) or not _contained([chamber.baseline_pitch_deg, float(chamber.baseline_pitch_deg) + height_deg], envelope.center_pitch_deg):
				return _failure("CHAMBER_ENVELOPE", path + ".motion.chambers")
			var maximum_pitch_deg: float = maxf(absf(float(chamber.baseline_pitch_deg)), absf(float(chamber.baseline_pitch_deg) + height_deg))
			var half_width_rad: float = deg_to_rad((float(chamber.yaw_deg[1]) - float(chamber.yaw_deg[0])) * 0.25)
			if rad_to_deg(2.0 * asin(cos(deg_to_rad(maximum_pitch_deg)) * sin(half_width_rad))) + 0.00000001 < float(spawn.transition_angle_deg[0]):
				return _failure("CHAMBER_RESPAWN", path + ".spawn.transition_angle_deg")
			if not is_inf(previous_end_deg):
				var yaw_gap_rad: float = deg_to_rad((float(chamber.yaw_deg[0]) - previous_end_deg) * 0.5)
				var envelope_pitch_deg: float = maxf(absf(float(envelope.center_pitch_deg[0])), absf(float(envelope.center_pitch_deg[1])))
				if rad_to_deg(2.0 * asin(cos(deg_to_rad(envelope_pitch_deg)) * sin(yaw_gap_rad))) + 0.00000001 < float(phase.diameter_deg) + float(spawn.minimum_silhouette_gap_deg):
					return _failure("CHAMBER_SEPARATION", path + ".motion.chambers")
			previous_end_deg = float(chamber.yaw_deg[1])
	elif kind == "depth_sines":
		var center_m: float = float(motion.distance_center_m)
		var amplitude_m: float = float(motion.distance_amplitude_m)
		var omega_rad_s: float = float(motion.distance_omega_rad_s)
		if center_m <= amplitude_m or amplitude_m < 0.0 or omega_rad_s <= 0.0 or not _json_equal(envelope.center_distance_m, [center_m - amplitude_m, center_m + amplitude_m]):
			return _failure("DEPTH_ENVELOPE", path + ".motion")
		for axis in ["yaw", "pitch"]:
			var amplitude_deg: float = float(motion[axis + "_amplitude_deg"])
			if float(motion[axis + "_omega_rad_s"]) <= 0.0 or not _contained([-amplitude_deg, amplitude_deg], envelope["center_" + axis + "_deg"]):
				return _failure("DEPTH_ANGULAR_ENVELOPE", path + ".motion")
		var yaw_speed_deg_s: float = float(motion.yaw_amplitude_deg) * float(motion.yaw_omega_rad_s)
		var pitch_speed_deg_s: float = float(motion.pitch_amplitude_deg) * float(motion.pitch_omega_rad_s)
		if not _close(float(motion.angular_speed_upper_bound_deg_s), sqrt(yaw_speed_deg_s * yaw_speed_deg_s + pitch_speed_deg_s * pitch_speed_deg_s)) or not _close(float(motion.radial_speed_max_m_s), amplitude_m * omega_rad_s) or not _close(float(motion.radial_acceleration_max_m_s2), amplitude_m * omega_rad_s * omega_rad_s):
			return _failure("DEPTH_DERIVED", path + ".motion")
	elif kind == "angular_ellipse":
		for axis in ["yaw", "pitch"]:
			var amplitude_deg: float = float(motion[axis + "_amplitude_deg"])
			if amplitude_deg <= 0.0 or not _contained([-amplitude_deg, amplitude_deg], envelope["center_" + axis + "_deg"]):
				return _failure("ELLIPSE_DOMAIN", path + ".motion")
		if _ellipse_peak_acceleration(motion) > float(motion.acceleration_validation_limit_deg_s2) + 0.00000001:
			return _failure("ELLIPSE_ACCELERATION_SAMPLE", path + ".motion.acceleration_validation_limit_deg_s2")
	return _success()


static func _stopping_distance_bound(maximum_speed_deg_s: float, minimum_speed_deg_s: float, nominal_s: float, acceleration_deg_s2: float) -> float:
	var duration_s: float = maxf(nominal_s, 3.0 * maximum_speed_deg_s / acceleration_deg_s2)
	var lower: float = 0.0
	var upper: float = 1.0
	for iteration in 64:
		var fraction: float = (lower + upper) * 0.5
		if maximum_speed_deg_s - (maximum_speed_deg_s + minimum_speed_deg_s) * (3.0 * fraction * fraction - 2.0 * fraction * fraction * fraction) > 0.0:
			lower = fraction
		else:
			upper = fraction
	var fraction: float = (lower + upper) * 0.5
	return duration_s * (maximum_speed_deg_s * fraction - (maximum_speed_deg_s + minimum_speed_deg_s) * (pow(fraction, 3) - pow(fraction, 4) * 0.5))


static func _ellipse_peak_acceleration(motion: Dictionary) -> float:
	var yaw_amplitude_rad: float = deg_to_rad(float(motion.yaw_amplitude_deg))
	var pitch_amplitude_rad: float = deg_to_rad(float(motion.pitch_amplitude_deg))
	var speed_rad_s: float = deg_to_rad(float(motion.path_angular_speed_deg_s))
	var peak_deg_s2: float = 0.0
	for sample_index in ELLIPSE_ACCELERATION_SAMPLES:
		var fraction_rad: float = TAU * float(sample_index) / float(ELLIPSE_ACCELERATION_SAMPLES)
		var yaw_rad: float = yaw_amplitude_rad * cos(fraction_rad)
		var pitch_rad: float = pitch_amplitude_rad * sin(fraction_rad)
		var yaw_derivative: float = -yaw_amplitude_rad * sin(fraction_rad)
		var pitch_derivative: float = pitch_amplitude_rad * cos(fraction_rad)
		var yaw_second_derivative: float = -yaw_amplitude_rad * cos(fraction_rad)
		var pitch_second_derivative: float = -pitch_amplitude_rad * sin(fraction_rad)
		var sine_yaw: float = sin(yaw_rad)
		var cosine_yaw: float = cos(yaw_rad)
		var sine_pitch: float = sin(pitch_rad)
		var cosine_pitch: float = cos(pitch_rad)
		var yaw_first: Array[float] = [cosine_pitch * cosine_yaw, 0.0, cosine_pitch * sine_yaw]
		var pitch_first: Array[float] = [-sine_pitch * sine_yaw, cosine_pitch, sine_pitch * cosine_yaw]
		var yaw_second: Array[float] = [-cosine_pitch * sine_yaw, 0.0, cosine_pitch * cosine_yaw]
		var mixed_second: Array[float] = [-sine_pitch * cosine_yaw, 0.0, -sine_pitch * sine_yaw]
		var pitch_second: Array[float] = [-cosine_pitch * sine_yaw, -sine_pitch, cosine_pitch * cosine_yaw]
		var tangent: Array[float] = []
		var second: Array[float] = []
		for axis_index in 3:
			tangent.append(yaw_first[axis_index] * yaw_derivative + pitch_first[axis_index] * pitch_derivative)
			second.append(yaw_first[axis_index] * yaw_second_derivative + pitch_first[axis_index] * pitch_second_derivative + yaw_second[axis_index] * yaw_derivative * yaw_derivative + 2.0 * mixed_second[axis_index] * yaw_derivative * pitch_derivative + pitch_second[axis_index] * pitch_derivative * pitch_derivative)
		var tangent_squared: float = Geometry.dot(tangent, tangent)
		if tangent_squared <= 0.0 or not is_finite(tangent_squared):
			return INF
		var projection: float = Geometry.dot(tangent, second) / tangent_squared
		var acceleration_squared: float = 0.0
		for axis_index in 3:
			var component: float = speed_rad_s * speed_rad_s / tangent_squared * (second[axis_index] - tangent[axis_index] * projection)
			if not is_finite(component):
				return INF
			acceleration_squared += component * component
		if not is_finite(acceleration_squared):
			return INF
		peak_deg_s2 = maxf(peak_deg_s2, rad_to_deg(sqrt(acceleration_squared)))
	return peak_deg_s2
