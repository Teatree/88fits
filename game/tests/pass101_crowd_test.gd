extends GdUnitTestSuite

## Pass 101, lane CROWD: the crowd draws only what the camera can see (EnemyManager.drawn_vis, refresh_drawn, vis_bounds),
## separates on its own finer grid (SEP_CELL) while the weapons' queries keep the 2.5 m one, and steers the creatures off
## the screen every 4th tick (_steer_due, _steer_dt). Garry: draw only creatures on the screen; "Test that there are no
## overlaps with 12 neighbours and increase if necessary"; off-screen creatures close the distance as fast as before.

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

## a stand-in camera rig without a camera (tools, tests): every creature drawn
const FAKE_RIG := """extends Node
func zoom() -> float:
	return 1.0
func current_yaw() -> float:
	return 0.0
"""

## a stand-in rig with a real camera (on_screen, camera): the draw rule applies
const CAM_RIG := """extends Node
var camera: Camera3D
func zoom() -> float:
	return 1.0
func current_yaw() -> float:
	return 0.0
func pixels_per_metre() -> float:
	return 90.0
func on_screen(_p: Vector3, _m: float = 0.0) -> bool:
	return true
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _fake_game(hero_at: Vector3, rig_src: String = FAKE_RIG) -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var rig := Node.new()
	rig.set_script(_script(rig_src))
	g.add_child(rig)
	g.camera = rig
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	return g


func _manager(g: Node) -> EnemyManager:
	var em := EnemyManager.new()
	em.game = g
	em.player = g.player
	g.add_child(em)
	g.enemies = em
	return em


## A portrait camera like the game's (46 degrees down, 22.5 m back, fov 55) in its own 540 x 1200 viewport, given to the
## fake rig; the viewport is returned.
func _camera(g: Node, focus: Vector3) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(540, 1200)
	g.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)
	var pitch := deg_to_rad(46.0)
	cam.global_position = focus + Vector3(0, sin(pitch) * 22.5, cos(pitch) * 22.5)
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	g.camera.camera = cam
	return vp


## The ground point (y 0) under a screen point of `cam`.
func _ground(cam: Camera3D, sp: Vector2) -> Vector3:
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	return o + d * (-o.y / d.y)


# ---------------------------------------------------------------- the drawn picture's bounds

## The quad's corners as enemy_billboard.gdshader places them from an instance (face_camera 1).
func _quad_corners(xf: Transform3D, sq: float, up: Vector3, right: Vector3) -> Array:
	var sx := xf.basis.x.length()
	var sy := xf.basis.y.length()
	var squash := maxf(sq, 0.2)
	var w := sx * (1.0 + (1.0 - squash) * 0.5)
	var h := sy * squash
	var roll := atan2(xf.basis.x.y, xf.basis.x.x)
	var out: Array = []
	for vx in [-0.5, 0.5]:
		for vy in [0.0, 1.0]:
			var q := Vector2(vx * w, vy * h)
			q = Vector2(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll))
			out.append(xf.origin + right * q.x + up * q.y)
	return out


## The badge quad's corners (badge.gdshader: lift up the camera's up, a bob and a rock).
func _badge_corners(xf: Transform3D, cd: Color, up: Vector3, right: Vector3) -> Array:
	var lift := cd.r
	var s := cd.g
	var out: Array = []
	for bob in [-0.07 * s, 0.07 * s]:
		for rock in [-0.09, 0.09]:
			for v in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
				var r := Vector2(v.x * cos(rock) - v.y * sin(rock), v.x * sin(rock) + v.y * cos(rock))
				out.append(xf.origin + right * r.x * s + up * (lift + bob + r.y * s))
	return out


func _inside(p: Vector3, b: PackedFloat32Array, k: int) -> bool:
	return p.distance_to(Vector3(b[k], b[k + 1], b[k + 2])) <= b[k + 3] + 0.001


func test_every_drawn_pixel_lies_in_the_bounds() -> void:
	var g := _fake_game(Vector3(60, 0, 60))
	var em := _manager(g)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var ids := ["goblin", "red_goblin", "bull_beetle", "hammer_giant", "rocketeer", "stone_golem", "skeleton_knight", "gila_grande"]
	var up: Vector3 = em._cam_up().normalized()
	var back := Vector3(0, -up.z, up.y).normalized()
	var vpc := em.get_viewport().get_camera_3d()
	if vpc != null:
		back = vpc.global_transform.basis.z.normalized()
	var right := up.cross(back).normalized()
	var checked := 0
	for id: String in ids:
		for trial in range(24):
			em.kill_all(false)
			var i := em.spawn(id, Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)))
			assert_int(i).is_greater_equal(0)
			var t := em.type_idx[i]
			em.squash[i] = rng.randf_range(0.02, 1.25)
			em.lift_h[i] = rng.randf_range(0.0, 3.0) if trial % 3 == 0 else 0.0
			em.rise_t[i] = rng.randf_range(0.0, 1.0) if trial % 4 == 1 else 1.0
			em.anim_t[i] = rng.randf_range(0.0, 20.0)
			match trial % 6:
				2:
					em.state[i] = EnemyManager.STATE_WINDUP
					em.timer[i] = rng.randf_range(0.0, 0.8)
				3:
					em.state[i] = EnemyManager.STATE_CHARGE
					em.charge_dir[i] = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
				4:
					em.state[i] = EnemyManager.STATE_DYING
					em.timer[i] = rng.randf_range(0.0, EnemyManager.DIE_TIME)
				_:
					em.state[i] = EnemyManager.STATE_MOVE
			em._glow_clock = rng.randf_range(0.0, 50.0)
			var b := em.vis_bounds(i, up, em._cf_tick)
			var q := _drawn_quad(em, i)
			for p in _quad_corners(q[0], q[1], up, right):
				assert_bool(_inside(p, b, 0)).override_failure_message("%s trial %d: a corner of its picture %s lies outside its bounds %s" % [id, trial, str(p), str(b)]).is_true()
			var scf: Vector3 = em._cf_tick
			var sxf := em.shadow_xform(i, scf, Vector3(-scf.z, 0, scf.x))
			for o in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
				var w: Vector3 = sxf.origin + sxf.basis.x * o.x + sxf.basis.z * o.y
				assert_bool(_inside(w, b, 4)).override_failure_message("%s trial %d: its shadow %s lies outside its bounds %s" % [id, trial, str(w), str(b)]).is_true()
			var bk := em.badge_of(i)
			if bk != "" and em.state[i] != EnemyManager.STATE_DYING:
				for p in _badge_corners(_badge_xf(em, i, q[1]), _badge_cd(em, i, q[1]), up, right):
					assert_bool(_inside(p, b, 0)).override_failure_message("%s trial %d: its badge %s lies outside its bounds %s" % [id, trial, str(p), str(b)]).is_true()
			checked += 1
	assert_int(checked).is_equal(ids.size() * 24)


## Where _render puts creature `i`'s quad: its lines for the foot point, the basis and the squash, mirrored here because
## the headless renderer keeps no instance data to read back (the windowed pixel test, tools/_p101_CROWD_pixels.gd,
## checks the real instances too). [Transform3D, squash]
func _drawn_quad(em: EnemyManager, i: int) -> Array:
	var t := em.type_idx[i]
	var s := em.size[i]
	var st := em.state[i]
	var strip := em._strip_of(i, t)
	var n := em._t_cnt[t * EnemyManager.N_ANIMS + strip]
	var sq := em.squash[i]
	if strip == EnemyManager.A_RUN:
		sq += sin(em.anim_t[i] * 1.5) * 0.05
	var scr := Vector3(-em._cf_tick.z, 0, em._cf_tick.x)
	var cp := Vector4(0.0, 0.0, 1.0, 0.0)
	if st == EnemyManager.STATE_WINDUP or st == EnemyManager.STATE_CHARGE:
		cp = em.charge_pose(i, scr)
		sq *= cp.z
	var cam_up := em._cam_up()
	var at := em.pos[i] + Vector3(0, em.lift_h[i] + cp.y, 0) + scr * cp.x
	if em._t_sh[t * 4 + 3] != 0.0:
		at -= em.sprite_sink(i, sq, cam_up)
	if strip == EnemyManager.A_DIE and em._t_ddrop[t] != 0.0:
		at -= em.die_sink(i, float(mini(int(em.anim_t[i]), n - 1)) / float(maxi(n - 1, 1)), sq, cam_up)
	if em.rise_t[i] < 1.0:
		at -= em.rise_sink(i, sq, cam_up)
	var xb: Basis = Basis().scaled(Vector3(s, s, s)) if cp.w == 0.0 else EnemyManager.roll_basis(s, cp.w)
	return [Transform3D(xb, at), sq]


## The badge's instance as _render writes it (its origin, and its custom data: lift and size).
func _badge_xf(em: EnemyManager, i: int, _sq: float) -> Transform3D:
	return Transform3D(Basis(), em.pos[i] + Vector3(0, em.lift_h[i], 0))


func _badge_cd(em: EnemyManager, i: int, sq: float) -> Color:
	var t := em.type_idx[i]
	var def: EnemyDef = em.types[t]["def"]
	var bk := em.badge_of(i)
	var bs: float = EnemyManager.BADGE_SIZE * em._badge_scale * (1.3 if i == em.boss_index or def.archetype == "boss" or bk == "skull" else 1.0)
	var drop: float = em._t_sh[t * 4 + 3]
	var rise_k := EnemyManager.rise_ease(em.rise_t[i])
	return Color(em.size[i] * maxf(float(em.types[t]["head"]) * rise_k - drop, 0.0) * maxf(sq, 0.2) + 0.12 + bs * 0.5, bs, 0.0, 0.0)


# ---------------------------------------------------------------- the draw rule at the screen's edges

func test_a_sphere_is_seen_only_when_it_reaches_into_the_view() -> void:
	var g := _fake_game(Vector3.ZERO, CAM_RIG)
	var vp := _camera(g, Vector3.ZERO)
	var cam: Camera3D = g.camera.camera
	var planes: Array[Plane] = cam.get_frustum()
	var sz := Vector2(vp.size)
	for sp in [Vector2(sz.x * 0.5, sz.y - 1.0), Vector2(1.0, sz.y * 0.5), Vector2(sz.x - 1.0, sz.y * 0.5), Vector2(sz.x * 0.5, 1.0)]:
		var p := _ground(cam, sp)
		assert_bool(EnemyManager.sphere_visible(planes, p, 0.0)).is_true()
	# well past the bottom edge, a sphere smaller than the gap is not seen; one bigger than it is
	var below := _ground(cam, Vector2(sz.x * 0.5, sz.y * 1.4))
	var edge := _ground(cam, Vector2(sz.x * 0.5, sz.y))
	var gap := below.distance_to(edge)
	assert_bool(EnemyManager.sphere_visible(planes, below, gap * 0.5)).is_false()
	assert_bool(EnemyManager.sphere_visible(planes, below, gap * 1.2)).is_true()


func test_a_tall_body_below_the_bottom_edge_is_drawn() -> void:
	var g := _fake_game(Vector3(0, 0, 0), CAM_RIG)
	var vp := _camera(g, Vector3.ZERO)
	var em := _manager(g)
	var cam: Camera3D = g.camera.camera
	var sz := Vector2(vp.size)
	# a giant with its feet a metre and a half below the screen's bottom edge: its body reaches up into the screen
	var edge := _ground(cam, Vector2(sz.x * 0.5, sz.y))
	var giant := em.spawn("hammer_giant", edge + Vector3(0, 0, 1.5))
	# a goblin 12 m below it, and one 12 m off the left edge
	var low := em.spawn("goblin", edge + Vector3(0, 0, 12.0))
	var left := em.spawn("goblin", _ground(cam, Vector2(0, sz.y * 0.5)) + Vector3(-12.0, 0, 0))
	# one with its feet 0.4 m past the left edge: its half width is on the screen
	var side := em.spawn("goblin", _ground(cam, Vector2(0, sz.y * 0.5)) + Vector3(-0.4, 0, 0))
	for k in range(EnemyManager.VIS_HOLD + 2):
		em.refresh_drawn(-1)
	assert_int(em.drawn_vis[giant]).is_equal(1)
	assert_int(em.drawn_vis[side]).is_equal(1)
	assert_int(em.drawn_vis[low]).is_equal(0)
	assert_int(em.drawn_vis[left]).is_equal(0)
	# only the drawn ones are written
	em._render()
	var drawn := 0
	for t in em.types:
		drawn += (t["mm"] as MultiMesh).visible_instance_count
	assert_int(drawn).is_equal(2)


func test_one_that_leaves_is_held_a_few_ticks() -> void:
	var g := _fake_game(Vector3(0, 0, 0), CAM_RIG)
	_camera(g, Vector3.ZERO)
	var em := _manager(g)
	var i := em.spawn("goblin", Vector3(0, 0, 0))
	em.refresh_drawn(-1)
	assert_int(em.drawn_vis[i]).is_equal(1)
	em.pos[i] = Vector3(0, 0, 80)
	for k in range(EnemyManager.VIS_HOLD - 1):
		em.refresh_drawn(-1)
		assert_int(em.drawn_vis[i]).is_equal(1)
	em.refresh_drawn(-1)
	assert_int(em.drawn_vis[i]).is_equal(0)
	# a fresh spawn is drawn at once, wherever it is, until its first check
	var j := em.spawn("goblin", Vector3(0, 0, 90))
	assert_int(em.drawn_vis[j]).is_equal(1)


func test_without_a_camera_every_creature_is_drawn() -> void:
	var g := _fake_game(Vector3(0, 0, 0))
	var em := _manager(g)
	var i := em.spawn("goblin", Vector3(0, 0, 200))
	em.drawn_vis[i] = 0
	em.refresh_drawn(-1)
	assert_int(em.drawn_vis[i]).is_equal(1)


# ---------------------------------------------------------------- the separation's own grid

func test_the_fine_grid_separates_as_the_old_one() -> void:
	var g := _fake_game(Vector3(400, 0, 400))
	var em := _manager(g)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids: Array = []
	for k in range(160):
		var i := em.spawn("goblin", Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7)))
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		# narrow bodies, ten wide ones (the big list stays short) and two giants
		em.radius[i] = rng.randf_range(0.3, 0.62) if k >= 12 else (0.85 if k >= 2 else 1.4)
		ids.append(i)
	var before := {}
	em.set_sep_cell(EnemyManager.CELL)
	em._rebuild_grid()
	for i: int in ids:
		em._steer(i, em.player.global_position, 0.0)
		before[i] = em.vel[i]
	em.set_sep_cell(EnemyManager.SEP_CELL)
	em._rebuild_grid()
	assert_int(em._big.size()).is_less_equal(EnemyManager.BIG_LIST_MAX)
	var pushed := 0
	for i: int in ids:
		em._steer(i, em.player.global_position, 0.0)
		var a: Vector3 = before[i]
		assert_bool(a.is_equal_approx(em.vel[i]) or a.distance_to(em.vel[i]) < 0.0001).override_failure_message("creature %d steers %s on the fine grid, %s on the old" % [i, str(em.vel[i]), str(a)]).is_true()
		if a.length() > 0.01:
			pushed += 1
	# the crowd was dense enough to push
	assert_int(pushed).is_greater(50)


func test_every_touching_pair_is_felt_with_many_wide_bodies() -> void:
	# 40 wide bodies (past half a separation cell) among 120 narrow ones: the old big list gave out past 16; the cells'
	# lists (_sep_bigs) never do: every creature's separation equals a scan of the whole crowd
	var g := _fake_game(Vector3(400, 0, 400))
	var em := _manager(g)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var ids: Array = []
	for k in range(160):
		var i := em.spawn("goblin", Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)))
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		em.radius[i] = rng.randf_range(0.66, 1.3) if k < 40 else rng.randf_range(0.3, 0.62)
		ids.append(i)
	em._rebuild_grid()
	assert_int(em._big.size()).is_greater(EnemyManager.BIG_LIST_MAX)
	var hero: Vector3 = em.player.global_position
	for i: int in ids:
		em._steer(i, hero, 0.0)
		var sep := Vector3.ZERO
		for j: int in ids:
			if j == i:
				continue
			var d := em.pos[i] - em.pos[j]
			d.y = 0.0
			var min_d := em.radius[i] + em.radius[j]
			var l2 := d.length_squared()
			if l2 < min_d * min_d and l2 > 0.0001:
				var l := sqrt(l2)
				sep += d / l * (min_d - l) / min_d
		var to := hero - em.pos[i]
		to.y = 0.0
		var want := to.normalized() * em.speed[i] + sep * 4.0
		assert_bool(want.distance_to(em.vel[i]) < 0.0001).override_failure_message("creature %d (radius %.2f) steers %s, the whole crowd says %s" % [i, em.radius[i], str(em.vel[i]), str(want)]).is_true()


func test_the_weapons_queries_are_untouched_by_the_separation_cell() -> void:
	var g := _fake_game(Vector3(0, 0, 0))
	var em := _manager(g)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in range(120):
		em.spawn("goblin", Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40)))
	var qs: Array = []
	for q in range(30):
		qs.append([Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40)), rng.randf_range(0.5, 12.0)])
	em.set_sep_cell(EnemyManager.CELL)
	em._rebuild_grid()
	var want: Array = []
	for q: Array in qs:
		want.append(Array(em.indices_in_radius(q[0], q[1])))
	em.set_sep_cell(EnemyManager.SEP_CELL)
	em._rebuild_grid()
	for k in range(qs.size()):
		assert_array(Array(em.indices_in_radius(qs[k][0], qs[k][1]))).is_equal(want[k])
	assert_float(EnemyManager.CELL).is_equal(2.5)


# ---------------------------------------------------------------- the far steer

## Mean metres closed on the hero by `n` goblins walking in from 30 m over `ticks`, with every creature drawn (vis_force
## 1: the old cadence) or none (0: every 4th tick), past a field of rocks.
func _closing(vis: int, ticks: int, rocks: bool) -> float:
	var g := _fake_game(Vector3(0, 0, 0))
	var em := _manager(g)
	em.vis_force = vis
	if rocks:
		var obs: Array = []
		for k in range(12):
			obs.append(Vector3(-11.0 + 2.0 * k, 18.0 + 2.5 * float(k % 3), 0.9))
		em.obstacles = obs
	var ids: Array = []
	for k in range(16):
		var i := em.spawn("goblin", Vector3(-15.0 + 2.0 * k, 0, 30.0))
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		# one walk and one body for all (a spawn's variance rolls on the manager's own dice)
		em.speed[i] = 3.0
		em.radius[i] = 0.45
		em.size[i] = 1.2
		ids.append(i)
	var d0 := 0.0
	for i: int in ids:
		d0 += Vector2(em.pos[i].x, em.pos[i].z).length()
	for k in range(ticks):
		em._physics_process(1.0 / 60.0)
	var d1 := 0.0
	for i: int in ids:
		d1 += Vector2(em.pos[i].x, em.pos[i].z).length()
	return (d0 - d1) / float(ids.size())


func test_off_screen_creatures_close_in_as_fast() -> void:
	var near := _closing(1, 300, false)
	var far := _closing(0, 300, false)
	assert_float(near).is_greater(5.0)
	assert_float(absf(far - near) / near).override_failure_message("closed %.2f m off the screen, %.2f m on it" % [far, near]).is_less(0.03)


func test_off_screen_creatures_get_past_rocks_as_fast() -> void:
	var near := _closing(1, 360, true)
	var far := _closing(0, 360, true)
	assert_float(near).is_greater(5.0)
	assert_float(absf(far - near) / near).override_failure_message("closed %.2f m off the screen, %.2f m on it" % [far, near]).is_less(0.05)


func test_off_screen_steers_every_fourth_tick_with_its_clocks_whole() -> void:
	var g := _fake_game(Vector3(30, 0, 30))
	var em := _manager(g)
	em.vis_force = 0
	var ids: Array = []
	for k in range(8):
		var i := em.spawn("goblin", Vector3(k * 2.0, 0, 0))
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		em.slow_t[i] = 5.0
		em.slow_f[i] = 0.1
		ids.append(i)
	var dt := 1.0 / 60.0
	var steered := 0
	em._physics_process(dt)
	for i: int in ids:
		if em.slow_t[i] < 5.0:
			steered += 1
	# a quarter of them on any one tick (two of the eight)
	assert_int(steered).is_equal(2)
	for k in range(39):
		em._physics_process(dt)
	# 40 ticks: every clock ran 40 ticks' time, less the first steer's two-tick guess at most
	for i: int in ids:
		var ran := 5.0 - em.slow_t[i]
		assert_float(ran).is_between(36.0 * dt - 0.0001, 40.0 * dt + 0.0001)
	# drawn again: its next steer runs the ticks since its last one, then every 2nd tick as before
	em.vis_force = 1
	var was := {}
	for i: int in ids:
		was[i] = em.slow_t[i]
	em._physics_process(dt)
	em._physics_process(dt)
	for i: int in ids:
		var ran := float(was[i]) - em.slow_t[i]
		assert_float(ran).is_between(2.0 * dt - 0.0001, 4.0 * dt + 0.0001)
		was[i] = em.slow_t[i]
	em._physics_process(dt)
	em._physics_process(dt)
	for i: int in ids:
		assert_float(float(was[i]) - em.slow_t[i]).is_equal_approx(2.0 * dt, 0.0001)
