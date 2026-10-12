extends GdUnitTestSuite

## Pass 54, lane WD (the wave data, docs/waves_schema.md "Pass 54 additions"): the timeline reads creature_damage_mult,
## spawn_sides, hp_curve and damage_curve; sample_points and curve_mult (points, and the linear / power / exponential
## formulas, the power one the old hp_growth / hp_power ramp); a roster row's presence keyframes (`weights`) replace the
## old weight / weight_late slide, which old rows still play; a row at weight 0 is never drawn; the spawn sides put 55 %
## of the spawns up the screen (camera space, the follow camera's yaw too) and the facing mode keeps the old rule; every
## creature and boss JSON carries its own contact knockback and EnemyDef.hit_knockback() falls back on the rule from its
## damage; a row's stats set the knockback, multiply it (knockback_mult), merge a variance block and carry elite_weight /
## elite_formats, which the random Elite draw and its arrival read; Red Canyon in the new shape.

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
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func enemy_shot_straight(_a, _b, _c, _d, _e, _f = {}) -> void:
	pass
func enemy_spit(_a, _b, _c, _d, _e, _f = {}) -> void:
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
var hits := 0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
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


## A fake game round a fake hero at `hero_at` with a plain map and the real crowd.
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
	return {"g": g, "hero": hero, "em": em}


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


func _modded(em: EnemyManager) -> int:
	var n := 0
	for i in _alive_indices(em):
		if em.elite_idx[i] >= 0:
			n += 1
	return n


func _max_spread(em: EnemyManager, idx: Array) -> float:
	var best := 0.0
	for a in idx:
		for b in idx:
			best = maxf(best, Vector2(em.pos[a].x - em.pos[b].x, em.pos[a].z - em.pos[b].z).length())
	return best


## `n` spawn points from the director.
func _points(dir: WaveDirector, n: int) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(dir._spawn_point())
	return out


## The share of `pts` (round the origin) within `half_deg` of the direction `axis`.
func _share_in_arc(pts: Array, axis: Vector3, half_deg: float = 45.0) -> float:
	var n := 0
	for p: Vector3 in pts:
		var flat := Vector3(p.x, 0.0, p.z).normalized()
		if rad_to_deg(flat.angle_to(axis)) <= half_deg:
			n += 1
	return float(n) / float(maxi(pts.size(), 1))


# ---------------------------------------------------------------- the timeline's new keys

func test_the_timeline_reads_the_pass_54_keys() -> void:
	var tl := JsonContent.timeline_from_dict({"creature_damage_mult": 1.25,
		"spawn_sides": {"mode": "sides", "top": 55, "bottom": 15, "left": 15, "right": 15},
		"hp_curve": {"mode": "points", "points": [[0, 1.0], [600, 3.0]]},
		"damage_curve": {"mode": "formula", "formula": {"kind": "linear", "a": 0.1}}})
	assert_float(tl.creature_damage_mult).is_equal_approx(1.25, 0.0001)
	assert_str(str(tl.spawn_sides["mode"])).is_equal("sides")
	assert_int(int(tl.spawn_sides["top"])).is_equal(55)
	assert_float(tl.hp_mult_at(300.0)).is_equal_approx(2.0, 0.0001)
	assert_float(tl.damage_mult_at(600.0)).is_equal_approx(2.0, 0.0001)
	# nothing said: as every map before this pass
	var plain := JsonContent.timeline_from_dict({})
	assert_float(plain.creature_damage_mult).is_equal(1.0)
	assert_bool(plain.spawn_sides.is_empty()).is_true()
	assert_bool(plain.hp_curve.is_empty()).is_true()
	assert_bool(plain.damage_curve.is_empty()).is_true()
	assert_float(WaveTimeline.new().creature_damage_mult).is_equal(1.0)
	# a block of the wrong shape is no block
	var bad := JsonContent.timeline_from_dict({"spawn_sides": "north", "hp_curve": [1, 2], "damage_curve": 3})
	assert_bool(bad.spawn_sides.is_empty()).is_true()
	assert_bool(bad.hp_curve.is_empty()).is_true()
	assert_bool(bad.damage_curve.is_empty()).is_true()


func test_sample_points_is_linear_between_and_flat_outside() -> void:
	var pts := [[0, 10], [60, 2]]
	assert_float(WaveTimeline.sample_points(pts, 30.0)).is_equal_approx(6.0, 0.0001)
	assert_float(WaveTimeline.sample_points(pts, 90.0)).is_equal_approx(2.0, 0.0001)
	assert_float(WaveTimeline.sample_points(pts, -5.0)).is_equal_approx(10.0, 0.0001)
	assert_float(WaveTimeline.sample_points(pts, 0.0)).is_equal_approx(10.0, 0.0001)
	assert_float(WaveTimeline.sample_points(pts, 60.0)).is_equal_approx(2.0, 0.0001)
	# the .tres round-trips the numbers as floats; a malformed entry is skipped; one point is flat; none is 0
	assert_float(WaveTimeline.sample_points([[0.0, 10.0], "x", [60.0], [60.0, 2.0]], 45.0)).is_equal_approx(4.0, 0.0001)
	assert_float(WaveTimeline.sample_points([[100, 7]], 45.0)).is_equal_approx(7.0, 0.0001)
	assert_float(WaveTimeline.sample_points([], 45.0)).is_equal(0.0)
	# the cap curve reads it, as it always read its points
	var tl := WaveTimeline.new()
	tl.cap_curve = [[0, 10], [300, 66]]
	tl.cap_max = 150
	assert_int(tl.cap_at(150.0, 0)).is_equal(38)
	assert_int(tl.cap_at(900.0, 0)).is_equal(66)


func test_curve_mult_reads_points_and_the_three_formulas() -> void:
	# the power formula is the old hp_growth / hp_power ramp
	var power := {"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}}
	for t: float in [0.0, 300.0, 900.0]:
		assert_float(WaveTimeline.curve_mult(power, t)).is_equal_approx(pow(1.0 + 0.0977 * t / 60.0, 1.25), 0.00001)
	# linear 1 + a*m, exponential (1 + a)^m, m in minutes
	assert_float(WaveTimeline.curve_mult({"mode": "formula", "formula": {"kind": "linear", "a": 0.5}}, 120.0)).is_equal_approx(2.0, 0.0001)
	assert_float(WaveTimeline.curve_mult({"mode": "formula", "formula": {"kind": "exponential", "a": 0.1}}, 120.0)).is_equal_approx(1.21, 0.0001)
	# an unknown kind or mode, or no block, is 1
	assert_float(WaveTimeline.curve_mult({"mode": "formula", "formula": {"kind": "zigzag", "a": 3.0}}, 120.0)).is_equal(1.0)
	assert_float(WaveTimeline.curve_mult({"mode": "sideways", "points": [[0, 5]]}, 10.0)).is_equal(1.0)
	assert_float(WaveTimeline.curve_mult({}, 500.0)).is_equal(1.0)
	assert_float(WaveTimeline.curve_mult({"mode": "points", "points": []}, 500.0)).is_equal(1.0)
	# both blocks present: the mode picks; no mode: the points when there are any, else the formula
	var both := {"mode": "points", "points": [[0, 1.0], [60, 3.0]], "formula": {"kind": "linear", "a": 1.0}}
	assert_float(WaveTimeline.curve_mult(both, 30.0)).is_equal_approx(2.0, 0.0001)
	both["mode"] = "formula"
	assert_float(WaveTimeline.curve_mult(both, 30.0)).is_equal_approx(1.5, 0.0001)
	both.erase("mode")
	assert_float(WaveTimeline.curve_mult(both, 30.0)).is_equal_approx(2.0, 0.0001)
	assert_float(WaveTimeline.curve_mult({"formula": {"kind": "linear", "a": 1.0}}, 30.0)).is_equal_approx(1.5, 0.0001)
	# the formula's own defaults are Red Canyon's HP ramp
	assert_float(WaveTimeline.curve_mult({"mode": "formula"}, 300.0)).is_equal_approx(pow(1.0 + 0.0977 * 5.0, 1.25), 0.00001)


func test_hp_and_damage_follow_their_curves_or_the_old_pair() -> void:
	var tl := WaveTimeline.new()
	tl.hp_growth = 0.08
	tl.hp_power = 1.2
	# no curve: the old ramp, and no time growth on damage
	assert_float(tl.hp_mult_at(600.0)).is_equal_approx(pow(1.8, 1.2), 0.00001)
	assert_float(tl.damage_mult_at(600.0)).is_equal(1.0)
	tl.hp_curve = {"mode": "points", "points": [[0, 1.0], [300, 2.0], [600, 4.0]]}
	assert_float(tl.hp_mult_at(450.0)).is_equal_approx(3.0, 0.0001)
	assert_float(tl.hp_mult_at(9000.0)).is_equal_approx(4.0, 0.0001)
	tl.damage_curve = {"mode": "points", "points": [[0, 1.0], [600, 1.5]]}
	assert_float(tl.damage_mult_at(300.0)).is_equal_approx(1.25, 0.0001)


# ---------------------------------------------------------------- presence keyframes

func test_presence_keyframes_set_a_rows_weight_and_old_rows_still_slide() -> void:
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.timeline = _tl({"weight_late_t": 600})
	var row := {"t": 0, "enemy": "skeleton", "weights": [[0, 10], [60, 2]]}
	assert_float(d._roster_weight(row, 30.0)).is_equal_approx(6.0, 0.0001)
	assert_float(d._roster_weight(row, 90.0)).is_equal_approx(2.0, 0.0001)
	# a negative keyframe never draws backwards; an empty list is the old shape (weight 1 without a weight)
	assert_float(d._roster_weight({"weights": [[0, -3]]}, 10.0)).is_equal(0.0)
	assert_float(d._roster_weight({"t": 0, "weights": []}, 10.0)).is_equal_approx(1.0, 0.0001)
	# the old shape: weight sliding to weight_late by weight_late_t from the row's own t
	var old := {"t": 0, "enemy": "skeleton", "weight": 10, "weight_late": 2}
	assert_float(d._roster_weight(old, 300.0)).is_equal_approx(6.0, 0.0001)
	assert_float(d._roster_weight(old, 900.0)).is_equal_approx(2.0, 0.0001)
	assert_float(d._roster_weight({"t": 0, "weight": 4}, 300.0)).is_equal_approx(4.0, 0.0001)
	# the conversion the editor and Red Canyon use, [[t, weight], [weight_late_t, weight_late]], draws the same
	var conv := {"t": 100, "weights": [[100, 10], [600, 2]]}
	var legacy := {"t": 100, "weight": 10, "weight_late": 2}
	for t: float in [100.0, 250.0, 433.0, 600.0, 1200.0]:
		assert_float(d._roster_weight(conv, t)).is_equal_approx(d._roster_weight(legacy, t), 0.0001)


func test_a_row_at_weight_zero_is_never_drawn() -> void:
	var a := _test_def("w54_zero", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var b := _test_def("w54_live", "skeleton", {"pack_size": 1, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"burst_min": 6, "burst_max": 6}))
	dir._rng.seed = 54
	Run.elapsed = 30.0
	# a row that fades in from 0 at 60 s is not there yet at 30 s
	var rows := [{"t": 0, "enemy": a.id, "weights": [[0, 0], [60, 0], [120, 5]]}, {"t": 0, "enemy": b.id, "weights": [[0, 3]]}]
	for k in range(10):
		dir._burst_from(rows, 6.0, 300)
	assert_int(em.alive_of(a.id)).is_equal(0)
	assert_int(em.alive_of(b.id)).is_equal(60)
	# every row at 0: nothing comes and the bodies are left as they were
	var left := dir._burst_from([rows[0]], 6.0, 300)
	assert_int(left).is_equal(300)
	# the portal wave's draw too
	assert_bool(dir._weighted_row([rows[0]]).is_empty()).is_true()
	for k in range(20):
		assert_str(str(dir._weighted_row(rows)["enemy"])).is_equal(b.id)
	# from 120 s the faded-in row draws as well
	Run.elapsed = 130.0
	for k in range(10):
		dir._burst_from(rows, 6.0, 300)
	assert_int(em.alive_of(a.id)).is_greater(0)


# ---------------------------------------------------------------- the spawn sides

func test_the_spawn_sides_put_most_spawns_up_the_screen() -> void:
	var w := _world(Vector3.ZERO)
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "top": 55, "bottom": 15, "left": 15, "right": 15}}))
	dir._rng.seed = 54
	var pts := _points(dir, 400)
	# 19-24 m out, on the four arcs by weight: top (north, -Z, up the fixed camera's screen) 55 %, the others 15 % each
	for p: Vector3 in pts:
		assert_float(Vector2(p.x, p.z).length()).is_between(18.99, 24.01)
	assert_float(_share_in_arc(pts, Vector3.FORWARD)).is_between(0.45, 0.65)
	assert_float(_share_in_arc(pts, Vector3.BACK)).is_between(0.07, 0.23)
	assert_float(_share_in_arc(pts, Vector3.LEFT)).is_between(0.07, 0.23)
	assert_float(_share_in_arc(pts, Vector3.RIGHT)).is_between(0.07, 0.23)
	# more than 8 m up the screen: the whole top arc and the upper ends of the two side arcs (about 63 %)
	var up := 0
	for p: Vector3 in pts:
		if p.z < -8.0:
			up += 1
	assert_float(float(up) / 400.0).is_between(0.5, 0.72)
	# whichever way the hero faces: the sides are the screen's
	(w["hero"] as Node3D).set("facing", -PI * 0.5)
	assert_float(_share_in_arc(_points(dir, 400), Vector3.FORWARD)).is_between(0.45, 0.65)
	# one side alone: every point on it (a missing side weighs 0)
	dir.timeline = _tl({"spawn_sides": {"mode": "sides", "top": 100}})
	for p: Vector3 in _points(dir, 100):
		assert_float(p.z).is_less(0.0)
	dir.timeline = _tl({"spawn_sides": {"mode": "sides", "right": 1}})
	for p: Vector3 in _points(dir, 100):
		assert_float(p.x).is_greater(0.0)
	dir.timeline = _tl({"spawn_sides": {"mode": "sides", "left": 1, "bottom": 0}})
	for p: Vector3 in _points(dir, 100):
		assert_float(p.x).is_less(0.0)
	dir.timeline = _tl({"spawn_sides": {"mode": "sides", "bottom": 2.5}})
	for p: Vector3 in _points(dir, 100):
		assert_float(p.z).is_greater(0.0)


func test_the_follow_camera_turns_the_sides_with_it() -> void:
	var w := _world(Vector3.ZERO)
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	(w["g"] as Node).add_child(cam)
	(w["g"] as Node).set("camera", cam)
	# the camera looks west (a yaw of 90 degrees in the hero's convention, forward = (-sin, 0, -cos)): up the screen is -X
	cam.set("yaw", PI * 0.5)
	var dir := _director(w, _tl({"spawn_sides": {"mode": "sides", "top": 1}}))
	dir._rng.seed = 7
	for p: Vector3 in _points(dir, 100):
		assert_float(p.x).is_less(0.0)
		assert_float(absf(p.z)).is_less_equal(-p.x + 0.001)


func test_the_facing_mode_and_a_timeline_without_sides_keep_the_old_rule() -> void:
	var w := _world(Vector3.ZERO)
	var hero: Node3D = w["hero"]
	# the hero faces east: his forward is (-sin(facing), 0, -cos(facing))
	hero.set("facing", -PI * 0.5)
	var east := Vector3(1, 0, 0)
	for tl: WaveTimeline in [_tl({"spawn_sides": {"mode": "facing"}}), _tl({}), _tl({"spawn_sides": {"mode": "sides"}})]:
		var dir := _director(w, tl)
		dir._rng.seed = 11
		# 70 % within 60 degrees of where he faces, and a third of the other 30 % lands there too: about 80 %
		assert_float(_share_in_arc(_points(dir, 400), east, 60.0)).is_between(0.72, 0.88)
	# the block's own share and spread
	var narrow := _director(w, _tl({"spawn_sides": {"mode": "facing", "facing_share": 1.0, "facing_spread_deg": 20}}))
	for p: Vector3 in _points(narrow, 100):
		assert_float(rad_to_deg(Vector3(p.x, 0.0, p.z).normalized().angle_to(east))).is_less(20.01)
	# the Elite bosses keep the old rule whatever the sides say (the schema: "placed as before"), the roster does not
	var eb := _director(w, _tl({"spawn_sides": {"mode": "sides", "top": 1, "facing_share": 1.0, "facing_spread_deg": 10}}))
	for p: Vector3 in _points(eb, 50):
		assert_float(p.z).is_less(0.0)
	eb._spawn_elite_boss("dune_scorpion")
	var em: EnemyManager = w["em"]
	assert_int(eb.elite_index).is_greater_equal(0)
	var at: Vector3 = em.pos[eb.elite_index]
	assert_float(rad_to_deg(Vector3(at.x, 0.0, at.z).normalized().angle_to(east))).is_less(10.01)


# ---------------------------------------------------------------- the damage multipliers

func test_the_director_hands_the_crowd_the_damage_multipliers() -> void:
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"creature_damage_mult": 1.25, "damage_curve": {"mode": "points", "points": [[0, 1.0], [600, 2.0]]}}))
	Run.elapsed = 300.0
	dir._apply_mults()
	if "creature_damage_mult" in em:
		assert_float(float(em.get("creature_damage_mult"))).is_equal_approx(1.25, 0.0001)
		assert_float(float(em.get("damage_time_mult"))).is_equal_approx(1.5, 0.0001)
		# the debug arena plays creatures at their data's damage (its dummies say what they bite for)
		Run.arena = true
		dir._apply_mults()
		assert_float(float(em.get("creature_damage_mult"))).is_equal_approx(1.0, 0.0001)
		Run.arena = false
	else:
		# lane C's EnemyManager fields are not in yet: the director's set() is a quiet no-op
		assert_bool(em.get("creature_damage_mult") == null).is_true()
	# Red Canyon's own: creatures hit 25 % harder (pass 62, lane PC); the ATK x curve is Garry's to tune in the Level
	# Editor (pass 68 re-pin: flat at 1 through stage 1 until his 2026-10-12 retune, 1.21 since, stages 2 and 3 above it),
	# so the test reads the map file: a positive multiplier everywhere, and the King's second (430) on stage 1's side of
	# any step there
	var rc: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(rc.creature_damage_mult).is_equal_approx(1.25, 0.0001)
	for t: float in [0.0, 300.0, 430.0, 1290.0, 3000.0]:
		assert_float(rc.damage_mult_at(t)).is_greater(0.0)
	assert_float(rc.damage_mult_at(430.0)).is_equal_approx(rc.damage_mult_at(429.0), 0.005)


# ---------------------------------------------------------------- the knockback numbers

func test_a_creature_carries_its_own_knockback_or_the_rule_from_its_damage() -> void:
	assert_float(EnemyDef.default_knockback(4.0)).is_equal_approx(3.4, 0.0001)
	assert_float(EnemyDef.default_knockback(3.0)).is_equal_approx(3.4 * sqrt(0.75), 0.0001)
	assert_float(EnemyDef.default_knockback(16.0)).is_equal_approx(6.8, 0.0001)
	# never under the old 2.5, never over 7
	assert_float(EnemyDef.default_knockback(0.0)).is_equal_approx(2.5, 0.0001)
	assert_float(EnemyDef.default_knockback(-5.0)).is_equal_approx(2.5, 0.0001)
	assert_float(EnemyDef.default_knockback(100.0)).is_equal_approx(7.0, 0.0001)
	# the JSON's own number, else 0 and the rule
	var own := JsonContent.build("enemies", {"id": "w54_kb", "damage": 4, "knockback": 5.5}, "res://content/enemies/skeleton/") as EnemyDef
	assert_float(own.knockback).is_equal_approx(5.5, 0.0001)
	assert_float(own.hit_knockback()).is_equal_approx(5.5, 0.0001)
	var none := JsonContent.build("enemies", {"id": "w54_kb0", "damage": 9}, "res://content/enemies/skeleton/") as EnemyDef
	assert_float(none.knockback).is_equal(0.0)
	assert_float(none.hit_knockback()).is_equal_approx(5.1, 0.0001)
	# every creature and boss of the content carries its own number now (tools/set_knockback.py), the dummies excepted
	var n := 0
	for k in Registry.enemies.keys():
		var id := str(k)
		if id.begins_with("training_dummy"):
			continue
		var e: EnemyDef = Registry.enemies[k]
		assert_float(e.knockback).override_failure_message(id + " has no knockback of its own").is_greater(0.0)
		n += 1
	assert_int(n).is_greater(30)
	for id in ["tumbleweed_king", "gila_grande", "brander"]:
		assert_float(Registry.enemy(id).knockback).is_greater(0.0)
	# written right after the damage, in the creature's own JSON
	for id in ["skeleton", "dust_mummy", "rocketeer", "buckshot_dwarf", "fire_ant"]:
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/%s/%s.json" % [id, id]))
		var keys: Array = j.keys()
		assert_int(keys.find("knockback")).override_failure_message(id).is_equal(keys.find("damage") + 1)


func test_a_rows_stats_set_and_multiply_the_knockback() -> void:
	var d := EnemyDef.new()
	d.id = "w54_kbsrc"
	d.damage = 4.0
	d.charge = {"knockback": 5.0}
	# none of its own: the rule from its damage, 3.4
	assert_float(d.hit_knockback()).is_equal_approx(3.4, 0.0001)
	assert_float(d.with_overrides({"knockback": 6}).hit_knockback()).is_equal_approx(6.0, 0.0001)
	# knockback_mult multiplies the contact knockback (from the rule when the creature has none) and the blocks
	var v := d.with_overrides({"knockback_mult": 2.0})
	assert_float(v.hit_knockback()).is_equal_approx(6.8, 0.0001)
	assert_float(float(v.charge["knockback"])).is_equal_approx(10.0, 0.0001)
	assert_float(d.with_overrides({"knockback": 3.0, "knockback_mult": 1.5}).hit_knockback()).is_equal_approx(4.5, 0.0001)
	# a multiplier of 0 shoves nothing (a knockback of exactly 0 would mean "the rule")
	assert_float(d.with_overrides({"knockback_mult": 0.0}).hit_knockback()).is_less(0.01)
	# a row that changes the damage and says nothing of the knockback: the rule from the new damage
	assert_float(d.with_overrides({"damage": 16}).hit_knockback()).is_equal_approx(6.8, 0.0001)
	# the source keeps its own
	assert_float(d.knockback).is_equal(0.0)
	assert_float(float(d.charge["knockback"])).is_equal_approx(5.0, 0.0001)


# ---------------------------------------------------------------- the variance and elite block per row

func test_a_rows_stats_merge_variance_and_carry_the_elite_settings() -> void:
	var d := EnemyDef.new()
	d.id = "w54_var"
	d.variance = {"size": 0.12, "speed": 0.1, "tints": ["#111111", "#222222"], "tint_strength": 0.22,
		"special_chance": 0.08, "special": {"size": 1.3, "hp": 1.6, "tint": "#abcdef"}}
	var v := d.with_overrides({"variance": {"special_chance": 0.5, "tints": ["#333333"], "special": {"tint": "#123456"}}})
	assert_float(float(v.variance["special_chance"])).is_equal_approx(0.5, 0.0001)
	assert_float(float(v.variance["size"])).is_equal_approx(0.12, 0.0001)
	assert_array(v.variance["tints"]).is_equal(["#333333"])
	var sp: Dictionary = v.variance["special"]
	assert_str(str(sp["tint"])).is_equal("#123456")
	assert_float(float(sp["hp"])).is_equal_approx(1.6, 0.0001)
	# the source keeps its own
	assert_float(float(d.variance["special_chance"])).is_equal_approx(0.08, 0.0001)
	assert_str(str((d.variance["special"] as Dictionary)["tint"])).is_equal("#abcdef")
	assert_int((d.variance["tints"] as Array).size()).is_equal(2)
	# the elite settings: weight 1 and a single arrival unless the row says
	assert_float(d.elite_weight).is_equal(1.0)
	assert_bool(d.elite_formats.is_empty()).is_true()
	var e := d.with_overrides({"elite_weight": 0, "elite_formats": {"pack": 1, "ring": 2}})
	assert_float(e.elite_weight).is_equal(0.0)
	assert_int(int(e.elite_formats["ring"])).is_equal(2)
	assert_float(d.with_overrides({"hp": 5}).elite_weight).is_equal(1.0)
	assert_float(d.with_overrides({"elite_weight": -3}).elite_weight).is_equal(0.0)
	# two rows that differ only there are two types
	var k1 := d.with_overrides({"elite_weight": 2}).type_key()
	var k2 := d.with_overrides({"elite_weight": 3}).type_key()
	var k3 := d.with_overrides({"variance": {"special_chance": 0.2}}).type_key()
	assert_str(k1).is_not_equal(k2)
	assert_str(k1).is_not_equal(k3)
	# an Elite candidate needs a weight above 0 and a creature that may be one
	var c := _test_def("w54_cand", "skeleton")
	var cands := WaveDirector.elite_candidates([{"enemy": c.id, "stats": {"elite_weight": 0}}, {"enemy": c.id}, {"enemy": "spit_cactus"}])
	assert_int(cands.size()).is_equal(1)
	assert_bool((cands[0] as Dictionary).has("stats")).is_false()


func test_a_random_elite_comes_from_the_rows_by_their_elite_weight() -> void:
	var a := _test_def("w54_never", "skeleton", {"pack_size": 1})
	var b := _test_def("w54_always", "skeleton", {"pack_size": 1})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [{"t": 0, "enemy": a.id, "weights": [[0, 50]], "stats": {"elite_weight": 0}},
		{"t": 0, "enemy": b.id, "weights": [[0, 1]]}]}))
	dir._rng.seed = 5
	Run.elapsed = 10.0
	for k in range(12):
		dir._spawn_elite("", "")
	assert_int(em.alive_of(a.id)).is_equal(0)
	assert_int(em.alive_of(b.id)).is_equal(12)
	assert_int(_modded(em)).is_equal(12)
	var toasts: Array = (w["g"] as Node).get("toasts")
	assert_int(toasts.size()).is_equal(12)
	# by weight, not evenly: 1 against 3
	var rows := [{"enemy": a.id, "stats": {"elite_weight": 1}}, {"enemy": b.id, "stats": {"elite_weight": 3}}]
	var hits := 0
	for k in range(400):
		if str(dir._weighted_elite_row(rows)["enemy"]) == b.id:
			hits += 1
	assert_float(float(hits) / 400.0).is_between(0.66, 0.84)


func test_an_elite_row_may_send_its_whole_pack_or_a_ring_all_wearing_the_modifier() -> void:
	var d := _test_def("w54_fmt", "skeleton", {"pack_size": 4})
	var mod_id := str(Registry.elites.keys()[0])
	# pack: the row's pack (its own 5 here) at one spawn point, every one modified, one toast
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [{"t": 0, "enemy": d.id, "weights": [[0, 1]], "pack": 5, "stats": {"elite_formats": {"pack": 1}}}]}))
	Run.elapsed = 10.0
	dir._spawn_elite("", mod_id)
	var idx := _alive_indices(em)
	assert_int(idx.size()).is_equal(5)
	assert_int(_modded(em)).is_equal(5)
	assert_float(_max_spread(em, idx)).is_less(8.0)
	var toasts: Array = (w["g"] as Node).get("toasts")
	assert_int(toasts.size()).is_equal(1)
	assert_str(str(toasts[0])).contains("×5")
	# ring: the creature's pack (4) round the hero, 12 m out
	var w2 := _world(Vector3.ZERO)
	var em2: EnemyManager = w2["em"]
	var dir2 := _director(w2, _tl({"roster": [{"t": 0, "enemy": d.id, "weights": [[0, 1]], "stats": {"elite_formats": {"ring": 1}}}]}))
	dir2._spawn_elite("", mod_id)
	var ring := _alive_indices(em2)
	assert_int(ring.size()).is_equal(4)
	assert_int(_modded(em2)).is_equal(4)
	for i in ring:
		assert_float(Vector2(em2.pos[i].x, em2.pos[i].z).length()).is_equal_approx(WaveDirector.ELITE_RING_RADIUS, 0.05)
	# single: the default, and what a row whose formats are all 0 gets
	var w3 := _world(Vector3.ZERO)
	var em3: EnemyManager = w3["em"]
	var dir3 := _director(w3, _tl({"roster": [{"t": 0, "enemy": d.id, "weights": [[0, 1]], "stats": {"elite_formats": {"pack": 0, "ring": 0}}}]}))
	dir3._spawn_elite("", mod_id)
	assert_int(_alive_indices(em3).size()).is_equal(1)
	assert_int(_modded(em3)).is_equal(1)
	var t3: Array = (w3["g"] as Node).get("toasts")
	assert_str(str(t3[0])).not_contains("×")


# ---------------------------------------------------------------- Red Canyon

func test_red_canyon_in_the_pass_54_shape() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(tl.creature_damage_mult).is_equal_approx(1.25, 0.0001)
	# pass 56 (re-pinned): Garry switched the map back to the facing rule in the Level Editor (2026-10-07); the side
	# weights stay in the file for when he switches again
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var mode := str(tl.spawn_sides.get("mode", ""))
	assert_bool(["sides", "facing"].has(mode)).is_true()
	assert_str(mode).is_equal(str(((d["timeline_data"] as Dictionary)["spawn_sides"] as Dictionary).get("mode", "")))
	assert_int(int(tl.spawn_sides.get("top", 0))).is_equal(55)
	for s in ["bottom", "left", "right"]:
		assert_int(int(tl.spawn_sides.get(s, 0))).is_equal(15)
	# the HP curve's formula is the old ramp (the pair is kept beside it), and its points agree at the stage marks
	assert_str(str(tl.hp_curve.get("mode", ""))).is_equal("formula")
	for t: float in [0.0, 300.0, 430.0, 900.0, 1290.0]:
		assert_float(tl.hp_mult_at(t)).is_equal_approx(pow(1.0 + tl.hp_growth * t / 60.0, tl.hp_power), 0.00001)
	var pts: Array = tl.hp_curve.get("points", [])
	assert_int(pts.size()).is_equal(4)
	for p in pts:
		var at := float(p[0])
		assert_float(float(p[1])).is_equal_approx(pow(1.0 + 0.0977 * at / 60.0, 1.25), 0.0001)
	# every roster row is in the new shape: presence keyframes and a label of its own
	var ids: Dictionary = {}
	for r in tl.roster:
		var row: Dictionary = r
		assert_bool(row.has("weights")).override_failure_message(str(row)).is_true()
		assert_bool(row.has("weight") or row.has("weight_late")).override_failure_message(str(row)).is_false()
		var rid := str(row.get("id", ""))
		assert_bool(rid.begins_with("r")).override_failure_message(str(row)).is_true()
		assert_bool(ids.has(rid)).override_failure_message("two rows are " + rid).is_false()
		ids[rid] = true
	# and the director draws from them
	var w := _world(Vector3.ZERO)
	var dir := _director(w, tl)
	Run.elapsed = 30.0
	var open: Array = tl.roster_at(30.0)
	assert_bool(open.is_empty()).is_false()
	var total := 0.0
	for r in open:
		total += dir._roster_weight(r, 30.0)
	assert_float(total).is_greater(0.0)
