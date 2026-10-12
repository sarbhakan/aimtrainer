class_name CalibrationRevisionArchive
extends RefCounted

const REVISION_TWO_PARAMETERS: Array[Array] = [
	["C02", "click", "static", 1.2, 4.0, 3.0, 1.4, 12.0, 1, 1.6],
	["C04", "click", "static", 1.4, 24.0, 10.0, 14.0, 12.0, 1, 1.8],
	["S01", "switching", "static", 1.3, 22.0, 10.0, 4.0, 12.0, 4, 2.8],
	["T01", "tracking", "horizontal", 2.0, 12.0, 3.0, 2.5, 12.0, 1, 2.0],
	["T05", "tracking", "strafe", 1.8, 12.0, 3.0, 2.5, 26.0, 1, 2.0]
]


static func definitions() -> Dictionary:
	var result: Dictionary = {}
	for parameters in REVISION_TWO_PARAMETERS:
		var definition := ScenarioDefinition.new()
		definition.scenario_id = parameters[0]
		definition.title = str(parameters[0])
		definition.revision = 2
		definition.family = parameters[1]
		definition.motion = parameters[2]
		definition.layout = "scatter"
		definition.angular_diameter_deg = float(parameters[3])
		definition.yaw_extent_deg = float(parameters[4])
		definition.pitch_extent_deg = float(parameters[5])
		definition.min_transition_deg = float(parameters[6])
		definition.speed_deg_s = float(parameters[7])
		definition.active_targets = int(parameters[8])
		definition.reference_hits_s = float(parameters[9])
		definition.lifetime_s = 0.0
		definition.distance_m = 4.0
		definition.turn_duration_s = 0.12
		result[definition.scenario_id] = definition
	return result


static func recognized_checkpoint(data: Dictionary) -> bool:
	var verifier := CalibrationService.new()
	verifier.scenario_overrides = definitions()
	return verifier.restore(data)
