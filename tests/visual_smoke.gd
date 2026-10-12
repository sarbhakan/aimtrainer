extends SceneTree

const MainScene := preload("res://scenes/app/Main.tscn")
const DomainTests := preload("res://tests/domain_tests.gd")

var app: Node
var failed: bool = false
var screenshot_dir: String = "res://dist/preview"
var capture_count: int = 0


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("Validation visuelle interrompue après 180 secondes.")
		quit(1))
	run.call_deferred()


func expect(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error(description)


func settle() -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw


func capture(caption: String) -> void:
	await settle()
	write_capture(caption)


func write_capture(caption: String) -> void:
	var path := screenshot_dir.path_join(caption + ".png")
	expect(root.get_texture().get_image().save_png(path) == OK, "Capture inaccessible : " + path)
	capture_count += 1


func validate_scrolls(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control and not child.is_visible_in_tree():
			continue
		if child is ScrollContainer and child.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			for content in child.get_children():
				if content is Container:
					expect(content.get_combined_minimum_size().x <= child.size.x + 1.0, "Débordement horizontal : " + str(child.get_path()) + " (" + str(content.get_combined_minimum_size().x) + " > " + str(child.size.x) + ")")
		validate_scrolls(child)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Un affichage graphique est nécessaire pour valider les captures.")
		quit(1)
		return
	if not OS.get_environment("AIM_LOCAL_SCREENSHOT_DIR").is_empty():
		screenshot_dir = OS.get_environment("AIM_LOCAL_SCREENSHOT_DIR")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshot_dir))
	app = MainScene.instantiate()
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	root.add_child(app)
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450), Vector2i(1920, 1080)]:
		root.size = dimensions
		await settle()
		for page_index in 6:
			app.home.show_page(page_index)
			await capture("%d-%02d-%s" % [dimensions.x, page_index, ["accueil", "exercices", "sensibilite", "conversion", "progression", "reglages"][page_index]])
			validate_scrolls(app.home)
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = dimensions
		app.home.show_page(0)
		await settle()
		var starter: Control = app.home.home_grid.get_child(0)
		app.home.show_home_preview(ScenarioCatalog.find("C03"), starter)
		await capture("%d-23-accueil-survol" % dimensions.x)
		expect(app.home.home_preview_popup.visible and root.get_visible_rect().encloses(app.home.home_preview_popup.get_global_rect()), "La bulle de l’accueil doit rester dans la fenêtre.")
		app.home.dismiss_home_preview()
	root.size = Vector2i(1280, 720)
	await settle()
	app.home.show_page(1)
	app.home.duration_input.show_popup()
	await capture("1280-12-durees")
	expect(app.home.duration_input.get_popup().visible, "Le choix de durée doit ouvrir son menu.")
	app.home.duration_input.get_popup().hide()
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = dimensions
		await settle()
		app.home.browser.show_card_preview(ScenarioCatalog.find("C02"))
		await capture("%d-16-survol" % dimensions.x)
		var popup: Control = app.home.browser.preview_popup
		expect(popup.visible and root.get_visible_rect().encloses(popup.get_global_rect()), "La bulle doit rester lisible et entièrement dans la fenêtre.")
		app.home.browser.dismiss_card_preview()
	root.size = Vector2i(1280, 720)
	app.home.show_page(2)
	var importer: SensitivityImport = app.home.reference_import
	importer.game_input.select(1)
	importer.select_game()
	importer.dpi_input.value = 800
	importer.value_input.value = 0.35
	importer.apply_button.pressed.emit()
	await capture("1280-17-import-valorant")
	root.size = Vector2i(800, 450)
	await capture("800-17-import-valorant")
	validate_scrolls(app.home)
	root.size = Vector2i(1280, 720)
	expect(is_equal_approx(app.aim_camera.degrees_per_count, 0.0245), "Le réglage importé doit réellement changer la caméra.")
	app.home.show_page(3)
	await capture("1280-18-conversion-valorant")
	app.home.show_page(2)
	importer.game_input.select(2)
	importer.select_game()
	importer.title_input.text = "Modern Warfare III (2023) · exemple mesuré"
	importer.value_input.value = 5.0
	importer.measurement_input.value = 34.123456
	importer.apply_button.pressed.emit()
	await capture("1280-19-import-cod")
	app.home.show_page(3)
	await capture("1280-20-conversion-cod")
	expect(is_equal_approx(app.home.conversion_value, 5.0), "Le coefficient mesuré doit permettre la conversion inverse exacte.")
	app.home.show_page(3)
	app.home.game_input.show_popup()
	await capture("1280-13-jeux")
	expect(app.home.game_input.get_popup().visible, "Le choix de jeu doit ouvrir son menu.")
	app.home.game_input.get_popup().hide()
	app.home.show_page(5)
	var settings_scroll: ScrollContainer = app.home.pages[5]
	var advanced: Control = app.home.fov_input.get_parent().get_parent()
	(advanced.get_parent().get_child(0) as Button).button_pressed = true
	await settle()
	settings_scroll.scroll_vertical = int(settings_scroll.get_v_scroll_bar().max_value)
	await capture("1280-14-options")
	validate_scrolls(app.home)
	for style in ["cross", "circle", "t"]:
		var crosshair_profile: Dictionary = app.home.read_profile()
		crosshair_profile.crosshair_style = style
		crosshair_profile.crosshair_color = "#64e6d9"
		crosshair_profile.crosshair_size_px = 6.0
		crosshair_profile.crosshair_outline = true
		app.home.crosshair_settings.configure(crosshair_profile)
		app.home.crosshair_settings.changed.emit()
		await settle()
		settings_scroll.ensure_control_visible(app.home.crosshair_settings)
		await capture("1280-24-viseur-" + style)
		validate_scrolls(app.home)
	root.size = Vector2i(800, 450)
	await settle()
	settings_scroll.ensure_control_visible(app.home.crosshair_settings)
	await capture("800-24-viseur")
	validate_scrolls(app.home)
	root.size = Vector2i(1280, 720)
	app.start_practice("C03", 30.0)
	await capture("1280-06-depart")
	root.size = Vector2i(800, 450)
	await capture("800-06-depart")
	root.size = Vector2i(1280, 720)
	for preparation_us in [1100000, 2100000]:
		app.clock.accumulated_us = preparation_us
		app.clock.resumed_us = Time.get_ticks_usec()
		app.update_telemetry()
		await capture("1280-06-decompte-%s" % ("2" if preparation_us < 2000000 else "1"))
	app.begin_training(Time.get_ticks_usec())
	await capture("1280-07-entrainement")
	app.hud.weapon_feedback.play_shot()
	app.hud.weapon_feedback.set_process(false)
	await RenderingServer.frame_post_draw
	write_capture("1280-21-tir")
	app.hud.weapon_feedback.update_processing()
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	write_capture("1280-22-recul")
	var direction: Vector3 = app.engine.target_direction(0, app.clock.elapsed_s(Time.get_ticks_usec()))
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2((app.aim_camera.yaw_deg - rad_to_deg(atan2(-direction.x, -direction.z))) / app.aim_camera.degrees_per_count,
		(app.aim_camera.pitch_deg - rad_to_deg(asin(direction.y))) / app.aim_camera.degrees_per_count)
	app._input(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	app._input(click)
	expect(app.engine.hits == 1 and app.hud.hit_remaining_s > 0.0, "Le hitmarker capturé doit provenir d’un vrai impact du moteur.")
	app.hud.set_process(false)
	await RenderingServer.frame_post_draw
	write_capture("1280-25-impact")
	app.hud.update_processing()
	app.pause_test()
	await capture("1280-08-pause")
	app.resume_test()
	app.clock.accumulated_us = 30000000
	app.finish_training(true)
	await capture("1280-09-resultat")
	root.size = Vector2i(800, 450)
	await capture("800-09-resultat")
	validate_scrolls(app.session_panel)
	root.size = Vector2i(1280, 720)
	var domain := DomainTests.new()
	domain.verify = expect
	var calibration := domain.completed_calibration([30, 40, 70])
	var example_trial: Dictionary = calibration.trials[0].duplicate(true)
	example_trial.warmup = not bool(example_trial.scored)
	app.session_panel.present_result(example_trial, "Données synthétiques de test, sans effet sur le profil utilisateur.", true, 1, 60)
	var comparison := CalibrationService.new()
	comparison.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "visual-comparison")
	app.session_panel.present_calibration_context(comparison, example_trial)
	app.session_panel.update_rest(2.0, false)
	app.session_panel.set_notice("Illustration · données synthétiques de test.")
	await capture("1280-15-repos")
	expect(app.session_panel.stat_values[1].text == "90 / 90", "Touches et tirs doivent rester entiers après lecture JSON.")
	root.size = Vector2i(800, 450)
	await capture("800-15-repos")
	validate_scrolls(app.session_panel)
	root.size = Vector2i(1280, 720)
	app.session_panel.present_recommendation(calibration.recommendation(), 800.0, "Données synthétiques de test, sans effet sur le profil utilisateur.")
	app.session_panel.set_notice("Illustration · données synthétiques de test.")
	await capture("1280-10-bilan")
	root.size = Vector2i(800, 450)
	await capture("800-10-bilan")
	validate_scrolls(app.session_panel)
	root.size = Vector2i(1280, 720)
	var record_example: Dictionary = example_trial.duplicate(true)
	record_example.warmup = false
	app.session_panel.present_result(record_example, "Fixture de rendu isolée, aucun record utilisateur.", false, 0, 0)
	app.session_panel.present_record(300.0, false)
	app.session_panel.set_notice("Illustration de la célébration · données de test.")
	await RenderingServer.frame_post_draw
	write_capture("1280-29-record-exemple")
	app.return_to_menu()
	root.size = Vector2i(1280, 720)
	app.home.show_page(4)
	var summaries: Array[Dictionary] = [{"title": "La grille · exemple de test", "count": 12, "latest_median": 640.0, "best": 725.0, "change_pct": 15.0, "recent_scores": [410.0, 430.0, 425.0, 520.0, 490.0, 590.0, 570.0, 640.0, 675.0, 620.0, 725.0, 660.0]}]
	summaries[0].scenario_id = "C03"
	summaries[0].family = "click"
	summaries[0].comparison_key = "visual-test-context"
	summaries[0].duration_s = 30.0
	summaries[0].dpi = 800
	summaries[0].cm_per_360 = 35.0
	summaries[0].latest_score = 660.0
	var history_sessions: Array[Dictionary] = []
	var history_scores: Array[float] = []
	for session_index in 12:
		var history_metrics := {"shots": 30 + session_index, "hits": 25 + session_index,
			"accuracy_pct": 100.0 * float(25 + session_index) / float(30 + session_index),
			"accuracy_fraction": float(25 + session_index) / float(30 + session_index), "hits_per_s": float(25 + session_index) / 30.0}
		var history_score := ScoringService.score({"family": "click", "metrics": history_metrics}, ScenarioCatalog.find("C03").reference_hits_s)
		history_scores.append(history_score)
		history_sessions.append({"session_id": "visual-" + str(session_index), "created_at_utc": "2026-10-12T00:%02d:00Z" % session_index,
			"scenario_id": "C03", "comparison_key": "visual-test-context", "score": history_score, "family": "click", "completed": true, "valid": true,
			"metrics": history_metrics})
	summaries[0].recent_sessions = history_sessions
	summaries[0].recent_scores = history_scores
	summaries[0].latest_score = history_scores.back()
	summaries[0].latest_median = ScoringService.median(history_scores.slice(7))
	summaries[0].best = history_scores.max()
	summaries[0].change_pct = (float(summaries[0].latest_median) / ScoringService.median(history_scores.slice(0, 5)) - 1.0) * 100.0
	app.home.show_history(12, summaries)
	app.home.set_status("Illustration de la progression · données synthétiques isolées.")
	await capture("1280-11-courbe-test")
	root.size = Vector2i(800, 450)
	await capture("800-11-tableau-exemple")
	validate_scrolls(app.home)
	app.return_to_menu()
	root.size = Vector2i(1280, 720)
	app.start_guided_calibration()
	await capture("1280-26-guide-depart")
	app.begin_training(Time.get_ticks_usec())
	await capture("1280-27-guide-exercice")
	app.return_to_menu()
	app.start_guided_calibration()
	while not app.calibration.current_stage().is_empty():
		if not app.calibration.accept(domain.trial_report(app.calibration, [25, 80, 40], 4), 4):
			expect(false, "Fixture guidée invalide : " + app.calibration.error)
			break
	expect(app.save_guided_progress("comparing"), "Le bilan guidé de démonstration doit être sauvegardé dans son dossier de test.")
	app.show_recommendation()
	app.session_panel.set_notice("Illustration · données synthétiques de test.")
	await capture("1280-28-guide-affinage")
	root.size = Vector2i(800, 450)
	await capture("800-28-guide-affinage")
	validate_scrolls(app.session_panel)
	root.size = Vector2i(1280, 720)
	for round_index in 2:
		app.next_calibration_stage()
		while not app.calibration.current_stage().is_empty():
			if not app.calibration.accept(domain.trial_report(app.calibration, [25, 80, 40], 4), 4):
				expect(false, "Fixture de validation guidée invalide : " + app.calibration.error)
				break
		expect(app.save_guided_progress("comparing"), "La validation guidée de démonstration doit rester isolée et reprenable.")
		app.show_recommendation()
	app.session_panel.set_notice("Illustration · conseil issu de données synthétiques, pas d’un joueur.")
	await capture("1280-30-guide-conseil-exemple")
	expect(app.session_panel.guided_confirmation.visible and app.session_panel.apply_button.disabled, "Le conseil capturé doit demander un consentement pour l’essai provisoire.")
	app.return_to_menu()
	for definition in ScenarioCatalog.DEFINITIONS:
		app.start_practice(definition.scenario_id, 30.0)
		app.begin_training(Time.get_ticks_usec())
		await capture("1280-31-exercice-" + definition.scenario_id)
		expect(app.hud.timer_card.is_visible_in_tree() and app.hud.metric_card.is_visible_in_tree(), "Chaque exercice présente temps et performance sans titre permanent.")
		expect(app.hud.title_label.text.is_empty() and app.hud.help_label.text.is_empty(), "Aucune aide envahissante n’est affichée pendant " + definition.scenario_id)
		app.return_to_menu()
	for weapon in WeaponCatalog.DEFINITIONS:
		var profile: Dictionary = app.home.read_profile()
		profile.weapon_id = weapon.weapon_id
		profile.sound_enabled = false
		app.home.bind_profile(profile)
		app.start_practice("C03", 30.0)
		app.begin_training(Time.get_ticks_usec())
		await capture("1280-32-arme-" + weapon.weapon_id)
		var model: WeaponViewmodel = app.hud.weapon_feedback.viewmodel
		expect(model != null and model.selected_id == weapon.weapon_id and not model.meshes.is_empty(), "Chaque arme capturée utilise une géométrie réellement 3D.")
		app.return_to_menu()
	root.size = Vector2i(800, 450)
	app.start_practice("T05", 30.0)
	app.begin_training(Time.get_ticks_usec())
	await capture("800-33-gameplay")
	expect(app.hud.timer_card.get_global_rect().end.x < 400.0 and app.hud.metric_card.get_global_rect().position.x > 400.0, "Les deux compteurs restent dans les coins, même à800px.")
	app.return_to_menu()
	print("VISUAL SMOKE : %d captures, %s." % [capture_count, "échec" if failed else "0 échec"])
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
