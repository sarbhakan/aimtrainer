extends RefCounted

const BrowserScript := preload("res://scripts/ui/training_browser.gd")
const DashboardScript := preload("res://scripts/ui/dashboard.gd")
const InterfaceTheme := preload("res://assets/ui_theme.tres")

var verify: Callable
var launched_id: String = ""
var launched_duration_s: float = 0.0


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func settle(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame


func wait_for_preview(tree: SceneTree) -> void:
	await tree.create_timer(BrowserScript.PREVIEW_DELAY_S + 0.06).timeout
	await settle(tree)


func settle_allocation(tree: SceneTree) -> void:
	await tree.create_timer(0.12).timeout
	await settle(tree)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await tree.process_frame


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var previous_motion_enabled: bool = AimUI.motion_enabled
	AimUI.motion_enabled = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var browser := BrowserScript.new()
	browser.theme = InterfaceTheme
	viewport.add_child(browser)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle(tree)
	browser.training_requested.connect(func(scenario_id: String, duration_s: float) -> void:
		launched_id = scenario_id
		launched_duration_s = duration_s)
	await test_hover(browser, tree)
	await test_click_and_focus(browser, tree)
	await test_dismissal(browser, tree)
	await test_motion(browser, tree)
	await test_layout(browser, viewport, tree)
	viewport.queue_free()
	await tree.process_frame
	await test_home(tree)
	AimUI.motion_enabled = previous_motion_enabled
	return true


func expect_contents(browser: TrainingBrowser, definition: ScenarioDefinition) -> void:
	var popup := browser.preview_popup
	expect(popup.visible and popup.definition == definition and popup.preview.definition == definition, "La bulle et sa démonstration doivent représenter l’ID demandé, pas la sélection précédente.")
	expect(popup.title_label.text == ScenarioCopy.title(definition) and popup.family_label.text == ScenarioCopy.family(definition), "La bulle doit présenter le titre et la famille de la carte consultée.")
	expect(popup.description_label.text == ScenarioCopy.description(definition) and popup.measure_label.text == ScenarioCopy.measure(definition), "La bulle doit expliquer l’action et la mesure du bon exercice.")


func test_hover(browser: TrainingBrowser, tree: SceneTree) -> void:
	var initial_id: String = browser.selected_definition.scenario_id
	var hovered := ScenarioCatalog.find("C03")
	var card: Button = browser.cards[hovered.scenario_id]
	card.mouse_entered.emit()
	expect(not browser.preview_popup.visible and not browser.preview_timer.is_stopped(), "Un survol bref doit attendre avant d’ouvrir la bulle.")
	await wait_for_preview(tree)
	expect_contents(browser, hovered)
	expect(browser.selected_definition.scenario_id == initial_id, "Consulter une carte au survol ne doit jamais sélectionner cet exercice.")
	browser.start_button.pressed.emit()
	expect(launched_id == initial_id, "Le lancement après un survol doit rester celui de la carte sélectionnée.")
	expect(browser.preview_popup.preview.is_processing() and not browser.preview.is_processing(), "Une seule démonstration doit s’animer, celle de la bulle ouverte.")
	for definition in ScenarioCatalog.DEFINITIONS:
		var thumbnail: ScenarioPreview = browser.cards[definition.scenario_id].get_child(0).get_child(0).get_child(0)
		expect(thumbnail.definition == definition and not thumbnail.is_processing(), "Les miniatures conservent leur structure et restent statiques.")
	card.mouse_exited.emit()
	expect(not browser.preview_popup.visible and not browser.preview_popup.preview.is_processing(), "Sortir de la carte doit masquer et arrêter la bulle.")
	expect(browser.preview.is_processing(), "La démonstration du détail peut reprendre quand la bulle est fermée.")
	card.mouse_entered.emit()
	card.mouse_exited.emit()
	await wait_for_preview(tree)
	expect(not browser.preview_popup.visible, "Un délai annulé ne doit pas ouvrir une bulle en retard.")
	card.mouse_entered.emit()
	var next_card: Button = browser.cards["T02"]
	next_card.mouse_entered.emit()
	card.mouse_exited.emit()
	await wait_for_preview(tree)
	expect_contents(browser, ScenarioCatalog.find("T02"))
	expect(browser.selected_definition.scenario_id == initial_id, "Un changement rapide de survol ne doit pas modifier la sélection.")
	next_card.mouse_exited.emit()
	for definition in ScenarioCatalog.DEFINITIONS:
		var current_card: Button = browser.cards[definition.scenario_id]
		current_card.mouse_entered.emit()
		browser.preview_timer.timeout.emit()
		await settle(tree)
		expect_contents(browser, definition)
		expect(browser.selected_definition.scenario_id == initial_id, "Chaque liaison de survol doit garder la sélection initiale.")
		current_card.mouse_exited.emit()


func test_click_and_focus(browser: TrainingBrowser, tree: SceneTree) -> void:
	for scenario_id in ["C02", "T01", "S02"]:
		var definition := ScenarioCatalog.find(scenario_id)
		var card: Button = browser.cards[scenario_id]
		card.pressed.emit()
		await settle(tree)
		expect_contents(browser, definition)
		expect(browser.selected_definition == definition and browser.preview.definition == definition and browser.title_label.text == ScenarioCopy.title(definition), "Après clic, carte, détail, bulle et sélection doivent être cohérents.")
		browser.duration_input.select(2)
		browser.start_button.pressed.emit()
		expect(launched_id == scenario_id and launched_duration_s == 15.0, "Le bouton doit lancer exactement l’exercice cliqué et la durée choisie.")
		browser.dismiss_card_preview()
	var selected_id: String = browser.selected_definition.scenario_id
	var focused: Button = browser.cards["C04"]
	focused.grab_focus()
	await wait_for_preview(tree)
	expect(focused.has_focus(), "Une carte doit être accessible au focus clavier.")
	expect_contents(browser, ScenarioCatalog.find("C04"))
	expect(browser.selected_definition.scenario_id == selected_id, "Le focus clavier consulte l’exercice sans le sélectionner.")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	browser._input(escape)
	expect(not browser.preview_popup.visible and browser.preview_timer.is_stopped(), "Échap doit fermer la bulle et annuler le délai.")
	browser.search_input.grab_focus()
	await settle(tree)
	expect(not browser.preview_popup.visible, "Quitter le focus d’une carte ne doit pas conserver sa bulle.")


func test_dismissal(browser: TrainingBrowser, tree: SceneTree) -> void:
	var card: Button = browser.cards["C03"]
	card.pressed.emit()
	browser.filter_buttons[2].pressed.emit()
	expect(not browser.preview_popup.visible and browser.preview_timer.is_stopped(), "Changer de famille doit fermer la bulle avant de filtrer.")
	browser.filter_buttons[0].pressed.emit()
	card.mouse_entered.emit()
	browser.search_input.text = "aucun-exercice-correspondant"
	browser.filter_catalog()
	await wait_for_preview(tree)
	expect(not browser.preview_popup.visible and browser.start_button.disabled, "La recherche doit annuler les aperçus des cartes retirées.")
	browser.search_input.clear()
	browser.filter_catalog()
	card.mouse_entered.emit()
	browser.hide()
	await wait_for_preview(tree)
	expect(not browser.preview_popup.visible and not browser.preview.is_processing(), "Une page masquée ne doit laisser ni bulle ni animation actives.")
	browser.show()
	await settle(tree)
	card.pressed.emit()
	browser.hide()
	expect(not browser.preview_popup.visible and not browser.preview_popup.preview.is_processing(), "Masquer la page doit fermer immédiatement une bulle déjà ouverte.")
	browser.show()
	await settle(tree)
	browser.show_card_preview(ScenarioCatalog.find("T04"))
	expect_contents(browser, ScenarioCatalog.find("T04"))
	browser.catalog_scroll.get_v_scroll_bar().value_changed.emit(1.0)
	expect(not browser.preview_popup.visible, "Faire défiler la bibliothèque doit fermer une bulle devenue mal ancrée.")


func test_motion(browser: TrainingBrowser, tree: SceneTree) -> void:
	AimUI.motion_enabled = false
	browser.show_card_preview(ScenarioCatalog.find("T05"))
	await settle(tree)
	expect_contents(browser, ScenarioCatalog.find("T05"))
	expect(not browser.preview.is_processing() and not browser.preview_popup.preview.is_processing(), "Animations réduites : la bulle reste lisible sans simulation animée.")
	browser.dismiss_card_preview()
	expect(not browser.preview.is_processing(), "Fermer la bulle ne doit pas contourner l’option animations réduites.")
	AimUI.motion_enabled = true
	browser.refresh_preview_animation()


func test_layout(browser: TrainingBrowser, viewport: SubViewport, tree: SceneTree) -> void:
	var anchor := Control.new()
	anchor.size = Vector2(96, 46)
	viewport.add_child(anchor)
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		await settle(tree)
		browser.update_layout()
		await settle(tree)
		expect(browser.get_combined_minimum_size().x <= dimensions.x, "La bibliothèque ne doit pas imposer un débordement horizontal à %s." % dimensions)
		expect(browser.grid.size.x <= browser.catalog_scroll.size.x + 1.0 and browser.catalog_scroll.scroll_horizontal == 0, "La grille doit tenir dans le catalogue sans défilement horizontal caché.")
		expect(browser.grid.columns >= 3 if dimensions.x >= 1280 else browser.grid.columns >= 1, "La grille doit utiliser trois ou quatre colonnes quand la largeur le permet.")
		expect(browser.detail_column.size.x >= 228.0 and browser.detail_column.size.x <= maxf(228.0, dimensions.x * 0.30) + 1.0, "Le détail doit garder une largeur confortable, proche de 30 %.")
		expect(browser.start_button.get_global_rect().end.y <= dimensions.y + 1.0 and browser.start_button.size.y >= 36.0, "Le bouton de lancement doit rester visible et assez grand, même à 800 × 450.")
		for corner in [Vector2.ZERO, Vector2(dimensions.x - 96, 0), Vector2(0, dimensions.y - 46), Vector2(dimensions.x - 96, dimensions.y - 46)]:
			anchor.position = corner
			for definition in ScenarioCatalog.DEFINITIONS:
				browser.show_card_preview(definition, anchor)
				await settle(tree)
				var popup_rect := browser.preview_popup.get_global_rect()
				expect(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(popup_rect), "La bulle %s doit rester dans le viewport %s, quel que soit le bord d’ancrage." % [definition.scenario_id, dimensions])
				expect(browser.preview_popup.get_combined_minimum_size().y <= browser.preview_popup.size.y + 1.0, "Tout le contenu de la bulle doit tenir dans sa hauteur.")
		browser.dismiss_card_preview()
	anchor.queue_free()


func expect_home_contents(dashboard: AimDashboard, definition: ScenarioDefinition) -> void:
	var popup := dashboard.home_preview_popup
	expect(popup.visible and popup.definition == definition and popup.preview.definition == definition, "La bulle d’accueil doit démontrer exactement la carte consultée.")
	expect(popup.title_label.text == ScenarioCopy.title(definition) and popup.description_label.text == ScenarioCopy.description(definition) and popup.measure_label.text == ScenarioCopy.measure(definition), "Le titre, la consigne et la mesure de l’accueil doivent correspondre au bon exercice.")


func test_home(tree: SceneTree) -> void:
	var viewport: Window = tree.root
	var original_size := viewport.size
	viewport.size = Vector2i(1280, 720)
	var dashboard := DashboardScript.new()
	dashboard.theme = InterfaceTheme
	viewport.add_child(dashboard)
	await settle_allocation(tree)
	expect(dashboard.home_cards.size() == 3, "Les trois cartes d’accueil doivent avoir des bulles dédiées.")
	var initial_id: String = dashboard.browser.selected_definition.scenario_id
	for scenario_id in ["C03", "T01", "C02"]:
		var definition := ScenarioCatalog.find(scenario_id)
		var card: Button = dashboard.home_cards[scenario_id]
		card.mouse_entered.emit()
		expect(not dashboard.home_preview_popup.visible and not dashboard.home_preview_timer.is_stopped(), "Les cartes d’accueil doivent attendre 180 ms avant d’ouvrir leur bulle.")
		await wait_for_preview(tree)
		expect_home_contents(dashboard, definition)
		expect(dashboard.selected_page == 0 and dashboard.browser.selected_definition.scenario_id == initial_id, "Le survol d’accueil ne doit ni naviguer ni modifier l’exercice sélectionné.")
		expect(dashboard.home_preview_popup.preview.is_processing() and not dashboard.hero_preview.is_processing() and not dashboard.browser.preview.is_processing(), "La bulle d’accueil doit être la seule démonstration animée.")
		card.mouse_exited.emit()
		expect(not dashboard.home_preview_popup.visible and not dashboard.home_preview_popup.preview.is_processing() and dashboard.hero_preview.is_processing(), "La sortie doit fermer la bulle et reprendre seulement le héros visible.")
	var focused: Button = dashboard.home_cards["C02"]
	focused.grab_focus()
	await wait_for_preview(tree)
	expect_home_contents(dashboard, ScenarioCatalog.find("C02"))
	expect(dashboard.browser.selected_definition.scenario_id == initial_id, "Le focus clavier d’accueil ne doit pas sélectionner l’exercice.")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	dashboard._input(escape)
	expect(not dashboard.home_preview_popup.visible and dashboard.home_preview_timer.is_stopped(), "Échap doit fermer la bulle d’accueil sans naviguer.")
	dashboard.nav_buttons[0].grab_focus()
	var first: Button = dashboard.home_cards["C03"]
	first.mouse_entered.emit()
	dashboard.show_page(2)
	await wait_for_preview(tree)
	expect(not dashboard.home_preview_popup.visible and dashboard.home_preview_timer.is_stopped(), "Changer de page doit annuler un survol d’accueil en attente.")
	dashboard.show_page(0)
	first.mouse_entered.emit()
	await wait_for_preview(tree)
	dashboard.home_scroll.get_v_scroll_bar().value_changed.emit(1.0)
	expect(not dashboard.home_preview_popup.visible and not dashboard.home_preview_popup.preview.is_processing(), "Faire défiler l’accueil doit fermer sa bulle.")
	first.mouse_entered.emit()
	await wait_for_preview(tree)
	dashboard.hide()
	expect(not dashboard.home_preview_popup.visible and not dashboard.hero_preview.is_processing(), "Masquer le dashboard doit nettoyer la bulle et les animations d’accueil.")
	dashboard.show()
	await settle(tree)
	for scenario_id in ["C03", "T01", "C02"]:
		dashboard.show_page(0)
		var card: Button = dashboard.home_cards[scenario_id]
		dashboard.show_home_preview(ScenarioCatalog.find(scenario_id), card)
		card.pressed.emit()
		await settle(tree)
		expect(dashboard.selected_page == 1 and dashboard.browser.selected_definition.scenario_id == scenario_id, "Cliquer une carte d’accueil doit sélectionner le bon exercice dans la bibliothèque.")
		expect_contents(dashboard.browser, ScenarioCatalog.find(scenario_id))
		expect(not dashboard.home_preview_popup.visible and not dashboard.hero_preview.is_processing() and not dashboard.browser.preview.is_processing(), "La navigation par clic doit transférer l’aperçu sans laisser deux animations.")
	dashboard.show_page(0)
	var profile := SensitivityService.default_profile()
	profile.reduced_motion = true
	dashboard.bind_profile(profile)
	dashboard.show_home_preview(ScenarioCatalog.find("T01"), dashboard.home_cards["T01"])
	await settle(tree)
	expect_home_contents(dashboard, ScenarioCatalog.find("T01"))
	expect(not dashboard.home_preview_popup.preview.is_processing() and not dashboard.hero_preview.is_processing(), "Le profil animations réduites doit aussi s’appliquer aux bulles d’accueil.")
	profile.reduced_motion = false
	dashboard.bind_profile(profile)
	expect(dashboard.home_preview_popup.preview.is_processing() and not dashboard.hero_preview.is_processing(), "Réactiver les animations ne doit pas relancer le héros derrière une bulle.")
	dashboard.dismiss_home_preview()
	expect(dashboard.hero_preview.is_processing(), "Fermer la bulle doit reprendre le héros quand le profil autorise l’animation.")
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		await settle_allocation(tree)
		for scenario_id in ["C03", "T01", "C02"]:
			dashboard.show_home_preview(ScenarioCatalog.find(scenario_id), dashboard.home_cards[scenario_id])
			await settle_allocation(tree)
			expect(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(dashboard.home_preview_popup.get_global_rect()), "La bulle d’accueil %s doit rester dans le viewport %s." % [scenario_id, dimensions])
			dashboard.dismiss_home_preview()
	await test_root_allocation(dashboard, tree)
	dashboard.queue_free()
	await tree.process_frame
	viewport.size = original_size


func test_root_allocation(dashboard: AimDashboard, tree: SceneTree) -> void:
	dashboard.show_page(1)
	var browser: TrainingBrowser = dashboard.browser
	expect(not browser.preview_popup.get_parent() is Container, "La bulle flottante ne doit jamais être un enfant direct d’un conteneur de mise en page.")
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 450), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		tree.root.size = dimensions
		await settle_allocation(tree)
		var available_rect := (browser.get_parent() as Control).get_global_rect().intersection(tree.root.get_visible_rect())
		expect(available_rect.grow(1.0).encloses(browser.start_button.get_global_rect()), "Le lancement doit rester entièrement visible après allocation réelle à %s : bouton %s, navigateur %s." % [dimensions, browser.start_button.get_global_rect(), browser.get_global_rect()])
		var minimum_before := browser.get_combined_minimum_size()
		var catalog_before := browser.catalog_scroll.get_global_rect()
		browser.show_card_preview(ScenarioCatalog.find("C02"))
		await settle_allocation(tree)
		expect(browser.preview_popup.visible and tree.root.get_visible_rect().encloses(browser.preview_popup.get_global_rect()), "Après allocation réelle des frames, la bulle C02 doit rester dans la fenêtre %s." % dimensions)
		expect(absf(browser.preview_popup.size.y - browser.preview_popup.get_combined_minimum_size().y) <= 1.0, "La bulle doit retrouver sa hauteur naturelle après le retour à la ligne, sans garder une hauteur initiale surdimensionnée.")
		expect(browser.get_combined_minimum_size().is_equal_approx(minimum_before), "Afficher une bulle ne doit pas agrandir la taille minimale du navigateur.")
		expect(browser.catalog_scroll.get_global_rect().is_equal_approx(catalog_before), "Afficher une bulle ne doit pas ajouter une barre ni déplacer le catalogue.")
		browser.dismiss_card_preview()
