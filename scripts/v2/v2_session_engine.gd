class_name V2SessionEngine
extends RefCounted

const RUNTIME_VERSION: String = "aimlocal.runtime.v2.0"
const CATALOGUE_REVISION: String = "2026-10-12-v2.0"
const INPUT_CONVENTION: String = "received_pose_hold_v1"
const MAX_PENDING_EVENTS: int = 65536
const MAX_POSE_EVENTS: int = 1000000
const INTERSECTION_TIE_M: float = 1e-9
const KILL_TIME_TOLERANCE_S: float = 0.0001

var program: Dictionary = {}
var conditions: Dictionary = {}
var session_seed_hex: String = ""
var duration_s: float = 60.0
var elapsed_s: float = 0.0
var phase_index: int = -1
var phase: Dictionary = {}
var metrics: Dictionary = {}
var completed: bool = false
var invalid_reason: String = ""
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var fire_held: bool = false
var targets: Dictionary = {}
var phases: Array = []
var target_outcomes: Array = []
var manifest: Array = []
var received_pose_trace: Array = []
var pose_event_count: int = 0
var pauses: Array = []
var initial_pose_yaw_pitch_deg: Array = [0.0, 0.0]
var hit_events: Array = []
var frame_times_ms: Array = []
var _pending_events: Array = []
var _sequence: int = 0
var _last_receipt_s: float = 0.0
var _spawner := V2Spawner.new()
var _contact := V2Contact.new()
var _scheduled: Array = []
var _schedule_index: int = 0
var _latencies_ms: Array = []
var _switch_latencies_ms: Array = []
var _contact_intervals: Array = []
var _definite_contact_intervals: Array = []
var _phase_motion_state: Dictionary = {}
var _angular_error_samples: Array = []
var _angular_error_integral_deg_s: float = 0.0
var _last_kill_s: Variant = null
var _last_killed_identity: String = ""
var _first_damage_identities: Dictionary = {}
var _report_cache: Dictionary = {}


func start(definition: Dictionary, seed_hex: String, frozen_conditions: Dictionary = {}, initial_yaw_deg: float = 0.0, initial_pitch_deg: float = 0.0) -> bool:
	var validation: Dictionary = V2Catalog.validate_program(definition)
	if not bool(validation.ok):
		program = {}
		phase = {}
		phases.clear()
		targets.clear()
		_report_cache.clear()
		invalid_reason = "invalid_program_definition:" + str(validation.get("code", "unknown"))
		completed = true
		return false
	program = definition.duplicate(true)
	conditions = frozen_conditions.duplicate(true)
	session_seed_hex = seed_hex
	duration_s = float(definition.duration_s)
	elapsed_s = 0.0
	phase_index = -1
	phase = {}
	metrics = {}
	completed = false
	invalid_reason = ""
	yaw_deg = initial_yaw_deg
	pitch_deg = clampf(initial_pitch_deg, -89.0, 89.0)
	initial_pose_yaw_pitch_deg = [yaw_deg, pitch_deg]
	fire_held = false
	targets.clear()
	phases.clear()
	target_outcomes.clear()
	manifest.clear()
	received_pose_trace.clear()
	pose_event_count = 0
	pauses.clear()
	hit_events.clear()
	frame_times_ms.clear()
	_pending_events.clear()
	_sequence = 0
	_last_receipt_s = 0.0
	_report_cache.clear()
	if seed_hex.length() != 32 or not seed_hex.is_valid_hex_number(false):
		invalidate("invalid_session_seed")
		return false
	for character_index: int in seed_hex.length():
		if seed_hex.substr(character_index, 1) not in "0123456789abcdef":
			invalidate("invalid_session_seed")
			return false
	_spawner.configure(program, seed_hex, float(conditions.get("aspect_ratio", 16.0 / 9.0)), float(conditions.get("vertical_fov_deg", 70.53280043291679)))
	_open_phase(0)
	return invalid_reason.is_empty()


func queue_pose(receipt_s: float, received_yaw_deg: float, received_pitch_deg: float) -> void:
	if not is_finite(received_yaw_deg) or not is_finite(received_pitch_deg):
		invalidate("nonfinite_received_pose")
		return
	_queue_event(receipt_s, "pose", [received_yaw_deg, clampf(received_pitch_deg, -89.0, 89.0)])


func queue_fire(receipt_s: float, pressed: bool) -> void:
	_queue_event(receipt_s, "fire", pressed)


func _queue_event(receipt_s: float, kind: String, value: Variant) -> void:
	if completed:
		return
	if not is_finite(receipt_s) or receipt_s < _last_receipt_s - 1e-12 or receipt_s < elapsed_s - 1e-12:
		invalidate("nonmonotonic_input_receipt")
		return
	if _pending_events.size() >= MAX_PENDING_EVENTS:
		invalidate("input_buffer_overflow")
		return
	_sequence += 1
	_last_receipt_s = receipt_s
	_pending_events.append([receipt_s, _sequence, kind, value])


func advance(to_s: float) -> void:
	if completed:
		return
	if not is_finite(to_s) or to_s < elapsed_s - 1e-12:
		invalidate("clock_discontinuity")
		return
	var requested_s: float = clampf(to_s, elapsed_s, duration_s)
	var events: Array = _pending_events
	_pending_events = []
	for event: Array in events:
		if float(event[0]) > requested_s:
			_pending_events.append(event)
			continue
		_advance_internal(float(event[0]))
		if completed:
			break
		if String(event[2]) == "pose":
			yaw_deg = float(event[3][0])
			pitch_deg = float(event[3][1])
			if pose_event_count == 0 and float(event[0]) == 0.0:
				initial_pose_yaw_pitch_deg = [yaw_deg, pitch_deg]
			pose_event_count += 1
			if bool(conditions.get("retain_input_trace", false)):
				if received_pose_trace.size() >= MAX_POSE_EVENTS:
					invalidate("pose_trace_overflow")
					break
				received_pose_trace.append([int(round(float(event[0]) * 1000000.0)), int(event[1]), yaw_deg, pitch_deg])
		else:
			var pressed: bool = bool(event[3])
			if pressed and not fire_held:
				_press(float(event[0]), int(event[1]))
			fire_held = pressed
	if not completed:
		_advance_internal(requested_s)


func mark_rendered(prepared_identities: Array, visibly_drawn_identities: Array, at_s: float, useful_viewport: bool = true, prepared_receipt: Dictionary = {}) -> void:
	advance(at_s)
	if completed:
		return
	if not useful_viewport:
		invalidate("render_viewport_failure")
		return
	for target: Dictionary in targets.values():
		if target.identity not in prepared_identities:
			continue
		if target.first_render_ack_s == null:
			target.first_render_ack_s = elapsed_s
			target.first_render_ack_receipt = prepared_receipt.duplicate(true)
		if target.identity in visibly_drawn_identities and target.first_rendered_s == null:
			target.first_rendered_s = elapsed_s
			target.first_rendered_receipt = prepared_receipt.duplicate(true)


func record_frame(frame_s: float) -> void:
	if not completed and is_finite(frame_s) and frame_s > 0.0:
		frame_times_ms.append(frame_s * 1000.0)


func invalidate(reason: String) -> void:
	if invalid_reason.is_empty():
		invalid_reason = reason
	if not completed:
		_close_phase(false)
	completed = true
	fire_held = false
	_pending_events.clear()


func abandon(reason: String = "abandoned") -> void:
	invalidate(reason)


func note_pause(at_s: float, reason: String = "manual_pause") -> void:
	advance(at_s)
	if not completed:
		pauses.append({"at_active_s": elapsed_s, "reason": reason})
		fire_held = false


func _advance_internal(to_s: float) -> void:
	var end_s: float = minf(to_s, duration_s)
	while not completed:
		var phase_end_s: float = float(phase.start_s) + float(phase.duration_s)
		var next_s: float = minf(end_s, phase_end_s)
		if _schedule_index < _scheduled.size():
			next_s = minf(next_s, float(_scheduled[_schedule_index].born_s))
		for target: Dictionary in targets.values():
			if target.expiry_s != null:
				next_s = minf(next_s, float(target.expiry_s))
		if next_s > elapsed_s:
			_integrate_to(next_s, phase_end_s)
			if completed:
				return
			elapsed_s = next_s
		if elapsed_s >= phase_end_s:
			_close_phase(true)
			if phase_index + 1 >= program.phases.size():
				completed = true
				fire_held = false
				break
			_open_phase(phase_index + 1)
			if completed:
				break
			continue
		var expired_slots: Array = []
		for slot: Variant in targets:
			if targets[slot].expiry_s != null and elapsed_s >= float(targets[slot].expiry_s):
				expired_slots.append(slot)
		for slot: Variant in expired_slots:
			var target: Dictionary = targets[slot]
			var outcome: String = "expired" if target.first_render_ack_s != null else "censored_technical"
			_resolve(target, outcome, elapsed_s)
			if outcome == "expired":
				metrics.expired += 1
			else:
				invalidate("nonrendered_opportunity")
				return
		while _schedule_index < _scheduled.size() and float(_scheduled[_schedule_index].born_s) <= elapsed_s:
			var planned: Dictionary = _scheduled[_schedule_index].duplicate(true)
			targets[int(planned.slot)] = planned
			_schedule_index += 1
		if elapsed_s >= end_s:
			break


func _open_phase(index: int) -> void:
	phase_index = index
	phase = program.phases[index]
	targets.clear()
	_scheduled.clear()
	_schedule_index = 0
	_latencies_ms.clear()
	_switch_latencies_ms.clear()
	_contact_intervals.clear()
	_definite_contact_intervals.clear()
	_phase_motion_state.clear()
	_angular_error_samples.clear()
	_angular_error_integral_deg_s = 0.0
	_last_kill_s = null
	_last_killed_identity = ""
	_first_damage_identities.clear()
	_contact = V2Contact.new()
	metrics = {"hits": 0, "shots": 0, "misses": 0, "expired": 0, "censored": 0, "opportunities": 0, "contact_s": 0.0, "contact_lower_s": 0.0, "contact_upper_s": 0.0, "exposure_s": float(phase.duration_s), "kills": 0, "useful_damage": 0.0, "credited_work": 0.0}
	if String(phase.lifecycle.kind) == "scheduled_window":
		var schedule: Dictionary = phase.spawn.schedule
		var anchor: Array = [0.0, 0.0]
		for opportunity: int in int(schedule.slots):
			var timing: V2Random = _spawner.stream(String(phase.id), "timing", 0, opportunity, "onset")
			var onset_s: float = float(phase.start_s) + float(schedule.slot_duration_s) * opportunity + timing.uniform(float(schedule.onset_delay_uniform_s[0]), float(schedule.onset_delay_uniform_s[1]))
			var target: Dictionary = _spawner.make(phase, 0, opportunity, onset_s, anchor, [])
			if not bool(target.get("ok", false)):
				invalidate(String(target.get("error", "spawn_constraint_failure")))
				return
			anchor = [target.initial_pose.yaw_deg, target.initial_pose.pitch_deg]
			_scheduled.append(target)
			_record_manifest(target)
		metrics.opportunities = int(schedule.slots)
	else:
		for slot: int in int(phase.target_count):
			var target: Dictionary = _spawner.make(phase, slot, 0, float(phase.start_s), [0.0, 0.0], targets.values())
			if not bool(target.get("ok", false)):
				invalidate(String(target.get("error", "spawn_constraint_failure")))
				return
			targets[slot] = target
			if String(phase.mechanic) == "tracking":
				_phase_motion_state = target.motion
			_record_manifest(target)


func _press(at_s: float, sequence: int) -> void:
	if String(phase.mechanic) not in ["click", "opportunity"]:
		return
	metrics.shots += 1
	var target: Dictionary = _ray_target(at_s)
	if target.is_empty():
		metrics.misses += 1
		return
	metrics.hits += 1
	_latencies_ms.append((at_s - float(target.born_s)) * 1000.0)
	hit_events.append({"at_s": at_s, "sequence": sequence, "identity": target.identity, "kind": "hit"})
	var pose: Dictionary = V2Spawner.sample_target(target, at_s)
	_resolve(target, "hit", at_s)
	if String(phase.lifecycle.kind) != "scheduled_window":
		_replace(target, at_s, [pose.yaw_deg, pose.pitch_deg])


func _ray_target(at_s: float) -> Dictionary:
	var direction: Array = V2Geometry.direction_deg(yaw_deg, pitch_deg)
	var selected: Dictionary = {}
	var nearest_m: float = INF
	for target: Dictionary in targets.values():
		if target.first_rendered_s == null or at_s < float(target.first_rendered_s) or (target.expiry_s != null and at_s >= float(target.expiry_s)):
			continue
		var pose: Dictionary = V2Spawner.sample_target(target, at_s)
		var intersection_m: float = V2Geometry.ray_sphere_distance(direction, pose.center_offset_m, float(pose.radius_m))
		if not is_finite(intersection_m) or intersection_m < 0.0:
			continue
		if intersection_m < nearest_m - INTERSECTION_TIE_M or (absf(intersection_m - nearest_m) <= INTERSECTION_TIE_M and (selected.is_empty() or String(target.identity) < String(selected.identity))):
			selected = target
			nearest_m = intersection_m
	return selected


func _integrate_to(to_s: float, phase_end_s: float) -> void:
	if String(phase.mechanic) not in ["tracking", "switching"]:
		return
	var tracking: bool = String(phase.mechanic) == "tracking"
	if not tracking and not fire_held:
		return
	var cursor_s: float = elapsed_s
	while cursor_s < to_s and not completed:
		var end_s: float = minf(to_s, cursor_s + V2Contact.MAX_SLAB_S)
		var current_targets: Array = targets.values()
		for target: Dictionary in current_targets:
			if tracking:
				_record_error(target, cursor_s, end_s)
			if target.first_rendered_s == null:
				continue
			var begin_s: float = maxf(cursor_s, float(target.first_rendered_s))
			if begin_s >= end_s:
				continue
			var integration: Dictionary = _target_contact(target, begin_s, end_s)
			if not bool(integration.ok):
				invalidate("unresolved_integration_error")
				return
			if tracking:
				_credit_contact(integration)
			else:
				_damage(target, integration, begin_s, end_s, phase_end_s)
		cursor_s = end_s
		elapsed_s = cursor_s


func _target_contact(target: Dictionary, begin_s: float, end_s: float) -> Dictionary:
	var velocity_bound_deg_s: float = float(target.velocity_bound_deg_s)
	if String(target.size.mode) == "world_radius_constant":
		var radial_bound_m_s: float = absf(float(target.motion.m.distance_amplitude_m) * float(target.motion.m.distance_omega_rad_s))
		var minimum_distance_m: float = float(target.motion.m.distance_center_m) - absf(float(target.motion.m.distance_amplitude_m))
		var radius_m: float = float(target.size.reference_distance_m) * sin(deg_to_rad(float(target.diameter_deg) * 0.5))
		velocity_bound_deg_s += rad_to_deg(radius_m * radial_bound_m_s / (minimum_distance_m * sqrt(minimum_distance_m * minimum_distance_m - radius_m * radius_m)))
	elif String(target.size.mode) == "angular_diameter_linear_over_window":
		velocity_bound_deg_s += absf(float(target.size.diameter_end_deg) - float(target.size.diameter_start_deg)) / (2.0 * float(target.size.progress_duration_s))
	var pose_direction: Array = V2Geometry.direction_deg(yaw_deg, pitch_deg)
	var error_at: Callable = func(at_s: float) -> float:
		var pose: Dictionary = V2Spawner.sample_target(target, at_s)
		return V2Geometry.separation_deg(pose_direction, pose.direction) - float(pose.diameter_deg) * 0.5
	return _contact.integrate(error_at, velocity_bound_deg_s, begin_s, end_s, V2Contact.MAX_WIDTH_FRACTION / maxf(1.0, float(phase.target_count)))


func _credit_contact(integration: Dictionary) -> void:
	metrics.contact_s += float(integration.estimate_s)
	metrics.contact_lower_s += float(integration.lower_s)
	metrics.contact_upper_s += float(integration.upper_s)
	for interval: Array in integration.intervals:
		V2Contact._append_interval(_contact_intervals, interval)
	for interval: Array in integration.get("definite_intervals", []):
		V2Contact._append_interval(_definite_contact_intervals, interval)


func _damage(target: Dictionary, integration: Dictionary, begin_s: float, end_s: float, phase_end_s: float) -> void:
	var damage_per_s: float = float(phase.fire.damage_per_s)
	var useful_contact_s: float = float(integration.estimate_s)
	var remaining_contact_s: float = (float(target.hp_max) - float(target.damage)) / damage_per_s
	if useful_contact_s <= 0.0:
		return
	if not _first_damage_identities.has(target.identity):
		_first_damage_identities[target.identity] = true
	if _last_kill_s != null and target.identity != _last_killed_identity:
		_switch_latencies_ms.append((float(integration.intervals[0][0]) - float(_last_kill_s)) * 1000.0)
		_last_kill_s = null
	if useful_contact_s + 1e-12 < remaining_contact_s:
		var useful_damage: float = useful_contact_s * damage_per_s
		target.damage += useful_damage
		metrics.useful_damage += useful_damage
		_credit_contact(integration)
		return
	var left_s: float = begin_s
	var right_s: float = end_s
	while right_s - left_s > KILL_TIME_TOLERANCE_S:
		var middle_s: float = (left_s + right_s) * 0.5
		var prefix: Dictionary = _target_contact(target, begin_s, middle_s)
		if not bool(prefix.ok):
			invalidate("unresolved_integration_error")
			return
		if float(prefix.estimate_s) >= remaining_contact_s:
			right_s = middle_s
		else:
			left_s = middle_s
	var kill_s: float = right_s
	if absf(useful_contact_s - remaining_contact_s) <= 1e-12:
		kill_s = end_s
	metrics.contact_s += remaining_contact_s
	metrics.contact_lower_s += remaining_contact_s
	metrics.contact_upper_s += remaining_contact_s
	metrics.useful_damage += float(target.hp_max) - float(target.damage)
	target.damage = float(target.hp_max)
	metrics.kills += 1
	metrics.credited_work = float(metrics.kills)
	hit_events.append({"at_s": kill_s, "identity": target.identity, "kind": "kill"})
	_last_kill_s = kill_s
	_last_killed_identity = String(target.identity)
	var pose: Dictionary = V2Spawner.sample_target(target, kill_s)
	_resolve(target, "destroyed", kill_s)
	if kill_s < phase_end_s - 1e-12:
		_replace(target, kill_s, [pose.yaw_deg, pose.pitch_deg])


func _record_error(target: Dictionary, begin_s: float, end_s: float) -> void:
	var pose: Dictionary = V2Spawner.sample_target(target, (begin_s + end_s) * 0.5)
	var angle_deg: float = V2Geometry.separation_deg(V2Geometry.direction_deg(yaw_deg, pitch_deg), pose.direction)
	_angular_error_integral_deg_s += angle_deg * (end_s - begin_s)
	_angular_error_samples.append([angle_deg, end_s - begin_s])


func _replace(old_target: Dictionary, at_s: float, anchor: Array) -> void:
	var replacement: Dictionary = _spawner.make(phase, int(old_target.slot), int(old_target.generation) + 1, at_s, anchor, targets.values())
	if not bool(replacement.get("ok", false)):
		invalidate(String(replacement.get("error", "spawn_constraint_failure")))
		return
	targets[int(old_target.slot)] = replacement
	_record_manifest(replacement)


func _resolve(target: Dictionary, outcome: String, at_s: float) -> void:
	var pose: Dictionary = V2Spawner.sample_target(target, at_s)
	target_outcomes.append({"identity": target.identity, "slot": target.slot, "generation": target.generation, "phase_id": target.phase_id, "onset_s": target.born_s, "deadline_s": target.expiry_s, "outcome": outcome, "resolved_s": at_s, "yaw_pitch_deg": [pose.yaw_deg, pose.pitch_deg], "first_rendered_s": target.first_rendered_s, "first_render_ack_s": target.first_render_ack_s, "damage": target.damage, "hp_max": target.hp_max})
	target_outcomes[-1].first_render_ack_receipt = target.get("first_render_ack_receipt", {})
	target_outcomes[-1].first_rendered_receipt = target.get("first_rendered_receipt", {})
	targets.erase(int(target.slot))


func _record_manifest(target: Dictionary) -> void:
	var state: Dictionary = target.motion
	var initialization: Dictionary = {}
	for key: String in ["phase", "sign", "x0", "y0", "cycle", "arc0", "phases"]:
		if state.has(key):
			initialization[key] = state[key]
	manifest.append({"identity": target.identity, "slot": target.slot, "generation": target.generation, "onset_s": target.born_s, "deadline_s": target.expiry_s, "motion_seed_uint32": target.motion_seed_uint32, "motion_compiler": V2Motion.COMPILER_VERSION, "initialization": initialization, "initial_pose": target.initial_pose, "anchor_yaw_pitch_deg": target.anchor_yaw_pitch_deg, "transition_angle_deg": target.transition_angle_deg, "fallback_used": target.fallback_used, "candidate_index": target.candidate_index, "compiled_motion_hash": V2Canonical.semantic_sha256(V2Canonical.json_ready(state))})


func _close_phase(complete: bool) -> void:
	if phase.is_empty() or phase_index < phases.size():
		return
	if String(phase.mechanic) == "switching":
		var partial_work: float = 0.0
		for target: Dictionary in targets.values():
			partial_work += float(target.damage) / float(target.hp_max)
		metrics.credited_work = float(metrics.kills) + partial_work
	for target: Dictionary in targets.values():
		metrics.censored += 1
		_resolve(target, "censored_phase" if complete else "censored_technical", elapsed_s)
	metrics.accuracy = V2Scores.accuracy(metrics)
	metrics.acquisition_p50_ms = V2Scores.percentile(_latencies_ms, 0.5)
	metrics.acquisition_p90_ms = V2Scores.percentile(_latencies_ms, 0.9)
	metrics.switch_latency_p50_ms = V2Scores.percentile(_switch_latencies_ms, 0.5)
	metrics.switch_latency_p90_ms = V2Scores.percentile(_switch_latencies_ms, 0.9)
	metrics.angular_error_mean_deg = _angular_error_integral_deg_s / (elapsed_s - float(phase.start_s)) if elapsed_s > float(phase.start_s) and not _angular_error_samples.is_empty() else null
	metrics.angular_error_p90_deg = _weighted_percentile(_angular_error_samples, 0.9)
	metrics.integration_g_evaluations = _contact.evaluations
	if String(phase.get("id", "")) == "reactive":
		metrics.merge(_reactive_diagnostics())
	var phase_score: Variant = V2Scores.phase_score(phase, metrics, complete, invalid_reason.is_empty())
	phases.append({"phase_id": phase.id, "title": phase.title, "start_s": phase.start_s, "duration_s": phase.duration_s, "elapsed_s": maxf(0.0, elapsed_s - float(phase.start_s)), "complete": complete, "valid": invalid_reason.is_empty(), "score_id": phase.scoring.id, "score": phase_score, "display_score": V2Scores.displayed_score(phase_score), "metrics": metrics.duplicate(true), "contact_intervals_s": _contact_intervals.duplicate(true), "rank_key": V2Scores.context_key(conditions, program, String(phase.id))})


func _reactive_diagnostics() -> Dictionary:
	var reversals: Array = []
	var phase_start_s: float = float(phase.start_s)
	if _phase_motion_state.has("tape"):
		for piece: Dictionary in _phase_motion_state.tape.pieces:
			if String(piece.shape) != "ramp" or float(piece.v0_deg_s) * float(piece.v1_deg_s) >= 0.0:
				continue
			var left_s: float = 0.0
			var right_s: float = float(piece.duration_s)
			for iteration: int in 48:
				var middle_s: float = (left_s + right_s) * 0.5
				var fraction: float = middle_s / float(piece.duration_s)
				var velocity_deg_s: float = float(piece.v0_deg_s) + (float(piece.v1_deg_s) - float(piece.v0_deg_s)) * fraction * fraction * (3.0 - 2.0 * fraction)
				if velocity_deg_s * float(piece.v0_deg_s) > 0.0:
					left_s = middle_s
				else:
					right_s = middle_s
			var reversal_s: float = float(piece.origin_s) + (left_s + right_s) * 0.5
			if reversal_s < float(piece.from_s) - 1e-9 or reversal_s > float(piece.to_s) + 1e-9 or phase_start_s + reversal_s > elapsed_s:
				continue
			if reversals.is_empty() or absf(float(reversals[-1]) - reversal_s) > 1e-9:
				reversals.append(reversal_s)
	var observations: Array = []
	var latencies_ms: Array = []
	var total_contact_s: float = 0.0
	var total_exposure_s: float = 0.0
	for index: int in reversals.size():
		var begin_s: float = phase_start_s + float(reversals[index])
		var next_reversal_s: float = phase_start_s + float(reversals[index + 1]) if index + 1 < reversals.size() else INF
		var end_s: float = minf(elapsed_s, minf(begin_s + 0.25, next_reversal_s))
		var contact_s: float = 0.0
		for interval: Array in _contact_intervals:
			contact_s += maxf(0.0, minf(float(interval[1]), end_s) - maxf(float(interval[0]), begin_s))
		var latency_ms: Variant = null
		for interval: Array in _definite_contact_intervals:
			var start_s: float = maxf(float(interval[0]), begin_s)
			if minf(float(interval[1]), end_s) - start_s >= 0.05:
				latency_ms = (start_s - begin_s) * 1000.0
				latencies_ms.append(latency_ms)
				break
		var exposure_s: float = maxf(0.0, end_s - begin_s)
		total_contact_s += contact_s
		total_exposure_s += exposure_s
		observations.append({"reversal_s": begin_s, "window_end_s": end_s, "censored_at_next_reversal": next_reversal_s < begin_s + 0.25, "contact_s": contact_s, "exposure_s": exposure_s, "stable_reacquisition_ms": latency_ms})
	var merged_diagnostic: Array = []
	for interval: Array in _contact_intervals:
		if not merged_diagnostic.is_empty() and float(interval[0]) - float(merged_diagnostic[-1][1]) <= 0.02:
			merged_diagnostic[-1][1] = interval[1]
		else:
			merged_diagnostic.append(interval.duplicate())
	var long_losses: int = 0
	for index: int in range(1, merged_diagnostic.size()):
		if float(merged_diagnostic[index][0]) - float(merged_diagnostic[index - 1][1]) > 0.2:
			long_losses += 1
	return {"reversal_observations": observations, "post_reversal_contact_fraction_250_ms": total_contact_s / total_exposure_s if total_exposure_s > 0.0 else null, "stable_reacquisition_p50_ms": V2Scores.percentile(latencies_ms, 0.5), "stable_reacquisition_p90_ms": V2Scores.percentile(latencies_ms, 0.9), "long_losses_over_200_ms": long_losses, "diagnostic_contact_fragments_merged_20_ms": merged_diagnostic.size(), "stable_contact_uses_certified_inside_intervals": true}


static func _weighted_percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty():
		return null
	var ordered: Array = values.duplicate()
	ordered.sort_custom(func(first: Array, second: Array) -> bool: return float(first[0]) < float(second[0]))
	var total_s: float = 0.0
	for value: Array in ordered:
		total_s += float(value[1])
	var accumulated_s: float = 0.0
	for value: Array in ordered:
		accumulated_s += float(value[1])
		if accumulated_s >= total_s * fraction:
			return float(value[0])
	return float(ordered[-1][0])


func snapshot() -> Array:
	var result: Array = []
	for target: Dictionary in targets.values():
		result.append({"identity": target.identity, "slot": target.slot, "generation": target.generation, "born_s": target.born_s, "expiry_s": target.expiry_s, "hp_max": target.hp_max, "damage": target.damage, "first_rendered_s": target.first_rendered_s, "pose": V2Spawner.sample_target(target, elapsed_s)})
	return result


func live_metrics() -> Dictionary:
	var current: Dictionary = metrics.duplicate()
	current.accuracy = V2Scores.accuracy(current)
	if String(phase.get("mechanic", "")) == "switching":
		current.credited_work = float(current.kills)
		for target: Dictionary in targets.values():
			current.credited_work += float(target.damage) / float(target.hp_max)
	current.score = V2Scores.phase_score(phase, current, true, invalid_reason.is_empty()) if not phase.is_empty() else null
	current.display_score = V2Scores.displayed_score(current.score)
	return current


func quality() -> Dictionary:
	if frame_times_ms.is_empty():
		return {"valid": false, "reason": "no_render_frametimes", "mean_fps": null, "median_fps": null, "p99_ms": null, "max_ms": null}
	var total_ms: float = 0.0
	var maximum_ms: float = 0.0
	for frame_ms: float in frame_times_ms:
		total_ms += frame_ms
		maximum_ms = maxf(maximum_ms, frame_ms)
	var mean_fps: float = float(frame_times_ms.size()) * 1000.0 / total_ms
	var p99_ms: float = float(V2Scores.percentile(frame_times_ms, 0.99))
	return {"valid": mean_fps >= 55.0 and p99_ms <= 25.0 and maximum_ms <= 100.0, "reason": "" if mean_fps >= 55.0 and p99_ms <= 25.0 and maximum_ms <= 100.0 else "render_frametime_limits", "mean_fps": mean_fps, "median_fps": 1000.0 / float(V2Scores.percentile(frame_times_ms, 0.5)), "p99_ms": p99_ms, "max_ms": maximum_ms, "frame_count": frame_times_ms.size()}


func report() -> Dictionary:
	if not _report_cache.is_empty():
		return _report_cache.duplicate(true)
	if program.is_empty():
		return {"schema_version": "aimlocal.report.v2.0", "runtime_version": RUNTIME_VERSION, "catalogue_revision": CATALOGUE_REVISION, "complete": false, "valid": false, "rank_eligible": false, "invalid_reason": invalid_reason, "phases": [], "program_score": null}
	var complete: bool = completed and invalid_reason.is_empty() and elapsed_s >= duration_s
	var score: Variant = V2Scores.program_score(program, phases, complete, invalid_reason.is_empty())
	var result: Dictionary = {"schema_version": "aimlocal.report.v2.0", "runtime_version": RUNTIME_VERSION, "catalogue_revision": CATALOGUE_REVISION, "input_convention": INPUT_CONVENTION, "session_seed_hex": session_seed_hex, "program_id": program.program_id, "difficulty": program.difficulty, "title": program.title, "duration_s": duration_s, "elapsed_s": elapsed_s, "complete": complete, "valid": invalid_reason.is_empty(), "invalid_reason": invalid_reason, "conditions": conditions.duplicate(true), "definition_hash": V2Canonical.semantic_sha256(program), "phases": phases.duplicate(true), "program_score": score, "display_score": V2Scores.displayed_score(score), "rank_key": V2Scores.context_key(conditions, program), "manifest": manifest.duplicate(true), "target_outcomes": target_outcomes.duplicate(true), "received_pose_trace": received_pose_trace.duplicate(true), "render_quality": quality()}
	result.manifest_hash = V2Canonical.semantic_sha256(result.manifest)
	result.pauses = pauses.duplicate(true)
	result.rank_eligible = complete and invalid_reason.is_empty() and pauses.is_empty() and bool(result.render_quality.valid)
	result.pose_event_count = pose_event_count
	result.initial_pose_yaw_pitch_deg = initial_pose_yaw_pitch_deg.duplicate()
	result.trace_retention = "full_received_pose_trace" if bool(conditions.get("retain_input_trace", false)) else "light_no_exact_input_replay"
	result = V2Canonical.json_ready(result)
	if completed:
		_report_cache = result.duplicate(true)
	return result
