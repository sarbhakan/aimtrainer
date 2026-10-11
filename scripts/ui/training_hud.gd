class_name TrainingHud
extends Control

const HIT_DURATION_S: float = 0.11
const COUNTDOWN_PULSE_DURATION_S: float = 0.16
const HIT_DIRECTIONS: PackedVector2Array = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

var title_label: Label
var metric_label: Label
var help_label: Label
var countdown_label: Label
var progress: ProgressBar
var weapon_feedback: WeaponFeedback
var hit_remaining_s: float = 0.0
var reduced_motion: bool = false
var crosshair_profile: Dictionary = CrosshairProfile.defaults()
var crosshair_layer: Control
var countdown_remaining_s: float = 0.0
var countdown_text: String = ""
var window_has_focus: bool = true
var configured_profile: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var content := AimUI.column(margin, 8)
	var top := AimUI.row(content)
	title_label = AimUI.label("", 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	metric_label = AimUI.label("", 16, AimUI.ACCENT)
	metric_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(metric_label)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(space)
	help_label = AimUI.label("", 12, AimUI.MUTED)
	content.add_child(help_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 4.0
	progress.show_percentage = false
	content.add_child(progress)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 64.0
	center.offset_bottom = 144.0
	add_child(center)
	countdown_label = AimUI.label("", 68, AimUI.ACCENT)
	countdown_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	countdown_label.custom_minimum_size.x = 96.0
	countdown_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	countdown_label.add_theme_color_override("font_outline_color", Color("09121d"))
	countdown_label.add_theme_constant_override("outline_size", 3)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(countdown_label)
	countdown_label.hide()
	countdown_label.visibility_changed.connect(sync_countdown)
	countdown_label.draw.connect(sync_countdown)
	countdown_label.resized.connect(func() -> void: countdown_label.pivot_offset = countdown_label.size * 0.5)
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
	if countdown_label != null:
		countdown_text = countdown_label.text if countdown_label.visible else ""
		countdown_label.scale = Vector2.ONE
		countdown_label.modulate.a = 1.0
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
		if feedback_available() and not reduced_motion and not countdown_text.is_empty():
			countdown_remaining_s = COUNTDOWN_PULSE_DURATION_S
			countdown_label.scale = Vector2.ONE * 1.08
			countdown_label.modulate.a = 0.85
	update_processing()


func update_processing() -> void:
	set_process(feedback_available() and (hit_remaining_s > 0.0 or countdown_remaining_s > 0.0))


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
	var pulse := countdown_remaining_s / COUNTDOWN_PULSE_DURATION_S
	countdown_label.scale = Vector2.ONE * (1.0 + 0.08 * pulse)
	countdown_label.modulate.a = 1.0 - 0.15 * pulse
	queue_redraw()
	update_processing()


func _draw() -> void:
	sync_countdown()
	if crosshair_layer != null:
		crosshair_layer.queue_redraw()


func draw_crosshair() -> void:
	if crosshair_layer == null:
		return
	var center := size * 0.5
	CrosshairProfile.draw(crosshair_layer, center, crosshair_profile)
	if hit_remaining_s > 0.0:
		var inner_px := maxf(CrosshairProfile.radius_px(crosshair_profile) + 5.0, 8.0)
		for direction in HIT_DIRECTIONS:
			var unit_direction := direction.normalized()
			crosshair_layer.draw_line(center + unit_direction * inner_px, center + unit_direction * (inner_px + 5.0), CrosshairProfile.OUTLINE_COLOR, 4.0, true)
			crosshair_layer.draw_line(center + unit_direction * inner_px, center + unit_direction * (inner_px + 5.0), AimUI.ACCENT, 2.0, true)
