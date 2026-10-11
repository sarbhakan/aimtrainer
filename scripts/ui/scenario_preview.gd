class_name ScenarioPreview
extends Control

var definition: ScenarioDefinition
var engine := ScenarioEngine.new()
var animated: bool = false
var elapsed_s: float = 0.0
var redraw_elapsed_s: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(animated and is_visible_in_tree() and AimUI.motion_enabled)


func configure(source: ScenarioDefinition, animate: bool = false) -> void:
	definition = source
	animated = animate
	elapsed_s = 0.0
	engine.start(source, 1337, 120.0)
	set_process(animated and is_visible_in_tree() and AimUI.motion_enabled)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(animated and is_visible_in_tree() and AimUI.motion_enabled)


func _process(delta_s: float) -> void:
	var previous_cycle := int(elapsed_s / 0.85)
	elapsed_s = fmod(elapsed_s + delta_s, 120.0)
	if definition.family != "tracking" and int(elapsed_s / 0.85) != previous_cycle:
		engine.spawn_target(previous_cycle % engine.targets.size(), elapsed_s)
	redraw_elapsed_s += delta_s
	if redraw_elapsed_s >= 1.0 / 30.0:
		redraw_elapsed_s = 0.0
		queue_redraw()


func project_direction(direction: Vector3) -> Vector2:
	var horizontal_px := size.x * 0.34 / tan(deg_to_rad(maxf(definition.yaw_extent_deg, 16.0)))
	var vertical_px := size.y * 0.28 / tan(deg_to_rad(maxf(definition.pitch_extent_deg, 9.0)))
	return size * Vector2(0.5, 0.43) + Vector2(direction.x * horizontal_px, -direction.y * vertical_px) / maxf(-direction.z, 0.05)


func _draw() -> void:
	draw_style_box(AimUI.style(Color("0d1824"), 0.0, Color("223545"), 10), Rect2(Vector2.ZERO, size))
	var horizon_px := size.y * 0.76
	for line_index in range(1, 5):
		var line_y := lerpf(horizon_px, size.y, pow(float(line_index) / 5.0, 1.7))
		draw_line(Vector2(0, line_y), Vector2(size.x, line_y), Color(0.35, 0.65, 0.72, 0.09), 1.0, true)
	for line_index in range(-3, 4):
		draw_line(Vector2(size.x * 0.5 + line_index * size.x * 0.06, horizon_px), Vector2(size.x * 0.5 + line_index * size.x * 0.3, size.y), Color(0.35, 0.65, 0.72, 0.09), 1.0, true)
	if definition == null:
		return
	var demonstration_s := elapsed_s if animated else 0.65
	for target_index in engine.targets.size():
		var direction := engine.target_direction(target_index, demonstration_s)
		var center := project_direction(direction)
		var radius_px := clampf(definition.angular_diameter_deg * size.y * 0.022, 2.5, 12.0)
		draw_circle(center + Vector2(0, radius_px * 0.7), radius_px * 1.2, Color(0, 0, 0, 0.22))
		draw_circle(center, radius_px + 5.0, Color(0.39, 0.9, 0.85, 0.06))
		draw_circle(center, radius_px, AimUI.ACCENT)
		draw_circle(center + Vector2(-radius_px * 0.25, -radius_px * 0.25), radius_px * 0.35, Color("bafcf1"))
	var cursor := size * Vector2(0.5, 0.43)
	if animated:
		if definition.family == "tracking":
			cursor = project_direction(engine.target_direction(0, maxf(demonstration_s - 0.07, 0.0)))
		else:
			var target_index := int(demonstration_s / 0.85) % engine.targets.size()
			var target_position := project_direction(engine.target_direction(target_index, demonstration_s))
			cursor = cursor.lerp(target_position, smoothstep(0.0, 0.5, fmod(demonstration_s, 0.85)))
	draw_line(cursor - Vector2(6, 0), cursor + Vector2(6, 0), Color("f4f9ff"), 1.5, true)
	draw_line(cursor - Vector2(0, 6), cursor + Vector2(0, 6), Color("f4f9ff"), 1.5, true)
