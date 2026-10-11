class_name WeaponCatalog
extends RefCounted

const DEFINITIONS: Array[WeaponDefinition] = [preload("res://content/weapons/pulse.tres"), preload("res://content/weapons/vector.tres"), preload("res://content/weapons/classic.tres")]


static func find(weapon_id: String) -> WeaponDefinition:
	for definition in DEFINITIONS:
		if definition.weapon_id == weapon_id:
			return definition
	return null
