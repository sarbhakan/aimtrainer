class_name V2Preview
extends Control

var arena: V2Arena
var viewport: SubViewport
var engine := V2SessionEngine.new()
var paused: bool = false
var active: bool = false
var preview_elapsed_s: float = 0.0
var _last_bot_action_s: float = 0.0
var _seed_hex: String = ""
var _program: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	arena = V2Arena.new()
	viewport.add_child(arena)
	var texture := TextureRect.new()
	texture.texture = viewport.get_texture()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(texture)
	RenderingServer.frame_post_draw.connect(_post_draw)
	set_process(false)


func start(program: Dictionary, vertical_fov_deg: float = V2Arena.VERTICAL_FOV_DEG, target_color: Color = V2Arena.TARGET_COLOR) -> void:
	_program = program.duplicate(true)
	_seed_hex = Crypto.new().generate_random_bytes(16).hex_encode()
	arena.camera.fov = vertical_fov_deg
	arena.set_target_color(target_color)
	engine.start(_program, _seed_hex, {"vertical_fov_deg": vertical_fov_deg})
	preview_elapsed_s = 0.0
	_last_bot_action_s = 0.0
	active = true
	paused = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	arena.prepare(engine.snapshot())


func stop() -> void:
	active = false
	set_process(false)
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta_s: float) -> void:
	if paused or not active:
		return
	preview_elapsed_s += delta_s
	var snapshot: Array = engine.snapshot()
	if not snapshot.is_empty() and preview_elapsed_s - _last_bot_action_s >= 0.8:
		var pose: Dictionary = snapshot[0].pose
		engine.queue_pose(preview_elapsed_s, float(pose.yaw_deg), float(pose.pitch_deg))
		engine.queue_fire(preview_elapsed_s, false)
		engine.queue_fire(preview_elapsed_s, true)
		_last_bot_action_s = preview_elapsed_s
	engine.advance(preview_elapsed_s)
	if engine.completed:
		engine.start(_program, _seed_hex, {"vertical_fov_deg": arena.camera.fov})
		preview_elapsed_s = 0.0
		_last_bot_action_s = 0.0
	arena.prepare(engine.snapshot())


func _post_draw() -> void:
	if active and not paused and is_visible_in_tree():
		engine.mark_rendered(arena.prepared_identities, arena.visibly_drawn_identities, preview_elapsed_s)
