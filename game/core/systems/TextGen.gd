## Generates every piece of item text from data: effect lines, weapon descriptions,
## next-level previews, evolution status. Nothing in the UI is hand-written per item.
class_name TextGen
extends RefCounted

## stat -> [display name, kind]. kind: "num" plain number, "pct" shown as percent when mul, "sec" seconds, "m" metres, "count" integer
## The one place a stat's shown name lives (every card, pause line, toast and plaque reads it; TitleScreen.SHORT only
## shortens a few). Pass 45: might is "attack damage", area "area of effect", greed "coin gain" (the ids stay).
const STATS := {
	"damage": ["damage", "num"], "cooldown": ["cooldown", "sec"], "amount": ["projectiles", "count"],
	"pierce": ["pierce", "count"], "area": ["area of effect", "pct"], "speed": ["projectile speed", "num"],
	"duration": ["duration", "sec"], "knockback": ["knockback", "num"], "chains": ["chain jumps", "count"],
	"range": ["range", "m"], "spread_deg": ["spread", "deg"], "orbit_radius": ["orbit radius", "m"],
	"max_hp": ["max HP", "num"], "damage_reduction": ["damage reduction", "pct"], "regen": ["regen per second", "num"],
	"move_speed": ["move speed", "num"], "might": ["attack damage", "pct"], "projectile_speed": ["projectile speed", "pct"],
	"magnet": ["pickup radius", "m"], "luck": ["luck", "pct"], "greed": ["coin gain", "pct"], "revives": ["revives", "count"],
	"rerolls": ["rerolls", "count"], "skips": ["skips", "count"], "banishes": ["banishes", "count"],
	"hp": ["HP", "num"], "size": ["size", "pct"], "turn_rate": ["turn rate", "num"], "lifetime": ["turret lifetime", "sec"],
	"poison_damage": ["poison per tick", "num"], "poison_stacks": ["poison stacks", "count"], "poison_duration": ["poison lasts", "sec"],
	"lifesteal": ["life steal", "pct"], "fire_damage": ["burn per tick", "num"], "fire_duration": ["burns for", "sec"], "fire_spread": ["spread chance", "pct"],
	"crit_chance": ["crit chance", "pct"], "crit_damage": ["crit damage", "pct"], "execute_frac": ["execute threshold", "pct"],
	"thorns": ["thorns damage", "num"], "adrenaline_speed": ["speed per kill stack", "pct"], "adrenaline_might": ["attack damage per kill stack", "pct"],
	"overkill": ["overkill splash", "pct"], "cooldown_on_kill": ["cooldown cut per kill", "sec"], "xp_gain": ["XP gain", "pct"],
	"ricochet": ["ricochet chance", "pct"], "homing_turn": ["homing agility", "pct"], "haste": ["weapon speed", "pct"],
	"evade": ["evade chance", "pct"], "evade_invuln": ["untouchable after an evade", "sec"], "shield_max": ["shield", "num"],
	"shield_delay": ["shield recharge wait", "sec"], "shield_rate": ["shield recharge a second", "pct"],
	"regen_delay": ["regen wait after a hit", "sec"], "lifesteal_cap": ["life steal cap a second", "pct"],
	"heal_drop": ["cake drop chance", "pct"], "coin_drop": ["coin bag drop chance", "pct"],
	"brand_chance": ["chance a kill burns the ground", "pct"],
	# pass 46
	"desperado": ["attack damage as health falls", "pct"], "revive_hp": ["health on revive", "pct"],
	"hit_invuln": ["invulnerability after a hit", "sec"],
	# pass 46, the weapons' own rows (WeaponInstance.stat_rows): the Guitarra's cone, the Spear's pin
	"cone_deg": ["cone width", "deg"], "lift": ["lift", "m"], "pin": ["pins for", "sec"], "plant": ["stands in the sand for", "sec"],
	# pass 47, the new lines and passive items
	"freeze_chance": ["chance a hit freezes for 1 s", "pct"], "crit_heal_chance": ["chance a crit heals 2% max HP", "pct"],
	"gold_on_hit": ["gold when hit", "num"],
	"debuff_duration": ["debuff duration", "pct"], "difficulty": ["difficulty", "pct"],
	"still_regen": ["regen per second standing still", "num"], "still_might": ["attack damage per second standing still", "pct"],
	"barrel_speed": ["move speed after a barrel", "pct"], "barrel_seconds": ["barrel boost", "sec"],
	"xp_drop_chance": ["extra XP gem chance", "pct"], "elite_damage": ["damage to Elites and bosses", "pct"],
	# pass 48, the new passive items
	"phoenix_revive": ["free revive", "count"], "hurt_speed": ["move speed after a hit", "pct"],
	"hurt_speed_seconds": ["boost after a hit", "sec"], "powder_keg_chance": ["chance a kill blows up", "pct"],
	"coin_on_hit": ["chance a hit knocks a coin out", "pct"], "gas_mask_cap": ["damage reduction from poisoned enemies", "pct"],
	"kill_might": ["attack damage per 1,000 kills", "pct"],
	# pass 54, Solenne's stats and the Sun Scepter's own row (WeaponInstance.stat_rows)
	"buff_duration": ["buff duration", "pct"], "heal_mult": ["healing", "pct"], "radius": ["pillar radius", "m"],
	# pass 62, the Pocket Watch
	"powerup_duration": ["power-up duration", "pct"], "powerup_chance": ["power-up drop chance", "pct"],
}
## Who a weapon with priority targeting goes for (pass 48: peashooter, revolver, tommy gun, tumbleweed, pike, sabre,
## turret, the Killer Bees and their evolutions), in its description.
const PRIORITY_WHO := "the strongest enemy nearby"
## Words in front of a stat's amount (pass 46: Desperado's bonus is a ceiling, "up to +12% attack damage as health falls"
## a level, +60% at level 5; pass 48: Gas Mask's is too, one point a poisoned enemy).
const PREFIX := {"desperado": "up to ", "gas_mask_cap": "up to "}

const RARITY_NAMES := {"common": "Common", "uncommon": "Uncommon", "rare": "Rare", "epic": "Epic", "legendary": "Legendary"}


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
	if e.op != "set" and PREFIX.has(e.stat):
		out = str(PREFIX[e.stat]) + out
	if e.target == "all_weapons":
		out += ", all weapons"
	elif e.target.begins_with("weapon:"):
		out += ", " + weapon_name(e.target.trim_prefix("weapon:"))
	return out


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
			parts.append(describe_effect(e, with_name))
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
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return str(n) + suffix


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
	var word := "sweep" if float(td.get("slice_deg", 0.0)) > 0.0 and not bool(td.get("alternate", false)) else "thrust"
	var s := " Every %s %s is a guaranteed crit" % [ordinal(every), word]
	if rm > 1.001:
		s += " and reaches %d%% further" % int(round((rm - 1.0) * 100.0))
	return s + "."


## A Lobber's landing blast in words (pass 62, Sun Cocktail's params.land_blast {damage_frac, radius_frac, look}): " Each
## one bursts with sunlight as it lands: 12 damage within 1.8 m and a light shove.", "" without one.
static func land_blast_words(params: Dictionary, sheet: StatSheet) -> String:
	var lb = params.get("land_blast")
	if not lb is Dictionary or sheet == null:
		return ""
	var d: Dictionary = lb
	var r := sheet.get_stat("area", 2.5) * float(d.get("radius_frac", 0.9))
	var dmg := sheet.get_stat("damage", 0.0) * float(d.get("damage_frac", 1.0))
	var how := "bursts with sunlight" if str(d.get("look", "")) == "sun" else "bursts"
	return " Each one %s as it lands: %.0f damage within %.1f m and a light shove." % [how, dmg, r]


## The basketball in words (pass 67, params.return_on_hit; its amount counts bounces with amount_mode "bounces"): "Throws
## a ball at the strongest enemy within 9 m: it bounces to 1 more enemy within 7 m, then flies back to his hand, hitting
## up to 2 on the way." (return_pierce 80 or more: "hitting everything on the way"), then its Heat (params.catch): "Every
## caught ball that scored adds Heat: +5% damage, up to +50%. A hit on him cools it." and Slam Dunk's dunk (catch.slam).
## A hop looks 7 m for its next creature unless ricochet_any.reach says otherwise (ProjectileManager.RICOCHET_REACH, not
## named here: TextGen compiles for tools before the autoloads exist).
static func ball_words(def: WeaponDef, sheet: StatSheet, pr: Dictionary) -> String:
	var who := "the strongest enemy" if def.targeting == "priority" else "the nearest enemy"
	var ra = pr.get("ricochet_any", {})
	var rd: Dictionary = ra if ra is Dictionary else {}
	var hops := maxi(int(rd.get("count", 0)), 0)
	if str(pr.get("amount_mode", "")) == "bounces":
		hops += maxi(sheet.get_int("amount", 1), 1) - 1
	var rp := int(pr.get("return_pierce", 80))
	var way := ", hitting everything on the way" if rp >= 80 else ((", hitting up to %d on the way" % rp) if rp > 0 else "")
	var text := "Throws a ball at %s within %.0f m: " % [who, sheet.get_stat("range", 8.0)]
	if hops > 0:
		text += "it bounces to %d more enem%s within %.0f m, then flies back to his hand%s." % [hops, "y" if hops == 1 else "ies", float(rd.get("reach", 7.0)), way]
	else:
		text += "it flies back to his hand%s." % way
	var ct = pr.get("catch")
	if not ct is Dictionary:
		return text
	var c: Dictionary = ct
	var per := float(c.get("heat_per", 0.0))
	var top := int(c.get("heat_max", 10))
	if per > 0.0 and top > 0:
		text += " Every caught ball that scored adds Heat: +%d%% damage, up to +%d%%." % [int(round(per * 100.0)), int(round(per * float(top) * 100.0))]
		text += " Its Heat never cools." if bool(c.get("heat_keep", false)) else " A hit on him cools it."
	var sl = c.get("slam")
	if sl is Dictionary:
		var at := int((sl as Dictionary).get("at_heat", top))
		text += " At %s every catch is a dunk: %d%% of its damage to everything within %.1f m, thrown back." % ["full Heat" if at >= top else "%d Heat" % at,
			int(round(float((sl as Dictionary).get("damage_frac", 1.0)) * 100.0)), float((sl as Dictionary).get("radius", 3.5))]
	return text


static func weapon_description(def: WeaponDef, sheet: StatSheet, params: Dictionary = {}) -> String:
	var amount := sheet.get_int("amount", 1)
	var range_m := sheet.get_stat("range", 8.0)
	var pr: Dictionary = params if not params.is_empty() else def.params
	var text := ""
	var behavior := def.behavior
	# priority targeting (pass 48, EnemyManager.priority_index): the strong and the close before the merely close
	var who := PRIORITY_WHO if def.targeting == "priority" else "the nearest enemy"
	# the Spear (pass 46) is thrown like any shot, and reads as what it is
	if behavior == "ProjectileEmitter" and pr.has("plant"):
		behavior = "Spear"
	match behavior:
		"Spear":
			# through everything in its way, and it stands in the sand where it comes down
			text = "Throws %s at %s: through everything in the way, out to %.0f m, where %s in the sand." % ["a spear" if amount == 1 else "%d spears" % amount, who, range_m, "it sticks" if amount == 1 else "they stick"]
			var pin = pr.get("pin")
			if pin is Dictionary:
				text += " The first enemy each spear strikes is pinned in place for %.1f s." % float((pin as Dictionary).get("seconds", 1.2))
			var tz = pr.get("trail_zone")
			if tz is Dictionary:
				text += " Each leaves a trail of dust that slows what walks in it."
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
				"priority":
					text = "Fires %d shot%s within %.0f m and aims at %s." % [amount, "" if amount == 1 else "s", range_m, who]
				_:
					text = "Fires %d shot%s at the nearest enemy within %.0f m." % [amount, "" if amount == 1 else "s", range_m]
			# pass 48: Birdshot and the Blunderbuss blast a shape instead of flying pellets
			var bl = pr.get("blast")
			if bl is Dictionary:
				var blast: Dictionary = bl
				if str(blast.get("shape", "")) == "lane":
					text = "Blasts a %.1f m wide lane %.0f m long where you face: everything in it is hit at once and shoved along it." % [float(blast.get("width", 2.6)), range_m * float(blast.get("length_mult", 1.25))]
				elif str(blast.get("shape", "")) == "cone":
					text = "Blasts a %d° cone %.0f m deep where you face: everything in it is hit at once." % [int(round(float(blast.get("deg", 75.0)))), float(blast.get("range", range_m))]
			# pass 67 (the basketball, params.return_on_hit): one ball that bounces on and flies back to his hand
			var ball := bool(pr.get("return_on_hit", false))
			if ball:
				text = ball_words(def, sheet, pr)
			var de := int(pr.get("double_every", 0))
			if de >= 2:
				text += " Every %s shot fires twice in quick succession." % ({2: "second", 3: "third", 4: "fourth"}.get(de, "%dth" % de))
			var hs = pr.get("hip_shot")
			if hs is Dictionary:
				text += " Every %dth pull fires %d volleys in a row." % [int((hs as Dictionary).get("every", 5)), int((hs as Dictionary).get("volleys", 3))]
			var rav = pr.get("ricochet_any")
			if rav is Dictionary and not ball:
				var ra := int((rav as Dictionary).get("count", 0))
				if ra > 0:
					text += " Every round ricochets %d time%s at %d%%." % [ra, "" if ra == 1 else "s", int(round(float((rav as Dictionary).get("frac", 1.0)) * 100.0))]
			var mc := float(pr.get("mini_crit", 0.0))
			if mc > 0.0:
				text += " %d%% of rounds are mini crits." % int(round(mc * 100.0))
		"Orbiter":
			text = "%d blade%s circle you at %.1f m, hitting anything they touch." % [amount, "" if amount == 1 else "s", sheet.get_stat("orbit_radius", 2.0)]
		"Lobber":
			if sheet.get_stat("fire_damage", 0.0) > 0.0:
				text = "Lobs %d bottle%s of fire at the thickest crowd that is not burning yet. Leaves a %.1f m pool of flames." % [amount, "" if amount == 1 else "s", sheet.get_stat("area", 2.5)]
			elif sheet.get_stat("poison_damage", 0.0) > 0.0:
				text = "Lobs %d poison bomb%s at the thickest crowd of healthy enemies. Leaves a %.1f m cloud of green smoke." % [amount, "" if amount == 1 else "s", sheet.get_stat("area", 2.5)]
			else:
				text = "Lobs %d grenade%s at the densest crowd. Explodes in a %.1f m radius." % [amount, "" if amount == 1 else "s", sheet.get_stat("area", 2.5)]
			# pass 62, Sun Cocktail (params.land_blast): a small blast where each one lands
			text += land_blast_words(pr, sheet)
		"Beam":
			text = "Zaps a random enemy within %.0f m and chains to %d more." % [range_m, sheet.get_int("chains", 2)]
		"Thruster":
			var th = pr.get("thrust", {})
			var slice_deg: float = float(th.get("slice_deg", 0.0)) if th is Dictionary else 0.0
			# pass 53: the Spear's sweep swings every blade in one stroke ("blades"), the Thunder Lance alternates a sweep and
			# a throwing thrust, Stunning Thrust stuns, the Whirlwind's crits refund the stroke, the stunned take more
			var blades: bool = th is Dictionary and str(th.get("amount_mode", "")) == "blades"
			if slice_deg > 0.0:
				var many := ""
				if amount > 1:
					many = (", %d blades sweeping together" % amount) if blades else (", %d swings a stroke" % amount)
				text = "Slices a %d° arc across %s within %.1f m%s, throwing what it cuts out and aside." % [int(slice_deg), who, range_m, many]
				if th is Dictionary and bool(th.get("alternate", false)):
					text += " Every other stroke is a thrust that throws harder."
			else:
				text = "Thrusts %d blade%s at %s within %.1f m." % [amount, "" if amount == 1 else "s", who, range_m]
			var st = th.get("stun") if th is Dictionary else null
			if st is Dictionary:
				var sc := float((st as Dictionary).get("chance", 0.0))
				var ss := float((st as Dictionary).get("seconds", 1.0))
				text += (" Every hit stuns for %.1f s." % ss) if sc >= 1.0 else (" Every hit has a %d%% chance to stun for %.1f s." % [int(round(sc * 100.0)), ss])
			if float(pr.get("crit_refund", 0.0)) > 0.0:
				text += " A critical hit gives back %d%% of the cooldown." % int(round(float(pr.get("crit_refund", 0.0)) * 100.0))
			if float(pr.get("stunned_mult", 1.0)) > 1.0:
				text += " A stunned enemy takes ×%.1f." % float(pr.get("stunned_mult", 1.0))
			# pass 62, Heartseeker (params.crit_stroke): every Nth stroke a guaranteed crit with a longer reach
			text += crit_stroke_words(pr)
		"Smasher":
			var sm = pr.get("smash", {})
			var blast: float = (float(sm.get("radius", 1.6)) if sm is Dictionary else 1.6) * sheet.get_stat("area", 1.0)
			text = "Brings %d hammer%s down on the thickest crowd within %.1f m: a %.1f m blast that throws them outwards." % [amount, "" if amount == 1 else "s", range_m, blast]
			# pass 48: the Earthshaker's cracks carry lightning and a second wave, and it always crushes big game
			var qk = (sm as Dictionary).get("quake") if sm is Dictionary else null
			if qk is Dictionary:
				text += " The ground splits in %d cracks" % int((qk as Dictionary).get("lines", 4))
				if (qk as Dictionary).get("zap") is Dictionary:
					text += " that run with lightning"
				if (qk as Dictionary).get("roll") is Dictionary:
					text += " and roll a second wave"
				text += "."
			var gs = pr.get("giant_slayer")
			if gs is Dictionary and bool((gs as Dictionary).get("always", false)):
				text += " Bosses and Elites in the blast always take ×%s." % _plain(float((gs as Dictionary).get("mult", 2.5)))
		"MineLayer":
			# pass 48: the Land Mine had no sentence ("Land Mine.")
			var jr = pr.get("jackrabbit")
			var spring = pr.get("spring")
			var each := "a creature that steps on it sets it off"
			if jr is Dictionary:
				each = "each springs at a creature within %.0f m and bursts at chest height, then its casing hops on to another" % float((jr as Dictionary).get("sense", 6.0))
			elif spring is Dictionary:
				each = "each springs at a creature within %.1f m and blows where it lands" % float((spring as Dictionary).get("sense", 3.5))
			text = "Drops %s at your feet every %.1f s: %s, a %.1f m blast." % ["a mine" if amount == 1 else "%d mines" % amount, sheet.get_stat("cooldown", 2.0), each, sheet.get_stat("area", 2.2)]
		"GravityGun":
			var gv = pr.get("gravity", {})
			var gd: Dictionary = gv if gv is Dictionary else {}
			if gd.get("black_hole") is Dictionary:
				text = "Lobs %d black hole%s at the thickest crowd: %s drag%s everything in and eat%s it, then pop%s." % [amount, "" if amount == 1 else "s", "it" if amount == 1 else "they", "s" if amount == 1 else "", "s" if amount == 1 else "", "s" if amount == 1 else ""]
			else:
				# the blast the landing makes, Repulsor's 40% wider one too (area_radius, pass 58: the card's change row
				# reads the same number)
				text = "Picks up %d enem%s within %.0f m and throws %s into the thickest crowd: a %.1f m blast. What it throws takes a hit when it lands." % [amount, "y" if amount == 1 else "ies", range_m, "it" if amount == 1 else "them", float(area_radius(def, sheet, pr)[1])]
		"Spawner":
			var cap: int = int(round(float(pr.get("max_turrets", 6)) * float(pr.get("max_turrets_mult", 1.0))))
			var life := sheet.get_stat("lifetime", 12.0)
			# the Turret Family's never go (a lifetime of 9999)
			var stays := ("stays and shoots %s" % who) if life >= 999.0 else "shoots %s for %.0f s" % [who, life]
			if amount > 1:
				text = "Drops %d turrets every %.1f s, up to %d standing. Each %s." % [amount, sheet.get_stat("cooldown", 6.0), cap, stays]
			else:
				text = "Drops a turret every %.1f s. It %s." % [sheet.get_stat("cooldown", 6.0), stays]
		"MissilePod":
			# a pod that circles the hero: rockets with a blast, or seekers that sting and fizzle (the bees of the Killer
			# Bees' hive and its evolutions, pass 49: they read as bees, not seekers)
			var blast_m := sheet.get_stat("area", 0.0)
			var prey := PRIORITY_WHO if def.targeting == "priority" else "enemies"
			if blast_m > 0.3:
				text = "Launches %d homing rocket%s at %s within %.0f m: a %.1f m blast each." % [amount, "" if amount == 1 else "s", prey, range_m, blast_m]
				# pass 53: Cluster Munitions and Pressure Cooker, and the Hellfire Battery that carries both
				var cl = pr.get("cluster")
				if cl is Dictionary:
					var cc := float((cl as Dictionary).get("chance", 0.3))
					text += ((" Every blast scatters %d bomblets" % int((cl as Dictionary).get("count", 5))) if cc >= 1.0 else
						(" %d%% of blasts scatter %d bomblets" % [int(round(cc * 100.0)), int((cl as Dictionary).get("count", 5))]))
					text += " that pop under a creature's feet for %d%% of the damage%s." % [int(round(float((cl as Dictionary).get("damage_frac", 0.25)) * 100.0)),
						", setting off their neighbours" if bool((cl as Dictionary).get("chain", false)) else ""]
				var ps = pr.get("pressure")
				if ps is Dictionary:
					# pass 60 (lane WP): the pressure is built by standing still (MissilePod._tick_pressure), moving lets it
					# all out and a hit vents `hit_vent` of it (half without the key)
					var vent := clampf(float((ps as Dictionary).get("hit_vent", 0.5)), 0.0, 1.0)
					var vent_s := "half" if absf(vent - 0.5) < 0.01 else ("all of it" if vent >= 0.999 else "%d%%" % int(round(vent * 100.0)))
					text += " Standing still builds pressure: up to %d%% faster after %.0f s; moving lets it out, a hit vents %s." % [int(round(float((ps as Dictionary).get("max", 2.0)) * 100.0)),
						float((ps as Dictionary).get("seconds", 15.0)), vent_s]
				var op = pr.get("overpressure")
				if op is Dictionary:
					text += " At full pressure every %s volley fires twice." % ordinal(int((op as Dictionary).get("every", 4)))
			else:
				text = "Sends %d killer bee%s after %s within %.0f m." % [amount, "" if amount == 1 else "s", prey, range_m]
		"LaserBeam":
			text = "Pours a %.0f m beam through the crowd for %.1f s." % [range_m, sheet.get_stat("duration", 2.0)]
		"ConeWave":
			# the Guitarra (pass 46): a cone of melody that lifts what stands in it and sets it down where it stood
			var cone = pr.get("cone", {})
			var cd: Dictionary = cone if cone is Dictionary else {}
			var deg := cone_width(pr, sheet.get_stat("area", 1.0))
			var lift := float(cd.get("lift", 0.6))
			if deg >= 359.0:
				text = "Strums a ring of melody %.1f m all round: whatever stands in it is lifted %.1f m and dropped where it stood." % [range_m, lift]
			else:
				text = "Strums a %d° cone of melody %.1f m at the nearest enemy: whatever stands in it is lifted %.1f m and dropped where it stood." % [int(round(deg)), range_m, lift]
			if bool(cd.get("side_random", false)):
				text += " Each chord slaps them aside."
			if amount > 1:
				text += " %d echo%s follow%s at 60%% damage." % [amount - 1, "es" if amount > 2 else "", "" if amount > 2 else "s"]
		"SunScepter":
			# the Sun Scepter (pass 54): pillars of sunlight on what she can see, the close likelier; Zenith's sweep; Gold Dust
			var sun = pr.get("sun", {})
			var sr: float = (float((sun as Dictionary).get("radius", 1.3)) if sun is Dictionary else 1.3) * sheet.get_stat("area", 1.0)
			text = "Calls a pillar of sunlight down on a random enemy you can see every %.1f s (the closer, the likelier): %d damage in %.1f m." % [sheet.get_stat("cooldown", 1.1), int(round(sheet.get_stat("damage", 14.0))), sr]
			if amount > 1:
				text += " %d pillars a strike." % amount
			var zn = pr.get("zenith")
			if zn is Dictionary:
				text += " Every %s strike hits every enemy on the screen at %d%%." % [ordinal(int((zn as Dictionary).get("every", 10))), int(round(float((zn as Dictionary).get("frac", 0.8)) * 100.0))]
			var gd = pr.get("gold_dust")
			if gd is Dictionary:
				text += " Its kills drop a coin %d%% of the time." % int(round(float((gd as Dictionary).get("chance", 0.3)) * 100.0))
		_:
			text = def.display_name + "."
	var extras: Array = []
	var pd := sheet.get_stat("poison_damage", 0.0)
	if pd > 0.0:
		var st := maxi(sheet.get_int("poison_stacks", 1), 1)
		extras.append("Poisons: %.0f damage every 2 s for %.0f s%s." % [pd * st, sheet.get_stat("poison_duration", 10.0), (" (%d stacks)" % st) if st > 1 else ""])
	var fd := sheet.get_stat("fire_damage", 0.0)
	if fd > 0.0:
		# only some of what it hits, when the weapon says so (pass 51: Dragon's Breath's 60%)
		var ic := clampf(float(pr.get("ignite_chance", 1.0)), 0.0, 1.0)
		var lit := "Sets on fire" if ic >= 1.0 else "Sets %d%% of the enemies it hits on fire" % int(round(ic * 100.0))
		extras.append("%s: %.0f damage every 0.6 s for %.1f s. Spreads to touching enemies (%d%%)." % [lit, fd, sheet.get_stat("fire_duration", 1.8), int(round(sheet.get_stat("fire_spread", 0.5) * 100.0))])
	var pierce := sheet.get_int("pierce", 0)
	# pass 62: the pierce drop-off, while Settings.pierce_falloff is on, says how the pierce hits ("Pierces 2: the first
	# enemy takes ...")
	var pfw := pierce_falloff_words(pr, behavior, pierce)
	if pierce > 0 and behavior == "ProjectileEmitter" and pfw == "":
		extras.append("Pierces %d." % pierce)
	if pfw != "":
		extras.append(pfw)
	if sheet.get_stat("knockback", 0.0) > 0.0:
		extras.append("Knocks enemies back.")
	if def.hero != "":
		var reg := _registry()
		var owner = reg.character(def.hero) if reg else null
		extras.append("%s only." % (str(owner.display_name) if owner else def.hero.capitalize()))
	if def.is_evolution:
		extras.append("Evolved: cannot level further.")
	if not extras.is_empty():
		text += " " + " ".join(extras)
	return text


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
	# one after it 20% less than the one before.")
	var lead := ""
	var first := "the first enemy"
	var rest := "after it"
	match behavior:
		"Thruster":
			var th = pr.get("thrust", {})
			var td: Dictionary = th if th is Dictionary else {}
			if float(td.get("slice_deg", 0.0)) > 0.0 and not bool(td.get("alternate", false)):
				return ""
			first = "the first enemy along the thrust"
			rest = "behind it"
		"ProjectileEmitter", "Spear":
			if pierce <= 0:
				return ""
			lead = "Pierces %d: " % pierce
		"Spawner":
			if pierce <= 0:
				return ""
			lead = "Its rounds pierce %d: " % pierce
		_:
			return ""
	var s := ("%s takes %d%% more, each one %s %d%% less than the one before." % [first, more, rest, less]) if more > 0 else \
		("each enemy %s takes %d%% less than the one before." % [rest, less])
	return lead + s if lead != "" else _sentence(s)


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
		return def.display_name + "."
	var total := describe_effects(_sum_effects(def.effects_for_level(lv)))
	# an evolved line has one level: all it is (pass 47); so has an item of one level (pass 48: Phoenix Feather)
	if def.max_level <= 1:
		return total + "."
	if _same_every_level(def):
		return "%s per level. Level %d: %s total." % [per, lv, total]
	# a first level of its own, then the same step (pass 47: Barrel Rush, Steady Hand; pass 48: Skedaddle, Powder Keg,
	# Loose Change)
	if def.levels.size() == 2 and def.repeat_last_level:
		var s := "%s at level 1, then %s a level." % [describe_effects(def.effects_at_level(1)), describe_effects(def.effects_at_level(2))]
		return s + (" Level %d: %s total." % [lv, total] if lv > 1 else "")
	# levels that differ (Evade, Vigour): what this level holds in all
	return "Level %d: %s total." % [lv, total]


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
			return "Evolved. Maxed."
		eff = def.effects_at_level(level + 1)
	elif def is PassiveDef:
		max_level = def.max_level
		eff = def.effects_at_level(level + 1)
	if level >= max_level:
		return "Maxed."
	var s := describe_effects(eff)
	return "Next level: " + (s if s != "" else "nothing new")


# --- what an upgrade changes (pass 58) -------------------------------------------------------------------------------
## The most rows a card lists of what an upgrade changes (pass 58, Garry: "Maybe we show which stats are actually
## changing as well with the upgrade, rather than just giving the line with a little arrow that shows a number turning
## into a different one").
const CHANGE_ROWS := 4
## A weapon's rows that follow from the others (the estimate, a blast's shape and what each creature in it takes): never
## listed as a change, since the stat that moved them is.
const CHANGE_SKIP := ["dps", "blast", "blast_hit"]
## Stats whose smaller number is the better one (a shorter cooldown or wait): a rise in one of them is a loss.
const LOWER_BETTER := ["cooldown", "shield_delay", "regen_delay"]


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
				return "spears"
			# pass 67 (the basketball): its amount counts bounces (params.amount_mode "bounces")
			if str(pr.get("amount_mode", "")) == "bounces":
				return "bounces"
			match def.targeting:
				"forward":
					return "pellets"
				"healthy":
					return "flares" if fire else "darts"
			return "shots"
		"Orbiter":
			return "blades"
		"Lobber":
			return "bottles" if fire else ("bombs" if poison else "grenades")
		"Thruster":
			# a slice swings `amount` times a stroke; the Spear's sweep (amount_mode "blades") and a thrust are blades
			var th = pr.get("thrust", {})
			var td: Dictionary = th if th is Dictionary else {}
			if float(td.get("slice_deg", 0.0)) > 0.0 and str(td.get("amount_mode", "")) != "blades":
				return "swings"
			return "blades"
		"Smasher":
			return "hammers"
		"MineLayer":
			return "mines"
		"GravityGun":
			var gv = pr.get("gravity", {})
			return "black holes" if gv is Dictionary and (gv as Dictionary).get("black_hole") is Dictionary else "enemies thrown"
		"Spawner":
			return "turrets"
		"MissilePod":
			# rockets with a blast, or the Killer Bees' seekers (no blast)
			var blast_m := sheet.get_stat("area", 0.0) if sheet else float(def.base.get("area", 0.0))
			return "rockets" if blast_m > 0.3 else "bees"
		"ConeWave":
			return "waves"
		"SunScepter":
			return "pillars"
		"Beam", "LaserBeam":
			return "beams"
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
				return ["pool radius", r]
			if sheet.get_stat("poison_damage", 0.0) > 0.0:
				return ["cloud radius", r]
			return ["blast radius", r]
		"MineLayer":
			return ["blast radius", sheet.get_stat("area", 2.2)]
		"MissilePod":
			var rm := sheet.get_stat("area", 0.0)
			return ["blast radius", rm] if rm > 0.3 else []
		"Smasher":
			var sm = pr.get("smash", {})
			return ["blast radius", (float((sm as Dictionary).get("radius", 1.6)) if sm is Dictionary else 1.6) * sheet.get_stat("area", 1.0)]
		"GravityGun":
			var gv = pr.get("gravity", {})
			var gd: Dictionary = gv if gv is Dictionary else {}
			if gd.get("black_hole") is Dictionary:
				return []
			return ["blast radius", float(gd.get("blast", 1.9)) * sheet.get_stat("area", 1.0) * maxf(float(gd.get("throw_mult", 1.0)), 0.1)]
	return []


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
			label += ", " + str(PREFIX[e.stat]).strip_edges().replace(" ", "\u00a0")
		out.append({"stat": e.stat, "name": label, "before": s0, "after": s1, "worse": _worse(e.stat, v0, e.value)})
	return out.slice(0, CHANGE_ROWS)


## A summed effect's amount as a change row shows it, with its sign and unit ("+16%", "+1", "+0.5 s", "−4%"), the
## way describe_effect words it; none yet is "0" in that unit.
static func change_value(stat: String, op: String, v: float) -> String:
	if op == "set":
		return format_value(stat, v)
	var kind := stat_kind(stat)
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
		return ", all weapons"
	if target.begins_with("weapon:"):
		return ", " + weapon_name(target.trim_prefix("weapon:"))
	return ""


static func rarity_name(r: String) -> String:
	return RARITY_NAMES.get(r, r.capitalize())


## The Registry by path: tools compile this before the autoloads exist, and Effect (every tool's JsonContent) compiles
## TextGen, so naming the autoload here broke the compile of every tool script (pass 46).
static func _registry() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("Registry") if ml is SceneTree else null


static func quest_text(q: QuestDef) -> String:
	if q.quest_text != "":
		return q.quest_text
	var c := q.condition
	match str(c.get("type", "")):
		"kills_with_weapon":
			var reg := _registry()
			var w: WeaponDef = reg.weapon(str(c.get("weapon", ""))) if reg else null
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
	var reg := _registry()
	var e: EnemyDef = reg.enemy(id) if reg else null
	var name: String = e.display_name if e else id.capitalize()
	if n <= 1:
		return "the " + name
	return "%d %s" % [n, name + ("es" if name.ends_with("s") or name.ends_with("x") else "s")]


static func map_name(id: String) -> String:
	var reg := _registry()
	var m: MapDef = reg.map(id) if reg else null
	return m.display_name if m else id.capitalize()


static func time_mmss(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- heroes (pass 61)

## A signature stat's name in a hero's trait (TextGen's stat names otherwise): "HP regen" reads better than "regen per
## second" after a number.
const HERO_WORDS := {"regen": "HP regen", "regen_delay": "regen delay", "max_hp": "max HP"}
## What a signature stat means, in brackets after the rule; {his} is the hero's own word (his, her, their).
const HERO_NOTES := {"debuff_duration": "{his} burns, poison, slows and pins last longer; buffs do not"}
## Stats a hero is better off with less of: a step down reads "0.05 s less regen delay".
const HERO_LOWER := ["cooldown", "regen_delay", "shield_delay"]


static func hero_word(stat: String) -> String:
	return str(HERO_WORDS.get(stat, stat_name(stat)))


## The hero's own possessive (his, her, their) from CharacterDef.pronoun.
static func possessive(c: CharacterDef) -> String:
	var p := c.pronoun if c else "they"
	match p:
		"he":
			return "his"
		"she":
			return "her"
	return "their"


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
			parts.append("%s less %s" % [hero_amount(x.stat, x.op, x.value), word])
		else:
			parts.append("%s %s" % [hero_amount(x.stat, x.op, x.value), word])
		if StatSheet.STAT_FLOORS.has(x.stat):
			notes.append("%s never under %s" % [word, hero_amount(x.stat, "add", float(StatSheet.STAT_FLOORS[x.stat]))])
		if HERO_NOTES.has(x.stat):
			notes.append(str(HERO_NOTES[x.stat]).replace("{his}", possessive(c)))
	var s := "Gain " + " and ".join(parts) + " per level"
	if c.level_heal > 0.0:
		s += ", and heal %s of max HP on every level-up" % (_plain(c.level_heal * 100.0) + "%")
	if not notes.is_empty():
		s += " (" + "; ".join(notes) + ")"
	s += "."
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
			parts.append("%s less %s" % [hero_amount(x.stat, x.op, v), word])
		else:
			parts.append("%s%s %s" % ["−" if v < 0.0 else "+", hero_amount(x.stat, x.op, v), word])
	return " and ".join(parts)


## The rule's "now" line: "+12% crit chance at level 12".
static func hero_trait_now(c: CharacterDef, level: int) -> String:
	var at := hero_trait_at(c, level)
	return "" if at == "" else "%s at level %d" % [at, level]
