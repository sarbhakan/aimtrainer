extends RefCounted

var verify: Callable

const HISTORICAL_FINGERPRINTS: Dictionary = {
	"C02": "a7fa138239543b4a6640556a2ada4bf2b969e1fbe0d41e478d8a1bb7b6f82602",
	"C04": "03334159e7e3601d16d4e79edbfef121a92198d5e4c017a2d81891b29aedcf92",
	"S01": "2d35b015e4b51ec81c0a21c26c0f9e0aba9da9f89125ff9115e80172b64e1f08",
	"T01": "57d0ba43baf2b2a130b269dc7ee0186bb6d8d88d6a0821ab5607de788f39fb7f",
	"T05": "661fcda2e1c27988d1463b20762f7d0152d4a4c5e1f322a985154612262e9bdf"
}


func run(_tree: SceneTree, check: Callable) -> bool:
	verify = check
	var historical_definitions := CalibrationRevisionArchive.definitions()
	for scenario_id in HISTORICAL_FINGERPRINTS:
		expect(historical_definitions[scenario_id].fingerprint() == HISTORICAL_FINGERPRINTS[scenario_id], "Le validateur historique conserve l’empreinte réellement publiée en 0.4 : " + scenario_id)
	for protocol_version in [2, 3]:
		for trial_count in [0, 18, 60]:
			test_comparison_archive(trial_count, protocol_version)
	test_guided_archive(false)
	test_guided_archive(true)
	test_rejected_history()
	return true


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func historical_comparison(profile: Dictionary, factors: Array, seed_value: int, identifier: String, trial_count: int) -> CalibrationService:
	var comparison := CalibrationService.new()
	comparison.scenario_overrides = CalibrationRevisionArchive.definitions()
	expect(comparison.begin(profile, 16.0 / 9.0, seed_value, identifier, factors), "Le contexte historique doit accepter les paramètres 0.4 sans utiliser les nouvelles cibles.")
	for trial_index in trial_count:
		var stage := comparison.current_stage()
		var definition := comparison.find_definition(stage.scenario_id)
		var engine := ScenarioEngine.new()
		engine.start(definition, int(stage.seed), float(stage.duration_s))
		engine.advance_to(float(stage.duration_s))
		var report := engine.result(comparison.candidate_profile(int(stage.candidate_index)), comparison.aspect, true)
		report.app_version = "0.4.0"
		report.metrics.input_events = 100
		report.metrics.angular_path_deg = 20.0
		if definition.family == "tracking":
			var ratio: float = [0.3, 0.8, 0.4][int(stage.candidate_index)]
			report.metrics.on_target_ratio = ratio
			report.metrics.on_target_time_s = float(stage.duration_s) * ratio
		else:
			var hit_count: int = [30, 80, 40][int(stage.candidate_index)]
			report.metrics.shots = hit_count
			report.metrics.hits = hit_count
			report.metrics.misses = 0
			report.metrics.accuracy_fraction = 1.0
			report.metrics.accuracy_pct = 100.0
			report.metrics.hits_per_s = float(hit_count) / float(stage.duration_s)
		report.performance = {"frame_samples": 1000, "frametime_p95_ms": 7.0, "frametime_p99_ms": 8.0, "max_frametime_ms": 12.0}
		report.score = ScoringService.score(report, definition.reference_hits_s)
		if not comparison.accept(report, 4):
			expect(false, "La fixture historique doit être entièrement vérifiée : " + comparison.error)
			break
	return comparison


func new_checkpoint() -> Dictionary:
	var comparison := CalibrationService.new()
	expect(comparison.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, LocalStore.new().identifier()), "La nouvelle comparaison doit être valide avant l’archivage.")
	return comparison.checkpoint()


func write_historical(store: LocalStore, path: String, data: Dictionary) -> PackedByteArray:
	var contents := ("\r\n" + JSON.stringify(data, "  ", false, true).replace("\n", "\r\n") + "\r\n").to_utf8_buffer()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	expect(file != null, "Le fichier historique doit être accessible dans le dossier de test isolé.")
	if file != null:
		file.store_buffer(contents)
		file.close()
	expect(store.read_json(path).ok, "La fixture historique doit survivre à la relecture JSON.")
	return contents


func test_comparison_archive(trial_count: int, protocol_version: int) -> void:
	var store := LocalStore.new("user://tests/revision-" + LocalStore.new().identifier())
	var old := historical_comparison(SensitivityService.default_profile(), CalibrationService.FACTORS, 42, "revision-two", trial_count).checkpoint()
	if protocol_version == 2:
		old.protocol_version = 2
		old.erase("speed_factors")
		old.erase("report_context")
	var path := store.root_path + "/calibration_checkpoint.json"
	var contents := write_historical(store, path, old)
	expect(store.load_checkpoint().is_empty() and store.last_error.contains("mis à jour"), "Une difficulté historique est expliquée, jamais reprise avec les nouvelles cibles.")
	expect(FileAccess.get_file_as_bytes(path) == contents, "La lecture ne doit pas modifier l’historique.")
	var next := new_checkpoint()
	expect(store.save_checkpoint(next), "Une ancienne comparaison reconnue doit permettre une nouvelle calibration : " + store.last_error)
	expect(FileAccess.get_file_as_bytes(store.root_path + "/archives/revision-two.json") == contents, "L’archive conserve les octets exacts du checkpoint 0.4, même complet.")
	expect(FileAccess.get_file_as_bytes(path + ".bak") == contents, "Le backup conserve aussi la version précédente exacte.")
	expect(not store.load_checkpoint().is_empty(), "Le nouveau protocole doit être reprenable après archivage.")
	if trial_count > 0:
		var old_trial: Dictionary = old.trials.back()
		var definition := ScenarioCatalog.find(old_trial.scenario_id)
		var key := ScoringService.comparison_key(definition, float(old_trial.duration_s), old_trial.profile, float(old_trial.aspect))
		expect(ProgressService.summarize([old_trial], key).count == 0, "Un résultat historique ne peut jamais devenir un record de la nouvelle difficulté.")


func guided_envelope(accepted: bool, historical: bool) -> Dictionary:
	var search := AdaptiveSensitivityService.new()
	if historical:
		search.scenario_overrides = CalibrationRevisionArchive.definitions()
	expect(search.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "guided-" + LocalStore.new().identifier()), "La recherche doit démarrer dans son contexte explicite.")
	var spec := search.current_spec()
	var comparison: CalibrationService
	if historical:
		comparison = historical_comparison(spec.profile, spec.speed_factors, int(spec.seed), spec.calibration_id, 60 if accepted else 18)
	else:
		comparison = CalibrationService.new()
		expect(comparison.begin(spec.profile, float(spec.aspect), int(spec.seed), spec.calibration_id, spec.speed_factors), "La comparaison actuelle doit correspondre à sa recherche.")
	if accepted:
		expect(search.accept_comparison(comparison.recommendation()), "L’historique guidé doit être accepté depuis ses véritables mesures : " + search.error)
	return {"schema_version": 1, "phase": "transition" if accepted else "comparing", "search_state": search.checkpoint(), "comparison": comparison.checkpoint()}


func test_guided_archive(accepted: bool) -> void:
	var store := LocalStore.new("user://tests/revision-guided-" + LocalStore.new().identifier())
	var old := guided_envelope(accepted, true)
	var path := store.root_path + "/guided_calibration_checkpoint.json"
	var contents := write_historical(store, path, old)
	expect(store.load_guided_checkpoint().is_empty() and store.last_error.contains("mis à jour"), "Une ancienne recherche est reconnue depuis son contrôleur et sa comparaison, sans reprise partielle.")
	expect(store.save_guided_checkpoint(guided_envelope(false, false)), "Un historique guidé 0.4 entièrement vérifié doit pouvoir être archivé : " + store.last_error)
	var archive := store.root_path + "/archives/guided-" + str(old.search_state.state.search_id) + ".json"
	expect(FileAccess.get_file_as_bytes(archive) == contents, "L’enveloppe guidée entière est archivée sans perte de ses décisions.")
	expect(not store.load_guided_checkpoint().is_empty(), "La nouvelle recherche doit être reprenable.")


func test_rejected_history() -> void:
	var original := historical_comparison(SensitivityService.default_profile(), CalibrationService.FACTORS, 42, "revision-two-bad", 18).checkpoint()
	for patch in [{"protocol_version": 99}, {"current_index": 17}, {"report_context": {}}]:
		var malformed := original.duplicate(true)
		malformed.merge(patch, true)
		assert_protected(malformed)
	var forged := original.duplicate(true)
	forged.trials[0].scenario_fingerprint = "a".repeat(64)
	assert_protected(forged)
	forged = original.duplicate(true)
	forged.trials[0].metrics.hits = 99999
	assert_protected(forged)
	var store := LocalStore.new("user://tests/revision-guided-bad-" + LocalStore.new().identifier())
	var envelope := guided_envelope(true, true)
	envelope.search_state.history[0].search_step.winner_index = 2
	var path := store.root_path + "/guided_calibration_checkpoint.json"
	var contents := write_historical(store, path, envelope)
	expect(not store.save_guided_checkpoint(guided_envelope(false, false)), "Une décision guidée falsifiée ne doit pas bénéficier de la migration.")
	expect(FileAccess.get_file_as_bytes(path) == contents, "L’enveloppe incohérente est conservée sans écrasement.")


func assert_protected(data: Dictionary) -> void:
	var store := LocalStore.new("user://tests/revision-bad-" + LocalStore.new().identifier())
	var path := store.root_path + "/calibration_checkpoint.json"
	var contents := write_historical(store, path, data)
	expect(not store.save_checkpoint(new_checkpoint()), "La migration refuse un contexte inconnu ou un passage incohérent.")
	expect(FileAccess.get_file_as_bytes(path) == contents and not FileAccess.file_exists(store.root_path + "/archives/revision-two-bad.json"), "Le checkpoint non reconnu n’est ni écrasé ni archivé comme valide.")
