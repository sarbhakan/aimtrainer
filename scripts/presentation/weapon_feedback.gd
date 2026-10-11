class_name WeaponFeedback
extends Control

const RECOIL_DURATION_S: float = 0.22
const FLASH_DURATION_S: float = 0.065
const TRACER_DURATION_S: float = 0.045

var definition: WeaponDefinition
var sound_enabled: bool = true
var sound_volume: float = 0.45
var show_sprite: bool = true
var reduced_motion: bool = false
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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for voice_index in 4:
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	continuous_player = AudioStreamPlayer.new()
	add_child(continuous_player)
	set_process(false)


func configure(source: WeaponDefinition, enabled: bool, volume: float, visible_sprite: bool, reduce_motion: bool) -> void:
	stop()
	definition = source
	sound_enabled = enabled
	sound_volume = clampf(volume, 0.0, 1.0)
	show_sprite = visible_sprite
	reduced_motion = reduce_motion
	if definition == null:
		for player in players:
			player.stream = null
		continuous_player.stream = null
		queue_redraw()
		return
	for player in players:
		player.stream = definition.shot_sound
		player.volume_linear = sound_volume
	var loop: AudioStreamWAV = definition.continuous_sound.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	continuous_player.stream = loop
	continuous_player.volume_linear = sound_volume
	queue_redraw()


func set_hud_mode(enabled: bool) -> void:
	hud_mode = enabled
	if not enabled:
		tracer_remaining_s = 0.0
	queue_redraw()


func play_shot() -> void:
	if definition == null or not is_visible_in_tree():
		return
	shot_count += 1
	if sound_enabled and sound_volume > 0.0:
		players[player_index].play()
		player_index = (player_index + 1) % players.size()
	begin_pulse()
	update_processing()
	queue_redraw()


func set_continuous(enabled: bool) -> void:
	if not enabled:
		continuous_active = false
		continuous_player.stop()
		update_processing()
		return
	if definition == null or continuous_active or not is_visible_in_tree():
		return
	continuous_active = true
	pulse_elapsed_s = 0.0
	begin_pulse()
	if sound_enabled and sound_volume > 0.0:
		continuous_player.play()
	update_processing()
	queue_redraw()


func stop() -> void:
	continuous_active = false
	pulse_elapsed_s = 0.0
	flash_remaining_s = 0.0
	recoil_elapsed_s = RECOIL_DURATION_S
	tracer_remaining_s = 0.0
	for player in players:
		player.stop()
	if continuous_player != null:
		continuous_player.stop()
	set_process(false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		stop()


func _process(delta_s: float) -> void:
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


func begin_pulse() -> void:
	if not show_sprite or reduced_motion:
		return
	flash_remaining_s = FLASH_DURATION_S
	recoil_elapsed_s = 0.0
	tracer_remaining_s = TRACER_DURATION_S if hud_mode else 0.0


func update_processing() -> void:
	set_process(show_sprite and not reduced_motion and (recoil_elapsed_s < RECOIL_DURATION_S or flash_remaining_s > 0.0 or tracer_remaining_s > 0.0 or continuous_active))


func sprite_rect() -> Rect2:
	if definition == null or definition.sprite == null:
		return Rect2()
	var aspect := float(definition.sprite.get_width()) / maxf(float(definition.sprite.get_height()), 1.0)
	if hud_mode:
		var width := minf(clampf(size.x * 0.4, 280.0, 720.0), size.y * 0.4 * aspect)
		var dimensions := Vector2(width, width / aspect)
		return Rect2(Vector2(size.x - dimensions.x * 0.94, size.y - dimensions.y), dimensions)
	var dimensions := Vector2(minf(size.x * 0.84, size.y * 0.8 * aspect), minf(size.y * 0.8, size.x * 0.84 / aspect))
	return Rect2(Vector2((size.x - dimensions.x) * 0.5, (size.y - dimensions.y) * 0.5), dimensions)


func sprite_transform() -> Transform2D:
	var rectangle := sprite_rect()
	var weight := pow(maxf(1.0 - recoil_elapsed_s / RECOIL_DURATION_S, 0.0), 2.0) if show_sprite and not reduced_motion else 0.0
	var amplitude := clampf(rectangle.size.x / 460.0, 0.4, 1.35)
	var rotation_rad := deg_to_rad(2.8) * weight
	var zoom := 1.0 + 0.022 * weight
	var pivot := rectangle.size * Vector2(0.72, 0.8)
	var recoil := Vector2(16.0, 14.0) * amplitude * weight
	var transform := Transform2D(rotation_rad, rectangle.position + pivot + recoil - (pivot * zoom).rotated(rotation_rad))
	transform.x *= zoom
	transform.y *= zoom
	return transform


func muzzle_position() -> Vector2:
	return sprite_transform() * (definition.muzzle_uv * sprite_rect().size) if definition != null else Vector2.ZERO


func _draw() -> void:
	if definition == null or not show_sprite:
		return
	var rectangle := sprite_rect()
	var transform := sprite_transform()
	draw_set_transform_matrix(transform)
	draw_texture_rect(definition.sprite, Rect2(Vector2.ZERO, rectangle.size), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var muzzle := transform * (definition.muzzle_uv * rectangle.size)
	if hud_mode and tracer_remaining_s > 0.0 and not reduced_motion:
		var toward_center := size * 0.5 - muzzle
		var distance := toward_center.length()
		if distance > 32.0:
			var travel := 1.0 - tracer_remaining_s / TRACER_DURATION_S
			var start := muzzle + toward_center * (0.06 + travel * 0.62)
			var end := muzzle + toward_center * minf(0.25 + travel * 0.62, 1.0 - 18.0 / distance)
			var tracer_color := definition.flash_color
			tracer_color.a = 0.4 * (1.0 - travel)
			draw_line(start, end, tracer_color, 1.5, true)
	if flash_remaining_s > 0.0 and not reduced_motion:
		var direction := (size * 0.5 - muzzle).normalized() if hud_mode else Vector2(-1.0, -0.44).rotated(transform.get_rotation()).normalized()
		var sideways := direction.orthogonal()
		var intensity := flash_remaining_s / FLASH_DURATION_S
		var flash_size := clampf(rectangle.size.x / 460.0, 0.45, 1.35)
		var color := definition.flash_color
		color.a = 0.75 * intensity
		draw_colored_polygon(PackedVector2Array([muzzle - direction * 3.0 * flash_size, muzzle + sideways * 9.0 * flash_size, muzzle + direction * 34.0 * flash_size, muzzle - sideways * 9.0 * flash_size]), color)
		color.a = 0.2 * intensity
		draw_circle(muzzle + direction * 4.0 * flash_size, 12.0 * flash_size, color)
		draw_circle(muzzle, 3.0 * flash_size, Color(1.0, 0.98, 0.9, intensity))
