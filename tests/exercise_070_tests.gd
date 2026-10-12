extends SceneTree

const RoutineService: GDScript = preload("res://scripts/training/training_routine_service.gd")
const EXERCISE_IDS: Array[String] = ["C03", "M01", "T10"]
const CALIBRATION_FINGERPRINTS: Dictionary = {
	"C02": "f9b201e83026d6142b07c5bb1eaa81e70a7517dfb6110f63783decba1ab05cb9",
	"C04": "ed8450202b0c9501a9797ac68007992bb1bea320b301bcbf8793ee33d08e7220",
	"S01": "c23d49729798e7257e3498a926e3b075a593df0b44e087019a03438798f86292",
	"T01": "f2f9281888509a3c079f6df139313898d83fe5f76a4e1364eb4bf3966d9803ef",
	"T05": "9b44a5a715828d4343ea9c0771c48798473a3e0972adb7ec68b19574541ecfa0"
}
const CALIBRATION_DIRECTIONS: Dictionary = {
	"C02": [Vector3(-0.09944026172, -0.02216500975, -0.99479663372)],
	"C04": [Vector3(-0.47674265504, -0.06645147502, -0.87652760744)],
	"S01": [Vector3(-0.38745695353, -0.05538870022, -0.92022234201)],
	"T01": [Vector3(-0.16148079932, 0.0, -0.98687583208), Vector3(-0.11869453639, 0.0, -0.99293082952), Vector3(0.03304019198, 0.0, -0.99945402145), Vector3(0.20516501367, 0.0, -0.97872740030)],
	"T05": [Vector3(-0.14858640730, 0.0, -0.98889940977), Vector3(-0.24805584550, 0.0, -0.96874570847), Vector3(0.06392297149, 0.0, -0.99795484543), Vector3(0.02120389417, 0.0, -0.99977517128)]
}

class ReserveOnlyEngine extends ScenarioEngine:
	var random_candidates_checked: int = 0
	var reserve_candidates_checked: int = 0

	func scatter_spawn_angles_deg(target_index: int, time_s: float, random_attempts: int = 128) -> Vector2:
		random_candidates_checked = 0
		reserve_candidates_checked = 0
		return super.scatter_spawn_angles_deg(target_index, time_s, random_attempts)

	func scatter_candidate_is_safe(target_index: int, time_s: float, angles_deg: Vector2) -> bool:
		if random_candidates_checked < 128:
			random_candidates_checked += 1
			return false
		reserve_candidates_checked += 1
		return super.scatter_candidate_is_safe(target_index, time_s, angles_deg)

var assertion_count: int = 0
var failure_count: int = 0
var viewport: SubViewport
var container: Node3D
var camera: Camera3D
var pool: TargetPool


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Les tests exercices 0.7 n'ont pas terminé en 90 secondes.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_tests() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	container = Node3D.new()
	viewport.add_child(container)
	camera = Camera3D.new()
	camera.name = "AimCamera"
	camera.position = Vector3(0.0, ScenarioDefinition.CAMERA_ORIGIN_HEIGHT_M, 0.0)
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 100.0
	container.add_child(camera)
	pool = TargetPool.new()
	container.add_child(pool)
	await process_frame
	test_calibration_contract()
	test_definitions_and_fingerprints()
	test_scatter_separation()
	test_scatter_reserve()
	test_mixed_transitions()
	test_waypoints()
	test_hit_render_and_preview()
	test_frame_replays()
	test_tracking_edges()
	test_routine()
	viewport.queue_free()
	await process_frame
	print("EXERCISE 070 : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_calibration_contract() -> void:
	for scenario_id in CALIBRATION_FINGERPRINTS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		check(definition.revision == 3 and definition.fingerprint() == CALIBRATION_FINGERPRINTS[scenario_id], scenario_id + " conserve son empreinte de calibration r3.")
		var engine := ScenarioEngine.new()
		check(engine.start(definition, 7919, 2.0), scenario_id + " démarre avec sa définition historique.")
		var expected_state: String = "2795282058164943041" if scenario_id == "S01" else "8391613367634471571"
		check(str(engine.rng.state) == expected_state, scenario_id + " conserve exactement ses tirages RNG historiques.")
		var directions: Array = CALIBRATION_DIRECTIONS[scenario_id]
		var times_s: Array[float] = [0.0, 0.25, 1.0, 2.0]
		for time_index in times_s.size():
			check(AimGeometry.angular_error_deg(engine.target_direction(0, times_s[time_index]), directions[mini(time_index, directions.size() - 1)]) < 0.00001, scenario_id + " conserve sa trajectoire r3.")
		var inactive: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
		inactive.small_transition_probability = 0.75
		inactive.waypoint_min_duration_s = 1.2
		inactive.depth_speed_m_s = 0.8
		check(inactive.fingerprint() == definition.fingerprint(), "Les paramètres nouveaux inactifs restent hors empreinte de calibration.")


func test_definitions_and_fingerprints() -> void:
	check(ScenarioCatalog.DEFINITIONS.size() == 18, "Le catalogue expose dix-huit définitions.")
	var scatter: ScenarioDefinition = ScenarioCatalog.find("C03")
	check(scatter.title == "Multi-cibles" and scatter.layout == "scatter" and scatter.active_targets == 6 and scatter.yaw_extent_deg == 22.0 and scatter.pitch_extent_deg == 13.0 and scatter.distance_m == 4.0 and scatter.angular_diameter_deg == 4.8, "C03 expose sa vraie dispersion et son enveloppe 0.7.")
	for scenario_id in EXERCISE_IDS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		check(definition.revision == 5 and definition.validate().is_empty(), scenario_id + " est une définition r5 valide.")
		check(definition.fits_view(75.0, 1.0) and definition.minimum_surface_height_m() > 0.0, scenario_id + " valide toute son enveloppe, silhouette et sol compris.")
		var cosmetic: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
		cosmetic.title = "Traduction"
		cosmetic.instructions = "Autre consigne"
		check(cosmetic.fingerprint() == definition.fingerprint(), "Les textes restent hors empreinte mécanique.")
		for settings in [{"distance_m": NAN}, {"distance_m": 0.09}, {"distance_m": 8.1}, {"pitch_extent_deg": 25.0, "distance_m": 8.0}, {"yaw_extent_deg": 40.0}, {"revision": 4, "motion": "waypoints"}]:
			check_rejected(definition, settings)
	var mixed: ScenarioDefinition = ScenarioCatalog.find("M01")
	for field in ["small_transition_min_deg", "small_transition_max_deg", "large_transition_min_deg", "large_transition_max_deg", "small_transition_probability", "angular_diameter_min_deg", "angular_diameter_max_deg", "yaw_extent_deg", "pitch_extent_deg", "distance_m"]:
		var changed: ScenarioDefinition = mixed.duplicate() as ScenarioDefinition
		changed.set(field, float(changed.get(field)) + 0.1)
		check(changed.fingerprint() != mixed.fingerprint(), "M01 versionne le paramètre actif " + field + ".")
	for settings in [{"spawn_pattern": "unknown"}, {"active_targets": 2}, {"motion": "horizontal"}, {"small_transition_probability": 0.0}, {"small_transition_probability": 1.0}, {"small_transition_probability": INF}, {"small_transition_min_deg": -1.0}, {"small_transition_max_deg": 21.0}, {"large_transition_min_deg": 29.0}, {"large_transition_max_deg": 19.0}, {"angular_diameter_min_deg": 0.0}, {"angular_diameter_max_deg": 3.0}]:
		check_rejected(mixed, settings)
	var tracking: ScenarioDefinition = ScenarioCatalog.find("T10")
	for field in ["speed_deg_s", "depth_speed_m_s", "waypoint_min_duration_s", "distance_min_m", "distance_max_m", "angular_diameter_deg", "angular_diameter_min_deg", "angular_diameter_max_deg"]:
		var changed: ScenarioDefinition = tracking.duplicate() as ScenarioDefinition
		changed.set(field, float(changed.get(field)) + 0.1)
		check(changed.fingerprint() != tracking.fingerprint(), "T10 versionne le paramètre actif " + field + ".")
	for settings in [{"waypoint_min_duration_s": 0.0}, {"waypoint_min_duration_s": NAN}, {"depth_speed_m_s": INF}, {"depth_speed_m_s": 0.0}, {"depth_speed_m_s": 5.1}, {"lifetime_s": 1.0}, {"family": "click"}, {"distance_min_m": 0.0}, {"distance_max_m": 8.1}, {"angular_diameter_max_deg": 5.0}, {"angular_diameter_min_deg": 3.3}]:
		check_rejected(tracking, settings)
	check_rejected(scatter, {"yaw_extent_deg": 10.0})
	check_rejected(scatter, {"angular_diameter_deg": 6.0})


func check_rejected(source: ScenarioDefinition, settings: Dictionary) -> void:
	var changed: ScenarioDefinition = source.duplicate() as ScenarioDefinition
	for field in settings:
		changed.set(field, settings[field])
	check(not changed.validate().is_empty(), source.scenario_id + " refuse " + str(settings) + ".")


func check_bounds(engine: ScenarioEngine, target_index: int, time_s: float) -> void:
	var geometry: Dictionary = engine.target_geometry(target_index, time_s)
	var direction: Vector3 = geometry.direction
	var radius_m: float = float(geometry.radius_m)
	var center: Vector3 = camera.global_position + Vector3(geometry.center_offset_m)
	var angles_deg: Vector2 = engine.angles_from_direction_deg(direction)
	check(absf(angles_deg.x) <= engine.definition.yaw_extent_deg + 0.00001 and absf(angles_deg.y) <= engine.definition.pitch_extent_deg + 0.00001, "Le centre reste dans la zone déclarée.")
	check(center.y - radius_m > 0.0 and center.z - radius_m > -11.9, "Toute la sphère reste au-dessus du sol et devant le mur.")
	var contained: bool = true
	for plane in camera.get_frustum():
		contained = contained and plane.distance_to(center) <= -radius_m + 0.00001
	check(contained, "Les six plans du frustum contiennent la sphère, near/far compris.")
	check(absf(rad_to_deg(2.0 * asin(radius_m / float(geometry.distance_m))) - float(geometry.angular_diameter_deg)) < 0.000001, "Rayon et silhouette angulaire partagent la même géométrie.")


func check_separation(engine: ScenarioEngine, time_s: float) -> void:
	var minimum_deg: float = 180.0
	for first_index in engine.targets.size():
		for second_index in range(first_index + 1, engine.targets.size()):
			minimum_deg = minf(minimum_deg, AimGeometry.angular_error_deg(engine.target_direction(first_index, time_s), engine.target_direction(second_index, time_s)))
	check(minimum_deg >= engine.definition.maximum_angular_diameter_deg() * 1.7 - 0.00001 and engine.invalid_reason.is_empty(), "C03 conserve six silhouettes séparées après chaque apparition.")


func test_scatter_separation() -> void:
	var positions: Dictionary = {}
	var extrema_deg := Rect2(Vector2.ZERO, Vector2.ZERO)
	for seed_value in 100:
		var engine := ScenarioEngine.new()
		check(engine.start(ScenarioCatalog.find("C03"), seed_value, 60.0), "C03 démarre pour chacune des cent graines.")
		for shot_index in 64:
			var time_s: float = float(shot_index + 1) * 0.2
			var target_index: int = shot_index % 6
			check_separation(engine, time_s)
			check_bounds(engine, target_index, time_s)
			var previous: Vector3 = engine.target_direction(target_index, time_s)
			check(engine.shoot(time_s, previous), "Les remplacements passent par de vrais impacts C03.")
			var direction: Vector3 = engine.target_direction(target_index, time_s)
			var angles_deg: Vector2 = engine.angles_from_direction_deg(direction)
			positions[angles_deg] = true
			extrema_deg = extrema_deg.expand(angles_deg)
			check(AimGeometry.angular_error_deg(previous, direction) >= engine.definition.min_transition_deg - 0.00001, "C03 garantit le temps et la distance entre deux apparitions.")
			check(float(engine.targets[target_index].born_s) == time_s, "C03 conserve le timestamp exact de remplacement.")
			check_separation(engine, time_s)
	check(positions.size() > 6000 and extrema_deg.size.x > 43.0 and extrema_deg.size.y > 25.0, "C03 utilise des coordonnées continues dans toute la zone, sans grille cachée.")


func test_scatter_reserve() -> void:
	for seed_value in 100:
		var engine := ReserveOnlyEngine.new()
		check(engine.start(ScenarioCatalog.find("C03"), seed_value, 60.0), "La réserve certifiée initialise six cibles sans tirage accepté.")
		for shot_index in 32:
			var time_s: float = float(shot_index + 1) * 0.25
			var target_index: int = shot_index % 6
			var previous: Vector3 = engine.target_direction(target_index, time_s)
			check(engine.shoot(time_s, previous), "La réserve remplace une cible sans poser un candidat en échec.")
			check(engine.random_candidates_checked == 128 and engine.reserve_candidates_checked >= 1 and engine.reserve_candidates_checked <= 8, "Après 128 candidats refusés, le repli réussit en huit contrôles au maximum.")
			check_separation(engine, time_s)
			check_bounds(engine, target_index, time_s)
			check(AimGeometry.angular_error_deg(previous, engine.target_direction(target_index, time_s)) >= engine.definition.min_transition_deg - 0.00001, "La réserve respecte aussi la transition minimale.")
	var engine := ScenarioEngine.new()
	engine.start(ScenarioCatalog.find("C03"), 7919, 60.0)
	for shot_index in 128:
		var target_index: int = shot_index % 6
		var time_s: float = float(shot_index + 1) * 0.2
		var fallback_deg: Vector2 = engine.scatter_spawn_angles_deg(target_index, time_s, 0)
		check(fallback_deg.is_finite() and engine.scatter_candidate_is_safe(target_index, time_s, fallback_deg), "La réserve reste disponible face à cinq positions continues arbitraires.")
		engine.initialize_new_target(target_index, time_s, fallback_deg)
		check_separation(engine, time_s)
		engine.shoot(time_s + 0.1, engine.target_direction((target_index + 1) % 6, time_s + 0.1))


func test_mixed_transitions() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("M01")
	var total_small: int = 0
	var observed_sizes: Dictionary = {}
	var observed_orders: Dictionary = {}
	for seed_value in 100:
		var engine := ScenarioEngine.new()
		var replay := ScenarioEngine.new()
		check(engine.start(definition, seed_value, 60.0) and replay.start(definition, seed_value, 60.0), "M01 démarre ses replays appariés.")
		var seen: Dictionary = {}
		var order: String = ""
		for shot_index in 64:
			var time_s: float = float(shot_index + 1) * 0.2
			var previous: Vector3 = engine.target_direction(0, time_s)
			check(engine.shoot(time_s, previous) and replay.shoot(time_s, replay.target_direction(0, time_s)), "M01 rejoue les clics exacts.")
			var kind: String = str(engine.targets[0].transition_kind)
			var separation_deg: float = AimGeometry.angular_error_deg(previous, engine.target_direction(0, time_s))
			var minimum_deg: float = definition.small_transition_min_deg if kind == "small" else definition.large_transition_min_deg
			var maximum_deg: float = definition.small_transition_max_deg if kind == "small" else definition.large_transition_max_deg
			check(separation_deg >= minimum_deg - 0.00001 and separation_deg <= maximum_deg + 0.00001, "La transition M01 correspond à la plage réellement tirée.")
			seen[kind] = true
			order += "s" if kind == "small" else "L"
			total_small += 1 if kind == "small" else 0
			var diameter_deg: float = engine.target_angular_diameter_deg(0, time_s)
			observed_sizes[diameter_deg] = true
			check(diameter_deg >= 2.5 and diameter_deg <= 4.2 and engine.targets.size() == 1, "M01 utilise une sphère de diamètre variable explicite.")
			check(engine.targets == replay.targets and engine.rng.state == replay.rng.state, "Les transitions et tailles M01 sont entièrement seedées.")
			check_bounds(engine, 0, time_s)
		check(seen.size() == 2 and (order.contains("ss") or order.contains("LL")), "Chaque replay mélange petits et grands gestes sans alternance imposée.")
		observed_orders[order] = true
	check(total_small > 2800 and total_small < 3600 and observed_sizes.size() > 6000 and observed_orders.size() == 100, "M01 renouvelle types, destinations et tailles selon la graine.")
	var good := ScenarioEngine.new()
	var poor := ScenarioEngine.new()
	good.start(definition, 7919, 60.0)
	poor.start(definition, 7919, 60.0)
	for shot_index in 20:
		var time_s: float = float(shot_index + 1) * 0.2
		good.shoot(time_s, good.target_direction(0, time_s))
		poor.shoot(time_s, Vector3.BACK)
		poor.spawn_target(0, time_s)
		check(good.targets == poor.targets and good.definition.fingerprint() == poor.definition.fingerprint(), "Les performances ne modifient ni distribution ni difficulté M01.")
	check(good.hits == 20 and poor.hits == 0, "Le contrôle d'adaptation compare réellement des réussites différentes.")


func test_waypoints() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("T10")
	var sequences: Dictionary = {}
	for seed_value in [0, 1, 42, 7919, -1, 2147483647]:
		var engine := ScenarioEngine.new()
		var replay := ScenarioEngine.new()
		check(engine.start(definition, seed_value, 120.0) and replay.start(definition, seed_value, 120.0), "T10 démarre une trajectoire de deux minutes.")
		var target: Dictionary = engine.targets[0]
		var poses: Array[Vector3] = target.waypoint_poses
		var times_s: PackedFloat64Array = target.waypoint_times_s
		var kinds: PackedStringArray = target.waypoint_kinds
		sequences[str(poses)] = true
		var seen: Dictionary = {}
		var forward_seen: bool = false
		var backward_seen: bool = false
		for segment_index in kinds.size():
			seen[kinds[segment_index]] = true
			forward_seen = forward_seen or poses[segment_index + 1].z < poses[segment_index].z
			backward_seen = backward_seen or poses[segment_index + 1].z > poses[segment_index].z
			check(times_s[segment_index + 1] - times_s[segment_index] >= definition.waypoint_min_duration_s - 0.000000000001, "Les destinations T10 ont une durée minimale explicite.")
			var midpoint_s: float = (times_s[segment_index] + times_s[segment_index + 1]) * 0.5
			check(engine.waypoint_pose(target, midpoint_s).is_equal_approx((poses[segment_index] + poses[segment_index + 1]) * 0.5), "L'interpolation T10 atteint le milieu sans dépendre d'une frame.")
			if segment_index > 0:
				var boundary_s: float = times_s[segment_index]
				check(engine.waypoint_pose(target, boundary_s - 0.0001).distance_to(poses[segment_index]) < 0.00001 and engine.waypoint_pose(target, boundary_s + 0.0001).distance_to(poses[segment_index]) < 0.00001, "Les virages T10 restent continus avec vitesse nulle au waypoint.")
		check(seen.size() == 4 and forward_seen and backward_seen and times_s[times_s.size() - 1] >= 120.0, "T10 couvre latéral, vertical, diagonal, avant et arrière sur tout l'horizon.")
		var bounded_speed: bool = true
		var pure_geometry: bool = true
		var stable_radius: bool = true
		var radius_m: float = definition.distance_m * sin(deg_to_rad(definition.angular_diameter_deg * 0.5))
		var initial_rng_state: int = engine.rng.state
		var previous: Dictionary = engine.target_geometry(0, 0.0)
		for sample_index in range(1, 120 * 120 + 1):
			var time_s: float = float(sample_index) / 120.0
			var geometry: Dictionary = engine.target_geometry(0, time_s)
			bounded_speed = bounded_speed and AimGeometry.angular_error_deg(previous.direction, geometry.direction) * 120.0 <= definition.speed_deg_s + 0.003 and absf(float(geometry.distance_m) - float(previous.distance_m)) * 120.0 <= definition.depth_speed_m_s + 0.001
			stable_radius = stable_radius and absf(float(geometry.radius_m) - radius_m) < 0.00000001
			if sample_index % 120 == 0:
				check_bounds(engine, 0, time_s)
				pure_geometry = pure_geometry and geometry == replay.target_geometry(0, time_s)
				engine.target_geometry(0, 120.0 - time_s)
				pure_geometry = pure_geometry and geometry == engine.target_geometry(0, time_s)
			previous = geometry
		check(bounded_speed and stable_radius, "T10 borne les vitesses angulaire et radiale et conserve une sphère physique stable.")
		check(pure_geometry and engine.rng.state == initial_rng_state and engine.targets == replay.targets, "Les lectures T10 sont pures, rejouables et sans tirage RNG pendant le rendu.")
	check(sequences.size() == 6, "Les six graines T10 génèrent six trajectoires distinctes.")


func test_hit_render_and_preview() -> void:
	for scenario_id in EXERCISE_IDS:
		var engine := ScenarioEngine.new()
		engine.start(ScenarioCatalog.find(scenario_id), 7919, 60.0)
		var preview := ScenarioPreview.new()
		preview.size = Vector2(320.0, 180.0)
		viewport.add_child(preview)
		preview.configure(engine.definition, false)
		preview.advance_demo(4.2)
		for time_s in [0.0, 0.37, 2.7, 17.5, 59.0]:
			pool.sync(engine, time_s)
			for target_index in engine.targets.size():
				var geometry: Dictionary = engine.target_geometry(target_index, time_s)
				var sphere: MeshInstance3D = pool.spheres[target_index]
				check(sphere.visible and (sphere.global_position - camera.global_position).is_equal_approx(geometry.center_offset_m) and sphere.global_basis.get_scale().is_equal_approx(Vector3.ONE * float(geometry.radius_m)), "Le mesh rendu utilise exactement le centre et rayon analytiques.")
				check(float(geometry.radius_m) == engine.radius_m(target_index, time_s) and float(geometry.angular_diameter_deg) == engine.target_angular_diameter_deg(target_index, time_s) and float(geometry.distance_m) == engine.target_distance_m(target_index, time_s), "Toutes les API partagent les mêmes fonctions temporelles.")
				var direction: Vector3 = geometry.direction
				var tangent: Vector3 = direction.cross(Vector3.UP).normalized()
				var inside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 - 0.01)
				var outside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 + 0.01)
				var inside: Vector3 = direction * cos(inside_rad) + tangent * sin(inside_rad)
				var outside: Vector3 = direction * cos(outside_rad) + tangent * sin(outside_rad)
				check(not is_inf(AimGeometry.ray_sphere_distance(inside, geometry.center_offset_m, float(geometry.radius_m))) and is_inf(AimGeometry.ray_sphere_distance(outside, geometry.center_offset_m, float(geometry.radius_m))), "Les rayons intérieur et extérieur correspondent à la silhouette courante.")
				check_bounds(engine, target_index, time_s)
		for target_index in preview.engine.targets.size():
			var geometry: Dictionary = preview.engine.target_geometry(target_index, preview.elapsed_s)
			check(preview.target_outline(target_index, preview.elapsed_s) == AimGeometry.project_sphere_outline(geometry.direction, float(geometry.angular_diameter_deg), preview.vertical_fov_deg, preview.projection_rect()), "L'aperçu utilise directement la géométrie stable du moteur.")
		preview.queue_free()
		if scenario_id != "T10":
			var edge_engine := ScenarioEngine.new()
			edge_engine.start(engine.definition, 7919, 2.0)
			var geometry: Dictionary = edge_engine.target_geometry(0, 0.3)
			var direction: Vector3 = geometry.direction
			var tangent: Vector3 = direction.cross(Vector3.UP).normalized()
			var outside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 + 0.01)
			var inside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 - 0.01)
			check(not edge_engine.shoot(0.3, direction * cos(outside_rad) + tangent * sin(outside_rad)) and edge_engine.shoot(0.31, direction * cos(inside_rad) + tangent * sin(inside_rad)), "Les vrais clics ratent au-delà du bord et touchent à l'intérieur.")


func test_frame_replays() -> void:
	for scenario_id in EXERCISE_IDS:
		for seed_value in [0, 42, 7919]:
			var reference: Dictionary = {}
			for frame_rate in [60, 144, 240]:
				var engine := ScenarioEngine.new()
				engine.start(ScenarioCatalog.find(scenario_id), seed_value, 6.003)
				if scenario_id == "T10":
					for event_index in 6004:
						var time_s: float = minf(float(event_index) / 1000.0, 6.003)
						var angles_deg: Vector2 = engine.angles_from_direction_deg(engine.target_direction(0, time_s))
						engine.record_aim(time_s, angles_deg.x + (4.0 if event_index % 900 < 300 else 0.0), angles_deg.y)
				var shot_index: int = 0
				var next_shot_s: float = 0.19
				for frame_index in range(1, ceili(6.003 * frame_rate) + 1):
					var end_s: float = minf(float(frame_index) / frame_rate, 6.003)
					if scenario_id != "T10":
						while next_shot_s <= end_s + 0.000000001 and next_shot_s < 6.003:
							var direction: Vector3 = engine.target_geometry(shot_index % engine.targets.size(), next_shot_s).direction
							var angles_deg: Vector2 = engine.angles_from_direction_deg(direction)
							engine.record_aim(next_shot_s, angles_deg.x, angles_deg.y)
							engine.shoot(next_shot_s, Vector3.BACK if shot_index % 3 == 0 else direction)
							shot_index += 1
							next_shot_s = float(shot_index + 1) * 0.19
					engine.record_frame(1.0 / frame_rate)
					engine.advance_to(end_s)
				var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
				var snapshot: Dictionary = {"targets": engine.targets.duplicate(true), "rng_state": engine.rng.state, "metrics": report.metrics, "score": report.score}
				check(report.valid and report.completed and report.score_version == 1 and ScoringService.validate_result(report).is_empty(), "Le replay produit un rapport valide avec le score V1 existant.")
				if scenario_id == "T10":
					check(engine.on_target_s > 3.0 and engine.on_target_s < 5.0 and engine.shots == 0, "Le replay T10 mesure réellement pertes et réacquisitions sans clic.")
				else:
					check(engine.shots == 31 and engine.hits == 20, "Le replay de clic exerce vingt touches et onze ratés.")
				if reference.is_empty():
					reference = snapshot
				else:
					check(snapshot == reference, scenario_id + " garde RNG, géométrie, métriques et score à 60/144/240 FPS.")


func test_tracking_edges() -> void:
	for inside in [false, true]:
		var reference: Dictionary = {}
		for frame_rate in [60, 144, 240]:
			var engine := ScenarioEngine.new()
			engine.start(ScenarioCatalog.find("T10"), 42, 12.003)
			for event_index in 12004:
				var time_s: float = minf(float(event_index) / 1000.0, 12.003)
				var geometry: Dictionary = engine.target_geometry(0, time_s)
				var direction: Vector3 = geometry.direction
				var tangent: Vector3 = direction.cross(Vector3.UP).normalized()
				var offset_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 + (-0.15 if inside else 0.15))
				var angles_deg: Vector2 = engine.angles_from_direction_deg(direction * cos(offset_rad) + tangent * sin(offset_rad))
				engine.record_aim(time_s, angles_deg.x, angles_deg.y)
			for frame_index in range(1, ceili(12.003 * frame_rate) + 1):
				engine.advance_to(minf(float(frame_index) / frame_rate, 12.003))
			var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			check(absf(engine.on_target_s - (12.003 if inside else 0.0)) < 0.00000001 and is_equal_approx(float(report.metrics.target_exposed_time_s), 12.003), "Le tracking intègre le bord de la silhouette en perspective et la fraction finale.")
			if reference.is_empty():
				reference = report.metrics
			else:
				check(reference == report.metrics, "Le bord dynamique T10 conserve ses métriques à tous les FPS.")


func test_routine() -> void:
	var service: RoutineService = RoutineService.new()
	check(service.current_stage(0).is_empty(), "La routine inactive n'expose aucune étape.")
	for duration_s in [45.0, 60.0]:
		check(service.begin(duration_s) and service.plan.size() == 3, "La routine accepte trois étapes de 45 ou 60 secondes.")
		for stage_index in 3:
			var stage: Dictionary = service.current_stage(stage_index)
			var expected_id: String = ["M01", "T10", "S02"][stage_index]
			check(stage == {"scenario_id": expected_id, "duration_s": duration_s, "index": stage_index, "total": 3, "title": ScenarioCatalog.find(expected_id).title}, "Le contrat d'étape expose uniquement les champs d'intégration prévus.")
			stage.title = "Mutation externe"
			check(service.current_stage(stage_index).title != stage.title, "La lecture d'étape ne permet pas de modifier le plan.")
			var engine := ScenarioEngine.new()
			check(engine.start(ScenarioCatalog.find(expected_id), 7919, duration_s), "Chaque étape de routine réutilise le moteur réel.")
			engine.advance_to(duration_s)
			check(engine.completed and engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true).valid, "Chaque étape atteint sa durée finale sans score agrégé inventé.")
		check(service.current_stage(-1).is_empty() and service.current_stage(3).is_empty(), "La fin du plan et les indices invalides n'exposent aucune étape supplémentaire.")
	for duration_s in [0.0, 30.0, 46.0, NAN, INF]:
		check(not service.begin(duration_s) and service.plan.is_empty(), "La routine refuse une durée hors contrat et ne garde aucun plan périmé.")
