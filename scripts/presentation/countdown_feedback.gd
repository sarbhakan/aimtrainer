extends Node

signal cue_played(cue: String)

const SAMPLE_RATE_HZ: int = 24000
const TICK_DURATION_S: float = 0.065
const GO_DURATION_S: float = 0.12

var tick_player: AudioStreamPlayer
var go_player: AudioStreamPlayer
var sound_enabled: bool = true
var sound_volume: float = 0.45
var consumed_ticks: int = 0
var go_consumed: bool = false


func _ready() -> void:
	tick_player = AudioStreamPlayer.new()
	tick_player.name = "CountdownTick"
	tick_player.stream = tone(880.0, TICK_DURATION_S)
	add_child(tick_player)
	go_player = AudioStreamPlayer.new()
	go_player.name = "CountdownGo"
	go_player.stream = tone(1320.0, GO_DURATION_S)
	add_child(go_player)
	configure(sound_enabled, sound_volume)
	set_process(false)
	set_physics_process(false)


func tone(frequency_hz: float, duration_s: float) -> AudioStreamWAV:
	var frame_count := roundi(SAMPLE_RATE_HZ * duration_s)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for frame_index in frame_count:
		var time_s := float(frame_index) / SAMPLE_RATE_HZ
		var attack := minf(time_s / 0.004, 1.0)
		var release := clampf((duration_s - time_s - 1.0 / SAMPLE_RATE_HZ) / 0.018, 0.0, 1.0)
		var sample := sin(TAU * frequency_hz * time_s) * attack * release * exp(-time_s * 12.0) * 0.24
		data.encode_s16(frame_index * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE_HZ
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


func configure(enabled: bool, volume: float) -> void:
	stop()
	sound_enabled = enabled
	sound_volume = clampf(volume, 0.0, 1.0) if is_finite(volume) else 0.0
	if tick_player != null:
		tick_player.volume_linear = sound_volume
		go_player.volume_linear = sound_volume


func reset_sequence() -> void:
	stop()
	consumed_ticks = 0
	go_consumed = false


func play_tick(text: String, available: bool) -> void:
	if text not in ["3", "2", "1"]:
		return
	var tick_mask := 1 << (int(text) - 1)
	if consumed_ticks & tick_mask:
		return
	consumed_ticks |= tick_mask
	if not can_play(available):
		return
	tick_player.play()
	cue_played.emit(text)


func play_go(available: bool) -> void:
	if go_consumed:
		return
	go_consumed = true
	if not can_play(available):
		return
	tick_player.stop()
	go_player.play()
	cue_played.emit("GO")


func can_play(available: bool) -> bool:
	return available and is_inside_tree() and is_node_ready() and not get_tree().paused and sound_enabled and sound_volume > 0.0


func stop() -> void:
	if tick_player != null:
		tick_player.stop()
	if go_player != null:
		go_player.stop()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
		stop()
