extends SceneTree

const Runner := preload("res://scripts/v2/v2_calibration_runner.gd")
const Store := preload("res://scripts/v2/v2_store.gd")
const Calibration := preload("res://scripts/v2/v2_calibration_service.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")

var assertions: int = 0
var failures: int = 0
var roots: Array[String] = []


class ClockRunner:
	extends "res://scripts/v2/v2_calibration_runner.gd"
	var now: float = 0.0

	func _init(store: Store, unix: float) -> void:
		now = unix
		super(store)

	func _clock_unix() -> float:
		return now


class FailingStore:
	extends "res://scripts/v2/v2_store.gd"
	var fail_checkpoint: bool = false
	var fail_refreeze_active: bool = false

	func _rename_file(source: String, destination: String) -> Error:
		if fail_checkpoint and destination.ends_with("/calibration_state.json"):
			return ERR_CANT_CREATE
		if fail_refreeze_active and destination.ends_with("/calibration_state.json"):
			var wire: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
			if wire is Dictionary and wire.get("payload", {}).get("status") == "active" and not str(wire.payload.get("checkpoint", {}).get("previous_plan_sha256", "")).is_empty():
				return ERR_CANT_CREATE
		return super._rename_file(source, destination)


class TimedStore:
	extends "res://scripts/v2/v2_store.gd"
	var read_ms: float = 0.0
	var write_ms: float = 0.0
	var read_count: int = 0
	var write_count: int = 0

	func _read_document(path: String, kind: String, use_backup: bool = false) -> Dictionary:
		var before: int = Time.get_ticks_usec()
		var result: Dictionary = super._read_document(path, kind, use_backup)
		read_ms += float(Time.get_ticks_usec() - before) / 1000.0
		read_count += 1
		return result

	func _write_document(relative_path: String, kind: String, payload: Variant, immutable: bool = false) -> bool:
		var before: int = Time.get_ticks_usec()
		var result: bool = super._write_document(relative_path, kind, payload, immutable)
		write_ms += float(Time.get_ticks_usec() - before) / 1000.0
		write_count += 1
		return result


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func new_store() -> Store:
	var path: String = "/tmp/aimlocal-v2-runner-" + Crypto.new().generate_random_bytes(12).hex_encode()
	roots.append(path)
	var store := Store.new(path.path_join("v2"))
	check(store.save_profile(Store.default_profile()), "Le fixture enregistre le vrai format du profil baseline.")
	return store


func conditions(gain_hex: String = "") -> Dictionary:
	return {"declared_dpi": 800, "dpi_source": "declared", "gain_hex": gain_hex if not gain_hex.is_empty() else Store.default_profile().gain_hex,
		"fov_horizontal_deg_at_16_9": 103.0, "render_resolution_px": [1920, 1080], "render_scale": 1.0,
		"renderer": "headless", "rendering_driver": "headless", "os": OS.get_name(), "engine_version": Engine.get_version_info().string,
		"frame_limit_hz": 144, "display_hz_declared": 144.0, "vsync": false, "input_convention": "received_pose_hold_v1",
		"crosshair": {"kind": "dot", "core_diameter_px": 2, "outline_radial_width_px": 1},
		"target_palette": "cyan_on_dark", "audio": "disabled", "seeded_scored_stimulus_preview": false,
		"candidate_value_masking": false, "player_utc_offset_minutes": 0,
		"test_origin": "synthetic_runner_fixture_not_measured_player_data"}


func settings() -> Dictionary:
	return {"objective": "polyvalent", "ratio": 1.25, "plan_seed_hex": "12345678901234567890123456789012",
		"levels": {"CLICK": "standard", "SMOOTH": "standard", "REACTIVE": "standard", "SWITCH": "standard"}}


func task_report(segment: Dictionary, utility: float = 0.55) -> Dictionary:
	var report: Dictionary = {"schema_version": "aimlocal.calibration_task_report.v2.0", "task": segment.task,
		"task_id": "CAL_" + segment.task + "_R2", "deck_id": segment.deck.deck_id,
		"deck_manifest_sha256": segment.deck.manifest_sha256, "duration_s": 24.0, "elapsed_s": 24.0,
		"complete": true, "valid": true, "invalid_reason": "", "comparative_utility_included": true,
		"utility": utility, "U": utility, "render_quality": {"mean_fps": 144.0, "median_fps": 144.0, "p99_ms": 7.0, "max_ms": 8.0, "frame_count": 3456},
		"data_origin": "synthetic_runner_fixture_not_measured_player_data", "received_pose_trace": {"record_count": 1, "base64": "synthetic_not_a_replay"},
		"conditions": conditions(str(segment.get("gain_hex", Store.default_profile().gain_hex)))}
	if segment.task in ["CLICK", "SWITCH"]:
		report["opportunities"] = 16 if segment.task == "CLICK" else 12
		report["raw_succeeded"] = 15 if segment.task == "CLICK" else 11
	return report


func durable_task(runner: ClockRunner, segment: Dictionary, utility: float = 0.55) -> Dictionary:
	var report: Dictionary = task_report(segment, utility)
	report["session_id"] = "trace_" + runner._calibration_id + "." + str(segment.segment_id)
	report["catalogue_revision"] = Calibration.REVISION
	report["score_version"] = "cal_utilities_R2"
	check(runner._store.save_report(report), "L'audit complet précède l'acceptation de la cellule : " + runner._store.last_error)
	report["trace_reference"] = {"session_id": report.session_id, "semantic_sha256": Canonical.semantic_sha256(report)}
	return report


func diagnostic_report(segment: Dictionary, utility: float = 0.55, duration_s: float = 15.0) -> Dictionary:
	var report: Dictionary = task_report(segment, utility)
	report["duration_s"] = duration_s
	report["elapsed_s"] = duration_s
	report["utility"] = null
	report["U"] = null
	report["diagnostic_utility"] = utility
	report["comparative_utility_included"] = false
	if segment.task in ["CLICK", "SWITCH"]:
		report["opportunities"] = (10 if segment.task == "CLICK" else 7) if duration_s == 15.0 else (16 if segment.task == "CLICK" else 12)
		report["raw_succeeded"] = report.opportunities
	return report


func record_preflight(runner: ClockRunner, utilities: Dictionary = {}) -> Dictionary:
	for segment: Dictionary in runner._segments:
		if segment.kind != "preflight":
			continue
		runner.timeline_at(float(segment.start_s))
		check(runner.record_familiarization(segment.segment_id, diagnostic_report(segment, float(utilities.get(segment.task, 0.55)))), "Le préflight non comparatif conserve l'audit complet : " + runner.error)
	var gate: Dictionary = runner.timeline_at(60.0 + float(runner._preflight.generation) * 84.0)
	check(gate.blocked and gate.kind == "preflight" and gate.reason == "PREFLIGHT_REVIEW_REQUIRED", "Aucune comparaison ne précède la revue volontaire du préflight.")
	return gate


func review_preflight(runner: ClockRunner, start: float) -> void:
	var gate: Dictionary = record_preflight(runner)
	check(runner.ready_task(gate.segment_id, start + float(gate.start_s) + runner._wait_total()), "Ready confirme explicitement les niveaux avant comparaison : " + runner.error)


func complete_day(runner: ClockRunner, start: float, role: int) -> Dictionary:
	var date: String = Time.get_date_string_from_unix_time(int(start))
	check(runner.start_day(role, start, date, conditions()), "Le rôle de journée autorisé démarre : " + runner.error)
	if not runner.active:
		return {}
	review_preflight(runner, start)
	var day: Dictionary = runner._epoch.session
	for period: Dictionary in day.periods:
		for cell: Dictionary in period.scored_cells:
			var countdown: Dictionary = runner.timeline_at(float(cell.countdown_start_s))
			check(countdown.kind == "countdown" and countdown.blocked, "Le décompte attend une action volontaire.")
			check(runner.ready_task(cell.cell_id, start + float(cell.countdown_start_s)), "La readiness est persistée avant le départ.")
			var measurement: Dictionary = runner.timeline_at(float(cell.scored_start_s))
			check(measurement.kind == "measurement" and measurement.time_origin == cell.scored_start_s and measurement.scored, "Le moteur reçoit le deck et l'origine exacte de la mesure.")
			var utility: float = 0.58 if period.candidate_id != "A" else 0.55
			check(runner.accept_task(cell.cell_id, durable_task(runner, measurement, utility), conditions(measurement.gain_hex), start + float(cell.scored_end_s)), "Le rapport réel du task-engine est committé avant le checkpoint : " + runner.error)
	var finished: Dictionary = runner.finish_day(start + float(day.planned_duration_s), date)
	check(not finished.is_empty() and finished.eligible, "Une journée complète et techniquement valide est acceptée : " + runner.error)
	return finished


func test_express_timeline_and_calendar() -> void:
	var store: Store = new_store()
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-12T12:00:00")
	var runner := ClockRunner.new(store, start)
	check(runner.prepare_express(store.load_profile(), conditions(), settings()), "L'express prépare et persiste un plan natif réel : " + runner.error)
	if runner.plan.is_empty():
		return
	check(not runner.plan.is_example and runner.plan.programmed_total_s == 696 and runner.plan.is_read_only(), "Le runner ne lit ni plan illustratif ni résultats humains fictifs.")
	var restored := ClockRunner.new(Store.new(store.root_path), start)
	check(restored.plan.plan_sha256 == runner.plan.plan_sha256 and restored.error.is_empty(), "Les hashes et doubles du plan survivent à sa persistance.")
	check(restored.start_day(0, start, "2026-10-12", conditions()), "Un plan préparé peut être repris avant de commencer une epoch.")
	var preflight: Dictionary = restored.timeline_at(0.0)
	check(preflight.kind == "preflight" and preflight.end_s == 15.0 and not preflight.scored, "Le préflight emploie un deck dédié non noté.")
	review_preflight(restored, start)
	var warmup: Dictionary = restored.timeline_at(60.0)
	check(warmup.kind == "acclimation" and warmup.end_s == 75.0 and not warmup.scored, "Une période commence par soixante secondes d'acclimatation, découpées en tâches.")
	check(restored.interrupt("abort"), "Le fixture interrompt son essai de timeline pour recommencer l'epoch entière.")
	var retry_start: float = start + 3600.0
	var completed: Dictionary = complete_day(restored, retry_start, 0)
	if completed.is_empty():
		return
	check(restored.result.status == "exploratory_only" and restored.result.accepted_epoch_by_day_role["0"] == 1, "L'express reste exploratoire et utilise la première epoch valide après interruption.")
	check(Canonical.float64_hex(restored.temporary_gain_deg_per_relative_unit) == restored.baseline_profile.gain_hex, "A est actif à la fin de l'express.")
	var end: float = float(completed.actual_end_utc)
	var early: float = end + 43200.0 - 1.0
	check(not restored.prepare_confirmation(conditions(), early, Time.get_date_string_from_unix_time(int(early))), "La confirmation ne démarre pas dans les douze heures après l'express.")
	check(restored.ui_state(early, Time.get_date_string_from_unix_time(int(early))).wait_remaining_s == 1.0, "L'UI expose une attente civile réelle.")
	var first_start: float = end + 43200.0
	check(restored.prepare_confirmation(conditions(), first_start, Time.get_date_string_from_unix_time(int(first_start))), "Exactement douze heures est admissible et le plan de confirmation est neuf : " + restored.error)
	if restored.plan.phase != "confirmation":
		return
	check(restored.plan.programmed_total_s == 2016 and restored.plan.plan_sha256 != runner.plan.plan_sha256, "Deux journées de 1008 s utilisent de nouveaux défis indépendants de l'express.")
	var day1: Dictionary = complete_day(restored, first_start, 1)
	if day1.is_empty():
		return
	check(restored.result.status == "incomplete", "Une seule journée n'autorise pas une conclusion confirmée.")
	check(not restored.start_day(1, first_start + 2000.0, Time.get_date_string_from_unix_time(int(first_start + 2000.0)), conditions()), "Une journée valide n'est jamais refaite pour sélectionner un meilleur score.")
	var second_early: float = first_start + 43200.0 - 1.0
	check(not restored.start_day(2, second_early, Time.get_date_string_from_unix_time(int(second_early)), conditions()), "Les douze heures entre départs acceptés sont contrôlées.")
	var too_late: float = first_start + 604800.0 + 1.0
	check(not restored.start_day(2, too_late, Time.get_date_string_from_unix_time(int(too_late)), conditions()), "La limite de 168 heures est contrôlée au départ.")
	var second_start: float = first_start + 86400.0
	check(not restored.start_day(2, second_start, str(day1.player_local_date), conditions()), "Des dates UTC différentes ne remplacent pas deux dates locales distinctes.")
	var day2: Dictionary = complete_day(restored, second_start, 2)
	if day2.is_empty():
		return
	check(restored.result.status == "repeated_improvement" and restored.ui_state(second_start + 1008.0, day2.player_local_date).can_apply, "Seules deux journées valides rendent disponible l'application explicite d'un candidat.")
	check(restored.plan.sessions[0].order != restored.plan.sessions[1].order, "ABBA/BAAB est inversé entre les deux jours.")
	var persisted: Dictionary = store.load_calibration_state()
	check(persisted.report_ids.size() >= 45 and persisted.baseline_profile.gain_hex == Store.default_profile().gain_hex, "Rapports/cells/jours et baseline A sont durables.")
	for row: Dictionary in store.history():
		if row.namespace == "v2" and row.report.get("kind") == "calibration_cell":
			check(not row.report.payload.cell.audit.has("received_pose_trace"), "Les poses haute fréquence restent externes au rapport normal compact.")
			check(row.report.payload.cell.audit.trace_reference.session_id in persisted.report_ids and row.report.payload.cell.audit.input_trace_event_count == 1, "La cellule compacte conserve une référence durable vers son audit et son nombre de poses.")


func test_restart_and_failed_checkpoint() -> void:
	var store: Store = new_store()
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-14T12:00:00")
	var runner := ClockRunner.new(store, start)
	check(runner.prepare_express(store.load_profile(), conditions(), settings()) and runner.start_day(0, start, "2026-10-14", conditions()), "Le fixture commence une epoch vraie avant de simuler le crash.")
	if not runner.active:
		return
	review_preflight(runner, start)
	var first: Dictionary = runner._epoch.session.periods[0].scored_cells[0]
	runner.timeline_at(first.countdown_start_s)
	check(runner.ready_task(first.cell_id, start + first.countdown_start_s), "La readiness est durable.")
	var segment: Dictionary = runner.timeline_at(first.scored_start_s)
	check(runner.accept_task(first.cell_id, durable_task(runner, segment), conditions(segment.gain_hex), start + first.scored_end_s), "Une cellule est durable avant le crash.")
	var before: Dictionary = store.load_calibration_state()
	var after := ClockRunner.new(Store.new(store.root_path), start + first.scored_end_s + 10.0)
	check(not after.active and Canonical.float64_hex(after.temporary_gain_deg_per_relative_unit) == before.baseline_profile.gain_hex, "Le redémarrage restaure A et n'active pas le gain temporaire.")
	check(after.result.status == "incomplete" and after._reports.size() == 1 and "process_restart" in after._reports[0].eligibility.reasons, "La journée partielle devient une epoch interrompue auditable, pas des scores repris.")
	check(after.start_day(0, start + 3600.0, "2026-10-14", conditions()), "La reprise commence l'epoch suivante complète.")
	check(after._epoch.session.attempt_epoch == 1 and after._cells.is_empty() and after._epoch.session.periods[0].scored_cells[0].deck_manifest_sha256 != first.deck_manifest_sha256, "La nouvelle epoch ne garde aucune cellule partielle et utilise de nouveaux défis.")
	after.now = start + 3700.0
	check(after.interrupt("focus_lost") and after.result.status == "unstable_conditions", "Une deuxième interruption épuise les deux tentatives sans choisir de meilleur score.")
	check(not after.start_day(0, start + 7200.0, "2026-10-14", conditions()), "Une troisième epoch est interdite.")
	var failure_store: Store = new_store()
	var failing := FailingStore.new(failure_store.root_path)
	var transaction := ClockRunner.new(failing, start)
	check(transaction.prepare_express(failing.load_profile(), conditions(), settings()) and transaction.start_day(0, start, "2026-10-14", conditions()), "Le fixture transactionnel démarre.")
	if not transaction.active:
		return
	review_preflight(transaction, start)
	first = transaction._epoch.session.periods[0].scored_cells[0]
	transaction.timeline_at(first.countdown_start_s)
	transaction.ready_task(first.cell_id, start + first.countdown_start_s)
	segment = transaction.timeline_at(first.scored_start_s)
	var original: Dictionary = durable_task(transaction, segment)
	var before_failure: Dictionary = failing.load_calibration_state()
	var history_count: int = failing.history().size()
	failing.fail_checkpoint = true
	check(not transaction.accept_task(first.cell_id, original, conditions(segment.gain_hex), start + first.scored_end_s), "Un échec de checkpoint est signalé après le commit du rapport.")
	check(failing.load_calibration_state().report_ids == before_failure.report_ids and failing.history().size() == history_count + 1, "Le checkpoint ne ment pas sur une cellule terminée ; le rapport original reste conservé.")
	failing.fail_checkpoint = false
	check(transaction.accept_task(first.cell_id, original, conditions(segment.gain_hex), start + first.scored_end_s + 0.1), "Le même commit peut être rejoué sans réécrire le rapport ni son premier timestamp.")
	check(failing.load_calibration_state().report_ids.size() == before_failure.report_ids.size() + 2 and failing.history().size() == history_count + 1, "Le retry est idempotent et ne compte pas deux cellules ; l'audit complet est référencé.")
	var second: Dictionary = transaction._epoch.session.periods[0].scored_cells[1]
	transaction.timeline_at(second.countdown_start_s)
	transaction.ready_task(second.cell_id, start + second.countdown_start_s)
	segment = transaction.timeline_at(second.scored_start_s)
	var changed_conditions: Dictionary = conditions(segment.gain_hex)
	changed_conditions.render_resolution_px = [1280, 720]
	check(not transaction.accept_task(second.cell_id, durable_task(transaction, segment), changed_conditions, start + second.scored_end_s) and not transaction.active, "Un changement de conditions interrompt toute l'epoch, même avec un score correct.")


func test_preflight_levels_and_archive() -> void:
	var store: Store = new_store()
	var failing := FailingStore.new(store.root_path)
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-14T00:30:00")
	var runner := ClockRunner.new(failing, start)
	var ui_settings: Dictionary = settings()
	ui_settings["difficulty_by_task"] = ui_settings.levels
	ui_settings.erase("levels")
	check(runner.prepare_express(failing.load_profile(), conditions(), ui_settings), "Le nom UI difficulty_by_task est accepté : " + runner.error)
	check(runner.ui_state(start, "2026-10-13", -300).can_continue, "L'UI accepte la date locale d'un fuseau UTC−5 même si UTC est déjà le lendemain.")
	check(not runner.ui_state(start, "2026-10-13", 0).can_continue, "Une date locale artificiellement incohérente n'est pas acceptée.")
	var local_conditions: Dictionary = conditions()
	local_conditions.player_utc_offset_minutes = -300
	check(runner.start_day(0, start, "2026-10-13", local_conditions), "L'epoch conserve le biais local, sans le figer dans les conditions comparatives.")
	if not runner.active:
		return
	var first: Dictionary = runner._segments[0]
	var wrong: Dictionary = diagnostic_report(first)
	wrong.opportunities = 16
	check(not runner.record_familiarization(first.segment_id, wrong), "La familiarisation CLICK emploie 10 opportunités et non le dénominateur de 24 secondes.")
	var gate: Dictionary = record_preflight(runner, {"CLICK": 0.05})
	var preflight_state: Dictionary = runner.ui_state(start + 60.0, "2026-10-13", -300).preflight
	check(preflight_state.proposals.size() == 1 and preflight_state.proposals[0].suggested_level == "novice", "Une utilité inférieure à 0,10 propose seulement le niveau voisin.")
	check(runner.prepare_level_adjustment("CLICK", "advanced").is_empty(), "Le saut non adjacent n'est jamais présenté comme un ajustement autorisé.")
	var original_hash: String = runner.plan.plan_sha256
	var trial: Dictionary = runner.prepare_level_adjustment("CLICK", "novice")
	check(not trial.is_empty() and trial.duration_s == 24.0 and not trial.scored, "Un ajustement crée un vrai deck de 24 secondes hors composite.")
	if trial.is_empty():
		return
	check(runner.ready_task(gate.segment_id, start + 65.0), "L'essai de niveau exige lui aussi un départ volontaire et conserve cinq secondes d'attente.")
	var trial_snapshot: Dictionary = runner.timeline_at(60.0)
	check(trial_snapshot.kind == "preflight_adjustment" and trial_snapshot.time_origin == 60.0 and not trial_snapshot.scored, "Le contrôleur conduit l'essai adapté sur la même horloge planifiée.")
	var trial_report: Dictionary = diagnostic_report(trial_snapshot, 0.55, 24.0)
	runner.timeline_at(84.0)
	check(not runner.record_adaptive_trial(trial.segment_id, trial_report, local_conditions, start + 88.0), "Une fausse fin avant 24 secondes réelles ne permet pas de figer le nouveau niveau.")
	failing.fail_checkpoint = true
	check(not runner.record_adaptive_trial(trial.segment_id, trial_report, local_conditions, start + 89.0), "Un défaut disque entre archive et checkpoint ne produit pas de faux nouveau plan.")
	failing.fail_checkpoint = false
	check(runner.record_adaptive_trial(trial.segment_id, trial_report, local_conditions, start + 89.5), "Le refreeze transactionnel se rejoue sans nouvelle seed ni réécriture des premiers timestamps : " + runner.error)
	check(runner.plan.plan_sha256 != original_hash and runner.plan.condition_snapshot.difficulty_by_task.CLICK == "novice", "La difficulté finale appartient à un nouveau plan avant la moindre comparaison.")
	check(runner._wait_total() == 5.0 and runner._preflight.generation == 1 and runner._cells.is_empty(), "Le budget ajoute 24 s d'essai et 60 s de préflight, sans inventer une attente supplémentaire au retry.")
	var repeated: Dictionary = runner.timeline_at(84.0)
	check(repeated.kind == "preflight" and repeated.start_s == 84.0 and repeated.end_s == 99.0, "Un préflight entier au nouveau niveau précède toute mesure.")
	gate = record_preflight(runner, {"CLICK": 0.99})
	trial = runner.prepare_level_adjustment("CLICK", "standard")
	check(not trial.is_empty(), "Un second changement adjacent de la même tâche reste possible.")
	if trial.is_empty():
		return
	check(runner.ready_task(gate.segment_id, start + 149.0), "Le deuxième essai démarre après la revue du nouveau préflight.")
	trial_snapshot = runner.timeline_at(144.0)
	trial_report = diagnostic_report(trial_snapshot, 0.55, 24.0)
	runner.timeline_at(168.0)
	check(runner.record_adaptive_trial(trial.segment_id, trial_report, local_conditions, start + 173.0), "Le deuxième essai de 24 secondes est complet et auditable : " + runner.error)
	record_preflight(runner, {"CLICK": 0.05, "SMOOTH": 0.05})
	preflight_state = runner.ui_state(start + 233.0, "2026-10-13", -300).preflight
	check(preflight_state.changes_by_task.CLICK == 2 and preflight_state.changes_by_task.SMOOTH == 0, "La limite porte sur chaque tâche, pas sur deux changements globaux.")
	var click_proposal: Dictionary = preflight_state.proposals[0]
	check(not click_proposal.can_adjust and click_proposal.configuration_review_required, "Après deux changements il faut expliquer que la configuration est à revoir.")
	check(runner.prepare_level_adjustment("CLICK", "novice").is_empty(), "Un troisième changement de la même tâche est refusé.")
	check(not runner.prepare_level_adjustment("SMOOTH", "novice").is_empty(), "Une autre tâche conserve son propre budget d'ajustements.")
	runner.now = start + 233.0
	var before_count: int = failing.history().size()
	check(runner.cancel_plan("synthetic_cancellation_fixture"), "L'annulation archive les données puis restaure durablement A : " + runner.error)
	check(failing.load_calibration_state().is_empty() and runner.plan.is_empty() and not runner.active, "L'annulation libère le verrou du profil et ne laisse pas de plan actif.")
	check(failing.load_profile().gain_hex == Store.default_profile().gain_hex and failing.history().size() >= before_count + 2, "Les anciens audits ne sont jamais supprimés et le gain A conserve ses bits.")
	check(runner.prepare_express(failing.load_profile(), conditions(), ui_settings), "Après l'archive, un nouvel express indépendant peut être préparé.")


func test_audit_reference_integrity() -> void:
	var store: Store = new_store()
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-15T12:00:00")
	var runner := ClockRunner.new(store, start)
	check(runner.prepare_express(store.load_profile(), conditions(), settings()) and runner.start_day(0, start, "2026-10-15", conditions()), "Le fixture d'intégrité commence un vrai plan natif.")
	if not runner.active:
		return
	review_preflight(runner, start)
	var first: Dictionary = runner._epoch.session.periods[0].scored_cells[0]
	runner.timeline_at(first.countdown_start_s)
	runner.ready_task(first.cell_id, start + first.countdown_start_s)
	var segment: Dictionary = runner.timeline_at(first.scored_start_s)
	check(not runner.accept_task(first.cell_id, task_report(segment), conditions(segment.gain_hex), start + first.scored_end_s), "Un résultat compact sans audit complet durable est refusé.")
	var full: Dictionary = durable_task(runner, segment)
	var bad: Dictionary = full.duplicate(true)
	bad.trace_reference.semantic_sha256 = "0".repeat(64)
	check(not runner.accept_task(first.cell_id, bad, conditions(segment.gain_hex), start + first.scored_end_s), "Le hash du payload complet, pas celui d'un rapport quelconque, est vérifié.")
	bad = full.duplicate(true)
	bad.utility = 0.56
	check(not runner.accept_task(first.cell_id, bad, conditions(segment.gain_hex), start + first.scored_end_s), "La référence ne permet pas de substituer une utilité après sauvegarde.")
	bad = full.duplicate(true)
	bad.trace_reference.session_id = "../profile"
	check(not runner.accept_task(first.cell_id, bad, conditions(segment.gain_hex), start + first.scored_end_s), "Un identifiant de trace ne peut pas sortir du namespace de rapports.")
	check(runner.accept_task(first.cell_id, full, conditions(segment.gain_hex), start + first.scored_end_s), "Le lien intact permet le commit de la mesure : " + runner.error)
	var state: Dictionary = store.load_calibration_state()
	check(full.trace_reference.session_id in state.report_ids and state.checkpoint.cells[first.cell_id].audit.input_trace_event_count == 1, "Le checkpoint conserve le lien intégral et le nombre de poses compactées.")
	var missing_path: String = store.root_path.path_join("reports").path_join(full.trace_reference.session_id + ".json")
	DirAccess.remove_absolute(missing_path)
	var restarted := ClockRunner.new(Store.new(store.root_path), start + first.scored_end_s + 1.0)
	check(not restarted.error.is_empty() and not restarted.active and Canonical.float64_hex(restarted.temporary_gain_deg_per_relative_unit) == Store.default_profile().gain_hex, "Une trace disparue à la reprise bloque les résultats et conserve A, jamais une mesure imaginaire.")


func test_recovery_commit_boundaries() -> void:
	var base: Store = new_store()
	var failing := FailingStore.new(base.root_path)
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-16T12:00:00")
	var runner := ClockRunner.new(failing, start)
	check(runner.prepare_express(failing.load_profile(), conditions(), settings()) and runner.start_day(0, start, "2026-10-16", conditions()), "Le fixture de crash entre commits démarre.")
	if not runner.active:
		return
	review_preflight(runner, start)
	var first: Dictionary = runner._epoch.session.periods[0].scored_cells[0]
	runner.timeline_at(first.countdown_start_s)
	runner.ready_task(first.cell_id, start + first.countdown_start_s)
	var measurement: Dictionary = runner.timeline_at(first.scored_start_s)
	var full: Dictionary = durable_task(runner, measurement)
	failing.fail_checkpoint = true
	check(not runner.accept_task(first.cell_id, full, conditions(measurement.gain_hex), start + first.scored_end_s), "Le rapport cellule peut être durable avant son checkpoint.")
	var recovery_failure := FailingStore.new(base.root_path)
	recovery_failure.fail_checkpoint = true
	var interrupted := ClockRunner.new(recovery_failure, start + first.scored_end_s + 10.0)
	check(not interrupted.error.is_empty() and not interrupted.active, "Un second crash au checkpoint de reprise n'active ni score partiel ni gain temporaire.")
	var history_count: int = failing.history().size()
	var recovered := ClockRunner.new(Store.new(base.root_path), start + first.scored_end_s + 20.0)
	check(recovered.error.is_empty() and not recovered.active and recovered.result.status == "incomplete", "La reprise rejoue le même footer interrompu sans conflit d'identifiant immuable : " + recovered.error)
	check(recovered._reports.size() == 1 and recovered._reports[0].cells.is_empty() and recovered._cells.is_empty(), "La cellule non committée n'est jamais récupérée comme score de la nouvelle epoch.")
	var state: Dictionary = failing.load_calibration_state()
	check(full.trace_reference.session_id in state.report_ids and state.checkpoint.recovery_context.uncommitted_cell_ids.size() == 1 and not state.checkpoint.recovery_context.partial_scores_reused, "Les documents déjà écrits sont reliés à l'audit de reprise sans devenir des scores.")
	check(failing.history().size() == history_count and failing.load_profile().gain_hex == Store.default_profile().gain_hex, "Le second redémarrage ne duplique pas le footer et restaure les mêmes bits A.")
	check(recovered.start_day(0, start + 3600.0, "2026-10-16", conditions()) and recovered._epoch.session.attempt_epoch == 1 and recovered._cells.is_empty(), "La tentative suivante rejoue la journée entière avec une nouvelle epoch.")
	var footer_base: Store = new_store()
	var footer_store := FailingStore.new(footer_base.root_path)
	var footer_runner := ClockRunner.new(footer_store, start)
	check(footer_runner.prepare_express(footer_store.load_profile(), conditions(), settings()) and footer_runner.start_day(0, start, "2026-10-16", conditions()), "Le fixture footer avant checkpoint démarre.")
	footer_runner.now = start + 1.0
	footer_store.fail_checkpoint = true
	check(not footer_runner.interrupt("focus_lost"), "Un footer est publié même si son checkpoint échoue ensuite.")
	var footer_id: String = footer_runner._calibration_id + "." + str(footer_runner._epoch.session.session_id)
	var footer_before: Dictionary = footer_store._read_document(footer_store.root_path.path_join("reports").path_join(footer_id + ".json"), "report")
	var resumed := ClockRunner.new(Store.new(footer_base.root_path), start + 2.0)
	check(resumed.error.is_empty() and not resumed.active and resumed._reports.size() == 1 and resumed.result.status == "incomplete", "Un footer antérieur non committé ne bloque pas la reprise par un conflit d'immutabilité.")
	var footer_after: Dictionary = footer_store._read_document(footer_store.root_path.path_join("reports").path_join(footer_id + ".json"), "report")
	check(footer_before.semantic_sha256 == footer_after.semantic_sha256 and footer_id in footer_store.load_calibration_state().report_ids, "Le footer original est conservé tel quel et relié au statut de reprise.")
	var adjustment_base: Store = new_store()
	var adjustment_store := FailingStore.new(adjustment_base.root_path)
	var adjustment := ClockRunner.new(adjustment_store, start)
	check(adjustment.prepare_express(adjustment_store.load_profile(), conditions(), settings()) and adjustment.start_day(0, start, "2026-10-16", conditions()), "Le fixture refreeze entre plans démarre.")
	var gate: Dictionary = record_preflight(adjustment, {"CLICK": 0.05})
	var trial: Dictionary = adjustment.prepare_level_adjustment("CLICK", "novice")
	if trial.is_empty():
		check(false, "Le fixture de refreeze reçoit un deck natif.")
		return
	adjustment.ready_task(gate.segment_id, start + 60.0)
	var trial_snapshot: Dictionary = adjustment.timeline_at(60.0)
	adjustment.timeline_at(84.0)
	adjustment_store.fail_refreeze_active = true
	check(not adjustment.record_adaptive_trial(trial.segment_id, diagnostic_report(trial_snapshot, 0.55, 24.0), conditions(), start + 84.0), "Le défaut disque laisse une transition durable avant d'activer le nouveau plan.")
	var interrupted_adjustment := ClockRunner.new(Store.new(adjustment_base.root_path), start + 85.0)
	check(interrupted_adjustment.error.is_empty() and not interrupted_adjustment.active and interrupted_adjustment.ui_state(start + 85.0, "2026-10-16").preflight.requires_new_express, "Un crash au refreeze invalide la journée, préserve l'historique et n'active aucun demi-plan : " + interrupted_adjustment.error)
	check(not interrupted_adjustment.start_day(0, start + 3600.0, "2026-10-16", conditions()), "Une transition incomplète exige un nouvel express, jamais la reprise avec les mauvais niveaux.")
	check(interrupted_adjustment.cancel_plan() and adjustment_store.load_calibration_state().is_empty() and adjustment_store.load_profile().gain_hex == Store.default_profile().gain_hex, "L'annulation de la transition libère le profil, conserve les archives et restaure A.")


func test_invalid_checkpoint_shapes() -> void:
	var store: Store = new_store()
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-17T12:00:00")
	var runner := ClockRunner.new(store, start)
	check(runner.prepare_express(store.load_profile(), conditions(), settings()), "Le fixture de validation de checkpoint part d'un plan réel.")
	var original: Dictionary = store.load_calibration_state()
	var invalid: Dictionary = original.duplicate(true)
	invalid.status = "active"
	invalid.checkpoint.stage = "active"
	check(store.save_calibration_state(invalid), "La couche stockage conserve un checkpoint JSON ; sa sémantique appartient au runner.")
	var recovered := ClockRunner.new(Store.new(store.root_path), start)
	check(recovered.error == "RUNNER_CHECKPOINT_ACTIVE_EPOCH_MISSING" and not recovered.active and Canonical.float64_hex(recovered.temporary_gain_deg_per_relative_unit) == Store.default_profile().gain_hex, "Une epoch absente n'est jamais activée et A est restauré sans erreur de script.")
	invalid = original.duplicate(true)
	invalid.checkpoint.reports = ["invalid_report_type"]
	check(store.save_calibration_state(invalid), "Le fixture persiste un type de rapport invalide sans NaN ni JSON malformé.")
	recovered = ClockRunner.new(Store.new(store.root_path), start)
	check(recovered.error == "RECOVERED_EPOCH_REPORT_INVALID" and not recovered.active, "Le runner rejette les types fermés de ses rapports avant toute conversion non sûre.")
	invalid = original.duplicate(true)
	invalid.checkpoint.preflight.reports["SMOOTH"] = "invalid_familiarization_type"
	check(store.save_calibration_state(invalid), "Le fixture persiste un diagnostic de mauvais type.")
	recovered = ClockRunner.new(Store.new(store.root_path), start)
	check(recovered.error == "RECOVERED_PREFLIGHT_INVALID" and not recovered.active, "Un diagnostic mal typé bloque proprement la reprise et ne devient pas un score.")


func profile_persistence() -> void:
	var base: Store = new_store()
	var store := TimedStore.new(base.root_path)
	var start: float = Time.get_unix_time_from_datetime_string("2026-10-18T12:00:00")
	var runner := ClockRunner.new(store, start)
	var before: int = Time.get_ticks_usec()
	check(runner.prepare_express(store.load_profile(), conditions(), settings()), "Le profilage prépare un plan natif, pas une simulation de performances Windows.")
	print("RUNNER PROFILE prepare_ms=%.3f reads_ms=%.3f writes_ms=%.3f reads=%d writes=%d" % [float(Time.get_ticks_usec() - before) / 1000.0, store.read_ms, store.write_ms, store.read_count, store.write_count])
	before = Time.get_ticks_usec()
	var validation: Dictionary = Calibration.validate_conditions(runner.plan, Runner._fixed_conditions(conditions()))
	check(validation.get("ok", false), "Le profilage utilise le validateur réel des conditions.")
	print("RUNNER PROFILE validate_conditions_ms=%.3f" % (float(Time.get_ticks_usec() - before) / 1000.0))
	store.read_ms = 0.0
	store.write_ms = 0.0
	store.read_count = 0
	store.write_count = 0
	before = Time.get_ticks_usec()
	check(runner.start_day(0, start, "2026-10-18", conditions()), "Le profilage génère et persiste la journée réelle.")
	print("RUNNER PROFILE start_day_ms=%.3f reads_ms=%.3f writes_ms=%.3f reads=%d writes=%d" % [float(Time.get_ticks_usec() - before) / 1000.0, store.read_ms, store.write_ms, store.read_count, store.write_count])
	store.read_ms = 0.0
	store.write_ms = 0.0
	store.read_count = 0
	store.write_count = 0
	before = Time.get_ticks_usec()
	var segment: Dictionary = runner._segments[0]
	check(runner.record_familiarization(segment.segment_id, diagnostic_report(segment)), "Le profilage conserve le vrai checkpoint après un diagnostic synthétique.")
	print("RUNNER PROFILE record_preflight_ms=%.3f reads_ms=%.3f writes_ms=%.3f reads=%d writes=%d bytes=%d" % [float(Time.get_ticks_usec() - before) / 1000.0, store.read_ms, store.write_ms, store.read_count, store.write_count, FileAccess.get_file_as_bytes(store.root_path.path_join("calibration_state.json")).size()])


func remove_root(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname in directory.get_directories():
		remove_root(path.path_join(dirname))
	DirAccess.remove_absolute(path)


func run() -> void:
	if "--profile-persistence" in OS.get_cmdline_user_args():
		profile_persistence()
		for path in roots:
			remove_root(path)
		print("V2 CALIBRATION RUNNER : %d assertions, %d échecs." % [assertions, failures])
		quit(1 if failures > 0 else 0)
		return
	var preflight_only: bool = "--preflight-only" in OS.get_cmdline_user_args()
	var recovery_only: bool = "--recovery-only" in OS.get_cmdline_user_args()
	if not preflight_only and not recovery_only:
		print("V2 CAL RUNNER · calendrier et journées complètes")
		test_express_timeline_and_calendar()
		print("V2 CAL RUNNER · reprise et checkpoint refusé")
		test_restart_and_failed_checkpoint()
	if not recovery_only:
		print("V2 CAL RUNNER · niveaux, archives et liens d'audit")
		test_preflight_levels_and_archive()
		test_audit_reference_integrity()
	if not preflight_only:
		print("V2 CAL RUNNER · crash entre commits et types fermés")
		test_recovery_commit_boundaries()
		test_invalid_checkpoint_shapes()
	for path in roots:
		remove_root(path)
	print("V2 CALIBRATION RUNNER : %d assertions, %d échecs." % [assertions, failures])
	quit(1 if failures > 0 else 0)
