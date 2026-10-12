class_name ProgressService
extends RefCounted


static func summarize(results: Array[Dictionary], comparison_key: String) -> Dictionary:
	var comparable: Array[Dictionary] = []
	var excluded_reasons: Dictionary = {}
	for result in results:
		var reason: String = "Clé de comparaison absente : aucune séance ne peut être regroupée." if comparison_key.is_empty() else ScoringService.comparison_error(result, comparison_key)
		if reason.is_empty():
			comparable.append(result)
		else:
			excluded_reasons[reason] = int(excluded_reasons.get(reason, 0)) + 1
	comparable.sort_custom(func(result_left: Dictionary, result_right: Dictionary) -> bool:
		var left_date: String = str(result_left.get("created_at_utc", ""))
		var right_date: String = str(result_right.get("created_at_utc", ""))
		return str(result_left.get("session_id", "")) < str(result_right.get("session_id", "")) if left_date == right_date else left_date < right_date)
	var values: Array[float] = []
	for result in comparable:
		values.append(float(result.get("score", 0.0)))
	var latest: Array[float] = []
	for value_index in range(maxi(0, values.size() - 5), values.size()):
		latest.append(values[value_index])
	var recent_sessions: Array[Dictionary] = []
	var summary := {"count": values.size(), "latest_median": ScoringService.median(latest),
		"best": values.max() if not values.is_empty() else 0.0, "trend_available": values.size() >= 10,
		"change_pct": null, "recent_scores": values.slice(maxi(0, values.size() - 20)),
		"latest_score": values.back() if not values.is_empty() else null,
		"latest_session_id": str(comparable.back().get("session_id", "")) if not comparable.is_empty() else "",
		"previous_best": null, "new_record": false, "recent_sessions": recent_sessions,
		"excluded_count": results.size() - comparable.size(), "excluded_reasons": excluded_reasons,
		"filter": {"comparison_key": comparison_key, "score_version": comparable[0].get("score_version", ScoringService.VERSION) if not comparable.is_empty() else ScoringService.VERSION,
			"completed": true, "valid": true, "warmup": false, "active": true,
			"recent_sessions_order": "created_at_utc descending, session_id descending"},
		"conditions": "Même configuration et version de score ; séances complètes, valides, actives, hors échauffement. Un score élevé cohérent reste admissible."}
	if values.size() > 1:
		summary.previous_best = values.slice(0, values.size() - 1).max()
	if not values.is_empty():
		summary.new_record = summary.previous_best == null or float(summary.latest_score) > float(summary.previous_best)
	for result_index in range(comparable.size() - 1, maxi(-1, comparable.size() - 21), -1):
		summary.recent_sessions.append(session_row(comparable[result_index]))
	if values.size() >= 10:
		var first: Array[float] = []
		for value_index in 5:
			first.append(values[value_index])
		var initial := ScoringService.median(first)
		if initial > 0.0:
			summary.change_pct = (float(summary.latest_median) / initial - 1.0) * 100.0
	return summary


static func session_row(result: Dictionary) -> Dictionary:
	var metrics: Dictionary = result.metrics
	var tracking: bool = result.family == "tracking"
	var accuracy_pct: Variant = null
	if not tracking and ScoringService.number(metrics.get("hits", null)) and ScoringService.number(metrics.get("shots", null)) and float(metrics.shots) > 0.0:
		accuracy_pct = 100.0 * float(metrics.hits) / float(metrics.shots)
	return {"session_id": str(result.get("session_id", "")), "created_at_utc": str(result.get("created_at_utc", "")),
		"scenario_id": str(result.get("scenario_id", "")), "family": result.family,
		"scenario_revision": result.get("scenario_revision", null), "score_version": result.get("score_version", ScoringService.VERSION),
		"comparison_key": result.comparison_key, "score": float(result.score),
		"shots": metrics.get("shots", null) if not tracking else null, "hits": metrics.get("hits", null) if not tracking else null,
		"accuracy_pct": accuracy_pct, "hits_per_s": metrics.get("hits_per_s", null) if not tracking else null,
		"on_target_ratio": metrics.get("on_target_ratio", null) if tracking else null,
		"on_target_time_s": metrics.get("on_target_time_s", null) if tracking else null,
		"angular_error_mean_deg": metrics.get("angular_error_mean_deg", null) if tracking else null,
		"active_duration_s": result.get("active_duration_s", null)}
