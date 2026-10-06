## What a Wanted card says about an item, from an offer card ({def, level_from, level_to, evolve, ...}): the kind in one
## word (in the kind's colour: WEAPON, LINE, PASSIVE since pass 47), the stars and the one effect line. A passive item's
## rarity is its plate's colour, never a seal or a word. No kind tags, level chips or flavour lines on in-run cards.
## Used by the level-up, path, chest, shop and Stranger screens.
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
		"line", "passive":
			var what := "LINE" if kind(def) == "line" else "PASSIVE"
			if bool(card.get("evolve", false)):
				var src = W.node("Registry").passive((def as PassiveDef).evolves_from)
				return "EVOLVES " + (src.display_name.to_upper() if src else "A " + what)
			return ("%s · LV %d → %d" % [what, lf, lt]) if lf > 0 else "NEW " + what
		"perk":
			var hero = W.node("Registry").character((def as PerkDef).hero)
			return "%s'S PERK · ONCE" % (hero.display_name.to_upper() if hero else "HERO")
		"mutation":
			return "HERO MUTATION" if (def as MutationDef).is_hero() else "MUTATION"
	return ""


static func word_color(card: Dictionary) -> Color:
	var def: ContentDef = card["def"]
	var k := kind(def)
	if (k == "passive" or k == "line") and bool(card.get("evolve", false)):
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


## Whether an effect is the price a passive charges (less health or speed, longer cooldowns).
static func _harms(e: Effect) -> bool:
	var v := float(e.value)
	match e.stat:
		"cooldown":
			return e.op == "mul" and v > 0.0
		"max_hp", "move_speed", "might", "area", "damage_reduction", "regen", "luck":
			return (e.op == "mul" or e.op == "add") and v < 0.0
	return false


## One effect line. A passive reads "+8 thorns damage a level. Trade: cooldowns 4% longer." (its harmful effect said
## once, in its own words; "a level" when every level gives the same), an upgrade "Next: ...", a new one landing past
## level 1 (the Stranger's, the hero's favourite) what it holds there in total, an evolved one all it is; everything else
## is the generated text the old cards had.
static func effect(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	if def is PassiveDef:
		var pd := def as PassiveDef
		var lf := int(card.get("level_from", 0))
		var lt := maxi(int(card.get("level_to", 1)), 1)
		var whole := bool(card.get("evolve", false)) or pd.is_evolved()
		var ranked := not whole and not (lf == 0 and lt > 1)
		if lf == 0 and pd.text != "" and not whole:
			return pd.text
		var effs: Array = pd.effects_at_level(lt) if ranked else TextGen._sum_effects(pd.effects_for_level(1 if whole else lt))
		var good: Array = []
		var ceiling := false
		for e in effs:
			if pd.trade == "" or not _harms(e):
				good.append(e)
			# a stat that reads as a ceiling ("up to +12% attack damage as health falls") takes no "a level"
			if e is Effect and TextGen.PREFIX.has((e as Effect).stat):
				ceiling = true
		var s := TextGen.describe_effects(good) + (" a level" if ranked and pd.levels.size() <= 1 and not ceiling else "")
		if pd.trade != "":
			s += ". Trade: " + pd.trade.trim_suffix(" a level") + "."
		else:
			s += "."
		if lf > 0 and ranked:
			return "Next: " + s
		return s.substr(0, 1).to_upper() + s.substr(1)
	var d := UiKit.card_description(card)
	return d


static func rarity(def: ContentDef) -> String:
	return W.rarity_of(def)


## The level a card's plate shows (pass 48: a weapon or a line takes its level's colour): the level the pick lands on.
static func level_of(card: Dictionary) -> int:
	return maxi(int(card.get("level_to", 1)), 0)


## The WCard options for an offer card, at the level-up's sizes (override with `extra`). The plate takes the level the
## pick lands on (pass 48), a weapon its mutation dots (WPlate.path_of; the glow when it is ready to evolve), an evolved
## line the dark plate in the brass ring like every evolution (the ember plate is gone).
static func options(card: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var def: ContentDef = card["def"]
	var o := {
		"word": word(card), "word_color": word_color(card), "stars": stars(card), "effect": effect(card),
		"rarity": "", "plate_px": 180.0, "icon_frac": 0.68,
		"evolution": kind(def) == "evolution" or bool(card.get("evolve", false)),
		"level": level_of(card), "dots": WPlate.path_of(def), "dots_ready": WPlate.ready_of(def),
	}
	for k in extra:
		o[k] = extra[k]
	return o
