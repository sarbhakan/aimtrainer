class_name TrackingRhythm
extends RefCounted


static func build(definition: ScenarioDefinition, seed_value: int, target_id: int, lifetime_s: float) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ (target_id * 104729)
	var direction_sign := -1.0 if random.randf() < 0.5 else 1.0
	var cruise_max_deg_s := maxf(definition.tracking_speed_min_deg_s, definition.tracking_speed_max_deg_s * 0.78)
	var initial_speed_deg_s := direction_sign * random.randf_range(definition.tracking_speed_min_deg_s, cruise_max_deg_s)
	var schedule := {"times_s": PackedFloat64Array([0.0]), "speeds_deg_s": PackedFloat64Array([initial_speed_deg_s]),
		"distances_deg": PackedFloat64Array([0.0]), "kinds": PackedStringArray()}
	while float(schedule.times_s[schedule.times_s.size() - 1]) < lifetime_s:
		append_segment(schedule, random.randf_range(0.45, 0.9), float(schedule.speeds_deg_s[schedule.speeds_deg_s.size() - 1]), "hold")
		var bands_deg_s: Array[float] = [random.randf_range(maxf(definition.tracking_speed_min_deg_s, definition.tracking_speed_max_deg_s * 0.82), definition.tracking_speed_max_deg_s),
			random.randf_range(definition.tracking_speed_min_deg_s, minf(definition.tracking_speed_min_deg_s * 1.3, definition.tracking_speed_max_deg_s))]
		if random.randf() < 0.5:
			bands_deg_s.reverse()
		for band_deg_s in bands_deg_s:
			var accelerating := band_deg_s > absf(float(schedule.speeds_deg_s[schedule.speeds_deg_s.size() - 1]))
			append_ramp(schedule, direction_sign * band_deg_s, random.randf_range(0.55, 0.95) if accelerating else random.randf_range(0.2, 0.38),
				definition.tracking_ramp_acceleration_deg_s2, "accelerate" if accelerating else "brake")
			append_segment(schedule, random.randf_range(0.45, 0.9), direction_sign * band_deg_s, "hold")
		append_ramp(schedule, 0.0, random.randf_range(0.22, 0.38), definition.tracking_ramp_acceleration_deg_s2, "brake")
		append_segment(schedule, random.randf_range(0.18, 0.35), 0.0, "pause")
		direction_sign = -direction_sign
		append_ramp(schedule, direction_sign * random.randf_range(definition.tracking_speed_min_deg_s, cruise_max_deg_s),
			random.randf_range(0.3, 0.55), definition.tracking_ramp_acceleration_deg_s2, "restart")
	return schedule


static func append_ramp(schedule: Dictionary, speed_deg_s: float, requested_duration_s: float, acceleration_deg_s2: float, kind: String) -> void:
	var previous_speed_deg_s := float(schedule.speeds_deg_s[schedule.speeds_deg_s.size() - 1])
	var duration_s := maxf(requested_duration_s, 1.5 * absf(speed_deg_s - previous_speed_deg_s) / acceleration_deg_s2)
	append_segment(schedule, duration_s, speed_deg_s, kind)


static func append_segment(schedule: Dictionary, duration_s: float, speed_deg_s: float, kind: String) -> void:
	var times_s: PackedFloat64Array = schedule.times_s
	var speeds_deg_s: PackedFloat64Array = schedule.speeds_deg_s
	var distances_deg: PackedFloat64Array = schedule.distances_deg
	var kinds: PackedStringArray = schedule.kinds
	distances_deg.append(distances_deg[distances_deg.size() - 1] + duration_s * (speeds_deg_s[speeds_deg_s.size() - 1] + speed_deg_s) * 0.5)
	times_s.append(times_s[times_s.size() - 1] + duration_s)
	speeds_deg_s.append(speed_deg_s)
	kinds.append(kind)
	schedule.times_s = times_s
	schedule.speeds_deg_s = speeds_deg_s
	schedule.distances_deg = distances_deg
	schedule.kinds = kinds


static func segment_at(schedule: Dictionary, age_s: float) -> int:
	var times_s: PackedFloat64Array = schedule.times_s
	var lower_index := 0
	var upper_index := times_s.size() - 1
	while upper_index - lower_index > 1:
		var midpoint_index := (lower_index + upper_index) / 2
		if times_s[midpoint_index] <= age_s:
			lower_index = midpoint_index
		else:
			upper_index = midpoint_index
	return lower_index


static func distance_deg(schedule: Dictionary, age_s: float) -> float:
	var times_s: PackedFloat64Array = schedule.times_s
	var speeds_deg_s: PackedFloat64Array = schedule.speeds_deg_s
	var distances_deg: PackedFloat64Array = schedule.distances_deg
	var bounded_s := clampf(age_s, 0.0, times_s[times_s.size() - 1])
	var segment_index := segment_at(schedule, bounded_s)
	var duration_s := times_s[segment_index + 1] - times_s[segment_index]
	var local_s := bounded_s - times_s[segment_index]
	var fraction := local_s / duration_s
	var ramp_integral_s := duration_s * fraction * fraction * fraction * (1.0 - 0.5 * fraction)
	return (distances_deg[segment_index] + speeds_deg_s[segment_index] * local_s +
		(speeds_deg_s[segment_index + 1] - speeds_deg_s[segment_index]) * ramp_integral_s)


static func speed_deg_s(schedule: Dictionary, age_s: float) -> float:
	var times_s: PackedFloat64Array = schedule.times_s
	var speeds_deg_s: PackedFloat64Array = schedule.speeds_deg_s
	var bounded_s := clampf(age_s, 0.0, times_s[times_s.size() - 1])
	var segment_index := segment_at(schedule, bounded_s)
	var fraction := (bounded_s - times_s[segment_index]) / (times_s[segment_index + 1] - times_s[segment_index])
	return lerpf(speeds_deg_s[segment_index], speeds_deg_s[segment_index + 1], smoothstep(0.0, 1.0, fraction))


static func phase_at(schedule: Dictionary, age_s: float) -> String:
	return str(schedule.kinds[segment_at(schedule, age_s)])
