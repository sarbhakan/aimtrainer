class_name ScenarioDefinition
extends Resource

@export var scenario_id: String = "C01"
@export var revision: int = 1
@export var title: String = "Static Single"
@export_multiline var instructions: String = "Cliquer une fois sur chaque sphère."
@export_enum("click", "tracking", "switching") var family: String = "click"
@export_enum("static", "horizontal", "vertical", "diagonal", "circle", "strafe") var motion: String = "static"
@export_enum("scatter", "grid") var layout: String = "scatter"
@export var angular_diameter_deg: float = 1.5
@export var yaw_extent_deg: float = 12.0
@export var pitch_extent_deg: float = 6.0
@export var min_transition_deg: float = 2.5
@export var speed_deg_s: float = 12.0
@export var active_targets: int = 1
@export var lifetime_s: float = 0.0
@export var reference_hits_s: float = 2.0
@export var distance_m: float = 8.0


func validate() -> String:
	if scenario_id.is_empty() or revision < 1 or title.is_empty():
		return "Identité de scénario invalide."
	if not family in ["click", "tracking", "switching"] or not motion in ["static", "horizontal", "vertical", "diagonal", "circle", "strafe"]:
		return "Famille ou mouvement invalide."
	if not layout in ["scatter", "grid"] or (layout == "grid" and (motion != "static" or family == "tracking")):
		return "Disposition de cibles invalide."
	for value in [angular_diameter_deg, yaw_extent_deg, pitch_extent_deg, speed_deg_s, reference_hits_s, distance_m]:
		if not is_finite(value) or value <= 0.0:
			return "Paramètre de scénario non positif ou non fini."
	if angular_diameter_deg > 10.0 or yaw_extent_deg > 40.0 or pitch_extent_deg > 25.0 or speed_deg_s > 120.0:
		return "Paramètres angulaires hors limites."
	if active_targets < 1 or active_targets > 6 or (family == "tracking" and active_targets != 1):
		return "Nombre de cibles invalide."
	if not is_finite(lifetime_s) or lifetime_s < 0.0 or not is_finite(min_transition_deg) or min_transition_deg < 0.0:
		return "Durée ou espacement invalide."
	return ""


func fits_view(vertical_fov_deg: float, aspect: float) -> bool:
	var horizontal_deg := SensitivityService.horizontal_fov_deg(vertical_fov_deg, aspect)
	return yaw_extent_deg + angular_diameter_deg < horizontal_deg * 0.5 and pitch_extent_deg + angular_diameter_deg < vertical_fov_deg * 0.5


func fingerprint() -> String:
	return JSON.stringify([scenario_id, revision, family, motion, layout, angular_diameter_deg,
		yaw_extent_deg, pitch_extent_deg, min_transition_deg, speed_deg_s, active_targets,
		lifetime_s, reference_hits_s, distance_m]).sha256_text()
