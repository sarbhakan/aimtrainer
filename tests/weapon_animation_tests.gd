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
	var started_us := Time.get_ticks_usec()
	await run_suite(self, check)
	if "--capture-weapons" in OS.get_cmdline_user_args() or "--capture-live-weapons" in OS.get_cmdline_user_args() or "--capture-inspection-weapons" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			check(false, "Un affichage graphique est requis pour les captures d’arme.")
		elif "--capture-live-weapons" in OS.get_cmdline_user_args():
			await capture_live_weapons()
		elif "--capture-inspection-weapons" in OS.get_cmdline_user_args():
			await capture_inspection_weapons()
		else:
			await capture_weapons()
	print("WEAPON ANIMATION : %d assertions, %d échecs." % [assertion_count, failure_count])
	print("WEAPON ELAPSED : %.3f s." % [float(Time.get_ticks_usec() - started_us) / 1000000.0])
	quit(0 if failure_count == 0 else 1)


static func run_suite(tree: SceneTree, verify: Callable) -> void:
	var feedback: WeaponFeedback = FeedbackScript.new()
	feedback.size = Vector2(1280, 720)
	feedback.set_hud_mode(true)
	tree.root.add_child(feedback)
	await tree.process_frame
	verify.call(feedback.players.size() == 4 and feedback.get_child_count() == 5, "Quatre voix de tir et une boucle sont préallouées.")
	test_models(feedback, verify)
	test_surfaces(feedback, verify)
	test_geometry(feedback, verify)
	test_grips(feedback, verify)
	var allocated_nodes := count_nodes(feedback)
	for definition in WeaponCatalog.DEFINITIONS:
		test_small_window_envelope(feedback, definition, verify)
		test_alignment(feedback, definition, verify)
		test_shot(feedback, definition, verify)
		test_continuous(feedback, definition, verify)
		test_preferences(feedback, definition, verify)
		test_preview(feedback, definition, verify)
	verify.call(count_nodes(feedback) == allocated_nodes, "Changer de profil réutilise tous les meshes, slides, marqueurs et effets préalloués.")
	test_stop_paths(feedback, verify)
	await test_pause(tree, feedback, verify)
	await test_camera_isolation(tree, feedback, verify)
	feedback.set_inspection_mode(true)
	await test_camera_isolation(tree, feedback, verify)
	feedback.queue_free()
	await tree.process_frame
	await test_inspection_switching(tree, verify)
	await test_hud(tree, verify)
	await test_hud_scores(tree, verify)
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


static func test_surfaces(feedback: WeaponFeedback, verify: Callable) -> void:
	var viewmodel := feedback.viewmodel
	var ivory_mesh: MeshInstance3D = viewmodel.models["pulse"].get_node("Slide/ChargingShroud")
	var graphite_mesh: MeshInstance3D = viewmodel.models["vector"].get_node("SlimReceiver")
	var steel_mesh: MeshInstance3D = viewmodel.models["classic"].get_node("Slide/SlideBody")
	var glove_mesh: MeshInstance3D = viewmodel.models["pulse"].get_node("GrippingHand/GlovedPalm")
	var ivory := ivory_mesh.material_override as StandardMaterial3D
	var graphite := graphite_mesh.material_override as StandardMaterial3D
	var steel := steel_mesh.material_override as StandardMaterial3D
	var glove := glove_mesh.material_override as StandardMaterial3D
	verify.call(ivory.albedo_color.get_luminance() > graphite.albedo_color.get_luminance() * 2.0, "La culasse perle se distingue franchement du châssis graphite.")
	verify.call(steel.metallic > ivory.metallic and steel.roughness < ivory.roughness and glove.roughness > ivory.roughness, "Acier satiné, revêtement perle et gant mat possèdent des réponses lumineuses distinctes.")
	var opaque_lit: bool = true
	var untextured: bool = true
	var no_glow: bool = true
	var casts_shadow: bool = true
	for instance in viewmodel.meshes:
		var surface := instance.material_override as StandardMaterial3D
		untextured = untextured and surface.albedo_texture == null and surface.normal_texture == null and surface.roughness_texture == null and surface.metallic_texture == null
		if viewmodel.flash.is_ancestor_of(instance):
			verify.call(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Le flash translucide ne projette aucune ombre.")
			continue
		opaque_lit = opaque_lit and surface.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and surface.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		no_glow = no_glow and not surface.emission_enabled
		casts_shadow = casts_shadow and instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	verify.call(untextured and opaque_lit and no_glow, "Armes et mains utilisent des volumes opaques éclairés sans texture ni émission décorative.")
	verify.call(casts_shadow, "Les volumes opaques peuvent porter leurs ombres locales dans le monde isolé.")
	var lights := viewmodel.stage.find_children("*", "DirectionalLight3D", true, false)
	var shadow_lights: int = 0
	for light: DirectionalLight3D in lights:
		if light.shadow_enabled:
			shadow_lights += 1
			verify.call(light.directional_shadow_max_distance <= 5.0 and light.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "L’ombre principale se limite à une projection et à la profondeur du viewmodel.")
	verify.call(lights.size() == 2 and shadow_lights == 1, "Une seule key projette des ombres ; le fill reste léger.")


static func test_geometry(feedback: WeaponFeedback, verify: Callable) -> void:
	var valid_normals: bool = true
	var valid_winding: bool = true
	var beveled_normals: bool = false
	var triangle_count: int = 0
	for instance in feedback.viewmodel.meshes:
		triangle_count += instance.mesh.get_faces().size() / 3
		if not instance.mesh is ArrayMesh:
			continue
		for surface_index in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			valid_normals = valid_normals and normals.size() == vertices.size()
			for normal in normals:
				valid_normals = valid_normals and normal.is_finite() and absf(normal.length_squared() - 1.0) < 0.001
				if absf(normal.x) > 0.1 and absf(normal.y) > 0.1:
					beveled_normals = true
			var element_count := vertices.size() if indices.is_empty() else indices.size()
			for element_index in range(0, element_count, 3):
				var first_index := element_index if indices.is_empty() else indices[element_index]
				var second_index := element_index + 1 if indices.is_empty() else indices[element_index + 1]
				var third_index := element_index + 2 if indices.is_empty() else indices[element_index + 2]
				var face := (vertices[second_index] - vertices[first_index]).cross(vertices[third_index] - vertices[first_index])
				valid_winding = valid_winding and face.length_squared() > 0.00000000000001 and face.dot(normals[first_index]) < 0.0
	verify.call(valid_normals and beveled_normals, "Les surfaces procédurales possèdent des normales unitaires finies, avec de vraies transitions de chanfrein.")
	verify.call(valid_winding, "Les triangles de chaque profil et chanfrein sont non dégénérés et orientés pour le culling Godot.")
	verify.call(feedback.viewmodel.meshes.size() <= 200 and triangle_count <= 24000, "Les trois armes, mains et flash restent dans un budget borné de 200 meshes et 24 000 triangles.")
	print("VIEWMODEL GEOMETRY : %d meshes, %d triangles préalloués." % [feedback.viewmodel.meshes.size(), triangle_count])


static func mesh_bounds_m(instance: MeshInstance3D) -> AABB:
	return instance.global_transform * instance.mesh.get_aabb()


static func test_grips(feedback: WeaponFeedback, verify: Callable) -> void:
	for model: Node3D in feedback.viewmodel.models.values():
		var hand: Node3D = model.get_node("GrippingHand")
		var grip: MeshInstance3D = model.get_node("Grip")
		var palm: MeshInstance3D = hand.get_node("GlovedPalm")
		var wrist: MeshInstance3D = hand.get_node("Wrist")
		var cuff: MeshInstance3D = hand.get_node("Cuff")
		var sleeve: MeshInstance3D = hand.get_node("Sleeve")
		verify.call(mesh_bounds_m(grip).intersects(mesh_bounds_m(palm)), "La paume enveloppe réellement la poignée de %s." % model.name)
		verify.call(mesh_bounds_m(palm).intersects(mesh_bounds_m(wrist)) and mesh_bounds_m(wrist).intersects(mesh_bounds_m(cuff)) and mesh_bounds_m(cuff).intersects(mesh_bounds_m(sleeve)), "La prise de %s se prolonge sans séparation jusqu’à la manche." % model.name)
		verify.call(hand.has_node("ThumbTip") and hand.has_node("IndexTip") and hand.has_node("Fingertip2") and not model.get_node("Slide").is_ancestor_of(hand), "Les doigts sont articulés et la main de %s ne suit pas le recul propre de la culasse." % model.name)
		for finger_index in 3:
			var fingertip: MeshInstance3D = hand.get_node("Fingertip%d" % finger_index)
			verify.call(mesh_bounds_m(fingertip).intersects(mesh_bounds_m(grip)), "L’extrémité du doigt %d de %s revient au contact de la poignée après l’enroulement." % [finger_index, model.name])
	var vector: Node3D = feedback.viewmodel.models["vector"]
	var support_palm: MeshInstance3D = vector.get_node("SupportHand/Palm")
	var foreguard: MeshInstance3D = vector.get_node("AngularForeguard")
	verify.call(mesh_bounds_m(support_palm).intersects(mesh_bounds_m(foreguard)), "La main de soutien de la carabine reste au contact du garde-main, sans marge artificielle.")


static func projected_bounds_px(viewmodel: WeaponViewmodel, instance: MeshInstance3D) -> Rect2:
	var bounds_m := mesh_bounds_m(instance)
	var bounds_px := Rect2(viewmodel.project_to_control(bounds_m.get_endpoint(0)), Vector2.ZERO)
	for corner_index in range(1, 8):
		bounds_px = bounds_px.expand(viewmodel.project_to_control(bounds_m.get_endpoint(corner_index)))
	return bounds_px


static func test_small_window_envelope(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.size = Vector2(800, 450)
	feedback.set_hud_mode(true)
	feedback.configure(definition, false, 0.0, true, false)
	var viewmodel := feedback.viewmodel
	var model: Node3D = viewmodel.models[definition.weapon_id]
	var reservation_px := Rect2(feedback.size * 0.5 - Vector2.ONE * feedback.crosshair_clearance_px, Vector2.ONE * feedback.crosshair_clearance_px * 2.0)
	var sleeve: MeshInstance3D = model.get_node("GrippingHand/Sleeve")
	for weight: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		viewmodel.apply_pose(weight, 1.0)
		verify_axis(feedback, verify)
		verify.call(viewmodel.region_px.has_point(feedback.muzzle_position()), "À 800×450, le canon de %s reste visible à chaque amplitude de recul." % definition.title)
		var clear_center: bool = true
		for instance in viewmodel.meshes:
			if model.is_ancestor_of(instance) or viewmodel.flash.is_ancestor_of(instance):
				var visible_bounds_px := projected_bounds_px(viewmodel, instance).intersection(viewmodel.region_px)
				clear_center = clear_center and not visible_bounds_px.intersects(reservation_px)
		verify.call(clear_center, "À 800×450, aucun volume de %s ni son flash ne recouvre la réserve centrale." % definition.title)
		verify.call(projected_bounds_px(viewmodel, sleeve).end.y >= feedback.size.y, "À 800×450, la manche de %s rejoint le bord bas au repos comme au tir." % definition.title)
	feedback.stop()


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
	var viewport_id := feedback.viewmodel.viewport.get_instance_id()
	var camera_id := feedback.viewmodel.camera.get_instance_id()
	var texture_id := feedback.viewmodel.texture.get_instance_id()
	var resting_transform := feedback.viewmodel.weapon_root.transform
	for dimensions in [Vector2(80, 40), Vector2(250, 125), Vector2(333, 167), Vector2(360, 200), Vector2(160, 360), Vector2(1280, 120), Vector2(960, 540), Vector2(3840, 2160)]:
		feedback.size = dimensions
		feedback.play_shot()
		verify.call(feedback.tracer_remaining_s == 0.0 and feedback.clip_contents, "Les aperçus n’envoient aucun tracer hors de leur contrôle.")
		var rectangle := feedback.sprite_rect()
		verify.call(rectangle.position == Vector2.ZERO and rectangle.size.is_equal_approx(dimensions) and feedback.viewmodel.get_rect().is_equal_approx(rectangle), "L’aperçu 3D reste strictement clippé à son contrôle.")
		verify_inspection(feedback, verify)
		verify.call(rectangle.has_point(feedback.muzzle_position()), "Le canon de l’aperçu reste dans son contrôle pendant le recul.")
		verify.call(feedback.viewmodel.weapon_root.transform.is_equal_approx(resting_transform) and feedback.viewmodel.slide.position == Vector3.ZERO and not feedback.viewmodel.flash.visible and not feedback.is_processing(), "Écouter un tir conserve l’arme d’inspection entière et immobile.")
		verify.call(feedback.viewmodel.viewport.size.x <= WeaponViewmodel.MAX_RENDER_SIZE_PX.x and feedback.viewmodel.viewport.size.y <= WeaponViewmodel.MAX_RENDER_SIZE_PX.y, "L’inspection borne la résolution même dans les grandes cartes.")
		feedback.stop()
	verify.call(feedback.viewmodel.viewport.get_instance_id() == viewport_id and feedback.viewmodel.camera.get_instance_id() == camera_id and feedback.viewmodel.texture.get_instance_id() == texture_id, "Redimensionner et écouter réutilise le viewport, la caméra et la texture d’inspection.")
	feedback.set_hud_mode(true)


static func verify_inspection(feedback: WeaponFeedback, verify: Callable) -> void:
	var viewmodel := feedback.viewmodel
	var model: Node3D = viewmodel.models[viewmodel.selected_id]
	verify.call(viewmodel.inspection_mode and not feedback.hud_mode and viewmodel.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Chaque aperçu non-HUD emploie automatiquement une caméra orthographique.")
	verify.call(absf(viewmodel.camera.global_basis.z.normalized().dot(viewmodel.muzzle_axis())) < 0.00001 and viewmodel.camera.global_basis.y.is_equal_approx(Vector3.UP), "L’arme est vue exactement de profil, sans perspective ni inclinaison.")
	var bounds_px := Rect2()
	var bounds_m := AABB()
	var has_bounds: bool = false
	var complete_weapon: bool = true
	var absent_hands: bool = true
	for hand_root in viewmodel.hand_roots:
		absent_hands = absent_hands and hand_root.has_meta("weapon_hand_root") and not hand_root.visible
	for instance in viewmodel.meshes:
		if not model.is_ancestor_of(instance):
			continue
		var belongs_to_hand: bool = false
		var ancestor := instance.get_parent()
		while ancestor != model:
			belongs_to_hand = belongs_to_hand or ancestor.has_meta("weapon_hand_root")
			ancestor = ancestor.get_parent()
		if belongs_to_hand:
			absent_hands = absent_hands and not instance.is_visible_in_tree()
			continue
		complete_weapon = complete_weapon and instance.is_visible_in_tree()
		var projected := projected_bounds_px(viewmodel, instance)
		var mesh_bounds := mesh_bounds_m(instance)
		bounds_px = bounds_px.merge(projected) if has_bounds else projected
		bounds_m = bounds_m.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	verify.call(has_bounds and complete_weapon and absent_hands and viewmodel.hand_roots.size() == 4, "Poignée, canon, culasse et crosse restent présents ; toutes les mains et manches sont masquées par leurs racines marquées.")
	verify.call(bounds_m.is_equal_approx(viewmodel.inspection_bounds_m[viewmodel.selected_id]), "Le cadrage utilise les bounds de tous les meshes de l’arme, sans main, manche ni flash.")
	var padded_region := viewmodel.region_px.grow_individual(-viewmodel.size.x * WeaponViewmodel.INSPECTION_PADDING_FRACTION, -viewmodel.size.y * WeaponViewmodel.INSPECTION_PADDING_FRACTION, -viewmodel.size.x * WeaponViewmodel.INSPECTION_PADDING_FRACTION, -viewmodel.size.y * WeaponViewmodel.INSPECTION_PADDING_FRACTION)
	verify.call(padded_region.grow(0.02).encloses(bounds_px), "L’arme entière conserve dix pour cent de marge dans chaque carte : %s, %s." % [feedback.size, bounds_px])
	verify.call(bounds_px.get_center().distance_to(feedback.size * 0.5) < 0.02 and viewmodel.project_to_control(bounds_m.get_center()).distance_to(feedback.size * 0.5) < 0.02, "Le centre des bounds de l’arme coïncide avec le centre de la carte.")
	var occupied_fraction := maxf(bounds_px.size.x / feedback.size.x, bounds_px.size.y / feedback.size.y)
	verify.call(absf(occupied_fraction - 0.8) < 0.002, "Le profil reste lisible en occupant quatre-vingts pour cent de son axe limitant.")


static func test_inspection_switching(tree: SceneTree, verify: Callable) -> void:
	var feedback: WeaponFeedback = FeedbackScript.new()
	feedback.configure(WeaponCatalog.DEFINITIONS[1], false, 0.0, true, false)
	tree.root.add_child(feedback)
	await tree.process_frame
	verify.call(not feedback.hud_mode and not feedback.viewmodel.rendering_enabled, "Un aperçu non-HUD peut être configuré avant son premier layout sans lancer un viewport vide.")
	feedback.size = Vector2(360, 200)
	await tree.process_frame
	verify_inspection(feedback, verify)
	var viewport_id := feedback.viewmodel.viewport.get_instance_id()
	var node_count := count_nodes(feedback)
	for definition in WeaponCatalog.DEFINITIONS:
		feedback.configure(definition, false, 0.0, true, false)
		verify_inspection(feedback, verify)
		feedback.size = Vector2(1280, 720)
		feedback.set_inspection_mode(false)
		verify.call(feedback.hud_mode and not feedback.viewmodel.inspection_mode and feedback.viewmodel.camera.projection == Camera3D.PROJECTION_FRUSTUM and feedback.viewmodel.camera.transform == Transform3D.IDENTITY, "Quitter l’inspection restaure la caméra HUD après layout.")
		var held_hands: bool = true
		for hand_root in feedback.viewmodel.hand_roots:
			held_hands = held_hands and hand_root.visible
		verify.call(held_hands, "Revenir au HUD restaure chaque vraie main et sa manche.")
		verify_axis(feedback, verify)
		var resting_transform := feedback.viewmodel.weapon_root.transform
		var resting_projection := feedback.viewmodel.camera.get_camera_projection()
		feedback.play_shot()
		feedback.set_inspection_mode(true)
		feedback.size = Vector2(250, 125)
		verify_inspection(feedback, verify)
		verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and not feedback.viewmodel.flash.visible and not feedback.is_processing(), "Passer en inspection pendant le recul efface tous les effets HUD.")
		feedback.size = Vector2(1280, 720)
		feedback.set_hud_mode(true)
		verify.call(feedback.viewmodel.weapon_root.transform.is_equal_approx(resting_transform) and feedback.viewmodel.camera.get_camera_projection() == resting_projection, "Un aller-retour conserve exactement la pose et la projection HUD au repos.")
		feedback.size = Vector2.ZERO
		feedback.set_inspection_mode(true)
		feedback.size = Vector2(360, 200)
		verify_inspection(feedback, verify)
	verify.call(count_nodes(feedback) == node_count and feedback.viewmodel.viewport.get_instance_id() == viewport_id, "Les commutations et layouts tardifs réutilisent tous les nœuds et le même viewport.")
	feedback.queue_free()
	await tree.process_frame


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


static func test_hud_scores(tree: SceneTree, verify: Callable) -> void:
	var hud: TrainingHud = HudScript.new()
	tree.root.add_child(hud)
	hud.size = Vector2(1280, 720)
	hud.configure({"weapon_id": "pulse", "sound_enabled": false})
	await tree.process_frame
	for tracking: bool in [false, true]:
		hud.present_live(10.0, 30.0, 8, 10, tracking, 6.0, 10.0, 2.0)
		var score_text := "Score 600" if tracking else "Score 256"
		var metric_text := "60 %" if tracking else "8 · 80 %"
		verify.call(hud.score_label.text == score_text and hud.metric_label.text == metric_text and hud.timer_label.text == "0:20", "Le HUD conserve les valeurs de référence clic et tracking du score V1.")
		for definition in WeaponCatalog.DEFINITIONS:
			hud.weapon_feedback.configure(definition, false, 0.0, true, false)
			hud.weapon_feedback.play_shot()
			hud.weapon_feedback.set_inspection_mode(true)
			hud.weapon_feedback.play_shot()
			hud.weapon_feedback.set_hud_mode(true)
			hud.weapon_feedback.set_continuous(true)
			hud.weapon_feedback._process(0.037)
			hud.weapon_feedback.stop()
			verify.call(hud.score_label.text == score_text and hud.metric_label.text == metric_text and hud.timer_label.text == "0:20" and hud.progress.value == 10.0, "Changer de profil, inspecter et tirer ne modifie aucun score, mesure ou temps du HUD.")
	hud.queue_free()
	await tree.process_frame


func capture_inspection_weapons() -> void:
	var directory := OS.get_environment("AIM_LOCAL_WEAPON_CAPTURE_DIR")
	if directory.is_empty():
		directory = "/tmp/aimlocal-weapon-inspection"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Le dossier isolé des captures d’inspection est disponible.")
	root.size = Vector2i(1280, 720)
	var background := ColorRect.new()
	background.color = Color("dedbd4")
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var feedback: WeaponFeedback = FeedbackScript.new()
	root.add_child(feedback)
	for dimensions: Vector2i in [Vector2i(250, 125), Vector2i(360, 200), Vector2i(960, 540)]:
		feedback.size = Vector2(dimensions)
		feedback.position = (Vector2(root.size) - feedback.size) * 0.5
		for definition in WeaponCatalog.DEFINITIONS:
			feedback.configure(definition, false, 0.0, true, false)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image().get_region(Rect2i(Vector2i(feedback.position), dimensions))
			var path := directory.path_join("%d-inspection-%s.png" % [dimensions.x, definition.weapon_id])
			check(capture.save_png(path) == OK, "Le profil nu a été capturé : " + path)
	feedback.queue_free()
	background.queue_free()
	await process_frame
	print("WEAPON INSPECTION CAPTURES : 9 rendus isolés dans " + directory)


func capture_weapons() -> void:
	var directory := OS.get_environment("AIM_LOCAL_WEAPON_CAPTURE_DIR")
	if directory.is_empty():
		directory = "/tmp/aimlocal-weapon-visual"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Le dossier isolé des captures est disponible.")
	var background := ColorRect.new()
	background.color = Color("dedbd4")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var feedback: WeaponFeedback = FeedbackScript.new()
	root.add_child(feedback)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback.set_hud_mode(true)
	for dimensions: Vector2i in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await create_timer(0.1).timeout
		for definition in WeaponCatalog.DEFINITIONS:
			feedback.configure(definition, false, 0.0, true, false)
			for phase in ["repos", "tir", "retour"]:
				feedback.stop()
				if phase != "repos":
					feedback.play_shot()
					if phase == "retour":
						feedback._process(0.11)
					feedback.set_process(false)
				await RenderingServer.frame_post_draw
				var capture := root.get_texture().get_image()
				if dimensions.x == 800:
					var center_clear: bool = true
					var center_px: Vector2i = dimensions / 2
					var radius_px := int(feedback.crosshair_clearance_px)
					for vertical_px in range(center_px.y - radius_px, center_px.y + radius_px + 1):
						for horizontal_px in range(center_px.x - radius_px, center_px.x + radius_px + 1):
							var pixel := capture.get_pixel(horizontal_px, vertical_px)
							center_clear = center_clear and absf(pixel.r - background.color.r) < 0.01 and absf(pixel.g - background.color.g) < 0.01 and absf(pixel.b - background.color.b) < 0.01
					check(center_clear, "La capture réelle 800×450 de %s/%s conserve tous les pixels de la réserve du viseur." % [definition.weapon_id, phase])
				var path := directory.path_join("%d-%s-%s.png" % [dimensions.x, definition.weapon_id, phase])
				check(capture.save_png(path) == OK, "Le rendu de l’arme a été capturé : " + path)
	feedback.queue_free()
	background.queue_free()
	await process_frame
	print("WEAPON CAPTURES : 27 rendus isolés dans " + directory)


static func reserve_matches(reference: Image, capture: Image, center_px: Vector2i, radius_px: int) -> bool:
	for vertical_px in range(center_px.y - radius_px, center_px.y + radius_px + 1):
		for horizontal_px in range(center_px.x - radius_px, center_px.x + radius_px + 1):
			var before := reference.get_pixel(horizontal_px, vertical_px)
			var after := capture.get_pixel(horizontal_px, vertical_px)
			if absf(before.r - after.r) > 0.01 or absf(before.g - after.g) > 0.01 or absf(before.b - after.b) > 0.01:
				return false
	return true


func capture_live_weapons() -> void:
	var directory := OS.get_environment("AIM_LOCAL_WEAPON_CAPTURE_DIR")
	if directory.is_empty():
		directory = "/tmp/aimlocal-weapon-live"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Le dossier isolé des captures live est disponible.")
	var main_scene := load("res://scenes/app/Main.tscn") as PackedScene
	var app := main_scene.instantiate()
	var store_script := load("res://scripts/persistence/local_store.gd") as GDScript
	var store: RefCounted = store_script.new()
	app.store = store_script.new("user://tests/weapon-live-" + str(store.call("identifier")))
	var previous_mouse_mode := Input.mouse_mode
	root.add_child(app)
	app.start_practice("C03", 30.0)
	app.begin_training(Time.get_ticks_usec())
	app.set_process(false)
	app.hud.set_process(false)
	var feedback: WeaponFeedback = app.hud.weapon_feedback
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = dimensions
		await create_timer(0.1).timeout
		feedback.configure(WeaponCatalog.DEFINITIONS[0], false, 0.0, false, false)
		await RenderingServer.frame_post_draw
		var reference := root.get_texture().get_image()
		for definition in WeaponCatalog.DEFINITIONS:
			feedback.configure(definition, false, 0.0, true, false)
			for phase in ["repos", "tir", "retour"]:
				feedback.stop()
				if phase != "repos":
					feedback.play_shot()
					if phase == "retour":
						feedback._process(0.11)
					feedback.set_process(false)
				await RenderingServer.frame_post_draw
				var capture := root.get_texture().get_image()
				if dimensions.x == 800:
					check(reserve_matches(reference, capture, dimensions / 2, int(feedback.crosshair_clearance_px)), "Le rendu live 800×450 de %s/%s conserve les pixels centraux de l’arène et du viseur." % [definition.weapon_id, phase])
				var path := directory.path_join("%d-live-%s-%s.png" % [dimensions.x, definition.weapon_id, phase])
				check(capture.save_png(path) == OK, "Le rendu live de l’arme a été capturé : " + path)
	feedback.stop()
	app.queue_free()
	Input.mouse_mode = previous_mouse_mode
	await process_frame
	print("WEAPON LIVE CAPTURES : 18 rendus de l’arène et du HUD dans " + directory)
