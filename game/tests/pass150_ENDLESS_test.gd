extends GdUnitTestSuite

## Pass 150, lane ENDLESS (Garry, 2026-11-14): a row's variations (tabs, each its % chance, rolled once a spawn decision,
## the timing shared), the Endless window (stage_list[k].endless_window: the boss-fight window's twin for Endless, with
## from_cycle / until_cycle and max_count_growth), the slow after a bite (map `bite_slow`), and the Ghost Pepper's trade
## in red wherever its words are shown.

const P110 := preload("res://tests/pass110_boss_window_test.gd")

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
	g.set_script(_script(P110.FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(P110.FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(P110.FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var mp := Node3D.new()
	mp.set_script(_script(P110.FLAT_MAP))
	g.add_child(mp)
	g.map = mp
	var pk := Node.new()
	pk.set_script(_script(P110.FAKE_PICKUPS))
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


## A one-stage timeline with `roster`, the stage's `boss_fight` and `endless_window` blocks (none when {}).
func _tl(roster: Array, boss_fight: Dictionary, endless_window: Dictionary, extra: Dictionary = {}) -> WaveTimeline:
	var entry := {"id": "s1", "name": "One", "length": END, "boss": "tumbleweed_king"}
	if not boss_fight.is_empty():
		entry["boss_fight"] = boss_fight
	if not endless_window.is_empty():
		entry["endless_window"] = endless_window
	var base := {"stage_length": END, "stages": 1, "stage_list": [entry], "cap_start": 100, "cap_per_minute": 0,
		"cap_max": 300, "hard_cap": 300, "spawn_interval": 0.5, "burst_min": 5, "burst_max": 5, "roster": roster,
		"events": [], "waves": [], "colour_after_kills": 0, "boss_cap_frac": 0.5, "boss_hp_scaling": {"enabled": false}}
	for k in extra.keys():
		base[k] = extra[k]
	return JsonContent.timeline_from_dict(base)


## A director on `tl`, started on its stage at second 0 (the normal phase).
func _start(w: Dictionary, tl: WaveTimeline) -> WaveDirector:
	var m: MapDef = _map_keep.duplicate()
	m.timeline = tl
	Run.map = m
	Run.start_stage(0)
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	w["g"].director = d
	w["g"].add_child(d)
	d.start(m)
	return d


## The same director taken straight into Endless (the clock at the stage's end, the crowd cleared).
func _endless(w: Dictionary, tl: WaveTimeline) -> WaveDirector:
	var d := _start(w, tl)
	Run.elapsed = END
	d.phase = WaveDirector.Phase.PORTAL
	(w["em"] as EnemyManager).kill_all(false)
	d.start_endless()
	return d


func _play(d: WaveDirector, secs: float, step: float = 0.1) -> void:
	for _k in range(int(round(secs / step))):
		d._process(step)


# ---------------------------------------------------------------- the variations' rule

func test_the_tabs_shares_sum_to_100_and_the_variations_carry_their_own_keys() -> void:
	var r := {"id": "r1", "t": 10, "until": 50, "enemy": "skeleton", "pace": "waves", "every": 5, "count": 4,
		"weights": [[10, 2.0]], "variant": "SK-F", "stats": {"hp_mult": 0.5},
		"variations": [{"percent": 30, "enemy": "goblin", "count": 9, "t": 99, "every": 1, "stats": {"hp_mult": 2.0}},
			{"percent": 20, "enemy": "imp"}, "not a tab"]}
	assert_bool(WaveTimeline.row_has_variations(r)).is_true()
	assert_bool(WaveTimeline.row_has_variations({"enemy": "skeleton"})).is_false()
	assert_int(WaveTimeline.row_variations(r).size()).is_equal(2)
	var ps := WaveTimeline.variation_percents(r)
	assert_float(ps[0]).is_equal_approx(50.0, 0.001)
	assert_float(ps[1]).is_equal_approx(30.0, 0.001)
	assert_float(ps[2]).is_equal_approx(20.0, 0.001)
	# the variations first, the original last
	assert_int(WaveTimeline.variation_pick(r, 0.0)).is_equal(1)
	assert_int(WaveTimeline.variation_pick(r, 0.29)).is_equal(1)
	assert_int(WaveTimeline.variation_pick(r, 0.31)).is_equal(2)
	assert_int(WaveTimeline.variation_pick(r, 0.49)).is_equal(2)
	assert_int(WaveTimeline.variation_pick(r, 0.51)).is_equal(0)
	assert_int(WaveTimeline.variation_pick(r, 1.0)).is_equal(0)
	# a variation plays its own keys, the original's shared ones (when the row comes, never its own t or every), and a
	# key it lacks it lacks (no look, no stats on the second)
	var v1 := WaveTimeline.variation_row(r, 1)
	assert_str(str(v1["enemy"])).is_equal("goblin")
	assert_int(int(v1["count"])).is_equal(9)
	assert_float(float(v1["t"])).is_equal(10.0)
	assert_float(float(v1["until"])).is_equal(50.0)
	assert_float(float(v1["every"])).is_equal(5.0)
	assert_str(str(v1["pace"])).is_equal("waves")
	assert_str(str(v1["id"])).is_equal("r1")
	assert_bool(v1.has("percent") or v1.has("variations")).is_false()
	assert_float(float(v1["stats"]["hp_mult"])).is_equal(2.0)
	var v2 := WaveTimeline.variation_row(r, 2)
	assert_bool(v2.has("variant") or v2.has("stats") or v2.has("count")).is_false()
	# the row itself for tab 0 (and a tab that is not there)
	assert_bool(is_same(WaveTimeline.variation_row(r, 0), r)).is_true()
	assert_bool(is_same(WaveTimeline.variation_row(r, 7), r)).is_true()
	# past 100 the variations are scaled to 100 and the original never comes
	var over := {"enemy": "skeleton", "variations": [{"percent": 150, "enemy": "goblin"}, {"percent": 50, "enemy": "imp"}]}
	var po := WaveTimeline.variation_percents(over)
	assert_float(po[0]).is_equal(0.0)
	assert_float(po[1]).is_equal_approx(75.0, 0.001)
	assert_float(po[2]).is_equal_approx(25.0, 0.001)
	assert_int(WaveTimeline.variation_pick(over, 0.999)).is_equal(2)


func test_a_continuous_row_brings_its_variation_by_its_share() -> void:
	var a := _test_def("p150_a", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var b := _test_def("p150_b", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# 100%: the original never comes, its fixed numbers kept apart from the variation's
	var tl := _tl([{"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter",
		"variations": [{"percent": 100, "enemy": b.id, "pattern": "scatter"}]}], {}, {})
	var d := _start(w, tl)
	_play(d, 3.0)
	assert_int(em.alive_of(b.id)).is_greater(0)
	assert_int(em.alive_of(a.id)).is_equal(0)
	assert_bool(d.source_state("row:r1#0~v1").is_empty()).is_false()
	# 0%: only the original
	em.kill_all(false)
	var tl0 := _tl([{"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter",
		"variations": [{"percent": 0, "enemy": b.id}]}], {}, {})
	var w2 := _world()
	var d2 := _start(w2, tl0)
	_play(d2, 3.0)
	assert_int((w2["em"] as EnemyManager).alive_of(a.id)).is_greater(0)
	assert_int((w2["em"] as EnemyManager).alive_of(b.id)).is_equal(0)


func test_a_waves_row_rolls_once_for_the_whole_wave() -> void:
	var a := _test_def("p150_wa", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var b := _test_def("p150_wb", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl := _tl([{"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 1]], "pace": "waves", "every": 4, "count": 6,
		"pattern": "scatter", "variations": [{"percent": 50, "enemy": b.id, "count": 3, "pattern": "scatter"}]}], {}, {})
	var d := _start(w, tl)
	# a wave is all of one tab: six of A or three of B, never a mix (each 4 s slice holds one wave, at its middle)
	_play(d, 2.0)
	for _k in range(6):
		em.kill_all(false)
		_play(d, 4.0)
		var na := em.alive_of(a.id)
		var nb := em.alive_of(b.id)
		assert_bool((na == 6 and nb == 0) or (na == 0 and nb == 3)).override_failure_message("A %d B %d" % [na, nb]).is_true()


func test_a_boss_fight_row_brings_its_variation() -> void:
	var a := _test_def("p150_ba", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var b := _test_def("p150_bb", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl := _tl([], {"length": 60, "max_count": 30, "roster": [{"id": "bf1", "t": 0, "enemy": a.id, "weights": [[0, 5]],
		"pattern": "scatter", "variations": [{"percent": 100, "enemy": b.id, "pattern": "scatter"}]}]}, {})
	var d := _start(w, tl)
	Run.elapsed = END
	em.kill_all(false)
	d._start_boss("tumbleweed_king")
	_play(d, 3.0)
	assert_int(em.alive_of(b.id)).is_greater(0)
	assert_int(em.alive_of(a.id)).is_equal(0)


# ---------------------------------------------------------------- the Endless window

func test_the_endless_window_plays_instead_of_the_old_endless() -> void:
	var a := _test_def("p150_ea", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var b := _test_def("p150_eb", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var c := _test_def("p150_ec", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# the stage's own row (the old Endless would draw it) and the window's: A all the time, B once from cycle 2, C once
	# in cycle 1 only; Max count 20, +10 a cycle
	var tl := _tl([{"id": "r1", "t": 0, "enemy": c.id, "weights": [[0, 5]], "pattern": "scatter"}], {},
		{"length": 30, "max_count": 20, "max_count_growth": 10, "roster": [
			{"id": "e1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter"},
			{"id": "e2", "t": 5, "enemy": b.id, "weights": [[5, 1]], "pace": "once", "count": 4, "pattern": "scatter",
				"respect_cap": false, "from_cycle": 2},
			{"id": "e3", "t": 5, "enemy": c.id, "weights": [[5, 1]], "pace": "once", "count": 3, "pattern": "scatter",
				"respect_cap": false, "until_cycle": 1}]})
	assert_bool(tl.has_endless_window(0)).is_true()
	assert_float(tl.endless_window_length(0)).is_equal(30.0)
	assert_int(tl.endless_window_max_count(0)).is_equal(20)
	var d := _endless(w, tl)
	assert_bool(Run.endless).is_true()
	assert_bool(d.endless_window.active).is_true()
	# the old pool is not drawn
	assert_array(d._endless_pool).is_empty()
	_play(d, 10.0)
	assert_int(em.alive_of(a.id)).is_greater(0)
	assert_int(em.alive_of(a.id)).is_less_equal(20)
	assert_int(d.current_cap()).is_equal(20)
	# cycle 1: C's once, no B
	assert_int(em.alive_of(c.id)).is_equal(3)
	assert_int(em.alive_of(b.id)).is_equal(0)
	# cycle 2 (from 30 s): Max count 30, B's once, no more C
	em.kill_all(false)
	_play(d, 27.0)
	assert_int(d.endless_window.cycle).is_equal(1)
	assert_int(d.current_cap()).is_equal(30)
	assert_int(em.alive_of(b.id)).is_equal(4)
	assert_int(em.alive_of(c.id)).is_equal(0)
	# the growth caps at the hard cap
	assert_int(d.endless_window.max_count_at(1000)).is_equal(300)


func test_the_endless_window_numbers_grow_with_endless() -> void:
	var a := _test_def("p150_ga", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var tl := _tl([], {}, {"length": 60, "max_count": 20, "roster": [
		{"id": "e1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter"}]},
		{"endless": {"every": 10, "hp": 1.0, "hp_growth": 0.5, "atk": 1.0, "atk_growth": 0.0}})
	var d := _endless(w, tl)
	_play(d, 1.0)
	var s1 := d.source_state("endless0:e1#0@w1")
	assert_bool(s1.is_empty()).is_false()
	# into wave 3 with room made, so a spawn fixes wave 3's numbers
	_play(d, 20.0)
	(w["em"] as EnemyManager).kill_all(false)
	_play(d, 1.0)
	assert_int(Run.endless_wave()).is_equal(3)
	var s3 := d.source_state("endless0:e1#0@w3")
	assert_bool(s3.is_empty()).is_false()
	# two growth steps of +50%
	assert_float(float(s3["hp_time"]) / float(s1["hp_time"])).is_equal_approx(2.25, 0.01)


func test_a_switched_off_window_plays_the_old_endless() -> void:
	var a := _test_def("p150_oa", "skeleton", {"pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var tl := _tl([{"id": "r1", "t": 0, "enemy": a.id, "weights": [[0, 5]], "pattern": "scatter"}], {},
		{"enabled": false, "roster": [{"id": "e1", "t": 0, "enemy": "imp", "weights": [[0, 5]]}]})
	assert_bool(tl.has_endless_window(0)).is_false()
	var d := _endless(w, tl)
	assert_bool(d.endless_window.active).is_false()
	assert_array(d._endless_pool).is_not_empty()


# ---------------------------------------------------------------- the slow after a bite

func test_a_bite_slows_the_biter_but_leaves_a_stronger_slow_alone() -> void:
	var a := _test_def("p150_bite", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl := _tl([], {}, {})
	var d := _start(w, tl)
	# the director hands the map's numbers over (the default 25% for 1 s)
	assert_float(em.bite_slow_frac).is_equal_approx(0.25, 0.0001)
	assert_float(em.bite_slow_seconds).is_equal_approx(1.0, 0.0001)
	d.running = false
	var hero: Node3D = w["hero"]
	var i := em.spawn(a.id, hero.global_position + Vector3(0.3, 0, 0))
	assert_int(i).is_greater_equal(0)
	em.rise_t[i] = 1.0
	em._tick_bite(i, em.type_idx[i], hero.global_position)
	assert_float(em.slow_t[i]).is_equal_approx(1.0, 0.0001)
	assert_float(em.slow_f[i]).is_equal_approx(0.25, 0.0001)
	assert_bool(em._bite_slowed.has(i)).is_true()
	# a pin stays a pin, its seconds unchanged
	em.slow(i, 1.0, 0.3, false)
	assert_bool(em._bite_slowed.has(i)).is_false()
	em._tick_bite(i, em.type_idx[i], hero.global_position)
	assert_float(em.slow_f[i]).is_equal(1.0)
	assert_float(em.slow_t[i]).is_equal_approx(1.0, 0.0001)
	# a weaker slow becomes the bite's for the longer of the two times
	em.slow_t[i] = 0.0
	em.slow(i, 0.1, 3.0, false)
	em.bite_slow(i)
	assert_float(em.slow_f[i]).is_equal_approx(0.25, 0.0001)
	assert_float(em.slow_t[i]).is_equal_approx(3.0, 0.0001)
	# a charging creature and a boss are never slowed by their bite
	em.slow_t[i] = 0.0
	em.slow_f[i] = 0.0
	em.state[i] = EnemyManager.STATE_CHARGE
	em._tick_bite(i, em.type_idx[i], hero.global_position)
	assert_float(em.slow_t[i]).is_equal(0.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.boss_index = i
	em._tick_bite(i, em.type_idx[i], hero.global_position)
	assert_float(em.slow_t[i]).is_equal(0.0)
	em.boss_index = -1
	# frac 0 is off
	em.bite_slow_frac = 0.0
	em._tick_bite(i, em.type_idx[i], hero.global_position)
	assert_float(em.slow_t[i]).is_equal(0.0)


func test_the_bite_slow_reads_the_map() -> void:
	var tl := _tl([], {}, {}, {"bite_slow": {"frac": 0.4}})
	assert_float(tl.bite_slow_value("frac")).is_equal_approx(0.4, 0.0001)
	assert_float(tl.bite_slow_value("seconds")).is_equal_approx(1.0, 0.0001)
	assert_float(WaveTimeline.new().bite_slow_value("frac")).is_equal_approx(0.25, 0.0001)


# ---------------------------------------------------------------- the Ghost Pepper's trade in red

func test_an_items_trade_is_red_on_a_fresh_card() -> void:
	# as on a fresh start: no screen has described the max HP price yet
	TextGen._bad.clear()
	TextGen._trades_noted = false
	var beer: PassiveDef = Registry.passive("beer")
	var t := WItem.effect({"def": beer, "level_from": 0, "level_to": 1})
	assert_str(t).contains("−5%")
	assert_array(Array(TextGen.bad_numbers_in(t))).contains(["−5%"])
	# the good number stays white
	assert_bool(TextGen.bad_numbers_in(t).has("+15%")).is_false()
	# every item's trade, as the pause screen and the Collection put it too
	TextGen._bad.clear()
	TextGen._trades_noted = false
	assert_array(Array(TextGen.bad_numbers_in("Trade: cooldowns 8% longer."))).contains(["8%"])


# ---------------------------------------------------------------- Red Canyon's four Endless windows

func test_every_stage_of_red_canyon_has_an_endless_window_with_known_creatures() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for s in range(tl.stage_count()):
		assert_bool(tl.has_endless_window(s)).override_failure_message("stage %d" % s).is_true()
		for r: Dictionary in tl.endless_window_rows(s):
			for k in range(WaveTimeline.variation_percents(r).size()):
				var v := WaveTimeline.variation_row(r, k)
				var e = v.get("enemy", "")
				var ids: Array = e if e is Array else [e]
				for id in ids:
					if str(id) == WaveTimeline.ROW_ENEMY_ROSTER:
						continue
					assert_object(Registry.enemy(str(id))).override_failure_message("%s tab %d: %s" % [r.get("id"), k, id]).is_not_null()
				var vr := str(v.get("variant", ""))
				if vr != "" and ids.size() == 1:
					var def: EnemyDef = Registry.enemy(str(ids[0]))
					assert_bool(def.variants.has(vr)).override_failure_message("%s tab %d: %s has no look %s" % [r.get("id"), k, ids[0], vr]).is_true()
