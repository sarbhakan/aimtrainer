extends SceneTree

const FeedbackScript := preload("res://scripts/presentation/weapon_feedback.gd")
const HudScript := preload("res://scripts/ui/training_hud.gd")

var assertion_count: int = 0
var failure_count: int = 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Les tests d’animation n’ont pas terminé en 60 secondes.")
		quit(1))
	run_standalone.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)


func run_standalone() -> void:
	await run_suite(self, check)
	if "--capture-weapons" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			check(false, "Un affichage graphique est requis pour les captures d’arme.")
		else:
			await capture_weapons()
	print("WEAPON ANIMATION : %d assertions, %d échecs." % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


static func run_suite(tree: SceneTree, verify: Callable) -> void:
	var feedback: WeaponFeedback = FeedbackScript.new()
	feedback.size = Vector2(1280, 720)
	feedback.set_hud_mode(true)
	tree.root.add_child(feedback)
	await tree.process_frame
	verify.call(feedback.players.size() == 4 and feedback.get_child_count() == 5, "Quatre voix de tir et une boucle sont préallouées.")
	for definition in WeaponCatalog.DEFINITIONS:
		test_shot(feedback, definition, verify)
		test_continuous(feedback, definition, verify)
		test_preferences(feedback, definition, verify)
		test_preview(feedback, definition, verify)
	test_stop_paths(feedback, verify)
	feedback.queue_free()
	await tree.process_frame
	await test_hud(tree, verify)
	await tree.create_timer(0.15).timeout


static func test_shot(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.set_hud_mode(true)
	feedback.size = Vector2(1280, 720)
	feedback.configure(definition, false, 0.45, true, false)
	var resting_muzzle := feedback.muzzle_position()
	var resting_transform := feedback.sprite_transform()
	var shot_count := feedback.shot_count
	feedback.play_shot()
	verify.call(feedback.shot_count == shot_count + 1 and not feedback.continuous_active, "Un appel de tir ne déclenche ni automatique ni deuxième tir.")
	verify.call(feedback.muzzle_position().distance_to(resting_muzzle) > 10.0, "Le recul doit déplacer le canon nettement plus que l’ancien effet de trois pixels.")
	verify.call(feedback.flash_remaining_s > 0.0 and feedback.tracer_remaining_s > 0.0 and feedback.is_processing(), "Le flash et le tracer démarrent immédiatement avec le recul.")
	verify.call(feedback.muzzle_position().is_equal_approx(feedback.sprite_transform() * (definition.muzzle_uv * feedback.sprite_rect().size)), "Le flash suit le canon du sprite, recul compris.")
	feedback._process(0.08)
	verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0, "Le flash et le tracer s’éteignent rapidement sans éclairer toute la scène.")
	verify.call(feedback.muzzle_position().distance_to(resting_muzzle) > 3.0 and feedback.is_processing(), "Le retour du sprite continue après la disparition du flash.")
	feedback._process(0.3)
	verify.call(feedback.sprite_transform().is_equal_approx(resting_transform) and not feedback.is_processing(), "Le sprite revient exactement au repos sans traitement permanent.")
	verify.call(feedback.shot_count == shot_count + 1, "L’animation d’un tir n’en génère pas d’autres.")
	var reference_transform := Transform2D.IDENTITY
	for frame_rate in [60.0, 144.0, 240.0]:
		feedback.play_shot()
		advance(feedback, 0.11, frame_rate)
		if frame_rate == 60.0:
			reference_transform = feedback.sprite_transform()
		verify.call(feedback.sprite_transform().is_equal_approx(reference_transform), "Le recul à temps égal ne dépend pas des FPS synthétiques.")
		feedback.stop()
	for repeat_index in 100:
		feedback.play_shot()
	verify.call(feedback.players.size() == 4 and feedback.get_child_count() == 5, "Les tirs rapprochés ne créent aucune nouvelle voix ou nœud.")
	verify.call(feedback.muzzle_position().distance_to(resting_muzzle) < 40.0, "Le recul ne s’accumule pas avec le spam de clics.")
	feedback.stop()


static func test_continuous(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.configure(definition, false, 0.45, true, false)
	var shot_count := feedback.shot_count
	feedback.set_continuous(true)
	feedback._process(definition.continuous_interval_s * 0.75)
	var returning_muzzle := feedback.muzzle_position()
	feedback._process(definition.continuous_interval_s * 0.3)
	verify.call(feedback.muzzle_position().distance_to(returning_muzzle) > 3.0, "Une nouvelle impulsion de tracking anime réellement le sprite.")
	verify.call(feedback.flash_remaining_s > 0.0 and feedback.continuous_active, "Le feedback continu suit la cadence cosmétique du profil.")
	verify.call(feedback.shot_count == shot_count, "La boucle de tracking ne comptabilise aucun tir de clic.")
	feedback.set_continuous(false)
	verify.call(not feedback.continuous_active and not feedback.continuous_player.playing, "Relâcher coupe immédiatement la boucle audio.")
	feedback._process(0.3)
	verify.call(not feedback.is_processing(), "Le retour au repos s’arrête aussi après la fin de boucle.")
	var reference_transform := Transform2D.IDENTITY
	var reference_flash_s: float = 0.0
	for frame_rate in [60.0, 144.0, 240.0]:
		feedback.stop()
		feedback.set_continuous(true)
		advance(feedback, definition.continuous_interval_s * 2.0 + 0.037, frame_rate)
		if frame_rate == 60.0:
			reference_transform = feedback.sprite_transform()
			reference_flash_s = feedback.flash_remaining_s
		verify.call(feedback.sprite_transform().is_equal_approx(reference_transform) and is_equal_approx(feedback.flash_remaining_s, reference_flash_s), "Les impulsions continues conservent leur phase à FPS synthétiques différents.")
	feedback.stop()
	feedback.set_continuous(true)
	feedback._process(definition.continuous_interval_s * 20.0 + 0.037)
	verify.call(is_equal_approx(feedback.recoil_elapsed_s, 0.037) and feedback.get_child_count() == 5, "Une longue frame ne crée pas de rafale de rattrapage ni de nouveaux nœuds.")
	feedback.stop()


static func advance(feedback: WeaponFeedback, duration_s: float, frame_rate: float) -> void:
	var elapsed_s: float = 0.0
	while elapsed_s < duration_s:
		var delta_s := minf(1.0 / frame_rate, duration_s - elapsed_s)
		feedback._process(delta_s)
		elapsed_s += delta_s


static func test_preferences(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.configure(definition, false, 0.45, true, false)
	feedback.play_shot()
	var voices_playing: bool = false
	for player in feedback.players:
		voices_playing = voices_playing or player.playing
	verify.call(not voices_playing and feedback.recoil_elapsed_s == 0.0, "Le silence coupe le son mais conserve le retour visuel.")
	feedback.configure(definition, true, 0.0, true, false)
	feedback.set_continuous(true)
	verify.call(not feedback.continuous_player.playing, "Un volume nul reste silencieux pendant le maintien.")
	feedback.configure(definition, false, 0.45, true, true)
	var resting_transform := feedback.sprite_transform()
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.sprite_transform().is_equal_approx(resting_transform) and feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and not feedback.is_processing(), "Réduire les animations désactive recul, flash et tracer.")
	feedback.configure(definition, false, 0.45, false, false)
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and not feedback.is_processing(), "Masquer l’arme masque aussi ses effets visuels.")
	feedback.configure(definition, true, 0.45, false, false)
	feedback.play_shot()
	voices_playing = false
	for player in feedback.players:
		voices_playing = voices_playing or player.playing
	verify.call(voices_playing, "Masquer le sprite ne désactive pas le son choisi séparément.")
	feedback.stop()


static func test_preview(feedback: WeaponFeedback, definition: WeaponDefinition, verify: Callable) -> void:
	feedback.set_hud_mode(false)
	feedback.configure(definition, false, 0.45, true, false)
	for dimensions in [Vector2(250, 125), Vector2(360, 200)]:
		feedback.size = dimensions
		feedback.play_shot()
		verify.call(feedback.tracer_remaining_s == 0.0 and feedback.clip_contents, "Les aperçus n’envoient aucun tracer hors de leur contrôle.")
		var rectangle := feedback.sprite_rect()
		for corner in [Vector2.ZERO, Vector2(rectangle.size.x, 0.0), rectangle.size, Vector2(0.0, rectangle.size.y)]:
			verify.call(Rect2(Vector2.ZERO, dimensions).has_point(feedback.sprite_transform() * corner), "Le recul de l’aperçu garde le sprite dans son contrôle.")
		feedback.stop()
	feedback.set_hud_mode(true)


static func test_stop_paths(feedback: WeaponFeedback, verify: Callable) -> void:
	feedback.configure(WeaponCatalog.DEFINITIONS[0], true, 0.45, true, false)
	for stop_path in ["stop", "focus", "hidden", "configure"]:
		feedback.show()
		feedback.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		feedback.play_shot()
		feedback.set_continuous(true)
		if stop_path == "stop":
			feedback.stop()
		elif stop_path == "focus":
			feedback.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif stop_path == "hidden":
			feedback.hide()
		else:
			feedback.configure(WeaponCatalog.DEFINITIONS[1], true, 0.45, true, false)
		var voices_playing: bool = feedback.continuous_player.playing
		for player in feedback.players:
			voices_playing = voices_playing or player.playing
		verify.call(not voices_playing and not feedback.continuous_active and not feedback.is_processing(), "Pause, focus, masquage et changement d’arme coupent toutes les voix.")
		verify.call(feedback.flash_remaining_s == 0.0 and feedback.tracer_remaining_s == 0.0 and feedback.recoil_elapsed_s == WeaponFeedback.RECOIL_DURATION_S, "L’arrêt efface tous les effets visuels en attente.")
		feedback.show()
		verify.call(not feedback.continuous_active, "Afficher à nouveau ne reprend jamais un maintien fantôme.")
	feedback.hide()
	var shot_count := feedback.shot_count
	feedback.play_shot()
	feedback.set_continuous(true)
	verify.call(feedback.shot_count == shot_count and not feedback.continuous_active, "Un contrôle masqué n’accepte aucun nouveau tir.")
	feedback.show()
	feedback.configure(null, false, 0.0, true, false)
	feedback.play_shot()
	verify.call(not feedback.is_processing() and feedback.shot_count == shot_count, "L’absence d’un profil ne provoque ni animation ni erreur.")


static func test_hud(tree: SceneTree, verify: Callable) -> void:
	var hud: TrainingHud = HudScript.new()
	tree.root.add_child(hud)
	await tree.process_frame
	hud.configure({"weapon_id": "pulse", "sound_enabled": false, "sound_volume": 45.0, "show_weapon": true, "reduced_motion": false})
	for dimensions in [Vector2(800, 450), Vector2(1280, 720), Vector2(1920, 1080)]:
		hud.size = dimensions
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await tree.process_frame
		var rectangle := hud.weapon_feedback.sprite_rect()
		verify.call(hud.weapon_feedback.hud_mode and hud.weapon_feedback.size.is_equal_approx(dimensions), "Le contrôle de tir couvre le HUD sans créer de couche d’input.")
		verify.call(rectangle.size.x >= dimensions.x * 0.3 and rectangle.size.x <= dimensions.x * 0.4, "L’arme occupe une place proportionnée, pas un timbre fixe dans un coin.")
		verify.call(not rectangle.has_point(dimensions * 0.5), "Le sprite ne recouvre jamais le point de visée central.")
		verify.call(hud.weapon_feedback.muzzle_position().y > dimensions.y * 0.5, "Le canon reste sous les cibles centrales.")
		verify.call(is_equal_approx(rectangle.end.y, dimensions.y) and rectangle.end.x > dimensions.x, "La prise en main se prolonge au bord de l’écran, sans arme flottante.")
		verify.call(hud.weapon_feedback.get_index() == 0, "Les instructions et la progression se dessinent devant le sprite.")
		verify.call(hud.weapon_feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Le retour de tir ne capture pas la souris.")
		hud.weapon_feedback.play_shot()
		hud.hit()
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		verify.call(hud.hit_remaining_s == 0.0 and not hud.weapon_feedback.is_processing(), "Le HUD entier se nettoie à la perte de focus.")
		hud.hide()
		hud.show()
		verify.call(hud.hit_remaining_s == 0.0 and not hud.weapon_feedback.continuous_active, "Revenir au HUD ne reprend aucun effet ou son précédent.")
	hud.queue_free()
	await tree.process_frame


func capture_weapons() -> void:
	var directory := OS.get_environment("AIM_LOCAL_WEAPON_CAPTURE_DIR")
	if directory.is_empty():
		directory = "/tmp/aimlocal-weapon-visual"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Le dossier isolé des captures est disponible.")
	var hud: TrainingHud = HudScript.new()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.title_label.text = "Retour de tir · contrôle graphique"
	hud.metric_label.text = "Données synthétiques"
	hud.help_label.text = "Le sprite, le flash et le tracer restent cosmétiques."
	hud.countdown_label.hide()
	for dimensions in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await create_timer(0.1).timeout
		for definition in WeaponCatalog.DEFINITIONS:
			hud.weapon_feedback.configure(definition, false, 0.0, true, false)
			for phase in ["repos", "tir", "retour"]:
				hud.weapon_feedback.stop()
				if phase != "repos":
					hud.weapon_feedback.play_shot()
					if phase == "retour":
						hud.weapon_feedback._process(0.11)
					hud.weapon_feedback.set_process(false)
				await RenderingServer.frame_post_draw
				var path := directory.path_join("%d-%s-%s.png" % [dimensions.x, definition.weapon_id, phase])
				check(root.get_texture().get_image().save_png(path) == OK, "Le rendu de l’arme a été capturé : " + path)
	hud.queue_free()
	await process_frame
	print("WEAPON CAPTURES : 27 rendus isolés dans " + directory)
