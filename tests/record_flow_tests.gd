extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")
const DomainTests := preload("res://tests/domain_tests.gd")

var verify: Callable

class FailingSessionStore extends LocalStore:
	var reject_sessions: bool = false

	func save_session(report: Dictionary) -> bool:
		if reject_sessions:
			last_error = "Écriture de séance refusée pour le test."
			return false
		return super.save_session(report)


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func shoot_targets(app: Node, count: int) -> void:
	for shot_index in count:
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


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var app := MainScene.instantiate()
	var store := FailingSessionStore.new()
	store.root_path = "user://tests/" + LocalStore.new().identifier()
	app.store = store
	tree.root.add_child(app)
	await tree.process_frame
	app.home.sound_input.button_pressed = false
	app.start_practice("C07", 8.0)
	var pose_motion := InputEventMouseMotion.new()
	pose_motion.screen_relative = Vector2(0.0, -30.0 / app.aim_camera.degrees_per_count)
	app._input(pose_motion)
	var counts_before: float = app.aim_camera.received_y_counts
	app.begin_training(Time.get_ticks_usec())
	expect(app.screen == app.Screen.COUNTDOWN and not app.session_active and not app.start_pose_ready, "Un départ dont la zone est hors champ doit attendre un réalignement, sans chronomètre actif.")
	expect(app.aim_camera.received_y_counts == counts_before and is_equal_approx(app.aim_camera.pitch_deg, 30.0), "L’aide de cadrage ne doit pas supprimer les counts ni réinitialiser la caméra.")
	pose_motion.screen_relative = Vector2(0.0, 30.0 / app.aim_camera.degrees_per_count)
	app._input(pose_motion)
	app.begin_training(Time.get_ticks_usec())
	expect(app.screen == app.Screen.TRAINING and app.start_pose_ready, "Le départ doit être possible après un réalignement effectué avec les vrais counts.")
	app.return_to_menu()
	var profile: Dictionary = app.home.read_profile()
	profile.cm_per_360 *= 0.9
	var calibration := CalibrationService.new()
	calibration.begin(profile, app.current_aspect(), 42, "record-reference")
	var domain := DomainTests.new()
	domain.verify = verify
	var prior: Dictionary = domain.trial_report(calibration, [3, 3, 3])
	prior.warmup = false
	expect(store.save_session(prior), "La référence historique V1 reste enregistrable sans modifier sa difficulté.")
	var legacy_key: String = prior.comparison_key
	var reference_engine := ScenarioEngine.new()
	expect(reference_engine.start(ScenarioCatalog.find_practice("C02"), 42, 8.0), "La référence publique utilise la difficulté temporelle actuelle.")
	for shot_index in 3:
		var shot_s: float = 0.1 * float(shot_index + 1)
		var direction: Vector3 = reference_engine.target_direction(0, shot_s)
		reference_engine.record_aim(shot_s, rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(direction.y)))
		reference_engine.shoot(shot_s, direction)
	reference_engine.record_frame(0.01)
	reference_engine.record_frame(0.01)
	reference_engine.advance_to(8.0)
	prior = reference_engine.result(app.home.read_profile(), app.current_aspect(), true)
	prior.warmup = false
	expect(ScoringService.comparison_error(prior).is_empty(), "La référence publique comporte un mouvement réel et trois impacts, donc reste admissible aux records.")
	expect(prior.score_version == ScoringService.EXPIRY_VERSION and prior.comparison_key != legacy_key and store.save_session(prior), "La référence de record publique V2 est sauvegardée dans un contexte distinct de la référence V1.")
	for changes in [{"engine_version": "4.6.3"}, {"renderer": "forward_plus"}, {"scenario_revision": 99}, {"scenario_fingerprint": "f".repeat(64)}, {"score": 999999.0}]:
		var altered: Dictionary = prior.duplicate(true)
		altered.merge(changes, true)
		altered.session_id = store.identifier()
		expect(not ScoringService.comparison_error(altered, prior.comparison_key).is_empty(), "Un contexte ou score altéré avec une ancienne clé ne doit pas devenir comparable.")
		expect(not store.save_session(altered), "Un rapport intrinsèquement incohérent doit être refusé avant écriture.")
		expect(ProgressService.summarize([prior, altered], prior.comparison_key).count == 1, "Un rapport altéré ne doit pas gonfler l’historique comparable.")
	var tracking := ScenarioEngine.new()
	tracking.start(ScenarioCatalog.find("T01"), 42, 8.0)
	tracking.advance_to(8.0)
	var legacy: Dictionary = tracking.result(app.home.read_profile(), app.current_aspect(), true)
	legacy.app_version = "0.3.0"
	legacy.metrics.erase("target_exposed_time_s")
	expect(ScoringService.validate_result(legacy).is_empty(), "Les suivis historiques à exposition continue doivent rester lisibles sans réécrire leur rapport.")
	legacy.app_version = "0.4.0"
	expect(not ScoringService.validate_result(legacy).is_empty(), "Un nouveau suivi doit fournir sa durée d’exposition explicite.")
	app.start_practice("C02", 8.0)
	app.begin_training(Time.get_ticks_usec())
	shoot_targets(app, 10)
	app.clock.accumulated_us = 8000000
	app.finish_training(true)
	expect(app.last_report.metrics.hits == 10 and app.last_report.score > prior.score, "Le record de test doit venir de dix impacts réels du moteur, pas d’un score injecté dans l’UI.")
	expect(app.session_panel.hero_caption.text == "NOUVEAU RECORD PERSONNEL", "Un record sauvegardé comparable doit être annoncé explicitement.")
	expect(app.session_panel.record_celebration.remaining_s > 0.0, "Un record doit déclencher un retour visuel discret.")
	app.return_to_menu()
	expect(app.session_panel.record_celebration.remaining_s == 0.0, "La célébration doit s’arrêter lorsque le bilan est masqué.")
	app.start_practice("C02", 8.0)
	app.begin_training(Time.get_ticks_usec())
	shoot_targets(app, 12)
	store.reject_sessions = true
	app.clock.accumulated_us = 8000000
	app.finish_training(true)
	expect(app.session_panel.hero_caption.text != "NOUVEAU RECORD PERSONNEL" and app.session_panel.notice_label.visible, "Un meilleur score non sauvegardé ne doit pas être célébré comme un record enregistré.")
	store.reject_sessions = false
	app.return_to_menu()
	app.start_practice("C02", 8.0)
	app.begin_training(Time.get_ticks_usec())
	shoot_targets(app, 15)
	app.clock.accumulated_us = 1000000
	app.finish_training(false)
	expect(app.session_panel.hero_caption.text != "NOUVEAU RECORD PERSONNEL", "Une séance interrompue, même très rapide, ne doit pas devenir un record.")
	app.return_to_menu()
	app.home.motion_input.button_pressed = true
	app.start_practice("C02", 8.0)
	app.begin_training(Time.get_ticks_usec())
	shoot_targets(app, 15)
	app.clock.accumulated_us = 8000000
	app.finish_training(true)
	expect(app.session_panel.hero_caption.text == "NOUVEAU RECORD PERSONNEL" and app.session_panel.record_celebration.remaining_s == 0.0, "Animations réduites doit garder l’information de record sans particules.")
	app.queue_free()
	await tree.process_frame
	await tree.create_timer(0.1).timeout
	return true
