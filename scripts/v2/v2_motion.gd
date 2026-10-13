class_name V2Motion
extends RefCounted

const COMPILER_VERSION: String = "motion_reference_v2.0"
const EVENT_LIMIT: int = 10000


static func compile_reactive(motion: Dictionary, seed: int, horizon_s: float = 60.0, initial_yaw_deg: Variant = null) -> Dictionary:
	var initialization: V2Random = _rng_child(seed, "initialization")
	var event_random: V2Random = _rng_child(seed, "events")
	var vertical_random: V2Random = _rng_child(seed, "vertical_phase")
	var lower_deg: float = float(motion.yaw_bounds_deg[0])
	var upper_deg: float = float(motion.yaw_bounds_deg[1])
	var inset_deg: float = float(motion.boundary.trigger_inset_deg)
	var left_deg: float = lower_deg + inset_deg
	var right_deg: float = upper_deg - inset_deg
	var yaw_deg: float = initialization.uniform(left_deg, right_deg)
	if initial_yaw_deg != null:
		if not left_deg - 1e-9 <= float(initial_yaw_deg) or not float(initial_yaw_deg) <= right_deg + 1e-9:
			push_error("INITIAL_YAW_OUTSIDE_SOFT_THRESHOLDS")
			return {}
		yaw_deg = float(initial_yaw_deg)
	var direction_sign: float = 1.0 if initialization.uniform01() < float(motion.initial_direction_prob_positive) else -1.0
	var last_speed_deg_s: float = initialization.uniform(float(motion.yaw_speed_abs_deg_s[0]), float(motion.yaw_speed_abs_deg_s[1]))
	var velocity_deg_s: float = direction_sign * last_speed_deg_s
	var vertical_phase_rad: float = vertical_random.uniform(0.0, TAU)
	var initial_state: Dictionary = {"yaw_deg": yaw_deg, "velocity_deg_s": velocity_deg_s, "vertical_phase_rad": vertical_phase_rad}
	var piece: Dictionary = _constant_piece(motion, event_random, 0.0, yaw_deg, velocity_deg_s)
	var control_end_s: float = _us_round(float(piece.origin_s) + float(piece.duration_s))
	var now_s: float = 0.0
	var armed: bool = true
	var pieces: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var boundary_side: String = ""
	if (yaw_deg >= right_deg - 1e-10 and velocity_deg_s > 0.0) or (yaw_deg <= left_deg + 1e-10 and velocity_deg_s < 0.0):
		boundary_side = "boundary_right" if velocity_deg_s > 0.0 else "boundary_left"
		events.append({"time_us": 0, "kind": boundary_side, "yaw_deg": yaw_deg, "velocity_deg_s": velocity_deg_s})
		piece = _ramp_piece(motion, 0.0, yaw_deg, velocity_deg_s, -last_speed_deg_s if velocity_deg_s > 0.0 else last_speed_deg_s)
		control_end_s = _us_round(float(piece.origin_s) + float(piece.duration_s))
		armed = false
	var stopped: bool = false
	for event_index: int in EVENT_LIMIT:
		if now_s >= horizon_s - 1e-9:
			stopped = true
			break
		var end_s: float = minf(control_end_s, horizon_s)
		var kind: String = "control_end" if control_end_s <= horizon_s else "end"
		var threshold_candidates: Array[Dictionary] = []
		if armed:
			_add_crossing(threshold_candidates, piece, left_deg, -1.0, "boundary_left", now_s, end_s)
			_add_crossing(threshold_candidates, piece, right_deg, 1.0, "boundary_right", now_s, end_s)
		else:
			var current: Array[float] = _evaluate_piece(piece, now_s)
			var returning: bool = (boundary_side == "boundary_right" and current[1] < 0.0) or (boundary_side == "boundary_left" and current[1] > 0.0)
			if left_deg + 1e-8 < current[0] and current[0] < right_deg - 1e-8 and returning:
				armed = true
				continue
			_add_crossing(threshold_candidates, piece, left_deg, 1.0, "rearm", now_s, end_s)
			_add_crossing(threshold_candidates, piece, right_deg, -1.0, "rearm", now_s, end_s)
		if not threshold_candidates.is_empty():
			var candidate: Dictionary = threshold_candidates[0]
			for candidate_index: int in range(1, threshold_candidates.size()):
				var other: Dictionary = threshold_candidates[candidate_index]
				if float(other.time_s) < float(candidate.time_s) or (float(other.time_s) == float(candidate.time_s) and String(other.kind) < String(candidate.kind)):
					candidate = other
			var event_s: float = minf(end_s, maxf(now_s + 0.000001, _us_round(float(candidate.time_s))))
			if event_s <= end_s + 1e-9:
				end_s = event_s
				kind = String(candidate.kind)
		var record: Dictionary = piece.duplicate()
		record.from_s = now_s
		record.to_s = end_s
		pieces.append(record)
		var reached: Array[float] = _evaluate_piece(piece, end_s)
		yaw_deg = reached[0]
		velocity_deg_s = reached[1]
		now_s = end_s
		if now_s >= horizon_s - 1e-9:
			stopped = true
			break
		events.append({"time_us": int(round(now_s * 1000000.0)), "kind": kind, "yaw_deg": yaw_deg, "velocity_deg_s": velocity_deg_s})
		if kind == "rearm":
			armed = true
			if absf(now_s - control_end_s) < 0.0000005:
				events[-1].kind = "rearm_and_control_end"
				if piece.shape == "ramp":
					piece = _constant_piece(motion, event_random, now_s, yaw_deg, float(piece.v1_deg_s))
				else:
					direction_sign = 1.0 if velocity_deg_s >= 0.0 else -1.0
					if event_random.uniform01() < float(motion.direction_flip_probability):
						direction_sign = -direction_sign
					last_speed_deg_s = event_random.uniform(float(motion.yaw_speed_abs_deg_s[0]), float(motion.yaw_speed_abs_deg_s[1]))
					piece = _ramp_piece(motion, now_s, yaw_deg, velocity_deg_s, direction_sign * last_speed_deg_s)
				control_end_s = _us_round(float(piece.origin_s) + float(piece.duration_s))
		elif kind.begins_with("boundary_"):
			var next_velocity_deg_s: float = last_speed_deg_s if kind == "boundary_left" else -last_speed_deg_s
			piece = _ramp_piece(motion, now_s, yaw_deg, velocity_deg_s, next_velocity_deg_s)
			control_end_s = _us_round(float(piece.origin_s) + float(piece.duration_s))
			armed = false
			boundary_side = kind
		elif piece.shape == "ramp":
			piece = _constant_piece(motion, event_random, now_s, yaw_deg, float(piece.v1_deg_s))
			control_end_s = _us_round(float(piece.origin_s) + float(piece.duration_s))
		else:
			direction_sign = 1.0 if velocity_deg_s >= 0.0 else -1.0
			if event_random.uniform01() < float(motion.direction_flip_probability):
				direction_sign = -direction_sign
			last_speed_deg_s = event_random.uniform(float(motion.yaw_speed_abs_deg_s[0]), float(motion.yaw_speed_abs_deg_s[1]))
			piece = _ramp_piece(motion, now_s, yaw_deg, velocity_deg_s, direction_sign * last_speed_deg_s)
			control_end_s = _us_round(float(piece.origin_s) + float(piece.duration_s))
	if not stopped:
		push_error("REACTIVE_EVENT_LIMIT")
		return {}
	if pieces.is_empty() or absf(float(pieces[-1].to_s) - horizon_s) > 1e-6:
		push_error("REACTIVE_TAPE_INCOMPLETE")
		return {}
	return {"compiler_version": COMPILER_VERSION, "seed_u32": seed, "horizon_s": horizon_s, "initial_state": initial_state, "pieces": pieces, "events": events}


static func sample_reactive(tape: Dictionary, time_s: float) -> Array[float]:
	var clamped_s: float = maxf(0.0, minf(float(tape.horizon_s), time_s))
	var pieces: Array = tape.pieces
	var piece_index: int = _record_index(pieces, "to_s", clamped_s)
	return _evaluate_piece(pieces[piece_index], clamped_s)


static func build(motion: Dictionary, seed: int, slot: int = 0, horizon_s: float = 120.0) -> Dictionary:
	return _build(motion, seed, slot, horizon_s, null)


static func with_origin(state: Dictionary, yaw_deg: float, pitch_deg: float = 0.0) -> Dictionary:
	var kind: String = String(state.kind)
	if kind == "static":
		var placed: Dictionary = state.duplicate(true)
		placed.x0 = yaw_deg
		placed.y0 = pitch_deg
		return placed
	if kind == "linear_reflect" and state.m.reflection != "instantaneous_velocity_sign_change":
		push_error("SMOOTH_REFLECTION_REQUIRES_CYCLE_FRACTION")
		return {}
	if kind not in ["linear_reflect", "reactive_axis", "reactive_lanes", "angular_bounce"]:
		push_error("MOTION_ORIGIN_NOT_REPOSITIONABLE:" + kind)
		return {}
	var placed: Dictionary = _build(state.m, int(state.seed), int(state.slot), float(state.horizon_s), yaw_deg)
	if not placed.is_empty():
		placed.distance_m = float(state.distance_m)
	return placed


static func with_cycle(state: Dictionary, cycle_fraction: float) -> Dictionary:
	if state.kind != "linear_reflect" or state.m.reflection == "instantaneous_velocity_sign_change":
		push_error("MOTION_HAS_NO_SMOOTH_REFLECTION_CYCLE")
		return {}
	var placed: Dictionary = state.duplicate(true)
	placed.cycle = cycle_fraction
	return placed


static func sample(state: Dictionary, time_s: float) -> Dictionary:
	var motion: Dictionary = state.m
	var kind: String = String(state.kind)
	var yaw_deg: float = 0.0
	var pitch_deg: float = 0.0
	var distance_m: float = float(state.get("distance_m", 4.0))
	var yaw_rate_deg_s: float = 0.0
	var pitch_rate_deg_s: float = 0.0
	var distance_rate_m_s: float = 0.0
	match kind:
		"static":
			yaw_deg = float(state.get("x0", 0.0))
			pitch_deg = float(state.get("y0", 0.0))
		"reactive_axis", "reactive_lanes":
			var horizontal: Array[float] = sample_reactive(state.tape, time_s)
			yaw_deg = horizontal[0]
			yaw_rate_deg_s = horizontal[1]
			var vertical: Dictionary = motion.vertical
			var omega_rad_s: float = TAU / float(vertical.period_s)
			var angle_rad: float = TAU * time_s / float(vertical.period_s) + float(state.phase)
			pitch_deg = float(motion.lanes_pitch_deg[int(state.slot)]) + float(vertical.amplitude_deg) * sin(angle_rad)
			pitch_rate_deg_s = float(vertical.amplitude_deg) * omega_rad_s * cos(angle_rad)
		"sinusoid_axis":
			var angle_rad: float = float(motion.omega_rad_s) * time_s + float(state.phase)
			var coordinate_deg: float = float(motion.amplitude_deg) * sin(angle_rad)
			var rate_deg_s: float = float(motion.amplitude_deg) * float(motion.omega_rad_s) * cos(angle_rad)
			if motion.axis == "yaw":
				yaw_deg = coordinate_deg
				yaw_rate_deg_s = rate_deg_s
				pitch_deg = float(motion.orthogonal_coordinate_deg)
			else:
				yaw_deg = float(motion.orthogonal_coordinate_deg)
				pitch_deg = coordinate_deg
				pitch_rate_deg_s = rate_deg_s
		"depth_sines":
			var yaw_rad: float = float(motion.yaw_omega_rad_s) * time_s + float(state.phases[0])
			var pitch_rad: float = float(motion.pitch_omega_rad_s) * time_s + float(state.phases[1])
			var distance_rad: float = float(motion.distance_omega_rad_s) * time_s + float(state.phases[2])
			yaw_deg = float(motion.yaw_amplitude_deg) * sin(yaw_rad)
			pitch_deg = float(motion.pitch_amplitude_deg) * sin(pitch_rad)
			distance_m = float(motion.distance_center_m) + float(motion.distance_amplitude_m) * sin(distance_rad)
			yaw_rate_deg_s = float(motion.yaw_amplitude_deg) * float(motion.yaw_omega_rad_s) * cos(yaw_rad)
			pitch_rate_deg_s = float(motion.pitch_amplitude_deg) * float(motion.pitch_omega_rad_s) * cos(pitch_rad)
			distance_rate_m_s = float(motion.distance_amplitude_m) * float(motion.distance_omega_rad_s) * cos(distance_rad)
		"angular_ellipse":
			var ellipse: Dictionary = state.ellipse
			var arc_rad: float = float(state.arc0) + float(state.sign) * deg_to_rad(float(motion.path_angular_speed_deg_s)) * time_s
			var parameter_rad: float = _ellipse_parameter(ellipse, arc_rad)
			var parameter_rate_rad_s: float = float(state.sign) * deg_to_rad(float(motion.path_angular_speed_deg_s)) / _ellipse_metric(ellipse, parameter_rad)
			yaw_deg = float(motion.yaw_amplitude_deg) * cos(parameter_rad)
			pitch_deg = float(motion.pitch_amplitude_deg) * sin(parameter_rad)
			yaw_rate_deg_s = -float(motion.yaw_amplitude_deg) * sin(parameter_rad) * parameter_rate_rad_s
			pitch_rate_deg_s = float(motion.pitch_amplitude_deg) * cos(parameter_rad) * parameter_rate_rad_s
		"linear_reflect":
			var lower_deg: float = float(motion.yaw_bounds_deg[0])
			var upper_deg: float = float(motion.yaw_bounds_deg[1])
			var speed_deg_s: float = float(motion.yaw_speed_deg_s)
			var horizontal: Array[float]
			if motion.reflection == "instantaneous_velocity_sign_change":
				horizontal = _reflected(float(state.x0), float(state.sign) * speed_deg_s, time_s, lower_deg, upper_deg)
			else:
				var turn_s: float = float(motion.turn_duration_s)
				var inset_deg: float = float(motion.turn_entry_inset_deg)
				var straight_s: float = float(motion.straight_segment_duration_s)
				var period_s: float = 2.0 * (straight_s + turn_s)
				var cycle_s: float = fposmod(time_s + float(state.cycle) * period_s, period_s)
				if cycle_s < straight_s:
					horizontal = [lower_deg + inset_deg + speed_deg_s * cycle_s, speed_deg_s]
				elif cycle_s < straight_s + turn_s:
					var ramp: Array[float] = _signed_ramp(speed_deg_s, -speed_deg_s, turn_s, cycle_s - straight_s)
					horizontal = [upper_deg - inset_deg + ramp[1], ramp[0]]
				elif cycle_s < 2.0 * straight_s + turn_s:
					horizontal = [upper_deg - inset_deg - speed_deg_s * (cycle_s - straight_s - turn_s), -speed_deg_s]
				else:
					var ramp: Array[float] = _signed_ramp(-speed_deg_s, speed_deg_s, turn_s, cycle_s - 2.0 * straight_s - turn_s)
					horizontal = [lower_deg + inset_deg + ramp[1], ramp[0]]
				if float(state.sign) < 0.0:
					horizontal[0] = lower_deg + upper_deg - horizontal[0]
					horizontal[1] = -horizontal[1]
			yaw_deg = horizontal[0]
			yaw_rate_deg_s = horizontal[1]
			pitch_deg = float(motion.lanes_pitch_deg[int(state.slot)])
		"angular_bounce":
			var bounces: Array = state.bounces
			var record: Dictionary = bounces[_record_index(bounces, "end", time_s)]
			var chamber: Dictionary = motion.chambers[int(state.slot)]
			var elapsed_s: float = maxf(0.0, time_s - float(record.start))
			var horizontal: Array[float] = _reflected(float(record.x), float(record.v), elapsed_s, float(chamber.yaw_deg[0]), float(chamber.yaw_deg[1]))
			yaw_deg = horizontal[0]
			yaw_rate_deg_s = horizontal[1]
			var age_s: float = float(record.age) + elapsed_s
			var fraction: float = maxf(0.0, minf(1.0, age_s / float(motion.flight_duration_s)))
			pitch_deg = float(chamber.baseline_pitch_deg)
			if bool(record.flight):
				pitch_deg += 4.0 * float(motion.apex_height_above_baseline_deg) * fraction * (1.0 - fraction)
				if 0.0 <= age_s and age_s <= float(motion.flight_duration_s):
					pitch_rate_deg_s = 4.0 * float(motion.apex_height_above_baseline_deg) * (1.0 - 2.0 * fraction) / float(motion.flight_duration_s)
		_:
			push_error("UNKNOWN_MOTION_KIND:" + kind)
			return {}
	return {"yaw_deg": yaw_deg, "pitch_deg": pitch_deg, "distance_m": distance_m, "yaw_rate_deg_s": yaw_rate_deg_s, "pitch_rate_deg_s": pitch_rate_deg_s, "distance_rate_m_s": distance_rate_m_s}


static func velocity_bound_deg_s(state: Dictionary, start_s: float, end_s: float) -> float:
	var motion: Dictionary = state.m
	var yaw_bound_deg_s: float = 0.0
	var pitch_bound_deg_s: float = 0.0
	match String(state.kind):
		"static":
			return 0.0
		"linear_reflect":
			return absf(float(motion.yaw_speed_deg_s))
		"reactive_axis", "reactive_lanes":
			var lower_s: float = clampf(minf(start_s, end_s), 0.0, float(state.tape.horizon_s))
			var upper_s: float = clampf(maxf(start_s, end_s), 0.0, float(state.tape.horizon_s))
			for piece: Dictionary in state.tape.pieces:
				if float(piece.to_s) < lower_s or float(piece.from_s) > upper_s:
					continue
				var first: Array[float] = _evaluate_piece(piece, maxf(lower_s, float(piece.from_s)))
				var last: Array[float] = _evaluate_piece(piece, minf(upper_s, float(piece.to_s)))
				yaw_bound_deg_s = maxf(yaw_bound_deg_s, maxf(absf(first[1]), absf(last[1])))
			pitch_bound_deg_s = absf(float(motion.vertical.amplitude_deg)) * TAU / float(motion.vertical.period_s)
		"sinusoid_axis":
			return absf(float(motion.amplitude_deg) * float(motion.omega_rad_s))
		"depth_sines":
			yaw_bound_deg_s = absf(float(motion.yaw_amplitude_deg) * float(motion.yaw_omega_rad_s))
			pitch_bound_deg_s = absf(float(motion.pitch_amplitude_deg) * float(motion.pitch_omega_rad_s))
		"angular_bounce":
			yaw_bound_deg_s = absf(float(motion.yaw_speed_deg_s))
			pitch_bound_deg_s = 4.0 * absf(float(motion.apex_height_above_baseline_deg)) / float(motion.flight_duration_s)
		"angular_ellipse":
			var yaw_amplitude_rad: float = absf(float(state.ellipse.a))
			var pitch_amplitude_rad: float = absf(float(state.ellipse.b))
			var minimum_metric: float = minf(yaw_amplitude_rad * maxf(0.0, cos(pitch_amplitude_rad)), pitch_amplitude_rad) if pitch_amplitude_rad < PI / 2.0 else 0.0
			if minimum_metric <= 0.0:
				return INF
			return absf(float(motion.path_angular_speed_deg_s)) * _hypot(yaw_amplitude_rad, pitch_amplitude_rad) / minimum_metric
		_:
			return INF
	return _hypot(yaw_bound_deg_s, pitch_bound_deg_s)


static func _build(motion: Dictionary, seed: int, slot: int, horizon_s: float, initial_yaw_deg: Variant) -> Dictionary:
	var random: V2Random = _rng_child(seed, "initialization")
	var phase_rad: float = random.uniform(0.0, TAU)
	var direction_sign: int = 1 if random.uniform01() < 0.5 else -1
	var state: Dictionary = {"m": motion.duplicate(true), "kind": String(motion.kind), "seed": seed, "slot": slot, "phase": phase_rad, "sign": direction_sign, "horizon_s": horizon_s, "distance_m": float(motion.get("distance_m", 4.0))}
	match String(motion.kind):
		"static", "sinusoid_axis":
			pass
		"reactive_axis", "reactive_lanes":
			state.tape = compile_reactive(motion, seed, horizon_s, initial_yaw_deg)
			if state.tape.is_empty():
				return {}
			state.phase = float(state.tape.initial_state.vertical_phase_rad)
		"linear_reflect":
			state.x0 = random.uniform(float(motion.yaw_bounds_deg[0]), float(motion.yaw_bounds_deg[1]))
			if initial_yaw_deg != null:
				state.x0 = float(initial_yaw_deg)
			state.cycle = random.uniform01()
		"angular_ellipse":
			state.ellipse = _build_ellipse(float(motion.yaw_amplitude_deg), float(motion.pitch_amplitude_deg), int(motion.arc_length_solver.lut_cells))
			state.arc0 = random.uniform01() * float(state.ellipse.length)
		"depth_sines":
			var phases: Array[float] = []
			for phase_index: int in 3:
				phases.append(random.uniform(0.0, TAU))
			state.phases = phases
		"angular_bounce":
			var bounces: Array[Dictionary] = []
			var chamber: Dictionary = motion.chambers[slot]
			var lower_deg: float = float(chamber.yaw_deg[0])
			var upper_deg: float = float(chamber.yaw_deg[1])
			var yaw_deg: float = random.uniform(lower_deg, upper_deg)
			if initial_yaw_deg != null:
				yaw_deg = float(initial_yaw_deg)
			var velocity_deg_s: float = float(direction_sign) * float(motion.yaw_speed_deg_s)
			var age_s: float = random.uniform(float(motion.initial_flight_age_uniform_s[0]), float(motion.initial_flight_age_uniform_s[1]))
			var now_s: float = 0.0
			var flight: bool = true
			while now_s < horizon_s + 1e-9:
				var duration_s: float = float(motion.flight_duration_s) - age_s if flight else random.uniform(float(motion.ground_rest_uniform_s[0]), float(motion.ground_rest_uniform_s[1]))
				bounces.append({"start": now_s, "end": now_s + duration_s, "x": yaw_deg, "v": velocity_deg_s, "age": age_s, "flight": flight})
				var reflected: Array[float] = _reflected(yaw_deg, velocity_deg_s, duration_s, lower_deg, upper_deg)
				yaw_deg = reflected[0]
				velocity_deg_s = reflected[1]
				now_s += duration_s
				if flight:
					if random.uniform01() < float(motion.landing_flip_probability):
						velocity_deg_s = -velocity_deg_s
					if absf(yaw_deg - lower_deg) < 1e-8:
						velocity_deg_s = absf(velocity_deg_s)
					if absf(yaw_deg - upper_deg) < 1e-8:
						velocity_deg_s = -absf(velocity_deg_s)
				flight = not flight
				age_s = 0.0
			state.bounces = bounces
		_:
			push_error("UNKNOWN_MOTION_KIND:" + String(motion.kind))
			return {}
	return state


static func _rng_child(seed: int, purpose: String) -> V2Random:
	return V2Random.new(V2Random.stream_seed([COMPILER_VERSION, "%08x" % seed, purpose]))


static func _us_round(time_s: float) -> float:
	return floor(time_s * 1000000.0 + 0.5) / 1000000.0


static func _plateau_duration(motion: Dictionary, random: V2Random) -> float:
	var draw: float = random.uniform01()
	var cumulative: float = 0.0
	var selected: Dictionary = motion.plateau_duration_mixture[-1]
	for item: Dictionary in motion.plateau_duration_mixture:
		cumulative += float(item.weight)
		if draw < cumulative:
			selected = item
			break
	return random.uniform(float(selected.uniform_duration_s[0]), float(selected.uniform_duration_s[1]))


static func _constant_piece(motion: Dictionary, random: V2Random, time_s: float, yaw_deg: float, velocity_deg_s: float) -> Dictionary:
	var duration_s: float = maxf(0.000001, _us_round(_plateau_duration(motion, random)))
	return {"shape": "constant", "origin_s": time_s, "x_origin_deg": yaw_deg, "v0_deg_s": velocity_deg_s, "v1_deg_s": velocity_deg_s, "duration_s": duration_s}


static func _ramp_piece(motion: Dictionary, time_s: float, yaw_deg: float, velocity_deg_s: float, next_velocity_deg_s: float) -> Dictionary:
	var transition: Dictionary = motion.velocity_transition
	var minimum_s: float = 1.5 * absf(next_velocity_deg_s - velocity_deg_s) / float(transition.acceleration_limit_deg_s2)
	var duration_s: float = maxf(float(transition.nominal_duration_s), minimum_s)
	duration_s = maxf(maxf(_us_round(duration_s), ceil(minimum_s * 1000000.0) / 1000000.0), 0.000001)
	return {"shape": "ramp", "origin_s": time_s, "x_origin_deg": yaw_deg, "v0_deg_s": velocity_deg_s, "v1_deg_s": next_velocity_deg_s, "duration_s": duration_s}


static func _signed_ramp(initial_deg_s: float, final_deg_s: float, duration_s: float, time_s: float) -> Array[float]:
	var elapsed_s: float = maxf(0.0, minf(duration_s, time_s))
	var fraction: float = elapsed_s / duration_s
	var smoothstep: float = fraction * fraction * (3.0 - 2.0 * fraction)
	var velocity_deg_s: float = initial_deg_s + (final_deg_s - initial_deg_s) * smoothstep
	var displacement_deg: float = initial_deg_s * elapsed_s + (final_deg_s - initial_deg_s) * duration_s * (pow(fraction, 3.0) - 0.5 * pow(fraction, 4.0))
	return [velocity_deg_s, displacement_deg]


static func _evaluate_piece(piece: Dictionary, time_s: float) -> Array[float]:
	var elapsed_s: float = maxf(0.0, time_s - float(piece.origin_s))
	if piece.shape == "constant":
		return [float(piece.x_origin_deg) + float(piece.v0_deg_s) * elapsed_s, float(piece.v0_deg_s)]
	var ramp: Array[float] = _signed_ramp(float(piece.v0_deg_s), float(piece.v1_deg_s), float(piece.duration_s), elapsed_s)
	return [float(piece.x_origin_deg) + ramp[1], ramp[0]]


static func _root_position(piece: Dictionary, threshold_deg: float, lower_s: float, upper_s: float) -> float:
	var lower_offset_deg: float = _evaluate_piece(piece, lower_s)[0] - threshold_deg
	for iteration: int in 70:
		var middle_s: float = (lower_s + upper_s) / 2.0
		var middle_offset_deg: float = _evaluate_piece(piece, middle_s)[0] - threshold_deg
		if absf(upper_s - lower_s) < 1e-10:
			return middle_s
		if lower_offset_deg * middle_offset_deg <= 0.0:
			upper_s = middle_s
		else:
			lower_s = middle_s
			lower_offset_deg = middle_offset_deg
	return (lower_s + upper_s) / 2.0


static func _velocity_zero(piece: Dictionary, lower_s: float, upper_s: float) -> Variant:
	var lower_velocity_deg_s: float = _evaluate_piece(piece, lower_s)[1]
	var upper_velocity_deg_s: float = _evaluate_piece(piece, upper_s)[1]
	if lower_velocity_deg_s * upper_velocity_deg_s >= 0.0:
		return null
	for iteration: int in 60:
		var middle_s: float = (lower_s + upper_s) / 2.0
		var middle_velocity_deg_s: float = _evaluate_piece(piece, middle_s)[1]
		if lower_velocity_deg_s * middle_velocity_deg_s <= 0.0:
			upper_s = middle_s
		else:
			lower_s = middle_s
			lower_velocity_deg_s = middle_velocity_deg_s
	return (lower_s + upper_s) / 2.0


static func _first_crossing(piece: Dictionary, threshold_deg: float, desired_sign: float, lower_s: float, upper_s: float) -> Variant:
	var cut_s: Variant = _velocity_zero(piece, lower_s, upper_s)
	var stops_s: Array[float] = [lower_s]
	if cut_s != null:
		stops_s.append(float(cut_s))
	stops_s.append(upper_s)
	for interval_index: int in range(stops_s.size() - 1):
		var begin_s: float = stops_s[interval_index]
		var end_s: float = stops_s[interval_index + 1]
		if end_s - begin_s < 1e-12:
			continue
		var first_deg: float = _evaluate_piece(piece, begin_s)[0]
		var last_deg: float = _evaluate_piece(piece, end_s)[0]
		if desired_sign * (last_deg - first_deg) <= 0.0:
			continue
		if desired_sign * (first_deg - threshold_deg) <= 1e-10 and desired_sign * (last_deg - threshold_deg) >= 0.0:
			var root_s: float = _root_position(piece, threshold_deg, begin_s, end_s)
			if root_s > lower_s + 1e-9:
				return root_s
	return null


static func _add_crossing(candidates: Array[Dictionary], piece: Dictionary, threshold_deg: float, desired_sign: float, kind: String, lower_s: float, upper_s: float) -> void:
	var crossing_s: Variant = _first_crossing(piece, threshold_deg, desired_sign, lower_s, upper_s)
	if crossing_s != null:
		candidates.append({"time_s": float(crossing_s), "kind": kind})


static func _record_index(records: Array, end_key: String, time_s: float) -> int:
	var lower: int = 0
	var upper: int = records.size()
	while lower < upper:
		var middle: int = (lower + upper) >> 1
		if time_s < float(records[middle][end_key]):
			upper = middle
		else:
			lower = middle + 1
	return mini(records.size() - 1, lower)


static func _reflected(origin_deg: float, velocity_deg_s: float, time_s: float, lower_deg: float, upper_deg: float) -> Array[float]:
	var width_deg: float = upper_deg - lower_deg
	var coordinate_deg: float = fposmod(origin_deg - lower_deg + velocity_deg_s * time_s, 2.0 * width_deg)
	var yaw_deg: float = lower_deg + coordinate_deg if coordinate_deg <= width_deg else upper_deg - (coordinate_deg - width_deg)
	var direction_sign: float = 1.0 if coordinate_deg < width_deg else -1.0
	if absf(coordinate_deg) < 1e-10:
		direction_sign = 1.0 if velocity_deg_s >= 0.0 else -1.0
	if absf(coordinate_deg - width_deg) < 1e-10:
		direction_sign = -1.0 if velocity_deg_s >= 0.0 else 1.0
	return [yaw_deg, velocity_deg_s * direction_sign]


static func _build_ellipse(yaw_amplitude_deg: float, pitch_amplitude_deg: float, cells: int) -> Dictionary:
	var ellipse: Dictionary = {"a": deg_to_rad(yaw_amplitude_deg), "b": deg_to_rad(pitch_amplitude_deg), "n": cells, "h": TAU / float(cells)}
	var prefix: Array[float] = [0.0]
	for cell_index: int in cells:
		prefix.append(prefix[-1] + _ellipse_integral(ellipse, float(cell_index) * float(ellipse.h), float(cell_index + 1) * float(ellipse.h)))
	ellipse.prefix = prefix
	ellipse.length = prefix[-1]
	return ellipse


static func _ellipse_metric(ellipse: Dictionary, parameter_rad: float) -> float:
	return _hypot(cos(float(ellipse.b) * sin(parameter_rad)) * (-float(ellipse.a) * sin(parameter_rad)), float(ellipse.b) * cos(parameter_rad))


static func _ellipse_integral(ellipse: Dictionary, begin_rad: float, end_rad: float) -> float:
	return (end_rad - begin_rad) * (_ellipse_metric(ellipse, begin_rad) + 4.0 * _ellipse_metric(ellipse, (begin_rad + end_rad) / 2.0) + _ellipse_metric(ellipse, end_rad)) / 6.0


static func _ellipse_parameter(ellipse: Dictionary, arc_rad: float) -> float:
	arc_rad = fposmod(arc_rad, float(ellipse.length))
	var prefix: Array = ellipse.prefix
	var lower_index: int = 0
	var upper_index: int = prefix.size()
	while lower_index < upper_index:
		var middle_index: int = (lower_index + upper_index) >> 1
		if arc_rad < float(prefix[middle_index]):
			upper_index = middle_index
		else:
			lower_index = middle_index + 1
	var cell_index: int = mini(int(ellipse.n) - 1, lower_index - 1)
	var origin_rad: float = float(cell_index) * float(ellipse.h)
	var lower_rad: float = origin_rad
	var upper_rad: float = lower_rad + float(ellipse.h)
	var target_rad: float = arc_rad - float(prefix[cell_index])
	var parameter_rad: float = lower_rad + (upper_rad - lower_rad) * target_rad / (float(prefix[cell_index + 1]) - float(prefix[cell_index]))
	for iteration: int in 16:
		var error_rad: float = _ellipse_integral(ellipse, origin_rad, parameter_rad) - target_rad
		if absf(error_rad) < 1e-11:
			return parameter_rad
		if error_rad > 0.0:
			upper_rad = parameter_rad
		else:
			lower_rad = parameter_rad
		var candidate_rad: float = parameter_rad - error_rad / _ellipse_metric(ellipse, parameter_rad)
		parameter_rad = candidate_rad if lower_rad < candidate_rad and candidate_rad < upper_rad else (lower_rad + upper_rad) / 2.0
	if absf(_ellipse_integral(ellipse, origin_rad, parameter_rad) - target_rad) > 1e-9:
		push_error("ELLIPSE_INVERSION_DID_NOT_CONVERGE")
	return parameter_rad


static func _hypot(horizontal: float, vertical: float) -> float:
	return sqrt(horizontal * horizontal + vertical * vertical)
