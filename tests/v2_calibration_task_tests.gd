extends SceneTree

const Task: GDScript = preload("res://scripts/v2/v2_calibration_task.gd")
const Service: GDScript = preload("res://scripts/v2/v2_calibration_service.gd")
const Motion: GDScript = preload("res://scripts/v2/v2_motion.gd")
const Spawner: GDScript = preload("res://scripts/v2/v2_spawner.gd")
const Canonical: GDScript = preload("res://scripts/v2/v2_canonical.gd")
const Contact: GDScript = preload("res://scripts/v2/v2_contact.gd")
const MAX_REPORTED_FAILURES: int = 25
const PYTHON_ORACLE: String = """
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys
sys.dont_write_bytecode = True
kit_root = Path(sys.argv[1])
sys.path.insert(0, str(kit_root / 'outils'))
import calibration_v2_reference as reference
import mouvements_reference as motions
validator_random = random.Random(92221)
seeds = [json.loads((kit_root / 'donnees/calibration_v2_plan_example.json').read_text())['confirmation_plan_seed_hex']]
seeds.extend(format(validator_random.getrandbits(128), '032x') for draw_index in range(2))
protocol = reference.protocol()
cases = []
for difficulty in ('novice', 'standard', 'advanced'):
    for seed in seeds:
        for task_name in reference.TASKS:
            deck = reference.make_deck(seed, 'confirmation', '1', '0', '0', task_name, difficulty)
            entry = {'seed': seed, 'difficulty': difficulty, 'task': task_name, 'deck': deck}
            if task_name in ('SMOOTH', 'REACTIVE'):
                samples = []
                times_s = sorted([0.0, 1.0, 15.0, 23.999999] + [validator_random.uniform(0, 24) for draw_index in range(48)])
                if task_name == 'REACTIVE':
                    times_s.extend(event['time_us'] / 1e6 for event in deck['trajectory_tape']['events'])
                for time_s in times_s:
                    if task_name == 'SMOOTH':
                        trajectory = deck['trajectory']
                        yaw_deg = trajectory['amplitude_deg'] * math.sin(trajectory['max_speed_deg_s'] / trajectory['amplitude_deg'] * time_s + trajectory['phase_rad'])
                    else:
                        yaw_deg = motions.sample_reactive(deck['trajectory_tape'], time_s)[0]
                    samples.append({'time_s': time_s, 'yaw_deg': yaw_deg, 'pitch_deg': 0.0, 'distance_m': 4.0})
                entry['samples'] = samples
                if task_name == 'SMOOTH':
                    trajectory = deck['trajectory']
                    omega_rad_s = trajectory['max_speed_deg_s'] / trajectory['amplitude_deg']
                    phase_rad = trajectory['phase_rad']
                    half_span_rad = math.asin(trajectory['diameter_deg'] / (2 * trajectory['amplitude_deg']))
                    total_contact_s = 0.0
                    for crossing_index in range(math.floor((phase_rad - half_span_rad) / math.pi) - 1, math.ceil((phase_rad + omega_rad_s * 24 + half_span_rad) / math.pi) + 2):
                        begin_s = max(0.0, (crossing_index * math.pi - half_span_rad - phase_rad) / omega_rad_s)
                        end_s = min(24.0, (crossing_index * math.pi + half_span_rad - phase_rad) / omega_rad_s)
                        total_contact_s += max(0.0, end_s - begin_s)
                    entry['stationary_contact_s'] = total_contact_s
            elif task_name == 'CLICK':
                entry['mixed_dispositions'] = ['resolved_premature', 'resolved_hit', 'resolved_miss', 'timeout'] * 4
                entry['mixed_utility'] = sum(1 - 0.25 / protocol['tasks']['CLICK']['active_window_s'] for slot_index in range(16) if slot_index % 4 == 1) / 16
                entry['perfect_latency_s'] = 0.20
                entry['perfect_utility'] = 1 - entry['perfect_latency_s'] / protocol['tasks']['CLICK']['active_window_s']
            else:
                ideal_ttk_s = protocol['tasks']['SWITCH']['hp'][difficulty] / protocol['tasks']['SWITCH']['damage_hp_s']
                entry['ideal_ttk_s'] = ideal_ttk_s
                entry['delayed_gate_utility'] = (protocol['tasks']['SWITCH']['active_window_s'] - (0.3 + ideal_ttk_s)) / (protocol['tasks']['SWITCH']['active_window_s'] - ideal_ttk_s)
            cases.append(entry)
source_paths = ['outils/calibration_v2_reference.py', 'outils/mouvements_reference.py', 'donnees/catalogue.v2.json', 'donnees/calibration_v2_protocol.json']
audit_rows = [(0.0, 1, -0.0, 0.12345678901234567), (0.12345678901234567, 3, 31.23456789012345, -7.654321098765432)]
pose_bytes = b''.join(struct.pack('<IIddd', math.floor(receipt_s * 1e6 + 0.5), sequence, receipt_s, yaw_deg, pitch_deg) for receipt_s, sequence, yaw_deg, pitch_deg in audit_rows)
fire_rows = [(0.0, 2, True), (audit_rows[1][0], 4, False)]
fire_bytes = b''.join(struct.pack('<IIdB', math.floor(receipt_s * 1e6 + 0.5), sequence, receipt_s, pressed) for receipt_s, sequence, pressed in fire_rows)
def wire(value):
    if isinstance(value, float):
        return 'f64be:' + struct.pack('>d', value).hex()
    if isinstance(value, dict):
        return {key: wire(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [wire(item) for item in value]
    return value
print(json.dumps(wire({'cases': cases, 'seeds': seeds, 'audit_rows': audit_rows, 'pose_bytes_hex': pose_bytes.hex(), 'pose_sha256': hashlib.sha256(pose_bytes).hexdigest(), 'fire_bytes_hex': fire_bytes.hex(), 'fire_sha256': hashlib.sha256(fire_bytes).hexdigest(), 'source_sha256': {name: hashlib.sha256((kit_root / name).read_bytes()).hexdigest() for name in source_paths}}), separators=(',', ':')))
"""

var assertion_count: int = 0
var failure_count: int = 0
var oracle: Dictionary = {}
var task_runs: int = 0
var deck_cases: int = 0


func _initialize() -> void:
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		if failure_count <= MAX_REPORTED_FAILURES:
			push_error(description)


func close_value(actual: float, expected: float, description: String, epsilon: float = 1e-9) -> void:
	check(is_finite(actual) and absf(actual - expected) <= epsilon, "%s got=%.17f expected=%.17f tolerance=%.12f" % [description, actual, expected, epsilon])


func run_tests() -> void:
	var output: Array = []
	var result: int = OS.execute("python3", PackedStringArray(["-c", PYTHON_ORACLE, ProjectSettings.globalize_path("res://docs/reference/v2")]), output, true)
	check(result == 0, "Archived Python CAL oracle failed: " + str(output).left(1500))
	if result != 0 or output.is_empty():
		finish()
		return
	var parsed: Variant = JSON.parse_string(String(output[0]))
	check(parsed is Dictionary, "CAL task oracle must produce a dictionary")
	if not parsed is Dictionary:
		finish()
		return
	oracle = decode_binary64(parsed)
	for source_path: String in oracle.source_sha256:
		check(FileAccess.get_sha256("res://docs/reference/v2/" + source_path) == oracle.source_sha256[source_path], "CAL source provenance differs: " + source_path)
	for case: Dictionary in oracle.cases:
		deck_cases += 1
		var deck: Dictionary = Service.make_deck(case.seed, "confirmation", "1", "0", "0", case.task, case.difficulty)
		check(not deck.has("error"), "Native CAL deck failed: " + str(deck))
		if deck.has("error"):
			continue
		match String(case.task):
			"CLICK":
				test_click_mixed(deck, case)
				test_click_perfect(deck, 15.0, float(case.perfect_latency_s), float(case.perfect_utility))
			"SWITCH":
				test_switch_perfect(deck, 24.0)
				test_switch_perfect(deck, 15.0)
			"SMOOTH", "REACTIVE":
				test_trajectory_oracle(deck, case)
				test_tracking_contact(deck, 15.0, 0.5, 120)
				if case.task == "SMOOTH":
					test_stationary_tracking_crossings(deck, float(case.stationary_contact_s))
	var seed: String = oracle.seeds[0]
	var click: Dictionary = Service.make_deck(seed, "confirmation", "1", "0", "0", "CLICK")
	var switching: Dictionary = Service.make_deck(seed, "confirmation", "1", "0", "0", "SWITCH")
	var smooth: Dictionary = Service.make_deck(seed, "confirmation", "1", "0", "0", "SMOOTH")
	var reactive: Dictionary = Service.make_deck(seed, "confirmation", "1", "0", "0", "REACTIVE")
	test_click_premature_and_nonrender(click)
	test_click_hold_and_ties(click)
	test_switch_deadline_and_partial(switching)
	test_switch_render_gate(switching)
	test_tracking_contact(smooth, 24.0, 0.0, 60)
	test_tracking_contact(smooth, 24.0, 0.0, 144)
	test_tracking_contact(reactive, 24.0, 0.0, 240)
	test_input_render_and_manifest_failures(smooth, reactive)
	test_compact_audit_and_gain(smooth)
	test_prepared_proof(switching)
	test_certified_reacquisition(reactive)
	test_eight_kilohertz_audit(smooth)
	finish()


func finish() -> void:
	print("V2 CAL TASKS: %d assertions, %d failures; %d original-oracle deck cases, %d native runs." % [assertion_count, failure_count, deck_cases, task_runs])
	quit(0 if failure_count == 0 else 1)


func decode_binary64(value: Variant) -> Variant:
	if value is Dictionary:
		for key: String in value:
			value[key] = decode_binary64(value[key])
	elif value is Array:
		for element_index: int in value.size():
			value[element_index] = decode_binary64(value[element_index])
	elif value is String and value.begins_with("f64be:"):
		return Canonical.float64_from_hex(value.trim_prefix("f64be:"))
	return value


func begin(deck: Dictionary, duration_s: float = 24.0) -> RefCounted:
	task_runs += 1
	var run: RefCounted = Task.new()
	check(run.start(deck, duration_s), "Native task must accept Service.make_deck: " + String(deck.task_id) + " " + str(run.invalid_reason))
	return run


func render(run: RefCounted, at_s: float, visible: bool = true) -> void:
	run.advance(at_s)
	var identities: Array = []
	for target: Dictionary in run.snapshot():
		identities.append(target.identity)
	run.mark_rendered(identities, identities if visible else [], at_s)
	run.record_frame(1.0 / 120.0)


func press(run: RefCounted, at_s: float, yaw_deg: float, pitch_deg: float, duplicate_held: bool = false) -> void:
	run.queue_pose(at_s, yaw_deg, pitch_deg)
	run.queue_fire(at_s, true)
	if duplicate_held:
		run.queue_fire(at_s, true)
	run.advance(at_s)
	run.queue_fire(at_s + 0.00001, false)
	run.advance(at_s + 0.00001)


func finish_remaining_click_premature(run: RefCounted, first_index: int) -> void:
	for slot_index: int in range(first_index, run.opportunities.size()):
		var row: Dictionary = run.opportunities[slot_index]
		press(run, float(row.slot_start_s) + 0.05, 0.0, 0.0)
		run.advance(minf(float(row.slot_end_s), float(run.duration_s)))


func test_click_mixed(deck: Dictionary, case: Dictionary) -> void:
	var saved: Dictionary = deck.duplicate(true)
	var run: RefCounted = begin(deck)
	for slot_index: int in 16:
		var row: Dictionary = deck.opportunities[slot_index]
		var onset_s: float = float(row.onset_us) / 1000000.0
		var deadline_s: float = float(row.deadline_us) / 1000000.0
		match slot_index % 4:
			0:
				press(run, float(row.slot_start_s) + 0.05, float(row.yaw_deg), float(row.pitch_deg), true)
				render(run, onset_s)
				check(run.snapshot().is_empty(), "Premature first press suppresses CLICK appearance")
				press(run, onset_s + 0.3, float(row.yaw_deg), float(row.pitch_deg))
			1:
				render(run, onset_s)
				press(run, onset_s + 0.25, float(row.yaw_deg), float(row.pitch_deg), true)
				press(run, onset_s + 0.3, float(row.yaw_deg), float(row.pitch_deg))
			2:
				render(run, onset_s)
				press(run, onset_s + 0.4, 90.0, 0.0)
				press(run, onset_s + 0.5, float(row.yaw_deg), float(row.pitch_deg))
			3:
				render(run, onset_s)
				press(run, deadline_s, float(row.yaw_deg), float(row.pitch_deg))
		run.advance(float(row.slot_end_s))
	var report: Dictionary = run.report()
	check(report.complete and report.valid and report.task == "CLICK", "Mixed CLICK task must complete without technical censoring")
	close_value(float(report.U), float(case.mixed_utility), "CLICK first-shot latency utility from original protocol")
	check(report.raw_succeeded == 4 and report.opportunities == 16 and report.first_presses == 12 and report.premature == 4 and report.extra_shots == 12 and report.late_shots == 4, "CLICK definite-first-press and diagnostic counters")
	check(report.metrics.technical_censored == 0 and report.metrics.hits == 4 and report.metrics.misses == 8 and report.metrics.timeouts == 4, "CLICK misses and premature failures cannot be repaired or censored as technical")
	for slot_index: int in 16:
		check(report.opportunity_dispositions[slot_index].disposition == case.mixed_dispositions[slot_index], "CLICK authoritative slot disposition: %d" % slot_index)
		close_value(float(report.opportunity_dispositions[slot_index].onset_s), float(case.deck.opportunities[slot_index].onset_s), "CLICK onset remains exogenous after resolution")
	check(run.report() == report and deck == saved, "Completed CLICK report and manifest stay immutable")
	report.metrics.hits = -1
	check(run.report().metrics.hits == 4, "Report callers cannot mutate the cached report")


func test_click_perfect(deck: Dictionary, duration_s: float, latency_s: float, expected_utility: float) -> void:
	var run: RefCounted = begin(deck, duration_s)
	for row: Dictionary in run.opportunities:
		if not bool(row.included_in_utility):
			continue
		render(run, float(row.onset_s))
		press(run, float(row.onset_s) + latency_s, float(row.yaw_deg), float(row.pitch_deg))
	run.advance(duration_s)
	var report: Dictionary = run.report()
	check(report.complete and report.valid and report.raw_succeeded == 10 and report.opportunities == 10, "15-second CLICK counts ten complete opportunities")
	close_value(float(report.diagnostic_utility), expected_utility, "CLICK preflight uses ten opportunities instead of sixteen")
	check(report.U == null and report.utility == null and not report.comparative_utility_included and not report.comparable, "CLICK preflight cannot enter measured comparison")


func test_click_premature_and_nonrender(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	var onset_s: float = float(run.opportunities[0].onset_s)
	run.advance(onset_s)
	press(run, onset_s + 0.01, float(deck.opportunities[0].yaw_deg), float(deck.opportunities[0].pitch_deg))
	finish_remaining_click_premature(run, 1)
	var report: Dictionary = run.report()
	check(report.complete and report.valid and report.premature == 16 and report.metrics.technical_censored == 0 and report.U == 0.0, "Active-but-unrendered first press remains a human premature failure")
	run = begin(deck)
	run.advance(float(run.opportunities[0].deadline_s))
	check(run.completed and run.invalid_reason == "nonrendered_opportunity" and run.report().U == null, "No press and no prepared frame is a technical opportunity failure")
	run = begin(deck)
	render(run, float(run.opportunities[0].onset_s), false)
	run.advance(float(run.opportunities[0].deadline_s))
	check(not run.completed and run.opportunities[0].disposition == "timeout", "Prepared-but-offscreen CLICK timeout remains human")
	finish_remaining_click_premature(run, 1)
	check(run.report().valid and run.report().premature == 15, "Offscreen timeout does not fabricate a visible-frame marker")
	run = begin(deck, float(deck.opportunities[0].deadline_us) / 1000000.0)
	render(run, float(run.opportunities[0].onset_s))
	run.advance(float(run.duration_s))
	check(run.report().complete and run.opportunities[0].disposition == "timeout" and run.report().opportunities == 1 and run.metrics.censored == 0, "A segment ending exactly at a full deadline closes its opportunity before segment censoring")


func test_click_hold_and_ties(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	run.queue_fire(0.0, true)
	run.advance(0.0)
	for row: Dictionary in run.opportunities:
		render(run, float(row.onset_s))
		run.queue_fire(float(row.onset_s), true)
		run.advance(float(row.slot_end_s))
	check(run.report().first_presses == 1 and run.report().premature == 1 and run.report().metrics.timeouts == 15, "Holding CLICK cannot produce another first press in subsequent slots")
	var before_pose: RefCounted = begin(deck)
	var after_pose: RefCounted = begin(deck)
	var row: Dictionary = deck.opportunities[0]
	var time_s: float = float(row.onset_us) / 1000000.0 + 0.2
	render(before_pose, float(row.onset_us) / 1000000.0)
	render(after_pose, float(row.onset_us) / 1000000.0)
	before_pose.queue_fire(time_s, true)
	before_pose.queue_pose(time_s, float(row.yaw_deg), float(row.pitch_deg))
	after_pose.queue_pose(time_s, float(row.yaw_deg), float(row.pitch_deg))
	after_pose.queue_fire(time_s, true)
	before_pose.advance(time_s)
	after_pose.advance(time_s)
	check(before_pose.opportunities[0].disposition == "resolved_miss" and after_pose.opportunities[0].disposition == "resolved_hit", "Same-timestamp receipts preserve pose/fire reception order")
	after_pose.queue_fire(time_s + 0.001, false)
	after_pose.advance(time_s + 0.001)
	after_pose.queue_fire(1.5, true)
	after_pose.advance(1.5)
	check(after_pose.opportunities[1].disposition == "resolved_premature", "New CLICK slot opens before a press at its exact start")


func test_switch_perfect(deck: Dictionary, duration_s: float) -> void:
	var run: RefCounted = begin(deck, duration_s)
	var saved: Dictionary = deck.duplicate(true)
	run.queue_fire(0.0, true)
	run.advance(0.0)
	var physical_kills: int = 0
	for row: Dictionary in run.opportunities:
		run.advance(float(row.slot_start_s))
		var neutral_snapshot: Array = run.snapshot()
		check(neutral_snapshot.size() == 3, "SWITCH restores three neutral positions at slot start")
		for target: Dictionary in neutral_snapshot:
			check(target.neutral and not target.priority and target.hp_max == 0.0 and target.damage == 0.0, "SWITCH pre-onset does not reveal or damage the future priority")
		var position: Dictionary = deck.positions[int(row.priority_target_id)]
		run.queue_pose(float(row.onset_s), float(position.yaw_deg), float(position.pitch_deg))
		render(run, float(row.onset_s))
		var priority_snapshot: Array = run.snapshot()
		var active_count: int = 0
		for target: Dictionary in priority_snapshot:
			if target.priority:
				active_count += 1
				close_value(float(target.hp_max), float(row.hp), "SWITCH resets full HP at each logical onset")
		check(active_count == 1, "Exactly one SWITCH priority becomes damageable")
		var kill_s: float = float(row.onset_s) + float(row.hp) / float(row.damage_hp_s)
		run.advance(kill_s)
		physical_kills += 1
		check(row.disposition == "resolved_killed" and run.snapshot().size() == 2, "SWITCH kill hides only the priority until the next slot")
		close_value(float(row.resolved_s), kill_s, "SWITCH ideal kill timestamp")
		close_value(float(row.utility), 1.0, "SWITCH utility subtracts the ideal TTK")
		run.advance(minf(float(row.slot_end_s), duration_s))
	var report: Dictionary = run.report()
	check(report.complete and report.valid and report.killed == physical_kills, "Held SWITCH completes without requiring a new press per slot")
	close_value(float(report.metrics.useful_damage), float(physical_kills) * float(deck.opportunities[0].hp), "SWITCH damage never spills beyond one priority's HP")
	close_value(float(report.metrics.contact_s), float(physical_kills) * float(deck.opportunities[0].ideal_ttk_s), "SWITCH credits useful contact only until each kill")
	if duration_s == 15.0:
		check(report.opportunities == 7 and report.raw_succeeded == 7 and report.killed == 8, "SWITCH preflight excludes the partial eighth window from its seven-opportunity denominator")
		close_value(float(report.diagnostic_utility), 1.0, "SWITCH preflight utility")
		check(report.U == null and not report.comparative_utility_included, "SWITCH preflight physical kills cannot enter scored comparison")
	else:
		check(report.opportunities == 12 and report.raw_succeeded == 12 and report.switch_completions == 12, "SWITCH records the twelve actual completed opportunities")
		close_value(float(report.U), 1.0, "SWITCH perfect utility from original formula")
	check(deck == saved, "SWITCH runtime never rewrites deck windows or positions")


func finish_switch_timeouts(run: RefCounted, first_index: int) -> void:
	for slot_index: int in range(first_index, run.opportunities.size()):
		var row: Dictionary = run.opportunities[slot_index]
		run.queue_pose(float(row.slot_start_s), 90.0, 0.0)
		render(run, float(row.onset_s))
		run.advance(minf(float(row.slot_end_s), float(run.duration_s)))


func test_switch_deadline_and_partial(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	var row: Dictionary = run.opportunities[0]
	var position: Dictionary = deck.positions[int(row.priority_target_id)]
	run.queue_pose(0.0, 90.0, 0.0)
	run.queue_fire(0.0, true)
	render(run, float(row.onset_s))
	var begin_s: float = float(row.deadline_s) - float(row.ideal_ttk_s)
	run.queue_pose(begin_s, float(position.yaw_deg), float(position.pitch_deg))
	run.advance(float(row.deadline_s))
	check(row.disposition == "resolved_killed" and run.metrics.kills == 1 and run.metrics.timeouts == 0, "HP reaching zero exactly at the exclusive deadline is one kill, not a timeout")
	close_value(float(row.resolved_s), float(row.deadline_s), "Exact SWITCH deadline kill timestamp")
	close_value(float(row.utility), 0.0, "Exact SWITCH deadline kill earns zero utility")
	finish_switch_timeouts(run, 1)
	check(run.report().raw_succeeded == 1 and run.report().U == 0.0, "SWITCH raw completion can be successful with zero latency utility")
	run = begin(deck)
	row = run.opportunities[0]
	run.queue_pose(float(row.onset_s), float(position.yaw_deg), float(position.pitch_deg))
	run.queue_fire(float(row.onset_s), true)
	render(run, float(row.onset_s))
	run.advance(float(row.onset_s) + float(row.ideal_ttk_s) * 0.5)
	close_value(float(row.damage), float(row.hp) * 0.5, "SWITCH partial HP is actual integrated contact")
	run.queue_pose(run.elapsed_s, 90.0, 0.0)
	run.advance(float(row.deadline_s))
	check(row.disposition == "timeout" and run.metrics.kills == 0 and row.utility == 0.0, "Partial damage never becomes a SWITCH completion")
	finish_switch_timeouts(run, 1)
	check(run.report().raw_succeeded == 0 and run.report().U == 0.0, "SWITCH ignores incomplete fractional damage in utility")
	run = begin(deck)
	row = run.opportunities[0]
	var nonpriority: Dictionary = deck.positions[(int(row.priority_target_id) + 1) % 3]
	run.queue_fire(0.0, true)
	run.queue_pose(float(row.onset_s), float(nonpriority.yaw_deg), float(nonpriority.pitch_deg))
	render(run, float(row.onset_s))
	run.advance(float(row.deadline_s))
	check(row.damage == 0.0 and run.metrics.useful_damage == 0.0, "Held contact on neutral positions never damages the priority")


func test_switch_render_gate(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	var row: Dictionary = run.opportunities[0]
	var position: Dictionary = deck.positions[int(row.priority_target_id)]
	var old_ids: Array = []
	for target: Dictionary in run.snapshot():
		old_ids.append(target.identity)
	run.mark_rendered(old_ids, old_ids, 0.0)
	run.queue_fire(0.0, true)
	run.queue_pose(float(row.onset_s), float(position.yaw_deg), float(position.pitch_deg))
	run.mark_rendered(old_ids, old_ids, float(row.onset_s))
	run.advance(float(row.onset_s) + 0.3)
	check(row.damage == 0.0 and row.first_rendered_s == null, "An earlier neutral render cannot admit a new SWITCH priority")
	render(run, float(row.onset_s) + 0.3)
	run.advance(float(row.onset_s) + 0.3 + float(row.ideal_ttk_s))
	var window_s: float = 1.7
	close_value(float(row.utility), (window_s - 0.3 - float(row.ideal_ttk_s)) / (window_s - float(row.ideal_ttk_s)), "SWITCH render gate delays eligibility without changing logical latency origin")
	check(run.metrics.premature == 0 and row.disposition == "resolved_killed", "SWITCH early held fire remains armed and never becomes CLICK premature failure")


func test_trajectory_oracle(deck: Dictionary, case: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	var target: Dictionary = run.targets[0]
	var saved_deck: Dictionary = deck.duplicate(true)
	var saved_target: Dictionary = target.duplicate(true)
	for sample_index: int in range(case.samples.size() - 1, -1, -1):
		var sample: Dictionary = case.samples[sample_index]
		var pose: Dictionary = run._sample_target(target, float(sample.time_s))
		check(pose == Spawner.sample_target(target, float(sample.time_s)), "CAL prepared pose is exactly the public spawner's authoritative pose")
		close_value(float(pose.yaw_deg), float(sample.yaw_deg), "Original CAL trajectory yaw " + String(case.task))
		close_value(float(pose.pitch_deg), float(sample.pitch_deg), "Original CAL trajectory pitch")
		close_value(float(pose.distance_m), float(sample.distance_m), "Original CAL trajectory distance")
		check(pose.direction is Array and pose.center_offset_m is Array and pose.direction.size() == 3, "CAL snapshots use authoritative binary64 direction and center arrays")
		close_value(float(pose.radius_m), float(pose.distance_m) * sin(deg_to_rad(float(pose.diameter_deg) * 0.5)), "CAL silhouette radius matches scalar collision sphere")
	check(run.snapshot()[0].pose == run._sample_target(target, 0.0) and target == saved_target and deck == saved_deck, "CAL trajectory queries and snapshots consume no random state or change the manifest")
	if case.task == "REACTIVE":
		check(target.motion.tape == deck.trajectory_tape, "CAL REACTIVE must use the manifest's actual tape")
		for reversal: Dictionary in run._reversals:
			var zero_s: float = float(reversal.effective_sign_change_s)
			var before: Array = Motion.sample_reactive(deck.trajectory_tape, maxf(0.0, zero_s - 0.000001))
			var after: Array = Motion.sample_reactive(deck.trajectory_tape, zero_s + 0.000001)
			check(float(before[1]) * float(after[1]) < 0.0 and zero_s > float(reversal.ramp_start_s), "Reactive diagnostics use actual sign changes rather than preempted ramp starts")


func test_tracking_contact(deck: Dictionary, duration_s: float, gate_s: float, frame_rate: int) -> void:
	var run: RefCounted = begin(deck, duration_s)
	var target: Dictionary = run.targets[0]
	for frame_index: int in range(int(round(duration_s * float(frame_rate))) + 1):
		var time_s: float = float(frame_index) / float(frame_rate)
		var pose: Dictionary = run._sample_target(target, time_s)
		run.queue_pose(time_s, float(pose.yaw_deg), float(pose.pitch_deg))
	if gate_s > 0.0:
		run.advance(gate_s)
	render(run, gate_s)
	for frame_index: int in range(int(round(gate_s * float(frame_rate))) + 1, int(round(duration_s * float(frame_rate))) + 1):
		run.record_frame(1.0 / float(frame_rate))
		run.advance(float(frame_index) / float(frame_rate))
	var report: Dictionary = run.report()
	check(report.complete and report.valid and report.task in ["SMOOTH", "REACTIVE"], "Invincible CAL tracking completes without a button requirement")
	close_value(float(report.metrics.contact_s), duration_s - gate_s, "Initial acquisition and first-render delay remain in the full exposure denominator")
	close_value(float(report.diagnostic_utility), (duration_s - gate_s) / duration_s, "Tracking utility matches planned exposure")
	check(float(report.diagnostic_utility) >= 0.0 and float(report.diagnostic_utility) <= 1.0, "Tracking utility stays inside the comparison service's strict probability bounds")
	check(report.metrics.contact_lower_s <= report.metrics.contact_s and report.metrics.contact_s <= report.metrics.contact_upper_s and float(report.metrics.contact_upper_s) - float(report.metrics.contact_lower_s) <= 0.0005 * duration_s, "CAL uses bounded shared contact integration")
	check(report.metrics.integration_g_evaluations > 0 and report.metrics.integration_g_evaluations < Contact.MAX_EVALUATIONS_PER_PHASE and report.metrics.kills == 0, "Tracking consumes a finite contact budget and never respawns or kills")
	if duration_s == 24.0:
		close_value(float(report.U), 1.0, "Perfect received-pose-hold tracking across frame rates")
		check(report.comparable and report.render_quality.eligible, "Actual recorded frame deltas gate comparability separately")
	else:
		check(report.U == null and not report.comparative_utility_included and not report.comparable, "Tracking preflight is diagnostic only")


func test_stationary_tracking_crossings(deck: Dictionary, exact_contact_s: float) -> void:
	var run: RefCounted = begin(deck)
	render(run, 0.0)
	run.advance(24.0)
	var report: Dictionary = run.report()
	check(report.complete and report.valid, "Moving CAL contact crossings remain resolved under the shared global uncertainty budget")
	var lower_s: float = float(report.metrics.contact_lower_s)
	var upper_s: float = float(report.metrics.contact_upper_s)
	check(lower_s <= exact_contact_s + 1e-9 and upper_s + 1e-9 >= exact_contact_s, "Contact bounds contain the Python closed-form sine crossing integral")
	check(upper_s - lower_s <= 0.0005 * 24.0 + 1e-9, "All ambiguous CAL crossings share one bounded phase uncertainty width")
	close_value(float(report.metrics.contact_s), exact_contact_s, "Contact estimate differs from the independent analytic truth only within its certified width", (upper_s - lower_s) * 0.5 + 1e-9)
	check(report.metrics.integration_g_evaluations > 0 and report.metrics.integration_g_evaluations < Contact.MAX_EVALUATIONS_PER_PHASE, "CAL crossing evaluations consume the shared cumulative phase budget")


func test_input_render_and_manifest_failures(deck: Dictionary, reactive: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	run.queue_pose(0.2, 0.0, 0.0)
	run.queue_pose(0.1, 0.0, 0.0)
	check(run.invalid_reason == "nonmonotonic_input_receipt" and run.completed and run.report().U == null, "Nonmonotonic receipt invalidates CAL instead of silently sorting")
	run = begin(deck)
	run.queue_pose(0.0, NAN, 0.0)
	check(run.invalid_reason == "nonfinite_input_pose", "Nonfinite authoritative pose must invalidate CAL")
	run = begin(deck)
	run.mark_rendered([], [], 0.0, false)
	check(run.invalid_reason == "render_viewport_failure", "Invalid viewport never relaxes the render gate")
	run = begin(deck)
	for event_index: int in Task.MAX_PENDING_EVENTS + 1:
		run.queue_pose(0.0, 0.0, 0.0)
	check(run.invalid_reason == "input_buffer_overflow", "Input overflow invalidates the calibration cell")
	run = begin(deck)
	render(run, 0.0)
	run._contact.evaluations = Contact.MAX_EVALUATIONS_PER_PHASE
	run.advance(0.1)
	check(run.invalid_reason == "unresolved_integration_error" and run.report().U == null, "Contact budget exhaustion remains a technical failure")
	run = begin(deck)
	run.record_frame(0.101)
	check(not run.quality().eligible and run.quality().max_ms > 100.0, "Frame quality uses actual recorded deltas and the 100-ms maximum")
	var corrupted: Dictionary = deck.duplicate(true)
	corrupted.trajectory.phase_rad = float(corrupted.trajectory.phase_rad) + 0.1
	run = Task.new()
	check(not run.start(corrupted) and run.invalid_reason == "calibration_manifest_hash_mismatch", "Deck corruption is refused before play")
	corrupted = reactive.duplicate(true)
	corrupted.trajectory_tape.pieces[0].x_origin_deg = float(corrupted.trajectory_tape.pieces[0].x_origin_deg) + 0.25
	var payload: Dictionary = corrupted.duplicate(true)
	payload.erase("manifest_sha256")
	corrupted.manifest_sha256 = Canonical.semantic_sha256(payload)
	run = Task.new()
	check(not run.start(corrupted) and run.invalid_reason == "calibration_trajectory_hash_mismatch", "Rehashed deck cannot replace the authoritative REACTIVE tape")


func decode_trace(block: Dictionary) -> PackedByteArray:
	var stored: PackedByteArray = PackedByteArray() if String(block.base64).is_empty() else Marshalls.base64_to_raw(String(block.base64))
	var decoded: PackedByteArray = stored.decompress(int(block.byte_count), FileAccess.COMPRESSION_ZSTD) if block.compression == "zstd" else stored
	check(decoded.size() == int(block.byte_count) and decoded.size() == int(block.record_count) * int(block.record_bytes), "Audit trace decodes to exactly its declared fixed-size records")
	check(Task._sha256_bytes(decoded) == block.sha256, "Decoded calibration audit bytes match their SHA-256")
	return decoded


func test_compact_audit_and_gain(deck: Dictionary) -> void:
	var baseline: Dictionary = Service.make_gain("A", 35.0)
	var temporary: Dictionary = Service.make_gain("B", 28.0)
	var context: Dictionary = {"candidate_id": "B", "applied_gain": temporary.degrees_per_relative_input_unit.duplicate(true), "profile": baseline.duplicate(true), "session_id": "unit-actual-held-gain", "monotonic_origin_us": 123456789}
	var saved_context: Dictionary = context.duplicate(true)
	var run: RefCounted = Task.new()
	task_runs += 1
	check(run.start(deck, 24.0, context), "Audit starts at the explicitly held temporary gain")
	var first: Array = oracle.audit_rows[0]
	var second: Array = oracle.audit_rows[1]
	run.queue_pose(float(first[0]), float(first[2]), float(first[3]))
	run.queue_fire(float(first[0]), true)
	run.queue_pose(float(second[0]), float(second[2]), float(second[3]))
	run.queue_fire(float(second[0]), false)
	render(run, 0.0)
	var active_report: Dictionary = run.report()
	check(not active_report.received_pose_trace.finalized and active_report.received_pose_trace.base64 == null and active_report.received_pose_trace.sha256 == null, "Active input tracing never performs JSON, hashing, or base64 finalization")
	run.record_frame(0.008)
	run.record_frame(0.012)
	run.advance(24.0)
	var report: Dictionary = run.report()
	var poses: PackedByteArray = decode_trace(report.received_pose_trace)
	var fires: PackedByteArray = decode_trace(report.fire_trace)
	check(poses.hex_encode() == oracle.pose_bytes_hex and report.received_pose_trace.sha256 == oracle.pose_sha256, "Pose receipt-us, sequence, exact time, and binary64 angles match Python packed bytes")
	check(fires.hex_encode() == oracle.fire_bytes_hex and report.fire_trace.sha256 == oracle.fire_sha256, "Fire press/release ordering matches Python packed bytes")
	check(report.applied_gain == temporary.degrees_per_relative_input_unit and report.candidate_id == "B" and context == saved_context, "Task audits held gain B without changing saved profile A or resetting gain")
	check(report.render_quality == Service.frame_quality(run.frame_intervals_s), "Task quality has the exact native service median, mean, ranked P99, maximum, and eligible fields")
	close_value(poses.decode_double(40), float(second[0]), "Audit preserves sub-microsecond receipt time in addition to integer microseconds", 0.0)
	check(report.audit.mandatory and report.audit.replay_exact_possible and int(report.audit.report_payload_bytes) <= Task.MAX_REPORT_BYTES, "Calibration audit retention is mandatory and bounded")
	var replay: RefCounted = Task.new()
	task_runs += 1
	check(replay.start(deck, 24.0, saved_context), "Audit replay uses unchanged manifest and actual held gain")
	var events: Array = []
	for record_index: int in int(report.received_pose_trace.record_count):
		var offset: int = record_index * Task.POSE_RECORD_BYTES
		events.append([poses.decode_double(offset + 8), float(poses.decode_u32(offset + 4)), "pose", [poses.decode_double(offset + 16), poses.decode_double(offset + 24)]])
	for record_index: int in int(report.fire_trace.record_count):
		var offset: int = record_index * Task.FIRE_RECORD_BYTES
		events.append([fires.decode_double(offset + 8), float(fires.decode_u32(offset + 4)), "fire", fires.decode_u8(offset + 16) == 1])
	var renders: PackedByteArray = decode_trace(report.render_trace)
	for record_index: int in int(report.render_trace.record_count):
		var offset: int = record_index * 24
		events.append([renders.decode_double(offset + 16), float(renders.decode_u32(offset + 4)) + 0.5, "render", [report.render_receipts[int(renders.decode_u32(offset + 8))], int(renders.decode_u32(offset + 12))]])
	events.sort_custom(func(first_event: Array, second_event: Array) -> bool:
		return float(first_event[0]) < float(second_event[0]) or (float(first_event[0]) == float(second_event[0]) and float(first_event[1]) < float(second_event[1])))
	for event: Array in events:
		if event[2] == "pose":
			replay.queue_pose(float(event[0]), float(event[3][0]), float(event[3][1]))
		elif event[2] == "fire":
			replay.queue_fire(float(event[0]), bool(event[3]))
		else:
			var receipt: Dictionary = event[3][0]
			var identity: String = String(receipt.identity)
			replay.mark_rendered([identity], [identity] if int(event[3][1]) & 2 else [], float(event[0]), true, receipt.prepared_receipt)
		replay.advance(float(event[0]))
	var frames: PackedByteArray = decode_trace(report.frame_trace)
	for frame_index: int in int(report.frame_trace.record_count):
		replay.record_frame(frames.decode_double(frame_index * 8))
	replay.advance(24.0)
	var replay_report: Dictionary = replay.report()
	close_value(float(replay_report.U), float(report.U), "Compact audit replays the measured utility exactly", 0.0)
	check(replay_report.received_pose_trace.sha256 == report.received_pose_trace.sha256 and replay_report.fire_trace.sha256 == report.fire_trace.sha256 and replay_report.render_quality == report.render_quality, "Replay retains exact poses, receipt order, held fire, render gates, and native frame quality")


func test_prepared_proof(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	var row: Dictionary = run.opportunities[0]
	run.advance(float(row.onset_s))
	var snapshot: Array = run.snapshot()
	var ids: Array = []
	for target: Dictionary in snapshot:
		ids.append(target.identity)
	var proof: Dictionary = {"prepare_sequence": 1, "logical_sample_s": run.elapsed_s, "camera_yaw_pitch_deg": [18.123456789012345, -4.0], "vertical_fov_deg": 70.53280043291679, "viewport_px": [1920, 1080], "targets": snapshot.duplicate(true), "ack_source": "unit_fixture_postdraw_not_physical_scanout"}
	var original: Dictionary = proof.duplicate(true)
	run.mark_rendered(ids, [], run.elapsed_s, true, proof)
	proof.camera_yaw_pitch_deg[0] = 99.0
	proof.targets.clear()
	check(row.first_render_ack_receipt == original and row.first_rendered_s == null and row.first_rendered_receipt.is_empty(), "Gaze-away preparation preserves immutable camera and geometry proof without fabricating visibility")
	var visible_proof: Dictionary = original.duplicate(true)
	visible_proof.prepare_sequence = 2
	visible_proof.camera_yaw_pitch_deg = [float(deck.positions[int(row.priority_target_id)].yaw_deg), float(deck.positions[int(row.priority_target_id)].pitch_deg)]
	run.mark_rendered(ids, ids, run.elapsed_s + 0.01, true, visible_proof)
	var saved_visible: Dictionary = visible_proof.duplicate(true)
	visible_proof.targets.clear()
	check(row.first_render_ack_receipt == original and row.first_rendered_receipt == saved_visible, "First prepared acknowledgement and first visible frame retain their separate immutable proofs")
	var next_onset_s: float = float(run.opportunities[1].onset_s)
	run.advance(next_onset_s)
	run.mark_rendered(ids, ids, next_onset_s, true, original)
	check(run.opportunities[1].first_render_ack_s == null and run.opportunities[1].first_rendered_s == null, "An old generation's postdraw IDs cannot attest the new priority")
	var exact: Dictionary = Task.exact_scalar_bits(original)
	var reread: Dictionary = JSON.parse_string(JSON.stringify(exact, "", true, true))
	check(Task.restore_scalar_bits(reread) == original, "Immutable postdraw camera and target scalars retain exact binary64 values through stored JSON")


func test_certified_reacquisition(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	run.queue_pose(0.0, 90.0, 0.0)
	render(run, 0.0)
	var change_s: float = float(run._reversals[0].effective_sign_change_s)
	var target: Dictionary = run.targets[0]
	for step_index: int in 251:
		var time_s: float = change_s + float(step_index) / 1000.0
		var on_target: bool = step_index < 30 or (step_index >= 40 and step_index < 100)
		var pose: Dictionary = run._sample_target(target, time_s)
		run.queue_pose(time_s, float(pose.yaw_deg) if on_target else 90.0, float(pose.pitch_deg) if on_target else 0.0)
		run.advance(time_s)
	run.advance(24.0)
	var report: Dictionary = run.report()
	var reacquisition: Dictionary = report.reacquisitions[0]
	close_value(float(reacquisition.reacquisition_ms), 40.0, "A ten-ms hole cannot fuse two short intervals into a fake fifty-ms stable reacquisition", 1e-7)
	close_value(float(reacquisition.stable_contact_start_s), change_s + 0.04, "Stable date is the start of the first certified continuous fifty-ms interval")
	check(not reacquisition.kept_contact and not reacquisition.censored and reacquisition.stable_contact_required_s == 0.05, "Reacquisition uses certified raw contact and the actual velocity sign change")
	for interval: Array in report.definite_contact_intervals_s:
		check(not (float(interval[0]) < change_s + 0.03 and float(interval[1]) > change_s + 0.04), "Certified contact intervals retain the real ten-ms hole")


func test_eight_kilohertz_audit(deck: Dictionary) -> void:
	var run: RefCounted = begin(deck)
	render(run, 0.0)
	var count: int = 24 * 8000
	for packet_index: int in count:
		var receipt_s: float = float(packet_index) / 8000.0
		run.queue_pose(receipt_s, 0.12345678901234567, -0.7654321098765432)
		if (packet_index + 1) % 16000 == 0:
			run.advance(receipt_s)
			run.record_frame(1.0 / 240.0)
	run.advance(24.0)
	var report: Dictionary = run.report()
	check(report.complete and report.valid and report.received_pose_trace.record_count == count and run.received_pose_trace is PackedByteArray, "An entire 24-second 8-kHz received-pose trace stays mandatory and complete")
	var decoded: PackedByteArray = decode_trace(report.received_pose_trace)
	close_value(decoded.decode_double((count - 1) * Task.POSE_RECORD_BYTES + 8), float(count - 1) / 8000.0, "The final 8-kHz receipt time remains exact binary64", 0.0)
	check(decoded.decode_u32((count - 1) * Task.POSE_RECORD_BYTES + 4) == count, "Eight-kHz trace preserves every receipt sequence without gain or clock resets")
	var serialized_bytes: int = JSON.stringify(report, "", false, true).to_utf8_buffer().size()
	var storage_bytes: int = JSON.stringify(report, "\t", true, true).to_utf8_buffer().size()
	check(serialized_bytes <= Task.MAX_REPORT_BYTES and serialized_bytes == int(report.audit.report_payload_bytes), "The final stored task-report payload remains at most eight MiB")
	check(storage_bytes <= Task.MAX_REPORT_BYTES and storage_bytes == int(report.audit.report_storage_bytes), "Indented full-precision storage also remains below eight MiB")
	print("V2 CAL AUDIT: %d complete poses, %d packed bytes, %d final report bytes." % [count, decoded.size(), serialized_bytes])
