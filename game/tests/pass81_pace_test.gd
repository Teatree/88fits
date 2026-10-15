extends GdUnitTestSuite

## Pass 81, lane PACE (Garry: "Add the ability to control the pacing of the waves. I mean the frequency at which enemy
## waves come"): a roster row's `pace`. "continuous" (the default) is every row as it always was: drawn into the cap by
## its weight at each spawn check. "waves": wave k at t + offset + k x every while the row is open, `count` creatures
## each (default its pack), cut to its channel's room with `respect_cap` (the rest owed, ahead of the continuous draw,
## until the next wave), never in the continuous draw unless it has `trickle`; a wave due while the row weighs 0 does
## not come; a jumped clock fires one wave, not a backlog. The keys read; the schedule's maths (WaveTimeline.row_*).

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


# ---------------------------------------------------------------- the keys and the schedule

func test_the_row_keys_read_and_the_schedule_maths() -> void:
	var tl := _tl({"roster": [{"id": "r1", "t": 10, "until": 80, "enemy": "skeleton", "weights": [[10, 5]], "pace": "waves",
		"every": 20, "count": 7, "offset": 5, "respect_cap": false, "trickle": true}]})
	var r: Dictionary = tl.roster[0]
	# the keys ride on the row as written (the roster rows are plain dictionaries)
	assert_str(str(r["pace"])).is_equal("waves")
	assert_float(float(r["every"])).is_equal(20.0)
	assert_int(int(r["count"])).is_equal(7)
	assert_float(float(r["offset"])).is_equal(5.0)
	assert_bool(bool(r["respect_cap"])).is_false()
	assert_bool(bool(r["trickle"])).is_true()
	assert_bool(WaveTimeline.row_paced(r)).is_true()
	assert_bool(WaveTimeline.row_drawn(r)).is_true()
	# t + offset + k x every, before until
	assert_array(WaveTimeline.row_wave_times(r, 1000.0)).is_equal([15.0, 35.0, 55.0, 75.0])
	assert_array(WaveTimeline.row_wave_times(r, 50.0)).is_equal([15.0, 35.0])
	assert_int(WaveTimeline.row_wave_index(r, 14.9)).is_equal(-1)
	assert_int(WaveTimeline.row_wave_index(r, 15.0)).is_equal(0)
	assert_int(WaveTimeline.row_wave_index(r, 54.99)).is_equal(1)
	assert_int(WaveTimeline.row_wave_index(r, 55.0)).is_equal(2)
	assert_float(WaveTimeline.row_wave_time(r, 3)).is_equal(75.0)
	assert_int(WaveTimeline.row_wave_count(r, 4)).is_equal(7)
	# the defaults: continuous; a waves row every 30 s from its t, a wave its pack (else the creature's), no trickle
	var plain := {"t": 0, "enemy": "skeleton"}
	assert_bool(WaveTimeline.row_paced(plain)).is_false()
	assert_bool(WaveTimeline.row_drawn(plain)).is_true()
	assert_array(WaveTimeline.row_wave_times(plain, 100.0)).is_empty()
	assert_bool(WaveTimeline.row_paced({"pace": "continuous"})).is_false()
	assert_bool(WaveTimeline.row_paced({"pace": "nonsense"})).is_false()
	var w := {"t": 100, "pace": "waves", "pack": 6}
	assert_bool(WaveTimeline.row_drawn(w)).is_false()
	assert_float(WaveTimeline.row_wave_every(w)).is_equal(WaveTimeline.ROW_WAVE_EVERY_DEFAULT)
	assert_array(WaveTimeline.row_wave_times(w, 170.0)).is_equal([100.0, 130.0, 160.0])
	assert_int(WaveTimeline.row_wave_count(w, 3)).is_equal(6)
	assert_int(WaveTimeline.row_wave_count({"pace": "waves"}, 3)).is_equal(3)
	# every 0 = one wave only; a negative offset is no offset
	var once := {"t": 40, "pace": "waves", "every": 0, "offset": -9}
	assert_array(WaveTimeline.row_wave_times(once, 1000.0)).is_equal([40.0])
	assert_int(WaveTimeline.row_wave_index(once, 900.0)).is_equal(0)


# ---------------------------------------------------------------- a waves row spawns only at its times

func test_a_waves_row_spawns_only_at_its_times_and_its_count() -> void:
	var d := _test_def("p81_waves", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"burst_min": 20, "burst_max": 20, "roster": [
		{"id": "r1", "t": 10, "until": 100, "enemy": d.id, "weights": [[10, 5]], "pace": "waves", "every": 20, "count": 7,
		"pattern": "scatter"}]}))
	dir._rng.seed = 11
	_frame(dir, 9.9)
	assert_int(em.alive_count()).is_equal(0)
	assert_bool(dir.row_wave_state(0).is_empty()).is_true()
	_frame(dir, 10.0)
	assert_int(em.alive_count()).is_equal(7)
	var st := dir.row_wave_state(0)
	assert_int(int(st["k"])).is_equal(0)
	assert_int(int(st["owed"])).is_equal(0)
	assert_int(int(st["came"])).is_equal(7)
	# between its waves nothing more of it comes: the spawn checks leave it out of the continuous draw
	for k in range(30):
		_frame(dir, 10.5 + 0.6 * k)
	assert_int(em.alive_count()).is_equal(7)
	_frame(dir, 30.0)
	assert_int(em.alive_count()).is_equal(14)
	# a clock that jumped (a tool): the latest wave due (k 4, at 90 s) comes once, the ones skipped over do not
	_frame(dir, 95.0)
	assert_int(em.alive_count()).is_equal(21)
	assert_int(int(dir.row_wave_state(0)["k"])).is_equal(4)
	assert_int(int(dir.row_wave_state(0)["waves"])).is_equal(3)
	_frame(dir, 99.0)
	assert_int(em.alive_count()).is_equal(21)
	# closed at until: no more
	_frame(dir, 110.0)
	_frame(dir, 130.0)
	assert_int(em.alive_count()).is_equal(21)
	# the row's numbers were fixed at its first wave, from its start (pass 58), under the row's own key
	var src := dir.source_state(dir.row_key(dir.timeline.roster[0]))
	assert_float(float(src.get("t0", -1.0))).is_equal(10.0)


func test_an_offset_moves_the_first_wave_and_a_count_defaults_to_the_pack() -> void:
	var d := _test_def("p81_offset", "skeleton", {"pack_size": 4, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [
		{"id": "r1", "t": 10, "enemy": d.id, "weights": [[10, 1]], "pace": "waves", "every": 10, "offset": 5, "pack": 3}]}))
	_frame(dir, 10.0)
	_frame(dir, 14.9)
	assert_int(em.alive_count()).is_equal(0)
	_frame(dir, 15.0)
	# no count: the row's pack, 3 (the creature's own 4 when the row names none)
	assert_int(em.alive_count()).is_equal(3)
	_frame(dir, 25.0)
	assert_int(em.alive_count()).is_equal(6)


func test_a_wave_due_while_the_row_weighs_zero_does_not_come() -> void:
	var d := _test_def("p81_gate", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 0], [30, 0], [31, 5]], "pace": "waves", "every": 10, "count": 2}]}))
	for t: float in [0.0, 10.0, 20.0, 30.0]:
		_frame(dir, t)
	assert_int(em.alive_count()).is_equal(0)
	assert_int(int(dir.row_wave_state(0)["waves"])).is_equal(0)
	_frame(dir, 40.0)
	assert_int(em.alive_count()).is_equal(2)
	assert_int(int(dir.row_wave_state(0)["waves"])).is_equal(1)


# ---------------------------------------------------------------- continuous unchanged

func test_a_continuous_row_draws_as_before_and_a_waves_row_only_with_trickle() -> void:
	var d := _test_def("p81_cont", "skeleton", {"pack_size": 3, "cap_share": 1.0})
	var counts: Array = []
	for row: Dictionary in [
			{"t": 0, "enemy": d.id, "weight": 1, "pack": 3},
			{"t": 0, "enemy": d.id, "weight": 1, "pack": 3, "pace": "continuous"},
			{"t": 0, "enemy": d.id, "weight": 1, "pack": 3, "pace": "waves", "every": 20, "trickle": true},
			{"t": 0, "enemy": d.id, "weight": 1, "pack": 3, "pace": "waves", "every": 20}]:
		var w := _world()
		var dir := _director(w, _tl({"burst_min": 9, "burst_max": 9}))
		dir._rng.seed = 21
		var left := dir._burst_from([row], 9.0, 300)
		counts.append([(w["em"] as EnemyManager).alive_count(), left])
	# no pace and "continuous" draw the same; a trickling waves row is drawn like them; a waves row alone draws nothing
	assert_array(counts[0]).is_equal([9, 291])
	assert_array(counts[1]).is_equal(counts[0])
	assert_array(counts[2]).is_equal(counts[0])
	assert_array(counts[3]).is_equal([0, 300])


func test_a_timeline_without_waves_rows_keeps_no_wave_state() -> void:
	var d := _test_def("p81_quiet", "skeleton", {"pack_size": 3, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"cap_start": 12, "cap_max": 12, "burst_min": 20, "burst_max": 20, "roster": [{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]]}]}))
	_frame(dir, 1.0)
	_frame(dir, 2.0)
	assert_bool(dir._row_waves.is_empty()).is_true()
	# the continuous row still fills the cap
	assert_float(em.cap_load()).is_greater_equal(12.0)


# ---------------------------------------------------------------- the cap

func test_a_wave_respects_the_cap_and_its_rest_comes_first_as_room_frees() -> void:
	var a := _test_def("p81_capa", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var b := _test_def("p81_capb", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# a cap of 10 that grows to 14 at 12 s; a waves row of 25 and a continuous row beside it
	var dir := _director(w, _tl({"cap_curve": [[0, 10], [11, 10], [12, 14]], "burst_min": 20, "burst_max": 20, "roster": [
		{"id": "r1", "t": 10, "enemy": a.id, "weights": [[10, 5]], "pace": "waves", "every": 20, "count": 25},
		{"id": "r2", "t": 11, "enemy": b.id, "weights": [[11, 5]]}]}))
	_frame(dir, 10.0)
	# ten load units of room: ten of the wave, fifteen owed
	assert_int(em.alive_of(a.id)).is_equal(10)
	assert_int(int(dir.row_wave_state(0)["owed"])).is_equal(15)
	assert_float(em.cap_load()).is_less_equal(10.0)
	_frame(dir, 11.0)
	assert_int(em.alive_of(a.id) + em.alive_of(b.id)).is_equal(10)
	# the cap grows by four: the wave's rest takes the room ahead of the continuous row
	_frame(dir, 12.0)
	assert_int(em.alive_of(a.id)).is_equal(14)
	assert_int(em.alive_of(b.id)).is_equal(0)
	assert_int(int(dir.row_wave_state(0)["owed"])).is_equal(11)
	assert_float(em.cap_load()).is_less_equal(14.0)
	# the next wave drops what the last one still owed: it owes its own 25, and the cap holds
	_frame(dir, 30.0)
	assert_int(int(dir.row_wave_state(0)["k"])).is_equal(1)
	assert_int(int(dir.row_wave_state(0)["owed"])).is_equal(25)
	assert_float(em.cap_load()).is_less_equal(14.0)


func test_a_wave_off_the_cap_comes_whole_and_the_hard_cap_and_max_alive_hold() -> void:
	var d := _test_def("p81_rude", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"cap_start": 10, "cap_max": 10, "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pace": "waves", "every": 10, "count": 25, "respect_cap": false}]}))
	_frame(dir, 0.0)
	assert_int(em.alive_count()).is_equal(25)
	# the hard cap still holds
	var w2 := _world()
	var em2: EnemyManager = w2["em"]
	var dir2 := _director(w2, _tl({"cap_start": 10, "cap_max": 10, "hard_cap": 18, "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pace": "waves", "every": 10, "count": 25, "respect_cap": false}]}))
	_frame(dir2, 0.0)
	assert_int(em2.alive_count()).is_equal(18)
	# so does the row's max_alive
	var w3 := _world()
	var em3: EnemyManager = w3["em"]
	var dir3 := _director(w3, _tl({"roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pace": "waves", "every": 10, "count": 25, "stats": {"max_alive": 6}}]}))
	_frame(dir3, 0.0)
	_frame(dir3, 10.0)
	assert_int(em3.alive_of(d.id)).is_equal(6)


func test_a_hell_waves_row_spawns_into_the_hell_room() -> void:
	var d := _test_def("p81_hell", "skeleton", {"pack_size": 10, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# a cap of 8, the hell channel half of it: a hell wave of 10 gets four now
	var dir := _director(w, _tl({"cap_start": 8, "cap_max": 8, "hell_cap": [0.5], "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pace": "waves", "every": 10, "count": 10, "channel": "hell"}]}))
	_frame(dir, 0.0)
	assert_int(em.alive_count()).is_equal(4)
	assert_int(int(dir.row_wave_state(0)["owed"])).is_equal(6)
	assert_float(dir._channel_room("regular")).is_equal_approx(8.0, 0.001)


func test_a_boss_fight_holds_what_a_wave_owes() -> void:
	var d := _test_def("p81_boss", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"cap_curve": [[0, 4], [11, 4], [12, 30]], "roster": [
		{"id": "r1", "t": 10, "enemy": d.id, "weights": [[10, 1]], "pace": "waves", "every": 60, "count": 12}]}))
	_frame(dir, 10.0)
	assert_int(em.alive_count()).is_equal(4)
	dir.phase = WaveDirector.Phase.BOSS
	Run.elapsed = 12.0
	dir._spawn_burst()
	assert_int(em.alive_count()).is_equal(4)
	assert_int(int(dir.row_wave_state(0)["owed"])).is_equal(8)
	dir.phase = WaveDirector.Phase.NORMAL
	dir._spawn_burst()
	assert_int(em.alive_count()).is_equal(12)
	assert_int(int(dir.row_wave_state(0)["owed"])).is_equal(0)
