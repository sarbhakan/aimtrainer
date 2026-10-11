class_name SessionPanel
extends Control

signal next_requested
signal retry_requested
signal menu_requested
signal apply_requested
signal refine_requested

var title_label: Label
var body_label: RichTextLabel
var comfort_input: SpinBox
var next_button: Button
var retry_button: Button
var apply_button: Button
var refine_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.065, 0.98)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 30)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 28)
	content.add_child(title_label)
	body_label = RichTextLabel.new()
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_label.add_theme_font_size_override("normal_font_size", 18)
	content.add_child(body_label)
	var comfort_row := HBoxContainer.new()
	content.add_child(comfort_row)
	var comfort_label := Label.new()
	comfort_label.text = "Confort : 1 très mauvais · 3 neutre · 5 très bon"
	comfort_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comfort_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comfort_row.add_child(comfort_label)
	comfort_input = SpinBox.new()
	comfort_input.min_value = 1
	comfort_input.max_value = 5
	comfort_input.value = 3
	comfort_row.add_child(comfort_input)
	var actions := HFlowContainer.new()
	content.add_child(actions)
	next_button = add_action(actions, "Passage suivant", func() -> void: next_requested.emit())
	retry_button = add_action(actions, "Rejouer", func() -> void: retry_requested.emit())
	apply_button = add_action(actions, "Appliquer la sensibilité conseillée", func() -> void: apply_requested.emit())
	refine_button = add_action(actions, "Affiner autour du meilleur réglage testé", func() -> void: refine_requested.emit())
	add_action(actions, "Retour à l'accueil", func() -> void: menu_requested.emit())


func add_action(parent: Container, caption: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(action)
	parent.add_child(control)
	return control


func present(title: String, body: String, calibration_step: bool = false) -> void:
	title_label.text = title
	body_label.text = body
	comfort_input.get_parent().visible = calibration_step
	comfort_input.value = 3
	next_button.visible = calibration_step
	next_button.disabled = calibration_step
	retry_button.visible = not calibration_step
	apply_button.hide()
	refine_button.hide()
	show()
