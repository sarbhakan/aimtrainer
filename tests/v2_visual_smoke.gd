extends SceneTree

const MainScene := preload("res://scenes/app/MainV2.tscn")
const Catalog := preload("res://scripts/v2/v2_catalog.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const Geometry := preload("res://scripts/v2/v2_geometry.gd")
const Store := preload("res://scripts/v2/v2_store.gd")
const Calibration := preload("res://scripts/v2/v2_calibration_service.gd")
const CalibrationRunner := preload("res://scripts/v2/v2_calibration_runner.gd")
const Ui := preload("res://scripts/ui/aim_ui.gd")
const SEED_HEX: String = "0000000000000000000000000000002a"
const FIXTURES_PATH: String = "res://docs/reference/v2/donnees/calibration_v2_comparison_examples.json"
const PROJECTION_TOLERANCE_PX: float = 0.5
const SOURCE_PATHS: PackedStringArray = [
	"project.godot", "scenes/app/MainV2.tscn", "scripts/v2/v2_app_controller.gd", "scripts/v2/v2_arena.gd",
	"scripts/v2/v2_preview.gd", "scripts/v2/v2_geometry.gd", "scripts/v2/v2_session_engine.gd",
	"scripts/v2/v2_catalog.gd", "scripts/v2/v2_canonical.gd", "scripts/v2/v2_random.gd",
	"scripts/v2/v2_motion.gd", "scripts/v2/v2_spawner.gd", "scripts/v2/v2_contact.gd",
	"scripts/v2/v2_scores.gd", "scripts/v2/v2_store.gd", "scripts/v2/v2_calibration_service.gd",
	"scripts/v2/v2_progress.gd",
	"scripts/v2/v2_calibration_runner.gd", "scripts/v2/v2_calibration_task.gd",
	"scripts/ui/aim_ui.gd", "scripts/ui/sensitivity_import.gd", "scripts/ui/crosshair_settings.gd",
	"scripts/presentation/crosshair_profile.gd", "scripts/presentation/weapon_catalog.gd",
	"assets/fonts/v2/DejaVuSans.ttf", "assets/fonts/v2/DejaVuSans-Bold.ttf",
	"scripts/ui/v2_shell.gd", "scripts/ui/v2_training_hud.gd", "tests/v2_visual_smoke.gd"
]

var app: Node
var capture_root: String = ""
var run_directory: String = ""
var run_id: String = ""
var store_root: String = ""
var records: Array[Dictionary] = []
var assertion_count: int = 0
var failure_count: int = 0
var marker_label: Label
var source_hashes: Dictionary = {}
var definitions: Dictionary = {}
var last_projection_checks: Array[Dictionary] = []
var last_body_samples: Array[Dictionary] = []
var publish_current: bool = true


func _initialize() -> void:
	publish_current = OS.get_environment("AIM_LOCAL_V2_VISUAL_DRAFT") != "1"
	capture_root = OS.get_environment("AIM_LOCAL_V2_SCREENSHOT_DIR")
	if capture_root.is_empty():
		capture_root = ProjectSettings.globalize_path("res://dist/preview_v2")
	store_root = OS.get_environment("AIM_LOCAL_V2_VISUAL_STORE")
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("V2 visual smoke did not complete within 180 seconds.")
		quit(1))
	run_suite.call_deferred()


func check(condition: bool, description: String) -> bool:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(description)
	return condition


func settle() -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func run_suite() -> void:
	if not check(DisplayServer.get_name() != "headless", "Native rendering is required; headless output is not visual evidence."):
		quit(1)
		return
	if not check(not store_root.is_empty() and store_root.is_absolute_path() and not store_root.begins_with("user://"), "The runner must inject an isolated absolute V2Store root."):
		quit(1)
		return
	run_id = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "") + "_" + Crypto.new().generate_random_bytes(8).hex_encode()
	run_directory = capture_root.path_join("runs").path_join(run_id)
	if not check(DirAccess.make_dir_recursive_absolute(run_directory) == OK, "The fresh capture directory is writable."):
		quit(1)
		return
	for source_path: String in SOURCE_PATHS:
		source_hashes[source_path] = FileAccess.get_sha256("res://" + source_path)
	for definition: Dictionary in Catalog.programs():
		definitions[str(definition.program_id) + "/" + str(definition.difficulty)] = Catalog.fingerprint(definition)
	check(definitions.size() == 24, "All 24 V2 definition hashes are present.")
	check(Calibration.protocol_hash() == Calibration.PROTOCOL_SHA256, "The protocol snapshot matches AIM-CANON-1.")
	app = MainScene.instantiate()
	app.store = Store.new(store_root.path_join("v2"))
	var profile := Store.default_profile()
	profile.sound_enabled = false
	profile.reduced_motion = true
	profile.show_weapon = false
	check(app.store.save_profile(profile), "The isolated QA profile is valid and saved before scene startup.")
	root.add_child(app)
	await settle()
	if not check(not app.catalogue.is_empty() and not app.profile.is_empty() and app.calibration is CalibrationRunner, "The actual MainV2 scene initializes its catalogue, profile and native CAL runner."):
		app.queue_free()
		await process_frame
		quit(1)
		return
	check(bool(app._calibration_ui_state().get("can_start_express", false)), "The actual CAL service enables preparation for the isolated baseline profile.")
	app.set_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	if RenderingServer.frame_post_draw.is_connected(app._post_draw):
		RenderingServer.frame_post_draw.disconnect(app._post_draw)
	_add_marker()
	check(not app.catalogue.is_empty() and not app.profile.is_empty(), "The actual MainV2 scene loads its catalogue, profile, shell and arena.")
	await capture_menus()
	print("V2 VISUAL STAGE : menus et aperçus terminés.")
	await capture_programs()
	print("V2 VISUAL STAGE : huit programmes et trois niveaux terminés.")
	await capture_calibration_fixtures()
	app.preview.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for source_path: String in SOURCE_PATHS:
		check(FileAccess.get_sha256("res://" + source_path) == source_hashes[source_path], "Source remains unchanged during the capture run: " + source_path)
	var manifest := _manifest()
	_write_json(run_directory.path_join("manifest.json"), manifest)
	if failure_count == 0 and publish_current:
		_write_json(capture_root.path_join("CURRENT.pending"), {
			"schema_version": "aimlocal.visuals.current.v2.0", "app_version": "1.0.0", "run_id": run_id,
			"manifest": "runs/" + run_id + "/manifest.json", "manifest_sha256": FileAccess.get_sha256(run_directory.path_join("manifest.json")),
			"capture_count": records.size(), "catalogue_revision": Catalog.REVISION,
			"generated_utc": Time.get_datetime_string_from_system(true)
		})
	print("V2 VISUAL SMOKE : %d captures, %d assertions, %d échecs." % [records.size(), assertion_count, failure_count])
	print("V2 VISUAL DIRECTORY : " + run_directory)
	if not publish_current:
		print("V2 VISUAL DRAFT : CURRENT non publié.")
	app.queue_free()
	await process_frame
	quit(0 if failure_count == 0 else 1)


func _add_marker() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	marker_label = Label.new()
	marker_label.text = "CAPTURE QA V2 · aucune mesure utilisateur"
	marker_label.add_theme_font_size_override("font_size", 16)
	marker_label.add_theme_color_override("font_color", Color("ffca74"))
	marker_label.add_theme_stylebox_override("normal", Ui.style(Color("0b1119"), 4.0, Color("0b1119"), 0))
	marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	marker_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	overlay.add_child(marker_label)


func resize_window(dimensions: Vector2i) -> void:
	app.preview.stop()
	app.screen = app.Screen.MENU
	root.size = dimensions
	DisplayServer.window_set_size(dimensions)
	await settle()
	check(Vector2i(root.get_visible_rect().size) == dimensions, "The native viewport uses the requested dimensions: " + str(dimensions))


func capture_menus() -> void:
	for dimensions: Vector2i in [Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await resize_window(dimensions)
		Input.warp_mouse(Vector2.ZERO)
		var home_motion := InputEventMouseMotion.new()
		home_motion.position = Vector2.ZERO
		home_motion.global_position = Vector2.ZERO
		root.push_input(home_motion, true)
		app.return_to_menu()
		await settle()
		for button: Button in app.shell._navigation_buttons.home:
			if button.is_visible_in_tree():
				button.grab_focus()
				break
		app.shell.stop_preview()
		await settle()
		check(not app.preview.active and not app.shell._preview_panel.visible, "Home captures remain clear of earlier hover and keyboard preview focus.")
		await capture("menu_home", {"kind": "menu", "page": "home", "data_origin": "isolated_QA_profile_empty_history", "preview_active": app.preview.active, "pointer_px": _portable(root.get_mouse_position())})
		app.shell.show_preparation("EX04")
		await settle()
		await capture("menu_preparation", {"kind": "menu", "page": "preparation", "program_id": "EX04", "difficulty": "standard", "data_origin": "native_catalogue"})
		app.shell.show_settings(app.profile)
		await settle()
		await capture("menu_settings", {"kind": "menu", "page": "settings", "data_origin": "isolated_QA_profile"})
		app.shell.show_history([])
		await settle()
		await capture("menu_history", {"kind": "menu", "page": "history", "data_origin": "empty_history_no_fixture_scores"})
		app.shell.show_calibration(app._calibration_ui_state())
		await settle()
		await capture("menu_calibration", {"kind": "menu", "page": "calibration", "data_origin": "actual_controller_service_state"})
		app.shell.show_home()
		await settle()
		var trigger: Button = app.shell._catalog_buttons.EX04
		Ui.ensure_control_visible(app.shell.content_scroll, trigger)
		await settle()
		var motion := InputEventMouseMotion.new()
		motion.position = trigger.get_global_rect().get_center()
		motion.global_position = motion.position
		root.push_input(motion, true)
		await settle()
		check(app.preview.active and app.preview.engine.program.program_id == "EX04", "Hover starts the actual V2 engine preview.")
		check(app.preview.clip_contents and app.shell.preview_host.get_global_rect().grow(0.5).encloses(app.preview.get_global_rect()), "The preview renderer remains clipped inside its native host.")
		check(root.get_visible_rect().grow(0.5).encloses(app.preview.get_global_rect()), "The hover preview is visible inside the actual window at every menu dimension.")
		var preview_info: Dictionary = {"kind": "preview", "page": "hover", "program_id": "EX04", "difficulty": "standard",
			"data_origin": "unmeasured_native_engine_preview", "seed_hex": app.preview.engine.session_seed_hex,
			"preview_elapsed_s": app.preview.engine.elapsed_s, "host_rect_px": _portable(app.shell.preview_host.get_global_rect()),
			"renderer_rect_px": _portable(app.preview.get_global_rect()), "render_resolution_px": [app.preview.viewport.size.x, app.preview.viewport.size.y],
			"clip_contents": app.preview.clip_contents, "snapshot": _portable(app.preview.engine.snapshot())}
		app.preview.paused = true
		await capture("hover_preview", preview_info)
		app.preview.stop()
		check(app.store.history().is_empty(), "Menu and preview captures never become practice history.")


func capture_programs() -> void:
	await resize_window(Vector2i(1920, 1080))
	for program_index in 8:
		var program_id := "EX%02d" % (program_index + 1)
		var definition := Catalog.find(program_id, "standard")
		for phase: Dictionary in definition.phases:
			await capture_practice(program_id, "standard", float(phase.start_s) + minf(1.5, float(phase.duration_s) * 0.5), "standard_" + str(phase.id))
		for difficulty: String in ["novice", "advanced"]:
			await capture_practice(program_id, difficulty, 1.5, difficulty + "_sample")
	app.screen = app.Screen.MENU
	app.return_to_menu(false)
	app.shell.show_results(app.engine.report())
	await settle()
	await capture("menu_results_no_input", {"kind": "menu", "page": "results", "data_origin": "native_engine_no_input_frozen_clock", "report": _portable(app.engine.report())})


func capture_practice(program_id: String, difficulty: String, sample_s: float, suffix: String) -> void:
	app.screen = app.Screen.MENU
	app.return_to_menu()
	app.start_practice(program_id, difficulty)
	app.set_process(false)
	check(app.screen == app.Screen.COUNTDOWN and not app.engine.program.is_empty(), "MainV2 prepares the actual practice definition: " + program_id + "/" + difficulty)
	var definition := Catalog.find(program_id, difficulty)
	check(app.engine.start(definition, SEED_HEX, app.actual_conditions()), "The visual fixture uses the real seeded engine.")
	app.screen = app.Screen.PRACTICE
	app.arena.show()
	app.hud.show_pause(false)
	app.hud.show_countdown(0.0)
	app.arena.set_pose(0.0, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await advance_with_render_receipts(sample_s)
	if app.engine.snapshot().is_empty() and app.engine.phase.mechanic == "opportunity":
		for step_index in 160:
			await advance_with_render_receipts(sample_s + float(step_index + 1) * 0.025)
			if not app.engine.snapshot().is_empty():
				break
	check(app.engine.invalid_reason.is_empty(), "Visual sampling preserves the runtime's render-onset contract: " + str(app.engine.invalid_reason))
	var intended_phase: Dictionary = definition.phases[0]
	for phase: Dictionary in definition.phases:
		if sample_s >= float(phase.start_s):
			intended_phase = phase
	check(app.engine.phase.id == intended_phase.id, "The saved frame belongs to its requested phase: " + suffix)
	app._pause_active_s = app.engine.elapsed_s
	app._clock_origin_us = Time.get_ticks_usec() - int(round(app.engine.elapsed_s * 1000000.0))
	app.screen = app.Screen.PRACTICE
	app.arena.show()
	app.arena.set_pose(0.0, 0.0)
	app.arena.prepare(app.engine.snapshot(), app.engine.elapsed_s)
	app.hud.show_pause(false)
	app.hud.show_countdown(0.0)
	app.hud.show()
	app._present_practice()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await settle()
	app.engine.mark_rendered(app.arena.prepared_identities, app.arena.visibly_drawn_identities, app.engine.elapsed_s, true, app.arena.prepared_receipt)
	last_projection_checks = projection_checks(app.arena)
	var info: Dictionary = {"kind": "practice", "data_origin": "native_engine_no_input_frozen_clock", "clock_mode": "explicit_active_time_sample",
		"program_id": program_id, "difficulty": difficulty, "phase_id": app.engine.phase.id, "elapsed_s": app.engine.elapsed_s,
		"seed_hex": SEED_HEX, "definition_sha256": Catalog.fingerprint(definition), "conditions": app.actual_conditions(),
		"snapshot": _portable(app.engine.snapshot()), "target_projections": _portable(app.arena.target_projections), "projection_checks": last_projection_checks,
		"prepared_receipt": _portable(app.arena.prepared_receipt), "frame_post_draw_observed": true}
	await capture("practice_" + program_id + "_" + suffix, info, true)
	if program_id == "EX08" and difficulty == "advanced":
		app.pause_practice("visual_fixture_pause")
		await settle()
		await capture("practice_pause", {"kind": "pause", "data_origin": "native_engine_no_input_frozen_clock"})
		app.hud.show_pause(false)


func advance_with_render_receipts(sample_s: float) -> void:
	while app.engine.elapsed_s < sample_s and not app.engine.completed:
		var snapshot: Array = app.engine.snapshot()
		if app.engine.phase.mechanic == "opportunity" and not snapshot.is_empty():
			app.arena.prepare(snapshot, app.engine.elapsed_s)
			app._present_practice()
			await RenderingServer.frame_post_draw
			app.engine.mark_rendered(app.arena.prepared_identities, app.arena.visibly_drawn_identities, app.engine.elapsed_s, true, app.arena.prepared_receipt)
		var next_s := sample_s
		if app.engine.phase.mechanic == "opportunity":
			next_s = minf(next_s, float(app.engine.phase.start_s) + float(app.engine.phase.duration_s))
			for target: Dictionary in app.engine.targets.values():
				if target.expiry_s != null:
					next_s = minf(next_s, float(target.expiry_s))
			if app.engine._schedule_index < app.engine._scheduled.size():
				next_s = minf(next_s, float(app.engine._scheduled[app.engine._schedule_index].born_s))
		app.engine.advance(next_s)


func projection_checks(arena: Node3D) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var eye := Vector3(0.0, Geometry.EYE_HEIGHT_M, 0.0)
	for target: Dictionary in arena.prepared_snapshot:
		var pose: Dictionary = target.pose
		var projected: Dictionary = arena.project_sphere(pose, arena.logical_yaw_deg, arena.logical_pitch_deg, float(arena.camera.fov), arena.prepared_viewport_size)
		if not bool(projected.get("visible", false)):
			continue
		var offset: Array = pose.center_offset_m
		var position := eye + Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		var center_error: float = arena.camera.unproject_position(position).distance_to(projected.center_px)
		var direction: Array = Geometry.normalized(offset)
		var first_basis: Array = Geometry.normalized(Geometry.cross([0.0, 1.0, 0.0], direction))
		var second_basis: Array = Geometry.normalized(Geometry.cross(direction, first_basis))
		var sine_radius: float = float(pose.radius_m) / Geometry.norm(offset)
		var cosine_radius := sqrt(1.0 - sine_radius * sine_radius)
		var maximum_error := center_error
		for point_index in projected.contour_px.size():
			var angle_rad := TAU * float(point_index) / float(projected.contour_px.size())
			var tangent: Array = []
			for axis in 3:
				tangent.append(float(direction[axis]) * cosine_radius + (float(first_basis[axis]) * cos(angle_rad) + float(second_basis[axis]) * sin(angle_rad)) * sine_radius)
			var world_point := eye + Vector3(float(tangent[0]), float(tangent[1]), float(tangent[2]))
			maximum_error = maxf(maximum_error, arena.camera.unproject_position(world_point).distance_to(projected.contour_px[point_index]))
		check(maximum_error <= PROJECTION_TOLERANCE_PX, "Camera projection differs from the same V2Geometry tangent source by at most 0.5 px: " + str(target.identity))
		results.append({"identity": target.identity, "center_error_px": center_error, "maximum_contour_error_px": maximum_error, "contour_point_count": projected.contour_px.size()})
	check(not results.is_empty(), "The practice frame contains actual projected targets.")
	return results


func capture_calibration_fixtures() -> void:
	await resize_window(Vector2i(1280, 720))
	app.screen = app.Screen.MENU
	app.return_to_menu()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES_PATH))
	var selections: Dictionary = {"repeated_improvement": "repeated_improvement", "repeated_regression": "repeated_regression",
		"mixed_tradeoff": "mixed_tradeoff", "close_observed": "close_observed", "opposite_days": "undetermined",
		"missing_second_day": "incomplete", "technical_blocker": "unstable_conditions", "exploratory_only": "exploratory_only"}
	for fixture_name: String in selections:
		var fixture: Dictionary = document.fixtures[fixture_name]
		var result := Calibration.compare(fixture)
		check(result.get("status", "") == selections[fixture_name], "The native CAL calculator reproduces the supplied kit fixture: " + fixture_name)
		var state := _calibration_fixture_state(fixture, result)
		app.shell.show_calibration(state)
		app.shell.set_notice("Exemple synthétique du kit V2 · aucune mesure utilisateur")
		marker_label.text = "FIXTURE CAL SYNTHÉTIQUE · " + fixture_name + " · aucune mesure utilisateur"
		await settle()
		var information: Dictionary = {"kind": "calibration_fixture", "synthetic": true,
			"data_origin": fixture.data_origin, "fixture_name": fixture_name, "fixture_source": FIXTURES_PATH.trim_prefix("res://"),
			"fixture_source_sha256": FileAccess.get_sha256(FIXTURES_PATH), "fixture_semantic_sha256": Canonical.semantic_sha256(fixture),
			"status": result.get("status", ""), "native_calculation": result, "display_state": state, "view": "summary"}
		await capture("cal_fixture_" + fixture_name, information)
		Ui.ensure_control_visible(app.shell.content_scroll, app.shell.calibration_apply_button)
		await settle()
		check(app.shell.calibration_apply_button.disabled, "A synthetic CAL fixture never authorizes applying its displayed candidate.")
		information.view = "decision_details"
		information.scroll_offset_px = app.shell.content_scroll.scroll_vertical
		await capture("cal_fixture_" + fixture_name + "_details", information)
	marker_label.text = "CAPTURE QA V2 · aucune mesure utilisateur"
	app.shell.set_notice("")


func _calibration_fixture_state(fixture: Dictionary, result: Dictionary) -> Dictionary:
	var candidate: Dictionary = {}
	for gain: Dictionary in fixture.get("gains", []):
		if gain.candidate_id != "A":
			candidate = gain.duplicate(true)
			break
	return {"result": result.duplicate(true), "candidate": candidate, "plan_id": "fixture_" + str(fixture.fixture_name),
		"can_apply": false, "can_continue": false, "can_start_confirmation": false, "profile_locked": true,
		"notice": "Exemple synthétique du kit V2 · aucune mesure utilisateur"}


func capture(caption: String, information: Dictionary, validate_body: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if not check(picture != null and not picture.is_empty(), "The actual native viewport returns pixels: " + caption):
		return
	picture.convert(Image.FORMAT_RGBA8)
	var dimensions := picture.get_size()
	var filename := "v2_%dx%d_%s.png" % [dimensions.x, dimensions.y, caption]
	var path := run_directory.path_join(filename)
	check(picture.save_png(path) == OK, "The fresh native capture is saved: " + filename)
	var record := information.duplicate(true)
	record.merge({"file": filename, "sha256": FileAccess.get_sha256(path), "byte_count": FileAccess.get_file_as_bytes(path).size(),
		"dimensions_px": [dimensions.x, dimensions.y], "scene": "scenes/app/MainV2.tscn", "capture_utc": Time.get_datetime_string_from_system(true)}, true)
	if validate_body:
		record.body_color_checks = body_color_checks(picture)
	records.append(record)


func body_color_checks(picture: Image) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for projected: Dictionary in app.arena.target_projections:
		var center: Vector2 = projected.center_px
		var matching: Array = []
		var observed: Dictionary = {}
		var bounds: Rect2 = projected.bounds_px
		var probe_extent := clampi(floori(minf(bounds.size.x, bounds.size.y) * 0.25), 1, 12)
		for offset_y in range(-probe_extent, probe_extent + 1):
			for offset_x in range(-probe_extent, probe_extent + 1):
				var pixel := Vector2i(floori(center.x), floori(center.y)) + Vector2i(offset_x, offset_y)
				if pixel.x < 0 or pixel.y < 0 or pixel.x >= picture.get_width() or pixel.y >= picture.get_height():
					continue
				var color := picture.get_pixelv(pixel).to_html(false)
				observed[color] = true
				if color == "42d9cb":
					matching.append([pixel.x, pixel.y])
		check(not matching.is_empty(), "Exported PNG target interiors have exact sRGB #42D9CB: " + str(projected.identity) + " observed " + str(observed.keys()))
		samples.append({"identity": projected.identity, "expected_srgb_hex": "42d9cb", "matching_pixels_px": matching, "observed_srgb_hex": observed.keys()})
	return samples


func _manifest() -> Dictionary:
	return {"schema_version": "aimlocal.visuals.manifest.v2.0", "app_version": "1.0.0", "run_id": run_id,
		"generated_utc": Time.get_datetime_string_from_system(true), "draft": not publish_current, "scene": "scenes/app/MainV2.tscn", "artifact_origin": "native_source_scene_not_exported_binary",
		"project_config_app_version": ProjectSettings.get_setting("application/config/version", ""),
		"catalogue_revision": Catalog.REVISION, "catalogue_file_sha256": FileAccess.get_sha256(Catalog.CATALOGUE_PATH),
		"catalogue_semantic_sha256": Canonical.semantic_sha256(Catalog.load_catalog()), "definition_sha256": definitions,
		"protocol_id": Calibration.PROTOCOL_ID, "protocol_sha256": Calibration.protocol_hash(), "protocol_file_sha256": FileAccess.get_sha256(Calibration.PROTOCOL_PATH),
		"source_sha256": source_hashes, "renderer": RenderingServer.call("get_current_rendering_method") if RenderingServer.has_method("get_current_rendering_method") else "unavailable",
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(), "video_adapter": RenderingServer.get_video_adapter_name(),
		"video_adapter_vendor": RenderingServer.get_video_adapter_vendor(), "display_server": DisplayServer.get_name(), "os": OS.get_name(),
		"engine_version": Engine.get_version_info().string, "render_scale": 1.0, "msaa_3d": root.msaa_3d,
		"projection_tolerance_px": PROJECTION_TOLERANCE_PX, "projection_check_scope": "analytic_tangent_points_vs_camera_unproject_not_raster_edge_error",
		"body_color_srgb_hex": "42d9cb", "fixture_source_sha256": FileAccess.get_sha256(FIXTURES_PATH),
		"store_isolated": true, "measured_player_data": false, "assertions": assertion_count, "failures": failure_count, "captures": records}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if check(file != null, "Metadata is writable: " + path):
		file.store_string(JSON.stringify(_portable(data), "\t", true, true) + "\n")


func _portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is Rect2 or value is Rect2i:
		return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is PackedVector2Array:
		var points: Array = []
		for point in value:
			points.append([point.x, point.y])
		return points
	if value is Array:
		var elements: Array = []
		for element: Variant in value:
			elements.append(_portable(element))
		return elements
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key)] = _portable(value[key])
		return result
	return value
