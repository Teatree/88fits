## A permanent shop upgrade: one Effect repeated per tier with rising gold cost.
class_name ShopUpgradeDef
extends ContentDef

## Effect applied once per tier bought (target player).
@export var effect_per_tier: Effect
## Gold cost of each tier, in order. Size = number of tiers.
@export var costs: Array = []
## Sort order in the shop list.
@export var order: int = 0
## Optional human line replacing the generated "+x per tier" text.
@export var effect_text: String = ""


func kind() -> String:
	return "shop"


func tiers() -> int:
	return costs.size()


func cost_of_tier(t: int) -> int:
	if t < 0 or t >= costs.size():
		return -1
	return int(costs[t])


func effects_for_tiers(bought: int) -> Array:
	var out: Array = []
	if effect_per_tier == null:
		return out
	for i in range(min(bought, costs.size())):
		out.append(effect_per_tier)
	return out
