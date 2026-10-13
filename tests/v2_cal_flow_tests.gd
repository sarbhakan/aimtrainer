extends SceneTree

const Store := preload("res://scripts/v2/v2_store.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const Task := preload("res://scripts/v2/v2_calibration_task.gd")
const FRAME_S: float = 1.0 / 144.0
const POSE_HZ: int = 72
const ORIGIN: String = "synthetic_controller_flow_fixture"

var assertions: int = 0
var failures: int = 0
var roots: Array[String] = []
var measured_tasks: int = 0
var familiarization_tasks: int = 0
var immutable_checked: bool = false
var saved_max_fps: int
var saved_accumulation: bool
var saved_mouse_mode: Input.MouseMode


class SyntheticController:
	extends "res://scripts/v2/v2_app_controller.gd"
	var synthetic_clock_us: int = 0
	var synthetic_unix_origin_s: float = Time.get_unix_time_from_datetime_string("2026-10-12T08:00:00")
	var forced_local_date: String = ""

	func _now_us() -> int:
		return synthetic_clock_us

	func _now_unix_s() -> float:
		return synthetic_unix_origin_s + float(synthetic_clock_us) / 1000000.0

	func _local_date() -> String:
		return forced_local_date if not forced_local_date.is_empty() else Time.get_date_string_from_unix_time(int(floor(_now_unix_s() + Time.get_time_zone_from_system().bias * 60.0)))

	func actual_conditions(difficulty_by_task: Dictionary = {}) -> Dictionary:
		var conditions: Dictionary = super.actual_conditions(difficulty_by_task)
		conditions["display_hz_declared"] = 144.0
		conditions["data_origin"] = "synthetic_controller_flow_fixture"
		return conditions


func _initialize() -> void:
	saved_max_fps = Engine.max_fps
	saved_accumulation = Input.use_accumulated_input
	saved_mouse_mode = Input.mouse_mode
	_run.call_deferred()


func _check(condition: bool, description: String) -> bool:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 30:
			printerr("V2 CAL FLOW : " + description)
	return condition


func _settle() -> void:
	await process_frame
	await process_frame


func _make_app() -> SyntheticController:
	var temporary: String = "/tmp/aimlocal-v2-cal-flow-isolated-synthetic-" + Crypto.new().generate_random_bytes(12).hex_encode()
	roots.append(temporary)
	var store := Store.new(temporary.path_join("v2"))
	var profile: Dictionary = Store.default_profile()
	profile["sound_enabled"] = false
	_check(store.save_profile(profile), "Profil natif A enregistré dans un stockage isolé avant le vrai _ready")
	var app := SyntheticController.new()
	app.store = store
	root.add_child(app)
	app.set_process(false)
	app.preview.set_process(false)
	app.preview.paused = true
	if RenderingServer.frame_post_draw.is_connected(app._post_draw):
		RenderingServer.frame_post_draw.disconnect(app._post_draw)
	await _settle()
	_check(app.calibration != null and app.arena != null and app.shell != null and app.hud != null, "Le vrai contrôleur construit son runner, son arène et son interface")
	_check(app.store.root_path.begins_with(temporary) and app.profile.gain_hex == profile.gain_hex, "Le contrôleur conserve le store injecté et les bits du profil A")
	app.shell.show_calibration(app._calibration_ui_state())
	return app


func _dispose(app: SyntheticController) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app.queue_free()
	await _settle()


func _reopen_app(previous: SyntheticController) -> SyntheticController:
	var store_path: String = previous.store.root_path
	await _dispose(previous)
	var reopened := SyntheticController.new()
	reopened.store = Store.new(store_path)
	root.add_child(reopened)
	reopened.set_process(false)
	reopened.preview.set_process(false)
	reopened.preview.paused = true
	if RenderingServer.frame_post_draw.is_connected(reopened._post_draw):
		RenderingServer.frame_post_draw.disconnect(reopened._post_draw)
	await _settle()
	reopened.shell.show_calibration(reopened._calibration_ui_state())
	return reopened


func _refresh(app: SyntheticController) -> void:
	app.shell.configure(app.catalogue, app.profile, app._calibration_ui_state(), [])
	app.shell.show_calibration(app._calibration_ui_state())


func _press(button: Button, description: String) -> bool:
	if not _check(is_instance_valid(button) and not button.disabled, description):
		return false
	button.pressed.emit()
	return true


func _tick(app: SyntheticController, wall_elapsed_s: float) -> bool:
	var requested_us: int = app._cal_session_origin_us + int(round(wall_elapsed_s * 1000000.0))
	if not _check(requested_us >= app.synthetic_clock_us, "L'horloge monotone synthétique avance sans retour pendant la journée"):
		return false
	app.synthetic_clock_us = requested_us
	if not _check(app.screen == app.Screen.CALIBRATION, "La transition est conduite par le vrai contrôleur CAL"):
		return false
	app._process_calibration(FRAME_S)
	return true


func _step(app: SyntheticController) -> void:
	app._process_calibration(FRAME_S)


func _set_calendar(app: SyntheticController, unix_s: float, local_date: String = "") -> void:
	_check(app.screen == app.Screen.MENU, "Les scénarios de calendrier sont préparés hors mesure active")
	app.synthetic_unix_origin_s = unix_s - float(app.synthetic_clock_us) / 1000000.0
	app.forced_local_date = local_date
	_refresh(app)


func _visible_bodies(app: SyntheticController) -> int:
	var count: int = 0
	for body: MeshInstance3D in app.arena.target_nodes:
		if body.visible:
			count += 1
	return count


func _render_marker(app: SyntheticController, task: RefCounted, at_s: float) -> bool:
	app.yaw_deg = task.yaw_deg
	app.pitch_deg = task.pitch_deg
	app.arena.set_pose(app.yaw_deg, app.pitch_deg)
	app.arena.prepare(task.snapshot(), at_s)
	if app.arena.prepared_identities.is_empty():
		return true
	var receipt: Dictionary = Canonical.json_ready(app.arena.prepared_receipt)
	receipt["data_origin"] = ORIGIN
	receipt["synthetic_monotonic_us"] = app._now_us()
	if not _check(Canonical.encode(receipt).ok, "Le marqueur synthétique utilise un RenderReceipt natif à clés JSON String"):
		return false
	task.mark_rendered(app.arena.prepared_identities, app.arena.visibly_drawn_identities, at_s, true, receipt)
	return _check(task.invalid_reason.is_empty(), "Les premiers marqueurs utiles précèdent les réponses des moteurs réels")


func _queue_replay(task: RefCounted, utility: float) -> Array:
	var markers: Array = [0.0, float(task.duration_s) * 0.5, float(task.duration_s) - 0.001]
	if task.task in ["SMOOTH", "REACTIVE"]:
		var target: Dictionary = task.targets[0]
		var contact_end_s: float = float(task.duration_s) * utility
		for frame_index: int in range(int(floor(contact_end_s * POSE_HZ)) + 1):
			var time_s: float = float(frame_index) / POSE_HZ
			var pose: Dictionary = task._sample_target(target, time_s)
			task.queue_pose(time_s, float(pose.yaw_deg), float(pose.pitch_deg))
		task.queue_pose(contact_end_s + 0.000001, 120.0, 0.0)
	else:
		for opportunity: Dictionary in task.opportunities:
			markers.append(float(opportunity.slot_start_s))
			markers.append(float(opportunity.onset_s) + 0.000001)
			var position: Dictionary = opportunity if task.task == "CLICK" else task.deck.positions[int(opportunity.priority_target_id)]
			var window_s: float = float(opportunity.deadline_s) - float(opportunity.onset_s)
			var work_s: float = float(opportunity.hp) / float(opportunity.damage_hp_s) if task.task == "SWITCH" else 0.0
			var response_s: float = float(opportunity.onset_s) + (1.0 - utility) * (window_s - work_s)
			task.queue_pose(float(opportunity.onset_s), float(position.yaw_deg), float(position.pitch_deg))
			if utility <= 0.0:
				continue
			task.queue_fire(response_s, true)
			task.queue_fire(minf(float(opportunity.deadline_s) - 0.000001, response_s + work_s + 0.001), false)
	for frame_index: int in int(round(float(task.duration_s) * 144.0)):
		task.record_frame(FRAME_S)
	markers.sort()
	return markers


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		hashing.update(bytes)
	return hashing.finish().hex_encode()


func _read_saved(store: Store, session_id: String) -> Dictionary:
	var path: String = store.root_path.path_join("reports").path_join(session_id + ".json")
	_check(FileAccess.file_exists(path), "La référence complète existe réellement sur disque dans /tmp")
	var document: Dictionary = store._read_document(path, "report")
	return document.payload if document.get("ok", false) and not document.get("missing", true) else {}


func _check_full_audit(report: Dictionary, comparative: bool) -> void:
	_check(not report.is_empty() and Canonical.encode(report).ok, "Le rapport chargé est complet et strictement JSON/canonique")
	if report.is_empty():
		return
	_check(report.complete and report.valid and report.audit.mandatory and report.audit.replay_exact_possible, "Le moteur réel termine avec un audit obligatoire rejouable")
	_check(not report.audit.physical_scanout_certified, "L'audit synthétique ne revendique aucun scanout physique")
	_check(report.comparative_utility_included == comparative and (report.utility != null) == comparative, "Seules les 24 s mesurées ont une utilité comparative")
	_check(report.conditions.data_origin == ORIGIN, "Les conditions conservent l'origine synthétique du contrôleur")
	_check(report.render_quality.eligible and report.render_quality.frame_count >= int(round(float(report.duration_s) * 144.0)), "La qualité vient des frametimes synthétiques fournis au vrai moteur")
	for entry: Array in [["received_pose_trace", Task.POSE_RECORD_BYTES], ["fire_trace", Task.FIRE_RECORD_BYTES], ["render_trace", 24], ["frame_trace", 8]]:
		var trace: Dictionary = report[entry[0]]
		var stored: PackedByteArray = Marshalls.base64_to_raw(trace.base64)
		var bytes: PackedByteArray = stored.decompress(int(trace.byte_count), FileAccess.COMPRESSION_ZSTD) if trace.compression == "zstd" else stored
		_check(trace.compression in ["none", "zstd"] and stored.size() == int(trace.stored_byte_count), "L'encodage natif et la taille stockée du trace sont conservés")
		_check(trace.finalized and bytes.size() == int(trace.byte_count) and bytes.size() == int(trace.record_count) * int(entry[1]) and _sha256(bytes) == trace.sha256, "Les octets décompressés du trace " + str(entry[0]) + " correspondent à son hash et ses comptes")
	_check(report.received_pose_trace.record_count > 0 and report.render_trace.record_count > 0 and not report.render_receipts.is_empty(), "Les poses et premiers rendus sont réellement présents")
	for receipt: Dictionary in report.render_receipts:
		_check(receipt.prepared_receipt_sha256 == Canonical.semantic_sha256(receipt.prepared_receipt) and receipt.prepared_receipt.data_origin == ORIGIN, "Chaque RenderReceipt conserve son empreinte et son origine synthétique")
	if report.task == "CLICK" and comparative:
		_check(report.first_presses == report.opportunities and report.premature == 0 and report.extra_shots == 0 and int(report.fire_trace.record_count) == 2 * int(report.opportunities), "Le clic UI de départ n'ajoute aucun tir : first=%s opportunities=%s premature=%s extra=%s fire=%s" % [report.first_presses, report.opportunities, report.premature, report.extra_shots, report.fire_trace.record_count])


func _drive_task(app: SyntheticController, overrides: Dictionary = {}) -> Dictionary:
	if not _check(app.active_task != null and app._cal_segment_kind in ["preflight", "acclimation", "measurement", "preflight_adjustment"], "Un vrai TaskEngine actif reçoit le replay synthétique"):
		return {}
	var task: RefCounted = app.active_task
	var kind: String = app._cal_segment_kind
	var snapshot: Dictionary = app._cal_snapshot.duplicate(true)
	var origin_s: float = app._cal_segment_origin_s
	var gain_hex: String = snapshot.gain_hex
	var preferred_id: String = str(app.calibration.plan.candidates[1].candidate_id)
	var utility: float = 0.70 if kind == "measurement" and snapshot.candidate_id == preferred_id else (0.45 if kind == "measurement" and snapshot.candidate_id != "A" else 0.55)
	utility = float(overrides.get(task.task, utility))
	_check(task.get_script() == Task and task.conditions.gain_hex == gain_hex and Canonical.float64_hex(app.gain_deg_per_relative_unit) == gain_hex, "Le gain effectif du client et celui figé par TaskEngine correspondent au candidat planifié")
	var markers: Array = _queue_replay(task, utility)
	var previous_s: float = -1.0
	for marker: float in markers:
		if marker < 0.0 or marker >= float(task.duration_s) or marker <= previous_s:
			continue
		previous_s = marker
		if not _tick(app, origin_s + marker) or app.active_task != task or not _render_marker(app, task, marker):
			return {}
		if kind == "measurement" and marker == 12.0:
			_check(task.elapsed_s == 12.0 and absf(float(app.hud._snapshot.remaining_s) - 12.0) <= 0.000001, "Le timer et l'échantillon effectif correspondent à 12 s sur les 24 s fixes")
		if not _check(Canonical.float64_hex(app.gain_deg_per_relative_unit) == gain_hex, "Le gain reste constant à chaque marqueur de la tâche"):
			return {}
	if not _tick(app, origin_s + float(task.duration_s)):
		return {}
	var native: Dictionary = task.report()
	if not _check(native.complete and native.valid, "Le moteur scalaire termine la vraie tâche : " + str(native.get("invalid_reason", ""))):
		return {}
	var trace_id: String = "trace_" + str(app.calibration._calibration_id) + "." + str(snapshot.segment_id)
	if kind in ["measurement", "preflight", "preflight_adjustment"]:
		var saved: Dictionary = _read_saved(app.store, trace_id)
		_check_full_audit(saved, kind == "measurement")
		if saved.is_empty():
			return {}
		_check(saved.conditions.gain_hex == gain_hex, "L'audit immuable sauvegarde le gain réellement appliqué, y compris B")
		if kind == "measurement":
			measured_tasks += 1
			_check(saved.data_origin == ORIGIN and saved.duration_s == 24.0 and saved.elapsed_s == 24.0, "La mesure reste explicitement synthétique et conserve son dénominateur de 24 s")
			_check(absf(float(saved.actual_start_s) - origin_s) <= 0.000001 and absf(float(saved.actual_end_s) - origin_s - 24.0) <= 0.000001, "Les timestamps actual_start/end suivent exactement la mesure, sans absorber le décompte ou les repos")
			var cell: Dictionary = app.calibration._cells.get(snapshot.segment_id, {})
			if _check(not cell.is_empty(), "Le contrôleur valide et checkpoint réellement la cellule : " + str(app.calibration.error)):
				_check(cell.audit.trace_reference.session_id == trace_id and cell.audit.trace_reference.semantic_sha256 == Canonical.semantic_sha256(saved), "La cellule compacte référence le rapport complet vérifié sur disque")
				_check(cell.applied_gain.ieee754_binary64_big_endian_hex == gain_hex and cell.utility == saved.utility, "Le gain et le score natifs restent identiques entre audit complet et cellule")
				_check(not cell.audit.has("received_pose_trace") and cell.audit.input_trace_event_count == saved.received_pose_trace.record_count, "Le checkpoint compact garde les comptes et le lien vers les traces complètes")
			if not immutable_checked:
				immutable_checked = true
				var original_hash: String = Canonical.semantic_sha256(saved)
				_check(app.store.save_report(saved), "Le rapport immuable peut être sauvegardé à nouveau identiquement")
				var changed: Dictionary = saved.duplicate(true)
				changed["utility"] = float(saved.utility) + 0.001
				_check(not app.store.save_report(changed) and Canonical.semantic_sha256(_read_saved(app.store, trace_id)) == original_hash, "Aucune réécriture d'un audit complet sous la même identité n'est possible")
		else:
			familiarization_tasks += 1
	else:
		familiarization_tasks += 1
		_check(native.utility == null and not native.comparative_utility_included, "Les acclimatations de 15 s restent des diagnostics natifs non notés")
	return native


func _preflight(app: SyntheticController, overrides: Dictionary = {}) -> bool:
	for task_index: int in 4:
		_step(app)
		if not _check(app._cal_segment_kind == "preflight" and app.active_task != null and app.active_task.duration_s == 15.0, "Le contrôleur conduit chacune des quatre familiarisations de 15 s"):
			return false
		if _drive_task(app, overrides).is_empty():
			return false
	return _check(app._cal_blocked and app._cal_segment_kind == "preflight" and app.calibration._preflight.reports.size() == 4 and app.calibration._cells.is_empty(), "La revue obligatoire apparaît après 4 × 15 s, sans cellule comparative")


func _ready(app: SyntheticController, wait_s: float = 0.0) -> bool:
	if not _check(app._cal_blocked and app.shell.visible and not app.hud.visible and _visible_bodies(app) == 0, "Ready libère la souris et masque les corps pendant l'attente volontaire"):
		return false
	var gain_hex: String = Canonical.float64_hex(app.gain_deg_per_relative_unit)
	app.synthetic_clock_us += int(round(wait_s * 1000000.0))
	_step(app)
	_check(Canonical.float64_hex(app.gain_deg_per_relative_unit) == gain_hex and app.active_task == null, "L'attente Ready ne crée pas de tâche ni de changement de gain")
	if not _press(app.shell.calibration_continue_button, "Le même bouton natif Continuer/Ready autorise explicitement le départ"):
		return false
	_step(app)
	return _check(not app._cal_blocked and app.calibration.active, "Le vrai handler Ready reprend le protocole et conserve son checkpoint")


func _countdown(app: SyntheticController) -> bool:
	var start_s: float = float(app._cal_snapshot.start_s) + app._cal_wait_offset_s
	var end_s: float = float(app._cal_snapshot.end_s) + app._cal_wait_offset_s
	if not _check(end_s - start_s == 3.0 and app.active_task != null and app.active_task.elapsed_s == 0.0 and _visible_bodies(app) == 0 and app.arena.prepared_identities.is_empty(), "Le décompte de 3 s ne révèle aucun corps ni temps de tâche"):
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	app._input(click)
	if not _tick(app, end_s - 0.001):
		return false
	_check(app._cal_segment_kind == "countdown" and app.active_task.elapsed_s == 0.0 and app.active_task._fire_trace_count == 0 and _visible_bodies(app) == 0, "Avant 3 s, même le clic UI synthétique n'entre pas dans la trace de tir")
	if not _tick(app, end_s):
		return false
	return _check(app._cal_segment_kind == "measurement" and app.active_task.duration_s == 24.0 and app.active_task.elapsed_s == 0.0, "La mesure de 24 s commence après la totalité du décompte")


func _complete_day(app: SyntheticController, stop_after_cells: int = -1) -> bool:
	for transition: int in 250:
		if app.screen == app.Screen.MENU:
			return _check(not app.calibration.active, "Le vrai contrôleur termine et restitue le menu")
		if stop_after_cells >= 0 and app.calibration._cells.size() >= stop_after_cells:
			return true
		if app._cal_blocked:
			if not _ready(app, 2.0):
				return false
		elif app._cal_segment_kind == "countdown":
			if not _countdown(app):
				return false
		elif app.active_task != null:
			if _drive_task(app).is_empty():
				return false
		elif app._cal_segment_kind in ["recovery", "rest"]:
			var snapshot: Dictionary = app._cal_snapshot.duplicate(true)
			var gain_hex: String = snapshot.gain_hex
			_check(app.arena.prepared_identities.is_empty() and _visible_bodies(app) == 0, "Les six secondes de récupération et les repos gardent les corps masqués")
			if snapshot.kind == "recovery":
				_check(float(snapshot.end_s) - float(snapshot.start_s) == 6.0, "Chaque mesure est suivie de six secondes de récupération")
			if not _tick(app, (float(snapshot.start_s) + float(snapshot.end_s)) * 0.5 + app._cal_wait_offset_s):
				return false
			_check(Canonical.float64_hex(app.gain_deg_per_relative_unit) == gain_hex, "Le gain reste celui du candidat imposé pendant le repos")
			if not _tick(app, float(snapshot.end_s) + app._cal_wait_offset_s):
				return false
		else:
			_step(app)
	return _check(false, "Le parcours doit terminer dans son nombre borné de transitions")


func _baseline_restored(app: SyntheticController) -> void:
	var baseline: Dictionary = app.calibration.baseline_profile
	_check(Canonical.float64_hex(app.gain_deg_per_relative_unit) == baseline.gain_hex and Canonical.float64_hex(app.calibration.temporary_gain_deg_per_relative_unit) == baseline.gain_hex, "Le contrôleur et le runner restaurent A exactement à la fin ou après interruption")
	_check(app.store.load_profile().gain_hex == baseline.gain_hex and app.profile.gain_hex == baseline.gain_hex, "Le profil persistant A reste identique pendant tout le protocole")


func _check_day(app: SyntheticController, role: int) -> Dictionary:
	var report: Dictionary = app.calibration._accepted_report(role)
	if not _check(not report.is_empty() and report.eligibility.eligible, "La journée est complète et admissible avec ses seules vraies cellules"):
		return {}
	var checkpoint: Dictionary = app.store.load_calibration_state()
	_check(not checkpoint.is_empty() and checkpoint.baseline_profile.gain_hex == app.profile.gain_hex, "Le checkpoint complet et le baseline A sont effectivement sauvegardés")
	for report_id: String in checkpoint.report_ids:
		_check(not _read_saved(app.store, report_id).is_empty(), "Chaque référence de l'audit complet reste lisible et vérifiée")
	_baseline_restored(app)
	return report


func _prepare_and_start(app: SyntheticController) -> bool:
	if not _press(app.shell.calibration_express_button, "Le bouton réel prépare l'express"):
		return false
	if not _check(app.screen == app.Screen.MENU and app.calibration.plan.get("phase") == "express" and not app.calibration.plan.get("is_example", true), "Le plan express natif est figé avant toute tâche"):
		return false
	_check(app.store.load_calibration_state().checkpoint.plan.plan_sha256 == app.calibration.plan.plan_sha256, "Le plan natif est déjà durable avant le départ UI")
	if not _press(app.shell.calibration_continue_button, "Le bouton réel démarre la journée express"):
		return false
	_step(app)
	return _check(app.screen == app.Screen.CALIBRATION and app.calibration.active, "Le vrai contrôleur entre dans la journée CAL à l'horloge synthétique")


func _test_express_and_confirmation() -> void:
	var app: SyntheticController = await _make_app()
	if not _prepare_and_start(app) or not _preflight(app):
		await _dispose(app)
		return
	var plan_hash: String = app.calibration.plan.plan_sha256
	var gate_us: int = app.synthetic_clock_us
	app.synthetic_clock_us += 5000000
	_step(app)
	_check(app._cal_blocked and app.calibration._cells.is_empty() and app.synthetic_clock_us == gate_us + 5000000, "La revue reste bloquée même si le temps civil avance de cinq secondes")
	if not _complete_day(app):
		await _dispose(app)
		return
	var express: Dictionary = _check_day(app, 0)
	if express.is_empty():
		await _dispose(app)
		return
	_check(app.calibration.result.status == "exploratory_only" and not app._calibration_ui_state().can_apply, "L'express restaure A et ne prétend pas autoriser une amélioration confirmée")
	var first_start_s: float = float(express.actual_end_utc) + 43200.0
	_set_calendar(app, first_start_s - 1.0)
	_check(is_instance_valid(app.shell.calibration_confirmation_button) and app.shell.calibration_confirmation_button.disabled, "La confirmation reste indisponible une seconde avant douze heures")
	app.shell.calibration_confirmation_button.pressed.emit()
	_check(app.calibration.plan.plan_sha256 == plan_hash and not app.calibration.active, "Le même bouton ne contourne pas la garde civile")
	_set_calendar(app, first_start_s)
	if not _press(app.shell.calibration_confirmation_button, "Le bouton natif prépare la confirmation exactement à douze heures"):
		await _dispose(app)
		return
	_check(app.calibration.plan.phase == "confirmation" and app.calibration.plan.plan_sha256 != plan_hash, "La confirmation utilise un plan et des défis indépendants de l'express")
	var confirmation_hash: String = app.calibration.plan.plan_sha256
	if not _press(app.shell.calibration_continue_button, "Le même bouton Continuer démarre le jour 1"):
		await _dispose(app)
		return
	_step(app)
	if not _complete_day(app):
		await _dispose(app)
		return
	var day1: Dictionary = _check_day(app, 1)
	if day1.is_empty():
		await _dispose(app)
		return
	_check(app.calibration.result.status == "incomplete" and not app._calibration_ui_state().can_apply, "Le jour 1 seul n'active pas Appliquer")
	for candidate_start: float in [first_start_s + 43200.0 - 1.0, first_start_s + 604800.0 + 1.0]:
		_set_calendar(app, candidate_start)
		_check(app.shell.calibration_continue_button.disabled, "Le jour 2 respecte les bornes civiles de 12 et 168 heures")
		app.shell.calibration_continue_button.pressed.emit()
		_check(not app.calibration.active and app.calibration.plan.plan_sha256 == confirmation_hash, "Le bouton Continuer ne démarre aucune époque hors créneau")
	_set_calendar(app, first_start_s + 86400.0, str(day1.player_local_date))
	_check(app.shell.calibration_continue_button.disabled and not app._calibration_ui_state().continue_reason.is_empty(), "Une date locale incohérente avec le fuseau ou identique au jour 1 bloque le jour 2")
	_set_calendar(app, first_start_s + 86400.0)
	if not _press(app.shell.calibration_continue_button, "Le même bouton démarre le jour 2 à une date locale autorisée"):
		await _dispose(app)
		return
	_step(app)
	if not _complete_day(app):
		await _dispose(app)
		return
	var day2: Dictionary = _check_day(app, 2)
	_check(not day2.is_empty() and day1.player_local_date != day2.get("player_local_date"), "Deux dates locales distinctes sont conservées dans les audits")
	_check(app.calibration.plan.sessions[0].order != app.calibration.plan.sessions[1].order, "Les ordres de gains sont inversés entre les deux journées")
	_check(app.calibration.result.status == "repeated_improvement" and app._calibration_ui_state().can_apply, "Les deux journées synthétiques admissibles activent le résultat natif : status=%s can_apply=%s" % [app.calibration.result.status, app._calibration_ui_state().can_apply])
	if not app._calibration_ui_state().can_apply:
		await _dispose(app)
		return
	var baseline: Dictionary = app.profile.duplicate(true)
	var candidate: Dictionary = app._calibration_ui_state().candidate.duplicate(true)
	var candidate_gain: float = V2CalibrationService.gain_value(candidate)
	var candidate_hex: String = Canonical.float64_hex(candidate_gain)
	var altered_candidate: Dictionary = candidate.duplicate(true)
	altered_candidate["candidate_id"] = "not_the_confirmed_candidate"
	app.shell.calibration_apply_requested.emit(altered_candidate)
	_check(app.store.load_profile().gain_hex == baseline.gain_hex and not app.calibration.plan.is_empty(), "Le vrai handler refuse un candidat différent du bilan confirmé sans toucher au profil")
	print("V2 CAL FLOW : application consentie, redémarrage et annulation du candidat natif confirmé")
	if not _press(app.shell.calibration_apply_button, "Le bouton Appliquer est accessible seulement après confirmation native complète"):
		await _dispose(app)
		return
	_check(app.profile.gain_hex == candidate_hex and app.store.load_profile().gain_hex == candidate_hex and Canonical.float64_hex(app.gain_deg_per_relative_unit) == candidate_hex, "Le bouton applique exactement les bits du candidat au contrôleur et au profil durable")
	_check(app.calibration.plan.is_empty() and app.store.load_calibration_state().is_empty(), "Le plan terminé est archivé avant le changement du profil")
	var application: Dictionary = app._application_backup.duplicate(true)
	_check(application.get("kind") == "application_committed" and application.get("explicit_consent") == true, "L'application possède un commit durable et un consentement explicite")
	var application_id: String = str(application.get("session_id", ""))
	_check(not application_id.is_empty() and not _read_saved(app.store, application_id).is_empty(), "Le commit d'application est réellement enregistré sur disque")
	var intent: Dictionary = _read_saved(app.store, application_id.trim_suffix("_committed"))
	_check(intent.get("kind") == "application_intent" and intent.get("plan_sha256") == confirmation_hash and Canonical.semantic_sha256(intent.get("baseline_profile", {})) == Canonical.semantic_sha256(baseline), "L'intention relie le plan confirmé aux bits exacts du profil initial")
	_check(app._calibration_ui_state().can_undo and is_instance_valid(app.shell.calibration_undo_button), "Le retour au réglage précédent est accessible dans l'interface après application")
	app = await _reopen_app(app)
	_check(app.profile.gain_hex == candidate_hex and app._application_backup.get("session_id") == application_id and app._calibration_ui_state().can_undo, "Un nouveau contrôleur récupère le candidat et le retour au profil initial depuis les fichiers, sans processus conservé")
	if not _press(app.shell.calibration_undo_button, "Le bouton natif de retour reste disponible après redémarrage"):
		await _dispose(app)
		return
	_check(Canonical.semantic_sha256(app.profile) == Canonical.semantic_sha256(baseline) and Canonical.semantic_sha256(app.store.load_profile()) == Canonical.semantic_sha256(baseline), "L'annulation restaure l'intégralité du profil initial et ses bits sur disque")
	_check(Canonical.float64_hex(app.gain_deg_per_relative_unit) == baseline.gain_hex and app._application_backup.is_empty() and not app._calibration_ui_state().can_undo, "L'annulation restaure aussi le gain effectif et retire l'action devenue sans objet")
	var undo_count: int = 0
	for history_row: Dictionary in app.store.history():
		var stored: Dictionary = history_row.get("report", {})
		if stored.get("kind") == "application_undo" and stored.get("application_session_id") == application_id:
			undo_count += 1
			_check(stored.get("explicit_consent") == true and Canonical.semantic_sha256(stored.get("baseline_profile", {})) == Canonical.semantic_sha256(baseline), "Le retour possède un commit audité relié à l'application originale")
	_check(undo_count == 1 and not _read_saved(app.store, application_id).is_empty(), "Un seul commit d'annulation est ajouté, sans effacer le commit d'application ni les mesures")
	app = await _reopen_app(app)
	_check(app.profile.gain_hex == baseline.gain_hex and app._application_backup.is_empty() and not app._calibration_ui_state().can_undo, "Un second redémarrage conserve le profil initial et ne ressuscite pas le candidat annulé")
	await _dispose(app)


func _adjust(app: SyntheticController, task: String) -> bool:
	var previous_generation: int = int(app.calibration._preflight.generation)
	var previous_hash: String = app.calibration.plan.plan_sha256
	if not _press(app.shell.calibration_adjustment_buttons.get(task), "Le bouton natif Tester en 24 s autorise l'ajustement adjacent de " + task):
		return false
	_step(app)
	if not _check(app._cal_segment_kind == "preflight_adjustment" and app.active_task != null and app.active_task.duration_s == 24.0, "Le handler d'ajustement conduit son vrai essai de 24 s, avec Ready explicite du bouton"):
		return false
	if _drive_task(app).is_empty():
		return false
	_check(app.calibration._preflight.generation == previous_generation + 1 and app.calibration.plan.plan_sha256 != previous_hash and app.calibration._cells.is_empty(), "Le vrai handler refreeze un nouveau plan avant toute comparaison")
	return _check(not app._cal_blocked and app._cal_segment_kind == "preflight" and app.active_task != null and float(app._cal_snapshot.start_s) == float(previous_generation + 1) * 84.0, "Les 24 s d'essai et 60 s de nouveau préflight ajoutent exactement 84 s")


func _test_levels_interruption_and_retry() -> void:
	var app: SyntheticController = await _make_app()
	if not _prepare_and_start(app) or not _preflight(app, {"CLICK": 0.0}):
		await _dispose(app)
		return
	var original_hash: String = app.calibration.plan.plan_sha256
	app._start_level_adjustment("CLICK", "advanced")
	_check(app.calibration.plan.plan_sha256 == original_hash and app.calibration._preflight.pending_adjustment.is_empty(), "Le contrôleur refuse un saut de niveau non adjacent")
	_refresh(app)
	if not _adjust(app, "CLICK") or not _preflight(app, {"CLICK": 0.995}):
		await _dispose(app)
		return
	if not _adjust(app, "CLICK") or not _preflight(app, {"CLICK": 0.0, "SMOOTH": 0.05}):
		await _dispose(app)
		return
	_check(app.calibration._preflight.changes_by_task.CLICK == 2 and app.calibration._preflight.changes_by_task.SMOOTH == 0, "La limite de deux changements porte sur chaque tâche séparément")
	_check(app.shell.calibration_adjustment_buttons.CLICK.disabled and not app.shell.calibration_adjustment_buttons.SMOOTH.disabled, "Le budget épuisé de CLICK ne bloque pas l'ajustement de SMOOTH")
	var frozen_hash: String = app.calibration.plan.plan_sha256
	app._start_level_adjustment("CLICK", "novice")
	_check(app.calibration.plan.plan_sha256 == frozen_hash, "Un troisième changement de CLICK est refusé par le vrai handler")
	_refresh(app)
	if not _adjust(app, "SMOOTH") or not _preflight(app):
		await _dispose(app)
		return
	if not _complete_day(app, 1):
		await _dispose(app)
		return
	var previous_epoch: String = app.calibration._epoch.epoch_sha256
	var old_ids: Array = app.calibration._report_ids.duplicate()
	frozen_hash = app.calibration.plan.plan_sha256
	app._start_level_adjustment("SMOOTH", "standard")
	_check(app.calibration.plan.plan_sha256 == frozen_hash and app.calibration._cells.size() == 1, "Les niveaux sont définitivement figés dès la première cellule comparative")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(app.screen == app.Screen.MENU and not app.calibration.active and app.active_task == null, "La perte de focus interrompt l'époque complète via le contrôleur")
	_baseline_restored(app)
	var interrupted: Array = app.calibration._role_reports(0)
	_check(interrupted.size() == 1 and not interrupted[0].complete and not interrupted[0].eligibility.eligible and app.calibration._accepted_report(0).is_empty(), "Les cellules de l'époque interrompue sont conservées mais exclues de l'époque acceptée")
	for identity: String in old_ids:
		_check(not _read_saved(app.store, identity).is_empty(), "Les audits immuables antérieurs à l'interruption ne disparaissent pas")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.synthetic_clock_us += 100000000
	_refresh(app)
	if not _press(app.shell.calibration_continue_button, "Le même bouton reprend une nouvelle époque complète après interruption"):
		await _dispose(app)
		return
	_step(app)
	_check(app.calibration._epoch.epoch_sha256 != previous_epoch and app.calibration._epoch.session.attempt_epoch == 1 and app.calibration._cells.is_empty() and app.calibration._ready_cells.is_empty(), "Le retry renouvelle toute l'époque et ses défis, sans reprendre une cellule isolée")
	if not _complete_day(app):
		await _dispose(app)
		return
	var completed: Dictionary = _check_day(app, 0)
	_check(not completed.is_empty() and app.calibration.result.accepted_epoch_by_day_role.get("0") == 1 and app.calibration._role_reports(0).size() == 2, "Seule l'époque intégrale de retry est retenue, avec l'interruption encore auditée")
	await _dispose(app)


func _remove_fixture(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_fixture(path.path_join(child))
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	DirAccess.remove_absolute(path)


func _run() -> void:
	print("V2 CAL FLOW : vrai V2AppController/UI/TaskEngine/store, horloges, poses, marqueurs et frametimes 1/144 synthétiques; aucun joueur, HID ou scanout physique mesuré.")
	await _test_express_and_confirmation()
	await _test_levels_interruption_and_retry()
	_check(measured_tasks == 57 and familiarization_tasks == 95, "Les quatre journées complètes, l'époque interrompue et les trois validations de niveau exécutent toutes leurs vraies tâches")
	for path: String in roots:
		_remove_fixture(path)
		_check(not DirAccess.dir_exists_absolute(path), "Le stockage synthétique isolé est supprimé après validation")
	Engine.max_fps = saved_max_fps
	Input.use_accumulated_input = saved_accumulation
	Input.mouse_mode = saved_mouse_mode
	print("V2 CAL FLOW : %d tâches mesurées, %d familiarisations synthétiques exécutées" % [measured_tasks, familiarization_tasks])
	print("V2 CAL FLOW : %d assertions, %d échecs" % [assertions, failures])
	quit(1 if failures > 0 else 0)
