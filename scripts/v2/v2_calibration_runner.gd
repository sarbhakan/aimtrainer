class_name V2CalibrationRunner
extends RefCounted

const Store := preload("res://scripts/v2/v2_store.gd")
const Calibration := preload("res://scripts/v2/v2_calibration_service.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const VERSION: String = "calibration_runner_v2.0"
const CHECKPOINT_FIELDS: Array[String] = [
	"runner_version", "calibration_id", "plan", "stage", "epoch", "cells", "reports", "report_ids",
	"started_unix", "local_date", "utc_offset_minutes", "waits", "ready_cells", "last_elapsed_s",
	"result", "express_context", "previous_plan_sha256", "preflight", "recovery_context"
]
const TASK_AUDIT_FIELDS: Array[String] = [
	"schema_version", "runtime_version", "input_convention", "task", "task_id", "deck_id",
	"deck_manifest_sha256", "duration_s", "elapsed_s", "complete", "valid", "invalid_reason",
	"U", "utility", "diagnostic_utility", "comparative_utility_included", "opportunities", "raw_succeeded", "success_count", "killed",
	"click_opportunities", "switch_opportunities", "click_successes", "switch_completions",
	"first_presses", "premature", "extra_shots", "late_shots", "metrics", "opportunity_dispositions",
	"hit_events", "diagnostic_events", "render_quality", "reversals", "trace_reference", "data_origin"
]

var plan: Dictionary = {}
var baseline_profile: Dictionary = {}
var temporary_gain_deg_per_relative_unit: float = 0.0
var active: bool = false
var result: Dictionary = {}
var error: String = ""

var _store: Store
var _calibration_id: String = ""
var _stage: String = "idle"
var _epoch: Dictionary = {}
var _cells: Dictionary = {}
var _reports: Array = []
var _report_ids: Array = []
var _segments: Array = []
var _ready_cells: Array = []
var _waits: Array = []
var _started_unix: float = 0.0
var _local_date: String = ""
var _utc_offset_minutes: Variant = null
var _last_elapsed_s: float = 0.0
var _gate: Dictionary = {}
var _last_snapshot: Dictionary = {}
var _express_context: Dictionary = {}
var _previous_plan_sha256: String = ""
var _pending_task: Dictionary = {}
var _pending_day: Dictionary = {}
var _preflight: Dictionary = {}
var _pending_cancel: Dictionary = {}
var _pending_refreeze: Dictionary = {}
var _recovery_context: Dictionary = {}


func _init(store: Store) -> void:
	_store = store
	recover()


func prepare_express(profile: Dictionary, actual_conditions: Dictionary, settings: Dictionary) -> bool:
	error = ""
	if active or not plan.is_empty():
		return _fail("CALIBRATION_PLAN_ALREADY_PENDING")
	var portable_profile: Dictionary = _portable(profile)
	if not Store._profile_valid(portable_profile) or portable_profile.dpi == null:
		return _fail("CALIBRATION_REQUIRES_VALID_PROFILE_AND_DPI")
	var levels: Variant = settings.get("difficulty_by_task", settings.get("levels", {"CLICK": "standard", "SMOOTH": "standard", "REACTIVE": "standard", "SWITCH": "standard"}))
	if not _finite(settings.get("ratio", 1.25)) or not levels is Dictionary or not settings.get("objective", "polyvalent") in Calibration.OBJECTIVES:
		return _fail("CALIBRATION_SETTINGS_INVALID")
	if settings.has("difficulty_by_task") and settings.has("levels") and not _same(_portable(settings.difficulty_by_task), _portable(settings.levels)):
		return _fail("CALIBRATION_DIFFICULTY_ALIASES_CONFLICT")
	var actual_gain: String = _actual_gain_hex(actual_conditions)
	if actual_gain != portable_profile.gain_hex:
		return _fail("BASELINE_ACTUAL_GAIN_MISMATCH")
	var baseline_gain: Dictionary = Calibration.make_gain("A", float(portable_profile.cm_per_360), float(portable_profile.dpi), Canonical.float64_from_hex(portable_profile.gain_hex))
	var grid: Dictionary = Calibration.candidate_grid(baseline_gain, float(settings.get("ratio", 1.25)))
	if not grid.get("ok", false):
		return _fail(str(grid.get("error", "CANDIDATE_GRID_FAILED")))
	var conditions: Dictionary = _fixed_conditions(actual_conditions)
	conditions["difficulty_by_task"] = _portable(levels)
	var built: Dictionary = Calibration.create_express_plan(baseline_gain, grid.gains, conditions, str(settings.get("objective", "polyvalent")), str(settings.get("plan_seed_hex", _seed())))
	if not built.get("ok", false):
		return _fail(str(built.get("error", "EXPRESS_PLAN_FAILED")))
	var checkpoint: Dictionary = _empty_checkpoint(built.plan, "cal_" + _seed())
	if not _save(checkpoint, portable_profile, "pending", 0, 0):
		return false
	baseline_profile = portable_profile.duplicate(true)
	Calibration._freeze(baseline_profile)
	_restore_checkpoint(checkpoint)
	_restore_gain()
	return true


func prepare_confirmation(actual_conditions: Dictionary, now_unix: float, local_date: String) -> bool:
	error = ""
	if active or plan.get("phase") != "express" or not _accepted_report(0) is Dictionary or _accepted_report(0).is_empty():
		return _fail("COMPLETE_VALID_EXPRESS_REQUIRED")
	if not result.get("uninformative_tasks", []).is_empty():
		return _fail("EXPRESS_DIFFICULTY_UNINFORMATIVE")
	var window: Dictionary = _window(1, now_unix, local_date, actual_conditions)
	if not window.ok:
		return _fail(window.error)
	if not _conditions_ok(actual_conditions) or _actual_gain_hex(actual_conditions) != baseline_profile.gain_hex:
		return _fail("CONFIRMATION_BASELINE_OR_CONDITIONS_CHANGED")
	var challenger_id: String = str(result.get("challenger_candidate_id", ""))
	var baseline_gain: Dictionary = _candidate("A")
	var challenger: Dictionary = _candidate(challenger_id)
	if challenger.is_empty() or challenger_id == "A":
		return _fail("EXPRESS_CHALLENGER_MISSING")
	var built: Dictionary = Calibration.create_confirmation_plan(baseline_gain, challenger, _fixed_conditions(actual_conditions), str(plan.condition_snapshot.objective), _seed(), plan.condition_snapshot.difficulty_by_task)
	if not built.get("ok", false):
		return _fail(str(built.get("error", "CONFIRMATION_PLAN_FAILED")))
	var checkpoint: Dictionary = _empty_checkpoint(built.plan, _calibration_id)
	checkpoint["report_ids"] = _report_ids.duplicate()
	checkpoint["previous_plan_sha256"] = plan.plan_sha256
	checkpoint["express_context"] = {"plan_sha256": plan.plan_sha256, "actual_end_utc": _accepted_report(0).actual_end_utc,
		"result": result.duplicate(true), "accepted_epoch_report": _accepted_report(0).duplicate(true)}
	if not _save(checkpoint, baseline_profile, "pending", 1, 0):
		return false
	_restore_checkpoint(checkpoint)
	_restore_gain()
	return true


func start_day(day_role: int, now_unix: float, local_date: String, conditions: Dictionary) -> bool:
	error = ""
	if active or plan.is_empty() or not _pending_task.is_empty() or not _pending_day.is_empty() or not _preflight.get("transition", {}).is_empty():
		return _fail("DAY_NOT_READY")
	if (plan.phase == "express" and day_role != 0) or (plan.phase == "confirmation" and not day_role in [1, 2]):
		return _fail("UNPLANNED_DAY_ROLE")
	if not _accepted_report(day_role).is_empty():
		return _fail("DAY_ALREADY_ACCEPTED")
	var window: Dictionary = _window(day_role, now_unix, local_date, conditions)
	if not window.ok:
		return _fail(window.error)
	if not _conditions_ok(conditions) or _actual_gain_hex(conditions) != baseline_profile.gain_hex:
		return _fail("DAY_BASELINE_OR_CONDITIONS_CHANGED")
	var attempts: Array = _role_reports(day_role)
	if attempts.size() >= 2:
		return _fail("MAXIMUM_DAY_ATTEMPTS_EXCEEDED")
	if not attempts.is_empty():
		if attempts[-1].eligibility.get("reasons", []).is_empty() or now_unix < float(attempts[-1].actual_end_utc):
			return _fail("RETRY_REQUIRES_TECHNICAL_CAUSE_AND_CHRONOLOGY")
	var built: Dictionary = Calibration.create_day_epoch(plan, day_role, attempts.size())
	if not built.get("ok", false):
		return _fail(str(built.get("error", "DAY_EPOCH_FAILED")))
	var checkpoint: Dictionary = _checkpoint()
	checkpoint["stage"] = "active"
	checkpoint["epoch"] = built.epoch
	checkpoint["cells"] = {}
	checkpoint["ready_cells"] = []
	checkpoint["waits"] = []
	checkpoint["started_unix"] = now_unix
	checkpoint["local_date"] = local_date
	checkpoint["utc_offset_minutes"] = conditions.get("player_utc_offset_minutes", null)
	checkpoint["last_elapsed_s"] = 0.0
	checkpoint["preflight"] = _empty_preflight()
	checkpoint["recovery_context"] = {}
	if not _save(checkpoint, baseline_profile, "active", day_role, attempts.size()):
		return false
	_restore_checkpoint(checkpoint)
	active = true
	_restore_gain()
	return true


func timeline_at(active_elapsed_s: float) -> Dictionary:
	if not active or _epoch.is_empty():
		return {"kind": "done", "segment_id": "", "start_s": 0.0, "end_s": 0.0, "time_origin": 0.0, "gain": _baseline_gain(), "gain_hex": baseline_profile.get("gain_hex", ""), "blocked": false, "scored": false}
	if not _finite(active_elapsed_s) or active_elapsed_s < _last_elapsed_s - 1.0e-9:
		_fail("CLOCK_DISCONTINUITY")
		return {"kind": "done", "blocked": true, "reason": error}
	if not _pending_task.is_empty() or not _pending_day.is_empty() or not _pending_refreeze.is_empty():
		var held: Dictionary = _last_snapshot.duplicate()
		held["blocked"] = true
		held["reason"] = "PERSISTENCE_PENDING"
		return held
	var trial: Dictionary = _preflight.pending_adjustment
	if not trial.is_empty() and trial.started:
		if active_elapsed_s < float(trial.end_s):
			_last_elapsed_s = active_elapsed_s
			_last_snapshot = _decorate(trial, false)
			return _last_snapshot
		_gate = _segment("preflight", _epoch.session.session_id + ".preflight.review", trial.end_s, trial.end_s, "A", {})
		_last_elapsed_s = float(trial.end_s)
		_last_snapshot = _decorate(_gate, true)
		_last_snapshot["reason"] = "PREFLIGHT_VALIDATION_RESULT_PENDING"
		return _last_snapshot
	var preflight_end_s: float = 60.0 + float(_preflight.generation) * 84.0
	if not _preflight.reviewed and active_elapsed_s >= preflight_end_s:
		_gate = _segment("preflight", _epoch.session.session_id + ".preflight.review", preflight_end_s, preflight_end_s, "A", {})
		_last_elapsed_s = preflight_end_s
		_last_snapshot = _decorate(_gate, true)
		_last_snapshot["reason"] = "PREFLIGHT_REVIEW_REQUIRED"
		return _last_snapshot
	for segment: Dictionary in _segments:
		if segment.kind == "countdown" and not segment.segment_id in _ready_cells and active_elapsed_s >= float(segment.start_s):
			_gate = segment
			_last_elapsed_s = float(segment.start_s)
			_last_snapshot = _decorate(segment, true)
			return _last_snapshot
	_last_elapsed_s = active_elapsed_s
	var snapshot: Dictionary = {}
	for segment: Dictionary in _segments:
		if active_elapsed_s >= float(segment.start_s) and active_elapsed_s < float(segment.end_s):
			snapshot = _decorate(segment, false)
			break
	if snapshot.is_empty():
		var end_s: float = float(_epoch.session.planned_duration_s) + float(_preflight.generation) * 84.0
		snapshot = {"kind": "done", "segment_id": "", "start_s": end_s, "end_s": end_s,
			"time_origin": end_s, "candidate_id": "A", "gain": _baseline_gain(), "gain_hex": baseline_profile.gain_hex, "blocked": false, "scored": false, "active_elapsed_s": active_elapsed_s, "sample_s": active_elapsed_s}
	temporary_gain_deg_per_relative_unit = float(snapshot.gain)
	_last_snapshot = snapshot
	return snapshot


func ready_task(segment_id: String, now_unix: float) -> bool:
	error = ""
	if not _gate.is_empty() and _gate.kind == "preflight" and _gate.segment_id == segment_id:
		if not _preflight.pending_adjustment.is_empty():
			return _ready_level_adjustment(now_unix)
		return review_preflight(now_unix)
	if not active or _gate.is_empty() or _gate.segment_id != segment_id or not _finite(now_unix):
		return _fail("TASK_READINESS_NOT_EXPECTED")
	var wait_start_s: float = float(_gate.start_s) + _wait_total()
	var wait_end_s: float = now_unix - _started_unix
	if wait_end_s < wait_start_s - 0.000001:
		return _fail("CLOCK_DISCONTINUITY")
	var checkpoint: Dictionary = _checkpoint()
	checkpoint.ready_cells.append(segment_id)
	if wait_end_s > wait_start_s:
		checkpoint.waits.append({"start_s": wait_start_s, "end_s": wait_end_s, "planned": false, "gain_hex": _candidate_hex(str(_gate.candidate_id)), "reason": "voluntary_ready"})
	if not _save(checkpoint, baseline_profile, "active", int(_epoch.session.day_role), int(_epoch.session.attempt_epoch)):
		return false
	_ready_cells = checkpoint.ready_cells
	_waits = checkpoint.waits
	_gate = {}
	if wait_end_s - wait_start_s > 900.0:
		return _interrupt_at("long_unplanned_interruption", now_unix)
	return true


func record_familiarization(segment_id: String, report: Dictionary) -> bool:
	error = ""
	if not active or _preflight.reviewed or not _preflight.transition.is_empty():
		return _fail("FAMILIARIZATION_NOT_EXPECTED")
	var expected: Dictionary = {}
	for segment: Dictionary in _segments:
		if segment.kind == "preflight" and segment.segment_id == segment_id:
			expected = segment
	if expected.is_empty() or not _diagnostic_valid(expected, report, 15.0):
		return _fail("FAMILIARIZATION_REPORT_INVALID")
	if _preflight.reports.has(expected.task):
		var existing: Dictionary = _preflight.reports[expected.task]
		var original: Dictionary = report.duplicate(true)
		original["trace_reference"] = existing.trace_reference
		return _same(existing, _compact_report(original)) or _fail("FAMILIARIZATION_ALREADY_COMMITTED")
	if _preflight.reports.size() != _epoch.session.preflight.tasks.find_custom(func(task: Dictionary) -> bool: return task.task == expected.task):
		return _fail("FAMILIARIZATION_OUT_OF_ORDER")
	var durable: Dictionary = _save_diagnostic_trace(segment_id, report)
	if durable.is_empty():
		return false
	var checkpoint: Dictionary = _checkpoint()
	checkpoint.preflight.reports[expected.task] = _compact_report(durable)
	checkpoint.report_ids.append(durable.trace_reference.session_id)
	if not _save(checkpoint, baseline_profile, "active", int(_epoch.session.day_role), int(_epoch.session.attempt_epoch)):
		return false
	_preflight = checkpoint.preflight
	_report_ids = checkpoint.report_ids
	return true


func review_preflight(now_unix: float) -> bool:
	error = ""
	if not active or _gate.get("kind") != "preflight" or _preflight.reports.size() != 4 or not _preflight.pending_adjustment.is_empty() or not _preflight.transition.is_empty():
		return _fail("PREFLIGHT_REVIEW_NOT_READY")
	var checkpoint: Dictionary = _checkpoint()
	if not _append_review_wait(checkpoint, now_unix):
		return false
	checkpoint.preflight.reviewed = true
	checkpoint.preflight.reviewed_unix = now_unix
	checkpoint.preflight.review_proposals = _preflight_ui().proposals
	if not _save(checkpoint, baseline_profile, "active", int(_epoch.session.day_role), int(_epoch.session.attempt_epoch)):
		return false
	_preflight = checkpoint.preflight
	_waits = checkpoint.waits
	_gate = {}
	return true


func prepare_level_adjustment(task: String, difficulty: String) -> Dictionary:
	error = ""
	var proposed: bool = false
	for proposal: Dictionary in _preflight_ui().proposals:
		if proposal.task == task and proposal.suggested_level == difficulty and proposal.can_adjust:
			proposed = true
	if not active or _gate.get("kind") != "preflight" or not proposed or not _preflight.pending_adjustment.is_empty() or not _preflight.transition.is_empty():
		_fail("PREFLIGHT_LEVEL_ADJUSTMENT_NOT_ALLOWED")
		return {}
	var change_index: int = int(_preflight.changes_by_task[task]) + 1
	var built: Dictionary = Calibration.make_deck(str(plan.plan_seed_hex), "express_preflight_validation", "0", "level%d" % int(_preflight.generation), str(change_index), task, difficulty)
	if built.has("error") or not Store._hex(built.get("manifest_sha256"), 64) or not built.get("deck_id") is String:
		_fail(str(built.get("error", "PREFLIGHT_VALIDATION_DECK_FAILED")))
		return {}
	var identity: String = _epoch.session.session_id + ".f%d.test.%s" % [int(_preflight.generation), task]
	var start_s: float = float(_gate.start_s)
	var trial: Dictionary = {"segment_id": identity, "kind": "preflight_adjustment", "task": task, "from_level": plan.condition_snapshot.difficulty_by_task[task],
		"difficulty": difficulty, "duration_s": 24.0, "candidate_id": "A", "gain_hex": baseline_profile.gain_hex,
		"gain": _baseline_gain(), "deck": built, "deck_manifest_sha256": built.manifest_sha256,
		"comparative_utility_included": false, "external_clock": false, "change_index": change_index,
		"start_s": start_s, "end_s": start_s + 24.0, "time_origin": start_s, "scored": false, "started": false, "actual_start_unix": null,
		"task_conditions": {"comparative_utility_included": false, "gain_hex": baseline_profile.gain_hex}}
	var checkpoint: Dictionary = _checkpoint()
	checkpoint.preflight.pending_adjustment = trial
	if not _save(checkpoint, baseline_profile, "active", int(_epoch.session.day_role), int(_epoch.session.attempt_epoch)):
		return {}
	_preflight = checkpoint.preflight
	return trial.duplicate(true)


func accept_level_adjustment(segment_id: String, report: Dictionary, conditions: Dictionary, unix: float) -> bool:
	error = ""
	if not _pending_refreeze.is_empty():
		if _pending_refreeze.segment_id != segment_id or Canonical.semantic_sha256(_portable(report)) != _pending_refreeze.report_sha256:
			return _fail("OTHER_PREFLIGHT_REFREEZE_COMMIT_PENDING")
		return _commit_refreeze()
	var trial: Dictionary = _preflight.get("pending_adjustment", {})
	if not active or _gate.get("kind") != "preflight" or trial.is_empty() or not trial.started or trial.segment_id != segment_id or not _preflight.transition.is_empty():
		return _fail("PREFLIGHT_VALIDATION_NOT_EXPECTED")
	if not _conditions_ok(conditions) or _actual_gain_hex(conditions) != baseline_profile.gain_hex:
		_interrupt_at("configuration_hash_change", unix)
		return _fail("PREFLIGHT_VALIDATION_CONDITIONS_CHANGED")
	if not _diagnostic_valid(trial, report, 24.0) or not _finite(unix) or unix - float(trial.actual_start_unix) < 24.0:
		return _fail("PREFLIGHT_VALIDATION_REQUIRES_COMPLETE_24_SECONDS")
	var durable: Dictionary = _save_diagnostic_trace(segment_id, report)
	if durable.is_empty():
		return false
	var levels: Dictionary = plan.condition_snapshot.difficulty_by_task.duplicate(true)
	levels[trial.task] = trial.difficulty
	var updated_conditions: Dictionary = _fixed_conditions(conditions)
	updated_conditions["difficulty_by_task"] = levels
	var built: Dictionary = Calibration.create_express_plan(_candidate("A"), plan.candidates, updated_conditions, str(plan.condition_snapshot.objective), _seed())
	if not built.get("ok", false):
		return _fail(str(built.get("error", "PREFLIGHT_REFREEZE_PLAN_FAILED")))
	var generated_epoch: Dictionary = Calibration.create_day_epoch(built.plan, 0, int(_epoch.session.attempt_epoch))
	if not generated_epoch.get("ok", false):
		return _fail(str(generated_epoch.get("error", "PREFLIGHT_REFREEZE_EPOCH_FAILED")))
	var checkpoint: Dictionary = _checkpoint()
	if not _append_review_wait(checkpoint, unix):
		return false
	checkpoint.preflight.validations.append({"task": trial.task, "from_level": trial.from_level, "difficulty": trial.difficulty,
		"actual_end_utc": unix, "duration_s": 24.0, "audit": _compact_report(durable), "source_plan_sha256": plan.plan_sha256})
	checkpoint.preflight.history.append({"generation": _preflight.generation, "plan_sha256": plan.plan_sha256, "reports": _preflight.reports.duplicate(true)})
	checkpoint.preflight.changes_by_task[trial.task] += 1
	checkpoint.preflight.pending_adjustment = {}
	checkpoint.preflight.transition = {"plan": built.plan, "epoch": generated_epoch.epoch}
	checkpoint["stage"] = "preflight_refreeze_pending"
	checkpoint.report_ids.append(durable.trace_reference.session_id)
	var archive_id: String = _calibration_id + ".preflight.f%d" % int(_preflight.generation)
	var archive: Dictionary = _storage_report(archive_id, "preflight_refreeze", {"checkpoint": checkpoint, "reason": "explicit_adjacent_level_change_after_24_second_validation"})
	checkpoint.report_ids.append(archive_id)
	_pending_refreeze = {"segment_id": segment_id, "report_sha256": Canonical.semantic_sha256(_portable(report)), "checkpoint": checkpoint,
		"archive": archive, "new_plan": built.plan, "new_epoch": generated_epoch.epoch, "previous_hash": plan.plan_sha256, "old_committed": false}
	return _commit_refreeze()


func record_adaptive_trial(segment_id: String, report: Dictionary, conditions: Dictionary, unix: float) -> bool:
	return accept_level_adjustment(segment_id, report, conditions, unix)


func _ready_level_adjustment(unix: float) -> bool:
	if not active or _preflight.pending_adjustment.started:
		return _fail("PREFLIGHT_VALIDATION_READINESS_NOT_EXPECTED")
	var checkpoint: Dictionary = _checkpoint()
	if not _append_review_wait(checkpoint, unix):
		return false
	checkpoint.preflight.pending_adjustment.started = true
	checkpoint.preflight.pending_adjustment.actual_start_unix = unix
	if not _save(checkpoint, baseline_profile, "active", 0, int(_epoch.session.attempt_epoch)):
		return false
	_preflight = checkpoint.preflight
	_waits = checkpoint.waits
	_gate = {}
	return true


func _commit_refreeze() -> bool:
	var pending: Dictionary = _pending_refreeze
	if not _store.save_report(pending.archive):
		return _fail("PREFLIGHT_ARCHIVE_SAVE_FAILED:" + _store.last_error)
	var checkpoint: Dictionary = pending.checkpoint.duplicate(true)
	if not pending.old_committed:
		if not _save(checkpoint, baseline_profile, "complete", 0, int(_epoch.session.attempt_epoch)):
			return false
		pending.old_committed = true
		_restore_checkpoint(checkpoint)
	_restore_gain()
	checkpoint["plan"] = pending.new_plan
	checkpoint["epoch"] = pending.new_epoch
	checkpoint["previous_plan_sha256"] = pending.previous_hash
	checkpoint["stage"] = "active"
	checkpoint.preflight.generation += 1
	checkpoint.preflight.reports = {}
	checkpoint.preflight.review_proposals = []
	checkpoint.preflight.reviewed = false
	checkpoint.preflight.reviewed_unix = null
	checkpoint.preflight.transition = {}
	if not _save(checkpoint, baseline_profile, "active", 0, int(_epoch.session.attempt_epoch)):
		return false
	_restore_checkpoint(checkpoint)
	_restore_gain()
	_pending_refreeze = {}
	return true


func cancel_plan(reason: String = "cancelled_by_player") -> bool:
	error = ""
	_restore_gain()
	if reason.is_empty() or reason.length() > 256:
		return _fail("CALIBRATION_CANCELLATION_REASON_INVALID")
	if plan.is_empty():
		return true
	if active and not interrupt(reason):
		return false
	if not _pending_day.is_empty():
		if not _commit_day(_pending_day):
			return false
		_pending_day = {}
	if _pending_cancel.is_empty():
		var identity: String = _calibration_id + ".archive." + _seed().substr(0, 16)
		_pending_cancel = _storage_report(identity, "archive", {"reason": reason, "created_unix": _clock_unix(),
			"checkpoint": _checkpoint(), "uncommitted_cell": _pending_task.duplicate(true), "baseline_profile": baseline_profile.duplicate(true)})
	if not _store.save_report(_pending_cancel):
		return _fail("CALIBRATION_ARCHIVE_SAVE_FAILED:" + _store.last_error)
	if not _store.clear_calibration_state():
		return _fail("CALIBRATION_BASELINE_RESTORE_FAILED:" + _store.last_error)
	_restore_checkpoint(_empty_checkpoint({}, ""))
	_stage = "idle"
	_pending_task = {}
	_pending_day = {}
	_pending_cancel = {}
	_pending_refreeze = {}
	baseline_profile = _store.load_profile()
	_restore_gain()
	return not baseline_profile.is_empty() or _fail("CANCELLED_PROFILE_RELOAD_FAILED:" + _store.last_error)


func accept_task(segment_id: String, report: Dictionary, conditions: Dictionary, unix: float) -> bool:
	error = ""
	if not active or not _finite(unix) or unix < _started_unix:
		return _fail("TASK_OUTSIDE_ACTIVE_DAY")
	if not _preflight.reviewed:
		return _fail("PREFLIGHT_REVIEW_REQUIRED")
	if not _trace_link_valid(report):
		return _fail("CELL_FULL_AUDIT_REFERENCE_INVALID")
	if _cells.has(segment_id):
		return _same(_cells[segment_id].audit, _compact_report(report)) or _fail("CELL_ALREADY_COMMITTED_WITH_DIFFERENT_DATA")
	var expected: Dictionary = _next_cell()
	if expected.is_empty() or expected.cell_id != segment_id or not segment_id in _ready_cells:
		return _fail("UNPLANNED_OR_OUT_OF_ORDER_CELL")
	if not _conditions_ok(conditions):
		_interrupt_at("configuration_hash_change", unix)
		return _fail("CELL_CONDITIONS_CHANGED")
	var gain_hex: String = _candidate_hex(str(expected.candidate_id))
	if _actual_gain_hex(conditions) != gain_hex or _reported_gain_hex(report) != gain_hex:
		_interrupt_at("configuration_hash_change", unix)
		return _fail("CELL_ACTUAL_GAIN_MISMATCH")
	var audit: Dictionary = _compact_report(report)
	if not _task_valid(expected, audit):
		return _fail("CELL_REPORT_INVALID")
	var actual_start_s: float = float(report.get("actual_start_s", float(expected.scored_start_s) + float(_preflight.generation) * 84.0 + _wait_total()))
	var actual_end_s: float = float(report.get("actual_end_s", unix - _started_unix))
	if not _finite(actual_start_s) or not _finite(actual_end_s) or actual_start_s < float(expected.scored_start_s) or actual_end_s - actual_start_s < 24.0 or actual_end_s > unix - _started_unix + 0.000001:
		return _fail("CELL_ACTUAL_TIMESTAMPS_INVALID")
	var cell: Dictionary = expected.duplicate(true)
	cell["complete"] = true
	cell["duration_s"] = 24.0
	cell["actual_start_s"] = actual_start_s
	cell["actual_end_s"] = actual_end_s
	cell["utility"] = float(audit.utility)
	cell["render_quality"] = audit.render_quality.duplicate(true)
	cell["applied_gain"] = _candidate(str(expected.candidate_id)).degrees_per_relative_input_unit.duplicate(true)
	cell["audit"] = audit
	if expected.task in ["CLICK", "SWITCH"]:
		cell["opportunities"] = int(audit.opportunities)
		cell["success_count"] = int(audit.get("success_count", audit.get("raw_succeeded", audit.get("click_successes" if expected.task == "CLICK" else "switch_completions", -1))))
	var report_id: String = _calibration_id + "." + segment_id
	if _pending_task.is_empty():
		_pending_task = {"segment_id": segment_id, "report_id": report_id, "cell": cell,
			"report": _storage_report(report_id, "cell", {"plan_sha256": plan.plan_sha256, "epoch_sha256": _epoch.epoch_sha256, "cell": cell})}
	elif _pending_task.segment_id != segment_id or not _same(_pending_task.cell.audit, audit):
		return _fail("OTHER_CELL_COMMIT_PENDING")
	if not _store.save_report(_pending_task.report):
		return _fail("CELL_REPORT_SAVE_FAILED:" + _store.last_error)
	var checkpoint: Dictionary = _checkpoint()
	checkpoint.cells[segment_id] = _pending_task.cell
	if not audit.trace_reference.session_id in checkpoint.report_ids:
		checkpoint.report_ids.append(audit.trace_reference.session_id)
	if not report_id in checkpoint.report_ids:
		checkpoint.report_ids.append(report_id)
	if not _save(checkpoint, baseline_profile, "active", int(_epoch.session.day_role), int(_epoch.session.attempt_epoch)):
		return false
	_cells = checkpoint.cells
	_report_ids = checkpoint.report_ids
	_pending_task = {}
	return true


func finish_day(now_unix: float, local_date: String) -> Dictionary:
	error = ""
	if not active and _pending_day.is_empty():
		_fail("NO_ACTIVE_DAY")
		return {}
	if not _finite(now_unix) or not _date_valid(local_date):
		_fail("INVALID_FINISH_LOCAL_DATE")
		return {}
	if _pending_day.is_empty():
		if not _pending_task.is_empty() or not _preflight.reviewed or _cells.size() != _cell_count() or not _finite(now_unix) or now_unix - _started_unix < float(_epoch.session.planned_duration_s) + float(_preflight.generation) * 84.0 + _wait_total():
			_fail("DAY_INCOMPLETE_OR_COMMIT_PENDING")
			return {}
		var report: Dictionary = _day_report(now_unix, true, [])
		var prepared: Dictionary = _prepare_day_commit(report)
		if not prepared.get("ok", false):
			_fail(str(prepared.get("error", "DAY_REPORT_INVALID")))
			return {}
		_pending_day = prepared
	_restore_gain()
	if not _commit_day(_pending_day):
		return {}
	var finished: Dictionary = _pending_day.report.duplicate(true)
	finished["result"] = result.duplicate(true)
	finished["eligible"] = _pending_day.eligibility.eligible
	_pending_day = {}
	return finished


func interrupt(reason: String) -> bool:
	return _interrupt_at(reason, _clock_unix())


func _interrupt_at(reason: String, now_unix: float) -> bool:
	error = ""
	_restore_gain()
	if not active:
		return true
	if not _finite(now_unix) or now_unix < _started_unix:
		active = false
		return _fail("CLOCK_DISCONTINUITY_DURING_INTERRUPTION")
	var report: Dictionary = _day_report(now_unix, false, [{"kind": _event_kind(reason), "reason": reason, "received_unix": now_unix}])
	var prepared: Dictionary = _prepare_day_commit(report)
	if not prepared.get("ok", false):
		active = false
		return _fail(str(prepared.get("error", "INTERRUPTED_DAY_INVALID")))
	_pending_day = prepared
	active = false
	if not _commit_day(prepared):
		return false
	_pending_day = {}
	return true


func recover() -> bool:
	error = ""
	active = false
	var state: Dictionary = _store.load_calibration_state()
	var state_error: String = _store.last_error
	baseline_profile = _store.load_profile()
	_restore_gain()
	if state.is_empty():
		if not state_error.is_empty() or not _store.last_error.is_empty():
			return _fail("STORE_RECOVERY_FAILED:" + state_error + _store.last_error)
		return true
	var checkpoint: Variant = state.get("checkpoint")
	if not Store._closed(checkpoint, CHECKPOINT_FIELDS, CHECKPOINT_FIELDS) or checkpoint.runner_version != VERSION:
		return _fail("RUNNER_CHECKPOINT_INVALID")
	for field in ["plan", "epoch", "cells", "result", "express_context", "preflight", "recovery_context"]:
		if not checkpoint[field] is Dictionary:
			return _fail("RUNNER_CHECKPOINT_INVALID")
	for field in ["reports", "report_ids", "waits", "ready_cells"]:
		if not checkpoint[field] is Array:
			return _fail("RUNNER_CHECKPOINT_INVALID")
	if not _finite(checkpoint.started_unix) or not _finite(checkpoint.last_elapsed_s) or checkpoint.started_unix < 0.0 or checkpoint.last_elapsed_s < 0.0 or not checkpoint.local_date is String:
		return _fail("RUNNER_CHECKPOINT_INVALID")
	if not checkpoint.stage is String or not checkpoint.stage in ["prepared", "active", "express_complete", "complete", "awaiting_day2", "interrupted", "preflight_refreeze_pending"] or not checkpoint.previous_plan_sha256 is String:
		return _fail("RUNNER_CHECKPOINT_INVALID")
	if checkpoint.stage in ["active", "preflight_refreeze_pending"] and checkpoint.epoch.is_empty():
		return _fail("RUNNER_CHECKPOINT_ACTIVE_EPOCH_MISSING")
	if checkpoint.calibration_id != state.calibration_id or checkpoint.plan.get("plan_sha256") != state.plan_sha256 or not _same(checkpoint.report_ids, state.report_ids):
		return _fail("RUNNER_CHECKPOINT_IDENTITY_MISMATCH")
	var validation: Dictionary = Calibration.validate_plan(checkpoint.plan)
	if not validation.get("ok", false) or validation.get("is_example", true):
		return _fail("RUNNER_PLAN_INVALID_OR_EXAMPLE")
	if not checkpoint.epoch.is_empty() and not Calibration.validate_day_epoch(checkpoint.plan, checkpoint.epoch).get("ok", false):
		return _fail("RUNNER_EPOCH_INVALID")
	baseline_profile = state.baseline_profile.duplicate(true)
	Calibration._freeze(baseline_profile)
	_restore_checkpoint(checkpoint)
	_restore_gain()
	active = false
	if not _preflight_valid():
		active = false
		return _fail("RECOVERED_PREFLIGHT_INVALID")
	for previous_value: Variant in _reports:
		if not previous_value is Dictionary or not Store._integer(previous_value.get("day_role"), 0, 2) or not Store._integer(previous_value.get("attempt_epoch"), 0, 1):
			active = false
			return _fail("RECOVERED_EPOCH_REPORT_INVALID")
		var previous: Dictionary = previous_value
		var built: Dictionary = Calibration.create_day_epoch(plan, int(previous.day_role), int(previous.attempt_epoch))
		var verified: Dictionary = Calibration.validate_epoch_report(plan, built.get("epoch", {}), previous) if built.get("ok", false) else built
		if not verified.get("ok", false):
			return _fail("RECOVERED_EPOCH_REPORT_INVALID")
		previous["eligibility"] = {"complete": verified.complete, "eligible": verified.eligible, "reasons": verified.reasons.duplicate()}
	if not _checkpoint_trace_links_valid():
		active = false
		return _fail("RECOVERED_AUDIT_REFERENCE_INVALID")
	if _stage in ["active", "preflight_refreeze_pending"]:
		active = true
		if not _recover_active_epoch():
			return false
	active = false
	return true


func ui_state(now_unix: float, local_date: String, utc_offset_minutes: Variant = null) -> Dictionary:
	var calendar_conditions: Dictionary = {"player_utc_offset_minutes": Time.get_time_zone_from_system().get("bias", 0) if utc_offset_minutes == null else utc_offset_minutes}
	var status: Dictionary = {"ready": error.is_empty() and not baseline_profile.is_empty(), "active": active, "stage": _stage,
		"phase": plan.get("phase", ""), "profile_locked": not plan.is_empty(), "result": result.duplicate(true),
		"can_start_express": plan.is_empty() and not baseline_profile.is_empty(), "can_start_confirmation": false,
		"can_continue": false, "can_apply": false, "wait_remaining_s": 0.0, "notice": error,
		"baseline_profile": baseline_profile.duplicate(true), "candidate": {}, "budgets": Calibration.protocol().get("duration_s", {})}
	status["preflight"] = _preflight_ui()
	status["can_cancel"] = not plan.is_empty()
	if active:
		if _gate.get("kind") == "preflight":
			status["stage"] = "preflight_review"
		status["can_continue"] = not _gate.is_empty()
		status["continue_label"] = "Je suis prêt · tester le niveau proposé" if not _preflight.pending_adjustment.is_empty() else "Conserver ces niveaux et continuer" if _gate.get("kind") == "preflight" else "Je suis prêt · démarrer le décompte"
		if _gate.get("kind") == "preflight":
			status["can_continue"] = _preflight.reports.size() == 4 and (_preflight.pending_adjustment.is_empty() or not _preflight.pending_adjustment.started) and _preflight.transition.is_empty()
		status["segment_id"] = _gate.get("segment_id", "")
		status["task"] = _last_snapshot.get("task", "")
		status["kind"] = _last_snapshot.get("kind", "preflight")
		status["remaining_s"] = maxf(float(_last_snapshot.get("end_s", 0.0)) - _last_elapsed_s, 0.0)
		return status
	if not plan.is_empty():
		var role: int = 0 if plan.phase == "express" else 1 if _accepted_report(1).is_empty() else 2
		var window: Dictionary = _window(role, now_unix, local_date, calendar_conditions)
		status["next_day_role"] = role
		status["day_label"] = "Express" if role == 0 else "Jour " + str(role)
		status["wait_remaining_s"] = maxf(float(window.get("not_before_unix", now_unix)) - now_unix, 0.0)
		status["continue_reason"] = str(window.get("error", ""))
		status["can_continue"] = window.ok and _accepted_report(role).is_empty() and _role_reports(role).size() < 2 and _pending_day.is_empty() and _preflight.get("transition", {}).is_empty()
		if plan.phase == "express" and not _accepted_report(0).is_empty():
			var confirmation_window: Dictionary = _window(1, now_unix, local_date, calendar_conditions)
			status["can_start_confirmation"] = confirmation_window.ok and result.get("uninformative_tasks", []).is_empty()
			status["wait_remaining_s"] = maxf(float(confirmation_window.get("not_before_unix", now_unix)) - now_unix, 0.0)
		elif plan.phase == "confirmation" and result.get("status") == "repeated_improvement" and not _accepted_report(2).is_empty():
			status["can_apply"] = true
			status["candidate"] = _candidate(str(plan.confirmation_selection.challenger_candidate_id)).duplicate(true)
	return status


func _prepare_day_commit(report: Dictionary, storage_identity: String = "") -> Dictionary:
	var eligibility: Dictionary = Calibration.validate_epoch_report(plan, _epoch, report)
	if not eligibility.get("ok", false):
		return eligibility
	report["eligibility"] = {"complete": eligibility.complete, "eligible": eligibility.eligible, "reasons": eligibility.reasons.duplicate()}
	var reports: Array = _reports.duplicate(true)
	reports.append(report)
	var comparison: Dictionary = Calibration.compare_epochs(plan, reports, _express_context.get("actual_end_utc", null))
	if comparison.get("ok", true) == false:
		return comparison
	var report_id: String = storage_identity if not storage_identity.is_empty() else _calibration_id + "." + str(_epoch.session.session_id)
	return {"ok": true, "report": report, "report_id": report_id, "reports": reports, "result": comparison,
		"eligibility": eligibility, "storage_report": _storage_report(report_id, "epoch", {"epoch_report": report, "comparison_result": comparison})}


func _commit_day(prepared: Dictionary) -> bool:
	if not _store.save_report(prepared.storage_report):
		return _fail("DAY_REPORT_SAVE_FAILED:" + _store.last_error)
	var checkpoint: Dictionary = _checkpoint()
	checkpoint["reports"] = prepared.reports
	checkpoint["result"] = prepared.result
	checkpoint["stage"] = "express_complete" if plan.phase == "express" and prepared.eligibility.eligible else "complete" if plan.phase == "confirmation" and prepared.result.get("accepted_epoch_by_day_role", {}).has("2") else "awaiting_day2" if prepared.eligibility.eligible else "interrupted"
	if not prepared.report_id in checkpoint.report_ids:
		checkpoint.report_ids.append(prepared.report_id)
	if not _save(checkpoint, baseline_profile, "complete" if prepared.eligibility.eligible else "interrupted", int(_epoch.session.day_role), int(_epoch.session.attempt_epoch)):
		return false
	_restore_checkpoint(checkpoint)
	active = false
	_restore_gain()
	return true


func _day_report(now_unix: float, complete: bool, technical_events: Array) -> Dictionary:
	var cells: Array = []
	for period: Dictionary in _epoch.session.periods:
		for expected: Dictionary in period.scored_cells:
			if _cells.has(expected.cell_id):
				cells.append(_cells[expected.cell_id].duplicate(true))
	var report: Dictionary = {"plan_sha256": plan.plan_sha256, "epoch_sha256": _epoch.epoch_sha256,
		"condition_snapshot_sha256": plan.condition_snapshot_sha256, "session_id": _epoch.session.session_id,
		"day_role": _epoch.session.day_role, "attempt_epoch": _epoch.session.attempt_epoch,
		"actual_start_utc": _started_unix, "actual_end_utc": now_unix, "player_local_date": _local_date,
		"complete": complete, "cells": cells, "waits": _waits.duplicate(true), "technical_events": technical_events,
		"timestamp_source": "controller_received_unix_and_monotonic_relative_timeline", "scanout_measured": false,
		"preflight": _preflight.duplicate(true), "report_ids": _report_ids.duplicate(), "additional_familiarization_s": float(_preflight.generation) * 84.0,
		"recovery_context": _recovery_context.duplicate(true)}
	if _utc_offset_minutes != null:
		report["player_utc_offset_minutes"] = _utc_offset_minutes
	return report


func _recover_active_epoch() -> bool:
	_restore_gain()
	var inventory: Dictionary = _uncommitted_inventory()
	if not inventory.get("ok", false):
		active = false
		return _fail(str(inventory.get("error", "UNCOMMITTED_CALIBRATION_AUDIT_INVALID")))
	_report_ids = inventory.report_ids
	_recovery_context = inventory.context
	var identity: String = _calibration_id + "." + str(_epoch.session.session_id) + ".recovery"
	var saved: Dictionary = _store._read_document(_store.root_path.path_join("reports").path_join(identity + ".json"), "report")
	if not saved.get("ok", false):
		active = false
		return _fail("RECOVERY_REPORT_INVALID")
	var report: Dictionary
	if saved.get("missing", true):
		var unix: float = _clock_unix()
		if not _finite(unix) or unix < _started_unix:
			active = false
			return _fail("CLOCK_DISCONTINUITY_DURING_RECOVERY")
		report = _day_report(unix, false, [{"kind": "process_restart", "reason": "process_restart", "received_unix": unix}])
	else:
		if not _epoch_storage_valid(saved.payload, identity):
			active = false
			return _fail("RECOVERY_REPORT_INVALID")
		report = saved.payload.payload.epoch_report.duplicate(true)
		var has_restart: bool = false
		for event: Dictionary in report.technical_events:
			if event.kind == "process_restart":
				has_restart = true
		if report.complete or not has_restart or not _same(report.cells, _day_report(float(report.actual_end_utc), false, []).cells) or not _same(report.get("recovery_context", {}), _recovery_context):
			active = false
			return _fail("RECOVERY_REPORT_CHECKPOINT_MISMATCH")
	var prepared: Dictionary = _prepare_day_commit(report, identity)
	if not prepared.get("ok", false):
		active = false
		return _fail(str(prepared.get("error", "RECOVERY_EPOCH_INVALID")))
	_pending_day = prepared
	active = false
	if not _commit_day(prepared):
		return false
	_pending_day = {}
	return true


func _uncommitted_inventory() -> Dictionary:
	var ids: Array = _report_ids.duplicate()
	var orphan_cells: Array = []
	for period: Dictionary in _epoch.session.periods:
		for expected: Dictionary in period.scored_cells:
			var identity: String = _calibration_id + "." + str(expected.cell_id)
			if identity in ids:
				continue
			var saved: Dictionary = _store._read_document(_store.root_path.path_join("reports").path_join(identity + ".json"), "report")
			if not saved.get("ok", false):
				return {"ok": false, "error": "UNCOMMITTED_CELL_DOCUMENT_INVALID"}
			if saved.get("missing", true):
				continue
			var wrapper: Dictionary = saved.payload
			var cell: Variant = wrapper.get("payload", {}).get("cell")
			if wrapper.get("session_id") != identity or wrapper.get("kind") != "calibration_cell" or wrapper.get("plan_sha256") != plan.plan_sha256 or wrapper.get("payload", {}).get("plan_sha256") != plan.plan_sha256 or wrapper.get("payload", {}).get("epoch_sha256") != _epoch.epoch_sha256 or not cell is Dictionary or cell.get("cell_id") != expected.cell_id or not cell.get("audit") is Dictionary:
				return {"ok": false, "error": "UNCOMMITTED_CELL_IDENTITY_INVALID"}
			if cell.get("candidate_id") != expected.candidate_id or cell.get("condition_snapshot_sha256") != plan.condition_snapshot_sha256 or not _same(cell.get("applied_gain"), _candidate(str(expected.candidate_id)).degrees_per_relative_input_unit) or not _task_valid(expected, cell.audit) or not _audit_trace_valid(cell.audit):
				return {"ok": false, "error": "UNCOMMITTED_CELL_FULL_AUDIT_INVALID"}
			var trace_id: String = cell.audit.trace_reference.session_id
			if not trace_id in ids:
				ids.append(trace_id)
			ids.append(identity)
			orphan_cells.append(identity)
	var footer_id: String = _calibration_id + "." + str(_epoch.session.session_id)
	var footer: Dictionary = _store._read_document(_store.root_path.path_join("reports").path_join(footer_id + ".json"), "report")
	if not footer.get("ok", false):
		return {"ok": false, "error": "UNCOMMITTED_EPOCH_DOCUMENT_INVALID"}
	var footer_reference: Variant = null
	if not footer.get("missing", true) and not footer_id in ids:
		if not _epoch_storage_valid(footer.payload, footer_id):
			return {"ok": false, "error": "UNCOMMITTED_EPOCH_IDENTITY_INVALID"}
		for cell: Dictionary in footer.payload.payload.epoch_report.cells:
			if not cell.get("audit") is Dictionary or not _audit_trace_valid(cell.audit):
				return {"ok": false, "error": "UNCOMMITTED_EPOCH_FULL_AUDIT_INVALID"}
			var trace_id: String = cell.audit.trace_reference.session_id
			if not trace_id in ids:
				ids.append(trace_id)
		ids.append(footer_id)
		footer_reference = {"session_id": footer_id, "semantic_sha256": Canonical.semantic_sha256(footer.payload)}
	return {"ok": true, "report_ids": ids, "context": {"uncommitted_cell_ids": orphan_cells,
		"uncommitted_epoch_reference": footer_reference, "partial_scores_reused": false}}


func _epoch_storage_valid(wrapper: Dictionary, identity: String) -> bool:
	if wrapper.get("session_id") != identity or wrapper.get("kind") != "calibration_epoch" or wrapper.get("plan_sha256") != plan.plan_sha256 or wrapper.get("condition_snapshot_sha256") != plan.condition_snapshot_sha256 or not wrapper.get("payload") is Dictionary or not wrapper.payload.get("epoch_report") is Dictionary:
		return false
	return Calibration.validate_epoch_report(plan, _epoch, wrapper.payload.epoch_report).get("ok", false)


func _window(role: int, now_unix: float, local_date: String, conditions: Dictionary) -> Dictionary:
	if not _finite(now_unix) or now_unix < 0.0 or not _date_valid(local_date):
		return {"ok": false, "error": "INVALID_CALENDAR_TIMESTAMP_OR_LOCAL_DATE"}
	var proposed: Dictionary = {"actual_start_utc": now_unix, "player_local_date": local_date}
	if conditions.has("player_utc_offset_minutes"):
		proposed["player_utc_offset_minutes"] = conditions.player_utc_offset_minutes
	var express_end: Variant = _express_context.get("actual_end_utc", null)
	if plan.get("phase") == "express" and not _accepted_report(0).is_empty():
		express_end = _accepted_report(0).actual_end_utc
	if role == 0:
		return Calibration.validate_day_window(proposed)
	if express_end == null:
		return {"ok": false, "error": "COMPLETE_VALID_EXPRESS_REQUIRED"}
	var not_before: float = float(express_end) + 43200.0
	if role == 1:
		var validation: Dictionary = Calibration.validate_day_window(proposed, {}, express_end)
		validation["not_before_unix"] = not_before
		return validation
	var first: Dictionary = _accepted_report(1)
	if first.is_empty():
		return {"ok": false, "error": "ACCEPTED_DAY1_REQUIRED"}
	var validation: Dictionary = Calibration.validate_day_window(first, proposed, express_end)
	validation["not_before_unix"] = float(first.actual_start_utc) + 43200.0
	validation["latest_unix"] = float(first.actual_start_utc) + 604800.0
	return validation


func _conditions_ok(conditions: Dictionary) -> bool:
	return Calibration.validate_conditions(plan, _fixed_conditions(conditions)).get("ok", false)


static func _fixed_conditions(conditions: Dictionary) -> Dictionary:
	var result: Dictionary = _portable(conditions)
	for field in ["gain_hex", "gain_deg_per_relative_unit", "applied_gain", "degrees_per_relative_input_unit", "player_utc_offset_minutes"]:
		result.erase(field)
	return result


static func _actual_gain_hex(conditions: Dictionary) -> String:
	var bits: Variant = conditions.get("gain_hex")
	if not Store._hex(bits, 16):
		return ""
	var gain: float = Canonical.float64_from_hex(bits)
	return bits if is_finite(gain) and gain > 0.0 else ""


func _candidate(identity: String) -> Dictionary:
	for candidate: Dictionary in plan.get("candidates", []):
		if candidate.candidate_id == identity:
			return candidate
	return {}


func _candidate_hex(identity: String) -> String:
	return str(_candidate(identity).get("degrees_per_relative_input_unit", {}).get("ieee754_binary64_big_endian_hex", ""))


func _baseline_gain() -> float:
	return Canonical.float64_from_hex(str(baseline_profile.get("gain_hex", ""))) if not baseline_profile.is_empty() else 0.0


func _restore_gain() -> void:
	temporary_gain_deg_per_relative_unit = _baseline_gain()


func _role_reports(role: int) -> Array:
	var reports: Array = []
	for report: Dictionary in _reports:
		if int(report.day_role) == role:
			reports.append(report)
	return reports


func _accepted_report(role: int) -> Dictionary:
	for report: Dictionary in _role_reports(role):
		if report.get("eligibility", {}).get("eligible", false):
			return report
	return {}


func _next_cell() -> Dictionary:
	for period: Dictionary in _epoch.get("session", {}).get("periods", []):
		for cell: Dictionary in period.scored_cells:
			if not _cells.has(cell.cell_id):
				return cell
	return {}


func _cell_count() -> int:
	var count: int = 0
	for period: Dictionary in _epoch.session.periods:
		count += period.scored_cells.size()
	return count


func _wait_total() -> float:
	var total: float = 0.0
	for wait_record: Dictionary in _waits:
		total += float(wait_record.end_s) - float(wait_record.start_s)
	return total


func _decorate(segment: Dictionary, blocked: bool) -> Dictionary:
	var result: Dictionary = segment.duplicate()
	var bits: String = _candidate_hex(str(segment.candidate_id))
	result["gain_hex"] = bits
	result["gain"] = Canonical.float64_from_hex(bits)
	result["blocked"] = blocked
	result["active_elapsed_s"] = _last_elapsed_s
	result["sample_s"] = _last_elapsed_s
	result["time_origin"] = segment.get("time_origin", segment.start_s)
	temporary_gain_deg_per_relative_unit = float(result.gain)
	return result


func _build_segments() -> void:
	_segments = []
	if _epoch.is_empty():
		return
	var extra_s: float = float(_preflight.get("generation", 0)) * 84.0
	var familiarization_prefix: String = _epoch.session.session_id + (".f%d" % int(_preflight.generation) if int(_preflight.generation) > 0 else "")
	for source: Dictionary in _epoch.session.preflight.tasks:
		_segments.append(_segment("preflight", familiarization_prefix + ".preflight." + source.task, float(source.start_s) + extra_s, float(source.end_s) + extra_s, "A", source))
	for period: Dictionary in _epoch.session.periods:
		for source: Dictionary in period.acclimation.task_segments:
			_segments.append(_segment("acclimation", _epoch.session.session_id + ".p%d.warmup.%s" % [int(period.period_index), str(source.task)], float(source.start_s) + extra_s, float(source.end_s) + extra_s, period.candidate_id, source))
		for cell: Dictionary in period.scored_cells:
			_segments.append(_segment("countdown", cell.cell_id, float(cell.countdown_start_s) + extra_s, float(cell.scored_start_s) + extra_s, cell.candidate_id, cell))
			_segments.append(_segment("measurement", cell.cell_id, float(cell.scored_start_s) + extra_s, float(cell.scored_end_s) + extra_s, cell.candidate_id, cell))
			_segments.append(_segment("recovery", cell.cell_id, float(cell.scored_end_s) + extra_s, float(cell.recovery_end_s) + extra_s, cell.candidate_id, cell))
	for index: int in _epoch.session.interperiod_rests.size():
		var rest: Dictionary = _epoch.session.interperiod_rests[index]
		_segments.append(_segment("rest", _epoch.session.session_id + ".rest%d" % index, float(rest.start_s) + extra_s, float(rest.end_s) + extra_s, rest.gain_candidate_id, {}))
	_segments.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.start_s) < float(second.start_s))


func _segment(kind: String, identity: String, start_s: float, end_s: float, candidate_id: String, source: Dictionary) -> Dictionary:
	var segment: Dictionary = {"kind": kind, "segment_id": identity, "start_s": start_s, "end_s": end_s,
		"time_origin": start_s, "candidate_id": candidate_id, "scored": kind == "measurement", "task": source.get("task", "")}
	if source.has("deck_id"):
		segment["deck"] = _epoch.decks[source.deck_id]
		segment["deck_manifest_sha256"] = source.deck_manifest_sha256
	return segment


static func _compact_report(report: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in TASK_AUDIT_FIELDS:
		if report.has(field):
			result[field] = _portable(report[field])
	if not result.has("utility") and report.has("U"):
		result["utility"] = report.U
	result["input_trace_retention"] = "immutable_full_report_reference_required"
	var trace: Variant = report.get("received_pose_trace", [])
	result["input_trace_event_count"] = int(trace.get("record_count", 0)) if trace is Dictionary else trace.size() if trace is Array else 0
	return result


static func _empty_preflight() -> Dictionary:
	return {"reports": {}, "reviewed": false, "reviewed_unix": null, "review_proposals": [], "history": [], "validations": [],
		"changes_by_task": {"CLICK": 0, "SMOOTH": 0, "REACTIVE": 0, "SWITCH": 0}, "generation": 0,
		"pending_adjustment": {}, "transition": {}}


func _preflight_valid() -> bool:
	var fields: Array[String] = ["reports", "reviewed", "reviewed_unix", "review_proposals", "history", "validations", "changes_by_task", "generation", "pending_adjustment", "transition"]
	if not Store._closed(_preflight, fields, fields) or not _preflight.reviewed is bool or not Store._integer(_preflight.generation, 0, 8):
		return false
	for field: String in ["reports", "changes_by_task", "pending_adjustment", "transition"]:
		if not _preflight[field] is Dictionary:
			return false
	for field: String in ["history", "validations", "review_proposals"]:
		if not _preflight[field] is Array:
			return false
	if _preflight.reviewed_unix != null and not _finite(_preflight.reviewed_unix):
		return false
	if not Store._closed(_preflight.changes_by_task, Calibration.TASKS, Calibration.TASKS) or _preflight.history.size() != int(_preflight.generation) + (1 if not _preflight.transition.is_empty() else 0) or _preflight.validations.size() > 8:
		return false
	var changes: int = 0
	for task: String in Calibration.TASKS:
		if not Store._integer(_preflight.changes_by_task[task], 0, 2):
			return false
		changes += int(_preflight.changes_by_task[task])
	if changes != _preflight.validations.size() or changes != int(_preflight.generation) + (1 if not _preflight.transition.is_empty() else 0):
		return false
	for task in _preflight.reports:
		if not task in Calibration.TASKS or not _preflight.reports[task] is Dictionary:
			return false
	if _preflight.reviewed and _preflight.reports.size() != 4:
		return false
	for record in _preflight.history:
		if not record is Dictionary or not record.get("reports") is Dictionary:
			return false
		for task in record.reports:
			if not task in Calibration.TASKS or not record.reports[task] is Dictionary:
				return false
	for record in _preflight.validations:
		if not record is Dictionary or not record.get("audit") is Dictionary or not record.get("task") in Calibration.TASKS or record.get("duration_s") != 24.0:
			return false
	if not _preflight.pending_adjustment.is_empty():
		var pending: Dictionary = _preflight.pending_adjustment
		if not pending.get("started") is bool or not pending.get("task") in Calibration.TASKS or not pending.get("deck") is Dictionary or not _finite(pending.get("start_s")) or not _finite(pending.get("end_s")) or pending.end_s - pending.start_s != 24.0:
			return false
		if pending.started and not _finite(pending.get("actual_start_unix")):
			return false
	return true


func _preflight_ui() -> Dictionary:
	var proposals: Array = []
	var records: Dictionary = {}
	var levels: Dictionary = plan.get("condition_snapshot", {}).get("difficulty_by_task", {})
	var comparison_started: bool = not _cells.is_empty() or not _reports.is_empty() or plan.get("phase") != "express"
	for task: String in Calibration.TASKS:
		var report: Dictionary = _preflight.get("reports", {}).get(task, {})
		var utility: Variant = report.get("diagnostic_utility")
		if not report.is_empty():
			records[task] = {"task": task, "difficulty": levels.get(task, "standard"), "diagnostic_utility": utility,
				"opportunities": report.get("opportunities"), "duration_s": report.get("duration_s"), "complete": report.get("complete"),
				"trace_reference": report.get("trace_reference", {}).duplicate(true)}
		if not _finite(utility) or (utility >= 0.10 and utility <= 0.95):
			continue
		var current: String = str(levels.get(task, "standard"))
		var ordered: Array[String] = ["novice", "standard", "advanced"]
		var target_index: int = ordered.find(current) + (-1 if utility < 0.10 else 1)
		var suggested: String = ordered[target_index] if target_index >= 0 and target_index < 3 else ""
		var count: int = int(_preflight.get("changes_by_task", {}).get(task, 0))
		proposals.append({"task": task, "diagnostic_utility": utility, "current_level": current, "suggested_level": suggested,
			"changes_used": count, "changes_remaining": 2 - count, "validation_duration_s": 24.0,
			"can_adjust": not comparison_started and count < 2 and not suggested.is_empty(),
			"configuration_review_required": count >= 2 or suggested.is_empty(), "levels_frozen": comparison_started,
			"scientific_player_level_measurement": false})
	return {"required": not _preflight.get("reviewed", false), "reports_received": _preflight.get("reports", {}).size(),
		"records": records, "proposals": proposals, "changes_by_task": _preflight.get("changes_by_task", {}).duplicate(),
		"pending_adjustment": _preflight.get("pending_adjustment", {}).duplicate(true),
		"additional_validation_s": float(_preflight.get("validations", []).size()) * 24.0,
		"additional_warmup_s": float(_preflight.get("generation", 0)) * 60.0,
		"levels_frozen": comparison_started, "requires_new_express": not _preflight.get("transition", {}).is_empty()}


func _append_review_wait(checkpoint: Dictionary, unix: float) -> bool:
	var start_s: float = float(_gate.start_s) + _wait_total()
	var end_s: float = unix - _started_unix
	if not _finite(unix) or end_s < start_s - 0.000001:
		return _fail("PREFLIGHT_REVIEW_CLOCK_INVALID")
	if end_s - start_s > 900.0:
		_interrupt_at("long_unplanned_interruption", unix)
		return _fail("PREFLIGHT_REVIEW_WAIT_EXCEEDED")
	if end_s > start_s:
		checkpoint.waits.append({"start_s": start_s, "end_s": end_s, "planned": false, "gain_hex": baseline_profile.gain_hex, "reason": "preflight_review_and_optional_level_validation"})
	return true


func _diagnostic_valid(expected: Dictionary, report: Dictionary, duration_s: float) -> bool:
	if not Store._json_value(_portable(report)) or report.get("task") != expected.task or report.get("task_id") != expected.deck.task_id or report.get("deck_id") != expected.deck.deck_id or report.get("deck_manifest_sha256") != expected.deck.manifest_sha256:
		return false
	if report.get("duration_s") != duration_s or report.get("complete") != true or not report.get("complete") is bool or report.get("valid") != true or not report.get("valid") is bool or report.get("comparative_utility_included") != false:
		return false
	if report.get("utility") != null or report.get("U") != null or not _finite(report.get("diagnostic_utility")) or report.diagnostic_utility < 0.0 or report.diagnostic_utility > 1.0 or _reported_gain_hex(report) != baseline_profile.gain_hex:
		return false
	if expected.task in ["CLICK", "SWITCH"]:
		var count: int = (10 if expected.task == "CLICK" else 7) if duration_s == 15.0 else (16 if expected.task == "CLICK" else 12)
		var successes: Variant = report.get("success_count", report.get("raw_succeeded"))
		if not Store._integer(report.get("opportunities"), count, count) or not Store._integer(successes, 0, count) or float(report.diagnostic_utility) > float(successes) / count + 1.0e-9:
			return false
	return true


static func _reported_gain_hex(report: Dictionary) -> String:
	var applied: Variant = report.get("applied_gain")
	var declared: String = ""
	if report.get("conditions") is Dictionary:
		declared = _actual_gain_hex(report.conditions)
	if applied is Dictionary and not applied.is_empty():
		var applied_hex: String = str(applied.get("ieee754_binary64_big_endian_hex", ""))
		if not Store._hex(applied_hex, 16) or (not declared.is_empty() and declared != applied_hex):
			return ""
		return applied_hex
	return declared


func _save_diagnostic_trace(segment_id: String, report: Dictionary) -> Dictionary:
	if report.has("trace_reference"):
		if not _trace_link_valid(report):
			_fail("FAMILIARIZATION_FULL_AUDIT_REFERENCE_INVALID")
			return {}
		return _portable(report)
	var complete_report: Dictionary = _portable(report)
	complete_report["session_id"] = "trace_" + _calibration_id + "." + segment_id
	complete_report["catalogue_revision"] = Calibration.REVISION
	complete_report["score_version"] = "cal_utilities_R2"
	if not _store.save_report(complete_report):
		_fail("FAMILIARIZATION_FULL_AUDIT_SAVE_FAILED:" + _store.last_error)
		return {}
	complete_report["trace_reference"] = {"session_id": complete_report.session_id, "semantic_sha256": Canonical.semantic_sha256(complete_report)}
	return complete_report


func _read_trace(reference: Variant) -> Dictionary:
	var fields: Array[String] = ["session_id", "semantic_sha256"]
	if not Store._closed(reference, fields, fields) or not Store._identifier(reference.session_id) or not Store._hex(reference.semantic_sha256, 64):
		return {}
	var saved: Dictionary = _store._read_document(_store.root_path.path_join("reports").path_join(reference.session_id + ".json"), "report")
	if not saved.get("ok", false) or saved.get("missing", true) or saved.payload.get("session_id") != reference.session_id or Canonical.semantic_sha256(saved.payload) != reference.semantic_sha256:
		return {}
	return saved.payload


func _trace_link_valid(report: Dictionary) -> bool:
	var saved: Dictionary = _read_trace(report.get("trace_reference"))
	if saved.is_empty():
		return false
	var unsigned: Dictionary = _portable(report)
	unsigned.erase("trace_reference")
	return _same(unsigned, saved)


func _audit_trace_valid(audit: Dictionary) -> bool:
	var saved: Dictionary = _read_trace(audit.get("trace_reference"))
	if saved.is_empty():
		return false
	saved["trace_reference"] = audit.trace_reference
	return _same(_compact_report(saved), audit)


func _checkpoint_trace_links_valid() -> bool:
	var audits: Array = []
	for cell: Dictionary in _cells.values():
		if not cell.get("audit") is Dictionary:
			return false
		audits.append(cell.audit)
	for report: Dictionary in _reports:
		for cell: Dictionary in report.get("cells", []):
			if not cell.get("audit") is Dictionary:
				return false
			audits.append(cell.audit)
	for audit: Dictionary in _preflight.reports.values():
		audits.append(audit)
	for prior: Dictionary in _preflight.history:
		for audit: Dictionary in prior.reports.values():
			audits.append(audit)
	for validation: Dictionary in _preflight.validations:
		audits.append(validation.audit)
	var verified: Dictionary = {}
	for audit: Dictionary in audits:
		var reference: Variant = audit.get("trace_reference")
		if not reference is Dictionary or not reference.get("session_id") in _report_ids:
			return false
		var digest: String = Canonical.semantic_sha256(audit)
		if verified.has(reference.session_id):
			if verified[reference.session_id] != digest:
				return false
			continue
		if not _audit_trace_valid(audit):
			return false
		verified[reference.session_id] = digest
	return true


static func _task_valid(expected: Dictionary, report: Dictionary) -> bool:
	if not Store._json_value(report) or report.get("task") != expected.task or report.get("task_id") != expected.task_id or report.get("deck_id") != expected.deck_id or report.get("deck_manifest_sha256") != expected.deck_manifest_sha256:
		return false
	if not report.get("complete") is bool or report.complete != true or not report.get("valid") is bool or report.valid != true or not _finite(report.get("duration_s")) or float(report.duration_s) != 24.0:
		return false
	if report.get("comparative_utility_included", true) != true or not _finite(report.get("utility")) or report.utility < 0.0 or report.utility > 1.0 or not report.get("render_quality") is Dictionary:
		return false
	if expected.task in ["CLICK", "SWITCH"]:
		var count: int = 16 if expected.task == "CLICK" else 12
		var succeeded: Variant = report.get("success_count", report.get("raw_succeeded", report.get("click_successes" if expected.task == "CLICK" else "switch_completions")))
		if not Store._integer(report.get("opportunities"), count, count) or not Store._integer(succeeded, 0, count) or float(report.utility) > float(succeeded) / count + 1.0e-9:
			return false
	return true


func _storage_report(identity: String, kind: String, payload: Dictionary) -> Dictionary:
	return {"schema_version": "aimlocal.calibration_runner_report.v2.0", "session_id": identity,
		"catalogue_revision": Calibration.REVISION, "score_version": "cal_utilities_R2", "mechanic_version": VERSION,
		"protocol_id": Calibration.PROTOCOL_ID, "protocol_revision": Calibration.REVISION, "app_version": "1.0.0-V2",
		"engine_version": plan.condition_snapshot.engine_version, "kind": "calibration_" + kind,
		"plan_sha256": plan.plan_sha256, "condition_snapshot_sha256": plan.condition_snapshot_sha256, "payload": payload}


func _checkpoint() -> Dictionary:
	return {"runner_version": VERSION, "calibration_id": _calibration_id, "plan": plan, "stage": _stage,
		"epoch": _epoch, "cells": _cells.duplicate(true), "reports": _reports.duplicate(true), "report_ids": _report_ids.duplicate(),
		"started_unix": _started_unix, "local_date": _local_date, "utc_offset_minutes": _utc_offset_minutes,
		"waits": _waits.duplicate(true), "ready_cells": _ready_cells.duplicate(), "last_elapsed_s": _last_elapsed_s,
		"result": result.duplicate(true), "express_context": _express_context.duplicate(true), "previous_plan_sha256": _previous_plan_sha256,
		"preflight": _preflight.duplicate(true), "recovery_context": _recovery_context.duplicate(true)}


static func _empty_checkpoint(new_plan: Dictionary, identity: String) -> Dictionary:
	return {"runner_version": VERSION, "calibration_id": identity, "plan": new_plan, "stage": "prepared", "epoch": {},
		"cells": {}, "reports": [], "report_ids": [], "started_unix": 0.0, "local_date": "", "utc_offset_minutes": null,
		"waits": [], "ready_cells": [], "last_elapsed_s": 0.0, "result": {}, "express_context": {}, "previous_plan_sha256": "", "preflight": _empty_preflight(), "recovery_context": {}}


func _save(checkpoint: Dictionary, baseline: Dictionary, status: String, role: int, epoch_index: int) -> bool:
	var state: Dictionary = {"schema_version": Store.CALIBRATION_SCHEMA, "calibration_id": checkpoint.calibration_id,
		"protocol_id": Calibration.PROTOCOL_ID, "protocol_revision": Calibration.REVISION,
		"plan_sha256": checkpoint.plan.plan_sha256, "day_role": "express" if role == 0 else "day" + str(role),
		"epoch": epoch_index, "status": status, "baseline_profile": baseline,
		"temporary_gain_hex": null, "checkpoint": checkpoint, "report_ids": checkpoint.report_ids}
	if not _store.save_calibration_state(state):
		return _fail("CALIBRATION_CHECKPOINT_SAVE_FAILED:" + _store.last_error)
	var committed: Dictionary = _store._calibration_document()
	if not committed.get("ok", false) or committed.get("payload") == null:
		return _fail("CALIBRATION_CHECKPOINT_READBACK_FAILED")
	checkpoint["report_ids"] = committed.payload.report_ids.duplicate()
	return true


func _restore_checkpoint(checkpoint: Dictionary) -> void:
	_calibration_id = checkpoint.calibration_id
	plan = checkpoint.plan.duplicate(true)
	Calibration._freeze(plan)
	_stage = checkpoint.stage
	_epoch = checkpoint.epoch.duplicate(true)
	Calibration._freeze(_epoch)
	_cells = checkpoint.cells.duplicate(true)
	_reports = checkpoint.reports.duplicate(true)
	_report_ids = checkpoint.report_ids.duplicate()
	_started_unix = float(checkpoint.started_unix)
	_local_date = checkpoint.local_date
	_utc_offset_minutes = checkpoint.utc_offset_minutes
	_waits = checkpoint.waits.duplicate(true)
	_ready_cells = checkpoint.ready_cells.duplicate()
	_last_elapsed_s = float(checkpoint.last_elapsed_s)
	result = checkpoint.result.duplicate(true)
	_express_context = checkpoint.express_context.duplicate(true)
	_previous_plan_sha256 = checkpoint.previous_plan_sha256
	_preflight = checkpoint.preflight.duplicate(true)
	_recovery_context = checkpoint.recovery_context.duplicate(true)
	active = _stage == "active"
	_gate = {}
	_last_snapshot = {}
	_build_segments()


static func _portable(value: Variant) -> Variant:
	return Calibration._portable_keys(value)


static func _event_kind(reason: String) -> String:
	if reason in ["focus_lost", "focus_loss"]:
		return "focus_loss"
	if reason in ["process_restart", "abort", "long_unplanned_interruption"] or reason in Calibration.protocol().quality.invalidating_events:
		return reason
	return "abort"


static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _date_valid(value: String) -> bool:
	var expression := RegEx.new()
	expression.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
	if expression.search(value) == null:
		return false
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(value + "T00:00:00")) == value


static func _same(first: Variant, second: Variant) -> bool:
	var hash: String = Canonical.semantic_sha256(first)
	return not hash.is_empty() and hash == Canonical.semantic_sha256(second)


static func _seed() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _clock_unix() -> float:
	return Time.get_unix_time_from_system()


func _fail(code: String) -> bool:
	error = code
	return false
