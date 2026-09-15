## Converts content JSON (the authoring format) into typed Resources.
## Used by tools/import_json.gd to write .tres files, and by Registry as a runtime fallback
## when a folder has JSON but no .tres yet.
class_name JsonContent
extends RefCounted

const TYPES := ["weapons", "evolutions", "passives", "enemies", "bosses", "elites", "characters", "shop", "quests", "maps", "pickups", "structures"]


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	push_error("JsonContent: %s is not a JSON object" % path)
	return {}


static func build(type: String, d: Dictionary, dir: String) -> ContentDef:
	var res: ContentDef = null
	match type:
		"weapons", "evolutions":
			res = _weapon(d, dir, type == "evolutions")
		"passives":
			res = _passive(d, dir)
		"enemies", "bosses":
			res = _enemy(d, dir)
		"elites":
			res = _elite(d, dir)
		"characters":
			res = _character(d, dir)
		"shop":
			res = _shop(d, dir)
		"quests":
			res = _quest(d, dir)
		"maps":
			res = _map(d, dir)
		"pickups":
			res = _pickup(d, dir)
		"structures":
			res = _structure(d, dir)
		_:
			push_error("JsonContent: unknown type %s" % type)
			return null
	_common(res, d, dir)
	return res


static func _common(res: ContentDef, d: Dictionary, dir: String) -> void:
	res.id = str(d.get("id", ""))
	res.display_name = str(d.get("name", res.id.capitalize()))
	res.flavour = str(d.get("flavour", ""))
	res.rarity = str(d.get("rarity", "common"))
	res.weight = float(d.get("weight", 10.0))
	res.icon_file = str(d.get("icon", res.id + "_icon.png"))
	res.icon = resolve_texture(dir, res.icon_file)
	var ph = d.get("placeholder", {})
	res.placeholder = ph if ph is Dictionary else {}
	res.source_dir = dir


static func effects_list(arr, default_target: String = "self") -> Array:
	var out: Array = []
	if arr is Array:
		for e in arr:
			if e is Dictionary:
				out.append(Effect.from_dict(e, default_target))
	return out


static func levels_list(arr, default_target: String = "self") -> Array:
	var out: Array = []
	if arr is Array:
		for lv in arr:
			out.append(effects_list(lv, default_target))
	return out


static func resolve_texture(dir: String, file: String) -> Texture2D:
	if file == "":
		return null
	var path := file if file.begins_with("res://") else dir + file
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	return null


static func resolve_scene(dir: String, file: String) -> PackedScene:
	if file == "":
		return null
	var path := file if file.begins_with("res://") else dir + file
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is PackedScene:
			return s
	return null


static func _weapon(d: Dictionary, dir: String, is_evo: bool) -> WeaponDef:
	var w := WeaponDef.new()
	w.behavior = str(d.get("behavior", "ProjectileEmitter"))
	w.targeting = str(d.get("targeting", "nearest"))
	var b = d.get("base", {})
	w.base = b if b is Dictionary else {}
	w.levels = levels_list(d.get("levels", []), "self")
	w.max_level = int(d.get("max_level", 8))
	w.evolves_with = str(d.get("evolves_with", ""))
	w.evolves_into = str(d.get("evolves_into", ""))
	w.is_evolution = bool(d.get("is_evolution", is_evo))
	w.evolved_from = str(d.get("evolved_from", ""))
	var s = d.get("sfx", {})
	w.sfx = s if s is Dictionary else {}
	var p = d.get("params", {})
	w.params = p if p is Dictionary else {}
	w.visual_file = str(d.get("visual", str(d.get("id", "")) + "_visual.tscn"))
	w.visual = resolve_scene(dir, w.visual_file)
	return w


static func _passive(d: Dictionary, dir: String) -> PassiveDef:
	var p := PassiveDef.new()
	p.levels = levels_list(d.get("levels", []), "player")
	p.repeat_last_level = bool(d.get("repeat_last_level", true))
	p.max_level = int(d.get("max_level", 8))
	p.pairs_with = str(d.get("pairs_with", ""))
	return p


static func _enemy(d: Dictionary, dir: String) -> EnemyDef:
	var e := EnemyDef.new()
	e.archetype = str(d.get("archetype", "walker"))
	e.brain = str(d.get("brain", "chase"))
	e.hp = float(d.get("hp", 10.0))
	e.speed = float(d.get("speed", 2.5))
	e.damage = float(d.get("damage", 5.0))
	e.radius = float(d.get("radius", 0.5))
	e.size = float(d.get("size", 1.0))
	e.pack_size = int(d.get("pack_size", 1))
	var dr = d.get("drops", {"small": 1.0, "gold": 0.02})
	e.drops = dr if dr is Dictionary else {}
	var an = d.get("anims", {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1})
	e.anims = an if an is Dictionary else {}
	e.frame_px = int(d.get("frame_px", 128))
	e.strip_cols = int(d.get("strip_cols", 0))
	var fp = d.get("fps", {})
	e.fps = fp if fp is Dictionary else {}
	e.sprite_file = str(d.get("sprite", str(d.get("id", "")) + "_sprite.png"))
	e.sprite = resolve_texture(dir, e.sprite_file)
	var r = d.get("ranged", {})
	e.ranged = r if r is Dictionary else {}
	var c = d.get("charge", {})
	e.charge = c if c is Dictionary else {}
	var b = d.get("boss", {})
	e.boss = b if b is Dictionary else {}
	var s = d.get("sfx", {})
	e.sfx = s if s is Dictionary else {}
	e.xp_mult = float(d.get("xp_mult", 1.0))
	var vr = d.get("variance", {})
	e.variance = vr if vr is Dictionary else {}
	return e


static func _elite(d: Dictionary, dir: String) -> EliteModDef:
	var m := EliteModDef.new()
	m.effects = effects_list(d.get("effects", []), "self")
	m.outline = Color(str(d.get("outline", "#FFFFFF")))
	m.scale_mult = float(d.get("scale_mult", 1.5))
	m.on_death = str(d.get("on_death", "none"))
	var p = d.get("params", {})
	m.params = p if p is Dictionary else {}
	return m


static func _character(d: Dictionary, dir: String) -> CharacterDef:
	var c := CharacterDef.new()
	c.trait_effects = effects_list(d.get("trait", []), "player")
	c.favourite_weapon = str(d.get("favourite_weapon", ""))
	var fb = d.get("favourite_bonus", {})
	c.favourite_bonus = fb.duplicate() if fb is Dictionary else {}
	if c.favourite_bonus.has("effects"):
		c.favourite_bonus["effects"] = effects_list(c.favourite_bonus["effects"], "self")
	var sp = d.get("specials", [])
	c.specials = sp if sp is Array else []
	c.unlock_quest = str(d.get("unlock_quest", ""))
	c.frame_px = int(d.get("frame_px", 256))
	c.strip_cols = int(d.get("strip_cols", 0))
	var fp = d.get("fps", {})
	c.fps = fp if fp is Dictionary else {}
	var an = d.get("anims", {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1})
	c.anims = an if an is Dictionary else {}
	c.sprite_file = str(d.get("sprite", str(d.get("id", "")) + "_sprite.png"))
	c.sprite = resolve_texture(dir, c.sprite_file)
	return c


static func _shop(d: Dictionary, dir: String) -> ShopUpgradeDef:
	var s := ShopUpgradeDef.new()
	var e = d.get("effect", {})
	if e is Dictionary and not e.is_empty():
		s.effect_per_tier = Effect.from_dict(e, "player")
	var costs = d.get("costs", [])
	s.costs = costs if costs is Array else []
	s.order = int(d.get("order", 0))
	s.effect_text = str(d.get("effect_text", ""))
	return s


static func _quest(d: Dictionary, dir: String) -> QuestDef:
	var q := QuestDef.new()
	var c = d.get("condition", {})
	q.condition = c if c is Dictionary else {}
	var u = d.get("unlocks", {})
	q.unlocks = u if u is Dictionary else {}
	q.quest_text = str(d.get("quest_text", ""))
	return q


static func _map(d: Dictionary, dir: String) -> MapDef:
	var m := MapDef.new()
	m.scene_file = str(d.get("scene", ""))
	m.scene = resolve_scene(dir, m.scene_file)
	m.timeline_file = str(d.get("timeline", ""))
	var tl = d.get("timeline_data", {})
	if tl is Dictionary and not tl.is_empty():
		m.timeline = timeline_from_dict(tl)
	var sk = d.get("skins", {})
	m.skins = sk if sk is Dictionary else {}
	m.boss = str(d.get("boss", ""))
	m.unlock_quest = str(d.get("unlock_quest", ""))
	var mu = d.get("music", {})
	if mu is Dictionary and not mu.is_empty():
		m.music = mu
	return m


static func _pickup(d: Dictionary, dir: String) -> PickupDef:
	var p := PickupDef.new()
	p.effect_kind = str(d.get("effect", "heal"))
	p.value = float(d.get("value", 0.3))
	p.duration = float(d.get("duration", 0.0))
	p.effects = effects_list(d.get("effects", []), "player")
	p.lifetime = float(d.get("lifetime", 20.0))
	p.color = Color(str(d.get("color", "#FFFFFF")))
	return p


static func _structure(d: Dictionary, dir: String) -> StructureDef:
	var st := StructureDef.new()
	st.effect_kind = str(d.get("effect", "heal"))
	var pr = d.get("params", {})
	st.params = pr if pr is Dictionary else {}
	st.effects = effects_list(st.params.get("effects", []), "player")
	st.radius = float(d.get("radius", 2.2))
	st.interact_time = float(d.get("interact_time", 3.0))
	st.color = Color(str(d.get("color", "#FFFFFF")))
	st.prop = str(d.get("prop", ""))
	st.height = float(d.get("height", 2.0))
	return st


static func timeline_from_dict(t: Dictionary) -> WaveTimeline:
	var w := WaveTimeline.new()
	w.stage_length = float(t.get("stage_length", 300.0))
	w.stages = int(t.get("stages", 3))
	var sm = t.get("stage_mults", [1.0, 1.35, 1.8])
	w.stage_mults = sm if sm is Array else [1.0]
	w.endless_mult_per_minute = float(t.get("endless_mult_per_minute", 0.1))
	w.cap_start = int(t.get("cap_start", 100))
	w.cap_per_minute = float(t.get("cap_per_minute", 10.0))
	w.cap_max = int(t.get("cap_max", 250))
	w.hard_cap = int(t.get("hard_cap", 300))
	w.hp_growth = float(t.get("hp_growth", 0.08))
	w.hp_power = float(t.get("hp_power", 1.2))
	w.burst_min = int(t.get("burst_min", 5))
	w.burst_max = int(t.get("burst_max", 20))
	w.spawn_interval = float(t.get("spawn_interval", 0.5))
	var ro = t.get("roster", [])
	w.roster = ro if ro is Array else []
	var ev = t.get("events", [])
	w.events = ev if ev is Array else []
	var pk = t.get("pickups", {})
	w.pickups = pk if pk is Dictionary else {}
	var stc = t.get("structures", {})
	w.structures = stc if stc is Dictionary else {}
	return w


static func soundmap_from_dict(d: Dictionary, dir: String) -> SoundMap:
	var sm := SoundMap.new()
	var entries = d.get("sounds", {})
	if entries is Dictionary:
		for id in entries.keys():
			var e = entries[id]
			if not (e is Dictionary):
				continue
			var row := {
				"file": str(e.get("file", "placeholder/%s.wav" % id)),
				"category": str(e.get("category", "sfx")),
				"voices": int(e.get("voices", 4)),
				"pitch_spread": float(e.get("pitch_spread", 0.05)),
				"volume_db": float(e.get("volume_db", 0.0)),
				"loop": bool(e.get("loop", false)),
				"stream": null,
			}
			var path: String = row["file"] if row["file"].begins_with("res://") else dir + row["file"]
			if ResourceLoader.exists(path):
				var s = load(path)
				if s is AudioStream:
					row["stream"] = s
			sm.entries[str(id)] = row
	return sm
