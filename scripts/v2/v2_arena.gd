class_name V2Arena
extends Node3D

const EYE_M: Vector3 = Vector3(0.0, 1.6, 0.0)
const VERTICAL_FOV_DEG: float = 70.53280043291679
const TARGET_COLOR: Color = Color("42d9cb")

var camera: Camera3D
var target_nodes: Array[MeshInstance3D] = []
var prepared_identities: Array = []
var visibly_drawn_identities: Array = []
var target_projections: Array = []
var prepared_snapshot: Array = []
var prepared_receipt: Dictionary = {}
var _prepare_sequence: int = 0
var logical_yaw_deg: float = 0.0
var logical_pitch_deg: float = 0.0
var prepared_viewport_size: Vector2i = Vector2i.ZERO
var _target_material: StandardMaterial3D
var _neutral_material: StandardMaterial3D


func _ready() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("18212b")
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.glow_enabled = false
	environment.ssao_enabled = false
	environment.ssr_enabled = false
	world_environment.environment = environment
	add_child(world_environment)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = EYE_M
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = VERTICAL_FOV_DEG
	camera.near = 0.05
	camera.far = 100.0
	add_child(camera)
	camera.make_current()
	_box("Floor", Vector3(80.0, 0.08, 80.0), Vector3(0.0, -0.04, -20.0), Color("202a35"))
	_box("RearWall", Vector3(80.0, 40.0, 0.08), Vector3(0.0, 20.0, -18.04), Color("18212b"))
	_target_material = _material(TARGET_COLOR)
	_neutral_material = _material(Color("77899b"))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	for slot: int in 6:
		var mesh := MeshInstance3D.new()
		mesh.name = "Target" + str(slot)
		mesh.mesh = sphere
		mesh.material_override = _target_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)
		target_nodes.append(mesh)


func _box(node_name: String, dimensions_m: Vector3, center_m: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = dimensions_m
	instance.mesh = box
	instance.material_override = _material(color)
	instance.position = center_m
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	return material


func set_pose(yaw_deg: float, pitch_deg: float) -> void:
	logical_yaw_deg = yaw_deg
	logical_pitch_deg = pitch_deg
	camera.rotation_degrees = Vector3(pitch_deg, -fposmod(yaw_deg + 180.0, 360.0) + 180.0, 0.0)


func prepare(snapshot: Array, logical_sample_s: float = 0.0) -> void:
	prepared_snapshot = snapshot.duplicate(true)
	prepared_identities.clear()
	visibly_drawn_identities.clear()
	target_projections.clear()
	prepared_viewport_size = Vector2i(get_viewport().get_visible_rect().size)
	_prepare_sequence += 1
	prepared_receipt = {"prepare_sequence": _prepare_sequence, "logical_sample_s": logical_sample_s, "camera_yaw_pitch_deg": [logical_yaw_deg, logical_pitch_deg], "vertical_fov_deg": camera.fov, "viewport_px": [prepared_viewport_size.x, prepared_viewport_size.y], "targets": prepared_snapshot.duplicate(true), "ack_source": "RenderingServer.frame_post_draw_not_physical_scanout"}
	for mesh: MeshInstance3D in target_nodes:
		mesh.hide()
	for target_index: int in mini(snapshot.size(), target_nodes.size()):
		var target: Dictionary = snapshot[target_index]
		var pose: Dictionary = target.pose
		var center: Array = pose.center_offset_m
		var mesh: MeshInstance3D = target_nodes[target_index]
		mesh.position = EYE_M + Vector3(float(center[0]), float(center[1]), float(center[2]))
		mesh.scale = Vector3.ONE * float(pose.radius_m)
		mesh.material_override = _neutral_material if bool(target.get("neutral", false)) else _target_material
		mesh.show()
		prepared_identities.append(target.identity)
		var projected: Dictionary = project_sphere(pose, logical_yaw_deg, logical_pitch_deg, float(camera.fov), prepared_viewport_size)
		if bool(projected.get("visible", false)):
			visibly_drawn_identities.append(target.identity)
			projected.identity = target.identity
			projected.hp_remaining = maxf(0.0, float(target.hp_max) - float(target.damage))
			projected.hp_max = target.hp_max
			projected.priority = bool(target.get("priority", false))
			if target.get("expiry_s") != null:
				projected.window_remaining_fraction = clampf((float(target.expiry_s) - logical_sample_s) / (float(target.expiry_s) - float(target.born_s)), 0.0, 1.0)
			target_projections.append(projected)


func set_target_color(color: Color) -> void:
	_target_material.albedo_color = color


static func project_point(offset_m: Array, yaw_deg: float, pitch_deg: float, vertical_fov_deg: float, viewport_size: Vector2i) -> Variant:
	var forward: Array = V2Geometry.direction_deg(yaw_deg, pitch_deg)
	var yaw_rad: float = deg_to_rad(yaw_deg)
	var pitch_rad: float = deg_to_rad(pitch_deg)
	var right: Array = [cos(yaw_rad), 0.0, sin(yaw_rad)]
	var up: Array = [-sin(pitch_rad) * sin(yaw_rad), cos(pitch_rad), sin(pitch_rad) * cos(yaw_rad)]
	var depth_m: float = V2Geometry.dot(forward, offset_m)
	if depth_m <= 0.0 or viewport_size.y <= 0:
		return null
	var focal_px: float = float(viewport_size.y) / (2.0 * tan(deg_to_rad(vertical_fov_deg * 0.5)))
	return Vector2(float(viewport_size.x) * 0.5 + focal_px * V2Geometry.dot(right, offset_m) / depth_m, float(viewport_size.y) * 0.5 - focal_px * V2Geometry.dot(up, offset_m) / depth_m)


static func project_sphere(pose: Dictionary, yaw_deg: float, pitch_deg: float, vertical_fov_deg: float, viewport_size: Vector2i) -> Dictionary:
	var offset: Array = pose.center_offset_m
	var center_px: Variant = project_point(offset, yaw_deg, pitch_deg, vertical_fov_deg, viewport_size)
	if center_px == null:
		return {"visible": false}
	var direction: Array = V2Geometry.normalized(offset)
	var first_basis: Array = V2Geometry.normalized(V2Geometry.cross([0.0, 1.0, 0.0], direction))
	var second_basis: Array = V2Geometry.normalized(V2Geometry.cross(direction, first_basis))
	var sine_radius: float = float(pose.radius_m) / V2Geometry.norm(offset)
	var cosine_radius: float = sqrt(1.0 - sine_radius * sine_radius)
	var contour := PackedVector2Array()
	var bounds := Rect2(center_px, Vector2.ZERO)
	for point_index: int in 128:
		var angle_rad: float = TAU * float(point_index) / 128.0
		var tangent: Array = []
		for axis: int in 3:
			tangent.append(float(direction[axis]) * cosine_radius + (float(first_basis[axis]) * cos(angle_rad) + float(second_basis[axis]) * sin(angle_rad)) * sine_radius)
		var point: Variant = project_point(tangent, yaw_deg, pitch_deg, vertical_fov_deg, viewport_size)
		if point == null:
			return {"visible": false}
		contour.append(point)
		bounds = bounds.expand(point)
	return {"visible": bounds.intersects(Rect2(Vector2.ZERO, Vector2(viewport_size))), "center_px": center_px, "contour_px": contour, "bounds_px": bounds, "radius_px": maxf(bounds.size.x, bounds.size.y) * 0.5, "diameter_deg": pose.diameter_deg}
