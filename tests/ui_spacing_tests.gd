extends SceneTree

const DashboardScript := preload("res://scripts/ui/dashboard.gd")
const SessionScript := preload("res://scripts/ui/session_panel.gd")
const InterfaceTheme := preload("res://assets/ui_theme.tres")
const DomainTests := preload("res://tests/domain_tests.gd")

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Les tests d’espacement n’ont pas terminé en 60 secondes.")
		quit(1))
	run_standalone.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_standalone() -> void:
	await run_suite(self, check)
	if "--ui-regressions" in OS.get_cmdline_user_args():
		var ux_tests := load("res://tests/ux_flow_tests.gd").new() as RefCounted
		check(await ux_tests.run(self, check), "Les parcours UI et la précision au focus doivent rester valides.")
		var import_tests := load("res://tests/sensitivity_import_tests.gd").new() as RefCounted
		check(await import_tests.run(self, check), "Les imports et conversions doivent conserver leur précision.")
		var polish_tests := load("res://tests/ui_polish_tests.gd").new() as RefCounted
		check(await polish_tests.run(self, check), "La navigation et les aperçus doivent conserver leur géométrie.")
	print("UI SPACING : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


static func settle(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame


static func push_key(viewport: Viewport, keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		viewport.push_input(event, true)


static func verify_scroll(scroll: ScrollContainer, verify: Callable, context: String) -> void:
	verify.call(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Le défilement vertical reste actif sans barre : " + context)
	verify.call(scroll.horizontal_scroll_mode in [ScrollContainer.SCROLL_MODE_DISABLED, ScrollContainer.SCROLL_MODE_SHOW_NEVER], "Le contenu doit tenir sans barre horizontale : " + context)
	verify.call((scroll.get_child(0) as Control).size.x <= scroll.size.x + 1.0 and scroll.scroll_horizontal == 0, "Le contenu doit tenir dans sa largeur sans défilement horizontal caché : " + context)
	verify.call(not scroll.get_v_scroll_bar().visible and not scroll.get_h_scroll_bar().visible, "Aucune barre ne doit occuper le bord du contenu : " + context)
	verify.call(scroll.follow_focus and scroll.focus_mode == Control.FOCUS_ALL, "Le contenu défilant reste accessible au focus : " + context)


static func test_scroll_inputs(tree: SceneTree, verify: Callable) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var scroll := ScrollContainer.new()
	scroll.theme = InterfaceTheme
	AimUI.configure_scroll(scroll)
	viewport.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := AimUI.column(scroll)
	var controls: Array[Button] = []
	for row_index in 12:
		var control := AimUI.button("Action %d" % (row_index + 1), func() -> void: pass)
		content.add_child(control)
		controls.append(control)
	await settle(tree)
	verify_scroll(scroll, verify, "fixture débordante")
	verify.call(content.size.y > scroll.size.y, "La fixture doit réellement déborder pour vérifier les interactions.")
	var pointer_position_px := scroll.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer_position_px
	motion.global_position = pointer_position_px
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.position = pointer_position_px
		wheel.global_position = pointer_position_px
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = pressed
		viewport.push_input(wheel, true)
	await settle(tree)
	verify.call(scroll.scroll_vertical > 0, "La molette doit déplacer le contenu malgré les barres invisibles.")
	scroll.scroll_vertical = 0
	var gesture := InputEventPanGesture.new()
	gesture.position = pointer_position_px
	gesture.delta = Vector2(0.0, 4.0)
	viewport.push_input(gesture, true)
	await settle(tree)
	verify.call(scroll.scroll_vertical > 0, "Un geste de défilement doit déplacer le contenu sans barre visible.")
	scroll.scroll_vertical = 0
	scroll.grab_focus()
	push_key(viewport, KEY_PAGEDOWN)
	await settle(tree)
	verify.call(scroll.has_focus() and scroll.scroll_vertical > 0, "Page suivante doit faire défiler le conteneur focalisé.")
	push_key(viewport, KEY_HOME)
	await settle(tree)
	verify.call(scroll.scroll_vertical == 0, "Début doit retrouver le haut du contenu.")
	push_key(viewport, KEY_DOWN)
	await settle(tree)
	verify.call(scroll.scroll_vertical > 0, "Flèche bas doit déplacer le conteneur focalisé.")
	push_key(viewport, KEY_END)
	await settle(tree)
	var end_offset_px := scroll.scroll_vertical
	verify.call(end_offset_px > 0 and scroll.get_v_scroll_bar().value + scroll.get_v_scroll_bar().page >= scroll.get_v_scroll_bar().max_value - 1.0, "Fin doit rejoindre le bas réel du contenu.")
	push_key(viewport, KEY_PAGEUP)
	await settle(tree)
	verify.call(scroll.scroll_vertical < end_offset_px, "Page précédente doit remonter le contenu.")
	scroll.scroll_vertical = 0
	controls[-1].grab_focus()
	await settle(tree)
	verify.call(scroll.scroll_vertical > 0 and scroll.get_global_rect().grow(1.0).encloses(controls[-1].get_global_rect()), "Le focus doit rendre visible une action initialement hors champ : offset %d, focus %s, action %s, conteneur %s." % [scroll.scroll_vertical, controls[-1].has_focus(), controls[-1].get_global_rect(), scroll.get_global_rect()])
	verify_scroll(scroll, verify, "après les interactions")
	viewport.queue_free()
	await settle(tree)


static func test_metrics(verify: Callable) -> void:
	var metrics := {"hits": 7, "shots": 10, "hits_per_s": 1.4}
	var original_metrics := metrics.duplicate(true)
	var insights := PerformanceInsights.analyze({"family": "click", "metrics": metrics})
	verify.call(insights.primary_value == "70,0 %" and insights.secondary_value == "7 / 10", "Précision et touches/tirs doivent garder leurs mesures distinctes.")
	verify.call(insights.tempo_value == "84 cibles/min" and insights.tempo_unit == "cibles/min", "1,4 cible par seconde doit afficher 84 cibles par minute.")
	verify.call(insights.tip.contains("84 cibles/min"), "Le conseil détaillé doit employer la même cadence que le bilan.")
	verify.call(metrics == original_metrics and insights.measurements.hits_per_s.value == 1.4 and insights.measurements.hits_per_min.value == 84.0, "La conversion d’affichage doit conserver la mesure canonique en secondes.")
	var board := ProgressBoard.new()
	verify.call(board.measurement_text({"family": "click", "metrics": metrics}).contains("84 cibles/min"), "La chronologie doit afficher la même conversion par minute.")
	var zero := PerformanceInsights.analyze({"family": "click", "metrics": {"hits_per_s": 0.0}})
	verify.call(zero.tempo_value == "0 cibles/min" and zero.measurements.hits_per_min.available, "Une cadence nulle mesurée reste distincte d’une mesure absente.")
	for unavailable_cadence in [null, -1.0, NAN, INF, 1e308, "1.4"]:
		var unavailable_metrics := {"hits_per_s": unavailable_cadence}
		var unavailable := PerformanceInsights.analyze({"family": "click", "metrics": unavailable_metrics})
		verify.call(unavailable.tempo_value == "—" and not unavailable.measurements.hits_per_min.available, "Une cadence absente ou invalide ne doit pas devenir une performance affichée.")
		verify.call(board.measurement_text({"family": "click", "metrics": unavailable_metrics}) == "Mesure indisponible", "La chronologie doit aussi refuser une cadence invalide.")
	var tracking := PerformanceInsights.analyze({"family": "tracking", "metrics": {"on_target_ratio": 0.75, "on_target_time_s": 6.0, "reacquisition_median_ms": 120.0, "reacquisition_samples": 1, "hits_per_s": 1.4}})
	verify.call(tracking.primary_value == "75,0 %" and tracking.tempo_value == "120 ms" and tracking.tempo_unit == "ms" and not tracking.measurements.hits_per_min.available, "Le suivi doit conserver pourcentage temporel et retour en millisecondes, sans cadence de clic.")
	board.free()


static func test_icon_actions(dashboard: AimDashboard, tree: SceneTree, verify: Callable) -> void:
	var controls: Array[Button] = [dashboard.conversion_copy_button, dashboard.history_refresh_button]
	for control in controls:
		verify.call(control.text.is_empty() and control.icon != null, "Les commandes évidentes doivent afficher uniquement leur icône.")
		verify.call(not control.tooltip_text.is_empty() and control.accessibility_name == control.tooltip_text and control.focus_mode == Control.FOCUS_ALL, "Chaque icône doit garder une infobulle, un nom accessible et le focus clavier.")
		var focus_style := control.get_theme_stylebox("focus") as StyleBoxFlat
		verify.call(focus_style != null and focus_style.border_width_left >= 2 and focus_style.border_color.a > 0.0, "Le focus des commandes doit rester visible.")
	var refresh_calls := {"count": 0}
	dashboard.history_requested.connect(func() -> void: refresh_calls.count += 1)
	dashboard.show_page(4)
	await settle(tree)
	var initial_calls: int = refresh_calls.count
	dashboard.history_refresh_button.grab_focus()
	push_key(tree.root, KEY_ENTER)
	await settle(tree)
	verify.call(refresh_calls.count == initial_calls + 1, "Entrée doit réellement activer l’icône Actualiser.")
	dashboard.show_page(3)
	await settle(tree)
	dashboard.conversion_copy_button.grab_focus()
	verify.call(dashboard.conversion_copy_button.has_focus(), "L’icône Copier doit recevoir le focus clavier.")
	for control in controls:
		verify.call(control.size.x >= 40.0 and control.size.y >= 40.0, "Les actions compactes conservent une surface de clic accessible.")


static func run_suite(tree: SceneTree, verify: Callable) -> void:
	var original_size := tree.root.size
	var original_motion := AimUI.motion_enabled
	AimUI.motion_enabled = false
	test_metrics(verify)
	await test_scroll_inputs(tree, verify)
	var dashboard := DashboardScript.new()
	dashboard.theme = InterfaceTheme
	tree.root.add_child(dashboard)
	await settle(tree)
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(800, 450)]:
		tree.root.size = dimensions
		await settle(tree)
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		for page_index in dashboard.pages.size():
			dashboard.show_page(page_index)
			await settle(tree)
			verify.call(dashboard.get_combined_minimum_size().x <= dimensions.x, "Le menu doit tenir horizontalement à %s, page %d." % [dimensions, page_index])
			verify.call(viewport_rect.encloses(dashboard.profile_badge.get_global_rect()), "La sensibilité et les DPI restent visibles à %s." % dimensions)
			if page_index == 1:
				verify_scroll(dashboard.browser.catalog_scroll, verify, "catalogue à %s" % dimensions)
				verify_scroll(dashboard.browser.detail_scroll, verify, "détail à %s" % dimensions)
				verify.call(viewport_rect.encloses(dashboard.browser.start_button.get_global_rect()), "Le lancement reste visible hors du défilement à %s." % dimensions)
				verify.call(dashboard.browser.grid.size.x <= dashboard.browser.catalog_scroll.size.x, "Le catalogue ne déborde pas de son défilement à %s." % dimensions)
			elif page_index == 2:
				verify_scroll(dashboard.pages[page_index] as ScrollContainer, verify, "sensibilité à %s" % dimensions)
				dashboard.guided_resume_button.show()
				dashboard.resume_calibration_button.show()
				await settle(tree)
				var calibration_content := dashboard.calibration_choices.get_parent() as VBoxContainer
				verify.call(calibration_content.get_theme_constant("separation") >= AimUI.SPACE_MD and dashboard.calibration_choices.get_global_rect().size.x <= dashboard.pages[2].size.x + 1.0, "Choix et formulaire partagent une colonne défilante correctement espacée à %s." % dimensions)
				verify.call(dashboard.pages[2].size.y >= 80.0, "Le formulaire conserve un défilement utilisable avec les reprises à %s." % dimensions)
				dashboard.progressive_resume_button.show()
				dashboard.progressive_resume_button.grab_focus()
				await settle(tree)
				verify.call(not dashboard.guided_resume_button.is_visible_in_tree() and not dashboard.resume_calibration_button.is_visible_in_tree() and (dashboard.pages[2] as ScrollContainer).get_global_rect().encloses(dashboard.progressive_resume_button.get_global_rect()), "Seule la reprise progressive est visible et révélée au focus à %s." % dimensions)
			else:
				var scroll := dashboard.pages[page_index] as ScrollContainer
				verify_scroll(scroll, verify, "page %d à %s" % [page_index, dimensions])
				verify.call(scroll.get_child(0).size.x + AimUI.SPACE_SM <= scroll.size.x + 1.0, "Le contenu laisse une marge devant le défilement à %s, page %d." % [dimensions, page_index])
		if dimensions.x == 800:
			verify.call(dashboard.home_grid.columns == 2, "L’accueil utilise deux cartes par ligne dans la petite fenêtre.")
		elif dimensions.x == 1920:
			verify.call(dashboard.browser.grid.columns >= 4, "Le catalogue utilise la largeur du grand écran.")
	var extreme := SensitivityService.default_profile()
	extreme.dpi = 64000.0
	extreme.cm_per_360 = 150.0
	dashboard.bind_profile(extreme)
	dashboard.show_page(2)
	await settle(tree)
	verify.call(dashboard.profile_badge.text.contains("<0,01"), "Une très petite sensibilité valide n’est pas présentée comme une valeur nulle.")
	var input := dashboard.sensitivity_input as SensitivityImport.ReadableSpinBox
	verify.call(input.display_input.text == "<0.01" and input.value > 0.0, "Le champ lisible signale sa limite d’arrondi sans changer le modèle.")
	var precise := input.value
	input.begin_edit()
	input.finish_edit()
	await settle(tree)
	verify.call(input.value == precise and dashboard.read_profile().cm_per_360 == 150.0, "Ouvrir/quitter une sensibilité inférieure au centième conserve sa distance canonique.")
	var coefficient := dashboard.reference_import.cs2_yaw_input
	coefficient.set_precise_value(0.0165)
	await settle(tree)
	verify.call(coefficient.display_input.text == "0.0165", "Le coefficient technique replié n’est pas une sensibilité et doit rester distinct de 0,022.")
	var precise_profile := SensitivityService.default_profile()
	precise_profile.cm_per_360 = 42.123456789123
	dashboard.bind_profile(precise_profile)
	var original_profile := dashboard.read_profile().duplicate(true)
	dashboard.sensitivity_input.begin_edit()
	dashboard.sensitivity_input.finish_edit()
	await settle(tree)
	verify.call(dashboard.read_profile() == original_profile and dashboard.current_distance_cm == precise_profile.cm_per_360, "Un champ abrégé à deux décimales doit conserver exactement la sensibilité canonique après focus et blur.")
	tree.root.size = Vector2i(1280, 720)
	await settle(tree)
	await test_icon_actions(dashboard, tree, verify)
	dashboard.queue_free()
	await settle(tree)
	var panel := SessionScript.new()
	panel.theme = InterfaceTheme
	tree.root.add_child(panel)
	await settle(tree)
	var domain := DomainTests.new()
	domain.verify = verify
	var calibration := domain.completed_calibration([30, 60, 30])
	var recommendation := calibration.recommendation()
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		panel.present_recommendation(recommendation, 800.0, "Mesures détaillées")
		await settle(tree)
		verify_scroll(panel.result_scroll, verify, "bilan à %s" % dimensions)
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		verify.call(viewport_rect.encloses(panel.apply_button.get_global_rect()) and viewport_rect.encloses(panel.refine_button.get_global_rect()), "Les actions du bilan restent visibles à %s." % dimensions)
		verify.call(panel.result_grid.size.x <= panel.result_scroll.size.x, "Le bilan utilise sa largeur sans déborder à %s." % dimensions)
		verify.call(panel.hero_label.text == AimUI.sensitivity(SensitivityService.game_sensitivity(800.0, recommendation.recommended_cm_per_360, SensitivityService.APP_YAW_DEG)), "Le conseil affiche deux décimales à %s." % dimensions)
		verify.call(panel.result_scroll.get_global_rect().end.y + AimUI.SPACE_MD <= panel.actions.get_global_rect().position.y, "Le bilan laisse une marge au-dessus des actions à %s." % dimensions)
		for stat_index in panel.stat_values.size():
			verify.call(panel.stat_titles[stat_index].get_global_rect().end.y + AimUI.SPACE_SM <= panel.stat_values[stat_index].get_global_rect().position.y, "La mesure %d sépare son titre et sa valeur à %s." % [stat_index, dimensions])
	panel.queue_free()
	await settle(tree)
	tree.root.size = original_size
	AimUI.motion_enabled = original_motion
