## Generates every piece of item text from data: effect lines, weapon descriptions,
## next-level previews, evolution status. Nothing in the UI is hand-written per item.
class_name TextGen
extends RefCounted

## stat -> kind. kind: "num" plain number, "pct" shown as percent when mul, "sec" seconds, "m" metres, "count" integer
## Pass 137 (lane W2-TEXTGEN): a stat's shown name is the row stat.<id>.name of content/strings/en.json (stat_name: every
## card, pause line, toast and plaque reads it there; TitleScreen.SHORT only shortens a few); a "hidden" stat has none.
## Pass 45: might is "attack damage", area "area of effect", greed "coin gain" (the ids stay).
const STATS := {
	"damage": "num", "cooldown": "sec", "amount": "count",
	"pierce": "count", "area": "pct", "speed": "num",
	"duration": "sec", "knockback": "num", "chains": "count",
	"range": "m", "spread_deg": "deg", "orbit_radius": "m",
	"max_hp": "num", "damage_reduction": "pct", "regen": "num",
	"move_speed": "num", "might": "pct", "projectile_speed": "pct",
	"magnet": "m", "luck": "pct", "greed": "pct", "revives": "count",
	"rerolls": "count", "skips": "count", "banishes": "count",
	"hp": "num", "size": "pct", "turn_rate": "num", "lifetime": "sec",
	"poison_damage": "num", "poison_stacks": "count", "poison_duration": "sec",
	"lifesteal": "pct", "fire_damage": "num", "fire_duration": "sec", "fire_spread": "pct",
	"crit_chance": "pct", "crit_damage": "pct", "execute_frac": "pct",
	"thorns": "num", "adrenaline_speed": "pct", "adrenaline_might": "pct",
	"overkill": "pct", "cooldown_on_kill": "sec", "xp_gain": "pct",
	"ricochet": "pct", "homing_turn": "pct", "haste": "pct",
	"evade": "pct", "evade_invuln": "sec", "shield_max": "num",
	"shield_delay": "sec", "shield_rate": "pct",
	"regen_delay": "sec", "lifesteal_cap": "pct",
	"heal_drop": "pct", "coin_drop": "pct",
	"brand_chance": "pct",
	# pass 46
	"desperado": "pct", "revive_hp": "pct",
	"hit_invuln": "sec",
	# pass 46, the weapons' own rows (WeaponInstance.stat_rows): the Guitarra's cone, the Spear's pin
	"cone_deg": "deg", "lift": "m", "pin": "sec", "plant": "sec",
	# pass 47, the new lines and passive items
	"freeze_chance": "pct", "crit_heal_chance": "pct",
	"gold_on_hit": "num",
	"debuff_duration": "pct", "difficulty": "pct",
	"still_regen": "num", "still_might": "pct",
	"barrel_speed": "pct", "barrel_seconds": "sec",
	"xp_drop_chance": "pct", "elite_damage": "pct",
	# pass 48, the new passive items
	"phoenix_revive": "count", "phoenix_hp": "hidden", "hurt_speed": "pct",
	"hurt_speed_seconds": "sec", "powder_keg_chance": "pct",
	"coin_on_hit": "pct", "gas_mask_cap": "pct",
	"kill_might": "pct",
	# pass 54, Solenne's stats and the Sun Scepter's own row (WeaponInstance.stat_rows)
	"buff_duration": "pct", "heal_mult": "pct", "radius": "m",
	# pass 62, the Pocket Watch
	"powerup_duration": "pct", "powerup_chance": "pct",
	# pass 69, the new passive items; "word": a stat said in words, never with its number (the Magnet's pulls come more
	# often a level, and Garry never wants their interval named), and left out of an item's totals (_sum_effects)
	"counter_damage": "pct", "counter_haste": "pct",
	"counter_speed": "pct", "counter_seconds": "sec",
	"heavyweight": "pct", "overheal": "pct",
	"heal_pulse": "num", "last_stand": "pct",
	"xp_pull_radius": "m", "xp_pull_rate": "word",
	# pass 70 (lane LINES), the new lines' evolutions; "rule": a stat said in its rule words (stat.<id>.rule) with its number inside
	"bronco_chance": "pct", "debuff_jump": "rule",
	"star_block_every": "rule", "gem_sweep_every": "rule",
	"vein_chance": "pct", "gold_might": "pct",
	# pass 88 (lane MIRROR), the Stakes (MirrorDanger; the Trail's Stakes nodes since pass 129); "hidden": a stat never written anywhere (Garry: the
	# coins and XP they pay more "we don't write that in the description")
	"danger_hp": "pct", "danger_attack": "pct", "danger_speed": "pct",
	"danger_bounty": "hidden", "boss_danger_hp": "pct",
	"boss_danger_attack": "pct", "boss_danger_speed": "pct",
	"boss_danger_bounty": "hidden",
	# pass 118 (lane ITEMS): the keys' per-chest stats (Run.chest_opened)
	"chest_luck": "pct", "chest_might": "pct",
	# pass 119 (lane LEGEND_B): the Grindstone's levels taken, each a level for the weakest weapon (Run._grindstone)
	"grind_levels": "count",
	# pass 119 (lane LEGEND_B): the four legendary items' rules, said in their rule words (stat.<id>.rule) with their number inside
	# (each level "set"s its number, so the Evolved card names the Evolved numbers)
	"crit_arcs": "rule", "crit_arc_pct": "rule",
	"crit_arc_stun": "rule", "grave_every": "rule", "grave_max": "rule",
	"grave_seconds": "rule", "grave_damage_pct": "rule",
	"purse_might_per": "rule", "purse_might_cap": "rule",
	"purse_hp_per": "rule", "purse_hp_cap": "rule",
	"hit_cap_pct": "rule", "boss_hit_cap_pct": "rule",
	"hit_block_every": "rule",
	# pass 119 (lane LEGEND_A): the Iron Horse's and Personal Storm's clocks, said in their rule words (stat.<id>.rule)
	"train_every": "rule", "train_cross": "rule",
	"storm_every": "rule", "storm_seconds": "rule",
	# pass 126 (lane ITEMS): the Assayer's Scale's pay for a spent skip (Run._pay_skip), the Canteen (Player._tick_canteen,
	# EnemyManager.damage); "word": water_walk is the rule itself, never a number
	"skip_coins": "num", "skip_xp": "pct",
	"water_walk": "word", "leave_water_regen": "num",
	"leave_water_seconds": "sec", "water_damage": "pct",
	# pass 129 (lane TRAILCORE): the Trail's own stats (Run.start, TotemBoons.boosted, BossChest.net)
	"start_gold": "num", "totem_boost": "pct",
	"boss_purse": "pct",
}
## A count stat's name for exactly one is its row stat.<id>.one when it has one (pass 118: _singular cuts only a last
## "s", and a name with its plural inside says its singular there; pass 119: the Grindstone's levels).
## The words of a "rule" stat (pass 70, lane LINES: the evolved lines' twists) are its row stat.<id>.rule, {n} its amount
## (pass 137); here the unit its number carries on a pause row or a change row: " s", "%", none, or a row's key whose
## text holds the number as {n} (gen.unit.gold, "{n} gold").
const RULE_UNIT := {
	"debuff_jump": "",
	"star_block_every": " s",
	"gem_sweep_every": " s",
	# pass 119 (lane LEGEND_B): Lightning in a Bottle, the Undertaker's Shovel, Fool's Gold, the Pocket Bible
	"crit_arcs": "",
	"crit_arc_pct": "%",
	"crit_arc_stun": " s",
	"grave_every": "",
	"grave_max": "",
	"grave_seconds": " s",
	"grave_damage_pct": "%",
	"purse_might_per": "gen.unit.gold",
	"purse_might_cap": "%",
	"purse_hp_per": "gen.unit.gold",
	"purse_hp_cap": "%",
	"hit_cap_pct": "%",
	"boss_hit_cap_pct": "%",
	"hit_block_every": " s",
	# pass 119 (lane LEGEND_A)
	"train_every": " s",
	"train_cross": "",
	"storm_every": " s",
	"storm_seconds": " s",
}
## Who a weapon with priority targeting goes for (pass 48: peashooter, revolver, tommy gun, tumbleweed, pike, sabre,
## turret, the Killer Bees and their evolutions), in its description. Pass 137: the description reads the row
## gen.weapon.who.priority; this copy is the old tests' reference (pass48_p0_test, pass137_loc_test).
const PRIORITY_WHO := "the strongest enemy nearby"
## The template a stat's amount sits in (pass 46: Desperado's bonus is a ceiling, "up to +12% attack damage as health
## falls" a level, +60% at level 5; pass 48: Gas Mask's is too, one point a poisoned enemy). Pass 137: a row's key.
const PREFIX := {"desperado": "gen.effect.up_to", "gas_mask_cap": "gen.effect.up_to"}

## The rarities' names are rows gen.rarity.<id> (pass 137; rarity_name).


static func stat_name(stat: String) -> String:
	var key := "stat.%s.name" % stat
	if Loc.has(key):
		return Loc.t(key)
	# a "hidden" stat (pass 88) has no name
	if STATS.has(stat):
		return ""
	return stat.replace("_", " ")


static func stat_kind(stat: String) -> String:
	if STATS.has(stat):
		return STATS[stat]
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
		"rule":
			return rule_amount(stat, _plain(v))
		_:
			if abs(v - round(v)) < 0.001:
				return str(int(round(v)))
			return "%.1f" % v


## A rule stat's number `n` (already written) with its unit (RULE_UNIT): "10 s", "25%", "3", "50 gold".
static func rule_amount(stat: String, n: String) -> String:
	var u := str(RULE_UNIT.get(stat, ""))
	if u.begins_with("gen.unit."):
		return Loc.t(u, {"n": n})
	return n + u


static func _signed(v: float, suffix: String = "") -> String:
	return ("+" if v >= 0.0 else "−") + _plain(absf(v)) + suffix


## A number with as few decimals as it needs, two at most (pass 47: Barrel Rush's +0.75 s read "+0.8 s", Mend's 0.45
## regen "+0.5").
static func _plain(a: float) -> String:
	if absf(a - roundf(a)) < 0.001:
		return str(int(roundf(a)))
	if absf(a * 10.0 - roundf(a * 10.0)) < 0.001:
		return "%.1f" % a
	return "%.2f" % a


static func describe_effect(e: Effect, with_name: bool = true) -> String:
	var name := stat_name(e.stat)
	var kind := stat_kind(e.stat)
	# a stat said in words (pass 69, "word": the Magnet's "pulls more often"): its name when it grows, nothing else
	if kind == "word":
		return name if e.value > 0.0 and with_name else ""
	# a hidden stat (pass 88): nothing at all
	if kind == "hidden":
		return ""
	# a rule (pass 70): its own words with the amount inside
	if kind == "rule":
		return rule_words(e.stat, e.value) if with_name else rule_amount(e.stat, _plain(e.value))
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
						out += " " + (name if n != 1 and n != -1 else singular_name(e.stat, name))
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
	if e.op != "set" and PREFIX.has(e.stat):
		out = Loc.t(str(PREFIX[e.stat]), {"effect": out})
	return out + _target_words(e.target)


## A count stat's name for exactly one (stat.<id>.one, else `name` without its last "s").
static func singular_name(stat: String, name: String) -> String:
	var key := "stat.%s.one" % stat
	return Loc.t(key) if Loc.has(key) else _singular(name)


## A "rule" stat in words (pass 70, lane LINES): its row stat.<id>.rule with `value` in it ("a star blocks a whole hit
## every 10 s"); the stat's name when it has no sentence.
static func rule_words(stat: String, value: float) -> String:
	var key := "stat.%s.rule" % stat
	if not Loc.has(key):
		return stat_name(stat)
	return Loc.t(key, {"n": _plain(value)})


## A weapon's name by its id (pass 49: an effect aimed at "weapon:hornet_nest", Pollen's buff, read "Hornet Nest", the
## id, after the weapon became the Killer Bees); the id in words when the Registry does not know it.
static func weapon_name(id: String) -> String:
	var reg := _registry()
	var w = reg.weapon(id) if reg else null
	return str(w.display_name) if w != null else id.capitalize()


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
			var s := describe_effect(e, with_name)
			# a "word" stat with nothing to say (pass 69) leaves no empty part
			if s != "":
				parts.append(s)
	return ", ".join(parts)


## The width of a cone wave in degrees (pass 46, the Guitarra): params.cone.deg, at least params.cone.min_deg (Far
## Reach's half circle, which never narrows the Requiem's full ring), widened by the weapon's area, 360 at most. ConeWave,
## its rows and its text all read it here.
static func cone_width(params: Dictionary, area: float = 1.0) -> float:
	var c = params.get("cone", {})
	var cone: Dictionary = c if c is Dictionary else {}
	var deg := maxf(float(cone.get("deg", 70.0)), float(cone.get("min_deg", 0.0)))
	return clampf(deg * maxf(area, 0.1), 5.0, 360.0)


## `params` are the weapon's as it is carried (WeaponInstance.params: its mutations' merged over its own); empty = the
## def's.
## "4th", "2nd", "11th" (pass 53: the Hellfire Battery's "every 4th volley").
## Pass 137: the number in its row gen.word.ordinal.<st|nd|rd|th> ("{n}st"); which row is English's rule, here.
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return Loc.t("gen.word.ordinal." + suffix, {"n": str(n)})


## Heartseeker's rule in words (pass 62, params.crit_stroke {every, reach_mult}): " Every 4th thrust is a guaranteed crit
## and reaches 20% further.", "" without it. A weapon that only sweeps (the Wide Sweep) counts sweeps; the Thunder Lance's
## crit is its thrust.
static func crit_stroke_words(params: Dictionary) -> String:
	var cs = params.get("crit_stroke")
	if not cs is Dictionary:
		return ""
	var every := maxi(int((cs as Dictionary).get("every", 4)), 1)
	var rm := float((cs as Dictionary).get("reach_mult", 1.0))
	var th = params.get("thrust", {})
	var td: Dictionary = th if th is Dictionary else {}
	var sweeps := float(td.get("slice_deg", 0.0)) > 0.0 and not bool(td.get("alternate", false))
	var vars := {"nth": ordinal(every), "pct": str(int(round((rm - 1.0) * 100.0)))}
	return " " + Loc.t("gen.weapon.crit_stroke.%s%s" % ["sweep" if sweeps else "thrust", "_reach" if rm > 1.001 else ""], vars)


## A Lobber's landing blast in words (pass 62, Sun Cocktail's params.land_blast {damage_frac, radius_frac, look}): " Each
## one bursts with sunlight as it lands: 12 damage within 1.8 m and a light shove.", "" without one.
static func land_blast_words(params: Dictionary, sheet: StatSheet) -> String:
	var lb = params.get("land_blast")
	if not lb is Dictionary or sheet == null:
		return ""
	var d: Dictionary = lb
	var r := sheet.get_stat("area", 2.5) * float(d.get("radius_frac", 0.9))
	var dmg := sheet.get_stat("damage", 0.0) * float(d.get("damage_frac", 1.0))
	var key := "gen.weapon.land_blast.sun" if str(d.get("look", "")) == "sun" else "gen.weapon.land_blast.plain"
	return " " + Loc.t(key, {"damage": "%.0f" % dmg, "radius": "%.1f" % r})


## The dynamite's fuse in words (pass 76, lane DYN, params.fuse {seconds}): " It lies where it lands and blows a second
## later." (" Each one ..." for a volley, " One that sticks to nothing ..." with Sticky), "" without a fuse.
static func fuse_words(pr: Dictionary, amount: int = 1) -> String:
	var fz = pr.get("fuse")
	if not fz is Dictionary:
		return ""
	var s := float((fz as Dictionary).get("seconds", 1.0))
	if s <= 0.0:
		return ""
	var when := Loc.t("gen.weapon.fuse.when_second") if absf(s - 1.0) < 0.01 else Loc.t("gen.weapon.fuse.when", {"seconds": _plain(s)})
	var who := "sticky" if pr.get("sticky") is Dictionary else ("it" if amount <= 1 else "each")
	return " " + Loc.t("gen.weapon.fuse." + who, {"when": when})


## The Drifter's Fire in the Hole in words (pass 76, lane DYN, params.mass_mini {min_hits}): " A blast that catches 9 or
## more enemies lands a Mini Crit on every one of them.", "" without it.
static func mass_mini_words(pr: Dictionary) -> String:
	var mm = pr.get("mass_mini")
	if not mm is Dictionary:
		return ""
	return " " + Loc.t("gen.weapon.mass_mini", {"hits": str(maxi(int((mm as Dictionary).get("min_hits", 9)), 1))})


## The basketball in words (pass 67, params.return_on_hit; its amount counts bounces with amount_mode "bounces"): "Throws
## a ball at the strongest enemy within 9 m: it bounces to 1 more enemy within 7 m, then flies back to his hand, hitting
## up to 2 on the way." (return_pierce 80 or more: "hitting everything on the way"), then its Heat (params.catch): "Every
## caught ball that scored adds Heat: +5% damage, up to +50%. A hit on him cools it." and Slam Dunk's dunk (catch.slam).
## A hop looks 7 m for its next creature unless ricochet_any.reach says otherwise (ProjectileManager.RICOCHET_REACH, not
## named here: TextGen compiles for tools before the autoloads exist).
## Alley-Oop's launch in words (pass 69, `params.launch {chance, fall_damage_frac}`): "" without one. The fall at 100%
## reads "the hit again", any other share as its percent of the hit.
static func launch_words(pr: Dictionary) -> String:
	var lc = pr.get("launch")
	if not lc is Dictionary:
		return ""
	var ch := int(round(float((lc as Dictionary).get("chance", 0.15)) * 100.0))
	var fr := float((lc as Dictionary).get("fall_damage_frac", 1.0))
	var again := Loc.t("gen.weapon.launch.again") if absf(fr - 1.0) < 0.01 else Loc.t("gen.weapon.launch.share", {"pct": str(int(round(fr * 100.0)))})
	return " " + Loc.t("gen.weapon.launch", {"pct": str(ch), "again": again})


## Pass 137 (lane W2-TEXTGEN): the ball's opening sentence, as the string table's key under gen.weapon.: "ball.bounces"
## (it bounces on to more enemies first) or "ball.back".
static func _ball_shape(sheet: StatSheet, pr: Dictionary) -> String:
	var ra = pr.get("ricochet_any", {})
	var hops := maxi(int((ra as Dictionary).get("count", 0)), 0) if ra is Dictionary else 0
	if str(pr.get("amount_mode", "")) == "bounces":
		hops += maxi(sheet.get_int("amount", 1), 1) - 1
	return "ball.bounces" if hops > 0 else "ball.back"


## Pass 137 (lane W2-TEXTGEN): an item's own description row (weapon.<id>.desc, evolution.<id>.desc) when its sentence is
## the shape it comes with (`shape` = `home`), else "" (Loc.t_first then takes the shape's generic row): the pilot's rule
## for the guns (_pe_shape), for every behaviour.
static func _own_key(def: WeaponDef, shape: String, home: String) -> String:
	if shape != home:
		return ""
	return ("evolution.%s.desc" if def.is_evolution else "weapon.%s.desc") % def.id


static func ball_words(def: WeaponDef, sheet: StatSheet, pr: Dictionary) -> String:
	var who := Loc.t("gen.weapon.ball.who_priority") if def.targeting == "priority" else Loc.t("gen.weapon.who.nearest")
	var ra = pr.get("ricochet_any", {})
	var rd: Dictionary = ra if ra is Dictionary else {}
	var hops := maxi(int(rd.get("count", 0)), 0)
	if str(pr.get("amount_mode", "")) == "bounces":
		hops += maxi(sheet.get_int("amount", 1), 1) - 1
	var rp := int(pr.get("return_pierce", 80))
	var way := (", " + Loc.t("gen.weapon.ball.way_all")) if rp >= 80 else ((", " + Loc.t("gen.weapon.ball.way_some", {"n": str(rp)})) if rp > 0 else "")
	var vars := {"who": who, "range": "%.0f" % sheet.get_stat("range", 8.0), "hops": str(hops), "reach": "%.0f" % float(rd.get("reach", 7.0)), "way": way}
	var shape := _ball_shape(sheet, pr)
	var text := Loc.t_first([_own_key(def, shape, _ball_shape(sheet, _home_params(def))), "gen.weapon." + shape], vars)
	# pass 69: Alley-Oop's launch (Slam Dunk's, amplified)
	text += launch_words(pr)
	var ct = pr.get("catch")
	if not ct is Dictionary:
		return text
	var c: Dictionary = ct
	var per := float(c.get("heat_per", 0.0))
	var top := int(c.get("heat_max", 10))
	if per > 0.0 and top > 0:
		text += " " + Loc.t("gen.weapon.ball.heat", {"pct": str(int(round(per * 100.0))), "top": str(int(round(per * float(top) * 100.0)))})
		text += " " + Loc.t("gen.weapon.ball.heat_keep" if bool(c.get("heat_keep", false)) else "gen.weapon.ball.heat_cools")
	var sl = c.get("slam")
	if sl is Dictionary:
		var at := int((sl as Dictionary).get("at_heat", top))
		var at_words := Loc.t("gen.weapon.ball.at_full") if at >= top else Loc.t("gen.weapon.ball.at_heat", {"heat": str(at)})
		text += " " + Loc.t("gen.weapon.ball.slam", {"at": at_words, "pct": str(int(round(float((sl as Dictionary).get("damage_frac", 1.0)) * 100.0))),
			"radius": "%.1f" % float((sl as Dictionary).get("radius", 3.5))})
	return text


## The Dragon's Breath in words (pass 95, lane BREATH; core/behaviors/FireBreath.gd): the cone, how long and how often
## it breathes (the amount's seconds in), what a second in it costs, then what the path adds (Backdraft's shove, Held
## Breath's held breath). The burn's line comes with the fire extras after it.
static func breath_words(sheet: StatSheet, pr: Dictionary, def: WeaponDef = null) -> String:
	var b = pr.get("breath", {})
	var bd: Dictionary = b if b is Dictionary else {}
	var amount := maxi(sheet.get_int("amount", 1), 1)
	var secs: float = clampf(sheet.get_stat("duration", 2.0) + float(amount - 1) * float(bd.get("seconds_per_amount", 1.0)), 0.1, maxf(float(bd.get("max_seconds", 6.0)), 0.1))
	var tick: float = maxf(float(bd.get("tick", 1.0)), 0.1)
	var each_second := absf(tick - 1.0) < 0.01
	var vars := {"deg": str(int(round(_breath_deg(sheet, pr)))), "range": "%.0f" % sheet.get_stat("range", 5.0), "seconds": "%.1f" % secs,
		"cooldown": "%.1f" % sheet.get_stat("cooldown", 10.0), "damage": str(int(round(sheet.get_stat("damage", 12.0)))),
		"every": Loc.t("gen.weapon.breath.every_second") if each_second else Loc.t("gen.weapon.breath.every_tick", {"tick": "%.1f" % tick})}
	var shape := _breath_shape(sheet, pr)
	var own := _own_key(def, shape, _breath_shape(sheet, _home_params(def))) if def != null else ""
	var text := Loc.t_first([own, "gen.weapon." + shape], vars)
	if float(bd.get("seconds_per_amount", 1.0)) > 0.0:
		text += " " + Loc.t("gen.weapon.breath.extra", {"seconds": _plain(float(bd.get("seconds_per_amount", 1.0)))})
	if float(bd.get("knock", 0.0)) > 0.0:
		text += " " + Loc.t("gen.weapon.breath.shove_second" if each_second else "gen.weapon.breath.shove_hit")
	var st = bd.get("still")
	if st is Dictionary:
		var sd: Dictionary = st
		text += " " + Loc.t("gen.weapon.breath.still_ring" if bool(sd.get("ring", true)) else "gen.weapon.breath.still", {
			"seconds": _plain(float(sd.get("seconds", 2.0))), "long": _plain(float(sd.get("duration_mult", 2.0))), "hits": _plain(float(sd.get("damage_mult", 1.5)))})
	return text


## The breath's cone in degrees now (pass 95): breath.cone_deg x the area stat, 15 at least, 360 at most.
static func _breath_deg(sheet: StatSheet, pr: Dictionary) -> float:
	var b = pr.get("breath", {})
	var bd: Dictionary = b if b is Dictionary else {}
	return clampf(float(bd.get("cone_deg", 50.0)) * sheet.get_stat("area", 1.0), 15.0, 360.0)


## Pass 137: the breath's opening sentence under gen.weapon.: "breath.ring" (a full ring) or "breath.cone".
static func _breath_shape(sheet: StatSheet, pr: Dictionary) -> String:
	return "breath.ring" if _breath_deg(sheet, pr) >= 359.0 else "breath.cone"


## The Frisbee in words (pass 69, lane FRIS; core/behaviors/Frisbee.gd): its throw, its curve, its drop-off and floor,
## then what its path adds (Carry's ride, Trick Shot's share, a stun, the Flying Saucer's loop).
static func frisbee_words(sheet: StatSheet, pr: Dictionary, def: WeaponDef = null) -> String:
	var amount := maxi(sheet.get_int("amount", 1), 1)
	var range_m := sheet.get_stat("range", 12.0)
	var fo = pr.get("falloff", {})
	var fd: Dictionary = fo if fo is Dictionary else {}
	var less := int(round((1.0 - clampf(float(fd.get("step", 0.85)), 0.0, 1.0)) * 100.0))
	var flo := int(round(clampf(float(fd.get("floor", 0.25)), 0.0, 1.0) * 100.0))
	var vars := {"amount": str(amount), "range": "%.0f" % range_m, "less": str(less), "floor": str(flo)}
	var text := Loc.t_first([_own_key(def, "frisbee", "frisbee") if def != null else "", "gen.weapon.frisbee"], vars)
	var cr = pr.get("carry")
	if cr is Dictionary and float((cr as Dictionary).get("chance", 0.0)) > 0.0:
		text += " " + Loc.t("gen.weapon.frisbee.carry_drop" if float((cr as Dictionary).get("drop_hit", 0.0)) > 0.0 else "gen.weapon.frisbee.carry",
			{"pct": str(int(round(float((cr as Dictionary).get("chance", 0.0)) * 100.0)))})
	var pm := float(pr.get("proc_mult", 1.0))
	if pm > 1.001:
		text += " " + Loc.t("gen.weapon.frisbee.procs", {"pct": str(int(round((pm - 1.0) * 100.0)))})
	var st = pr.get("stun")
	if st is Dictionary and float((st as Dictionary).get("chance", 0.0)) > 0.0:
		text += " " + Loc.t("gen.weapon.stun_chance", {"pct": str(int(round(float((st as Dictionary).get("chance", 0.0)) * maxf(pm, 1.0) * 100.0))),
			"seconds": "%.1f" % float((st as Dictionary).get("seconds", 1.0))})
	if pr.get("loop") is Dictionary:
		text += " " + Loc.t("gen.weapon.frisbee.loop")
	return text


static func weapon_description(def: WeaponDef, sheet: StatSheet, params: Dictionary = {}) -> String:
	var amount := sheet.get_int("amount", 1)
	var range_m := sheet.get_stat("range", 8.0)
	var pr: Dictionary = params if not params.is_empty() else def.params
	var text := ""
	var behavior := def.behavior
	# priority targeting (pass 48, EnemyManager.priority_index): the strong and the close before the merely close
	var who := Loc.t("gen.weapon.who.priority") if def.targeting == "priority" else Loc.t("gen.weapon.who.nearest")
	# the Spear (pass 46) is thrown like any shot, and reads as what it is
	if behavior == "ProjectileEmitter" and pr.has("plant"):
		behavior = "Spear"
	match behavior:
		"Spear":
			# through everything in its way, and it stands in the sand where it comes down
			text = Loc.t_first([_own_key(def, "spear", "spear"), "gen.weapon.spear"], {"amount": str(amount), "who": who, "range": "%.0f" % range_m})
			var pin = pr.get("pin")
			if pin is Dictionary:
				text += " " + Loc.t("gen.weapon.spear.pin", {"seconds": "%.1f" % float((pin as Dictionary).get("seconds", 1.2))})
			var tz = pr.get("trail_zone")
			if tz is Dictionary:
				text += " " + Loc.t("gen.weapon.spear.dust")
		"ProjectileEmitter":
			# pass 137 (lane LOCKIT, the string table's pilot): the sentence is a row of content/strings/en.json, the
			# weapon's own (weapon.<id>.desc / evolution.<id>.desc) when the shape is the one it comes with, else the
			# shape's generic one (gen.weapon.shot.* / gen.weapon.blast.*), so a new weapon folder still has words
			var vars := {"amount": str(amount), "range": "%.0f" % range_m, "who": who}
			var shape := _pe_shape(def, sheet, pr)
			match shape:
				"shot.forward":
					vars["cone"] = str(int(round(sheet.get_stat("spread_deg", 30.0))))
				"blast.lane":
					var bll: Dictionary = pr["blast"]
					vars["width"] = "%.1f" % float(bll.get("width", 2.6))
					vars["length"] = "%.0f" % (range_m * float(bll.get("length_mult", 1.25)))
				"blast.cone":
					var blc: Dictionary = pr["blast"]
					vars["deg"] = str(int(round(float(blc.get("deg", 75.0)))))
					vars["depth"] = "%.0f" % float(blc.get("range", range_m))
			# pass 67 (the basketball, params.return_on_hit): one ball that bounces on and flies back to his hand (pass
			# 137: its own words, ball_words, in place of a shot's)
			var ball := bool(pr.get("return_on_hit", false))
			if ball:
				text = ball_words(def, sheet, pr)
			else:
				text = Loc.t_first([_own_key(def, shape, _pe_shape(def, sheet, _home_params(def))), "gen.weapon." + shape], vars)
			var de := int(pr.get("double_every", 0))
			if de >= 2:
				var nth := Loc.t("gen.word.nth.%d" % de) if Loc.has("gen.word.nth.%d" % de) else Loc.t("gen.word.nth.n", {"n": str(de)})
				text += " " + Loc.t("gen.weapon.double_every", {"nth": nth})
			var hs = pr.get("hip_shot")
			if hs is Dictionary:
				text += " " + Loc.t("gen.weapon.hip_shot", {"nth": ordinal(int((hs as Dictionary).get("every", 5))), "volleys": str(int((hs as Dictionary).get("volleys", 3)))})
			var rav = pr.get("ricochet_any")
			if rav is Dictionary and not ball:
				var ra := int((rav as Dictionary).get("count", 0))
				if ra > 0:
					text += " " + Loc.t("gen.weapon.ricochet", {"count": str(ra), "pct": str(int(round(float((rav as Dictionary).get("frac", 1.0)) * 100.0)))})
			var mc := float(pr.get("mini_crit", 0.0))
			if mc > 0.0:
				text += " " + Loc.t("gen.weapon.mini_crit", {"pct": str(int(round(mc * 100.0)))})
		"Orbiter":
			text = Loc.t_first([_own_key(def, "orbit", "orbit"), "gen.weapon.orbit"], {"amount": str(amount), "radius": "%.1f" % sheet.get_stat("orbit_radius", 2.0)})
		"Lobber":
			# pass 76 (lane LOOKS): the thing lobbed in the look's words (thing_word: "sticks"), else the sentence's own
			# (pass 137: gen.noun.*); the sentence by what it carries (_lob_shape: lob.fire, lob.poison, lob.blast)
			var lob := _lob_shape(sheet)
			var thing := {"lob.fire": ["bottle", "bottles"], "lob.poison": ["bomb", "bombs"]}.get(lob, ["grenade", "grenades"]) as Array
			var lvars := {"amount": str(amount), "area": "%.1f" % sheet.get_stat("area", 2.5),
				"thing": thing_word(def, amount, Loc.t("gen.weapon.noun." + str(thing[0])), Loc.t("gen.weapon.noun." + str(thing[1])))}
			text = Loc.t_first([_own_key(def, lob, _lob_shape(sheet)), "gen.weapon." + lob], lvars)
			# pass 62, Sun Cocktail (params.land_blast): a small blast where each one lands
			text += land_blast_words(pr, sheet)
			# pass 76 (lane DYN): the dynamite's fuse and the Drifter's mass mini crits
			text += fuse_words(pr, amount) + mass_mini_words(pr)
		"Beam":
			text = Loc.t_first([_own_key(def, "zap", "zap"), "gen.weapon.zap"], {"range": "%.0f" % range_m, "chains": str(sheet.get_int("chains", 2))})
		"Thruster":
			var th = pr.get("thrust", {})
			var slice_deg: float = float(th.get("slice_deg", 0.0)) if th is Dictionary else 0.0
			# pass 53: the Spear's sweep swings every blade in one stroke ("blades"), the Thunder Lance alternates a sweep and
			# a throwing thrust, Stunning Thrust stuns, the Whirlwind's crits refund the stroke, the stunned take more.
			# Pass 137: the sentence by _thrust_shape (thrust.sweep: blades sweeping together, thrust.slice: swings a
			# stroke, thrust.thrust)
			var tshape := _thrust_shape(pr)
			text = Loc.t_first([_own_key(def, tshape, _thrust_shape(_home_params(def))), "gen.weapon." + tshape],
				{"amount": str(amount), "deg": str(int(slice_deg)), "who": who, "range": "%.1f" % range_m})
			if slice_deg > 0.0 and th is Dictionary and bool(th.get("alternate", false)):
				text += " " + Loc.t("gen.weapon.thrust.alternate")
			var st = th.get("stun") if th is Dictionary else null
			if st is Dictionary:
				var sc := float((st as Dictionary).get("chance", 0.0))
				var ss := "%.1f" % float((st as Dictionary).get("seconds", 1.0))
				text += " " + (Loc.t("gen.weapon.stun_always", {"seconds": ss}) if sc >= 1.0 else Loc.t("gen.weapon.stun_chance", {"pct": str(int(round(sc * 100.0))), "seconds": ss}))
			if float(pr.get("crit_refund", 0.0)) > 0.0:
				text += " " + Loc.t("gen.weapon.thrust.crit_refund", {"pct": str(int(round(float(pr.get("crit_refund", 0.0)) * 100.0)))})
			if float(pr.get("stunned_mult", 1.0)) > 1.0:
				text += " " + Loc.t("gen.weapon.thrust.stunned_mult", {"mult": "%.1f" % float(pr.get("stunned_mult", 1.0))})
			# pass 62, Heartseeker (params.crit_stroke): every Nth stroke a guaranteed crit with a longer reach
			text += crit_stroke_words(pr)
		"Smasher":
			var sm = pr.get("smash", {})
			var blast: float = (float(sm.get("radius", 1.6)) if sm is Dictionary else 1.6) * sheet.get_stat("area", 1.0)
			text = Loc.t_first([_own_key(def, "smash", "smash"), "gen.weapon.smash"], {"amount": str(amount), "range": "%.1f" % range_m, "blast": "%.1f" % blast})
			# pass 48: the Earthshaker's cracks carry lightning and a second wave, and it always crushes big game (pass
			# 137: one sentence a mix, "gen.weapon.smash.quake", "gen.weapon.smash.quake_zap", "gen.weapon.smash.quake_roll",
			# "gen.weapon.smash.quake_zap_roll")
			var qk = (sm as Dictionary).get("quake") if sm is Dictionary else null
			if qk is Dictionary:
				var qkey := "gen.weapon.smash.quake"
				if (qk as Dictionary).get("zap") is Dictionary:
					qkey += "_zap"
				if (qk as Dictionary).get("roll") is Dictionary:
					qkey += "_roll"
				text += " " + Loc.t(qkey, {"lines": str(int((qk as Dictionary).get("lines", 4)))})
			var gs = pr.get("giant_slayer")
			if gs is Dictionary and bool((gs as Dictionary).get("always", false)):
				text += " " + Loc.t("gen.weapon.smash.giant_slayer", {"mult": _plain(float((gs as Dictionary).get("mult", 2.5)))})
		"MineLayer":
			# pass 48: the Land Mine had no sentence ("Land Mine."); pass 137: the sentence by _mine_shape
			var jr = pr.get("jackrabbit")
			var spring = pr.get("spring")
			var sense := 0.0
			if jr is Dictionary:
				sense = float((jr as Dictionary).get("sense", 6.0))
			elif spring is Dictionary:
				sense = float((spring as Dictionary).get("sense", 3.5))
			var mshape := _mine_shape(pr)
			text = Loc.t_first([_own_key(def, mshape, _mine_shape(_home_params(def))), "gen.weapon." + mshape], {"amount": str(amount),
				"cooldown": "%.1f" % sheet.get_stat("cooldown", 2.0), "area": "%.1f" % sheet.get_stat("area", 2.2),
				"sense": ("%.0f" % sense) if mshape == "mine.jackrabbit" else ("%.1f" % sense)})
		"GravityGun":
			var gv = pr.get("gravity", {})
			var gd: Dictionary = gv if gv is Dictionary else {}
			var gshape := "gravity.hole" if gd.get("black_hole") is Dictionary else "gravity.throw"
			var gv0 = _home_params(def).get("gravity", {})
			var ghome := "gravity.hole" if gv0 is Dictionary and (gv0 as Dictionary).get("black_hole") is Dictionary else "gravity.throw"
			# the throw: the blast the landing makes, Repulsor's 40% wider one too (area_radius, pass 58: the card's change
			# row reads the same number)
			var gvars := {"amount": str(amount), "range": "%.0f" % range_m}
			if gshape == "gravity.throw":
				gvars["blast"] = "%.1f" % float(area_radius(def, sheet, pr)[1])
			text = Loc.t_first([_own_key(def, gshape, ghome), "gen.weapon." + gshape], gvars)
		"Spawner":
			var cap: int = int(round(float(pr.get("max_turrets", 6)) * float(pr.get("max_turrets_mult", 1.0))))
			var life := sheet.get_stat("lifetime", 12.0)
			# the Turret Family's never go (a lifetime of 9999)
			var stays := Loc.t("gen.weapon.spawn.stays", {"who": who}) if life >= 999.0 else Loc.t("gen.weapon.spawn.shoots_for", {"who": who, "seconds": "%.0f" % life})
			text = Loc.t_first([_own_key(def, "spawn", "spawn"), "gen.weapon.spawn"], {"amount": str(maxi(amount, 1)),
				"cooldown": "%.1f" % sheet.get_stat("cooldown", 6.0), "cap": str(cap), "stays": stays})
		"MissilePod":
			# a pod that circles the hero: rockets with a blast, or seekers that sting and fizzle (the bees of the Killer
			# Bees' hive and its evolutions, pass 49: they read as bees, not seekers)
			var blast_m := sheet.get_stat("area", 0.0)
			var prey := Loc.t("gen.weapon.who.priority") if def.targeting == "priority" else Loc.t("gen.weapon.who.enemies")
			# pass 137: rockets (pod.rockets) or bees (pod.bees), by the blast
			var pshape := "pod.rockets" if blast_m > 0.3 else "pod.bees"
			var phome := "pod.rockets" if float(def.base.get("area", 0.0)) > 0.3 else "pod.bees"
			text = Loc.t_first([_own_key(def, pshape, phome), "gen.weapon." + pshape], {"amount": str(amount), "prey": prey, "range": "%.0f" % range_m,
				"blast": "%.1f" % blast_m})
			if blast_m > 0.3:
				# pass 53: Cluster Munitions and Pressure Cooker, and the Hellfire Battery that carries both
				var cl = pr.get("cluster")
				if cl is Dictionary:
					var cc := float((cl as Dictionary).get("chance", 0.3))
					# rows "gen.weapon.pod.cluster_all", "gen.weapon.pod.cluster_all_chain", "gen.weapon.pod.cluster", "gen.weapon.pod.cluster_chain"
					var ckey := "gen.weapon.pod.cluster_all" if cc >= 1.0 else "gen.weapon.pod.cluster"
					if bool((cl as Dictionary).get("chain", false)):
						ckey += "_chain"
					text += " " + Loc.t(ckey, {"count": str(int((cl as Dictionary).get("count", 5))), "chance": str(int(round(cc * 100.0))),
						"pct": str(int(round(float((cl as Dictionary).get("damage_frac", 0.25)) * 100.0)))})
				var ps = pr.get("pressure")
				if ps is Dictionary:
					# pass 60 (lane WP): the pressure is built by standing still (MissilePod._tick_pressure), moving lets it
					# all out and a hit vents `hit_vent` of it (half without the key)
					var vent := clampf(float((ps as Dictionary).get("hit_vent", 0.5)), 0.0, 1.0)
					var vent_s := Loc.t("gen.weapon.pod.vent_half") if absf(vent - 0.5) < 0.01 else (Loc.t("gen.weapon.pod.vent_all") if vent >= 0.999 else "%d%%" % int(round(vent * 100.0)))
					text += " " + Loc.t("gen.weapon.pod.pressure", {"pct": str(int(round(float((ps as Dictionary).get("max", 2.0)) * 100.0))),
						"seconds": "%.0f" % float((ps as Dictionary).get("seconds", 15.0)), "vent": vent_s})
				var op = pr.get("overpressure")
				if op is Dictionary:
					text += " " + Loc.t("gen.weapon.pod.overpressure", {"nth": ordinal(int((op as Dictionary).get("every", 4)))})
		"LaserBeam":
			text = Loc.t_first([_own_key(def, "laser", "laser"), "gen.weapon.laser"], {"range": "%.0f" % range_m, "seconds": "%.1f" % sheet.get_stat("duration", 2.0)})
		"ConeWave":
			# the Guitarra (pass 46): a cone of melody that lifts what stands in it and sets it down where it stood (pass
			# 137: cone.ring for a full ring, else cone.cone)
			var cone = pr.get("cone", {})
			var cd: Dictionary = cone if cone is Dictionary else {}
			var deg := cone_width(pr, sheet.get_stat("area", 1.0))
			var cshape := "cone.ring" if deg >= 359.0 else "cone.cone"
			var chome := "cone.ring" if cone_width(_home_params(def), sheet.get_stat("area", 1.0)) >= 359.0 else "cone.cone"
			text = Loc.t_first([_own_key(def, cshape, chome), "gen.weapon." + cshape], {"deg": str(int(round(deg))), "range": "%.1f" % range_m,
				"lift": "%.1f" % float(cd.get("lift", 0.6))})
			if bool(cd.get("side_random", false)):
				text += " " + Loc.t("gen.weapon.cone.slap")
			if amount > 1:
				text += " " + Loc.t("gen.weapon.cone.echoes", {"echoes": str(amount - 1)})
		"SunScepter":
			# the Sun Scepter (pass 54): pillars of sunlight on what she can see, the close likelier; Zenith's sweep; Gold Dust
			var sun = pr.get("sun", {})
			var sr: float = (float((sun as Dictionary).get("radius", 1.3)) if sun is Dictionary else 1.3) * sheet.get_stat("area", 1.0)
			text = Loc.t_first([_own_key(def, "sun", "sun"), "gen.weapon.sun"], {"cooldown": "%.1f" % sheet.get_stat("cooldown", 1.1),
				"damage": str(int(round(sheet.get_stat("damage", 14.0)))), "radius": "%.1f" % sr})
			if amount > 1:
				text += " " + Loc.t("gen.weapon.sun.pillars", {"amount": str(amount)})
			var zn = pr.get("zenith")
			if zn is Dictionary:
				text += " " + Loc.t("gen.weapon.sun.zenith", {"nth": ordinal(int((zn as Dictionary).get("every", 10))), "pct": str(int(round(float((zn as Dictionary).get("frac", 0.8)) * 100.0)))})
			var gd = pr.get("gold_dust")
			if gd is Dictionary:
				text += " " + Loc.t("gen.weapon.sun.gold_dust", {"pct": str(int(round(float((gd as Dictionary).get("chance", 0.3)) * 100.0)))})
		"Frisbee":
			# pass 69 (lane FRIS): the Frisbee, frisbee_words
			text = frisbee_words(sheet, pr, def)
		"SaltShaker":
			# pass 69 (lane SALT): patches of salt in the hero's wake
			text = salt_words(sheet, pr, def)
		"FireBreath":
			# pass 95 (lane BREATH): the Dragon's Breath, breath_words
			text = breath_words(sheet, pr, def)
		_:
			text = Loc.t("gen.item.name_only", {"name": def.display_name})
	var extras: Array = []
	var pd := sheet.get_stat("poison_damage", 0.0)
	if pd > 0.0:
		var st := maxi(sheet.get_int("poison_stacks", 1), 1)
		extras.append(Loc.t("gen.weapon.poisons_stacks" if st > 1 else "gen.weapon.poisons", {"damage": "%.0f" % (pd * st),
			"seconds": "%.0f" % sheet.get_stat("poison_duration", 10.0), "stacks": str(st)}))
	var fd := sheet.get_stat("fire_damage", 0.0)
	if fd > 0.0:
		# only some of what it hits, when the weapon says so (pass 51: Dragon's Breath's 60%)
		var ic := clampf(float(pr.get("ignite_chance", 1.0)), 0.0, 1.0)
		extras.append(Loc.t("gen.weapon.burns" if ic >= 1.0 else "gen.weapon.burns_some", {"pct": str(int(round(ic * 100.0))), "damage": "%.0f" % fd,
			"seconds": "%.1f" % sheet.get_stat("fire_duration", 1.8), "spread": str(int(round(sheet.get_stat("fire_spread", 0.5) * 100.0)))}))
	var pierce := sheet.get_int("pierce", 0)
	# pass 62: the pierce drop-off, while Settings.pierce_falloff is on, says how the pierce hits ("Pierces 2: the first
	# enemy takes ...")
	var pfw := pierce_falloff_words(pr, behavior, pierce)
	if pierce > 0 and behavior == "ProjectileEmitter" and pfw == "":
		extras.append(Loc.t("gen.weapon.pierces", {"pierce": str(pierce)}))
	if pfw != "":
		extras.append(pfw)
	if sheet.get_stat("knockback", 0.0) > 0.0:
		extras.append(Loc.t("gen.weapon.knocks_back"))
	if def.hero != "":
		# pass 118 (lane ITEMS): anyone may find it now; the card still says whose own it is
		var reg := _registry()
		var owner = reg.character(def.hero) if reg else null
		extras.append(Loc.t("gen.weapon.outlaws_own", {"who": str(owner.display_name) if owner else def.hero.capitalize()}))
	if def.is_evolution:
		extras.append(Loc.t("gen.weapon.evolved"))
	if not extras.is_empty():
		text += " " + " ".join(extras)
	return text


## Pass 137 (lane LOCKIT): which sentence a ProjectileEmitter's description opens with, as the string table's key under
## gen.weapon.: "shot.forward", "shot.random", "shot.flare", "shot.dart", "shot.priority", "shot.nearest", or a blast
## ("blast.lane", "blast.cone") that replaces the flying shots. The basketball's words are ball_words.
static func _pe_shape(def: WeaponDef, sheet: StatSheet, pr: Dictionary) -> String:
	var bl = pr.get("blast")
	if bl is Dictionary:
		var sh := str((bl as Dictionary).get("shape", ""))
		if sh == "lane":
			return "blast.lane"
		if sh == "cone":
			return "blast.cone"
	match def.targeting:
		"forward":
			return "shot.forward"
		"random":
			return "shot.random"
		"healthy":
			return "shot.flare" if sheet.get_stat("fire_damage", 0.0) > 0.0 else "shot.dart"
		"priority":
			return "shot.priority"
	return "shot.nearest"


## A weapon's params as it comes (no mutation): its own with its `final` block over them (WeaponInstance.fold_params with
## no mutation), for _pe_shape's "the shape it comes with".
static func _home_params(def: WeaponDef) -> Dictionary:
	var fin = def.params.get("final")
	return WeaponInstance.merge_params(def.params, fin) if fin is Dictionary else def.params


## Pass 137 (lane W2-TEXTGEN): a Lobber's sentence under gen.weapon. by what it carries: "lob.fire", "lob.poison", "lob.blast".
static func _lob_shape(sheet: StatSheet) -> String:
	if sheet.get_stat("fire_damage", 0.0) > 0.0:
		return "lob.fire"
	if sheet.get_stat("poison_damage", 0.0) > 0.0:
		return "lob.poison"
	return "lob.blast"


## Pass 137: a Thruster's sentence under gen.weapon.: "thrust.sweep" (a slice whose blades sweep together, amount_mode
## "blades"), "thrust.slice" (a slice swung `amount` times a stroke) or "thrust.thrust".
static func _thrust_shape(pr: Dictionary) -> String:
	var th = pr.get("thrust", {})
	if not th is Dictionary or float((th as Dictionary).get("slice_deg", 0.0)) <= 0.0:
		return "thrust.thrust"
	return "thrust.sweep" if str((th as Dictionary).get("amount_mode", "")) == "blades" else "thrust.slice"


## Pass 137 (lane W2-TEXTGEN): the key under gen.weapon. of the sentence weapon `def` opens with as it comes (level 1, its
## own params, no hero's stats): the row its own weapon.<id>.desc / evolution.<id>.desc was copied from ("" for a
## behaviour without one). The tests and the lane's probe read it; weapon_description decides the same way inline.
static func home_shape(def: WeaponDef) -> String:
	if def == null:
		return ""
	var inst := WeaponInstance.new(def, 1)
	inst.rebuild(StatSheet.new(), [inst])
	var sheet := inst.sheet
	var pr := _home_params(def)
	var b := def.behavior
	if b == "ProjectileEmitter" and pr.has("plant"):
		return "spear"
	match b:
		"ProjectileEmitter":
			return _ball_shape(sheet, pr) if bool(pr.get("return_on_hit", false)) else _pe_shape(def, sheet, pr)
		"Orbiter":
			return "orbit"
		"Lobber":
			return _lob_shape(sheet)
		"Beam":
			return "zap"
		"Thruster":
			return _thrust_shape(pr)
		"Smasher":
			return "smash"
		"MineLayer":
			return _mine_shape(pr)
		"GravityGun":
			var gv = pr.get("gravity", {})
			return "gravity.hole" if gv is Dictionary and (gv as Dictionary).get("black_hole") is Dictionary else "gravity.throw"
		"Spawner":
			return "spawn"
		"MissilePod":
			return "pod.rockets" if float(def.base.get("area", 0.0)) > 0.3 else "pod.bees"
		"LaserBeam":
			return "laser"
		"ConeWave":
			return "cone.ring" if cone_width(pr, sheet.get_stat("area", 1.0)) >= 359.0 else "cone.cone"
		"SunScepter":
			return "sun"
		"Frisbee":
			return "frisbee"
		"SaltShaker":
			return "salt"
		"FireBreath":
			return _breath_shape(sheet, pr)
	return ""


## Pass 137: a MineLayer's sentence under gen.weapon.: "mine.jackrabbit", "mine.spring" or "mine.step".
static func _mine_shape(pr: Dictionary) -> String:
	if pr.get("jackrabbit") is Dictionary:
		return "mine.jackrabbit"
	if pr.get("spring") is Dictionary:
		return "mine.spring"
	return "mine.step"


## The pierce drop-off in words (pass 62, params.pierce_falloff {step, floor, first_mult}; ProjectileManager.falloff_factor
## does the sums): "" when the weapon has none, when it cannot pierce (a shot with pierce 0, a Spear that only sweeps)
## or while Settings.pierce_falloff is off. `behavior` is the description's (the thrown spear reads "Spear").
static func pierce_falloff_words(pr: Dictionary, behavior: String, pierce: int) -> String:
	var pf = pr.get("pierce_falloff")
	if not pf is Dictionary or not pierce_falloff_on():
		return ""
	var less := int(round((1.0 - clampf(float((pf as Dictionary).get("step", 0.8)), 0.0, 1.0)) * 100.0))
	var more := int(round((float((pf as Dictionary).get("first_mult", 1.0)) - 1.0) * 100.0))
	# how it opens and where the rest are met, in this weapon's words ("Pierces 2: the first enemy takes 15% more, each
	# one after it 20% less than the one before."). Pass 137: one row a way (gen.pierce.<how>[_more]), the opening
	# (gen.pierce.lead_*) its own row before it
	var lead := ""
	var how := "shot"
	match behavior:
		"Thruster":
			var th = pr.get("thrust", {})
			var td: Dictionary = th if th is Dictionary else {}
			if float(td.get("slice_deg", 0.0)) > 0.0 and not bool(td.get("alternate", false)):
				return ""
			how = "thrust"
		"ProjectileEmitter", "Spear":
			if pierce <= 0:
				return ""
			lead = Loc.t("gen.weapon.pierce.lead_shot", {"pierce": str(pierce)})
		"Spawner":
			if pierce <= 0:
				return ""
			lead = Loc.t("gen.weapon.pierce.lead_rounds", {"pierce": str(pierce)})
		_:
			return ""
	var s := Loc.t("gen.weapon.pierce.%s%s" % [how, "_more" if more > 0 else ""], {"more": str(more), "less": str(less)})
	return lead + " " + s if lead != "" else _sentence(s)


## Whether the pierce drop-off is on (Settings.pierce_falloff, pass 62), read by path like _registry: on when there are no
## Settings (a tool).
static func pierce_falloff_on() -> bool:
	var ml := Engine.get_main_loop()
	var st: Node = (ml as SceneTree).root.get_node_or_null("Settings") if ml is SceneTree else null
	return st == null or bool(st.get("pierce_falloff"))


## A passive's lines at `level` for the pause screen's Build tab and the Collection; a sentence of its own, so a ceiling
## stat's "up to" starts with a capital (pass 48: Desperado, Gas Mask).
static func passive_description(def: PassiveDef, level: int) -> String:
	return _sentence(_passive_lines(def, level))


static func _passive_lines(def: PassiveDef, level: int) -> String:
	var lv: int = max(level, 1)
	var per := describe_effects(def.effects_at_level(lv))
	if per == "":
		# pass 119 (lane LEGEND_B): an item whose levels say nothing in numbers says its own rule
		var own := passive_text(def)
		return own.trim_suffix(".") + "." if own != "" else Loc.t("gen.item.name_only", {"name": def.display_name})
	var total := describe_effects(_sum_effects(def.effects_for_level(lv)))
	# an evolved line has one level: all it is (pass 47); so has an item of one level (pass 48: Phoenix Feather)
	if def.max_level <= 1:
		return total + "."
	var vars := {"level": str(lv), "total": total, "per": per}
	# pass 95 (lane PASSIVES): a passive item on the rarity ladder names its rung ("Level 3 (Rare): ... total.",
	# "Level 4 (Evolved): ..."); its first level is what it gives, plainly
	if def.on_ladder():
		if lv <= 1:
			return total + "."
		# pass 119 (lane LEGEND_A): a rule said in words has no "total" (the Iron Horse's "every 15 s")
		vars["rung"] = rung_name(def, lv)
		return Loc.t("gen.passive.rung_rules" if _all_rules(def.effects_for_level(lv)) else "gen.passive.rung", vars)
	if _same_every_level(def):
		return Loc.t("gen.passive.per_level", vars)
	# a first level of its own, then the same step (pass 47: Barrel Rush, Steady Hand; pass 48: Skedaddle, Powder Keg,
	# Loose Change)
	if def.levels.size() == 2 and def.repeat_last_level:
		vars["first"] = describe_effects(def.effects_at_level(1))
		vars["step"] = describe_effects(def.effects_at_level(2))
		return Loc.t("gen.passive.first_then_total" if lv > 1 else "gen.passive.first_then", vars)
	# levels that differ (Evade, Vigour): what this level holds in all
	return Loc.t("gen.passive.level_total", vars)


## Whether every effect in `list` is a "rule" stat (pass 119, lane LEGEND_A: said in its own words, never summed).
static func _all_rules(list: Array) -> bool:
	for e in list:
		if e is Effect and stat_kind((e as Effect).stat) != "rule":
			return false
	return not list.is_empty()


## `s` with its first letter a capital.
static func _sentence(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


## Whether every level of a passive gives the same (one entry repeated), so "per level" is true of it.
static func _same_every_level(def: PassiveDef) -> bool:
	if def.levels.size() <= 1:
		return true
	var first := describe_effects(def.effects_at_level(1))
	for k in range(2, def.levels.size() + 1):
		if describe_effects(def.effects_at_level(k)) != first:
			return false
	return true


static func _sum_effects(list: Array) -> Array:
	## Collapse repeated effects on the same stat/op into one for display.
	var acc: Dictionary = {}
	var order: Array = []
	for item in list:
		var e := item as Effect
		if e == null:
			continue
		# a stat said in words has no total (pass 69: the Magnet's "pulls more often" is a step, never a sum)
		if stat_kind(e.stat) == "word" or stat_kind(e.stat) == "hidden":
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
	# one level unless the item has more (a weapon's max_level, five since pass 48; a passive's): a mutation, a perk
	var max_level := 1
	var eff: Array = []
	if def is WeaponDef:
		max_level = def.max_level
		if def.is_evolution:
			return Loc.t("gen.next.evolved")
		eff = def.effects_at_level(level + 1)
	elif def is PassiveDef:
		max_level = def.max_level
		eff = def.effects_at_level(level + 1)
	if level >= max_level:
		return Loc.t("gen.next.maxed")
	var s := describe_effects(eff)
	var what := s if s != "" else Loc.t("gen.next.nothing_new")
	# pass 95 (lane PASSIVES): a passive item names the rung the next level lands on ("Next level (Rare): ...")
	if def is PassiveDef and (def as PassiveDef).on_ladder():
		return Loc.t("gen.next.rung", {"rung": rung_name(def as PassiveDef, level + 1), "effects": what})
	return Loc.t("gen.next.level", {"effects": what})


## The name of the rung a passive item stands on at `level` (pass 95, lane PASSIVES): "Common" .. "Legendary",
## "Evolved" at its top; its rarity's name for a line or an evolved form.
static func rung_name(def: PassiveDef, level: int) -> String:
	var r: String = def.rung_at(level) if def != null else "common"
	return Loc.t("gen.rarity.evolved") if r == PassiveDef.EVOLVED_RUNG else rarity_name(r)


# --- what an upgrade changes (pass 58) -------------------------------------------------------------------------------
## The most rows a card lists of what an upgrade changes (pass 58, Garry: "Maybe we show which stats are actually
## changing as well with the upgrade, rather than just giving the line with a little arrow that shows a number turning
## into a different one").
const CHANGE_ROWS := 4
## A weapon's rows that follow from the others (the estimate, a blast's shape and what each creature in it takes): never
## listed as a change, since the stat that moved them is.
const CHANGE_SKIP := ["dps", "blast", "blast_hit"]
## Stats whose smaller number is the better one (a shorter cooldown or wait): a rise in one of them is a loss.
## Pass 70 (lane LINES): the waits between Marshal's Star's blocks and Mother Lode's sweeps.
const LOWER_BETTER := ["cooldown", "shield_delay", "regen_delay", "star_block_every", "gem_sweep_every", "train_every", "storm_every",
	# pass 119 (lane LEGEND_B): fewer kills a grave, fewer gold a percent, a smaller share a hit may take, a shorter wait
	"grave_every", "purse_might_per", "purse_hp_per", "hit_cap_pct", "boss_hit_cap_pct", "hit_block_every"]


## What a weapon's step from `level_from` to `level_to` changes: its rows (WeaponInstance.stat_rows, the pause screen's
## names and numbers) at both levels, the ones that differ, then any other stat its levels move, at most CHANGE_ROWS.
## `held` is the hero's copy (its mutations and its bonus go along); `player` is the hero's sheet (his attack damage,
## cooldown and area fold in, as the pause screen shows them). Each row: {stat, name, before, after, worse}. Two rows
## read as the weapon's description reads them (_weapon_row): the amount names what it counts ("Hammers 2 → 3") and an
## area that is a radius on the sand is in metres ("Blast radius 2.4 m → 2.9 m").
static func weapon_changes(def: WeaponDef, level_from: int, level_to: int, held: WeaponInstance = null,
		player: StatSheet = null, all_weapons: Array = []) -> Array:
	if def == null or def.is_evolution or level_from < 1 or level_to <= level_from:
		return []
	var a := _weapon_at(def, level_from, held, player, all_weapons)
	var b := _weapon_at(def, level_to, held, player, all_weapons)
	var was: Dictionary = {}
	for r: Dictionary in a.stat_rows():
		was[str(r["stat"])] = str(r["value"])
	var out: Array = []
	var covered: Array = []
	for r: Dictionary in b.stat_rows():
		var st := str(r["stat"])
		covered.append(st)
		if CHANGE_SKIP.has(st) or not was.has(st):
			continue
		var row := _weapon_row(a, b, st, str(was[st]), str(r["value"]), str(r["name"]))
		if not row.is_empty():
			out.append(row)
	# a stat the levels move that the rows leave out; the area is already there as the Sun Scepter's pillar radius or
	# the Guitarra's cone width
	var shaped := covered.has("radius") or covered.has("cone_deg")
	for k in range(level_from + 1, level_to + 1):
		for e in def.effects_at_level(k):
			var st2 := (e as Effect).stat
			if covered.has(st2) or (st2 == "area" and shaped):
				continue
			covered.append(st2)
			var row2 := _weapon_row(a, b, st2, format_value(st2, a.stat(st2)), format_value(st2, b.stat(st2)), stat_name(st2))
			if not row2.is_empty():
				out.append(row2)
	return out.slice(0, CHANGE_ROWS)


## One row of a weapon's step, {} when the stat reads the same at both levels: `before` and `after` as the Build tab
## shows them, except two the Build tab words loosely (pass 58 review): the amount takes the noun the weapon's
## description uses (amount_noun: "Hammers", "Blades", "Rockets", not "Projectiles" on weapons that fire none), and an
## area that is a radius on the sand reads in metres (area_radius: the Land Mine's "Blast radius 2.4 m → 2.9 m", not
## "Area of effect 240% → 288%", which reads as 2.4 times the area).
static func _weapon_row(a: WeaponInstance, b: WeaponInstance, st: String, before: String, after: String, label: String) -> Dictionary:
	var v0 := a.stat(st)
	var v1 := b.stat(st)
	if st == "amount":
		label = amount_noun(b.def, b.sheet, b.params)
	elif st == "area":
		var r0 := area_radius(a.def, a.sheet, a.params)
		var r1 := area_radius(b.def, b.sheet, b.params)
		if not r0.is_empty() and not r1.is_empty():
			label = str(r1[0])
			v0 = float(r0[1])
			v1 = float(r1[1])
			before = "%.1f m" % v0
			after = "%.1f m" % v1
	if before == after:
		return {}
	var pair := _tidy_pair(before, after)
	return {"stat": st, "name": _sentence(label), "before": pair[0], "after": pair[1], "worse": _worse(st, v0, v1)}


## A weapon's thing words in the look it wears (pass 76, lane LOOKS: the Grenade as a Dynamite Stick), [one, many]:
## WeaponDef.noun / nouns (the look's `noun` / `nouns`, else the JSON's top level); an evolution with none takes its family
## weapon's; one given alone makes the other ("stick" -> "sticks"). ["", ""] when there are none: the sentence keeps its
## own word ("grenade", "bottle", "bomb").
static func weapon_nouns(def: WeaponDef) -> Array:
	if def == null:
		return ["", ""]
	var one: String = def.noun
	var many: String = def.nouns
	if one == "" and many == "" and def.is_evolution:
		var reg := _registry()
		var root := str(reg.call("item_family_root", def.id)) if reg and reg.has_method("item_family_root") else def.evolved_from
		var w = reg.call("weapon", root) if reg and root != "" else null
		if w is WeaponDef and w != def:
			one = (w as WeaponDef).noun
			many = (w as WeaponDef).nouns
	if one != "" and many == "":
		many = one + "s"
	elif many != "" and one == "":
		one = _singular(many)
	return [one, many]


## The word for `n` of a weapon's things (pass 76): its look's (weapon_nouns), else `one` / `many`, the sentence's own.
static func thing_word(def: WeaponDef, n: int, one: String, many: String) -> String:
	var nn := weapon_nouns(def)
	if n == 1:
		return str(nn[0]) if str(nn[0]) != "" else one
	return str(nn[1]) if str(nn[1]) != "" else many


## What a weapon's `amount` counts, in the word its description uses (pass 58 review: the change rows said "Projectiles
## 2 → 3" on the Hammer, the Gravity Gun and the Orbit Saws): plural, lower case. `sheet` and `params` are the weapon's as
## it is carried (WeaponInstance.sheet, .params; empty params = the def's). The Sun Scepter's pillars and the Guitarra's
## waves are the words their Build tab rows already use; the Build tab's other rows keep "projectiles".
static func amount_noun(def: WeaponDef, sheet: StatSheet = null, params: Dictionary = {}) -> String:
	if def == null:
		return stat_name("amount")
	var pr: Dictionary = params if not params.is_empty() else def.params
	var fire := sheet != null and sheet.get_stat("fire_damage", 0.0) > 0.0
	var poison := sheet != null and sheet.get_stat("poison_damage", 0.0) > 0.0
	match def.behavior:
		"ProjectileEmitter":
			# the Spear is thrown like any shot and reads as what it is (weapon_description)
			if pr.has("plant"):
				return Loc.t("gen.weapon.noun.spears")
			# pass 67 (the basketball): its amount counts bounces (params.amount_mode "bounces")
			if str(pr.get("amount_mode", "")) == "bounces":
				return Loc.t("gen.weapon.noun.bounces")
			match def.targeting:
				"forward":
					return Loc.t("gen.weapon.noun.pellets")
				"healthy":
					return Loc.t("gen.weapon.noun.flares") if fire else Loc.t("gen.weapon.noun.darts")
			return Loc.t("gen.weapon.noun.shots")
		"Orbiter":
			return Loc.t("gen.weapon.noun.blades")
		"Lobber":
			# pass 76 (lane LOOKS): the look's word ("sticks") when it has one
			return thing_word(def, 2, "", Loc.t("gen.weapon.noun.bottles") if fire else (Loc.t("gen.weapon.noun.bombs") if poison else Loc.t("gen.weapon.noun.grenades")))
		"Thruster":
			# a slice swings `amount` times a stroke; the Spear's sweep (amount_mode "blades") and a thrust are blades
			var th = pr.get("thrust", {})
			var td: Dictionary = th if th is Dictionary else {}
			if float(td.get("slice_deg", 0.0)) > 0.0 and str(td.get("amount_mode", "")) != "blades":
				return Loc.t("gen.weapon.noun.swings")
			return Loc.t("gen.weapon.noun.blades")
		"Smasher":
			return Loc.t("gen.weapon.noun.hammers")
		"MineLayer":
			return Loc.t("gen.weapon.noun.mines")
		"GravityGun":
			var gv = pr.get("gravity", {})
			return Loc.t("gen.weapon.noun.black_holes") if gv is Dictionary and (gv as Dictionary).get("black_hole") is Dictionary else Loc.t("gen.weapon.noun.enemies_thrown")
		"Spawner":
			return Loc.t("gen.weapon.noun.turrets")
		"MissilePod":
			# rockets with a blast, or the Killer Bees' seekers (no blast)
			var blast_m := sheet.get_stat("area", 0.0) if sheet else float(def.base.get("area", 0.0))
			return Loc.t("gen.weapon.noun.rockets") if blast_m > 0.3 else Loc.t("gen.weapon.noun.bees")
		"ConeWave":
			return Loc.t("gen.weapon.noun.waves")
		"SunScepter":
			return Loc.t("gen.weapon.noun.pillars")
		"Beam", "LaserBeam":
			return Loc.t("gen.weapon.noun.beams")
		"Frisbee":
			return Loc.t("gen.weapon.noun.frisbees")
		"SaltShaker":
			return Loc.t("gen.weapon.noun.patches")
		"FireBreath":
			# pass 95 (lane BREATH): every point of amount is a second more of breath
			return Loc.t("gen.weapon.noun.seconds_of_breath")
	return stat_name("amount")


## A weapon's area as the radius it reaches on the sand, [what the radius is called, metres], for the weapons whose area
## is one (pass 58 review): a Lobber's area is its pool's, cloud's or blast's radius, a mine's and a rocket's the same,
## the Hammer's blast is smash.radius x area and the Gravity Gun's landing gravity.blast x area x Repulsor's throw_mult
## (as GravityGun._blast_r). [] for a weapon whose area is a share of its own size (blades, swings, cones, the bees) and
## for the Singularity's hole. `sheet` and `params` as amount_noun's.
static func area_radius(def: WeaponDef, sheet: StatSheet, params: Dictionary = {}) -> Array:
	if def == null or sheet == null:
		return []
	var pr: Dictionary = params if not params.is_empty() else def.params
	match def.behavior:
		"Lobber":
			var r := sheet.get_stat("area", 2.5)
			if sheet.get_stat("fire_damage", 0.0) > 0.0:
				return [Loc.t("gen.weapon.radius.pool"), r]
			if sheet.get_stat("poison_damage", 0.0) > 0.0:
				return [Loc.t("gen.weapon.radius.cloud"), r]
			return [Loc.t("gen.weapon.radius.blast"), r]
		"MineLayer":
			return [Loc.t("gen.weapon.radius.blast"), sheet.get_stat("area", 2.2)]
		"MissilePod":
			var rm := sheet.get_stat("area", 0.0)
			return [Loc.t("gen.weapon.radius.blast"), rm] if rm > 0.3 else []
		"Smasher":
			var sm = pr.get("smash", {})
			return [Loc.t("gen.weapon.radius.blast"), (float((sm as Dictionary).get("radius", 1.6)) if sm is Dictionary else 1.6) * sheet.get_stat("area", 1.0)]
		"GravityGun":
			var gv = pr.get("gravity", {})
			var gd: Dictionary = gv if gv is Dictionary else {}
			if gd.get("black_hole") is Dictionary:
				return []
			return [Loc.t("gen.weapon.radius.blast"), float(gd.get("blast", 1.9)) * sheet.get_stat("area", 1.0) * maxf(float(gd.get("throw_mult", 1.0)), 0.1)]
		"SaltShaker":
			# pass 69: a patch's radius, salt.radius x area x salt.area_mult (Salt Spill's 1.6)
			return [Loc.t("gen.weapon.radius.patch"), salt_radius(sheet, pr)]
	return []


# ---- pass 69, lane SALT: the Salt's words ----

## The Salt's patch radius (pass 69): params.salt.radius x area x salt.area_mult.
static func salt_radius(sheet: StatSheet, pr: Dictionary) -> float:
	var s = pr.get("salt", {})
	var sd: Dictionary = s if s is Dictionary else {}
	return float(sd.get("radius", 1.4)) * sheet.get_stat("area", 1.0) * float(sd.get("area_mult", 1.0))


## The Salt in words (pass 69, SaltShaker): how many patches a pour, how often, how big, how long, what a tick does, and
## what the path adds (Hiwa Kai's crystals, Thing About Luck's power-ups, Salt Flats' charge).
static func salt_words(sheet: StatSheet, pr: Dictionary, def: WeaponDef = null) -> String:
	var s = pr.get("salt", {})
	var sd: Dictionary = s if s is Dictionary else {}
	var n := maxi(sheet.get_int("amount", 1), 1)
	var secs := sheet.get_stat("duration", 4.0) * float(sd.get("duration_mult", 1.0))
	var dmg := sheet.get_stat("damage", 6.0) * float(sd.get("damage_mult", 1.0))
	var r := salt_radius(sheet, pr)
	var vars := {"amount": str(n), "radius": "%.1f" % r, "cooldown": "%.1f" % sheet.get_stat("cooldown", 1.6), "lasts": _plain(snappedf(secs, 0.1)),
		"damage": str(int(round(dmg))), "tick": _plain(float(sd.get("tick", 0.5)))}
	var text := Loc.t_first([_own_key(def, "salt", "salt") if def != null else "", "gen.weapon.salt"], vars)
	var cr = sd.get("crunch")
	var sl := float(sd.get("slow", 0.0))
	if cr is Dictionary:
		text += " " + Loc.t("gen.weapon.salt.crunch_slow" if sl > 0.0 else "gen.weapon.salt.crunch", {"mult": _plain(float((cr as Dictionary).get("mult", 2.0))),
			"pct": str(int(round(sl * 100.0)))})
	elif sl > 0.0:
		text += " " + Loc.t("gen.weapon.salt.slow", {"pct": str(int(round(sl * 100.0)))})
	var luck := float(sd.get("luck_mult", 1.0))
	if luck > 1.0:
		text += " " + Loc.t("gen.weapon.salt.luck", {"mult": _plain(luck)})
	if bool(sd.get("momentum_on_enter", false)):
		text += " " + Loc.t("gen.weapon.salt.momentum")
	return text


static var _whole_re: RegEx


## A row's two numbers without the zeros neither needs ("12.00 s → 16.00 s" reads "12 s → 16 s"); a pair where one
## needs its decimals keeps both as they are (the cooldown's "1.10 s → 0.95 s").
static func _tidy_pair(a: String, b: String) -> Array:
	if _whole_re == null:
		_whole_re = RegEx.create_from_string(r"^([+\-−]?\d+)\.0+(\D.*)?$")
	var ma := _whole_re.search(a)
	var mb := _whole_re.search(b)
	if ma and mb:
		return [ma.get_string(1) + ma.get_string(2), mb.get_string(1) + mb.get_string(2)]
	return [a, b]


## The weapon at `level` as the hero would carry it: his copy's mutations and bonus, his sheet folded in.
static func _weapon_at(def: WeaponDef, level: int, held: WeaponInstance, player: StatSheet, all_weapons: Array) -> WeaponInstance:
	var w := WeaponInstance.new(def, level)
	if held:
		w.mutations = held.mutations
		w.bonus_effects = held.bonus_effects
	w.rebuild(player if player else StatSheet.new(), all_weapons)
	return w


## What a line's or a passive item's step from `level_from` to `level_to` changes: its effects summed at both levels (as
## the pause screen sums them), the ones that differ, at most CHANGE_ROWS. A trade's growing price is a row too, marked
## worse. Each row: {stat, name, before, after, worse}.
static func passive_changes(def: PassiveDef, level_from: int, level_to: int) -> Array:
	if def == null or level_from < 1 or level_to <= level_from:
		return []
	var was: Dictionary = {}
	for e: Effect in _sum_effects(def.effects_for_level(level_from)):
		was[e.stat + "|" + e.op + "|" + e.target] = e.value
	var out: Array = []
	for e: Effect in _sum_effects(def.effects_for_level(level_to)):
		var v0 := float(was.get(e.stat + "|" + e.op + "|" + e.target, 0.0))
		var s0 := change_value(e.stat, e.op, v0)
		var s1 := change_value(e.stat, e.op, e.value)
		if s0 == s1:
			continue
		var label := _sentence(stat_name(e.stat)) + _target_words(e.target)
		# a ceiling keeps its "up to" (pass 58 review: Gas Mask's "+8% → +16%" read as a flat bonus; it is 1% a poisoned
		# enemy up to that, and Desperado's grows as health falls), after the name so it covers both numbers; its words
		# joined by a no-break space, so a long name wraps before "up to", never between them ("falls, up / to")
		if e.op != "set" and PREFIX.has(e.stat):
			label += ", " + Loc.t("gen.word.up_to").replace(" ", "\u00a0")
		out.append({"stat": e.stat, "name": label, "before": s0, "after": s1, "worse": _worse(e.stat, v0, e.value)})
	return out.slice(0, CHANGE_ROWS)


## A summed effect's amount as a change row shows it, with its sign and unit ("+16%", "+1", "+0.5 s", "−4%"), the
## way describe_effect words it; none yet is "0" in that unit.
static func change_value(stat: String, op: String, v: float) -> String:
	if op == "set":
		return format_value(stat, v)
	var kind := stat_kind(stat)
	# a rule (pass 70) shows its number in its own unit
	if kind == "rule":
		return format_value(stat, v)
	if op == "mul":
		var pct := int(round(v * 100.0))
		return "0%" if pct == 0 else ("+" if pct > 0 else "−") + str(absi(pct)) + "%"
	var unit: String = {"pct": "%", "sec": " s", "m": " m", "deg": "°"}.get(kind, "")
	var x := v * 100.0 if kind == "pct" else v
	if kind == "count":
		x = float(int(round(x)))
	if absf(x) < 0.0005:
		return "0" + unit
	return _signed(x, unit)


## Whether going from `v0` to `v1` is a loss: a smaller number, or a larger one where smaller is better (LOWER_BETTER).
static func _worse(stat: String, v0: float, v1: float) -> bool:
	if absf(v1 - v0) < 0.000001:
		return false
	return v1 > v0 if LOWER_BETTER.has(stat) else v1 < v0


## The weapons an effect aims at, after its stat's name, as describe_effect says them.
static func _target_words(target: String) -> String:
	if target == "all_weapons":
		return ", " + Loc.t("gen.word.all_weapons")
	if target.begins_with("weapon:"):
		return ", " + weapon_name(target.trim_prefix("weapon:"))
	return ""


static func rarity_name(r: String) -> String:
	var key := "gen.rarity.%s" % r
	return Loc.t(key) if Loc.has(key) else r.capitalize()


## The Registry by path: tools compile this before the autoloads exist, and Effect (every tool's JsonContent) compiles
## TextGen, so naming the autoload here broke the compile of every tool script (pass 46).
static func _registry() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("Registry") if ml is SceneTree else null


static func quest_text(q: QuestDef) -> String:
	if q.quest_text != "":
		return q.quest_text
	var c := q.condition
	# pass 137 (lane W2-TEXTGEN): one row a quest type, gen.quest.<type>
	match str(c.get("type", "")):
		"kills_with_weapon":
			var reg := _registry()
			var w: WeaponDef = reg.weapon(str(c.get("weapon", ""))) if reg else null
			return Loc.t("gen.quest.kills_with_weapon", {"count": str(int(c.get("count", 0))), "weapon": w.display_name if w else str(c.get("weapon", "")).capitalize()})
		"kills_of_enemy":
			return Loc.t("gen.quest.kills_of_enemy", {"creatures": creature_count(str(c.get("enemy", "")), int(c.get("count", 0)))})
		"reach_level":
			return Loc.t("gen.quest.reach_level", {"level": str(int(c.get("level", 0)))})
		"survive_minutes":
			return Loc.t("gen.quest.survive_minutes", {"minutes": str(int(c.get("minutes", 0)))})
		"survive_minutes_no_lift":
			return Loc.t("gen.quest.survive_minutes_no_lift", {"minutes": str(int(c.get("minutes", 0)))})
		"open_chests":
			return Loc.t("gen.quest.open_chests", {"count": str(int(c.get("count", 0)))})
		"evolve_any":
			var times := int(c.get("count", 1))
			return Loc.t("gen.quest.evolve_any", {"count": "1" if times <= 1 else str(times)})
		"extract_after_stage":
			return Loc.t("gen.quest.extract_after_stage", {"stage": str(int(c.get("stage", 1))), "map": map_name(str(c.get("map", "")))})
		"kill_boss":
			return Loc.t("gen.quest.kill_boss", {"stage": str(int(c.get("stage", 1))), "map": map_name(str(c.get("map", "")))})
		"kills_in_run_of_enemy":
			return Loc.t("gen.quest.kills_in_run_of_enemy", {"creatures": creature_count(str(c.get("enemy", "")), int(c.get("count", 0)))})
		# pass 44: totals across runs, and a stage reached in one
		"kills_total":
			return Loc.t("gen.quest.kills_total", {"count": grouped(int(c.get("count", 0)))})
		"runs_total":
			return Loc.t("gen.quest.runs_total", {"count": str(int(c.get("count", 0)))})
		"pickups_total":
			return Loc.t("gen.quest.pickups_total", {"count": str(int(c.get("count", 0)))})
		"gold_total":
			return Loc.t("gen.quest.gold_total", {"count": str(int(c.get("count", 0)))})
		"reach_stage":
			return Loc.t("gen.quest.reach_stage", {"stage": str(int(c.get("stage", 1)))})
		# pass 111 (lane SKINS): "Beat Nightfall with May." / "Beat Nightfall."
		"beat_stage":
			return beat_stage_text(c)
		# pass 100 (lane QUESTS): levels, upgrades and evolutions (quest_build_text)
		"hero_level", "item_level", "evolve_item", "weapon_paths", "items_maxed":
			return quest_build_text(c)
		# pass 113 (lane TASKS): damage, healing, barrels, Totem gifts, fire and poison (quest_task_text)
		"damage_with_weapon", "heal_with_item", "heal_with_source", "element_damage", "barrels_total", "totems_total":
			return quest_task_text(c)
	return Loc.t("gen.quest.any")


## Pass 113 (lane TASKS): the words of the task quests (QuestDef's header): "Deal 50,000 damage with the Revolver.",
## "Restore 2,000 HP with Death.", "Restore 500 HP with Hearts.", "Restore 300 HP with Healing Wells.", "Deal 20,000 fire
## damage.", "Break 40 barrels.", "Take 10 Totem gifts."; "... in one run." with `in_one_run` (pass 137: the row
## gen.quest.task.<what>_run).
static func quest_task_text(c: Dictionary) -> String:
	var n := int(c.get("count", 0))
	# rows "gen.quest.task.<what>" and, in one run, "gen.quest.task.<what>_run": "gen.quest.task.damage_run",
	# "gen.quest.task.heal_run", "gen.quest.task.element_run", "gen.quest.task.barrels_run", "gen.quest.task.totems_run"
	var run := "_run" if bool(c.get("in_one_run", false)) else ""
	var vars := {"count": grouped(n)}
	match str(c.get("type", "")):
		"damage_with_weapon":
			var wid := str(c.get("weapon", ""))
			vars["what"] = quest_item_name(wid) if wid != "" else quest_kind_words("weapon", true)
			return Loc.t("gen.quest.task.damage" + run, vars)
		"heal_with_item":
			var iid := str(c.get("item", ""))
			vars["what"] = quest_item_name(iid) if iid != "" else quest_kind_words("item", true)
			return Loc.t("gen.quest.task.heal" + run, vars)
		"heal_with_source":
			var src := str(c.get("source", ""))
			var cut := src.find(":")
			var kind := src.substr(0, cut) if cut > 0 else "pickup"
			var sid := src.substr(cut + 1) if cut > 0 else ""
			var what := Loc.t("gen.quest.power_ups") if kind == "pickup" else Loc.t("gen.quest.structures")
			if sid != "":
				var reg := _registry()
				var d: ContentDef = (reg.pickup(sid) if kind == "pickup" else reg.structure(sid)) if reg else null
				what = plural_name(d.display_name if d else sid.capitalize())
			vars["what"] = what
			return Loc.t("gen.quest.task.heal" + run, vars)
		"element_damage":
			var el := str(c.get("element", ""))
			vars["element"] = Loc.t("gen.quest.element." + (el if el == "fire" or el == "poison" else "any"))
			return Loc.t("gen.quest.task.element" + run, vars)
		"barrels_total":
			return Loc.t("gen.quest.task.barrels" + run, vars)
		"totems_total":
			return Loc.t("gen.quest.task.totems" + run, vars)
	return Loc.t("gen.quest.any")


## "Hearts", "Healing Wells", "Boxes": a name made plural the way creature_count does it.
static func plural_name(name: String) -> String:
	return name + ("es" if name.ends_with("s") or name.ends_with("x") else "s")


## Pass 100 (lane QUESTS): the words of the build quests (QuestDef's header): "Reach level 15 with Drifter.", "Get the
## Orbit Saws to level 5 in one run.", "Get a passive item to Legendary in one run.", "Evolve Temperance into Temperance
## Risen.", "Take all 3 mutations of the Revolver in one run.", "Hold 3 weapons at max level at once."
static func quest_build_text(c: Dictionary) -> String:
	var id := str(c.get("id", ""))
	var kind := str(c.get("kind", "any"))
	match str(c.get("type", "")):
		"hero_level":
			var reg := _registry()
			var h: CharacterDef = reg.character(str(c.get("hero", ""))) if reg else null
			var who: String = h.display_name if h else str(c.get("hero", "")).capitalize()
			return Loc.t("gen.quest.hero_level", {"level": str(int(c.get("level", 0))), "who": who})
		"item_level":
			var rung := str(c.get("rung", ""))
			var to := rarity_name(rung) if rung != "" else Loc.t("gen.quest.level_n", {"level": str(int(c.get("level", 0)))})
			var what := quest_item_name(id) if id != "" else quest_kind_words(("passive" if rung != "" else kind), true)
			return Loc.t("gen.quest.item_level", {"what": what, "to": to})
		"evolve_item":
			if id == "":
				return Loc.t("gen.quest.evolve_kind", {"kind": quest_kind_words(kind, false)})
			var reg := _registry()
			var w: WeaponDef = reg.weapon(id) if reg else null
			if w and w.is_evolution:
				return Loc.t("gen.quest.evolve_weapon", {"weapon": w.display_name})
			if w:
				var into: WeaponDef = reg.weapon(w.evolves_into)
				return Loc.t("gen.quest.evolve_weapon_into", {"weapon": w.display_name, "into": into.display_name}) if into else Loc.t("gen.quest.evolve_weapon", {"weapon": w.display_name})
			var p: PassiveDef = reg.passive(id) if reg else null
			if p and p.evolves_into != "":
				return Loc.t("gen.quest.evolve_card_into", {"card": p.display_name, "into": PassiveDef.display_name_of(p.evolves_into)})
			if p and p.is_item():
				return Loc.t("gen.quest.item_to_evolved", {"item": p.display_name})
			return Loc.t("gen.quest.evolve_item", {"item": quest_item_name(id)})
		"weapon_paths":
			var wid := str(c.get("weapon", ""))
			if wid == "":
				return Loc.t("gen.quest.paths_any")
			var reg := _registry()
			var n: int = (reg.mutations_of(wid) as Array).size() if reg else 3
			return Loc.t("gen.quest.paths", {"count": str(n), "item": quest_item_name(wid)})
		"items_maxed":
			var k := int(c.get("count", 1))
			return Loc.t("gen.quest.items_maxed", {"count": str(k), "kind": quest_kind_words(kind, false), "kinds": quest_kind_plural(kind)})
	return Loc.t("gen.quest.any")


## An item by its name as a quest says it: "the Orbit Saws" (a weapon), "Temperance" (a card), "Beer" (a passive item).
static func quest_item_name(id: String) -> String:
	var reg := _registry()
	var w: WeaponDef = reg.weapon(id) if reg else null
	if w:
		return Loc.t("gen.quest.the", {"name": w.display_name})
	return PassiveDef.display_name_of(id)


## The quest words' kind of item (gen.quest.kind.<k>: weapon, card, passive, item).
static func _quest_kind(kind: String) -> String:
	return kind if kind in ["weapon", "card", "passive"] else "item"


## A kind of item in a quest's words: "a weapon" / "weapon", "a card", "a passive item", "an item" / "item".
static func quest_kind_words(kind: String, article: bool) -> String:
	return Loc.t(("gen.quest.kind.%s.a" if article else "gen.quest.kind.%s") % _quest_kind(kind))


## A kind of item in a quest's words, more than one: "weapons", "cards", "passive items", "items".
static func quest_kind_plural(kind: String) -> String:
	return Loc.t("gen.quest.kind.%s.many" % _quest_kind(kind))


## "the Dune Scorpion", "150 Goblins", "30 Spit Cactuses": the creature by its name, counted.
static func creature_count(id: String, n: int) -> String:
	var reg := _registry()
	var e: EnemyDef = reg.enemy(id) if reg else null
	var name: String = e.display_name if e else id.capitalize()
	if n <= 1:
		return Loc.t("gen.quest.the", {"name": name})
	return "%d %s" % [n, name + ("es" if name.ends_with("s") or name.ends_with("x") else "s")]


## Pass 111 (lane SKINS): a beat_stage goal's words: the stage's name from the map's stage_list (its "Stage N" when the
## map names none), then the hero when it names one: "Beat Nightfall with May.", "Beat Nightfall."
static func beat_stage_text(c: Dictionary) -> String:
	var reg := _registry()
	var k := int(c.get("stage", 1)) - 1
	var map_id := str(c.get("map", ""))
	var m: MapDef = reg.map(map_id if map_id != "" else "red_canyon") if reg else null
	var stage_word := Loc.t("gen.quest.stage_n", {"stage": str(k + 1)})
	if m and m.timeline and k >= 0 and k < m.timeline.stage_count():
		stage_word = m.timeline.stage_name(k)
	var hero := str(c.get("hero", ""))
	if hero == "":
		return Loc.t("gen.quest.beat_stage", {"stage": stage_word})
	var h: CharacterDef = reg.character(hero) if reg else null
	return Loc.t("gen.quest.beat_stage_with", {"stage": stage_word, "who": h.display_name if h else hero.capitalize()})


static func map_name(id: String) -> String:
	var reg := _registry()
	var m: MapDef = reg.map(id) if reg else null
	return m.display_name if m else id.capitalize()


## A count with its thousands grouped (pass 69: "Kill 2,500 creatures, all time.", Mira's 99,999,999).
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func time_mmss(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- heroes (pass 61)

## A signature stat's name in a hero's trait is its row stat.<id>.hero_name when it has one (pass 137; "HP regen" reads
## better than "regen per second" after a number), else its stat name.
## What a signature stat means, in brackets after the rule: the row stat.<id>.hero_note (hero_note), {his} the hero's own
## word (his, her, their).
## Stats a hero is better off with less of: a step down reads "0.05 s less regen delay".
const HERO_LOWER := ["cooldown", "regen_delay", "shield_delay"]


static func hero_word(stat: String) -> String:
	var key := "stat.%s.hero_name" % stat
	return Loc.t(key) if Loc.has(key) else stat_name(stat)


## What signature stat `stat` means for hero `c` (stat.<id>.hero_note, {his} his own word); "" for a stat without a note.
static func hero_note(stat: String, c: CharacterDef) -> String:
	var key := "stat.%s.hero_note" % stat
	return Loc.t(key, {"his": possessive(c)}) if Loc.has(key) else ""


## The hero's own possessive (his, her, their) from CharacterDef.pronoun (rows gen.word.his, gen.word.her, gen.word.their).
static func possessive(c: CharacterDef) -> String:
	var p := c.pronoun if c else "they"
	match p:
		"he":
			return Loc.t("gen.word.his")
		"she":
			return Loc.t("gen.word.her")
	return Loc.t("gen.word.their")


## One signature stat's amount, unsigned ("1%", "2", "0.1", "0.05 s"): `value` is what the levels give (or one step).
static func hero_amount(stat: String, op: String, value: float) -> String:
	var a := absf(value)
	if op == "mul" or stat_kind(stat) == "pct":
		return _plain(a * 100.0) + "%"
	if stat_kind(stat) == "sec":
		return _plain(a) + " s"
	return _plain(a)


## A signature stat's value as it counts (a level's or the levels' sum): a step down stops at the stat's floor, measured
## from its default (Ironwood's delay: 3 s less 2.5 s at the most, so 0.5 s).
static func hero_capped(e: Effect) -> float:
	var v := e.value
	if StatSheet.STAT_FLOORS.has(e.stat) and e.op == "add" and v < 0.0:
		var room := float(StatSheet.PLAYER_DEFAULTS.get(e.stat, 0.0)) - float(StatSheet.STAT_FLOORS[e.stat])
		v = -minf(-v, maxf(room, 0.0))
	return v


## A signature stat's value signed and short, as the plaque and the hero sheet show it: "+1%", "+2", "+0.1", "−0.05 s"
## (one level's step, or `e` from CharacterDef.level_effects for what the levels come to).
static func hero_step(e: Effect) -> String:
	var v := hero_capped(e)
	return ("−" if v < 0.0 else "+") + hero_amount(e.stat, e.op, v)


## A hero's rule in words (pass 61, Garry: "Heroes have 1-2 unique stats, and they scale as they level up"): "Gain 1% crit
## chance per level." from the level_trait, Astro's heal on every level-up after it, a floor or what the stat means in
## brackets. A hero without one (the hidden heroes) reads its own trait_text; a hero with both a level trait and a
## special (pass 67: Buck) reads the rule, then his trait_text. The title plaque, the hero sheet, the arena and the
## Collection all read it here.
static func hero_trait(c: CharacterDef) -> String:
	if c == null:
		return ""
	if c.level_trait.is_empty():
		return c.trait_text if c.trait_text != "" else describe_effects(c.trait_effects)
	var parts: Array = []
	var notes: Array = []
	for e in c.level_trait:
		if not (e is Effect):
			continue
		var x: Effect = e
		var word := hero_word(x.stat)
		if x.value < 0.0 and x.stat in HERO_LOWER:
			parts.append(Loc.t("gen.outlaw.less", {"amount": hero_amount(x.stat, x.op, x.value), "stat": word}))
		else:
			parts.append("%s %s" % [hero_amount(x.stat, x.op, x.value), word])
		if StatSheet.STAT_FLOORS.has(x.stat):
			notes.append(Loc.t("gen.outlaw.floor", {"stat": word, "amount": hero_amount(x.stat, "add", float(StatSheet.STAT_FLOORS[x.stat]))}))
		var note := hero_note(x.stat, c)
		if note != "":
			notes.append(note)
	# pass 137: one sentence a mix, "gen.outlaw.gain", "gen.outlaw.gain_notes", "gen.outlaw.gain_heal", "gen.outlaw.gain_heal_notes"
	var key := "gen.outlaw.gain" + ("_heal" if c.level_heal > 0.0 else "") + ("_notes" if not notes.is_empty() else "")
	var s := Loc.t(key, {"parts": and_join(parts), "heal": _plain(c.level_heal * 100.0) + "%", "notes": "; ".join(notes)})
	# a hero with a mechanism of his own (pass 67: Buck's charge, CharacterDef.specials) says it after the rule, in his
	# trait_text, so the plaque, the hero sheet and the Collection carry the whole of it
	if c.trait_text != "" and not c.specials.is_empty():
		s += " " + c.trait_text
	return s


## What the signature stat comes to at a level, signed: "+12% crit chance", "+1.2 HP regen and 0.6 s less regen delay"
## (a step down stops at the stat's floor: Ironwood's delay at 0.5 s); "" for a hero without one.
static func hero_trait_at(c: CharacterDef, level: int) -> String:
	if c == null or c.level_trait.is_empty():
		return ""
	var parts: Array = []
	for e in c.level_effects(level):
		var x: Effect = e
		var v := hero_capped(x)
		var word := hero_word(x.stat)
		if v < 0.0 and x.stat in HERO_LOWER:
			parts.append(Loc.t("gen.outlaw.less", {"amount": hero_amount(x.stat, x.op, v), "stat": word}))
		else:
			parts.append("%s%s %s" % ["−" if v < 0.0 else "+", hero_amount(x.stat, x.op, v), word])
	return and_join(parts)


## Pieces joined with " and " (the row gen.word.and): "+12% crit chance and +2 regen".
static func and_join(parts: Array) -> String:
	return (" %s " % Loc.t("gen.word.and")).join(parts)


## The rule's "now" line: "+12% crit chance at level 12".
static func hero_trait_now(c: CharacterDef, level: int) -> String:
	var at := hero_trait_at(c, level)
	return "" if at == "" else Loc.t("gen.outlaw.at_level", {"trait": at, "level": str(level)})


# ---------------------------------------------------------------- pass 76 (lane UI): the hero's own numbers

## The hero's stats that multiply a weapon's own number though a weapon's is counted in seconds: on the hero's sheet
## cooldown and duration are 1 = as the weapon has it (StatSheet.PLAYER_DEFAULTS), so the pause Stats tab reads them as a
## share ("100%", "92%"), never "1.00 s".
const PLAYER_SHARE := ["cooldown", "duration"]


## A hero stat's kind as the pause Stats tab says it: the shares above as "pct", the rest as STATS has them.
static func player_kind(stat: String) -> String:
	return "pct" if PLAYER_SHARE.has(stat) else stat_kind(stat)


## A hero stat's value as the pause Stats tab shows it ("100%", "144.6", "1.5 m"): format_value, the shares as a percent.
static func player_value(stat: String, v: float) -> String:
	if PLAYER_SHARE.has(stat):
		return "%d%%" % int(round(v * 100.0))
	return format_value(stat, v)


## How far a hero stat moved, unsigned, in its value's own unit ("20%", "12", "0.7", "0.6 m", "1"; a percent stat in
## points): the Stats tab's change mark (the arrow says which way), whole from 10 up, else to a tenth. "" when it moved by
## less than that unit shows.
static func player_change(stat: String, v0: float, v1: float) -> String:
	var d := absf(v1 - v0)
	match player_kind(stat):
		"pct":
			var p := _change_amount(d * 100.0)
			return "" if p == "" else p + "%"
		"count":
			return "" if roundf(d) < 1.0 else str(int(roundf(d)))
		"sec":
			return "" if d < 0.05 else _change_amount(d) + " s"
		"m":
			return "" if d < 0.05 else _change_amount(d) + " m"
		"deg":
			return "" if d < 0.5 else "%d°" % int(round(d))
		"rule":
			return "" if d < 0.05 else rule_amount(stat, _change_amount(d))
	return _change_amount(d)


## The same move as a share of where it started ("15%": 90% -> 76% cooldown is a 15% cut): how the Stats tab says it
## when every source of the stat multiplies (its rows say "+8%", "−15%" too). "" for nothing, or from 0.
static func player_share_change(v0: float, v1: float) -> String:
	if absf(v0) < 0.000001:
		return ""
	var x := absf(v1 / v0 - 1.0) * 100.0
	return "" if x < 0.05 else _change_amount(x) + "%"


## An unsigned amount as a change mark says it: whole from 10 up, else to a tenth; "" under a twentieth.
static func _change_amount(x: float) -> String:
	if x < 0.05:
		return ""
	if x >= 9.95:
		return str(int(roundf(x)))
	return _plain(snappedf(x, 0.1))


## One source's amount on a hero stat, as its row in the Stats tab says it ("+10%", "+12", "−8%", "= 100%"): describe_effect
## without the name, a share's flat step in percent too.
static func player_effect(e: Effect) -> String:
	if PLAYER_SHARE.has(e.stat):
		if e.op == "set":
			return "= " + player_value(e.stat, e.value)
		if e.op == "add":
			return _signed(e.value * 100.0, "%")
	return describe_effect(e, false)


## A passive item's own sentence (pass 118, lane ITEMS): its `text`, else one written from its params for a rule TextGen
## knows (pass 119: the Grindstone's grind_text, the legendaries' arc_text, grave_text, purse_text, bible_text); "" for
## an item with neither.
static func passive_text(def: PassiveDef) -> String:
	if def == null:
		return ""
	if def.text != "":
		return def.text
	# pass 119 (lane LEGEND_B): the Grindstone and the four legendary items, from their first level and params
	if def.params.get("grind") is Dictionary:
		return grind_text(def)
	if def.params.get("arc") is Dictionary:
		return arc_text(def)
	if def.params.get("grave") is Dictionary:
		return grave_text(def)
	if def.params.get("purse") is Dictionary:
		return purse_text(def)
	if def.params.get("bible") is Dictionary:
		return bible_text(def)
	# pass 119 (lane LEGEND_A): the Iron Horse's and Personal Storm's rules from their params and first level
	if def.params.get("train") is Dictionary:
		return train_text(def)
	if def.params.get("storm") is Dictionary:
		return storm_text(def)
	return chest_text(def)


## The keys' rule in words (pass 118) from their first level's `chest_<stat>` effects: "Every chest you open banks +1%
## luck for the rest of the run; a later level raises only the chests after it." "" without such an effect. A banked
## multiplier stat (attack damage) is said as Run.chest_op lands it.
static func chest_text(def: PassiveDef) -> String:
	var fx: Array = []
	for e in def.effects_at_level(1):
		var x: Effect = e
		if x.stat.begins_with("chest_") and x.op == "add":
			var s := x.stat.trim_prefix("chest_")
			var mul := absf(float(StatSheet.PLAYER_DEFAULTS.get(s, 0.0)) - 1.0) < 0.0001
			fx.append(Effect.make(s, "mul" if mul else "add", x.value, "player"))
	if fx.is_empty():
		return ""
	return _own_rule(def, "chest", {"effects": describe_effects(fx)})


## Pass 137 (lane W2-TEXTGEN): a passive item's rule sentence: its own row passive.<id>.desc when it has one (pre-filled
## with the rule's text), else the rule's gen.passive.rule.<rule>, so a new item folder with the same params has words.
static func _own_rule(def: PassiveDef, rule: String, vars: Dictionary) -> String:
	return Loc.t_first(["passive.%s.desc" % def.id if def != null else "", "gen.passive.rule." + rule], vars)


## The Grindstone's rule in words (pass 119, lane LEGEND_B; Garry: "Just Upgrade or Evolve the weakest one"): what one
## level of it does (Run._grindstone). The card is offered only while a weapon can take it (CardPool, Run.grind_can_work).
static func grind_text(_def: PassiveDef = null) -> String:
	# pass 121 (lane GRIND; Garry: "a 1 time use item ... no upgrades"): a one-shot Grindstone (`single`) works once
	if _def != null and _def.single:
		return _own_rule(_def, "grind_once", {})
	# (the Grindstone's own row is its one-shot sentence: a levelled one reads the rule's)
	return Loc.t("gen.passive.rule.grind")


## Lightning in a Bottle's rule (pass 119, lane LEGEND_B) from its first level (crit_arcs, crit_arc_pct) and params.arc
## (radius): "Every critical hit throws an arc to up to 3 more enemies within 5 m for 25% of the hit. Arcs never chain."
static func arc_text(def: PassiveDef) -> String:
	var arc: Dictionary = def.params.get("arc", {})
	return _own_rule(def, "arc", {"arcs": _plain(first_level_value(def, "crit_arcs", 3.0)), "radius": _plain(float(arc.get("radius", 5.0))),
		"pct": _plain(first_level_value(def, "crit_arc_pct", 25.0))})


## The Undertaker's Shovel's rule (pass 119, lane LEGEND_B; pass 120, lane GHOST: a floating ghost circling its grave and
## firing ghost bolts that grow with the hero's power) from its first level and params.grave (rise, bolts_max): "One kill
## in 25 leaves a grave; 2 s later a ghost rises and circles it for 8 s, firing ghost bolts at the nearest enemies. The
## stronger you are, the more bolts (up to 6) and the harder they hit; no knockback. At most 4 at once."
static func grave_text(def: PassiveDef) -> String:
	var g: Dictionary = def.params.get("grave", {})
	return _own_rule(def, "grave", {"every": _plain(first_level_value(def, "grave_every", 25.0)), "rise": _plain(float(g.get("rise", 2.0))),
		"seconds": _plain(first_level_value(def, "grave_seconds", 8.0)), "bolts": _plain(float(g.get("bolts_max", 6.0))),
		"max": _plain(first_level_value(def, "grave_max", 4.0))})


## Fool's Gold's rule (pass 119, lane LEGEND_B) from its first level: "+1% attack damage for every 50 gold in this run's
## purse, up to +60%. Spending lowers it." (and the max HP part when its first level has one; pass 137: one row a mix,
## gen.passive.rule.purse[_cap][_hp])
static func purse_text(def: PassiveDef) -> String:
	var cap := first_level_value(def, "purse_might_cap", 0.0)
	var hp := first_level_value(def, "purse_hp_per", 0.0)
	var rule := "purse" + ("_cap" if cap > 0.0 else "") + ("_hp" if hp > 0.0 else "")
	return _own_rule(def, rule, {"per": _plain(first_level_value(def, "purse_might_per", 50.0)), "cap": _plain(cap), "hp": _plain(hp)})


## The Pocket Bible's rule (pass 119, lane LEGEND_B) from its first level: "No single hit takes more than 12% of your max
## HP (35% from a boss). Once every 20 s a hit is stopped outright, never a boss's." (pass 137: one row a mix,
## gen.passive.rule.bible[_boss][_block])
static func bible_text(def: PassiveDef) -> String:
	var cap := first_level_value(def, "hit_cap_pct", 12.0)
	var boss := first_level_value(def, "boss_hit_cap_pct", 0.0)
	# pass 120 (one cap for every hit, 35%): the boss's share named only when it differs
	var boss_differs := boss > 0.0 and not is_equal_approx(boss, cap)
	var every := first_level_value(def, "hit_block_every", 0.0)
	var rule := "bible" + ("_boss" if boss_differs else "") + ("_block" if every > 0.0 else "")
	return _own_rule(def, rule, {"cap": _plain(cap), "boss": _plain(boss), "every": _plain(every)})


## Pass 119 (lane LEGEND_A): the value a passive's first level sets `stat` to (its "set" effect, else the sum of its
## adds), `fallback` without one: the clocks the Iron Horse's and Personal Storm's words name.
static func first_level_value(def: PassiveDef, stat: String, fallback: float) -> float:
	var v := fallback
	var adds := 0.0
	var any_add := false
	for e in def.effects_at_level(1):
		var x: Effect = e
		if x == null or x.stat != stat:
			continue
		if x.op == "set":
			v = x.value
		elif x.op == "add":
			adds += x.value
			any_add = true
	return adds if any_add else v


## The Iron Horse's rule in words (pass 119, lane LEGEND_A) from its first level (`train_every`) and params.train {share,
## big_share, damage}: "Every 20 s a whistle blows and a ghost train charges down a track through you, the way you face.
## Everything on the rails takes 25% of its max HP (Elites and bosses 5%) + 35 damage and is thrown aside."
static func train_text(def: PassiveDef) -> String:
	var t: Dictionary = def.params.get("train", {})
	var every := first_level_value(def, "train_every", float(t.get("every", 20.0)))
	return _own_rule(def, "train", {"every": _plain(every), "share": _plain(float(t.get("share", 0.25)) * 100.0),
		"big": _plain(float(t.get("big_share", 0.05)) * 100.0),
		"damage": _plain(roundf(scaled_damage(float(t.get("damage", 35.0)), float(t.get("stage_scaled", 1.0)) > 0.5)))})


## Pass 119 (lane LEGEND_A): a legendary item's flat damage as the run would deal it now: x the hero's attack damage, x the
## stage multiplier when `stage` (the Run by path: tools compile TextGen before the autoloads exist); the number itself
## outside a run.
static func scaled_damage(base: float, stage: bool) -> float:
	var ml := Engine.get_main_loop()
	var run: Node = (ml as SceneTree).root.get_node_or_null("Run") if ml is SceneTree else null
	if run == null:
		return base
	var sheet = run.get("player_sheet")
	var d := base * (float(sheet.call("get_stat", "might", 1.0)) if sheet != null else 1.0)
	if stage and run.has_method("reward_mult"):
		d *= float(run.call("reward_mult"))
	return d


## Personal Storm's rule in words (pass 119, lane LEGEND_A) from its first level (`storm_every`, `storm_seconds`) and
## params.storm {rate, damage, big_mult}: "Every 30 s storm clouds gather over you and for 8 s lightning strikes about 2
## times a second, mostly where enemies crowd: 40 damage and a hard shove (half to Elites and bosses)."
static func storm_text(def: PassiveDef) -> String:
	var st: Dictionary = def.params.get("storm", {})
	var every := first_level_value(def, "storm_every", float(st.get("every", 30.0)))
	var secs := first_level_value(def, "storm_seconds", float(st.get("seconds", 8.0)))
	var big := float(st.get("big_mult", 0.5))
	var big_words := Loc.t("gen.passive.rule.storm_half") if absf(big - 0.5) < 0.001 else _plain(big * 100.0) + "%"
	return _own_rule(def, "storm", {"every": _plain(every), "seconds": _plain(secs), "rate": _plain(float(st.get("rate", 2.0))),
		"damage": _plain(roundf(scaled_damage(float(st.get("damage", 40.0)), float(st.get("stage_scaled", 1.0)) > 0.5))), "big": big_words})


## A perk's card text (pass 116): written from its params for a mechanism TextGen knows (the Invisible Box, special
## "box"), else the perk's own `text`.
static func perk_text(def: PerkDef) -> String:
	if def == null:
		return ""
	if def.special == "box":
		var p: Dictionary = def.params
		# pass 137: the perk's own row perk.<id>.desc, else the mechanism's gen.perk.box
		return Loc.t_first(["perk.%s.desc" % def.id, "gen.perk.box"], {"every": _plain(float(p.get("every", 25.0))), "seconds": _plain(float(p.get("seconds", 3.0)))})
	return def.text
