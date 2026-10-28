extends GdUnitTestSuite

## Pass 110 (lane ARENA): the debug arena's screenshot tools. The creature pool grows past a run's 320 for the arena
## alone (EnemyManager.grow_pool), keeping every creature; the freeze (crowd_freeze) holds every creature where it stands
## while it turns to face the hero and still dies to a hit; the crowds' layouts (ui/ArenaShots.gd: a ring round a clear
## circle, a scatter, a chunk a kind, counts split by weights); the camera's screenshot framing (CameraRig.frame_hero_y)
## puts the hero's middle where it is asked, every frame.

const SHOTS := preload("res://ui/ArenaShots.gd")

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
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
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


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _manager() -> EnemyManager:
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
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	return em


## A settled creature (no special, up out of the ground, standing) at `at`.
func _settled(em: EnemyManager, id: String, at: Vector3) -> int:
	var i := em.spawn(id, at)
	assert_int(i).is_greater_equal(0)
	em.vspecial[i] = 0
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	return i


func test_a_run_keeps_the_pool_of_320() -> void:
	var em := _manager()
	assert_int(em.pool_max).is_equal(EnemyManager.MAX)
	assert_int(EnemyManager.MAX).is_equal(320)
	assert_int(em.pos.size()).is_equal(320)
	assert_int(em.free_list.size()).is_equal(320)
	# the lowest slot first, as before
	assert_int(em.spawn("goblin", Vector3(3, 0, 0))).is_equal(0)


func test_the_arena_pool_grows_and_keeps_its_creatures() -> void:
	var em := _manager()
	var a := _settled(em, "goblin", Vector3(3, 0, 1))
	var b := _settled(em, "lesser_scorpion", Vector3(-2, 0, 4))
	em.damage(b, 1.0, "test")
	var hp_b := em.hp[b]
	assert_int(em.grow_pool(2500)).is_equal(2500)
	assert_int(em.pool_max).is_equal(2500)
	for arr in [em.pos, em.alive, em.hp, em.drawn_vis, em.rise_t, em.state, em.type_idx, em.lift_t, em.poison_src, em.serial]:
		assert_int(arr.size()).is_equal(2500)
	# the two kept, the new slots started as _ready starts them
	assert_int(em.alive[a]).is_equal(1)
	assert_float(em.pos[a].x).is_equal_approx(3.0, 0.001)
	assert_float(em.hp[b]).is_equal_approx(hp_b, 0.001)
	assert_float(em.rise_t[2400]).is_equal(1.0)
	assert_int(em.drawn_vis[2400]).is_equal(1)
	assert_bool(em.poison_src[2400] is Dictionary).is_true()
	assert_int(em.free_list.size()).is_equal(2498)
	for td in em.types:
		assert_int(((td as Dictionary)["mm"] as MultiMesh).instance_count).is_equal(2500)
	# never shrinks, never past the arena's ceiling
	assert_int(em.grow_pool(100)).is_equal(2500)
	assert_int(em.grow_pool(99999)).is_equal(EnemyManager.ARENA_MAX)
	# fill past 320 and kill one up there
	var last := -1
	for k in range(600):
		last = em.spawn("goblin", Vector3(float(k % 30) * 0.7 + 5.0, 0, float(k / 30) * 0.7))
		assert_int(last).is_greater_equal(0)
	assert_int(last).is_greater(320)
	em.rise_t[last] = 1.0
	em.state[last] = EnemyManager.STATE_MOVE
	em.damage(last, 1.0e9, "test")
	assert_int(em.state[last]).is_equal(EnemyManager.STATE_DYING)
	# a tick runs over the grown pool (the grids sized again)
	em._physics_process(1.0 / 60.0)
	em._process(0.0)


func test_a_frozen_crowd_stands_and_faces_the_hero() -> void:
	var em := _manager()
	# the hero at the origin: one to his west, one to his east
	var w := _settled(em, "goblin", Vector3(-6, 0, 0))
	var e := _settled(em, "goblin", Vector3(6, 0, 0))
	em.crowd_freeze = EnemyManager.FREEZE_WALK
	em.kb[w] = Vector3(8, 0, 0)
	var at_w := em.pos[w]
	var at_e := em.pos[e]
	var anim0 := em.anim_t[w]
	for k in range(30):
		em._physics_process(1.0 / 60.0)
	assert_float(em.pos[w].distance_to(at_w)).is_less(0.001)
	assert_float(em.pos[e].distance_to(at_e)).is_less(0.001)
	# facing the hero: the west one heads screen-right, the east one screen-left (flip 1)
	assert_int(em.flip[w]).is_equal(0)
	assert_int(em.flip[e]).is_equal(1)
	# walking in place: the legs go and the walk strip shows
	assert_float(em.anim_t[w]).is_greater(anim0)
	# (a run strip: the front one, or an eight-direction creature's run in the view it shows)
	assert_bool([0, 5, 7, 9, 11].has(em._strip_of(w, em.type_idx[w]))).is_true()
	# the pose holds the picture
	em.crowd_freeze = EnemyManager.FREEZE_POSE
	var anim1 := em.anim_t[w]
	for k in range(10):
		em._physics_process(1.0 / 60.0)
	assert_float(em.anim_t[w]).is_equal(anim1)
	# a hit still kills, and the death plays out
	em.damage(e, 1.0e9, "test")
	assert_int(em.state[e]).is_equal(EnemyManager.STATE_DYING)
	for k in range(int(EnemyManager.DIE_TIME * 60.0) + 10):
		em._physics_process(1.0 / 60.0)
	assert_int(em.alive[e]).is_equal(0)
	# let go: it walks again
	em.crowd_freeze = EnemyManager.FREEZE_OFF
	for k in range(30):
		em._physics_process(1.0 / 60.0)
	assert_float(em.pos[w].distance_to(at_w)).is_greater(0.05)


func test_a_ring_leaves_the_clear_circle_and_mixes_the_kinds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var poly := PackedVector2Array([Vector2(-15, -25), Vector2(15, -25), Vector2(15, 12), Vector2(-15, 12)])
	var ok := func(_p: Vector2) -> bool: return true
	var out: Array = SHOTS.layout(600, 2, "ring", Vector2.ZERO, poly, 4.0, 0.0, 1.2, ok, rng)
	assert_int(out.size()).is_equal(600)
	var kinds := [0, 0]
	var nearest := INF
	for pair in out:
		var p: Vector2 = pair[1]
		nearest = minf(nearest, p.length())
		assert_bool(SHOTS.in_poly(poly, p)).is_true()
		kinds[int(pair[0])] += 1
	assert_float(nearest).is_greater_equal(4.0)
	assert_int(kinds[0]).is_equal(300)
	assert_int(kinds[1]).is_equal(300)
	# a ring 3 m deep stays inside 7 m
	var band: Array = SHOTS.layout(200, 1, "ring", Vector2.ZERO, poly, 4.0, 3.0, 1.2, ok, rng)
	assert_int(band.size()).is_equal(200)
	for pair in band:
		assert_float((pair[1] as Vector2).length()).is_between(4.0, 7.0)


func test_a_scatter_keeps_off_the_rocks_and_the_clear_circle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var poly := PackedVector2Array([Vector2(-15, -25), Vector2(15, -25), Vector2(15, 12), Vector2(-15, 12)])
	# a rock 3 m across at (6, -6)
	var ok := func(p: Vector2) -> bool: return p.distance_to(Vector2(6, -6)) > 1.5
	var out: Array = SHOTS.layout(400, 3, "scatter", Vector2.ZERO, poly, 3.0, 0.0, 1.2, ok, rng)
	assert_int(out.size()).is_equal(400)
	for pair in out:
		var p: Vector2 = pair[1]
		assert_float(p.length()).is_greater_equal(3.0)
		assert_float(p.distance_to(Vector2(6, -6))).is_greater(1.5)


func test_chunks_are_one_group_a_kind_apart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var poly := PackedVector2Array([Vector2(-15, -25), Vector2(15, -25), Vector2(15, 12), Vector2(-15, 12)])
	var ok := func(_p: Vector2) -> bool: return true
	var out: Array = SHOTS.layout(300, 3, "chunks", Vector2.ZERO, poly, 4.0, 0.0, 1.2, ok, rng, [100, 100, 100])
	assert_int(out.size()).is_equal(300)
	var centres := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var counts := [0, 0, 0]
	for pair in out:
		var k: int = pair[0]
		centres[k] += pair[1]
		counts[k] += 1
		assert_float((pair[1] as Vector2).length()).is_greater_equal(4.0)
	for k in range(3):
		assert_int(counts[k]).is_equal(100)
		centres[k] /= float(counts[k])
	# each spot nearer its own group's middle than any other's
	for pair in out:
		var k2: int = pair[0]
		var p2: Vector2 = pair[1]
		for j in range(3):
			if j != k2:
				assert_float(p2.distance_to(centres[k2])).is_less(p2.distance_to(centres[j]))
	# the first group stands up the screen (north, -z)
	assert_float((centres[0] as Vector2).y).is_less(-4.0)


func test_counts_split_by_weights_and_add_up() -> void:
	assert_array(Array(SHOTS.split(10, 3))).is_equal([4, 3, 3])
	assert_array(Array(SHOTS.split(10, 3, [5, 3, 2]))).is_equal([5, 3, 2])
	var odd := SHOTS.split(1000, 3, [1, 1, 1])
	assert_int(odd[0] + odd[1] + odd[2]).is_equal(1000)


func test_the_framing_puts_the_heros_middle_where_asked() -> void:
	var rig: CameraRig = auto_free(CameraRig.new())
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	var hero: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(hero)
	# off: the fixed camera's own look-ahead
	assert_float(rig.focus_ahead(22.5, deg_to_rad(46.0))).is_equal(rig.fixed_focus_ahead)
	var vp := rig.get_viewport().get_visible_rect().size
	for want: float in [0.5, 0.35, 0.3]:
		rig.frame_hero_y = want
		rig.snap_to(hero)
		var y := cam.unproject_position(hero.global_position + Vector3(0, CameraRig.FRAME_HERO_MID, 0)).y / vp.y
		assert_float(y).is_equal_approx(want, 0.005)
	# held frame after frame (the follow code reads it every frame)
	rig._update(1.0 / 60.0)
	rig._update(1.0 / 60.0)
	var y2 := cam.unproject_position(hero.global_position + Vector3(0, CameraRig.FRAME_HERO_MID, 0)).y / vp.y
	assert_float(y2).is_equal_approx(0.3, 0.005)
	rig.frame_hero_y = -1.0
	rig.snap_to(hero)
	var y3 := cam.unproject_position(hero.global_position + Vector3(0, CameraRig.FRAME_HERO_MID, 0)).y / vp.y
	assert_float(y3).is_greater(0.5)
