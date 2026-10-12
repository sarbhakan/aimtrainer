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
	environment.ambient_light_color = Color("b9cddd")
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	add_light(Vector3(-0.65, -0.55, -0.2), Color("e4f3ff"), 1.15)
	add_light(Vector3(0.2, 2.4, 0.3), Color("90b7ca"), 0.6)
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
	light.rotation = rotation_rad
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = false
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
	var key := "%s/%s/%s" % [color.to_html(), metallic, emission]
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.46 if metallic > 0.0 else 0.8
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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	meshes.append(instance)
	return instance


func block(parent: Node3D, label: String, dimensions_m: Vector3, origin_m: Vector3, surface: Material, rotation_rad: Vector3 = Vector3.ZERO) -> void:
	add_mesh(parent, label, chamfered_box(dimensions_m), surface, origin_m, rotation_rad)


func chamfered_box(dimensions_m: Vector3) -> ArrayMesh:
	var half_m := dimensions_m * 0.5
	var bevel_m := minf(0.025, minf(half_m.x, minf(half_m.y, half_m.z)) * 0.28)
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
	mesh.radial_segments = 12
	add_mesh(parent, label, mesh, surface, Vector3(0.0, 0.0, depth_m), Vector3(PI * 0.5, 0.0, 0.0))


func muzzle_rim(parent: Node3D, radius_m: float, depth_m: float, surface: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius_m * 0.70
	mesh.outer_radius = radius_m
	mesh.rings = 12
	mesh.ring_segments = 6
	add_mesh(parent, "MuzzleRim", mesh, surface, Vector3(0.0, 0.0, -depth_m), Vector3(PI * 0.5, 0.0, 0.0))
	barrel(parent, "RecessedBore", radius_m * 0.70, 0.008, -depth_m + 0.014, material(Color("080e16")))


func build_grip(parent: Node3D, surface: Material) -> void:
	block(parent, "Grip", Vector3(0.16, 0.33, 0.23), Vector3(0.0, -0.22, 0.14), surface, Vector3(-0.18, 0.0, 0.0))
	var glove := material(Color("25303d"))
	block(parent, "GlovedPalm", Vector3(0.22, 0.22, 0.20), Vector3(0.035, -0.23, 0.23), glove)
	for finger_index in 3:
		block(parent, "Finger%d" % finger_index, Vector3(0.19, 0.049, 0.09), Vector3(0.015, -0.16 - finger_index * 0.056, 0.015), glove)
	block(parent, "Thumb", Vector3(0.07, 0.14, 0.13), Vector3(0.125, -0.16, 0.16), glove, Vector3(0.0, 0.0, -0.28))
	block(parent, "Cuff", Vector3(0.24, 0.17, 0.16), Vector3(0.055, -0.39, 0.28), material(Color("435466")))
	block(parent, "Sleeve", Vector3(0.25, 0.23, 0.56), Vector3(0.095, -0.46, 0.58), material(Color("1c2839")), Vector3(0.22, -0.08, 0.0))


func build_pulse() -> void:
	var model := make_model("pulse", 1.14)
	var armor := material(Color("345266"), 0.45)
	var dark := material(Color("192b38"), 0.35)
	var steel := material(Color("9aafb7"), 0.65)
	var accent := material(Color("5fe0cb"), 0.3, 0.35)
	block(model, "Receiver", Vector3(0.30, 0.29, 0.94), Vector3(0.0, 0.06, -0.35), armor)
	block(model, "RearHousing", Vector3(0.33, 0.25, 0.29), Vector3(0.0, 0.035, 0.27), dark)
	block(model.get_node("Slide"), "ChargingShroud", Vector3(0.25, 0.095, 0.54), Vector3(0.0, 0.225, -0.35), steel)
	block(model, "LowerSpine", Vector3(0.22, 0.13, 0.80), Vector3(0.0, -0.135, -0.36), dark)
	barrel(model, "OctagonalBarrel", 0.072, 0.34, -0.96, dark)
	for ring_index in 3:
		barrel(model, "InductionCollar%d" % ring_index, 0.105, 0.045, -0.78 - ring_index * 0.1, steel)
	muzzle_rim(model, 0.082, 1.14, steel)
	for side_sign in [-1.0, 1.0]:
		block(model, "SideArmor", Vector3(0.045, 0.21, 0.57), Vector3(side_sign * 0.164, 0.045, -0.34), dark)
		block(model, "EnergyChannel", Vector3(0.008, 0.019, 0.43), Vector3(side_sign * 0.189, 0.075, -0.4), accent)
		block(model, "RearIndicator", Vector3(0.012, 0.045, 0.06), Vector3(side_sign * 0.175, 0.11, 0.19), accent)
		for vent_index in 4:
			block(model, "HeatVent", Vector3(0.012, 0.065, 0.028), Vector3(side_sign * 0.19, -0.015, -0.48 + vent_index * 0.09), steel, Vector3(0.23, 0.0, 0.0))
	block(model, "FrontSight", Vector3(0.065, 0.055, 0.05), Vector3(0.0, 0.26, -0.7), dark)
	block(model, "RearSight", Vector3(0.095, 0.055, 0.055), Vector3(0.0, 0.27, -0.03), dark)
	build_grip(model, dark)


func build_vector() -> void:
	var model := make_model("vector", 1.28)
	var dark := material(Color("252b46"), 0.35)
	var armor := material(Color("647087"), 0.55)
	var steel := material(Color("b5c5d1"), 0.65)
	var accent := material(Color("afa0f2"), 0.3, 0.28)
	block(model, "SlimReceiver", Vector3(0.21, 0.22, 0.81), Vector3(0.0, 0.07, -0.27), dark)
	block(model, "AngularForeguard", Vector3(0.26, 0.21, 0.53), Vector3(0.0, 0.025, -0.82), armor, Vector3(0.07, 0.0, 0.0))
	block(model, "RailSpine", Vector3(0.12, 0.055, 1.02), Vector3(0.0, 0.205, -0.55), steel)
	block(model.get_node("Slide"), "Bolt", Vector3(0.23, 0.06, 0.30), Vector3(0.0, 0.155, -0.12), armor)
	block(model, "StockBrace", Vector3(0.14, 0.095, 0.4), Vector3(0.0, 0.075, 0.35), armor, Vector3(-0.13, 0.0, 0.0))
	block(model, "StockPad", Vector3(0.20, 0.27, 0.09), Vector3(0.0, -0.015, 0.55), dark)
	block(model, "PowerPack", Vector3(0.15, 0.32, 0.22), Vector3(0.0, -0.22, -0.26), dark, Vector3(0.18, 0.0, 0.0))
	barrel(model, "Barrel", 0.055, 0.25, -1.155, dark)
	muzzle_rim(model, 0.064, 1.28, steel)
	for side_sign in [-1.0, 1.0]:
		block(model, "ReceiverPanel", Vector3(0.022, 0.115, 0.42), Vector3(side_sign * 0.116, 0.065, -0.24), armor)
		block(model, "StatusStrip", Vector3(0.009, 0.015, 0.24), Vector3(side_sign * 0.132, 0.095, -0.22), accent)
		for vent_index in 5:
			block(model, "ForeguardSlot", Vector3(0.009, 0.085, 0.023), Vector3(side_sign * 0.133, 0.035, -0.95 + vent_index * 0.07), dark, Vector3(-0.28, 0.0, 0.0))
	for rail_index in 6:
		block(model, "RailTooth", Vector3(0.14, 0.025, 0.035), Vector3(0.0, 0.24, -0.89 + rail_index * 0.12), dark)
	block(model, "FrontSight", Vector3(0.04, 0.04, 0.035), Vector3(0.0, 0.275, -0.95), dark)
	build_grip(model, dark)


func build_classic() -> void:
	var model := make_model("classic", 0.88)
	var frame := material(Color("444855"), 0.5)
	var steel := material(Color("b9b4a7"), 0.7)
	var grip := material(Color("634b3f"))
	var accent := material(Color("edbd75"), 0.45, 0.15)
	block(model, "Frame", Vector3(0.21, 0.16, 0.63), Vector3(0.0, -0.05, -0.21), frame)
	var moving_slide: Node3D = model.get_node("Slide")
	block(moving_slide, "SlideBody", Vector3(0.23, 0.18, 0.75), Vector3(0.0, 0.11, -0.27), steel)
	block(moving_slide, "TopFlat", Vector3(0.12, 0.025, 0.63), Vector3(0.0, 0.215, -0.28), frame)
	barrel(model, "Barrel", 0.060, 0.22, -0.77, frame)
	muzzle_rim(model, 0.07, 0.88, steel)
	block(model, "TriggerGuardBase", Vector3(0.16, 0.035, 0.30), Vector3(0.0, -0.18, -0.08), frame)
	block(model, "TriggerGuardFront", Vector3(0.16, 0.115, 0.035), Vector3(0.0, -0.125, -0.225), frame)
	for side_sign in [-1.0, 1.0]:
		block(model, "GripPanel", Vector3(0.024, 0.24, 0.15), Vector3(side_sign * 0.085, -0.22, 0.13), grip, Vector3(-0.18, 0.0, 0.0))
		block(moving_slide, "SlideInlay", Vector3(0.008, 0.02, 0.26), Vector3(side_sign * 0.119, 0.11, -0.4), accent)
		for groove_index in 5:
			block(moving_slide, "SlideSerration", Vector3(0.009, 0.085, 0.012), Vector3(side_sign * 0.12, 0.105, -0.07 + groove_index * 0.025), frame, Vector3(0.2, 0.0, 0.0))
	block(moving_slide, "FrontSight", Vector3(0.035, 0.035, 0.045), Vector3(0.0, 0.245, -0.58), frame)
	block(moving_slide, "RearSight", Vector3(0.09, 0.035, 0.045), Vector3(0.0, 0.245, 0.04), frame)
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
