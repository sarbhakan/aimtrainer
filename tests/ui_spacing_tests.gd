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


static func run_suite(tree: SceneTree, verify: Callable) -> void:
	var original_size := tree.root.size
	var original_motion := AimUI.motion_enabled
	AimUI.motion_enabled = false
	var dashboard := DashboardScript.new()
	dashboard.theme = InterfaceTheme
	tree.root.add_child(dashboard)
	await settle(tree)
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		await settle(tree)
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		for page_index in dashboard.pages.size():
			dashboard.show_page(page_index)
			await settle(tree)
			verify.call(dashboard.get_combined_minimum_size().x <= dimensions.x, "Le menu doit tenir horizontalement à %s, page %d." % [dimensions, page_index])
			verify.call(viewport_rect.encloses(dashboard.profile_badge.get_global_rect()), "La sensibilité et les DPI restent visibles à %s." % dimensions)
			if page_index == 1:
				verify.call(viewport_rect.encloses(dashboard.browser.start_button.get_global_rect()), "Le lancement reste visible hors du défilement à %s." % dimensions)
				verify.call(dashboard.browser.grid.size.x <= dashboard.browser.catalog_scroll.size.x, "Le catalogue ne déborde pas de son défilement à %s." % dimensions)
			elif page_index == 2:
				dashboard.guided_resume_button.show()
				dashboard.resume_calibration_button.show()
				await settle(tree)
				var choices_bottom_px := dashboard.calibration_choices.get_global_rect().end.y
				verify.call(dashboard.pages[2].get_global_rect().position.y - choices_bottom_px >= AimUI.SPACE_MD, "Les choix et le formulaire sont séparés à %s." % dimensions)
				verify.call(dashboard.pages[2].size.y >= 80.0, "Le formulaire conserve un défilement utilisable avec les reprises à %s." % dimensions)
				verify.call(viewport_rect.encloses(dashboard.guided_resume_button.get_global_rect()) and viewport_rect.encloses(dashboard.resume_calibration_button.get_global_rect()), "Les reprises restent visibles à %s." % dimensions)
			else:
				var scroll := dashboard.pages[page_index] as ScrollContainer
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
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		panel.present_recommendation(recommendation, 800.0, "Mesures détaillées")
		await settle(tree)
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
