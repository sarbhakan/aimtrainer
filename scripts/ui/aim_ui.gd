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
const SPACE_XS: int = 4
const SPACE_SM: int = 8
const SPACE_MD: int = 12
const SPACE_LG: int = 16
const SPACE_XL: int = 24
const SPACE_2XL: int = 32
const FIELD_WIDTH_PX: float = 150.0
const SENSITIVITY_DECIMALS: int = 2
const FeedbackScript := preload("res://scripts/ui/interaction_feedback.gd")
const BACKDROP := preload("res://assets/ui/ambient.svg")

class ScrollFocus extends Node:
	var scroll: ScrollContainer

	func _ready() -> void:
		get_viewport().gui_focus_changed.connect(follow_control)

	func follow_control(control: Control) -> void:
		if scroll.follow_focus and scroll.is_ancestor_of(control):
			reveal_control.call_deferred(control)

	func reveal_control(control: Control) -> void:
		if is_instance_valid(control) and control.has_focus() and control.is_visible_in_tree():
			AimUI.ensure_control_visible(scroll, control)


static var motion_enabled: bool = true:
	set(enabled):
		if motion_enabled == enabled:
			return
		motion_enabled = enabled
		FeedbackScript.set_motion_enabled(enabled)


static func number(value: float, decimals: int = 2) -> String:
	return ("%.*f" % [decimals, value]).replace(".", ",")


static func sensitivity(value: float) -> String:
	if value > 0.0 and value < 0.005:
		return "<0,01"
	return number(value, SENSITIVITY_DECIMALS)


static func label(caption: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var control := Label.new()
	control.text = caption
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	control.add_theme_constant_override("line_spacing", SPACE_XS)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


static func style(color: Color = PANEL, padding: float = SPACE_XL, border: Color = BORDER, radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(padding)
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = border
	return box


static func column(parent: Node, separation: int = SPACE_MD) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", separation)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	return content


static func row(parent: Node, separation: int = SPACE_MD) -> HBoxContainer:
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", separation)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	return content


static func flow(parent: Node, separation: int = SPACE_SM) -> HFlowContainer:
	var content := HFlowContainer.new()
	content.add_theme_constant_override("h_separation", separation)
	content.add_theme_constant_override("v_separation", separation)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	return content


static func grid_spacing(control: GridContainer, separation: int = SPACE_LG) -> void:
	control.add_theme_constant_override("h_separation", separation)
	control.add_theme_constant_override("v_separation", separation)


static func card(parent: Node, padding: float = SPACE_XL) -> VBoxContainer:
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


static func icon_button(icon: Texture2D, caption: String, action: Callable) -> Button:
	var control := button("", action)
	control.icon = icon
	control.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.expand_icon = true
	control.add_theme_constant_override("icon_max_width", 20)
	control.custom_minimum_size = Vector2(40.0, 40.0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.tooltip_text = caption
	control.accessibility_name = caption
	control.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		control.get_theme_stylebox(state).set_content_margin_all(SPACE_SM)
	return control


static func configure_scroll(control: ScrollContainer, flexible_width: bool = false) -> void:
	control.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if flexible_width else ScrollContainer.SCROLL_MODE_DISABLED
	control.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	control.follow_focus = true
	control.focus_mode = Control.FOCUS_ALL
	control.gui_input.connect(func(event: InputEvent) -> void: scroll_keyboard(control, event))
	var focus_follow := ScrollFocus.new()
	focus_follow.scroll = control
	control.add_child(focus_follow, false, Node.INTERNAL_MODE_BACK)


static func ensure_control_visible(scroll: ScrollContainer, control: Control) -> void:
	if not scroll.is_ancestor_of(control) or not control.is_visible_in_tree():
		return
	var content := scroll.get_child(0) as Control
	var panel := scroll.get_theme_stylebox("panel")
	var visible_height_px := maxf(scroll.size.y - panel.get_minimum_size().y, 0.0)
	var top_px := float(scroll.scroll_vertical)
	var bottom_px := top_px + visible_height_px
	var control_rect: Rect2 = content.get_global_transform().affine_inverse() * control.get_global_rect()
	if control_rect.size.y > visible_height_px or control_rect.position.y < top_px:
		scroll.scroll_vertical = maxi(floori(control_rect.position.y), 0)
	elif control_rect.end.y > bottom_px:
		scroll.scroll_vertical = maxi(ceili(control_rect.end.y - visible_height_px), 0)


static func scroll_keyboard(control: ScrollContainer, event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or not control.has_focus():
		return
	var next_offset_px := control.scroll_vertical
	var page_step_px := maxi(roundi(control.size.y) - SPACE_MD, SPACE_2XL)
	match key_event.keycode:
		KEY_UP:
			next_offset_px -= SPACE_2XL
		KEY_DOWN:
			next_offset_px += SPACE_2XL
		KEY_PAGEUP:
			next_offset_px -= page_step_px
		KEY_PAGEDOWN:
			next_offset_px += page_step_px
		KEY_HOME:
			next_offset_px = 0
		KEY_END:
			next_offset_px = ceili(control.get_v_scroll_bar().max_value)
		_:
			return
	control.scroll_vertical = maxi(next_offset_px, 0)
	control.accept_event()


static func style_button(control: Button, variant: StringName = &"default") -> void:
	var card_variant := variant == &"card"
	var primary := variant == &"primary"
	var padding_px := 0.0 if card_variant else float(SPACE_MD)
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
			box.content_margin_left = SPACE_LG
			box.content_margin_right = SPACE_LG
		control.add_theme_stylebox_override(states[state_index], box)
	var focus := style(Color.TRANSPARENT, padding_px, FOCUS, radius)
	focus.set_border_width_all(2)
	if not card_variant:
		focus.content_margin_left = SPACE_LG
		focus.content_margin_right = SPACE_LG
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
	input.custom_minimum_size.x = FIELD_WIDTH_PX
	fields.add_child(input)
	return input


static func foldout(parent: Node, caption: String) -> VBoxContainer:
	var content := column(parent, SPACE_SM)
	var toggle := Button.new()
	toggle.text = "+  " + caption
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.toggle_mode = true
	style_button(toggle)
	content.add_child(toggle)
	feedback(toggle)
	var details := column(content)
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
	var content := card(parent, SPACE_LG)
	content.add_theme_constant_override("separation", SPACE_XS)
	content.add_child(label(caption, 12, MUTED))
	var result := label(value, 26, color)
	content.add_child(result)
	return result
