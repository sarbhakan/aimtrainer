extends SceneTree

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("Les cycles de vie n’ont pas terminé leur validation.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func engine_for(scenario_id: String, seed_value: int = 42) -> ScenarioEngine:
	var engine := ScenarioEngine.new()
	check(engine.start(ScenarioCatalog.find_practice(scenario_id), seed_value, 30.0), "L’exercice temporel démarre : " + scenario_id + " " + engine.invalid_reason)
	return engine


func run_tests() -> void:
	test_definitions()
	test_expiration_order()
	test_shrinking_hitbox()
	test_scoring_and_storage()
	test_tracking_replays()
	test_tracking_renewal()
	test_partial_boundary()
	test_old_protocol()
	print("LIFECYCLE : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_definitions() -> void:
	check(ScenarioCatalog.practice_definitions().size() == 18, "Les dix-huit exercices publics disposent de cycles de vie explicites.")
	for definition in ScenarioCatalog.practice_definitions():
		check(definition.revision == 6 and definition.has_lifecycle() and definition.validate().is_empty(), "Variante r6 valide : " + definition.scenario_id + " " + definition.validate())
		check(definition.fits_view(75.0, 16.0 / 9.0) and definition.lifecycle_shrink_ratio > 0.0, "Le cadrage initial et la taille finale sont visables.")
		var base := ScenarioCatalog.find(definition.scenario_id)
		check(base.revision < 6 and base.fingerprint() != definition.fingerprint(), "La difficulté historique et ses records ne sont pas réécrits.")
		for mutation in [{"lifecycle_shrink_ratio": 0.0}, {"lifecycle_shrink_ratio": 1.0}, {"lifecycle_shrink_ratio": NAN}, {"lifetime_min_s": 0.01}, {"lifetime_max_s": INF}]:
			var bad := definition.duplicate() as ScenarioDefinition
			for field in mutation:
				bad.set(field, mutation[field])
			check(not bad.validate().is_empty(), "Une disparition incompatible ou non finie est refusée.")


func test_expiration_order() -> void:
	for scenario_id in ["C03", "C05", "S01", "S02", "M01", "D01"]:
		for seed_value in [1, 42, 7919]:
			var direct := engine_for(scenario_id, seed_value)
			var stepped := engine_for(scenario_id, seed_value)
			var deadlines: Dictionary = {}
			for target in direct.targets:
				deadlines[target.expires_s] = true
			check(deadlines.size() == direct.targets.size(), "Les cibles simultanées n’expirent pas toutes en bloc.")
			direct.advance_to(30.0)
			for frame_index in 7200:
				stepped.advance_to(float(frame_index + 1) / 240.0)
			check(direct.targets == stepped.targets and direct.rng.state == stepped.rng.state and direct.expired == stepped.expired, "Chronologie et RNG identiques après saut ou petits pas : " + scenario_id)
			check(direct.expired > 0 and direct.shots == 0 and direct.hits == 0, "Une cible oubliée expire sans fabriquer un tir ni une touche.")
			var report := direct.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			check(ScoringService.validate_result(report).is_empty() and report.metrics.failed_actions == direct.expired and report.score == 0, "Les expirations apparaissent comme échecs avec un score nul sans touche.")


func test_shrinking_hitbox() -> void:
	for scenario_id in ["C03", "C02", "C05", "M01", "T01", "T09", "T10"]:
		var engine := engine_for(scenario_id)
		var target: Dictionary = engine.targets[0]
		var early := engine.target_geometry(0, 0.0)
		var time_s := float(target.expires_s) * 0.99
		var late := engine.target_geometry(0, time_s)
		var base_diameter := engine.base_target_angular_diameter_deg(0, time_s)
		check(float(late.angular_diameter_deg) <= base_diameter and float(late.angular_diameter_deg) >= base_diameter * engine.definition.lifecycle_shrink_ratio, "Le rétrécissement respecte un plancher positif : " + scenario_id)
		check(is_equal_approx(float(late.radius_m), float(late.distance_m) * sin(deg_to_rad(float(late.angular_diameter_deg)) * 0.5)), "Le rayon mesuré est exactement le rayon de la silhouette.")
		var center: Vector3 = late.direction
		var perpendicular := center.cross(Vector3.UP).normalized()
		var half_angle_rad := deg_to_rad(float(late.angular_diameter_deg) * 0.5)
		var inside := (center * cos(half_angle_rad * 0.99) + perpendicular * sin(half_angle_rad * 0.99)).normalized()
		var outside := (center * cos(half_angle_rad * 1.01) + perpendicular * sin(half_angle_rad * 1.01)).normalized()
		check(not is_inf(AimGeometry.ray_sphere_distance(inside, late.center_offset_m, late.radius_m)) and is_inf(AimGeometry.ray_sphere_distance(outside, late.center_offset_m, late.radius_m)), "Le bord visible et la collision rétrécissent ensemble.")
		if engine.definition.motion == "static":
			check(late.angular_diameter_deg < early.angular_diameter_deg, "La taille diminue vraiment avec l’âge.")
	var clicking := engine_for("C02")
	var old_direction := clicking.target_direction(0, clicking.targets[0].expires_s)
	var deadline_s: float = clicking.targets[0].expires_s
	check(not clicking.shoot(deadline_s, old_direction) and clicking.expired == 1 and clicking.hits == 0, "Un clic à l’échéance ne touche pas l’ancienne cible ni n’efface son expiration.")
	var identity: int = clicking.targets[0].id
	clicking.paused = true
	clicking.advance_to(20.0)
	check(clicking.targets[0].id == identity and clicking.expired == 1, "La pause ne fait pas vieillir ni remplacer les cibles.")


func test_scoring_and_storage() -> void:
	var engine := engine_for("C03")
	engine.record_aim(0.01, 1.0, 0.0)
	engine.record_aim(0.02, 2.0, 1.0)
	for shot_index in 3:
		var time_s := 0.1 + shot_index * 0.1
		check(engine.shoot(time_s, engine.target_direction(0, time_s)), "Les touches avant disparition sont réellement attribuées.")
	engine.advance_to(1.0)
	var before := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, false)
	engine.advance_to(30.0)
	var after := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
	check(ScoringService.effective_accuracy(after.metrics) < ScoringService.effective_accuracy(before.metrics) and after.metrics.accuracy_pct == 100.0, "La réussite baisse avec les oublis, sans falsifier la précision des trois tirs.")
	check(after.metrics.failed_actions == after.metrics.misses + after.metrics.targets_expired and after.score < ScoringService.score({"family": "click", "metrics": after.metrics}, engine.definition.reference_hits_s), "Les expirations pénalisent le score V2, pas les anciens scores V1.")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(after, "\t", true, true))
	check(ScoringService.validate_result(parsed).is_empty(), "Les rapports V2 restent cohérents après JSON.")
	for mutation in [{"targets_expired": -1}, {"targets_expired": 2.5}, {"targets_expired": "bad"}, {"effective_accuracy_pct": 100.0}, {"failed_actions": 0}]:
		var bad := parsed.duplicate(true)
		bad.metrics.merge(mutation, true)
		check(not ScoringService.validate_result(bad).is_empty(), "Un compteur ou taux falsifié est rejeté : " + str(mutation))
	var store := LocalStore.new("user://tests/lifecycle-" + LocalStore.new().identifier())
	check(store.save_session(after) and store.sessions().size() == 1, "Une séance V2 complète reste lisible dans le stockage local.")
	var summary := ProgressService.summarize(store.sessions(), after.comparison_key)
	check(summary.count == 1 and summary.filter.score_version == 2, "La progression conserve la version du score temporel.")
	var directory := store.export_sessions()
	check(not directory.is_empty(), "Les mesures V2 sont exportables.")
	var export_directory := DirAccess.open(directory)
	for filename in export_directory.get_files():
		if filename.ends_with(".csv"):
			var file := FileAccess.open(directory.path_join(filename), FileAccess.READ)
			var header := file.get_csv_line()
			var row := file.get_csv_line()
			check(header.size() == row.size() and row[header.find("warmup")] == "false" and float(row[header.find("dpi")]) == 800.0, "Les anciennes colonnes CSV gardent leur ordre et leurs unités.")
			check(int(row[header.find("targets_expired")]) == engine.expired and int(row[header.find("failed_actions")]) == engine.expired, "Les expirations et échecs sont exportés, pas seulement la précision des tirs.")
	var old := ScenarioEngine.new()
	old.start(ScenarioCatalog.find("C03"), 42, 30.0)
	check(ScoringService.comparison_key(old.definition, 30.0, SensitivityService.default_profile(), 16.0 / 9.0) != after.comparison_key, "Ancienne difficulté et nouveau score ne mélangent pas leurs records.")


func replay(scenario_id: String, fps: int) -> ScenarioEngine:
	var engine := engine_for(scenario_id)
	for pose_index in 7201:
		var time_s := float(pose_index) / 240.0
		engine.record_aim(time_s, sin(time_s * 1.7) * 10.0, cos(time_s * 0.9) * 7.0)
	for frame_index in fps * 30:
		engine.advance_to(float(frame_index + 1) / fps)
	return engine


func test_tracking_replays() -> void:
	for scenario_id in ["T01", "T02", "T03", "T04", "T05", "T09", "T10"]:
		var reference := replay(scenario_id, 240)
		for fps in [60, 144]:
			var candidate := replay(scenario_id, fps)
			check(candidate.expired == reference.expired and candidate.targets == reference.targets and candidate.rng.state == reference.rng.state, "Cycles de suivi identiques avec le même replay, à %d FPS : %s" % [fps, scenario_id])
			check(absf(candidate.on_target_s - reference.on_target_s) < 0.000000001 and absf(candidate.angular_error_sum_deg_s - reference.angular_error_sum_deg_s) < 0.000000001, "Temps et erreur intégrés ne dépendent pas des frames.")
		check(reference.expired >= 2 and absf(reference.integrated_s - 30.0) < 0.000000001, "L’exposition inclut les cycles sans trous artificiels.")


func test_tracking_renewal() -> void:
	for scenario_id in ["T01", "T02", "T03", "T04", "T05", "T09", "T10"]:
		for seed_value in range(1, 65):
			var engine := engine_for(scenario_id, seed_value)
			var deadline_s: float = engine.targets[0].expires_s
			var before := engine.target_direction(0, deadline_s)
			var old_identity: int = engine.targets[0].id
			engine.advance_to(deadline_s + ScenarioEngine.SAMPLE_STEP_S)
			var born_s: float = engine.targets[0].born_s
			var after := engine.target_direction(0, born_s)
			check(engine.targets[0].id > old_identity and AimGeometry.angular_error_deg(before, after) > 0.1, "Le cycle terminé est remplacé ailleurs, pas réutilisé à taille nulle.")
			var geometry := engine.target_geometry(0, born_s)
			check(is_equal_approx(float(geometry.angular_diameter_deg), engine.base_target_angular_diameter_deg(0, born_s)), "La nouvelle cible repart à sa taille initiale.")


func test_partial_boundary() -> void:
	var definition := ScenarioCatalog.find_practice("T10").duplicate() as ScenarioDefinition
	definition.lifetime_s = 0.503
	definition.lifetime_min_s = 0.503
	definition.lifetime_max_s = 0.503
	var engine := ScenarioEngine.new()
	check(engine.start(definition, 42, 1.009), "La fixture place une expiration entre deux ticks et une durée partielle finale.")
	engine.record_aim(0.0, 0.0, 0.0)
	engine.record_aim(0.001, 1.0, 0.0)
	engine.advance_to(1.009)
	var report := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
	check(engine.expired == 2 and absf(engine.integrated_s - 1.009) < 0.000000001 and ScoringService.validate_result(report).is_empty(), "Le dernier fragment et les deux échéances sont intégrés sans perte ni double comptage.")


func test_old_protocol() -> void:
	var legacy := ProgressiveCalibrationService.new()
	check(legacy.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "legacy-four", 60.0, true, 4), "Un ancien protocole 4 se reconstruit sans changer sa difficulté.")
	var current := ProgressiveCalibrationService.new()
	check(current.restore(JSON.parse_string(JSON.stringify(legacy.checkpoint(), "\t", true, true))) and current.protocol_version == 4 and not current.definition_for("C02").has_lifecycle(), "La reprise 0.7 conserve les conditions et les scores anciens.")
	var modern := ProgressiveCalibrationService.new()
	check(modern.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "modern-five") and modern.protocol_version == 5 and modern.definition_for("C02").has_lifecycle(), "Une nouvelle calibration utilise le protocole 5 temporel.")
	check(current.checkpoint().scenario_fingerprints != modern.checkpoint().scenario_fingerprints, "Les deux protocoles ne prétendent pas mesurer la même difficulté.")
