class_name CrosshairProfile
extends RefCounted

const STYLES: PackedStringArray = ["dot", "cross", "circle", "t"]
const MIN_SIZE_PX: float = 1.0
const MAX_SIZE_PX: float = 32.0
const MIN_THICKNESS_PX: float = 1.0
const MAX_THICKNESS_PX: float = 8.0
const MIN_GAP_PX: float = 0.0
const MAX_GAP_PX: float = 24.0
const OUTLINE_WIDTH_PX: float = 1.0
const OUTLINE_COLOR: Color = Color(0.015, 0.02, 0.03, 0.95)
const DIRECTIONS: PackedVector2Array = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]


static func defaults() -> Dictionary:
	return {"crosshair_style": "dot", "crosshair_size_px": 2.0, "crosshair_thickness_px": 2.0,
		"crosshair_gap_px": 4.0, "crosshair_color": "#f4f9ff", "crosshair_outline": false}


static func validate(profile: Dictionary) -> String:
	if profile.has("crosshair_style") and (not profile.crosshair_style is String or not profile.crosshair_style in STYLES):
		return "Forme de viseur inconnue."
	var ranges := {"crosshair_size_px": Vector2(MIN_SIZE_PX, MAX_SIZE_PX),
		"crosshair_thickness_px": Vector2(MIN_THICKNESS_PX, MAX_THICKNESS_PX),
		"crosshair_gap_px": Vector2(MIN_GAP_PX, MAX_GAP_PX)}
	for field in ranges:
		if not profile.has(field):
			continue
		var value: Variant = profile[field]
		var limits: Vector2 = ranges[field]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < limits.x or float(value) > limits.y:
			return "Valeur de viseur invalide : %s (%.0f à %.0f px)." % [field, limits.x, limits.y]
	if profile.has("crosshair_color") and (not profile.crosshair_color is String or not Color.html_is_valid(profile.crosshair_color)):
		return "La couleur du viseur doit être une couleur HTML valide."
	if profile.has("crosshair_outline") and not profile.crosshair_outline is bool:
		return "Le contour du viseur doit être activé ou désactivé."
	return ""


static func resolve(profile: Dictionary) -> Dictionary:
	var settings := defaults()
	for field in settings:
		if profile.has(field):
			settings[field] = profile[field]
	return settings


static func radius_px(profile: Dictionary) -> float:
	var radius := float(profile.crosshair_size_px)
	if profile.crosshair_style in ["cross", "t"]:
		radius += float(profile.crosshair_gap_px)
	if profile.crosshair_style != "dot":
		radius += float(profile.crosshair_thickness_px) * 0.5
	return radius + (OUTLINE_WIDTH_PX if profile.crosshair_outline else 0.0)


static func draw(control: CanvasItem, center_px: Vector2, profile: Dictionary) -> void:
	var style: String = profile.crosshair_style
	var size_px := float(profile.crosshair_size_px)
	var thickness_px := float(profile.crosshair_thickness_px)
	var gap_px := float(profile.crosshair_gap_px)
	var color := Color.html(profile.crosshair_color)
	var outline: bool = profile.crosshair_outline
	if style == "dot":
		if outline:
			control.draw_circle(center_px, size_px + OUTLINE_WIDTH_PX, OUTLINE_COLOR, true, -1.0, true)
		control.draw_circle(center_px, size_px, color, true, -1.0, true)
	elif style == "circle":
		if outline:
			control.draw_arc(center_px, size_px, 0.0, TAU, 64, OUTLINE_COLOR, thickness_px + OUTLINE_WIDTH_PX * 2.0, true)
		control.draw_arc(center_px, size_px, 0.0, TAU, 64, color, thickness_px, true)
	else:
		var arm_count := 3 if style == "t" else 4
		if outline:
			for arm_index in arm_count:
				var direction := DIRECTIONS[arm_index]
				control.draw_line(center_px + direction * maxf(gap_px - OUTLINE_WIDTH_PX, 0.0), center_px + direction * (gap_px + size_px + OUTLINE_WIDTH_PX), OUTLINE_COLOR, thickness_px + OUTLINE_WIDTH_PX * 2.0, true)
		for arm_index in arm_count:
			var direction := DIRECTIONS[arm_index]
			control.draw_line(center_px + direction * gap_px, center_px + direction * (gap_px + size_px), color, thickness_px, true)
