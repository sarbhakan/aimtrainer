class_name ScenarioDefinition
extends Resource

const CAMERA_ORIGIN_HEIGHT_M: float = 1.6

@export var scenario_id: String = "C01"
@export var revision: int = 1
@export var title: String = "Static Single"
@export_multiline var instructions: String = "Cliquer une fois sur chaque sphère."
@export_enum("click", "tracking", "switching") var family: String = "click"
@export_enum("static", "horizontal", "vertical", "diagonal", "circle", "strafe", "reactive") var motion: String = "static"
@export_enum("scatter", "grid", "lanes") var layout: String = "scatter"
@export var angular_diameter_deg: float = 1.5
@export var yaw_extent_deg: float = 12.0
@export var pitch_extent_deg: float = 6.0
@export var min_transition_deg: float = 2.5
@export var speed_deg_s: float = 12.0
@export var active_targets: int = 1
@export var lifetime_s: float = 0.0
@export var reference_hits_s: float = 2.0
@export var distance_m: float = 4.0
@export var turn_duration_s: float = 0.12
@export var angular_diameter_min_deg: float = 0.0
@export var angular_diameter_max_deg: float = 0.0
@export var distance_min_m: float = 0.0
@export var distance_max_m: float = 0.0
@export_enum("fixed", "shrink") var diameter_motion: String = "fixed"


func validate() -> String:
	if scenario_id.is_empty() or revision < 1 or title.is_empty():
		return "Identité de scénario invalide."
	if not family in ["click", "tracking", "switching"] or not motion in ["static", "horizontal", "vertical", "diagonal", "circle", "strafe", "reactive"]:
		return "Famille ou mouvement invalide."
	if not layout in ["scatter", "grid", "lanes"] or (layout == "grid" and (motion != "static" or family == "tracking")):
		return "Disposition de cibles invalide."
	for value in [angular_diameter_deg, yaw_extent_deg, pitch_extent_deg, speed_deg_s, reference_hits_s, distance_m]:
		if not is_finite(value) or value <= 0.0:
			return "Paramètre de scénario non positif ou non fini."
	if angular_diameter_deg > 10.0 or yaw_extent_deg > 40.0 or pitch_extent_deg > 25.0 or speed_deg_s > 120.0:
		return "Paramètres angulaires hors limites."
	var variation_error: String = validate_variations()
	if not variation_error.is_empty():
		return variation_error
	if active_targets < 1 or active_targets > 6 or (family == "tracking" and active_targets != 1):
		return "Nombre de cibles invalide."
	if layout == "lanes" and (family != "switching" or not motion in ["horizontal", "reactive"] or active_targets < 2 or 2.0 * pitch_extent_deg / active_targets < maximum_angular_diameter_deg() * 1.7):
		return "Couloirs de cibles trop serrés ou incompatibles avec le mouvement."
	if layout == "grid":
		var horizontal_spacing_deg: float = AimGeometry.angular_error_deg(AimGeometry.direction(0.0, pitch_extent_deg), AimGeometry.direction(yaw_extent_deg, pitch_extent_deg))
		if minf(horizontal_spacing_deg, pitch_extent_deg) < maximum_angular_diameter_deg() * 1.7:
			return "Grille de cibles trop serrée."
	if revision >= 3 and minimum_surface_height_m() <= 0.0:
		return "La silhouette de cible traverse le sol depuis l'origine caméra de 1,6 m."
	if not is_finite(turn_duration_s) or turn_duration_s < 0.0:
		return "Durée de virage invalide."
	var motion_extent_deg: float = yaw_extent_deg * (0.9 if family == "tracking" else 0.45)
	if motion in ["strafe", "reactive"] and (turn_duration_s < 0.02 or turn_duration_s > minf(1.0, 4.0 * motion_extent_deg / speed_deg_s)):
		return "Durée de virage incompatible avec la vitesse et l'amplitude."
	if motion == "reactive" and (revision < 4 or family == "tracking"):
		return "Le mouvement réactif exige une définition de clic ou switching de révision 4."
	if not is_finite(lifetime_s) or lifetime_s < 0.0 or not is_finite(min_transition_deg) or min_transition_deg < 0.0:
		return "Durée ou espacement invalide."
	return ""


func has_diameter_variation() -> bool:
	return angular_diameter_min_deg != 0.0 or angular_diameter_max_deg != 0.0


func has_distance_variation() -> bool:
	return distance_min_m != 0.0 or distance_max_m != 0.0


func maximum_angular_diameter_deg() -> float:
	return angular_diameter_max_deg if has_diameter_variation() else angular_diameter_deg


func maximum_distance_m() -> float:
	return distance_max_m if has_distance_variation() else distance_m


func validate_variations() -> String:
	if not diameter_motion in ["fixed", "shrink"]:
		return "Mouvement du diamètre invalide."
	if diameter_motion == "shrink" and (revision < 4 or not has_diameter_variation() or not is_finite(lifetime_s) or lifetime_s <= 0.0):
		return "Le rétrécissement exige une révision 4, des bornes de diamètre et une durée de vie positive."
	if (has_diameter_variation() or has_distance_variation()) and revision < 4:
		return "Les variations de taille ou profondeur exigent une révision 4."
	if has_diameter_variation():
		if not is_finite(angular_diameter_min_deg) or not is_finite(angular_diameter_max_deg) or angular_diameter_min_deg <= 0.0 or angular_diameter_max_deg > 10.0 or angular_diameter_min_deg > angular_diameter_deg or angular_diameter_max_deg < angular_diameter_deg:
			return "Bornes de diamètre angulaire invalides."
	if has_distance_variation():
		if not is_finite(distance_min_m) or not is_finite(distance_max_m) or distance_min_m < 0.1 or distance_max_m > 8.0 or distance_min_m > distance_m or distance_max_m < distance_m:
			return "Bornes de profondeur invalides."
	return ""


func minimum_surface_height_m() -> float:
	return CAMERA_ORIGIN_HEIGHT_M - maximum_distance_m() * (sin(deg_to_rad(pitch_extent_deg)) + sin(deg_to_rad(maximum_angular_diameter_deg() * 0.5)))


func fits_view(vertical_fov_deg: float, aspect: float) -> bool:
	return AimGeometry.sphere_fits_view(AimGeometry.direction(yaw_extent_deg, pitch_extent_deg), maximum_angular_diameter_deg(), vertical_fov_deg, aspect)


func fingerprint() -> String:
	var parameters: Array = [scenario_id, revision, family, motion, layout, angular_diameter_deg,
		yaw_extent_deg, pitch_extent_deg, min_transition_deg, speed_deg_s, active_targets,
		lifetime_s, reference_hits_s, distance_m]
	if motion in ["strafe", "reactive"]:
		parameters.append(turn_duration_s)
	if has_diameter_variation():
		parameters.append(["angular_diameter_range_deg", angular_diameter_min_deg, angular_diameter_max_deg])
	if has_distance_variation():
		parameters.append(["distance_range_m", distance_min_m, distance_max_m])
	if diameter_motion != "fixed":
		parameters.append(["diameter_motion", diameter_motion])
	return JSON.stringify(parameters).sha256_text()
