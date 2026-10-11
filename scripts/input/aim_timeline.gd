class_name AimTimeline
extends RefCounted

const CAPACITY: int = 32768

var timestamps_s := PackedFloat64Array()
var yaw_deg := PackedFloat64Array()
var pitch_deg := PackedFloat64Array()
var read_index: int = 0
var write_index: int = 0
var count: int = 0
var overflow_count: int = 0
var sampled_pose: Vector2 = Vector2.ZERO
var last_time_s: float = 0.0
var last_yaw_deg: float = 0.0
var last_pitch_deg: float = 0.0
var angular_path_deg: float = 0.0
var event_count: int = 0


func _init() -> void:
	timestamps_s.resize(CAPACITY)
	yaw_deg.resize(CAPACITY)
	pitch_deg.resize(CAPACITY)


func reset(initial_yaw_deg: float, initial_pitch_deg: float) -> void:
	read_index = 0
	write_index = 0
	count = 0
	overflow_count = 0
	sampled_pose = Vector2(initial_yaw_deg, initial_pitch_deg)
	last_yaw_deg = initial_yaw_deg
	last_pitch_deg = initial_pitch_deg
	last_time_s = 0.0
	angular_path_deg = 0.0
	event_count = 0


func push(time_s: float, new_yaw_deg: float, new_pitch_deg: float) -> void:
	if not is_finite(time_s) or not is_finite(new_yaw_deg) or not is_finite(new_pitch_deg) or time_s < last_time_s:
		return
	event_count += 1
	var delta_yaw_deg := new_yaw_deg - last_yaw_deg
	var delta_pitch_deg := new_pitch_deg - last_pitch_deg
	angular_path_deg += sqrt(delta_yaw_deg * delta_yaw_deg + delta_pitch_deg * delta_pitch_deg)
	last_time_s = time_s
	last_yaw_deg = new_yaw_deg
	last_pitch_deg = new_pitch_deg
	if count == CAPACITY:
		overflow_count += 1
		return
	timestamps_s[write_index] = time_s
	yaw_deg[write_index] = new_yaw_deg
	pitch_deg[write_index] = new_pitch_deg
	write_index = (write_index + 1) % CAPACITY
	count += 1


func sample(time_s: float) -> Vector2:
	while count > 0 and timestamps_s[read_index] <= time_s:
		sampled_pose = Vector2(yaw_deg[read_index], pitch_deg[read_index])
		read_index = (read_index + 1) % CAPACITY
		count -= 1
	return sampled_pose
