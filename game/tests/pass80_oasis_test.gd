extends GdUnitTestSuite

## Pass 80, lane OASIS (Garry: "make the water slow everyone down when they walk though it, not by a lot, just 10%. And
## make it so there are 2 oasis at least per level generation in the red canyon, sometimes 3"): Red Canyon rolls two
## oases a run and a third in about a third of the runs (timeline_data `oases`, RedCanyon._roll_oases), each with its
## dish, damp ring, disc and greenery, apart from each other, the flats and the dry river; every caller of the water
## reads every lake (in_water, water_level(p), water_disc(p), lakes(); EnemyManager.map_lakes / lakes_of); anyone
## walking in water moves at 1 - water_slow (0.1) of his walking speed (Player._wade_mult, EnemyManager._wade_mult),
## never in the air, under the sand or by a push.

const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
const LAUNCH := "user://debug_launch.json"
const DT := 1.0 / 60.0

## a fake game for a crowd (pass54_combat_test's)
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
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
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
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

## two lakes as Red Canyon names them (lakes()): 4 m at (10, 0) and 3 m at (-12, 20)
const FAKE_TWO_LAKES := """extends MapBase
func lakes() -> Array:
	return [{"center": Vector2(10, 0), "radius": 4.0, "level": 0.0, "floor": -0.4, "disc": {"center": Vector2(10, 0), "top": 0.04, "radius": 4.24, "thick": 0.08}},
		{"center": Vector2(-12, 20), "radius": 3.0, "level": 0.2, "floor": -0.2, "disc": {"center": Vector2(-12, 20), "top": 0.24, "radius": 3.18, "thick": 0.08}}]
func lake_center() -> Vector2:
	return Vector2(10, 0)
func lake_radius() -> float:
	return 4.0
func in_water(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Vector2(10, 0)) < 4.08 or Vector2(p.x, p.z).distance_to(Vector2(-12, 20)) < 3.06
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.arena_next = false
	Run.end()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.forced_map_seed = 0
	Run.arena = false
	Run.arena_next = false
	Run.debug_clear_items()
	Run.end()
	if FileAccess.file_exists(LAUNCH):
		DirAccess.remove_absolute(LAUNCH)


## Red Canyon's roll for `seed` alone (no terrain, no scenery): the map node, not in the tree (free it).
func _roll(ms: int) -> Node3D:
	var m: Node3D = (Registry.map("red_canyon").scene as PackedScene).instantiate()
	m.set("run_seed", ms)
	(m.get("_rng") as RandomNumberGenerator).seed = ms
	var nz: FastNoiseLite = m.get("_noise")
	nz.seed = ms
	nz.frequency = 0.045
	nz.fractal_octaves = 3
	m.set("flats_center", Vector3(0, 0, 8))
	m.call("_roll_layout")
	return m


## The whole map for `seed`, in the tree.
func _canyon(ms: int) -> MapBase:
	Run.forced_map_seed = ms
	Run.end()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	return m


# ---------------------------------------------------------------- the roll

func test_every_seed_rolls_two_oases_and_a_third_about_a_third_of_the_time() -> void:
	var n := 400
	var threes := 0
	var cfg: Dictionary = WaveTimeline.OASES_DEFAULTS
	for s in range(1, n + 1):
		var m := _roll(s)
		var lakes: Array = m.call("lakes")
		assert_int(lakes.size()).override_failure_message("seed %d: %d lakes" % [s, lakes.size()]).is_between(2, 3)
		if lakes.size() == 3:
			threes += 1
		var fc := Vector2(0, 8)
		for i in lakes.size():
			var a: Dictionary = lakes[i]
			var c: Vector2 = a["center"]
			var r: float = a["radius"]
			assert_float(r).is_between(RED_CANYON.LAKE_R.x, RED_CANYON.LAKE_R.y)
			# off the flats (and the start in their middle), off the dry river's bed, inside the wall with room to walk round
			assert_float(c.distance_to(fc)).override_failure_message("seed %d: lake %d on the flats" % [s, i]).is_greater_equal(float(m.get("flats_radius")) + r + 8.0 - 0.001)
			assert_float(float(m.call("_river_dist", c))).override_failure_message("seed %d: lake %d on the river" % [s, i]).is_greater_equal(float(m.get("river_width")) * 0.5 + r + 5.0 - 0.001)
			assert_float(c.length() + r * RED_CANYON.LAKE_DISH).is_less(float(m.get("arena_radius")) - 5.0)
			# apart: every two dishes the gap of open ground apart
			for j in range(i):
				var b: Dictionary = lakes[j]
				var gap: float = c.distance_to(b["center"]) - (r + float(b["radius"])) * RED_CANYON.LAKE_DISH
				assert_float(gap).override_failure_message("seed %d: lakes %d and %d %.1f m apart" % [s, j, i, gap]).is_greater_equal(float(cfg["gap"]) - 0.001)
		# the first lake is the one lake of before (lake_center / lake_radius answer it)
		assert_bool((m.call("lake_center") as Vector2).is_equal_approx((lakes[0] as Dictionary)["center"])).is_true()
		m.free()
	# about the named share of three (0.35): 400 seeds put it within 0.25..0.45 (more than three standard deviations)
	var share := float(threes) / float(n)
	assert_float(share).override_failure_message("a third oasis on %.2f of the seeds" % share).is_between(0.25, 0.45)


func test_the_first_oasis_stays_where_the_seed_had_it() -> void:
	# the roll draws the first lake exactly as before pass 80 (the extra lakes after it): seed 5's oasis
	var m := _roll(5)
	var c: Vector2 = m.call("lake_center")
	assert_float(c.x).is_equal_approx(28.5, 0.1)
	assert_float(c.y).is_equal_approx(-2.5, 0.1)
	assert_float(float(m.call("lake_radius"))).is_equal_approx(5.64, 0.01)
	m.free()


func test_the_map_file_sets_the_count() -> void:
	var tl: WaveTimeline = Run.map.timeline
	var keep: Dictionary = tl.oases
	tl.oases = {"min": 3, "max": 3}
	for s in range(1, 41):
		var m := _roll(s)
		assert_int((m.call("lakes") as Array).size()).is_equal(3)
		m.free()
	tl.oases = {"min": 1, "max": 1}
	for s in range(1, 21):
		var m := _roll(s)
		assert_int((m.call("lakes") as Array).size()).is_equal(1)
		m.free()
	# a key left out plays the game's own
	tl.oases = {"extra_chance": 0.0}
	for s in range(1, 21):
		var m := _roll(s)
		assert_int((m.call("lakes") as Array).size()).is_equal(2)
		m.free()
	tl.oases = keep


func test_red_canyon_names_its_oases_and_its_water_slow() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var t: Dictionary = d["timeline_data"]
	assert_float(float(t.get("water_slow", WaveTimeline.WATER_SLOW_DEFAULT))).is_equal_approx(0.1, 0.0001)
	var o: Dictionary = t.get("oases", {})
	assert_int(int(o.get("min", 2))).is_greater_equal(2)
	assert_int(int(o.get("max", 3))).is_greater_equal(int(o.get("min", 2)))
	# the game's defaults are Garry's words: two at least, sometimes three, 10% slower
	assert_float(WaveTimeline.WATER_SLOW_DEFAULT).is_equal_approx(0.1, 0.0001)
	assert_int(int(WaveTimeline.OASES_DEFAULTS["min"])).is_equal(2)
	assert_int(int(WaveTimeline.OASES_DEFAULTS["max"])).is_equal(3)
	assert_float(Run.map.timeline.water_slow).is_equal_approx(0.1, 0.0001)


# ---------------------------------------------------------------- the built map

func test_every_lake_has_its_dish_disc_and_greenery() -> void:
	for ms in [5, 6]:
		var m := _canyon(ms)
		var lakes: Array = m.call("lakes")
		assert_int(lakes.size()).is_equal(3 if ms == 5 else 2)
		var props: PropField = m.get("props")
		for k in lakes.size():
			var l: Dictionary = lakes[k]
			var c: Vector2 = l["center"]
			var r: float = l["radius"]
			var level: float = l["level"]
			# its disc, drawn where water_disc says, at its own level
			var disc_node: MeshInstance3D = m.find_child("Oasis" if k == 0 else "Oasis%d" % (k + 1), true, false)
			assert_object(disc_node).override_failure_message("seed %d: no disc for lake %d" % [ms, k]).is_not_null()
			assert_float(disc_node.position.y).is_equal_approx(level, 0.0001)
			assert_float(Vector2(disc_node.position.x, disc_node.position.z).distance_to(c)).is_less(0.001)
			var cm := disc_node.mesh as CylinderMesh
			assert_float(cm.top_radius).is_equal_approx(r * RED_CANYON.LAKE_DISC, 0.0001)
			var here := Vector3(c.x, level, c.y)
			var disc: Dictionary = m.call("water_disc", here)
			assert_bool((disc["center"] as Vector2).is_equal_approx(c)).is_true()
			assert_float(float(disc["top"])).is_equal_approx(level + RED_CANYON.LAKE_THICK * 0.5, 0.0001)
			assert_float(float(m.call("water_level", here))).is_equal_approx(level, 0.0001)
			assert_int(int(m.call("lake_index", c))).is_equal(k)
			# wadeable: its middle the dish's flat floor, knee-deep under the water's surface; in the water there, not past
			# the edge
			assert_float(m.height_at(c.x, c.y)).is_equal_approx(float(l["floor"]), 0.05)
			assert_float(level - m.height_at(c.x, c.y)).is_between(0.3, 0.5)
			assert_bool(bool(m.call("in_water", here))).is_true()
			assert_bool(bool(m.call("in_water", Vector3(c.x + r * 1.5, level, c.y)))).is_false()
			for o: Vector3 in m.obstacles:
				assert_bool(Vector2(o.x, o.y).distance_to(c) > r * 0.5 or o.z < r * 0.5).override_failure_message("a collider in lake %d" % k).is_true()
			# palms at its shore
			var palms := 0
			for row: Dictionary in props.placed:
				var rp: Vector3 = row["pos"]
				if str(row["id"]) == "fan_palm" and Vector2(rp.x, rp.z).distance_to(c) < r + 5.5:
					palms += 1
			assert_int(palms).override_failure_message("seed %d lake %d: %d palms" % [ms, k, palms]).is_greater_equal(4)
		# one disc a lake, no more
		var discs := 0
		for ch in m.get_children():
			if ch is MeshInstance3D and str(ch.name).begins_with("Oasis"):
				discs += 1
		assert_int(discs).is_equal(lakes.size())
		# no painting stands in any lake
		for row: Dictionary in props.placed:
			var rp: Vector3 = row["pos"]
			assert_bool(bool(m.call("in_water", rp))).override_failure_message("a %s in the water" % row["id"]).is_false()
		# old callers: no argument is the first lake
		assert_float(float(m.call("water_level"))).is_equal_approx(float((lakes[0] as Dictionary)["level"]), 0.0001)
		assert_bool(((m.call("water_disc") as Dictionary)["center"] as Vector2).is_equal_approx(m.call("lake_center"))).is_true()
		m.queue_free()
		await get_tree().process_frame


func test_the_bush_patches_keep_off_every_oasis_and_still_number_five() -> void:
	# seed 11 has three oases and found only four patches before the late tries were relaxed
	for ms in [5, 7, 11]:
		var m := _canyon(ms)
		var patches: Array = m.call("bush_patches")
		assert_int(patches.size()).override_failure_message("seed %d: %d patches" % [ms, patches.size()]).is_between(RED_CANYON.BUSH_PATCHES.x, RED_CANYON.BUSH_PATCHES.y)
		for p: Dictionary in patches:
			var c: Vector2 = p["center"]
			for l: Dictionary in m.call("lakes"):
				assert_float(c.distance_to(l["center"])).is_greater_equal(float(l["radius"]) + RED_CANYON.BUSH_LAKE_NEAR + RED_CANYON.BUSH_PATCH_R * 0.6 - 0.01)
			# and no bush of it in the water
			for b: Dictionary in p["bushes"]:
				var at: Vector2 = b["pos"]
				assert_bool(bool(m.call("in_water", Vector3(at.x, 0, at.y)))).is_false()
		m.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------- the crowd reads every lake

func _world(map_src: String) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	hero.global_position = Vector3(0, 0, -40)
	var mb := MapBase.new()
	if map_src != "":
		mb.set_script(_script(map_src))
	g.add_child(mb)
	g.map = mb
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	em.colour_after_kills = 999999
	return {"g": g, "hero": hero, "em": em, "map": mb}


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	return i


func test_the_crowd_knows_every_lake() -> void:
	var w := _world(FAKE_TWO_LAKES)
	var em: EnemyManager = w["em"]
	assert_bool(em._lake_refresh()).is_true()
	assert_bool(em.in_lake(Vector3(10, 0, 0))).is_true()
	assert_bool(em.in_lake(Vector3(-12, 0, 20))).is_true()
	assert_bool(em.in_lake(Vector3(0, 0, 10))).is_false()
	# the first is still the one lake the old fields name
	assert_bool(em._lake_c.is_equal_approx(Vector2(10, 0))).is_true()
	assert_int(EnemyManager.lakes_of(w["map"]).size()).is_equal(2)
	# a creature's shadow goes in either lake
	var a := _creature(em, Vector3(-12, 0, 20))
	var scf: Vector3 = em._cf_tick
	var xf := em.shadow_xform(a, scf, Vector3(-scf.z, 0, scf.x))
	assert_bool(em.shadow_wet(a, xf, Vector3.INF)).is_true()
	assert_bool(em._near_water(Vector3(-12, 0, 20))).is_true()
	assert_bool(em._near_water(Vector3(40, 0, -40))).is_false()


func test_spawn_rings_keep_out_of_every_lake() -> void:
	var w := _world(FAKE_TWO_LAKES)
	var mb: MapBase = w["map"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# a ring round a hero between the two lakes crosses both
	var hero_at := Vector3(-1, 0, 10)
	var r_ring := Vector2(10, 0).distance_to(Vector2(-1, 10))
	for k in range(20):
		var pts: Array = EnemyManager.ring_spots(hero_at, r_ring, 60, 64.0, rng, rng.randf() * TAU, 0.3, 0.5, mb)
		assert_int(pts.size()).is_equal(60)
		for p: Vector3 in pts:
			assert_bool(mb.in_water(p)).override_failure_message("a ring spot in a lake at %s" % str(p)).is_false()
	# a point ahead in the second lake turns past it
	var from := Vector3(-12, 0, 0)
	var a := 0.0 + PI   # yaw PI: +Z, towards (-12, 20)
	var turns: Array = EnemyManager.lake_turns(mb, from, a, 20.0)
	assert_int(turns.size()).is_equal(2)
	for t: float in turns:
		var q := from + Vector3(-sin(t), 0, -cos(t)) * 20.0
		assert_bool(mb.in_water(q)).is_false()


# ---------------------------------------------------------------- the slow

func test_a_creature_wades_ten_percent_slower() -> void:
	var w := _world("")
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(0, 0, 0)
	em.set_lake(Vector2(12, 0), 4.0)
	em.add_lake(Vector2(-30, 30), 3.0)
	var wet := _creature(em, Vector3(12, 0, 0))
	var dry := _creature(em, Vector3(-12, 0, 0))
	em._wade_tick()
	assert_float(em._wade_slow).is_equal_approx(0.1, 0.0001)
	assert_float(em._wade_mult(wet)).is_equal_approx(0.9, 0.0001)
	assert_float(em._wade_mult(dry)).is_equal_approx(1.0, 0.0001)
	# the second lake too
	em.pos[dry] = Vector3(-30, 0, 30)
	assert_float(em._wade_mult(dry)).is_equal_approx(0.9, 0.0001)
	em._free(dry)
	# one creature (each rolls its own speed) walks at the hero from 12 m on dry sand, then from 12 m out of the lake's
	# middle: in the water it covers 0.9 of the ground
	em.pos[wet] = Vector3(-12, 0, 0)
	em.vel[wet] = Vector3.ZERO
	for k in range(40):
		em._physics_process(DT)
	var went_dry: float = em.pos[wet].x + 12.0
	em.pos[wet] = Vector3(12, 0, 0)
	em.vel[wet] = Vector3.ZERO
	em.kb[wet] = Vector3.ZERO
	for k in range(40):
		em._physics_process(DT)
	var went_wet: float = 12.0 - em.pos[wet].x
	assert_float(went_dry).is_greater(0.5)
	assert_bool(em.in_lake(em.pos[wet])).is_true()
	assert_float(went_wet / went_dry).override_failure_message("wet %.3f m, dry %.3f m" % [went_wet, went_dry]).is_between(0.88, 0.92)


## The crowd's grid and the wading marks as a tick makes them.
func _wade_now(em: EnemyManager) -> void:
	em._rebuild_grid()
	em._wade_tick()


func test_what_is_not_walking_is_not_slowed() -> void:
	var w := _world("")
	var em: EnemyManager = w["em"]
	em.set_lake(Vector2(12, 0), 4.0)
	var i := _creature(em, Vector3(12, 0, 0))
	_wade_now(em)
	assert_float(em._wade_mult(i)).is_equal_approx(0.9, 0.0001)
	assert_float(em._wade_k[i]).is_equal_approx(0.9, 0.0001)
	# in the air (tossed, bounced, launched)
	em.lift_h[i] = 1.0
	_wade_now(em)
	assert_float(em._wade_mult(i)).is_equal(1.0)
	assert_float(em._wade_k[i]).is_equal(1.0)
	em.lift_h[i] = 0.0
	# under the sand, or rising out of it / sinking into it
	em.hidden[i] = 1
	_wade_now(em)
	assert_float(em._wade_mult(i)).is_equal(1.0)
	assert_float(em._wade_k[i]).is_equal(1.0)
	em.hidden[i] = 0
	em.rise_t[i] = 0.5
	_wade_now(em)
	assert_float(em._wade_mult(i)).is_equal(1.0)
	assert_float(em._wade_k[i]).is_equal(1.0)
	em.rise_t[i] = 1.0
	# out of the water again: back to 1 on the next tick
	_wade_now(em)
	assert_float(em._wade_k[i]).is_equal_approx(0.9, 0.0001)
	em.pos[i] = Vector3(20, 0, 0)
	_wade_now(em)
	assert_float(em._wade_k[i]).is_equal(1.0)
	em.pos[i] = Vector3(12, 0, 0)
	# water_slow 0 = off
	var tl: WaveTimeline = Run.map.timeline
	var keep := tl.water_slow
	tl.water_slow = 0.0
	_wade_now(em)
	assert_float(em._wade_mult(i)).is_equal(1.0)
	assert_float(em._wade_k[i]).is_equal(1.0)
	tl.water_slow = keep
	_wade_now(em)
	# a push is never slowed: stunned (no walk, its knockback still carries it), a wader and a dry one thrown alike go as far
	em.pos[i] = Vector3(12, 0, -1.5)
	var dry := _creature(em, Vector3(-30, 0, -31.5))
	var p0: Vector3 = em.pos[i]
	var d0: Vector3 = em.pos[dry]
	for j in [i, dry]:
		em.stun_t[j] = 10.0
		em.vel[j] = Vector3.ZERO
		em.kb[j] = Vector3(0, 0, 3.0)
	for k in range(6):
		em._physics_process(DT)
	var went_wet: float = em.pos[i].z - p0.z
	var went_dry: float = em.pos[dry].z - d0.z
	assert_bool(em.in_lake(em.pos[i])).is_true()
	assert_float(went_dry).is_greater(0.1)
	assert_float(went_wet).is_equal_approx(went_dry, 0.001)


func _arena(ms: int) -> Game:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"arena": true, "character": "drifter", "map": "red_canyon", "map_seed": ms, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	g.clear_dummies()
	var em: EnemyManager = g.enemies
	for i in EnemyManager.MAX:
		if em.alive[i] == 1:
			em._free(i)
	em._rebuild_grid()
	return g


func _hold_stick(pl: Player, stick: Vector2) -> void:
	pl.input.set_process(false)
	pl.input.wants_move = stick.length() > 0.0
	pl.input.stick_dir = stick


## His mean flat speed over `frames` physics frames from `at`, the stick held along +X.
func _pace(pl: Player, at: Vector3, frames: int) -> float:
	_hold_stick(pl, Vector2.ZERO)
	pl.global_position = at
	pl.velocity = Vector3.ZERO
	pl._kb = Vector3.ZERO
	for k in range(8):
		await get_tree().physics_frame
	_hold_stick(pl, Vector2(1, 0))
	await get_tree().physics_frame
	var from := pl.global_position
	for k in range(frames):
		await get_tree().physics_frame
	var d := pl.global_position - from
	_hold_stick(pl, Vector2.ZERO)
	return Vector2(d.x, d.z).length() / (float(frames) * DT)


func test_the_hero_wades_ten_percent_slower() -> void:
	var g := _arena(5)
	var pl: Player = g.player
	pl.god = true
	var lakes: Array = g.map.call("lakes")
	assert_int(lakes.size()).is_greater_equal(2)
	# from 2 m short of a lake's middle, across its flat floor; and on the flats
	var c: Vector2 = (lakes[1] as Dictionary)["center"]
	var wet_at := Vector3(c.x - 2.0, g.map.height_at(c.x - 2.0, c.y) + 0.05, c.y)
	var fc: Vector3 = g.map.flats_center
	var dry_at := Vector3(fc.x - 4.0, g.map.height_at(fc.x - 4.0, fc.z) + 0.05, fc.z)
	var wet_v: float = await _pace(pl, wet_at, 12)
	assert_bool(bool(g.map.call("in_water", pl.global_position))).is_true()
	var dry_v: float = await _pace(pl, dry_at, 12)
	assert_bool(bool(g.map.call("in_water", pl.global_position))).is_false()
	assert_float(dry_v).is_greater(1.0)
	assert_float(wet_v / dry_v).override_failure_message("wet %.2f m/s, dry %.2f m/s" % [wet_v, dry_v]).is_between(0.86, 0.94)
	# the factor itself: in the water on its floor 0.9; in the air (Hang Time's flight, or well over the floor) 1
	pl.global_position = wet_at
	assert_float(pl._wade_mult()).is_equal_approx(0.9, 0.0001)
	pl.airborne = true
	assert_float(pl._wade_mult()).is_equal(1.0)
	pl.airborne = false
	pl.global_position = wet_at + Vector3(0, 1.0, 0)
	assert_float(pl._wade_mult()).is_equal(1.0)
	pl.global_position = dry_at
	assert_float(pl._wade_mult()).is_equal(1.0)
