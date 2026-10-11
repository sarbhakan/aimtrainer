class_name SensitivityImport
extends VBoxContainer

signal profile_requested(profile: Dictionary)

var game_input: OptionButton
var dpi_input: SpinBox
var value_input: SpinBox
var title_input: LineEdit
var measurement_input: SpinBox
var cs2_yaw_input: SpinBox
var manual_fields: VBoxContainer
var cs2_fields: VBoxContainer
var preview_label: Label
var explanation_label: Label
var apply_button: Button
var current_profile: Dictionary = {}
var updating: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	add_child(AimUI.label("Je viens d’un autre jeu", 20))
	add_child(AimUI.label("Entrez votre réglage habituel. Il sera utilisé dans tous les exercices AIM/LOCAL.", 13, AimUI.MUTED))
	game_input = OptionButton.new()
	for title in GameProfileService.TITLES:
		game_input.add_item(title)
	game_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(game_input)
	dpi_input = AimUI.numeric(self, "DPI du jeu source", 1, 64000, 0.0)
	dpi_input.custom_arrow_step = 1.0
	dpi_input.allow_lesser = true
	dpi_input.allow_greater = true
	value_input = AimUI.numeric(self, "Sensibilité dans le jeu source", 0.000001, 100000.0, 0.0)
	value_input.custom_arrow_step = 0.001
	value_input.allow_lesser = true
	value_input.allow_greater = true
	manual_fields = AimUI.column(self, 10)
	manual_fields.add_child(AimUI.label("Titre et version du jeu", 13))
	title_input = LineEdit.new()
	title_input.placeholder_text = "Ex. Modern Warfare III (2023)"
	title_input.max_length = 96
	manual_fields.add_child(title_input)
	measurement_input = AimUI.numeric(manual_fields, "Distance mesurée dans le jeu source (cm)", 0, 150, 0.0)
	measurement_input.custom_arrow_step = 0.01
	measurement_input.allow_lesser = true
	measurement_input.allow_greater = true
	manual_fields.add_child(AimUI.label("Sans zoom, mesurez un tour complet avec une règle. Gardez les mêmes DPI et la sensibilité indiquée ci-dessus. CoD n’a pas un coefficient commun à toutes ses versions.", 13, AimUI.MUTED))
	cs2_fields = AimUI.foldout(self, "CS2 : m_yaw personnalisé")
	cs2_yaw_input = AimUI.numeric(cs2_fields, "m_yaw", 0.000001, 1.0, 0.0)
	cs2_yaw_input.custom_arrow_step = 0.000001
	cs2_yaw_input.allow_lesser = true
	cs2_yaw_input.allow_greater = true
	cs2_fields.add_child(AimUI.label("Gardez 0,022 si vous n’avez pas modifié m_yaw dans CS2.", 12, AimUI.MUTED))
	explanation_label = AimUI.label("", 12, AimUI.MUTED)
	add_child(explanation_label)
	preview_label = AimUI.label("", 16, AimUI.ACCENT)
	add_child(preview_label)
	apply_button = AimUI.button("Utiliser ce réglage dans AIM/LOCAL", request_import, true)
	add_child(apply_button)
	game_input.item_selected.connect(func(_index: int) -> void: select_game())
	for control in [dpi_input, value_input, measurement_input, cs2_yaw_input]:
		control.value_changed.connect(func(_value: float) -> void: update_preview())
	title_input.text_changed.connect(func(_text: String) -> void: update_preview())
	cs2_yaw_input.value = 0.022
	measurement_input.value = 0.0
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
		dpi_input.value = float(reference.dpi) if historical else float(current_profile.dpi)
		cs2_yaw_input.value = float(reference.yaw_deg) if historical and game_id == "cs2" else 0.022
		measurement_input.value = float(reference.source_cm_per_360) if historical else 0.0
		title_input.text = str(reference.title) if historical and game_input.selected >= 2 else ""
		var yaw_deg := GameProfileService.default_yaw(game_id)
		value_input.value = float(reference.sensitivity) if historical else SensitivityService.game_sensitivity(dpi_input.value, current_profile.cm_per_360, yaw_deg) if yaw_deg > 0.0 else 1.0
		updating = false
	manual_fields.visible = game_input.selected >= 2
	cs2_fields.get_parent().visible = game_input.selected == 0
	explanation_label.text = "Réglage source d’origine : l’import le rétablit, même si votre sensibilité AIM/LOCAL a changé." if historical else "Nouveau profil : recopiez les réglages du jeu source." if game_input.selected < 2 else "Nouveau profil : renseignez une mesure réelle, sans zoom. Aucun coefficient universel."
	explanation_label.text += "\nVos DPI AIM/LOCAL restent inchangés."
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
