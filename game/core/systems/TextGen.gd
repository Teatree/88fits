## Generates every piece of item text from data: effect lines, weapon descriptions,
## next-level previews, evolution status. Nothing in the UI is hand-written per item.
class_name TextGen
extends RefCounted

## stat -> [display name, kind]. kind: "num" plain number, "pct" shown as percent when mul, "sec" seconds, "m" metres, "count" integer
const STATS := {
	"damage": ["damage", "num"], "cooldown": ["cooldown", "sec"], "amount": ["projectiles", "count"],
	"pierce": ["pierce", "count"], "area": ["area", "pct"], "speed": ["projectile speed", "num"],
	"duration": ["duration", "sec"], "knockback": ["knockback", "num"], "chains": ["chain jumps", "count"],
	"range": ["range", "m"], "spread_deg": ["spread", "deg"], "orbit_radius": ["orbit radius", "m"],
	"max_hp": ["max HP", "num"], "damage_reduction": ["damage reduction", "pct"], "regen": ["regen per second", "num"],
	"move_speed": ["move speed", "num"], "might": ["might", "pct"], "projectile_speed": ["projectile speed", "pct"],
	"magnet": ["pickup radius", "m"], "luck": ["luck", "pct"], "greed": ["greed", "pct"], "revives": ["revives", "count"],
	"rerolls": ["rerolls", "count"], "skips": ["skips", "count"], "banishes": ["banishes", "count"],
	"hp": ["HP", "num"], "size": ["size", "pct"], "turn_rate": ["turn rate", "num"], "lifetime": ["turret lifetime", "sec"],
	"poison_damage": ["poison per tick", "num"], "poison_stacks": ["poison stacks", "count"], "poison_duration": ["poison lasts", "sec"],
	"lifesteal": ["life steal", "pct"], "fire_damage": ["burn per tick", "num"], "fire_duration": ["burns for", "sec"], "fire_spread": ["spread chance", "pct"],
	"crit_chance": ["crit chance", "pct"], "crit_damage": ["crit damage", "pct"], "execute_frac": ["execute threshold", "pct"],
	"thorns": ["thorns damage", "num"], "adrenaline_speed": ["speed per kill stack", "pct"], "adrenaline_might": ["might per kill stack", "pct"],
	"overkill": ["overkill splash", "pct"], "cooldown_on_kill": ["cooldown cut per kill", "sec"], "xp_gain": ["XP gain", "pct"],
	"ricochet": ["ricochet chance", "pct"], "homing_turn": ["homing agility", "pct"], "haste": ["weapon speed", "pct"],
	"evade": ["evade chance", "pct"], "evade_invuln": ["untouchable after an evade", "sec"], "shield_max": ["shield", "num"],
	"shield_delay": ["shield recharge wait", "sec"], "shield_rate": ["shield recharge a second", "pct"],
	"regen_delay": ["regen wait after a hit", "sec"], "lifesteal_cap": ["life steal cap a second", "pct"],
	"heal_drop": ["cheese drop chance", "pct"], "coin_drop": ["coin bag drop chance", "pct"],
	"brand_chance": ["chance a kill burns the ground", "pct"],
}

const RARITY_NAMES := {"common": "Common", "rare": "Rare", "epic": "Epic"}


static func stat_name(stat: String) -> String:
	if STATS.has(stat):
		return STATS[stat][0]
	return stat.replace("_", " ")


static func stat_kind(stat: String) -> String:
	if STATS.has(stat):
		return STATS[stat][1]
	return "num"


static func format_value(stat: String, v: float) -> String:
	match stat_kind(stat):
		"pct":
			return "%d%%" % int(round(v * 100.0))
		"sec":
			return "%.2f s" % v
		"m":
			return "%.1f m" % v
		"deg":
			return "%d°" % int(round(v))
		"count":
			return str(int(round(v)))
		_:
			if abs(v - round(v)) < 0.001:
				return str(int(round(v)))
			return "%.1f" % v


static func _signed(v: float, suffix: String = "") -> String:
	var s := ""
	if abs(v - round(v)) < 0.001:
		s = str(int(round(abs(v))))
	else:
		s = "%.1f" % abs(v)
	return ("+" if v >= 0.0 else "−") + s + suffix


static func describe_effect(e: Effect, with_name: bool = true) -> String:
	var name := stat_name(e.stat)
	var kind := stat_kind(e.stat)
	var out := ""
	match e.op:
		"mul":
			var pct := int(round(e.value * 100.0))
			out = ("+" if pct >= 0 else "−") + str(abs(pct)) + "%"
			if with_name:
				out += " " + name
		"add":
			match kind:
				"count":
					var n := int(round(e.value))
					out = _signed(float(n))
					if with_name:
						out += " " + (name if n != 1 and n != -1 else _singular(name))
				"sec":
					out = _signed(e.value, " s") + (" " + name if with_name else "")
				"m":
					out = _signed(e.value, " m") + (" " + name if with_name else "")
				"pct":
					out = _signed(e.value * 100.0, "%") + (" " + name if with_name else "")
				_:
					out = _signed(e.value) + (" " + name if with_name else "")
		"set":
			out = (name + " = " if with_name else "= ") + format_value(e.stat, e.value)
	if e.target == "all_weapons":
		out += ", all weapons"
	elif e.target.begins_with("weapon:"):
		out += ", " + e.target.trim_prefix("weapon:").capitalize()
	return out


static func _singular(name: String) -> String:
	if name.ends_with("shes") or name.ends_with("ches") or name.ends_with("xes"):
		return name.trim_suffix("es")
	if name.ends_with("s"):
		return name.trim_suffix("s")
	return name


static func describe_effects(list: Array, with_name: bool = true) -> String:
	var parts: Array = []
	for e in list:
		if e is Effect:
			parts.append(describe_effect(e, with_name))
	return ", ".join(parts)


static func weapon_description(def: WeaponDef, sheet: StatSheet) -> String:
	var amount := sheet.get_int("amount", 1)
	var range_m := sheet.get_stat("range", 8.0)
	var text := ""
	match def.behavior:
		"ProjectileEmitter":
			match def.targeting:
				"forward":
					text = "Fires %d pellet%s in a %d° cone where you face." % [amount, "" if amount == 1 else "s", int(round(sheet.get_stat("spread_deg", 30.0)))]
				"random":
					text = "Fires %d shot%s at random enemies within %.0f m." % [amount, "" if amount == 1 else "s", range_m]
				"healthy":
					if sheet.get_stat("fire_damage", 0.0) > 0.0:
						text = "Fires %d flare%s at the nearest enemy within %.0f m that is not burning yet." % [amount, "" if amount == 1 else "s", range_m]
					else:
						text = "Fires %d dart%s at the nearest enemy within %.0f m that is not poisoned yet." % [amount, "" if amount == 1 else "s", range_m]
				_:
					text = "Fires %d shot%s at the nearest enemy within %.0f m." % [amount, "" if amount == 1 else "s", range_m]
		"Orbiter":
			text = "%d blade%s circle you at %.1f m, hitting anything they touch." % [amount, "" if amount == 1 else "s", sheet.get_stat("orbit_radius", 2.0)]
		"Lobber":
			if sheet.get_stat("fire_damage", 0.0) > 0.0:
				text = "Lobs %d bottle%s of fire at the thickest crowd that is not burning yet. Leaves a %.1f m pool of flames." % [amount, "" if amount == 1 else "s", sheet.get_stat("area", 2.5)]
			elif sheet.get_stat("poison_damage", 0.0) > 0.0:
				text = "Lobs %d poison bomb%s at the thickest crowd of healthy enemies. Leaves a %.1f m cloud of green smoke." % [amount, "" if amount == 1 else "s", sheet.get_stat("area", 2.5)]
			else:
				text = "Lobs %d grenade%s at the densest crowd. Explodes in a %.1f m radius." % [amount, "" if amount == 1 else "s", sheet.get_stat("area", 2.5)]
		"Beam":
			text = "Zaps a random enemy within %.0f m and chains to %d more." % [range_m, sheet.get_int("chains", 2)]
		"Thruster":
			var th = def.params.get("thrust", {})
			var slice_deg: float = float(th.get("slice_deg", 0.0)) if th is Dictionary else 0.0
			if slice_deg > 0.0:
				text = "Slices a %d° arc across the nearest enemy within %.1f m%s, throwing what it cuts out and aside." % [int(slice_deg), range_m, (", %d swings a stroke" % amount) if amount > 1 else ""]
			else:
				text = "Thrusts %d blade%s at the nearest enemy within %.1f m." % [amount, "" if amount == 1 else "s", range_m]
		"Smasher":
			var sm = def.params.get("smash", {})
			var blast: float = (float(sm.get("radius", 1.6)) if sm is Dictionary else 1.6) * sheet.get_stat("area", 1.0)
			text = "Brings %d hammer%s down on the thickest crowd within %.1f m: a %.1f m blast that throws them outwards." % [amount, "" if amount == 1 else "s", range_m, blast]
		"GravityGun":
			var gv = def.params.get("gravity", {})
			var gd: Dictionary = gv if gv is Dictionary else {}
			if gd.get("black_hole") is Dictionary:
				text = "Lobs %d black hole%s at the thickest crowd: %s drag%s everything in and eat%s it, then pop%s." % [amount, "" if amount == 1 else "s", "it" if amount == 1 else "they", "s" if amount == 1 else "", "s" if amount == 1 else "", "s" if amount == 1 else ""]
			else:
				text = "Picks up %d enem%s within %.0f m and throws %s into the thickest crowd: a %.1f m blast. What it throws takes a hit when it lands." % [amount, "y" if amount == 1 else "ies", range_m, "it" if amount == 1 else "them", float(gd.get("blast", 1.9)) * sheet.get_stat("area", 1.0)]
		"Spawner":
			text = "Drops a turret every %.1f s. It shoots the nearest enemy for %.0f s." % [sheet.get_stat("cooldown", 6.0), sheet.get_stat("lifetime", 12.0)]
		"MissilePod":
			# a pod that circles the hero: rockets with a blast, or seekers that sting and fizzle
			var blast_m := sheet.get_stat("area", 0.0)
			if blast_m > 0.3:
				text = "Launches %d homing rocket%s at enemies within %.0f m: a %.1f m blast each." % [amount, "" if amount == 1 else "s", range_m, blast_m]
			else:
				text = "Sends %d seeker%s after enemies within %.0f m." % [amount, "" if amount == 1 else "s", range_m]
		"LaserBeam":
			text = "Pours a %.0f m beam through the crowd for %.1f s." % [range_m, sheet.get_stat("duration", 2.0)]
		_:
			text = def.display_name + "."
	var extras: Array = []
	var pd := sheet.get_stat("poison_damage", 0.0)
	if pd > 0.0:
		var st := maxi(sheet.get_int("poison_stacks", 1), 1)
		extras.append("Poisons: %.0f damage every 2 s for %.0f s%s." % [pd * st, sheet.get_stat("poison_duration", 10.0), (" (%d stacks)" % st) if st > 1 else ""])
	var fd := sheet.get_stat("fire_damage", 0.0)
	if fd > 0.0:
		extras.append("Sets on fire: %.0f damage every 0.6 s for %.1f s. Spreads to touching enemies (%d%%)." % [fd, sheet.get_stat("fire_duration", 1.8), int(round(sheet.get_stat("fire_spread", 0.5) * 100.0))])
	var pierce := sheet.get_int("pierce", 0)
	if pierce > 0 and def.behavior == "ProjectileEmitter":
		extras.append("Pierces %d." % pierce)
	if sheet.get_stat("knockback", 0.0) > 0.0:
		extras.append("Knocks enemies back.")
	if def.hero != "":
		# the Registry by path: tools compile this before the autoloads exist
		var ml := Engine.get_main_loop()
		var reg: Node = (ml as SceneTree).root.get_node_or_null("Registry") if ml is SceneTree else null
		var owner = reg.character(def.hero) if reg else null
		extras.append("%s only." % (str(owner.display_name) if owner else def.hero.capitalize()))
	if def.is_evolution:
		extras.append("Evolved: cannot level further.")
	if not extras.is_empty():
		text += " " + " ".join(extras)
	return text


static func passive_description(def: PassiveDef, level: int) -> String:
	var lv: int = max(level, 1)
	var per := describe_effects(def.effects_at_level(lv))
	if per == "":
		return def.display_name + "."
	return "%s per level. Level %d: %s total." % [per, lv, describe_effects(_sum_effects(def.effects_for_level(lv)))]


static func _sum_effects(list: Array) -> Array:
	## Collapse repeated effects on the same stat/op into one for display.
	var acc: Dictionary = {}
	var order: Array = []
	for item in list:
		var e := item as Effect
		if e == null:
			continue
		var key := e.stat + "|" + e.op + "|" + e.target
		if not acc.has(key):
			acc[key] = Effect.make(e.stat, e.op, 0.0, e.target)
			order.append(key)
		if e.op == "mul":
			acc[key].value = (1.0 + acc[key].value) * (1.0 + e.value) - 1.0
		elif e.op == "set":
			acc[key].value = e.value
		else:
			acc[key].value += e.value
	var out: Array = []
	for k in order:
		out.append(acc[k])
	return out


static func next_level_text(def: ContentDef, level: int) -> String:
	var max_level := 8
	var eff: Array = []
	if def is WeaponDef:
		max_level = def.max_level
		if def.is_evolution:
			return "Evolved. Maxed."
		eff = def.effects_at_level(level + 1)
	elif def is PassiveDef:
		max_level = def.max_level
		eff = def.effects_at_level(level + 1)
	if level >= max_level:
		return "Maxed."
	var s := describe_effects(eff)
	return "Next level: " + (s if s != "" else "nothing new")


static func rarity_name(r: String) -> String:
	return RARITY_NAMES.get(r, r.capitalize())


static func quest_text(q: QuestDef) -> String:
	if q.quest_text != "":
		return q.quest_text
	var c := q.condition
	match str(c.get("type", "")):
		"kills_with_weapon":
			var w: WeaponDef = Registry.weapon(str(c.get("weapon", "")))
			return "Kill %d creatures with the %s." % [int(c.get("count", 0)), w.display_name if w else str(c.get("weapon", "")).capitalize()]
		"kills_of_enemy":
			return "Kill %s." % creature_count(str(c.get("enemy", "")), int(c.get("count", 0)))
		"reach_level":
			return "Reach level %d in one run." % int(c.get("level", 0))
		"survive_minutes":
			return "Survive %d minutes in one run." % int(c.get("minutes", 0))
		"survive_minutes_no_lift":
			return "Survive %d minutes without lifting your thumb." % int(c.get("minutes", 0))
		"open_chests":
			return "Open %d chests." % int(c.get("count", 0))
		"evolve_any":
			return "Evolve any weapon%s." % ("" if int(c.get("count", 1)) <= 1 else " %d times" % int(c.get("count", 1)))
		"extract_after_stage":
			return "Extract after stage %d on %s." % [int(c.get("stage", 1)), map_name(str(c.get("map", "")))]
		"kill_boss":
			return "Kill the stage %d boss on %s." % [int(c.get("stage", 1)), map_name(str(c.get("map", "")))]
		"kills_in_run_of_enemy":
			return "Kill %s in one run." % creature_count(str(c.get("enemy", "")), int(c.get("count", 0)))
		# pass 44: totals across runs, and a stage reached in one
		"kills_total":
			return "Kill %d creatures, all time." % int(c.get("count", 0))
		"runs_total":
			return "Play %d runs." % int(c.get("count", 0))
		"pickups_total":
			return "Pick up %d power-ups." % int(c.get("count", 0))
		"gold_total":
			return "Earn %d gold, all time." % int(c.get("count", 0))
		"reach_stage":
			return "Reach stage %d." % int(c.get("stage", 1))
	return "Complete a challenge."


## "the Dune Scorpion", "150 Goblins", "30 Spit Cactuses": the creature by its name, counted.
static func creature_count(id: String, n: int) -> String:
	var e: EnemyDef = Registry.enemy(id)
	var name: String = e.display_name if e else id.capitalize()
	if n <= 1:
		return "the " + name
	return "%d %s" % [n, name + ("es" if name.ends_with("s") or name.ends_with("x") else "s")]


static func map_name(id: String) -> String:
	var m: MapDef = Registry.map(id)
	return m.display_name if m else id.capitalize()


static func time_mmss(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]
