class_name WeaponFeedback
extends Control

signal stopped

const ViewmodelScript := preload("res://scripts/presentation/weapon_viewmodel.gd")
const RECOIL_DURATION_S: float = 0.22
const FLASH_DURATION_S: float = 0.065
const TRACER_DURATION_S: float = 0.045

var definition: WeaponDefinition
var sound_enabled: bool = true
var sound_volume: float = 0.45
var show_sprite: bool = true:
	set(value):
		show_sprite = value
		if not value:
			clear_visuals()
		update_processing()
		update_viewmodel()
var reduced_motion: bool = false:
	set(value):
		reduced_motion = value
		if value:
			clear_visuals()
		update_processing()
		update_viewmodel()
var continuous_active: bool = false
var pulse_elapsed_s: float = 0.0
var flash_remaining_s: float = 0.0
var recoil_elapsed_s: float = RECOIL_DURATION_S
var tracer_remaining_s: float = 0.0
var hud_mode: bool = false
var shot_count: int = 0
var players: Array[AudioStreamPlayer] = []
var player_index: int = 0
var continuous_player: AudioStreamPlayer
var window_has_focus: bool = true
var crosshair_clearance_px: float = 18.0:
	set(value):
		crosshair_clearance_px = maxf(value, 0.0) if is_finite(value) else 18.0
		sync_layout()
var viewmodel: ViewmodelScript


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for voice_index in 4:
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	continuous_player = AudioStreamPlayer.new()
	add_child(continuous_player)
	viewmodel = ViewmodelScript.new()
	viewmodel.name = "WeaponViewmodel"
	add_child(viewmodel, false, Node.INTERNAL_MODE_BACK)
	resized.connect(sync_layout)
	set_process(false)
	configure(definition, sound_enabled, sound_volume, show_sprite, reduced_motion)
	update_viewmodel.call_deferred()


func configure(source: WeaponDefinition, enabled: bool, volume: float, visible_sprite: bool, reduce_motion: bool) -> void:
	stop()
	definition = source
	sound_enabled = enabled
	sound_volume = clampf(volume, 0.0, 1.0)
	show_sprite = visible_sprite
	reduced_motion = reduce_motion
	if viewmodel == null:
		return
	if definition == null:
		for player in players:
			player.stream = null
		continuous_player.stream = null
		viewmodel.set_render_state(false, false)
		queue_redraw()
		return
	for player in players:
		player.stream = definition.shot_sound
		player.volume_linear = sound_volume
	if definition.continuous_sound != null:
		var loop: AudioStreamWAV = definition.continuous_sound.duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
		continuous_player.stream = loop
	else:
		continuous_player.stream = null
	continuous_player.volume_linear = sound_volume
	viewmodel.set_profile(definition.weapon_id, definition.flash_color)
	sync_layout()
	queue_redraw()


func set_hud_mode(enabled: bool) -> void:
	hud_mode = enabled
	if not enabled:
		tracer_remaining_s = 0.0
	sync_layout()
	queue_redraw()


func play_shot() -> void:
	if definition == null or not feedback_available():
		return
	shot_count += 1
	if sound_enabled and sound_volume > 0.0:
		players[player_index].play()
		player_index = (player_index + 1) % players.size()
	begin_pulse()
	update_processing()
	update_viewmodel()
	queue_redraw()


func set_continuous(enabled: bool) -> void:
	if not enabled:
		continuous_active = false
		if continuous_player != null:
			continuous_player.stop()
		update_processing()
		update_viewmodel()
		return
	if definition == null or continuous_active or not feedback_available():
		return
	continuous_active = true
	pulse_elapsed_s = 0.0
	begin_pulse()
	if sound_enabled and sound_volume > 0.0:
		continuous_player.play()
	update_processing()
	update_viewmodel()
	queue_redraw()


func stop() -> void:
	continuous_active = false
	pulse_elapsed_s = 0.0
	clear_visuals()
	for player in players:
		player.stop()
	if continuous_player != null:
		continuous_player.stop()
	set_process(false)
	update_viewmodel()
	queue_redraw()
	stopped.emit()


func clear_visuals() -> void:
	flash_remaining_s = 0.0
	recoil_elapsed_s = RECOIL_DURATION_S
	tracer_remaining_s = 0.0
	queue_redraw()


func feedback_available() -> bool:
	return is_node_ready() and is_visible_in_tree() and window_has_focus and not get_tree().paused


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		window_has_focus = false
		stop()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		window_has_focus = true
		update_viewmodel()
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		stop()
	elif what == NOTIFICATION_UNPAUSED or what == NOTIFICATION_VISIBILITY_CHANGED:
		update_viewmodel()


func _process(delta_s: float) -> void:
	if not feedback_available():
		stop()
		return
	var elapsed_s := maxf(delta_s, 0.0)
	if continuous_active:
		pulse_elapsed_s += elapsed_s
		if pulse_elapsed_s >= definition.continuous_interval_s:
			pulse_elapsed_s = fmod(pulse_elapsed_s, definition.continuous_interval_s)
			begin_pulse()
			elapsed_s = pulse_elapsed_s
	flash_remaining_s = maxf(flash_remaining_s - elapsed_s, 0.0)
	tracer_remaining_s = maxf(tracer_remaining_s - elapsed_s, 0.0)
	recoil_elapsed_s = minf(recoil_elapsed_s + elapsed_s, RECOIL_DURATION_S)
	queue_redraw()
	update_processing()
	update_viewmodel()


func begin_pulse() -> void:
	if not show_sprite or reduced_motion:
		return
	flash_remaining_s = FLASH_DURATION_S
	recoil_elapsed_s = 0.0
	tracer_remaining_s = TRACER_DURATION_S if hud_mode else 0.0


func update_processing() -> void:
	set_process(feedback_available() and show_sprite and not reduced_motion and (recoil_elapsed_s < RECOIL_DURATION_S or flash_remaining_s > 0.0 or tracer_remaining_s > 0.0 or continuous_active))


func sync_layout() -> void:
	if viewmodel == null or not viewmodel.is_node_ready():
		return
	viewmodel.set_layout(size, hud_mode, crosshair_clearance_px)
	update_viewmodel()


func update_viewmodel() -> void:
	if viewmodel == null or not viewmodel.is_node_ready():
		return
	var available := definition != null and show_sprite and feedback_available()
	viewmodel.set_render_state(available, is_processing())
	if viewmodel.is_inside_tree():
		var weight := pow(maxf(1.0 - recoil_elapsed_s / RECOIL_DURATION_S, 0.0), 2.0) if show_sprite and not reduced_motion else 0.0
		viewmodel.apply_pose(weight, flash_remaining_s / FLASH_DURATION_S if viewmodel.rendering_enabled and not reduced_motion else 0.0)


func sprite_rect() -> Rect2:
	return viewmodel.region_px if viewmodel != null and definition != null else Rect2()


func sprite_transform() -> Transform2D:
	return Transform2D(0.0, sprite_rect().position)


func muzzle_position() -> Vector2:
	return viewmodel.muzzle_position_px() if viewmodel != null and definition != null else Vector2.ZERO


func tracer_segment() -> PackedVector2Array:
	if definition == null or not show_sprite or reduced_motion or not hud_mode or tracer_remaining_s <= 0.0:
		return PackedVector2Array()
	var muzzle_px := muzzle_position()
	var toward_center := size * 0.5 - muzzle_px
	var distance_px := toward_center.length()
	var clearance_px := maxf(crosshair_clearance_px + 2.0, 32.0)
	if distance_px <= clearance_px:
		return PackedVector2Array()
	var travel := clampf(1.0 - tracer_remaining_s / TRACER_DURATION_S, 0.0, 1.0)
	var start_fraction := 0.02 + travel * 0.62
	var end_fraction := minf(0.21 + travel * 0.62, 1.0 - clearance_px / distance_px)
	if end_fraction <= start_fraction:
		return PackedVector2Array()
	return PackedVector2Array([muzzle_px + toward_center * start_fraction, muzzle_px + toward_center * end_fraction])


func _draw() -> void:
	var segment := tracer_segment()
	if segment.size() == 2:
		var tracer_color := definition.flash_color
		tracer_color.a = 0.3 * tracer_remaining_s / TRACER_DURATION_S
		draw_line(segment[0], segment[1], tracer_color, 1.3, true)
