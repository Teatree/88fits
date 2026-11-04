extends GdUnitTestSuite

## Pass 125: the crowd's compiled loops (native/, EnemyManager._nat): the library is there on this machine, the same crowd plays
## the same numbers with it and without it (the whole-run proof is game/tools/_p125_NATIVE_proof.gd), the switch turns it off,
## and the steering's cadence (the map's timeline_data.crowd) shares the crowd out evenly. Garry: "I want to have lots of enemies
## on the screen at the same time"; "We can also try moving the crowd less often".

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var telegraphs = null
var fx = null
var map = null
var camera = null
var paused := false
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = false) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
var bites := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	bites += 1
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(_d: Vector3) -> Vector3:
	return global_position
"""

const FAKE_RIG := """extends Node
func zoom() -> float:
	return 1.0
func current_yaw() -> float:
	return 0.0
"""

const MIX := ["skeleton", "skeleton_knight", "fire_ant", "goblin", "hammer_giant", "werewolf"]


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _fake_game() -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var rig := Node.new()
	rig.set_script(_script(FAKE_RIG))
	g.add_child(rig)
	g.camera = rig
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	return g


## A small height map with a slope, so the height sums matter.
func _map(g: Node) -> MapBase:
	var m := MapBase.new()
	m.size_m = 80.0
	m.resolution = 1.0
	m.grid_n = 81
	m.heights.resize(81 * 81)
	for z in range(81):
		for x in range(81):
			m.heights[z * 81 + x] = sin(float(x) * 0.31) * 0.4 + cos(float(z) * 0.23) * 0.3
	g.add_child(m)
	g.map = m
	return m


func _manager(g: Node, native: bool) -> EnemyManager:
	var keep := Settings.native_crowd
	Settings.native_crowd = native
	var em := EnemyManager.new()
	em.game = g
	em.player = g.player
	g.add_child(em)
	g.enemies = em
	Settings.native_crowd = keep
	return em


## A crowd on a ring and in a pack, with rocks in its way, walking on the slope.
func _crowd(em: EnemyManager, m: MapBase) -> void:
	em.height_fn = m.height_at
	em.obstacles = [Vector3(3.0, 4.0, 1.5), Vector3(-5.0, -2.0, 1.0), Vector3(8.0, -6.0, 2.0)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in range(120):
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, 18.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.y = m.height_at(p.x, p.z)
		em.spawn(str(MIX[k % MIX.size()]), p)


func _same_floats(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	return a.to_byte_array() == b.to_byte_array()


func _same_vecs(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	return a.to_byte_array() == b.to_byte_array()


func test_the_library_is_there_and_the_manager_uses_it() -> void:
	assert_bool(ClassDB.class_exists(&"CrowdCore")).is_true()
	var g := _fake_game()
	var em := _manager(g, true)
	assert_bool(em.native_on()).is_true()


func test_the_switch_turns_it_off() -> void:
	var g := _fake_game()
	var em := _manager(g, false)
	assert_bool(em.native_on()).is_false()


func test_the_same_crowd_plays_the_same_numbers_with_it_and_without_it() -> void:
	var results: Array = []
	for native: bool in [false, true]:
		# the same dice for both (a manager's own come from the run's seed)
		Dice.reseed(4242)
		var g := _fake_game()
		var m := _map(g)
		var em := _manager(g, native)
		assert_bool(em.native_on()).is_equal(native)
		_crowd(em, m)
		for _t in range(150):
			em._physics_process(1.0 / 60.0)
		results.append(em)
	Dice.reseed(0)
	var a: EnemyManager = results[0]
	var b: EnemyManager = results[1]
	assert_bool(_same_vecs(a.pos, b.pos)).is_true()
	assert_bool(_same_vecs(a.vel, b.vel)).is_true()
	assert_bool(_same_vecs(a.kb, b.kb)).is_true()
	assert_bool(_same_vecs(a.intent, b.intent)).is_true()
	assert_bool(_same_floats(a.anim_t, b.anim_t)).is_true()
	assert_bool(_same_floats(a.flash, b.flash)).is_true()
	assert_bool(_same_floats(a.squash, b.squash)).is_true()
	assert_bool(_same_floats(a.contact_cd, b.contact_cd)).is_true()
	assert_array(Array(a.flip)).is_equal(Array(b.flip))
	assert_array(Array(a.away)).is_equal(Array(b.away))
	assert_array(Array(a.view)).is_equal(Array(b.view))
	assert_array(Array(a._st_last)).is_equal(Array(b._st_last))
	assert_int(int(a.player.bites)).is_equal(int(b.player.bites))
	assert_float(a._mean_max_hp).is_equal(b._mean_max_hp)
	# it really ran them
	var c: PackedInt64Array = b.native_counts()
	assert_int(c[0]).is_greater(10000)


func test_the_grids_are_built_alike() -> void:
	var g := _fake_game()
	var m := _map(g)
	var em := _manager(g, true)
	_crowd(em, m)
	em._rebuild_grid()
	var gh := em._g_head.duplicate()
	var gn := em._g_next.duplicate()
	var sh := em._s_head.duplicate()
	var sn := em._s_next.duplicate()
	var bh := em._bg_head.duplicate()
	var bn := em._bg_n
	var gm := em._grid_max_r
	var nat = em._nat
	em._nat = null
	em._nat_ok = false
	em._rebuild_grid()
	em._nat = nat
	assert_array(Array(gh)).is_equal(Array(em._g_head))
	assert_array(Array(sh)).is_equal(Array(em._s_head))
	assert_array(Array(bh)).is_equal(Array(em._bg_head))
	assert_int(bn).is_equal(em._bg_n)
	assert_float(gm).is_equal(em._grid_max_r)
	# a creature's next link counts only while it is in a cell
	for i in range(em.pool_max):
		if em.alive[i] == 1:
			assert_int(gn[i]).is_equal(em._g_next[i])
			assert_int(sn[i]).is_equal(em._s_next[i])


func test_a_wide_crowd_outgrows_the_lists_and_they_grow() -> void:
	var g := _fake_game()
	var m := _map(g)
	var em := _manager(g, true)
	em.height_fn = m.height_at
	for k in range(60):
		em.spawn("hammer_giant", Vector3(float(k % 8) * 2.0 - 8.0, 0.0, float(k / 8) * 2.0 - 8.0))
	em._rebuild_grid()
	assert_int(em._bg_n).is_greater(0)
	assert_bool(em._bg_j.size() >= em._bg_n).is_true()


func test_a_height_function_it_cannot_read_leaves_the_tick_to_the_script() -> void:
	var g := _fake_game()
	var em := _manager(g, true)
	em.height_fn = func(_x: float, _z: float) -> float: return 0.25
	em.spawn("skeleton", Vector3(4.0, 0.0, 0.0))
	em._physics_process(1.0 / 60.0)
	assert_bool(em._nat_ok).is_false()
	assert_float(em.pos[0].y).is_equal_approx(0.25, 0.0001)


func test_the_draw_counts_what_the_script_counts() -> void:
	var counts: Array = []
	for native: bool in [false, true]:
		Dice.reseed(4242)
		var g := _fake_game()
		var m := _map(g)
		var em := _manager(g, native)
		_crowd(em, m)
		for _t in range(30):
			em._physics_process(1.0 / 60.0)
		em._render()
		var row: Array = []
		for t in range(em.types.size()):
			row.append((em._t_mm[t] as MultiMesh).visible_instance_count)
		row.append(em._shadow_mm.visible_instance_count)
		counts.append(row)
	Dice.reseed(0)
	assert_array(counts[1]).is_equal(counts[0])
	assert_int(int(counts[1][0])).is_greater(0)


func test_the_cadence_shares_the_crowd_out_evenly() -> void:
	var g := _fake_game()
	var em := _manager(g, false)
	em.set_cadence(3, 6)
	em.drawn_vis.fill(1)
	em.spawn("skeleton", Vector3(4.0, 0.0, 0.0))
	var t: int = em.type_idx[0]
	em.type_idx.fill(t)
	for i in range(30):
		var due := 0
		for phase in range(3):
			if em._steer_due(i, phase):
				due += 1
		assert_int(due).is_equal(1)
	# each steer's clocks run for the ticks since its last, its push held at 2/3 per tick (far_push_scale)
	em._tick = 10
	em._st_last[0] = 7
	assert_float(em._steer_dt(0, 0.1, 0.3)).is_equal_approx(0.3, 0.000001)


func test_a_map_may_set_the_cadence_and_keeps_todays_without_it() -> void:
	var g := _fake_game()
	var em := _manager(g, false)
	assert_int(em.steer_every).is_equal(2)
	assert_int(em.steer_far_every).is_equal(4)
	em.set_cadence(0, 0)
	assert_int(em.steer_every).is_equal(1)
	assert_int(em.steer_far_every).is_equal(1)
	em.set_cadence(3, 2)
	assert_int(em.steer_far_every).is_equal(3)
	assert_int(int(WaveTimeline.CROWD_DEFAULTS["steer_every"])).is_equal(2)
	assert_int(int(WaveTimeline.CROWD_DEFAULTS["steer_far_every"])).is_equal(4)
