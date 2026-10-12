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
	if DirAccess.dir_exists_absolute("res://tests"):
		push_error("Le dossier de tests doit être absent du pack produit.")
		failures += 1
	for test_path in ["run_tests", "domain_tests", "ui_tests", "sensitivity_import_tests", "geometry_regression_tests", "browser_preview_tests", "weapon_animation_tests", "calibration_block_tests", "checkpoint_migration_tests", "ui_polish_tests", "ux_flow_tests", "crosshair_feedback_tests", "gameplay_quality_tests", "adaptive_calibration_tests", "guided_flow_tests", "record_flow_tests", "revision_archive_tests", "training_presentation_tests", "ui_spacing_tests", "preview_containment_tests", "pause_seed_tests", "pattern_variation_tests", "storage_roundtrip_tests", "exercise_070_tests", "presentation_070_tests", "progressive_ui_tests", "progressive_calibration_tests", "progressive_calibration_flow_tests", "progressive_visual_fixtures", "export_smoke", "benchmark", "visual_smoke"]:
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
	smoke_progressive_calibration(app.home.read_profile())
	var routine := TrainingRoutineService.new()
	for duration_s in [45.0, 60.0]:
		if not routine.begin(duration_s) or routine.plan.size() != 3:
			push_error("Routine exportée incohérente.")
			failures += 1
			continue
		for phase_index in 3:
			var phase: Dictionary = routine.current_stage(phase_index)
			if phase.scenario_id != ["M01", "T10", "S02"][phase_index] or phase.duration_s != duration_s or phase.index != phase_index or phase.total != 3 or phase.title != ScenarioCatalog.find(phase.scenario_id).title:
				push_error("Phase de routine exportée incohérente : " + str(phase_index))
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
	if ScenarioCatalog.DEFINITIONS.size() != 18:
		push_error("Le catalogue exporté doit contenir 18 exercices.")
		failures += 1
	for definition in ScenarioCatalog.DEFINITIONS:
		var expected_revision: int = 5 if definition.scenario_id in ["C03", "M01", "T10"] else 4 if definition.scenario_id in ["D01", "D02", "S02"] else 3
		if definition.revision != expected_revision or not definition.validate().is_empty():
			push_error("Définition exportée invalide : " + definition.scenario_id)
			failures += 1
		app.start_practice(definition.scenario_id, 1.0)
		app.begin_training(Time.get_ticks_usec())
		if not app.session_active or app.engine.definition == null or app.engine.definition.scenario_id != definition.scenario_id:
			push_error("Exercice exporté non démarré : " + definition.scenario_id)
			failures += 1
			app.return_to_menu()
			continue
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
	var sessions: Array[Dictionary] = app.store.sessions()
	var session_ids: Dictionary = {}
	for report in sessions:
		if session_ids.has(report.scenario_id) or not report.completed or not report.valid or not ScoringService.validate_result(report).is_empty():
			push_error("Séance exportée sauvegardée incohérente : " + str(report.scenario_id))
			failures += 1
		session_ids[report.scenario_id] = true
	if sessions.size() != 18 or session_ids.size() != 18:
		push_error("Nombre de séances exportées : %d au lieu de 18. %s" % [sessions.size(), app.store.last_error])
		failures += 1
	app.queue_free()
	await process_frame
	print("EXPORT SMOKE : 18 exercices embarqués, %d échecs." % failures)
	print("EXPORT ASSETS : 3 profils d’arme embarqués, %d échecs." % failures)
	print("EXPORT PROFILES : 3 imports, protocole 4, 25 essais de 60 s et routine 3 phases embarqués, %d échecs." % failures)
	print("EXPORT CROSSHAIRS : 4 styles embarqués, %d échecs." % failures)
	quit(0 if failures == 0 else 1)


func smoke_progressive_calibration(profile: Dictionary) -> void:
	var progressive := ProgressiveCalibrationService.new()
	if not progressive.begin(profile, 16.0 / 9.0, 42, "export-progressive") or ProgressiveCalibrationService.PROTOCOL_VERSION != 4 or ProgressiveCalibrationService.TOTAL_TRIALS != 25 or ProgressiveCalibrationService.TRIALS_PER_BLOCK != 5 or progressive.duration_s != 60.0:
		push_error("Calibration progressive exportée incohérente : " + progressive.error)
		failures += 1
		return
	for trial_index in 25:
		var stage: Dictionary = progressive.current_stage()
		if stage.is_empty() or stage.scenario_id != ["C02", "C04", "S01", "T01", "T05"][trial_index / 5] or stage.duration_s != 60.0 or stage.total_trials != 25 or stage.completed_trials != trial_index or stage.block_index != trial_index / 5 or stage.trial_index != trial_index % 5 or not stage.scored:
			push_error("Ordre des essais progressifs exportés incohérent : " + str(trial_index))
			failures += 1
			break
		var definition: ScenarioDefinition = ScenarioCatalog.find(stage.scenario_id)
		var engine := ScenarioEngine.new()
		if not engine.start(definition, int(stage.seed), float(stage.duration_s)):
			push_error("Essai progressif exporté non démarré : " + engine.invalid_reason)
			failures += 1
			break
		for sample_index in range(1, 3601):
			var time_s: float = sample_index / 60.0
			var direction: Vector3 = engine.target_direction(0, time_s)
			engine.record_aim(time_s, rad_to_deg(atan2(-direction.x, -direction.z)), rad_to_deg(asin(direction.y)))
			engine.record_frame(1.0 / 60.0)
			if definition.family != "tracking" and sample_index % 30 == 0 and time_s < 60.0:
				if not engine.shoot(time_s, direction):
					push_error("Impact progressif exporté refusé : " + definition.scenario_id)
					failures += 1
			engine.advance_to(time_s)
		var report: Dictionary = engine.result(stage.profile, progressive.aspect, true)
		report.warmup = false
		report.calibration_id = progressive.calibration_id
		if not progressive.accept(report):
			push_error("Essai progressif exporté refusé : " + progressive.error)
			failures += 1
			break
	if not progressive.completed() or progressive.trials.size() != 25 or progressive.blocks.size() != 5 or not progressive.current_stage().is_empty() or progressive.checkpoint().protocol_version != 4:
		push_error("Les 25 essais progressifs exportés n'ont pas terminé leurs cinq blocs.")
		failures += 1
