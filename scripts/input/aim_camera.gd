class_name AimCamera
extends Camera3D

@export_range(0.001, 1.0, 0.001) var degrees_per_count: float = 0.044

var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var received_counts: Vector2 = Vector2.ZERO
var received_x_counts: float = 0.0
var received_y_counts: float = 0.0
var invert_y: bool = false


func apply_mouse_counts(mouse_counts: Vector2) -> void:
	received_x_counts += float(mouse_counts.x)
	received_y_counts += float(mouse_counts.y)
	received_counts = Vector2(received_x_counts, received_y_counts)
	yaw_deg -= float(mouse_counts.x) * degrees_per_count
	pitch_deg = clampf(pitch_deg - float(mouse_counts.y) * degrees_per_count * (-1.0 if invert_y else 1.0), -89.0, 89.0)
	rotation_degrees = Vector3(pitch_deg, wrapf(yaw_deg, -180.0, 180.0), 0.0)


func reset_aim() -> void:
	yaw_deg = 0.0
	pitch_deg = 0.0
	received_counts = Vector2.ZERO
	received_x_counts = 0.0
	received_y_counts = 0.0
	rotation = Vector3.ZERO
