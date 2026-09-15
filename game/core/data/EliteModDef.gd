## An elite modifier stacked on any enemy archetype: Effects plus a visual and a death rule.
class_name EliteModDef
extends ContentDef

## Effects applied to the enemy's own stats (hp, speed, damage, armor, size).
@export var effects: Array = []
## Outline colour drawn behind the sprite.
@export var outline: Color = Color(1, 1, 1)
@export var scale_mult: float = 1.5
## none | split | explode
@export var on_death: String = "none"
## Extra parameters, e.g. {"split_count": 3, "explode_radius": 3.0, "explode_damage": 20}
@export var params: Dictionary = {}


func kind() -> String:
	return "elite"
