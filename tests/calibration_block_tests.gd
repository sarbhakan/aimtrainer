extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")
const DomainTests := preload("res://tests/domain_tests.gd")

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var calibration := CalibrationService.new()
	calibration.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "block-test")
	expect(CalibrationService.PROTOCOL_VERSION == 3, "Les facteurs configurables doivent versionner le protocole.")
	for block_index in 5:
		var positions: Array[Array] = [[], [], []]
		for passage_index in 12:
			var stage: Dictionary = calibration.plan[block_index * 12 + passage_index]
			expect(stage.scenario_id == CalibrationService.SCENARIOS[block_index] and int(stage.block_index) == block_index, "Un bloc doit rester sur le même exercice pendant douze passages.")
			expect(stage.scored == (passage_index >= 3), "Les trois familiarisations doivent précéder les neuf passages mesurés de chaque bloc.")
			if stage.scored:
				positions[(passage_index - 3) % 3].append(stage.candidate_index)
		for order in positions:
			order.sort()
			expect(order == [0, 1, 2], "Chaque sensibilité doit occuper chacune des trois positions une fois par exercice.")
	var old := calibration.checkpoint().duplicate(true)
	old.protocol_version = 1
	var restored := CalibrationService.new()
	expect(not restored.restore(old), "Un ancien protocole ne doit pas être interprété selon le nouvel ordre.")
	var domain := DomainTests.new()
	domain.verify = verify
	var finished := domain.completed_calibration([30, 60, 40])
	var recommendation := finished.recommendation()
	expect(recommendation.scenario_results.size() == 5, "Le bilan doit expliquer les cinq comparaisons d’exercice.")
	for row in recommendation.scenario_results:
		for candidate in row.candidates:
			expect(candidate.samples == 3 and candidate.median_score != null, "Chaque résultat médian doit venir de trois vrais passages notés, jamais d’un échauffement.")
	var app := MainScene.instantiate()
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	tree.root.add_child(app)
	await tree.process_frame
	app.start_calibration()
	app.begin_training(Time.get_ticks_usec())
	app.clock.accumulated_us = 8000000
	app.finish_training(true)
	expect(app.screen == app.Screen.RESULTS and app.session_panel.retry_button.visible, "Un passage inactif doit proposer explicitement un réessai sans être accepté.")
	app.retry_training()
	app.begin_training(Time.get_ticks_usec())
	for click_index in 3:
		var direction: Vector3 = app.engine.target_direction(0, app.clock.elapsed_s(Time.get_ticks_usec()))
		var motion := InputEventMouseMotion.new()
		motion.screen_relative = Vector2((app.aim_camera.yaw_deg - rad_to_deg(atan2(-direction.x, -direction.z))) / app.aim_camera.degrees_per_count,
			(app.aim_camera.pitch_deg - rad_to_deg(asin(direction.y))) / app.aim_camera.degrees_per_count)
		app._input(motion)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		app._input(click)
	app.engine.record_frame(0.01)
	app.engine.record_frame(0.01)
	app.clock.accumulated_us = 8000000
	app.finish_training(true)
	expect(app.screen == app.Screen.REST and app.session_panel.retry_button.visible, "Un passage valide reste refaisable avant sa validation, sans masquer le réessai.")
	var checkpoint_before: String = FileAccess.get_file_as_string(app.store.root_path.path_join("calibration_checkpoint.json"))
	app.retry_training()
	expect(app.screen == app.Screen.REST, "Refaire un passage doit respecter le repos minimal.")
	app.rest_until_us = 0
	app.retry_training()
	expect(app.screen == app.Screen.COUNTDOWN and app.calibration.current_index == 0 and app.pending_trial.is_empty(), "Refaire doit relancer le même candidat sans valider ni perdre un passage.")
	expect(FileAccess.get_file_as_string(app.store.root_path.path_join("calibration_checkpoint.json")) == checkpoint_before, "Un réessai ne doit pas changer le checkpoint avant un passage accepté.")
	app.return_to_menu()
	app.session_panel.present_recommendation(recommendation, 800.0, "Test isolé")
	expect(app.session_panel.context_root.visible and app.session_panel.context.get_child_count() == 7, "Le bilan doit afficher les cinq lignes d’exercice, pas seulement un nombre final.")
	var displayed_labels := label_texts(app.session_panel.context)
	for candidate in recommendation.scenario_results[0].candidates:
		var caption: String = "%s · %s" % [["A", "B", "C"][int(candidate.candidate_index)], AimUI.number(float(candidate.sensitivity), 4)]
		expect(caption in displayed_labels, "Le bilan doit associer chaque colonne A/B/C à sa vraie sensibilité, indépendamment du classement final.")
	app.queue_free()
	await tree.process_frame
	await tree.create_timer(0.1).timeout
	return true


func label_texts(parent: Node) -> Array[String]:
	var texts: Array[String] = []
	for child in parent.get_children():
		if child is Label:
			texts.append(child.text)
		texts.append_array(label_texts(child))
	return texts
