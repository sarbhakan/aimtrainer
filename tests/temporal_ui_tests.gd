extends SceneTree

const InterfaceTheme := preload("res://assets/ui_theme.tres")
const DIMENSIONS: Array[Vector2i] = [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Temporal UI : délai de test dépassé.")
		quit(1))
	run_tests.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func settle() -> void:
	for frame_index in 5:
		await process_frame


func counted_report(scenario_id: String, practice: bool = true, hits_count: int = 4, shots_count: int = 5, explicit_definition: ScenarioDefinition = null) -> Dictionary:
	var definition := explicit_definition if explicit_definition != null else ScenarioCatalog.find_practice(scenario_id) if practice else ScenarioCatalog.find(scenario_id)
	var engine := ScenarioEngine.new()
	check(engine.start(definition, 1337, 60.0), "Le moteur accepte la définition du bilan : " + scenario_id)
	for action_index in shots_count:
		var time_s: float = float(action_index + 1) * 0.1
		engine.record_aim(time_s, float(action_index + 1), 0.0)
		engine.record_frame(1.0 / 144.0)
		engine.advance_to(time_s)
		if definition.family != "tracking":
			engine.shoot(time_s, engine.target_direction(0, time_s) if action_index < hits_count else Vector3.BACK)
	engine.advance_to(60.0)
	var report: Dictionary = engine.result(SensitivityService.default_profile(), 16.0 / 9.0, true)
	check(ScoringService.validate_result(report).is_empty(), "Le bilan compté est cohérent : " + ScoringService.validate_result(report))
	return report


func labels_text(parent: Node) -> String:
	var text: String = parent.text + "\n" if parent is Label else ""
	for child in parent.get_children():
		text += labels_text(child)
	return text


func previews(parent: Node) -> Array[ScenarioPreview]:
	var found: Array[ScenarioPreview] = []
	for child in parent.get_children():
		if child is ScenarioPreview:
			found.append(child)
		found.append_array(previews(child))
	return found


func history_fixture(report: Dictionary) -> Array:
	var history: Array = []
	for trial_index in 5:
		var candidate: Dictionary = report.duplicate(true)
		candidate.profile.cm_per_360 += trial_index
		if trial_index % 2 == 1:
			candidate = {"family": report.family, "score_version": report.score_version, "score": report.score,
				"sensitivity": 1.0 + float(trial_index) * 0.25, "hits": report.metrics.hits,
				"misses": report.metrics.misses, "targets_expired": report.metrics.targets_expired,
				"accuracy_pct": report.metrics.accuracy_pct, "on_target_ratio": report.metrics.on_target_ratio}
			if report.score_version == 2:
				candidate.effective_accuracy_pct = report.metrics.effective_accuracy_pct
		history.append(candidate)
	return history


func trial_context(report: Dictionary) -> Dictionary:
	return {"scenario_id": report.scenario_id, "block_index": 0, "trial_index": 4,
		"completed_trials": 5, "total_trials": 25, "active_sensitivity": 1.623456789,
		"direction": "affinage", "block_history": history_fixture(report)}


func summary_fixture() -> Dictionary:
	var blocks: Array = []
	var calibration := ProgressiveCalibrationService.new()
	check(calibration.begin(SensitivityService.default_profile(), 16.0 / 9.0, 42, "temporal-ui-summary") and calibration.protocol_version == 6, "Les rapports du bilan utilisent les difficultés du protocole 6.")
	for scenario_id in ProgressiveCalibrationService.SCENARIOS:
		var report: Dictionary = counted_report(scenario_id, true, 4, 5, calibration.definition_for(scenario_id))
		blocks.append({"scenario_id": scenario_id, "trials": history_fixture(report)})
	return {"protocol_version": calibration.protocol_version, "recommended_sensitivity": 1.623456789,
		"tested_trials": 25, "blocks": blocks, "status": "complete", "apply_allowed": true}


func run_tests() -> void:
	var original_size := root.size
	var original_motion: bool = AimUI.motion_enabled
	AimUI.motion_enabled = false
	var click: Dictionary = counted_report("C02")
	var tracking: Dictionary = counted_report("T01")
	var switching: Dictionary = counted_report("S02")
	var legacy: Dictionary = counted_report("C02", false)
	test_insights(click, tracking, legacy)
	await test_dashboard()
	await test_panels(click, tracking, switching, legacy)
	root.size = original_size
	AimUI.motion_enabled = original_motion
	print("TEMPORAL UI : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func test_insights(click: Dictionary, tracking: Dictionary, legacy: Dictionary) -> void:
	var original: Dictionary = click.duplicate(true)
	var insights: Dictionary = PerformanceInsights.analyze(click)
	var attempts: int = int(click.metrics.shots) + int(click.metrics.targets_expired)
	var success_pct: float = 100.0 * float(click.metrics.hits) / attempts
	var expected_score: float = round(1000.0 * float(click.metrics.hits_per_s) * pow(success_pct / 100.0, 2.0) / float(click.reference_hits_s))
	check(click.score_version == 2 and click.score == expected_score, "Le score V2 affiché provient des tirs, touches et expirations comptés.")
	check(click.metrics.shots == 5 and click.metrics.hits == 4 and click.metrics.misses == 1 and click.metrics.targets_expired > 0, "Les expirations ne modifient aucun compteur de tir.")
	check(insights.primary_label == "Touches" and insights.primary_value == "4", "Le bilan V2 expose les touches.")
	check(insights.secondary_label == "Ratées" and insights.secondary_value == str(1 + int(click.metrics.targets_expired)), "Les ratées additionnent les tirs manqués et les expirations.")
	check(insights.tempo_label == "Réussite" and insights.tempo_value == PerformanceInsights.display(success_pct, 1, "%"), "La réussite utilise tirs + expirations sans arrondir le calcul.")
	check(insights.measurements.accuracy_pct.value == 80.0 and insights.measurements.effective_accuracy_pct.value == success_pct, "Précision des tirs et réussite V2 restent distinctes.")
	check(insights.tip.contains("tirs manqués") and insights.tip.contains("cibles expirées") and click == original, "L’explication conserve le bilan canonique.")
	var optional: Dictionary = click.metrics.duplicate(true)
	optional.erase("failed_actions")
	optional.erase("effective_accuracy_pct")
	check(PerformanceInsights.failed_actions(optional) == 1 + int(optional.targets_expired) and PerformanceInsights.effective_accuracy_pct(optional) == success_pct, "Les valeurs dérivées facultatives sont calculables depuis les compteurs bruts.")
	check(PerformanceInsights.effective_accuracy_pct({"hits": 0, "shots": 0, "targets_expired": 3}) == 0.0 and PerformanceInsights.effective_accuracy_pct({"hits": 0, "shots": 0, "targets_expired": 0}) == null, "Sans tir, des expirations donnent zéro réussite ; sans action, la mesure reste indisponible.")
	var old_insights: Dictionary = PerformanceInsights.analyze(legacy)
	check(legacy.score_version == 1 and old_insights.primary_label == "Précision" and old_insights.primary_value == "80,0 %" and old_insights.secondary_value == "4 / 5", "Les résultats V1 conservent leurs mesures historiques.")
	check(not old_insights.measurements.has("effective_accuracy_pct") and legacy.score == round(1000.0 * float(legacy.metrics.hits_per_s) * 0.64 / float(legacy.reference_hits_s)), "L’explication et le score V1 ne sont pas requalifiés en V2.")
	var tracking_insights: Dictionary = PerformanceInsights.analyze(tracking)
	check(tracking.score_version == 1 and tracking_insights.primary_label == "Temps sur cible" and tracking.metrics.shots == 0 and tracking.metrics.misses == 0 and tracking.metrics.targets_expired > 0, "Le tracking garde le score V1 et ses remplacements planifiés ne deviennent pas des ratés.")
	var replay: Variant = JSON.parse_string(JSON.stringify(click))
	check(replay is Dictionary and replay.score == click.score and PerformanceInsights.analyze(replay).tempo_value == insights.tempo_value, "La relecture JSON préserve le score arrondi et la réussite affichée depuis les mesures.")


func test_dashboard() -> void:
	var dashboard := AimDashboard.new()
	dashboard.theme = InterfaceTheme
	root.add_child(dashboard)
	await settle()
	check(dashboard.browser.cards.size() == 18 and ScenarioCatalog.DEFINITIONS.size() == 18, "Le catalogue public conserve les 18 identifiants.")
	for preview in previews(dashboard):
		if preview.definition == null:
			continue
		var expected := ScenarioCatalog.find_practice(preview.definition.scenario_id)
		check(preview.definition.fingerprint() == expected.fingerprint() and preview.engine.definition.fingerprint() == expected.fingerprint(), "Chaque aperçu public utilise exactement la variante de pratique : " + expected.scenario_id)
	var profile: Dictionary = dashboard.read_profile()
	dashboard.show_page(2)
	check(not dashboard.goal_input.is_visible_in_tree() and dashboard.goal_input.item_count == 3 and dashboard.read_profile().goal == profile.goal, "La priorité legacy reste dans l’API et disparaît du parcours progressif.")
	check(dashboard.calibration_duration_input.get_selected_id() == 60 and dashboard.progressive_effort_label.text.contains("25"), "La calibration conserve cinq activités, cinq essais et 60 s par défaut.")
	var protocol_copy: String = labels_text(dashboard.protocol_grid)
	var calibration := ProgressiveCalibrationService.new()
	check(calibration.begin(profile, 16.0 / 9.0, 42, "temporal-ui-current"), "La présentation utilise le protocole de calibration courant.")
	for scenario_id in ProgressiveCalibrationService.SCENARIOS:
		var definition := calibration.definition_for(scenario_id)
		check(protocol_copy.contains(ScenarioCopy.description(definition)), "Les consignes de calibration correspondent au protocole courant : " + scenario_id)
	for dimensions in DIMENSIONS:
		root.size = dimensions
		dashboard.show_page(0)
		await settle()
		check(dashboard.home_scroll.get_child(0).size.x <= dashboard.home_scroll.size.x + 1.0, "L’accueil tient en largeur à " + str(dimensions))
		for scenario_id in dashboard.home_cards:
			var anchor: Control = dashboard.home_cards[scenario_id]
			AimUI.ensure_control_visible(dashboard.home_scroll, anchor)
			await settle()
			var definition := ScenarioCatalog.find_practice(scenario_id)
			dashboard.show_home_preview(definition, anchor)
			await settle()
			check(dashboard.home_preview_popup.preview.definition.fingerprint() == definition.fingerprint() and dashboard.home_preview_popup.description_label.text == ScenarioCopy.description(definition), "La bulle d’accueil décrit la variante animée à " + str(dimensions))
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1.0).encloses(dashboard.home_preview_popup.get_global_rect()), "La bulle d’accueil tient dans la fenêtre à " + str(dimensions))
			dashboard.dismiss_home_preview()
		dashboard.show_page(1)
		var definition := ScenarioCatalog.find_practice("S02")
		dashboard.browser.select_definition(definition)
		dashboard.browser.show_card_preview(definition)
		await settle()
		check(dashboard.browser.preview.definition == definition and dashboard.browser.preview_popup.preview.definition == definition, "Sélection et bulle de navigateur montrent la même variante.")
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1.0).encloses(dashboard.browser.preview_popup.get_global_rect()), "La bulle du navigateur tient dans la fenêtre à " + str(dimensions))
		dashboard.show_page(2)
		await settle()
		var calibration_scroll := dashboard.pages[2] as ScrollContainer
		check(calibration_scroll.get_child(0).size.x <= calibration_scroll.size.x + 1.0, "La calibration tient en largeur à " + str(dimensions))
	dashboard.queue_free()
	await settle()


func test_panels(click: Dictionary, tracking: Dictionary, switching: Dictionary, legacy: Dictionary) -> void:
	var summary: Dictionary = summary_fixture()
	var boundary: Dictionary = counted_report("C03", false, 27, 30)
	var unrounded_score: float = 1000.0 * float(boundary.metrics.hits_per_s) * pow(float(boundary.metrics.accuracy_fraction), 2.0) / float(boundary.reference_hits_s)
	check(absf(unrounded_score - 121.5) < 0.000000001 and boundary.metrics.hits == 27 and boundary.metrics.shots == 30, "La fixture de demi-point vient de 27 touches réellement comptées sur 30 tirs.")
	var panel := SessionPanel.new()
	panel.theme = InterfaceTheme
	root.add_child(panel)
	await settle()
	for dimensions in DIMENSIONS:
		root.size = dimensions
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1.0)
		for report in [click, switching, tracking]:
			panel.present_progressive_trial(report, "Mesures comptées", trial_context(report))
			await settle()
			check(panel.hero_label.text == PerformanceInsights.display(report.score, 0) and not panel.comfort_row.visible, "Le bilan progressif affiche son vrai score sans confort à " + str(dimensions))
			check(panel.expiration_label.is_visible_in_tree() and not panel.details_content.visible, "Les expirations restent lisibles lorsque les mesures détaillées sont repliées.")
			var candidate_text: String = labels_text(panel.progressive_history_grid)
			if report.family == "tracking":
				check(candidate_text.contains("Sur cible") and not candidate_text.contains("Ratées") and not candidate_text.contains("Touches"), "Les candidats tracking présentent uniquement leur mesure de suivi.")
				check(panel.expiration_label.text.contains("remplacées") and panel.stat_titles[0].text == "Temps sur cible", "Les échéances tracking sont des remplacements.")
			else:
				check(panel.stat_titles[0].text == "Touches" and panel.stat_titles[1].text == "Ratées" and panel.stat_titles[2].text == "Réussite", "Touches, ratées et réussite restent les trois mesures principales.")
				check(panel.result_scroll.get_global_rect().grow(1.0).encloses(panel.expiration_label.get_global_rect()), "Le détail des expirations est visible sans ouvrir les mesures ni faire défiler à %s : détail %s, zone %s." % [dimensions, panel.expiration_label.get_global_rect(), panel.result_scroll.get_global_rect()])
				check(candidate_text.contains("Ratées") and candidate_text.contains("expirées") and candidate_text.contains("Réussite") and not candidate_text.contains("Sur cible"), "Chaque candidat de clic ou transitions expose échecs, expirations et réussite.")
				for card in panel.progressive_history_grid.get_children():
					var text: String = labels_text(card)
					check(text.contains("Ratées " + PerformanceInsights.display(PerformanceInsights.failed_actions(report.metrics), 0)) and text.contains("expirées " + str(report.metrics.targets_expired)) and text.contains("Réussite " + PerformanceInsights.display(report.metrics.effective_accuracy_pct, 1, "%")), "Chaque historique brut ou imbriqué conserve les valeurs exactes.")
			check(panel.result_grid.size.x <= panel.result_scroll.size.x + 1.0 and panel.progressive_history_grid.get_child_count() == 5, "Les cinq candidats tiennent sans débordement à " + str(dimensions))
			check(bounds.encloses(panel.next_button.get_global_rect()) and bounds.encloses(panel.retry_button.get_global_rect()), "Continuer et Rejouer restent visibles à " + str(dimensions))
		panel.present_result(click, "", false, 0, 0)
		await settle()
		check(panel.stat_titles[2].text == "Réussite" and previews(panel.context)[0].definition.fingerprint() == click.scenario_fingerprint, "Le résultat libre et son prochain aperçu correspondent au scénario mesuré.")
		panel.present_routine_complete([click, tracking, switching], "")
		await settle()
		check(labels_text(panel.context).contains("réussite") and labels_text(panel.context).contains("cibles expirées") and panel.result_grid.size.x <= panel.result_scroll.size.x + 1.0, "La routine sépare ses mesures et conserve les expirations à " + str(dimensions))
		panel.present_progressive_trial(legacy, "Archive", trial_context(legacy))
		await settle()
		check(panel.stat_titles[0].text == "Touches / ratés" and panel.stat_values[1].text == "80,0 %" and not panel.expiration_label.visible, "Un ancien résultat progressif V1 conserve sa présentation.")
		panel.present_result(boundary, "Archive arrondie", false, 0, 0)
		await settle()
		check(panel.hero_label.text == PerformanceInsights.display(boundary.score, 0) and previews(panel.context)[0].definition.fingerprint() == boundary.scenario_fingerprint, "Le score au demi-point et l’aperçu legacy restent ceux du rapport enregistré.")
		panel.present_progressive_complete(summary, 800.0, "Mesures comptées")
		panel.details_toggle.button_pressed = true
		await settle()
		check(panel.progress.value <= 25.0 and panel.hero_label.text == "1,62" and labels_text(panel.details_content).contains("Réussite") and labels_text(panel.details_content).contains("Sur cible"), "Le bilan final présente les cinq familles de mesures et la sensibilité retenue.")
		check(panel.result_grid.size.x <= panel.result_scroll.size.x + 1.0 and bounds.encloses(panel.apply_button.get_global_rect()), "L’historique final déplié tient en largeur et Appliquer reste accessible à " + str(dimensions))
	panel.queue_free()
	await settle()
