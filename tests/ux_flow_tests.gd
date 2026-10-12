extends RefCounted

const DashboardScript := preload("res://scripts/ui/dashboard.gd")
const InterfaceTheme := preload("res://assets/ui_theme.tres")
const ApplicationScene := preload("res://scenes/app/Main.tscn")

var verify: Callable
var failures: int = 0
var quick_requests: int = 0
var guided_requests: int = 0
var quick_resumes: int = 0
var guided_resumes: int = 0
var started_id: String = ""
var started_duration_s: float = 0.0


func expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
	verify.call(condition, description)


func settle(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var original_size := tree.root.size
	var original_motion := AimUI.motion_enabled
	tree.root.size = Vector2i(1280, 720)
	var dashboard := DashboardScript.new()
	dashboard.theme = InterfaceTheme
	tree.root.add_child(dashboard)
	await settle(tree)
	var profile := SensitivityService.default_profile()
	profile.reduced_motion = true
	dashboard.bind_profile(profile)
	test_first_steps(dashboard)
	await test_exact_import(dashboard, tree)
	await test_source_focus(tree)
	test_progress(dashboard)
	test_crosshair(dashboard)
	await test_layout(dashboard, tree)
	dashboard.queue_free()
	await tree.process_frame
	tree.root.size = original_size
	AimUI.motion_enabled = original_motion
	return failures == 0


func test_first_steps(dashboard: AimDashboard) -> void:
	dashboard.training_requested.connect(func(scenario_id: String, duration_s: float) -> void:
		started_id = scenario_id
		started_duration_s = duration_s)
	dashboard.home_start_button.pressed.emit()
	expect(started_id == "C03" and started_duration_s == 30.0, "Le premier pas lance réellement une activité de 30 s depuis l’accueil.")
	dashboard.calibration_requested.connect(func() -> void: quick_requests += 1)
	dashboard.guided_calibration_requested.connect(func() -> void: guided_requests += 1)
	dashboard.calibration_resume_requested.connect(func() -> void: quick_resumes += 1)
	dashboard.guided_resume_requested.connect(func() -> void: guided_resumes += 1)
	dashboard.show_page(2)
	dashboard.guided_calibration_button.pressed.emit()
	expect(guided_requests == 1 and quick_requests == 0, "Trouver mon réglage émet uniquement le signal du parcours guidé.")
	dashboard.calibration_button.pressed.emit()
	expect(quick_requests == 1 and guided_requests == 1, "Comparer mon réglage conserve le signal rapide compatible avec le parent.")
	dashboard.guided_resume_button.pressed.emit()
	expect(guided_resumes == 1 and quick_resumes == 0, "Reprendre la recherche ne peut pas reprendre le checkpoint rapide.")
	dashboard.resume_calibration_button.pressed.emit()
	expect(quick_resumes == 1 and guided_resumes == 1, "Les reprises guidée et rapide restent indépendantes même avec deux checkpoints.")
	expect(dashboard.guided_effort_label.tooltip_text.contains("3–4") and dashboard.guided_effort_label.text.contains("51–68"), "Le parcours guidé annonce 51–68 minutes et précise 3–4 comparaisons à la demande, pas 17 minutes au total.")
	expect(dashboard.quick_effort_label.text.contains("17") and dashboard.quick_effort_label.text.contains("reprise"), "La comparaison rapide annonce son effort et sa possibilité de reprise.")
	for definition in ScenarioCatalog.DEFINITIONS:
		expect(ScenarioCopy.description(definition).length() <= 90, "Chaque activité garde une consigne courte : " + definition.scenario_id)
		expect(ScenarioCopy.measure(definition).contains("%"), "La mesure de l’activité est expliquée avec une unité compréhensible : " + definition.scenario_id)
	dashboard.show_page(0)
	expect(not dashboard.calibration_choices.visible, "Les choix de calibration ne débordent pas dans les autres destinations.")


func test_exact_import(dashboard: AimDashboard, tree: SceneTree) -> void:
	var active := SensitivityService.default_profile()
	active.dpi = 1600.0
	var imported := GameProfileService.import_profile(active, "valorant", 800.0, 0.3512345678901234)
	expect(imported.error.is_empty(), "La fixture d’import précis est valide.")
	var history: Dictionary = imported.profile.reference_game.duplicate(true)
	var changed: Dictionary = imported.profile.duplicate(true)
	changed.cm_per_360 = 45.0
	dashboard.bind_profile(changed)
	dashboard.show_page(2)
	await settle(tree)
	var form := dashboard.reference_import
	expect(form.value_input.display_input.text == "0.35", "Le champ source affiche au plus deux décimales depuis son début.")
	expect(form.dpi_input.display_input.text == "800", "Les DPI entiers ne sont pas affichés avec une décimale inutile.")
	expect(form.value_input.value == history.sensitivity and form.draft().profile.reference_game == history, "L’affichage abrégé conserve exactement la source et sa provenance.")
	expect(not form.value_input.get_line_edit().visible and form.value_input.display_input.visible, "La longue décimale interne reste cachée jusqu’à une édition explicite.")
	var before := dashboard.read_profile()
	form.value_input.display_input.grab_focus()
	dashboard.save_button.grab_focus()
	await settle(tree)
	expect(dashboard.read_profile() == before and form.draft().profile.reference_game == history, "Traverser le champ abrégé au clavier ne réinterprète pas le profil.")
	form.value_input.begin_edit()
	expect(form.value_input.get_line_edit().has_focus() and not form.value_input.display_input.visible, "Une édition explicite donne accès au nombre précis.")
	form.value_input.apply()
	form.value_input.finish_edit()
	await settle(tree)
	expect(form.value_input.value == history.sensitivity and form.draft().profile.reference_game == history, "Entrée sans modification ne réarrondit pas la référence source.")
	var restored := form.draft()
	for repeat_index in 4:
		form.bind_context(restored.profile)
		restored = form.draft()
		expect(restored.profile.reference_game == history and restored.profile.dpi == 1600.0, "Réimporter conserve la référence historique et les DPI actuels.")
	form.value_input.begin_edit()
	form.value_input.get_line_edit().text = "0.3523456789012345"
	form.value_input.apply()
	form.value_input.finish_edit()
	await settle(tree)
	expect(form.value_input.value == 0.3523456789012345, "Une nouvelle sensibilité explicite conserve tous les chiffres saisis.")
	expect(form.draft().profile.reference_game.sensitivity == 0.3523456789012345, "L’import utilise l’édition réelle et non l’ancien historique.")
	var manual := GameProfileService.import_profile(active, "custom", 800.125, 4.012345678901234, "Jeu UX · version 1", 42.12345678901234)
	dashboard.bind_profile(manual.profile)
	await settle(tree)
	expect(form.dpi_input.display_input.text == "800.12" and form.measurement_input.display_input.text == "42.12", "Les DPI fractionnaires et les centimètres restent lisibles à deux décimales sans quantifier le modèle.")
	expect(form.draft().profile.reference_game == manual.profile.reference_game, "Le coefficient mesuré du jeu manuel reste exact après affichage.")
	var storage := LocalStore.new("user://tests/ux-" + LocalStore.new().identifier())
	expect(storage.save_profile(dashboard.read_profile()), "Le profil précis se sauvegarde uniquement dans le dossier de tests isolé.")
	var loaded := storage.load_profile()
	expect(absf(float(loaded.cm_per_360) - 42.12345678901234) < 0.000000000001, "La sauvegarde ne relit pas les centimètres arrondis de l’interface.")
	form.measurement_input.value = 151.0
	await settle(tree)
	expect(form.apply_button.disabled and form.measurement_input.value == 151.0, "Une mesure hors limites reste visible et refusée, sans clamp silencieux.")
	dashboard.bind_profile(SensitivityService.default_profile())


func disk_profile_matches(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.size() != actual.size():
		return false
	for field in expected:
		if not actual.has(field):
			return false
		if expected[field] is Dictionary:
			if not actual[field] is Dictionary or not disk_profile_matches(expected[field], actual[field]):
				return false
		elif expected[field] is float or expected[field] is int:
			if not (actual[field] is float or actual[field] is int) or not is_finite(float(actual[field])):
				return false
			if absf(float(actual[field]) - float(expected[field])) > 1e-14 * maxf(1.0, absf(float(expected[field]))):
				return false
		elif expected[field] != actual[field]:
			return false
	return true


func test_source_focus(tree: SceneTree) -> void:
	var original_max_fps := Engine.max_fps
	var original_accumulated_input := Input.use_accumulated_input
	var original_auto_accept_quit := tree.auto_accept_quit
	var app := ApplicationScene.instantiate()
	app.store = LocalStore.new("/tmp/aimlocal-qa040-ux-" + LocalStore.new().identifier())
	tree.root.add_child(app)
	app.set_process(false)
	await settle(tree)
	app.window_has_focus = true
	app.home.show_page(2)
	var active := SensitivityService.default_profile()
	active.dpi = 1600.125
	active.invert_y = false
	active.goal = "tracking"
	active.max_fps = 240
	var imports: Array[Dictionary] = [
		GameProfileService.import_profile(active, "cs2", 800.125, 2.012345678901234, "", 0.0, 0.016500123456789),
		GameProfileService.import_profile(active, "cod", 800.125, 5.012345678901234, "Modern Warfare III (2023)", 34.12345678901234)
	]
	for imported in imports:
		expect(imported.error.is_empty(), "La fixture QA040-12 doit être valide avant tout focus.")
		if not imported.error.is_empty():
			continue
		var expected: Dictionary = imported.profile.duplicate(true)
		var history: Dictionary = expected.reference_game.duplicate(true)
		app.home.bind_profile(expected)
		await settle(tree)
		var form: SensitivityImport = app.home.reference_import
		var initial := form.draft()
		expect(initial.error.is_empty() and initial.get("profile", {}) == expected, "Le draft initial reste exact, avec invert_y explicite dans la fixture : " + history.game_id)
		var before_profile: Dictionary = app.home.read_profile()
		var controls: Array[SensitivityImport.ReadableSpinBox] = [form.dpi_input, form.value_input]
		var source_values: Array[float] = [history.dpi, history.sensitivity]
		var captions: Array[String] = ["800.12", "2.01" if history.game_id == "cs2" else "5.01"]
		if history.game_id == "cs2":
			form.cs2_fields.show()
			controls.append(form.cs2_yaw_input)
			source_values.append(history.yaw_deg)
			captions.append("0.0165")
		else:
			controls.append(form.measurement_input)
			source_values.append(history.source_cm_per_360)
			captions.append("34.12")
		await settle(tree)
		for field_index in controls.size():
			var control := controls[field_index]
			expect(control.step == 0.0 and control.value == source_values[field_index], "Le champ source n’est pas quantifié avant focus : %s/%d." % [history.game_id, field_index])
			expect(control.display_input.text == captions[field_index], "Le champ lisible abrège seulement l’affichage : %s/%d." % [history.game_id, field_index])
			control.display_input.grab_focus()
			await settle(tree)
			app.home.save_button.grab_focus()
			await settle(tree)
			expect(control.value == source_values[field_index] and form.draft() == initial, "Traverser l’affichage conserve exactement le draft : %s/%d." % [history.game_id, field_index])
			var observed_drafts: Array[Dictionary] = []
			var observe_change := func(_value: float) -> void: observed_drafts.append(form.draft())
			control.value_changed.connect(observe_change)
			control.begin_edit()
			await settle(tree)
			expect(control.get_line_edit().has_focus() and control.original_value == source_values[field_index], "Le vrai éditeur reçoit le focus avec son cache float exact : %s/%d." % [history.game_id, field_index])
			app.home.save_button.grab_focus()
			await settle(tree)
			control.value_changed.disconnect(observe_change)
			expect(not control.editing and control.value == source_values[field_index], "Le blur natif sans édition conserve chaque bit : %s/%d." % [history.game_id, field_index])
			expect(form.draft() == initial and app.home.read_profile() == before_profile, "Le focus ne recalcule ni canonique ni historique ni DPI actifs : %s/%d." % [history.game_id, field_index])
			expect(observed_drafts.all(func(snapshot: Dictionary) -> bool: return snapshot == initial), "Les callbacks du Range lisent déjà le draft exact : %s/%d." % [history.game_id, field_index])
		form.value_input.begin_edit()
		form.value_input.apply()
		form.value_input.finish_edit()
		await settle(tree)
		expect(form.draft() == initial, "Entrée sans édition conserve aussi le cache exact : " + history.game_id)
		form.apply_button.pressed.emit()
		await settle(tree)
		var applied: Dictionary = app.home.read_profile()
		expect(applied == expected and applied.reference_game == history, "Le vrai signal d’import conserve le profil exact en mémoire : " + history.game_id)
		expect(applied.dpi == 1600.125 and applied.reference_game.dpi == 800.125, "Les DPI actuels restent distincts des DPI historiques : " + history.game_id)
		var expected_deg_per_count := SensitivityService.degrees_per_count(expected.dpi, expected.cm_per_360)
		expect(app.aim_camera.degrees_per_count == expected_deg_per_count, "Appliquer configure exactement la caméra réelle avec les DPI actuels : " + history.game_id)
		app.aim_camera.reset_aim()
		app.aim_camera.apply_mouse_counts(Vector2(1000.0, 0.0))
		expect(app.aim_camera.yaw_deg == -1000.0 * expected_deg_per_count, "La caméra applique réellement le coefficient importé aux counts : " + history.game_id)
		var saved: Dictionary = app.store.load_profile()
		expect(app.store.last_error.is_empty() and disk_profile_matches(applied, saved), "Seul le JSON utilise la tolérance double 1e-14 ; les métadonnées restent strictes : " + history.game_id)
		expect(app.home.read_profile() == applied, "Relire le disque ne remplace pas le cache mémoire exact : " + history.game_id)
		form.bind_context(saved)
		expect(form.draft().get("profile", {}) == saved, "Réimporter le cache chargé ne recalcule pas son coefficient : " + history.game_id)
		form.bind_context(expected)
		form.value_input.begin_edit()
		form.value_input.get_line_edit().text = "2.1" if history.game_id == "cs2" else "5.1"
		form.value_input.apply()
		form.value_input.finish_edit()
		await settle(tree)
		var edited := form.draft()
		expect(edited.error.is_empty() and edited.profile.reference_game.sensitivity == (2.1 if history.game_id == "cs2" else 5.1), "Une vraie édition reste applicable malgré la protection du cache : " + history.game_id)
		expect(edited.profile.reference_game != history, "Une édition explicite utilise de nouvelles valeurs source : " + history.game_id)
	app.queue_free()
	await settle(tree)
	Engine.max_fps = original_max_fps
	Input.use_accumulated_input = original_accumulated_input
	tree.auto_accept_quit = original_auto_accept_quit


func session_fixture(scenario_id: String, key: String, identifier: String, stamp: String, score: float) -> Dictionary:
	var definition := ScenarioCatalog.find(scenario_id)
	return {"session_id": identifier, "created_at_utc": stamp, "scenario_id": scenario_id,
		"family": definition.family, "comparison_key": key, "score": score,
		"completed": true, "valid": true, "warmup": false, "active_duration_s": 30.0,
		"metrics": {"input_events": 8, "angular_path_deg": 2.0, "shots": 5, "hits": 4,
			"accuracy_fraction": 0.8, "hits_per_s": 4.0 / 30.0, "on_target_ratio": 0.75}}


func summary_fixture(scenario_id: String, key: String, sessions: Array[Dictionary]) -> Dictionary:
	var definition := ScenarioCatalog.find(scenario_id)
	var scores: Array[float] = []
	for session in sessions:
		scores.append(float(session.score))
	return {"scenario_id": scenario_id, "family": definition.family, "title": ScenarioCopy.title(definition),
		"comparison_key": key, "duration_s": 30.0, "dpi": 800.0, "cm_per_360": 35.0,
		"count": sessions.size(), "latest_score": sessions.back().score, "best": scores.max(),
		"latest_median": ScoringService.median(scores), "recent_scores": scores, "recent_sessions": sessions, "change_pct": null}


func select_activity(board: ProgressBoard, scenario_id: String) -> void:
	for index in board.activity_input.item_count:
		if board.activity_input.get_item_metadata(index) == scenario_id:
			board.activity_input.select(index)
			board.activity_input.item_selected.emit(index)
			return


func test_progress(dashboard: AimDashboard) -> void:
	var older := session_fixture("C03", "grid-context", "older", "2026-10-10T10:00:00Z", 100.0)
	var newer := session_fixture("C03", "grid-context", "newer", "2026-10-11T10:00:00Z", 120.0)
	var tracking := session_fixture("T01", "tracking-context", "tracking", "2026-10-11T11:00:00Z", 750.0)
	var grid_summary := summary_fixture("C03", "grid-context", [older, newer])
	var tracking_summary := summary_fixture("T01", "tracking-context", [tracking])
	grid_summary.recent_sessions = [ProgressService.session_row(older), ProgressService.session_row(newer)]
	tracking_summary.recent_sessions = [ProgressService.session_row(tracking)]
	var warmup := newer.duplicate(true)
	warmup.warmup = true
	var foreign := newer.duplicate(true)
	foreign.comparison_key = "another-context"
	var inactive := newer.duplicate(true)
	inactive.metrics.input_events = 0
	var invalid := newer.duplicate(true)
	invalid.valid = false
	grid_summary.recent_sessions.append_array([warmup, foreign, inactive, invalid])
	dashboard.show_history(999, [grid_summary, tracking_summary])
	var board := dashboard.progress_board
	expect(board.comparable_count == 3 and board.summary_label.text.begins_with("3 séances comparables"), "L’en-tête compte les séances comparables, pas le total des fichiers enregistrés.")
	expect(board.displayed_sessions.size() == 3 and board.displayed_sessions[0].session_id == "tracking" and board.displayed_sessions[1].session_id == "newer", "Le tableau ordonne les vrais détails fournis et exclut les autres contextes, échauffements et invalides.")
	expect(board.context_label.text.contains("30 s") and board.context_label.text.contains("800 DPI"), "La durée et les DPI de comparaison sont visibles.")
	expect(board.measurement_text(board.displayed_sessions[0]).contains("75,0 % du temps"), "Le suivi exprime le temps sur cible en pourcentage.")
	expect(board.measurement_text(board.displayed_sessions[1]).contains("80,0 % de tirs") and board.measurement_text(board.displayed_sessions[1]).contains("8 cibles/min"), "Le clic exprime précision et cibles réussies par minute, pas un taux de tirs inventé.")
	board.family_input.select(2)
	board.family_input.item_selected.emit(2)
	expect(board.comparable_count == 1 and board.displayed_summaries.size() == 1 and board.displayed_sessions[0].family == "tracking", "Le filtre de famille utilise le champ family fourni par le parent.")
	select_activity(board, "T01")
	expect(board.selected_activity == "T01" and board.displayed_sessions.size() == 1, "Le filtre d’activité isole sa chronologie.")
	dashboard.show_history(999, [grid_summary, tracking_summary])
	expect(board.selected_family == "tracking" and board.selected_activity == "T01", "Actualiser garde les filtres choisis.")
	select_activity(board, "T02")
	expect(board.comparable_count == 0 and board.empty_button.visible, "Une activité sans séance propose une première action sans inventer de résultat.")
	board.empty_button.pressed.emit()
	expect(dashboard.selected_page == 1 and dashboard.browser.selected_definition.scenario_id == "T02", "L’état vide sélectionne la bonne activité dans Entraînement.")
	board.family_input.select(0)
	board.family_input.item_selected.emit(0)
	select_activity(board, "all")
	var legacy := grid_summary.duplicate(true)
	legacy.erase("latest_score")
	legacy.erase("recent_sessions")
	dashboard.show_history(999, [legacy])
	expect(board.displayed_sessions.is_empty() and board.empty_label.text.contains("indisponible"), "Un ancien résumé sans détail ne devient pas une chronologie fabriquée.")
	dashboard.show_history(999, [grid_summary, tracking_summary])
	var chart := ScoreChart.new()
	chart.score_values = [0.0, 750.0, NAN, "score", -1.0]
	expect(chart.plot_values() == [0.0, 750.0], "La courbe accepte un vrai score nul et refuse les valeurs non finies ou incohérentes.")
	chart.free()


func test_crosshair(dashboard: AimDashboard) -> void:
	var profile := SensitivityService.default_profile()
	dashboard.bind_profile(profile)
	var default_settings := dashboard.read_profile()
	profile.merge({"crosshair_style": "t", "crosshair_size_px": 8.5, "crosshair_thickness_px": 1.5,
		"crosshair_gap_px": 3.5, "crosshair_color": "#f7b733", "crosshair_outline": true}, true)
	dashboard.bind_profile(profile)
	var settings := dashboard.read_profile()
	for field in dashboard.CROSSHAIR_FIELDS:
		expect(settings.get(field) == profile[field], "Le profil conserve le champ de viseur : " + field)
	if dashboard.crosshair_settings != null:
		expect(not dashboard.crosshair_placeholder.visible and not dashboard.crosshair_reset_button.disabled, "Le widget fourni remplace son placeholder et permet la remise à zéro.")
		var size_input := dashboard.crosshair_settings.get("size_input") as SpinBox
		size_input.value = 9.0
		expect(dashboard.read_profile().crosshair_size_px == 9.0 and dashboard.status_label.visible, "Le signal changed expose le viseur modifié au profil et indique qu’il faut enregistrer.")
		var storage := LocalStore.new("user://tests/ux-crosshair-" + LocalStore.new().identifier())
		expect(storage.save_profile(dashboard.read_profile()) and storage.load_profile().crosshair_size_px == 9.0, "Le viseur modifié persiste dans un profil de tests isolé.")
		dashboard.crosshair_reset_button.pressed.emit()
		var reset_settings := dashboard.read_profile()
		for field in dashboard.CROSSHAIR_FIELDS:
			expect(reset_settings[field] == default_settings[field], "Rétablir le viseur remet réellement la valeur par défaut : " + field)
	else:
		expect(dashboard.crosshair_placeholder.visible and dashboard.crosshair_reset_button.disabled, "L’absence du widget laisse un placeholder sans action trompeuse.")
	dashboard.bind_profile(SensitivityService.default_profile())
	dashboard.set_status("")


func test_layout(dashboard: AimDashboard, tree: SceneTree) -> void:
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		await settle(tree)
		dashboard.update_layout()
		await settle(tree)
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		dashboard.show_page(0)
		await settle(tree)
		expect(viewport_rect.encloses(dashboard.home_start_button.get_global_rect()), "Le premier lancement est visible sans défiler à %s." % dimensions)
		dashboard.show_page(1)
		await settle(tree)
		expect(viewport_rect.encloses(dashboard.browser.start_button.get_global_rect()), "Le lancement d’activité reste entièrement visible à %s." % dimensions)
		dashboard.show_page(2)
		dashboard.guided_resume_button.show()
		dashboard.resume_calibration_button.show()
		await settle(tree)
		expect(viewport_rect.encloses(dashboard.guided_calibration_button.get_global_rect()) and viewport_rect.encloses(dashboard.calibration_button.get_global_rect()), "Les deux modes restent visibles dans le viewport %s." % dimensions)
		expect(viewport_rect.encloses(dashboard.save_button.get_global_rect()), "Enregistrer reste visible dans le viewport %s." % dimensions)
		expect(viewport_rect.encloses(dashboard.guided_resume_button.get_global_rect()) and viewport_rect.encloses(dashboard.resume_calibration_button.get_global_rect()), "Les deux reprises sont visibles et distinctes à %s." % dimensions)
		expect(dashboard.reference_import.value_input.display_input.size.x >= 100.0, "Le champ source conserve une surface lisible à %s." % dimensions)
		dashboard.show_page(3)
		await settle(tree)
		expect(viewport_rect.encloses(dashboard.conversion_copy_button.get_global_rect()), "La valeur convertie et son action de copie restent visibles à %s." % dimensions)
		for page_index in [0, 2, 3, 4, 5]:
			dashboard.show_page(page_index)
			await settle(tree)
			expect(dashboard.get_combined_minimum_size().x <= dimensions.x, "Le dashboard n’impose pas de débordement horizontal à %s, page %d." % [dimensions, page_index])
			var scroll := dashboard.pages[page_index] as ScrollContainer
			expect(scroll.get_child(0).size.x <= scroll.size.x + 1.0, "Le contenu de la page %d tient dans sa largeur à %s." % [page_index, dimensions])
		if dimensions.x == 1920:
			expect(dashboard.calibration_grid.columns == 2 and dashboard.settings_grid.columns == 2 and dashboard.conversion_grid.columns == 2, "Les réglages, imports et conversions utilisent la largeur disponible.")
	dashboard.show_page(0)
