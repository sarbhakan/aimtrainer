class_name TrainingPause
extends Control

signal sensitivity_requested(profile: Dictionary)
signal resume_requested
signal menu_requested

var resume_button: Button
var menu_button: Button
var apply_button: Button
var sensitivity_input: SensitivityImport.ReadableSpinBox
var unit_input: OptionButton
var editor: VBoxContainer
var context_label: Label
var notice_label: Label
var base_profile: Dictionary = {}
var canonical_cm_per_360: float = 35.0
var current_yaw_deg: float = SensitivityService.APP_YAW_DEG
var locked: bool = false


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.028, 0.045, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 440.0
	center.add_child(card)
	var content := AimUI.column(card, AimUI.SPACE_LG)
	content.add_child(AimUI.label("Pause", 24))
	context_label = AimUI.label("", 13, AimUI.MUTED)
	content.add_child(context_label)
	editor = AimUI.column(content, AimUI.SPACE_MD)
	var heading := AimUI.row(editor, AimUI.SPACE_MD)
	heading.add_child(AimUI.label("Sensibilité", 14))
	unit_input = OptionButton.new()
	for title in ["AIM/LOCAL", "Valorant", "CS2"]:
		unit_input.add_item(title)
	unit_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_input.fit_to_longest_item = false
	heading.add_child(unit_input)
	sensitivity_input = SensitivityImport.numeric(editor, "Valeur", 0.000001, 100000.0, 0.01)
	apply_button = AimUI.button("Appliquer et recommencer", request_sensitivity)
	apply_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	editor.add_child(apply_button)
	notice_label = AimUI.label("", 13, AimUI.MUTED)
	content.add_child(notice_label)
	var actions := AimUI.row(content, AimUI.SPACE_MD)
	resume_button = AimUI.button("Reprendre", resume_requested.emit, true)
	menu_button = AimUI.button("Menu", menu_requested.emit)
	for button in [resume_button, menu_button]:
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		actions.add_child(button)
	unit_input.item_selected.connect(select_unit)
	sensitivity_input.precise_value_changed.connect(update_sensitivity)
	set_process(false)


func bind(profile: Dictionary, comparison_locked: bool) -> void:
	base_profile = profile.duplicate(true)
	canonical_cm_per_360 = float(profile.cm_per_360)
	locked = comparison_locked
	editor.visible = not locked
	context_label.text = "%s DPI · sensibilité %s" % [AimUI.number(float(profile.dpi), 0), AimUI.sensitivity(SensitivityService.game_sensitivity(profile.dpi, canonical_cm_per_360, SensitivityService.APP_YAW_DEG))]
	unit_input.select(0)
	select_unit(0)
	if locked:
		notice_label.text = "Réglage fixé pour cette comparaison."
	resume_button.grab_focus()


func select_unit(index: int) -> void:
	current_yaw_deg = [SensitivityService.APP_YAW_DEG, 0.07, cs2_yaw_deg()][index]
	if not base_profile.is_empty():
		sensitivity_input.set_precise_value(SensitivityService.game_sensitivity(base_profile.dpi, canonical_cm_per_360, current_yaw_deg))
	refresh_notice()


func cs2_yaw_deg() -> float:
	var reference: Dictionary = base_profile.get("reference_game", {})
	return float(reference.yaw_deg) if reference.get("game_id", "") == "cs2" else 0.022


func update_sensitivity(value: float) -> void:
	canonical_cm_per_360 = SensitivityService.cm_per_360(float(base_profile.dpi), value * current_yaw_deg)
	refresh_notice()


func draft_profile() -> Dictionary:
	var profile := base_profile.duplicate(true)
	profile.cm_per_360 = canonical_cm_per_360
	return profile


func refresh_notice() -> void:
	if base_profile.is_empty():
		return
	var error := SensitivityService.validate_profile(draft_profile())
	apply_button.disabled = locked or not error.is_empty() or canonical_cm_per_360 == float(base_profile.cm_per_360)
	notice_label.text = "Réglage fixé pour cette comparaison." if locked else error if not error.is_empty() else "Le changement redémarre l’essai ; les scores restent séparés."


func request_sensitivity() -> void:
	if locked or apply_button.disabled:
		return
	sensitivity_requested.emit(draft_profile())


func set_error(message: String) -> void:
	notice_label.text = message
