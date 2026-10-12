class_name ProgressiveCalibrationService
extends RefCounted

const PROTOCOL_VERSION: int = 4
const TRIALS_PER_BLOCK: int = 5
const SCENARIOS: Array[String] = ["C02", "C04", "S01", "T01", "T05"]
const TOTAL_TRIALS: int = 25
const SPEED_EPSILON: float = 0.000000001

var baseline: Dictionary = {}
var aspect: float = 16.0 / 9.0
var calibration_seed: int = 1
var calibration_id: String = ""
var duration_s: float = 60.0
var exploration: bool = true
var trials: Array[Dictionary] = []
var blocks: Array[Dictionary] = []
var error: String = ""
var lower_log: float = 0.0
var upper_log: float = 0.0
var center_log: float = 0.0
var current_log: float = 0.0
var block_trials: Array[Dictionary] = []
var initial_span_log: float = 0.0


func begin(profile: Dictionary, viewport_aspect: float, seed_value: int, identifier: String, trial_duration_s: float = 60.0, wide_search: bool = true) -> bool:
	error = SensitivityService.validate_profile(profile)
	if not error.is_empty():
		return false
	if not SensitivityService.positive(viewport_aspect) or not trial_duration_s in [45.0, 60.0] or identifier.is_empty() or not identifier.is_valid_filename() or identifier in [".", ".."] or identifier.length() > 96 or absf(float(seed_value)) > 2147000000:
		error = "Paramètres de calibration progressive invalides."
		return false
	for scenario_id in SCENARIOS:
		var definition := ScenarioCatalog.find(scenario_id)
		if definition == null or not definition.validate().is_empty() or not definition.fits_view(float(profile.vertical_fov_deg), viewport_aspect):
			error = "Champ de vision incompatible avec " + scenario_id + "."
			return false
	baseline = profile.duplicate(true)
	aspect = viewport_aspect
	calibration_seed = seed_value
	calibration_id = identifier
	duration_s = trial_duration_s
	exploration = wide_search
	trials.clear()
	blocks.clear()
	block_trials.clear()
	initial_span_log = log(1.6 if exploration else 1.2)
	lower_log = maxf(-initial_span_log, minimum_log())
	upper_log = minf(initial_span_log, maximum_log())
	center_log = 0.0
	current_log = 0.0
	return true


func minimum_log() -> float:
	return log(float(baseline.cm_per_360) / 150.0)


func maximum_log() -> float:
	return log(float(baseline.cm_per_360) / 5.0)


func completed() -> bool:
	return trials.size() == TOTAL_TRIALS


func candidate_profile() -> Dictionary:
	if baseline.is_empty() or completed():
		return {}
	var profile := baseline.duplicate(true)
	profile.cm_per_360 = clampf(float(baseline.cm_per_360) / exp(current_log), 5.0, 150.0)
	return profile


func current_stage() -> Dictionary:
	if baseline.is_empty() or completed():
		return {}
	var profile := candidate_profile()
	var speed_offset_pct := (exp(current_log - center_log) - 1.0) * 100.0
	var direction := "Départ" if block_trials.is_empty() else "Plus rapide" if current_log - center_log > SPEED_EPSILON else "Plus lent"
	return {"scenario_id": SCENARIOS[blocks.size()], "block_index": blocks.size(), "trial_index": block_trials.size(),
		"duration_s": duration_s, "seed": calibration_seed + blocks.size() * 7919, "scored": true,
		"profile": profile, "direction": direction, "speed_offset_pct": speed_offset_pct,
		"active_sensitivity": SensitivityService.game_sensitivity(profile.dpi, profile.cm_per_360, SensitivityService.APP_YAW_DEG),
		"title": ScenarioCopy.title(ScenarioCatalog.find(SCENARIOS[blocks.size()])), "total_trials": TOTAL_TRIALS,
		"completed_trials": trials.size(), "block_history": block_history()}


func block_history() -> Array[Dictionary]:
	var history: Array[Dictionary] = []
	for trial in block_trials:
		history.append({"family": trial.family, "sensitivity": SensitivityService.game_sensitivity(trial.profile.dpi, trial.profile.cm_per_360, SensitivityService.APP_YAW_DEG),
			"score": trial.score, "hits": trial.metrics.hits, "misses": trial.metrics.misses, "accuracy_pct": trial.metrics.accuracy_pct,
			"on_target_ratio": trial.metrics.on_target_ratio, "utility": ScoringService.utility(trial)})
	return history


func same_value(first: Variant, second: Variant) -> bool:
	if ScoringService.number(first) and ScoringService.number(second):
		return absf(float(first) - float(second)) <= 0.000000000001 * maxf(1.0, maxf(absf(float(first)), absf(float(second))))
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size():
			return false
		for key in first:
			if not second.has(key) or not same_value(first[key], second[key]):
				return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size():
			return false
		for value_index in first.size():
			if not same_value(first[value_index], second[value_index]):
				return false
		return true
	return first == second


func accept(report: Dictionary) -> bool:
	var stage := current_stage()
	if stage.is_empty():
		error = "Aucun essai en attente."
		return false
	error = ScoringService.validate_result(report)
	if error.is_empty():
		error = ScoringService.calibration_quality_error(report)
	if not error.is_empty():
		return false
	var definition := ScenarioCatalog.find(stage.scenario_id)
	if not report.completed or not report.valid or report.get("warmup", true) != false or report.get("calibration_id", "") != calibration_id:
		error = "L’essai doit être terminé et associé à ce parcours."
		return false
	if report.scenario_id != stage.scenario_id or report.seed != stage.seed or report.scenario_fingerprint != definition.fingerprint() or report.scenario_revision != definition.revision:
		error = "L’exercice ou sa graine ne correspond pas à l’essai prévu."
		return false
	if not same_value(report.profile, stage.profile) or not same_value(report.duration_s, duration_s) or not same_value(report.aspect, aspect) or report.get("renderer", "") != "compatibility" or report.engine_version != "4.7.2":
		error = "Les conditions ont changé ; rejouez cet essai."
		return false
	if report.comparison_key != ScoringService.comparison_key(definition, duration_s, report.profile, aspect):
		error = "Le contexte enregistré ne correspond pas au réglage testé."
		return false
	if (report.has("progressive_block_index") and report.progressive_block_index != blocks.size()) or (report.has("progressive_trial_index") and report.progressive_trial_index != block_trials.size()):
		error = "L’ordre des essais a changé."
		return false
	var trial := report.duplicate(true)
	trial.progressive_block_index = blocks.size()
	trial.progressive_trial_index = block_trials.size()
	trials.append(trial)
	block_trials.append(trial)
	if block_trials.size() == TRIALS_PER_BLOCK:
		close_block()
	elif not select_next():
		trials.pop_back()
		block_trials.pop_back()
		error = "Aucun réglage distinct disponible dans cette zone."
		return false
	error = ""
	return true


func speed_log(trial: Dictionary) -> float:
	return log(float(baseline.cm_per_360) / float(trial.profile.cm_per_360))


func best_trial() -> Dictionary:
	var best: Dictionary = block_trials[0]
	for trial in block_trials:
		var utility := ScoringService.utility(trial)
		var best_utility := ScoringService.utility(best)
		var tolerance := 0.0000000001 * maxf(1.0, maxf(absf(utility), absf(best_utility)))
		if utility > best_utility + tolerance or (absf(utility - best_utility) <= tolerance and absf(speed_log(trial) - center_log) < absf(speed_log(best) - center_log) - SPEED_EPSILON):
			best = trial
	return best


func untested(candidate_log: float) -> bool:
	if candidate_log < lower_log - SPEED_EPSILON or candidate_log > upper_log + SPEED_EPSILON:
		return false
	for trial in block_trials:
		if absf(candidate_log - speed_log(trial)) < SPEED_EPSILON:
			return false
	return true


func select_next() -> bool:
	var proposal_log: float
	if block_trials.size() == 1:
		proposal_log = upper_log if upper_log - center_log > SPEED_EPSILON else lower_log
	elif block_trials.size() == 2:
		var first_log := speed_log(block_trials[0])
		var second_log := speed_log(block_trials[1])
		var first_utility := ScoringService.utility(block_trials[0])
		var second_utility := ScoringService.utility(block_trials[1])
		if second_utility > first_utility + 0.0000000001 * maxf(1.0, maxf(first_utility, second_utility)):
			proposal_log = (first_log + second_log) * 0.5
		else:
			proposal_log = lower_log if second_log > first_log else upper_log
	else:
		var best_log := speed_log(best_trial())
		if blocks.is_empty() and exploration and block_trials.size() == 3 and absf(best_log - upper_log) < SPEED_EPSILON and upper_log < maximum_log() - SPEED_EPSILON:
			upper_log = minf(maximum_log(), upper_log + initial_span_log)
			proposal_log = upper_log
		elif blocks.is_empty() and exploration and block_trials.size() == 3 and absf(best_log - lower_log) < SPEED_EPSILON and lower_log > minimum_log() + SPEED_EPSILON:
			lower_log = maxf(minimum_log(), lower_log - initial_span_log)
			proposal_log = lower_log
		else:
			proposal_log = gap_proposal(best_log)
	if not untested(proposal_log):
		proposal_log = gap_proposal(speed_log(best_trial()))
	if not untested(proposal_log):
		return false
	current_log = proposal_log
	return true


func gap_proposal(best_log: float) -> float:
	var positions: Array[float] = [lower_log, upper_log]
	for trial in block_trials:
		positions.append(speed_log(trial))
	positions.sort()
	var best_gap_weight := -1.0
	var proposal_log := center_log
	for position_index in range(positions.size() - 1):
		var gap_width := positions[position_index + 1] - positions[position_index]
		var midpoint := (positions[position_index + 1] + positions[position_index]) * 0.5
		var gap_weight := gap_width / (1.0 + 4.0 * absf(midpoint - best_log))
		if untested(midpoint) and gap_weight > best_gap_weight + 0.000000000001:
			best_gap_weight = gap_weight
			proposal_log = midpoint
	return proposal_log


func close_block() -> void:
	var best := best_trial()
	var best_log := speed_log(best)
	var next_lower := lower_log
	var next_upper := upper_log
	for trial in block_trials:
		var tested_log := speed_log(trial)
		if tested_log < best_log - SPEED_EPSILON:
			next_lower = maxf(next_lower, tested_log)
		elif tested_log > best_log + SPEED_EPSILON:
			next_upper = minf(next_upper, tested_log)
	var maximum_width := (upper_log - lower_log) * 0.7
	next_lower = maxf(next_lower, best_log - maximum_width * 0.5)
	next_upper = minf(next_upper, best_log + maximum_width * 0.5)
	blocks.append({"scenario_id": SCENARIOS[blocks.size()], "title": ScenarioCopy.title(ScenarioCatalog.find(SCENARIOS[blocks.size()])),
		"trials": block_trials.duplicate(true), "best_cm_per_360": best.profile.cm_per_360,
		"moving_range_cm": [float(baseline.cm_per_360) / exp(next_upper), float(baseline.cm_per_360) / exp(next_lower)]})
	lower_log = next_lower
	upper_log = next_upper
	center_log = best_log
	current_log = best_log
	block_trials.clear()


func checkpoint() -> Dictionary:
	var fingerprints: Dictionary = {}
	for scenario_id in SCENARIOS:
		fingerprints[scenario_id] = ScenarioCatalog.find(scenario_id).fingerprint()
	return {"schema_version": 1, "protocol_version": PROTOCOL_VERSION, "baseline": baseline.duplicate(true), "aspect": aspect,
		"calibration_seed": calibration_seed, "calibration_id": calibration_id, "duration_s": duration_s,
		"exploration": exploration, "scenario_fingerprints": fingerprints, "trials": trials.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if data.get("schema_version", null) != 1 or data.get("protocol_version", null) != PROTOCOL_VERSION or not data.get("baseline", null) is Dictionary or not data.get("trials", null) is Array or data.trials.size() > TOTAL_TRIALS:
		error = "Version ou forme du parcours progressif invalide."
		return false
	if not ScoringService.number(data.get("aspect", null)) or not ScoringService.number(data.get("duration_s", null)) or not data.get("exploration", null) is bool or not CalibrationService.integer(data.get("calibration_seed", null)) or not data.get("calibration_id", null) is String:
		error = "Conditions de reprise invalides."
		return false
	if not data.get("scenario_fingerprints", null) is Dictionary:
		error = "Empreintes de reprise absentes."
		return false
	for scenario_id in SCENARIOS:
		if data.scenario_fingerprints.get(scenario_id, "") != ScenarioCatalog.find(scenario_id).fingerprint():
			error = "La difficulté a changé : le parcours existant est conservé, pas réinterprété."
			return false
	var verifier := ProgressiveCalibrationService.new()
	if not verifier.begin(data.baseline, float(data.aspect), int(data.calibration_seed), data.calibration_id, float(data.duration_s), data.exploration):
		error = verifier.error
		return false
	for trial in data.trials:
		if not trial is Dictionary or not verifier.accept(trial):
			error = "Historique de reprise incohérent : " + verifier.error
			return false
	if not same_value(data, verifier.checkpoint()):
		error = "Historique de reprise incomplet ou modifié."
		return false
	baseline = verifier.baseline
	aspect = verifier.aspect
	calibration_seed = verifier.calibration_seed
	calibration_id = verifier.calibration_id
	duration_s = verifier.duration_s
	exploration = verifier.exploration
	trials = verifier.trials
	blocks = verifier.blocks
	block_trials = verifier.block_trials
	lower_log = verifier.lower_log
	upper_log = verifier.upper_log
	center_log = verifier.center_log
	current_log = verifier.current_log
	initial_span_log = verifier.initial_span_log
	error = ""
	return true


func recommendation() -> Dictionary:
	if not completed():
		return {}
	var selected_cm := float(blocks.back().best_cm_per_360)
	return {"schema_version": 1, "protocol_version": PROTOCOL_VERSION, "calibration_id": calibration_id, "baseline": baseline.duplicate(true),
		"recommended_cm_per_360": selected_cm, "recommended_sensitivity": SensitivityService.game_sensitivity(baseline.dpi, selected_cm, SensitivityService.APP_YAW_DEG),
		"tested_trials": TOTAL_TRIALS, "duration_s": duration_s, "blocks": blocks.duplicate(true), "status": "complete", "apply_allowed": true,
		"checkpoint": checkpoint()}
