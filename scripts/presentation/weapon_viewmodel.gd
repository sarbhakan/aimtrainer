class_name WeaponViewmodel
extends TextureRect

const MAX_RENDER_SIZE_PX := Vector2i(960, 540)
const VIEW_FOV_DEG: float = 50.0
const AIM_DEPTH_M: float = 18.0

var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var weapon_root: Node3D
var muzzle: Marker3D
var slide: Node3D
var flash: Node3D
var flash_material: StandardMaterial3D
var models: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var materials: Dictionary = {}
var region_px := Rect2()
var control_size_px := Vector2.ZERO
var aim_point_m := Vector3.ZERO
var mount_position_m := Vector3.ZERO
var hud_mode: bool = false
var rendering_enabled: bool = false
var animated: bool = false
var selected_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(false)
	viewport = SubViewport.new()
	viewport.name = "WeaponViewport"
	viewport.size = Vector2i(2, 2)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(viewport)
	texture = viewport.get_texture()
	stage = Node3D.new()
	stage.name = "WeaponStage"
	viewport.add_child(stage)
	camera = Camera3D.new()
	camera.name = "ViewmodelCamera"
	camera.near = 0.05
	camera.far = 30.0
	stage.add_child(camera)
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9d2dd")
	environment.ambient_light_energy = 0.38
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	add_light(Vector3(-0.85, -0.65, -0.18), Color("fff1dc"), 1.05)
	add_light(Vector3(-0.2, 2.2, 0.15), Color("bdd3eb"), 0.42)
	weapon_root = Node3D.new()
	weapon_root.name = "HeldWeapon"
	stage.add_child(weapon_root)
	build_pulse()
	build_vector()
	build_classic()
	build_flash()
	weapon_root.hide()
	hide()


func add_light(rotation_rad: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	var is_key := stage.get_node_or_null("KeyLight") == null
	light.name = "KeyLight" if is_key else "FillLight"
	light.rotation = rotation_rad
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = is_key
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 5.0
	light.shadow_bias = 0.1
	light.shadow_normal_bias = 1.5
	light.shadow_opacity = 0.65
	stage.add_child(light)


func set_profile(weapon_id: String, color: Color) -> void:
	for model: Node3D in models.values():
		model.hide()
	selected_id = weapon_id if models.has(weapon_id) else "pulse"
	var selected: Node3D = models[selected_id]
	selected.show()
	muzzle = selected.get_node("Muzzle") as Marker3D
	slide = selected.get_node("Slide") as Node3D
	flash_material.albedo_color = Color(color, 0.8)
	flash_material.emission = color
	weapon_root.show()
	apply_pose(0.0, 0.0)


func set_layout(dimensions_px: Vector2, in_hud: bool, clearance_px: float) -> void:
	control_size_px = dimensions_px
	hud_mode = in_hud
	region_px = Rect2(Vector2.ZERO, dimensions_px)
	if hud_mode:
		var margin_px := maxf(clearance_px, 18.0) + 8.0
		var corner_px := Vector2(maxf(dimensions_px.x * 0.57, dimensions_px.x * 0.5 + margin_px), maxf(dimensions_px.y * 0.55, dimensions_px.y * 0.5 + margin_px))
		region_px = Rect2(corner_px, (dimensions_px - corner_px).max(Vector2.ZERO))
	position = region_px.position
	size = region_px.size
	if size.x < 2.0 or size.y < 2.0 or dimensions_px.x < 2.0 or dimensions_px.y < 2.0:
		set_render_state(false, false)
		return
	var resolution_scale := minf(1.0, minf(float(MAX_RENDER_SIZE_PX.x) / size.x, float(MAX_RENDER_SIZE_PX.y) / size.y))
	viewport.size = Vector2i(maxi(roundi(size.x * resolution_scale), 2), maxi(roundi(size.y * resolution_scale), 2))
	var near_height_m := 2.0 * camera.near * tan(deg_to_rad(VIEW_FOV_DEG * 0.5))
	var offset_px := region_px.get_center() - dimensions_px * 0.5
	var offset_m := Vector2(offset_px.x, -offset_px.y) * near_height_m / dimensions_px.y
	camera.set_frustum(near_height_m * size.y / dimensions_px.y, offset_m, camera.near, camera.far)
	aim_point_m = unproject_from_control(dimensions_px * 0.5, AIM_DEPTH_M)
	var anchor_uv := Vector2(0.84, 0.80) if hud_mode else Vector2(0.70, 0.96)
	mount_position_m = unproject_from_control(dimensions_px * anchor_uv, 2.0 if hud_mode else 1.45)
	apply_pose(0.0, 0.0)
	request_render()


func to_viewport_px(point_px: Vector2) -> Vector2:
	return (point_px - region_px.position) * Vector2(viewport.size) / region_px.size.max(Vector2.ONE)


func unproject_from_control(point_px: Vector2, depth_m: float) -> Vector3:
	var normalized := to_viewport_px(point_px) / Vector2(viewport.size)
	var clip_point := Vector4(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0, 0.0, 1.0)
	var projected := camera.get_camera_projection().inverse() * clip_point
	var local_point_m := Vector3(projected.x, projected.y, projected.z) / projected.w
	return camera.global_transform * (local_point_m * depth_m / -local_point_m.z)


func project_to_control(point_m: Vector3) -> Vector2:
	return region_px.position + camera.unproject_position(point_m) * region_px.size / Vector2(viewport.size)


func muzzle_position_px() -> Vector2:
	return project_to_control(muzzle.global_position) if muzzle != null else Vector2.ZERO


func muzzle_axis() -> Vector3:
	return -muzzle.global_basis.z.normalized() if muzzle != null else Vector3.FORWARD


func apply_pose(recoil_weight: float, flash_weight: float) -> void:
	if muzzle == null:
		return
	var weight := clampf(recoil_weight, 0.0, 1.0)
	var origin_m := mount_position_m + Vector3(0.022, -0.036, 0.10) * weight
	var direction := aim_point_m - origin_m
	var aim_basis := Basis.looking_at(direction, Vector3.UP) if direction.length_squared() > 0.0001 else Basis.IDENTITY
	var model_scale := 0.70 if hud_mode else 1.0
	weapon_root.transform = Transform3D((aim_basis * Basis(Vector3.FORWARD, 0.022 * weight)).scaled(Vector3.ONE * model_scale), origin_m)
	slide.position = Vector3(0.0, 0.009, 0.085) * weight
	flash.global_transform = muzzle.global_transform
	flash.scale = Vector3.ONE * (0.65 + 0.35 * clampf(flash_weight, 0.0, 1.0))
	flash.visible = flash_weight > 0.0
	flash_material.albedo_color.a = 0.8 * clampf(flash_weight, 0.0, 1.0)


func set_render_state(enabled: bool, moving: bool) -> void:
	rendering_enabled = enabled and region_px.size.x >= 2.0 and region_px.size.y >= 2.0
	animated = moving and rendering_enabled
	visible = rendering_enabled
	viewport.process_mode = Node.PROCESS_MODE_INHERIT if rendering_enabled else Node.PROCESS_MODE_DISABLED
	if not rendering_enabled:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		flash.hide()
	else:
		request_render()


func request_render() -> void:
	if rendering_enabled:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if animated else SubViewport.UPDATE_ONCE


func make_model(weapon_id: String, muzzle_depth_m: float) -> Node3D:
	var model := Node3D.new()
	model.name = weapon_id.capitalize()
	weapon_root.add_child(model)
	models[weapon_id] = model
	var marker := Marker3D.new()
	marker.name = "Muzzle"
	marker.position.z = -muzzle_depth_m
	model.add_child(marker)
	var moving_slide := Node3D.new()
	moving_slide.name = "Slide"
	model.add_child(moving_slide)
	model.hide()
	return model


func material(color: Color, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	return _finish(color, metallic, 0.46 if metallic > 0.0 else 0.8, emission)


func _finish(color: Color, metallic: float, roughness: float, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%s/%s/%s" % [color.to_html(), metallic, roughness, emission]
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	result.emission_enabled = emission > 0.0
	result.emission = color
	result.emission_energy_multiplier = emission
	materials[key] = result
	return result


func add_mesh(parent: Node3D, label: String, mesh: Mesh, surface: Material, origin_m: Vector3, rotation_rad: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = surface
	instance.position = origin_m
	instance.rotation = rotation_rad
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if surface is BaseMaterial3D and surface.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	meshes.append(instance)
	return instance


func block(parent: Node3D, label: String, dimensions_m: Vector3, origin_m: Vector3, surface: Material, rotation_rad: Vector3 = Vector3.ZERO) -> void:
	add_mesh(parent, label, chamfered_box(dimensions_m), surface, origin_m, rotation_rad)


func chamfered_box(dimensions_m: Vector3) -> ArrayMesh:
	var half_m := dimensions_m * 0.5
	var bevel_m := minf(0.018, minf(half_m.x, minf(half_m.y, half_m.z)) * 0.32)
	var rings: Array[PackedVector3Array] = []
	for ring_index in 4:
		var inset_m := bevel_m * 0.6 if ring_index == 0 or ring_index == 3 else 0.0
		var extent_m := Vector2(half_m.x - inset_m, half_m.y - inset_m)
		var depth_m: float = [-half_m.z, -half_m.z + bevel_m, half_m.z - bevel_m, half_m.z][ring_index]
		var outline: PackedVector2Array = [Vector2(-extent_m.x + bevel_m, -extent_m.y), Vector2(extent_m.x - bevel_m, -extent_m.y), Vector2(extent_m.x, -extent_m.y + bevel_m), Vector2(extent_m.x, extent_m.y - bevel_m), Vector2(extent_m.x - bevel_m, extent_m.y), Vector2(-extent_m.x + bevel_m, extent_m.y), Vector2(-extent_m.x, extent_m.y - bevel_m), Vector2(-extent_m.x, -extent_m.y + bevel_m)]
		var ring := PackedVector3Array()
		for point in outline:
			ring.append(Vector3(point.x, point.y, depth_m))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_face(surface, rings[0])
	append_face(surface, rings[3])
	for ring_index in 3:
		for edge_index in 8:
			var next_index := (edge_index + 1) % 8
			append_face(surface, PackedVector3Array([rings[ring_index][edge_index], rings[ring_index][next_index], rings[ring_index + 1][next_index], rings[ring_index + 1][edge_index]]))
	return surface.commit()


func _profile(parent: Node3D, label: String, width_m: float, outline_m: PackedVector2Array, origin_m: Vector3, surface: Material, rotation_rad: Vector3 = Vector3.ZERO) -> void:
	add_mesh(parent, label, _beveled_profile(width_m, outline_m), surface, origin_m, rotation_rad)


func _beveled_profile(width_m: float, outline_m: PackedVector2Array) -> ArrayMesh:
	var bevel_m := minf(0.014, width_m * 0.18)
	var inset_outline_m := PackedVector2Array()
	for point_index in outline_m.size():
		var point_m := outline_m[point_index]
		var previous_m := outline_m[(point_index + outline_m.size() - 1) % outline_m.size()]
		var next_m := outline_m[(point_index + 1) % outline_m.size()]
		var before := (point_m - previous_m).normalized()
		var after := (next_m - point_m).normalized()
		var inward := Vector2(-before.y, before.x)
		var bisector := (inward + Vector2(-after.y, after.x)).normalized()
		inset_outline_m.append(point_m + bisector * bevel_m / maxf(bisector.dot(inward), 0.2))
	var rings: Array[PackedVector3Array] = []
	for ring_index in 4:
		var offset_m: float = [-width_m * 0.5, -width_m * 0.5 + bevel_m, width_m * 0.5 - bevel_m, width_m * 0.5][ring_index]
		var outline := inset_outline_m if ring_index == 0 or ring_index == 3 else outline_m
		var ring := PackedVector3Array()
		for point_m in outline:
			ring.append(Vector3(offset_m, point_m.y, point_m.x))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_face(surface, rings[0])
	append_face(surface, rings[3])
	for ring_index in 3:
		for edge_index in outline_m.size():
			var next_index := (edge_index + 1) % outline_m.size()
			append_face(surface, PackedVector3Array([rings[ring_index][edge_index], rings[ring_index][next_index], rings[ring_index + 1][next_index], rings[ring_index + 1][edge_index]]))
	return surface.commit()


func _rounded(parent: Node3D, label: String, dimensions_m: Vector3, origin_m: Vector3, surface: Material, rotation_rad: Vector3 = Vector3.ZERO) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var instance := add_mesh(parent, label, mesh, surface, origin_m, rotation_rad)
	instance.scale = dimensions_m


func _segment(parent: Node3D, label: String, start_m: Vector3, end_m: Vector3, radius_m: float, surface: Material) -> void:
	var direction_m := end_m - start_m
	var mesh := CapsuleMesh.new()
	mesh.radius = radius_m
	mesh.height = direction_m.length() + radius_m * 2.0
	mesh.radial_segments = 12
	mesh.rings = 2
	var instance := add_mesh(parent, label, mesh, surface, (start_m + end_m) * 0.5)
	instance.quaternion = Quaternion(Vector3.UP, direction_m.normalized())


func _soft_volume(parent: Node3D, label: String, centers_m: PackedVector3Array, radii_m: PackedVector2Array, surface: Material) -> void:
	var radial_segments: int = 12
	var rings: Array[PackedVector3Array] = []
	var side := (centers_m[1] - centers_m[0]).cross(Vector3.UP).normalized()
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	for center_index in centers_m.size():
		var before_m := centers_m[maxi(center_index - 1, 0)]
		var after_m := centers_m[mini(center_index + 1, centers_m.size() - 1)]
		var tangent := (after_m - before_m).normalized()
		side = (side - tangent * side.dot(tangent)).normalized()
		var up := side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		for radial_index in radial_segments:
			var angle_rad := TAU * float(radial_index) / float(radial_segments)
			ring.append(centers_m[center_index] + side * cos(angle_rad) * radii_m[center_index].x + up * sin(angle_rad) * radii_m[center_index].y)
		rings.append(ring)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(0)
	for ring_index in rings.size() - 1:
		for radial_index in radial_segments:
			var next_index := (radial_index + 1) % radial_segments
			for point_m in [rings[ring_index][radial_index], rings[ring_index][next_index], rings[ring_index + 1][next_index], rings[ring_index][radial_index], rings[ring_index + 1][next_index], rings[ring_index + 1][radial_index]]:
				builder.add_vertex(point_m)
	for radial_index in radial_segments:
		var next_index := (radial_index + 1) % radial_segments
		for point_m in [centers_m[0], rings[0][next_index], rings[0][radial_index], centers_m[-1], rings[-1][radial_index], rings[-1][next_index]]:
			builder.add_vertex(point_m)
	builder.generate_normals()
	builder.index()
	add_mesh(parent, label, builder.commit(), surface, Vector3.ZERO)


func append_face(surface: SurfaceTool, polygon: PackedVector3Array) -> void:
	var normal := (polygon[1] - polygon[0]).cross(polygon[2] - polygon[0]).normalized()
	var center_m := Vector3.ZERO
	for point in polygon:
		center_m += point
	if normal.dot(center_m) < 0.0:
		normal = -normal
	for triangle_index in range(1, polygon.size() - 1):
		var second := polygon[triangle_index]
		var third := polygon[triangle_index + 1]
		if (second - polygon[0]).cross(third - polygon[0]).dot(normal) > 0.0:
			var previous_second := second
			second = third
			third = previous_second
		for point in [polygon[0], second, third]:
			surface.set_normal(normal)
			surface.add_vertex(point)


func barrel(parent: Node3D, label: String, radius_m: float, length_m: float, depth_m: float, surface: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_m
	mesh.bottom_radius = radius_m
	mesh.height = length_m
	mesh.radial_segments = 16
	add_mesh(parent, label, mesh, surface, Vector3(0.0, 0.0, depth_m), Vector3(PI * 0.5, 0.0, 0.0))


func muzzle_rim(parent: Node3D, radius_m: float, depth_m: float, surface: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius_m * 0.70
	mesh.outer_radius = radius_m
	mesh.rings = 16
	mesh.ring_segments = 8
	add_mesh(parent, "MuzzleRim", mesh, surface, Vector3(0.0, 0.0, -depth_m), Vector3(PI * 0.5, 0.0, 0.0))
	barrel(parent, "RecessedBore", radius_m * 0.70, 0.008, -depth_m + 0.014, material(Color("080e16")))


func build_grip(parent: Node3D, surface: Material) -> void:
	var grip_origin_m := Vector3(0.0, -0.235, 0.11)
	var grip_rotation_rad := Vector3(-0.24, 0.0, 0.0)
	var grip_outline_m: PackedVector2Array = [Vector2(-0.08, -0.17), Vector2(0.07, -0.17), Vector2(0.105, 0.08), Vector2(0.075, 0.17), Vector2(-0.085, 0.17), Vector2(-0.105, 0.10)]
	_profile(parent, "Grip", 0.14, grip_outline_m, grip_origin_m, surface, grip_rotation_rad)
	block(parent, "GripHeel", Vector3(0.155, 0.024, 0.19), Vector3(0.0, -0.404, 0.151), surface, grip_rotation_rad)
	var hand := Node3D.new()
	hand.name = "GrippingHand"
	hand.position = grip_origin_m
	hand.rotation = grip_rotation_rad
	parent.add_child(hand)
	var glove := _finish(Color("414649"), 0.0, 0.94)
	var palm_centers_m: PackedVector3Array = [Vector3(0.038, -0.135, 0.132), Vector3(0.038, -0.10, 0.132), Vector3(0.035, -0.04, 0.13), Vector3(0.03, 0.035, 0.122), Vector3(0.02, 0.082, 0.112), Vector3(0.014, 0.112, 0.10)]
	var palm_radii_m: PackedVector2Array = [Vector2(0.055, 0.041), Vector2(0.075, 0.052), Vector2(0.089, 0.057), Vector2(0.087, 0.054), Vector2(0.077, 0.042), Vector2(0.046, 0.027)]
	_soft_volume(hand, "GlovedPalm", palm_centers_m, palm_radii_m, glove)
	for finger_index in 3:
		var height_m := 0.038 - finger_index * 0.057
		var radius_m := 0.025 - finger_index * 0.002
		var finger_centers_m: PackedVector3Array = [Vector3(0.078, height_m, 0.079), Vector3(0.098, height_m, 0.031), Vector3(0.104, height_m, -0.025), Vector3(0.088, height_m, -0.075), Vector3(0.058, height_m, -0.105)]
		var finger_radii_m: PackedVector2Array = [Vector2(radius_m * 0.85, radius_m * 0.8), Vector2(radius_m, radius_m * 0.86), Vector2(radius_m, radius_m * 0.9), Vector2(radius_m * 0.92, radius_m * 0.86), Vector2(radius_m * 0.82, radius_m * 0.8)]
		_soft_volume(hand, "Finger%d" % finger_index, finger_centers_m, finger_radii_m, glove)
		var tip_centers_m: PackedVector3Array = [finger_centers_m[-1], Vector3(0.005, height_m, -0.116), Vector3(-0.046, height_m, -0.108), Vector3(-0.079, height_m + 0.005, -0.083), Vector3(-0.081, height_m + 0.01, -0.054), Vector3(-0.073, height_m + 0.012, -0.038)]
		var tip_radii_m: PackedVector2Array = [Vector2(radius_m * 0.83, radius_m * 0.8), Vector2(radius_m * 0.82, radius_m * 0.78), Vector2(radius_m * 0.8, radius_m * 0.75), Vector2(radius_m * 0.74, radius_m * 0.71), Vector2(radius_m * 0.61, radius_m * 0.59), Vector2(radius_m * 0.36, radius_m * 0.35)]
		_soft_volume(hand, "Fingertip%d" % finger_index, tip_centers_m, tip_radii_m, glove)
	var thumb_centers_m: PackedVector3Array = [Vector3(-0.048, 0.004, 0.104), Vector3(-0.075, 0.036, 0.065), Vector3(-0.096, 0.068, 0.014), Vector3(-0.108, 0.085, -0.042)]
	var thumb_radii_m: PackedVector2Array = [Vector2(0.028, 0.024), Vector2(0.029, 0.025), Vector2(0.026, 0.023), Vector2(0.022, 0.020)]
	_soft_volume(hand, "Thumb", thumb_centers_m, thumb_radii_m, glove)
	_segment(hand, "ThumbTip", thumb_centers_m[-1], Vector3(-0.098, 0.09, -0.09), 0.021, glove)
	var index_centers_m: PackedVector3Array = [Vector3(0.074, 0.088, 0.07), Vector3(0.094, 0.115, 0.015), Vector3(0.097, 0.128, -0.062), Vector3(0.075, 0.121, -0.123)]
	var index_radii_m: PackedVector2Array = [Vector2(0.023, 0.02), Vector2(0.023, 0.021), Vector2(0.022, 0.020), Vector2(0.020, 0.018)]
	_soft_volume(hand, "Index", index_centers_m, index_radii_m, glove)
	_segment(hand, "IndexTip", index_centers_m[-1], Vector3(0.028, 0.10, -0.182), 0.019, glove)
	_rounded(hand, "Wrist", Vector3(0.135, 0.13, 0.12), Vector3(0.037, -0.158, 0.132), glove)
	_segment(hand, "Cuff", Vector3(0.038, -0.207, 0.148), Vector3(0.052, -0.236, 0.174), 0.075, _finish(Color("363d40"), 0.0, 0.9))
	var sleeve_centers_m: PackedVector3Array = [Vector3(0.052, -0.233, 0.172), Vector3(0.058, -0.272, 0.221), Vector3(0.076, -0.326, 0.353), Vector3(0.115, -0.43, 0.61), Vector3(0.123, -0.454, 0.672)]
	var sleeve_radii_m: PackedVector2Array = [Vector2(0.073, 0.067), Vector2(0.082, 0.077), Vector2(0.089, 0.083), Vector2(0.096, 0.09), Vector2(0.10, 0.092)]
	_soft_volume(hand, "Sleeve", sleeve_centers_m, sleeve_radii_m, _finish(Color("464e51"), 0.0, 0.95))


func _support_hand(parent: Node3D) -> void:
	var hand := Node3D.new()
	hand.name = "SupportHand"
	parent.add_child(hand)
	var glove := _finish(Color("414649"), 0.0, 0.94)
	var palm_centers_m: PackedVector3Array = [Vector3(-0.01, -0.122, -0.585), Vector3(-0.006, -0.125, -0.638), Vector3(-0.005, -0.126, -0.72), Vector3(-0.006, -0.123, -0.80), Vector3(-0.012, -0.12, -0.854)]
	var palm_radii_m: PackedVector2Array = [Vector2(0.05, 0.036), Vector2(0.087, 0.052), Vector2(0.098, 0.06), Vector2(0.089, 0.053), Vector2(0.053, 0.036)]
	_soft_volume(hand, "Palm", palm_centers_m, palm_radii_m, glove)
	for finger_index in 4:
		var depth_m := -0.636 - finger_index * 0.054
		var radius_m := 0.024 - finger_index * 0.001
		var finger_centers_m: PackedVector3Array = [Vector3(-0.107, -0.077, depth_m), Vector3(-0.134, -0.106, depth_m), Vector3(-0.094, -0.158, depth_m), Vector3(-0.025, -0.182, depth_m), Vector3(0.05, -0.16, depth_m + 0.005)]
		var finger_radii_m: PackedVector2Array = [Vector2(radius_m * 0.9, radius_m), Vector2(radius_m, radius_m), Vector2(radius_m, radius_m * 0.9), Vector2(radius_m * 0.9, radius_m * 0.85), Vector2(radius_m * 0.85, radius_m * 0.8)]
		_soft_volume(hand, "Finger%d" % finger_index, finger_centers_m, finger_radii_m, glove)
		_segment(hand, "Fingertip%d" % finger_index, finger_centers_m[-1], Vector3(0.119, -0.085, depth_m + 0.008), radius_m * 0.85, glove)
	var thumb_centers_m: PackedVector3Array = [Vector3(-0.10, -0.12, -0.595), Vector3(-0.126, -0.071, -0.631), Vector3(-0.132, -0.025, -0.688), Vector3(-0.128, -0.013, -0.746)]
	var thumb_radii_m: PackedVector2Array = [Vector2(0.027, 0.024), Vector2(0.027, 0.024), Vector2(0.024, 0.021), Vector2(0.020, 0.018)]
	_soft_volume(hand, "Thumb", thumb_centers_m, thumb_radii_m, glove)
	_rounded(hand, "Wrist", Vector3(0.13, 0.125, 0.15), Vector3(-0.105, -0.175, -0.60), glove)
	_segment(hand, "Cuff", Vector3(-0.116, -0.218, -0.56), Vector3(-0.133, -0.242, -0.53), 0.072, _finish(Color("363d40"), 0.0, 0.9))
	var sleeve_centers_m: PackedVector3Array = [Vector3(-0.128, -0.23, -0.54), Vector3(-0.149, -0.285, -0.46), Vector3(-0.174, -0.39, -0.27), Vector3(-0.18, -0.59, 0.08), Vector3(-0.18, -0.64, 0.17)]
	var sleeve_radii_m: PackedVector2Array = [Vector2(0.069, 0.065), Vector2(0.077, 0.073), Vector2(0.084, 0.078), Vector2(0.092, 0.085), Vector2(0.095, 0.088)]
	_soft_volume(hand, "Sleeve", sleeve_centers_m, sleeve_radii_m, _finish(Color("464e51"), 0.0, 0.95))


func _trigger_guard(parent: Node3D, surface: Material) -> void:
	block(parent, "TriggerGuardBase", Vector3(0.135, 0.027, 0.255), Vector3(0.0, -0.212, -0.08), surface, Vector3(0.06, 0.0, 0.0))
	var outline_m: PackedVector2Array = [Vector2(-0.021, -0.044), Vector2(0.012, -0.056), Vector2(0.026, 0.044), Vector2(-0.016, 0.056)]
	_profile(parent, "TriggerGuardFront", 0.135, outline_m, Vector3(0.0, -0.152, -0.208), surface)
	block(parent, "TriggerGuardRear", Vector3(0.135, 0.07, 0.026), Vector3(0.0, -0.163, 0.047), surface, Vector3(-0.24, 0.0, 0.0))
	_segment(parent, "Trigger", Vector3(0.0, -0.09, -0.075), Vector3(0.0, -0.17, -0.11), 0.011, _finish(Color("868d91"), 0.65, 0.4))


func _sights(parent: Node3D, front_depth_m: float, rear_depth_m: float, height_m: float, surface: Material) -> void:
	block(parent, "FrontSight", Vector3(0.029, 0.042, 0.044), Vector3(0.0, height_m + 0.025, front_depth_m), surface)
	block(parent, "RearSight", Vector3(0.135, 0.019, 0.06), Vector3(0.0, height_m + 0.008, rear_depth_m), surface)
	var accent := _finish(Color("295baa"), 0.25, 0.48)
	for side_sign in [-1.0, 1.0]:
		block(parent, "SightEar", Vector3(0.028, 0.042, 0.047), Vector3(side_sign * 0.052, height_m + 0.029, rear_depth_m), surface)
		block(parent, "SightInsert", Vector3(0.016, 0.018, 0.007), Vector3(side_sign * 0.052, height_m + 0.032, rear_depth_m + 0.026), accent)


func build_pulse() -> void:
	var model := make_model("pulse", 0.66)
	var ivory := _finish(Color("ded9cb"), 0.12, 0.56)
	var graphite := _finish(Color("363e42"), 0.4, 0.54)
	var polymer := _finish(Color("282f32"), 0.0, 0.82)
	var steel := _finish(Color("a9b0b4"), 0.68, 0.36)
	var accent := _finish(Color("295baa"), 0.25, 0.48)
	var frame_outline_m: PackedVector2Array = [Vector2(-0.28, -0.04), Vector2(0.10, -0.06), Vector2(0.28, -0.016), Vector2(0.28, 0.025), Vector2(0.20, 0.065), Vector2(-0.26, 0.065), Vector2(-0.28, 0.025)]
	_profile(model, "Receiver", 0.19, frame_outline_m, Vector3(0.0, -0.035, -0.15), graphite)
	block(model, "LowerSpine", Vector3(0.15, 0.045, 0.35), Vector3(0.0, -0.088, -0.35), polymer)
	var moving_slide: Node3D = model.get_node("Slide")
	var slide_outline_m: PackedVector2Array = [Vector2(-0.31, -0.073), Vector2(0.28, -0.073), Vector2(0.31, -0.044), Vector2(0.31, 0.045), Vector2(0.275, 0.087), Vector2(-0.28, 0.087), Vector2(-0.31, 0.045)]
	_profile(moving_slide, "ChargingShroud", 0.215, slide_outline_m, Vector3(0.0, 0.075, -0.23), ivory)
	block(moving_slide, "RearHousing", Vector3(0.14, 0.105, 0.022), Vector3(0.0, 0.074, 0.087), graphite)
	block(moving_slide, "TopFlat", Vector3(0.096, 0.012, 0.43), Vector3(0.0, 0.165, -0.26), ivory)
	barrel(model, "OctagonalBarrel", 0.052, 0.24, -0.54, graphite)
	barrel(model, "InductionCollar0", 0.061, 0.025, -0.60, steel)
	muzzle_rim(model, 0.057, 0.66, steel)
	for side_sign in [-1.0, 1.0]:
		block(moving_slide, "AccentRecess", Vector3(0.01, 0.03, 0.14), Vector3(side_sign * 0.108, 0.057, -0.34), graphite)
		block(moving_slide, "CobaltInlay", Vector3(0.008, 0.014, 0.115), Vector3(side_sign * 0.115, 0.06, -0.34), accent)
		for groove_index in 3:
			block(moving_slide, "SlideSerration", Vector3(0.009, 0.073, 0.009), Vector3(side_sign * 0.109, 0.075, -0.08 + groove_index * 0.033), graphite, Vector3(0.20, 0.0, 0.0))
	block(moving_slide, "EjectionPort", Vector3(0.052, 0.01, 0.10), Vector3(0.047, 0.166, -0.19), graphite)
	_trigger_guard(model, polymer)
	_sights(moving_slide, -0.485, 0.025, 0.164, graphite)
	build_grip(model, polymer)


func build_vector() -> void:
	var model := make_model("vector", 1.28)
	var graphite := _finish(Color("363e42"), 0.4, 0.54)
	var ivory := _finish(Color("ded9cb"), 0.12, 0.56)
	var polymer := _finish(Color("282f32"), 0.0, 0.82)
	var steel := _finish(Color("a9b0b4"), 0.68, 0.36)
	var accent := _finish(Color("295baa"), 0.25, 0.48)
	var receiver_outline_m: PackedVector2Array = [Vector2(-0.30, -0.09), Vector2(0.24, -0.09), Vector2(0.30, -0.04), Vector2(0.30, 0.05), Vector2(0.20, 0.11), Vector2(-0.27, 0.11), Vector2(-0.30, 0.05)]
	_profile(model, "SlimReceiver", 0.205, receiver_outline_m, Vector3(0.0, 0.015, -0.20), graphite)
	var foreguard_outline_m: PackedVector2Array = [Vector2(-0.30, -0.065), Vector2(0.26, -0.085), Vector2(0.30, -0.05), Vector2(0.30, 0.06), Vector2(0.26, 0.095), Vector2(-0.27, 0.095), Vector2(-0.30, 0.05)]
	_profile(model, "AngularForeguard", 0.225, foreguard_outline_m, Vector3(0.0, 0.015, -0.83), ivory)
	block(model, "LowerRail", Vector3(0.15, 0.028, 0.51), Vector3(0.0, -0.088, -0.83), polymer)
	block(model, "RailSpine", Vector3(0.12, 0.026, 1.05), Vector3(0.0, 0.14, -0.55), graphite)
	block(model.get_node("Slide"), "Bolt", Vector3(0.047, 0.05, 0.19), Vector3(0.096, 0.065, -0.17), steel)
	block(model, "StockBrace", Vector3(0.105, 0.072, 0.29), Vector3(0.0, 0.06, 0.235), graphite)
	var stock_outline_m: PackedVector2Array = [Vector2(-0.16, -0.045), Vector2(0.12, -0.12), Vector2(0.17, -0.09), Vector2(0.17, 0.065), Vector2(0.12, 0.09), Vector2(-0.16, 0.09)]
	_profile(model, "StockHousing", 0.15, stock_outline_m, Vector3(0.0, 0.015, 0.395), ivory)
	block(model, "StockPad", Vector3(0.18, 0.23, 0.048), Vector3(0.0, -0.04, 0.575), polymer)
	var magazine_outline_m: PackedVector2Array = [Vector2(-0.095, -0.19), Vector2(0.10, -0.165), Vector2(0.085, 0.19), Vector2(-0.09, 0.19)]
	_profile(model, "PowerPack", 0.135, magazine_outline_m, Vector3(0.0, -0.28, -0.31), graphite, Vector3(0.12, 0.0, 0.0))
	block(model, "MagazineHeel", Vector3(0.15, 0.026, 0.20), Vector3(0.0, -0.46, -0.34), polymer, Vector3(0.12, 0.0, 0.0))
	barrel(model, "Barrel", 0.045, 0.25, -1.155, graphite)
	muzzle_rim(model, 0.064, 1.28, steel)
	for side_sign in [-1.0, 1.0]:
		block(model, "ReceiverPanel", Vector3(0.011, 0.10, 0.27), Vector3(side_sign * 0.106, 0.012, -0.21), graphite)
		block(model, "CobaltInlay", Vector3(0.008, 0.043, 0.06), Vector3(side_sign * 0.114, 0.033, -0.12), accent)
		for vent_index in 3:
			block(model, "ForeguardSlot", Vector3(0.008, 0.038, 0.085), Vector3(side_sign * 0.114, 0.026, -0.99 + vent_index * 0.14), polymer)
	for rail_index in 6:
		block(model, "RailTooth", Vector3(0.13, 0.019, 0.028), Vector3(0.0, 0.16, -0.91 + rail_index * 0.115), graphite)
	block(model, "FrontSight", Vector3(0.031, 0.065, 0.045), Vector3(0.0, 0.19, -1.03), graphite)
	block(model, "OpticBase", Vector3(0.15, 0.044, 0.12), Vector3(0.0, 0.195, -0.13), graphite)
	for side_sign in [-1.0, 1.0]:
		block(model, "OpticPost", Vector3(0.027, 0.103, 0.045), Vector3(side_sign * 0.055, 0.264, -0.13), graphite)
	block(model, "OpticBridge", Vector3(0.13, 0.024, 0.045), Vector3(0.0, 0.32, -0.13), graphite)
	_trigger_guard(model, polymer)
	build_grip(model, polymer)
	_support_hand(model)


func build_classic() -> void:
	var model := make_model("classic", 0.88)
	var frame := _finish(Color("515a60"), 0.58, 0.46)
	var steel := _finish(Color("bbc0c2"), 0.72, 0.38)
	var grip := _finish(Color("35383a"), 0.0, 0.85)
	var graphite := _finish(Color("363e42"), 0.4, 0.54)
	var frame_outline_m: PackedVector2Array = [Vector2(-0.32, -0.045), Vector2(0.11, -0.065), Vector2(0.32, -0.016), Vector2(0.32, 0.023), Vector2(0.23, 0.065), Vector2(-0.29, 0.065), Vector2(-0.32, 0.025)]
	_profile(model, "Frame", 0.205, frame_outline_m, Vector3(0.0, -0.038, -0.18), frame)
	var moving_slide: Node3D = model.get_node("Slide")
	var slide_outline_m: PackedVector2Array = [Vector2(-0.39, -0.071), Vector2(0.35, -0.071), Vector2(0.39, -0.036), Vector2(0.39, 0.043), Vector2(0.35, 0.09), Vector2(-0.36, 0.09), Vector2(-0.39, 0.043)]
	_profile(moving_slide, "SlideBody", 0.225, slide_outline_m, Vector3(0.0, 0.08, -0.30), steel)
	block(moving_slide, "TopFlat", Vector3(0.11, 0.012, 0.63), Vector3(0.0, 0.173, -0.31), steel)
	block(moving_slide, "BreechPlate", Vector3(0.14, 0.092, 0.018), Vector3(0.0, 0.076, 0.096), graphite)
	barrel(model, "Barrel", 0.052, 0.29, -0.735, frame)
	muzzle_rim(model, 0.06, 0.88, steel)
	for side_sign in [-1.0, 1.0]:
		block(model, "GripPanel", Vector3(0.012, 0.245, 0.125), Vector3(side_sign * 0.074, -0.245, 0.109), grip, Vector3(-0.24, 0.0, 0.0))
		for groove_index in 4:
			block(moving_slide, "SlideSerration", Vector3(0.008, 0.075, 0.008), Vector3(side_sign * 0.115, 0.08, -0.09 + groove_index * 0.028), graphite, Vector3(0.19, 0.0, 0.0))
	block(moving_slide, "EjectionPort", Vector3(0.06, 0.012, 0.115), Vector3(0.045, 0.17, -0.25), graphite)
	_trigger_guard(model, frame)
	_sights(moving_slide, -0.635, 0.025, 0.173, graphite)
	build_grip(model, grip)


func build_flash() -> void:
	flash = Node3D.new()
	flash.name = "MuzzleFlash"
	stage.add_child(flash)
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.emission_enabled = true
	flash_material.emission_energy_multiplier = 0.5
	var cone := CylinderMesh.new()
	cone.top_radius = 0.073
	cone.bottom_radius = 0.0
	cone.height = 0.19
	cone.radial_segments = 6
	add_mesh(flash, "FlashCone", cone, flash_material, Vector3(0.0, 0.0, -0.09), Vector3(PI * 0.5, 0.0, 0.0))
	block(flash, "FlashFin", Vector3(0.15, 0.012, 0.09), Vector3(0.0, 0.0, -0.035), flash_material)
	block(flash, "FlashFinCross", Vector3(0.012, 0.11, 0.09), Vector3(0.0, 0.0, -0.035), flash_material)
	flash.hide()
