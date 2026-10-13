extends SceneTree

const Catalog := preload("res://scripts/v2/v2_catalog.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("V2 catalogue tests did not finish.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_tests() -> void:
	test_catalogue_and_independent_definitions()
	test_original_byte_guard()
	test_supplied_schema()
	test_required_fields_and_types()
	test_semantic_mutations()
	test_size_and_lifecycle_variants()
	test_arbitrary_valid_definition()
	print("V2 CATALOGUE : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_catalogue_and_independent_definitions() -> void:
	var root := Catalog.load_catalog()
	check(not root.is_empty(), "The original V2 catalogue loads: " + Catalog.last_error)
	if root.is_empty():
		return
	check(root.catalogue_revision == Catalog.REVISION and Catalog.REVISION == "2026-10-12-v2.0", "Runtime revision comes from the original catalogue.")
	check(root.schema_version == "aimlocal.catalogue.v2" and root.configuration_count == 24 and root.public_program_count == 8, "Original root keys and declared counts remain authoritative.")
	check(root.keys().size() == 9 and not root.has("configs"), "The original nine-key catalogue root is retained.")
	var definitions: Array = Catalog.programs()
	check(definitions.size() == 24, "Eight programs have all three resolved difficulties.")
	var identities: Dictionary = {}
	var phase_count: int = 0
	for definition in definitions:
		var identity: String = String(definition.program_id) + "/" + String(definition.difficulty)
		check(not identities.has(identity), "Program/difficulty identity is unique: " + identity)
		identities[identity] = true
		phase_count += definition.phases.size()
		var result := Catalog.validate_program(definition)
		check(result.ok, "Original definition validates: " + identity + " " + str(result))
		check(result.get("definition_sha256", "") == Canonical.semantic_sha256(definition), "Definition fingerprint uses AIM-CANON-1: " + identity)
		check(Catalog.find(definition.program_id, definition.difficulty) == definition, "Find returns the exact variant: " + identity)
	check(phase_count == 54, "The native catalogue contains all 54 phases.")
	var changed := Catalog.find("EX01", "standard")
	changed.phases[0].diameter_deg = 99.0
	changed.arena.eye_position_m[1] = 99.0
	check(Catalog.find("EX01", "standard").phases[0].diameter_deg == 1.2, "Find returns a deep duplicate of phase parameters.")
	check(Catalog.find("EX01", "standard").arena.eye_position_m[1] == 1.6, "Nested arena state is independent.")
	definitions[0].phases.clear()
	root.programs.clear()
	check(Catalog.programs().size() == 24 and Catalog.programs()[0].phases.size() == 3, "Root and programs results cannot modify the source catalogue.")
	check(Catalog.find("EX99", "standard").is_empty() and Catalog.find("EX01", "expert").is_empty(), "Unknown variants do not fall back to a default.")


func test_original_byte_guard() -> void:
	var original := FileAccess.get_file_as_bytes(Catalog.CATALOGUE_PATH)
	check(Catalog.validate_catalogue_bytes(original).ok, "The pinned original bytes pass the raw-file SHA-256 guard.")
	var changed := original.duplicate()
	changed.append(10)
	var result := Catalog.validate_catalogue_bytes(changed)
	check(not result.ok and result.code == "CATALOGUE_SHA256", "Even an extra newline refuses unknown catalogue bytes.")
	for raw in [PackedByteArray(), "{}".to_utf8_buffer(), '{"programs":[],"programs":[]}'.to_utf8_buffer(), '{"programs":[NaN]}'.to_utf8_buffer()]:
		result = Catalog.validate_catalogue_bytes(raw)
		check(not result.ok and result.code == "CATALOGUE_SHA256", "Unverified parser inputs cannot bypass the original byte guard.")


func test_supplied_schema() -> void:
	var schema := Catalog.catalogue_schema()
	check(not schema.is_empty() and schema["$defs"].size() == 14, "The fourteen original named schema definitions are embedded.")
	check(Catalog.SCHEMA_SOURCE_SHA256 == "211563525acb4c23dada3351386cb84f2b6f59bb6761ea7b0f8bee82186743e6", "Schema ownership records the original supplied source SHA.")
	var source_path: String = "res://docs/reference/v2/schemas/catalogue.schema.json"
	if FileAccess.file_exists(source_path):
		var original: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
		check(schema == original, "Embedded schema dictionary equals the verbatim supplied schema.")
	schema["unevaluatedProperties"] = false
	var result := Catalog._check_schema_subset(schema)
	check(not result.ok and result.code == "SCHEMA_UNSUPPORTED_KEYWORD", "Unsupported schema keywords fail closed.")
	schema.erase("unevaluatedProperties")
	schema["$defs"].Program["$ref"] = "https://example.invalid/schema.json"
	result = Catalog._check_schema_subset(schema)
	check(not result.ok and result.code == "SCHEMA_NONLOCAL_REFERENCE", "Only local supplied schema references can resolve.")
	check(not Catalog.catalogue_schema()["$defs"].Program.has("$ref"), "Schema access returns an independent dictionary.")


func expect_rejected(config: Dictionary, description: String, expected_code: String = "") -> void:
	var result := Catalog.validate_program(config)
	check(result.has("ok") and result.has("error") and result.has("code") and result.has("path"), "Validation returns the public result contract: " + description)
	check(not result.ok and not String(result.code).is_empty() and String(result.path).begins_with("$"), "Invalid definition is rejected with a path: " + description + " " + str(result))
	if not expected_code.is_empty():
		check(result.code == expected_code, "Rejection code identifies the violated contract: " + description + " " + str(result))


func test_required_fields_and_types() -> void:
	var original := Catalog.find("EX01", "standard")
	for field in original:
		var changed: Dictionary = original.duplicate(true)
		changed.erase(field)
		expect_rejected(changed, "Missing program field " + String(field), "SCHEMA_REQUIRED")
	for field in original.phases[0]:
		var changed: Dictionary = original.duplicate(true)
		changed.phases[0].erase(field)
		expect_rejected(changed, "Missing phase field " + String(field), "SCHEMA_REQUIRED")
	for field in ["target_count", "diameter_deg", "distance_m", "start_s", "duration_s"]:
		var changed: Dictionary = original.duplicate(true)
		changed.phases[0][field] = true
		expect_rejected(changed, "Boolean cannot become numeric " + field, "SCHEMA_TYPE")
	for value in [NAN, INF, -INF]:
		var changed: Dictionary = original.duplicate(true)
		changed.phases[0].diameter_deg = value
		expect_rejected(changed, "Nonfinite required scalar", "JSON_NONFINITE")
	var changed: Dictionary = original.duplicate(true)
	changed.phases[0].target_count = 9007199254740992
	expect_rejected(changed, "Unsafe integer", "JSON_UNSAFE_INTEGER")
	changed = original.duplicate(true)
	changed[7] = "nonstring key"
	expect_rejected(changed, "Nonstring dictionary key", "JSON_NONSTRING_KEY")
	changed = original.duplicate(true)
	changed.phases[0].diameter_deg = Vector2.ONE
	expect_rejected(changed, "Unsupported engine value", "JSON_TYPE")
	for field in ["static_positions", "opportunities", "states"]:
		changed = original.duplicate(true)
		changed.phases[0][field] = []
		expect_rejected(changed, "Illustrative sample cannot enter a phase definition: " + field, "SCHEMA_ADDITIONAL_PROPERTY")
	changed = original.duplicate(true)
	changed.phases[0].motion["yaw_speed_deg_s"] = 10
	expect_rejected(changed, "Static motion rejects unused dynamic parameters", "SCHEMA_ONEOF")
	changed = original.duplicate(true)
	changed.program_id = "EX99"
	expect_rejected(changed, "Unknown public program", "SCHEMA_ENUM")
	changed = original.duplicate(true)
	changed.difficulty = "expert"
	expect_rejected(changed, "Unknown difficulty", "SCHEMA_ENUM")


func set_phase_field(config: Dictionary, phase_index: int, fields: Array, value: Variant) -> void:
	var target: Variant = config.phases[phase_index]
	for index in fields.size() - 1:
		target = target[fields[index]]
	target[fields[-1]] = value


func test_semantic_mutations() -> void:
	var cases: Array = [
		["EX01", 1, ["start_s"], 21.0, "Phase gap", "PHASE_CONTIGUITY"],
		["EX01", 1, ["start_s"], 19.0, "Phase overlap", "PHASE_CONTIGUITY"],
		["EX01", 2, ["duration_s"], 19.0, "Wrong phase duration", "PHASE_DURATION"],
		["EX01", 0, ["spawn", "target_slots"], 2, "Target count disagrees with slots", "TARGET_COUNT"],
		["EX01", 0, ["target_count"], 7, "Pool capacity above six", "TARGET_COUNT"],
		["EX01", 0, ["scoring", "phase_duration_s"], 19.0, "Score denominator duration", "SCORE_DURATION"],
		["EX01", 0, ["size", "world_radius_m"], 0.09, "Collider radius formula", "SPHERE_RADIUS"],
		["EX01", 0, ["spawn", "yaw_deg"], [6, -6], "Reversed interval", "RANGE_ORDER"],
		["EX01", 0, ["spawn", "transition_angle_deg"], [-1, 6], "Negative transition angle", "TRANSITION_DOMAIN"],
		["EX01", 1, ["spawn", "transition_band_bag", "draw_count"], 11, "Bag count mismatch", "BAG_COUNT"],
		["EX02", 1, ["spawn", "minimum_equal_size_center_separation_deg"], 0.75, "Separation must include both silhouettes", "CENTER_SEPARATION"],
		["EX03", 0, ["lifecycle", "ttl_s"], 2.5, "Window overflow", "WINDOW_OVERFLOW"],
		["EX03", 0, ["spawn", "schedule", "slots"], 11, "Exactly ten opportunities", "WINDOW_SCHEDULE"],
		["EX03", 1, ["size", "diameter_end_deg"], 1.9, "Fixed sixty percent shrink ratio", "WINDOW_SIZE"],
		["EX03", 1, ["size", "progress_duration_s"], 0.5, "Shrink belongs to the logical window", "WINDOW_SIZE"],
		["EX04", 0, ["spawn", "candidate_yaw_deg"], [-30, 30], "Candidate exceeds spawn domain", "CANDIDATE_ENVELOPE"],
		["EX04", 2, ["motion", "pitch_acceleration_deg_s2"], -9.81, "Angular parabola is not earth gravity", "BOUNCE_DERIVED"],
		["EX04", 2, ["spawn", "transition_angle_deg"], [4, 180], "Impossible chamber replacement distance", "CHAMBER_RESPAWN"],
		["EX05", 0, ["motion", "omega_rad_s"], 2.0, "Sine speed coefficients", "SINUSOID_DERIVED"],
		["EX05", 2, ["motion", "acceleration_validation_limit_deg_s2"], 1.0, "Ellipse sampled acceleration limit", "ELLIPSE_ACCELERATION_SAMPLE"],
		["EX06", 0, ["motion", "plateau_duration_mixture", 0, "weight"], 0.6, "Unnormalized mixture", "MIXTURE_WEIGHTS"],
		["EX06", 0, ["motion", "boundary", "trigger_inset_deg"], 0.1, "No room for a reactive turn", "BRAKING_DISTANCE"],
		["EX06", 0, ["motion", "event_tape", "horizon_s"], 10.0, "Event tape horizon", "EVENT_HORIZON"],
		["EX07", 0, ["motion", "radial_speed_max_m_s"], 0.9, "Depth radial speed formula", "DEPTH_DERIVED"],
		["EX08", 1, ["motion", "turn_entry_inset_deg"], 0.1, "Smooth reflection inset", "SOFT_REFLECT_DERIVED"],
		["EX08", 0, ["lifecycle", "ideal_contact_time_to_kill_s"], 0.2, "Real sustained damage time", "SWITCH_HP"],
		["EX08", 0, ["lifecycle", "hp_regeneration_per_s"], 1.0, "No unannounced regeneration", "SWITCH_DAMAGE"]
	]
	for case in cases:
		var config := Catalog.find(case[0], "standard")
		set_phase_field(config, int(case[1]), case[2], case[3])
		expect_rejected(config, case[4], case[5])
	var config := Catalog.find("EX01", "standard")
	config.duration_s = 59.0
	expect_rejected(config, "Public programs remain 60 seconds", "PROGRAM_DURATION")
	config = Catalog.find("EX01", "standard")
	config.phases.remove_at(2)
	expect_rejected(config, "Missing public phase", "PHASE_COUNT")
	config = Catalog.find("EX01", "standard")
	var first: Dictionary = config.phases[0]
	config.phases[0] = config.phases[1]
	config.phases[1] = first
	config.phases[0].start_s = 0.0
	config.phases[1].start_s = 20.0
	expect_rejected(config, "Retiming does not authorize reordered phases", "PHASE_IDENTITY")
	config = Catalog.find("EX01", "standard")
	config.arena.fov_vertical_deg = 60.0
	expect_rejected(config, "Reference FOV relationship", "REFERENCE_FOV")
	config = Catalog.find("EX01", "standard")
	config.phases[0].envelope.center_pitch_deg = [-40, -30]
	config.phases[0].spawn.pitch_deg = [-40, -30]
	expect_rejected(config, "Full sphere floor clearance", "FLOOR_CLEARANCE")
	config = Catalog.find("EX01", "standard")
	config.phases[0].envelope.center_yaw_deg = [60, 75]
	config.phases[0].spawn.yaw_deg = [60, 75]
	expect_rejected(config, "Full sphere frustum clearance", "FRUSTUM_CLEARANCE")
	config = Catalog.find("EX08", "standard")
	config.phases[1].lifecycle.hp_max = 41.0
	config.phases[1].scoring.hp_max = 41.0
	config.phases[1].lifecycle.ideal_contact_time_to_kill_s = 0.41
	expect_rejected(config, "HP stays identical across switching phases", "SWITCH_PHASE_CONDITIONS")
	config = Catalog.find("EX04", "standard")
	config.phases[1].motion.lanes_pitch_deg = [-3, -1, 1, 3]
	config.phases[1].spawn.lane_pitch_deg = [-3, -1, 1, 3]
	expect_rejected(config, "Lane motion preserves silhouette clearance", "LANE_SEPARATION")
	config = Catalog.find("EX05", "standard")
	config.phases[2].motion.yaw_amplitude_deg = 1.0e-200
	config.phases[2].motion.pitch_amplitude_deg = 1.0e-200
	expect_rejected(config, "A numerically collapsed ellipse cannot divide by zero", "ELLIPSE_ACCELERATION_SAMPLE")
	config = Catalog.find("EX05", "standard")
	config.phases[2].motion.yaw_amplitude_deg = 0.0
	config.phases[2].motion.pitch_amplitude_deg = 0.0
	expect_rejected(config, "Zero amplitude violates the ellipse domain", "ELLIPSE_DOMAIN")
	check(not Catalog._close(INF, 1.0), "Overflowing derived values cannot pass a relative tolerance.")


func test_size_and_lifecycle_variants() -> void:
	for definition in Catalog.programs():
		for index in definition.phases.size():
			var phase: Dictionary = definition.phases[index]
			var window_shrink: bool = definition.program_id == "EX03" and phase.id == "shrinking_window"
			check(phase.size.shrink == window_shrink, "Shrink belongs only to the EX03 shrinking window.")
			check((phase.lifecycle.ttl_s != null) == (definition.program_id == "EX03"), "Only EX03 has a target TTL.")
			if definition.program_id == "EX08" and phase.id == "mobile":
				check(phase.motion.kind == "linear_reflect" and phase.motion.reflection == "symmetric_cubic_smoothstep_velocity", "EX08 uses the reflection modifier without renaming kind.")
				check(phase.motion.finite_acceleration_limit_applies, "EX08 smooth reflection has finite acceleration.")
			if definition.program_id == "EX04" and phase.id == "linear":
				check(phase.motion.reflection == "instantaneous_velocity_sign_change" and not phase.motion.finite_acceleration_limit_applies, "EX04 linear reflection keeps its explicit velocity impulse.")
	var config := Catalog.find("EX01", "standard")
	config.phases[0].lifecycle.ttl_s = 10.0
	expect_rejected(config, "Generic expiry cannot enter free click")
	config = Catalog.find("EX05", "standard")
	config.phases[0].lifecycle.ttl_s = 10.0
	expect_rejected(config, "Tracking does not respawn periodically")
	config = Catalog.find("EX01", "standard")
	config.phases[0].size = Catalog.find("EX03", "standard").phases[1].size.duplicate(true)
	expect_rejected(config, "Complete shrink parameters do not authorize shrink in EX01")
	config = Catalog.find("EX07", "standard")
	config.phases[0].motion.no_screen_size_compensation = false
	expect_rejected(config, "Depth cannot compensate the apparent diameter")
	config = Catalog.find("EX05", "standard")
	config.phases[0].scoring.exposure_never_retimed = false
	expect_rejected(config, "First-render gating never retimes exposure")
	config = Catalog.find("EX03", "standard")
	config.phases[0].lifecycle.human_miss_on_nonpresented_opportunity = true
	expect_rejected(config, "Render failure is not a human miss")
	config = Catalog.find("EX08", "standard")
	config.phases[1].motion.reflection = "instantaneous_velocity_sign_change"
	expect_rejected(config, "Changing only the reflection modifier cannot replace the model")


func test_arbitrary_valid_definition() -> void:
	var original := Catalog.find("EX01", "standard")
	var changed: Dictionary = original.duplicate(true)
	changed.phases[0].diameter_deg = 1.1
	changed.phases[0].size.world_radius_m = 4.0 * sin(deg_to_rad(1.1 * 0.5))
	var result := Catalog.validate_program(changed)
	check(result.ok, "Arbitrary definitions receive schema and semantic validation: " + str(result))
	check(result.get("definition_sha256", "") != Catalog.fingerprint(original), "A valid changed definition gets its own mechanical fingerprint.")
	var float_counts: Dictionary = original.duplicate(true)
	float_counts.phases[0].target_count = 1.0
	float_counts.phases[0].spawn.target_slots = 1.0
	result = Catalog.validate_program(float_counts)
	check(result.ok and result.definition_sha256 == Catalog.fingerprint(original), "Integral JSON numbers accept decimal notation without becoming booleans or changing hashes.")
	var ellipse := Catalog.find("EX05", "standard")
	ellipse.phases[2].motion.path_angular_speed_deg_s = 20.0
	ellipse.phases[2].motion.acceleration_validation_limit_deg_s2 = 100.0
	result = Catalog.validate_program(ellipse)
	check(result.ok, "A new valid ellipse uses its calculated acceleration rather than a hard-coded difficulty ceiling: " + str(result))
