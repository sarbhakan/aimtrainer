class_name AimUI
extends RefCounted

const TEXT := Color("e4edf9")
const MUTED := Color("9aaac3")
const ACCENT := Color("64e6d9")
const PANEL := Color("121827")
const BORDER := Color("243044")
const BACKDROP := preload("res://assets/ui/ambient.svg")

static var motion_enabled: bool = true


static func number(value: float, decimals: int = 2) -> String:
	return ("%.*f" % [decimals, value]).replace(".", ",")


static func label(caption: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var control := Label.new()
	control.text = caption
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
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
	panel.add_theme_stylebox_override("panel", style(PANEL, padding))
	parent.add_child(panel)
	return column(panel)


static func button(caption: String, action: Callable, primary: bool = false) -> Button:
	var control := Button.new()
	control.text = caption
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.pressed.connect(action)
	if primary:
		control.add_theme_stylebox_override("normal", style(ACCENT, 13.0, ACCENT, 8))
		control.add_theme_stylebox_override("hover", style(Color("8bf5e7"), 13.0, Color("8bf5e7"), 8))
		control.add_theme_stylebox_override("pressed", style(Color("43baaf"), 13.0, Color("43baaf"), 8))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			control.add_theme_color_override(state, Color("082a2c"))
	return control


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
	content.add_child(toggle)
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
	if not motion_enabled:
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	control.create_tween().tween_property(control, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)


static func stat(parent: Node, caption: String, value: String, color: Color = TEXT) -> Label:
	var content := card(parent, 18.0)
	content.add_child(label(caption, 12, MUTED))
	var result := label(value, 26, color)
	content.add_child(result)
	return result
