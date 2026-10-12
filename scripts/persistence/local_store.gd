class_name LocalStore
extends RefCounted

const LEGACY_CALIBRATION_PARAMETERS: Array[Array] = [
	["C02", 1, "click", "static", "scatter", 0.65, 4.0, 3.0, 1.4, 12.0, 1, 0.0, 1.6, 8.0],
	["C04", 1, "click", "static", "scatter", 1.4, 24.0, 10.0, 14.0, 12.0, 1, 0.0, 1.8, 8.0],
	["S01", 1, "switching", "static", "scatter", 1.3, 22.0, 10.0, 4.0, 12.0, 4, 0.0, 2.8, 8.0],
	["T01", 1, "tracking", "horizontal", "scatter", 2.0, 12.0, 3.0, 2.5, 12.0, 1, 0.0, 2.0, 8.0],
	["T05", 1, "tracking", "strafe", "scatter", 1.8, 12.0, 3.0, 2.5, 26.0, 1, 0.0, 2.0, 8.0]
]
const LEGACY_CALIBRATION_FACTORS: Array[float] = [0.9, 1.0, 1.1]

var root_path: String = "user://aim_local"
var last_error: String = ""


func _init(path: String = "user://aim_local") -> void:
	root_path = path


func identifier() -> String:
	return "%016d-%s" % [int(Time.get_unix_time_from_system() * 1000.0), Crypto.new().generate_random_bytes(8).hex_encode()]


func valid_identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 96 and value.is_valid_filename() and not value in [".", ".."]


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": true, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024:
		last_error = "Fichier inaccessible ou trop volumineux : " + path
		return {"ok": false, "missing": false, "data": {}}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary or not ScoringService.number(parser.data.get("schema_version", null)) or float(parser.data.schema_version) != 1.0:
		last_error = "Fichier invalide conservé : " + path
		return {"ok": false, "missing": false, "data": {}}
	return {"ok": true, "missing": false, "data": parser.data}


func write_json(path: String, data: Dictionary, immutable: bool = false) -> bool:
	last_error = ""
	if FileAccess.file_exists(path):
		if immutable or not read_json(path).ok:
			last_error = "Écriture refusée pour préserver le fichier existant : " + path
			return false
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		last_error = "Impossible de créer le dossier de données."
		return false
	var temporary := absolute + ".tmp-" + identifier()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Impossible d'ouvrir le fichier temporaire."
		return false
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Écriture des données incomplète ; le fichier original est conservé."
		return false
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
		last_error = "Impossible de sauvegarder la version précédente."
		return false
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		last_error = "Impossible de remplacer les données ; backup et fichier temporaire conservés."
		return false
	return true


func load_profile() -> Dictionary:
	var saved := read_json(root_path + "/profile.json")
	if saved.ok and SensitivityService.validate_profile(saved.data).is_empty():
		return saved.data
	if not saved.get("missing", false):
		last_error = "Profil invalide conservé. Réglages par défaut utilisés sans écrasement."
	return SensitivityService.default_profile()


func save_profile(profile: Dictionary) -> bool:
	var error := SensitivityService.validate_profile(profile)
	if not error.is_empty():
		last_error = error
		return false
	var existing := read_json(root_path + "/profile.json")
	if existing.ok and not SensitivityService.validate_profile(existing.data).is_empty():
		last_error = "Profil existant incohérent conservé ; sauvegarde refusée."
		return false
	return write_json(root_path + "/profile.json", profile)


func save_session(report: Dictionary) -> bool:
	last_error = ScoringService.validate_result(report)
	if not last_error.is_empty():
		return false
	if not report.has("session_id"):
		report.session_id = identifier()
	if not valid_identifier(report.session_id):
		last_error = "Identifiant de séance invalide."
		return false
	report.created_at_utc = Time.get_datetime_string_from_system(true) + "Z"
	return write_json(root_path + "/sessions/" + str(report.session_id) + ".json", report, true)


func save_checkpoint(data: Dictionary) -> bool:
	if not checkpoint_shape_is_valid(data):
		last_error = "Nouveau checkpoint incompatible ou invalide ; sauvegarde refusée."
		return false
	var verifier := CalibrationService.new()
	if not verifier.restore(data):
		last_error = verifier.error
		return false
	var existing := read_json(root_path + "/calibration_checkpoint.json")
	if not existing.ok and not existing.missing:
		return false
	if existing.ok:
		if checkpoint_integer(existing.data.get("protocol_version", null)) and int(existing.data.protocol_version) == 1:
			if not legacy_checkpoint_is_valid(existing.data):
				last_error = "Ancien checkpoint inconnu ou incohérent conservé ; sauvegarde refusée."
				return false
			if not archive_checkpoint(existing.data):
				return false
		elif checkpoint_integer(existing.data.get("protocol_version", null)) and int(existing.data.protocol_version) == 2:
			if not checkpoint_shape_is_valid(existing.data) or not CalibrationRevisionArchive.recognized_checkpoint(existing.data):
				last_error = "Ancienne comparaison incohérente conservée ; sauvegarde refusée."
				return false
			if not archive_checkpoint(existing.data):
				return false
		elif not checkpoint_shape_is_valid(existing.data):
			last_error = "Checkpoint existant incohérent conservé ; sauvegarde refusée."
			return false
		elif not verifier.restore(existing.data):
			if not CalibrationRevisionArchive.recognized_checkpoint(existing.data):
				last_error = "Checkpoint existant incohérent conservé ; sauvegarde refusée."
				return false
			if not archive_checkpoint(existing.data):
				return false
	return write_json(root_path + "/calibration_checkpoint.json", data)


func checkpoint_integer(value: Variant) -> bool:
	return ScoringService.number(value) and absf(float(value)) < 9007199254740992.0 and float(value) == floor(float(value))


func checkpoint_trial_types_are_safe(trial: Dictionary) -> bool:
	for field in ["schema_version", "score_version"]:
		if not checkpoint_integer(trial.get(field, null)) or int(trial[field]) != 1:
			return false
	for field in ["candidate_index", "repetition", "comfort", "scenario_revision", "seed"]:
		if not checkpoint_integer(trial.get(field, null)):
			return false
	for field in ["scenario_id", "family", "scenario_fingerprint", "comparison_key", "engine_version"]:
		if not trial.get(field, null) is String:
			return false
	return trial.get("scored", null) is bool


func checkpoint_shape_is_valid(data: Dictionary) -> bool:
	if not checkpoint_integer(data.get("schema_version", null)) or int(data.schema_version) != 1:
		return false
	if not checkpoint_integer(data.get("protocol_version", null)) or not int(data.protocol_version) in [2, CalibrationService.PROTOCOL_VERSION]:
		return false
	if not data.get("baseline", null) is Dictionary or not data.get("trials", null) is Array or not data.get("status", null) is String:
		return false
	if not checkpoint_integer(data.get("seed", null)) or not checkpoint_integer(data.get("current_index", null)) or not ScoringService.number(data.get("aspect", null)):
		return false
	for trial in data.trials:
		if not trial is Dictionary or not checkpoint_trial_types_are_safe(trial):
			return false
	return true


func legacy_checkpoint_is_valid(data: Dictionary) -> bool:
	for version_field in ["schema_version", "protocol_version"]:
		if not checkpoint_integer(data.get(version_field, null)) or int(data[version_field]) != 1:
			return false
	if not data.get("baseline", null) is Dictionary or not data.get("trials", null) is Array or not data.get("status", null) is String or not valid_identifier(data.get("calibration_id", null)):
		return false
	if not checkpoint_integer(data.get("seed", null)) or not checkpoint_integer(data.get("current_index", null)):
		return false
	if not ScoringService.number(data.get("aspect", null)) or float(data.aspect) <= 0.0:
		return false
	var baseline: Dictionary = data.baseline
	if baseline.has("schema_version") and (not checkpoint_integer(baseline.schema_version) or int(baseline.schema_version) != 1):
		return false
	if not SensitivityService.validate_profile(baseline).is_empty() or float(baseline.cm_per_360) < 5.5 or float(baseline.cm_per_360) > 135.0:
		return false
	var trial_count: int = data.trials.size()
	if trial_count > 60 or int(data.current_index) != trial_count or data.get("status", "") != ("complete" if trial_count == 60 else "active"):
		return false
	var horizontal_fov_deg: float = SensitivityService.horizontal_fov_deg(float(baseline.vertical_fov_deg), float(data.aspect))
	for parameters in LEGACY_CALIBRATION_PARAMETERS:
		if float(parameters[6]) + float(parameters[5]) >= horizontal_fov_deg * 0.5 or float(parameters[7]) + float(parameters[5]) >= float(baseline.vertical_fov_deg) * 0.5:
			return false
	for trial_index in trial_count:
		if not data.trials[trial_index] is Dictionary or not legacy_trial_is_valid(data.trials[trial_index], data, trial_index):
			return false
	return true


func legacy_trial_is_valid(trial: Dictionary, checkpoint: Dictionary, trial_index: int) -> bool:
	if not checkpoint_trial_types_are_safe(trial):
		return false
	if not ScoringService.validate_result(trial).is_empty() or not ScoringService.calibration_quality_error(trial).is_empty() or not trial.completed or not trial.valid:
		return false
	var repetition: int = -1
	var scenario_index: int = int(trial_index / 3)
	var candidate_index: int = trial_index % 3
	if trial_index >= 15:
		var measured_index: int = trial_index - 15
		repetition = int(measured_index / 15)
		scenario_index = (int((measured_index % 15) / 3) + repetition) % 5
		candidate_index = (repetition + scenario_index + measured_index % 3) % 3
	var parameters: Array = LEGACY_CALIBRATION_PARAMETERS[scenario_index]
	var duration_s: float = 8.0 if repetition < 0 else 12.0
	var seed_value: int = int(checkpoint.seed) + scenario_index * 7919 + (repetition + 1) * 1009
	if int(trial.candidate_index) != candidate_index or int(trial.repetition) != repetition or not trial.get("scored", null) is bool or trial.scored != (repetition >= 0):
		return false
	if int(trial.comfort) < 1 or int(trial.comfort) > 5 or int(trial.scenario_revision) != 1 or int(trial.seed) != seed_value:
		return false
	var fingerprint: String = JSON.stringify(parameters).sha256_text()
	if trial.get("scenario_id", "") != parameters[0] or trial.family != parameters[2] or trial.scenario_fingerprint != fingerprint or trial.get("engine_version", "") != "4.7.2":
		return false
	if not is_equal_approx(float(trial.duration_s), duration_s) or not is_equal_approx(float(trial.aspect), float(checkpoint.aspect)):
		return false
	var baseline: Dictionary = checkpoint.baseline
	var profile: Dictionary = trial.profile
	if not is_equal_approx(float(profile.dpi), float(baseline.dpi)) or not is_equal_approx(float(profile.vertical_fov_deg), float(baseline.vertical_fov_deg)):
		return false
	if not is_equal_approx(float(profile.cm_per_360), float(baseline.cm_per_360) / LEGACY_CALIBRATION_FACTORS[candidate_index]):
		return false
	for field in ["accumulated_input", "max_fps", "invert_y"]:
		var fallback: Variant = 144 if field == "max_fps" else field == "accumulated_input"
		if profile.get(field, fallback) != baseline.get(field, fallback):
			return false
	var comparison_key: String = JSON.stringify([fingerprint, 1, duration_s, float(profile.dpi),
		float(profile.cm_per_360), float(profile.vertical_fov_deg), snappedf(float(checkpoint.aspect), 0.0001),
		bool(profile.get("accumulated_input", true)), int(profile.get("max_fps", 144)), bool(profile.get("invert_y", false)), "4.7.2", "compatibility"]).sha256_text()
	return trial.comparison_key == comparison_key


func load_checkpoint() -> Dictionary:
	var loaded := read_json(root_path + "/calibration_checkpoint.json")
	if not loaded.ok:
		return {}
	if not checkpoint_shape_is_valid(loaded.data):
		last_error = "Checkpoint incompatible ou invalide conservé."
		return {}
	if int(loaded.data.protocol_version) == 2:
		last_error = "Exercices mis à jour : l’ancienne comparaison est conservée. Démarrez une nouvelle comparaison." if CalibrationRevisionArchive.recognized_checkpoint(loaded.data) else "Ancienne comparaison invalide conservée."
		return {}
	var verifier := CalibrationService.new()
	if not verifier.restore(loaded.data):
		last_error = "Exercices mis à jour : l’ancienne comparaison est conservée. Démarrez une nouvelle comparaison." if CalibrationRevisionArchive.recognized_checkpoint(loaded.data) else "Checkpoint invalide conservé : " + verifier.error
		return {}
	return loaded.data


func validate_guided_checkpoint(data: Dictionary, definitions: Dictionary = {}) -> String:
	if not checkpoint_integer(data.get("schema_version", null)) or int(data.schema_version) != 1 or not data.get("phase", null) in ["comparing", "transition", "complete"]:
		return "Recherche guidée de version inconnue ou invalide."
	if not data.get("search_state", null) is Dictionary or not data.get("comparison", null) is Dictionary:
		return "État de recherche ou comparaison absent."
	var search := AdaptiveSensitivityService.new()
	search.scenario_overrides = definitions.duplicate()
	if not search.restore(data.search_state):
		return search.error
	var comparison := CalibrationService.new()
	comparison.scenario_overrides = definitions.duplicate()
	if not checkpoint_shape_is_valid(data.comparison) or not comparison.restore(data.comparison):
		return "Comparaison guidée invalide : " + comparison.error
	var spec: Dictionary
	if data.phase == "comparing":
		if search.finished:
			return "Recherche terminée avec un passage encore actif."
		spec = search.current_spec()
	else:
		if search.history.is_empty() or not comparison.current_stage().is_empty() or search.finished != (data.phase == "complete"):
			return "Transition de recherche incohérente."
		var last_comparison: Dictionary = search.history.back()
		spec = last_comparison.search_step.spec
		if not AdaptiveSensitivityService.same_value(last_comparison.trials, comparison.trials):
			return "Le bilan accepté ne correspond pas aux passages sauvegardés."
	if comparison.calibration_id != spec.calibration_id or comparison.calibration_seed != int(spec.seed) or not is_equal_approx(comparison.aspect, float(spec.aspect)):
		return "Identifiant, graine ou format de recherche incohérent."
	if not AdaptiveSensitivityService.same_value(comparison.baseline, spec.profile) or not AdaptiveSensitivityService.same_value(comparison.speed_factors, spec.speed_factors):
		return "La plage sauvegardée diffère de la comparaison prévue."
	return ""


func save_guided_checkpoint(data: Dictionary) -> bool:
	last_error = validate_guided_checkpoint(data)
	if not last_error.is_empty():
		return false
	var path := root_path + "/guided_calibration_checkpoint.json"
	var existing := read_json(path)
	if not existing.ok and not existing.missing:
		return false
	if existing.ok:
		last_error = validate_guided_checkpoint(existing.data)
		if not last_error.is_empty():
			if not validate_guided_checkpoint(existing.data, CalibrationRevisionArchive.definitions()).is_empty():
				return false
			if not archive_guided_checkpoint(existing.data):
				return false
		elif existing.data.search_state.state.search_id != data.search_state.state.search_id and not archive_guided_checkpoint(existing.data):
			return false
	return write_json(path, data)


func load_guided_checkpoint() -> Dictionary:
	var loaded := read_json(root_path + "/guided_calibration_checkpoint.json")
	if not loaded.ok:
		return {}
	last_error = validate_guided_checkpoint(loaded.data)
	if not last_error.is_empty() and validate_guided_checkpoint(loaded.data, CalibrationRevisionArchive.definitions()).is_empty():
		last_error = "Exercices mis à jour : l’ancienne recherche est conservée. Démarrez une nouvelle recherche."
	return loaded.data if last_error.is_empty() else {}


func archive_guided_checkpoint(data: Dictionary) -> bool:
	var path := root_path + "/guided_calibration_checkpoint.json"
	var contents := checkpoint_bytes(path)
	var parsed: Variant = JSON.parse_string(contents.get_string_from_utf8())
	if not parsed is Dictionary or not AdaptiveSensitivityService.same_value(parsed, data):
		last_error = "Recherche modifiée ou illisible ; archivage refusé."
		return false
	var identifier: String = data.search_state.state.search_id
	if not valid_identifier(identifier):
		last_error = "Identifiant de recherche invalide."
		return false
	var absolute := ProjectSettings.globalize_path(root_path + "/archives/guided-" + identifier + ".json")
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		last_error = "Dossier d’archive inaccessible."
		return false
	var lock_path := absolute + ".lock"
	if DirAccess.make_dir_absolute(lock_path) != OK:
		last_error = "Archive verrouillée ; recherche conservée."
		return false
	var archived := publish_checkpoint_archive(absolute, contents)
	if DirAccess.remove_absolute(lock_path) != OK:
		last_error = "Verrou d’archive conservé ; recherche non remplacée."
		return false
	return archived


func save_calibration(report: Dictionary) -> bool:
	if not valid_identifier(report.get("calibration_id", null)):
		last_error = "Identifiant de bilan invalide."
		return false
	var path := root_path + "/calibrations/" + str(report.calibration_id) + ".json"
	if FileAccess.file_exists(path):
		var existing := read_json(path)
		var normalized: Variant = JSON.parse_string(JSON.stringify(report, "", true, true))
		if existing.ok and normalized is Dictionary and existing.data.get("trials", []) == normalized.get("trials", []) and existing.data.get("baseline", {}) == normalized.get("baseline", {}):
			return true
		last_error = "Bilan existant conservé ; remplacement refusé."
		return false
	report.created_at_utc = Time.get_datetime_string_from_system(true) + "Z"
	return write_json(path, report, true)


func sessions() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var directory := DirAccess.open(root_path + "/sessions")
	if directory == null:
		return results
	var filenames := directory.get_files()
	filenames.sort()
	for file_index in range(maxi(0, filenames.size() - 2000), filenames.size()):
		var filename := filenames[file_index]
		if not filename.ends_with(".json"):
			continue
		var saved := read_json(root_path + "/sessions/" + filename)
		if saved.ok and ScoringService.validate_result(saved.data).is_empty():
			results.append(saved.data)
	return results


func archive_checkpoint(data: Dictionary) -> bool:
	last_error = ""
	if not valid_identifier(data.get("calibration_id", null)):
		last_error = "Checkpoint invalide conservé ; archivage refusé."
		return false
	var contents: PackedByteArray = checkpoint_bytes(root_path + "/calibration_checkpoint.json")
	if contents.is_empty():
		return false
	var parser: JSON = JSON.new()
	if parser.parse(contents.get_string_from_utf8()) != OK or not parser.data is Dictionary or parser.data != data:
		last_error = "Checkpoint modifié ou invalide conservé ; archivage refusé."
		return false
	var absolute: String = ProjectSettings.globalize_path(root_path + "/archives/" + str(data.calibration_id) + ".json")
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		last_error = "Impossible de créer le dossier d'archives ; checkpoint conservé."
		return false
	var lock_path: String = absolute + ".lock"
	if DirAccess.make_dir_absolute(lock_path) != OK:
		last_error = "Archive en cours ou verrou existant ; checkpoint conservé."
		return false
	var archived: bool = publish_checkpoint_archive(absolute, contents)
	if DirAccess.remove_absolute(lock_path) != OK:
		last_error = "Impossible de libérer le verrou d'archive ; checkpoint conservé."
		return false
	return archived


func checkpoint_bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Fichier d'archive inaccessible ; checkpoint conservé."
		return PackedByteArray()
	var length: int = file.get_length()
	if length <= 0 or length > 8 * 1024 * 1024:
		last_error = "Fichier d'archive vide ou trop volumineux ; checkpoint conservé."
		return PackedByteArray()
	var contents: PackedByteArray = file.get_buffer(length)
	var error: Error = file.get_error()
	file.close()
	if error != OK or contents.size() != length:
		last_error = "Lecture d'archive incomplète ; checkpoint conservé."
		return PackedByteArray()
	return contents


func publish_checkpoint_archive(absolute: String, contents: PackedByteArray) -> bool:
	if FileAccess.file_exists(absolute):
		if checkpoint_bytes(absolute) == contents:
			return true
		last_error = "Archive existante différente conservée ; nouveau checkpoint refusé."
		return false
	if DirAccess.dir_exists_absolute(absolute):
		last_error = "Chemin d'archive déjà occupé ; checkpoint conservé."
		return false
	var temporary: String = absolute + ".tmp-" + identifier()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Impossible d'ouvrir l'archive temporaire ; checkpoint conservé."
		return false
	file.store_buffer(contents)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or checkpoint_bytes(temporary) != contents:
		DirAccess.remove_absolute(temporary)
		last_error = "Écriture d'archive incomplète ; checkpoint conservé."
		return false
	if FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute) or DirAccess.rename_absolute(temporary, absolute) != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "Impossible de publier l'archive immuable ; checkpoint conservé."
		return false
	return true


func export_sessions() -> String:
	var results := sessions()
	var prefix := root_path + "/exports/" + identifier()
	if not write_json(prefix + ".json", {"schema_version": 1, "sessions": results}, true):
		return ""
	var file := FileAccess.open(prefix + ".csv", FileAccess.WRITE)
	if file == null:
		last_error = "Impossible de créer l'export CSV."
		return ""
	file.store_csv_line(PackedStringArray(["session_id", "created_at_utc", "scenario_id", "scenario_revision", "completed", "valid", "warmup", "dpi", "cm_per_360", "active_duration_s", "shots", "hits", "accuracy_pct", "on_target_ratio", "angular_error_mean_deg", "score", "score_version", "comparison_key", "received_x_counts", "received_y_counts"]))
	for result in results:
		var metrics: Dictionary = result.metrics
		var profile: Dictionary = result.profile
		var row := PackedStringArray()
		for value in [result.get("session_id", ""), result.get("created_at_utc", ""), result.get("scenario_id", ""), result.get("scenario_revision", 1), result.get("completed", false), result.get("valid", false), result.get("warmup", false), profile.get("dpi", 0), profile.get("cm_per_360", 0), result.get("active_duration_s", 0), metrics.get("shots", 0), metrics.get("hits", 0), metrics.get("accuracy_pct", null), metrics.get("on_target_ratio", 0), metrics.get("angular_error_mean_deg", 0), result.get("score", 0), result.get("score_version", 1), result.get("comparison_key", ""), metrics.get("received_x_counts", null), metrics.get("received_y_counts", null)]:
			row.append("" if value == null else str(value))
		file.store_csv_line(row)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		last_error = "Export CSV incomplet."
		return ""
	return ProjectSettings.globalize_path(prefix.get_base_dir())
