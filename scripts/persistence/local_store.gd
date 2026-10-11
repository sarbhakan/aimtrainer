class_name LocalStore
extends RefCounted

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
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary or parser.data.get("schema_version", -1) != 1:
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
	var verifier := CalibrationService.new()
	if not verifier.restore(data):
		last_error = verifier.error
		return false
	var existing := read_json(root_path + "/calibration_checkpoint.json")
	if existing.ok and not verifier.restore(existing.data):
		last_error = "Checkpoint existant incohérent conservé ; sauvegarde refusée."
		return false
	return write_json(root_path + "/calibration_checkpoint.json", data)


func load_checkpoint() -> Dictionary:
	var loaded := read_json(root_path + "/calibration_checkpoint.json")
	if not loaded.ok:
		return {}
	var verifier := CalibrationService.new()
	if not verifier.restore(loaded.data):
		last_error = "Checkpoint invalide conservé : " + verifier.error
		return {}
	return loaded.data


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
	if not valid_identifier(data.get("calibration_id", null)):
		last_error = "Checkpoint invalide conservé ; archivage refusé."
		return false
	var path := root_path + "/archives/" + str(data.calibration_id) + ".json"
	if FileAccess.file_exists(path):
		return read_json(path).ok
	return write_json(path, data, true)


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
