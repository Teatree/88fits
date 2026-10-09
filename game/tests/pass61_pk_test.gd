extends GdUnitTestSuite

## Pass 61, lane PK (Garry: "The EXP gems still disappear. Now they combine into a big gem. I'd prefer that they don't
## disappear ever, but don't affect the performance negatively at all"): no gem or coin ever merges or is lost (the pool
## doubles when it fills); a pickup lying on the sand is out of the tick (the grid, the idle turns' wheel) and out of the
## draw (its instance written once as it lands: the float and the spin are the shaders'); the magnet and a big pull still
## take every one, the pull keeping to its flight budget and starting the ones beyond the screen just off its edge.

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
func max_speed() -> float:
	return 5.0
"""

## A PickupManager that writes down what each pickup it takes was worth (its XP and its gold, before the run's own sums),
## and of the ones a big pull takes unseen (quiet), how many and how many of those lay on the screen (none may).
const COUNTING := """extends PickupManager
var got := 0.0
var got_gold := 0.0
var taken := 0
var quiet_n := 0
var quiet_seen := 0
func _collect(i: int, quiet: bool = false) -> void:
	if kind[i] == KIND_COIN:
		got_gold += value[i]
	else:
		got += value[i]
	taken += 1
	if quiet:
		quiet_n += 1
		var h: Vector3 = game.player.global_position
		if Vector2(pos[i].x - h.x, pos[i].z - h.z).length() <= edge_at(pos[i], h):
			quiet_seen += 1
	super(i, quiet)
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game with a fake hero at the origin, no map (the sand flat at 0) and a real (counting) PickupManager.
func _pickups() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var pm: PickupManager = auto_free(_script(COUNTING).new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	return {"g": g, "hero": hero, "pm": pm}


## The run's camera (a real CameraRig, as pass56_pk_test builds it), bolted to the hero at the origin.
func _camera(w: Dictionary) -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	rig.snap_to(w["hero"])
	w["g"].camera = rig
	return rig


func _tick(pm: PickupManager, seconds: float, step: float = DT) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		pm._physics_process(step)
		t += step


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## `n` pickups spread over the ring `from`..`to` m round the origin (gems of the three sizes, worth 1, 5 and 25, and a
## coin every `coin_every`), the same field every time. Returns {slot: [kind, value]}.
func _field(pm: PickupManager, n: int, from: float, to: float, coin_every := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var out := {}
	for k in range(n):
		var kd: int = k % 3
		if coin_every > 0 and k % coin_every == 0:
			kd = PickupManager.KIND_COIN
		var v: float = [1.0, 5.0, 25.0, 3.0][kd]
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf_range(from * from, to * to))
		var i := pm.spawn(kd, Vector3(cos(a) * d, 0.0, sin(a) * d), v)
		assert_int(i).is_greater_equal(0)
		out[i] = [kd, v]
	return out


func _alive(pm: PickupManager) -> Array:
	var out: Array = []
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1:
			out.append(i)
	return out


# ---------------------------------------------------------------- 1. never lost, never merged

func test_three_thousand_gems_never_merge_and_none_is_lost() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var made := _field(pm, 3000, 6.0, 60.0)
	assert_int(pm.count).is_equal(3000)
	# the pool grew past its start (MAX) and every kind's MultiMesh with it
	assert_int(pm.alive.size()).is_greater_equal(3000)
	assert_int(pm.alive.size()).is_greater(PickupManager.MAX)
	_tick(pm, 3.0)
	var total := 0.0
	for i: int in made:
		assert_int(pm.alive[i]).override_failure_message("gem %d went" % i).is_equal(1)
		assert_int(pm.kind[i]).is_equal(int(made[i][0]))
		assert_float(pm.value[i]).is_equal(float(made[i][1]))
		total += pm.value[i]
	assert_int(_alive(pm).size()).is_equal(3000)
	var want := 0.0
	for i: int in made:
		want += float(made[i][1])
	assert_float(total).is_equal(want)
	# and 1000 more on top: still nothing goes
	_field(pm, 1000, 6.0, 60.0)
	assert_int(pm.count).is_equal(4000)
	assert_int(_alive(pm).size()).is_equal(4000)


func test_coins_past_150_do_not_fuse() -> void:
	var pm: PickupManager = _pickups()["pm"]
	for k in range(400):
		pm.spawn(PickupManager.KIND_COIN, Vector3(30.0, 0.0, float(k % 20) * 0.5), 2.0)
	_tick(pm, 3.0)
	assert_int(pm.count_coins()).is_equal(400)
	var gold := 0.0
	for i: int in _alive(pm):
		assert_int(pm.kind[i]).is_equal(PickupManager.KIND_COIN)
		assert_float(pm.value[i]).is_equal(2.0)
		gold += pm.value[i]
	assert_float(gold).is_equal(800.0)
	# the old merge and the coins' cap are gone
	assert_bool(pm.has_method("_merge")).is_false()
	assert_bool("COIN_CAP" in pm).is_false()


func test_a_far_gem_stays_where_it_fell_for_minutes_of_run_time() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var far: Array = []
	for k in range(30):
		far.append(pm.spawn(k % 3, Vector3(25.0 + float(k), 0.0, -10.0 + float(k % 7)), 5.0))
	_tick(pm, 2.0)
	var at: Array = []
	for i: int in far:
		at.append(pm.pos[i])
	# five minutes of the run's clock (in 0.1 s ticks), hops and glints and all
	_tick(pm, 300.0, 0.1)
	for k in range(far.size()):
		var i: int = far[k]
		assert_int(pm.alive[i]).is_equal(1)
		assert_float(pm.value[i]).is_equal(5.0)
		assert_vector(pm.pos[i]).is_equal(at[k])


# ---------------------------------------------------------------- 2. lying still costs nothing

func test_resting_pickups_are_out_of_the_tick_and_out_of_the_draw() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var made := _field(pm, 600, 6.0, 60.0, 10)
	# falling from the kill: every one is in the active list
	assert_int(pm._act.size()).is_equal(600)
	_tick(pm, 2.0)
	# down: in the grid, none in the active list
	assert_int(pm._act.size()).is_equal(0)
	for i: int in made:
		assert_int(pm.act_at[i]).is_equal(-1)
		assert_int(pm.g_cell[i]).is_greater_equal(0)
	pm.record_draws = true
	pm._render()
	var drawn: Dictionary = {}
	for i: int in made:
		drawn[i] = pm.drawn_xf[i]
	# a second of play: not one instance or custom datum written
	pm.instance_writes = 0
	pm.custom_writes = 0
	for f in range(60):
		pm._physics_process(DT)
		pm._render()
	assert_int(pm.instance_writes).is_equal(0)
	assert_int(pm.custom_writes).is_equal(0)
	for i: int in made:
		assert_bool((pm.drawn_xf[i] as Transform3D).is_equal_approx(drawn[i])).is_true()
	# every kind shows them all, in one packed run of instances, in a box of its own (the server never measures them)
	for k in range(PickupManager.KINDS):
		var mm: MultiMesh = pm._mms[k]
		assert_int(mm.visible_instance_count).is_equal(pm._inst_n[k])
		var box = mm.get("custom_aabb")
		assert_bool(box is AABB).is_true()
		assert_float((box as AABB).size.x).is_equal_approx(400.0, 0.001)


func test_the_float_and_the_spin_live_in_the_shaders() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var g := pm.spawn(PickupManager.KIND_GEM_M, Vector3(20, 0, 0), 5.0)
	var c := pm.spawn(PickupManager.KIND_COIN, Vector3(22, 0, 0), 2.0)
	_tick(pm, 2.0)
	pm.record_draws = true
	pm._render()
	var xg: Transform3D = pm.drawn_xf[g]
	var xc: Transform3D = pm.drawn_xf[c]
	var sg0 := pm.shown_xf(g)
	var sc0 := pm.shown_xf(c)
	_tick(pm, 0.4)
	pm._render()
	# the instances never moved ...
	assert_bool((pm.drawn_xf[g] as Transform3D).is_equal_approx(xg)).is_true()
	assert_bool((pm.drawn_xf[c] as Transform3D).is_equal_approx(xc)).is_true()
	# ... the instance is where it lies, upright, with no float in it
	assert_float(xg.origin.y).is_equal_approx(pm.pos[g].y, 0.0001)
	assert_bool(xg.basis.is_equal_approx(Basis())).is_true()
	# ... while what shows floats and turns, as the shaders work it out at the run's clock
	var sg1 := pm.shown_xf(g)
	var sc1 := pm.shown_xf(c)
	assert_float(sg1.origin.y).is_equal_approx(pm.pos[g].y + PickupManager.float_y(g, pm._time), 0.0001)
	assert_float(absf(sg1.origin.y - sg0.origin.y)).is_greater(0.001)
	assert_bool(sg1.basis.is_equal_approx(sg0.basis)).is_false()
	assert_bool(sc1.basis.is_equal_approx(sc0.basis)).is_false()
	# the coin stands on its edge: its face (the cylinder's axis) lies flat
	assert_float(absf(sc1.basis.y.normalized().y)).is_less(0.001)
	# the clocks the shaders are given, wrapped on whole turns
	var gm: ShaderMaterial = pm._gem_mats[0]
	assert_float(float(gm.get_shader_parameter("t_now"))).is_equal_approx(fmod(pm._time, PickupManager.GEM_WRAP), 0.0001)
	assert_float(float(PickupManager.coin_material().get_shader_parameter("t_now"))).is_equal_approx(fmod(pm._time, PickupManager.COIN_WRAP), 0.0001)
	for turns: float in [PickupManager.GEM_WRAP * 2.0, PickupManager.GEM_WRAP * 2.4, PickupManager.COIN_WRAP * 3.0, PickupManager.COIN_WRAP * 2.4]:
		var whole := turns / TAU
		assert_float(absf(whole - roundf(whole))).is_less(0.00001)
	for path in ["res://core/shaders/gem.gdshader", "res://core/shaders/coin.gdshader"]:
		var code: String = (load(path) as Shader).code
		assert_str(code).contains("uniform float t_now")
		assert_str(code).contains("float_base")
		assert_str(code).contains("stencil_mode read, compare_not_equal, %d;" % PickupManager.PAINTING_STENCIL)
	assert_str((load("res://core/shaders/gem.gdshader") as Shader).code).contains("INSTANCE_CUSTOM.y")


func test_the_pool_and_its_multimeshes_grow_and_stay_packed() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var made := _field(pm, 2500, 6.0, 60.0, 7)
	_tick(pm, 2.0)
	pm._render()
	_check_packed(pm)
	assert_int((pm._mms[0] as MultiMesh).instance_count).is_greater_equal(pm._inst_n[0])
	# take a thousand anywhere in the run of instances: the kinds' last ones fill the holes, still packed
	var gone := 0
	for i: int in made:
		if gone >= 1000:
			break
		if i % 2 == 1:
			pm._free(i)
			gone += 1
	_check_packed(pm)
	assert_int(pm.count).is_equal(1500)
	# a cleared field shows nothing and fills again from the start
	pm.clear_all()
	pm._render()
	for k in range(PickupManager.KINDS):
		assert_int((pm._mms[k] as MultiMesh).visible_instance_count).is_equal(0)
	assert_int(pm.count).is_equal(0)
	assert_int(pm._act.size()).is_equal(0)
	_field(pm, 50, 6.0, 20.0)
	_tick(pm, 2.0)
	_check_packed(pm)
	assert_int(pm.count).is_equal(50)


## Every pickup holds one place in its kind's MultiMesh, the places of each kind run 0..n-1 without a gap, and each place
## knows its pickup.
func _check_packed(pm: PickupManager) -> void:
	var seen := {}
	var per := PackedInt32Array()
	per.resize(PickupManager.KINDS)
	for i: int in _alive(pm):
		var k: int = pm.kind[i]
		var n: int = pm.inst[i]
		assert_int(n).is_between(0, pm._inst_n[k] - 1)
		assert_bool(seen.has(k * 100000 + n)).is_false()
		seen[k * 100000 + n] = true
		assert_int(pm._islot[k * pm._icap + n]).is_equal(i)
		per[k] += 1
	for k in range(PickupManager.KINDS):
		assert_int(per[k]).is_equal(pm._inst_n[k])


# ---------------------------------------------------------------- 3. the magnet and the big pull take every one

func test_the_magnet_and_a_vacuum_collect_every_one_exactly() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var made := _field(pm, 2000, 6.0, 60.0, 9)
	# a little heap far off, which the hero walks onto
	var heap: Array = []
	for k in range(20):
		heap.append(pm.spawn(PickupManager.KIND_GEM_S, Vector3(40.0 + 0.1 * float(k % 5), 0.0, 40.0 + 0.1 * float(k / 5)), 1.0))
	_tick(pm, 2.0)
	var xp_heap := 0.0
	var xp_all := 0.0
	var gold_all := 0.0
	for i: int in made:
		if int(made[i][0]) == PickupManager.KIND_COIN:
			gold_all += float(made[i][1])
		else:
			xp_all += float(made[i][1])
	for i: int in heap:
		xp_heap += pm.value[i]
	hero.global_position = Vector3(40.2, 0.0, 40.2)
	_tick(pm, 2.0)
	for i: int in heap:
		assert_int(pm.alive[i]).is_equal(0)
	var got: float = pm.get("got")
	# (the field's own gems the hero stood near were taken too)
	assert_float(got).is_greater_equal(xp_heap)
	# the big pull: every one comes, never more than FLIGHT_MAX on their way at once
	hero.global_position = Vector3.ZERO
	pm.vacuum_all(true)
	var most := 0
	var t := 0.0
	while pm.count > 0 and t < 90.0:
		pm._physics_process(DT)
		t += DT
		most = maxi(most, pm._flying_n)
	assert_int(pm.count).is_equal(0)
	assert_int(most).is_less_equal(PickupManager.FLIGHT_MAX)
	assert_int(most).is_greater(PickupManager.FLIGHT_MAX / 2)
	assert_float(float(pm.get("got"))).is_equal(xp_all + xp_heap)
	assert_float(float(pm.get("got_gold"))).is_equal(gold_all)
	assert_int(int(pm.get("taken"))).is_equal(2020)
	assert_int(pm._flying_n).is_equal(0)
	assert_int(pm._act.size()).is_equal(0)
	assert_bool(pm._vac_on).is_false()


func test_a_big_pull_starts_the_ones_off_the_screen_just_past_its_edge() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	_camera(w)
	var made := _field(pm, 1500, 4.0, 62.0)
	_tick(pm, 2.0)
	var want := 0.0
	for i: int in made:
		want += float(made[i][1])
	pm.vacuum_all()
	# the screen's edge on the sand was measured: some metres out all round, nowhere near the whole arena
	assert_int(pm._edge_r.size()).is_equal(PickupManager.EDGE_BINS)
	for r: float in pm._edge_r:
		assert_float(r).is_between(3.0, 60.0)
	var hero := Vector3.ZERO
	var d0 := {}
	var edge := {}
	for i: int in made:
		d0[i] = _flat(pm.pos[i])
		edge[i] = pm.edge_at(pm.pos[i], hero)
	assert_int(pm._flying_n).is_less_equal(PickupManager.FLIGHT_MAX)
	var near_arcs := 0
	var far_seen := {}
	var most_edge := 0
	var t := 0.0
	while pm.count > 0 and t < 30.0:
		for i: int in made:
			if pm.alive[i] == 0 or pm.flying[i] == 0:
				continue
			if float(d0[i]) <= float(edge[i]):
				if pm.phase[i] == PickupManager.PHASE_ARC_WAIT:
					near_arcs += 1
				continue
			# one off the screen: never thrown up where it lay; it starts its dive just past the edge, in its turn
			assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_FLY)
			assert_int(pm.edge_f[i]).is_equal(1)
			if not far_seen.has(i):
				far_seen[i] = true
				assert_float(t).is_greater_equal(PickupManager.FAR_LEAD - DT)
				var d := _flat(pm.pos[i])
				assert_float(d).is_between(float(edge[i]) - 0.01, float(edge[i]) + 0.01)
				assert_float(d).is_less_equal(float(d0[i]) + 0.01)
				assert_float(pm.charge_of(i)).is_equal(1.0)
		most_edge = maxi(most_edge, pm._edge_n)
		pm._physics_process(DT)
		t += DT
	assert_int(pm.count).is_equal(0)
	assert_int(near_arcs).is_greater(0)
	assert_int(far_seen.size()).is_greater(100)
	assert_int(most_edge).is_less_equal(PickupManager.EDGE_MAX)
	# the ones the edge's stream had no room for were taken unseen, never one lying on the screen, and every one's XP came
	assert_int(int(pm.get("quiet_n"))).is_greater(0)
	assert_int(int(pm.get("quiet_seen"))).is_equal(0)
	assert_float(float(pm.get("got"))).is_equal(want)
	assert_int(pm._edge_n).is_equal(0)
	assert_int(pm._flying_n).is_equal(0)


func test_a_pull_waits_while_the_hero_is_down() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	_field(pm, 1200, 6.0, 60.0)
	_tick(pm, 2.0)
	pm.vacuum_all()
	var left := pm.count
	hero.set("dead", true)
	_tick(pm, 3.0)
	# nothing taken while he is down, and the pull calls no more (the ones on their way lie down where they reach him)
	assert_int(pm.count).is_equal(1200)
	var flying := pm._flying_n
	_tick(pm, 1.0)
	assert_int(pm._flying_n).is_less_equal(flying)
	assert_bool(pm._vac_on).is_true()
	hero.set("dead", false)
	_tick(pm, 40.0)
	assert_int(pm.count).is_equal(0)
	assert_int(left).is_equal(1200)


# ---------------------------------------------------------------- 4. the review of pass 61

## A wait re-queued while the reading lags (the edge's stream full, after the hero was down) and the tick's turns run out
## in the same bucket: no wait is left behind the reading, and every one is taken in the end.
func test_off_screen_waits_are_never_left_behind_the_reading() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var made := _field(pm, 200, 15.0, 30.0)
	_tick(pm, 2.0)
	# a screen edge 2 m out all round (there is no camera here): every one of them is off it; the edge's stream is full
	var edge := PackedFloat32Array()
	edge.resize(PickupManager.EDGE_BINS)
	edge.fill(2.0)
	pm._edge_r = edge
	pm._edge_t = 1.0e9
	pm._edge_n = PickupManager.EDGE_MAX
	# all their turns came due long ago, in one bucket the reading is still at
	var b0 := floori(pm._time / PickupManager.IDLE_BUCKET) - 40
	pm._vq_next = b0
	for i: int in made:
		pm.vac_q[i] = 1
		pm._vq_add(i, float(b0) * PickupManager.IDLE_BUCKET)
	pm._physics_process(DT)
	# VQ_TURNS taken, each re-queued ahead; the rest kept where the reading is, none behind it
	assert_int(pm._vq_next).is_equal(b0)
	for k in pm._vq.keys():
		assert_int(int(k)).is_greater_equal(pm._vq_next)
	var t := 0.0
	while pm.count > 0 and t < 20.0:
		pm._physics_process(DT)
		t += DT
		for k in pm._vq.keys():
			assert_int(int(k)).is_greater_equal(pm._vq_next)
	assert_int(pm.count).is_equal(0)
	for i: int in made:
		assert_int(pm.vac_q[i]).is_equal(0)
	_tick(pm, 1.0)
	assert_bool(pm._vq.is_empty()).is_true()


func test_a_vacuum_gem_taken_unseen_starts_nothing() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var v := pm.spawn(PickupManager.KIND_VACUUM, Vector3(30, 0, 0), 0.0)
	var g := pm.spawn(PickupManager.KIND_GEM_S, Vector3(-30, 0, 0), 1.0)
	_tick(pm, 2.0)
	pm._collect(v, true)
	assert_int(pm.alive[v]).is_equal(0)
	assert_bool(pm._vac_on).is_false()
	assert_int(pm.flying[g]).is_equal(0)
	# one the hero really reaches starts a pull
	var v2 := pm.spawn(PickupManager.KIND_VACUUM, Vector3(30, 0, 5), 0.0)
	_tick(pm, 2.0)
	pm._collect(v2)
	assert_int(pm.flying[g]).is_equal(1)


func test_the_phase_is_a_seed_and_a_coin_floats_straight_up_whatever_its_turn() -> void:
	var pm: PickupManager = _pickups()["pm"]
	# the phase rides as a seed 0..1 (a half float carries it), the same value the CPU's sums use
	for i in [0, 1, 777, 2047, 4095, 9000]:
		assert_float(PickupManager.phase_of(i)).is_between(0.0, TAU)
		if i < pm._seed.size():
			assert_float(pm._seed[i] * TAU).is_equal_approx(PickupManager.phase_of(i), 0.0001)
	assert_bool((pm._mms[PickupManager.KIND_COIN] as MultiMesh).use_custom_data).is_true()
	var c := pm.spawn(PickupManager.KIND_COIN, Vector3(20, 0, 0), 2.0)
	_tick(pm, 2.0)
	# on the arc, its extra spin turning through every angle, and knocked loose, tumbling: the float is straight up and
	# smooth, never jumping with the turn
	pm.flying[c] = 1
	pm.arced[c] = 1
	pm.phase[c] = PickupManager.PHASE_FLY
	var last := INF
	for k in range(64):
		pm.arc_spin[c] = TAU * float(k) / 16.0
		var xf := pm.shown_xf(c)
		assert_float(xf.origin.y).is_equal_approx(pm.pos[c].y + PickupManager.float_y(c, pm._time), 0.00001)
		assert_float(Vector2(xf.origin.x - pm.pos[c].x, xf.origin.z - pm.pos[c].z).length()).is_less(0.00001)
		if last != INF:
			assert_float(absf(xf.origin.y - last)).is_less(0.00001)
		last = xf.origin.y
	pm.flying[c] = 0
	pm.arced[c] = 0
	pm.phase[c] = PickupManager.PHASE_TOSS
	pm.hop_dir[c] = Vector3(0.6, 0.0, 0.8)
	for k in range(10):
		pm.phase_t[c] = 0.05 * float(k)
		var xf := pm.shown_xf(c)
		assert_float(xf.origin.y).is_equal_approx(pm.pos[c].y + PickupManager.float_y(c, pm._time), 0.00001)


func test_a_real_runs_field_never_grows_the_pool() -> void:
	var pm: PickupManager = _pickups()["pm"]
	assert_int(PickupManager.MAX).is_greater_equal(2048)
	assert_int(PickupManager.INST_START).is_greater_equal(1024)
	# more than the most a stage-1 run left lying in pass 61's count (876)
	_field(pm, 1500, 6.0, 60.0, 11)
	_tick(pm, 1.0)
	assert_int(pm.alive.size()).is_equal(PickupManager.MAX)
	assert_int(pm._icap).is_equal(PickupManager.INST_START)
