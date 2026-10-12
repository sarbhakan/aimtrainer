extends SceneTree

const ArenaScene := preload("res://scenes/training/Arena.tscn")
const HudScript := preload("res://scripts/ui/training_hud.gd")
const FORMATS: Array[Vector2i] = [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]

var assertion_count: int = 0
var failure_count: int = 0
var viewport: SubViewport
var arena: Node3D
var hud: TrainingHud


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Les tests présentation 0.8 n’ont pas terminé en 90 secondes.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func profile() -> Dictionary:
	return {"sound_enabled": false, "sound_volume": 37.0, "show_weapon": false,
		"reduced_motion": false, "crosshair_style": "cross", "crosshair_size_px": 6.0,
		"crosshair_gap_px": 4.0, "crosshair_thickness_px": 2.0,
		"crosshair_color": "#54e6cf", "crosshair_outline": true}


func run_tests() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	arena = ArenaScene.instantiate() as Node3D
	viewport.add_child(arena)
	hud = HudScript.new()
	hud.configure(profile())
	viewport.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	arena.get_node("ReferenceSphere").hide()
	test_arena()
	test_target_space()
	test_hitmarker()
	test_feedback_lifecycle()
	await test_live_metrics()
	if DisplayServer.get_name() != "headless":
		await test_render()
	else:
		print("PRESENTATION 080 : rendu graphique et écoute matériels non exécutés en headless.")
	hud.stop()
	viewport.queue_free()
	await create_timer(0.15).timeout
	await process_frame
	print("PRESENTATION 080 : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_arena() -> void:
	var lights := arena.find_children("*", "Light3D", true, false)
	check(lights.size() == 1 and lights[0] is DirectionalLight3D, "L’arène possède exactement une lumière 3D directionnelle.")
	var key := arena.get_node("Light") as DirectionalLight3D
	var light_direction := -key.global_basis.z
	check(key.shadow_enabled and key.light_energy > 0.0 and light_direction.y < -0.35 and absf(light_direction.x) > absf(light_direction.z), "La clé éclaire depuis le côté et projette de vraies ombres communes.")
	var camera := arena.get_node("AimCamera") as Camera3D
	check(camera.position == Vector3(0, 1.6, 0) and camera.fov == 75.0 and camera.keep_aspect == Camera3D.KEEP_HEIGHT, "Le décor conserve l’origine et le FOV vertical de la caméra.")
	var presentation := arena.get_node("Presentation") as ArenaPresentation
	var world_meshes := arena.find_children("*", "MeshInstance3D", true, false)
	check(presentation.environment_meshes.size() > 7 and world_meshes.size() <= 32, "Les détails enrichissent les sept volumes initiaux sans dépasser 32 meshes, pool compris.")
	check(not presentation.is_processing() and not presentation.is_physics_processing(), "Tous les détails restent statiques, sans travail par frame.")
	check(arena.find_children("*", "Decal", true, false).is_empty(), "Aucune ombre peinte par decal ne contredit les vraies ombres.")
	for instance: MeshInstance3D in world_meshes:
		var surface := instance.mesh.surface_get_material(0) as StandardMaterial3D
		check(surface != null and surface.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not surface.emission_enabled and surface.roughness >= 0.7 - 0.000001, "Chaque cible et détail possède un matériau mat éclairé, sans émission, à la précision du float de matériau.")
		check((instance.layers & key.light_cull_mask) == instance.layers and instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Chaque cible et détail reçoit la même lumière et projette son ombre.")
	for instance in presentation.environment_meshes:
		test_bevel(instance.mesh as ArrayMesh)
		var bounds := instance.get_aabb()
		bounds.position += instance.position
		check(bounds.end.z <= -8.75 or bounds.position.x >= 8.75 or bounds.end.x <= -8.75 or bounds.end.y <= 0.25, "Chaque volume reste en périphérie ou derrière toute la zone de cibles 3–8 m.")
	var pool := arena.get_node("TargetPool") as TargetPool
	check(pool.spheres.size() == 6 and pool.spheres[0].mesh is SphereMesh, "Le pool conserve ses six sphères réutilisables.")
	var mesh := pool.spheres[0].mesh as SphereMesh
	check(mesh.radius == 1.0 and mesh.height == 2.0 and mesh.radial_segments >= 64 and mesh.rings >= 32, "La géométrie et la silhouette des cibles restent inchangées.")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var valid_normals := not vertices.is_empty() and vertices.size() == normals.size()
	var left_normal := false
	var right_normal := false
	for vertex_index in mini(vertices.size(), normals.size()):
		valid_normals = valid_normals and normals[vertex_index].is_finite() and is_equal_approx(normals[vertex_index].length(), 1.0) and normals[vertex_index].dot(vertices[vertex_index].normalized()) > 0.999
		left_normal = left_normal or normals[vertex_index].x < -0.9
		right_normal = right_normal or normals[vertex_index].x > 0.9
	check(valid_normals and left_normal and right_normal, "Les normales du TargetPool sont unitaires et sortantes sur les deux côtés éclairés.")


func test_bevel(mesh: ArrayMesh) -> void:
	check(mesh != null and mesh.get_surface_count() == 1, "Chaque détail biseauté est une seule surface statique.")
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var valid_normals := vertices.size() == 132 and vertices.size() == normals.size()
	var edge_counts: Dictionary = {}
	for triangle_index in range(0, vertices.size(), 3):
		var first_m := vertices[triangle_index]
		var second_m := vertices[triangle_index + 1]
		var third_m := vertices[triangle_index + 2]
		var normal := normals[triangle_index]
		valid_normals = valid_normals and is_equal_approx(normal.length(), 1.0) and normal.dot(first_m + second_m + third_m) > 0.0 and (second_m - first_m).cross(third_m - first_m).dot(normal) < 0.0
		for edge_index in 3:
			var first_key := str(vertices[triangle_index + edge_index])
			var second_key := str(vertices[triangle_index + (edge_index + 1) % 3])
			var edge_key := first_key + "/" + second_key if first_key < second_key else second_key + "/" + first_key
			edge_counts[edge_key] = int(edge_counts.get(edge_key, 0)) + 1
	var closed := true
	for count: int in edge_counts.values():
		closed = closed and count == 2
	check(valid_normals and closed, "Faces, biseaux et coins forment un volume fermé à normales sortantes et winding cohérent.")


func test_target_space() -> void:
	var camera := arena.get_node("AimCamera") as Camera3D
	var presentation := arena.get_node("Presentation") as ArenaPresentation
	for instance in presentation.environment_meshes:
		var clear_space := true
		for yaw_deg in range(-40, 41, 10):
			for pitch_deg in range(-25, 26, 5):
				for distance_m in [3.0, 8.0]:
					var center_m: Vector3 = camera.global_position + AimGeometry.direction(float(yaw_deg), float(pitch_deg)) * distance_m
					var radius_m: float = distance_m * sin(deg_to_rad(5.0))
					clear_space = clear_space and not blocks_target(instance, camera.global_position, center_m, radius_m)
		check(clear_space, "Aucun détail n’occulte les cibles de 3 à 8 m jusqu’aux limites ±40° yaw / ±25° pitch.")
	var static_meshes: Array[MeshInstance3D] = presentation.environment_meshes.duplicate()
	static_meshes.append(arena.get_node("Floor") as MeshInstance3D)
	static_meshes.append(arena.get_node("BackWall") as MeshInstance3D)
	for definition in ScenarioCatalog.DEFINITIONS:
		var unobstructed := true
		var minimum_distance_m: float = definition.distance_min_m if definition.has_distance_variation() else definition.distance_m
		for yaw_deg in [-definition.yaw_extent_deg, 0.0, definition.yaw_extent_deg]:
			for pitch_deg in [-definition.pitch_extent_deg, 0.0, definition.pitch_extent_deg]:
				for distance_m in [minimum_distance_m, definition.maximum_distance_m()]:
					var center_m: Vector3 = camera.global_position + AimGeometry.direction(yaw_deg, pitch_deg) * distance_m
					var radius_m: float = distance_m * sin(deg_to_rad(definition.maximum_angular_diameter_deg() * 0.5))
					for instance in static_meshes:
						unobstructed = unobstructed and not blocks_target(instance, camera.global_position, center_m, radius_m)
		check(unobstructed, definition.scenario_id + " : la silhouette entière reste libre du sol, des murs et des nouveaux détails.")


func blocks_target(instance: MeshInstance3D, camera_m: Vector3, center_m: Vector3, radius_m: float) -> bool:
	var inverse := instance.global_transform.affine_inverse()
	return instance.get_aabb().grow(radius_m + 0.0001).intersects_segment(inverse * camera_m, inverse * center_m) != null


func test_hitmarker() -> void:
	check(HudScript.HIT_DIRECTIONS.size() == 4, "Le hitmarker possède exactement quatre directions.")
	for dimensions in FORMATS:
		hud.size = Vector2(dimensions)
		for style in CrosshairProfile.STYLES:
			for maximum in [false, true]:
				var settings := profile()
				settings.crosshair_style = style
				if maximum:
					settings.crosshair_size_px = CrosshairProfile.MAX_SIZE_PX
					settings.crosshair_gap_px = CrosshairProfile.MAX_GAP_PX
					settings.crosshair_thickness_px = CrosshairProfile.MAX_THICKNESS_PX
				hud.configure(settings)
				var center_px := hud.size * 0.5
				var radius_px := CrosshairProfile.radius_px(hud.crosshair_profile)
				var segments := hud.hitmarker_segments()
				check(segments.size() == 8, "Quatre traits distincts entourent le centre ouvert pour chaque style et taille.")
				if segments.size() != 8:
					continue
				for segment_index in 4:
					var direction := Vector2.from_angle(deg_to_rad(45.0 + 90.0 * segment_index))
					var first_px := segments[segment_index * 2] - center_px
					var last_px := segments[segment_index * 2 + 1] - center_px
					check(first_px.normalized().is_equal_approx(direction) and (last_px - first_px).normalized().is_equal_approx(direction), "Chaque trait suit un angle fixe 45/135/225/315°, jamais une extension cardinale du viseur.")
					check(absf(first_px.distance_to(last_px) - 5.0) < 0.001 and first_px.dot(last_px) > 0.0, "Chaque bras du X mesure cinq pixels à la précision subpixel du Canvas, sans traverser le centre.")
					check(first_px.length() - 3.0 >= radius_px + 8.0 - 0.001, "Même le contour garde huit pixels de séparation au-delà du rayon maximal du viseur.")
				check((segments[0] + segments[4]).is_equal_approx(center_px * 2.0) and (segments[2] + segments[6]).is_equal_approx(center_px * 2.0), "Les quatre diagonales sont symétriques autour du centre à toutes les tailles.")
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func test_feedback_lifecycle() -> void:
	hud.configure(profile())
	hud.set_training_view(true, false)
	var camera := arena.get_node("AimCamera") as Camera3D
	var original_camera := camera.global_transform
	var pool := arena.get_node("TargetPool") as TargetPool
	var engine := ScenarioEngine.new()
	check(engine.start(ScenarioCatalog.find("C03"), 800, 30.0), "La fixture utilise de vraies cibles C03 seedées.")
	pool.sync(engine, 0.0)
	var target_transforms: Array[Transform3D] = []
	for sphere in pool.spheres:
		target_transforms.append(sphere.global_transform)
	hud.hit()
	var original_segments := hud.hitmarker_segments()
	check(is_equal_approx(hud.hit_remaining_s, 0.11) and hud.hitmarker_opacity() == 1.0, "Une touche affiche immédiatement le X pendant 110 ms.")
	hud._process(0.055)
	check(is_equal_approx(hud.hitmarker_opacity(), 0.5) and hud.hitmarker_segments() == original_segments, "Le X normal s’estompe brièvement sans allonger ses bras ni déplacer le viseur.")
	hud._process(0.056)
	check(hud.hit_remaining_s == 0.0 and hud.hitmarker_opacity() == 0.0 and not hud.is_processing(), "Le hitmarker s’arrête entièrement après 110 ms.")
	var settings := profile()
	settings.reduced_motion = true
	hud.configure(settings)
	hud.hit()
	check(hud.hitmarker_segments() == original_segments, "Le mode mouvement réduit transmet la même information et la même géométrie.")
	hud._process(0.055)
	check(hud.hitmarker_opacity() == 1.0 and hud.hitmarker_segments() == original_segments, "En mouvement réduit le X reste statique, sans fade ni changement d’échelle.")
	hud._process(0.056)
	check(hud.hit_remaining_s == 0.0 and not hud.is_processing(), "Le X statique disparaît aussi après 110 ms.")
	check(camera.global_transform == original_camera, "Le feedback de touche ne modifie jamais la caméra de visée.")
	for target_index in pool.spheres.size():
		check(pool.spheres[target_index].global_transform == target_transforms[target_index], "Le feedback de touche ne modifie jamais une cible ni sa hitbox.")
	settings.sound_enabled = true
	hud.configure(settings)
	var cues: Array[String] = []
	hud.countdown_feedback.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	hud.begin_countdown()
	hud.set_training_view(false, true)
	hud.present_countdown("3")
	hud.present_countdown("3")
	hud.sync_countdown()
	hud.hit()
	check(cues == ["3"] and hud.hit_remaining_s == 0.0, "Le bip 3 reste unique et une touche est ignorée pendant le décompte.")
	hud.present_countdown("2")
	hud.present_countdown("1")
	hud.set_training_view(true, false)
	hud.show_go()
	hud.show_go()
	check(cues == ["3", "2", "1", "GO"], "Le HUD conserve exactement un bip par chiffre et un GO, y compris en mouvement réduit.")
	hud.hit()
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(hud.hit_remaining_s == 0.0 and not hud.countdown_feedback.tick_player.playing and not hud.countdown_feedback.go_player.playing and not hud.is_processing(), "La perte de focus coupe immédiatement le X et les bips existants.")
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	hud.show_go()
	check(cues == ["3", "2", "1", "GO"] and hud.hit_remaining_s == 0.0, "Le retour de focus ne rejoue aucun bip ni hitmarker consommé.")
	hud.configure(profile())
	hud.hit()
	hud.hide()
	check(hud.hit_remaining_s == 0.0 and not hud.is_processing(), "Masquer le HUD coupe le feedback de touche.")
	hud.show()
	hud.hit()
	paused = true
	check(hud.hit_remaining_s == 0.0 and not hud.is_processing(), "La pause coupe le X sans perturber les états audio.")
	paused = false
	hud.stop()


func test_live_metrics() -> void:
	hud.set_training_view(true, false)
	hud.present_live(10.0, 30.0, 8, 10, false, 0.0, 0.0, 2.0)
	check(hud.timer_label.text == "0:20" and hud.stat_label.text == "TOUCHES · PRÉCISION" and hud.metric_label.text == "8 · 80 %" and hud.score_label.text == "Score 256", "Les anciens arguments gardent les labels, métriques et score V1 exacts.")
	check(not hud.expired_label.visible and hud.expired_label.text.is_empty(), "Le HUD historique n’ajoute aucune légende superflue.")
	hud.present_live(10.0, 30.0, 8, 10, false, 0.0, 0.0, 2.0, 10, 2)
	check(hud.stat_label.text == "TOUCHES · RÉUSSITE" and hud.metric_label.text == "8 · 40 %", "En V2 la réussite utilise touches / (tirs + expirations), sans être appelée précision des tirs.")
	var report := {"family": "click", "score_version": 2,
		"metrics": {"hits_per_s": 0.8, "hits": 8, "shots": 10, "targets_expired": 10,
			"accuracy_fraction": 0.8, "on_target_ratio": 0.0}}
	var expected_score := int(ScoringService.score(report, 2.0))
	check(hud.score_label.text == "Score %d" % expected_score and expected_score == 64, "Le HUD transmet les compteurs et la version au service : 0,8 touches/s × (8/20)² / 2 donne 64 points V2.")
	check(hud.expired_label.visible and hud.expired_label.text == "10 cibles expirées" and hud.expired_label.get_theme_font_size("font_size") <= 12, "Une seule petite légende explique les expirations dans la carte existante.")
	for dimensions in FORMATS:
		viewport.size = dimensions
		await process_frame
		await process_frame
		check(hud.metric_card.size.y <= 140.0 and hud.metric_card.get_global_rect().position.x > float(dimensions.x) * 0.5, "La carte avec expirations reste compacte à droite aux trois tailles.")
	hud.present_live(0.0, 30.0, 0, 0, false, 0.0, 0.0, 2.0, 1, 2)
	check(hud.metric_label.text == "0 · 0 %" and hud.expired_label.text == "1 cible expirée" and hud.score_label.text == "Score 0", "Une cible expirée sans tir donne 0 % de réussite, avec une légende au singulier.")
	hud.present_live(0.0, 30.0, 0, 0, false, 0.0, 0.0, 2.0, 0, 2)
	check(hud.metric_label.text == "0 · —" and not hud.expired_label.visible, "Sans tir ni expiration la réussite reste inconnue et la légende disparaît.")
	hud.present_live(10.0, 30.0, 0, 0, true, 6.0, 10.0, 2.0, 10, 2)
	check(hud.stat_label.text == "SUR CIBLE" and hud.metric_label.text == "60 %" and hud.score_label.text == "Score 600" and not hud.expired_label.visible, "Le tracking V2 conserve temps sur cible et score, sans légende de clic.")
	hud.present_live(10.0, 30.0, 8, 10, false, 0.0, 0.0, 2.0)
	check(hud.metric_label.text == "8 · 80 %" and hud.score_label.text == "Score 256" and not hud.expired_label.visible, "Revenir aux anciens arguments restaure exactement le comportement V1.")


func test_render() -> void:
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hud.configure(profile())
	hud.set_training_view(true, false)
	hud.present_live(10.0, 30.0, 8, 10, false, 0.0, 0.0, 2.0, 2, 2)
	await process_frame
	await process_frame
	hud.hit()
	hud.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	check(not rendered.is_empty(), "La capture provient d’un rendu réel de l’arène et du HUD.")
	if rendered.is_empty():
		return
	var segments := hud.hitmarker_segments()
	var center_px := hud.size * 0.5
	var inner_px := segments[0].distance_to(center_px)
	for segment_index in 4:
		var middle_px := (segments[segment_index * 2] + segments[segment_index * 2 + 1]) * 0.5
		var color := rendered.get_pixel(roundi(middle_px.x), roundi(middle_px.y))
		check(color.r > 0.8 and color.g > 0.6 and color.b < 0.65, "Chaque petit trait diagonal ambre est visible dans les pixels rendus.")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var position_px: Vector2 = center_px + direction * (inner_px + 2.5)
		var color := rendered.get_pixel(roundi(position_px.x), roundi(position_px.y))
		check(not (color.r > 0.8 and color.g > 0.6 and color.b < 0.65), "Le rendu n’ajoute aucun bras cardinal prolongeant le viseur.")
	var capture_path := "/tmp/aimtrainer-presentation-080.png"
	check(rendered.save_png(capture_path) == OK, "La capture 0.8 est enregistrée hors du checkout partagé.")
	print("PRESENTATION 080 CAPTURE : " + capture_path)
	hud.stop()
