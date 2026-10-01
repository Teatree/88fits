## What a Wanted card says about an item, from an offer card ({def, level_from, level_to, evolve, ...}): the kind in one
## word (in the kind's colour), the stars, the one effect line and the rarity. No kind tags, level chips or flavour
## lines on in-run cards. Used by the level-up, path, chest, shop and Stranger screens.
class_name WItem
extends RefCounted


static func kind(def: ContentDef) -> String:
	return W.kind_of(def)


static func word(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	var lf := int(card.get("level_from", 0))
	var lt := int(card.get("level_to", 1))
	match kind(def):
		"weapon":
			return ("WEAPON · LV %d → %d" % [lf, lt]) if lf > 0 else "NEW WEAPON"
		"evolution":
			return "EVOLUTION"
		"passive":
			return ("PASSIVE · LV %d → %d" % [lf, lt]) if lf > 0 else "NEW PASSIVE"
		"line":
			if bool(card.get("evolve", false)):
				var src = W.node("Registry").line((def as LineDef).evolves_from)
				return "EVOLVES " + (src.display_name.to_upper() if src else "A LINE")
			return ("LINE · RANK %d → %d" % [lf, lt]) if lf > 0 else "NEW LINE"
		"perk":
			var hero = W.node("Registry").character((def as PerkDef).hero)
			return "%s'S PERK · ONCE" % (hero.display_name.to_upper() if hero else "HERO")
		"mutation":
			return "HERO PATH" if (def as MutationDef).is_hero() else "MUTATION"
	return ""


static func word_color(card: Dictionary) -> Color:
	var def: ContentDef = card["def"]
	var k := kind(def)
	if k == "line" and bool(card.get("evolve", false)):
		return W.EMBER
	return W.KIND_WORD.get(k, W.INK_SOFT)


## [total, held, upto]: a new item shows the level it lands on in brass; an upgrade shows what it has in brass and the
## step this pick gives in paper. Mutations, perks, evolutions and a line's evolution have no stars.
static func stars(card: Dictionary) -> Array:
	var def: ContentDef = card["def"]
	var k := kind(def)
	if k in ["mutation", "perk", "evolution"] or bool(card.get("evolve", false)):
		return []
	var mx := int(def.get("max_level")) if def.get("max_level") != null else 1
	var lf := int(card.get("level_from", 0))
	var lt := maxi(int(card.get("level_to", 1)), 1)
	if lf <= 0:
		return [mx, lt, -1]
	return [mx, lf, lt]


## Whether an effect is the price a line charges (less health or speed, longer cooldowns).
static func _harms(e: Effect) -> bool:
	var v := float(e.value)
	match e.stat:
		"cooldown":
			return e.op == "mul" and v > 0.0
		"max_hp", "move_speed", "might", "area", "damage_reduction", "regen", "luck":
			return (e.op == "mul" or e.op == "add") and v < 0.0
	return false


## One effect line. A line reads "+8 thorns damage a rank. Trade: cooldowns 4% longer." (its harmful effect said once,
## in its own words); everything else is the generated text the old cards had.
static func effect(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	if def is LineDef:
		var ld := def as LineDef
		var ranked := not bool(card.get("evolve", false)) and ld.evolves_from == ""
		var lvl := 1 if bool(card.get("evolve", false)) else maxi(int(card.get("level_to", 1)), 1)
		var effs: Array = ld.effects_at_level(lvl) if ranked else ld.effects_for_level(1)
		if int(card.get("level_from", 0)) == 0 and ld.text != "" and ranked:
			return ld.text
		var good: Array = []
		for e in effs:
			if ld.trade == "" or not _harms(e):
				good.append(e)
		var s := TextGen.describe_effects(good) + (" a rank" if ranked else "")
		s = s.substr(0, 1).to_upper() + s.substr(1) if s.begins_with("+") == false else s
		if ld.trade != "":
			s += ". Trade: " + ld.trade.trim_suffix(" a rank") + "."
		else:
			s += "."
		return ("Next: " + s) if int(card.get("level_from", 0)) > 0 and ranked else s
	var d := UiKit.card_description(card)
	return d


static func rarity(def: ContentDef) -> String:
	return W.rarity_of(def)


## The WCard options for an offer card, at the level-up's sizes (override with `extra`).
static func options(card: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var def: ContentDef = card["def"]
	var o := {
		"word": word(card), "word_color": word_color(card), "stars": stars(card), "effect": effect(card),
		"rarity": "", "plate_px": 180.0, "icon_frac": 0.68,
		"evolution": kind(def) == "evolution" or bool(card.get("evolve", false)),
	}
	if bool(card.get("evolve", false)):
		o["plate_fill"] = W.EMBER
	for k in extra:
		o[k] = extra[k]
	return o
