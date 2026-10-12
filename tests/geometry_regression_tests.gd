extends SceneTree

const ArenaScene: PackedScene = preload("res://scenes/training/Arena.tscn")
const FORMATS: Array[Vector2i] = [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 1024), Vector2i(2560, 1080)]
const CALIBRATION_IDS: Array[String] = ["C02", "C04", "S01", "T01", "T05"]
const VARIABLE_IDS: Array[String] = ["D01", "D02", "S02"]

var assertion_count: int = 0
var failure_count: int = 0
var viewport: SubViewport
var arena: Node3D
var camera: AimCamera
var pool: TargetPool


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("La régression géométrique n'a pas terminé en 90 secondes.")
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
	arena = ArenaScene.instantiate() as Node3D
	viewport.add_child(arena)
	await process_frame
	camera = arena.get_node("AimCamera") as AimCamera
	pool = arena.get_node("TargetPool") as TargetPool
	arena.get_node("ReferenceSphere").hide()
	test_real_camera_origin()
	test_definition_policy()
	test_angular_pixels()
	test_entry_microprecision()
	test_full_frustum()
	test_catalog_bounds()
	test_static_separation()
	test_moving_separation()
	test_motion_speed_bounds()
	test_strafe_turns()
	test_collision_boundaries()
	test_replays()
	await capture_geometry()
	viewport.queue_free()
	await process_frame
	print("GEOMETRY REGRESSION : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func silhouette_pixels(direction: Vector3, distance_m: float, diameter_deg: float) -> Rect2:
	var half_angle_rad: float = deg_to_rad(diameter_deg * 0.5)
	var tangent_distance_m: float = distance_m * cos(half_angle_rad)
	var horizontal: Vector3 = direction.cross(Vector3.UP).normalized()
	var vertical: Vector3 = horizontal.cross(direction).normalized()
	var bounds: Rect2 = Rect2(camera.unproject_position(camera.global_position + direction * distance_m), Vector2.ZERO)
	for perimeter_index in 128:
		var phase_rad: float = float(perimeter_index) * TAU / 128.0
		var tangent: Vector3 = horizontal * cos(phase_rad) + vertical * sin(phase_rad)
		var ray: Vector3 = direction * cos(half_angle_rad) + tangent * sin(half_angle_rad)
		bounds = bounds.expand(camera.unproject_position(camera.global_position + ray * tangent_distance_m))
	return bounds


func test_real_camera_origin() -> void:
	check(camera.keep_aspect == Camera3D.KEEP_HEIGHT and is_equal_approx(camera.fov, 75.0), "La scène réelle doit utiliser un FOV vertical de 75 degrés.")
	check(is_equal_approx(camera.global_position.y, ScenarioDefinition.CAMERA_ORIGIN_HEIGHT_M), "La caméra doit garder son origine mondiale à 1,6 m au-dessus du sol.")
	var reference: MeshInstance3D = arena.get_node("ReferenceSphere") as MeshInstance3D
	var reference_mesh: SphereMesh = reference.mesh as SphereMesh
	var reference_distance_m: float = camera.global_position.distance_to(reference.global_position)
	check(is_equal_approx(reference_distance_m, 4.0) and is_equal_approx(reference_mesh.radius / reference_distance_m, 0.05), "Le repère du test souris doit suivre la profondeur de présentation sans changer son diamètre angulaire.")
	check(reference.global_position.z - reference_mesh.radius > (arena.get_node("BackWall") as MeshInstance3D).global_position.z + 0.1, "Le repère de souris doit rester devant le mur rapproché.")
	for yaw_deg in [-39.0, 0.0, 15.0, 732.0]:
		for pitch_deg in [-20.0, 0.0, 25.0]:
			camera.reset_aim()
			camera.apply_mouse_counts(Vector2(-yaw_deg, -pitch_deg) / camera.degrees_per_count)
			check(AimGeometry.angular_error_deg(-camera.global_basis.z, AimGeometry.direction(yaw_deg, pitch_deg)) < 0.00002, "La caméra réelle et le moteur doivent partager les angles, même après deux tours.")
	camera.reset_aim()
	var engine: ScenarioEngine = ScenarioEngine.new()
	check(engine.start(ScenarioCatalog.find("C02"), 42, 1.0), "Le scénario micro doit démarrer pour le contrôle d'origine.")
	pool.sync(engine, 0.0)
	check((pool.spheres[0].global_position - camera.global_position).is_equal_approx(engine.target_direction(0, 0.0) * engine.definition.distance_m), "L'origine réelle des cibles doit être celle de la caméra, pas celle du sol.")
	var camera_position: Vector3 = camera.position
	camera.position += Vector3(0.2, 0.4, 0.1)
	pool.position = Vector3(1.0, 0.3, -0.4)
	pool.rotation.y = 0.25
	pool.scale = Vector3(1.5, 0.8, 1.2)
	pool.sync(engine, 0.0)
	check((pool.spheres[0].global_position - camera.global_position).is_equal_approx(engine.target_direction(0, 0.0) * engine.definition.distance_m), "Déplacer la caméra ou le pool ne doit pas désaligner la cible visible et le rayon logique.")
	check(pool.spheres[0].global_basis.get_scale().is_equal_approx(Vector3.ONE * engine.radius_m()), "Le rayon visible doit rester sphérique et égal au rayon analytique malgré le transform du pool.")
	var mesh: SphereMesh = pool.spheres[0].mesh as SphereMesh
	check(mesh.radius == 1.0 and mesh.height == 2.0, "Le mesh visible doit être une sphère unité mise à l'échelle par le rayon de collision.")
	check(mesh.radial_segments >= 64 and mesh.rings >= 32, "La silhouette doit être suffisamment tessellée pour approcher la sphère analytique sans marge invisible notable.")
	for sphere in pool.spheres:
		check(sphere.mesh == mesh, "Les six cibles doivent partager le même mesh, sans allocation à chaque spawn.")
	camera.position = camera_position
	pool.transform = Transform3D.IDENTITY


func test_definition_policy() -> void:
	var defaults := ScenarioDefinition.new()
	check(defaults.angular_diameter_deg == 1.5 and defaults.yaw_extent_deg == 12.0 and defaults.pitch_extent_deg == 6.0 and defaults.min_transition_deg == 2.5 and defaults.speed_deg_s == 12.0 and defaults.reference_hits_s == 2.0, "Les valeurs implicites historiques doivent rester inchangées ; les nouvelles difficultés sont explicites dans les ressources.")
	var depths: Array[float] = []
	check(ScenarioCatalog.DEFINITIONS.size() == 18, "Le catalogue géométrique doit couvrir dix-huit exercices.")
	for definition in ScenarioCatalog.DEFINITIONS:
		var expected_revision: int = 5 if definition.scenario_id in ["C03", "M01", "T10"] else 4 if definition.scenario_id in VARIABLE_IDS else 3
		check(definition.revision == expected_revision and definition.validate().is_empty(), definition.scenario_id + " : chaque difficulté publiée doit avoir sa révision explicite et valide.")
		check(definition.distance_m >= 3.0 and definition.distance_m <= 8.0 and definition.minimum_surface_height_m() > 0.25, definition.scenario_id + " : la profondeur nominale doit garder la silhouette entière à plus de 25 cm du sol, même aux extrêmes déclarés.")
		check(definition.fits_view(75.0, 16.0 / 9.0), definition.scenario_id + " : tout l'exercice doit tenir dans le cadrage minimal 16:9 au FOV vertical par défaut de 75°.")
		if definition.scenario_id in ["C05", "T09"]:
			check(definition.angular_diameter_deg < 1.0 and definition.title.contains("avancé") and definition.instructions.contains("facultatif"), "Les petites cibles C05/T09 doivent être explicitement avancées et facultatives.")
		elif definition.scenario_id == "C03":
			check(definition.layout == "scatter" and is_equal_approx(definition.angular_diameter_deg, 4.8) and definition.active_targets == 6 and definition.yaw_extent_deg == 22.0 and definition.pitch_extent_deg == 13.0, "C03 doit répartir six cibles de 4,8 degrés dans son champ libre de 44 sur 26 degrés.")
		else:
			check(definition.angular_diameter_deg >= 2.5 and definition.angular_diameter_deg <= 4.0, definition.scenario_id + " : la difficulté normale doit avoir une silhouette lisible de 2,5 à 4 degrés.")
		if not definition.distance_m in depths:
			depths.append(definition.distance_m)
	check(depths.size() >= 5, "Les distances nominales doivent varier selon l'intention des exercices.")
	var grid: ScenarioDefinition = ScenarioCatalog.find("C03").duplicate() as ScenarioDefinition
	grid.revision = 3
	grid.layout = "grid"
	grid.yaw_extent_deg = 18.0
	grid.pitch_extent_deg = 10.0
	check(grid.validate().is_empty(), "La fixture explicite de grille r3 doit être valide avant le resserrement des cellules.")
	grid.pitch_extent_deg = 4.0
	check(not grid.validate().is_empty(), "Une grosse cible de grille ne doit pas être acceptée dans des cellules qui se chevauchent.")
	var below_floor: ScenarioDefinition = ScenarioCatalog.find("C07").duplicate() as ScenarioDefinition
	below_floor.distance_m = 8.0
	check(not below_floor.validate().is_empty(), "Une profondeur masquant la sphère verticale sous le sol doit être refusée, sans réduire automatiquement sa taille.")
	var definition: ScenarioDefinition = ScenarioCatalog.find("C01")
	var meaningful_changes: Dictionary = {"revision": 4, "family": "switching", "motion": "horizontal", "layout": "grid",
		"angular_diameter_deg": 3.3, "yaw_extent_deg": 15.0, "pitch_extent_deg": 9.0, "min_transition_deg": 4.5,
		"speed_deg_s": 13.0, "active_targets": 2, "lifetime_s": 1.0, "reference_hits_s": 2.1, "distance_m": 5.0}
	for field in meaningful_changes:
		var alternative: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
		alternative.set(field, meaningful_changes[field])
		check(alternative.fingerprint() != definition.fingerprint(), "Le champ mécanique " + field + " doit modifier l'empreinte, sans mélanger les records.")
	var cosmetic: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
	cosmetic.title = "Autre titre"
	cosmetic.instructions = "Autre consigne"
	check(cosmetic.fingerprint() == definition.fingerprint(), "Une traduction de titre ou de consigne ne doit pas changer la difficulté mécanique.")


func test_angular_pixels() -> void:
	for format in FORMATS:
		viewport.size = format
		for definition in ScenarioCatalog.DEFINITIONS:
			var scenario_id: String = definition.scenario_id
			var engine: ScenarioEngine = ScenarioEngine.new()
			engine.start(definition, 42, 1.0)
			var geometry: Dictionary = engine.target_geometry(0, 0.0)
			var recovered_deg: float = rad_to_deg(2.0 * asin(float(geometry.radius_m) / float(geometry.distance_m)))
			check(absf(recovered_deg - float(geometry.angular_diameter_deg)) < 0.000001, scenario_id + " : le rayon de sphère doit préserver exactement le diamètre angulaire déclaré à cet instant.")
			var expected_px: float = float(format.y) * tan(deg_to_rad(definition.angular_diameter_deg * 0.5)) / tan(deg_to_rad(camera.fov * 0.5))
			var baseline_px: float = 0.0
			for distance_m in [2.0, 4.0, 8.0]:
				var bounds: Rect2 = silhouette_pixels(Vector3.FORWARD, distance_m, definition.angular_diameter_deg)
				check(absf(bounds.size.x - expected_px) < 0.001 and absf(bounds.size.y - expected_px) < 0.001, scenario_id + " : les pixels réels doivent dépendre du FOV et de l'angle, pas de la distance.")
				if baseline_px > 0.0:
					check(absf(bounds.size.x - baseline_px) < 0.001, "Passer de 8 m à 4 m ne doit pas agrandir artificiellement les cibles.")
				baseline_px = bounds.size.x
			if scenario_id == "C02":
				print("GEOMETRY PIXELS : C02 %dx%d, FOV vertical 75, diamètre %.3f px." % [format.x, format.y, expected_px])
	viewport.size = Vector2i(1280, 720)


func test_entry_microprecision() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("C02")
	check(definition.revision == 3 and is_equal_approx(definition.angular_diameter_deg, 2.5), "C02 doit être la difficulté versionnée de microprécision d'entrée : diamètre 2,5 degrés, révision 3.")
	check(is_equal_approx(ScenarioCatalog.find("C05").angular_diameter_deg, 0.7), "C05 doit conserver sa petite cible de précision exigeante.")
	check(is_equal_approx(ScenarioCatalog.find("T09").angular_diameter_deg, 0.9), "T09 doit conserver sa petite cible de suivi exigeante.")
	var previous_difficulty: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
	previous_difficulty.revision = 1
	previous_difficulty.angular_diameter_deg = 0.65
	previous_difficulty.yaw_extent_deg = 4.0
	previous_difficulty.pitch_extent_deg = 3.0
	previous_difficulty.min_transition_deg = 1.4
	previous_difficulty.distance_m = 8.0
	var historical_parameters: Array = ["C02", 1, "click", "static", "scatter", 0.65, 4.0, 3.0, 1.4, 12.0, 1, 0.0, 1.6, 8.0]
	check(previous_difficulty.fingerprint() == JSON.stringify(historical_parameters).sha256_text() and previous_difficulty.fingerprint() != definition.fingerprint(), "La fixture historique C02 révision 1 doit garder exactement ses anciens paramètres et son empreinte distincte.")
	var engine: ScenarioEngine = ScenarioEngine.new()
	check(engine.start(definition, 42, 1.0), "La difficulté micro d'entrée doit démarrer sans changement du protocole.")
	var radius_m: float = definition.distance_m * sin(deg_to_rad(1.25))
	check(absf(engine.radius_m() - radius_m) < 0.000001, "La hitbox C02 doit utiliser le même diamètre 2,5 degrés que la sphère visible.")
	camera.reset_aim()
	camera.fov = 75.0
	for format in [Vector2i(1280, 720), Vector2i(800, 450)]:
		viewport.size = format
		var minimum_diameter_px: float = 20.0 if format.y == 720 else 12.0
		var viewport_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(format))
		for yaw_deg in [-definition.yaw_extent_deg, 0.0, definition.yaw_extent_deg]:
			for pitch_deg in [-definition.pitch_extent_deg, 0.0, definition.pitch_extent_deg]:
				var direction: Vector3 = AimGeometry.direction(yaw_deg, pitch_deg)
				var silhouette: Rect2 = silhouette_pixels(direction, definition.distance_m, definition.angular_diameter_deg)
				check(silhouette.size.x >= minimum_diameter_px and silhouette.size.y >= minimum_diameter_px, "C02 : le diamètre apparent doit rester au moins %.0f px à %dp/FOV 75, sans auto-scaling en pixels." % [minimum_diameter_px, format.y])
				check(viewport_bounds.encloses(silhouette) and definition.fits_view(camera.fov, float(format.x) / format.y), "C02 : la silhouette complète de 2,5 degrés doit tenir dans le viewport, y compris aux coins de spawn.")
				var tangent: Vector3 = direction.cross(Vector3.UP).normalized()
				var inside_rad: float = deg_to_rad(1.249)
				var outside_rad: float = deg_to_rad(1.251)
				var inside: Vector3 = direction * cos(inside_rad) + tangent * sin(inside_rad)
				var outside: Vector3 = direction * cos(outside_rad) + tangent * sin(outside_rad)
				var center: Vector3 = direction * definition.distance_m
				check(not is_inf(AimGeometry.ray_sphere_distance(inside, center, engine.radius_m())), "C02 : le bord intérieur à 1,249 degré doit toucher la nouvelle hitbox visible.")
				check(is_inf(AimGeometry.ray_sphere_distance(outside, center, engine.radius_m())), "C02 : le bord extérieur à 1,251 degré doit rater, sans hitbox agrandie séparément.")
		pool.sync(engine, 0.0)
		check(pool.spheres[0].global_basis.get_scale().is_equal_approx(Vector3.ONE * radius_m), "C02 : le rayon du mesh visible doit égaler celui de la hitbox à chaque résolution.")
	viewport.size = Vector2i(1280, 720)


func test_full_frustum() -> void:
	var corner: ScenarioDefinition = ScenarioCatalog.find("C04").duplicate() as ScenarioDefinition
	corner.yaw_extent_deg = 40.0
	corner.pitch_extent_deg = 20.0
	corner.angular_diameter_deg = 1.4
	viewport.size = Vector2i(1920, 640)
	camera.fov = 44.0
	var direction: Vector3 = AimGeometry.direction(40.0, 20.0)
	var projected: Rect2 = silhouette_pixels(direction, 4.0, corner.angular_diameter_deg)
	check(projected.position.y < 0.0, "Reproduction : un pitch de 20 degrés à yaw 40 sort verticalement du FOV 44, malgré des bornes séparées acceptables.")
	check(not corner.fits_view(44.0, 3.0), "La garde FOV doit rejeter le coin réellement hors écran, pas seulement comparer yaw et pitch séparément.")
	check(not corner.fits_view(NAN, 3.0) and not corner.fits_view(75.0, INF), "Les paramètres de projection non finis doivent être refusés.")
	check(not corner.fits_view(0.0, 3.0) and not corner.fits_view(180.0, 3.0) and not corner.fits_view(75.0, 0.0), "Les paramètres de projection dégénérés doivent être refusés.")
	check(not AimGeometry.sphere_fits_view(Vector3.BACK, 1.0, 75.0, 16.0 / 9.0), "Une silhouette derrière la caméra doit être refusée.")
	check(not AimGeometry.sphere_fits_view(Vector3.ZERO, 1.0, 75.0, 16.0 / 9.0), "Une direction de cible nulle doit être refusée.")
	camera.fov = 75.0
	viewport.size = Vector2i(1280, 720)
	for definition in ScenarioCatalog.DEFINITIONS:
		for format in FORMATS:
			viewport.size = format
			for vertical_fov_deg in [40.0, 60.0, 75.0, 90.0, 110.0]:
				camera.fov = vertical_fov_deg
				var bounds: Rect2 = silhouette_pixels(AimGeometry.direction(definition.yaw_extent_deg, definition.pitch_extent_deg), definition.maximum_distance_m(), definition.maximum_angular_diameter_deg())
				var contained: bool = bounds.position.x >= 0.0 and bounds.position.y >= 0.0 and bounds.end.x <= format.x and bounds.end.y <= format.y
				check(definition.fits_view(vertical_fov_deg, float(format.x) / format.y) == contained, definition.scenario_id + " : la garde FOV doit correspondre à la silhouette complète projetée par Camera3D pour tous les FOV de profil.")
	camera.fov = 75.0
	viewport.size = Vector2i(1280, 720)


func test_catalog_bounds() -> void:
	var floor_height_m: float = (arena.get_node("Floor") as MeshInstance3D).global_position.y
	var wall_front_m: float = (arena.get_node("BackWall") as MeshInstance3D).global_position.z + 0.1
	for definition in ScenarioCatalog.DEFINITIONS:
		var lowest_surface_m: float = INF
		var bounds_valid: bool = true
		var transforms_valid: bool = true
		var minimum_seed: int = 0
		for seed_value in range(1, 65):
			var engine: ScenarioEngine = ScenarioEngine.new()
			bounds_valid = engine.start(definition, seed_value, 30.0) and bounds_valid
			for sample_index in 61:
				var time_s: float = float(sample_index) * 0.5
				pool.sync(engine, time_s)
				for target_index in engine.targets.size():
					var geometry: Dictionary = engine.target_geometry(target_index, time_s)
					var direction: Vector3 = geometry.direction
					var yaw_deg: float = rad_to_deg(atan2(-direction.x, -direction.z))
					var pitch_deg: float = rad_to_deg(asin(direction.y))
					bounds_valid = bounds_valid and absf(yaw_deg) <= definition.yaw_extent_deg + 0.00001 and absf(pitch_deg) <= definition.pitch_extent_deg + 0.00001
					var sphere: MeshInstance3D = pool.spheres[target_index]
					var surface_m: float = sphere.global_position.y - float(geometry.radius_m)
					if surface_m < lowest_surface_m:
						lowest_surface_m = surface_m
						minimum_seed = seed_value
					transforms_valid = transforms_valid and (sphere.global_position - camera.global_position).is_equal_approx(geometry.center_offset_m)
					transforms_valid = transforms_valid and sphere.global_basis.get_scale().is_equal_approx(Vector3.ONE * float(geometry.radius_m))
					transforms_valid = transforms_valid and sphere.global_position.z - float(geometry.radius_m) > wall_front_m
					transforms_valid = transforms_valid and float(geometry.distance_m) - float(geometry.radius_m) > camera.near and float(geometry.distance_m) + float(geometry.radius_m) < camera.far
		var expected_revision: int = 5 if definition.scenario_id in ["C03", "M01", "T10"] else 4 if definition.scenario_id in VARIABLE_IDS else 3
		check(definition.validate().is_empty() and definition.revision == expected_revision, definition.scenario_id + " : la nouvelle difficulté doit être versionnée.")
		check(definition.distance_m >= 3.0 and definition.distance_m <= 8.0, definition.scenario_id + " : la profondeur nominale doit rester dans l'arène de 3 à 8 mètres.")
		check(bounds_valid, definition.scenario_id + " : toutes les positions seedées doivent rester dans les bornes angulaires déclarées.")
		check(transforms_valid, definition.scenario_id + " : positions visibles, rayon logique, near/far et mur doivent être cohérents.")
		check(lowest_surface_m > floor_height_m, definition.scenario_id + " : aucune partie de cible ne doit traverser le sol opaque.")
		print("GEOMETRY ARENA : %s, profondeur %.1f m, surface minimale y %.3f m, seed %d." % [definition.scenario_id, definition.distance_m, lowest_surface_m, minimum_seed])
	pool.hide_targets()


func test_static_separation() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		if definition.motion != "static":
			continue
		var minimum_separation_deg: float = INF
		var minimum_transition_deg: float = INF
		var valid: bool = true
		for seed_value in range(1, 65):
			var engine := ScenarioEngine.new()
			valid = engine.start(definition, seed_value, 10.0) and valid
			for shot_index in 64:
				var time_s: float = (shot_index + 1) * 0.05
				var target_index: int = shot_index % engine.targets.size()
				var previous: Vector3 = engine.target_direction(target_index, time_s)
				valid = engine.shoot(time_s, previous) and valid
				minimum_transition_deg = minf(minimum_transition_deg, AimGeometry.angular_error_deg(previous, engine.target_direction(target_index, time_s)))
				for first_index in engine.targets.size():
					for second_index in range(first_index + 1, engine.targets.size()):
						minimum_separation_deg = minf(minimum_separation_deg, AimGeometry.angular_error_deg(engine.target_direction(first_index, time_s), engine.target_direction(second_index, time_s)))
			valid = valid and engine.invalid_reason.is_empty() and engine.hits == 64 and engine.spawned == definition.active_targets + 64
		check(valid, definition.scenario_id + " : 64 graines et 64 remplacements par graine doivent garder une génération possible et des compteurs exacts.")
		check(minimum_transition_deg >= definition.min_transition_deg - 0.00001, definition.scenario_id + " : chaque cible statique remplacée doit respecter son espacement déclaré avec la précédente.")
		check(minimum_separation_deg >= definition.angular_diameter_deg * 1.7 - 0.00001, definition.scenario_id + " : les silhouettes doivent rester distinctes après chaque remplacement.")
		print("GEOMETRY STATIC : %s, transition min %.3f°, séparation min %.3f°, 4096 remplacements." % [definition.scenario_id, minimum_transition_deg, minimum_separation_deg])


func test_moving_separation() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("S02")
	var minimum_deg: float = INF
	var minimum_seed: int = 0
	var minimum_time_s: float = 0.0
	for seed_value in range(1, 65):
		var engine: ScenarioEngine = ScenarioEngine.new()
		engine.start(definition, seed_value, 30.0)
		for sample_index in 601:
			var time_s: float = float(sample_index) * 0.05
			for target_index in engine.targets.size():
				for other_index in range(target_index + 1, engine.targets.size()):
					var separation_deg: float = AimGeometry.angular_error_deg(engine.target_direction(target_index, time_s), engine.target_direction(other_index, time_s))
					if separation_deg < minimum_deg:
						minimum_deg = separation_deg
						minimum_seed = seed_value
						minimum_time_s = time_s
	print("GEOMETRY SEPARATION : S02 minimum %.4f degrés, diamètre %.1f, seed %d, t %.2f s." % [minimum_deg, definition.angular_diameter_deg, minimum_seed, minimum_time_s])
	check(minimum_deg >= definition.angular_diameter_deg * 1.7 - 0.00001, "S02 : les cibles mobiles ne doivent pas se chevaucher au spawn ni pendant leurs trajectoires.")
	var broken: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
	broken.pitch_extent_deg = 1.0
	check(not broken.validate().is_empty(), "Les couloirs impossibles doivent être refusés avant le démarrage.")
	broken = definition.duplicate() as ScenarioDefinition
	broken.motion = "circle"
	check(not broken.validate().is_empty(), "Le mode couloirs ne doit pas prétendre éviter les collisions d'orbites.")
	var engine: ScenarioEngine = ScenarioEngine.new()
	engine.start(definition, 19, 10.0)
	var safe_respawns: bool = true
	for shot_index in 100:
		var time_s: float = (shot_index + 1) * 0.05
		var target_index: int = shot_index % engine.targets.size()
		safe_respawns = engine.shoot(time_s, engine.target_direction(target_index, time_s)) and safe_respawns
		for horizon_s in [0.0, 0.1, 0.5, 2.0]:
			for first_index in engine.targets.size():
				for second_index in range(first_index + 1, engine.targets.size()):
					safe_respawns = safe_respawns and AimGeometry.angular_error_deg(engine.target_direction(first_index, time_s + horizon_s), engine.target_direction(second_index, time_s + horizon_s)) >= definition.angular_diameter_deg * 1.7 - 0.00001
	check(safe_respawns and engine.invalid_reason.is_empty(), "S02 : les couloirs doivent rester distincts après 100 remplacements et sur les trajectoires futures.")


func test_motion_speed_bounds() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		if definition.motion == "static":
			continue
		var engine: ScenarioEngine = ScenarioEngine.new()
		engine.start(definition, 42, 10.0)
		var max_speed_deg_s: float = 0.0
		var step_s: float = 0.002
		for target_index in engine.targets.size():
			var previous_direction: Vector3 = engine.target_direction(target_index, 0.0)
			for sample_index in range(1, 5001):
				var direction: Vector3 = engine.target_direction(target_index, sample_index * step_s)
				max_speed_deg_s = maxf(max_speed_deg_s, AimGeometry.angular_error_deg(previous_direction, direction) / step_s)
				previous_direction = direction
		check(max_speed_deg_s <= definition.speed_deg_s + 0.01, definition.scenario_id + " : la vitesse angulaire totale, pas seulement une composante, doit respecter la limite déclarée.")
		print("GEOMETRY SPEED : %s, maximum %.3f degrés/s, limite %.1f." % [definition.scenario_id, max_speed_deg_s, definition.speed_deg_s])


func test_strafe_turns() -> void:
	var definition: ScenarioDefinition = ScenarioCatalog.find("T05")
	var turn_duration: Variant = definition.get("turn_duration_s")
	check(turn_duration != null, "T05 : la durée des virages doit être explicite et versionnée, pas un demi-tour à accélération infinie.")
	if turn_duration == null:
		return
	var turn_s: float = float(turn_duration)
	var engine: ScenarioEngine = ScenarioEngine.new()
	engine.start(definition, 42, 30.0)
	var max_speed_deg_s: float = 0.0
	var max_acceleration_deg_s2: float = 0.0
	var sample_s: float = 0.001
	var previous_yaw_deg: float = rad_to_deg(atan2(-engine.target_direction(0, 0.0).x, -engine.target_direction(0, 0.0).z))
	var previous_speed_deg_s: float = 0.0
	for sample_index in range(1, 10001):
		var direction: Vector3 = engine.target_direction(0, sample_index * sample_s)
		var yaw_deg: float = rad_to_deg(atan2(-direction.x, -direction.z))
		var speed_deg_s: float = (yaw_deg - previous_yaw_deg) / sample_s
		max_speed_deg_s = maxf(max_speed_deg_s, absf(speed_deg_s))
		if sample_index > 1:
			max_acceleration_deg_s2 = maxf(max_acceleration_deg_s2, absf(speed_deg_s - previous_speed_deg_s) / sample_s)
		previous_yaw_deg = yaw_deg
		previous_speed_deg_s = speed_deg_s
	check(max_speed_deg_s <= definition.speed_deg_s + 0.02, "T05 : vitesse de croisière bornée au paramètre déclaré.")
	check(max_acceleration_deg_s2 <= 2.0 * definition.speed_deg_s / turn_s + 5.0, "T05 : les retournements doivent être continus en vitesse et à accélération bornée.")
	print("GEOMETRY STRAFE : vitesse max %.3f degrés/s, accélération max %.3f degrés/s²." % [max_speed_deg_s, max_acceleration_deg_s2])
	var amplitude_deg: float = definition.yaw_extent_deg * 0.9
	var half_period_s: float = 2.0 * amplitude_deg / definition.speed_deg_s + turn_s * 0.5
	var epsilon_s: float = 0.00001
	for boundary_s in [0.0, turn_s * 0.5, half_period_s - turn_s * 0.5, half_period_s, half_period_s * 2.0]:
		var center_deg: float = engine.strafe_offset_deg(boundary_s, 0.0, amplitude_deg)
		var before_deg: float = engine.strafe_offset_deg(boundary_s - epsilon_s, 0.0, amplitude_deg)
		var after_deg: float = engine.strafe_offset_deg(boundary_s + epsilon_s, 0.0, amplitude_deg)
		var left_speed_deg_s: float = (center_deg - before_deg) / epsilon_s
		var right_speed_deg_s: float = (after_deg - center_deg) / epsilon_s
		check(absf(left_speed_deg_s - right_speed_deg_s) <= 4.0 * definition.speed_deg_s / turn_s * epsilon_s + 0.000001, "Les jonctions de virage et le bouclage doivent préserver la continuité de la vitesse de la cible.")
	var alternative: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
	alternative.turn_duration_s = turn_s * 1.5
	check(alternative.fingerprint() != definition.fingerprint(), "Changer la dynamique des virages doit changer le contexte et invalider les anciens checkpoints.")
	for bad_turn_s in [-1.0, 0.0, 0.001, 10.0, NAN, INF]:
		alternative.turn_duration_s = bad_turn_s
		check(not alternative.validate().is_empty(), "Les durées de virage impossibles ou non finies doivent être refusées.")


func test_collision_boundaries() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		var engine: ScenarioEngine = ScenarioEngine.new()
		engine.start(definition, 42, 1.0)
		var geometry: Dictionary = engine.target_geometry(0, 0.2)
		var center_direction: Vector3 = geometry.direction
		var tangent: Vector3 = center_direction.cross(Vector3.UP).normalized()
		var inside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 - 0.001)
		var outside_rad: float = deg_to_rad(float(geometry.angular_diameter_deg) * 0.5 + 0.001)
		var inside: Vector3 = center_direction * cos(inside_rad) + tangent * sin(inside_rad)
		var outside: Vector3 = center_direction * cos(outside_rad) + tangent * sin(outside_rad)
		var center: Vector3 = geometry.center_offset_m
		check(not is_inf(AimGeometry.ray_sphere_distance(inside, center, float(geometry.radius_m))), definition.scenario_id + " : un rayon juste à l'intérieur de la silhouette sphérique doit toucher.")
		check(is_inf(AimGeometry.ray_sphere_distance(outside, center, float(geometry.radius_m))), definition.scenario_id + " : un rayon juste à l'extérieur doit rater, sans aim assist.")
	check(is_inf(AimGeometry.ray_sphere_distance(Vector3(NAN, 0.0, -1.0), Vector3.FORWARD, 0.1)), "Une direction de tir non finie doit être refusée.")
	check(is_inf(AimGeometry.ray_sphere_distance(Vector3.FORWARD, Vector3(INF, 0.0, -1.0), 0.1)), "Une position de cible non finie doit être refusée.")


func test_replays() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		var reference_metrics: Dictionary = {}
		var reference_targets: Array[Dictionary] = []
		var reference_rng_state: int = 0
		for frame_rate in [60, 144, 240]:
			var engine: ScenarioEngine = ScenarioEngine.new()
			check(engine.start(definition, 7919, 2.0), definition.scenario_id + " : replay initialisé.")
			if definition.family == "tracking":
				for event_index in 2001:
					var time_s: float = event_index * 0.001
					var direction: Vector3 = engine.target_direction(0, time_s)
					engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)) + 0.3 * sin(time_s * 7.0), rad_to_deg(asin(direction.y)))
			else:
				for shot_index in 20:
					var time_s: float = (shot_index + 1) * 0.05
					var target_index: int = shot_index % engine.targets.size()
					var direction: Vector3 = engine.target_direction(target_index, time_s)
					engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(direction.y)))
					check(engine.shoot(time_s, direction), definition.scenario_id + " : le rayon doit toucher le centre logique visible au moment du clic.")
			for frame_index in range(1, 2 * frame_rate + 1):
				engine.advance_to(float(frame_index) / frame_rate)
			var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			check(engine.completed and engine.invalid_reason.is_empty() and report.valid, definition.scenario_id + " : le replay doit rester valide et déterministe.")
			if reference_metrics.is_empty():
				reference_metrics = report.metrics.duplicate(true)
				reference_targets = engine.targets.duplicate(true)
				reference_rng_state = engine.rng.state
			else:
				check(reference_metrics == report.metrics and reference_targets == engine.targets and reference_rng_state == engine.rng.state, definition.scenario_id + " : mêmes métriques, trajet, événements, cibles et RNG à 60/144/240 FPS pour les mêmes événements horodatés.")
		var alternative_depth: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
		alternative_depth.distance_m = 2.0
		var depth_scale: float = alternative_depth.distance_m / definition.distance_m
		if definition.has_distance_variation():
			alternative_depth.distance_min_m *= depth_scale
			alternative_depth.distance_max_m *= depth_scale
		if definition.motion == "waypoints":
			alternative_depth.depth_speed_m_s *= depth_scale
		var previous_engine: ScenarioEngine = ScenarioEngine.new()
		var current_engine: ScenarioEngine = ScenarioEngine.new()
		check(previous_engine.start(alternative_depth, 42, 2.0) and current_engine.start(definition, 42, 2.0), "Les deux profondeurs du test doivent être valides.")
		var previous_targets: Array[Dictionary] = previous_engine.targets.duplicate(true)
		var current_targets: Array[Dictionary] = current_engine.targets.duplicate(true)
		for target_index in previous_targets.size():
			if definition.motion == "waypoints":
				var previous_poses: Array[Vector3] = previous_targets[target_index].waypoint_poses
				var current_poses: Array[Vector3] = current_targets[target_index].waypoint_poses
				check(previous_poses.size() == current_poses.size() and previous_targets[target_index].waypoint_kinds == current_targets[target_index].waypoint_kinds, "Changer l'échelle physique doit conserver toutes les destinations et leurs types de mouvement.")
				for waypoint_index in previous_poses.size():
					var scaled_pose: Vector3 = current_poses[waypoint_index]
					scaled_pose.z *= depth_scale
					check(previous_poses[waypoint_index].is_equal_approx(scaled_pose) and is_equal_approx(previous_targets[target_index].waypoint_times_s[waypoint_index], current_targets[target_index].waypoint_times_s[waypoint_index]), "Les destinations doivent garder leurs angles et leurs instants lorsque profondeur et vitesse physique sont mises à la même échelle.")
				previous_targets[target_index].erase("waypoint_poses")
				current_targets[target_index].erase("waypoint_poses")
				previous_targets[target_index].erase("waypoint_times_s")
				current_targets[target_index].erase("waypoint_times_s")
			previous_targets[target_index].erase("distance_m")
			current_targets[target_index].erase("distance_m")
			for time_s in ([0.0, 0.5, 1.0, 2.0] if definition.motion == "waypoints" else [0.5]):
				check(previous_engine.target_direction(target_index, time_s).is_equal_approx(current_engine.target_direction(target_index, time_s)), "L'échelle des profondeurs et de leur vitesse physique ne change pas le parcours angulaire du viseur.")
				if definition.motion == "waypoints":
					check(is_equal_approx(previous_engine.target_distance_m(target_index, time_s), current_engine.target_distance_m(target_index, time_s) * depth_scale) and is_equal_approx(previous_engine.radius_m(target_index, time_s), current_engine.radius_m(target_index, time_s) * depth_scale), "La sphère et son déplacement en profondeur doivent suivre exactement l'échelle physique déclarée.")
		check(previous_targets == current_targets and previous_engine.rng.state == current_engine.rng.state, definition.scenario_id + " : changer uniquement l'échelle des profondeurs ne change ni positions angulaires, ni phases, ni RNG.")
		check(alternative_depth.fingerprint() != definition.fingerprint(), definition.scenario_id + " : une autre profondeur doit créer un contexte distinct sans prétendre être une fixture historique.")


func capture_geometry() -> void:
	if DisplayServer.get_name() == "headless":
		print("NON EXÉCUTÉ : captures graphiques ; les projections Camera3D sont testées sans rendu.")
		return
	var output_directory: String = "/tmp/aimlocal-geometry-regression"
	check(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "Le dossier temporaire des captures doit être disponible.")
	viewport.size = Vector2i(1280, 720)
	var identifiers: Array[String] = CALIBRATION_IDS.duplicate()
	identifiers.append_array(["C07", "S02"])
	for scenario_id in identifiers:
		var engine: ScenarioEngine = ScenarioEngine.new()
		engine.start(ScenarioCatalog.find(scenario_id), 42, 30.0)
		if scenario_id == "C07":
			for seed_value in range(1, 65):
				engine.start(ScenarioCatalog.find(scenario_id), seed_value, 30.0)
				if engine.target_direction(0, 0.0).y < sin(deg_to_rad(-15.0)):
					break
		pool.sync(engine, 0.0)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var rendered: Image = viewport.get_texture().get_image()
		check(not rendered.is_empty() and rendered.save_png(output_directory.path_join(scenario_id + ".png")) == OK, scenario_id + " : le rendu réel de l'arène doit être capturé.")
		for target_index in engine.targets.size():
			var center: Vector2 = camera.unproject_position(pool.spheres[target_index].global_position)
			var color: Color = rendered.get_pixel(clampi(roundi(center.x), 0, rendered.get_width() - 1), clampi(roundi(center.y), 0, rendered.get_height() - 1))
			check(color.g > color.r * 1.3 and color.b > color.r * 1.25, scenario_id + " : chaque centre de cible doit être effectivement rendu, pas simplement projeté derrière un obstacle.")
	print("GEOMETRY CAPTURES : 7 rendus de l'arène, " + output_directory)
