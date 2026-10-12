extends RefCounted

const DashboardScript := preload("res://scripts/ui/dashboard.gd")
const SessionScript := preload("res://scripts/ui/session_panel.gd")
const InterfaceTheme := preload("res://assets/ui_theme.tres")

var verify: Callable
var failure_count: int = 0
var progressive_requests: Array[Dictionary] = []
var progressive_resumes: int = 0
var routine_durations_s: Array[float] = []
var legacy_requests: int = 0
var next_requests: int = 0
var retry_requests: int = 0
var apply_requests: int = 0


func expect(condition: bool, description: String) -> void:
	if not condition:
		failure_count += 1
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
	test_dashboard(dashboard)
	await test_dashboard_layout(dashboard, tree)
	dashboard.queue_free()
	await settle(tree)
	var panel := SessionScript.new()
	panel.theme = InterfaceTheme
	tree.root.add_child(panel)
	await settle(tree)
	test_trial(panel)
	test_complete(panel)
	test_routine(panel)
	test_legacy(panel)
	await test_panel_layout(panel, tree)
	panel.queue_free()
	await settle(tree)
	test_scenario_copy()
	tree.root.size = original_size
	AimUI.motion_enabled = original_motion
	return failure_count == 0


func test_dashboard(dashboard: AimDashboard) -> void:
	var profile := SensitivityService.default_profile()
	profile.reduced_motion = true
	profile.cm_per_360 = 42.123456789
	dashboard.bind_profile(profile)
	var initial_profile := dashboard.read_profile().duplicate(true)
	dashboard.progressive_requested.connect(func(exploration: bool, duration_s: float) -> void:
		progressive_requests.append({"exploration": exploration, "duration_s": duration_s}))
	dashboard.progressive_resume_requested.connect(func() -> void: progressive_resumes += 1)
	dashboard.routine_requested.connect(func(duration_s: float) -> void: routine_durations_s.append(duration_s))
	dashboard.calibration_requested.connect(func() -> void: legacy_requests += 1)
	dashboard.guided_calibration_requested.connect(func() -> void: legacy_requests += 1)
	dashboard.calibration_resume_requested.connect(func() -> void: legacy_requests += 1)
	dashboard.guided_resume_requested.connect(func() -> void: legacy_requests += 1)
	dashboard.show_page(2)
	expect(dashboard.calibration_duration_input.name == "calibrationDuration" and dashboard.calibration_duration_input.item_count == 2, "La calibration expose uniquement les durées 45 et 60 s.")
	expect(dashboard.calibration_duration_input.get_selected_id() == 60 and dashboard.routine_duration_input.get_selected_id() == 60, "Calibration et entraînement complet démarrent à 60 s par essai.")
	expect(dashboard.progressive_effort_label.text.contains("25") and dashboard.progressive_effort_label.text.contains("28"), "Le parcours public annonce 25 mesures et environ 28 minutes avec pauses.")
	dashboard.progressive_button.pressed.emit()
	dashboard.progressive_exploration_button.pressed.emit()
	expect(progressive_requests == [{"exploration": false, "duration_s": 60.0}, {"exploration": true, "duration_s": 60.0}] and legacy_requests == 0, "Les actions connu et nouveau transmettent l’exploration au seul signal progressif.")
	expect(dashboard.read_profile() == initial_profile, "Démarrer un parcours émet une demande sans changer le profil ni sa précision.")
	dashboard.calibration_duration_input.select(0)
	dashboard.calibration_duration_input.item_selected.emit(0)
	dashboard.progressive_button.pressed.emit()
	dashboard.progressive_exploration_button.pressed.emit()
	expect(progressive_requests[2].duration_s == 45.0 and progressive_requests[3].duration_s == 45.0, "Les deux parcours respectent le choix de 45 s.")
	expect(dashboard.progressive_effort_label.text.contains("22"), "L’estimation d’effort suit la durée choisie.")
	expect(not dashboard.progressive_resume_button.visible, "La reprise progressive reste cachée tant que le parent ne l’active pas.")
	dashboard.progressive_resume_button.show()
	dashboard.progressive_resume_button.pressed.emit()
	expect(progressive_resumes == 1 and legacy_requests == 0, "La reprise progressive dispose de son propre signal.")
	dashboard.guided_resume_button.show()
	dashboard.resume_calibration_button.show()
	for control in [dashboard.calibration_button, dashboard.guided_calibration_button, dashboard.guided_resume_button, dashboard.resume_calibration_button]:
		expect(not control.is_visible_in_tree(), "Les commandes historiques restent absentes du parcours public, même après activation par un ancien parent.")
		control.pressed.emit()
	expect(legacy_requests == 4, "Les quatre signaux historiques restent disponibles pour relire et tester les anciens parcours.")
	for preset_index in 3:
		dashboard.preset_buttons[preset_index].pressed.emit()
		expect(dashboard.read_profile().cm_per_360 == [50.0, 35.0, 25.0][preset_index], "Les points de départ lent, moyen et rapide conservent leurs valeurs.")
		dashboard.novice_input.select(preset_index + 1)
		dashboard.novice_input.item_selected.emit(preset_index + 1)
		expect(dashboard.read_profile().cm_per_360 == [50.0, 35.0, 25.0][preset_index], "Le sélecteur novice utilise le même point de départ que les boutons existants.")
	dashboard.dpi_input.set_precise_value(1600.0)
	expect(dashboard.read_profile().dpi == 1600.0 and dashboard.read_profile().cm_per_360 == 25.0, "Les DPI saisis sont conservés sans déplacer le point de départ.")
	var imported := GameProfileService.import_profile(dashboard.read_profile(), "valorant", 800.0, 0.35123456789)
	dashboard.bind_profile(imported.profile)
	var before_import := dashboard.read_profile().duplicate(true)
	dashboard.progressive_button.pressed.emit()
	expect(dashboard.read_profile() == before_import and dashboard.reference_import != null, "L’import source et les réglages existants survivent au nouveau parcours.")
	dashboard.show_page(0)
	dashboard.routine_button.pressed.emit()
	dashboard.routine_duration_input.select(0)
	dashboard.routine_duration_input.item_selected.emit(0)
	dashboard.routine_button.pressed.emit()
	expect(routine_durations_s == [60.0, 45.0], "L’entraînement complet émet la durée choisie depuis sa carte d’accueil.")
	expect(not dashboard.calibration_choices.is_visible_in_tree(), "La calibration reste dans Ma sensibilité.")


func report_fixture(scenario_id: String = "C02") -> Dictionary:
	return {"scenario_id": scenario_id, "family": "tracking" if scenario_id.begins_with("T") else "click",
		"completed": true, "valid": true, "score": 256.0, "profile": SensitivityService.default_profile(),
		"metrics": {"hits": 40, "misses": 10, "shots": 50, "accuracy_pct": 80.0,
			"accuracy_fraction": 0.8, "on_target_ratio": 0.625, "hits_per_s": 40.0 / 60.0}}


func history_fixture() -> Array:
	var history: Array = []
	for trial_index in 5:
		history.append({"sensitivity": 1.0 + float(trial_index) * 0.25, "score": 200.0 + trial_index,
			"hits": 40 + trial_index, "misses": 10, "accuracy_pct": 80.0,
			"on_target_ratio": 0.625, "utility": 0.42 + float(trial_index) * 0.01})
	return history


func context_fixture() -> Dictionary:
	return {"block_index": 2, "trial_index": 3, "total_trials": 25, "completed_trials": 13,
		"scenario_id": "C02", "title": "Micro-précision", "active_sensitivity": 1.75,
		"direction": "affinage", "block_history": history_fixture()}


func summary_fixture() -> Dictionary:
	var blocks: Array = []
	for scenario_id in ["C02", "C04", "S01", "T01", "T05"]:
		var trials: Array = []
		for trial_index in 5:
			var report := report_fixture(scenario_id)
			report.profile.cm_per_360 = 35.0 + trial_index
			trials.append(report)
		blocks.append({"scenario_id": scenario_id, "title": ScenarioCopy.TITLES[scenario_id], "trials": trials,
			"moving_range_cm": [32.0, 39.0]})
	return {"protocol_version": 4, "calibration_id": "presentation-test", "baseline": SensitivityService.default_profile(),
		"recommended_cm_per_360": 32.0, "recommended_sensitivity": 1.623456789,
		"tested_trials": 25, "blocks": blocks, "status": "complete", "apply_allowed": true}


func test_trial(panel: SessionPanel) -> void:
	panel.next_requested.connect(func() -> void: next_requests += 1)
	panel.retry_requested.connect(func() -> void: retry_requests += 1)
	panel.apply_requested.connect(func() -> void: apply_requests += 1)
	var report := report_fixture()
	var trial_context := context_fixture()
	var initial_report := report.duplicate(true)
	var initial_context := trial_context.duplicate(true)
	panel.present_progressive_trial(report, "Calculs et mesures", trial_context)
	expect(not panel.comfort_row.visible and not panel.guided_confirmation.visible, "Un essai progressif ne demande aucune note de confort ni confirmation subjective.")
	expect(panel.next_button.visible and not panel.next_button.disabled and panel.retry_button.visible, "Un seul Continuer et un Rejouer pour erreur sont disponibles immédiatement.")
	expect(not panel.apply_button.visible and not panel.refine_button.visible, "Un essai intermédiaire ne propose pas d’application ou d’affinage manuel.")
	expect(panel.badge_label.text.contains("3 / 5") and panel.badge_label.text.contains("4 / 5") and panel.progress.value == 13.0 and panel.progress.max_value == 25.0, "Indices de bloc et d’essai deviennent des repères humains, avec la progression réelle.")
	expect(panel.subtitle_label.text.contains("1,75") and panel.subtitle_label.text.contains("affinage"), "La sensibilité active et la direction viennent du contexte.")
	expect(panel.stat_titles[0].text == "Touches / ratés" and panel.stat_values[0].text == "40 / 10" and panel.stat_values[1].text == "80,0 %" and panel.stat_titles[2].text == "Durée mesurée", "Le clic affiche touches, ratés, précision et durée, pas un suivi sans signification.")
	expect(panel.progressive_history_grid.columns == 5 and panel.progressive_history_grid.get_child_count() == 5, "Les cinq sensibilités occupent cinq colonnes distinctes.")
	expect(labels_text(panel.progressive_history_grid).contains("Score 204") and labels_text(panel.progressive_history_grid).contains("2,00"), "L’historique expose les vraies valeurs et les scores des candidats.")
	expect(not panel.details_toggle.button_pressed and not panel.body_label.is_visible_in_tree(), "Les mesures et calculs restent repliés par défaut.")
	panel.next_button.pressed.emit()
	panel.retry_button.pressed.emit()
	expect(next_requests == 1 and retry_requests == 1 and apply_requests == 0, "Les actions utilisent les signaux existants sans appliquer un réglage.")
	expect(report == initial_report and trial_context == initial_context, "L’API de présentation ne modifie aucun rapport ou contexte du parent.")
	trial_context.block_history = []
	panel.present_progressive_trial(report, "", trial_context)
	expect(labels_text(panel.progressive_history_grid).count("À venir") == 5, "Les cinq emplacements restent visibles avant le premier candidat accepté.")
	var tracking := report_fixture("T01")
	tracking.metrics.accuracy_pct = null
	tracking.metrics.hits = 0
	tracking.metrics.misses = 0
	panel.present_progressive_trial(tracking, "", context_fixture())
	expect(panel.stat_values[0].text == "62,5 %" and panel.stat_titles[1].text == "Suivi réussi" and panel.stat_titles[2].text == "Écart moyen", "Un suivi montre temps sur cible, secondes et écart, pas des tirs facultatifs à zéro.")
	for direction in ["départ", "plus rapide", "plus lent", "affinage"]:
		trial_context.direction = direction
		panel.present_progressive_trial(report, "", trial_context)
		expect(panel.subtitle_label.text.contains(direction), "La direction de recherche est affichée sans être recalculée.")
	report.valid = false
	report.invalid_reason = "Perte de mesure"
	panel.present_progressive_trial(report, "", trial_context)
	expect(panel.next_button.disabled and panel.retry_button.visible and panel.notice_label.text.contains("Perte de mesure"), "Une mesure invalide propose de rejouer et empêche sa validation visuelle.")
	report.valid = true
	report.completed = false
	panel.present_progressive_trial(report, "", trial_context)
	expect(panel.next_button.disabled and panel.notice_label.visible, "Un essai interrompu ne se présente pas comme une mesure terminée.")


func test_complete(panel: SessionPanel) -> void:
	var summary := summary_fixture()
	var initial_summary := summary.duplicate(true)
	panel.present_progressive_complete(summary, 1600.0, "Formule et valeurs brutes")
	expect(panel.hero_caption.text == "Votre sensibilité" and panel.hero_label.text == "1,62", "Le bilan affiche une unique sensibilité, issue de la valeur canonique du service.")
	expect(panel.apply_button.visible and not panel.apply_button.disabled and panel.apply_button.text == "Appliquer", "Un bilan complet autorisé propose directement Appliquer.")
	expect(not panel.next_button.visible and not panel.retry_button.visible and not panel.refine_button.visible and not panel.comfort_row.visible, "Le bilan progressif abandonne les actions des protocoles historiques.")
	expect(not panel.notice_label.visible and not panel.guided_confirmation.visible, "Aucun avertissement de bord de plage ni consentement confort ne détourne le bilan.")
	expect(panel.stat_values[0].text == "5" and panel.stat_values[1].text == "25" and panel.stat_values[2].text == "1600 DPI", "Le bilan présente les cinq blocs, les 25 essais et les DPI transmis.")
	expect(not panel.details_content.visible, "Les calculs, utilités et intervalles sont initialement repliés.")
	panel.details_toggle.button_pressed = true
	expect(panel.details_content.visible and labels_text(panel.details_content).contains("32,00–39,00 cm/360°") and labels_text(panel.details_content).contains("Utilités"), "Les détails donnent accès aux intervalles et utilités sans avertissement public.")
	expect(labels_text(panel.details_content).contains(AimUI.sensitivity(SensitivityService.game_sensitivity(800.0, 35.0, SensitivityService.APP_YAW_DEG))), "Les rapports standards des blocs affichent la sensibilité de leur propre profil.")
	panel.apply_button.pressed.emit()
	expect(apply_requests == 1 and summary == initial_summary, "Appliquer émet seulement la demande et préserve le bilan fourni par le parent.")
	panel.present_progressive_complete(summary, 800.0, "")
	expect(not panel.details_content.visible and panel.details_content.get_child_count() == 21, "Revoir un bilan replie ses détails sans dupliquer les blocs.")
	summary.apply_allowed = false
	panel.present_progressive_complete(summary, 800.0, "")
	expect(not panel.apply_button.visible, "Le parent peut interdire l’application via son contrat.")


func test_routine(panel: SessionPanel) -> void:
	var reports: Array = [report_fixture("M01"), report_fixture("T10"), report_fixture("S02")]
	var initial_reports := reports.duplicate(true)
	panel.present_routine_complete(reports, "Mesures de routine")
	expect(panel.hero_label.text == "3 / 3" and panel.title_label.text == "Entraînement complet", "Le bilan confirme les trois étapes terminées.")
	var body := labels_text(panel.context)
	expect(body.contains(ScenarioCopy.TITLES.M01) and body.contains(ScenarioCopy.TITLES.T10) and body.contains(ScenarioCopy.TITLES.S02) and body.count("Score 256") == 3, "Les résultats restent séparés pour M01, T10 et S02, sans score artificiellement agrégé.")
	expect(body.contains("Temps sur cible : 62,5 %") and not panel.apply_button.visible and not panel.next_button.visible and not panel.comfort_row.visible, "La routine conserve ses mesures de suivi sans commande de calibration.")
	expect(reports == initial_reports and panel.details_content.get_child_count() == 1, "La routine préserve les rapports et nettoie les anciens détails de calibration.")
	reports[2].completed = false
	panel.present_routine_complete(reports, "")
	expect(panel.hero_label.text == "2 / 3" and labels_text(panel.context).contains("Étape interrompue"), "Une étape interrompue ne devient pas une routine intégralement terminée.")


func test_legacy(panel: SessionPanel) -> void:
	panel.present_result(report_fixture(), "Ancien essai", true, 1, 60)
	expect(panel.comfort_row.visible and panel.next_button.disabled and panel.progress.max_value == 60.0, "L’ancienne API de résultat garde ses champs et sa signature de calibration.")
	panel.present_recommendation({"status": "indicative", "recommended_cm_per_360": 35.0,
		"apply_allowed": true, "candidates": []}, 800.0, "Ancien bilan")
	expect(panel.apply_button.visible and panel.apply_button.text == "Utiliser ce réglage", "Les anciennes recommandations restent consultables avec leur comportement historique.")
	panel.present_progressive_trial(report_fixture(), "Nouveau passage", context_fixture())
	expect(not panel.comfort_row.visible and not panel.details_content.visible and not panel.apply_button.visible, "Le passage de l’historique au protocole progressif nettoie l’état précédent.")


func labels_text(parent: Node) -> String:
	var result: String = parent.text + "\n" if parent is Label else ""
	for child in parent.get_children():
		result += labels_text(child)
	return result


func test_scenario_copy() -> void:
	for scenario_id in ["M01", "T10", "C03", "S02"]:
		var definition := ScenarioDefinition.new()
		definition.scenario_id = scenario_id
		expect(ScenarioCopy.title(definition) == ScenarioCopy.TITLES[scenario_id] and ScenarioCopy.description(definition).length() <= 90, "Chaque étape récente possède un titre et une consigne courts : " + scenario_id)
	expect(not ScenarioCopy.TITLES.C03.to_lower().contains("grille") and not ScenarioCopy.DESCRIPTIONS.C03.to_lower().contains("grille"), "C03 présente des multicibles réparties plutôt qu’une ancienne grille.")
	expect(ScenarioCopy.DESCRIPTIONS.M01.contains("petits") and ScenarioCopy.DESCRIPTIONS.M01.contains("grands"), "La consigne de M01 décrit les deux amplitudes du flick mixte.")


func test_dashboard_layout(dashboard: AimDashboard, tree: SceneTree) -> void:
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		dashboard.show_page(2)
		await settle(tree)
		var scroll := dashboard.pages[2] as ScrollContainer
		expect(scroll.get_child(0).size.x <= scroll.size.x + 1.0, "La page progressive reste dans la largeur disponible à %s." % dimensions)
		dashboard.progressive_exploration_button.grab_focus()
		await settle(tree)
		expect(scroll.get_global_rect().encloses(dashboard.progressive_exploration_button.get_global_rect()), "Le focus révèle l’action novice dans les petites fenêtres à %s." % dimensions)
		dashboard.show_page(0)
		dashboard.routine_button.grab_focus()
		await settle(tree)
		expect(dashboard.home_scroll.get_global_rect().encloses(dashboard.routine_button.get_global_rect()), "L’entraînement complet est accessible au clavier à %s." % dimensions)


func test_panel_layout(panel: SessionPanel, tree: SceneTree) -> void:
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		tree.root.size = dimensions
		panel.present_progressive_trial(report_fixture(), "Calculs", context_fixture())
		await settle(tree)
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		expect(viewport_rect.encloses(panel.next_button.get_global_rect()) and viewport_rect.encloses(panel.retry_button.get_global_rect()), "Continuer et Rejouer restent visibles à %s." % dimensions)
		expect(panel.result_grid.size.x <= panel.result_scroll.size.x + 1.0 and panel.progressive_history_grid.columns == 5, "Les cinq colonnes tiennent sans débordement à %s." % dimensions)
		panel.present_progressive_complete(summary_fixture(), 800.0, "Calculs")
		panel.details_toggle.button_pressed = true
		await settle(tree)
		expect(viewport_rect.encloses(panel.apply_button.get_global_rect()) and panel.result_grid.size.x <= panel.result_scroll.size.x + 1.0, "Appliquer reste visible même lorsque les mesures sont dépliées à %s." % dimensions)
