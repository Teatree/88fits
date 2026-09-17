## Builds level-up and starter card offers from the Registry and the current run build.
## A card: {"type": "weapon"|"passive", "id", "def", "level_from", "level_to", "is_new"}
class_name CardPool
extends RefCounted

const RARITY_W := {"common": 1.0, "rare": 0.55, "epic": 0.25}


static func level_up_offer(count: int = 3) -> Array:
	var cands: Array = []
	var weapon_slot_free := Run.weapons.size() < Run.MAX_WEAPONS
	var passive_slot_free := Run.passives.size() < Run.MAX_PASSIVES
	for w in Registry.unlocked_weapons():
		if Run.banished.has(w.id) or not Run.element_allowed(w):
			continue
		var inst := Run.weapon_instance(w.id)
		if inst == null:
			if weapon_slot_free:
				cands.append(_card("weapon", w, 0, 1, _weight(w, false)))
		elif inst.level < w.max_level and not inst.def.is_evolution:
			cands.append(_card("weapon", w, inst.level, inst.level + 1, _weight(w, true)))
	for p in Registry.unlocked_passives():
		if Run.banished.has(p.id) or not Run.element_allowed(p):
			continue
		var lv := int(Run.passives.get(p.id, 0))
		if lv == 0:
			if passive_slot_free:
				cands.append(_card("passive", p, 0, 1, _weight(p, false)))
		elif lv < p.max_level:
			cands.append(_card("passive", p, lv, lv + 1, _weight(p, true)))
	return _pick(cands, count)


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


static func _pick(cands: Array, count: int) -> Array:
	var out: Array = []
	var pool := cands.duplicate()
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
