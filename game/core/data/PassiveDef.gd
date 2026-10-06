## A passive: a level table of Effects that target the player (or all weapons). Pass 47 splits content/passives in two:
## the line items (`line`: four levels, an evolution once maxed, six slots beside the weapons) and the passive items (the
## rest: no cap, not on the HUD, their rarity shown as the plate's colour).
class_name PassiveDef
extends ContentDef

## A line item (pass 47, Garry: "Line Items"): a levelled stat item that evolves when maxed and takes one of the six line
## slots next to the weapons on the HUD. Its evolution carries `line` too. False = a passive item: as many as the run
## finds, listed only on the pause screen's Build tab and in the Collection.
@export var line: bool = false

## levels[i] is an Array of Effect gained when reaching level i+1.
@export var levels: Array = []
## When true and levels has fewer entries than max_level, the last entry repeats for the remaining levels.
@export var repeat_last_level: bool = true
@export var max_level: int = 8
## Weapon id this passive pairs with for an evolution (informational; the weapon carries the recipe).
@export var pairs_with: String = ""
## The price in words ("−6% max HP a level"), empty for none (a line's trade; on the passive since pass 46).
@export var trade: String = ""
## What it evolves into once maxed (pass 33.2 on the lines, every passive since pass 46): a level-up card offers it at
## the top level.
@export var evolves_into: String = ""
## On an evolved one: what it replaces. An evolved item has one level and is never offered on its own.
@export var evolves_from: String = ""
## Its own sentence for the card (the Energy Shield's rules), shown above the generated effect text.
@export var text: String = ""


func kind() -> String:
	return "passive"


## Whether this is a line item (pass 47): `line` in its JSON. A line and a passive item are both kind() "passive" (the
## Registry, the save's met-it lists and the unlock quests know them by that); this tells them apart.
func is_line() -> bool:
	return line


## Whether this is the evolution of another (it replaces `evolves_from`).
func is_evolved() -> bool:
	return evolves_from != ""


func effects_at_level(level: int) -> Array:
	if levels.is_empty() or level < 1:
		return []
	var idx := level - 1
	if idx >= levels.size():
		if not repeat_last_level:
			return []
		idx = levels.size() - 1
	var lv = levels[idx]
	return lv if lv is Array else []


func effects_for_level(level: int) -> Array:
	var out: Array = []
	for l in range(1, level + 1):
		out.append_array(effects_at_level(l))
	return out
