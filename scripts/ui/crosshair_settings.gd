class_name CrosshairSettings
extends VBoxContainer

signal changed

var style_input: OptionButton
var size_input: SpinBox
var thickness_input: SpinBox
var gap_input: SpinBox
var color_input: ColorPickerButton
var outline_input: CheckButton
var preview: Panel
var current_profile: Dictionary = CrosshairProfile.defaults()
var updating: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(AimUI.label("Votre viseur", 20))
	add_child(AimUI.label("Ajustez sa forme et sa lisibilité avec cet aperçu en direct.", 13, AimUI.MUTED))
	preview = Panel.new()
	preview.custom_minimum_size = Vector2(180, 144)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override("panel", AimUI.style(Color("09121d"), 0.0))
	preview.draw.connect(draw_preview)
	add_child(preview)
	var style_row := AimUI.row(self)
	style_row.add_child(AimUI.label("Forme"))
	style_input = OptionButton.new()
	for caption in ["Point", "Croix", "Cercle", "T"]:
		style_input.add_item(caption)
	style_input.custom_minimum_size.x = 150.0
	style_row.add_child(style_input)
	size_input = AimUI.numeric(self, "Rayon / branche (px)", CrosshairProfile.MIN_SIZE_PX, CrosshairProfile.MAX_SIZE_PX, 0.0)
	thickness_input = AimUI.numeric(self, "Épaisseur (px)", CrosshairProfile.MIN_THICKNESS_PX, CrosshairProfile.MAX_THICKNESS_PX, 0.0)
	gap_input = AimUI.numeric(self, "Espace central (px)", CrosshairProfile.MIN_GAP_PX, CrosshairProfile.MAX_GAP_PX, 0.0)
	for control in [size_input, thickness_input, gap_input]:
		control.custom_arrow_step = 0.5
	var color_row := AimUI.row(self)
	color_row.add_child(AimUI.label("Couleur"))
	color_input = ColorPickerButton.new()
	color_input.custom_minimum_size = Vector2(150, 32)
	color_input.edit_alpha = true
	color_row.add_child(color_input)
	outline_input = CheckButton.new()
	outline_input.text = "Contour sombre"
	add_child(outline_input)
	style_input.item_selected.connect(func(_index: int) -> void: update_preview())
	for control in [size_input, thickness_input, gap_input]:
		control.value_changed.connect(func(_value: float) -> void: update_preview())
	color_input.color_changed.connect(func(_color: Color) -> void: update_preview())
	outline_input.toggled.connect(func(_enabled: bool) -> void: update_preview())
	configure(current_profile)


func configure(profile: Dictionary) -> void:
	var error := CrosshairProfile.validate(profile)
	if not error.is_empty():
		push_error(error)
		return
	current_profile = CrosshairProfile.resolve(profile)
	if style_input == null:
		return
	updating = true
	style_input.select(CrosshairProfile.STYLES.find(current_profile.crosshair_style))
	size_input.set_value_no_signal(float(current_profile.crosshair_size_px))
	thickness_input.set_value_no_signal(float(current_profile.crosshair_thickness_px))
	gap_input.set_value_no_signal(float(current_profile.crosshair_gap_px))
	color_input.color = Color.html(current_profile.crosshair_color)
	outline_input.set_pressed_no_signal(current_profile.crosshair_outline)
	updating = false
	update_style_fields()
	preview.queue_redraw()


func read_settings() -> Dictionary:
	if style_input == null:
		return current_profile.duplicate(true)
	return {"crosshair_style": CrosshairProfile.STYLES[style_input.selected], "crosshair_size_px": size_input.value,
		"crosshair_thickness_px": thickness_input.value, "crosshair_gap_px": gap_input.value,
		"crosshair_color": "#" + color_input.color.to_html(not is_equal_approx(color_input.color.a, 1.0)),
		"crosshair_outline": outline_input.button_pressed}


func update_preview() -> void:
	if updating:
		return
	current_profile = read_settings()
	update_style_fields()
	preview.queue_redraw()
	changed.emit()


func update_style_fields() -> void:
	thickness_input.editable = current_profile.crosshair_style != "dot"
	gap_input.editable = current_profile.crosshair_style in ["cross", "t"]


func draw_preview() -> void:
	CrosshairProfile.draw(preview, preview.size * 0.5, current_profile)
