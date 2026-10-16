extends GdUnitTestSuite

## Pass 84, lane SPAWN (Garry: "spawning options are important to me ... But I do agree that there are too many ways of
## spawning an enemy right now"): one spawning language. The row keys (pace "once", every [min, max], enemy lists with
## enemy_weights and "roster", elite, special, banner, ring_radius, chance, t_jitter; role and name ignored), the mix
## (WaveTimeline.row_in_mix), a once row playing exactly as the swarm event it replaces (the same spots, numbers and
## dice), Elites-every as a row (its firings, Hot Sauce, colour), the density floor, an old map's rows taking no new
## dice, the shown difficulty against the HP a creature really spawns with, and Red Canyon migrated (no swarm / elite /
## elite_every event left).

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

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"

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


## The director's normal-phase frame at run second `t`: the events, the rows' waves, a spawn check.
func _frame(dir: WaveDirector, t: float) -> void:
	Run.elapsed = t
	dir._process_events()
	dir._tick_row_waves()
	dir._spawn_burst()


## Every living creature's [type id, position rounded to 1 mm, max hp, elite modifier index, special flag], sorted.
func _crowd(em: EnemyManager) -> Array:
	var out: Array = []
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 0:
			continue
		var p: Vector3 = em.pos[i]
		out.append([str((em.types[em.type_idx[i]]["def"] as EnemyDef).id), snappedf(p.x, 0.001), snappedf(p.z, 0.001),
			snappedf(em.max_hp[i], 0.001), int(em.elite_idx[i]), int(em.vspecial[i])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	return out


func _modded(em: EnemyManager) -> int:
	var n := 0
	for i in range(EnemyManager.MAX):
		if em.alive[i] != 0 and em.elite_idx[i] >= 0:
			n += 1
	return n


# ---------------------------------------------------------------- the keys

func test_the_row_keys_and_the_mix() -> void:
	var once := {"t": 120, "pace": "once", "enemy": "skeleton", "count": 5}
	assert_bool(WaveTimeline.row_paced(once)).is_true()
	assert_bool(WaveTimeline.row_drawn(once)).is_false()
	assert_float(WaveTimeline.row_wave_every(once)).is_equal(0.0)
	assert_array(WaveTimeline.row_wave_times(once, 1000.0)).is_equal([120.0])
	assert_bool(WaveTimeline.ROW_PACES.has("once")).is_true()
	# every [min, max] reads as its middle for the schedule's rhythm, and makes the row a timer
	var ranged := {"t": 0, "pace": "waves", "every": [10, 30], "enemy": "skeleton"}
	assert_float(WaveTimeline.row_wave_every(ranged)).is_equal(20.0)
	assert_bool(WaveTimeline.row_timer(ranged)).is_true()
	assert_bool(WaveTimeline.row_timer({"t": 0, "pace": "waves", "every": 10, "enemy": "skeleton"})).is_false()
	assert_bool(WaveTimeline.row_timer({"t": 0, "pace": "waves", "every": 10, "enemy": "roster", "elite": "random"})).is_true()
	assert_bool(WaveTimeline.row_timer({"t": 0, "enemy": "skeleton", "elite": "random"})).is_false()
	# the mix: one creature by id, no elite, no special, not once
	assert_bool(WaveTimeline.row_in_mix({"t": 0, "enemy": "skeleton"})).is_true()
	assert_bool(WaveTimeline.row_in_mix({"t": 0, "enemy": "skeleton", "pace": "waves", "role": "tank", "name": "x"})).is_true()
	assert_bool(WaveTimeline.row_in_mix(once)).is_false()
	assert_bool(WaveTimeline.row_in_mix({"t": 0, "enemy": ["skeleton", "goblin"]})).is_false()
	assert_bool(WaveTimeline.row_in_mix({"t": 0, "enemy": "roster"})).is_false()
	assert_bool(WaveTimeline.row_in_mix({"t": 0, "enemy": "skeleton", "elite": "random"})).is_false()
	assert_bool(WaveTimeline.row_in_mix({"t": 0, "enemy": "skeleton", "special": true})).is_false()
	assert_str(WaveTimeline.row_elite({"elite": "random"})).is_equal("random")
	assert_str(WaveTimeline.row_elite({"elite": false})).is_equal("")
	assert_str(WaveTimeline.row_elite({})).is_equal("")
	# the floor curve reads from the JSON, linear between its points; none = 0
	var tl := _tl({"floor_curve": [[0, 10], [100, 30]]})
	assert_int(tl.floor_curve.size()).is_equal(2)
	assert_float(tl.floor_at(50.0)).is_equal_approx(20.0, 0.0001)
	assert_float(_tl().floor_at(50.0)).is_equal(0.0)


# ---------------------------------------------------------------- a once row is the swarm it replaces

## The same swarm as an event and as the converted once row, in two worlds with the same dice: the same creatures at
## the same spots with the same HP, the same banner.
func _swarm_pair(ev: Dictionary, row: Dictionary, roster: Array, t: float) -> Array:
	var out: Array = []
	for k in range(2):
		var w := _world()
		var em: EnemyManager = w["em"]
		var tl := _tl({"roster": roster.duplicate(true) + ([row.duplicate(true)] if k == 1 else []),
			"events": [ev.duplicate(true)] if k == 0 else [], "burst_min": 0, "burst_max": 0})
		var dir := _director(w, tl)
		dir._rng.seed = 7
		em._rng.seed = 9
		_frame(dir, t - 0.5)
		_frame(dir, t)
		_frame(dir, t + 0.5)
		out.append({"crowd": _crowd(em), "toasts": (w["g"].toasts as Array).duplicate()})
	return out


func test_a_once_row_is_the_ring_swarm_it_replaces() -> void:
	var d := _test_def("p84_ant", "fire_ant", {"pack_size": 6, "cap_share": 0.5})
	var ev := {"t": 610, "type": "swarm", "enemy": d.id, "count": 24, "name": "Ant swarm", "stats": {"hp_mult": 0.78}}
	var row := {"id": "r9", "name": "Ant swarm", "t": 610, "enemy": d.id, "weights": [[610, 1]], "pace": "once", "count": 24,
		"pattern": "ring", "ring_radius": 16, "respect_cap": false, "respect_hard_cap": false, "banner": "SWARM!", "role": "swarm", "stats": {"hp_mult": 0.78}}
	var got := _swarm_pair(ev, row, [], 610.0)
	assert_int((got[0]["crowd"] as Array).size()).is_equal(24)
	assert_array(got[1]["crowd"]).is_equal(got[0]["crowd"])
	assert_array(got[1]["toasts"]).is_equal(["SWARM!"])
	assert_array(got[0]["toasts"]).is_equal(["SWARM!"])
	# every one 16 m from the hero (the swarm's own ring)
	for c: Array in got[1]["crowd"]:
		assert_float(Vector2(float(c[1]), float(c[2])).length()).is_between(14.5, 17.5)


func test_a_once_row_joins_a_mix_row_for_its_numbers_as_the_swarm_did() -> void:
	var d := _test_def("p84_join", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	# a mix row of the same creature open since 100 s: the swarm at 400 s plays that row's numbers (pass 58's join)
	var mix := [{"id": "r1", "t": 100, "until": 900, "enemy": d.id, "weights": [[100, 0.0001]], "stats": {"damage_mult": 2}}]
	var ev := {"t": 400, "type": "swarm", "enemy": d.id, "count": 6, "pattern": "scatter"}
	var row := {"id": "r2", "t": 400, "enemy": d.id, "weights": [[400, 1]], "pace": "once", "count": 6, "pattern": "scatter",
		"respect_cap": false, "banner": "SWARM!"}
	var got := _swarm_pair(ev, row, mix, 400.0)
	assert_array(got[1]["crowd"]).is_equal(got[0]["crowd"])


func test_a_special_once_row_is_the_special_goblin() -> void:
	var d := _test_def("p84_gob", "red_goblin", {"pack_size": 4, "cap_share": 1.0, "variance": {"special_chance": 0.0}})
	var ev := {"t": 120, "type": "swarm", "enemy": d.id, "count": 1, "pattern": "in_front", "special": true, "name": "Special Goblin"}
	var row := {"id": "r6", "name": "Special Goblin", "t": 120, "enemy": d.id, "weights": [[120, 1]], "pace": "once", "count": 1,
		"pattern": "in_front", "respect_cap": false, "respect_hard_cap": false, "special": true, "role": "special"}
	var got := _swarm_pair(ev, row, [], 120.0)
	assert_int((got[1]["crowd"] as Array).size()).is_equal(1)
	assert_array(got[1]["crowd"]).is_equal(got[0]["crowd"])
	# no banner for a special, as the event had none
	assert_array(got[1]["toasts"]).is_empty()


func test_a_once_row_fires_once_and_a_jumped_clock_drops_it() -> void:
	var d := _test_def("p84_one", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [{"id": "r1", "t": 50, "enemy": d.id, "weights": [[50, 1]], "pace": "once",
		"count": 7, "pattern": "scatter", "respect_cap": false}], "burst_min": 0, "burst_max": 0}))
	_frame(dir, 49.9)
	assert_int(em.alive_count()).is_equal(0)
	_frame(dir, 50.0)
	assert_int(em.alive_count()).is_equal(7)
	_frame(dir, 80.0)
	_frame(dir, 500.0)
	assert_int(em.alive_count()).is_equal(7)
	# a director whose clock jumps past the row (a tool) drops it, as a skipped event
	var w2 := _world()
	var dir2 := _director(w2, _tl({"roster": [{"id": "r1", "t": 50, "enemy": d.id, "weights": [[50, 1]], "pace": "once",
		"count": 7, "pattern": "scatter", "respect_cap": false}], "burst_min": 0, "burst_max": 0}))
	_frame(dir2, 300.0)
	assert_int((w2["em"] as EnemyManager).alive_count()).is_equal(0)


# ---------------------------------------------------------------- Elites every as a row

func test_elites_every_as_a_row_fires_as_the_event_did() -> void:
	var d := _test_def("p84_el", "skeleton", {"pack_size": 3, "cap_share": 1.0})
	var mix := [{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]]}]
	var ev := {"t": 301, "type": "elite_every", "interval": 129}
	var row := {"id": "r7", "name": "Elites every", "t": 301, "enemy": "roster", "weights": [[301, 1]], "pace": "waves",
		"every": 129, "count": 1, "respect_cap": false, "elite": "random", "role": "elite"}
	var out: Array = []
	for k in range(2):
		var w := _world()
		var em: EnemyManager = w["em"]
		var dir := _director(w, _tl({"roster": mix.duplicate(true) + ([row.duplicate(true)] if k == 1 else []),
			"events": [ev.duplicate(true)] if k == 0 else [], "burst_min": 0, "burst_max": 0}))
		dir._rng.seed = 3
		em._rng.seed = 5
		var fired: Array = []
		for s in range(290, 700):
			var before := _modded(em)
			_frame(dir, float(s))
			if _modded(em) > before:
				fired.append(s)
		out.append({"fired": fired, "crowd": _crowd(em), "toasts": (w["g"].toasts as Array).duplicate()})
	var pace: float = 1.0
	var first := 301
	assert_array(out[1]["fired"]).is_equal(out[0]["fired"])
	assert_int((out[1]["fired"] as Array)[0]).is_equal(first)
	assert_int((out[1]["fired"] as Array).size()).is_equal(4)
	assert_float(float((out[1]["fired"] as Array)[1]) - float(first)).is_equal_approx(ceilf(129.0 / pace), 1.0)
	assert_array(out[1]["crowd"]).is_equal(out[0]["crowd"])
	assert_array(out[1]["toasts"]).is_equal(out[0]["toasts"])


func test_an_elite_row_waits_for_colour_and_its_gap_follows_hot_sauce() -> void:
	var d := _test_def("p84_col", "skeleton", {"pack_size": 3, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"colour_after_kills": 5, "burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]]},
		{"id": "r2", "t": 10, "enemy": "roster", "weights": [[10, 1]], "pace": "waves", "every": 40, "count": 2, "elite": "random"}]}))
	Run.kills = 0
	_frame(dir, 10.0)
	_frame(dir, 11.0)
	assert_int(_modded(em)).is_equal(0)
	# colour opens: the wave comes at the next ask, two arrivals, and the next one its gap / elite_pace later
	Run.kills = 5
	_frame(dir, 12.0)
	assert_int(_modded(em)).is_equal(2)
	var st := dir.row_wave_state(1)
	assert_float(float(st["next"])).is_equal_approx(12.0 + 40.0 / dir.elite_pace(), 0.001)


func test_a_ranged_every_draws_a_fresh_gap_inside_it() -> void:
	var d := _test_def("p84_rng", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var dir := _director(w, _tl({"burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pace": "waves", "every": [10, 20], "count": 1, "pattern": "single"}]}))
	dir._rng.seed = 21
	var gaps: Dictionary = {}
	var last := -1.0
	for s in range(0, 400):
		_frame(dir, float(s) * 0.5)
		var st := dir.row_wave_state(0)
		if not st.is_empty() and float(st["next"]) != last:
			last = float(st["next"])
			var g := last - Run.elapsed
			assert_float(g).is_between(10.0, 20.0)
			gaps[snappedf(g, 0.01)] = true
	assert_int(gaps.size()).is_greater(3)


# ---------------------------------------------------------------- lists, "roster", chance, jitter

func test_a_list_row_draws_by_enemy_weights_and_roster_from_the_mix_only() -> void:
	var a := _test_def("p84_la", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var b := _test_def("p84_lb", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var c := _test_def("p84_lc", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# a list at weights [1, 0]: only the first ever comes; the "roster" row draws from the mix row (a), never from the
	# once row of c beside it
	var dir := _director(w, _tl({"burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 0.0001]]},
		{"id": "r2", "t": 5, "enemy": [b.id, c.id], "enemy_weights": [1, 0], "weights": [[5, 1]], "pace": "waves", "every": 5, "count": 3, "pattern": "scatter", "respect_cap": false},
		{"id": "r3", "t": 5, "enemy": c.id, "weights": [[5, 1]], "pace": "once", "count": 1, "pattern": "scatter", "respect_cap": false},
		{"id": "r4", "t": 6, "enemy": "roster", "weights": [[6, 1]], "pace": "waves", "every": 5, "count": 4, "pattern": "scatter", "respect_cap": false}]}))
	for s in range(0, 40):
		_frame(dir, float(s))
	assert_int(em.alive_of(b.id)).is_greater(0)
	assert_int(em.alive_of(c.id)).is_equal(1)
	assert_int(em.alive_of(a.id)).is_greater_equal(4)


func test_chance_and_jitter_roll_once_a_run_and_plain_rows_take_no_dice() -> void:
	var d := _test_def("p84_ch", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var plain := _tl({"roster": [{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]]},
		{"id": "r2", "t": 10, "enemy": d.id, "weights": [[10, 1]], "pace": "waves", "every": 5, "count": 2}]})
	var dir := _director(w, plain)
	dir._rng.seed = 99
	var s0 := dir._rng.state
	dir._roll_rows()
	# an old map's rows (no chance, no t_jitter) take no dice and keep no roll
	assert_int(dir._rng.state).is_equal(s0)
	assert_bool(dir.row_roll(1).is_empty()).is_true()
	assert_bool(dir._row_new84(plain.roster[0], 0)).is_false()
	assert_bool(dir._row_new84(plain.roster[1], 1)).is_false()
	# chance 0 never comes; a jitter moves the row inside +- its size
	var tl := _tl({"burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 20, "enemy": d.id, "weights": [[20, 1]], "pace": "once", "count": 3, "pattern": "scatter", "respect_cap": false, "chance": 0.0},
		{"id": "r2", "t": 20, "enemy": d.id, "weights": [[20, 1]], "pace": "once", "count": 3, "pattern": "scatter", "respect_cap": false, "t_jitter": 5}]})
	var w2 := _world()
	var dir2 := _director(w2, tl)
	dir2._rng.seed = 4
	dir2._roll_rows()
	assert_bool(bool(dir2.row_roll(0)["skip"])).is_true()
	var shift := float(dir2.row_roll(1)["shift"])
	assert_float(shift).is_between(-5.0, 5.0)
	var came_at := -1.0
	for s in range(0, 120):
		_frame(dir2, float(s) * 0.25)
		if came_at < 0.0 and (w2["em"] as EnemyManager).alive_count() > 0:
			came_at = Run.elapsed
	assert_int((w2["em"] as EnemyManager).alive_count()).is_equal(3)
	assert_float(came_at).is_between(20.0 + shift - 0.01, 20.0 + shift + 0.26)


# ---------------------------------------------------------------- the density floor

func test_the_floor_draws_at_once_within_the_cap() -> void:
	var d := _test_def("p84_fl", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"floor_curve": [[0, 30]], "burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pattern": "scatter"}]}))
	Run.elapsed = 1.0
	dir._floor_fill()
	assert_int(em.alive_count()).is_equal(30)
	# a cap of 12 holds the floor back
	var w2 := _world()
	var dir2 := _director(w2, _tl({"cap_curve": [[0, 12]], "floor_curve": [[0, 30]], "burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]], "pattern": "scatter"}]}))
	Run.elapsed = 1.0
	dir2._floor_fill()
	assert_int((w2["em"] as EnemyManager).alive_count()).is_equal(12)
	# no floor: nothing
	var w3 := _world()
	var dir3 := _director(w3, _tl({"burst_min": 0, "burst_max": 0, "roster": [{"id": "r1", "t": 0, "enemy": d.id, "weights": [[0, 1]]}]}))
	Run.elapsed = 1.0
	dir3._floor_fill()
	assert_int((w3["em"] as EnemyManager).alive_count()).is_equal(0)


# ---------------------------------------------------------------- the shown difficulty

func test_the_shown_numbers_are_what_a_row_spawns_with() -> void:
	var d := _test_def("p84_hp", "skeleton", {"pack_size": 1, "cap_share": 1.0, "hp": 40.0, "damage": 6.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var row := {"id": "r1", "t": 200, "enemy": d.id, "weights": [[200, 1]], "pattern": "single", "stats": {"hp_mult": 1.5}}
	var tl := _tl({"hp_curve": {"mode": "points", "points": [[0, 1.0], [430, 2.0]]}, "creature_hp_mult": 1.3,
		"creature_damage_mult": 1.25, "level_hp_per_level": 0.05, "level_damage_per_level": 0.03, "burst_min": 1, "burst_max": 1,
		"roster": [row]})
	var dir := _director(w, tl)
	Run.level = 1
	Run.elapsed = 250.0
	dir._apply_mults()
	dir._spawn_burst()
	assert_int(em.alive_count()).is_equal(1)
	var i := -1
	for k in range(EnemyManager.MAX):
		if em.alive[k] != 0:
			i = k
	var lv := maxi(Run.card_level(), 1)
	var shown := WaveDirector.shown_numbers(tl, tl.roster[0], 250.0, lv)
	assert_float(float(shown["hp"])).is_equal_approx(em.max_hp[i], 0.01)
	# 40 x 1.5 x the curve at the row's start (1 + 200/430) x stage 1 x level x 1.3
	assert_float(float(shown["hp_time"])).is_equal_approx(1.0 + 200.0 / 430.0, 0.0001)
	assert_float(float(shown["atk"])).is_greater(0.0)
	assert_bool(WaveDirector.shown_numbers(tl, {"enemy": "roster"}, 10.0, 1).is_empty()).is_true()


# ---------------------------------------------------------------- Red Canyon migrated

func test_red_canyon_spawns_through_rows_only() -> void:
	var f := FileAccess.open(MAP_JSON, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var tl: Dictionary = data["timeline_data"]
	for ev in (tl["events"] as Array):
		assert_bool(["boss", "elite_boss"].has(str(ev.get("type", "")))).override_failure_message("event %s" % str(ev)).is_true()
	assert_bool(tl.has("waves") and not (tl["waves"] as Array).is_empty()).is_false()
	# the swarms, the special goblin and Elites every are rows now
	var once := 0
	var elite_rows := 0
	for r: Dictionary in (tl["roster"] as Array):
		if str(r.get("pace", "")) == "once":
			once += 1
			assert_bool(r.has("weights")).is_true()
		if str(r.get("elite", "")) != "":
			elite_rows += 1
			assert_str(str(r.get("enemy", ""))).is_equal("roster")
		var e = r.get("enemy", "")
		if e is String and e != "roster":
			assert_object(Registry.enemy(e)).override_failure_message(str(r.get("id", ""))).is_not_null()
	assert_int(once).is_greater_equal(5)
	assert_int(elite_rows).is_equal(1)


func test_a_swarm_row_comes_past_the_hard_cap_as_the_event_did() -> void:
	var d := _test_def("p84_hc", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# a hard cap of 10, already full: the swarm row (respect_hard_cap false) still brings its 8, the other row nothing
	var dir := _director(w, _tl({"hard_cap": 10, "burst_min": 0, "burst_max": 0, "roster": [
		{"id": "r1", "t": 5, "enemy": d.id, "weights": [[5, 1]], "pace": "once", "count": 8, "pattern": "scatter", "respect_cap": false, "respect_hard_cap": false},
		{"id": "r2", "t": 5, "enemy": d.id, "weights": [[5, 1]], "pace": "once", "count": 8, "pattern": "scatter", "respect_cap": false}]}))
	for k in range(10):
		em.spawn(d.id, Vector3(30, 0, float(k)))
	assert_int(em.alive_count()).is_equal(10)
	_frame(dir, 5.0)
	assert_int(em.alive_count()).is_equal(18)
	assert_int(int(dir.row_wave_state(1)["owed"])).is_equal(8)
