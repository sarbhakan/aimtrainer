class_name V2Geometry
extends RefCounted

const EPSILON: float = 2.220446049250313e-16
const ANGLE_EPSILON_DEG: float = 0.000000001
const EYE_HEIGHT_M: float = 1.6


static func direction_deg(yaw_deg: float, pitch_deg: float) -> Array[float]:
	var yaw_rad := deg_to_rad(yaw_deg)
	var pitch_rad := deg_to_rad(pitch_deg)
	return [cos(pitch_rad) * sin(yaw_rad), sin(pitch_rad), -cos(pitch_rad) * cos(yaw_rad)]


static func dot(first: Array, second: Array) -> float:
	return float(first[0]) * float(second[0]) + float(first[1]) * float(second[1]) + float(first[2]) * float(second[2])


static func cross(first: Array, second: Array) -> Array[float]:
	return [float(first[1]) * float(second[2]) - float(first[2]) * float(second[1]),
		float(first[2]) * float(second[0]) - float(first[0]) * float(second[2]),
		float(first[0]) * float(second[1]) - float(first[1]) * float(second[0])]


static func norm(value: Array) -> float:
	return sqrt(dot(value, value))


static func normalized(value: Array) -> Array[float]:
	var length := norm(value)
	var result: Array[float] = [0.0, 0.0, -1.0]
	if length > 0.0:
		result = [float(value[0]) / length, float(value[1]) / length, float(value[2]) / length]
	return result


static func separation_deg(first: Array, second: Array) -> float:
	return rad_to_deg(atan2(norm(cross(first, second)), dot(first, second)))


static func angles_deg(value: Array) -> Array[float]:
	return [rad_to_deg(atan2(float(value[0]), -float(value[2]))), rad_to_deg(asin(clampf(float(value[1]), -1.0, 1.0)))]


static func ray_sphere_distance(direction: Array, center: Array, radius_m: float, near_m: float = 0.05, far_m: float = 100.0) -> float:
	var projection := -dot(direction, center)
	var constant := dot(center, center) - radius_m * radius_m
	var discriminant := projection * projection - constant
	var tolerance := 64.0 * EPSILON * maxf(1.0, maxf(projection * projection, maxf(absf(constant), radius_m * radius_m)))
	if discriminant < -tolerance:
		return INF
	var root := sqrt(maxf(discriminant, 0.0))
	var nearer := -projection - root
	var farther := -projection + root
	if nearer >= near_m and nearer <= far_m:
		return nearer
	return farther if farther >= near_m and farther <= far_m else INF


static func sphere_fits(direction: Array, diameter_deg: float, vertical_fov_deg: float, aspect: float) -> bool:
	var vertical_rad := deg_to_rad(vertical_fov_deg * 0.5)
	var horizontal_rad := atan(tan(vertical_rad) * aspect)
	var angular_radius := deg_to_rad(diameter_deg * 0.5)
	var yaw_rad := atan2(float(direction[0]), -float(direction[2]))
	var pitch_rad := asin(clampf(float(direction[1]), -1.0, 1.0))
	if float(direction[2]) >= 0.0:
		return false
	var horizontal_margin := asin(clampf(cos(pitch_rad) * sin(horizontal_rad - absf(yaw_rad)), -1.0, 1.0))
	var vertical_margin := asin(clampf(cos(yaw_rad) * cos(pitch_rad) * sin(vertical_rad) - absf(float(direction[1])) * cos(vertical_rad), -1.0, 1.0))
	return horizontal_margin + 0.000000000001 >= angular_radius and vertical_margin + 0.000000000001 >= angular_radius


static func center_offset(direction: Array, distance_m: float) -> Array[float]:
	return [float(direction[0]) * distance_m, float(direction[1]) * distance_m, float(direction[2]) * distance_m]


static func sample_rectangle(random: V2Random, yaw_bounds: Array, pitch_bounds: Array) -> Array[float]:
	return [random.uniform(float(yaw_bounds[0]), float(yaw_bounds[1])),
		rad_to_deg(asin(random.uniform(sin(deg_to_rad(float(pitch_bounds[0]))), sin(deg_to_rad(float(pitch_bounds[1]))))))]


static func sample_annulus(random: V2Random, reference: Array, minimum_deg: float, maximum_deg: float) -> Array[float]:
	var cosine_distance := random.uniform(cos(deg_to_rad(maximum_deg)), cos(deg_to_rad(minimum_deg)))
	var sine_distance := sqrt(maxf(0.0, 1.0 - cosine_distance * cosine_distance))
	var azimuth := random.uniform(0.0, TAU)
	var horizontal := normalized(cross([0.0, 1.0, 0.0], reference))
	var vertical := normalized(cross(reference, horizontal))
	var candidate: Array[float] = []
	for axis_index in 3:
		candidate.append(float(reference[axis_index]) * cosine_distance + (horizontal[axis_index] * cos(azimuth) + vertical[axis_index] * sin(azimuth)) * sine_distance)
	return angles_deg(normalized(candidate))
