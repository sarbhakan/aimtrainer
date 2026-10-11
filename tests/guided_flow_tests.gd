extends RefCounted

const MainScene := preload("res://scenes/app/Main.tscn")
const DomainTests := preload("res://tests/domain_tests.gd")

var verify: Callable

class FailingGuidedStore extends LocalStore:
	var reject_guided: bool = false

	func save_guided_checkpoint(data: Dictionary) -> bool:
		if reject_guided:
			last_error = "Écriture guidée refusée pour le test."
			return false
		return super.save_guided_checkpoint(data)


func expect(condition: bool, description: String) -> void:
	verify.call(condition, description)


func finish_comparison(comparison: CalibrationService, values: Array) -> void:
	var domain := DomainTests.new()
	domain.verify = verify
	while not comparison.current_stage().is_empty():
		if not comparison.accept(domain.trial_report(comparison, values, 4), 4):
			expect(false, "Chaque passage synthétique doit satisfaire le protocole verrouillé : " + comparison.error)
			return


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	var app := MainScene.instantiate()
	app.store = LocalStore.new("user://tests/" + LocalStore.new().identifier())
	tree.root.add_child(app)
	await tree.process_frame
	app.start_guided_calibration()
	expect(app.is_guided and app.screen == app.Screen.COUNTDOWN, "Le parcours guidé doit démarrer par un vrai compte à rebours.")
	expect(app.calibration.speed_factors == [0.5, 1.0, 2.0], "Un débutant doit commencer par une exploration large, pas toujours ±10 %.")
	var initial_checkpoint: Dictionary = app.store.load_guided_checkpoint()
	expect(not initial_checkpoint.is_empty() and initial_checkpoint.phase == "comparing", "Comparaison et recherche doivent être sauvegardées dans une seule transaction.")
	var initial_profile: Dictionary = app.home.read_profile()
	finish_comparison(app.calibration, [25, 80, 40])
	expect(app.save_guided_progress("comparing"), "Un dernier passage complet doit rester reprenable avant la décision suivante.")
	app.show_recommendation()
	expect(app.guided_phase == "transition" and app.guided_search.history.size() == 1, "Une comparaison ne doit être acceptée qu’une fois avant d’afficher la nouvelle plage.")
	expect(app.home.read_profile() == initial_profile and app.session_panel.next_button.visible and not app.session_panel.apply_button.visible, "Une étape intermédiaire doit proposer la suite sans modifier le profil ni proposer une application prématurée.")
	app.show_recommendation()
	expect(app.guided_search.history.size() == 1, "Revoir le bilan intermédiaire ne doit pas dupliquer sa décision.")
	app.return_to_menu()
	expect(app.home.guided_resume_button.visible, "La recherche guidée doit avoir sa propre action de reprise.")
	app.resume_guided_calibration()
	expect(app.screen == app.Screen.RESULTS and app.guided_phase == "transition", "Une reprise entre deux comparaisons doit retrouver le bilan, pas sauter une étape.")
	app.next_calibration_stage()
	expect(app.calibration.speed_factors == [0.75, 1.0, 1.25] and app.calibration.current_index == 0, "Un centre dominant doit conduire à une plage plus précise, avec de nouveaux passages.")
	finish_comparison(app.calibration, [25, 80, 40])
	expect(app.save_guided_progress("comparing"), "La deuxième comparaison complète doit être sauvegardable.")
	app.show_recommendation()
	app.next_calibration_stage()
	expect(app.calibration.speed_factors == CalibrationService.FACTORS, "L’affinage doit être suivi d’une validation plus étroite.")
	finish_comparison(app.calibration, [25, 80, 40])
	expect(app.save_guided_progress("comparing"), "La validation complète doit être enregistrable.")
	app.show_recommendation()
	expect(app.guided_phase == "complete" and app.guided_search.finished and app.guided_search.history.size() == 3, "Le conseil stable doit provenir de trois comparaisons complètes sur les cinq exercices.")
	expect(app.session_panel.stat_values[1].text == "135", "Le bilan guidé doit compter les 135 mesures réellement cumulées, pas seulement la dernière comparaison.")
	expect(app.final_recommendation.trial_allowed and not app.final_recommendation.apply_allowed, "Un essai provisoire explicite n’est pas une validation définitive automatique.")
	expect(app.session_panel.guided_confirmation.visible and app.session_panel.apply_button.disabled, "Le conseil guidé doit demander un consentement avant application.")
	app.apply_recommendation()
	expect(app.screen == app.Screen.RESULTS and app.home.read_profile() == initial_profile, "Sans confirmation, même un résultat stable ne doit pas modifier le réglage.")
	var checkpoint: Dictionary = app.store.load_guided_checkpoint()
	var tampered: Dictionary = checkpoint.duplicate(true)
	tampered.phase = "transition"
	expect(not app.store.save_guided_checkpoint(tampered), "Un état terminé ne doit pas pouvoir être falsifié en transition.")
	var stored: Dictionary = app.store.load_guided_checkpoint()
	expect(AdaptiveSensitivityService.same_value(stored, checkpoint), "Une sauvegarde refusée doit préserver la recherche précédente.")
	app.return_to_menu()
	app.resume_guided_calibration()
	expect(app.guided_search.history.size() == 3 and app.screen == app.Screen.RESULTS, "Revoir le conseil final après reprise doit rester idempotent.")
	app.session_panel.guided_confirmation.button_pressed = true
	app.apply_recommendation()
	expect(app.screen == app.Screen.HOME and app.home.selected_page == 3, "Un essai consenti doit ouvrir la conversion du réglage réellement appliqué.")
	expect(app.home.status_label.text.contains("test"), "L’application d’un conseil guidé doit rester qualifiée de test provisoire.")
	app.queue_free()
	await tree.process_frame
	await tree.create_timer(0.1).timeout
	await test_transaction_failure(tree)
	return true


func test_transaction_failure(tree: SceneTree) -> void:
	var app := MainScene.instantiate()
	var store := FailingGuidedStore.new()
	store.root_path = "user://tests/" + LocalStore.new().identifier()
	app.store = store
	tree.root.add_child(app)
	await tree.process_frame
	app.start_guided_calibration()
	finish_comparison(app.calibration, [25, 40, 80])
	expect(app.save_guided_progress("comparing"), "Le dernier passage doit être écrit avant de simuler une panne de transition.")
	var before: Dictionary = app.guided_search.checkpoint()
	var disk_before: String = FileAccess.get_file_as_string(store.root_path.path_join("guided_calibration_checkpoint.json"))
	store.reject_guided = true
	app.show_recommendation()
	expect(app.guided_phase == "comparing" and app.guided_search.history.is_empty(), "Une transition refusée doit annuler la décision en mémoire.")
	expect(AdaptiveSensitivityService.same_value(app.guided_search.checkpoint(), before), "Le rollback doit conserver exactement le plan de recherche précédent.")
	expect(FileAccess.get_file_as_string(store.root_path.path_join("guided_calibration_checkpoint.json")) == disk_before, "La panne ne doit pas altérer la dernière transaction durable.")
	expect(not app.session_panel.apply_button.visible and app.session_panel.next_button.visible, "Après panne, proposer un réessai d’écriture, jamais appliquer un bilan non validé.")
	store.reject_guided = false
	app.next_calibration_stage()
	expect(app.guided_phase == "transition" and app.guided_search.history.size() == 1, "Le réessai doit accepter une seule fois la décision restaurée.")
	var old_center: float = app.calibration.baseline.cm_per_360
	store.reject_guided = true
	app.next_calibration_stage()
	expect(app.guided_phase == "transition" and app.calibration.baseline.cm_per_360 == old_center, "La panne au début du nouveau tour doit garder l’ancien comparateur et sa phase.")
	store.reject_guided = false
	app.next_calibration_stage()
	expect(app.guided_phase == "comparing" and app.calibration.baseline.cm_per_360 < old_center, "Après réessai, un bord gagnant doit réellement déplacer la plage vers une vitesse supérieure.")
	app.return_to_menu()
	app.resume_guided_calibration()
	expect(app.is_guided and app.calibration.current_index == 0 and app.guided_search.history.size() == 1, "La reprise après déplacement doit restaurer les nouveaux candidats et l’historique intact.")
	app.return_to_menu()
	var file := FileAccess.open(store.root_path.path_join("guided_calibration_checkpoint.json"), FileAccess.WRITE)
	file.store_string("{\"schema_version\":999}")
	file.close()
	var profile_before: Dictionary = app.home.read_profile()
	app.start_guided_calibration()
	expect(app.screen == app.Screen.HOME and app.home.read_profile() == profile_before, "Une nouvelle recherche ne doit pas écraser un fichier de version inconnue.")
	expect(FileAccess.get_file_as_string(store.root_path.path_join("guided_calibration_checkpoint.json")) == "{\"schema_version\":999}", "Les octets du fichier inconnu doivent rester conservés.")
	app.queue_free()
	await tree.process_frame
	await tree.create_timer(0.1).timeout
