extends SceneTree

const MainScene := preload("res://scenes/app/Main.tscn")
const VisualFixtures := preload("res://tests/progressive_visual_fixtures.gd")
const LAYOUTS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(800, 450), Vector2i(1920, 1080)]

var app: Node
var failed: bool = false
var screenshot_dir: String = "res://dist/preview"
var capture_count: int = 0
var capture_names: Array[String] = []
var lifecycle_states: Array[Dictionary] = []


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
	capture_names.append(caption + ".png")


func validate_scrolls(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control and not child.is_visible_in_tree():
			continue
		if child is ScrollContainer:
			expect(child.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER and not child.get_v_scroll_bar().is_visible_in_tree(), "Le défilement reste disponible sans barre visible : " + str(child.get_path()))
			expect(not child.get_h_scroll_bar().is_visible_in_tree() and child.get_h_scroll_bar().max_value <= child.get_h_scroll_bar().page + 1.0, "Aucun débordement horizontal masqué : " + str(child.get_path()))
			for content in child.get_children():
				if content is Container:
					expect(maxf(content.size.x, content.get_combined_minimum_size().x) <= child.size.x + 1.0, "Débordement horizontal : " + str(child.get_path()) + " (" + str(content.size.x) + " > " + str(child.size.x) + ")")
		validate_scrolls(child)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Un affichage graphique est nécessaire pour valider les captures.")
		quit(1)
		return
	if not OS.get_environment("AIM_LOCAL_SCREENSHOT_DIR").is_empty():
		screenshot_dir = OS.get_environment("AIM_LOCAL_SCREENSHOT_DIR")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshot_dir)) != OK:
		push_error("Dossier de captures inaccessible : " + screenshot_dir)
		quit(1)
		return
	var marker_path := screenshot_dir.path_join("CURRENT")
	if FileAccess.file_exists(marker_path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(marker_path)) != OK:
		push_error("L’ancien marqueur CURRENT ne peut pas être remplacé.")
		quit(1)
		return
	app = MainScene.instantiate()
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	root.add_child(app)
	for dimensions in LAYOUTS:
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
		app.home.show_home_preview(ScenarioCatalog.find_practice("C03"), starter)
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
		app.home.browser.show_card_preview(ScenarioCatalog.find_practice("C02"))
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
	app.set_process(false)
	await capture("1280-06-depart")
	expect(app.hud.countdown_label.text == "3", "Le départ affiche le premier chiffre réel du compte à rebours.")
	root.size = Vector2i(800, 450)
	await capture("800-06-depart")
	root.size = Vector2i(1280, 720)
	for preparation_us in [1100000, 2100000]:
		app.clock.accumulated_us = preparation_us
		app.clock.resumed_us = Time.get_ticks_usec()
		app.update_telemetry()
		await capture("1280-06-decompte-%s" % ("2" if preparation_us < 2000000 else "1"))
		expect(app.hud.countdown_label.text == ("2" if preparation_us < 2000000 else "1"), "Les chiffres 2 et 1 proviennent du chronomètre de préparation.")
	app.begin_training(Time.get_ticks_usec())
	app.set_process(true)
	await capture("1280-07-entrainement")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var shots_before: int = app.engine.shots
	app._input(click)
	expect(app.engine.shots == shots_before + 1 and app.hud.weapon_feedback.flash_remaining_s > 0.0 and app.hud.weapon_feedback.viewmodel.flash.visible, "Le flash capturé provient d’un vrai tir transmis au moteur.")
	app.hud.weapon_feedback.set_process(false)
	await RenderingServer.frame_post_draw
	write_capture("1280-21-tir")
	app.hud.weapon_feedback.update_processing()
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	write_capture("1280-22-recul")
	app.clock.pause(Time.get_ticks_usec())
	var direction: Vector3 = app.engine.target_direction(0, app.clock.elapsed_s(Time.get_ticks_usec()))
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2((app.aim_camera.yaw_deg - rad_to_deg(atan2(-direction.x, -direction.z))) / app.aim_camera.degrees_per_count,
		(app.aim_camera.pitch_deg - rad_to_deg(asin(direction.y))) / app.aim_camera.degrees_per_count)
	app._input(motion)
	var hits_before: int = app.engine.hits
	app._input(click)
	expect(app.engine.hits == hits_before + 1 and app.hud.hit_remaining_s > 0.0, "Le hitmarker capturé doit provenir d’un vrai impact du moteur.")
	app.hud.set_process(false)
	await RenderingServer.frame_post_draw
	write_capture("1280-25-impact")
	app.hud.update_processing()
	app.clock.resume(Time.get_ticks_usec())
	app.pause_test()
	await capture("1280-08-pause")
	root.size = Vector2i(800, 450)
	await capture("800-08-pause")
	expect(root.get_visible_rect().encloses(app.pause_panel.apply_button.get_global_rect()), "La sensibilité en pause doit rester accessible dans la petite fenêtre.")
	root.size = Vector2i(1280, 720)
	app.pause_panel.unit_input.select(1)
	app.pause_panel.select_unit(1)
	app.pause_panel.sensitivity_input.value = 0.4
	await capture("1280-34-sensibilite-en-pause")
	app.resume_test()
	app.clock.accumulated_us = 30000000
	app.finish_training(true)
	mark_synthetic("Illustration · visée et durée simulées, pas les performances d’un joueur.")
	await capture("1280-09-resultat")
	root.size = Vector2i(800, 450)
	await capture("800-09-resultat")
	validate_scrolls(app.session_panel)
	root.size = Vector2i(1280, 720)
	app.return_to_menu()
	await capture_progressive_workflow()
	if app.progressive.trials.is_empty():
		app.queue_free()
		await process_frame
		quit(1)
		return
	var record_example: Dictionary = app.progressive.trials[0].duplicate(true)
	app.session_panel.present_result(record_example, "Fixture de rendu isolée, aucun record utilisateur.", false, 0, 0)
	app.session_panel.present_record(float(record_example.score) * 0.8, false)
	mark_synthetic()
	await RenderingServer.frame_post_draw
	write_capture("1280-29-record-exemple")
	app.return_to_menu()
	root.size = Vector2i(1280, 720)
	app.home.show_page(4)
	var summaries: Array[Dictionary] = [{"title": ScenarioCopy.title(ScenarioCatalog.find_practice("C03")) + " · données synthétiques", "count": 12}]
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
		var history_report := VisualFixtures.session_report("C03", app.home.read_profile(), 30.0, app.current_aspect(), 42,
			25.0 + session_index, "visual-" + str(session_index), null, 5 + session_index)
		history_report.created_at_utc = "2026-10-12T00:%02d:00Z" % session_index
		expect(ScoringService.validate_result(history_report).is_empty(), "Chaque point de progression synthétique utilise des mesures temporelles V2 vérifiables.")
		history_scores.append(float(history_report.score))
		history_sessions.append(history_report)
	summaries[0].comparison_key = history_sessions[0].comparison_key
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
	expect(ScenarioCatalog.practice_definitions().size() == 18 and ScenarioCatalog.find_practice("M01") != null and ScenarioCatalog.find_practice("T10") != null, "La galerie utilise les dix-huit exercices actuels, dont M01 et T10.")
	for definition in ScenarioCatalog.practice_definitions():
		app.start_practice(definition.scenario_id, 30.0)
		app.begin_training(Time.get_ticks_usec())
		await capture("1280-31-exercice-" + definition.scenario_id)
		validate_gameplay(definition.scenario_id)
		app.return_to_menu()
	await capture_weapon_inspections()
	await capture_routine_workflow()
	await capture_lifecycle_workflow()
	await capture_expiry_result()
	await capture_legacy_progressive()
	for scenario_id in ["D01", "D02"]:
		app.prepare_training(ScenarioCatalog.find_practice(scenario_id), 30.0, 42, app.home.read_profile())
		app.begin_training(Time.get_ticks_usec())
		app.set_process(false)
		for sample_index in 3:
			var sample_s := float(sample_index) * (0.4 if scenario_id == "D01" else 1.0)
			app.engine.advance_to(sample_s)
			app.target_pool.sync(app.engine, sample_s)
			app.update_telemetry()
			await capture("1280-35-pattern-%s-%d" % [scenario_id, sample_index])
		app.return_to_menu()
		app.set_process(true)
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
	validate_gameplay("T05")
	app.return_to_menu()
	expect(lifecycle_states.size() == 10 and capture_count == 177 and capture_count < 180, "La galerie actuelle conserve dix captures temporelles dans une limite de moins de 180 images.")
	if not failed:
		var marker := FileAccess.open(screenshot_dir.path_join("CURRENT"), FileAccess.WRITE)
		expect(marker != null, "Le marqueur CURRENT de la galerie actuelle est accessible.")
		if marker != null:
			marker.store_string(JSON.stringify({"app_version": ProjectSettings.get_setting("application/config/version"),
				"protocol_version": app.progressive.protocol_version, "scenario_revision": 6,
				"captures": capture_names, "lifecycle_states": lifecycle_states}, "\t"))
			marker.close()
	print("VISUAL CURRENT : 0.8 · protocole 5 · 18 variantes r6 · %d captures temporelles, %s." % [lifecycle_states.size(), "échec" if failed else "0 échec"])
	print("VISUAL SMOKE : %d captures, %s." % [capture_count, "échec" if failed else "0 échec"])
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)


func validate_gameplay(scenario_id: String) -> void:
	expect(app.hud.timer_card.is_visible_in_tree() and app.hud.metric_card.is_visible_in_tree(), "Temps et performance restent visibles pendant " + scenario_id)
	expect(not app.hud.timer_label.text.is_empty() and app.hud.score_label.text.begins_with("Score "), "Le HUD expose le chronomètre et le score du moteur pendant " + scenario_id)
	expect(app.hud.title_label.text.is_empty() and app.hud.help_label.text.is_empty(), "Aucune aide permanente devant les cibles de " + scenario_id)
	expect(root.get_visible_rect().encloses(app.hud.timer_card.get_global_rect()) and root.get_visible_rect().encloses(app.hud.metric_card.get_global_rect()), "Les compteurs tiennent dans la fenêtre pendant " + scenario_id)
	var center_x: float = float(root.size.x) * 0.5
	expect(app.hud.timer_card.get_global_rect().end.x < center_x and app.hud.metric_card.get_global_rect().position.x > center_x, "Les compteurs restent dans les deux coins pendant " + scenario_id)
	expect(app.hud.crosshair_layer.is_visible_in_tree() and app.hud.crosshair_profile.crosshair_style == app.training_profile.crosshair_style, "Le viseur utilise le profil actif pendant " + scenario_id)


func mark_synthetic(message: String = VisualFixtures.NOTICE) -> void:
	app.session_panel.set_notice(message)
	var header_logo: Label = app.session_panel.main_layout.get_child(0).get_child(0)
	header_logo.text = "AIM/LOCAL · DONNÉES SYNTHÉTIQUES"


func capture_progressive_workflow() -> void:
	root.size = Vector2i(1280, 720)
	await settle()
	app.start_progressive_calibration(true, 60.0)
	if not app.is_progressive or app.progressive.current_stage().is_empty():
		expect(false, "Le parcours public de calibration progressive doit démarrer.")
		return
	expect(app.progressive.protocol_version == 5 and app.progressive.duration_s == 60.0 and ProgressiveCalibrationService.TOTAL_TRIALS == 25 and app.selected_definition == app.progressive.definition_for("C02"), "La calibration publique propose vingt-cinq essais de soixante secondes sous protocole 5 temporel.")
	app.set_process(false)
	for dimensions in LAYOUTS:
		root.size = dimensions
		await capture("%d-26-guide-depart" % dimensions.x)
		expect(app.hud.countdown_label.text == "3" and app.hud.title_label.text.contains("1/5 · essai 1/5"), "Le départ vient du premier essai progressif réel.")
	root.size = Vector2i(1280, 720)
	await settle()
	app.begin_training(Time.get_ticks_usec())
	for dimensions in LAYOUTS:
		root.size = dimensions
		await capture("%d-27-guide-exercice" % dimensions.x)
		validate_gameplay("C02 · calibration progressive")
	app.pause_test()
	for dimensions in LAYOUTS:
		root.size = dimensions
		await capture("%d-37-calibration-pause" % dimensions.x)
		expect(app.pause_panel.locked and not app.pause_panel.editor.visible, "La calibration conserve sa sensibilité verrouillée en pause.")
	root.size = Vector2i(1280, 720)
	app.return_to_menu()
	app.home.hide()
	for block_index in 5:
		var report: Dictionary = {}
		var context: Dictionary = {}
		var tested_distances_cm: Array[float] = []
		for trial_index in 5:
			var stage: Dictionary = app.progressive.current_stage()
			if stage.is_empty():
				expect(false, "Fixture progressive interrompue avant vingt-cinq essais.")
				app.set_process(true)
				return
			expect(int(stage.block_index) == block_index and int(stage.trial_index) == trial_index and stage.duration_s == 60.0, "Chaque bloc conserve cinq essais de soixante secondes dans l’ordre public.")
			var distance_cm: float = stage.profile.cm_per_360
			for tested_cm in tested_distances_cm:
				expect(not is_equal_approx(distance_cm, tested_cm), "Les cinq sensibilités du bloc doivent être distinctes.")
			tested_distances_cm.append(distance_cm)
			report = VisualFixtures.progressive_report(app.progressive)
			context = VisualFixtures.trial_context(app.progressive, report)
			if not app.progressive.accept(report):
				expect(false, "Fixture progressive refusée : " + app.progressive.error)
				app.set_process(true)
				return
			if trial_index == 1:
				var next_stage: Dictionary = app.progressive.current_stage()
				var first_cm: float = tested_distances_cm[0]
				var second_cm: float = tested_distances_cm[1]
				var next_cm: float = next_stage.profile.cm_per_360
				var improved: bool = ScoringService.utility(report) > ScoringService.utility(app.progressive.block_trials[0])
				expect(next_cm > second_cm and next_cm < first_cm if improved else next_cm > first_cm, "Le score du deuxième essai détermine la prochaine sensibilité.")
		app.session_panel.present_progressive_trial(report, VisualFixtures.NOTICE, context)
		mark_synthetic(VisualFixtures.NOTICE + " Bloc %d/5 · cinq essais de 60 s." % (block_index + 1))
		app.session_panel.update_rest(2.0, block_index == 4)
		for dimensions in LAYOUTS:
			root.size = dimensions
			await capture("%d-38-calibration-bloc-%d-exemple" % [dimensions.x, block_index + 1])
			validate_scrolls(app.session_panel)
			expect(app.session_panel.progressive_history_grid.get_child_count() == 5 and app.session_panel.progress.value == (block_index + 1) * 5, "Le bloc affiche ses cinq sensibilités et sa progression sur vingt-cinq essais.")
			expect(root.get_visible_rect().encloses(app.session_panel.next_button.get_global_rect()), "Continuer reste accessible dans chaque format.")
			if block_index == 0:
				write_capture("%d-15-repos" % dimensions.x)
			elif block_index == 4:
				write_capture("%d-28-guide-affinage" % dimensions.x)
	root.size = Vector2i(1280, 720)
	expect(app.progressive.completed() and app.progressive.trials.size() == 25 and app.progressive.blocks.size() == 5, "Le bilan provient des vingt-cinq fixtures acceptées par le service public.")
	expect(app.store.save_progressive_checkpoint(app.progressive.checkpoint()), "Le checkpoint synthétique reste isolé sous user://tests.")
	app.show_progressive_recommendation()
	mark_synthetic()
	var recommendation: Dictionary = app.progressive.recommendation()
	expect(app.session_panel.hero_label.text == AimUI.sensitivity(recommendation.recommended_sensitivity), "Le bilan présente une unique sensibilité issue du service progressif.")
	for dimensions in LAYOUTS:
		root.size = dimensions
		await capture("%d-10-bilan" % dimensions.x)
		validate_scrolls(app.session_panel)
		expect(root.get_visible_rect().encloses(app.session_panel.apply_button.get_global_rect()), "Appliquer reste accessible dans chaque format.")
		write_capture("%d-30-guide-conseil-exemple" % dimensions.x)
	app.session_panel.details_toggle.button_pressed = true
	for dimensions in LAYOUTS:
		root.size = dimensions
		await settle()
		app.session_panel.result_scroll.ensure_control_visible(app.session_panel.details_content.get_child(1))
		await capture("%d-41-calibration-mesures-exemple" % dimensions.x)
		validate_scrolls(app.session_panel)
		expect(root.get_visible_rect().encloses(app.session_panel.apply_button.get_global_rect()), "Les calculs dépliés ne masquent pas l’action finale.")
	root.size = Vector2i(1280, 720)
	app.set_process(true)


func capture_weapon_inspections() -> void:
	app.return_to_menu()
	app.home.show_page(5)
	var settings_scroll: ScrollContainer = app.home.pages[5]
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = dimensions
		for weapon in WeaponCatalog.DEFINITIONS:
			var profile: Dictionary = app.home.read_profile()
			profile.weapon_id = weapon.weapon_id
			profile.sound_enabled = false
			app.home.bind_profile(profile)
			app.home.weapon_preview.set_inspection_mode(true)
			await settle()
			settings_scroll.ensure_control_visible(app.home.weapon_preview)
			await capture("%d-36-inspection-%s" % [dimensions.x, weapon.weapon_id])
			validate_scrolls(app.home)
			var model: WeaponViewmodel = app.home.weapon_preview.viewmodel
			expect(model.selected_id == weapon.weapon_id and model.inspection_mode and model.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Chaque arme utilise son vrai rendu orthographique de profil.")
			expect(absf(model.camera.global_basis.z.normalized().dot(model.muzzle_axis())) < 0.00001 and not model.flash.visible, "Le profil est latéral et sans flash.")
			for hand_root in model.hand_roots:
				expect(not hand_root.is_visible_in_tree(), "L’inspection montre l’arme nue, sans mains ni manches.")
			var selected: Node3D = model.models[weapon.weapon_id]
			var padded_region: Rect2 = model.region_px.grow(-minf(model.size.x, model.size.y) * 0.09)
			for mesh in model.meshes:
				if not selected.is_ancestor_of(mesh) or model.is_hand_mesh(mesh):
					continue
				expect(mesh.is_visible_in_tree(), "L’inspection conserve toutes les pièces de l’arme.")
				var bounds_m: AABB = mesh.mesh.get_aabb()
				for corner_index in 8:
					var point_px: Vector2 = model.project_to_control(mesh.global_transform * bounds_m.get_endpoint(corner_index))
					expect(padded_region.grow(1.0).has_point(point_px), "L’arme entière reste contenue dans son aperçu de profil.")
			expect(root.get_visible_rect().encloses(app.home.weapon_preview.get_global_rect()), "L’aperçu de profil reste entièrement visible à 800 et 1280 px.")
	root.size = Vector2i(1280, 720)


func capture_routine_workflow() -> void:
	app.return_to_menu()
	app.set_process(false)
	for duration_s in [45.0, 60.0]:
		root.size = Vector2i(1280, 720)
		await settle()
		app.start_routine(duration_s)
		if not app.is_routine or app.routine.plan.size() != 3:
			expect(false, "La routine publique doit préparer ses trois étapes longues.")
			app.set_process(true)
			return
		for stage_index in 3:
			var stage: Dictionary = app.routine.current_stage(app.routine_index)
			expect(stage.index == stage_index and stage.duration_s == duration_s and app.selected_definition == ScenarioCatalog.find_practice(stage.scenario_id), "La routine suit les variantes temporelles M01, T10 et S02 depuis current_stage.")
			for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
				root.size = dimensions
				await capture("%d-39-routine-%d-etape-%d-depart" % [dimensions.x, int(duration_s), stage_index + 1])
				expect(app.hud.title_label.text.contains("Étape %d/3" % (stage_index + 1)), "Le départ identifie l’étape de la routine.")
			root.size = Vector2i(1280, 720)
			await settle()
			app.begin_training(Time.get_ticks_usec())
			for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
				root.size = dimensions
				await capture("%d-39-routine-%d-etape-%d-exercice" % [dimensions.x, int(duration_s), stage_index + 1])
				validate_gameplay(stage.scenario_id)
			app.finish_training(false, false)
			var report := VisualFixtures.routine_report(stage, app.training_profile, app.training_aspect, app.selected_seed)
			expect(report.score_version == ScoringService.version_for(app.selected_definition) and ScoringService.validate_result(report).is_empty(), "Les mesures synthétiques de routine sont cohérentes avec leur score V1 ou V2.")
			app.last_report = report
			app.present_routine_result(VisualFixtures.NOTICE, false)
			app.routine_auto_continue = false
			mark_synthetic(VisualFixtures.NOTICE + " Étape %d/3 · %s." % [stage_index + 1, ScenarioCopy.title(ScenarioCatalog.find_practice(stage.scenario_id))])
			for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
				root.size = dimensions
				await capture("%d-39-routine-%d-etape-%d-repos-exemple" % [dimensions.x, int(duration_s), stage_index + 1])
				validate_scrolls(app.session_panel)
			root.size = Vector2i(1280, 720)
			await settle()
			app.rest_until_us = 0
			app.continue_routine()
			expect(app.routine_index == stage_index + 1, "Continuer accepte la fixture isolée et avance la routine publique.")
		mark_synthetic()
		for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
			root.size = dimensions
			await capture("%d-40-routine-%d-bilan-exemple" % [dimensions.x, int(duration_s)])
			validate_scrolls(app.session_panel)
			expect(app.session_panel.hero_label.text == "3 / 3", "Le bilan conserve trois résultats séparés, sans somme de scores.")
		app.return_to_menu()
	root.size = Vector2i(1280, 720)
	app.set_process(true)


func capture_live_snapshot(caption: String, sample_s: float, reference: ScenarioEngine) -> void:
	app.clock.accumulated_us = ceili(sample_s * 1000000.0)
	app._process(0.1)
	var actual_s: float = app.engine.elapsed_s
	reference.advance_to(actual_s)
	expect(app.session_active and app.screen == app.Screen.TRAINING and not app.engine.completed, "La capture temporelle conserve un exercice actif : " + caption)
	expect(app.engine.targets == reference.targets and app.engine.expired == reference.expired and app.engine.spawned == reference.spawned,
		"La capture reproduit les cibles, échéances et expirations du moteur seedé : " + caption)
	expect(app.engine.shots == 0 and app.engine.timeline.event_count == 0, "Le renouvellement capturé ne dépend d’aucun tir ni mouvement de souris : " + caption)
	var report: Dictionary = app.engine.result(app.training_profile, app.training_aspect, false)
	var remaining_s: int = ceili(maxf(app.selected_duration_s - actual_s, 0.0))
	expect(app.hud.score_label.text == "Score %d" % int(report.score) and absf(app.hud.progress.value - actual_s) <= maxf(app.hud.progress.step * 0.5, 0.000001)
		and app.hud.timer_label.text == "%d:%02d" % [remaining_s / 60, remaining_s % 60],
		"Le HUD actif affiche le temps et le score réellement recalculés par le moteur : " + caption)
	if report.score_version == ScoringService.EXPIRY_VERSION:
		expect(app.hud.score_label.text == "Score 0" and app.hud.metric_label.text == ("0 · 0 %" if app.engine.expired > 0 else "0 · —"),
			"Les expirations sans tir passent d’une réussite inconnue à zéro et conservent un score nul.")
		expect(app.hud.expired_label.visible == (app.engine.expired > 0) and (app.engine.expired == 0 or app.hud.expired_label.text.contains(str(app.engine.expired))),
			"Le nombre de cibles expirées provient du moteur actif.")
	var target_ids: Array[int] = []
	var diameters_deg: Array[float] = []
	for target_index in app.engine.targets.size():
		var geometry: Dictionary = reference.target_geometry(target_index, actual_s)
		var sphere: MeshInstance3D = app.target_pool.spheres[target_index]
		expect(sphere.visible and sphere.global_position.is_equal_approx(app.aim_camera.global_position + Vector3(geometry.center_offset_m))
			and sphere.global_basis.get_scale().is_equal_approx(Vector3.ONE * float(geometry.radius_m)),
			"La silhouette capturée conserve la position et le rayon physiques du moteur : " + caption)
		target_ids.append(int(app.engine.targets[target_index].id))
		diameters_deg.append(float(geometry.angular_diameter_deg))
	lifecycle_states.append({"capture": caption + ".png", "scenario_id": app.selected_definition.scenario_id,
		"seed": app.selected_seed, "elapsed_s": actual_s, "active": app.session_active, "shots": app.engine.shots,
		"input_events": app.engine.timeline.event_count, "targets_expired": app.engine.expired,
		"score_version": report.score_version, "score": report.score, "target_ids": target_ids, "diameters_deg": diameters_deg})
	await capture(caption)
	validate_gameplay(app.selected_definition.scenario_id)


func capture_lifecycle_workflow() -> void:
	app.return_to_menu()
	root.size = Vector2i(1280, 720)
	await settle()
	app.set_process(false)
	for scenario_id in ["C03", "T10"]:
		var definition := ScenarioCatalog.find_practice(scenario_id)
		expect(app.prepare_training(definition, 30.0, 42, app.home.read_profile()), "La capture temporelle prépare la vraie définition publique.")
		app.begin_training(Time.get_ticks_usec())
		app.clock.pause(Time.get_ticks_usec())
		var reference := ScenarioEngine.new()
		expect(reference.start(definition, app.selected_seed, 30.0), "Le moteur de référence conserve la graine enregistrée.")
		var earliest_index := 0
		for target_index in app.engine.targets.size():
			if float(app.engine.targets[target_index].expires_s) < float(app.engine.targets[earliest_index].expires_s):
				earliest_index = target_index
		var first_target: Dictionary = app.engine.targets[earliest_index].duplicate(true)
		var deadline_s: float = first_target.expires_s
		var initial_diameter_deg: float = app.engine.target_angular_diameter_deg(earliest_index, 0.0)
		if scenario_id == "C03":
			await capture_live_snapshot("1280-42-lifeC03-early", 0.0, reference)
			await capture_live_snapshot("1280-42-lifeC03-late", deadline_s * 0.7, reference)
			expect(app.engine.targets[earliest_index].id == first_target.id and app.engine.target_angular_diameter_deg(earliest_index, app.engine.elapsed_s) < initial_diameter_deg,
				"C03 rétrécit sa cible initiale selon son âge avant son échéance seedée.")
			await capture_live_snapshot("1280-42-lifeC03-predeadline", deadline_s - 0.001, reference)
			expect(app.engine.expired == 0 and app.engine.targets[earliest_index].id == first_target.id, "La cible initiale reste présente juste avant sa vraie échéance.")
			await capture_live_snapshot("1280-42-lifeC03-deadline", deadline_s, reference)
			var replacement_id: int = app.engine.targets[earliest_index].id
			expect(app.engine.expired >= 1 and replacement_id != first_target.id and is_equal_approx(float(app.engine.targets[earliest_index].born_s), deadline_s),
				"L’échéance réelle renouvelle C03 immédiatement, sans attendre un tir.")
			await capture_live_snapshot("1280-42-lifeC03-hold-2s", deadline_s + 2.25, reference)
			expect(app.engine.targets[earliest_index].id == replacement_id and app.engine.elapsed_s - float(app.engine.targets[earliest_index].born_s) >= 2.0
				and app.engine.expired == definition.active_targets, "Les six remplacements restent visibles après plus de deux secondes sans input.")
		else:
			await capture_live_snapshot("1280-43-lifeT10-early", 0.0, reference)
			await capture_live_snapshot("1280-43-lifeT10-midlife", 5.0, reference)
			await capture_live_snapshot("1280-43-lifeT10-predeadline", 9.0, reference)
			expect(app.engine.targets[0].id == first_target.id and app.engine.target_angular_diameter_deg(0, app.engine.elapsed_s) < initial_diameter_deg,
				"T10 conserve sa cible et réduit sa taille visable aux instants réels 0, 5 et 9 secondes.")
			await capture_live_snapshot("1280-43-lifeT10-cycle-1", ceil(deadline_s / ScenarioEngine.SAMPLE_STEP_S) * ScenarioEngine.SAMPLE_STEP_S, reference)
			var second_id: int = app.engine.targets[0].id
			expect(app.engine.expired == 1 and second_id != first_target.id and is_equal_approx(float(app.engine.targets[0].born_s), deadline_s),
				"Le suivi renouvelle la cible à l’échéance réelle intégrée entre deux bins de 240 Hz.")
			var next_deadline_s: float = app.engine.targets[0].expires_s
			await capture_live_snapshot("1280-43-lifeT10-cycle-2", ceil(next_deadline_s / ScenarioEngine.SAMPLE_STEP_S) * ScenarioEngine.SAMPLE_STEP_S, reference)
			expect(app.engine.expired == 2 and app.engine.targets[0].id != second_id, "Deux cycles T10 distincts sont renouvelés dans le même exercice actif.")
		app.return_to_menu()
	app.set_process(true)


func capture_expiry_result() -> void:
	root.size = Vector2i(1280, 720)
	await settle()
	var report := VisualFixtures.session_report("C03", app.home.read_profile(), 30.0, app.current_aspect(), 42,
		36.0, "visual-expiry-v2", null, 12)
	expect(ScoringService.validate_result(report).is_empty() and report.score_version == 2 and report.metrics.effective_accuracy_pct == 60.0,
		"Le résultat V2 illustre 36 touches, 48 tirs et 12 expirations : 60 % de réussite effective.")
	app.home.hide()
	app.session_panel.present_result(report, VisualFixtures.NOTICE, false, 0, 0)
	mark_synthetic(VisualFixtures.NOTICE + " Réussite intégrant 12 cibles expirées.")
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = dimensions
		await capture("%d-44-expirations-score-v2-exemple" % dimensions.x)
		validate_scrolls(app.session_panel)
	app.return_to_menu()


func capture_legacy_progressive() -> void:
	root.size = Vector2i(1280, 720)
	await settle()
	var legacy := ProgressiveCalibrationService.new()
	expect(legacy.begin(app.home.read_profile(), app.current_aspect(), 42, "visual-progressive-legacy-4", 60.0, true, 4),
		"L’illustration historique conserve le protocole 4 explicite.")
	while not legacy.completed():
		var report := VisualFixtures.progressive_report(legacy)
		if not legacy.accept(report):
			expect(false, "Fixture historique de protocole 4 refusée : " + legacy.error)
			return
	var recommendation := legacy.recommendation()
	expect(recommendation.protocol_version == 4 and legacy.trials[0].score_version == 1 and legacy.trials[0].scenario_revision == 3,
		"Le bilan historique garde ses vingt-cinq mesures V1 et les empreintes r3.")
	app.home.hide()
	app.session_panel.present_progressive_complete(recommendation, legacy.baseline.dpi, VisualFixtures.NOTICE)
	mark_synthetic(VisualFixtures.NOTICE + " Historique 0.7 · protocole 4 · scores V1.")
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = dimensions
		await capture("%d-45-calibration-protocole4-exemple" % dimensions.x)
		validate_scrolls(app.session_panel)
	app.return_to_menu()
	root.size = Vector2i(1280, 720)
