extends RefCounted

const NOTICE: String = "Illustration · données synthétiques de test, pas les performances d’un joueur."
const BLOCK_VALUES: Array = [
	[36.0, 68.0, 82.0, 56.0, 74.0],
	[72.0, 38.0, 84.0, 54.0, 66.0],
	[54.0, 78.0, 90.0, 66.0, 82.0],
	[82.0, 54.0, 70.0, 88.0, 76.0],
	[62.0, 84.0, 74.0, 92.0, 88.0]
]


static func session_report(scenario_id: String, profile: Dictionary, duration_s: float, aspect: float, seed_value: int, value: float, identifier: String, explicit_definition: ScenarioDefinition = null, expired_targets: int = 0) -> Dictionary:
	var definition := explicit_definition if explicit_definition != null else ScenarioCatalog.find_practice(scenario_id)
	var tracking: bool = definition.family == "tracking"
	var hits: int = 0 if tracking else roundi(value)
	var shots: int = 0 if tracking else hits + 12
	var accuracy: float = float(hits) / maxf(float(shots), 1.0)
	var ratio: float = value / 100.0 if tracking else 0.0
	var report: Dictionary = {
		"schema_version": 1, "score_version": ScoringService.version_for(definition),
		"engine_version": "4.7.2", "renderer": "compatibility",
		"app_version": ProjectSettings.get_setting("application/config/version"),
		"session_id": identifier, "created_at_utc": "2026-10-12T00:00:00Z",
		"synthetic": true, "synthetic_label": NOTICE,
		"scenario_id": scenario_id, "scenario_revision": definition.revision,
		"scenario_fingerprint": definition.fingerprint(), "family": definition.family,
		"seed": seed_value, "duration_s": duration_s, "active_duration_s": duration_s,
		"completed": true, "valid": true, "warmup": false,
		"profile": profile.duplicate(true), "aspect": aspect,
		"reference_hits_s": definition.reference_hits_s,
		"metrics": {
			"shots": shots, "hits": hits, "misses": shots - hits, "targets_expired": expired_targets,
			"accuracy_fraction": accuracy, "accuracy_pct": accuracy * 100.0 if shots > 0 else null,
			"hits_per_s": float(hits) / duration_s, "input_events": 100,
			"input_buffer_overflows": 0, "angular_path_deg": 20.0,
			"on_target_ratio": ratio, "on_target_time_s": duration_s * ratio,
			"target_exposed_time_s": duration_s,
			"angular_error_mean_deg": 1.0, "angular_error_p95_deg": 2.0
		},
		"performance": {"frame_samples": 1000, "frametime_p99_ms": 8.0, "max_frametime_ms": 12.0},
		"comparison_key": ScoringService.comparison_key(definition, duration_s, profile, aspect)
	}
	if report.score_version == ScoringService.EXPIRY_VERSION:
		report.score_policy = "expiry_accuracy_v2"
		report.metrics.effective_accuracy_fraction = ScoringService.effective_accuracy(report.metrics)
		report.metrics.effective_accuracy_pct = report.metrics.effective_accuracy_fraction * 100.0 if shots + expired_targets > 0 else null
		report.metrics.failed_actions = shots - hits + expired_targets
	report.score = ScoringService.score(report, definition.reference_hits_s)
	return report


static func progressive_report(service: ProgressiveCalibrationService) -> Dictionary:
	var stage := service.current_stage()
	var value: float = BLOCK_VALUES[int(stage.block_index)][int(stage.trial_index)]
	var report := session_report(stage.scenario_id, stage.profile, stage.duration_s, service.aspect,
		stage.seed, value, "visual-progressive-%02d" % service.trials.size(), service.definition_for(stage.scenario_id))
	report.calibration_id = service.calibration_id
	report.progressive_block_index = stage.block_index
	report.progressive_trial_index = stage.trial_index
	return report


static func trial_context(service: ProgressiveCalibrationService, report: Dictionary) -> Dictionary:
	var context := service.current_stage().duplicate(true)
	context.completed_trials += 1
	context.block_history.append({
		"family": report.family, "score_version": report.score_version, "targets_expired": report.metrics.targets_expired,
		"sensitivity": context.active_sensitivity, "score": report.score,
		"hits": report.metrics.hits, "misses": report.metrics.misses,
		"accuracy_pct": report.metrics.accuracy_pct,
		"effective_accuracy_pct": report.metrics.get("effective_accuracy_pct", report.metrics.accuracy_pct), "on_target_ratio": report.metrics.on_target_ratio,
		"utility": ScoringService.utility(report)
	})
	return context


static func routine_report(stage: Dictionary, profile: Dictionary, aspect: float, seed_value: int) -> Dictionary:
	var report := session_report(stage.scenario_id, profile, stage.duration_s, aspect, seed_value,
		64.0 + float(stage.index) * 8.0, "visual-routine-%d-%d" % [int(stage.duration_s), int(stage.index)])
	report.routine_stage_index = stage.index
	return report
