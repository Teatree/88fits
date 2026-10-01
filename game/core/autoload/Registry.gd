## Scans res://content/** at boot and holds every content definition by type.
## Prefers <id>.tres; falls back to <id>.json through JsonContent. Never hard-codes content.
extends Node

const CONTENT_ROOT := "res://content/"

var weapons: Dictionary = {}     # includes evolutions
var passives: Dictionary = {}
var mutations: Dictionary = {}   # a weapon's path (three picks) and the hero mutations
var lines: Dictionary = {}       # the six character lines
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
	weapons.clear(); passives.clear(); mutations.clear(); lines.clear(); perks.clear(); enemies.clear(); elites.clear()
	characters.clear(); talents.clear(); quests.clear(); maps.clear(); pickups.clear(); structures.clear()
	missing_icons.clear(); problems.clear()
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
		"lines":
			lines[res.id] = res
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


func line(id: String) -> LineDef:
	return lines.get(id)


func perk(id: String) -> PerkDef:
	return perks.get(id)


const MUTATION_ORDER := {"element": 0, "volume": 1, "motion": 2, "hero": 3}


## A weapon's path: its three mutations in element, volume, motion order (hero mutations are not part of the path).
func mutations_of(weapon_id: String) -> Array:
	var out: Array = []
	for m: MutationDef in mutations.values():
		if m.weapon == weapon_id and not m.is_hero() and not m.hidden:
			out.append(m)
	out.sort_custom(func(a, b): return int(MUTATION_ORDER.get(a.mutation_kind, 9)) < int(MUTATION_ORDER.get(b.mutation_kind, 9)))
	return out


## The hero mutations a hero is offered (its favourite weapon's extra option).
func hero_mutations(hero_id: String) -> Array:
	var out: Array = []
	for m: MutationDef in mutations.values():
		if m.hero == hero_id:
			out.append(m)
	return out


func perks_of(hero_id: String) -> Array:
	var out: Array = []
	for p: PerkDef in perks.values():
		if p.hero == hero_id and not p.hidden:
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## The base lines, sorted: evolved lines come only as the evolution of the line they replace. (A line behind an unlock
## quest, pass 44, is kept out of the offers by CardPool, not here: this is the content listing.)
func sorted_lines() -> Array:
	var out: Array = []
	for l: LineDef in lines.values():
		if l.evolves_from == "" and not l.hidden:
			out.append(l)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func passive(id: String) -> PassiveDef:
	return passives.get(id)


func enemy(id: String) -> EnemyDef:
	return enemies.get(id)


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
		"line":
			return lines.get(id)
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


func unlocked_passives() -> Array:
	var out: Array = []
	for p in passives.values():
		if not p.hidden and is_unlocked("passive", p.id):
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


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


## The playable heroes, by id (a hidden one is kept in the content but never offered).
func sorted_characters() -> Array:
	var out: Array = characters.values().filter(func(c: CharacterDef) -> bool: return not c.hidden)
	out.sort_custom(func(a, b): return a.id < b.id)
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
		"line":
			return not is_hidden(lines.get(what))
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
