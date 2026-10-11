class_name AimGeometry
extends RefCounted


static func direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw_rad := deg_to_rad(fposmod(yaw_deg, 360.0))
	var pitch_rad := deg_to_rad(pitch_deg)
	return Vector3(-sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), -cos(yaw_rad) * cos(pitch_rad))


static func angular_error_deg(aim_direction: Vector3, target_direction: Vector3) -> float:
	return rad_to_deg(atan2(aim_direction.cross(target_direction).length(), aim_direction.dot(target_direction)))


static func ray_sphere_distance(aim_direction: Vector3, center: Vector3, radius_m: float) -> float:
	if radius_m <= 0.0 or not is_finite(radius_m) or aim_direction.is_zero_approx():
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
