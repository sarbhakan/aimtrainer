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
var result_grid: GridContainer
var context: VBoxContainer
var context_root: PanelContainer
var record_celebration: RecordCelebration
var guided_confirmation: CheckButton
var content_margin: MarginContainer
var main_layout: VBoxContainer
var result_scroll: ScrollContainer
var result_content: VBoxContainer
var actions: HFlowContainer
var details_content: VBoxContainer
var progressive_history_grid: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AimUI.backdrop(self)
	var margin := MarginContainer.new()
	content_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, AimUI.SPACE_XL)
	add_child(margin)
	var layout := AimUI.column(margin, AimUI.SPACE_LG)
	main_layout = layout
	var header := AimUI.row(layout)
	var logo := AimUI.label("AIM/LOCAL", 17, AimUI.ACCENT)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(logo)
	header.add_child(AimUI.button("Retour au menu", func() -> void: menu_requested.emit()))
	var scroll := ScrollContainer.new()
	result_scroll = scroll
	AimUI.configure_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	result_grid = GridContainer.new()
	result_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AimUI.grid_spacing(result_grid, AimUI.SPACE_XL)
	scroll.add_child(result_grid)
	var content := AimUI.column(result_grid)
	result_content = content
	badge_label = AimUI.label("", 11, AimUI.ACCENT)
	content.add_child(badge_label)
	title_label = AimUI.label("", 28)
	content.add_child(title_label)
	subtitle_label = AimUI.label("", 14, AimUI.MUTED)
	content.add_child(subtitle_label)
	var hero := AimUI.card(content)
	hero.add_theme_constant_override("separation", AimUI.SPACE_SM)
	hero_caption = AimUI.label("SCORE", 11, AimUI.MUTED)
	hero.add_child(hero_caption)
	hero_label = AimUI.label("", 42, AimUI.ACCENT)
	hero.add_child(hero_label)
	record_celebration = RecordCelebration.new()
	hero_label.add_child(record_celebration)
	guided_confirmation = CheckButton.new()
	guided_confirmation.text = "Je souhaite tester ce conseil."
	guided_confirmation.tooltip_text = "Conseil provisoire : confirmez le confort et les résultats un autre jour."
	guided_confirmation.toggled.connect(func(confirmed: bool) -> void:
		if guided_confirmation.visible:
			apply_button.disabled = not confirmed)
	hero.add_child(guided_confirmation)
	guided_confirmation.hide()
	stats = AimUI.row(content)
	for stat_index in 3:
		var stat := AimUI.card(stats, AimUI.SPACE_LG)
		stat.add_theme_constant_override("separation", AimUI.SPACE_SM)
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
	comfort_row = AimUI.column(content, AimUI.SPACE_SM)
	comfort_caption = AimUI.label("Ce réglage est-il confortable ?", 15)
	comfort_row.add_child(comfort_caption)
	var choices := AimUI.row(comfort_row, AimUI.SPACE_SM)
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
	var comfortable := AimUI.label("5 · Très confortable", 11, AimUI.MUTED)
	comfortable.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	comfort_help.add_child(comfortable)
	notice_label = AimUI.label("", 13, Color("f5c789"))
	notice_label.hide()
	content.add_child(notice_label)
	actions = AimUI.flow(layout)
	next_button = AimUI.button("Continuer  →", func() -> void: next_requested.emit(), true)
	actions.add_child(next_button)
	retry_button = AimUI.button("Rejouer  →", func() -> void: retry_requested.emit(), true)
	actions.add_child(retry_button)
	apply_button = AimUI.button("Utiliser ce réglage", func() -> void: apply_requested.emit(), true)
	actions.add_child(apply_button)
	refine_button = AimUI.button("Affiner le test", func() -> void: refine_requested.emit())
	actions.add_child(refine_button)
	var details := AimUI.foldout(content, "Voir les mesures détaillées")
	details_content = details
	details_toggle = details.get_parent().get_child(0) as Button
	body_label = RichTextLabel.new()
	body_label.fit_content = true
	body_label.scroll_active = false
	details.add_child(body_label)
	context = AimUI.card(result_grid)
	context_root = context.get_parent()
	resized.connect(update_layout)
	update_layout()


func update_layout() -> void:
	if result_grid != null:
		result_grid.columns = 2 if size.x >= 1100.0 else 1
		var padding := AimUI.SPACE_LG if size.y < 600.0 else AimUI.SPACE_XL
		for edge in ["left", "right", "top", "bottom"]:
			content_margin.add_theme_constant_override("margin_" + edge, padding)
		main_layout.add_theme_constant_override("separation", AimUI.SPACE_MD if size.y < 600.0 else AimUI.SPACE_LG)


func clear_context() -> void:
	progressive_history_grid = null
	for child in context.get_children():
		context.remove_child(child)
		child.queue_free()
	context_root.hide()


func select_comfort(value: int) -> void:
	comfort_input.value = value
	comfort_caption.text = "Votre confort : " + ["très inconfortable", "inconfortable", "neutre", "confortable", "très confortable"][value - 1]
	for index in comfort_buttons.size():
		comfort_buttons[index].set_pressed_no_signal(index + 1 == value)


func present(title: String, body: String, calibration_step: bool = false) -> void:
	record_celebration.stop()
	clear_context()
	for child in details_content.get_children():
		if child != body_label:
			details_content.remove_child(child)
			child.queue_free()
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
	next_button.text = "Continuer  →"
	retry_button.visible = not calibration_step
	retry_button.text = "Rejouer  →"
	retry_button.disabled = false
	AimUI.style_button(retry_button, &"primary")
	apply_button.hide()
	apply_button.disabled = false
	apply_button.text = "Utiliser ce réglage"
	guided_confirmation.hide()
	guided_confirmation.set_pressed_no_signal(false)
	refine_button.hide()
	notice_label.hide()
	details_toggle.text = "Voir les mesures détaillées"
	details_toggle.set_pressed_no_signal(false)
	details_content.hide()
	stats.show()
	for value in stat_values:
		value.tooltip_text = ""
	show()
	AimUI.fade_in(self)


func present_progressive_trial(report: Dictionary, details: String, trial_context: Dictionary) -> void:
	var scenario_id: String = str(trial_context.get("scenario_id", report.get("scenario_id", "")))
	var definition := ScenarioCatalog.find(scenario_id)
	var exercise_title: String = str(trial_context.get("title", ScenarioCopy.title(definition) if definition != null else scenario_id))
	present(exercise_title, details)
	var block_index: int = int(trial_context.get("block_index", 0))
	var trial_index: int = int(trial_context.get("trial_index", 0))
	var direction: String = str(trial_context.get("direction", "départ"))
	badge_label.text = "CALIBRATION · EXERCICE %d / 5 · ESSAI %d / 5" % [block_index + 1, trial_index + 1]
	hero_caption.text = "SCORE"
	hero_label.text = PerformanceInsights.display(report.get("score", null), 0)
	subtitle_label.text = "Sensibilité %s · %s" % [AimUI.sensitivity(float(trial_context.get("active_sensitivity", 0.0))), direction]
	show_raw_stats(report)
	progress.show()
	progress_label.show()
	var total_trials: int = int(trial_context.get("total_trials", 25))
	var completed_trials: int = int(trial_context.get("completed_trials", 0))
	progress.max_value = total_trials
	progress.value = completed_trials
	progress_label.text = "%d / %d mesures terminées · pause et reprise possibles" % [completed_trials, total_trials]
	next_button.show()
	next_button.disabled = false
	retry_button.text = "Rejouer pour corriger une erreur"
	retry_button.show()
	AimUI.style_button(retry_button, &"default")
	if not bool(report.get("valid", true)):
		next_button.disabled = true
		set_notice("Cet essai ne compte pas : " + str(report.get("invalid_reason", "mesure invalide")))
	elif not bool(report.get("completed", true)):
		next_button.disabled = true
		set_notice("Essai interrompu : rejouez pour terminer cette mesure.")
	context_root.show()
	context.add_child(AimUI.label("Les cinq sensibilités de cet exercice", 20))
	progressive_history_grid = show_progressive_candidates(context, trial_context.get("block_history", []))


func show_raw_stats(report: Dictionary) -> void:
	var metrics: Dictionary = report.get("metrics", {})
	if report.get("family", "") == "tracking":
		set_stat(0, "Temps sur cible", PerformanceInsights.display(float(metrics.get("on_target_ratio", 0.0)) * 100.0, 1, "%"))
		set_stat(1, "Suivi réussi", PerformanceInsights.display(metrics.get("on_target_time_s", null), 1, "s"))
		set_stat(2, "Écart moyen", PerformanceInsights.display(metrics.get("angular_error_mean_deg", null), 2, "°"))
		return
	var hits: Variant = metrics.get("hits", null)
	var misses: Variant = metrics.get("misses", null)
	set_stat(0, "Touches / ratés", "%s / %s" % [PerformanceInsights.display(hits, 0), PerformanceInsights.display(misses, 0)])
	set_stat(1, "Précision des tirs", PerformanceInsights.display(metrics.get("accuracy_pct", null), 1, "%"))
	set_stat(2, "Durée mesurée", PerformanceInsights.display(report.get("active_duration_s", null), 0, "s"))
	stat_values[0].tooltip_text = "Cibles touchées / tirs ratés."
	stat_values[1].tooltip_text = "Pourcentage des tirs qui touchent une cible ; indisponible sans tir."
	stat_values[2].tooltip_text = "Temps actif, hors préparation et pauses."


func show_progressive_candidates(parent: Node, history: Array) -> GridContainer:
	var candidates := GridContainer.new()
	candidates.columns = 5
	candidates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AimUI.grid_spacing(candidates, AimUI.SPACE_SM)
	parent.add_child(candidates)
	for trial_index in 5:
		var card := AimUI.card(candidates, AimUI.SPACE_SM)
		card.add_theme_constant_override("separation", AimUI.SPACE_XS)
		card.add_child(AimUI.label("Essai %d" % (trial_index + 1), 12, AimUI.MUTED))
		if trial_index >= history.size():
			card.add_child(AimUI.label("À venir", 13, AimUI.MUTED))
			continue
		var candidate: Dictionary = history[trial_index]
		var metrics: Dictionary = candidate.get("metrics", candidate)
		var candidate_sensitivity: Variant = candidate.get("sensitivity", null)
		var profile: Dictionary = candidate.get("profile", {})
		if candidate_sensitivity == null and profile.has("dpi") and profile.has("cm_per_360"):
			candidate_sensitivity = SensitivityService.game_sensitivity(float(profile.dpi), float(profile.cm_per_360), SensitivityService.APP_YAW_DEG)
		card.add_child(AimUI.label(AimUI.sensitivity(float(candidate_sensitivity)) if candidate_sensitivity != null else "—", 16, AimUI.ACCENT))
		card.add_child(AimUI.label("Score %s" % PerformanceInsights.display(candidate.get("score", null), 0), 12))
		if candidate.get("family", "") == "tracking":
			var ratio: Variant = metrics.get("on_target_ratio", null)
			card.add_child(AimUI.label("Sur cible %s" % PerformanceInsights.display(float(ratio) * 100.0 if ratio != null else null, 1, "%"), 11, AimUI.MUTED))
		else:
			card.add_child(AimUI.label("Touches %s" % PerformanceInsights.display(metrics.get("hits", null), 0), 11, AimUI.MUTED))
			card.add_child(AimUI.label("Ratés %s" % PerformanceInsights.display(metrics.get("misses", null), 0), 11, AimUI.MUTED))
			card.add_child(AimUI.label("Précision %s" % PerformanceInsights.display(metrics.get("accuracy_pct", null), 1, "%"), 11, AimUI.MUTED))
	return candidates


func present_progressive_complete(summary: Dictionary, dpi: float, details: String) -> void:
	present("Votre sensibilité", details)
	badge_label.text = "CALIBRATION TERMINÉE"
	hero_caption.text = "Votre sensibilité"
	var sensitivity: float = float(summary.get("recommended_sensitivity", SensitivityService.game_sensitivity(dpi, float(summary.get("recommended_cm_per_360", 35.0)), SensitivityService.APP_YAW_DEG)))
	hero_label.text = AimUI.sensitivity(sensitivity)
	subtitle_label.text = "Le réglage retenu d’après vos scores sur les cinq exercices."
	retry_button.hide()
	apply_button.text = "Appliquer"
	apply_button.visible = bool(summary.get("apply_allowed", false)) and summary.get("status", "") == "complete"
	var blocks: Array = summary.get("blocks", [])
	set_stat(0, "Exercices", str(blocks.size()))
	set_stat(1, "Essais mesurés", str(int(summary.get("tested_trials", 0))))
	set_stat(2, "Votre souris", "%d DPI" % int(dpi))
	context_root.show()
	context.add_child(AimUI.label("Vos cinq exercices", 20))
	for block in blocks:
		var scenario_id: String = str(block.get("scenario_id", ""))
		var definition := ScenarioCatalog.find(scenario_id)
		var exercise_title: String = str(block.get("title", ScenarioCopy.title(definition) if definition != null else scenario_id))
		var trials: Array = block.get("trials", [])
		context.add_child(AimUI.label("%s · %d essais" % [exercise_title, trials.size()], 14))
		details_content.add_child(AimUI.label(exercise_title, 16, AimUI.ACCENT))
		show_progressive_candidates(details_content, trials)
		var moving_range_cm: Array = block.get("moving_range_cm", [])
		if moving_range_cm.size() == 2:
			details_content.add_child(AimUI.label("Intervalle exploré : %s–%s cm/360°" % [AimUI.number(float(moving_range_cm[0])), AimUI.number(float(moving_range_cm[1]))], 12, AimUI.MUTED))
		details_content.add_child(AimUI.label("Utilités : " + progressive_utilities(trials), 12, AimUI.MUTED))


func progressive_utilities(trials: Array) -> String:
	var values := PackedStringArray()
	for trial in trials:
		values.append(PerformanceInsights.display(trial.get("utility", ScoringService.utility(trial) if trial.has("metrics") else null), 4))
	return " · ".join(values)


func present_routine_complete(reports: Array, details: String) -> void:
	present("Entraînement complet", details)
	badge_label.text = "BILAN D’ENTRAÎNEMENT"
	var completed_steps: int = 0
	for report in reports:
		completed_steps += 1 if bool(report.get("completed", false)) else 0
	hero_caption.text = "ÉTAPES TERMINÉES"
	hero_label.text = "%d / 3" % completed_steps
	subtitle_label.text = "Retrouvez vos mesures pour chaque exercice."
	stats.hide()
	retry_button.hide()
	context_root.show()
	context.add_child(AimUI.label("Vos résultats par étape", 20))
	for report in reports:
		var scenario_id: String = str(report.get("scenario_id", ""))
		var definition := ScenarioCatalog.find(scenario_id)
		var exercise_title: String = ScenarioCopy.title(definition) if definition != null else str(ScenarioCopy.TITLES.get(scenario_id, scenario_id))
		var card := AimUI.card(context, AimUI.SPACE_LG)
		card.add_child(AimUI.label(exercise_title, 16, AimUI.ACCENT))
		card.add_child(AimUI.label("Score %s" % PerformanceInsights.display(report.get("score", null), 0), 18))
		var metrics: Dictionary = report.get("metrics", {})
		card.add_child(AimUI.label("Touches %s · ratés %s · précision %s" % [PerformanceInsights.display(metrics.get("hits", null), 0), PerformanceInsights.display(metrics.get("misses", null), 0), PerformanceInsights.display(metrics.get("accuracy_pct", null), 1, "%")], 13, AimUI.MUTED))
		if report.get("family", "") == "tracking":
			var ratio: Variant = metrics.get("on_target_ratio", null)
			card.add_child(AimUI.label("Temps sur cible : %s" % PerformanceInsights.display(float(ratio) * 100.0 if ratio != null else null, 1, "%"), 13, AimUI.MUTED))
		if not bool(report.get("completed", false)):
			card.add_child(AimUI.label("Étape interrompue", 13, AimUI.MUTED))
		elif not bool(report.get("valid", true)):
			card.add_child(AimUI.label("Mesure invalide", 13, AimUI.MUTED))


func present_result(report: Dictionary, details: String, calibration_step: bool, stage_index: int, stage_total: int) -> void:
	var definition := ScenarioCatalog.find(report.scenario_id)
	present(ScenarioCopy.title(definition), details, calibration_step)
	var insights := PerformanceInsights.analyze(report)
	hero_caption.text = "ÉCHAUFFEMENT · NON NOTÉ" if report.get("warmup", false) else "SCORE" if report.completed else "SCORE PROVISOIRE · SÉANCE INTERROMPUE"
	hero_label.text = "Échauffement terminé" if report.get("warmup", false) else "%.0f" % report.score
	subtitle_label.text = "Respirez un instant, puis indiquez votre confort." if calibration_step else "Gardez les mêmes réglages pour comparer votre prochaine séance."
	set_stat(0, insights.primary_label, insights.primary_value)
	set_stat(1, insights.secondary_label, insights.secondary_value)
	set_stat(2, insights.tempo_label, insights.tempo_value)
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
	if not calibration_step:
		context_root.show()
		context.add_child(AimUI.label("Votre prochain essai", 20))
		context.add_child(AimUI.label(insights.get("short_tip", insights.tip), 15, AimUI.ACCENT))
		var exercise_preview := ScenarioPreview.new()
		exercise_preview.custom_minimum_size.y = 230.0
		context.add_child(exercise_preview)
		exercise_preview.configure(definition, true)


func present_record(previous_best: float, reduced_motion: bool) -> void:
	hero_caption.text = "NOUVEAU RECORD PERSONNEL"
	badge_label.text = "RECORD · MÊMES CONDITIONS"
	subtitle_label.text = "Votre précédent record : %.0f points. Ce résultat est enregistré." % previous_best
	record_celebration.celebrate(reduced_motion)


func present_guided_search(search: AdaptiveSensitivityService, can_continue: bool) -> void:
	badge_label.text = "RECHERCHE GUIDÉE · %d / %d COMPARAISONS" % [search.history.size(), AdaptiveSensitivityService.MAX_COMPARISONS]
	var measured_passages: int = 0
	for entry in search.history:
		for trial in entry.trials:
			measured_passages += 1 if trial.scored else 0
	set_stat(1, "Passages cumulés", str(measured_passages))
	refine_button.hide()
	retry_button.hide()
	next_button.visible = can_continue
	next_button.disabled = false
	next_button.text = "Continuer la recherche  →"
	apply_button.hide()
	if can_continue:
		title_label.text = "Une nouvelle plage à comparer"
		hero_caption.text = "MEILLEUR RÉGLAGE TESTÉ À CETTE ÉTAPE"
		var next_spec := search.current_spec()
		subtitle_label.text = "Prochaine étape : " + str(next_spec.label).split(" · ")[0]
	else:
		var result := search.final_result()
		subtitle_label.text = result.advice
		if result.get("trial_allowed", false):
			hero_caption.text = "SENSIBILITÉ À ESSAYER · CONSEIL PROVISOIRE"
			guided_confirmation.show()
			apply_button.show()
			apply_button.disabled = not guided_confirmation.button_pressed
			apply_button.text = "Essayer ce conseil"
	var history_card := AimUI.foldout(context, "Les étapes de votre recherche")
	for entry in search.history:
		var step: Dictionary = entry.search_step
		history_card.add_child(AimUI.label("%d · %s" % [int(step.spec.round_index) + 1, str(step.spec.label).split(" · ")[0]], 14, AimUI.ACCENT))
		var explanations := {"recenter": "Un réglage en bord de plage est meilleur et confortable : on déplace les essais autour de lui.",
			"refine": "Le centre se détache : on compare des réglages plus proches.",
			"validate": "Le choix reste cohérent : on vérifie une plage encore plus précise.",
			"stable": "Un conseil se détache après plusieurs comparaisons. Essayez-le, puis confirmez-le un autre jour.",
			"retest": "Les résultats ne permettent pas de choisir. Gardez votre réglage et retestez après repos.",
			"boundary": "Le meilleur essai reste au bord : cette recherche ne suffit pas pour conseiller un changement.",
			"limit": "La limite d’essais est atteinte. Faites une pause avant de reprendre une recherche."}
		history_card.add_child(AimUI.label(explanations.get(step.decision, step.reason), 13, AimUI.MUTED))


func present_calibration_context(calibration: CalibrationService, pending: Dictionary) -> void:
	clear_context()
	context_root.show()
	var stage := calibration.current_stage()
	var block_index: int = int(stage.block_index)
	badge_label.text = "COMPARAISON · EXERCICE %d / 5" % (block_index + 1)
	var phase := "Échauffement %d / 3" % (calibration.current_index % 12 + 1) if not stage.scored else "Série %d / 3 · passage %d / 3" % [int(stage.repetition) + 1, (calibration.current_index % 12 - 3) % 3 + 1]
	progress_label.text = "%s · passage %d / 60" % [phase, calibration.current_index + 1]
	subtitle_label.text = "Réglage %s · sensibilité AIM/LOCAL %s. Indiquez votre confort, puis continuez." % [["A", "B", "C"][int(stage.candidate_index)], AimUI.sensitivity(SensitivityService.game_sensitivity(calibration.baseline.dpi, calibration.candidate_profile(int(stage.candidate_index)).cm_per_360, SensitivityService.APP_YAW_DEG))]
	context.add_child(AimUI.label("Même exercice, trois réglages", 21))
	context.add_child(AimUI.label(ScenarioCopy.description(ScenarioCatalog.find(stage.scenario_id)), 14, AimUI.MUTED))
	for candidate in calibration.scenario_scores(stage.scenario_id, pending):
		var row := AimUI.card(context, AimUI.SPACE_LG)
		row.add_theme_constant_override("separation", AimUI.SPACE_SM)
		row.add_child(AimUI.label(candidate.label + "  ·  " + AimUI.sensitivity(candidate.sensitivity), 16, AimUI.ACCENT if int(candidate.candidate_index) == int(stage.candidate_index) else AimUI.TEXT))
		row.add_child(AimUI.label("%d / 3 passages notés · score médian %s" % [candidate.samples, "—" if candidate.median_score == null else "%.0f" % candidate.median_score], 13, AimUI.MUTED))
	context.add_child(AimUI.label("Les échauffements ne comptent pas. Le conseil final combine les cinq exercices et votre confort.", 13, AimUI.MUTED))
	retry_button.text = "Refaire ce passage"
	retry_button.show()
	retry_button.disabled = true


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
	hero_label.text = AimUI.sensitivity(SensitivityService.game_sensitivity(dpi, float(recommendation.get("recommended_cm_per_360", 35.0)), SensitivityService.APP_YAW_DEG))
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
	var summaries: Array = recommendation.get("scenario_results", [])
	if not summaries.is_empty():
		context_root.show()
		context.add_child(AimUI.label("Vos résultats par exercice", 21))
		context.add_child(AimUI.label("Scores médians de trois passages, sans les échauffements. Comparez les réglages sur une même ligne, pas les exercices entre eux.", 13, AimUI.MUTED))
		for summary in summaries:
			var card := AimUI.card(context, AimUI.SPACE_LG)
			card.add_child(AimUI.label(ScenarioCopy.title(ScenarioCatalog.find(summary.scenario_id)), 16))
			var results := AimUI.row(card)
			for candidate in summary.candidates:
				var candidate_index := int(candidate.candidate_index)
				AimUI.stat(results, "%s · %s" % [["A", "B", "C"][candidate_index], AimUI.sensitivity(float(candidate.sensitivity))], "—" if candidate.median_score == null else "%.0f" % candidate.median_score)


func set_stat(index: int, caption: String, value: String) -> void:
	stat_titles[index].text = caption
	stat_values[index].text = value
	stat_values[index].add_theme_color_override("font_color", AimUI.TEXT)


func set_notice(message: String) -> void:
	notice_label.text = message
	notice_label.visible = not message.is_empty()


func update_rest(remaining_s: float, last_stage: bool) -> void:
	next_button.text = "Respirez… %d s" % int(ceil(remaining_s)) if remaining_s > 0.0 else "Voir mon réglage  →" if last_stage else "Continuer  →"
