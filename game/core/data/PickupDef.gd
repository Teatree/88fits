## A pickup that appears on the ground now and then (content/pickups/<id>/): a heal, a timed buff, a shield,
## or a gem vacuum. Which ones appear, how often and how rare is the map's timeline ("pickups" block).
class_name PickupDef
extends ContentDef

## heal | buff | shield | vacuum
@export var effect_kind: String = "heal"
## heal: fraction of max HP restored.
@export var value: float = 0.3
## buff / shield: seconds it lasts.
@export var duration: float = 0.0
## buff: Effects on the player sheet while it lasts.
@export var effects: Array = []
## Seconds it waits on the ground before fading away.
@export var lifetime: float = 20.0
## Colour of its glow.
@export var color: Color = Color(1, 1, 1)


func kind() -> String:
	return "pickup"
