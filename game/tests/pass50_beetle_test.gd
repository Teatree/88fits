extends GdUnitTestSuite

## Pass 50 (Garry's Bull Beetle list): BB-C stays the beetle in play; it stands on its shadow (the scorpion's fix, its own
## numbers: the painted legs end above the cell's floor); winding up it crouches, scrabbles its legs in place, rocks and
## shakes, and paws sand back; it launches stretched in a burst of dust, runs with its legs at charge.legs times their
## walk, bouncing and leaning into the run, with a trail of soft dust behind it; it shoves what stands in its way out to
## the side, a little (charge.shove, shove_walk while it walks), never a boss, an Elite or anything bigger; and the
## Dune Scorpion, a charger without these keys, charges as it did.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
var lines: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, c, d, _e) -> void:
	lines.append({"length": float(c), "dur": float(d)})
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at` with the real crowd, and the real effects when `with_fx`.
func _world(hero_at := Vector3.ZERO, with_fx := false) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var fx: Fx = null
	if with_fx:
		fx = Fx.new()
		g.add_child(fx)
		g.fx = fx
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": fx}


## A creature on the sand, out of its spawn, standing still, with no variance in its size.
func _put(em: EnemyManager, id: String, at: Vector3) -> int:
	var i := em.spawn(id, at)
	em.state[i] = EnemyManager.STATE_MOVE
	em.size[i] = Registry.enemy(id).size
	em.radius[i] = Registry.enemy(id).radius
	em.vel[i] = Vector3.ZERO
	em.kb[i] = Vector3.ZERO
	em.squash[i] = 1.0
	return i


## The beetle `i` put into its wind-up towards the hero (its brain's own start, the red line and all).
func _wind_up(em: EnemyManager, i: int) -> void:
	em.cooldown[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)


# ---------------------------------------------------------------- the art and its shadow

func test_bb_c_is_the_beetle_in_play_and_stands_on_its_shadow() -> void:
	var d: EnemyDef = Registry.enemy("bull_beetle")
	assert_str(d.variant).is_equal("BB-C")
	var n := EnemyManager.shadow_numbers(d)
	# a wider, deeper blob slid up the screen under the body, and the painting sunk onto it (the scorpion's numbers per
	# metre of size)
	assert_float(n[0]).is_equal_approx(1.45, 0.001)
	assert_float(n[1]).is_equal_approx(1.7, 0.001)
	assert_float(n[2] * d.size).is_equal_approx(0.35, 0.001)
	assert_float(n[3]).is_equal_approx(0.07, 0.001)
	# the sink covers the empty cell under the lowest painted legs in every view, by a few pixels at most
	var img: Image = d.sprite.get_image()
	if img.is_compressed():
		img.decompress()
	var px := d.frame_px
	var lowest := px
	for a: String in ["idle", "run", "run_b", "run_s", "run_bd", "run_fd", "idle_s", "idle_bd", "idle_fd"]:
		var f := d.frame_offset(a)
		var x0 := (f % d.strip_cols) * px
		var y0 := (f / d.strip_cols) * px
		# the first row up from the floor with a solid pixel in it (every other column; a lossy import leaves faint noise)
		for r in range(px - 1, -1, -1):
			var hit := false
			for x in range(0, px, 2):
				if img.get_pixel(x0 + x, y0 + r).a > 0.5:
					hit = true
					break
			if hit:
				lowest = mini(lowest, px - 1 - r)
				break
	var sink := n[3] * float(px)
	assert_float(sink).override_failure_message("sinks %.1f px, the legs end %d px above the floor" % [sink, lowest]).is_greater_equal(float(lowest) - 1.0)
	assert_float(sink).is_less_equal(float(lowest) + 6.0)


func test_the_scorpion_charges_as_it_did() -> void:
	var n := EnemyManager.charge_numbers(Registry.enemy("dune_scorpion"))
	for k in [0, 1, 3, 4, 5, 6]:
		assert_float(n[k]).override_failure_message("key %d" % k).is_equal(0.0)
	assert_float(n[2]).is_equal(1.0)
	var c: Dictionary = Registry.enemy("bull_beetle").charge
	for key: String in ["shake", "crouch", "legs", "lean", "dust", "shove", "shove_walk"]:
		assert_bool(c.has(key)).override_failure_message(key).is_true()


# ---------------------------------------------------------------- the wind-up

func test_the_wind_up_crouches_scrabbles_rocks_and_shakes_harder_towards_the_launch() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _put(em, "bull_beetle", Vector3(5, 0, 0))
	_wind_up(em, i)
	var t := em.type_idx[i]
	var c: Dictionary = Registry.enemy("bull_beetle").charge
	var scr := Vector3(1, 0, 0)
	# its legs go: the run strip of the view it shows, not the idle set the scorpion holds
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.VIEW_ANIM[EnemyManager.A_RUN][em.view[i]])
	# early in the wind-up it is barely down and barely shaking; late, all the way down and shaking hard (each the most
	# over a second of its clock at that point of the wind-up)
	var total: float = em.timer[i]
	var peaks := {}
	for f0: float in [0.05, 0.95]:
		em.timer[i] = total * (1.0 - f0)
		var most := Vector3.ZERO   # side shake, crouch (1 - squash), rock
		for k in range(240):
			em._glow_clock = float(k) * 0.0042
			var cp := em.charge_pose(i, scr)
			most = Vector3(maxf(most.x, absf(cp.x)), maxf(most.y, 1.0 - cp.z), maxf(most.z, absf(cp.w)))
		peaks[f0] = most
	var early: Vector3 = peaks[0.05]
	var late: Vector3 = peaks[0.95]
	assert_float(late.x).is_greater(float(c["shake"]) * 0.75)
	assert_float(late.x).is_less_equal(float(c["shake"]) + 0.001)
	assert_float(early.x).is_less(late.x * 0.4)
	assert_float(late.y).is_equal_approx(float(c["crouch"]), 0.005)
	assert_float(early.y).is_less(late.y * 0.2)
	assert_float(late.z).is_greater(EnemyManager.ROCK * 0.8)
	# the legs speed up through it: from the walk's pace to `legs` times it at the launch
	em.timer[i] = total * 0.98
	var a0: float = em.anim_t[i]
	em._physics_process(DT)
	var slow: float = em.anim_t[i] - a0
	em.state[i] = EnemyManager.STATE_WINDUP
	em.timer[i] = total * 0.03
	a0 = em.anim_t[i]
	em._physics_process(DT)
	var fast: float = em.anim_t[i] - a0
	assert_float(fast).is_greater(slow * 2.0)


func test_a_charger_without_the_keys_holds_its_idle_set_and_stands_still() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _put(em, "dune_scorpion", Vector3(6, 0, 0))
	_wind_up(em, i)
	var t := em.type_idx[i]
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.VIEW_ANIM[EnemyManager.A_IDLE][em.view[i]])
	em.timer[i] = 0.05
	assert_bool(em.charge_pose(i, Vector3(1, 0, 0)) == Vector4(0, 0, 1, 0)).is_true()


# ---------------------------------------------------------------- the launch and the run

func test_the_charge_launches_stretched_and_runs_its_legs_faster_bouncing_and_leaning() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _put(em, "bull_beetle", Vector3(5, 0, 0))
	_wind_up(em, i)
	var c: Dictionary = Registry.enemy("bull_beetle").charge
	em.timer[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_CHARGE)
	# it springs out of the crouch stretched long
	assert_float(em.squash[i]).is_equal_approx(1.0 + float(c["crouch"]) * 1.6, 0.001)
	# heading straight across the screen (west, to the hero) it leans the whole angle into the run, the top towards the hero
	var scr := Vector3(1, 0, 0)
	em.charge_dir[i] = Vector3(-1, 0, 0)
	var cp := em.charge_pose(i, scr)
	assert_float(cp.w).is_equal_approx(deg_to_rad(float(c["lean"])), 0.001)
	assert_float(cp.y).is_greater_equal(0.0)
	# heading down the screen, no lean
	em.charge_dir[i] = Vector3(0, 0, 1)
	assert_float(em.charge_pose(i, scr).w).is_equal_approx(0.0, 0.0001)
	# it bounces at its steps, never above BOUNCE of its size
	var top := 0.0
	for k in range(24):
		em.anim_t[i] = float(k) * 0.5
		top = maxf(top, em.charge_pose(i, scr).y)
	assert_float(top).is_equal_approx(EnemyManager.BOUNCE * em.size[i], 0.01)
	# the legs run at `legs` times the walk
	em.charge_dir[i] = Vector3(-1, 0, 0)
	var a0: float = em.anim_t[i]
	em._physics_process(DT)
	var run_fps := float(Registry.enemy("bull_beetle").fps.get("run", 10.0))
	assert_float(em.anim_t[i] - a0).is_equal_approx(DT * run_fps * Run.move_pace() * float(c["legs"]), 0.001)
	# at the end it digs in, squashed
	em.timer[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.squash[i]).is_equal_approx(1.0 - float(c["crouch"]), 0.001)


func test_the_billboards_draw_the_lean_as_a_roll_about_the_feet() -> void:
	for shader_name in ["enemy_billboard", "enemy_silhouette"]:
		var src := FileAccess.get_file_as_string("res://core/shaders/%s.gdshader" % shader_name)
		assert_bool(src.contains("atan(MODEL_MATRIX[0].y, MODEL_MATRIX[0].x)")).override_failure_message(shader_name).is_true()
	# the rolled basis keeps the size the shaders read off the columns, and carries the roll in the x column's angle
	var bas := EnemyManager.roll_basis(2.0, 0.12)
	assert_float(atan2(bas.x.y, bas.x.x)).is_equal_approx(0.12, 0.0001)
	assert_float(bas.x.length()).is_equal_approx(2.0, 0.0001)
	assert_float(bas.y.length()).is_equal_approx(2.0, 0.0001)
	# the render draws a charger with it, and everyone else with a plain scale (no roll)
	var src2 := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	assert_bool(src2.contains("Basis().scaled(Vector3(s, s, s)) if cp.w == 0.0 else roll_basis(s, cp.w)")).is_true()
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _put(em, "bull_beetle", Vector3(5, 0, 0))
	em.state[i] = EnemyManager.STATE_CHARGE
	em.timer[i] = 0.5
	em.charge_dir[i] = Vector3(-1, 0, 0)
	assert_float(absf(em.charge_pose(i, Vector3(1, 0, 0)).w)).is_greater(0.05)
	var j := _put(em, "skeleton", Vector3(-5, 0, 3))
	assert_bool(em.charge_pose(j, Vector3(1, 0, 0)) == Vector4(0, 0, 1, 0)).is_true()


# ---------------------------------------------------------------- the shove

func test_a_charge_shoves_what_stands_in_its_way_out_to_the_side_once() -> void:
	var w := _world(Vector3(20, 0, 0))
	var em: EnemyManager = w["em"]
	var c: Dictionary = Registry.enemy("bull_beetle").charge
	var b := _put(em, "bull_beetle", Vector3(0, 0, 0))
	em.state[b] = EnemyManager.STATE_CHARGE
	em.timer[b] = 0.5
	em.charge_dir[b] = Vector3(1, 0, 0)
	# one a little north of its line, one a little south, one it has already passed, and an Elite in the way
	var north := _put(em, "skeleton", Vector3(1.2, 0, -0.25))
	var south := _put(em, "skeleton", Vector3(1.4, 0, 0.3))
	var behind := _put(em, "skeleton", Vector3(-1.2, 0, 0.1))
	var elite := _put(em, "dune_scorpion", Vector3(0.6, 0, 1.6))
	em._rebuild_grid()
	em._steer(b, em.player.global_position, DT)
	# straight out to the side each stands on, at charge.shove metres a second, none along the run
	assert_float(em.kb[north].z).is_equal_approx(-float(c["shove"]), 0.001)
	assert_float(em.kb[south].z).is_equal_approx(float(c["shove"]), 0.001)
	assert_float(absf(em.kb[north].x) + absf(em.kb[south].x)).is_equal_approx(0.0, 0.0001)
	# a flinch
	assert_float(em.squash[north]).is_less(0.87)
	# never one it has passed, never an Elite
	assert_bool(em.kb[behind].is_zero_approx()).is_true()
	assert_bool(em.kb[elite].is_zero_approx()).is_true()
	# once a pass: the next steer, still overlapping, gives no second shove
	em._steer(b, em.player.global_position, DT)
	assert_float(em.kb[north].z).is_equal_approx(-float(c["shove"]), 0.001)
	# about half a metre aside, then it walks on: knockback dies away at 6 a second
	var moved := 0.0
	var v: float = em.kb[north].z
	for k in range(120):
		moved += v * DT
		v = lerpf(v, 0.0, DT * 6.0)
	assert_float(absf(moved)).is_between(0.3, 0.6)


func test_walking_it_nudges_only_what_is_ahead_of_it_and_nothing_bigger() -> void:
	var w := _world(Vector3(10, 0, 0))
	var em: EnemyManager = w["em"]
	var c: Dictionary = Registry.enemy("bull_beetle").charge
	var b := _put(em, "bull_beetle", Vector3(0, 0, 0))
	em.cooldown[b] = 99.0
	var ahead := _put(em, "skeleton", Vector3(1.3, 0, 0.2))
	var behind := _put(em, "skeleton", Vector3(-1.3, 0, 0.0))
	var giant := _put(em, "hammer_giant", Vector3(0.4, 0, -1.4))
	em._rebuild_grid()
	em._steer(b, em.player.global_position, DT)
	assert_float(em.kb[ahead].z).is_equal_approx(float(c["shove_walk"]), 0.001)
	assert_float(float(c["shove_walk"])).is_less(float(c["shove"]))
	assert_bool(em.kb[behind].is_zero_approx()).is_true()
	assert_bool(em.kb[giant].is_zero_approx()).is_true()


# ---------------------------------------------------------------- the dust

func test_the_wind_up_paws_sand_and_the_launch_and_the_run_throw_up_soft_dust() -> void:
	var w := _world(Vector3.ZERO, true)
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	var i := _put(em, "bull_beetle", Vector3(5, 0, 0))
	_wind_up(em, i)
	# pawing, late in the wind-up (it is random: a second of it paws many times)
	var n0: int = fx._n
	var total: float = em.timer[i]
	for k in range(60):
		em.timer[i] = total * 0.3
		em._steer(i, em.player.global_position, DT)
	assert_int(fx._n).is_greater(n0)
	# the launch: a burst of dust that is never thinned
	n0 = fx._n
	em.timer[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	assert_int(fx._n).is_greater_equal(n0 + 4)
	# the run: a beat of the trail every steer, on the soft dust pool
	n0 = fx._n
	for k in range(6):
		em._steer(i, em.player.global_position, DT)
	assert_int(fx._n).is_greater(n0)
	fx._process(DT)
	assert_int(fx._dust_mm.visible_instance_count).is_greater(0)


func test_a_charger_without_dust_throws_up_none() -> void:
	var w := _world(Vector3.ZERO, true)
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	var i := _put(em, "dune_scorpion", Vector3(6, 0, 0))
	_wind_up(em, i)
	var n0: int = fx._n
	em.timer[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	for k in range(6):
		em._steer(i, em.player.global_position, DT)
	assert_int(fx._n).is_equal(n0)
