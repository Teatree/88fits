## One stat operation. The only way any content changes a number.
## Weapon levels, passives, shop tiers, elite modifiers, and character traits are all lists of these.
class_name Effect
extends Resource

## Stat name, e.g. "damage", "might", "move_speed". See StatSheet.STATS for the known list.
@export var stat: String = ""
## "add" adds value to the base, "mul" multiplies the total by (1 + value), "set" replaces the base.
@export var op: String = "add"
@export var value: float = 0.0
## "self" = the item this effect belongs to (weapon stats), "player" = player stats,
## "all_weapons" = every weapon's stat of that name, "weapon:<id>" = one weapon.
@export var target: String = "self"


static func make(p_stat: String, p_op: String, p_value: float, p_target: String = "self") -> Effect:
	var e := Effect.new()
	e.stat = p_stat
	e.op = p_op
	e.value = p_value
	e.target = p_target
	return e


static func from_dict(d: Dictionary, default_target: String = "self") -> Effect:
	return make(str(d.get("stat", "")), str(d.get("op", "add")), float(d.get("value", 0.0)), str(d.get("target", default_target)))


func to_dict() -> Dictionary:
	return {"stat": stat, "op": op, "value": value, "target": target}


func describe() -> String:
	return TextGen.describe_effect(self)
