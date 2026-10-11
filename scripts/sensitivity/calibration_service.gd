class_name CalibrationService
extends RefCounted

const PROTOCOL_VERSION: int = 3
const SCENARIOS: Array[String] = ["C02", "C04", "S01", "T01", "T05"]
const FACTORS: Array[float] = [0.9, 1.0, 1.1]
const WEIGHTS: Dictionary = {"balanced": [0.2, 0.2, 0.2, 0.2, 0.2],
	"precision": [0.3, 0.25, 0.2, 0.15, 0.1], "tracking": [0.1, 0.1, 0.1, 0.35, 0.35]}

var baseline: Dictionary = {}
var aspect: float = 16.0 / 9.0
var calibration_seed: int = 1
var calibration_id: String = ""
var speed_factors: Array[float] = FACTORS.duplicate()
var plan: Array[Dictionary] = []
var trials: Array[Dictionary] = []
var current_index: int = 0
var error: String = ""


func begin(profile: Dictionary, viewport_aspect: float, seed_value: int, identifier: String, speed_factors: Array = FACTORS) -> bool:
	error = SensitivityService.validate_profile(profile)
	if not error.is_empty():
		return false
	if not SensitivityService.positive(viewport_aspect) or identifier.is_empty() or not identifier.is_valid_filename() or identifier in [".", ".."] or identifier.length() > 96:
		error = "Format de fenêtre ou identifiant de calibration invalide."
		return false
	if absf(float(seed_value)) >= 9007199254640992.0:
		error = "Graine de calibration hors limites."
		return false
	var factors: Array[float] = []
	if speed_factors.size() != 3:
		error = "Une comparaison exige exactement trois facteurs de vitesse."
		return false
	for factor in speed_factors:
		if not ScoringService.number(factor) or not SensitivityService.positive(float(factor)):
			error = "Les facteurs de vitesse doivent être positifs et finis."
			return false
		factors.append(float(factor))
	factors.sort()
	if factors[1] != 1.0 or is_equal_approx(factors[0], factors[1]) or is_equal_approx(factors[1], factors[2]):
		error = "Trois vitesses distinctes doivent encadrer la référence centrale (facteur 1)."
		return false
	for factor in factors:
		var distance_cm: float = float(profile.cm_per_360) / factor
		if not is_finite(distance_cm) or distance_cm < 5.0 or distance_cm > 150.0:
			error = "Les trois candidats doivent rester entre 5 et 150 cm/360°."
			return false
	for scenario_id in SCENARIOS:
		if not ScenarioCatalog.find(scenario_id).fits_view(float(profile.vertical_fov_deg), viewport_aspect):
			error = "Champ de vision trop étroit pour " + scenario_id + " : élargir la fenêtre ou augmenter le FOV."
			return false
	baseline = profile.duplicate(true)
	aspect = viewport_aspect
	calibration_seed = seed_value
	calibration_id = identifier
	self.speed_factors.assign(factors)
	plan.clear()
	trials.clear()
	current_index = 0
	for scenario_index in SCENARIOS.size():
		for candidate_index in self.speed_factors.size():
			plan.append(stage(scenario_index, candidate_index, -1))
		for repetition in 3:
			for order_index in self.speed_factors.size():
				var candidate_index := (repetition + scenario_index + order_index) % self.speed_factors.size()
				plan.append(stage(scenario_index, candidate_index, repetition))
	return true


func stage(scenario_index: int, candidate_index: int, repetition: int) -> Dictionary:
	return {"scenario_id": SCENARIOS[scenario_index], "candidate_index": candidate_index,
		"repetition": repetition, "scored": repetition >= 0, "duration_s": 12.0 if repetition >= 0 else 8.0,
		"block_index": scenario_index, "seed": calibration_seed + scenario_index * 7919 + (repetition + 1) * 1009}


func candidate_profile(candidate_index: int) -> Dictionary:
	if baseline.is_empty() or candidate_index < 0 or candidate_index >= speed_factors.size():
		return {}
	var profile := baseline.duplicate(true)
	profile.cm_per_360 = float(baseline.cm_per_360) / speed_factors[candidate_index]
	return profile


func current_stage() -> Dictionary:
	return plan[current_index].duplicate(true) if current_index >= 0 and current_index < plan.size() else {}


func accept(report: Dictionary, comfort: int) -> bool:
	if not integer(report.get("seed", null)) or not integer(report.get("scenario_revision", null)):
		error = "Graine ou révision de séance invalide."
		return false
	error = ScoringService.validate_result(report)
	if not error.is_empty():
		return false
	var expected := current_stage()
	if expected.is_empty() or not report.get("completed", false) or not report.get("valid", false):
		error = "Séance interrompue ou invalide : recommencer ce passage."
		return false
	error = ScoringService.calibration_quality_error(report)
	if not error.is_empty():
		return false
	var profile: Dictionary = report.get("profile", {})
	var candidate := candidate_profile(int(expected.candidate_index))
	if report.get("scenario_id", "") != expected.scenario_id or int(report.get("seed", -1)) != int(expected.seed):
		error = "Scénario ou graine incompatible avec le protocole."
		return false
	if report.get("scenario_fingerprint", "") != ScenarioCatalog.find(expected.scenario_id).fingerprint() or int(report.scenario_revision) != ScenarioCatalog.find(expected.scenario_id).revision:
		error = "Révision du scénario incompatible."
		return false
	if report.family != ScenarioCatalog.find(expected.scenario_id).family or report.get("engine_version", "") != "4.7.2" or report.get("renderer", "compatibility") != "compatibility":
		error = "Famille ou version du moteur incompatible."
		return false
	for field in ["dpi", "cm_per_360", "vertical_fov_deg"]:
		if not profile.has(field) or not is_equal_approx(float(profile[field]), float(candidate[field])):
			error = "Les conditions de calibration ont changé : " + field
			return false
	if not is_equal_approx(float(report.get("duration_s", 0.0)), float(expected.duration_s)) or not is_equal_approx(float(report.get("aspect", 0.0)), aspect):
		error = "Durée ou format de fenêtre incompatible."
		return false
	if int(report.get("score_version", -1)) != ScoringService.VERSION or profile.get("accumulated_input", true) != baseline.get("accumulated_input", true) or profile.get("max_fps", 144) != baseline.get("max_fps", 144) or profile.get("invert_y", false) != baseline.get("invert_y", false):
		error = "Version de score ou paramètres d'input/rendu incompatibles."
		return false
	if report.comparison_key != ScoringService.comparison_key(ScenarioCatalog.find(expected.scenario_id), float(expected.duration_s), candidate, aspect):
		error = "Contexte de comparaison incompatible."
		return false
	var trial := report.duplicate(true)
	trial.candidate_index = int(expected.candidate_index)
	trial.repetition = int(expected.repetition)
	trial.scored = bool(expected.scored)
	trial.comfort = clampi(comfort, 1, 5)
	trials.append(trial)
	current_index += 1
	error = ""
	return true


func checkpoint() -> Dictionary:
	return {"schema_version": 1, "protocol_version": PROTOCOL_VERSION, "baseline": baseline.duplicate(true),
		"aspect": aspect, "seed": calibration_seed, "calibration_id": calibration_id,
		"speed_factors": speed_factors.duplicate(), "report_context": report_context(),
		"current_index": current_index, "trials": trials.duplicate(true), "status": "active" if current_index < plan.size() else "complete"}


func report_context() -> Dictionary:
	var fingerprints: Dictionary = {}
	for scenario_id in SCENARIOS:
		fingerprints[scenario_id] = ScenarioCatalog.find(scenario_id).fingerprint()
	return {"score_version": ScoringService.VERSION, "engine_version": "4.7.2",
		"renderer": "compatibility", "scenario_fingerprints": fingerprints}


static func integer(value: Variant) -> bool:
	return ScoringService.number(value) and absf(float(value)) < 9007199254740992.0 and float(value) == floor(float(value))


func restore(data: Dictionary) -> bool:
	var restored := CalibrationService.new()
	if not restored.restore_data(data):
		error = restored.error
		return false
	baseline = restored.baseline
	aspect = restored.aspect
	calibration_seed = restored.calibration_seed
	calibration_id = restored.calibration_id
	speed_factors = restored.speed_factors
	plan = restored.plan
	trials = restored.trials
	current_index = restored.current_index
	error = ""
	return true


func restore_data(data: Dictionary) -> bool:
	if not integer(data.get("schema_version", null)) or data.schema_version != 1 or not integer(data.get("protocol_version", null)) or not int(data.protocol_version) in [2, PROTOCOL_VERSION] or not data.get("baseline", null) is Dictionary or not data.get("trials", null) is Array:
		error = "Ce test provient d’une autre version ou est invalide. Il reste conservé ; démarrez une nouvelle comparaison."
		return false
	for field in ["aspect", "seed", "current_index"]:
		if not ScoringService.number(data.get(field, null)):
			error = "Valeur de checkpoint invalide : " + field
			return false
	for field in ["seed", "current_index"]:
		if not integer(data[field]):
			error = "Compteur de checkpoint non entier : " + field
			return false
	if not data.get("calibration_id", null) is String:
		error = "Identifiant de checkpoint invalide."
		return false
	var factors: Array = FACTORS.duplicate()
	if int(data.protocol_version) == PROTOCOL_VERSION:
		if not data.get("speed_factors", null) is Array or not data.get("report_context", null) is Dictionary:
			error = "Facteurs ou contexte du protocole 3 absents."
			return false
		factors = data.speed_factors.duplicate()
	elif data.has("speed_factors") and data.speed_factors != FACTORS:
		error = "Le protocole 2 exige les facteurs historiques."
		return false
	if not begin(data.baseline, float(data.get("aspect", 0.0)), int(data.get("seed", 1)), str(data.get("calibration_id", "")), factors):
		return false
	if int(data.protocol_version) == PROTOCOL_VERSION:
		var context: Dictionary = data.report_context
		var expected_context := report_context()
		if data.speed_factors != speed_factors or context.size() != expected_context.size() or not integer(context.get("score_version", null)) or int(context.score_version) != ScoringService.VERSION or context.get("engine_version", null) != expected_context.engine_version or context.get("renderer", null) != expected_context.renderer or context.get("scenario_fingerprints", null) != expected_context.scenario_fingerprints:
			error = "Facteurs triés ou contexte de checkpoint incohérents."
			return false
	if data.trials.size() > plan.size():
		error = "Nombre de passages invalide."
		return false
	for trial in data.trials:
		if not trial is Dictionary:
			error = "Passage de checkpoint invalide."
			return false
		for field in ["candidate_index", "repetition", "comfort", "seed", "scenario_revision", "schema_version", "score_version"]:
			if not integer(trial.get(field, null)):
				error = "Compteur de passage invalide : " + field
				return false
		if int(trial.comfort) < 1 or int(trial.comfort) > 5 or not trial.get("scored", null) is bool:
			error = "Confort ou état de passage invalide."
			return false
		for field in ["scenario_id", "family", "scenario_fingerprint", "comparison_key", "engine_version"]:
			if not trial.get(field, null) is String:
				error = "Contexte de passage invalide : " + field
				return false
		var expected := current_stage()
		if trial.get("candidate_index", -1) != expected.candidate_index or trial.get("repetition", -2) != expected.repetition or trial.get("scored", null) != expected.scored:
			error = "Ordre des passages incohérent."
			return false
		if trial.has("warmup") and (not trial.warmup is bool or trial.warmup != (not bool(expected.scored))):
			error = "Familiarisation de checkpoint incohérente."
			return false
		if not accept(trial, int(trial.comfort)):
			return false
	if current_index != int(data.get("current_index", -1)):
		error = "Progression du checkpoint incohérente."
		return false
	if data.get("status", "") != ("active" if current_index < plan.size() else "complete"):
		error = "État du checkpoint incohérent."
		return false
	return true


func recommendation() -> Dictionary:
	if baseline.is_empty() or plan.is_empty():
		return {"status": "insufficient", "apply_allowed": false}
	var candidates: Array[Dictionary] = []
	var complete_data: bool = current_index == plan.size() and not plan.is_empty()
	var weights: Array = WEIGHTS[baseline.get("goal", "balanced")]
	var total_weight: float = 0.0
	for weight in weights:
		total_weight += float(weight)
	for candidate_index in speed_factors.size():
		candidates.append({"index": candidate_index, "cm_per_360": candidate_profile(candidate_index).cm_per_360,
			"value": 0.0, "spread": 0.0, "per_scenario": {}, "comfort_values": []})
	for scenario_index in SCENARIOS.size():
		var scenario_id := SCENARIOS[scenario_index]
		var medians: Array[float] = []
		var deviations: Array[float] = []
		for candidate_index in speed_factors.size():
			var utilities: Array[float] = []
			for trial in trials:
				if not trial.get("scored", false) or trial.candidate_index != candidate_index or trial.scenario_id != scenario_id:
					continue
				if not ScoringService.has_activity(trial):
					continue
				utilities.append(ScoringService.utility(trial))
				candidates[candidate_index].comfort_values.append(int(trial.comfort))
			complete_data = complete_data and utilities.size() == 3
			var median_value := ScoringService.median(utilities)
			var distances: Array[float] = []
			for utility in utilities:
				distances.append(absf(utility - median_value))
			medians.append(median_value)
			deviations.append(1.4826 * ScoringService.median(distances))
			candidates[candidate_index].per_scenario[scenario_id] = {"median_utility": median_value,
				"dispersion": deviations.back(), "samples": utilities.size()}
		var best_median: float = medians.max()
		complete_data = complete_data and best_median > 0.0
		for candidate_index in speed_factors.size():
			var weight := float(weights[scenario_index]) / total_weight
			candidates[candidate_index].value += weight * medians[candidate_index] / maxf(best_median, 0.000001)
			candidates[candidate_index].spread += weight * deviations[candidate_index] / maxf(best_median, 0.000001)
	for candidate in candidates:
		candidate.comfort_median = ScoringService.median(candidate.comfort_values)
		candidate.erase("comfort_values")
	candidates.sort_custom(func(candidate_left: Dictionary, candidate_right: Dictionary) -> bool:
		if float(candidate_left.value) == float(candidate_right.value):
			return abs(int(candidate_left.index) - 1) < abs(int(candidate_right.index) - 1) if abs(int(candidate_left.index) - 1) != abs(int(candidate_right.index) - 1) else int(candidate_left.index) < int(candidate_right.index)
		return float(candidate_left.value) > float(candidate_right.value))
	var best: Dictionary = candidates[0]
	var runner_up: Dictionary = candidates[1]
	var gap := float(best.value) - float(runner_up.value)
	var threshold := maxf(0.03, sqrt(pow(float(best.spread), 2.0) + pow(float(runner_up.spread), 2.0)))
	var status := "indicative" if complete_data and gap > threshold else "uncertain"
	if not complete_data:
		status = "insufficient"
	elif float(best.comfort_median) <= 2.0:
		status = "uncomfortable"
	var accepted_cm: Array[float] = []
	for candidate in candidates:
		if float(best.value) - float(candidate.value) <= threshold:
			accepted_cm.append(float(candidate.cm_per_360))
	accepted_cm.sort()
	return {"schema_version": 1, "protocol_version": PROTOCOL_VERSION, "calibration_id": calibration_id,
		"aspect": aspect, "seed": calibration_seed, "speed_factors": speed_factors.duplicate(), "report_context": report_context(),
		"status": status, "candidates": candidates, "goal": baseline.get("goal", "balanced"),
		"weights": weights.duplicate(), "score_gap": gap, "dispersion_threshold": threshold,
		"best_tested_cm_per_360": best.cm_per_360, "recommended_cm_per_360": best.cm_per_360 if status == "indicative" else baseline.cm_per_360,
		"range_cm_per_360": [accepted_cm.front(), accepted_cm.back()], "apply_allowed": status == "indicative",
		"boundary_best": int(best.index) != 1, "trials_completed": current_index, "trials_expected": plan.size(),
		"baseline": baseline.duplicate(true), "trials": trials.duplicate(true), "scenario_results": all_scenario_scores()}


func scenario_scores(scenario_id: String, pending_report: Dictionary = {}) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var stage_data := current_stage()
	for candidate_index in speed_factors.size():
		var scores: Array[float] = []
		for trial in trials:
			if trial.scored and trial.scenario_id == scenario_id and int(trial.candidate_index) == candidate_index:
				scores.append(float(trial.score))
		if not pending_report.is_empty() and not stage_data.is_empty() and stage_data.scored and stage_data.scenario_id == scenario_id and int(stage_data.candidate_index) == candidate_index:
			if pending_report.get("completed", false) and pending_report.get("valid", false) and ScoringService.calibration_quality_error(pending_report).is_empty():
				scores.append(float(pending_report.score))
		results.append({"candidate_index": candidate_index, "label": ["A · plus lent", "B · départ", "C · plus rapide"][candidate_index],
			"sensitivity": SensitivityService.game_sensitivity(float(baseline.dpi), float(candidate_profile(candidate_index).cm_per_360), SensitivityService.APP_YAW_DEG),
			"samples": scores.size(), "median_score": ScoringService.median(scores) if not scores.is_empty() else null})
	return results


func all_scenario_scores() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for scenario_id in SCENARIOS:
		summaries.append({"scenario_id": scenario_id, "candidates": scenario_scores(scenario_id)})
	return summaries
