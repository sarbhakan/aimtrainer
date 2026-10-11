extends RefCounted

const ProfileScript := preload("res://scripts/presentation/crosshair_profile.gd")
const SettingsScript := preload("res://scripts/ui/crosshair_settings.gd")
const HudScript := preload("res://scripts/ui/training_hud.gd")

var verify: Callable
var failure_count: int = 0
var changed_count: int = 0


func expect(condition: bool, description: String) -> void:
	if not condition:
		failure_count += 1
	verify.call(condition, description)


func run(tree: SceneTree, check: Callable) -> bool:
	verify = check
	failure_count = 0
	test_validation()
	await test_settings(tree)
	var hud: TrainingHud = HudScript.new()
	hud.configure(silent_profile())
	tree.root.add_child(hud)
	await tree.process_frame
	await test_hud(hud, tree)
	test_countdown(hud)
	test_stop_paths(hud, tree)
	test_feedback_metrics(hud)
	hud.stop()
	hud.queue_free()
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await test_rendering(tree)
	return failure_count == 0


func silent_profile() -> Dictionary:
	var profile := SensitivityService.default_profile()
	profile.sound_enabled = false
	profile.merge(ProfileScript.defaults(), true)
	return profile


func test_validation() -> void:
	var defaults: Dictionary = ProfileScript.defaults()
	expect(defaults.size() == 6 and ProfileScript.validate(defaults).is_empty(), "Les six valeurs par défaut du viseur sont valides.")
	defaults.crosshair_size_px = 8.0
	expect(ProfileScript.defaults().crosshair_size_px == 2.0, "Chaque appel de defaults fournit un dictionnaire indépendant.")
	expect(ProfileScript.validate({}).is_empty(), "Un ancien profil sans champs de viseur reste valide.")
	expect(ProfileScript.validate({"dpi": 800, "cm_per_360": 35.0, "vertical_fov_deg": 75.0}).is_empty(), "Le validateur du viseur accepte un profil physique historique.")
	for style in ["dot", "cross", "circle", "t"]:
		expect(ProfileScript.validate({"crosshair_style": style}).is_empty(), "Les quatre styles publics acceptent les autres champs absents : " + style)
	for field in ["crosshair_size_px", "crosshair_thickness_px", "crosshair_gap_px"]:
		var limits := Vector2(1, 32) if field == "crosshair_size_px" else Vector2(1, 8) if field == "crosshair_thickness_px" else Vector2(0, 24)
		for valid_value in [int(limits.x), float(limits.x), float(limits.y), (limits.x + limits.y) * 0.5]:
			expect(ProfileScript.validate({field: valid_value}).is_empty(), "Bornes incluses et nombres valides pour " + field)
		for invalid_value in [limits.x - 0.01, limits.y + 0.01, NAN, INF, -INF, true, false, "2", null, [], {}]:
			expect(not ProfileScript.validate({field: invalid_value}).is_empty(), "Types, valeurs non finies et hors bornes refusés pour " + field)
	for invalid_style in ["plus", "Cross", "", 1, true, null, [], {}]:
		expect(not ProfileScript.validate({"crosshair_style": invalid_style}).is_empty(), "La forme utilise exclusivement dot/cross/circle/t.")
	for valid_color in ["#fff", "f4f9ff", "#64e6d9", "#64e6d980", "#abcd"]:
		expect(ProfileScript.validate({"crosshair_color": valid_color}).is_empty(), "Une couleur HTML valide avec ou sans alpha est acceptée.")
	for invalid_color in ["red", "#gggggg", "#12", "", 123, Color.WHITE, null, true, [], {}]:
		expect(not ProfileScript.validate({"crosshair_color": invalid_color}).is_empty(), "La couleur doit être une chaîne HTML valide.")
	for valid_outline in [true, false]:
		expect(ProfileScript.validate({"crosshair_outline": valid_outline}).is_empty(), "Le contour accepte uniquement un booléen.")
	for invalid_outline in [0, 1, "true", null, [], {}]:
		expect(not ProfileScript.validate({"crosshair_outline": invalid_outline}).is_empty(), "Un contour de mauvais type est refusé.")
	var legacy := SensitivityService.default_profile()
	for field in ProfileScript.defaults():
		legacy.erase(field)
	expect(SensitivityService.validate_profile(legacy).is_empty(), "Le validateur parent conserve les anciens profils physiques.")
	var invalid := legacy.duplicate(true)
	invalid.crosshair_color = "#invalid"
	expect(not SensitivityService.validate_profile(invalid).is_empty(), "SensitivityService relaie les erreurs du validateur de viseur.")


func test_settings(tree: SceneTree) -> void:
	var settings: CrosshairSettings = SettingsScript.new()
	var profile := ProfileScript.defaults()
	profile.crosshair_style = "cross"
	profile.crosshair_size_px = 8.375
	profile.crosshair_thickness_px = 2.125
	profile.crosshair_gap_px = 3.375
	settings.configure(profile)
	expect(settings.read_settings() == profile, "configure et read_settings fonctionnent avant l’entrée dans l’arbre.")
	changed_count = 0
	settings.changed.connect(func() -> void: changed_count += 1)
	tree.root.add_child(settings)
	await tree.process_frame
	expect(settings.read_settings() == profile and changed_count == 0, "Le chargement préserve les valeurs canoniques sans émettre changed.")
	expect(settings.preview is Panel and settings.preview.mouse_filter == Control.MOUSE_FILTER_IGNORE, "L’aperçu utilise un contrôle Godot natif et laisse passer la souris.")
	for style_index in 4:
		settings.style_input.select(style_index)
		settings.style_input.item_selected.emit(style_index)
		expect(settings.read_settings().crosshair_style == ProfileScript.STYLES[style_index], "Chaque choix UI correspond au même identifiant public de style.")
		expect(settings.current_profile == settings.read_settings(), "L’aperçu reçoit immédiatement les valeurs modifiées.")
		expect(settings.gap_input.editable == (style_index in [1, 3]), "L’espace central est éditable pour croix et T.")
		expect(settings.thickness_input.editable == (style_index != 0), "L’épaisseur est éditable pour les formes tracées.")
	expect(changed_count == 4, "Chaque sélection utilisateur émet changed une seule fois.")
	settings.size_input.value = 12.0
	settings.thickness_input.value = 3.0
	settings.gap_input.value = 6.0
	settings.color_input.color = Color("ff8800")
	settings.color_input.color_changed.emit(settings.color_input.color)
	settings.outline_input.button_pressed = true
	var edited := settings.read_settings()
	expect(changed_count == 9 and edited.crosshair_size_px == 12.0 and edited.crosshair_thickness_px == 3.0 and edited.crosshair_gap_px == 6.0, "Les réglages de taille, épaisseur, espace, couleur et contour actualisent l’aperçu.")
	expect(edited.crosshair_color == "#ff8800" and edited.crosshair_outline and ProfileScript.validate(edited).is_empty(), "Le widget fournit les six champs dans leur format validable.")
	var largest := ProfileScript.defaults()
	largest.crosshair_style = "cross"
	largest.crosshair_size_px = ProfileScript.MAX_SIZE_PX
	largest.crosshair_thickness_px = ProfileScript.MAX_THICKNESS_PX
	largest.crosshair_gap_px = ProfileScript.MAX_GAP_PX
	largest.crosshair_outline = true
	settings.configure(largest)
	expect(settings.preview.custom_minimum_size.y * 0.5 > ProfileScript.radius_px(largest) + 2.0, "Le plus grand viseur garde une marge visible dans l’aperçu natif.")
	settings.configure({})
	expect(settings.read_settings() == ProfileScript.defaults() and changed_count == 9, "Configurer un ancien profil rétablit les défauts sans changement utilisateur.")
	var detached := settings.read_settings()
	detached.crosshair_style = "circle"
	expect(settings.read_settings().crosshair_style == "dot", "Le dictionnaire retourné ne modifie pas l’état interne.")
	settings.queue_free()
	await tree.process_frame


func test_hud(hud: TrainingHud, tree: SceneTree) -> void:
	for dimensions in [Vector2(800, 450), Vector2(1280, 720), Vector2(1920, 1080)]:
		hud.size = dimensions
		hud.countdown_label.text = "2"
		hud.countdown_label.show()
		await tree.process_frame
		expect(hud.crosshair_layer.size.is_equal_approx(dimensions), "La couche du viseur suit la taille native du HUD.")
		expect(hud.crosshair_layer.get_index() > hud.weapon_feedback.get_index(), "Le viseur est dessiné devant le sprite et les traces.")
		var countdown_rect := Rect2(hud.countdown_label.global_position, hud.countdown_label.size)
		expect(countdown_rect.end.y < dimensions.y * 0.5 - 32.0, "Le compte à rebours reste au-dessus de la cible centrale : %s, rectangle %s." % [dimensions, countdown_rect])
		hud.countdown_label.hide()
	for style in ProfileScript.STYLES:
		var profile := silent_profile()
		profile.crosshair_style = style
		profile.crosshair_size_px = 12.0
		profile.crosshair_outline = true
		hud.configure(profile)
		expect(hud.crosshair_profile == ProfileScript.resolve(profile), "HUD.configure applique exactement le profil de viseur : " + style)
		var center := hud.crosshair_layer.position + hud.crosshair_layer.size * 0.5
		hud.weapon_feedback.play_shot()
		expect(center.is_equal_approx(hud.size * 0.5) and hud.crosshair_layer.scale == Vector2.ONE, "Le recul du sprite ne déplace et n’agrandit jamais le viseur.")
		expect(hud.weapon_feedback.crosshair_clearance_px > ProfileScript.radius_px(hud.crosshair_profile), "La trace s’arrête à distance du viseur personnalisé.")
		expect(hud.hit_remaining_s == 0.0, "Un tir cosmétique ne déclenche jamais de hitmarker.")
		hud.hit()
		expect(hud.hit_remaining_s >= 0.09 and hud.hit_remaining_s <= 0.14, "hit démarre un retour court de 90 à 140 ms.")
		hud._process(0.06)
		expect(hud.hit_remaining_s > 0.0, "Le hitmarker reste lisible après 60 ms.")
		hud._process(0.06)
		expect(hud.hit_remaining_s == 0.0 and not hud.is_processing(), "Le hitmarker s’éteint sans traitement permanent.")
		hud.stop()
	hud.configure({"sound_enabled": false})
	expect(hud.crosshair_profile == ProfileScript.defaults(), "Un profil HUD historique conserve le point blanc de deux pixels.")
	expect(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.crosshair_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Le HUD et son viseur ne capturent pas les mouvements ou clics.")


func test_countdown(hud: TrainingHud) -> void:
	hud.configure(silent_profile())
	hud.countdown_label.text = "2"
	hud.countdown_label.show()
	hud.sync_countdown()
	expect(hud.countdown_remaining_s > 0.0 and hud.countdown_label.scale.x > 1.0 and hud.countdown_label.modulate.a >= 0.85, "Un nouveau chiffre démarre une impulsion courte et lisible.")
	hud.hit()
	expect(hud.hit_remaining_s == 0.0, "La préparation n’affiche aucun retour de touche.")
	hud._process(0.08)
	var remaining_s := hud.countdown_remaining_s
	hud.sync_countdown()
	expect(hud.countdown_remaining_s == remaining_s and hud.countdown_label.text == "2", "Redessiner le même chiffre ne relance ni animation ni chronomètre.")
	hud._process(0.08)
	expect(hud.countdown_remaining_s == 0.0 and hud.countdown_label.scale == Vector2.ONE and hud.countdown_label.modulate.a == 1.0, "Le chiffre revient exactement au repos après 160 ms.")
	hud.countdown_label.text = "1"
	hud.sync_countdown()
	expect(hud.countdown_remaining_s > 0.0 and hud.countdown_label.text == "1", "Le parent garde la valeur affichée et le prochain chiffre relance l’impulsion.")
	hud.countdown_label.hide()
	expect(hud.countdown_remaining_s == 0.0 and hud.countdown_label.scale == Vector2.ONE, "Masquer le compte à rebours efface son animation immédiatement.")
	var reduced := silent_profile()
	reduced.reduced_motion = true
	hud.configure(reduced)
	hud.countdown_label.text = "2"
	hud.countdown_label.show()
	hud.sync_countdown()
	expect(hud.countdown_label.text == "2" and hud.countdown_label.scale == Vector2.ONE and hud.countdown_remaining_s == 0.0, "Réduire les animations garde un compte à rebours lisible et immobile.")
	hud.countdown_label.hide()
	hud.weapon_feedback.play_shot()
	hud.weapon_feedback.set_continuous(true)
	expect(hud.weapon_feedback.flash_remaining_s == 0.0 and hud.weapon_feedback.tracer_remaining_s == 0.0 and not hud.weapon_feedback.is_processing(), "Réduire les animations supprime recul, flash et trace.")
	hud.hit()
	expect(hud.hit_remaining_s == TrainingHud.HIT_DURATION_S and hud.crosshair_layer.scale == Vector2.ONE, "Le mode réduit conserve un hitmarker statique sans déplacer le viseur.")
	hud.stop()


func test_stop_paths(hud: TrainingHud, tree: SceneTree) -> void:
	for stop_path in ["pause_parent", "focus", "hidden", "tree_pause", "stop"]:
		hud.configure(silent_profile())
		hud.show()
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		hud.hit()
		hud.weapon_feedback.play_shot()
		hud.weapon_feedback.set_continuous(true)
		if stop_path == "pause_parent":
			hud.weapon_feedback.stop()
		elif stop_path == "focus":
			hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif stop_path == "hidden":
			hud.hide()
		elif stop_path == "tree_pause":
			tree.paused = true
		else:
			hud.stop()
		expect(hud.hit_remaining_s == 0.0 and not hud.is_processing(), "Chaque arrêt nettoie aussi le hitmarker : " + stop_path)
		expect(hud.weapon_feedback.flash_remaining_s == 0.0 and hud.weapon_feedback.tracer_remaining_s == 0.0 and not hud.weapon_feedback.continuous_active, "Chaque arrêt nettoie les effets de l’arme : " + stop_path)
		if stop_path in ["focus", "hidden", "tree_pause"]:
			var shots := hud.weapon_feedback.shot_count
			hud.hit()
			hud.weapon_feedback.play_shot()
			hud.weapon_feedback.set_continuous(true)
			expect(hud.hit_remaining_s == 0.0 and hud.weapon_feedback.shot_count == shots and not hud.weapon_feedback.continuous_active, "Un contrôle inactif refuse les nouveaux retours : " + stop_path)
		tree.paused = false
		hud.show()
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		expect(hud.hit_remaining_s == 0.0 and not hud.weapon_feedback.continuous_active, "Le retour exige un nouveau hit ou clic explicite : " + stop_path)
	hud.configure(silent_profile())
	hud.countdown_label.text = "2"
	hud.countdown_label.show()
	hud.sync_countdown()
	hud.weapon_feedback.stop()
	hud.sync_countdown()
	expect(hud.countdown_remaining_s == 0.0 and hud.countdown_label.scale == Vector2.ONE, "La pause parent arrête aussi l’impulsion du compte à rebours.")
	hud.countdown_label.hide()
	var voices := hud.weapon_feedback.get_child_count()
	for repeat_index in 100:
		hud.weapon_feedback.play_shot()
		hud.hit()
	expect(hud.weapon_feedback.players.size() == 4 and voices == 5 and hud.weapon_feedback.get_child_count() == voices, "Cent retours réutilisent les quatre voix et la boucle préallouées.")
	expect(hud.hit_remaining_s == TrainingHud.HIT_DURATION_S, "Des touches rapprochées ne cumulent pas la durée du hitmarker.")
	hud.stop()


func test_feedback_metrics(hud: TrainingHud) -> void:
	var profile := silent_profile()
	for scenario_id in ["C01", "T01"]:
		var baseline := replay(scenario_id, profile, null)
		for style in ProfileScript.STYLES:
			var custom := profile.duplicate(true)
			custom.crosshair_style = style
			custom.crosshair_size_px = 24.0
			custom.crosshair_thickness_px = 5.0
			custom.crosshair_gap_px = 12.0
			custom.crosshair_color = "#ff8800"
			custom.crosshair_outline = true
			hud.configure(custom)
			var animated := replay(scenario_id, custom, hud)
			expect(animated == baseline, "À counts et timestamps égaux, le feedback ne change ni métriques, score, contexte ni caméra : %s/%s" % [scenario_id, style])


func replay(scenario_id: String, profile: Dictionary, hud: TrainingHud) -> Dictionary:
	var engine := ScenarioEngine.new()
	expect(engine.start(ScenarioCatalog.find(scenario_id), 21981, 1.0), "Le replay utilise une définition et une graine valides.")
	var camera := AimCamera.new()
	var clock := SessionClock.new()
	clock.start(1000000)
	for event_index in 20:
		var timestamp_us := 1000000 + (event_index + 1) * 40000
		var time_s := clock.elapsed_s(timestamp_us)
		camera.apply_mouse_counts(Vector2(3.0, -1.0) if event_index % 2 == 0 else Vector2(-2.0, 1.0))
		engine.record_aim(time_s, camera.yaw_deg, camera.pitch_deg)
		engine.advance_to(time_s)
		if scenario_id == "C01":
			var direction := engine.target_direction(0, time_s) if event_index % 2 == 0 else Vector3.BACK
			var actual_hit := engine.shoot(time_s, direction)
			if hud != null:
				hud.weapon_feedback.play_shot()
				if actual_hit:
					hud.hit()
		elif hud != null:
			hud.weapon_feedback.set_continuous(true)
		if hud != null:
			hud._process(0.15)
			hud.weapon_feedback._process(0.04)
		engine.record_frame(1.0 / 144.0)
	engine.advance_to(1.0)
	var report := engine.result(profile, 16.0 / 9.0, true)
	var state := {"metrics": report.metrics, "score": report.score, "comparison_key": report.comparison_key,
		"performance": report.performance, "duration_s": report.active_duration_s, "yaw_deg": camera.yaw_deg,
		"pitch_deg": camera.pitch_deg, "counts": camera.received_counts, "clock_s": clock.elapsed_s(2000000),
		"last_input_s": engine.timeline.last_time_s, "event_count": engine.timeline.event_count}
	camera.free()
	if hud != null:
		hud.stop()
	return state


func test_rendering(tree: SceneTree) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, 160)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var canvas := Control.new()
	canvas.size = Vector2(160, 160)
	var profile := ProfileScript.defaults()
	profile.crosshair_color = "#ff8800"
	profile.crosshair_size_px = 10.0
	profile.crosshair_thickness_px = 2.0
	profile.crosshair_gap_px = 4.0
	canvas.draw.connect(func() -> void: ProfileScript.draw(canvas, Vector2(80, 80), profile))
	viewport.add_child(canvas)
	tree.root.add_child(viewport)
	var capture_directory := "user://tests/crosshair_feedback/" + LocalStore.new().identifier()
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	expect(directory_error == OK, "Les captures sont isolées sous user://tests/.")
	for style in ProfileScript.STYLES:
		profile.crosshair_style = style
		for outline in [false, true]:
			profile.crosshair_outline = outline
			canvas.queue_redraw()
			await tree.process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var center_pixel := image.get_pixel(80, 80)
			var right_pixel := image.get_pixel(87, 80)
			var top_pixel := image.get_pixel(80, 73)
			var bottom_pixel := image.get_pixel(80, 87)
			if style == "dot":
				expect(center_pixel.r > 0.8 and right_pixel.r > 0.8, "Le point remplit le centre jusqu’à son rayon configuré.")
			else:
				expect(center_pixel.r < 0.2, "Les formes ouvertes gardent le centre visible : " + style)
			if style in ["cross", "t"]:
				expect(right_pixel.r > 0.8 and bottom_pixel.r > 0.8, "Croix et T affichent les branches latérale et basse.")
				expect((top_pixel.r > 0.8) == (style == "cross"), "Le T supprime exactement la branche haute de la croix.")
			elif style == "circle":
				expect(image.get_pixel(90, 80).r > 0.5 and right_pixel.r < 0.2, "Le cercle trace son rayon sans remplir l’intérieur.")
			expect(image.save_png(capture_directory.path_join(style + ("-outline" if outline else "") + ".png")) == OK, "La capture du viseur natif est enregistrée.")
	print("CROSSHAIR CAPTURES : " + ProjectSettings.globalize_path(capture_directory))
	canvas.hide()
	viewport.size = Vector2i(800, 450)
	var visible_hud: TrainingHud = HudScript.new()
	var profile_hud := silent_profile()
	profile_hud.show_weapon = false
	profile_hud.reduced_motion = true
	visible_hud.configure(profile_hud)
	visible_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(visible_hud)
	visible_hud.countdown_label.text = "2"
	visible_hud.countdown_label.show()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var hud_image := viewport.get_texture().get_image()
	expect(hud_image.get_pixel(400, 225).r > 0.8, "Le viseur reste réellement visible au centre pendant le compte à rebours.")
	expect(visible_hud.countdown_label.size.x >= 96.0 and visible_hud.countdown_label.size.y < 110.0, "Le compte à rebours natif affiche son chiffre sur une seule ligne.")
	expect(hud_image.save_png(capture_directory.path_join("hud-countdown.png")) == OK, "Le HUD est capturé dans une fenêtre de 800 × 450.")
	visible_hud.queue_free()
	await tree.process_frame
	viewport.size = Vector2i(384, 650)
	var visible_settings: CrosshairSettings = SettingsScript.new()
	profile.crosshair_style = "cross"
	visible_settings.configure(profile)
	visible_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(visible_settings)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var preview_center := visible_settings.preview.position + visible_settings.preview.size * 0.5
	var settings_image := viewport.get_texture().get_image()
	expect(settings_image.get_pixel(roundi(preview_center.x + 8.0), roundi(preview_center.y)).r > 0.8, "Le widget natif dessine le viseur configuré dans son aperçu.")
	visible_settings.size_input.value = 16.0
	await tree.process_frame
	await RenderingServer.frame_post_draw
	settings_image = viewport.get_texture().get_image()
	expect(settings_image.get_pixel(roundi(preview_center.x + 18.0), roundi(preview_center.y)).r > 0.8, "Modifier la taille redessine immédiatement la branche dans l’aperçu natif.")
	expect(settings_image.save_png(capture_directory.path_join("widget-preview.png")) == OK, "Le widget et son aperçu sont capturés.")
	viewport.queue_free()
	await tree.process_frame
