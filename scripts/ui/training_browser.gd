class_name TrainingBrowser
extends VBoxContainer

signal training_requested(scenario_id: String, duration_s: float)

const PreviewPopupScript := preload("res://scripts/ui/exercise_preview_popup.gd")
const PREVIEW_DELAY_S: float = 0.18
const FAMILY_IDS := ["all", "click", "tracking", "switching"]
const CARD_WIDTH_PX: float = 192.0

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
var detail_column: VBoxContainer
var catalog_scroll: ScrollContainer
var preview_popup: PreviewPopupScript
var preview_timer: Timer
var pending_definition: ScenarioDefinition
var pending_anchor: Control


func _ready() -> void:
	add_theme_constant_override("separation", AimUI.SPACE_LG)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var filters := AimUI.flow(self)
	var filter_group := ButtonGroup.new()
	filter_group.allow_unpress = false
	for filter_index in FAMILY_IDS.size():
		var family_id: String = FAMILY_IDS[filter_index]
		var control := AimUI.button(["Tout", "Précision", "Suivi", "Transitions"][filter_index], func() -> void:
			selected_family = family_id
			filter_catalog())
		control.toggle_mode = true
		control.button_group = filter_group
		filter_buttons.append(control)
		filters.add_child(control)
	search_input = LineEdit.new()
	search_input.placeholder_text = "Rechercher un exercice"
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(func(_query: String) -> void: filter_catalog())
	add_child(search_input)
	var layout := AimUI.row(self, AimUI.SPACE_LG)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var catalog := AimUI.column(layout)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_scroll = ScrollContainer.new()
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	catalog_scroll.follow_focus = true
	catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.add_child(catalog_scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AimUI.grid_spacing(grid, AimUI.SPACE_MD)
	catalog_scroll.add_child(grid)
	var card_group := ButtonGroup.new()
	card_group.allow_unpress = false
	for definition in ScenarioCatalog.DEFINITIONS:
		var control := scenario_card(definition, func() -> void: select_definition(definition))
		control.toggle_mode = true
		control.button_group = card_group
		grid.add_child(control)
		cards[definition.scenario_id] = control
		control.mouse_entered.connect(func() -> void: schedule_card_preview(definition, control))
		control.focus_entered.connect(func() -> void: schedule_card_preview(definition, control))
		control.mouse_exited.connect(func() -> void:
			if not control.has_focus():
				dismiss_card_preview(control))
		control.focus_exited.connect(func() -> void:
			if not control.is_hovered():
				dismiss_card_preview(control))
		control.pressed.connect(func() -> void: show_card_preview(definition, control))
	empty_label = AimUI.label("Aucun exercice trouvé. Essayez un autre mot.", 14, AimUI.MUTED)
	empty_label.hide()
	catalog.add_child(empty_label)
	detail_column = AimUI.column(layout)
	detail_column.custom_minimum_size.x = 228.0
	detail_column.size_flags_horizontal = Control.SIZE_FILL
	detail_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(detail_scroll)
	var detail := AimUI.card(detail_scroll, AimUI.SPACE_LG)
	family_label = AimUI.label("", 11, AimUI.ACCENT)
	detail.add_child(family_label)
	title_label = AimUI.label("", 21)
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
	AimUI.feedback(duration_input)
	start_button = AimUI.button("Lancer l’exercice  →", func() -> void:
		training_requested.emit(selected_definition.scenario_id, [30.0, 60.0, 15.0][duration_input.selected]), true)
	detail_column.add_child(start_button)
	var preview_host := Node.new()
	add_child(preview_host)
	preview_popup = PreviewPopupScript.new()
	preview_host.add_child(preview_popup)
	preview_popup.visibility_changed.connect(refresh_preview_animation)
	preview_timer = Timer.new()
	preview_timer.one_shot = true
	preview_timer.wait_time = PREVIEW_DELAY_S
	preview_timer.timeout.connect(show_pending_preview)
	add_child(preview_timer)
	catalog_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: dismiss_card_preview())
	visibility_changed.connect(browser_visibility_changed)
	AimUI.feedback(self).motion_changed.connect(func(_enabled: bool) -> void: refresh_preview_animation())
	resized.connect(update_layout)
	catalog_scroll.resized.connect(update_layout)
	filter_catalog()
	update_layout.call_deferred()


static func scenario_card(definition: ScenarioDefinition, action: Callable) -> Button:
	var control := AimUI.button("", action)
	control.set_meta("scenario_id", definition.scenario_id)
	control.custom_minimum_size = Vector2(CARD_WIDTH_PX, 184)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AimUI.style_button(control, &"card")
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, AimUI.SPACE_LG)
	control.add_child(margin)
	var content := AimUI.column(margin, AimUI.SPACE_SM)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumbnail := ScenarioPreview.new()
	thumbnail.custom_minimum_size.y = 78.0
	content.add_child(thumbnail)
	thumbnail.configure(definition)
	content.add_child(AimUI.label(ScenarioCopy.family(definition), 10, AimUI.ACCENT))
	content.add_child(AimUI.label(ScenarioCopy.title(definition), 16))
	return control


func select_definition(definition: ScenarioDefinition) -> void:
	var changed := selected_definition != definition or title_label.text.is_empty()
	selected_definition = definition
	family_label.text = ScenarioCopy.family(definition)
	title_label.text = ScenarioCopy.title(definition)
	description_label.text = ScenarioCopy.description(definition)
	measure_label.text = ScenarioCopy.measure(definition)
	if changed:
		preview.configure(definition, not preview_popup.visible if preview_popup != null else true)
		detail_scroll.scroll_vertical = 0
		AimUI.fade_in(detail_scroll)
	for scenario_id in cards:
		var control: Button = cards[scenario_id]
		control.set_pressed_no_signal(scenario_id == definition.scenario_id)
	refresh_preview_animation()


func filter_catalog() -> void:
	dismiss_card_preview()
	var matches: Array[ScenarioDefinition] = []
	var query := search_input.text.strip_edges().to_lower()
	for definition in ScenarioCatalog.DEFINITIONS:
		var visible_card := (selected_family == "all" or definition.family == selected_family) and (query.is_empty() or (ScenarioCopy.title(definition) + " " + ScenarioCopy.description(definition)).to_lower().contains(query))
		cards[definition.scenario_id].visible = visible_card
		if visible_card:
			matches.append(definition)
	for filter_index in filter_buttons.size():
		filter_buttons[filter_index].set_pressed_no_signal(selected_family == FAMILY_IDS[filter_index])
	empty_label.visible = matches.is_empty()
	start_button.disabled = matches.is_empty()
	if not matches.is_empty():
		select_definition(selected_definition if selected_definition in matches else matches[0])
	else:
		preview.animated = false
		preview.set_process(false)
	update_card_focus()


func update_layout() -> void:
	if grid != null:
		add_theme_constant_override("separation", AimUI.SPACE_SM if size.y < 420.0 else AimUI.SPACE_LG)
		detail_column.custom_minimum_size.x = clampf(size.x * 0.30, 228.0, 420.0)
		var catalog_width_px := catalog_scroll.size.x - catalog_scroll.get_theme_stylebox("panel").get_minimum_size().x - catalog_scroll.get_v_scroll_bar().get_combined_minimum_size().x
		grid.columns = clampi(floori((catalog_width_px + AimUI.SPACE_MD) / (CARD_WIDTH_PX + AimUI.SPACE_MD)), 1, 5)
		preview.visible = size.y >= 420.0
		update_card_focus()
		refresh_preview_animation()
		if preview_popup != null and preview_popup.visible:
			preview_popup.place_in_viewport.call_deferred()


func update_card_focus() -> void:
	var visible_cards: Array[Button] = []
	for definition in ScenarioCatalog.DEFINITIONS:
		var control: Button = cards[definition.scenario_id]
		if control.visible:
			visible_cards.append(control)
	for card_index in visible_cards.size():
		var control := visible_cards[card_index]
		control.focus_previous = control.get_path_to(visible_cards[card_index - 1] if card_index > 0 else search_input)
		control.focus_next = control.get_path_to(visible_cards[card_index + 1] if card_index + 1 < visible_cards.size() else duration_input)
		control.focus_neighbor_left = control.get_path_to(visible_cards[card_index - 1] if card_index % grid.columns > 0 else control)
		control.focus_neighbor_right = control.get_path_to(visible_cards[card_index + 1] if card_index % grid.columns < grid.columns - 1 and card_index + 1 < visible_cards.size() else control)
		control.focus_neighbor_top = control.get_path_to(visible_cards[card_index - grid.columns] if card_index >= grid.columns else search_input)
		control.focus_neighbor_bottom = control.get_path_to(visible_cards[card_index + grid.columns] if card_index + grid.columns < visible_cards.size() else duration_input)
	search_input.focus_next = search_input.get_path_to(visible_cards[0] if not visible_cards.is_empty() else duration_input)
	duration_input.focus_previous = duration_input.get_path_to(visible_cards[-1] if not visible_cards.is_empty() else search_input)


func schedule_card_preview(definition: ScenarioDefinition, anchor: Control) -> void:
	if not is_visible_in_tree() or not anchor.is_visible_in_tree():
		return
	if anchor == pending_anchor or (preview_popup.visible and preview_popup.anchor == anchor and preview_popup.definition == definition):
		return
	dismiss_card_preview()
	if anchor.has_focus() and grid.is_ancestor_of(anchor):
		catalog_scroll.ensure_control_visible(anchor)
	pending_definition = definition
	pending_anchor = anchor
	preview_timer.start()


func show_pending_preview() -> void:
	if pending_definition != null and is_instance_valid(pending_anchor):
		show_card_preview(pending_definition, pending_anchor)


func show_card_preview(definition: ScenarioDefinition, anchor: Control = null) -> void:
	if definition == null:
		dismiss_card_preview()
		return
	preview_timer.stop()
	pending_definition = null
	pending_anchor = null
	var source: Control = anchor if is_instance_valid(anchor) else cards.get(definition.scenario_id)
	if not is_visible_in_tree() or not is_instance_valid(source) or not source.is_visible_in_tree():
		dismiss_card_preview()
		return
	preview.animated = false
	preview.set_process(false)
	preview_popup.present(definition, source)


func dismiss_card_preview(anchor: Control = null) -> void:
	if preview_popup == null or preview_timer == null:
		return
	if anchor != null and anchor != pending_anchor and anchor != preview_popup.anchor:
		return
	preview_timer.stop()
	pending_definition = null
	pending_anchor = null
	preview_popup.dismiss()
	refresh_preview_animation()


func refresh_preview_animation() -> void:
	if preview == null:
		return
	preview.animated = not start_button.disabled and (preview_popup == null or not preview_popup.visible)
	preview.set_process(preview.animated and preview.is_visible_in_tree() and AimUI.motion_enabled)


func browser_visibility_changed() -> void:
	if not is_visible_in_tree():
		dismiss_card_preview()
	refresh_preview_animation()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel") and (preview_popup.visible or not preview_timer.is_stopped()):
		dismiss_card_preview()
		get_viewport().set_input_as_handled()
