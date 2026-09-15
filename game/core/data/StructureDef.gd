## A structure scattered on the map (content/structures/<id>/): a small 3D landmark the hero uses once by standing
## in its circle for a few seconds. What it does is `effect_kind` with `params`; how often it appears is `weight`.
class_name StructureDef
extends ContentDef

## vacuum_all | shop | heal | loot | buff | dice | level_up
@export var effect_kind: String = "heal"
## Free-form numbers for the effect: heal {"fraction": 0.5}, loot {"gold": 60, "gems": 3}, buff {"seconds": 30, "effects": [...]}, dice {"outcomes": [...]}
@export var params: Dictionary = {}
## Effects for the buff kind (parsed from params.effects).
@export var effects: Array = []
## Metres the hero must stand within, and for how long.
@export var radius: float = 2.2
@export var interact_time: float = 3.0
## Colour of the ring, the progress marker and the glow.
@export var color: Color = Color(1, 1, 1)
## GLB in res://art/props/ (a primitive stand-in is built when it is missing).
@export var prop: String = ""
## Approximate height, for the glow and the used-up tint.
@export var height: float = 2.0


func kind() -> String:
	return "structure"
