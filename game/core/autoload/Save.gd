## One JSON save file: gold, talents, quests, totals, best runs, settings, hint flags, what has been met, and (pass 57)
## the anonymous install id the play data goes out under.
## Pass 45: the write is atomic (save.json.tmp, the old file to save.json.bak, the tmp into place), a file that cannot
## be read falls back to the backup and is kept aside, versions migrate forward only, writes are debounced and flushed
## when the app goes to the background or quits, and the debug arena runs in a sandbox that never reaches the disk.
extends Node

const VERSION := 5
const DEBOUNCE_MS := 400   # a change made in a menu is on disk within half a second
const LAZY_MS := 8000      # in-run tallies (kills, pickups, coins) wait up to 8 s; the background flush catches them

signal gold_changed(gold: int)
signal quest_completed(quest_id: String)
signal saved(ok: bool)

## The hero a clean save opens on (pass 53: the Drifter, unlocked from the start; Astro before). A save whose hero is gone
## from the content falls back to him too.
const DEFAULT_HERO := "drifter"

var data: Dictionary = {}
## where the file lives (the tests point it at user://test_saves so they never touch a real save)
var dir := "user://"
var _dirty := false
var _due_ms := 0
var _sandboxed := false
var _sandbox_backup: Dictionary = {}
## the last write (unix time, or 0), its error ("" = fine) and what the boot read: save, backup, tmp or new
var last_saved_unix := 0
var last_error := ""
var loaded_from := "new"


func path() -> String:
	return dir.path_join("save.json")


func bak_path() -> String:
	return path() + ".bak"


func tmp_path() -> String:
	return path() + ".tmp"


func _ready() -> void:
	# the debounce must tick behind the pause menu, the cards and the reel (the tree is paused there)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# the gdUnit runner (-s GdUnitCmdTool.gd) gets its own folder: the suites wipe and refill the save as they test
	if Array(OS.get_cmdline_args()).any(func(a) -> bool: return str(a).ends_with("GdUnitCmdTool.gd")):
		dir = "user://test_saves"
	load_save()


func _process(_delta: float) -> void:
	if _dirty and Time.get_ticks_msec() >= _due_ms:
		save_now()


## The phone taking the app off the screen, the window closing, the tree quitting: whatever is pending goes to disk now.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush()


func _default() -> Dictionary:
	return {
		"version": VERSION,
		"saved_at": 0,
		"gold": 0,
		"talents": {}, "talent_spent": 0,
		"quests_done": [],
		"totals": {"kills": 0, "kills_with_weapon": {}, "kills_of_enemy": {}, "chests": 0, "evolutions": 0, "runs": 0, "extracts": 0,
			"pickups": 0, "gold_earned": 0},
		"once": [],
		"best_runs": {},
		# what the player has met in a run, by kind (pass 44): the Collection shows only these
		"seen": {},
		"settings": {},
		"hints_seen": [],
		# the Drifter on a clean save (pass 53, Garry: "By Default Drifter hero is selected (on a clean save I mean)"; Astro
		# from 2026-09-14 to pass 52). An existing save keeps the hero it last played.
		"last_character": DEFAULT_HERO,
		"last_map": "red_canyon",
		"runs_started": 0,
		"materials": {"bones": 0, "relics": 0},
		# the look each hero is drawn with, kept from the arena's HERO tab (pass 55): hero id -> art variant code; a hero
		# missing here wears his JSON's `variant`
		"hero_look": {},
		# the anonymous id the play data goes out under (pass 57, install_id()): made the first time it is asked for
		"install_id": "",
	}


## The file, or the backup, or the half-finished tmp: the first that reads as a whole JSON object is the save. One that
## does not is kept aside under a new name (never deleted, never overwritten), and a recovery goes back in place at the
## next write.
func load_save() -> void:
	data = _default()
	loaded_from = "new"
	last_error = ""
	for c in [[path(), "save"], [bak_path(), "backup"], [tmp_path(), "tmp"]]:
		var p: String = c[0]
		if not FileAccess.file_exists(p):
			continue
		var parsed = _read_json(p)
		if parsed is Dictionary and not parsed.is_empty():
			_merge_file(parsed)
			loaded_from = str(c[1])
			break
		var aside := "%s.corrupt-%d" % [p, int(Time.get_unix_time_from_system())]
		var n := 0
		while FileAccess.file_exists(aside):
			n += 1
			aside = "%s.corrupt-%d-%d" % [p, int(Time.get_unix_time_from_system()), n]
		DirAccess.rename_absolute(p, aside)
		last_error = "could not read %s (kept as %s)" % [p.get_file(), aside.get_file()]
		push_warning("Save: " + last_error)
	if loaded_from == "backup" or loaded_from == "tmp":
		# the recovered data goes back in place as save.json right away
		_dirty = true
		_due_ms = 0
	_migrate()
	# content can disappear between versions (heroes come and go): never point at a missing id
	if not Registry.characters.has(str(data.get("last_character", ""))):
		data["last_character"] = DEFAULT_HERO if Registry.characters.has(DEFAULT_HERO) else (Registry.sorted_characters()[0].id if not Registry.characters.is_empty() else DEFAULT_HERO)
	# Pass 53: the hero_astro once-flag (2026-09-14: every save switched to Astro once) is gone. It fired on every clean
	# save too, so a new player always opened on Astro whatever the default said; every existing save already carries the
	# flag in "once", so nothing moves for them, and a save without it keeps the hero it last played.
	# a hero that has been hidden since (pass 33.4) is not played any more
	var lc: CharacterDef = Registry.playable_character(str(data.get("last_character", DEFAULT_HERO)))
	if lc:
		data["last_character"] = lc.id
	if not Registry.maps.has(str(data.get("last_map", ""))):
		data["last_map"] = "red_canyon"
	if not (data.get("seen") is Dictionary):
		data["seen"] = {}
	_migrate_seen()
	Settings.from_dict(data.get("settings", {}))
	last_saved_unix = int(data.get("saved_at", 0))


func _read_json(p: String) -> Variant:
	var j := JSON.new()
	var err := j.parse(FileAccess.get_file_as_string(p))
	if err != OK:
		push_warning("Save: %s line %d: %s" % [p.get_file(), j.get_error_line(), j.get_error_message()])
		return null
	return j.data


## The file's keys over the defaults, by type: a key the file has with the right type wins, a key this build does not
## know is kept for the build that wrote it, a wrong-typed value falls back to the default (and is said so). "totals"
## merges one level down so a total this build added starts at its default.
func _merge_file(parsed: Dictionary) -> void:
	for k in parsed.keys():
		var v = parsed[k]
		if data.has(k) and not _same_kind(data[k], v):
			push_warning("Save: '%s' is a %s in the file, the default is kept" % [k, type_string(typeof(v))])
			continue
		if k == "totals" and v is Dictionary:
			for tk in v.keys():
				if data["totals"].has(tk) and not _same_kind(data["totals"][tk], v[tk]):
					push_warning("Save: total '%s' is a %s in the file, the default is kept" % [tk, type_string(typeof(v[tk]))])
					continue
				data["totals"][tk] = v[tk]
		else:
			data[k] = v


## JSON reads every number back as a float, so an int and a float are one kind.
func _same_kind(a, b) -> bool:
	var num := func(x) -> bool: return typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT
	return typeof(a) == typeof(b) or (num.call(a) and num.call(b))


## Forward only: a file older than VERSION is stepped up one version at a time; a newer file is loaded as it is and keeps
## its number (never reset, never downgraded).
func _migrate() -> void:
	var v := int(data.get("version", 1))
	if v > VERSION:
		push_warning("Save: version %d is newer than this build's %d; loaded as it is" % [v, VERSION])
		return
	var stepped := false
	while v < VERSION:
		match v:
			1:
				pass   # 1 -> 2: the atomic era; the once/seen fixes in load_save are idempotent and run for every version
			2:
				_migrate_2_to_3()
			3:
				_migrate_3_to_4()
			4:
				_migrate_4_to_5()
		v += 1
		data["version"] = v
		stepped = true
	if stepped:
		request_save()


## 2 -> 3 (pass 46): the lines became passives, so what was met as a line was met as a passive (merged, never twice),
## and Cheese became Cake (cheese -> cake, cheese_bite -> cake_slice) wherever "seen" lists it. Runs before load_save
## puts "seen" right, so it takes the record as the file has it and leaves anything it does not know alone.
const RENAMED_3 := {"cheese": "cake", "cheese_bite": "cake_slice"}


func _migrate_2_to_3() -> void:
	var s = data.get("seen")
	if not (s is Dictionary):
		return
	var seen_d: Dictionary = s
	if seen_d.get("line") is Array:
		if not (seen_d.get("passive") is Array):
			seen_d["passive"] = []
		for id in seen_d["line"]:
			if not (seen_d["passive"] as Array).has(id):
				(seen_d["passive"] as Array).append(id)
	seen_d.erase("line")
	for kind in seen_d.keys():
		if not (seen_d[kind] is Array):
			continue
		var out: Array = []
		for id in seen_d[kind]:
			var nid = RENAMED_3.get(str(id), id) if (id is String or id is StringName) else id
			if not out.has(nid):
				out.append(nid)
		seen_d[kind] = out


## 3 -> 4 (pass 47): the floating damage numbers on, once. Garry never saw them: a benchmark tool had saved them off on
## the PC, and a phone's save may hold them off too. Runs before load_save hands the settings to Settings; from here on
## the player's own switch sticks.
func _migrate_3_to_4() -> void:
	if not (data.get("settings") is Dictionary):
		data["settings"] = {}
	(data["settings"] as Dictionary)["damage_numbers"] = true


## 4 -> 5 (pass 53): the live main menu, once. Garry: "By default set the Main Menu to be the new one - the one with the
## live heroes". Every save written under pass 52 holds "painted" (to_dict wrote the default), so the new default alone
## would not reach a phone; from here on the developer menu's switch sticks. Runs before load_save hands the settings on.
func _migrate_4_to_5() -> void:
	if not (data.get("settings") is Dictionary):
		data["settings"] = {}
	(data["settings"] as Dictionary)["menu_style"] = Settings.MENU_STYLE_DEFAULT


## A save from before pass 44 has no "seen" record: what its totals prove was met counts as seen (the creatures it
## killed, the weapons it killed with), so the Collection does not go blank on an old save.
func _migrate_seen() -> void:
	if once("seen_migrated"):
		return
	for id in data["totals"].get("kills_of_enemy", {}).keys():
		if int(data["totals"]["kills_of_enemy"][id]) > 0:
			mark_seen("enemy", str(id))
	for id in data["totals"].get("kills_with_weapon", {}).keys():
		if int(data["totals"]["kills_with_weapon"][id]) > 0:
			mark_seen("weapon", str(id))
	mark_once("seen_migrated")


## Writes the whole file now. Returns false (and sets last_error) when the disk refused.
func save_now() -> bool:
	_dirty = false
	if _sandboxed:
		return true
	return _write(data)


## The write itself (pass 55: out of save_now, so the arena can write the copy end_sandbox will put back): `d` with the
## settings, the clock and the version on it, through the tmp file and the backup.
func _write(d: Dictionary) -> bool:
	d["settings"] = Settings.to_dict()
	d["saved_at"] = int(Time.get_unix_time_from_system())
	d["version"] = maxi(int(d.get("version", VERSION)), VERSION)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(tmp_path(), FileAccess.WRITE)
	if f == null:
		return _fail("open: " + error_string(FileAccess.get_open_error()))
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	# the new file is whole on disk: the old one steps back to .bak, the new one steps into its place (a rename replaces
	# an existing file on Windows and on Android alike; at every moment one complete file exists)
	if FileAccess.file_exists(path()):
		var e1 := DirAccess.rename_absolute(path(), bak_path())
		if e1 != OK:
			return _fail("backup: " + error_string(e1))
	var e2 := DirAccess.rename_absolute(tmp_path(), path())
	if e2 != OK:
		return _fail("rename: " + error_string(e2))
	last_saved_unix = int(d["saved_at"])
	last_error = ""
	saved.emit(true)
	return true


func _fail(why: String) -> bool:
	last_error = why
	_dirty = true   # try again on the next flush
	push_error("Save: " + why)
	saved.emit(false)
	return false


## Asks for a write soon: within DEBOUNCE_MS, or LAZY_MS for an in-run tally; an earlier request keeps its earlier time.
func request_save(lazy: bool = false) -> void:
	var due := Time.get_ticks_msec() + (LAZY_MS if lazy else DEBOUNCE_MS)
	_due_ms = mini(_due_ms, due) if _dirty else due
	_dirty = true


func flush() -> void:
	if _dirty:
		save_now()


## The debug arena: whatever happens to the data from here on stays in memory; end_sandbox puts the copy back and
## writes it once. An app killed in the arena boots into the file as it was before the arena.
func begin_sandbox() -> void:
	if _sandboxed:
		return
	flush()
	_sandbox_backup = data.duplicate(true)
	_sandboxed = true


func end_sandbox() -> void:
	if not _sandboxed:
		return
	data = _sandbox_backup
	_sandbox_backup = {}
	_sandboxed = false
	save_now()


func sandboxed() -> bool:
	return _sandboxed


# ---------------------------------------------------------------- the heroes' looks (pass 55)

## The art variant code the player kept for hero `id` ("" = none kept: he wears his JSON's `variant`). A code the hero
## no longer has is left to CharacterDef.variant_def, which falls back to the JSON's look.
func hero_look(id: String) -> String:
	var looks = data.get("hero_look")
	return str((looks as Dictionary).get(id, "")) if looks is Dictionary else ""


## Keeps `code` as the look hero `id` wears from now on, in runs, on the title and in the arena ("" = his JSON's look
## again). Garry: "I'd also like the option to choose which art should be used from that point onwards in this debug
## menu". The arena keeps it from inside its sandbox: a look is a choice about the game, not something that happened in
## a run, so it goes into the copy end_sandbox puts back as well, and that copy is written now, so the choice holds even
## when the app is closed before the arena is left.
func set_hero_look(id: String, code: String) -> void:
	var targets: Array = [data]
	if _sandboxed:
		targets.append(_sandbox_backup)
	for d: Dictionary in targets:
		if not (d.get("hero_look") is Dictionary):
			d["hero_look"] = {}
		var looks: Dictionary = d["hero_look"]
		if code == "":
			looks.erase(id)
		else:
			looks[id] = code
	if _sandboxed:
		_write(_sandbox_backup)
	else:
		request_save()


# ---------------------------------------------------------------- the install id (pass 57)

## The anonymous id the play data goes out under (pass 57, core/autoload/Analytics.gd, PostHog's distinct_id): a random
## UUID v4, made the first time it is asked for and kept in the save. No account, no advertising id, no device serial:
## a wipe makes a new one, and with it a new anonymous player. Made inside the arena's sandbox (it is not: the arena
## sends nothing), it goes into the copy end_sandbox puts back too, so it is never made twice.
func install_id() -> String:
	var id := str(data.get("install_id", ""))
	if id != "":
		return id
	id = new_uuid4()
	data["install_id"] = id
	if _sandboxed:
		_sandbox_backup["install_id"] = id
		_write(_sandbox_backup)
	else:
		request_save()
	return id


## Whether this save has an install id yet (the first app_open after an install or a wipe is the one without).
func has_install_id() -> bool:
	return str(data.get("install_id", "")) != ""


## A random UUID v4 (RFC 4122: version 4, variant 10) from the crypto generator.
static func new_uuid4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


## A wipe is a wipe: the backup is removed too, so nothing comes back from it.
func wipe() -> void:
	data = _default()
	save_now()
	if FileAccess.file_exists(bak_path()):
		DirAccess.remove_absolute(bak_path())


# ---------------------------------------------------------------- gold

func gold() -> int:
	return int(data.get("gold", 0))


func add_gold(n: int) -> void:
	data["gold"] = gold() + max(n, 0)
	gold_changed.emit(gold())
	request_save()


func spend_gold(n: int) -> bool:
	if gold() < n:
		return false
	data["gold"] = gold() - n
	gold_changed.emit(gold())
	request_save()
	return true


# ---------------------------------------------------------------- the Mirror

## What form of a talent is picked (0 or 1) and how many ranks of it are owned.
func talent_form(id: String) -> int:
	var t = data.get("talents", {}).get(id, {})
	return int(t.get("form", 0)) if t is Dictionary else 0


func talent_rank(id: String) -> int:
	var t = data.get("talents", {}).get(id, {})
	return int(t.get("rank", 0)) if t is Dictionary else 0


## Switching form is free and keeps the ranks: the Mirror is a choice, not a purchase you regret.
func set_talent_form(id: String, form: int) -> void:
	var all: Dictionary = data.get("talents", {})
	var t: Dictionary = all.get(id, {"form": 0, "rank": 0})
	t["form"] = clampi(form, 0, 1)
	all[id] = t
	data["talents"] = all
	request_save()


## Buy the next rank of a talent with gold.
func buy_talent(def: TalentDef) -> bool:
	var rank := talent_rank(def.id)
	if rank >= def.ranks:
		return false
	var cost := def.cost_of_rank(rank)
	if cost < 0 or not spend_gold(cost):
		return false
	var all: Dictionary = data.get("talents", {})
	var t: Dictionary = all.get(def.id, {"form": 0, "rank": 0})
	t["rank"] = rank + 1
	all[def.id] = t
	data["talents"] = all
	data["talent_spent"] = talent_spent() + cost
	request_save()
	return true


func talent_spent() -> int:
	return int(data.get("talent_spent", 0))


## Everything back, for half the gold (pass 44: the refund keeps REFUND_FRAC of what was spent): the board empties and
## half the coins return.
const REFUND_FRAC := 0.5


func talent_refund() -> int:
	return int(floor(talent_spent() * REFUND_FRAC))


func talent_refund_all() -> int:
	var back := talent_refund()
	data["talents"] = {}
	data["talent_spent"] = 0
	add_gold(back)
	request_save()
	return back



# ---------------------------------------------------------------- the homestead

func quest_done(id: String) -> bool:
	return data["quests_done"].has(id)


func mark_quest(id: String) -> void:
	if not quest_done(id):
		data["quests_done"].append(id)
		quest_completed.emit(id)
		request_save()


func total(key: String) -> int:
	return int(data["totals"].get(key, 0))


## The tallies come many a second in a run: they ask for the lazy write (LAZY_MS), which the background flush catches.
func add_total(key: String, n: int = 1) -> void:
	data["totals"][key] = total(key) + n
	request_save(true)


func add_keyed_total(key: String, sub: String, n: int = 1) -> void:
	if not (data["totals"].get(key) is Dictionary):
		data["totals"][key] = {}
	data["totals"][key][sub] = int(data["totals"][key].get(sub, 0)) + n
	request_save(true)


func keyed_total(key: String, sub: String) -> int:
	var d = data["totals"].get(key, {})
	return int(d.get(sub, 0)) if d is Dictionary else 0


func once(key: String) -> bool:
	return data["once"].has(key)


func mark_once(key: String) -> void:
	if not once(key):
		data["once"].append(key)
		request_save(true)


# ---------------------------------------------------------------- runs and hints

func record_run(map_id: String, time: float, level: int, stage: int, kills: int = 0) -> void:
	var best: Dictionary = data["best_runs"].get(map_id, {"time": 0.0, "level": 0, "stage": 0, "kills": 0})
	best["time"] = max(float(best.get("time", 0.0)), time)
	best["level"] = max(int(best.get("level", 0)), level)
	best["stage"] = max(int(best.get("stage", 0)), stage)
	best["kills"] = max(int(best.get("kills", 0)), kills)
	data["best_runs"][map_id] = best
	add_total("runs", 1)
	request_save()


# ---------------------------------------------------------------- what has been met (pass 44)

## Whether an item or creature of `kind` ("weapon", "passive", "perk", "enemy") has been met in a run. A line (pass 47)
## is met as a passive (version 3 folded "line" into "passive"), so "line" reads and writes the passive list.
func seen(kind: String, id: String) -> bool:
	kind = SEEN_KIND.get(kind, kind)
	var s = data.get("seen", {}).get(kind, [])
	return s is Array and s.has(id)


## The met-it list a kind is kept under (pass 47: a line is a passive there).
const SEEN_KIND := {"line": "passive"}


func mark_seen(kind: String, id: String) -> void:
	kind = SEEN_KIND.get(kind, kind)
	if id == "" or seen(kind, id):
		return
	if not (data.get("seen") is Dictionary):
		data["seen"] = {}
	if not (data["seen"].get(kind) is Array):
		data["seen"][kind] = []
	data["seen"][kind].append(id)
	request_save()


func best_run(map_id: String) -> Dictionary:
	return data["best_runs"].get(map_id, {})


func hint_seen(id: String) -> bool:
	return data["hints_seen"].has(id)


func mark_hint(id: String) -> void:
	if not hint_seen(id):
		data["hints_seen"].append(id)
		request_save()


func reset_hints() -> void:
	data["hints_seen"] = []
	request_save()


func first_run_done() -> bool:
	return int(data.get("runs_started", 0)) > 0


func note_run_started() -> void:
	data["runs_started"] = int(data.get("runs_started", 0)) + 1
	request_save()
