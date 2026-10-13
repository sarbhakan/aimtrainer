class_name V2CalibrationTask
extends RefCounted

const Motion: GDScript = preload("res://scripts/v2/v2_motion.gd")
const Geometry: GDScript = preload("res://scripts/v2/v2_geometry.gd")
const Spawner: GDScript = preload("res://scripts/v2/v2_spawner.gd")
const Contact: GDScript = preload("res://scripts/v2/v2_contact.gd")
const Canonical: GDScript = preload("res://scripts/v2/v2_canonical.gd")
const Service: GDScript = preload("res://scripts/v2/v2_calibration_service.gd")
const MAX_PENDING_EVENTS: int = 65536
const MAX_POSE_EVENTS: int = 1000000
const INTERSECTION_TIE_M: float = 1e-9
const RUNTIME_VERSION: String = "aimlocal.calibration_task.v2.0"
const MAX_REPORT_BYTES: int = 8 * 1024 * 1024
const MAX_AUDIT_BYTES: int = MAX_REPORT_BYTES
const POSE_RECORD_BYTES: int = 32
const FIRE_RECORD_BYTES: int = 17
const STABLE_CONTACT_S: float = 0.05

var deck: Dictionary = {}
var conditions: Dictionary = {}
var task: String = ""
var duration_s: float = 24.0
var elapsed_s: float = 0.0
var completed: bool = false
var invalid_reason: String = ""
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var fire_held: bool = false
var metrics: Dictionary = {}
var hit_events: Array = []
var diagnostic_events: Array = []
var received_pose_trace: PackedByteArray = PackedByteArray()
var frame_intervals_s: Array = []
var targets: Dictionary = {}
var opportunities: Array = []
var _pending_events: Array = []
var _sequence: int = 0
var _last_receipt_s: float = 0.0
var _processed_sequence: int = 0
var _pose_trace_count: int = 0
var _fire_trace: PackedByteArray = PackedByteArray()
var _fire_trace_count: int = 0
var _render_trace: PackedByteArray = PackedByteArray()
var _render_trace_count: int = 0
var _render_receipts: Array = []
var _frame_trace: PackedByteArray = PackedByteArray()
var _initial_pose_deg: Array[float] = [0.0, 0.0]
var _trajectory_target: Dictionary = {}
var _opportunity_index: int = -1
var _contact: RefCounted = Contact.new()
var _contact_intervals: Array = []
var _definite_contact_intervals: Array = []
var _reversals: Array = []
var _angular_error_integral_deg_s: float = 0.0
var _angular_error_weight_s: float = 0.0
var _protocol_task: Dictionary = {}
var _comparison_enabled: bool = false
var _report_cache: Dictionary = {}


func start(requested_deck: Dictionary, requested_duration_s: float = 24.0, frozen_conditions: Dictionary = {}) -> bool:
	deck = requested_deck.duplicate(true)
	conditions = frozen_conditions.duplicate(true)
	task = String(deck.get("task_id", "")).trim_prefix("CAL_").trim_suffix("_R2")
	duration_s = requested_duration_s
	elapsed_s = 0.0
	completed = false
	invalid_reason = ""
	yaw_deg = float(conditions.get("initial_yaw_deg", 0.0))
	pitch_deg = clampf(float(conditions.get("initial_pitch_deg", 0.0)), -89.0, 89.0)
	_initial_pose_deg = [yaw_deg, pitch_deg]
	fire_held = false
	metrics = {"hits": 0, "shots": 0, "misses": 0, "first_presses": 0, "premature": 0, "extra_shots": 0, "late_shots": 0, "timeouts": 0, "censored": 0, "technical_censored": 0, "opportunities": 0, "raw_succeeded": 0, "kills": 0, "useful_damage": 0.0, "contact_s": 0.0, "contact_lower_s": 0.0, "contact_upper_s": 0.0, "exposure_s": duration_s}
	hit_events.clear()
	diagnostic_events.clear()
	received_pose_trace.clear()
	frame_intervals_s.clear()
	targets.clear()
	opportunities.clear()
	_pending_events.clear()
	_sequence = 0
	_last_receipt_s = 0.0
	_processed_sequence = 0
	_pose_trace_count = 0
	_fire_trace.clear()
	_fire_trace_count = 0
	_render_trace.clear()
	_render_trace_count = 0
	_render_receipts.clear()
	_frame_trace.clear()
	_trajectory_target.clear()
	_opportunity_index = -1
	_contact = Contact.new()
	_contact_intervals.clear()
	_definite_contact_intervals.clear()
	_reversals.clear()
	_angular_error_integral_deg_s = 0.0
	_angular_error_weight_s = 0.0
	_report_cache.clear()
	_protocol_task = {}
	_comparison_enabled = false
	var error: String = _validate_deck()
	if not error.is_empty():
		invalidate(error)
		return false
	_comparison_enabled = duration_s == 24.0 and bool(conditions.get("comparative_utility_included", true)) and not String(deck.deck_id).contains("_preflight") and not String(deck.deck_id).contains("_warmup")
	if task in ["CLICK", "SWITCH"]:
		for definition: Dictionary in deck.opportunities:
			if float(definition.slot_start_s) >= duration_s:
				continue
			var row: Dictionary = definition.duplicate(true)
			row.onset_s = float(int(definition.onset_us)) / 1000000.0
			row.deadline_s = float(int(definition.deadline_us)) / 1000000.0
			row.included_in_utility = float(row.deadline_s) <= duration_s
			row.disposition = "pending"
			row.first_press_s = null
			row.first_press_sequence = null
			row.first_rendered_s = null
			row.first_render_ack_s = null
			row.first_render_ack_receipt = {}
			row.first_rendered_receipt = {}
			row.resolved_s = null
			row.latency_s = null
			row.render_latency_s = null
			row.utility = 0.0
			row.damage = 0.0
			row.extra_shots = 0
			row.late_shots = 0
			row.actual_acquisition_amplitude_deg = null
			opportunities.append(row)
			if bool(row.included_in_utility):
				metrics.opportunities += 1
		_open_slot(0)
	else:
		var motion: Dictionary = _tracking_motion()
		var diameter_deg: float = float(deck.trajectory.diameter_deg) if task == "SMOOTH" else float(_protocol_task.diameter_deg[deck.difficulty])
		var target: Dictionary = _target("trajectory/0", 0, 0, 0.0, motion, diameter_deg, 0.0)
		target.priority = false
		target.neutral = false
		targets[0] = target
		_trajectory_target = target
		if task == "REACTIVE":
			_record_reversals()
	return invalid_reason.is_empty()


func _validate_deck() -> String:
	if task not in ["CLICK", "SMOOTH", "REACTIVE", "SWITCH"] or deck.get("task_id") != "CAL_" + task + "_R2":
		return "invalid_calibration_task"
	if not is_finite(duration_s) or duration_s <= 0.0 or duration_s > 24.0 or float(deck.get("duration_s", 0.0)) != 24.0:
		return "invalid_calibration_duration"
	if not is_finite(yaw_deg) or not is_finite(pitch_deg) or not deck.get("deck_id") is String or not deck.get("difficulty") in ["novice", "standard", "advanced"]:
		return "invalid_calibration_manifest"
	if conditions.has("applied_gain"):
		if not conditions.applied_gain is Dictionary or not conditions.applied_gain.get("ieee754_binary64_big_endian_hex") is String:
			return "invalid_actual_calibration_gain"
		var actual_gain: float = Canonical.float64_from_hex(conditions.applied_gain.ieee754_binary64_big_endian_hex)
		if not is_finite(actual_gain) or actual_gain <= 0.0:
			return "invalid_actual_calibration_gain"
	var payload: Dictionary = deck.duplicate(true)
	var manifest_hash: Variant = payload.get("manifest_sha256")
	payload.erase("manifest_sha256")
	if not manifest_hash is String or Canonical.semantic_sha256(payload) != manifest_hash:
		return "calibration_manifest_hash_mismatch"
	var protocol: Dictionary = Service.protocol()
	if not protocol.get("tasks") is Dictionary or not protocol.tasks.get(task) is Dictionary:
		return "missing_calibration_protocol"
	_protocol_task = protocol.tasks[task].duplicate(true)
	if task in ["CLICK", "SWITCH"]:
		if not deck.get("opportunities") is Array or deck.opportunities.size() != int(_protocol_task.slots):
			return "invalid_calibration_opportunities"
		for slot_index: int in deck.opportunities.size():
			var row: Variant = deck.opportunities[slot_index]
			if not row is Dictionary or int(row.get("slot_index", -1)) != slot_index:
				return "invalid_calibration_opportunities"
			var slot_s: float = float(_protocol_task.slot_s)
			var onset_us: int = int(row.get("onset_us", -1))
			var deadline_us: int = int(row.get("deadline_us", -1))
			if float(row.get("slot_start_s", -1.0)) != float(slot_index) * slot_s or float(row.get("slot_end_s", -1.0)) != float(slot_index + 1) * slot_s:
				return "invalid_calibration_opportunities"
			var jitter_us: int = onset_us - int(round(float(slot_index) * slot_s * 1000000.0))
			if jitter_us < 100000 or jitter_us > 250000 or deadline_us - onset_us != int(round(float(_protocol_task.active_window_s) * 1000000.0)):
				return "invalid_calibration_opportunity_timing"
			if task == "CLICK":
				if not _valid_position(row) or float(row.diameter_deg) <= 0.0:
					return "invalid_calibration_geometry"
			elif int(row.get("priority_target_id", -1)) not in [0, 1, 2] or float(row.get("hp", 0.0)) <= 0.0 or float(row.get("damage_hp_s", 0.0)) != 100.0 or float(row.hp) / 100.0 >= float(_protocol_task.active_window_s):
				return "invalid_calibration_switch_priority"
		if task == "SWITCH":
			if not deck.get("positions") is Array or deck.positions.size() != 3:
				return "invalid_calibration_geometry"
			for target_index: int in 3:
				var position: Variant = deck.positions[target_index]
				if not position is Dictionary or int(position.get("target_id", -1)) != target_index or not _valid_position(position):
					return "invalid_calibration_geometry"
	elif task == "SMOOTH":
		if not deck.get("trajectory") is Dictionary:
			return "invalid_calibration_trajectory"
		var trajectory: Dictionary = deck.trajectory
		if trajectory.get("kind") != "great_circle_horizontal_sine" or not _finite_number(trajectory.get("phase_rad")) or float(trajectory.get("amplitude_deg", 0.0)) != 14.0 or float(trajectory.get("max_speed_deg_s", 0.0)) <= 0.0 or float(trajectory.get("diameter_deg", 0.0)) <= 0.0 or float(trajectory.get("distance_m", 0.0)) != 4.0:
			return "invalid_calibration_trajectory"
	else:
		if not deck.get("trajectory_tape") is Dictionary or not deck.get("shared_motion_source") is Dictionary:
			return "invalid_calibration_trajectory"
		var tape: Dictionary = deck.trajectory_tape
		if Canonical.semantic_sha256(tape) != deck.get("trajectory_tape_sha256") or tape.get("compiler_version") != Motion.COMPILER_VERSION or float(tape.get("horizon_s", 0.0)) != 24.0 or not tape.get("pieces") is Array or tape.pieces.is_empty():
			return "calibration_trajectory_hash_mismatch"
		var source: Dictionary = deck.shared_motion_source
		if not source.get("motion_resource") is Dictionary or Canonical.semantic_sha256(source.motion_resource) != source.get("motion_resource_sha256") or source.motion_resource_sha256 != _protocol_task.shared_motion_sha256_by_difficulty[deck.difficulty]:
			return "calibration_motion_resource_hash_mismatch"
	return ""


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _valid_position(position: Dictionary) -> bool:
	return _finite_number(position.get("yaw_deg")) and _finite_number(position.get("pitch_deg")) and _finite_number(position.get("diameter_deg")) and float(position.get("distance_m", 0.0)) == 4.0 and float(position.diameter_deg) > 0.0 and float(position.diameter_deg) < 180.0


func _tracking_motion() -> Dictionary:
	if task == "REACTIVE":
		return {"kind": "reactive_axis", "m": deck.shared_motion_source.motion_resource.duplicate(true), "seed": int(deck.shared_motion_source.initial_rng_uint32), "slot": 0, "phase": float(deck.trajectory_tape.initial_state.vertical_phase_rad), "sign": 1, "horizon_s": 24.0, "distance_m": 4.0, "tape": deck.trajectory_tape.duplicate(true)}
	var trajectory: Dictionary = deck.trajectory
	return {"kind": "sinusoid_axis", "m": {"kind": "sinusoid_axis", "axis": "yaw", "amplitude_deg": float(trajectory.amplitude_deg), "omega_rad_s": float(trajectory.max_speed_deg_s) / float(trajectory.amplitude_deg), "orthogonal_coordinate_deg": 0.0}, "seed": int(deck.rng_seeds.motion.uint32), "slot": 0, "phase": float(trajectory.phase_rad), "sign": 1, "horizon_s": 24.0, "distance_m": float(trajectory.distance_m)}


func _target(identity_suffix: String, slot: int, generation: int, born_s: float, motion: Dictionary, diameter_deg: float, hp: float) -> Dictionary:
	return {"identity": String(deck.deck_id) + "/" + identity_suffix, "slot": slot, "generation": generation, "born_s": born_s, "hp_max": hp, "damage": 0.0, "first_rendered_s": null, "first_render_ack_s": null, "motion": motion, "diameter_deg": diameter_deg, "size": {"mode": "angular_diameter_constant"}, "priority": false, "neutral": false}


static func _static_motion(position: Dictionary) -> Dictionary:
	return {"kind": "static", "m": {"kind": "static"}, "x0": float(position.yaw_deg), "y0": float(position.pitch_deg), "distance_m": float(position.distance_m)}


func _open_slot(slot_index: int) -> void:
	_opportunity_index = slot_index
	if slot_index >= opportunities.size():
		return
	var row: Dictionary = opportunities[slot_index]
	row.disposition = "pre_onset"
	row.actual_acquisition_amplitude_deg = Geometry.separation_deg(Geometry.direction_deg(yaw_deg, pitch_deg), Geometry.direction_deg(float(row.yaw_deg), float(row.pitch_deg))) if task == "CLICK" else null
	targets.clear()
	if task == "SWITCH":
		for position: Dictionary in deck.positions:
			var target_id: int = int(position.target_id)
			var target: Dictionary = _target("neutral/%d" % target_id, target_id, slot_index, float(row.slot_start_s), _static_motion(position), float(position.diameter_deg), 0.0)
			target.neutral = true
			target.target_id = target_id
			targets[target_id] = target


func _activate() -> void:
	var row: Dictionary = opportunities[_opportunity_index]
	if row.disposition != "pre_onset":
		return
	row.disposition = "active_unrendered"
	var target: Dictionary
	if task == "CLICK":
		target = _target("opportunity/%d" % int(row.slot_index), 0, int(row.slot_index), float(row.onset_s), _static_motion(row), float(row.diameter_deg), 0.0)
	else:
		var target_id: int = int(row.priority_target_id)
		var position: Dictionary = deck.positions[target_id]
		target = _target("priority/%d/%d" % [int(row.slot_index), target_id], target_id, int(row.slot_index), float(row.onset_s), _static_motion(position), float(position.diameter_deg), float(row.hp))
		target.priority = true
		target.target_id = target_id
	row.identity = target.identity
	targets[int(target.slot)] = target


func queue_pose(receipt_s: float, received_yaw_deg: float, received_pitch_deg: float) -> void:
	if not is_finite(received_yaw_deg) or not is_finite(received_pitch_deg):
		if not completed:
			invalidate("nonfinite_input_pose")
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
	if _sequence > 0xffffffff:
		invalidate("calibration_audit_sequence_overflow")
		return
	_last_receipt_s = receipt_s
	_pending_events.append([receipt_s, _sequence, kind, value])


func advance(to_s: float) -> void:
	if completed:
		return
	if not is_finite(to_s):
		invalidate("nonfinite_active_time")
		return
	var requested_s: float = clampf(to_s, elapsed_s, duration_s)
	var pending: Array = _pending_events
	_pending_events = []
	for event: Array in pending:
		if float(event[0]) > requested_s:
			_pending_events.append(event)
			continue
		_advance_internal(float(event[0]))
		if completed:
			break
		if event[2] == "pose":
			if _pose_trace_count >= MAX_POSE_EVENTS:
				invalidate("pose_trace_overflow")
				break
			if not _append_pose_trace(event):
				break
			yaw_deg = float(event[3][0])
			pitch_deg = float(event[3][1])
		else:
			if not _append_fire_trace(event):
				break
			var pressed: bool = bool(event[3])
			if pressed and not fire_held:
				_press(float(event[0]), int(event[1]))
			fire_held = pressed
		_processed_sequence = int(event[1])
	if not completed:
		_advance_internal(requested_s)


func _reserve_audit(additional_bytes: int) -> bool:
	if received_pose_trace.size() + _fire_trace.size() + _render_trace.size() + _frame_trace.size() + additional_bytes > MAX_AUDIT_BYTES:
		invalidate("calibration_audit_overflow")
		return false
	return true


func _append_pose_trace(event: Array) -> bool:
	if not _reserve_audit(POSE_RECORD_BYTES):
		return false
	var offset: int = received_pose_trace.size()
	received_pose_trace.resize(offset + POSE_RECORD_BYTES)
	received_pose_trace.encode_u32(offset, int(round(float(event[0]) * 1000000.0)))
	received_pose_trace.encode_u32(offset + 4, int(event[1]))
	received_pose_trace.encode_double(offset + 8, float(event[0]))
	received_pose_trace.encode_double(offset + 16, float(event[3][0]))
	received_pose_trace.encode_double(offset + 24, float(event[3][1]))
	_pose_trace_count += 1
	return true


func _append_fire_trace(event: Array) -> bool:
	if not _reserve_audit(FIRE_RECORD_BYTES):
		return false
	var offset: int = _fire_trace.size()
	_fire_trace.resize(offset + FIRE_RECORD_BYTES)
	_fire_trace.encode_u32(offset, int(round(float(event[0]) * 1000000.0)))
	_fire_trace.encode_u32(offset + 4, int(event[1]))
	_fire_trace.encode_double(offset + 8, float(event[0]))
	_fire_trace.encode_u8(offset + 16, 1 if bool(event[3]) else 0)
	_fire_trace_count += 1
	return true


func _advance_internal(to_s: float) -> void:
	var end_s: float = minf(to_s, duration_s)
	while not completed:
		var next_s: float = end_s
		if task in ["CLICK", "SWITCH"] and _opportunity_index < opportunities.size():
			var row: Dictionary = opportunities[_opportunity_index]
			for boundary_s: float in [float(row.onset_s), float(row.deadline_s), float(row.slot_end_s)]:
				if boundary_s > elapsed_s:
					next_s = minf(next_s, boundary_s)
		if next_s > elapsed_s:
			_integrate_to(next_s)
			if completed:
				return
			elapsed_s = next_s
		if task in ["CLICK", "SWITCH"] and _opportunity_index < opportunities.size():
			var current: Dictionary = opportunities[_opportunity_index]
			if elapsed_s >= float(current.deadline_s) and not _resolved(current):
				_deadline()
				if completed:
					return
		if elapsed_s >= duration_s:
			_finish()
			return
		if task in ["CLICK", "SWITCH"] and _opportunity_index < opportunities.size():
			var row: Dictionary = opportunities[_opportunity_index]
			if elapsed_s >= float(row.slot_end_s):
				_open_slot(_opportunity_index + 1)
			elif elapsed_s >= float(row.onset_s) and row.disposition == "pre_onset":
				_activate()
		if elapsed_s >= end_s:
			return


static func _resolved(row: Dictionary) -> bool:
	return String(row.disposition) in ["resolved_hit", "resolved_miss", "resolved_premature", "resolved_killed", "timeout", "censored_segment", "censored_technical"]


func _press(at_s: float, sequence: int) -> void:
	if task != "CLICK" or _opportunity_index >= opportunities.size():
		return
	metrics.shots += 1
	var row: Dictionary = opportunities[_opportunity_index]
	if at_s >= float(row.deadline_s):
		metrics.late_shots += 1
		row.late_shots += 1
		diagnostic_events.append({"kind": "late_shot", "at_s": at_s, "sequence": sequence, "slot_index": row.slot_index})
		return
	if _resolved(row):
		metrics.extra_shots += 1
		row.extra_shots += 1
		diagnostic_events.append({"kind": "extra_shot", "at_s": at_s, "sequence": sequence, "slot_index": row.slot_index})
		return
	metrics.first_presses += 1
	row.first_press_s = at_s
	row.first_press_sequence = sequence
	row.latency_s = at_s - float(row.onset_s)
	var target: Dictionary = targets.get(0, {})
	if at_s < float(row.onset_s) or target.is_empty() or target.first_rendered_s == null or at_s < float(target.first_rendered_s):
		metrics.premature += 1
		metrics.misses += 1
		diagnostic_events.append({"kind": "premature", "at_s": at_s, "sequence": sequence, "slot_index": row.slot_index})
		_resolve("resolved_premature", at_s)
		return
	row.render_latency_s = at_s - float(target.first_rendered_s)
	var selected: Dictionary = _ray_target(at_s)
	if selected.is_empty():
		metrics.misses += 1
		_resolve("resolved_miss", at_s)
	else:
		metrics.hits += 1
		if bool(row.included_in_utility):
			metrics.raw_succeeded += 1
		row.utility = 1.0 - float(row.latency_s) / float(_protocol_task.active_window_s)
		hit_events.append({"kind": "hit", "at_s": at_s, "sequence": sequence, "identity": selected.identity, "slot_index": row.slot_index})
		_resolve("resolved_hit", at_s)


func _ray_target(at_s: float) -> Dictionary:
	var direction: Array = Geometry.direction_deg(yaw_deg, pitch_deg)
	var selected: Dictionary = {}
	var nearest_m: float = INF
	for target: Dictionary in targets.values():
		if bool(target.neutral) or target.first_rendered_s == null or at_s < float(target.first_rendered_s):
			continue
		var pose: Dictionary = _sample_target(target, at_s)
		var intersection_m: float = Geometry.ray_sphere_distance(direction, pose.center_offset_m, float(pose.radius_m))
		if intersection_m < 0.0:
			continue
		if intersection_m < nearest_m - INTERSECTION_TIE_M or (absf(intersection_m - nearest_m) <= INTERSECTION_TIE_M and (selected.is_empty() or String(target.identity) < String(selected.identity))):
			selected = target
			nearest_m = intersection_m
	return selected


func mark_rendered(prepared_ids: Array, visible_ids: Array, at_s: float, useful_viewport: bool = true, prepared_receipt: Dictionary = {}) -> void:
	advance(at_s)
	if completed:
		return
	if not useful_viewport:
		invalidate("render_viewport_failure")
		return
	for target: Dictionary in targets.values():
		if target.identity not in prepared_ids:
			continue
		var flags: int = 0
		if target.first_render_ack_s == null:
			target.first_render_ack_s = elapsed_s
			target.first_render_ack_receipt = prepared_receipt.duplicate(true)
			flags |= 1
		if target.identity in visible_ids and target.first_rendered_s == null:
			target.first_rendered_s = elapsed_s
			target.first_rendered_receipt = prepared_receipt.duplicate(true)
			flags |= 2
		if flags != 0:
			if not _reserve_audit(24):
				return
			var offset: int = _render_trace.size()
			_render_trace.resize(offset + 24)
			_render_trace.encode_u32(offset, int(round(elapsed_s * 1000000.0)))
			_render_trace.encode_u32(offset + 4, _processed_sequence)
			_render_trace.encode_u32(offset + 8, _render_receipts.size())
			_render_trace.encode_u32(offset + 12, flags)
			_render_trace.encode_double(offset + 16, elapsed_s)
			_render_trace_count += 1
			_render_receipts.append({"identity": target.identity, "generation": target.generation, "prepared_receipt": prepared_receipt.duplicate(true)})
		if task in ["CLICK", "SWITCH"] and opportunities[_opportunity_index].get("identity") == target.identity:
			var row: Dictionary = opportunities[_opportunity_index]
			row.first_render_ack_s = target.first_render_ack_s
			row.first_rendered_s = target.first_rendered_s
			row.first_render_ack_receipt = target.get("first_render_ack_receipt", {}).duplicate(true)
			row.first_rendered_receipt = target.get("first_rendered_receipt", {}).duplicate(true)
			if target.first_rendered_s != null and not _resolved(row):
				row.disposition = "active_visible"


func _deadline() -> void:
	var row: Dictionary = opportunities[_opportunity_index]
	if row.first_render_ack_s == null:
		metrics.technical_censored += 1
		_resolve("censored_technical", float(row.deadline_s))
		invalidate("nonrendered_opportunity")
		return
	metrics.timeouts += 1
	_resolve("timeout", float(row.deadline_s))


func _resolve(disposition: String, at_s: float) -> void:
	var row: Dictionary = opportunities[_opportunity_index]
	row.disposition = disposition
	row.resolved_s = at_s
	if task == "CLICK":
		targets.clear()
	else:
		var target_id: int = int(row.priority_target_id)
		if disposition == "resolved_killed":
			targets.erase(target_id)
		else:
			var position: Dictionary = deck.positions[target_id]
			var neutral: Dictionary = _target("neutral/%d" % target_id, target_id, int(row.slot_index), at_s, _static_motion(position), float(position.diameter_deg), 0.0)
			neutral.neutral = true
			neutral.target_id = target_id
			targets[target_id] = neutral


func _integrate_to(to_s: float) -> void:
	if task == "CLICK" or (task == "SWITCH" and not fire_held):
		return
	var selected: Dictionary = {}
	if task in ["SMOOTH", "REACTIVE"]:
		selected = targets.get(0, {})
	elif _opportunity_index < opportunities.size():
		var row: Dictionary = opportunities[_opportunity_index]
		if _resolved(row) or elapsed_s < float(row.onset_s) or elapsed_s >= float(row.deadline_s):
			return
		selected = targets.get(int(row.priority_target_id), {})
	if selected.is_empty() or selected.first_rendered_s == null:
		return
	var begin_s: float = maxf(elapsed_s, float(selected.first_rendered_s))
	if begin_s >= to_s:
		return
	var direction: Array = Geometry.direction_deg(yaw_deg, pitch_deg)
	var velocity_bound_deg_s: float = Motion.velocity_bound_deg_s(selected.motion, begin_s - float(selected.born_s), to_s - float(selected.born_s))
	var error_at: Callable = func(at_s: float) -> float:
		var pose: Dictionary = _sample_target(selected, at_s)
		return Geometry.separation_deg(direction, pose.direction) - float(pose.diameter_deg) * 0.5
	var integration: Dictionary = _contact.integrate(error_at, velocity_bound_deg_s, begin_s, to_s)
	if not bool(integration.ok):
		invalidate("unresolved_integration_error")
		return
	if task == "SWITCH":
		_damage(selected, integration, to_s)
	else:
		_credit_contact(integration)
		var cursor_s: float = begin_s
		while cursor_s < to_s:
			var end_s: float = minf(to_s, cursor_s + Contact.MAX_SLAB_S)
			var middle: Dictionary = _sample_target(selected, (cursor_s + end_s) * 0.5)
			_angular_error_integral_deg_s += Geometry.separation_deg(direction, middle.direction) * (end_s - cursor_s)
			_angular_error_weight_s += end_s - cursor_s
			cursor_s = end_s


func _credit_contact(integration: Dictionary) -> void:
	metrics.contact_s += float(integration.estimate_s)
	metrics.contact_lower_s += float(integration.lower_s)
	metrics.contact_upper_s += float(integration.upper_s)
	for interval: Array in integration.intervals:
		Contact._append_interval(_contact_intervals, interval)
	for interval: Array in integration.get("definite_intervals", []):
		Contact._append_interval(_definite_contact_intervals, interval)


func _damage(target: Dictionary, integration: Dictionary, end_s: float) -> void:
	var row: Dictionary = opportunities[_opportunity_index]
	var damage_hp_s: float = float(row.damage_hp_s)
	var remaining_contact_s: float = (float(target.hp_max) - float(target.damage)) / damage_hp_s
	if float(integration.estimate_s) <= 0.0:
		return
	if float(integration.estimate_s) + 1e-12 < remaining_contact_s:
		var damage_hp: float = float(integration.estimate_s) * damage_hp_s
		target.damage += damage_hp
		row.damage = target.damage
		metrics.useful_damage += damage_hp
		_credit_contact(integration)
		return
	var needed_s: float = remaining_contact_s
	var kill_s: float = end_s
	for interval: Array in integration.intervals:
		var contact_s: float = float(interval[1]) - float(interval[0])
		if needed_s <= contact_s + 1e-12:
			kill_s = minf(end_s, float(interval[0]) + needed_s)
			break
		needed_s -= contact_s
	if absf(float(integration.estimate_s) - remaining_contact_s) <= 1e-12:
		kill_s = end_s
	metrics.contact_s += remaining_contact_s
	metrics.contact_lower_s += remaining_contact_s
	metrics.contact_upper_s += remaining_contact_s
	for interval: Array in integration.intervals:
		if float(interval[0]) >= kill_s:
			break
		Contact._append_interval(_contact_intervals, [float(interval[0]), minf(float(interval[1]), kill_s)])
	for interval: Array in integration.get("definite_intervals", []):
		if float(interval[0]) >= kill_s:
			break
		Contact._append_interval(_definite_contact_intervals, [float(interval[0]), minf(float(interval[1]), kill_s)])
	metrics.useful_damage += float(target.hp_max) - float(target.damage)
	target.damage = float(target.hp_max)
	row.damage = target.damage
	metrics.kills += 1
	if bool(row.included_in_utility):
		metrics.raw_succeeded += 1
	row.latency_s = kill_s - float(row.onset_s)
	row.render_latency_s = kill_s - float(target.first_rendered_s)
	var window_s: float = float(_protocol_task.active_window_s)
	row.utility = clampf((window_s - float(row.latency_s)) / (window_s - float(row.hp) / damage_hp_s), 0.0, 1.0)
	hit_events.append({"kind": "kill", "at_s": kill_s, "identity": target.identity, "slot_index": row.slot_index})
	_resolve("resolved_killed", kill_s)


func _finish() -> void:
	if task in ["CLICK", "SWITCH"]:
		for row: Dictionary in opportunities:
			if _resolved(row):
				continue
			row.disposition = "censored_segment"
			row.resolved_s = elapsed_s
			metrics.censored += 1
	else:
		if targets[0].first_render_ack_s == null:
			invalidate("nonrendered_trajectory")
			return
	completed = true
	fire_held = false
	_pending_events.clear()
	targets.clear()


func invalidate(reason: String) -> void:
	if invalid_reason.is_empty():
		invalid_reason = reason
	if not completed:
		for row: Dictionary in opportunities:
			if _resolved(row):
				continue
			row.disposition = "censored_technical"
			row.resolved_s = elapsed_s
			metrics.technical_censored += 1
	completed = true
	fire_held = false
	_pending_events.clear()
	targets.clear()
	_report_cache.clear()


func record_frame(delta_s: float) -> void:
	if not completed and is_finite(delta_s) and delta_s > 0.0:
		if not _reserve_audit(8):
			return
		var offset: int = _frame_trace.size()
		_frame_trace.resize(offset + 8)
		_frame_trace.encode_double(offset, delta_s)
		frame_intervals_s.append(delta_s)


func _sample_target(target: Dictionary, at_s: float) -> Dictionary:
	return Spawner.sample_target(target, at_s)


func snapshot() -> Array:
	var result: Array = []
	for target: Dictionary in targets.values():
		var entry: Dictionary = {"identity": target.identity, "slot": target.slot, "generation": target.generation, "born_s": target.born_s, "hp_max": target.hp_max, "damage": target.damage, "first_rendered_s": target.first_rendered_s, "pose": _sample_target(target, elapsed_s), "priority": target.priority, "neutral": target.neutral}
		if target.has("target_id"):
			entry.target_id = target.target_id
		result.append(entry)
	return result


func quality() -> Dictionary:
	return Service.frame_quality(frame_intervals_s)


func _record_reversals() -> void:
	var origins: Dictionary = {}
	for piece: Dictionary in deck.trajectory_tape.pieces:
		if piece.shape != "ramp" or float(piece.v0_deg_s) * float(piece.v1_deg_s) >= 0.0 or origins.has(piece.origin_s):
			continue
		var zero_s: Variant = Motion._velocity_zero(piece, float(piece.from_s), float(piece.to_s))
		if zero_s != null and float(zero_s) < duration_s:
			origins[piece.origin_s] = true
			_reversals.append({"ramp_start_s": piece.origin_s, "effective_sign_change_s": float(zero_s)})


func _pose_at(time_s: float) -> Array[float]:
	var lower: int = 0
	var upper: int = _pose_trace_count
	while lower < upper:
		var middle: int = (lower + upper) >> 1
		if received_pose_trace.decode_double(middle * POSE_RECORD_BYTES + 8) > time_s:
			upper = middle
		else:
			lower = middle + 1
	if lower == 0:
		return _initial_pose_deg.duplicate()
	var offset: int = (lower - 1) * POSE_RECORD_BYTES
	return [received_pose_trace.decode_double(offset + 16), received_pose_trace.decode_double(offset + 24)]


func _reacquisition_diagnostics() -> Array:
	var result: Array = []
	for reversal_index: int in _reversals.size():
		var reversal: Dictionary = _reversals[reversal_index]
		var change_s: float = float(reversal.effective_sign_change_s)
		if change_s > elapsed_s:
			continue
		var censor_s: float = minf(elapsed_s, float(_reversals[reversal_index + 1].effective_sign_change_s)) if reversal_index + 1 < _reversals.size() else elapsed_s
		var stable_start_s: Variant = null
		var window_end_s: float = minf(censor_s, change_s + 0.25)
		var contact_lower_s: float = 0.0
		for interval: Array in _definite_contact_intervals:
			contact_lower_s += maxf(0.0, minf(window_end_s, float(interval[1])) - maxf(change_s, float(interval[0])))
			var begin_s: float = maxf(change_s, float(interval[0]))
			var end_s: float = minf(censor_s, float(interval[1]))
			if stable_start_s == null and end_s - begin_s >= STABLE_CONTACT_S - 1e-12:
				stable_start_s = begin_s
		var held_pose: Array[float] = _pose_at(change_s)
		var target_pose: Dictionary = _sample_target(_trajectory_target, change_s)
		var off_target: bool = Geometry.separation_deg(Geometry.direction_deg(held_pose[0], held_pose[1]), target_pose.direction) > float(target_pose.diameter_deg) * 0.5
		var kept_contact: bool = stable_start_s != null and not off_target and absf(float(stable_start_s) - change_s) <= 1e-12
		var event_kind: String = "spontaneous"
		for event: Dictionary in deck.trajectory_tape.events:
			if absf(float(event.time_us) / 1000000.0 - float(reversal.ramp_start_s)) <= 1e-12 and String(event.kind).begins_with("boundary_"):
				event_kind = String(event.kind)
				break
		result.append({"ramp_start_s": reversal.ramp_start_s, "effective_sign_change_s": change_s, "event_kind": event_kind, "latency_origin": "effective_velocity_sign_change", "stable_contact_required_s": STABLE_CONTACT_S, "stable_contact_start_s": stable_start_s, "reacquisition_ms": (float(stable_start_s) - change_s) * 1000.0 if stable_start_s != null else null, "kept_contact": kept_contact, "already_off_target_at_change": off_target, "censored": stable_start_s == null, "censor_s": censor_s, "contact_window_end_s": window_end_s, "contact_window_certified_lower_s": contact_lower_s})
	return result


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish().hex_encode()


func _trace_block(bytes: PackedByteArray, count: int, record_bytes: int, fields: Array) -> Dictionary:
	var stored: PackedByteArray = PackedByteArray()
	var compression: String = "none"
	if completed:
		stored = bytes.compress(FileAccess.COMPRESSION_ZSTD) if not bytes.is_empty() else bytes
		if stored.size() < bytes.size():
			compression = "zstd"
		else:
			stored = bytes
	var encoded: Variant = null
	if completed:
		encoded = "" if stored.is_empty() else Marshalls.raw_to_base64(stored)
	return {"encoding": "packed_little_endian_v1", "compression": compression, "record_bytes": record_bytes, "record_count": count, "fields": fields, "byte_count": bytes.size(), "stored_byte_count": stored.size(), "finalized": completed, "sha256": _sha256_bytes(bytes) if completed else null, "base64": encoded}


static func _payload_bytes(value: Dictionary) -> int:
	return JSON.stringify(value, "", false, true).to_utf8_buffer().size()


static func _storage_bytes(value: Dictionary) -> int:
	return JSON.stringify(value, "\t", true, true).to_utf8_buffer().size()


static func exact_scalar_bits(value: Variant) -> Variant:
	if value is Dictionary:
		var encoded: Dictionary = {}
		for key: String in value:
			encoded[key] = exact_scalar_bits(value[key])
		return encoded
	if value is Array:
		var encoded: Array = []
		for element: Variant in value:
			encoded.append(exact_scalar_bits(element))
		return encoded
	if typeof(value) == TYPE_FLOAT:
		return "f64be:" + Canonical.float64_hex(float(value))
	if typeof(value) == TYPE_INT:
		return "i64:" + str(value)
	return value


static func restore_scalar_bits(value: Variant) -> Variant:
	if value is Dictionary:
		var decoded: Dictionary = {}
		for key: String in value:
			decoded[key] = restore_scalar_bits(value[key])
		return decoded
	if value is Array:
		var decoded: Array = []
		for element: Variant in value:
			decoded.append(restore_scalar_bits(element))
		return decoded
	if value is String and value.begins_with("f64be:"):
		return Canonical.float64_from_hex(value.trim_prefix("f64be:"))
	if value is String and value.begins_with("i64:"):
		return value.trim_prefix("i64:").to_int()
	return value


func report() -> Dictionary:
	if not _report_cache.is_empty():
		return _report_cache.duplicate(true)
	var complete: bool = completed and elapsed_s >= duration_s and invalid_reason.is_empty()
	var diagnostic_utility: Variant = null
	if complete:
		if task in ["SMOOTH", "REACTIVE"]:
			diagnostic_utility = clampf(float(metrics.contact_s) / duration_s, 0.0, 1.0)
		elif int(metrics.opportunities) > 0:
			var total_utility: float = 0.0
			for row: Dictionary in opportunities:
				if bool(row.included_in_utility):
					total_utility += float(row.utility)
			diagnostic_utility = total_utility / float(metrics.opportunities)
	var utility: Variant = diagnostic_utility if _comparison_enabled else null
	var applied_gain: Dictionary = conditions.applied_gain.duplicate(true) if conditions.get("applied_gain") is Dictionary else {}
	var attested_render_count: int = 0
	for render_receipt: Dictionary in _render_receipts:
		var proof: Dictionary = render_receipt.prepared_receipt
		if proof.get("ack_source") != "RenderingServer.frame_post_draw_not_physical_scanout" or not proof.get("targets") is Array:
			continue
		for prepared_target: Variant in proof.targets:
			if prepared_target is Dictionary and prepared_target.get("identity") == render_receipt.identity:
				attested_render_count += 1
				break
	var result_metrics: Dictionary = metrics.duplicate(true)
	result_metrics.integration_g_evaluations = _contact.evaluations
	result_metrics.angular_error_mean_deg = _angular_error_integral_deg_s / _angular_error_weight_s if _angular_error_weight_s > 0.0 else null
	result_metrics.accuracy = float(metrics.hits) / float(metrics.first_presses) if int(metrics.first_presses) > 0 else null
	var result: Dictionary = {
		"schema_version": "aimlocal.calibration_task_report.v2.0",
		"runtime_version": RUNTIME_VERSION,
		"input_convention": "received_pose_hold_v1",
		"task": task,
		"task_id": deck.get("task_id", ""),
		"deck_id": deck.get("deck_id", ""),
		"deck_manifest_sha256": deck.get("manifest_sha256", ""),
		"duration_s": duration_s,
		"elapsed_s": elapsed_s,
		"complete": complete,
		"valid": invalid_reason.is_empty(),
		"invalid_reason": invalid_reason,
		"conditions": conditions.duplicate(true),
		"candidate_id": conditions.get("candidate_id", ""),
		"applied_gain": applied_gain,
		"U": utility,
		"utility": utility,
		"diagnostic_utility": diagnostic_utility,
		"comparative_utility_included": _comparison_enabled,
		"opportunities": int(metrics.opportunities),
		"raw_succeeded": int(metrics.raw_succeeded),
		"success_count": int(metrics.raw_succeeded),
		"killed": int(metrics.kills),
		"click_opportunities": int(metrics.opportunities) if task == "CLICK" else 0,
		"switch_opportunities": int(metrics.opportunities) if task == "SWITCH" else 0,
		"click_successes": int(metrics.raw_succeeded) if task == "CLICK" else 0,
		"switch_completions": int(metrics.raw_succeeded) if task == "SWITCH" else 0,
		"first_presses": int(metrics.first_presses),
		"premature": int(metrics.premature),
		"extra_shots": int(metrics.extra_shots),
		"late_shots": int(metrics.late_shots),
		"metrics": result_metrics,
		"opportunity_dispositions": opportunities.duplicate(true),
		"hit_events": hit_events.duplicate(true),
		"diagnostic_events": diagnostic_events.duplicate(true),
		"received_pose_trace": _trace_block(received_pose_trace, _pose_trace_count, POSE_RECORD_BYTES, ["receipt_us:u32", "sequence:u32", "receipt_s:f64", "yaw_deg:f64", "pitch_deg:f64"]),
		"fire_trace": _trace_block(_fire_trace, _fire_trace_count, FIRE_RECORD_BYTES, ["receipt_us:u32", "sequence:u32", "receipt_s:f64", "pressed:u8"]),
		"render_trace": _trace_block(_render_trace, _render_trace_count, 24, ["receipt_us:u32", "after_input_sequence:u32", "receipt_index:u32", "flags:u32", "receipt_s:f64"]),
		"frame_trace": _trace_block(_frame_trace, frame_intervals_s.size(), 8, ["delta_s:f64"]),
		"render_receipts": _render_receipts.duplicate(true),
		"contact_intervals_s": _contact_intervals.duplicate(true),
		"definite_contact_intervals_s": _definite_contact_intervals.duplicate(true),
		"reversals": _reversals.duplicate(true),
		"reacquisitions": _reacquisition_diagnostics() if task == "REACTIVE" else [],
		"render_quality": quality(),
		"audit": {"mandatory": true, "replay_exact_possible": completed and invalid_reason.is_empty(), "initial_yaw_pitch_deg_f64": [Canonical.float64_hex(_initial_pose_deg[0]), Canonical.float64_hex(_initial_pose_deg[1])], "session_id": conditions.get("session_id", ""), "monotonic_origin_us": conditions.get("monotonic_origin_us", null), "actual_start_s": conditions.get("actual_start_s", null), "render_flags": {"first_prepared_ack": 1, "first_visible": 2}, "physical_scanout_certified": false, "optional_contact_intervals_omitted": false, "report_payload_bytes": 0}
	}
	result.comparable = complete and _comparison_enabled and bool(result.render_quality.get("eligible", false))
	result.audit.actual_gain_known = not applied_gain.is_empty()
	result.audit.render_proof_attested = not _render_receipts.is_empty() and attested_render_count == _render_receipts.size()
	result.audit.attested_render_record_count = attested_render_count
	result.audit.unattested_render_record_count = _render_receipts.size() - attested_render_count
	if completed:
		for receipt: Dictionary in result.render_receipts:
			receipt.prepared_receipt_exact = exact_scalar_bits(receipt.prepared_receipt)
			receipt.prepared_receipt_sha256 = Canonical.semantic_sha256(receipt.prepared_receipt)
		if _storage_bytes(result) > MAX_REPORT_BYTES:
			result.contact_intervals_s = []
			result.definite_contact_intervals_s = []
			result.audit.optional_contact_intervals_omitted = true
		if _storage_bytes(result) > MAX_REPORT_BYTES:
			invalidate("calibration_report_payload_overflow")
			result = {"schema_version": "aimlocal.calibration_task_report.v2.0", "task": task, "task_id": deck.get("task_id", ""), "deck_id": deck.get("deck_id", ""), "complete": false, "valid": false, "comparable": false, "invalid_reason": invalid_reason, "U": null, "utility": null, "duration_s": duration_s, "elapsed_s": elapsed_s, "received_pose_trace": result.received_pose_trace, "fire_trace": result.fire_trace, "render_trace": result.render_trace, "frame_trace": result.frame_trace, "audit": {"mandatory": true, "replay_exact_possible": false, "report_payload_bytes": 0}}
			if _storage_bytes(result) > MAX_REPORT_BYTES:
				for trace_key: String in ["received_pose_trace", "fire_trace", "render_trace", "frame_trace"]:
					result[trace_key].base64 = null
				result.audit.traces_omitted_due_to_payload_limit = true
		for size_iteration: int in 3:
			result.audit.report_payload_bytes = _payload_bytes(result)
			result.audit.report_storage_bytes = _storage_bytes(result)
		_report_cache = result.duplicate(true)
	return result
