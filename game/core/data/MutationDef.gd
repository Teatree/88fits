## A mutation: one of a weapon's three path picks (an Element, a Volume or a Motion) or a hero's own extra option for
## the favourite weapon. Its effects fold into the weapon's sheet (those aimed at "player" into the hero's), its params
## merge over the weapon's, and it may swap the weapon's behaviour or visual scene. Content: content/mutations/<id>/.
class_name MutationDef
extends ContentDef

## The family: a base weapon id. The weapon's evolution inherits the mutation.
@export var weapon: String = ""
## element | volume | motion | hero
@export var mutation_kind: String = "motion"
## Set on a hero mutation: only that hero sees it, and it sits outside the weapon's path.
@export var hero: String = ""
## The card line.
@export var text: String = ""
## What it looks like in the world (the bible's table).
@export var vfx: String = ""
@export var effects: Array = []
@export var params: Dictionary = {}
## An optional behaviour that replaces the weapon's (Needle Rain turns the darts into a Lobber).
@export var behavior: String = ""
## An optional visual scene that replaces the weapon's.
@export var visual: PackedScene
@export var visual_file: String = ""


func kind() -> String:
	return "mutation"


func is_hero() -> bool:
	return hero != ""


## Effects aimed at the weapon (everything not marked "player").
func weapon_effects() -> Array:
	var out: Array = []
	for e in effects:
		if e is Effect and e.target != "player":
			out.append(e)
	return out


## Effects aimed at the hero's sheet.
func player_effects() -> Array:
	var out: Array = []
	for e in effects:
		if e is Effect and e.target == "player":
			out.append(e)
	return out
