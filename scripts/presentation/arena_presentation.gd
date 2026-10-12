class_name ArenaPresentation
extends Node3D

var environment_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	var dark := material(Color("172936"))
	var accent := material(Color("30545c"))
	var light := material(Color("417e82"))
	for side in [-1.0, 1.0]:
		add_block(Vector3(side * 12.4, 4.4, -11.8), Vector3(0.7, 12.0, 0.5), dark)
		add_block(Vector3(side * 11.9, 4.4, -11.45), Vector3(0.06, 11.5, 0.06), accent)
		add_block(Vector3(side * 3.0, 0.012, -7.0), Vector3(0.025, 0.02, 14.0), accent)
		for marker_index in 4:
			add_block(Vector3(side * 6.6, 0.018, -2.5 - marker_index * 2.2), Vector3(0.45, 0.025, 0.05), light)
		for strip_index in 3:
			add_block(Vector3(side * 11.3, 1.2 + strip_index * 2.2, -11.45), Vector3(0.55, 0.06, 0.06), light)
	add_block(Vector3(0.0, 10.2, -11.8), Vector3(25.5, 0.65, 0.5), dark)
	add_block(Vector3(0.0, 9.8, -11.45), Vector3(23.6, 0.06, 0.06), accent)
	add_block(Vector3(0.0, 0.22, -11.65), Vector3(25.5, 0.45, 0.6), dark)
	add_block(Vector3(0.0, 0.46, -11.3), Vector3(23.6, 0.03, 0.06), accent)
	add_block(Vector3(0.0, 0.015, -11.0), Vector3(12.0, 0.025, 0.05), light)


func material(color: Color) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color = color
	return surface


func add_block(center: Vector3, dimensions: Vector3, surface: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = surface
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	environment_meshes.append(instance)
