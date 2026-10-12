extends SceneTree

const MainScene := preload("res://scenes/app/Main.tscn")
const VisualFixtures := preload("res://tests/progressive_visual_fixtures.gd")
const LAYOUTS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(800, 450), Vector2i(1920, 1080)]

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
	var summaries: Array[Dictionary] = [{"title": ScenarioCopy.title(ScenarioCatalog.find("C03")) + " · données synthétiques", "count": 12}]
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
	expect(ScenarioCatalog.DEFINITIONS.size() == 18 and ScenarioCatalog.find("M01") != null and ScenarioCatalog.find("T10") != null, "La galerie utilise les dix-huit exercices actuels, dont M01 et T10.")
	for definition in ScenarioCatalog.DEFINITIONS:
		app.start_practice(definition.scenario_id, 30.0)
		app.begin_training(Time.get_ticks_usec())
		await capture("1280-31-exercice-" + definition.scenario_id)
		validate_gameplay(definition.scenario_id)
		app.return_to_menu()
	await capture_weapon_inspections()
	await capture_routine_workflow()
	for scenario_id in ["D01", "D02"]:
		app.prepare_training(ScenarioCatalog.find(scenario_id), 30.0, 42, app.home.read_profile())
		app.begin_training(Time.get_ticks_usec())
		app.set_process(false)
		for sample_index in 3:
			var sample_s := float(sample_index) * (0.4 if scenario_id == "D01" else 1.0)
			app.engine.advance_to(sample_s)
			app.target_pool.sync(app.engine, sample_s)
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
	expect(app.progressive.duration_s == 60.0 and ProgressiveCalibrationService.TOTAL_TRIALS == 25, "La calibration publique propose vingt-cinq essais de soixante secondes.")
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
			expect(stage.index == stage_index and stage.duration_s == duration_s and app.selected_definition.scenario_id == stage.scenario_id, "La routine suit M01, T10 et S02 depuis current_stage.")
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
			expect(ScoringService.validate_result(report).is_empty(), "Les mesures synthétiques de routine sont cohérentes avec le score V1.")
			app.last_report = report
			app.present_routine_result(VisualFixtures.NOTICE, false)
			app.routine_auto_continue = false
			mark_synthetic(VisualFixtures.NOTICE + " Étape %d/3 · %s." % [stage_index + 1, ScenarioCopy.title(ScenarioCatalog.find(stage.scenario_id))])
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
