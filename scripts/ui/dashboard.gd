class_name AimDashboard
extends Control

signal calibration_requested
signal calibration_resume_requested
signal training_requested(scenario_id: String, duration_s: float)
signal profile_save_requested
signal reference_import_requested(profile: Dictionary)
signal history_requested
signal export_requested
signal test_requested
signal quit_requested

const PAGE_TITLES: Array[String] = ["Accueil", "Entraînement", "Ma sensibilité", "Conversion", "Progression", "Réglages"]
const NAV_ICONS: Array[Texture2D] = [preload("res://assets/ui/home.svg"), preload("res://assets/ui/train.svg"), preload("res://assets/ui/sensitivity.svg"), preload("res://assets/ui/convert.svg"), preload("res://assets/ui/progress.svg"), preload("res://assets/ui/settings.svg")]
const HomePreviewPopupScript := preload("res://scripts/ui/exercise_preview_popup.gd")

var dpi_input: SpinBox
var distance_input: SpinBox
var sensitivity_input: SpinBox
var fov_input: SpinBox
var goal_input: OptionButton
var fps_input: OptionButton
var accumulated_input: CheckButton
var inverted_input: CheckButton
var duration_input: OptionButton
var game_input: OptionButton
var destination_dpi: SpinBox
var yaw_input: SpinBox
var test_button: Button
var quit_button: Button
var calibration_button: Button
var resume_calibration_button: Button
var status_label: Label
var conversion_label: Label
var conversion_value: float = 0.0
var browser: TrainingBrowser
var pages: Array[Control] = []
var nav_buttons: Array[Button] = []
var selected_page: int = 0
var sidebar: PanelContainer
var content_margin: MarginContainer
var brand_label: Label
var local_label: Label
var page_title: Label
var profile_badge: Button
var save_button: Button
var page_host: VBoxContainer
var home_grid: GridContainer
var hero_preview: ScenarioPreview
var home_cards: Dictionary = {}
var home_preview_popup: HomePreviewPopupScript
var home_preview_timer: Timer
var home_preview_definition: ScenarioDefinition
var home_preview_anchor: Control
var home_scroll: ScrollContainer
var settings_preview_grid: GridContainer
var conversion_details: Label
var history_content: VBoxContainer
var history_summary: Label
var preset_buttons: Array[Button] = []
var start_help_label: Label
var weapon_buttons: Array[Button] = []
var weapon_id: String = "pulse"
var weapon_preview: WeaponFeedback
var weapon_title: Label
var sound_input: CheckButton
var weapon_visible_input: CheckButton
var motion_input: CheckButton
var volume_input: HSlider
var syncing_sensitivity: bool = false
var current_distance_cm: float = 35.0
var reference_game: Dictionary = {}
var reference_import: SensitivityImport
var calibration_grid: GridContainer
var protocol_grid: GridContainer
var conversion_copy_button: Button
var conversion_reference_label: Label
var destination_yaw_deg: float = 0.022


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AimUI.backdrop(self)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	build_sidebar(layout)
	var margin := MarginContainer.new()
	content_margin = margin
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 26)
	layout.add_child(margin)
	var content := AimUI.column(margin, 20)
	var header := AimUI.row(content)
	var heading := AimUI.column(header, 4)
	heading.add_child(AimUI.label("VOTRE ESPACE", 10, AimUI.MUTED))
	page_title = AimUI.label("Accueil", 27)
	heading.add_child(page_title)
	save_button = AimUI.button("Enregistrer", func() -> void: profile_save_requested.emit(), true)
	save_button.hide()
	header.add_child(save_button)
	profile_badge = AimUI.button("", func() -> void: show_page(2))
	profile_badge.tooltip_text = "Votre souris et votre sensibilité"
	header.add_child(profile_badge)
	page_host = AimUI.column(content, 0)
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_home(page("Accueil"))
	browser = TrainingBrowser.new()
	page_host.add_child(browser)
	pages.append(browser)
	browser.training_requested.connect(func(scenario_id: String, seconds: float) -> void: training_requested.emit(scenario_id, seconds))
	duration_input = browser.duration_input
	build_calibration(page("Calibration"))
	build_conversion(page("Conversion"))
	build_history(page("Progression"))
	build_settings(page("Réglages"))
	status_label = AimUI.label("", 13, AimUI.ACCENT)
	status_label.hide()
	content.add_child(status_label)
	dpi_input.value_changed.connect(func(_value: float) -> void: sync_sensitivity())
	distance_input.value_changed.connect(func(value: float) -> void:
		if not syncing_sensitivity:
			current_distance_cm = value
			sync_sensitivity())
	sensitivity_input.value_changed.connect(change_app_sensitivity)
	bind_profile(SensitivityService.default_profile())
	resized.connect(update_layout)
	show_page(0)
	update_layout.call_deferred()


func build_sidebar(parent: Node) -> void:
	sidebar = PanelContainer.new()
	sidebar.custom_minimum_size.x = 196.0
	sidebar.add_theme_stylebox_override("panel", AimUI.style(Color("0c1120"), 16, Color("192336"), 0))
	parent.add_child(sidebar)
	var content := AimUI.column(sidebar, 8)
	var brand := AimUI.row(content, 10)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/ui/logo.svg")
	logo.custom_minimum_size = Vector2(32, 32)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(logo)
	brand_label = AimUI.label("AIM/LOCAL", 17)
	brand_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.add_child(brand_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 34.0
	content.add_child(gap)
	for page_index in PAGE_TITLES.size():
		var control := AimUI.button(PAGE_TITLES[page_index], func() -> void: show_page(page_index))
		control.icon = NAV_ICONS[page_index]
		control.alignment = HORIZONTAL_ALIGNMENT_LEFT
		control.tooltip_text = PAGE_TITLES[page_index]
		control.toggle_mode = true
		control.add_theme_stylebox_override("normal", AimUI.style(Color.TRANSPARENT, 10, Color.TRANSPARENT, 8))
		control.add_theme_stylebox_override("pressed", AimUI.style(Color("173237"), 10, Color("245456"), 8))
		nav_buttons.append(control)
		content.add_child(control)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(space)
	local_label = AimUI.label("●  LOCAL · HORS LIGNE", 10, AimUI.MUTED)
	content.add_child(local_label)
	quit_button = AimUI.button("Quitter", func() -> void: quit_requested.emit())
	quit_button.tooltip_text = "Quitter AIM/LOCAL"
	content.add_child(quit_button)


func page(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_host.add_child(scroll)
	pages.append(scroll)
	return AimUI.column(scroll, 18)


func show_page(page_index: int) -> void:
	dismiss_home_preview()
	selected_page = page_index
	page_title.text = PAGE_TITLES[page_index]
	save_button.visible = page_index in [2, 5]
	for index in pages.size():
		pages[index].visible = index == page_index
		nav_buttons[index].set_pressed_no_signal(index == page_index)
	AimUI.fade_in(pages[page_index])
	nav_buttons[page_index].grab_focus()
	if page_index == 4:
		history_requested.emit()


func build_home(content: VBoxContainer) -> void:
	var hero := AimUI.card(content, 28)
	var layout := AimUI.row(hero, 24)
	var introduction := AimUI.column(layout, 16)
	introduction.add_child(AimUI.label("PRENEZ LE TEMPS DE PROGRESSER", 10, AimUI.ACCENT))
	introduction.add_child(AimUI.label("Visez juste.\nProgressez vraiment.", 36))
	introduction.add_child(AimUI.label("Votre souris. Votre rythme. Votre entraînement.", 15, AimUI.MUTED))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	introduction.add_child(actions)
	actions.add_child(AimUI.button("S’entraîner  →", func() -> void: show_page(1), true))
	actions.add_child(AimUI.button("Régler ma sensibilité", func() -> void: show_page(2)))
	var preview := ScenarioPreview.new()
	hero_preview = preview
	preview.custom_minimum_size = Vector2(230, 210)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview)
	preview.configure(ScenarioCatalog.find("C03"), true)
	content.add_child(AimUI.label("Pour commencer", 18))
	home_grid = GridContainer.new()
	home_grid.columns = 3
	home_grid.add_theme_constant_override("h_separation", 14)
	home_grid.add_theme_constant_override("v_separation", 14)
	content.add_child(home_grid)
	for scenario_id in ["C03", "T01", "C02"]:
		var definition := ScenarioCatalog.find(scenario_id)
		var control := TrainingBrowser.scenario_card(definition, func() -> void:
			browser.selected_family = "all"
			browser.search_input.clear()
			browser.filter_catalog()
			browser.select_definition(definition)
			show_page(1)
			browser.show_card_preview(definition))
		home_grid.add_child(control)
		home_cards[scenario_id] = control
		control.mouse_entered.connect(func() -> void: schedule_home_preview(definition, control))
		control.focus_entered.connect(func() -> void: schedule_home_preview(definition, control))
		control.mouse_exited.connect(func() -> void: dismiss_home_preview(control))
		control.focus_exited.connect(func() -> void: dismiss_home_preview(control))
	var reminder := AimUI.row(content)
	var copy := AimUI.label("Une bonne sensibilité commence par un réglage confortable.", 14, AimUI.MUTED)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reminder.add_child(copy)
	reminder.add_child(AimUI.button("Trouver mon réglage", func() -> void: show_page(2)))
	home_preview_popup = HomePreviewPopupScript.new()
	add_child(home_preview_popup)
	home_preview_popup.visibility_changed.connect(refresh_home_preview_animation)
	home_preview_timer = Timer.new()
	home_preview_timer.one_shot = true
	home_preview_timer.wait_time = TrainingBrowser.PREVIEW_DELAY_S
	home_preview_timer.timeout.connect(show_pending_home_preview)
	add_child(home_preview_timer)
	home_scroll = content.get_parent() as ScrollContainer
	home_scroll.follow_focus = true
	home_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: dismiss_home_preview())
	home_scroll.visibility_changed.connect(home_visibility_changed)
	visibility_changed.connect(home_visibility_changed)


func schedule_home_preview(definition: ScenarioDefinition, anchor: Control) -> void:
	if selected_page != 0 or not is_visible_in_tree() or not anchor.is_visible_in_tree():
		return
	dismiss_home_preview()
	if anchor.has_focus():
		home_scroll.ensure_control_visible(anchor)
	home_preview_definition = definition
	home_preview_anchor = anchor
	home_preview_timer.start()


func show_pending_home_preview() -> void:
	if home_preview_definition != null and is_instance_valid(home_preview_anchor):
		show_home_preview(home_preview_definition, home_preview_anchor)


func show_home_preview(definition: ScenarioDefinition, anchor: Control) -> void:
	home_preview_timer.stop()
	home_preview_definition = null
	home_preview_anchor = null
	if selected_page != 0 or not is_visible_in_tree() or not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
		dismiss_home_preview()
		return
	hero_preview.animated = false
	hero_preview.set_process(false)
	home_preview_popup.present(definition, anchor)


func dismiss_home_preview(anchor: Control = null) -> void:
	if home_preview_popup == null or home_preview_timer == null:
		return
	if anchor != null and anchor != home_preview_anchor and anchor != home_preview_popup.anchor:
		return
	home_preview_timer.stop()
	home_preview_definition = null
	home_preview_anchor = null
	home_preview_popup.dismiss()
	refresh_home_preview_animation()


func refresh_home_preview_animation() -> void:
	if hero_preview == null:
		return
	hero_preview.animated = home_preview_popup == null or not home_preview_popup.visible
	hero_preview.set_process(hero_preview.animated and hero_preview.is_visible_in_tree() and AimUI.motion_enabled)


func home_visibility_changed() -> void:
	if not is_visible_in_tree() or not home_scroll.is_visible_in_tree():
		dismiss_home_preview()
	refresh_home_preview_animation()


func _input(event: InputEvent) -> void:
	if selected_page == 0 and is_visible_in_tree() and event.is_action_pressed("ui_cancel") and (home_preview_popup.visible or not home_preview_timer.is_stopped()):
		dismiss_home_preview()
		get_viewport().set_input_as_handled()


func build_calibration(content: VBoxContainer) -> void:
	content.add_child(AimUI.label("Réglez AIM/LOCAL ou importez votre jeu avant de comparer les sensibilités.", 15, AimUI.MUTED))
	var actions := AimUI.row(content, 12)
	calibration_button = AimUI.button("Comparer mes sensibilités  →", func() -> void: calibration_requested.emit(), true)
	actions.add_child(calibration_button)
	resume_calibration_button = AimUI.button("Reprendre", func() -> void: calibration_resume_requested.emit())
	resume_calibration_button.hide()
	actions.add_child(resume_calibration_button)
	content.add_child(AimUI.label("Test complet : environ 16 min · pauses et reprise possibles", 13, AimUI.MUTED))
	calibration_grid = GridContainer.new()
	calibration_grid.columns = 2
	calibration_grid.add_theme_constant_override("h_separation", 18)
	calibration_grid.add_theme_constant_override("v_separation", 18)
	content.add_child(calibration_grid)
	var setup := AimUI.card(calibration_grid)
	setup.add_child(AimUI.label("Sensibilité active dans AIM/LOCAL", 20))
	sensitivity_input = AimUI.numeric(setup, "Sensibilité", 0.000001, 100000.0, 0.000001)
	sensitivity_input.tooltip_text = "Plus grand = rotation plus rapide. Ce nombre est propre à AIM/LOCAL."
	setup.add_child(AimUI.label("Actif au prochain exercice. Enregistrez pour le conserver.", 13, AimUI.MUTED))
	dpi_input = AimUI.numeric(setup, "DPI actuels de la souris", 1, 64000, 1)
	dpi_input.tooltip_text = "Recopiez les DPI indiqués dans le logiciel de votre souris. AIM/LOCAL ne les détecte pas."
	var goal_row := AimUI.row(setup)
	var goal_label := AimUI.label("Votre priorité")
	goal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_row.add_child(goal_label)
	goal_input = OptionButton.new()
	for caption in ["Polyvalent", "Précision", "Suivi"]:
		goal_input.add_item(caption)
	goal_input.custom_minimum_size.x = 150.0
	goal_row.add_child(goal_input)
	setup.add_child(AimUI.label("Point de départ", 14))
	var presets := AimUI.row(setup, 8)
	for preset_index in 3:
		var control := AimUI.button(["Plus lent", "Équilibré", "Plus rapide"][preset_index], func() -> void:
			distance_input.value = [50.0, 35.0, 25.0][preset_index])
		control.toggle_mode = true
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(control)
		preset_buttons.append(control)
	start_help_label = AimUI.label("Le test ajuste la sensibilité pour vous. Gardez les mêmes DPI.", 13, AimUI.MUTED)
	setup.add_child(start_help_label)
	var import_card := AimUI.card(calibration_grid)
	reference_import = SensitivityImport.new()
	import_card.add_child(reference_import)
	reference_import.profile_requested.connect(func(profile: Dictionary) -> void:
		var applied := read_profile()
		for field in ["cm_per_360", "reference_game"]:
			applied[field] = profile[field]
		reference_import_requested.emit(applied))
	content.add_child(AimUI.label("Le parcours de comparaison", 18))
	protocol_grid = GridContainer.new()
	protocol_grid.add_theme_constant_override("h_separation", 12)
	protocol_grid.add_theme_constant_override("v_separation", 12)
	content.add_child(protocol_grid)
	for scenario_index in CalibrationService.SCENARIOS.size():
		var definition := ScenarioCatalog.find(CalibrationService.SCENARIOS[scenario_index])
		var block := AimUI.card(protocol_grid, 14)
		block.add_child(AimUI.label("%02d · %s" % [scenario_index + 1, ScenarioCopy.title(definition)], 14))
		block.add_child(AimUI.label("3 réglages · 3 passages notés chacun", 12, AimUI.MUTED))
	var details := AimUI.foldout(content, "Comment le test fonctionne")
	details.add_child(AimUI.label("Pour chaque exercice : trois échauffements, puis trois séries avec les réglages A, B et C dans un ordre alterné. Ensuite, on passe à l’exercice suivant. Les échauffements ne comptent pas. Votre confort compte aussi.", 14, AimUI.MUTED))
	details.add_child(AimUI.label("Le conseil concerne les réglages essayés, pas une sensibilité universellement parfaite. Refaites le test un autre jour pour le confirmer.", 14, AimUI.MUTED))


func build_conversion(content: VBoxContainer) -> void:
	content.add_child(AimUI.label("Le même mouvement, dans votre jeu.", 29))
	content.add_child(AimUI.label("Choisissez votre jeu, puis recopiez la valeur dans ses réglages de souris.", 15, AimUI.MUTED))
	var setup := AimUI.card(content)
	var game_row := AimUI.row(setup)
	var caption := AimUI.label("Jeu")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_row.add_child(caption)
	game_input = OptionButton.new()
	for game_name in GameProfileService.TITLES:
		game_input.add_item(game_name)
	game_row.add_child(game_input)
	destination_dpi = AimUI.numeric(setup, "DPI utilisés dans le jeu", 1, 64000, 1)
	var result := AimUI.card(content, 28)
	result.add_child(AimUI.label("SENSIBILITÉ À RECOPIER", 11, AimUI.ACCENT))
	conversion_label = AimUI.label("", 42)
	result.add_child(conversion_label)
	conversion_reference_label = AimUI.label("", 13, AimUI.MUTED)
	result.add_child(conversion_reference_label)
	conversion_copy_button = AimUI.button("Copier la valeur", func() -> void:
		if SensitivityService.positive(conversion_value):
			DisplayServer.clipboard_set("%.6f" % conversion_value)
			set_status("Valeur copiée. Collez-la dans les réglages du jeu."), true)
	result.add_child(conversion_copy_button)
	result.add_child(AimUI.button("Importer plutôt le réglage de mon jeu", func() -> void: show_page(2)))
	content.add_child(AimUI.label("La conversion conserve la distance de rotation, sans zoom. Vérifiez le résultat dans le jeu ; le zoom et l’accélération peuvent changer le ressenti.", 14, AimUI.MUTED))
	var advanced := AimUI.foldout(content, "Réglages du jeu et détails")
	yaw_input = AimUI.numeric(advanced, "Coefficient de rotation du jeu", 0.0, 100000.0, 0.000001)
	conversion_details = AimUI.label("", 13, AimUI.MUTED)
	advanced.add_child(conversion_details)
	game_input.item_selected.connect(func(index: int) -> void:
		var game_id := GameProfileService.IDS[index]
		set_conversion_yaw(float(reference_game.yaw_deg) if reference_game.get("game_id", "") == game_id else GameProfileService.default_yaw(game_id))
		advanced.get_parent().get_child(0).button_pressed = index >= 2 and destination_yaw_deg <= 0.0
		update_conversion())
	destination_dpi.value_changed.connect(func(_value: float) -> void: update_conversion())
	yaw_input.value_changed.connect(func(value: float) -> void:
		destination_yaw_deg = value
		update_conversion())
	yaw_input.value = 0.022
	destination_dpi.value = 800


func build_history(content: VBoxContainer) -> void:
	var actions := AimUI.row(content)
	var introduction := AimUI.column(actions, 6)
	introduction.add_child(AimUI.label("Vos progrès, pas seulement un record.", 27))
	history_summary = AimUI.label("Vos séances apparaîtront ici.", 14, AimUI.MUTED)
	introduction.add_child(history_summary)
	actions.add_child(AimUI.button("Actualiser", func() -> void: history_requested.emit()))
	content.add_child(AimUI.label("On compare uniquement les séances réalisées avec les mêmes réglages et la même durée.", 13, AimUI.MUTED))
	history_content = AimUI.column(content, 12)
	history_content.add_child(AimUI.label("Commencez par un exercice pour voir vos résultats.", 16, AimUI.MUTED))
	content.add_child(AimUI.button("Exporter mes résultats", func() -> void: export_requested.emit()))


func show_history(total: int, summaries: Array[Dictionary]) -> void:
	history_summary.text = "%d séance%s enregistrée%s · exercices de %d s" % [total, "s" if total != 1 else "", "s" if total != 1 else "", [30, 60, 15][duration_input.selected]]
	for child in history_content.get_children():
		child.queue_free()
	var displayed: int = 0
	for summary in summaries:
		if int(summary.count) == 0:
			continue
		displayed += 1
		var card := AimUI.card(history_content, 18)
		card.add_child(AimUI.label(summary.title, 17))
		var values := AimUI.row(card)
		AimUI.stat(values, "Score habituel", "%.0f" % summary.latest_median)
		AimUI.stat(values, "Record", "%.0f" % summary.best)
		AimUI.stat(values, "Séances comparables", str(summary.count))
		var chart := ScoreChart.new()
		chart.custom_minimum_size.y = 96.0
		chart.score_values = summary.get("recent_scores", [])
		card.add_child(chart)
		card.add_child(AimUI.label("Scores des %d dernières séances comparables" % chart.score_values.size(), 11, AimUI.MUTED))
		var trend := "Encore %d séances comparables avant la première tendance." % maxi(10 - int(summary.count), 0)
		if summary.change_pct != null:
			trend = ("+" if float(summary.change_pct) >= 0.0 else "") + AimUI.number(summary.change_pct, 1) + " % entre vos premières séances et les plus récentes."
		elif int(summary.count) >= 10:
			trend = "La tendance est indisponible : les premières séances n’ont pas de score positif."
		card.add_child(AimUI.label(trend, 13, AimUI.MUTED))
	if displayed == 0:
		var empty := AimUI.card(history_content, 26)
		empty.add_child(AimUI.label("Le premier pas, c’est une séance.", 22))
		empty.add_child(AimUI.label("Aucun résultat comparable pour ces réglages. Choisissez un exercice et gardez la même durée pour suivre vos progrès.", 14, AimUI.MUTED))
		empty.add_child(AimUI.button("Choisir un exercice  →", func() -> void: show_page(1), true))


func build_settings(content: VBoxContainer) -> void:
	var weapons := AimUI.card(content)
	weapons.add_child(AimUI.label("Votre équipement", 20))
	weapons.add_child(AimUI.label("Un look et un son, pas un avantage. Les armes ne changent ni la visée ni le score.", 13, AimUI.MUTED))
	var choices := AimUI.row(weapons, 8)
	for definition in WeaponCatalog.DEFINITIONS:
		var control := AimUI.button(definition.title, func() -> void:
			weapon_id = definition.weapon_id
			update_weapon())
		control.toggle_mode = true
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weapon_buttons.append(control)
		choices.add_child(control)
	var preview_row := GridContainer.new()
	preview_row.columns = 2
	preview_row.add_theme_constant_override("h_separation", 14)
	preview_row.add_theme_constant_override("v_separation", 14)
	weapons.add_child(preview_row)
	settings_preview_grid = preview_row
	weapon_preview = WeaponFeedback.new()
	weapon_preview.custom_minimum_size = Vector2(250, 125)
	preview_row.add_child(weapon_preview)
	var presentation := AimUI.column(preview_row, 8)
	weapon_title = AimUI.label("", 20)
	presentation.add_child(weapon_title)
	presentation.add_child(AimUI.label("Clic : un tir. En suivi, maintenez le clic pour un son continu facultatif.", 13, AimUI.MUTED))
	var tests := HFlowContainer.new()
	tests.add_theme_constant_override("h_separation", 8)
	tests.add_theme_constant_override("v_separation", 8)
	presentation.add_child(tests)
	tests.add_child(AimUI.button("Écouter un tir", func() -> void: weapon_preview.play_shot()))
	var continuous_test := Button.new()
	continuous_test.text = "Maintenir pour écouter"
	continuous_test.button_down.connect(func() -> void: weapon_preview.set_continuous(true))
	continuous_test.button_up.connect(func() -> void: weapon_preview.set_continuous(false))
	tests.add_child(continuous_test)
	sound_input = CheckButton.new()
	sound_input.text = "Sons des tirs"
	weapons.add_child(sound_input)
	var volume_row := AimUI.row(weapons)
	var volume_label := AimUI.label("Volume", 14)
	volume_label.size_flags_horizontal = Control.SIZE_FILL
	volume_label.custom_minimum_size.x = 65.0
	volume_row.add_child(volume_label)
	volume_input = HSlider.new()
	volume_input.max_value = 100.0
	volume_input.step = 1.0
	volume_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_input)
	weapon_visible_input = CheckButton.new()
	weapon_visible_input.text = "Afficher l’arme pendant les exercices"
	weapons.add_child(weapon_visible_input)
	var display := AimUI.card(content)
	display.add_child(AimUI.label("Confort d’affichage", 20))
	motion_input = CheckButton.new()
	motion_input.text = "Réduire les animations"
	display.add_child(motion_input)
	var fps_row := AimUI.row(display)
	var fps_label := AimUI.label("Limite d’images par seconde")
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	fps_input = OptionButton.new()
	for caption in ["144 FPS", "240 FPS", "60 FPS", "Illimitée"]:
		fps_input.add_item(caption)
	fps_row.add_child(fps_input)
	var advanced := AimUI.foldout(content, "Souris et paramètres avancés")
	distance_input = AimUI.numeric(advanced, "Distance pour un tour complet (cm)", 5, 150, 0.000001)
	advanced.add_child(AimUI.label("C’est la distance réelle parcourue par votre souris pour faire un tour complet à l’écran. Plus elle est grande, plus la visée est lente.", 13, AimUI.MUTED))
	fov_input = AimUI.numeric(advanced, "Champ de vision vertical (°)", 40, 110, 1)
	accumulated_input = CheckButton.new()
	accumulated_input.text = "Regrouper les événements souris"
	advanced.add_child(accumulated_input)
	accumulated_input.tooltip_text = "Option technique Godot : comparez les deux modes sur votre matériel. Aucun lissage n’est ajouté."
	inverted_input = CheckButton.new()
	inverted_input.text = "Inverser la visée verticale"
	advanced.add_child(inverted_input)
	test_button = AimUI.button("Vérifier le mouvement de ma souris", func() -> void: test_requested.emit())
	advanced.add_child(test_button)
	sound_input.toggled.connect(func(_enabled: bool) -> void: update_weapon())
	volume_input.value_changed.connect(func(_value: float) -> void: update_weapon())
	motion_input.toggled.connect(func(reduced: bool) -> void:
		AimUI.motion_enabled = not reduced
		refresh_previews(self)
		update_weapon())


func refresh_previews(parent: Node) -> void:
	for child in parent.get_children():
		if child is ScenarioPreview:
			child.set_process(child.animated and child.is_visible_in_tree() and AimUI.motion_enabled)
		refresh_previews(child)


func update_weapon() -> void:
	if sound_input == null or weapon_preview == null or volume_input == null:
		return
	var definition := WeaponCatalog.find(weapon_id)
	weapon_title.text = definition.title
	weapon_preview.configure(definition, sound_input.button_pressed, volume_input.value / 100.0, true, motion_input.button_pressed if motion_input != null else false)
	for index in weapon_buttons.size():
		weapon_buttons[index].set_pressed_no_signal(WeaponCatalog.DEFINITIONS[index].weapon_id == weapon_id)


func sync_sensitivity() -> void:
	if syncing_sensitivity or distance_input == null:
		return
	syncing_sensitivity = true
	sensitivity_input.min_value = SensitivityService.game_sensitivity(dpi_input.value, 150.0, SensitivityService.APP_YAW_DEG)
	sensitivity_input.max_value = SensitivityService.game_sensitivity(dpi_input.value, 5.0, SensitivityService.APP_YAW_DEG)
	sensitivity_input.set_value_no_signal(SensitivityService.game_sensitivity(dpi_input.value, current_distance_cm, SensitivityService.APP_YAW_DEG))
	for index in preset_buttons.size():
		preset_buttons[index].set_pressed_no_signal(is_equal_approx(distance_input.value, [50.0, 35.0, 25.0][index]))
	var custom_start := not is_equal_approx(distance_input.value, 50.0) and not is_equal_approx(distance_input.value, 35.0) and not is_equal_approx(distance_input.value, 25.0)
	start_help_label.text = "Votre réglage actuel est conservé. Le test l’ajustera pour vous." if custom_start else "Le test ajuste la sensibilité pour vous. Gardez les mêmes DPI."
	profile_badge.text = "Sensibilité · %s\n%d DPI" % [AimUI.number(sensitivity_input.value, 4), int(dpi_input.value)]
	syncing_sensitivity = false
	if reference_import != null:
		reference_import.current_profile = read_profile()
		reference_import.update_preview()
	update_conversion()


func change_app_sensitivity(value: float) -> void:
	if not syncing_sensitivity:
		current_distance_cm = SensitivityService.cm_per_360(dpi_input.value, value * SensitivityService.APP_YAW_DEG)
		distance_input.set_value_no_signal(current_distance_cm)
		sync_sensitivity()


func update_conversion() -> void:
	if conversion_label == null or distance_input == null:
		return
	conversion_value = SensitivityService.game_sensitivity(destination_dpi.value, current_distance_cm, destination_yaw_deg)
	var available := SensitivityService.positive(conversion_value)
	conversion_label.text = AimUI.number(conversion_value, 6) if available else "Profil à renseigner"
	conversion_copy_button.disabled = not available
	var game_id := GameProfileService.IDS[game_input.selected]
	conversion_reference_label.text = GameProfileService.confidence_text(reference_game) + " · " + str(reference_game.title) if reference_game.get("game_id", "") == game_id and is_equal_approx(float(reference_game.get("yaw_deg", 0.0)), destination_yaw_deg) else "Coefficient documentaire · rotation sans zoom" if game_input.selected < 2 and is_equal_approx(destination_yaw_deg, GameProfileService.default_yaw(game_id)) else "Coefficient saisi manuellement · à vérifier dans le jeu" if available else "Importez d’abord ce jeu dans Ma sensibilité, ou renseignez son coefficient vérifié dans les détails."
	conversion_details.text = "Sensibilité AIM/LOCAL : %s · %d DPI\nDistance : %s cm pour un tour complet.\nCoefficient utilisé : %s (le champ ci-dessus peut arrondir l’affichage).\nCS2 : m_yaw par défaut 0,022. VALORANT : coefficient documentaire 0,07.\nCoD et autres jeux : profil mesuré par titre/version, sans zoom. Aucun coefficient universel ADS." % [AimUI.number(sensitivity_input.value, 4), int(dpi_input.value), AimUI.number(current_distance_cm, 3), str(destination_yaw_deg)]


func set_conversion_yaw(value: float) -> void:
	destination_yaw_deg = value
	yaw_input.set_value_no_signal(value)


func read_profile() -> Dictionary:
	var profile := {"schema_version": 1, "dpi": dpi_input.value, "cm_per_360": current_distance_cm,
		"vertical_fov_deg": fov_input.value, "goal": ["balanced", "precision", "tracking"][goal_input.selected],
		"accumulated_input": accumulated_input.button_pressed, "invert_y": inverted_input.button_pressed,
		"max_fps": [144, 240, 60, 0][fps_input.selected], "weapon_id": weapon_id,
		"sound_enabled": sound_input.button_pressed, "sound_volume": volume_input.value,
		"show_weapon": weapon_visible_input.button_pressed, "reduced_motion": motion_input.button_pressed}
	if not reference_game.is_empty():
		profile.reference_game = reference_game.duplicate(true)
	return profile


func bind_profile(profile: Dictionary) -> void:
	syncing_sensitivity = true
	current_distance_cm = float(profile.cm_per_360)
	reference_game = profile.get("reference_game", {}).duplicate(true)
	dpi_input.value = float(profile.dpi)
	distance_input.value = float(profile.cm_per_360)
	fov_input.value = float(profile.vertical_fov_deg)
	goal_input.select(maxi(0, ["balanced", "precision", "tracking"].find(profile.get("goal", "balanced"))))
	fps_input.select(maxi(0, [144, 240, 60, 0].find(int(profile.get("max_fps", 144)))))
	accumulated_input.button_pressed = bool(profile.get("accumulated_input", true))
	inverted_input.button_pressed = bool(profile.get("invert_y", false))
	weapon_id = str(profile.get("weapon_id", "pulse"))
	sound_input.set_pressed_no_signal(bool(profile.get("sound_enabled", true)))
	volume_input.set_value_no_signal(float(profile.get("sound_volume", 45.0)))
	weapon_visible_input.button_pressed = bool(profile.get("show_weapon", true))
	motion_input.set_pressed_no_signal(bool(profile.get("reduced_motion", false)))
	AimUI.motion_enabled = not motion_input.button_pressed
	destination_dpi.value = float(profile.dpi)
	if not reference_game.is_empty():
		game_input.select(GameProfileService.IDS.find(reference_game.game_id))
		set_conversion_yaw(float(reference_game.yaw_deg))
	else:
		game_input.select(0)
		set_conversion_yaw(0.022)
	reference_import.bind_context(profile)
	syncing_sensitivity = false
	sync_sensitivity()
	update_weapon()
	refresh_previews(self)


func update_layout() -> void:
	var compact := size.x < 1060.0
	sidebar.custom_minimum_size.x = 68.0 if compact else 196.0
	brand_label.visible = not compact
	local_label.visible = not compact
	for index in nav_buttons.size():
		nav_buttons[index].text = "" if compact else PAGE_TITLES[index]
		nav_buttons[index].alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	quit_button.text = "×" if compact else "Quitter"
	var side_margin := 26 if size.x < 1600.0 else 36
	content_margin.add_theme_constant_override("margin_left", side_margin)
	content_margin.add_theme_constant_override("margin_right", side_margin)
	hero_preview.visible = size.x >= 1060.0
	home_grid.columns = 3 if size.x >= 1180.0 else 2 if size.x >= 940.0 else 1
	settings_preview_grid.columns = 2 if size.x >= 1060.0 else 1
	calibration_grid.columns = 2 if size.x >= 1180.0 else 1
	protocol_grid.columns = 5 if size.x >= 1700.0 else 3 if size.x >= 1180.0 else 2


func set_status(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()
