class_name AimDashboard
extends Control

signal calibration_requested
signal calibration_resume_requested
signal training_requested(scenario_id: String, duration_s: float)
signal profile_save_requested
signal history_requested
signal export_requested
signal test_requested
signal quit_requested

var dpi_input: SpinBox
var distance_input: SpinBox
var fov_input: SpinBox
var goal_input: OptionButton
var fps_input: OptionButton
var accumulated_input: CheckButton
var inverted_input: CheckButton
var scenario_input: OptionButton
var duration_input: OptionButton
var game_input: OptionButton
var destination_dpi: SpinBox
var yaw_input: SpinBox
var test_button: Button
var quit_button: Button
var calibration_button: Button
var resume_calibration_button: Button
var status_label: Label
var scenario_label: Label
var conversion_label: Label
var history_label: RichTextLabel
var conversion_value: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.05, 0.075)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := label("AIM/LOCAL", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	test_button = button("Test souris", func() -> void: test_requested.emit())
	header.add_child(test_button)
	quit_button = button("Quitter", func() -> void: quit_requested.emit())
	header.add_child(quit_button)
	layout.add_child(label("Votre DPI. Des exercices comparables. Une sensibilité conseillée, mesurée localement.", 17))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	build_profile_tab(page(tabs, "Calibration"))
	build_training_tab(page(tabs, "Exercices"))
	build_conversion_tab(page(tabs, "Convertir"))
	build_history_tab(page(tabs, "Progression"))
	status_label = label("Hors ligne · Godot 4.7.2 · Données dans user://aim_local", 15)
	layout.add_child(status_label)
	bind_profile(SensitivityService.default_profile())


func label(text: String, size: int = 18) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size", size)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return control


func button(text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	return control


func page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	return content


func numeric_row(parent: VBoxContainer, title: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := label(title)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.custom_minimum_size.x = 180.0
	row.add_child(input)
	return input


func build_profile_tab(content: VBoxContainer) -> void:
	content.add_child(label("Trouver votre sensibilité repère", 26))
	content.add_child(label("Indiquez les DPI configurés sur votre souris et votre distance de départ. Si vous débutez, 35 cm/360° sert de point de départ à affiner.", 17))
	dpi_input = numeric_row(content, "DPI déclarés (pas de détection automatique)", 1, 64000, 1)
	distance_input = numeric_row(content, "Distance de départ · cm / 360°", 5, 150, 0.001)
	fov_input = numeric_row(content, "Champ de vision vertical · degrés", 40, 110, 1)
	goal_input = OptionButton.new()
	for title in ["Polyvalent · 20 % par test", "Précision · 30/25/20/15/10 %", "Tracking · 10/10/10/35/35 %"]:
		goal_input.add_item(title)
	content.add_child(goal_input)
	fps_input = OptionButton.new()
	for title in ["Limite 144 FPS", "Limite 240 FPS", "Limite 60 FPS", "FPS illimités"]:
		fps_input.add_item(title)
	content.add_child(fps_input)
	accumulated_input = CheckButton.new()
	accumulated_input.text = "Accumulation d'input Godot (défaut ; comparer par mesure)"
	content.add_child(accumulated_input)
	inverted_input = CheckButton.new()
	inverted_input.text = "Inverser l'axe vertical"
	content.add_child(inverted_input)
	content.add_child(button("Enregistrer le profil", func() -> void: profile_save_requested.emit()))
	content.add_child(label("Micro-précision → grands flicks → switching → suivi fluide → strafes. Trois réglages (−10 %, référence, +10 %), trois répétitions. 15 familiarisations non notées, puis 45 passages mesurés. Ordre alterné, graines communes, repos et confort déclarés. Environ 16 min minimum ; interrompre et reprendre reste possible.", 17))
	calibration_button = button("DÉMARRER LA CALIBRATION", func() -> void: calibration_requested.emit())
	content.add_child(calibration_button)
	resume_calibration_button = button("Reprendre la calibration sauvegardée", func() -> void: calibration_resume_requested.emit())
	resume_calibration_button.hide()
	content.add_child(resume_calibration_button)
	content.add_child(label("Le résultat décrit cette séance et cet objectif. Une plage est proposée si les écarts sont faibles ; un nouveau test à un autre jour permet de vérifier la stabilité.", 16))


func build_training_tab(content: VBoxContainer) -> void:
	content.add_child(label("16 exercices · un moteur commun", 26))
	scenario_input = OptionButton.new()
	for definition in ScenarioCatalog.DEFINITIONS:
		scenario_input.add_item(definition.scenario_id + " · " + definition.title)
	content.add_child(scenario_input)
	scenario_label = label("", 18)
	content.add_child(scenario_label)
	scenario_input.item_selected.connect(func(_index: int) -> void: update_scenario())
	duration_input = OptionButton.new()
	for seconds in [30, 60, 15]:
		duration_input.add_item("Durée : %d secondes actives" % seconds)
	content.add_child(duration_input)
	content.add_child(button("LANCER L'EXERCICE", func() -> void:
		training_requested.emit(ScenarioCatalog.DEFINITIONS[scenario_input.selected].scenario_id, [30.0, 60.0, 15.0][duration_input.selected])))
	content.add_child(label("Les cibles, trajectoires et difficultés restent fixes. Les résultats affichent précision, cadence, acquisition, temps sur cible et erreurs en degrés. Un changement de réglage crée un autre contexte de progression.", 17))
	update_scenario()


func update_scenario() -> void:
	var definition := ScenarioCatalog.DEFINITIONS[scenario_input.selected]
	var rule := "Score : 1000 × proportion du temps sur cible." if definition.family == "tracking" else "Score : 1000 × cadence × précision² / cadence de référence, sans plafond artificiel."
	scenario_label.text = "%s\nCible %.2f° · %d active(s) · %s\n%s" % [definition.instructions,
		definition.angular_diameter_deg, definition.active_targets, definition.motion, rule]


func build_conversion_tab(content: VBoxContainer) -> void:
	content.add_child(label("Conserver la rotation physique", 26))
	content.add_child(label("Conversion du profil actuel par cm/360°, en hipfire. Les FOV, zooms et courbes d'accélération peuvent modifier le ressenti.", 17))
	game_input = OptionButton.new()
	for title in ["CS2 · m_yaw par défaut 0,022", "Valorant · coefficient documentaire 0,07", "Jeu manuel · coefficient connu"]:
		game_input.add_item(title)
	content.add_child(game_input)
	destination_dpi = numeric_row(content, "DPI dans le jeu de destination", 1, 64000, 1)
	yaw_input = numeric_row(content, "Coefficient yaw · °/count/unité de sensibilité", 0.0001, 1.0, 0.0001)
	conversion_label = label("", 20)
	content.add_child(conversion_label)
	content.add_child(button("Copier la sensibilité", func() -> void:
		if SensitivityService.positive(conversion_value):
			DisplayServer.clipboard_set("%.6f" % conversion_value)
			set_status("Sensibilité copiée. Renseignez-la manuellement dans le jeu.")))
	game_input.item_selected.connect(func(index: int) -> void:
		if index < 2:
			yaw_input.value = [0.022, 0.07][index]
		update_conversion())
	for input in [destination_dpi, yaw_input, dpi_input, distance_input]:
		input.value_changed.connect(func(_value: float) -> void: update_conversion())
	yaw_input.value = 0.022
	destination_dpi.value = 800


func update_conversion() -> void:
	if conversion_label == null:
		return
	conversion_value = SensitivityService.game_sensitivity(destination_dpi.value, distance_input.value, yaw_input.value)
	var rounded := snappedf(conversion_value, 0.000001)
	var actual_cm := SensitivityService.cm_per_360(destination_dpi.value, rounded * yaw_input.value)
	conversion_label.text = "Sensibilité : %.6f\nDistance demandée : %.2f cm/360° · après arrondi : %.4f cm/360°\nAIM/LOCAL : %.6f (une unité = 0,022°/count)\nFormule : 914,4 / (DPI destination × cm/360 × yaw)\nCS2 : m_yaw modifiable. Valorant : valeur documentaire, à vérifier en jeu.\nPour Call of Duty / ADS : utiliser un coefficient manuel validé pour le titre et la version." % [conversion_value, distance_input.value, actual_cm, SensitivityService.game_sensitivity(dpi_input.value, distance_input.value, SensitivityService.APP_YAW_DEG)]


func build_history_tab(content: VBoxContainer) -> void:
	content.add_child(label("Progression à conditions constantes", 26))
	content.add_child(button("Actualiser les résultats comparables", func() -> void: history_requested.emit()))
	content.add_child(button("Exporter les séances · CSV + JSON", func() -> void: export_requested.emit()))
	history_label = RichTextLabel.new()
	history_label.fit_content = true
	history_label.custom_minimum_size.y = 180
	history_label.text = "Aucune séance chargée. Les échauffements, abandons et conditions différentes sont exclus des comparaisons."
	content.add_child(history_label)
	content.add_child(label("La médiane des 5 dernières séances est comparée aux 5 premières après au moins 10 séances comparables. Le record et la régularité restent distincts. Une nouvelle sensibilité, durée ou difficulté ne peut pas gonfler artificiellement cette tendance.", 17))


func read_profile() -> Dictionary:
	return {"schema_version": 1, "dpi": dpi_input.value, "cm_per_360": distance_input.value,
		"vertical_fov_deg": fov_input.value, "goal": ["balanced", "precision", "tracking"][goal_input.selected],
		"accumulated_input": accumulated_input.button_pressed, "invert_y": inverted_input.button_pressed,
		"max_fps": [144, 240, 60, 0][fps_input.selected]}


func bind_profile(profile: Dictionary) -> void:
	dpi_input.value = float(profile.dpi)
	distance_input.value = float(profile.cm_per_360)
	fov_input.value = float(profile.vertical_fov_deg)
	goal_input.select(maxi(0, ["balanced", "precision", "tracking"].find(profile.get("goal", "balanced"))))
	fps_input.select(maxi(0, [144, 240, 60, 0].find(int(profile.get("max_fps", 144)))))
	accumulated_input.button_pressed = bool(profile.get("accumulated_input", true))
	inverted_input.button_pressed = bool(profile.get("invert_y", false))
	if destination_dpi != null:
		destination_dpi.value = float(profile.dpi)
	update_conversion()


func set_status(message: String) -> void:
	status_label.text = message
