## The boss's own chest (pass 118, lane BOSSCHEST; Garry: "Each Boss now drops a unique chest and inside it is a whole
## bunch of EXP and Gold (it's the same gold and EXP that Players already get from killing the boss, now packaged into
## this chest) ... The faster the Boss was killed the more Gold and Exp flies out."): its rules and numbers in one place.
## - The pack: everything a boss's kill paid in gold and XP before (its purse, its coins on the sand, its own big coin, its
##   XP gem, Prospector's and Eureka's gems, Gold Dust's coins: whatever PickupManager would have dropped while the kill
##   is handled, caught by PickupManager.capture_swap) is counted at the kill instead (Game._on_enemy_died), times the
##   speed bonus: gold before greed (a coin as PickupManager._collect pays it: its value x the stage's coin factor) and
##   XP before Field Notes. Motherlode, the Stakes' bounty (MirrorDanger) and the stage's XP shares apply as they did.
## - The speed bonus: the fight from the boss's arrival (WaveDirector._start_boss) to its death on the rule clock
##   (Run.rule_seconds: the frames' own clock, stopped with the screens), against S = the boss's boss_hp_scaling
##   seconds (the least fight at the hero's full DPS): max_mult at fast x S or quicker, 1 at slow x S or slower, a straight
##   line between. The map's timeline_data.boss_chest {fast, slow, max_mult}; DEFAULTS fill what it leaves out.
## - The net amounts: at the opening the pack is turned into what the hero gains (gold x greed, XP x Field Notes) and those
##   are the counters the pop-up counts up and exactly what the pickups pay when they land (PickupManager.exact_pay).
## - The look: each boss's chest in its JSON's boss.chest {name, shine, model, art}: its 3D model
##   (art/props/meta/boss_chest_<boss>.glb by default, tools/blender_boss_chests.py), its three paintings
##   (art/ui/wanted/bosschest/<boss>_<closed|cracked|open>.png, tools/gen_boss_chests.py) and the colour of its light.
class_name BossChest
extends RefCounted

## timeline_data.boss_chest's defaults: the fight lengths (in multiples of S) at which the bonus is whole and gone, and
## the bonus at its whole
const DEFAULTS := {"fast": 1.5, "slow": 4.0, "max_mult": 2.0}
const MODEL := "res://art/props/meta/boss_chest_%s.glb"
const ART := "res://art/ui/wanted/bosschest/%s_%s.png"
const FRAMES := ["closed", "cracked", "open"]
## a chest whose JSON names no light
const SHINE_DEFAULT := Color(1.0, 0.8, 0.32)
## How many pickups the payout throws (and the pop-up flies): about one coin per GOLD_PER_PIECE of gold and one gem per
## XP_PER_PIECE of XP, never fewer than the floor nor more than the cap of each.
const GOLD_PER_PIECE := 12.0
const XP_PER_PIECE := 45.0
const PIECES_MIN := 10
const PIECES_MAX := 70


## The map's block with every key filled and in range (`tl`: a WaveTimeline or anything with a `boss_chest` Dictionary;
## null = the defaults).
static func config(tl = null) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var block = tl.get("boss_chest") if tl != null and tl is Object else (tl if tl is Dictionary else null)
	if block is Dictionary:
		for k in DEFAULTS.keys():
			var v = (block as Dictionary).get(k)
			if v is float or v is int:
				out[k] = float(v)
	out["fast"] = maxf(float(out["fast"]), 0.0)
	out["slow"] = maxf(float(out["slow"]), float(out["fast"]) + 0.001)
	out["max_mult"] = maxf(float(out["max_mult"]), 1.0)
	return out


## The bonus for a fight of `fight_s` seconds against a boss whose S is `secs` (0 = no S: no bonus).
static func speed_mult(fight_s: float, secs: float, cfg: Dictionary = DEFAULTS) -> float:
	var c := config(cfg)
	if secs <= 0.0 or fight_s < 0.0:
		return 1.0
	var fast := float(c["fast"]) * secs
	var slow := float(c["slow"]) * secs
	var top := float(c["max_mult"])
	if fight_s <= fast:
		return top
	if fight_s >= slow:
		return 1.0
	return lerpf(top, 1.0, (fight_s - fast) / (slow - fast))


## The pack a boss's kill makes: `gold` (before greed) and `xp` (before Field Notes) as it would have paid them, times the
## bonus for a fight of `fight_s` against S `secs`.
static func make_pack(boss_id: String, gold: float, xp: float, fight_s: float, secs: float, cfg: Dictionary = DEFAULTS, stage: int = 0) -> Dictionary:
	var m := speed_mult(fight_s, secs, cfg)
	return {"boss": boss_id, "stage": stage, "gold_base": gold, "xp_base": xp, "mult": m, "fight": fight_s, "secs": secs,
		"gold": int(round(gold * m)), "xp": xp * m}


## The pack's net amounts at the opening (what the counters show and the pickups pay): gold x `greed`, XP x `xp_gain`.
static func net(pack: Dictionary, greed: float, xp_gain: float) -> Dictionary:
	var out := pack.duplicate()
	out["gold_net"] = int(round(float(pack.get("gold", 0)) * greed))
	out["xp_net"] = float(pack.get("xp", 0.0)) * xp_gain
	return out


## The pieces the payout throws: [coins, gems] for these net amounts (none of a kind with nothing to carry).
static func piece_counts(gold_net: int, xp_net: float) -> Vector2i:
	var c := 0 if gold_net <= 0 else clampi(int(ceil(float(gold_net) / GOLD_PER_PIECE)), mini(PIECES_MIN, gold_net), PIECES_MAX)
	var g := 0 if xp_net <= 0.0 else clampi(int(ceil(xp_net / XP_PER_PIECE)), PIECES_MIN, PIECES_MAX)
	return Vector2i(c, g)


## `total` split into `n` whole shares that add up to it exactly (the first ones a unit bigger where it does not divide).
static func split_int(total: int, n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var base := total / n
	var extra := total - base * n
	for k in range(n):
		out.append(base + (1 if k < extra else 0))
	return out


## `total` split into `n` equal shares that add up to it (the last one takes the float's rounding).
static func split_float(total: float, n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var s := total / float(n)
	var sum := 0.0
	for k in range(n - 1):
		out.append(s)
		sum += s
	out.append(total - sum)
	return out


## Boss `boss_id`'s chest: {name, shine (Color), model (path), art (path pattern with %s for the frame)} from its JSON's
## boss.chest, the defaults by its id for what that leaves out.
static func look(boss_id: String) -> Dictionary:
	var def: EnemyDef = Registry.enemy(boss_id) if boss_id != "" else null
	var block = def.boss.get("chest", {}) if def != null else {}
	if not (block is Dictionary):
		block = {}
	var shine := SHINE_DEFAULT
	var s = block.get("shine", "")
	if s is String and (s as String).is_valid_html_color():
		shine = Color(s)
	var nm := str(block.get("name", ""))
	if nm == "":
		nm = ("%s's Chest" % def.display_name) if def != null else "Boss Chest"
	return {"id": boss_id, "name": nm, "shine": shine, "boss_name": def.display_name if def != null else "",
		"model": str(block.get("model", MODEL % boss_id)), "art": str(block.get("art", ART.replace("%s_%s", boss_id + "_%s")))}


## The three paintings of `boss_id`'s chest (closed, cracked, open), or [] while any is missing (the screen draws one).
static func paintings(boss_id: String) -> Array:
	var pattern := str(look(boss_id)["art"])
	var out: Array = []
	for f: String in FRAMES:
		var p := pattern % f
		if not ResourceLoader.exists(p):
			return []
		var t := load(p) as Texture2D
		if t == null:
			return []
		out.append(t)
	return out


## What a boss would pay on `stage` (0-based) for a fight of `fight_s` (the arena's buttons, the captures, the tests): its
## purse, its drops.coins coins of 5, its own coin at its average (2 x the big coin's factor) and its large gem at its XP
## (xp_mult x 25 x the stage's XP multiplier), with Motherlode and the Stakes left out.
static func sample_pack(boss_id: String, stage: int = 0, fight_s: float = 30.0, tl = null) -> Dictionary:
	var def: EnemyDef = Registry.enemy(boss_id)
	if def == null:
		return {}
	var coin_k := float(maxi(int(round(Run.stage_mult())), 1))
	var gold := float(Game.boss_purse(stage)) + float(def.drops.get("coins", Game.BOSS_COINS)) * 5.0 * coin_k
	gold += 2.0 * PickupManager.BIG_COIN_MULT * coin_k * float(def.drops.get("gold", 0.0))
	var xp := 25.0 * def.xp_mult * float(def.drops.get("large", 0.0))
	var t = tl if tl != null else (Run.map.timeline if Run.map else null)
	if t != null and t.has_method("stage_xp_mult"):
		xp *= float(t.stage_xp_mult(stage))
	var secs: float = t.boss_seconds(boss_id) if t != null and t.has_method("boss_seconds") else 0.0
	return make_pack(boss_id, gold, xp, fight_s, secs, config(t), stage)
