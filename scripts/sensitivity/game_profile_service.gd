class_name GameProfileService
extends RefCounted

const IDS: Array[String] = ["cs2", "valorant", "cod", "custom"]
const TITLES: Array[String] = ["Counter-Strike 2", "VALORANT", "Call of Duty · profil mesuré", "Autre jeu · profil mesuré"]


static func default_yaw(game_id: String) -> float:
	return {"cs2": 0.022, "valorant": 0.07}.get(game_id, 0.0)


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0


static func validate_reference(reference: Variant) -> String:
	if not reference is Dictionary:
		return "Le profil du jeu source est invalide."
	if not reference.get("game_id", null) is String or not reference.game_id in IDS:
		return "Jeu source inconnu."
	if not reference.get("title", null) is String or reference.title.strip_edges().is_empty() or reference.title.length() > 96:
		return "Indiquez le titre et la version du jeu source."
	for field in ["dpi", "sensitivity", "yaw_deg", "source_cm_per_360"]:
		if not number(reference.get(field, null)):
			return "Valeur du jeu source invalide : " + field
	if float(reference.dpi) > 64000.0 or float(reference.source_cm_per_360) < 5.0 or float(reference.source_cm_per_360) > 150.0:
		return "Le profil source dépasse les limites de souris prises en charge."
	if not reference.get("confidence", "") in ["documented", "user_coefficient", "user_measurement"]:
		return "Origine du coefficient de jeu inconnue."
	if reference.game_id in ["cod", "custom"] and reference.confidence != "user_measurement":
		return "Ce jeu nécessite un profil mesuré, pas un coefficient universel."
	if reference.game_id == "valorant" and (reference.confidence != "documented" or not is_equal_approx(float(reference.yaw_deg), 0.07)):
		return "Le coefficient documentaire VALORANT doit rester 0,07."
	if reference.game_id == "cs2" and reference.confidence == "documented" and not is_equal_approx(float(reference.yaw_deg), 0.022):
		return "Un m_yaw modifié doit être identifié comme personnalisé."
	var expected_distance := 914.4 / (float(reference.dpi) * float(reference.sensitivity) * float(reference.yaw_deg))
	if not is_equal_approx(expected_distance, float(reference.source_cm_per_360)):
		return "Le profil du jeu source ne correspond pas à la distance déclarée."
	return ""


static func import_profile(current: Dictionary, game_id: String, dpi: float, sensitivity: float, title: String = "", measured_cm: float = 0.0, cs2_yaw: float = 0.022) -> Dictionary:
	var current_error := SensitivityService.validate_profile(current)
	if not current_error.is_empty():
		return {"error": "Profil AIM/LOCAL invalide : " + current_error}
	if not game_id in IDS or not number(dpi) or dpi > 64000.0 or not number(sensitivity):
		return {"error": "Entrez des DPI et une sensibilité de jeu positifs et valides."}
	var historical_reference: Dictionary = current.get("reference_game", {})
	if _matches_reference(historical_reference, game_id, dpi, sensitivity, title, measured_cm, cs2_yaw):
		return _profile_from_reference(current, historical_reference)
	var yaw_deg := default_yaw(game_id)
	var confidence := "documented"
	if game_id == "cs2":
		if not number(cs2_yaw):
			return {"error": "Le coefficient m_yaw doit être positif."}
		yaw_deg = cs2_yaw
		confidence = "documented" if is_equal_approx(cs2_yaw, 0.022) else "user_coefficient"
	if game_id in ["cod", "custom"]:
		if title.strip_edges().is_empty() or title.length() > 96:
			return {"error": "Indiquez le titre et la version du jeu pour conserver ce profil."}
		if not number(measured_cm) or measured_cm < 5.0 or measured_cm > 150.0:
			return {"error": "Mesurez la distance nécessaire pour faire un tour complet, entre 5 et 150 cm."}
		yaw_deg = 914.4 / (dpi * sensitivity * measured_cm)
		confidence = "user_measurement"
	var distance_cm := measured_cm if game_id in ["cod", "custom"] else 914.4 / (dpi * sensitivity * yaw_deg)
	if distance_cm < 5.0 or distance_cm > 150.0:
		return {"error": "Ce réglage est hors de la plage prise en charge (5 à 150 cm par tour). Vérifiez les DPI et la sensibilité."}
	var reference := {"game_id": game_id, "title": title.strip_edges() if game_id in ["cod", "custom"] else TITLES[IDS.find(game_id)],
		"dpi": dpi, "sensitivity": sensitivity, "yaw_deg": yaw_deg,
		"source_cm_per_360": distance_cm, "confidence": confidence}
	var reference_error := validate_reference(reference)
	if not reference_error.is_empty():
		return {"error": reference_error}
	return _profile_from_reference(current, reference)


static func _matches_reference(reference: Dictionary, game_id: String, dpi: float, sensitivity: float, title: String, measured_cm: float, cs2_yaw: float) -> bool:
	if reference.is_empty() or reference.game_id != game_id or reference.dpi != dpi or reference.sensitivity != sensitivity:
		return false
	if game_id in ["cod", "custom"]:
		return reference.title.strip_edges() == title.strip_edges() and reference.source_cm_per_360 == measured_cm
	if game_id == "cs2":
		return reference.yaw_deg == cs2_yaw
	return true


static func _profile_from_reference(current: Dictionary, reference: Dictionary) -> Dictionary:
	var profile := current.duplicate(true)
	profile.cm_per_360 = float(reference.source_cm_per_360)
	profile.reference_game = reference.duplicate(true)
	return {"error": "", "profile": profile}


static func confidence_text(reference: Dictionary) -> String:
	return {"documented": "Coefficient documentaire · sans zoom", "user_coefficient": "Coefficient personnalisé · sans zoom",
		"user_measurement": "Rotation issue de votre mesure · sans zoom"}.get(reference.get("confidence", ""), "Profil non renseigné")
