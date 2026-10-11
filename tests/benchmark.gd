extends SceneTree

const CameraScript = preload("res://scripts/input/aim_camera.gd")
const EngineScript = preload("res://scripts/training/scenario_engine.gd")
const PoolScript = preload("res://scripts/training/target_pool.gd")


func _initialize() -> void:
	benchmark.call_deferred()


func benchmark() -> void:
	var camera := CameraScript.new()
	root.add_child(camera)
	var engine := EngineScript.new()
	engine.start(ScenarioCatalog.find("T05"), 42, 30.0)
	var pool := PoolScript.new()
	root.add_child(pool)
	var event_count: int = 200000
	var started_us := Time.get_ticks_usec()
	var max_buffer_count: int = 0
	for event_index in event_count:
		var time_s := event_index / 8000.0
		camera.apply_mouse_counts(Vector2(1, 0.25))
		engine.record_aim(time_s, camera.yaw_deg, camera.pitch_deg)
		max_buffer_count = maxi(max_buffer_count, engine.timeline.count)
		if event_index % 133 == 0:
			engine.record_frame(133.0 / 8000.0)
			engine.advance_to(time_s)
			pool.sync(engine, time_s)
	var elapsed_us := Time.get_ticks_usec() - started_us
	print("BENCH SYNTHÉTIQUE headless : %d événements caméra+timeline, %.2f ms, %.3f µs/événement, tampon max %d/%d, %d nœuds cibles." % [event_count, elapsed_us / 1000.0, float(elapsed_us) / event_count, max_buffer_count, AimTimeline.CAPACITY, pool.get_child_count()])
	print("Ce test de débit logiciel ne mesure ni polling matériel, ni latence, ni rendu Windows.")
	var passed: bool = engine.invalid_reason.is_empty() and engine.timeline.overflow_count == 0 and pool.get_child_count() == 6 and engine.timeline.event_count == event_count
	camera.queue_free()
	pool.queue_free()
	await process_frame
	quit(0 if passed else 1)
