extends SceneTree

const FeedbackScript := preload("res://scripts/presentation/weapon_feedback.gd")
const HudScript := preload("res://scripts/ui/training_hud.gd")
const CameraScript := preload("res://scripts/input/aim_camera.gd")

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Les tests d’animation n’ont pas terminé en 60 secondes.")
		quit(1))
	run_standalone.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_standalone() -> void:
	await run_suite(self, check)
	if "--capture-weapons" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			check(false, "Un affichage graphique est requis pour les captures d’arme.")
		else:
			await capture_weapons()
	print("WEAPON ANIMATION : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


static func run_suite(tree: SceneTree, verify: Callable) -> void:
	var feedback: WeaponFeedback = FeedbackScript.new()
	feedback.size = Vector2(1280, 720)
	feedback.set_hud_mode(true)
	tree.root.add_child(feedback)
	await tree.process_frame
	verify.call(feedback.players.size() == 4 and feedback.get_child_count() == 5, "Quatre voix de tir et une boucle sont préallouées.")
	test_models(feedback, verify)
	var allocated_nodes := count_nodes(feedback)
	for definition in WeaponCatalog.DEFINITIONS:
		test_alignment(feedback, definition, verify)
		test_shot(feedback, definition, verify)
		test_continuous(feedback, definition, verify)
		test_preferences(feedback, definition, verify)
		test_preview(feedback, definition, verify)
	verify.call(count_nodes(feedback) == allocated_nodes, "Changer de profil réutilise tous les meshes, slides, marqueurs et effets préalloués.")
	test_stop_paths(feedback, verify)
	await test_pause(tree, feedback, verify)
	await test_camera_isolation(tree, feedback, verify)
	feedback.queue_free()
	await tree.process_frame
	await test_hud(tree, verify)
	await tree.create_timer(0.15).timeout


static func count_nodes(parent: Node) -> int:
	var total: int = 1
	for child in parent.get_children(true):
		total += count_nodes(child)
	return total


static func test_models(feedback: WeaponFeedback, verify: Callable) -> void:
	var viewmodel := feedback.viewmodel
	verify.call(viewmodel != null and viewmodel.models.size() == 3, "Les trois profils originaux possèdent un modèle 3D préalloué.")
	verify.call(viewmodel.viewport.own_world_3d and viewmodel.viewport.transparent_bg, "Le rendu possède un monde 3D isolé et un fond transparent.")
	verify.call(viewmodel.viewport.world_3d != feedback.get_viewport().world_3d, "L’arme et les cibles ne partagent ni monde ni éclairage.")
	verify.call(viewmodel.viewport.gui_disable_input and not viewmodel.viewport.physics_object_picking and viewmodel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Le viewport d’arme ne reçoit pas d’input et ne fait aucun picking.")
	verify.call(not viewmodel.is_processing() and viewmodel.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Le renderer n’ajoute aucun traitement permanent.")
	verify.call(viewmodel.stage.find_children("*", "CollisionObject3D", true, false).is_empty(), "Aucun collider de premier plan ne peut intercepter un tir.")
	var solid_mesh_count: int = 0
	var beveled_mesh_count: int = 0
	for instance in viewmodel.meshes:
		var bounds_m := instance.mesh.get_aabb().size
		if bounds_m.x > 0.0 and bounds_m.y > 0.0 and bounds_m.z > 0.0 and not instance.mesh is QuadMesh:
			solid_mesh_count += 1
		if instance.mesh is ArrayMesh:
			beveled_mesh_count += 1
	verify.call(solid_mesh_count == viewmodel.meshes.size() and solid_mesh_count > 60 and beveled_mesh_count > 40, "Les armes sont des volumes hard-surface à facettes, pas des plans texturés.")
	var pulse: Node3D = viewmodel.models["pulse"]
	var vector: Node3D = viewmodel.models["vector"]
	var classic: Node3D = viewmodel.models["classic"]
	verify.call(pulse.has_node("InductionCollar0") and vector.has_node("StockBrace") and classic.has_node("TriggerGuardFront"), "Pulse, Vector et Classic possèdent des silhouettes et détails distincts.")
	verify.call((pulse.get_node("Muzzle") as Marker3D).position.z != (classic.get_node("Muzzle") as Marker3D).position.z and (vector.get_node("Muzzle") as Marker3D).position.z < (pulse.get_node("Muzzle") as Marker3D).position.z, "Les longueurs de canon distinguent les trois modèles.")
	var without_sprite: WeaponDefinition = WeaponCatalog.DEFINITIONS[0].duplicate()
	without_sprite.sprite = null
	without_sprite.muzzle_uv = Vector2(0.99, 0.99)
	feedback.configure(without_sprite, false, 0.0, true, false)
	verify.call(viewmodel.visible and viewmodel.muzzle != null, "Le renderer ne dépend plus du sprite ni de son ancienne position de canon.")


static func verify_axis(feedback: WeaponFeedback, verify: Callable) -> void:
	var viewmodel := feedback.viewmodel
	var toward_aim := (viewmodel.aim_point_m - viewmodel.muzzle.global_position).normalized()
	verify.call(viewmodel.muzzle_axis().dot(toward_aim) > 0.99999, "L’axe réel du canon pointe vers le réticule, même pendant le recul.")
	verify.call(viewmodel.project_to_control(viewmodel.aim_point_m).distance_to(feedback.size * 0.5) < 0.02, "Le point de visée se projette sur le centre du HUD : %s au lieu de %s." % [viewmodel.project_to_control(viewmodel.aim_point_m), feedback.size * 0.5])
	var muzzle_px := feedback.muzzle_position()
	var projected_axis := viewmodel.project_to_control(viewmodel.muzzle.global_position + viewmodel.muzzle_axis() * 0.3) - muzzle_px
	verify.call(projected_axis.normalized().dot((feedback.size * 0.5 - muzzle_px).normalized()) > 0.9999, "La direction projetée du canon converge vers le viseur sans image latérale.")
	var model: Node3D = viewmodel.models[viewmodel.selected_id]
	var barrel: MeshInstance3D = model.get_node("OctagonalBarrel" if viewmodel.selected_id == "pulse" else "Barrel")
	verify.call((-barrel.global_basis.y).normalized().dot(viewmodel.muzzle_axis()) > 0.99999, "Le marqueur du flash correspond à l’axe du mesh de canon.")


static func test_alignment(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.set_hud_mode(true)
	feedback.configure(definition, false, 0.45, true, false)
	for dimensions in [Vector2(800, 450), Vector2(1280, 720), Vector2(1920, 1080), Vector2(3440, 1440), Vector2(640, 640), Vector2(600, 900), Vector2(320, 180)]:
		feedback.size = dimensions
		feedback.sync_layout()
		var rectangle := feedback.sprite_rect()
		verify.call(rectangle.position.x > dimensions.x * 0.5 + feedback.crosshair_clearance_px and rectangle.position.y > dimensions.y * 0.5 + feedback.crosshair_clearance_px, "La région transparente laisse une zone centrale entièrement libre.")
		verify.call(rectangle.end.is_equal_approx(dimensions) and feedback.clip_contents and feedback.viewmodel.clip_contents, "Le rendu reste accroché aux bords droit et bas, et doublement clippé.")
		verify.call(feedback.viewmodel.viewport.size.x <= 960 and feedback.viewmodel.viewport.size.y <= 540, "La résolution du viewport reste bornée sur écran large.")
		verify_axis(feedback, verify)
		feedback.play_shot()
		verify_axis(feedback, verify)
		verify.call(feedback.muzzle_position().x > dimensions.x * 0.5 and feedback.muzzle_position().y > dimensions.y * 0.5, "Le canon reste dans le quadrant inférieur droit : %s pour %s." % [feedback.muzzle_position(), dimensions])
		var segment := feedback.tracer_segment()
		verify.call(segment.size() == 2 and segment[0].distance_to(dimensions * 0.5) > segment[1].distance_to(dimensions * 0.5), "La trace cosmétique va du canon vers le viseur.")
		verify.call(segment.size() == 2 and segment[1].distance_to(dimensions * 0.5) >= feedback.crosshair_clearance_px + 2.0, "La trace ne pénètre jamais la réserve du viseur.")
		feedback.stop()
	feedback.size = Vector2(800, 450)
	feedback.crosshair_clearance_px = 100.0
	feedback.play_shot()
	var segment := feedback.tracer_segment()
	verify.call(feedback.sprite_rect().position.y >= 333.0 and (segment.is_empty() or segment[1].distance_to(feedback.size * 0.5) >= 102.0), "Une grande réserve personnalisée repousse aussi le viewport et le tracer.")
	feedback.crosshair_clearance_px = 18.0
	feedback.stop()


static func test_shot(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.set_hud_mode(true)
	feedback.size = Vector2(1280, 720)
	feedback.configure(definition, false, 0.45, true, false)
	var resting_muzzle := feedback.muzzle_position()
	feedback.sync_layout()
	var resting_transform := feedback.viewmodel.weapon_root.transform
	var node_count := count_nodes(feedback)
	var flash_id := feedback.viewmodel.flash.get_instance_id()
	var shot_count := feedback.shot_count
	feedback.play_shot()
	verify.call(feedback.shot_count == shot_count + 1 and not feedback.continuous_active, "Un appel de tir ne déclenche ni automatique ni deuxième tir.")
	verify.call(feedback.muzzle_position().distance_to(resting_muzzle) > 10.0 and feedback.viewmodel.weapon_root.position.distance_to(resting_transform.origin) > 0.1, "Le recul déplace réellement le modèle dans les trois dimensions.")
	verify.call(feedback.flash_remaining_s > 0.0 and feedback.tracer_remaining_s > 0.0 and feedback.is_processing(), "Le flash et le tracer démarrent immédiatement avec le recul.")
	verify.call(feedback.viewmodel.flash.visible and feedback.viewmodel.flash.global_position.is_equal_approx(feedback.viewmodel.muzzle.global_position), "Le flash 3D suit le canon, recul compris.")
	verify.call(feedback.viewmodel.slide.position.z > 0.08 and feedback.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "Le slide recule et le viewport ne rend que tant que son contrôle est visible.")
	feedback._process(0.08)
	verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0, "Le flash et le tracer s’éteignent rapidement sans éclairer toute la scène.")
	verify.call(feedback.muzzle_position().distance_to(resting_muzzle) > 3.0 and feedback.is_processing() and not feedback.viewmodel.flash.visible, "Le retour 3D continue après la disparition du flash.")
	feedback._process(0.3)
	verify.call(feedback.viewmodel.weapon_root.transform.is_equal_approx(resting_transform) and feedback.viewmodel.slide.position == Vector3.ZERO and not feedback.is_processing(), "L’arme et le slide reviennent exactement au repos sans traitement permanent.")
	verify.call(feedback.viewmodel.viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED], "Le dernier rendu au repos remplace le rendu continu.")
	verify.call(feedback.shot_count == shot_count + 1, "L’animation d’un tir n’en génère pas d’autres.")
	var reference_transform := Transform3D.IDENTITY
	for frame_rate in [60.0, 144.0, 240.0]:
		feedback.play_shot()
		advance(feedback, 0.11, frame_rate)
		if frame_rate == 60.0:
			reference_transform = feedback.viewmodel.weapon_root.transform
		verify.call(feedback.viewmodel.weapon_root.transform.is_equal_approx(reference_transform), "Le recul à temps égal ne dépend pas des FPS synthétiques.")
		feedback.stop()
	for repeat_index in 100:
		feedback.play_shot()
	verify.call(feedback.players.size() == 4 and feedback.get_child_count() == 5, "Les tirs rapprochés ne créent aucune nouvelle voix ou nœud.")
	verify.call(count_nodes(feedback) == node_count and feedback.viewmodel.flash.get_instance_id() == flash_id, "Cent tirs réutilisent aussi tous les nœuds du renderer et le même flash 3D.")
	verify.call(feedback.muzzle_position().distance_to(resting_muzzle) < 40.0, "Le recul ne s’accumule pas avec le spam de clics.")
	feedback.stop()


static func test_continuous(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.configure(definition, false, 0.45, true, false)
	var shot_count := feedback.shot_count
	feedback.set_continuous(true)
	feedback._process(definition.continuous_interval_s * 0.75)
	var returning_muzzle := feedback.muzzle_position()
	feedback._process(definition.continuous_interval_s * 0.3)
	verify.call(feedback.muzzle_position().distance_to(returning_muzzle) > 3.0, "Une nouvelle impulsion de tracking anime réellement le modèle 3D.")
	verify.call(feedback.flash_remaining_s > 0.0 and feedback.continuous_active, "Le feedback continu suit la cadence cosmétique du profil.")
	verify.call(feedback.shot_count == shot_count, "La boucle de tracking ne comptabilise aucun tir de clic.")
	feedback.set_continuous(false)
	verify.call(not feedback.continuous_active and not feedback.continuous_player.playing, "Relâcher coupe immédiatement la boucle audio.")
	feedback._process(0.3)
	verify.call(not feedback.is_processing(), "Le retour au repos s’arrête aussi après la fin de boucle.")
	var reference_transform := Transform3D.IDENTITY
	var reference_flash_s: float = 0.0
	for frame_rate in [60.0, 144.0, 240.0]:
		feedback.stop()
		feedback.set_continuous(true)
		advance(feedback, definition.continuous_interval_s * 2.0 + 0.037, frame_rate)
		if frame_rate == 60.0:
			reference_transform = feedback.viewmodel.weapon_root.transform
			reference_flash_s = feedback.flash_remaining_s
		verify.call(feedback.viewmodel.weapon_root.transform.is_equal_approx(reference_transform) and is_equal_approx(feedback.flash_remaining_s, reference_flash_s), "Les impulsions continues conservent leur phase à FPS synthétiques différents.")
	feedback.stop()
	feedback.set_continuous(true)
	feedback._process(definition.continuous_interval_s * 20.0 + 0.037)
	verify.call(is_equal_approx(feedback.recoil_elapsed_s, 0.037) and feedback.get_child_count() == 5, "Une longue frame ne crée pas de rafale de rattrapage ni de nouveaux nœuds.")
	feedback.stop()


static func advance(feedback: WeaponFeedback, duration_s: float, frame_rate: float) -> void:
	var elapsed_s: float = 0.0
	while elapsed_s < duration_s:
		var delta_s := minf(1.0 / frame_rate, duration_s - elapsed_s)
		feedback._process(delta_s)
		elapsed_s += delta_s


static func test_preferences(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.configure(definition, false, 0.45, true, false)
	feedback.play_shot()
	var voices_playing: bool = false
	for player in feedback.players:
		voices_playing = voices_playing or player.playing
	verify.call(not voices_playing and feedback.recoil_elapsed_s == 0.0, "Le silence coupe le son mais conserve le retour visuel.")
	feedback.configure(definition, true, 0.0, true, false)
	feedback.set_continuous(true)
	verify.call(not feedback.continuous_player.playing, "Un volume nul reste silencieux pendant le maintien.")
	feedback.configure(definition, false, 0.45, true, true)
	var resting_transform := feedback.viewmodel.weapon_root.transform
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.viewmodel.weapon_root.transform.is_equal_approx(resting_transform) and feedback.viewmodel.slide.position == Vector3.ZERO and not feedback.viewmodel.flash.visible and feedback.tracer_segment().is_empty() and feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and not feedback.is_processing(), "Réduire les animations désactive recul, slide, flash et tracer.")
	verify.call(feedback.viewmodel.viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED], "Le mouvement réduit laisse une arme statique sans viewport animé.")
	feedback.configure(definition, false, 0.45, false, false)
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and not feedback.is_processing(), "Masquer l’arme masque aussi ses effets visuels.")
	verify.call(not feedback.viewmodel.visible and feedback.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and feedback.viewmodel.viewport.process_mode == Node.PROCESS_MODE_DISABLED, "Masquer l’arme coupe aussi le rendu et le traitement du viewport.")
	feedback.configure(definition, true, 0.45, false, false)
	feedback.play_shot()
	voices_playing = false
	for player in feedback.players:
		voices_playing = voices_playing or player.playing
	verify.call(voices_playing, "Masquer le sprite ne désactive pas le son choisi séparément.")
	feedback.configure(definition, false, 0.45, true, false)
	feedback.play_shot()
	feedback.reduced_motion = true
	verify.call(not feedback.viewmodel.flash.visible and not feedback.is_processing() and feedback.tracer_segment().is_empty(), "Activer le mouvement réduit pendant un tir efface les effets immédiatement.")
	feedback.reduced_motion = false
	feedback.play_shot()
	feedback.show_sprite = false
	verify.call(not feedback.viewmodel.visible and not feedback.viewmodel.flash.visible and not feedback.is_processing(), "Masquer le modèle pendant le recul ne laisse aucun effet actif.")
	feedback.stop()


static func test_preview(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.set_hud_mode(false)
	feedback.configure(definition, false, 0.45, true, false)
	for dimensions in [Vector2(250, 125), Vector2(360, 200)]:
		feedback.size = dimensions
		feedback.play_shot()
		verify.call(feedback.tracer_remaining_s == 0.0 and feedback.clip_contents, "Les aperçus n’envoient aucun tracer hors de leur contrôle.")
		var rectangle := feedback.sprite_rect()
		verify.call(rectangle.position == Vector2.ZERO and rectangle.size.is_equal_approx(dimensions) and feedback.viewmodel.get_rect().is_equal_approx(rectangle), "L’aperçu 3D reste strictement clippé à son contrôle.")
		verify_axis(feedback, verify)
		verify.call(rectangle.has_point(feedback.muzzle_position()), "Le canon de l’aperçu reste dans son contrôle pendant le recul.")
		feedback.stop()
	feedback.set_hud_mode(true)


static func test_stop_paths(feedback: WeaponFeedback, verify: Callable) -> void:
	feedback.configure(WeaponCatalog.DEFINITIONS[0], true, 0.45, true, false)
	for stop_path in ["stop", "focus", "hidden", "configure"]:
		feedback.show()
		feedback.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		feedback.play_shot()
		feedback.set_continuous(true)
		if stop_path == "stop":
			feedback.stop()
		elif stop_path == "focus":
			feedback.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif stop_path == "hidden":
			feedback.hide()
		else:
			feedback.configure(WeaponCatalog.DEFINITIONS[1], true, 0.45, true, false)
		var voices_playing: bool = feedback.continuous_player.playing
		for player in feedback.players:
			voices_playing = voices_playing or player.playing
		verify.call(not voices_playing and not feedback.continuous_active and not feedback.is_processing(), "Pause, focus, masquage et changement d’arme coupent toutes les voix.")
		verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and feedback.recoil_elapsed_s == WeaponFeedback.RECOIL_DURATION_S, "L’arrêt efface tous les effets visuels en attente.")
		verify.call(not feedback.viewmodel.flash.visible and feedback.viewmodel.slide.position == Vector3.ZERO, "Chaque arrêt restaure aussi les effets et le slide du modèle 3D.")
		if stop_path in ["focus", "hidden"]:
			verify.call(feedback.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and feedback.viewmodel.viewport.process_mode == Node.PROCESS_MODE_DISABLED, "Focus perdu ou contrôle masqué coupe complètement le viewport.")
		feedback.show()
		verify.call(not feedback.continuous_active, "Afficher à nouveau ne reprend jamais un maintien fantôme.")
	feedback.hide()
	var shot_count := feedback.shot_count
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.shot_count == shot_count and not feedback.continuous_active, "Un contrôle masqué n’accepte aucun nouveau tir.")
	feedback.show()
	feedback.configure(null, false, 0.0, true, false)
	feedback.play_shot()
	verify.call(not feedback.is_processing() and feedback.shot_count == shot_count, "L’absence d’un profil ne provoque ni animation ni erreur.")
	verify.call(not feedback.viewmodel.visible and feedback.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Sans profil, aucun rendu d’arme précédente ne subsiste.")


static func test_pause(tree: SceneTree, feedback: WeaponFeedback, verify: Callable) -> void:
	feedback.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	feedback.configure(WeaponCatalog.DEFINITIONS[0], true, 0.45, true, false)
	feedback.play_shot()
	feedback.set_continuous(true)
	tree.paused = true
	verify.call(not feedback.continuous_active and not feedback.continuous_player.playing and not feedback.viewmodel.flash.visible, "La pause réelle arrête sons et effets 3D.")
	verify.call(feedback.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and feedback.viewmodel.viewport.process_mode == Node.PROCESS_MODE_DISABLED, "La pause désactive le rendu et le traitement du viewport isolé.")
	var shot_count := feedback.shot_count
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.shot_count == shot_count and not feedback.continuous_active, "Une pause refuse tout nouveau feedback.")
	tree.paused = false
	verify.call(not feedback.continuous_active and not feedback.is_processing() and not feedback.viewmodel.flash.visible, "Reprendre affiche seulement le modèle au repos.")
	var host := Control.new()
	tree.root.add_child(host)
	var child: WeaponFeedback = FeedbackScript.new()
	child.size = Vector2(800, 450)
	host.add_child(child)
	child.configure(WeaponCatalog.DEFINITIONS[0], true, 0.45, true, false)
	child.play_shot()
	child.set_continuous(true)
	host.hide()
	verify.call(not child.continuous_active and not child.viewmodel.visible and child.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Masquer un parent arrête également le renderer et le son.")
	host.queue_free()
	await tree.process_frame


static func test_camera_isolation(tree: SceneTree, feedback: WeaponFeedback, verify: Callable) -> void:
	var root_camera := tree.root.get_camera_3d()
	var world_viewport := SubViewport.new()
	world_viewport.size = Vector2i(1280, 720)
	world_viewport.own_world_3d = true
	world_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(world_viewport)
	var world_camera := CameraScript.new()
	world_viewport.add_child(world_camera)
	world_camera.position = Vector3(1.2, 2.0, 4.5)
	world_camera.fov = 75.0
	world_camera.apply_mouse_counts(Vector2(220.0, -90.0))
	world_camera.make_current()
	var camera_transform := world_camera.global_transform
	var received_counts: Vector2 = world_camera.received_counts
	var ray_origin_m := world_camera.project_ray_origin(Vector2(640, 360))
	var ray_direction := world_camera.project_ray_normal(Vector2(640, 360))
	var input_mode := Input.mouse_mode
	var accumulated_input := Input.use_accumulated_input
	for definition in WeaponCatalog.DEFINITIONS:
		feedback.configure(definition, false, 0.45, true, false)
		feedback.play_shot()
		feedback.set_continuous(true)
		feedback._process(0.037)
		feedback.stop()
	verify.call(world_viewport.get_camera_3d() == world_camera and tree.root.get_camera_3d() == root_camera, "Le viewmodel ne devient jamais la caméra de visée du monde ou du viewport racine.")
	verify.call(world_camera.global_transform.is_equal_approx(camera_transform) and world_camera.fov == 75.0 and world_camera.received_counts == received_counts, "Changer d’arme et tirer ne change ni pose, FOV ni counts de la caméra de visée.")
	verify.call(world_camera.project_ray_origin(Vector2(640, 360)).is_equal_approx(ray_origin_m) and world_camera.project_ray_normal(Vector2(640, 360)).is_equal_approx(ray_direction), "Les rayons mécaniques restent identiques pendant le rendu d’arme.")
	verify.call(Input.mouse_mode == input_mode and Input.use_accumulated_input == accumulated_input, "Le renderer ne modifie aucune préférence ou capture d’input.")
	world_viewport.queue_free()
	await tree.process_frame


static func test_hud(tree: SceneTree, verify: Callable) -> void:
	var hud: TrainingHud = HudScript.new()
	tree.root.add_child(hud)
	await tree.process_frame
	hud.configure({"weapon_id": "pulse", "sound_enabled": false, "sound_volume": 45.0, "show_weapon": true, "reduced_motion": false})
	for dimensions in [Vector2(800, 450), Vector2(1280, 720), Vector2(1920, 1080)]:
		hud.size = dimensions
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await tree.process_frame
		var rectangle := hud.weapon_feedback.sprite_rect()
		verify.call(hud.weapon_feedback.hud_mode and hud.weapon_feedback.size.is_equal_approx(dimensions), "Le contrôle de tir couvre le HUD sans créer de couche d’input.")
		verify.call(rectangle.size.x >= dimensions.x * 0.3 and rectangle.size.x <= dimensions.x * 0.45, "La région 3D occupe une place proportionnée dans le quadrant inférieur droit.")
		verify.call(not rectangle.has_point(dimensions * 0.5), "Le rendu 3D ne recouvre jamais le point de visée central.")
		verify.call(hud.weapon_feedback.muzzle_position().y > dimensions.y * 0.5, "Le canon reste sous les cibles centrales.")
		verify.call(rectangle.end.is_equal_approx(dimensions), "La prise en main se prolonge aux bords de l’écran, sans arme flottante.")
		verify.call(hud.weapon_feedback.get_index() == 0, "Les instructions et la progression se dessinent devant le modèle 3D.")
		verify.call(hud.weapon_feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Le retour de tir ne capture pas la souris.")
		hud.weapon_feedback.play_shot()
		hud.hit()
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		verify.call(hud.hit_remaining_s == 0.0 and not hud.weapon_feedback.is_processing(), "Le HUD entier se nettoie à la perte de focus.")
		hud.hide()
		hud.show()
		verify.call(hud.hit_remaining_s == 0.0 and not hud.weapon_feedback.continuous_active, "Revenir au HUD ne reprend aucun effet ou son précédent.")
	hud.queue_free()
	await tree.process_frame


func capture_weapons() -> void:
	var directory := OS.get_environment("AIM_LOCAL_WEAPON_CAPTURE_DIR")
	if directory.is_empty():
		directory = "/tmp/aimlocal-weapon-visual"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Le dossier isolé des captures est disponible.")
	var hud: TrainingHud = HudScript.new()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.title_label.text = "Retour de tir · contrôle graphique"
	hud.metric_label.text = "Données synthétiques"
	hud.help_label.text = "Le modèle 3D, le flash et le tracer restent cosmétiques."
	hud.countdown_label.hide()
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await create_timer(0.1).timeout
		for definition in WeaponCatalog.DEFINITIONS:
			hud.weapon_feedback.configure(definition, false, 0.0, true, false)
			for phase in ["repos", "tir", "retour"]:
				hud.weapon_feedback.stop()
				if phase != "repos":
					hud.weapon_feedback.play_shot()
					if phase == "retour":
						hud.weapon_feedback._process(0.11)
					hud.weapon_feedback.set_process(false)
				await RenderingServer.frame_post_draw
				var path := directory.path_join("%d-%s-%s.png" % [dimensions.x, definition.weapon_id, phase])
				check(root.get_texture().get_image().save_png(path) == OK, "Le rendu de l’arme a été capturé : " + path)
	hud.queue_free()
	await process_frame
	print("WEAPON CAPTURES : 27 rendus isolés dans " + directory)
