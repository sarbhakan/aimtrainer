extends SceneTree

const Calibration := preload("res://scripts/v2/v2_calibration_service.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const MAX_REPORTED_FAILURES: int = 30

var assertion_count: int = 0
var failure_count: int = 0
var fixture_count: int = 0
var negative_plan_count: int = 0
var oracle: Dictionary = {}


func _initialize() -> void:
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		if failure_count <= MAX_REPORTED_FAILURES:
			push_error(description)


func run_tests() -> void:
	var oracle_path: String = "/tmp/v2_calibration_oracle.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			oracle_path = argument.trim_prefix("--oracle=")
	var parser := JSON.new()
	check(FileAccess.file_exists(oracle_path), "Generate the development oracle before running calibration tests.")
	if not FileAccess.file_exists(oracle_path) or parser.parse(FileAccess.get_file_as_string(oracle_path)) != OK or not parser.data is Dictionary:
		finish()
		return
	oracle = decode_binary64(parser.data)
	check(oracle.protocol_sha256 == Calibration.PROTOCOL_SHA256, "Protocol identity must match the archived reference.")
	for relative_path: String in oracle.source_sha256:
		check(FileAccess.get_sha256("res://docs/reference/v2/" + relative_path) == oracle.source_sha256[relative_path], "Oracle source provenance: " + relative_path)
	test_gains()
	test_comparisons()
	if not FileAccess.file_exists(Calibration.PROTOCOL_PATH) or not FileAccess.file_exists(Calibration.CATALOGUE_PATH):
		check(false, "Calibration resources must be present before deck and plan checks.")
		finish()
		return
	test_decks()
	test_reference_plans()
	test_real_plans()
	test_quality_and_dates()
	test_epoch_eligibility()
	test_preflight_difficulty()
	finish()


func finish() -> void:
	print("V2 CALIBRATION: %d assertions, %d failures; %d comparison fixtures, %d rehashed negative plans." % [assertion_count, failure_count, fixture_count, negative_plan_count])
	quit(0 if failure_count == 0 else 1)


func decode_binary64(value: Variant) -> Variant:
	if value is Dictionary:
		for key: String in value:
			value[key] = decode_binary64(value[key])
	elif value is Array:
		for index: int in value.size():
			value[index] = decode_binary64(value[index])
	elif value is String and value.begins_with("f64be:"):
		return Canonical.float64_from_hex(value.trim_prefix("f64be:"))
	return value


func compare_value(actual: Variant, expected: Variant, path: String, exact_hashes: bool = true) -> void:
	if expected is Dictionary:
		check(actual is Dictionary, path + " must be a dictionary")
		if not actual is Dictionary:
			return
		check(actual.size() == expected.size(), path + " must contain exactly the reference fields")
		for key: String in expected:
			check(actual.has(key), path + " missing " + key)
			if actual.has(key):
				if not exact_hashes and key in ["manifest_sha256", "trajectory_tape_sha256"]:
					continue
				compare_value(actual[key], expected[key], path + "." + key, exact_hashes)
	elif expected is Array:
		check(actual is Array, path + " must be an array")
		if not actual is Array:
			return
		check(actual.size() == expected.size(), path + " must contain the reference element count")
		for index: int in mini(actual.size(), expected.size()):
			compare_value(actual[index], expected[index], path + "[%d]" % index, exact_hashes)
	elif expected is int or expected is float:
		check(actual is int or actual is float, path + " must be numeric")
		if actual is int or actual is float:
			check(is_finite(float(actual)) and absf(float(actual) - float(expected)) <= 1.0e-9, "%s actual=%.17f expected=%.17f" % [path, float(actual), float(expected)])
	else:
		check(actual == expected, "%s actual=%s expected=%s" % [path, str(actual), str(expected)])


func test_gains() -> void:
	for case: Dictionary in oracle.grids:
		var baseline: Dictionary = Calibration.make_gain("A", case.baseline.requested_cm_per_360, case.baseline.declared_dpi)
		compare_value(baseline, case.baseline, "make_gain")
		var result: Dictionary = Calibration.candidate_grid(case.baseline, case.ratio)
		if case.has("error"):
			check(not result.ok and result.error == case.error, "Grid must refuse the reference invalid baseline.")
		else:
			check(result.ok, "Grid must construct representable local alternatives: " + str(result))
			if result.ok:
				compare_value(result.gains, case.gains, "candidate_grid")
				check(Canonical.semantic_sha256(result.gains[0]) == Canonical.semantic_sha256(case.baseline), "Grid must preserve every exact baseline field.")
	var baseline: Dictionary = Calibration.make_gain("A", 35.0)
	check(not Calibration.candidate_grid(baseline, 1.20).ok, "Undeclared ratios must be refused.")
	var duplicate: Dictionary = baseline.duplicate(true)
	duplicate.candidate_id = "B"
	check(Calibration.verify_gains([baseline, duplicate]).error == "DUPLICATE_EFFECTIVE_GAIN", "Distinct labels cannot hide the same effective gain.")
	duplicate.degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex = "0000000000000000"
	check(Calibration.verify_gains([duplicate]).error == "GAIN_DECIMAL_BITS_MISMATCH", "A forged decimal/bit pair must fail.")


func test_comparisons() -> void:
	var statuses: Dictionary = {}
	for fixture_name: String in oracle.comparisons.fixtures:
		var actual: Dictionary = Calibration.compare(oracle.comparisons.fixtures[fixture_name])
		compare_value(actual, oracle.comparisons.results[fixture_name], fixture_name)
		statuses[actual.get("status", "invalid")] = true
		fixture_count += 1
	check(fixture_count == 11 and statuses.size() == 8, "Eleven independent reference fixtures must cover all eight statuses.")
	var valid: Dictionary = oracle.comparisons.fixtures.repeated_improvement
	for count_field: String in ["click_successes", "switch_completions"]:
		for invalid_count: Variant in [true, 1.5, -1, 17, NAN]:
			var corrupted: Dictionary = valid.duplicate(true)
			corrupted.days[0].periods[0][count_field] = invalid_count
			check(Calibration.compare(corrupted).get("ok") == false, "Fractional, boolean, or out-of-range success counts must fail.")
	var forged: Dictionary = valid.duplicate(true)
	forged.protocol_sha256 = "0".repeat(64)
	check(Calibration.compare(forged).error == "MISSING_OR_INCOMPATIBLE_PROTOCOL_SNAPSHOT_HASH", "A forged protocol snapshot cannot produce a performance status.")
	for loss: int in [3, 4]:
		var boundary: Dictionary = valid.duplicate(true)
		var remaining: int = loss
		for day: Dictionary in boundary.days:
			for period: Dictionary in day.periods:
				if period.alias == "B" and remaining > 0:
					period.click_successes -= 1
					remaining -= 1
		check(Calibration.compare(boundary).status == ("repeated_improvement" if loss == 3 else "mixed_tradeoff"), "CLICK uses the exact three-success loss guard.")
	for loss: int in [4, 5]:
		var boundary: Dictionary = valid.duplicate(true)
		var remaining: int = loss
		for day: Dictionary in boundary.days:
			for period: Dictionary in day.periods:
				if period.alias == "B" and remaining > 0:
					var removed: int = mini(remaining, 2)
					period.switch_completions -= removed
					remaining -= removed
		check(Calibration.compare(boundary).status == ("repeated_improvement" if loss == 4 else "mixed_tradeoff"), "SWITCH uses the exact four-completion loss guard.")
	var ceiling: Dictionary = oracle.comparisons.fixtures.close_observed.duplicate(true)
	for day: Dictionary in ceiling.days:
		for period: Dictionary in day.periods:
			period.utilities.REACTIVE = 0.99
	check(Calibration.compare(ceiling).status == "undetermined", "A ceiling overrides performance rules.")


func test_decks() -> void:
	check(Calibration.protocol_hash() == oracle.protocol_sha256, "Runtime resource scalars must preserve the exact protocol hash.")
	for case: Dictionary in oracle.decks:
		var arguments: Array = case.arguments
		var actual: Dictionary = Calibration.make_deck(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6])
		compare_value(actual, case.deck, "deck." + case.deck.deck_id)
		if not actual.has("error"):
			check(Canonical.semantic_sha256(Calibration._without(actual, "manifest_sha256")) == actual.manifest_sha256, "A deck must commit all its scalar fields.")


func rehash_plan(plan: Dictionary) -> void:
	plan.plan_sha256 = Canonical.semantic_sha256(Calibration._without(plan, "plan_sha256"))


func apply_operations(plan: Dictionary, operations: Array) -> void:
	for operation: Dictionary in operations:
		var parts: PackedStringArray = operation.path.trim_prefix("/").split("/")
		var target: Variant = plan
		for index: int in parts.size() - 1:
			var key: String = parts[index].replace("~1", "/").replace("~0", "~")
			target = target[int(key)] if target is Array else target[key]
		var key: String = parts[-1].replace("~1", "/").replace("~0", "~")
		if target is Array:
			target[int(key)] = operation.value.duplicate(true) if operation.value is Dictionary or operation.value is Array else operation.value
		else:
			target[key] = operation.value.duplicate(true) if operation.value is Dictionary or operation.value is Array else operation.value
	rehash_plan(plan)


func test_reference_plans() -> void:
	var original: Dictionary = oracle.example_plan
	check(Calibration.validate_plan(original).ok, "The reference example must validate as an example.")
	for fixture: Dictionary in oracle.negative_plans.fixtures:
		var corrupted: Dictionary = original.duplicate(true)
		apply_operations(corrupted, fixture.operations)
		var result: Dictionary = Calibration.validate_plan(corrupted)
		check(not result.ok and result.error == fixture.expected_error, "%s must fail semantically with %s, got %s" % [fixture.id, fixture.expected_error, str(result)])
		negative_plan_count += 1
	var forged: Dictionary = original.duplicate(true)
	forged.is_example = false
	forged.engine_executable = true
	rehash_plan(forged)
	check(Calibration.validate_plan(forged).error == "EXAMPLE_PLAN_NOT_RUNTIME", "Changing an executable flag must not turn an illustration into a runtime plan.")
	forged = original.duplicate(true)
	forged.condition_snapshot.weights.CLICK = 0.5
	forged.condition_snapshot_sha256 = Canonical.semantic_sha256(forged.condition_snapshot)
	for session: Dictionary in forged.sessions:
		for period: Dictionary in session.periods:
			for cell: Dictionary in period.scored_cells:
				cell.condition_snapshot_sha256 = forged.condition_snapshot_sha256
	rehash_plan(forged)
	check(Calibration.validate_plan(forged).error == "CONDITION_OBJECTIVE_WEIGHTS_MISMATCH", "Rehashed weights and linked cells must still obey the fixed objective.")


func actual_test_conditions() -> Dictionary:
	return {"declared_dpi": 800, "dpi_source": "declared", "fov_horizontal_deg_at_16_9": 103.0,
		"gain_hex": Calibration.make_gain("A", 35.0).degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex,
		"render_resolution_px": [1920, 1080], "render_scale": 1.0, "renderer": "headless", "rendering_driver": "headless",
		"os": OS.get_name(), "engine_version": Engine.get_version_info().string, "frame_limit_hz": 0,
		"display_hz_declared": 60.0, "vsync": false, "input_convention": "received_pose_hold_v1",
		"crosshair": {"kind": "dot", "core_diameter_px": 2, "outline_radial_width_px": 1, "outer_diameter_px": 4},
		"target_palette": "cyan_on_dark", "audio": "disabled", "seeded_scored_stimulus_preview": false,
		"candidate_value_masking": true, "test_origin": "synthetic_fixture_with_actual_OS_and_engine_not_measured_player_data"}


func test_real_plans() -> void:
	var baseline: Dictionary = Calibration.make_gain("A", 35.0)
	var gains: Array = Calibration.candidate_grid(baseline).gains
	var conditions: Dictionary = actual_test_conditions()
	var express: Dictionary = Calibration.create_express_plan(baseline, gains, conditions, "polyvalent", "11111111111111111111111111111111")
	check(express.ok, "Generate a native express plan from supplied test conditions: " + str(express.get("error")))
	if not express.ok:
		return
	check(express.validation.scored_cells == 12 and express.validation.deck_count == 12 and express.plan.programmed_total_s == 696, "Express must resolve all 12 scored cells and 12 shared manifests.")
	check(express.plan.is_read_only() and express.plan.decks.is_read_only() and express.plan.sessions.is_read_only() and express.plan.sessions[0].periods[0].applied_gain.is_read_only(), "Every nested plan container must be immutable before the first score.")
	check(not express.plan.has("engine_executable") and express.plan.plan_id != oracle.example_plan.plan_id, "Native constructors must generate fresh plan identities without an executable flag.")
	check(Calibration.validate_conditions(express.plan, conditions).ok, "Unchanged supplied conditions must remain compatible.")
	var altered: Dictionary = conditions.duplicate(true)
	altered.render_resolution_px = [1280, 720]
	check(not Calibration.validate_conditions(express.plan, altered).ok, "A changed render profile must fail before a score.")
	var confirmation: Dictionary = Calibration.create_confirmation_plan(baseline, gains[1], conditions, "polyvalent", "22222222222222222222222222222222")
	check(confirmation.ok, "Generate a native confirmation plan: " + str(confirmation.get("error")))
	if not confirmation.ok:
		return
	check(confirmation.plan.sessions.size() == 2 and confirmation.validation.scored_cells == 32 and confirmation.validation.deck_count == 40 and confirmation.plan.programmed_total_s == 2016, "Confirmation must resolve two days, four paired blocks each, and new stimuli.")
	for session: Dictionary in confirmation.plan.sessions:
		for pair_index: int in 2:
			compare_value(session.periods[pair_index * 2].acclimation.task_segments.map(func(segment: Dictionary) -> String: return segment.deck_manifest_sha256), session.periods[pair_index * 2 + 1].acclimation.task_segments.map(func(segment: Dictionary) -> String: return segment.deck_manifest_sha256), "paired warmups")
			compare_value(session.periods[pair_index * 2].scored_cells.map(func(cell: Dictionary) -> String: return cell.deck_manifest_sha256), session.periods[pair_index * 2 + 1].scored_cells.map(func(cell: Dictionary) -> String: return cell.deck_manifest_sha256), "paired scored decks")
	var retry: Dictionary = Calibration.create_day_epoch(confirmation.plan, 1, 1)
	check(retry.ok and retry.epoch.session.attempt_epoch == 1, "A retry must rebuild the whole day at epoch one.")
	if retry.ok:
		check(retry.epoch.session.order == confirmation.plan.sessions[0].order, "A retry retains its frozen ABBA/BAAB sequence.")
		check(retry.epoch.session.periods[0].scored_cells[0].deck_manifest_sha256 != confirmation.plan.sessions[0].periods[0].scored_cells[0].deck_manifest_sha256, "A retry uses new paired stimuli.")
	check(not Calibration.create_day_epoch(confirmation.plan, 1, 2).ok, "A third day attempt is forbidden.")
	var near_bound: Dictionary = Calibration.make_gain("A", 5.0)
	var bound_conditions: Dictionary = conditions.duplicate(true)
	bound_conditions.gain_hex = near_bound.degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex
	var two_gain: Dictionary = Calibration.create_express_plan(near_bound, Calibration.candidate_grid(near_bound).gains, bound_conditions, "polyvalent", "33333333333333333333333333333333")
	check(two_gain.ok and two_gain.plan.programmed_total_s == 474 and two_gain.validation.scored_cells == 8, "Near a search bound, a valid two-gain express lasts 474 seconds.")
	var forged: Dictionary = confirmation.plan.duplicate(true)
	var forged_deck_id: String = forged.sessions[0].periods[0].scored_cells[0].deck_id
	forged.decks[forged_deck_id].opportunities[0].yaw_deg += 0.5e-9
	forged.decks[forged_deck_id].manifest_sha256 = Canonical.semantic_sha256(Calibration._without(forged.decks[forged_deck_id], "manifest_sha256"))
	for session: Dictionary in forged.sessions:
		for period: Dictionary in session.periods:
			for cell: Dictionary in period.scored_cells:
				if cell.deck_id == forged_deck_id:
					cell.deck_manifest_sha256 = forged.decks[forged_deck_id].manifest_sha256
	rehash_plan(forged)
	check(Calibration.validate_plan(forged).error == "DECK_STIMULUS_DOES_NOT_MATCH_FROZEN_SEED", "Rehashing even a small stimulus forgery cannot change a frozen native deck.")
	var bad_conditions: Dictionary = conditions.duplicate(true)
	bad_conditions.gain_hex = gains[1].degrees_per_relative_input_unit.ieee754_binary64_big_endian_hex
	check(Calibration.create_confirmation_plan(baseline, gains[1], bad_conditions, "polyvalent", "22222222222222222222222222222222").error == "CONDITION_BASELINE_GAIN_MISMATCH", "The condition snapshot gain is always the exact baseline, including during challenger periods.")
	bad_conditions = conditions.duplicate(true)
	bad_conditions.display_hz_declared = -1
	check(not Calibration.create_express_plan(baseline, gains, bad_conditions, "polyvalent", "11111111111111111111111111111111").ok, "Unknown actual display refresh cannot be replaced by an example value.")
	bad_conditions = conditions.duplicate(true)
	bad_conditions.difficulty_by_task = "standard"
	check(not Calibration.create_express_plan(baseline, gains, bad_conditions, "polyvalent", "11111111111111111111111111111111").ok, "Malformed conditions must return an error without a script exception.")


func test_quality_and_dates() -> void:
	var quality: Dictionary = Calibration.frame_quality([0.010, 0.020])
	check(quality.ok and quality.eligible and absf(quality.median_fps - 1.0 / 0.015) <= 1e-9, "FPS median must use the arithmetic median of even frame interval counts.")
	check(quality.p99_ms == 20.0 and quality.max_ms == 20.0, "P99 must use nearest rank.")
	var long_trace: Array = [0.101]
	for frame_index: int in 5000:
		long_trace.append(1.0 / 240.0)
	quality = Calibration.frame_quality(long_trace)
	check(not quality.eligible and "maximum_frametime_above_maximum" in quality.reasons and quality.frame_count == 5001, "An initial hitch remains invalidating after 4096 good frames.")
	check(not Calibration.frame_quality([0.01, true]).ok, "Boolean and invalid frame intervals must fail.")
	var first: Dictionary = {"actual_start_utc": "2026-10-12T12:00:00Z", "player_local_date": "2026-10-12", "player_utc_offset_minutes": 0}
	for boundary: Array in [["2026-10-13T00:00:00Z", "2026-10-13", true], ["2026-10-19T12:00:00Z", "2026-10-19", true], ["2026-10-19T12:00:01Z", "2026-10-19", false]]:
		var second: Dictionary = {"actual_start_utc": boundary[0], "player_local_date": boundary[1], "player_utc_offset_minutes": 0}
		check(Calibration.validate_day_window(first, second).ok == boundary[2], "Confirmation gaps must include exactly 12 and 168 hours.")
	var same_date: Dictionary = {"actual_start_utc": "2026-10-12T23:59:59Z", "player_local_date": "2026-10-12"}
	check(not Calibration.validate_day_window(first, same_date).ok, "Distinct UTC starts do not substitute for distinct player-local dates.")
	check(Calibration.validate_day_window(first, {}, "2026-10-12T00:00:00Z").ok, "Exactly 12 hours after express is allowed.")
	check(not Calibration.validate_day_window(first, {}, "2026-10-12T00:00:01Z").ok, "Less than 12 hours after express is refused.")
	var forged: Dictionary = first.duplicate(true)
	forged.player_local_date = "2026-10-13"
	check(not Calibration.validate_day_window(forged).ok, "A forged local date must fail when the actual timezone offset is recorded.")


func synthetic_epoch_report(plan: Dictionary, epoch: Dictionary, start_utc: float) -> Dictionary:
	var session: Dictionary = epoch.session
	var report: Dictionary = {"plan_sha256": plan.plan_sha256, "epoch_sha256": epoch.epoch_sha256,
		"condition_snapshot_sha256": plan.condition_snapshot_sha256, "session_id": session.session_id,
		"day_role": session.day_role, "attempt_epoch": session.attempt_epoch, "actual_start_utc": start_utc,
		"actual_end_utc": start_utc + session.planned_duration_s, "player_local_date": Time.get_date_string_from_unix_time(int(start_utc)),
		"player_utc_offset_minutes": 0, "complete": true, "cells": [], "waits": [], "technical_events": [],
		"data_origin": "synthetic_test_only_not_measured_player_data"}
	var baseline: Dictionary = {"CLICK": 0.565, "SMOOTH": 0.710, "REACTIVE": 0.600, "SWITCH": 0.590}
	for period: Dictionary in session.periods:
		for expected: Dictionary in period.scored_cells:
			var cell: Dictionary = expected.duplicate(true)
			cell["applied_gain"] = period.applied_gain.duplicate(true)
			cell["complete"] = true
			cell["actual_start_s"] = expected.scored_start_s
			cell["actual_end_s"] = expected.scored_end_s
			cell["utility"] = baseline[cell.task] + (0.03 if period.comparison_alias == "B" else 0.0)
			cell["render_quality"] = {"mean_fps": 100.0, "median_fps": 100.0, "p99_ms": 10.0, "max_ms": 10.0, "frame_count": 2400}
			if cell.task in ["CLICK", "SWITCH"]:
				cell["opportunities"] = 16 if cell.task == "CLICK" else 12
				cell["success_count"] = 15 if cell.task == "CLICK" else 11
			report.cells.append(cell)
	return report


func test_epoch_eligibility() -> void:
	var baseline: Dictionary = Calibration.make_gain("A", 35.0)
	var challenger: Dictionary = Calibration.make_gain("C_m1", 28.0)
	var built: Dictionary = Calibration.create_confirmation_plan(baseline, challenger, actual_test_conditions(), "polyvalent", "44444444444444444444444444444444")
	check(built.ok, "Technical eligibility requires a real generated plan.")
	if not built.ok:
		return
	var plan: Dictionary = built.plan
	var first_epoch: Dictionary = Calibration.create_day_epoch(plan, 1, 0).epoch
	var second_epoch: Dictionary = Calibration.create_day_epoch(plan, 2, 0).epoch
	var start_utc: float = Time.get_unix_time_from_datetime_string("2026-10-12T12:00:00")
	var first_report: Dictionary = synthetic_epoch_report(plan, first_epoch, start_utc)
	var second_report: Dictionary = synthetic_epoch_report(plan, second_epoch, start_utc + 86400.0)
	var eligibility: Dictionary = Calibration.validate_epoch_report(plan, first_epoch, first_report)
	check(eligibility.ok and eligibility.complete and eligibility.eligible, "A whole, technically valid epoch must be eligible.")
	var comparison: Dictionary = Calibration.compare_epochs(plan, [first_report, second_report])
	check(comparison.get("status") == "repeated_improvement" and comparison.accepted_epoch_by_day_role == {"1": 0, "2": 0}, "Comparison consumes only complete accepted day epochs.")
	var corrupted: Dictionary = first_report.duplicate(true)
	corrupted.cells[0].render_quality.mean_fps = 54.999
	check(not Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "Mean FPS threshold cannot be weakened.")
	corrupted = first_report.duplicate(true)
	corrupted.cells[0].render_quality.p99_ms = 25.0
	corrupted.cells[0].render_quality.max_ms = 100.0
	check(Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "P99 and maximum frame interval boundaries are inclusive.")
	corrupted.cells[0].render_quality.max_ms = 100.00001
	check(not Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "Maximum frame interval threshold cannot be weakened.")
	corrupted = first_report.duplicate(true)
	corrupted.cells[0].render_quality.median_fps = 95.0
	corrupted.cells[4].render_quality.median_fps = 105.0
	check(Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "Paired median FPS difference at exactly ten percent is allowed.")
	corrupted.cells[4].render_quality.median_fps = 105.001
	check(not Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "Paired median FPS difference above ten percent invalidates the whole epoch.")
	corrupted.cells = corrupted.cells.slice(0, 4) + corrupted.cells.slice(8, 12) + corrupted.cells.slice(4, 8) + corrupted.cells.slice(12, 16)
	check(not Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "Reordering report rows cannot change the frozen quality pairings.")
	corrupted = first_report.duplicate(true)
	corrupted.cells.remove_at(0)
	eligibility = Calibration.validate_epoch_report(plan, first_epoch, corrupted)
	check(eligibility.ok and not eligibility.complete and not eligibility.eligible, "Missing tasks remain missing and never become zero utility.")
	corrupted = first_report.duplicate(true)
	corrupted.technical_events = ["pause_during_score"]
	check(not Calibration.validate_epoch_report(plan, first_epoch, corrupted).eligible, "A pause invalidates the whole day.")
	var retry_epoch: Dictionary = Calibration.create_day_epoch(plan, 1, 1).epoch
	var retry_report: Dictionary = synthetic_epoch_report(plan, retry_epoch, start_utc + 3600.0)
	comparison = Calibration.compare_epochs(plan, [corrupted, retry_report, second_report])
	check(comparison.get("status") == "repeated_improvement" and comparison.accepted_epoch_by_day_role.get("1") == 1 and comparison.budget.scheduled_attempt_count == 3, "One documented invalid day can be replaced by the first complete valid new epoch.")
	check(Calibration.compare_epochs(plan, [first_report, retry_report, second_report]).get("error") == "RETRY_AFTER_FIRST_VALID_COMPLETE_EPOCH", "Low performance cannot justify replacing an accepted epoch.")
	var exhausted: Dictionary = retry_report.duplicate(true)
	exhausted.technical_events = ["capture_loss"]
	check(Calibration.compare_epochs(plan, [corrupted, exhausted, second_report]).get("status") == "unstable_conditions", "Two invalid scheduled attempts produce a terminal technical status.")
	corrupted = first_report.duplicate(true)
	corrupted.waits = [{"start_s": 60.0, "end_s": 60.0 + 901.0, "planned": false}]
	corrupted.actual_end_utc += 901.0
	for cell: Dictionary in corrupted.cells:
		cell.actual_start_s += 901.0
		cell.actual_end_s += 901.0
	eligibility = Calibration.validate_epoch_report(plan, first_epoch, corrupted)
	check(eligibility.ok and not eligibility.eligible and "long_unplanned_interruption" in eligibility.reasons, "An unplanned wait longer than fifteen minutes requires a whole-day epoch.")


func test_preflight_difficulty() -> void:
	var levels: Dictionary = {"CLICK": "standard", "SMOOTH": "standard", "REACTIVE": "standard", "SWITCH": "standard"}
	var rows: Dictionary = {"CLICK": {"complete": true, "utility": 0.05, "opportunities": 10},
		"SMOOTH": {"complete": true, "utility": 0.97, "duration_s": 15},
		"REACTIVE": {"complete": true, "utility": 0.50, "duration_s": 15},
		"SWITCH": {"complete": true, "utility": 0.50, "opportunities": 7}}
	var suggested: Dictionary = Calibration.preflight_difficulty(rows, levels)
	check(suggested.ok and suggested.complete and suggested.additional_programmed_s == 48 and suggested.requires_new_frozen_plan, "Each changed preflight task adds a full independent 24-second diagnostic before a new plan.")
	check(suggested.difficulty_by_task.CLICK == "novice" and suggested.difficulty_by_task.SMOOTH == "advanced" and levels.CLICK == "standard", "Difficulty changes are proposals and cannot mutate a frozen level.")
	check(Calibration.preflight_difficulty(rows, levels, {"CLICK": 2}).review_tasks == ["CLICK"], "After two changes, an uninformative task needs configuration review.")
	rows.CLICK.opportunities = 16
	check(Calibration.preflight_difficulty(rows, levels).error == "WRONG_PREFLIGHT_OPPORTUNITY_DENOMINATOR", "A fifteen-second preflight must not use a 24-second CLICK denominator.")
