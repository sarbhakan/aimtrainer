extends SceneTree

var failures: int = 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	smoke.call_deferred()


func smoke() -> void:
	var scene := load("res://scenes/app/Main.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var app := scene.instantiate()
	app.store = LocalStore.new("user://tests/export-" + LocalStore.new().identifier())
	root.add_child(app)
	await process_frame
	for test_path in ["run_tests", "domain_tests", "ui_tests", "sensitivity_import_tests", "geometry_regression_tests", "browser_preview_tests", "weapon_animation_tests", "calibration_block_tests", "checkpoint_migration_tests", "ui_polish_tests", "ux_flow_tests", "crosshair_feedback_tests", "gameplay_quality_tests", "adaptive_calibration_tests", "guided_flow_tests", "record_flow_tests", "revision_archive_tests", "training_presentation_tests", "ui_spacing_tests", "preview_containment_tests", "pause_seed_tests", "pattern_variation_tests", "storage_roundtrip_tests"]:
		if ResourceLoader.exists("res://tests/" + test_path + ".gd"):
			push_error("Ressource de test présente dans le pack : " + test_path)
			failures += 1
	for game_id in ["cs2", "valorant", "cod"]:
		var profile: Dictionary = app.home.read_profile()
		profile.dpi = 1600.0
		var source_value: float = 0.35 if game_id == "valorant" else 5.0 if game_id == "cod" else 1.5
		var imported := GameProfileService.import_profile(profile, game_id, 800.0, source_value, "Modern Warfare III (2023)", 34.123456)
		if not imported.error.is_empty():
			push_error("Import exporté refusé : " + game_id + " · " + imported.error)
			failures += 1
			continue
		app.import_reference_profile(imported.profile)
		app.home.destination_dpi.value = 800.0
		if app.home.read_profile().dpi != 1600.0 or not is_equal_approx(app.aim_camera.degrees_per_count, SensitivityService.degrees_per_count(1600.0, imported.profile.cm_per_360)) or not is_equal_approx(app.home.conversion_value, source_value):
			push_error("Import/conversion exporté incohérent : " + game_id)
			failures += 1
	var calibration := CalibrationService.new()
	if not calibration.begin(app.home.read_profile(), 16.0 / 9.0, 42, "export-protocol") or CalibrationService.PROTOCOL_VERSION != 3 or calibration.plan.size() != 60:
		push_error("Protocole exporté incohérent : " + calibration.error)
		failures += 1
	var search := AdaptiveSensitivityService.new()
	if not search.begin(app.home.read_profile(), 16.0 / 9.0, 42, "export-guided") or search.current_spec().speed_factors != [0.5, 1.0, 2.0]:
		push_error("Recherche exportée incohérente : " + search.error)
		failures += 1
	for style in CrosshairProfile.STYLES:
		var profile: Dictionary = app.home.read_profile()
		profile.crosshair_style = style
		app.hud.configure(profile)
		if app.hud.crosshair_profile.crosshair_style != style:
			push_error("Viseur exporté incohérent : " + style)
			failures += 1
	for definition in WeaponCatalog.DEFINITIONS:
		if not definition.validate().is_empty() or definition.sprite.get_width() <= 0 or definition.shot_sound.data.is_empty() or definition.continuous_sound.data.is_empty():
			push_error("Ressources d’arme exportées invalides : " + definition.weapon_id)
			failures += 1
		var profile: Dictionary = app.home.read_profile()
		profile.weapon_id = definition.weapon_id
		app.hud.configure(profile)
		if app.hud.weapon_feedback.continuous_player.stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			push_error("Boucle d’arme exportée invalide : " + definition.weapon_id)
			failures += 1
		var model: WeaponViewmodel = app.hud.weapon_feedback.viewmodel
		if model == null or model.meshes.is_empty() or model.selected_id != definition.weapon_id or not model.viewport.own_world_3d:
			push_error("Viewmodel exporté invalide : " + definition.weapon_id)
			failures += 1
	for definition in ScenarioCatalog.DEFINITIONS:
		if definition.revision != (4 if definition.scenario_id in ["D01", "D02", "S02"] else 3) or not definition.validate().is_empty():
			push_error("Définition exportée invalide : " + definition.scenario_id)
			failures += 1
		app.start_practice(definition.scenario_id, 1.0)
		app.begin_training(Time.get_ticks_usec())
		app.engine.record_aim(0.01, 1, 0)
		app.engine.record_frame(0.01)
		if definition.family != "tracking":
			app.engine.shoot(0.1, app.engine.target_direction(0, 0.1))
		app.clock.accumulated_us = 1000000
		app.finish_training(true)
		if not app.last_report.completed or not app.last_report.valid or app.last_report.scenario_id != definition.scenario_id:
			push_error("Exercice exporté invalide : " + definition.scenario_id + " · " + app.last_report.invalid_reason)
			failures += 1
		app.return_to_menu()
	if app.store.sessions().size() != 16:
		push_error("Nombre de séances exportées : %d au lieu de 16. %s" % [app.store.sessions().size(), app.store.last_error])
		failures += 1
	app.queue_free()
	await process_frame
	print("EXPORT SMOKE : 16 exercices embarqués, %d échecs." % failures)
	print("EXPORT ASSETS : 3 profils d’arme embarqués, %d échecs." % failures)
	print("EXPORT PROFILES : 3 imports, protocole 3 et recherche guidée embarqués, %d échecs." % failures)
	print("EXPORT CROSSHAIRS : 4 styles embarqués, %d échecs." % failures)
	quit(0 if failures == 0 else 1)
