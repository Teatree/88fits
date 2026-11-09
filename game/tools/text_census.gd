## The text census (pass 137, lane LOCKIT; Garry: "double check that the texts haven't changed after your changes"): every
## player-facing text the game can produce, written as one stable sorted JSON, so a change that moves texts into the string
## table (game/core/systems/Loc.gd, content/strings/en.json) can be proved to have changed none of them:
##   tools/text_census_diff.py <before.json> <after.json>     (exit 1 on any difference, a readable report)
##
## bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs log> --script res://tools/text_census.gd -- out=<abs json> [parts=a,b] [only=<touch_audit screens>] [samples=1]
##
## Parts:
##  a  the generated words (TextGen and its kin) for every content item: weapons and evolutions at every level, alone and
##     with each of their mutations (and all their path mutations at once), the next-level texts and the change rows,
##     passives and cards at every level and rung, perks, outlaws' traits at levels, quests, the Trail's nodes, levels and
##     bundles, the Wanted tasks' words, stat names and kinds, rarities, rule words. Exact text, numbers and all.
##  b  every screen state's visible words: the screens touch_audit.gd drives (this script extends it, so `only=` picks
##     screens the same way), every visible Label, Button, RichTextLabel, LineEdit placeholder and kit piece holding
##     `text` / `runs` (WText, WSeal, WPlate, ...), collected before the audit's taps. Numbers are written as # (a clock,
##     a gold count and a random offer move from run to run; the words are what a conversion could break), a screen's
##     texts as a sorted set. Run-random contents (the cards and chests offered) can differ between two runs: compare two
##     baselines once (tools/dl/p137/LOCKIT/census_*.json) before blaming a change.
##  c  the toasts, banners and run messages seen while part b plays (a watcher every few frames over the whole tree's
##     kit toasts and banners), normalised as in b; timing-dependent, so the diff reports c as a warning unless --strict.
## samples=1 turns Loc's capture mode on and writes tools/dl/loc/samples.json (the Strings tab's sample values).
##
## Texts drawn with draw_string from a script's own variables (a seal's number, a chart's axis) are reached only when the
## piece also holds them in a `text` property; loc_verify.py is the static proof for those.
extends "res://tools/touch_audit.gd"

var _out := ""
var _parts: Array = ["a", "b"]
var _samples := false
var _census_a: Dictionary = {}
var _census_b: Dictionary = {}   # screen -> {text: true}
var _census_c: Dictionary = {}   # text -> true
var _watch := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("parts="):
			_parts = Array(a.substr(6).split(","))
		elif a == "samples=1":
			_samples = true
	if _out == "":
		push_error("text_census: out=<abs json> is needed")
	super._initialize()


func _run() -> void:
	var loc: GDScript = load("res://core/systems/Loc.gd")
	if _samples:
		loc.set("capture", true)
	if _parts.has("a"):
		_part_a()
	if _parts.has("b") or _parts.has("c"):
		_watch = true
		_fix_seed()
		_watcher()
		await super._run()   # touch_audit's screens; its _report (overridden below) writes the census
	else:
		_report()


# ---------------------------------------------------------------- part a: the generated words

func _put(key: String, text) -> void:
	var s := str(text)
	if s == "":
		return
	_census_a[key] = s


func _rows_text(rows: Array) -> String:
	var parts: Array = []
	for r in rows:
		if r is Dictionary:
			var d: Dictionary = r
			if d.has("before"):
				parts.append("%s: %s -> %s" % [d.get("name", d.get("stat", "")), d.get("before", ""), d.get("after", "")])
			else:
				parts.append("%s: %s" % [d.get("name", d.get("stat", "")), d.get("value", "")])
		else:
			parts.append(str(r))
	return " | ".join(parts)


func _part_a() -> void:
	var reg = root.get_node("Registry")
	var tg: GDScript = load("res://core/systems/TextGen.gd")
	var wi: GDScript = load("res://core/systems/WeaponInstance.gd")
	var ss: GDScript = load("res://core/systems/StatSheet.gd")
	var consts: Dictionary = tg.get_script_constant_map()
	var stats: Dictionary = consts.get("STATS", {})
	var stat_ids := stats.keys()
	stat_ids.sort()
	for st in stat_ids:
		_put("stat|%s|name" % st, tg.call("stat_name", st))
		_put("stat|%s|kind" % st, tg.call("stat_kind", st))
		for v in [0.05, 1.0, 2.5]:
			_put("stat|%s|value|%s" % [st, v], tg.call("format_value", st, v))
		_put("stat|%s|rule" % st, tg.call("rule_words", st, 1.0))
		_put("stat|%s|hero_word" % st, tg.call("hero_word", st))
		_put("stat|%s|player_value" % st, tg.call("player_value", st, 1.0))
		_put("stat|%s|player_change" % st, tg.call("player_change", st, 1.0, 1.5))
		for op in ["add", "mul"]:
			_put("stat|%s|change|%s" % [st, op], tg.call("change_value", st, op, 0.1))
			_put("stat|%s|hero_amount|%s" % [st, op], tg.call("hero_amount", st, op, 0.1))
	for r in ["common", "uncommon", "rare", "epic", "legendary"]:
		_put("rarity|%s" % r, tg.call("rarity_name", r))
	for n in [1, 2, 3, 4, 11, 12, 13, 21, 22]:
		_put("ordinal|%d" % n, tg.call("ordinal", n))
	_put("time|75", tg.call("time_mmss", 75.0))
	_put("grouped|12345", tg.call("grouped", 12345))
	var player: StatSheet = ss.new()
	# weapons and evolutions at every level, alone and with their mutations
	var wids: Array = reg.weapons.keys()
	wids.sort()
	for id in wids:
		var def = reg.weapons[id]
		_put("weapon|%s|name" % id, def.display_name)
		_put("weapon|%s|nouns" % id, str(tg.call("weapon_nouns", def)))
		for lv in range(1, def.max_level + 1):
			var inst = wi.new(def, lv)
			inst.rebuild(player, [inst])
			_put("weapon|%s|L%d|desc" % [id, lv], inst.description())
			_put("weapon|%s|L%d|rows" % [id, lv], _rows_text(inst.stat_rows()))
			_put("weapon|%s|L%d|next" % [id, lv], tg.call("next_level_text", def, lv))
			_put("weapon|%s|L%d|noun" % [id, lv], tg.call("amount_noun", def, inst.sheet, inst.params))
			if lv < def.max_level:
				_put("weapon|%s|L%d|changes" % [id, lv], _rows_text(tg.call("weapon_changes", def, lv, lv + 1, null, player, [])))
		var fam: String = def.evolved_from if def.is_evolution and def.evolved_from != "" else id
		var muts: Array = []
		for m in reg.mutations_of(fam):
			muts.append(m)
		for m in reg.weapon_hero_mutations(fam):
			if not muts.has(m):
				muts.append(m)
		var path: Array = []
		for m in muts:
			var mi = wi.new(def, def.max_level)
			mi.mutations = [m]
			mi.rebuild(player, [mi])
			_put("weapon|%s|mut|%s|desc" % [id, m.id], mi.description())
			_put("weapon|%s|mut|%s|rows" % [id, m.id], _rows_text(mi.stat_rows()))
			if not m.get("hero") or str(m.get("hero")) == "":
				path.append(m)
		if path.size() > 1:
			var all = wi.new(def, def.max_level)
			all.mutations = path
			all.rebuild(player, [all])
			_put("weapon|%s|mut|ALL|desc" % id, all.description())
	# mutations' own words
	var mids: Array = reg.mutations.keys()
	mids.sort()
	for id in mids:
		var m = reg.mutations[id]
		_put("mutation|%s|name" % id, m.display_name)
		_put("mutation|%s|effects" % id, tg.call("describe_effects", m.effects) if m.get("effects") is Array else "")
	# passives, cards and the evolved ones at every level and rung
	var pids: Array = reg.passives.keys()
	pids.sort()
	for id in pids:
		var p = reg.passives[id]
		_put("passive|%s|name" % id, p.display_name)
		_put("passive|%s|text" % id, tg.call("passive_text", p))
		for lv in range(1, p.max_level + 1):
			_put("passive|%s|L%d|desc" % [id, lv], tg.call("passive_description", p, lv))
			_put("passive|%s|L%d|next" % [id, lv], tg.call("next_level_text", p, lv))
			_put("passive|%s|L%d|rung" % [id, lv], tg.call("rung_name", p, lv))
			if lv < p.max_level:
				_put("passive|%s|L%d|changes" % [id, lv], _rows_text(tg.call("passive_changes", p, lv, lv + 1)))
	# perks
	var kids: Array = reg.perks.keys()
	kids.sort()
	for id in kids:
		_put("perk|%s|text" % id, tg.call("perk_text", reg.perks[id]))
	# outlaws
	var cids: Array = reg.characters.keys()
	cids.sort()
	for id in cids:
		var c = reg.characters[id]
		_put("outlaw|%s|name" % id, c.display_name)
		_put("outlaw|%s|trait" % id, tg.call("hero_trait", c))
		_put("outlaw|%s|possessive" % id, tg.call("possessive", c))
		for lv in [1, 2, 5, 10, 20, 30]:
			_put("outlaw|%s|L%d|trait_at" % [id, lv], tg.call("hero_trait_at", c, lv))
			_put("outlaw|%s|L%d|trait_now" % [id, lv], tg.call("hero_trait_now", c, lv))
	# quests
	var qids: Array = reg.quests.keys()
	qids.sort()
	for id in qids:
		_put("quest|%s|text" % id, tg.call("quest_text", reg.quests[id]))
	# the Trail: every node's words, every level's bundle, the end
	var trail: GDScript = load("res://core/systems/Trail.gd")
	if bool(trail.call("has_nodes")):
		for n in trail.call("nodes"):
			var nd: Dictionary = n
			var nid := str(nd.get("id", ""))
			_put("trail|node|%s|gives" % nid, trail.call("give_text", nd))
		_put("trail|end", trail.call("end_text"))
		var ids: Array = []
		for l in range(1, int(trail.call("levels")) + 1):
			for n in trail.call("nodes_on", l):
				ids.append(str((n as Dictionary).get("id", "")))
			if l % 5 == 0 or l <= 3:
				_put("trail|bundle|L%d" % l, trail.call("bundle_of", ids))
	# the Wanted tasks' words (their templates live in content/wanted/wanted.json)
	var wb = FileAccess.get_file_as_string("res://content/wanted/wanted.json")
	var wd = JSON.parse_string(wb)
	if wd is Dictionary and wd.get("tasks") is Array:
		for t in wd["tasks"]:
			if t is Dictionary:
				_put("wanted|%s|name" % t.get("type", "?"), t.get("name", ""))
				_put("wanted|%s|text" % t.get("type", "?"), t.get("text", ""))
	print("text_census: part a, %d texts" % _census_a.size())


# ---------------------------------------------------------------- part b: the screens (touch_audit drives them)

static func _norm(s: String) -> String:
	var r := RegEx.create_from_string("[0-9]+")
	var out := r.sub(s, "#", true)
	var ws := RegEx.create_from_string("\\s+")
	return ws.sub(out, " ", true).strip_edges()


func _texts_of(c: Node) -> Array:
	var out: Array = []
	if c is Label:
		out.append((c as Label).text)
	elif c is RichTextLabel:
		out.append((c as RichTextLabel).get_parsed_text())
	elif c is Button:
		out.append((c as Button).text)
	elif c is LineEdit:
		out.append((c as LineEdit).placeholder_text)
	elif c.get_script() != null:
		var t = c.get("text")
		if t is String:
			out.append(t)
		var runs = c.get("runs")
		if runs is Array and not (runs as Array).is_empty():
			var joined := ""
			for r in runs:
				if r is Array and not (r as Array).is_empty():
					joined += str(r[0])
				elif r is String:
					joined += r
			out.append(joined)
	return out


func _collect(screen: String, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var bag: Dictionary = _census_b.get(screen, {})
	for c in node.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl == null or not ctl.is_visible_in_tree():
			continue
		for t in _texts_of(ctl):
			var s := _norm(str(t))
			if s != "" and s != "#":
				bag[s] = true
	_census_b[screen] = bag


func _audit(screen: String, node: Node) -> void:
	await _frames(2)
	_collect(screen, node)
	await super._audit(screen, node)


func _confirm_audit(screen: String, host: Node, ask: Callable) -> void:
	await super._confirm_audit(screen, host, ask)


## Part c: the kit's toasts and banners anywhere in the tree, every 6 frames while the screens play. Every frame it also
## hands the next run a fixed seed (Run.forced_run_seed, the launch's `run_seed` route), so the offers a run rolls (the
## cards, the chest, the Stranger's deal) are the same from one census to the next.
func _watcher() -> void:
	while _watch:
		for k in range(6):
			_fix_seed()
			await process_frame
		if not _watch:
			break
		for n in root.find_children("*", "Control", true, false):
			var sc: Script = (n as Node).get_script()
			if sc == null:
				continue
			var gname := str(sc.get_global_name())
			if gname in ["WToasts", "WBanner", "Hints", "WCelebrate"] or (n as Node).name.begins_with("Toast"):
				for c in (n as Node).find_children("*", "Control", true, false):
					if (c as Control).is_visible_in_tree():
						for t in _texts_of(c):
							var s := _norm(str(t))
							if s != "" and s != "#":
								_census_c[s] = true


const RUN_SEED := 1370


func _fix_seed() -> void:
	var run := root.get_node_or_null("Run")
	if run != null and int(run.get("forced_run_seed")) == 0:
		run.set("forced_run_seed", RUN_SEED)


func _report() -> void:
	_watch = false
	_write()
	if _parts.has("b") or _parts.has("c"):
		super._report()
	else:
		quit(0)


func _write() -> void:
	var out := {"version": 1, "parts": _parts, "a": {}, "b": {}, "c": []}
	var ka := _census_a.keys()
	ka.sort()
	for k in ka:
		out["a"][k] = _census_a[k]
	var kb := _census_b.keys()
	kb.sort()
	for k in kb:
		var texts: Array = (_census_b[k] as Dictionary).keys()
		texts.sort()
		out["b"][k] = texts
	var kc := _census_c.keys()
	kc.sort()
	out["c"] = kc
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", false) + "\n")
		f.close()
		print("text_census: wrote %s (a %d, b %d screens, c %d)" % [_out, ka.size(), kb.size(), kc.size()])
	if _samples:
		var loc: GDScript = load("res://core/systems/Loc.gd")
		loc.call("write_samples", loc.call("samples_path"))
