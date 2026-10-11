extends RefCounted

const BrowserScript := preload("res://scripts/ui/training_browser.gd")
const InterfaceTheme := preload("res://assets/ui_theme.tres")
const FeedbackScript := preload("res://scripts/ui/interaction_feedback.gd")

var verify: Callable
var launched_id: String = ""
var launched_duration_s: float = 0.0


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func settle(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame


func key(viewport: Viewport, keycode: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.pressed = pressed
		viewport.push_input(event, true)


func move_mouse(viewport: Viewport, position_px: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position_px
	event.global_position = position_px
	event.relative = Vector2(1.0, 0.0)
	viewport.push_input(event, true)


func mouse_button(viewport: Viewport, position_px: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position_px
	event.global_position = position_px
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	viewport.push_input(event, true)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var previous_motion: bool = AimUI.motion_enabled
	AimUI.motion_enabled = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	await test_feedback(viewport, tree)
	var browser := BrowserScript.new()
	browser.theme = InterfaceTheme
	viewport.add_child(browser)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.training_requested.connect(func(scenario_id: String, duration_s: float) -> void:
		launched_id = scenario_id
		launched_duration_s = duration_s)
	await settle(tree)
	await test_selection(browser, viewport, tree)
	await test_keyboard(browser, viewport, tree)
	await test_preview_lifecycle(browser, viewport, tree)
	viewport.queue_free()
	await tree.process_frame
	AimUI.motion_enabled = previous_motion
	return true


func test_feedback(viewport: SubViewport, tree: SceneTree) -> void:
	var previous_instances: int = FeedbackScript.instances.size()
	var host := VBoxContainer.new()
	host.theme = InterfaceTheme
	host.position = Vector2(40.0, 40.0)
	viewport.add_child(host)
	var control := AimUI.button("Action", func() -> void: pass, true)
	host.add_child(control)
	await settle(tree)
	var feedback := AimUI.feedback(control)
	expect(feedback == AimUI.feedback(control), "Un contrôle doit réutiliser un seul retour d’interaction.")
	expect(not feedback.is_processing(), "Le retour d’interaction ne doit pas ajouter de traitement par frame permanent.")
	var initial_rect := control.get_global_rect()
	var initial_minimum := host.get_combined_minimum_size()
	move_mouse(viewport, initial_rect.get_center())
	expect(feedback.hovered and feedback.interaction_tween != null, "L’entrée réelle du pointeur doit déclencher le retour de survol.")
	var hover_tween := feedback.interaction_tween
	for event_index in 80:
		move_mouse(viewport, initial_rect.get_center() + Vector2(float(event_index % 2), 0.0))
	expect(feedback.interaction_tween == hover_tween, "Bouger dans le même bouton ne doit jamais créer un nouveau tween.")
	mouse_button(viewport, initial_rect.get_center(), true)
	expect(feedback.held and feedback.interaction_tween != hover_tween, "La pression réelle doit remplacer le retour de survol.")
	mouse_button(viewport, initial_rect.get_center(), false)
	expect(not feedback.held, "Le relâchement doit quitter l’état maintenu.")
	await tree.create_timer(0.16).timeout
	expect(control.get_global_rect().is_equal_approx(initial_rect) and host.get_combined_minimum_size().is_equal_approx(initial_minimum), "Survol, focus et pression ne doivent changer ni géométrie ni taille minimale.")
	AimUI.fade_in(host)
	var host_feedback := AimUI.feedback(host)
	var old_fade := host_feedback.fade_tween
	AimUI.fade_in(host)
	expect(not old_fade.is_valid() and host_feedback.fade_tween != old_fade, "Une nouvelle entrée doit arrêter le fondu précédent.")
	control.button_down.emit()
	AimUI.motion_enabled = false
	expect(host_feedback.fade_tween == null and is_equal_approx(host.modulate.a, 1.0), "Animations réduites doit terminer immédiatement un fondu déjà lancé.")
	expect(feedback.interaction_tween == null and control.self_modulate.is_equal_approx(feedback.target_tint), "Animations réduites doit arrêter et stabiliser un retour déjà lancé.")
	control.button_up.emit()
	control.mouse_exited.emit()
	expect(feedback.interaction_tween == null, "Les interactions réduites doivent rester instantanées sans nouveau tween.")
	AimUI.fade_in(host)
	expect(host_feedback.fade_tween == null and is_equal_approx(host.modulate.a, 1.0), "Un fondu demandé en animations réduites doit rester lisible immédiatement.")
	AimUI.motion_enabled = true
	AimUI.fade_in(host)
	control.button_down.emit()
	var hidden_fade := host_feedback.fade_tween
	var hidden_interaction := feedback.interaction_tween
	host.hide()
	expect(not hidden_fade.is_valid() and not hidden_interaction.is_valid(), "Masquer un ancêtre doit tuer les tweens de ses descendants.")
	expect(host_feedback.fade_tween == null and feedback.interaction_tween == null and control.self_modulate == feedback.resting_tint, "Les contrôles masqués doivent retrouver un état neutre.")
	host.queue_free()
	await tree.process_frame
	expect(FeedbackScript.instances.size() == previous_instances, "Libérer les contrôles doit retirer leurs observateurs de mouvement.")


func test_selection(browser: TrainingBrowser, viewport: SubViewport, tree: SceneTree) -> void:
	var selected: Button = browser.cards["C03"]
	browser.select_definition(ScenarioCatalog.find("C03"))
	await settle(tree)
	var minimum := browser.get_combined_minimum_size()
	var selected_rect := selected.get_global_rect()
	move_mouse(viewport, selected_rect.get_center())
	expect(selected.button_pressed and selected.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED, "Le survol d’une carte sélectionnée doit conserver son état natif sélectionné.")
	var selected_hover := selected.get_theme_stylebox("hover_pressed") as StyleBoxFlat
	var plain_hover := selected.get_theme_stylebox("hover") as StyleBoxFlat
	expect(selected_hover.border_color == AimUI.ACCENT and selected_hover.bg_color != plain_hover.bg_color, "La carte sélectionnée doit rester identifiable pendant le survol.")
	var focused: Button = browser.cards["C02"]
	focused.grab_focus()
	await settle(tree)
	expect(browser.selected_definition.scenario_id == "C03" and selected.button_pressed and not focused.button_pressed, "Le focus clavier doit consulter sans déplacer la sélection.")
	key(viewport, KEY_SPACE)
	await settle(tree)
	expect(browser.selected_definition.scenario_id == "C02" and focused.button_pressed and not selected.button_pressed, "Espace doit sélectionner exactement la carte focalisée.")
	var selected_count: int = 0
	for control: Button in browser.cards.values():
		if control.button_pressed:
			selected_count += 1
	expect(selected_count == 1, "La bibliothèque doit toujours garder une seule carte sélectionnée.")
	browser.duration_input.select(2)
	browser.start_button.pressed.emit()
	expect(launched_id == "C02" and launched_duration_s == 15.0, "Le lancement doit conserver l’ID sélectionné et la durée choisie.")
	expect(browser.get_combined_minimum_size().is_equal_approx(minimum) and selected.get_global_rect().is_equal_approx(selected_rect), "La sélection et son fondu ne doivent jamais déplacer les cartes.")
	browser.dismiss_card_preview()
	var detail_feedback := AimUI.feedback(browser.detail_scroll)
	var previous_fade := detail_feedback.fade_tween
	browser.preview.elapsed_s = 0.42
	browser.select_definition(browser.selected_definition)
	var previous_measure := browser.measure_label.text
	browser.measure_label.text = "42"
	expect(detail_feedback.fade_tween == previous_fade and is_equal_approx(browser.preview.elapsed_s, 0.42), "Rafraîchir la même sélection ou une mesure ne doit relancer ni fondu ni démonstration.")
	browser.measure_label.text = previous_measure
	move_mouse(viewport, Vector2(1275.0, 715.0))


func test_keyboard(browser: TrainingBrowser, viewport: SubViewport, tree: SceneTree) -> void:
	browser.filter_buttons[2].pressed.emit()
	await settle(tree)
	expect(browser.filter_buttons[2].button_pressed and not browser.filter_buttons[0].button_pressed, "Le filtre actif doit utiliser une sélection native exclusive.")
	browser.search_input.grab_focus()
	key(viewport, KEY_TAB)
	await settle(tree)
	var first: Button = browser.cards["T01"]
	var second: Button = browser.cards["T02"]
	expect(first.has_focus(), "Tab depuis la recherche doit rejoindre la première carte visible après filtrage.")
	key(viewport, KEY_RIGHT)
	await settle(tree)
	expect(second.has_focus(), "Flèche droite doit rejoindre la carte suivante visible.")
	key(viewport, KEY_TAB, true)
	await settle(tree)
	expect(first.has_focus(), "Maj+Tab doit revenir sur la carte visible précédente.")
	var selected_id: String = browser.selected_definition.scenario_id
	first.mouse_exited.emit()
	browser.preview_timer.timeout.emit()
	expect(browser.preview_popup.visible and browser.preview_popup.anchor == first, "La sortie du pointeur ne doit pas annuler l’aperçu d’une carte encore focalisée.")
	key(viewport, KEY_ESCAPE)
	await settle(tree)
	expect(not browser.preview_popup.visible and browser.preview_timer.is_stopped() and browser.selected_definition.scenario_id == selected_id, "Échap doit fermer l’aperçu clavier sans sélectionner ni naviguer.")
	browser.search_input.text = "aucun-exercice-correspondant"
	browser.filter_catalog()
	browser.search_input.grab_focus()
	key(viewport, KEY_TAB)
	await settle(tree)
	expect(browser.duration_input.has_focus() and browser.start_button.disabled and not browser.preview.is_processing(), "Sans résultat, Tab doit sortir de la recherche et arrêter la démonstration obsolète.")
	browser.search_input.clear()
	browser.filter_buttons[0].pressed.emit()
	browser.search_input.grab_focus()


func test_preview_lifecycle(browser: TrainingBrowser, viewport: SubViewport, tree: SceneTree) -> void:
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		await tree.create_timer(0.12).timeout
		await settle(tree)
		var minimum := browser.get_combined_minimum_size()
		var catalog_rect := browser.catalog_scroll.get_global_rect()
		expect(minimum.x <= dimensions.x and browser.grid.size.x <= browser.catalog_scroll.size.x + 1.0, "Le catalogue doit tenir sans débordement à %s." % dimensions)
		expect(browser.start_button.get_global_rect().end.y <= dimensions.y + 1.0 and browser.start_button.size.y >= 36.0, "Le lancement doit rester visible et utilisable à %s." % dimensions)
		var selected_id: String = browser.selected_definition.scenario_id
		browser.search_input.grab_focus()
		key(viewport, KEY_TAB)
		await settle(tree)
		var first: Button = browser.cards[ScenarioCatalog.DEFINITIONS[0].scenario_id]
		expect(first.has_focus(), "Tab doit rejoindre la première carte à %s." % dimensions)
		key(viewport, KEY_DOWN)
		await settle(tree)
		var below: Button = browser.cards[ScenarioCatalog.DEFINITIONS[browser.grid.columns].scenario_id]
		expect(below.has_focus() and browser.selected_definition.scenario_id == selected_id, "Flèche bas doit suivre la colonne sans sélectionner à %s." % dimensions)
		key(viewport, KEY_UP)
		await settle(tree)
		expect(first.has_focus() and browser.selected_definition.scenario_id == selected_id, "Flèche haut doit revenir dans la même colonne à %s." % dimensions)
		first.release_focus()
		browser.dismiss_card_preview()
		for definition in ScenarioCatalog.DEFINITIONS:
			browser.show_card_preview(definition)
			await settle(tree)
			expect(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(browser.preview_popup.get_global_rect()), "L’aperçu %s doit tenir dans %s." % [definition.scenario_id, dimensions])
			expect(not browser.preview.is_processing() and browser.preview_popup.preview.is_processing(), "Une bulle visible doit être la seule démonstration animée.")
			expect(browser.get_combined_minimum_size().is_equal_approx(minimum) and browser.catalog_scroll.get_global_rect().is_equal_approx(catalog_rect), "Présenter un aperçu ne doit pas provoquer de reflow.")
		AimUI.motion_enabled = false
		expect(not browser.preview_popup.preview.is_processing() and not browser.preview.is_processing(), "Changer les préférences doit arrêter immédiatement la démonstration déjà visible.")
		expect(AimUI.feedback(browser.preview_popup).fade_tween == null and is_equal_approx(browser.preview_popup.modulate.a, 1.0), "Changer les préférences doit aussi terminer le fondu de la bulle.")
		AimUI.motion_enabled = true
		expect(browser.preview_popup.preview.is_processing() and not browser.preview.is_processing(), "Réactiver le mouvement doit reprendre seulement l’aperçu visible.")
		browser.hide()
		expect(not browser.preview_popup.visible and not browser.preview.is_processing() and not browser.preview_popup.preview.is_processing() and browser.preview_timer.is_stopped(), "Masquer la page doit arrêter la bulle, son délai et toutes les démonstrations.")
		browser.show()
		await settle(tree)
		var detail_processing := browser.preview.is_processing()
		expect(detail_processing == browser.preview.is_visible_in_tree(), "Le détail doit reprendre seulement lorsqu’il est visible à la taille courante.")
