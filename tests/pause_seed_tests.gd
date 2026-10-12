extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")

class ProfileFailureStore extends LocalStore:
	var reject_profile: bool = false
	var reject_sessions: bool = false

	func save_profile(profile: Dictionary) -> bool:
		if reject_profile:
			last_error = "Sauvegarde du profil refusée pour le test."
			return false
		return super.save_profile(profile)

	func save_session(report: Dictionary) -> bool:
		if reject_sessions:
			last_error = "Sauvegarde de l’essai refusée pour le test."
			return false
		return super.save_session(report)

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var app: Node = MainScene.instantiate()
	var store := ProfileFailureStore.new()
	store.root_path = "user://tests/pause-" + LocalStore.new().identifier()
	app.store = store
	tree.root.add_child(app)
	await tree.process_frame
	app.set_process(false)
	var profile: Dictionary = app.home.read_profile()
	profile.sound_enabled = false
	profile.cm_per_360 = 34.123456789
	app.home.bind_profile(profile)
	var seeds: Array[int] = []
	var positions: Array[Vector3] = []
	for attempt_index in 16:
		app.start_practice("C02", 30.0)
		seeds.append(app.selected_seed)
		positions.append(app.preparation_engine.target_direction(0, 0.0))
		expect(not app.hud.help_label.visible and app.hud.help_label.text.is_empty(), "La consigne n’est pas répétée pendant le décompte.")
		app.begin_training(Time.get_ticks_usec())
		var replay := ScenarioEngine.new()
		replay.start(app.selected_definition, app.selected_seed, 30.0)
		expect(app.engine.targets == replay.targets and app.engine.scenario_seed == app.selected_seed, "Une graine de pratique enregistrée reproduit exactement le départ.")
		app.return_to_menu()
	expect(seeds.size() == 16 and seeds[0] != seeds[1] and positions[0] != positions[1], "Les lancements de pratique n’utilisent plus une graine fixe ni une disposition apprise par cœur.")
	app.start_practice("C02", 30.0)
	app.begin_training(Time.get_ticks_usec())
	var original_key: String = ScoringService.comparison_key(app.selected_definition, 30.0, app.training_profile, app.training_aspect)
	var original_seed: int = app.selected_seed
	app.engine.record_aim(0.1, 1.0, 0.0)
	app.engine.record_frame(0.01)
	app.clock.accumulated_us = 100000
	app.pause_test()
	var pause: TrainingPause = app.pause_panel
	var original_degrees_per_count: float = app.aim_camera.degrees_per_count
	var exact_sensitivity: float = pause.sensitivity_input.value
	pause.sensitivity_input.begin_edit()
	pause.sensitivity_input.finish_edit()
	await tree.process_frame
	expect(pause.sensitivity_input.value == exact_sensitivity and pause.draft_profile().cm_per_360 == profile.cm_per_360 and pause.apply_button.disabled, "Focus/blur d’un affichage arrondi ne change pas la sensibilité canonique en pause.")
	pause.unit_input.select(1)
	pause.select_unit(1)
	expect(is_equal_approx(pause.sensitivity_input.value, SensitivityService.game_sensitivity(profile.dpi, profile.cm_per_360, 0.07)), "La pause peut afficher le réglage équivalent de Valorant.")
	pause.sensitivity_input.value = 0.4
	expect(app.aim_camera.degrees_per_count == original_degrees_per_count and not app.clock.running and app.screen == app.Screen.PAUSED, "Éditer la valeur ne change ni la caméra ni l’essai avant application explicite.")
	var next_profile: Dictionary = pause.draft_profile()
	store.reject_profile = true
	pause.apply_button.pressed.emit()
	expect(app.screen == app.Screen.PAUSED and app.session_active and app.training_profile.cm_per_360 == profile.cm_per_360 and pause.notice_label.text.contains("refusée"), "Un refus de sauvegarde conserve l’essai et le réglage précédents.")
	store.reject_profile = false
	pause.apply_button.pressed.emit()
	expect(app.screen == app.Screen.COUNTDOWN and not app.session_active and app.selected_seed != original_seed, "Appliquer en pause redémarre un vrai décompte avec une nouvelle graine de pratique.")
	expect(app.training_profile == next_profile and is_equal_approx(app.aim_camera.degrees_per_count, 0.4 * 0.07) and is_equal_approx(float(store.load_profile().cm_per_360), float(next_profile.cm_per_360)), "Le réglage appliqué est exact, actif et sauvegardé, pas l’affichage à deux décimales.")
	var new_key: String = ScoringService.comparison_key(app.selected_definition, 30.0, app.training_profile, app.training_aspect)
	expect(new_key != original_key and not app.last_report.completed and app.last_report.comparison_key == original_key and app.last_report.profile.cm_per_360 == profile.cm_per_360, "L’essai quitté conserve son ancienne sensibilité et reste exclu des records.")
	expect(ProgressService.summarize(store.sessions(), original_key).count == 0, "Une modification en pause ne crée pas un record artificiel.")
	app.begin_training(Time.get_ticks_usec())
	app.clock.accumulated_us = 30000000
	app.finish_training(true)
	var completed_seed: int = app.selected_seed
	app.retry_training()
	expect(app.selected_seed != completed_seed and app.training_profile == next_profile, "Rejouer un entraînement renouvelle la disposition sans changer la difficulté ni le profil.")
	app.return_to_menu()
	app.start_calibration()
	var stage_seed: int = app.selected_seed
	var stage_profile: Dictionary = app.training_profile.duplicate(true)
	app.pause_test()
	expect(pause.locked and not pause.editor.visible and pause.apply_button.disabled, "La calibration ne propose pas un changement qui fausserait la comparaison.")
	var forbidden: Dictionary = stage_profile.duplicate(true)
	forbidden.cm_per_360 *= 1.05
	app.apply_paused_sensitivity(forbidden)
	expect(app.training_profile == stage_profile and app.screen == app.Screen.PAUSED and app.selected_seed == stage_seed, "Un appel direct ne peut pas contourner le verrouillage de calibration.")
	app.resume_test()
	app.begin_training(Time.get_ticks_usec())
	app.finish_training(false)
	app.retry_training()
	expect(app.selected_seed == stage_seed and app.training_profile == stage_profile, "Rejouer un passage de calibration conserve sa graine et son réglage prescrits.")
	app.return_to_menu()
	app.start_practice("C02", 30.0)
	app.begin_training(Time.get_ticks_usec())
	app.engine.record_aim(0.1, 1.0, 0.0)
	app.clock.accumulated_us = 100000
	app.pause_test()
	pause.sensitivity_input.value *= 1.05
	var retry_profile: Dictionary = pause.draft_profile()
	store.reject_sessions = true
	pause.apply_button.pressed.emit()
	expect(app.screen == app.Screen.RESULTS and not app.pending_abandon_report.is_empty() and app.session_panel.notice_label.text.contains("non sauvegardé"), "Un abandon non enregistré est retenu et signalé, sans redémarrage silencieux.")
	var pending_identifier: String = app.pending_abandon_report.session_id
	app.retry_training()
	expect(app.screen == app.Screen.RESULTS and app.pending_abandon_report.session_id == pending_identifier and app.pending_restart_profile == retry_profile, "Une panne persistante ne perd ni le rapport d’abandon ni le réglage demandé.")
	app.quit_application()
	expect(app.unsaved_exit_dialog != null and app.unsaved_exit_dialog.visible and app.unsaved_exit_dialog.dialog_text.contains("Quitter le perdra"), "Une fermeture pendant cette panne demande de confirmer la perte, plutôt que de supprimer silencieusement l’abandon en mémoire.")
	app.unsaved_exit_dialog.hide()
	store.reject_sessions = false
	app.retry_training()
	expect(app.screen == app.Screen.COUNTDOWN and app.pending_abandon_report.is_empty() and app.training_profile == retry_profile, "Après résolution de l’erreur, le rapport est enregistré avant le nouveau décompte.")
	expect(FileAccess.file_exists(store.root_path + "/sessions/" + pending_identifier + ".json"), "La relance n’escamote pas l’enregistrement de l’ancien essai interrompu.")
	app.return_to_menu()
	app.start_practice("C02", 30.0)
	app.begin_training(Time.get_ticks_usec())
	app.pause_test()
	pause.sensitivity_input.value *= 1.05
	store.reject_sessions = true
	pause.apply_button.pressed.emit()
	app.return_to_menu()
	for entry in [app.start_calibration, app.start_guided_calibration, app.resume_calibration, app.resume_guided_calibration]:
		entry.call()
		expect(app.screen == app.Screen.HOME and not app.is_calibrating and not app.is_guided and not app.pending_abandon_report.is_empty(), "Un abandon non sauvegardé bloque l’entrée en calibration sans laisser ses flags actifs au menu.")
	app.start_test()
	app.pause_test()
	expect(not pause.locked and pause.editor.visible, "Le test souris ne reste pas verrouillé après un départ de calibration refusé.")
	app.return_to_menu()
	store.reject_sessions = false
	expect(app.save_pending_abandon(), "Le rapport reste retentable même après un retour au menu et un test souris indépendant.")
	app.start_test()
	app.pause_test()
	pause.sensitivity_input.value *= 1.1
	pause.apply_button.pressed.emit()
	expect(app.screen == app.Screen.TEST and not pause.visible and is_equal_approx(float(app.training_profile.cm_per_360), float(store.load_profile().cm_per_360)), "Le test souris accepte aussi un nouveau réglage en pause sans créer une séance scorée.")
	app.pause_test()
	var original_size: Vector2i = tree.root.size
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		await tree.process_frame
		await tree.process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		expect(bounds.encloses(pause.apply_button.get_global_rect()) and bounds.encloses(pause.resume_button.get_global_rect()), "Le réglage et la reprise tiennent entièrement dans la fenêtre %s." % dimensions)
		expect(pause.resume_button.size.x < 180.0 and pause.resume_button.size.y < 60.0, "Reprendre garde la taille d’un bouton, pas celle d’une bannière.")
	tree.root.size = original_size
	app.queue_free()
	await tree.process_frame
	return true
