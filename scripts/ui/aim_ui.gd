class_name AimUI
extends RefCounted

const TEXT := Color("e4edf9")
const MUTED := Color("9aaac3")
const ACCENT := Color("64e6d9")
const PANEL := Color("121827")
const BORDER := Color("243044")
const HOVER := Color("1b293b")
const SELECTED := Color("16323b")
const HOVER_BORDER := Color("466578")
const FOCUS := Color("a5fff0")
const DISABLED := Color("101725")
const FeedbackScript := preload("res://scripts/ui/interaction_feedback.gd")
const BACKDROP := preload("res://assets/ui/ambient.svg")

static var motion_enabled: bool = true:
	set(enabled):
		if motion_enabled == enabled:
			return
		motion_enabled = enabled
		FeedbackScript.set_motion_enabled(enabled)


static func number(value: float, decimals: int = 2) -> String:
	return ("%.*f" % [decimals, value]).replace(".", ",")


static func label(caption: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var control := Label.new()
	control.text = caption
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	control.add_theme_constant_override("line_spacing", 3)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


static func style(color: Color = PANEL, padding: float = 22.0, border: Color = BORDER, radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(padding)
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = border
	return box


static func column(parent: Node, separation: int = 14) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", separation)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	return content


static func row(parent: Node, separation: int = 12) -> HBoxContainer:
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", separation)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	return content


static func card(parent: Node, padding: float = 22.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style(PANEL, padding, BORDER, 14))
	parent.add_child(panel)
	return column(panel)


static func button(caption: String, action: Callable, primary: bool = false) -> Button:
	var control := Button.new()
	control.text = caption
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.pressed.connect(action)
	style_button(control, &"primary" if primary else &"default")
	control.ready.connect(func() -> void: feedback(control), CONNECT_ONE_SHOT)
	return control


static func style_button(control: Button, variant: StringName = &"default") -> void:
	var card_variant := variant == &"card"
	var primary := variant == &"primary"
	var padding_px := 0.0 if card_variant else 11.0
	var radius := 12 if card_variant else 8
	var backgrounds: Array[Color] = [PANEL if card_variant else Color("1a2435"), HOVER, SELECTED, Color("1d4048"), DISABLED]
	var borders: Array[Color] = [BORDER, HOVER_BORDER, ACCENT, ACCENT, Color("1f293b")]
	if primary:
		backgrounds = [ACCENT, Color("8bf5e7"), Color("43baaf"), Color("72eede"), Color("183b40")]
		borders = [ACCENT, Color("8bf5e7"), Color("43baaf"), Color("72eede"), Color("2b555b")]
	var states := ["normal", "hover", "pressed", "hover_pressed", "disabled"]
	for state_index in states.size():
		var box := style(backgrounds[state_index], padding_px, borders[state_index], radius)
		if not card_variant:
			box.content_margin_left = 16.0
			box.content_margin_right = 16.0
		control.add_theme_stylebox_override(states[state_index], box)
	var focus := style(Color.TRANSPARENT, padding_px, FOCUS, radius)
	focus.set_border_width_all(2)
	if not card_variant:
		focus.content_margin_left = 16.0
		focus.content_margin_right = 16.0
	control.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(state, Color("082a2c") if primary else TEXT)
	control.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))


static func feedback(control: Control) -> FeedbackScript:
	var existing := control.get_node_or_null("AimInteractionFeedback") as FeedbackScript
	if existing != null:
		return existing
	var result := FeedbackScript.new()
	result.control = control
	result.button = control as BaseButton
	result.name = "AimInteractionFeedback"
	control.add_child(result)
	return result


static func numeric(parent: Node, caption: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var fields := row(parent)
	var text := label(caption)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(text)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.custom_minimum_size.x = 150.0
	fields.add_child(input)
	return input


static func foldout(parent: Node, caption: String) -> VBoxContainer:
	var content := column(parent, 10)
	var toggle := Button.new()
	toggle.text = "+  " + caption
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.toggle_mode = true
	style_button(toggle)
	content.add_child(toggle)
	feedback(toggle)
	var details := column(content, 12)
	details.hide()
	toggle.toggled.connect(func(expanded: bool) -> void:
		details.visible = expanded
		toggle.text = ("−  " if expanded else "+  ") + caption)
	return details


static func backdrop(parent: Control) -> void:
	var texture := TextureRect.new()
	texture.texture = BACKDROP
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(texture)


static func fade_in(control: Control) -> void:
	feedback(control).fade_in()


static func stat(parent: Node, caption: String, value: String, color: Color = TEXT) -> Label:
	var content := card(parent, 18.0)
	content.add_child(label(caption, 12, MUTED))
	var result := label(value, 26, color)
	content.add_child(result)
	return result
