extends SceneTree

const Shell := preload("res://scripts/ui/v2_shell.gd")
const Hud := preload("res://scripts/ui/v2_training_hud.gd")
const PROFILE: Dictionary = {
	"dpi": 800.0, "cm_per_360": 35.01234567890123,
	"vertical_fov_deg": 70.53280043291679, "invert_y": false,
	"weapon_id": "pulse", "show_weapon": true, "sound_enabled": false,
	"reduced_motion": true, "crosshair_style": "dot", "crosshair_size_px": 1.0,
	"crosshair_thickness_px": 2.0, "crosshair_gap_px": 4.0,
	"crosshair_color": "#ffffff", "crosshair_outline": true,
	"canonical_gain_bits": "3fa4c794c81a702d", "source_metadata": {"preserve": "exact"},
	"reference_game": null
}

var assertion_count: int = 0
var failure_count: int = 0
var catalog: Dictionary = {}
var capture_directory: String = ""


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("V2 UI did not finish within 60 seconds.")
		quit(1))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	run_suite.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func run_suite() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/v2/donnees/catalogue.v2.json"))
	check(parsed is Dictionary, "The supplied V2 catalogue must be readable without an import.")
	if not parsed is Dictionary:
		quit(1)
		return
	catalog = parsed
	await test_shell_flow()
	await test_profile_precision()
	await test_calibration_flow()
	await test_results()
	await test_history_progress()
	await test_hud()
	await test_dimensions()
	print("V2 UI : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func make_viewport(dimensions: Vector2i = Vector2i(1280, 720)) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func make_shell(viewport: SubViewport) -> Shell:
	var shell := Shell.new()
	shell.configure(catalog, PROFILE)
	viewport.add_child(shell)
	return shell


func test_shell_flow() -> void:
	var viewport := make_viewport()
	var shell := Shell.new()
	var events: Dictionary = {"practice": [], "preview": [], "active_preview": "", "stops": 0, "overlap": false, "pauses": [], "history": 0, "quit": 0}
	shell.practice_requested.connect(func(program_id: String, difficulty: String) -> void: events.practice.append([program_id, difficulty]))
	shell.preview_requested.connect(func(program_id: String, difficulty: String) -> void:
		events.overlap = events.overlap or not str(events.active_preview).is_empty()
		events.active_preview = program_id
		events.preview.append([program_id, difficulty]))
	shell.preview_stop_requested.connect(func() -> void:
		events.active_preview = ""
		events.stops += 1)
	shell.preview_pause_requested.connect(func(paused: bool) -> void: events.pauses.append(paused))
	shell.history_requested.connect(func() -> void: events.history += 1)
	shell.quit_requested.connect(func() -> void: events.quit += 1)
	shell.configure(catalog, PROFILE)
	viewport.add_child(shell)
	await settle()
	check(shell.catalog_grid.get_child_count() == 8, "Only the eight V2 cards appear in the public catalogue.")
	check(shell.program_definitions.size() == 8 and shell._definition("EX04", "advanced").duration_s == 60, "The full 24-configuration kit is accepted.")
	var adapter := Control.new()
	shell.set_preview_content(adapter)
	shell.show_preparation("EX04")
	await settle()
	check(shell.level_buttons.size() == 3 and shell.start_button.disabled, "Preparation offers exactly three levels and waits for runtime readiness.")
	shell.start_button.pressed.emit()
	check(events.practice.is_empty(), "An unready program cannot start even if the action is invoked.")
	shell.set_practice_ready("EX04", "standard", true)
	shell.start_button.pressed.emit()
	check(events.practice == [["EX04", "standard"]], "Practice requests preserve the chosen program and canonical level.")
	check(str(events.active_preview).is_empty(), "Starting practice stops the active preview.")
	shell.show_preparation("EX04")
	shell.level_buttons[2].pressed.emit()
	await settle()
	check(shell.selected_difficulty == "advanced" and shell.start_button.disabled, "Changing difficulty requires readiness for that exact configuration.")
	shell.set_practice_ready("EX04", "advanced", true)
	shell.start_button.pressed.emit()
	check(events.practice[-1] == ["EX04", "advanced"], "The advanced launch is not silently changed to standard.")
	shell.show_preparation("EX04")
	shell._preview_pause_button.pressed.emit()
	check(events.pauses == [true], "The mounted renderer receives the preview pause request.")
	shell._return_to_catalog()
	await settle()
	check(shell._catalog_buttons.EX04.has_focus(), "Returning from preparation restores the originating card's focus.")
	check(not events.overlap, "Preview switches always stop the previous engine adapter first.")
	shell._open_history()
	check(events.history == 1 and shell.current_page == "history", "History navigation emits the parent refresh request.")
	shell._compact_navigation.get_children()[-1].pressed.emit()
	check(events.quit == 1, "Native quit controls emit the parent quit request.")
	viewport.queue_free()
	await settle()


func test_profile_precision() -> void:
	var viewport := make_viewport()
	var shell := make_shell(viewport)
	var requests: Array[Dictionary] = []
	shell.profile_requested.connect(func(profile: Dictionary) -> void: requests.append(profile))
	shell.show_settings(PROFILE)
	await settle()
	check(shell.draft_profile() == PROFILE, "Opening settings preserves every canonical value and unknown metadata field.")
	var distance := shell.profile_fields.cm_per_360 as SpinBox
	distance.call("begin_edit")
	await settle()
	distance.call("finish_edit")
	await settle()
	check(shell.draft_profile() == PROFILE, "Focus and blur of a rounded display never rewrite the precise distance.")
	distance.value = 38.12345678901234
	shell.profile_fields.sound_enabled.set_pressed(true)
	var expected := PROFILE.duplicate(true)
	expected.cm_per_360 = 38.12345678901234
	expected.sound_enabled = true
	shell.profile_apply_button.pressed.emit()
	check(requests.size() == 1 and requests[0] == expected, "Saving forwards the precise edits and all original metadata.")
	check(shell.current_profile == PROFILE, "The UI waits for parent persistence before changing the accepted profile.")
	var exported := shell.draft_profile()
	exported.source_metadata.preserve = "changed outside"
	check(shell.draft_profile().source_metadata.preserve == "exact", "Returned profile drafts are independent deep copies.")
	shell.show_calibration({"profile_locked": true, "plan_frozen": true})
	shell.show_settings(PROFILE)
	await settle()
	check(shell.profile_apply_button.disabled and not shell.profile_fields.cm_per_360.editable, "A service-locked visual/input profile cannot be edited.")
	viewport.queue_free()
	await settle()


func test_calibration_flow() -> void:
	var viewport := make_viewport()
	var shell := make_shell(viewport)
	var events: Dictionary = {"starts": [], "continues": 0, "applies": [], "undos": 0, "adjustments": []}
	shell.calibration_requested.connect(func(mode: String, settings: Dictionary) -> void: events.starts.append({"mode": mode, "settings": settings}))
	shell.calibration_continue_requested.connect(func() -> void: events.continues += 1)
	shell.calibration_apply_requested.connect(func(candidate: Dictionary) -> void: events.applies.append(candidate))
	shell.calibration_undo_requested.connect(func() -> void: events.undos += 1)
	shell.calibration_level_adjustment_requested.connect(func(task: String, difficulty: String) -> void: events.adjustments.append([task, difficulty]))
	shell.show_calibration({})
	shell._request_calibration("express")
	check(events.starts.is_empty(), "An absent calibration service cannot pretend to be ready.")
	shell.show_calibration({"ready": true})
	shell.objective_input.select(2)
	shell.objective_input.item_selected.emit(2)
	shell.ratio_input.select(1)
	shell.ratio_input.item_selected.emit(1)
	shell.calibration_level_inputs.CLICK.item_selected.emit(0)
	shell._request_calibration("express")
	var settings := shell.calibration_settings()
	check(events.starts.size() == 1 and settings.objective == "tracking" and settings.ratio == 1.5 and settings.levels.CLICK == "novice", "Objective, local ratio and per-task levels are chosen before the plan freezes.")
	check(settings.profile == PROFILE, "Calibration requests retain the exact baseline profile.")
	shell.show_calibration({"plan_frozen": true, "settings": settings, "can_continue": false, "wait_remaining_s": 0.0})
	await settle()
	check(shell.objective_input.disabled and shell.ratio_input.disabled and shell.calibration_level_inputs.CLICK.disabled, "A frozen plan keeps all setup choices fixed.")
	shell.objective_input.item_selected.emit(0)
	shell.ratio_input.item_selected.emit(0)
	shell.calibration_level_inputs.CLICK.item_selected.emit(2)
	check(shell.calibration_settings() == settings, "Late setup callbacks cannot alter an immutable calibration plan.")
	shell.calibration_continue_button.pressed.emit()
	check(events.continues == 0, "A displayed zero wait never substitutes for service eligibility.")
	shell.show_calibration({"plan_frozen": true, "can_continue": true, "continue_label": "Commencer le jour 2"})
	shell.calibration_continue_button.pressed.emit()
	check(events.continues == 1, "Continuing an eligible day remains an explicit user action.")
	shell.show_calibration({"ready": true, "can_start_confirmation": false, "can_continue": false, "eligibility_text": "Attendre le créneau", "wait_remaining_s": 43200.0})
	await settle()
	shell.calibration_express_button.grab_focus()
	await settle()
	var page_identity := shell.page_content.get_instance_id()
	var focus_identity := viewport.gui_get_focus_owner().get_instance_id()
	var scroll_offset := shell.content_scroll.scroll_vertical
	shell.update_calibration_availability({"ready": true, "can_start_confirmation": true, "can_continue": true, "eligibility_text": "Créneau autorisé", "wait_remaining_s": 0.0})
	check(shell.page_content.get_instance_id() == page_identity and viewport.gui_get_focus_owner().get_instance_id() == focus_identity and shell.content_scroll.scroll_vertical == scroll_offset, "The periodic availability refresh never rebuilds or resets focus and scrolling.")
	check(not shell.calibration_confirmation_button.disabled and not shell.calibration_continue_button.disabled and shell.calibration_eligibility_label.text == "Créneau autorisé", "Fresh service eligibility updates the existing native controls in place.")
	shell.show_calibration({"profile_locked": true, "active": true})
	check(shell.objective_input.disabled and shell.ratio_input.disabled and shell.calibration_level_inputs.CLICK.disabled, "The native profile_locked flag freezes a pending plan even without a plan_frozen alias.")
	shell.calibration_restart_button.pressed.emit()
	check(events.starts.size() == 1, "An active calibration cannot be restarted from the UI.")
	shell.update_calibration_availability({"profile_locked": true, "active": false})
	shell.calibration_restart_button.pressed.emit()
	check(events.starts.size() == 2 and events.starts[-1].mode == "restart_express", "An inactive locked plan can request an archived fresh comparison through the parent.")
	for status: String in Shell.CALIBRATION_TITLES:
		shell.show_calibration({"status": status})
		check(shell._title_label.text == Shell.CALIBRATION_TITLES[status], "The service status is translated directly: " + status)
		check(shell.calibration_apply_button.disabled, "A status alone does not authorize candidate application: " + status)
	var candidate: Dictionary = {"id": "B", "cm_per_360": 28.12345678901234, "gain_bits": "original", "source": {"plan": "real-service"}}
	shell.show_calibration({"status": "repeated_improvement", "candidate": candidate})
	shell.calibration_apply_button.pressed.emit()
	check(events.applies.is_empty(), "A positive status still requires the service's can_apply flag.")
	shell.show_calibration({"status": "repeated_improvement", "candidate": candidate, "can_apply": true, "can_undo": true})
	shell.calibration_apply_button.pressed.emit()
	shell.calibration_undo_button.pressed.emit()
	check(events.applies == [candidate] and events.undos == 1, "Voluntary apply and undo forward the exact service candidate.")
	shell.show_calibration({"status": "repeated_regression", "day_effects": [-3.2, -3.08]})
	await settle()
	check(visible_text(shell).contains("−3,20 à +3,20") and visible_text(shell).contains("-3,08 pt"), "Losses retain negative values on a shared signed scale.")
	shell.show_calibration({"result": {"status": "repeated_regression", "day_effects": [
		{"day_role": 1, "composite_pp": -3.2, "effects_pp": {"CLICK": -4.5, "SMOOTH": 0.0}},
		{"day_role": 2, "composite_pp": -3.08, "effects_pp": {"CLICK": -4.25}}
	]}, "candidate": {"effective_cm_per_360": 28.0, "degrees_per_relative_input_unit": {"decimal_roundtrip": "0.040821428571428573"}}})
	var native_text := visible_text(shell)
	check(native_text.contains("−3,20 à +3,20") and native_text.contains("-3,08 pt") and native_text.contains("Jour 2 · -4,25 pt"), "Native composite_pp and effects_pp values are displayed directly without a fixture adapter.")
	check(native_text.contains("Jour 1 · +0,00 pt") and not native_text.contains("Suivi réactif") and not native_text.contains("Transitions"), "A measured zero task effect is visible while absent task effects remain absent.")
	check(native_text.contains("0.040821428571428573 °/unité relative"), "The native candidate's exact gain roundtrip string is not rounded in the comparison view.")
	var review: Dictionary = {"stage": "preflight", "phase": "express", "active": true, "profile_locked": true, "plan_frozen": true, "can_continue": true,
		"continue_label": "Garder ces niveaux / continuer", "result": {"status": "repeated_improvement", "score": 987654.0},
		"preflight": {"reports_received": 4, "levels_frozen": false, "records": {
			"CLICK": {"difficulty": "standard", "diagnostic_utility": 0.05}, "SMOOTH": {"difficulty": "standard", "diagnostic_utility": 0.56},
			"REACTIVE": {"difficulty": "standard", "diagnostic_utility": 0.0}, "SWITCH": {"difficulty": "standard"}},
			"proposals": [{"task": "CLICK", "current_level": "standard", "suggested_level": "novice", "can_adjust": true}], "pending_adjustment": {}}}
	var frozen_settings := shell.calibration_settings()
	shell.show_calibration(review)
	check(shell.calibration_adjustment_buttons.size() == 4 and shell.objective_input == null and shell.calibration_level_inputs.is_empty(), "Preflight review uses four diagnostic cards rather than the frozen setup selectors.")
	var review_text := visible_text(shell)
	check(review_text.contains("U diagnostique · 0,0500") and review_text.contains("U diagnostique · 0,5600") and review_text.contains("U diagnostique · 0,0000") and review_text.contains("Diagnostic non fourni"), "Original preflight utilities distinguish measured zero from missing diagnostic data.")
	check(not review_text.contains("987654") and not review_text.contains("avantage retrouvé") and shell.calibration_continue_button.text == "Garder ces niveaux / continuer", "Preflight review has diagnostics and an explicit keep-levels action, never comparative outcomes.")
	shell.calibration_adjustment_buttons.CLICK.pressed.emit()
	shell.calibration_adjustment_buttons.SMOOTH.pressed.emit()
	check(events.adjustments == [["CLICK", "novice"]] and shell.calibration_settings() == frozen_settings, "A suggested 24-second validation delegates its exact task and level without quietly modifying the frozen plan.")
	review.preflight.proposals[0].can_adjust = false
	shell.update_calibration_availability(review)
	shell.calibration_adjustment_buttons.CLICK.pressed.emit()
	check(shell.calibration_adjustment_buttons.CLICK.disabled and events.adjustments.size() == 1, "A withdrawn retest permission disables the existing button and blocks a late callback.")
	review.preflight.proposals[0].can_adjust = true
	review.preflight.proposals[0].suggested_level = "advanced"
	shell.update_calibration_availability(review)
	shell.calibration_adjustment_buttons.CLICK.pressed.emit()
	check(events.adjustments[-1] == ["CLICK", "advanced"] and shell.calibration_adjustment_buttons.CLICK.text.contains("Avancé"), "Retest callbacks use the latest service proposal rather than a stale bound difficulty.")
	review.phase = "confirmation"
	shell.update_calibration_availability(review)
	shell.calibration_adjustment_buttons.CLICK.pressed.emit()
	check(shell.calibration_adjustment_buttons.CLICK.disabled and events.adjustments.size() == 2, "Confirmation levels cannot change even if a stale proposal claims can_adjust.")
	review.phase = "express"
	review.preflight.levels_frozen = true
	shell.update_calibration_availability(review)
	check(shell.calibration_adjustment_buttons.CLICK.disabled, "A comparison-started preflight lock forbids any level retest.")
	review.preflight.levels_frozen = false
	review.preflight.pending_adjustment = {"task": "CLICK"}
	shell.update_calibration_availability(review)
	check(shell.calibration_adjustment_buttons.CLICK.disabled, "A pending validation cannot start a second overlapping retest.")
	review.stage = "preflight_review"
	review.preflight.pending_adjustment = {}
	shell.show_calibration(review)
	check(not shell.calibration_adjustment_buttons.CLICK.disabled, "The explicit preflight_review stage supports the same native retest flow.")
	review.preflight.records = [{"task": "CLICK", "difficulty": "standard", "diagnostic_utility": 0.0625}]
	shell.update_calibration_availability(review)
	check(shell.calibration_preflight_labels.CLICK.utility.text.contains("0,0625"), "Native records may also be an array of task-identified diagnostic rows.")
	review.preflight.reports_received = 3
	shell.update_calibration_availability(review)
	check(shell.calibration_adjustment_buttons.CLICK.disabled, "The optional report count cannot authorize level testing before all four original diagnostics exist.")
	shell.show_calibration({"stage": "measurement", "task_title": "Suivi réactif", "remaining_s": 15.0, "status": "repeated_improvement", "score": 987654.0, "day_effects": [987654.0]})
	check(not visible_text(shell).contains("987654") and not visible_text(shell).contains("avantage retrouvé"), "Calibration measurement hides scores and outcome forecasts.")
	viewport.queue_free()
	await settle()


func report_fixture(program_id: String = "EX01") -> Dictionary:
	return {
		"schema_version": "aimlocal.report.v2.0", "runtime_version": "aimlocal.runtime.v2.0",
		"catalogue_revision": "2026-10-12-v2.0", "program_id": program_id, "difficulty": "standard",
		"title": Shell.PROGRAM_COPY[program_id].title, "duration_s": 60.0, "elapsed_s": 12.5,
		"complete": false, "valid": true, "invalid_reason": "", "conditions": PROFILE.duplicate(true),
		"phases": [{"phase_id": "micro", "title": "Micro-ajustements", "score": 17.126, "display_score": 17,
			"complete": false, "metrics": {"hits": 7, "shots": 10, "misses": 3, "accuracy": 0.7, "acquisition_p50_ms": 231.0}}],
		"program_score": 987654.0, "display_score": 987654
	}


func test_results() -> void:
	var viewport := make_viewport()
	var shell := make_shell(viewport)
	var report := report_fixture()
	shell.show_results(report)
	await settle()
	var text := visible_text(shell)
	check(text.contains("Score de phase C · 17"), "Click scores use the provided integer display value for their individual phase.")
	check(text.contains("12,50 s actives") and text.contains("Programme interrompu") and not text.contains("60,00 s actives"), "Partial results report the measured active time and completion state.")
	check(text.contains("Acquisition médiane") and text.contains("231"), "The runtime's acquisition_p50_ms field reaches the native result rows.")
	check(not text.contains("987654"), "A supplied aggregate cannot leak into a C/P program's public score.")
	report.program_id = "EX03"
	shell.show_results(report)
	check(visible_text(shell).contains("Score de phase P"), "Timed opportunity scores use their P phase label.")
	report.program_id = "EX05"
	shell.show_results(report)
	check(visible_text(shell).contains("Indice de contact du programme") and visible_text(shell).contains("987654"), "A supplied T program index is displayed with its meaning.")
	report.program_id = "EX08"
	shell.show_results(report)
	check(visible_text(shell).contains("Indice de travail utile du programme"), "The S program index has a distinct work label.")
	shell.show_results({"program_id": "EX01", "phases": [{"title": "Sans mesures", "score": null, "metrics": {"hits": null, "shots": null}}]})
	check(not visible_text(shell).contains("0,00") and not visible_text(shell).contains("Cibles touchées"), "Null or absent measurements do not become fake zero scores or counts.")
	shell.show_results({"program_id": "EX01", "phases": [{"title": "Zéro mesuré", "score": 0.0, "metrics": {"hits": 0}}]})
	check(visible_text(shell).contains("Score de phase C · 0") and visible_text(shell).contains("Cibles touchées"), "An actual measured zero remains a valid visible value.")
	shell.show_history([])
	check(visible_text(shell).contains("Votre première séance"), "Empty history presents no sample or invented scores.")
	viewport.queue_free()
	await settle()


func test_history_progress() -> void:
	var viewport := make_viewport()
	var shell := make_shell(viewport)
	var report := report_fixture()
	report.session_id = "history_best"
	report.ended_utc = "2026-10-12T20:00:00"
	var rows: Array = [{"namespace": "v2", "read_only": true, "report": report}]
	var conditions: Dictionary = {"declared_dpi": 800, "gain_hex": "3fa0b83e2a193daa", "vertical_fov_deg": 70.53280043291679, "render_resolution_px": [1280, 720]}
	var groups: Array = [
		{"group_id": "click_context_9", "program_id": "EX01", "difficulty": "standard", "phase_id": "micro", "score_family": "click_v3", "conditions": conditions,
			"context_count": 9, "best_score": 17.5, "best_report_id": "history_best", "first_five_median": 987651.0, "last_five_median": 987652.0},
		{"group_id": "click_context_10", "program_id": "EX01", "difficulty": "standard", "phase_id": "micro", "score_family": "click_v3", "conditions": conditions,
			"context_count": 10, "best_score": 18.5, "first_five_median": 1.5, "last_five_median": 3.5},
		{"group_id": "tracking_context", "program_id": "EX05", "difficulty": "novice", "phase_id": "", "score_family": "contact_v2", "conditions": conditions, "context_count": 1, "best_score": 73.5},
		{"group_id": "switch_context", "program_id": "EX08", "difficulty": "advanced", "phase_id": "", "score_family": "switch_work_v3", "conditions": conditions, "context_count": 1, "best_score": 0.0},
		{"group_id": "invalid_click_aggregate", "program_id": "EX01", "difficulty": "standard", "phase_id": "", "score_family": "click_v3", "context_count": 10, "best_score": 987654.0},
		{"group_id": "absent_score", "program_id": "EX03", "difficulty": "standard", "phase_id": "fixed", "score_family": "opportunities_v2", "context_count": 1}
	]
	shell.show_history(rows, groups)
	await settle()
	var text := visible_text(shell)
	check(text.contains("Record · 18") and text.contains("Record · 19") and not text.contains("17,50"), "History records use integer half-up display from the supplied raw best_score.")
	check(text.contains("Médianes · 5 premières 2 → 5 dernières 4") and not text.contains("987651") and not text.contains("987652"), "First-five and last-five medians are visible only once a single backend context has ten sessions.")
	check(text.contains("9 séances comparables") and text.contains("10 séances comparables") and text.contains("Phase") and text.contains("famille C"), "Native progress contexts retain program, difficulty, phase and family boundaries.")
	check(text.contains("Indice de contact du programme T") and text.contains("Indice de travail utile du programme S") and text.contains("Record · 74"), "Only T and S progress groups may expose a program index.")
	check(text.contains("Record · 0") and not text.contains("987654"), "A measured zero record remains visible while a C/P aggregate is not fabricated.")
	check(text.contains("Gain 3fa0b83e2a193daa") and text.contains("1280×720") and text.contains("2026-10-12T20:00:00"), "History retains explicit gain, viewport and actual saved chronology context.")
	check(shell.history_progress_groups == groups, "The shell renders the supplied backend summary without recomputing, merging or modifying it.")
	shell.configure(catalog, PROFILE, {}, rows)
	check(shell.history_progress_groups == groups, "A same-history profile refresh preserves the existing progress summary.")
	for dimensions: Vector2i in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		await settle()
		verify_layout(shell, dimensions, "history_progress")
		await capture(viewport, dimensions, "history_progress")
	shell.configure(catalog, PROFILE, {}, [])
	check(shell.history_progress_groups.is_empty() and visible_text(shell).contains("Votre première séance"), "A changed history cannot retain a stale prior progress summary.")
	viewport.queue_free()
	await settle()


func test_hud() -> void:
	var viewport := make_viewport()
	var hud := Hud.new()
	hud.configure(PROFILE)
	viewport.add_child(hud)
	await settle()
	hud.present_live({})
	check(hud.timer_label.text == "--:--" and hud.score_label.text.is_empty() and hud.metric_label.text.is_empty() and not hud.ammo_label.visible, "Missing HUD values remain unknown or absent.")
	var snapshot: Dictionary = {"program_id": "EX03", "program_title": "Temporisées", "difficulty": "standard", "phase_title": "Fixe",
		"duration_s": 60.0, "elapsed_s": 28.01, "phase_duration_s": 30.0, "phase_remaining_s": 1.99,
		"next_phase_title": "Réduction", "phase_score": 42.5, "metrics": {"hits": 7, "shots": 10, "accuracy": 0.7},
		"ammo": 7, "ammo_capacity": 30, "program_score": 987654.0}
	hud.present_live(snapshot)
	check(hud.timer_label.text == "00:32" and hud.phase_alert_label.visible and hud.phase_alert_label.text.contains("Réduction"), "The timer and two-second phase cue use the parent's active clock.")
	check(hud.score_label.text == "Score de phase P · 43" and not hud.metric_label.text.contains("987654"), "The HUD uses integer half-up phase scores without merging C/P totals.")
	check(hud.ammo_label.text.contains("7 / 30"), "Ammo appears only from the supplied values.")
	snapshot.phase_remaining_s = 2.01
	hud.present_live(snapshot)
	check(not hud.phase_alert_label.visible, "Phase warnings do not appear before the two-second window.")
	snapshot.is_calibration = true
	hud.present_live(snapshot)
	check(hud.score_label.text.is_empty() and hud.metric_label.text.is_empty() and not hud._metrics.visible, "Calibration snapshots hide all performance measurements.")
	var broad_metrics: Dictionary = {"hits": 0, "shots": 0, "kills": 2, "expired": 0, "contact_s": 12.5, "exposure_s": 20.0, "contact_ratio": 0.625, "accuracy": 0.0, "credited_work": 2.25}
	hud.present_live({"program_id": "EX05", "metrics": broad_metrics})
	check(hud.metric_label.text.contains("Contact 12,5 / 20,0 s") and not hud.metric_label.text.contains("Tirs") and not hud.metric_label.text.contains("Destructions"), "Tracking omits irrelevant zero-filled engine metrics.")
	hud.present_live({"program_id": "EX08", "metrics": broad_metrics})
	check(hud.metric_label.text.contains("Destructions 2") and hud.metric_label.text.contains("Travail utile 2,25") and not hud.metric_label.text.contains("Contact") and not hud.metric_label.text.contains("Tirs"), "Switching shows only useful work and destruction measures.")
	hud.present_live({"program_id": "EX01", "metrics": broad_metrics})
	check(hud.metric_label.text.contains("Touches 0") and not hud.metric_label.text.contains("Contact") and not hud.metric_label.text.contains("Destructions") and not hud.metric_label.text.contains("Expirations"), "Click metrics retain measured zeros while omitting unrelated contact, work and opportunities.")
	hud.begin_countdown()
	hud.show_countdown(2.1)
	check(hud.countdown_label.text == "3" and hud.target_projections.is_empty() and not hud._metrics.visible, "Countdown displays a number and clears prior targets and metrics.")
	hud.show_countdown(0.0)
	check(not hud._countdown.visible, "The parent ends the countdown without an independent UI timer.")
	var target: Dictionary = {"center_px": Vector2(100.0, 120.0), "radius_px": 10.0, "hp_remaining": 40.0, "hp_max": 80.0}
	var original := target.duplicate(true)
	var ring := hud.health_ring_points(target)
	check(ring.size() == 129 and ring[0].is_equal_approx(Vector2(100.0, 108.0)), "Health rings start above the actual projected target at factor 1.2.")
	check(target == original, "Cosmetic ring generation never changes a target's hitbox data.")
	check(hud.health_ring_points({"pose": {"radius_m": 0.1}}).is_empty(), "World radii without render projection cannot create fake screen targets.")
	var contour := PackedVector2Array()
	for point_index in 16:
		contour.append(Vector2(100.0, 120.0) + Vector2.from_angle(TAU * float(point_index) / 16.0) * Vector2(20.0, 10.0))
	var projected := hud.health_ring_points({"center_px": [100.0, 120.0], "contour_px": contour})
	check(projected.size() == 17 and projected[0].is_equal_approx(Vector2(100.0, 108.0)), "Off-axis contour projections retain their supplied shape.")
	hud.present_live({"arena_rect_px": [0.0, 60.0, 1280.0, 600.0], "target_projections": [target]})
	check(hud.arena_rect_px.get_center() == Vector2(640.0, 360.0), "The crosshair follows the rendered arena rather than a menu layout.")
	var pause_events: Dictionary = {"resume": 0, "menu": 0, "settings": 0, "sensitivity": 0}
	hud.resume_requested.connect(func() -> void: pause_events.resume += 1)
	hud.menu_requested.connect(func() -> void: pause_events.menu += 1)
	hud.settings_requested.connect(func() -> void: pause_events.settings += 1)
	hud.sensitivity_edit_requested.connect(func() -> void: pause_events.sensitivity += 1)
	hud.show_pause(true, "Pause demandée")
	await settle()
	hud.resume_button.pressed.emit()
	hud.menu_button.pressed.emit()
	check(hud.resume_button.has_focus() and pause_events.resume == 1 and pause_events.menu == 1, "Pause buttons have native focus and forward lifecycle requests.")
	hud.settings_button.pressed.emit()
	hud.sensitivity_button.pressed.emit()
	check(pause_events.settings == 1 and pause_events.sensitivity == 1 and hud._paused, "Settings and sensitivity delegate to the parent while practice stays paused.")
	hud.show_pause(true, "", {"is_calibration": true})
	hud.resume_button.pressed.emit()
	hud.settings_button.pressed.emit()
	hud.sensitivity_button.pressed.emit()
	check(not hud.resume_button.visible and not hud.settings_button.visible and not hud.sensitivity_button.visible and pause_events.resume == 1 and pause_events.settings == 1 and pause_events.sensitivity == 1, "Calibration pause offers no quiet resume or profile editing path.")
	check(hud.resume_button.custom_minimum_size.y == hud.menu_button.custom_minimum_size.y, "Pause controls share the shell's 44-pixel minimum height.")
	hud.show_pause(false)
	hud.flash_hit()
	check(hud._hit_remaining_s == 0.0, "Reduced-motion mode omits cosmetic hit flashes.")
	for style: String in ["dot", "cross", "circle", "t"]:
		var profile := PROFILE.duplicate(true)
		profile.crosshair_style = style
		hud.configure(profile)
		check(hud.crosshair_profile.crosshair_style == style and hud.configured_profile == profile, "All four cosmetic crosshair styles retain the profile: " + style)
	viewport.queue_free()
	await settle()


func test_dimensions() -> void:
	for dimensions: Vector2i in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var viewport := make_viewport(dimensions)
		var shell := make_shell(viewport)
		await settle()
		var expected_columns := 1 if dimensions.x < 900 else 2 if dimensions.x < 1500 else 4
		check(shell.catalog_grid.columns == expected_columns, "Catalogue reflows at " + str(dimensions))
		verify_layout(shell, dimensions, "home")
		await capture(viewport, dimensions, "home")
		shell.show_preparation("EX04")
		await settle()
		verify_layout(shell, dimensions, "preparation")
		check(shell.content_scroll.scroll_vertical == 0, "Preparation keeps its heading visible before scrolling: " + str(dimensions))
		await capture(viewport, dimensions, "preparation")
		shell.show_calibration({"ready": true})
		await settle()
		verify_layout(shell, dimensions, "calibration")
		await capture(viewport, dimensions, "calibration")
		shell.show_calibration({"stage": "preflight", "phase": "express", "active": true, "profile_locked": true, "can_continue": true,
			"preflight": {"reports_received": 4, "records": {"CLICK": {"difficulty": "standard", "diagnostic_utility": 0.05}},
			"proposals": [{"task": "CLICK", "current_level": "standard", "suggested_level": "novice", "can_adjust": true}]}})
		await settle()
		verify_layout(shell, dimensions, "preflight")
		await capture(viewport, dimensions, "preflight")
		shell.update_calibration_availability({})
		shell.show_results(report_fixture())
		await settle()
		verify_layout(shell, dimensions, "results")
		await capture(viewport, dimensions, "results")
		shell.show_settings(PROFILE)
		await settle()
		verify_layout(shell, dimensions, "settings")
		check(shell.content_scroll.scroll_vertical == 0, "Settings focus starts at the first precise field: " + str(dimensions))
		await capture(viewport, dimensions, "settings")
		shell.hide()
		var hud := Hud.new()
		hud.configure(PROFILE)
		viewport.add_child(hud)
		hud.present_live({"program_id": "EX05", "program_title": "Suivi fluide", "difficulty": "standard", "phase_title": "Horizontal",
			"remaining_s": 42.0, "phase_duration_s": 20.0, "phase_remaining_s": 2.0, "next_phase_title": "Vertical",
			"phase_score": 75.0, "metrics": {"contact_s": 15.0, "exposure_s": 18.0}, "ammo": 12, "ammo_capacity": 30})
		await settle()
		check(hud.timer_label.get_global_rect().end.x <= float(dimensions.x) + 1.0, "HUD timer fits at " + str(dimensions))
		check(hud.metric_label.get_global_rect().end.y <= float(dimensions.y) + 1.0, "HUD measurements fit at " + str(dimensions))
		await capture(viewport, dimensions, "hud")
		hud.show_pause()
		await settle()
		check(hud.resume_button.get_global_rect().end.x <= float(dimensions.x), "Pause action fits at " + str(dimensions))
		await capture(viewport, dimensions, "pause")
		viewport.queue_free()
		await settle()


func verify_layout(shell: Shell, dimensions: Vector2i, context: String) -> void:
	var scroll := shell.content_scroll
	var content := scroll.get_child(0) as Control
	check(content.size.x <= scroll.size.x + 1.0, "Native content needs no hidden horizontal scrolling: %s %s (%s / %s)" % [context, dimensions, content.size, scroll.size])
	check(not scroll.get_h_scroll_bar().visible and not scroll.get_v_scroll_bar().visible, "Scrollbars remain hidden while scrolling stays native: " + context)
	check(scroll.follow_focus, "Off-screen controls can be reached by keyboard: " + context)


func capture(viewport: SubViewport, dimensions: Vector2i, context: String) -> void:
	if capture_directory.is_empty():
		return
	var marker := Label.new()
	marker.theme = Shell.make_theme()
	marker.text = "TEST UI V2 · données synthétiques, pas une mesure"
	marker.add_theme_font_size_override("font_size", 14)
	marker.add_theme_color_override("font_color", Shell.PALETTE.caution)
	marker.position = Vector2(12.0, float(dimensions.y) - 24.0)
	viewport.add_child(marker)
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	marker.queue_free()
	check(picture != null and not picture.is_empty(), "Native capture must contain rendered pixels: " + context)
	if picture == null or picture.is_empty():
		return
	var filename := "%s/v2_%s_%dx%d.png" % [capture_directory, context, dimensions.x, dimensions.y]
	check(picture.save_png(filename) == OK, "Native capture is saved: " + filename)


func visible_text(parent: Node) -> String:
	var parts := PackedStringArray()
	for child in parent.get_children():
		if child is Control and not child.is_visible_in_tree():
			continue
		if child is Label or child is Button:
			parts.append(child.text)
		parts.append(visible_text(child))
	return "\n".join(parts)
