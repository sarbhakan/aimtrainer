class_name TrainingHud
extends Control

var title_label: Label
var metric_label: Label
var help_label: Label
var countdown_label: Label
var progress: ProgressBar
var weapon_feedback: WeaponFeedback
var hit_remaining_s: float = 0.0
var reduced_motion: bool = false


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
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	countdown_label = AimUI.label("", 68, AimUI.ACCENT)
	center.add_child(countdown_label)
	weapon_feedback = WeaponFeedback.new()
	weapon_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weapon_feedback.set_hud_mode(true)
	add_child(weapon_feedback)
	move_child(weapon_feedback, 0)
	ignore_mouse(self)
	set_process(false)


func ignore_mouse(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_mouse(child)


func configure(profile: Dictionary) -> void:
	hit_remaining_s = 0.0
	set_process(false)
	reduced_motion = bool(profile.get("reduced_motion", false))
	weapon_feedback.configure(WeaponCatalog.find(profile.get("weapon_id", "pulse")), bool(profile.get("sound_enabled", true)), float(profile.get("sound_volume", 45.0)) / 100.0, bool(profile.get("show_weapon", true)), reduced_motion)
	queue_redraw()


func hit() -> void:
	hit_remaining_s = 0.09
	queue_redraw()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		hit_remaining_s = 0.0
		set_process(false)
		if weapon_feedback != null:
			weapon_feedback.stop()
		queue_redraw()


func _process(delta_s: float) -> void:
	hit_remaining_s = maxf(hit_remaining_s - delta_s, 0.0)
	queue_redraw()
	if hit_remaining_s <= 0.0:
		set_process(false)


func _draw() -> void:
	if countdown_label != null and countdown_label.visible:
		return
	var center := size * 0.5
	draw_circle(center, 2.0, Color("f4f9ff"))
	if hit_remaining_s > 0.0:
		for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + direction * 5.0, center + direction * 10.0, AimUI.ACCENT, 2.0, true)
