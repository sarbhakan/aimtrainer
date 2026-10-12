extends SceneTree

var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("La validation des scores sérialisés n’a pas terminé.")
		quit(1))
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	var profile := SensitivityService.default_profile()
	profile.dpi = 1600.0
	profile.cm_per_360 = 34.123456
	var observed_boundary := false
	for definition in ScenarioCatalog.DEFINITIONS:
		for seed_value in range(1, 513):
			var engine := ScenarioEngine.new()
			engine.start(definition, seed_value, 1.0)
			engine.record_aim(0.01, 1.0, 0.0)
			engine.record_frame(0.01)
			if definition.family != "tracking":
				engine.shoot(0.1, engine.target_direction(0, 0.1))
			engine.advance_to(1.0)
			var report := engine.result(profile, 16.0 / 9.0, true)
			var restored: Dictionary = JSON.parse_string(JSON.stringify(report, "", true, true))
			check(ScoringService.validate_result(restored).is_empty(), "%s seed%d : un rapport valide reste lisible après un aller-retour JSON." % [definition.scenario_id, seed_value])
			check(restored.score == report.score and restored.comparison_key == report.comparison_key, "Relire ne réécrit ni le score ni les conditions de comparaison.")
			var forged: Dictionary = restored.duplicate(true)
			forged.score += 2.0
			check(not ScoringService.validate_result(forged).is_empty(), "La tolérance numérique n’accepte pas un score arbitrairement augmenté.")
			var explanation := ScoringService.explain(restored)
			observed_boundary = observed_boundary or explanation.score_rounding_range.size() == 2
			if explanation.score_rounding_range.size() == 1:
				forged.score = restored.score + 1.0
				check(not ScoringService.validate_result(forged).is_empty(), "Même un seul point falsifié est rejeté hors d’une frontière d’arrondi numérique.")
			else:
				forged.score = restored.score + 0.25
				check(not ScoringService.validate_result(forged).is_empty(), "La frontière n’accepte que les deux entiers voisins, pas une valeur fractionnaire.")
	check(observed_boundary, "Les graines couvrent réellement le cas de demi-point qui change au dernier bit JSON.")
	check(ScoringService.rounding_range(112.5 - 0.00001) == [112.0] and ScoringService.rounding_range(112.5 + 0.00001) == [113.0], "Un avantage réel de 0,00001 point n’est pas traité comme du bruit de sérialisation.")
	check(ScoringService.rounding_range(112.5).size() == 2, "Le demi-point exact est explicitement qualifié comme frontière numérique.")
	print("STORAGE ROUNDTRIP : %d assertions, %d échecs." % [assertions, failures])
	quit(1 if failures else 0)
