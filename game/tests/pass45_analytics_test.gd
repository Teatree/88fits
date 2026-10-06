## Pass 45, the analytics lane: the run recorder (core/systems/RunAnalytics.gd) samples once a second from the game's
## choke points, keeps its per-second accumulators sparse, writes a run file that parses back, and is nothing outside a
## run (RunAnalytics.I is null in the arena and in tests); the DPS estimate follows the behaviour that runs.
extends GdUnitTestSuite

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
var level_hp_mult := 1.0
var level_dmg_mult := 1.0
var time_scale := 1.0
var count_alive := 0
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


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	RunAnalytics.I = null


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A game with two goblins up (hp 10/12 dealing 3, hp 20/24 dealing 5), a director and a hero at 80 of 100.
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


func test_samples_once_a_second_from_the_hooks_and_writes_a_run_file() -> void:
	var g := _fake_game()
	var ra := RunAnalytics.new()
	ra.mirror = false
	g.add_child(ra)
	ra.begin(g)
	assert_object(RunAnalytics.I).is_same(ra)
	assert_int(int(ra.header["schema"])).is_equal(1)
	assert_str(str(ra.header["hero"])).is_equal("astro")
	ra.dealt("peashooter", 12.0)
	ra.took({"by": "Goblin", "id": "goblin", "kind": "melee"}, 10.0, 8.0, 0.0, "")
	ra.spawned(Registry.enemy("goblin"))
	ra.event("weapon", "peashooter", 2)
	ra.tick(0.5)
	assert_int(ra.samples.size()).is_equal(0)
	ra.tick(0.5)
	assert_int(ra.samples.size()).is_equal(1)
	var row: Dictionary = ra.samples[0]
	assert_float(float(row["t"])).is_equal(1.0)
	assert_float(float(row["dmg"]["peashooter"])).is_equal(12.0)
	assert_float(float(row["took"]["goblin"])).is_equal(8.0)
	assert_float(float(row["took_kind"]["melee"])).is_equal(8.0)
	assert_float(float(row["took_raw"])).is_equal(10.0)
	assert_int(int(row["hits"])).is_equal(1)
	assert_int(int(row["spawned"]["goblin"])).is_equal(1)
	assert_int(int(row["alive"])).is_equal(2)
	assert_int(int(row["cap"])).is_equal(20)
	assert_float(float(row["press"])).is_equal(12.0 * 3.0 + 24.0 * 5.0)
	assert_float(float(row["press_hp"])).is_equal(30.0)
	assert_float(float(row["press_dmg"])).is_equal(8.0)
	assert_int(int(row["alive_by"]["goblin"])).is_equal(2)
	assert_float(float(row["hp"])).is_equal(80.0)
	assert_float(float(row["hp_max"])).is_equal(100.0)
	# the first row carries the sheet and the creature multipliers
	assert_bool(row.has("stats")).is_true()
	assert_float(float(row["stats"]["max_hp"])).is_greater(0.0)
	assert_bool(row.has("mults")).is_true()
	# the item event: how it came and the estimate before it
	assert_int(ra.events.size()).is_equal(1)
	assert_str(str(ra.events[0]["kind"])).is_equal("weapon")
	assert_str(str(ra.events[0]["via"])).is_equal("card")
	assert_bool(ra.events[0].has("est_before")).is_true()
	# the next second starts from zero: a quiet row has no dmg/took/hits keys and no second snapshot
	ra.tick(1.0)
	var quiet: Dictionary = ra.samples[1]
	assert_bool(quiet.has("dmg")).is_false()
	assert_bool(quiet.has("took")).is_false()
	assert_bool(quiet.has("hits")).is_false()
	assert_bool(quiet.has("spawned")).is_false()
	assert_bool(quiet.has("stats")).is_false()
	assert_bool(quiet.has("mults")).is_false()
	assert_float(float(quiet["hp"])).is_equal(80.0)
	# a kill arrives through the manager's signal
	g.enemies.enemy_died.emit(Registry.enemy("goblin"), Vector3.ZERO, null, "peashooter")
	ra.tick(1.0)
	assert_int(int(ra.samples[2]["killed"]["goblin"])).is_equal(1)
	# a real build change: Run notes the item, and its build_changed fills est_after on that event
	ra.via = "chest"
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	assert_int(ra.events.size()).is_equal(2)
	assert_str(str(ra.events[1]["kind"])).is_equal("weapon")
	assert_str(str(ra.events[1]["id"])).is_equal("peashooter")
	assert_str(str(ra.events[1]["via"])).is_equal("chest")
	assert_bool(bool(ra.events[1]["new"])).is_true()
	assert_bool(ra.events[1].has("est_after")).is_true()
	assert_float(float(ra.events[1]["est_after"])).is_greater(0.0)
	# the file: under user://, parsing back with the header completed
	ra.header["stamp"] = "test-%d" % Time.get_ticks_usec()
	ra.finish()
	var path: String = "user://analytics/runs/%s.json" % ra.header["stamp"]
	assert_bool(FileAccess.file_exists(path)).is_true()
	var f := FileAccess.open(path, FileAccess.READ)
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	DirAccess.remove_absolute(path)
	assert_bool(doc is Dictionary).is_true()
	assert_int(int(doc["schema"])).is_equal(1)
	assert_str(str(doc["result"])).is_equal("end")
	assert_int((doc["samples"] as Array).size()).is_equal(3)
	assert_int((doc["events"] as Array).size()).is_equal(2)
	assert_bool((doc["names"] as Dictionary).has("peashooter")).is_true()
	assert_bool((doc["names"] as Dictionary).has("goblin")).is_true()
	assert_int((doc["build"]["weapons"] as Array).size()).is_equal(1)
	assert_bool(doc.has("hit_log")).is_true()
	# gone with the game: the handle is null again
	g.remove_child(ra)
	ra.free()
	assert_object(RunAnalytics.I).is_null()


func test_nothing_records_outside_a_run() -> void:
	RunAnalytics.I = null
	var before := float(Run.damage_by_weapon.get("peashooter", 0.0))
	Run.add_damage("peashooter", 5.0)
	assert_float(float(Run.damage_by_weapon["peashooter"])).is_equal(before + 5.0)
	Run._note("weapon", "peashooter", 1, {})
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	Run.level_weapon("peashooter")
	Run.add_or_level_passive("multishot")
	assert_object(RunAnalytics.I).is_null()
	# the hit info carries the creature id and the elite flag for the recorder; nothing else changed for the death log
	var em: EnemyManager = auto_free(EnemyManager.new())
	var info := em.hit_info(-1, "ranged")
	assert_str(str(info["by"])).is_equal("something")
	assert_str(str(info["kind"])).is_equal("ranged")
	assert_str(str(info["id"])).is_equal("")
	assert_bool(bool(info["elite"])).is_false()


func test_dps_estimate_follows_the_behaviour_that_runs() -> void:
	var w := WeaponInstance.new(Registry.weapon("orbit_saws"), 1)
	w.rebuild(Run.player_sheet, [])
	var hits := float(maxi(w.stat_int("amount", 1), 1))
	assert_float(w.dps_estimate()).is_equal_approx(w.stat("damage") * hits * 2.0, 0.01)
	# a mutation that swaps the behaviour is estimated as what fires
	var m := MutationDef.new()
	m.id = "test_swap"
	m.behavior = "ProjectileEmitter"
	w.mutations = [m]
	var cd: float = maxf(w.stat("cooldown", 1.0), 0.05)
	assert_float(w.dps_estimate()).is_equal_approx(w.stat("damage") * hits / cd, 0.01)
