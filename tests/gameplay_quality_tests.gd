extends RefCounted

const ArenaScene: PackedScene = preload("res://scenes/training/Arena.tscn")
const MainScene: PackedScene = preload("res://scenes/app/Main.tscn")
const AppScript = preload("res://scripts/core/main.gd")

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var fingerprints: Array[String] = []
	for definition in ScenarioCatalog.DEFINITIONS:
		fingerprints.append(definition.fingerprint())
	test_preview_definitions()
	test_fixed_difficulty()
	await test_countdown_preparation(tree)
	await test_preview_projection(tree)
	await test_initial_camera_poses(tree)
	await capture_previews(tree)
	test_preview_replays()
	test_insights()
	test_records()
	for definition_index in ScenarioCatalog.DEFINITIONS.size():
		var definition: ScenarioDefinition = ScenarioCatalog.DEFINITIONS[definition_index]
		expect(definition.revision == (4 if definition.scenario_id in ["D01", "D02", "S02"] else 3) and definition.fingerprint() == fingerprints[definition_index], "L’audit ne doit pas modifier la difficulté publiée ou l’empreinte de " + definition.scenario_id + ".")
	return true


func outline_bounds(outline: PackedVector2Array) -> Rect2:
	var bounds: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	return bounds


func test_preview_definitions() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		var preview := ScenarioPreview.new()
		preview.configure(definition)
		var live := ScenarioEngine.new()
		live.start(definition, ScenarioPreview.DEMO_SEED, ScenarioPreview.DEMO_DURATION_S)
		var source_fingerprint: String = definition.fingerprint()
		var live_targets: Array[Dictionary] = live.targets.duplicate(true)
		var live_rng_state: int = live.rng.state
		expect(preview.engine != live and preview.engine.definition != definition and preview.engine.definition.fingerprint() == source_fingerprint and preview.engine.targets == live_targets, definition.scenario_id + " : l'aperçu doit lire la nouvelle définition avec son propre moteur seedé et sa copie de difficulté.")
		preview.advance_demo(1.1)
		expect(live.targets == live_targets and live.rng.state == live_rng_state and live.elapsed_s == 0.0 and live.shots == 0 and live.timeline.event_count == 0 and definition.fingerprint() == source_fingerprint, "Jouer l'aperçu ne doit modifier ni la ressource, ni le RNG, ni les mesures d'un exercice réel.")
		var revised: ScenarioDefinition = definition.duplicate() as ScenarioDefinition
		revised.angular_diameter_deg *= 0.9
		preview.configure(revised)
		expect(preview.preview_error.is_empty() and preview.elapsed_s == 0.0 and preview.engine.definition.fingerprint() == revised.fingerprint() and preview.engine.definition.angular_diameter_deg == revised.angular_diameter_deg and preview.engine.definition.distance_m == revised.distance_m, "Reconfigurer l'aperçu doit relire taille et profondeur depuis la définition, sans cache d'ancienne difficulté.")
		preview.free()


func test_fixed_difficulty() -> void:
	for definition in ScenarioCatalog.DEFINITIONS:
		var original_fingerprint: String = definition.fingerprint()
		for accurate in [false, true]:
			var engine := ScenarioEngine.new()
			expect(engine.start(definition, 7919, 1.0), definition.scenario_id + " : la difficulté fixe doit accepter une performance faible ou élevée.")
			if definition.family == "tracking":
				for sample_index in range(1, 241):
					var time_s: float = sample_index / 240.0
					var direction: Vector3 = engine.target_direction(0, time_s)
					engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)) + (0.0 if accurate else 20.0), rad_to_deg(asin(direction.y)))
					engine.advance_to(time_s)
			else:
				for shot_index in 4:
					var time_s: float = (shot_index + 1) * 0.2
					var direction: Vector3 = engine.target_direction(shot_index % engine.targets.size(), time_s)
					engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(direction.y)))
					engine.shoot(time_s, direction if accurate else Vector3.BACK)
			engine.advance_to(1.0)
			for projection in [[40.0, 1.25], [75.0, 16.0 / 9.0], [110.0, 3.0]]:
				var profile: Dictionary = SensitivityService.default_profile()
				profile.vertical_fov_deg = projection[0]
				var report: Dictionary = engine.result(profile, float(projection[1]), true)
				expect(report.valid and ScoringService.validate_result(report).is_empty() and report.scenario_revision == definition.revision and report.scenario_fingerprint == original_fingerprint and engine.definition.fingerprint() == original_fingerprint, "Performance, FOV et fenêtre ne doivent adapter ni taille, ni vitesse, ni disposition de la difficulté enregistrée.")
				expect(report.score_version == 1 and report.reference_hits_s == definition.reference_hits_s and report.score == ScoringService.score(report, definition.reference_hits_s), "Les scores doivent conserver leur formule V1 et la référence déclarée par l'exercice.")
				expect(report.metrics.input_events == (240 if definition.family == "tracking" else 4) and report.metrics.angular_path_deg > 0.0 and report.metrics.input_buffer_overflows == 0, "Le chemin et les événements doivent rester mesurables, sans counts fabriqués ni tampon saturé.")
			expect(engine.shots == (0 if definition.family == "tracking" else 4) and engine.hits == (4 if accurate and definition.family != "tracking" else 0), "La performance synthétique doit réellement exercer les touches et les ratés, sans changer la cadence de clic.")
			if definition.family == "tracking":
				expect(engine.on_target_s > 0.99 if accurate else engine.on_target_s < 0.01, "Les deux replays de suivi doivent réellement produire une tenue presque complète et presque nulle, à difficulté identique.")
		expect(definition.fingerprint() == original_fingerprint, "Les essais et leurs bilans ne doivent pas modifier la ressource utilisée par la calibration.")


func test_preview_projection(tree: SceneTree) -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var arena: Node3D = ArenaScene.instantiate() as Node3D
	viewport.add_child(arena)
	await tree.process_frame
	var camera: Camera3D = arena.get_node("AimCamera") as Camera3D
	camera.position += Vector3(0.25, 0.4, 0.1)
	var preview := ScenarioPreview.new()
	viewport.add_child(preview)
	for settings in [[Vector2i(1280, 720), 75.0], [Vector2i(800, 600), 45.0], [Vector2i(1200, 400), 110.0]]:
		var dimensions: Vector2i = settings[0]
		viewport.size = dimensions
		camera.fov = float(settings[1])
		preview.size = Vector2(dimensions)
		for definition in ScenarioCatalog.DEFINITIONS:
			preview.configure(definition, false, camera.fov, float(dimensions.x) / dimensions.y)
			var view: Rect2 = preview.projection_rect()
			expect(view.position.is_zero_approx() and view.size.is_equal_approx(Vector2(dimensions)), "Le viewport d’aperçu doit conserver exactement le ratio demandé.")
			for target_index in preview.engine.targets.size():
				var direction: Vector3 = preview.engine.target_direction(target_index, 0.0)
				var expected_center: Vector2 = camera.unproject_position(camera.global_position + direction * definition.distance_m)
				expect(preview.project_direction(direction).distance_to(expected_center) < 0.003, definition.scenario_id + " : le centre de l’aperçu doit coïncider avec Camera3D depuis son origine réelle.")
				var outline: PackedVector2Array = preview.target_outline(target_index, 0.0)
				expect(outline.size() == 128, "La silhouette réelle doit être projetée avec 128 segments, sans rayon minimum en pixels.")
				var tangent_error_deg: float = 0.0
				for perimeter_index in range(0, outline.size(), 8):
					var ray: Vector3 = camera.project_ray_normal(outline[perimeter_index])
					var geometry: Dictionary = preview.engine.target_geometry(target_index, 0.0)
					tangent_error_deg = maxf(tangent_error_deg, absf(AimGeometry.angular_error_deg(direction, ray) - float(geometry.angular_diameter_deg) * 0.5))
				expect(tangent_error_deg < 0.00005, definition.scenario_id + " : les points de silhouette doivent être les rayons tangents de la hitbox sphérique visible.")
	preview.size = Vector2(160.0, 78.0)
	preview.configure(ScenarioCatalog.find("C05"))
	var narrow_outline: PackedVector2Array = AimGeometry.project_sphere_outline(Vector3.FORWARD, preview.definition.angular_diameter_deg, preview.vertical_fov_deg, preview.projection_rect())
	var narrow_bounds: Rect2 = outline_bounds(narrow_outline)
	var expected_diameter_px: float = preview.projection_rect().size.y * tan(deg_to_rad(0.35)) / tan(deg_to_rad(37.5))
	expect(narrow_bounds.size.y < 1.0 and absf(narrow_bounds.size.y - expected_diameter_px) < 0.001, "C05 miniature : aucune inflation à 2,5 px de rayon ne doit masquer la taille angulaire réelle.")
	preview.size = Vector2(200.0, 200.0)
	expect(absf(preview.projection_rect().size.x / preview.projection_rect().size.y - 16.0 / 9.0) < 0.000001, "Un aperçu carré doit utiliser des bandes plutôt que déformer le ratio du gameplay.")
	expect(not preview.set_projection(NAN, 1.0) and not preview.preview_error.is_empty() and preview.target_outline(0, 0.0).is_empty(), "Un FOV invalide doit être signalé, sans projection approximative de remplacement.")
	preview.configure(null, true)
	expect(not preview.preview_error.is_empty() and preview.engine.targets.is_empty() and not preview.is_processing(), "Une définition absente ne doit pas continuer l’ancienne démonstration.")
	preview.configure(ScenarioCatalog.find("C02"), false, 75.0, 16.0 / 9.0)
	expect(preview.preview_error.is_empty() and preview.tooltip_text.contains("simulés") and preview.tooltip_text.contains("sans agrandissement"), "L’aperçu doit expliquer FOV, ratio, taille réelle et visée simulée.")
	viewport.queue_free()
	await tree.process_frame


func test_countdown_preparation(tree: SceneTree) -> void:
	var app := MainScene.instantiate() as AppScript
	app.store = LocalStore.new("user://tests/countdown_geometry_" + LocalStore.new().identifier())
	tree.root.add_child(app)
	await tree.process_frame
	for definition in ScenarioCatalog.DEFINITIONS:
		app.engine = ScenarioEngine.new()
		expect(app.prepare_training(definition, 15.0, 7919, SensitivityService.default_profile()), definition.scenario_id + " : la préparation doit accepter la nouvelle difficulté au cadrage par défaut.")
		var preparation: ScenarioEngine = app.preparation_engine
		var initial_targets: Array[Dictionary] = preparation.targets.duplicate(true)
		var initial_rng_state: int = preparation.rng.state
		var transforms: Array[Transform3D] = []
		for target_index in preparation.targets.size():
			transforms.append(app.target_pool.spheres[target_index].global_transform)
			expect(app.target_pool.spheres[target_index].visible, "La cible préparée doit être visible dès le début du décompte.")
		var motion := InputEventMouseMotion.new()
		motion.screen_relative = Vector2(7.0, -5.0)
		app._input(motion)
		var shot := InputEventMouseButton.new()
		shot.button_index = MOUSE_BUTTON_LEFT
		shot.pressed = true
		app._input(shot)
		for countdown_s in [0.0, 0.5, 1.0, 2.5]:
			app.clock.start(Time.get_ticks_usec() - int(countdown_s * 1000000.0))
			app._process(1.0 / 144.0)
			expect(app.screen == AppScript.Screen.COUNTDOWN and preparation.targets == initial_targets and preparation.rng.state == initial_rng_state, "Le décompte doit figer cibles et RNG, y compris au-delà de la durée de vie de Pop-up.")
			for target_index in transforms.size():
				expect(app.target_pool.spheres[target_index].global_transform.is_equal_approx(transforms[target_index]), "La sphère préparée doit garder sa direction mondiale et son rayon pendant le décompte et les mouvements souris.")
			expect(app.engine != preparation and app.engine.definition == null and app.engine.shots == 0 and app.engine.elapsed_s == 0.0 and app.engine.timeline.event_count == 0 and preparation.shots == 0 and preparation.elapsed_s == 0.0 and preparation.on_target_s == 0.0 and preparation.timeline.event_count == 0, "La préparation doit utiliser un second moteur, sans tirs, temps actif ni mesures de visée.")
		app.begin_training(Time.get_ticks_usec())
		expect(app.screen == AppScript.Screen.TRAINING and app.engine.definition.fingerprint() == definition.fingerprint() and app.engine.rng.state == initial_rng_state and app.engine.spawned == definition.active_targets, "Le départ doit recréer le moteur mesuré à zéro avec la même graine et la difficulté de révision 3.")
		expect(app.engine.elapsed_s == 0.0 and app.engine.integrated_s == 0.0 and app.engine.shots == 0 and app.engine.timeline.event_count == 0 and app.engine.timeline.angular_path_deg == 0.0, "Aucune mesure du décompte ne doit être transférée dans la séance.")
		expect(app.aim_camera.received_x_counts == 7.0 and app.aim_camera.received_y_counts == -5.0 and app.initial_x_counts == 7.0 and app.initial_y_counts == -5.0 and app.engine.timeline.last_yaw_deg == app.aim_camera.yaw_deg and app.engine.timeline.last_pitch_deg == app.aim_camera.pitch_deg, "Les counts du décompte doivent orienter la caméra et servir de référence initiale, sans être supprimés ni ajoutés au trajet mesuré.")
		for target_index in transforms.size():
			expect(app.target_pool.spheres[target_index].global_transform.is_equal_approx(transforms[target_index]) and float(app.engine.targets[target_index].born_s) == 0.0, "La cible visible préparée doit être celle du départ mesuré, avec une naissance à zéro.")
		app.return_to_menu()
	app.queue_free()
	await tree.process_frame


func test_initial_camera_poses(tree: SceneTree) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var arena: Node3D = ArenaScene.instantiate() as Node3D
	viewport.add_child(arena)
	await tree.process_frame
	var camera: AimCamera = arena.get_node("AimCamera") as AimCamera
	var pool: TargetPool = arena.get_node("TargetPool") as TargetPool
	(arena.get_node("ReferenceSphere") as MeshInstance3D).hide()
	var floor_height_m: float = (arena.get_node("Floor") as MeshInstance3D).global_position.y
	var output_directory: String = "user://tests/gameplay_initial_pose_" + Crypto.new().generate_random_bytes(8).hex_encode()
	if DisplayServer.get_name() != "headless":
		expect(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "Les captures de poses initiales doivent rester sous user://tests/.")
	for pose in [Vector2(30.0, -30.0), Vector2(30.0, 30.0), Vector2(-30.0, -30.0), Vector2(-30.0, 30.0), Vector2(30.0, -89.0), Vector2(30.0, 89.0), Vector2(732.0, -89.0), Vector2(-732.0, 89.0), Vector2(180.0, 0.0), Vector2.ZERO]:
		camera.reset_aim()
		camera.apply_mouse_counts(-pose / camera.degrees_per_count)
		var received_counts: Vector2 = camera.received_counts
		var received_x_counts: float = camera.received_x_counts
		var received_y_counts: float = camera.received_y_counts
		var camera_transform: Transform3D = camera.global_transform
		var frustum_planes: Array[Plane] = camera.get_frustum()
		expect(AimGeometry.angular_error_deg(-camera.global_basis.z, AimGeometry.direction(camera.yaw_deg, camera.pitch_deg)) < 0.00002, "La base réelle de Camera3D doit correspondre à la visée, y compris aux limites de pitch et après plusieurs tours.")
		var min_surface_m: float = INF
		var outside_frustum: int = 0
		for definition in ScenarioCatalog.DEFINITIONS:
			var bounds_valid: bool = true
			var initial_pose_valid: bool = true
			var radius_valid: bool = true
			var frustum_valid: bool = true
			var projection_valid: bool = true
			for seed_value in [1, 23, 42, 57]:
				var engine := ScenarioEngine.new()
				var nominal := ScenarioEngine.new()
				expect(engine.start(definition, seed_value, 30.0, camera.yaw_deg, camera.pitch_deg) and nominal.start(definition, seed_value, 30.0), "Chaque exercice doit accepter la pose initiale effectivement permise par la caméra.")
				initial_pose_valid = initial_pose_valid and engine.timeline.last_yaw_deg == camera.yaw_deg and engine.timeline.last_pitch_deg == camera.pitch_deg
				initial_pose_valid = initial_pose_valid and engine.timeline.angular_path_deg == 0.0 and engine.timeline.event_count == 0
				for time_s in [0.0, 0.5, 7.5, 30.0]:
					pool.sync(engine, time_s)
					for target_index in engine.targets.size():
						var geometry: Dictionary = engine.target_geometry(target_index, time_s)
						var direction: Vector3 = geometry.direction
						var sphere: MeshInstance3D = pool.spheres[target_index]
						var surface_m: float = sphere.global_position.y - float(geometry.radius_m)
						min_surface_m = minf(min_surface_m, surface_m)
						bounds_valid = bounds_valid and direction.is_equal_approx(nominal.target_direction(target_index, time_s)) and surface_m > floor_height_m
						bounds_valid = bounds_valid and (sphere.global_position - camera.global_position).is_equal_approx(geometry.center_offset_m)
						radius_valid = radius_valid and sphere.global_basis.get_scale().is_equal_approx(Vector3.ONE * float(geometry.radius_m)) and (sphere.mesh as SphereMesh).radius == 1.0
						var relative_direction: Vector3 = camera.global_basis.inverse() * direction
						var fits_frustum: bool = AimGeometry.sphere_fits_view(relative_direction, float(geometry.angular_diameter_deg), camera.fov, 16.0 / 9.0)
						var fits_real_planes: bool = true
						for plane in frustum_planes:
							fits_real_planes = fits_real_planes and plane.distance_to(sphere.global_position) <= -float(geometry.radius_m)
						frustum_valid = frustum_valid and fits_frustum == fits_real_planes
						if fits_frustum:
							var projected: Vector2 = AimGeometry.project_direction(relative_direction, camera.fov, Rect2(Vector2.ZERO, Vector2(viewport.size)))
							projection_valid = projection_valid and projected.distance_to(camera.unproject_position(sphere.global_position)) < 0.003
						else:
							outside_frustum += 1
						if definition.scenario_id == "C07" and seed_value == 23 and time_s == 0.0 and pose.x == 30.0 and absf(pose.y) == 30.0:
							print("GAMEPLAY POSE CASE : C07 seed 23, caméra %s, centre %s, bas %.6f m, erreur regard %.6f°, écran %s, frustum %s." % [pose, sphere.global_position, surface_m, AimGeometry.angular_error_deg(-camera.global_basis.z, direction), camera.unproject_position(sphere.global_position), fits_frustum])
				for yaw_sign in [-1.0, 1.0]:
					for pitch_sign in [-1.0, 1.0]:
						var direction: Vector3 = AimGeometry.direction(yaw_sign * definition.yaw_extent_deg, pitch_sign * definition.pitch_extent_deg)
						var maximum_radius_m: float = definition.maximum_distance_m() * sin(deg_to_rad(definition.maximum_angular_diameter_deg() * 0.5))
						var surface_m: float = camera.global_position.y + direction.y * definition.maximum_distance_m() - maximum_radius_m
						min_surface_m = minf(min_surface_m, surface_m)
						bounds_valid = bounds_valid and surface_m > floor_height_m
				expect(bounds_valid, definition.scenario_id + " : la pose initiale change la visée, pas l’ancrage mondial ni le rayon visible ; même les extrêmes doivent rester au-dessus du sol.")
			expect(initial_pose_valid, definition.scenario_id + " : la timeline doit partir des angles reçus sans inventer de counts ni de trajet angulaire.")
			expect(radius_valid, definition.scenario_id + " : le rayon rendu doit rester identique à celui de collision pour toute pose initiale.")
			expect(frustum_valid, definition.scenario_id + " : le contrôle de silhouette dans la base caméra doit correspondre aux six plans réels du frustum.")
			expect(projection_valid, definition.scenario_id + " : la projection dans la base caméra doit correspondre à Camera3D pour les cibles cadrées.")
			expect(camera.received_counts == received_counts and camera.received_x_counts == received_x_counts and camera.received_y_counts == received_y_counts and camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(camera.yaw_deg, pose.x) and is_equal_approx(camera.pitch_deg, pose.y), "Le démarrage et les synchronisations ne doivent modifier ni transform caméra ni angles ni counts.")
		print("GAMEPLAY INITIAL POSE : yaw %.0f°, pitch %.0f°, surface minimale %.3f m ; %d silhouettes hors du frustum depuis cette visée." % [pose.x, pose.y, min_surface_m, outside_frustum])
		if DisplayServer.get_name() != "headless" and pose.x == 30.0 and absf(pose.y) == 30.0:
			for scenario_id in ["C04", "C07", "S02"]:
				var engine := ScenarioEngine.new()
				engine.start(ScenarioCatalog.find(scenario_id), 23, 30.0, camera.yaw_deg, camera.pitch_deg)
				pool.sync(engine, 0.0)
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				var rendered: Image = viewport.get_texture().get_image()
				expect(not rendered.is_empty() and rendered.save_png(output_directory.path_join("%s_pitch_%+.0f.png" % [scenario_id, pose.y])) == OK, "La pose initiale doit être examinée dans un rendu de l’arène réelle.")
				for target_index in engine.targets.size():
					var direction: Vector3 = engine.target_direction(target_index, 0.0)
					var relative_direction: Vector3 = camera.global_basis.inverse() * direction
					if AimGeometry.sphere_fits_view(relative_direction, engine.definition.angular_diameter_deg, camera.fov, 16.0 / 9.0):
						var center: Vector2 = camera.unproject_position(pool.spheres[target_index].global_position)
						var color: Color = rendered.get_pixel(roundi(center.x), roundi(center.y))
						expect(color.g > color.r * 1.3 and color.b > color.r * 1.25, "Une cible dans le frustum réel ne doit être masquée ni par le sol ni par le mur.")
	if DisplayServer.get_name() != "headless":
		print("GAMEPLAY INITIAL POSE CAPTURES : " + ProjectSettings.globalize_path(output_directory))
	viewport.queue_free()
	await tree.process_frame


func capture_previews(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		print("NON EXÉCUTÉ : rendu des aperçus ; les projections sont comparées à Camera3D sans affichage.")
		return
	var output_directory: String = "user://tests/gameplay_quality_" + Crypto.new().generate_random_bytes(8).hex_encode()
	expect(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "Les captures gameplay doivent être isolées sous user://tests/.")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var preview := ScenarioPreview.new()
	preview.size = Vector2(viewport.size)
	viewport.add_child(preview)
	await tree.process_frame
	for scenario_id in ["C02", "D01", "S02", "T03", "T05"]:
		preview.configure(ScenarioCatalog.find(scenario_id))
		preview.advance_demo(0.65)
		preview.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var rendered: Image = viewport.get_texture().get_image()
		expect(not rendered.is_empty() and rendered.save_png(output_directory.path_join(scenario_id + ".png")) == OK, scenario_id + " : l’aperçu réellement rendu doit être capturé.")
		for target_index in preview.engine.targets.size():
			var center: Vector2 = preview.project_direction(preview.engine.target_direction(target_index, preview.elapsed_s))
			var color: Color = rendered.get_pixel(roundi(center.x), roundi(center.y))
			expect(color.g > 0.7 and color.b > 0.65, scenario_id + " : chaque cible doit être visible dans le rendu, pas seulement dans la projection mathématique.")
	print("GAMEPLAY CAPTURES : " + ProjectSettings.globalize_path(output_directory))
	viewport.queue_free()
	await tree.process_frame


func test_preview_replays() -> void:
	var definitions: Array[ScenarioDefinition] = ScenarioCatalog.DEFINITIONS.duplicate()
	var short_lifetime: ScenarioDefinition = ScenarioCatalog.find("D01").duplicate() as ScenarioDefinition
	short_lifetime.lifetime_s = 0.2
	definitions.append(short_lifetime)
	for definition in definitions:
		var reference := ScenarioPreview.new()
		reference.configure(definition, true)
		reference.advance_demo(3.0)
		for frame_rate in [60, 144, 240]:
			var preview := ScenarioPreview.new()
			preview.configure(definition, true)
			for frame_index in 3 * frame_rate:
				preview.advance_demo(1.0 / frame_rate)
			expect(preview.preview_error.is_empty() and preview.engine.targets == reference.engine.targets and preview.engine.hits == reference.engine.hits and preview.engine.expired == reference.engine.expired, definition.scenario_id + " : une frame longue et les replays 60/144/240 doivent traiter tous les clics et expirations aux mêmes instants.")
			expect(AimGeometry.angular_error_deg(preview.engine.target_direction(0, preview.elapsed_s), reference.engine.target_direction(0, reference.elapsed_s)) < 0.00003, "Les positions des aperçus doivent évoluer à vitesse réelle indépendamment de leur cadence de rendu.")
			preview.free()
		expect(definition.family == "tracking" or reference.engine.hits == 3, "La démonstration doit utiliser les vrais tirs et remplacements, pas un spawn arbitraire par frame.")
		if definition == short_lifetime:
			expect(reference.engine.expired > 0, "L’aperçu doit aussi jouer les expirations réelles, même entre deux clics simulés.")
		reference.free()
	var wrapped := ScenarioPreview.new()
	wrapped.configure(ScenarioCatalog.find("S02"), true)
	wrapped.advance_demo(120.2)
	var restarted := ScenarioPreview.new()
	restarted.configure(ScenarioCatalog.find("S02"), true)
	restarted.advance_demo(0.2)
	expect(is_equal_approx(wrapped.elapsed_s, 0.2) and wrapped.engine.targets == restarted.engine.targets and wrapped.engine.spawned == restarted.engine.spawned, "Le bouclage doit recréer le moteur seedé, sans cibles nées dans le cycle précédent.")
	wrapped.free()
	restarted.free()


func click_report(hits_count: int = 7, shots_count: int = 10, duration_s: float = 5.0) -> Dictionary:
	var engine := ScenarioEngine.new()
	engine.start(ScenarioCatalog.find("C01"), 7919, duration_s)
	for shot_index in shots_count:
		var time_s: float = duration_s * float(shot_index + 1) / float(shots_count + 1)
		var direction: Vector3 = engine.target_direction(0, time_s)
		engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(direction.y)))
		engine.shoot(time_s, direction if shot_index < hits_count else Vector3.BACK)
	engine.record_frame(1.0 / 144.0)
	engine.record_frame(1.0 / 144.0)
	engine.advance_to(duration_s)
	return engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)


func tracking_report(on_target: bool = true) -> Dictionary:
	var engine := ScenarioEngine.new()
	engine.start(ScenarioCatalog.find("T01"), 7919, 2.0)
	for sample_index in 481:
		var time_s: float = sample_index / 240.0
		var direction: Vector3 = engine.target_direction(0, time_s)
		engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)) + (0.0 if on_target else 10.0), rad_to_deg(asin(direction.y)))
		engine.advance_to(time_s)
	return engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)


func test_insights() -> void:
	var report: Dictionary = click_report()
	var insights: Dictionary = PerformanceInsights.analyze(report)
	expect(ScoringService.validate_result(report).is_empty() and insights.eligible, "Les diagnostics doivent accepter un rapport moteur complet et actif.")
	expect(report.get("renderer", "") == "compatibility" and report.comparison_key == ScoringService.reported_comparison_key(report), "Le rapport moteur doit déclarer le renderer déjà inclus dans sa clé de comparaison, sans changer les conditions.")
	for field in ["primary_label", "primary_value", "secondary_label", "secondary_value", "tempo_label", "tempo_value", "tip", "short_tip", "reason"]:
		expect(insights.get(field, null) is String, "Le contrat SessionPanel expose " + field + " en String.")
	expect(insights.primary_label == "Précision" and insights.primary_value == "70,0 %" and insights.secondary_value == "7 / 10" and insights.tempo_value == "84 cibles/min", "Le bilan doit séparer précision, touches/tirs et cadence réelle, sans confondre cibles touchées et tirs effectués.")
	expect(insights.measurements.acquisition_median_ms.available and insights.measurements.acquisition_median_ms.unit == "ms", "Le temps d’acquisition reste disponible avec son unité et sa définition.")
	expect(report.metrics.acquisition_samples == 7 and insights.score_explanation.expected_score == report.score and is_equal_approx(ScoringService.utility(report), 1.4 * 0.49), "Le score V1 et sa pénalité de précision au carré doivent rester inchangés.")
	expect(insights.short_tip.contains("centrer le viseur") and not insights.short_tip.contains("%"), "Le conseil court doit proposer une action fondée sur les tirs manqués, sans répéter les chiffres.")
	var no_hit: Dictionary = PerformanceInsights.analyze(click_report(0, 4))
	expect(not no_hit.measurements.acquisition_median_ms.available and no_hit.primary_value == "0,0 %", "Une médiane d’acquisition vide ne doit pas prétendre mesurer zéro milliseconde.")
	var no_shot: Dictionary = PerformanceInsights.analyze(click_report(0, 0))
	expect(no_shot.primary_value == "—" and not no_shot.eligible and not no_shot.reason.is_empty(), "Sans tir, aucune précision ni record ne doit être inventé.")
	var tracking: Dictionary = tracking_report()
	var tracking_insights: Dictionary = PerformanceInsights.analyze(tracking)
	expect(tracking_insights.eligible and tracking_insights.primary_value == "100,0 %" and tracking_insights.secondary_value == "2,00 s" and tracking_insights.tempo_unit == "ms", "Le tracking doit présenter ratio temporel, secondes suivies et acquisitions mesurées.")
	expect(tracking_insights.measurements.reacquisition_median_ms.description.contains("première acquisition") and is_equal_approx(tracking_insights.measurements.tracking_sample_step_s.value, 1.0 / 240.0), "Le diagnostic doit expliquer la première acquisition et la résolution de l’intégration.")
	expect(tracking_insights.score_explanation.expected_score == 1000 and ScoringService.utility(tracking) == 1.0, "Le score tracking V1 conserve le ratio temporel, sans pondération cachée.")
	var no_tracking: Dictionary = PerformanceInsights.analyze(tracking_report(false))
	expect(no_tracking.tempo_value == "—" and not no_tracking.measurements.reacquisition_median_ms.available, "Aucun retour sur cible ne doit afficher une médiane nulle comme une performance.")
	expect(no_tracking.short_tip == "Cherchez à garder le viseur sur la cible plus régulièrement." and not no_tracking.short_tip.contains("p95") and tracking_insights.short_tip.contains("confirmer"), "Le conseil tracking court doit distinguer pertes de suivi et suivi complet sans jargon ni promesse.")
	tracking.metrics.reacquisition_samples = "invalide"
	expect(PerformanceInsights.analyze(tracking).tempo_value == "—", "Un compteur de diagnostic corrompu doit rester indisponible sans erreur de conversion.")
	expect(not PerformanceInsights.analyze({}).eligible and not PerformanceInsights.analyze({"metrics": []}).eligible, "Le diagnostic doit expliquer les rapports incomplets sans erreur de script.")


func test_records() -> void:
	var values: Array[Dictionary] = []
	for session_index in 25:
		var report: Dictionary = click_report(session_index + 3, session_index + 3)
		report.session_id = "session-%02d" % session_index
		report.created_at_utc = "2026-10-11T12:00:%02dZ" % session_index
		values.push_front(report)
	var key: String = values[0].comparison_key
	expect(ProgressService.summarize(values, "").count == 0, "Une clé absente ne doit jamais mélanger toutes les configurations en un faux record.")
	var summary: Dictionary = ProgressService.summarize(values, key)
	expect(summary.count == 25 and summary.latest_score == values[0].score and summary.previous_best == values[1].score and summary.new_record, "Le dernier score et son record précédent doivent être calculés après tri des séances admissibles.")
	expect(summary.recent_sessions.size() == 20 and summary.recent_sessions[0].session_id == "session-24" and summary.recent_sessions[19].session_id == "session-05", "La table doit exposer au plus vingt séances, de la plus récente à la plus ancienne.")
	expect(summary.recent_scores[0] == values[19].score and summary.recent_scores[-1] == values[0].score and summary.trend_available, "Les anciennes clés et l’ordre chronologique du graphe restent compatibles.")
	expect(summary.recent_sessions[0].accuracy_pct == 100.0 and summary.recent_sessions[0].hits == 27 and summary.filter.comparison_key == key and summary.filter.score_version == 1, "Les lignes de table doivent exposer les mesures et leurs conditions de filtrage.")
	var high_score: Dictionary = click_report(120, 120)
	high_score.session_id = "outlier-valid"
	high_score.created_at_utc = "2026-10-11T12:01:00Z"
	values.append(high_score)
	expect(ProgressService.summarize(values, key).best == high_score.score and high_score.score > 1000.0, "Un score extrême réellement cohérent doit rester admissible, sans plafond ni filtre statistique arbitraire.")
	for field in ["warmup", "completed", "valid", "comparison_key", "score_version", "score", "metrics"]:
		var excluded: Dictionary = high_score.duplicate(true)
		match field:
			"warmup": excluded.warmup = true
			"completed": excluded.completed = false
			"valid": excluded.valid = false
			"comparison_key": excluded.comparison_key = "autres-conditions"
			"score_version": excluded.score_version = 2
			"score": excluded.score = NAN
			"metrics": excluded.metrics = "invalide"
		values.append(excluded)
	var inactive: Dictionary = high_score.duplicate(true)
	inactive.metrics.input_events = 0
	values.append(inactive)
	var overflow: Dictionary = high_score.duplicate(true)
	overflow.metrics.input_buffer_overflows = 1
	values.append(overflow)
	var corrupt_score: Dictionary = high_score.duplicate(true)
	corrupt_score.score += 999999.0
	values.append(corrupt_score)
	summary = ProgressService.summarize(values, key)
	expect(summary.count == 26 and summary.best == high_score.score and summary.excluded_count == 10 and not summary.excluded_reasons.is_empty(), "Versions, conditions, inactivité, saturation et scores incohérents doivent être exclus avec des raisons explicites.")
	var first: Array[Dictionary] = [high_score]
	summary = ProgressService.summarize(first, key)
	expect(summary.previous_best == null and summary.new_record, "La première séance admissible établit un record, sans précédent inventé.")
	var tied: Dictionary = high_score.duplicate(true)
	tied.session_id = "outlier-tie"
	tied.created_at_utc = "2026-10-11T12:02:00Z"
	first.append(tied)
	summary = ProgressService.summarize(first, key)
	expect(not summary.new_record and summary.previous_best == high_score.score, "Égaler un record ne doit pas déclencher un nouveau record.")
	tied.created_at_utc = high_score.created_at_utc
	summary = ProgressService.summarize(first, key)
	expect(summary.latest_session_id == "outlier-valid", "À date identique, l’ID fournit un ordre stable et explicite.")
	var tracking: Dictionary = tracking_report()
	tracking.session_id = "tracking"
	tracking.created_at_utc = "2026-10-11T12:03:00Z"
	var tracking_values: Array[Dictionary] = [tracking]
	summary = ProgressService.summarize(tracking_values, tracking.comparison_key)
	expect(summary.recent_sessions[0].hits == null and summary.recent_sessions[0].accuracy_pct == null and summary.recent_sessions[0].on_target_ratio == 1.0, "La table tracking doit exposer du temps sur cible plutôt qu’une fausse précision de clic.")
	var bad_tracking: Dictionary = tracking.duplicate(true)
	bad_tracking.metrics.on_target_time_s = 20.0
	expect(not ScoringService.validate_result(bad_tracking).is_empty() and not PerformanceInsights.analyze(bad_tracking).eligible, "Une durée sur cible supérieure à l’exposition ne doit pas devenir un record valide.")
	var empty: Array[Dictionary] = []
	summary = ProgressService.summarize(empty, key)
	expect(summary.count == 0 and summary.latest_score == null and summary.previous_best == null and not summary.new_record and summary.recent_sessions.is_empty(), "L’historique vide conserve ses clés sans inventer de séance.")
