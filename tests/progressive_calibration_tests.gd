extends SceneTree

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Calibration progressive : délai de test dépassé.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


static func synthetic_report(service: ProgressiveCalibrationService, value: float = 40.0) -> Dictionary:
	var stage := service.current_stage()
	var definition := service.definition_for(stage.scenario_id)
	var tracking: bool = definition.family == "tracking"
	var hits := 0 if tracking else roundi(value)
	var shots := 0 if tracking else maxi(3, hits)
	var accuracy := float(hits) / maxf(shots, 1.0)
	var ratio := value / 100.0 if tracking else 0.0
	var report := {"schema_version": 1, "score_version": ScoringService.version_for(definition), "engine_version": "4.7.2", "renderer": "compatibility",
		"scenario_id": stage.scenario_id, "scenario_revision": definition.revision, "scenario_fingerprint": definition.fingerprint(),
		"family": definition.family, "seed": stage.seed, "duration_s": stage.duration_s, "active_duration_s": stage.duration_s,
		"completed": true, "valid": true, "warmup": false, "calibration_id": service.calibration_id,
		"profile": stage.profile, "aspect": service.aspect, "reference_hits_s": definition.reference_hits_s,
		"metrics": {"shots": shots, "hits": hits, "misses": shots - hits, "targets_expired": 0, "accuracy_fraction": accuracy,
			"accuracy_pct": accuracy * 100.0 if shots > 0 else null, "hits_per_s": float(hits) / stage.duration_s,
			"input_events": 100, "input_buffer_overflows": 0, "angular_path_deg": 20.0,
			"on_target_ratio": ratio, "on_target_time_s": stage.duration_s * ratio, "target_exposed_time_s": stage.duration_s,
			"angular_error_mean_deg": 1.0, "angular_error_p95_deg": 2.0},
		"performance": {"frame_samples": 1000, "frametime_p99_ms": 8.0, "max_frametime_ms": 12.0},
		"comparison_key": ScoringService.comparison_key(definition, stage.duration_s, stage.profile, service.aspect)}
	if report.score_version == ScoringService.EXPIRY_VERSION:
		report.score_policy = "expiry_accuracy_v2"
	report.score = ScoringService.score(report, definition.reference_hits_s)
	return report


func new_service(identifier: String = "progressive-test", distance_cm: float = 35.0, duration_s: float = 60.0, wide: bool = true) -> ProgressiveCalibrationService:
	var service := ProgressiveCalibrationService.new()
	var profile := SensitivityService.default_profile()
	profile.cm_per_360 = distance_cm
	check(service.begin(profile, 16.0 / 9.0, 42, identifier, duration_s, wide), "Le parcours long démarre à paramètres fixes : " + service.error)
	return service


func run_tests() -> void:
	test_directions()
	test_conditions()
	test_protocol_compatibility()
	for duration_s in [45.0, 60.0]:
		for distance_cm in [5.0, 35.123456789, 150.0]:
			for wide in [false, true]:
				for preference in ["stable", "fast", "slow", "interior"]:
					test_full_protocol(distance_cm, duration_s, wide, preference)
	test_storage()
	var flow := load("res://tests/progressive_calibration_flow_tests.gd").new() as RefCounted
	check(await flow.run(self, check), "Le parcours intégré se termine sans erreur de script.")
	print("PROGRESSIVE CALIBRATION : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_directions() -> void:
	for improved in [false, true]:
		var service := new_service()
		var first_cm: float = service.candidate_profile().cm_per_360
		check(service.accept(synthetic_report(service, 40.0)), "Le premier score fixe la référence.")
		var second_cm: float = service.candidate_profile().cm_per_360
		check(second_cm < first_cm, "Le deuxième essai est plus rapide que la référence.")
		check(service.accept(synthetic_report(service, 80.0 if improved else 20.0)), "Le deuxième score guide la recherche.")
		var third_cm: float = service.candidate_profile().cm_per_360
		check(third_cm > second_cm and third_cm < first_cm if improved else third_cm > first_cm,
			"Si le rapide gagne : entre les deux. Sinon : plus lent que le départ, pas seulement que le deuxième.")
	var edge := new_service()
	for value in [20.0, 80.0, 40.0]:
		check(edge.accept(synthetic_report(edge, value)), "Les trois premiers essais actifs sont acceptés.")
	check(edge.candidate_profile().cm_per_360 < float(edge.trials[1].profile.cm_per_360), "Un meilleur score au bord élargit la recherche novice au quatrième essai.")


func test_conditions() -> void:
	var service := new_service()
	for mutation in [{"duration_s": 15.0}, {"warmup": true}, {"completed": false}, {"calibration_id": "other"}, {"seed": 43},
		{"scenario_revision": 4}, {"renderer": "forward_plus"}, {"engine_version": "4.8"},
		{"progressive_trial_index": 1}, {"progressive_block_index": 1}, {"score": -1.0}]:
		var bad := synthetic_report(service)
		bad.merge(mutation, true)
		check(not service.accept(bad) and service.trials.is_empty(), "Rejet atomique d’un essai modifié : " + str(mutation))
	for field in ["input_events", "angular_path_deg"]:
		var bad := synthetic_report(service)
		bad.metrics[field] = 0
		check(not service.accept(bad), "Une mesure sans activité n’oriente pas la sensibilité.")
	var slow := synthetic_report(service)
	slow.performance.frametime_p99_ms = 51.0
	check(not service.accept(slow), "Les saccades invalident l’essai de calibration.")
	var profile := SensitivityService.default_profile()
	for duration_s in [0.0, 15.0, 44.0, NAN, INF]:
		check(not service.begin(profile, 16.0 / 9.0, 42, "bad-duration", duration_s), "Seuls 45 et 60 secondes sont admis.")
	for identifier in ["", "..", "../outside"]:
		check(not service.begin(profile, 16.0 / 9.0, 42, identifier), "Les identifiants de chemin sont refusés.")


func test_protocol_compatibility() -> void:
	check(ProgressiveCalibrationService.PROTOCOL_VERSION == 6 and ScoringService.VERSION == 1 and ScoringService.EXPIRY_VERSION == 2,
		"Le parcours public passe au protocole 6 sans réécrire les scores historiques V1/V2.")
	for protocol in [4, 5, 6]:
		var service := ProgressiveCalibrationService.new()
		check(service.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "protocol-%d" % protocol, 60.0, true, protocol),
			"Les protocoles progressifs 4, 5 et 6 démarrent explicitement.")
		for trial_index in ProgressiveCalibrationService.TOTAL_TRIALS:
			var stage := service.current_stage()
			var definition := service.definition_for(stage.scenario_id)
			var expected := ScenarioCatalog.find(stage.scenario_id) if protocol == 4 else ScenarioCatalog.find_lifecycle(stage.scenario_id) if protocol == 5 else ScenarioCatalog.find_practice(stage.scenario_id)
			var expected_revision: int = 3 if protocol == 4 else 7 if protocol == 6 and expected.family == "tracking" else 6
			check(definition == expected and definition.revision == expected_revision and definition.has_lifecycle() == (protocol >= 5),
				"La version du protocole choisit la difficulté historique ou temporelle de chaque activité.")
			var report := synthetic_report(service)
			check(report.score_version == ScoringService.version_for(expected) and service.accept(report),
				"Chaque version accepte les mesures et le score de sa propre difficulté : " + service.error)
			var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(service.checkpoint(), "\t", true, true))
			var restored := ProgressiveCalibrationService.new()
			check(restored.restore(checkpoint) and restored.protocol_version == protocol and restored.same_value(restored.current_stage(), service.current_stage()),
				"Une reprise JSON conserve le protocole et les difficultés de chacun des vingt-cinq essais : " + restored.error)


func test_full_protocol(distance_cm: float, duration_s: float, wide: bool, preference: String) -> void:
	var service := new_service("full", distance_cm, duration_s, wide)
	var seen: Dictionary = {}
	var previous_width := INF
	for trial_index in 25:
		var stage := service.current_stage()
		check(not stage.is_empty() and stage.block_index == trial_index / 5 and stage.trial_index == trial_index % 5 and stage.duration_s == duration_s,
			"Cinq essais longs pour chaque activité, dans l’ordre prévu.")
		if stage.is_empty():
			return
		var current_cm := float(stage.profile.cm_per_360)
		check(current_cm >= 5.0 and current_cm <= 150.0, "Chaque réglage respecte les bornes physiques.")
		var key := "%d:%.10f" % [int(stage.block_index), current_cm]
		check(not seen.has(key), "Les cinq sensibilités d’une activité sont distinctes.")
		seen[key] = true
		check(stage.seed == 42 + int(stage.block_index) * 7919 and stage.scored, "Même graine par activité, sans micro-échauffement ni confort.")
		var value := 40.0
		if preference == "fast":
			value = 90.0 - 50.0 * current_cm / 150.0
		elif preference == "slow":
			value = 20.0 + 60.0 * current_cm / 150.0
		elif preference == "interior":
			value = maxf(10.0, 90.0 - absf(log(current_cm / 30.0)) * 30.0)
		var report := synthetic_report(service, value)
		check(ScoringService.validate_result(report).is_empty() and service.accept(report), "Le score provient de métriques cohérentes : " + service.error)
		var checkpoint := service.checkpoint()
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(checkpoint, "\t", true, true))
		var restored := ProgressiveCalibrationService.new()
		check(restored.restore(parsed) and service.same_value(restored.current_stage(), service.current_stage()), "Reprise JSON exacte à chaque frontière d’essai : " + restored.error)
		if trial_index % 5 == 4:
			var width := service.upper_log - service.lower_log
			check(width > 0.0 and width < previous_width, "Chaque activité transmet une zone resserrée et exploitable.")
			previous_width = width
		var tampered := checkpoint.duplicate(true)
		tampered.trials.back().progressive_trial_index = 99
		check(not restored.restore(tampered) and restored.same_value(restored.checkpoint(), parsed), "Un historique altéré est refusé sans détruire l’état restauré.")
	check(service.completed() and service.current_stage().is_empty() and service.blocks.size() == 5, "Le parcours s’arrête après exactement 25 mesures.")
	var summary := service.recommendation()
	var observed: bool = false
	for trial in service.blocks.back().trials:
		observed = observed or trial.profile.cm_per_360 == summary.recommended_cm_per_360
	check(observed and summary.apply_allowed and summary.tested_trials == 25, "La sensibilité finale unique est un réglage réellement testé.")
	if preference == "stable":
		check(is_equal_approx(summary.recommended_cm_per_360, distance_cm), "Sans différence de score, conserver la référence plutôt qu’inventer un gain.")
	check(not service.accept(service.trials.back()), "Aucun essai supplémentaire après la fin.")


func test_storage() -> void:
	var store := LocalStore.new("user://tests/progressive-" + LocalStore.new().identifier())
	var service := new_service("first")
	check(store.save_progressive_checkpoint(service.checkpoint()), "Le checkpoint initial est sauvegardé.")
	var path := store.root_path + "/progressive_calibration_checkpoint.json"
	var original := FileAccess.get_file_as_bytes(path)
	var next := new_service("second")
	check(store.save_progressive_checkpoint(next.checkpoint()), "Un nouveau parcours archive le précédent avant remplacement.")
	var initial_checkpoint := next.checkpoint()
	var archived_path := store.root_path + "/archives/progressive-first.json"
	check(FileAccess.get_file_as_bytes(archived_path) == original, "L’archive conserve les octets exacts, sans conversion de score.")
	while not next.completed():
		if not next.accept(synthetic_report(next)):
			check(false, "Le parcours stockable termine : " + next.error)
			return
	check(store.save_progressive_checkpoint(next.checkpoint()) and not store.load_progressive_checkpoint().is_empty(), "Un parcours complet reste reprenable.")
	check(not store.save_progressive_checkpoint(initial_checkpoint) and store.load_progressive_checkpoint().trials.size() == 25, "Un ancien état mémoire ne peut pas effacer des mesures déjà enregistrées.")
	var summary := next.recommendation()
	check(store.save_progressive_recommendation(summary) and store.save_progressive_recommendation(summary), "Le bilan immuable peut être revu sans écrasement.")
	var wrong := summary.duplicate(true)
	wrong.recommended_cm_per_360 += 0.1
	check(not store.save_progressive_recommendation(wrong), "Une recommandation différente des essais est refusée.")
	var contents := FileAccess.get_file_as_bytes(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(not store.save_progressive_checkpoint(service.checkpoint()) and FileAccess.get_file_as_string(path) == "{broken", "Un checkpoint illisible est préservé, jamais écrasé.")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(contents)
	file.close()
	var lock_path := ProjectSettings.globalize_path(store.root_path + "/archives/progressive-second.json.lock")
	check(DirAccess.make_dir_absolute(lock_path) == OK, "La simulation de verrou est créée dans le dossier de test.")
	check(not store.save_progressive_checkpoint(service.checkpoint()) and FileAccess.get_file_as_bytes(path) == contents, "Un verrou d’archive bloque le remplacement sans perdre le parcours.")
	DirAccess.remove_absolute(lock_path)
