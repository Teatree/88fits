## The Trail (pass 129, lane TRAILCORE; Garry's brief and answers of 2026-11-06, docs/trail_schema.md): the game's
## permanent progression, one long track of nodes bought with gold. It replaces the Upgrade board ("the Mirror" in code),
## which stays beside it until the screen is built. This is the one place the Trail's rules live:
## - the data: content/trail/trail.json (plain JSON, read once; `load_from(path)` for the tests, `load_data(d)` for a tool):
##   `price` (the curve), `sections` (the backdrop), `upgrades` (the upgrade types), `nodes`, `end`;
## - the graph and the rules (trail_schema.md "The rules" 1-6): a node is "bought", "open", "locked" or "closed"; a level
##   is done when every node on it that is neither optional nor closed is bought; the Trail Level is the highest level L
##   with every level 1..L done; a node whose gift the save already has counts as bought at no cost;
## - buying: the price in the Trail's currency (Currency), the node recorded in the save (Save.trail_buy), the gift at once;
## - the gates: a thing some node's `gives` names is locked until that node is bought (`has`); a thing no node names
##   keeps the rule it had (`gated` is false, `has` is true). Every lock hook in the game asks here first;
## - the stat effects: all bought nodes of one upgrade type add up into one effect per stat, source id "trail:<type>",
##   named "The Trail: <name>" (Run.hero_sheet adds them);
## - `check`: the warnings the Level Editor's Trail tab shows.
## With no nodes in the file nothing is gated and nothing can be bought: every hook answers as it did before the Trail.
## States are cached and rebuilt after a buy, a load, or when the save's lists changed (their sizes, or the save's data
## replaced: a wipe, a load, the sandbox put back); a test that edits a list in place without changing its size calls
## `refresh()`.
## Static, and no class it names refers to an autoload at compile time: the Save, the Registry and the Analytics are
## fetched from the tree (tools compile before the autoloads exist), like core/systems/Currency.gd.
class_name Trail
extends RefCounted

const DEFAULT := "res://content/trail/trail.json"
## The unlock quests as they stood when the Trail arrived, {"<quest type>:<id>": quest id} (quest types: weapon, passive,
## character, skin, map). The migration reads it to tell a thing that was free from one whose quest has been retired
## since (its file gone): a retired quest counts as done only when its id is in the save's done list.
const QUESTS_BEFORE := "res://content/trail/quests_before.json"
## An upgrade type's icon (256 px, transparent): its `icon` name in art/ui/trail/.
const ICON := "res://art/ui/trail/%s.png"
## The save's once-flag of the migration (Save._migrate_trail).
const ONCE := "trail_v129"
## What a node may give (`gives.type`). "upgrade" is the only one that is not an unlock.
const GIFTS := ["upgrade", "outlaw", "skin", "weapon", "passive", "stage", "map", "structure", "powerup", "feature"]
const KINDS := ["node", "choice", "optional"]
## How an upgrade type's value is written (`kind`): percent 0.03 -> "+3%", flat "+2", count "+1", seconds "+2 s", word
## (its text alone).
const UPGRADE_KINDS := ["percent", "flat", "count", "seconds", "word"]
const MOTIFS := ["cactus", "star", "skull", "horseshoe", "moon", "flame", "dust", "none"]
## The features a node may open, and the words for each.
const FEATURES := {"wanted": "The Bounty Board"}
## `price` when the file leaves a key out.
const PRICE := {"base": 40.0, "k": 1.5, "power": 2.0, "round": 10.0}
## The name of an upgrade type's source on the sheet (the pause screen's Stats tab).
const SOURCE := "The Trail: %s"
## The reason the saved gold moves under when a node is bought (gold_meta).
const SINK := "trail"
## pass 130: the bundle's words for a Trail that gives nothing, and how its unlocks are counted: [one, many, the gift
## types counted together], in the order they are written (bundle_text)
const BUNDLE_EMPTY := "nothing yet"
const UNLOCK_WORDS := [["outlaw", "outlaws", ["outlaw"]], ["skin", "skins", ["skin"]], ["item", "items", ["weapon", "passive"]],
	["stage", "stages", ["stage"]], ["map", "maps", ["map"]], ["structure", "structures", ["structure"]],
	["power-up", "power-ups", ["powerup"]], ["feature", "features", ["feature"]]]
## The most nodes a level holds (the layout has four places), the sizes of a choice group.
const LEVEL_MAX := 4
const GROUP_MIN := 2
const GROUP_MAX := 4

static var _path := DEFAULT
static var _loaded := false
static var _data: Dictionary = {}
static var _nodes: Array[Dictionary] = []
static var _by_id: Dictionary = {}
## level -> [node id, ...] in file order
static var _by_level: Dictionary = {}
## "<level>|<group>" -> [node id, ...]
static var _groups: Dictionary = {}
## "<type>:<id>" -> [node id, ...] (lowest level first), and the gift types that have a gate at all
static var _gates: Dictionary = {}
static var _gate_types: Dictionary = {}
static var _levels := 0
static var _sections: Array = []
static var _icons: Dictionary = {}
## While the migration looks at the rules as they were (had_before): no gate answers.
static var _off := false

static var _fresh := false
static var _seen_data: Variant = null
static var _seen_sig := -1
static var _bought: Dictionary = {}
static var _closed: Dictionary = {}
static var _done: Dictionary = {}
static var _level := 0
static var _totals: Dictionary = {}
static var _effects: Array = []


# ---------------------------------------------------------------- the autoloads, by path

static func _tree_node(n: String) -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null(n) if ml is SceneTree else null


static func _save() -> Node:
	return _tree_node("Save")


static func _reg() -> Node:
	return _tree_node("Registry")


# ---------------------------------------------------------------- the file

## Reads the Trail again from `path` (the game's own file by default; the tests load a fixture). Not `reload`: the
## class is a script, and Trail.reload(...) would be the engine's own Script.reload(keep_state).
static func load_from(path: String = DEFAULT) -> void:
	_path = path
	_loaded = false
	_ensure()


## The Trail from a dictionary shaped like the file (the tests, a tool's preview); `load_from()` goes back to the file.
static func load_data(d: Dictionary) -> void:
	_path = ""
	_build(d)


## Reads a Trail file: the dictionary, or {} (with a warning) when it is missing or not a JSON object.
static func read_file(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("Trail: %s is not a JSON object; the Trail is empty" % path)
	return {}


static func _ensure() -> void:
	if _loaded:
		return
	_build(read_file(_path))


static func _build(d: Dictionary) -> void:
	_loaded = true
	_data = d
	_nodes = []
	_by_id = {}
	_by_level = {}
	_groups = {}
	_gates = {}
	_gate_types = {}
	_levels = 0
	var raw: Variant = d.get("nodes")
	if raw is Array:
		for e: Variant in (raw as Array):
			if not (e is Dictionary):
				continue
			var n := _norm(e as Dictionary)
			var id := str(n["id"])
			if id == "" or _by_id.has(id):
				continue
			n["index"] = _nodes.size()
			_nodes.append(n)
			_by_id[id] = n
	for n: Dictionary in _nodes:
		var id := str(n["id"])
		var lv := int(n["level"])
		_levels = maxi(_levels, lv)
		if not _by_level.has(lv):
			_by_level[lv] = []
		(_by_level[lv] as Array).append(id)
		if str(n["kind"]) == "choice":
			var gk := _group_key(n)
			if not _groups.has(gk):
				_groups[gk] = []
			(_groups[gk] as Array).append(id)
		# a `from` that names no node of the file is left out (check() says so): a typo never closes a node for good
		var keep: Array = []
		for f: Variant in (n["from"] as Array):
			if _by_id.has(str(f)) and str(f) != id and not keep.has(str(f)):
				keep.append(str(f))
		n["from"] = keep
		var key := gift_key(n["gives"] as Dictionary)
		n["gift"] = key
		if key != "":
			if not _gates.has(key):
				_gates[key] = []
			(_gates[key] as Array).append(id)
			_gate_types[str((n["gives"] as Dictionary).get("type", ""))] = true
	for key: String in _gates.keys():
		(_gates[key] as Array).sort_custom(func(a: String, b: String) -> bool:
			var na: Dictionary = _by_id[a]
			var nb: Dictionary = _by_id[b]
			return int(na["index"]) < int(nb["index"]) if int(na["level"]) == int(nb["level"]) else int(na["level"]) < int(nb["level"]))
	_sections = _norm_sections(d.get("sections"))
	refresh()


## One node as the rules read it: every key present and of its type ({} gives, [] from, "all" need, kind "node").
static func _norm(e: Dictionary) -> Dictionary:
	var kind := str(e.get("kind", "node"))
	if not KINDS.has(kind):
		kind = "node"
	var from: Array = []
	var rf: Variant = e.get("from")
	if rf is Array:
		for f: Variant in (rf as Array):
			from.append(str(f))
	elif rf is String and str(rf) != "":
		from.append(str(rf))
	var gives: Dictionary = (e.get("gives") as Dictionary).duplicate(true) if e.get("gives") is Dictionary else {}
	var out := {"id": str(e.get("id", "")), "level": maxi(_int(e.get("level"), 1), 1), "kind": kind,
		"group": str(e.get("group", "")) if kind == "choice" else "", "from": from,
		"need": "any" if str(e.get("need", "all")) == "any" else "all", "gives": gives,
		"price_mult": maxf(_num(e.get("price_mult"), 1.0), 0.0), "name": str(e.get("name", "")), "note": str(e.get("note", ""))}
	if _is_num(e.get("price")):
		out["price"] = maxi(int(round(float(e["price"]))), 0)
	if _is_num(e.get("x")):
		out["x"] = clampf(float(e["x"]), 0.0, 1.0)
	return out


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if _is_num(v) else fallback


static func _int(v: Variant, fallback: int) -> int:
	return int(round(float(v))) if _is_num(v) else fallback


static func _group_key(n: Dictionary) -> String:
	return "%d|%s" % [int(n["level"]), str(n["group"])]


static func _norm_sections(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for e: Variant in (raw as Array):
			if e is Dictionary:
				var s := e as Dictionary
				var motif := str(s.get("motif", "none"))
				out.append({"from": maxi(_int(s.get("from"), 1), 1), "name": str(s.get("name", "")),
					"top": str(s.get("top", "000000")), "bottom": str(s.get("bottom", "000000")),
					"motif": motif if MOTIFS.has(motif) else "none"})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["from"]) < int(b["from"]))
	return out


## The key a gift is gated under: "<type>:<id>" ("stage:<map>:<stage id>" for a stage); "" for an upgrade or a gift
## that names nothing.
static func gift_key(gives: Dictionary) -> String:
	var type := str(gives.get("type", ""))
	if type == "" or type == "upgrade":
		return ""
	var id := str(gives.get("id", ""))
	if type == "stage" and id == "":
		var m := str(gives.get("map", ""))
		var st := str(gives.get("stage", ""))
		id = "%s:%s" % [m, st] if m != "" and st != "" else ""
	return "%s:%s" % [type, id] if id != "" else ""


# ---------------------------------------------------------------- reading the file

## Whether the Trail has any node (none: nothing is gated, nothing can be bought, the migration waits).
static func has_nodes() -> bool:
	_ensure()
	return not _nodes.is_empty()


## Every node in file order, as the rules read it: {id, level, kind, group, from ([] = the default), need, gives, gift
## (its gate key, "" for an upgrade), price_mult, name, note, index; price and x only when the file gives them}.
static func nodes() -> Array[Dictionary]:
	_ensure()
	return _nodes


## Node `id` ({} when the file has none).
static func node(id: String) -> Dictionary:
	_ensure()
	var n: Variant = _by_id.get(id)
	return n if n is Dictionary else {}


## The highest level any node stands on (0 for an empty Trail).
static func levels() -> int:
	_ensure()
	return _levels


## The nodes on level `l`, in file order.
static func nodes_on(l: int) -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for id: String in _by_level.get(l, []):
		out.append(_by_id[id])
	return out


## The members of node `id`'s choice group, itself among them, in file order ([] for a node that is not a choice).
static func group(id: String) -> Array:
	var n := node(id)
	if n.is_empty() or str(n["kind"]) != "choice":
		return []
	return (_groups.get(_group_key(n), []) as Array).duplicate()


## The currency the Trail is paid in (`currency`; one the content lacks reads as gold).
static func currency() -> String:
	_ensure()
	return Currency.of(str(_data.get("currency", Currency.DEFAULT)))


## The backdrop's sections by their first level: [{from, name, top, bottom (hex without #), motif}].
static func sections() -> Array:
	_ensure()
	return _sections


## The section level `l` lies in ({} with none).
static func section_at(l: int) -> Dictionary:
	var out := {}
	for s: Dictionary in sections():
		if int(s["from"]) <= l:
			out = s
	return out


## The plate above the last level (`end.text`).
static func end_text() -> String:
	_ensure()
	var e: Variant = _data.get("end")
	return str((e as Dictionary).get("text", "")) if e is Dictionary else ""


## Every upgrade type's id, in file order.
static func upgrade_types() -> Array:
	_ensure()
	var u: Variant = _data.get("upgrades")
	return (u as Dictionary).keys() if u is Dictionary else []


## Upgrade type `type`: {name, icon, kind, text, effects: [{stat, op, per}], warn} ({} when the file has none).
static func upgrade(type: String) -> Dictionary:
	_ensure()
	var u: Variant = _data.get("upgrades")
	var e: Variant = (u as Dictionary).get(type) if u is Dictionary else null
	return e if e is Dictionary else {}


## The path of upgrade type `type`'s icon (its `icon` name, else its own id).
static func icon_path(type: String) -> String:
	var name := str(upgrade(type).get("icon", ""))
	return ICON % (name if name != "" else type)


## Upgrade type `type`'s icon, null while its picture is not painted yet.
static func icon(type: String) -> Texture2D:
	var p := icon_path(type)
	if not _icons.has(p):
		_icons[p] = load(p) as Texture2D if ResourceLoader.exists(p) else null
	return _icons[p]


# ---------------------------------------------------------------- prices

## What node `id` costs: its own `price`, else the curve at its level times its `price_mult` (0 for an unknown node).
static func price(id: String) -> int:
	var n := node(id)
	if n.is_empty():
		return 0
	if n.has("price"):
		return int(n["price"])
	var p: Variant = _data.get("price")
	return price_at(p if p is Dictionary else {}, int(n["level"]), float(n["price_mult"]))


## The curve: round_to(base + k * level ^ power, round) * mult, a whole number, never below 0 (`cfg`: the file's
## `price`; PRICE fills what it leaves out).
static func price_at(cfg: Dictionary, lv: int, mult: float = 1.0) -> int:
	var base := _num(cfg.get("base"), float(PRICE["base"]))
	var k := _num(cfg.get("k"), float(PRICE["k"]))
	var power := _num(cfg.get("power"), float(PRICE["power"]))
	var step := _num(cfg.get("round"), float(PRICE["round"]))
	var raw := base + k * pow(float(maxi(lv, 1)), power)
	var v := roundf(raw / step) * step if step > 0.0 else roundf(raw)
	return maxi(int(round(v * mult)), 0)


# ---------------------------------------------------------------- the rules

## Forgets the cached states (after anything that changed what the save holds without going through buy).
static func refresh() -> void:
	_fresh = false


static func _sig(d: Variant) -> int:
	if not (d is Dictionary):
		return -1
	var dd := d as Dictionary
	var t: Variant = dd.get("trail")
	var a := 0
	var b := 0
	if t is Dictionary:
		var tb: Variant = (t as Dictionary).get("bought")
		var th: Variant = (t as Dictionary).get("had")
		a = (tb as Array).size() if tb is Array else 0
		b = (th as Array).size() if th is Array else 0
	var ho: Variant = dd.get("heroes_owned")
	var so: Variant = dd.get("skins_owned")
	var c: int = (ho as Array).size() if ho is Array else 0
	var e: int = (so as Array).size() if so is Array else 0
	return ((a * 4099 + b) * 4099 + c) * 4099 + e


static func _ensure_states() -> void:
	_ensure()
	var sv := _save()
	var d: Variant = sv.get("data") if sv else null
	var sig := _sig(d)
	if _fresh and sig == _seen_sig and is_same(d, _seen_data):
		return
	_fresh = true
	_seen_sig = sig
	_seen_data = d
	_bought = {}
	_closed = {}
	_done = {}
	_level = 0
	_totals = {}
	_effects = []
	if _nodes.is_empty():
		return
	# what the save holds: the nodes bought, and the gifts it already has (kept from before the Trail, an outlaw or a
	# skin it owns)
	var had := {}
	if d is Dictionary:
		var t: Variant = (d as Dictionary).get("trail")
		if t is Dictionary:
			var tb: Variant = (t as Dictionary).get("bought")
			if tb is Array:
				for id: Variant in (tb as Array):
					_bought[str(id)] = true
			var th: Variant = (t as Dictionary).get("had")
			if th is Array:
				for k: Variant in (th as Array):
					had[str(k)] = true
		var ho: Variant = (d as Dictionary).get("heroes_owned")
		if ho is Array:
			for h: Variant in (ho as Array):
				had["outlaw:" + str(h)] = true
		var so: Variant = (d as Dictionary).get("skins_owned")
		if so is Array:
			for s: Variant in (so as Array):
				had["skin:" + str(s)] = true
	for n: Dictionary in _nodes:
		if str(n["gift"]) != "" and had.has(str(n["gift"])):
			_bought[str(n["id"])] = true
	# closed: a sibling of its choice group bought, or a `from` that can no longer be met
	var visiting := {}
	for n: Dictionary in _nodes:
		_is_closed(str(n["id"]), visiting)
	# a level is done when every node on it that is neither optional nor closed is bought
	for l in range(1, _levels + 1):
		var ok := true
		for id: String in _by_level.get(l, []):
			if str((_by_id[id] as Dictionary)["kind"]) != "optional" and not _bought.has(id) and not bool(_closed.get(id, false)):
				ok = false
				break
		_done[l] = ok
	while _level < _levels and bool(_done.get(_level + 1, false)):
		_level += 1
	# the upgrades: every bought node of a type added up, one effect per stat
	for n: Dictionary in _nodes:
		var g: Dictionary = n["gives"]
		if str(g.get("type", "")) == "upgrade" and _bought.has(str(n["id"])):
			var ut := str(g.get("upgrade", ""))
			_totals[ut] = float(_totals.get(ut, 0.0)) + _num(g.get("value"), 0.0)
	for ut: Variant in upgrade_types():
		var sum := float(_totals.get(str(ut), 0.0))
		if absf(sum) < 0.0000001:
			continue
		var u := upgrade(str(ut))
		var list: Array = []
		var raw: Variant = u.get("effects")
		if raw is Array:
			for e: Variant in (raw as Array):
				if e is Dictionary and str((e as Dictionary).get("stat", "")) != "":
					var op := str((e as Dictionary).get("op", "add"))
					list.append(Effect.make(str(e["stat"]), op if op == "mul" else "add", sum * _num((e as Dictionary).get("per"), 1.0), "player"))
		if not list.is_empty():
			_effects.append({"effects": list, "name": SOURCE % str(u.get("name", ut)), "source": "trail:" + str(ut), "type": str(ut), "value": sum})


static func _is_closed(id: String, visiting: Dictionary) -> bool:
	if _bought.has(id):
		return false
	if _closed.has(id):
		return bool(_closed[id])
	if visiting.has(id):
		# a ring of `from`s can never be bought into
		return true
	visiting[id] = true
	var n: Dictionary = _by_id[id]
	var c := false
	if str(n["kind"]) == "choice":
		for sib: String in _groups.get(_group_key(n), []):
			if sib != id and _bought.has(sib):
				c = true
				break
	var from: Array = n["from"]
	if not c and not from.is_empty():
		var dead := 0
		for f: String in from:
			if _is_closed(f, visiting):
				dead += 1
		c = dead == from.size() if str(n["need"]) == "any" else dead > 0
	visiting.erase(id)
	_closed[id] = c
	return c


## Whether node `n`'s `from` is met: every one bought (`all`), or one of them (`any`). A node that names none hangs on
## the level below it, which the level gate already asks for.
static func _from_met(n: Dictionary) -> bool:
	var from: Array = n["from"]
	if from.is_empty():
		return true
	var got := 0
	for f: String in from:
		if _bought.has(f):
			got += 1
	return got > 0 if str(n["need"]) == "any" else got == from.size()


## Where the player stands with node `id`: "bought" (paid for, or its gift already his), "open" (can be bought),
## "closed" (for good: a sibling was chosen, or what it hangs on is closed) or "locked" (an unknown node too).
static func state(id: String) -> String:
	_ensure_states()
	if not _by_id.has(id):
		return "locked"
	if _bought.has(id):
		return "bought"
	if bool(_closed.get(id, false)):
		return "closed"
	var n: Dictionary = _by_id[id]
	if int(n["level"]) <= _level + 1 and _from_met(n):
		return "open"
	return "locked"


## The Trail Level: the highest level L with every level 1..L done (0 on a new save).
static func level() -> int:
	_ensure_states()
	return _level


## Whether level `l` is done: every node on it that is neither optional nor closed is bought (a level with no such
## node is done; a level past the last one is not).
static func level_done(l: int) -> bool:
	_ensure_states()
	return bool(_done.get(l, false))


## The nodes a rail is drawn to node `id` from: its `from`, else every required node of the nearest lower level that
## has one (closed ones left out; a choice group as the one chosen, all its members while none is).
static func from_of(id: String) -> Array:
	_ensure_states()
	var n := node(id)
	if n.is_empty():
		return []
	if not (n["from"] as Array).is_empty():
		return (n["from"] as Array).duplicate()
	var out: Array = []
	var l := int(n["level"]) - 1
	while l >= 1 and out.is_empty():
		for other: String in _by_level.get(l, []):
			var o: Dictionary = _by_id[other]
			if str(o["kind"]) == "optional" or bool(_closed.get(other, false)):
				continue
			out.append(other)
		l -= 1
	return out


## Whether node `id` can be bought now: open, and the purse holds its price.
static func can_buy(id: String) -> bool:
	return state(id) == "open" and Currency.can_afford(currency(), price(id))


## Buys node `id`: only an open one the purse can pay; the price leaves the purse (reason "trail"), the save records the
## node and what it cost, the gift is the player's at once (every gate and the next run's sheet read it), and the
## `trail_buy` event goes out {node, level, type, what, value, price}. True when it is bought after it.
static func buy(id: String) -> bool:
	if state(id) != "open":
		return false
	var sv := _save()
	if sv == null:
		return false
	var n := node(id)
	var g: Dictionary = n["gives"]
	var type := str(g.get("type", ""))
	var cost := price(id)
	var info := {"node": id, "level": int(n["level"]), "type": type,
		"what": str(g.get("upgrade", "")) if type == "upgrade" else str(n["gift"]).trim_prefix(type + ":"), "price": cost}
	if type == "upgrade":
		info["value"] = _num(g.get("value"), 0.0)
	if not Currency.spend(currency(), cost, SINK, info):
		return false
	sv.call("trail_buy", id, cost)
	refresh()
	var an := _tree_node("Analytics")
	if an and an.has_method("track"):
		an.call("track", "trail_buy", info)
	return true


## Whether any node can be bought now (the tab's red crumb).
static func any_affordable() -> bool:
	_ensure_states()
	if _nodes.is_empty():
		return false
	var purse := Currency.balance(currency())
	for n: Dictionary in _nodes:
		var id := str(n["id"])
		if state(id) == "open" and price(id) <= purse:
			return true
	return false


# ---------------------------------------------------------------- the gates

## Whether some node gives `type` `id` ("stage" ids are "<map>:<stage id>", "skin" ids "<outlaw>:<CODE>").
static func gated(type: String, id: String) -> bool:
	_ensure()
	return not _off and _gate_types.has(type) and _gates.has(type + ":" + id)


## The node that gives `type` `id` (the lowest when several do), {} if none.
static func gate(type: String, id: String) -> Dictionary:
	if not gated(type, id):
		return {}
	return _by_id[str((_gates[type + ":" + id] as Array)[0])]


## Whether the player has `type` `id` as far as the Trail goes: no node gives it, or one that does is bought.
static func has(type: String, id: String) -> bool:
	if not gated(type, id):
		return true
	_ensure_states()
	for nid: String in _gates[type + ":" + id]:
		if _bought.has(nid):
			return true
	return false


## N of "Reach Trail Level N" for `type` `id`: its node's level, 0 when no node gives it.
static func level_for(type: String, id: String) -> int:
	var g := gate(type, id)
	return int(g["level"]) if not g.is_empty() else 0


## What a locked thing reads: "Reach Trail Level N" ("" when no node gives it).
static func requirement_text(type: String, id: String) -> String:
	var n := level_for(type, id)
	return "Reach Trail Level %d" % n if n > 0 else ""


## The gate id of stage `i` (0-based) of map `map_id`: "<map>:<stage id>" ("" for a map or a timeline the game lacks).
static func stage_key(map_id: String, i: int) -> String:
	var reg := _reg()
	var maps: Variant = reg.get("maps") if reg else null
	var m: Variant = (maps as Dictionary).get(map_id) if maps is Dictionary else null
	var tl: Variant = (m as Object).get("timeline") if m is Object else null
	if not (tl is Object) or not (tl as Object).has_method("stage_id"):
		return ""
	return "%s:%s" % [map_id, str((tl as Object).call("stage_id", i))]


## Whether the Trail lets stage `i` (0-based) of map `map_id` be played (Save.stage_unlocked asks it beside its own
## rule, the stage before it beaten).
static func stage_open(map_id: String, i: int) -> bool:
	_ensure()
	if _off or not _gate_types.has("stage"):
		return true
	var key := stage_key(map_id, i)
	return key == "" or has("stage", key)


## The rows of a weighted roster ([{id, ...}]) whose `type` the player has: the same list when no node gives any of
## that type (the power-up rosters of the drops, the barrels and a timed roster).
static func rows_open(type: String, rows: Array) -> Array:
	_ensure()
	if _off or not _gate_types.has(type):
		return rows
	return rows.filter(func(r: Variant) -> bool: return not (r is Dictionary) or has(type, str((r as Dictionary).get("id", ""))))


# ---------------------------------------------------------------- the stat effects and the words

## The bought upgrades for Run.hero_sheet: one entry per upgrade type with a node bought, in the file's order,
## {effects: Array[Effect] (the stat gets the summed value x `per`, aimed at the player), name ("The Trail: Might"),
## source ("trail:might"), type, value (the sum)}.
static func effects() -> Array:
	_ensure_states()
	return _effects


## The summed value of upgrade type `type` over the bought nodes (0 with none).
static func total(type: String) -> float:
	_ensure_states()
	return float(_totals.get(type, 0.0))


## An amount as upgrade kind `kind` writes it: "+3%", "+2.5%", "+2", "+0.3", "+1", "+2 s"; "" for a word.
static func amount_text(kind: String, value: float) -> String:
	var sg := "+" if value >= 0.0 else "−"
	var a := absf(value)
	match kind:
		"percent":
			return sg + _plain(a * 100.0) + "%"
		"count":
			return sg + str(int(round(a)))
		"seconds":
			return sg + _plain(a) + " s"
		"word":
			return ""
	return sg + _plain(a)


static func _plain(a: float) -> String:
	if absf(a - roundf(a)) < 0.001:
		return str(int(roundf(a)))
	if absf(a * 10.0 - roundf(a * 10.0)) < 0.001:
		return "%.1f" % a
	return "%.2f" % a


## What buying node `n` gives, in words: "Attack damage +3%", "Outlaw: Astro", "Skin: Astro, Moonwalker", "Weapon: Tommy
## Gun", "Card: The Tower", "Item: Cake", "Stage: Nightfall", "Map: Red Canyon", "Structure: Totem Pole", "Power-up:
## Rage", "The Bounty Board". A name the content lacks reads as its id.
static func give_text(n: Dictionary) -> String:
	var gv: Variant = n.get("gives")
	var g: Dictionary = gv if gv is Dictionary else {}
	var type := str(g.get("type", ""))
	var id := str(g.get("id", ""))
	var reg := _reg()
	match type:
		"upgrade":
			var u := upgrade(str(g.get("upgrade", "")))
			var words := str(u.get("text", u.get("name", str(g.get("upgrade", "")))))
			var amount := amount_text(str(u.get("kind", "flat")), _num(g.get("value"), 0.0))
			return words if amount == "" else "%s %s" % [words, amount]
		"outlaw":
			return "Outlaw: %s" % _name_in(reg, "characters", id)
		"skin":
			var hero := id.get_slice(":", 0)
			var code := id.get_slice(":", 1)
			var chars: Variant = reg.get("characters") if reg else null
			var c: Variant = (chars as Dictionary).get(hero) if chars is Dictionary else null
			var skin := str((c as Object).call("skin_name", code)) if c is Object and (c as Object).has_method("skin_name") else code
			return "Skin: %s, %s" % [_name_in(reg, "characters", hero), skin]
		"weapon":
			return "Weapon: %s" % _name_in(reg, "weapons", id)
		"passive":
			var ps: Variant = reg.get("passives") if reg else null
			var p: Variant = (ps as Dictionary).get(id) if ps is Dictionary else null
			var line := p is Object and bool((p as Object).get("line"))
			return "%s: %s" % ["Card" if line else "Item", _name_in(reg, "passives", id)]
		"stage":
			var map_id := str(g.get("map", id.get_slice(":", 0)))
			var stage_id := str(g.get("stage", id.get_slice(":", 1)))
			return "Stage: %s" % _stage_name(reg, map_id, stage_id)
		"map":
			return "Map: %s" % _name_in(reg, "maps", id)
		"structure":
			return "Structure: %s" % _name_in(reg, "structures", id)
		"powerup":
			return "Power-up: %s" % _name_in(reg, "pickups", id)
		"feature":
			return str(FEATURES.get(id, id.capitalize()))
	return ""


static func _name_in(reg: Node, table: String, id: String) -> String:
	var all: Variant = reg.get(table) if reg else null
	var d: Variant = (all as Dictionary).get(id) if all is Dictionary else null
	var n := str((d as Object).get("display_name")) if d is Object else ""
	return n if n != "" and n != "<null>" else id.capitalize()


## The index (0-based) of the stage of map `map_id` whose id is `stage_id`, -1 when the map has none.
static func stage_index(map_id: String, stage_id: String) -> int:
	var reg := _reg()
	var maps: Variant = reg.get("maps") if reg else null
	var m: Variant = (maps as Dictionary).get(map_id) if maps is Dictionary else null
	var tl: Variant = (m as Object).get("timeline") if m is Object else null
	if not (tl is Object) or not (tl as Object).has_method("stage_count"):
		return -1
	for k in range(int((tl as Object).call("stage_count"))):
		if str((tl as Object).call("stage_id", k)) == stage_id:
			return k
	return -1


static func _stage_name(reg: Node, map_id: String, stage_id: String) -> String:
	var k := stage_index(map_id, stage_id)
	if k < 0:
		return stage_id.capitalize()
	var maps: Dictionary = reg.get("maps")
	return str(((maps[map_id] as Object).get("timeline") as Object).call("stage_name", k))


## The toast for the note the migration left (Save.board_note, kind "trail_refund"): "The Upgrade board is now the
## Trail. Your 2,400 coins are back." ("" for any other note; no coins: the first sentence alone).
static func note_text(note: Dictionary) -> String:
	if str(note.get("kind", "")) != "trail_refund":
		return ""
	var n := int(note.get("gold", 0))
	if n <= 0:
		return "The Upgrade board is now the Trail."
	return "The Upgrade board is now the Trail. Your %s coin%s back." % [_grouped(n), " is" if n == 1 else "s are"]


static func _grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The run record's block (RunAnalytics, header `trail`): the Trail as the run began, {level, bought (node ids, file
## order, the ones a gift already had among them), paid (how many of them were paid for), spent, upgrades {type: summed
## value} (pass 130: in the file's order of upgrade types), unlocks {gift type: how many bought nodes gave one} (pass
## 130)}.
static func record() -> Dictionary:
	_ensure_states()
	var ids: Array = []
	for n: Dictionary in _nodes:
		if _bought.has(str(n["id"])):
			ids.append(str(n["id"]))
	var sv := _save()
	var t := tally(ids)
	return {"level": _level, "bought": ids, "paid": (sv.call("trail_bought") as Array).size() if sv else 0,
		"spent": int(sv.call("trail_spent")) if sv else 0, "upgrades": t["upgrades"], "unlocks": t["unlocks"]}


# ---------------------------------------------------------------- the bundle (pass 130)

## Pass 130 (lane HOUSE; Garry: "whenever we do show the level of trail, we also show the stats increases as just a
## bundle (a list of comma-separated increases) ... in one build, the trail is giving one set of stat increases and in
## the other build it's giving a different set"). What the nodes `ids` give, added up without a save: {upgrades {type:
## summed value}, in the file's order of upgrade types (a type the file lacks after them), unlocks {gift type: how
## many}, in GIFTS' order}. Ids the Trail has no node for are skipped.
static func tally(ids: Array) -> Dictionary:
	_ensure()
	var sums := {}
	var gifts := {}
	for id: Variant in ids:
		var n: Variant = _by_id.get(str(id))
		if not (n is Dictionary):
			continue
		var g: Dictionary = (n as Dictionary)["gives"]
		var type := str(g.get("type", ""))
		if type == "upgrade":
			var ut := str(g.get("upgrade", ""))
			sums[ut] = float(sums.get(ut, 0.0)) + _num(g.get("value"), 0.0)
		elif type != "":
			gifts[type] = int(gifts.get(type, 0)) + 1
	var ups := {}
	for ut: Variant in upgrade_types():
		if sums.has(str(ut)):
			ups[str(ut)] = snappedf(float(sums[str(ut)]), 0.0001)
	for ut: Variant in sums.keys():
		if not ups.has(str(ut)):
			ups[str(ut)] = snappedf(float(sums[ut]), 0.0001)
	var unlocks := {}
	for type: String in GIFTS:
		if gifts.has(type):
			unlocks[type] = int(gifts[type])
	return {"upgrades": ups, "unlocks": unlocks}


## The bundle: what a Trail gives, on one line, wherever a tool shows a Trail Level: "Attack damage +12%, Max health
## +30%, Reroll a run +2 · unlocks: 2 outlaws, 3 items, 1 stage"; BUNDLE_EMPTY ("nothing yet") for a Trail that gives
## nothing. `block` is a trail block (record(), RunAnalytics.trail_block, tally()): its `upgrades` {type: summed value}
## are written in the block's own order with the words of its `types` ({type: {name, kind, text}}) when it carries
## them, so a record from another build reads as THAT build's Trail; a block without `types` reads by this build's
## upgrade types, in the file's order. A type reads "<text> <amount>" (amount_text by its kind; without a text its
## name, without either its id), a word-kind type by its name alone, a sum of 0 not at all. Then the block's `unlocks`
## {gift type: count} in short (UNLOCK_WORDS; weapons, cards and items all count as "items"); a block without
## `unlocks` (a record from before pass 130) names none.
## tools/level_editor/trail_bundle.js and tools/trail_bundle.py are this function's twins: change all three (the
## fixture game/tests/fixtures/trail_bundle.json pins them together).
static func bundle_text(block: Dictionary) -> String:
	var raw: Variant = block.get("upgrades")
	var ups: Dictionary = raw if raw is Dictionary else {}
	var own: Variant = block.get("types")
	var order: Array = []
	if own is Dictionary:
		order = ups.keys()
	else:
		for ut: Variant in upgrade_types():
			if ups.has(ut):
				order.append(ut)
		for ut: Variant in ups.keys():
			if not order.has(ut):
				order.append(ut)
	var parts := PackedStringArray()
	for ut: Variant in order:
		var uv: Variant = (own as Dictionary).get(ut) if own is Dictionary else upgrade(str(ut))
		var u: Dictionary = uv if uv is Dictionary else {}
		var kind := str(u.get("kind", "flat"))
		var name := str(u.get("name", ""))
		var text := str(u.get("text", ""))
		if kind == "word":
			parts.append(name if name != "" else (text if text != "" else str(ut)))
			continue
		var value := _num(ups[ut], 0.0)
		if absf(value) < 0.0000001:
			continue
		parts.append("%s %s" % [text if text != "" else (name if name != "" else str(ut)), amount_text(kind, value)])
	var got := PackedStringArray()
	var un: Variant = block.get("unlocks")
	if un is Dictionary:
		for w: Array in UNLOCK_WORDS:
			var n := 0
			for type: Variant in (w[2] as Array):
				n += _int((un as Dictionary).get(type), 0)
			if n > 0:
				got.append("%d %s" % [n, str(w[0]) if n == 1 else str(w[1])])
	var out := ", ".join(parts)
	if not got.is_empty():
		out += (" · " if out != "" else "") + "unlocks: " + ", ".join(got)
	return out if out != "" else BUNDLE_EMPTY


## The bundle of the nodes `ids` (tally): what a tool's Trail gives before any run has a record.
static func bundle_of(ids: Array) -> String:
	return bundle_text(tally(ids))


## The bundle of the Trail the save holds now (record()).
static func bundle() -> String:
	return bundle_text(record())


# ---------------------------------------------------------------- the migration's look at the save

## The gifts the save has by the rules as they were before the Trail (Save._migrate_trail keeps them in `trail.had`, so
## a node that gives one counts as bought at no cost): every outlaw owned ("outlaw:<id>"), every skin owned
## ("skin:<outlaw>:<CODE>"), every weapon, card, item and map that was not locked ("weapon:<id>", "passive:<id>",
## "map:<id>": no quest, or its quest done; a quest retired since counts by QUESTS_BEFORE), every stage open now
## ("stage:<map>:<stage id>"), every structure and power-up in play ("structure:<id>", "powerup:<id>"), and the Bounty
## Board when it had opened ("feature:wanted"). Every gate is off while it looks, so the rules answer as they did.
static func had_before() -> Array:
	var out: Array = []
	var sv := _save()
	var reg := _reg()
	if sv == null or reg == null:
		return out
	var before := read_file(QUESTS_BEFORE)
	var was := _off
	_off = true
	var chars: Dictionary = reg.get("characters")
	for cid: Variant in chars.keys():
		var c: Object = chars[cid]
		var id := str(cid)
		if str(reg.call("hero_state", c)) == "owned" and (bool(sv.call("owns_hero", id)) or _quest_was_done(sv, reg, before, "character", id)):
			out.append("outlaw:" + id)
		var variants: Variant = c.get("variants")
		if variants is Dictionary and not bool(c.get("hidden")):
			for code: Variant in (variants as Dictionary).keys():
				var key := "%s:%s" % [id, str(code)]
				if str(code) != str(c.call("home_look")) and str(reg.call("skin_state", c, str(code))) == "owned" \
						and (bool(sv.call("owns_skin", key)) or _quest_was_done(sv, reg, before, "skin", key)):
					out.append("skin:" + key)
	for pair: Array in [["weapon", "weapons"], ["passive", "passives"], ["map", "maps"]]:
		var all: Dictionary = reg.get(str(pair[1]))
		for iid: Variant in all.keys():
			if bool(reg.call("is_unlocked", str(pair[0]), str(iid))) and _quest_was_done(sv, reg, before, str(pair[0]), str(iid)):
				out.append("%s:%s" % [str(pair[0]), str(iid)])
	var maps: Dictionary = reg.get("maps")
	for mid: Variant in maps.keys():
		var tl: Variant = (maps[mid] as Object).get("timeline")
		if tl is Object and (tl as Object).has_method("stage_count"):
			for k in range(int((tl as Object).call("stage_count"))):
				if bool(sv.call("stage_unlocked", str(mid), k)):
					out.append("stage:%s:%s" % [str(mid), str((tl as Object).call("stage_id", k))])
	var structures: Dictionary = reg.get("structures")
	for sid: Variant in structures.keys():
		if not bool((structures[sid] as Object).get("hidden")):
			out.append("structure:" + str(sid))
	var pickups: Dictionary = reg.get("pickups")
	for pid: Variant in pickups.keys():
		out.append("powerup:" + str(pid))
	var wanted: Variant = load("res://core/systems/WantedBoard.gd")
	if wanted is Script and bool(wanted.unlocked()):
		out.append("feature:wanted")
	_off = was
	out.sort()
	return out


## Whether the quest that locked `qtype` `id` before the Trail was done: true with no quest then (it was free); with a
## quest still in the content, the rule that just answered has asked it; with one retired since (QUESTS_BEFORE names it,
## the content has it no more), whether the save's done list holds its id.
static func _quest_was_done(sv: Node, reg: Node, before: Dictionary, qtype: String, id: String) -> bool:
	if reg.call("quest_for", qtype, id) != null:
		return true
	var q := str(before.get("%s:%s" % [qtype, id], ""))
	return q == "" or bool(sv.call("quest_done", q))


# ---------------------------------------------------------------- the warnings (the Level Editor shows the same)

## What is wrong or doubtful in a Trail file `data` (the dictionary as read), one line each, "<where>: <what>"; [] for a
## sound file. The game plays a file with warnings as well as it can (docs/trail_schema.md "Warnings" lists them).
static func check(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var reg := _reg()
	# the price curve and the currency
	var p: Variant = data.get("price")
	if not (p is Dictionary):
		out.append("price: missing (base, k, power, round)")
	else:
		for k: String in PRICE.keys():
			if not _is_num((p as Dictionary).get(k)):
				out.append("price: '%s' is not a number" % k)
		if _num((p as Dictionary).get("round"), 1.0) < 0.0 or _num((p as Dictionary).get("k"), 0.0) < 0.0 or _num((p as Dictionary).get("base"), 0.0) < 0.0:
			out.append("price: base, k and round cannot be negative")
	var cur := str(data.get("currency", ""))
	if cur == "" or not Currency.known(cur):
		out.append("currency: '%s' is not a currency the content has (gold is used)" % cur)
	# the sections
	var secs: Variant = data.get("sections")
	if not (secs is Array) or (secs as Array).is_empty():
		out.append("sections: none (the backdrop needs one that starts at level 1)")
	else:
		var last := 0
		var first := true
		for s: Variant in (secs as Array):
			if not (s is Dictionary):
				out.append("sections: an entry is not an object")
				continue
			var sd := s as Dictionary
			var from := _int(sd.get("from"), 0)
			var where := "section '%s'" % str(sd.get("name", from))
			if first and from != 1:
				out.append("%s: the first section must start at level 1" % where)
			if not first and from <= last:
				out.append("%s: starts at level %d, not after the section before it (%d)" % [where, from, last])
			first = false
			last = from
			for ck: String in ["top", "bottom"]:
				if not str(sd.get(ck, "")).is_valid_hex_number() or str(sd.get(ck, "")).length() != 6:
					out.append("%s: '%s' is not a colour (six hex digits, no #)" % [where, ck])
			if not MOTIFS.has(str(sd.get("motif", "none"))):
				out.append("%s: unknown motif '%s'" % [where, str(sd.get("motif", ""))])
	# the upgrade types
	var ups: Variant = data.get("upgrades")
	var types: Dictionary = ups if ups is Dictionary else {}
	for t: Variant in types.keys():
		var where := "upgrade '%s'" % str(t)
		var u: Variant = types[t]
		if not (u is Dictionary):
			out.append("%s: not an object" % where)
			continue
		var ud := u as Dictionary
		if str(ud.get("name", "")) == "":
			out.append("%s: no name" % where)
		if not UPGRADE_KINDS.has(str(ud.get("kind", ""))):
			out.append("%s: unknown kind '%s'" % [where, str(ud.get("kind", ""))])
		var icon_name := str(ud.get("icon", ""))
		if icon_name == "":
			out.append("%s: no icon" % where)
		elif not ResourceLoader.exists(ICON % icon_name) and not FileAccess.file_exists(ICON % icon_name):
			out.append("%s: its icon art/ui/trail/%s.png is missing" % [where, icon_name])
		var effs: Variant = ud.get("effects")
		if not (effs is Array) or (effs as Array).is_empty():
			out.append("%s: no effects" % where)
		else:
			for e: Variant in (effs as Array):
				if not (e is Dictionary):
					out.append("%s: an effect is not an object" % where)
					continue
				var stat := str((e as Dictionary).get("stat", ""))
				if not StatSheet.PLAYER_DEFAULTS.has(stat):
					out.append("%s: '%s' is not a stat of the outlaw's sheet" % [where, stat])
				if not ["add", "mul"].has(str((e as Dictionary).get("op", ""))):
					out.append("%s: %s's op must be add or mul" % [where, stat])
				if absf(_num((e as Dictionary).get("per"), 0.0)) < 0.0000001:
					out.append("%s: %s's per is 0 or missing" % [where, stat])
	# the nodes
	var raw: Variant = data.get("nodes")
	var list: Array = raw if raw is Array else []
	var by_id := {}
	var per_level := {}
	var groups := {}
	var given := {}
	for e: Variant in list:
		if not (e is Dictionary):
			out.append("nodes: an entry is not an object")
			continue
		var id := str((e as Dictionary).get("id", ""))
		if id == "":
			out.append("nodes: a node has no id")
			continue
		if by_id.has(id):
			out.append("node %s: its id is used twice (the second is ignored)" % id)
			continue
		by_id[id] = e
	for id: String in by_id.keys():
		var e: Dictionary = by_id[id]
		var where := "node %s" % id
		var lv := _int(e.get("level"), 0)
		if lv < 1:
			out.append("%s: its level must be 1 or more" % where)
			lv = 1
		per_level[lv] = int(per_level.get(lv, 0)) + 1
		var kind := str(e.get("kind", "node"))
		if not KINDS.has(kind):
			out.append("%s: unknown kind '%s' (read as a plain node)" % [where, kind])
			kind = "node"
		if kind == "choice":
			var gk := "%d|%s" % [lv, str(e.get("group", ""))]
			if str(e.get("group", "")) == "":
				out.append("%s: a choice without a group" % where)
			if not groups.has(gk):
				groups[gk] = []
			(groups[gk] as Array).append(id)
		elif str(e.get("group", "")) != "":
			out.append("%s: only a choice has a group" % where)
		if e.has("need") and not ["all", "any"].has(str(e.get("need"))):
			out.append("%s: need must be all or any" % where)
		var rf: Variant = e.get("from")
		if rf is Array:
			for f: Variant in (rf as Array):
				var fid := str(f)
				if fid == id:
					out.append("%s: names itself in from" % where)
				elif not by_id.has(fid):
					out.append("%s: from names '%s', which is no node (left out)" % [where, fid])
				else:
					var fl := _int((by_id[fid] as Dictionary).get("level"), 1)
					if fl > lv:
						out.append("%s: from names %s, which stands above it (level %d)" % [where, fid, fl])
					elif fl == lv and kind != "optional":
						out.append("%s: from names %s of its own level (only an optional node may)" % [where, fid])
		elif e.has("from"):
			out.append("%s: from must be a list of node ids" % where)
		if e.has("price") and (not _is_num(e.get("price")) or float(e["price"]) < 0.0):
			out.append("%s: its price must be a number, 0 or more" % where)
		if e.has("price_mult") and (not _is_num(e.get("price_mult")) or float(e["price_mult"]) <= 0.0):
			out.append("%s: its price_mult must be more than 0" % where)
		if e.has("x") and (not _is_num(e.get("x")) or float(e["x"]) < 0.0 or float(e["x"]) > 1.0):
			out.append("%s: x must be between 0 and 1" % where)
		elif _is_num(e.get("x")) and float(e["x"]) > 0.75:
			out.append("%s: x %.2f is in the right quarter, which is kept free" % [where, float(e["x"])])
		var gv: Variant = e.get("gives")
		if not (gv is Dictionary):
			out.append("%s: gives nothing" % where)
			continue
		var g := gv as Dictionary
		var type := str(g.get("type", ""))
		if not GIFTS.has(type):
			out.append("%s: gives an unknown type '%s'" % [where, type])
			continue
		if type == "upgrade":
			var ut := str(g.get("upgrade", ""))
			if not types.has(ut):
				out.append("%s: gives an unknown upgrade type '%s'" % [where, ut])
			if not _is_num(g.get("value")) or absf(float(g["value"])) < 0.0000001:
				out.append("%s: its upgrade has no value" % where)
			continue
		var key := gift_key(g)
		if key == "":
			out.append("%s: its %s names nothing" % [where, type])
			continue
		if given.has(key):
			out.append("%s: gives %s, which %s gives too" % [where, key, str(given[key])])
		else:
			given[key] = id
		if kind == "choice":
			out.append("%s: an unlock (%s) in a choice group could be lost for good" % [where, key])
		var miss := _missing(reg, type, g, key)
		if miss != "":
			out.append("%s: %s" % [where, miss])
	for gk: String in groups.keys():
		var n := (groups[gk] as Array).size()
		if n < GROUP_MIN or n > GROUP_MAX:
			out.append("choice group '%s' on level %s: %d member%s (%d to %d)" % [gk.get_slice("|", 1), gk.get_slice("|", 0), n,
				"" if n == 1 else "s", GROUP_MIN, GROUP_MAX])
	var top := 0
	for lv: int in per_level.keys():
		top = maxi(top, lv)
		if int(per_level[lv]) > LEVEL_MAX:
			out.append("level %d: %d nodes (the layout has room for %d)" % [lv, int(per_level[lv]), LEVEL_MAX])
	for lv in range(1, top):
		if not per_level.has(lv):
			out.append("level %d: no nodes (the Trail Level passes it by)" % lv)
	return out


## Why the content cannot give what a node names ("" when it can): an id the game lacks, a hidden one, a stage the map
## does not have, the first stage, a feature the game does not know.
static func _missing(reg: Node, type: String, g: Dictionary, key: String) -> String:
	if reg == null:
		return ""
	var id := key.trim_prefix(type + ":")
	match type:
		"outlaw":
			return _missing_in(reg, "characters", id, "outlaw")
		"skin":
			var hero := id.get_slice(":", 0)
			var code := id.get_slice(":", 1)
			var miss := _missing_in(reg, "characters", hero, "outlaw")
			if miss != "":
				return miss
			var c: Object = (reg.get("characters") as Dictionary)[hero]
			var variants: Variant = c.get("variants")
			if not (variants is Dictionary) or not (variants as Dictionary).has(code):
				return "%s has no look '%s'" % [hero, code]
			if code == str(c.call("home_look")):
				return "'%s' is the look every player owns" % code
			return ""
		"weapon":
			return _missing_in(reg, "weapons", id, "weapon")
		"passive":
			return _missing_in(reg, "passives", id, "card or item")
		"map":
			return _missing_in(reg, "maps", id, "map")
		"structure":
			return _missing_in(reg, "structures", id, "structure")
		"powerup":
			return _missing_in(reg, "pickups", id, "power-up")
		"stage":
			var map_id := str(g.get("map", id.get_slice(":", 0)))
			var stage_id := str(g.get("stage", id.get_slice(":", 1)))
			var miss := _missing_in(reg, "maps", map_id, "map")
			if miss != "":
				return miss
			var k := stage_index(map_id, stage_id)
			if k < 0:
				return "map %s has no stage '%s'" % [map_id, stage_id]
			if k == 0:
				return "'%s' is the map's first stage: a new save could not play at all" % stage_id
			return ""
		"feature":
			return "" if FEATURES.has(id) else "'%s' is not a feature the game knows (%s)" % [id, ", ".join(PackedStringArray(FEATURES.keys()))]
	return ""


static func _missing_in(reg: Node, table: String, id: String, word: String) -> String:
	var all: Variant = reg.get(table)
	var d: Variant = (all as Dictionary).get(id) if all is Dictionary else null
	if not (d is Object):
		return "'%s' is no %s the game has" % [id, word]
	if (d as Object).get("hidden") == true:
		return "the %s '%s' is hidden (out of play)" % [word, id]
	return ""
