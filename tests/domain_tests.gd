extends RefCounted

var verify: Callable


func run(check: Callable) -> bool:
	verify = check
	test_sensitivity()
	test_clock()
	test_geometry()
	test_catalog()
	test_click_metrics()
	test_tracking_replay()
	test_timeline()
	test_calibration()
	test_persistence()
	test_progress()
	return true


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func test_sensitivity() -> void:
	for dpi in [400.0, 800.0, 1600.0, 6400.0]:
		for distance_cm in [10.0, 35.0, 80.0]:
			var rotation := SensitivityService.degrees_per_count(dpi, distance_cm)
			expect(is_equal_approx(SensitivityService.cm_per_360(dpi, rotation), distance_cm), "La conversion DPI/cm/angle doit être réversible.")
			for yaw in [0.022, 0.07, 0.0066]:
				var sensitivity := SensitivityService.game_sensitivity(dpi, distance_cm, yaw)
				expect(is_equal_approx(sensitivity * yaw, rotation), "La conversion vers un jeu doit conserver les degrés/count.")
	expect(is_equal_approx(SensitivityService.degrees_per_count(800, 35), 914.4 / 28000.0), "La constante physique doit être 360 × 2,54 = 914,4.")
	expect(is_equal_approx(SensitivityService.game_sensitivity(800, 35, 0.022), 1.4844155844), "Exemple CS2 : 800 DPI et 35 cm/360°.")
	expect(is_equal_approx(SensitivityService.game_sensitivity(800, 35, 0.07), 0.4665306122), "Exemple Valorant : 800 DPI et 35 cm/360°.")
	for invalid in [0.0, -1.0, NAN, INF]:
		expect(is_nan(SensitivityService.degrees_per_count(invalid, 35)), "DPI non positif/non fini refusé.")
		expect(is_nan(SensitivityService.game_sensitivity(800, 35, invalid)), "Coefficient yaw invalide refusé.")
	var profile := SensitivityService.default_profile()
	expect(SensitivityService.validate_profile(profile).is_empty(), "Le profil par défaut doit être valide.")
	for field in ["dpi", "cm_per_360", "vertical_fov_deg", "accumulated_input", "max_fps", "invert_y"]:
		var broken := profile.duplicate(true)
		broken[field] = "invalide"
		expect(not SensitivityService.validate_profile(broken).is_empty(), "Les types du profil doivent être vérifiés : " + field)
	expect(is_equal_approx(SensitivityService.horizontal_fov_deg(90, 16.0 / 9.0), 121.2844929), "La conversion FOV vertical/horizontal doit utiliser le format réel.")
	expect(is_nan(SensitivityService.horizontal_fov_deg(75, 0)), "Un format de fenêtre nul doit être refusé.")
	var camera := AimCamera.new()
	camera.degrees_per_count = SensitivityService.degrees_per_count(800, 35)
	camera.apply_mouse_counts(Vector2(11000000, 0))
	expect(is_equal_approx(camera.yaw_deg, -11000000.0 * camera.degrees_per_count), "Le yaw cumulé conserve sa précision après beaucoup de tours.")
	expect(absf(camera.rotation_degrees.y) <= 180.0, "La pose rendue doit rester bornée, sans effacer les counts.")
	camera.invert_y = true
	camera.reset_aim()
	camera.apply_mouse_counts(Vector2(0, 100))
	expect(camera.pitch_deg > 0, "L'inversion verticale doit changer uniquement le signe du pitch.")
	camera.free()


func test_clock() -> void:
	var clock := SessionClock.new()
	clock.start(1000000)
	clock.pause(11000000)
	clock.pause(15000000)
	expect(clock.elapsed_s(31000000) == 10.0, "Une pause de 20 secondes ne doit pas gonfler le temps actif.")
	clock.resume(31000000)
	clock.resume(32000000)
	expect(clock.elapsed_s(66000000) == 45.0, "Le chronomètre doit finir à 45 s actives malgré la pause.")
	clock.start(100)
	expect(clock.elapsed_s(50) == 0.0, "Une horloge injectée en recul ne doit pas produire un temps négatif.")


func test_geometry() -> void:
	expect(AimGeometry.direction(0, 0).is_equal_approx(Vector3.FORWARD), "Yaw/pitch nuls doivent viser -Z.")
	expect(AimGeometry.direction(90, 0).is_equal_approx(Vector3.LEFT), "Le signe du yaw doit correspondre à Camera3D.")
	expect(is_equal_approx(AimGeometry.angular_error_deg(Vector3.FORWARD, AimGeometry.direction(0.001, 0)), 0.001), "L'erreur angulaire doit rester précise près de zéro.")
	expect(is_equal_approx(AimGeometry.ray_sphere_distance(Vector3.FORWARD, Vector3(0, 0, -8), 1), 7), "L'intersection doit renvoyer la première surface.")
	expect(is_inf(AimGeometry.ray_sphere_distance(Vector3.FORWARD, Vector3(0, 0, 8), 1)), "Une cible derrière le joueur ne doit pas être touchée.")
	var radius_m := 8.0 * sin(deg_to_rad(0.325))
	expect(not is_inf(AimGeometry.ray_sphere_distance(AimGeometry.direction(0.324, 0), Vector3(0, 0, -8), radius_m)), "Un rayon juste dans la cible micro doit toucher.")
	expect(is_inf(AimGeometry.ray_sphere_distance(AimGeometry.direction(0.326, 0), Vector3(0, 0, -8), radius_m)), "Un rayon juste hors de la cible micro doit rater.")
	expect(is_inf(AimGeometry.ray_sphere_distance(Vector3.ZERO, Vector3(0, 0, -8), 1)), "Un rayon nul doit être refusé.")


func test_catalog() -> void:
	expect(ScenarioCatalog.DEFINITIONS.size() == 18, "Le catalogue doit comporter 18 exercices exécutables.")
	var identifiers: Dictionary = {}
	for definition in ScenarioCatalog.DEFINITIONS:
		var expected_revision: int = 5 if definition.scenario_id in ["C03", "M01", "T10"] else 4 if definition.scenario_id in ["D01", "D02", "S02"] else 3
		expect(definition.revision == expected_revision, definition.scenario_id + " doit conserver sa révision mécanique publiée.")
		expect(definition.validate().is_empty(), definition.scenario_id + " doit avoir une définition valide.")
		expect(definition.fits_view(75, 16.0 / 9.0), definition.scenario_id + " doit tenir dans le FOV par défaut.")
		expect(not identifiers.has(definition.scenario_id), "Les identifiants de scénario doivent être uniques.")
		identifiers[definition.scenario_id] = true
		for seed_value in [1, 42, 1337, 7919, 1000000]:
			var engine := ScenarioEngine.new()
			expect(engine.start(definition, seed_value, 1.0), definition.scenario_id + " doit générer des cibles pour chaque graine testée.")
			engine.advance_to(1.0)
			expect(engine.completed and engine.invalid_reason.is_empty(), definition.scenario_id + " doit terminer sans erreur de génération.")
			if definition.family != "tracking":
				engine.start(definition, seed_value, 10.0)
				var all_hits: bool = true
				for click_index in 100:
					var time_s := (click_index + 1) * 0.05
					var target_index := click_index % engine.targets.size()
					all_hits = engine.shoot(time_s, engine.target_direction(target_index, time_s)) and all_hits
				expect(all_hits and engine.hits == 100 and engine.invalid_reason.is_empty(), definition.scenario_id + " doit respawner 100 fois sans chevauchement impossible.")
	var broken: ScenarioDefinition = ScenarioCatalog.find("C01").duplicate()
	broken.angular_diameter_deg = -1
	expect(not broken.validate().is_empty(), "Un diamètre négatif doit être refusé.")
	broken = ScenarioCatalog.find("T01").duplicate()
	broken.active_targets = 2
	expect(not broken.validate().is_empty(), "Le tracking v1 exige une seule cible.")
	expect(not ScenarioCatalog.find("C04").fits_view(40, 0.5), "Une arène trop étroite doit être refusée, pas masquer les cibles.")
	var scatter: ScenarioDefinition = ScenarioCatalog.find("C03")
	expect(scatter.revision == 5 and scatter.layout == "scatter" and scatter.motion == "static" and scatter.active_targets == 6 and is_equal_approx(scatter.angular_diameter_deg, 4.8), "C03 doit proposer six cibles statiques de 4,8 degrés en dispersion libre, révision 5.")
	var grid_definition: ScenarioDefinition = scatter.duplicate() as ScenarioDefinition
	grid_definition.revision = 3
	grid_definition.layout = "grid"
	grid_definition.yaw_extent_deg = 18.0
	grid_definition.pitch_extent_deg = 10.0
	var grid := ScenarioEngine.new()
	expect(grid.start(grid_definition, 42, 1.0), "La fixture explicite de grille r3 doit rester exécutable.")
	for target in grid.targets:
		expect(float(target.yaw_deg) in [-grid.definition.yaw_extent_deg, 0.0, grid.definition.yaw_extent_deg] and float(target.pitch_deg) in [-grid.definition.pitch_extent_deg, 0.0, grid.definition.pitch_extent_deg], "La fixture de grille r3 doit réellement utiliser les cellules d’une grille 3×3 dans son champ versionné.")


func test_click_metrics() -> void:
	var engine := ScenarioEngine.new()
	var definition := ScenarioCatalog.find("C01")
	engine.start(definition, 42, 2.0)
	var first_target := engine.target_direction(0, 0.1)
	engine.record_aim(0.1, 1, 0)
	expect(engine.shoot(0.1, first_target), "Un clic au centre de la cible doit toucher.")
	expect(not engine.shoot(0.2, Vector3.BACK), "Un clic hors cible doit rater.")
	engine.paused = true
	engine.record_aim(1, 50, 0)
	engine.advance_to(1)
	expect(not engine.shoot(1, engine.target_direction(0, 1)) and engine.shots == 2 and engine.elapsed_s == 0.2, "La pause interdit mouvements, tirs et temps de scénario.")
	engine.paused = false
	engine.advance_to(2)
	expect(not engine.shoot(2, first_target) and engine.shots == 2, "Aucun tir ne doit être enregistré après la fin.")
	var report := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
	expect(ScoringService.validate_result(report).is_empty(), "Les métriques produites doivent respecter le schéma.")
	expect(report.metrics.shots == 2 and report.metrics.hits == 1 and report.metrics.misses == 1, "Les tirs, touches et ratés doivent être cohérents.")
	expect(report.metrics.accuracy_pct == 50.0 and report.metrics.hits_per_s == 0.5, "Précision et cadence doivent employer le temps actif.")
	expect(is_equal_approx(ScoringService.utility(report), 0.125), "Les ratés doivent être pénalisés par la précision au carré.")
	expect(not engine.result(SensitivityService.default_profile(), 1.777, false).completed, "Un abandon reste exclu, même si le timer a atteint sa limite.")
	engine.start(definition, 42, 2.0)
	expect(engine.shots == 0 and engine.hits == 0 and engine.timeline.event_count == 0, "Rejouer doit remettre tous les compteurs à zéro.")
	expect(engine.target_direction(0, 0.1).is_equal_approx(first_target), "Une même graine doit retrouver la cible initiale.")
	var empty := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, false)
	expect(empty.metrics.accuracy_pct == null and empty.score == 0.0, "Sans tir, afficher N/A et zéro score, jamais NaN.")
	var spam := report.duplicate(true)
	spam.metrics.accuracy_fraction = 0.1
	expect(ScoringService.utility(spam) < ScoringService.utility(report), "Spammer des clics ne doit pas améliorer le score à cadence de touches identique.")
	var advanced := report.duplicate(true)
	advanced.metrics.hits_per_s = 10.0
	advanced.metrics.accuracy_fraction = 1.0
	var improved := advanced.duplicate(true)
	improved.metrics.hits_per_s = 11.0
	expect(ScoringService.score(advanced, 2.0) == 5000 and ScoringService.score(improved, 2.0) == 5500, "Le score d'un joueur rapide ne doit pas plafonner artificiellement sa progression.")
	var expiration_results: Array[Dictionary] = []
	for frame_rate in [60, 144, 240]:
		engine = ScenarioEngine.new()
		engine.start(ScenarioCatalog.find("D01"), 123, 3.0)
		for frame_index in range(1, 3 * frame_rate + 1):
			engine.advance_to(float(frame_index) / frame_rate)
		expiration_results.append(engine.targets[0].duplicate(true))
		expect(engine.expired == 3, "Les cibles temporaires doivent expirer selon l'horloge et non les FPS.")
	expect(expiration_results[0] == expiration_results[1] and expiration_results[1] == expiration_results[2], "Les respawns temporaires doivent être déterministes à 60/144/240 FPS.")


func test_tracking_replay() -> void:
	for scenario_id in ["T01", "T02", "T03", "T04", "T05", "T09", "T10"]:
		var baseline_metrics: Dictionary = {}
		for frame_rate in [60, 144, 240]:
			var engine := ScenarioEngine.new()
			engine.start(ScenarioCatalog.find(scenario_id), 456, 2.0)
			for event_index in range(0, 2001):
				var time_s := event_index / 1000.0
				var target := engine.target_direction(0, time_s)
				var yaw_deg := rad_to_deg(atan2(-target.x, -target.z)) + sin(time_s * 8.0)
				var pitch_deg := rad_to_deg(asin(target.y))
				engine.record_aim(time_s, yaw_deg, pitch_deg)
			for frame_index in range(1, 2 * frame_rate + 1):
				engine.record_frame(1.0 / frame_rate)
				engine.advance_to(float(frame_index) / frame_rate)
			var report := engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
			expect(ScoringService.validate_result(report).is_empty(), scenario_id + " doit produire des données valides.")
			expect(is_equal_approx(report.metrics.target_exposed_time_s, 2.0), "L'intégration tracking doit couvrir la durée complète.")
			expect(report.metrics.on_target_ratio >= 0 and report.metrics.on_target_ratio <= 1.000001, "Le temps sur cible doit rester une proportion bornée.")
			if baseline_metrics.is_empty():
				baseline_metrics = report.metrics
			else:
				for metric in ["on_target_ratio", "angular_error_mean_deg", "angular_error_p95_deg", "reacquisition_median_ms"]:
					expect(is_equal_approx(float(report.metrics[metric]), float(baseline_metrics[metric])), scenario_id + " : " + metric + " doit être indépendant des FPS pour un même replay horodaté.")
	var engine := ScenarioEngine.new()
	engine.start(ScenarioCatalog.find("T01"), 1, 2)
	expect(not engine.shoot(0.5, Vector3.FORWARD) and engine.shots == 0, "Le tracking ne doit pas compter les clics comme du DPS.")


func test_timeline() -> void:
	var timeline := AimTimeline.new()
	timeline.reset(0, 0)
	timeline.push(0.1, 3, 4)
	timeline.push(0.2, 6, 8)
	expect(timeline.sample(0.099) == Vector2.ZERO, "Une pose future ne doit pas modifier une mesure passée.")
	expect(timeline.sample(0.1) == Vector2(3, 4) and timeline.count == 1, "La timeline doit consommer exactement les événements arrivés.")
	timeline.push(0.15, 10, 10)
	timeline.push(NAN, 0, 0)
	expect(timeline.event_count == 2 and timeline.angular_path_deg == 10.0, "Les timestamps inversés/non finis doivent être rejetés sans gonfler le trajet.")
	timeline.reset(0, 0)
	for event_index in AimTimeline.CAPACITY + 1:
		timeline.push(event_index / 8000.0, event_index * 0.01, 0)
	expect(timeline.count == AimTimeline.CAPACITY and timeline.overflow_count == 1, "Le tampon doit rester borné et signaler sa saturation.")
	var engine := ScenarioEngine.new()
	engine.start(ScenarioCatalog.find("T01"), 1, 10)
	engine.timeline = timeline
	engine.advance_to(0.1)
	expect(not engine.result(SensitivityService.default_profile(), 16.0 / 9.0, false).valid, "Une perte de données d'input doit invalider la séance.")


func trial_report(calibration: CalibrationService, values: Array, comfort: int = 3) -> Dictionary:
	var stage := calibration.current_stage()
	var definition := ScenarioCatalog.find(stage.scenario_id)
	var engine := ScenarioEngine.new()
	engine.start(definition, int(stage.seed), float(stage.duration_s))
	engine.advance_to(float(stage.duration_s))
	var report := engine.result(calibration.candidate_profile(int(stage.candidate_index)), calibration.aspect, true)
	var value := float(values[int(stage.candidate_index)])
	report.metrics.input_events = 100
	report.metrics.angular_path_deg = 10.0
	if definition.family == "tracking":
		report.metrics.on_target_ratio = value / 100.0
		report.metrics.on_target_time_s = float(stage.duration_s) * value / 100.0
	else:
		report.metrics.shots = round(value)
		report.metrics.hits = round(value)
		report.metrics.misses = 0
		report.metrics.accuracy_fraction = 1.0
		report.metrics.accuracy_pct = 100.0
		report.metrics.hits_per_s = value / float(stage.duration_s)
	report.performance = {"frame_samples": 1000, "frametime_p95_ms": 7.0, "frametime_p99_ms": 8.0, "max_frametime_ms": 12.0}
	report.score = ScoringService.score(report, definition.reference_hits_s)
	report.comfort = comfort
	return report


func completed_calibration(values: Array, discomfort_candidate: int = -1) -> CalibrationService:
	var calibration := CalibrationService.new()
	expect(calibration.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "test-calibration"), "Le protocole doit démarrer avec des conditions valides.")
	while not calibration.current_stage().is_empty():
		var candidate_index := int(calibration.current_stage().candidate_index)
		var comfort := 1 if candidate_index == discomfort_candidate else 4
		var values_for_stage: Array = [90, 10, 90] if not calibration.current_stage().scored else values
		if not calibration.accept(trial_report(calibration, values_for_stage, comfort), comfort):
			expect(false, "Un passage conforme doit être accepté : " + calibration.error)
			break
	return calibration


func test_calibration() -> void:
	var calibration := CalibrationService.new()
	expect(not calibration.recommendation().apply_allowed, "Aucune recommandation ne peut précéder un protocole.")
	expect(not calibration.begin(SensitivityService.default_profile(), 0, 42, "test"), "Le format zéro doit être refusé.")
	expect(not calibration.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "../test"), "Un identifiant de calibration ne doit pas être un chemin.")
	calibration.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "test-calibration")
	expect(calibration.plan.size() == 60, "Le protocole comprend 15 familiarisations et 45 essais mesurés.")
	var cells: Dictionary = {}
	var seed_groups: Dictionary = {}
	var order_groups: Dictionary = {}
	for stage_index in calibration.plan.size():
		var stage: Dictionary = calibration.plan[stage_index]
		if stage.scored:
			var cell := "%s/%d" % [stage.scenario_id, stage.candidate_index]
			cells[cell] = int(cells.get(cell, 0)) + 1
			var pair := "%s/%d" % [stage.scenario_id, stage.repetition]
			if seed_groups.has(pair):
				expect(seed_groups[pair] == stage.seed, "La graine doit être commune aux trois réglages d'un même exercice/passage.")
			seed_groups[pair] = stage.seed
			var order_key := "%s/%d" % [stage.scenario_id, (stage_index - 15) % 3]
			if not order_groups.has(order_key):
				order_groups[order_key] = []
			order_groups[order_key].append(stage.candidate_index)
	for count in cells.values():
		expect(count == 3, "Chaque cellule scénario/réglage exige trois répétitions.")
	for candidates in order_groups.values():
		candidates.sort()
		expect(candidates == [0, 1, 2], "Chaque réglage doit occuper chaque position une fois par exercice.")
	expect(calibration.recommendation().status == "insufficient", "Des essais manquants doivent empêcher toute application.")
	var wrong := trial_report(calibration, [30, 60, 30])
	wrong.profile.dpi = 1600
	expect(not calibration.accept(wrong, 3) and calibration.current_index == 0, "Un changement de DPI ne doit pas être accepté.")
	wrong = trial_report(calibration, [30, 60, 30])
	wrong.profile.invert_y = true
	expect(not calibration.accept(wrong, 3), "Une inversion d'axe en cours de protocole doit être rejetée.")
	wrong = trial_report(calibration, [30, 60, 30])
	wrong.metrics.input_events = 0
	expect(not calibration.accept(wrong, 3), "Un passage sans mouvement doit être refait.")
	wrong = trial_report(calibration, [30, 60, 30])
	wrong.metrics.angular_path_deg = 0.0
	expect(not calibration.accept(wrong, 3), "Des événements nuls ne doivent pas simuler une activité réelle.")
	wrong = trial_report(calibration, [30, 60, 30])
	wrong.performance.max_frametime_ms = 300
	expect(not calibration.accept(wrong, 3), "Un gros freeze ne doit pas décider d'une sensibilité.")
	wrong = trial_report(calibration, [30, 60, 30])
	wrong.metrics.hits = "corrompu"
	expect(not calibration.accept(wrong, 3), "Des mesures mal typées doivent être rejetées sans exception.")
	var winner := completed_calibration([30, 60, 30])
	var result := winner.recommendation()
	expect(result.status == "indicative" and result.apply_allowed, "Un écart net et régulier doit autoriser une recommandation indicative.")
	expect(is_equal_approx(result.recommended_cm_per_360, 35) and not result.boundary_best, "Le réglage central doit gagner indépendamment des familiarisations biaisées.")
	var restored := CalibrationService.new()
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(winner.checkpoint()))
	expect(restored.restore(checkpoint), "Le checkpoint complet doit survivre à un aller-retour JSON.")
	expect(restored.recommendation().candidates == result.candidates, "La reprise doit conserver l'ensemble des mesures et du classement.")
	checkpoint.trials[0].candidate_index = 2
	expect(not restored.restore(checkpoint), "Un checkpoint avec ordre de passages altéré doit être refusé.")
	var ties := completed_calibration([50, 50, 50]).recommendation()
	expect(ties.status == "uncertain" and not ties.apply_allowed and ties.recommended_cm_per_360 == 35, "Des résultats équivalents doivent conserver la référence et proposer une plage.")
	expect(ties.range_cm_per_360[0] < 35 and ties.range_cm_per_360[1] > 35, "La plage doit inclure tous les réglages indiscernables.")
	var edge := completed_calibration([30, 40, 70]).recommendation()
	expect(edge.boundary_best and edge.apply_allowed, "Un meilleur réglage au bord doit déclencher une possibilité d'affinage.")
	var uncomfortable := completed_calibration([30, 60, 30], 1).recommendation()
	expect(uncomfortable.status == "uncomfortable" and not uncomfortable.apply_allowed, "Le confort très mauvais doit bloquer l'application automatique.")
	var weights: Array = CalibrationService.WEIGHTS.tracking
	expect(is_equal_approx(float(weights[3]) + float(weights[4]), 0.7), "L'objectif tracking doit réellement accorder 70 % aux deux suivis.")
	var noisy := completed_calibration([40, 45, 40])
	for trial in noisy.trials:
		if not trial.scored:
			continue
		var factor: float = [0.2, 1.0, 1.8][int(trial.repetition)]
		if trial.family == "tracking":
			trial.metrics.on_target_ratio *= factor
		else:
			trial.metrics.hits_per_s *= factor
	expect(noisy.recommendation().status == "uncertain", "Une forte dispersion doit bloquer un petit avantage apparent.")
	var no_signal := completed_calibration([30, 60, 30])
	for trial in no_signal.trials:
		if trial.scenario_id == "T05":
			trial.metrics.on_target_ratio = 0.0
	expect(no_signal.recommendation().status == "insufficient", "Un exercice sans signal utile ne doit pas être ignoré pour inventer un optimum.")


func test_persistence() -> void:
	var store := LocalStore.new("user://tests/" + LocalStore.new().identifier())
	var profile := SensitivityService.default_profile()
	expect(store.save_profile(profile), "Le profil doit être enregistré dans un dossier vierge.")
	profile.cm_per_360 = 40.0
	expect(store.save_profile(profile) and store.load_profile().cm_per_360 == 40.0, "Un remplacement atomique doit charger la dernière valeur.")
	expect(store.read_json(store.root_path + "/profile.json.bak").data.cm_per_360 == 35.0, "Le backup doit conserver la version précédente.")
	profile.cm_per_360 = 35.12345678912345
	expect(store.save_profile(profile) and store.load_profile().cm_per_360 == profile.cm_per_360, "La sauvegarde doit conserver toute la précision du cm/360°.")
	var engine := ScenarioEngine.new()
	engine.start(ScenarioCatalog.find("C01"), 1337, 1)
	engine.record_aim(0.1, 2, 0)
	engine.record_frame(0.01)
	engine.advance_to(1)
	var report := engine.result(profile, 16.0 / 9.0, true)
	expect(store.save_session(report), "Une séance brute valide doit être enregistrée.")
	expect(not store.save_session(report), "Une séance existante doit être immuable.")
	expect(store.sessions().size() == 1, "Le chargement doit retrouver la séance sans la dupliquer.")
	report.session_id = "../outside"
	expect(not store.save_session(report), "Un identifiant ne doit pas permettre une traversée de chemin.")
	var export_dir := store.export_sessions()
	expect(not export_dir.is_empty(), "L'export doit produire CSV et JSON.")
	var export_files := DirAccess.open(export_dir).get_files()
	expect(export_files.size() == 2, "Le dossier d'export doit contenir les deux formats.")
	for filename in export_files:
		if filename.ends_with(".csv"):
			var csv := FileAccess.open(export_dir + "/" + filename, FileAccess.READ)
			expect(csv.get_csv_line().size() == 20 and csv.get_csv_line().size() == 20, "L'en-tête CSV et les valeurs doivent garder les mêmes colonnes.")
		else:
			expect(store.read_json(export_dir + "/" + filename).data.sessions.size() == 1, "L'export JSON doit conserver les données brutes.")
	var calibration := CalibrationService.new()
	calibration.begin(profile, 16.0 / 9.0, 123, store.identifier())
	calibration.accept(trial_report(calibration, [30, 60, 30]), 3)
	expect(store.save_checkpoint(calibration.checkpoint()), "La progression partielle doit être enregistrable.")
	var restored := CalibrationService.new()
	expect(restored.restore(store.load_checkpoint()) and restored.current_index == 1, "La reprise ne doit pas refaire les passages déjà validés.")
	var finished := completed_calibration([30, 60, 30])
	finished.calibration_id = store.identifier()
	expect(store.save_checkpoint(finished.checkpoint()) and store.load_checkpoint().status == "complete", "Un checkpoint complet doit rester consultable après redémarrage.")
	var recommendation := finished.recommendation()
	expect(store.save_calibration(recommendation) and store.save_calibration(recommendation), "Revoir un bilan identique ne doit pas tenter de l'écraser.")
	var altered := recommendation.duplicate(true)
	altered.baseline.cm_per_360 = 50.0
	expect(not store.save_calibration(altered), "Un bilan final existant ne doit pas être modifié.")
	var corrupt_path := store.root_path + "/profile.json"
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	file.store_string("{corrompu")
	file.close()
	expect(store.load_profile().cm_per_360 == 35 and not store.last_error.is_empty(), "Un profil corrompu doit conduire à un défaut accompagné d'une erreur.")
	expect(not store.save_profile(profile), "Ne jamais écraser silencieusement le profil corrompu.")
	expect(FileAccess.get_file_as_string(corrupt_path) == "{corrompu", "Les octets corrompus doivent rester disponibles pour diagnostic.")


func test_progress() -> void:
	var profile := SensitivityService.default_profile()
	var definition := ScenarioCatalog.find("C01")
	var key := ScoringService.comparison_key(definition, 30, profile, 16.0 / 9.0)
	for field in ["dpi", "cm_per_360", "vertical_fov_deg", "max_fps", "accumulated_input", "invert_y"]:
		var different := profile.duplicate(true)
		if field in ["accumulated_input", "invert_y"]:
			different[field] = not bool(profile.get(field, false))
		else:
			different[field] = float(profile[field]) + 1.0
		expect(ScoringService.comparison_key(definition, 30, different, 16.0 / 9.0) != key, "Un changement de " + field + " doit séparer les historiques comparables.")
	expect(ScoringService.comparison_key(definition, 60, profile, 16.0 / 9.0) != key, "Les durées différentes ne doivent pas mélanger les tendances.")
	var values: Array[Dictionary] = []
	for sample_index in 10:
		values.append({"completed": true, "valid": true, "warmup": false, "family": "click",
			"comparison_key": key, "score": 100.0 if sample_index < 5 else 150.0,
			"created_at_utc": "%03d" % sample_index, "metrics": {"input_events": 10, "shots": 5, "angular_path_deg": 3.0}})
	var summary := ProgressService.summarize(values, key)
	expect(summary.count == 10 and summary.best == 150 and is_equal_approx(summary.change_pct, 50), "La tendance doit comparer deux groupes de cinq sans chevauchement.")
	for field in ["warmup", "completed", "valid", "comparison_key"]:
		var excluded: Dictionary = values[0].duplicate(true)
		excluded.score = 99999
		excluded[field] = true if field == "warmup" else "other" if field == "comparison_key" else false
		values.append(excluded)
	expect(ProgressService.summarize(values, key).best == 150, "Échauffements, abandons, invalides et contextes différents ne doivent pas battre les records.")
	values.resize(9)
	expect(ProgressService.summarize(values, key).change_pct == null, "Moins de dix séances ne doivent pas afficher une fausse tendance.")
