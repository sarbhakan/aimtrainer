class_name ProgressService
extends RefCounted


static func summarize(results: Array[Dictionary], comparison_key: String) -> Dictionary:
	var comparable: Array[Dictionary] = []
	for result in results:
		if result.get("completed", false) and result.get("valid", false) and not result.get("warmup", false) and ScoringService.has_activity(result) and result.get("comparison_key", "") == comparison_key:
			comparable.append(result)
	comparable.sort_custom(func(result_left: Dictionary, result_right: Dictionary) -> bool: return str(result_left.get("created_at_utc", "")) < str(result_right.get("created_at_utc", "")))
	var values: Array[float] = []
	for result in comparable:
		values.append(float(result.get("score", 0.0)))
	var latest: Array[float] = []
	for value_index in range(maxi(0, values.size() - 5), values.size()):
		latest.append(values[value_index])
	var summary := {"count": values.size(), "latest_median": ScoringService.median(latest),
		"best": values.max() if not values.is_empty() else 0.0, "trend_available": values.size() >= 10,
		"change_pct": null}
	if values.size() >= 10:
		var first: Array[float] = []
		for value_index in 5:
			first.append(values[value_index])
		var initial := ScoringService.median(first)
		if initial > 0.0:
			summary.change_pct = (float(summary.latest_median) / initial - 1.0) * 100.0
	return summary
