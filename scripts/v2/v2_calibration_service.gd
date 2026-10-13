class_name V2CalibrationService
extends RefCounted

const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const RandomStream := preload("res://scripts/v2/v2_random.gd")
const Motion := preload("res://scripts/v2/v2_motion.gd")
const PROTOCOL_ID: String = "sustained_blocks_v2"
const PROTOCOL_SHA256: String = "70a6875973728295520f8d55e711055013330f84d468adbf0d399f33271fc562"
const REVISION: String = "2026-10-12-v2.0"
const HASH_ENCODING: String = "AIM-CANON-1"
const PROTOCOL_PATH: String = "res://content/v2/calibration_v2_protocol.json"
const CATALOGUE_PATH: String = "res://content/v2/catalogue.v2.json"
const TASKS: Array[String] = ["CLICK", "SMOOTH", "REACTIVE", "SWITCH"]
const DAY1_TASK_ORDER: Array[String] = ["CLICK", "SMOOTH", "SWITCH", "REACTIVE"]
const DAY2_TASK_ORDER: Array[String] = ["REACTIVE", "SWITCH", "SMOOTH", "CLICK"]
const OBJECTIVES: Dictionary = {
	"polyvalent": {"CLICK": 0.25, "SMOOTH": 0.25, "REACTIVE": 0.25, "SWITCH": 0.25},
	"acquisition": {"CLICK": 0.45, "SMOOTH": 0.15, "REACTIVE": 0.15, "SWITCH": 0.25},
	"tracking": {"CLICK": 0.15, "SMOOTH": 0.30, "REACTIVE": 0.35, "SWITCH": 0.20}
}
const NUMERIC_TOLERANCE: float = 1.0e-9
const MAX_SAFE_INTEGER: int = 9007199254740991
const CONDITION_FIELDS: Array[String] = [
	"declared_dpi", "fov_horizontal_deg_at_16_9", "render_resolution_px", "render_scale",
	"renderer", "frame_limit_hz", "display_hz_declared", "vsync", "input_convention",
	"crosshair", "target_palette", "audio", "seeded_scored_stimulus_preview", "candidate_value_masking"
]
const ACTUAL_CONDITION_FIELDS: Array[String] = ["dpi_source", "rendering_driver", "os", "engine_version"]


static func protocol() -> Dictionary:
	return _read_dictionary(PROTOCOL_PATH)


static func protocol_hash() -> String:
	var snapshot: Dictionary = protocol()
	return Canonical.semantic_sha256(snapshot) if not snapshot.is_empty() else ""


static func _read_dictionary(path: String) -> Dictionary:
	var parser := JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code, "errors": [code]}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum and float(value) == floor(float(value))


static func _bits(value: float) -> String:
	return Canonical.float64_hex(value)


static func _decimal17(value: float) -> String:
	if value == 0.0:
		return "0"
	var exponent: int = int(floor(log(absf(value)) / log(10.0)))
	while absf(value) < pow(10.0, exponent):
		exponent -= 1
	while absf(value) >= pow(10.0, exponent + 1):
		exponent += 1
	var decimal: String = ("%." + str(maxi(0, 16 - exponent)) + "f") % value
	if decimal.contains("."):
		decimal = decimal.rstrip("0").rstrip(".")
	if exponent >= -4 and exponent < 17:
		return decimal
	var digits: String = decimal.replace(".", "").trim_prefix("-").lstrip("0").rstrip("0")
	var mantissa: String = digits.substr(0, 1)
	if digits.length() > 1:
		mantissa += "." + digits.substr(1)
	return ("-" if value < 0.0 else "") + mantissa + "e" + ("-" if exponent < 0 else "+") + ("%02d" % absi(exponent))


static func gain_value(gain: Dictionary) -> float:
	var encoded: Variant = gain.get("degrees_per_relative_input_unit")
	if not encoded is Dictionary or not encoded.get("ieee754_binary64_big_endian_hex") is String:
		return NAN
	return Canonical.float64_from_hex(encoded.ieee754_binary64_big_endian_hex)


static func make_gain(candidate_id: String, cm: float, dpi: float = 800.0, applied_gain: Variant = null) -> Dictionary:
	if candidate_id.is_empty() or not is_finite(cm) or cm <= 0.0 or not _integer(dpi, 1, MAX_SAFE_INTEGER):
		return _error("INVALID_GAIN")
	if applied_gain != null and not _number(applied_gain):
		return _error("INVALID_GAIN")
	var actual_gain: float = float(applied_gain) if applied_gain != null else 914.4 / (dpi * cm)
	if not is_finite(actual_gain) or actual_gain <= 0.0:
		return _error("INVALID_GAIN")
	return {
		"candidate_id": candidate_id, "requested_cm_per_360": cm,
		"effective_cm_per_360": 914.4 / (dpi * actual_gain), "declared_dpi": dpi,
		"degrees_per_relative_input_unit": {"decimal_roundtrip": _decimal17(actual_gain), "ieee754_binary64_big_endian_hex": _bits(actual_gain)},
		"runtime_gain_precision": "IEEE754_binary64", "cm_label_is_nominal_because_dpi_is_declared": true
	}


static func verify_gains(gains: Array, qa_allow_identical: bool = false) -> Dictionary:
	var identities: Dictionary = {}
	var known_bits: Dictionary = {}
	for entry: Variant in gains:
		if not entry is Dictionary:
			return _error("INVALID_GAIN")
		var gain: Dictionary = entry
		var identity: Variant = gain.get("candidate_id")
		if not identity is String or identity.is_empty():
			return _error("INVALID_GAIN")
		if identities.has(identity):
			return _error("DUPLICATE_CANDIDATE_ID")
		identities[identity] = true
		var encoded_gain: Variant = gain.get("degrees_per_relative_input_unit")
		if not encoded_gain is Dictionary or not encoded_gain.get("ieee754_binary64_big_endian_hex") is String:
			return _error("GAIN_DECIMAL_BITS_MISMATCH")
		var value: float = gain_value(gain)
		if not is_finite(value) or value <= 0.0:
			return _error("GAIN_DECIMAL_BITS_MISMATCH")
		if not is_finite(value) or value <= 0.0 or not _integer(gain.get("declared_dpi"), 1, MAX_SAFE_INTEGER):
			return _error("INVALID_GAIN")
		var bit_string: String = _bits(value)
		if not gain.degrees_per_relative_input_unit.get("decimal_roundtrip") is String or _decimal17(value) != gain.degrees_per_relative_input_unit.decimal_roundtrip:
			return _error("GAIN_DECIMAL_BITS_MISMATCH")
		if known_bits.has(bit_string) and not qa_allow_identical:
			return _error("DUPLICATE_EFFECTIVE_GAIN")
		known_bits[bit_string] = true
		var actual_cm: float = 914.4 / (float(gain.declared_dpi) * value)
		if not _number(gain.get("effective_cm_per_360")) or absf(actual_cm - float(gain.effective_cm_per_360)) > 1.0e-10:
			return _error("GAIN_CM_MISMATCH")
		if actual_cm < 5.0 or actual_cm > 150.0:
			return _error("GAIN_OUT_OF_SEARCH_BOUNDS")
		if gain.get("runtime_gain_precision") != "IEEE754_binary64" or gain.get("cm_label_is_nominal_because_dpi_is_declared") != true:
			return _error("GAIN_PRECISION_OR_UNIT_MISMATCH")
	return {"ok": true, "error": ""}


static func candidate_grid(baseline: Dictionary, ratio: float = 1.25) -> Dictionary:
	if ratio != 1.25 and ratio != 1.50:
		return _error("UNDECLARED_GRID_RATIO")
	var verified: Dictionary = verify_gains([baseline])
	if not verified.ok:
		return verified
	if baseline.candidate_id != "A":
		return _error("BASELINE_ID_MUST_BE_A")
	var baseline_cm: float = baseline.effective_cm_per_360
	var dpi: float = baseline.declared_dpi
	var minimum_exponent: int = int(ceil(log(5.0 / baseline_cm) / log(ratio) - 1.0e-12))
	var maximum_exponent: int = int(floor(log(150.0 / baseline_cm) / log(ratio) + 1.0e-12))
	var exponent_span: int = maxi(absi(minimum_exponent), absi(maximum_exponent))
	var chosen: Array = [baseline.duplicate(true)]
	var known_bits: Dictionary = {baseline.degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex: true}
	for magnitude: int in range(1, exponent_span + 1):
		for exponent: int in [-magnitude, magnitude]:
			if exponent < minimum_exponent or exponent > maximum_exponent:
				continue
			var requested_cm: float = baseline_cm * pow(ratio, exponent)
			var applied_gain: float = 914.4 / (dpi * requested_cm)
			var effective_cm: float = 914.4 / (dpi * applied_gain)
			if effective_cm < 5.0 or effective_cm > 150.0 or maxf(effective_cm / baseline_cm, baseline_cm / effective_cm) > 1.50 + 1.0e-12:
				continue
			var bit_string: String = _bits(applied_gain)
			if known_bits.has(bit_string):
				continue
			var identity: String = "C_" + ("m" if exponent < 0 else "p") + str(absi(exponent))
			var gain: Dictionary = make_gain(identity, requested_cm, dpi, applied_gain)
			gain["grid_exponent"] = exponent
			gain["representation_adapter_applied"] = false
			chosen.append(gain)
			known_bits[bit_string] = true
			if chosen.size() == 3:
				return {"ok": true, "error": "", "gains": chosen}
	if chosen.size() < 2:
		return _error("NO_DISTINCT_REPRESENTABLE_LOCAL_CHALLENGER")
	return {"ok": true, "error": "", "gains": chosen}


static func _stream(plan_seed: String, phase: String, day: String, pair: String, epoch: String, task: String, domain: String) -> Dictionary:
	var parts: Array = [REVISION, plan_seed, phase, day, pair, epoch, task, domain]
	var encoded: String = JSON.stringify(parts)
	var seed: int = RandomStream.stream_seed(parts)
	return {"rng": RandomStream.new(seed), "seed": {"uint32": seed, "tuple_canonical_json": encoded, "sha256": encoded.sha256_text(), "generator": "xorshift32_v1"}}


static func _shuffle(values: Array, rng: RefCounted) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var selected_index: int = rng.randint(0, index)
		var previous: Variant = values[index]
		values[index] = values[selected_index]
		values[selected_index] = previous


static func _direction(yaw_deg: float, pitch_deg: float) -> Array:
	var yaw_rad: float = deg_to_rad(yaw_deg)
	var pitch_rad: float = deg_to_rad(pitch_deg)
	return [sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), -cos(yaw_rad) * cos(pitch_rad)]


static func _dot(first: Array, second: Array) -> float:
	var result: float = 0.0
	var correction: float = 0.0
	for axis: int in 3:
		var term: float = float(first[axis]) * float(second[axis])
		var combined: float = result + term
		correction += ((result - combined) + term) if absf(result) >= absf(term) else ((term - combined) + result)
		result = combined
	return result + correction


static func _cross(first: Array, second: Array) -> Array:
	return [first[1] * second[2] - first[2] * second[1], first[2] * second[0] - first[0] * second[2], first[0] * second[1] - first[1] * second[0]]


static func _unit(value: Array) -> Array:
	var magnitude: float = sqrt(_dot(value, value))
	return [value[0] / magnitude, value[1] / magnitude, value[2] / magnitude]


static func _angle(first: Array, second: Array) -> float:
	return rad_to_deg(acos(clampf(_dot(first, second), -1.0, 1.0)))


static func _click_layout(rng: RefCounted, difficulty: String, snapshot: Dictionary) -> Dictionary:
	var combinations: Array = []
	for repetition: int in 4:
		for size_index: int in 2:
			for amplitude_index: int in 2:
				combinations.append([size_index, amplitude_index])
	_shuffle(combinations, rng)
	var diameters: Array = snapshot.tasks.CLICK.diameters_deg[difficulty]
	var previous: Array = _direction(0.0, 0.0)
	var slots: Array = []
	for slot_index: int in combinations.size():
		var size_index: int = combinations[slot_index][0]
		var amplitude_index: int = combinations[slot_index][1]
		var amplitude_band: Array = [[4.0, 8.0], [18.0, 30.0]][amplitude_index]
		var first_basis: Array = _unit(_cross([0.0, 1.0, 0.0], previous))
		var second_basis: Array = _unit(_cross(previous, first_basis))
		var found: bool = false
		for attempt: int in 4096:
			var cos_rho: float = rng.uniform(cos(deg_to_rad(amplitude_band[1])), cos(deg_to_rad(amplitude_band[0])))
			var sin_rho: float = sqrt(maxf(0.0, 1.0 - cos_rho * cos_rho))
			var bearing_rad: float = rng.uniform(0.0, 2.0 * PI)
			var direction: Array = []
			for axis: int in 3:
				direction.append(cos_rho * previous[axis] + sin_rho * (cos(bearing_rad) * first_basis[axis] + sin(bearing_rad) * second_basis[axis]))
			var yaw_deg: float = rad_to_deg(atan2(direction[0], -direction[2]))
			var pitch_deg: float = rad_to_deg(asin(clampf(direction[1], -1.0, 1.0)))
			if yaw_deg < -25.0 or yaw_deg > 25.0 or pitch_deg < -12.0 or pitch_deg > 12.0:
				continue
			var diameter_deg: float = diameters[size_index]
			slots.append({"slot_index": slot_index, "slot_start_s": slot_index * 1.5, "slot_end_s": (slot_index + 1) * 1.5,
				"diameter_deg": diameter_deg, "radius_m": 4.0 * sin(deg_to_rad(diameter_deg / 2.0)), "distance_m": 4.0,
				"yaw_deg": yaw_deg, "pitch_deg": pitch_deg, "planned_initial_amplitude_deg": _angle(previous, direction),
				"amplitude_band_deg": amplitude_band, "size_index": size_index, "amplitude_index": amplitude_index,
				"planned_previous_direction": previous, "direction": direction, "position_draw_attempts": attempt + 1})
			previous = direction
			found = true
			break
		if not found:
			return _error("UNSATISFIABLE_CLICK_LAYOUT_NO_FALLBACK_ALLOWED")
	return {"ok": true, "slots": slots}


static func _switch_layout(rng: RefCounted, difficulty: String, snapshot: Dictionary) -> Dictionary:
	var positions: Array = []
	for target_index: int in 3:
		var found: bool = false
		for attempt: int in 4096:
			var yaw_deg: float = rng.uniform(-23.0, 23.0)
			var pitch_deg: float = rad_to_deg(asin(rng.uniform(sin(deg_to_rad(-10.0)), sin(deg_to_rad(10.0)))))
			var direction: Array = _direction(yaw_deg, pitch_deg)
			var separated: bool = true
			for position: Dictionary in positions:
				if _angle(direction, position.direction) < 10.0:
					separated = false
			if not separated:
				continue
			var diameter_deg: float = snapshot.tasks.SWITCH.diameter_deg[difficulty]
			positions.append({"target_id": target_index, "yaw_deg": yaw_deg, "pitch_deg": pitch_deg, "direction": direction,
				"distance_m": 4.0, "diameter_deg": diameter_deg, "radius_m": 4.0 * sin(deg_to_rad(diameter_deg / 2.0))})
			found = true
			break
		if not found:
			return _error("UNSATISFIABLE_SWITCH_LAYOUT_NO_FALLBACK_ALLOWED")
	for attempt: int in 4096:
		var priorities: Array = [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]
		_shuffle(priorities, rng)
		var adjacent_repeat: bool = false
		for index: int in 11:
			if priorities[index] == priorities[index + 1]:
				adjacent_repeat = true
		if not adjacent_repeat:
			return {"ok": true, "positions": positions, "priorities": priorities}
	return _error("UNSATISFIABLE_SWITCH_PRIORITY_NO_FALLBACK_ALLOWED")


static func _reactive_motion(difficulty: String) -> Dictionary:
	var catalogue: Dictionary = _read_dictionary(CATALOGUE_PATH)
	for program: Dictionary in catalogue.get("programs", []):
		if program.get("program_id") == "EX06" and program.get("difficulty") == difficulty:
			for phase: Dictionary in program.get("phases", []):
				if phase.get("id") == "reactive":
					return phase.motion.duplicate(true)
	return {}


static func make_deck(plan_seed: String, phase: String, day: String, pair: String, epoch: String, task: String, difficulty: String = "standard") -> Dictionary:
	if not task in TASKS or not difficulty in ["novice", "standard", "advanced"]:
		return _error("UNKNOWN_TASK_OR_DIFFICULTY")
	if not _valid_seed(plan_seed):
		return _error("INVALID_PLAN_SEED_HEX")
	for part: String in [phase, day, pair, epoch]:
		if part.is_empty():
			return _error("INVALID_STIMULUS_SEED_COMPONENT")
		for character_index: int in part.length():
			if part.unicode_at(character_index) > 127:
				return _error("INVALID_STIMULUS_SEED_COMPONENT")
	var snapshot: Dictionary = protocol()
	if snapshot.is_empty():
		return _error("MISSING_PROTOCOL_RESOURCE")
	var layout: Dictionary = _stream(plan_seed, phase, day, pair, epoch, task, "layout")
	var timing: Dictionary = _stream(plan_seed, phase, day, pair, epoch, task, "timing")
	var motion: Dictionary = _stream(plan_seed, phase, day, pair, epoch, task, "motion")
	var deck: Dictionary = {"deck_id": "%s.d%s.pair%s.e%s.%s" % [phase, day, pair, epoch, task], "task_id": "CAL_" + task + "_R2",
		"hash_encoding": HASH_ENCODING, "difficulty": difficulty, "duration_s": 24.0,
		"rng_seeds": {"layout": layout.seed, "timing": timing.seed, "motion": motion.seed}, "candidate_id_in_seed": false, "depends_on_player_actions": false}
	if task == "CLICK":
		var positions: Dictionary = _click_layout(layout.rng, difficulty, snapshot)
		if not positions.ok:
			return positions
		deck["resolution_state"] = "resolved_scheduled_opportunities"
		deck["opportunities"] = positions.slots
		for slot: Dictionary in deck.opportunities:
			_set_slot_timing(slot, timing.rng, 1500000, 1200000)
	elif task == "SWITCH":
		var positions: Dictionary = _switch_layout(layout.rng, difficulty, snapshot)
		if not positions.ok:
			return positions
		deck["resolution_state"] = "resolved_scheduled_opportunities"
		deck["positions"] = positions.positions
		deck["opportunities"] = []
		var hp: float = snapshot.tasks.SWITCH.hp[difficulty]
		for slot_index: int in 12:
			var slot: Dictionary = {"slot_index": slot_index, "slot_start_s": slot_index * 2.0, "slot_end_s": (slot_index + 1) * 2.0,
				"priority_target_id": positions.priorities[slot_index], "hp": hp, "damage_hp_s": 100.0, "ideal_ttk_s": hp / 100.0}
			_set_slot_timing(slot, timing.rng, 2000000, 1700000)
			deck.opportunities.append(slot)
	elif task == "SMOOTH":
		deck["resolution_state"] = "resolved_analytic_trajectory"
		deck["trajectory"] = {"kind": "great_circle_horizontal_sine", "phase_rad": motion.rng.uniform(0.0, 2.0 * PI),
			"amplitude_deg": 14.0, "max_speed_deg_s": snapshot.tasks.SMOOTH.max_speed_deg_s[difficulty],
			"diameter_deg": snapshot.tasks.SMOOTH.diameter_deg[difficulty], "distance_m": 4.0}
	else:
		var motion_spec: Dictionary = _reactive_motion(difficulty)
		if motion_spec.is_empty():
			return _error("SHARED_EX06_RESOURCE_NOT_FOUND")
		var motion_hash: String = Canonical.semantic_sha256(motion_spec)
		if motion_hash != snapshot.tasks.REACTIVE.shared_motion_sha256_by_difficulty[difficulty]:
			return _error("SHARED_EX06_RESOURCE_HASH_MISMATCH")
		deck["resolution_state"] = "resolved_shared_EX06_piecewise_trajectory"
		deck["shared_motion_source"] = {"catalogue_revision": REVISION, "program_id": "EX06", "difficulty": difficulty,
			"phase_id": "reactive", "duration_override_s": 24.0, "motion_kind": "reactive_axis", "motion_resource": motion_spec,
			"motion_resource_sha256": motion_hash, "initial_rng_uint32": motion.seed.uint32, "compiler_version": snapshot.tasks.REACTIVE.shared_compiler_version}
		deck["trajectory_tape"] = _portable_keys(Motion.compile_reactive(motion_spec, motion.seed.uint32, 24.0))
		if deck.trajectory_tape.is_empty() or deck.trajectory_tape.has("error"):
			return _error("REACTIVE_COMPILER_FAILED")
		deck["trajectory_tape_sha256"] = Canonical.semantic_sha256(deck.trajectory_tape)
	deck["manifest_sha256"] = Canonical.semantic_sha256(deck)
	return deck


static func _portable_keys(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key)] = _portable_keys(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_portable_keys(element))
		return result
	return value


static func _set_slot_timing(slot: Dictionary, rng: RefCounted, slot_us: int, window_us: int) -> void:
	var jitter_us: int = rng.randint(100000, 250000)
	var onset_us: int = int(slot.slot_index) * slot_us + jitter_us
	slot.merge({"onset_delay_us": jitter_us, "onset_delay_s": jitter_us / 1000000.0, "onset_us": onset_us,
		"deadline_us": onset_us + window_us, "onset_s": onset_us / 1000000.0, "deadline_s": (onset_us + window_us) / 1000000.0})


static func _result(base: Dictionary, status: String, reasons: Array) -> Dictionary:
	base["status"] = status
	base["reasons"] = reasons.duplicate(true)
	return base


static func _utility_error(utilities: Dictionary) -> String:
	for task: String in TASKS:
		var utility: Variant = utilities.get(task)
		if not _number(utility) or float(utility) < 0.0 or float(utility) > 1.0:
			return "UTILITY_OUT_OF_BOUNDS"
	return ""


static func _missing_utilities(row: Dictionary) -> bool:
	if not row.get("utilities") is Dictionary:
		return true
	for task: String in TASKS:
		if row.utilities.get(task) == null:
			return true
	return false


static func _same_dpi(gains: Array) -> bool:
	for gain: Dictionary in gains:
		if gain.declared_dpi != gains[0].declared_dpi:
			return false
	return true


static func explore(data: Dictionary) -> Dictionary:
	if data.get("protocol_id") != PROTOCOL_ID or not OBJECTIVES.has(data.get("objective")):
		return _error("UNKNOWN_PROTOCOL_OR_OBJECTIVE")
	if data.get("protocol_sha256") != PROTOCOL_SHA256:
		return _error("MISSING_OR_INCOMPATIBLE_PROTOCOL_SNAPSHOT_HASH")
	if not data.get("terminal_condition_failures", []) is Array:
		return _error("MALFORMED_TERMINAL_CONDITION_FAILURES")
	var gains: Variant = data.get("gains", [])
	if not gains is Array:
		return _error("INVALID_GAIN")
	var verified: Dictionary = verify_gains(gains)
	if not verified.ok:
		return verified
	var lookup: Dictionary = {}
	for gain: Dictionary in gains:
		lookup[gain.candidate_id] = gain
	if not gains.size() in [2, 3] or not lookup.has("A"):
		return _error("EXPRESS_REQUIRES_BASELINE_AND_ONE_OR_TWO_ALTERNATIVES")
	if not _same_dpi(gains):
		return _error("DPI_MISMATCH")
	var base: Dictionary = {"protocol_id": PROTOCOL_ID, "objective": data.objective,
		"evidence_method": "exploratory_single_period_per_gain", "confidence_interval": null,
		"equivalence_proven": false, "recommended_action": "keep_original_setting"}
	if not data.get("terminal_condition_failures", []).is_empty():
		return _result(base, "unstable_conditions", data.terminal_condition_failures)
	var rows: Variant = data.get("candidate_results", {})
	if not rows is Dictionary or data.get("accepted_conditions_verified") != true:
		return _result(base, "incomplete", ["express_conditions_or_candidates_incomplete"])
	for identity: String in lookup:
		if not rows.has(identity):
			return _result(base, "incomplete", ["express_conditions_or_candidates_incomplete"])
	if rows.size() != lookup.size():
		return _error("UNPLANNED_EXPRESS_CANDIDATE")
	var weights: Dictionary = OBJECTIVES[data.objective]
	var scores: Dictionary = {}
	for identity: String in rows:
		if not rows[identity] is Dictionary:
			return _error("MALFORMED_EXPRESS_ROW")
		var row: Dictionary = rows[identity]
		if _missing_utilities(row):
			return _result(base, "incomplete", ["missing_express_task"])
		var utility_error: String = _utility_error(row.utilities)
		if not utility_error.is_empty():
			return _error(utility_error)
		for count_spec: Array in [["click_successes", 16, "CLICK"], ["switch_completions", 12, "SWITCH"]]:
			var count: Variant = row.get(count_spec[0])
			if not _integer(count, 0, count_spec[1]) or float(row.utilities[count_spec[2]]) > float(count) / float(count_spec[1]) + NUMERIC_TOLERANCE:
				return _error("INVALID_SUCCESS_COUNT_OR_UTILITY")
		var weighted: float = 0.0
		for task: String in TASKS:
			weighted += float(weights[task]) * float(row.utilities[task])
		scores[identity] = 100.0 * weighted
	var best_nonbaseline: float = -INF
	var best: float = -INF
	for identity: String in scores:
		best = maxf(best, scores[identity])
		if identity != "A":
			best_nonbaseline = maxf(best_nonbaseline, scores[identity])
	var baseline_cm: float = lookup.A.effective_cm_per_360
	var challenger: String = ""
	var challenger_distance: float = INF
	var envelope: Array = []
	var observed_best: Array = []
	for identity: String in scores:
		if identity != "A" and best_nonbaseline - scores[identity] <= 0.25 + NUMERIC_TOLERANCE:
			var distance: float = absf(log(float(lookup[identity].effective_cm_per_360) / baseline_cm))
			if distance < challenger_distance or (distance == challenger_distance and (challenger.is_empty() or Canonical.utf8_less(identity, challenger))):
				challenger = identity
				challenger_distance = distance
		var task_guard: bool = true
		for task: String in TASKS:
			if 100.0 * (float(rows[identity].utilities[task]) - float(rows.A.utilities[task])) < -5.0 - NUMERIC_TOLERANCE:
				task_guard = false
		if best - scores[identity] <= 3.0 + NUMERIC_TOLERANCE and task_guard:
			envelope.append(identity)
		if absf(scores[identity] - best) <= NUMERIC_TOLERANCE:
			observed_best.append(identity)
	envelope.sort_custom(func(first: String, second: String) -> bool: return lookup[first].effective_cm_per_360 < lookup[second].effective_cm_per_360)
	var cm_order: Array = lookup.keys()
	cm_order.sort_custom(func(first: String, second: String) -> bool: return lookup[first].effective_cm_per_360 < lookup[second].effective_cm_per_360)
	var uninformative: Array = []
	for task: String in TASKS:
		var total_utility: float = 0.0
		for identity: String in rows:
			total_utility += float(rows[identity].utilities[task])
		var mean_utility: float = total_utility / rows.size()
		if mean_utility < 0.10 or mean_utility > 0.95:
			uninformative.append(task)
	var flags: Array = []
	if not uninformative.is_empty():
		flags.append("difficulty_may_be_uninformative_freeze_new_plan_before_confirmation")
	var open_sides: Array = []
	if cm_order[0] in observed_best:
		open_sides.append("faster_gain_side_not_explored")
	if cm_order[-1] in observed_best:
		open_sides.append("slower_gain_side_not_explored")
	base.merge({"scores_pp": scores, "challenger_candidate_id": challenger, "baseline_is_observed_best": "A" in observed_best,
		"descriptive_envelope_tested_candidate_ids": envelope, "envelope_is_continuous_interval": false,
		"uninformative_tasks": uninformative, "diagnostic_flags": flags, "unexplored_sides": open_sides})
	return _result(base, "exploratory_only", ["fresh_independent_confirmation_required_for_challenger"])


static func compare(data: Dictionary) -> Dictionary:
	if data.get("phase") == "express":
		return explore(data)
	if data.get("protocol_id") != PROTOCOL_ID:
		return _error("UNKNOWN_PROTOCOL")
	if data.get("protocol_sha256") != PROTOCOL_SHA256:
		return _error("MISSING_OR_INCOMPATIBLE_PROTOCOL_SNAPSHOT_HASH")
	if not OBJECTIVES.has(data.get("objective")):
		return _error("UNKNOWN_OBJECTIVE")
	if not data.get("terminal_condition_failures", []) is Array:
		return _error("MALFORMED_TERMINAL_CONDITION_FAILURES")
	var gains: Variant = data.get("gains", [])
	if not gains is Array:
		return _error("INVALID_GAIN")
	var qa_only: bool = data.get("qa_only", false) == true
	var verified: Dictionary = verify_gains(gains, qa_only and data.get("data_origin") == "synthetic_illustration_not_measured_player_data")
	if not verified.ok:
		return verified
	var lookup: Dictionary = {}
	for gain: Dictionary in gains:
		lookup[gain.candidate_id] = gain
	if lookup.size() != 2 or not lookup.has("A") or not lookup.has("B"):
		return _error("EXPECTED_A_B_GAIN_IDENTITIES")
	if not _same_dpi(gains):
		return _error("DPI_MISMATCH")
	var baseline_cm: float = lookup.A.effective_cm_per_360
	var challenger_cm: float = lookup.B.effective_cm_per_360
	if maxf(baseline_cm, challenger_cm) / minf(baseline_cm, challenger_cm) > 1.50 + 1.0e-12:
		return _error("CONFIRMATION_GAIN_CHANGE_EXCEEDS_PROTOCOL_LIMIT")
	var base: Dictionary = {"protocol_id": PROTOCOL_ID, "objective": data.objective, "evidence_method": "descriptive_two_day_rules",
		"confidence_interval": null, "equivalence_proven": false, "qa_only": qa_only, "recommended_action": "keep_original_setting"}
	if not data.get("terminal_condition_failures", []).is_empty():
		return _result(base, "unstable_conditions", data.terminal_condition_failures)
	if data.get("phase") != "confirmation":
		return _error("UNKNOWN_PHASE")
	var days: Variant = data.get("days", [])
	if not days is Array:
		return _error("MALFORMED_DAYS")
	if days.size() < 2:
		return _result(base, "incomplete", ["two_complete_days_required"])
	for day: Variant in days:
		if not day is Dictionary or not day.get("periods", []) is Array:
			return _error("MALFORMED_DAYS")
		if day.get("periods", []).size() < 4:
			return _result(base, "incomplete", ["two_complete_days_required"])
	if days.size() != 2 or days[0].periods.size() != 4 or days[1].periods.size() != 4:
		return _error("EXTRA_ACCEPTED_OBSERVATIONS_NOT_PREDECLARED")
	days = days.duplicate(true)
	days.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.get("day_role", 0)) < float(second.get("day_role", 0)))
	if days[0].get("day_role") != 1 or days[1].get("day_role") != 2:
		return _error("WRONG_DAY_ROLES")
	if not [days[0].get("order"), days[1].get("order")] in [["ABBA", "BAAB"], ["BAAB", "ABBA"]]:
		return _error("ORDERS_NOT_COUNTERBALANCED")
	if data.get("accepted_conditions_verified") != true:
		return _result(base, "incomplete", ["condition_eligibility_not_verified"])
	var weights: Dictionary = OBJECTIVES[data.objective]
	var pair_rows: Array = []
	var day_rows: Array = []
	var totals: Dictionary = {"A": {"CLICK": 0, "SWITCH": 0}, "B": {"CLICK": 0, "SWITCH": 0}}
	var utility_totals: Dictionary = {"CLICK": 0.0, "SMOOTH": 0.0, "REACTIVE": 0.0, "SWITCH": 0.0}
	for day: Dictionary in days:
		var periods: Array = day.periods
		for period_index: int in 4:
			if not periods[period_index] is Dictionary:
				return _error("MALFORMED_PERIOD")
			var period: Dictionary = periods[period_index]
			if period.get("alias") != day.order[period_index]:
				return _error("PERIOD_GAIN_ORDER_MISMATCH")
			if _missing_utilities(period):
				return _result(base, "incomplete", ["missing_required_task"])
			if period.get("click_opportunities") == null or period.get("switch_opportunities") == null:
				return _result(base, "incomplete", ["missing_opportunity_denominator"])
			if not _integer(period.click_opportunities, 16, 16) or not _integer(period.switch_opportunities, 12, 12):
				return _error("WRONG_OPPORTUNITY_DENOMINATOR")
			var utility_error: String = _utility_error(period.utilities)
			if not utility_error.is_empty():
				return _error(utility_error)
			for task: String in TASKS:
				utility_totals[task] += float(period.utilities[task])
			for count_spec: Array in [["click_successes", 16, "CLICK"], ["switch_completions", 12, "SWITCH"]]:
				var count: Variant = period.get(count_spec[0])
				if count == null:
					return _result(base, "incomplete", ["missing_success_count"])
				if not _integer(count, 0, count_spec[1]):
					return _error("INVALID_SUCCESS_COUNT")
				if float(period.utilities[count_spec[2]]) > float(count) / float(count_spec[1]) + NUMERIC_TOLERANCE:
					return _error("UTILITY_EXCEEDS_SUCCESS_FRACTION")
				totals[period.alias][count_spec[2]] += int(count)
		var day_pairs: Array = []
		for pair_index: int in 2:
			var first_period: Dictionary = periods[pair_index * 2]
			var second_period: Dictionary = periods[pair_index * 2 + 1]
			var baseline: Dictionary = first_period if first_period.alias == "A" else second_period
			var challenger: Dictionary = first_period if first_period.alias == "B" else second_period
			var effects: Dictionary = {}
			var composite: float = 0.0
			for task: String in TASKS:
				effects[task] = 100.0 * (float(challenger.utilities[task]) - float(baseline.utilities[task]))
				composite += float(weights[task]) * float(effects[task])
			var row: Dictionary = {"day_role": day.day_role, "pair_index": pair_index, "effects_pp": effects, "composite_pp": composite}
			day_pairs.append(row)
			pair_rows.append(row)
		var day_effects: Dictionary = {}
		for task: String in TASKS:
			day_effects[task] = (float(day_pairs[0].effects_pp[task]) + float(day_pairs[1].effects_pp[task])) / 2.0
		day_rows.append({"day_role": day.day_role, "effects_pp": day_effects,
			"composite_pp": (float(day_pairs[0].composite_pp) + float(day_pairs[1].composite_pp)) / 2.0,
			"pair_span_pp": absf(float(day_pairs[0].composite_pp) - float(day_pairs[1].composite_pp))})
	var day_values: Array = [day_rows[0].composite_pp, day_rows[1].composite_pp]
	var pair_values: Array = []
	for row: Dictionary in pair_rows:
		pair_values.append(row.composite_pp)
	var raw_differences: Dictionary = {"CLICK": totals.B.CLICK - totals.A.CLICK, "SWITCH": totals.B.SWITCH - totals.A.SWITCH}
	var guards: Dictionary = {"CLICK": raw_differences.CLICK >= -3, "SWITCH": raw_differences.SWITCH >= -4}
	var symmetric_raw: bool = absi(raw_differences.CLICK) <= 3 and absi(raw_differences.SWITCH) <= 4
	var task_guard: bool = true
	var global_good: bool = true
	var global_bad: bool = true
	var close_observed: bool = symmetric_raw
	var strong_positive: Array = []
	var strong_negative: Array = []
	var uninformative: Array = []
	var flags: Array = []
	for task: String in TASKS:
		var both_positive: bool = true
		var both_negative: bool = true
		for row: Dictionary in day_rows:
			var effect: float = row.effects_pp[task]
			task_guard = task_guard and effect >= -5.0 - NUMERIC_TOLERANCE
			close_observed = close_observed and absf(effect) <= 5.0 + NUMERIC_TOLERANCE
			both_positive = both_positive and effect >= 5.0 - NUMERIC_TOLERANCE
			both_negative = both_negative and effect <= -5.0 + NUMERIC_TOLERANCE
		if both_positive:
			strong_positive.append(task)
		if both_negative:
			strong_negative.append(task)
		var mean_utility: float = utility_totals[task] / 8.0
		if mean_utility < 0.10 - NUMERIC_TOLERANCE or mean_utility > 0.95 + NUMERIC_TOLERANCE:
			uninformative.append(task)
	for value: float in day_values:
		global_good = global_good and value >= 2.0 - NUMERIC_TOLERANCE
		global_bad = global_bad and value <= -2.0 + NUMERIC_TOLERANCE
		close_observed = close_observed and absf(value) <= 2.0 + NUMERIC_TOLERANCE
	for value: float in pair_values:
		global_good = global_good and value > NUMERIC_TOLERANCE
		global_bad = global_bad and value < -NUMERIC_TOLERANCE
		close_observed = close_observed and absf(value) <= 3.0 + NUMERIC_TOLERANCE
	if day_rows[0].pair_span_pp > 6.0 + NUMERIC_TOLERANCE or day_rows[1].pair_span_pp > 6.0 + NUMERIC_TOLERANCE:
		flags.append("order_sensitive_pair_span")
	if float(day_values[0]) * float(day_values[1]) < 0.0:
		flags.append("opposite_day_effect_signs")
	base.merge({"pair_effects": pair_rows, "day_effects": day_rows, "observed_mean_effect_pp": (float(day_values[0]) + float(day_values[1])) / 2.0,
		"observed_day_range_pp": [day_values.min(), day_values.max()], "observed_pair_range_pp": [pair_values.min(), pair_values.max()],
		"effective_day_count": 2, "paired_contrast_count": 4, "success_counts": totals, "success_count_difference_B_minus_A": raw_differences,
		"success_rate_difference_B_minus_A": {"CLICK": raw_differences.CLICK / 64.0, "SWITCH": raw_differences.SWITCH / 48.0},
		"per_task_guard_pass": task_guard, "raw_success_guards": guards, "diagnostic_flags": flags, "uninformative_tasks": uninformative})
	if not uninformative.is_empty():
		return _result(base, "undetermined", ["task_floor_or_ceiling_requires_new_frozen_difficulty"])
	if global_bad:
		return _result(base, "repeated_regression", ["global_loss_repeated_on_both_days"])
	if global_good and task_guard and guards.CLICK and guards.SWITCH:
		base.recommended_action = "offer_saved_challenger_for_explicit_application"
		return _result(base, "repeated_improvement", ["global_gain_repeated_with_guards"])
	if (global_good and (not task_guard or not guards.CLICK or not guards.SWITCH)) or (not strong_positive.is_empty() and not strong_negative.is_empty()):
		return _result(base, "mixed_tradeoff", ["gain_with_skill_or_success_tradeoff"])
	if close_observed:
		return _result(base, "close_observed", ["small_observed_differences_not_proven_equivalence"])
	return _result(base, "undetermined", ["predeclared_repeatability_rules_not_met"])


static func _valid_seed(seed: Variant) -> bool:
	if not seed is String or seed.length() != 32:
		return false
	for character_index: int in seed.length():
		if not seed.substr(character_index, 1) in "0123456789abcdef":
			return false
	return true


static func _condition_error(snapshot: Dictionary, gains: Array, actual: bool) -> String:
	for field: String in CONDITION_FIELDS:
		if not snapshot.has(field):
			return "MISSING_CONDITION_FIELD:" + field
	if snapshot.get("task_revision") != "CAL_R2_2026-10-12" or snapshot.get("catalogue_revision") != REVISION:
		return "CONDITION_RESOURCE_REVISION_MISMATCH"
	if not OBJECTIVES.has(snapshot.get("objective")):
		return "UNKNOWN_OBJECTIVE"
	if not snapshot.get("weights") is Dictionary or Canonical.semantic_sha256(snapshot.weights) != Canonical.semantic_sha256(OBJECTIVES[snapshot.objective]):
		return "CONDITION_OBJECTIVE_WEIGHTS_MISMATCH"
	var difficulty: Variant = snapshot.get("difficulty_by_task")
	if not difficulty is Dictionary or difficulty.size() != 4:
		return "CONDITION_DIFFICULTY_MISMATCH"
	for task: String in TASKS:
		if not difficulty.get(task) in ["novice", "standard", "advanced"]:
			return "CONDITION_DIFFICULTY_MISMATCH"
	if not _integer(snapshot.declared_dpi, 1, MAX_SAFE_INTEGER):
		return "INVALID_CONDITION_DPI"
	for gain: Dictionary in gains:
		if gain.declared_dpi != snapshot.declared_dpi:
			return "DPI_MISMATCH"
		if gain.candidate_id == "A" and snapshot.has("gain_hex") and snapshot.gain_hex != gain.degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex:
			return "CONDITION_BASELINE_GAIN_MISMATCH"
	if not _number(snapshot.fov_horizontal_deg_at_16_9) or float(snapshot.fov_horizontal_deg_at_16_9) <= 0.0 or float(snapshot.fov_horizontal_deg_at_16_9) >= 180.0:
		return "INVALID_CONDITION_FOV"
	var resolution: Variant = snapshot.render_resolution_px
	if not resolution is Array or resolution.size() != 2 or not _integer(resolution[0], 1, 65536) or not _integer(resolution[1], 1, 65536):
		return "INVALID_RENDER_RESOLUTION"
	if not _number(snapshot.render_scale) or snapshot.render_scale <= 0.0 or not _number(snapshot.frame_limit_hz) or snapshot.frame_limit_hz < 0.0:
		return "INVALID_RENDER_CONDITION"
	if not _number(snapshot.display_hz_declared) or snapshot.display_hz_declared <= 0.0:
		return "INVALID_DECLARED_DISPLAY_HZ"
	if not snapshot.vsync is bool or not snapshot.candidate_value_masking is bool or snapshot.seeded_scored_stimulus_preview != false:
		return "INVALID_PRESENTATION_CONDITION"
	if not snapshot.crosshair is Dictionary or snapshot.crosshair.is_empty():
		return "INVALID_CROSSHAIR_CONDITION"
	for field: String in ["renderer", "input_convention", "target_palette", "audio"]:
		var value: Variant = snapshot[field]
		if not value is String and not value is Dictionary:
			return "INVALID_CONDITION_FIELD:" + field
		if value.is_empty():
			return "INVALID_CONDITION_FIELD:" + field
	if actual:
		for field: String in ACTUAL_CONDITION_FIELDS:
			var value: Variant = snapshot.get(field)
			if not value is String or value.is_empty() or value.to_lower().contains("example") or value.to_lower().contains("illustrat"):
				return "MISSING_ACTUAL_CONDITION_FIELD:" + field
		if not snapshot.dpi_source in ["declared", "physical_measurement"] or str(snapshot.renderer).to_lower().contains("example"):
			return "EXAMPLE_OR_UNKNOWN_CONDITIONS_NOT_RUNTIME"
	if snapshot.has("quality_limits") and Canonical.semantic_sha256(snapshot.quality_limits) != Canonical.semantic_sha256(protocol().get("quality")):
		return "CONDITION_QUALITY_LIMITS_MISMATCH"
	return "" if not Canonical.semantic_sha256(snapshot).is_empty() else "MALFORMED_CONDITION_SNAPSHOT"


static func _prepare_conditions(conditions: Dictionary, gains: Array, objective: String, difficulty_by_task: Dictionary) -> Dictionary:
	if not OBJECTIVES.has(objective):
		return _error("UNKNOWN_OBJECTIVE")
	var snapshot: Dictionary = conditions.duplicate(true)
	var difficulty: Dictionary = difficulty_by_task.duplicate(true)
	if difficulty.is_empty():
		var supplied_difficulty: Variant = snapshot.get("difficulty_by_task", {"CLICK": "standard", "SMOOTH": "standard", "REACTIVE": "standard", "SWITCH": "standard"})
		if not supplied_difficulty is Dictionary:
			return _error("CONDITION_DIFFICULTY_MISMATCH")
		difficulty = supplied_difficulty.duplicate(true)
	var fixed: Dictionary = {"task_revision": "CAL_R2_2026-10-12", "catalogue_revision": REVISION,
		"objective": objective, "weights": OBJECTIVES[objective].duplicate(true), "difficulty_by_task": difficulty,
		"quality_limits": protocol().get("quality", {}).duplicate(true)}
	for key: String in fixed:
		if snapshot.has(key) and Canonical.semantic_sha256(snapshot[key]) != Canonical.semantic_sha256(fixed[key]):
			return _error("CONFLICTING_FROZEN_CONDITION:" + key)
		snapshot[key] = fixed[key]
	var error: String = _condition_error(snapshot, gains, true)
	if not error.is_empty():
		return _error(error)
	return {"ok": true, "error": "", "snapshot": snapshot}


static func create_express_plan(baseline: Dictionary, gains: Array, conditions: Dictionary, objective: String, plan_seed: String) -> Dictionary:
	var verified: Dictionary = verify_gains(gains)
	if not verified.ok:
		return verified
	if baseline.get("candidate_id") != "A" or not gains.size() in [2, 3]:
		return _error("EXPRESS_REQUIRES_BASELINE_AND_ONE_OR_TWO_ALTERNATIVES")
	var has_baseline: bool = false
	for gain: Dictionary in gains:
		if gain.candidate_id == "A":
			has_baseline = Canonical.semantic_sha256(gain) == Canonical.semantic_sha256(baseline)
	if not has_baseline:
		return _error("BASELINE_EXACT_GAIN_NOT_PRESERVED")
	return _create_plan("express", gains, conditions, objective, plan_seed, {}, {})


static func create_confirmation_plan(baseline: Dictionary, challenger: Dictionary, conditions: Dictionary, objective: String, plan_seed: String, difficulty_by_task: Dictionary = {}) -> Dictionary:
	if baseline.get("candidate_id") != "A" or challenger.get("candidate_id") == "A":
		return _error("INVALID_CONFIRMATION_ALIAS_MAPPING")
	var selection: Dictionary = {"baseline_candidate_id": "A", "challenger_candidate_id": challenger.get("candidate_id"),
		"alias_B": challenger.get("candidate_id"), "selection_scores_excluded_from_confirmation": true}
	return _create_plan("confirmation", [baseline, challenger], conditions, objective, plan_seed, difficulty_by_task, selection)


static func _create_plan(phase: String, gains: Array, conditions: Dictionary, objective: String, seed: String, difficulty: Dictionary, selection: Dictionary) -> Dictionary:
	if not _valid_seed(seed):
		return _error("INVALID_PLAN_SEED_HEX")
	if protocol_hash() != PROTOCOL_SHA256:
		return _error("PROTOCOL_HASH_MISMATCH")
	var verified: Dictionary = verify_gains(gains)
	if not verified.ok:
		return verified
	if not _same_dpi(gains):
		return _error("DPI_MISMATCH")
	var baseline: Dictionary = {}
	for gain: Dictionary in gains:
		if gain.candidate_id == "A":
			baseline = gain
	if baseline.is_empty():
		return _error("BASELINE_ID_MUST_BE_A")
	for gain: Dictionary in gains:
		if maxf(gain.effective_cm_per_360 / baseline.effective_cm_per_360, baseline.effective_cm_per_360 / gain.effective_cm_per_360) > 1.50 + 1.0e-12:
			return _error("CONFIRMATION_GAIN_CHANGE_EXCEEDS_PROTOCOL_LIMIT")
	var prepared: Dictionary = _prepare_conditions(conditions, gains, objective, difficulty)
	if not prepared.ok:
		return prepared
	var candidates: Array = gains.duplicate(true)
	for gain: Dictionary in candidates:
		gain["cm_ratio_to_baseline"] = gain.effective_cm_per_360 / baseline.effective_cm_per_360
		gain["gain_ratio_to_baseline"] = gain_value(gain) / gain_value(baseline)
	var identity_material: Dictionary = {"phase": phase, "plan_seed_hex": seed, "condition_snapshot": prepared.snapshot, "candidates": candidates}
	var plan: Dictionary = {"schema_version": "aimlocal.calibration.plan.v2", "protocol_id": PROTOCOL_ID, "hash_encoding": HASH_ENCODING,
		"plan_id": "cal_v2." + phase + "." + Canonical.semantic_sha256(identity_material).substr(0, 32), "is_example": false,
		"phase": phase, "protocol_sha256": PROTOCOL_SHA256, "protocol_snapshot": protocol(), "plan_seed_hex": seed,
		"condition_snapshot": prepared.snapshot, "condition_snapshot_sha256": Canonical.semantic_sha256(prepared.snapshot),
		"candidates": candidates, "schedule_resolution": "complete_relative_timeline_and_resolved_stimuli", "sessions": [], "decks": {}}
	plan[phase + "_plan_seed_hex"] = seed
	var order_stream: Dictionary = _stream(seed, "orders", "0", "0", "0", "ALL", "orders")
	if phase == "express":
		var order: Array = []
		for gain: Dictionary in candidates:
			order.append(gain.candidate_id)
		_shuffle(order, order_stream.rng)
		var session: Dictionary = _make_session(plan, phase, 0, 0, order, seed)
		if session.has("error"):
			return session
		plan.sessions.append(session)
		plan["programmed_total_s"] = session.planned_duration_s
	else:
		plan["confirmation_selection"] = selection.duplicate(true)
		var first_order: String = "ABBA" if order_stream.rng.randint(0, 1) == 0 else "BAAB"
		for day_role: int in [1, 2]:
			var order_text: String = first_order if day_role == 1 else ("BAAB" if first_order == "ABBA" else "ABBA")
			var order: Array = order_text.split("")
			var session: Dictionary = _make_session(plan, phase, day_role, 0, order, seed)
			if session.has("error"):
				return session
			plan.sessions.append(session)
		plan["programmed_total_s"] = 2016
	plan["plan_sha256"] = Canonical.semantic_sha256(plan)
	var validation: Dictionary = validate_plan(plan)
	if not validation.ok:
		return validation
	_freeze(plan)
	return {"ok": true, "error": "", "plan": plan, "validation": validation}


static func _make_session(plan: Dictionary, phase: String, day_role: int, epoch: int, order: Array, seed: String) -> Dictionary:
	var task_order: Array = DAY2_TASK_ORDER.duplicate() if day_role == 2 else DAY1_TASK_ORDER.duplicate()
	var rest_s: int = 30 if phase == "express" else 60
	var session_id: String = "%s.day%d.epoch%d" % [phase, day_role, epoch]
	var session: Dictionary = {"session_id": session_id, "phase": phase, "day_role": day_role, "attempt_epoch": epoch,
		"planned_duration_s": 60 + order.size() * 192 + (order.size() - 1) * rest_s, "planned_local_date": null,
		"actual_start_utc": null, "task_order": task_order, "order": order.duplicate(),
		"preflight": {"start_s": 0, "end_s": 60, "gain_candidate_id": "A", "tasks": []}, "periods": [], "interperiod_rests": []}
	var gains: Dictionary = {}
	for gain: Dictionary in plan.candidates:
		gains[gain.candidate_id] = gain
	var selection: Dictionary = plan.get("confirmation_selection", {})
	for task_index: int in 4:
		var segment: Dictionary = _familiarization_segment(plan, seed, phase + "_preflight", day_role, 0, epoch, task_order[task_index], task_index * 15)
		if segment.has("error"):
			return segment
		segment["ignore_partial_final_opportunity_for_familiarization_metric"] = true
		session.preflight.tasks.append(segment)
	for period_index: int in order.size():
		var alias: String = order[period_index]
		var identity: String = selection.challenger_candidate_id if phase == "confirmation" and alias == "B" else alias
		var start_s: int = 60 + period_index * (192 + rest_s)
		var pair_index: int = 0 if phase == "express" else period_index / 2
		var period: Dictionary = {"period_index": period_index, "comparison_alias": alias, "candidate_id": identity,
			"start_s": start_s, "end_s": start_s + 192, "pair_index": pair_index,
			"applied_gain": gains[identity].degrees_per_relative_input_unit.duplicate(true),
			"acclimation": {"start_s": start_s, "end_s": start_s + 60, "score_included": false, "task_segments": []}, "scored_cells": []}
		for task_index: int in 4:
			var task: String = task_order[task_index]
			var warmup: Dictionary = _familiarization_segment(plan, seed, phase + "_warmup", day_role, pair_index, epoch, task, start_s + task_index * 15)
			if warmup.has("error"):
				return warmup
			warmup["final_partial_opportunity_censored"] = true
			period.acclimation.task_segments.append(warmup)
			var deck: Dictionary = _store_deck(plan, seed, phase, day_role, pair_index, epoch, task)
			if deck.has("error"):
				return deck
			var onset_s: int = start_s + 63 + 33 * task_index
			period.scored_cells.append({"cell_id": "%s.p%d.%s" % [session_id, period_index, task], "task": task,
				"task_id": "CAL_" + task + "_R2", "candidate_id": identity, "deck_id": deck.deck_id, "deck_manifest_sha256": deck.manifest_sha256,
				"countdown_start_s": onset_s - 3, "scored_start_s": onset_s, "scored_end_s": onset_s + 24,
				"recovery_end_s": onset_s + 30, "duration_s": 24, "logical_stimulus_time_origin": "scored_start",
				"condition_snapshot_sha256": plan.condition_snapshot_sha256})
		session.periods.append(period)
		if period_index < order.size() - 1:
			session.interperiod_rests.append({"start_s": start_s + 192, "end_s": start_s + 192 + rest_s, "gain_candidate_id": identity, "restore_baseline": false})
	return session


static func _store_deck(plan: Dictionary, seed: String, phase: String, day: int, pair: int, epoch: int, task: String) -> Dictionary:
	var identity: String = "%s.d%d.pair%d.e%d.%s" % [phase, day, pair, epoch, task]
	if plan.decks.has(identity):
		return plan.decks[identity]
	var deck: Dictionary = make_deck(seed, phase, str(day), str(pair), str(epoch), task, plan.condition_snapshot.difficulty_by_task[task])
	if not deck.has("error"):
		plan.decks[identity] = deck
	return deck


static func _familiarization_segment(plan: Dictionary, seed: String, phase: String, day: int, pair: int, epoch: int, task: String, start_s: int) -> Dictionary:
	var deck: Dictionary = _store_deck(plan, seed, phase, day, pair, epoch, task)
	if deck.has("error"):
		return deck
	return {"task": task, "start_s": start_s, "end_s": start_s + 15, "deck_id": deck.deck_id,
		"deck_manifest_sha256": deck.manifest_sha256, "expose_deck_interval_s": [0.0, 15.0], "comparative_utility_included": false}


static func _without(value: Dictionary, field: String) -> Dictionary:
	var result: Dictionary = value.duplicate()
	result.erase(field)
	return result


static func _time_is(value: Dictionary, field: String, expected: float) -> bool:
	return _number(value.get(field)) and float(value[field]) == expected


static func _false(value: Variant) -> bool:
	return value is bool and not value


static func _true(value: Variant) -> bool:
	return value is bool and value


static func _seed_for_session(plan: Dictionary, phase: String) -> String:
	return str(plan.get(phase + "_plan_seed_hex", plan.get("plan_seed_hex", "")))


static func _aliases(plan: Dictionary) -> Dictionary:
	var selection: Variant = plan.get("confirmation_selection", plan.get("confirmation_selection_in_example", {}))
	if not selection is Dictionary:
		return {}
	return {"A": selection.get("baseline_candidate_id"), "B": selection.get("challenger_candidate_id")}


static func validate_plan(plan: Dictionary) -> Dictionary:
	if not plan.get("candidates") is Array or not plan.get("sessions") is Array or not plan.get("decks") is Dictionary or not plan.get("condition_snapshot") is Dictionary:
		return _error("MALFORMED_PLAN")
	var verified: Dictionary = verify_gains(plan.candidates)
	if not verified.ok:
		return verified
	if plan.get("protocol_id") != PROTOCOL_ID or plan.get("protocol_sha256") != PROTOCOL_SHA256 or protocol_hash() != PROTOCOL_SHA256:
		return _error("PROTOCOL_HASH_MISMATCH")
	if plan.get("hash_encoding") != HASH_ENCODING:
		return _error("HASH_ENCODING_MISMATCH")
	var encoding: Dictionary = Canonical.encode(plan)
	if not encoding.ok:
		return _error(encoding.error)
	if Canonical.semantic_sha256(_without(plan, "plan_sha256")) != plan.get("plan_sha256"):
		return _error("PLAN_HASH_MISMATCH")
	if Canonical.semantic_sha256(plan.condition_snapshot) != plan.get("condition_snapshot_sha256"):
		return _error("CONDITION_HASH_MISMATCH")
	var example: bool = plan.get("schema_version") == "aimlocal.calibration.example_plan.v2"
	if not example and plan.get("schema_version") != "aimlocal.calibration.plan.v2":
		return _error("UNKNOWN_PLAN_SCHEMA")
	if example and (not _true(plan.get("is_example")) or not _false(plan.get("engine_executable"))):
		return _error("EXAMPLE_PLAN_NOT_RUNTIME")
	if not example and (not _false(plan.get("is_example")) or plan.has("engine_executable") or plan.has("confirmation_selection_in_example")):
		return _error("EXAMPLE_PLAN_NOT_RUNTIME")
	var condition_error: String = _condition_error(plan.condition_snapshot, plan.candidates, not example)
	if not condition_error.is_empty():
		return _error(condition_error)
	if not example and (Canonical.semantic_sha256(plan.get("protocol_snapshot")) != PROTOCOL_SHA256 or not plan.condition_snapshot.has("quality_limits")):
		return _error("PROTOCOL_SNAPSHOT_MISMATCH")
	var gains: Dictionary = {}
	for gain: Dictionary in plan.candidates:
		gains[gain.candidate_id] = gain
	if not gains.has("A") or not gains.size() in [2, 3] or not _same_dpi(plan.candidates):
		return _error("INVALID_PLAN_CANDIDATES")
	for gain: Dictionary in plan.candidates:
		var ratio: float = float(gain.effective_cm_per_360) / float(gains.A.effective_cm_per_360)
		if maxf(ratio, 1.0 / ratio) > 1.50 + 1.0e-12:
			return _error("CONFIRMATION_GAIN_CHANGE_EXCEEDS_PROTOCOL_LIMIT")
		if gain.has("cm_ratio_to_baseline") and (not _number(gain.cm_ratio_to_baseline) or absf(float(gain.cm_ratio_to_baseline) - ratio) > NUMERIC_TOLERANCE):
			return _error("GAIN_BASELINE_RATIO_MISMATCH")
	var aliases: Dictionary = _aliases(plan)
	var has_confirmation: bool = false
	for session: Variant in plan.sessions:
		if not session is Dictionary:
			return _error("MALFORMED_SESSION")
		has_confirmation = has_confirmation or session.get("phase") == "confirmation"
	if has_confirmation and (aliases.get("A") != "A" or aliases.get("B") == "A" or not gains.has(aliases.get("B"))):
		return _error("INVALID_CONFIRMATION_ALIAS_MAPPING")
	var context: Dictionary = {"gains": gains, "aliases": aliases, "cell_ids": {}, "session_ids": {}, "deck_ids": {}, "confirmation_orders": {}, "duration_s": 0, "scored_cells": 0, "express_count": 0}
	for session: Dictionary in plan.sessions:
		var session_error: String = _session_error(plan, session, context)
		if not session_error.is_empty():
			return _error(session_error)
	if context.confirmation_orders.size() == 2 and context.confirmation_orders[1] == context.confirmation_orders[2]:
		return _error("CONFIRMATION_DAY_ORDERS_NOT_REVERSED")
	if not _time_is(plan, "programmed_total_s", context.duration_s):
		return _error("TOTAL_BUDGET_MISMATCH")
	if not example:
		var phase: Variant = plan.get("phase")
		if phase == "express":
			if context.express_count != 1 or not context.confirmation_orders.is_empty() or plan.sessions.size() != 1:
				return _error("WRONG_PLAN_SESSION_COUNT")
		elif phase == "confirmation":
			if context.express_count != 0 or context.confirmation_orders.size() != 2 or gains.size() != 2 or plan.sessions.size() != 2:
				return _error("WRONG_PLAN_SESSION_COUNT")
		else:
			return _error("UNKNOWN_PLAN_PHASE")
		if not _valid_seed(plan.get("plan_seed_hex")):
			return _error("INVALID_PLAN_SEED_HEX")
		var identity_material: Dictionary = {"phase": phase, "plan_seed_hex": plan.plan_seed_hex, "condition_snapshot": plan.condition_snapshot, "candidates": plan.candidates}
		if plan.get("plan_id") != "cal_v2." + phase + "." + Canonical.semantic_sha256(identity_material).substr(0, 32):
			return _error("PLAN_ID_MISMATCH")
		if plan.decks.size() != context.deck_ids.size():
			return _error("UNLINKED_MANIFEST_IN_PLAN")
	for deck_id: Variant in plan.decks:
		if not deck_id is String or not plan.decks[deck_id] is Dictionary:
			return _error("MALFORMED_DECK")
		var deck_error: String = _deck_error(deck_id, plan.decks[deck_id])
		if not deck_error.is_empty():
			return _error(deck_error)
	return {"ok": true, "error": "", "errors": [], "scored_cells": context.scored_cells, "deck_count": plan.decks.size(),
		"programmed_seconds": context.duration_s, "is_example": example, "plan_ready": not example}


static func _session_error(plan: Dictionary, session: Dictionary, context: Dictionary) -> String:
	for field: String in ["periods", "order", "task_order", "interperiod_rests"]:
		if not session.get(field) is Array:
			return "MALFORMED_SESSION"
	if not session.get("preflight") is Dictionary or not session.preflight.get("tasks") is Array:
		return "MALFORMED_PREFLIGHT"
	var phase: Variant = session.get("phase")
	var day_role: Variant = session.get("day_role")
	var epoch: Variant = session.get("attempt_epoch")
	if not _integer(epoch, 0, 1):
		return "INVALID_ATTEMPT_EPOCH"
	var expected_count: int = 0
	var rest_s: int = 0
	var task_order: Array = []
	if phase == "express":
		expected_count = context.gains.size()
		rest_s = 30
		task_order = DAY1_TASK_ORDER.duplicate()
		var identities: Dictionary = {}
		for identity: Variant in session.order:
			if not context.gains.has(identity) or identities.has(identity):
				return "EXPRESS_GAIN_ORDER_NOT_A_PERMUTATION"
			identities[identity] = true
		if session.order.size() != expected_count or not _integer(day_role, 0, 0):
			return "EXPRESS_GAIN_ORDER_NOT_A_PERMUTATION"
		context.express_count += 1
		if context.express_count > 1:
			return "DUPLICATE_EXPRESS_SESSION"
	elif phase == "confirmation":
		expected_count = 4
		rest_s = 60
		if not _integer(day_role, 1, 2) or context.confirmation_orders.has(int(day_role)):
			return "DUPLICATE_OR_INVALID_CONFIRMATION_DAY_ROLE"
		if not session.order in [["A", "B", "B", "A"], ["B", "A", "A", "B"]]:
			return "WRONG_CONFIRMATION_ORDER"
		context.confirmation_orders[int(day_role)] = session.order
		task_order = DAY1_TASK_ORDER.duplicate() if day_role == 1 else DAY2_TASK_ORDER.duplicate()
	else:
		return "UNKNOWN_PLAN_PHASE"
	if session.periods.size() != expected_count:
		return "WRONG_PERIOD_COUNT"
	var session_id: String = "%s.day%d.epoch%d" % [phase, int(day_role), int(epoch)]
	if session.get("session_id") != session_id or context.session_ids.has(session_id):
		return "INVALID_OR_DUPLICATE_SESSION_ID"
	context.session_ids[session_id] = true
	var seed: String = _seed_for_session(plan, phase)
	if not _valid_seed(seed):
		return "INVALID_PLAN_SEED_HEX"
	if plan.get("schema_version") == "aimlocal.calibration.plan.v2":
		var order_stream: Dictionary = _stream(seed, "orders", "0", "0", "0", "ALL", "orders")
		var expected_order: Array = []
		if phase == "express":
			for gain: Dictionary in plan.candidates:
				expected_order.append(gain.candidate_id)
			_shuffle(expected_order, order_stream.rng)
		else:
			var order_text: String = "ABBA" if order_stream.rng.randint(0, 1) == 0 else "BAAB"
			if day_role == 2:
				order_text = "BAAB" if order_text == "ABBA" else "ABBA"
			expected_order.assign(order_text.split(""))
		if session.order != expected_order:
			return "ORDER_SEED_MISMATCH"
	var budget_s: int = 60 + expected_count * 192 + (expected_count - 1) * rest_s
	if not _time_is(session, "planned_duration_s", budget_s):
		return "BUDGET_MISMATCH"
	if session.task_order != task_order:
		return "UNDECLARED_TASK_ORDER"
	var preflight: Dictionary = session.preflight
	if not _time_is(preflight, "start_s", 0):
		return "PREFLIGHT_START_MISMATCH"
	if not _time_is(preflight, "end_s", 60):
		return "PREFLIGHT_DURATION_MISMATCH"
	if preflight.get("gain_candidate_id") != "A" or preflight.tasks.size() != 4:
		return "PREFLIGHT_GAIN_OR_TASK_COUNT_MISMATCH"
	for task_index: int in 4:
		if not preflight.tasks[task_index] is Dictionary:
			return "MALFORMED_PREFLIGHT"
		var segment: Dictionary = preflight.tasks[task_index]
		var task: String = task_order[task_index]
		if segment.get("task") != task:
			return "PREFLIGHT_TASK_ORDER_MISMATCH"
		if not _time_is(segment, "start_s", task_index * 15) or not _time_is(segment, "end_s", (task_index + 1) * 15):
			return "PREFLIGHT_TIMELINE_MISMATCH"
		if segment.get("expose_deck_interval_s") != [0.0, 15.0] or not _false(segment.get("comparative_utility_included")) or not _true(segment.get("ignore_partial_final_opportunity_for_familiarization_metric")):
			return "PREFLIGHT_COMPARATIVE_EXPOSURE_MISMATCH"
		var link_error: String = _deck_link_error(plan, segment, task, phase + "_preflight", int(day_role), 0, int(epoch), context)
		if not link_error.is_empty():
			return link_error
	if session.interperiod_rests.size() != expected_count - 1:
		return "WRONG_INTERPERIOD_REST_COUNT"
	for period_index: int in expected_count:
		if not session.periods[period_index] is Dictionary:
			return "MALFORMED_PERIOD"
		var period: Dictionary = session.periods[period_index]
		var start_s: int = 60 + period_index * (192 + rest_s)
		if not _time_is(period, "start_s", start_s):
			return "PERIOD_START_NOT_ON_FROZEN_TIMELINE"
		if not _time_is(period, "end_s", start_s + 192):
			return "WRONG_PERIOD_DURATION"
		if not _integer(period.get("period_index"), period_index, period_index):
			return "WRONG_PERIOD_INDEX"
		var alias: String = session.order[period_index]
		var identity: String = context.aliases[alias] if phase == "confirmation" else alias
		if period.get("comparison_alias") != alias or period.get("candidate_id") != identity:
			return "PERIOD_ALIAS_OR_CANDIDATE_MISMATCH"
		var applied_gain: Variant = period.get("applied_gain")
		if not applied_gain is Dictionary or not applied_gain.get("decimal_roundtrip") is String or not applied_gain.decimal_roundtrip.is_valid_float():
			return "MALFORMED_PERIOD_GAIN"
		if not applied_gain.get("ieee754_binary64_big_endian_hex") is String:
			return "MALFORMED_PERIOD_GAIN"
		var applied_value: float = Canonical.float64_from_hex(applied_gain.ieee754_binary64_big_endian_hex)
		if not is_finite(applied_value) or applied_value <= 0.0 or _decimal17(applied_value) != applied_gain.decimal_roundtrip:
			return "MALFORMED_PERIOD_GAIN"
		if _bits(applied_value) != context.gains[identity].degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex:
			return "PERIOD_APPLIED_GAIN_MISMATCH"
		var pair_index: int = 0 if phase == "express" else period_index / 2
		if not _integer(period.get("pair_index"), pair_index, pair_index):
			return "PERIOD_PAIR_INDEX_MISMATCH"
		if not period.get("acclimation") is Dictionary or not period.acclimation.get("task_segments") is Array:
			return "MALFORMED_WARMUP"
		var warmup: Dictionary = period.acclimation
		if not _time_is(warmup, "start_s", start_s):
			return "WARMUP_START_MISMATCH"
		if not _time_is(warmup, "end_s", start_s + 60):
			return "WARMUP_DURATION_MISMATCH"
		if not _false(warmup.get("score_included")) or warmup.task_segments.size() != 4:
			return "WARMUP_SCORE_OR_TASK_COUNT_MISMATCH"
		for task_index: int in 4:
			if not warmup.task_segments[task_index] is Dictionary:
				return "MALFORMED_WARMUP"
			var segment: Dictionary = warmup.task_segments[task_index]
			var task: String = task_order[task_index]
			if segment.get("task") != task:
				return "WARMUP_TASK_ORDER_MISMATCH"
			if not _time_is(segment, "start_s", start_s + task_index * 15) or not _time_is(segment, "end_s", start_s + (task_index + 1) * 15):
				return "WARMUP_TIMELINE_MISMATCH"
			if segment.get("expose_deck_interval_s") != [0.0, 15.0] or not _false(segment.get("comparative_utility_included")) or not _true(segment.get("final_partial_opportunity_censored")):
				return "WARMUP_COMPARATIVE_EXPOSURE_MISMATCH"
			var link_error: String = _deck_link_error(plan, segment, task, phase + "_warmup", int(day_role), pair_index, int(epoch), context)
			if not link_error.is_empty():
				return link_error
		if not period.get("scored_cells") is Array or period.scored_cells.size() != 4:
			return "MISSING_TASK"
		for task_index: int in 4:
			if not period.scored_cells[task_index] is Dictionary:
				return "MALFORMED_SCORED_CELL"
			var cell: Dictionary = period.scored_cells[task_index]
			var task: String = task_order[task_index]
			var cell_id: Variant = cell.get("cell_id")
			if context.cell_ids.has(cell_id):
				return "DUPLICATE_SCORED_CELL_ID"
			if cell_id != "%s.p%d.%s" % [session_id, period_index, task]:
				return "INVALID_SCORED_CELL_ID"
			context.cell_ids[cell_id] = true
			if cell.get("candidate_id") != identity:
				return "CELL_CANDIDATE_MISMATCH"
			if cell.get("task") != task or cell.get("task_id") != "CAL_" + task + "_R2":
				return "SCORED_CELL_TASK_ORDER_MISMATCH"
			var onset_s: int = start_s + 63 + 33 * task_index
			if not _time_is(cell, "scored_start_s", onset_s):
				return "WRONG_SCORE_OFFSET"
			if not _time_is(cell, "countdown_start_s", onset_s - 3):
				return "WRONG_COUNTDOWN_OFFSET"
			if not _time_is(cell, "scored_end_s", onset_s + 24) or not _time_is(cell, "duration_s", 24):
				return "WRONG_SCORED_CELL_DURATION"
			if not _time_is(cell, "recovery_end_s", onset_s + 30):
				return "WRONG_RECOVERY_DURATION"
			if cell.get("condition_snapshot_sha256") != plan.condition_snapshot_sha256:
				return "CELL_CONDITION_SNAPSHOT_MISMATCH"
			if cell.get("logical_stimulus_time_origin") != "scored_start":
				return "SCORED_STIMULUS_ORIGIN_MISMATCH"
			var link_error: String = _deck_link_error(plan, cell, task, phase, int(day_role), pair_index, int(epoch), context)
			if not link_error.is_empty():
				return link_error
		if period_index < expected_count - 1:
			if not session.interperiod_rests[period_index] is Dictionary:
				return "MALFORMED_REST"
			var rest: Dictionary = session.interperiod_rests[period_index]
			if not _time_is(rest, "start_s", start_s + 192):
				return "REST_START_MISMATCH"
			if not _time_is(rest, "end_s", start_s + 192 + rest_s):
				return "REST_DURATION_MISMATCH"
			if rest.get("gain_candidate_id") != identity or not _false(rest.get("restore_baseline")):
				return "REST_GAIN_CONTINUITY_BROKEN"
	context.duration_s += budget_s
	context.scored_cells += expected_count * 4
	return ""


static func _deck_link_error(plan: Dictionary, segment: Dictionary, task: String, phase: String, day: int, pair: int, epoch: int, context: Dictionary) -> String:
	var identity: Variant = segment.get("deck_id")
	if not plan.decks.has(identity) or not plan.decks[identity] is Dictionary:
		return "UNDECLARED_DECK_ID"
	var deck: Dictionary = plan.decks[identity]
	if segment.get("deck_manifest_sha256") != deck.get("manifest_sha256"):
		return "DECK_HASH_LINK_MISMATCH"
	if deck.get("task_id") != "CAL_" + task + "_R2":
		return "DECK_TASK_MISMATCH"
	if deck.get("difficulty") != plan.condition_snapshot.difficulty_by_task[task]:
		return "DECK_DIFFICULTY_MISMATCH"
	if identity != "%s.d%d.pair%d.e%d.%s" % [phase, day, pair, epoch, task]:
		return "UNPAIRED_OR_WRONG_DOMAIN_STIMULUS_MANIFEST"
	var seed_phase: String = phase.trim_suffix("_preflight").trim_suffix("_warmup")
	var seed: String = _seed_for_session(plan, seed_phase)
	if not deck.get("rng_seeds") is Dictionary:
		return "MALFORMED_DECK_SEEDS"
	for domain: String in ["layout", "timing", "motion"]:
		var expected: Dictionary = _stream(seed, phase, str(day), str(pair), str(epoch), task, domain).seed
		if Canonical.semantic_sha256(deck.rng_seeds.get(domain)) != Canonical.semantic_sha256(expected):
			return "DECK_SEED_TUPLE_MISMATCH"
	context.deck_ids[identity] = true
	return ""


static func _equivalent(first: Variant, second: Variant, ignored_fields: Array = []) -> bool:
	if _number(first) and _number(second):
		return absf(float(first) - float(second)) <= NUMERIC_TOLERANCE
	if typeof(first) != typeof(second):
		return false
	if first is Dictionary:
		var first_keys: Array = first.keys()
		var second_keys: Array = second.keys()
		for field: String in ignored_fields:
			first_keys.erase(field)
			second_keys.erase(field)
		if first_keys.size() != second_keys.size():
			return false
		for key: Variant in first_keys:
			if not second.has(key) or not _equivalent(first[key], second[key], ignored_fields):
				return false
		return true
	if first is Array:
		if first.size() != second.size():
			return false
		for index: int in first.size():
			if not _equivalent(first[index], second[index], ignored_fields):
				return false
		return true
	return first == second


static func _deck_error(identity: String, deck: Dictionary) -> String:
	if deck.get("deck_id") != identity:
		return "DECK_ID_KEY_MISMATCH"
	if Canonical.semantic_sha256(_without(deck, "manifest_sha256")) != deck.get("manifest_sha256"):
		return "DECK_HASH_MISMATCH"
	if not _time_is(deck, "duration_s", 24.0):
		return "WRONG_MANIFEST_HORIZON"
	if not deck.get("task_id") is String or not deck.get("rng_seeds") is Dictionary or not deck.rng_seeds.get("layout") is Dictionary:
		return "MALFORMED_DECK"
	var task: String = deck.task_id.trim_prefix("CAL_").trim_suffix("_R2")
	if not task in TASKS or deck.task_id != "CAL_" + task + "_R2" or not deck.get("difficulty") in ["novice", "standard", "advanced"]:
		return "UNKNOWN_TASK_OR_DIFFICULTY"
	var encoded_tuple: Variant = deck.rng_seeds.layout.get("tuple_canonical_json")
	if not encoded_tuple is String:
		return "MALFORMED_DECK_SEEDS"
	var parts: Variant = JSON.parse_string(encoded_tuple)
	if not parts is Array or parts.size() != 8:
		return "MALFORMED_DECK_SEEDS"
	for part: Variant in parts:
		if not part is String:
			return "MALFORMED_DECK_SEEDS"
	if parts[0] != REVISION or parts[6] != task or parts[7] != "layout" or not _valid_seed(parts[1]):
		return "DECK_SEED_TUPLE_MISMATCH"
	var expected: Dictionary = make_deck(parts[1], parts[2], parts[3], parts[4], parts[5], task, deck.difficulty)
	if expected.has("error"):
		return expected.error
	if task == "REACTIVE":
		if not deck.get("trajectory_tape") is Dictionary or Canonical.semantic_sha256(deck.trajectory_tape) != deck.get("trajectory_tape_sha256") or not _time_is(deck.trajectory_tape, "horizon_s", 24.0):
			return "REACTIVE_TAPE_HASH_OR_HORIZON_MISMATCH"
		if not _equivalent(deck.get("shared_motion_source"), expected.shared_motion_source):
			return "SHARED_EX06_RESOURCE_HASH_MISMATCH"
	if not _equivalent(deck, expected, ["manifest_sha256", "trajectory_tape_sha256"]):
		return "DECK_STIMULUS_DOES_NOT_MATCH_FROZEN_SEED"
	if deck.manifest_sha256 != expected.manifest_sha256:
		return "DECK_STIMULUS_DOES_NOT_MATCH_FROZEN_SEED"
	return ""


static func validate_conditions(plan: Dictionary, current_conditions: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_plan(plan)
	if not validation.ok:
		return validation
	if validation.is_example:
		return _error("EXAMPLE_PLAN_NOT_RUNTIME")
	var prepared: Dictionary = _prepare_conditions(current_conditions, plan.candidates, plan.condition_snapshot.objective, plan.condition_snapshot.difficulty_by_task)
	if not prepared.ok:
		return prepared
	if Canonical.semantic_sha256(prepared.snapshot) != plan.condition_snapshot_sha256:
		return _error("CURRENT_CONDITION_SNAPSHOT_MISMATCH")
	return {"ok": true, "error": "", "condition_snapshot_sha256": plan.condition_snapshot_sha256}


static func create_day_epoch(plan: Dictionary, day_role: int, attempt_epoch: int) -> Dictionary:
	var validation: Dictionary = validate_plan(plan)
	if not validation.ok:
		return validation
	if validation.is_example:
		return _error("EXAMPLE_PLAN_NOT_RUNTIME")
	if attempt_epoch < 0 or attempt_epoch > 1:
		return _error("MAXIMUM_DAY_ATTEMPTS_EXCEEDED")
	var source_session: Dictionary = {}
	for session: Dictionary in plan.sessions:
		if session.day_role == day_role:
			source_session = session
	if source_session.is_empty():
		return _error("WRONG_DAY_ROLES")
	var temporary_plan: Dictionary = plan.duplicate(true)
	temporary_plan.decks = {}
	var session: Dictionary = _make_session(temporary_plan, source_session.phase, day_role, attempt_epoch, source_session.order, _seed_for_session(plan, source_session.phase))
	if session.has("error"):
		return session
	var bundle: Dictionary = {"schema_version": "aimlocal.calibration.day_epoch.v2", "plan_sha256": plan.plan_sha256,
		"condition_snapshot_sha256": plan.condition_snapshot_sha256, "session": session, "decks": temporary_plan.decks}
	bundle["epoch_sha256"] = Canonical.semantic_sha256(bundle)
	_freeze(bundle)
	return {"ok": true, "error": "", "epoch": bundle}


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for element: Variant in value:
			_freeze(element)
		value.make_read_only()


static func frame_quality(frame_intervals_s: Array) -> Dictionary:
	if frame_intervals_s.is_empty():
		return _error("MISSING_RENDER_FRAMETIMES")
	var ordered: Array[float] = []
	var total_s: float = 0.0
	for interval: Variant in frame_intervals_s:
		if not _number(interval) or float(interval) <= 0.0:
			return _error("INVALID_RENDER_FRAMETIME")
		ordered.append(float(interval))
		total_s += float(interval)
	ordered.sort()
	var count: int = ordered.size()
	var midpoint: int = count / 2
	var median_s: float = ordered[midpoint] if count % 2 == 1 else (ordered[midpoint - 1] + ordered[midpoint]) / 2.0
	var quality: Dictionary = {"mean_fps": count / total_s, "median_fps": 1.0 / median_s,
		"p99_ms": ordered[int(ceil(0.99 * count)) - 1] * 1000.0, "max_ms": ordered[-1] * 1000.0, "frame_count": count}
	var reasons: Array = _quality_failures(quality)
	quality.merge({"ok": true, "eligible": reasons.is_empty(), "reasons": reasons})
	return quality


static func _quality_failures(quality: Dictionary) -> Array:
	for field: String in ["mean_fps", "median_fps", "p99_ms", "max_ms"]:
		if not _number(quality.get(field)) or float(quality[field]) <= 0.0:
			return ["missing_or_invalid_render_quality"]
	if quality.p99_ms > quality.max_ms or (quality.has("frame_count") and not _integer(quality.frame_count, 1, MAX_SAFE_INTEGER)):
		return ["inconsistent_render_quality"]
	var reasons: Array = []
	if quality.mean_fps < 55.0:
		reasons.append("mean_fps_below_minimum")
	if quality.p99_ms > 25.0:
		reasons.append("p99_frametime_above_maximum")
	if quality.max_ms > 100.0:
		reasons.append("maximum_frametime_above_maximum")
	return reasons


static func _timestamp_seconds(value: Variant) -> Variant:
	if _number(value) and float(value) >= 0.0 and float(value) <= MAX_SAFE_INTEGER:
		return float(value)
	if not value is String or not value.ends_with("Z"):
		return null
	var expression := RegEx.new()
	expression.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?Z$")
	if expression.search(value) == null:
		return null
	var base: String = value.substr(0, 19)
	var seconds: int = Time.get_unix_time_from_datetime_string(base)
	if Time.get_datetime_string_from_unix_time(seconds) != base:
		return null
	var fractional_s: float = 0.0
	if value.length() > 20:
		fractional_s = value.substr(19, value.length() - 20).to_float()
	return float(seconds) + fractional_s


static func _local_date_error(report: Dictionary, start_utc: float) -> String:
	var date: Variant = report.get("player_local_date")
	if not date is String or date.length() != 10:
		return "MISSING_PLAYER_LOCAL_DATE"
	var expression := RegEx.new()
	expression.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
	if expression.search(date) == null:
		return "INVALID_PLAYER_LOCAL_DATE"
	var date_seconds: int = Time.get_unix_time_from_datetime_string(date + "T00:00:00")
	if Time.get_date_string_from_unix_time(date_seconds) != date:
		return "INVALID_PLAYER_LOCAL_DATE"
	if report.has("player_utc_offset_minutes"):
		if not _integer(report.player_utc_offset_minutes, -1440, 1440):
			return "INVALID_PLAYER_UTC_OFFSET"
		if Time.get_date_string_from_unix_time(int(floor(start_utc + float(report.player_utc_offset_minutes) * 60.0))) != date:
			return "PLAYER_LOCAL_DATE_TIMESTAMP_MISMATCH"
	return ""


static func validate_day_window(first_day: Dictionary, second_day: Dictionary = {}, express_end_utc: Variant = null) -> Dictionary:
	var first_start: Variant = _timestamp_seconds(first_day.get("actual_start_utc"))
	if first_start == null:
		return _error("MISSING_OR_INVALID_ACTUAL_START_UTC")
	var date_error: String = _local_date_error(first_day, first_start)
	if not date_error.is_empty():
		return _error(date_error)
	if express_end_utc != null:
		var express_end: Variant = _timestamp_seconds(express_end_utc)
		if express_end == null:
			return _error("MISSING_OR_INVALID_EXPRESS_END_UTC")
		if float(first_start) - float(express_end) < 12.0 * 3600.0:
			return _error("EXPRESS_TO_CONFIRMATION_GAP_BELOW_12H")
	if second_day.is_empty():
		return {"ok": true, "error": ""}
	var second_start: Variant = _timestamp_seconds(second_day.get("actual_start_utc"))
	if second_start == null:
		return _error("MISSING_OR_INVALID_ACTUAL_START_UTC")
	date_error = _local_date_error(second_day, second_start)
	if not date_error.is_empty():
		return _error(date_error)
	if first_day.player_local_date == second_day.player_local_date:
		return _error("CONFIRMATION_REQUIRES_DISTINCT_LOCAL_DATES")
	var gap_s: float = float(second_start) - float(first_start)
	if gap_s < 12.0 * 3600.0 or gap_s > 168.0 * 3600.0:
		return _error("CONFIRMATION_START_GAP_OUTSIDE_12_TO_168H")
	return {"ok": true, "error": "", "gap_h": gap_s / 3600.0}


static func validate_day_epoch(plan: Dictionary, epoch: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_plan(plan)
	if not validation.ok:
		return validation
	if validation.is_example:
		return _error("EXAMPLE_PLAN_NOT_RUNTIME")
	if epoch.get("schema_version") != "aimlocal.calibration.day_epoch.v2" or epoch.get("plan_sha256") != plan.plan_sha256 or epoch.get("condition_snapshot_sha256") != plan.condition_snapshot_sha256:
		return _error("EPOCH_PLAN_OR_CONDITION_MISMATCH")
	if Canonical.semantic_sha256(_without(epoch, "epoch_sha256")) != epoch.get("epoch_sha256") or not epoch.get("session") is Dictionary or not epoch.get("decks") is Dictionary:
		return _error("EPOCH_HASH_OR_SHAPE_MISMATCH")
	var gains: Dictionary = {}
	for gain: Dictionary in plan.candidates:
		gains[gain.candidate_id] = gain
	var epoch_plan: Dictionary = plan.duplicate(true)
	epoch_plan.decks = epoch.decks
	var context: Dictionary = {"gains": gains, "aliases": _aliases(plan), "cell_ids": {}, "session_ids": {}, "deck_ids": {}, "confirmation_orders": {}, "duration_s": 0, "scored_cells": 0, "express_count": 0}
	var session_error: String = _session_error(epoch_plan, epoch.session, context)
	if not session_error.is_empty():
		return _error(session_error)
	if epoch.session.phase != plan.phase or epoch.decks.size() != context.deck_ids.size():
		return _error("EPOCH_PHASE_OR_MANIFEST_COUNT_MISMATCH")
	for deck_id: String in epoch.decks:
		var deck_error: String = _deck_error(deck_id, epoch.decks[deck_id])
		if not deck_error.is_empty():
			return _error(deck_error)
	return {"ok": true, "error": "", "scored_cells": context.scored_cells, "epoch_sha256": epoch.epoch_sha256}


static func validate_epoch_report(plan: Dictionary, epoch: Dictionary, report: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_day_epoch(plan, epoch)
	if not validation.ok:
		return validation
	var session: Dictionary = epoch.session
	if report.get("plan_sha256") != plan.plan_sha256 or report.get("epoch_sha256") != epoch.epoch_sha256 or report.get("condition_snapshot_sha256") != plan.condition_snapshot_sha256:
		return _error("REPORT_PLAN_EPOCH_OR_CONDITION_HASH_MISMATCH")
	if report.get("session_id") != session.session_id or not _integer(report.get("day_role"), int(session.day_role), int(session.day_role)) or not _integer(report.get("attempt_epoch"), int(session.attempt_epoch), int(session.attempt_epoch)):
		return _error("REPORT_SESSION_OR_EPOCH_ID_MISMATCH")
	var actual_start: Variant = _timestamp_seconds(report.get("actual_start_utc"))
	var actual_end: Variant = _timestamp_seconds(report.get("actual_end_utc"))
	if actual_start == null or actual_end == null or float(actual_end) < float(actual_start):
		return _error("INVALID_EPOCH_ACTUAL_TIMESTAMPS")
	var date_error: String = _local_date_error(report, actual_start)
	if not date_error.is_empty():
		return _error(date_error)
	if not report.get("cells") is Array or not report.get("waits") is Array or not report.get("technical_events") is Array:
		return _error("MISSING_EPOCH_CELLS_WAITS_OR_EVENTS")
	var reasons: Array = []
	for event: Variant in report.technical_events:
		var kind: Variant = event.get("kind") if event is Dictionary else event
		if not kind is String or (not kind in protocol().quality.invalidating_events and not kind in ["process_restart", "abort", "long_unplanned_interruption"]):
			return _error("UNKNOWN_TECHNICAL_EVENT")
		if not kind in reasons:
			reasons.append(kind)
	var extra_wait_s: float = 0.0
	var previous_wait_end_s: float = 0.0
	for wait_entry: Variant in report.waits:
		if not wait_entry is Dictionary or not _number(wait_entry.get("start_s")) or not _number(wait_entry.get("end_s")) or not _false(wait_entry.get("planned")):
			return _error("MALFORMED_EXTRA_WAIT")
		var wait_record: Dictionary = wait_entry
		if wait_record.start_s < previous_wait_end_s or wait_record.end_s <= wait_record.start_s or wait_record.end_s > float(actual_end) - float(actual_start):
			return _error("EXTRA_WAIT_TIMELINE_MISMATCH")
		previous_wait_end_s = wait_record.end_s
		extra_wait_s += wait_record.end_s - wait_record.start_s
		if wait_record.end_s - wait_record.start_s > 900.0 and not "long_unplanned_interruption" in reasons:
			reasons.append("long_unplanned_interruption")
	var expected_cells: Dictionary = {}
	for period: Dictionary in session.periods:
		for cell: Dictionary in period.scored_cells:
			expected_cells[cell.cell_id] = cell
	var by_id: Dictionary = {}
	var complete: bool = _true(report.get("complete")) and report.cells.size() == expected_cells.size()
	var medians_by_task: Dictionary = {}
	for task: String in TASKS:
		medians_by_task[task] = []
	for row: Variant in report.cells:
		if not row is Dictionary or not expected_cells.has(row.get("cell_id")) or by_id.has(row.get("cell_id")):
			return _error("UNPLANNED_OR_DUPLICATE_REPORTED_CELL")
		var cell: Dictionary = row
		var expected: Dictionary = expected_cells[cell.cell_id]
		by_id[cell.cell_id] = cell
		for field: String in ["task", "task_id", "candidate_id", "deck_manifest_sha256", "condition_snapshot_sha256"]:
			if cell.get(field) != expected[field]:
				return _error("REPORTED_CELL_" + field.to_upper() + "_MISMATCH")
		var applied: Variant = cell.get("applied_gain")
		var gain: Dictionary = {}
		for candidate: Dictionary in plan.candidates:
			if candidate.candidate_id == expected.candidate_id:
				gain = candidate
		if not applied is Dictionary or Canonical.semantic_sha256(applied) != Canonical.semantic_sha256(gain.degrees_per_relative_input_unit):
			return _error("REPORTED_CELL_APPLIED_GAIN_MISMATCH")
		if not _true(cell.get("complete")):
			complete = false
			continue
		if not _time_is(cell, "duration_s", 24.0) or not _number(cell.get("actual_start_s")) or not _number(cell.get("actual_end_s")) or cell.actual_start_s < expected.scored_start_s or cell.actual_end_s - cell.actual_start_s < 24.0:
			return _error("REPORTED_CELL_DURATION_OR_TIMELINE_MISMATCH")
		if cell.actual_end_s > float(actual_end) - float(actual_start):
			return _error("REPORTED_CELL_OUTSIDE_SESSION")
		if not _number(cell.get("utility")) or cell.utility < 0.0 or cell.utility > 1.0:
			return _error("UTILITY_OUT_OF_BOUNDS")
		if cell.task in ["CLICK", "SWITCH"]:
			var opportunities: int = 16 if cell.task == "CLICK" else 12
			if not _integer(cell.get("opportunities"), opportunities, opportunities) or not _integer(cell.get("success_count"), 0, opportunities):
				return _error("INVALID_SUCCESS_COUNT_OR_OPPORTUNITY_DENOMINATOR")
			if cell.utility > float(cell.success_count) / opportunities + NUMERIC_TOLERANCE:
				return _error("UTILITY_EXCEEDS_SUCCESS_FRACTION")
		var quality: Variant = cell.get("render_quality")
		if not quality is Dictionary:
			complete = false
			continue
		for failure: String in _quality_failures(quality):
			if not failure in reasons:
				reasons.append(failure)
		for wait_record: Dictionary in report.waits:
			if wait_record.start_s < cell.actual_end_s and wait_record.end_s > cell.actual_start_s:
				return _error("WAIT_OVERLAPS_SCORED_TASK")
	if complete:
		if float(actual_end) - float(actual_start) < float(session.planned_duration_s) + extra_wait_s:
			return _error("ACTUAL_BUDGET_OMITS_PROGRAMMED_TIME_OR_WAITS")
		var previous_end_s: float = 0.0
		for period: Dictionary in session.periods:
			for expected: Dictionary in period.scored_cells:
				var cell: Dictionary = by_id[expected.cell_id]
				if cell.actual_start_s < previous_end_s:
					return _error("REPORTED_SCORED_CELLS_OVERLAP")
				previous_end_s = cell.actual_end_s + 9.0
				if _number(cell.render_quality.get("median_fps")):
					medians_by_task[cell.task].append(float(cell.render_quality.median_fps))
		for task: String in TASKS:
			var medians: Array = medians_by_task[task]
			if medians.size() != session.periods.size():
				complete = false
				continue
			if session.phase == "express":
				var relative_difference: float = (float(medians.max()) - float(medians.min())) / ((float(medians.max()) + float(medians.min())) / 2.0)
				if relative_difference > 0.10 and not "paired_median_fps_difference" in reasons:
					reasons.append("paired_median_fps_difference")
			else:
				for pair_index: int in 2:
					var first_median: float = medians[pair_index * 2]
					var second_median: float = medians[pair_index * 2 + 1]
					if absf(first_median - second_median) / ((first_median + second_median) / 2.0) > 0.10 and not "paired_median_fps_difference" in reasons:
						reasons.append("paired_median_fps_difference")
	var summary: Dictionary = {"day_role": session.day_role, "order": "".join(PackedStringArray(session.order)), "periods": []}
	if complete:
		for period: Dictionary in session.periods:
			var utilities: Dictionary = {}
			var counts: Dictionary = {}
			for expected: Dictionary in period.scored_cells:
				var cell: Dictionary = by_id[expected.cell_id]
				utilities[cell.task] = cell.utility
				if cell.task in ["CLICK", "SWITCH"]:
					counts[cell.task] = int(cell.success_count)
			summary.periods.append({"alias": period.comparison_alias, "candidate_id": period.candidate_id, "utilities": utilities,
				"click_opportunities": 16, "switch_opportunities": 12, "click_successes": counts.CLICK, "switch_completions": counts.SWITCH})
	return {"ok": true, "error": "", "complete": complete, "eligible": complete and reasons.is_empty(), "reasons": reasons,
		"summary": summary, "actual_duration_s": float(actual_end) - float(actual_start), "extra_wait_s": extra_wait_s}


static func compare_epochs(plan: Dictionary, reports: Array, express_end_utc: Variant = null) -> Dictionary:
	var plan_validation: Dictionary = validate_plan(plan)
	if not plan_validation.ok:
		return plan_validation
	if plan_validation.is_example:
		return _error("EXAMPLE_PLAN_NOT_RUNTIME")
	var by_role: Dictionary = {}
	for report: Variant in reports:
		if not report is Dictionary or not _integer(report.get("day_role"), 0, 2) or not _integer(report.get("attempt_epoch"), 0, 1):
			return _error("INVALID_REPORTED_DAY_ROLE_OR_EPOCH")
		var role: int = int(report.day_role)
		if not by_role.has(role):
			by_role[role] = []
		by_role[role].append(report)
	var data: Dictionary = {"protocol_id": PROTOCOL_ID, "protocol_sha256": PROTOCOL_SHA256, "phase": plan.phase,
		"objective": plan.condition_snapshot.objective, "gains": [], "accepted_conditions_verified": true, "terminal_condition_failures": []}
	var accepted: Dictionary = {}
	var accepted_reports: Dictionary = {}
	var total_actual_s: float = 0.0
	var total_wait_s: float = 0.0
	var attempt_count: int = 0
	for session: Dictionary in plan.sessions:
		var role: int = int(session.day_role)
		var attempts: Array = by_role.get(role, [])
		attempts = attempts.duplicate()
		attempts.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.attempt_epoch < second.attempt_epoch)
		if attempts.size() > 2:
			return _error("MAXIMUM_DAY_ATTEMPTS_EXCEEDED")
		var previous: Dictionary = {}
		var previous_report: Dictionary = {}
		for attempt_index: int in attempts.size():
			var report: Dictionary = attempts[attempt_index]
			if int(report.attempt_epoch) != attempt_index:
				return _error("MISSING_OR_DUPLICATE_ATTEMPT_HISTORY")
			if accepted.has(role):
				return _error("RETRY_AFTER_FIRST_VALID_COMPLETE_EPOCH")
			if attempt_index > 0:
				if previous.reasons.is_empty():
					return _error("RETRY_WITHOUT_WHOLE_EPOCH_TECHNICAL_CAUSE")
				var previous_end: Variant = _timestamp_seconds(previous_report.get("actual_end_utc"))
				var next_start: Variant = _timestamp_seconds(report.get("actual_start_utc"))
				if previous_end == null or next_start == null or float(next_start) < float(previous_end):
					return _error("ATTEMPT_CHRONOLOGY_MISMATCH")
			var built: Dictionary = create_day_epoch(plan, role, attempt_index)
			if not built.ok:
				return built
			var eligibility: Dictionary = validate_epoch_report(plan, built.epoch, report)
			if not eligibility.ok:
				return eligibility
			previous = eligibility
			previous_report = report
			total_actual_s += eligibility.actual_duration_s
			total_wait_s += eligibility.extra_wait_s
			attempt_count += 1
			if eligibility.eligible:
				accepted[role] = eligibility.summary
				accepted_reports[role] = report
			elif attempt_index == 1 and not eligibility.reasons.is_empty():
				data.terminal_condition_failures.append("retry_exhausted:" + str(role) + ":" + ",".join(PackedStringArray(eligibility.reasons)))
		by_role.erase(role)
	if not by_role.is_empty():
		return _error("UNPLANNED_DAY_ROLE")
	if plan.phase == "express":
		data.gains = plan.candidates.duplicate(true)
		data["candidate_results"] = {}
		data.accepted_conditions_verified = accepted.has(0)
		if accepted.has(0):
			for period: Dictionary in accepted[0].periods:
				data.candidate_results[period.candidate_id] = {"utilities": period.utilities,
					"click_successes": period.click_successes, "switch_completions": period.switch_completions}
	else:
		var aliases: Dictionary = _aliases(plan)
		for alias: String in ["A", "B"]:
			for candidate: Dictionary in plan.candidates:
				if candidate.candidate_id == aliases[alias]:
					var gain: Dictionary = candidate.duplicate(true)
					gain.candidate_id = alias
					data.gains.append(gain)
		data["days"] = []
		for role: int in [1, 2]:
			if accepted.has(role):
				data.days.append(accepted[role])
		if accepted_reports.has(1):
			var window: Dictionary = validate_day_window(accepted_reports[1], accepted_reports.get(2, {}), express_end_utc)
			if not window.ok:
				data.terminal_condition_failures.append(window.error)
	var result: Dictionary = compare(data)
	if result.get("ok") == false:
		return result
	result["budget"] = {"programmed_minimum_s": plan.programmed_total_s, "actual_elapsed_s_all_attempts": total_actual_s,
		"recorded_extra_wait_s": total_wait_s, "scheduled_attempt_count": attempt_count}
	result["accepted_epoch_by_day_role"] = {}
	for role: int in accepted_reports:
		result.accepted_epoch_by_day_role[str(role)] = int(accepted_reports[role].attempt_epoch)
	return result


static func preflight_difficulty(familiarization: Dictionary, difficulty_by_task: Dictionary, change_counts_by_task: Dictionary = {}) -> Dictionary:
	var proposed: Dictionary = difficulty_by_task.duplicate(true)
	var changes: Array = []
	var review_tasks: Array = []
	var levels: Array = ["novice", "standard", "advanced"]
	for task: String in TASKS:
		if not levels.has(proposed.get(task)):
			return _error("CONDITION_DIFFICULTY_MISMATCH")
		if not familiarization.get(task) is Dictionary:
			return {"ok": true, "complete": false, "error": "", "action": "complete_preflight_before_freezing_plan"}
		var row: Dictionary = familiarization[task]
		if not _true(row.get("complete")) or not _number(row.get("utility")):
			return {"ok": true, "complete": false, "error": "", "action": "complete_preflight_before_freezing_plan"}
		if row.utility < 0.0 or row.utility > 1.0:
			return _error("UTILITY_OUT_OF_BOUNDS")
		if task in ["CLICK", "SWITCH"]:
			var expected_count: int = 10 if task == "CLICK" else 7
			if not _integer(row.get("opportunities"), expected_count, expected_count):
				return _error("WRONG_PREFLIGHT_OPPORTUNITY_DENOMINATOR")
		elif not _time_is(row, "duration_s", 15.0):
			return _error("WRONG_PREFLIGHT_TRACKING_DURATION")
		var change_count: Variant = change_counts_by_task.get(task, 0)
		if not _integer(change_count, 0, 2):
			return _error("INVALID_PREFLIGHT_DIFFICULTY_CHANGE_COUNT")
		var adjustment: int = -1 if row.utility < 0.10 else (1 if row.utility > 0.95 else 0)
		if adjustment == 0:
			continue
		var current_index: int = levels.find(proposed[task])
		var next_index: int = current_index + adjustment
		if change_count == 2 or next_index < 0 or next_index >= levels.size():
			review_tasks.append(task)
			continue
		changes.append({"task": task, "from": proposed[task], "to": levels[next_index], "required_additional_trial_s": 24,
			"reason": "familiarization_floor" if adjustment < 0 else "familiarization_ceiling"})
		proposed[task] = levels[next_index]
	return {"ok": true, "error": "", "complete": true, "difficulty_by_task": proposed, "changes": changes,
		"review_tasks": review_tasks, "additional_programmed_s": changes.size() * 24, "requires_new_frozen_plan": not changes.is_empty(),
		"action": "review_configuration" if not review_tasks.is_empty() else ("offer_difficulty_change_before_new_plan" if not changes.is_empty() else "freeze_plan")}
