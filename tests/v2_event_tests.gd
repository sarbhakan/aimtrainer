extends SceneTree

var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("V2 EVENTS: " + description)


func _ack(engine: V2SessionEngine) -> void:
	var identities: Array = []
	for target: Dictionary in engine.snapshot():
		identities.append(target.identity)
	engine.mark_rendered(identities, identities, engine.elapsed_s)


func _replay(frame_hz: int, events: Array) -> Dictionary:
	var engine := V2SessionEngine.new()
	engine.start(V2Catalog.find("EX06", "standard"), "00000000000000000000000000000042", {"retain_input_trace": true})
	_ack(engine)
	var read_index: int = 0
	for frame: int in frame_hz * 2:
		var frame_end_s: float = float(frame + 1) / float(frame_hz)
		while read_index < events.size() and float(events[read_index][0]) <= frame_end_s:
			var event: Array = events[read_index]
			engine.queue_pose(float(event[0]), float(event[1]), float(event[2]))
			read_index += 1
		engine.advance(frame_end_s)
	_check(engine.invalid_reason.is_empty(), "8 kHz synthetic receipt stream survives " + str(frame_hz) + " FPS framing")
	_check(engine.pose_event_count == events.size(), "all received poses applied exactly once")
	_check(engine.received_pose_trace.size() == events.size(), "full opt-in QA trace")
	_check(int(engine.received_pose_trace[-1][1]) == events.size(), "receipt sequence monotonic and complete")
	return engine.metrics.duplicate()


func _run() -> void:
	var engine := V2SessionEngine.new()
	engine.start(V2Catalog.find("EX01", "standard"), "00000000000000000000000000000042")
	_ack(engine)
	var pose: Dictionary = engine.snapshot()[0].pose
	engine.queue_pose(0.1, float(pose.yaw_deg), float(pose.pitch_deg))
	engine.queue_fire(0.1, true)
	engine.queue_pose(0.1, 80.0, 0.0)
	engine.advance(0.1)
	_check(int(engine.metrics.hits) == 1, "motion / press / motion at same receipt time uses intermediate pose")
	_check(engine.yaw_deg == 80.0 and engine.pose_event_count == 2, "each equal-time pose exactly once")
	_check(engine.received_pose_trace.is_empty(), "light practice does not retain raw input silently")
	var same := V2SessionEngine.new()
	same.start(V2Catalog.find("EX02", "standard"), "00000000000000000000000000000042")
	_check(same.manifest.size() == 3, "initial three grid identities")
	var saved_manifest: Array = same.manifest.duplicate(true)
	for event_index: int in 20:
		same.queue_pose(float(event_index) * 0.001, -80.0, 70.0)
	same.advance(0.02)
	_check(same.manifest == saved_manifest, "reticle motion cannot bias spawn randomness")
	var offscreen := V2SessionEngine.new()
	offscreen.start(V2Catalog.find("EX03", "standard"), "00000000000000000000000000000042")
	var planned: Dictionary = offscreen._scheduled[0]
	offscreen.advance(float(planned.born_s))
	offscreen.mark_rendered([planned.identity], [], offscreen.elapsed_s, true)
	offscreen.advance(float(planned.expiry_s))
	_check(offscreen.invalid_reason.is_empty() and int(offscreen.metrics.expired) == 1, "deliberate look-away is an expiry, not a technical failure")
	var missing := V2SessionEngine.new()
	missing.start(V2Catalog.find("EX03", "standard"), "00000000000000000000000000000042")
	missing.advance(float(missing._scheduled[0].expiry_s))
	_check(missing.invalid_reason == "nonrendered_opportunity", "actual missing draw invalidates rather than counts human miss")
	var switching := V2SessionEngine.new()
	switching.start(V2Catalog.find("EX08", "standard"), "00000000000000000000000000000042")
	_ack(switching)
	var target: Dictionary = switching.targets[0]
	var switch_pose: Dictionary = V2Spawner.sample_target(target, 0.0)
	switching.queue_pose(0.0, float(switch_pose.yaw_deg), float(switch_pose.pitch_deg))
	switching.queue_fire(0.0, true)
	switching.advance(0.4)
	_check(int(switching.metrics.kills) == 1, "exact ideal contact produces one destruction")
	_check(int(switching.targets[0].generation) == 1 and float(switching.targets[0].damage) == 0.0, "no damage overflow into next unrendered generation")
	var paused := V2SessionEngine.new()
	paused.start(V2Catalog.find("EX01", "standard"), "00000000000000000000000000000042")
	paused.note_pause(0.1)
	paused.advance(60.0)
	_check(paused.report().complete and not paused.report().rank_eligible, "paused practice remains diagnostic, not continuous record")
	var synthetic_events: Array = []
	for event_index: int in 16000:
		var receipt_s: float = float(event_index) / 8000.0
		synthetic_events.append([receipt_s, 10.0 * sin(receipt_s * 3.1), 0.0])
	var reference: Dictionary = _replay(60, synthetic_events)
	for frame_hz: int in [144, 240]:
		var candidate: Dictionary = _replay(frame_hz, synthetic_events)
		_check(absf(float(candidate.contact_s) - float(reference.contact_s)) <= 0.001 + float(candidate.contact_upper_s) - float(candidate.contact_lower_s) + float(reference.contact_upper_s) - float(reference.contact_lower_s), "same hold trace scores within published integration bounds across FPS")
	print("V2 EVENTS : %d assertions, %d échecs" % [assertions, failures])
	quit(0 if failures == 0 else 1)
