class_name V2Spawner
extends RefCounted

const REVISION: String = "2026-10-12-v2.0"
const EYE_Y_M: float = 1.6

var program: Dictionary = {}
var session_seed_hex: String = ""
var aspect: float = 16.0 / 9.0
var vertical_fov_deg: float = 70.53280043291679
var transition_bags: Dictionary = {}
var grid_orders: Dictionary = {}


func configure(definition: Dictionary, seed_hex: String, frozen_aspect: float, fov_deg: float) -> void:
	program = definition
	session_seed_hex = seed_hex
	aspect = frozen_aspect
	vertical_fov_deg = fov_deg
	transition_bags.clear()
	grid_orders.clear()


func stream(phase_id: String, domain: String, slot: int, generation: int, purpose: String) -> V2Random:
	return V2Random.new(V2Random.public_seed(REVISION, session_seed_hex, String(program.program_id), String(program.difficulty), phase_id, "%s/%d/%d/%s" % [domain, slot, generation, purpose]))


func make(phase: Dictionary, slot: int, generation: int, at_s: float, anchor_deg: Array, living: Array) -> Dictionary:
	var motion_seed: int = V2Random.public_seed(REVISION, session_seed_hex, String(program.program_id), String(program.difficulty), String(phase.id), "motion/%d/%d/initial_state" % [slot, generation])
	var motion: Dictionary = V2Motion.build(phase.motion, motion_seed, slot, maxf(60.0, float(phase.duration_s)))
	if motion.is_empty():
		return {"ok": false, "error": "motion_compilation_failure"}
	motion.distance_m = float(phase.distance_m)
	var transition: Array = _transition(phase, generation)
	var target: Dictionary = {"identity": "%s/%s/%d/%d" % [program.program_id, phase.id, slot, generation], "slot": slot, "generation": generation, "phase_id": phase.id, "born_s": at_s, "motion": motion, "first_rendered_s": null, "first_render_ack_s": null, "hp_max": float(phase.lifecycle.get("hp_max", 0.0)), "damage": 0.0, "fallback_used": false, "motion_seed_uint32": motion_seed, "anchor_yaw_pitch_deg": anchor_deg.duplicate(), "transition_angle_deg": transition.duplicate(), "size": phase.size.duplicate(true), "diameter_deg": float(phase.diameter_deg), "distance_m": float(phase.distance_m)}
	var random: V2Random = stream(String(phase.id), "layout", slot, generation, "candidate")
	var distribution: String = String(phase.spawn.coordinate_distribution)
	if String(phase.spawn.kind) == "trajectory_initial_state":
		return _finish(target, phase, motion, false, -1)
	if String(phase.spawn.kind) == "grid_without_overlap":
		var eligible: Array = []
		var nodes: Array = phase.spawn.nodes_yaw_pitch_deg
		if generation == 0:
			if not grid_orders.has(phase.id):
				var initial_nodes: Array = range(nodes.size())
				stream(String(phase.id), "layout", 0, 0, "initial_nodes").shuffle(initial_nodes)
				grid_orders[phase.id] = initial_nodes
			eligible.append(int(grid_orders[phase.id][slot]))
		else:
			for node_index: int in nodes.size():
				if V2Geometry.separation_deg(V2Geometry.direction_deg(float(nodes[node_index][0]), float(nodes[node_index][1])), V2Geometry.direction_deg(float(anchor_deg[0]), float(anchor_deg[1]))) < 1e-7:
					continue
				eligible.append(node_index)
			for live: Dictionary in living:
				eligible.erase(int(live.get("grid_node", -1)))
		if eligible.is_empty():
			return {"ok": false, "error": "spawn_constraint_failure"}
		var grid_node: int = int(eligible[random.randint(0, eligible.size() - 1)])
		motion = V2Motion.with_origin(motion, float(nodes[grid_node][0]), float(nodes[grid_node][1]))
		target.grid_node = grid_node
		if not _valid(phase, motion, at_s, anchor_deg, transition, living):
			return {"ok": false, "error": "spawn_constraint_failure"}
		return _finish(target, phase, motion, false, grid_node)
	for candidate_index: int in int(phase.spawn.random_candidate_limit):
		var candidate: Dictionary = _candidate(phase, motion, random, anchor_deg, transition, distribution)
		if not candidate.is_empty() and _valid(phase, candidate, at_s, anchor_deg, transition, living):
			return _finish(target, phase, candidate, false, candidate_index)
	var best_hash: String = ""
	var best_motion: Dictionary = {}
	var best_index: int = -1
	var fallback: Dictionary = phase.spawn.fallback
	var dimensions: Array = _lattice_dimensions(phase, slot)
	for horizontal_index: int in int(dimensions[0]):
		for vertical_index: int in int(dimensions[1]):
			var index: int = horizontal_index * int(dimensions[1]) + vertical_index
			var candidate: Dictionary
			if String(fallback.kind) == "valid_cycle_fraction_lattice_minimum_hash":
				candidate = V2Motion.with_cycle(motion, float(horizontal_index) / float(fallback.fraction_bins))
			else:
				var yaw_bounds: Array = _yaw_bounds(phase, slot)
				var yaw_deg: float = float(yaw_bounds[0]) + horizontal_index * float(fallback.get("yaw_step_deg", 0.25))
				var pitch_deg: float = float(phase.spawn.pitch_deg[0]) + vertical_index * float(fallback.get("pitch_step_deg", 0.25))
				candidate = V2Motion.with_origin(motion, yaw_deg, pitch_deg)
			if candidate.is_empty() or not _valid(phase, candidate, at_s, anchor_deg, transition, living):
				continue
			var tuple: Array = [REVISION, session_seed_hex, program.program_id, program.difficulty, phase.id, "layout/%d/%d/fallback_lattice_%d" % [slot, generation, index]]
			var hash_text: String = JSON.stringify(tuple).sha256_text()
			if best_hash.is_empty() or hash_text < best_hash:
				best_hash = hash_text
				best_motion = candidate
				best_index = index
	if best_motion.is_empty():
		return {"ok": false, "error": "spawn_constraint_failure"}
	return _finish(target, phase, best_motion, true, best_index)


func _candidate(phase: Dictionary, motion: Dictionary, random: V2Random, anchor_deg: Array, transition: Array, distribution: String) -> Dictionary:
	if distribution == "sample_cycle_fraction_conditioned_on_spawn_constraints":
		return V2Motion.with_cycle(motion, random.uniform01())
	if String(phase.motion.kind) != "static":
		var bounds: Array = _yaw_bounds(phase, int(motion.slot))
		return V2Motion.with_origin(motion, random.uniform(float(bounds[0]), float(bounds[1])))
	var angles: Array
	if distribution == "uniform_solid_angle_spherical_annulus_then_envelope_rejection":
		angles = V2Geometry.sample_annulus(random, V2Geometry.direction_deg(float(anchor_deg[0]), float(anchor_deg[1])), float(transition[0]), float(transition[1]))
	else:
		angles = V2Geometry.sample_rectangle(random, phase.spawn.yaw_deg, phase.spawn.pitch_deg)
	return V2Motion.with_origin(motion, float(angles[0]), float(angles[1]))


func _valid(phase: Dictionary, motion: Dictionary, at_s: float, anchor_deg: Array, transition: Array, living: Array) -> bool:
	var initial: Dictionary = V2Motion.sample(motion, 0.0)
	var yaw_deg: float = float(initial.yaw_deg)
	var pitch_deg: float = float(initial.pitch_deg)
	if yaw_deg < float(phase.spawn.yaw_deg[0]) - 1e-9 or yaw_deg > float(phase.spawn.yaw_deg[1]) + 1e-9 or pitch_deg < float(phase.spawn.pitch_deg[0]) - 1e-9 or pitch_deg > float(phase.spawn.pitch_deg[1]) + 1e-9:
		return false
	var direction: Array = V2Geometry.direction_deg(yaw_deg, pitch_deg)
	var transition_deg: float = V2Geometry.separation_deg(direction, V2Geometry.direction_deg(float(anchor_deg[0]), float(anchor_deg[1])))
	if transition_deg < float(transition[0]) - 1e-9 or transition_deg > float(transition[1]) + 1e-9:
		return false
	if phase.spawn.has("transition_band_bag") and float(transition[1]) < 32.0 and transition_deg >= float(transition[1]):
		return false
	var diameter_deg: float = float(phase.diameter_deg)
	var distance_m: float = float(phase.distance_m)
	var radius_m: float = distance_m * sin(deg_to_rad(diameter_deg * 0.5))
	if not V2Geometry.sphere_fits(direction, diameter_deg, vertical_fov_deg, aspect) or EYE_Y_M + distance_m * float(direction[1]) - radius_m < float(phase.envelope.minimum_floor_clearance_m) - 1e-9:
		return false
	for live: Dictionary in living:
		var pose: Dictionary = sample_target(live, at_s)
		var required_gap_deg: float = (diameter_deg + float(pose.diameter_deg)) * 0.5 + float(phase.spawn.minimum_silhouette_gap_deg)
		if V2Geometry.separation_deg(direction, pose.direction) < required_gap_deg - 1e-9:
			return false
	return true


func _transition(phase: Dictionary, generation: int) -> Array:
	if not phase.spawn.has("transition_band_bag"):
		return phase.spawn.transition_angle_deg.duplicate()
	if not transition_bags.has(phase.id) or transition_bags[phase.id].is_empty():
		var band_bag: Array = []
		for band: Dictionary in phase.spawn.transition_band_bag.bands:
			for copy_index: int in int(band.copies):
				band_bag.append(band.angle_deg.duplicate())
		stream(String(phase.id), "layout", 0, generation, "transition_bag").shuffle(band_bag)
		transition_bags[phase.id] = band_bag
	return transition_bags[phase.id].pop_front()


func _yaw_bounds(phase: Dictionary, slot: int = 0) -> Array:
	if phase.spawn.has("chambers"):
		return phase.spawn.chambers[slot].yaw_deg
	return phase.spawn.get("candidate_yaw_deg", phase.spawn.yaw_deg)


func _lattice_dimensions(phase: Dictionary, slot: int = 0) -> Array:
	if String(phase.spawn.fallback.kind) == "valid_cycle_fraction_lattice_minimum_hash":
		return [int(phase.spawn.fallback.fraction_bins), 1]
	var bounds: Array = _yaw_bounds(phase, slot)
	var horizontal_count: int = int(round((float(bounds[1]) - float(bounds[0])) / float(phase.spawn.fallback.get("yaw_step_deg", 0.25)))) + 1
	var vertical_count: int = 1
	if String(phase.motion.kind) == "static":
		vertical_count = int(round((float(phase.spawn.pitch_deg[1]) - float(phase.spawn.pitch_deg[0])) / float(phase.spawn.fallback.get("pitch_step_deg", 0.25)))) + 1
	return [horizontal_count, vertical_count]


func _finish(target: Dictionary, phase: Dictionary, motion: Dictionary, fallback_used: bool, candidate_index: int) -> Dictionary:
	target.motion = motion
	target.fallback_used = fallback_used
	target.candidate_index = candidate_index
	target.initial_pose = V2Motion.sample(motion, 0.0)
	target.velocity_bound_deg_s = V2Motion.velocity_bound_deg_s(motion, 0.0, float(phase.duration_s))
	target.ok = true
	target.expiry_s = float(target.born_s) + float(phase.lifecycle.ttl_s) if phase.lifecycle.ttl_s != null else null
	return target


static func sample_target(target: Dictionary, at_s: float) -> Dictionary:
	var age_s: float = maxf(0.0, at_s - float(target.born_s))
	var sample: Dictionary = V2Motion.sample(target.motion, age_s)
	var direction: Array = V2Geometry.direction_deg(float(sample.yaw_deg), float(sample.pitch_deg))
	var distance_m: float = float(sample.distance_m)
	var diameter_deg: float = float(target.diameter_deg)
	var size: Dictionary = target.size
	var radius_m: float
	if String(size.mode) == "world_radius_constant":
		radius_m = float(size.reference_distance_m) * sin(deg_to_rad(diameter_deg * 0.5))
		diameter_deg = rad_to_deg(2.0 * asin(radius_m / distance_m))
	else:
		if String(size.mode) == "angular_diameter_linear_over_window":
			diameter_deg = lerpf(float(size.diameter_start_deg), float(size.diameter_end_deg), clampf(age_s / float(size.progress_duration_s), 0.0, 1.0))
		radius_m = distance_m * sin(deg_to_rad(diameter_deg * 0.5))
	return {"yaw_deg": sample.yaw_deg, "pitch_deg": sample.pitch_deg, "distance_m": distance_m, "direction": direction, "center_offset_m": [float(direction[0]) * distance_m, float(direction[1]) * distance_m, float(direction[2]) * distance_m], "radius_m": radius_m, "diameter_deg": diameter_deg}
