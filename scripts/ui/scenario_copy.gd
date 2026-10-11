class_name ScenarioCopy
extends RefCounted

const TITLES: Dictionary = {
	"C01": "Une cible, un clic", "C02": "Micro-précision", "C03": "La grille",
	"C04": "Grands mouvements", "C05": "Six petites cibles", "C07": "Visée verticale",
	"D01": "Réflexes", "D02": "Cible mobile", "T01": "Suivi horizontal",
	"T02": "Suivi vertical", "T03": "Suivi diagonal", "T04": "Suivi circulaire",
	"T05": "Changements de direction", "T09": "Suivi de précision",
	"S01": "De cible en cible", "S02": "Transitions mobiles"
}

const DESCRIPTIONS: Dictionary = {
	"C01": "Visez la cible, puis cliquez.",
	"C02": "Visez les petites cibles proches, puis cliquez.",
	"C03": "Cliquez sur les cibles de la grille dans l’ordre de votre choix.",
	"C04": "Visez de l’autre côté de l’écran, puis cliquez.",
	"C05": "Cliquez sur les six petites cibles, une à une.",
	"C07": "Cliquez sur les cibles en haut et en bas.",
	"D01": "Cliquez sur la cible avant qu’elle disparaisse : une seconde.",
	"D02": "Cliquez sur la cible pendant qu’elle se déplace.",
	"T01": "Gardez le viseur sur la cible qui va de gauche à droite.",
	"T02": "Gardez le viseur sur la cible qui monte et descend.",
	"T03": "Gardez le viseur sur la cible qui se déplace en diagonale.",
	"T04": "Gardez le viseur sur la cible qui tourne en cercle.",
	"T05": "Gardez le viseur sur la cible à chaque changement de direction.",
	"T09": "Gardez le viseur sur la petite cible lente.",
	"S01": "Cliquez sur une cible, puis visez la suivante.",
	"S02": "Visez une cible mobile, cliquez, puis passez à la suivante."
}


static func title(definition: ScenarioDefinition) -> String:
	return str(TITLES.get(definition.scenario_id, definition.title))


static func description(definition: ScenarioDefinition) -> String:
	return str(DESCRIPTIONS.get(definition.scenario_id, definition.instructions))


static func family(definition: ScenarioDefinition) -> String:
	return {"click": "PRÉCISION", "tracking": "SUIVI", "switching": "TRANSITIONS"}[definition.family]


static func interaction(definition: ScenarioDefinition) -> String:
	return "Suivez avec le viseur. Tir facultatif." if definition.family == "tracking" else "Un clic pour chaque tir."


static func measure(definition: ScenarioDefinition) -> String:
	return "Mesure : % du temps avec le viseur sur la cible. Tir facultatif." if definition.family == "tracking" else "Mesures : % de tirs réussis et cibles touchées par minute."
