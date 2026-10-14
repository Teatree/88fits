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
## Pass 76 (lane LOOKS): its looks in its weapon family (ItemLooks; the family plays its weapon's `variant`): code -> the
## JSON entry resolved (name, flavour, text, icon, visual, params, note, shelved, fresh: only the keys it has), worn in
## place while its family plays that code; without an entry for the code it wears its top level (`look_top`).
@export var variants: Dictionary = {}
@export var variant_base: String = ""
var look_top: Dictionary = {}
var look_worn := "?"
const ItemLooks := preload("res://core/data/ItemLooks.gd")


func kind() -> String:
	return "mutation"


## Its looks (pass 76): its base first, then by code; shelved ones only when asked; [] with one look.
func variant_codes(include_shelved := false) -> Array:
	var all: Array = ItemLooks.codes(self, include_shelved)
	return all if all.size() > 1 else []


func variant_shelved(code: String) -> bool:
	return ItemLooks.shelved(self, code)


func variant_note(code: String) -> String:
	return ItemLooks.note(self, code)


func look_icon(code: String) -> Texture2D:
	return ItemLooks.look_icon(self, code)


func look_name(code: String) -> String:
	return ItemLooks.look_name(self, code)


## Wears look `code` (its entry, or its top level when it has none); returns the code worn.
func wear_look(code: String) -> String:
	return ItemLooks.wear(self, code)


func look_code() -> String:
	return ItemLooks.code_worn(self)


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
