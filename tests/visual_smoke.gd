extends SceneTree

const MainScene := preload("res://scenes/app/Main.tscn")
const DomainTests := preload("res://tests/domain_tests.gd")

var app: Node
var failed: bool = false
var screenshot_dir: String = "res://dist/preview"
var capture_count: int = 0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Validation visuelle interrompue après 90 secondes.")
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
	settings_scroll.scroll_vertical = int(settings_scroll.get_v_scroll_bar().max_value)
	await capture("1280-14-options")
	validate_scrolls(app.home)
	app.start_practice("C03", 30.0)
	await capture("1280-06-depart")
	app.begin_training(Time.get_ticks_usec())
	await capture("1280-07-entrainement")
	app.hud.weapon_feedback.play_shot()
	await RenderingServer.frame_post_draw
	write_capture("1280-21-tir")
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	write_capture("1280-22-recul")
	app.pause_test()
	await capture("1280-08-pause")
	app.resume_test()
	app.clock.accumulated_us = 30000000
	app.finish_training(true)
	await capture("1280-09-resultat")
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
	await capture("1280-15-repos")
	expect(app.session_panel.stat_values[1].text == "90", "Le nombre de cibles doit rester entier après lecture JSON.")
	root.size = Vector2i(800, 450)
	await capture("800-15-repos")
	validate_scrolls(app.session_panel)
	root.size = Vector2i(1280, 720)
	app.session_panel.present_recommendation(calibration.recommendation(), 800.0, "Données synthétiques de test, sans effet sur le profil utilisateur.")
	await capture("1280-10-bilan")
	root.size = Vector2i(800, 450)
	await capture("800-10-bilan")
	validate_scrolls(app.session_panel)
	app.return_to_menu()
	root.size = Vector2i(1280, 720)
	app.home.show_page(4)
	var summaries: Array[Dictionary] = [{"title": "La grille · exemple de test", "count": 12, "latest_median": 640.0, "best": 725.0, "change_pct": 15.0, "recent_scores": [410.0, 430.0, 425.0, 520.0, 490.0, 590.0, 570.0, 640.0, 675.0, 620.0, 725.0, 660.0]}]
	app.home.show_history(12, summaries)
	await capture("1280-11-courbe-test")
	print("VISUAL SMOKE : %d captures, %s." % [capture_count, "échec" if failed else "0 échec"])
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
