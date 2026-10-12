class_name ScenarioPreview
extends Control

const DEMO_SEED: int = 1337
const DEMO_DURATION_S: float = 120.0
const DEMO_SHOT_INTERVAL_S: float = 0.85
const DEMO_TRACKING_LAG_S: float = 0.07
const PLAYBACK_BAR_HEIGHT_PX: float = 18.0
const REDRAW_INTERVAL_S: float = 1.0 / 30.0
const MAX_PROCESS_STEP_S: float = 0.1

var definition: ScenarioDefinition
var engine := ScenarioEngine.new()
var animated: bool = false:
	set(enabled):
		animated = enabled
		refresh_animation()
var elapsed_s: float = 0.0
var redraw_elapsed_s: float = 0.0
var vertical_fov_deg: float = 75.0
var display_aspect: float = 16.0 / 9.0
var next_shot_s: float = DEMO_SHOT_INTERVAL_S
var demo_shots: int = 0
var preview_error: String = ""
var background_style := AimUI.style(Color("0d1824"), 0.0, Color("223545"), 8)
var playback_style := AimUI.style(Color("173138"), 0.0, Color("2b555b"), 6)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	AimUI.feedback(self).motion_changed.connect(func(_enabled: bool) -> void: refresh_animation())
	refresh_animation()


func configure(source: ScenarioDefinition, animate: bool = false, fov_deg: float = 75.0, aspect: float = 16.0 / 9.0) -> void:
	definition = source
	animated = animate
	reset_demo()
	set_projection(fov_deg, aspect)
	refresh_animation()


func refresh_animation() -> void:
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
	tooltip_text = "Viseur et clics simulés ; cibles sans agrandissement."
	refresh_animation()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		refresh_animation()


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
	if not is_finite(delta_s) or delta_s <= 0.0:
		return
	redraw_elapsed_s += minf(delta_s, MAX_PROCESS_STEP_S)
	if redraw_elapsed_s < REDRAW_INTERVAL_S:
		return
	advance_demo(redraw_elapsed_s)
	redraw_elapsed_s = 0.0
	queue_redraw()


func projection_rect() -> Rect2:
	var available_size: Vector2 = Vector2(size.x, maxf(size.y - PLAYBACK_BAR_HEIGHT_PX, 0.0))
	var height_px: float = minf(available_size.y, available_size.x / display_aspect)
	var view_size: Vector2 = Vector2(height_px * display_aspect, height_px)
	return Rect2((available_size - view_size) * 0.5, view_size)


func project_direction(direction: Vector3) -> Vector2:
	return AimGeometry.project_direction(direction, vertical_fov_deg, projection_rect())


func target_outline(target_index: int, time_s: float) -> PackedVector2Array:
	if definition == null or not preview_error.is_empty() or target_index < 0 or target_index >= engine.targets.size():
		return PackedVector2Array()
	return AimGeometry.project_sphere_outline(engine.target_direction(target_index, time_s), engine.definition.angular_diameter_deg, vertical_fov_deg, projection_rect())


func playback_caption() -> String:
	if not animated:
		return ""
	return "Démo animée" if is_processing() and AimUI.motion_enabled else "Aperçu fixe"


func playback_badge_rect() -> Rect2:
	var caption := playback_caption()
	if caption.is_empty() or size.y < PLAYBACK_BAR_HEIGHT_PX:
		return Rect2()
	var caption_width_px := get_theme_default_font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
	return Rect2(Vector2(0.0, size.y - PLAYBACK_BAR_HEIGHT_PX + 2.0), Vector2(minf(caption_width_px + 30.0, size.x), 14.0))


func playback_light_color() -> Color:
	if not is_processing() or not AimUI.motion_enabled:
		return AimUI.MUTED
	var brightness := 0.7 + 0.3 * sin(elapsed_s * TAU)
	return AimUI.ACCENT * Color(brightness, brightness, brightness, 1.0)


func _draw() -> void:
	draw_style_box(background_style, Rect2(Vector2.ZERO, size))
	if definition == null or not preview_error.is_empty():
		if not preview_error.is_empty():
			draw_string(get_theme_default_font(), Vector2(4.0, maxf(size.y - 4.0, 10.0)), "Aperçu indisponible", HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 8.0, 0.0), 10, AimUI.MUTED)
		return
	var view: Rect2 = projection_rect()
	if not view.has_area():
		return
	draw_rect(view, Color("12202e"))
	draw_rect(view, Color("2b4050"), false, 1.0)
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
	if cursor.is_finite() and view.encloses(Rect2(cursor - Vector2(4.0, 4.0), Vector2(8.0, 8.0))):
		var cursor_color := Color(0.96, 0.98, 1.0, 0.72)
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(cursor + direction * 2.0, cursor + direction * 4.0, cursor_color, 1.0, true)
	var badge := playback_badge_rect()
	if badge.size.x >= 30.0:
		draw_style_box(playback_style, badge)
		var play_origin := badge.position + Vector2(5.0, 4.0)
		draw_colored_polygon(PackedVector2Array([play_origin, play_origin + Vector2(0.0, 6.0), play_origin + Vector2(5.0, 3.0)]), AimUI.ACCENT)
		draw_string(get_theme_default_font(), badge.position + Vector2(15.0, 10.5), playback_caption(), HORIZONTAL_ALIGNMENT_LEFT, badge.size.x - 29.0, 10, AimUI.TEXT)
		var light_position := Vector2(badge.end.x - 8.0, badge.get_center().y)
		var light_color := playback_light_color()
		draw_circle(light_position, 4.0, Color(light_color, 0.12))
		draw_circle(light_position, 2.0, light_color)
