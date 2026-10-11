class_name SensitivityService
extends RefCounted

const APP_YAW_DEG: float = 0.022
const GAME_YAW_DEG: Dictionary = {"CS2": 0.022, "Valorant": 0.07}


static func positive(value: float) -> bool:
	return is_finite(value) and value > 0.0


static func degrees_per_count(dpi: float, cm_per_360: float) -> float:
	if not positive(dpi) or not positive(cm_per_360):
		return NAN
	return 914.4 / (dpi * cm_per_360)


static func cm_per_360(dpi: float, rotation_deg_per_count: float) -> float:
	if not positive(dpi) or not positive(rotation_deg_per_count):
		return NAN
	return 914.4 / (dpi * rotation_deg_per_count)


static func game_sensitivity(dpi: float, distance_cm: float, yaw_deg: float) -> float:
	if not positive(yaw_deg):
		return NAN
	return degrees_per_count(dpi, distance_cm) / yaw_deg


static func horizontal_fov_deg(vertical_fov_deg: float, aspect: float) -> float:
	if not positive(aspect) or not positive(vertical_fov_deg) or vertical_fov_deg >= 180.0:
		return NAN
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical_fov_deg) * 0.5) * aspect))


static func validate_profile(profile: Dictionary) -> String:
	for field in ["dpi", "cm_per_360", "vertical_fov_deg"]:
		if not profile.has(field) or not (profile[field] is float or profile[field] is int):
			return "Valeur manquante ou invalide : " + field
		if not positive(float(profile[field])):
			return "Les DPI, la distance et le FOV doivent être positifs et finis."
	if float(profile.dpi) > 64000.0 or float(profile.cm_per_360) < 5.0 or float(profile.cm_per_360) > 150.0:
		return "Utiliser des DPI ≤ 64 000 et une distance entre 5 et 150 cm/360°."
	if float(profile.vertical_fov_deg) < 40.0 or float(profile.vertical_fov_deg) > 110.0:
		return "Le FOV vertical doit être compris entre 40 et 110°."
	if not profile.get("goal", "balanced") in ["balanced", "precision", "tracking"]:
		return "Objectif de calibration inconnu."
	for field in ["accumulated_input", "invert_y", "sound_enabled", "show_weapon", "reduced_motion"]:
		if profile.has(field) and not profile[field] is bool:
			return "Option d'input invalide : " + field
	var max_fps: Variant = profile.get("max_fps", 144)
	if not (max_fps is int or max_fps is float) or not is_finite(float(max_fps)) or not float(max_fps) in [0.0, 60.0, 144.0, 240.0]:
		return "Limite de FPS invalide."
	if profile.has("weapon_id") and not profile.weapon_id in ["pulse", "vector", "classic"]:
		return "Arme inconnue."
	var sound_volume: Variant = profile.get("sound_volume", 45.0)
	if not (sound_volume is int or sound_volume is float) or not is_finite(float(sound_volume)) or float(sound_volume) < 0.0 or float(sound_volume) > 100.0:
		return "Volume des tirs invalide."
	if profile.has("reference_game"):
		var reference_error := GameProfileService.validate_reference(profile.reference_game)
		if not reference_error.is_empty():
			return reference_error
	return ""


static func default_profile() -> Dictionary:
	return {"schema_version": 1, "dpi": 800.0, "cm_per_360": 35.0,
		"vertical_fov_deg": 75.0, "goal": "balanced", "accumulated_input": true, "max_fps": 144,
		"weapon_id": "pulse", "sound_enabled": true, "sound_volume": 45.0, "show_weapon": true, "reduced_motion": false}
