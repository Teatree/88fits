## A hero perk: a card only its hero is offered, taken once. Effects fold into the hero's sheet; `special` names a
## mechanism the systems run (Game, EnemyManager, Player), tuned by `params`. Content: content/perks/<id>/.
class_name PerkDef
extends ContentDef

@export var hero: String = ""
@export var text: String = ""
@export var effects: Array = []
@export var special: String = ""
@export var params: Dictionary = {}


func kind() -> String:
	return "perk"
