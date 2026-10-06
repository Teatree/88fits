## Builds level-up and path card offers from the Registry and the current run build.
## A card: {"type": "weapon"|"passive"|"mutation"|"perk", "id", "def", "level_from", "level_to", "is_new", "weight"}, and
## on a passive's evolution "evolve": true with "src_id" (the passive it replaces), on the hero's favourite weapon or
## passive "favourite": true (the card says so).
##
## How likely an item is (pass 47, the one formula for level-up cards and chests; Run.chest_roll draws with it too):
##   weight = def.weight
##          x RARITY_W[rarity]                      common 1.0, uncommon 0.75, rare 0.55, epic 0.3, legendary 0.15
##          x (1 + luck x LUCK_TIER[rarity])        luck lifts the higher tiers: common 0, uncommon 0.5, rare 1,
##                                                  epic 1.5, legendary 2 (Clover adds 0.1 luck a level)
##          x HELD_WEIGHT (1.5)                     when it is already held (a level of it)
##          x LEVEL_DECAY ^ (level_from - 1)        when held: every level already taken past the first makes the next
##                                                  one 0.88 times as likely (Garry: "every consecutive Upgrade of an
##                                                  item slightly less likely to drop in Chests or Level Ups")
##          x EVOLVE_WEIGHT (3)                     on a maxed line's evolution card (its source's weight and level)
##   A perk's card is weighed x4 on top (at most one in five offers, Run.perk_gap). An offer draws its cards one at a
##   time in proportion to these weights, without putting a drawn card back (_pick).
class_name CardPool
extends RefCounted

## The rarity tiers' share of an offer (pass 47: five tiers; the single table, Run reads it through weight_of).
const RARITY_W := {"common": 1.0, "uncommon": 0.75, "rare": 0.55, "epic": 0.3, "legendary": 0.15}
## How much luck lifts each tier: weight x (1 + luck x this).
const LUCK_TIER := {"common": 0.0, "uncommon": 0.5, "rare": 1.0, "epic": 1.5, "legendary": 2.0}
## Each level already held past the first makes the next one this much as likely.
const LEVEL_DECAY := 0.88
## A held item's card against a new one's.
const HELD_WEIGHT := 1.5
## A maxed line's evolution card against a plain level of it.
const EVOLVE_WEIGHT := 3.0


## `exclude` keeps ids already on the table out of a partial redraw (a banish replaces one card, not the offer).
## Three kinds of card share a level-up (pass 26/27, pass 46, pass 47): weapons (a new one only while a weapon slot is
## free, at most one an offer), lines and passive items (pass 47: a new line only while a line slot is free, a passive
## item always, there is no cap on them; a maxed line offers its evolution instead) and the hero's perks (at most one in
## five offers). Mutations have their own table at the stage's path slots (path_offer). A weapon or passive already held
## is levelled whatever its unlock quest (Ironwood lands with the Spear, the pike, which may still be locked).
static func level_up_offer(count: int = 3, exclude: Array = []) -> Array:
	var cands: Array = []
	var weapon_slot_free := Run.weapons.size() < Run.weapon_cap()
	var line_slot_free := Run.held_lines().size() < Run.line_cap()
	for w: WeaponDef in offer_weapons():
		if Run.banished.has(w.id) or exclude.has(w.id) or not stage_open(w):
			continue
		var inst := Run.weapon_instance(w.id)
		if inst == null:
			if weapon_slot_free:
				cands.append(_favourite(_card("weapon", w, 0, 1, weight_of(w, 0))))
		elif inst.level < w.max_level and not inst.def.is_evolution:
			cands.append(_card("weapon", w, inst.level, inst.level + 1, weight_of(w, inst.level)))
	# base passives only: an evolved one comes as its source's evolution card, never on its own
	for p: PassiveDef in offer_passives():
		if Run.banished.has(p.id) or exclude.has(p.id) or not stage_open(p):
			continue
		# spent: its evolution took its slot
		if p.evolves_into != "" and Run.passives.has(p.evolves_into):
			continue
		var lv := Run.passive_level(p.id)
		if lv == 0:
			if line_slot_free or not p.is_line():
				cands.append(_favourite(_card("passive", p, 0, Run.first_passive_level(p), weight_of(p, 0))))
		elif lv < p.max_level:
			cands.append(_card("passive", p, lv, lv + 1, weight_of(p, lv)))
		elif p.evolves_into != "":
			# a maxed line evolves (pass 33.2): its evolution comes as a card of its own, weighted three times, and takes
			# the source's slot
			var evo: PassiveDef = Registry.passive(p.evolves_into)
			if evo and not Run.banished.has(evo.id) and not exclude.has(evo.id):
				var ec := _card("passive", evo, lv, lv + 1, weight_of(p, lv, true))
				ec["evolve"] = true
				ec["src_id"] = p.id
				cands.append(ec)
	if Run.character and Run.perk_gap >= 5:
		for pk: PerkDef in Registry.perks_of(Run.character.id):
			if not Run.perks.has(pk.id) and not Run.banished.has(pk.id) and not exclude.has(pk.id):
				cands.append(_card("perk", pk, 0, 1, weight_of(pk, 0) * 4.0))
	var out := _pick(cands, count, {"weapon_new": 1, "perk": 1})
	if exclude.is_empty():
		Run.note_offer(out)
	return out


## The weight of one card (pass 47): the formula at the top of this file. `level_from` is the level held (0 = new);
## `evolve` weighs a maxed line's evolution card (pass the source and its level).
static func weight_of(def: ContentDef, level_from: int = 0, evolve: bool = false) -> float:
	if def == null:
		return 0.0
	var w := float(def.weight) * float(RARITY_W.get(def.rarity, 1.0)) * luck_boost(def.rarity)
	if level_from > 0:
		w *= HELD_WEIGHT * pow(LEVEL_DECAY, float(level_from - 1))
	if evolve:
		w *= EVOLVE_WEIGHT
	return maxf(w, 0.01)


## How much the run's luck lifts a tier: 1 + luck x LUCK_TIER (common never moves).
static func luck_boost(rarity: String) -> float:
	return 1.0 + Run.player_sheet.get_stat("luck", 0.0) * float(LUCK_TIER.get(rarity, 0.0))


## The base weapons a level-up (or the Stranger) may hold: those the run may be offered (Registry.unlocked_weapons) and
## every base weapon already held, whatever its unlock quest.
static func offer_weapons() -> Array:
	var out: Array = Registry.unlocked_weapons()
	for inst: WeaponInstance in Run.weapons:
		if not inst.def.is_evolution and not out.has(inst.def):
			out.append(inst.def)
	return out


## The base lines and passive items an offer may hold: the unlocked ones (Registry.unlocked_passives), every base one
## already held, whatever its unlock quest, and the run hero's favourite passive (pass 54: Solenne finds Haste from her
## first level-up, though for everyone else it waits behind its quest).
static func offer_passives() -> Array:
	var out: Array = Registry.unlocked_passives()
	for pid in Run.passives.keys():
		var p: PassiveDef = Registry.passive(str(pid))
		if p and not p.is_evolved() and not out.has(p):
			out.append(p)
	if Run.character and Run.character.favourite_passive != "":
		var fav: PassiveDef = Registry.passive(Run.character.favourite_passive)
		if fav and not fav.hidden and not fav.is_evolved() and not out.has(fav):
			out.append(fav)
	return out


## One card drawn from `cands` in proportion to their "weight" ({} when there is none): a chest's roll (Run.chest_roll).
static func pick_one(cands: Array) -> Dictionary:
	var one := _pick(cands, 1)
	return one[0] if not one.is_empty() else {}


## A new card for the hero's favourite weapon or passive says so (CardScreen adds " · FAVOURITE" to its word).
static func _favourite(card: Dictionary) -> Dictionary:
	if Run.is_favourite(card["def"]):
		card["favourite"] = true
	return card


## Whether the run's stage has reached an item's `from_stage` (pass 43: the hell items are stage 3's alone).
static func stage_open(def: ContentDef) -> bool:
	return def.from_stage <= 0 or Run.stage + 1 >= def.from_stage


## Which limited category a card falls in, "" for none.
static func _category(c: Dictionary) -> String:
	match str(c["type"]):
		"weapon":
			return "weapon_new" if bool(c.get("is_new", false)) else ""
		"perk":
			return "perk"
	return ""


## A weapon's path on the table (pass 27): every open path mutation as a card, and the hero's own option for that
## weapon after them. Shown at the stage's path slots, never mixed into a level-up.
static func path_offer(w: WeaponInstance) -> Array:
	var out: Array = []
	var hero: Array = []
	for m: MutationDef in Run.open_mutations(w):
		if Run.banished.has(m.id):
			continue
		var c := _card("mutation", m, 0, 1, 1.0)
		if m.is_hero():
			hero.append(c)
		else:
			out.append(c)
	out.append_array(hero)
	return out


static func _card(type: String, def: ContentDef, from: int, to: int, weight: float) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": weight}


static func _pick(cands: Array, count: int, limits: Dictionary = {}) -> Array:
	var out: Array = []
	var pool := cands.duplicate()
	var used: Dictionary = {}
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += float(c["weight"])
		var r := randf() * total
		var chosen: Dictionary = pool[0]
		for c in pool:
			r -= float(c["weight"])
			if r <= 0.0:
				chosen = c
				break
		out.append(chosen)
		pool.erase(chosen)
		# a limited category (one new weapon, one perk an offer) empties from the pool once it is full
		var cat := _category(chosen)
		if cat != "" and limits.has(cat):
			used[cat] = int(used.get(cat, 0)) + 1
			if used[cat] >= int(limits[cat]):
				pool = pool.filter(func(c): return _category(c) != cat)
	return out



## Apply a chosen card to the run. Returns a human line for the toast.
static func apply(card: Dictionary) -> String:
	if card["type"] == "weapon":
		var def: WeaponDef = card["def"]
		if Run.has_weapon(def.id):
			Run.level_weapon(def.id)
		else:
			var inst := Run.add_weapon(def, 1)
			if inst and Run.character and Run.character.favourite_weapon == def.id:
				apply_favourite(inst)
		var inst2 := Run.weapon_instance(def.id)
		return "%s Lv %d" % [def.display_name, inst2.level if inst2 else 1]
	elif card["type"] == "mutation":
		var mdef: MutationDef = card["def"]
		Run.add_mutation(mdef.id)
		return mdef.display_name
	elif card["type"] == "perk":
		var pdef: PerkDef = card["def"]
		Run.add_perk(pdef.id)
		return pdef.display_name
	else:
		var def: PassiveDef = card["def"]
		if bool(card.get("evolve", false)):
			# the evolution takes its source's slot (Run.evolve_passive)
			Run.evolve_passive(str(card.get("src_id", "")))
			return "%s evolved" % def.display_name
		Run.add_or_level_passive(def.id)
		return "%s Lv %d" % [def.display_name, Run.passive_level(def.id)]


## The favourite's bonus (CharacterDef.favourite_bonus): a level, or effects folded into the instance; also when the run
## starts with it (pass 45: a launch file naming the favourite).
static func apply_favourite(inst: WeaponInstance) -> void:
	var b: Dictionary = Run.character.favourite_bonus
	match str(b.get("type", "")):
		"level":
			inst.level = clamp(int(b.get("value", 2)), 1, inst.def.max_level)
		"effects":
			var eff = b.get("effects", [])
			if eff is Array:
				inst.bonus_effects = eff
	inst.rebuild(Run.player_sheet, Run.weapons)
