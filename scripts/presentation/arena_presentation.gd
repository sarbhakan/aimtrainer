class_name ArenaPresentation
extends Node3D

var environment_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	var pearl := material(Color("b0afa4"), 0.94)
	var ivory := material(Color("bdb8a9"), 0.88)
	var graphite := material(Color("33434d"), 0.68)
	var cobalt := material(Color("345d79"), 0.72)
	var steel := material(Color("717c83"), 0.48, 0.35)
	var glass := material(Color("a9c5d3"), 0.32)
	for side in [-1.0, 1.0]:
		add_block(Vector3(side * 10.2, 4.45, -11.7), Vector3(3.5, 8.8, 0.4), cobalt)
		add_block(Vector3(side * 8.35, 4.45, -11.55), Vector3(0.18, 9.0, 0.55), graphite)
		add_block(Vector3(side * 12.0, 4.45, -11.55), Vector3(0.18, 9.0, 0.55), graphite)
		add_block(Vector3(side * 10.15, 0.3, -11.4), Vector3(3.7, 0.32, 0.3), steel)
		add_block(Vector3(side * 13.5, 4.5, -5.5), Vector3(0.3, 9.0, 13.0), pearl)
		add_block(Vector3(side * 13.29, 5.9, -6.0), Vector3(0.12, 3.5, 7.0), glass)
		add_block(Vector3(side * 13.18, 4.05, -6.0), Vector3(0.3, 0.16, 7.2), steel)
		add_block(Vector3(side * 12.8, 0.06, -6.5), Vector3(0.13, 0.12, 13.0), graphite)
	for panel_index in 5:
		var horizontal_m := float(panel_index - 2) * 2.85
		var vertical_m: float = [4.0, 4.8, 4.35, 4.0, 4.6][panel_index]
		add_block(Vector3(horizontal_m, vertical_m, -11.72), Vector3(2.55, 5.8, 0.3), ivory if panel_index % 2 == 0 else pearl)
	add_block(Vector3(0.0, 0.16, -11.63), Vector3(26.8, 0.3, 0.5), graphite)
	add_block(Vector3(0.0, 8.95, -11.35), Vector3(27.0, 0.3, 0.9), steel)
	for side in [-1.0, 1.0]:
		add_block(Vector3(side * 10.2, 9.2, -6.0), Vector3(6.4, 0.3, 13.0), ivory)
	for roof_depth_m in [-11.4, -0.6]:
		add_block(Vector3(0.0, 9.2, roof_depth_m), Vector3(14.0, 0.3, 2.2), ivory)
	for beam_depth_m in [-2.5, -6.5, -10.5]:
		add_block(Vector3(0.0, 8.98, beam_depth_m), Vector3(27.0, 0.3, 0.24), graphite)
	add_block(Vector3(0.0, 9.0, -6.5), Vector3(14.0, 0.08, 7.6), glass)
	environment_meshes.back().cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_process(false)


func material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = roughness
	surface.metallic = metallic
	return surface


func add_block(center: Vector3, dimensions: Vector3, surface: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = surface
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	add_child(instance)
	environment_meshes.append(instance)
