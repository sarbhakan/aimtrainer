class_name V2Progress
extends RefCounted

const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const Catalog := preload("res://scripts/v2/v2_catalog.gd")
const Scores := preload("res://scripts/v2/v2_scores.gd")
const Session := preload("res://scripts/v2/v2_session_engine.gd")
const Store := preload("res://scripts/v2/v2_store.gd")
const Crosshair := preload("res://scripts/presentation/crosshair_profile.gd")
const MAX_SAFE_INTEGER: int = 9007199254740991
const REPORT_FIELDS: Array[String] = [
	"schema_version", "runtime_version", "catalogue_revision", "input_convention", "session_seed_hex",
	"program_id", "difficulty", "title", "duration_s", "elapsed_s", "complete", "valid", "invalid_reason",
	"conditions", "definition_hash", "phases", "program_score", "display_score", "rank_key", "manifest",
	"target_outcomes", "received_pose_trace", "render_quality", "manifest_hash", "pauses", "rank_eligible",
	"pose_event_count", "trace_retention"
]
const REPORT_METADATA: Array[String] = ["session_id", "app_version", "score_version", "engine_version", "started_utc", "ended_utc", "initial_pose_yaw_pitch_deg"]
const CONDITION_FIELDS: Array[String] = [
	"declared_dpi", "dpi_source", "gain_hex", "fov_horizontal_deg_at_16_9", "vertical_fov_deg", "aspect_ratio",
	"render_resolution_px", "render_scale", "renderer", "rendering_driver", "os", "engine_version",
	"frame_limit_hz", "display_hz_declared", "display_hz_source", "vsync", "input_convention",
	"input_accumulation", "invert_y", "crosshair", "target_palette", "audio", "look_profile_id",
	"show_weapon", "reduced_motion", "seeded_scored_stimulus_preview", "candidate_value_masking", "retain_input_trace"
]
const OPTIONAL_CONDITION_FIELDS: Array[String] = ["player_utc_offset_minutes"]
const PHASE_FIELDS: Array[String] = [
	"phase_id", "title", "start_s", "duration_s", "elapsed_s", "complete", "valid", "score_id", "score",
	"display_score", "metrics", "contact_intervals_s", "rank_key"
]
const COUNT_METRICS: Array[String] = ["hits", "shots", "misses", "expired", "censored", "opportunities", "kills", "integration_g_evaluations"]
const VALUE_METRICS: Array[String] = ["contact_s", "contact_lower_s", "contact_upper_s", "exposure_s", "useful_damage", "credited_work"]
const NULLABLE_METRICS: Array[String] = [
	"accuracy", "acquisition_p50_ms", "acquisition_p90_ms", "switch_latency_p50_ms", "switch_latency_p90_ms",
	"angular_error_mean_deg", "angular_error_p90_deg"
]
const REACTIVE_METRICS: Array[String] = [
	"reversal_observations", "post_reversal_contact_fraction_250_ms", "stable_reacquisition_p50_ms",
	"stable_reacquisition_p90_ms", "long_losses_over_200_ms", "diagnostic_contact_fragments_merged_20_ms",
	"stable_contact_uses_certified_inside_intervals"
]
const DEFINITION_HASHES: Dictionary = {
	"EX01": {
		"novice": "32d306a4f368c35c9810f784fc1af434f44ef0fdf0da1d611b9f133b27ccb87b",
		"standard": "56629cbad56e2a63c7eea4b506a5418bae4a450819cb010a5ea23cbe4e34a66a",
		"advanced": "95b2bba15131ea339a87e7943d15a0d2ae19ed7756e1289ca2ff83874ae66502"
	},
	"EX02": {
		"novice": "042e6b10e3ab34f2a1318bd2341d4563e0fb2a9a52e6008df20342170f920867",
		"standard": "94000fb5963a21ff057d48cae902f89b236d149dc1a32f95ee28222a4717bb19",
		"advanced": "a695d4266ca86ab862bedb38cd13f3c0f46ed748cee8d8e748c0ed65a4ffe566"
	},
	"EX03": {
		"novice": "77a12b9b1588104d7670754f8026861bd8deb1cfec579c6f6a05bfc09818a79b",
		"standard": "7be30bd45f39a4d0504672129716e190f23def10cf4c4c00ef379be7e3df2ea7",
		"advanced": "cbed486f183460f09e07f4280dcdc919145da194918c43562319e32c24b7661c"
	},
	"EX04": {
		"novice": "ae9fbdebb9515999b313b0d1c8fdc36b487d44292a7fd7e66d60f0660cb36b75",
		"standard": "d8e837fdc38c08c6ba01264dfa529d4495ce970e8772ff8239ebfe0a421f498b",
		"advanced": "9e16421aa25867d00b5dfbbcdda9687298d4e43a62c2f6744fcd069fc99a38aa"
	},
	"EX05": {
		"novice": "42b5dba3d963478e6627a577fbe08d798fbcf4c2a43bee302241becd78ff0796",
		"standard": "b4b94d1cdb69077b5212659fddc73d850ec73a33ac8ddebd73fe7845b4c4ad06",
		"advanced": "1d035030de76ef291c78a562f418656f54b52174bec2f855f92cf5248402663b"
	},
	"EX06": {
		"novice": "a5fee2b9b4e0d1eb2d2eff5d3dc9171454cc8656fa0fe05c460a19b6afce886f",
		"standard": "b02c6886d71413a59710074fd1817e8f1986dea8e4526f182b60a16ba9c058b1",
		"advanced": "6a40356bfbbe18d2484d6656e8d3914cb3102f950c15e233f548a486c3471db4"
	},
	"EX07": {
		"novice": "fdfc9acaf4203d783d0a9071149e1c15a78d4935aa35df4b0c326f0d1f7228e3",
		"standard": "c27f467f8028cb1c5a4a2841b8f89aaddee87e279bfae4611a023c5d034e4d2d",
		"advanced": "545467a1652064391761875f8470761b9c3d1def090e45171218ca3b85a96961"
	},
	"EX08": {
		"novice": "bc3a6d10de000b0f04c1562bbbef63f5d1ef1bd7f39c9fffacf65cd4531aaf55",
		"standard": "449fe0d4d6734fa20a334ddd94ab99e6a075ebd05f4ca8444e721364ea37b182",
		"advanced": "6d86d02cd7e5609f0def24f67f99f1df3899f7cd6225e771ef8514420cc174f4"
	}
}


static func validate_report(report: Variant) -> Dictionary:
	if not _json_value(report) or not _closed(report, REPORT_FIELDS + REPORT_METADATA, REPORT_FIELDS):
		return _failure("REPORT_FIELDS")
	if report.schema_version != "aimlocal.report.v2.0" or report.runtime_version != Session.RUNTIME_VERSION or report.catalogue_revision != Catalog.REVISION or report.input_convention != Session.INPUT_CONVENTION:
		return _failure("REPORT_VERSION")
	if not report.program_id is String or not DEFINITION_HASHES.has(report.program_id) or not report.difficulty is String or not DEFINITION_HASHES[report.program_id].has(report.difficulty):
		return _failure("PUBLIC_PROGRAM_REQUIRED")
	if not _text(report.title) or not _hex(report.session_seed_hex, 32) or report.definition_hash != DEFINITION_HASHES[report.program_id][report.difficulty]:
		return _failure("REPORT_DEFINITION")
	if not _true(report.complete) or not _true(report.valid) or not _true(report.rank_eligible) or report.invalid_reason != "" or not report.pauses is Array or not report.pauses.is_empty():
		return _failure("REPORT_NOT_ELIGIBLE")
	if not _equal_number(report.duration_s, 60.0) or not _equal_number(report.elapsed_s, 60.0):
		return _failure("REPORT_INCOMPLETE")
	if not _conditions_valid(report.conditions) or not _quality_valid(report.render_quality):
		return _failure("REPORT_CONDITIONS_OR_QUALITY")
	if not _metadata_valid(report):
		return _failure("REPORT_METADATA")
	if report.has("initial_pose_yaw_pitch_deg"):
		var initial_pose: Variant = report.initial_pose_yaw_pitch_deg
		if not initial_pose is Array or initial_pose.size() != 2 or not _number(initial_pose[0]) or not _range(initial_pose[1], -89.0, 89.0):
			return _failure("REPORT_INITIAL_POSE")
	var definition: Dictionary = _score_definition(report.program_id, report.difficulty)
	if not report.phases is Array or report.phases.size() != definition.phases.size() or report.rank_key != _rank_key(report.conditions, definition):
		return _failure("REPORT_PHASES_OR_CONTEXT")
	for phase_index: int in definition.phases.size():
		if not _phase_valid(report.phases[phase_index], definition.phases[phase_index], definition, report.conditions):
			return _failure("REPORT_PHASE_%d" % phase_index)
	var expected_score: Variant = Scores.program_score(definition, report.phases, true, true)
	if not _score_equal(report.program_score, expected_score) or not _score_equal(report.display_score, Scores.displayed_score(expected_score)):
		return _failure("REPORT_PROGRAM_SCORE")
	if not report.manifest is Array or report.manifest.is_empty() or not report.target_outcomes is Array or not report.received_pose_trace is Array or not _integer(report.pose_event_count):
		return _failure("REPORT_TRACE")
	if not _hex(report.manifest_hash, 64) or report.manifest_hash != Canonical.semantic_sha256(report.manifest):
		return _failure("REPORT_MANIFEST_HASH")
	var retains_trace: bool = report.conditions.retain_input_trace
	if report.trace_retention != ("full_received_pose_trace" if retains_trace else "light_no_exact_input_replay") or report.received_pose_trace.size() != (int(report.pose_event_count) if retains_trace else 0):
		return _failure("REPORT_TRACE_RETENTION")
	return {"ok": true, "error": ""}


static func summarize(history_rows: Array) -> Array:
	var saved: Dictionary = {}
	var conflicts: Dictionary = {}
	for row: Variant in history_rows:
		if not _saved_row_valid(row):
			continue
		var identity: String = row.report.session_id
		if saved.has(identity) and saved[identity].semantic_sha256 != row.semantic_sha256:
			conflicts[identity] = true
		elif not saved.has(identity):
			saved[identity] = row
	var ordered: Array = []
	for identity: String in saved:
		if not conflicts.has(identity):
			ordered.append(saved[identity].report)
	ordered.sort_custom(_earlier_report)
	var groups: Dictionary = {}
	var group_order: Array[String] = []
	for report: Dictionary in ordered:
		for phase: Dictionary in report.phases:
			_add_score(groups, group_order, report, phase.phase_id, phase.score_id, phase.rank_key, float(phase.score))
		if report.program_score != null:
			_add_score(groups, group_order, report, "", report.phases[0].score_id, report.rank_key, float(report.program_score))
	var result: Array = []
	for group_id: String in group_order:
		var group: Dictionary = groups[group_id]
		var scores: Array = group._scores
		if scores.size() >= 10:
			var first_five: float = float(Scores.percentile(scores.slice(0, 5), 0.5))
			var last_five: float = float(Scores.percentile(scores.slice(scores.size() - 5), 0.5))
			var delta_points: float = last_five - first_five
			var delta_percent: Variant = delta_points / first_five * 100.0 if first_five > 0.0 else null
			group.merge({"first_five_median": first_five, "last_five_median": last_five, "delta_points": delta_points,
				"delta_percent": delta_percent if delta_percent == null or is_finite(float(delta_percent)) else null})
		group.erase("_scores")
		result.append(group)
	return result


static func _score_definition(program_id: String, difficulty: String) -> Dictionary:
	var phases: Array = []
	var start_s: float = 0.0
	for layout: Array in Catalog.PHASE_LAYOUT[program_id]:
		phases.append({"id": layout[0], "start_s": start_s, "duration_s": float(layout[1]), "target_count": layout[4],
			"scoring": {"id": Catalog.SCORE_IDS[layout[2]]}, "spawn": {"schedule": {"slots": 10}}})
		start_s += float(layout[1])
	var aggregate: String = "descriptive_only" if program_id in ["EX01", "EX02", "EX03", "EX04"] else ("sum_credited_switch_work_per_program_time" if program_id == "EX08" else "time_weighted_contact")
	return {"program_id": program_id, "difficulty": difficulty, "definition_hash": DEFINITION_HASHES[program_id][difficulty],
		"duration_s": 60.0, "phases": phases, "aggregate": {"kind": aggregate, "ranked_program_score": aggregate != "descriptive_only"}}


static func _rank_key(conditions: Dictionary, definition: Dictionary, phase_id: String = "") -> String:
	return Canonical.semantic_sha256({"runtime": Session.RUNTIME_VERSION, "definition_hash": definition.definition_hash,
		"program_id": definition.program_id, "difficulty": definition.difficulty, "phase_id": phase_id, "conditions": conditions})


static func _phase_valid(phase: Variant, definition: Dictionary, program: Dictionary, conditions: Dictionary) -> bool:
	if not _closed(phase, PHASE_FIELDS, PHASE_FIELDS) or phase.phase_id != definition.id or phase.score_id != definition.scoring.id or not _text(phase.title) or not _true(phase.complete) or not _true(phase.valid):
		return false
	if not _equal_number(phase.start_s, definition.start_s) or not _equal_number(phase.duration_s, definition.duration_s) or not _equal_number(phase.elapsed_s, definition.duration_s):
		return false
	if phase.rank_key != _rank_key(conditions, program, definition.id) or not _metrics_valid(phase.metrics, definition):
		return false
	var expected_score: Variant = Scores.phase_score(definition, phase.metrics, true, true)
	if not _score_equal(phase.score, expected_score) or not _score_equal(phase.display_score, Scores.displayed_score(expected_score)):
		return false
	return _intervals_valid(phase.contact_intervals_s, float(definition.start_s), float(definition.start_s) + float(definition.duration_s))


static func _metrics_valid(metrics: Variant, phase: Dictionary) -> bool:
	var required: Array[String] = COUNT_METRICS + VALUE_METRICS + NULLABLE_METRICS
	var reactive: bool = phase.id == "reactive"
	if reactive:
		required.append_array(REACTIVE_METRICS)
	if not _closed(metrics, required, required):
		return false
	for field: String in COUNT_METRICS:
		if not _integer(metrics[field]):
			return false
	for field: String in VALUE_METRICS:
		if not _nonnegative(metrics[field]):
			return false
	for field: String in NULLABLE_METRICS:
		if metrics[field] != null and not _nonnegative(metrics[field]):
			return false
	if metrics.hits > metrics.shots or metrics.misses != metrics.shots - metrics.hits or not _score_equal(metrics.accuracy, Scores.accuracy(metrics)):
		return false
	var duration_s: float = phase.duration_s
	if not _equal_number(metrics.exposure_s, duration_s) or metrics.contact_lower_s > metrics.contact_s or metrics.contact_s > metrics.contact_upper_s or metrics.contact_upper_s > duration_s + 1.0e-9:
		return false
	if metrics.contact_upper_s - metrics.contact_lower_s > duration_s * 0.0005 + 1.0e-9:
		return false
	if phase.scoring.id == Scores.OPPORTUNITY_ID:
		if not _equal_number(metrics.opportunities, 10.0) or metrics.hits + metrics.expired + metrics.censored > 10:
			return false
	elif metrics.opportunities != 0:
		return false
	if phase.scoring.id == Scores.SWITCH_ID:
		if metrics.credited_work < metrics.kills or metrics.credited_work > metrics.kills + int(phase.target_count):
			return false
	elif metrics.kills != 0 or metrics.credited_work != 0.0 or metrics.useful_damage != 0.0:
		return false
	if phase.scoring.id in [Scores.CONTACT_ID, Scores.SWITCH_ID] and (metrics.hits != 0 or metrics.shots != 0 or metrics.expired != 0):
		return false
	if not reactive:
		return true
	if not _true(metrics.stable_contact_uses_certified_inside_intervals) or not _integer(metrics.long_losses_over_200_ms) or not _integer(metrics.diagnostic_contact_fragments_merged_20_ms) or not metrics.reversal_observations is Array:
		return false
	for field: String in ["post_reversal_contact_fraction_250_ms", "stable_reacquisition_p50_ms", "stable_reacquisition_p90_ms"]:
		if metrics[field] != null and not _nonnegative(metrics[field]):
			return false
	if metrics.post_reversal_contact_fraction_250_ms != null and metrics.post_reversal_contact_fraction_250_ms > 1.0 + 1.0e-9:
		return false
	var fields: Array[String] = ["reversal_s", "window_end_s", "censored_at_next_reversal", "contact_s", "exposure_s", "stable_reacquisition_ms"]
	for observation: Variant in metrics.reversal_observations:
		if not _closed(observation, fields, fields) or not observation.censored_at_next_reversal is bool:
			return false
		for field: String in ["reversal_s", "window_end_s", "contact_s", "exposure_s"]:
			if not _nonnegative(observation[field]):
				return false
		if observation.reversal_s < phase.start_s or observation.window_end_s > phase.start_s + duration_s or observation.window_end_s < observation.reversal_s or observation.contact_s > observation.exposure_s + 1.0e-9:
			return false
		if observation.stable_reacquisition_ms != null and not _nonnegative(observation.stable_reacquisition_ms):
			return false
	return true


static func _conditions_valid(conditions: Variant) -> bool:
	if not _closed(conditions, CONDITION_FIELDS + OPTIONAL_CONDITION_FIELDS, CONDITION_FIELDS):
		return false
	if conditions.has("player_utc_offset_minutes") and not _integer(conditions.player_utc_offset_minutes, -1440, 1440):
		return false
	if not conditions.dpi_source in ["declared", "physical_measurement", "unknown"] or not _hex(conditions.gain_hex, 16) or not _range(conditions.vertical_fov_deg, 40.0, 110.0):
		return false
	if conditions.dpi_source == "unknown":
		if conditions.declared_dpi != null:
			return false
	elif not _integer(conditions.declared_dpi, 1, 64000):
		return false
	var gain: float = Canonical.float64_from_hex(conditions.gain_hex)
	if not _nonnegative(gain) or gain <= 0.0:
		return false
	if not conditions.render_resolution_px is Array or conditions.render_resolution_px.size() != 2:
		return false
	for dimension: Variant in conditions.render_resolution_px:
		if not _integer(dimension, 1, 65536):
			return false
	var aspect_ratio: float = float(conditions.render_resolution_px[0]) / float(conditions.render_resolution_px[1])
	var horizontal_deg: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(float(conditions.vertical_fov_deg) * 0.5)) * 16.0 / 9.0))
	if not _close_number(conditions.aspect_ratio, aspect_ratio) or not _close_number(conditions.fov_horizontal_deg_at_16_9, horizontal_deg) or not _equal_number(conditions.render_scale, 1.0):
		return false
	if not conditions.renderer in ["gl_compatibility", "mobile", "forward_plus"] or not conditions.rendering_driver in ["opengl3", "vulkan", "d3d12", "metal"] or not conditions.os in ["Windows", "macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "Android", "iOS", "Web"] or not _text(conditions.engine_version):
		return false
	if (conditions.renderer == "gl_compatibility") != (conditions.rendering_driver == "opengl3"):
		return false
	if not _integer(conditions.frame_limit_hz, 0, 1000) or not (conditions.display_hz_declared == -1 and _number(conditions.display_hz_declared) or _range(conditions.display_hz_declared, 1.0, 1000.0)) or conditions.display_hz_source != "display_server_reported_not_physical_scanout":
		return false
	for field: String in ["vsync", "invert_y", "show_weapon", "reduced_motion", "retain_input_trace"]:
		if not conditions[field] is bool:
			return false
	if conditions.input_convention != Session.INPUT_CONVENTION or not _false(conditions.input_accumulation) or not _false(conditions.seeded_scored_stimulus_preview) or not _false(conditions.candidate_value_masking) or conditions.look_profile_id != "reference_gl_v2":
		return false
	var crosshair_fields: Array[String] = ["crosshair_style", "crosshair_size_px", "crosshair_thickness_px", "crosshair_gap_px", "crosshair_color", "crosshair_outline"]
	if not _closed(conditions.crosshair, crosshair_fields, crosshair_fields) or not Crosshair.validate(conditions.crosshair).is_empty():
		return false
	if not _closed(conditions.target_palette, ["active", "amber"], ["active", "amber"]):
		return false
	for color: Variant in conditions.target_palette.values():
		if not color is String or not Color.html_is_valid(color):
			return false
	return _closed(conditions.audio, ["enabled", "volume_percent", "weapon_id"], ["enabled", "volume_percent", "weapon_id"]) and conditions.audio.enabled is bool and _range(conditions.audio.volume_percent, 0.0, 100.0) and conditions.audio.weapon_id in ["pulse", "vector", "classic"]


static func _quality_valid(quality: Variant) -> bool:
	var fields: Array[String] = ["valid", "reason", "mean_fps", "median_fps", "p99_ms", "max_ms", "frame_count"]
	if not _closed(quality, fields, fields) or not _true(quality.valid) or quality.reason != "" or not _integer(quality.frame_count, 1):
		return false
	for field: String in ["mean_fps", "median_fps", "p99_ms", "max_ms"]:
		if not _nonnegative(quality[field]) or quality[field] <= 0.0:
			return false
	return quality.mean_fps >= 55.0 and quality.p99_ms <= 25.0 and quality.max_ms <= 100.0 and quality.p99_ms <= quality.max_ms and 1000.0 / float(quality.median_fps) <= quality.p99_ms + 1.0e-9 and 1000.0 / float(quality.mean_fps) <= quality.max_ms + 1.0e-9


static func _saved_row_valid(row: Variant) -> bool:
	if not row is Dictionary:
		return false
	for key: Variant in row:
		if not key is String:
			return false
	if not row.get("namespace") is String or row.get("namespace") != "v2" or not _true(row.get("read_only")) or not row.get("kind") is String or row.get("kind") != "session" or not _hex(row.get("semantic_sha256"), 64) or not validate_report(row.get("report")).ok:
		return false
	var report: Dictionary = row.report
	if not _identifier(report.get("session_id")) or report.get("score_version") != "scores_v2.0" or not report.has("started_utc") or not report.has("ended_utc"):
		return false
	var versions: Dictionary = {"store": Store.DOCUMENT_SCHEMA, "hash_encoding": Store.HASH_ENCODING}
	for field: String in Store.VERSION_FIELDS:
		if report.has(field):
			versions[field] = report[field]
	var document: Dictionary = {"schema_version": Store.DOCUMENT_SCHEMA, "kind": "report", "hash_encoding": Store.HASH_ENCODING,
		"number_encoding": Store.NUMBER_ENCODING, "versions": versions, "payload": report}
	return row.semantic_sha256 == Canonical.semantic_sha256(document)


static func _metadata_valid(report: Dictionary) -> bool:
	if report.has("session_id") and not _identifier(report.session_id):
		return false
	for field: String in ["app_version", "engine_version"]:
		if report.has(field) and (not _text(report[field]) or report[field].length() > 128):
			return false
	if report.has("score_version") and report.score_version != "scores_v2.0":
		return false
	if report.has("engine_version") and report.engine_version != report.conditions.engine_version:
		return false
	if report.has("started_utc") or report.has("ended_utc"):
		var start: String = _utc(report.get("started_utc"))
		var end: String = _utc(report.get("ended_utc"))
		if start.is_empty() or end.is_empty() or Time.get_unix_time_from_datetime_string(end) - Time.get_unix_time_from_datetime_string(start) < 60:
			return false
	return true


static func _earlier_report(first: Dictionary, second: Dictionary) -> bool:
	var first_start: String = _utc(first.started_utc)
	var second_start: String = _utc(second.started_utc)
	if first_start != second_start:
		return first_start < second_start
	var first_end: String = _utc(first.ended_utc)
	var second_end: String = _utc(second.ended_utc)
	return first_end < second_end if first_end != second_end else first.session_id < second.session_id


static func _add_score(groups: Dictionary, order: Array[String], report: Dictionary, phase_id: String, family: String, group_id: String, score: float) -> void:
	if not groups.has(group_id):
		groups[group_id] = {"group_id": group_id, "program_id": report.program_id, "difficulty": report.difficulty,
			"phase_id": phase_id, "score_family": family, "conditions": report.conditions.duplicate(true),
			"definition_hash": report.definition_hash, "context_count": 0, "best_score": score,
			"best_report_id": report.session_id, "_scores": []}
		order.append(group_id)
	var group: Dictionary = groups[group_id]
	group.context_count += 1
	group._scores.append(score)
	if score > float(group.best_score):
		group.best_score = score
		group.best_report_id = report.session_id


static func _utc(value: Variant) -> String:
	if not value is String or not (value.length() == 19 or value.length() == 20 and value.ends_with("Z")):
		return ""
	var stamp: String = value.substr(0, 19)
	if stamp[4] != "-" or stamp[7] != "-" or stamp[10] != "T" or stamp[13] != ":" or stamp[16] != ":":
		return ""
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]:
		if not stamp[index] in "0123456789":
			return ""
	var year: int = int(stamp.substr(0, 4))
	var month: int = int(stamp.substr(5, 2))
	var day: int = int(stamp.substr(8, 2))
	if year < 1970 or month < 1 or month > 12 or day < 1 or int(stamp.substr(11, 2)) > 23 or int(stamp.substr(14, 2)) > 59 or int(stamp.substr(17, 2)) > 59:
		return ""
	var month_days: Array[int] = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return stamp if day <= month_days[month - 1] else ""


static func _intervals_valid(intervals: Variant, start_s: float, end_s: float) -> bool:
	if not intervals is Array:
		return false
	var previous_end_s: float = start_s
	for interval: Variant in intervals:
		if not interval is Array or interval.size() != 2 or not _nonnegative(interval[0]) or not _nonnegative(interval[1]):
			return false
		if interval[0] < previous_end_s or interval[1] < interval[0] or interval[1] > end_s + 1.0e-9:
			return false
		previous_end_s = float(interval[1])
	return true


static func _closed(value: Variant, allowed: Array[String], required: Array[String]) -> bool:
	if not value is Dictionary:
		return false
	for field: Variant in value:
		if not field is String or not field in allowed:
			return false
	for field: String in required:
		if not value.has(field):
			return false
	return true


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_STRING:
			for index: int in value.length():
				if value.unicode_at(index) >= 55296 and value.unicode_at(index) <= 57343:
					return false
			return true
		TYPE_INT, TYPE_FLOAT:
			return _number(value)
		TYPE_ARRAY:
			for entry: Variant in value:
				if not _json_value(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _json_value(key, depth + 1) or not _json_value(value[key], depth + 1):
					return false
			return true
	return false


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= MAX_SAFE_INTEGER


static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0


static func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum


static func _integer(value: Variant, minimum: int = 0, maximum: int = MAX_SAFE_INTEGER) -> bool:
	return _range(value, minimum, maximum) and float(value) == floor(float(value))


static func _equal_number(value: Variant, expected: float) -> bool:
	return _nonnegative(value) and float(value) == expected


static func _close_number(value: Variant, expected: float) -> bool:
	return _nonnegative(value) and absf(float(value) - expected) <= 1.0e-12 * maxf(1.0, absf(expected))


static func _score_equal(value: Variant, expected: Variant) -> bool:
	return value == null if expected == null else _nonnegative(value) and _nonnegative(expected) and float(value) == float(expected)


static func _true(value: Variant) -> bool:
	return value is bool and value


static func _false(value: Variant) -> bool:
	return value is bool and not value


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 256


static func _identifier(value: Variant) -> bool:
	if not _text(value) or value.length() > 96 or value.begins_with("."):
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":
			return false
	return true


static func _hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
