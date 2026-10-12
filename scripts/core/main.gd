extends Node

enum Screen { HOME, TEST, PAUSED, COUNTDOWN, TRAINING, RESULTS, REST }

const COUNTDOWN_DURATION_S: float = 3.0

var screen: Screen = Screen.HOME
var paused_from: Screen = Screen.TEST
var window_has_focus: bool = true
var telemetry_elapsed_s: float = 0.0
var store := LocalStore.new()
var engine := ScenarioEngine.new()
var clock := SessionClock.new()
var calibration := CalibrationService.new()
var guided_search := AdaptiveSensitivityService.new()
var is_guided: bool = false
var guided_phase: String = "comparing"
var training_profile: Dictionary = {}
var selected_definition: ScenarioDefinition
var selected_duration_s: float = 30.0
var selected_seed: int = 1337
var training_aspect: float = 16.0 / 9.0
var is_calibrating: bool = false
var session_active: bool = false
var finish_queued: bool = false
var skip_frame_sample: bool = true
var pending_trial: Dictionary = {}
var last_report: Dictionary = {}
var final_recommendation: Dictionary = {}
var rest_until_us: int = 0
var initial_x_counts: float = 0.0
var initial_y_counts: float = 0.0
var start_pose_ready: bool = true
var preparation_engine := ScenarioEngine.new()
var pending_abandon_report: Dictionary = {}
var pending_restart_profile: Dictionary = {}
var unsaved_exit_dialog: ConfirmationDialog

@onready var arena: Node3D = $Arena
@onready var aim_camera: AimCamera = $Arena/AimCamera
@onready var target_pool: TargetPool = $Arena/TargetPool
@onready var reference_sphere: MeshInstance3D = $Arena/ReferenceSphere
@onready var home: AimDashboard = $Interface/Home
@onready var hud: TrainingHud = $Interface/TestHud
@onready var hud_title: Label = hud.title_label
@onready var angles_label: Label = hud.metric_label
@onready var help_label: Label = hud.help_label
@onready var pause_panel: TrainingPause = $Interface/PausePanel
@onready var resume_button: Button = pause_panel.resume_button
@onready var menu_button: Button = pause_panel.menu_button
@onready var session_panel: SessionPanel = $Interface/SessionPanel
@onready var test_button: Button = home.test_button
@onready var quit_button: Button = home.quit_button


func _ready() -> void:
	get_tree().auto_accept_quit = false
	home.bind_profile(store.load_profile())
	if not store.last_error.is_empty():
		home.set_status(store.last_error)
	home.test_requested.connect(start_test)
	home.quit_requested.connect(quit_application)
	home.profile_save_requested.connect(save_profile)
	home.reference_import_requested.connect(import_reference_profile)
	home.training_requested.connect(start_practice)
	home.calibration_requested.connect(start_calibration)
	home.guided_calibration_requested.connect(start_guided_calibration)
	home.guided_resume_requested.connect(resume_guided_calibration)
	home.calibration_resume_requested.connect(resume_calibration)
	home.history_requested.connect(refresh_history)
	home.export_requested.connect(export_history)
	pause_panel.resume_requested.connect(resume_test)
	pause_panel.menu_requested.connect(return_to_menu)
	pause_panel.sensitivity_requested.connect(apply_paused_sensitivity)
	session_panel.next_requested.connect(next_calibration_stage)
	session_panel.retry_requested.connect(retry_training)
	session_panel.menu_requested.connect(return_to_menu)
	session_panel.apply_requested.connect(apply_recommendation)
	session_panel.refine_requested.connect(refine_calibration)
	return_to_menu()


func current_aspect() -> float:
	var size := get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


func apply_profile(profile: Dictionary) -> void:
	aim_camera.degrees_per_count = SensitivityService.degrees_per_count(float(profile.dpi), float(profile.cm_per_360))
	aim_camera.fov = float(profile.vertical_fov_deg)
	aim_camera.invert_y = bool(profile.get("invert_y", false))
	Input.use_accumulated_input = bool(profile.get("accumulated_input", true))
	Engine.max_fps = int(profile.get("max_fps", 144))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if screen in [Screen.TEST, Screen.TRAINING, Screen.COUNTDOWN]:
			pause_test()
		elif screen == Screen.PAUSED:
			resume_test()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not window_has_focus or finish_queued:
		return
	if screen in [Screen.TEST, Screen.TRAINING, Screen.COUNTDOWN] and event is InputEventMouseMotion:
		aim_camera.apply_mouse_counts(event.screen_relative)
		if screen == Screen.TRAINING:
			engine.record_aim(clock.elapsed_s(Time.get_ticks_usec()), aim_camera.yaw_deg, aim_camera.pitch_deg)
	elif screen == Screen.TRAINING and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if selected_definition.family == "tracking":
			hud.weapon_feedback.set_continuous(event.pressed)
		elif event.pressed:
			var hit := engine.shoot(clock.elapsed_s(Time.get_ticks_usec()), -aim_camera.global_basis.z)
			if not engine.completed:
				hud.weapon_feedback.play_shot()
				if hit:
					hud.hit()
		if engine.completed:
			queue_finish()


func _process(delta_s: float) -> void:
	var now_us := Time.get_ticks_usec()
	if screen == Screen.REST:
		session_panel.next_button.disabled = now_us < rest_until_us or not window_has_focus
		session_panel.retry_button.disabled = session_panel.next_button.disabled
		session_panel.update_rest(maxf(float(rest_until_us - now_us) / 1000000.0, 0.0), calibration.current_index + 1 == calibration.plan.size())
		return
	if finish_queued:
		return
	if screen == Screen.COUNTDOWN and clock.elapsed_s(now_us) >= COUNTDOWN_DURATION_S:
		begin_training(now_us)
	if screen == Screen.TRAINING:
		if not is_equal_approx(current_aspect(), training_aspect):
			engine.invalid_reason = "Format de fenêtre modifié pendant l'exercice. Recommencer à conditions fixes."
			finish_training(false)
			return
		if skip_frame_sample:
			skip_frame_sample = false
		else:
			engine.record_frame(delta_s)
		engine.advance_to(clock.elapsed_s(now_us))
		target_pool.sync(engine, engine.elapsed_s)
		if engine.completed:
			queue_finish()
	if screen in [Screen.TEST, Screen.TRAINING, Screen.COUNTDOWN]:
		telemetry_elapsed_s += delta_s
		if telemetry_elapsed_s >= 0.1:
			telemetry_elapsed_s = 0.0
			update_telemetry()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		window_has_focus = false
		pause_test()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		window_has_focus = true
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_application()


func start_test() -> void:
	if screen != Screen.HOME or not window_has_focus:
		return
	is_calibrating = false
	is_guided = false
	activate_test(home.read_profile())


func activate_test(profile: Dictionary) -> void:
	training_profile = profile.duplicate(true)
	apply_profile(profile)
	hud.configure(profile)
	aim_camera.reset_aim()
	reference_sphere.show()
	target_pool.hide_targets()
	telemetry_elapsed_s = 0.0
	Input.flush_buffered_events()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	screen = Screen.TEST
	arena.show()
	home.hide()
	hud.show()
	pause_panel.hide()
	session_panel.hide()
	update_telemetry()


func pause_test() -> void:
	if not screen in [Screen.TEST, Screen.TRAINING, Screen.COUNTDOWN]:
		return
	paused_from = screen
	clock.pause(Time.get_ticks_usec())
	engine.paused = true
	hud.weapon_feedback.stop()
	hud.stop()
	screen = Screen.PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_panel.bind(training_profile, is_calibrating)
	pause_panel.show()
	resume_button.grab_focus()


func resume_test() -> void:
	if screen != Screen.PAUSED or not window_has_focus:
		return
	Input.flush_buffered_events()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	clock.resume(Time.get_ticks_usec())
	engine.paused = false
	screen = paused_from
	skip_frame_sample = true
	pause_panel.hide()


func apply_paused_sensitivity(profile: Dictionary) -> void:
	if screen != Screen.PAUSED or not window_has_focus or is_calibrating:
		return
	var expected := training_profile.duplicate(true)
	expected.cm_per_360 = profile.get("cm_per_360", NAN)
	var error := SensitivityService.validate_profile(expected)
	if error.is_empty() and paused_from != Screen.TEST and not selected_definition.fits_view(float(expected.vertical_fov_deg), current_aspect()):
		error = "Rétablissez le format de fenêtre avant de recommencer."
	if profile != expected or not error.is_empty():
		pause_panel.set_error(error if not error.is_empty() else "Seule la sensibilité peut changer ici.")
		return
	if expected.cm_per_360 == training_profile.cm_per_360:
		return
	if not store.save_profile(expected):
		pause_panel.set_error(store.last_error)
		return
	home.bind_profile(expected)
	if session_active and not finish_training(false, false):
		pending_abandon_report = last_report.duplicate(true)
		pending_restart_profile = expected.duplicate(true)
		screen = Screen.RESULTS
		hud.hide()
		pause_panel.hide()
		arena.hide()
		session_panel.present_result(last_report, result_text(last_report), false, 0, 0)
		session_panel.set_notice("Essai non sauvegardé. Rejouer réessaie l’enregistrement avant de démarrer. " + store.last_error)
		return
	if paused_from == Screen.TEST:
		activate_test(expected)
	else:
		prepare_training(selected_definition, selected_duration_s, next_practice_seed(), expected)


func next_practice_seed() -> int:
	var seed_value := int(Crypto.new().generate_random_bytes(4).decode_u32(0) & 0x7fffffff)
	if seed_value == selected_seed:
		seed_value = (seed_value + 1) & 0x7fffffff
	return seed_value


func save_pending_abandon() -> bool:
	if pending_abandon_report.is_empty():
		return true
	if not store.save_session(pending_abandon_report):
		return false
	pending_abandon_report.clear()
	return true


func return_to_menu() -> void:
	if session_active:
		finish_training(false, false)
	pending_restart_profile.clear()
	if not save_pending_abandon():
		home.set_status("Essai interrompu non sauvegardé : " + store.last_error)
	is_calibrating = false
	is_guided = false
	screen = Screen.HOME
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	arena.hide()
	hud.hide()
	pause_panel.hide()
	session_panel.hide()
	home.show()
	var checkpoint := store.load_checkpoint()
	home.resume_calibration_button.visible = not checkpoint.is_empty()
	home.resume_calibration_button.text = "Voir mon dernier bilan" if checkpoint.get("status", "") == "complete" else "Reprendre"
	var guided_checkpoint := store.load_guided_checkpoint()
	home.guided_resume_button.visible = not guided_checkpoint.is_empty()
	home.guided_resume_button.text = "Revoir la recherche" if guided_checkpoint.get("phase", "") == "complete" else "Reprendre la recherche"
	home.nav_buttons[home.selected_page].grab_focus()


func save_profile() -> void:
	var profile := home.read_profile()
	if store.save_profile(profile):
		apply_profile(profile)
		home.set_status("Sensibilité et préférences enregistrées. Ce réglage est actif dans les exercices.")
	else:
		home.set_status(store.last_error)


func import_reference_profile(profile: Dictionary) -> void:
	if screen != Screen.HOME:
		return
	var reference_error := GameProfileService.validate_reference(profile.get("reference_game", null))
	if not reference_error.is_empty():
		home.set_status(reference_error)
		return
	if not store.save_profile(profile):
		home.set_status(store.last_error)
		return
	home.bind_profile(profile)
	apply_profile(profile)
	home.set_status("Réglage de %s appliqué dans AIM/LOCAL. Retrouvez la conversion dans Conversion." % profile.reference_game.title)


func start_practice(scenario_id: String, duration_s: float) -> void:
	if screen != Screen.HOME:
		return
	is_calibrating = false
	is_guided = false
	prepare_training(ScenarioCatalog.find(scenario_id), duration_s, next_practice_seed(), home.read_profile())


func prepare_training(definition: ScenarioDefinition, duration_s: float, seed_value: int, profile: Dictionary) -> bool:
	if not save_pending_abandon():
		var notice := "Essai précédent non sauvegardé : " + store.last_error
		home.set_status(notice)
		if screen != Screen.HOME:
			session_panel.set_notice(notice)
		return false
	var error := SensitivityService.validate_profile(profile)
	if not window_has_focus or definition == null:
		return false
	if error.is_empty():
		error = definition.validate()
	if error.is_empty() and not definition.fits_view(float(profile.vertical_fov_deg), current_aspect()):
		error = "Champ de vision trop étroit : élargir la fenêtre ou augmenter le FOV."
	if error.is_empty() and is_calibrating and not is_equal_approx(current_aspect(), calibration.aspect):
		error = "Restaurer le format de fenêtre de départ avant le passage suivant."
	if not error.is_empty():
		home.set_status(error)
		if screen != Screen.HOME:
			session_panel.set_notice(error)
		return false
	selected_definition = definition
	selected_duration_s = duration_s
	selected_seed = seed_value
	training_profile = profile.duplicate(true)
	training_aspect = current_aspect()
	finish_queued = false
	pending_trial.clear()
	apply_profile(profile)
	hud.configure(profile)
	aim_camera.reset_aim()
	reference_sphere.hide()
	preparation_engine.start(definition, seed_value, duration_s)
	target_pool.sync(preparation_engine, 0.0)
	Input.flush_buffered_events()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	clock.start(Time.get_ticks_usec())
	start_pose_ready = true
	screen = Screen.COUNTDOWN
	home.hide()
	pause_panel.hide()
	session_panel.hide()
	arena.show()
	hud.show()
	update_telemetry()
	return true


func exercise_zone_fits_start_pose() -> bool:
	if selected_definition == null:
		return false
	var view_basis := aim_camera.global_basis.orthonormalized().inverse()
	for yaw_sign in [-1.0, 1.0]:
		for pitch_sign in [-1.0, 1.0]:
			var direction := AimGeometry.direction(selected_definition.yaw_extent_deg * yaw_sign, selected_definition.pitch_extent_deg * pitch_sign)
			if not AimGeometry.sphere_fits_view(view_basis * direction, selected_definition.maximum_angular_diameter_deg(), aim_camera.fov, current_aspect()):
				return false
	return true


func begin_training(now_us: int) -> void:
	start_pose_ready = exercise_zone_fits_start_pose()
	if not start_pose_ready:
		reference_sphere.show()
		update_telemetry()
		return
	reference_sphere.hide()
	if not engine.start(selected_definition, selected_seed, selected_duration_s, aim_camera.yaw_deg, aim_camera.pitch_deg):
		home.set_status(engine.invalid_reason)
		return_to_menu()
		return
	clock.start(now_us)
	initial_x_counts = aim_camera.received_x_counts
	initial_y_counts = aim_camera.received_y_counts
	screen = Screen.TRAINING
	skip_frame_sample = true
	session_active = true
	target_pool.sync(engine, 0.0)
	update_telemetry()
	hud.show_go()


func queue_finish() -> void:
	if not finish_queued:
		finish_queued = true
		finish_training.call_deferred(true)


func finish_training(finished: bool, show_result: bool = true) -> bool:
	if not session_active:
		return false
	session_active = false
	finish_queued = false
	engine.paused = false
	engine.advance_to(clock.elapsed_s(Time.get_ticks_usec()))
	clock.pause(Time.get_ticks_usec())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	last_report = engine.result(training_profile, training_aspect, finished)
	last_report.session_id = store.identifier()
	last_report.metrics.received_x_counts = aim_camera.received_x_counts - initial_x_counts
	last_report.metrics.received_y_counts = aim_camera.received_y_counts - initial_y_counts
	last_report.warmup = is_calibrating and not calibration.current_stage().get("scored", false)
	last_report.calibration_id = calibration.calibration_id if is_calibrating else ""
	var record_eligible: bool = not is_calibrating and ScoringService.comparison_error(last_report).is_empty()
	var previous_summary: Dictionary = ProgressService.summarize(store.sessions(), last_report.comparison_key) if record_eligible else {"count": 0, "best": 0.0}
	var saved := store.save_session(last_report)
	var body := result_text(last_report)
	if not saved:
		body += "\n\nÉchec de sauvegarde : " + store.last_error
	if not show_result:
		return saved
	hud.hide()
	pause_panel.hide()
	arena.hide()
	var quality_error := ScoringService.calibration_quality_error(last_report) if is_calibrating else ""
	if is_calibrating and last_report.completed and last_report.valid and quality_error.is_empty():
		pending_trial = last_report.duplicate(true)
		screen = Screen.REST
		rest_until_us = Time.get_ticks_usec() + 3000000
		session_panel.present_result(last_report, body, true, calibration.current_index + 1, calibration.plan.size())
		session_panel.present_calibration_context(calibration, pending_trial)
		session_panel.update_rest(3.0, calibration.current_index + 1 == calibration.plan.size())
	else:
		screen = Screen.RESULTS
		session_panel.present_result(last_report, body, false, 0, 0)
		if not quality_error.is_empty():
			session_panel.set_notice("Ce passage n’est pas assez fiable. Rejouez en visant activement et sans saccades.")
			session_panel.body_label.text += "\n\nPassage à refaire : " + quality_error
	if not saved:
		session_panel.set_notice("Résultat non sauvegardé : " + store.last_error)
	elif record_eligible and int(previous_summary.count) > 0 and float(last_report.score) > float(previous_summary.best):
		session_panel.present_record(float(previous_summary.best), bool(training_profile.get("reduced_motion", false)))
	return saved


func result_text(report: Dictionary) -> String:
	var metrics: Dictionary = report.metrics
	var sensitivity_text: String = "Réglage " + ["A", "B", "C"][int(calibration.current_stage().candidate_index)] if is_calibrating else "%.2f cm/360°" % report.profile.cm_per_360
	var body := "%s · %.2f secondes actives · %s\n%s\n" % [report.scenario_id, report.active_duration_s,
		sensitivity_text, "Échauffement exclu des comparaisons" if report.get("warmup", false) else "Séance complète" if report.completed else "Abandon exclu des records"]
	if report.family == "tracking":
		body += "Temps sur cible : %.1f %% (%.2f / %.2f s)\nErreur moyenne : %.2f° · p95 : %.2f° (bins de 0,1°)\nRéacquisition médiane : %.0f ms\nScore v1 : %.0f = 1000 × proportion sur cible" % [100.0 * metrics.on_target_ratio,
			metrics.on_target_time_s, metrics.target_exposed_time_s, metrics.angular_error_mean_deg,
			metrics.angular_error_p95_deg, metrics.reacquisition_median_ms, report.score]
	else:
		var accuracy := "N/A" if metrics.accuracy_pct == null else "%.1f %%" % metrics.accuracy_pct
		body += "Cibles touchées : %d · ratés : %d · tirs : %d · cibles expirées : %d\nPrécision : %s · rythme : %.0f cibles/min\nAcquisition/transition : médiane %.0f ms · p95 %.0f ms\nErreur médiane au clic : %.2f° · efficacité de trajet : %.1f %%\nScore v1 : %.0f (1000 × cadence × précision² / référence ; sans plafond artificiel)" % [metrics.hits, metrics.misses,
			metrics.shots, metrics.targets_expired, accuracy, metrics.hits_per_s * 60.0,
			metrics.acquisition_median_ms, metrics.acquisition_p95_ms, metrics.shot_error_median_deg,
			metrics.path_efficiency_median * 100.0, report.score]
	body += "\nInput reçu : %d événements (pas le polling matériel)\nFrametime p95/p99 : %.2f / %.2f ms · %d frames récentes\nGraine : %d · révision : %d" % [metrics.input_events, report.performance.frametime_p95_ms,
		report.performance.frametime_p99_ms, report.performance.frame_samples, report.seed, report.scenario_revision]
	if not report.valid:
		body += "\nINUTILISABLE POUR LA CALIBRATION : " + report.invalid_reason
	elif not ScoringService.has_activity(report):
		body += "\nActivité insuffisante : exclu de la recommandation et de la progression."
	return body


func start_guided_calibration() -> void:
	if screen != Screen.HOME or not window_has_focus:
		return
	if not save_pending_abandon():
		home.set_status("Essai précédent non sauvegardé : " + store.last_error)
		return
	var search := AdaptiveSensitivityService.new()
	if not search.begin(home.read_profile(), current_aspect(), randi_range(1, 1000000000), store.identifier()):
		home.set_status(search.error)
		return
	var spec := search.current_spec()
	var comparison := CalibrationService.new()
	if not comparison.begin(spec.profile, float(spec.aspect), int(spec.seed), str(spec.calibration_id), spec.speed_factors):
		home.set_status(comparison.error)
		return
	var checkpoint := {"schema_version": 1, "phase": "comparing", "search_state": search.checkpoint(), "comparison": comparison.checkpoint()}
	if not store.save_guided_checkpoint(checkpoint):
		home.set_status(store.last_error)
		return
	guided_search = search
	calibration = comparison
	guided_phase = "comparing"
	is_guided = true
	is_calibrating = true
	final_recommendation.clear()
	start_calibration_stage()


func resume_guided_calibration() -> void:
	if screen != Screen.HOME or not window_has_focus:
		return
	if not save_pending_abandon():
		home.set_status("Essai précédent non sauvegardé : " + store.last_error)
		return
	var checkpoint := store.load_guided_checkpoint()
	if checkpoint.is_empty():
		home.set_status(store.last_error if not store.last_error.is_empty() else "Aucune recherche guidée à reprendre.")
		return
	var search := AdaptiveSensitivityService.new()
	var comparison := CalibrationService.new()
	if not search.restore(checkpoint.search_state) or not comparison.restore(checkpoint.comparison):
		home.set_status(search.error + comparison.error)
		return
	if not is_equal_approx(comparison.aspect, current_aspect()):
		home.set_status("Reprenez avec le même format de fenêtre que lors de la recherche.")
		return
	guided_search = search
	calibration = comparison
	guided_phase = checkpoint.phase
	is_guided = true
	is_calibrating = true
	home.bind_profile(search.initial_profile)
	if guided_phase == "comparing" and not calibration.current_stage().is_empty():
		start_calibration_stage()
	else:
		show_guided_recommendation()


func save_guided_progress(phase: String) -> bool:
	return store.save_guided_checkpoint({"schema_version": 1, "phase": phase,
		"search_state": guided_search.checkpoint(), "comparison": calibration.checkpoint()})


func continue_guided_search() -> void:
	if screen != Screen.RESULTS or not window_has_focus or not is_guided:
		return
	if guided_phase == "comparing":
		show_guided_recommendation()
		return
	if guided_phase != "transition" or guided_search.finished:
		return
	var spec := guided_search.current_spec()
	var comparison := CalibrationService.new()
	if not comparison.begin(spec.profile, float(spec.aspect), int(spec.seed), str(spec.calibration_id), spec.speed_factors):
		session_panel.set_notice(comparison.error)
		return
	var previous_comparison := calibration
	calibration = comparison
	if not save_guided_progress("comparing"):
		calibration = previous_comparison
		session_panel.set_notice(store.last_error)
		return
	guided_phase = "comparing"
	final_recommendation.clear()
	start_calibration_stage()


func show_guided_recommendation() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	home.hide()
	arena.hide()
	hud.hide()
	pause_panel.hide()
	screen = Screen.RESULTS
	var round_report := calibration.recommendation()
	if guided_phase == "comparing":
		var previous_search := guided_search.checkpoint()
		if not guided_search.accept_comparison(round_report):
			session_panel.present_recommendation(round_report, float(calibration.baseline.dpi), guided_search.error)
			session_panel.apply_button.hide()
			session_panel.set_notice(guided_search.error)
			return
		var next_phase := "complete" if guided_search.finished else "transition"
		if not save_guided_progress(next_phase):
			var save_error := store.last_error
			guided_search.restore(previous_search)
			session_panel.present_recommendation(round_report, float(calibration.baseline.dpi), save_error)
			session_panel.apply_button.hide()
			session_panel.next_button.show()
			session_panel.next_button.disabled = false
			session_panel.next_button.text = "Réessayer l’enregistrement"
			session_panel.set_notice(save_error)
			return
		guided_phase = next_phase
	final_recommendation = guided_search.final_result()
	var displayed := final_recommendation.duplicate(true) if guided_search.finished else round_report.duplicate(true)
	displayed.apply_allowed = false
	var body: String = "Recherche guidée · %d comparaisons complètes · DPI constants.\n" % guided_search.history.size()
	for entry in guided_search.history:
		body += "\n%s\n%s\n" % [entry.search_step.spec.label, entry.search_step.reason]
		for candidate in entry.candidates:
			body += "Réglage %s : %.3f cm/360°, utilité relative %.3f, confort %.1f/5.\n" % [["A", "B", "C"][int(candidate.index)], candidate.cm_per_360, candidate.value, candidate.comfort_median]
	body += "\n" + str(final_recommendation.advice)
	session_panel.present_recommendation(displayed, float(calibration.baseline.dpi), body)
	session_panel.present_guided_search(guided_search, not guided_search.finished)
	if not store.save_calibration(round_report):
		session_panel.set_notice("Bilan non sauvegardé : " + store.last_error)


func start_calibration() -> void:
	if screen != Screen.HOME or not window_has_focus:
		return
	if not save_pending_abandon():
		home.set_status("Essai précédent non sauvegardé : " + store.last_error)
		return
	is_guided = false
	var profile := home.read_profile()
	if not calibration.begin(profile, current_aspect(), randi_range(1, 1000000000), store.identifier()):
		home.set_status(calibration.error)
		return
	final_recommendation.clear()
	var old_checkpoint := store.load_checkpoint()
	if not old_checkpoint.is_empty():
		if not store.archive_checkpoint(old_checkpoint):
			home.set_status(store.last_error)
			return
	if not store.save_checkpoint(calibration.checkpoint()):
		home.set_status(store.last_error)
		return
	is_calibrating = true
	start_calibration_stage()


func resume_calibration() -> void:
	if screen != Screen.HOME:
		return
	if not save_pending_abandon():
		home.set_status("Essai précédent non sauvegardé : " + store.last_error)
		return
	is_guided = false
	if not calibration.restore(store.load_checkpoint()):
		home.set_status(calibration.error)
		return
	if not calibration.current_stage().is_empty() and not is_equal_approx(current_aspect(), calibration.aspect):
		home.set_status("Reprendre avec le même format de fenêtre que la calibration d'origine.")
		return
	home.bind_profile(calibration.baseline)
	is_calibrating = true
	start_calibration_stage()


func start_calibration_stage() -> void:
	var stage := calibration.current_stage()
	if stage.is_empty():
		show_recommendation()
		return
	prepare_training(ScenarioCatalog.find(stage.scenario_id), float(stage.duration_s), int(stage.seed), calibration.candidate_profile(int(stage.candidate_index)))


func next_calibration_stage() -> void:
	if is_guided and screen == Screen.RESULTS:
		continue_guided_search()
		return
	if screen != Screen.REST or Time.get_ticks_usec() < rest_until_us or not window_has_focus:
		return
	if pending_trial.is_empty():
		start_calibration_stage()
		return
	if not calibration.accept(pending_trial, int(session_panel.comfort_input.value)):
		session_panel.set_notice(calibration.error)
		return
	var saved: bool = save_guided_progress("comparing") if is_guided else store.save_checkpoint(calibration.checkpoint())
	if not saved:
		calibration.trials.pop_back()
		calibration.current_index -= 1
		session_panel.set_notice(store.last_error + "\nVotre passage reste en mémoire. Réessayez Continuer.")
		return
	pending_trial.clear()
	start_calibration_stage()


func show_recommendation() -> void:
	if is_guided:
		show_guided_recommendation()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	home.hide()
	arena.hide()
	hud.hide()
	pause_panel.hide()
	final_recommendation = calibration.recommendation()
	var status: String = final_recommendation.status
	var captions := {"indicative": "Une sensibilité se détache sur cette séance.", "uncertain": "Réglages trop proches : conserver une plage, puis retester.",
		"insufficient": "Données insuffisantes : il faut trois passages actifs par réglage et par exercice.", "uncomfortable": "Le meilleur score est associé à un mauvais confort : ne pas appliquer automatiquement."}
	var body: String = captions[status] + "\n\n"
	body += "45 passages mesurés · 15 familiarisations exclues · pondérations " + str(final_recommendation.weights) + "\n"
	for candidate in final_recommendation.candidates:
		body += "\nRéglage %s · %.2f cm/360° · score relatif %.0f/1000 · dispersion %.0f · confort %.1f/5\n" % [
			["A", "B", "C"][int(candidate.index)], candidate.cm_per_360, 1000.0 * candidate.value,
			1000.0 * candidate.spread, candidate.comfort_median]
		for scenario_id in CalibrationService.SCENARIOS:
			var detail: Dictionary = candidate.per_scenario[scenario_id]
			body += "%s : médiane %.3f · dispersion %.3f · n=%d\n" % [scenario_id, detail.median_utility, detail.dispersion, detail.samples]
	body += "\nPlage testée compatible : %.2f–%.2f cm/360°. Écart %.1f points, seuil de dispersion %.1f points.\nCes dispersions ne sont pas des intervalles de confiance statistiques.\nRejouer à un autre jour et vérifier à la règle puis dans le jeu." % [
		final_recommendation.range_cm_per_360[0], final_recommendation.range_cm_per_360[1],
		1000.0 * final_recommendation.score_gap, 1000.0 * final_recommendation.dispersion_threshold]
	if final_recommendation.boundary_best:
		body += "\nLe meilleur réglage est au bord de la plage : affiner autour de lui peut tester une autre zone."
	var saved := store.save_calibration(final_recommendation)
	screen = Screen.RESULTS
	session_panel.present_recommendation(final_recommendation, float(calibration.baseline.dpi), body)
	if not saved:
		session_panel.set_notice("Bilan non sauvegardé : " + store.last_error)


func apply_recommendation() -> void:
	var trial_consent: bool = is_guided and final_recommendation.get("trial_allowed", false) and session_panel.guided_confirmation.button_pressed
	if screen != Screen.RESULTS or not (final_recommendation.get("apply_allowed", false) or trial_consent):
		return
	var profile: Dictionary = calibration.baseline.duplicate(true)
	profile.cm_per_360 = snappedf(float(final_recommendation.recommended_cm_per_360), 0.001)
	if not store.save_profile(profile):
		session_panel.set_notice(store.last_error)
		return
	home.bind_profile(profile)
	return_to_menu()
	home.show_page(3)
	home.set_status("Réglage de test appliqué. Confirmez-le un autre jour avant de le garder." if trial_consent else "Sensibilité appliquée. Vous pouvez maintenant la reporter dans votre jeu.")


func refine_calibration() -> void:
	if is_guided:
		return
	if not final_recommendation.get("status", "") in ["indicative", "uncertain"]:
		return
	var profile: Dictionary = calibration.baseline.duplicate(true)
	profile.cm_per_360 = snappedf(float(final_recommendation.best_tested_cm_per_360), 0.001)
	home.bind_profile(profile)
	return_to_menu()
	start_calibration()


func retry_training() -> void:
	if screen not in [Screen.RESULTS, Screen.REST] or not window_has_focus:
		return
	if screen == Screen.REST and Time.get_ticks_usec() < rest_until_us:
		return
	if not pending_restart_profile.is_empty():
		if not save_pending_abandon():
			session_panel.set_notice("Essai non sauvegardé : " + store.last_error)
			return
		if prepare_training(selected_definition, selected_duration_s, next_practice_seed(), pending_restart_profile):
			pending_restart_profile.clear()
		return
	if is_calibrating:
		start_calibration_stage()
	else:
		prepare_training(selected_definition, selected_duration_s, next_practice_seed(), training_profile)


func refresh_history() -> void:
	var results := store.sessions()
	var profile := home.read_profile()
	var seconds: float = [30.0, 60.0, 15.0][home.duration_input.selected]
	var summaries: Array[Dictionary] = []
	for definition in ScenarioCatalog.DEFINITIONS:
		var key := ScoringService.comparison_key(definition, seconds, profile, current_aspect())
		var summary := ProgressService.summarize(results, key)
		summary.title = ScenarioCopy.title(definition)
		summary.scenario_id = definition.scenario_id
		summary.family = definition.family
		summary.comparison_key = key
		summary.duration_s = seconds
		summary.dpi = profile.dpi
		summary.cm_per_360 = profile.cm_per_360
		summaries.append(summary)
	home.show_history(results.size(), summaries)


func export_history() -> void:
	var directory := store.export_sessions()
	home.set_status("CSV + JSON exportés : " + directory if not directory.is_empty() else store.last_error)


func update_telemetry() -> void:
	if screen == Screen.TEST:
		hud.set_training_view(true, true)
		hud.countdown_label.hide()
		hud.progress.hide()
		hud.timer_label.text = "TEST"
		hud.stat_label.text = "ROTATION · COUNTS"
		hud.score_label.text = ""
		hud_title.text = "Vérification souris"
		angles_label.text = "Yaw %+.2f° · Pitch %+.2f°\nCounts X %.0f / Y %.0f" % [aim_camera.yaw_deg, aim_camera.pitch_deg, aim_camera.received_x_counts, aim_camera.received_y_counts]
		help_label.text = "Faites un tour complet avec la souris."
		help_label.show()
		hud.queue_redraw()
		return
	var prefix := ""
	if is_calibrating:
		var stage := calibration.current_stage()
		prefix = "%s · %s · " % [["A", "B", "C"][int(stage.candidate_index)], "Série %d/3" % (int(stage.repetition) + 1) if stage.scored else "Échauffement"]
	hud.set_training_view(screen == Screen.TRAINING, screen == Screen.COUNTDOWN)
	hud.countdown_label.visible = screen == Screen.COUNTDOWN
	if screen == Screen.COUNTDOWN:
		hud_title.text = prefix + ScenarioCopy.title(selected_definition)
		hud.countdown_label.text = "%.0f" % ceil(maxf(COUNTDOWN_DURATION_S - clock.elapsed_s(Time.get_ticks_usec()), 1.0)) if start_pose_ready else "↓" if aim_camera.pitch_deg > 0.0 else "↑" if aim_camera.pitch_deg < 0.0 else "→" if aim_camera.yaw_deg > 0.0 else "←"
		help_label.text = "" if start_pose_ready else "Revenez vers le repère pour démarrer."
		help_label.visible = not start_pose_ready
	else:
		hud.present_live(engine.elapsed_s, engine.duration_s, engine.hits, engine.shots, selected_definition.family == "tracking", engine.on_target_s, engine.integrated_s, selected_definition.reference_hits_s)
	hud.queue_redraw()


func quit_application() -> void:
	hud.weapon_feedback.stop()
	home.weapon_preview.stop()
	if not save_pending_abandon():
		if unsaved_exit_dialog == null:
			unsaved_exit_dialog = ConfirmationDialog.new()
			unsaved_exit_dialog.title = "Essai non sauvegardé"
			unsaved_exit_dialog.dialog_text = "L’essai interrompu n’est pas enregistré. Quitter le perdra."
			unsaved_exit_dialog.ok_button_text = "Quitter sans enregistrer"
			unsaved_exit_dialog.cancel_button_text = "Rester"
			unsaved_exit_dialog.theme = home.theme
			unsaved_exit_dialog.confirmed.connect(func() -> void: get_tree().quit())
			add_child(unsaved_exit_dialog)
		unsaved_exit_dialog.popup_centered(Vector2i(460, 0))
		return
	if session_active:
		finish_training(false, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit()
