extends SceneTree

var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(1))
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("V2 EXPORT: " + description)


func _ack(engine: V2SessionEngine) -> void:
	var identities: Array = []
	for target: Dictionary in engine.snapshot():
		identities.append(target.identity)
	engine.mark_rendered(identities, identities, engine.elapsed_s)


func _run() -> void:
	_check(ProjectSettings.get_setting("application/config/version") == "1.0.0", "current product version")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/app/MainV2.tscn", "native V2 public entry point")
	_check(not DirAccess.dir_exists_absolute("res://docs") and not DirAccess.dir_exists_absolute("res://tests") and not DirAccess.dir_exists_absolute("res://tools"), "development files excluded")
	for path: String in ["res://assets/fonts/v2/DejaVuSans.ttf", "res://assets/fonts/v2/DejaVuSans-Bold.ttf", "res://scripts/v2/v2_calibration_runner.gd", "res://scripts/v2/v2_calibration_task.gd"]:
		_check(ResourceLoader.exists(path), "native resource embedded " + path)
	var scene: PackedScene = load("res://scenes/app/MainV2.tscn")
	var app: Node = scene.instantiate()
	app.store = V2Store.new("user://tests/export_v2_" + Crypto.new().generate_random_bytes(16).hex_encode())
	root.add_child(app)
	await process_frame
	_check(app.profile.gain_hex == V2Canonical.float64_hex(914.4 / (800.0 * 35.0)), "exact baseline after isolated startup")
	_check(app.calibration != null and app.calibration.has_method("prepare_express") and app.calibration.has_method("prepare_confirmation"), "native CAL runner initialized by the exported public controller")
	_check(app.shell != null and app.arena != null and app.hud != null, "native V2 interface and arena initialized from the exported public scene")
	var catalogue: Dictionary = V2Catalog.load_catalog()
	_check(not catalogue.is_empty() and catalogue.programs.size() == 24, "all 24 validated configurations embedded")
	var phase_count: int = 0
	for definition: Dictionary in catalogue.get("programs", []):
		var engine := V2SessionEngine.new()
		_check(engine.start(definition, "00000000000000000000000000000042"), "start exported configuration " + definition.program_id + "/" + definition.difficulty)
		for phase: Dictionary in definition.phases:
			phase_count += 1
			engine.advance(float(phase.start_s))
			if phase.mechanic == "opportunity":
				for opportunity: Dictionary in engine._scheduled:
					engine.advance(float(opportunity.born_s))
					_ack(engine)
			else:
				_ack(engine)
		engine.advance(60.0)
		_check(engine.completed and engine.invalid_reason.is_empty(), "exported phase lifecycle complete")
		_check(engine.report().phases.size() == definition.phases.size(), "all exported phase scores")
	_check(phase_count == 54, "exactly 54 native phases")
	_check(V2CalibrationService.protocol_hash() == V2CalibrationService.PROTOCOL_SHA256, "embedded protocol semantic hash")
	var baseline: Dictionary = V2CalibrationService.make_gain("A", 35.0, 800.0)
	var grid: Dictionary = V2CalibrationService.candidate_grid(baseline)
	_check(bool(grid.ok) and grid.gains.size() == 3, "native actual-gain grid")
	for task: String in V2CalibrationService.TASKS:
		var deck: Dictionary = V2CalibrationService.make_deck("00000000000000000000000000000042", "express", "0", "0", "0", task)
		_check(deck.has("manifest_sha256") and not deck.has("error"), "native CAL deck " + task)
		var task_engine: RefCounted = load("res://scripts/v2/v2_calibration_task.gd").new()
		_check(task_engine.start(deck), "native CAL task engine " + task)
	app.return_to_menu(false)
	root.remove_child(app)
	app.free()
	print("V2 EXPORT : %d assertions, %d échecs; 24 configurations, 54 phases, 4 tâches CAL." % [assertions, failures])
	quit(0 if failures == 0 else 1)
