class_name TrainingHud
extends Control

const CountdownFeedbackScript := preload("res://scripts/presentation/countdown_feedback.gd")
const HIT_DURATION_S: float = 0.11
const COUNTDOWN_PULSE_DURATION_S: float = 0.16
const GO_DURATION_S: float = 0.45
const HIT_DIRECTIONS: PackedVector2Array = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const HIT_COLOR: Color = Color("ffd18a")
const HIT_LENGTH_PX: float = 5.0

var title_label: Label
var metric_label: Label
var timer_label: Label
var stat_label: Label
var score_label: Label
var help_label: Label
var countdown_label: Label
var progress: ProgressBar
var weapon_feedback: WeaponFeedback
var countdown_feedback: CountdownFeedbackScript
var hit_remaining_s: float = 0.0
var reduced_motion: bool = false
var crosshair_profile: Dictionary = CrosshairProfile.defaults()
var crosshair_layer: Control
var countdown_remaining_s: float = 0.0
var countdown_text: String = ""
var window_has_focus: bool = true
var configured_profile: Dictionary = {}
var timer_card: PanelContainer
var metric_card: PanelContainer
var preparation: CenterContainer
var go_label: Label
var go_remaining_s: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, AimUI.SPACE_XL)
	add_child(margin)
	var content := AimUI.column(margin, AimUI.SPACE_MD)
	var top := AimUI.row(content)
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	timer_card = make_metric_card(top)
	var time_column := AimUI.column(timer_card, 4)
	var time_heading := AimUI.label("TEMPS", 10, AimUI.MUTED)
	time_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_column.add_child(time_heading)
	timer_label = AimUI.label("0:30", 28)
	timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_column.add_child(timer_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	metric_card = make_metric_card(top)
	var metric_column := AimUI.column(metric_card, 4)
	stat_label = AimUI.label("TOUCHES · PRÉCISION", 10, AimUI.MUTED)
	stat_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	metric_column.add_child(stat_label)
	metric_label = AimUI.label("0 · —", 24, AimUI.ACCENT)
	metric_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	metric_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	metric_column.add_child(metric_label)
	score_label = AimUI.label("Score 0", 12, AimUI.MUTED)
	score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	metric_column.add_child(score_label)
	progress = ProgressBar.new()
	progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	progress.offset_bottom = 2.0
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.show_percentage = false
	add_child(progress)
	preparation = CenterContainer.new()
	preparation.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	preparation.offset_top = AimUI.SPACE_XL
	preparation.offset_bottom = 220.0
	add_child(preparation)
	var countdown_content := AimUI.column(preparation, AimUI.SPACE_MD)
	countdown_content.custom_minimum_size.x = 480.0
	title_label = AimUI.label("", 16, Color("172a36"))
	title_label.add_theme_color_override("font_outline_color", Color("efeee8"))
	title_label.add_theme_constant_override("outline_size", 2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_content.add_child(title_label)
	countdown_label = AimUI.label("", 88, Color("172a36"))
	countdown_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	countdown_label.custom_minimum_size = Vector2(128.0, 112.0)
	countdown_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	countdown_label.add_theme_color_override("font_outline_color", Color("efeee8"))
	countdown_label.add_theme_constant_override("outline_size", 3)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_content.add_child(countdown_label)
	help_label = AimUI.label("", 14, Color("172a36"))
	help_label.add_theme_color_override("font_outline_color", Color("efeee8"))
	help_label.add_theme_constant_override("outline_size", 2)
	help_label.custom_minimum_size.x = 480.0
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_content.add_child(help_label)
	countdown_label.hide()
	countdown_label.visibility_changed.connect(sync_countdown_visibility)
	countdown_label.resized.connect(func() -> void: countdown_label.pivot_offset = countdown_label.size * 0.5)
	var go_center := CenterContainer.new()
	go_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	go_center.offset_top = 24.0
	go_center.offset_bottom = 76.0
	add_child(go_center)
	go_label = AimUI.label("GO", 28, Color("172a36"))
	go_label.add_theme_color_override("font_outline_color", Color("efeee8"))
	go_label.add_theme_constant_override("outline_size", 2)
	go_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	go_label.hide()
	go_center.add_child(go_label)
	countdown_feedback = CountdownFeedbackScript.new()
	countdown_feedback.name = "CountdownFeedback"
	add_child(countdown_feedback)
	weapon_feedback = WeaponFeedback.new()
	weapon_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weapon_feedback.set_hud_mode(true)
	add_child(weapon_feedback)
	move_child(weapon_feedback, 0)
	weapon_feedback.stopped.connect(clear_feedback)
	crosshair_layer = Control.new()
	crosshair_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair_layer.draw.connect(draw_crosshair)
	add_child(crosshair_layer)
	ignore_mouse(self)
	configure(configured_profile)


func make_metric_card(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.027, 0.046, 0.065, 0.88)
	style.set_corner_radius_all(12)
	style.content_margin_left = AimUI.SPACE_LG
	style.content_margin_right = AimUI.SPACE_LG
	style.content_margin_top = AimUI.SPACE_MD
	style.content_margin_bottom = AimUI.SPACE_MD
	style.border_color = Color(0.3, 0.55, 0.6, 0.2)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func set_training_view(active: bool, preparing: bool) -> void:
	timer_card.visible = active
	metric_card.visible = active
	preparation.visible = preparing
	progress.visible = active
	if not preparing:
		countdown_label.hide()
		help_label.text = ""
		title_label.text = ""


func present_live(elapsed_s: float, duration_s: float, hits: int, shots: int, tracking: bool, on_target_s: float, exposed_s: float, reference_hits_s: float) -> void:
	var remaining_s := int(ceil(maxf(duration_s - elapsed_s, 0.0)))
	timer_label.text = "%d:%02d" % [remaining_s / 60, remaining_s % 60]
	var accuracy := float(hits) / maxf(float(shots), 1.0)
	var ratio := on_target_s / maxf(exposed_s, 0.000001)
	stat_label.text = "SUR CIBLE" if tracking else "TOUCHES · PRÉCISION"
	metric_label.text = "%s %%" % AimUI.number(ratio * 100.0, 0) if tracking else "%d · %s" % [hits, (AimUI.number(accuracy * 100.0, 0) + " %") if shots > 0 else "—"]
	var metrics := {"accuracy_fraction": accuracy, "hits_per_s": float(hits) / maxf(elapsed_s, 0.000001), "on_target_ratio": ratio}
	var score := int(ScoringService.score({"family": "tracking" if tracking else "click", "metrics": metrics}, reference_hits_s))
	score_label.text = "Score %d" % score
	progress.max_value = duration_s
	progress.value = elapsed_s


func show_go() -> void:
	if countdown_feedback == null or countdown_feedback.go_consumed or (countdown_label != null and countdown_label.visible):
		return
	countdown_feedback.play_go(feedback_available())
	if reduced_motion or not feedback_available():
		return
	go_remaining_s = GO_DURATION_S
	go_label.show()
	go_label.modulate.a = 1.0
	update_processing()


func begin_countdown() -> void:
	clear_feedback()
	countdown_text = ""
	if countdown_feedback != null:
		countdown_feedback.reset_sequence()


func present_countdown(text: String) -> void:
	if countdown_label == null:
		return
	countdown_label.text = text
	countdown_label.show()
	sync_countdown()


func ignore_mouse(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_mouse(child)


func configure(profile: Dictionary) -> void:
	var error := CrosshairProfile.validate(profile)
	if not error.is_empty():
		push_error(error)
		return
	configured_profile = profile.duplicate(true)
	crosshair_profile = CrosshairProfile.resolve(profile)
	clear_feedback()
	reduced_motion = bool(profile.get("reduced_motion", false))
	if weapon_feedback != null:
		weapon_feedback.configure(WeaponCatalog.find(profile.get("weapon_id", "pulse")), bool(profile.get("sound_enabled", true)), float(profile.get("sound_volume", 45.0)) / 100.0, bool(profile.get("show_weapon", true)), reduced_motion)
		weapon_feedback.crosshair_clearance_px = maxf(CrosshairProfile.radius_px(crosshair_profile) + 8.0, 18.0)
	if countdown_feedback != null:
		countdown_feedback.configure(bool(profile.get("sound_enabled", true)), float(profile.get("sound_volume", 45.0)) / 100.0)
	queue_redraw()


func hit() -> void:
	if not feedback_available() or (countdown_label != null and countdown_label.visible):
		return
	hit_remaining_s = HIT_DURATION_S
	queue_redraw()
	update_processing()


func stop() -> void:
	clear_feedback()
	if weapon_feedback != null:
		weapon_feedback.stop()


func clear_feedback() -> void:
	hit_remaining_s = 0.0
	countdown_remaining_s = 0.0
	go_remaining_s = 0.0
	if go_label != null:
		go_label.hide()
	if countdown_label != null:
		countdown_text = countdown_label.text if countdown_label.visible else ""
		countdown_label.scale = Vector2.ONE
		countdown_label.modulate.a = 1.0
	if countdown_feedback != null:
		countdown_feedback.play_tick(countdown_text, false)
		countdown_feedback.stop()
	set_process(false)
	queue_redraw()


func feedback_available() -> bool:
	return is_inside_tree() and is_visible_in_tree() and window_has_focus and not get_tree().paused


func sync_countdown() -> void:
	if countdown_label == null:
		return
	if not countdown_label.visible:
		countdown_text = ""
		countdown_remaining_s = 0.0
		countdown_label.scale = Vector2.ONE
		countdown_label.modulate.a = 1.0
	elif countdown_label.text != countdown_text:
		countdown_text = countdown_label.text
		hit_remaining_s = 0.0
		countdown_remaining_s = 0.0
		countdown_label.scale = Vector2.ONE
		countdown_label.modulate.a = 1.0
		if countdown_feedback != null:
			countdown_feedback.play_tick(countdown_text, feedback_available())
			if countdown_text not in ["3", "2", "1"]:
				countdown_feedback.stop()
		if feedback_available() and not reduced_motion and countdown_text in ["3", "2", "1"]:
			countdown_remaining_s = COUNTDOWN_PULSE_DURATION_S
			countdown_label.scale = Vector2.ONE * 1.08
			countdown_label.modulate.a = 0.85
	update_processing()


func sync_countdown_visibility() -> void:
	if countdown_label != null and not countdown_label.visible:
		countdown_text = ""
		countdown_remaining_s = 0.0
		countdown_label.scale = Vector2.ONE
		countdown_label.modulate.a = 1.0
	update_processing()


func update_processing() -> void:
	set_process(feedback_available() and (hit_remaining_s > 0.0 or countdown_remaining_s > 0.0 or go_remaining_s > 0.0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		window_has_focus = false
		stop()
		if weapon_feedback != null:
			weapon_feedback.notification(what)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		window_has_focus = true
		if weapon_feedback != null:
			weapon_feedback.notification(what)
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		stop()


func _process(delta_s: float) -> void:
	if not feedback_available():
		stop()
		return
	var elapsed_s := maxf(delta_s, 0.0)
	hit_remaining_s = maxf(hit_remaining_s - elapsed_s, 0.0)
	countdown_remaining_s = maxf(countdown_remaining_s - elapsed_s, 0.0)
	go_remaining_s = maxf(go_remaining_s - elapsed_s, 0.0)
	go_label.modulate.a = go_remaining_s / GO_DURATION_S
	go_label.visible = go_remaining_s > 0.0
	var pulse := countdown_remaining_s / COUNTDOWN_PULSE_DURATION_S
	countdown_label.scale = Vector2.ONE * (1.0 + 0.08 * pulse)
	countdown_label.modulate.a = 1.0 - 0.15 * pulse
	queue_redraw()
	update_processing()


func _draw() -> void:
	if countdown_label != null and countdown_label.is_visible_in_tree():
		var ring_center := countdown_label.global_position - global_position + countdown_label.size * 0.5
		var ring_radius := 58.0 + 4.0 * countdown_remaining_s / COUNTDOWN_PULSE_DURATION_S
		draw_arc(ring_center, ring_radius, -PI * 0.5, PI * 1.5, 64, Color(0.39, 0.9, 0.85, 0.12), 2.0, true)
	if crosshair_layer != null:
		crosshair_layer.queue_redraw()


func draw_crosshair() -> void:
	if crosshair_layer == null:
		return
	var center := size * 0.5
	CrosshairProfile.draw(crosshair_layer, center, crosshair_profile)
	if hit_remaining_s > 0.0:
		var segments := hitmarker_segments()
		for segment_index in HIT_DIRECTIONS.size():
			var first_px := segments[segment_index * 2]
			var last_px := segments[segment_index * 2 + 1]
			var direction := HIT_DIRECTIONS[segment_index]
			crosshair_layer.draw_line(first_px - direction, last_px + direction, CrosshairProfile.OUTLINE_COLOR, 4.0, true)
			crosshair_layer.draw_line(first_px, last_px, HIT_COLOR, 2.0, true)


func hitmarker_segments() -> PackedVector2Array:
	var center_px := size * 0.5
	var inner_px := maxf(CrosshairProfile.radius_px(crosshair_profile) + 5.0, 8.0)
	var segments := PackedVector2Array()
	for direction in HIT_DIRECTIONS:
		segments.append(center_px + direction * inner_px)
		segments.append(center_px + direction * (inner_px + HIT_LENGTH_PX))
	return segments
