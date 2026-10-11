class_name AdaptiveSensitivityService
extends RefCounted

const SEARCH_VERSION: int = 1
const MAX_COMPARISONS: int = 4
const MAX_EXPANSIONS: int = 2
const SEED_STRIDE: int = 104729
const EXPLORE_FACTORS: Array[float] = [0.5, 1.0, 2.0]
const REFINE_FACTORS: Array[float] = [0.75, 1.0, 1.25]

var finished: bool:
	get:
		return _finished
var history: Array[Dictionary]:
	get:
		return _history.duplicate(true)
var error: String = ""
var initial_profile: Dictionary = {}
var aspect: float = 16.0 / 9.0
var search_seed: int = 1
var search_id: String = ""
var _history: Array[Dictionary] = []
var _finished: bool = false
var _spec: Dictionary = {}
var _current_report: Dictionary = {}
var _search_status: String = "idle"
var _expansion_count: int = 0
var _advice: String = ""


func begin(profile: Dictionary, viewport_aspect: float = 16.0 / 9.0, seed_value: int = 1, identifier: String = "") -> bool:
	error = SensitivityService.validate_profile(profile)
	if not error.is_empty():
		return false
	if absf(float(seed_value)) >= 9007199253640992.0:
		error = "Graine de recherche hors limites."
		return false
	var resolved_id: String = identifier if not identifier.is_empty() else "guided-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	if not resolved_id.is_valid_filename() or resolved_id in [".", ".."] or resolved_id.length() > 80:
		error = "Identifiant de recherche invalide."
		return false
	var spec := make_spec(profile, viewport_aspect, seed_value, resolved_id, float(profile.cm_per_360), "explore", 0)
	var verifier := CalibrationService.new()
	if not verifier.begin(spec.profile, viewport_aspect, int(spec.seed), str(spec.calibration_id), spec.speed_factors):
		error = verifier.error
		return false
	initial_profile = profile.duplicate(true)
	aspect = viewport_aspect
	search_seed = seed_value
	search_id = resolved_id
	_history.clear()
	_spec = spec
	_current_report = {}
	_search_status = "exploring"
	_expansion_count = 0
	_advice = "Explorer trois vitesses avec cinq exercices fixes ; faire une pause avant chaque nouvelle comparaison."
	_finished = false
	error = ""
	return true


static func make_spec(profile: Dictionary, viewport_aspect: float, seed_value: int, identifier: String, requested_center_cm: float, phase: String, round_index: int) -> Dictionary:
	var factors: Array[float] = EXPLORE_FACTORS.duplicate()
	var label: String = "Exploration large"
	if phase == "refine":
		factors = REFINE_FACTORS.duplicate()
		label = "Affinage à 25 %"
	elif phase == "validate":
		factors = CalibrationService.FACTORS.duplicate()
		label = "Validation à 10 %"
	var center_cm: float = clampf(requested_center_cm, 5.0 * factors[2], 150.0 * factors[0])
	var comparison_profile: Dictionary = profile.duplicate(true)
	comparison_profile.cm_per_360 = center_cm
	label += " · comparaison %d/%d" % [round_index + 1, MAX_COMPARISONS]
	if center_cm != requested_center_cm:
		label += " · centre borné à %.3f cm/360° (repère demandé %.3f)" % [center_cm, requested_center_cm]
	if round_index == 0 and center_cm != float(profile.cm_per_360):
		label += " · départ hors du centre, profil initial conservé"
	return {"profile": comparison_profile, "speed_factors": factors, "round_index": round_index,
		"label": label, "phase": phase, "seed": seed_value + round_index * SEED_STRIDE,
		"calibration_id": "%s-r%d" % [identifier, round_index], "aspect": viewport_aspect,
		"requested_center_cm_per_360": requested_center_cm, "center_adjusted": center_cm != requested_center_cm}


func current_spec() -> Dictionary:
	return {} if finished else _spec.duplicate(true)


func accept_comparison(recommendation: Dictionary) -> bool:
	if finished or _spec.is_empty():
		error = "Aucune comparaison en attente ; ce bilan a déjà été traité ou la recherche est terminée."
		return false
	var report := verified_report(recommendation)
	if report.is_empty():
		return false
	var best: Dictionary = report.candidates[0]
	var winner_index: int = int(best.index)
	var winner_cm: float = float(best.cm_per_360)
	var decision: String = "retest"
	var reason: String = ""
	var next_spec: Dictionary = {}
	var next_status: String = str(report.status)
	var next_expansion_count: int = _expansion_count
	if report.status == "insufficient":
		reason = "Un exercice ne fournit pas de signal utile. Conserver le départ et refaire après repos."
	elif report.status == "uncertain":
		reason = "L’écart ne dépasse pas le seuil heuristique de dispersion. Conserver le départ et refaire un autre jour."
	elif report.status == "uncomfortable" or not comfortable_winner(report, winner_index):
		next_status = "uncomfortable"
		reason = "Le confort du meilleur testé est insuffisant sur au moins un exercice. Arrêter, conserver le départ et réévaluer après repos."
	elif _spec.phase == "validate" and winner_index == 1:
		decision = "confirm"
		next_status = "stable"
		reason = "Le centre reste stable après exploration et affinage. Confirmer dans 2 à 7 jours ; aucune application automatique."
	elif _history.size() + 1 >= MAX_COMPARISONS:
		decision = "budget"
		next_status = "limit_reached"
		reason = "Quatre comparaisons atteintes sans validation stable à 10 %. Conserver le départ et retester un autre jour."
	elif winner_index == 1:
		var next_phase: String = "refine" if _spec.phase == "explore" else "validate"
		next_spec = make_spec(initial_profile, aspect, search_seed, search_id, winner_cm, next_phase, _history.size() + 1)
		decision = next_phase
		next_status = "refining" if next_phase == "refine" else "validating"
		reason = "Le centre confortable dépasse le seuil heuristique ; resserrer la plage pour vérifier sa stabilité."
	elif _spec.phase == "refine":
		next_spec = make_spec(initial_profile, aspect, search_seed, search_id, winner_cm, "validate", _history.size() + 1)
		if float(next_spec.profile.cm_per_360) != winner_cm:
			next_spec = {}
			decision = "boundary"
			next_status = "boundary_limited"
			reason = "La validation autour du meilleur essai dépasserait les bornes physiques. Conserver le départ et retester après repos."
		else:
			decision = "validate"
			next_status = "validating"
			reason = "Un bord de l’affinage est nettement meilleur et confortable ; recentrer la validation étroite sur ce réglage réellement testé."
	elif _spec.phase == "explore" and _expansion_count < MAX_EXPANSIONS:
		next_spec = make_spec(initial_profile, aspect, search_seed, search_id, winner_cm, "explore", _history.size() + 1)
		if float(next_spec.profile.cm_per_360) == float(_spec.profile.cm_per_360):
			next_spec = {}
			decision = "boundary"
			next_status = "boundary_limited"
			reason = "Le meilleur testé est au bord de la plage physique 5–150 cm/360°. Aucun déplacement distinct du centre n’est possible ; conserver le départ."
		else:
			next_expansion_count += 1
			decision = "recenter"
			next_status = "exploring"
			reason = "Un bord confortable dépasse le seuil heuristique ; déplacer le centre sur ce réglage testé et garder une exploration large."
	else:
		decision = "boundary"
		next_status = "boundary_limited"
		reason = "Le meilleur testé reste au bord après les déplacements autorisés ou pendant l’affinage. La recherche ne démontre pas un centre stable ; conserver le départ."
	var entry := report.duplicate(true)
	entry.search_step = {"spec": _spec.duplicate(true),
		"winner_index": winner_index, "best_tested_cm_per_360": winner_cm,
		"score_gap": report.score_gap, "dispersion_threshold": report.dispersion_threshold,
		"comfort_median": best.comfort_median, "decision": decision, "reason": reason,
		"search_status": next_status}
	_history.append(entry)
	_current_report = report
	_spec = next_spec
	_search_status = next_status
	_expansion_count = next_expansion_count
	_advice = reason
	_finished = next_spec.is_empty()
	error = ""
	return true


func verified_report(recommendation: Dictionary) -> Dictionary:
	if not recommendation.get("baseline", null) is Dictionary or not recommendation.get("trials", null) is Array or recommendation.trials.size() != 60:
		error = "La recherche exige une comparaison complète : 15 familiarisations et 45 mesures validées."
		return {}
	if not same_value(recommendation.baseline, _spec.profile):
		error = "Le bilan ne correspond pas au centre et au profil attendus."
		return {}
	var verifier := CalibrationService.new()
	if not verifier.begin(_spec.profile, aspect, int(_spec.seed), str(_spec.calibration_id), _spec.speed_factors):
		error = verifier.error
		return {}
	var data := verifier.checkpoint()
	data.trials = recommendation.trials.duplicate(true)
	data.current_index = 60
	data.status = "complete"
	if not verifier.restore(data):
		error = verifier.error
		return {}
	var derived := verifier.recommendation()
	for field in derived:
		if not recommendation.has(field) or not same_value(recommendation[field], derived[field]):
			error = "Bilan incohérent avec ses passages ou le contexte attendu : " + str(field)
			return {}
	var scored_count: int = 0
	for trial in verifier.trials:
		if trial.scored:
			scored_count += 1
	if scored_count != 45 or not safe_medians(derived):
		error = "Les 45 mesures et leurs médianes doivent être complètes, finies et sûres."
		return {}
	return derived


static func safe_medians(report: Dictionary) -> bool:
	for field in ["score_gap", "dispersion_threshold"]:
		if not ScoringService.number(report.get(field, null)) or float(report[field]) < 0.0:
			return false
	if report.candidates.size() != 3:
		return false
	for candidate in report.candidates:
		for field in ["value", "spread", "comfort_median"]:
			if not ScoringService.number(candidate.get(field, null)) or float(candidate[field]) < 0.0:
				return false
		for scenario_id in CalibrationService.SCENARIOS:
			var cell: Dictionary = candidate.per_scenario.get(scenario_id, {})
			if cell.get("samples", 0) != 3:
				return false
			for field in ["median_utility", "dispersion"]:
				if not ScoringService.number(cell.get(field, null)) or float(cell[field]) < 0.0:
					return false
	return true


static func comfortable_winner(report: Dictionary, winner_index: int) -> bool:
	for scenario_id in CalibrationService.SCENARIOS:
		var comfort_values: Array[int] = []
		for trial in report.trials:
			if trial.scored and int(trial.candidate_index) == winner_index and trial.scenario_id == scenario_id:
				comfort_values.append(int(trial.comfort))
		if comfort_values.size() != 3 or ScoringService.median(comfort_values) <= 2.0:
			return false
	return true


func final_result() -> Dictionary:
	var result := _current_report.duplicate(true)
	var stable: bool = finished and _search_status == "stable"
	result.status = "indicative" if stable else (str(_search_status) if _search_status in ["uncertain", "uncomfortable", "insufficient"] else "insufficient")
	result.current_report = _current_report.duplicate(true)
	result.initial_profile = initial_profile.duplicate(true)
	result.search_id = search_id
	result.search_history = _history.duplicate(true)
	result.search_status = _search_status
	result.search_version = SEARCH_VERSION
	result.finished = finished
	result.rounds_completed = _history.size()
	result.comparisons_limit = MAX_COMPARISONS
	result.confirmation_required = stable
	result.confirmation_after_days = [2, 7] if stable else []
	result.trial_allowed = stable
	result.apply_allowed = false
	result.advice = _advice
	if not initial_profile.is_empty():
		result.recommended_cm_per_360 = _current_report.best_tested_cm_per_360 if stable else initial_profile.cm_per_360
	return result


func checkpoint() -> Dictionary:
	return {"schema_version": 1, "search_version": SEARCH_VERSION,
		"state": {"initial_profile": initial_profile.duplicate(true), "aspect": aspect,
			"seed": search_seed, "search_id": search_id, "current_spec": current_spec(),
			"finished": finished, "search_status": _search_status, "expansion_count": _expansion_count, "advice": _advice},
		"history": _history.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if not CalibrationService.integer(data.get("schema_version", null)) or data.schema_version != 1 or not CalibrationService.integer(data.get("search_version", null)) or data.search_version != SEARCH_VERSION or not data.get("state", null) is Dictionary or not data.get("history", null) is Array:
		error = "Checkpoint de recherche inconnu ou invalide ; données conservées."
		return false
	var state: Dictionary = data.state
	if data.history.size() > MAX_COMPARISONS or not state.get("initial_profile", null) is Dictionary or not ScoringService.number(state.get("aspect", null)) or not CalibrationService.integer(state.get("seed", null)) or not state.get("search_id", null) is String or str(state.search_id).is_empty():
		error = "Contexte ou longueur de recherche invalide."
		return false
	var replay := AdaptiveSensitivityService.new()
	if not replay.begin(state.initial_profile, float(state.aspect), int(state.seed), str(state.search_id)):
		error = replay.error
		return false
	for entry in data.history:
		if not entry is Dictionary or not entry.get("search_step", null) is Dictionary or not entry.search_step.get("spec", null) is Dictionary or not same_value(entry.search_step.spec, replay.current_spec()):
			error = "Ordre ou contexte de l’historique de recherche incohérent."
			return false
		if not replay.accept_comparison(entry):
			error = replay.error
			return false
		if not same_value(entry, replay._history.back()):
			error = "Décision historique incompatible avec les passages vérifiés."
			return false
	if not same_value(state, replay.checkpoint().state) or data.size() != 4:
		error = "État de recherche incompatible avec l’historique recalculé."
		return false
	initial_profile = replay.initial_profile
	aspect = replay.aspect
	search_seed = replay.search_seed
	search_id = replay.search_id
	_history = replay._history
	_spec = replay._spec
	_current_report = replay._current_report
	_search_status = replay._search_status
	_expansion_count = replay._expansion_count
	_advice = replay._advice
	_finished = replay.finished
	error = ""
	return true


static func same_value(left: Variant, right: Variant) -> bool:
	if ScoringService.number(left) and ScoringService.number(right):
		if left is int or right is int:
			return float(left) == float(right)
		return absf(float(left) - float(right)) <= 8.0 * 2.220446049250313e-16 * maxf(1.0, maxf(absf(float(left)), absf(float(right))))
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for field in left:
			if not right.has(field) or not same_value(left[field], right[field]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for item_index in left.size():
			if not same_value(left[item_index], right[item_index]):
				return false
		return true
	return typeof(left) == typeof(right) and left == right
