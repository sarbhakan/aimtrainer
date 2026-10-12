class_name ScenarioCatalog
extends RefCounted

const DEFINITIONS: Array[ScenarioDefinition] = [
	preload("res://content/scenarios/C01.tres"), preload("res://content/scenarios/C02.tres"),
	preload("res://content/scenarios/C03.tres"), preload("res://content/scenarios/C04.tres"),
	preload("res://content/scenarios/C05.tres"), preload("res://content/scenarios/C07.tres"),
	preload("res://content/scenarios/D01.tres"), preload("res://content/scenarios/D02.tres"),
	preload("res://content/scenarios/T01.tres"), preload("res://content/scenarios/T02.tres"),
	preload("res://content/scenarios/T03.tres"), preload("res://content/scenarios/T04.tres"),
	preload("res://content/scenarios/T05.tres"), preload("res://content/scenarios/T09.tres"),
	preload("res://content/scenarios/S01.tres"), preload("res://content/scenarios/S02.tres"),
	preload("res://content/scenarios/M01.tres"), preload("res://content/scenarios/T10.tres")
]

static var temporal_definitions: Array[ScenarioDefinition] = []


static func find(scenario_id: String) -> ScenarioDefinition:
	for definition in DEFINITIONS:
		if definition.scenario_id == scenario_id:
			return definition
	return null


static func practice_definitions() -> Array[ScenarioDefinition]:
	if temporal_definitions.is_empty():
		for source in DEFINITIONS:
			var definition := source.duplicate() as ScenarioDefinition
			definition.revision = 6
			var minimum_diameter_deg := definition.angular_diameter_min_deg if definition.has_diameter_variation() else definition.angular_diameter_deg
			definition.lifecycle_shrink_ratio = clampf(0.55 / minimum_diameter_deg, 0.65, 0.85) if definition.family == "tracking" else clampf(1.5 / minimum_diameter_deg, 0.35, 0.75)
			definition.diameter_motion = "fixed" if definition.diameter_motion == "shrink" else definition.diameter_motion
			definition.lifetime_s = 10.0 if definition.family == "tracking" else 6.0 if definition.scenario_id == "C05" else 5.0 if definition.scenario_id == "S02" else 4.0 if definition.active_targets > 1 else 1.0 if definition.scenario_id == "D01" else 3.0
			definition.lifetime_min_s = definition.lifetime_s * 0.85
			definition.lifetime_max_s = definition.lifetime_s * 1.15
			temporal_definitions.append(definition)
	return temporal_definitions


static func find_practice(scenario_id: String) -> ScenarioDefinition:
	for definition in practice_definitions():
		if definition.scenario_id == scenario_id:
			return definition
	return null


static func resolve(scenario_id: String, fingerprint: String) -> ScenarioDefinition:
	for definition in [find(scenario_id), find_practice(scenario_id)]:
		if definition != null and definition.fingerprint() == fingerprint:
			return definition
	return null
