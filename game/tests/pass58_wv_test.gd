extends GdUnitTestSuite

## Pass 58, lane WV (Garry, 2026-10-07: "While I want the HP of enemies to increase over time, I don't actually want it to
## change for the same 'wave' of enemies on the fly, because then it feels weird for the Player that shooting the same
## enemy with the same weapon suddenly doesn't kill it even though it was killing them just a 20 seconds ago"; "Add option
## to change enemy wave enemy size ... editable as a kind of a range (between 3-5 for example)"; "Add option to change
## enemy colour (should be a kind of a range) ... a version that kind of colours all the enemies that come out of that
## wave"). R1: a roster row's and a wave's HP and damage are fixed from its start (the curves at its t0, an overridden
## number taking no curve, the hero's level at its first spawn), an event's from the moment it fires, the stage multiplier
## stays live, every later hit of a creature reads its own factors, and a creature spawned by hand, a boss and an Elite
## play as before. R2: `stats.size` as [min, max] rolls each creature's size (no variance jitter on top), its radius
## following, one type per row. R3: `stats.tint` rolls a hue in its range (through red when h1 < h0) at strength
## `amount`; a special's own tint, an elite modifier's colour and the status tints still win. The fix round (the review):
## an event of a creature a row or wave brings joins that row's numbers, the portal wave plays the row it drew, endless
## fixes the rows afresh each wave, rows that share an id keep their own, a split child keeps its parent's stage, size and
## hue, a size range's special stays in the range, wide bodies push each other apart past the 3 x 3 cells, and the ring and
## in_front spots keep out of a lake the size of Red Canyon's oasis.

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
var missiles: Array = []
var blasts: Array = []
var director = null
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
func enemy_missile(_i, _at, _speed, _turn, damage, _area, _soh = 0.0, _info = {}, _ms = {}) -> void:
	missiles.append(damage)
func elite_explosion(_at, _r, damage, _delay = 0.0, _kb = 0.0, _ff = 0.2, _info = {}) -> void:
	blasts.append(damage)
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
var taken: Array = []
func take_damage(a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	taken.append(a)
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

const FAKE_PICKUPS := """extends Node
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(_at, _boss = false) -> void:
	pass
func spawn(_k, _at, _v = 0.0) -> int:
	return -1
"""

const TMP_TRES := "user://pass58_wv_map.tres"

## Curves that move a lot: HP x1 at 0 s to x3 at 600 s (1 + t / 300), damage x1 to x2 (1 + t / 600), the creatures 1.3
## times tougher and 1.25 times harder, +5% HP and +3% damage a hero level above 1 (Red Canyon's level factors).
const CURVES := {"hp_curve": {"mode": "points", "points": [[0, 1.0], [600, 3.0]]},
	"damage_curve": {"mode": "points", "points": [[0, 1.0], [600, 2.0]]},
	"creature_hp_mult": 1.3, "creature_damage_mult": 1.25, "level_hp_per_level": 0.05, "level_damage_per_level": 0.03}

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.arena = false
	Run.endless = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.level = 1


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at` with a plain map (arena radius 66 m) and the real crowd.
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.set("player", hero)
	var mb := MapBase.new()
	g.add_child(mb)
	g.set("map", mb)
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.set("pickups", pk)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "map": mb}


## A timeline from `extra` over quiet test defaults: a flat cap of 100, no roster, no events, colour from the start.
func _tl(extra: Dictionary = {}) -> WaveTimeline:
	var base := {"stage_length": 430, "stages": 3, "cap_start": 100, "cap_per_minute": 0, "cap_max": 300, "hard_cap": 300,
		"spawn_interval": 0.5, "roster": [], "events": [], "waves": [], "colour_after_kills": 0, "hell_cap": [0.5, 0.5, 0.5]}
	for k in extra.keys():
		base[k] = extra[k]
	return JsonContent.timeline_from_dict(base.duplicate(true))


## The curves above with `extra` on top.
func _curves(extra: Dictionary = {}) -> WaveTimeline:
	var d: Dictionary = CURVES.duplicate(true)
	for k in extra.keys():
		d[k] = extra[k]
	return _tl(d)


## A director on `tl` in the world `w`, driven by hand (not in the tree: its _process would run the clock).
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


func _alive_indices(em: EnemyManager) -> Array:
	var out: Array = []
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1 and em.state[i] != EnemyManager.STATE_DYING:
			out.append(i)
	return out


## The creatures alive now that were not in `before`.
func _new_since(em: EnemyManager, before: Array) -> Array:
	var out: Array = []
	for i in _alive_indices(em):
		if not before.has(i):
			out.append(i)
	return out


## One creature of roster row `row` through the roster's burst at `t` seconds of the run clock (the director's live
## numbers set for that moment first, as its tick does): its index.
func _from_row(dir: WaveDirector, em: EnemyManager, row: Dictionary, t: float) -> int:
	Run.elapsed = t
	dir._apply_mults()
	var before := _alive_indices(em)
	var def: EnemyDef = WaveDirector._row_def(row)
	dir._burst_from([row], maxf(def.cap_share, 0.05), 300)
	var got := _new_since(em, before)
	assert_int(got.size()).is_equal(1)
	return int(got[0]) if not got.is_empty() else -1


func _row(id: String, t: float, enemy: String, stats: Dictionary = {}) -> Dictionary:
	var r := {"id": id, "t": t, "enemy": enemy, "weight": 1, "pack": 1}
	if not stats.is_empty():
		r["stats"] = stats
	return r


# ---------------------------------------------------------------- R1: a row's numbers fixed from its start

func test_two_creatures_of_one_row_a_minute_apart_are_equal() -> void:
	var d := _test_def("p58_a", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	var row := _row("r1", 60.0, d.id)
	var a := _from_row(dir, em, row, 100.0)
	var live_then := em.hp_time_mult
	var b := _from_row(dir, em, row, 160.0)
	# the live curve moved on between the two (x1.33 -> x1.53) ...
	assert_float(em.hp_time_mult).is_greater(live_then + 0.15)
	# ... the row did not: both stand on the curve at the row's start (x1.2 at 60 s), times the creatures' x1.3
	assert_float(em.max_hp[a]).is_equal_approx(10.0 * 1.2 * 1.3, 0.0001)
	assert_float(em.max_hp[b]).is_equal_approx(em.max_hp[a], 0.0001)
	# and the damage the same way: x1.1 at 60 s, x1.25 for every creature
	assert_float(em.dmg[a]).is_equal_approx(4.0 * 1.1 * 1.25, 0.0001)
	assert_float(em.dmg[b]).is_equal_approx(em.dmg[a], 0.0001)
	assert_int(em.fixed[a]).is_equal(1)
	assert_int(em.fixed[b]).is_equal(1)
	var s := dir.source_state("row:r1")
	assert_float(float(s["t0"])).is_equal(60.0)
	assert_float(float(s["hp_time"])).is_equal_approx(1.2, 0.0001)
	assert_float(float(s["dmg_time"])).is_equal_approx(1.1, 0.0001)


func test_a_row_that_starts_later_carries_the_curve_at_its_own_start() -> void:
	var d := _test_def("p58_b", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	# a row from 300 s first spawning at 400 s: the curve at 300 (x2.0), not at 400 (x2.33)
	var c := _from_row(dir, em, _row("r2", 300.0, d.id), 400.0)
	assert_float(em.max_hp[c]).is_equal_approx(10.0 * 2.0 * 1.3, 0.0001)
	assert_float(em.dmg[c]).is_equal_approx(4.0 * 1.5 * 1.25, 0.0001)
	# a row from 0 s spawning at the same moment: the curve at 0 (x1)
	var z := _from_row(dir, em, _row("r0", 0.0, d.id), 400.0)
	assert_float(em.max_hp[z]).is_equal_approx(10.0 * 1.3, 0.0001)
	# a row with no `t` starts at 0
	var n := _from_row(dir, em, {"id": "rn", "enemy": d.id, "weight": 1, "pack": 1}, 400.0)
	assert_float(em.max_hp[n]).is_equal_approx(10.0 * 1.3, 0.0001)


func test_an_overridden_number_takes_no_curve() -> void:
	var d := _test_def("p58_c", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	# Garry: "the multiplier will inform what the HP should be for enemy rows whose stats weren't overridden"
	var c := _from_row(dir, em, _row("r3", 300.0, d.id, {"hp": 50, "damage": 9}), 400.0)
	assert_float(em.max_hp[c]).is_equal_approx(50.0 * 1.3, 0.0001)
	assert_float(em.dmg[c]).is_equal_approx(9.0 * 1.25, 0.0001)
	# a multiplier on an override: still no curve
	var m := _from_row(dir, em, _row("r4", 300.0, d.id, {"hp": 50, "hp_mult": 2.0}), 400.0)
	assert_float(em.max_hp[m]).is_equal_approx(100.0 * 1.3, 0.0001)
	# a multiplier alone keeps the curve at the row's start
	var k := _from_row(dir, em, _row("r5", 300.0, d.id, {"hp_mult": 2.0, "damage_mult": 3.0}), 400.0)
	assert_float(em.max_hp[k]).is_equal_approx(10.0 * 2.0 * 2.0 * 1.3, 0.0001)
	assert_float(em.dmg[k]).is_equal_approx(4.0 * 3.0 * 1.5 * 1.25, 0.0001)
	# overriding the damage leaves the HP on the curve, and the other way round
	var o := _from_row(dir, em, _row("r6", 300.0, d.id, {"damage": 9}), 400.0)
	assert_float(em.max_hp[o]).is_equal_approx(10.0 * 2.0 * 1.3, 0.0001)
	assert_float(em.dmg[o]).is_equal_approx(9.0 * 1.25, 0.0001)
	# the director's rule itself
	var f := dir.fixed_numbers(300.0, {"hp": 5})
	assert_float(float(f["hp_time"])).is_equal(1.0)
	assert_float(float(f["dmg_time"])).is_equal_approx(1.5, 0.0001)
	f = dir.fixed_numbers(300.0, {"damage": 5})
	assert_float(float(f["hp_time"])).is_equal_approx(2.0, 0.0001)
	assert_float(float(f["dmg_time"])).is_equal(1.0)


func test_the_heros_level_at_the_rows_first_spawn_is_kept() -> void:
	var d := _test_def("p58_d", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	var row := _row("r1", 60.0, d.id)
	Run.level = 5
	var a := _from_row(dir, em, row, 100.0)
	Run.level = 15
	var b := _from_row(dir, em, row, 130.0)
	# level 5 when the row first came: +20% HP and +12% damage for every one of it
	assert_float(em.max_hp[a]).is_equal_approx(10.0 * 1.2 * 1.2 * 1.3, 0.0001)
	assert_float(em.max_hp[b]).is_equal_approx(em.max_hp[a], 0.0001)
	assert_float(em.dmg[b]).is_equal_approx(4.0 * 1.1 * 1.12 * 1.25, 0.0001)
	# while the live factor is the level's now
	assert_float(em.level_hp_mult).is_equal_approx(1.7, 0.0001)
	# a row that first spawns now takes level 15's
	var c := _from_row(dir, em, _row("r9", 60.0, d.id), 130.0)
	assert_float(em.max_hp[c]).is_equal_approx(10.0 * 1.2 * 1.7 * 1.3, 0.0001)
	assert_float(em.dmg[c]).is_equal_approx(4.0 * 1.1 * 1.42 * 1.25, 0.0001)


func test_the_stage_multiplier_still_applies_to_each_new_creature() -> void:
	var d := _test_def("p58_e", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	var row := _row("r1", 60.0, d.id)
	var a := _from_row(dir, em, row, 100.0)
	var hp_a: float = em.max_hp[a]
	# the next stage (Red Canyon's x2.2): announced, and the row's next creature carries it
	Run.stage = 1
	var b := _from_row(dir, em, row, 130.0)
	assert_float(em.stage_mult).is_equal_approx(2.2, 0.0001)
	assert_float(em.max_hp[b]).is_equal_approx(hp_a * 2.2, 0.0001)
	assert_float(em.dmg[b]).is_equal_approx(em.dmg[a] * 2.2, 0.0001)
	# the one already on the sand keeps its own, for its health and its hits
	assert_float(em.max_hp[a]).is_equal_approx(hp_a, 0.0001)
	assert_float(em.stage_of(a)).is_equal_approx(1.0, 0.0001)
	assert_float(em.stage_of(b)).is_equal_approx(2.2, 0.0001)


func test_a_creatures_later_hits_keep_its_own_factor() -> void:
	var r := _test_def("p58_rk", "rocketeer", {"pack_size": 1, "cap_share": 1.0})
	var t := _test_def("p58_toad", "horned_toad", {"pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var dir := _director(w, _curves())
	# both from rows at 60 s: the damage curve is x1.1 there
	var i := _from_row(dir, em, _row("rk", 60.0, r.id), 60.0)
	var j := _from_row(dir, em, _row("td", 60.0, t.id), 60.0)
	# the clock runs on: the live curve doubles
	Run.elapsed = 600.0
	dir._apply_mults()
	assert_float(em.hostile_mult()).is_equal_approx(1.25 * 2.0, 0.0001)
	assert_float(em.host_of(i)).is_equal_approx(1.25 * 1.1, 0.0001)
	var md: float = float((r.artillery["missile"] as Dictionary)["damage"])
	em._fire_artillery(i, r, Vector3.ZERO)
	assert_float(float(g.missiles[0])).is_equal_approx(md * 1.25 * 1.1, 0.0001)
	# the toad's death burst too
	em._die(j, "")
	assert_float(float(g.blasts[0])).is_equal_approx(float(t.death_burst["damage"]) * 1.25 * 1.1, 0.0001)
	# a rocketeer spawned by hand plays the live numbers, as before
	var h := em.spawn(r.id, Vector3(-8, 0, 0))
	assert_int(em.fixed[h]).is_equal(0)
	assert_float(em.host_of(h)).is_equal_approx(em.hostile_mult(), 0.0001)
	em._fire_artillery(h, r, Vector3.ZERO)
	assert_float(float(g.missiles[1])).is_equal_approx(md * 1.25 * 2.0, 0.0001)


func test_a_wave_takes_its_own_start_and_keeps_it() -> void:
	var d := _test_def("p58_f", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves({"waves": [{"id": "wv", "t": 120, "count": 0, "burst": 2, "every": 30, "enemy": d.id, "pattern": "scatter"}]}))
	Run.elapsed = 200.0
	dir._apply_mults()
	dir._tick_waves()
	Run.elapsed = 260.0
	dir._apply_mults()
	dir._tick_waves()
	var idx := _alive_indices(em)
	assert_int(idx.size()).is_equal(10)
	# every creature of it on the curve at the wave's 120 s (x1.4), the bursts at 200 and 260 s alike
	for i in idx:
		assert_float(em.max_hp[i]).is_equal_approx(10.0 * 1.4 * 1.3, 0.0001)
	assert_float(float(dir.source_state("wave#0")["t0"])).is_equal(120.0)


func test_an_event_takes_the_moment_it_fires() -> void:
	var d := _test_def("p58_g", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var r := _test_def("p58_g2", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 2, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# the roster brings another creature, so the swarms below join no row (the fix round's rule)
	var dir := _director(w, _curves({"roster": [{"t": 0, "until": 1e9, "enemy": r.id, "weight": 1, "pack": 2}], "portal_wave": {"count": 4}}))
	var row: Dictionary = dir.timeline.roster[0]
	# the row's first creature at 100 s, the hero at level 1: the row fixes the curve at its 0 s (x1) and level 1
	var streamed := _from_row(dir, em, row, 100.0)
	assert_float(em.max_hp[streamed]).is_equal_approx(10.0 * 1.3, 0.0001)
	Run.elapsed = 300.0
	dir._apply_mults()
	var before := _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 3, "pattern": "scatter"})
	var first := _new_since(em, before)
	assert_int(first.size()).is_equal(3)
	for i in first:
		assert_float(em.max_hp[i]).is_equal_approx(10.0 * 2.0 * 1.3, 0.0001)
	# the same swarm later: its own moment (x2.5 at 450 s)
	Run.elapsed = 450.0
	dir._apply_mults()
	before = _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 3, "pattern": "scatter"})
	for i in _new_since(em, before):
		assert_float(em.max_hp[i]).is_equal_approx(10.0 * 2.5 * 1.3, 0.0001)
	# an event that sets the HP takes no curve
	before = _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 2, "pattern": "scatter", "stats": {"hp": 70}})
	for i in _new_since(em, before):
		assert_float(em.max_hp[i]).is_equal_approx(70.0 * 1.3, 0.0001)
	# the portal wave brings the creatures of the rows open at the stage's end on their row's own numbers (the fix round:
	# beside the ones the hero was just shooting), whatever the clock and the hero's level now
	Run.elapsed = 430.0
	Run.level = 9
	dir._apply_mults()
	before = _alive_indices(em)
	assert_int(dir.spawn_portal_wave()).is_equal(4)
	for i in _new_since(em, before):
		assert_float(em.max_hp[i]).is_equal_approx(em.max_hp[streamed], 0.0001)
		assert_float(em.dmg[i]).is_equal_approx(em.dmg[streamed], 0.0001)


func test_a_boss_and_an_elite_keep_their_own_rules_and_a_hand_spawn_plays_live() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	Run.elapsed = 300.0
	dir._apply_mults()
	var src := dir.fixed_numbers(60.0)
	# an Elite by its kind: no curve on its health, as before, whatever the source says
	var scorp: EnemyDef = Registry.enemy("dune_scorpion")
	var e := em.spawn("dune_scorpion", Vector3(6, 0, 0), null, 1.0, 1.0, "", {}, src)
	assert_int(em.fixed[e]).is_equal(0)
	assert_float(em.max_hp[e]).is_equal_approx(scorp.hp * 1.3, 0.01)
	assert_float(em.host_of(e)).is_equal_approx(em.hostile_mult(), 0.0001)
	# a boss: its own health
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var b := em.spawn_boss("tumbleweed_king", Vector3(-6, 0, 0), "", {}, src)
	assert_int(em.fixed[b]).is_equal(0)
	assert_float(em.max_hp[b]).is_equal_approx(king.hp, 0.01)
	em.kill_all(false)
	# a creature spawned by hand: the live curve and level, as before
	var d := _test_def("p58_h", "skeleton", {"hp": 10.0, "damage": 4.0})
	var h := em.spawn(d.id, Vector3(0, 0, 8))
	assert_int(em.fixed[h]).is_equal(0)
	assert_float(em.max_hp[h]).is_equal_approx(10.0 * 2.0 * 1.3, 0.0001)
	assert_dict(em.src_of(h)).is_empty()
	# its hits follow the live numbers as they move
	em.damage_time_mult = 3.0
	assert_float(em.host_of(h)).is_equal_approx(1.25 * 3.0, 0.0001)


func test_split_children_and_the_brood_carry_fixed_numbers() -> void:
	var d := _test_def("p58_s", "skeleton", {"hp": 10.0, "damage": 4.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	Run.elapsed = 300.0
	dir._apply_mults()
	var src := dir.fixed_numbers(60.0)
	var splitter: EliteModDef = Registry.elites.get("splitter")
	assert_object(splitter).is_not_null()
	var p := em.spawn(d.id, Vector3(5, 0, 5), splitter, 1.0, 1.0, "", {}, src)
	assert_dict(em.src_of(p)).contains_keys(["hp_time", "dmg_time", "lv_hp", "lv_dmg"])
	var before := _alive_indices(em)
	em._die(p, "")
	var kids := _new_since(em, before)
	assert_int(kids.size()).is_equal(int(splitter.params.get("split_count", 3)))
	for k in kids:
		assert_int(em.fixed[k]).is_equal(1)
		assert_float(em.f_hpt[k]).is_equal_approx(1.2, 0.0001)
		# half the health, on the parent's curve value (x1.2 at 60 s), not the live x2
		assert_float(em.max_hp[k]).is_equal_approx(10.0 * 1.2 * 0.5 * 1.3, 0.0001)
	# a boss's brood: the moment's numbers
	var now := em.now_src()
	assert_float(float(now["hp_time"])).is_equal_approx(em.hp_time_mult, 0.0001)
	assert_float(float(now["dmg_time"])).is_equal_approx(em.damage_time_mult, 0.0001)
	before = _alive_indices(em)
	em.spawn_ring(d.id, 4, Vector3.ZERO, 5.0, "", {}, now)
	for k in _new_since(em, before):
		assert_int(em.fixed[k]).is_equal(1)
		assert_float(em.max_hp[k]).is_equal_approx(10.0 * 2.0 * 1.3, 0.0001)


func test_a_row_keeps_its_numbers_once_made_and_a_new_run_forgets_them() -> void:
	var w := _world()
	var dir := _director(w, _curves())
	var a := dir.source_for("row:x", 60.0, {})
	Run.level = 9
	var b := dir.source_for("row:x", 400.0, {"hp": 3})
	assert_dict(b).is_equal(a)
	assert_float(float(b["lv_hp"])).is_equal(1.0)
	# rows are told apart by their place in the timeline's roster, with their id when they have one (the fix round: two
	# rows of a hand-made JSON sharing an id shared one snapshot); a row built by hand by its id
	var r0 := {"t": 0, "enemy": "skeleton", "weight": 1}
	var r1 := {"t": 0, "enemy": "skeleton", "weight": 1}
	var r2 := {"id": "dup", "t": 0, "enemy": "skeleton", "weight": 1}
	var r3 := {"id": "dup", "t": 300, "enemy": "skeleton", "weight": 1}
	dir.timeline.roster = [r0, r1, r2, r3]
	assert_str(dir.row_key(r1)).is_equal("row#1")
	assert_str(dir.row_key(r0)).is_equal("row#0")
	assert_str(dir.row_key(r2)).is_equal("row:dup#2")
	assert_str(dir.row_key(r3)).is_equal("row:dup#3")
	assert_str(dir.row_key({"id": "r7", "t": 0})).is_equal("row:r7")
	# so the two "dup" rows fix their own numbers: the curve at 0 s and at 300 s
	assert_float(float(dir._row_src(r2)["hp_time"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(dir._row_src(r3)["hp_time"])).is_equal_approx(2.0, 0.0001)
	# a fresh run starts with nothing fixed
	dir.start(Registry.map("red_canyon"))
	assert_dict(dir.source_state("row:x")).is_empty()
	dir.stop()


# ---------------------------------------------------------------- R2: size ranges

func test_size_ranges_read_from_the_stats() -> void:
	assert_vector(EnemyDef.size_range_of([3, 5])).is_equal(Vector2(3, 5))
	assert_vector(EnemyDef.size_range_of([5.0, 3.0])).is_equal(Vector2(3, 5))
	assert_vector(EnemyDef.size_range_of([2])).is_equal(Vector2(2, 2))
	assert_vector(EnemyDef.size_range_of(1.5)).is_equal(Vector2.ZERO)
	assert_vector(EnemyDef.size_range_of([1, 2, 3])).is_equal(Vector2.ZERO)
	assert_vector(EnemyDef.size_range_of(["big", 2])).is_equal(Vector2.ZERO)
	assert_vector(EnemyDef.size_range_of([0, 2])).is_equal(Vector2(EnemyDef.SIZE_MIN, 2))
	var base: EnemyDef = Registry.enemy("skeleton")
	var c := base.with_overrides({"size": [3, 5]})
	assert_vector(c.size_range).is_equal(Vector2(3, 5))
	# the copy keeps the painting's own size, which the radius scales against
	assert_float(c.size).is_equal_approx(base.size, 0.0001)
	assert_float(c.size_ref).is_equal_approx(base.size, 0.0001)
	assert_bool(c.radius_follows).is_true()
	assert_bool(base.with_overrides({"size": [3, 5], "radius": 0.8}).radius_follows).is_false()
	# size_mult scales both ends
	assert_vector(base.with_overrides({"size": [2, 4], "size_mult": 1.5}).size_range).is_equal(Vector2(3, 6))
	# a plain number as before, and a malformed list never breaks a spawn: the creature's own size
	var p := base.with_overrides({"size": 1.5})
	assert_vector(p.size_range).is_equal(Vector2.ZERO)
	assert_float(p.size).is_equal_approx(1.5, 0.0001)
	var bad := base.with_overrides({"size": [1, 2, 3]})
	assert_vector(bad.size_range).is_equal(Vector2.ZERO)
	assert_float(bad.size).is_equal_approx(base.size, 0.0001)


func test_a_size_range_rolls_each_creature_and_moves_its_radius() -> void:
	var d := _test_def("p58_sz", "skeleton", {"size": 1.75, "radius": 0.52, "variance": {"size": 0.3, "speed": 0.0}})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	var s := {"size": [3, 5]}
	var sizes: Array = []
	var idx: Array = []
	var type := -1
	for k in range(40):
		var i := em.spawn(d.id, Vector3(float(k % 8) * 3.0 - 12.0, 0, floorf(float(k) / 8.0) * 3.0), null, 1.0, 1.0, "", s)
		assert_int(i).is_greater_equal(0)
		# inside the range (no variance jitter on top: 5 x 1.3 would leave it)
		assert_float(em.size[i]).is_between(3.0, 5.0)
		# the body follows the painting: radius x size / JSON size
		assert_float(em.radius[i]).is_equal_approx(0.52 * em.size[i] / 1.75, 0.0001)
		sizes.append(em.size[i])
		idx.append(i)
		# one type for the whole row, whatever each one rolled
		if type < 0:
			type = em.type_idx[i]
		assert_int(em.type_idx[i]).is_equal(type)
	assert_float(float(sizes.max()) - float(sizes.min())).is_greater(1.0)
	# its shadow follows the rolled size too
	var lo: int = idx[sizes.find(sizes.min())]
	var hi: int = idx[sizes.find(sizes.max())]
	var scf := Vector3(0, 0, -1)
	var scr := Vector3(1, 0, 0)
	var ratio: float = em.shadow_xform(hi, scf, scr).basis.x.length() / em.shadow_xform(lo, scf, scr).basis.x.length()
	assert_float(ratio).is_equal_approx(em.size[hi] / em.size[lo], 0.001)
	em.kill_all(false)
	# a row that sets its radius keeps it
	var j := em.spawn(d.id, Vector3(0, 0, 10), null, 1.0, 1.0, "", {"size": [3, 5], "radius": 0.8})
	assert_float(em.radius[j]).is_equal_approx(0.8, 0.0001)
	# a split child's scale still applies on top of the roll
	var c := em.spawn(d.id, Vector3(4, 0, 10), null, 0.6, 1.0, "", s)
	assert_float(em.size[c]).is_between(3.0 * 0.6, 5.0 * 0.6)
	# a plain size: the number, the variance jitter on top as before, the radius as before
	var q := _test_def("p58_sq", "skeleton", {"size": 1.75, "radius": 0.52})
	var m := em.spawn(q.id, Vector3(-4, 0, 10), null, 1.0, 1.0, "", {"size": 1.5})
	assert_float(em.size[m]).is_equal_approx(1.5, 0.0001)
	assert_float(em.radius[m]).is_equal_approx(0.52, 0.0001)


# ---------------------------------------------------------------- R3: colour ranges

func test_hues_roll_up_the_wheel_and_wrap_through_red() -> void:
	assert_float(EnemyDef.roll_hue(100.0, 200.0, 0.5)).is_equal_approx(150.0, 0.0001)
	assert_float(EnemyDef.roll_hue(350.0, 10.0, 0.0)).is_equal_approx(350.0, 0.0001)
	assert_float(EnemyDef.roll_hue(350.0, 10.0, 0.5)).is_equal_approx(0.0, 0.0001)
	assert_float(EnemyDef.roll_hue(350.0, 10.0, 1.0)).is_equal_approx(10.0, 0.0001)
	assert_float(EnemyDef.roll_hue(40.0, 40.0, 0.7)).is_equal_approx(40.0, 0.0001)
	# the whole wheel
	assert_float(EnemyDef.roll_hue(0.0, 360.0, 0.25)).is_equal_approx(90.0, 0.0001)
	# the read: defaults, a single hue, clamps, nothing without a hue
	var t := EnemyDef.tint_range_of({"hue": [340, 20]})
	assert_float(float(t["sat"])).is_equal_approx(EnemyDef.TINT_SAT, 0.0001)
	assert_float(float(t["val"])).is_equal_approx(EnemyDef.TINT_VAL, 0.0001)
	assert_float(float(t["amount"])).is_equal_approx(EnemyDef.TINT_AMOUNT, 0.0001)
	var one := EnemyDef.tint_range_of({"hue": 200, "amount": 0.8})
	assert_float(float(one["h0"])).is_equal(200.0)
	assert_float(float(one["h1"])).is_equal(200.0)
	var wild := EnemyDef.tint_range_of({"hue": [400, -20], "sat": 2, "amount": 3})
	assert_float(float(wild["h0"])).is_equal(360.0)
	assert_float(float(wild["h1"])).is_equal(0.0)
	assert_float(float(wild["sat"])).is_equal(1.0)
	assert_float(float(wild["amount"])).is_equal(1.0)
	assert_dict(EnemyDef.tint_range_of({"hue": "red"})).is_empty()
	assert_dict(EnemyDef.tint_range_of({})).is_empty()


## A creature's tint hue in degrees.
func _hue(c: Color) -> float:
	return c.h * 360.0


func test_a_colour_range_tints_every_creature_of_the_row() -> void:
	var d := _test_def("p58_t", "skeleton", {"variance": {"tints": ["#00ff00"], "tint_strength": 0.35}})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	# colour waits for the run's first kills for the palette, but not for a row's own colour
	em.colour_after_kills = 50
	Run.kills = 0
	var s := {"tint": {"hue": [340, 20], "sat": 0.9, "val": 1.0, "amount": 0.7}}
	var below := 0
	var above := 0
	var type := -1
	for k in range(60):
		var i := em.spawn(d.id, Vector3(float(k % 10) * 2.0 - 10.0, 0, floorf(float(k) / 10.0) * 2.0), null, 1.0, 1.0, "", s)
		var c: Color = em.vtint[i]
		# amount is the strength
		assert_float(c.a).is_equal_approx(0.7, 0.0001)
		assert_float(c.s).is_equal_approx(0.9, 0.01)
		var h := _hue(c)
		assert_bool(h >= 339.9 or h <= 20.1).override_failure_message("hue %.1f outside 340..20" % h).is_true()
		if h >= 339.9:
			below += 1
		else:
			above += 1
		# drawn as it is
		assert_bool(em.tint_of(i).is_equal_approx(c)).is_true()
		if type < 0:
			type = em.type_idx[i]
		assert_int(em.type_idx[i]).is_equal(type)
	# the range really wraps: both sides of red come up
	assert_int(below).is_greater(5)
	assert_int(above).is_greater(5)
	# with colour open the palette still never shows on a coloured row
	Run.kills = 99
	for k in range(10):
		var i2 := em.spawn(d.id, Vector3(float(k) * 2.0 - 10.0, 0, 20.0), null, 1.0, 1.0, "", s)
		var h2 := _hue(em.vtint[i2])
		assert_bool(h2 >= 339.9 or h2 <= 20.1).is_true()
	# a plain row of the creature: the palette, as before
	var p := em.spawn(d.id, Vector3(0, 0, 30))
	assert_float(em.vtint[p].g).is_equal_approx(1.0, 0.01)
	assert_float(em.vtint[p].a).is_equal_approx(0.35, 0.0001)


func test_a_coloured_rows_special_keeps_the_rows_hue_darker() -> void:
	var d := _test_def("p58_u", "skeleton", {"variance": {"special_chance": 1.0,
		"special": {"size": 1.5, "hp": 1.0, "damage": 1.0, "xp": 1.0, "tint": "#123456", "tint_strength": 0.6}}})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 0
	# (pass 72, lane SPEC: twenty specials at once, so no cap on how many live, EnemyDef.special_max_alive)
	em.special_defaults = {"max_alive": 0}
	# the lead (pass 58): the special of a coloured row is a darker, stronger shade of the hue it rolled, not its own wine
	var s := {"tint": {"hue": [100, 120], "sat": 0.8, "val": 1.0, "amount": 0.5}}
	for k in range(20):
		var i := em.spawn(d.id, Vector3(float(k) * 1.5 - 15.0, 0, 0), null, 1.0, 1.0, "", s)
		assert_int(em.vspecial[i]).is_equal(1)
		var c: Color = em.vtint[i]
		assert_float(c.h * 360.0).is_between(99.5, 120.5)
		assert_float(c.s).is_equal_approx(minf(0.8 + EnemyDef.SPECIAL_SAT_ADD, 1.0), 0.01)
		assert_float(c.v).is_equal_approx(1.0 * EnemyDef.SPECIAL_VAL_MULT, 0.01)
		# the stronger of the row's amount (0.5) and the special's own strength (0.6), and a little more
		assert_float(c.a).is_equal_approx(minf(0.6 + EnemyDef.SPECIAL_STRENGTH_ADD, 1.0), 0.0001)
		# its size factor stays (no jitter: the test creature has none)
		assert_float(em.size[i]).is_equal_approx(1.75 * 1.5, 0.01)
	# the formula itself: the shade of the very hue a plain one of the row rolls at the same u
	var trg := EnemyDef.tint_range_of({"hue": [340, 20], "sat": 0.95, "val": 0.8, "amount": 0.9})
	var plain := EnemyDef.tint_color(trg, 0.25)
	var dark := EnemyDef.tint_special_color(trg, 0.25, 0.45)
	assert_float(dark.h).is_equal_approx(plain.h, 0.002)
	assert_float(dark.s).is_equal_approx(1.0, 0.01)
	assert_float(dark.v).is_equal_approx(0.8 * EnemyDef.SPECIAL_VAL_MULT, 0.01)
	# 0.9 and 0.15 more, at most 1
	assert_float(dark.a).is_equal_approx(1.0, 0.0001)
	# a faint row: the special's own strength and a little more
	assert_float(EnemyDef.tint_special_color(EnemyDef.tint_range_of({"hue": 30, "amount": 0.2}), 0.0, 0.45).a).is_equal_approx(0.45 + EnemyDef.SPECIAL_STRENGTH_ADD, 0.0001)
	# a row without a tint: the special's own colour, exactly as before
	var j := em.spawn(d.id, Vector3(0, 0, 6))
	assert_int(em.vspecial[j]).is_equal(1)
	assert_str(Color(em.vtint[j].r, em.vtint[j].g, em.vtint[j].b).to_html(false)).is_equal("123456")
	assert_float(em.vtint[j].a).is_equal_approx(0.6, 0.0001)


func test_an_elite_and_the_status_tints_still_win_over_a_rows_colour() -> void:
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 0
	var s := {"tint": {"hue": [100, 120], "amount": 0.9}}
	# an elite modifier's colour over the row's
	var q := _test_def("p58_v", "skeleton")
	var mod: EliteModDef = em.elites[0]
	var e := em.spawn(q.id, Vector3(-2, 0, 0), mod, 1.0, 1.0, "", s)
	assert_float(em.tint_of(e).r).is_equal_approx(mod.outline.r, 0.0001)
	assert_float(em.tint_of(e).a).is_equal_approx(0.7, 0.0001)
	# a frozen creature is ice blue whatever its row says
	var f := em.spawn(q.id, Vector3(0, 0, 4), null, 1.0, 1.0, "", s)
	em.freeze_t[f] = 1.0
	assert_bool(em.tint_of(f).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0))).is_true()


# ---------------------------------------------------------------- the import

func test_ranges_survive_the_json_to_tres_import() -> void:
	var d := JsonContent.load_json("res://content/maps/red_canyon/red_canyon.json")
	assert_bool(d.is_empty()).is_false()
	var tl: Dictionary = d["timeline_data"]
	(tl["roster"] as Array)[0]["stats"] = {"size": [3, 5], "tint": {"hue": [340, 20], "sat": 0.9, "val": 1.0, "amount": 0.7}}
	var res := JsonContent.build("maps", d, "res://content/maps/red_canyon/")
	assert_object(res).is_not_null()
	assert_int(ResourceSaver.save(res, TMP_TRES)).is_equal(OK)
	var back: MapDef = ResourceLoader.load(TMP_TRES, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(back).is_not_null()
	var st: Dictionary = (back.timeline.roster[0] as Dictionary)["stats"]
	assert_vector(EnemyDef.size_range_of(st["size"])).is_equal(Vector2(3, 5))
	var t := EnemyDef.tint_range_of(st["tint"])
	assert_float(float(t["h0"])).is_equal(340.0)
	assert_float(float(t["h1"])).is_equal(20.0)
	assert_float(float(t["amount"])).is_equal_approx(0.7, 0.0001)
	# the same overrides from the JSON and from the .tres are one type
	assert_str(EnemyDef.override_key_of(st)).is_equal(EnemyDef.override_key_of((tl["roster"] as Array)[0]["stats"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_TRES))


# ---------------------------------------------------------------- the review of pass 57: rings and points by the wall

## A plain map with a lake: `in_water` inside the disc at `lake_c` of `lake_r` (as Red Canyon answers for its oasis).
const FAKE_LAKE_MAP := """extends MapBase
var lake_c := Vector2(0.0, 11.7)
var lake_r := 2.5
func in_water(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(lake_c) < lake_r
"""


func _gap(p: Vector3, h: Vector3) -> float:
	return Vector2(p.x - h.x, p.z - h.z).length()


func test_a_ring_by_the_wall_keeps_a_rings_width_and_its_count() -> void:
	# the reviewer's case: a 105-ring round a hero 64 m out (the wall's usable edge is 64.5 m); 7 had landed within 2 m
	var hero_at := Vector3(64.0, 0.0, 0.0)
	var w := _world(hero_at)
	var lim: float = (w["map"] as MapBase).arena_radius - 1.5
	var dir := _director(w, _tl())
	for seed: int in [1, 2, 105]:
		dir._rng.seed = seed
		var pts: Array = dir.ring_points(105)
		assert_int(pts.size()).is_equal(105)
		var angles: Array = []
		for p: Vector3 in pts:
			# a ring's width from him (never the 6 m the review asks for, let alone 2), and inside the arena
			assert_float(_gap(p, hero_at)).is_greater_equal(WaveDirector.RING_RADIUS - WaveDirector.RING_JITTER - 0.001)
			assert_float(Vector2(p.x, p.z).length()).is_less_equal(lim + 0.001)
			angles.append(fposmod(atan2(p.z - hero_at.z, p.x - hero_at.x), TAU))
		# spread over the arc inside, not heaped at its ends: no two within a third of the even spacing round the hero
		angles.sort()
		var arc := EnemyManager.ring_arc(hero_at, WaveDirector.RING_RADIUS + WaveDirector.RING_JITTER, lim)
		assert_float(arc.y).is_less(PI)
		var spacing: float = 2.0 * arc.y / 105.0
		for k in range(angles.size() - 1):
			assert_float(float(angles[k + 1]) - float(angles[k])).is_greater(spacing * 0.33)
	# the same ring in the open is the whole ring, as before
	(w["hero"] as Node3D).global_position = Vector3.ZERO
	assert_float(EnemyManager.ring_arc(Vector3.ZERO, WaveDirector.RING_RADIUS, lim).y).is_equal_approx(PI, 0.0001)


func test_the_elite_ring_and_the_swarm_ring_keep_their_distance_by_the_wall() -> void:
	var d := _test_def("p58_wr", "skeleton", {"pack_size": 6, "cap_share": 1.0})
	var hero_at := Vector3(0.0, 0.0, 64.0)
	var w := _world(hero_at)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl())
	dir._rng.seed = 12
	assert_int(dir._spawn_elite_ring(d.id, 12, em.elites[0], "", {})).is_equal(12)
	for i in _alive_indices(em):
		assert_float(_gap(em.pos[i], hero_at)).is_greater_equal(WaveDirector.ELITE_RING_RADIUS - 0.01)
	em.kill_all(false)
	# the swarm's own 16 m ring (EnemyManager.spawn_ring): its whole count, every one 16 m out, inside the arena
	var before := _alive_indices(em)
	assert_int(em.spawn_ring(d.id, 40, hero_at, 16.0)).is_equal(40)
	for i in _new_since(em, before):
		assert_float(_gap(em.pos[i], hero_at)).is_greater_equal(15.99)
		assert_float(Vector2(em.pos[i].x, em.pos[i].z).length()).is_less_equal(em.arena_radius - 2.0 + 0.001)


func test_in_front_and_every_spawn_point_by_the_wall_keep_their_distance() -> void:
	# the reviewer's second case: a hero by the north wall (north = -Z = the top of the screen); 47% had landed within 6 m
	var hero_at := Vector3(0.0, 0.0, -64.0)
	var w := _world(hero_at)
	var lim: float = (w["map"] as MapBase).arena_radius - 1.5
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "top": 1}}))
	dir._rng.seed = 47
	for k in range(200):
		for p: Vector3 in [dir._in_front_point(), dir._spawn_point(), dir._around_point()]:
			assert_float(Vector2(p.x, p.z).length()).is_less_equal(lim + 0.001)
			# 19-24 m for the spawn points, 15-20 m for the portal wave's: never within 6 m
			assert_float(_gap(p, hero_at)).is_greater_equal(15.0 - 0.001)
	# a hero facing the wall in the old facing mode too
	var dir2 := _director(w, _tl())
	dir2._rng.seed = 48
	(w["hero"] as Node3D).set("facing", 0.0)
	for k in range(100):
		assert_float(_gap(dir2._spawn_point(), hero_at)).is_greater_equal(19.0 - 0.001)
	# in the open, in_front is as before: 19-24 m out, within 45 degrees of straight up the screen
	(w["hero"] as Node3D).global_position = Vector3.ZERO
	for k in range(100):
		var p := dir._in_front_point()
		assert_float(_gap(p, Vector3.ZERO)).is_between(19.0 - 0.001, 24.0 + 0.001)
		assert_float(rad_to_deg(Vector3(p.x, 0.0, p.z).normalized().angle_to(Vector3(0, 0, -1)))).is_less_equal(45.01)


func test_ring_points_step_off_rocks_and_the_lake() -> void:
	var g: Node = auto_free(Node.new())
	add_child(g)
	var mb: MapBase = MapBase.new()
	mb.set_script(_script(FAKE_LAKE_MAP))
	g.add_child(mb)
	# two rocks on the ring and a lake across it (the ring is 11.7 m round the hero at the middle)
	mb.obstacles = [Vector3(11.7, 0.0, 1.0), Vector3(-8.27, -8.27, 0.6)]
	var rng := RandomNumberGenerator.new()
	for seed: int in [3, 4, 5, 6]:
		rng.seed = seed
		var pts: Array = EnemyManager.ring_spots(Vector3.ZERO, WaveDirector.RING_RADIUS, 40, 64.5, rng, rng.randf() * TAU, WaveDirector.RING_SLIDE, WaveDirector.RING_JITTER, mb)
		assert_int(pts.size()).is_equal(40)
		for p: Vector3 in pts:
			assert_bool(EnemyManager.spawn_clear(mb, p)).override_failure_message("a ring point on a rock or in the lake at %s" % str(p)).is_true()
			assert_float(_gap(p, Vector3.ZERO)).is_greater_equal(6.0)
	# what spawn_clear calls clear: outside a rock's painted foot (its collider / 0.62) and a body, out of the water
	assert_bool(EnemyManager.spawn_clear(mb, Vector3(11.7 + 1.0 / 0.62 + 0.45, 0, 0))).is_false()
	assert_bool(EnemyManager.spawn_clear(mb, Vector3(11.7 + 1.0 / 0.62 + 0.55, 0, 0))).is_true()
	assert_bool(EnemyManager.spawn_clear(mb, Vector3(0, 0, 11.7))).is_false()
	assert_bool(EnemyManager.spawn_clear(null, Vector3.ZERO)).is_true()


# ---------------------------------------------------------------- the fix round (the review of lane WV)

func test_an_event_of_a_creature_a_row_brings_joins_the_row() -> void:
	var d := _test_def("p58_j", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0,
		"variants": {"ZZ": {}}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	# a row of the creature from 60 s that sets its HP (Garry's fire ants: 55), there until 520 s
	var dir := _director(w, _curves({"roster": [{"id": "rj", "t": 60, "until": 1e9, "enemy": d.id, "weights": [[60, 1], [500, 1], [520, 0]], "pack": 1, "stats": {"hp": 55}}]}))
	var row: Dictionary = dir.timeline.roster[0]
	Run.level = 5
	var a := _from_row(dir, em, row, 100.0)
	# the row's 55 HP takes no curve, at the hero's level 5 when it first came
	assert_float(em.max_hp[a]).is_equal_approx(55.0 * 1.2 * 1.3, 0.0001)
	# the clock and the hero move on: a swarm of the same creature at 300 s, the hero at level 12 (the review: a fire-ant
	# swarm beside the fire-ant row had 1.6 times their HP)
	Run.level = 12
	Run.elapsed = 300.0
	dir._apply_mults()
	var before := _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 3, "pattern": "scatter"})
	var sw := _new_since(em, before)
	assert_int(sw.size()).is_equal(3)
	for i in sw:
		assert_float(em.max_hp[i]).is_equal_approx(em.max_hp[a], 0.0001)
		assert_float(em.dmg[i]).is_equal_approx(em.dmg[a], 0.0001)
	var en := dir.event_numbers(d.id, "", {})
	assert_str(str(en["joined"])).is_equal(dir.row_key(row))
	# an event that sets its own HP keeps it, at the moment's level; its damage, which it leaves alone, still joins the row
	before = _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 1, "pattern": "scatter", "stats": {"hp": 70}})
	var own := _new_since(em, before)
	assert_float(em.max_hp[own[0]]).is_equal_approx(70.0 * 1.55 * 1.3, 0.0001)
	assert_float(em.dmg[own[0]]).is_equal_approx(em.dmg[a], 0.0001)
	# another look of the creature is another creature to the eye: the moment's numbers (the curve x2 at 300 s, level 12)
	before = _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "variant": "ZZ", "count": 1, "pattern": "scatter"})
	var other := _new_since(em, before)
	assert_float(em.max_hp[other[0]]).is_equal_approx(10.0 * 2.0 * 1.55 * 1.3, 0.0001)
	# a special of the creature joins too, and so does a boss's brood (EnemyManager asks the director)
	g.director = dir
	var bn: Dictionary = em.brood_numbers(d.id)
	assert_str(str(bn["joined"])).is_equal(dir.row_key(row))
	g.director = null
	assert_dict(em.brood_numbers(d.id)["src"]).is_equal(em.now_src())
	# an elite drawn from the row comes on the row's numbers, its modifier on top
	before = _alive_indices(em)
	dir._spawn_elite("", "")
	var el := _new_since(em, before)
	assert_int(el.size()).is_greater_equal(1)
	for i in el:
		assert_int(em.elite_idx[i]).is_greater_equal(0)
		assert_int(em.fixed[i]).is_equal(1)
		assert_float(em.f_hpt[i]).is_equal_approx(em.f_hpt[a], 0.0001)
		assert_float(em.f_lvh[i]).is_equal_approx(em.f_lvh[a], 0.0001)
	# once the row has gone (its weight 0 from 520 s) the moment's numbers again
	Run.elapsed = 530.0
	dir._apply_mults()
	assert_str(str(dir.event_numbers(d.id, "", {})["joined"])).is_equal("")


func test_an_event_joins_an_open_wave() -> void:
	var d := _test_def("p58_jw", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves({"waves": [{"id": "wj", "t": 120, "until": 900, "count": 0, "burst": 1, "every": 30, "enemy": d.id, "pattern": "scatter"}]}))
	Run.elapsed = 200.0
	dir._apply_mults()
	dir._tick_waves()
	var stream := _alive_indices(em)
	assert_int(stream.size()).is_greater(0)
	Run.elapsed = 400.0
	Run.level = 7
	dir._apply_mults()
	var before := _alive_indices(em)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 2, "pattern": "scatter"})
	for i in _new_since(em, before):
		# the wave's curve at its 120 s (x1.4) and its level 1, not the moment's x2.33 and level 7
		assert_float(em.max_hp[i]).is_equal_approx(em.max_hp[stream[0]], 0.0001)
		assert_float(em.max_hp[i]).is_equal_approx(10.0 * 1.4 * 1.3, 0.0001)
	assert_str(str(dir.event_numbers(d.id, "", {})["joined"])).is_equal("wave#0")


func test_endless_waves_fix_the_rows_afresh() -> void:
	var d := _test_def("p58_en", "skeleton", {"hp": 10.0, "damage": 4.0, "pack_size": 1, "cap_share": 1.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	# a curve that keeps rising (1 + t / 300), endless waves of 60 s from 1290 s (430 x 3), a hell-like row with no end
	var dir := _director(w, _curves({"hp_curve": {"mode": "points", "points": [[0, 1.0], [3000, 11.0]]},
		"endless_wave_seconds": 60, "roster": [{"id": "re", "t": 860, "enemy": d.id, "weight": 1, "pack": 1}]}))
	var row: Dictionary = dir.timeline.roster[0]
	Run.stage = 2
	Run.level = 20
	var a := _from_row(dir, em, row, 900.0)
	assert_float(em.f_hpt[a]).is_equal_approx(1.0 + 860.0 / 300.0, 0.0001)
	assert_float(em.f_lvh[a]).is_equal_approx(1.0 + 0.05 * 19.0, 0.0001)
	# stage 3 rolls on: the row keeps its numbers
	Run.level = 26
	var a2 := _from_row(dir, em, row, 1200.0)
	assert_float(em.f_hpt[a2]).is_equal_approx(em.f_hpt[a], 0.0001)
	assert_float(em.f_lvh[a2]).is_equal_approx(em.f_lvh[a], 0.0001)
	# Endless after the stage (pass 87, lane SGAME, re-pinned: the run clock stands at the stage's end in Endless, and
	# each Endless wave fixes the rows afresh from their own start and the hero's level at its first creature then, times
	# that wave's multipliers, WaveTimeline.endless_mults), its first wave
	Run.endless = true
	Run.endless_time = 0.0
	Run.level = 30
	var m1: Dictionary = dir.timeline.endless_mults(1, Run.stage)
	var b := _from_row(dir, em, row, 1290.0)
	assert_float(em.f_hpt[b]).is_equal_approx((1.0 + 860.0 / 300.0) * float(m1["hp"]), 0.0001)
	assert_float(em.f_lvh[b]).is_equal_approx(1.0 + 0.05 * 29.0, 0.0001)
	assert_float(float(dir.source_state(dir.row_key(row) + "@w1")["t0"])).is_equal(860.0)
	# the same wave later: the same numbers, whatever the hero's level now
	Run.level = 34
	Run.endless_time = 5.0
	var c := _from_row(dir, em, row, 1290.0)
	assert_float(em.f_hpt[c]).is_equal_approx(em.f_hpt[b], 0.0001)
	assert_float(em.f_lvh[c]).is_equal_approx(em.f_lvh[b], 0.0001)
	assert_float(em.max_hp[c]).is_equal_approx(em.max_hp[b], 0.0001)
	# the next wave (a wave's `every` on): afresh again, at the next wave's multiplier
	Run.level = 40
	Run.endless_time = Run.map.timeline.endless_value("every", Run.stage) + 0.5
	var m2: Dictionary = dir.timeline.endless_mults(2, Run.stage)
	var e := _from_row(dir, em, row, 1290.0)
	assert_float(em.f_hpt[e]).is_equal_approx((1.0 + 860.0 / 300.0) * float(m2["hp"]), 0.0001)
	assert_float(em.f_lvh[e]).is_equal_approx(1.0 + 0.05 * 39.0, 0.0001)
	assert_float(float(m2["hp"])).is_greater(float(m1["hp"]))
	Run.endless = false
	Run.endless_time = 0.0


func test_split_children_keep_the_parents_stage_size_and_hue() -> void:
	var d := _test_def("p58_sp", "skeleton", {"hp": 10.0, "damage": 4.0, "size": 1.75, "radius": 0.52})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	var dir := _director(w, _curves())
	Run.elapsed = 300.0
	dir._apply_mults()
	var splitter: EliteModDef = Registry.elites.get("splitter")
	var sc := float(splitter.params.get("split_scale", 0.6))
	var stats := {"size": [1.0, 3.0], "tint": {"hue": [0, 300], "amount": 0.8}}
	for k in range(6):
		var p := em.spawn(d.id, Vector3(float(k) * 6.0 - 15.0, 0, 5), splitter, 1.0, 1.0, "", stats, dir.fixed_numbers(60.0, stats))
		var base: float = em.f_bsz[p]
		var hue: float = em.vtint[p].h
		assert_float(base).is_between(1.0, 3.0)
		# the portal: the next stage's multiplier is live by the time it dies
		Run.stage = 1
		dir._apply_mults()
		var before := _alive_indices(em)
		em._die(p, "")
		var kids := _new_since(em, before)
		assert_int(kids.size()).is_equal(int(splitter.params.get("split_count", 3)))
		for kid in kids:
			# its parent's stage (x1, not x2.2), its parent's size roll (never a child bigger than the parent), its hue
			assert_float(em.f_stage[kid]).is_equal_approx(1.0, 0.0001)
			assert_float(em.max_hp[kid]).is_equal_approx(10.0 * 1.2 * 0.5 * 1.3, 0.0001)
			assert_float(em.f_bsz[kid]).is_equal_approx(base, 0.0001)
			assert_float(em.size[kid]).is_equal_approx(base * sc, 0.0001)
			assert_float(em.size[kid]).is_less(em.size[p])
			assert_float(em.vtint[kid].h).is_equal_approx(hue, 0.001)
		em.kill_all(false)
		Run.stage = 0
		dir._apply_mults()


func test_a_size_ranges_special_stays_inside_the_range() -> void:
	var d := _test_def("p58_sr", "skeleton", {"size": 1.75, "radius": 0.52,
		"variance": {"special_chance": 1.0, "special": {"size": 1.5, "hp": 1.6, "damage": 1.0, "xp": 1.0}}})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 0
	# (pass 72, lane SPEC: thirty specials at once, so no cap on how many live, EnemyDef.special_max_alive)
	em.special_defaults = {"max_alive": 0}
	var plain := em.spawn(d.id, Vector3(0, 0, -20), null, 1.0, 1.0, "", {"size": [3, 5], "variance": {"special_chance": 0.0}})
	for k in range(30):
		var i := em.spawn(d.id, Vector3(float(k % 10) * 3.0 - 15.0, 0, floorf(float(k) / 10.0) * 3.0), null, 1.0, 1.0, "", {"size": [3, 5]})
		assert_int(em.vspecial[i]).is_equal(1)
		# Garry's "between 3-5": the special's x1.5 lifts it towards 5, never past it; the body follows
		assert_float(em.size[i]).is_between(3.0, 5.0 + 0.0001)
		assert_float(em.size[i]).is_equal_approx(minf(em.f_bsz[i] * 1.5, 5.0), 0.0001)
		assert_float(em.radius[i]).is_equal_approx(0.52 * em.size[i] / 1.75, 0.0001)
	# its HP stays the special's (x1.6 of a plain one of the row)
	var s := em.spawn(d.id, Vector3(0, 0, 20), null, 1.0, 1.0, "", {"size": [3, 5]})
	assert_float(em.max_hp[s]).is_equal_approx(em.max_hp[plain] * 1.6, 0.0001)
	# a plain size: the special's factor on top, as before
	var q := em.spawn(d.id, Vector3(6, 0, 20), null, 1.0, 1.0, "", {"size": 2.0})
	assert_float(em.size[q]).is_equal_approx(3.0, 0.0001)


func test_wide_bodies_push_apart_past_the_next_cell() -> void:
	var big := _test_def("p58_big", "skeleton", {"size": 6.0, "radius": 2.7, "speed": 1.0})
	var small := _test_def("p58_small", "skeleton", {"radius": 0.5, "speed": 1.0})
	var w := _world(Vector3(2.65, 0, 200))
	var em: EnemyManager = w["em"]
	var hero: Vector3 = (w["hero"] as Node3D).global_position
	# two giants 5.1 m apart (their bodies 5.4 m together), two grid cells apart: the 3 x 3 cells never met them
	var l := em.spawn(big.id, Vector3(0.1, 0, 0))
	var r := em.spawn(big.id, Vector3(5.2, 0, 0))
	for i in [l, r]:
		em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	assert_int(absi(em._gcol(em.pos[r].x) - em._gcol(em.pos[l].x))).is_greater(1)
	em._steer(l, hero, 0.016)
	em._steer(r, hero, 0.016)
	assert_float(em.vel[l].x).is_less(-0.1)
	assert_float(em.vel[r].x).is_greater(0.1)
	em.kill_all(false)
	# a small body past the next cell from a huge one still steps off its edge
	var h := _test_def("p58_huge", "skeleton", {"size": 12.0, "radius": 4.9, "speed": 1.0})
	var s := em.spawn(small.id, Vector3(0.1, 0, 0))
	var g := em.spawn(h.id, Vector3(5.1, 0, 0))
	for i in [s, g]:
		em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	assert_int(absi(em._gcol(em.pos[g].x) - em._gcol(em.pos[s].x))).is_greater(1)
	em._steer(s, hero, 0.016)
	assert_float(em.vel[s].x).is_less(-0.1)


## A plain map with a lake it can name, as Red Canyon does (lake_center, lake_radius; in_water 1.02 x the radius).
const FAKE_OASIS_MAP := """extends MapBase
var lake_c := Vector2(0.0, 0.0)
var lake_r := 6.8
func lake_center() -> Vector2:
	return lake_c
func lake_radius() -> float:
	return lake_r
func in_water(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(lake_c) < lake_r * 1.02
"""


func test_ring_and_in_front_spots_keep_out_of_an_oasis_sized_lake() -> void:
	# the review: by Red Canyon's oasis (6.76 m) 11-14% of the ring and in_front spots stayed in the water
	var w := _world()
	var mb: MapBase = w["map"]
	mb.set_script(_script(FAKE_OASIS_MAP))
	var lim: float = mb.arena_radius - 1.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 58
	for lr: float in [5.5, 6.8, 7.5]:
		mb.set("lake_r", lr)
		for k in range(12):
			var ang := TAU * float(k) / 12.0
			# a hero 3 m from the shore: the 11.7 m ring crosses the water
			var hero_at := Vector3(cos(ang), 0, sin(ang)) * (lr + 3.0)
			var pts: Array = EnemyManager.ring_spots(hero_at, WaveDirector.RING_RADIUS, 105, lim, rng, rng.randf() * TAU, WaveDirector.RING_SLIDE, WaveDirector.RING_JITTER, mb)
			assert_int(pts.size()).is_equal(105)
			for p: Vector3 in pts:
				assert_bool(mb.in_water(p)).override_failure_message("a ring spot in the lake at %s (lake %.1f m)" % [str(p), lr]).is_false()
				assert_float(_gap(p, hero_at)).is_between(WaveDirector.RING_RADIUS - WaveDirector.RING_JITTER - 0.001, WaveDirector.RING_RADIUS + WaveDirector.RING_JITTER + 0.001)
			# spread over the dry arcs, not heaped: no two within a quarter of the even spacing round the hero
			var angles: Array = []
			for p: Vector3 in pts:
				angles.append(fposmod(atan2(p.z - hero_at.z, p.x - hero_at.x), TAU))
			angles.sort()
			for q in range(angles.size() - 1):
				assert_float(float(angles[q + 1]) - float(angles[q])).is_greater(TAU / 105.0 * 0.25)
		# the swarm's 30-ring at 16 m round a hero 9 m from the shore
		for k in range(8):
			var ang2 := TAU * float(k) / 8.0
			var c2 := Vector3(cos(ang2), 0, sin(ang2)) * (lr + 9.0)
			for p: Vector3 in EnemyManager.ring_spots(c2, 16.0, 30, 64.0, rng, 0.0, 0.1 / (TAU / 30.0), 0.0, mb):
				assert_bool(mb.in_water(p)).is_false()
	# in_front with the lake straight up the screen, 21 m off (north = -Z)
	mb.set("lake_r", 6.8)
	(w["hero"] as Node3D).global_position = Vector3(0, 0, 21.0)
	var dir := _director(w, _tl())
	dir._rng.seed = 21
	var wet := 0
	for k in range(400):
		var p := dir._in_front_point()
		if mb.in_water(p):
			wet += 1
		assert_float(_gap(p, Vector3(0, 0, 21.0))).is_between(17.5 - 0.001, 25.5 + 0.001)
	assert_int(wet).is_equal(0)
	# the turn itself: a point dead ahead turns just past the lake's edge, the nearer side first
	var turns: Array = EnemyManager.lake_turns(mb, Vector3(0, 0, 21.0), 0.1, 21.0)
	assert_int(turns.size()).is_equal(2)
	var half := asin((6.8 * 1.02 + EnemyManager.ROCK_PAD) / 21.0)
	assert_float(absf(float(turns[0]))).is_greater(half * 0.9)
	assert_float(float(turns[0])).is_greater(0.0)
	assert_float(float(turns[1])).is_less(0.0)
	# a dry point has no turn
	assert_int(EnemyManager.lake_turns(mb, Vector3(0, 0, 21.0), PI * 0.5, 21.0).size()).is_equal(0)
