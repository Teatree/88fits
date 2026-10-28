## Pass 81 (lane PROD, Garry: "no extra art (unless it's used in the Level timeline)"): what the production build can
## show, walked from the Registry, and so what tools/prod_prune.py may delete from the production build's staging copy.
## Static; loaded at run time (never preloaded by a --script tool: it names the content classes, which name autoloads).
##
## Kept (a content folder is "type/id", res://content/<type>/<id>/):
##  - every map; every hero not hidden (available or on sale) and what he brings: his start weapon (start_weapon_for),
##    his favourite weapon and passive, his perks (perks_of) and hero mutations (hero_mutations);
##  - every base weapon not hidden, with its evolution (evolves_into), the passive it evolves with and its path
##    (mutations_of); every base passive not hidden (lines and passive items) with its evolution; every talent, Elite
##    modifier, pickup and structure not hidden;
##  - every creature or boss the map's JSON names anywhere (roster rows, waves, events, specials, Elites, bosses, the
##    portal, hell...), the map's skins and boss, and every creature, boss, custom boss attack, pickup or structure that
##    any kept item names in its own JSON (summons, a split's children, damage_from, a perk's pickup), to a fixed point;
##  - the code's own fallbacks: a `Registry.<getter>("id")` literal (weapon, passive, enemy, character, pickup, ...) in
##    a script of the game outside the debug-only ones (ArenaPanel, DebugPanel, DebugHand, DevMenu); such a pin keeps
##    the folder and what the Registry needs to stay whole (its evolution and the passive it evolves with), but a hidden
##    weapon pinned so is not in play: its path is not walked;
##  - every quest that is shown (Registry.quest_visible) whose unlock is kept (or unlocks no item).
## Looks: a hero and a card keep only the look the game plays (the JSON's `variant`; a fresh save keeps none of its
## own), "promoted" to the base when it was not (pass 111: a hero also keeps every look sold as a skin); a creature keeps its base, the look it plays and every look a map row
## or event names (paired with its `enemy`; a code named without one is matched to every creature that has it). A
## weapon family keeps all its looks. Everything else is dropped, with the reason.
extends RefCounted

const DEBUG_SCRIPTS := ["res://ui/ArenaPanel.gd", "res://ui/DebugPanel.gd", "res://ui/DebugHand.gd", "res://ui/DevMenu.gd"]
const CODE_DIRS := ["res://core", "res://game", "res://ui", "res://player", "res://world"]
## Registry getter -> the Registry dictionary it reads
const GETTERS := {"weapon": "weapons", "passive": "passives", "enemy": "enemies", "enemy_with": "enemies",
	"character": "characters", "playable_character": "characters", "pickup": "pickups", "structure": "structures",
	"perk": "perks", "mutation": "mutations", "map": "maps", "talent": "talents", "boss_attack": "boss_attacks"}
## The content types whose ids a raw JSON walk may name: creatures, boss attacks, pickups and structures (never weapons,
## passives, mutations or perks, whose ids are also stats' and kinds' words: "haste", "swarm", "strike")
const WALK_DICTS := ["enemies", "boss_attacks", "pickups", "structures"]
## Raw keys a creature's own JSON names its looks with (not references to anything)
const LOOK_KEYS := ["variants", "variant", "variant_base"]


## {"keep": {folder: why}, "drop": {folder: why}, "looks": {folder: {...}}, "pins": [..], "counts": {...}}
static func plan(reg: Node) -> Dictionary:
	var st := {"reg": reg, "keep": {}, "queue": [], "pins": []}
	# the roots
	for m in reg.maps.values():
		_add(st, m, "a map", true)
	for c in reg.characters.values():
		if not c.hidden:
			_add(st, c, "a hero in play (%s)" % c.availability, true)
	for w in reg.base_weapons():
		if not w.hidden:
			_add(st, w, "a weapon in play", true)
	for p in reg.base_passives():
		_add(st, p, "a %s in play" % ("card" if p.is_line() else "passive item"), true)
	# pass 111 (lane SKINS): and every currency
	for dict_name in ["talents", "elites", "pickups", "structures", "currencies"]:
		for d in (reg.get(dict_name) as Dictionary).values():
			if not d.hidden:
				_add(st, d, "not hidden (%s)" % dict_name, true)
	for pin: Array in code_pins(reg):
		var d = (reg.get(str(pin[0])) as Dictionary).get(str(pin[1]))
		if d != null:
			st["pins"].append("%s %s (%s)" % [pin[0], pin[1], pin[2]])
			_add(st, d, "named by the code (%s)" % pin[2], false)
	# the walk
	while not (st["queue"] as Array).is_empty():
		var def = (st["queue"] as Array).pop_front()
		_expand(st, def)
	var keep: Dictionary = st["keep"]
	# quests: shown, and what they unlock is kept (or they unlock no item)
	for q in reg.quests.values():
		var what = reg.unlocked_by(q)
		var shown: bool = reg.quest_visible(q) and not q.hidden
		if shown and (what == null or keep.has(folder_of(what))):
			keep[folder_of(q)] = {"why": "a quest for %s" % (folder_of(what) if what else "no item"), "expand": false}
	# the drops: every content folder not kept
	var drop := {}
	for dir_name: String in content_dirs():
		var key := dir_name.trim_prefix("res://content/").trim_suffix("/")
		if key.begins_with("sounds"):
			continue
		if not keep.has(key):
			drop[key] = _why_dropped(reg, key)
	var looks := _looks(reg, keep)
	var reasons := {}
	for k: String in keep:
		reasons[k] = str((keep[k] as Dictionary)["why"])
	return {"keep": reasons, "drop": drop, "looks": looks, "pins": st["pins"],
		"counts": {"keep": reasons.size(), "drop": drop.size()}}


## "type/id" for a def (its folder under res://content/), "" for none.
static func folder_of(def) -> String:
	if def == null:
		return ""
	var sd := str(def.get("source_dir"))
	return sd.trim_prefix("res://content/").trim_suffix("/")


static func _add(st: Dictionary, def, why: String, expand: bool) -> void:
	if def == null:
		return
	var key := folder_of(def)
	if key == "":
		return
	var keep: Dictionary = st["keep"]
	if keep.has(key):
		# a folder first kept by a pin is walked once it turns out to be in play after all
		if expand and not bool((keep[key] as Dictionary)["expand"]):
			keep[key] = {"why": why, "expand": true}
			(st["queue"] as Array).append(def)
		return
	keep[key] = {"why": why, "expand": expand}
	if expand:
		(st["queue"] as Array).append(def)
	else:
		_close(st, def, key)


## What a folder kept but not walked (a code pin) still needs for the Registry to stay whole (Registry._validate: a
## weapon's evolution and the passive it evolves with, a passive's evolution pair), kept the same way.
static func _close(st: Dictionary, def, key: String) -> void:
	var reg: Node = st["reg"]
	var why := "named by %s's needs" % key
	match key.get_slice("/", 0):
		"weapons", "evolutions":
			if str(def.evolves_into) != "":
				_add(st, reg.weapon(def.evolves_into), why + " (its evolution)", false)
			if str(def.evolves_with) != "":
				_add(st, reg.passive(def.evolves_with), why + " (it evolves with it)", false)
		"passives":
			if str(def.evolves_into) != "":
				_add(st, reg.passive(def.evolves_into), why + " (its evolution)", false)
			if str(def.evolves_from) != "":
				_add(st, reg.passive(def.evolves_from), why + " (it evolves from it)", false)


static func _expand(st: Dictionary, def) -> void:
	var reg: Node = st["reg"]
	var key := folder_of(def)
	var type := key.get_slice("/", 0)
	match type:
		"characters":
			var c = def
			_add(st, reg.start_weapon_for(c), "%s's start weapon" % c.id, true)
			if c.start_weapon != "":
				_add(st, reg.weapon(c.start_weapon), "%s's start weapon" % c.id, true)
			if c.favourite_weapon != "":
				_add(st, reg.weapon(c.favourite_weapon), "%s's favourite" % c.id, true)
			if c.favourite_passive != "":
				_add(st, reg.passive(c.favourite_passive), "%s's favourite" % c.id, true)
			for p in reg.perks_of(c.id):
				_add(st, p, "%s's perk" % c.id, true)
			for m in reg.hero_mutations(c.id):
				_add(st, m, "%s's hero mutation" % c.id, true)
		"weapons", "evolutions":
			var w = def
			if w.evolves_into != "":
				_add(st, reg.weapon(w.evolves_into), "%s's evolution" % w.id, true)
			if w.evolves_with != "":
				_add(st, reg.passive(w.evolves_with), "%s evolves with it" % w.id, true)
			for m in reg.mutations_of(w.id):
				_add(st, m, "%s's path" % w.id, true)
		"passives":
			var p = def
			if p.evolves_into != "":
				_add(st, reg.passive(p.evolves_into), "%s's evolution" % p.id, true)
		"maps":
			var m = def
			for arch in m.skins.keys():
				_add(st, reg.enemy(str(m.skins[arch])), "the map's %s" % arch, true)
			if m.boss != "":
				_add(st, reg.enemy(m.boss), "the map's boss", true)
	# whatever its own JSON names: a map's rows, a boss's summons, a perk's pickup (the Timeout's), a split's children
	_walk_named(st, raw_json(def), "named by %s" % key, [] if type == "maps" else LOOK_KEYS)


## Every creature / boss attack a raw JSON names (any string value equal to one's id), kept and walked.
static func _walk_named(st: Dictionary, d, why: String, skip_keys: Array) -> void:
	var reg: Node = st["reg"]
	var found := {}
	_strings(d, skip_keys, found)
	for s: String in found:
		for dict_name: String in WALK_DICTS:
			var hit = (reg.get(dict_name) as Dictionary).get(s)
			if hit != null:
				_add(st, hit, why, true)


static func _strings(x, skip_keys: Array, out: Dictionary) -> void:
	if x is Dictionary:
		for k in x:
			if skip_keys.has(str(k)):
				continue
			_strings(x[k], skip_keys, out)
	elif x is Array:
		for v in x:
			_strings(v, skip_keys, out)
	elif x is String:
		out[x] = true


## The content JSON a def came from ({} when it has none).
static func raw_json(def) -> Dictionary:
	var key := folder_of(def)
	if key == "":
		return {}
	var p := "res://content/%s/%s.json" % [key, key.get_slice("/", 1)]
	if not FileAccess.file_exists(p):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}


## Every content folder (res://content/<type>/<id>/), sounds excluded.
static func content_dirs() -> Array:
	var out: Array = []
	var root := DirAccess.open("res://content/")
	if root == null:
		return out
	for t in root.get_directories():
		if t == "sounds":
			continue
		var td := DirAccess.open("res://content/%s/" % t)
		if td == null:
			continue
		for i in td.get_directories():
			if not i.begins_with("."):
				out.append("res://content/%s/%s/" % [t, i])
	return out


## [dict name, id, where] for every `Registry.<getter>("id")` (or a bare `<getter>("id")` inside Registry.gd) in the
## game's scripts outside the debug-only ones.
static func code_pins(reg: Node) -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("(?<![A-Za-z0-9_])(weapon|passive|enemy_with|enemy|character|playable_character|pickup|structure|perk|mutation|map|talent|boss_attack)\\(\\s*\"([a-z0-9_]+)\"")
	for path: String in game_scripts():
		if DEBUG_SCRIPTS.has(path):
			continue
		var src := FileAccess.get_file_as_string(path)
		for m in rx.search_all(src):
			var dict_name := str(GETTERS[m.get_string(1)])
			var id := m.get_string(2)
			if (reg.get(dict_name) as Dictionary).has(id):
				out.append([dict_name, id, path.get_file()])
	return out


static func game_scripts() -> Array:
	var out: Array = []
	for d: String in CODE_DIRS:
		_scripts_under(d, out)
	return out


static func _scripts_under(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in da.get_directories():
		if not sub.begins_with("."):
			_scripts_under(dir.path_join(sub), out)


static func _why_dropped(reg: Node, key: String) -> String:
	var type := key.get_slice("/", 0)
	var id := key.get_slice("/", 1)
	var dict_name := type
	match type:
		"evolutions":
			dict_name = "weapons"
		"bosses":
			dict_name = "enemies"
	var d = (reg.get(dict_name) as Dictionary).get(id) if reg.get(dict_name) is Dictionary else null
	if d == null:
		return "not loaded by the Registry"
	if reg.is_hidden(d):
		return "hidden"
	return "not reachable from the map, the heroes or the items in play"


## Per kept folder with looks: {"kind", "play", "base", "keep": [codes], "drop": [codes], "promote": bool}.
static func _looks(reg: Node, keep: Dictionary) -> Dictionary:
	var out := {}
	var named := _named_looks(reg, keep)
	for key: String in keep:
		var type := key.get_slice("/", 0)
		if not ["characters", "passives", "enemies", "bosses"].has(type):
			continue
		var raw := _raw_by_key(key)
		var vs = raw.get("variants")
		if not (vs is Dictionary) or (vs as Dictionary).is_empty():
			continue
		var id := key.get_slice("/", 1)
		var base := str(raw.get("variant_base", ""))
		var def = reg.character(id) if type == "characters" else (reg.passive(id) if type == "passives" else reg.enemy(id))
		if def == null:
			continue
		var play := str(def.variant)
		var keep_codes: Array = []
		var kind := "creature"
		if type == "characters" or type == "passives":
			kind = "hero" if type == "characters" else "card"
			if play != "":
				keep_codes.append(play)
			elif base != "":
				keep_codes.append(base)
			# pass 111 (lane SKINS): and every look a player can buy and wear (CharacterDef.sells_skin)
			if type == "characters":
				for c in (vs as Dictionary).keys():
					if def.sells_skin(str(c)) and not keep_codes.has(str(c)):
						keep_codes.append(str(c))
		else:
			for c in [base, play]:
				if str(c) != "" and not keep_codes.has(str(c)):
					keep_codes.append(str(c))
			for c in (named.get(id, []) as Array):
				if (vs as Dictionary).has(c) and not keep_codes.has(c):
					keep_codes.append(c)
		var drop_codes: Array = []
		for c in (vs as Dictionary).keys():
			if not keep_codes.has(str(c)):
				drop_codes.append(str(c))
		drop_codes.sort()
		var promote: bool = kind != "creature" and play != "" and play != base
		out[key] = {"kind": kind, "play": play, "base": base, "keep": keep_codes, "drop": drop_codes, "promote": promote}
	return out


static func _raw_by_key(key: String) -> Dictionary:
	var p := "res://content/%s/%s.json" % [key, key.get_slice("/", 1)]
	if not FileAccess.file_exists(p):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}


## creature id -> [look codes] a kept map, boss, creature or boss attack names: a dict with `variant` beside `enemy`
## (a string or a list) names that creature's look; a `variant` without an `enemy` names every creature that has it.
static func _named_looks(reg: Node, keep: Dictionary) -> Dictionary:
	var out := {}
	var loose := {}
	for key: String in keep:
		var type := key.get_slice("/", 0)
		if not ["maps", "enemies", "bosses", "boss_attacks"].has(type):
			continue
		_pairs(_raw_by_key(key), out, loose, type != "maps")
	for code: String in loose:
		for e in reg.enemies.values():
			if (e.variants as Dictionary).has(code):
				if not out.has(e.id):
					out[e.id] = []
				if not (out[e.id] as Array).has(code):
					(out[e.id] as Array).append(code)
	return out


static func _pairs(x, out: Dictionary, loose: Dictionary, top: bool) -> void:
	if x is Dictionary:
		var d: Dictionary = x
		# a creature's own `variant` / `variants` name its own looks, not a reference
		if not top and d.get("variant") is String and str(d["variant"]) != "":
			var code := str(d["variant"])
			var who = d.get("enemy")
			var ids: Array = []
			if who is String:
				ids = [who]
			elif who is Array:
				ids = who
			if ids.is_empty():
				loose[code] = true
			for i in ids:
				if not out.has(str(i)):
					out[str(i)] = []
				if not (out[str(i)] as Array).has(code):
					(out[str(i)] as Array).append(code)
		for k in d:
			if top and LOOK_KEYS.has(str(k)):
				continue
			_pairs(d[k], out, loose, false)
	elif x is Array:
		for v in x:
			_pairs(v, out, loose, false)
