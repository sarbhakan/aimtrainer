class_name RecordCelebration
extends Control

var remaining_s: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			stop())


func celebrate(reduced_motion: bool) -> void:
	remaining_s = 0.0 if reduced_motion else 0.8
	set_process(remaining_s > 0.0)
	queue_redraw()


func stop() -> void:
	remaining_s = 0.0
	set_process(false)
	queue_redraw()


func _process(delta_s: float) -> void:
	remaining_s = maxf(0.0, remaining_s - delta_s)
	queue_redraw()
	if remaining_s <= 0.0:
		set_process(false)


func _draw() -> void:
	if remaining_s <= 0.0:
		return
	var progress := 1.0 - remaining_s / 0.8
	var color := Color("f5c879")
	color.a = 1.0 - progress
	for particle_index in 12:
		var horizontal_fraction := float(particle_index) / 11.0
		var position_px := Vector2(size.x * horizontal_fraction, size.y - 2.0 - progress * (10.0 + float(particle_index % 3) * 4.0))
		draw_circle(position_px, 1.5 + (1.0 - progress), color)
