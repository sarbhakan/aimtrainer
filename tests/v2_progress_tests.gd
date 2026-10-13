extends SceneTree

const Progress := preload("res://scripts/v2/v2_progress.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const Catalog := preload("res://scripts/v2/v2_catalog.gd")
const Scores := preload("res://scripts/v2/v2_scores.gd")
const Session := preload("res://scripts/v2/v2_session_engine.gd")
const Store := preload("res://scripts/v2/v2_store.gd")
const Crosshair := preload("res://scripts/presentation/crosshair_profile.gd")

var assertions: int = 0
var failures: int = 0
var fixture_sequence: int = 0
var fixture_roots: Array[String] = []
var catalogue: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("V2 PROGRESS: " + message)


func _definition(program_id: String, difficulty: String = "standard") -> Dictionary:
	for definition: Dictionary in catalogue.programs:
		if definition.program_id == program_id and definition.difficulty == difficulty:
			return definition
	return {}


func _synthetic_conditions() -> Dictionary:
	var vertical_deg: float = 70.53280043291679
	return {
		"declared_dpi": 800, "dpi_source": "declared", "gain_hex": Canonical.float64_hex(0.03265714285714286),
		"fov_horizontal_deg_at_16_9": rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical_deg * 0.5)) * 16.0 / 9.0)),
		"vertical_fov_deg": vertical_deg, "aspect_ratio": 16.0 / 9.0, "render_resolution_px": [1280, 720],
		"render_scale": 1.0, "renderer": "gl_compatibility", "rendering_driver": "opengl3", "os": "Linux",
		"engine_version": Engine.get_version_info().string, "frame_limit_hz": 144, "display_hz_declared": 144.0,
		"display_hz_source": "display_server_reported_not_physical_scanout", "vsync": false,
		"input_convention": Session.INPUT_CONVENTION, "input_accumulation": false, "invert_y": false,
		"crosshair": Crosshair.defaults(), "target_palette": {"active": "#42D9CB", "amber": "#FFB454"},
		"audio": {"enabled": false, "volume_percent": 70.0, "weapon_id": "pulse"},
		"look_profile_id": "reference_gl_v2", "show_weapon": true, "reduced_motion": false,
		"seeded_scored_stimulus_preview": false, "candidate_value_masking": false, "retain_input_trace": false
	}


func _synthetic_metrics(phase: Dictionary, contact_fraction: float) -> Dictionary:
	var family: String = phase.scoring.id
	var hits: int = 20 if family == Scores.CLICK_ID else (8 if family == Scores.OPPORTUNITY_ID else 0)
	var shots: int = 25 if family == Scores.CLICK_ID else (10 if family == Scores.OPPORTUNITY_ID else 0)
	var contact_s: float = float(phase.duration_s) * contact_fraction if family == Scores.CONTACT_ID else (0.6 if family == Scores.SWITCH_ID else 0.0)
	var result: Dictionary = {
		"hits": hits, "shots": shots, "misses": shots - hits, "expired": 2 if family == Scores.OPPORTUNITY_ID else 0,
		"censored": 0, "opportunities": 10 if family == Scores.OPPORTUNITY_ID else 0,
		"contact_s": contact_s, "contact_lower_s": contact_s, "contact_upper_s": contact_s,
		"exposure_s": phase.duration_s, "kills": 1 if family == Scores.SWITCH_ID else 0,
		"useful_damage": 60.0 if family == Scores.SWITCH_ID else 0.0,
		"credited_work": 1.5 if family == Scores.SWITCH_ID else 0.0,
		"accuracy": float(hits) / shots if shots > 0 else null,
		"acquisition_p50_ms": null, "acquisition_p90_ms": null, "switch_latency_p50_ms": null,
		"switch_latency_p90_ms": null, "angular_error_mean_deg": null, "angular_error_p90_deg": null,
		"integration_g_evaluations": 0
	}
	if phase.id == "reactive":
		result.merge({"reversal_observations": [], "post_reversal_contact_fraction_250_ms": null,
			"stable_reacquisition_p50_ms": null, "stable_reacquisition_p90_ms": null,
			"long_losses_over_200_ms": 0, "diagnostic_contact_fragments_merged_20_ms": 0,
			"stable_contact_uses_certified_inside_intervals": true})
	return result


func _synthetic_report(program_id: String = "EX06", difficulty: String = "standard", contact_fraction: float = 0.5) -> Dictionary:
	fixture_sequence += 1
	var definition: Dictionary = _definition(program_id, difficulty)
	var engine := Session.new()
	_check(engine.start(definition, "%032x" % fixture_sequence, _synthetic_conditions()), "Isolated synthetic fixture starts the pinned native definition")
	for frame_index: int in 120:
		engine.record_frame(1.0 / 144.0)
	engine.phases.clear()
	for phase: Dictionary in definition.phases:
		var metrics: Dictionary = _synthetic_metrics(phase, contact_fraction)
		var score: Variant = Scores.phase_score(phase, metrics)
		var intervals: Array = [[float(phase.start_s), float(phase.start_s) + float(metrics.contact_s)]] if metrics.contact_s > 0.0 else []
		engine.phases.append({"phase_id": phase.id, "title": phase.title, "start_s": phase.start_s,
			"duration_s": phase.duration_s, "elapsed_s": phase.duration_s, "complete": true, "valid": true,
			"score_id": phase.scoring.id, "score": score, "display_score": Scores.displayed_score(score),
			"metrics": metrics, "contact_intervals_s": intervals, "rank_key": Scores.context_key(engine.conditions, definition, phase.id)})
	engine.elapsed_s = float(definition.duration_s)
	engine.completed = true
	var report: Dictionary = engine.report()
	var start_unix_s: int = Time.get_unix_time_from_datetime_string("2026-10-12T08:00:00") + fixture_sequence * 120
	report.merge({"session_id": "isolated_synthetic_v2_progress_%04d" % fixture_sequence,
		"app_version": "1.0.0-isolated-synthetic-test", "engine_version": Engine.get_version_info().string,
		"score_version": "scores_v2.0", "started_utc": Time.get_datetime_string_from_unix_time(start_unix_s),
		"ended_utc": Time.get_datetime_string_from_unix_time(start_unix_s + 60)})
	return report


func _isolated_store() -> Store:
	var temporary: String = "/tmp/aimlocal-v2-progress-isolated-synthetic-" + Crypto.new().generate_random_bytes(12).hex_encode()
	fixture_roots.append(temporary)
	return Store.new(temporary.path_join("v2"))


func _saved_rows(reports: Array) -> Array:
	var store := _isolated_store()
	for report: Dictionary in reports:
		_check(store.save_report(report), "Isolated synthetic report uses the real immutable V2 store: " + store.last_error)
	var rows: Array = store.history()
	_check(rows.size() == reports.size(), "Isolated synthetic store returns every expected saved report")
	return rows


func _changed(report: Dictionary, path: Array, value: Variant) -> Dictionary:
	var result: Dictionary = report.duplicate(true)
	var current: Variant = result
	for path_index: int in range(path.size() - 1):
		current = current[path[path_index]]
	current[path[-1]] = value
	return result


func _rekey(report: Dictionary) -> void:
	var definition: Dictionary = _definition(report.program_id, report.difficulty)
	report["rank_key"] = Scores.context_key(report.conditions, definition)
	for phase: Dictionary in report.phases:
		phase["rank_key"] = Scores.context_key(report.conditions, definition, phase.phase_id)
	if report.has("engine_version"):
		report["engine_version"] = report.conditions.engine_version


func _group(groups: Array, program_id: String, phase_id: String, difficulty: String = "standard") -> Dictionary:
	for group: Dictionary in groups:
		if group.program_id == program_id and group.phase_id == phase_id and group.difficulty == difficulty:
			return group
	return {}


func _test_native_contracts() -> void:
	_check(catalogue.programs.size() == 24, "All 24 native public definitions are covered")
	for definition: Dictionary in catalogue.programs:
		var report: Dictionary = _synthetic_report(definition.program_id, definition.difficulty)
		_check(report.definition_hash == Progress.DEFINITION_HASHES[definition.program_id][definition.difficulty], "Pinned hash matches the complete native definition")
		_check(Progress.validate_report(report).ok, "Native output with explicitly synthetic metrics and frametimes validates for " + definition.program_id + "/" + definition.difficulty)
		for phase: Dictionary in report.phases:
			var expected: float = 800.0 if phase.score_id == Scores.CLICK_ID and phase.duration_s == 20 else (400.0 if phase.score_id == Scores.CLICK_ID else (640.0 if phase.score_id == Scores.OPPORTUNITY_ID else (500.0 if phase.score_id == Scores.CONTACT_ID else 75.0)))
			_check(absf(float(phase.score) - expected) < 1.0e-9, "Independent analytical phase score for " + definition.program_id + "/" + phase.phase_id)
		var aggregate: Variant = null if definition.program_id in ["EX01", "EX02", "EX03", "EX04"] else (75.0 if definition.program_id == "EX08" else 500.0)
		_check(report.program_score == aggregate, "Native aggregate policy and analytical score are preserved")
	var engine := Session.new()
	engine.start(_definition("EX01"), "0000000000000000000000000000002a", _synthetic_conditions())
	engine.record_frame(1.0 / 144.0)
	engine.advance(60.0)
	_check(Progress.validate_report(engine.report()).ok, "Unmodified native completion and zero scores validate with an explicitly synthetic frame sample")
	_check(Progress.summarize([engine.report()]).is_empty(), "Unsaved native output cannot establish a saved record")
	var no_frames := Session.new()
	no_frames.start(_definition("EX01"), "0000000000000000000000000000002a", _synthetic_conditions())
	no_frames.advance(60.0)
	_check(not no_frames.report().rank_eligible and not Progress.validate_report(no_frames.report()).ok, "A real renderer label without recorded frame quality never becomes eligible")
	var paused := Session.new()
	paused.start(_definition("EX01"), "0000000000000000000000000000002a", _synthetic_conditions())
	paused.record_frame(1.0 / 144.0)
	paused.note_pause(1.0)
	paused.advance(60.0)
	_check(not Progress.validate_report(paused.report()).ok, "Native paused completion is excluded")
	var abandoned := Session.new()
	abandoned.start(_definition("EX01"), "0000000000000000000000000000002a", _synthetic_conditions())
	abandoned.record_frame(1.0 / 144.0)
	abandoned.abandon()
	_check(not Progress.validate_report(abandoned.report()).ok, "Native abandoned report is excluded")


func _test_closed_validation() -> void:
	var base: Dictionary = _synthetic_report()
	var before: String = Canonical.semantic_sha256(base)
	var mutations: Array = [
		[["schema_version"], "aimlocal.session.v1.0"], [["runtime_version"], "aimlocal.runtime.v2.1"],
		[["catalogue_revision"], "different-v2"], [["input_convention"], "different-input"],
		[["program_id"], "CAL-CLICK"], [["program_id"], "warmup"], [["difficulty"], "easy"],
		[["definition_hash"], "a".repeat(64)], [["rank_key"], "a".repeat(64)], [["manifest_hash"], "a".repeat(64)],
		[["complete"], false], [["complete"], 1], [["valid"], false], [["valid"], 1],
		[["rank_eligible"], false], [["rank_eligible"], 1], [["invalid_reason"], "abandoned"],
		[["duration_s"], 59.0], [["elapsed_s"], 59.0], [["elapsed_s"], 61.0], [["duration_s"], "60"],
		[["pauses"], [{"at_active_s": 1.0, "reason": "manual_pause"}]], [["pauses"], false],
		[["score_version"], "legacy-score"], [["session_id"], "../escape"], [["engine_version"], "different-engine"],
		[["started_utc"], "2026-02-30T08:00:00"], [["started_utc"], "2026-10-12T24:00:00"],
		[["ended_utc"], base.started_utc], [["started_utc"], 123],
		[["program_score"], 501.0], [["program_score"], "500"], [["display_score"], 501],
		[["conditions", "renderer"], "illustrative-example-renderer"], [["conditions", "renderer"], "headless"],
		[["conditions", "rendering_driver"], "dummy"], [["conditions", "input_accumulation"], true],
		[["conditions", "rendering_driver"], "vulkan"],
		[["conditions", "input_accumulation"], 0], [["conditions", "gain_hex"], Canonical.float64_hex(NAN)],
		[["conditions", "gain_hex"], Canonical.float64_hex(INF)], [["conditions", "gain_hex"], Canonical.float64_hex(-0.1)],
		[["conditions", "gain_hex"], Canonical.float64_hex(1.0e30)], [["app_version"], "x".repeat(129)],
		[["conditions", "gain_hex"], "0".repeat(16)], [["conditions", "declared_dpi"], true],
		[["conditions", "declared_dpi"], 800.5], [["conditions", "aspect_ratio"], 2.0],
		[["conditions", "render_resolution_px"], [0, 720]], [["conditions", "render_resolution_px"], [1280.5, 720]],
		[["conditions", "render_resolution_px"], [1280]], [["conditions", "fov_horizontal_deg_at_16_9"], 90.0],
		[["conditions", "seeded_scored_stimulus_preview"], true], [["conditions", "candidate_value_masking"], true],
		[["conditions", "crosshair", "crosshair_color"], "invalid-color"], [["conditions", "crosshair", "crosshair_outline"], 1],
		[["conditions", "audio", "enabled"], 1], [["conditions", "audio", "volume_percent"], -1.0],
		[["render_quality", "valid"], false], [["render_quality", "valid"], 1], [["render_quality", "reason"], "no_render_frametimes"],
		[["render_quality", "mean_fps"], 54.999], [["render_quality", "p99_ms"], 25.001],
		[["render_quality", "max_ms"], 100.001], [["render_quality", "p99_ms"], 0.0],
		[["render_quality", "median_fps"], -1.0], [["render_quality", "frame_count"], 0],
		[["render_quality", "frame_count"], 1.5], [["render_quality", "mean_fps"], INF],
		[["phases"], []], [["phases", 0, "phase_id"], "horizontal"], [["phases", 0, "score_id"], "click_v3"],
		[["phases", 0, "complete"], false], [["phases", 0, "valid"], false], [["phases", 0, "elapsed_s"], 59.0],
		[["phases", 0, "rank_key"], base.rank_key], [["phases", 0, "score"], 500.000001],
		[["phases", 0, "score"], NAN], [["phases", 0, "display_score"], 501],
		[["phases", 0, "metrics", "contact_s"], -1.0], [["phases", 0, "metrics", "contact_lower_s"], 31.0],
		[["phases", 0, "metrics", "contact_upper_s"], 61.0], [["phases", 0, "metrics", "exposure_s"], 59.0],
		[["phases", 0, "metrics", "shots"], 0.5], [["phases", 0, "metrics", "shots"], true],
		[["phases", 0, "metrics", "shots"], 9007199254740992], [["phases", 0, "metrics", "angular_error_mean_deg"], -1.0],
		[["phases", 0, "metrics", "reversal_observations"], [{"reversal_s": 0.0}]],
		[["phases", 0, "contact_intervals_s"], [[-1.0, 2.0]]], [["phases", 0, "contact_intervals_s"], [[0.0, 61.0]]],
		[["pose_event_count"], -1], [["trace_retention"], "full_received_pose_trace"],
		[["received_pose_trace"], [[0, 0, 0.0, 0.0]]], [["manifest"], []], [["manifest"], [Vector3.ZERO]],
		[["unexpected_field"], true], [["warmup"], true], [["abandoned"], true],
		[["initial_pose_yaw_pitch_deg"], null], [["initial_pose_yaw_pitch_deg"], [0.0]],
		[["initial_pose_yaw_pitch_deg"], [0.0, 0.0, 0.0]], [["initial_pose_yaw_pitch_deg"], [true, 0.0]],
		[["initial_pose_yaw_pitch_deg"], [INF, 0.0]], [["initial_pose_yaw_pitch_deg"], [0.0, -90.0]],
		[["initial_pose_yaw_pitch_deg"], [0.0, "0"]], [["conditions", "player_utc_offset_minutes"], true],
		[["conditions", "player_utc_offset_minutes"], "0"], [["conditions", "player_utc_offset_minutes"], 0.5],
		[["conditions", "player_utc_offset_minutes"], 1441], [["conditions", "player_utc_offset_minutes"], NAN],
		[["conditions", "unexpected_field"], false], [["phases", 0, "unexpected_field"], false],
		[["phases", 0, "metrics", "unexpected_field"], 0.0]
	]
	for mutation: Array in mutations:
		var result: Dictionary = Progress.validate_report(_changed(base, mutation[0], mutation[1]))
		_check(not result.ok and not result.error.is_empty(), "Reject malformed, ineligible, or altered report at " + str(mutation[0]))
	for field: String in Progress.REPORT_FIELDS:
		var missing: Dictionary = base.duplicate(true)
		missing.erase(field)
		_check(not Progress.validate_report(missing).ok, "Native required report field cannot be omitted: " + field)
	for field: String in Progress.CONDITION_FIELDS:
		var missing: Dictionary = base.duplicate(true)
		missing.conditions.erase(field)
		_check(not Progress.validate_report(missing).ok, "Frozen condition cannot be omitted: " + field)
	for value: Variant in [null, [], 1, true, "report"]:
		_check(not Progress.validate_report(value).ok, "Reject non-dictionary input without throwing")
	var named: Dictionary = base.duplicate(true)
	named.erase("program_id")
	named[&"program_id"] = "EX06"
	_check(not Progress.validate_report(named).ok, "Stored StringName keys are rejected without normalization")
	_check(not Progress.validate_report(_changed(base, ["program_id"], &"EX06")).ok, "Stored StringName values are rejected without normalization")
	var nested: Variant = [0]
	for depth: int in 66:
		nested = [nested]
	_check(not Progress.validate_report(_changed(base, ["manifest"], nested)).ok, "Excessively deep external data is rejected")
	_check(Canonical.semantic_sha256(base) == before, "Report validation does not mutate caller data")
	var click: Dictionary = _synthetic_report("EX01")
	_check(not Progress.validate_report(_changed(click, ["program_score"], 800.0)).ok, "No fabricated EX01 aggregate is accepted")
	_check(not Progress.validate_report(_changed(click, ["phases", 0, "metrics", "accuracy"], 1.0)).ok, "Click accuracy is recomputed")
	_check(not Progress.validate_report(_changed(click, ["phases", 0, "metrics", "hits"], 26)).ok, "Hits cannot exceed shots")
	_check(not Progress.validate_report(_changed(click, ["phases", 0, "metrics", "misses"], 0)).ok, "Click misses must match hits and shots")
	var reordered: Dictionary = click.duplicate(true)
	reordered.phases.reverse()
	_check(not Progress.validate_report(reordered).ok, "Phase order is part of the native definition")
	var duplicate: Dictionary = click.duplicate(true)
	duplicate.phases[1] = duplicate.phases[0].duplicate(true)
	_check(not Progress.validate_report(duplicate).ok, "Repeated phases cannot replace required phases")
	var opportunity: Dictionary = _synthetic_report("EX03")
	_check(not Progress.validate_report(_changed(opportunity, ["phases", 0, "metrics", "opportunities"], 9)).ok, "Opportunity denominator cannot shrink")
	var switching: Dictionary = _synthetic_report("EX08")
	_check(not Progress.validate_report(_changed(switching, ["phases", 0, "metrics", "credited_work"], 0.5)).ok, "Credited switching work cannot be below kills")
	_check(not Progress.validate_report(_changed(switching, ["program_score"], 75.1)).ok, "Native switching aggregate is recomputed")


func _test_completed_native_profile_report() -> void:
	var store := _isolated_store()
	var source_profile: Dictionary = Store.default_profile()
	_check(store.save_profile(source_profile), "The completed native fixture first saves a real V2 profile")
	var profile: Dictionary = store.load_profile()
	_check(Canonical.semantic_sha256(profile) == Canonical.semantic_sha256(source_profile), "Real profile conditions retain the native saved values")
	var conditions: Dictionary = _synthetic_conditions()
	conditions.merge({"declared_dpi": profile.dpi, "dpi_source": profile.dpi_source, "gain_hex": profile.gain_hex,
		"vertical_fov_deg": profile.vertical_fov_deg,
		"fov_horizontal_deg_at_16_9": rad_to_deg(2.0 * atan(tan(deg_to_rad(float(profile.vertical_fov_deg) * 0.5)) * 16.0 / 9.0)),
		"frame_limit_hz": profile.max_fps, "invert_y": profile.invert_y, "crosshair": Crosshair.resolve(profile),
		"audio": {"enabled": profile.sound_enabled, "volume_percent": profile.sound_volume, "weapon_id": profile.weapon_id},
		"target_palette": {"active": profile.target_color, "amber": "#FFB454"}, "show_weapon": profile.show_weapon,
		"reduced_motion": profile.reduced_motion, "look_profile_id": profile.look_profile_id,
		"player_utc_offset_minutes": Time.get_time_zone_from_system().bias}, true)
	var engine := Session.new()
	_check(engine.start(_definition("EX06"), "0000000000000000000000000000002a", conditions, 22.25, -4.5), "Native EX06 starts with a saved real profile and signed initial pose")
	var identities: Array = []
	for target: Dictionary in engine.snapshot():
		identities.append(target.identity)
	engine.mark_rendered(identities, identities, 0.0, true, {"data_origin": "isolated_synthetic_progress_render_marker"})
	for frame_index: int in 8640:
		engine.record_frame(1.0 / 144.0)
	engine.advance(60.0)
	var report: Dictionary = engine.report()
	_check(report.complete and report.valid and report.rank_eligible, "Native engine actually completes EX06 with explicit synthetic frame samples")
	_check(report.initial_pose_yaw_pitch_deg == [22.25, -4.5] and report.conditions.player_utc_offset_minutes == Time.get_time_zone_from_system().bias, "Native optional pose and timezone fields survive unchanged")
	var metrics: Dictionary = report.phases[0].metrics
	_check(not metrics.reversal_observations.is_empty(), "Native reactive diagnostics come from the executed motion tape")
	_check(metrics.stable_contact_uses_certified_inside_intervals is bool and metrics.long_losses_over_200_ms is int and metrics.diagnostic_contact_fragments_merged_20_ms is int, "Native reactive flags and counters retain strict scalar types")
	_check(Canonical.encode(report).ok and Progress.validate_report(report).ok, "Already JSON-ready native report validates without consumer normalization")
	report.merge({"session_id": "isolated_synthetic_completed_native_ex06", "app_version": "1.0.0-isolated-synthetic-test",
		"engine_version": Engine.get_version_info().string, "score_version": "scores_v2.0",
		"started_utc": "2026-10-12T08:00:00", "ended_utc": "2026-10-12T08:01:00"})
	_check(store.save_report(report), "Completed native report is saved through the immutable store")
	var groups: Array = Progress.summarize(store.history())
	_check(groups.size() == 2 and _group(groups, "EX06", "reactive").best_report_id == report.session_id, "Actual completed native report enters its phase and permitted program records")
	var older: Dictionary = report.duplicate(true)
	older.erase("initial_pose_yaw_pitch_deg")
	older.conditions.erase("player_utc_offset_minutes")
	_rekey(older)
	_check(Progress.validate_report(older).ok, "Earlier saved reports remain valid when both newly recognized optional fields are absent")
	for field: String in ["post_reversal_contact_fraction_250_ms", "stable_reacquisition_p50_ms", "stable_reacquisition_p90_ms"]:
		_check(Progress.validate_report(_changed(report, ["phases", 0, "metrics", field], null)).ok, "Native reactive nullable diagnostic accepts null: " + field)
		_check(not Progress.validate_report(_changed(report, ["phases", 0, "metrics", field], true)).ok, "Native reactive diagnostic rejects a boolean: " + field)
	for offset: int in [-1440, -300, 0, 330, 1440]:
		var changed: Dictionary = _changed(report, ["conditions", "player_utc_offset_minutes"], offset)
		_rekey(changed)
		_check(Progress.validate_report(changed).ok, "Signed integral timezone offsets remain exact comparison conditions")
	_check(not Progress.validate_report(_changed(report, ["phases", 0, "metrics", "long_losses_over_200_ms"], 0.5)).ok, "Native reactive counts reject fractional values")
	_check(not Progress.validate_report(_changed(report, ["phases", 0, "metrics", "stable_contact_uses_certified_inside_intervals"], 1)).ok, "Native reactive certification flag rejects integer coercion")
	_check(not Progress.validate_report(_changed(report, ["conditions", "unknown_optional_flag"], false)).ok, "Recognizing native optional fields never relaxes the closed condition contract")


func _test_saved_proof_and_exclusions() -> void:
	var report: Dictionary = _synthetic_report()
	var rows: Array = _saved_rows([report])
	var before: String = Canonical.semantic_sha256(rows)
	var groups: Array = Progress.summarize(rows)
	_check(groups.size() == 2, "A verified saved contact report has separate phase and permitted program groups")
	var phase: Dictionary = _group(groups, "EX06", "reactive")
	_check(phase.context_count == 1 and phase.best_score == 500.0 and phase.best_report_id == report.session_id, "Saved raw phase record retains its report identity")
	_check(phase.group_id == report.phases[0].rank_key and phase.score_family == Scores.CONTACT_ID, "Group identity is the exact native phase context")
	_check(not phase.has("delta_points"), "One saved session does not imply a trend")
	var repeated: Array = rows + rows + rows
	_check(_group(Progress.summarize(repeated), "EX06", "reactive").context_count == 1, "Repeated loaded rows never multiply the session count")
	_check(Canonical.semantic_sha256(rows) == before, "Summarization preserves loaded rows and reports")
	phase.conditions["invert_y"] = true
	_check(not rows[0].report.conditions.invert_y, "Summary conditions do not alias saved data")
	_check(Progress.summarize([report, {"report": report, "namespace": "v2", "read_only": true, "kind": "session", "semantic_sha256": "a".repeat(64)}]).is_empty(), "Synthetic labels and fabricated metadata cannot replace an immutable store hash")
	for mutation: Array in [
		[["namespace"], "legacy"], [["read_only"], false], [["read_only"], 1], [["kind"], "calibration"],
		[["namespace"], &"v2"], [["kind"], &"session"],
		[["semantic_sha256"], null], [["semantic_sha256"], Canonical.semantic_sha256(report)],
		[["report", "phases", 0, "score"], 999.0], [["report", "session_id"], "different_saved_identity"]
	]:
		_check(Progress.summarize([_changed(rows[0], mutation[0], mutation[1])]).is_empty(), "Saved provenance rejects " + str(mutation[0]))
	var named_row: Dictionary = rows[0].duplicate(true)
	named_row.erase("namespace")
	named_row[&"namespace"] = "v2"
	_check(Progress.summarize([named_row]).is_empty(), "Stored row keys also reject raw StringName without normalization")
	var unstorable: Dictionary = rows[0].duplicate(true)
	unstorable.report.erase("score_version")
	var forged_versions: Dictionary = {"store": Store.DOCUMENT_SCHEMA, "hash_encoding": Store.HASH_ENCODING}
	for field: String in Store.VERSION_FIELDS:
		if unstorable.report.has(field):
			forged_versions[field] = unstorable.report[field]
	unstorable["semantic_sha256"] = Canonical.semantic_sha256({"schema_version": Store.DOCUMENT_SCHEMA,
		"kind": "report", "hash_encoding": Store.HASH_ENCODING, "number_encoding": Store.NUMBER_ENCODING,
		"versions": forged_versions, "payload": unstorable.report})
	_check(Progress.validate_report(unstorable.report).ok and Progress.summarize([unstorable]).is_empty(), "A forged matching envelope cannot make an unstorable unversioned native report count as saved practice")
	var store := _isolated_store()
	_check(store.save_report(report), "Save the isolated immutable report")
	_check(not store.save_report(_changed(report, ["title"], "Altered synthetic report")), "Store refuses replacement under the same immutable identity")
	_check(_group(Progress.summarize(store.history()), "EX06", "reactive").best_score == 500.0, "Immutable original still establishes its record")
	var changed: Dictionary = _synthetic_report("EX06", "standard", 0.6)
	changed["session_id"] = report.session_id
	changed["started_utc"] = report.started_utc
	changed["ended_utc"] = report.ended_utc
	_check(Progress.summarize(rows + _saved_rows([changed])).is_empty(), "Conflicting saved bodies for one identity are excluded independent of order")
	var ineligible: Array = [
		_changed(report, ["complete"], false), _changed(report, ["valid"], false),
		_changed(report, ["rank_eligible"], false), _changed(report, ["invalid_reason"], "abandoned"),
		_changed(report, ["pauses"], [{"at_active_s": 1.0, "reason": "manual_pause"}]),
		_changed(report, ["program_id"], "CAL-CLICK"), _changed(report, ["warmup"], true)
	]
	for report_index: int in ineligible.size():
		ineligible[report_index]["session_id"] = "isolated_synthetic_excluded_%d" % report_index
	_check(Progress.summarize(_saved_rows(ineligible)).is_empty(), "Even correctly saved CAL, warmup, invalid, paused, incomplete, and abandoned bodies do not enter practice records")


func _test_context_separation() -> void:
	var baseline: Dictionary = _synthetic_report()
	var variants: Array = [baseline]
	var changes: Array = [
		[["gain_hex"], Canonical.float64_hex(0.03265714285714286 + 1.0e-16)],
		[["declared_dpi"], 1600], [["render_resolution_px"], [1920, 1080]],
		[["frame_limit_hz"], 240], [["display_hz_declared"], 240.0], [["vsync"], true], [["invert_y"], true],
		[["crosshair", "crosshair_size_px"], 4.0], [["audio", "enabled"], true],
		[["target_palette", "active"], "#FFB454"], [["show_weapon"], false], [["reduced_motion"], true],
		[["os"], "Windows"]
	]
	for change: Array in changes:
		var variant: Dictionary = _synthetic_report()
		var conditions: Dictionary = _changed(variant.conditions, change[0], change[1])
		variant["conditions"] = conditions
		_check(not Progress.validate_report(variant).ok, "Condition changes invalidate stale native rank keys")
		_rekey(variant)
		_check(Progress.validate_report(variant).ok, "A complete changed condition forms a separate valid context")
		variants.append(variant)
	var wider: Dictionary = _synthetic_report()
	wider.conditions["render_resolution_px"] = [1600, 800]
	wider.conditions["aspect_ratio"] = 2.0
	_rekey(wider)
	variants.append(wider)
	var fov: Dictionary = _synthetic_report()
	fov.conditions["vertical_fov_deg"] = 75.0
	fov.conditions["fov_horizontal_deg_at_16_9"] = rad_to_deg(2.0 * atan(tan(deg_to_rad(37.5)) * 16.0 / 9.0))
	_rekey(fov)
	variants.append(fov)
	var renderer: Dictionary = _synthetic_report()
	renderer.conditions["renderer"] = "forward_plus"
	renderer.conditions["rendering_driver"] = "vulkan"
	_rekey(renderer)
	variants.append(renderer)
	var unknown_dpi: Dictionary = _synthetic_report()
	unknown_dpi.conditions["declared_dpi"] = null
	unknown_dpi.conditions["dpi_source"] = "unknown"
	_rekey(unknown_dpi)
	variants.append(unknown_dpi)
	var groups: Array = Progress.summarize(_saved_rows(variants))
	_check(groups.size() == variants.size() * 2, "Every exact gain, DPI, input, presentation, viewport, renderer, and technical condition stays separate")
	for group: Dictionary in groups:
		_check(group.context_count == 1 and not group.has("delta_points"), "Different contexts cannot fabricate a ten-session comparison")
	var public_reports: Array = []
	for program_id: String in ["EX01", "EX02", "EX03", "EX04"]:
		public_reports.append(_synthetic_report(program_id))
	var click_groups: Array = Progress.summarize(_saved_rows(public_reports))
	_check(click_groups.size() == 10, "EX01, EX02, EX03 and EX04 keep all ten distinct phase records")
	for group: Dictionary in click_groups:
		_check(not group.phase_id.is_empty(), "No heterogeneous click or opportunity program aggregate is invented")
	var difficulty_rows: Array = _saved_rows([_synthetic_report("EX05", "novice"), _synthetic_report("EX05", "standard"), _synthetic_report("EX05", "advanced"), _synthetic_report("EX08")])
	var difficulty_groups: Array = Progress.summarize(difficulty_rows)
	_check(difficulty_groups.size() == 16, "Three difficulties and permitted contact/switching aggregates keep their own groups")
	_check(_group(difficulty_groups, "EX05", "", "novice").best_score == 500.0 and _group(difficulty_groups, "EX08", "").best_score == 75.0, "Permitted native program scores retain their raw units")


func _test_medians_and_records() -> void:
	var reports: Array = []
	var points: Array[float] = [0.0, 10.0, 20.0, 30.0, 1000.0, 40.0, 50.0, 60.0, 70.0, 900.0]
	for score: float in points:
		reports.append(_synthetic_report("EX06", "standard", score / 1000.0))
	var rows: Array = _saved_rows(reports)
	var nine: Dictionary = _group(Progress.summarize(rows.slice(0, 9)), "EX06", "reactive")
	_check(nine.context_count == 9 and not nine.has("first_five_median") and not nine.has("last_five_median") and not nine.has("delta_points"), "Nine matched sessions never expose overlapping five-session windows")
	rows.reverse()
	var before: String = Canonical.semantic_sha256(rows)
	var ten: Dictionary = _group(Progress.summarize(rows), "EX06", "reactive")
	_check(ten.context_count == 10 and absf(ten.first_five_median - 20.0) < 1.0e-9 and absf(ten.last_five_median - 60.0) < 1.0e-9, "Ten sessions use chronological first-five and last-five medians, robust to outliers")
	_check(absf(ten.delta_points - 40.0) < 1.0e-9 and absf(ten.delta_percent - 200.0) < 1.0e-9, "Delta reports raw score points and relative percent only")
	_check(ten.best_score == 1000.0 and ten.best_report_id == reports[4].session_id, "Record includes all matched sessions and links the actual best report")
	_check(Canonical.semantic_sha256(rows) == before, "Chronological ordering does not reorder caller history")
	rows.append_array(rows.slice(0, 3))
	_check(_group(Progress.summarize(rows), "EX06", "reactive").context_count == 10, "Duplicate history cannot reach or expand a comparison threshold")
	var additional: Dictionary = _synthetic_report("EX06", "standard", 0.08)
	rows.append_array(_saved_rows([additional]))
	var eleven: Dictionary = _group(Progress.summarize(rows), "EX06", "reactive")
	_check(eleven.context_count == 11 and absf(eleven.first_five_median - 20.0) < 1.0e-9 and absf(eleven.last_five_median - 70.0) < 1.0e-9, "After eleven sessions the first window remains fixed and the last window advances")
	var zero_reports: Array = []
	for report_index: int in 10:
		zero_reports.append(_synthetic_report("EX06", "standard", 0.0 if report_index < 5 else float(report_index - 3) * 0.1))
	var zero: Dictionary = _group(Progress.summarize(_saved_rows(zero_reports)), "EX06", "reactive")
	_check(zero.first_five_median == 0.0 and absf(zero.delta_points - 400.0) < 1.0e-9 and zero.delta_percent == null, "Zero baseline preserves raw delta and never fabricates an infinite percentage")
	var falling_reports: Array = []
	for report_index: int in 10:
		falling_reports.append(_synthetic_report("EX06", "standard", 0.6 if report_index < 5 else 0.12345))
	var falling: Dictionary = _group(Progress.summarize(_saved_rows(falling_reports)), "EX06", "reactive")
	_check(absf(falling.last_five_median - 123.45) < 1.0e-9 and absf(falling.delta_points + 476.55) < 1.0e-9, "Raw fractional scores and negative changes remain intact")
	_check(falling.best_report_id == falling_reports[0].session_id, "Equal records use the earliest matched report deterministically")
	var sparse: Array = _saved_rows([_synthetic_report("EX06", "standard", 0.0)])
	for repeat_index: int in 12:
		sparse.append(sparse[0].duplicate(true))
	var sparse_group: Dictionary = _group(Progress.summarize(sparse), "EX06", "reactive")
	_check(sparse_group.context_count == 1 and sparse_group.best_score == 0.0 and not sparse_group.has("delta_points"), "A valid zero remains a record and repeated loads never become longitudinal evidence")


func _remove_fixture(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_fixture(path.path_join(child))
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	DirAccess.remove_absolute(path)


func _run() -> void:
	print("V2 PROGRESS fixtures are isolated synthetic reports and synthetic frametimes, not player data or renderer benchmarks.")
	catalogue = Catalog.load_catalog()
	if catalogue.is_empty():
		_check(false, "Pinned native catalogue must be available")
	else:
		_test_native_contracts()
		_test_completed_native_profile_report()
		_test_closed_validation()
		_test_saved_proof_and_exclusions()
		_test_context_separation()
		_test_medians_and_records()
	for fixture: String in fixture_roots:
		_remove_fixture(fixture)
		_check(not DirAccess.dir_exists_absolute(fixture), "Isolated synthetic history is removed after testing")
	print("V2 PROGRESS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)
