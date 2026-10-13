extends SceneTree

const MainScene := preload("res://scenes/app/MainV2.tscn")
const Store := preload("res://scripts/v2/v2_store.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const SOURCE_CM_PER_360: float = 35.0000000007
const FRAME_DELTA_S: float = 1.0 / 144.0
const MAX_REPORTED_FAILURES: int = 30

var assertion_count: int = 0
var failure_count: int = 0
var unrun_input_routes: int = 0
var roots: Array[String] = []
var input_capture_available: bool = false
var saved_max_fps: int = 0
var saved_accumulation: bool = false
var saved_mouse_mode: Input.MouseMode


func _initialize() -> void:
	saved_max_fps = Engine.max_fps
	saved_accumulation = Input.use_accumulated_input
	saved_mouse_mode = Input.mouse_mode
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("V2 APP FLOW did not finish its bounded controller routes in 90 seconds.")
		quit(1))
	run_suite.call_deferred()


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		if failure_count <= MAX_REPORTED_FAILURES:
			push_error("V2 APP FLOW: " + description)


func settle() -> void:
	await process_frame
	await process_frame


func make_app() -> V2AppController:
	var test_root: String = "/tmp/aimlocal-v2-app-flow-" + Crypto.new().generate_random_bytes(12).hex_encode()
	roots.append(test_root)
	var test_store := Store.new(test_root.path_join("v2"))
	var source_profile: Dictionary = Store.default_profile()
	var source_gain: float = 914.4 / (float(source_profile.dpi) * SOURCE_CM_PER_360)
	source_profile.cm_per_360 = SOURCE_CM_PER_360
	source_profile.gain_deg_per_relative_unit = source_gain
	source_profile.gain_hex = Canonical.float64_hex(source_gain)
	source_profile.sound_enabled = false
	check(test_store.save_profile(source_profile), "The isolated source profile must be durable before MainV2._ready: " + test_store.last_error)
	var app: V2AppController = MainScene.instantiate()
	app.store = test_store
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.preview.set_process(false)
	app.preview.paused = true
	if RenderingServer.frame_post_draw.is_connected(app._post_draw):
		RenderingServer.frame_post_draw.disconnect(app._post_draw)
	check(app.store == test_store and app.store.root_path.begins_with(test_root), "MainV2 must keep the V2Store injected before add_child.")
	check(Canonical.float64_hex(app.profile.cm_per_360) == Canonical.float64_hex(SOURCE_CM_PER_360) and app.profile.gain_hex == source_profile.gain_hex, "MainV2 loads 35.0000000007 cm and its source gain bits exactly.")
	return app


func dispose_app(app: V2AppController) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app.queue_free()
	await settle()


func run_suite() -> void:
	print("V2 APP FLOW scope: actual MainV2 scene, native UI signals, isolated V2Store, synthetic clock/callbacks; no measured player data or physical HID/scanout validation.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	input_capture_available = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("V2 APP FLOW display=%s capture_available=%s" % [DisplayServer.get_name(), str(input_capture_available)])
	await test_catalogue_and_profile()
	await test_high_fov_profiles()
	await test_physical_size_fov_gate()
	await test_profile_persistence_protection()
	await test_practice_pause_focus_and_save()
	await test_settings_abort_routes()
	await test_render_generation_identity()
	if input_capture_available:
		await test_controller_input_queue()
		await test_held_button_arming()
	else:
		unrun_input_routes += 2
		print("V2 APP FLOW LIMITATION: this display backend cannot retain captured mouse mode; controller screen_relative/fire input routes remain unrun. Countdown, lifecycle, UI/profile/store and render-identity callbacks still execute.")
	Engine.max_fps = saved_max_fps
	Input.use_accumulated_input = saved_accumulation
	Input.mouse_mode = saved_mouse_mode
	print("V2 APP FLOW: %d assertions, %d failures, %d input routes unrun; isolated roots=%s" % [assertion_count, failure_count, unrun_input_routes, str(roots)])
	quit(0 if failure_count == 0 else 1)


func visible_targets(app: V2AppController) -> int:
	var visible_count: int = 0
	for target: MeshInstance3D in app.arena.target_nodes:
		if target.visible:
			visible_count += 1
	return visible_count


func identities(app: V2AppController) -> Array:
	var values: Array = []
	for target: Dictionary in app.engine.snapshot():
		values.append(target.identity)
	return values


func advance_countdown(app: V2AppController, elapsed_s: float) -> void:
	app._countdown_origin_us = Time.get_ticks_usec() - int(round(elapsed_s * 1000000.0))
	app._process(FRAME_DELTA_S)


func advance_practice(app: V2AppController, elapsed_s: float) -> void:
	app._clock_origin_us = Time.get_ticks_usec() - int(round(elapsed_s * 1000000.0))
	app._process(FRAME_DELTA_S)


func enter_practice(app: V2AppController, program_id: String = "EX01", difficulty: String = "standard") -> void:
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.start_practice(program_id, difficulty)
	check(app.screen == app.Screen.COUNTDOWN, "Controller.start_practice prepares a countdown for " + program_id + "/" + difficulty)
	if app.screen != app.Screen.COUNTDOWN:
		return
	check(visible_targets(app) == 0 and app.arena.prepared_identities.is_empty(), "Countdown has no active rendered target body or prepared identity.")
	check(app.engine.elapsed_s == 0.0 and app.engine.pose_event_count == 0, "Countdown contributes neither active time nor a scored received pose.")
	advance_countdown(app, 2.0)
	check(app.screen == app.Screen.COUNTDOWN and app.engine.elapsed_s == 0.0 and visible_targets(app) == 0, "Two countdown seconds cannot start the 60-second clock or expose scored targets.")
	advance_countdown(app, 3.1)
	check(app.screen == app.Screen.PRACTICE and app.engine.duration_s == 60.0, "After the full three seconds, the actual controller enters fixed 60-second practice.")


func report_for(store: V2Store, session_id: String) -> Dictionary:
	for row: Dictionary in store.history():
		if row.namespace == "v2" and row.report.session_id == session_id:
			return row.report
	return {}


func diagnose_missing_report(app: V2AppController) -> void:
	if app._last_report.is_empty():
		print("V2 APP FLOW REPORT DIAGNOSTIC: controller has no final report.")
		return
	var nonstring_keys: Array = []
	for key: Variant in app._last_report:
		if not key is String:
			nonstring_keys.append(str(key) + ":" + str(typeof(key)))
	var save_ok: bool = app.store.save_report(app._last_report)
	print("V2 APP FLOW REPORT DIAGNOSTIC: retry_same_controller_report=%s error=%s canonical_error=%s nonstring_root_keys=%s" % [str(save_ok), app.store.last_error, Canonical.encode(app._last_report).error, str(nonstring_keys)])
	print("V2 APP FLOW REPORT KEY PATHS: " + str(nonstring_key_paths(app._last_report, "report").slice(0, 24)))


func nonstring_key_paths(value: Variant, path: String) -> Array:
	var paths: Array = []
	if value is Dictionary:
		for key: Variant in value:
			var child_path: String = path + "." + str(key)
			if not key is String:
				paths.append(child_path)
			paths.append_array(nonstring_key_paths(value[key], child_path))
	elif value is Array:
		for index: int in value.size():
			paths.append_array(nonstring_key_paths(value[index], path + "[%d]" % index))
	return paths


func check_report_integrity(report: Dictionary, route: String) -> void:
	var encoded: Dictionary = Canonical.encode(report)
	check(encoded.ok, route + " must already be strict-canonical JSON without test-side normalization: " + str(encoded.error))
	check(nonstring_key_paths(report, "report").is_empty(), route + " has only String keys recursively, including phase metrics and render receipts.")
	var report_hash: String = Canonical.semantic_sha256(report)
	check(report_hash.length() == 64 and report_hash.is_valid_hex_number(), route + " has a nonempty semantic SHA-256 before persistence.")
	var raw_manifest: Variant = report.get("manifest")
	check(raw_manifest is Array and not raw_manifest.is_empty(), route + " contains actual generated target manifests, not an empty hash proof.")
	if not raw_manifest is Array:
		return
	var manifest: Array = raw_manifest
	var manifest_hash: String = Canonical.semantic_sha256(manifest)
	check(manifest_hash.length() == 64 and report.get("manifest_hash") == manifest_hash, route + " retains the exact canonical manifest SHA-256.")
	for entry: Dictionary in manifest:
		var motion_hash: Variant = entry.get("compiled_motion_hash")
		check(motion_hash is String and motion_hash.length() == 64 and motion_hash.is_valid_hex_number(), route + " has a nonempty compiled-motion SHA-256 for " + str(entry.get("identity", "missing_identity")))
	print("V2 APP FLOW REPORT INTEGRITY: %s canonical=%s semantic_sha256=%s manifest_entries=%d" % [route, str(encoded.ok), report_hash, manifest.size()])


func check_live_motion_hashes(app: V2AppController) -> void:
	check(not app.engine.targets.is_empty(), "The motion-hash proof uses actual live controller targets.")
	for target: Dictionary in app.engine.targets.values():
		var expected_hash: String = Canonical.semantic_sha256(Canonical.json_ready(target.motion))
		var matching_entry: Dictionary = {}
		for entry: Dictionary in app.engine.manifest:
			if entry.identity == target.identity:
				matching_entry = entry
				break
		check(expected_hash.length() == 64 and matching_entry.get("compiled_motion_hash") == expected_hash, "The actual target's portable compiled motion matches its manifest SHA-256: " + str(target.identity))


func check_public_readiness(app: V2AppController) -> void:
	check(app.shell._ready_states.size() == 24, "Native catalogue navigation must retain all 24 actual viewport/FOV readiness decisions after profile Apply.")
	var mismatches: Array[String] = []
	for definition: Dictionary in app.catalogue.programs:
		var key: String = str(definition.program_id) + ":" + str(definition.difficulty)
		var state: Dictionary = app.shell._ready_states.get(key, {})
		if not state.has("ready") or bool(state.ready) != app._program_fits(definition):
			mismatches.append(key)
	check(mismatches.is_empty(), "Native readiness agrees with the actual frozen profile and viewport for every configuration: " + str(mismatches))


func apply_fov_from_ui(app: V2AppController, vertical_fov_deg: float) -> void:
	app.shell._navigation_buttons.settings[0].pressed.emit()
	await settle()
	check(app.screen == app.Screen.MENU and app.shell.current_page == "settings", "The native Settings navigation opens profile editing before changing FOV.")
	app.shell.profile_fields.vertical_fov_deg.value = vertical_fov_deg
	check(not app.shell.profile_apply_button.disabled, "An accepted FOV edit enables native Apply.")
	app.shell.profile_apply_button.pressed.emit()
	await settle()
	var restored: Dictionary = Store.new(app.store.root_path).load_profile()
	check(app.profile.vertical_fov_deg == vertical_fov_deg and app.arena.camera.fov == vertical_fov_deg and restored.vertical_fov_deg == vertical_fov_deg, "Native Apply commits the accepted FOV to controller, camera and actual V2Store.")
	check(Canonical.float64_hex(app.profile.cm_per_360) == Canonical.float64_hex(SOURCE_CM_PER_360) and app.profile.gain_hex == restored.gain_hex and Canonical.float64_hex(app.gain_deg_per_relative_unit) == restored.gain_hex, "Changing only FOV preserves the IEEE baseline and applied gain bits.")
	app.shell._navigation_buttons.home[0].pressed.emit()
	await settle()
	check(app.shell.current_page == "home", "The actual Training navigation returns from accepted profile Apply to the native catalogue.")
	check_public_readiness(app)


func open_depth_preparation(app: V2AppController) -> void:
	app.shell._navigation_buttons.home[0].pressed.emit()
	await settle()
	app.shell._catalog_buttons.EX07.pressed.emit()
	await settle()
	app.shell.level_buttons[2].pressed.emit()
	await settle()
	check(app.shell.current_page == "preparation" and app.shell.selected_program_id == "EX07" and app.shell.selected_difficulty == "advanced", "Native card and level controls prepare the fixed EX07 advanced definition.")


func required_depth_fov_deg(stage: Dictionary, aspect: float, nearest_size: bool) -> float:
	var angular_radius_rad: float = deg_to_rad(float(stage.diameter_deg) * 0.5)
	if nearest_size:
		var physical_radius_m: float = float(stage.size.reference_distance_m) * sin(angular_radius_rad)
		angular_radius_rad = asin(physical_radius_m / float(stage.envelope.center_distance_m[0]))
	var required_half_rad: float = 0.0
	for yaw_deg: float in stage.envelope.center_yaw_deg:
		for pitch_deg: float in stage.envelope.center_pitch_deg:
			var yaw_rad: float = deg_to_rad(absf(yaw_deg))
			var pitch_rad: float = deg_to_rad(absf(pitch_deg))
			var horizontal_half_rad: float = yaw_rad + asin(sin(angular_radius_rad) / cos(pitch_rad))
			var forward_component: float = cos(yaw_rad) * cos(pitch_rad)
			var vertical_component: float = sin(pitch_rad)
			var vertical_half_rad: float = atan2(vertical_component, forward_component) + asin(sin(angular_radius_rad) / sqrt(forward_component * forward_component + vertical_component * vertical_component))
			required_half_rad = maxf(required_half_rad, maxf(atan(tan(horizontal_half_rad) / aspect), vertical_half_rad))
	return rad_to_deg(2.0 * required_half_rad)


func test_catalogue_and_profile() -> void:
	var app: V2AppController = await make_app()
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/app/MainV2.tscn", "The public product entrypoint must be the actual MainV2 scene.")
	check(app.screen == app.Screen.MENU and app.shell.current_page == "home" and app.shell.visible and not app.arena.visible and not app.hud.visible, "MainV2 boots into the native catalogue without an active arena.")
	check(app.profile.max_fps == 144 and not Input.use_accumulated_input, "The accepted default is 144 FPS with input accumulation disabled.")
	check(app.shell.catalog_grid.get_child_count() == 8 and app.shell.program_definitions.size() == 8 and app.catalogue.programs.size() == 24, "MainV2 exposes exactly eight public cards and 24 complete configurations.")
	var public_ids: Array = app.shell.program_definitions.keys()
	public_ids.sort()
	check(public_ids == ["EX01", "EX02", "EX03", "EX04", "EX05", "EX06", "EX07", "EX08"], "Legacy exercises and CAL tasks cannot become extra public cards.")
	for program_id: String in public_ids:
		var levels: Dictionary = app.shell.program_definitions[program_id]
		check(levels.size() == 3, "Every actual controller card owns exactly three difficulty definitions: " + program_id)
		for difficulty: String in ["novice", "standard", "advanced"]:
			check(levels.has(difficulty) and float(levels[difficulty].duration_s) == 60.0, "Every public configuration fixes 60 seconds: " + program_id + "/" + difficulty)
	check(app.store.history().is_empty(), "The real catalogue and previews cannot manufacture saved practice results.")
	app.shell._catalog_buttons.EX01.pressed.emit()
	await settle()
	check(app.shell.current_page == "preparation" and app.shell.level_buttons.size() == 3, "The native catalogue button opens the actual three-level preparation page.")
	var ready: bool = app.shell.start_button != null and not app.shell.start_button.disabled
	check(ready, "COUNTEREXAMPLE START_READINESS: MainV2 must authorize its loaded definition/viewport so the public Start button is enabled; current ready_states=" + str(app.shell._ready_states))
	if app.shell.start_button != null:
		app.shell.start_button.pressed.emit()
	check(app.screen == app.Screen.COUNTDOWN, "COUNTEREXAMPLE PUBLIC_START_ROUTE: preparation -> native Start signal must reach the actual controller countdown.")
	if app.screen != app.Screen.MENU:
		app.return_to_menu()
	app.shell.show_settings(app.profile)
	await settle()
	var source_gain_hex: String = app.profile.gain_hex
	var source_cm_hex: String = Canonical.float64_hex(app.profile.cm_per_360)
	var distance: SpinBox = app.shell.profile_fields.cm_per_360
	distance.call("begin_edit")
	await settle()
	distance.call("finish_edit")
	await settle()
	check(Canonical.float64_hex(app.shell.draft_profile().cm_per_360) == source_cm_hex, "Focusing/blurring the rounded native UI keeps the exact 35.0000000007 cm value.")
	app.save_profile(app.profile.duplicate(true))
	check(app.profile.gain_hex == source_gain_hex and Canonical.float64_hex(app.profile.gain_deg_per_relative_unit) == source_gain_hex and Canonical.float64_hex(app.profile.cm_per_360) == source_cm_hex, "Controller.save_profile with unchanged inputs preserves the entire IEEE-754 baseline.")
	app.shell.profile_fields.sound_enabled.set_pressed(true)
	check(not app.shell.profile_apply_button.disabled, "A cosmetic edit enables the real profile Apply button.")
	app.shell.profile_apply_button.pressed.emit()
	var reloaded: Dictionary = Store.new(app.store.root_path).load_profile()
	check(app.profile.sound_enabled and app.profile.gain_hex == source_gain_hex and reloaded.gain_hex == source_gain_hex and Canonical.float64_hex(reloaded.cm_per_360) == source_cm_hex, "Native Apply reaches controller persistence without replacing the unedited baseline from rounded text.")
	app.shell.profile_fields.cm_per_360.value = 28.0
	check(not app.shell.profile_apply_button.disabled, "A real numeric UI edit enables Apply.")
	app.shell.profile_apply_button.pressed.emit()
	var expected_gain_hex: String = Canonical.float64_hex(914.4 / (800.0 * 28.0))
	reloaded = Store.new(app.store.root_path).load_profile()
	check(app.profile.cm_per_360 == 28.0 and app.profile.gain_hex == expected_gain_hex and Canonical.float64_hex(app.gain_deg_per_relative_unit) == expected_gain_hex and reloaded.gain_hex == expected_gain_hex, "Changing cm/360 through the native UI updates camera gain bits and the actual durable profile.")
	var conditions: Dictionary = app.actual_conditions()
	check(conditions.gain_hex == app.profile.gain_hex and conditions.declared_dpi == 800 and conditions.render_resolution_px == [int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y)], "Actual conditions come from the controller's accepted baseline and real viewport.")
	if DisplayServer.get_name() == "headless":
		check(conditions.display_hz_declared == -1.0, "Headless reports unavailable actual display refresh; it cannot fabricate a real CAL profile.")
	check(app.engine.program.is_empty() or app.engine.completed, "Profile editing cannot leave an active practice engine behind.")
	await dispose_app(app)


func test_high_fov_profiles() -> void:
	var app: V2AppController = await make_app()
	var source_gain_hex: String = app.profile.gain_hex
	var catalogue_hash: String = Canonical.semantic_sha256(app.catalogue)
	var depth_definition: Dictionary = V2Catalog.find("EX07", "advanced")
	var definition_hash: String = Canonical.semantic_sha256(depth_definition)
	for vertical_fov_deg: float in [90.0, 110.0]:
		await apply_fov_from_ui(app, vertical_fov_deg)
		check(app.profile.gain_hex == source_gain_hex and Canonical.semantic_sha256(app.catalogue) == catalogue_hash, "A high-FOV profile never adapts baseline gain or catalogue target sizes.")
		await open_depth_preparation(app)
		check(app._program_fits(depth_definition) and not app.shell.start_button.disabled, "A fitting high-FOV EX07 profile enables genuine native Start.")
		app.shell.start_button.pressed.emit()
		check(app.screen == app.Screen.COUNTDOWN and visible_targets(app) == 0, "Native high-FOV Start reaches a target-free countdown.")
		if app.screen == app.Screen.COUNTDOWN:
			advance_countdown(app, 3.1)
			check(app.screen == app.Screen.PRACTICE and app.engine.conditions.vertical_fov_deg == vertical_fov_deg and app.engine.conditions.gain_hex == source_gain_hex and app.engine.duration_s == 60.0, "The native high-FOV practice freezes the accepted FOV, baseline bits and 60-second duration.")
			check(Canonical.semantic_sha256(app.engine.program) == definition_hash, "High FOV cannot rewrite the scored definition or compensate its physical target size.")
			app.pause_practice("manual_pause")
			app.hud.menu_button.pressed.emit()
			check(app.screen == app.Screen.MENU and app.shell.current_page == "home", "The real pause Menu route exits high-FOV practice before another profile edit.")
	app.shell._navigation_buttons.settings[0].pressed.emit()
	await settle()
	var accepted_profile: Dictionary = app.profile.duplicate(true)
	var profile_path: String = app.store.root_path.path_join("profile.json")
	var accepted_bytes: PackedByteArray = FileAccess.get_file_as_bytes(profile_path)
	for invalid_fov_deg: float in [110.1, 179.0]:
		app.shell.profile_fields.vertical_fov_deg.value = invalid_fov_deg
		check(not app.shell.profile_apply_button.disabled, "The native FOV input can submit an out-of-profile-range value for real store validation.")
		app.shell.profile_apply_button.pressed.emit()
		check(app.profile == accepted_profile and app.arena.camera.fov == accepted_profile.vertical_fov_deg and FileAccess.get_file_as_bytes(profile_path) == accepted_bytes, "An excessive FOV is rejected without changing the actual camera, baseline or profile bytes.")
		check(app.shell._notice.contains("PROFILE_INVALID") and app.shell._notice.contains("non enregistré"), "The actual excessive-FOV Apply reports rejection, not a successful profile update.")
	await dispose_app(app)


func test_physical_size_fov_gate() -> void:
	var saved_window_size: Vector2i = root.size
	root.size = Vector2i(800, 900)
	await settle()
	var app: V2AppController = await make_app()
	var conditions: Dictionary = app.actual_conditions()
	var actual_size: Vector2 = app.get_viewport().get_visible_rect().size
	var aspect: float = actual_size.x / actual_size.y
	check(conditions.render_resolution_px == [int(actual_size.x), int(actual_size.y)] and conditions.aspect_ratio == aspect, "Physical-size FOV guards consume the real resized Godot viewport, not a fabricated conditions callback.")
	var definition: Dictionary = V2Catalog.find("EX07", "advanced")
	var stage: Dictionary = definition.phases[0]
	var definition_hash: String = Canonical.semantic_sha256(definition)
	var nominal_fov_deg: float = required_depth_fov_deg(stage, aspect, false)
	var physical_fov_deg: float = required_depth_fov_deg(stage, aspect, true)
	var clipped_fov_deg: float = snappedf((nominal_fov_deg + physical_fov_deg) * 0.5, 0.125)
	var fitting_fov_deg: float = ceil(physical_fov_deg * 8.0) / 8.0 + 0.25
	check(stage.size.mode == "world_radius_constant" and nominal_fov_deg < clipped_fov_deg and clipped_fov_deg < physical_fov_deg and clipped_fov_deg >= 40.0 and fitting_fov_deg <= 110.0, "The native EX07 guard case separates reference diameter from the larger near-distance physical silhouette inside the accepted FOV range.")
	await apply_fov_from_ui(app, clipped_fov_deg)
	await open_depth_preparation(app)
	check(not app._program_fits(definition) and app.shell.start_button.disabled, "EX07 Start is disabled when its nominal diameter fits but its worst physical-size envelope corner clips.")
	check(not app.shell.start_button.tooltip_text.is_empty(), "The real clipped-target preparation explains why Start is unavailable.")
	var session_id: String = app._current_session_id
	var history_size: int = app.store.history().size()
	app.shell.start_button.pressed.emit()
	app.start_practice("EX07", "advanced")
	check(app.screen == app.Screen.MENU and app._current_session_id == session_id and app.engine.targets.is_empty() and visible_targets(app) == 0 and app.store.history().size() == history_size, "Both native Start and the public controller API reject clipped geometry before any clock, target or stored session exists.")
	check(app.shell._notice.contains("coupe les cibles"), "The real controller's envelope guard reports the concrete clipping reason.")
	await apply_fov_from_ui(app, fitting_fov_deg)
	await open_depth_preparation(app)
	check(app._program_fits(definition) and not app.shell.start_button.disabled, "Widening the accepted FOV authorizes the unchanged physical-size definition.")
	root.size = Vector2i(800, 1000)
	await settle()
	check(not app._program_fits(definition), "A later actual aspect-ratio change makes the previously prepared physical silhouette unsafe.")
	app.shell.start_button.pressed.emit()
	app.start_practice("EX07", "advanced")
	check(app.screen == app.Screen.MENU and app._current_session_id == session_id and app.engine.targets.is_empty() and app.store.history().size() == history_size, "Controller Start rechecks actual viewport geometry even when an older preparation authorized another aspect ratio.")
	root.size = Vector2i(800, 900)
	await settle()
	await open_depth_preparation(app)
	app.shell.start_button.pressed.emit()
	check(app.screen == app.Screen.COUNTDOWN and visible_targets(app) == 0, "Restoring a fitting real viewport permits genuine native Start without shrinking the target.")
	if app.screen == app.Screen.COUNTDOWN:
		advance_countdown(app, 3.1)
		check(app.screen == app.Screen.PRACTICE and Canonical.semantic_sha256(app.engine.program) == definition_hash and app.engine.conditions.render_resolution_px == [800, 900], "The authorized practice keeps its immutable scored definition and actual viewport snapshot.")
		var physical_radius_m: float = float(stage.size.reference_distance_m) * sin(deg_to_rad(float(stage.diameter_deg) * 0.5))
		var snapshots: Array = app.engine.snapshot()
		check(not snapshots.is_empty() and absf(float(snapshots[0].pose.radius_m) - physical_radius_m) <= 1e-9, "The live native EX07 target retains its prescribed physical radius after every FOV/aspect guard.")
	await dispose_app(app)
	root.size = saved_window_size
	await settle()


func test_practice_pause_focus_and_save() -> void:
	var app: V2AppController = await make_app()
	enter_practice(app)
	if app.screen != app.Screen.PRACTICE:
		await dispose_app(app)
		return
	advance_practice(app, 0.25)
	check_live_motion_hashes(app)
	var session_id: String = app._current_session_id
	var before_ids: Array = identities(app)
	var before_seed: String = app.engine.session_seed_hex
	var gain_hex: String = app.profile.gain_hex
	app.save_profile({"cm_per_360": 28.0})
	check(app.profile.gain_hex == gain_hex and app.engine.conditions.gain_hex == gain_hex, "An active practice refuses a direct profile change and keeps its frozen conditions.")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	app._input(escape)
	check(app.screen == app.Screen.PAUSED and app.hud._paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not app.engine.fire_held, "Escape pauses the actual controller, opens native HUD controls, and releases capture/fire.")
	var paused_s: float = app.engine.elapsed_s
	check(identities(app) == before_ids and app.engine.pauses.size() == 1, "Pause keeps target generations and records the interruption.")
	app._process(5.0)
	check(app.engine.elapsed_s == paused_s and app.engine.session_seed_hex == before_seed and identities(app) == before_ids, "While paused, real controller processing cannot advance the clock or redraw a new challenge.")
	app.hud.resume_button.pressed.emit()
	check(app.screen == app.Screen.COUNTDOWN and app.engine.elapsed_s == paused_s and visible_targets(app) == 0, "The native Resume button starts a fresh three-second countdown at the saved active instant.")
	advance_countdown(app, 2.0)
	check(app.screen == app.Screen.COUNTDOWN and app.engine.elapsed_s == paused_s, "Resume countdown is excluded from active time.")
	advance_countdown(app, 3.1)
	check(app.screen == app.Screen.PRACTICE and app.engine.elapsed_s == paused_s and identities(app) == before_ids and app.engine.session_seed_hex == before_seed, "Resume preserves clock, generations, and seed instead of restarting practice.")
	advance_practice(app, paused_s + 0.25)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.screen == app.Screen.PAUSED and not app._focus and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The actual focus-out callback pauses and releases capture.")
	app.hud.resume_button.pressed.emit()
	check(app.screen == app.Screen.PAUSED, "A Resume UI event cannot run while application focus is absent.")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(app.screen == app.Screen.PAUSED and app._focus, "Focus return waits for an explicit user resume.")
	app.hud.resume_button.pressed.emit()
	advance_countdown(app, 3.1)
	check(app.screen == app.Screen.PRACTICE and app.engine.pauses.size() == 2, "Explicit focus recovery follows the same countdown and records both interruptions.")
	advance_practice(app, 60.0)
	check(app.screen == app.Screen.MENU and app.shell.current_page == "results" and not app.hud.visible and not app.arena.visible, "The actual 60-second completion returns to a native result page.")
	check(app._last_report.complete and app._last_report.valid and not app._last_report.rank_eligible and app._last_report.pauses.size() == 2, "The actual controller's finalized result marks both pauses/focus loss ineligible before attempting persistence.")
	check_report_integrity(app._last_report, "completed MainV2 result")
	var persisted: Dictionary = report_for(app.store, session_id)
	check(not persisted.is_empty(), "COUNTEREXAMPLE PRACTICE_SAVE: MainV2 completion must commit an actual V2Store report; last_error=" + app.store.last_error)
	if persisted.is_empty():
		diagnose_missing_report(app)
	if not persisted.is_empty():
		check_report_integrity(persisted, "completed V2Store result")
		check(Canonical.semantic_sha256(persisted) == Canonical.semantic_sha256(app._last_report), "The finalized controller report round-trips through V2Store with the same semantic SHA-256.")
		check(persisted.complete and persisted.valid and not persisted.rank_eligible and persisted.pauses.size() == 2, "A complete paused/focus-interrupted practice remains diagnostic and ineligible for continuous records.")
		check(persisted.duration_s == 60.0 and persisted.elapsed_s == 60.0 and persisted.conditions.gain_hex == gain_hex and persisted.phases.size() == 3, "The stored result retains its full fixed duration, frozen gain, and three phase reports.")
		check(persisted.phases[0].metrics.shots == 0 and persisted.trace_retention == "light_no_exact_input_replay", "A no-input synthetic controller route cannot invent human shots or a retained raw replay.")
	app.shell._open_history()
	check(app.shell.current_page == "history" and app.shell.history_rows.size() == app.store.history().size(), "The native history signal consumes the real persisted controller reports.")
	check(Store.new(app.store.root_path).load_profile().gain_hex == gain_hex, "Pausing, resuming, completing and viewing history never replace the baseline profile.")
	await dispose_app(app)


func test_profile_persistence_protection() -> void:
	var app: V2AppController = await make_app()
	var baseline: Dictionary = app.profile.duplicate(true)
	var profile_path: String = app.store.root_path.path_join("profile.json")
	var before_bytes: PackedByteArray = FileAccess.get_file_as_bytes(profile_path)
	var lock_path: String = profile_path + ".lock"
	check(DirAccess.make_dir_absolute(lock_path) == OK, "The isolated profile write-lock fixture can be acquired.")
	app.shell.show_settings(app.profile)
	await settle()
	app.shell.profile_fields.cm_per_360.value = 30.0
	app.shell.profile_apply_button.pressed.emit()
	check(app.profile == baseline and Canonical.float64_hex(app.gain_deg_per_relative_unit) == baseline.gain_hex and FileAccess.get_file_as_bytes(profile_path) == before_bytes, "A real V2Store write-lock failure leaves the controller, camera and durable baseline unchanged.")
	check(app.shell._notice.contains("non enregistré") and app.shell._notice.contains("DOCUMENT_LOCKED"), "The actual failed Apply route reports the concrete persistence failure without success text.")
	check(DirAccess.remove_absolute(lock_path) == OK, "Only the test's own profile lock is released.")
	var pending: Dictionary = {"calibration_id": "qa_profile_protection_" + Crypto.new().generate_random_bytes(8).hex_encode(),
		"protocol_id": "sustained_blocks_v2", "protocol_revision": "2026-10-12-v2.0",
		"plan_sha256": Canonical.semantic_sha256({"fixture_scope": "opaque_checkpoint_profile_protection_only", "baseline_gain_hex": baseline.gain_hex}),
		"day_role": "express", "epoch": 0, "status": "pending",
		"checkpoint": {"data_origin": "synthetic_store_lock_fixture_no_CAL_execution", "completed_cells": []}}
	check(app.store.save_calibration_state(pending), "An isolated opaque pending-checkpoint fixture preserves the actual controller baseline: " + app.store.last_error)
	var protected_bytes: PackedByteArray = FileAccess.get_file_as_bytes(app.store.root_path.path_join("calibration_state.json"))
	app.save_profile(baseline.duplicate(true))
	check(app.profile.gain_hex == baseline.gain_hex and Canonical.float64_hex(app.profile.cm_per_360) == Canonical.float64_hex(SOURCE_CM_PER_360) and FileAccess.get_file_as_bytes(profile_path) == before_bytes, "Controller.save_profile remains bit-exact for unchanged 35.0000000007 cm while a pending baseline is protected.")
	app.save_profile({"cm_per_360": 28.0})
	check(app.profile == baseline and app.shell._notice.contains("CALIBRATION_PROFILE_LOCKED") and FileAccess.get_file_as_bytes(app.store.root_path.path_join("calibration_state.json")) == protected_bytes, "The real controller cannot replace a pending baseline or alter its stored checkpoint when profile editing is rejected.")
	var restored: Dictionary = Store.new(app.store.root_path).load_profile()
	check(restored.gain_hex == baseline.gain_hex and Canonical.float64_hex(restored.gain_deg_per_relative_unit) == baseline.gain_hex and Canonical.float64_hex(restored.cm_per_360) == Canonical.float64_hex(SOURCE_CM_PER_360), "A fresh store reads the same protected binary64 baseline without rebuilding it from the UI label.")
	await dispose_app(app)


func test_settings_abort_routes() -> void:
	for action: String in ["settings", "sensitivity"]:
		var app: V2AppController = await make_app()
		enter_practice(app, "EX02")
		if app.screen != app.Screen.PRACTICE:
			await dispose_app(app)
			continue
		advance_practice(app, 0.1)
		var frozen_gain: String = app.profile.gain_hex
		var session_id: String = app._current_session_id
		app.pause_practice("manual_pause")
		var button: Button = app.hud.settings_button if action == "settings" else app.hud.sensitivity_button
		check(button.visible and not button.disabled, "The real pause menu exposes the " + action + " control.")
		button.pressed.emit()
		check(app.screen == app.Screen.MENU and app.shell.current_page == "settings", "COUNTEREXAMPLE PAUSE_" + action.to_upper() + "_ROUTE: the real pause control must abort practice and open profile settings.")
		if app.screen == app.Screen.MENU and app.shell.current_page == "settings":
			check_report_integrity(app._last_report, action + "-aborted MainV2 result")
			var persisted: Dictionary = report_for(app.store, session_id)
			check(app.engine.completed and app.engine.invalid_reason == "settings_changed_during_practice" and not persisted.is_empty(), "Opening settings finalizes and persists the old fixed-condition practice before any edit.")
			if persisted.is_empty():
				diagnose_missing_report(app)
			if not persisted.is_empty():
				check_report_integrity(persisted, action + "-aborted V2Store result")
				check(Canonical.semantic_sha256(persisted) == Canonical.semantic_sha256(app._last_report), "The " + action + " abort preserves the report's semantic SHA-256 across actual persistence.")
				check(not persisted.complete and not persisted.rank_eligible and persisted.conditions.gain_hex == frozen_gain, "The abandoned result retains the original gain and cannot become a record.")
			app.shell.profile_fields.cm_per_360.value = 43.75
			app.shell.profile_apply_button.pressed.emit()
			var edited_gain: String = Canonical.float64_hex(914.4 / (800.0 * 43.75))
			check(app.profile.gain_hex == edited_gain and app.engine.conditions.gain_hex == frozen_gain and Store.new(app.store.root_path).load_profile().gain_hex == edited_gain, "The next accepted profile changes independently of the abandoned report's frozen conditions.")
		await dispose_app(app)


func test_render_generation_identity() -> void:
	var app: V2AppController = await make_app()
	enter_practice(app, "EX03")
	if app.screen != app.Screen.PRACTICE:
		await dispose_app(app)
		return
	var first_schedule: Dictionary = app.engine._scheduled[0]
	advance_practice(app, float(first_schedule.born_s) + 0.01)
	check(not app.arena.prepared_identities.is_empty(), "The controller prepares the actual first timed opportunity.")
	app._post_draw()
	var first_id: String = app.engine.targets[0].identity
	check(app.engine.targets[0].first_rendered_s != null, "The actual controller draw callback marks only its prepared and visible generation.")
	var old_prepared: Array = app.arena.prepared_identities.duplicate()
	var old_visible: Array = app.arena.visibly_drawn_identities.duplicate()
	var second_schedule: Dictionary = app.engine._scheduled[1]
	app._clock_origin_us = Time.get_ticks_usec() - int(round((float(second_schedule.born_s) + 0.01) * 1000000.0))
	app._post_draw()
	check(not app.engine.completed and app.engine.targets.has(0), "A delayed real controller draw callback advances scheduled expiry and the next opportunity.")
	if app.engine.targets.has(0):
		var next_target: Dictionary = app.engine.targets[0]
		check(next_target.identity != first_id and next_target.generation == 1 and next_target.first_rendered_s == null and next_target.first_render_ack_s == null, "An old prepared frame never acknowledges the new generation created during the draw callback.")
		check(app.arena.prepared_identities == old_prepared and app.arena.visibly_drawn_identities == old_visible, "The stale-frame test keeps actual prepared/visible identities unchanged until a new prepare.")
		app._process(FRAME_DELTA_S)
		app._post_draw()
		check(next_target.first_rendered_s != null and next_target.identity in app.arena.prepared_identities, "The new generation becomes eligible only after its own controller preparation and draw callback.")
	await dispose_app(app)


func motion_event(counts: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.screen_relative = counts
	event.relative = Vector2(-777.0, 555.0)
	return event


func button_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(-100.0, -100.0)
	event.global_position = event.position
	return event


func test_controller_input_queue() -> void:
	var app: V2AppController = await make_app()
	enter_practice(app)
	if app.screen != app.Screen.PRACTICE:
		await dispose_app(app)
		return
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Input route tests require the actual display backend to retain capture.")
	var initial_events: int = app.engine.pose_event_count
	var initial_yaw: float = app.yaw_deg
	var initial_pitch: float = app.pitch_deg
	app._input(motion_event(Vector2(1000.0, 25.0)))
	app._input(motion_event(Vector2(-400.0, -5.0)))
	var expected_yaw: float = initial_yaw + 600.0 * app.gain_deg_per_relative_unit
	var expected_pitch: float = initial_pitch - 20.0 * app.gain_deg_per_relative_unit
	check(absf(app.yaw_deg - expected_yaw) <= 1e-9 and absf(app.pitch_deg - expected_pitch) <= 1e-9, "MainV2 applies screen_relative once with the exact gain, correct signs, and no frame-time/UI-scale multiplier.")
	check(app.engine.pose_event_count == initial_events and app.engine._pending_events.size() == 2, "Actual controller input queues both poses without applying them in the callback or losing one.")
	var queued: Array = app.engine._pending_events.duplicate(true)
	check(queued[0][1] < queued[1][1] and queued[0][0] <= queued[1][0], "Queued controller events preserve total receipt order.")
	app._process(FRAME_DELTA_S)
	check(app.engine.pose_event_count == initial_events + 2 and app.engine._pending_events.is_empty() and absf(app.engine.yaw_deg - expected_yaw) <= 1e-9 and absf(app.engine.pitch_deg - expected_pitch) <= 1e-9, "The real practice process consumes both queued poses exactly once.")
	app._process(FRAME_DELTA_S)
	check(app.engine.pose_event_count == initial_events + 2, "A later frame cannot reapply the same received movement.")
	var burst_start_yaw: float = app.yaw_deg
	var burst_start_events: int = app.engine.pose_event_count
	for event_index: int in 128:
		app._input(motion_event(Vector2(1.0, 0.0)))
	check(app.engine._pending_events.size() == 128, "A burst of real controller callbacks queues every received pose before the next frame.")
	app._process(FRAME_DELTA_S)
	check(app.engine.pose_event_count == burst_start_events + 128 and absf(app.engine.yaw_deg - burst_start_yaw - 128.0 * app.gain_deg_per_relative_unit) <= 1e-9, "The real frame path consumes the complete synthetic mouse burst without lost or duplicated movement.")
	await dispose_app(app)


func test_held_button_arming() -> void:
	var app: V2AppController = await make_app()
	Input.parse_input_event(button_event(true))
	Input.flush_buffered_events()
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "The synthetic held-button setup reaches the real Godot input state.")
	enter_practice(app)
	if app.screen != app.Screen.PRACTICE:
		Input.parse_input_event(button_event(false))
		await dispose_app(app)
		return
	check(not app._armed and not app.engine.fire_held, "A button held before countdown does not arm a practice shot.")
	app._input(button_event(true))
	check(app.engine._pending_events.is_empty(), "The inherited held press cannot enqueue a gameplay shot.")
	app._input(button_event(false))
	check(app._armed, "A real controller release explicitly arms subsequent presses.")
	app._input(button_event(true))
	app._process(FRAME_DELTA_S)
	check(app.engine.metrics.shots == 1, "Only the new press after release becomes one actual engine shot.")
	app._input(button_event(true))
	app._process(FRAME_DELTA_S)
	check(app.engine.metrics.shots == 1, "Keeping the button pressed cannot invent another click edge.")
	Input.parse_input_event(button_event(false))
	Input.flush_buffered_events()
	await dispose_app(app)
