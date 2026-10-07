## What a Wanted card says about an item, from an offer card ({def, level_from, level_to, evolve, ...}): the kind in one
## word (in the kind's colour: WEAPON, LINE, PASSIVE since pass 47), the stars and the one effect line. A passive item's
## rarity is its plate's colour, never a seal or a word. No level chips or flavour lines on in-run cards.
## Used by the level-up, path, chest, shop and Stranger screens.
## Pass 58 (Garry: "There should be some kind of an indicator on items when they are upgraded rather than a new item ...
## Maybe the new star is pulsating in an animated way. Maybe there's a word "upgrade." ... Maybe we show which stats are
## actually changing as well with the upgrade"): a tag beside the kind's word says UPGRADE, NEW or EVOLUTION (tag), an
## upgrade lists the stats it changes before and after (changes) in place of its "Next:" line, and its new stars pulse.
class_name WItem
extends RefCounted

## The tag's colours (pass 58): an upgrade in brass (it builds on what the hero holds), a new item in sage, an
## evolution in its own ember.
const TAG_COLORS := {"UPGRADE": W.BRASS, "NEW": W.SAGE, "EVOLUTION": W.EMBER}


static func kind(def: ContentDef) -> String:
	return W.kind_of(def)


## The kind in one word (pass 58: the tag beside it says NEW or UPGRADE, and the stars the levels, so the word no
## longer carries "NEW" or "LV 2 → 3"); an evolution names what it evolves.
static func word(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	match kind(def):
		"weapon":
			return "WEAPON"
		"evolution":
			var reg := W.node("Registry")
			var from := str(card.get("src_id", (def as WeaponDef).evolved_from))
			var src = reg.weapon(from) if reg and from != "" else null
			return "EVOLVES " + src.display_name.to_upper() if src else "EVOLUTION"
		"line", "passive":
			var what := "LINE" if kind(def) == "line" else "PASSIVE"
			if bool(card.get("evolve", false)):
				var src = W.node("Registry").passive((def as PassiveDef).evolves_from)
				return "EVOLVES " + (src.display_name.to_upper() if src else "A " + what)
			return what
		"perk":
			var hero = W.node("Registry").character((def as PerkDef).hero)
			return "%s'S PERK · ONCE" % (hero.display_name.to_upper() if hero else "HERO")
		"mutation":
			return "HERO MUTATION" if (def as MutationDef).is_hero() else "MUTATION"
	return ""


## The card's tag (pass 58): UPGRADE for a weapon, a line or a passive item the hero holds (level_from past 0), NEW for
## one he does not, EVOLUTION for a weapon's evolution or a maxed line's; "" for a mutation or a perk (unchanged).
static func tag(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	var k := kind(def)
	if k == "evolution" or bool(card.get("evolve", false)) or W.is_evolved(def):
		return "EVOLUTION"
	if k in ["weapon", "line", "passive"]:
		return "UPGRADE" if int(card.get("level_from", 0)) > 0 else "NEW"
	return ""


static func tag_color(t: String) -> Color:
	return TAG_COLORS.get(t, W.BRASS)


## What this pick changes (pass 58): an upgrade of a weapon, a line or a passive item lists the stats it moves, before
## and after (TextGen.weapon_changes on the hero's own copy of the weapon and his sheet, TextGen.passive_changes), at most
## four rows; a new item, an evolution, a mutation and a perk list none and keep their one line.
static func changes(card: Dictionary) -> Array:
	var def: ContentDef = card["def"]
	var lf := int(card.get("level_from", 0))
	var lt := int(card.get("level_to", 1))
	if lf <= 0 or lt <= lf or bool(card.get("evolve", false)) or W.is_evolved(def):
		return []
	if def is WeaponDef:
		var run := W.node("Run")
		var held: WeaponInstance = run.call("weapon_instance", def.id) if run else null
		var sheet: StatSheet = run.get("player_sheet") if run else null
		var all: Array = run.get("weapons") if run and run.get("weapons") is Array else []
		return TextGen.weapon_changes(def as WeaponDef, lf, lt, held, sheet, all)
	if def is PassiveDef:
		return TextGen.passive_changes(def as PassiveDef, lf, lt)
	return []


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
## line the dark plate in the brass ring like every evolution (the ember plate is gone). Pass 58: the tag (UPGRADE, NEW,
## EVOLUTION) and an upgrade's change rows, shown by the card in place of its effect line.
static func options(card: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var def: ContentDef = card["def"]
	var o := {
		"word": word(card), "word_color": word_color(card), "stars": stars(card), "effect": effect(card),
		"rarity": "", "plate_px": 180.0, "icon_frac": 0.68,
		"evolution": kind(def) == "evolution" or bool(card.get("evolve", false)),
		"level": level_of(card), "dots": WPlate.path_of(def), "dots_ready": WPlate.ready_of(def),
		"tag": tag(card), "changes": changes(card),
	}
	for k in extra:
		o[k] = extra[k]
	# an upgrade shown without its stars (the shop's cards) says its step in the word, as every card did before pass 58
	# (pass 58 review: the shop's Hammer 2 → 3 showed no level anywhere)
	var lf := int(card.get("level_from", 0))
	if lf > 0 and (o.get("stars", []) as Array).is_empty() and stars(card).size() >= 2:
		o["word"] = "%s · LV %d → %d" % [str(o["word"]), lf, maxi(int(card.get("level_to", lf + 1)), lf + 1)]
	return o


## What a card shows under its name, as one line of plain text (pass 58 review: the arena's INFO quotes "the level-up
## card", which shows an upgrade's change rows, not its "Next:" line): "Damage 9.6 → 11.5 · Cooldown 0.90 s → 0.81 s"
## for an upgrade, else its effect line.
static func card_text(card: Dictionary) -> String:
	var rows := changes(card)
	if rows.is_empty():
		return effect(card)
	var parts: Array = []
	for r: Dictionary in rows:
		parts.append("%s %s → %s" % [str(r["name"]), str(r["before"]), str(r["after"])])
	return " · ".join(parts)
