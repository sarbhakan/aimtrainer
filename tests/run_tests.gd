extends SceneTree

const CameraScript = preload("res://scripts/input/aim_camera.gd")
const AppScript = preload("res://scripts/core/main.gd")
const MainScene = preload("res://scenes/app/Main.tscn")
const DomainTests = preload("res://tests/domain_tests.gd")
const UiTests = preload("res://tests/ui_tests.gd")
const SensitivityImportTests = preload("res://tests/sensitivity_import_tests.gd")
const WeaponAnimationTests = preload("res://tests/weapon_animation_tests.gd")
const CalibrationBlockTests = preload("res://tests/calibration_block_tests.gd")
const BrowserPreviewTests = preload("res://tests/browser_preview_tests.gd")
const CheckpointMigrationTests = preload("res://tests/checkpoint_migration_tests.gd")
const UiPolishTests = preload("res://tests/ui_polish_tests.gd")
const UxFlowTests = preload("res://tests/ux_flow_tests.gd")
const CrosshairFeedbackTests = preload("res://tests/crosshair_feedback_tests.gd")
const GameplayQualityTests = preload("res://tests/gameplay_quality_tests.gd")
const GuidedFlowTests = preload("res://tests/guided_flow_tests.gd")
const RecordFlowTests = preload("res://tests/record_flow_tests.gd")
const RevisionArchiveTests = preload("res://tests/revision_archive_tests.gd")
const TrainingPresentationTests = preload("res://tests/training_presentation_tests.gd")

var assertion_count: int = 0
var failure_count: int = 0
var skipped_count: int = 0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Les tests n'ont pas atteint leur fin en 90 secondes.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_tests() -> void:
	test_mouse_math()
	check(DomainTests.new().run(check), "La suite métier doit se terminer sans erreur de script.")
	await test_application_flow()
	await test_training_flow()
	check(await UiTests.new().run(self, check), "La suite d’interface et d’équipement doit se terminer.")
	check(await SensitivityImportTests.new().run(self, check), "La strate d’import et de conversion doit se terminer.")
	await WeaponAnimationTests.run_suite(self, check)
	check(await CalibrationBlockTests.new().run(self, check), "La strate de calibration par blocs doit se terminer.")
	check(await BrowserPreviewTests.new().run(self, check), "La strate d’aperçus au survol et au clic doit se terminer.")
	check(await CheckpointMigrationTests.new().run(self, check), "Les anciens checkpoints doivent être archivés sans perte ni écrasement incohérent.")
	check(await UiPolishTests.new().run(self, check), "Les interactions UI doivent se terminer sans fuite ni déplacement de layout.")
	check(await UxFlowTests.new().run(self, check), "Les parcours novices doivent rester accessibles et compréhensibles.")
	check(await CrosshairFeedbackTests.new().run(self, check), "Viseur et retour de tir doivent rester cosmétiques et sauvegardables.")
	check(await GameplayQualityTests.new().run(self, check), "Gameplay, aperçus et mesures doivent rester cohérents.")
	check(await GuidedFlowTests.new().run(self, check), "La recherche guidée doit rester transactionnelle et reprenable.")
	check(await RecordFlowTests.new().run(self, check), "Seuls les records réellement sauvegardés et comparables doivent être annoncés.")
	check(RevisionArchiveTests.new().run(self, check), "La révision des exercices doit archiver les comparaisons reconnues sans écraser les fichiers incohérents.")
	check(await TrainingPresentationTests.new().run(self, check), "La préparation et le HUD doivent être lisibles sans altérer les mesures.")
	print("AIM/LOCAL : %d assertions, %d échecs, %d contrôles non exécutés." % [assertion_count, failure_count, skipped_count])
	quit(0 if failure_count == 0 else 1)


func test_mouse_math() -> void:
	var camera := CameraScript.new()
	camera.apply_mouse_counts(Vector2(1000.0, 0.0))
	check(is_equal_approx(camera.yaw_deg, -44.0), "1000 counts doivent produire -44 degrés de yaw.")
	check(camera.pitch_deg == 0.0, "Un déplacement horizontal ne doit pas modifier le pitch.")
	check(is_equal_approx(camera.rotation.y, deg_to_rad(-44.0)), "La pose Godot doit convertir les degrés en radians.")
	var single_yaw_deg: float = camera.yaw_deg
	camera.reset_aim()
	for counts in [200.0, 300.0, 500.0]:
		camera.apply_mouse_counts(Vector2(counts, 0.0))
	check(is_equal_approx(camera.yaw_deg, single_yaw_deg), "Le regroupement des counts ne doit pas changer la rotation finale.")
	check(camera.received_counts == Vector2(1000.0, 0.0), "Les counts doivent être cumulés exactement une fois.")
	camera.reset_aim()
	camera.apply_mouse_counts(Vector2(-100.0, -100.0))
	check(is_equal_approx(camera.yaw_deg, 4.4), "Un mouvement gauche doit tourner la caméra vers la gauche.")
	check(is_equal_approx(camera.pitch_deg, 4.4), "Un mouvement haut doit lever la caméra.")
	camera.apply_mouse_counts(Vector2(0.0, -100000.0))
	check(camera.pitch_deg == 89.0, "Le pitch haut doit être limité à 89 degrés.")
	camera.apply_mouse_counts(Vector2(0.0, 100000.0))
	check(camera.pitch_deg == -89.0, "Le pitch bas doit être limité à -89 degrés.")
	camera.reset_aim()
	check(camera.received_counts == Vector2.ZERO and camera.rotation == Vector3.ZERO, "Reset doit effacer counts et pose.")
	camera.free()


func mouse_motion(screen_counts: Vector2, scaled_relative: Vector2 = Vector2.ZERO) -> void:
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = screen_counts
	motion.relative = scaled_relative
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func escape_pressed() -> void:
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = false
	Input.parse_input_event(escape)
	Input.flush_buffered_events()


func test_application_flow() -> void:
	var app := MainScene.instantiate() as AppScript
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	root.add_child(app)
	await process_frame
	check(app.screen == AppScript.Screen.HOME and app.home.visible, "Le projet doit démarrer sur l'accueil.")
	check(not app.arena.visible and not app.hud.visible, "L'arène et le HUD doivent rester masqués au menu.")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "La souris doit être libre au menu.")
	mouse_motion(Vector2(1000.0, 0.0))
	check(app.aim_camera.yaw_deg == 0.0, "Le mouvement au menu ne doit pas être compté.")
	app.test_button.pressed.emit()
	await process_frame
	var expected_yaw_deg := -1000.0 * app.aim_camera.degrees_per_count
	check(app.screen == AppScript.Screen.TEST and app.arena.visible and app.hud.visible, "Le bouton Test doit ouvrir l'arène.")
	check(not app.home.visible, "Le test doit masquer le menu.")
	if DisplayServer.get_name() == "headless":
		skipped_count += 1
		print("NON EXÉCUTÉ : capture réelle du pointeur ; le serveur headless conserve MOUSE_MODE_VISIBLE.")
	else:
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Le test doit capturer la souris.")
	mouse_motion(Vector2(1000.0, 0.0), Vector2(9000.0, 9000.0))
	check(is_equal_approx(app.aim_camera.yaw_deg, expected_yaw_deg), "Le handler doit utiliser screen_relative et non relative.")
	check(app.aim_camera.pitch_deg == 0.0, "Le scaling simulé de relative ne doit pas altérer le pitch.")
	app.start_test()
	check(is_equal_approx(app.aim_camera.yaw_deg, expected_yaw_deg), "Un double lancement ne doit pas réinitialiser le test actif.")
	escape_pressed()
	check(app.screen == AppScript.Screen.PAUSED and app.pause_panel.visible, "Échap doit mettre le test en pause.")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "La pause doit libérer la souris.")
	mouse_motion(Vector2(1000.0, 0.0))
	check(is_equal_approx(app.aim_camera.yaw_deg, expected_yaw_deg), "La pause doit ignorer les mouvements.")
	app.resume_button.pressed.emit()
	check(app.screen == AppScript.Screen.TEST and not app.pause_panel.visible, "Le bouton Reprendre doit réactiver le test.")
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.screen == AppScript.Screen.PAUSED and not app.window_has_focus, "La perte de focus doit mettre le test en pause.")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "La perte de focus doit libérer le pointeur.")
	mouse_motion(Vector2(1000.0, 0.0))
	app.resume_button.pressed.emit()
	check(app.screen == AppScript.Screen.PAUSED, "Une reprise sans focus doit être refusée.")
	check(is_equal_approx(app.aim_camera.yaw_deg, expected_yaw_deg), "Les mouvements hors focus doivent être ignorés.")
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(app.screen == AppScript.Screen.PAUSED, "Le retour de focus ne doit pas reprendre automatiquement.")
	escape_pressed()
	check(app.screen == AppScript.Screen.TEST, "Une reprise explicite avec focus doit fonctionner.")
	mouse_motion(Vector2.ZERO)
	check(is_equal_approx(app.aim_camera.yaw_deg, expected_yaw_deg), "Un événement nul de recentrage ne doit pas changer la pose.")
	app.pause_test()
	app.menu_button.pressed.emit()
	check(app.screen == AppScript.Screen.HOME and not app.pause_panel.visible, "Le bouton Menu doit revenir à l'accueil.")
	for frame_rate in [60, 144, 240]:
		app.test_button.pressed.emit()
		for counts in [200.0, 300.0, 500.0]:
			app._process(1.0 / float(frame_rate))
			mouse_motion(Vector2(counts, 0.0))
		check(is_equal_approx(app.aim_camera.yaw_deg, expected_yaw_deg), "Les durées de frame simulées à %d FPS ne doivent pas changer l'angle." % frame_rate)
		app.return_to_menu()
	app.test_button.pressed.emit()
	check(app.aim_camera.yaw_deg == 0.0 and app.aim_camera.received_counts == Vector2.ZERO, "Une nouvelle entrée doit repartir avec une pose vierge.")
	app.return_to_menu()
	app.queue_free()
	await process_frame


func aim_at_target(app: Node) -> void:
	var direction: Vector3 = app.engine.target_direction(0, app.clock.elapsed_s(Time.get_ticks_usec()))
	var yaw_deg := rad_to_deg(atan2(-direction.x, -direction.z))
	var pitch_deg := rad_to_deg(asin(direction.y))
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2((app.aim_camera.yaw_deg - yaw_deg) / app.aim_camera.degrees_per_count,
		(app.aim_camera.pitch_deg - pitch_deg) / app.aim_camera.degrees_per_count)
	app._input(motion)


func click_event(app: Node, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	app._input(event)


func test_training_flow() -> void:
	var app := MainScene.instantiate() as AppScript
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	root.add_child(app)
	await process_frame
	app.start_practice("C01", 1.0)
	check(app.screen == AppScript.Screen.COUNTDOWN and not app.session_active, "L'exercice doit démarrer par un compte à rebours non noté.")
	app.pause_test()
	check(app.paused_from == AppScript.Screen.COUNTDOWN, "Le compte à rebours doit pouvoir être suspendu.")
	app.resume_test()
	app.begin_training(Time.get_ticks_usec())
	check(app.screen == AppScript.Screen.TRAINING and app.session_active, "La fin du compte à rebours doit activer le moteur de mesure.")
	check(app.target_pool.get_child_count() == 6, "Le pool doit créer seulement six instances réutilisables.")
	for click_index in 3:
		aim_at_target(app)
		click_event(app, true)
		click_event(app, false)
	check(app.engine.shots == 3 and app.engine.hits == 3, "Les trois pressions doivent toucher ; les relâchements ne doivent pas ajouter de tirs.")
	app.pause_test()
	var paused_shots: int = app.engine.shots
	click_event(app, true)
	app._process(10.0)
	check(app.engine.shots == paused_shots and not app.clock.running, "La pause UI ne doit pas compter de tirs ni faire avancer l'horloge.")
	app.resume_test()
	app.clock.accumulated_us = 1000000
	app._process(0.01)
	await process_frame
	check(app.screen == AppScript.Screen.RESULTS and app.session_panel.visible, "La fin doit montrer les métriques et libérer la souris.")
	check(app.store.sessions().size() == 1 and app.last_report.completed, "La fin doit enregistrer une seule séance complète.")
	check(app.target_pool.get_child_count() == 6, "Les respawns ne doivent pas accumuler des nœuds.")
	app.retry_training()
	app.begin_training(Time.get_ticks_usec())
	check(app.engine.shots == 0, "Le bouton Rejouer doit repartir avec des compteurs vierges.")
	app.return_to_menu()
	check(app.store.sessions().size() == 2 and not app.last_report.completed, "Le retour au menu doit conserver l'abandon, sans en faire un record.")
	app.start_calibration()
	check(app.is_calibrating and app.calibration.current_index == 0 and app.screen == AppScript.Screen.COUNTDOWN, "Le bouton calibration doit appliquer le premier candidat.")
	app.begin_training(Time.get_ticks_usec())
	for click_index in 3:
		aim_at_target(app)
		click_event(app, true)
		click_event(app, false)
	app.engine.record_frame(0.01)
	app.engine.record_frame(0.01)
	app.clock.accumulated_us = 8000000
	app.finish_training(true)
	check(app.screen == AppScript.Screen.REST and app.last_report.warmup, "Une familiarisation complète doit demander repos et confort, sans entrer dans le classement.")
	app.next_calibration_stage()
	check(app.calibration.current_index == 0, "Le repos minimal ne doit pas pouvoir être contourné par le bouton.")
	var checkpoint_path: String = app.store.root_path + "/calibration_checkpoint.json"
	var original := FileAccess.get_file_as_string(checkpoint_path)
	var corrupt_file := FileAccess.open(checkpoint_path, FileAccess.WRITE)
	corrupt_file.store_string("{corrompu")
	corrupt_file.close()
	app.rest_until_us = 0
	app.next_calibration_stage()
	check(app.calibration.current_index == 0 and not app.pending_trial.is_empty(), "Un échec de sauvegarde doit conserver le passage et annuler uniquement sa validation.")
	corrupt_file = FileAccess.open(checkpoint_path, FileAccess.WRITE)
	corrupt_file.store_string(original)
	corrupt_file.close()
	app.next_calibration_stage()
	check(app.calibration.current_index == 1 and app.screen == AppScript.Screen.COUNTDOWN, "Réessayer après une panne disque doit sauvegarder et avancer exactement une fois.")
	app.return_to_menu()
	check(app.home.resume_calibration_button.visible, "Une calibration interrompue doit rester reprenable depuis l'accueil.")
	app.resume_calibration()
	check(app.calibration.current_index == 1 and app.is_calibrating, "La reprise UI doit restaurer les réglages et le bon passage.")
	app.return_to_menu()
	var domain := DomainTests.new()
	domain.verify = check
	var finished := domain.completed_calibration([30, 40, 70])
	finished.calibration_id = app.store.identifier()
	check(app.store.save_checkpoint(finished.checkpoint()), "Le dernier passage doit rendre le bilan disponible après redémarrage.")
	app.resume_calibration()
	check(app.screen == AppScript.Screen.RESULTS and not app.home.visible and app.session_panel.apply_button.visible, "Un checkpoint complet doit afficher le bilan et l'action d'application, pas recommencer un exercice.")
	app.apply_recommendation()
	var applied_cm := snappedf(35.0 / 1.1, 0.001)
	check(app.screen == AppScript.Screen.HOME and app.home.read_profile().cm_per_360 == applied_cm, "Appliquer doit réellement changer la sensibilité dans l'interface.")
	check(app.store.load_profile().cm_per_360 == applied_cm, "La sensibilité conseillée appliquée doit persister sur disque.")
	check(is_equal_approx(app.home.conversion_value, SensitivityService.game_sensitivity(800, applied_cm, 0.022)), "Le convertisseur doit immédiatement utiliser la nouvelle sensibilité.")
	app.resume_calibration()
	check(app.screen == AppScript.Screen.RESULTS and not app.store.last_error.contains("refus"), "Revoir le bilan doit rester idempotent après l'application.")
	app.return_to_menu()
	app.queue_free()
	await process_frame
