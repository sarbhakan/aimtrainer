extends SceneTree

const PATTERN_IDS: Array[String] = ["D01", "D02", "S02"]
const SEEDS: Array[int] = [1, 23, 42, 57, 1337, 7919]
const CALIBRATION_FINGERPRINTS: Dictionary = {
	"C02": "f9b201e83026d6142b07c5bb1eaa81e70a7517dfb6110f63783decba1ab05cb9",
	"C04": "ed8450202b0c9501a9797ac68007992bb1bea320b301bcbf8793ee33d08e7220",
	"S01": "c23d49729798e7257e3498a926e3b075a593df0b44e087019a03438798f86292",
	"T01": "f2f9281888509a3c079f6df139313898d83fe5f76a4e1364eb4bf3966d9803ef",
	"T05": "9b44a5a715828d4343ea9c0771c48798473a3e0972adb7ec68b19574541ecfa0"
}
const ARCHIVE_FINGERPRINTS: Dictionary = {
	"C02": "a7fa138239543b4a6640556a2ada4bf2b969e1fbe0d41e478d8a1bb7b6f82602",
	"C04": "03334159e7e3601d16d4e79edbfef121a92198d5e4c017a2d81891b29aedcf92",
	"S01": "2d35b015e4b51ec81c0a21c26c0f9e0aba9da9f89125ff9115e80172b64e1f08",
	"T01": "57d0ba43baf2b2a130b269dc7ee0186bb6d8d88d6a0821ab5607de788f39fb7f",
	"T05": "661fcda2e1c27988d1463b20762f7d0152d4a4c5e1f322a985154612262e9bdf"
}
const CALIBRATION_DIRECTIONS: Dictionary = {
	"C02": [Vector3(-0.09944026172, -0.02216500975, -0.99479663372)],
	"C04": [Vector3(-0.47674265504, -0.06645147502, -0.87652760744)],
	"S01": [Vector3(-0.38745695353, -0.05538870022, -0.92022234201)],
	"T01": [Vector3(-0.16148079932, 0.0, -0.98687583208), Vector3(-0.11869453639, 0.0, -0.99293082952), Vector3(0.03304019198, 0.0, -0.99945402145), Vector3(0.20516501367, 0.0, -0.97872740030)],
	"T05": [Vector3(-0.14858640730, 0.0, -0.98889940977), Vector3(-0.24805584550, 0.0, -0.96874570847), Vector3(0.06392297149, 0.0, -0.99795484543), Vector3(0.02120389417, 0.0, -0.99977517128)]
}

var assertion_count: int = 0
var failure_count: int = 0
var viewport: SubViewport
var container: Node3D
var camera: Camera3D
var pool: TargetPool


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Les tests de variation n'ont pas terminé en 45 secondes.")
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
	test_catalog_and_fingerprints()
	test_seeded_variations()
	test_diameter_temporal_function()
	test_reactive_motion()
	test_hit_render_consistency()
	test_preview_physical_silhouette()
	test_fixed_difficulty()
	test_frame_rate_replays()
	test_tracking_semantics()
	test_bounds_and_invalid()
	test_grid_respawns()
	viewport.queue_free()
	await process_frame
	print("PATTERN VARIATION : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_calibration_contract() -> void:
	var archived: Dictionary = CalibrationRevisionArchive.definitions()
	for scenario_id in CALIBRATION_FINGERPRINTS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		check(definition.revision == 3 and definition.fingerprint() == CALIBRATION_FINGERPRINTS[scenario_id], scenario_id + " : l'empreinte de calibration publiée doit rester identique.")
		check(not definition.has_diameter_variation() and not definition.has_distance_variation(), scenario_id + " : aucun nouveau paramètre ne doit être activé pour la calibration.")
		var engine := ScenarioEngine.new()
		check(engine.start(definition, 7919, 2.0), scenario_id + " : la mécanique historique doit démarrer.")
		var expected_rng_state: String = "2795282058164943041" if scenario_id == "S01" else "8391613367634471571"
		check(str(engine.rng.state) == expected_rng_state, scenario_id + " : aucun tirage supplémentaire ne doit modifier le RNG historique.")
		var directions: Array = CALIBRATION_DIRECTIONS[scenario_id]
		var times_s: Array[float] = [0.0, 0.25, 1.0, 2.0]
		for time_index in times_s.size():
			var expected: Vector3 = directions[mini(time_index, directions.size() - 1)]
			check(AimGeometry.angular_error_deg(engine.target_direction(0, times_s[time_index]), expected) < 0.00001, scenario_id + " : la trajectoire seedée antérieure doit rester identique.")
		check(archived[scenario_id].fingerprint() == ARCHIVE_FINGERPRINTS[scenario_id], scenario_id + " : l'archive de révision 2 doit garder son empreinte exacte.")
		check(engine.start(archived[scenario_id], 7919, 2.0), scenario_id + " : les définitions de révision 2 restent jouables.")
	var calibration := CalibrationService.new()
	check(calibration.begin(SensitivityService.default_profile(), 16.0 / 9.0, 7919, "pattern_variation_contract"), "La calibration doit conserver un protocole utilisable.")
	var seeds_by_repetition: Dictionary = {}
	for stage in calibration.plan:
		var repetition_key: String = str(stage.scenario_id) + ":" + str(stage.repetition)
		if seeds_by_repetition.has(repetition_key):
			check(seeds_by_repetition[repetition_key] == stage.seed, "A/B/C doivent jouer la même graine pour une répétition donnée.")
		else:
			seeds_by_repetition[repetition_key] = stage.seed


func test_catalog_and_fingerprints() -> void:
	check(ScenarioCatalog.DEFINITIONS.size() == 16, "Le catalogue doit conserver exactement seize exercices.")
	for definition in ScenarioCatalog.DEFINITIONS:
		check(definition.revision == (4 if definition.scenario_id in PATTERN_IDS else 3) and definition.validate().is_empty(), definition.scenario_id + " : seules les trois mécaniques choisies passent en révision 4.")
		check(definition.fits_view(75.0, 16.0 / 9.0), definition.scenario_id + " : l'enveloppe maximale doit tenir dans le frustum nominal.")
	for scenario_id in PATTERN_IDS:
		var source: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		var changed: ScenarioDefinition = source.duplicate() as ScenarioDefinition
		if scenario_id == "D01":
			changed.angular_diameter_min_deg += 0.1
		elif scenario_id == "S02":
			changed.distance_max_m -= 0.1
		else:
			changed.turn_duration_s += 0.01
		check(changed.fingerprint() != source.fingerprint(), "Tout paramètre actif de " + scenario_id + " doit modifier l'empreinte.")
		if scenario_id == "D01":
			changed = source.duplicate() as ScenarioDefinition
			changed.diameter_motion = "fixed"
			check(changed.fingerprint() != source.fingerprint(), "Le rétrécissement temporel actif doit modifier l'empreinte de D01.")
		changed = source.duplicate() as ScenarioDefinition
		changed.title = "Autre titre"
		changed.instructions = "Autres consignes"
		check(changed.fingerprint() == source.fingerprint(), "Les cosmétiques de " + scenario_id + " restent hors empreinte mécanique.")
	var inactive: ScenarioDefinition = ScenarioCatalog.find("C02").duplicate() as ScenarioDefinition
	inactive.turn_duration_s = 0.9
	check(inactive.fingerprint() == CALIBRATION_FINGERPRINTS.C02, "Une durée de virage inactive ne doit pas entrer dans l'empreinte historique.")


func test_seeded_variations() -> void:
	for scenario_id in PATTERN_IDS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		var signatures: Dictionary = {}
		for seed_value in SEEDS:
			var first := ScenarioEngine.new()
			var replay := ScenarioEngine.new()
			check(first.start(definition, seed_value, 8.0) and replay.start(definition, seed_value, 120.0), scenario_id + " : deux moteurs de durées différentes doivent jouer les mêmes patterns.")
			check(first.targets == replay.targets and first.rng.state == replay.rng.state, "La génération ne dépend ni de la durée du rendu ni d'un horizon d'aperçu différent.")
			var initial_targets: Array[Dictionary] = first.targets.duplicate(true)
			var initial_rng_state: int = first.rng.state
			for time_s in [7.9, 0.0, 2.5, 0.1]:
				for target_index in first.targets.size():
					check(first.target_geometry(target_index, time_s) == replay.target_geometry(target_index, time_s), scenario_id + " : les lectures de géométrie dans un autre ordre doivent être pures.")
			check(first.targets == initial_targets and first.rng.state == initial_rng_state and first.shots == 0 and first.elapsed_s == 0.0, "L'aperçu de la géométrie ne doit avancer ni RNG, ni cibles, ni mesures.")
			signatures[JSON.stringify(first.targets).sha256_text()] = true
			var observed_sizes: Dictionary = {}
			var observed_depths: Dictionary = {}
			for shot_index in 24:
				var time_s: float = float(shot_index + 1) * 0.2
				var target_index: int = shot_index % first.targets.size()
				var geometry: Dictionary = first.target_geometry(target_index, time_s)
				observed_sizes[float(geometry.angular_diameter_deg)] = true
				observed_depths[float(geometry.distance_m)] = true
				check(first.shoot(time_s, geometry.direction) and replay.shoot(time_s, geometry.direction), scenario_id + " : les vrais impacts et remplacements doivent se rejouer.")
				check(first.targets == replay.targets and first.rng.state == replay.rng.state, scenario_id + " : une séquence d'actions identique garde toutes les variations identiques.")
			if scenario_id == "D01":
				check(observed_sizes.size() > 1 and observed_depths.size() == 1, "D01 varie explicitement le diamètre par apparition, avec une profondeur fixe.")
			elif scenario_id == "S02":
				check(observed_depths.size() > 1 and observed_sizes.size() == 1, "S02 varie explicitement la profondeur par cible, avec un diamètre angulaire constant.")
		check(signatures.size() == SEEDS.size(), scenario_id + " : plusieurs graines doivent produire plusieurs patterns, sous la même empreinte de difficulté.")


func test_diameter_temporal_function() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("D01")
	for seed_value in SEEDS:
		var engine := ScenarioEngine.new()
		engine.start(definition, seed_value, 8.0)
		var initial_diameter_deg: float = engine.target_angular_diameter_deg(0, 0.0)
		var minimum_diameter_deg: float = definition.angular_diameter_min_deg
		check(initial_diameter_deg >= minimum_diameter_deg and initial_diameter_deg <= definition.angular_diameter_max_deg, "Le diamètre initial est tiré dans les bornes déclarées.")
		check(is_equal_approx(engine.target_angular_diameter_deg(0, 0.5), (initial_diameter_deg + minimum_diameter_deg) * 0.5), "D01 rétrécit linéairement avec son âge logique.")
		check(engine.target_angular_diameter_deg(0, 1.0) == minimum_diameter_deg and engine.target_angular_diameter_deg(0, 4.0) == minimum_diameter_deg, "L'âge est borné à la durée de vie, sans diamètre inférieur au minimum.")
		var later_s: float = 0.75
		var geometry: Dictionary = engine.target_geometry(0, later_s)
		check(float(geometry.angular_diameter_deg) < initial_diameter_deg and float(geometry.angular_diameter_deg) == engine.target_angular_diameter_deg(0, later_s) and float(geometry.radius_m) == engine.radius_m(0, later_s) and float(geometry.distance_m) == engine.target_distance_m(0, later_s), "Toutes les API de géométrie utilisent la même fonction temporelle.")
		pool.sync(engine, later_s)
		check(pool.spheres[0].global_basis.get_scale().is_equal_approx(Vector3.ONE * engine.radius_m(0, later_s)), "Le mesh rétrécit exactement comme le rayon analytique.")
		var direction: Vector3 = geometry.direction
		var tangent: Vector3 = direction.cross(Vector3.UP).normalized()
		var between_rad: float = deg_to_rad((initial_diameter_deg + float(geometry.angular_diameter_deg)) * 0.25)
		var formerly_inside: Vector3 = direction * cos(between_rad) + tangent * sin(between_rad)
		check(not is_inf(AimGeometry.ray_sphere_distance(formerly_inside, geometry.center_offset_m, engine.radius_m(0, 0.0))) and is_inf(AimGeometry.ray_sphere_distance(formerly_inside, geometry.center_offset_m, engine.radius_m(0, later_s))), "Un rayon initialement dans la cible doit sortir de sa hitbox après rétrécissement.")
		var outside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 + 0.005)
		var inside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 - 0.005)
		var outside: Vector3 = direction * cos(outside_rad) + tangent * sin(outside_rad)
		var inside: Vector3 = direction * cos(inside_rad) + tangent * sin(inside_rad)
		check(not engine.shoot(later_s, outside) and engine.shoot(later_s, inside), "Après rétrécissement, un clic juste extérieur rate et un clic juste intérieur touche.")
		var birth_s: float = float(engine.targets[0].born_s)
		check(engine.target_angular_diameter_deg(0, birth_s - 0.1) == engine.target_angular_diameter_deg(0, birth_s), "Un âge antérieur à l'apparition est borné à zéro pour la cible courante.")
	for settings in [{"diameter_motion": "unknown"}, {"lifetime_s": 0.0}, {"lifetime_s": NAN}, {"revision": 3}, {"angular_diameter_min_deg": 0.0, "angular_diameter_max_deg": 0.0}]:
		var invalid: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
		for field in settings:
			invalid.set(field, settings[field])
		check(not invalid.validate().is_empty() and not ScenarioEngine.new().start(invalid, 1, 8.0), "Un rétrécissement invalide est refusé avant la session.")


func test_reactive_motion() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("D02")
	for seed_value in SEEDS:
		var engine := ScenarioEngine.new()
		engine.start(definition, seed_value, 120.0)
		var maximum_speed_deg_s: float = 0.0
		var maximum_acceleration_deg_s2: float = 0.0
		var step_s: float = 0.005
		var previous_yaw_deg: float = rad_to_deg(atan2(-engine.target_direction(0, 0.0).x, -engine.target_direction(0, 0.0).z))
		var previous_speed_deg_s: float = 0.0
		var bounded: bool = true
		for sample_index in range(1, 2401):
			var direction: Vector3 = engine.target_direction(0, sample_index * step_s)
			var yaw_deg: float = rad_to_deg(atan2(-direction.x, -direction.z))
			var speed_deg_s: float = (yaw_deg - previous_yaw_deg) / step_s
			maximum_speed_deg_s = maxf(maximum_speed_deg_s, absf(speed_deg_s))
			if sample_index > 1:
				maximum_acceleration_deg_s2 = maxf(maximum_acceleration_deg_s2, absf(speed_deg_s - previous_speed_deg_s) / step_s)
			bounded = bounded and absf(yaw_deg) <= definition.yaw_extent_deg * 0.9 + 0.00002 and absf(rad_to_deg(asin(direction.y))) <= definition.pitch_extent_deg
			previous_yaw_deg = yaw_deg
			previous_speed_deg_s = speed_deg_s
		check(bounded and maximum_speed_deg_s <= definition.speed_deg_s + 0.02, "D02 doit rester dans son champ et sous sa vitesse déclarée.")
		check(maximum_acceleration_deg_s2 <= 2.0 * definition.speed_deg_s / definition.turn_duration_s + 5.0, "Les reprises réactives doivent conserver une accélération finie bornée.")
		var former_period_s: float = TAU * definition.yaw_extent_deg * 0.45 / definition.speed_deg_s
		var repeats: bool = true
		for time_s in [0.0, 0.4, 1.0, 2.0]:
			repeats = repeats and AimGeometry.angular_error_deg(engine.target_direction(0, time_s), engine.target_direction(0, time_s + former_period_s)) < 0.001
		check(not repeats, "D02 doit changer ses destinations, pas seulement la phase de l'ancien cycle.")
		var interval_s: float = float(engine.targets[0].reactive_interval_s)
		for boundary_index in range(1, 6):
			var boundary_s: float = boundary_index * interval_s
			var before_deg: float = engine.reactive_offset_deg(engine.targets[0], boundary_s - 0.0001)
			var center_deg: float = engine.reactive_offset_deg(engine.targets[0], boundary_s)
			var after_deg: float = engine.reactive_offset_deg(engine.targets[0], boundary_s + 0.0001)
			check(absf((center_deg - before_deg) / 0.0001 - (after_deg - center_deg) / 0.0001) < 0.02, "Les jonctions des destinations doivent préserver position et vitesse.")


func test_hit_render_consistency() -> void:
	var material: StandardMaterial3D = (pool.spheres[0].mesh as SphereMesh).material as StandardMaterial3D
	check(material.albedo_color.is_equal_approx(Color("FF684B")) and is_equal_approx(material.roughness, 0.7) and not material.emission_enabled and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Les cibles sont corail, mates, éclairées et sans émission.")
	pool.position = Vector3(0.3, 0.2, -0.1)
	pool.scale = Vector3(1.4, 0.8, 1.1)
	for scenario_id in PATTERN_IDS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		for seed_value in [1, 42, 7919]:
			var engine := ScenarioEngine.new()
			engine.start(definition, seed_value, 120.0)
			for time_s in [0.0, 0.37, 1.2, 5.0, 119.5]:
				engine.advance_to(time_s)
				pool.sync(engine, time_s)
				for target_index in engine.targets.size():
					var geometry: Dictionary = engine.target_geometry(target_index, time_s)
					var sphere: MeshInstance3D = pool.spheres[target_index]
					var radius_m: float = float(geometry.radius_m)
					check(sphere.visible and (sphere.global_position - camera.global_position).is_equal_approx(geometry.center_offset_m) and sphere.global_basis.get_scale().is_equal_approx(Vector3.ONE * radius_m), "La sphère rendue doit utiliser le centre et le rayon exacts de la hitbox dynamique.")
					check(absf(rad_to_deg(2.0 * asin(radius_m / float(geometry.distance_m))) - float(geometry.angular_diameter_deg)) < 0.00000001, "La profondeur variable doit préserver le diamètre angulaire de chaque cible.")
					var direction: Vector3 = geometry.direction
					var tangent: Vector3 = direction.cross(Vector3.UP).normalized()
					var inside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 - 0.005)
					var outside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 + 0.005)
					var inside: Vector3 = direction * cos(inside_rad) + tangent * sin(inside_rad)
					var outside: Vector3 = direction * cos(outside_rad) + tangent * sin(outside_rad)
					check(not is_inf(AimGeometry.ray_sphere_distance(inside, geometry.center_offset_m, radius_m)) and is_inf(AimGeometry.ray_sphere_distance(outside, geometry.center_offset_m, radius_m)), "Le bord intérieur touche et le bord extérieur rate la silhouette actuelle.")
					var shooter := ScenarioEngine.new()
					shooter.start(definition, seed_value, 120.0)
					shooter.advance_to(time_s)
					check(not shooter.shoot(time_s, outside) and shooter.shoot(time_s, inside) and shooter.shots == 2 and shooter.hits == 1, "Le vrai moteur de clic doit employer cette même hitbox, pour chaque cible et instant.")
					var outline: PackedVector2Array = AimGeometry.project_sphere_outline(direction, float(geometry.angular_diameter_deg), camera.fov, Rect2(Vector2.ZERO, Vector2(viewport.size)))
					var projection_matches: bool = outline.size() == 128
					for perimeter_index in range(0, outline.size(), 16):
						projection_matches = projection_matches and absf(AimGeometry.angular_error_deg(direction, camera.project_ray_normal(outline[perimeter_index])) - float(geometry.angular_diameter_deg) * 0.5) < 0.00008
					check(projection_matches, "La projection destinée à l'aperçu doit être tangente à la hitbox réelle.")
	pool.transform = Transform3D.IDENTITY


func test_preview_physical_silhouette() -> void:
	for scenario_id in PATTERN_IDS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		var preview := ScenarioPreview.new()
		preview.size = Vector2(viewport.size) + Vector2(0.0, ScenarioPreview.PLAYBACK_BAR_HEIGHT_PX)
		preview.configure(definition, false, camera.fov, 16.0 / 9.0)
		var live := ScenarioEngine.new()
		live.start(definition, ScenarioPreview.DEMO_SEED, ScenarioPreview.DEMO_DURATION_S)
		var initial_rng_state: int = live.rng.state
		for time_s in [0.0, 0.1, 0.45, 0.75]:
			preview.advance_demo(time_s - preview.elapsed_s)
			pool.sync(live, time_s)
			for target_index in live.targets.size():
				var geometry: Dictionary = live.target_geometry(target_index, time_s)
				var outline: PackedVector2Array = preview.target_outline(target_index, time_s)
				var coherent: bool = outline.size() == 128
				for perimeter_index in range(0, outline.size(), 16):
					var ray: Vector3 = camera.project_ray_normal(outline[perimeter_index])
					coherent = coherent and absf(AimGeometry.angular_error_deg(geometry.direction, ray) - float(geometry.angular_diameter_deg) * 0.5) < 0.00008
				check(coherent and pool.spheres[target_index].global_basis.get_scale().is_equal_approx(Vector3.ONE * float(geometry.radius_m)), scenario_id + " : l'aperçu réel et le mesh doivent partager la silhouette physique à chaque instant.")
		check(preview.engine != live and live.elapsed_s == 0.0 and live.shots == 0 and live.rng.state == initial_rng_state, "L'aperçu animé doit rester indépendant des mesures et du RNG du moteur réel.")
		preview.free()


func test_fixed_difficulty() -> void:
	for scenario_id in PATTERN_IDS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		var fingerprint: String = definition.fingerprint()
		var good := ScenarioEngine.new()
		var poor := ScenarioEngine.new()
		good.start(definition, 42, 8.0)
		poor.start(definition, 42, 8.0)
		var original: Array[Dictionary] = good.targets.duplicate(true)
		for shot_index in 10:
			var time_s: float = float(shot_index + 1) * 0.05
			poor.shoot(time_s, Vector3.BACK)
		var pattern_unchanged: bool = poor.rng.state == good.rng.state
		for target_index in poor.targets.size():
			pattern_unchanged = pattern_unchanged and poor.targets[target_index].id == original[target_index].id
			for time_s in [0.0, 0.25, 0.5]:
				pattern_unchanged = pattern_unchanged and poor.target_geometry(target_index, time_s) == good.target_geometry(target_index, time_s)
		check(pattern_unchanged, "Des ratés ne doivent pas adapter taille, profondeur, trajectoire ou RNG.")
		for shot_index in 10:
			var time_s: float = float(shot_index + 1) * 0.05
			good.shoot(time_s, good.target_geometry(0, time_s).direction)
		check(good.hits == 10 and poor.hits == 0 and good.definition.fingerprint() == fingerprint and poor.definition.fingerprint() == fingerprint and definition.fingerprint() == fingerprint, "Des performances différentes conservent la même définition de difficulté.")
		for engine in [good, poor]:
			engine.advance_to(8.0)
			var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			check(report.valid and report.scenario_fingerprint == fingerprint and report.score_version == 1 and report.score == ScoringService.score(report, definition.reference_hits_s) and ScoringService.validate_result(report).is_empty(), "La variation explicite conserve score V1 et rapports cohérents.")


func test_frame_rate_replays() -> void:
	for scenario_id in PATTERN_IDS:
		for seed_value in [1, 42, 7919]:
			var reference: Dictionary = {}
			for frame_rate in [60, 144, 240]:
				var engine := ScenarioEngine.new()
				engine.start(ScenarioCatalog.find(scenario_id), seed_value, 6.0)
				var next_shot_s: float = 0.57
				var shot_index: int = 0
				for frame_index in range(1, 6 * frame_rate + 1):
					var end_s: float = float(frame_index) / frame_rate
					while next_shot_s <= end_s + 0.000000001 and next_shot_s < 6.0:
						engine.advance_to(next_shot_s)
						var direction: Vector3 = engine.target_geometry(shot_index % engine.targets.size(), next_shot_s).direction
						engine.record_aim(next_shot_s, rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(direction.y)))
						engine.shoot(next_shot_s, Vector3.BACK if shot_index % 3 == 0 else direction)
						shot_index += 1
						next_shot_s = float(shot_index + 1) * 0.57
					engine.record_frame(1.0 / frame_rate)
					engine.advance_to(end_s)
				var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
				var snapshot: Dictionary = {"targets": engine.targets.duplicate(true), "rng_state": engine.rng.state, "metrics": report.metrics, "score": report.score}
				check(report.valid and report.completed and report.metrics.shots == 10 and report.metrics.misses > 0 and ScoringService.validate_result(report).is_empty(), "Le replay doit exécuter ses vrais clics et ratés.")
				if scenario_id == "D01":
					check(engine.expired > 0, "Le replay de D01 doit réellement exercer des expirations entre les clics.")
				if reference.is_empty():
					reference = snapshot
				else:
					check(snapshot == reference, scenario_id + " : mêmes événements horodatés, géométrie, RNG, métriques et score à 60/144/240 FPS.")


func test_tracking_semantics() -> void:
	var source: ScenarioDefinition = ScenarioCatalog.find("T01").duplicate() as ScenarioDefinition
	source.revision = 4
	source.angular_diameter_min_deg = 3.0
	source.angular_diameter_max_deg = 5.0
	for inside in [false, true]:
		var reference: Dictionary = {}
		for frame_rate in [60, 144, 240]:
			var engine := ScenarioEngine.new()
			engine.start(source, 42, 2.003)
			var diameter_deg: float = float(engine.target_geometry(0, 0.0).angular_diameter_deg)
			var aim_offset_deg: float = diameter_deg * 0.5 + (-0.25 if inside else 0.25)
			for event_index in 2004:
				var time_s: float = minf(float(event_index) / 1000.0, 2.003)
				var direction: Vector3 = engine.target_direction(0, time_s)
				engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)) + aim_offset_deg, 0.0)
			for frame_index in range(1, ceili(2.003 * frame_rate) + 1):
				engine.advance_to(minf(float(frame_index) / frame_rate, 2.003))
			var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			var expected_on_target: bool = engine.on_target_s > 2.0 if inside else engine.on_target_s == 0.0
			check(report.valid and is_equal_approx(report.metrics.target_exposed_time_s, 2.003) and expected_on_target, "Le suivi doit intégrer le diamètre actuel et la fraction finale de temps à 240 Hz.")
			check(not engine.shoot(1.0, Vector3.FORWARD) and engine.shots == 0, "Le tracking ne doit compter aucun clic comme du score.")
			if reference.is_empty():
				reference = report.metrics
			else:
				check(reference == report.metrics, "Un replay tracking identique doit garder toutes ses métriques à 60/144/240 FPS.")
	source.diameter_motion = "shrink"
	source.lifetime_s = 2.003
	source.motion = "static"
	source.pitch_extent_deg = 0.01
	var shrinking_reference: Dictionary = {}
	for frame_rate in [60, 144, 240]:
		var engine := ScenarioEngine.new()
		engine.start(source, 42, source.lifetime_s)
		var initial_diameter_deg: float = engine.target_angular_diameter_deg(0, 0.0)
		var fixed_offset_deg: float = (initial_diameter_deg + source.angular_diameter_min_deg) * 0.25
		for event_index in 2004:
			var time_s: float = minf(float(event_index) / 1000.0, source.lifetime_s)
			var direction: Vector3 = engine.target_direction(0, time_s)
			engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)) + fixed_offset_deg, rad_to_deg(asin(direction.y)))
		for frame_index in range(1, ceili(source.lifetime_s * frame_rate) + 1):
			engine.advance_to(minf(float(frame_index) / frame_rate, source.lifetime_s))
		var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
		check(report.valid and absf(engine.on_target_s - source.lifetime_s * 0.5) < 0.05, "Un écart fixe traverse le bord d'une cible qui rétrécit à mi-durée, sans conserver le seuil nominal.")
		if shrinking_reference.is_empty():
			shrinking_reference = report.metrics
		else:
			check(shrinking_reference == report.metrics, "Le tracking temporel à diamètre changeant doit garder ses métriques à tous les FPS.")


func test_bounds_and_invalid() -> void:
	var camera_transform: Transform3D = camera.global_transform
	for scenario_id in PATTERN_IDS:
		var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id)
		check(definition.minimum_surface_height_m() > 0.25, "L'enveloppe maximale, pas seulement la profondeur nominale, reste au-dessus du sol.")
		for seed_value in SEEDS:
			var engine := ScenarioEngine.new()
			engine.start(definition, seed_value, 120.0)
			var bounded: bool = true
			for sample_index in 241:
				var time_s: float = float(sample_index) * 0.5
				for target_index in engine.targets.size():
					var geometry: Dictionary = engine.target_geometry(target_index, time_s)
					var center: Vector3 = camera.global_position + Vector3(geometry.center_offset_m)
					var radius_m: float = float(geometry.radius_m)
					bounded = bounded and center.y - radius_m > 0.0 and center.z - radius_m > -11.9
					for plane in camera.get_frustum():
						bounded = bounded and plane.distance_to(center) <= -radius_m
			check(bounded and camera.global_transform == camera_transform, "Sol, mur et six plans du frustum doivent contenir toute la sphère sans déplacer la caméra.")
	var invalid_settings: Array[Dictionary] = [
		{"revision": 3}, {"angular_diameter_min_deg": 0.0}, {"angular_diameter_max_deg": 2.0},
		{"angular_diameter_min_deg": NAN}, {"angular_diameter_max_deg": INF}, {"angular_diameter_max_deg": 10.1}
	]
	for settings in invalid_settings:
		var invalid: ScenarioDefinition = ScenarioCatalog.find("D01").duplicate() as ScenarioDefinition
		for field in settings:
			invalid.set(field, settings[field])
		check(not invalid.validate().is_empty() and not ScenarioEngine.new().start(invalid, 1, 8.0), "Les bornes de taille invalides ou non versionnées sont refusées avant le jeu.")
	for settings in [{"distance_min_m": 0.0}, {"distance_max_m": 4.0}, {"distance_min_m": NAN}, {"distance_max_m": INF}, {"distance_max_m": 8.1}, {"distance_max_m": 7.0}, {"angular_diameter_min_deg": 3.0, "angular_diameter_max_deg": 4.0}]:
		var invalid: ScenarioDefinition = ScenarioCatalog.find("S02").duplicate() as ScenarioDefinition
		for field in settings:
			invalid.set(field, settings[field])
		check(not invalid.validate().is_empty(), "Une profondeur qui traverse le sol ou des silhouettes qui croisent les couloirs sont refusées.")
	for bad_turn_s in [0.0, 0.001, 2.0, NAN, INF]:
		var invalid: ScenarioDefinition = ScenarioCatalog.find("D02").duplicate() as ScenarioDefinition
		invalid.turn_duration_s = bad_turn_s
		check(not invalid.validate().is_empty(), "Les dynamiques réactives impossibles ou non finies sont refusées.")
	var engine := ScenarioEngine.new()
	check(engine.target_geometry(0, 0.0).is_empty(), "Un moteur non initialisé n'a aucune géométrie valide.")
	engine.start(ScenarioCatalog.find("D01"), 1, 8.0)
	check(engine.target_geometry(-1, 0.0).is_empty() and engine.target_geometry(1, 0.0).is_empty() and engine.target_geometry(0, NAN).is_empty() and engine.target_geometry(0, -1.0).is_empty(), "Indices et instants de géométrie invalides sont refusés.")


func test_grid_respawns() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("C03")
	check(definition.layout == "grid" and definition.motion == "static" and definition.active_targets == 6 and definition.revision == 3, "C03 conserve sa vraie grille de neuf cellules et six cibles.")
	var engine := ScenarioEngine.new()
	engine.start(definition, 42, 8.0)
	var cells: Dictionary = {}
	var valid: bool = true
	for shot_index in 128:
		var time_s: float = float(shot_index + 1) * 0.04
		var target_index: int = shot_index % engine.targets.size()
		var target: Dictionary = engine.targets[target_index]
		var yaw_cell: float = float(target.yaw_deg) / definition.yaw_extent_deg
		var pitch_cell: float = float(target.pitch_deg) / definition.pitch_extent_deg
		valid = valid and yaw_cell in [-1.0, 0.0, 1.0] and pitch_cell in [-1.0, 0.0, 1.0]
		cells[Vector2(yaw_cell, pitch_cell)] = true
		valid = engine.shoot(time_s, engine.target_direction(target_index, time_s)) and valid
	check(valid and cells.size() == 9 and engine.invalid_reason.is_empty(), "Les respawns de C03 choisissent librement les cellules disponibles, sans abandonner la grille.")
