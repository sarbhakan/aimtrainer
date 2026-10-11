class_name AimGeometry
extends RefCounted


static func direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw_rad := deg_to_rad(fposmod(yaw_deg, 360.0))
	var pitch_rad := deg_to_rad(pitch_deg)
	return Vector3(-sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), -cos(yaw_rad) * cos(pitch_rad))


static func angular_error_deg(aim_direction: Vector3, target_direction: Vector3) -> float:
	return rad_to_deg(atan2(aim_direction.cross(target_direction).length(), aim_direction.dot(target_direction)))


static func sphere_fits_view(center_direction: Vector3, angular_diameter_deg: float, vertical_fov_deg: float, aspect: float) -> bool:
	if not center_direction.is_finite() or center_direction.is_zero_approx():
		return false
	if not is_finite(angular_diameter_deg) or angular_diameter_deg <= 0.0 or angular_diameter_deg >= 180.0:
		return false
	if not is_finite(vertical_fov_deg) or vertical_fov_deg <= 0.0 or vertical_fov_deg >= 180.0 or not is_finite(aspect) or aspect <= 0.0:
		return false
	var direction: Vector3 = center_direction.normalized()
	var vertical_half_rad: float = deg_to_rad(vertical_fov_deg * 0.5)
	var horizontal_half_rad: float = atan(tan(vertical_half_rad) * aspect)
	var radius_ratio: float = sin(deg_to_rad(angular_diameter_deg * 0.5))
	var horizontal_margin: float = -direction.z * sin(horizontal_half_rad) - absf(direction.x) * cos(horizontal_half_rad)
	var vertical_margin: float = -direction.z * sin(vertical_half_rad) - absf(direction.y) * cos(vertical_half_rad)
	return direction.z < 0.0 and horizontal_margin >= radius_ratio and vertical_margin >= radius_ratio


static func ray_sphere_distance(aim_direction: Vector3, center: Vector3, radius_m: float) -> float:
	if radius_m <= 0.0 or not is_finite(radius_m) or not aim_direction.is_finite() or not center.is_finite() or aim_direction.is_zero_approx():
		return INF
	var direction := aim_direction.normalized()
	var projected_m := center.dot(direction)
	var radius_squared_m := radius_m * radius_m
	var discriminant := radius_squared_m - center.cross(direction).length_squared()
	if discriminant < -maxf(radius_squared_m * 0.000001, 0.000000000001):
		return INF
	var offset_m := sqrt(maxf(discriminant, 0.0))
	var distance_m := projected_m - offset_m
	if distance_m >= 0.0:
		return distance_m
	return projected_m + offset_m if projected_m + offset_m >= 0.0 else INF
