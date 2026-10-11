extends Node

enum Screen { HOME, TEST, PAUSED, COUNTDOWN, TRAINING, RESULTS, REST }

var screen: Screen = Screen.HOME
var paused_from: Screen = Screen.TEST
var window_has_focus: bool = true
var telemetry_elapsed_s: float = 0.0
var store := LocalStore.new()
var engine := ScenarioEngine.new()
var clock := SessionClock.new()
var calibration := CalibrationService.new()
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

@onready var arena: Node3D = $Arena
@onready var aim_camera: AimCamera = $Arena/AimCamera
@onready var target_pool: TargetPool = $Arena/TargetPool
@onready var reference_sphere: MeshInstance3D = $Arena/ReferenceSphere
@onready var home: AimDashboard = $Interface/Home
@onready var hud: Control = $Interface/TestHud
@onready var hud_title: Label = $Interface/TestHud/Margin/Rows/Title
@onready var angles_label: Label = $Interface/TestHud/Margin/Rows/Angles
@onready var help_label: Label = $Interface/TestHud/Margin/Rows/Help
@onready var pause_panel: Control = $Interface/PausePanel
@onready var resume_button: Button = $Interface/PausePanel/Center/Card/Content/ResumeButton
@onready var menu_button: Button = $Interface/PausePanel/Center/Card/Content/MenuButton
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
	home.training_requested.connect(start_practice)
	home.calibration_requested.connect(start_calibration)
	home.calibration_resume_requested.connect(resume_calibration)
	home.history_requested.connect(refresh_history)
	home.export_requested.connect(export_history)
	resume_button.pressed.connect(resume_test)
	menu_button.pressed.connect(return_to_menu)
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
		get_viewport().set_input_as_handled()
		return
	if not window_has_focus or finish_queued:
		return
	if screen in [Screen.TEST, Screen.TRAINING, Screen.COUNTDOWN] and event is InputEventMouseMotion:
		aim_camera.apply_mouse_counts(event.screen_relative)
		if screen == Screen.TRAINING:
			engine.record_aim(clock.elapsed_s(Time.get_ticks_usec()), aim_camera.yaw_deg, aim_camera.pitch_deg)
	elif screen == Screen.TRAINING and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		engine.shoot(clock.elapsed_s(Time.get_ticks_usec()), -aim_camera.global_basis.z)
		if engine.completed:
			queue_finish()


func _process(delta_s: float) -> void:
	var now_us := Time.get_ticks_usec()
	if screen == Screen.REST:
		session_panel.next_button.disabled = now_us < rest_until_us or not window_has_focus
		return
	if finish_queued:
		return
	if screen == Screen.COUNTDOWN and clock.elapsed_s(now_us) >= 2.0:
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
	apply_profile(home.read_profile())
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
	screen = Screen.PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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


func return_to_menu() -> void:
	if session_active:
		finish_training(false, false)
	is_calibrating = false
	screen = Screen.HOME
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	arena.hide()
	hud.hide()
	pause_panel.hide()
	session_panel.hide()
	home.show()
	var checkpoint := store.load_checkpoint()
	home.resume_calibration_button.visible = not checkpoint.is_empty()
	home.resume_calibration_button.text = "Revoir le dernier bilan de calibration" if checkpoint.get("status", "") == "complete" else "Reprendre la calibration sauvegardée"
	test_button.grab_focus()


func save_profile() -> void:
	var profile := home.read_profile()
	home.set_status("Profil enregistré localement." if store.save_profile(profile) else store.last_error)


func start_practice(scenario_id: String, duration_s: float) -> void:
	if screen != Screen.HOME:
		return
	is_calibrating = false
	prepare_training(ScenarioCatalog.find(scenario_id), duration_s, 1337, home.read_profile())


func prepare_training(definition: ScenarioDefinition, duration_s: float, seed_value: int, profile: Dictionary) -> bool:
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
			session_panel.body_label.text += "\n" + error
		return false
	selected_definition = definition
	selected_duration_s = duration_s
	selected_seed = seed_value
	training_profile = profile.duplicate(true)
	training_aspect = current_aspect()
	finish_queued = false
	pending_trial.clear()
	apply_profile(profile)
	aim_camera.reset_aim()
	reference_sphere.hide()
	target_pool.hide_targets()
	Input.flush_buffered_events()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	clock.start(Time.get_ticks_usec())
	screen = Screen.COUNTDOWN
	home.hide()
	pause_panel.hide()
	session_panel.hide()
	arena.show()
	hud.show()
	update_telemetry()
	return true


func begin_training(now_us: int) -> void:
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


func queue_finish() -> void:
	if not finish_queued:
		finish_queued = true
		finish_training.call_deferred(true)


func finish_training(finished: bool, show_result: bool = true) -> void:
	if not session_active:
		return
	session_active = false
	finish_queued = false
	engine.paused = false
	engine.advance_to(clock.elapsed_s(Time.get_ticks_usec()))
	clock.pause(Time.get_ticks_usec())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	last_report = engine.result(training_profile, training_aspect, finished)
	last_report.metrics.received_x_counts = aim_camera.received_x_counts - initial_x_counts
	last_report.metrics.received_y_counts = aim_camera.received_y_counts - initial_y_counts
	last_report.warmup = is_calibrating and not calibration.current_stage().get("scored", false)
	last_report.calibration_id = calibration.calibration_id if is_calibrating else ""
	var saved := store.save_session(last_report)
	var body := result_text(last_report)
	if not saved:
		body += "\n\nÉchec de sauvegarde : " + store.last_error
	if not show_result:
		return
	hud.hide()
	pause_panel.hide()
	arena.hide()
	var quality_error := ScoringService.calibration_quality_error(last_report) if is_calibrating else ""
	if is_calibrating and last_report.completed and last_report.valid and quality_error.is_empty():
		pending_trial = last_report.duplicate(true)
		screen = Screen.REST
		rest_until_us = Time.get_ticks_usec() + 3000000
		var caption := "Familiarisation non notée" if last_report.warmup else "Passage mesuré"
		session_panel.present(caption + " · %d / %d" % [calibration.current_index + 1, calibration.plan.size()], body + "\n\nRepos d'au moins 3 secondes. Indiquez votre confort avant de continuer.", true)
		session_panel.next_button.text = "Voir la recommandation" if calibration.current_index + 1 == calibration.plan.size() else "Passage suivant"
	else:
		screen = Screen.RESULTS
		session_panel.present("Résultat" if last_report.completed else "Passage interrompu", body + ("\n\nPassage à refaire : " + quality_error if not quality_error.is_empty() else ""))


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
		body += "Touches : %d · ratés : %d · tirs : %d · cibles expirées : %d\nPrécision : %s · cadence : %.1f touches/min\nAcquisition/transition : médiane %.0f ms · p95 %.0f ms\nErreur médiane au clic : %.2f° · efficacité de trajet : %.1f %%\nScore v1 : %.0f (1000 × cadence × précision² / référence ; sans plafond artificiel)" % [metrics.hits, metrics.misses,
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


func start_calibration() -> void:
	if screen != Screen.HOME or not window_has_focus:
		return
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
	if screen != Screen.REST or Time.get_ticks_usec() < rest_until_us or not window_has_focus:
		return
	if pending_trial.is_empty():
		start_calibration_stage()
		return
	if not calibration.accept(pending_trial, int(session_panel.comfort_input.value)):
		session_panel.body_label.text += "\n" + calibration.error
		return
	if not store.save_checkpoint(calibration.checkpoint()):
		calibration.trials.pop_back()
		calibration.current_index -= 1
		session_panel.body_label.text += "\n" + store.last_error + "\nPassage conservé en mémoire ; réessayer la sauvegarde."
		return
	pending_trial.clear()
	start_calibration_stage()


func show_recommendation() -> void:
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
	if not store.save_calibration(final_recommendation):
		body += "\nSauvegarde du bilan en échec : " + store.last_error
	screen = Screen.RESULTS
	session_panel.present("Votre sensibilité repère", body)
	session_panel.retry_button.hide()
	session_panel.apply_button.visible = bool(final_recommendation.apply_allowed)
	session_panel.refine_button.visible = status in ["indicative", "uncertain"]


func apply_recommendation() -> void:
	if screen != Screen.RESULTS or not final_recommendation.get("apply_allowed", false):
		return
	var profile: Dictionary = calibration.baseline.duplicate(true)
	profile.cm_per_360 = snappedf(float(final_recommendation.recommended_cm_per_360), 0.001)
	if not store.save_profile(profile):
		session_panel.body_label.text += "\n" + store.last_error
		return
	home.bind_profile(profile)
	return_to_menu()
	home.set_status("Sensibilité appliquée : %.3f cm/360°. Les valeurs CS2/Valorant sont dans Convertir." % profile.cm_per_360)


func refine_calibration() -> void:
	if not final_recommendation.get("status", "") in ["indicative", "uncertain"]:
		return
	var profile: Dictionary = calibration.baseline.duplicate(true)
	profile.cm_per_360 = snappedf(float(final_recommendation.best_tested_cm_per_360), 0.001)
	home.bind_profile(profile)
	return_to_menu()
	start_calibration()


func retry_training() -> void:
	if screen != Screen.RESULTS:
		return
	if is_calibrating:
		start_calibration_stage()
	else:
		prepare_training(selected_definition, selected_duration_s, selected_seed, training_profile)


func refresh_history() -> void:
	var results := store.sessions()
	var profile := home.read_profile()
	var seconds: float = [30.0, 60.0, 15.0][home.duration_input.selected]
	var text := "%d séances locales ; contexte actuel : %.2f cm/360°, %.0f DPI, %.0f s, FOV vertical %.0f°.\n" % [results.size(), profile.cm_per_360, profile.dpi, seconds, profile.vertical_fov_deg]
	for definition in ScenarioCatalog.DEFINITIONS:
		var key := ScoringService.comparison_key(definition, seconds, profile, current_aspect())
		var summary := ProgressService.summarize(results, key)
		var trend := "tendance : données insuffisantes (10 séances nécessaires)"
		if summary.change_pct != null:
			trend = "médiane récente %+.1f %% vs cinq premières" % summary.change_pct
		text += "\n%s · n=%d · médiane récente %.0f · record %.0f · %s\n" % [definition.title, summary.count, summary.latest_median, summary.best, trend]
	home.history_label.text = text


func export_history() -> void:
	var directory := store.export_sessions()
	home.set_status("CSV + JSON exportés : " + directory if not directory.is_empty() else store.last_error)


func update_telemetry() -> void:
	if screen == Screen.TEST:
		hud_title.text = "TEST SOURIS"
		angles_label.text = "Yaw %+.2f° · Pitch %+.2f°\nCounts X %.0f / Y %.0f" % [aim_camera.yaw_deg, aim_camera.pitch_deg, aim_camera.received_x_counts, aim_camera.received_y_counts]
		help_label.text = "Échap : pause/reprise · Repère sans score · %.5f°/count · FOV vertical %.0f°" % [aim_camera.degrees_per_count, aim_camera.fov]
		return
	var prefix := ""
	if is_calibrating:
		var stage := calibration.current_stage()
		prefix = "%d/%d · %s · Réglage %s · " % [calibration.current_index + 1, calibration.plan.size(), "Mesuré" if stage.scored else "Familiarisation", ["A", "B", "C"][int(stage.candidate_index)]]
	hud_title.text = prefix + selected_definition.title
	if screen == Screen.COUNTDOWN:
		angles_label.text = "Départ dans %.0f…" % ceil(maxf(2.0 - clock.elapsed_s(Time.get_ticks_usec()), 0.0))
	else:
		angles_label.text = "Reste %.1f s · %d touches / %d tirs" % [maxf(engine.duration_s - engine.elapsed_s, 0.0), engine.hits, engine.shots]
		if selected_definition.family == "tracking":
			angles_label.text = "Reste %.1f s · temps sur cible %.1f %%" % [maxf(engine.duration_s - engine.elapsed_s, 0.0), 100.0 * engine.on_target_s / maxf(engine.integrated_s, 0.000001)]
	help_label.text = selected_definition.instructions + "\nÉchap : pause et pointeur libre."


func quit_application() -> void:
	if session_active:
		finish_training(false, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit()
