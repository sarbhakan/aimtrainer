extends SceneTree

const TRACKING_IDS: Array[String] = ["T01", "T02", "T03", "T04", "T05", "T09", "T10"]
const SEEDS: Array[int] = [-1, 0, 1, 42, 7919, 2147483647]
const REPLAY_DURATION_S: float = 24.013
const HISTORICAL_PARAMETERS: Dictionary = {
	"C01": ["C01", 3, "click", "static", "scatter", 3.2, 14.0, 8.0, 4.0, 12.0, 1, 0.0, 2.0, 4.5],
	"C02": ["C02", 3, "click", "static", "scatter", 2.5, 6.0, 4.0, 3.0, 12.0, 1, 0.0, 1.6, 3.0],
	"C03": ["C03", 5, "click", "static", "scatter", 4.8, 22.0, 13.0, 5.5, 12.0, 6, 0.0, 3.0, 4.0, "bounded_scatter_v1"],
	"C04": ["C04", 3, "click", "static", "scatter", 3.2, 30.0, 12.0, 20.0, 12.0, 1, 0.0, 1.8, 5.0],
	"C05": ["C05", 3, "click", "static", "scatter", 0.7, 16.0, 9.0, 2.5, 12.0, 6, 0.0, 2.4, 7.0],
	"C07": ["C07", 3, "click", "static", "scatter", 3.0, 3.0, 20.0, 10.0, 12.0, 1, 0.0, 2.0, 3.0],
	"D01": ["D01", 4, "click", "static", "scatter", 3.4, 16.0, 9.0, 4.5, 12.0, 1, 1.0, 2.0, 4.0, ["angular_diameter_range_deg", 3.0, 3.8], ["diameter_motion", "shrink"]],
	"D02": ["D02", 4, "click", "reactive", "scatter", 3.0, 16.0, 6.0, 3.5, 14.0, 1, 0.0, 1.8, 3.5, 0.24],
	"T01": ["T01", 3, "tracking", "horizontal", "scatter", 4.0, 16.0, 2.0, 2.5, 12.0, 1, 0.0, 2.0, 4.0],
	"T02": ["T02", 3, "tracking", "vertical", "scatter", 3.6, 2.0, 16.0, 2.5, 12.0, 1, 0.0, 2.0, 3.5],
	"T03": ["T03", 3, "tracking", "diagonal", "scatter", 3.4, 16.0, 10.0, 2.5, 16.0, 1, 0.0, 2.0, 4.5],
	"T04": ["T04", 3, "tracking", "circle", "scatter", 3.4, 15.0, 11.0, 2.5, 18.0, 1, 0.0, 2.0, 5.0],
	"T05": ["T05", 3, "tracking", "strafe", "scatter", 3.6, 16.0, 2.0, 2.5, 26.0, 1, 0.0, 2.0, 3.0, 0.16],
	"T09": ["T09", 3, "tracking", "horizontal", "scatter", 0.9, 8.0, 2.0, 2.5, 6.0, 1, 0.0, 2.0, 8.0],
	"S01": ["S01", 3, "switching", "static", "scatter", 3.4, 24.0, 10.0, 6.0, 12.0, 4, 0.0, 2.8, 4.5],
	"S02": ["S02", 4, "switching", "horizontal", "lanes", 3.2, 22.0, 12.0, 4.0, 16.0, 4, 0.0, 2.4, 5.0, ["distance_range_m", 3.5, 5.5]],
	"M01": ["M01", 5, "click", "static", "scatter", 3.4, 28.0, 12.0, 2.5, 12.0, 1, 0.0, 2.0, 4.0, ["angular_diameter_range_deg", 2.5, 4.2], ["mixed_transitions_v1", 2.5, 6.0, 20.0, 44.0, 0.5]],
	"T10": ["T10", 5, "tracking", "waypoints", "scatter", 4.0, 20.0, 12.0, 2.5, 18.0, 1, 0.0, 2.0, 4.0, ["angular_diameter_range_deg", 3.0, 5.5], ["distance_range_m", 3.0, 5.0], ["diameter_motion", "perspective"], ["waypoints_3d_v1", 0.6, 1.2]]
}
const HISTORICAL_LIFETIMES_S: Dictionary = {
	"C01": 3.0, "C02": 3.0, "C03": 4.0, "C04": 3.0, "C05": 6.0, "C07": 3.0,
	"D01": 1.0, "D02": 3.0, "T01": 10.0, "T02": 10.0, "T03": 10.0, "T04": 10.0,
	"T05": 10.0, "T09": 10.0, "S01": 4.0, "S02": 5.0, "M01": 3.0, "T10": 10.0
}
const HISTORICAL_DIRECTIONS: Dictionary = {
	"T01": [Vector3(-0.16148079932, 0.0, -0.98687583208), Vector3(-0.11869453639, 0.0, -0.99293082952), Vector3(0.03304019198, 0.0, -0.99945402145), Vector3(0.20516501367, 0.0, -0.97872740030)],
	"T05": [Vector3(-0.14858640730, 0.0, -0.98889940977), Vector3(-0.24805584550, 0.0, -0.96874570847), Vector3(0.06392297149, 0.0, -0.99795484543), Vector3(0.02120389417, 0.0, -0.99977517128)]
}

var assertion_count: int = 0
var failure_count: int = 0
var viewport: SubViewport
var camera: Camera3D
var pool: TargetPool


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("Les rythmes de suivi n’ont pas terminé leur validation en 120 secondes.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func check_close(actual: float, expected: float, tolerance: float, description: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= tolerance,
		"%s ; obtenu=%.12f attendu=%.12f tolérance=%.12f" % [description, actual, expected, tolerance])


func separation_deg(first_direction: Vector3, second_direction: Vector3) -> float:
	return rad_to_deg(atan2(first_direction.cross(second_direction).length(), first_direction.dot(second_direction)))


func engine_for(definition: ScenarioDefinition, seed_value: int, duration_s: float = REPLAY_DURATION_S) -> ScenarioEngine:
	var engine := ScenarioEngine.new()
	var started := engine.start(definition, seed_value, duration_s)
	check(started, "Démarrage seed=%d : %s" % [seed_value, engine.invalid_reason])
	return engine if started else null


func run_tests() -> void:
	test_catalog_and_validation()
	test_exact_queries()
	await process_frame
	test_seeded_schedules()
	test_narrow_cadence_bounds()
	await process_frame
	prepare_pool()
	await process_frame
	test_geometry_and_query_purity()
	await process_frame
	test_renewal_and_jumps()
	await process_frame
	test_pause_and_metric_replays()
	await process_frame
	test_historical_motion_and_protocols()
	viewport.queue_free()
	await process_frame
	print("TRACKING RHYTHM : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func historical_fingerprint(scenario_id: String, lifecycle: bool) -> String:
	var parameters: Array = HISTORICAL_PARAMETERS[scenario_id].duplicate(true)
	if lifecycle:
		parameters[1] = 6
		var lifetime_s: float = HISTORICAL_LIFETIMES_S[scenario_id]
		parameters[11] = lifetime_s
		var minimum_diameter_deg: float = parameters[5]
		for parameter in parameters.duplicate():
			if parameter is Array and parameter[0] == "angular_diameter_range_deg":
				minimum_diameter_deg = float(parameter[1])
			if parameter is Array and parameter == ["diameter_motion", "shrink"]:
				parameters.erase(parameter)
		if parameters[4] == "scatter" and int(parameters[10]) > 1 and not "bounded_scatter_v1" in parameters:
			parameters.append("bounded_scatter_v1")
		var ratio: float = clampf(0.55 / minimum_diameter_deg, 0.65, 0.85) if parameters[2] == "tracking" else clampf(1.5 / minimum_diameter_deg, 0.35, 0.75)
		parameters.append(["lifecycle_v1", ratio, lifetime_s * 0.85, lifetime_s * 1.15])
	return JSON.stringify(parameters).sha256_text()


func test_catalog_and_validation() -> void:
	check(ScenarioCatalog.lifecycle_definitions().size() == 18, "Les dix-huit références publiques 0.8 r6 restent disponibles.")
	check(ScenarioCatalog.practice_definitions().size() == 18, "Le catalogue courant contient toujours dix-huit exercices.")
	var tracking_count: int = 0
	var other_count: int = 0
	for scenario_id in HISTORICAL_PARAMETERS:
		var base := ScenarioCatalog.find(scenario_id)
		var lifecycle := ScenarioCatalog.find_lifecycle(scenario_id)
		var practice := ScenarioCatalog.find_practice(scenario_id)
		check(base != null and lifecycle != null and practice != null, "Trois références accessibles : " + scenario_id)
		if base == null or lifecycle == null or practice == null:
			continue
		check(base.fingerprint() == historical_fingerprint(scenario_id, false), "Empreinte de base figée avant les rythmes : " + scenario_id)
		check(lifecycle.revision == 6 and lifecycle.fingerprint() == historical_fingerprint(scenario_id, true), "Empreinte publique 0.8 r6 exacte : " + scenario_id)
		check(not base.has_tracking_rhythm() and not lifecycle.has_tracking_rhythm(), "Aucun rythme activé rétroactivement : " + scenario_id)
		for definition in [base, lifecycle, practice]:
			check(definition.validate().is_empty(), "Définition valide : %s r%d %s" % [scenario_id, definition.revision, definition.validate()])
			check(ScenarioCatalog.resolve(scenario_id, definition.fingerprint()) == definition, "Résolution exacte de %s r%d" % [scenario_id, definition.revision])
		if scenario_id in TRACKING_IDS:
			tracking_count += 1
			check(practice.revision == 7 and practice.has_lifecycle() and practice.has_tracking_rhythm(), "Le suivi actuel utilise r7 et son cycle de vie : " + scenario_id)
			check(practice.fingerprint() != lifecycle.fingerprint() and practice.motion == lifecycle.motion, "Le rythme change la difficulté et conserve la forme : " + scenario_id)
			check(practice.tracking_speed_min_deg_s > 0.0 and practice.tracking_speed_max_deg_s > practice.tracking_speed_min_deg_s and practice.tracking_ramp_acceleration_deg_s2 > 0.0, "Bornes explicites de vitesse et accélération : " + scenario_id)
			for field in ["tracking_speed_min_deg_s", "tracking_speed_max_deg_s", "tracking_ramp_acceleration_deg_s2"]:
				var changed := practice.duplicate() as ScenarioDefinition
				changed.set(field, float(changed.get(field)) * 1.01)
				check(changed.validate().is_empty() and changed.fingerprint() != practice.fingerprint(), "Le champ %s participe à l’empreinte : %s" % [field, scenario_id])
		else:
			other_count += 1
			check(practice.revision == 6 and practice.fingerprint() == lifecycle.fingerprint() and not practice.has_tracking_rhythm(), "Le clic/switching conserve sa difficulté r6 : " + scenario_id)
		check(ScenarioCatalog.resolve(scenario_id, "unknown-fingerprint") == null, "Une empreinte inconnue ne résout aucune variante : " + scenario_id)
	check(tracking_count == 7 and other_count == 11, "Exactement sept suivis r7 et onze autres exercices r6.")
	var source := ScenarioCatalog.find_practice("T01")
	if source == null:
		return
	var invalid_mutations: Array[Dictionary] = [
		{"revision": 6}, {"family": "click"}, {"family": "switching"}, {"motion": "static"},
		{"lifecycle_shrink_ratio": 0.0, "lifetime_min_s": 0.0, "lifetime_max_s": 0.0},
		{"tracking_speed_min_deg_s": 0.0}, {"tracking_speed_min_deg_s": -1.0},
		{"tracking_speed_min_deg_s": source.tracking_speed_max_deg_s},
		{"tracking_speed_max_deg_s": source.tracking_speed_min_deg_s * 0.5},
		{"tracking_speed_max_deg_s": 0.0}, {"tracking_speed_max_deg_s": -1.0},
		{"tracking_ramp_acceleration_deg_s2": 0.0}, {"tracking_ramp_acceleration_deg_s2": -1.0}
	]
	for field in ["tracking_speed_min_deg_s", "tracking_speed_max_deg_s", "tracking_ramp_acceleration_deg_s2"]:
		for non_finite in [NAN, INF, -INF]:
			invalid_mutations.append({field: non_finite})
	for mutation in invalid_mutations:
		var bad := source.duplicate() as ScenarioDefinition
		for field in mutation:
			bad.set(field, mutation[field])
		check(not bad.validate().is_empty(), "Refus du rythme invalide : " + str(mutation))


func test_exact_queries() -> void:
	var fixture := {
		"times_s": PackedFloat64Array([0.0, 2.0, 3.0, 3.25, 5.25, 6.25]),
		"speeds_deg_s": PackedFloat64Array([0.0, 12.0, 0.0, 0.0, -12.0, -12.0]),
		"distances_deg": PackedFloat64Array([0.0, 12.0, 18.0, 18.0, 6.0, -6.0]),
		"kinds": PackedStringArray(["accelerate", "brake", "pause", "restart", "hold"])
	}
	var cases: Array[Array] = [
		[0.0, 0.0, 0.0, "accelerate"], [0.5, 1.875, 0.328125, "accelerate"],
		[1.0, 6.0, 2.25, "accelerate"], [1.5, 10.125, 6.328125, "accelerate"],
		[2.0, 12.0, 12.0, "brake"], [2.25, 10.125, 14.8359375, "brake"],
		[2.5, 6.0, 16.875, "brake"], [3.0, 0.0, 18.0, "pause"],
		[3.125, 0.0, 18.0, "pause"], [3.25, 0.0, 18.0, "restart"],
		[3.75, -1.875, 17.671875, "restart"], [4.25, -6.0, 15.75, "restart"],
		[4.75, -10.125, 11.671875, "restart"], [5.25, -12.0, 6.0, "hold"],
		[6.25, -12.0, -6.0, "hold"]
	]
	var snapshot := fixture.duplicate(true)
	for pass_index in 2:
		for case_index in cases.size():
			var sample: Array = cases[case_index if pass_index == 0 else cases.size() - case_index - 1]
			var age_s: float = sample[0]
			check_close(TrackingRhythm.speed_deg_s(fixture, age_s), sample[1], 0.000000001, "Rampe analytique âge=%.6f s" % age_s)
			check_close(TrackingRhythm.distance_deg(fixture, age_s), sample[2], 0.000000001, "Intégrale analytique signée âge=%.6f s" % age_s)
			check(TrackingRhythm.phase_at(fixture, age_s) == sample[3], "Frontière de phase âge=%.6f : obtenu=%s attendu=%s" % [age_s, TrackingRhythm.phase_at(fixture, age_s), sample[3]])
	check(fixture == snapshot, "Les requêtes analytiques ne modifient pas leur calendrier.")
	var many_times_s := PackedFloat64Array([0.0])
	var many_speeds_deg_s := PackedFloat64Array([3.0])
	var many_distances_deg := PackedFloat64Array([0.0])
	var many_kinds := PackedStringArray()
	for segment_index in 257:
		var duration_s := 0.02 + float(segment_index % 11) * 0.013
		many_times_s.append(many_times_s[-1] + duration_s)
		many_speeds_deg_s.append(3.0)
		many_distances_deg.append(many_times_s[-1] * 3.0)
		many_kinds.append("segment-%d" % segment_index)
	var many := {"times_s": many_times_s, "speeds_deg_s": many_speeds_deg_s, "distances_deg": many_distances_deg, "kinds": many_kinds}
	for segment_index in range(256, -1, -1):
		for age_s in [many_times_s[segment_index], lerpf(many_times_s[segment_index], many_times_s[segment_index + 1], 0.37)]:
			check(TrackingRhythm.phase_at(many, age_s) == many_kinds[segment_index], "Recherche des frontières non uniformes segment=%d âge=%.9f" % [segment_index, age_s])
			check_close(TrackingRhythm.distance_deg(many, age_s), age_s * 3.0, 0.000000001, "Intégrale sur 257 segments âge=%.9f" % age_s)


func schedule_has_shape(schedule: Dictionary, context: String) -> bool:
	var fields_present: bool = schedule.has_all(["times_s", "speeds_deg_s", "distances_deg", "kinds"])
	check(fields_present, "Calendrier incomplet : " + context)
	if not fields_present:
		return false
	var arrays_typed: bool = schedule.times_s is PackedFloat64Array and schedule.speeds_deg_s is PackedFloat64Array and schedule.distances_deg is PackedFloat64Array and schedule.kinds is PackedStringArray
	check(arrays_typed, "Types des tableaux du calendrier : " + context)
	if not arrays_typed:
		return false
	var lengths_match: bool = schedule.times_s.size() >= 2 and schedule.speeds_deg_s.size() == schedule.times_s.size() and schedule.distances_deg.size() == schedule.times_s.size() and schedule.kinds.size() == schedule.times_s.size() - 1
	check(lengths_match, "Nombre de frontières et segments : " + context)
	return lengths_match


func test_seeded_schedules() -> void:
	for scenario_id in TRACKING_IDS:
		var definition := ScenarioCatalog.find_practice(scenario_id)
		if definition == null:
			continue
		for seed_value in SEEDS:
			for lifetime_s in [definition.lifetime_min_s, definition.lifetime_max_s]:
				var context := "%s seed=%d id=17 vie=%.6f" % [scenario_id, seed_value, lifetime_s]
				var schedule := TrackingRhythm.build(definition, seed_value, 17, lifetime_s)
				var snapshot := schedule.duplicate(true)
				check(schedule == TrackingRhythm.build(definition, seed_value, 17, lifetime_s), "Reconstruction seedée exacte : " + context)
				check(schedule != TrackingRhythm.build(definition, seed_value, 18, lifetime_s), "Le calendrier dépend de l’identité de cible : " + context)
				check(schedule != TrackingRhythm.build(definition, seed_value ^ 7919, 17, lifetime_s), "Le calendrier dépend de la graine : " + context)
				if not schedule_has_shape(schedule, context):
					continue
				verify_schedule(definition, schedule, lifetime_s, context)
				check(schedule == snapshot, "Ordre de requête sans mutation : " + context)


func verify_schedule(definition: ScenarioDefinition, schedule: Dictionary, lifetime_s: float, context: String) -> void:
	var times_s: PackedFloat64Array = schedule.times_s
	var speeds_deg_s: PackedFloat64Array = schedule.speeds_deg_s
	var distances_deg: PackedFloat64Array = schedule.distances_deg
	var kinds: PackedStringArray = schedule.kinds
	check(times_s[0] == 0.0 and distances_deg[0] == 0.0 and times_s[-1] >= lifetime_s, "Origine et couverture du cycle : " + context)
	var pause_count: int = 0
	var positive_motion: bool = false
	var negative_motion: bool = false
	var minimum_hold_deg_s: float = INF
	var maximum_hold_deg_s: float = 0.0
	var acceleration_duration_s: float = 0.0
	var brake_duration_s: float = 0.0
	var acceleration_count: int = 0
	var brake_count: int = 0
	var cadence_tolerance_deg_s: float = definition.tracking_speed_max_deg_s * 0.0000001
	for segment_index in range(kinds.size() - 1, -1, -1):
		var start_s: float = times_s[segment_index]
		var duration_s: float = times_s[segment_index + 1] - start_s
		var start_speed_deg_s: float = speeds_deg_s[segment_index]
		var end_speed_deg_s: float = speeds_deg_s[segment_index + 1]
		var segment_context := "%s segment=%d phase=%s" % [context, segment_index, kinds[segment_index]]
		check(is_finite(start_s) and is_finite(duration_s) and duration_s > 0.0 and is_finite(start_speed_deg_s) and is_finite(end_speed_deg_s) and is_finite(distances_deg[segment_index]), "Frontières finies et strictement ordonnées : " + segment_context)
		if duration_s <= 0.0 or not is_finite(duration_s):
			continue
		check(absf(start_speed_deg_s) <= definition.tracking_speed_max_deg_s + cadence_tolerance_deg_s and absf(end_speed_deg_s) <= definition.tracking_speed_max_deg_s + cadence_tolerance_deg_s, "Vitesses de frontière bornées : %s v0=%.12f v1=%.12f max=%.12f" % [segment_context, start_speed_deg_s, end_speed_deg_s, definition.tracking_speed_max_deg_s])
		check(start_speed_deg_s * end_speed_deg_s >= 0.0, "Une inversion passe par une frontière à zéro : " + segment_context)
		check_close(distances_deg[segment_index + 1] - distances_deg[segment_index], duration_s * (start_speed_deg_s + end_speed_deg_s) * 0.5, 0.000000001, "Intégrale exacte aux frontières : " + segment_context)
		var peak_acceleration_deg_s2 := 1.5 * absf(end_speed_deg_s - start_speed_deg_s) / duration_s
		check(peak_acceleration_deg_s2 <= definition.tracking_ramp_acceleration_deg_s2 + 0.000000001, "Pic de rampe borné : %s obtenu=%.9f borne=%.9f" % [segment_context, peak_acceleration_deg_s2, definition.tracking_ramp_acceleration_deg_s2])
		if start_s < lifetime_s:
			positive_motion = positive_motion or maxf(start_speed_deg_s, end_speed_deg_s) > 0.0
			negative_motion = negative_motion or minf(start_speed_deg_s, end_speed_deg_s) < 0.0
		if kinds[segment_index] == "hold":
			check(start_speed_deg_s == end_speed_deg_s and absf(start_speed_deg_s) >= definition.tracking_speed_min_deg_s - cadence_tolerance_deg_s, "Plateau mobile constant dans les bornes : %s obtenu=%.12f min=%.12f" % [segment_context, start_speed_deg_s, definition.tracking_speed_min_deg_s])
			minimum_hold_deg_s = minf(minimum_hold_deg_s, absf(start_speed_deg_s))
			maximum_hold_deg_s = maxf(maximum_hold_deg_s, absf(start_speed_deg_s))
		elif kinds[segment_index] == "pause":
			check(start_speed_deg_s == 0.0 and end_speed_deg_s == 0.0 and duration_s >= 0.18 - 0.000000001 and duration_s <= 0.35 + 0.000000001, "Arrêt nul de 180 à 350 ms : %s durée=%.12f" % [segment_context, duration_s])
			if times_s[segment_index + 1] < lifetime_s:
				pause_count += 1
			check(segment_index > 0 and segment_index + 2 < speeds_deg_s.size(), "Arrêt encadré par frein et reprise : " + segment_context)
			if segment_index > 0 and segment_index + 2 < speeds_deg_s.size():
				check(speeds_deg_s[segment_index - 1] * speeds_deg_s[segment_index + 2] < 0.0, "La reprise après arrêt inverse réellement le signe : " + segment_context)
		elif kinds[segment_index] == "accelerate":
			check(absf(end_speed_deg_s) > absf(start_speed_deg_s), "Une accélération augmente la vitesse : " + segment_context)
			acceleration_duration_s += duration_s
			acceleration_count += 1
		elif kinds[segment_index] == "brake":
			check(absf(end_speed_deg_s) < absf(start_speed_deg_s), "Un freinage réduit la vitesse : " + segment_context)
			brake_duration_s += duration_s
			brake_count += 1
		elif kinds[segment_index] == "restart":
			check(start_speed_deg_s == 0.0 and absf(end_speed_deg_s) >= definition.tracking_speed_min_deg_s - cadence_tolerance_deg_s, "La reprise part de zéro vers une vitesse mobile : %s obtenu=%.12f min=%.12f" % [segment_context, end_speed_deg_s, definition.tracking_speed_min_deg_s])
		else:
			check(false, "Phase inconnue : " + segment_context)
		for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875]:
			var age_s: float = start_s + duration_s * fraction
			var smooth_fraction: float = 3.0 * fraction * fraction - 2.0 * fraction * fraction * fraction
			var expected_speed_deg_s: float = start_speed_deg_s + (end_speed_deg_s - start_speed_deg_s) * smooth_fraction
			var expected_distance_deg: float = distances_deg[segment_index] + duration_s * (start_speed_deg_s * fraction + (end_speed_deg_s - start_speed_deg_s) * (pow(fraction, 3.0) - 0.5 * pow(fraction, 4.0)))
			check_close(TrackingRhythm.speed_deg_s(schedule, age_s), expected_speed_deg_s, 0.00000001, "Vitesse smoothstep âge=%.9f : %s" % [age_s, segment_context])
			check_close(TrackingRhythm.distance_deg(schedule, age_s), expected_distance_deg, 0.00000001, "Distance intégrée âge=%.9f : %s" % [age_s, segment_context])
			check(TrackingRhythm.phase_at(schedule, age_s) == kinds[segment_index], "Phase recherchée à âge=%.9f : %s" % [age_s, segment_context])
			if fraction > 0.0:
				var delta_s: float = minf(0.00001, duration_s * 0.001)
				var derivative_deg_s: float = (TrackingRhythm.distance_deg(schedule, age_s + delta_s) - TrackingRhythm.distance_deg(schedule, age_s - delta_s)) / (2.0 * delta_s)
				check_close(derivative_deg_s, expected_speed_deg_s, 0.00001, "La dérivée de la distance est la vitesse âge=%.9f : %s" % [age_s, segment_context])
		if segment_index > 0:
			var epsilon_s: float = minf(0.000001, duration_s * 0.001)
			check_close(TrackingRhythm.distance_deg(schedule, start_s - epsilon_s), distances_deg[segment_index], definition.tracking_speed_max_deg_s * epsilon_s * 1.01, "Continuité gauche de la distance : " + segment_context)
			check_close(TrackingRhythm.speed_deg_s(schedule, start_s - epsilon_s), start_speed_deg_s, 0.00001, "Continuité gauche de la vitesse : " + segment_context)
	check(pause_count > 0 and positive_motion and negative_motion, "Arrêt et inversion observables avant expiration : " + context)
	check(maximum_hold_deg_s > minimum_hold_deg_s + (definition.tracking_speed_max_deg_s - definition.tracking_speed_min_deg_s) * 0.001, "Plusieurs vitesses mobiles, pas une vitesse constante : %s min=%.9f max=%.9f" % [context, minimum_hold_deg_s, maximum_hold_deg_s])
	check(acceleration_count > 0 and brake_count > 0, "Accélérations et freinages présents : " + context)
	if acceleration_count > 0 and brake_count > 0:
		check(acceleration_duration_s / acceleration_count > brake_duration_s / brake_count, "Les accélérations sont plus lentes que les freinages en moyenne : " + context)
	check_close(TrackingRhythm.distance_deg(schedule, times_s[-1]), distances_deg[-1], 0.000000001, "Dernière frontière exacte : " + context)
	check_close(TrackingRhythm.speed_deg_s(schedule, times_s[-1]), speeds_deg_s[-1], 0.000000001, "Vitesse à la dernière frontière : " + context)


func test_narrow_cadence_bounds() -> void:
	var definition := ScenarioCatalog.find_practice("T01").duplicate() as ScenarioDefinition
	definition.tracking_speed_min_deg_s = definition.tracking_speed_max_deg_s * 0.999
	check(definition.validate().is_empty(), "Une plage de cadence personnalisée étroite reste valide : " + definition.validate())
	for seed_value in SEEDS:
		var context := "cadence étroite seed=%d min=%.9f max=%.9f" % [seed_value, definition.tracking_speed_min_deg_s, definition.tracking_speed_max_deg_s]
		var schedule := TrackingRhythm.build(definition, seed_value, 31, definition.lifetime_max_s)
		if schedule_has_shape(schedule, context):
			verify_schedule(definition, schedule, definition.lifetime_max_s, context)
		var engine := engine_for(definition, seed_value)
		if engine == null or not engine.targets[0].has("tracking_rhythm"):
			check(false, "Le moteur accepte le rythme personnalisé étroit : " + context)
			continue
		var physical_speed_below_cadence: bool = false
		for sample_index in 96:
			var age_s: float = float(engine.targets[0].lifetime_s) * float(sample_index) / 96.0
			var delta_s: float = 0.002
			var speed_deg_s: float = separation_deg(engine.target_direction(0, age_s), engine.target_direction(0, age_s + delta_s)) / delta_s
			physical_speed_below_cadence = physical_speed_below_cadence or speed_deg_s < definition.tracking_speed_min_deg_s
			check(speed_deg_s <= definition.tracking_speed_max_deg_s + 0.03, "Le maximum physique est respecté avec cadence étroite : %s âge=%.9f obtenu=%.9f" % [context, age_s, speed_deg_s])
		check(physical_speed_below_cadence, "Le minimum de cadence n’impose aucun minimum physique près des virages ou arrêts : " + context)


func prepare_pool() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var container := Node3D.new()
	viewport.add_child(container)
	camera = Camera3D.new()
	camera.name = "AimCamera"
	camera.position = Vector3(0.0, ScenarioDefinition.CAMERA_ORIGIN_HEIGHT_M, 0.0)
	camera.fov = 75.0
	container.add_child(camera)
	pool = TargetPool.new()
	container.add_child(pool)


func test_geometry_and_query_purity() -> void:
	for scenario_id in TRACKING_IDS:
		for seed_value in [1, 42, 7919]:
			var engine := engine_for(ScenarioCatalog.find_practice(scenario_id), seed_value)
			var historical := engine_for(ScenarioCatalog.find_lifecycle(scenario_id), seed_value)
			if engine == null or historical == null:
				continue
			var target: Dictionary = engine.targets[0]
			var context := "%s seed=%d id=%d" % [scenario_id, seed_value, target.id]
			check(target.has("tracking_rhythm"), "Le moteur attache le calendrier à la cible : " + context)
			if not target.has("tracking_rhythm") or not schedule_has_shape(target.tracking_rhythm, context):
				continue
			var schedule: Dictionary = target.tracking_rhythm
			check(schedule == TrackingRhythm.build(engine.definition, seed_value, int(target.id), float(target.lifetime_s)), "Calendrier construit après fixation de la durée et de l’identité : " + context)
			var geometry_without_rhythm := target.duplicate(true)
			geometry_without_rhythm.erase("tracking_rhythm")
			check(geometry_without_rhythm == historical.targets[0] and engine.rng.state == historical.rng.state, "L’ajout du calendrier ne consomme pas le RNG géométrique initial : " + context)
			var snapshot := engine.targets.duplicate(true)
			var rng_state: int = engine.rng.state
			var lifetime_s: float = target.lifetime_s
			for sample_index in range(95, -1, -1):
				var age_s: float = lifetime_s * float(sample_index) / 96.0
				var geometry := engine.target_geometry(0, age_s)
				var direction: Vector3 = geometry.direction
				var angles_deg := engine.angles_from_direction_deg(direction)
				var sample_context := "%s âge=%.9f" % [context, age_s]
				check(absf(angles_deg.x) <= engine.definition.yaw_extent_deg + 0.00001 and absf(angles_deg.y) <= engine.definition.pitch_extent_deg + 0.00001, "Enveloppe angulaire préservée : " + sample_context)
				check(AimGeometry.sphere_fits_view(direction, geometry.angular_diameter_deg, 75.0, 16.0 / 9.0), "La silhouette entière reste cadrée : " + sample_context)
				var virtual_s: float = TrackingRhythm.distance_deg(schedule, age_s) / engine.definition.speed_deg_s
				var expected_time_s: float = absf(virtual_s) if engine.definition.motion == "waypoints" else virtual_s
				check(separation_deg(direction, historical.target_direction(0, expected_time_s)) < 0.00002, "La distance signée réutilise la forme historique : %s horloge=%.9f" % [sample_context, expected_time_s])
				var depth_time_s: float = expected_time_s if engine.definition.motion == "waypoints" else 0.0
				check_close(float(geometry.distance_m), historical.target_distance_m(0, depth_time_s), 0.000001, "La profondeur utilise la même horloge virtuelle : " + sample_context)
				var delta_s: float = 0.002
				var later := engine.target_geometry(0, age_s + delta_s)
				var angular_speed_deg_s: float = separation_deg(direction, later.direction) / delta_s
				check(angular_speed_deg_s <= engine.definition.tracking_speed_max_deg_s + 0.03, "Vitesse angulaire réelle bornée : %s obtenu=%.9f max=%.9f" % [sample_context, angular_speed_deg_s, engine.definition.tracking_speed_max_deg_s])
				if engine.definition.motion == "waypoints":
					var depth_speed_m_s: float = absf(float(later.distance_m) - float(geometry.distance_m)) / delta_s
					var depth_bound_m_s: float = engine.definition.depth_speed_m_s * engine.definition.tracking_speed_max_deg_s / engine.definition.speed_deg_s
					check(depth_speed_m_s <= depth_bound_m_s + 0.0001 and geometry.distance_m >= engine.definition.distance_min_m and geometry.distance_m <= engine.definition.distance_max_m, "Profondeur et vitesse mises à l’échelle : %s obtenu=%.9f borne=%.9f" % [sample_context, depth_speed_m_s, depth_bound_m_s])
				if sample_index % 12 == 0:
					verify_hitbox_and_pool(engine, age_s, sample_context)
			verify_motion_stops(engine, schedule, context)
			check(engine.targets == snapshot and engine.rng.state == rng_state and engine.elapsed_s == 0.0 and engine.integrated_s == 0.0 and engine.shots == 0, "Les requêtes de mouvement/géométrie restent pures malgré leur ordre inverse : " + context)
			check(engine.target_geometry(0, lifetime_s * 0.31) == engine.target_geometry(0, lifetime_s * 0.31), "Une pose répétée est exactement reproductible : " + context)


func verify_hitbox_and_pool(engine: ScenarioEngine, age_s: float, context: String) -> void:
	var geometry := engine.target_geometry(0, age_s)
	var direction: Vector3 = geometry.direction
	var diameter_deg: float = geometry.angular_diameter_deg
	var radius_m: float = geometry.radius_m
	check_close(radius_m, float(geometry.distance_m) * sin(deg_to_rad(diameter_deg) * 0.5), 0.000000001, "Rayon de silhouette et hitbox identiques : " + context)
	var base_diameter_deg: float = engine.base_target_angular_diameter_deg(0, age_s)
	var age_fraction: float = age_s / float(engine.targets[0].lifetime_s)
	check_close(diameter_deg, base_diameter_deg * lerpf(1.0, engine.definition.lifecycle_shrink_ratio, age_fraction), 0.000000001, "Le rétrécissement suit l’âge réel pendant les variations de vitesse : " + context)
	var perpendicular := direction.cross(Vector3.UP).normalized()
	var half_angle_rad: float = deg_to_rad(diameter_deg * 0.5)
	var inside := (direction * cos(half_angle_rad * 0.98) + perpendicular * sin(half_angle_rad * 0.98)).normalized()
	var outside := (direction * cos(half_angle_rad * 1.02) + perpendicular * sin(half_angle_rad * 1.02)).normalized()
	check(not is_inf(AimGeometry.ray_sphere_distance(inside, geometry.center_offset_m, radius_m)) and is_inf(AimGeometry.ray_sphere_distance(outside, geometry.center_offset_m, radius_m)), "Les rayons de part et d’autre du bord visible correspondent à la collision : " + context)
	pool.sync(engine, age_s)
	var sphere: MeshInstance3D = pool.spheres[0]
	check(sphere.visible and sphere.global_position.distance_to(camera.global_position + Vector3(geometry.center_offset_m)) < 0.000001, "Le pool place la sphère au centre de la hitbox : " + context)
	check(sphere.global_basis.get_scale().distance_to(Vector3.ONE * radius_m) < 0.000001, "La sphère rendue utilise exactement le rayon de collision : " + context)


func verify_motion_stops(engine: ScenarioEngine, schedule: Dictionary, context: String) -> void:
	var times_s: PackedFloat64Array = schedule.times_s
	var kinds: PackedStringArray = schedule.kinds
	var observed_pause: bool = false
	for segment_index in kinds.size():
		if kinds[segment_index] != "pause" or times_s[segment_index + 1] >= float(engine.targets[0].lifetime_s):
			continue
		observed_pause = true
		var first_s: float = lerpf(times_s[segment_index], times_s[segment_index + 1], 0.1)
		var second_s: float = lerpf(times_s[segment_index], times_s[segment_index + 1], 0.9)
		var first := engine.target_geometry(0, first_s)
		var second := engine.target_geometry(0, second_s)
		check(first.direction == second.direction and first.distance_m == second.distance_m, "Un arrêt de rythme fige la position et la profondeur : %s segment=%d" % [context, segment_index])
		check(float(second.angular_diameter_deg) < float(first.angular_diameter_deg), "Un arrêt de mouvement conserve le vieillissement de la hitbox : " + context)
	check(observed_pause, "Au moins un arrêt moteur observable avant expiration : " + context)


func test_renewal_and_jumps() -> void:
	for scenario_id in TRACKING_IDS:
		for seed_value in [1, 42]:
			var direct := engine_for(ScenarioCatalog.find_practice(scenario_id), seed_value)
			var stepped := engine_for(ScenarioCatalog.find_practice(scenario_id), seed_value)
			if direct == null or stepped == null:
				continue
			var first_schedule: Dictionary = direct.targets[0].get("tracking_rhythm", {}).duplicate(true)
			var first_id: int = direct.targets[0].id
			direct.advance_to(REPLAY_DURATION_S)
			for frame_index in ceili(REPLAY_DURATION_S * 144.0):
				stepped.advance_to(minf(float(frame_index + 1) / 144.0, REPLAY_DURATION_S))
			var context := "%s seed=%d" % [scenario_id, seed_value]
			check(direct.targets == stepped.targets and direct.rng.state == stepped.rng.state and direct.expired == stepped.expired, "Saut de plusieurs vies identique aux frames : " + context)
			check(direct.expired >= 2 and int(direct.targets[0].id) > first_id, "Chaque expiration renouvelle réellement l’identité : " + context)
			var target: Dictionary = direct.targets[0]
			check(target.has("tracking_rhythm"), "Le remplacement conserve un calendrier : " + context)
			if target.has("tracking_rhythm"):
				check(target.tracking_rhythm != first_schedule and target.tracking_rhythm == TrackingRhythm.build(direct.definition, seed_value, int(target.id), float(target.lifetime_s)), "Le renouvellement utilise graine, nouvelle identité et durée finale : " + context)
				check_close(TrackingRhythm.distance_deg(target.tracking_rhythm, 0.0), 0.0, 0.0, "La nouvelle horloge locale repart de zéro : " + context)
				check_close(direct.target_angular_diameter_deg(0, float(target.born_s)), direct.base_target_angular_diameter_deg(0, float(target.born_s)), 0.000000001, "La nouvelle silhouette repart à sa taille initiale : " + context)
				var shape_reference := engine_for(ScenarioCatalog.find_lifecycle(scenario_id), seed_value)
				if shape_reference != null:
					shape_reference.targets[0] = target.duplicate(true)
					shape_reference.targets[0].erase("tracking_rhythm")
					for age_fraction in [0.0, 0.17, 0.53, 0.91]:
						var age_s: float = float(target.lifetime_s) * age_fraction
						var virtual_s: float = TrackingRhythm.distance_deg(target.tracking_rhythm, age_s) / direct.definition.speed_deg_s
						var historical_time_s: float = float(target.born_s) + (absf(virtual_s) if direct.definition.motion == "waypoints" else virtual_s)
						var actual_time_s: float = float(target.born_s) + age_s
						check(separation_deg(direct.target_direction(0, actual_time_s), shape_reference.target_direction(0, historical_time_s)) < 0.00002, "Après renouvellement, l’horloge utilise l’âge depuis la nouvelle naissance : %s naissance=%.9f âge=%.9f" % [context, float(target.born_s), age_s])
						check_close(direct.target_distance_m(0, actual_time_s), shape_reference.target_distance_m(0, historical_time_s), 0.000001, "La profondeur renouvelée utilise aussi l’âge local : " + context)
			check_close(direct.integrated_s, REPLAY_DURATION_S, 0.000000001, "Le saut inclut les frontières et le dernier fragment : " + context)
			check(direct.error_histogram == stepped.error_histogram and direct.reacquisition_ms == stepped.reacquisition_ms, "Le saut conserve histogramme et réacquisitions : " + context)
			check_close(direct.on_target_s, stepped.on_target_s, 0.000000001, "Le saut conserve le temps sur cible : " + context)
			check_close(direct.angular_error_sum_deg_s, stepped.angular_error_sum_deg_s, 0.000000001, "Le saut conserve l’intégrale d’erreur : " + context)
	var definition := ScenarioCatalog.find_practice("T10").duplicate() as ScenarioDefinition
	definition.lifetime_s = 0.503
	definition.lifetime_min_s = 0.503
	definition.lifetime_max_s = 0.503
	var partial := engine_for(definition, 42, 1.009)
	if partial != null:
		partial.advance_to(1.009)
		check(partial.expired == 2, "Deux expirations de rythme entre ticks à 0,503 et 1,006 s.")
		check_close(partial.integrated_s, 1.009, 0.000000001, "Le fragment final de trois ms n’est pas perdu.")
		var report := partial.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
		check(ScoringService.validate_result(report).is_empty(), "Rapport cohérent après deux renouvellements entre ticks : " + ScoringService.validate_result(report))


func replay(scenario_id: String, fps: int, with_pause: bool) -> ScenarioEngine:
	var engine := engine_for(ScenarioCatalog.find_practice(scenario_id), 42)
	if engine == null:
		return null
	for pose_index in ceili(REPLAY_DURATION_S * 240.0):
		var time_s: float = float(pose_index) / 240.0
		engine.record_aim(time_s, sin(time_s * 1.7) * 10.0, cos(time_s * 0.9) * 7.0)
	engine.record_aim(REPLAY_DURATION_S, sin(REPLAY_DURATION_S * 1.7) * 10.0, cos(REPLAY_DURATION_S * 0.9) * 7.0)
	for frame_index in ceili(REPLAY_DURATION_S * fps):
		var time_s: float = minf(float(frame_index + 1) / fps, REPLAY_DURATION_S)
		engine.advance_to(time_s)
		if with_pause and frame_index == fps * 4 - 1:
			var targets_before := engine.targets.duplicate(true)
			var rng_before: int = engine.rng.state
			var timeline_before: int = engine.timeline.event_count
			var histogram_before := engine.error_histogram.duplicate()
			var report_before := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, false)
			engine.paused = true
			engine.record_aim(time_s + 0.001, 88.0, 88.0)
			engine.advance_to(REPLAY_DURATION_S)
			check(engine.targets == targets_before and engine.rng.state == rng_before and engine.timeline.event_count == timeline_before and engine.error_histogram == histogram_before and engine.elapsed_s == time_s and not engine.completed, "Pause sans vieillissement, tirage ni mesure : %s %d FPS" % [scenario_id, fps])
			var report_after := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, false)
			check(report_before == report_after, "Rapport intégralement figé pendant la pause : %s %d FPS" % [scenario_id, fps])
			engine.paused = false
	return engine


func test_pause_and_metric_replays() -> void:
	for scenario_id in TRACKING_IDS:
		var reference := replay(scenario_id, 240, false)
		if reference == null:
			continue
		var reference_report := reference.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
		check(ScoringService.validate_result(reference_report).is_empty(), "Replay r7 mesurable et cohérent : " + scenario_id + " " + ScoringService.validate_result(reference_report))
		check(reference.integrated_s > 24.0 and reference.expired >= 2 and reference_report.metrics.input_buffer_overflows == 0, "Replay non vide avec renouvellements et aucun overflow : " + scenario_id)
		check(reference.shots == 0 and reference.hits == 0 and reference_report.metrics.misses == 0 and reference_report.score_version == ScoringService.VERSION, "Le rythme de suivi conserve son score V1 sans fabriquer de tirs : " + scenario_id)
		for fps in [60, 144, 240]:
			var candidate := replay(scenario_id, fps, true)
			if candidate == null:
				continue
			var report := candidate.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			var context := "%s %d FPS avec pause" % [scenario_id, fps]
			check(candidate.targets == reference.targets and candidate.rng.state == reference.rng.state and candidate.expired == reference.expired, "Calendriers et RNG du replay identiques : " + context)
			check(report.metrics == reference_report.metrics and report.score == reference_report.score, "Toutes les métriques et le score sont indépendants des frames : %s obtenu=%s attendu=%s" % [context, str(report.metrics), str(reference_report.metrics)])
			check(candidate.error_histogram == reference.error_histogram and candidate.reacquisition_ms == reference.reacquisition_ms, "Histogramme et échantillons de réacquisition identiques : " + context)
			check(ScoringService.validate_result(report).is_empty() and report.comparison_key == reference_report.comparison_key, "Rapport valide dans le même contexte après reprise : " + context)
			check_close(candidate.integrated_s, REPLAY_DURATION_S, 0.000000001, "Exposition complète après reprise : " + context)


func test_historical_motion_and_protocols() -> void:
	for scenario_id in HISTORICAL_DIRECTIONS:
		for lifecycle in [false, true]:
			var definition := ScenarioCatalog.find_lifecycle(scenario_id) if lifecycle else ScenarioCatalog.find(scenario_id)
			var engine := engine_for(definition, 7919)
			if engine == null:
				continue
			var expected_random := RandomNumberGenerator.new()
			expected_random.seed = 7919
			for draw_index in (4 if lifecycle else 3):
				expected_random.randf()
			check(engine.rng.state == expected_random.state, "Nombre de tirages historiques inchangé : %s r%d" % [scenario_id, definition.revision])
			var times_s: Array[float] = [0.0, 0.25, 1.0, 2.0]
			for sample_index in times_s.size():
				var expected_direction: Vector3 = HISTORICAL_DIRECTIONS[scenario_id][sample_index]
				check(separation_deg(engine.target_direction(0, times_s[sample_index]), expected_direction) < 0.00001, "Contre-exemple géométrique historique : %s r%d seed=7919 âge=%.3f" % [scenario_id, definition.revision, times_s[sample_index]])
			check(not engine.targets[0].has("tracking_rhythm"), "Aucun calendrier sur une ancienne cible : " + scenario_id)
	for scenario_id in TRACKING_IDS:
		var old := engine_for(ScenarioCatalog.find_lifecycle(scenario_id), 42)
		if old == null:
			continue
		old.advance_to(REPLAY_DURATION_S)
		check(old.expired >= 2 and not old.targets[0].has("tracking_rhythm") and not old.definition.has_tracking_rhythm(), "Les renouvellements r6 restent sans rythme : " + scenario_id)
		var modern := engine_for(ScenarioCatalog.find_practice(scenario_id), 42)
		if modern != null:
			check(ScoringService.comparison_key(old.definition, REPLAY_DURATION_S, SensitivityService.default_profile(), 16.0 / 9.0) != ScoringService.comparison_key(modern.definition, REPLAY_DURATION_S, SensitivityService.default_profile(), 16.0 / 9.0), "Les records r6 et r7 restent séparés : " + scenario_id)
	for protocol in [4, 5, 6]:
		var service := ProgressiveCalibrationService.new()
		var started := service.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "rhythm-protocol-%d" % protocol, 60.0, true, protocol)
		check(started, "Reconstruction explicite du protocole %d : %s" % [protocol, service.error])
		if not started:
			continue
		var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(service.checkpoint(), "\t", true, true))
		var restored := ProgressiveCalibrationService.new()
		check(restored.restore(checkpoint) and restored.protocol_version == protocol, "Reprise JSON du protocole %d : %s" % [protocol, restored.error])
		for scenario_id in ProgressiveCalibrationService.SCENARIOS:
			var expected := ScenarioCatalog.find(scenario_id) if protocol == 4 else ScenarioCatalog.find_lifecycle(scenario_id) if protocol == 5 else ScenarioCatalog.find_practice(scenario_id)
			var actual := restored.definition_for(scenario_id)
			check(actual != null and actual.fingerprint() == expected.fingerprint() and actual.has_tracking_rhythm() == (protocol == 6 and scenario_id in TRACKING_IDS), "Conditions conservées après JSON : protocole=%d scénario=%s" % [protocol, scenario_id])
		var bad := checkpoint.duplicate(true)
		bad.scenario_fingerprints.T01 = ScenarioCatalog.find_lifecycle("T01").fingerprint() if protocol == 6 else ScenarioCatalog.find_practice("T01").fingerprint()
		var rejected := ProgressiveCalibrationService.new()
		check(not rejected.restore(bad), "Une empreinte r6/r7 substituée ne réinterprète pas le protocole %d." % protocol)
	var latest := ProgressiveCalibrationService.new()
	check(latest.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "rhythm-latest") and latest.protocol_version == 6, "Une nouvelle calibration adopte le protocole 6.")
