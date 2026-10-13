class_name V2AppController
extends Node

const CountdownScript := preload("res://scripts/presentation/countdown_feedback.gd")
const WeaponScript := preload("res://scripts/presentation/weapon_feedback.gd")

enum Screen { MENU, COUNTDOWN, PRACTICE, PAUSED, CALIBRATION }

var screen: Screen = Screen.MENU
var store := V2Store.new()
var engine := V2SessionEngine.new()
var profile: Dictionary = {}
var catalogue: Dictionary = {}
var arena: V2Arena
var shell: V2Shell
var hud: V2TrainingHud
var preview: V2Preview
var weapon: WeaponScript
var countdown: CountdownScript
var calibration: RefCounted
var active_task: RefCounted
var gain_deg_per_relative_unit: float = 0.0
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var _clock_origin_us: int = 0
var _countdown_origin_us: int = 0
var _pause_active_s: float = 0.0
var _resuming: bool = false
var _armed: bool = false
var _focus: bool = true
var _hit_read_index: int = 0
var _hud_elapsed_s: float = 0.0
var _current_session_id: String = ""
var _started_utc: String = ""
var _last_conditions: Dictionary = {}
var _last_report: Dictionary = {}
var _cal_segment_id: String = ""
var _cal_session_origin_us: int = 0
var _cal_segment_origin_s: float = 0.0
var _cal_segment_kind: String = ""
var _cal_wait_offset_s: float = 0.0
var _cal_blocked: bool = false
var _cal_task_actual_start_s: float = 0.0
var _cal_snapshot: Dictionary = {}
var _cal_familiarization: Dictionary = {}
var _application_backup: Dictionary = {}
var _menu_refresh_s: float = 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	Input.use_accumulated_input = false
	catalogue = V2Catalog.load_catalog()
	profile = store.load_profile()
	arena = V2Arena.new()
	arena.name = "ArenaV2"
	add_child(arena)
	var interface := CanvasLayer.new()
	interface.name = "InterfaceV2"
	add_child(interface)
	shell = V2Shell.new()
	shell.name = "ShellV2"
	interface.add_child(shell)
	hud = V2TrainingHud.new()
	hud.name = "HudV2"
	interface.add_child(hud)
	weapon = WeaponScript.new()
	weapon.name = "WeaponFeedback"
	weapon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.add_child(weapon)
	weapon.set_hud_mode(true)
	countdown = CountdownScript.new()
	add_child(countdown)
	preview = V2Preview.new()
	preview.name = "RuntimePreview"
	interface.add_child(preview)
	shell.practice_requested.connect(start_practice)
	shell.profile_requested.connect(save_profile)
	shell.history_requested.connect(refresh_history)
	shell.quit_requested.connect(quit_application)
	shell.menu_requested.connect(return_to_menu)
	shell.resume_requested.connect(resume_practice)
	shell.preview_requested.connect(_start_preview)
	shell.preview_stop_requested.connect(preview.stop)
	shell.preview_pause_requested.connect(func(paused: bool) -> void: preview.paused = paused)
	shell.calibration_requested.connect(start_calibration)
	shell.calibration_continue_requested.connect(continue_calibration)
	shell.calibration_apply_requested.connect(apply_calibration_candidate)
	shell.calibration_undo_requested.connect(undo_calibration)
	if shell.has_signal("calibration_level_adjustment_requested"):
		shell.connect("calibration_level_adjustment_requested", _start_level_adjustment)
	hud.resume_requested.connect(resume_practice)
	hud.menu_requested.connect(return_to_menu)
	if hud.has_signal("settings_requested"):
		hud.connect("settings_requested", _pause_settings)
	if hud.has_signal("sensitivity_edit_requested"):
		hud.connect("sensitivity_edit_requested", _pause_settings)
	RenderingServer.frame_post_draw.connect(_post_draw)
	if not profile.is_empty():
		_apply_profile()
	var runner_path: String = "res://scripts/v2/v2_calibration_runner.gd"
	if ResourceLoader.exists(runner_path):
		var runner_script: Script = load(runner_path)
		calibration = runner_script.new(store)
	_recover_application_backup()
	return_to_menu()
	if catalogue.is_empty():
		shell.set_notice("Le catalogue V2 est invalide. Aucun exercice n’est lancé.")
	elif profile.is_empty():
		shell.set_notice("Profil protégé : " + store.last_error + ". Le fichier d’origine est conservé.")


func _apply_profile() -> void:
	gain_deg_per_relative_unit = V2Canonical.float64_from_hex(str(profile.gain_hex))
	Engine.max_fps = int(profile.max_fps)
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	arena.camera.fov = float(profile.vertical_fov_deg)
	arena.set_target_color(Color.html(str(profile.target_color)))
	hud.configure(profile)
	weapon.configure(WeaponCatalog.find(str(profile.weapon_id)), bool(profile.sound_enabled), float(profile.sound_volume) / 100.0, bool(profile.show_weapon), bool(profile.reduced_motion))
	countdown.configure(bool(profile.sound_enabled), float(profile.sound_volume) / 100.0)


func actual_conditions(difficulty_by_task: Dictionary = {}) -> Dictionary:
	var viewport_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	var refresh_hz: float = DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()) if DisplayServer.get_name() != "headless" else -1.0
	var vertical_deg: float = float(profile.get("vertical_fov_deg", V2Arena.VERTICAL_FOV_DEG))
	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
	var result: Dictionary = {"declared_dpi": profile.dpi, "dpi_source": profile.get("dpi_source", "declared"), "gain_hex": profile.gain_hex,
		"fov_horizontal_deg_at_16_9": rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical_deg * 0.5)) * 16.0 / 9.0)),
		"vertical_fov_deg": vertical_deg, "aspect_ratio": float(viewport_size.x) / maxf(float(viewport_size.y), 1.0),
		"render_resolution_px": [viewport_size.x, viewport_size.y], "render_scale": 1.0, "renderer": renderer,
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(), "os": OS.get_name(), "engine_version": Engine.get_version_info().string,
		"frame_limit_hz": Engine.max_fps, "display_hz_declared": refresh_hz, "display_hz_source": "display_server_reported_not_physical_scanout",
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"input_convention": V2SessionEngine.INPUT_CONVENTION, "input_accumulation": false, "invert_y": bool(profile.invert_y),
		"crosshair": CrosshairProfile.resolve(profile), "target_palette": {"active": profile.target_color, "amber": "#FFB454"},
		"audio": {"enabled": profile.sound_enabled, "volume_percent": profile.sound_volume, "weapon_id": profile.weapon_id},
		"look_profile_id": profile.look_profile_id, "show_weapon": profile.show_weapon, "reduced_motion": profile.reduced_motion,
		"seeded_scored_stimulus_preview": false, "candidate_value_masking": false, "retain_input_trace": false,
		"player_utc_offset_minutes": Time.get_time_zone_from_system().bias}
	if not difficulty_by_task.is_empty():
		result.difficulty_by_task = difficulty_by_task.duplicate(true)
	return result


func save_profile(requested: Dictionary) -> void:
	if screen != Screen.MENU or profile.is_empty():
		return
	var next: Dictionary = profile.duplicate(true)
	for field: String in V2Store.PROFILE_FIELDS:
		if requested.has(field):
			next[field] = requested[field]
	next.schema_version = V2Store.PROFILE_SCHEMA
	next.accumulated_input = false
	if float(next.dpi) != float(profile.dpi) or float(next.cm_per_360) != float(profile.cm_per_360):
		var gain: float = 914.4 / (float(next.dpi) * float(next.cm_per_360))
		next.gain_deg_per_relative_unit = gain
		next.gain_hex = V2Canonical.float64_hex(gain)
	else:
		next.gain_deg_per_relative_unit = profile.gain_deg_per_relative_unit
		next.gain_hex = profile.gain_hex
	if not store.save_profile(next):
		shell.set_notice("Réglage non enregistré : " + store.last_error)
		return
	profile = next
	_apply_profile()
	shell.configure(catalogue, profile, _calibration_ui_state(), store.history())
	_authorize_public_programs()
	shell.show_settings(profile)
	shell.set_notice("Réglage enregistré.")


func start_practice(program_id: String, difficulty: String) -> void:
	if profile.is_empty() or catalogue.is_empty():
		return
	if screen == Screen.CALIBRATION:
		_interrupt_calibration("launch_practice")
	var definition: Dictionary = V2Catalog.find(program_id, difficulty)
	if definition.is_empty():
		shell.set_notice("Exercice non disponible.")
		return
	if not _program_fits(definition):
		shell.set_notice("Ce cadrage coupe les cibles. Élargissez la fenêtre ou le champ de vision avant de démarrer.")
		return
	preview.stop()
	preview.hide()
	_apply_profile()
	yaw_deg = 0.0
	pitch_deg = 0.0
	_last_conditions = actual_conditions()
	_current_session_id = "practice_" + Crypto.new().generate_random_bytes(16).hex_encode()
	_started_utc = Time.get_datetime_string_from_system(true)
	var seed_hex: String = Crypto.new().generate_random_bytes(16).hex_encode()
	if not engine.start(definition, seed_hex, _last_conditions):
		shell.set_notice("Exercice interrompu : " + engine.invalid_reason)
		return
	_hit_read_index = 0
	_resuming = false
	_pause_active_s = 0.0
	_begin_countdown()


func _begin_countdown() -> void:
	Input.flush_buffered_events()
	screen = Screen.COUNTDOWN
	shell.hide()
	arena.show()
	arena.set_pose(yaw_deg, pitch_deg)
	arena.prepare([])
	hud.show()
	hud.show_pause(false)
	hud.begin_countdown(3.0)
	weapon.show()
	countdown.reset_sequence()
	_countdown_origin_us = Time.get_ticks_usec()
	_armed = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _begin_practice(now_us: int) -> void:
	screen = Screen.PRACTICE
	_clock_origin_us = now_us - int(round(_pause_active_s * 1000000.0))
	engine.queue_pose(_pause_active_s, yaw_deg, pitch_deg)
	engine.advance(_pause_active_s)
	countdown.play_go(_focus)
	hud.show_countdown(0.0)
	_resuming = false


func _active_time_s() -> float:
	return maxf(0.0, float(Time.get_ticks_usec() - _clock_origin_us) / 1000000.0)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if screen == Screen.CALIBRATION:
			_interrupt_calibration("manual_pause")
		elif screen in [Screen.PRACTICE, Screen.COUNTDOWN]:
			pause_practice("manual_pause")
		elif screen == Screen.PAUSED and _focus:
			resume_practice()
		get_viewport().set_input_as_handled()
		return
	if not _focus or screen not in [Screen.COUNTDOWN, Screen.PRACTICE, Screen.CALIBRATION] or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var counts: Vector2 = event.screen_relative
		yaw_deg += float(counts.x) * gain_deg_per_relative_unit
		pitch_deg = clampf(pitch_deg - float(counts.y) * gain_deg_per_relative_unit * (-1.0 if bool(profile.invert_y) else 1.0), -89.0, 89.0)
		if screen == Screen.PRACTICE:
			engine.queue_pose(_active_time_s(), yaw_deg, pitch_deg)
		elif screen == Screen.CALIBRATION and active_task != null and _cal_segment_kind in ["measurement", "preflight", "acclimation", "preflight_adjustment"] and not _cal_blocked:
			active_task.queue_pose(_cal_task_time_s(), yaw_deg, pitch_deg)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_armed = true
		if screen == Screen.PRACTICE:
			if _armed:
				engine.queue_fire(_active_time_s(), event.pressed)
			if event.pressed and _armed:
				weapon.play_shot()
			if engine.phase.mechanic in ["tracking", "switching"]:
				weapon.set_continuous(event.pressed and _armed)
		elif screen == Screen.CALIBRATION and active_task != null and _armed and _cal_segment_kind in ["measurement", "preflight", "acclimation", "preflight_adjustment"] and not _cal_blocked:
			active_task.queue_fire(_cal_task_time_s(), event.pressed)


func _process(delta_s: float) -> void:
	if screen == Screen.COUNTDOWN:
		var remaining_s: float = maxf(0.0, 3.0 - float(Time.get_ticks_usec() - _countdown_origin_us) / 1000000.0)
		hud.show_countdown(remaining_s)
		countdown.play_tick(str(ceili(remaining_s)), _focus)
		arena.set_pose(yaw_deg, pitch_deg)
		if remaining_s <= 0.0:
			_begin_practice(Time.get_ticks_usec())
	elif screen == Screen.PRACTICE:
		if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			pause_practice("capture_lost")
			return
		if Vector2i(get_viewport().get_visible_rect().size) != Vector2i(int(_last_conditions.render_resolution_px[0]), int(_last_conditions.render_resolution_px[1])):
			engine.invalidate("render_resolution_changed")
		engine.record_frame(delta_s)
		engine.advance(_active_time_s())
		arena.set_pose(yaw_deg, pitch_deg)
		arena.prepare(engine.snapshot(), engine.elapsed_s)
		while _hit_read_index < engine.hit_events.size():
			hud.flash_hit()
			_hit_read_index += 1
		_hud_elapsed_s += delta_s
		if _hud_elapsed_s >= 0.05:
			_hud_elapsed_s = 0.0
			_present_practice()
		if engine.completed:
			_finish_practice()
	elif screen == Screen.CALIBRATION:
		_process_calibration(delta_s)
	elif screen == Screen.MENU:
		_menu_refresh_s += delta_s
		if _menu_refresh_s >= 10.0 and shell.current_page == "calibration":
			_menu_refresh_s = 0.0
			if shell.has_method("update_calibration_availability"):
				shell.update_calibration_availability(_calibration_ui_state())


func _post_draw() -> void:
	if screen == Screen.PRACTICE and _focus:
		var viewport_valid: bool = arena.prepared_viewport_size == Vector2i(get_viewport().get_visible_rect().size) and arena.is_visible_in_tree() and arena.camera.current
		engine.mark_rendered(arena.prepared_identities.duplicate(), arena.visibly_drawn_identities.duplicate(), _active_time_s(), viewport_valid, arena.prepared_receipt.duplicate(true))
	elif screen == Screen.CALIBRATION and active_task != null and _focus and not _cal_blocked and _cal_segment_kind in ["preflight", "acclimation", "measurement", "preflight_adjustment"]:
		var viewport_valid: bool = arena.prepared_viewport_size == Vector2i(get_viewport().get_visible_rect().size) and arena.is_visible_in_tree() and arena.camera.current
		active_task.mark_rendered(arena.prepared_identities.duplicate(), arena.visibly_drawn_identities.duplicate(), _cal_task_time_s(), viewport_valid, arena.prepared_receipt.duplicate(true))


func _present_practice() -> void:
	var source: Dictionary = engine.live_metrics()
	var shown: Dictionary = {}
	match str(engine.phase.mechanic):
		"click", "opportunity":
			shown = {"hits": source.hits, "shots": source.shots, "accuracy": source.accuracy}
			if engine.phase.mechanic == "opportunity":
				shown.expired = source.expired
		"tracking":
			shown = {"contact_s": source.contact_s, "exposure_s": maxf(0.0, engine.elapsed_s - float(engine.phase.start_s)), "contact_ratio": float(source.contact_s) / maxf(0.001, engine.elapsed_s - float(engine.phase.start_s))}
		"switching":
			shown = {"kills": source.kills, "credited_work": source.credited_work}
	var next_title: String = str(engine.program.phases[engine.phase_index + 1].title) if engine.phase_index + 1 < engine.program.phases.size() else ""
	hud.present_live({"program_id": engine.program.program_id, "title": engine.program.title, "difficulty": engine.program.difficulty, "phase": engine.phase, "elapsed_s": engine.elapsed_s, "duration_s": engine.duration_s, "phase_remaining_s": maxf(0.0, float(engine.phase.start_s) + float(engine.phase.duration_s) - engine.elapsed_s), "next_phase_title": next_title, "metrics": shown, "phase_score": source.score, "target_projections": arena.target_projections, "arena_rect_px": Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)})


func pause_practice(reason: String) -> void:
	if screen not in [Screen.COUNTDOWN, Screen.PRACTICE]:
		return
	if screen == Screen.PRACTICE:
		engine.note_pause(_active_time_s(), reason)
		_pause_active_s = engine.elapsed_s
	if engine.completed:
		_finish_practice()
		return
	screen = Screen.PAUSED
	weapon.stop()
	countdown.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pause(true, "La séance reprendra au même instant. Elle reste hors records continus.")


func resume_practice() -> void:
	if screen != Screen.PAUSED or not _focus:
		return
	_resuming = true
	_begin_countdown()


func _pause_settings() -> void:
	if screen != Screen.PAUSED:
		return
	engine.abandon("settings_changed_during_practice")
	_finish_practice()
	shell.show_settings(profile)
	shell.set_notice("Séance arrêtée. Modifiez le réglage avant de relancer pour garder des mesures comparables.")


func _finish_practice() -> void:
	_last_report = engine.report()
	_last_report.merge({"session_id": _current_session_id, "app_version": "1.0.0", "score_version": "scores_v2.0", "engine_version": Engine.get_version_info().string, "started_utc": _started_utc, "ended_utc": Time.get_datetime_string_from_system(true)})
	var saved: bool = store.save_report(_last_report)
	return_to_menu(false)
	shell.show_results(_last_report)
	if not saved:
		shell.set_notice("Résultat non enregistré : " + store.last_error)


func return_to_menu(show_home: bool = true) -> void:
	if screen == Screen.CALIBRATION:
		_interrupt_calibration("return_to_menu")
	if screen in [Screen.PRACTICE, Screen.PAUSED, Screen.COUNTDOWN] and not engine.completed:
		engine.abandon()
		if not _current_session_id.is_empty():
			var abandoned: Dictionary = engine.report()
			abandoned.merge({"session_id": _current_session_id, "app_version": "1.0.0", "score_version": "scores_v2.0", "started_utc": _started_utc, "ended_utc": Time.get_datetime_string_from_system(true)})
			store.save_report(abandoned)
	screen = Screen.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon.stop()
	weapon.hide()
	countdown.stop()
	hud.hide()
	arena.hide()
	preview.stop()
	preview.hide()
	if not profile.is_empty():
		_apply_profile()
	shell.show()
	shell.configure(catalogue, profile, _calibration_ui_state(), store.history())
	_authorize_public_programs()
	if show_home:
		shell.show_home()


func refresh_history() -> void:
	var rows: Array = store.history()
	var progress_script: Script = load("res://scripts/v2/v2_progress.gd")
	shell.show_history(rows, progress_script.summarize(rows))


func _start_preview(program_id: String, difficulty: String) -> void:
	var definition: Dictionary = V2Catalog.find(program_id, difficulty)
	if definition.is_empty() or screen != Screen.MENU:
		return
	shell.set_preview_content(preview)
	preview.show()
	preview.start(definition, float(profile.vertical_fov_deg), Color.html(str(profile.target_color)))


func _authorize_public_programs() -> void:
	for definition: Dictionary in catalogue.get("programs", []):
		var ready: bool = not profile.is_empty() and _program_fits(definition)
		shell.set_practice_ready(str(definition.program_id), str(definition.difficulty), ready, "" if ready else "Élargissez la fenêtre ou le champ de vision pour garder toutes les cibles dans le cadre.")


func _program_fits(definition: Dictionary) -> bool:
	if profile.is_empty():
		return false
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	for stage: Dictionary in definition.phases:
		var diameter_deg: float = float(stage.diameter_deg)
		if str(stage.size.mode) == "world_radius_constant":
			var radius_m: float = float(stage.size.reference_distance_m) * sin(deg_to_rad(diameter_deg * 0.5))
			diameter_deg = rad_to_deg(2.0 * asin(radius_m / float(stage.envelope.center_distance_m[0])))
		for horizontal_deg: float in stage.envelope.center_yaw_deg:
			for vertical_deg: float in stage.envelope.center_pitch_deg:
				if not V2Geometry.sphere_fits(V2Geometry.direction_deg(horizontal_deg, vertical_deg), diameter_deg, float(profile.vertical_fov_deg), aspect):
					return false
	return true


func _calibration_ui_state() -> Dictionary:
	var state: Dictionary = calibration.ui_state(_now_unix_s(), _local_date(), Time.get_time_zone_from_system().bias) if calibration != null else {"ready": false, "notice": "Le protocole natif attend son initialisation."}
	state.can_undo = not _application_backup.is_empty()
	if bool(state.get("active", false)):
		state.stage = "preflight_review" if _cal_blocked and _cal_segment_kind == "preflight" else "countdown" if _cal_blocked else _cal_segment_kind
		state.task_title = _cal_task_title(str(state.get("task", "")))
		state.plan_frozen = true
	if not state.get("candidate", {}).is_empty():
		state.candidate = state.candidate.duplicate(true)
	return state


func start_calibration(mode: String, settings: Dictionary) -> void:
	if calibration == null or profile.is_empty():
		return
	_start_calibration_plan(mode, settings)


func continue_calibration() -> void:
	_continue_calibration_plan()


func apply_calibration_candidate(candidate: Dictionary) -> void:
	_apply_calibration_result(candidate)


func undo_calibration() -> void:
	_undo_calibration_result()


func _start_calibration_plan(mode: String, settings: Dictionary) -> void:
	if screen != Screen.MENU or calibration == null:
		return
	var prepared: bool = false
	if mode == "express":
		var options: Dictionary = settings.duplicate(true)
		options.levels = settings.get("difficulty_by_task", settings.get("levels", {"CLICK": "standard", "SMOOTH": "standard", "REACTIVE": "standard", "SWITCH": "standard"}))
		prepared = calibration.prepare_express(profile, actual_conditions(), options)
	elif mode == "confirmation":
		prepared = calibration.prepare_confirmation(actual_conditions(), _now_unix_s(), _local_date())
	elif mode == "restart_express":
		if not _archive_calibration_plan():
			return
		calibration = load("res://scripts/v2/v2_calibration_runner.gd").new(store)
		_start_calibration_plan("express", settings)
		return
	shell.configure(catalogue, profile, _calibration_ui_state(), store.history())
	shell.show_calibration(_calibration_ui_state())
	if not prepared:
		shell.set_notice("Le parcours n’est pas prêt : " + str(calibration.error))


func _continue_calibration_plan() -> void:
	if calibration == null:
		return
	var now_unix: float = _now_unix_s()
	if screen == Screen.CALIBRATION and calibration.active and _cal_blocked:
		if not calibration.ready_task(_cal_segment_id, now_unix):
			shell.set_notice("Départ non validé : " + str(calibration.error))
			return
		if not bool(calibration.active):
			screen = Screen.MENU
			return_to_menu(false)
			shell.show_calibration(_calibration_ui_state())
			return
		_cal_wait_offset_s = float(calibration._wait_total())
		_cal_session_origin_us = _now_us() - int(round((float(_cal_snapshot.get("start_s", 0.0)) + _cal_wait_offset_s) * 1000000.0))
		_cal_blocked = false
		_cal_segment_kind = ""
		_armed = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		shell.hide()
		hud.show()
		countdown.reset_sequence()
		return
	if screen != Screen.MENU:
		return
	var state: Dictionary = _calibration_ui_state()
	if not bool(state.get("can_continue", false)):
		shell.show_calibration(state)
		return
	preview.stop()
	preview.hide()
	var before_us: int = _now_us()
	if not calibration.start_day(int(state.get("next_day_role", 0)), now_unix, _local_date(), actual_conditions()):
		shell.show_calibration(_calibration_ui_state())
		shell.set_notice("Séance non démarrée : " + str(calibration.error))
		return
	_cal_session_origin_us = before_us
	_cal_wait_offset_s = 0.0
	_cal_segment_id = ""
	_cal_segment_kind = ""
	_cal_snapshot.clear()
	_cal_familiarization.clear()
	_cal_blocked = false
	active_task = null
	yaw_deg = 0.0
	pitch_deg = 0.0
	screen = Screen.CALIBRATION
	gain_deg_per_relative_unit = float(calibration.temporary_gain_deg_per_relative_unit)
	shell.hide()
	hud.show()
	arena.show()
	weapon.stop()
	weapon.hide()
	_armed = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_calibration_result(candidate: Dictionary) -> void:
	if screen != Screen.MENU or calibration == null:
		return
	var state: Dictionary = _calibration_ui_state()
	if not bool(state.get("can_apply", false)) or V2Canonical.semantic_sha256(candidate) != V2Canonical.semantic_sha256(state.get("candidate", {})):
		shell.set_notice("Ce candidat n’a pas de confirmation complète permettant son application.")
		return
	var baseline: Dictionary = calibration.baseline_profile.duplicate(true)
	var updated: Dictionary = baseline.duplicate(true)
	var gain: float = V2CalibrationService.gain_value(candidate)
	updated.gain_deg_per_relative_unit = gain
	updated.gain_hex = V2Canonical.float64_hex(gain)
	updated.cm_per_360 = 914.4 / (float(updated.dpi) * gain)
	var action: Dictionary = {"schema_version": "aimlocal.calibration_application.v2.0", "session_id": "application_" + Crypto.new().generate_random_bytes(16).hex_encode(), "catalogue_revision": V2Catalog.REVISION, "score_version": "cal_utilities_R2", "kind": "application_intent", "created_utc": Time.get_datetime_string_from_system(true), "baseline_profile": baseline, "candidate_profile": updated, "plan_sha256": calibration.plan.plan_sha256, "result": calibration.result.duplicate(true), "explicit_consent": true}
	if not store.save_report(action) or not _archive_calibration_plan():
		shell.set_notice("Changement non appliqué : " + store.last_error)
		return
	if not store.save_profile(updated):
		shell.set_notice("Réglage initial conservé : " + store.last_error)
		return
	var commit: Dictionary = action.duplicate(true)
	commit.session_id = action.session_id + "_committed"
	commit.kind = "application_committed"
	if not store.save_report(commit):
		store.save_profile(baseline)
		shell.set_notice("Validation du changement impossible. Le profil initial est restauré.")
		return
	_application_backup = commit
	profile = updated
	calibration = load("res://scripts/v2/v2_calibration_runner.gd").new(store)
	_apply_profile()
	shell.configure(catalogue, profile, _calibration_ui_state(), store.history())
	shell.show_calibration(_calibration_ui_state())
	shell.set_notice("Candidat appliqué. Vous pouvez revenir au réglage précédent.")


func _undo_calibration_result() -> void:
	if screen != Screen.MENU or _application_backup.is_empty() or not store.load_calibration_state().is_empty():
		return
	var baseline: Dictionary = _application_backup.baseline_profile.duplicate(true)
	var action: Dictionary = {"schema_version": "aimlocal.calibration_application.v2.0", "session_id": "undo_" + Crypto.new().generate_random_bytes(16).hex_encode(), "catalogue_revision": V2Catalog.REVISION, "score_version": "cal_utilities_R2", "kind": "application_undo_intent", "created_utc": Time.get_datetime_string_from_system(true), "application_session_id": _application_backup.session_id, "baseline_profile": baseline, "explicit_consent": true}
	if not store.save_report(action) or not store.save_profile(baseline):
		shell.set_notice("Retour non enregistré : " + store.last_error)
		return
	var committed: Dictionary = action.duplicate(true)
	committed.session_id = action.session_id + "_committed"
	committed.kind = "application_undo"
	if not store.save_report(committed):
		store.save_profile(_application_backup.candidate_profile)
		shell.set_notice("Retour non validé. Le candidat reste votre réglage.")
		return
	profile = baseline
	_application_backup.clear()
	calibration = load("res://scripts/v2/v2_calibration_runner.gd").new(store)
	_apply_profile()
	shell.configure(catalogue, profile, _calibration_ui_state(), store.history())
	shell.show_settings(profile)
	shell.set_notice("Réglage précédent restauré, avec son gain exact.")


func _cal_task_time_s() -> float:
	return maxf(0.0, float(_now_us() - _cal_session_origin_us) / 1000000.0 - _cal_segment_origin_s)


func _now_us() -> int:
	return Time.get_ticks_usec()


func _now_unix_s() -> float:
	return Time.get_unix_time_from_system()


func _local_date() -> String:
	return Time.get_date_string_from_system()


func _process_calibration(delta_s: float) -> void:
	if calibration == null or not bool(calibration.active):
		_interrupt_calibration("calibration_not_active")
		return
	if not _cal_blocked and DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_interrupt_calibration("capture_loss")
		return
	var current_conditions: Dictionary = actual_conditions()
	if not calibration.plan.is_empty() and current_conditions.render_resolution_px != calibration.plan.condition_snapshot.render_resolution_px:
		_interrupt_calibration("configuration_hash_change")
		return
	var wall_elapsed_s: float = maxf(0.0, float(_now_us() - _cal_session_origin_us) / 1000000.0)
	var planned_elapsed_s: float = maxf(0.0, wall_elapsed_s - _cal_wait_offset_s)
	if _cal_blocked:
		return
	var snapshot: Dictionary = calibration.timeline_at(planned_elapsed_s)
	if not calibration.error.is_empty() and str(snapshot.get("kind", "")) == "done":
		_interrupt_calibration("clock_discontinuity")
		return
	var kind: String = str(snapshot.kind)
	var segment_id: String = str(snapshot.segment_id)
	if active_task != null and _cal_segment_kind in ["measurement", "preflight", "acclimation", "preflight_adjustment"] and (segment_id != _cal_segment_id or kind != _cal_segment_kind):
		var completing_adjustment: bool = _cal_segment_kind == "preflight_adjustment"
		if not _finish_calibration_task(wall_elapsed_s):
			return
		if completing_adjustment:
			planned_elapsed_s = maxf(float(calibration._last_elapsed_s), wall_elapsed_s - _cal_wait_offset_s)
			snapshot = calibration.timeline_at(planned_elapsed_s)
			kind = str(snapshot.kind)
			segment_id = str(snapshot.segment_id)
	_cal_snapshot = snapshot
	gain_deg_per_relative_unit = float(snapshot.get("gain", calibration.temporary_gain_deg_per_relative_unit))
	if kind == "done":
		var finished: Dictionary = calibration.finish_day(_now_unix_s(), _local_date())
		if finished.is_empty():
			_interrupt_calibration("abort")
			return
		active_task = null
		screen = Screen.MENU
		return_to_menu(false)
		shell.show_calibration(_calibration_ui_state())
		return
	if bool(snapshot.get("blocked", false)):
		_cal_segment_id = segment_id
		_cal_segment_kind = kind
		_cal_blocked = true
		arena.prepare([])
		hud.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		shell.show()
		shell.show_calibration(_calibration_ui_state())
		return
	var changed: bool = segment_id != _cal_segment_id or kind != _cal_segment_kind
	if changed:
		_cal_segment_id = segment_id
		_cal_segment_kind = kind
		_hit_read_index = 0
		_hud_elapsed_s = 0.0
		if kind == "countdown":
			active_task = load("res://scripts/v2/v2_calibration_task.gd").new()
			var task_conditions: Dictionary = _cal_actual_conditions()
			if not active_task.start(snapshot.deck, 24.0, task_conditions):
				_interrupt_calibration("unknown_resource_revision")
				return
			_cal_segment_origin_s = float(snapshot.end_s) + _cal_wait_offset_s
			countdown.reset_sequence()
			_armed = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		elif kind in ["preflight", "acclimation", "preflight_adjustment"]:
			active_task = load("res://scripts/v2/v2_calibration_task.gd").new()
			var familiarization_conditions: Dictionary = _cal_actual_conditions()
			familiarization_conditions["comparative_utility_included"] = false
			if not active_task.start(snapshot.deck, float(snapshot.end_s) - float(snapshot.start_s), familiarization_conditions):
				_interrupt_calibration("unknown_resource_revision")
				return
			_cal_segment_origin_s = float(snapshot.start_s) + _cal_wait_offset_s
			_cal_task_actual_start_s = _cal_segment_origin_s
			active_task.queue_pose(0.0, yaw_deg, pitch_deg)
		elif kind == "measurement":
			if active_task == null:
				_interrupt_calibration("unknown_resource_revision")
				return
			_cal_task_actual_start_s = float(snapshot.start_s) + _cal_wait_offset_s
			active_task.queue_pose(0.0, yaw_deg, pitch_deg)
			countdown.play_go(_focus)
		else:
			active_task = null
			countdown.stop()
	arena.set_pose(yaw_deg, pitch_deg)
	if kind in ["preflight", "acclimation", "measurement", "preflight_adjustment"]:
		active_task.record_frame(delta_s)
		active_task.advance(_cal_task_time_s())
		arena.prepare(active_task.snapshot(), active_task.elapsed_s)
		while _hit_read_index < active_task.hit_events.size():
			hud.flash_hit()
			_hit_read_index += 1
		if not active_task.invalid_reason.is_empty():
			_interrupt_calibration(str(active_task.invalid_reason))
			return
	else:
		arena.prepare([])
	hud.show()
	shell.hide()
	var remaining_s: float = maxf(0.0, float(snapshot.end_s) - planned_elapsed_s)
	if kind == "countdown":
		hud.show_countdown(remaining_s)
		countdown.play_tick(str(ceili(remaining_s)), _focus)
	else:
		hud.present_live({"is_calibration": true, "title": "Calibration", "task_title": _cal_task_title(str(snapshot.get("task", ""))) if kind not in ["rest", "recovery"] else "Repos", "remaining_s": remaining_s, "duration_s": float(snapshot.end_s) - float(snapshot.start_s), "elapsed_s": planned_elapsed_s - float(snapshot.start_s), "target_projections": arena.target_projections, "arena_rect_px": Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)})


func _cal_actual_conditions() -> Dictionary:
	var actual: Dictionary = actual_conditions()
	actual.gain_hex = V2Canonical.float64_hex(gain_deg_per_relative_unit)
	return actual


func _finish_calibration_task(actual_end_s: float) -> bool:
	active_task.advance(active_task.duration_s)
	var report: Dictionary = active_task.report()
	if not bool(report.get("complete", false)) or not bool(report.get("valid", false)):
		_interrupt_calibration(str(report.get("invalid_reason", "unknown_resource_revision")))
		return false
	if _cal_segment_kind == "preflight":
		_cal_familiarization[str(active_task.task)] = {"complete": true, "utility": report.get("diagnostic_utility"), "opportunities": report.get("opportunities"), "duration_s": report.duration_s}
		if calibration.has_method("record_familiarization"):
			if not calibration.record_familiarization(_cal_segment_id, report):
				_interrupt_calibration("unknown_resource_revision")
				return false
	elif _cal_segment_kind == "preflight_adjustment":
		if not calibration.accept_level_adjustment(_cal_segment_id, report, _cal_actual_conditions(), _now_unix_s()):
			_interrupt_calibration("unknown_resource_revision")
			return false
		_cal_wait_offset_s = float(calibration._wait_total())
	if _cal_segment_kind == "measurement":
		report.actual_start_s = _cal_task_actual_start_s
		report.actual_end_s = maxf(actual_end_s, _cal_task_actual_start_s + 24.0)
		report.session_id = "trace_" + str(calibration._calibration_id) + "." + _cal_segment_id
		report.catalogue_revision = V2Catalog.REVISION
		report.score_version = "cal_utilities_R2"
		report.app_version = "1.0.0"
		report.data_origin = _cal_actual_conditions().get("data_origin", "measured_local_player_received_input")
		report = V2Canonical.json_ready(report)
		if not store.save_report(report):
			_interrupt_calibration("unknown_resource_revision")
			shell.set_notice("Audit non enregistré : " + store.last_error)
			return false
		report.trace_reference = {"session_id": report.session_id, "semantic_sha256": V2Canonical.semantic_sha256(report)}
		if not calibration.accept_task(_cal_segment_id, report, _cal_actual_conditions(), _now_unix_s()):
			_interrupt_calibration("configuration_hash_change")
			shell.set_notice("Mesure non validée : " + str(calibration.error))
			return false
	active_task = null
	return true


static func _cal_task_title(task: String) -> String:
	return {"CLICK": "Clic · une première tentative par cible", "SMOOTH": "Suivi fluide · gardez le contact", "REACTIVE": "Suivi réactif · corrigez les inversions", "SWITCH": "Transitions · maintenez le tir sur la cible active"}.get(task, "Calibration")


func _start_level_adjustment(task: String, difficulty: String) -> void:
	if screen != Screen.CALIBRATION or not _cal_blocked or _cal_segment_kind != "preflight":
		return
	var trial: Dictionary = calibration.prepare_level_adjustment(task, difficulty)
	if trial.is_empty():
		shell.set_notice("Test de niveau indisponible : " + str(calibration.error))
		return
	_continue_calibration_plan()


func _archive_calibration_plan() -> bool:
	var state: Dictionary = store.load_calibration_state()
	if state.is_empty():
		return store.last_error.is_empty()
	var archive: Dictionary = {"schema_version": "aimlocal.calibration_archive.v2.0", "session_id": "archive_" + Crypto.new().generate_random_bytes(16).hex_encode(), "catalogue_revision": V2Catalog.REVISION, "score_version": "cal_utilities_R2", "kind": "calibration_archive", "created_utc": Time.get_datetime_string_from_system(true), "state": state}
	return store.save_report(archive) and store.clear_calibration_state()


func _recover_application_backup() -> void:
	var committed: Array = []
	var intents: Array = []
	var committed_ids: Dictionary = {}
	var undone: Dictionary = {}
	for row: Dictionary in store.history():
		var report: Dictionary = row.get("report", {})
		if report.get("kind") == "application_committed":
			committed.append(report)
			committed_ids[str(report.session_id).trim_suffix("_committed")] = true
		elif report.get("kind") == "application_intent":
			intents.append(report)
		elif report.get("kind") == "application_undo":
			undone[str(report.get("application_session_id", ""))] = true
	for intent: Dictionary in intents:
		if committed_ids.has(intent.session_id) or intent.get("explicit_consent") != true:
			continue
		if intent.get("candidate_profile", {}).get("gain_hex") == profile.get("gain_hex") and store.load_calibration_state().is_empty() and V2Store._profile_valid(intent.get("baseline_profile", {})):
			if store.save_profile(intent.baseline_profile):
				profile = intent.baseline_profile.duplicate(true)
	committed.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return str(first.get("created_utc", "")) > str(second.get("created_utc", "")))
	for report: Dictionary in committed:
		if not undone.has(report.session_id) and report.get("candidate_profile", {}).get("gain_hex") == profile.get("gain_hex"):
			_application_backup = report.duplicate(true)
			break


func _interrupt_calibration(reason: String) -> void:
	if calibration != null:
		calibration._interrupt_at(reason, _now_unix_s())
	if active_task != null:
		active_task.invalidate(reason)
	active_task = null
	screen = Screen.MENU
	return_to_menu(false)
	shell.show_calibration(_calibration_ui_state())


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus = false
		if screen == Screen.CALIBRATION:
			_interrupt_calibration("focus_lost")
		else:
			pause_practice("focus_lost")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus = true
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_application()


func quit_application() -> void:
	if screen == Screen.CALIBRATION:
		_interrupt_calibration("application_closed")
	return_to_menu(false)
	get_tree().quit()
