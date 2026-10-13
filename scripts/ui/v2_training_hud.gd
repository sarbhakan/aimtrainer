class_name V2TrainingHud
extends Control

signal resume_requested
signal menu_requested
signal settings_requested
signal sensitivity_edit_requested

const Shell := preload("res://scripts/ui/v2_shell.gd")
const Ui := preload("res://scripts/ui/aim_ui.gd")
const Crosshair := preload("res://scripts/presentation/crosshair_profile.gd")
const HIT_DURATION_S: float = 0.06
const PHASE_WARNING_S: float = 2.0
const RING_SEGMENTS: int = 128
const HIT_DIRECTIONS: PackedVector2Array = [
	Vector2(-0.70710678, -0.70710678), Vector2(0.70710678, -0.70710678),
	Vector2(-0.70710678, 0.70710678), Vector2(0.70710678, 0.70710678)
]

var configured_profile: Dictionary = {}
var crosshair_profile: Dictionary = Crosshair.defaults()
var reduced_motion: bool = false
var program_label: Label
var difficulty_label: Label
var phase_label: Label
var phase_alert_label: Label
var timer_label: Label
var score_label: Label
var metric_label: Label
var ammo_label: Label
var countdown_label: Label
var phase_progress: ProgressBar
var resume_button: Button
var menu_button: Button
var settings_button: Button
var sensitivity_button: Button
var target_projections: Array = []
var arena_rect_px: Rect2
var _overlay: Control
var _countdown: CenterContainer
var _pause_overlay: Control
var _pause_context: Label
var _top_margin: MarginContainer
var _bottom_margin: MarginContainer
var _metrics: VBoxContainer
var _snapshot: Dictionary = {}
var _hit_remaining_s: float = 0.0
var _preparing: bool = false
var _paused: bool = false
var _pause_options: Dictionary = {}
var _window_has_focus: bool = true
var _built: bool = false


func _ready() -> void:
	theme = Shell.make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_top_margin = MarginContainer.new()
	_top_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_overlay.add_child(_top_margin)
	var top_row := Ui.row(_top_margin, 16)
	var program := Ui.column(top_row, 4)
	program.size_flags_stretch_ratio = 1.0
	program_label = _label("", 24, Shell.PALETTE.text)
	program.add_child(program_label)
	difficulty_label = _label("", 17, Shell.PALETTE.secondary)
	program.add_child(difficulty_label)
	var phase := Ui.column(top_row, 4)
	phase.size_flags_stretch_ratio = 1.0
	phase_label = _label("", 20, Shell.PALETTE.text)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase.add_child(phase_label)
	phase_alert_label = _label("", 17, Shell.PALETTE.caution)
	phase_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase.add_child(phase_alert_label)
	var timer := VBoxContainer.new()
	timer.custom_minimum_size.x = 128.0
	top_row.add_child(timer)
	timer_label = _label("--:--", 34, Shell.PALETTE.text)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	timer.add_child(timer_label)
	phase_progress = ProgressBar.new()
	phase_progress.custom_minimum_size.y = 4.0
	phase_progress.show_percentage = false
	phase_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_progress.add_theme_stylebox_override("background", Ui.style(Shell.PALETTE.raised, 0.0, Shell.PALETTE.raised, 2))
	phase_progress.add_theme_stylebox_override("fill", Ui.style(Shell.PALETTE.accent, 0.0, Shell.PALETTE.accent, 2))
	timer.add_child(phase_progress)
	_bottom_margin = MarginContainer.new()
	_bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_overlay.add_child(_bottom_margin)
	var bottom_row := Ui.row(_bottom_margin, 16)
	_metrics = Ui.column(bottom_row, 4)
	score_label = _label("", 20, Shell.PALETTE.text)
	metric_label = _label("", 17, Shell.PALETTE.secondary)
	_metrics.add_child(score_label)
	_metrics.add_child(metric_label)
	ammo_label = _label("", 20, Shell.PALETTE.text)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	bottom_row.add_child(ammo_label)
	_countdown = CenterContainer.new()
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_countdown)
	countdown_label = _label("", 64, Shell.PALETTE.text)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_child(countdown_label)
	_countdown.hide()
	_build_pause()
	_ignore_mouse(_overlay)
	_built = true
	resized.connect(_layout)
	_layout()
	if not _snapshot.is_empty():
		present_live(_snapshot)
	elif _preparing:
		show_countdown(float(get_meta("v2_countdown_s", 3.0)))
	set_process(false)


func configure(profile: Dictionary) -> void:
	configured_profile = profile.duplicate(true)
	reduced_motion = bool(Shell._first(profile, ["reduced_motion", "reducedmotion"], false))
	var settings := Shell._dict(profile.get("crosshair", profile))
	crosshair_profile = Crosshair.resolve(settings if Crosshair.validate(settings).is_empty() else {})
	clear_feedback()
	queue_redraw()


func present_live(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if not _built:
		return
	_preparing = false
	_countdown.hide()
	if snapshot.has("paused"):
		show_pause(bool(snapshot.paused), str(snapshot.get("pause_reason", "")), _pause_options)
	var program_id := str(snapshot.get("program_id", ""))
	var phase := Shell._dict(snapshot.get("phase", {}))
	program_label.text = str(Shell._first(snapshot, ["program_title", "title"], Shell._dict(Shell.PROGRAM_COPY.get(program_id, {})).get("title", "")))
	difficulty_label.text = Shell._difficulty_label(str(snapshot.get("difficulty", "")))
	phase_label.text = str(Shell._first(snapshot, ["phase_title", "phase_label", "task_title"], Shell._first(phase, ["title", "name", "id"], "")))
	var remaining: Variant = Shell._first(snapshot, ["remaining_s", "time_left_s"], null)
	var duration: Variant = snapshot.get("duration_s", null)
	var elapsed: Variant = snapshot.get("elapsed_s", null)
	if not Shell._is_number(remaining) and Shell._is_number(duration) and Shell._is_number(elapsed):
		remaining = maxf(float(duration) - float(elapsed), 0.0)
	timer_label.text = _timer(float(remaining)) if Shell._is_number(remaining) else "--:--"
	var phase_remaining: Variant = Shell._first(snapshot, ["phase_remaining_s"], phase.get("remaining_s", remaining))
	var phase_duration: Variant = Shell._first(snapshot, ["phase_duration_s"], phase.get("duration_s", duration))
	phase_progress.visible = Shell._is_number(phase_remaining) and Shell._is_number(phase_duration) and float(phase_duration) > 0.0
	if phase_progress.visible:
		phase_progress.value = clampf((1.0 - float(phase_remaining) / float(phase_duration)) * 100.0, 0.0, 100.0)
	var next_phase := str(Shell._first(snapshot, ["next_phase_title", "next_phase_label"], ""))
	phase_alert_label.visible = not next_phase.is_empty() and Shell._is_number(phase_remaining) and float(phase_remaining) > 0.0 and float(phase_remaining) <= PHASE_WARNING_S
	phase_alert_label.text = "Ensuite · " + next_phase if phase_alert_label.visible else ""
	var calibration: bool = bool(snapshot.get("is_calibration", false)) or snapshot.get("calibration", null) is Dictionary or snapshot.get("calibration", false) == true
	_metrics.visible = not calibration and not _paused
	if not calibration:
		_present_metrics(snapshot, program_id)
	else:
		score_label.text = ""
		metric_label.text = ""
	_present_ammo(snapshot)
	target_projections = Shell._array(Shell._first(snapshot, ["target_projections", "projected_targets"], []))
	arena_rect_px = _rectangle(snapshot.get("arena_rect_px", null), Rect2(Vector2.ZERO, size))
	_layout()
	queue_redraw()


func begin_countdown(duration_s: float = 3.0) -> void:
	_snapshot.clear()
	target_projections.clear()
	show_pause(false)
	clear_feedback()
	if _built:
		score_label.text = ""
		metric_label.text = ""
		timer_label.text = "--:--"
	show_countdown(duration_s)


func show_countdown(remaining_s: float) -> void:
	var remaining := maxf(remaining_s, 0.0) if is_finite(remaining_s) else 0.0
	set_meta("v2_countdown_s", remaining)
	_preparing = remaining > 0.0
	if not _built:
		return
	_countdown.visible = _preparing and not _paused
	countdown_label.text = str(ceili(remaining)) if _preparing else ""
	_metrics.hide()
	ammo_label.hide()
	phase_alert_label.hide()
	queue_redraw()


func show_pause(paused: bool = true, context: String = "", options: Dictionary = {}) -> void:
	_paused = paused
	_pause_options = options.duplicate(true)
	clear_feedback()
	if not _built:
		return
	_pause_overlay.visible = paused
	var calibration := _calibration_pause()
	_pause_context.text = context if not context.is_empty() else "La pause invalide la journée de mesure. Reprenez une journée complète depuis la calibration." if calibration else "Temps actif suspendu."
	resume_button.visible = not calibration
	resume_button.disabled = calibration or not bool(options.get("resume_allowed", true))
	settings_button.visible = not calibration and bool(options.get("allow_settings", true))
	sensitivity_button.visible = not calibration and bool(options.get("allow_sensitivity_edit", true))
	_countdown.visible = _preparing and not paused
	_metrics.visible = not paused and not _preparing and not bool(_snapshot.get("is_calibration", false)) and not (_snapshot.get("calibration", null) is Dictionary) and _snapshot.get("calibration", false) != true
	ammo_label.visible = not ammo_label.text.is_empty() and not paused and not _preparing
	if paused:
		if resume_button.visible and not resume_button.disabled:
			resume_button.grab_focus.call_deferred()
		else:
			menu_button.grab_focus.call_deferred()
	queue_redraw()


func flash_hit() -> void:
	if reduced_motion or _paused or _preparing or not _window_has_focus or not is_visible_in_tree():
		return
	_hit_remaining_s = HIT_DURATION_S
	set_process(true)
	queue_redraw()


func clear_feedback() -> void:
	_hit_remaining_s = 0.0
	set_process(false)
	queue_redraw()


func health_ring_points(target: Dictionary) -> PackedVector2Array:
	return _outline(target, 1.2)


func _present_metrics(snapshot: Dictionary, program_id: String) -> void:
	var metrics := Shell._dict(snapshot.get("metrics", snapshot))
	var score: Variant = Shell._first(snapshot, ["phase_score"], metrics.get("phase_score", null))
	var family := str(snapshot.get("score_family", Shell._score_family(program_id) if Shell.PROGRAM_COPY.has(program_id) else ""))
	var display_score: Variant = snapshot.get("phase_display_score", null)
	if score is Dictionary:
		family = str(score.get("family", family))
		display_score = score.get("display_score", display_score)
		score = score.get("value", null)
	score_label.text = "Score de phase %s · %s" % [family, Shell._score_display(float(score), display_score)] if Shell._is_number(score) and family in ["C", "P", "T", "S"] else ""
	var parts := PackedStringArray()
	var phase := Shell._dict(snapshot.get("phase", {}))
	var mechanic := str(snapshot.get("mechanic", phase.get("mechanic", "")))
	var tracking := family == "T" or mechanic == "tracking"
	var switching := family == "S" or mechanic in ["switch", "switching"]
	var clicking := family in ["C", "P"] or mechanic in ["click", "opportunity", "timed_click"]
	var fields: Dictionary = {}
	if switching:
		fields = {"kills": "Destructions", "credited_work": "Travail utile"}
	elif clicking:
		fields = {"hits": "Touches", "shots": "Tirs"}
		if family == "P" or metrics.has("opportunities"):
			fields["expired"] = "Expirations"
	for field: String in fields:
		var value: Variant = metrics.get(field, null)
		if Shell._is_number(value):
			parts.append(str(fields[field]) + " " + Shell._number(float(value), 2 if field == "credited_work" else 0))
	var accuracy: Variant = metrics.get("accuracy", null)
	if clicking and Shell._is_number(accuracy):
		parts.append("Précision " + Shell._number(float(accuracy) * 100.0, 1) + " %")
	var contact: Variant = Shell._first(metrics, ["contact_s", "on_target_s"], null)
	var exposure: Variant = Shell._first(metrics, ["exposure_s", "exposed_s"], null)
	if tracking and Shell._is_number(contact):
		parts.append("Contact " + Shell._number(float(contact), 1) + (" / " + Shell._number(float(exposure), 1) if Shell._is_number(exposure) else "") + " s")
	var contact_ratio: Variant = metrics.get("contact_ratio", null)
	if tracking and Shell._is_number(contact_ratio):
		parts.append("Contact " + Shell._number(float(contact_ratio) * 100.0, 1) + " %")
	var hp: Variant = Shell._first(snapshot, ["hp_remaining"], metrics.get("hp_remaining", null))
	var hp_max: Variant = Shell._first(snapshot, ["hp_max"], metrics.get("hp_max", null))
	if Shell._is_number(hp) and Shell._is_number(hp_max) and float(hp_max) > 0.0:
		parts.append("PV " + Shell._number(float(hp), 0) + " / " + Shell._number(float(hp_max), 0))
	var program_index: Variant = Shell._first(snapshot, ["program_index", "program_score"], null)
	if program_id in ["EX05", "EX06", "EX07", "EX08"] and Shell._is_number(program_index):
		parts.append(("Indice de travail utile " if program_id == "EX08" else "Indice de contact ") + Shell._number(float(program_index), 2))
	metric_label.text = " · ".join(parts)
	score_label.visible = not score_label.text.is_empty()
	metric_label.visible = not metric_label.text.is_empty()


func _present_ammo(snapshot: Dictionary) -> void:
	var ammo: Variant = snapshot.get("ammo", null)
	var capacity: Variant = snapshot.get("ammo_capacity", null)
	if ammo is Dictionary:
		capacity = Shell._first(ammo, ["capacity", "maximum"], capacity)
		ammo = Shell._first(ammo, ["remaining", "current"], null)
	ammo_label.text = ""
	if Shell._is_number(ammo):
		ammo_label.text = "Munitions · " + Shell._number(float(ammo), 0)
		if Shell._is_number(capacity):
			ammo_label.text += " / " + Shell._number(float(capacity), 0)
	ammo_label.visible = not ammo_label.text.is_empty() and not _paused and not _preparing


func _build_pause() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pause_overlay)
	var shade := ColorRect.new()
	shade.color = Color(Shell.PALETTE.background, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 440.0
	center.add_child(card)
	var content := Ui.column(card, 16)
	content.add_child(_label("Pause", 32, Shell.PALETTE.text))
	_pause_context = _label("", 17, Shell.PALETTE.secondary)
	content.add_child(_pause_context)
	var actions := Ui.row(content, 12)
	resume_button = _pause_button("Reprendre", _request_resume, true)
	menu_button = _pause_button("Menu", menu_requested.emit)
	actions.add_child(resume_button)
	actions.add_child(menu_button)
	var preferences := Ui.row(content, 12)
	settings_button = _pause_button("Réglages", _request_settings)
	sensitivity_button = _pause_button("Sensibilité", _request_sensitivity_edit)
	preferences.add_child(settings_button)
	preferences.add_child(sensitivity_button)
	_pause_overlay.hide()


func _calibration_pause() -> bool:
	return bool(_pause_options.get("is_calibration", false)) or bool(_snapshot.get("is_calibration", false)) or _snapshot.get("calibration", null) is Dictionary or _snapshot.get("calibration", false) == true


func _request_resume() -> void:
	if _paused and not _calibration_pause() and bool(_pause_options.get("resume_allowed", true)):
		resume_requested.emit()


func _request_settings() -> void:
	if _paused and not _calibration_pause() and bool(_pause_options.get("allow_settings", true)):
		settings_requested.emit()


func _request_sensitivity_edit() -> void:
	if _paused and not _calibration_pause() and bool(_pause_options.get("allow_sensitivity_edit", true)):
		sensitivity_edit_requested.emit()


func _pause_button(caption: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	if primary:
		button.add_theme_stylebox_override("normal", Ui.style(Shell.PALETTE.accent, 12.0, Shell.PALETTE.accent, 8))
		button.add_theme_color_override("font_color", Shell.PALETTE.background)
	return button


func _label(caption: String, font_size: int, color: Color) -> Label:
	var label := Ui.label(caption, font_size, color)
	label.set_meta("v2_font_size", font_size)
	return label


func _layout() -> void:
	if not _built:
		return
	if not _snapshot.has("arena_rect_px"):
		arena_rect_px = Rect2(Vector2.ZERO, size)
	_overlay.position = arena_rect_px.position
	_overlay.size = arena_rect_px.size
	var margin_px := 16 if arena_rect_px.size.x < 1500.0 else 32
	for margin in [_top_margin, _bottom_margin]:
		margin.add_theme_constant_override("margin_left", margin_px)
		margin.add_theme_constant_override("margin_right", margin_px)
		margin.add_theme_constant_override("margin_top", margin_px)
		margin.add_theme_constant_override("margin_bottom", margin_px)
	for label in [program_label, difficulty_label, phase_label, phase_alert_label, timer_label, score_label, metric_label, ammo_label]:
		var font_size := int(label.get_meta("v2_font_size"))
		label.add_theme_font_size_override("font_size", maxi(16, roundi(float(font_size) * (0.8 if arena_rect_px.size.x < 1500.0 else 1.0))))
	queue_redraw()


func _ignore_mouse(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)


func _process(delta_s: float) -> void:
	_hit_remaining_s = maxf(_hit_remaining_s - maxf(delta_s, 0.0), 0.0)
	queue_redraw()
	if _hit_remaining_s <= 0.0:
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_has_focus = false
		clear_feedback()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_has_focus = true
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		clear_feedback()


func _draw() -> void:
	if not _built or _paused:
		return
	var center_px := arena_rect_px.get_center()
	Crosshair.draw(self, center_px, crosshair_profile)
	if not _preparing:
		for target_value: Variant in target_projections:
			if target_value is Dictionary:
				_draw_target_feedback(target_value)
	if _hit_remaining_s > 0.0:
		var inner_px := maxf(Crosshair.radius_px(crosshair_profile) + 11.0, 14.0)
		for direction in HIT_DIRECTIONS:
			draw_line(center_px + direction * inner_px, center_px + direction * (inner_px + 5.0), Shell.PALETTE.amber, 2.0, true)


func _draw_target_feedback(target: Dictionary) -> void:
	if target.get("visible", true) == false:
		return
	var center: Variant = _point(target.get("center_px", null))
	if center == null or not arena_rect_px.has_point(center):
		return
	var hp: Variant = Shell._first(target, ["hp_remaining", "remaining_hp"], null)
	var maximum: Variant = Shell._first(target, ["hp_max", "maximum_hp", "max_hp"], null)
	if Shell._is_number(hp) and Shell._is_number(maximum) and float(maximum) > 0.0 and float(hp) <= 0.0:
		return
	var width_px := maxf(1.0, 2.0 * arena_rect_px.size.y / 1080.0)
	if Shell._is_number(hp) and Shell._is_number(maximum) and float(maximum) > 0.0:
		var health := _partial_outline(health_ring_points(target), clampf(float(hp) / float(maximum), 0.0, 1.0))
		if health.size() >= 2:
			draw_polyline(health, Shell.PALETTE.amber, width_px, true)
	var window_fraction: Variant = target.get("window_remaining_fraction", null)
	if Shell._is_number(window_fraction):
		var window := _partial_outline(_outline(target, 1.4), clampf(float(window_fraction), 0.0, 1.0))
		if window.size() >= 2:
			draw_polyline(window, Shell.PALETTE.caution, width_px, true)
	if bool(target.get("priority", false)):
		var outline := _outline(target, 1.3)
		if outline.is_empty():
			return
		var bounds := Rect2(outline[0], Vector2.ZERO)
		for point in outline:
			bounds = bounds.expand(point)
		var length_px := clampf(minf(bounds.size.x, bounds.size.y) * 0.2, 4.0, 12.0)
		for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
			var inward := Vector2(1.0 if corner.x < center.x else -1.0, 1.0 if corner.y < center.y else -1.0)
			draw_line(corner, corner + Vector2(inward.x * length_px, 0.0), Shell.PALETTE.amber, width_px, true)
			draw_line(corner, corner + Vector2(0.0, inward.y * length_px), Shell.PALETTE.amber, width_px, true)


func _outline(target: Dictionary, factor: float) -> PackedVector2Array:
	var center: Variant = _point(target.get("center_px", null))
	if center == null:
		return PackedVector2Array()
	var contour := PackedVector2Array()
	var supplied: Variant = target.get("contour_px", null)
	if supplied is PackedVector2Array:
		contour = supplied
	elif supplied is Array:
		for value: Variant in supplied:
			var point: Variant = _point(value)
			if point != null:
				contour.append(point)
	if contour.size() >= 8:
		var top_index := 0
		var area := 0.0
		for point_index in contour.size():
			if contour[point_index].y < contour[top_index].y:
				top_index = point_index
			area += contour[point_index].cross(contour[(point_index + 1) % contour.size()])
		var points := PackedVector2Array()
		var direction := 1 if area >= 0.0 else -1
		for point_index in contour.size() + 1:
			var index := posmod(top_index + point_index * direction, contour.size())
			points.append(center + (contour[index] - center) * factor)
		return points
	var radius: Variant = target.get("radius_px", null)
	if not Shell._is_number(radius) or float(radius) <= 0.0:
		return PackedVector2Array()
	var points := PackedVector2Array()
	for point_index in RING_SEGMENTS + 1:
		points.append(center + Vector2.from_angle(-PI * 0.5 + TAU * float(point_index) / float(RING_SEGMENTS)) * float(radius) * factor)
	return points


static func _partial_outline(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	if points.size() < 2 or fraction <= 0.0:
		return PackedVector2Array()
	var last_position := fraction * float(points.size() - 1)
	var last_index := mini(floori(last_position), points.size() - 1)
	var result := points.slice(0, last_index + 1)
	if last_index + 1 < points.size():
		result.append(points[last_index].lerp(points[last_index + 1], last_position - float(last_index)))
	return result


static func _point(value: Variant) -> Variant:
	if value is Vector2 and value.is_finite():
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() >= 2 and Shell._is_number(value[0]) and Shell._is_number(value[1]):
		return Vector2(float(value[0]), float(value[1]))
	return null


static func _rectangle(value: Variant, fallback: Rect2) -> Rect2:
	if value is Rect2 and value.position.is_finite() and value.size.is_finite() and value.size.x > 0.0 and value.size.y > 0.0:
		return value
	if value is Rect2i:
		return _rectangle(Rect2(value), fallback)
	if value is Array and value.size() == 4:
		for coordinate: Variant in value:
			if not Shell._is_number(coordinate):
				return fallback
		return _rectangle(Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3])), fallback)
	return fallback


static func _timer(remaining_s: float) -> String:
	var seconds := maxi(ceili(remaining_s), 0)
	return "%02d:%02d" % [seconds / 60, seconds % 60]
