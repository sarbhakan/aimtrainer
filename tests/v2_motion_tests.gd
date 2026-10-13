extends SceneTree

const Motion: GDScript = preload("res://scripts/v2/v2_motion.gd")
const POSITION_EPSILON_DEG: float = 1e-9
const RATE_EPSILON: float = 1e-9
const STATE_EPSILON: float = 1e-9
const MAX_REPORTED_FAILURES: int = 20

var assertion_count: int = 0
var failure_count: int = 0
var motion_case_count: int = 0
var tape_case_count: int = 0
var sample_count: int = 0


func _initialize() -> void:
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		if failure_count <= MAX_REPORTED_FAILURES:
			push_error(description)


func run_tests() -> void:
	var fixture_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			fixture_path = argument.trim_prefix("--oracle=")
	if fixture_path.is_empty():
		fixture_path = "/tmp/aimlocal-v2-motion-%d.json" % OS.get_process_id()
		var output: Array = []
		var result: int = OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tools/v2_motion_oracle.py"), "--output", fixture_path]), output, true)
		check(result == 0, "Python motion oracle failed: " + str(output))
		if result != 0:
			finish()
			return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	check(parsed is Dictionary, "Motion oracle fixture must be a dictionary: " + fixture_path)
	if not parsed is Dictionary:
		finish()
		return
	var fixture: Dictionary = decode_binary64(parsed)
	check(fixture.float_encoding == "ieee754_binary64_little_endian_hex", "Oracle must transfer binary64 inputs exactly across JSON parsing")
	check(fixture.compiler_version == Motion.COMPILER_VERSION, "Motion compiler version differs from archived reference")
	check(int(fixture.phase_count) == 54 and fixture.levels.size() == 3 and fixture.kinds.size() == 8, "Oracle must exercise 54 phases, three difficulties, and all eight primitive kinds")
	for relative_path: String in fixture.input_sha256:
		var source_path: String = "res://docs/reference/v2/" + relative_path
		check(FileAccess.get_sha256(source_path) == fixture.input_sha256[relative_path], "Oracle source provenance mismatch: " + source_path)
	for field: String in fixture.coverage:
		check(int(fixture.coverage[field]) > 0, "Oracle misses reactive edge: " + field)
	check(int(fixture.wall_landing_ties) > 0 and int(fixture.soft_cycle_fractions) > 0, "Oracle must cover wall/landing ties and conditioned smooth cycle fractions")
	for case: Dictionary in fixture.reactive_cases:
		test_reactive_case(case)
	for case: Dictionary in fixture.cases:
		test_motion_case(case)
	test_negative_controls(fixture)
	print("V2 MOTION COVERAGE: %d phases, %s, %s, reactive=%s, wall_landing_ties=%d." % [int(fixture.phase_count), str(fixture.levels), str(fixture.kinds), str(fixture.coverage), int(fixture.wall_landing_ties)])
	finish()


func finish() -> void:
	print("V2 MOTION: %d assertions, %d failures; %d motion states, %d reactive tapes, %d samples." % [assertion_count, failure_count, motion_case_count, tape_case_count, sample_count])
	quit(0 if failure_count == 0 else 1)


func decode_binary64(value: Variant) -> Variant:
	if value is Dictionary:
		for key: String in value:
			value[key] = decode_binary64(value[key])
	elif value is Array:
		for element_index: int in value.size():
			value[element_index] = decode_binary64(value[element_index])
	elif typeof(value) == TYPE_STRING and String(value).begins_with("f64:"):
		return String(value).substr(4).hex_decode().decode_double(0)
	return value


func compare_value(actual: Variant, expected: Variant, path: String, epsilon: float = STATE_EPSILON, exact_keys: bool = true) -> void:
	if expected is Dictionary:
		check(actual is Dictionary, path + " must be a dictionary")
		if not actual is Dictionary:
			return
		if exact_keys:
			check(actual.size() == expected.size(), "%s key count: got=%d expected=%d" % [path, actual.size(), expected.size()])
		for key: String in expected:
			check(actual.has(key), path + " missing key: " + key)
			if actual.has(key):
				compare_value(actual[key], expected[key], path + "." + key, epsilon)
	elif expected is Array:
		check(actual is Array, path + " must be a binary64 array")
		if not actual is Array:
			return
		check(actual.size() == expected.size(), "%s array size: got=%d expected=%d" % [path, actual.size(), expected.size()])
		for element_index: int in mini(actual.size(), expected.size()):
			compare_value(actual[element_index], expected[element_index], path + "[%d]" % element_index, epsilon)
	elif typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		check(typeof(actual) in [TYPE_INT, TYPE_FLOAT], path + " must be numeric")
		if typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
			var difference: float = absf(float(actual) - float(expected))
			check(is_finite(float(actual)) and difference <= epsilon, "%s got=%.17f expected=%.17f difference=%.17f limit=%.12f" % [path, float(actual), float(expected), difference, epsilon])
	else:
		check(actual == expected, "%s got=%s expected=%s" % [path, str(actual), str(expected)])


func test_reactive_case(case: Dictionary) -> void:
	tape_case_count += 1
	var label: String = String(case.label)
	var tape: Dictionary = Motion.compile_reactive(case.motion, int(case.seed), float(case.horizon_s), case.initial_yaw_deg)
	check(not tape.is_empty(), label + " compiler returned an empty tape")
	if tape.is_empty():
		return
	compare_value(tape, case.tape, label + ".tape")
	var snapshot: Dictionary = tape.duplicate(true)
	for sample_index: int in range(case.samples.size() - 1, -1, -1):
		var expected_sample: Dictionary = case.samples[sample_index]
		var time_s: float = float(expected_sample.time_s)
		var actual: Array[float] = Motion.sample_reactive(tape, time_s)
		sample_count += 1
		compare_value(actual, expected_sample.expected, "%s.sample(%.17f)" % [label, time_s], POSITION_EPSILON_DEG)
		check(actual == Motion.sample_reactive(tape, time_s), label + " repeated reactive query changes its result")
	check(tape == snapshot, label + " sampling mutates the compiled tape")
	var previous_s: float = 0.0
	var previous_event_us: int = -1
	for piece: Dictionary in tape.pieces:
		check(float(piece.from_s) == previous_s and float(piece.to_s) > float(piece.from_s), label + " empty, overlapping, or gapped piece")
		previous_s = float(piece.to_s)
	check(absf(previous_s - float(case.horizon_s)) <= 1e-9, label + " incomplete horizon")
	for event: Dictionary in tape.events:
		check(int(event.time_us) > previous_event_us, label + " duplicate or reversed event timestamp")
		previous_event_us = int(event.time_us)
		if event.kind == "rearm":
			verify_rearm_origin(tape, int(event.time_us), label)


func verify_rearm_origin(tape: Dictionary, time_us: int, label: String) -> void:
	var pieces: Array = tape.pieces
	for piece_index: int in range(pieces.size() - 1):
		var before: Dictionary = pieces[piece_index]
		if int(round(float(before.to_s) * 1000000.0)) != time_us:
			continue
		if before.shape == "ramp" and float(before.to_s) < float(before.origin_s) + float(before.duration_s) - 0.000001:
			var after: Dictionary = pieces[piece_index + 1]
			for field: String in ["shape", "origin_s", "x_origin_deg", "v0_deg_s", "v1_deg_s", "duration_s"]:
				check(before[field] == after[field], "%s rearm at %d us rebases %s" % [label, time_us, field])
		return


func test_motion_case(case: Dictionary) -> void:
	motion_case_count += 1
	var label: String = String(case.label)
	var definition: Dictionary = case.motion
	var definition_snapshot: Dictionary = definition.duplicate(true)
	var state: Dictionary = Motion.build(definition, int(case.seed)) if bool(case.default_build) else Motion.build(definition, int(case.seed), int(case.slot), float(case.horizon_s))
	check(not state.is_empty(), label + " build returned an empty state")
	if state.is_empty():
		return
	var unplaced: Dictionary = state.duplicate(true)
	if case.origin != null:
		state = Motion.with_origin(state, float(case.origin[0]), float(case.origin[1]))
		check(unplaced == Motion.build(definition, int(case.seed), int(case.slot), float(case.horizon_s)), label + " origin helper mutates its input or changes random draws")
	elif case.cycle != null:
		state = Motion.with_cycle(state, float(case.cycle))
		check(unplaced == Motion.build(definition, int(case.seed), int(case.slot), float(case.horizon_s)), label + " cycle helper mutates its input or changes random draws")
	if state.is_empty():
		check(false, label + " placement returned an empty state")
		return
	compare_value(state, case.state, label + ".state", STATE_EPSILON, false)
	var snapshot: Dictionary = state.duplicate(true)
	var global_bound_deg_s: float = Motion.velocity_bound_deg_s(state, 0.0, float(case.horizon_s))
	for sample_index: int in range(case.samples.size() - 1, -1, -1):
		var expected_sample: Dictionary = case.samples[sample_index]
		var time_s: float = float(expected_sample.time_s)
		var actual: Dictionary = Motion.sample(state, time_s)
		sample_count += 1
		compare_pose(actual, expected_sample.expected, "%s.sample(%.17f)" % [label, time_s])
		check(actual == Motion.sample(state, time_s), label + " repeated motion query changes its result")
		if actual.is_empty():
			continue
		var speed_deg_s: float = sqrt(pow(cos(deg_to_rad(float(actual.pitch_deg))) * float(actual.yaw_rate_deg_s), 2.0) + pow(float(actual.pitch_rate_deg_s), 2.0))
		check(speed_deg_s <= global_bound_deg_s + 1e-10, "%s nonconservative global speed bound at %.17f: speed=%.17f bound=%.17f" % [label, time_s, speed_deg_s, global_bound_deg_s])
		if sample_index % 37 == 0:
			var local_bound_deg_s: float = Motion.velocity_bound_deg_s(state, time_s - 0.000001, time_s + 0.000001)
			check(speed_deg_s <= local_bound_deg_s + 1e-10, "%s nonconservative local speed bound at %.17f: speed=%.17f bound=%.17f" % [label, time_s, speed_deg_s, local_bound_deg_s])
	check(state == snapshot and definition == definition_snapshot, label + " queries mutate runtime state or source motion")
	for timestamp_index: int in 13:
		var time_s: float = float(timestamp_index) / 6.0
		var baseline: Dictionary = Motion.sample(state, time_s)
		for frame_rate: int in [60, 144, 240]:
			var frame_time_s: float = round(time_s * float(frame_rate)) / float(frame_rate)
			check(Motion.sample(state, frame_time_s) == baseline, "%s timestamp %.17f depends on %d FPS" % [label, time_s, frame_rate])
	if state.kind == "angular_ellipse":
		check(state.ellipse.prefix.size() == int(definition.arc_length_solver.lut_cells) + 1, label + " ellipse LUT size differs from the source solver")
		for probe_index: int in 33:
			var pose: Dictionary = Motion.sample(state, float(case.horizon_s) * float(probe_index) / 32.0)
			var speed_deg_s: float = sqrt(pow(cos(deg_to_rad(float(pose.pitch_deg))) * float(pose.yaw_rate_deg_s), 2.0) + pow(float(pose.pitch_rate_deg_s), 2.0))
			check(absf(speed_deg_s - float(definition.path_angular_speed_deg_s)) <= RATE_EPSILON, label + " ellipse rates do not use the spherical metric")


func compare_pose(actual: Dictionary, expected: Dictionary, label: String) -> void:
	check(actual.size() == 6, label + " sample must expose exactly six scalar fields")
	for field: String in expected:
		check(actual.has(field), label + " missing field: " + field)
		if actual.has(field):
			compare_value(actual[field], expected[field], label + "." + field, RATE_EPSILON if field.contains("rate") else POSITION_EPSILON_DEG)


func test_negative_controls(fixture: Dictionary) -> void:
	var reference_case: Dictionary = fixture.reactive_cases[0]
	var original: Dictionary = reference_case.tape
	var corrupted: Dictionary = original.duplicate(true)
	corrupted.pieces[0].x_origin_deg = float(corrupted.pieces[0].x_origin_deg) + 0.25
	var source_sample: Array[float] = Motion.sample_reactive(original, 0.0)
	var corrupted_sample: Array[float] = Motion.sample_reactive(corrupted, 0.0)
	check(absf(corrupted_sample[0] - source_sample[0]) > POSITION_EPSILON_DEG, "Oracle comparisons must reject a corrupted reactive origin")
	corrupted = original.duplicate(true)
	corrupted.events[0].time_us = int(corrupted.events[0].time_us) + 1
	check(corrupted != original, "Exact event comparisons must reject a one-microsecond event corruption")
