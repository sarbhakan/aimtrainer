class_name ScenarioDefinition
extends Resource

const CAMERA_ORIGIN_HEIGHT_M: float = 1.6

@export var scenario_id: String = "C01"
@export var revision: int = 1
@export var title: String = "Static Single"
@export_multiline var instructions: String = "Cliquer une fois sur chaque sphère."
@export_enum("click", "tracking", "switching") var family: String = "click"
@export_enum("static", "horizontal", "vertical", "diagonal", "circle", "strafe", "reactive", "waypoints") var motion: String = "static"
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
@export_enum("fixed", "shrink", "perspective") var diameter_motion: String = "fixed"
@export_enum("uniform", "mixed") var spawn_pattern: String = "uniform"
@export var small_transition_min_deg: float = 2.5
@export var small_transition_max_deg: float = 6.0
@export var large_transition_min_deg: float = 20.0
@export var large_transition_max_deg: float = 44.0
@export var small_transition_probability: float = 0.5
@export var waypoint_min_duration_s: float = 0.6
@export var depth_speed_m_s: float = 1.2
@export var lifecycle_shrink_ratio: float = 0.0
@export var lifetime_min_s: float = 0.0
@export var lifetime_max_s: float = 0.0
@export var tracking_speed_min_deg_s: float = 0.0
@export var tracking_speed_max_deg_s: float = 0.0
@export var tracking_ramp_acceleration_deg_s2: float = 0.0


func validate() -> String:
	if scenario_id.is_empty() or revision < 1 or title.is_empty():
		return "Identité de scénario invalide."
	if not family in ["click", "tracking", "switching"] or not motion in ["static", "horizontal", "vertical", "diagonal", "circle", "strafe", "reactive", "waypoints"]:
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
	if not is_finite(lifecycle_shrink_ratio) or not is_finite(lifetime_min_s) or not is_finite(lifetime_max_s):
		return "Cycle de vie non fini."
	if has_lifecycle():
		if revision < 6 or lifecycle_shrink_ratio < 0.3 or lifecycle_shrink_ratio >= 1.0 or lifetime_min_s < 0.5 or lifetime_min_s > lifetime_s or lifetime_max_s < lifetime_s or lifetime_max_s > 15.0 or diameter_motion == "shrink":
			return "Cycle de vie incompatible : durée bornée et taille finale visable requises."
	elif lifetime_min_s != 0.0 or lifetime_max_s != 0.0 or lifecycle_shrink_ratio != 0.0:
		return "Cycle de vie incomplet."
	for value in [tracking_speed_min_deg_s, tracking_speed_max_deg_s, tracking_ramp_acceleration_deg_s2]:
		if not is_finite(value):
			return "Rythme de suivi non fini."
	if has_tracking_rhythm():
		if revision < 7 or family != "tracking" or not motion in ["horizontal", "vertical", "diagonal", "circle", "strafe", "waypoints"] or not has_lifecycle() or tracking_speed_min_deg_s <= 0.0 or tracking_speed_min_deg_s >= tracking_speed_max_deg_s or tracking_speed_max_deg_s > 120.0 or tracking_ramp_acceleration_deg_s2 <= 0.0 or tracking_ramp_acceleration_deg_s2 > 600.0:
			return "Rythme de suivi incompatible : vitesses et rampes bornées requises."
	elif tracking_speed_min_deg_s != 0.0 or tracking_speed_max_deg_s != 0.0 or tracking_ramp_acceleration_deg_s2 != 0.0:
		return "Rythme de suivi incomplet."
	var pattern_error: String = validate_patterns()
	if not pattern_error.is_empty():
		return pattern_error
	if revision >= 5:
		if distance_m < 0.1 or distance_m > 8.0 or not fits_view(75.0, 1.0):
			return "Profondeur ou enveloppe maximale hors de la vue nominale."
		var minimum_distance_m: float = distance_min_m if has_distance_variation() else distance_m
		if minimum_distance_m * (cos(deg_to_rad(yaw_extent_deg)) * cos(deg_to_rad(pitch_extent_deg)) - sin(deg_to_rad(maximum_angular_diameter_deg() * 0.5))) <= 0.05:
			return "La silhouette traverse le plan proche de la caméra."
	return ""


func has_diameter_variation() -> bool:
	return angular_diameter_min_deg != 0.0 or angular_diameter_max_deg != 0.0


func has_lifecycle() -> bool:
	return lifecycle_shrink_ratio > 0.0


func has_tracking_rhythm() -> bool:
	return tracking_speed_max_deg_s > 0.0


func has_distance_variation() -> bool:
	return distance_min_m != 0.0 or distance_max_m != 0.0


func maximum_angular_diameter_deg() -> float:
	return angular_diameter_max_deg if has_diameter_variation() else angular_diameter_deg


func maximum_distance_m() -> float:
	return distance_max_m if has_distance_variation() else distance_m


func validate_variations() -> String:
	if not diameter_motion in ["fixed", "shrink", "perspective"]:
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
	if diameter_motion == "perspective":
		if revision < 5 or motion != "waypoints" or not has_distance_variation() or not has_diameter_variation():
			return "La perspective exige un suivi de révision 5 et des enveloppes explicites."
		var sphere_radius_m: float = distance_m * sin(deg_to_rad(angular_diameter_deg * 0.5))
		if sphere_radius_m >= distance_min_m:
			return "La sphère englobe l'origine de visée."
		if angular_diameter_min_deg > rad_to_deg(2.0 * asin(sphere_radius_m / distance_max_m)) or angular_diameter_max_deg < rad_to_deg(2.0 * asin(sphere_radius_m / distance_min_m)):
			return "Les bornes de diamètre ne contiennent pas la silhouette en perspective."
	return ""


func scatter_reserve_angles_deg() -> Array[Vector2]:
	return [Vector2(-yaw_extent_deg, -pitch_extent_deg), Vector2(0.0, -pitch_extent_deg),
		Vector2(yaw_extent_deg, -pitch_extent_deg), Vector2(-yaw_extent_deg, pitch_extent_deg),
		Vector2(0.0, pitch_extent_deg), Vector2(yaw_extent_deg, pitch_extent_deg),
		Vector2(-yaw_extent_deg * 0.5, 0.0), Vector2(yaw_extent_deg * 0.5, 0.0)]


func validate_patterns() -> String:
	if not spawn_pattern in ["uniform", "mixed"]:
		return "Distribution d'apparition invalide."
	if spawn_pattern == "mixed":
		if revision < 5 or family != "click" or motion != "static" or layout != "scatter" or active_targets != 1:
			return "Les transitions mixtes exigent une seule cible statique de clic en révision 5."
		for value in [small_transition_min_deg, small_transition_max_deg, large_transition_min_deg, large_transition_max_deg, small_transition_probability]:
			if not is_finite(value):
				return "Distribution de transitions non finie."
		if small_transition_min_deg <= 0.0 or small_transition_min_deg > small_transition_max_deg or small_transition_max_deg >= large_transition_min_deg or large_transition_min_deg > large_transition_max_deg or large_transition_max_deg >= 180.0 or large_transition_min_deg > yaw_extent_deg or small_transition_max_deg >= yaw_extent_deg or small_transition_probability <= 0.0 or small_transition_probability >= 1.0 or min_transition_deg != small_transition_min_deg:
			return "Bornes ou probabilité de transitions mixtes incompatibles."
	if motion == "waypoints":
		if revision < 5 or family != "tracking" or layout != "scatter" or not has_distance_variation() or (lifetime_s != 0.0 and not has_lifecycle()):
			return "Les destinations 3D exigent un suivi continu de révision 5 avec profondeur variable."
		if not is_finite(waypoint_min_duration_s) or waypoint_min_duration_s < 0.2 or waypoint_min_duration_s > 5.0 or not is_finite(depth_speed_m_s) or depth_speed_m_s <= 0.0 or depth_speed_m_s > 5.0 or distance_min_m >= distance_max_m:
			return "Durée de destination ou vitesse de profondeur invalide."
	if revision >= 5 and layout == "scatter" and active_targets > 1:
		if motion != "static":
			return "La réserve de dispersion exige des cibles statiques."
		var reserve: Array[Vector2] = scatter_reserve_angles_deg()
		var exclusion_deg: float = maxf(maximum_angular_diameter_deg() * 1.7, min_transition_deg)
		for first_index in reserve.size():
			for second_index in range(first_index + 1, reserve.size()):
				if AimGeometry.angular_error_deg(AimGeometry.direction(reserve[first_index].x, reserve[first_index].y), AimGeometry.direction(reserve[second_index].x, reserve[second_index].y)) <= exclusion_deg * 2.0 + 0.0001:
					return "L'enveloppe ne garantit pas une réserve de dispersion sans chevauchement."
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
	if spawn_pattern == "mixed":
		parameters.append(["mixed_transitions_v1", small_transition_min_deg, small_transition_max_deg,
			large_transition_min_deg, large_transition_max_deg, small_transition_probability])
	if motion == "waypoints":
		parameters.append(["waypoints_3d_v1", waypoint_min_duration_s, depth_speed_m_s])
	if revision >= 5 and layout == "scatter" and active_targets > 1:
		parameters.append("bounded_scatter_v1")
	if has_lifecycle():
		parameters.append(["lifecycle_v1", lifecycle_shrink_ratio, lifetime_min_s, lifetime_max_s])
	if has_tracking_rhythm():
		parameters.append(["bounded_tracking_rhythm_v1", tracking_speed_min_deg_s, tracking_speed_max_deg_s, tracking_ramp_acceleration_deg_s2])
	return JSON.stringify(parameters).sha256_text()
