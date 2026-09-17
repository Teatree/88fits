## A weapon the player holds: its def, level, and a StatSheet resolved from base stats,
## level effects, player passives that target weapons, and the player's global multipliers.
class_name WeaponInstance
extends RefCounted

var def: WeaponDef
var level: int = 1
var sheet: StatSheet = StatSheet.new()
var kills: int = 0
var damage: float = 0.0
## Extra effects granted for this instance only (character favourite bonus).
var bonus_effects: Array = []


func _init(p_def: WeaponDef, p_level: int = 1) -> void:
	def = p_def
	level = clamp(p_level, 1, p_def.max_level if p_def else 8)


func rebuild(player: StatSheet, all_weapons: Array) -> void:
	sheet = StatSheet.new()
	sheet.set_bases({"damage": 5.0, "cooldown": 1.0, "amount": 1, "pierce": 0, "area": 1.0, "speed": 10.0,
		"duration": 2.0, "knockback": 0.0, "chains": 0, "range": 8.0, "spread_deg": 30.0, "orbit_radius": 2.0, "lifetime": 12.0})
	sheet.set_bases(def.base)
	sheet.add_effects(def.effects_for_level(level), "level")
	sheet.add_effects(bonus_effects, "bonus")
	# player-side multipliers that every weapon inherits
	var might := player.get_stat("might", 1.0)
	if abs(might - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("damage", "mul", might - 1.0), "might")
	var cd := player.get_stat("cooldown", 1.0)
	if abs(cd - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("cooldown", "mul", cd - 1.0), "haste")
	var area := player.get_stat("area", 1.0)
	if abs(area - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("area", "mul", area - 1.0), "reach")
		sheet.add_effect(Effect.make("orbit_radius", "mul", (area - 1.0) * 0.5), "reach")
	var ps := player.get_stat("projectile_speed", 1.0)
	if abs(ps - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("speed", "mul", ps - 1.0), "projectile speed")
	var dur := player.get_stat("duration", 1.0)
	if abs(dur - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("duration", "mul", dur - 1.0), "duration")
	var extra_amount := player.get_stat("amount", 0.0)
	if extra_amount > 0.0:
		sheet.add_effect(Effect.make("amount", "add", extra_amount), "multishot")
	# passive effects aimed at weapons
	for en in player.entries:
		var e: Effect = en["effect"]
		if e.target == "all_weapons" or e.target == "weapon:" + def.id:
			sheet.add_effect(e, en["source"])


## The element this weapon carries: "fire", "poison" or "".
func element() -> String:
	if def.element != "":
		return def.element
	if float(def.base.get("fire_damage", 0.0)) > 0.0:
		return "fire"
	if float(def.base.get("poison_damage", 0.0)) > 0.0:
		return "poison"
	return ""


func stat(name: String, default: float = 0.0) -> float:
	return sheet.get_stat(name, default)


func stat_int(name: String, default: int = 0) -> int:
	return sheet.get_int(name, default)


func dps_estimate() -> float:
	var cd: float = max(stat("cooldown", 1.0), 0.05)
	var hits := float(max(stat_int("amount", 1), 1))
	match def.behavior:
		"Orbiter":
			return stat("damage") * hits * 2.0
		"Beam":
			return stat("damage") * (1.0 + float(stat_int("chains", 0))) / cd
		"Spawner":
			return stat("damage") * 3.0
		_:
			return stat("damage") * hits / cd


func description() -> String:
	return TextGen.weapon_description(def, sheet)


func stat_rows() -> Array:
	## [{"stat": "damage", "name": "damage", "value": "9.4"}] for the pause screen, only stats the behaviour uses.
	var keys: Array = []
	match def.behavior:
		"ProjectileEmitter":
			keys = ["damage", "cooldown", "amount", "range", "pierce", "knockback", "speed"]
			if def.targeting == "forward":
				keys.append("spread_deg")
		"Orbiter":
			keys = ["damage", "amount", "orbit_radius", "knockback", "area"]
		"Lobber":
			keys = ["damage", "cooldown", "amount", "area", "range", "knockback"]
		"Beam":
			keys = ["damage", "cooldown", "chains", "range"]
		"Spawner":
			keys = ["damage", "cooldown", "lifetime", "range", "amount"]
		_:
			keys = ["damage", "cooldown", "amount"]
	if sheet.get_stat("poison_damage", 0.0) > 0.0:
		keys += ["poison_damage", "poison_stacks", "poison_duration"]
	if sheet.get_stat("fire_damage", 0.0) > 0.0:
		keys += ["fire_damage", "fire_duration", "fire_spread"]
	var rows: Array = []
	for k in keys:
		rows.append({"stat": k, "name": TextGen.stat_name(k), "value": TextGen.format_value(k, sheet.get_stat(k))})
	rows.append({"stat": "dps", "name": "dps", "value": str(int(round(dps_estimate())))})
	return rows
