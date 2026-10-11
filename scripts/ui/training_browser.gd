class_name TrainingBrowser
extends VBoxContainer

signal training_requested(scenario_id: String, duration_s: float)

var selected_definition: ScenarioDefinition = ScenarioCatalog.DEFINITIONS[0]
var selected_family: String = "all"
var search_input: LineEdit
var duration_input: OptionButton
var grid: GridContainer
var cards: Dictionary = {}
var filter_buttons: Array[Button] = []
var preview: ScenarioPreview
var detail_scroll: ScrollContainer
var title_label: Label
var description_label: Label
var family_label: Label
var measure_label: Label
var start_button: Button
var empty_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var filters := AimUI.row(self, 6)
	var families := ["all", "click", "tracking", "switching"]
	for filter_index in families.size():
		var family_id: String = families[filter_index]
		var control := AimUI.button(["Tout", "Précision", "Suivi", "Transitions"][filter_index], func() -> void:
			selected_family = family_id
			filter_catalog())
		control.toggle_mode = true
		filter_buttons.append(control)
		filters.add_child(control)
	search_input = LineEdit.new()
	search_input.placeholder_text = "Rechercher un exercice"
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(func(_query: String) -> void: filter_catalog())
	add_child(search_input)
	var layout := AimUI.row(self, 18)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var catalog := AimUI.column(layout)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for definition in ScenarioCatalog.DEFINITIONS:
		var control := scenario_card(definition, func() -> void: select_definition(definition))
		grid.add_child(control)
		cards[definition.scenario_id] = control
	empty_label = AimUI.label("Aucun exercice trouvé. Essayez un autre mot.", 14, AimUI.MUTED)
	empty_label.hide()
	catalog.add_child(empty_label)
	var detail_column := AimUI.column(layout, 10)
	detail_column.custom_minimum_size.x = 278.0
	detail_column.size_flags_horizontal = Control.SIZE_FILL
	detail_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(detail_scroll)
	var detail := AimUI.card(detail_scroll, 12)
	detail.add_theme_constant_override("separation", 8)
	family_label = AimUI.label("", 11, AimUI.ACCENT)
	detail.add_child(family_label)
	title_label = AimUI.label("", 20)
	detail.add_child(title_label)
	preview = ScenarioPreview.new()
	preview.custom_minimum_size.y = 104.0
	detail.add_child(preview)
	description_label = AimUI.label("", 14, AimUI.MUTED)
	detail.add_child(description_label)
	measure_label = AimUI.label("", 12, AimUI.MUTED)
	detail.add_child(measure_label)
	var duration_row := AimUI.row(detail_column)
	var duration_label := AimUI.label("Durée", 14)
	duration_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_row.add_child(duration_label)
	duration_input = OptionButton.new()
	for seconds in [30, 60, 15]:
		duration_input.add_item("%d s" % seconds)
	duration_row.add_child(duration_input)
	start_button = AimUI.button("Lancer l’exercice  →", func() -> void:
		training_requested.emit(selected_definition.scenario_id, [30.0, 60.0, 15.0][duration_input.selected]), true)
	detail_column.add_child(start_button)
	resized.connect(update_layout)
	filter_catalog()
	update_layout.call_deferred()


static func scenario_card(definition: ScenarioDefinition, action: Callable) -> Button:
	var control := AimUI.button("", action)
	control.tooltip_text = ScenarioCopy.description(definition)
	control.custom_minimum_size = Vector2(176, 180)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.add_theme_stylebox_override("normal", AimUI.style(AimUI.PANEL, 0.0))
	control.add_theme_stylebox_override("hover", AimUI.style(Color("192b39"), 0.0, Color("397b7e")))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	control.add_child(margin)
	var content := AimUI.column(margin, 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumbnail := ScenarioPreview.new()
	thumbnail.custom_minimum_size.y = 78.0
	content.add_child(thumbnail)
	thumbnail.configure(definition)
	content.add_child(AimUI.label(ScenarioCopy.family(definition), 10, AimUI.ACCENT))
	content.add_child(AimUI.label(ScenarioCopy.title(definition), 15))
	return control


func select_definition(definition: ScenarioDefinition) -> void:
	selected_definition = definition
	family_label.text = ScenarioCopy.family(definition) + "  /  APERÇU"
	title_label.text = ScenarioCopy.title(definition)
	description_label.text = ScenarioCopy.description(definition)
	measure_label.text = "Score · temps sur cible" if definition.family == "tracking" else "Score · précision et vitesse"
	preview.configure(definition, true)
	if detail_scroll != null:
		detail_scroll.scroll_vertical = 0
	for scenario_id in cards:
		var control: Button = cards[scenario_id]
		var selected: bool = scenario_id == definition.scenario_id
		control.add_theme_stylebox_override("normal", AimUI.style(Color("152a33") if selected else AimUI.PANEL, 0.0, AimUI.ACCENT if selected else AimUI.BORDER))


func filter_catalog() -> void:
	var matches: Array[ScenarioDefinition] = []
	var query := search_input.text.strip_edges().to_lower()
	for definition in ScenarioCatalog.DEFINITIONS:
		var visible_card := (selected_family == "all" or definition.family == selected_family) and (query.is_empty() or (ScenarioCopy.title(definition) + " " + ScenarioCopy.description(definition)).to_lower().contains(query))
		cards[definition.scenario_id].visible = visible_card
		if visible_card:
			matches.append(definition)
	for filter_index in filter_buttons.size():
		filter_buttons[filter_index].set_pressed_no_signal(selected_family == ["all", "click", "tracking", "switching"][filter_index])
	empty_label.visible = matches.is_empty()
	start_button.disabled = matches.is_empty()
	if not matches.is_empty():
		select_definition(selected_definition if selected_definition in matches else matches[0])


func update_layout() -> void:
	if grid != null:
		grid.columns = 2 if size.x >= 790.0 else 1
		preview.visible = size.y >= 420.0
