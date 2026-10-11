extends RefCounted

const MainScene: PackedScene = preload("res://scenes/app/Main.tscn")
const LEGACY_SCENARIOS: Array[String] = ["C02", "C04", "S01", "T01", "T05"]
const LEGACY_FACTORS: Array[float] = [0.9, 1.0, 1.1]

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	for trial_count in [0, 18, 35, 60]:
		await test_application_migration(tree, trial_count)
	test_validation_before_archiving()
	test_unknown_and_malformed()
	await test_archive_collisions(tree)
	test_archiving_failure()
	test_archive_retries()
	verify = Callable()
	return true


func legacy_profile() -> Dictionary:
	return {"schema_version": 1, "dpi": 800.0, "cm_per_360": 35.12345678912345,
		"vertical_fov_deg": 75.0, "goal": "balanced", "accumulated_input": true, "max_fps": 144,
		"weapon_id": "pulse", "sound_enabled": true, "sound_volume": 45.0, "show_weapon": true, "reduced_motion": false}


func legacy_definition(scenario_id: String) -> ScenarioDefinition:
	var definition: ScenarioDefinition = ScenarioCatalog.find(scenario_id).duplicate() as ScenarioDefinition
	definition.revision = 1
	definition.distance_m = 8.0
	if scenario_id == "C02":
		definition.angular_diameter_deg = 0.65
	return definition


func legacy_fingerprint(definition: ScenarioDefinition) -> String:
	return JSON.stringify([definition.scenario_id, definition.revision, definition.family, definition.motion,
		definition.layout, definition.angular_diameter_deg, definition.yaw_extent_deg, definition.pitch_extent_deg,
		definition.min_transition_deg, definition.speed_deg_s, definition.active_targets, definition.lifetime_s,
		definition.reference_hits_s, definition.distance_m]).sha256_text()


func legacy_plan(seed_value: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	for scenario_index in LEGACY_SCENARIOS.size():
		for candidate_index in LEGACY_FACTORS.size():
			plan.append(legacy_stage(scenario_index, candidate_index, -1, seed_value))
	for repetition in 3:
		for scenario_offset in LEGACY_SCENARIOS.size():
			var scenario_index: int = (scenario_offset + repetition) % LEGACY_SCENARIOS.size()
			for order_index in LEGACY_FACTORS.size():
				var candidate_index: int = (repetition + scenario_index + order_index) % LEGACY_FACTORS.size()
				plan.append(legacy_stage(scenario_index, candidate_index, repetition, seed_value))
	return plan


func legacy_stage(scenario_index: int, candidate_index: int, repetition: int, seed_value: int) -> Dictionary:
	return {"scenario_id": LEGACY_SCENARIOS[scenario_index], "candidate_index": candidate_index,
		"repetition": repetition, "scored": repetition >= 0, "duration_s": 12.0 if repetition >= 0 else 8.0,
		"seed": seed_value + scenario_index * 7919 + (repetition + 1) * 1009}


func legacy_report(stage: Dictionary, baseline: Dictionary, aspect: float) -> Dictionary:
	var definition: ScenarioDefinition = legacy_definition(stage.scenario_id)
	var profile: Dictionary = baseline.duplicate(true)
	profile.cm_per_360 = float(baseline.cm_per_360) / LEGACY_FACTORS[int(stage.candidate_index)]
	var engine: ScenarioEngine = ScenarioEngine.new()
	engine.start(definition, int(stage.seed), float(stage.duration_s))
	engine.advance_to(float(stage.duration_s))
	var report: Dictionary = engine.result(profile, aspect, true)
	report.app_version = "0.2.0"
	report.scenario_fingerprint = legacy_fingerprint(definition)
	report.comparison_key = JSON.stringify([report.scenario_fingerprint, 1, float(stage.duration_s),
		float(profile.dpi), float(profile.cm_per_360), float(profile.vertical_fov_deg), snappedf(aspect, 0.0001),
		bool(profile.accumulated_input), int(profile.max_fps), bool(profile.get("invert_y", false)), "4.7.2", "compatibility"]).sha256_text()
	report.metrics.input_events = 100
	report.metrics.angular_path_deg = 10.0
	if definition.family == "tracking":
		report.metrics.on_target_ratio = 0.5
		report.metrics.on_target_time_s = float(stage.duration_s) * 0.5
	else:
		report.metrics.shots = 12
		report.metrics.hits = 12
		report.metrics.misses = 0
		report.metrics.accuracy_fraction = 1.0
		report.metrics.accuracy_pct = 100.0
		report.metrics.hits_per_s = 12.0 / float(stage.duration_s)
	report.performance = {"frame_samples": 1000, "frametime_p95_ms": 7.0, "frametime_p99_ms": 8.0, "max_frametime_ms": 12.0}
	report.score = ScoringService.score(report, definition.reference_hits_s)
	report.candidate_index = int(stage.candidate_index)
	report.repetition = int(stage.repetition)
	report.scored = bool(stage.scored)
	report.warmup = not bool(stage.scored)
	report.comfort = 3
	return report


func legacy_checkpoint(trial_count: int) -> Dictionary:
	var baseline: Dictionary = legacy_profile()
	var plan: Array[Dictionary] = legacy_plan(42)
	var trials: Array[Dictionary] = []
	for trial_index in trial_count:
		trials.append(legacy_report(plan[trial_index], baseline, 16.0 / 9.0))
	return {"schema_version": 1, "protocol_version": 1, "baseline": baseline, "aspect": 16.0 / 9.0,
		"seed": 42, "calibration_id": "legacy-" + LocalStore.new().identifier(), "current_index": trial_count,
		"trials": trials, "status": "complete" if trial_count == 60 else "active", "note": "Séance héritée · précision é"}


func raw_checkpoint(data: Dictionary) -> PackedByteArray:
	return ("\r\n " + JSON.stringify(data, "  ", false, true).replace("\n", "\r\n") + "\r\n\r\n").to_utf8_buffer()


func write_bytes(path: String, contents: PackedByteArray) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir()) != OK:
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(contents)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK


func read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func checkpoint_path(store: LocalStore) -> String:
	return store.root_path.path_join("calibration_checkpoint.json")


func archive_path(store: LocalStore, data: Dictionary) -> String:
	return store.root_path.path_join("archives").path_join(str(data.calibration_id) + ".json")


func new_checkpoint() -> Dictionary:
	var calibration: CalibrationService = CalibrationService.new()
	expect(calibration.begin(legacy_profile(), 16.0 / 9.0, 42, LocalStore.new().identifier()), "Le nouveau checkpoint doit être validable avant toute migration.")
	return calibration.checkpoint()


func test_application_migration(tree: SceneTree, trial_count: int) -> void:
	var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	var old: Dictionary = legacy_checkpoint(trial_count)
	var contents: PackedByteArray = raw_checkpoint(old)
	expect(write_bytes(checkpoint_path(store), contents), "Le checkpoint historique doit être écrit dans un dossier de test isolé.")
	expect(store.load_checkpoint().is_empty(), "Le protocole 1 doit rester interdit à la reprise, même s'il est bien formé.")
	expect(read_bytes(checkpoint_path(store)) == contents, "Refuser la reprise ne doit modifier aucun octet historique.")
	if trial_count > 0:
		expect(old.trials[0].scenario_revision == 1 and old.trials[0].scenario_fingerprint != ScenarioCatalog.find("C02").fingerprint(), "La fixture partielle doit contenir l'ancienne empreinte de scénario, pas une simple version changée du protocole 2.")
	var app: Node = MainScene.instantiate()
	app.store = store
	tree.root.add_child(app)
	await tree.process_frame
	app.start_calibration()
	expect(app.is_calibrating and app.screen == app.Screen.COUNTDOWN and app.calibration.current_index == 0, "Main.start_calibration doit repartir à zéro après archivage de %d passages historiques." % trial_count)
	var saved: Dictionary = store.read_json(checkpoint_path(store))
	expect(saved.ok and saved.data.get("protocol_version", 0) == 2 and saved.data.get("trials", [null]).is_empty(), "Le fichier actif doit être un nouveau protocole 2 vide, jamais une reprise réordonnée du protocole 1.")
	expect(read_bytes(archive_path(store, old)) == contents, "L'archive immuable doit conserver les octets exacts, CRLF, Unicode, précision et données anciennes inclus.")
	expect(read_bytes(checkpoint_path(store) + ".bak") == contents, "Le backup de remplacement doit lui aussi préserver l'ancien checkpoint exact.")
	app.return_to_menu()
	app.queue_free()
	await tree.process_frame
	await tree.create_timer(0.1).timeout


func test_validation_before_archiving() -> void:
	var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	var old: Dictionary = legacy_checkpoint(0)
	var contents: PackedByteArray = raw_checkpoint(old)
	expect(write_bytes(checkpoint_path(store), contents), "La fixture précédant un nouveau checkpoint invalide doit être écrite.")
	var invalid: Dictionary = new_checkpoint()
	invalid.baseline.dpi = 0.0
	expect(not store.save_checkpoint(invalid), "Un nouveau checkpoint invalide doit être refusé avant tout archivage.")
	expect(read_bytes(checkpoint_path(store)) == contents and not FileAccess.file_exists(archive_path(store, old)), "Un refus du nouveau protocole ne doit ni toucher l'ancien ni créer son archive.")
	for patch in [{"protocol_version": 1}, {"protocol_version": "2"}, {"schema_version": true}, {"baseline": []}]:
		var malformed_new: Dictionary = new_checkpoint()
		malformed_new.merge(patch, true)
		expect(not store.save_checkpoint(malformed_new), "Les versions et types du nouveau checkpoint doivent être validés avant toute opération sur l'ancien.")
		expect(read_bytes(checkpoint_path(store)) == contents and not FileAccess.file_exists(archive_path(store, old)), "Un nouveau checkpoint malformé ne doit pas déclencher l'archivage ni remplacer l'original.")


func test_unknown_and_malformed() -> void:
	var partial: Dictionary = legacy_checkpoint(18)
	var cases: Array[Dictionary] = []
	for version in [0, 3, 99, 1.5, "1", true]:
		var unknown: Dictionary = partial.duplicate(true)
		unknown.protocol_version = version
		cases.append(unknown)
	for patch in [{"schema_version": 2}, {"schema_version": "1"}, {"schema_version": true}, {"baseline": []}, {"aspect": 0.0}, {"seed": 42.5},
		{"seed": "42"}, {"current_index": 17}, {"current_index": 18.5}, {"trials": {}},
		{"status": "complete"}, {"calibration_id": "../outside"}]:
		var malformed: Dictionary = partial.duplicate(true)
		malformed.merge(patch, true)
		cases.append(malformed)
	for profile_patch in [{"schema_version": "1"}, {"dpi": 0.0}, {"dpi": "800"}, {"cm_per_360": 5.0}, {"vertical_fov_deg": 120.0}]:
		var malformed: Dictionary = partial.duplicate(true)
		malformed.baseline.merge(profile_patch, true)
		cases.append(malformed)
	for trial_patch in [{"schema_version": "1"}, {"score_version": true}, {"candidate_index": "0"}, {"candidate_index": 2}, {"repetition": 0}, {"scored": true}, {"comfort": 0},
		{"comfort": 3.5}, {"scenario_id": "C04"}, {"seed": 43}, {"duration_s": 12.0},
		{"completed": false}, {"valid": false}, {"scenario_revision": 2}, {"scenario_fingerprint": "f".repeat(64)},
		{"comparison_key": "f".repeat(64)}, {"engine_version": "4.6.3"}, {"metrics": {}}]:
		var malformed: Dictionary = partial.duplicate(true)
		malformed.trials[0].merge(trial_patch, true)
		cases.append(malformed)
	var bad_profile: Dictionary = partial.duplicate(true)
	bad_profile.trials[0].profile.dpi = 1600.0
	cases.append(bad_profile)
	var bad_order: Dictionary = partial.duplicate(true)
	bad_order.trials[15] = legacy_report(legacy_plan(42)[16], partial.baseline, partial.aspect)
	cases.append(bad_order)
	var bad_frames: Dictionary = partial.duplicate(true)
	bad_frames.trials[0].performance.frame_samples = 0
	cases.append(bad_frames)
	var bad_activity: Dictionary = partial.duplicate(true)
	bad_activity.trials[0].metrics.input_events = 0
	cases.append(bad_activity)
	var new_data: Dictionary = new_checkpoint()
	for malformed in cases:
		var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
		var contents: PackedByteArray = raw_checkpoint(malformed)
		expect(write_bytes(checkpoint_path(store), contents), "La fixture inconnue ou malformée doit être disponible.")
		expect(not store.save_checkpoint(new_data), "Un ancien protocole inconnu, incohérent ou altéré ne doit pas être remplacé.")
		expect(read_bytes(checkpoint_path(store)) == contents and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(store.root_path.path_join("archives"))), "Un refus conservateur doit préserver les octets et ne pas archiver un document non reconnu.")
	for contents in ["{corrompu".to_utf8_buffer(), "[]".to_utf8_buffer(), PackedByteArray()]:
		var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
		expect(write_bytes(checkpoint_path(store), contents), "La fixture de JSON corrompu doit être créée.")
		expect(not store.save_checkpoint(new_data) and read_bytes(checkpoint_path(store)) == contents, "Un JSON réellement corrompu doit rester inchangé et bloquer le remplacement.")


func test_archive_collisions(tree: SceneTree) -> void:
	for same_document in [false, true]:
		var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
		var old: Dictionary = legacy_checkpoint(18)
		var contents: PackedByteArray = raw_checkpoint(old)
		var other: Dictionary = old.duplicate(true)
		if not same_document:
			other.note = "Archive différente à conserver"
		var collision: PackedByteArray = JSON.stringify(other, "\t", true, true).to_utf8_buffer()
		expect(write_bytes(checkpoint_path(store), contents) and write_bytes(archive_path(store, old), collision), "Les deux documents en collision doivent être écrits.")
		var app: Node = MainScene.instantiate()
		app.store = store
		tree.root.add_child(app)
		await tree.process_frame
		app.start_calibration()
		expect(not app.is_calibrating and app.screen == app.Screen.HOME, "Une collision d'archive doit empêcher le nouveau départ, même pour une sérialisation différente du même JSON.")
		expect(read_bytes(checkpoint_path(store)) == contents and read_bytes(archive_path(store, old)) == collision, "Une collision ne doit modifier ni le checkpoint original ni l'archive immuable.")
		app.queue_free()
		await tree.process_frame
		await tree.create_timer(0.1).timeout


func test_archiving_failure() -> void:
	var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	var old: Dictionary = legacy_checkpoint(0)
	var contents: PackedByteArray = raw_checkpoint(old)
	expect(write_bytes(checkpoint_path(store), contents), "Le checkpoint précédant une panne d'archive doit exister.")
	expect(write_bytes(store.root_path.path_join("archives"), "Dossier bloqué".to_utf8_buffer()), "Un fichier doit bloquer concrètement la création du dossier d'archives.")
	expect(not store.save_checkpoint(new_checkpoint()), "Une panne d'archivage doit empêcher tout remplacement.")
	expect(read_bytes(checkpoint_path(store)) == contents, "La panne doit laisser le checkpoint exact intact.")


func test_archive_retries() -> void:
	var store: LocalStore = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	var old: Dictionary = legacy_checkpoint(18)
	var contents: PackedByteArray = raw_checkpoint(old)
	expect(write_bytes(checkpoint_path(store), contents) and write_bytes(archive_path(store, old), contents), "Une archive exacte déjà présente doit simuler un remplacement interrompu après archivage.")
	var new_data: Dictionary = new_checkpoint()
	expect(store.save_checkpoint(new_data), "Une archive déjà identique doit permettre un réessai sans écrasement de l'archive.")
	expect(read_bytes(archive_path(store, old)) == contents, "L'archive exacte doit rester immuable après le réessai.")
	expect(store.save_checkpoint(new_data) and store.load_checkpoint().get("protocol_version", 0) == 2, "Les sauvegardes ordinaires du protocole 2 doivent continuer de fonctionner.")
	expect(read_bytes(archive_path(store, old)) == contents, "Une sauvegarde ultérieure ne doit jamais réécrire l'archive historique.")
