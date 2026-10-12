extends RefCounted

const ArenaScene := preload("res://scenes/training/Arena.tscn")
const HudScript := preload("res://scripts/ui/training_hud.gd")

var verify: Callable
var failure_count: int = 0


func expect(condition: bool, description: String) -> void:
	if not condition:
		failure_count += 1
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	failure_count = 0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var arena: Node3D = ArenaScene.instantiate()
	viewport.add_child(arena)
	await tree.process_frame
	test_arena(arena)
	var hud: TrainingHud = HudScript.new()
	hud.configure(profile())
	viewport.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tree.process_frame
	var cues: Array[String] = []
	hud.countdown_feedback.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	test_pcm(hud)
	await test_countdown(hud, cues, tree)
	test_silence_and_reduced_motion(hud, cues)
	await test_stops(hud, cues, tree)
	test_hitmarker(hud)
	if DisplayServer.get_name() != "headless":
		await test_render(viewport, arena, hud, tree)
	else:
		print("PRESENTATION 0.7 : rendu et écoute matériels non exécutés en headless.")
	hud.stop()
	viewport.queue_free()
	await tree.create_timer(0.15).timeout
	await tree.process_frame
	await tree.process_frame
	verify = Callable()
	return failure_count == 0


func profile() -> Dictionary:
	return {"sound_enabled": true, "sound_volume": 37.0, "show_weapon": false,
		"reduced_motion": false, "crosshair_style": "cross", "crosshair_size_px": 6.0,
		"crosshair_gap_px": 4.0, "crosshair_thickness_px": 2.0,
		"crosshair_color": "#54e6cf", "crosshair_outline": true}


func test_arena(arena: Node3D) -> void:
	var lights := arena.find_children("*", "Light3D", true, false)
	expect(lights.size() == 1 and lights[0] is DirectionalLight3D, "Le monde contient exactement une source directionnelle ; aucun FillLight contradictoire.")
	var key := arena.get_node("Light") as DirectionalLight3D
	expect(key.shadow_enabled and key.light_energy > 0.0, "La source commune projette de vraies ombres 3D.")
	var environment: Environment = (arena.get_node("Environment") as WorldEnvironment).environment
	expect(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and environment.ambient_light_energy >= 0.4, "Un ambiant neutre rend le laboratoire clair sans autre source directionnelle.")
	var camera := arena.get_node("AimCamera") as AimCamera
	expect(camera.position == Vector3(0, 1.6, 0) and camera.fov == 75.0 and camera.keep_aspect == Camera3D.KEEP_HEIGHT, "L’origine et le FOV vertical de la caméra de visée restent identiques.")
	var presentation := arena.get_node("Presentation") as ArenaPresentation
	expect(presentation.environment_meshes.size() == 7 and arena.find_children("*", "", true, false).size() <= 32, "Le laboratoire simplifié conserve sept volumes et moins de 32 nœuds au total, cibles incluses.")
	expect(not presentation.is_processing() and not presentation.is_physics_processing(), "Le décor reste entièrement statique, sans traitement par frame.")
	for instance: MeshInstance3D in arena.find_children("*", "MeshInstance3D", true, false):
		var material := instance.mesh.surface_get_material(0) as StandardMaterial3D
		expect(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not material.emission_enabled, "Chaque objet du monde et cible possède un matériau mat réellement éclairé.")
		expect((instance.layers & key.light_cull_mask) == instance.layers and instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Chaque objet du monde et cible reçoit la même clé et participe aux ombres 3D.")
	for instance in presentation.environment_meshes:
		test_bevel(instance.mesh as ArrayMesh)
		var bounds := instance.mesh.get_aabb()
		bounds.position += instance.position
		expect(not (bounds.position.x < -3.0 and bounds.end.x > 3.0 and bounds.end.y > 1.0), "Aucune poutre ou panneau saillant ne traverse le fond de la zone de tir.")
	var reference_mesh := (arena.get_node("ReferenceSphere") as MeshInstance3D).mesh as SphereMesh
	expect(reference_mesh.radial_segments >= 64 and reference_mesh.rings >= 32, "La sphère de réalignement possède une silhouette aussi régulière que les cibles.")
	var pool := arena.get_node("TargetPool") as TargetPool
	expect(pool.spheres.size() == 6 and (pool.spheres[0].mesh as SphereMesh).radius == 1.0, "Le pool et la géométrie des hitboxes conservent leurs dimensions d’origine.")


func test_bevel(mesh: ArrayMesh) -> void:
	expect(mesh != null and mesh.get_surface_count() == 1, "Les biseaux sont une seule surface statique, pas des nœuds ajoutés.")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var valid_normals := true
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
	expect(valid_normals and vertices.size() == 132, "Les six faces, douze biseaux et huit coins possèdent des normales sortantes et un winding cohérent.")
	var closed := true
	for count: int in edge_counts.values():
		closed = closed and count == 2
	expect(closed, "Chaque arête est partagée exactement deux fois : le volume biseauté est fermé et sans trou.")


func test_pcm(hud: TrainingHud) -> void:
	var feedback := hud.countdown_feedback
	expect(feedback.get_child_count() == 2 and not feedback.is_processing() and not feedback.is_physics_processing(), "Deux voix audio sont préallouées ; aucun générateur ni traitement permanent.")
	for player: AudioStreamPlayer in [feedback.tick_player, feedback.go_player]:
		var stream := player.stream as AudioStreamWAV
		expect(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == 24000 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Chaque bip original est du PCM mono 16 bits à 24 kHz sans compression ni boucle.")
		var peak: int = 0
		for frame_index in stream.data.size() / 2:
			peak = maxi(peak, absi(stream.data.decode_s16(frame_index * 2)))
		expect(peak > 1000 and peak < 8000 and stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0, "Le son est réel, sans saturation, avec attaque et fin à zéro.")
		expect(is_equal_approx(player.volume_linear, 0.37), "Le volume audio suit exactement les 37 % du profil.")
	expect(is_equal_approx(feedback.tick_player.stream.get_length(), 0.065) and is_equal_approx(feedback.go_player.stream.get_length(), 0.12), "Le tick est court et le GO possède un signal distinct, sans son soutenu.")


func test_countdown(hud: TrainingHud, cues: Array[String], tree: SceneTree) -> void:
	var tick_player_id := hud.countdown_feedback.tick_player.get_instance_id()
	var go_player_id := hud.countdown_feedback.go_player.get_instance_id()
	var tick_stream_id := hud.countdown_feedback.tick_player.stream.get_instance_id()
	var go_stream_id := hud.countdown_feedback.go_player.stream.get_instance_id()
	hud.set_training_view(false, true)
	hud.begin_countdown()
	hud.countdown_label.text = "3"
	hud.countdown_label.show()
	hud.queue_redraw()
	await tree.process_frame
	await tree.process_frame
	expect(cues.is_empty(), "Modifier le label, le montrer et le dessiner ne déclenche jamais automatiquement de son.")
	hud.present_countdown("3")
	expect(cues == ["3"] and hud.countdown_remaining_s > 0.0, "Afficher 3 joue un seul tick et une impulsion visuelle.")
	for redraw_index in 4:
		hud.sync_countdown()
		hud.queue_redraw()
		hud.countdown_label.queue_redraw()
		await tree.process_frame
	expect(cues == ["3"], "Les redraws et les appels synchrones ne rejouent pas le chiffre.")
	for text in ["→", "←", "↑", "↓", "0", "", "ATTENTE", "3"]:
		hud.present_countdown(text)
		expect(cues == ["3"], "Flèches, attente et retour au même chiffre ne produisent aucun bip supplémentaire.")
	hud.present_countdown("2")
	hud.present_countdown("1")
	hud.set_training_view(true, false)
	hud.show_go()
	hud.show_go()
	expect(cues == ["3", "2", "1", "GO"] and hud.go_label.visible, "La séquence complète joue précisément 3, 2, 1 et un seul GO.")
	hud._process(1.0)
	expect(not hud.is_processing() and not hud.go_label.visible, "L’impulsion GO s’arrête et le HUD retrouve un coût nul au repos.")
	hud.show_go()
	expect(cues.size() == 4, "La fin de l’animation ne réarme pas le GO.")
	expect(tick_player_id == hud.countdown_feedback.tick_player.get_instance_id() and go_player_id == hud.countdown_feedback.go_player.get_instance_id() and tick_stream_id == hud.countdown_feedback.tick_player.stream.get_instance_id() and go_stream_id == hud.countdown_feedback.go_player.stream.get_instance_id(), "Tout le décompte réutilise les voix et données PCM allouées au démarrage.")


func test_silence_and_reduced_motion(hud: TrainingHud, cues: Array[String]) -> void:
	hud.begin_countdown()
	hud.set_training_view(false, true)
	var initial_count := cues.size()
	var silent := profile()
	silent.sound_enabled = false
	hud.configure(silent)
	hud.present_countdown("3")
	hud.configure(profile())
	hud.present_countdown("→")
	hud.present_countdown("3")
	expect(cues.size() == initial_count, "Désactiver puis réactiver le son ne rattrape pas un chiffre consommé en silence.")
	silent = profile()
	silent.sound_volume = 0.0
	hud.configure(silent)
	hud.present_countdown("2")
	hud.configure(profile())
	hud.sync_countdown()
	expect(cues.size() == initial_count, "Un volume nul est silencieux et sa remontée ne déclenche aucun rattrapage.")
	hud.present_countdown("1")
	expect(cues.size() == initial_count + 1 and cues.back() == "1", "Le prochain chiffre inédit suit la préférence audio actuelle.")
	var reduced := profile()
	reduced.reduced_motion = true
	hud.configure(reduced)
	hud.begin_countdown()
	hud.present_countdown("3")
	expect(cues.back() == "3" and hud.countdown_remaining_s == 0.0 and hud.countdown_label.scale == Vector2.ONE, "Les animations réduites conservent le bip et un chiffre parfaitement immobile.")
	hud.set_training_view(true, false)
	hud.show_go()
	expect(cues.back() == "GO" and not hud.go_label.visible and not hud.is_processing(), "Le mode réduit garde le GO sonore sans animation ou traitement permanent.")
	hud.stop()
	var stopped_count := cues.size()
	hud.show_go()
	expect(cues.size() == stopped_count and not hud.countdown_feedback.tick_player.playing and not hud.countdown_feedback.go_player.playing, "Stop coupe aussi les voix en mode réduit sans réarmer le GO.")


func stop_path(hud: TrainingHud, tree: SceneTree, path: String) -> void:
	match path:
		"focus": hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		"hidden": hud.hide()
		"pause": tree.paused = true
		"weapon": hud.weapon_feedback.stop()
		_: hud.stop()


func restore(hud: TrainingHud, tree: SceneTree) -> void:
	tree.paused = false
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	hud.show()


func test_stops(hud: TrainingHud, cues: Array[String], tree: SceneTree) -> void:
	for path in ["stop", "focus", "hidden", "pause", "weapon"]:
		restore(hud, tree)
		hud.configure(profile())
		hud.begin_countdown()
		hud.set_training_view(false, true)
		hud.present_countdown("3")
		var initial_count := cues.size()
		stop_path(hud, tree, path)
		expect(not hud.countdown_feedback.tick_player.playing and not hud.countdown_feedback.go_player.playing and not hud.is_processing(), "Le chemin d’arrêt coupe immédiatement son et animations : " + path)
		restore(hud, tree)
		hud.sync_countdown()
		hud.present_countdown("→")
		hud.present_countdown("3")
		await tree.process_frame
		expect(cues.size() == initial_count, "Reprise et redraw ne rejouent pas le chiffre arrêté : " + path)
		hud.present_countdown("2")
		expect(cues.size() == initial_count + 1, "La reprise autorise uniquement le chiffre suivant : " + path)
		hud.set_training_view(true, false)
		hud.show_go()
		initial_count = cues.size()
		stop_path(hud, tree, path)
		restore(hud, tree)
		hud.show_go()
		expect(cues.size() == initial_count and not hud.countdown_feedback.go_player.playing, "Un GO arrêté ne repart jamais à la reprise : " + path)
	hud.begin_countdown()
	hud.set_training_view(false, true)
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var initial_count := cues.size()
	hud.present_countdown("2")
	restore(hud, tree)
	hud.sync_countdown()
	expect(cues.size() == initial_count, "Un chiffre reçu sans focus est consommé silencieusement, sans bip au retour.")
	hud.present_countdown("1")
	expect(cues.size() == initial_count + 1, "Le retour de focus permet le prochain chiffre sans rejouer celui manqué.")
	hud.stop()


func test_hitmarker(hud: TrainingHud) -> void:
	hud.configure(profile())
	hud.set_training_view(true, false)
	for dimensions in [Vector2(800, 450), Vector2(1280, 720), Vector2(1920, 1080)]:
		hud.size = dimensions
		var center_px: Vector2 = dimensions * 0.5
		var segments := hud.hitmarker_segments()
		expect(segments.size() == 8 and HudScript.HIT_COLOR != Color.html(hud.crosshair_profile.crosshair_color), "Le hitmarker présente quatre ticks ambre distincts du viseur turquoise.")
		for segment_index in 4:
			var first_px: Vector2 = segments[segment_index * 2] - center_px
			var last_px: Vector2 = segments[segment_index * 2 + 1] - center_px
			expect((is_zero_approx(first_px.x) or is_zero_approx(first_px.y)) and is_equal_approx(first_px.distance_to(last_px), 5.0) and first_px.length() > CrosshairProfile.radius_px(hud.crosshair_profile) + 4.0, "Chaque tick reste orthogonal, compact et hors du viseur ; aucune diagonale au centre.")
		expect((segments[0] + segments[2]).is_equal_approx(center_px * 2.0) and (segments[4] + segments[6]).is_equal_approx(center_px * 2.0), "Les ticks sont symétriques autour du centre aux trois tailles de fenêtre.")
	hud.hit()
	hud._process(0.06)
	expect(hud.hit_remaining_s > 0.0, "Une vraie touche conserve son retour compact pendant au moins 60 ms.")
	hud._process(0.06)
	expect(hud.hit_remaining_s == 0.0 and not hud.is_processing(), "Le retour de touche s’éteint sans traitement permanent.")
	hud.stop()


func test_render(viewport: SubViewport, arena: Node3D, hud: TrainingHud, tree: SceneTree) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hud.size = Vector2(viewport.size)
	(arena.get_node("ReferenceSphere") as MeshInstance3D).hide()
	var pool := arena.get_node("TargetPool") as TargetPool
	var engine := ScenarioEngine.new()
	expect(engine.start(ScenarioCatalog.find("C03"), 700, 30.0), "La capture emploie de vraies cibles C03, sans déplacer leur géométrie.")
	pool.sync(engine, 0.0)
	var original_transform := pool.spheres[0].global_transform
	var camera := arena.get_node("AimCamera") as Camera3D
	var original_camera := camera.global_transform
	hud.hit()
	hud.set_process(false)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	expect(not rendered.is_empty(), "La capture est un rendu OpenGL réel du laboratoire et du HUD.")
	var center_px := Vector2(viewport.size) * 0.5
	var background := rendered.get_pixel(viewport.size.x / 2, viewport.size.y / 4)
	expect(background.r > 0.55 and background.r < 0.97 and background.g < 0.97 and background.b < 0.97, "Le mur central reste lumineux et conserve ses nuances, sans saturation blanche.")
	var segments := hud.hitmarker_segments()
	for segment_index in 4:
		var middle_px := (segments[segment_index * 2] + segments[segment_index * 2 + 1]) * 0.5
		var color := rendered.get_pixel(roundi(middle_px.x), roundi(middle_px.y))
		expect(color.r > 0.8 and color.g > 0.6 and color.b < 0.65, "Chaque tick ambre est présent dans les pixels réellement rendus.")
	var diagonal := rendered.get_pixel(roundi(center_px.x + 14.0), roundi(center_px.y + 14.0))
	expect(not (diagonal.r > 0.9 and diagonal.g > 0.7 and diagonal.b < 0.65), "Le hitmarker n’ajoute aucune diagonale autour du centre rendu.")
	expect(original_camera == camera.global_transform and original_transform == pool.spheres[0].global_transform, "Les feedbacks rendus ne modifient ni caméra ni cible réelle.")
	var capture_path := "/tmp/aimtrainer-presentation-070.png"
	expect(rendered.save_png(capture_path) == OK, "La capture réelle est enregistrée hors du checkout partagé.")
	print("PRESENTATION 0.7 CAPTURE : " + capture_path)
	hud.stop()
