## Builds level-up and starter card offers from the Registry and the current run build.
## A card: {"type": "weapon"|"passive"|"mutation"|"line"|"perk", "id", "def", "level_from", "level_to", "is_new"}
class_name CardPool
extends RefCounted

const RARITY_W := {"common": 1.0, "rare": 0.55, "epic": 0.25}


## `exclude` keeps ids already on the table out of a partial redraw (a banish replaces one card, not the offer).
## Four kinds of card share a level-up (pass 26/27): weapons (a new one only under the stage's cap, at most one), passives,
## lines (at most one; only ranks once two are open) and the hero's perks (at most one in five offers). Mutations have
## their own table at the stage's path slots (path_offer).
static func level_up_offer(count: int = 3, exclude: Array = []) -> Array:
	var cands: Array = []
	var weapon_slot_free := Run.weapons.size() < Run.weapon_cap()
	var passive_slot_free := Run.passives.size() < Run.MAX_PASSIVES
	for w in Registry.unlocked_weapons():
		if Run.banished.has(w.id) or exclude.has(w.id) or not stage_open(w):
			continue
		var inst := Run.weapon_instance(w.id)
		if inst == null:
			if weapon_slot_free:
				cands.append(_card("weapon", w, 0, 1, _weight(w, false)))
		elif inst.level < w.max_level and not inst.def.is_evolution:
			cands.append(_card("weapon", w, inst.level, inst.level + 1, _weight(w, true)))
	for p in Registry.unlocked_passives():
		if Run.banished.has(p.id) or exclude.has(p.id) or not stage_open(p):
			continue
		var lv := int(Run.passives.get(p.id, 0))
		if lv == 0:
			if passive_slot_free:
				cands.append(_card("passive", p, 0, 1, _weight(p, false)))
		elif lv < p.max_level:
			cands.append(_card("passive", p, lv, lv + 1, _weight(p, true)))
	var lines_full := Run.lines.size() >= Run.line_cap()
	for l: LineDef in open_lines():
		if Run.banished.has(l.id) or exclude.has(l.id) or not stage_open(l):
			continue
		var r := Run.line_rank(l.id)
		if r == 0:
			if not lines_full:
				cands.append(_card("line", l, 0, 1, _weight(l, false)))
		elif r < l.max_level:
			cands.append(_card("line", l, r, r + 1, _weight(l, true)))
		elif l.evolves_into != "" and Registry.line(l.evolves_into) != null:
			# a maxed line evolves (pass 33.2): its evolution comes as the offer's line card, heavily weighted
			var evo: LineDef = Registry.line(l.evolves_into)
			var ec := _card("line", evo, r, r + 1, _weight(l, true) * 3.0)
			ec["evolve"] = true
			ec["src_id"] = l.id
			cands.append(ec)
	if Run.character and Run.perk_gap >= 5:
		for pk: PerkDef in Registry.perks_of(Run.character.id):
			if not Run.perks.has(pk.id) and not Run.banished.has(pk.id) and not exclude.has(pk.id):
				cands.append(_card("perk", pk, 0, 1, _weight(pk, false) * 4.0))
	var out := _pick(cands, count, {"weapon_new": 1, "line": 1, "perk": 1})
	if exclude.is_empty():
		Run.note_offer(out)
	return out


## The base lines a run may be offered: the content listing less the ones behind an unlock quest (pass 44).
static func open_lines() -> Array:
	return Registry.sorted_lines().filter(func(l: LineDef) -> bool: return Registry.is_unlocked("line", l.id))


## Whether the run's stage has reached an item's `from_stage` (pass 43: the hell items are stage 3's alone).
static func stage_open(def: ContentDef) -> bool:
	return def.from_stage <= 0 or Run.stage + 1 >= def.from_stage


## Which limited category a card falls in, "" for none.
static func _category(c: Dictionary) -> String:
	match str(c["type"]):
		"weapon":
			return "weapon_new" if bool(c.get("is_new", false)) else ""
		"line":
			return "line"
		"perk":
			return "perk"
	return ""


## A path that has missed two offers in a row gets one of its mutations in place of the offer's lightest card.
static func _force_mutation(out: Array, cands: Array) -> void:
	for inst in Run.weapons:
		var fam: String = inst.family_id()
		if int(Run.mutation_misses.get(fam, 0)) < 2:
			continue
		var present := false
		for c in out:
			if c["type"] == "mutation" and (c["def"] as MutationDef).weapon == fam:
				present = true
		if present:
			continue
		var pool: Array = cands.filter(func(c): return c["type"] == "mutation" and (c["def"] as MutationDef).weapon == fam and not out.has(c))
		if pool.is_empty() or out.is_empty():
			continue
		var lightest := 0
		for k in range(1, out.size()):
			if float(out[k]["weight"]) < float(out[lightest]["weight"]):
				lightest = k
		out[lightest] = pool[randi() % pool.size()]
		return


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


static func starter_offer(fixed_ids: Array = []) -> Array:
	var out: Array = []
	if not fixed_ids.is_empty():
		for id in fixed_ids:
			var w := Registry.weapon(id)
			if w:
				out.append(_card("weapon", w, 0, 1, 1.0))
		return out
	var cands: Array = []
	var fav := ""
	if Run.character:
		fav = Run.character.favourite_weapon
	for w in Registry.unlocked_weapons():
		if w.id == fav:
			continue
		cands.append(_card("weapon", w, 0, 1, _weight(w, false)))
	var favw := Registry.weapon(fav)
	if favw:
		var c := _card("weapon", favw, 0, 1, 1.0)
		c["favourite"] = true
		out.append(c)
	var rest := _pick(cands, 3 - out.size())
	out.append_array(rest)
	out.shuffle()
	return out


static func _weight(def: ContentDef, owned: bool) -> float:
	var w := float(def.weight) * float(RARITY_W.get(def.rarity, 1.0))
	if owned:
		w *= 1.5
	var luck: float = Run.player_sheet.get_stat("luck", 0.0)
	if def.rarity != "common":
		w *= 1.0 + luck
	return max(w, 0.01)


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
		# a limited category (one new weapon, one line, one perk an offer) empties from the pool once it is full
		var cat := _category(chosen)
		if cat != "" and limits.has(cat):
			used[cat] = int(used.get(cat, 0)) + 1
			if used[cat] >= int(limits[cat]):
				pool = pool.filter(func(c): return _category(c) != cat)
	return out


static func bonus_card_chance() -> float:
	return clamp(Run.player_sheet.get_stat("luck", 0.0) * 0.5, 0.0, 0.6)


## Apply a chosen card to the run. Returns a human line for the toast.
static func apply(card: Dictionary) -> String:
	if card["type"] == "weapon":
		var def: WeaponDef = card["def"]
		if Run.has_weapon(def.id):
			Run.level_weapon(def.id)
		else:
			var inst := Run.add_weapon(def, 1)
			if inst and Run.character and Run.character.favourite_weapon == def.id:
				_apply_favourite(inst)
		var inst2 := Run.weapon_instance(def.id)
		return "%s Lv %d" % [def.display_name, inst2.level if inst2 else 1]
	elif card["type"] == "mutation":
		var mdef: MutationDef = card["def"]
		Run.add_mutation(mdef.id)
		return mdef.display_name
	elif card["type"] == "line":
		var ldef: LineDef = card["def"]
		if bool(card.get("evolve", false)):
			Run.evolve_line(str(card.get("src_id", "")))
			return "%s evolved" % ldef.display_name
		Run.add_or_rank_line(ldef.id)
		return "%s rank %d" % [ldef.display_name, Run.line_rank(ldef.id)]
	elif card["type"] == "perk":
		var pdef: PerkDef = card["def"]
		Run.add_perk(pdef.id)
		return pdef.display_name
	else:
		var def: PassiveDef = card["def"]
		Run.add_or_level_passive(def.id)
		return "%s Lv %d" % [def.display_name, int(Run.passives.get(def.id, 1))]


static func _apply_favourite(inst: WeaponInstance) -> void:
	var b: Dictionary = Run.character.favourite_bonus
	match str(b.get("type", "")):
		"level":
			inst.level = clamp(int(b.get("value", 2)), 1, inst.def.max_level)
		"effects":
			var eff = b.get("effects", [])
			if eff is Array:
				inst.bonus_effects = eff
	inst.rebuild(Run.player_sheet, Run.weapons)
