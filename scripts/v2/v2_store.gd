class_name V2Store
extends RefCounted

const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const LegacySensitivity := preload("res://scripts/sensitivity/sensitivity_service.gd")
const LegacyScoring := preload("res://scripts/statistics/scoring_service.gd")
const Crosshair := preload("res://scripts/presentation/crosshair_profile.gd")
const GameProfiles := preload("res://scripts/sensitivity/game_profile_service.gd")
const DOCUMENT_SCHEMA: String = "aimlocal.store.v2.0"
const PROFILE_SCHEMA: String = "aimlocal.profile.v2.0"
const CALIBRATION_SCHEMA: String = "aimlocal.calibration_state.v2.0"
const HASH_ENCODING: String = "AIM-CANON-1"
const NUMBER_ENCODING: String = "binary64_hex_v1"
const MAX_FILE_BYTES: int = 8 * 1024 * 1024
const MAX_DEPTH: int = 64
const MAX_SAFE_INTEGER: int = 9007199254740991
const HISTORY_LIMIT: int = 2000
const VERIFIED_CACHE_BYTES: int = 16 * 1024 * 1024
const VERIFIED_CACHE_DOCUMENTS: int = 64
const VERTICAL_FOV_DEG: float = 70.53280043291679
const PROFILE_FIELDS: Array[String] = [
	"schema_version", "dpi", "dpi_source", "cm_per_360", "gain_deg_per_relative_unit", "gain_hex",
	"vertical_fov_deg", "invert_y", "accumulated_input", "max_fps", "goal", "reference_game",
	"crosshair_style", "crosshair_size_px", "crosshair_thickness_px", "crosshair_gap_px",
	"crosshair_color", "crosshair_outline", "weapon_id", "show_weapon", "sound_enabled",
	"sound_volume", "reduced_motion", "look_profile_id", "target_color"
]
const STATE_FIELDS: Array[String] = [
	"schema_version", "calibration_id", "protocol_id", "protocol_revision", "plan_sha256",
	"day_role", "epoch", "status", "baseline_profile", "temporary_gain_hex", "checkpoint", "report_ids"
]
const VERSION_FIELDS: Array[String] = [
	"schema_version", "app_version", "engine_version", "catalogue_revision", "mechanic_version",
	"score_version", "render_profile_revision", "protocol_id", "protocol_revision"
]

var root_path: String
var legacy_root_path: String
var last_error: String = ""
var _verified_cache: Dictionary = {}
var _verified_order: Array[String] = []
var _verified_bytes: int = 0
var _verified_report_links: Dictionary = {}
var _verified_link_order: Array[String] = []
var _checkpoint_resources: Dictionary = {}


class StrictJson:
	extends RefCounted
	var source: String = ""
	var position: int = 0
	var error: String = ""

	func parse(text: String) -> Variant:
		source = text
		position = 0
		error = ""
		var result: Variant = value(0)
		space()
		if position != source.length() and error.is_empty():
			error = "JSON_TRAILING_CONTENT"
		return result

	func space() -> void:
		while position < source.length() and source[position] in [" ", "\t", "\r", "\n"]:
			position += 1

	func value(depth: int) -> Variant:
		space()
		if depth > 64 or position >= source.length() or not error.is_empty():
			error = "JSON_DEPTH_OR_VALUE" if error.is_empty() else error
			return null
		match source[position]:
			"{":
				return object(depth + 1)
			"[":
				return array(depth + 1)
			'"':
				return string_value()
			"t":
				return literal("true", true)
			"f":
				return literal("false", false)
			"n":
				return literal("null", null)
			_:
				return number_value()

	func literal(token: String, result: Variant) -> Variant:
		if source.substr(position, token.length()) != token:
			error = "JSON_LITERAL"
		else:
			position += token.length()
		return result

	func object(depth: int) -> Dictionary:
		var result: Dictionary = {}
		position += 1
		space()
		if consume("}"):
			return result
		while error.is_empty():
			space()
			if position >= source.length() or source[position] != '"':
				error = "JSON_OBJECT_KEY"
				break
			var key: Variant = string_value()
			if not error.is_empty():
				break
			if result.has(key):
				error = "JSON_DUPLICATE_KEY"
				break
			space()
			if not consume(":"):
				error = "JSON_OBJECT_COLON"
				break
			result[key] = value(depth)
			space()
			if consume("}"):
				break
			if not consume(","):
				error = "JSON_OBJECT_SEPARATOR"
				break
		return result

	func array(depth: int) -> Array:
		var result: Array = []
		position += 1
		space()
		if consume("]"):
			return result
		while error.is_empty():
			result.append(value(depth))
			space()
			if consume("]"):
				break
			if not consume(","):
				error = "JSON_ARRAY_SEPARATOR"
				break
		return result

	func consume(character: String) -> bool:
		if position < source.length() and source[position] == character:
			position += 1
			return true
		return false

	func string_value() -> Variant:
		var start: int = position
		position += 1
		while position < source.length():
			var character: String = source[position]
			position += 1
			if character == '"':
				var parser := JSON.new()
				if parser.parse(source.substr(start, position - start)) != OK or not parser.data is String:
					error = "JSON_STRING"
					return null
				return parser.data
			if character.unicode_at(0) < 32:
				error = "JSON_STRING_CONTROL"
				return null
			if character == "\\":
				if position >= source.length():
					break
				var escaped: String = source[position]
				position += 1
				if escaped == "u":
					if not unicode_escape():
						return null
				elif not escaped in ['"', "\\", "/", "b", "f", "n", "r", "t"]:
					error = "JSON_STRING_ESCAPE"
					return null
		error = "JSON_STRING_UNTERMINATED"
		return null

	func unicode_escape() -> bool:
		var digits: String = source.substr(position, 4)
		if not hex_digits(digits):
			error = "JSON_UNICODE_ESCAPE"
			return false
		var codepoint: int = digits.hex_to_int()
		position += 4
		if codepoint >= 56320 and codepoint <= 57343:
			error = "JSON_UNPAIRED_SURROGATE"
			return false
		if codepoint >= 55296 and codepoint <= 56319:
			if source.substr(position, 2) != "\\u":
				error = "JSON_UNPAIRED_SURROGATE"
				return false
			var low_digits: String = source.substr(position + 2, 4)
			if not hex_digits(low_digits):
				error = "JSON_UNPAIRED_SURROGATE"
				return false
			var low: int = low_digits.hex_to_int()
			if low < 56320 or low > 57343:
				error = "JSON_UNPAIRED_SURROGATE"
				return false
			position += 6
		return true

	func hex_digits(digits: String) -> bool:
		if digits.length() != 4:
			return false
		for character in digits:
			if not character.to_lower() in "0123456789abcdef":
				return false
		return true

	func digit() -> bool:
		return position < source.length() and source[position] >= "0" and source[position] <= "9"

	func number_value() -> Variant:
		var start: int = position
		consume("-")
		if not digit():
			error = "JSON_NUMBER"
			return null
		if consume("0"):
			if digit():
				error = "JSON_LEADING_ZERO"
				return null
		else:
			while digit():
				position += 1
		var fractional: bool = false
		if consume("."):
			fractional = true
			if not digit():
				error = "JSON_FRACTION"
				return null
			while digit():
				position += 1
		if consume("e") or consume("E"):
			fractional = true
			if not consume("+"):
				consume("-")
			if not digit():
				error = "JSON_EXPONENT"
				return null
			while digit():
				position += 1
		var token: String = source.substr(start, position - start)
		var exponent_index: int = maxi(token.find("e"), token.find("E"))
		if exponent_index >= 0:
			var exponent: String = token.substr(exponent_index + 1)
			if exponent.length() > 6 or exponent.to_int() > 308 or exponent.to_int() < -400:
				error = "JSON_EXPONENT_RANGE"
				return null
		var number: float = token.to_float()
		if not is_finite(number) or absf(number) > 9007199254740991.0:
			error = "JSON_NONFINITE_OR_UNSAFE_NUMBER"
			return null
		return number if fractional else token.to_int()


class ExactNumbers:
	extends RefCounted
	var error: String = ""

	static func encode(value: Variant) -> Variant:
		if value is float:
			return {"f64be": Canonical.float64_hex(value)}
		if value is Array:
			var elements: Array = []
			for element in value:
				elements.append(encode(element))
			return elements
		if value is Dictionary:
			var members: Dictionary = {}
			for key: String in value:
				members[key] = encode(value[key])
			if members.size() == 1 and (members.has("f64be") or members.has("object")):
				return {"object": members}
			return members
		return value

	func decode(value: Variant, depth: int = 0) -> Variant:
		if depth > 64 or not error.is_empty():
			error = "EXACT_NUMBER_DEPTH" if error.is_empty() else error
			return null
		if value is float:
			error = "UNENCODED_BINARY64"
			return null
		if value is Array:
			var elements: Array = []
			for element in value:
				elements.append(decode(element, depth + 1))
			return elements
		if value is Dictionary:
			if value.size() == 1 and value.has("f64be"):
				var bits: Variant = value.f64be
				if not bits is String or bits.length() != 16 or not bits.is_valid_hex_number():
					error = "INVALID_BINARY64_BITS"
					return null
				var number: float = Canonical.float64_from_hex(bits)
				if not is_finite(number):
					error = "NONFINITE_BINARY64"
					return null
				return number
			if value.size() == 1 and value.has("object"):
				if not value.object is Dictionary:
					error = "INVALID_ESCAPED_OBJECT"
					return null
				return decode_object(value.object, depth + 1)
			return decode_object(value, depth + 1)
		return value

	func decode_object(value: Dictionary, depth: int) -> Dictionary:
		var result: Dictionary = {}
		for key: String in value:
			result[key] = decode(value[key], depth)
		return result


func _init(root: String = "user://aim_local/v2") -> void:
	root_path = root.trim_suffix("/")
	legacy_root_path = root_path.get_base_dir()


static func default_profile() -> Dictionary:
	var gain: float = 914.4 / (800.0 * 35.0)
	var profile: Dictionary = {
		"schema_version": PROFILE_SCHEMA, "dpi": 800, "dpi_source": "declared", "cm_per_360": 35.0,
		"gain_deg_per_relative_unit": gain, "gain_hex": Canonical.float64_hex(gain),
		"vertical_fov_deg": VERTICAL_FOV_DEG, "invert_y": false, "accumulated_input": false,
		"max_fps": 144, "goal": "balanced", "reference_game": null, "weapon_id": "pulse",
		"show_weapon": true, "sound_enabled": true, "sound_volume": 45.0, "reduced_motion": false,
		"look_profile_id": "reference_gl_v2", "target_color": "#42D9CB"
	}
	profile.merge(Crosshair.defaults())
	profile.crosshair_color = "#FFFFFF"
	profile.crosshair_outline = true
	return profile


func load_profile() -> Dictionary:
	last_error = ""
	var pending: Dictionary = _calibration_document()
	if not pending.ok:
		last_error = pending.error
		return {}
	if pending.payload != null:
		if pending.get("recovered_from_backup", false):
			last_error = "CALIBRATION_STATE_BACKUP_USED"
		return _decode_profile(pending.payload.baseline_profile)
	var saved: Dictionary = _read_document(root_path.path_join("profile.json"), "profile", true)
	if saved.ok and not saved.missing:
		if saved.get("recovered_from_backup", false):
			last_error = "PROFILE_BACKUP_USED"
		return _decode_profile(saved.payload)
	if not saved.ok:
		last_error = saved.error
		return {}
	var legacy: Dictionary = _read_json(legacy_root_path.path_join("profile.json"))
	if legacy.missing:
		return default_profile()
	if not legacy.ok or not legacy.data is Dictionary or not _json_value(legacy.data):
		last_error = "LEGACY_PROFILE_INVALID"
		return {}
	if not LegacySensitivity.validate_profile(legacy.data).is_empty():
		last_error = "LEGACY_PROFILE_INVALID"
		return {}
	return _import_legacy_profile(legacy.data)


func save_profile(profile: Dictionary) -> bool:
	last_error = ""
	if not _profile_valid(profile):
		return _fail("PROFILE_INVALID")
	var pending: Dictionary = _calibration_document()
	if not pending.ok:
		return _fail(pending.error)
	if pending.payload != null and not _same(_encode_profile(profile), pending.payload.baseline_profile):
		return _fail("CALIBRATION_PROFILE_LOCKED")
	return _write_document("profile.json", "profile", _encode_profile(profile))


func save_report(report: Dictionary) -> bool:
	last_error = ""
	if not _report_valid(report):
		return _fail("REPORT_INVALID")
	return _write_document("reports/" + str(report.session_id) + ".json", "report", report, true)


func history() -> Array:
	last_error = ""
	var rows: Array = []
	for filename in _json_files(root_path.path_join("reports")):
		var saved: Dictionary = _read_document(root_path.path_join("reports").path_join(filename), "report")
		if not saved.ok or str(saved.payload.session_id) + ".json" != filename:
			last_error = "HISTORY_REPORT_INVALID"
			continue
		rows.append({"namespace": "v2", "read_only": true, "kind": "session", "report": saved.payload.duplicate(true), "semantic_sha256": saved.semantic_sha256})
	for directory_name in ["sessions", "calibrations"]:
		for filename in _json_files(legacy_root_path.path_join(directory_name)):
			var saved: Dictionary = _read_json(legacy_root_path.path_join(directory_name).path_join(filename))
			if not saved.ok or not saved.data is Dictionary or not _json_value(saved.data):
				last_error = "HISTORY_LEGACY_INVALID"
				continue
			var report: Dictionary = saved.data
			if directory_name == "sessions" and not LegacyScoring.validate_result(report).is_empty():
				last_error = "HISTORY_LEGACY_INVALID"
				continue
			if directory_name == "calibrations" and (not _integer(report.get("schema_version"), 1, 1) or not _identifier(report.get("calibration_id"))):
				last_error = "HISTORY_LEGACY_INVALID"
				continue
			rows.append({"namespace": "legacy", "read_only": true, "kind": "session" if directory_name == "sessions" else "calibration", "report": report.duplicate(true), "semantic_sha256": null})
	return rows


func save_calibration_state(state: Dictionary) -> bool:
	last_error = ""
	if not _closed(state, STATE_FIELDS, ["calibration_id", "protocol_id", "protocol_revision", "plan_sha256", "day_role", "epoch", "status", "checkpoint"]):
		return _fail("CALIBRATION_STATE_INVALID")
	var existing: Dictionary = _calibration_document()
	if not existing.ok:
		return _fail(existing.error)
	var prepared: Dictionary = state.duplicate(true)
	var baseline: Dictionary
	if existing.payload != null:
		var plan_transition: bool = existing.payload.status == "complete" and state.checkpoint.get("previous_plan_sha256") == existing.payload.plan_sha256
		if existing.payload.calibration_id != state.calibration_id or (existing.payload.plan_sha256 != state.plan_sha256 and not plan_transition) or existing.payload.protocol_revision != state.protocol_revision:
			return _fail("CALIBRATION_ALREADY_PENDING")
		baseline = _decode_profile(existing.payload.baseline_profile)
		if existing.payload.day_role == state.day_role and not _integer(state.epoch, int(existing.payload.epoch), MAX_SAFE_INTEGER):
			return _fail("CALIBRATION_EPOCH_ROLLBACK")
		if existing.payload.day_role != state.day_role:
			var roles: Array[String] = ["express", "day1", "day2"]
			if existing.payload.status != "complete" or roles.find(str(state.day_role)) != roles.find(str(existing.payload.day_role)) + 1:
				return _fail("CALIBRATION_DAY_TRANSITION_INVALID")
	else:
		baseline = load_profile()
		if baseline.is_empty():
			return false
	if state.has("baseline_profile"):
		if not state.baseline_profile is Dictionary or not _profile_valid(state.baseline_profile) or not _same(_encode_profile(state.baseline_profile), _encode_profile(baseline)):
			return _fail("CALIBRATION_BASELINE_MISMATCH")
	prepared["schema_version"] = state.get("schema_version", CALIBRATION_SCHEMA)
	prepared["baseline_profile"] = _encode_profile(baseline)
	prepared["temporary_gain_hex"] = state.get("temporary_gain_hex", null)
	if not state.get("report_ids", []) is Array:
		return _fail("CALIBRATION_STATE_INVALID")
	prepared["report_ids"] = state.get("report_ids", []).duplicate()
	if not _compact_runner_checkpoint(prepared):
		return false
	if not _state_valid(prepared) or not _report_links_valid(prepared.report_ids):
		return _fail("CALIBRATION_STATE_INVALID")
	if existing.payload != null:
		for report_id in existing.payload.report_ids:
			if not report_id in prepared.report_ids:
				return _fail("CALIBRATION_REPORT_ROLLBACK")
	return _write_document("calibration_state.json", "calibration_state", prepared)


func load_calibration_state() -> Dictionary:
	last_error = ""
	var saved: Dictionary = _calibration_document()
	if not saved.ok:
		last_error = saved.error
		return {}
	if saved.payload == null:
		return {}
	var result: Dictionary = saved.payload.duplicate(true)
	result.baseline_profile = _decode_profile(result.baseline_profile)
	if not _report_links_valid(result.report_ids):
		last_error = "CALIBRATION_REPORT_MISSING_OR_INVALID"
		return {}
	if not _expand_runner_checkpoint(result):
		last_error = "CALIBRATION_RESOURCE_INVALID"
		return {}
	if saved.get("recovered_from_backup", false):
		last_error = "CALIBRATION_STATE_BACKUP_USED"
	return result


func _compact_runner_checkpoint(state: Dictionary) -> bool:
	var checkpoint: Dictionary = state.checkpoint
	if checkpoint.get("runner_version") != "calibration_runner_v2.0":
		return true
	for field: String in ["plan", "epoch"]:
		var resource: Variant = checkpoint.get(field)
		if not resource is Dictionary or resource.is_empty():
			continue
		var digest: String = Canonical.semantic_sha256(resource)
		var key: String = str(state.calibration_id) + ":" + field + ":" + digest
		var reference: Dictionary = _checkpoint_resources.get(key, {})
		if reference.is_empty() or not _report_links_valid([reference.session_id]):
			var identity: String = str(state.calibration_id) + ".resource." + field + "." + digest.substr(0, 32)
			var report: Dictionary = {"schema_version": "aimlocal.calibration_resource.v2.0", "session_id": identity,
				"catalogue_revision": state.protocol_revision, "score_version": "cal_utilities_R2", "kind": "calibration_resource",
				"resource_kind": field, "resource_sha256": digest, "resource": resource}
			if not save_report(report):
				return false
			reference = {"session_id": identity, "semantic_sha256": Canonical.semantic_sha256(report), "resource_kind": field, "resource_sha256": digest}
			_checkpoint_resources[key] = reference.duplicate(true)
		checkpoint[field] = {"store_resource_reference": reference}
		if not reference.session_id in state.report_ids:
			state.report_ids.append(reference.session_id)
	checkpoint["report_ids"] = state.report_ids.duplicate()
	return true


func _expand_runner_checkpoint(state: Dictionary) -> bool:
	var checkpoint: Dictionary = state.checkpoint
	if checkpoint.get("runner_version") != "calibration_runner_v2.0":
		return true
	for field: String in ["plan", "epoch"]:
		var value: Variant = checkpoint.get(field)
		if not value is Dictionary or not value.has("store_resource_reference"):
			continue
		var fields: Array[String] = ["session_id", "semantic_sha256", "resource_kind", "resource_sha256"]
		var reference: Variant = value.store_resource_reference
		if value.size() != 1 or not _closed(reference, fields, fields) or not _identifier(reference.session_id) or not _hex(reference.semantic_sha256, 64) or not _hex(reference.resource_sha256, 64) or reference.resource_kind != field or not reference.session_id in state.report_ids:
			return false
		var saved: Dictionary = _read_document(root_path.path_join("reports").path_join(reference.session_id + ".json"), "report")
		if not saved.get("ok", false) or saved.get("missing", true):
			return false
		var report: Dictionary = saved.payload
		if report.get("session_id") != reference.session_id or report.get("kind") != "calibration_resource" or report.get("resource_kind") != field or report.get("resource_sha256") != reference.resource_sha256 or not report.get("resource") is Dictionary:
			return false
		if Canonical.semantic_sha256(report) != reference.semantic_sha256 or Canonical.semantic_sha256(report.resource) != reference.resource_sha256:
			return false
		checkpoint[field] = report.resource.duplicate(true)
		var key: String = str(state.calibration_id) + ":" + field + ":" + str(reference.resource_sha256)
		_checkpoint_resources[key] = reference.duplicate(true)
	return true


func clear_calibration_state() -> bool:
	last_error = ""
	var saved: Dictionary = _calibration_document()
	if not saved.ok:
		return _fail(saved.error)
	if saved.payload == null:
		return true
	if not _write_document("profile.json", "profile", saved.payload.baseline_profile):
		return false
	return _write_document("calibration_state.json", "calibration_state", null)


func _calibration_document() -> Dictionary:
	var saved: Dictionary = _read_document(root_path.path_join("calibration_state.json"), "calibration_state", true)
	if saved.ok and saved.missing:
		saved.payload = null
	return saved


static func _encode_profile(profile: Dictionary) -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result.erase("gain_deg_per_relative_unit")
	return result


static func _decode_profile(profile: Dictionary) -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result["gain_deg_per_relative_unit"] = Canonical.float64_from_hex(str(result.get("gain_hex", "")))
	return result


func _import_legacy_profile(legacy: Dictionary) -> Dictionary:
	var profile: Dictionary = default_profile()
	for field in ["dpi", "cm_per_360", "invert_y", "max_fps", "goal", "weapon_id", "show_weapon", "sound_enabled", "sound_volume", "reduced_motion", "crosshair_style", "crosshair_size_px", "crosshair_thickness_px", "crosshair_gap_px", "crosshair_color", "crosshair_outline", "reference_game"]:
		if legacy.has(field):
			profile[field] = legacy[field]
	profile.gain_deg_per_relative_unit = 914.4 / (float(profile.dpi) * float(profile.cm_per_360))
	profile.gain_hex = Canonical.float64_hex(profile.gain_deg_per_relative_unit)
	if not _profile_valid(profile):
		last_error = "LEGACY_PROFILE_IMPORT_INVALID"
		return {}
	return profile


static func _profile_valid(profile: Dictionary) -> bool:
	if not _closed(profile, PROFILE_FIELDS, PROFILE_FIELDS) or profile.schema_version != PROFILE_SCHEMA:
		return false
	if not _hex(profile.gain_hex, 16) or not _number(profile.gain_deg_per_relative_unit) or float(profile.gain_deg_per_relative_unit) <= 0.0:
		return false
	if Canonical.float64_hex(float(profile.gain_deg_per_relative_unit)) != profile.gain_hex:
		return false
	if not profile.dpi_source in ["declared", "physical_measurement", "unknown"]:
		return false
	if profile.dpi_source == "unknown":
		if profile.dpi != null or profile.cm_per_360 != null:
			return false
	else:
		if not _integer(profile.dpi, 1, 64000) or not _range(profile.cm_per_360, 0.000001, 100000.0):
			return false
		var expected_cm: float = 914.4 / (float(profile.dpi) * float(profile.gain_deg_per_relative_unit))
		if absf(float(profile.cm_per_360) - expected_cm) > 1.0e-12 * maxf(1.0, expected_cm):
			return false
	if not _range(profile.vertical_fov_deg, 40.0, 110.0) or profile.accumulated_input != false or not profile.accumulated_input is bool:
		return false
	if not _integer(profile.max_fps, 0, 1000) or not profile.goal in ["balanced", "precision", "tracking"]:
		return false
	for field in ["invert_y", "crosshair_outline", "show_weapon", "sound_enabled", "reduced_motion"]:
		if not profile[field] is bool:
			return false
	if not profile.weapon_id in ["pulse", "vector", "classic"] or not _range(profile.sound_volume, 0.0, 100.0):
		return false
	if profile.look_profile_id != "reference_gl_v2" or not profile.target_color in ["#42D9CB", "#FFB454"]:
		return false
	if not Crosshair.validate(profile).is_empty():
		return false
	if profile.reference_game != null:
		var fields: Array[String] = ["game_id", "title", "dpi", "sensitivity", "yaw_deg", "source_cm_per_360", "confidence"]
		if not _closed(profile.reference_game, fields, fields) or not GameProfiles.validate_reference(profile.reference_game).is_empty():
			return false
	return true


static func _report_valid(report: Dictionary) -> bool:
	if not _json_value(report) or not _identifier(report.get("session_id")):
		return false
	var schema: Variant = report.get("schema_version")
	if not (_integer(schema, 2, MAX_SAFE_INTEGER) or (schema is String and schema.begins_with("aimlocal.") and ".v2" in schema)):
		return false
	for field in ["catalogue_revision", "score_version"]:
		if not _version(report.get(field)):
			return false
	for field in VERSION_FIELDS:
		if report.has(field) and not _version(report[field]):
			return false
	return true


static func _state_valid(state: Dictionary) -> bool:
	if not _closed(state, STATE_FIELDS, STATE_FIELDS) or state.schema_version != CALIBRATION_SCHEMA:
		return false
	if not _identifier(state.calibration_id) or state.protocol_id != "sustained_blocks_v2" or not _version(state.protocol_revision):
		return false
	if not _hex(state.plan_sha256, 64) or not state.day_role in ["express", "day1", "day2"] or not _integer(state.epoch, 0, MAX_SAFE_INTEGER):
		return false
	if not state.status in ["pending", "active", "interrupted", "complete"] or not state.checkpoint is Dictionary:
		return false
	if not state.baseline_profile is Dictionary or state.baseline_profile.has("gain_deg_per_relative_unit") or not _profile_valid(_decode_profile(state.baseline_profile)):
		return false
	if state.temporary_gain_hex != null:
		if not _hex(state.temporary_gain_hex, 16) or not is_finite(Canonical.float64_from_hex(state.temporary_gain_hex)) or Canonical.float64_from_hex(state.temporary_gain_hex) <= 0.0:
			return false
	if not state.report_ids is Array:
		return false
	var seen: Dictionary = {}
	for report_id in state.report_ids:
		if not _identifier(report_id) or seen.has(report_id):
			return false
		seen[report_id] = true
	return true


func _report_links_valid(report_ids: Array) -> bool:
	for report_id in report_ids:
		var path: String = root_path.path_join("reports").path_join(str(report_id) + ".json")
		if _verified_report_links.has(path):
			var proof: Dictionary = _verified_report_links[path]
			if proof.session_id == report_id and _file_byte_sha256(path) == proof.content_sha256:
				continue
			_verified_report_links.erase(path)
			_verified_link_order.erase(path)
		var saved: Dictionary = _read_document(path, "report")
		if not saved.ok or saved.missing or not saved.payload is Dictionary or saved.payload.session_id != report_id:
			return false
	return true


static func _payload_valid(kind: String, payload: Variant) -> bool:
	match kind:
		"profile":
			return payload is Dictionary and not payload.has("gain_deg_per_relative_unit") and _profile_valid(_decode_profile(payload))
		"report":
			return payload is Dictionary and _report_valid(payload)
		"calibration_state":
			return payload == null or (payload is Dictionary and _state_valid(payload))
	return false


static func _versions(kind: String, payload: Variant) -> Dictionary:
	var versions: Dictionary = {"store": DOCUMENT_SCHEMA, "hash_encoding": HASH_ENCODING}
	if payload is Dictionary:
		for field in VERSION_FIELDS:
			if payload.has(field):
				versions[field] = payload[field]
	if kind == "profile":
		versions["look_profile_id"] = payload.look_profile_id
	return versions


func _read_document(path: String, kind: String, use_backup: bool = false) -> Dictionary:
	var cached: Dictionary = _cached_document(path, kind)
	if not cached.is_empty():
		return cached
	var saved: Dictionary = _read_json(path)
	if saved.ok:
		var verified: Dictionary = _verify_document(saved.data, kind)
		if verified.ok:
			_remember_document(path, kind, int(saved.byte_count), str(saved.content_sha256), verified)
			return verified
	if use_backup:
		var backup: Dictionary = _read_json(path + ".bak")
		if backup.ok:
			var verified: Dictionary = _verify_document(backup.data, kind)
			if verified.ok:
				verified["recovered_from_backup"] = true
				return verified
		if not backup.missing:
			return {"ok": false, "missing": false, "error": "DOCUMENT_BACKUP_INVALID"}
	if saved.missing:
		return {"ok": true, "missing": true, "payload": null}
	return {"ok": false, "missing": false, "error": "DOCUMENT_INVALID"}


func _cached_document(path: String, kind: String) -> Dictionary:
	var key: String = kind + ":" + path
	if not _verified_cache.has(key):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		_forget_document(key)
		return {}
	var length: int = file.get_length()
	var contents: PackedByteArray = file.get_buffer(length)
	file.close()
	if contents.size() != length or _byte_sha256(contents) != _verified_cache[key].content_sha256:
		_forget_document(key)
		return {}
	_verified_order.erase(key)
	_verified_order.append(key)
	return _verified_cache[key].verified.duplicate(true)


func _remember_document(path: String, kind: String, length: int, digest: String, verified: Dictionary) -> void:
	if kind == "report":
		_verified_report_links[path] = {"session_id": verified.payload.session_id, "content_sha256": digest}
		_verified_link_order.erase(path)
		_verified_link_order.append(path)
		while _verified_link_order.size() > HISTORY_LIMIT:
			_verified_report_links.erase(_verified_link_order.pop_front())
	var key: String = kind + ":" + path
	_forget_document(key)
	if length > VERIFIED_CACHE_BYTES:
		return
	while not _verified_order.is_empty() and (_verified_bytes + length > VERIFIED_CACHE_BYTES or _verified_order.size() >= VERIFIED_CACHE_DOCUMENTS):
		_forget_document(_verified_order[0])
	_verified_cache[key] = {"content_sha256": digest, "byte_count": length, "verified": verified.duplicate(true)}
	_verified_order.append(key)
	_verified_bytes += length


func _forget_document(key: String) -> void:
	if _verified_cache.has(key):
		_verified_bytes -= int(_verified_cache[key].byte_count)
		_verified_cache.erase(key)
		_verified_order.erase(key)


static func _byte_sha256(contents: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(contents)
	return context.finish().hex_encode()


static func _file_byte_sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return ""
	var length: int = file.get_length()
	var contents: PackedByteArray = file.get_buffer(length)
	file.close()
	return _byte_sha256(contents) if contents.size() == length else ""


static func _verify_document(document: Variant, kind: String) -> Dictionary:
	var fields: Array[String] = ["schema_version", "kind", "hash_encoding", "number_encoding", "versions", "payload", "semantic_sha256"]
	var decoder := ExactNumbers.new()
	document = decoder.decode(document)
	if not decoder.error.is_empty() or not _closed(document, fields, fields) or document.schema_version != DOCUMENT_SCHEMA or document.kind != kind or document.hash_encoding != HASH_ENCODING or document.number_encoding != NUMBER_ENCODING:
		return {"ok": false}
	if not _payload_valid(kind, document.payload) or not _same(document.versions, _versions(kind, document.payload)) or not _hex(document.semantic_sha256, 64):
		return {"ok": false}
	var unsigned: Dictionary = document.duplicate(true)
	unsigned.erase("semantic_sha256")
	if Canonical.semantic_sha256(unsigned) != document.semantic_sha256:
		return {"ok": false}
	return {"ok": true, "missing": false, "payload": document.payload, "semantic_sha256": document.semantic_sha256}


func _write_document(relative_path: String, kind: String, payload: Variant, immutable: bool = false) -> bool:
	if not _payload_valid(kind, payload):
		return _fail("DOCUMENT_PAYLOAD_INVALID")
	var document: Dictionary = {"schema_version": DOCUMENT_SCHEMA, "kind": kind, "hash_encoding": HASH_ENCODING, "number_encoding": NUMBER_ENCODING, "versions": _versions(kind, payload), "payload": payload}
	document["semantic_sha256"] = Canonical.semantic_sha256(document)
	var contents: PackedByteArray = JSON.stringify(ExactNumbers.encode(document), "\t", true, true).to_utf8_buffer()
	if contents.size() > MAX_FILE_BYTES:
		return _fail("DOCUMENT_TOO_LARGE")
	var parser := StrictJson.new()
	var parsed: Variant = parser.parse(contents.get_string_from_utf8())
	var roundtrip: Dictionary = _verify_document(parsed, kind)
	if not roundtrip.ok or not parser.error.is_empty():
		return _fail("DOCUMENT_ROUNDTRIP_INVALID")
	var path: String = root_path.path_join(relative_path)
	var absolute: String = ProjectSettings.globalize_path(path)
	if root_path.is_empty() or root_path in ["/", "user://", "res://"] or DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return _fail("STORE_DIRECTORY_UNAVAILABLE")
	var lock_path: String = absolute + ".lock"
	if DirAccess.make_dir_absolute(lock_path) != OK:
		return _fail("DOCUMENT_LOCKED")
	var success: bool = _publish_locked(path, absolute, kind, document, contents, immutable)
	if DirAccess.remove_absolute(lock_path) != OK:
		return _fail("DOCUMENT_LOCK_RELEASE_FAILED")
	if success:
		_remember_document(path, kind, contents.size(), _byte_sha256(contents), roundtrip)
	return success


func _publish_locked(path: String, absolute: String, kind: String, document: Dictionary, contents: PackedByteArray, immutable: bool) -> bool:
	var exists: bool = FileAccess.file_exists(path)
	if exists:
		var current: Dictionary = _read_document(path, kind)
		if not current.ok:
			return _fail("EXISTING_DOCUMENT_INVALID")
		if current.semantic_sha256 == document.semantic_sha256:
			return true
		if immutable:
			return _fail("REPORT_ID_CONFLICT")
		if not _publish_bytes(absolute + ".bak", FileAccess.get_file_as_bytes(path)):
			return false
	return _publish_bytes(absolute, contents)


func _publish_bytes(destination: String, contents: PackedByteArray) -> bool:
	var temporary: String = destination + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("TEMPORARY_OPEN_FAILED")
	file.store_buffer(contents)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_bytes(temporary) != contents:
		DirAccess.remove_absolute(temporary)
		return _fail("TEMPORARY_WRITE_FAILED")
	if _rename_file(temporary, destination) != OK:
		DirAccess.remove_absolute(temporary)
		return _fail("ATOMIC_RENAME_FAILED")
	return true


func _rename_file(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": not DirAccess.dir_exists_absolute(path), "error": "JSON_FILE_MISSING"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {"ok": false, "missing": false, "error": "JSON_FILE_UNAVAILABLE"}
	var contents: PackedByteArray = file.get_buffer(file.get_length())
	var expected_length: int = file.get_length()
	file.close()
	if contents.size() != expected_length or not _utf8_valid(contents):
		return {"ok": false, "missing": false, "error": "JSON_INVALID_BYTES"}
	var text: String = contents.get_string_from_utf8()
	if text.to_utf8_buffer() != contents:
		return {"ok": false, "missing": false, "error": "JSON_INVALID_UTF8"}
	var parser := StrictJson.new()
	var data: Variant = parser.parse(text)
	return {"ok": parser.error.is_empty(), "missing": false, "data": data, "error": parser.error,
		"byte_count": contents.size(), "content_sha256": _byte_sha256(contents)}


static func _utf8_valid(bytes: PackedByteArray) -> bool:
	var index: int = 0
	while index < bytes.size():
		var first: int = bytes[index]
		var width: int = 1
		if first >= 194 and first <= 223:
			width = 2
		elif first >= 224 and first <= 239:
			width = 3
		elif first >= 240 and first <= 244:
			width = 4
		elif first > 127:
			return false
		if index + width > bytes.size():
			return false
		for offset in range(1, width):
			if bytes[index + offset] < 128 or bytes[index + offset] > 191:
				return false
		if width >= 3:
			var second: int = bytes[index + 1]
			if (first == 224 and second < 160) or (first == 237 and second >= 160) or (first == 240 and second < 144) or (first == 244 and second >= 144):
				return false
		index += width
	return true


static func _json_files(path: String) -> PackedStringArray:
	var directory := DirAccess.open(path)
	if directory == null:
		return PackedStringArray()
	var result := PackedStringArray()
	var filenames: PackedStringArray = directory.get_files()
	filenames.sort()
	for filename in filenames:
		if filename.ends_with(".json"):
			result.append(filename)
	return result.slice(maxi(0, result.size() - HISTORY_LIMIT))


static func _closed(value: Variant, allowed: Array[String], required: Array[String]) -> bool:
	if not value is Dictionary or not _json_value(value):
		return false
	for key in value:
		if not key in allowed:
			return false
	for key in required:
		if not value.has(key):
			return false
	return true


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_STRING:
			for index in value.length():
				var codepoint: int = value.unicode_at(index)
				if codepoint >= 55296 and codepoint <= 57343:
					return false
			return true
		TYPE_INT, TYPE_FLOAT:
			return _number(value) and absf(float(value)) <= MAX_SAFE_INTEGER
		TYPE_ARRAY:
			for element in value:
				if not _json_value(element, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not _json_value(key, depth + 1) or not _json_value(value[key], depth + 1):
					return false
			return true
	return false


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _range(value, minimum, maximum) and float(value) == floor(float(value))


static func _version(value: Variant) -> bool:
	return (value is String and not value.strip_edges().is_empty() and value.length() <= 128) or _integer(value, 1, MAX_SAFE_INTEGER)


static func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 96 or value.begins_with("."):
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":
			return false
	return true


static func _hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _same(first: Variant, second: Variant) -> bool:
	var hash: String = Canonical.semantic_sha256(first)
	return not hash.is_empty() and hash == Canonical.semantic_sha256(second)


func _fail(code: String) -> bool:
	last_error = code
	return false
