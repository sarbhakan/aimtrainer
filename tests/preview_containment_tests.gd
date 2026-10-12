extends SceneTree

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("La suite d’aperçus n’a pas atteint sa fin.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_tests() -> void:
	await test_engine_projection()
	test_deterministic_playback()
	test_bounded_process()
	await test_popup_containment()
	await test_hover_lifecycle()
	if "--preview-only" not in OS.get_cmdline_user_args():
		var browser_tests := load("res://tests/browser_preview_tests.gd") as GDScript
		if browser_tests == null or not browser_tests.can_instantiate():
			check(false, "La suite d’interactions des bulles doit compiler.")
		else:
			check(await browser_tests.new().run(self, check), "Les interactions et allocations des bulles doivent se terminer.")
	print("PREVIEW CONTAINMENT : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_engine_projection() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0.25, 1.4, 0.1)
	viewport.add_child(camera)
	var preview := ScenarioPreview.new()
	viewport.add_child(preview)
	await process_frame
	var definitions: Array[ScenarioDefinition] = ScenarioCatalog.DEFINITIONS.duplicate()
	var revised := ScenarioCatalog.find("C02").duplicate() as ScenarioDefinition
	revised.angular_diameter_deg *= 1.4
	revised.distance_m *= 1.7
	revised.revision += 1
	definitions.append(revised)
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		camera.fov = 75.0
		preview.size = Vector2(dimensions)
		for definition in definitions:
			var fingerprint := definition.fingerprint()
			preview.configure(definition, true, camera.fov, float(dimensions.x) / dimensions.y)
			preview.set_process(false)
			var reference := ScenarioEngine.new()
			check(reference.start(definition, ScenarioPreview.DEMO_SEED, ScenarioPreview.DEMO_DURATION_S), "Le moteur de référence doit accepter la définition courante.")
			var shot_count := 0
			for time_s in [0.0, 0.35, 0.85, 1.75, 3.4]:
				if definition.family != "tracking":
					while float(shot_count + 1) * ScenarioPreview.DEMO_SHOT_INTERVAL_S <= time_s + 0.000000001:
						var shot_s := float(shot_count + 1) * ScenarioPreview.DEMO_SHOT_INTERVAL_S
						reference.advance_to(shot_s)
						var target_index := shot_count % reference.targets.size()
						reference.shoot(shot_s, reference.target_direction(target_index, shot_s))
						shot_count += 1
				reference.advance_to(time_s)
				if time_s > preview.elapsed_s:
					preview.advance_demo(time_s - preview.elapsed_s)
				check(preview.preview_error.is_empty() and preview.engine.targets == reference.targets and preview.engine.hits == reference.hits and preview.engine.expired == reference.expired, "%s : la démo doit conserver les apparitions, mouvements et tirs du moteur réel à %.2f s." % [definition.scenario_id, time_s])
				var silhouettes_contained := true
				var maximum_tangent_error_deg := 0.0
				for target_index in preview.engine.targets.size():
					var geometry: Dictionary = reference.target_geometry(target_index, time_s)
					var direction: Vector3 = geometry.direction
					var center := camera.unproject_position(camera.global_position + geometry.center_offset_m)
					check(preview.project_direction(direction).distance_to(center) < 0.003, "%s : le centre doit correspondre à Camera3D à %s, avec la profondeur de la définition." % [definition.scenario_id, dimensions])
					var outline := preview.target_outline(target_index, time_s)
					check(outline.size() == 128, "La silhouette doit utiliser les tangentes réelles de la sphère, sans rayon en pixels imposé.")
					for perimeter_index in outline.size():
						silhouettes_contained = silhouettes_contained and preview.projection_rect().grow(0.01).has_point(outline[perimeter_index])
						if perimeter_index % 16 == 0:
							var ray := camera.project_ray_normal(outline[perimeter_index])
							maximum_tangent_error_deg = maxf(maximum_tangent_error_deg, absf(AimGeometry.angular_error_deg(direction, ray) - float(geometry.angular_diameter_deg) * 0.5))
				check(silhouettes_contained, "%s : aucun bord de cible ne doit être coupé à %s et %.2f s." % [definition.scenario_id, dimensions, time_s])
				check(maximum_tangent_error_deg < 0.00005, "Le diamètre projeté doit provenir de la définition courante, y compris après changement de révision et de distance.")
			check(definition.fingerprint() == fingerprint and preview.engine.definition.fingerprint() == fingerprint, "La démo doit conserver l’empreinte de gameplay sans modifier sa difficulté.")
	viewport.queue_free()
	await process_frame


func test_deterministic_playback() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		var reference := ScenarioPreview.new()
		reference.configure(definition, true)
		reference.advance_demo(3.0)
		for frame_rate in [60, 144, 240]:
			var preview := ScenarioPreview.new()
			preview.configure(definition, true)
			for frame_index in frame_rate * 3:
				preview.advance_demo(1.0 / frame_rate)
			check(preview.preview_error.is_empty() and preview.engine.targets == reference.engine.targets and preview.engine.hits == reference.engine.hits and preview.engine.expired == reference.engine.expired, "%s : la cadence de rendu ne doit changer ni la seed ni les tirs." % definition.scenario_id)
			check(AimGeometry.angular_error_deg(preview.engine.target_direction(0, preview.elapsed_s), reference.engine.target_direction(0, reference.elapsed_s)) < 0.00003, "La démo doit garder la vitesse du scénario à chaque cadence.")
			preview.free()
		reference.free()
	var wrapped := ScenarioPreview.new()
	wrapped.configure(ScenarioCatalog.find("S02"), true)
	wrapped.advance_demo(ScenarioPreview.DEMO_DURATION_S + 0.2)
	var restarted := ScenarioPreview.new()
	restarted.configure(ScenarioCatalog.find("S02"), true)
	restarted.advance_demo(0.2)
	check(is_equal_approx(wrapped.elapsed_s, restarted.elapsed_s) and wrapped.engine.targets == restarted.engine.targets, "Le bouclage doit reprendre exactement la démo seedée.")
	wrapped.free()
	restarted.free()


func test_bounded_process() -> void:
	var preview := ScenarioPreview.new()
	preview.configure(ScenarioCatalog.find("C03"), true)
	preview._process(0.005)
	check(preview.elapsed_s == 0.0, "Le moteur d’aperçu doit attendre le rafraîchissement à 30 Hz.")
	preview._process(NAN)
	preview._process(-1.0)
	check(preview.elapsed_s == 0.0, "Une durée de frame invalide ne doit pas faire avancer la démo.")
	preview._process(600.0)
	check(preview.elapsed_s <= ScenarioPreview.MAX_PROCESS_STEP_S + ScenarioPreview.REDRAW_INTERVAL_S and preview.engine.shots <= 1, "Une frame longue doit garder un coût borné, sans rattrapage de centaines de tirs.")
	preview.size = Vector2(276.0, 174.0)
	check(preview.playback_caption().is_empty() and not preview.playback_badge_rect().has_area(), "Le plus petit aperçu ne doit garder aucun badge animé ou fixe.")
	preview.size = Vector2(320.0, 180.0)
	check(preview.projection_rect().is_equal_approx(Rect2(Vector2.ZERO, preview.size)), "Un cadre au ratio demandé doit utiliser toute sa hauteur, sans réserver une barre.")
	var animated_projection := preview.projection_rect()
	preview.animated = false
	check(preview.projection_rect().is_equal_approx(animated_projection), "Les animations réduites ne doivent pas modifier le cadrage.")
	preview.free()


func test_popup_containment() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var host := Control.new()
	viewport.add_child(host)
	var anchor := Control.new()
	anchor.size = Vector2(96.0, 46.0)
	viewport.add_child(anchor)
	var popup := ExercisePreviewPopup.new()
	popup.theme = preload("res://assets/ui_theme.tres")
	host.add_child(popup)
	var previous_motion_enabled := AimUI.motion_enabled
	AimUI.motion_enabled = true
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(800, 450)]:
		viewport.size = dimensions
		for definition in ScenarioCatalog.DEFINITIONS:
			anchor.position = Vector2(dimensions) - anchor.size
			popup.present(definition, anchor)
			await create_timer(0.04).timeout
			await process_frame
			var context := "%s à %s" % [definition.scenario_id, dimensions]
			check(viewport.get_visible_rect().grow(-11.0).encloses(popup.get_global_rect()), "La bulle ouverte doit rester dans la fenêtre, y compris au redimensionnement : " + context)
			var panel := popup.get_theme_stylebox("panel")
			check(panel.get_content_margin(SIDE_LEFT) == AimUI.SPACE_LG and panel.get_content_margin(SIDE_TOP) == AimUI.SPACE_LG, "La bulle doit réutiliser le token d’espacement partagé.")
			var content_rect := popup.get_global_rect().grow(-AimUI.SPACE_LG)
			for control in [popup.get_child(0) as Control, popup.title_label, popup.preview_frame, popup.preview, popup.description_label]:
				check(content_rect.grow(1.0).encloses(control.get_global_rect()), "Le contenu doit tenir dans les marges sans clipping : " + context)
			for label in [popup.title_label, popup.description_label]:
				check(label.get_line_count() == label.get_visible_line_count() and label.get_combined_minimum_size().y <= label.size.y + 1.0, "Toutes les lignes doivent tenir dans la bulle : " + context)
			check(popup.title_label.text == ScenarioCopy.title(definition) and popup.description_label.text == ScenarioCopy.description(definition), "La bulle doit présenter le titre et la consigne de l’exercice consulté.")
			var view := popup.preview.projection_rect()
			check(Rect2(Vector2.ZERO, popup.preview.size).encloses(view), "La projection entière doit tenir dans son cadre.")
			check(absf(view.size.x - popup.preview.size.x) <= 1.0 and absf(view.size.y - popup.preview.size.y) <= 1.0, "La bulle doit montrer le ratio complet sans réserver de barre ni écraser la démo.")
			check(popup.preview.playback_caption().is_empty() and not popup.preview.playback_badge_rect().has_area() and popup.preview.is_processing(), "La démonstration doit rester animée sans afficher de badge.")
			check(host.get_combined_minimum_size().is_zero_approx() and popup.get_parent() == host and popup.is_set_as_top_level(), "L’aperçu flottant ne doit pas imposer sa hauteur au Control hôte.")
			for corner in [Vector2.ZERO, Vector2(float(dimensions.x) - anchor.size.x, 0.0), Vector2(0.0, float(dimensions.y) - anchor.size.y)]:
				anchor.position = corner
				popup.place_in_viewport()
				check(viewport.get_visible_rect().grow(-11.0).encloses(popup.get_global_rect()), "La bulle doit rester contenue depuis chaque coin de la fenêtre : " + context)
	popup.dismiss()
	check(not popup.visible and not popup.preview.is_processing(), "La fermeture doit immédiatement arrêter la démo.")
	AimUI.motion_enabled = previous_motion_enabled
	viewport.queue_free()
	await process_frame


func test_hover_lifecycle() -> void:
	var previous_motion_enabled := AimUI.motion_enabled
	AimUI.motion_enabled = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var browser := TrainingBrowser.new()
	browser.theme = preload("res://assets/ui_theme.tres")
	viewport.add_child(browser)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for frame_index in 3:
		await process_frame
	var initial_definition := browser.selected_definition
	var definition := ScenarioCatalog.find("C03")
	var card: Button = browser.cards[definition.scenario_id]
	card.grab_focus()
	check(not browser.preview_popup.visible and not browser.preview_timer.is_stopped(), "Le focus doit respecter le délai d’ouverture de la bulle.")
	await create_timer(TrainingBrowser.PREVIEW_DELAY_S + 0.04).timeout
	check(browser.preview_popup.visible and browser.preview_popup.definition == definition and browser.selected_definition == initial_definition, "La bulle au focus doit représenter la carte consultée sans changer la sélection.")
	check(browser.preview_popup.preview.is_processing() and not browser.preview.is_processing(), "Une bulle ouverte doit rester la seule démonstration animée.")
	AimUI.motion_enabled = false
	check(not browser.preview_popup.preview.is_processing() and not browser.preview.is_processing() and browser.preview_popup.preview.playback_caption().is_empty(), "Les animations réduites doivent figer la bulle sans ajouter de badge.")
	AimUI.motion_enabled = true
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	viewport.push_input(cancel, true)
	check(not browser.preview_popup.visible and browser.preview_timer.is_stopped(), "Échap doit fermer la bulle et son délai sans naviguer.")
	card.release_focus()
	browser.show_card_preview(definition, card)
	var initial_scroll_px := browser.catalog_scroll.scroll_vertical
	browser.catalog_scroll.scroll_vertical = initial_scroll_px + AimUI.SPACE_2XL
	await process_frame
	check(browser.catalog_scroll.scroll_vertical != initial_scroll_px and not browser.preview_popup.visible and not browser.preview_popup.preview.is_processing(), "Défiler sans barre visible doit fermer une bulle devenue mal ancrée.")
	browser.schedule_card_preview(definition, card)
	browser.hide()
	check(not browser.preview_popup.visible and browser.preview_timer.is_stopped() and not browser.preview.is_processing(), "Masquer la page doit annuler les bulles et animations en attente.")
	AimUI.motion_enabled = previous_motion_enabled
	viewport.queue_free()
	await process_frame
