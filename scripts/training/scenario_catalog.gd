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


static func find(scenario_id: String) -> ScenarioDefinition:
	for definition in DEFINITIONS:
		if definition.scenario_id == scenario_id:
			return definition
	return null
