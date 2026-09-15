## Scans res://content/** at boot and holds every content definition by type.
## Prefers <id>.tres; falls back to <id>.json through JsonContent. Never hard-codes content.
extends Node

const CONTENT_ROOT := "res://content/"

var weapons: Dictionary = {}     # includes evolutions
var passives: Dictionary = {}
var enemies: Dictionary = {}     # includes bosses
var elites: Dictionary = {}
var characters: Dictionary = {}
var shop: Dictionary = {}
var quests: Dictionary = {}
var maps: Dictionary = {}
var pickups: Dictionary = {}
var structures: Dictionary = {}
var soundmap: SoundMap = SoundMap.new()
var missing_icons: Array = []
var problems: Array = []
var scanned := false


func _ready() -> void:
	scan()


func scan() -> void:
	weapons.clear(); passives.clear(); enemies.clear(); elites.clear()
	characters.clear(); shop.clear(); quests.clear(); maps.clear(); pickups.clear(); structures.clear()
	missing_icons.clear(); problems.clear()
	for type: String in JsonContent.TYPES:
		_scan_type(type)
	_load_soundmap()
	_validate()
	scanned = true
	print("Registry: %d weapons, %d passives, %d enemies, %d elites, %d characters, %d shop, %d quests, %d maps, %d sounds" % [
		weapons.size(), passives.size(), enemies.size(), elites.size(), characters.size(), shop.size(), quests.size(), maps.size(), soundmap.entries.size()])


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
		"enemies", "bosses":
			enemies[res.id] = res
		"elites":
			elites[res.id] = res
		"characters":
			characters[res.id] = res
		"shop":
			shop[res.id] = res
		"quests":
			quests[res.id] = res
		"maps":
			maps[res.id] = res
		"pickups":
			pickups[res.id] = res
		"structures":
			structures[res.id] = res


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


func base_weapons() -> Array:
	## Non-evolved weapons, sorted by id.
	var out: Array = []
	for w in weapons.values():
		if not w.is_evolution:
			out.append(w)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func unlocked_weapons() -> Array:
	return base_weapons().filter(func(w): return is_unlocked("weapon", w.id))


func unlocked_passives() -> Array:
	var out: Array = []
	for p in passives.values():
		if is_unlocked("passive", p.id):
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func sorted_shop() -> Array:
	var out: Array = shop.values()
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.id < b.id)
	return out


func sorted_characters() -> Array:
	var out: Array = characters.values()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func sorted_maps() -> Array:
	var out: Array = maps.values()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func elites_list() -> Array:
	return elites.values()
