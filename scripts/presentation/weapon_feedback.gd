class_name WeaponFeedback
extends Control

var definition: WeaponDefinition
var sound_enabled: bool = true
var sound_volume: float = 0.45
var show_sprite: bool = true
var reduced_motion: bool = false
var continuous_active: bool = false
var pulse_elapsed_s: float = 0.0
var flash_remaining_s: float = 0.0
var shot_count: int = 0
var players: Array[AudioStreamPlayer] = []
var player_index: int = 0
var continuous_player: AudioStreamPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func play_shot() -> void:
	if definition == null or not is_visible_in_tree():
		return
	shot_count += 1
	if sound_enabled and sound_volume > 0.0:
		players[player_index].play()
		player_index = (player_index + 1) % players.size()
	flash_remaining_s = 0.07 if show_sprite and not reduced_motion else 0.0
	set_process(flash_remaining_s > 0.0 or continuous_active)
	queue_redraw()


func set_continuous(enabled: bool) -> void:
	if not enabled:
		continuous_active = false
		continuous_player.stop()
		set_process(flash_remaining_s > 0.0)
		return
	if definition == null or continuous_active or not is_visible_in_tree():
		return
	continuous_active = true
	pulse_elapsed_s = 0.0
	flash_remaining_s = 0.07 if show_sprite and not reduced_motion else 0.0
	if sound_enabled and sound_volume > 0.0:
		continuous_player.play()
	set_process(show_sprite and not reduced_motion)
	queue_redraw()


func stop() -> void:
	continuous_active = false
	flash_remaining_s = 0.0
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
	flash_remaining_s = maxf(flash_remaining_s - delta_s, 0.0)
	if continuous_active:
		pulse_elapsed_s += delta_s
		if pulse_elapsed_s >= definition.continuous_interval_s:
			pulse_elapsed_s = fmod(pulse_elapsed_s, definition.continuous_interval_s)
			flash_remaining_s = 0.04
	queue_redraw()
	if flash_remaining_s <= 0.0 and not continuous_active:
		set_process(false)


func _draw() -> void:
	if definition == null or not show_sprite:
		return
	var recoil_px := flash_remaining_s * 45.0
	var sprite_size := Vector2(minf(size.x, size.y * 1.8), minf(size.y, size.x / 1.8))
	var origin := Vector2(size.x - sprite_size.x, size.y - sprite_size.y + recoil_px)
	draw_texture_rect(definition.sprite, Rect2(origin, sprite_size), false)
	if flash_remaining_s > 0.0 and not reduced_motion:
		var muzzle := origin + definition.muzzle_uv * sprite_size
		var color := definition.flash_color
		color.a = minf(flash_remaining_s * 9.0, 0.65)
		draw_circle(muzzle, 8.0, color)
		draw_line(muzzle - Vector2(13, 6), muzzle + Vector2(13, 6), color, 2.0, true)
		draw_line(muzzle - Vector2(4, 11), muzzle + Vector2(4, 11), color, 2.0, true)
