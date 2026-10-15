## The bot's cards (pass 80, lane BOT): pass 77's tiers (card_tier, choose_card, item_kind, moved here from
## tools/sim_run.gd, which forwards to them) and pass 80's scores (score_card and its parts, pick_scored).
## Reached only from tools and tests: nothing here names an autoload or a game class (tools compile before autoloads);
## the game's scripts are loaded when a score is asked for.
extends RefCounted


## What a card hands over, as lane SIMUI charts it: weapon, evolution (a maxed line's evolution card, or a weapon
## evolution), line, passive (a passive item), perk or mutation.
static func item_kind(card: Dictionary) -> String:
	var type := str(card.get("type", ""))
	var d = card.get("def")
	if bool(card.get("evolve", false)) or (type == "weapon" and d != null and bool(d.get("is_evolution"))):
		return "evolution"
	if type == "passive":
		return "line" if d != null and d.has_method("is_line") and bool(d.is_line()) else "passive"
	return type


## A level-up card's tier for the bot (lower is taken first; ties at random), a sensible player's priorities (pass 77
## contract): 0 an evolution (a maxed line's evolution card), 1 the hero's favourite arriving (the card says FAVOURITE),
## 2 a new weapon (offered only while a weapon slot is free), 3 a level of a held weapon, 4 a hero perk (the contract
## names none: placed after the weapons), 5 a new line (only while a line slot is free), 6 a level of a held line,
## 7 a passive item (new or a level), 8 anything else.
static func card_tier(card: Dictionary) -> int:
	var type := str(card.get("type", ""))
	var d = card.get("def")
	if bool(card.get("evolve", false)) or type == "evolution":
		return 0
	if type == "weapon" and d != null and bool(d.get("is_evolution")):
		return 0
	if bool(card.get("favourite", false)):
		return 1
	var fresh := bool(card.get("is_new", false))
	match type:
		"weapon":
			return 2 if fresh else 3
		"perk":
			return 4
		"passive":
			var line: bool = d != null and d.has_method("is_line") and bool(d.is_line())
			if line:
				return 5 if fresh else 6
			return 7
	return 8


## The tiers' words (a decision's reason under the pass 77 rules).
const TIER_WORDS := ["an evolution", "the favourite", "a new weapon", "a weapon's next level", "a hero perk", "a new card",
	"a card's next level", "a passive item", "something else"]


## The card the bot takes from `offer`: the best tier on the table, ties at random by `rng` ({} for an empty offer).
static func choose_card(offer: Array, rng: RandomNumberGenerator) -> Dictionary:
	var best := 1 << 30
	var tied: Array = []
	for c in offer:
		if not (c is Dictionary):
			continue
		var tier := card_tier(c)
		if tier < best:
			best = tier
			tied = [c]
		elif tier == best:
			tied.append(c)
	if tied.is_empty():
		return {}
	return tied[rng.randi() % tied.size()]


## A card's name as the player reads it.
static func card_name(card: Dictionary) -> String:
	var d = card.get("def")
	if d != null and d.get("display_name") != null and str(d.get("display_name")) != "":
		return str(d.get("display_name"))
	if card.has("name"):
		return str(card["name"])
	return str(card.get("id", "?"))


# ---------------------------------------------------------------- pass 80: the scores

## The game's scripts the scores build with, loaded when first asked for (tools compile before the autoloads they name)
const WI_PATH := "res://core/systems/WeaponInstance.gd"
const EFFECT_PATH := "res://core/data/Effect.gd"

## A score is points: a part each (dps: the estimated DPS it adds, in % of today's, at most DPS_CAP; survival; plan;
## greed), each times the style's weight, survival also times the danger weight (danger_weight).
const DPS_CAP := 100.0
const STYLE_W := {
	"balanced": {"dps": 1.0, "survival": 1.0, "plan": 1.0, "greed": 0.6},
	"damage": {"dps": 1.6, "survival": 0.6, "plan": 1.0, "greed": 0.3},
	"safety": {"dps": 0.7, "survival": 1.8, "plan": 0.8, "greed": 0.3},
	"greedy": {"dps": 0.8, "survival": 0.7, "plan": 0.8, "greed": 1.8},
}
## Survival points for one unit of a player stat ("mul" values are fractions: +0.05 = +5%); max_hp's and shield_max's
## add count as their share of the hero's max HP, move_speed's add as its share of 3.6 m/s, regen's add as HP a second
## in % of max HP.
const SURVIVAL_PTS := {"max_hp": 80.0, "damage_reduction": 150.0, "regen": 30.0, "move_speed": 60.0, "evade": 120.0,
	"lifesteal": 300.0, "shield_max": 80.0, "revives": 25.0, "phoenix_revive": 25.0, "hit_invuln": 10.0, "heal_mult": 30.0,
	"overheal": 20.0, "heal_pulse": 40.0, "last_stand": 15.0, "thorns": 20.0, "heal_drop": 60.0, "hurt_speed": 20.0,
	"still_regen": 15.0, "crit_heal_chance": 40.0, "freeze_chance": 60.0}
## Greed points for one unit (XP, the gems' reach, luck, gold); magnet's add counts as its share of 1.5 m.
const GREED_PTS := {"xp_gain": 60.0, "magnet": 20.0, "luck": 40.0, "greed": 40.0, "coin_drop": 30.0, "xp_drop_chance": 60.0,
	"gold_on_hit": 20.0, "coin_on_hit": 20.0, "powerup_chance": 20.0, "powerup_duration": 10.0, "xp_pull_radius": 5.0,
	"xp_pull_rate": 10.0, "vein_chance": 40.0}
## Plan points: an evolution, the favourite, a weapon's or a line's level (more on its last), a new weapon while slots are
## free (times the free share), a new line, a mutation (more on a weapon's last of its path), a perk, a passive item, and
## MISC_PTS for effects none of the tables knows (so a card is never worth nothing).
const PLAN_EVOLUTION := 40.0
const PLAN_FAVOURITE := 20.0
const PLAN_WEAPON_LEVEL := 6.0
const PLAN_WEAPON_MAX := 8.0
const PLAN_LINE_LEVEL := 3.0
const PLAN_LINE_MAX := 10.0
const PLAN_NEW_WEAPON := 10.0
const PLAN_NEW_LINE := 4.0
const PLAN_MUTATION := 10.0
const PLAN_MUTATION_LAST := 6.0
const PLAN_PERK := 8.0
const PLAN_PASSIVE := 2.0
const MISC_PTS := 3.0
## skill: the scores the bot reads carry a gaussian error of (1 - skill) x SKILL_NOISE points (1 reads them exactly)
const SKILL_NOISE := 25.0


## The run as a score sees it (built once a decision): {run, sheet (the hero's), weapons, est (the DPS now), max_hp,
## hp_frac, danger (0..1), w (the style's weights), fav_w / fav_p (the favourites' ids)}.
static func context(run: Node, hp_frac: float, danger: float, style: String) -> Dictionary:
	var est := 0.0
	for w in run.weapons:
		est += float(w.dps_estimate())
	var sheet = run.player_sheet
	var ch = run.character
	return {"run": run, "sheet": sheet, "weapons": run.weapons, "est": est, "max_hp": float(sheet.get_stat("max_hp", 100.0)),
		"hp_frac": hp_frac, "danger": danger, "w": STYLE_W.get(style, STYLE_W["balanced"]),
		"fav_w": str(ch.favourite_weapon) if ch else "", "fav_p": str(ch.favourite_passive) if ch else ""}


## Survival's weight now: 0.6 calm, up to 2.1 when the last 30 s cost him his whole health and he is low.
static func danger_weight(ctx: Dictionary) -> float:
	return 0.6 + clampf(float(ctx.get("danger", 0.0)), 0.0, 1.0) + (1.0 - clampf(float(ctx.get("hp_frac", 1.0)), 0.0, 1.0)) * 0.5


## A card's score: {score, parts {dps, survival, plan, greed}, words (the reason's main clause)}. Works for level-up cards,
## mutation offers, chest gifts, shop wares and the Stranger's ware ({type, id, def, level_from, level_to, ...}) and for a
## Totem gift ({type: "boon", effects: [Effect], name}).
static func score_card(card: Dictionary, ctx: Dictionary) -> Dictionary:
	var type := str(card.get("type", ""))
	var d = card.get("def")
	var run: Node = ctx["run"]
	var parts := {"dps": 0.0, "survival": 0.0, "plan": 0.0, "greed": 0.0}
	var effs: Array = []
	var est: float = float(ctx["est"])
	var after := est
	var lv_to := int(card.get("level_to", 1))
	var lv_from := int(card.get("level_from", 0))
	var fresh := bool(card.get("is_new", false))
	var wi = load(WI_PATH)
	match type:
		"weapon", "evolution":
			var held = run.weapon_instance(str(d.id)) if d != null else null
			var src = null
			if d != null and (type == "evolution" or bool(d.is_evolution)):
				if card.has("src_id"):
					src = run.weapon_instance(str(card["src_id"]))
				else:
					src = run.family_instance(str(d.evolved_from))
				parts["plan"] += PLAN_EVOLUTION
			if d != null:
				var tmp = wi.new(d, maxi(lv_to, 1))
				var base_inst = held if held != null else src
				if base_inst != null:
					tmp.mutations = base_inst.mutations.duplicate()
					tmp.bonus_effects = base_inst.bonus_effects.duplicate()
				tmp.rebuild(ctx["sheet"], ctx["weapons"])
				after = est + float(tmp.dps_estimate()) - (float(base_inst.dps_estimate()) if base_inst != null else 0.0)
				if src == null:
					if held != null:
						parts["plan"] += PLAN_WEAPON_LEVEL + (PLAN_WEAPON_MAX if lv_to >= int(d.max_level) else 0.0)
					else:
						var cap := maxi(int(run.weapon_cap()), 1)
						parts["plan"] += PLAN_NEW_WEAPON * float(maxi(cap - (ctx["weapons"] as Array).size(), 0)) / float(cap)
		"mutation":
			if d != null:
				var inst = run.family_instance(str(d.weapon))
				if inst != null:
					var tmp = wi.new(inst.def, inst.level)
					tmp.mutations = inst.mutations.duplicate()
					tmp.mutations.append(d)
					tmp.bonus_effects = inst.bonus_effects.duplicate()
					tmp.rebuild(ctx["sheet"], ctx["weapons"])
					after = est + float(tmp.dps_estimate()) - float(inst.dps_estimate())
					var pp := Vector2i(0, 3)
					if run.has_method("path_progress"):
						pp = run.path_progress(inst)
					parts["plan"] += PLAN_MUTATION + (PLAN_MUTATION_LAST if pp.y > 0 and pp.x + 1 >= pp.y else 0.0)
				else:
					parts["plan"] += PLAN_MUTATION * 0.5
				effs = d.player_effects()
		"passive":
			if d != null:
				if bool(card.get("evolve", false)):
					parts["plan"] += PLAN_EVOLUTION
					effs = d.effects_for_level(maxi(lv_to, 1))
				else:
					for l in range(lv_from + 1, lv_to + 1):
						effs.append_array(d.effects_at_level(l))
					var line: bool = d.has_method("is_line") and bool(d.is_line())
					if line:
						parts["plan"] += (PLAN_NEW_LINE if fresh else PLAN_LINE_LEVEL) + (PLAN_LINE_MAX if lv_to >= int(d.max_level) else 0.0)
					else:
						parts["plan"] += PLAN_PASSIVE
		"perk":
			if d != null:
				effs = (d.effects as Array).duplicate()
			parts["plan"] += PLAN_PERK
		"boon":
			effs = card.get("effects", [])
		"gold":
			parts["greed"] += float(card.get("gold", 0)) * 0.05
	var favourite := bool(card.get("favourite", false))
	if not favourite and d != null and fresh and d.get("id") != null:
		favourite = str(d.id) != "" and (str(d.id) == str(ctx["fav_w"]) or str(d.id) == str(ctx["fav_p"]))
	if favourite:
		parts["plan"] += PLAN_FAVOURITE
	if not effs.is_empty():
		var r := _effects_parts(effs, ctx)
		after += float(r["dps_abs"])
		parts["survival"] += float(r["survival"])
		parts["greed"] += float(r["greed"])
		parts["dps"] += float(r["crit"])
		if float(r["dps_abs"]) == 0.0 and float(r["survival"]) == 0.0 and float(r["greed"]) == 0.0 and float(r["crit"]) == 0.0:
			parts["plan"] += MISC_PTS
	parts["dps"] += minf(100.0 * (after - est) / maxf(est, 1.0), DPS_CAP)
	var w: Dictionary = ctx["w"]
	var score: float = float(parts["dps"]) * float(w["dps"]) + float(parts["survival"]) * float(w["survival"]) * danger_weight(ctx) \
		+ float(parts["plan"]) * float(w["plan"]) + float(parts["greed"]) * float(w["greed"])
	for k in parts:
		parts[k] = snappedf(float(parts[k]), 0.1)
	return {"score": snappedf(score, 0.1), "parts": parts, "words": reason_words(card, parts)}


## What a list of player effects adds: {dps_abs (the estimate's change: the weapons rebuilt on a copy of the hero's sheet
## with the effects on it), crit (crit chance and damage as % DPS), survival, greed}.
static func _effects_parts(effs: Array, ctx: Dictionary) -> Dictionary:
	var out := {"dps_abs": 0.0, "crit": 0.0, "survival": 0.0, "greed": 0.0}
	var sheet = ctx["sheet"]
	var mx: float = maxf(float(ctx["max_hp"]), 1.0)
	var sheet2 = sheet.duplicate_sheet()
	sheet2.add_effects(effs, "bot")
	var wi = load(WI_PATH)
	var est2 := 0.0
	for w in ctx["weapons"]:
		var tmp = wi.new(w.def, w.level)
		tmp.mutations = w.mutations.duplicate()
		tmp.bonus_effects = w.bonus_effects.duplicate()
		tmp.rebuild(sheet2, ctx["weapons"])
		est2 += float(tmp.dps_estimate())
	out["dps_abs"] = est2 - float(ctx["est"])
	var cc := float(sheet.get_stat("crit_chance", 0.0))
	var cd := float(sheet.get_stat("crit_damage", 2.0))
	out["crit"] = (float(sheet2.get_stat("crit_chance", 0.0)) - cc) * (cd - 1.0) * 100.0 + (float(sheet2.get_stat("crit_damage", 2.0)) - cd) * cc * 100.0
	for e in effs:
		if e == null:
			continue
		var st := str(e.stat)
		var v := float(e.value)
		var op := str(e.op)
		if SURVIVAL_PTS.has(st):
			var unit := v
			if (st == "max_hp" or st == "shield_max") and op == "add":
				unit = v / mx
			elif st == "move_speed" and op == "add":
				unit = v / 3.6
			elif st == "regen" and op == "add":
				unit = v / mx * 100.0
			out["survival"] += unit * float(SURVIVAL_PTS[st])
		elif GREED_PTS.has(st):
			var u := v
			if st == "magnet" and op == "add":
				u = v / 1.5
			out["greed"] += u * float(GREED_PTS[st])
	return out


## The reason's main clause from a card's parts: the biggest part in a player's words.
static func reason_words(card: Dictionary, parts: Dictionary) -> String:
	var type := str(card.get("type", ""))
	var nm := card_name(card)
	var lv := int(card.get("level_to", 0))
	var what := nm
	if type in ["weapon", "passive"] and lv > 0:
		what = "%s to Lv %d" % [nm, lv]
	var best := "plan"
	var bv := -INF
	for k in ["dps", "survival", "plan", "greed"]:
		if float(parts.get(k, 0.0)) > bv:
			bv = float(parts.get(k, 0.0))
			best = k
	match best:
		"dps":
			return "+%d%% DPS: %s" % [roundi(float(parts["dps"])), what]
		"survival":
			return "safer (+%d): %s" % [roundi(float(parts["survival"])), what]
		"greed":
			return "richer (+%d): %s" % [roundi(float(parts["greed"])), what]
	if bool(card.get("evolve", false)) or type == "evolution":
		return "the evolution: %s" % what
	if bool(card.get("favourite", false)):
		return "the favourite: %s" % what
	if type == "mutation":
		return "a step on the path: %s" % what
	return "for the build (+%d): %s" % [roundi(float(parts["plan"])), what]


## The pick from scored rows [{score, ...}]: with skill 1 the best (the first of equals); below, each score read with a
## gaussian error of (1 - skill) x SKILL_NOISE (the bot's `rng`), the best read taken. Returns its index (-1 for none).
static func pick_scored(rows: Array, skill: float, rng: RandomNumberGenerator) -> int:
	var best := -1
	var bv := -INF
	var sd := (1.0 - clampf(skill, 0.0, 1.0)) * SKILL_NOISE
	for i in range(rows.size()):
		var v := float((rows[i] as Dictionary).get("score", 0.0))
		if sd > 0.0:
			v += rng.randfn(0.0, sd)
		if v > bv:
			bv = v
			best = i
	return best
