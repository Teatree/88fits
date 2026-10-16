extends GdUnitTestSuite

## Pass 83, lane TIMELINE (Garry: "for Continuous spawning, I would still like to control the interval of continuous
## spawning, the 0.7s can be a default"): a roster row in the continuous draw may carry `interval` (seconds). Without it
## the row draws at the director's spawn check as before (the same dice); with it the row draws on its own clock, every
## `interval` seconds from the frame it opens, a burst cut to its share of the channel's weight (a burst below one
## creature brings one with that chance), and the spawn check draws the other rows with their share only.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
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

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero with a plain map and the real crowd (pass53_waves_test's way).
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


## A timeline from `extra` over quiet test defaults: a flat cap of 100, no roster, no events, colour from the start.
func _tl(extra: Dictionary = {}) -> WaveTimeline:
	var base := {"stage_length": 430, "stages": 3, "cap_start": 100, "cap_per_minute": 0, "cap_max": 300, "hard_cap": 300,
		"spawn_interval": 0.5, "roster": [], "events": [], "waves": [], "colour_after_kills": 0, "hell_cap": [0.5, 0.5, 0.5]}
	for k in extra.keys():
		base[k] = extra[k]
	return JsonContent.timeline_from_dict(base)


func _director(w: Dictionary, tl: WaveTimeline) -> WaveDirector:
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = tl
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	return d


## A test creature `id` made from `from`, no variance, with `fields` set; gone after the test.
func _test_def(id: String, from: String, fields: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	for k: String in fields.keys():
		d.set(k, fields[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


## The director's normal-phase frame at run second `t` as far as spawning goes: the rows' waves, then a spawn check.
func _frame(dir: WaveDirector, t: float) -> void:
	Run.elapsed = t
	dir._tick_row_waves()
	dir._spawn_burst()


# ---------------------------------------------------------------- the key

func test_the_interval_key_reads() -> void:
	assert_bool(WaveDirector.row_has_interval({"t": 0})).is_false()
	assert_bool(WaveDirector.row_has_interval({"interval": 0})).is_false()
	assert_bool(WaveDirector.row_has_interval({"interval": -1.0})).is_false()
	assert_bool(WaveDirector.row_has_interval({"interval": "2"})).is_false()
	assert_bool(WaveDirector.row_has_interval({"interval": 2})).is_true()
	assert_bool(WaveDirector.row_has_interval("not a row")).is_false()
	assert_float(WaveDirector.row_draw_interval({"t": 0}, 0.7)).is_equal_approx(0.7, 1e-9)
	assert_float(WaveDirector.row_draw_interval({"interval": 2.5}, 0.7)).is_equal_approx(2.5, 1e-9)
	assert_float(WaveDirector.row_draw_interval({"interval": 0.01}, 0.7)).is_equal_approx(WaveDirector.ROW_INTERVAL_MIN, 1e-9)


# ---------------------------------------------------------------- absent = today's

func test_a_row_without_the_key_draws_as_before() -> void:
	# pass81_pace_test's pin: seed 21, a burst of 9, packs of 3 -> 9 creatures, 291 bodies left
	var d := _test_def("p83_plain", "skeleton", {"pack_size": 3, "cap_share": 1.0})
	var w := _world()
	var dir := _director(w, _tl({"burst_min": 9, "burst_max": 9}))
	dir._rng.seed = 21
	var left := dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 3}], 9.0, 300)
	assert_int((w["em"] as EnemyManager).alive_count()).is_equal(9)
	assert_int(left).is_equal(291)
	# and its own clock never draws it
	var w2 := _world()
	var dir2 := _director(w2, _tl({"burst_min": 9, "burst_max": 9, "roster": [{"t": 0, "enemy": d.id, "weight": 1, "pack": 3}]}))
	Run.elapsed = 1.0
	for k in range(20):
		dir2._tick_row_intervals(0.25)
	assert_int((w2["em"] as EnemyManager).alive_count()).is_equal(0)
	assert_bool(dir2._row_draw_left.is_empty()).is_true()


# ---------------------------------------------------------------- its own clock

func test_an_own_interval_row_is_left_out_of_the_spawn_check() -> void:
	var a := _test_def("p83_chk_a", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var b := _test_def("p83_chk_b", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"burst_min": 8, "burst_max": 8}))
	dir._rng.seed = 5
	# alone it is not drawn at the check at all
	dir._burst_from([{"t": 0, "enemy": b.id, "weight": 1, "interval": 2.0}], 8.0, 300)
	assert_int(em.alive_count()).is_equal(0)
	# beside a plain row of the same weight: the plain one takes its half of the burst (4 of 8), the other none
	dir._burst_from([{"t": 0, "enemy": a.id, "weight": 1}, {"t": 0, "enemy": b.id, "weight": 1, "interval": 2.0}], 8.0, 300)
	assert_int(em.alive_of(a.id)).is_equal(4)
	assert_int(em.alive_of(b.id)).is_equal(0)


func test_an_own_interval_row_draws_every_interval_from_its_start() -> void:
	var d := _test_def("p83_clock", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"burst_min": 3, "burst_max": 3, "roster": [{"t": 1, "until": 9, "enemy": d.id, "weight": 1, "interval": 2.0}]}))
	var t := 0.0
	# 0.25 s frames from 0 to 12 s: closed before 1 s, then a draw on its first open frame and one every 2 s, till 9 s
	for k in range(48):
		t += 0.25
		Run.elapsed = t
		dir._tick_row_intervals(0.25)
		if is_equal_approx(t, 0.75):
			assert_int(em.alive_count()).is_equal(0)
		if is_equal_approx(t, 1.0):
			assert_int(em.alive_count()).is_equal(3)
		if is_equal_approx(t, 2.75):
			assert_int(em.alive_count()).is_equal(3)
		if is_equal_approx(t, 3.0):
			assert_int(em.alive_count()).is_equal(6)
	# draws at 1, 3, 5, 7 (9 is its until): four bursts of 3, the whole burst (it is the only row: its share is 1)
	assert_int(em.alive_count()).is_equal(12)


func test_an_own_interval_draw_takes_its_share_of_the_channel() -> void:
	var a := _test_def("p83_sh_a", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var b := _test_def("p83_sh_b", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"burst_min": 8, "burst_max": 8, "roster": [
		{"t": 0, "enemy": a.id, "weight": 3},
		{"t": 0, "enemy": b.id, "weight": 1, "interval": 1.5}]}))
	Run.elapsed = 0.5
	dir._tick_row_intervals(0.1)
	# its own draw: 8 x 1 / (3 + 1) = 2 creatures of its own, none of the plain row
	assert_int(em.alive_of(b.id)).is_equal(2)
	assert_int(em.alive_of(a.id)).is_equal(0)
	# the spawn check: 8 x 3 / 4 = 6 of the plain row, none of the own-interval one
	dir._spawn_burst()
	assert_int(em.alive_of(a.id)).is_equal(6)
	assert_int(em.alive_of(b.id)).is_equal(2)


func test_a_cut_burst_below_one_creature_keeps_its_expected_count() -> void:
	var a := _test_def("p83_lo_a", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var b := _test_def("p83_lo_b", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var own := {"t": 0, "enemy": b.id, "weight": 1, "interval": 0.7}
	var dir := _director(w, _tl({"cap_start": 300, "cap_max": 300, "burst_min": 5, "burst_max": 5, "roster": [{"t": 0, "enemy": a.id, "weight": 9}, own]}))
	dir._rng.seed = 83
	Run.elapsed = 1.0
	# 5 x 1 / 10 = half a creature a draw: about 100 in 200 draws, never one at every draw
	for k in range(200):
		dir._spawn_burst([dir.timeline.roster[1]])
	assert_int(em.alive_of(a.id)).is_equal(0)
	assert_int(em.alive_of(b.id)).is_between(70, 130)


func test_a_waves_row_with_an_interval_draws_only_when_it_trickles() -> void:
	var d := _test_def("p83_wv", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	for trickle: bool in [false, true]:
		var w := _world()
		var dir := _director(w, _tl({"burst_min": 2, "burst_max": 2, "roster": [{"t": 0, "enemy": d.id, "weight": 1, "pace": "waves", "every": 100, "offset": 50, "interval": 1.0, "trickle": trickle}]}))
		Run.elapsed = 2.0
		dir._tick_row_intervals(0.1)
		assert_int((w["em"] as EnemyManager).alive_count()).is_equal(2 if trickle else 0)
