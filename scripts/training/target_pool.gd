class_name TargetPool
extends Node3D

var spheres: Array[MeshInstance3D] = []
@onready var aim_camera: Camera3D = get_node("../AimCamera") as Camera3D


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("64e6d9")
	material.roughness = 1.0
	mesh.material = material
	for target_index in 6:
		var sphere := MeshInstance3D.new()
		sphere.mesh = mesh
		sphere.visible = false
		add_child(sphere)
		spheres.append(sphere)


func sync(engine: ScenarioEngine, time_s: float) -> void:
	for target_index in spheres.size():
		var sphere := spheres[target_index]
		sphere.visible = target_index < engine.targets.size()
		if sphere.visible:
			var center: Vector3 = aim_camera.global_position + engine.target_direction(target_index, time_s) * engine.definition.distance_m
			sphere.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * engine.radius_m()), center)


func hide_targets() -> void:
	for sphere in spheres:
		sphere.hide()
