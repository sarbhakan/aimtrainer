extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")

var verify: Callable


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var baseline := SensitivityService.default_profile()
	for game_id in ["cs2", "valorant"]:
		for dpi in [400.0, 800.0, 1600.0]:
			var source_value := 2.0 if game_id == "cs2" else 0.35
			var imported := GameProfileService.import_profile(baseline, game_id, dpi, source_value)
			expect(imported.error.is_empty(), "L’import d’une sensibilité de jeu usuelle doit être valide.")
			if not imported.error.is_empty():
				continue
			expect(imported.profile.dpi == baseline.dpi and imported.profile.reference_game.dpi == dpi, "Les DPI source doivent rester séparés des DPI actifs.")
			expect(SensitivityService.validate_profile(imported.profile).is_empty(), "Le profil importé doit être sauvegardable.")
			expect(absf(SensitivityService.game_sensitivity(dpi, imported.profile.cm_per_360, GameProfileService.default_yaw(game_id)) - source_value) < 0.000000001, "Jeu → AIM/LOCAL → jeu doit conserver la rotation sans arrondi intermédiaire.")
	for values in [[0.0, 1.0], [800.0, 0.0], [-800.0, 1.0], [800.0, NAN], [INF, 1.0], [800.0, 99999.0]]:
		expect(not GameProfileService.import_profile(baseline, "cs2", values[0], values[1]).error.is_empty(), "Une saisie invalide ne doit pas être convertie ou clampée silencieusement.")
	expect(not GameProfileService.import_profile(baseline, "cod", 800.0, 5.0).error.is_empty(), "CoD sans titre et distance ne doit pas inventer un coefficient.")
	var cod := GameProfileService.import_profile(baseline, "cod", 800.0, 5.0, "Modern Warfare III (2023)", 34.0)
	expect(cod.error.is_empty() and cod.profile.cm_per_360 == 34.0, "Un CoD mesuré doit reproduire la distance déclarée.")
	expect(absf(SensitivityService.game_sensitivity(800.0, 34.0, cod.profile.reference_game.yaw_deg) - 5.0) < 0.000000001, "Le coefficient dérivé doit permettre la conversion inverse du même titre et réglage.")
	var altered: Dictionary = cod.profile.duplicate(true)
	altered.reference_game.confidence = "documented"
	expect(not SensitivityService.validate_profile(altered).is_empty(), "Un profil CoD mesuré ne doit pas devenir une constante documentaire par une étiquette.")
	var cs2_custom := GameProfileService.import_profile(baseline, "cs2", 800.0, 2.0, "", 0.0, 0.0165)
	expect(cs2_custom.error.is_empty() and cs2_custom.profile.reference_game.confidence == "user_coefficient", "Un m_yaw personnalisé doit être conservé et identifié.")
	test_service_history()
	var app := MainScene.instantiate()
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	tree.root.add_child(app)
	await tree.process_frame
	app.home.show_page(2)
	expect(app.home.sensitivity_input.is_visible_in_tree(), "La sensibilité doit être directement modifiable sans ouvrir les paramètres avancés.")
	app.home.reference_import.game_input.select(1)
	app.home.reference_import.select_game()
	app.home.reference_import.dpi_input.value = 800.0
	app.home.reference_import.value_input.value = 0.35
	app.home.weapon_id = "vector"
	app.home.reference_import.apply_button.pressed.emit()
	var profile: Dictionary = app.home.read_profile()
	expect(profile.reference_game.game_id == "valorant" and profile.weapon_id == "vector", "Importer un jeu conserve les préférences et active le profil source choisi.")
	var expected_cm := 914.4 / (800.0 * 0.35 * 0.07)
	expect(absf(profile.cm_per_360 - expected_cm) < 0.000000001, "Le formulaire ne doit pas arrondir l’état canonique au cm affiché.")
	expect(absf(app.aim_camera.degrees_per_count - 0.35 * 0.07) < 0.000000001, "L’import doit appliquer immédiatement la rotation à la caméra.")
	expect(absf(app.home.conversion_value - 0.35) < 0.000000001, "La conversion inverse doit afficher la sensibilité d’origine.")
	var reloaded: Dictionary = app.store.load_profile()
	expect(reloaded.reference_game.game_id == "valorant" and absf(reloaded.cm_per_360 - expected_cm) < 0.000000001, "Le profil source et sa précision doivent survivre à la sauvegarde.")
	app.start_practice("C03", 15.0)
	expect(absf(app.aim_camera.degrees_per_count - 0.0245) < 0.000000001, "Le premier exercice doit utiliser le réglage importé, pas une valeur par défaut.")
	app.return_to_menu()
	app.import_reference_profile(cod.profile)
	expect(app.home.game_input.selected == 2 and absf(app.home.conversion_value - 5.0) < 0.000000001, "Le convertisseur CoD doit réutiliser le profil mesuré du titre source.")
	await test_form_history(app)
	test_missing_measurement(app)
	app.home.bind_profile(baseline)
	app.home.reference_import.game_input.select(1)
	app.home.reference_import.select_game()
	app.home.reference_import.dpi_input.value = 800.0
	app.home.reference_import.value_input.value = 0.35
	app.home.dpi_input.value = 1600.0
	expect(app.home.reference_import.dpi_input.value == 800.0 and app.home.reference_import.value_input.value == 0.35, "Actualiser les DPI actifs ne doit pas réinitialiser les champs du jeu source.")
	expect(app.home.reference_import.preview_label.text.contains("1600 DPI actifs conservés"), "L’aperçu doit afficher les DPI actifs conservés à jour.")
	expect(app.home.reference_import.preview_label.text.contains(AimUI.sensitivity(SensitivityService.game_sensitivity(1600.0, expected_cm, SensitivityService.APP_YAW_DEG))), "L’aperçu doit recalculer la sensibilité locale dès que les DPI actifs changent, avec deux décimales visibles.")
	app.home.reference_import.apply_button.pressed.emit()
	var distinct_profile: Dictionary = app.home.read_profile()
	expect(distinct_profile.dpi == 1600.0 and distinct_profile.reference_game.dpi == 800.0, "Modifier les DPI actifs après l’ouverture du formulaire ne doit pas les remplacer à l’import.")
	expect(absf(distinct_profile.cm_per_360 - expected_cm) < 0.000000001, "Des DPI actifs différents doivent conserver la distance du jeu source.")
	expect(absf(app.aim_camera.degrees_per_count - 0.01225) < 0.000000001, "La caméra doit utiliser les DPI actifs et non ceux du jeu source.")
	app.start_practice("C03", 15.0)
	expect(absf(app.aim_camera.degrees_per_count - 0.01225) < 0.000000001, "Le prochain exercice doit conserver les DPI actifs distincts.")
	app.return_to_menu()
	app.home.bind_profile(baseline)
	app.home.game_input.select(2)
	app.home.game_input.item_selected.emit(2)
	expect(app.home.conversion_copy_button.disabled and not SensitivityService.positive(app.home.conversion_value), "Sans profil mesuré, la conversion CoD doit rester explicitement indisponible.")
	test_rejected_imports(app, cod.profile)
	var failing_path := "user://tests/" + LocalStore.new().identifier()
	var failing_store := LocalStore.new(failing_path)
	failing_store.save_profile(baseline)
	var bad_file := FileAccess.open(failing_path.path_join("profile.json"), FileAccess.WRITE)
	bad_file.store_string(JSON.stringify({"schema_version": 999}))
	bad_file.close()
	app.store = failing_store
	var before: Dictionary = app.home.read_profile()
	var camera_before: Dictionary = camera_state(app)
	var bytes_before := FileAccess.get_file_as_bytes(failing_path.path_join("profile.json"))
	app.import_reference_profile(cod.profile)
	expect(app.home.read_profile() == before and app.home.status_label.visible, "Une sauvegarde refusée ne doit pas annoncer ou appliquer un import réussi.")
	expect(camera_state(app) == camera_before, "Une sauvegarde refusée ne doit modifier aucun paramètre de caméra.")
	expect(FileAccess.get_file_as_bytes(failing_path.path_join("profile.json")) == bytes_before, "Une sauvegarde refusée doit préserver les octets du profil existant.")
	app.queue_free()
	await tree.process_frame
	return true


func test_service_history() -> void:
	var active: Dictionary = SensitivityService.default_profile()
	active.dpi = 1600.0
	active.weapon_id = "vector"
	var original: Dictionary = active.duplicate(true)
	var imported := GameProfileService.import_profile(active, "valorant", 800.0, 0.35)
	expect(imported.error.is_empty() and imported.profile.dpi == 1600.0, "L’import doit préserver les DPI actuels du profil.")
	expect(active == original and imported.profile.weapon_id == "vector", "Le service ne doit ni muter le profil appelant ni perdre ses préférences.")
	expect(absf(SensitivityService.degrees_per_count(imported.profile.dpi, imported.profile.cm_per_360) - 0.01225) < 0.000000001, "La même distance doit produire la rotation attendue à 1600 DPI.")
	var history: Dictionary = imported.profile.reference_game.duplicate(true)
	var current: Dictionary = imported.profile.duplicate(true)
	current.cm_per_360 = 45.0
	for repeat_index in 5:
		var restored := GameProfileService.import_profile(current, "valorant", history.dpi, history.sensitivity)
		expect(restored.error.is_empty() and restored.profile.reference_game == history, "Réimporter sans édition doit conserver exactement la référence documentaire.")
		expect(restored.profile.dpi == 1600.0 and restored.profile.cm_per_360 == history.source_cm_per_360, "Réimporter doit retrouver le réglage source d’origine sans modifier les DPI actifs.")
		current = restored.profile
	var measured: Dictionary = GameProfileService.import_profile(active, "cod", 800.0, 5.012345678901234, "Modern Warfare III (2023)", 34.12345678901234)
	expect(measured.error.is_empty() and measured.profile.cm_per_360 == 34.12345678901234, "Une mesure source ne doit pas être recalculée ou arrondie.")
	var invalid_changes: Array[Dictionary] = [{"dpi": "1600"}, {"dpi": NAN}, {"cm_per_360": false}, {"vertical_fov_deg": "75"}, {"reference_game": []}]
	for change in invalid_changes:
		var invalid: Dictionary = active.duplicate(true)
		invalid.merge(change, true)
		expect(not GameProfileService.import_profile(invalid, "valorant", 800.0, 0.35).error.is_empty(), "Un profil actif invalide ne doit pas être réparé silencieusement par l’import.")


func test_form_history(app: Node) -> void:
	var active: Dictionary = SensitivityService.default_profile()
	active.dpi = 1600.0
	var imports: Array[Dictionary] = [
		GameProfileService.import_profile(active, "cs2", 800.125, 2.012345678901234, "", 0.0, 0.016500123456789),
		GameProfileService.import_profile(active, "valorant", 800.0, 0.3512345678901234),
		GameProfileService.import_profile(active, "cod", 800.0, 5.012345678901234, "Modern Warfare III (2023)", 34.12345678901234),
		GameProfileService.import_profile(active, "custom", 800.0, 4.012345678901234, "FPS personnel · version 1", 42.12345678901234),
		GameProfileService.import_profile(active, "cod", 64000.0, 100000.0, "Modern Warfare III (2023)", 149.0)
	]
	var form: SensitivityImport = app.home.reference_import
	for imported in imports:
		expect(imported.error.is_empty(), "Chaque fixture source précise doit être valide.")
		if not imported.error.is_empty():
			continue
		var history: Dictionary = imported.profile.reference_game.duplicate(true)
		var changed: Dictionary = imported.profile.duplicate(true)
		changed.cm_per_360 = 45.0
		app.home.bind_profile(changed)
		await app.get_tree().process_frame
		expect(form.dpi_input.value == history.dpi and form.value_input.value == history.sensitivity, "Réouvrir doit restaurer les DPI et la sensibilité source exacts, pas le réglage actif.")
		expect(form.measurement_input.value == history.source_cm_per_360, "Réouvrir doit restaurer la mesure historique complète, sans quantification du SpinBox.")
		expect(absf(form.value_input.get_line_edit().text.to_float() - float(history.sensitivity)) <= float(history.sensitivity) * 0.00000000000001, "Le champ doit afficher la sensibilité source précise : " + form.value_input.get_line_edit().text)
		if history.game_id in ["cod", "custom"]:
			expect(absf(form.measurement_input.get_line_edit().text.to_float() - float(history.source_cm_per_360)) <= float(history.source_cm_per_360) * 0.00000000000001, "Le champ doit afficher la mesure source précise : " + form.measurement_input.get_line_edit().text)
		if history.game_id == "cs2":
			expect(form.cs2_yaw_input.value == history.yaw_deg, "Réouvrir CS2 doit restaurer le m_yaw personnalisé exact.")
		expect(form.explanation_label.text.contains("origine"), "La réimportation du réglage source original doit être explicitement annoncée.")
		var game_index: int = GameProfileService.IDS.find(history.game_id)
		form.game_input.select((game_index + 1) % GameProfileService.IDS.size())
		form.select_game()
		form.game_input.select(game_index)
		form.select_game()
		var draft: Dictionary = form.draft()
		expect(draft.error.is_empty() and draft.profile.reference_game == history, "Changer de jeu puis revenir doit offrir la référence historique inchangée.")
		for repeat_index in 5:
			form.bind_context(draft.profile)
			draft = form.draft()
			expect(draft.error.is_empty() and draft.profile.reference_game == history, "Des réimports successifs sans édition doivent conserver tous les champs et le coefficient historique.")
		form.apply_button.pressed.emit()
		var restored: Dictionary = app.home.read_profile()
		expect(restored.dpi == active.dpi and restored.cm_per_360 == history.source_cm_per_360, "Appliquer la référence historique doit restaurer sa distance avec les DPI actifs conservés.")
		expect(restored.reference_game == history, "Le signal UI doit conserver exactement les métadonnées historiques.")
		var saved_profile: Dictionary = app.store.load_profile()
		var saved_history: Dictionary = saved_profile.reference_game
		for field in history:
			if history[field] is int or history[field] is float:
				expect(absf(float(saved_history[field]) - float(history[field])) <= absf(float(history[field])) * 0.00000000000001, "Les nombres source doivent survivre au JSON en précision flottante complète : " + str(field))
			else:
				expect(saved_history[field] == history[field], "Les métadonnées de provenance doivent rester identiques sur disque : " + str(field))
		form.bind_context(saved_profile)
		expect(form.draft().profile.reference_game == saved_history, "Réimporter une référence relue sur disque doit préserver exactement son coefficient sans le recalculer.")
		expect(absf(app.aim_camera.degrees_per_count - SensitivityService.degrees_per_count(active.dpi, history.source_cm_per_360)) < 0.000000001, "Chaque historique doit s’appliquer à la caméra avec les DPI actifs.")
		form.measurement_input.value = 36.12345678901234
		if history.game_id in ["cod", "custom"]:
			var edited: Dictionary = form.draft()
			expect(edited.error.is_empty() and edited.profile.cm_per_360 == 36.12345678901234, "Une nouvelle mesure explicite doit être utilisée sans arrondi.")
			expect(edited.profile.reference_game.yaw_deg != history.yaw_deg, "Une édition réelle doit recalculer le coefficient au lieu de forcer l’ancien historique.")


func test_missing_measurement(app: Node) -> void:
	var form: SensitivityImport = app.home.reference_import
	app.home.bind_profile(SensitivityService.default_profile())
	for game_index in [2, 3]:
		form.game_input.select(game_index)
		form.select_game()
		form.title_input.text = "Jeu test · version 1"
		expect(form.measurement_input.value == 0.0 and form.apply_button.disabled, "Sans référence source, aucune distance locale ne doit être présentée comme une mesure.")
		expect(not form.draft().error.is_empty(), "Une nouvelle mesure est obligatoire pour CoD et les jeux manuels.")
		form.measurement_input.value = -1.0
		expect(form.apply_button.disabled, "Une mesure négative doit être refusée et non transformée en valeur plausible.")
		form.measurement_input.value = 151.0
		expect(form.measurement_input.value == 151.0 and form.apply_button.disabled, "Une mesure hors limites doit être refusée et non ramenée silencieusement à 150 cm.")
		form.measurement_input.value = 34.12345678901234
		expect(not form.apply_button.disabled and form.draft().profile.cm_per_360 == 34.12345678901234, "Une vraie mesure saisie doit débloquer l’import sans quantification.")
		form.dpi_input.value = 64001.0
		expect(form.dpi_input.value == 64001.0 and form.apply_button.disabled, "Des DPI source hors limites doivent être refusés et non clampés.")
		form.dpi_input.value = 0.0
		expect(form.dpi_input.value == 0.0 and form.apply_button.disabled, "Des DPI source nuls doivent être refusés et non remplacés par un DPI plausible.")


func camera_state(app: Node) -> Dictionary:
	return {"degrees_per_count": app.aim_camera.degrees_per_count, "fov": app.aim_camera.fov,
		"invert_y": app.aim_camera.invert_y, "yaw_deg": app.aim_camera.yaw_deg, "pitch_deg": app.aim_camera.pitch_deg}


func test_rejected_imports(app: Node, valid: Dictionary) -> void:
	var requests: Array[Dictionary] = [SensitivityService.default_profile()]
	for reference in [null, false, [], "profil", {}]:
		var request: Dictionary = valid.duplicate(true)
		request.reference_game = reference
		requests.append(request)
	var invalid_changes: Array[Dictionary] = [{"game_id": 42}, {"title": 12}, {"dpi": "800"}, {"sensitivity": true}, {"yaw_deg": NAN}, {"source_cm_per_360": INF}, {"confidence": []}, {"confidence": "documented"}]
	for change in invalid_changes:
		var request: Dictionary = valid.duplicate(true)
		request.reference_game.merge(change, true)
		requests.append(request)
	var before: Dictionary = app.home.read_profile()
	var camera_before: Dictionary = camera_state(app)
	var profile_path: String = app.store.root_path.path_join("profile.json")
	var bytes_before := FileAccess.get_file_as_bytes(profile_path)
	for request in requests:
		request.dpi = 400.0
		request.cm_per_360 = 50.0
		app.import_reference_profile(request)
		expect(app.home.read_profile() == before, "Une référence absente ou malformée doit être refusée avant de modifier l’UI.")
		expect(camera_state(app) == camera_before, "Une référence absente ou malformée doit laisser la caméra intacte.")
		expect(FileAccess.get_file_as_bytes(profile_path) == bytes_before, "Une référence absente ou malformée doit être refusée avant écriture du profil.")
		expect(app.home.status_label.visible and not app.home.status_label.text.is_empty() and not app.home.status_label.text.contains("appliqué"), "Une référence refusée doit afficher l’erreur sans annoncer un succès.")
