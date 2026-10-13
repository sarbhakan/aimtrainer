extends SceneTree

var assertions: int = 0
var failures: int = 0
var catalogue: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("V2 RUNTIME: " + description)


func _definition(program_id: String, difficulty: String = "standard") -> Dictionary:
	for definition: Dictionary in catalogue.programs:
		if definition.program_id == program_id and definition.difficulty == difficulty:
			return definition
	return {}


func _ack(engine: V2SessionEngine) -> void:
	var identities: Array = []
	for target: Dictionary in engine.snapshot():
		identities.append(target.identity)
	engine.mark_rendered(identities, identities, engine.elapsed_s)


func _click(engine: V2SessionEngine, target: Dictionary, time_s: float) -> void:
	var pose: Dictionary = V2Spawner.sample_target(target, time_s)
	engine.queue_pose(time_s, float(pose.yaw_deg), float(pose.pitch_deg))
	engine.queue_fire(time_s, false)
	engine.queue_fire(time_s, true)
	engine.advance(time_s)


func _run() -> void:
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://content/v2/catalogue.v2.json"))
	for definition: Dictionary in catalogue.programs:
		var engine := V2SessionEngine.new()
		_check(engine.start(definition, "0000000000000000000000000000002a"), "start " + definition.program_id + "/" + definition.difficulty)
		for phase: Dictionary in definition.phases:
			engine.advance(float(phase.start_s))
			if phase.mechanic == "opportunity":
				for opportunity: Dictionary in engine._scheduled:
					engine.advance(float(opportunity.born_s))
					_ack(engine)
			else:
				_ack(engine)
			for target: Dictionary in engine.targets.values():
				var pose: Dictionary = V2Spawner.sample_target(target, engine.elapsed_s)
				_check(float(pose.radius_m) > 0.0, "positive sphere")
				_check(V2Geometry.sphere_fits(pose.direction, float(pose.diameter_deg), V2Arena.VERTICAL_FOV_DEG, 16.0 / 9.0), "initial silhouette fits")
		engine.advance(60.0)
		_check(engine.completed and engine.invalid_reason.is_empty(), "complete all phases " + definition.program_id + "/" + definition.difficulty + " " + engine.invalid_reason)
		var report: Dictionary = engine.report()
		_check(report.phases.size() == definition.phases.size(), "all phase reports")
		_check((report.program_score != null) == bool(definition.aggregate.ranked_program_score), "program aggregate policy")
		for phase_report: Dictionary in report.phases:
			_check(float(phase_report.metrics.contact_upper_s) - float(phase_report.metrics.contact_lower_s) <= 0.0005 * float(phase_report.duration_s) + 1e-9, "contact width contract")
	var click_engine := V2SessionEngine.new()
	click_engine.start(_definition("EX02"), "00000000000000000000000000000042")
	var first: Dictionary = click_engine.targets[0]
	_click(click_engine, first, 0.0)
	_check(int(click_engine.metrics.hits) == 0 and int(click_engine.metrics.shots) == 1, "unrendered target not hittable, press counted")
	_ack(click_engine)
	var neighbor: Dictionary = click_engine.targets[1].duplicate(true)
	_click(click_engine, first, 0.01)
	_check(int(click_engine.metrics.hits) == 1, "rendered target hit")
	_check(click_engine.targets[1] == neighbor, "replacement preserves neighbor exactly")
	_check(int(click_engine.targets[0].generation) == 1 and click_engine.targets[0].grid_node != first.grid_node, "generation and free node replacement")
	_click(click_engine, click_engine.targets[0], 0.02)
	_check(int(click_engine.metrics.hits) == 1, "replacement needs its own frame")
	_ack(click_engine)
	_click(click_engine, click_engine.targets[0], 0.03)
	_check(int(click_engine.metrics.hits) == 2, "replacement eligible after own frame")
	click_engine.advance(20.0)
	_check(click_engine.phase.id == "precision" and click_engine.targets.size() == 6, "exact boundary routed to new phase")
	_check(int(click_engine.phases[0].metrics.shots) == 4, "all presses retained in old phase")
	var window_engine := V2SessionEngine.new()
	window_engine.start(_definition("EX03"), "00000000000000000000000000000042")
	var scheduled: Dictionary = window_engine._scheduled[0]
	window_engine.advance(float(scheduled.born_s))
	_ack(window_engine)
	var identity: String = window_engine.targets[0].identity
	window_engine.queue_fire(window_engine.elapsed_s + 0.01, true)
	window_engine.advance(window_engine.elapsed_s + 0.01)
	_check(window_engine.targets[0].identity == identity, "miss does not reset slot")
	var deadline_s: float = float(scheduled.expiry_s)
	var before: Dictionary = window_engine.targets[0].duplicate(true)
	_click(window_engine, before, deadline_s)
	_check(window_engine.targets.is_empty() and int(window_engine.metrics.hits) == 0 and int(window_engine.metrics.expired) == 1, "deadline exclusive one expiry")
	var switch_engine := V2SessionEngine.new()
	switch_engine.start(_definition("EX08"), "00000000000000000000000000000042")
	_ack(switch_engine)
	var target: Dictionary = switch_engine.targets[0]
	var switch_pose: Dictionary = V2Spawner.sample_target(target, 0.0)
	switch_engine.queue_pose(0.0, float(switch_pose.yaw_deg), float(switch_pose.pitch_deg))
	switch_engine.queue_fire(0.0, true)
	switch_engine.advance(0.2)
	_check(absf(float(target.damage) - 20.0) < 1e-8, "hold damage, no instantaneous click kill")
	var radius_before: float = float(V2Spawner.sample_target(target, 0.0).radius_m)
	_check(V2Spawner.sample_target(target, 0.2).radius_m == radius_before, "damage never shrinks body")
	switch_engine.queue_fire(0.2, false)
	switch_engine.advance(20.0)
	_check(absf(float(switch_engine.phases[0].metrics.credited_work) - 0.5) < 1e-8, "partial credited before phase censor")
	_check(absf(float(switch_engine.phases[0].score) - 25.0) < 1e-8, "partial work score")
	var depth_engine := V2SessionEngine.new()
	depth_engine.start(_definition("EX07"), "00000000000000000000000000000042")
	var depth_target: Dictionary = depth_engine.targets[0]
	_check(absf(float(V2Spawner.sample_target(depth_target, 1.0).radius_m) - float(V2Spawner.sample_target(depth_target, 5.0).radius_m)) < 1e-15, "EX07 constant physical radius")
	var budget_engine := V2SessionEngine.new()
	budget_engine.start(_definition("EX06"), "00000000000000000000000000000042")
	_ack(budget_engine)
	budget_engine._contact.evaluations = V2Contact.MAX_EVALUATIONS_PER_PHASE
	budget_engine.advance(0.1)
	_check(budget_engine.completed and budget_engine.report().program_score == null and budget_engine.invalid_reason == "unresolved_integration_error", "no score on integration exhaustion")
	print("V2 RUNTIME : %d assertions, %d échecs" % [assertions, failures])
	quit(0 if failures == 0 else 1)
