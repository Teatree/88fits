## Pass 74, lane ANALYTICS (Garry: "Update it so it contains all the info that might need adding or updating ... Make it
## so that I can actually download the data as a .csv file"): the run record's schema 2 (core/systems/RunAnalytics.gd):
## the header's new blocks, the rows' healing by source, regen, hits by creature and specials up, the new events (the
## boss's HP pegging, the coloured specials, the Elite modifiers, the Stranger, the Totem Poles), a tool's run in
## analytics/runs/tools/, the newest 50 files kept under user://, the index row the history CSV reads, and the two
## kinds that reach PostHog. The CSVs themselves are tools/analytics_csv.py's and the dashboard's (checked from the lane
## with Python and Node, not here).
extends GdUnitTestSuite

const TOTEM_BOONS := preload("res://core/systems/TotemBoons.gd")

const FAKE_GAME := """extends Node
var enemies = null
var director = null
var player = null
"""

const FAKE_ENEMIES := """extends Node
signal enemy_died(def, pos, elite, weapon_id)
signal boss_died(def, pos)
var alive := PackedByteArray()
var state := PackedInt32Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var dmg := PackedFloat32Array()
var type_idx := PackedInt32Array()
var types: Array = []
var boss_index := -1
var stage_mult := 1.0
var hp_time_mult := 1.0
var damage_time_mult := 1.25
var level_hp_mult := 1.0
var level_dmg_mult := 1.0
var time_scale := 1.0
var count_alive := 0
var specials_alive := 2
var special_chests := 0
var sniper_aims := 3
var sniper_hero_hits := 1
func alive_count() -> int:
	return count_alive
func cap_load() -> float:
	return float(count_alive)
"""

const FAKE_DIRECTOR := """extends Node
signal boss_started(def)
signal stage_started(stage)
var phase := 0
var timeline = null
var last_boss_scale: Dictionary = {}
func current_cap() -> int:
	return 20
"""

const FAKE_PLAYER := """extends Node
var hp := 80.0
var max_hp := 100.0
var shield_pts := 0.0
var invuln := 0.0
var damage_log: Array = []
"""

var _stamps: Array = []
var _dirs: Array = []


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	RunAnalytics.I = null
	_stamps = []
	_dirs = []


func after_test() -> void:
	RunAnalytics.I = null
	for s in _stamps:
		DirAccess.remove_absolute("user://analytics/runs/%s.json" % s)
	for d in _dirs:
		_rm_tree(str(d))


func _rm_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A game with two goblins up, a director, a hero at 80 of 100 (pass45_analytics_test's, with the pass 74 fields).
func _fake_game() -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var em := Node.new()
	em.set_script(_script(FAKE_ENEMIES))
	g.add_child(em)
	var alive := PackedByteArray()
	alive.resize(8)
	alive[0] = 1
	alive[1] = 1
	em.alive = alive
	var state := PackedInt32Array()
	state.resize(8)
	em.state = state
	em.hp = PackedFloat32Array([10.0, 20.0, 0, 0, 0, 0, 0, 0])
	em.max_hp = PackedFloat32Array([12.0, 24.0, 0, 0, 0, 0, 0, 0])
	em.dmg = PackedFloat32Array([3.0, 5.0, 0, 0, 0, 0, 0, 0])
	em.type_idx = PackedInt32Array([0, 0, -1, -1, -1, -1, -1, -1])
	em.types = [{"def": Registry.enemy("goblin")}]
	em.count_alive = 2
	g.enemies = em
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	g.director = d
	var p := Node.new()
	p.set_script(_script(FAKE_PLAYER))
	g.add_child(p)
	g.player = p
	return g


func _recorder(g: Node) -> RunAnalytics:
	var ra := RunAnalytics.new()
	ra.mirror = false
	g.add_child(ra)
	ra.begin(g)
	var stamp := "test-p74-%d" % Time.get_ticks_usec()
	ra.header["stamp"] = stamp
	_stamps.append(stamp)
	return ra


func _events_of(ra: RunAnalytics, kind: String) -> Array:
	return ra.events.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == kind)


func test_the_header_carries_the_run_its_settings_and_the_map_as_played() -> void:
	var g := _fake_game()
	var ra := _recorder(g)
	ra.set_launch({"weapon": "revolver", "level": 3, "spawn": true, "skip_me": {"a": 1}})
	var h: Dictionary = ra.header
	# pass 101 (lane FPS): schema 3 (the rows' frame times, pass101_fps_test); pass 102 (lane STEADY): schema 4 (the
	# rows' work times, pass102_steady_test), re-pinned on purpose
	assert_int(int(h["schema"])).is_equal(4)
	assert_int(RunAnalytics.SCHEMA).is_equal(4)
	# the test runner is a tool's process (headless, started with -s)
	assert_bool(bool(h["tool"])).is_true()
	assert_bool(RunAnalytics.is_tool_process()).is_true()
	assert_str(str(h["hero_look"])).is_equal(Analytics.hero_look_of(Registry.character("astro")))
	assert_bool(h["talents"] is Dictionary).is_true()
	assert_bool(h["talent_forms"] is Dictionary).is_true()
	assert_dict(h["settings"]).contains_keys(["pierce_falloff", "debug_mode", "dev"])
	assert_bool(bool(h["settings"]["pierce_falloff"])).is_equal(bool(Settings.pierce_falloff))
	# the launch file's plain values only
	assert_dict(h["launch"]).is_equal({"weapon": "revolver", "level": 3, "spawn": true})
	# the map's numbers as played: Red Canyon's own where it names them, the game's defaults where it leaves a key out
	var ms: Dictionary = h["map_settings"]
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(float(ms["hero_knockback_mult"])).is_equal(tl.hero_knockback_mult)
	assert_float(float(ms["special_defaults"]["hp"])).is_equal(EnemyDef.special_value({}, tl.special_defaults, "hp"))
	assert_int(int(ms["special_defaults"]["max_alive"])).is_equal(EnemyDef.special_max_alive(tl.special_defaults))
	assert_float(float(ms["boss_hp_scaling"]["ref_dps"]["tumbleweed_king"])).is_equal(tl.boss_ref_dps("tumbleweed_king"))
	assert_float(float(ms["boss_hp_scaling"]["window"])).is_equal(tl.boss_dps_window())
	assert_dict(ms["target_priority"]).contains_keys(["enabled", "reach"])
	assert_float(float(ms["spawn_rise"]["seconds"])).is_equal(tl.spawn_rise_value("seconds"))
	assert_float(float(ms["creature_hp_mult"])).is_equal(tl.creature_hp_mult)
	# an empty block plays the defaults
	var bare := RunAnalytics.map_settings(WaveTimeline.new())
	assert_float(float(bare["special_defaults"]["hp"])).is_equal(float(EnemyDef.SPECIAL_DEFAULTS["hp"]))
	assert_int(int(bare["special_defaults"]["max_alive"])).is_equal(EnemyDef.SPECIAL_MAX_ALIVE)
	assert_float(float(bare["boss_hp_scaling"]["exponent"])).is_equal(float(WaveTimeline.BOSS_HP_SCALING_DEFAULTS["exponent"]))
	assert_float(float(bare["boss_hp_scaling"]["ref_dps"]["brander"])).is_equal(float(WaveTimeline.BOSS_REF_DPS_DEFAULTS["brander"]))
	assert_float(float(bare["spawn_rise"]["targetable"])).is_equal(float(WaveTimeline.SPAWN_RISE_DEFAULTS["targetable"]))
	assert_dict(RunAnalytics.map_settings(null)).is_empty()
	# the end: a line and a passive item apart, a totem's gift, the trait, the gold block, the story, the quests
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("beer")
	var pool: Array = TOTEM_BOONS.offer(Registry.structure("totem_pole"))
	assert_bool(pool.is_empty()).is_false()
	Run.take_totem_boon(pool[0])
	ra.tick(1.0)
	ra.finish()
	var b: Dictionary = ra.header["build"]
	assert_bool((b["lines"] as Dictionary).has("brawn")).is_true()
	assert_bool((b["passives"] as Dictionary).has("brawn")).is_false()
	assert_bool((b["passives"] as Dictionary).has("beer")).is_true()
	# the passive event of a line says so
	var lines := _events_of(ra, "passive").filter(func(e: Dictionary) -> bool: return str(e.get("id", "")) == "brawn")
	assert_bool(bool(lines[0].get("line", false))).is_true()
	var beer := _events_of(ra, "passive").filter(func(e: Dictionary) -> bool: return str(e.get("id", "")) == "beer")
	assert_bool(beer[0].has("line")).is_false()
	# the row's snapshot keeps them apart too
	assert_bool((ra.samples[0]["lines"] as Dictionary).has("brawn")).is_true()
	assert_bool((ra.samples[0]["passives"] as Dictionary).has("brawn")).is_false()
	var totems: Array = ra.header["totems"]
	assert_int(totems.size()).is_equal(1)
	assert_str(str(totems[0]["id"])).is_equal(str(pool[0]["id"]))
	assert_str(str(totems[0]["words"])).is_not_empty()
	var trt: Dictionary = ra.header["trait"]
	assert_str(str(trt["name"])).is_equal(Registry.character("astro").trait_name)
	assert_int(int(trt["level"])).is_equal(Run.level)
	assert_dict(ra.header["gold_end"]).contains_keys(["gold_earned", "gold_spent", "gold_banked", "gold_lost", "gold_before", "gold_after"])
	assert_dict(ra.header["timeline"]).contains_keys(["start_weapon", "markers", "stages", "sources"])
	assert_bool(ra.header["quests"] is Dictionary).is_true()
	for qid in ra.header["quests"]:
		assert_dict(ra.header["quests"][qid]).contains_keys(["name", "before", "after", "need", "done"])
	# the crowd's counters above zero only
	assert_dict(ra.header["crowd"]).is_equal({"sniper_aims": 3, "sniper_hero_hits": 1})
	# headless: no frame rate
	assert_bool(ra.header.has("fps")).is_false()
	# the totem gift is named for the dashboard
	assert_str(str(ra.header["names"].get("brawn", ""))).is_equal(Registry.passive("brawn").display_name)


func test_rows_carry_healing_by_source_regen_hits_by_creature_and_specials_up() -> void:
	var g := _fake_game()
	var ra := _recorder(g)
	ra.healed(5.0, "Heart")
	# lifesteal's heal comes unnamed; Run's signal (heard after Game heals) names it
	ra.healed(3.0)
	Run.lifesteal_healed.emit(3.0)
	# the level-up patch the same way (Run.level_up reaches the recorder's _on_level)
	assert_bool(Run.level_up.is_connected(ra._on_level)).is_true()
	ra.healed(4.0)
	ra._on_level(2)
	# a heal nothing names stays "other"
	ra.healed(1.0)
	ra.regen(1.5)
	ra.took({"by": "Goblin", "id": "goblin", "kind": "melee"}, 10.0, 8.0, 0.0, "")
	ra.took({"by": "Goblin", "id": "goblin", "kind": "melee"}, 10.0, 0.0, 0.0, "evaded")
	ra.took({"by": "the ring of fire", "kind": "ranged"}, 4.0, 4.0, 0.0, "")
	ra.tick(1.0)
	var row: Dictionary = ra.samples[0]
	assert_float(float(row["healed"])).is_equal(13.0)
	assert_float(float(row["healed_by"]["Heart"])).is_equal(5.0)
	assert_float(float(row["healed_by"]["lifesteal"])).is_equal(3.0)
	assert_float(float(row["healed_by"]["level_up"])).is_equal(4.0)
	assert_float(float(row["healed_by"]["other"])).is_equal(1.0)
	assert_float(float(row["regen"])).is_equal(1.5)
	assert_int(int(row["hits_by"]["goblin"])).is_equal(2)
	assert_int(int(row["hits_by"]["the ring of fire"])).is_equal(1)
	assert_int(int(row["hits"])).is_equal(3)
	assert_int(int(row["specials_alive"])).is_equal(2)
	assert_float(float(row["mults"]["dmg_t"])).is_equal(1.25)
	# the level event still lands
	assert_int(_events_of(ra, "level").size()).is_equal(1)
	# the next second starts from nothing
	g.enemies.specials_alive = 0
	ra.tick(1.0)
	var quiet: Dictionary = ra.samples[1]
	for k in ["healed_by", "regen", "hits_by", "specials_alive"]:
		assert_bool(quiet.has(k)).override_failure_message(k).is_false()
	# an unnamed heal left over from an earlier second is never named later
	ra.healed(2.0)
	ra.tick(1.0)
	Run.lifesteal_healed.emit(2.0)
	ra.tick(1.0)
	assert_float(float(ra.samples[2]["healed_by"]["other"])).is_equal(2.0)
	assert_bool(ra.samples[3].has("healed_by")).is_false()
	# finished here, so the recorder's own exit writes no "quit" file after after_test has cleaned up
	ra.finish()


func test_events_record_the_bosses_pegging_specials_elites_the_stranger_and_the_totems() -> void:
	var g := _fake_game()
	var ra := _recorder(g)
	var goblin: EnemyDef = Registry.enemy("goblin")
	# a boss: its HP as it came and the director's pegging
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	g.enemies.boss_index = 1
	g.director.last_boss_scale = {"id": "tumbleweed_king", "dps": 1210.04, "ref": 600.0, "mult": 1.4201, "window": 45.0, "stage": 0}
	g.director.boss_started.emit(king)
	var bs: Dictionary = _events_of(ra, "boss_start")[0]
	assert_str(str(bs["id"])).is_equal("tumbleweed_king")
	assert_float(float(bs["dps"])).is_equal(1210.0)
	assert_float(float(bs["ref"])).is_equal(600.0)
	assert_float(float(bs["mult"])).is_equal(1.42)
	assert_float(float(bs["window"])).is_equal(45.0)
	assert_float(float(bs["hp"])).is_equal(24.0)
	# scaling off (no pegging read for this boss): the id and the HP only
	g.director.last_boss_scale = {}
	g.director.boss_started.emit(king)
	assert_bool(_events_of(ra, "boss_start")[1].has("mult")).is_false()
	# a coloured special came (forced by a Special swarm), fell twice: the chest only when the crowd's count moved
	ra.spawned_marked(goblin, null, true, true)
	var sp: Dictionary = _events_of(ra, "special")[0]
	assert_str(str(sp["id"])).is_equal("goblin")
	assert_bool(bool(sp["forced"])).is_true()
	ra.special_killed(goblin, 1, "revolver")
	ra.special_killed(goblin, 1, "revolver")
	var sk := _events_of(ra, "special_kill")
	assert_bool(bool(sk[0]["chest"])).is_true()
	assert_bool(bool(sk[1]["chest"])).is_false()
	assert_str(str(sk[0]["weapon"])).is_equal("revolver")
	# a creature wearing an Elite modifier: came and fell with its modifier; an Elite by its kind falls without one
	var mod: EliteModDef = Registry.elites_list()[0]
	ra.spawned_marked(goblin, mod, false, false)
	assert_str(str(_events_of(ra, "elite_mod")[0]["mod"])).is_equal(mod.id)
	assert_int(_events_of(ra, "special").size()).is_equal(1)
	g.enemies.enemy_died.emit(goblin, Vector3.ZERO, mod, "peashooter")
	var ek: Dictionary = _events_of(ra, "elite_kill")[0]
	assert_str(str(ek["id"])).is_equal("goblin")
	assert_str(str(ek["mod"])).is_equal(mod.id)
	assert_str(str(ek["weapon"])).is_equal("peashooter")
	var big: EnemyDef = null
	for e: EnemyDef in Registry.enemies.values():
		if e.archetype == "elite":
			big = e
			break
	if big != null:
		g.enemies.enemy_died.emit(big, Vector3.ZERO, null, "")
		assert_bool(_events_of(ra, "elite_kill")[1].has("mod")).is_false()
	# a plain kill is no Elite's
	var n_elite := _events_of(ra, "elite_kill").size()
	g.enemies.enemy_died.emit(goblin, Vector3.ZERO, null, "peashooter")
	assert_int(_events_of(ra, "elite_kill").size()).is_equal(n_elite)
	# the Stranger: a deal taken (his max HP read again once the sheet is rebuilt) and one turned down
	ra.stranger({"type": "weapon", "id": "peashooter", "level_to": 2}, 0.15, 100.0, true)
	g.player.max_hp = 85.0
	await await_idle_frame()
	var st: Dictionary = _events_of(ra, "stranger")[0]
	assert_str(str(st["id"])).is_equal("peashooter")
	assert_str(str(st["type"])).is_equal("weapon")
	assert_int(int(st["level"])).is_equal(2)
	assert_float(float(st["cost"])).is_equal(0.15)
	assert_float(float(st["hp_max_before"])).is_equal(100.0)
	assert_float(float(st["hp_max_after"])).is_equal(85.0)
	ra.stranger({"type": "passive", "id": "beer", "level_to": 2}, 0.2, 85.0, false)
	var sd: Dictionary = _events_of(ra, "stranger_decline")[0]
	assert_str(str(sd["id"])).is_equal("beer")
	assert_bool(sd.has("hp_max_before")).is_false()
	# a Totem Pole's menu: what it offered and the one taken
	var offer: Array = TOTEM_BOONS.offer(Registry.structure("totem_pole"))
	assert_int(offer.size()).is_greater(1)
	ra.totem_offer(offer, offer[1])
	var to: Dictionary = _events_of(ra, "totem_offer")[0]
	assert_str(str(to["id"])).is_equal(str(offer[1]["id"]))
	assert_int((to["offered"] as Array).size()).is_equal(offer.size())
	assert_int((to["words"] as Array).size()).is_equal(offer.size())
	assert_int((to["quality"] as Array).size()).is_equal(offer.size())
	ra.totem_offer(offer, {})
	assert_str(str(_events_of(ra, "totem_offer")[1].get("id", ""))).is_equal("")
	# the names: the modifier and the gifts
	ra.finish()
	var names: Dictionary = ra.header["names"]
	assert_str(str(names.get(mod.id, ""))).is_equal(mod.display_name)
	assert_str(str(names.get(str(offer[0]["id"]), ""))).is_equal(TOTEM_BOONS.title(offer[0]))


func test_a_tools_run_mirrors_into_its_own_folder_and_the_index_row_flattens_the_header() -> void:
	var root := "user://p74_an_mirror_%d" % Time.get_ticks_usec()
	_dirs.append(root)
	DirAccess.make_dir_recursive_absolute(root)
	for tool_run in [true, false]:
		var g := _fake_game()
		var ra := _recorder(g)
		ra.mirror = true
		ra.mirror_root = root
		ra.header["tool"] = tool_run
		# through Run, so the run's totals (the index row's damage) hear it as the rows do
		Run.damage_by_weapon.clear()
		Run.add_damage("peashooter", 12.0)
		ra.took({"by": "Goblin", "id": "goblin", "kind": "melee"}, 10.0, 8.0, 0.0, "")
		ra.tick(1.0)
		ra.finish()
		var dir := root.path_join("runs/tools") if tool_run else root.path_join("runs")
		var fname := str(ra.header["stamp"]) + ".json"
		assert_bool(FileAccess.file_exists(dir.path_join(fname))).override_failure_message(dir).is_true()
		assert_bool(FileAccess.file_exists(dir.path_join("latest.js"))).is_true()
		assert_bool(FileAccess.file_exists(dir.path_join("index.js"))).is_true()
		var lj := FileAccess.get_file_as_string(dir.path_join("latest.js"))
		assert_bool(lj.begins_with("window.RUN = ")).is_true()
		var idx = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("index.json")))
		assert_bool(idx is Array).is_true()
		var row: Dictionary = (idx as Array).back()
		assert_str(str(row["file"])).is_equal(fname)
		assert_int(int(row["schema"])).is_equal(4)   # pass 101 (lane FPS): schema 3; pass 102 (lane STEADY): 4, re-pinned on purpose
		assert_bool(bool(row["tool"])).is_equal(tool_run)
		for k in ["hero_look", "gold_end.gold_banked", "settings.dev", "map_settings.hero_knockback_mult",
				"map_settings.boss_hp_scaling.ref_dps.tumbleweed_king", "trait.name", "talents", "totems", "damage",
				"top_source", "dps_end", "build", "hp_lost", "hits_taken", "bosses", "specials_killed", "elites_killed", "killer"]:
			assert_bool(row.has(k)).override_failure_message("index row lacks " + k).is_true()
		assert_float(float(row["damage"])).is_equal(12.0)
		assert_float(float(row["hp_lost"])).is_equal(8.0)
		assert_int(int(row["hits_taken"])).is_equal(1)
		# the big blocks stay in the run file
		for k in ["names", "samples", "events", "hit_log", "timeline", "quests"]:
			assert_bool(row.has(k)).override_failure_message("index row has " + k).is_false()
	# the played run's folder holds no tool run, and the tool's folder no played one
	var played_idx = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("runs/index.json")))
	assert_int((played_idx as Array).size()).is_equal(1)
	var tool_idx = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("runs/tools/index.json")))
	assert_int((tool_idx as Array).size()).is_equal(1)


func test_flatten_into_names_every_value_by_its_path() -> void:
	var row := {}
	RunAnalytics.flatten_into(row, "a", {"b": 1, "c": {"d": "x", "e": [1, 2, 3]}, "f": [{"g": 1}, {"g": 2}], "h": {}})
	assert_dict(row).is_equal({"a.b": 1, "a.c.d": "x", "a.c.e": "1; 2; 3", "a.f": 2})


func test_user_runs_keep_the_newest_files_only() -> void:
	var dir := "user://p74_an_prune_%d" % Time.get_ticks_usec()
	_dirs.append(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	for k in range(RunAnalytics.KEEP_FILES + 5):
		var f := FileAccess.open(dir.path_join("2026-01-01T00-%02d-00.json" % k), FileAccess.WRITE)
		f.store_string("{}")
		f.close()
	var other := FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE)
	other.store_string("kept")
	other.close()
	assert_int(RunAnalytics.prune(dir)).is_equal(5)
	var left := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".json"))
	assert_int(left.size()).is_equal(RunAnalytics.KEEP_FILES)
	# the oldest went, the newest stayed, and nothing that is not a run file was touched
	assert_bool(FileAccess.file_exists(dir.path_join("2026-01-01T00-00-00.json"))).is_false()
	assert_bool(FileAccess.file_exists(dir.path_join("2026-01-01T00-04-00.json"))).is_false()
	assert_bool(FileAccess.file_exists(dir.path_join("2026-01-01T00-05-00.json"))).is_true()
	assert_bool(FileAccess.file_exists(dir.path_join("2026-01-01T00-54-00.json"))).is_true()
	assert_bool(FileAccess.file_exists(dir.path_join("notes.txt"))).is_true()
	assert_int(RunAnalytics.prune(dir)).is_equal(0)
	assert_int(RunAnalytics.KEEP_FILES).is_equal(50)
	# the lead's rule: a phone prunes, the PC never (the editor binary, the PC exe, tools, tests)
	assert_bool(RunAnalytics.prunes_here()).is_equal(OS.has_feature("mobile"))
	assert_bool(RunAnalytics.prunes_here()).is_false()
	var src := FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")
	assert_bool(src.contains("if index and RunAnalytics.prunes_here():")).is_true()
	assert_int(src.count("RunAnalytics.prune(\"user://analytics/runs\"")).is_equal(1)


func test_totems_and_special_kills_reach_posthog_the_rest_stays_local() -> void:
	assert_str(str(Analytics.KIND_EVENTS.get("totem", ""))).is_equal("totem_taken")
	assert_str(str(Analytics.KIND_EVENTS.get("special_kill", ""))).is_equal("special_killed")
	var m: Array = Analytics.map_event({"t": 3.0, "clock": 3.0, "kind": "special_kill", "id": "goblin", "chest": true, "weapon": "revolver"})
	assert_str(str(m[0])).is_equal("special_killed")
	assert_bool(bool(m[1]["chest"])).is_true()
	m = Analytics.map_event({"t": 3.0, "clock": 3.0, "kind": "totem", "id": "wolf", "level": 1, "stat": "move_speed", "value": 0.05})
	assert_str(str(m[0])).is_equal("totem_taken")
	for k in ["special", "elite_mod", "elite_kill", "stranger", "stranger_decline", "totem_offer"]:
		assert_bool(Analytics.KIND_EVENTS.has(k)).override_failure_message(k).is_false()
		assert_array(Analytics.map_event({"kind": k})).is_empty()


func test_the_hooks_are_in_the_game() -> void:
	# the one-line hooks the record hangs on (a later edit that drops one leaves its data quietly empty)
	var player := FileAccess.get_file_as_string("res://player/Player.gd")
	assert_bool(player.contains("RunAnalytics.I.healed(got, source)")).is_true()
	assert_bool(player.contains("RunAnalytics.I.regen(hp - before)")).is_true()
	var em := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	assert_bool(em.contains("RunAnalytics.I.spawned_marked(def, elite, vspecial[i] == 1, force_special)")).is_true()
	assert_bool(em.contains("RunAnalytics.I.special_killed(def, special_chests, weapon_id)")).is_true()
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game.contains("RunAnalytics.I.stranger(offer, cost, player.max_hp, bool(took))")).is_true()
	assert_bool(game.contains("RunAnalytics.I.totem_offer(offer, boon)")).is_true()
	assert_bool(game.contains("RunAnalytics.create(self, debug_launch)")).is_true()
	# the recorder hears lifesteal and the level-ups after Game (Game connects first, then makes the recorder)
	var ls := game.find("Run.lifesteal_healed.connect(")
	var lu := game.find("Run.level_up.connect(")
	var mk := game.find("RunAnalytics.create(self")
	assert_bool(ls > 0 and lu > 0 and ls < mk and lu < mk).is_true()
