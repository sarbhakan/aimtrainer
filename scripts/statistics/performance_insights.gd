class_name PerformanceInsights
extends RefCounted


static func measured(metrics: Dictionary, field: String) -> Variant:
	var value: Variant = metrics.get(field, null)
	return float(value) if ScoringService.number(value) and float(value) >= 0.0 else null


static func hits_per_minute(metrics: Dictionary) -> Variant:
	var hits_per_s: Variant = measured(metrics, "hits_per_s")
	if hits_per_s == null:
		return null
	var cadence_hits_min: float = float(hits_per_s) * 60.0
	return cadence_hits_min if is_finite(cadence_hits_min) else null


static func display(value: Variant, decimals: int, unit: String = "") -> String:
	if value == null:
		return "—"
	return (("%." + str(decimals) + "f") % float(value)).replace(".", ",") + (" " + unit if not unit.is_empty() else "")


static func measurement(value: Variant, unit: String, description: String) -> Dictionary:
	return {"value": value, "unit": unit, "available": value != null, "description": description}


static func analyze(report: Dictionary) -> Dictionary:
	var insights: Dictionary = analyze_v1(report)
	if int(report.get("score_version", 1)) != 2 or report.get("family", "") == "tracking":
		return insights
	var metrics: Dictionary = report.get("metrics", {}) if report.get("metrics", {}) is Dictionary else {}
	var hits: Variant = measured(metrics, "hits")
	var misses: Variant = shot_misses(metrics)
	var expired: Variant = measured(metrics, "targets_expired")
	var failures: Variant = failed_actions(metrics)
	var success_pct: Variant = effective_accuracy_pct(metrics)
	insights.primary_label = "Touches"
	insights.primary_value = display(hits, 0)
	insights.primary_unit = "touches"
	insights.secondary_label = "Ratées"
	insights.secondary_value = display(failures, 0)
	insights.secondary_unit = "tirs manqués + cibles expirées"
	insights.tempo_label = "Réussite"
	insights.tempo_value = display(success_pct, 1, "%")
	insights.tempo_unit = "%"
	insights.tip = "Ratées : %s tirs manqués + %s cibles expirées. Réussite : %s ; cadence : %s." % [display(misses, 0), display(expired, 0), display(success_pct, 1, "%"), display(hits_per_minute(metrics), 0, "cibles/min")]
	insights.short_tip = "Visez et cliquez avant l’échéance des cibles." if expired != null and float(expired) > 0.0 else "Prenez un instant pour centrer le viseur avant chaque clic." if misses != null and float(misses) > 0.0 else "Rejouez avec les mêmes échéances pour confirmer cette réussite."
	insights.advice = insights.short_tip
	insights.measurements.misses = measurement(misses, "tirs manqués", "Tirs qui ne touchent aucune cible ; les expirations restent séparées.")
	insights.measurements.targets_expired = measurement(expired, "cibles expirées", "Cibles non touchées avant leur échéance ; aucune expiration ne compte comme un tir.")
	insights.measurements.failed_actions = measurement(failures, "ratées", "Tirs manqués + cibles expirées.")
	insights.measurements.effective_accuracy_pct = measurement(success_pct, "%", "100 × touches / (tirs + cibles expirées) ; indisponible sans tir ni expiration.")
	return insights


static func shot_misses(metrics: Dictionary) -> Variant:
	var misses: Variant = measured(metrics, "misses")
	if misses != null:
		return misses
	var hits: Variant = measured(metrics, "hits")
	var shots: Variant = measured(metrics, "shots")
	return float(shots) - float(hits) if shots != null and hits != null and float(hits) <= float(shots) else null


static func failed_actions(metrics: Dictionary) -> Variant:
	var misses: Variant = shot_misses(metrics)
	var expired: Variant = measured(metrics, "targets_expired")
	return float(misses) + float(expired) if misses != null and expired != null else measured(metrics, "failed_actions")


static func effective_accuracy_pct(metrics: Dictionary) -> Variant:
	var hits: Variant = measured(metrics, "hits")
	var shots: Variant = measured(metrics, "shots")
	var expired: Variant = measured(metrics, "targets_expired")
	if hits != null and shots != null and expired != null:
		var attempts: float = float(shots) + float(expired)
		return 100.0 * float(hits) / attempts if attempts > 0.0 and float(hits) <= float(shots) else null
	var success_pct: Variant = measured(metrics, "effective_accuracy_pct")
	return success_pct if success_pct != null and float(success_pct) <= 100.0 else null


static func analyze_v1(report: Dictionary) -> Dictionary:
	var metrics: Dictionary = report.get("metrics", {}) if report.get("metrics", {}) is Dictionary else {}
	var tracking: bool = report.get("family", "") == "tracking"
	var hits: Variant = measured(metrics, "hits")
	var shots: Variant = measured(metrics, "shots")
	var accuracy_pct: Variant = 100.0 * float(hits) / float(shots) if hits != null and shots != null and float(shots) > 0.0 and float(hits) <= float(shots) else null
	var cadence_hits_s: Variant = measured(metrics, "hits_per_s")
	var cadence_hits_min: Variant = hits_per_minute(metrics)
	var on_target_ratio: Variant = measured(metrics, "on_target_ratio")
	if on_target_ratio != null and float(on_target_ratio) > 1.000001:
		on_target_ratio = null
	var tracking_pct: Variant = float(on_target_ratio) * 100.0 if on_target_ratio != null else null
	var on_target_time_s: Variant = measured(metrics, "on_target_time_s")
	var acquisition_ms: Variant = measured(metrics, "acquisition_median_ms") if hits != null and float(hits) > 0.0 else null
	var return_samples: Variant = metrics.get("reacquisition_samples", 1)
	var reacquisition_ms: Variant = measured(metrics, "reacquisition_median_ms") if on_target_time_s != null and float(on_target_time_s) > 0.0 and ScoringService.number(return_samples) and float(return_samples) > 0.0 else null
	var mean_error_deg: Variant = measured(metrics, "angular_error_mean_deg") if tracking else null
	var p95_error_deg: Variant = measured(metrics, "angular_error_p95_deg") if tracking else null
	var reason: String = ScoringService.comparison_error(report)
	var secondary_value: String = display(on_target_time_s, 2, "s") if tracking else ("%s / %s" % [display(hits, 0), display(shots, 0)])
	var tip: String
	var short_tip: String
	if tracking:
		short_tip = "Cherchez à garder le viseur sur la cible plus régulièrement." if tracking_pct != null and float(tracking_pct) < 100.0 else "Rejouez à la même vitesse pour confirmer ce suivi." if tracking_pct != null else "Suivez la cible pour établir votre première mesure."
		tip = "Suivi mesuré : %s." % display(tracking_pct, 1, "%")
		if p95_error_deg != null:
			tip += " Erreur angulaire p95 : %s. Chercher à réduire les pertes de suivi à taille et vitesse identiques." % display(p95_error_deg, 1, "°")
		else:
			tip += " Rejouer à taille et vitesse identiques pour comparer le temps sur cible."
	elif hits != null and shots != null and float(shots) > 0.0:
		var misses: float = maxf(float(shots) - float(hits), 0.0)
		short_tip = "Prenez un instant pour centrer le viseur avant chaque clic." if misses > 0.0 else "Essayez de cliquer un peu plus vite en gardant cette précision."
		tip = "%s tirs manqués sur %s, cadence de %s." % [display(misses, 0), display(shots, 0), display(cadence_hits_min, 0, "cibles/min")]
		tip += " Soigner les clics avant d’accélérer, puis comparer précision et cadence." if misses > 0.0 else " Essayer une cadence plus élevée en conservant cette précision."
	else:
		short_tip = "Bougez le viseur et cliquez sur les cibles pour commencer."
		tip = "Aucun tir mesurable : effectuer des clics et déplacer le viseur pour établir une référence."
	return {"eligible": reason.is_empty(), "primary_label": "Temps sur cible" if tracking else "Précision",
		"primary_value": display(tracking_pct if tracking else accuracy_pct, 1, "%"), "primary_unit": "%",
		"secondary_label": "Temps suivi" if tracking else "Touches / tirs", "secondary_value": secondary_value,
		"secondary_unit": "s" if tracking else "touches / tirs", "tempo_label": "Acquisition / retour" if tracking else "Cadence",
		"tempo_value": display(reacquisition_ms, 0, "ms") if tracking else display(cadence_hits_min, 0, "cibles/min"),
		"tempo_unit": "ms" if tracking else "cibles/min", "tip": tip, "short_tip": short_tip, "advice": short_tip, "reason": reason,
		"score_explanation": ScoringService.explain(report), "measurements": {
			"hits": measurement(hits, "touches", "Clics dont le rayon intersecte la sphère visible."),
			"shots": measurement(shots, "tirs", "Un clic validé compte un tir ; le tracking n’exige pas de clic."),
			"accuracy_pct": measurement(accuracy_pct, "%", "100 × touches / tirs ; indisponible sans tir."),
			"hits_per_s": measurement(cadence_hits_s if not tracking else null, "touches/s", "Touches divisées par la durée active ; aucune pause au dénominateur."),
			"hits_per_min": measurement(cadence_hits_min if not tracking else null, "cibles/min", "60 × touches par seconde de durée active ; pauses exclues."),
			"acquisition_median_ms": measurement(acquisition_ms if not tracking else null, "ms", "Clic : apparition jusqu’à la touche réussie ; transitions : intervalle entre touches réussies."),
			"on_target_time_s": measurement(on_target_time_s if tracking else null, "s", "Temps où le rayon de visée intersecte la silhouette sphérique."),
			"on_target_ratio": measurement(on_target_ratio if tracking else null, "ratio", "Temps sur cible divisé par le temps exposé intégré."),
			"target_exposed_time_s": measurement(measured(metrics, "target_exposed_time_s") if tracking else null, "s", "Durée active couverte par l’intégration tracking."),
			"angular_error_mean_deg": measurement(mean_error_deg, "°", "Écart au centre de la cible, moyenne pondérée par le temps."),
			"angular_error_p95_deg": measurement(p95_error_deg, "°", "Borne supérieure du bin de 0,1° contenant le percentile temporel 95."),
			"reacquisition_median_ms": measurement(reacquisition_ms if tracking else null, "ms", "Médiane des acquisitions après une perte, incluant la première acquisition depuis le départ."),
			"tracking_sample_step_s": measurement(ScenarioEngine.SAMPLE_STEP_S if tracking else null, "s", "Pas logique de 1/240 s, poses maintenues entre événements ; limite de résolution temporelle.")}}
