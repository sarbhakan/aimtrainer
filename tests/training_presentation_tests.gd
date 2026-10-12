extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var app: Node = MainScene.instantiate()
	app.store = LocalStore.new("user://tests/presentation-" + LocalStore.new().identifier())
	tree.root.add_child(app)
	await tree.process_frame
	app.set_process(false)
	var profile: Dictionary = app.home.read_profile()
	profile.sound_enabled = false
	app.home.bind_profile(profile)
	app.start_practice("C03", 30.0)
	expect(app.screen == app.Screen.COUNTDOWN and app.hud.countdown_label.text == "3", "Chaque départ commence par trois secondes lisibles.")
	expect(not app.session_active and not app.hud.timer_card.visible and not app.hud.metric_card.visible, "La préparation ne comporte ni mesure active ni compteurs superflus.")
	expect(app.target_pool.spheres[0].visible, "Les cibles de départ sont visibles avant la mesure pour repérer la zone.")
	var initial_target: Vector3 = app.preparation_engine.target_direction(0, 0.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	app._input(click)
	expect(app.preparation_engine.shots == 0 and app.engine.shots == 0, "Les tirs de préparation ne produisent aucun score.")
	for preparation_us in [1100000, 2100000]:
		app.clock.accumulated_us = preparation_us
		app.clock.resumed_us = Time.get_ticks_usec()
		app.update_telemetry()
		expect(app.hud.countdown_label.text == ("2" if preparation_us < 2000000 else "1"), "Le décompte affiche 3, puis 2, puis 1 sans afficher zéro.")
	app.clock.accumulated_us = 2900000
	app.clock.resumed_us = Time.get_ticks_usec()
	app._process(0.001)
	expect(app.screen == app.Screen.COUNTDOWN, "La mesure ne démarre pas après l’ancien seuil de deux secondes.")
	app.clock.accumulated_us = 3100000
	app._process(0.001)
	expect(app.screen == app.Screen.TRAINING and app.session_active, "Le moteur démarre à la fin des trois secondes.")
	expect(app.engine.target_direction(0, 0.0).is_equal_approx(initial_target), "La préparation et l’exercice mesuré conservent la même disposition seedée.")
	expect(app.engine.timeline.angular_path_deg == 0.0 and app.engine.timeline.event_count == 0, "La préparation n’entre jamais dans les mesures de souris.")
	expect(not app.hud.preparation.visible and app.hud.title_label.text.is_empty() and app.hud.help_label.text.is_empty(), "L’exercice ne conserve aucun titre ni consigne envahissante.")
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var original_size: Vector2i = tree.root.size
		tree.root.size = dimensions
		app.hud.present_live(10.0, 30.0, 100, 123, false, 0.0, 0.0, 2.0)
		await tree.process_frame
		await tree.process_frame
		expect(app.hud.timer_card.size.y <= 120.0 and app.hud.metric_card.size.y <= 120.0, "Les compteurs restent des cartes compactes, pas des colonnes pleine hauteur.")
		expect(app.hud.metric_label.autowrap_mode == TextServer.AUTOWRAP_OFF and app.hud.go_label.autowrap_mode == TextServer.AUTOWRAP_OFF, "Compteur et GO ne peuvent pas se transformer en texte vertical.")
		expect(app.hud.metric_card.get_global_rect().position.x > float(dimensions.x) * 0.5, "La performance reste dans le coin droit aux trois tailles.")
		tree.root.size = original_size
	app.hud.present_live(10.0, 30.0, 8, 10, false, 0.0, 0.0, 2.0)
	expect(app.hud.timer_label.text == "0:20" and app.hud.metric_label.text == "8 · 80 %", "Temps et touches/précision sont séparés et lisibles.")
	expect(app.hud.score_label.text == "Score 256", "Le score en direct applique la véritable formule clic V1, pas une approximation arbitraire.")
	app.hud.present_live(10.0, 30.0, 0, 0, true, 6.0, 10.0, 2.0)
	expect(app.hud.metric_label.text == "60 %" and app.hud.score_label.text == "Score 600", "Le HUD tracking exprime le vrai temps sur cible et son score V1.")
	app.hud.present_live(0.0, 30.0, 0, 0, false, 0.0, 0.0, 2.0)
	expect(app.hud.metric_label.text == "0 · —" and app.hud.score_label.text == "Score 0", "Une précision inconnue ne devient pas artificiellement 100 %.")
	app.pause_test()
	expect(not app.hud.go_label.visible and not app.hud.is_processing(), "Pause et perte de focus arrêtent aussi l’impulsion GO.")
	app.return_to_menu()
	var presentation: ArenaPresentation = app.arena.get_node("Presentation")
	expect(presentation.environment_meshes.size() <= 32 and not presentation.is_processing(), "Le décor virtuel est statique et son coût en nœuds est borné.")
	for definition in ScenarioCatalog.DEFINITIONS:
		expect(definition.distance_m + definition.distance_m * sin(deg_to_rad(definition.angular_diameter_deg * 0.5)) < 11.0, "Aucune cible ne peut être masquée par le fond virtuel : " + definition.scenario_id)
	app.queue_free()
	await tree.process_frame
	return true
