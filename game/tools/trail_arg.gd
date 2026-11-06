## What a tool's `trail=` argument means (pass 129, lane TRAIL-REMOVE). The Trail replaced the Upgrade board, so the run
## sim, the Watch and the probes say how far a player's permanent upgrades are as a Trail Level where they said
## `board=` / `mirror=` / `talents=`:
##   trail=none | quarter | half | full | <level>      trail_optional=1      (trail_ids=n001,n002,... = these nodes exactly)
## The tool's save gets every required node of levels 1..N bought at no cost (`trail.bought`, `trail.spent` 0): plain
## nodes all, the choices taken in turn (the k-th choice group in file order takes its member k mod its size: the first
## group its first member, the second its second, ...; tools/trail_setup.py `even_pick` is the same rule), optional nodes
## (the Stakes, the Grubstake, Spirit) left out unless trail_optional=1. The named fractions are fractions of the
## Trail's levels, rounded half up (70 levels: a quarter 18, half 35, full 70). Outlaws, items and stages come with
## their nodes, so the pool is what a player at that level has; what no node gives keeps its own rule.
## The old names still read (`board_to_trail`): 0 none, 1.5 a quarter, 3 half, 6 or more full, any other number its
## share of the board's 6 ranks a talent.
## No autoload is named here (tools compile before they exist): the save comes in as a node. Load it by path:
##     const TRAIL_ARG := preload("res://tools/trail_arg.gd")
extends RefCounted

const NAMED := {"none": 0.0, "quarter": 0.25, "half": 0.5, "full": 1.0}
const WORDS := {"none": "none", "quarter": "a quarter", "half": "half", "full": "full"}
## The Upgrade board's ranks a talent that `board=` / `mirror=` counted as full.
const BOARD_FULL := 6.0


## The Trail Level `arg` names on a Trail of `levels` levels: a name's share of them (rounded half up), a number as it
## is (kept inside 0..levels); -1 for anything else.
static func level_of(arg: String, levels: int) -> int:
	var a := arg.strip_edges().to_lower()
	if a == "":
		return 0
	if NAMED.has(a):
		return int(floor(float(NAMED[a]) * float(levels) + 0.5))
	if a.is_valid_int():
		return clampi(int(a), 0, levels)
	return -1


## An old `board=` / `mirror=` value as a `trail=` one: a name passes through, ranks a talent become the nearest name
## (0, 1.5, 3, 6) or else a level (the share of BOARD_FULL of `levels`).
static func board_to_trail(v: String, levels: int) -> String:
	var a := v.strip_edges().to_lower()
	if NAMED.has(a) or a == "save":
		return a
	if not a.is_valid_float():
		return a
	var m := clampf(float(a), 0.0, BOARD_FULL)
	for name: String in NAMED.keys():
		if is_equal_approx(m / BOARD_FULL, float(NAMED[name])):
			return name
	return str(int(floor(m / BOARD_FULL * float(levels) + 0.5)))


## The node ids a player at Trail Level `level` holds (file order): every plain node of levels 1..level, one member
## of each choice group in turn, the optional nodes only with `optional`.
static func ids_upto(level: int, optional: bool = false) -> Array:
	var out: Array = []
	var taken := {}
	var k := 0
	for n: Dictionary in Trail.nodes():
		var id := str(n["id"])
		var kind := str(n["kind"])
		var lv := int(n["level"])
		if kind == "choice":
			var g: Array = Trail.group(id)
			var key := str(g[0]) if not g.is_empty() else id
			if not taken.has(key):
				taken[key] = str(g[k % g.size()]) if not g.is_empty() else id
				k += 1
			if lv <= level and str(taken[key]) == id:
				out.append(id)
		elif lv <= level and (kind == "node" or optional):
			out.append(id)
	return out


## Writes the Trail a `trail=` argument names into `save` (its `trail` block: the ids as bought, nothing spent, and
## nothing "had before the Trail": a tool's Trail is what its argument says, whatever save it started from) and returns {arg, asked (the level named), level (the Trail Level that came of
## it), bought (how many nodes), optional, label}; {error} for an argument that names nothing. `ids` (trail_ids=) wins
## over `arg`: exactly those nodes (the ones the Trail has).
static func apply(save: Node, arg: String, optional: bool = false, ids: Array = []) -> Dictionary:
	var levels := Trail.levels()
	var asked := -1
	var bought: Array = []
	if not ids.is_empty():
		for id: Variant in ids:
			if not Trail.node(str(id)).is_empty() and not bought.has(str(id)):
				bought.append(str(id))
	else:
		asked = level_of(arg, levels)
		if asked < 0:
			return {"error": "trail: '%s' is not none, quarter, half, full or a level (0 to %d)" % [arg, levels]}
		bought = ids_upto(asked, optional)
	var data: Dictionary = save.get("data")
	data["trail"] = {"bought": bought, "spent": 0, "had": []}
	Trail.refresh()
	var lv := Trail.level()
	return {"arg": arg.strip_edges().to_lower() if ids.is_empty() else "ids", "asked": asked, "level": lv,
		"bought": bought.size(), "optional": optional, "label": label_of(arg if ids.is_empty() else "ids", lv, levels)}


## The Trail in words for a tool's header: "a quarter (Trail Level 18 of 70)", "Trail Level 36 of 70", "none".
static func label_of(arg: String, level: int, levels: int) -> String:
	var a := arg.strip_edges().to_lower()
	if a == "none" or (a != "ids" and level <= 0):
		return "none"
	var where := "Trail Level %d of %d" % [level, levels]
	if WORDS.has(a):
		return "%s (%s)" % [str(WORDS[a]), where]
	return where
