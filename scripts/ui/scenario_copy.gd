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
	"C01": "Visez la cible et cliquez. Une nouvelle apparaît après chaque touche.",
	"C02": "Touchez de petites cibles proches. Prenez le temps de terminer chaque mouvement.",
	"C03": "Touchez les cibles de la grille, dans l’ordre de votre choix.",
	"C04": "Passez rapidement d’un côté à l’autre et cliquez sans dépasser la cible.",
	"C05": "Touchez six petites cibles. Restez précis en passant de l’une à l’autre.",
	"C07": "Touchez les cibles en haut et en bas. Gardez le contrôle sur l’axe vertical.",
	"D01": "Touchez la cible avant qu’elle disparaisse. Vous avez une seconde.",
	"D02": "Cliquez sur la cible pendant qu’elle se déplace.",
	"T01": "Gardez le viseur sur la cible pendant ses allers-retours horizontaux.",
	"T02": "Gardez le viseur sur la cible quand elle monte et descend.",
	"T03": "Suivez la cible en diagonale, avec des mouvements réguliers.",
	"T04": "Suivez la cible tout au long de sa trajectoire circulaire.",
	"T05": "Restez sur la cible, même quand elle change brusquement de direction.",
	"T09": "Suivez une petite cible lente. Corrigez votre visée par petits mouvements.",
	"S01": "Touchez une cible, puis passez à la suivante. Gardez un rythme précis.",
	"S02": "Passez d’une cible mobile à l’autre et cliquez pour les toucher."
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
	return "Le score récompense le temps passé sur la cible." if definition.family == "tracking" else "Le score récompense les touches rapides et précises."
