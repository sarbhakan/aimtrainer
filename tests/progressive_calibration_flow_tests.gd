extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")
const UiTests := preload("res://tests/progressive_ui_tests.gd")
const PresentationTests := preload("res://tests/presentation_070_tests.gd")

class FailureStore extends LocalStore:
	var reject_checkpoint: bool = false
	var reject_session: bool = false
	var reject_summary: bool = false
	var reject_profile: bool = false

	func save_progressive_checkpoint(data: Dictionary) -> bool:
		if reject_checkpoint:
			last_error = "Checkpoint refusé pour le test."
			return false
		return super.save_progressive_checkpoint(data)

	func save_session(report: Dictionary) -> bool:
		if reject_session:
			last_error = "Séance refusée pour le test."
			return false
		return super.save_session(report)

	func save_progressive_recommendation(data: Dictionary) -> bool:
		if reject_summary:
			last_error = "Bilan refusé pour le test."
			return false
		return super.save_progressive_recommendation(data)

	func save_profile(profile: Dictionary) -> bool:
		if reject_profile:
			last_error = "Profil refusé pour le test."
			return false
		return super.save_profile(profile)

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func complete_trial(app: Node, expected_saved: bool = true) -> void:
	app.begin_training(Time.get_ticks_usec())
	expect(app.session_active and app.screen == app.Screen.TRAINING, "Le décompte active la vraie mesure de l’exercice.")
	app.engine.record_aim(0.02, 1.0, 0.0)
	app.engine.record_aim(0.04, 2.0, 1.0)
	if app.selected_definition.family != "tracking":
		for shot_index in 3:
			var time_s := 0.1 + shot_index * 0.1
			app.engine.shoot(time_s, app.engine.target_direction(0, time_s))
	app.engine.record_frame(0.008)
	app.engine.record_frame(0.009)
	app.clock.accumulated_us = int(app.selected_duration_s * 1000000.0)
	app.clock.resumed_us = Time.get_ticks_usec()
	expect(app.finish_training(true) == expected_saved, "Le rapport issu du moteur indique honnêtement sa sauvegarde ou son refus.")


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	await UiTests.new().run(tree, check)
	await PresentationTests.new().run(tree, check)
	var app: Node = MainScene.instantiate()
	var store := FailureStore.new("user://tests/progressive-flow-" + LocalStore.new().identifier())
	app.store = store
	tree.root.add_child(app)
	await tree.process_frame
	app.set_process(false)
	var profile: Dictionary = app.home.read_profile()
	profile.sound_enabled = false
	profile.reduced_motion = true
	profile.cm_per_360 = 34.123456789
	app.home.bind_profile(profile)
	store.reject_checkpoint = true
	app.home.progressive_button.pressed.emit()
	expect(app.screen == app.Screen.HOME and not app.is_progressive and not app.is_calibrating, "Un départ non sauvegardé ne capture pas la souris.")
	store.reject_checkpoint = false
	app.home.progressive_button.pressed.emit()
	expect(app.screen == app.Screen.COUNTDOWN and app.is_progressive and app.selected_duration_s == 60.0 and app.training_profile.cm_per_360 == profile.cm_per_360, "L’interface publique démarre un vrai essai de 60 s à la sensibilité exacte.")
	expect(app.progressive.protocol_version == 6 and app.selected_definition == app.progressive.definition_for("C02") and app.selected_definition == ScenarioCatalog.find_practice("C02"), "Le parcours public associe le protocole 6 à sa définition actuelle.")
	var first_seed: int = app.selected_seed
	complete_trial(app)
	expect(app.screen == app.Screen.REST and not app.session_panel.comfort_row.visible and not app.last_report.warmup, "Le résultat présente les mesures, sans questionnaire de confort ni échauffement de 8 s.")
	app.next_calibration_stage()
	expect(app.progressive.trials.is_empty(), "La pause minimale n’est pas contournable.")
	app.rest_until_us = 0
	store.reject_checkpoint = true
	app.next_calibration_stage()
	expect(app.progressive.trials.is_empty() and not app.pending_trial.is_empty() and app.screen == app.Screen.REST, "Une panne checkpoint restaure la recherche et conserve l’essai à valider.")
	store.reject_checkpoint = false
	app.next_calibration_stage()
	expect(app.progressive.trials.size() == 1 and app.screen == app.Screen.COUNTDOWN and app.selected_seed == first_seed and app.training_profile.cm_per_360 < profile.cm_per_360, "Après reprise de sauvegarde, un seul essai est validé et le prochain est plus rapide.")
	var second_profile: Dictionary = app.training_profile.duplicate(true)
	app.pause_test()
	expect(app.pause_panel.locked and not app.pause_panel.editor.visible, "Une sensibilité imposée par calibration n’est pas modifiable en pause.")
	app.resume_test()
	app.begin_training(Time.get_ticks_usec())
	app.finish_training(false)
	app.retry_training()
	expect(app.selected_seed == first_seed and app.training_profile == second_profile and app.progressive.trials.size() == 1, "Rejouer l’essai interrompu conserve réglage, graine et position du parcours.")
	app.return_to_menu()
	expect(app.home.progressive_resume_button.visible, "La calibration interrompue se reprend depuis son bouton public.")
	app.home.progressive_resume_button.pressed.emit()
	expect(app.progressive.trials.size() == 1 and app.progressive.same_value(app.training_profile, second_profile) and app.screen == app.Screen.COUNTDOWN, "La reprise recharge la recherche et non un nouveau plan identique pour tous.")
	for trial_index in range(1, 25):
		if trial_index == 1:
			store.reject_session = true
		complete_trial(app, trial_index != 1)
		if trial_index == 1:
			var retained_identifier: String = app.pending_trial.session_id
			app.rest_until_us = 0
			app.next_calibration_stage()
			expect(app.progressive.trials.size() == 1 and app.pending_trial.session_id == retained_identifier and not app.pending_trial_saved, "Un rapport refusé ne valide rien et garde son identifiant lors du réessai.")
			store.reject_session = false
		expect(app.last_report.active_duration_s == 60.0 and (app.pending_trial_saved or trial_index == 1) and not app.pending_trial.is_empty(), "Chaque mesure couvre toute la minute et conserve son rapport fiable, même pendant une panne.")
		app.rest_until_us = 0
		if trial_index == 24:
			store.reject_summary = true
		app.next_calibration_stage()
		if trial_index == 1:
			expect(FileAccess.file_exists(store.root_path + "/sessions/" + app.last_report.session_id + ".json"), "Continuer enregistre effectivement le même rapport une fois la panne résolue.")
		if trial_index < 24:
			expect(app.screen == app.Screen.COUNTDOWN and app.progressive.trials.size() == trial_index + 1, "Continuer démarre l’essai adaptatif suivant exactement une fois.")
	expect(app.screen == app.Screen.RESULTS and app.progressive.completed() and not app.session_panel.apply_button.visible, "Un bilan non sauvegardé n’est pas appliqué en silence.")
	store.reject_summary = false
	app.next_calibration_stage()
	expect(app.session_panel.apply_button.visible and app.final_recommendation.tested_trials == 25, "Le bilan final fournit une sensibilité unique après cinq essais dans chacun des cinq exercices.")
	var retained_cm: float = app.final_recommendation.recommended_cm_per_360
	store.reject_profile = true
	app.session_panel.apply_button.pressed.emit()
	expect(app.screen == app.Screen.RESULTS, "Appliquer attend une sauvegarde du profil réussie.")
	store.reject_profile = false
	app.session_panel.apply_button.pressed.emit()
	expect(app.screen == app.Screen.HOME and app.home.read_profile().cm_per_360 == retained_cm and store.load_profile().cm_per_360 == retained_cm, "Appliquer conserve la valeur testée, sans arrondir le réglage canonique.")
	app.home.progressive_resume_button.pressed.emit()
	expect(app.screen == app.Screen.RESULTS and app.session_panel.apply_button.visible, "Le dernier bilan est consultable après application.")
	app.return_to_menu()
	app.start_practice("C02", 30.0)
	app.begin_training(Time.get_ticks_usec())
	store.reject_session = true
	app.return_to_menu()
	expect(not app.pending_abandon_report.is_empty() and app.screen == app.Screen.HOME, "Un abandon refusé depuis le menu est conservé, pas perdu silencieusement.")
	app.start_progressive_calibration()
	expect(app.screen == app.Screen.HOME and not app.is_progressive, "Le nouveau parcours bloque sur un abandon non sauvegardé.")
	app.start_routine()
	expect(app.screen == app.Screen.HOME and not app.is_routine, "La routine protège aussi le rapport en attente.")
	store.reject_session = false
	expect(app.save_pending_abandon(), "Le rapport conserve sa possibilité de sauvegarde avant le prochain départ.")
	app.start_routine(45.0)
	expect(app.is_routine and app.selected_definition.scenario_id == "M01" and app.selected_duration_s == 45.0, "La séance commence par les grands et petits mouvements mélangés.")
	var routine_profile: Dictionary = app.training_profile.duplicate(true)
	for stage_index in 3:
		expect(app.selected_definition == ScenarioCatalog.find_practice(TrainingRoutineService.SCENARIO_IDS[stage_index]) and app.training_profile == routine_profile, "Chaque phase suit sa variante temporelle avec le même réglage.")
		complete_trial(app)
		app.rest_until_us = 0
		if stage_index == 0:
			app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			app._process(0.01)
			expect(app.screen == app.Screen.REST and app.routine_index == 0, "Le retour du focus ne lance pas implicitement l’étape suivante.")
		app.next_calibration_stage()
	expect(app.screen == app.Screen.RESULTS and app.routine_reports.size() == 3 and not app.session_panel.retry_button.visible, "Le bilan montre trois performances séparées, sans faux score total.")
	app.return_to_menu()
	app.queue_free()
	await tree.process_frame
	await tree.process_frame
	return true
