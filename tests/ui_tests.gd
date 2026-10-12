extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")
const DomainTests := preload("res://tests/domain_tests.gd")

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var app := MainScene.instantiate()
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	tree.root.add_child(app)
	await tree.process_frame
	test_navigation(app)
	test_browser(app)
	test_profile(app)
	test_resources()
	await test_feedback(app, tree)
	test_results(app)
	app.return_to_menu()
	app.queue_free()
	await tree.process_frame
	return true


func test_navigation(app: Node) -> void:
	expect(app.home.pages.size() == 6 and app.home.selected_page == 0, "Six écrans, avec l’accueil comme point d’entrée.")
	expect(app.home.brand_label.get_line_count() == 1, "La marque ne doit pas se couper lettre par lettre.")
	expect(not app.home.status_label.visible, "Aucun diagnostic technique ne doit envahir l’accueil.")
	for page_index in 6:
		app.home.nav_buttons[page_index].pressed.emit()
		var visible_pages: int = 0
		for page in app.home.pages:
			visible_pages += 1 if page.visible else 0
		expect(visible_pages == 1 and app.home.selected_page == page_index, "La navigation doit n’afficher qu’une page.")
		expect(app.home.save_button.visible == (page_index in [2, 5]), "Enregistrer reste accessible dans l’en-tête de sensibilité et des réglages.")
	app.home.show_page(2)
	expect(not app.home.distance_input.is_visible_in_tree() and not app.home.fov_input.is_visible_in_tree(), "La calibration doit cacher les unités physiques et le FOV.")
	app.home.show_page(5)
	expect(not app.home.distance_input.is_visible_in_tree(), "Les paramètres avancés sont repliés par défaut.")
	app.home.set_status("Erreur de test visible")
	expect(app.home.status_label.visible and app.home.status_label.text == "Erreur de test visible", "Une erreur reste visible sans ouvrir de détails.")
	app.home.set_status("")


func visible_card_count(browser: TrainingBrowser) -> int:
	var count: int = 0
	for card in browser.cards.values():
		count += 1 if card.visible else 0
	return count


func test_browser(app: Node) -> void:
	var browser: TrainingBrowser = app.home.browser
	app.home.show_page(1)
	expect(browser.cards.size() == 16 and visible_card_count(browser) == 16, "Les seize exercices doivent être accessibles sans liste déroulante.")
	for definition in ScenarioCatalog.DEFINITIONS:
		expect(ScenarioCopy.TITLES.has(definition.scenario_id) and ScenarioCopy.DESCRIPTIONS.has(definition.scenario_id), "Chaque exercice doit avoir un titre et une consigne en français.")
		browser.select_definition(definition)
		expect(browser.title_label.text == ScenarioCopy.title(definition) and browser.preview.definition == definition, "Le titre, l’aperçu et l’exercice à lancer doivent correspondre.")
		var thumbnail: ScenarioPreview = browser.cards[definition.scenario_id].get_child(0).get_child(0).get_child(0)
		expect(not thumbnail.is_processing(), "Les miniatures ne doivent pas simuler seize scènes en continu.")
	browser.filter_buttons[2].pressed.emit()
	expect(visible_card_count(browser) == 6 and browser.selected_definition.family == "tracking", "Le filtre Suivi doit isoler les six exercices de suivi.")
	browser.search_input.text = "aucun-exercice-correspondant"
	browser.filter_catalog()
	expect(browser.empty_label.visible and browser.start_button.disabled, "Une recherche vide ne doit pas lancer un exercice masqué.")
	browser.search_input.clear()
	browser.filter_buttons[0].pressed.emit()
	browser.select_definition(ScenarioCatalog.find("C02"))
	browser.duration_input.select(2)
	browser.start_button.pressed.emit()
	expect(app.selected_definition.scenario_id == "C02" and app.selected_duration_s == 15.0, "La carte sélectionnée et la durée choisie doivent réellement piloter le lancement.")
	app.return_to_menu()
	browser.duration_input.select(0)
	app.home.show_page(0)
	expect(not browser.preview.is_processing(), "Un aperçu masqué doit arrêter ses animations.")


func test_profile(app: Node) -> void:
	var legacy := SensitivityService.default_profile()
	for field in ["weapon_id", "sound_enabled", "sound_volume", "show_weapon", "reduced_motion"]:
		legacy.erase(field)
	expect(SensitivityService.validate_profile(legacy).is_empty(), "Les profils de la 0.1.0 restent lisibles sans migration destructive.")
	app.home.bind_profile(legacy)
	expect(app.home.weapon_id == "pulse" and app.home.volume_input.value == 45.0, "Un ancien profil reçoit les préférences visuelles par défaut.")
	for dpi in [400.0, 800.0, 64000.0]:
		app.home.dpi_input.value = dpi
		expect(app.home.distance_input.value == 35.0, "Changer les DPI déclarés ne doit pas modifier la distance de départ.")
		expect(absf(app.home.sensitivity_input.value - SensitivityService.game_sensitivity(dpi, 35.0, 0.022)) < 0.00011, "La valeur simple doit correspondre au profil physique, à l’arrondi d’affichage près.")
	app.home.bind_profile(SensitivityService.default_profile())
	app.home.sensitivity_input.value = 2.0
	expect(absf(app.home.read_profile().cm_per_360 - SensitivityService.cm_per_360(800.0, 2.0 * 0.022)) <= 0.001, "Une sensibilité saisie doit modifier réellement le réglage du moteur.")
	app.home.preset_buttons[0].pressed.emit()
	expect(app.home.distance_input.value == 50.0, "Le départ Plus lent doit appliquer une vitesse plus faible.")
	app.home.weapon_buttons[1].pressed.emit()
	app.home.volume_input.value = 25.0
	app.home.sound_input.button_pressed = false
	app.home.weapon_visible_input.button_pressed = false
	app.home.motion_input.button_pressed = true
	app.home.save_button.pressed.emit()
	var saved: Dictionary = app.store.load_profile()
	expect(saved.weapon_id == "vector" and saved.sound_volume == 25.0 and not saved.sound_enabled and not saved.show_weapon and saved.reduced_motion, "Toutes les préférences d’équipement doivent persister.")
	var context_profile := SensitivityService.default_profile()
	var context := ScoringService.comparison_key(ScenarioCatalog.find("C01"), 30.0, context_profile, 16.0 / 9.0)
	context_profile.weapon_id = "classic"
	context_profile.sound_enabled = false
	context_profile.sound_volume = 0.0
	context_profile.show_weapon = false
	context_profile.reduced_motion = true
	expect(context == ScoringService.comparison_key(ScenarioCatalog.find("C01"), 30.0, context_profile, 16.0 / 9.0), "Une arme cosmétique ne doit pas modifier la formule ou le contexte du score.")
	for invalid in [-1.0, 101.0, NAN, INF, "fort", null]:
		var broken := context_profile.duplicate(true)
		broken.sound_volume = invalid
		expect(not SensitivityService.validate_profile(broken).is_empty(), "Les volumes incohérents doivent être refusés.")
	for field in ["sound_enabled", "show_weapon", "reduced_motion", "weapon_id"]:
		var broken := context_profile.duplicate(true)
		broken[field] = "invalide"
		expect(not SensitivityService.validate_profile(broken).is_empty(), "Les préférences mal typées doivent être refusées.")
	app.home.bind_profile(SensitivityService.default_profile())


func test_resources() -> void:
	var hashes: Dictionary = {}
	for definition in WeaponCatalog.DEFINITIONS:
		expect(definition.validate().is_empty(), "Chaque arme doit fournir son sprite, son tir et sa boucle.")
		expect(definition.sprite.get_width() > 0, "Le sprite doit être une texture importée exploitable.")
		for stream in [definition.shot_sound, definition.continuous_sound]:
			expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 24000 and not stream.stereo and stream.data.size() > 0, "Les sons sont de vraies données PCM mono 16 bits à 24 kHz.")
			var hashing := HashingContext.new()
			hashing.start(HashingContext.HASH_SHA256)
			hashing.update(stream.data)
			var digest := hashing.finish().hex_encode()
			expect(not hashes.has(digest), "Chaque profil doit avoir des sons distincts.")
			hashes[digest] = true
		expect(definition.continuous_sound.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Le contrôleur ne doit pas modifier la ressource audio partagée.")
		expect(is_equal_approx(definition.continuous_sound.get_length(), 4.0 * definition.continuous_interval_s), "La boucle doit contenir exactement quatre impulsions à la cadence du profil.")
	expect(WeaponCatalog.find("arme-inconnue") == null, "Une arme inconnue ne doit pas devenir une nouvelle mécanique.")
	var broken := WeaponDefinition.new()
	expect(not broken.validate().is_empty(), "Un profil sans assets est refusé.")


func click(app: Node, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	app._input(event)


func test_feedback(app: Node, tree: SceneTree) -> void:
	app.start_practice("T01", 2.0)
	app.begin_training(Time.get_ticks_usec())
	click(app, true)
	expect(app.hud.weapon_feedback.continuous_active and app.engine.shots == 0, "Maintenir le clic en suivi déclenche uniquement un feedback continu.")
	expect(app.hud.weapon_feedback.continuous_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "La boucle doit se répéter sans création de joueurs audio.")
	expect(app.hud.weapon_feedback.continuous_player.stream.loop_end == roundi(app.hud.weapon_feedback.continuous_player.stream.get_length() * app.hud.weapon_feedback.continuous_player.stream.mix_rate), "La fin de boucle est exprimée en échantillons, pas en octets compressés.")
	click(app, false)
	expect(not app.hud.weapon_feedback.continuous_active and not app.hud.weapon_feedback.continuous_player.playing, "Relâcher le clic arrête immédiatement le son continu.")
	click(app, true)
	app.pause_test()
	expect(not app.hud.weapon_feedback.continuous_active, "La pause ne doit pas laisser un tir sonore actif.")
	app.resume_test()
	expect(not app.hud.weapon_feedback.continuous_active, "Reprendre exige un nouveau clic pour le son, pas un maintien fantôme.")
	click(app, true)
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not app.hud.weapon_feedback.continuous_active, "La perte de focus doit arrêter le son.")
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.return_to_menu()
	app.home.weapon_id = "vector"
	app.home.sound_input.button_pressed = false
	app.start_practice("C01", 2.0)
	app.begin_training(Time.get_ticks_usec())
	var shot_count: int = app.hud.weapon_feedback.shot_count
	var yaw_deg: float = app.aim_camera.yaw_deg
	click(app, true)
	click(app, false)
	app._process(0.01)
	expect(app.engine.shots == 1 and app.hud.weapon_feedback.shot_count == shot_count + 1, "Même avec Vector, une pression produit un seul tir mesuré.")
	expect(app.aim_camera.yaw_deg == yaw_deg, "Le recul visuel ne doit jamais déplacer la caméra.")
	var voices_playing: bool = false
	for player in app.hud.weapon_feedback.players:
		voices_playing = voices_playing or player.playing
	expect(not voices_playing, "Le mode silencieux ne doit pas jouer de son de tir.")
	expect(app.hud.weapon_feedback.players.size() == 4 and app.hud.weapon_feedback.get_child_count() == 5, "Le nombre de voix audio est préalloué et borné.")
	app.return_to_menu()
	app.home.bind_profile(SensitivityService.default_profile())
	app.home.show_page(5)
	app.home.weapon_preview.set_continuous(true)
	app.home.show_page(0)
	expect(not app.home.weapon_preview.continuous_active, "Changer de page arrête aussi l’écoute de démonstration.")
	await tree.process_frame


func test_results(app: Node) -> void:
	var domain := DomainTests.new()
	domain.verify = verify
	var calibration := domain.completed_calibration([30, 40, 70])
	var recommendation := calibration.recommendation()
	app.session_panel.present_recommendation(recommendation, 800.0, "Formules et diagnostics réservés aux détails.")
	expect(app.session_panel.hero_label.text == AimUI.sensitivity(SensitivityService.game_sensitivity(800.0, recommendation.recommended_cm_per_360, 0.022)), "Le bilan doit présenter une seule sensibilité conseillée à deux décimales, issue du vrai meilleur essai.")
	expect(app.session_panel.stat_values[1].text == "45", "Le bilan doit compter les passages mesurés, sans inclure les quinze familiarisations.")
	expect(app.session_panel.apply_button.visible and not app.session_panel.body_label.is_visible_in_tree(), "Le bilan doit montrer l’action utile et replier le bloc de données.")
	app.session_panel.set_notice("Sauvegarde impossible")
	expect(app.session_panel.notice_label.visible, "Une erreur de sauvegarde ne doit pas disparaître dans les mesures repliées.")
	var uncertain := domain.completed_calibration([50, 50, 50]).recommendation()
	app.session_panel.present_recommendation(uncertain, 800.0, "Égalité de test")
	expect(not app.session_panel.apply_button.visible and app.session_panel.hero_caption.text.contains("INCHANGÉ"), "Un résultat indécis garde le réglage actuel et n’offre pas d’application trompeuse.")
	app.session_panel.select_comfort(5)
	expect(app.session_panel.comfort_input.value == 5 and app.session_panel.comfort_buttons[4].button_pressed, "Le choix de confort doit fournir la note réelle au protocole.")
