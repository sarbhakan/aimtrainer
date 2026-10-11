class_name SensitivityImport
extends VBoxContainer

signal profile_requested(profile: Dictionary)

class ReadableSpinBox extends SpinBox:
	var display_input: LineEdit
	var display_decimals: int = 6
	var editing: bool = false
	var original_value: float = 0.0
	var original_text: String = ""

	func _ready() -> void:
		display_input = LineEdit.new()
		display_input.editable = false
		display_input.add_theme_stylebox_override("read_only", get_line_edit().get_theme_stylebox("normal"))
		display_input.add_theme_color_override("font_uneditable_color", get_line_edit().get_theme_color("font_color"))
		display_input.mouse_default_cursor_shape = Control.CURSOR_IBEAM
		add_child(display_input)
		get_line_edit().hide()
		get_line_edit().resized.connect(place_display)
		get_line_edit().focus_exited.connect(finish_edit)
		get_line_edit().text_submitted.connect(func(_text: String) -> void: finish_edit())
		display_input.gui_input.connect(func(event: InputEvent) -> void:
			if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("ui_accept"):
				begin_edit.call_deferred()
				display_input.accept_event())
		value_changed.connect(preserve_unedited_value)
		refresh_display()
		place_display.call_deferred()


	func place_display() -> void:
		display_input.position = get_line_edit().position
		display_input.size = get_line_edit().size


	func set_precise_value(next_value: float) -> void:
		original_text = ""
		if editing:
			editing = false
			get_line_edit().hide()
			display_input.show()
		set_value_no_signal(next_value)
		if display_input != null:
			refresh_display()


	func refresh_display() -> void:
		var caption := String.num(value, display_decimals)
		if caption.contains("."):
			caption = caption.rstrip("0").rstrip(".")
		display_input.text = caption
		display_input.caret_column = 0
		display_input.tooltip_text = "Valeur conservée : %s\nCliquez ou appuyez sur Entrée pour modifier la valeur précise." % get_line_edit().text


	func preserve_unedited_value(next_value: float) -> void:
		if not original_text.is_empty() and get_line_edit().text == original_text and next_value == original_text.to_float():
			set_value_no_signal(original_value)
		refresh_display.call_deferred()


	func begin_edit() -> void:
		if editing:
			return
		editing = true
		original_value = value
		original_text = get_line_edit().text
		display_input.hide()
		get_line_edit().show()
		get_line_edit().grab_focus()
		get_line_edit().select_all()
		get_line_edit().caret_column = 0


	func finish_edit() -> void:
		if not editing:
			return
		editing = false
		if get_line_edit().text == original_text:
			set_value_no_signal(original_value)
		get_line_edit().hide()
		display_input.show()
		refresh_display.call_deferred()


static func numeric(parent: Node, caption: String, minimum: float, maximum: float, arrow_step: float, decimals: int = 6) -> ReadableSpinBox:
	var fields := AimUI.row(parent)
	fields.add_child(AimUI.label(caption))
	var input := ReadableSpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 0.0
	input.custom_arrow_step = arrow_step
	input.allow_lesser = true
	input.allow_greater = true
	input.display_decimals = decimals
	input.custom_minimum_size.x = 150.0
	fields.add_child(input)
	return input

var game_input: OptionButton
var dpi_input: ReadableSpinBox
var value_input: ReadableSpinBox
var title_input: LineEdit
var measurement_input: ReadableSpinBox
var cs2_yaw_input: ReadableSpinBox
var manual_fields: VBoxContainer
var cs2_fields: VBoxContainer
var preview_label: Label
var explanation_label: Label
var apply_button: Button
var current_profile: Dictionary = {}
var updating: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	add_child(AimUI.label("Reprendre mon réglage de jeu", 20))
	game_input = OptionButton.new()
	for title in GameProfileService.TITLES:
		game_input.add_item(title)
	game_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(game_input)
	dpi_input = numeric(self, "DPI dans ce jeu", 1, 64000, 1.0)
	value_input = numeric(self, "Sensibilité dans ce jeu", 0.000001, 100000.0, 0.001)
	manual_fields = AimUI.column(self, 10)
	manual_fields.add_child(AimUI.label("Titre et version du jeu", 13))
	title_input = LineEdit.new()
	title_input.placeholder_text = "Ex. Modern Warfare III (2023)"
	title_input.max_length = 96
	manual_fields.add_child(title_input)
	measurement_input = numeric(manual_fields, "Distance mesurée pour un tour (cm)", 0, 150, 0.01)
	manual_fields.add_child(AimUI.label("Mesurez un tour à la règle, sans zoom, avec ces DPI et cette sensibilité.", 13, AimUI.MUTED))
	cs2_fields = AimUI.foldout(self, "CS2 : m_yaw personnalisé")
	cs2_yaw_input = numeric(cs2_fields, "m_yaw", 0.000001, 1.0, 0.000001)
	cs2_fields.add_child(AimUI.label("Gardez 0,022 si vous n’avez pas modifié m_yaw dans CS2.", 12, AimUI.MUTED))
	explanation_label = AimUI.label("", 12, AimUI.MUTED)
	add_child(explanation_label)
	preview_label = AimUI.label("", 16, AimUI.ACCENT)
	add_child(preview_label)
	apply_button = AimUI.button("Importer ce réglage", request_import, true)
	add_child(apply_button)
	game_input.item_selected.connect(func(_index: int) -> void: select_game())
	for control in [dpi_input, value_input, measurement_input, cs2_yaw_input]:
		control.value_changed.connect(func(_value: float) -> void: update_preview())
	title_input.text_changed.connect(func(_text: String) -> void: update_preview())
	cs2_yaw_input.set_precise_value(0.022)
	measurement_input.set_precise_value(0.0)
	bind_context(SensitivityService.default_profile())


func bind_context(profile: Dictionary) -> void:
	current_profile = profile.duplicate(true)
	var reference: Dictionary = profile.get("reference_game", {})
	game_input.select(maxi(0, GameProfileService.IDS.find(reference.get("game_id", "cs2"))))
	select_game()


func select_game(reset_value: bool = true) -> void:
	var game_id := GameProfileService.IDS[game_input.selected]
	var reference: Dictionary = current_profile.get("reference_game", {})
	var historical: bool = not reference.is_empty() and reference.get("game_id", "") == game_id
	if reset_value and not current_profile.is_empty():
		updating = true
		dpi_input.set_precise_value(float(reference.dpi) if historical else float(current_profile.dpi))
		cs2_yaw_input.set_precise_value(float(reference.yaw_deg) if historical and game_id == "cs2" else 0.022)
		measurement_input.set_precise_value(float(reference.source_cm_per_360) if historical else 0.0)
		title_input.text = str(reference.title) if historical and game_input.selected >= 2 else ""
		var yaw_deg := GameProfileService.default_yaw(game_id)
		value_input.set_precise_value(float(reference.sensitivity) if historical else SensitivityService.game_sensitivity(dpi_input.value, current_profile.cm_per_360, yaw_deg) if yaw_deg > 0.0 else 1.0)
		updating = false
	manual_fields.visible = game_input.selected >= 2
	cs2_fields.get_parent().visible = game_input.selected == 0
	explanation_label.text = "Réimporter restaure le réglage d’origine de ce jeu." if historical else "Recopiez les valeurs du jeu ; vérifiez la rotation après import." if game_input.selected < 2 else "Titre et mesure obligatoires : le coefficient dépend du jeu."
	update_preview()


func draft() -> Dictionary:
	return GameProfileService.import_profile(current_profile, GameProfileService.IDS[game_input.selected], dpi_input.value,
		value_input.value, title_input.text, measurement_input.value, cs2_yaw_input.value)


func update_preview() -> void:
	if updating or current_profile.is_empty():
		return
	var result := draft()
	apply_button.disabled = not result.error.is_empty()
	preview_label.text = result.error if not result.error.is_empty() else "AIM/LOCAL : %s · %s DPI actifs conservés" % [AimUI.number(SensitivityService.game_sensitivity(result.profile.dpi, result.profile.cm_per_360, SensitivityService.APP_YAW_DEG), 4), AimUI.number(float(result.profile.dpi), 0)]
	preview_label.add_theme_color_override("font_color", Color("f5c789") if not result.error.is_empty() else AimUI.ACCENT)


func request_import() -> void:
	var result := draft()
	if result.error.is_empty():
		profile_requested.emit(result.profile)
