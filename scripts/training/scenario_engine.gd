class_name ScenarioEngine
extends RefCounted

const SAMPLE_STEP_S: float = 1.0 / 240.0
const ERROR_BIN_DEG: float = 0.1

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
	if source == null or not source.validate().is_empty() or not is_finite(seconds) or seconds <= 0.0 or seconds > 120.0:
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
		var candidate := AimGeometry.direction(candidate_yaw_deg, candidate_pitch_deg)
		if definition.family != "tracking" and AimGeometry.angular_error_deg(candidate, old_direction) < definition.min_transition_deg:
			continue
		found = true
		for other_index in targets.size():
			if other_index == target_index or (float(targets[other_index].born_s) == 0.0 and int(targets[other_index].get("id", 0)) == 0):
				continue
			if AimGeometry.angular_error_deg(candidate, target_direction(other_index, time_s)) < definition.angular_diameter_deg * 1.7:
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
	target.path_start_deg = timeline.angular_path_deg
	spawned += 1
	target.id = spawned
	target.initial_error_deg = AimGeometry.angular_error_deg(
		AimGeometry.direction(timeline.last_yaw_deg, timeline.last_pitch_deg), target_direction(target_index, time_s))


func target_direction(target_index: int, time_s: float) -> Vector3:
	var target: Dictionary = targets[target_index]
	var yaw_deg: float = float(target.yaw_deg)
	var pitch_deg: float = float(target.pitch_deg)
	if definition.motion == "static":
		return AimGeometry.direction(yaw_deg, pitch_deg)
	var amplitude_yaw_deg := definition.yaw_extent_deg * (0.9 if definition.family == "tracking" else 0.45)
	var amplitude_pitch_deg := definition.pitch_extent_deg * (0.9 if definition.family == "tracking" else 0.45)
	var amplitude_deg := amplitude_pitch_deg if definition.motion == "vertical" else amplitude_yaw_deg
	var phase_rad := float(target.phase_rad) + definition.speed_deg_s / amplitude_deg * time_s
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
			phase_rad = float(target.phase_rad) + definition.speed_deg_s * PI / (2.0 * amplitude_yaw_deg) * time_s
			yaw_deg += amplitude_yaw_deg * 2.0 / PI * asin(sin(phase_rad))
	return AimGeometry.direction(yaw_deg, pitch_deg)


func radius_m() -> float:
	return definition.distance_m * sin(deg_to_rad(definition.angular_diameter_deg) * 0.5)


func expire_targets(time_s: float) -> void:
	if definition.lifetime_s <= 0.0:
		return
	for target_index in targets.size():
		while float(targets[target_index].born_s) + definition.lifetime_s <= time_s:
			var birth_s: float = float(targets[target_index].born_s) + definition.lifetime_s
			expired += 1
			spawn_target(target_index, birth_s)


func integrate_sample(midpoint_s: float, weight_s: float) -> void:
	var pose := timeline.sample(midpoint_s)
	var direction := AimGeometry.direction(pose.x, pose.y)
	var error_deg := AimGeometry.angular_error_deg(direction, target_direction(0, midpoint_s))
	var is_on_target := error_deg <= definition.angular_diameter_deg * 0.5
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
		var center_direction := target_direction(target_index, time_s)
		var error_deg := AimGeometry.angular_error_deg(aim_direction, center_direction)
		if error_deg < closest_error_deg:
			closest_error_deg = error_deg
			nearest_index = target_index
		var distance_m := AimGeometry.ray_sphere_distance(aim_direction, center_direction * definition.distance_m, radius_m())
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
		path_efficiencies.append(clampf(maxf(float(target.initial_error_deg) - definition.angular_diameter_deg * 0.5, 0.0) / maxf(path_deg, 0.000001), 0.0, 1.0))
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
		"shot_error_median_deg": ScoringService.median(shot_error_deg),
		"on_target_time_s": on_target_s, "target_exposed_time_s": integrated_s,
		"on_target_ratio": on_target_s / maxf(integrated_s, 0.000001),
		"angular_error_mean_deg": angular_error_sum_deg_s / maxf(integrated_s, 0.000001),
		"angular_error_p95_deg": weighted_error_percentile(0.95), "error_bin_deg": ERROR_BIN_DEG,
		"reacquisition_median_ms": ScoringService.median(reacquisition_ms),
		"path_efficiency_median": ScoringService.median(path_efficiencies),
		"angular_path_deg": timeline.angular_path_deg, "input_events": timeline.event_count,
		"input_buffer_overflows": timeline.overflow_count}
	var report := {"schema_version": 1, "app_version": str(ProjectSettings.get_setting("application/config/version")), "engine_version": "4.7.2",
		"scenario_id": definition.scenario_id, "scenario_revision": definition.revision,
		"scenario_fingerprint": definition.fingerprint(), "family": definition.family, "seed": scenario_seed,
		"duration_s": duration_s, "active_duration_s": elapsed_s, "completed": finished and completed,
		"valid": invalid_reason.is_empty(), "invalid_reason": invalid_reason, "profile": profile.duplicate(true),
		"aspect": aspect, "score_version": ScoringService.VERSION, "metrics": metrics,
		"performance": {"frame_samples": frame_count, "frametime_p95_ms": ScoringService.percentile(frames, 0.95),
			"frametime_p99_ms": ScoringService.percentile(frames, 0.99), "max_frametime_ms": max_frametime_ms},
		"comparison_key": ScoringService.comparison_key(definition, duration_s, profile, aspect)}
	report.score = ScoringService.score(report, definition.reference_hits_s)
	return report
