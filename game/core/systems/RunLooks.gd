## Pass 101 (lane LOOKS; Garry's item 6: "load only the looks that will appear"): the strips a run will draw, loaded
## and pinned before the spawn beam so play never waits on a first spawn (LookArt holds them; every other look's strip
## stays a path until something asks for it). Warmup.run calls prepare() under the beam (the arena's and a tool's instant
## start too), and draws the creature types it returns once, as it drew every creature before.
##
## The set: every creature the map's stage window can bring, in the look it brings it in: the roster rows open in the
## window (a row's own `variant`, else the creature's played look; a list row's every creature; a "roster" row's own
## variant laid on the mix creatures open then), the waves and events in the window, the specials whose stage has come,
## the stage's boss and the map's `boss` and `skins` (the director registers those at its start), and what any of them
## brings in turn (a boss attack's `enemy` / `spawn`, a custom boss attack's). Plus the hero's played look (the save's
## kept look, Registry.played_look). The arena: its training dummies and a tool's launch pick (`spawn_enemy` + `variant`,
## `look`); the rest of the arena loads a look the first time it is picked or spawned.
class_name RunLooks
extends RefCounted

## The keys under which a creature's own data names another creature it brings (a boss's brood, an erupt's young).
const BRINGS := ["enemy", "enemies", "spawn", "summon", "summons"]
## The arena's own creatures (Game's training dummies).
const ARENA_IDS := ["training_dummy", "training_dummy_elite", "training_dummy_boss", "training_dummy_melee", "training_dummy_ranged"]

## The last prepare()'s pairs [[id, variant], ...] and the strip paths it pinned (tests, the probes).
static var last_pairs: Array = []
static var last_paths: Array = []


## Loads and pins the run's strips (LookArt.pin_only) and returns the creature defs (each in its played look) whose
## types Warmup draws once. `launch` is the tool's launch dictionary when there is one. Pass 136 (lane LOAD): the strips
## a curtain or the title asked for ahead (prefetch_next) are in LookArt already, so pinning them waits for nothing.
static func prepare(game: Node, launch: Dictionary = {}) -> Array:
	var reg: Node = game.get_tree().root.get_node_or_null("Registry")
	var run: Node = game.get_tree().root.get_node_or_null("Run")
	if reg == null or run == null:
		return []
	var plan := plan_for(reg, run.get("map"), int(run.get("stage")), bool(run.get("arena")), run.get("character"),
		launch, true)
	LookArt.pin_only(plan["paths"])
	last_pairs = plan["pairs"]
	last_paths = plan["paths"]
	return plan["defs"]


## The run's set without loading anything: {pairs, paths (the strips, the Outlaw's look last), defs (only `with_defs`)}
## for `map`'s stage `stage` (or the arena's), the Outlaw `character` and a tool's `launch`.
static func plan_for(reg: Node, map: MapDef, stage: int, arena: bool, character, launch: Dictionary = {},
		with_defs: bool = false) -> Dictionary:
	var pairs: Array = []
	if arena:
		for id: String in ARENA_IDS:
			pairs.append([id, ""])
		if launch.has("spawn_enemy"):
			pairs.append([str(launch["spawn_enemy"]), str(launch.get("variant", ""))])
	else:
		pairs = pairs_for(reg, map, stage)
	var paths: Array = []
	var defs: Array = []
	var seen_ids := {}
	for p: Array in pairs:
		var d: EnemyDef = reg.enemy(str(p[0]))
		if d == null:
			continue
		var path := d.look_strip_path(str(p[1]))
		if path != "" and not paths.has(path):
			paths.append(path)
		# one type per creature for Warmup to draw, in the first look the stage brings it in (its played look's strip is
		# not loaded for a creature that only comes in another)
		if with_defs and not seen_ids.has(d.id):
			seen_ids[d.id] = true
			var vd: EnemyDef = reg.enemy_with(d.id, str(p[1]))
			defs.append(vd if vd != null else d)
	# the hero in the look he is played in, and a tool's launch look
	if character is CharacterDef:
		var look: CharacterDef = reg.played_look(character)
		if look and look.strip_path() != "":
			paths.append(look.strip_path())
		if launch.has("look"):
			var lp := (character as CharacterDef).look_strip_path(str(launch["look"]))
			if lp != "" and not paths.has(lp):
				paths.append(lp)
	return {"pairs": pairs, "paths": paths, "defs": defs}


## Pass 136 (lane LOAD): the strips of the run a tap is about to start, before its Game exists, chosen as Game._ready
## chooses: the save's last Outlaw (a playable one, else Astro) and map (else the first), Run.stage_next (clamped as
## Run.start_stage clamps it), the arena when Run.arena_next. `stage` >= 0, `hero_id` and `map_id` stand in for those (the
## title asks for the Outlaw it shows, the Stages menu for the stage it expects).
static func next_run_paths(tree: SceneTree, stage: int = -1, hero_id: String = "", map_id: String = "") -> Array:
	var root := tree.root
	var reg: Node = root.get_node_or_null("Registry")
	var run: Node = root.get_node_or_null("Run")
	var save: Node = root.get_node_or_null("Save")
	var settings: Node = root.get_node_or_null("Settings")
	if reg == null or run == null or save == null:
		return []
	var data: Dictionary = save.get("data")
	var hid := hero_id if hero_id != "" else str(data.get("last_character", "drifter"))
	var c = reg.playable_character(hid)
	if c == null and not (reg.get("characters") as Dictionary).is_empty():
		c = reg.playable_character("astro")
	var mid := map_id if map_id != "" else str(data.get("last_map", "red_canyon"))
	var m: MapDef = reg.map(mid)
	if m == null:
		var maps: Array = reg.sorted_maps()
		m = maps[0] if not maps.is_empty() else null
	var arena := bool(run.get("arena_next")) and not (settings != null and bool(settings.call("is_prod")))
	var st := stage if stage >= 0 else int(run.get("stage_next"))
	if m != null and m.timeline != null:
		st = m.timeline.stage_clamp(st)
	return plan_for(reg, m, st, arena, c)["paths"]


## Asks for the next run's strips on the loader threads (LookArt.request; see next_run_paths); returns how many were asked.
static func prefetch_next(tree: SceneTree, stage: int = -1, hero_id: String = "", map_id: String = "") -> int:
	return LookArt.request(next_run_paths(tree, stage, hero_id, map_id))


## Every [id, variant] the map's stage `stage` (0-based) can bring (see the header); variant "" = the creature's played
## look. Ids may repeat with different variants; unknown ids are left out.
static func pairs_for(reg: Node, map: MapDef, stage: int) -> Array:
	var out: Array = []
	if map == null:
		return out
	var tl: WaveTimeline = map.timeline
	var win := Vector2(0.0, INF)
	if tl != null:
		win = tl.stage_window(stage)
	# the director registers the skins and the map's boss at its start
	for k in map.skins.keys():
		_add(reg, out, str(map.skins[k]), "")
	_add(reg, out, map.boss, "")
	if tl != null:
		_add(reg, out, tl.stage_boss(stage), "")
		var mix_ids: Array = []
		var roster_variants: Array = []
		for r in tl.roster:
			if not (r is Dictionary):
				continue
			var t0 := float(r.get("t", 0.0))
			var until := float(r["until"]) if r.get("until") != null else INF
			if t0 > win.y or until <= win.x:
				continue
			var v := str(r.get("variant", ""))
			var e = r.get("enemy", "")
			if e is Array:
				for x in e:
					_add(reg, out, str(x), v)
			elif str(e) == WaveTimeline.ROW_ENEMY_ROSTER:
				if v != "":
					roster_variants.append(v)
			else:
				_add(reg, out, str(e), v)
				if WaveTimeline.row_in_mix(r):
					mix_ids.append(str(e))
		# a "roster" row with its own look lays it on whichever mix creature it draws
		for v: String in roster_variants:
			for id: String in mix_ids:
				_add(reg, out, id, v)
		for list: Array in [tl.waves, tl.events]:
			for ev in list:
				if not (ev is Dictionary):
					continue
				var t := float(ev.get("t", 0.0))
				if t < win.x or t > win.y + 0.5:
					continue
				# the boss event on the window's first second is the stage before's (its boss comes at its end)
				if stage > 0 and str(ev.get("type", "")) == "boss" and t < win.x + 0.5:
					continue
				_walk(reg, out, ev, str(ev.get("variant", "")))
		var sp: Dictionary = tl.specials
		var from := float(sp.get("from", 0.0))
		if from <= win.y:
			for row in sp.get("pool", []):
				var id := str(row.get("enemy", "")) if row is Dictionary else str(row)
				var st := int(row.get("stage", 1)) if row is Dictionary else 1
				if stage + 1 >= st:
					_add(reg, out, id, str(row.get("variant", "")) if row is Dictionary else "")
	# what they bring in turn (a boss's brood, a custom attack's), until nothing new comes
	var seen := {}
	var k := 0
	while k < out.size():
		var d: EnemyDef = reg.enemy(str(out[k][0]))
		k += 1
		if d == null:
			continue
		for prop in d.get_property_list():
			if int(prop["usage"]) & PROPERTY_USAGE_STORAGE == 0:
				continue
			var val = d.get(str(prop["name"]))
			if val is Dictionary or val is Array:
				_brings(reg, out, val, seen)
	return out


## Adds [id, variant] once when `id` is a creature.
static func _add(reg: Node, out: Array, id: String, variant: String) -> void:
	if id == "" or reg.enemy(id) == null:
		return
	for p: Array in out:
		if p[0] == id and p[1] == variant:
			return
	out.append([id, variant])


## Every creature id anywhere in an event or a wave (its `enemy`, a list of them, an alt's), with the entry's variant.
static func _walk(reg: Node, out: Array, v, variant: String) -> void:
	if v is Dictionary:
		var own := str((v as Dictionary).get("variant", variant))
		for key in (v as Dictionary).keys():
			_walk(reg, out, v[key], own)
	elif v is Array:
		for x in v:
			_walk(reg, out, x, variant)
	elif v is String:
		_add(reg, out, str(v), variant)


## The creatures a creature's own blocks bring (BRINGS keys) and those of the custom boss attacks it names.
static func _brings(reg: Node, out: Array, v, seen: Dictionary) -> void:
	if v is Dictionary:
		for key in (v as Dictionary).keys():
			var x = v[key]
			if str(key) in BRINGS and (x is String or x is Array):
				for id in (x if x is Array else [x]):
					_add(reg, out, str(id), "")
					# pass 127: a ring that wears several looks (`looks` beside its `enemy`) needs them all pinned
					if (v as Dictionary).get("looks") is Array:
						for lk in (v as Dictionary)["looks"]:
							_add(reg, out, str(id), str(lk))
			else:
				_brings(reg, out, x, seen)
	elif v is Array:
		for x in v:
			_brings(reg, out, x, seen)
	elif v is String:
		var ba = reg.get("boss_attacks")
		if ba is Dictionary and (ba as Dictionary).has(str(v)) and not seen.has(str(v)):
			seen[str(v)] = true
			var bd: Resource = ba[str(v)]
			for prop in bd.get_property_list():
				if int(prop["usage"]) & PROPERTY_USAGE_STORAGE == 0:
					continue
				var val = bd.get(str(prop["name"]))
				if val is Dictionary:
					_brings(reg, out, val, seen)
