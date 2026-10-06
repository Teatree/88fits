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
## The mutations this weapon carries (MutationDef), set by Run; their effects fold into the sheet below, their params
## merge into `params`, and the last one naming a behaviour or a visual replaces the weapon's.
var mutations: Array = []
## def.params with every mutation's params merged over it (deep), rebuilt with the sheet. Behaviours read this.
var params: Dictionary = {}
## A cone wave's echo (pass 46, ConeWave: one more wave for every `amount` past the first) lands at this share of the
## first wave's damage.
const ECHO_FRAC := 0.6
## A blast's catch (pass 48, the Boomstick's lane and the Blunderbuss's cone, `params.blast`): the estimate counts one
## creature for every BLAST_M2 square metres the shape covers, at least one and at most BLAST_MAX.
const BLAST_M2 := 6.5
const BLAST_MAX := 6.0
## A mini crit (pass 48, `params.mini_crit`) adds half a crit's extra damage: +50% with the default 2x crit.
const MINI_EXTRA := 0.5
## Frag's spikes (Lobber `burst_spawn`) are counted as landing this often in the estimate.
const SPIKE_HIT := 0.5
## The Sun Scepter's pillar (pass 54) as the estimate counts it: about this many creatures in it; Zenith's sweep this many
## creatures on the screen.
const SUN_CATCH := 1.6
const SWEEP_CATCH := 10.0


func _init(p_def: WeaponDef, p_level: int = 1) -> void:
	def = p_def
	level = clamp(p_level, 1, p_def.max_level if p_def else 8)
	params = fold_params() if p_def else {}


## def.params with every mutation's params merged over it, then the def's `final` block (pass 48): an evolution's own
## word over the path it keeps (the Blunderbuss's cone over Birdshot's lane, the Golden Revolver's every-third hip shot
## over Hip Shot's every fifth). `final` itself is not kept.
func fold_params() -> Dictionary:
	var out: Dictionary = def.params.duplicate(true)
	var fin = out.get("final")
	out.erase("final")
	for m in mutations:
		out = merge_params(out, m.params)
	if fin is Dictionary:
		out = merge_params(out, fin)
	return out


## The path this weapon belongs to: the base weapon's id, also for its evolution.
func family_id() -> String:
	if def.is_evolution and def.evolved_from != "":
		return def.evolved_from
	return def.id


func has_mutation(id: String) -> bool:
	for m in mutations:
		if m.id == id:
			return true
	return false


## The behaviour that runs this weapon: the last mutation naming one, else the weapon's own.
func behavior() -> String:
	var b: String = def.behavior
	for m in mutations:
		if m.behavior != "":
			b = m.behavior
	return b


## The visual scene: the last mutation carrying one, else the weapon's own (may be null). An evolution keeps its own
## (pass 48: the Moonshine's jug, though the path it carries holds Methanol's blue bottle) unless the mutation also
## swaps the behaviour, whose visual goes with it (Needle Rain).
func visual_scene() -> PackedScene:
	var v: PackedScene = def.visual
	var own: bool = def.is_evolution and def.visual != null
	for m in mutations:
		if m.visual and (m.behavior != "" or not own):
			v = m.visual
	return v


static func merge_params(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = merge_params(out[k], over[k])
		elif over[k] is Dictionary or over[k] is Array:
			# a copy (pass 48): a mutation's own nested dictionary handed over by reference let a write to inst.params
			# reach the Registry's MutationDef
			out[k] = over[k].duplicate(true)
		else:
			out[k] = over[k]
	return out


func rebuild(player: StatSheet, all_weapons: Array) -> void:
	sheet = StatSheet.new()
	sheet.set_bases({"damage": 5.0, "cooldown": 1.0, "amount": 1, "pierce": 0, "area": 1.0, "speed": 10.0,
		"duration": 2.0, "knockback": 0.0, "chains": 0, "range": 8.0, "spread_deg": 30.0, "orbit_radius": 2.0, "lifetime": 12.0})
	sheet.set_bases(def.base)
	sheet.add_effects(def.effects_for_level(level), "level")
	sheet.add_effects(bonus_effects, "bonus")
	for m in mutations:
		sheet.add_effects(m.weapon_effects(), "mutation:" + m.id)
	params = fold_params()
	# player-side multipliers that every weapon inherits
	var might := player.get_stat("might", 1.0)
	if abs(might - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("damage", "mul", might - 1.0), "might")
	var cd := player.get_stat("cooldown", 1.0)
	if abs(cd - 1.0) > 0.0001:
		sheet.add_effect(Effect.make("cooldown", "mul", cd - 1.0), "haste")
	# Berserk: weapon speed ×2 halves every cooldown on top of everything else
	var hs := player.get_stat("haste", 1.0)
	if hs > 1.0001:
		sheet.add_effect(Effect.make("cooldown", "mul", 1.0 / hs - 1.0), "berserk")
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
		if e.target == "all_weapons" or e.target == "weapon:" + def.id or (e.target.begins_with("tag:") and def.tags.has(e.target.trim_prefix("tag:"))):
			sheet.add_effect(e, en["source"])


## Blue fire (pass 48: Methanol, Moonshine): `params.fire_blue` on the weapon or on a mutation it carries. Its pools, the
## bottle's drip and every creature it sets burning burn blue (EnemyManager.ignite, Fx, ElementCloud).
func blue_fire() -> bool:
	if bool(params.get("fire_blue", false)) or bool(def.params.get("fire_blue", false)):
		return true
	for m in mutations:
		if bool((m as MutationDef).params.get("fire_blue", false)):
			return true
	return false


## The share of the creatures it hits that this weapon sets alight (pass 51, `params.ignite_chance` merged from the
## weapon, its mutations and an evolution's `final`): 1 = every one (the default), Dragon's Breath 0.6.
func ignite_chance() -> float:
	return clampf(float(params.get("ignite_chance", 1.0)), 0.0, 1.0)


## The element this weapon carries: "fire", "poison" or "".
func element() -> String:
	if def.element != "":
		return def.element
	for m in mutations:
		if m.element != "":
			return m.element
	if float(def.base.get("fire_damage", 0.0)) > 0.0 or sheet.get_stat("fire_damage", 0.0) > 0.0:
		return "fire"
	if float(def.base.get("poison_damage", 0.0)) > 0.0 or sheet.get_stat("poison_damage", 0.0) > 0.0:
		return "poison"
	return ""


func stat(name: String, default: float = 0.0) -> float:
	return sheet.get_stat(name, default)


func stat_int(name: String, default: int = 0) -> int:
	return sheet.get_int(name, default)


func dps_estimate() -> float:
	var cd: float = max(stat("cooldown", 1.0), 0.05)
	var hits := float(max(stat_int("amount", 1), 1))
	# the behaviour that runs (a mutation may swap it: Needle Rain's lobber over the dart), so the recorder and the pause
	# screen estimate the weapon as it fires (pass 45)
	match behavior():
		"Orbiter":
			return stat("damage") * hits * 2.0
		"Beam":
			return stat("damage") * (1.0 + float(stat_int("chains", 0))) / cd
		"Spawner":
			return stat("damage") * 3.0
		"Smasher":
			# a blast lands on a crowd: call it three creatures a blow
			return stat("damage") * hits * 3.0 / cd
		"GravityGun":
			# a blast lands on a crowd: call it three creatures a blow; a black hole (pass 48, the Singularity) ticks
			# dps_frac of the damage a second for its seconds and pops for `pop` of it at the end
			var gv = params.get("gravity", {})
			var bh = (gv as Dictionary).get("black_hole") if gv is Dictionary else null
			if bh is Dictionary:
				var bd: Dictionary = bh
				return stat("damage") * (float(bd.get("seconds", 3.0)) * float(bd.get("dps_frac", 0.9)) + float(bd.get("pop", 1.0))) * 3.0 * hits / cd
			return stat("damage") * hits * 3.0 / cd
		"MineLayer":
			# a mine goes off on a creature and what stands by it: call it two a blast; Extra Supply (pass 48) lays its
			# share of drops twice, the Jackrabbit Mines always twice and a hop on for `hop.frac`
			var lay := 1.0 + float(params.get("extra_supply", 0.0))
			var jr = params.get("jackrabbit")
			if jr is Dictionary:
				if bool((jr as Dictionary).get("double", false)):
					lay = 2.0
				var hop = (jr as Dictionary).get("hop")
				if hop is Dictionary:
					lay *= 1.0 + float((hop as Dictionary).get("frac", 0.6)) * 0.5
			return stat("damage") * hits * lay * 2.0 / cd
		"ConeWave":
			# a chord catches a crowd (call it three), and every echo after the first wave lands at 60%
			return stat("damage") * (1.0 + ECHO_FRAC * (hits - 1.0)) * 3.0 / cd
		"LaserBeam":
			# a tick every beam.tick for `duration`, through the line: call it two creatures in it (pass 46)
			var b = params.get("beam", {})
			var tick: float = maxf(float(b.get("tick", 0.18)) if b is Dictionary else 0.18, 0.05)
			return stat("damage") * (stat("duration", 2.0) / tick) * 2.0 / cd
		"Lobber":
			# a bomb a throw (one creature a blast, as before), and pass 48's extra blasts: every bounce of a skull at full
			# damage, the bomblets at their share, Frag's spikes at their share when they land (SPIKE_HIT)
			var blasts := 1.0
			var bo = params.get("bounce")
			if bo is Dictionary:
				blasts += float(maxi(int((bo as Dictionary).get("count", 0)), 0))
			blasts += float(maxi(int(params.get("bomblets", 0)), 0)) * float(params.get("bomblet_damage_mult", 0.5))
			var bs = params.get("burst_spawn")
			if bs is Dictionary:
				blasts += float((bs as Dictionary).get("count", 0)) * float((bs as Dictionary).get("damage_mult", 0.5)) * SPIKE_HIT
			return stat("damage") * hits * blasts / cd
		"SunScepter":
			# a pillar catches about SUN_CATCH creatures (pass 54); Zenith's every `every`th strike is a sweep instead, every
			# creature on the screen at its `frac` (counted as SWEEP_CATCH of them)
			var per := stat("damage") * hits * SUN_CATCH
			var zn = params.get("zenith")
			if zn is Dictionary:
				var every: float = maxf(float((zn as Dictionary).get("every", 10)), 1.0)
				var sweep: float = stat("damage") * float((zn as Dictionary).get("frac", 0.8)) * SWEEP_CATCH
				per = (per * (every - 1.0) + sweep) / every
			return per / cd
		"MissilePod":
			# every seeker stings once; a Tarantula Hawk (pass 48) every `hawk.every` bursts stings `hawk.stings` times
			var dps := stat("damage") * hits / cd
			var hk = params.get("hawk")
			if hk is Dictionary:
				var every: float = maxf(float((hk as Dictionary).get("every", 4)), 1.0)
				dps += stat("damage") * float((hk as Dictionary).get("stings", 5)) / (every * cd)
			return dps
		_:
			return _shot_dps(hits, cd)


## A gun's estimate (pass 48): every round lands, a lane or a cone (`blast`) hits all it covers at its `frac` of the
## volley, Both Barrels' `double_every` fires that many pulls' worth once more, a hip shot's extra volleys, every
## ricochet of `ricochet_any` at its share, and the mini crits at MINI_EXTRA on average.
func _shot_dps(hits: float, cd: float) -> float:
	var per := stat("damage") * hits
	var bl := blast()
	if not bl.is_empty():
		per *= float(bl["frac"]) * blast_catch(bl)
	var de := int(params.get("double_every", 0))
	if de > 0:
		per *= 1.0 + 1.0 / float(de)
	var hs = params.get("hip_shot")
	if hs is Dictionary and int((hs as Dictionary).get("every", 0)) > 0:
		var ev := int(hs["every"])
		per *= (float(ev - 1) + float(maxi(int((hs as Dictionary).get("volleys", 3)), 1))) / float(ev)
	var ra = params.get("ricochet_any")
	if ra is Dictionary:
		per *= 1.0 + float(maxi(int((ra as Dictionary).get("count", 0)), 0)) * float((ra as Dictionary).get("frac", 0.8))
	per *= 1.0 + float(params.get("mini_crit", 0.0)) * MINI_EXTRA
	return per / cd


## The weapon's blast (pass 48, `params.blast`), read: {shape "lane", width, range (its length), frac} or {shape "cone",
## deg, range, frac}; {} for a weapon whose shots fly. A lane is `length` long, or the weapon's range times
## `length_mult`; a cone is `deg` wide (else the spread) and `range` deep (else the weapon's range).
func blast() -> Dictionary:
	var bl = params.get("blast")
	if not bl is Dictionary:
		return {}
	var b: Dictionary = bl
	var shape := str(b.get("shape", "lane"))
	if shape == "cone":
		return {"shape": "cone", "deg": float(b.get("deg", stat("spread_deg", 30.0))), "range": float(b.get("range", stat("range", 8.0))), "frac": float(b.get("frac", 0.4))}
	return {"shape": "lane", "width": float(b.get("width", 2.6)), "range": float(b.get("length", stat("range", 8.0) * float(b.get("length_mult", 1.0)))), "frac": float(b.get("frac", 0.4))}


## How many creatures the estimate counts in a blast: its ground area over BLAST_M2, from one to BLAST_MAX.
static func blast_catch(bl: Dictionary) -> float:
	var r := float(bl.get("range", 6.0))
	var m2: float = (float(bl.get("deg", 30.0)) / 360.0 * PI * r * r) if str(bl.get("shape", "lane")) == "cone" else float(bl.get("width", 2.6)) * r
	return clampf(m2 / BLAST_M2, 1.0, BLAST_MAX)


func description() -> String:
	return TextGen.weapon_description(def, sheet, params)


func stat_rows() -> Array:
	## [{"stat": "damage", "name": "damage", "value": "9.4"}] for the pause screen, only stats the behaviour uses.
	var keys: Array = []
	match def.behavior:
		"SunScepter":
			# the Sun Scepter (pass 54): its pillars, each one's radius, Zenith's sweep and Gold Dust's coins
			var srows: Array = []
			var sun = params.get("sun", {})
			var sr: float = (float((sun as Dictionary).get("radius", 1.3)) if sun is Dictionary else 1.3) * stat("area", 1.0)
			srows.append({"stat": "damage", "name": TextGen.stat_name("damage"), "value": TextGen.format_value("damage", stat("damage"))})
			srows.append({"stat": "cooldown", "name": TextGen.stat_name("cooldown"), "value": TextGen.format_value("cooldown", stat("cooldown"))})
			srows.append({"stat": "amount", "name": "pillars", "value": TextGen.format_value("amount", float(maxi(stat_int("amount", 1), 1)))})
			srows.append({"stat": "radius", "name": TextGen.stat_name("radius"), "value": TextGen.format_value("radius", sr)})
			var zn = params.get("zenith")
			if zn is Dictionary:
				srows.append({"stat": "zenith", "name": "sweep", "value": "every %d, %d%%" % [int((zn as Dictionary).get("every", 10)), int(round(float((zn as Dictionary).get("frac", 0.8)) * 100.0))]})
			var gd = params.get("gold_dust")
			if gd is Dictionary:
				srows.append({"stat": "gold_dust", "name": "coin a kill", "value": "%d%%" % int(round(float((gd as Dictionary).get("chance", 0.3)) * 100.0))})
			_element_rows(srows)
			srows.append({"stat": "dps", "name": "dps", "value": str(int(round(dps_estimate())))})
			return srows
		"ConeWave":
			# the Guitarra (pass 46): its reach, the cone's width and lift, and its waves (`amount`: the first and its echoes)
			var rows: Array = []
			var cone = params.get("cone", {})
			var cd: Dictionary = cone if cone is Dictionary else {}
			rows.append({"stat": "damage", "name": TextGen.stat_name("damage"), "value": TextGen.format_value("damage", stat("damage"))})
			rows.append({"stat": "cooldown", "name": TextGen.stat_name("cooldown"), "value": TextGen.format_value("cooldown", stat("cooldown"))})
			rows.append({"stat": "range", "name": "reach", "value": TextGen.format_value("range", stat("range"))})
			rows.append({"stat": "cone_deg", "name": TextGen.stat_name("cone_deg"), "value": TextGen.format_value("cone_deg", TextGen.cone_width(params, stat("area", 1.0)))})
			rows.append({"stat": "amount", "name": "waves", "value": TextGen.format_value("amount", float(maxi(stat_int("amount", 1), 1)))})
			rows.append({"stat": "lift", "name": TextGen.stat_name("lift"), "value": TextGen.format_value("lift", float(cd.get("lift", 0.6)))})
			_element_rows(rows)
			rows.append({"stat": "dps", "name": "dps", "value": str(int(round(dps_estimate())))})
			return rows
		"ProjectileEmitter":
			keys = ["damage", "cooldown", "amount", "range", "pierce", "knockback", "speed"]
			if def.targeting == "forward" and blast().is_empty():
				keys.append("spread_deg")
		"Orbiter":
			keys = ["damage", "amount", "orbit_radius", "knockback", "area"]
		"Lobber":
			keys = ["damage", "cooldown", "amount", "area", "range", "knockback"]
		"Beam":
			keys = ["damage", "cooldown", "chains", "range"]
		"LaserBeam":
			keys = ["damage", "cooldown", "duration", "range"]
		"Spawner":
			keys = ["damage", "cooldown", "lifetime", "range", "amount"]
		"Thruster":
			keys = ["damage", "cooldown", "amount", "range", "area", "knockback"]
		"Smasher", "GravityGun":
			keys = ["damage", "cooldown", "amount", "range", "area", "knockback"]
		_:
			keys = ["damage", "cooldown", "amount"]
	var rows: Array = []
	for k in keys:
		rows.append({"stat": k, "name": TextGen.stat_name(k), "value": TextGen.format_value(k, sheet.get_stat(k))})
	# the Spear (pass 46): how long the first creature it strikes is pinned, and how long it stands in the sand after
	var pin = params.get("pin")
	if pin is Dictionary:
		rows.append({"stat": "pin", "name": TextGen.stat_name("pin"), "value": TextGen.format_value("pin", float((pin as Dictionary).get("seconds", 1.2)))})
	var plant = params.get("plant")
	if plant is Dictionary:
		rows.append({"stat": "plant", "name": TextGen.stat_name("plant"), "value": TextGen.format_value("plant", float((plant as Dictionary).get("seconds", 0.6)))})
	_gun_rows(rows)
	_element_rows(rows)
	rows.append({"stat": "dps", "name": "dps", "value": str(int(round(dps_estimate())))})
	return rows


## Pass 48's gun rows: the lane or the cone a blast covers and what each creature in it takes, every how many pulls Both
## Barrels fires twice, the hip shot, the ricochets that need no kill, the share of mini crits.
func _gun_rows(rows: Array) -> void:
	var bl := blast()
	if not bl.is_empty():
		var per: float = float(bl["frac"]) * stat("damage") * float(maxi(stat_int("amount", 1), 1))
		if str(bl["shape"]) == "cone":
			rows.append({"stat": "blast", "name": "cone", "value": "%d° × %.1f m" % [int(round(float(bl["deg"]))), float(bl["range"])]})
		else:
			rows.append({"stat": "blast", "name": "lane", "value": "%.1f × %.1f m" % [float(bl["width"]), float(bl["range"])]})
		rows.append({"stat": "blast_hit", "name": "each hit", "value": TextGen.format_value("damage", per)})
	var de := int(params.get("double_every", 0))
	if de > 0:
		rows.append({"stat": "double_every", "name": "fires twice", "value": "every %d" % de})
	var hs = params.get("hip_shot")
	if hs is Dictionary and int((hs as Dictionary).get("every", 0)) > 0:
		rows.append({"stat": "hip_shot", "name": "hip shot", "value": "%d volleys, every %d" % [int((hs as Dictionary).get("volleys", 3)), int(hs["every"])]})
	var ra = params.get("ricochet_any")
	if ra is Dictionary and int((ra as Dictionary).get("count", 0)) > 0:
		rows.append({"stat": "ricochet_any", "name": "ricochets", "value": "%d at %d%%" % [int(ra["count"]), int(round(float((ra as Dictionary).get("frac", 0.8)) * 100.0))]})
	var mc := float(params.get("mini_crit", 0.0))
	if mc > 0.0:
		rows.append({"stat": "mini_crit", "name": "mini crits", "value": "%d%%" % int(round(mc * 100.0))})


## The poison and burn rows, when the weapon carries either.
func _element_rows(rows: Array) -> void:
	var keys: Array = []
	if sheet.get_stat("poison_damage", 0.0) > 0.0:
		keys += ["poison_damage", "poison_stacks", "poison_duration"]
	if sheet.get_stat("fire_damage", 0.0) > 0.0:
		keys += ["fire_damage", "fire_duration", "fire_spread"]
	for k in keys:
		rows.append({"stat": k, "name": TextGen.stat_name(k), "value": TextGen.format_value(k, sheet.get_stat(k))})
	# a fire that takes only some of what it hits (pass 51: Dragon's Breath)
	if sheet.get_stat("fire_damage", 0.0) > 0.0 and ignite_chance() < 1.0:
		rows.append({"stat": "ignite_chance", "name": "catches fire", "value": "%d%%" % int(round(ignite_chance() * 100.0))})
