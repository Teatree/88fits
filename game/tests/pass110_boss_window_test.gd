extends GdUnitTestSuite

## Pass 110, lane BOSS (Garry: "I'd like some control over which enemies spawn during the Boss fight. Just add a 2 minute
## window in the Timeline where I can set up the cycle of enemies that will be spawning ... as long as the Boss Fight is
## continuing it will be those enemies at that pace that will be spawning"): a stage entry's `boss_fight` block
## {enabled, length, max_count, roster} (WaveTimeline.boss_fight), played by BossFightWindow from the boss's arrival until
## it dies. Only its rows spawn in the fight (the stage's rows, the own-interval rows, the floor and the specials' clock
## stand still), its cycle loops every `length` seconds, max_count (bodies) holds for every row that respects the cap,
## the boss's summons stop at the hard cap, and a map without the block (or with it switched off) fights as before.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var director = null
var fx = null
var hud = null
var paused := false
var toasts: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const FAKE_PICKUPS := """extends Node
var chests: Array = []
var endless_coin_chance := 1.0
func spawn_chest(at: Vector3, boss: bool = false) -> void:
	chests.append({"at": at, "boss": boss})
"""

const FLAT_MAP := """extends MapBase
"""

## the test stage's end (its boss's second)
const END := 100.0

var _save_keep: Dictionary = {}
var _map_keep: MapDef = null
var _added: Array = []


func before_test() -> void:
	_save_keep = Save.data.duplicate(true)
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 1000
	_map_keep = Run.map


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.map = _map_keep
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.endless = false
	Run.endless_time = 0.0
	Run.stage_beaten = false
	Save.data = _save_keep


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var mp := Node3D.new()
	mp.set_script(_script(FLAT_MAP))
	g.add_child(mp)
	g.map = mp
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pk": pk}


## A test creature `id` made from `from`, no variance (no coloured specials), with `fields` set; gone after the test.
func _test_def(id: String, from: String, fields: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	d.max_alive = 0
	for k: String in fields.keys():
		d.set(k, fields[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


## A one-stage timeline (its boss the King at END) with `roster` and the stage's `boss_fight` block (none when {}), over
## quiet defaults: a flat cap of 100, the boss fight at half of it, bursts of 5, no boss HP scaling, colour from the start.
func _tl(roster: Array, boss_fight: Dictionary, extra: Dictionary = {}) -> WaveTimeline:
	var entry := {"id": "s1", "name": "One", "length": END, "boss": "tumbleweed_king"}
	if not boss_fight.is_empty():
		entry["boss_fight"] = boss_fight
	var base := {"stage_length": END, "stages": 1, "stage_list": [entry], "cap_start": 100, "cap_per_minute": 0,
		"cap_max": 300, "hard_cap": 300, "spawn_interval": 0.5, "burst_min": 5, "burst_max": 5, "roster": roster,
		"events": [], "waves": [], "colour_after_kills": 0, "boss_cap_frac": 0.5, "boss_hp_scaling": {"enabled": false}}
	for k in extra.keys():
		base[k] = extra[k]
	return JsonContent.timeline_from_dict(base)


## A director on `tl` (a copy of Red Canyon's map carrying it), started on its stage and run up to the boss's arrival:
## the clock at the stage's end, the crowd cleared, the boss up.
func _fight(w: Dictionary, tl: WaveTimeline) -> WaveDirector:
	var m: MapDef = _map_keep.duplicate()
	m.timeline = tl
	Run.map = m
	Run.start_stage(0)
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	w["g"].director = d
	w["g"].add_child(d)
	d.start(m)
	Run.elapsed = END
	(w["em"] as EnemyManager).kill_all(false)
	d._start_boss("tumbleweed_king")
	return d


## `secs` of the director's frames in `step` second slices (its fight clock, its spawn checks).
func _play(d: WaveDirector, secs: float, step: float = 0.1) -> void:
	var n := int(round(secs / step))
	for _k in range(n):
		d._process(step)


# ---------------------------------------------------------------- the keys

func test_the_window_keys_read_with_their_defaults() -> void:
	var tl := _tl([], {"length": 90, "max_count": 25, "roster": [{"t": 0, "enemy": "skeleton"}, 7, {"t": 10, "until": 40, "enemy": "imp"}]})
	assert_bool(tl.has_boss_fight(0)).is_true()
	assert_float(tl.boss_fight_length(0)).is_equal(90.0)
	assert_int(tl.boss_fight_max_count(0)).is_equal(25)
	# only the dictionaries are rows
	assert_int(tl.boss_fight_rows(0).size()).is_equal(2)
	# the defaults: a 2-minute cycle, 40 bodies; -1 = no limit but the hard cap; never below -1; at least 1 s
	var d := _tl([], {"roster": []})
	assert_bool(d.has_boss_fight(0)).is_true()
	assert_float(d.boss_fight_length(0)).is_equal(WaveTimeline.BOSS_FIGHT_LENGTH_DEFAULT)
	assert_float(WaveTimeline.BOSS_FIGHT_LENGTH_DEFAULT).is_equal(120.0)
	assert_int(d.boss_fight_max_count(0)).is_equal(WaveTimeline.BOSS_FIGHT_MAX_COUNT_DEFAULT)
	assert_int(_tl([], {"max_count": -7}).boss_fight_max_count(0)).is_equal(-1)
	assert_float(_tl([], {"length": 0}).boss_fight_length(0)).is_equal(1.0)
	# switched off, or none at all: no window (and a stage past the list reads the last stage's, as every stage key)
	assert_bool(_tl([], {"enabled": false, "roster": [{"t": 0, "enemy": "skeleton"}]}).has_boss_fight(0)).is_false()
	assert_bool(_tl([], {}).has_boss_fight(0)).is_false()
	assert_bool(WaveTimeline.new().has_boss_fight(0)).is_false()
	assert_array(WaveTimeline.new().boss_fight_rows(0)).is_empty()
	# the rows open at a fight second: t <= ct < until, no until = open to the cycle's end
	var rows := tl.boss_fight_rows(0)
	assert_int(WaveTimeline.boss_fight_open(rows, 5.0).size()).is_equal(1)
	assert_int(WaveTimeline.boss_fight_open(rows, 10.0).size()).is_equal(2)
	assert_int(WaveTimeline.boss_fight_open(rows, 40.0).size()).is_equal(1)
	# the block rides through the .tres as the JSON has it (stage_list is kept whole)
	var again: WaveTimeline = tl.duplicate(true)
	assert_float(again.boss_fight_length(0)).is_equal(90.0)


# ---------------------------------------------------------------- only the window spawns

func test_only_the_window_rows_spawn_while_the_boss_lives() -> void:
	var a := _test_def("p110_a", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var b := _test_def("p110_b", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# the stage's last row (A, open at the boss's second) and the window's (B); the specials' clock would bring a
	# Rocketeer every 0.2 s
	var tl := _tl([{"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter"}],
		{"length": 60, "max_count": 30, "roster": [{"id": "bf1-1", "t": 0, "enemy": b.id, "weights": [[0, 5]], "pattern": "scatter"}]},
		{"specials": {"from": 0, "interval": [0.2, 0.2], "max_alive": 3, "pool": [{"enemy": "rocketeer"}]},
		"floor_curve": [[0, 50]]})
	var d := _fight(w, tl)
	assert_int(d.phase).is_equal(WaveDirector.Phase.BOSS)
	assert_bool(d.boss_window.active).is_true()
	assert_bool(d.boss_window_on()).is_true()
	assert_int(em.boss_index).is_greater_equal(0)
	_play(d, 6.0)
	assert_int(em.alive_of(b.id)).is_greater(0)
	# nothing of the stage's rows, of the floor (which draws them) or of the specials
	assert_int(em.alive_of(a.id)).is_equal(0)
	assert_int(em.alive_of("rocketeer")).is_equal(0)
	assert_int(d.boss_window.came_total).is_equal(em.alive_of(b.id))
	# the cap the director reports in the fight is the window's
	assert_int(d.current_cap()).is_equal(30)
	# the boss dies: the window stops with the fight
	em.damage(em.boss_index, 1e7, "test")
	assert_int(d.phase).is_equal(WaveDirector.Phase.PORTAL)
	assert_bool(d.boss_window.active).is_false()
	assert_bool(d.boss_window_on()).is_false()
	d.stop()


func test_a_map_without_the_window_fights_as_before() -> void:
	var a := _test_def("p110_a", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var b := _test_def("p110_b", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var row := {"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter"}
	var specials := {"from": 0, "interval": [0.2, 0.2], "max_alive": 1, "pool": [{"enemy": "rocketeer"}]}
	for bf: Dictionary in [{}, {"enabled": false, "max_count": 3, "roster": [{"t": 0, "enemy": b.id}]}]:
		var w := _world()
		var em: EnemyManager = w["em"]
		var tl := _tl([row.duplicate(true)], bf, {"specials": specials})
		var d := _fight(w, tl)
		assert_bool(d.boss_window.active).is_false()
		assert_bool(d.boss_window_on()).is_false()
		# boss_cap_frac of the cap, the stage's last rows drawn, the specials' clock running
		assert_int(d.current_cap()).is_equal(int(tl.cap_at(END, 0) * tl.boss_cap_frac))
		_play(d, 4.0)
		assert_int(em.alive_of(a.id)).is_greater(0)
		assert_int(em.alive_of(b.id)).is_equal(0)
		assert_int(em.alive_of("rocketeer")).is_equal(1)
		d.stop()


# ---------------------------------------------------------------- the cycle loops

func test_the_cycle_loops_every_length_seconds() -> void:
	var b := _test_def("p110_b", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var c := _test_def("p110_c", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	# a 20 s cycle: a once row of 3 at 0:05, a waves row of 2 every 8 s from 0:00 (0, 8, 16: three waves a cycle), both
	# on top of the max count so only the schedule counts
	var tl := _tl([], {"length": 20, "max_count": 200, "roster": [
		{"id": "bf1-1", "t": 5, "enemy": b.id, "weights": [[0, 1]], "pace": "once", "count": 3, "respect_cap": false, "pattern": "scatter"},
		{"id": "bf1-2", "t": 0, "enemy": c.id, "weights": [[0, 1]], "pace": "waves", "every": 8, "count": 2, "respect_cap": false, "pattern": "scatter"}]})
	var d := _fight(w, tl)
	var bw := d.boss_window
	var kb := bw.key_of(bw.rows[0], 0)
	var kc := bw.key_of(bw.rows[1], 1)
	_play(d, 4.9)
	assert_int(int(bw.came_by.get(kb, 0))).is_equal(0)
	assert_int(int(bw.came_by.get(kc, 0))).is_equal(2)
	_play(d, 0.2)
	assert_int(int(bw.came_by.get(kb, 0))).is_equal(3)
	# one whole cycle: the once row once, the waves row three times
	_play(d, 14.8)
	assert_int(bw.cycles).is_equal(1)
	assert_int(int(bw.came_by.get(kb, 0))).is_equal(3)
	assert_int(int(bw.came_by.get(kc, 0))).is_equal(6)
	# the clock loops at 0:20: the waves row starts again from its t (a wave at 20, not at 24), the once row comes again
	_play(d, 0.2)
	assert_int(bw.cycles).is_equal(2)
	assert_int(int(bw.came_by.get(kc, 0))).is_equal(8)
	_play(d, 5.0)
	assert_int(int(bw.came_by.get(kb, 0))).is_equal(6)
	# three cycles: three once waves and nine waves of two
	_play(d, 34.6)
	assert_int(bw.cycles).is_equal(3)
	assert_int(int(bw.came_by.get(kb, 0))).is_equal(9)
	assert_int(int(bw.came_by.get(kc, 0))).is_equal(18)
	assert_float(bw.cycle_time()).is_less(20.0)
	d.stop()


# ---------------------------------------------------------------- the max count

func test_the_max_count_holds_with_the_boss_and_the_leftovers_counted() -> void:
	var a := _test_def("p110_a", "skeleton", {"pack_size": 2, "cap_share": 0.5})
	var b := _test_def("p110_b", "skeleton", {"pack_size": 5, "cap_share": 0.5})
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl := _tl([], {"length": 120, "max_count": 10, "roster": [
		{"id": "bf1-1", "t": 0, "enemy": b.id, "weights": [[0, 1]], "pattern": "scatter"}]}, {"burst_min": 20, "burst_max": 20})
	var d := _fight(w, tl)
	# twelve of the stage's crowd are still alive when the boss comes: nothing comes until they are under the count
	for k in range(12):
		em.spawn(a.id, Vector3(8.0 + k, 0, 8.0))
	_play(d, 3.0)
	assert_int(em.alive_of(b.id)).is_equal(0)
	assert_int(em.alive_count()).is_equal(13)
	# eight of them die: the window fills to its count, bodies whatever their share (the boss counts too)
	assert_int(_kill(em, a.id, 8)).is_equal(8)
	_play(d, 3.0)
	assert_int(em.alive_count()).is_equal(10)
	assert_int(em.alive_of(b.id)).is_equal(5)
	# many spawn checks later it still holds
	_play(d, 10.0)
	assert_int(em.alive_count()).is_less_equal(10)
	d.stop()


func test_a_wave_respects_the_max_count_unless_told_not_to() -> void:
	var b := _test_def("p110_b", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var c := _test_def("p110_c", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# max 6 bodies (the boss is one): a wave of 8 that respects it brings 5 and owes 3; one that does not brings all 8
	var tl := _tl([], {"length": 120, "max_count": 6, "roster": [
		{"id": "bf1-1", "t": 1, "enemy": b.id, "weights": [[0, 1]], "pace": "once", "count": 8, "pattern": "scatter"},
		{"id": "bf1-2", "t": 3, "enemy": c.id, "weights": [[0, 1]], "pace": "once", "count": 8, "respect_cap": false, "pattern": "scatter"}]})
	var d := _fight(w, tl)
	_play(d, 2.0)
	assert_int(em.alive_of(b.id)).is_equal(5)
	assert_int(int(d.boss_window.row_state(0).get("owed", 0))).is_equal(3)
	_play(d, 2.0)
	assert_int(em.alive_of(c.id)).is_equal(8)
	assert_int(em.alive_count()).is_equal(14)
	# the eight over the count die: the boss and the five are the count, so the owed three still wait
	assert_int(_kill(em, c.id, 99)).is_equal(8)
	_play(d, 1.0)
	assert_int(em.alive_of(b.id)).is_equal(5)
	assert_int(int(d.boss_window.row_state(0).get("owed", 0))).is_equal(3)
	# three of the five die: the owed three come into the room
	assert_int(_kill(em, b.id, 3)).is_equal(3)
	_play(d, 1.0)
	assert_int(em.alive_of(b.id)).is_equal(5)
	assert_int(int(d.boss_window.row_state(0).get("owed", 0))).is_equal(0)
	assert_int(em.alive_count()).is_equal(6)
	d.stop()


## Kills up to `n` living creatures of `id` (never the boss); returns how many died.
func _kill(em: EnemyManager, id: String, n: int) -> int:
	var gone := 0
	for i in range(em.pool_max):
		if gone >= n:
			break
		if em.alive[i] == 1 and em.state[i] != EnemyManager.STATE_DYING and i != em.boss_index and (em.types[em.type_idx[i]]["def"] as EnemyDef).id == id:
			em.damage(i, 1e9, "test")
			gone += 1
	return gone


# ---------------------------------------------------------------- numbers, summons

func test_a_window_row_is_fixed_from_the_stage_end() -> void:
	var b := _test_def("p110_b", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var tl := _tl([], {"length": 120, "max_count": 20, "roster": [
		{"id": "bf1-1", "t": 30, "enemy": b.id, "weights": [[0, 1]], "pace": "once", "count": 2, "pattern": "scatter"}]},
		{"hp_curve": {"mode": "points", "points": [[0, 1.0], [END, 3.0]]}})
	var d := _fight(w, tl)
	_play(d, 31.0)
	var s := d.source_state(d.boss_window.key_of(d.boss_window.rows[0], 0))
	assert_bool(s.is_empty()).is_false()
	# its numbers come from the run clock at the fight (the stage's end), not from its own 0:30 on the fight clock
	assert_float(float(s["t0"])).is_equal(END)
	assert_float(float(s["hp_time"])).is_equal_approx(3.0, 0.0001)
	d.stop()


func test_the_bosses_summons_stop_at_the_hard_cap() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl := _tl([], {"length": 120, "max_count": 5, "roster": []}, {"hard_cap": 20})
	var d := _fight(w, tl)
	for k in range(14):
		em.spawn("skeleton", Vector3(6.0 + k, 0, 6.0))
	# fifteen alive (the boss and fourteen): a spawn_ring of 16 may bring five
	assert_int(d.summon_room(16)).is_equal(5)
	assert_int(em.summon_count(16)).is_equal(5)
	assert_int(d.summon_room(3)).is_equal(3)
	for k in range(10):
		em.spawn("skeleton", Vector3(6.0 + k, 0, 10.0))
	assert_int(em.summon_count(16)).is_equal(0)
	# without a director a summon keeps its count
	var em2 := EnemyManager.new()
	assert_int(em2.summon_count(16)).is_equal(16)
	em2.free()
	d.stop()


# ---------------------------------------------------------------- Red Canyon's windows

func _json() -> Dictionary:
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func test_red_canyon_has_a_window_on_every_stage() -> void:
	# the map's own numbers are Garry's to tune: the shape is read from the file, never pinned
	var tl := JsonContent.timeline_from_dict(_json().get("timeline_data", {}))
	for s in range(tl.stage_count()):
		assert_bool(tl.has_boss_fight(s)).override_failure_message("stage %d has no boss-fight window" % (s + 1)).is_true()
		var length := tl.boss_fight_length(s)
		var mx := tl.boss_fight_max_count(s)
		assert_int(mx).override_failure_message("stage %d: max_count %d" % [s + 1, mx]).is_greater(0)
		# lower numbers than the stage's own end: well under its cap's bodies (the cap in load is at least the bodies of
		# half-share creatures / 2)
		assert_int(mx).is_less(tl.hard_cap)
		var rows := tl.boss_fight_rows(s)
		assert_int(rows.size()).override_failure_message("stage %d's window is empty" % (s + 1)).is_greater(0)
		for r: Dictionary in rows:
			var e = r.get("enemy", "")
			var ids: Array = e if e is Array else [e]
			for id in ids:
				if str(id) != WaveTimeline.ROW_ENEMY_ROSTER:
					assert_object(Registry.enemy(str(id))).override_failure_message("stage %d row %s: no creature %s" % [s + 1, str(r.get("id", "")), str(id)]).is_not_null()
			var t := float(r.get("t", 0.0))
			assert_float(t).is_greater_equal(0.0)
			assert_float(t).override_failure_message("stage %d row %s starts past its cycle" % [s + 1, str(r.get("id", ""))]).is_less(length)
			if r.get("until") != null:
				assert_float(float(r["until"])).is_greater(t)
