class_name ScenarioEngine
extends RefCounted

const SAMPLE_STEP_S: float = 1.0 / 240.0
const ERROR_BIN_DEG: float = 0.1
const MAX_DURATION_S: float = 120.0

var definition: ScenarioDefinition
var timeline := AimTimeline.new()
var rng := RandomNumberGenerator.new()
var targets: Array[Dictionary] = []
var duration_s: float = 30.0
var elapsed_s: float = 0.0
var integrated_s: float = 0.0
var scenario_seed: int = 0
var completed: bool = false
var paused: bool = false
var invalid_reason: String = ""
var shots: int = 0
var hits: int = 0
var expired: int = 0
var spawned: int = 0
var first_shot_hits: int = 0
var attempted_targets: int = 0
var last_hit_s: float = 0.0
var on_target_s: float = 0.0
var angular_error_sum_deg_s: float = 0.0
var previous_on_target: bool = false
var loss_started_s: float = 0.0
var acquisition_ms: Array[float] = []
var shot_error_deg: Array[float] = []
var reacquisition_ms: Array[float] = []
var path_efficiencies: Array[float] = []
var error_histogram := PackedFloat64Array()
var frame_ms := PackedFloat64Array()
var frame_index: int = 0
var frame_count: int = 0
var max_frametime_ms: float = 0.0


func _init() -> void:
	error_histogram.resize(1801)
	frame_ms.resize(4096)


func start(source: ScenarioDefinition, seed_value: int, seconds: float, initial_yaw_deg: float = 0.0, initial_pitch_deg: float = 0.0) -> bool:
	if source == null or not source.validate().is_empty() or not is_finite(seconds) or seconds <= 0.0 or seconds > MAX_DURATION_S:
		invalid_reason = "Définition ou durée invalide."
		return false
	definition = source.duplicate()
	scenario_seed = seed_value
	rng.seed = seed_value
	duration_s = seconds
	elapsed_s = 0.0
	integrated_s = 0.0
	completed = false
	paused = false
	invalid_reason = ""
	shots = 0
	hits = 0
	expired = 0
	spawned = 0
	first_shot_hits = 0
	attempted_targets = 0
	last_hit_s = 0.0
	on_target_s = 0.0
	angular_error_sum_deg_s = 0.0
	previous_on_target = false
	loss_started_s = 0.0
	acquisition_ms.clear()
	shot_error_deg.clear()
	reacquisition_ms.clear()
	path_efficiencies.clear()
	error_histogram.fill(0.0)
	frame_index = 0
	frame_count = 0
	max_frametime_ms = 0.0
	timeline.reset(initial_yaw_deg, initial_pitch_deg)
	targets.clear()
	for target_index in definition.active_targets:
		targets.append({"yaw_deg": 0.0, "pitch_deg": 0.0, "born_s": 0.0, "attempts": 0,
			"phase_rad": 0.0, "path_start_deg": 0.0, "initial_error_deg": 0.0})
		spawn_target(target_index, 0.0)
	return invalid_reason.is_empty()


func record_aim(time_s: float, yaw_deg: float, pitch_deg: float) -> void:
	if not paused and not completed and time_s <= duration_s:
		timeline.push(time_s, yaw_deg, pitch_deg)


func record_frame(delta_s: float) -> void:
	if delta_s > 0.0 and is_finite(delta_s):
		max_frametime_ms = maxf(max_frametime_ms, delta_s * 1000.0)
		frame_ms[frame_index] = delta_s * 1000.0
		frame_index = (frame_index + 1) % frame_ms.size()
		frame_count = mini(frame_count + 1, frame_ms.size())


func spawn_target(target_index: int, time_s: float) -> void:
	var previous_direction := target_direction(target_index, time_s) if targets[target_index].get("id", 0) > 0 else Vector3.ZERO
	if definition.has_lifecycle():
		targets[target_index].lifetime_s = definition.lifetime_s
		targets[target_index].expires_s = time_s + definition.lifetime_s
		targets[target_index].respawn_from_direction = previous_direction
	spawn_target_geometry(target_index, time_s)
	if not definition.has_lifecycle():
		return
	var target: Dictionary = targets[target_index]
	target.lifetime_s = rng.randf_range(definition.lifetime_min_s, definition.lifetime_max_s)
	target.expires_s = time_s + float(target.lifetime_s)
	if definition.family == "tracking" and previous_direction != Vector3.ZERO:
		if definition.motion != "waypoints":
			var previous_angles := angles_from_direction_deg(previous_direction)
			var separated := false
			for attempt in 32:
				var next_direction := target_direction(target_index, time_s)
				var next_angles := angles_from_direction_deg(next_direction)
				separated = Vector2(previous_angles.x, previous_angles.y).dot(Vector2(next_angles.x, next_angles.y)) <= 0.0 and AimGeometry.angular_error_deg(previous_direction, next_direction) >= definition.maximum_angular_diameter_deg() * 1.5
				if separated:
					break
				target.phase_rad = rng.randf_range(0.0, TAU)
			if not separated:
				if definition.motion == "circle":
					target.phase_rad = atan2(-previous_angles.y / definition.pitch_extent_deg, -previous_angles.x / definition.yaw_extent_deg)
				elif definition.motion == "strafe":
					target.phase_rad = 0.0 if previous_angles.x >= 0.0 else PI
				else:
					target.phase_rad = -PI * 0.5 if (previous_angles.y if definition.motion == "vertical" else previous_angles.x) >= 0.0 else PI * 0.5
	if definition.has_tracking_rhythm():
		target.tracking_rhythm = TrackingRhythm.build(definition, scenario_seed, int(target.id), float(target.lifetime_s))


func spawn_target_geometry(target_index: int, time_s: float) -> void:
	if definition.spawn_pattern == "mixed":
		spawn_mixed_target(target_index, time_s)
		return
	if definition.motion == "waypoints":
		spawn_waypoint_target(target_index, time_s)
		return
	if definition.revision >= 5 and definition.layout == "scatter" and definition.active_targets > 1:
		var angles_deg: Vector2 = scatter_spawn_angles_deg(target_index, time_s)
		if not angles_deg.is_finite():
			invalid_reason = "Réserve de dispersion incompatible : aucune cible remplacée."
			return
		initialize_new_target(target_index, time_s, angles_deg)
		return
	var target: Dictionary = targets[target_index]
	var old_direction := AimGeometry.direction(float(target.yaw_deg), float(target.pitch_deg))
	var candidate_yaw_deg: float = 0.0
	var candidate_pitch_deg: float = 0.0
	var found: bool = false
	for attempt in 128:
		candidate_yaw_deg = rng.randf_range(-definition.yaw_extent_deg, definition.yaw_extent_deg)
		candidate_pitch_deg = rng.randf_range(-definition.pitch_extent_deg, definition.pitch_extent_deg)
		if definition.layout == "grid":
			var cell_index := rng.randi_range(0, 8)
			candidate_yaw_deg = float(cell_index % 3 - 1) * definition.yaw_extent_deg
			candidate_pitch_deg = float(cell_index / 3 - 1) * definition.pitch_extent_deg
		if definition.motion != "static":
			candidate_yaw_deg *= 0.45
			candidate_pitch_deg *= 0.45
		if definition.layout == "lanes":
			candidate_pitch_deg = lerpf(-definition.pitch_extent_deg, definition.pitch_extent_deg, (float(target_index) + 0.5) / definition.active_targets)
		var candidate := AimGeometry.direction(candidate_yaw_deg, candidate_pitch_deg)
		if definition.family != "tracking" and AimGeometry.angular_error_deg(candidate, old_direction) < definition.min_transition_deg:
			continue
		found = true
		for other_index in targets.size():
			if other_index == target_index or (float(targets[other_index].born_s) == 0.0 and int(targets[other_index].get("id", 0)) == 0):
				continue
			if AimGeometry.angular_error_deg(candidate, target_direction(other_index, time_s)) < definition.maximum_angular_diameter_deg() * 1.7:
				found = false
				break
		if found:
			break
	if not found:
		invalid_reason = "Impossible de générer une cible sans chevauchement."
	target.yaw_deg = candidate_yaw_deg
	target.pitch_deg = candidate_pitch_deg
	target.born_s = time_s
	target.attempts = 0
	target.phase_rad = rng.randf_range(0.0, TAU)
	if definition.has_diameter_variation():
		target.angular_diameter_deg = rng.randf_range(definition.angular_diameter_min_deg, definition.angular_diameter_max_deg)
	if definition.has_distance_variation():
		target.distance_m = rng.randf_range(definition.distance_min_m, definition.distance_max_m)
	if definition.motion == "reactive":
		build_reactive_path(target)
	target.path_start_deg = timeline.angular_path_deg
	spawned += 1
	target.id = spawned
	target.initial_error_deg = AimGeometry.angular_error_deg(
		AimGeometry.direction(timeline.last_yaw_deg, timeline.last_pitch_deg), target_direction(target_index, time_s))


func scatter_candidate_is_safe(target_index: int, time_s: float, angles_deg: Vector2) -> bool:
	var candidate: Vector3 = AimGeometry.direction(angles_deg.x, angles_deg.y)
	var target: Dictionary = targets[target_index]
	var old_direction: Vector3 = AimGeometry.direction(float(target.yaw_deg), float(target.pitch_deg))
	if AimGeometry.angular_error_deg(candidate, old_direction) < definition.min_transition_deg:
		return false
	for other_index in targets.size():
		if other_index != target_index and int(targets[other_index].get("id", 0)) > 0:
			if AimGeometry.angular_error_deg(candidate, target_direction(other_index, time_s)) < definition.maximum_angular_diameter_deg() * 1.7:
				return false
	return true


func scatter_spawn_angles_deg(target_index: int, time_s: float, random_attempts: int = 128) -> Vector2:
	for attempt in clampi(random_attempts, 0, 128):
		var candidate_deg := Vector2(rng.randf_range(-definition.yaw_extent_deg, definition.yaw_extent_deg),
			rng.randf_range(-definition.pitch_extent_deg, definition.pitch_extent_deg))
		if scatter_candidate_is_safe(target_index, time_s, candidate_deg):
			return candidate_deg
	var reserve: Array[Vector2] = definition.scatter_reserve_angles_deg()
	var first_index: int = rng.randi_range(0, reserve.size() - 1)
	for offset in reserve.size():
		var candidate_deg: Vector2 = reserve[(first_index + offset) % reserve.size()]
		if scatter_candidate_is_safe(target_index, time_s, candidate_deg):
			return candidate_deg
	return Vector2(INF, INF)


func initialize_new_target(target_index: int, time_s: float, angles_deg: Vector2) -> void:
	var target: Dictionary = targets[target_index]
	target.yaw_deg = float(angles_deg.x)
	target.pitch_deg = float(angles_deg.y)
	target.born_s = time_s
	target.attempts = 0
	target.phase_rad = 0.0
	if definition.has_diameter_variation() and definition.diameter_motion != "perspective":
		target.angular_diameter_deg = rng.randf_range(definition.angular_diameter_min_deg, definition.angular_diameter_max_deg)
	if definition.has_distance_variation() and definition.motion != "waypoints":
		target.distance_m = rng.randf_range(definition.distance_min_m, definition.distance_max_m)
	target.path_start_deg = timeline.angular_path_deg
	spawned += 1
	target.id = spawned
	target.initial_error_deg = AimGeometry.angular_error_deg(
		AimGeometry.direction(timeline.last_yaw_deg, timeline.last_pitch_deg), target_direction(target_index, time_s))


func angles_from_direction_deg(direction: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(clampf(direction.y, -1.0, 1.0))))


func spawn_mixed_target(target_index: int, time_s: float) -> void:
	var target: Dictionary = targets[target_index]
	var old_direction: Vector3 = AimGeometry.direction(float(target.yaw_deg), float(target.pitch_deg))
	var small_transition: bool = rng.randf() < definition.small_transition_probability
	var minimum_deg: float = definition.small_transition_min_deg if small_transition else definition.large_transition_min_deg
	var maximum_deg: float = definition.small_transition_max_deg if small_transition else definition.large_transition_max_deg
	var angles_deg := Vector2(INF, INF)
	var horizontal: Vector3 = old_direction.cross(Vector3.UP).normalized()
	var vertical: Vector3 = horizontal.cross(old_direction).normalized()
	for attempt in 128:
		var candidate_deg: Vector2
		if small_transition:
			var offset_rad: float = deg_to_rad(rng.randf_range(minimum_deg, maximum_deg))
			var bearing_rad: float = rng.randf_range(0.0, TAU)
			candidate_deg = angles_from_direction_deg(old_direction * cos(offset_rad) +
				(horizontal * cos(bearing_rad) + vertical * sin(bearing_rad)) * sin(offset_rad))
		else:
			candidate_deg = Vector2(rng.randf_range(-definition.yaw_extent_deg, definition.yaw_extent_deg),
				rng.randf_range(-definition.pitch_extent_deg, definition.pitch_extent_deg))
		var separation_deg: float = AimGeometry.angular_error_deg(old_direction, AimGeometry.direction(candidate_deg.x, candidate_deg.y))
		if absf(candidate_deg.x) <= definition.yaw_extent_deg and absf(candidate_deg.y) <= definition.pitch_extent_deg and separation_deg >= minimum_deg and separation_deg <= maximum_deg:
			angles_deg = candidate_deg
			break
	if not angles_deg.is_finite():
		var goal: Vector3 = Vector3.FORWARD
		if not small_transition or AimGeometry.angular_error_deg(old_direction, goal) < maximum_deg:
			goal = AimGeometry.direction(-definition.yaw_extent_deg if float(target.yaw_deg) >= 0.0 else definition.yaw_extent_deg, 0.0)
		var goal_error_deg: float = AimGeometry.angular_error_deg(old_direction, goal)
		var offset_deg: float = minf((minimum_deg + maximum_deg) * 0.5, (minimum_deg + goal_error_deg) * 0.5)
		angles_deg = angles_from_direction_deg(old_direction.slerp(goal, offset_deg / goal_error_deg).normalized())
	target.transition_kind = "small" if small_transition else "large"
	initialize_new_target(target_index, time_s, angles_deg)


func opposite_waypoint_value(current_value: float, minimum_value: float, maximum_value: float) -> float:
	var midpoint: float = (minimum_value + maximum_value) * 0.5
	var margin: float = (maximum_value - minimum_value) * 0.1
	return rng.randf_range(midpoint + margin, maximum_value) if current_value <= midpoint else rng.randf_range(minimum_value, midpoint - margin)


func spawn_waypoint_target(target_index: int, time_s: float) -> void:
	var target: Dictionary = targets[target_index]
	var pose := Vector3(rng.randf_range(-definition.yaw_extent_deg, definition.yaw_extent_deg),
		rng.randf_range(-definition.pitch_extent_deg, definition.pitch_extent_deg),
		rng.randf_range(definition.distance_min_m, definition.distance_max_m))
	if definition.has_lifecycle() and target.get("respawn_from_direction", Vector3.ZERO) != Vector3.ZERO:
		var previous_angles := angles_from_direction_deg(target.respawn_from_direction)
		pose.x = opposite_waypoint_value(previous_angles.x, -definition.yaw_extent_deg, definition.yaw_extent_deg)
		pose.y = opposite_waypoint_value(previous_angles.y, -definition.pitch_extent_deg, definition.pitch_extent_deg)
	var poses: Array[Vector3] = [pose]
	var times_s := PackedFloat64Array([0.0])
	var kinds := PackedStringArray()
	var segment_end_s: float = 0.0
	while segment_end_s < MAX_DURATION_S:
		var order: Array[int] = [0, 1, 2, 3]
		for shuffle_index in range(order.size() - 1, 0, -1):
			var swap_index: int = rng.randi_range(0, shuffle_index)
			var previous_kind: int = order[shuffle_index]
			order[shuffle_index] = order[swap_index]
			order[swap_index] = previous_kind
		for kind in order:
			var next_pose: Vector3 = pose
			if kind == 0 or kind == 2:
				next_pose.x = opposite_waypoint_value(pose.x, -definition.yaw_extent_deg, definition.yaw_extent_deg)
			if kind == 1 or kind == 2:
				next_pose.y = opposite_waypoint_value(pose.y, -definition.pitch_extent_deg, definition.pitch_extent_deg)
			if kind == 3:
				next_pose.z = opposite_waypoint_value(pose.z, definition.distance_min_m, definition.distance_max_m)
			var angular_path_deg: float = Vector2(next_pose.x - pose.x, next_pose.y - pose.y).length()
			var segment_duration_s: float = maxf(definition.waypoint_min_duration_s,
				maxf(1.5 * angular_path_deg / definition.speed_deg_s, 1.5 * absf(next_pose.z - pose.z) / definition.depth_speed_m_s))
			segment_end_s += segment_duration_s
			poses.append(next_pose)
			times_s.append(segment_end_s)
			kinds.append(["horizontal", "vertical", "diagonal", "depth"][kind])
			pose = next_pose
			if segment_end_s >= MAX_DURATION_S:
				break
	target.waypoint_poses = poses
	target.waypoint_times_s = times_s
	target.waypoint_kinds = kinds
	initialize_new_target(target_index, time_s, Vector2(poses[0].x, poses[0].y))


func motion_time_s(target: Dictionary, time_s: float) -> float:
	var local_s := time_s - float(target.born_s) if definition.has_lifecycle() else time_s
	if definition.has_tracking_rhythm() and target.has("tracking_rhythm"):
		return TrackingRhythm.distance_deg(target.tracking_rhythm, local_s) / definition.speed_deg_s
	return local_s


func waypoint_pose(target: Dictionary, time_s: float) -> Vector3:
	var poses: Array[Vector3] = target.waypoint_poses
	var times_s: PackedFloat64Array = target.waypoint_times_s
	var age_s: float = clampf(absf(motion_time_s(target, time_s)) if definition.has_tracking_rhythm() else time_s - float(target.born_s), 0.0, times_s[times_s.size() - 1])
	var lower_index: int = 0
	var upper_index: int = times_s.size() - 1
	while upper_index - lower_index > 1:
		var midpoint_index: int = (lower_index + upper_index) / 2
		if times_s[midpoint_index] <= age_s:
			lower_index = midpoint_index
		else:
			upper_index = midpoint_index
	var fraction: float = (age_s - times_s[lower_index]) / (times_s[upper_index] - times_s[lower_index])
	return poses[lower_index].lerp(poses[upper_index], smoothstep(0.0, 1.0, fraction))


func target_direction(target_index: int, time_s: float) -> Vector3:
	var target: Dictionary = targets[target_index]
	if definition.motion == "waypoints":
		var pose: Vector3 = waypoint_pose(target, time_s)
		return AimGeometry.direction(pose.x, pose.y)
	var yaw_deg: float = float(target.yaw_deg)
	var pitch_deg: float = float(target.pitch_deg)
	if definition.motion == "static":
		return AimGeometry.direction(yaw_deg, pitch_deg)
	if definition.motion == "reactive":
		return AimGeometry.direction(yaw_deg + reactive_offset_deg(target, time_s), pitch_deg)
	var amplitude_yaw_deg := definition.yaw_extent_deg * (0.9 if definition.family == "tracking" else 0.45)
	var amplitude_pitch_deg := definition.pitch_extent_deg * (0.9 if definition.family == "tracking" else 0.45)
	var amplitude_deg := amplitude_pitch_deg if definition.motion == "vertical" else amplitude_yaw_deg
	if definition.motion == "diagonal":
		amplitude_deg = sqrt(amplitude_yaw_deg * amplitude_yaw_deg + amplitude_pitch_deg * amplitude_pitch_deg)
	elif definition.motion == "circle":
		amplitude_deg = maxf(amplitude_yaw_deg, amplitude_pitch_deg)
	var local_s := motion_time_s(target, time_s)
	var phase_rad := float(target.phase_rad) + definition.speed_deg_s / amplitude_deg * local_s
	if definition.family == "tracking":
		yaw_deg = 0.0
		pitch_deg = 0.0
	match definition.motion:
		"horizontal": yaw_deg += amplitude_yaw_deg * sin(phase_rad)
		"vertical": pitch_deg += amplitude_pitch_deg * sin(phase_rad)
		"diagonal":
			yaw_deg += amplitude_yaw_deg * sin(phase_rad)
			pitch_deg += amplitude_pitch_deg * sin(phase_rad)
		"circle":
			yaw_deg += amplitude_yaw_deg * cos(phase_rad)
			pitch_deg += amplitude_pitch_deg * sin(phase_rad)
		"strafe":
			yaw_deg += strafe_offset_deg(local_s, float(target.phase_rad), amplitude_yaw_deg)
	return AimGeometry.direction(yaw_deg, pitch_deg)


func build_reactive_path(target: Dictionary) -> void:
	var amplitude_deg: float = definition.yaw_extent_deg * 0.45
	var interval_s: float = 3.0 * amplitude_deg / definition.speed_deg_s + definition.turn_duration_s
	var offsets_deg := PackedFloat64Array()
	offsets_deg.resize(ceili(MAX_DURATION_S / interval_s) + 2)
	for waypoint_index in offsets_deg.size():
		offsets_deg[waypoint_index] = rng.randf_range(-amplitude_deg, amplitude_deg)
	target.reactive_interval_s = interval_s
	target.reactive_offsets_deg = offsets_deg


func reactive_offset_deg(target: Dictionary, time_s: float) -> float:
	var offsets_deg: PackedFloat64Array = target.reactive_offsets_deg
	var coordinate: float = clampf((time_s - float(target.born_s)) / float(target.reactive_interval_s), 0.0, float(offsets_deg.size() - 1))
	var waypoint_index: int = mini(floori(coordinate), offsets_deg.size() - 2)
	return lerpf(offsets_deg[waypoint_index], offsets_deg[waypoint_index + 1], smoothstep(0.0, 1.0, coordinate - waypoint_index))


func target_geometry(target_index: int, time_s: float) -> Dictionary:
	if definition == null or target_index < 0 or target_index >= targets.size() or not is_finite(time_s) or time_s < 0.0:
		return {}
	var direction: Vector3 = target_direction(target_index, time_s)
	var distance_m: float = target_distance_m(target_index, time_s)
	var diameter_deg: float = target_angular_diameter_deg(target_index, time_s)
	return {"direction": direction, "distance_m": distance_m, "angular_diameter_deg": diameter_deg,
		"center_offset_m": direction * distance_m, "radius_m": distance_m * sin(deg_to_rad(diameter_deg) * 0.5)}


func target_distance_m(target_index: int, time_s: float) -> float:
	if definition == null or target_index < 0 or target_index >= targets.size() or not is_finite(time_s) or time_s < 0.0:
		return 0.0
	if definition.motion == "waypoints":
		return waypoint_pose(targets[target_index], time_s).z
	return float(targets[target_index].get("distance_m", definition.distance_m))


func target_angular_diameter_deg(target_index: int, time_s: float) -> float:
	var diameter_deg := base_target_angular_diameter_deg(target_index, time_s)
	if definition != null and definition.has_lifecycle() and diameter_deg > 0.0:
		var target: Dictionary = targets[target_index]
		var age_fraction := clampf((time_s - float(target.born_s)) / float(target.lifetime_s), 0.0, 1.0)
		diameter_deg *= lerpf(1.0, definition.lifecycle_shrink_ratio, age_fraction)
	return diameter_deg


func base_target_angular_diameter_deg(target_index: int, time_s: float) -> float:
	if definition == null or target_index < 0 or target_index >= targets.size() or not is_finite(time_s) or time_s < 0.0:
		return 0.0
	var target: Dictionary = targets[target_index]
	if definition.diameter_motion == "perspective":
		var sphere_radius_m: float = definition.distance_m * sin(deg_to_rad(definition.angular_diameter_deg * 0.5))
		return rad_to_deg(2.0 * asin(sphere_radius_m / target_distance_m(target_index, time_s)))
	var initial_diameter_deg: float = float(target.get("angular_diameter_deg", definition.angular_diameter_deg))
	if definition.diameter_motion == "shrink":
		var age_fraction: float = clampf((time_s - float(target.born_s)) / definition.lifetime_s, 0.0, 1.0)
		return lerpf(initial_diameter_deg, definition.angular_diameter_min_deg, age_fraction)
	return initial_diameter_deg


func strafe_offset_deg(time_s: float, phase_rad: float, amplitude_deg: float) -> float:
	var turn_s: float = definition.turn_duration_s
	var half_period_s: float = 2.0 * amplitude_deg / definition.speed_deg_s + turn_s * 0.5
	var cycle_s: float = fposmod(time_s + phase_rad / TAU * half_period_s * 2.0, half_period_s * 2.0)
	var second_half: bool = cycle_s >= half_period_s
	var local_s: float = cycle_s - half_period_s if second_half else cycle_s
	var offset_deg: float
	if local_s < turn_s * 0.5:
		offset_deg = -amplitude_deg + definition.speed_deg_s / turn_s * local_s * local_s
	elif local_s <= half_period_s - turn_s * 0.5:
		offset_deg = -amplitude_deg + definition.speed_deg_s * (local_s - turn_s * 0.25)
	else:
		var remaining_s: float = half_period_s - local_s
		offset_deg = amplitude_deg - definition.speed_deg_s / turn_s * remaining_s * remaining_s
	return -offset_deg if second_half else offset_deg


func radius_m(target_index: int = 0, time_s: float = 0.0) -> float:
	return target_distance_m(target_index, time_s) * sin(deg_to_rad(target_angular_diameter_deg(target_index, time_s)) * 0.5)


func expire_targets(time_s: float) -> void:
	if definition.lifetime_s <= 0.0:
		return
	if definition.has_lifecycle():
		while true:
			var earliest_index := -1
			var earliest_s := INF
			for target_index in targets.size():
				var deadline_s := float(targets[target_index].expires_s)
				if deadline_s <= time_s and deadline_s < earliest_s:
					earliest_index = target_index
					earliest_s = deadline_s
			if earliest_index < 0:
				break
			expired += 1
			spawn_target(earliest_index, earliest_s)
			if definition.family == "tracking":
				previous_on_target = false
				loss_started_s = earliest_s
		return
	for target_index in targets.size():
		while float(targets[target_index].born_s) + definition.lifetime_s <= time_s:
			var birth_s: float = float(targets[target_index].born_s) + definition.lifetime_s
			expired += 1
			spawn_target(target_index, birth_s)


func integrate_sample(midpoint_s: float, weight_s: float) -> void:
	if definition.has_lifecycle():
		var start_s := midpoint_s - weight_s * 0.5
		var end_s := midpoint_s + weight_s * 0.5
		expire_targets(start_s)
		while float(targets[0].expires_s) < end_s:
			var deadline_s := float(targets[0].expires_s)
			if deadline_s > start_s:
				integrate_geometry_sample((start_s + deadline_s) * 0.5, deadline_s - start_s)
			expire_targets(deadline_s)
			start_s = deadline_s
		if end_s > start_s:
			integrate_geometry_sample((start_s + end_s) * 0.5, end_s - start_s)
		return
	integrate_geometry_sample(midpoint_s, weight_s)


func integrate_geometry_sample(midpoint_s: float, weight_s: float) -> void:
	var pose := timeline.sample(midpoint_s)
	var direction := AimGeometry.direction(pose.x, pose.y)
	var geometry: Dictionary = target_geometry(0, midpoint_s)
	var error_deg := AimGeometry.angular_error_deg(direction, geometry.direction)
	var is_on_target := error_deg <= float(geometry.angular_diameter_deg) * 0.5
	angular_error_sum_deg_s += error_deg * weight_s
	error_histogram[clampi(int(floor(error_deg / ERROR_BIN_DEG)), 0, error_histogram.size() - 1)] += weight_s
	if is_on_target:
		on_target_s += weight_s
		if not previous_on_target:
			reacquisition_ms.append(maxf(midpoint_s - loss_started_s, 0.0) * 1000.0)
	elif previous_on_target:
		loss_started_s = midpoint_s
	previous_on_target = is_on_target


func advance_to(time_s: float) -> void:
	if definition == null or paused or completed:
		return
	var end_s := clampf(time_s, elapsed_s, duration_s)
	if definition.family == "tracking":
		while integrated_s + SAMPLE_STEP_S <= end_s + 0.000000001:
			integrate_sample(integrated_s + SAMPLE_STEP_S * 0.5, SAMPLE_STEP_S)
			integrated_s += SAMPLE_STEP_S
		if end_s >= duration_s and integrated_s < duration_s:
			var remaining_s := duration_s - integrated_s
			integrate_sample(integrated_s + remaining_s * 0.5, remaining_s)
			integrated_s = duration_s
		if definition.has_lifecycle():
			expire_targets(integrated_s)
	else:
		timeline.sample(end_s)
		expire_targets(end_s)
	elapsed_s = end_s
	completed = end_s >= duration_s
	if timeline.overflow_count > 0:
		invalid_reason = "Tampon d'input saturé : cette séance ne peut pas servir à la calibration."


func shoot(time_s: float, aim_direction: Vector3) -> bool:
	if definition == null or paused or completed or definition.family == "tracking":
		return false
	advance_to(time_s)
	if completed:
		return false
	shots += 1
	var nearest_distance_m: float = INF
	var hit_index: int = -1
	var closest_error_deg: float = 180.0
	var nearest_index: int = 0
	for target_index in targets.size():
		var geometry: Dictionary = target_geometry(target_index, time_s)
		var center_direction: Vector3 = geometry.direction
		var error_deg := AimGeometry.angular_error_deg(aim_direction, center_direction)
		if error_deg < closest_error_deg:
			closest_error_deg = error_deg
			nearest_index = target_index
		var distance_m := AimGeometry.ray_sphere_distance(aim_direction, geometry.center_offset_m, float(geometry.radius_m))
		if distance_m < nearest_distance_m:
			nearest_distance_m = distance_m
			hit_index = target_index
	shot_error_deg.append(closest_error_deg)
	var selected_index := hit_index if hit_index >= 0 else nearest_index
	var target: Dictionary = targets[selected_index]
	if int(target.attempts) == 0:
		attempted_targets += 1
	target.attempts = int(target.attempts) + 1
	if hit_index < 0:
		return false
	hits += 1
	if int(target.attempts) == 1:
		first_shot_hits += 1
	var acquisition_s := time_s - (last_hit_s if definition.family == "switching" else float(target.born_s))
	acquisition_ms.append(maxf(acquisition_s, 0.0) * 1000.0)
	last_hit_s = time_s
	if definition.motion == "static":
		var path_deg := timeline.angular_path_deg - float(target.path_start_deg)
		var diameter_deg: float = float(target_geometry(hit_index, time_s).angular_diameter_deg)
		path_efficiencies.append(clampf(maxf(float(target.initial_error_deg) - diameter_deg * 0.5, 0.0) / maxf(path_deg, 0.000001), 0.0, 1.0))
	spawn_target(hit_index, time_s)
	return true


func weighted_error_percentile(fraction: float) -> float:
	var cumulative_s: float = 0.0
	for bin_index in error_histogram.size():
		cumulative_s += error_histogram[bin_index]
		if cumulative_s >= integrated_s * fraction and cumulative_s > 0.0:
			return minf(float(bin_index + 1) * ERROR_BIN_DEG, 180.0)
	return 0.0


func result(profile: Dictionary, aspect: float, finished: bool) -> Dictionary:
	var frames: Array = []
	for frame_number in frame_count:
		frames.append(frame_ms[frame_number])
	var metrics := {"shots": shots, "hits": hits, "misses": shots - hits, "targets_spawned": spawned,
		"targets_expired": expired, "accuracy_fraction": float(hits) / shots if shots > 0 else 0.0,
		"accuracy_pct": 100.0 * hits / shots if shots > 0 else null,
		"hits_per_s": float(hits) / maxf(elapsed_s, 0.000001),
		"first_shot_accuracy_pct": 100.0 * first_shot_hits / attempted_targets if attempted_targets > 0 else null,
		"acquisition_median_ms": ScoringService.median(acquisition_ms),
		"acquisition_p95_ms": ScoringService.percentile(acquisition_ms, 0.95),
		"acquisition_samples": acquisition_ms.size(),
		"shot_error_median_deg": ScoringService.median(shot_error_deg),
		"on_target_time_s": on_target_s, "target_exposed_time_s": integrated_s,
		"on_target_ratio": on_target_s / maxf(integrated_s, 0.000001),
		"angular_error_mean_deg": angular_error_sum_deg_s / maxf(integrated_s, 0.000001),
		"angular_error_p95_deg": weighted_error_percentile(0.95), "error_bin_deg": ERROR_BIN_DEG,
		"reacquisition_median_ms": ScoringService.median(reacquisition_ms),
		"reacquisition_samples": reacquisition_ms.size(),
		"path_efficiency_median": ScoringService.median(path_efficiencies),
		"path_efficiency_samples": path_efficiencies.size(),
		"angular_path_deg": timeline.angular_path_deg, "input_events": timeline.event_count,
		"input_buffer_overflows": timeline.overflow_count}
	var report := {"schema_version": 1, "app_version": str(ProjectSettings.get_setting("application/config/version")), "engine_version": "4.7.2", "renderer": "compatibility",
		"scenario_id": definition.scenario_id, "scenario_revision": definition.revision,
		"scenario_fingerprint": definition.fingerprint(), "family": definition.family, "seed": scenario_seed,
		"duration_s": duration_s, "active_duration_s": elapsed_s, "completed": finished and completed,
		"valid": invalid_reason.is_empty(), "invalid_reason": invalid_reason, "profile": profile.duplicate(true),
		"aspect": aspect, "score_version": ScoringService.version_for(definition), "reference_hits_s": definition.reference_hits_s, "metrics": metrics,
		"performance": {"frame_samples": frame_count, "frametime_p95_ms": ScoringService.percentile(frames, 0.95),
			"frametime_p99_ms": ScoringService.percentile(frames, 0.99), "max_frametime_ms": max_frametime_ms},
		"comparison_key": ScoringService.comparison_key(definition, duration_s, profile, aspect)}
	if report.score_version == ScoringService.EXPIRY_VERSION:
		report.score_policy = "expiry_accuracy_v2"
		metrics.effective_accuracy_fraction = float(hits) / maxf(float(shots + expired), 1.0)
		metrics.effective_accuracy_pct = metrics.effective_accuracy_fraction * 100.0 if shots + expired > 0 else null
		metrics.failed_actions = shots - hits + expired
	report.score = ScoringService.score(report, definition.reference_hits_s)
	return report
