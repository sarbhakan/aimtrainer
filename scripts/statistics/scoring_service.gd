class_name ScoringService
extends RefCounted

const VERSION: int = 1


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func validate_result(result: Dictionary) -> String:
	if result.get("schema_version", 0) != 1 or result.get("score_version", 0) != VERSION:
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
	if result.valid and int(metrics.input_buffer_overflows) > 0:
		return "Saturation de tampon non signalée."
	return ""


static func has_activity(result: Dictionary) -> bool:
	var metrics: Dictionary = result.get("metrics", {})
	return int(metrics.get("input_events", 0)) > 0 and float(metrics.get("angular_path_deg", 0.0)) > 0.0 and (result.get("family", "") == "tracking" or int(metrics.get("shots", 0)) >= 3)


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
