extends GdUnitTestSuite

## Pass 57, lane SP (Garry, 2026-10-07: "add 'Ring' option to the spawn options of enemies ... spawn in a Ring around the
## Player (kind of like what we have in the debug option in the Arena), but about 30% further from the Player", and
## "add 'In-front' option ... This one makes the enemies spawn above the Player, basically an override to the Spawning
## part in the Settings"): a ring of n stands evenly round the hero at RING_RADIUS (the arena's 9 m x 1.3 = 11.7 m) with a
## little jitter, clamped to the arena; in_front puts every creature of a spawn in the top wedge of the screen whatever
## spawn_sides says (sides or facing, the hero facing down the screen) and turns with the follow camera; a roster row with
## pattern ring, a wave with pattern in_front or ring, a swarm event with in_front and the portal wave go through those
## paths; the swarm's own ring stays 16 m; an unknown pattern is still a pack; the patterns survive the JSON -> .tres
## import.

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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
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

## the follow camera as the director reads it: only its yaw
const FAKE_CAMERA := """extends Node
var yaw := 0.0
func current_yaw() -> float:
	return yaw
"""

const FAKE_PICKUPS := """extends Node
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(_at, _boss = false) -> void:
	pass
"""

const TMP_TRES := "user://pass57_sp_map.tres"

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
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0


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
	return JsonContent.timeline_from_dict(base)


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


func _clear(em: EnemyManager) -> void:
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)


func _positions(em: EnemyManager) -> Array:
	var out: Array = []
	for i in _alive_indices(em):
		out.append(em.pos[i])
	return out


func _flat(p: Vector3, center: Vector3) -> Vector2:
	return Vector2(p.x - center.x, p.z - center.z)


## The angle (degrees) between where `p` lies from `center` and the direction `axis` on the ground.
func _deg_from(p: Vector3, center: Vector3, axis: Vector3) -> float:
	var f := _flat(p, center)
	return rad_to_deg(Vector3(f.x, 0.0, f.y).normalized().angle_to(Vector3(axis.x, 0.0, axis.z).normalized()))


## Every point within RING_RADIUS +- tol of `center`, and spread round the circle: no two closer (in angle) than half the
## even spacing, and no gap wider than one and a half spacings (the angles cover the circle).
func _assert_ring(pts: Array, center: Vector3, n: int, tol := 0.7) -> void:
	assert_int(pts.size()).is_equal(n)
	var angles: Array = []
	for p: Vector3 in pts:
		var f := _flat(p, center)
		assert_float(f.length()).is_between(WaveDirector.RING_RADIUS - tol, WaveDirector.RING_RADIUS + tol)
		angles.append(fposmod(atan2(f.y, f.x), TAU))
	angles.sort()
	var step := TAU / float(n)
	var min_gap := TAU
	var max_gap := 0.0
	for k in range(angles.size()):
		var nxt: float = angles[(k + 1) % angles.size()] + (TAU if k == angles.size() - 1 else 0.0)
		var gap: float = nxt - float(angles[k])
		min_gap = minf(min_gap, gap)
		max_gap = maxf(max_gap, gap)
	assert_float(min_gap).is_greater_equal(step * 0.5)
	assert_float(max_gap).is_less_equal(step * 1.5)


# ---------------------------------------------------------------- the ring

func test_the_ring_is_the_arenas_ring_a_third_further() -> void:
	# Garry: "kind of like what we have in the debug option in the Arena ... but about 30% further": 9 m x 1.3
	assert_float(WaveDirector.RING_RADIUS).is_equal_approx(11.7, 0.0001)
	assert_float(WaveDirector.RING_RADIUS).is_equal_approx(9.0 * 1.3, 0.0001)
	# the jitter keeps every point inside the brief's +-0.7 m and the slide keeps neighbours over half a spacing apart
	assert_float(WaveDirector.RING_JITTER).is_less_equal(0.7)
	assert_float(WaveDirector.RING_SLIDE).is_less_equal(0.25)


func test_a_ring_of_n_stands_evenly_round_the_hero() -> void:
	var w := _world(Vector3(5.0, 0.0, -3.0))
	var dir := _director(w, _tl())
	dir._rng.seed = 57
	var center: Vector3 = (w["hero"] as Node3D).global_position
	for n: int in [3, 12, 40, 105, 160]:
		_assert_ring(dir.ring_points(n), center, n)
	# a new ring starts at a new angle (it is not the same ring every time)
	var a: Vector3 = dir.ring_points(8)[0]
	var b: Vector3 = dir.ring_points(8)[0]
	assert_float(absf(_flat(a, center).angle_to(_flat(b, center)))).is_greater(0.001)
	# the jitter is real: a big ring is not a drawn line
	var radii: Array = []
	for p: Vector3 in dir.ring_points(105):
		radii.append(_flat(p, center).length())
	assert_float(float(radii.max()) - float(radii.min())).is_greater(0.4)
	# nothing asked, nothing given
	assert_array(dir.ring_points(0)).is_empty()


func test_a_ring_spawns_the_whole_group_and_stays_in_the_arena() -> void:
	var d := _test_def("p57_ring", "skeleton", {"pack_size": 5, "cap_share": 0.5})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl())
	dir._rng.seed = 7
	# all 30 at once round the hero, whatever the pack (5): a wave's burst is one ring
	assert_int(dir._spawn_group(d.id, 30, "ring", 5, null, "", {})).is_equal(30)
	_assert_ring(_positions(em), Vector3.ZERO, 30)
	_clear(em)
	# near the arena's edge every point is clamped inside it, like every spawn point
	var mb: MapBase = w["map"]
	(w["hero"] as Node3D).global_position = Vector3(mb.arena_radius - 3.0, 0.0, 0.0)
	assert_int(dir._spawn_group(d.id, 24, "ring", 5, null, "", {})).is_equal(24)
	for p: Vector3 in _positions(em):
		assert_float(Vector2(p.x, p.z).length()).is_less_equal(mb.arena_radius - 1.5 + 0.001)


func test_a_roster_row_with_pattern_ring_rings_the_hero_with_its_pack() -> void:
	var d := _test_def("p57_row", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	# a burst as big as the room handed in, so the room is what limits each call
	var dir := _director(w, _tl({"burst_min": 20, "burst_max": 20}))
	dir._rng.seed = 11
	# a row's spawn is its pack: eight load units of room, a pack of 8, one ring of 8 (with the row's overrides on)
	var left := dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 8, "pattern": "ring", "stats": {"hp": 33}}], 8.0, 300)
	assert_int(left).is_equal(292)
	_assert_ring(_positions(em), Vector3.ZERO, 8)
	for i in _alive_indices(em):
		assert_float(em.hp[i]).is_equal_approx(33.0, 0.001)
	_clear(em)
	# the cap rules as they are: the room cuts the ring (three load units, three of the pack of 8)
	dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 8, "pattern": "ring"}], 3.0, 300)
	_assert_ring(_positions(em), Vector3.ZERO, 3)


func test_a_wave_with_pattern_ring_sends_its_burst_as_one_ring() -> void:
	var d := _test_def("p57_wring", "skeleton", {"pack_size": 4, "cap_share": 0.5})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"waves": [{"id": "ring", "t": 0, "count": 20, "burst": 20, "every": 0, "pattern": "ring",
		"respect_cap": false, "enemy": d.id, "pack": 4}]}))
	dir._rng.seed = 13
	Run.elapsed = 0.0
	dir._tick_waves()
	_assert_ring(_positions(em), Vector3.ZERO, 20)
	assert_int(int(dir.wave_state("ring")["spawned"])).is_equal(20)


# ---------------------------------------------------------------- in front

func test_in_front_spawns_in_the_top_wedge_whatever_spawn_sides_says() -> void:
	var w := _world(Vector3(4.0, 0.0, 6.0))
	var hero: Node3D = w["hero"]
	var center := hero.global_position
	# the settings send everything from the bottom of the screen; in_front still comes from the top
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "bottom": 100}}))
	dir._rng.seed = 21
	var below := 0
	for k in range(200):
		if dir._spawn_point().z > center.z:
			below += 1
	assert_int(below).is_equal(200)
	for k in range(200):
		var p := dir._in_front_point()
		assert_float(_flat(p, center).length()).is_between(18.99, 24.01)
		assert_float(_deg_from(p, center, Vector3.FORWARD)).is_less_equal(45.01)
	# the old facing rule with the hero facing down the screen (south, +Z): the usual spawns come from behind the camera's
	# top, in_front from the top all the same
	dir.timeline = _tl({"spawn_sides": {"mode": "facing", "facing_share": 1.0, "facing_spread_deg": 30}})
	hero.set("facing", PI)
	for k in range(100):
		assert_float(_deg_from(dir._spawn_point(), center, Vector3.BACK)).is_less_equal(30.01)
	var left_side := 0
	var right_side := 0
	for k in range(300):
		var p := dir._in_front_point()
		assert_float(_flat(p, center).length()).is_between(18.99, 24.01)
		assert_float(_deg_from(p, center, Vector3.FORWARD)).is_less_equal(45.01)
		if p.x < center.x:
			left_side += 1
		else:
			right_side += 1
	# spread across the whole wedge, both halves of it
	assert_int(left_side).is_greater(90)
	assert_int(right_side).is_greater(90)
	# no block at all: still the top
	dir.timeline = _tl()
	for k in range(50):
		assert_float(_deg_from(dir._in_front_point(), center, Vector3.FORWARD)).is_less_equal(45.01)


func test_in_front_turns_with_the_follow_camera() -> void:
	var w := _world(Vector3.ZERO)
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	(w["g"] as Node).add_child(cam)
	(w["g"] as Node).set("camera", cam)
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "bottom": 100}}))
	dir._rng.seed = 23
	# screen up at yaw PI / 2 is west (-X) in the hero's convention (0 = -Z)
	cam.set("yaw", PI * 0.5)
	for k in range(100):
		assert_float(_deg_from(dir._in_front_point(), Vector3.ZERO, Vector3(-1, 0, 0))).is_less_equal(45.01)


func test_a_wave_with_pattern_in_front_comes_from_the_top() -> void:
	var d := _test_def("p57_wfront", "skeleton", {"pack_size": 4, "cap_share": 0.5})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "bottom": 100},
		"waves": [{"id": "front", "t": 0, "count": 12, "burst": 12, "every": 0, "pattern": "in_front", "respect_cap": false,
			"enemy": d.id, "pack": 4}]}))
	dir._rng.seed = 31
	Run.elapsed = 0.0
	dir._tick_waves()
	var pts := _positions(em)
	assert_int(pts.size()).is_equal(12)
	for p: Vector3 in pts:
		assert_float(p.z).is_less(-10.0)
		assert_float(_deg_from(p, Vector3.ZERO, Vector3.FORWARD)).is_less_equal(45.01)
	# a loose band across the top, each at its own point (not packs of 4 sharing one): wider than any pack spreads
	var spread := 0.0
	for a: Vector3 in pts:
		for b: Vector3 in pts:
			spread = maxf(spread, Vector2(a.x - b.x, a.z - b.z).length())
	assert_float(spread).is_greater(12.0)
	_clear(em)
	# a roster row with in_front goes the same way
	dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 4, "pattern": "in_front"}], 2.0, 300)
	pts = _positions(em)
	assert_int(pts.size()).is_equal(4)
	for p: Vector3 in pts:
		assert_float(_deg_from(p, Vector3.ZERO, Vector3.FORWARD)).is_less_equal(45.01)


func test_a_swarm_event_takes_in_front_and_keeps_its_own_16_m_ring() -> void:
	var d := _test_def("p57_swarm", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "bottom": 100}}))
	dir._rng.seed = 41
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 10, "pattern": "in_front"})
	var pts := _positions(em)
	assert_int(pts.size()).is_equal(10)
	for p: Vector3 in pts:
		assert_float(_deg_from(p, Vector3.ZERO, Vector3.FORWARD)).is_less_equal(45.01)
	assert_array(g.get("toasts")).is_equal(["SWARM!"])
	_clear(em)
	# the swarm's ring is its own, 16 m as it always was (not the rows' 11.7 m)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 8, "pattern": "ring"})
	for p: Vector3 in _positions(em):
		assert_float(Vector2(p.x, p.z).length()).is_between(15.0, 17.0)


func test_the_portal_wave_keeps_a_rows_ring_and_in_front() -> void:
	var d := _test_def("p57_portal", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	# a ring row: still a ring round the hero when the portal wave sends it (the wave's own spots are round him anyway)
	var dir := _director(w, _tl({"roster": [{"t": 0, "enemy": d.id, "weight": 1, "pack": 6, "pattern": "ring"}], "portal_wave": {"count": 6}}))
	dir.phase = WaveDirector.Phase.PORTAL
	Run.elapsed = 10.0
	dir._rng.seed = 61
	assert_int(dir.spawn_portal_wave()).is_equal(6)
	_assert_ring(_positions(em), Vector3.ZERO, 6)
	_clear(em)
	# an in-front row: from the top of the screen, not from all round him
	dir.timeline = _tl({"spawn_sides": {"mode": "sides", "bottom": 100}, "roster": [{"t": 0, "enemy": d.id, "weight": 1, "pack": 3, "pattern": "in_front"}], "portal_wave": {"count": 6}})
	assert_int(dir.spawn_portal_wave()).is_equal(6)
	for p: Vector3 in _positions(em):
		assert_float(_deg_from(p, Vector3.ZERO, Vector3.FORWARD)).is_less_equal(45.01)


func test_an_unknown_pattern_is_still_a_pack() -> void:
	var d := _test_def("p57_odd", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl())
	dir._rng.seed = 51
	assert_int(dir._spawn_group(d.id, 5, "zigzag", 5, null, "", {})).is_equal(5)
	var pts := _positions(em)
	var spread := 0.0
	for a: Vector3 in pts:
		for b: Vector3 in pts:
			spread = maxf(spread, Vector2(a.x - b.x, a.z - b.z).length())
	# one point, spread out a little (a pack), 19-24 m out
	assert_float(spread).is_less(6.0)
	assert_float(Vector2(pts[0].x, pts[0].z).length()).is_between(12.0, 31.0)
	_clear(em)
	# and through a roster row
	dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 4, "pattern": "sideways"}], 4.0, 300)
	pts = _positions(em)
	assert_int(pts.size()).is_equal(4)
	spread = 0.0
	for a: Vector3 in pts:
		for b: Vector3 in pts:
			spread = maxf(spread, Vector2(a.x - b.x, a.z - b.z).length())
	assert_float(spread).is_less(6.0)


func test_the_patterns_survive_the_json_to_tres_import() -> void:
	var d := JsonContent.load_json("res://content/maps/red_canyon/red_canyon.json")
	assert_bool(d.is_empty()).is_false()
	var tl: Dictionary = d["timeline_data"]
	(tl["roster"] as Array)[0]["pattern"] = "ring"
	(tl["roster"] as Array)[1]["pattern"] = "in_front"
	tl["waves"] = [{"id": "p57", "t": 10, "count": 30, "burst": 30, "every": 0, "pattern": "in_front", "enemy": "skeleton"},
		{"id": "p57b", "t": 20, "count": 105, "burst": 105, "every": 0, "pattern": "ring", "respect_cap": false, "enemy": "skeleton"}]
	(tl["events"] as Array).append({"t": 100, "type": "swarm", "enemy": "skeleton", "count": 20, "pattern": "in_front"})
	var res := JsonContent.build("maps", d, "res://content/maps/red_canyon/")
	assert_object(res).is_not_null()
	assert_int(ResourceSaver.save(res, TMP_TRES)).is_equal(OK)
	var back: MapDef = ResourceLoader.load(TMP_TRES, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(back).is_not_null()
	assert_str(str((back.timeline.roster[0] as Dictionary)["pattern"])).is_equal("ring")
	assert_str(str((back.timeline.roster[1] as Dictionary)["pattern"])).is_equal("in_front")
	assert_str(str((back.timeline.waves[0] as Dictionary)["pattern"])).is_equal("in_front")
	assert_str(str((back.timeline.waves[1] as Dictionary)["pattern"])).is_equal("ring")
	var ev: Dictionary = back.timeline.events[back.timeline.events.size() - 1]
	assert_str(str(ev["pattern"])).is_equal("in_front")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_TRES))
