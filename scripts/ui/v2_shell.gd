class_name V2Shell
extends Control

signal practice_requested(program_id: String, difficulty: String)
signal calibration_requested(mode: String, settings: Dictionary)
signal profile_requested(profile: Dictionary)
signal history_requested
signal quit_requested
signal resume_requested
signal menu_requested
signal calibration_continue_requested
signal calibration_apply_requested(candidate: Dictionary)
signal calibration_undo_requested
signal calibration_level_adjustment_requested(task: String, difficulty: String)
signal preview_requested(program_id: String, difficulty: String)
signal preview_stop_requested
signal preview_pause_requested(paused: bool)

const Ui := preload("res://scripts/ui/aim_ui.gd")
const SensitivityEditor := preload("res://scripts/ui/sensitivity_import.gd")
const CrosshairEditor := preload("res://scripts/ui/crosshair_settings.gd")
const Crosshair := preload("res://scripts/presentation/crosshair_profile.gd")
const Weapons := preload("res://scripts/presentation/weapon_catalog.gd")
const PALETTE: Dictionary = {
	"background": Color("0b1119"), "surface": Color("121d29"),
	"raised": Color("1b2a3a"), "border": Color("314252"),
	"text": Color("f2f6fa"), "secondary": Color("a9bacb"),
	"accent": Color("42d9cb"), "amber": Color("ffb454"),
	"success": Color("81d6a5"), "caution": Color("ffca74"),
	"error": Color("ff8897")
}
const DIFFICULTIES: PackedStringArray = ["novice", "standard", "advanced"]
const DIFFICULTY_LABELS: PackedStringArray = ["Novice", "Standard", "Avancé"]
const OBJECTIVES: PackedStringArray = ["polyvalent", "acquisition", "tracking"]
const TASKS: PackedStringArray = ["CLICK", "SMOOTH", "REACTIVE", "SWITCH"]
const TASK_LABELS: PackedStringArray = ["Clic", "Suivi fluide", "Suivi réactif", "Transitions"]
const PROGRAM_COPY: Dictionary = {
	"EX01": {"title": "Acquisition", "goal": "Ajustez le geste, du micro au grand déplacement.", "phases": "Micro · Général · Amplitude"},
	"EX02": {"title": "Multicibles", "goal": "Organisez vos clics entre plusieurs cibles.", "phases": "Grille · Précision"},
	"EX03": {"title": "Temporisées", "goal": "Touchez chaque cible dans sa fenêtre de temps.", "phases": "Fixe · Rétrécissante"},
	"EX04": {"title": "Clic mobile", "goal": "Lisez le mouvement et interceptez la cible.", "phases": "Linéaire · Évasif · Arcs"},
	"EX05": {"title": "Suivi fluide", "goal": "Gardez le viseur sur une trajectoire continue.", "phases": "Horizontal · Vertical · Ellipse"},
	"EX06": {"title": "Suivi réactif", "goal": "Corrigez après les changements de vitesse.", "phases": "Suivi continu · 60 s"},
	"EX07": {"title": "Contrôle 3D", "goal": "Maintenez le contact quand la distance varie.", "phases": "Profondeur réelle · 60 s"},
	"EX08": {"title": "Transitions", "goal": "Acquérez, maintenez, détruisez, repartez.", "phases": "Statique · Mobile · Évasif"}
}
const CALIBRATION_TITLES: Dictionary = {
	"unstable_conditions": "Conditions de mesure insuffisantes",
	"incomplete": "Comparaison à terminer",
	"exploratory_only": "Un candidat à vérifier",
	"repeated_regression": "Le réglage actuel reste préférable sur ces essais",
	"repeated_improvement": "Un avantage retrouvé sur deux séances",
	"mixed_tradeoff": "Les gestes ne favorisent pas tous le même réglage",
	"close_observed": "Résultats proches dans cette comparaison",
	"undetermined": "Ces essais ne permettent pas de trancher"
}

class SignedEffectBar extends Control:
	var effect_points: float = 0.0
	var limit_points: float = 1.0

	func _draw() -> void:
		var track := Rect2(Vector2(0.0, 8.0), Vector2(size.x, 12.0))
		draw_style_box(Ui.style(PALETTE.raised, 0.0, PALETTE.raised, 4), track)
		var zero_px := size.x * 0.5
		var extent_px := clampf(effect_points / limit_points, -1.0, 1.0) * zero_px
		var fill := Rect2(Vector2(minf(zero_px, zero_px + extent_px), 8.0), Vector2(absf(extent_px), 12.0))
		if fill.size.x > 0.0:
			draw_rect(fill, PALETTE.accent if effect_points >= 0.0 else PALETTE.error)
		draw_line(Vector2(zero_px, 4.0), Vector2(zero_px, 24.0), PALETTE.secondary, 1.0)

var current_profile: Dictionary = {}
var calibration_state: Dictionary = {}
var history_rows: Array = []
var history_progress_groups: Array = []
var program_definitions: Dictionary = {}
var selected_program_id: String = ""
var selected_difficulty: String = "standard"
var current_page: String = "home"
var catalog_grid: GridContainer
var content_scroll: ScrollContainer
var page_content: VBoxContainer
var preview_host: Control
var start_button: Button
var profile_apply_button: Button
var calibration_continue_button: Button
var calibration_apply_button: Button
var calibration_undo_button: Button
var _pending_focus_parent: WeakRef
var calibration_express_button: Button
var calibration_confirmation_button: Button
var calibration_restart_button: Button
var calibration_eligibility_label: Label
var calibration_wait_label: Label
var calibration_next_date_label: Label
var profile_fields: Dictionary = {}
var level_buttons: Array[Button] = []
var calibration_level_inputs: Dictionary = {}
var calibration_adjustment_buttons: Dictionary = {}
var calibration_preflight_labels: Dictionary = {}
var objective_input: OptionButton
var ratio_input: OptionButton
var crosshair_settings: CrosshairEditor
var _main_margin: MarginContainer
var _sidebar: PanelContainer
var _compact_navigation: HFlowContainer
var _profile_label: Label
var _notice_label: Label
var _title_label: Label
var _subtitle_label: Label
var _page_root: VBoxContainer
var _preview_panel: PanelContainer
var _preview_caption: Label
var _preview_placeholder: Label
var _preview_pause_button: Button
var _readiness_label: Label
var _preview_id: String = ""
var _preview_difficulty: String = ""
var _preview_paused: bool = false
var _ready_states: Dictionary = {}
var _draft_profile: Dictionary = {}
var _calibration_draft: Dictionary = {"objective": "polyvalent", "ratio": 1.25, "levels": {"CLICK": "standard", "SMOOTH": "standard", "REACTIVE": "standard", "SWITCH": "standard"}}
var _navigation_buttons: Dictionary = {}
var _catalog_buttons: Dictionary = {}
var _responsive_grids: Array[GridContainer] = []
var _notice: String = ""
var _built: bool = false


static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	for font_kind in ["regular", "bold"]:
		var font_path := "res://assets/fonts/v2/DejaVuSans%s.ttf" % ("-Bold" if font_kind == "bold" else "")
		var font: Font
		if ResourceLoader.exists(font_path):
			font = load(font_path) as Font
		elif FileAccess.file_exists(font_path):
			var font_file := FontFile.new()
			font_file.data = FileAccess.get_file_as_bytes(font_path)
			font = font_file
		if font != null:
			if font_kind == "regular":
				result.default_font = font
			else:
				result.set_font("font", "Button", font)
	for control_type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var color: Color = PALETTE.raised if state != "disabled" else PALETTE.surface
			var border: Color = PALETTE.accent if state in ["hover", "pressed", "hover_pressed"] else PALETTE.border
			result.set_stylebox(state, control_type, Ui.style(color, 12.0, border, 8))
		var focus := Ui.style(Color.TRANSPARENT, 12.0, PALETTE.accent, 8)
		focus.set_border_width_all(2)
		result.set_stylebox("focus", control_type, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			result.set_color(state, control_type, PALETTE.text)
		result.set_color("font_disabled_color", control_type, PALETTE.secondary)
	result.set_color("font_color", "Label", PALETTE.text)
	result.set_color("font_color", "CheckButton", PALETTE.text)
	result.set_color("font_color", "LineEdit", PALETTE.text)
	result.set_color("font_uneditable_color", "LineEdit", PALETTE.secondary)
	for state in ["normal", "read_only"]:
		result.set_stylebox(state, "LineEdit", Ui.style(PALETTE.raised, 10.0, PALETTE.border, 6))
	var input_focus := Ui.style(Color.TRANSPARENT, 10.0, PALETTE.accent, 6)
	input_focus.set_border_width_all(2)
	result.set_stylebox("focus", "LineEdit", input_focus)
	result.set_stylebox("panel", "PanelContainer", Ui.style(PALETTE.surface, 24.0, PALETTE.border, 12))
	return result


func _ready() -> void:
	theme = make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = PALETTE.background
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	_sidebar = PanelContainer.new()
	_sidebar.custom_minimum_size.x = 232.0
	_sidebar.add_theme_stylebox_override("panel", Ui.style(PALETTE.surface, 16.0, PALETTE.surface, 0))
	layout.add_child(_sidebar)
	var sidebar_content := Ui.column(_sidebar, 24)
	sidebar_content.add_child(_label("AIM/LOCAL", 28, PALETTE.text, true))
	sidebar_content.add_child(_label("Entraînez le geste", 17, PALETTE.secondary))
	var navigation := Ui.column(sidebar_content, 12)
	_add_navigation(navigation, false)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_content.add_child(spacer)
	sidebar_content.add_child(_label("Disponible hors ligne", 17, PALETTE.secondary))
	sidebar_content.add_child(_button("Quitter", quit_requested.emit))
	_main_margin = MarginContainer.new()
	_main_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(_main_margin)
	var main_content := Ui.column(_main_margin, 16)
	_compact_navigation = Ui.flow(main_content, 8)
	_add_navigation(_compact_navigation, true)
	_profile_label = _label("", 17, PALETTE.secondary)
	main_content.add_child(_profile_label)
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Ui.configure_scroll(content_scroll, true)
	main_content.add_child(content_scroll)
	_page_root = Ui.column(content_scroll, 24)
	_notice_label = _label(_notice, 17, PALETTE.caution)
	_notice_label.visible = not _notice.is_empty()
	main_content.add_child(_notice_label)
	_build_preview()
	_built = true
	resized.connect(_reflow)
	_refresh_profile_label()
	_restore_page()
	_reflow()


func configure(catalog: Variant, profile: Dictionary, calibration_status: Dictionary = {}, history: Array = []) -> void:
	current_profile = profile.duplicate(true)
	_draft_profile = profile.duplicate(true)
	Ui.motion_enabled = not bool(_first(profile, ["reduced_motion", "reducedmotion"], false))
	calibration_state = calibration_status.duplicate(true)
	if history_rows != history:
		history_progress_groups.clear()
	history_rows = history.duplicate(true)
	program_definitions.clear()
	_ingest_catalog(catalog)
	_ready_states.clear()
	if _built:
		_refresh_profile_label()
		_restore_page()


func show_home() -> void:
	current_page = "home"
	if not _built:
		return
	_begin_page("Choisissez votre geste", "Huit programmes de 60 secondes. Un niveau fixe pour chaque séance.", "home")
	_preview_panel.reparent(self)
	_preview_panel.hide()
	_preview_caption.text = "Aperçu du programme"
	_preview_placeholder.text = "Survolez une carte ou donnez-lui le focus pour voir le geste."
	catalog_grid = _grid(page_content, 4)
	_catalog_buttons.clear()
	for program_id: String in PROGRAM_COPY:
		var copy: Dictionary = PROGRAM_COPY[program_id]
		var card := _card(catalog_grid, 20.0)
		card.add_child(_label(program_id + " · 60 s", 17, PALETTE.accent))
		card.add_child(_label(_program_title(program_id), 24, PALETTE.text, true))
		card.add_child(_label(str(copy.goal), 18))
		card.add_child(_label(str(copy.phases), 17, PALETTE.secondary))
		var prepare := _button("Préparer", show_preparation.bind(program_id))
		prepare.accessibility_name = "Préparer " + _program_title(program_id)
		prepare.mouse_entered.connect(_request_preview.bind(program_id, _default_difficulty(program_id)))
		prepare.focus_entered.connect(_request_preview.bind(program_id, _default_difficulty(program_id)))
		card.get_parent().mouse_entered.connect(_request_preview.bind(program_id, _default_difficulty(program_id)))
		card.add_child(prepare)
		_catalog_buttons[program_id] = prepare
	_reflow()
	_focus_page()


func show_preparation(program_id: String) -> void:
	if not PROGRAM_COPY.has(program_id):
		return
	selected_program_id = program_id
	selected_difficulty = _default_difficulty(program_id)
	current_page = "preparation"
	if _built:
		_render_preparation()


func set_practice_ready(program_id: String, difficulty: String, ready: bool, reason: String = "") -> void:
	if not PROGRAM_COPY.has(program_id) or not difficulty in DIFFICULTIES:
		return
	_ready_states[program_id + ":" + difficulty] = {"ready": ready, "reason": reason}
	_refresh_practice_readiness()


func set_preview_content(control: Control) -> void:
	if not _built or control == null or control == preview_host or control.is_ancestor_of(preview_host):
		return
	for child in preview_host.get_children():
		if child == _preview_placeholder or child == control:
			continue
		preview_host.remove_child(child)
	if control.get_parent() != null:
		control.reparent(preview_host)
	else:
		preview_host.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_placeholder.hide()
	_preview_pause_button.disabled = false


func stop_preview() -> void:
	if not _preview_id.is_empty():
		preview_stop_requested.emit()
	_preview_id = ""
	_preview_difficulty = ""
	_preview_paused = false
	if _preview_pause_button != null:
		_preview_pause_button.text = "Suspendre l’aperçu"
	if _built and current_page == "home":
		_preview_panel.hide()


func show_results(report: Dictionary) -> void:
	current_page = "results"
	set_meta("v2_report", report.duplicate(true))
	if not _built:
		return
	var program_id := str(_first(report, ["program_id", "exercise_id"], ""))
	var title := str(report.get("title", _program_title(program_id)))
	_begin_page(title + " · résultat", "Les mesures de chaque phase gardent leur propre sens.", "history")
	var metadata := _card(page_content)
	metadata.add_child(_label(_report_context(report), 17, PALETTE.secondary))
	metadata.add_child(_label(_validity_text(report), 18, PALETTE.caution if report.get("valid", null) == false else PALETTE.text))
	var phases := _array(_first(report, ["phase_reports", "phases"], []))
	if phases.is_empty() and report.has("metrics"):
		phases = [report]
	var phase_grid := _grid(page_content, 3)
	for phase_value: Variant in phases:
		if not phase_value is Dictionary:
			continue
		var phase: Dictionary = phase_value
		var card := _card(phase_grid)
		card.add_child(_label(str(_first(phase, ["title", "phase_title", "name", "phase_id", "id"], "Phase")), 24, PALETTE.text, true))
		var duration: Variant = _first(phase, ["active_duration_s", "completed_s", "duration_s"], null)
		if _is_number(duration):
			card.add_child(_label("Temps actif · " + _number(float(duration), 2) + " s", 17, PALETTE.secondary))
		if phase.get("complete", null) == false:
			card.add_child(_label("Phase incomplète · diagnostics conservés", 17, PALETTE.caution))
		_add_phase_metrics(card, phase, program_id)
	if phases.is_empty():
		page_content.add_child(_label("Les mesures de cette séance ne sont pas disponibles.", 20, PALETTE.secondary))
	var aggregate := _dict(report.get("aggregate", {}))
	var program_index: Variant = _first(report, ["program_index", "program_score", "contact_index", "useful_work_index"], _first(aggregate, ["program_index", "program_score", "contact_index", "useful_work_index"], null))
	if program_id in ["EX05", "EX06", "EX07", "EX08"] and _is_number(program_index):
		var index_card := _card(page_content)
		var index_label := "Indice de travail utile du programme" if program_id == "EX08" else "Indice de contact du programme"
		index_card.add_child(_label(index_label + " · " + _score_display(float(program_index), report.get("display_score", null)), 24, PALETTE.accent))
	var interpretation := str(_first(report, ["interpretation", "summary_text", "notice"], ""))
	if not interpretation.is_empty():
		_card(page_content).add_child(_label(interpretation))
	var actions := Ui.flow(page_content, 12)
	if PROGRAM_COPY.has(program_id):
		actions.add_child(_button("Rejouer", show_preparation.bind(program_id), true))
	actions.add_child(_button("Choisir un exercice", show_home))
	actions.add_child(_button("Historique", _open_history))
	_add_details(page_content, report)
	_reflow()
	_focus_page()


func show_history(rows: Array, progress_groups: Array = []) -> void:
	history_rows = rows.duplicate(true)
	history_progress_groups = progress_groups.duplicate(true)
	current_page = "history"
	if not _built:
		return
	_begin_page("Votre historique", "Comparez les séances réalisées dans les mêmes conditions.", "history")
	if history_rows.is_empty() and history_progress_groups.is_empty():
		var empty := _card(page_content)
		empty.add_child(_label("Votre première séance apparaîtra ici.", 24, PALETTE.text, true))
		empty.add_child(_label("Les exercices et les calibrations conservent leurs résultats séparément.", 18, PALETTE.secondary))
		empty.add_child(_button("Choisir un exercice", show_home, true))
	if not history_progress_groups.is_empty():
		page_content.add_child(_label("Records dans un même contexte", 24, PALETTE.text, true))
		_render_history_progress()
	if not history_rows.is_empty():
		page_content.add_child(_label("Rapports conservés", 24, PALETTE.text, true))
	for row_value: Variant in history_rows:
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var report := _dict(row.get("report", row))
		var card := _card(page_content, 16.0)
		var line := Ui.row(card, 16)
		var copy := Ui.column(line, 6)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := str(report.get("title", _program_title(str(report.get("program_id", "")))))
		if title.is_empty():
			title = "Audit de calibration" if report.has("task") or str(report.get("kind", "")).begins_with("calibration") else "Rapport local"
		copy.add_child(_label(title, 20, PALETTE.text, true))
		var context := _report_context(report)
		var recorded_at := str(_first(report, ["ended_utc", "started_utc"], ""))
		if not recorded_at.is_empty():
			context = recorded_at + " · " + context
		if row.get("namespace", "") == "legacy":
			context = "Archive antérieure · " + context
		copy.add_child(_label(context, 16, PALETTE.secondary))
		copy.add_child(_label(_validity_text(report), 16, PALETTE.secondary))
		line.add_child(_button("Ouvrir", show_results.bind(report)))
	_reflow()
	_focus_page()


func _render_history_progress() -> void:
	var families: Dictionary = {"click_v3": "C", "opportunities_v2": "P", "contact_v2": "T", "switch_work_v3": "S", "C": "C", "P": "P", "T": "T", "S": "S"}
	for group_value: Variant in history_progress_groups:
		if not group_value is Dictionary:
			continue
		var group: Dictionary = group_value
		var program_id := str(group.get("program_id", ""))
		var difficulty := str(group.get("difficulty", ""))
		var phase_id := str(group.get("phase_id", ""))
		var family := str(families.get(group.get("score_family", ""), ""))
		var count: Variant = group.get("context_count", null)
		if not PROGRAM_COPY.has(program_id) or not difficulty in DIFFICULTIES or family.is_empty() or not _is_number(count) or float(count) < 1.0 or float(count) != floorf(float(count)):
			continue
		if family != _score_family(program_id):
			continue
		if phase_id.is_empty() and not (program_id in ["EX05", "EX06", "EX07", "EX08"] and family in ["T", "S"]):
			continue
		var card := _card(page_content, 16.0)
		card.add_child(_label(_program_title(program_id) + " · " + _difficulty_label(difficulty), 22, PALETTE.text, true))
		var scope := "Indice de travail utile du programme S" if family == "S" else "Indice de contact du programme T"
		if not phase_id.is_empty():
			var phase_title := phase_id
			for phase_value: Variant in _array(_definition(program_id, difficulty).get("phases", [])):
				if phase_value is Dictionary and phase_value.get("id", "") == phase_id:
					phase_title = str(phase_value.get("title", phase_id))
					break
			scope = "Phase %s · famille %s" % [phase_title, family]
		card.add_child(_label(scope, 17, PALETTE.secondary))
		var best: Variant = group.get("best_score", null)
		if _is_number(best):
			card.add_child(_label("Record · " + _score_display(float(best)), 24, PALETTE.accent, true))
		var context := "Contexte · " + str(group.get("group_id", "")).left(12)
		var context_label := _label("%d séance%s comparables · %s" % [int(count), "s" if int(count) != 1 else "", context], 16, PALETTE.secondary)
		context_label.tooltip_text = "Contexte " + str(group.get("group_id", "")) + "\nDéfinition " + str(group.get("definition_hash", ""))
		card.add_child(context_label)
		var conditions := _dict(group.get("conditions", {}))
		var condition_parts := PackedStringArray()
		var dpi: Variant = conditions.get("declared_dpi", null)
		if _is_number(dpi):
			condition_parts.append(_number(float(dpi), 0) + " DPI")
		var gain_hex := str(conditions.get("gain_hex", ""))
		if not gain_hex.is_empty():
			condition_parts.append("Gain " + gain_hex)
		var field_of_view: Variant = conditions.get("vertical_fov_deg", null)
		if _is_number(field_of_view):
			condition_parts.append("FOV vertical " + _number(float(field_of_view), 2) + "°")
		var resolution := _array(conditions.get("render_resolution_px", []))
		if resolution.size() == 2 and _is_number(resolution[0]) and _is_number(resolution[1]):
			condition_parts.append("%d×%d" % [int(resolution[0]), int(resolution[1])])
		if not condition_parts.is_empty():
			var condition_label := _label(" · ".join(condition_parts), 16, PALETTE.secondary)
			condition_label.tooltip_text = JSON.stringify(conditions, "  ")
			card.add_child(condition_label)
		var first_median: Variant = group.get("first_five_median", null)
		var last_median: Variant = group.get("last_five_median", null)
		if int(count) >= 10 and _is_number(first_median) and _is_number(last_median):
			card.add_child(_label("Médianes · 5 premières %s → 5 dernières %s" % [_score_display(float(first_median)), _score_display(float(last_median))], 18))
		elif int(count) < 10:
			card.add_child(_label("La tendance nécessite dix séances complètes dans ce même contexte.", 16, PALETTE.secondary))
		var best_id := str(group.get("best_report_id", ""))
		if not best_id.is_empty():
			for row_value: Variant in history_rows:
				var report := _dict(_dict(row_value).get("report", row_value))
				if report.get("session_id", "") == best_id:
					card.add_child(_button("Voir le record", show_results.bind(report)))
					break


func set_notice(text: String) -> void:
	_notice = text
	if _notice_label != null:
		_notice_label.text = text
		_notice_label.visible = not text.is_empty()


func show_calibration(state: Dictionary) -> void:
	calibration_state = state.duplicate(true)
	current_page = "calibration"
	_sync_calibration_draft(state)
	if not _built:
		return
	var result := _dict(state.get("result", state))
	var status := str(result.get("status", ""))
	var stage := str(_first(state, ["stage", "step", "phase"], "preparation"))
	var reviewing := stage in ["preflight", "preflight_review"]
	var measuring := reviewing or stage in ["measurement", "measuring", "running", "acclimation", "recovery", "countdown", "preflight_adjustment"]
	var title := "Trouver un réglage qui vous convient"
	if reviewing:
		title = "Avant la comparaison"
	elif measuring:
		title = "Calibration · " + str(_first(state, ["day_label", "stage_label"], "Bloc en cours"))
	elif CALIBRATION_TITLES.has(status):
		title = str(CALIBRATION_TITLES[status])
	_begin_page(title, "Un réglage constant par bloc. Une confirmation sur deux jours.", "calibration")
	calibration_continue_button = null
	calibration_apply_button = null
	calibration_undo_button = null
	calibration_express_button = null
	calibration_confirmation_button = null
	calibration_restart_button = null
	calibration_eligibility_label = null
	calibration_wait_label = null
	calibration_next_date_label = null
	calibration_level_inputs.clear()
	calibration_adjustment_buttons.clear()
	calibration_preflight_labels.clear()
	objective_input = null
	ratio_input = null
	var baseline := _card(page_content, 20.0)
	baseline.add_child(_label("Votre point de départ", 17, PALETTE.secondary))
	baseline.add_child(_label(_profile_summary(), 24, PALETTE.text, true))
	if not measuring:
		baseline.add_child(_button("Vérifier le réglage", func() -> void: show_settings(current_profile)))
	if reviewing:
		_render_calibration_preflight(state)
	elif measuring:
		_render_calibration_measurement(state)
	elif CALIBRATION_TITLES.has(status):
		_render_calibration_result(result, state)
	else:
		_render_calibration_choices(state)
		_render_calibration_calendar(state)
		_render_calibration_start_actions(state)
	var notice := str(_first(state, ["notice", "reason", "status_text"], ""))
	if not notice.is_empty():
		page_content.add_child(_label(notice, 18, PALETTE.caution))
	var eligibility := str(_first(state, ["eligibility_text", "wait_text"], ""))
	if not eligibility.is_empty():
		calibration_eligibility_label = _label(eligibility, 18, PALETTE.secondary)
		page_content.add_child(calibration_eligibility_label)
	var wait_s: Variant = state.get("wait_remaining_s", null)
	if _is_number(wait_s) and float(wait_s) > 0.0:
		calibration_wait_label = _label("Attente restante · " + _duration(float(wait_s)), 17, PALETTE.secondary)
		page_content.add_child(calibration_wait_label)
	var eligible_at := str(_first(state, ["next_eligible_at", "eligible_at"], ""))
	if not eligible_at.is_empty():
		calibration_next_date_label = _label("Prochain départ autorisé · " + eligible_at, 17, PALETTE.secondary)
		page_content.add_child(calibration_next_date_label)
	if state.has("can_continue") or measuring or bool(state.get("plan_frozen", false)):
		calibration_continue_button = _button(str(state.get("continue_label", "Continuer le protocole")), _request_calibration_continue, true)
		calibration_continue_button.disabled = not bool(state.get("can_continue", false))
		calibration_continue_button.tooltip_text = str(_first(state, ["continue_reason", "eligibility_text", "reason"], "La disponibilité est vérifiée par le protocole."))
		page_content.add_child(calibration_continue_button)
	if bool(state.get("can_undo", false)):
		calibration_undo_button = _button("Revenir au réglage précédent", calibration_undo_requested.emit)
		page_content.add_child(calibration_undo_button)
	if bool(state.get("profile_locked", false)):
		calibration_restart_button = _button("Nouvelle comparaison", _request_calibration.bind("restart_express"))
		calibration_restart_button.disabled = bool(state.get("active", false))
		calibration_restart_button.tooltip_text = "Une nouvelle exploration conserve les mesures précédentes dans l’historique."
		page_content.add_child(calibration_restart_button)
	_reflow()
	_focus_page()


func update_calibration_availability(state: Dictionary) -> void:
	calibration_state = state.duplicate(true)
	if not _built or current_page != "calibration":
		return
	if is_instance_valid(calibration_express_button):
		calibration_express_button.disabled = not bool(state.get("can_start_express", state.get("ready", false)))
		calibration_express_button.tooltip_text = str(state.get("start_reason", "La préparation attend la disponibilité du protocole."))
	if is_instance_valid(calibration_confirmation_button):
		calibration_confirmation_button.disabled = not bool(state.get("can_start_confirmation", false))
		calibration_confirmation_button.tooltip_text = str(_first(state, ["confirmation_reason", "eligibility_text"], "Un candidat et un créneau autorisé sont nécessaires."))
	if is_instance_valid(calibration_restart_button):
		calibration_restart_button.disabled = bool(state.get("active", false)) or not bool(state.get("profile_locked", false))
	if is_instance_valid(calibration_continue_button):
		calibration_continue_button.disabled = not bool(state.get("can_continue", false))
		calibration_continue_button.tooltip_text = str(_first(state, ["continue_reason", "eligibility_text", "reason"], "La disponibilité est vérifiée par le protocole."))
	if is_instance_valid(calibration_apply_button):
		var result := _dict(state.get("result", state))
		var candidate := _dict(state.get("candidate", result.get("candidate", {})))
		calibration_apply_button.disabled = candidate.is_empty() or not bool(state.get("can_apply", result.get("can_apply", false)))
	if is_instance_valid(calibration_undo_button):
		calibration_undo_button.disabled = not bool(state.get("can_undo", false))
	if is_instance_valid(calibration_eligibility_label):
		calibration_eligibility_label.text = str(_first(state, ["eligibility_text", "wait_text"], ""))
	if is_instance_valid(calibration_wait_label):
		var wait_s: Variant = state.get("wait_remaining_s", null)
		calibration_wait_label.text = "Attente restante · " + _duration(float(wait_s)) if _is_number(wait_s) else ""
	if is_instance_valid(calibration_next_date_label):
		var eligible_at := str(_first(state, ["next_eligible_at", "eligible_at"], ""))
		calibration_next_date_label.text = "Prochain départ autorisé · " + eligible_at if not eligible_at.is_empty() else ""
	for input: OptionButton in calibration_level_inputs.values():
		if is_instance_valid(input):
			input.disabled = _plan_frozen()
	if is_instance_valid(objective_input):
		objective_input.disabled = _plan_frozen()
	if is_instance_valid(ratio_input):
		ratio_input.disabled = _plan_frozen()
	_refresh_calibration_preflight()


func show_settings(profile: Dictionary) -> void:
	current_profile = profile.duplicate(true)
	_draft_profile = profile.duplicate(true)
	current_page = "settings"
	if not _built:
		return
	_refresh_profile_label()
	_begin_page("Votre profil", "Réglez votre souris et votre présentation avant la séance.", "settings")
	profile_fields.clear()
	var locked := bool(calibration_state.get("profile_locked", false))
	var grid := _grid(page_content, 2)
	var sensitivity := _card(grid)
	sensitivity.add_child(_label("Souris et sensibilité", 24, PALETTE.text, true))
	_profile_number(sensitivity, "dpi", "DPI déclarés", 1.0, 64000.0, 1.0, 0, locked)
	_profile_number(sensitivity, "cm_per_360", "Distance pour un tour (cm/360°)", 0.000001, 100000.0, 0.1, 2, locked)
	_profile_number(sensitivity, "vertical_fov_deg", "Champ de vision vertical (°)", 1.0, 179.0, 0.1, 2, locked)
	_profile_toggle(sensitivity, "invert_y", "Inverser la souris verticale", false, locked)
	sensitivity.add_child(_label("Modifier les DPI déclarés ne change pas le réglage matériel de votre souris.", 17, PALETTE.secondary))
	var presentation := _card(grid)
	presentation.add_child(_label("Présentation", 24, PALETTE.text, true))
	var weapon_input := _option_field(presentation, "Arme", PackedStringArray(["Pulse", "Vector", "Classic"]))
	var weapon_ids := PackedStringArray(["pulse", "vector", "classic"])
	for weapon_index in Weapons.DEFINITIONS.size():
		weapon_input.set_item_text(weapon_index, Weapons.DEFINITIONS[weapon_index].title)
	var selected_weapon := weapon_ids.find(str(profile.get("weapon_id", "")))
	weapon_input.select(selected_weapon if selected_weapon >= 0 else -1)
	weapon_input.disabled = locked
	weapon_input.item_selected.connect(func(index: int) -> void:
		_draft_profile["weapon_id"] = weapon_ids[index]
		_refresh_profile_apply())
	profile_fields["weapon_id"] = weapon_input
	_profile_toggle(presentation, _existing_key(profile, ["show_weapon", "showweapon"], "show_weapon"), "Afficher l’arme", true, locked)
	_profile_toggle(presentation, _existing_key(profile, ["sound_enabled", "sound"], "sound_enabled"), "Sons", true, locked)
	_profile_toggle(presentation, _existing_key(profile, ["reduced_motion", "reducedmotion"], "reduced_motion"), "Animations réduites", false, locked)
	presentation.add_child(_label("Les mouvements des cibles restent identiques.", 17, PALETTE.secondary))
	var crosshair_card := _card(grid)
	crosshair_settings = CrosshairEditor.new()
	crosshair_card.add_child(crosshair_settings)
	var crosshair_profile := _dict(profile.get("crosshair", profile))
	if not Crosshair.validate(crosshair_profile).is_empty():
		crosshair_profile = {}
	crosshair_settings.configure(crosshair_profile)
	crosshair_settings.changed.connect(func() -> void:
		if profile.get("crosshair", null) is Dictionary:
			var nested := _dict(_draft_profile.get("crosshair", {})).duplicate(true)
			nested.merge(crosshair_settings.read_settings(), true)
			_draft_profile["crosshair"] = nested
		else:
			_draft_profile.merge(crosshair_settings.read_settings(), true)
		_refresh_profile_apply())
	_retoken_component(crosshair_settings, locked)
	if _is_number(profile.get("dpi", null)) and _is_number(profile.get("cm_per_360", null)):
		var import_card := _card(grid)
		var import_editor := SensitivityEditor.new()
		import_card.add_child(import_editor)
		var import_context := profile.duplicate(true)
		if import_context.has("reference_game") and not import_context.reference_game is Dictionary:
			import_context.erase("reference_game")
		import_editor.bind_context(import_context)
		import_editor.profile_requested.connect(func(candidate: Dictionary) -> void:
			if not bool(calibration_state.get("profile_locked", false)):
				profile_requested.emit(candidate.duplicate(true)))
		_retoken_component(import_editor, locked)
	var actions := Ui.flow(page_content, 12)
	profile_apply_button = _button("Enregistrer mon profil", _request_profile, true)
	actions.add_child(profile_apply_button)
	actions.add_child(_button("Retour aux exercices", show_home))
	_readiness_label = _label("", 17, PALETTE.secondary)
	page_content.add_child(_readiness_label)
	_refresh_profile_apply()
	_reflow()
	_focus_page()


func draft_profile() -> Dictionary:
	return _draft_profile.duplicate(true)


func calibration_settings() -> Dictionary:
	var settings := _calibration_draft.duplicate(true)
	settings["profile"] = current_profile.duplicate(true)
	return settings


func _restore_page() -> void:
	match current_page:
		"preparation":
			_render_preparation()
		"results":
			show_results(_dict(get_meta("v2_report", {})))
		"calibration":
			show_calibration(calibration_state)
		"history":
			show_history(history_rows, history_progress_groups)
		"settings":
			show_settings(current_profile)
		_:
			show_home()


func _begin_page(title: String, subtitle: String, navigation: String) -> void:
	stop_preview()
	if _preview_panel.get_parent() != self:
		_preview_panel.reparent(self)
	_preview_panel.hide()
	for child in _page_root.get_children():
		_page_root.remove_child(child)
		child.queue_free()
	_responsive_grids.clear()
	catalog_grid = null
	start_button = null
	profile_apply_button = null
	_readiness_label = null
	profile_fields.clear()
	crosshair_settings = null
	level_buttons.clear()
	_title_label = _label(title, 32, PALETTE.text, true)
	_page_root.add_child(_title_label)
	_subtitle_label = _label(subtitle, 20, PALETTE.secondary)
	_page_root.add_child(_subtitle_label)
	page_content = Ui.column(_page_root, 24)
	content_scroll.scroll_vertical = 0
	for key: String in _navigation_buttons:
		var buttons: Array = _navigation_buttons[key]
		for button: Button in buttons:
			button.set_pressed_no_signal(key == navigation)
	_reflow()


func _render_preparation() -> void:
	var copy := _dict(PROGRAM_COPY.get(selected_program_id, {}))
	_begin_page("Préparer · " + _program_title(selected_program_id), str(copy.get("goal", "")), "home")
	var levels := Ui.flow(page_content, 12)
	var group := ButtonGroup.new()
	for level_index in DIFFICULTIES.size():
		var difficulty := DIFFICULTIES[level_index]
		var button := _button(DIFFICULTY_LABELS[level_index], _choose_difficulty.bind(difficulty))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(difficulty == selected_difficulty)
		button.disabled = _definition(selected_program_id, difficulty).is_empty()
		button.tooltip_text = "Configuration non disponible." if button.disabled else "Niveau fixé pour les 60 secondes."
		levels.add_child(button)
		level_buttons.append(button)
	_mount_preview(page_content)
	_preview_caption.text = "Aperçu · " + _difficulty_label(selected_difficulty)
	_preview_placeholder.text = "Préparation de l’aperçu…"
	_render_phase_plan(page_content)
	var profile_card := _card(page_content, 20.0)
	profile_card.add_child(_label("Votre réglage · " + _profile_summary(), 18, PALETTE.secondary))
	var actions := Ui.flow(page_content, 12)
	start_button = _button("Démarrer · 60 s", _request_practice, true)
	actions.add_child(start_button)
	actions.add_child(_button("Retour au catalogue", _return_to_catalog))
	_readiness_label = _label("", 17, PALETTE.secondary)
	page_content.add_child(_readiness_label)
	_refresh_practice_readiness()
	_request_preview(selected_program_id, selected_difficulty)
	_reflow()
	_focus_page()


func _render_phase_plan(parent: Node) -> void:
	var definition := _definition(selected_program_id, selected_difficulty)
	var phases := _array(definition.get("phases", []))
	var grid := _grid(parent, 3)
	for phase_value: Variant in phases:
		if not phase_value is Dictionary:
			continue
		var phase: Dictionary = phase_value
		var card := _card(grid, 20.0)
		card.add_child(_label(str(_first(phase, ["title", "name", "id"], "Phase")), 24, PALETTE.text, true))
		var start: Variant = phase.get("start_s", null)
		var duration: Variant = phase.get("duration_s", null)
		if _is_number(start) and _is_number(duration):
			card.add_child(_label("%s–%s s" % [_number(float(start), 0), _number(float(start) + float(duration), 0)], 20, PALETTE.accent))
		elif _is_number(duration):
			card.add_child(_label(_number(float(duration), 0) + " s", 20, PALETTE.accent))
		var goal := str(_first(phase, ["goal", "instruction", "description"], ""))
		if not goal.is_empty():
			card.add_child(_label(goal, 18, PALETTE.secondary))
	if phases.is_empty():
		parent.add_child(_label("Le déroulement sera disponible avec la configuration du programme.", 18, PALETTE.secondary))


func _choose_difficulty(difficulty: String) -> void:
	if difficulty == selected_difficulty:
		return
	selected_difficulty = difficulty
	_render_preparation()


func _request_practice() -> void:
	_refresh_practice_readiness()
	if start_button == null or start_button.disabled:
		return
	stop_preview()
	practice_requested.emit(selected_program_id, selected_difficulty)


func _refresh_practice_readiness() -> void:
	if start_button == null or _readiness_label == null:
		return
	var state := _dict(_ready_states.get(selected_program_id + ":" + selected_difficulty, {}))
	var definition := _definition(selected_program_id, selected_difficulty)
	var duration: Variant = definition.get("duration_s", null)
	var valid_definition := not definition.is_empty() and _is_number(duration) and float(duration) == 60.0
	start_button.disabled = not valid_definition or not bool(state.get("ready", false))
	var reason := str(state.get("reason", ""))
	if reason.is_empty():
		reason = "Programme prêt · niveau fixé pour 60 s." if not start_button.disabled else "Préparation du programme en cours." if valid_definition else "Configuration de 60 secondes non disponible."
	_readiness_label.text = reason
	start_button.tooltip_text = reason


func _build_preview() -> void:
	_preview_panel = PanelContainer.new()
	_preview_panel.add_theme_stylebox_override("panel", Ui.style(PALETTE.surface, 16.0, PALETTE.border, 12))
	add_child(_preview_panel)
	var content := Ui.column(_preview_panel, 12)
	var heading := Ui.row(content, 12)
	_preview_caption = _label("Aperçu", 18, PALETTE.secondary)
	heading.add_child(_preview_caption)
	_preview_pause_button = _button("Suspendre l’aperçu", _toggle_preview)
	_preview_pause_button.disabled = true
	_preview_pause_button.add_theme_font_size_override("font_size", 16)
	heading.add_child(_preview_pause_button)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.custom_minimum_size.y = 180.0
	content.add_child(aspect)
	preview_host = Control.new()
	preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.add_child(preview_host)
	_preview_placeholder = _label("", 18, PALETTE.secondary)
	_preview_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_host.add_child(_preview_placeholder)
	_preview_panel.hide()


func _mount_preview(parent: Node) -> void:
	_preview_panel.reparent(parent)
	_preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_panel.show()


func _request_preview(program_id: String, difficulty: String) -> void:
	if _preview_id == program_id and _preview_difficulty == difficulty:
		return
	stop_preview()
	_preview_id = program_id
	_preview_difficulty = difficulty
	_preview_caption.text = _program_title(program_id) + " · " + _difficulty_label(difficulty) + " · aperçu"
	if current_page == "home":
		_preview_pause_button.text = "Pause"
		_preview_panel.show()
		_layout_home_preview()
	preview_requested.emit(program_id, difficulty)


func _toggle_preview() -> void:
	if _preview_id.is_empty():
		return
	_preview_paused = not _preview_paused
	_preview_pause_button.text = ("Reprendre" if _preview_paused else "Pause") if current_page == "home" else "Reprendre l’aperçu" if _preview_paused else "Suspendre l’aperçu"
	preview_pause_requested.emit(_preview_paused)


func _layout_home_preview() -> void:
	if current_page != "home" or _preview_id.is_empty() or _preview_panel.get_parent() != self:
		return
	var width_px := minf(400.0, size.x * 0.46)
	_preview_panel.size = Vector2(width_px, maxf(264.0, _preview_panel.get_combined_minimum_size().y))
	var trigger := _catalog_buttons.get(_preview_id, null) as Button
	var trigger_center := trigger.get_global_rect().get_center() - global_position if is_instance_valid(trigger) else size * 0.5
	var left_px := 16.0 if size.x < 900.0 else 272.0
	var horizontal_px := size.x - _preview_panel.size.x - 16.0 if trigger_center.x <= size.x * 0.5 else left_px
	var vertical_px := clampf(trigger_center.y - _preview_panel.size.y - 16.0, 112.0 if size.x < 900.0 else 56.0, maxf(size.y - _preview_panel.size.y - 32.0, 16.0))
	_preview_panel.position = Vector2(horizontal_px, vertical_px)


func _return_to_catalog() -> void:
	var previous_id := selected_program_id
	show_home()
	var trigger := _catalog_buttons.get(previous_id, null) as Button
	if trigger != null:
		trigger.grab_focus.call_deferred()


func _sync_calibration_draft(state: Dictionary) -> void:
	var settings := _dict(state.get("settings", state))
	var objective := str(settings.get("objective", ""))
	if objective in OBJECTIVES:
		_calibration_draft["objective"] = objective
	var ratio: Variant = settings.get("ratio", null)
	if _is_number(ratio) and float(ratio) in [1.25, 1.5]:
		_calibration_draft["ratio"] = float(ratio)
	var levels := _dict(_first(settings, ["levels", "difficulty_by_task", "task_difficulties"], {}))
	for task: String in TASKS:
		var difficulty := str(levels.get(task, ""))
		if difficulty in DIFFICULTIES:
			_calibration_draft.levels[task] = difficulty


func _plan_frozen() -> bool:
	return bool(calibration_state.get("profile_locked", false)) or bool(calibration_state.get("plan_frozen", false)) or bool(calibration_state.get("locked", false)) or not _dict(calibration_state.get("plan", {})).is_empty()


func _render_calibration_choices(state: Dictionary) -> void:
	var choices := _grid(page_content, 2)
	var objective_card := _card(choices)
	objective_card.add_child(_label("Votre objectif", 24, PALETTE.text, true))
	objective_input = _option_field(objective_card, "Gestes privilégiés", PackedStringArray(["Polyvalent", "Acquisition", "Suivi"]))
	objective_input.select(OBJECTIVES.find(str(_calibration_draft.objective)))
	objective_input.disabled = _plan_frozen()
	objective_input.item_selected.connect(func(index: int) -> void:
		if not _plan_frozen():
			_calibration_draft["objective"] = OBJECTIVES[index])
	ratio_input = _option_field(objective_card, "Rapport local", PackedStringArray(["×1,25", "×1,50"]))
	ratio_input.select(0 if float(_calibration_draft.ratio) == 1.25 else 1)
	ratio_input.disabled = _plan_frozen()
	ratio_input.item_selected.connect(func(index: int) -> void:
		if not _plan_frozen():
			_calibration_draft["ratio"] = [1.25, 1.5][index])
	objective_card.add_child(_label("Les réglages effectifs seront vérifiés avant la première mesure.", 17, PALETTE.secondary))
	var level_card := _card(choices)
	level_card.add_child(_label("Niveaux des quatre gestes", 24, PALETTE.text, true))
	for task_index in TASKS.size():
		var task := TASKS[task_index]
		var input := _option_field(level_card, TASK_LABELS[task_index], DIFFICULTY_LABELS)
		input.select(DIFFICULTIES.find(str(_calibration_draft.levels[task])))
		input.disabled = _plan_frozen()
		input.item_selected.connect(func(index: int) -> void:
			if not _plan_frozen():
				_calibration_draft.levels[task] = DIFFICULTIES[index])
		calibration_level_inputs[task] = input
	level_card.add_child(_label("Ces choix sont fixés avant la création du plan.", 17, PALETTE.secondary))
	var candidates := _array(_first(state, ["candidates", "effective_candidates"], []))
	if not candidates.is_empty():
		var candidate_card := _card(page_content)
		candidate_card.add_child(_label("Réglages effectivement proposés", 24, PALETTE.text, true))
		for candidate_value: Variant in candidates:
			if candidate_value is Dictionary:
				var candidate: Dictionary = candidate_value
				var value: Variant = _first(candidate, ["cm_per_360", "effective_cm_per_360"], null)
				if _is_number(value):
					candidate_card.add_child(_label(str(_first(candidate, ["label", "id"], "Réglage")) + " · " + _number(float(value), 2) + " cm/360°", 20, PALETTE.accent))
	else:
		page_content.add_child(_label("Les candidats seront affichés avant le départ du plan.", 17, PALETTE.secondary))


func _render_calibration_calendar(state: Dictionary) -> void:
	var calendar := _grid(page_content, 3)
	var budgets := _dict(_first(state, ["budgets", "duration_s"], {}))
	var steps: Array[Dictionary] = [
		{"title": "Express", "field": "express_three_gains", "duration_s": 696.0, "goal": "Comparer trois réglages. Une présélection à vérifier."},
		{"title": "Confirmation · jour 1", "field": "confirmation_per_day", "duration_s": 1008.0, "goal": "Comparer le départ et le candidat dans quatre blocs."},
		{"title": "Confirmation · jour 2", "field": "confirmation_per_day", "duration_s": 1008.0, "goal": "Reprendre un autre jour, avec l’ordre inversé."}
	]
	for step in steps:
		var card := _card(calendar)
		card.add_child(_label(str(step.title), 24, PALETTE.text, true))
		var supplied: Variant = budgets.get(step.field, step.duration_s)
		if _is_number(supplied):
			card.add_child(_label(_duration(float(supplied)), 28, PALETTE.accent, true))
		card.add_child(_label(str(step.goal), 18, PALETTE.secondary))
		card.add_child(_label("Durée programmée minimale, hors attentes et reprises.", 17, PALETTE.secondary))
	var waiting := _card(page_content, 20.0)
	waiting.add_child(_label("Prévoyez deux jours", 24, PALETTE.text, true))
	waiting.add_child(_label("La confirmation commence au moins 12 h après la fin de l’express. Le jour 2 se déroule à une autre date locale, 12 à 168 h après le départ du jour 1. Suggestion : le lendemain.", 18, PALETTE.secondary))


func _render_calibration_start_actions(state: Dictionary) -> void:
	var actions := Ui.flow(page_content, 12)
	calibration_express_button = _button("Préparer l’express", _request_calibration.bind("express"), true)
	calibration_express_button.disabled = not bool(state.get("can_start_express", state.get("ready", false)))
	calibration_express_button.tooltip_text = str(state.get("start_reason", "La préparation attend la disponibilité du protocole."))
	actions.add_child(calibration_express_button)
	calibration_confirmation_button = _button("Préparer la confirmation", _request_calibration.bind("confirmation"))
	calibration_confirmation_button.disabled = not bool(state.get("can_start_confirmation", false))
	calibration_confirmation_button.tooltip_text = str(_first(state, ["confirmation_reason", "eligibility_text"], "Un candidat et un créneau autorisé sont nécessaires."))
	actions.add_child(calibration_confirmation_button)


func _render_calibration_measurement(state: Dictionary) -> void:
	var card := _card(page_content)
	card.add_child(_label(str(_first(state, ["task_title", "task_label", "task"], "Bloc de calibration")), 28, PALETTE.text, true))
	var context := str(_first(state, ["period_label", "block_label", "progress_text"], ""))
	if not context.is_empty():
		card.add_child(_label(context, 20, PALETTE.secondary))
	var remaining: Variant = _first(state, ["remaining_s", "time_left_s"], null)
	if _is_number(remaining):
		card.add_child(_label("Temps restant · " + _duration(float(remaining)), 28, PALETTE.text, true))
	var instruction := str(_first(state, ["instruction", "instruction_text"], "Le réglage reste constant pendant ce bloc."))
	card.add_child(_label(instruction, 18, PALETTE.secondary))


func _render_calibration_preflight(state: Dictionary) -> void:
	page_content.add_child(_label("Ces diagnostics au réglage de départ servent seulement à vérifier les niveaux avant les mesures comparatives.", 18, PALETTE.secondary))
	var context := str(_first(state, ["instruction", "instruction_text", "progress_text"], ""))
	if not context.is_empty():
		page_content.add_child(_label(context, 18, PALETTE.secondary))
	var grid := _grid(page_content, 4)
	for task_index in TASKS.size():
		var task := TASKS[task_index]
		var card := _card(grid, 16.0)
		card.add_child(_label(TASK_LABELS[task_index], 22, PALETTE.text, true))
		var labels: Dictionary = {"utility": _label("", 20), "level": _label("", 17, PALETTE.secondary), "proposal": _label("", 17, PALETTE.secondary)}
		for label: Label in labels.values():
			card.add_child(label)
		calibration_preflight_labels[task] = labels
		var button := _button("Tester en 24 s", _request_calibration_level_adjustment.bind(task))
		button.tooltip_text = "Un test explicite de 24 s au réglage de départ. Le protocole valide le nouveau plan avant toute comparaison."
		card.add_child(button)
		calibration_adjustment_buttons[task] = button
	_refresh_calibration_preflight()


func _refresh_calibration_preflight() -> void:
	var preflight := _dict(calibration_state.get("preflight", {}))
	for task: String in calibration_adjustment_buttons:
		var proposal := _preflight_row(preflight.get("proposals", []), task)
		var record := _preflight_row(_first(preflight, ["records", "reports"], {}), task)
		var labels := _dict(calibration_preflight_labels.get(task, {}))
		var utility: Variant = _first(record, ["original_diagnostic_utility", "diagnostic_utility", "U", "utility"], proposal.get("diagnostic_utility", null))
		var level := str(_first(record, ["difficulty", "current_level", "level"], proposal.get("current_level", "")))
		var suggested := str(proposal.get("suggested_level", ""))
		if is_instance_valid(labels.get("utility", null)):
			labels.utility.text = "U diagnostique · " + _number(float(utility), 4) if _is_number(utility) else "Diagnostic non fourni"
		if is_instance_valid(labels.get("level", null)):
			labels.level.text = "Niveau testé · " + _difficulty_label(level) if level in DIFFICULTIES else ""
		if is_instance_valid(labels.get("proposal", null)):
			labels.proposal.text = "Proposition · " + _difficulty_label(suggested) if suggested in DIFFICULTIES else "Pas de proposition du protocole"
		var button: Button = calibration_adjustment_buttons[task]
		if is_instance_valid(button):
			button.disabled = not _can_adjust_calibration_level(task)
			button.text = "Tester %s · 24 s" % _difficulty_label(suggested) if suggested in DIFFICULTIES else "Tester en 24 s"


func _can_adjust_calibration_level(task: String) -> bool:
	var stage := str(calibration_state.get("stage", ""))
	var preflight := _dict(calibration_state.get("preflight", {}))
	var proposal := _preflight_row(preflight.get("proposals", []), task)
	var received: Variant = preflight.get("reports_received", null)
	if not task in TASKS or not stage in ["preflight", "preflight_review"]:
		return false
	if calibration_state.get("phase", "") != "express" or not bool(calibration_state.get("active", false)):
		return false
	if bool(preflight.get("levels_frozen", false)) or bool(proposal.get("levels_frozen", false)) or bool(preflight.get("requires_new_express", false)):
		return false
	if not _dict(preflight.get("pending_adjustment", {})).is_empty() or (_is_number(received) and float(received) != 4.0):
		return false
	return bool(proposal.get("can_adjust", false)) and proposal.get("suggested_level", "") in DIFFICULTIES


func _request_calibration_level_adjustment(task: String) -> void:
	if not _can_adjust_calibration_level(task):
		return
	var preflight := _dict(calibration_state.get("preflight", {}))
	var proposal := _preflight_row(preflight.get("proposals", []), task)
	calibration_level_adjustment_requested.emit(task, str(proposal.suggested_level))


static func _preflight_row(rows: Variant, task: String) -> Dictionary:
	if rows is Dictionary:
		return _dict(rows.get(task, {}))
	for row_value: Variant in _array(rows):
		if row_value is Dictionary and row_value.get("task", "") == task:
			return row_value
	return {}


func _render_calibration_result(result: Dictionary, state: Dictionary) -> void:
	var status := str(result.get("status", ""))
	var explanation := str(_first(result, ["explanation", "summary_text", "reason"], ""))
	if explanation.is_empty():
		var explanations: Dictionary = {
			"exploratory_only": "Ce candidat reste à comparer sur deux jours. Votre réglage actuel est conservé par défaut.",
			"repeated_improvement": "L’avantage observé concerne ces gestes et ces deux séances. Le changement reste votre choix.",
			"repeated_regression": "Les essais favorisent le réglage de départ. Il reste votre réglage par défaut.",
			"mixed_tradeoff": "Un bénéfice dans un geste peut accompagner une baisse dans un autre. Votre réglage actuel reste le choix par défaut.",
			"close_observed": "Les résultats sont proches dans ces essais. Cela ne démontre pas une équivalence.",
			"incomplete": "Les mesures conservées attendent la suite autorisée par le protocole.",
			"unstable_conditions": "Les conditions relevées ne permettent pas cette comparaison.",
			"undetermined": "Les observations disponibles ne permettent pas de recommander un changement."
		}
		explanation = str(explanations.get(status, ""))
	page_content.add_child(_label(explanation, 20, PALETTE.secondary))
	var candidate := _dict(_first(state, ["candidate"], result.get("candidate", {})))
	if not candidate.is_empty():
		var card := _card(page_content)
		card.add_child(_label("Candidat effectivement testé", 24, PALETTE.text, true))
		var value: Variant = _first(candidate, ["cm_per_360", "effective_cm_per_360"], null)
		if _is_number(value):
			card.add_child(_label(_number(float(value), 2) + " cm/360°", 32, PALETTE.accent, true))
		var gain: Variant = _first(candidate, ["gain_deg_per_relative_unit", "gain_deg_per_count", "degrees_per_relative_input_unit", "gain_deg"], null)
		if _is_number(gain):
			card.add_child(_label("Gain testé · " + String.num(float(gain), 17) + " °/unité relative", 17, PALETTE.secondary))
		elif gain is Dictionary and gain.get("decimal_roundtrip", null) is String:
			card.add_child(_label("Gain testé · " + str(gain.decimal_roundtrip) + " °/unité relative", 17, PALETTE.secondary))
	var effects := _array(_first(result, ["day_effects", "day_differences"], []))
	var limit_points := 1.0
	for effect_value: Variant in effects:
		var effect: Variant = _effect_value(effect_value)
		if _is_number(effect):
			limit_points = maxf(limit_points, absf(float(effect)))
	var supplied_limit: Variant = result.get("effect_scale_points", null)
	if _is_number(supplied_limit) and float(supplied_limit) > 0.0:
		limit_points = maxf(limit_points, float(supplied_limit))
	if not effects.is_empty():
		var effect_card := _card(page_content)
		effect_card.add_child(_label("Différences observées par jour", 24, PALETTE.text, true))
		effect_card.add_child(_label("Échelle commune · −%s à +%s points · zéro au centre" % [_number(limit_points, 2), _number(limit_points, 2)], 17, PALETTE.secondary))
		for effect_index in effects.size():
			var effect: Variant = _effect_value(effects[effect_index])
			if not _is_number(effect):
				continue
			var effect_row := Ui.row(effect_card, 12)
			var effect_data := _dict(effects[effect_index])
			var day_role: Variant = effect_data.get("day_role", effect_index + 1)
			var day_label := "Jour %d" % int(day_role) if _is_number(day_role) else "Jour %d" % (effect_index + 1)
			effect_row.add_child(_label(str(effect_data.get("label", day_label)), 17, PALETTE.secondary))
			var bar := SignedEffectBar.new()
			bar.custom_minimum_size = Vector2(80.0, 28.0)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.effect_points = float(effect)
			bar.limit_points = limit_points
			effect_row.add_child(bar)
			effect_row.add_child(_label(("+" if float(effect) >= 0.0 else "") + _number(float(effect), 2) + " pt", 20))
	var task_effects := _array(_first(result, ["task_effects", "tasks", "skills"], []))
	if task_effects.is_empty():
		for task_id: String in TASKS:
			var task_row: Dictionary = {"task": task_id}
			for effect_value: Variant in effects:
				if not effect_value is Dictionary:
					continue
				var day_role: Variant = effect_value.get("day_role", null)
				if not _is_number(day_role) or not float(day_role) in [1.0, 2.0]:
					continue
				var effect: Variant = _dict(effect_value.get("effects_pp", {})).get(task_id, null)
				if _is_number(effect):
					task_row["day_%d_points" % int(day_role)] = effect
			if task_row.size() > 1:
				task_effects.append(task_row)
	if not task_effects.is_empty():
		var task_grid := _grid(page_content, 4)
		for task_value: Variant in task_effects:
			if not task_value is Dictionary:
				continue
			var task: Dictionary = task_value
			var card := _card(task_grid)
			var task_id := str(_first(task, ["task", "id"], ""))
			var task_label := TASK_LABELS[TASKS.find(task_id)] if task_id in TASKS else "Geste"
			card.add_child(_label(str(_first(task, ["title", "label"], task_label)), 24, PALETTE.text, true))
			for day_index in [1, 2]:
				var effect: Variant = _first(task, ["day_%d_points" % day_index, "day_%d" % day_index], null)
				if _is_number(effect):
					card.add_child(_label("Jour %d · %s%s pt" % [day_index, "+" if float(effect) >= 0.0 else "", _number(float(effect), 2)], 20, PALETTE.accent if float(effect) >= 0.0 else PALETTE.error))
			_add_phase_metrics(card, task, "")
	var conditions: Variant = _first(result, ["conditions_text", "conditions", "flags"], null)
	if conditions is String and not conditions.is_empty():
		page_content.add_child(_label(conditions, 17, PALETTE.secondary))
	elif conditions is Array and not conditions.is_empty():
		page_content.add_child(_label("Conditions · " + ", ".join(PackedStringArray(conditions)), 17, PALETTE.secondary))
	var plan_id := str(_first(state, ["plan_id"], result.get("plan_id", "")))
	if not plan_id.is_empty():
		page_content.add_child(_label("Plan · " + plan_id, 17, PALETTE.secondary))
	var actions := Ui.flow(page_content, 12)
	calibration_apply_button = _button("Appliquer ce candidat", _request_calibration_apply, true)
	calibration_apply_button.disabled = candidate.is_empty() or not bool(state.get("can_apply", result.get("can_apply", false)))
	calibration_apply_button.tooltip_text = str(state.get("apply_reason", "L’application attend l’autorisation du protocole."))
	actions.add_child(calibration_apply_button)
	actions.add_child(_button("Conserver mon réglage", show_home))
	if status == "exploratory_only":
		calibration_confirmation_button = _button("Préparer la confirmation", _request_calibration.bind("confirmation"))
		calibration_confirmation_button.disabled = not bool(state.get("can_start_confirmation", false))
		calibration_confirmation_button.tooltip_text = str(state.get("eligibility_text", "Attendre au moins 12 h après l’express."))
		actions.add_child(calibration_confirmation_button)
	_add_details(page_content, result)


func _request_calibration(mode: String) -> void:
	var available := false
	match mode:
		"express":
			available = bool(calibration_state.get("can_start_express", calibration_state.get("ready", false)))
		"confirmation":
			available = bool(calibration_state.get("can_start_confirmation", false))
		"restart_express":
			available = not bool(calibration_state.get("active", false)) and bool(calibration_state.get("profile_locked", false))
	if available:
		calibration_requested.emit(mode, calibration_settings())


func _request_calibration_continue() -> void:
	if bool(calibration_state.get("can_continue", false)):
		calibration_continue_requested.emit()


func _request_calibration_apply() -> void:
	var result := _dict(calibration_state.get("result", calibration_state))
	var candidate := _dict(calibration_state.get("candidate", result.get("candidate", {})))
	if not candidate.is_empty() and bool(calibration_state.get("can_apply", result.get("can_apply", false))):
		calibration_apply_requested.emit(candidate.duplicate(true))


func _profile_number(parent: Node, field: String, caption: String, minimum: float, maximum: float, arrow_step: float, decimals: int, locked: bool) -> void:
	var input := SensitivityEditor.numeric(parent, caption, minimum, maximum, arrow_step, decimals)
	var value: Variant = current_profile.get(field, null)
	if _is_number(value):
		input.set_precise_value(float(value))
	input.editable = not locked
	input.get_line_edit().accessibility_name = caption
	if input.display_input != null:
		input.display_input.accessibility_name = caption
	input.precise_value_changed.connect(func(next_value: float) -> void:
		_draft_profile[field] = next_value
		_refresh_profile_apply())
	profile_fields[field] = input


func _profile_toggle(parent: Node, field: String, caption: String, fallback: bool, locked: bool) -> void:
	var input := CheckButton.new()
	input.text = caption
	input.custom_minimum_size.y = 44.0
	input.set_pressed_no_signal(bool(current_profile.get(field, fallback)))
	input.disabled = locked
	input.toggled.connect(func(enabled: bool) -> void:
		_draft_profile[field] = enabled
		_refresh_profile_apply())
	parent.add_child(input)
	profile_fields[field] = input


func _option_field(parent: Node, caption: String, titles: PackedStringArray) -> OptionButton:
	var row := Ui.row(parent, 12)
	row.add_child(_label(caption, 18, PALETTE.secondary))
	var input := OptionButton.new()
	input.custom_minimum_size = Vector2(150.0, 44.0)
	input.fit_to_longest_item = false
	input.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	input.accessibility_name = caption
	for title: String in titles:
		input.add_item(title)
	row.add_child(input)
	return input


func _refresh_profile_apply() -> void:
	if profile_apply_button == null:
		return
	var error := ""
	for field in ["dpi", "cm_per_360", "vertical_fov_deg"]:
		var value: Variant = _draft_profile.get(field, null)
		if not _is_number(value) or float(value) <= 0.0:
			error = "Renseignez des valeurs positives pour les DPI, la distance et le champ de vision."
			break
	if error.is_empty() and float(_draft_profile.get("vertical_fov_deg", 0.0)) >= 180.0:
		error = "Le champ de vision vertical doit rester inférieur à 180°."
	var locked := bool(calibration_state.get("profile_locked", false))
	profile_apply_button.disabled = locked or not error.is_empty() or _draft_profile == current_profile
	if _readiness_label != null:
		_readiness_label.text = "Le profil est fixé pour ce plan de calibration." if locked else error if not error.is_empty() else "Le profil sera enregistré après validation de vos réglages."


func _request_profile() -> void:
	_refresh_profile_apply()
	if profile_apply_button != null and not profile_apply_button.disabled:
		profile_requested.emit(draft_profile())


func _retoken_component(parent: Node, locked: bool) -> void:
	for child in parent.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", maxi(16, child.get_theme_font_size("font_size")))
			child.add_theme_color_override("font_color", PALETTE.secondary)
		elif child is Panel:
			child.add_theme_stylebox_override("panel", Ui.style(PALETTE.raised, 0.0, PALETTE.border, 8))
		elif child is BaseButton:
			child.disabled = child.disabled or locked
		elif child is SpinBox:
			child.editable = child.editable and not locked
		elif child is LineEdit and locked:
			child.editable = false
		_retoken_component(child, locked)


static func _effect_value(value: Variant) -> Variant:
	if value is Dictionary:
		return _first(value, ["points", "difference_points", "value", "effect_points", "composite_pp"], null)
	return value if _is_number(value) else null


static func _existing_key(data: Dictionary, fields: Array, fallback: String) -> String:
	for field: String in fields:
		if data.has(field):
			return field
	return fallback


static func _duration(seconds: float) -> String:
	var whole_seconds := maxi(ceili(seconds), 0)
	if whole_seconds >= 3600:
		return "%d h %02d min" % [whole_seconds / 3600, (whole_seconds % 3600) / 60]
	return "%d min %02d s" % [whole_seconds / 60, whole_seconds % 60]


func _add_phase_metrics(parent: Node, phase: Dictionary, program_id: String) -> void:
	var metrics := _dict(phase.get("metrics", phase))
	var score_data: Variant = _first(phase, ["phase_score", "score"], _first(metrics, ["phase_score", "score"], null))
	var family := str(_first(phase, ["score_family", "family"], _score_family(program_id))).to_upper()
	var score: Variant = score_data
	var display_score: Variant = phase.get("display_score", null)
	if score_data is Dictionary:
		family = str(score_data.get("family", family)).to_upper()
		score = score_data.get("value", null)
		display_score = score_data.get("display_score", display_score)
	if _is_number(score) and family in ["C", "P", "T", "S"]:
		parent.add_child(_label("Score de phase " + family + " · " + _score_display(float(score), display_score), 24, PALETTE.accent, true))
	var fields: Dictionary = {
		"hits": "Cibles touchées", "shots": "Tirs", "misses": "Tirs ratés", "expired": "Expirations",
		"opportunities": "Opportunités", "kills": "Cibles détruites", "on_target_s": "Contact (s)",
		"contact_s": "Contact (s)", "exposed_s": "Exposition (s)", "exposure_s": "Exposition (s)",
		"contact_lower_s": "Borne basse du contact (s)", "contact_upper_s": "Borne haute du contact (s)",
		"median_acquisition_ms": "Acquisition médiane (ms)", "acquisition_p50_ms": "Acquisition médiane (ms)",
		"credited_work": "Travail crédité", "partial_damage": "Dégâts partiels"
	}
	var displayed := false
	for field: String in fields:
		var value: Variant = metrics.get(field, null)
		if _is_number(value):
			_measurement(parent, str(fields[field]), _number(float(value), 2 if field.ends_with("_s") or field in ["partial_damage", "credited_work"] else 0))
			displayed = true
	for field in ["accuracy", "contact_ratio", "success_ratio"]:
		var value: Variant = metrics.get(field, null)
		if _is_number(value):
			var caption: String = {"accuracy": "Précision", "contact_ratio": "Contact", "success_ratio": "Réussite"}[field]
			_measurement(parent, caption, _number(float(value) * 100.0, 1) + " %")
			displayed = true
	if not displayed and not _is_number(score):
		parent.add_child(_label("Mesures non disponibles.", 17, PALETTE.secondary))


func _ingest_catalog(value: Variant, inherited_id: String = "", inherited_difficulty: String = "") -> void:
	if value is Array:
		for item: Variant in value:
			_ingest_catalog(item, inherited_id, inherited_difficulty)
		return
	if not value is Dictionary:
		return
	var data: Dictionary = value
	var program_id := str(_first(data, ["program_id", "id"], inherited_id)).to_upper()
	var difficulty := str(_first(data, ["difficulty", "level"], inherited_difficulty)).to_lower()
	if PROGRAM_COPY.has(program_id) and difficulty in DIFFICULTIES:
		var definitions := _dict(program_definitions.get(program_id, {}))
		definitions[difficulty] = data.duplicate(true)
		program_definitions[program_id] = definitions
	for field in ["programs", "catalog", "cards", "configurations", "difficulties", "levels"]:
		if data.has(field) and (data[field] is Array or data[field] is Dictionary):
			_ingest_catalog(data[field], program_id, difficulty)
	for key: Variant in data:
		var key_text := str(key)
		if PROGRAM_COPY.has(key_text.to_upper()):
			_ingest_catalog(data[key], key_text.to_upper(), difficulty)
		elif key_text.to_lower() in DIFFICULTIES:
			_ingest_catalog(data[key], program_id, key_text.to_lower())


func _definition(program_id: String, difficulty: String) -> Dictionary:
	return _dict(_dict(program_definitions.get(program_id, {})).get(difficulty, {}))


func _default_difficulty(program_id: String) -> String:
	if not _definition(program_id, selected_difficulty).is_empty():
		return selected_difficulty
	for difficulty: String in ["standard", "novice", "advanced"]:
		if not _definition(program_id, difficulty).is_empty():
			return difficulty
	return "standard"


func _program_title(program_id: String) -> String:
	var definition := _definition(program_id, _default_difficulty(program_id))
	return str(definition.get("title", _dict(PROGRAM_COPY.get(program_id, {})).get("title", "Séance")))


func _profile_summary() -> String:
	var parts := PackedStringArray()
	for field: String in {"dpi": "DPI", "cm_per_360": "cm/360°"}:
		var value: Variant = current_profile.get(field, null)
		if _is_number(value):
			parts.append(_number(float(value), 0 if field == "dpi" else 2) + " " + str({"dpi": "DPI", "cm_per_360": "cm/360°"}[field]))
	return " · ".join(parts) if not parts.is_empty() else "Profil à renseigner"


func _refresh_profile_label() -> void:
	if _profile_label != null:
		_profile_label.text = "Profil local · " + _profile_summary()


func _report_context(report: Dictionary) -> String:
	var parts := PackedStringArray()
	var difficulty := str(_first(report, ["difficulty", "level"], ""))
	if not difficulty.is_empty():
		parts.append(_difficulty_label(difficulty))
	for field in ["local_date", "date", "created_at", "score_version", "catalogue_revision"]:
		if report.has(field):
			parts.append(("Score v" if field == "score_version" else "") + str(report[field]))
	var duration: Variant = _first(report, ["elapsed_s", "active_duration_s", "completed_s"], report.get("duration_s", null) if report.get("complete", null) == true else null)
	if _is_number(duration):
		parts.append(_number(float(duration), 2) + " s actives")
	return " · ".join(parts) if not parts.is_empty() else "Conditions non renseignées"


func _validity_text(report: Dictionary) -> String:
	var text := str(_first(report, ["validity_text", "status_text", "invalid_reason", "reason"], ""))
	if not text.is_empty():
		return text
	if report.get("complete", null) == false:
		return "Programme interrompu · diagnostics conservés"
	if report.get("valid", null) == false:
		return "Séance non comparable · diagnostics conservés"
	if report.get("valid", null) == true:
		return "Séance valide dans les conditions enregistrées"
	return "Validité non renseignée"


func _add_navigation(parent: Node, compact: bool) -> void:
	var destinations: Dictionary = {"home": "Entraînement", "calibration": "Calibration", "history": "Historique", "settings": "Réglages"}
	for destination: String in destinations:
		var action: Callable
		match destination:
			"calibration":
				action = func() -> void: show_calibration(calibration_state)
			"history":
				action = _open_history
			"settings":
				action = func() -> void: show_settings(current_profile)
			_:
				action = show_home
		var button := _button(str(destinations[destination]), action)
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
		parent.add_child(button)
		var buttons: Array = _navigation_buttons.get(destination, [])
		buttons.append(button)
		_navigation_buttons[destination] = buttons
	if compact:
		parent.add_child(_button("Quitter", quit_requested.emit))


func _open_history() -> void:
	show_history(history_rows)
	history_requested.emit()


func _label(caption: String, font_size: int = 20, color: Color = PALETTE.text, bold: bool = false) -> Label:
	var control := Ui.label(caption, font_size, color)
	control.set_meta("v2_font_size", font_size)
	if bold and theme != null:
		control.add_theme_font_override("font", theme.get_font("font", "Button"))
	return control


func _button(caption: String, action: Callable, primary: bool = false) -> Button:
	var control := Button.new()
	control.text = caption
	control.custom_minimum_size.y = 44.0
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.pressed.connect(action)
	if primary:
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			control.add_theme_stylebox_override(state, Ui.style(PALETTE.accent, 12.0, PALETTE.accent, 8))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			control.add_theme_color_override(state, PALETTE.background)
	return control


func _card(parent: Node, padding_px: float = 24.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Ui.style(PALETTE.surface, padding_px, PALETTE.border, 12))
	parent.add_child(panel)
	return Ui.column(panel, 12)


func _grid(parent: Node, maximum_columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ui.grid_spacing(grid, 24)
	grid.set_meta("v2_maximum_columns", maximum_columns)
	parent.add_child(grid)
	_responsive_grids.append(grid)
	return grid


func _measurement(parent: Node, caption: String, value: String) -> void:
	var row := Ui.row(parent, 12)
	row.add_child(_label(caption, 17, PALETTE.secondary))
	var value_label := _label(value, 20)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)


func _add_details(parent: Node, data: Dictionary) -> void:
	var content := Ui.column(parent, 12)
	var toggle := _button("Détails du rapport", func() -> void: pass)
	toggle.toggle_mode = true
	content.add_child(toggle)
	var details := TextEdit.new()
	details.editable = false
	details.custom_minimum_size.y = 240.0
	details.text = JSON.stringify(data, "  ")
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	details.hide()
	content.add_child(details)
	toggle.toggled.connect(func(expanded: bool) -> void: details.visible = expanded)


func _focus_page() -> void:
	_focus_after_layout.call_deferred(page_content)


func _focus_after_layout(parent: Node) -> void:
	if not is_inside_tree() or not is_instance_valid(parent):
		return
	_pending_focus_parent = weakref(parent)
	if not get_tree().process_frame.is_connected(_focus_current_page):
		get_tree().process_frame.connect(_focus_current_page, CONNECT_ONE_SHOT)


func _focus_current_page() -> void:
	if _pending_focus_parent == null:
		return
	var parent: Node = _pending_focus_parent.get_ref() as Node
	_pending_focus_parent = null
	if not is_instance_valid(parent) or parent != page_content or not is_visible_in_tree():
		return
	if current_page == "home" and not _catalog_buttons.is_empty():
		var button := _catalog_buttons.get(selected_program_id, _catalog_buttons.values()[0]) as Button
		button.grab_focus()
	elif current_page == "preparation" and not level_buttons.is_empty():
		for button in level_buttons:
			if button.button_pressed and not button.disabled:
				button.grab_focus()
				return
	else:
		_focus_first(parent)


func _focus_first(parent: Node) -> bool:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return false
	for child in parent.get_children():
		if child == _preview_panel:
			continue
		if child is BaseButton and child.is_visible_in_tree() and not child.disabled:
			child.grab_focus()
			return true
		if child is SensitivityEditor.ReadableSpinBox and child.editable and child.is_visible_in_tree():
			child.display_input.grab_focus()
			return true
		if child is LineEdit and child.editable and child.is_visible_in_tree():
			child.grab_focus()
			return true
		if child is Container and _focus_first(child):
			return true
	return false


func _reflow() -> void:
	if not _built:
		return
	var compact := size.x < 900.0
	_sidebar.visible = not compact
	_compact_navigation.visible = compact
	_main_margin.add_theme_constant_override("margin_left", 16 if compact else 40)
	_main_margin.add_theme_constant_override("margin_right", 16 if compact else 32)
	_main_margin.add_theme_constant_override("margin_top", 16 if compact else 24)
	_main_margin.add_theme_constant_override("margin_bottom", 16 if compact else 24)
	theme.default_font_size = 16 if size.x < 1500.0 else 20
	var columns := 1 if compact else 2 if size.x < 1500.0 else 4
	for grid in _responsive_grids:
		if is_instance_valid(grid):
			grid.columns = mini(columns, int(grid.get_meta("v2_maximum_columns", 4)))
	_reflow_labels(_page_root)
	_layout_home_preview()


func _reflow_labels(parent: Node) -> void:
	for child in parent.get_children():
		if child is Label and child.has_meta("v2_font_size"):
			var baseline := int(child.get_meta("v2_font_size"))
			child.add_theme_font_size_override("font_size", maxi(16, roundi(float(baseline) * (0.8 if size.x < 1500.0 else 1.0))))
		_reflow_labels(child)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _built and not is_visible_in_tree():
		stop_preview()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _built:
		stop_preview()


static func _first(data: Dictionary, fields: Array, fallback: Variant = null) -> Variant:
	for field: String in fields:
		if data.has(field) and data[field] != null:
			return data[field]
	return fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return value.values()
	return []


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _number(value: float, decimals: int = 2) -> String:
	return Ui.number(value, decimals)


static func _score_display(value: float, supplied: Variant = null) -> String:
	if _is_number(supplied) and float(supplied) == floorf(float(supplied)):
		return _number(float(supplied), 0)
	return _number(floorf(value + 0.5), 0)


static func _difficulty_label(difficulty: String) -> String:
	var index := DIFFICULTIES.find(difficulty.to_lower())
	return DIFFICULTY_LABELS[index] if index >= 0 else difficulty


static func _score_family(program_id: String) -> String:
	if program_id == "EX03":
		return "P"
	if program_id in ["EX05", "EX06", "EX07"]:
		return "T"
	return "S" if program_id == "EX08" else "C"
