extends SceneTree

const AdaptiveService := preload("res://scripts/sensitivity/adaptive_sensitivity_service.gd")

var assertion_count: int = 0
var failure_count: int = 0
var test_root: String = ""


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Les tests de calibration adaptative n’ont pas terminé en 90 secondes.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_tests() -> void:
	test_root = "user://tests/adaptive-calibration-%d" % Time.get_ticks_usec()
	check(DirAccess.make_dir_recursive_absolute(test_root) == OK, "Les données de test doivent rester sous user://tests/.")
	test_comparison_protocol()
	test_comparison_restore()
	test_physical_bounds()
	test_full_comparison_required()
	test_stable_search()
	test_refine_edge_recenter()
	test_bounded_search()
	test_uncertainty_and_comfort()
	test_search_restore()
	await test_guided_application()
	print("ADAPTIVE CALIBRATION : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func trial_report(calibration: CalibrationService, values: Array) -> Dictionary:
	var stage := calibration.current_stage()
	var definition := ScenarioCatalog.find(str(stage.scenario_id))
	var profile := calibration.candidate_profile(int(stage.candidate_index))
	var value: float = float(values[int(stage.candidate_index)])
	var duration_s: float = float(stage.duration_s)
	var hit_count: int = 0 if definition.family == "tracking" else int(round(value))
	var metrics: Dictionary = {"shots": hit_count, "hits": hit_count, "input_events": 100,
		"input_buffer_overflows": 0, "angular_path_deg": 10.0,
		"accuracy_fraction": 1.0 if hit_count > 0 else 0.0, "hits_per_s": float(hit_count) / duration_s,
		"on_target_ratio": value / 100.0 if definition.family == "tracking" else 0.0,
		"on_target_time_s": duration_s * value / 100.0 if definition.family == "tracking" else 0.0,
		"target_exposed_time_s": duration_s, "angular_error_mean_deg": 1.0, "angular_error_p95_deg": 2.0}
	var report: Dictionary = {"schema_version": 1, "score_version": ScoringService.VERSION,
		"engine_version": "4.7.2", "scenario_id": definition.scenario_id,
		"scenario_revision": definition.revision, "scenario_fingerprint": definition.fingerprint(),
		"family": definition.family, "seed": stage.seed, "duration_s": duration_s,
		"active_duration_s": duration_s, "completed": true, "valid": true,
		"profile": profile, "aspect": calibration.aspect, "metrics": metrics,
		"performance": {"frame_samples": 1000, "frametime_p99_ms": 8.0, "max_frametime_ms": 12.0},
		"comparison_key": ScoringService.comparison_key(definition, duration_s, profile, calibration.aspect)}
	report.score = ScoringService.score(report, definition.reference_hits_s)
	return report


func comparison_from_spec(spec: Dictionary, values: Array = [30, 70, 40], discomfort_scenario: String = "", no_signal: bool = false, noisy: bool = false) -> CalibrationService:
	var calibration := CalibrationService.new()
	check(calibration.begin(spec.profile, float(spec.aspect), int(spec.seed), str(spec.calibration_id), spec.speed_factors), "Les conditions du contrôleur doivent lancer un comparateur standard : " + calibration.error)
	while not calibration.current_stage().is_empty():
		var stage := calibration.current_stage()
		var stage_values: Array = values.duplicate() if stage.scored else [90, 10, 90]
		if noisy and stage.scored:
			var factor: float = [0.2, 1.0, 1.8][int(stage.repetition)]
			for candidate_index in stage_values.size():
				stage_values[candidate_index] = round(float(stage_values[candidate_index]) * factor)
		if no_signal and stage.scenario_id == "T05":
			stage_values = [0, 0, 0]
		var comfort: int = 2 if stage.scenario_id == discomfort_scenario and int(stage.candidate_index) == 1 else 4
		if not calibration.accept(trial_report(calibration, stage_values), comfort):
			check(false, "Les passages synthétiques conformes doivent être acceptés : " + calibration.error)
			break
	return calibration


func new_search(profile: Dictionary = SensitivityService.default_profile(), identifier: String = "adaptive-test") -> AdaptiveService:
	var search := AdaptiveService.new()
	check(search.begin(profile, 16.0 / 9.0, 42, identifier), "La recherche doit démarrer avec des conditions valides : " + search.error)
	return search


func test_comparison_protocol() -> void:
	var calibration := CalibrationService.new()
	var profile := SensitivityService.default_profile()
	check(calibration.begin(profile, 16.0 / 9.0, 42, "quick"), "L’API rapide à quatre arguments doit rester disponible.")
	check(calibration.speed_factors == [0.9, 1.0, 1.1] and CalibrationService.FACTORS == [0.9, 1.0, 1.1], "Les facteurs rapides historiques doivent rester inchangés.")
	check(CalibrationService.PROTOCOL_VERSION == 3 and ScoringService.VERSION == 1, "Le protocole évolue sans changer le score.")
	check(calibration.begin(profile, 16.0 / 9.0, 42, "wide", [2.0, 0.5, 1.0]), "Trois facteurs fournis dans le désordre doivent être triés par vitesse.")
	check(calibration.speed_factors == [0.5, 1.0, 2.0], "A/B/C doivent correspondre à lent/centre/rapide.")
	check(calibration.candidate_profile(0).cm_per_360 == 70.0 and calibration.candidate_profile(1).cm_per_360 == 35.0 and calibration.candidate_profile(2).cm_per_360 == 17.5, "Les distances doivent utiliser les facteurs configurés sans modifier la référence centrale.")
	var scored_count: int = 0
	var familiarization_count: int = 0
	var exercise_duration_s: float = 0.0
	for scenario_index in 5:
		var positions: Array[Array] = [[], [], []]
		for passage_index in 12:
			var stage: Dictionary = calibration.plan[scenario_index * 12 + passage_index]
			check(stage.scenario_id == CalibrationService.SCENARIOS[scenario_index] and stage.scored == (passage_index >= 3), "Chaque bloc doit conserver un exercice avec trois familiarisations puis neuf mesures.")
			exercise_duration_s += float(stage.duration_s)
			if stage.scored:
				scored_count += 1
				positions[(passage_index - 3) % 3].append(stage.candidate_index)
			else:
				familiarization_count += 1
		for position in positions:
			position.sort()
			check(position == [0, 1, 2], "Chaque candidat doit occuper chaque position une fois par exercice.")
	check(calibration.plan.size() == 60 and scored_count == 45 and familiarization_count == 15, "Toute plage conserve exactement 60 passages, dont 45 notés.")
	check(exercise_duration_s + 60.0 * (2.0 + 3.0) == 960.0, "Avec décompte de 2 s et repos de 3 s, une comparaison reste à 16 minutes minimum.")
	var before := calibration.checkpoint()
	for factors in [[0.5, 1.0], [0.0, 1.0, 2.0], [NAN, 1.0, 2.0], [0.5, 1.0, INF], [0.5, 1.0, 1.0], [0.5, 0.8, 2.0], ["0.5", 1.0, 2.0]]:
		check(not calibration.begin(profile, 16.0 / 9.0, 42, "invalid", factors), "Des facteurs invalides doivent être refusés.")
		check(AdaptiveService.same_value(before, calibration.checkpoint()), "Un begin invalide doit protéger la comparaison existante.")
	var detached := calibration.checkpoint()
	detached.baseline.cm_per_360 = 99.0
	detached.speed_factors[0] = 0.1
	check(calibration.baseline.cm_per_360 == 35.0 and calibration.speed_factors[0] == 0.5, "Le checkpoint ne doit pas exposer les données internes par référence.")
	check(calibration.candidate_profile(-1).is_empty() and calibration.candidate_profile(3).is_empty(), "Un index de candidat invalide doit être sûr.")
	var first_stage := calibration.current_stage()
	check(calibration.accept(trial_report(calibration, [30, 70, 40]), 4), "Le premier passage réel du protocole doit être accepté.")
	check(first_stage.candidate_index == 0 and calibration.current_stage().candidate_index == 1, "Un candidat ne change qu’après validation d’un passage terminé.")
	var failed_stage := calibration.current_stage()
	var wrong := trial_report(calibration, [30, 70, 40])
	wrong.profile.cm_per_360 = 17.5
	check(not calibration.accept(wrong, 4) and calibration.current_stage() == failed_stage, "Un changement de candidat pendant un passage doit être refusé sans progression.")


func test_comparison_restore() -> void:
	var search := new_search()
	var completed := comparison_from_spec(search.current_spec())
	var restored := CalibrationService.new()
	var checkpoint := disk_roundtrip(completed.checkpoint(), "comparison-v3")
	check(restored.restore(checkpoint), "Le protocole 3 doit survivre à une sauvegarde JSON complète.")
	check(restored.plan == completed.plan and AdaptiveService.same_value(restored.recommendation(), completed.recommendation()), "La restauration doit reproduire le plan et le bilan avec les vrais facteurs.")
	var quick := CalibrationService.new()
	check(quick.begin(SensitivityService.default_profile(), 16.0 / 9.0, 77, "legacy-two"), "Le protocole rapide doit permettre une migration à facteurs historiques.")
	for trial_index in 17:
		check(quick.accept(trial_report(quick, [30, 70, 40]), 4), "Les passages historiques de protocole 2 doivent être rejouables.")
	var legacy := quick.checkpoint()
	legacy.protocol_version = 2
	legacy.erase("speed_factors")
	legacy.erase("report_context")
	check(restored.restore(disk_roundtrip(legacy, "comparison-v2")), "Un checkpoint 2 valide doit être accepté avec ses trois facteurs historiques.")
	check(restored.current_index == 17 and restored.plan == quick.plan and restored.speed_factors == CalibrationService.FACTORS and restored.checkpoint().protocol_version == 3, "Migrer de 2 vers 3 doit conserver le passage attendu et les facteurs legacy.")
	var unchanged := restored.checkpoint()
	var malformed: Array[Dictionary] = []
	var bad := checkpoint.duplicate(true)
	bad.speed_factors = [2.0, 1.0, 0.5]
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.report_context.renderer = "mobile"
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.report_context.scenario_fingerprints.C02 = "changed"
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.trials[0].comfort = 3.5
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.trials[0].candidate_index = 2
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.current_index = "60"
	malformed.append(bad)
	bad = legacy.duplicate(true)
	bad.protocol_version = 1
	malformed.append(bad)
	bad = legacy.duplicate(true)
	bad.speed_factors = [0.5, 1.0, 2.0]
	malformed.append(bad)
	for data in malformed:
		check(not restored.restore(data), "Un checkpoint de comparaison incohérent doit être refusé.")
		check(AdaptiveService.same_value(restored.checkpoint(), unchanged), "Une restauration invalide ne doit pas détruire la progression existante.")


func test_physical_bounds() -> void:
	for distance_cm in [5.0, 8.0, 35.0, 140.0, 150.0]:
		var profile := SensitivityService.default_profile()
		profile.cm_per_360 = distance_cm
		var search := new_search(profile, "bounds-%d" % int(distance_cm))
		var spec := search.current_spec()
		var calibration := CalibrationService.new()
		check(calibration.begin(spec.profile, spec.aspect, spec.seed, spec.calibration_id, spec.speed_factors), "Les départs proches des limites doivent produire un comparateur valide.")
		var distances: Array[float] = []
		for candidate_index in 3:
			var candidate := calibration.candidate_profile(candidate_index)
			distances.append(float(candidate.cm_per_360))
			check(SensitivityService.validate_profile(candidate).is_empty(), "Chaque candidat doit respecter les limites physiques 5–150 cm/360°.")
		check(distances[0] > distances[1] and distances[1] > distances[2], "Les bornes doivent conserver trois profils physiques distincts par géométrie.")
		check(spec.speed_factors == [0.5, 1.0, 2.0] and profile.cm_per_360 == distance_cm and search.initial_profile.cm_per_360 == distance_cm, "L’exploration large ne doit jamais remplacer le profil sauvegardé de départ.")
		if distance_cm == 5.0 or distance_cm == 150.0:
			check(distance_cm in distances and spec.center_adjusted and "hors du centre" in str(spec.label), "À 5/150 cm, le départ reste un candidat et sa position hors centre est explicitée.")


func test_full_comparison_required() -> void:
	var search := new_search()
	var spec := search.current_spec()
	var incomplete := CalibrationService.new()
	check(incomplete.begin(spec.profile, spec.aspect, spec.seed, spec.calibration_id, spec.speed_factors), "Le comparateur incomplet doit avoir un contexte valide.")
	for trial_index in 59:
		check(incomplete.accept(trial_report(incomplete, [30, 70, 40]), 4), "Tous les passages précédant le dernier doivent être acceptés.")
	check(not search.accept_comparison(incomplete.recommendation()) and search.history.is_empty() and search.current_spec() == spec, "59 passages ne peuvent pas déplacer le centre ni terminer la comparaison.")
	check(incomplete.accept(trial_report(incomplete, [30, 70, 40]), 4), "Le dernier passage valide doit terminer la comparaison.")
	var report := incomplete.recommendation()
	var malformed: Array[Dictionary] = []
	var bad := report.duplicate(true)
	bad.best_tested_cm_per_360 = 17.5
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.candidates[0].index = 2
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.seed += 1
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.speed_factors = [0.9, 1.0, 1.1]
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.trials[0].performance.max_frametime_ms = 300.0
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.trials[0].metrics.input_events = 0
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.trials[0].profile.invert_y = true
	malformed.append(bad)
	bad = report.duplicate(true)
	bad.candidates[0].per_scenario.C02.median_utility = NAN
	malformed.append(bad)
	for data in malformed:
		check(not search.accept_comparison(data) and search.history.is_empty() and search.current_spec() == spec, "Une recommandation forgée ou de mauvaise qualité doit être refusée sans changement d’état.")
	check(search.accept_comparison(report) and search.history.size() == 1, "Seule la comparaison complète reconstruite doit faire avancer la recherche.")
	check(not search.accept_comparison(report) and search.history.size() == 1, "Le même bilan ne doit jamais être accepté deux fois à la reprise.")


func test_stable_search() -> void:
	var imported := GameProfileService.import_profile(SensitivityService.default_profile(), "cs2", 1600.0, 0.8)
	check(imported.error.is_empty(), "Le profil source doit être valide pour tester sa préservation.")
	var profile: Dictionary = imported.profile
	var original := profile.duplicate(true)
	var search := new_search(profile, "stable-source")
	var expected_cm: float = float(profile.cm_per_360) / 2.0
	var phases: Array[String] = ["explore", "explore", "refine", "validate"]
	for round_index in 4:
		var spec := search.current_spec()
		check(spec.round_index == round_index and spec.phase == phases[round_index], "La recherche doit déplacer le centre puis resserrer 25 % et 10 %.")
		check(spec.seed == 42 + round_index * 104729 and spec.calibration_id == "stable-source-r%d" % round_index, "Chaque comparaison doit avoir un id et une graine distincts reproductibles.")
		var values: Array = [30, 40, 70] if round_index == 0 else [30, 70, 40]
		var completed := comparison_from_spec(spec, values)
		check(search.accept_comparison(completed.recommendation()), "Un avantage stable et confortable doit être accepté.")
		check(AdaptiveService.same_value(profile, original), "La recherche ne doit jamais appliquer ou réinterpréter le profil source.")
	var result := search.final_result()
	check(search.finished and search.current_spec().is_empty() and result.search_status == "stable", "La validation centrale à 10 % termine une recherche stable.")
	check(result.trial_allowed and result.confirmation_required and not result.apply_allowed and result.confirmation_after_days == [2, 7], "Une recherche stable autorise un essai volontaire et exige une confirmation différée sans appliquer automatiquement.")
	check(is_equal_approx(float(result.recommended_cm_per_360), expected_cm) and result.current_report.trials_completed == 60, "Le résultat conserve le dernier bilan complet et le réglage réellement testé.")
	check(result.current_report.scenario_results.size() == 5 and result.search_history.size() == 4 and result.initial_profile.reference_game == original.reference_game, "Les traces doivent préserver les cinq exercices, toutes les comparaisons et la conversion source.")
	var exported_history: Array[Dictionary] = search.history
	exported_history[0].baseline.cm_per_360 = 99.0
	check(search.history[0].baseline.cm_per_360 != 99.0, "Le getter history ne doit pas permettre de modifier les traces internes.")
	check(not search.accept_comparison(result.current_report), "Un bilan final répété doit rester refusé.")
	var restored := AdaptiveService.new()
	check(restored.restore(disk_roundtrip(search.checkpoint(), "stable-source-final")), "Les profils source de pleine précision doivent survivre au rejeu JSON final : " + restored.error)
	check(AdaptiveService.same_value(restored.final_result(), result), "Un recalcul flottant à l’arrondi machine près ne doit pas invalider une vraie reprise.")


func test_refine_edge_recenter() -> void:
	var search := new_search(SensitivityService.default_profile(), "refine-edge-test")
	check(search.accept_comparison(comparison_from_spec(search.current_spec(), [30, 70, 40]).recommendation()), "Un centre gagnant doit amorcer l’affinage.")
	var refined := comparison_from_spec(search.current_spec(), [70, 30, 40])
	var winner_cm: float = refined.recommendation().best_tested_cm_per_360
	check(search.accept_comparison(refined.recommendation()), "Un bord gagnant de l’affinage doit être traité sans inventer un optimum.")
	check(not search.finished and search.current_spec().phase == "validate" and search.current_spec().profile.cm_per_360 == winner_cm, "La validation doit se recentrer sur ce meilleur essai, pas s’arrêter arbitrairement ni repartir du même centre.")
	check(search.accept_comparison(comparison_from_spec(search.current_spec(), [30, 70, 40]).recommendation()), "La nouvelle validation doit être réellement rejouée sur les cinq exercices.")
	check(search.finished and search.final_result().trial_allowed and search.history.size() == 3, "Seule une validation centrale cohérente après le déplacement autorise l’essai provisoire.")
	var restored := AdaptiveService.new()
	check(restored.restore(search.checkpoint()), "Le recentrage d’affinage doit être reproduit depuis l’historique vérifié.")


func test_bounded_search() -> void:
	var search := new_search()
	for round_index in 4:
		var spec := search.current_spec()
		var values: Array = [30, 40, 70] if round_index < 2 else [30, 70, 40]
		check(search.accept_comparison(comparison_from_spec(spec, values).recommendation()), "Chaque comparaison du budget maximal doit rester complète.")
		if round_index < 2:
			check(search.current_spec().phase == "explore" and search.current_spec().speed_factors == [0.5, 1.0, 2.0], "Au maximum deux déplacements gardent l’exploration large.")
	var result := search.final_result()
	check(search.finished and search.history.size() == 4 and result.search_status == "limit_reached", "Quatre comparaisons sans validation à 10 % doivent produire un échec explicite.")
	check(result.recommended_cm_per_360 == 35.0 and not result.apply_allowed and not result.confirmation_required, "Un budget épuisé conserve le départ et conseille un retest.")
	for distance_cm in [5.0, 150.0]:
		var profile := SensitivityService.default_profile()
		profile.cm_per_360 = distance_cm
		var bounded := new_search(profile)
		var values: Array = [30, 40, 70] if distance_cm == 5.0 else [70, 40, 30]
		check(bounded.accept_comparison(comparison_from_spec(bounded.current_spec(), values).recommendation()), "Un meilleur testé sur une borne physique peut être expliqué.")
		check(bounded.finished and bounded.final_result().search_status == "boundary_limited" and not bounded.final_result().apply_allowed, "Un centre impossible à déplacer ne doit pas tourner en boucle ou annoncer un optimum.")


func test_uncertainty_and_comfort() -> void:
	for mode in ["tie", "close", "noise", "no_signal", "comfort"]:
		var search := new_search()
		var values: Array = [50, 50, 50] if mode == "tie" else ([50, 51, 50] if mode == "close" else ([40, 45, 40] if mode == "noise" else [30, 70, 40]))
		var completed := comparison_from_spec(search.current_spec(), values, "C02" if mode == "comfort" else "", mode == "no_signal", mode == "noise")
		var report := completed.recommendation()
		if mode == "comfort":
			check(report.status == "indicative", "Un inconfort propre à un exercice peut être masqué par la médiane globale.")
		check(search.accept_comparison(report), "Une comparaison complète incertaine doit pouvoir produire un échec expliqué.")
		var result := search.final_result()
		var expected_status: String = "uncomfortable" if mode == "comfort" else ("insufficient" if mode == "no_signal" else "uncertain")
		check(search.finished and result.search_status == expected_status and search.current_spec().is_empty(), "Bruit, absence de signal et inconfort doivent stopper la recherche.")
		check(result.recommended_cm_per_360 == 35.0 and not result.trial_allowed and not result.apply_allowed and not result.advice.is_empty(), "Une recherche non concluante conserve le départ, bloque l’essai du conseil et donne une raison de retest.")


func test_search_restore() -> void:
	check(not AdaptiveService.same_value(1000000000000000, 1000000000000001), "Les compteurs et graines entiers ne doivent jamais bénéficier de tolérance flottante.")
	var search := new_search()
	var empty_checkpoint := disk_roundtrip(search.checkpoint(), "search-empty")
	var restored := AdaptiveService.new()
	check(restored.restore(empty_checkpoint) and AdaptiveService.same_value(restored.current_spec(), search.current_spec()), "La pause avant le premier passage doit être reprenable.")
	for round_index in 3:
		var spec := search.current_spec()
		check(search.accept_comparison(comparison_from_spec(spec).recommendation()), "Les comparaisons centrales complètes doivent conduire à une confirmation différée.")
		var saved := disk_roundtrip(search.checkpoint(), "search-round-%d" % round_index)
		check(restored.restore(saved), "Pause/reprise doit revalider l’historique et dériver le même état : " + restored.error)
		check(AdaptiveService.same_value(restored.final_result(), search.final_result()) and AdaptiveService.same_value(restored.current_spec(), search.current_spec()), "Le rejeu doit reproduire le bilan et la comparaison suivante sans double acceptation.")
	var valid := search.checkpoint()
	var unchanged := restored.checkpoint()
	var malformed: Array[Dictionary] = []
	var bad := valid.duplicate(true)
	bad.search_version = 2
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.state.finished = false
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.state.seed += 1
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.history[0].search_step.winner_index = 2
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.history[0].candidates[0].value = 0.01
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.history[0].trials[0].comfort = "four"
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.history.reverse()
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.history.append(bad.history[0].duplicate(true))
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.state.initial_profile.cm_per_360 = 36.0
	malformed.append(bad)
	bad = valid.duplicate(true)
	bad.history[0].report_context.renderer = "mobile"
	malformed.append(bad)
	for data in malformed:
		var original := data.duplicate(true)
		check(not restored.restore(data), "Un historique ou état altéré doit être refusé, sans faire confiance au gagnant déclaré.")
		check(AdaptiveService.same_value(restored.checkpoint(), unchanged) and AdaptiveService.same_value(data, original), "La restauration échouée protège l’état actif et les données fournies.")


func disk_roundtrip(data: Dictionary, identifier: String) -> Dictionary:
	var path: String = test_root.path_join(identifier + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Le checkpoint synthétique doit être écrit dans le dossier de test isolé.")
	if file == null:
		return {}
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "Le checkpoint doit être relu comme un vrai document JSON.")
	return parsed if parsed is Dictionary else {}


func test_guided_application() -> void:
	var main_scene := load("res://scenes/app/Main.tscn") as PackedScene
	check(main_scene != null, "L’intégration guidée doit charger la vraie scène Main.")
	if main_scene == null:
		return
	var app := main_scene.instantiate()
	app.store = LocalStore.new(test_root.path_join("guided-app"))
	var imported := GameProfileService.import_profile(SensitivityService.default_profile(), "cs2", 1600.0, 0.8)
	var initial: Dictionary = imported.profile
	initial.sound_enabled = false
	check(app.store.save_profile(initial), "Le parcours UI doit utiliser un profil isolé de pleine précision.")
	root.add_child(app)
	await process_frame
	app.start_guided_calibration()
	check(app.is_guided and app.is_calibrating and app.screen == app.Screen.COUNTDOWN, "Le bouton de recherche doit lancer le premier candidat large sans appliquer de conseil.")
	if not app.is_guided:
		app.queue_free()
		await process_frame
		return
	var expected_cm: float = float(initial.cm_per_360) / 2.0
	for round_index in 4:
		var scored_count: int = 0
		for passage_index in 60:
			var stage: Dictionary = app.calibration.current_stage()
			if stage.is_empty():
				check(false, "Le parcours UI ne doit pas terminer une comparaison avant ses 60 passages.")
				break
			var values: Array = [30, 40, 70] if round_index == 0 else [30, 70, 40]
			app.pending_trial = trial_report(app.calibration, values if stage.scored else [90, 10, 90])
			app.pending_trial.warmup = not bool(stage.scored)
			check(app.store.save_session(app.pending_trial), "Chaque passage synthétique du parcours UI doit être enregistré hors des données produit.")
			app.session_panel.comfort_input.value = 4
			app.screen = app.Screen.REST
			app.rest_until_us = 0
			app.next_calibration_stage()
			check(app.calibration.current_index == passage_index + 1, "Le callback Main doit valider et sauvegarder exactement un passage.")
			if stage.scored:
				scored_count += 1
			if round_index == 0 and passage_index == 16:
				app.return_to_menu()
				app.resume_guided_calibration()
				check(app.is_guided and app.calibration.current_index == 17 and app.guided_search.history.is_empty(), "Une reprise au milieu d’un exercice doit retrouver le candidat et les 17 passages, sans bilan prématuré.")
		check(scored_count == 45 and app.screen == app.Screen.RESULTS, "Chaque bilan Main doit résulter de 45 mesures et 15 familiarisations.")
		check(app.guided_search.history.size() == round_index + 1, "Main doit accepter chaque comparaison complète une seule fois.")
		var wrapped: Dictionary = app.store.load_guided_checkpoint()
		var expected_phase: String = "complete" if round_index == 3 else "transition"
		check(not wrapped.is_empty() and wrapped.phase == expected_phase, "Le fichier atomique doit conserver le comparateur accepté et la bonne phase.")
		var replay := AdaptiveService.new()
		check(replay.restore(wrapped.search_state) and AdaptiveService.same_value(replay.final_result(), app.guided_search.final_result()), "L’historique sauvegardé par Main doit se reconstruire à partir des vrais passages.")
		app.apply_recommendation()
		check(app.store.load_profile().cm_per_360 == initial.cm_per_360, "Afficher un bilan ou appeler Appliquer sans consentement ne doit pas modifier le profil.")
		app.return_to_menu()
		app.resume_guided_calibration()
		check(app.guided_phase == expected_phase and app.guided_search.history.size() == round_index + 1, "Reprendre un bilan déjà accepté ne doit jamais ajouter une seconde comparaison.")
		if round_index < 3:
			app.next_calibration_stage()
			check(app.guided_phase == "comparing" and app.calibration.current_index == 0 and app.guided_search.current_spec().round_index == round_index + 1, "Continuer depuis RESULTS doit lancer explicitement la prochaine plage, avec un comparateur neuf.")
	var result: Dictionary = app.final_recommendation
	check(result.search_status == "stable" and result.trial_allowed and result.confirmation_required and not result.apply_allowed, "Le bilan racine peut autoriser un essai du conseil stable sans le déclarer définitivement validé.")
	check(app.session_panel.guided_confirmation.visible and not app.session_panel.guided_confirmation.button_pressed and app.session_panel.apply_button.disabled, "La case de consentement doit être visible et le bouton d’essai bloqué avant action explicite.")
	app.session_panel.guided_confirmation.button_pressed = true
	check(not app.session_panel.apply_button.disabled, "Cocher le consentement doit autoriser le bouton Essayer ce conseil.")
	app.apply_recommendation()
	var trial_profile: Dictionary = app.store.load_profile()
	check(app.screen == app.Screen.HOME and trial_profile.cm_per_360 == snappedf(expected_cm, 0.001), "L’essai explicitement accepté doit enregistrer uniquement le réglage réellement testé et revenir au menu.")
	check(trial_profile.dpi == initial.dpi and trial_profile.vertical_fov_deg == initial.vertical_fov_deg and AdaptiveService.same_value(trial_profile.reference_game, initial.reference_game), "L’essai du conseil doit préserver DPI actifs, FOV et provenance de conversion.")
	check(app.guided_search.final_result().confirmation_required and not app.guided_search.final_result().apply_allowed, "Un essai volontaire ne constitue pas une confirmation différée déjà réalisée.")
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
