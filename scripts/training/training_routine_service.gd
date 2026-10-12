class_name TrainingRoutineService
extends RefCounted

const SCENARIO_IDS: Array[String] = ["M01", "T10", "S02"]

var plan: Array[Dictionary] = []


func begin(duration_s: float = 45.0) -> bool:
	plan.clear()
	if not is_finite(duration_s) or not duration_s in [45.0, 60.0]:
		return false
	for stage_index in SCENARIO_IDS.size():
		var definition: ScenarioDefinition = ScenarioCatalog.find_practice(SCENARIO_IDS[stage_index])
		if definition == null or not definition.validate().is_empty():
			plan.clear()
			return false
		plan.append({"scenario_id": definition.scenario_id, "duration_s": duration_s,
			"index": stage_index, "total": SCENARIO_IDS.size(), "title": definition.title})
	return true


func current_stage(index: int) -> Dictionary:
	return plan[index].duplicate(true) if index >= 0 and index < plan.size() else {}
