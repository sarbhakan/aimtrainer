extends SceneTree

var failures: int = 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	smoke.call_deferred()


func smoke() -> void:
	var scene := load("res://scenes/app/Main.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var app := scene.instantiate()
	app.store = LocalStore.new("user://tests/export-" + LocalStore.new().identifier())
	root.add_child(app)
	await process_frame
	if ResourceLoader.exists("res://tests/run_tests.gd") or ResourceLoader.exists("res://tests/domain_tests.gd"):
		failures += 1
	for definition in ScenarioCatalog.DEFINITIONS:
		app.start_practice(definition.scenario_id, 1.0)
		app.begin_training(Time.get_ticks_usec())
		app.engine.record_aim(0.01, 1, 0)
		app.engine.record_frame(0.01)
		if definition.family != "tracking":
			app.engine.shoot(0.1, app.engine.target_direction(0, 0.1))
		app.clock.accumulated_us = 1000000
		app.finish_training(true)
		if not app.last_report.completed or not app.last_report.valid or app.last_report.scenario_id != definition.scenario_id:
			failures += 1
		app.return_to_menu()
	if app.store.sessions().size() != 16:
		failures += 1
	app.queue_free()
	await process_frame
	print("EXPORT SMOKE : 16 exercices embarqués, %d échecs." % failures)
	quit(0 if failures == 0 else 1)
