class_name ArenaPresentation
extends Node3D

var environment_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	var pearl := material(Color("c9ccc9"), 0.94)
	var slate := material(Color("788991"), 0.9)
	var trim := material(Color("9fa8ab"), 0.92)
	var graphite := material(Color("485d68"), 0.9)
	var cobalt := material(Color("658491"), 0.88)
	for side in [-1.0, 1.0]:
		add_block(Vector3(side * 10.8, 4.2, -11.8), Vector3(2.6, 7.8, 0.16), slate)
		add_block(Vector3(side * 13.5, 4.5, -5.5), Vector3(0.4, 9.0, 12.0), pearl)
		add_block(Vector3(side * 13.24, 0.12, -5.5), Vector3(0.16, 0.24, 12.0), trim)
		add_block(Vector3(side * 7.0, 2.6, -11.76), Vector3(2.8, 4.8, 0.2), pearl)
		add_block(Vector3(side * 8.7, 3.45, -11.65), Vector3(0.12, 6.9, 0.18), trim)
		add_block(Vector3(side * 10.3, 0.42, -9.0), Vector3(2.6, 0.84, 2.0), slate)
		add_block(Vector3(side * 10.3, 0.88, -9.0), Vector3(2.76, 0.08, 2.12), trim)
		add_block(Vector3(side * 11.2, 1.47, -9.4), Vector3(0.68, 1.12, 0.7), graphite)
		add_block(Vector3(side * 11.2, 1.55, -9.02), Vector3(0.46, 0.56, 0.08), cobalt)
		add_block(Vector3(side * 13.23, 2.9, -3.2), Vector3(0.12, 1.3, 2.4), slate)
	add_block(Vector3(0.0, 0.12, -11.8), Vector3(26.6, 0.24, 0.16), trim)
	set_process(false)
	set_physics_process(false)


func material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = roughness
	surface.metallic = metallic
	return surface


func add_block(center: Vector3, dimensions: Vector3, surface: Material) -> void:
	var mesh := beveled_box(dimensions)
	mesh.surface_set_material(0, surface)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	add_child(instance)
	environment_meshes.append(instance)


func beveled_box(dimensions_m: Vector3) -> ArrayMesh:
	var half_m := dimensions_m * 0.5
	var bevel_m := minf(0.06, minf(half_m.x, minf(half_m.y, half_m.z)) * 0.3)
	var inset_m := half_m - Vector3.ONE * bevel_m
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis_index in 3:
		var next_axis := (axis_index + 1) % 3
		var last_axis := (axis_index + 2) % 3
		for side in [-1.0, 1.0]:
			var polygon := PackedVector3Array()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point_m := Vector3.ZERO
				point_m[axis_index] = side * half_m[axis_index]
				point_m[next_axis] = corner.x * inset_m[next_axis]
				point_m[last_axis] = corner.y * inset_m[last_axis]
				polygon.append(point_m)
			append_face(builder, polygon)
	for first_axis in 3:
		for second_axis in range(first_axis + 1, 3):
			var edge_axis := 3 - first_axis - second_axis
			for first_side in [-1.0, 1.0]:
				for second_side in [-1.0, 1.0]:
					var first_m := Vector3.ZERO
					first_m[first_axis] = first_side * half_m[first_axis]
					first_m[second_axis] = second_side * inset_m[second_axis]
					first_m[edge_axis] = -inset_m[edge_axis]
					var second_m := Vector3.ZERO
					second_m[first_axis] = first_side * inset_m[first_axis]
					second_m[second_axis] = second_side * half_m[second_axis]
					second_m[edge_axis] = -inset_m[edge_axis]
					var third_m := second_m
					third_m[edge_axis] = inset_m[edge_axis]
					var fourth_m := first_m
					fourth_m[edge_axis] = inset_m[edge_axis]
					append_face(builder, PackedVector3Array([first_m, second_m, third_m, fourth_m]))
	for horizontal_side in [-1.0, 1.0]:
		for vertical_side in [-1.0, 1.0]:
			for depth_side in [-1.0, 1.0]:
				var signs := Vector3(horizontal_side, vertical_side, depth_side)
				append_face(builder, PackedVector3Array([
					signs * Vector3(half_m.x, inset_m.y, inset_m.z),
					signs * Vector3(inset_m.x, half_m.y, inset_m.z),
					signs * Vector3(inset_m.x, inset_m.y, half_m.z)]))
	return builder.commit()


func append_face(builder: SurfaceTool, polygon: PackedVector3Array) -> void:
	var normal := (polygon[1] - polygon[0]).cross(polygon[2] - polygon[0]).normalized()
	var center_m := Vector3.ZERO
	for point_m in polygon:
		center_m += point_m
	if normal.dot(center_m) < 0.0:
		normal = -normal
	for triangle_index in range(1, polygon.size() - 1):
		var second_m := polygon[triangle_index]
		var third_m := polygon[triangle_index + 1]
		if (second_m - polygon[0]).cross(third_m - polygon[0]).dot(normal) > 0.0:
			var previous_second_m := second_m
			second_m = third_m
			third_m = previous_second_m
		for point_m in [polygon[0], second_m, third_m]:
			builder.set_normal(normal)
			builder.add_vertex(point_m)
