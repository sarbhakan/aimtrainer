class_name V2Scores
extends RefCounted

const CLICK_ID: String = "click_v3"
const OPPORTUNITY_ID: String = "opportunities_v2"
const CONTACT_ID: String = "contact_v2"
const SWITCH_ID: String = "switch_work_v3"


static func phase_score(definition: Dictionary, metrics: Dictionary, complete: bool = true, valid: bool = true) -> Variant:
	if not complete or not valid:
		return null
	var duration_s: float = float(definition.duration_s)
	var hits: float = float(metrics.get("hits", 0))
	var shots: float = float(metrics.get("shots", 0))
	match String(definition.scoring.id):
		CLICK_ID:
			return 1000.0 * hits / duration_s * hits / maxf(shots, 1.0)
		OPPORTUNITY_ID:
			var opportunities: float = float(definition.spawn.schedule.slots)
			return 1000.0 * hits / opportunities * hits / maxf(shots, 1.0)
		CONTACT_ID:
			return 1000.0 * float(metrics.get("contact_s", 0.0)) / duration_s
		SWITCH_ID:
			return 1000.0 * float(metrics.get("credited_work", 0.0)) / duration_s
	return null


static func program_score(definition: Dictionary, phases: Array, complete: bool, valid: bool) -> Variant:
	if not complete or not valid or not bool(definition.aggregate.ranked_program_score) or phases.size() != definition.phases.size():
		return null
	var numerator: float = 0.0
	for phase: Dictionary in phases:
		if phase.get("score") == null or not bool(phase.get("complete", false)):
			return null
		if String(definition.aggregate.kind) == "time_weighted_contact":
			numerator += float(phase.metrics.contact_s)
		elif String(definition.aggregate.kind) == "sum_credited_switch_work_per_program_time":
			numerator += float(phase.metrics.credited_work)
	return 1000.0 * numerator / float(definition.duration_s)


static func displayed_score(score: Variant) -> Variant:
	return int(floor(float(score) + 0.5)) if score != null else null


static func accuracy(metrics: Dictionary) -> Variant:
	return float(metrics.get("hits", 0)) / float(metrics.shots) if int(metrics.get("shots", 0)) > 0 else null


static func percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty():
		return null
	var ordered: Array = values.duplicate()
	ordered.sort()
	var position: float = clampf(fraction, 0.0, 1.0) * float(ordered.size() - 1)
	var lower: int = int(floor(position))
	var upper: int = mini(lower + 1, ordered.size() - 1)
	return lerpf(float(ordered[lower]), float(ordered[upper]), position - lower)


static func context_key(context: Dictionary, definition: Dictionary, phase_id: String = "") -> String:
	return V2Canonical.semantic_sha256({"runtime": "aimlocal.runtime.v2.0", "definition_hash": V2Canonical.semantic_sha256(definition), "program_id": definition.program_id, "difficulty": definition.difficulty, "phase_id": phase_id, "conditions": context})
