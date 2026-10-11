class_name SessionPanel
extends Control

signal next_requested
signal retry_requested
signal menu_requested
signal apply_requested
signal refine_requested

var title_label: Label
var subtitle_label: Label
var badge_label: Label
var hero_label: Label
var hero_caption: Label
var notice_label: Label
var body_label: RichTextLabel
var comfort_input: SpinBox
var comfort_row: VBoxContainer
var comfort_caption: Label
var comfort_buttons: Array[Button] = []
var progress: ProgressBar
var progress_label: Label
var stat_titles: Array[Label] = []
var stat_values: Array[Label] = []
var stats: HBoxContainer
var next_button: Button
var retry_button: Button
var apply_button: Button
var refine_button: Button
var details_toggle: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AimUI.backdrop(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var layout := AimUI.column(margin, 18)
	var header := AimUI.row(layout)
	var logo := AimUI.label("AIM/LOCAL", 17, AimUI.ACCENT)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(logo)
	header.add_child(AimUI.button("Retour au menu", func() -> void: menu_requested.emit()))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var content := AimUI.column(center, 14)
	content.custom_minimum_size.x = 600.0
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge_label = AimUI.label("", 11, AimUI.ACCENT)
	content.add_child(badge_label)
	title_label = AimUI.label("", 28)
	content.add_child(title_label)
	subtitle_label = AimUI.label("", 14, AimUI.MUTED)
	content.add_child(subtitle_label)
	var hero := AimUI.card(content, 20)
	hero_caption = AimUI.label("SCORE", 11, AimUI.MUTED)
	hero.add_child(hero_caption)
	hero_label = AimUI.label("", 42, AimUI.ACCENT)
	hero.add_child(hero_label)
	stats = AimUI.row(content, 12)
	for stat_index in 3:
		var stat := AimUI.card(stats, 16)
		var caption := AimUI.label("", 11, AimUI.MUTED)
		stat.add_child(caption)
		stat_titles.append(caption)
		var value := AimUI.label("", 23)
		stat.add_child(value)
		stat_values.append(value)
	progress_label = AimUI.label("", 12, AimUI.MUTED)
	content.add_child(progress_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 5.0
	progress.show_percentage = false
	content.add_child(progress)
	comfort_row = AimUI.column(content, 10)
	comfort_caption = AimUI.label("Ce réglage est-il confortable ?", 15)
	comfort_row.add_child(comfort_caption)
	var choices := AimUI.row(comfort_row, 8)
	comfort_input = SpinBox.new()
	comfort_input.min_value = 1
	comfort_input.max_value = 5
	comfort_input.value = 3
	comfort_input.hide()
	comfort_row.add_child(comfort_input)
	for comfort_index in 5:
		var value := comfort_index + 1
		var control := AimUI.button(str(value), func() -> void: select_comfort(value))
		control.toggle_mode = true
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.tooltip_text = ["Très inconfortable", "Inconfortable", "Neutre", "Confortable", "Très confortable"][comfort_index]
		choices.add_child(control)
		comfort_buttons.append(control)
	var comfort_help := AimUI.row(comfort_row)
	var uncomfortable := AimUI.label("1 · Inconfortable", 11, AimUI.MUTED)
	uncomfortable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comfort_help.add_child(uncomfortable)
	comfort_help.add_child(AimUI.label("5 · Très confortable", 11, AimUI.MUTED))
	notice_label = AimUI.label("", 13, Color("f5c789"))
	notice_label.hide()
	content.add_child(notice_label)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 8)
	content.add_child(actions)
	next_button = AimUI.button("Continuer  →", func() -> void: next_requested.emit(), true)
	actions.add_child(next_button)
	retry_button = AimUI.button("Rejouer  →", func() -> void: retry_requested.emit(), true)
	actions.add_child(retry_button)
	apply_button = AimUI.button("Utiliser ce réglage", func() -> void: apply_requested.emit(), true)
	actions.add_child(apply_button)
	refine_button = AimUI.button("Affiner le test", func() -> void: refine_requested.emit())
	actions.add_child(refine_button)
	var details := AimUI.foldout(content, "Voir les mesures détaillées")
	details_toggle = details.get_parent().get_child(0) as Button
	body_label = RichTextLabel.new()
	body_label.fit_content = true
	body_label.custom_minimum_size.y = 170.0
	details.add_child(body_label)


func select_comfort(value: int) -> void:
	comfort_input.value = value
	comfort_caption.text = "Votre confort : " + ["très inconfortable", "inconfortable", "neutre", "confortable", "très confortable"][value - 1]
	for index in comfort_buttons.size():
		comfort_buttons[index].set_pressed_no_signal(index + 1 == value)


func present(title: String, body: String, calibration_step: bool = false) -> void:
	title_label.text = title
	body_label.text = body
	subtitle_label.text = ""
	badge_label.text = "CALIBRATION" if calibration_step else "VOTRE SÉANCE"
	comfort_row.visible = calibration_step
	select_comfort(3)
	progress.visible = calibration_step
	progress_label.visible = calibration_step
	next_button.visible = calibration_step
	next_button.disabled = calibration_step
	retry_button.visible = not calibration_step
	apply_button.hide()
	refine_button.hide()
	notice_label.hide()
	details_toggle.button_pressed = false
	stats.show()
	show()
	AimUI.fade_in(self)


func present_result(report: Dictionary, details: String, calibration_step: bool, stage_index: int, stage_total: int) -> void:
	var definition := ScenarioCatalog.find(report.scenario_id)
	present(ScenarioCopy.title(definition), details, calibration_step)
	var metrics: Dictionary = report.metrics
	hero_caption.text = "ÉCHAUFFEMENT · NON NOTÉ" if report.get("warmup", false) else "SCORE" if report.completed else "SCORE PROVISOIRE · SÉANCE INTERROMPUE"
	hero_label.text = "Bien joué." if report.get("warmup", false) else "%.0f" % report.score
	subtitle_label.text = "Respirez un instant, puis indiquez votre confort." if calibration_step else "Gardez les mêmes réglages pour comparer votre prochaine séance."
	if report.family == "tracking":
		set_stat(0, "Temps sur cible", AimUI.number(100.0 * metrics.on_target_ratio, 1) + " %")
		set_stat(1, "Temps suivi", AimUI.number(metrics.on_target_time_s, 1) + " s")
		set_stat(2, "Retour sur cible", "—" if metrics.on_target_time_s <= 0.0 else "%.0f ms" % metrics.reacquisition_median_ms)
	else:
		set_stat(0, "Précision", "—" if metrics.accuracy_pct == null else AimUI.number(metrics.accuracy_pct, 1) + " %")
		set_stat(1, "Cibles touchées", str(int(metrics.hits)))
		set_stat(2, "Temps de visée", "—" if metrics.hits == 0 else "%.0f ms" % metrics.acquisition_median_ms)
	if calibration_step:
		progress.max_value = stage_total
		progress.value = stage_index
		progress_label.text = "Passage %d sur %d · votre progression est sauvegardée après Continuer." % [stage_index, stage_total]
	if not report.valid:
		set_notice("Ce passage ne compte pas : " + str(report.invalid_reason))
	elif not report.completed:
		set_notice("Séance interrompue : elle n’entre pas dans vos records.")
	elif not ScoringService.has_activity(report):
		set_notice("Pas assez d’activité pour comparer ce passage. Bougez le viseur et réessayez.")


func present_recommendation(recommendation: Dictionary, dpi: float, details: String) -> void:
	present("Votre sensibilité repère", details)
	badge_label.text = "BILAN DE CALIBRATION"
	var status: String = recommendation.status
	var messages := {
		"indicative": "Ce réglage se détache aujourd’hui. Essayez-le, puis confirmez-le un autre jour.",
		"uncertain": "Les résultats sont trop proches. Gardez votre réglage actuel et refaites le test un autre jour.",
		"insufficient": "Il manque des passages fiables. Terminez ou recommencez le test pour obtenir un conseil.",
		"uncomfortable": "Le meilleur score n’est pas confortable. Gardez votre réglage actuel."
	}
	subtitle_label.text = messages[status]
	hero_caption.text = "SENSIBILITÉ AIM/LOCAL" if status == "indicative" else "VOTRE RÉGLAGE RESTE INCHANGÉ"
	hero_label.text = AimUI.number(SensitivityService.game_sensitivity(dpi, float(recommendation.get("recommended_cm_per_360", 35.0)), SensitivityService.APP_YAW_DEG), 4)
	retry_button.hide()
	apply_button.visible = bool(recommendation.apply_allowed)
	refine_button.visible = status in ["indicative", "uncertain"]
	var candidates: Array = recommendation.get("candidates", [])
	if candidates.size() != 3:
		stats.hide()
		return
	set_stat(0, "Votre souris", "%d DPI" % int(dpi))
	var measured_passages: int = 0
	for trial in recommendation.get("trials", []):
		measured_passages += 1 if trial.get("scored", false) else 0
	set_stat(1, "Passages mesurés", str(measured_passages))
	set_stat(2, "Confort du conseil", AimUI.number(candidates[0].comfort_median, 1) + " / 5")
	if status != "indicative":
		set_stat(2, "Réglages testés", "3")
	if recommendation.boundary_best and status in ["indicative", "uncertain"]:
		set_notice("Le meilleur essai est au bord de la plage. Affiner permet d’explorer les réglages voisins.")


func set_stat(index: int, caption: String, value: String) -> void:
	stat_titles[index].text = caption
	stat_values[index].text = value
	stat_values[index].add_theme_color_override("font_color", AimUI.TEXT)


func set_notice(message: String) -> void:
	notice_label.text = message
	notice_label.visible = not message.is_empty()


func update_rest(remaining_s: float, last_stage: bool) -> void:
	next_button.text = "Respirez… %d s" % int(ceil(remaining_s)) if remaining_s > 0.0 else "Voir mon réglage  →" if last_stage else "Continuer  →"
