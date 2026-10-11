class_name ScenarioPreview
extends Control

const DEMO_SEED: int = 1337
const DEMO_DURATION_S: float = 120.0
const DEMO_SHOT_INTERVAL_S: float = 0.85
const DEMO_TRACKING_LAG_S: float = 0.07

var definition: ScenarioDefinition
var engine := ScenarioEngine.new()
var animated: bool = false
var elapsed_s: float = 0.0
var redraw_elapsed_s: float = 0.0
var vertical_fov_deg: float = 75.0
var display_aspect: float = 16.0 / 9.0
var next_shot_s: float = DEMO_SHOT_INTERVAL_S
var demo_shots: int = 0
var preview_error: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(animated and is_visible_in_tree() and AimUI.motion_enabled and preview_error.is_empty())


func configure(source: ScenarioDefinition, animate: bool = false, fov_deg: float = 75.0, aspect: float = 16.0 / 9.0) -> void:
	definition = source
	animated = animate
	reset_demo()
	set_projection(fov_deg, aspect)
	set_process(animated and is_visible_in_tree() and AimUI.motion_enabled and preview_error.is_empty())
	queue_redraw()


func reset_demo() -> void:
	elapsed_s = 0.0
	redraw_elapsed_s = 0.0
	next_shot_s = DEMO_SHOT_INTERVAL_S
	demo_shots = 0
	preview_error = ""
	if not engine.start(definition, DEMO_SEED, DEMO_DURATION_S):
		preview_error = engine.invalid_reason
		engine.targets.clear()


func set_projection(fov_deg: float, aspect: float) -> bool:
	if not is_finite(fov_deg) or fov_deg <= 0.0 or fov_deg >= 180.0 or not is_finite(aspect) or aspect <= 0.0:
		preview_error = "FOV vertical ou ratio invalide."
		set_process(false)
		queue_redraw()
		return false
	vertical_fov_deg = fov_deg
	display_aspect = aspect
	if preview_error == "FOV vertical ou ratio invalide.":
		preview_error = ""
	tooltip_text = "Projection perspective réelle : FOV vertical %.1f°, ratio %.4f:1, diamètre angulaire sans agrandissement minimal. Silhouette sphérique à 128 segments. Caméra fixe ; viseur et clics simulés toutes les %.2f s, hors mesures joueur. Mouvement à vitesse réelle ×1 ; suivi illustré avec %.0f ms de retard simulé." % [vertical_fov_deg, display_aspect, DEMO_SHOT_INTERVAL_S, DEMO_TRACKING_LAG_S * 1000.0]
	set_process(animated and is_visible_in_tree() and AimUI.motion_enabled and preview_error.is_empty())
	queue_redraw()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(animated and is_visible_in_tree() and AimUI.motion_enabled and preview_error.is_empty())


func advance_demo(delta_s: float) -> void:
	if definition == null or not preview_error.is_empty() or not is_finite(delta_s) or delta_s <= 0.0:
		return
	var remaining_s: float = delta_s
	while remaining_s > 0.0:
		var step_s: float = minf(remaining_s, DEMO_DURATION_S - elapsed_s)
		var end_s: float = elapsed_s + step_s
		if definition.family != "tracking":
			while next_shot_s <= end_s + 0.000000001 and next_shot_s < DEMO_DURATION_S:
				engine.advance_to(next_shot_s)
				var target_index: int = demo_shots % engine.targets.size()
				engine.shoot(next_shot_s, engine.target_direction(target_index, next_shot_s))
				demo_shots += 1
				next_shot_s = float(demo_shots + 1) * DEMO_SHOT_INTERVAL_S
		engine.advance_to(end_s)
		elapsed_s = end_s
		remaining_s -= step_s
		if not engine.invalid_reason.is_empty():
			preview_error = engine.invalid_reason
			set_process(false)
			return
		if elapsed_s >= DEMO_DURATION_S:
			reset_demo()


func _process(delta_s: float) -> void:
	advance_demo(delta_s)
	redraw_elapsed_s += delta_s
	if redraw_elapsed_s >= 1.0 / 30.0:
		redraw_elapsed_s = 0.0
		queue_redraw()


func projection_rect() -> Rect2:
	var available_size: Vector2 = Vector2(size.x, maxf(size.y - 18.0, 0.0))
	var height_px: float = minf(available_size.y, available_size.x / display_aspect)
	var view_size: Vector2 = Vector2(height_px * display_aspect, height_px)
	return Rect2((available_size - view_size) * 0.5, view_size)


func project_direction(direction: Vector3) -> Vector2:
	return AimGeometry.project_direction(direction, vertical_fov_deg, projection_rect())


func target_outline(target_index: int, time_s: float) -> PackedVector2Array:
	if definition == null or not preview_error.is_empty() or target_index < 0 or target_index >= engine.targets.size():
		return PackedVector2Array()
	return AimGeometry.project_sphere_outline(engine.target_direction(target_index, time_s), definition.angular_diameter_deg, vertical_fov_deg, projection_rect())


func _draw() -> void:
	draw_style_box(AimUI.style(Color("0d1824"), 0.0, Color("223545"), 10), Rect2(Vector2.ZERO, size))
	if definition == null or not preview_error.is_empty():
		if not preview_error.is_empty():
			draw_string(get_theme_default_font(), Vector2(4.0, maxf(size.y - 4.0, 10.0)), preview_error, HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 8.0, 0.0), 10, AimUI.MUTED)
		return
	var view: Rect2 = projection_rect()
	if not view.has_area():
		return
	draw_rect(view, Color("12202e"))
	var clip_polygon: PackedVector2Array = PackedVector2Array([view.position, Vector2(view.end.x, view.position.y), view.end, Vector2(view.position.x, view.end.y)])
	for target_index in engine.targets.size():
		var outline: PackedVector2Array = target_outline(target_index, elapsed_s)
		if outline.size() >= 3:
			for polygon in Geometry2D.intersect_polygons(outline, clip_polygon):
				draw_colored_polygon(polygon, AimUI.ACCENT)
	var cursor: Vector2 = view.get_center()
	if animated:
		if definition.family == "tracking":
			cursor = project_direction(engine.target_direction(0, maxf(elapsed_s - DEMO_TRACKING_LAG_S, 0.0)))
		else:
			var target_index: int = demo_shots % engine.targets.size()
			var target_position: Vector2 = project_direction(engine.target_direction(target_index, elapsed_s))
			cursor = cursor.lerp(target_position, smoothstep(0.0, 0.5, fmod(elapsed_s, DEMO_SHOT_INTERVAL_S)))
	if cursor.is_finite() and view.has_point(cursor):
		draw_line(cursor - Vector2(4.0, 0.0), cursor + Vector2(4.0, 0.0), Color("f4f9ff"), 1.0, true)
		draw_line(cursor - Vector2(0.0, 4.0), cursor + Vector2(0.0, 4.0), Color("f4f9ff"), 1.0, true)
	var caption: String = "%.0f° · %.3f:1 · %s" % [vertical_fov_deg, display_aspect, "visée simulée ×1" if is_processing() else "vue figée"]
	if not definition.fits_view(vertical_fov_deg, display_aspect):
		caption = "Cadrage incompatible · " + caption
	draw_string(get_theme_default_font(), Vector2(4.0, size.y - 4.0), caption, HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 8.0, 0.0), 10, AimUI.MUTED)
