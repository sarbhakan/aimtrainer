class_name ScenarioCopy
extends RefCounted

const TITLES: Dictionary = {
	"C01": "Cible unique", "C02": "Micro-précision", "C03": "Multicibles",
	"C04": "Grands mouvements", "C05": "Précision avancée", "C07": "Visée verticale",
	"D01": "Réflexes", "D02": "Cible mobile", "T01": "Suivi horizontal",
	"T02": "Suivi vertical", "T03": "Suivi diagonal", "T04": "Suivi circulaire",
	"T05": "Suivi réactif", "T09": "Suivi avancé", "T10": "Suivi varié",
	"M01": "Flicks mixtes",
	"S01": "De cible en cible", "S02": "Transitions mobiles"
}

const DESCRIPTIONS: Dictionary = {
	"C01": "Visez la cible, puis cliquez.",
	"C02": "Ajustez le viseur entre les cibles proches et cliquez.",
	"C03": "Cliquez sur les cibles réparties devant vous, dans l’ordre de votre choix.",
	"C04": "Enchaînez de grands déplacements du viseur et cliquez.",
	"C05": "Défi avancé facultatif : cliquez sur les six petites cibles.",
	"C07": "Cliquez sur les cibles en haut et en bas.",
	"D01": "Touchez la cible avant qu’elle rétrécisse et disparaisse.",
	"D02": "Touchez la cible malgré ses changements de direction.",
	"T01": "Gardez le viseur sur la cible qui va de gauche à droite.",
	"T02": "Gardez le viseur sur la cible qui monte et descend.",
	"T03": "Gardez le viseur sur la cible qui se déplace en diagonale.",
	"T04": "Gardez le viseur sur la cible qui tourne en cercle.",
	"T05": "Gardez le viseur sur la cible à chaque changement de direction.",
	"T09": "Défi avancé facultatif : suivez la petite cible lente.",
	"T10": "Suivez la cible dans toutes les directions, même quand elle se rapproche.",
	"M01": "Alternez petits ajustements et grands mouvements du viseur, puis cliquez.",
	"S01": "Cliquez sur une cible, puis visez la suivante.",
	"S02": "Passez entre les cibles mobiles, proches et lointaines."
}


static func title(definition: ScenarioDefinition) -> String:
	return str(TITLES.get(definition.scenario_id, definition.title))


static func description(definition: ScenarioDefinition) -> String:
	var text: String = str(DESCRIPTIONS.get(definition.scenario_id, definition.instructions))
	if temporal(definition):
		if definition.scenario_id == "D01":
			text = "Touchez la cible avant son échéance."
		text += " La cible rétrécit puis est remplacée à son échéance." if definition.family == "tracking" else " Les cibles rétrécissent puis expirent."
	return text


static func temporal(definition: ScenarioDefinition) -> bool:
	return definition.has_lifecycle()


static func report_definition(report: Dictionary) -> ScenarioDefinition:
	var scenario_id: String = str(report.get("scenario_id", ""))
	if report.has("scenario_fingerprint"):
		var definition := ScenarioCatalog.resolve(scenario_id, str(report.scenario_fingerprint))
		if definition != null:
			return definition
	if int(report.get("scenario_revision", 1)) >= 6:
		return ScenarioCatalog.find_practice(scenario_id)
	return ScenarioCatalog.find(scenario_id)


static func family(definition: ScenarioDefinition) -> String:
	return {"click": "PRÉCISION", "tracking": "SUIVI", "switching": "TRANSITIONS"}[definition.family]


static func interaction(definition: ScenarioDefinition) -> String:
	return "Suivez avec le viseur. Tir facultatif." if definition.family == "tracking" else "Un clic pour chaque tir."


static func measure(definition: ScenarioDefinition) -> String:
	if temporal(definition) and definition.family != "tracking":
		return "Mesures : touches, tirs ratés et cibles oubliées."
	return "Mesure : % du temps avec le viseur sur la cible. Tir facultatif." if definition.family == "tracking" else "Mesures : % de tirs réussis et cibles touchées par minute."
