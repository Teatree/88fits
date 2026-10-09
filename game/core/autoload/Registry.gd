## Scans res://content/** at boot and holds every content definition by type.
## Prefers <id>.tres; falls back to <id>.json through JsonContent. Never hard-codes content.
extends Node

const CONTENT_ROOT := "res://content/"

var weapons: Dictionary = {}     # includes evolutions
var passives: Dictionary = {}    # includes the evolved ones (pass 46: the lines folded in)
var mutations: Dictionary = {}   # a weapon's path (three picks) and the hero mutations
var perks: Dictionary = {}       # one per hero
var enemies: Dictionary = {}     # includes bosses
var elites: Dictionary = {}
var characters: Dictionary = {}
var talents: Dictionary = {}
var quests: Dictionary = {}
var maps: Dictionary = {}
var pickups: Dictionary = {}
var structures: Dictionary = {}
var buildings: Dictionary = {}
var soundmap: SoundMap = SoundMap.new()
var missing_icons: Array = []
var problems: Array = []
var scanned := false


func _ready() -> void:
	scan()


func scan() -> void:
	weapons.clear(); passives.clear(); mutations.clear(); perks.clear(); enemies.clear(); elites.clear()
	characters.clear(); talents.clear(); quests.clear(); maps.clear(); pickups.clear(); structures.clear()
	missing_icons.clear(); problems.clear(); _enemy_cache.clear()
	for type: String in JsonContent.TYPES:
		_scan_type(type)
	_load_soundmap()
	_validate()
	scanned = true
	print("Registry: %d weapons, %d passives, %d enemies, %d elites, %d characters, %d talents, %d quests, %d maps, %d sounds" % [
		weapons.size(), passives.size(), enemies.size(), elites.size(), characters.size(), talents.size(), quests.size(), maps.size(), soundmap.entries.size()])


func _scan_type(type: String) -> void:
	var base := CONTENT_ROOT + type + "/"
	var dir := DirAccess.open(base)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		var folder := base + sub + "/"
		var res := _load_item(type, folder, sub)
		if res == null:
			problems.append("%s: could not load %s" % [type, folder])
			continue
		if res.id == "":
			res.id = sub
		_store(type, res)


func _load_item(type: String, folder: String, id: String) -> ContentDef:
	var tres := folder + id + ".tres"
	var json := folder + id + ".json"
	var res: ContentDef = null
	if ResourceLoader.exists(tres):
		var r = load(tres)
		if r is ContentDef:
			res = r
	if res == null and FileAccess.file_exists(json):
		res = JsonContent.build(type, JsonContent.load_json(json), folder)
	if res == null:
		return null
	res.source_dir = folder
	if res.icon == null and res.icon_file != "":
		res.icon = JsonContent.resolve_texture(folder, res.icon_file)
	if res.icon == null:
		missing_icons.append(id)
	return res


func _store(type: String, res: ContentDef) -> void:
	match type:
		"weapons", "evolutions":
			weapons[res.id] = res
		"passives":
			passives[res.id] = res
		"mutations":
			mutations[res.id] = res
		"perks":
			perks[res.id] = res
		"enemies", "bosses":
			enemies[res.id] = res
		"elites":
			elites[res.id] = res
		"characters":
			characters[res.id] = res
		"talents":
			talents[res.id] = res
		"quests":
			quests[res.id] = res
		"maps":
			maps[res.id] = res
		"pickups":
			pickups[res.id] = res
		"structures":
			structures[res.id] = res
		"buildings":
			buildings[res.id] = res


func _load_soundmap() -> void:
	var folder := CONTENT_ROOT + "sounds/"
	var tres := folder + "soundmap.tres"
	var json := folder + "soundmap.json"
	if ResourceLoader.exists(tres):
		var r = load(tres)
		if r is SoundMap:
			soundmap = r
			# streams may be unresolved if the .tres predates the wav import
			for id in soundmap.entries.keys():
				var row: Dictionary = soundmap.entries[id]
				if row.get("stream") == null:
					var p: String = row.get("file", "")
					var path: String = p if p.begins_with("res://") else folder + p
					if ResourceLoader.exists(path):
						row["stream"] = load(path)
			return
	if FileAccess.file_exists(json):
		soundmap = JsonContent.soundmap_from_dict(JsonContent.load_json(json), folder)


func _validate() -> void:
	for w in weapons.values():
		if w.evolves_into != "" and not weapons.has(w.evolves_into):
			problems.append("weapon %s evolves into missing %s" % [w.id, w.evolves_into])
		if w.evolves_with != "" and not passives.has(w.evolves_with):
			problems.append("weapon %s needs missing passive %s" % [w.id, w.evolves_with])
	# a passive's evolution pair names each other (pass 46: the lines' evolutions, now every passive's); pass 47: a line
	# and its evolution are both lines
	for p: PassiveDef in passives.values():
		if p.evolves_into != "" and passives.has(p.evolves_into) and (passives[p.evolves_into] as PassiveDef).is_line() != p.is_line():
			problems.append("passive %s and its evolution %s disagree on being a line" % [p.id, p.evolves_into])
		if p.evolves_into != "":
			var into: PassiveDef = passives.get(p.evolves_into)
			if into == null:
				problems.append("passive %s evolves into missing %s" % [p.id, p.evolves_into])
			elif into.evolves_from != p.id:
				problems.append("passive %s evolves into %s, which says it evolves from '%s'" % [p.id, into.id, into.evolves_from])
		if p.evolves_from != "":
			var src: PassiveDef = passives.get(p.evolves_from)
			if src == null:
				problems.append("passive %s evolves from missing %s" % [p.id, p.evolves_from])
			elif src.evolves_into != p.id:
				problems.append("passive %s evolves from %s, which evolves into '%s'" % [p.id, src.id, src.evolves_into])
	# what a hero names must exist once he is played; a hidden hero may name things still being made (pass 46:
	# Ironwood's spear and Cake come with their own lanes)
	for c: CharacterDef in characters.values():
		if c.hidden:
			continue
		if c.start_weapon != "" and not weapons.has(c.start_weapon):
			problems.append("character %s starts with missing weapon %s" % [c.id, c.start_weapon])
		if c.favourite_weapon != "" and not weapons.has(c.favourite_weapon):
			problems.append("character %s favours missing weapon %s" % [c.id, c.favourite_weapon])
		if c.favourite_passive != "" and not passives.has(c.favourite_passive):
			problems.append("character %s favours missing passive %s" % [c.id, c.favourite_passive])
	for m in maps.values():
		for a in m.skins.keys():
			if not enemies.has(m.skins[a]):
				problems.append("map %s skin %s -> missing enemy %s" % [m.id, a, m.skins[a]])
		if m.boss != "" and not enemies.has(m.boss):
			problems.append("map %s boss missing %s" % [m.id, m.boss])
		if m.timeline:
			for r in m.timeline.pickups.get("roster", []):
				if r is Dictionary and not pickups.has(str(r.get("id", ""))):
					problems.append("map %s pickup roster -> missing pickup %s" % [m.id, str(r.get("id", ""))])
			for sid in m.timeline.structures.get("roster", []):
				if not structures.has(str(sid)):
					problems.append("map %s structure roster -> missing structure %s" % [m.id, str(sid)])
	for p in problems:
		push_warning("Registry: " + p)


# ---------------------------------------------------------------- queries

func weapon(id: String) -> WeaponDef:
	return weapons.get(id)


func mutation(id: String) -> MutationDef:
	return mutations.get(id)


func perk(id: String) -> PerkDef:
	return perks.get(id)


## A path's order: element, volume, motion, then a stance (the turret's fourth), the hero's own last.
const MUTATION_ORDER := {"element": 0, "volume": 1, "motion": 2, "stance": 3, "hero": 4}


## A weapon's path: its three mutations in element, volume, motion order (hero mutations are not part of the path).
func mutations_of(weapon_id: String) -> Array:
	var out: Array = []
	for m: MutationDef in mutations.values():
		if m.weapon == weapon_id and not m.is_hero() and not m.hidden:
			out.append(m)
	out.sort_custom(func(a, b): return int(MUTATION_ORDER.get(a.mutation_kind, 9)) < int(MUTATION_ORDER.get(b.mutation_kind, 9)))
	return out


## The hero mutations a hero is offered (its favourite weapon's extra option). A hidden hero is out of play and so are
## his (pass 46), and a mutation marked hidden is never offered.
func hero_mutations(hero_id: String) -> Array:
	var out: Array = []
	var c: CharacterDef = characters.get(hero_id)
	if c == null or c.hidden:
		return out
	for m: MutationDef in mutations.values():
		if m.hero == hero_id and not m.hidden:
			out.append(m)
	return out


## Every hero's own mutation on a weapon family, the heroes in play only, by hero name (pass 46: the Collection lists
## them on the weapon's page, each marked with the hero who alone can take it).
func weapon_hero_mutations(weapon_id: String) -> Array:
	var out: Array = []
	for m: MutationDef in mutations.values():
		if m.weapon != weapon_id or not m.is_hero() or m.hidden:
			continue
		var c: CharacterDef = characters.get(m.hero)
		if c != null and not c.hidden:
			out.append(m)
	out.sort_custom(func(a: MutationDef, b: MutationDef) -> bool: return _hero_name(a.hero) < _hero_name(b.hero))
	return out


## A hero's shown name (his id when there is no such hero).
func _hero_name(hero_id: String) -> String:
	var c: CharacterDef = characters.get(hero_id)
	return c.display_name if c else hero_id


func perks_of(hero_id: String) -> Array:
	var out: Array = []
	for p: PerkDef in perks.values():
		if p.hero == hero_id and not p.hidden:
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## The base passives, sorted by id: not hidden and not evolved (an evolved passive comes only as the evolution of the
## one it replaces, pass 46). The content listing: an unlock quest does not keep one out of it (unlocked_passives does).
func base_passives() -> Array:
	var out: Array = []
	for p: PassiveDef in passives.values():
		if not p.is_evolved() and not p.hidden:
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## The base line items (pass 47), by id: not hidden, not evolved (an evolved line comes only as its source's evolution).
## The content listing, like base_passives: an unlock quest does not keep one out.
func sorted_lines() -> Array:
	return base_passives().filter(func(p: PassiveDef) -> bool: return p.is_line())


## The passive items (pass 47: content/passives that are not lines), by id, not hidden. The content listing too.
func sorted_passives_only() -> Array:
	return base_passives().filter(func(p: PassiveDef) -> bool: return not p.is_line())


func passive(id: String) -> PassiveDef:
	return passives.get(id)


func enemy(id: String) -> EnemyDef:
	return enemies.get(id)


## Copies of creatures with another art variant and/or stat overrides (pass 53), by their type_key; each entry remembers
## the base def it was made from, so a def swapped under the same id (the tests, a rescan) is never served a stale copy.
var _enemy_cache: Dictionary = {}


## The creature `id` as the wave schema spawns it (pass 53): with art variant `variant` (its own when "" or unknown) and
## the `overrides` of a roster row, a wave alt or an event laid on it (EnemyDef.with_overrides; none when empty). The
## variant comes first, then the overrides, so the key is id[@variant][#hash]; equal asks return the same copy, and so
## one EnemyManager type. Null for an unknown creature.
func enemy_with(id: String, variant := "", overrides := {}) -> EnemyDef:
	var base: EnemyDef = enemies.get(id)
	if base == null:
		return null
	if variant == "" and overrides.is_empty():
		return base
	var vd: EnemyDef = base.variant_def(variant) if variant != "" else base
	var key := vd.type_key()
	if not overrides.is_empty():
		key += "#" + EnemyDef.override_key_of(overrides)
	var hit = _enemy_cache.get(key)
	if hit is Dictionary and (hit as Dictionary).get("base") == base:
		return (hit as Dictionary)["def"]
	var def: EnemyDef = vd.with_overrides(overrides) if not overrides.is_empty() else vd
	_enemy_cache[key] = {"def": def, "base": base}
	return def


func character(id: String) -> CharacterDef:
	return characters.get(id)


func map(id: String) -> MapDef:
	return maps.get(id)


func pickup(id: String) -> PickupDef:
	return pickups.get(id)


func structure(id: String) -> StructureDef:
	return structures.get(id)


func quest_for(type: String, id: String) -> QuestDef:
	for q in quests.values():
		if str(q.unlocks.get("type", "")) == type and str(q.unlocks.get("id", "")) == id:
			return q
	return null


func is_unlocked(type: String, id: String) -> bool:
	var q := quest_for(type, id)
	if q == null:
		return true
	return Save.quest_done(q.id)


## What a quest hands over, as its content item (null for a mode or an unknown kind).
func unlocked_by(q: QuestDef) -> ContentDef:
	var id := str(q.unlocks.get("id", ""))
	match str(q.unlocks.get("type", "")):
		"weapon":
			return weapons.get(id)
		"passive":
			return passives.get(id)
		"character":
			return characters.get(id)
		"map":
			return maps.get(id)
	return null


func base_weapons() -> Array:
	## Non-evolved weapons, sorted by id.
	var out: Array = []
	for w in weapons.values():
		if not w.is_evolution:
			out.append(w)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## The base weapons a run may be offered: not hidden, unlocked, and not another hero's own (WeaponDef.hero).
func unlocked_weapons() -> Array:
	return base_weapons().filter(func(w): return not w.hidden and is_unlocked("weapon", w.id) and hero_may_use(w))


## Whether the hero of the run may take `w` (pass 35: the Revolver is the Drifter's alone); outside a run, anyone may.
func hero_may_use(w: WeaponDef) -> bool:
	if w == null or w.hero == "":
		return true
	var run := get_node_or_null("/root/Run")
	var c = run.get("character") if run else null
	return c == null or str(c.id) == w.hero


## The weapon a hero lands with (pass 45): `start_weapon`, else the first base weapon that is his alone (WeaponDef.hero),
## else his favourite, else the Peashooter; unlock quests do not apply to a hero's own gun.
func start_weapon_for(c: CharacterDef) -> WeaponDef:
	if c and c.start_weapon != "":
		var w := weapon(c.start_weapon)
		if w:
			return w
	if c:
		for bw: WeaponDef in base_weapons():
			if bw.hero == c.id and not bw.hidden:
				return bw
	if c and c.favourite_weapon != "":
		var f := weapon(c.favourite_weapon)
		if f:
			return f
	return weapon("peashooter")


## The passives a run may be offered: base ones only (an evolved passive is its source's evolution card, never one of
## its own), not hidden, unlocked.
func unlocked_passives() -> Array:
	return base_passives().filter(func(p: PassiveDef) -> bool: return is_unlocked("passive", p.id))


func sorted_shop() -> Array:
	var out: Array = talents.values()
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.id < b.id)
	return out


func sorted_buildings() -> Array:
	var out: Array = buildings.values()
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.id < b.id)
	return out


## The building that keeps a permanent upgrade (null when no building lists it: then the upgrade is not gated).
func building_for_upgrade(upgrade_id: String) -> BuildingDef:
	for b in buildings.values():
		if (b as BuildingDef).unlocks.has(upgrade_id):
			return b
	return null


func market() -> BuildingDef:
	for b: BuildingDef in buildings.values():
		if b.is_market:
			return b
	return null


func building(id: String) -> BuildingDef:
	return buildings.get(id)


## The playable heroes in their order (a hidden one is kept in the content but never offered).
func sorted_characters() -> Array:
	var out: Array = characters.values().filter(func(c: CharacterDef) -> bool: return not c.hidden)
	# by the hero's `order` (pass 61, Garry: "The Drifter, Astro, Calavera, Ironwood, Solenne"), then by id
	out.sort_custom(func(a: CharacterDef, b: CharacterDef) -> bool:
		return a.id < b.id if a.order == b.order else a.order < b.order)
	return out


## A hero that may be played: `id` when it is there and not hidden, else Astro (else the first playable one).
func playable_character(id: String) -> CharacterDef:
	var c: CharacterDef = characters.get(id)
	if c and not c.hidden:
		return c
	var a: CharacterDef = characters.get("astro")
	if a and not a.hidden:
		return a
	var all := sorted_characters()
	return all[0] if not all.is_empty() else null


## Whether a quest is shown and tracked: not when what it unlocks is hidden (a hero, a weapon, a passive).
func quest_visible(q: QuestDef) -> bool:
	var what := str(q.unlocks.get("id", ""))
	match str(q.unlocks.get("type", "")):
		"character":
			var c: CharacterDef = characters.get(what)
			return c != null and not c.hidden
		"weapon":
			return not is_hidden(weapons.get(what))
		"passive":
			return not is_hidden(passives.get(what))
	return true


## Out of play (pass 34): marked hidden (a creature: or retired), or brought only by something hidden: an evolution of
## hidden weapons, a path of a hidden weapon, a perk of a hidden hero. The collection lists these apart.
func is_hidden(def: ContentDef) -> bool:
	if def == null:
		return false
	if def.hidden:
		return true
	if def is EnemyDef:
		return (def as EnemyDef).retired
	if def is WeaponDef and (def as WeaponDef).is_evolution:
		var srcs: Array = weapons.values().filter(func(b: WeaponDef) -> bool: return not b.is_evolution and b.evolves_into == def.id)
		return not srcs.is_empty() and srcs.all(func(b: WeaponDef) -> bool: return b.hidden)
	if def is MutationDef:
		var md := def as MutationDef
		var fam: WeaponDef = weapons.get(md.weapon)
		if fam != null and fam.hidden:
			return true
		# a hero mutation goes with its hero
		var owner: CharacterDef = characters.get(md.hero) if md.hero != "" else null
		return owner != null and owner.hidden
	if def is PerkDef:
		var hero: CharacterDef = characters.get((def as PerkDef).hero)
		return hero != null and hero.hidden
	return false


func sorted_maps() -> Array:
	var out: Array = maps.values()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func elites_list() -> Array:
	return elites.values()


## The Mirror's talents in board order.
func talent(id: String) -> TalentDef:
	return talents.get(id)


func talents_list() -> Array:
	var out: Array = talents.values()
	out.sort_custom(func(a, b): return a.order < b.order)
	return out
