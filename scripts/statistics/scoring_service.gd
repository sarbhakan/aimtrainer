class_name ScoringService
extends RefCounted

const VERSION: int = 1


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func validate_result(result: Dictionary) -> String:
	if not number(result.get("schema_version", null)) or result.schema_version != 1 or not number(result.get("score_version", null)) or result.score_version != VERSION:
		return "Version des données incompatible."
	if not result.get("profile", null) is Dictionary or not SensitivityService.validate_profile(result.profile).is_empty():
		return "Profil de séance invalide."
	if not result.get("metrics", null) is Dictionary:
		return "Mesures de séance absentes."
	for field in ["duration_s", "active_duration_s", "aspect", "score", "seed"]:
		if not number(result.get(field, null)):
			return "Mesure invalide : " + field
	if float(result.duration_s) <= 0.0 or float(result.duration_s) > 120.0 or float(result.aspect) <= 0.0 or float(result.score) < 0.0:
		return "Durée, format ou score hors limites."
	if float(result.active_duration_s) < 0.0 or float(result.active_duration_s) > float(result.duration_s) + 0.000001:
		return "Durée active incohérente."
	for field in ["completed", "valid"]:
		if not result.get(field, null) is bool:
			return "État de séance invalide."
	if result.completed and not is_equal_approx(float(result.active_duration_s), float(result.duration_s)):
		return "Une séance complète doit couvrir toute la durée."
	if not result.get("family", "") in ["click", "tracking", "switching"] or not result.get("comparison_key", null) is String or not result.get("scenario_fingerprint", null) is String:
		return "Contexte de séance invalide."
	for field in ["scenario_id", "engine_version"]:
		if not result.get(field, null) is String or result[field].is_empty():
			return "Contexte de séance absent : " + field
	if result.has("renderer") and (not result.renderer is String or result.renderer.is_empty()):
		return "Méthode de rendu invalide."
	if not number(result.get("scenario_revision", null)) or float(result.scenario_revision) < 1.0 or float(result.scenario_revision) != floor(float(result.scenario_revision)):
		return "Révision de séance invalide."
	if result.scenario_fingerprint.length() != 64 or not result.scenario_fingerprint.is_valid_hex_number():
		return "Empreinte de séance invalide."
	if reported_comparison_key(result) != result.comparison_key:
		return "Clé de comparaison incohérente avec les conditions réellement déclarées."
	var definition := ScenarioCatalog.find(result.scenario_id)
	if definition != null and definition.fingerprint() == result.scenario_fingerprint and (int(result.scenario_revision) != definition.revision or result.family != definition.family):
		return "Révision ou famille incompatible avec l’empreinte de l’exercice."
	var metrics: Dictionary = result.metrics
	for field in ["shots", "hits", "input_events", "input_buffer_overflows"]:
		if not number(metrics.get(field, null)) or float(metrics[field]) < 0.0 or float(metrics[field]) != floor(float(metrics[field])):
			return "Compteur invalide : " + field
	if float(metrics.hits) > float(metrics.shots):
		return "Plus de touches que de tirs."
	for field in ["accuracy_fraction", "on_target_ratio", "hits_per_s", "angular_path_deg"]:
		if not number(metrics.get(field, null)) or float(metrics[field]) < 0.0:
			return "Taux invalide : " + field
	if float(metrics.accuracy_fraction) > 1.0 or float(metrics.on_target_ratio) > 1.000001:
		return "Proportion hors limites."
	var expected_accuracy := float(metrics.hits) / maxf(float(metrics.shots), 1.0)
	var expected_cadence := float(metrics.hits) / maxf(float(result.active_duration_s), 0.000001)
	if not is_equal_approx(float(metrics.accuracy_fraction), expected_accuracy) or not is_equal_approx(float(metrics.hits_per_s), expected_cadence):
		return "Taux et compteurs incohérents."
	if metrics.has("misses") and (not number(metrics.misses) or float(metrics.misses) != float(metrics.shots) - float(metrics.hits)):
		return "Compteur de ratés incohérent."
	if metrics.has("accuracy_pct"):
		if float(metrics.shots) == 0.0 and metrics.accuracy_pct != null:
			return "Précision disponible sans tir."
		if float(metrics.shots) > 0.0 and (not number(metrics.accuracy_pct) or not is_equal_approx(float(metrics.accuracy_pct), expected_accuracy * 100.0)):
			return "Pourcentage de précision incohérent."
	if result.family == "tracking":
		for field in ["on_target_time_s", "angular_error_mean_deg", "angular_error_p95_deg"]:
			if not number(metrics.get(field, null)) or float(metrics[field]) < 0.0:
				return "Mesure de tracking invalide : " + field
		var legacy_tracking: bool = not metrics.has("target_exposed_time_s") and result.get("app_version", "") in ["0.1.0", "0.2.0", "0.3.0"]
		var exposure: Variant = result.active_duration_s if legacy_tracking else metrics.get("target_exposed_time_s", null)
		if not number(exposure) or float(exposure) < 0.0:
			return "Durée d’exposition de tracking absente ou invalide."
		var exposed_s: float = float(exposure)
		if float(metrics.on_target_time_s) > exposed_s + 0.000001 or exposed_s > float(result.active_duration_s) + 0.000001:
			return "Durées de tracking incohérentes."
		if not is_equal_approx(float(metrics.on_target_ratio), float(metrics.on_target_time_s) / maxf(exposed_s, 0.000001)):
			return "Ratio de tracking incohérent."
		if result.completed and not is_equal_approx(exposed_s, float(result.active_duration_s)):
			return "Intégration de tracking incomplète."
	if result.valid and int(metrics.input_buffer_overflows) > 0:
		return "Saturation de tampon non signalée."
	if result.has("reference_hits_s") and (not number(result.reference_hits_s) or float(result.reference_hits_s) <= 0.0):
		return "Cadence de référence invalide."
	var explanation := explain(result)
	if explanation.expected_score != null and float(result.score) != float(explanation.expected_score):
		return "Score incohérent avec les mesures et la formule V1."
	return ""


static func has_activity(result: Dictionary) -> bool:
	if not result.get("metrics", null) is Dictionary or not result.get("family", "") in ["click", "tracking", "switching"]:
		return false
	var metrics: Dictionary = result.metrics
	for field in ["input_events", "angular_path_deg"]:
		if not number(metrics.get(field, null)) or float(metrics[field]) <= 0.0:
			return false
	return result.family == "tracking" or (number(metrics.get("shots", null)) and float(metrics.shots) >= 3.0)


static func comparison_error(result: Dictionary, expected_key: String = "") -> String:
	if not result.get("completed", null) is bool or not result.completed:
		return "Séance interrompue : les records exigent une durée complète."
	if not result.get("valid", null) is bool or not result.valid:
		return "Séance invalide : " + str(result.get("invalid_reason", "mesures non fiables."))
	if not result.get("warmup", false) is bool:
		return "État d’échauffement invalide."
	if result.get("warmup", false):
		return "Échauffement : exclu des records et tendances."
	if not number(result.get("score_version", VERSION)) or result.get("score_version", VERSION) != VERSION:
		return "Version de score incompatible avec le score V1."
	if not number(result.get("score", null)) or float(result.score) < 0.0:
		return "Score non fini ou négatif."
	if not result.get("comparison_key", null) is String or result.comparison_key.is_empty():
		return "Contexte de comparaison absent."
	if not expected_key.is_empty() and result.comparison_key != expected_key:
		return "Conditions différentes : comparer uniquement la même clé de configuration."
	if result.has("schema_version"):
		var validation_error: String = validate_result(result)
		if not validation_error.is_empty():
			return validation_error
		var definition: ScenarioDefinition = ScenarioCatalog.find(str(result.get("scenario_id", "")))
		if definition != null and definition.fingerprint() == result.scenario_fingerprint:
			if comparison_key(definition, float(result.duration_s), result.profile, float(result.aspect)) != result.comparison_key:
				return "Clé de comparaison incohérente avec les conditions de la séance."
			if result.has("reference_hits_s") and (not number(result.reference_hits_s) or float(result.reference_hits_s) != definition.reference_hits_s):
				return "Cadence de référence incohérente avec l’empreinte du scénario."
	if not result.get("metrics", null) is Dictionary:
		return "Mesures de séance absentes."
	var overflows: Variant = result.metrics.get("input_buffer_overflows", 0)
	if not number(overflows) or float(overflows) != 0.0:
		return "Tampon d’input saturé ou mesure de saturation invalide."
	if not has_activity(result):
		return "Activité insuffisante : mouvement mesuré et au moins trois tirs pour le clic."
	var explanation: Dictionary = explain(result)
	if explanation.expected_score != null and float(result.score) != float(explanation.expected_score):
		return "Score incohérent avec les mesures et la formule V1."
	return ""


static func explain(result: Dictionary) -> Dictionary:
	var metrics: Dictionary = result.get("metrics", {}) if result.get("metrics", {}) is Dictionary else {}
	var tracking: bool = result.get("family", "") == "tracking"
	var reference_hits_s: Variant = result.get("reference_hits_s", null)
	if reference_hits_s == null:
		var definition: ScenarioDefinition = ScenarioCatalog.find(str(result.get("scenario_id", "")))
		if definition != null and definition.fingerprint() == result.get("scenario_fingerprint", ""):
			reference_hits_s = definition.reference_hits_s
	if not number(reference_hits_s) or float(reference_hits_s) <= 0.0:
		reference_hits_s = null
	var measured_utility: Variant = null
	if tracking and number(metrics.get("on_target_ratio", null)) and float(metrics.on_target_ratio) >= 0.0 and float(metrics.on_target_ratio) <= 1.000001:
		measured_utility = float(metrics.on_target_ratio)
	elif not tracking and number(metrics.get("hits_per_s", null)) and number(metrics.get("accuracy_fraction", null)) and float(metrics.hits_per_s) >= 0.0 and float(metrics.accuracy_fraction) >= 0.0 and float(metrics.accuracy_fraction) <= 1.0:
		measured_utility = utility(result)
	var expected_score: Variant = null
	if measured_utility != null and (tracking or reference_hits_s != null):
		expected_score = round(1000.0 * float(measured_utility) / (1.0 if tracking else float(reference_hits_s)))
	return {"score_version": VERSION, "utility": measured_utility, "utility_unit": "ratio" if tracking else "touches/s",
		"utility_formula": "temps sur cible / temps exposé" if tracking else "cadence de touches × précision²",
		"score_formula": "arrondi(1000 × temps sur cible / temps exposé)" if tracking else "arrondi(1000 × cadence de touches × précision² / cadence de référence)",
		"reference_hits_s": reference_hits_s, "expected_score": expected_score,
		"components": {"hits_per_s": metrics.get("hits_per_s", null), "accuracy_fraction": metrics.get("accuracy_fraction", null),
			"on_target_time_s": metrics.get("on_target_time_s", null), "target_exposed_time_s": metrics.get("target_exposed_time_s", null),
			"on_target_ratio": metrics.get("on_target_ratio", null)},
		"conditions": "Même empreinte de scénario, version de score, durée, DPI, cm/360°, FOV vertical, ratio, accumulation, limite FPS, inversion et moteur."}


static func calibration_quality_error(result: Dictionary) -> String:
	if not has_activity(result):
		return "Activité insuffisante : bouger la souris et effectuer au moins trois tirs pour un exercice de clic."
	if not result.get("performance", null) is Dictionary:
		return "Mesures de performances absentes."
	var performance: Dictionary = result.performance
	for field in ["frame_samples", "frametime_p99_ms", "max_frametime_ms"]:
		if not number(performance.get(field, null)) or float(performance[field]) < 0.0:
			return "Mesures de performances invalides."
	if int(performance.frame_samples) < 2:
		return "Pas assez de frames observées."
	if float(performance.frametime_p99_ms) > 50.0 or float(performance.max_frametime_ms) > 250.0:
		return "Séance trop saccadée (p99 > 50 ms ou frame > 250 ms) : stabiliser les performances et recommencer."
	return ""


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var middle := ordered.size() / 2
	return float(ordered[middle]) if ordered.size() % 2 else (float(ordered[middle - 1]) + float(ordered[middle])) * 0.5


static func percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return float(ordered[clampi(int(ceil(fraction * ordered.size())) - 1, 0, ordered.size() - 1)])


static func utility(result: Dictionary) -> float:
	var metrics: Dictionary = result.get("metrics", {})
	if result.get("family", "") == "tracking":
		return float(metrics.get("on_target_ratio", 0.0))
	return float(metrics.get("hits_per_s", 0.0)) * pow(float(metrics.get("accuracy_fraction", 0.0)), 2.0)


static func score(result: Dictionary, reference_hits_s: float) -> float:
	if result.get("family", "") == "tracking":
		return round(1000.0 * utility(result))
	return round(1000.0 * utility(result) / reference_hits_s)


static func comparison_key(definition: ScenarioDefinition, duration_s: float, profile: Dictionary, aspect: float) -> String:
	return JSON.stringify([definition.fingerprint(), VERSION, float(duration_s), float(profile.dpi),
		float(profile.cm_per_360), float(profile.vertical_fov_deg), snappedf(aspect, 0.0001),
		bool(profile.get("accumulated_input", true)), int(profile.get("max_fps", 144)), bool(profile.get("invert_y", false)), "4.7.2", "compatibility"]).sha256_text()


static func reported_comparison_key(result: Dictionary) -> String:
	var profile: Dictionary = result.profile
	return JSON.stringify([result.scenario_fingerprint, int(result.score_version), float(result.duration_s), float(profile.dpi),
		float(profile.cm_per_360), float(profile.vertical_fov_deg), snappedf(float(result.aspect), 0.0001),
		bool(profile.get("accumulated_input", true)), int(profile.get("max_fps", 144)), bool(profile.get("invert_y", false)), result.engine_version, result.get("renderer", "compatibility")]).sha256_text()
