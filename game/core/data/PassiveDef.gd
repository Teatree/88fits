## A passive: a level table of Effects that target the player (or all weapons).
class_name PassiveDef
extends ContentDef

## levels[i] is an Array of Effect gained when reaching level i+1.
@export var levels: Array = []
## When true and levels has fewer entries than max_level, the last entry repeats for the remaining levels.
@export var repeat_last_level: bool = true
@export var max_level: int = 8
## Weapon id this passive pairs with for an evolution (informational; the weapon carries the recipe).
@export var pairs_with: String = ""


func kind() -> String:
	return "passive"


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
