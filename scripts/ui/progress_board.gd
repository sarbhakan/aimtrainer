class_name ProgressBoard
extends VBoxContainer

signal activity_requested(scenario_id: String)

const FAMILY_IDS: Array[String] = ["all", "click", "tracking", "switching"]
const FAMILY_TITLES: Array[String] = ["Toutes les familles", "Précision", "Suivi", "Transitions"]

var family_input: OptionButton
var activity_input: OptionButton
var summary_label: Label
var context_label: Label
var data_grid: GridContainer
var overview_grid: GridContainer
var chronology: GridContainer
var chronology_caption: Label
var empty_label: Label
var empty_button: Button
var selected_family: String = "all"
var selected_activity: String = "all"
var summaries: Array[Dictionary] = []
var displayed_summaries: Array[Dictionary] = []
var displayed_sessions: Array[Dictionary] = []
var comparable_count: int = 0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 10)
	filters.add_theme_constant_override("v_separation", 8)
	add_child(filters)
	family_input = OptionButton.new()
	for family_title in FAMILY_TITLES:
		family_input.add_item(family_title)
	family_input.tooltip_text = "Filtrer les séances par geste travaillé"
	filters.add_child(family_input)
	activity_input = OptionButton.new()
	activity_input.tooltip_text = "Filtrer les séances par activité"
	activity_input.custom_minimum_size.x = 210.0
	filters.add_child(activity_input)
	summary_label = AimUI.label("", 17)
	add_child(summary_label)
	context_label = AimUI.label("", 13, AimUI.MUTED)
	add_child(context_label)
	data_grid = GridContainer.new()
	data_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_grid.add_theme_constant_override("h_separation", 18)
	data_grid.add_theme_constant_override("v_separation", 14)
	add_child(data_grid)
	overview_grid = GridContainer.new()
	overview_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_grid.add_theme_constant_override("h_separation", 14)
	overview_grid.add_theme_constant_override("v_separation", 14)
	data_grid.add_child(overview_grid)
	var table_column := AimUI.column(data_grid, 14)
	chronology_caption = AimUI.label("Séances comparables · plus récentes d’abord", 17)
	table_column.add_child(chronology_caption)
	var table := AimUI.card(table_column, 14)
	chronology = GridContainer.new()
	chronology.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chronology.add_theme_constant_override("h_separation", 12)
	chronology.add_theme_constant_override("v_separation", 12)
	table.add_child(chronology)
	empty_label = AimUI.label("", 14, AimUI.MUTED)
	add_child(empty_label)
	empty_button = AimUI.button("Choisir une activité", func() -> void: activity_requested.emit(selected_activity), true)
	add_child(empty_button)
	family_input.item_selected.connect(func(index: int) -> void:
		selected_family = FAMILY_IDS[index]
		rebuild_activities()
		render())
	activity_input.item_selected.connect(func(index: int) -> void:
		selected_activity = str(activity_input.get_item_metadata(index))
		render())
	resized.connect(update_layout)
	rebuild_activities()
	render()


func configure(_total: int, supplied_summaries: Array[Dictionary]) -> void:
	summaries.clear()
	for supplied in supplied_summaries:
		var summary := supplied.duplicate(true)
		var definition := definition_for(summary)
		if definition != null:
			summary["scenario_id"] = definition.scenario_id
			summary["family"] = str(summary.get("family", definition.family))
			summary["title"] = str(summary.get("title", ScenarioCopy.title(definition)))
		summaries.append(summary)
	rebuild_activities()
	render()


func definition_for(summary: Dictionary) -> ScenarioDefinition:
	var scenario_id := str(summary.get("scenario_id", ""))
	if not scenario_id.is_empty():
		return ScenarioCatalog.find(scenario_id)
	for definition in ScenarioCatalog.DEFINITIONS:
		if summary.get("title", "") == ScenarioCopy.title(definition):
			return definition
	return null


func rebuild_activities() -> void:
	activity_input.clear()
	activity_input.add_item("Toutes les activités")
	activity_input.set_item_metadata(0, "all")
	var selected_index: int = 0
	for definition in ScenarioCatalog.DEFINITIONS:
		if selected_family != "all" and definition.family != selected_family:
			continue
		activity_input.add_item(ScenarioCopy.title(definition))
		var index := activity_input.item_count - 1
		activity_input.set_item_metadata(index, definition.scenario_id)
		if selected_activity == definition.scenario_id:
			selected_index = index
	activity_input.select(selected_index)
	selected_activity = str(activity_input.get_item_metadata(selected_index))


func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func render() -> void:
	clear_children(overview_grid)
	displayed_summaries.clear()
	displayed_sessions.clear()
	comparable_count = 0
	var identifiers: Dictionary = {}
	for summary in summaries:
		if selected_family != "all" and summary.get("family", "") != selected_family:
			continue
		if selected_activity != "all" and summary.get("scenario_id", "") != selected_activity:
			continue
		if int(summary.get("count", 0)) <= 0:
			continue
		displayed_summaries.append(summary)
		comparable_count += int(summary.count)
		build_overview(summary)
		var key := str(summary.get("comparison_key", ""))
		if key.is_empty():
			continue
		for session in summary.get("recent_sessions", []):
			if not session is Dictionary or session.get("comparison_key", "") != key:
				continue
			if not session.get("completed", true) or not session.get("valid", true) or session.get("warmup", false):
				continue
			if session.has("metrics") and not ScoringService.has_activity(session):
				continue
			if session.get("scenario_id", summary.get("scenario_id", "")) != summary.get("scenario_id", "") or session.get("family", summary.get("family", "")) != summary.get("family", ""):
				continue
			var identifier := str(session.get("session_id", ""))
			if not identifier.is_empty() and identifiers.has(identifier):
				continue
			if not identifier.is_empty():
				identifiers[identifier] = true
			var row: Dictionary = session.duplicate(true)
			row["summary"] = summary
			displayed_sessions.append(row)
	displayed_sessions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_stamp := str(left.get("created_at_utc", ""))
		var right_stamp := str(right.get("created_at_utc", ""))
		return left_stamp > right_stamp if left_stamp != right_stamp else str(left.get("session_id", "")) > str(right.get("session_id", "")))
	summary_label.text = "%d séance%s comparable%s avec les réglages et la durée choisis" % [comparable_count, "s" if comparable_count != 1 else "", "s" if comparable_count != 1 else ""]
	var context: Dictionary = displayed_summaries[0] if not displayed_summaries.is_empty() else summaries[0] if not summaries.is_empty() else {}
	context_label.text = context_text(context).replace("\n", " · ") if not context.is_empty() else "Choisissez une activité et une durée dans Entraînement."
	empty_label.visible = displayed_sessions.is_empty()
	empty_label.text = "Aucune séance comparable : lancez cette activité avec ces réglages et cette durée." if displayed_summaries.is_empty() else "Le détail chronologique de ces séances est indisponible."
	empty_button.visible = displayed_summaries.is_empty()
	empty_button.text = "Choisir une activité" if selected_activity == "all" else "S’entraîner à cette activité"
	chronology_caption.visible = not displayed_sessions.is_empty()
	chronology.get_parent().get_parent().visible = not displayed_sessions.is_empty()
	chronology_caption.get_parent().visible = not displayed_sessions.is_empty()
	render_chronology()
	update_layout()


func build_overview(summary: Dictionary) -> void:
	var card := AimUI.card(overview_grid, 16)
	card.add_theme_constant_override("separation", 8)
	card.add_child(AimUI.label(str(summary.get("title", "Activité")), 18))
	var values := AimUI.row(card, 10)
	for field in ["latest_score", "best", "latest_median"]:
		var stat := AimUI.column(values, 3)
		stat.add_child(AimUI.label({"latest_score": "Dernière séance", "best": "Meilleur score", "latest_median": "Médiane · jusqu’à 5"}[field], 11, AimUI.MUTED))
		var value: Variant = summary.get(field, null)
		stat.add_child(AimUI.label(AimUI.number(float(value), 0) if ScoringService.number(value) else "—", 24, AimUI.ACCENT if field == "latest_score" else AimUI.TEXT))
	var chart := ScoreChart.new()
	chart.custom_minimum_size.y = 100.0
	chart.score_values = summary.get("recent_scores", []).duplicate()
	card.add_child(chart)
	var change: Variant = summary.get("change_pct", null)
	var trend := "Tendance à partir de 10 séances comparables."
	if ScoringService.number(change):
		trend = "Évolution : %s%s %%" % ["+" if float(change) > 0.0 else "", AimUI.number(float(change), 1)]
	elif int(summary.count) >= 10:
		trend = "Tendance indisponible pour ces séances."
	var trend_label := AimUI.label(trend, 12, AimUI.MUTED)
	trend_label.tooltip_text = "Médiane des cinq dernières séances comparée aux cinq premières. Chaque activité garde son propre score."
	trend_label.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(trend_label)


func context_text(summary: Dictionary) -> String:
	var parts: Array[String] = []
	if ScoringService.number(summary.get("duration_s", null)):
		parts.append("%s s" % AimUI.number(float(summary.duration_s), 0))
	if ScoringService.number(summary.get("dpi", null)):
		parts.append("%s DPI" % AimUI.number(float(summary.dpi), 0))
	if ScoringService.number(summary.get("cm_per_360", null)):
		parts.append("%s cm/tour" % AimUI.number(float(summary.cm_per_360), 2))
	return " · ".join(parts) if not parts.is_empty() else "Même réglage et même durée"


func measurement_text(session: Dictionary) -> String:
	var metrics: Dictionary = session.get("metrics", session)
	if session.get("family", "") == "tracking":
		var ratio: Variant = metrics.get("on_target_ratio", null)
		return "%s %% du temps sur cible" % AimUI.number(float(ratio) * 100.0, 1) if ScoringService.number(ratio) else "Mesure indisponible"
	var accuracy: Variant = metrics.get("accuracy_fraction", null)
	var accuracy_pct: Variant = metrics.get("accuracy_pct", null)
	var cadence_hits_min: Variant = PerformanceInsights.hits_per_minute(metrics)
	var parts: Array[String] = []
	if ScoringService.number(accuracy):
		parts.append("%s %% de tirs réussis" % AimUI.number(float(accuracy) * 100.0, 1))
	elif ScoringService.number(accuracy_pct):
		parts.append("%s %% de tirs réussis" % AimUI.number(float(accuracy_pct), 1))
	if cadence_hits_min != null:
		parts.append("%s cibles/min" % AimUI.number(float(cadence_hits_min), 0))
	return "\n".join(parts) if not parts.is_empty() else "Mesure indisponible"


func date_text(stamp: String) -> String:
	return "%s/%s/%s · %s" % [stamp.substr(8, 2), stamp.substr(5, 2), stamp.substr(0, 4), stamp.substr(11, 5)] if stamp.length() >= 16 else "Date indisponible"


func cell(caption: String, heading: bool = false) -> void:
	chronology.add_child(AimUI.label(caption, 12, AimUI.MUTED if heading else AimUI.TEXT))


func render_chronology() -> void:
	clear_children(chronology)
	var wide := size.x >= 1000.0
	chronology.columns = 5 if wide else 3
	var headings: Array[String] = ["Date (UTC) · activité", "Score", "Mesure · contexte"]
	if wide:
		headings.assign(["Date (UTC)", "Activité", "Score", "Mesure", "Contexte"])
	for heading in headings:
		cell(heading, true)
	for session in displayed_sessions:
		var summary: Dictionary = session.summary
		var date := date_text(str(session.get("created_at_utc", "")))
		var title := str(summary.get("title", "Activité"))
		cell(date if wide else date + "\n" + title)
		if wide:
			cell(title)
		var score: Variant = session.get("score", null)
		cell(AimUI.number(float(score), 0) if ScoringService.number(score) else "—")
		cell(measurement_text(session) if wide else measurement_text(session) + "\n" + context_text(summary))
		if wide:
			cell(context_text(summary))


func update_layout() -> void:
	if overview_grid == null:
		return
	var alongside := size.x >= 1400.0 and not displayed_sessions.is_empty()
	data_grid.columns = 2 if alongside else 1
	var columns := 1 if alongside else 2 if size.x >= 760.0 else 1
	overview_grid.columns = mini(columns, maxi(displayed_summaries.size(), 1))
	if chronology.columns != (5 if size.x >= 1000.0 else 3):
		render_chronology()
