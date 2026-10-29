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
## The saved gold moved (pass 61): `delta` signed, `reason` the source or sink (run_bank, strongbox, talent,
## talent_refund, wipe, ...), `balance` after it, `extra` what it was for (a talent's id and rank). Analytics sends it
## as gold_meta.
signal gold_moved(delta: int, reason: String, balance: int, extra: Dictionary)
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
			"pickups": 0, "gold_earned": 0,
			# pass 113 (lane TASKS, TaskTally): banked at each run's end: damage by weapon family, HP restored by item family
			# and by source ("pickup:heart"), fire / poison damage, barrels broken, Totem gifts taken
			"damage_with_weapon": {}, "heal_with_item": {}, "heal_with_source": {}, "element_damage": {}, "barrels": 0, "totems": 0},
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
		# pass 59: the name PostHog shows for this install ("Dusty Coyote 41", player_name()), the answer to the play-data
		# card ("" not asked yet, "yes", "no") and the end-of-run survey record (Analytics.survey_after_run). All four are
		# the player, not the progress: a wipe keeps them (KEEP_ON_WIPE)
		"player_name": "",
		"consent": "",
		"survey": {},
		# pass 69 (Garry: heroes to unlock and buy): the ids of the heroes bought with gold (owns_hero, buy_hero). A free
		# hero (availability "available") is owned without being listed; a save from before has none bought, so it keeps
		# only the free heroes, whoever it played (Garry asked for the locks)
		"heroes_owned": [],
		# pass 87 (lane SGAME): the stages beaten per map (a stage's boss killed), map id -> [bool, ...] by stage index
		# (stage_beaten, stage_unlocked); filled once from the old flags and kill totals (_migrate_stages)
		"stages_beaten": {},
		# pass 111 (lane SKINS): every currency but gold (gold keeps its own key "gold"): currency id -> balance
		# (currency_balance, add_currency, spend_currency; core/systems/Currency.gd)
		"wallets": {},
		# pass 111 (lane SKINS): the looks bought as skins ("<hero>:<CODE>", Registry.skin_key; owns_skin, buy_skin) and
		# the look each hero wears by the player's choice (hero id -> CODE; skin_worn, set_skin_worn). A save from before
		# has neither: every hero wears the look the game plays, the one every player owns
		"skins_owned": [],
		"skin_worn": {},
		# pass 111 (lane SKINS): what the Upgrade board cost in a currency other than gold (gold's total stays in
		# "talent_spent"): currency id -> spent; Take it all back pays half of each back
		"talent_spent_in": {},
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
	# pass 83 (lane META): a hero this save had freed by his quest, who is bought now, stays its own
	_keep_freed_heroes()
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
	# pass 69: a hero the save does not own (he is to be bought now) is not the one a run starts with
	if lc and Registry.hero_state(lc) != "owned" and Registry.characters.has(DEFAULT_HERO):
		data["last_character"] = DEFAULT_HERO
	if not Registry.maps.has(str(data.get("last_map", ""))):
		data["last_map"] = "red_canyon"
	if not (data.get("seen") is Dictionary):
		data["seen"] = {}
	_migrate_seen()
	# pass 87 (lane SGAME): the stages this save has beaten, once, from what it did before stages were their own runs
	_migrate_stages()
	# pass 88 (lane MIRROR): Spite's old Thorns / Thirst ranks paid back in full, once
	_migrate_stakes()
	_survey_counted_from_runs()
	Settings.from_dict(data.get("settings", {}))
	last_saved_unix = int(data.get("saved_at", 0))
	# pass 73 (lane CARDS): the cards in the look kept on this phone (the Registry scanned before the save was read)
	Registry.apply_card_looks()
	# pass 76 (lane LOOKS): and every weapon family in the look kept for it here (item_looks)
	Registry.apply_item_looks()


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


# ---------------------------------------------------------------- the cards' look (pass 73, lane CARDS)

## The look every fortune card (line item) is drawn in on this phone, kept from the arena's ITEMS tab ("" = each card's
## JSON `variant`): Garry compares the card framings in play. Registry.apply_card_looks puts it on.
func card_look() -> String:
	return str(data.get("card_look", ""))


## Keeps `code` as every card's look from now on ("" = each card's JSON look again), past the arena's sandbox as
## set_hero_look does, and puts it on at once.
func set_card_look(code: String) -> void:
	var targets: Array = [data]
	if _sandboxed:
		targets.append(_sandbox_backup)
	for d: Dictionary in targets:
		if code == "":
			d.erase("card_look")
		else:
			d["card_look"] = code
	if _sandboxed:
		_write(_sandbox_backup)
	else:
		request_save()
	Registry.apply_card_looks()


# ---------------------------------------------------------------- the weapon families' looks (pass 76, lane LOOKS)

## The look kept on this phone for each weapon family ({weapon id: look code}, data key "item_looks", set from the arena's
## ITEMS tab); a family missing here plays its weapon's JSON `variant` (Registry.played_item_look).
func item_looks() -> Dictionary:
	var looks = data.get("item_looks")
	return looks if looks is Dictionary else {}


## The look kept for weapon family `weapon_id` ("" = none kept).
func item_look(weapon_id: String) -> String:
	return str(item_looks().get(weapon_id, ""))


## Keeps `code` as the look family `weapon_id` plays from now on ("" = its JSON's again), past the arena's sandbox as
## set_card_look does (a look is a choice about the game, not something that happened in a run), and puts it on at once:
## the family's defs, and a held weapon's params and behaviour (Registry.apply_item_looks).
func set_item_look(weapon_id: String, code: String) -> void:
	var targets: Array = [data]
	if _sandboxed:
		targets.append(_sandbox_backup)
	for d: Dictionary in targets:
		if not (d.get("item_looks") is Dictionary):
			d["item_looks"] = {}
		var looks: Dictionary = d["item_looks"]
		if code == "":
			looks.erase(weapon_id)
		else:
			looks[weapon_id] = code
	if _sandboxed:
		_write(_sandbox_backup)
	else:
		request_save()
	Registry.apply_item_looks()


# ---------------------------------------------------------------- the install id (pass 57)

## The anonymous id the play data goes out under (pass 57, core/autoload/Analytics.gd, PostHog's distinct_id): a random
## UUID v4, made the first time it is asked for and kept in the save. No account, no advertising id, no device serial.
## Pass 59 (Garry: "they should keep the same id"): a wipe keeps it, so one tester stays one person in PostHog. Made inside the arena's sandbox (it is not: the arena
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


## The player's own keys a wipe keeps (pass 59): who they are to PostHog, their answer to the play-data card and their
## survey record. Everything else (gold, talents, quests, totals, what has been met, settings) goes.
const KEEP_ON_WIPE := ["install_id", "player_name", "consent", "survey"]

## The western words a player's name is made of (pass 59, Garry: "assign them some type of ID / name"): an adjective, a
## noun and a number, 32 x 32 x 90 = 92,160 names.
const NAME_ADJ := ["Dusty", "Rusty", "Lucky", "Salty", "Crooked", "Quiet", "Lonesome", "Sly", "Rowdy", "Gritty",
	"Sunburnt", "Wild", "Copper", "Brass", "Ragged", "Smoky", "Thirsty", "Restless", "Stubborn", "Lanky",
	"Grumpy", "Sleepy", "Jolly", "Silver", "Midnight", "Red", "Desert", "Prairie", "Canyon", "Hungry", "Lazy", "Swift"]
const NAME_NOUN := ["Coyote", "Rattler", "Buzzard", "Mustang", "Drifter", "Outlaw", "Prospector", "Tumbleweed",
	"Jackrabbit", "Gila", "Scorpion", "Bandit", "Wrangler", "Cactus", "Vulture", "Bronco", "Sheriff", "Deputy",
	"Gambler", "Stranger", "Rustler", "Cowpoke", "Roadrunner", "Armadillo", "Lizard", "Mule", "Hawk", "Bison",
	"Ranger", "Miner", "Tinker", "Nomad"]


## The name this install goes by in PostHog (pass 59), made from its install id, so the same id always reads the same
## name ("Dusty Coyote 41"); shown in Settings beside the version so a tester can read it out.
func player_name() -> String:
	var n := str(data.get("player_name", ""))
	if n != "":
		return n
	n = name_for(install_id())
	data["player_name"] = n
	if _sandboxed:
		_sandbox_backup["player_name"] = n
		_write(_sandbox_backup)
	else:
		request_save()
	return n


## The name an id reads as: an adjective, a noun and a number from the id's own hash.
static func name_for(id: String) -> String:
	var h := id.md5_buffer()
	return "%s %s %d" % [NAME_ADJ[h[0] % NAME_ADJ.size()], NAME_NOUN[h[1] % NAME_NOUN.size()], 10 + (h[2] % 90)]


## The answer to the play-data card (pass 59): "" not asked yet, "yes" or "no".
func consent() -> String:
	return str(data.get("consent", ""))


func set_consent(answer: String) -> void:
	data["consent"] = answer
	if _sandboxed:
		_sandbox_backup["consent"] = answer
		_write(_sandbox_backup)
	else:
		request_save()


## The end-of-run survey record (pass 59, Analytics.survey_after_run): {answered: [survey ids], runs_since: counted runs
## since the last card}. Pass 62 (Garry: "control over the count of runs at which the first Survey appears"): counted
## (the player's lifetime count of runs of a minute or more, what a survey's [after N] / [run N] tag counts), shown
## ({survey id: the counted run it was last shown after}), dismissed ([survey ids] closed with "Not now", for the
## developer menu) and armed (the developer menu's "Next run asks"). A wipe keeps all of it (KEEP_ON_WIPE).
func survey_state() -> Dictionary:
	var st = data.get("survey", {})
	if not (st is Dictionary):
		st = {}
	data["survey"] = st
	return st


## A save from before pass 62 has no counted runs: it starts from the runs it has finished (totals.runs, every run that
## ended, short ones too, since no older record tells them apart), so a long-time player is not asked a "5th run" survey
## at his fiftieth. A new save starts at 0. Runs at every load and does nothing once the count is there.
func _survey_counted_from_runs() -> void:
	var st := survey_state()
	if not st.has("counted"):
		st["counted"] = total("runs")

## A wipe takes the progress: the backup is removed too, so nothing comes back from it. The player's own keys stay
## (KEEP_ON_WIPE, pass 59).
func wipe() -> void:
	var had := gold()
	var keep := {}
	for k in KEEP_ON_WIPE:
		if data.has(k):
			keep[k] = data[k]
	data = _default()
	data.merge(keep, true)
	save_now()
	# pass 76 (lane LOOKS): the weapon looks kept here went with the progress: every family plays its JSON's look again
	Registry.apply_item_looks()
	# the saved gold went with it (pass 61: the balance chart drops to it)
	if had > gold():
		gold_moved.emit(gold() - had, "wipe", gold(), {})
	if FileAccess.file_exists(bak_path()):
		DirAccess.remove_absolute(bak_path())


# ---------------------------------------------------------------- gold

func gold() -> int:
	return int(data.get("gold", 0))


## Gold into the save; `source` says from where (pass 61: run_bank, strongbox, talent_refund, ...), `extra` rides along
## on the gold_meta event.
func add_gold(n: int, source: String = "other", extra: Dictionary = {}) -> void:
	var add := maxi(n, 0)
	data["gold"] = gold() + add
	gold_changed.emit(gold())
	if add > 0:
		gold_moved.emit(add, source, gold(), extra)
		currency_moved.emit("gold", add, source, gold(), extra)
	request_save()


## Gold out of the save; `sink` says for what (pass 61: talent, ...).
func spend_gold(n: int, sink: String = "other", extra: Dictionary = {}) -> bool:
	if gold() < n:
		return false
	data["gold"] = gold() - n
	gold_changed.emit(gold())
	if n > 0:
		gold_moved.emit(-n, sink, gold(), extra)
		currency_moved.emit("gold", -n, sink, gold(), extra)
	request_save()
	return true


# ---------------------------------------------------------------- every currency (pass 111, lane SKINS)

## A currency's balance moved (pass 111): every currency, gold too (add_gold and spend_gold send it beside gold_moved
## and gold_changed, which still come as before, so the analytics read what they always did). core/systems/Currency.gd
## is the API the screens call.
signal currency_moved(currency: String, delta: int, reason: String, balance: int, extra: Dictionary)


## The balance of currency `id`: gold under the old "gold" key, any other under "wallets"[id] (0 when it has none).
func currency_balance(id: String) -> int:
	if id == "gold" or id == "":
		return gold()
	var w = data.get("wallets")
	return int((w as Dictionary).get(id, 0)) if w is Dictionary else 0


func _wallets() -> Dictionary:
	if not (data.get("wallets") is Dictionary):
		data["wallets"] = {}
	return data["wallets"]


## `n` of currency `id` into the save, `source` from where (Currency.add): gold through add_gold.
func add_currency(id: String, n: int, source: String = "other", extra: Dictionary = {}) -> void:
	var add := maxi(n, 0)
	if id == "gold" or id == "":
		add_gold(add, source, extra)
		return
	_wallets()[id] = currency_balance(id) + add
	request_save()
	if add > 0:
		currency_moved.emit(id, add, source, currency_balance(id), extra)


## `n` of currency `id` out of the save for `sink` (Currency.spend): false, nothing spent, when the balance is short.
func spend_currency(id: String, n: int, sink: String = "other", extra: Dictionary = {}) -> bool:
	var cost := maxi(n, 0)
	if id == "gold" or id == "":
		return spend_gold(cost, sink, extra)
	if currency_balance(id) < cost:
		return false
	_wallets()[id] = currency_balance(id) - cost
	request_save()
	if cost > 0:
		currency_moved.emit(id, -cost, sink, currency_balance(id), extra)
	return true


# ---------------------------------------------------------------- looks sold as skins (pass 111, lane SKINS)

## The skins bought, as "<hero>:<CODE>" keys (Registry.skin_key). A look every player owns is never listed.
func skins_owned() -> Array:
	var s = data.get("skins_owned")
	if not (s is Array):
		s = []
		data["skins_owned"] = s
	return s


func owns_skin(key: String) -> bool:
	return skins_owned().has(key)


## The look hero `id` wears by the player's choice ("" = none: the look the game plays). Registry.worn_skin reads it
## only while the look is his (owned, not shelved).
func skin_worn(id: String) -> String:
	var w = data.get("skin_worn")
	return str((w as Dictionary).get(id, "")) if w is Dictionary else ""


## Wears look `code` on hero `id` from now on ("" = the look every player owns). The sheet's choice is the player's own,
## so it also lets go of a look the arena kept for him (Save.hero_look, a debug choice that would win over it).
func set_skin_worn(id: String, code: String) -> void:
	if not (data.get("skin_worn") is Dictionary):
		data["skin_worn"] = {}
	var w: Dictionary = data["skin_worn"]
	if code == "":
		w.erase(id)
	else:
		w[id] = code
	if hero_look(id) != "":
		set_hero_look(id, "")
	request_save()


## Buys look `code` of hero `c` (pass 111): only a look Registry.skin_state calls "buyable" (sold, its goal done, not
## owned) of a hero the player owns, for its price in its currency (Currency.of: an unknown one reads as gold), spent
## with the sink "skin" (the event carries the hero, the look and the price). True when it is owned after it.
func buy_skin(c: CharacterDef, code: String) -> bool:
	if c == null or Registry.hero_state(c) != "owned" or Registry.skin_state(c, code) != "buyable":
		return false
	var price := c.skin_price(code)
	var cur := Currency.of(c.skin_currency(code))
	if not spend_currency(cur, price, "skin", {"hero": c.id, "look": code, "price": price, "currency": cur}):
		return false
	var key := Registry.skin_key(c.id, code)
	if not owns_skin(key):
		skins_owned().append(key)
	request_save()
	return true


## The developer menu's "Looks · own every one" (and the tests'): every look sold marked bought, nothing spent. Returns
## how many.
func own_every_skin() -> int:
	var n := 0
	for c: CharacterDef in Registry.characters.values():
		for code in c.variants.keys():
			var key := Registry.skin_key(c.id, str(code))
			if c.sells_skin(str(code)) and not owns_skin(key):
				skins_owned().append(key)
				n += 1
	request_save()
	return n


## The developer menu's "Looks · forget the bought ones": every skin bought and worn forgotten (the gold stays spent).
func forget_skins() -> void:
	data["skins_owned"] = []
	data["skin_worn"] = {}
	request_save()


# ---------------------------------------------------------------- heroes to buy (pass 69)

## The heroes bought with gold, by id (a free hero is owned without being listed: Registry.hero_state).
func heroes_owned() -> Array:
	var h = data.get("heroes_owned")
	if not (h is Array):
		h = []
		data["heroes_owned"] = h
	return h


## Whether hero `id` has been bought (Registry.hero_state says whether he is owned: a free one always is).
func owns_hero(id: String) -> bool:
	return heroes_owned().has(id)


## Heroes who were free once their quest was done and are bought now (pass 83, lane META): hero id -> the quest that
## freed him. Ironwood was free after 2,500 kills until pass 83 made him one of the two heroes sold for gold alone (his
## quest retired): a save that had done it owns him (listed in heroes_owned, nothing spent). Idempotent, every load.
const FREED_BY_QUEST := {"ironwood": "unlock_ironwood"}


func _keep_freed_heroes() -> void:
	var done = data.get("quests_done")
	if not (done is Array):
		return
	for id: String in FREED_BY_QUEST.keys():
		if (done as Array).has(FREED_BY_QUEST[id]) and not owns_hero(id):
			heroes_owned().append(id)
			request_save(true)


## Buys hero `c` (pass 69, Garry: "After the requirements are met the heroes will become available to unlock by buying
## them with coins"): only a hero Registry.hero_state calls "buyable" (his quest done, not owned yet), for his `price` in
## `currency_type` (gold, the only purse there is), spent with the sink "hero" (the gold_meta event carries his id). True
## when he is owned after it; false when he cannot be bought (locked, already owned, hidden) or the purse is short.
func buy_hero(c: CharacterDef) -> bool:
	if c == null or Registry.hero_state(c) != "buyable":
		return false
	# pass 111 (lane SKINS): paid in his `currency_type` through Currency (an id the content lacks reads as gold)
	var cur := Currency.of(c.currency_type)
	var extra := {"hero": c.id, "price": maxi(c.price, 0)}
	if cur != "gold":
		extra["currency"] = cur
	if not spend_currency(cur, maxi(c.price, 0), "hero", extra):
		return false
	if not owns_hero(c.id):
		heroes_owned().append(c.id)
	request_save()
	return true


## The developer menu's "own every hero" (pass 69): every hero on sale marked bought, no gold spent, no quest needed.
## Returns how many were added.
func own_every_hero() -> int:
	var n := 0
	for c: CharacterDef in Registry.characters.values():
		if not c.hidden and c.availability == "purchase" and not owns_hero(c.id):
			heroes_owned().append(c.id)
			n += 1
	request_save()
	return n


## The developer menu's "forget the bought heroes" (pass 69): back to the free heroes only (the gold stays spent).
func forget_bought_heroes() -> void:
	data["heroes_owned"] = []
	request_save()


# ---------------------------------------------------------------- the Mirror

## The forms bought for a talent, rank by rank (pass 63, Garry: "each Upgrade is a choice ... that choice stays"): [0, 1, 0]
## = rank 1 the first form (Padding), rank 2 the second (Plate), rank 3 the first again. A rank's form never changes;
## Take it all back is the only way to choose again. A save from before reads {form, rank} as that form `rank` times.
func talent_picks(id: String) -> Array:
	var t = data.get("talents", {}).get(id, {})
	var out: Array = []
	if not (t is Dictionary):
		return out
	var p = (t as Dictionary).get("picks")
	if p is Array:
		for f in p:
			out.append(clampi(int(f), 0, 1))
		return out
	for k in range(int((t as Dictionary).get("rank", 0))):
		out.append(clampi(int((t as Dictionary).get("form", 0)), 0, 1))
	return out


## How many ranks a talent has, both forms together.
func talent_rank(id: String) -> int:
	return talent_picks(id).size()


## How many of a talent's ranks are of `form`.
func talent_count(id: String, form: int) -> int:
	var n := 0
	for f in talent_picks(id):
		if int(f) == form:
			n += 1
	return n


## The form of the last rank bought (0 with none): what the analytics and old callers read.
func talent_form(id: String) -> int:
	var p := talent_picks(id)
	return int(p[p.size() - 1]) if not p.is_empty() else 0


## Buy the talent's next rank in `form` with gold: the rank keeps that form for good.
func buy_talent(def: TalentDef, form: int = 0) -> bool:
	var picks := talent_picks(def.id)
	var rank := picks.size()
	if rank >= def.ranks:
		return false
	form = clampi(form, 0, 1)
	var cost := def.cost_of_rank(rank)
	# pass 111 (lane SKINS): in the talent's `currency_type` (gold), through Currency
	var cur := Currency.of(def.currency_type)
	var extra := {"talent": def.id, "rank": rank + 1, "form": form}
	if cur != "gold":
		extra["currency"] = cur
	if cost < 0 or not spend_currency(cur, cost, "talent", extra):
		return false
	picks.append(form)
	# pass 88 (lane MIRROR): a Stakes rank bought is never taken for an old Spite rank (a save wiped since its load)
	if def.id == "spite":
		mark_once(STAKES_ONCE)
	var all: Dictionary = data.get("talents", {})
	all[def.id] = {"picks": picks, "rank": picks.size(), "form": form}
	data["talents"] = all
	if cur == "gold":
		data["talent_spent"] = talent_spent() + cost
	else:
		if not (data.get("talent_spent_in") is Dictionary):
			data["talent_spent_in"] = {}
		data["talent_spent_in"][cur] = talent_spent_in(cur) + cost
	request_save()
	return true


## What the board cost in currency `cur` (pass 111): gold is talent_spent, any other its own total.
func talent_spent_in(cur: String) -> int:
	if cur == "gold" or cur == "":
		return talent_spent()
	var d = data.get("talent_spent_in")
	return int((d as Dictionary).get(cur, 0)) if d is Dictionary else 0


func talent_spent() -> int:
	return int(data.get("talent_spent", 0))


## Everything back, for half the gold (pass 44: the refund keeps REFUND_FRAC of what was spent): the board empties and
## half the coins return.
const REFUND_FRAC := 0.5


func talent_refund() -> int:
	return int(floor(talent_spent() * REFUND_FRAC))


func talent_refund_all() -> int:
	var back := talent_refund()
	# what went back (pass 61, on the gold_meta event): the ranks the board held and the gold they had cost
	var ranks := 0
	var all = data.get("talents", {})
	if all is Dictionary:
		for id in (all as Dictionary).keys():
			ranks += talent_rank(str(id))
	var info := {"ranks": ranks, "spent": talent_spent()}
	# pass 111 (lane SKINS): a rank paid in another currency comes back half in that currency
	var other = data.get("talent_spent_in")
	data["talents"] = {}
	data["talent_spent"] = 0
	data["talent_spent_in"] = {}
	add_gold(back, "talent_refund", info)
	if other is Dictionary:
		for cur in (other as Dictionary).keys():
			var half := int(floor(float(int(other[cur])) * REFUND_FRAC))
			if half > 0:
				add_currency(str(cur), half, "talent_refund", {"spent": int(other[cur])})
	request_save()
	return back


# ---------------------------------------------------------------- pass 88 (lane MIRROR): Spite's old forms

## What Spite's ranks cost before pass 88, rank by rank, when its forms were Thorns and Thirst: an old save's ranks come
## back at these prices (the talent is Stakes now: Difficulty and Boss, which make the game harder).
const SPITE_OLD_COST := [500, 900, 1500, 2250, 3250, 4500]
const STAKES_ONCE := "stakes_v88"


## Once per save (the once-flag STAKES_ONCE, set on every save, a new one too, so a Stakes rank bought later is never
## paid back): the ranks an older save bought in Spite (Thorns / Thirst) are erased and their whole price comes back
## (SPITE_OLD_COST, not the half of Take it all back: the player never chose to give them up), the board's spent total
## lowered by as much, and a note left for the Upgrade board's toast (board_note). Returns the gold paid back.
func _migrate_stakes() -> int:
	if once(STAKES_ONCE):
		return 0
	var all = data.get("talents", {})
	var back := 0
	var ranks := 0
	if all is Dictionary and (all as Dictionary).has("spite"):
		ranks = talent_rank("spite")
		for k in range(ranks):
			back += int(SPITE_OLD_COST[mini(k, SPITE_OLD_COST.size() - 1)])
		(all as Dictionary).erase("spite")
	if back > 0:
		data["talent_spent"] = maxi(talent_spent() - back, 0)
		add_gold(back, "talent_refund", {"talent": "spite", "ranks": ranks, "why": STAKES_ONCE})
		data["board_note"] = {"kind": "stakes_refund", "gold": back, "ranks": ranks}
	mark_once(STAKES_ONCE)
	return back


## The note the Upgrade board shows once as a toast ({kind, gold, ranks}; {} none).
func board_note() -> Dictionary:
	var n = data.get("board_note", {})
	return n if n is Dictionary else {}


func clear_board_note() -> void:
	if data.has("board_note"):
		data.erase("board_note")
		request_save()



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


## Pass 88 (lane STAGEMENU): a creature or boss met = the Collection's rule (pass 44): it has been on the sand in a
## run once (seen, EnemyManager.spawn marks it) or killed once. The Stages menu hides a boss not met yet.
func enemy_met(id: String) -> bool:
	return id != "" and (seen("enemy", id) or keyed_total("kills_of_enemy", id) > 0)


func best_run(map_id: String) -> Dictionary:
	return data["best_runs"].get(map_id, {})


# ---------------------------------------------------------------- stages unlocked (pass 87, lane SGAME)

## Garry (2026-10-17): "Now Player Unlocks Stages and is only able to enter them after having completed the previous
## one." A stage is beaten once its boss is killed in a run of it (WaveDirector marks it); stage 1 is always open, stage
## i once stage i - 1 is beaten; the Stages menu opens on every Play once stage 1 is beaten (stages_menu_open).

## The beaten flags of map `map_id`'s stages by index (a copy; shorter than the map's stages when the later ones are not).
func stages_beaten(map_id: String) -> Array:
	var all = data.get("stages_beaten", {})
	var v = all.get(map_id, []) if all is Dictionary else []
	return (v as Array).duplicate() if v is Array else []


## Whether stage `i` (0-based) of map `map_id` has been beaten (its boss killed in a run of it).
func stage_beaten(map_id: String, i: int) -> bool:
	var v := stages_beaten(map_id)
	return i >= 0 and i < v.size() and bool(v[i])


## Whether stage `i` (0-based) of map `map_id` may be played: stage 1 always, a later one once the one before is beaten.
func stage_unlocked(map_id: String, i: int) -> bool:
	return i <= 0 or stage_beaten(map_id, i - 1)


## Whether Play opens the Stages menu for map `map_id` (Garry: "opens on every Play" once stage 1 is beaten).
func stages_menu_open(map_id: String) -> bool:
	return stage_beaten(map_id, 0)


## Stage `i` (0-based) of map `map_id` beaten (WaveDirector, as its boss dies; tests, the developer menu).
func mark_stage_beaten(map_id: String, i: int) -> void:
	if map_id == "" or i < 0 or stage_beaten(map_id, i):
		return
	if not (data.get("stages_beaten") is Dictionary):
		data["stages_beaten"] = {}
	var v := stages_beaten(map_id)
	while v.size() <= i:
		v.append(false)
	v[i] = true
	data["stages_beaten"][map_id] = v
	request_save()


## Forgets every stage beaten on map `map_id` ("" = every map): the developer menu's reset, tests.
func forget_stages(map_id: String = "") -> void:
	if not (data.get("stages_beaten") is Dictionary) or map_id == "":
		data["stages_beaten"] = {}
	else:
		(data["stages_beaten"] as Dictionary).erase(map_id)
	request_save()


## A save from before pass 87 (once, "stages_migrated"): a stage counts as beaten when the save killed that stage's boss
## in a run before: its "boss_<map>_<k>" flag (marked as a stage's boss died since pass 30), or a kill of the stage's
## boss in the totals (kills_of_enemy: the King for stage 1, the Gila for stage 2, the Brander for stage 3 on Red Canyon).
## The bosses are read off each map's stages (WaveTimeline.stage_boss). Never takes a stage away.
func _migrate_stages() -> void:
	if once("stages_migrated"):
		return
	if not (data.get("stages_beaten") is Dictionary):
		data["stages_beaten"] = {}
	var kills = data["totals"].get("kills_of_enemy", {})
	for map_id in Registry.maps.keys():
		var m: MapDef = Registry.maps[map_id]
		if m == null or m.timeline == null:
			continue
		for k in range(m.timeline.stage_count()):
			var boss: String = m.timeline.stage_boss(k)
			var killed: bool = boss != "" and kills is Dictionary and int((kills as Dictionary).get(boss, 0)) > 0
			if once("boss_%s_%d" % [str(map_id), k + 1]) or killed:
				mark_stage_beaten(str(map_id), k)
	mark_once("stages_migrated")


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
