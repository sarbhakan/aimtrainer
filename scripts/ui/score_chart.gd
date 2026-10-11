class_name ScoreChart
extends Control

var score_values: Array = []:
	set(values):
		score_values = values.duplicate()
		queue_redraw()


func plot_values() -> Array[float]:
	var values: Array[float] = []
	for value in score_values:
		if ScoringService.number(value) and float(value) >= 0.0:
			values.append(float(value))
	return values


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var values := plot_values()
	if values.is_empty() or size.x <= 60.0 or size.y <= 48.0:
		return
	var minimum: float = 0.0
	var maximum: float = maxf(float(values.max()), 1.0)
	var amplitude: float = maximum
	var left_px: float = 48.0
	var top_px: float = 12.0
	var bottom_px: float = size.y - 24.0
	for grid_index in 3:
		var position_y := lerpf(top_px, bottom_px, float(grid_index) * 0.5)
		draw_line(Vector2(left_px, position_y), Vector2(size.x, position_y), Color(0.3, 0.4, 0.55, 0.16), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, top_px + 4.0), "%.0f" % maximum, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AimUI.MUTED)
	draw_string(font, Vector2(0, bottom_px + 4.0), "%.0f" % minimum, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AimUI.MUTED)
	var points := PackedVector2Array()
	for value_index in values.size():
		var position_x := lerpf(left_px, size.x - 6.0, float(value_index) / maxf(values.size() - 1, 1.0))
		var proportion := (values[value_index] - minimum) / amplitude
		points.append(Vector2(position_x, lerpf(bottom_px, top_px, proportion)))
	if points.size() >= 2:
		var fill := points.duplicate()
		fill.append(Vector2(points[-1].x, bottom_px))
		fill.append(Vector2(points[0].x, bottom_px))
		draw_colored_polygon(fill, Color(0.39, 0.9, 0.85, 0.06))
		draw_polyline(points, AimUI.ACCENT, 2.0, true)
	for point in points:
		draw_circle(point, 3.0, AimUI.ACCENT)
	draw_string(font, Vector2(left_px, size.y - 5.0), "Ancien → récent", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AimUI.MUTED)
