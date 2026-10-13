extends GdUnitTestSuite

## Pass 60, lane PK (Garry: the magnet "should make the gems fly up and then down to the Player. If possible a cheap shader
## that makes the gems look like they are 'charged' while they are flying", for "the things that do big pulls" only (the
## Magnet Pulse, the Uber Magnet, the boss chest's opening, the Elite's white vacuum gem, Turret Family's attractors);
## "Make the EXP gems a shade darker so they are more easily visible on the sand background ... Maybe add low emit to
## them"): a vacuum or a turret's attractor sends a gem up the magnet arc (a wait rippling out from the hero, a throw metres
## up with a little drift, a hang at the apex, the dive on the flight's own code) and the walk-up pull keeps the hop and
## the flight; XP and gold arrive on arrival only; a gem is charged (custom data to core/shaders/gem.gdshader) only on
## the arc, and the draw writes custom data only for charged gems and once to clear a slot one left; the gems' colours are
## a shade darker with the same hues while the glints and motes keep the bright colours; the gem material is the shader,
## one a kind, drawn under the paintings as pass 54 had it.

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

## The effects, as far as the pickups care: the motes they leave, with their colours
const FAKE_FX := """extends Node
var motes: Array = []
func mote(_at, _v, _size, _life, color) -> void:
	motes.append(color)
"""

const DT := 1.0 / 60.0
## v0.45's gem colours (pass 46), the glints' and motes' still (GLINT_COLOURS)
const OLD := [Color(0.62, 0.48, 1.0), Color(0.45, 0.85, 1.0), Color(1.0, 0.55, 0.85), Color(1.0, 0.72, 0.25), Color(1.0, 1.0, 1.0)]


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game with a fake hero at the origin, no map (the sand flat at 0), a fake Fx and a real PickupManager.
func _pickups() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var fx := Node.new()
	fx.set_script(_script(FAKE_FX))
	g.add_child(fx)
	g.fx = fx
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	return {"g": g, "hero": hero, "pm": pm, "fx": fx}


## A pickup of `k` lying on the sand at (x, z), far past the hero's magnet unless placed near him.
func _resting(pm: PickupManager, k: int, x: float, z: float = 0.0) -> int:
	var i := pm.spawn(k, Vector3(x, 0, z), 1.0)
	pm.pos[i] = Vector3(x, PickupManager.rest_of(k), z)
	pm.vel[i] = Vector3.ZERO
	return i


func _tick(pm: PickupManager, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		pm._physics_process(DT)
		t += DT


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _mmi_of(pm: PickupManager, mm: MultiMesh) -> MultiMeshInstance3D:
	for c in pm.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == mm:
			return c
	return null


func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# ---------------------------------------------------------------- 1. who arcs and who hops

func test_a_vacuum_starts_the_arc_and_the_walk_up_pull_keeps_the_hop() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	# inside his reach: the hop, as in v0.45
	var near := _resting(pm, PickupManager.KIND_GEM_S, magnet * 0.6)
	pm._physics_process(DT)
	assert_int(pm.flying[near]).is_equal(1)
	assert_int(pm.phase[near]).is_equal(PickupManager.PHASE_HOP)
	assert_int(pm.arced[near]).is_equal(0)
	# far out: nothing calls it until the vacuum, which sends it up the arc
	var far := _resting(pm, PickupManager.KIND_GEM_M, 12.0)
	pm._physics_process(DT)
	assert_int(pm.flying[far]).is_equal(0)
	pm.vacuum_all()
	assert_int(pm.flying[far]).is_equal(1)
	assert_int(pm.phase[far]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_int(pm.arced[far]).is_equal(1)
	# the one already hopping is left alone: no arc for it
	assert_int(pm.phase[near]).is_equal(PickupManager.PHASE_HOP)
	assert_int(pm.arced[near]).is_equal(0)
	# the phases are their own numbers
	assert_int(PickupManager.PHASE_ARC_WAIT).is_equal(4)
	assert_int(PickupManager.PHASE_ARC_RISE).is_equal(5)


func test_a_turret_attractor_arcs_the_gems_it_reaches() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var caught := _resting(pm, PickupManager.KIND_GEM_M, 10.0)
	var out := _resting(pm, PickupManager.KIND_GEM_M, 10.0, 6.0)
	pm.add_attractor(Vector3(10, 0, 0), 4.0)
	pm._physics_process(DT)
	assert_int(pm.flying[caught]).is_equal(1)
	assert_int(pm.phase[caught]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_int(pm.arced[caught]).is_equal(1)
	assert_int(pm.flying[out]).is_equal(0)


# ---------------------------------------------------------------- 2. the arc

func test_the_arc_rises_hangs_and_dives_in_paying_only_on_arrival() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var i := _resting(pm, PickupManager.KIND_GEM_L, 8.0)
	var rest: float = pm.pos[i].y
	var xp0: float = Run.xp
	var lv0: int = Run.level
	pm.vacuum_all()
	var phases: Array = []
	var top := 0.0
	var hung := false
	var t := 0.0
	while pm.alive[i] == 1 and t < 4.0:
		pm._physics_process(DT)
		t += DT
		if pm.alive[i] == 0:
			break
		if phases.is_empty() or int(phases[phases.size() - 1]) != pm.phase[i]:
			phases.append(int(pm.phase[i]))
		top = maxf(top, pm.pos[i].y)
		if pm.phase[i] == PickupManager.PHASE_ARC_RISE and pm.arc_apex[i] >= 0.0:
			# hanging at the apex: no speed
			hung = true
			assert_vector(pm.vel[i]).is_equal(Vector3.ZERO)
		# nothing is his until it gets there
		assert_float(Run.xp).is_equal(xp0)
		assert_int(Run.level).is_equal(lv0)
	assert_array(phases).contains_exactly([PickupManager.PHASE_ARC_WAIT, PickupManager.PHASE_ARC_RISE, PickupManager.PHASE_FLY])
	assert_float(top).is_greater(rest + 1.5)
	assert_bool(hung).is_true()
	assert_int(pm.alive[i]).is_equal(0)
	assert_float(t).is_less(4.0)
	assert_float(Run.xp).is_greater(xp0)


func test_the_wait_ripples_out_from_the_hero_and_never_past_the_cap() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var near := _resting(pm, PickupManager.KIND_GEM_S, 2.0)
	var far := _resting(pm, PickupManager.KIND_GEM_S, 14.0)
	var very := _resting(pm, PickupManager.KIND_GEM_S, 40.0)
	pm.vacuum_all()
	var j := PickupManager.ARC_WAIT_JITTER + 0.0001
	assert_float(pm.arc_delay[near]).is_between(PickupManager.ARC_WAIT_PER_M * 2.0 - 0.0001, PickupManager.ARC_WAIT_PER_M * 2.0 + j)
	assert_float(pm.arc_delay[far]).is_between(PickupManager.ARC_WAIT_PER_M * 14.0 - 0.0001, PickupManager.ARC_WAIT_PER_M * 14.0 + j)
	assert_float(pm.arc_delay[very]).is_between(PickupManager.ARC_WAIT_MAX - 0.0001, PickupManager.ARC_WAIT_MAX + j)
	assert_float(pm.arc_delay[far]).is_greater(pm.arc_delay[near])
	assert_float(PickupManager.ARC_WAIT_MAX + PickupManager.ARC_WAIT_JITTER).is_less_equal(0.62)
	# until its turn it sits where it lies
	var p0: Vector3 = pm.pos[far]
	_tick(pm, 0.3)
	assert_int(pm.phase[far]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_vector(pm.pos[far]).is_equal_approx(p0, Vector3.ONE * 0.0001)
	# the near one has gone up by then, the far one goes at its own delay
	assert_int(pm.phase[near]).is_not_equal(PickupManager.PHASE_ARC_WAIT)
	var waited: float = pm.phase_t[far]
	while pm.phase[far] == PickupManager.PHASE_ARC_WAIT:
		waited = pm.phase_t[far]
		pm._physics_process(DT)
	assert_float(waited).is_between(pm.arc_delay[far] - DT - 0.0001, pm.arc_delay[far] + 0.0001)


func test_the_launch_goes_up_with_a_little_drift_then_hangs_at_the_apex() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var i := _resting(pm, PickupManager.KIND_GEM_M, 6.0)
	var rest: float = pm.pos[i].y
	pm.vacuum_all()
	while pm.phase[i] == PickupManager.PHASE_ARC_WAIT:
		pm._physics_process(DT)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_RISE)
	assert_float(pm.phase_t[i]).is_equal(0.0)
	# the first beat of the rise: nearly its launch speed up, the drift across
	var v: Vector3 = pm.vel[i]
	assert_float(Vector2(v.x, v.z).length()).is_between(PickupManager.ARC_DRIFT_MIN - 0.0001, PickupManager.ARC_DRIFT_MAX + 0.0001)
	assert_float(v.y).is_greater(sqrt(2.0 * PickupManager.ARC_GRAV * PickupManager.ARC_HEIGHT_MIN) - 0.0001)
	assert_float(pm.arc_v0[i]).is_equal_approx(v.y, 0.0001)
	# its line out: straight away from him, turned by at most the fan
	assert_float(pm.hop_dir[i].x).is_greater(cos(PickupManager.ARC_DRIFT_FAN) - 0.0001)
	assert_float(pm.hop_dir[i].length()).is_equal_approx(1.0, 0.0001)
	# up to the apex: ARC_HEIGHT_MIN to ARC_HEIGHT_MIN + ARC_HEIGHT_RANGE (+ the distance's share) over its rest
	while pm.phase[i] == PickupManager.PHASE_ARC_RISE and pm.arc_apex[i] < 0.0:
		pm._physics_process(DT)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_RISE)
	var h: float = pm.pos[i].y - rest
	assert_float(h).is_greater(PickupManager.ARC_HEIGHT_MIN - 0.15)
	assert_float(h).is_less(PickupManager.ARC_HEIGHT_MIN + PickupManager.ARC_HEIGHT_RANGE + PickupManager.ARC_HEIGHT_PER_M * 6.0 + 0.05)
	# it drifted out a little on the way up
	assert_float(_flat(pm.pos[i])).is_greater(6.0 + 0.1)
	# the hang: still, for its own ARC_HANG_MIN..ARC_HANG_MAX, then the dive from a standstill
	var hang: float = pm.arc_hang[i]
	assert_float(hang).is_between(PickupManager.ARC_HANG_MIN, PickupManager.ARC_HANG_MAX)
	var apex: Vector3 = pm.pos[i]
	var held := 0.0
	while pm.phase[i] == PickupManager.PHASE_ARC_RISE:
		pm._physics_process(DT)
		held += DT
		if pm.phase[i] == PickupManager.PHASE_ARC_RISE:
			assert_vector(pm.pos[i]).is_equal(apex)
	assert_float(held).is_between(hang - 0.0001, hang + DT + 0.0001)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_FLY)
	assert_float(pm.phase_t[i]).is_equal(0.0)
	assert_int(pm.arced[i]).is_equal(1)
	# and down it comes, into him
	_tick(pm, 3.0)
	assert_int(pm.alive[i]).is_equal(0)


func test_the_wait_lets_a_falling_drop_land_and_the_launch_starts_where_it_lies() -> void:
	var pm: PickupManager = _pickups()["pm"]
	# a drop popping out of a kill, still in the air when the pull comes (a boss's death: the gems and the vacuum at once)
	var i := pm.spawn(PickupManager.KIND_GEM_S, Vector3(16, 0, 0), 1.0)
	assert_float(pm.vel[i].y).is_greater(0.0)
	pm.vacuum_all()
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_WAIT)
	# it falls on through its wait and lies down before its turn (16 m: the wait is at its cap)
	var landed := false
	while pm.phase[i] == PickupManager.PHASE_ARC_WAIT:
		pm._physics_process(DT)
		if pm.phase[i] == PickupManager.PHASE_ARC_WAIT and pm.vel[i] == Vector3.ZERO:
			landed = true
			assert_float(pm.pos[i].y).is_equal_approx(PickupManager.rest_of(PickupManager.KIND_GEM_S), 0.0001)
	assert_bool(landed).is_true()
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_RISE)
	assert_float(pm.pos[i].y).is_equal_approx(PickupManager.rest_of(PickupManager.KIND_GEM_S), 0.0001)
	_tick(pm, 4.0)
	assert_int(pm.alive[i]).is_equal(0)


func test_a_second_call_never_restarts_an_arc_and_the_magnet_never_grabs_a_waiting_gem() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var i := _resting(pm, PickupManager.KIND_GEM_S, 12.0)
	pm.vacuum_all()
	pm._physics_process(DT)
	var pt: float = pm.phase_t[i]
	var dl: float = pm.arc_delay[i]
	pm.vacuum_all()
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_float(pm.phase_t[i]).is_equal(pt)
	assert_float(pm.arc_delay[i]).is_equal(dl)
	# he steps onto it: the walk-up pull would take a resting gem; this one is on its way
	hero.global_position = Vector3(12, 0, 0)
	pm._physics_process(DT)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_float(pm.phase_t[i]).is_equal_approx(pt + DT, 0.0001)
	# (a merge left it alone too: the merge is gone since pass 61)
	# and it still ends in him
	hero.global_position = Vector3.ZERO
	_tick(pm, 4.0)
	assert_int(pm.alive[i]).is_equal(0)


func test_coins_arc_with_the_vacuum_and_pay_on_arrival() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var coin := _resting(pm, PickupManager.KIND_COIN, 9.0)
	pm.vacuum_all()
	assert_int(pm.flying[coin]).is_equal(0)
	pm.vacuum_all(true)
	assert_int(pm.flying[coin]).is_equal(1)
	assert_int(pm.phase[coin]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_int(pm.arced[coin]).is_equal(1)
	# the coin's own shader shows no charge and the draw writes it none (re-pinned in pass 61: its MultiMesh carries custom
	# data now, the seed its float and spin are timed by, written once when it is made)
	assert_bool((pm._mms[PickupManager.KIND_COIN] as MultiMesh).use_custom_data).is_true()
	pm._physics_process(DT)
	pm.custom_writes = 0
	pm._render()
	assert_int(pm.custom_writes).is_equal(0)
	var g0: int = Run.run_gold
	var top := 0.0
	var t := 0.0
	while pm.alive[coin] == 1 and t < 4.0:
		pm._physics_process(DT)
		t += DT
		top = maxf(top, pm.pos[coin].y)
		if pm.alive[coin] == 1:
			assert_int(Run.run_gold).is_equal(g0)
	assert_int(pm.alive[coin]).is_equal(0)
	assert_float(top).is_greater(PickupManager.REST + 1.5)
	assert_int(Run.run_gold).is_greater(g0)


# ---------------------------------------------------------------- 3. the charge

func test_the_charge_is_full_on_the_arc_and_zero_on_the_sand_and_the_hop() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	var ground := _resting(pm, PickupManager.KIND_GEM_S, 20.0)
	var hop := _resting(pm, PickupManager.KIND_GEM_M, magnet * 0.6)
	var arc := _resting(pm, PickupManager.KIND_GEM_L, 10.0)
	pm._physics_process(DT)
	assert_int(pm.phase[hop]).is_equal(PickupManager.PHASE_HOP)
	assert_float(pm.charge_of(ground)).is_equal(0.0)
	assert_float(pm.charge_of(hop)).is_equal(0.0)
	pm.vacuum_all()
	assert_float(pm.charge_of(hop)).is_equal(0.0)
	# it fades in over the wait, full by the launch
	pm._physics_process(DT)
	var c1: float = pm.charge_of(arc)
	assert_float(c1).is_greater(0.0)
	assert_float(c1).is_equal_approx(DT / maxf(pm.arc_delay[arc], PickupManager.CHARGE_RISE), 0.001)
	var last := c1
	while pm.phase[arc] == PickupManager.PHASE_ARC_WAIT:
		pm._physics_process(DT)
		var c: float = pm.charge_of(arc)
		assert_float(c).is_greater_equal(last)
		assert_float(c).is_less_equal(1.0)
		last = c
	assert_int(pm.phase[arc]).is_equal(PickupManager.PHASE_ARC_RISE)
	assert_float(pm.charge_of(arc)).is_equal(1.0)
	while pm.alive[arc] == 1 and pm.phase[arc] != PickupManager.PHASE_FLY:
		pm._physics_process(DT)
	assert_int(pm.alive[arc]).is_equal(1)
	assert_float(pm.charge_of(arc)).is_equal(1.0)
	# the hop's own flight shows none
	while pm.alive[hop] == 1 and pm.phase[hop] != PickupManager.PHASE_FLY:
		pm._physics_process(DT)
	if pm.alive[hop] == 1:
		assert_float(pm.charge_of(hop)).is_equal(0.0)


func test_the_charge_reaches_the_gem_multimesh_as_custom_data_only_while_it_is_on() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var gems: Array = []
	for k in range(50):
		gems.append(_resting(pm, PickupManager.KIND_GEM_S, 12.0 + float(k % 10) * 0.6, -3.0 + floorf(float(k) / 10.0) * 1.5))
	pm._physics_process(DT)
	pm.record_draws = true
	pm.custom_writes = 0
	pm._render()
	# a field of resting gems costs the draw no custom-data write at all
	assert_int(pm.custom_writes).is_equal(0)
	for i: int in gems:
		assert_float(pm.drawn_charge[i]).is_equal(0.0)
	# the pull: every one is written, charged
	pm.vacuum_all()
	pm._physics_process(DT)
	pm.custom_writes = 0
	pm._render()
	assert_int(pm.custom_writes).is_equal(50)
	for i: int in gems:
		assert_float(pm.drawn_charge[i]).is_greater(0.0)
		assert_float(pm.drawn_charge[i]).is_less_equal(1.0)
	# all taken
	_tick(pm, 5.0)
	for i: int in gems:
		assert_int(pm.alive[i]).is_equal(0)
	# a resting gem drawn into a slot a charged one left: one write to clear it, then none (re-pinned in pass 61: the
	# write is the spawn's, which also gives the shader the gem's slot for its float and spin)
	pm.custom_writes = 0
	var j := _resting(pm, PickupManager.KIND_GEM_S, 20.0)
	pm._physics_process(DT)
	pm._render()
	assert_int(pm.custom_writes).is_equal(1)
	assert_float(pm.drawn_charge[j]).is_equal(0.0)
	pm._render()
	assert_int(pm.custom_writes).is_equal(1)
	# the seeds the shimmer rides on: one a slot, spread over 0..1
	assert_int(pm._seed.size()).is_equal(PickupManager.MAX)
	assert_float(pm._seed[1]).is_not_equal(pm._seed[2])
	assert_float(pm._seed[j]).is_between(0.0, 1.0)


func test_the_arc_spins_faster_and_pops_as_it_leaves() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var i := _resting(pm, PickupManager.KIND_GEM_M, 6.0)
	pm._physics_process(DT)
	pm.record_draws = true
	pm.vacuum_all()
	while pm.phase[i] == PickupManager.PHASE_ARC_WAIT:
		pm._physics_process(DT)
	# the launch tick only throws it; the first beat of the rise: the hop's pop, and the extra spin has begun
	pm._physics_process(DT)
	pm._render()
	var xf: Transform3D = pm.drawn_xf[i]
	assert_float(xf.basis.get_scale().x).is_greater(1.2)
	assert_float(pm.arc_spin[i]).is_greater(0.0)
	assert_float(pm.arc_spin[i]).is_equal_approx(PickupManager.ARC_SPIN * DT, 0.001)
	# by ARC_POP_TIME it is its own size again, still rising
	_tick(pm, PickupManager.ARC_POP_TIME + 2.0 * DT)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_ARC_RISE)
	pm._render()
	xf = pm.drawn_xf[i]
	assert_float(xf.basis.get_scale().x).is_equal_approx(1.0, 0.001)
	# the extra spin is in the draw: without it the gem would be turned arc_spin less
	var spin: float = pm.arc_spin[i]
	assert_float(spin).is_greater(2.0)
	var with_spin: Vector3 = xf.basis.x
	pm.arc_spin[i] = 0.0
	pm._render()
	var without: Vector3 = (pm.drawn_xf[i] as Transform3D).basis.x
	pm.arc_spin[i] = spin
	assert_float(absf(without.signed_angle_to(with_spin, Vector3.UP))).is_equal_approx(absf(wrapf(spin, -PI, PI)), 0.01)
	# it keeps turning, slower, through the dive
	while pm.alive[i] == 1 and pm.phase[i] != PickupManager.PHASE_FLY:
		pm._physics_process(DT)
	var s1: float = pm.arc_spin[i]
	pm._physics_process(DT)
	assert_float(pm.arc_spin[i]).is_equal_approx(s1 + PickupManager.ARC_SPIN * 0.5 * DT, 0.001)


# ---------------------------------------------------------------- 4. the look

func test_the_colours_are_a_shade_darker_with_the_same_hue_and_the_glints_as_bright_as_before() -> void:
	assert_float(PickupManager.GEM_SHADE).is_equal_approx(0.78, 0.0001)
	assert_int(PickupManager.COLOURS.size()).is_equal(5)
	assert_int(PickupManager.GLINT_COLOURS.size()).is_equal(5)
	for k in range(5):
		assert_bool((PickupManager.GLINT_COLOURS[k] as Color).is_equal_approx(OLD[k])).override_failure_message("glint colour %d moved" % k).is_true()
	for k in range(3):
		var c: Color = PickupManager.COLOURS[k]
		var o: Color = OLD[k]
		assert_float(c.r).is_equal_approx(o.r * PickupManager.GEM_SHADE, 0.001)
		assert_float(c.g).is_equal_approx(o.g * PickupManager.GEM_SHADE, 0.001)
		assert_float(c.b).is_equal_approx(o.b * PickupManager.GEM_SHADE, 0.001)
		assert_float(c.a).is_equal(1.0)
		assert_float(_luminance(c)).is_less(_luminance(o) * 0.8)
		assert_float(c.h).is_equal_approx(o.h, 0.01)
		assert_float(c.s).is_equal_approx(o.s, 0.01)
	# the coin and the vacuum as they were
	assert_bool((PickupManager.COLOURS[PickupManager.KIND_COIN] as Color).is_equal_approx(OLD[PickupManager.KIND_COIN])).is_true()
	assert_bool((PickupManager.COLOURS[PickupManager.KIND_VACUUM] as Color).is_equal_approx(OLD[PickupManager.KIND_VACUUM])).is_true()
	# a low glow on the sand, a bright one charged
	assert_float(PickupManager.GEM_EMISSION).is_equal_approx(0.3, 0.0001)
	assert_float(PickupManager.CHARGED_EMISSION).is_greater(PickupManager.GEM_EMISSION)
	# the glint on a resting gem is the bright colour paled, as before
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var l := _resting(pm, PickupManager.KIND_GEM_L, 20.0)
	pm._physics_process(DT)
	pm.start_glint(l)
	pm.glint_t[l] = PickupManager.GLINT_TIME * 0.37
	var want: Color = (OLD[PickupManager.KIND_GEM_L] as Color).lerp(Color.WHITE, PickupManager.GLINT_PALE)
	var got := pm.glint_color(l)
	assert_float(got.r).is_equal_approx(want.r, 0.001)
	assert_float(got.g).is_equal_approx(want.g, 0.001)
	assert_float(got.b).is_equal_approx(want.b, 0.001)
	# the mote where a gem is taken and where a merge pops are the bright colours too
	var fx: Node = w["fx"]
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	var m := _resting(pm, PickupManager.KIND_GEM_M, magnet * 0.5)
	_tick(pm, 2.0)
	assert_int(pm.alive[m]).is_equal(0)
	var motes: Array = fx.get("motes")
	assert_int(motes.size()).is_equal(1)
	assert_bool((motes[0] as Color).is_equal_approx(OLD[PickupManager.KIND_GEM_M])).is_true()
	# (the mote where a merge popped went with the merge in pass 61)


func test_the_gem_material_is_the_charged_shader_drawn_under_the_paintings() -> void:
	var pm: PickupManager = _pickups()["pm"]
	# one MultiMesh a kind, as before
	assert_int(pm._mms.size()).is_equal(5)
	for k in [PickupManager.KIND_GEM_S, PickupManager.KIND_GEM_M, PickupManager.KIND_GEM_L, PickupManager.KIND_VACUUM]:
		var mm: MultiMesh = pm._mms[k]
		assert_bool(mm.use_custom_data).override_failure_message("kind %d carries no custom data" % k).is_true()
		var mmi := _mmi_of(pm, mm)
		assert_object(mmi).is_not_null()
		var mat := mmi.material_override as ShaderMaterial
		assert_object(mat).override_failure_message("kind %d is not on the gem shader" % k).is_not_null()
		assert_str((mat.shader as Shader).resource_path).is_equal("res://core/shaders/gem.gdshader")
		assert_int(mat.render_priority).is_equal(PickupManager.PICKUP_PRIORITY)
		var alb: Color = mat.get_shader_parameter("albedo")
		var want: Color = PickupManager.COLOURS[k]
		assert_float(alb.r).is_equal_approx(want.r, 0.001)
		assert_float(alb.g).is_equal_approx(want.g, 0.001)
		assert_float(alb.b).is_equal_approx(want.b, 0.001)
		assert_float(float(mat.get_shader_parameter("rest_emission"))).is_equal_approx(PickupManager.GEM_EMISSION, 0.0001)
		assert_float(float(mat.get_shader_parameter("charged_emission"))).is_equal_approx(PickupManager.CHARGED_EMISSION, 0.0001)
	# one material a kind: the small and the medium gem are not the same object
	var ms := _mmi_of(pm, pm._mms[PickupManager.KIND_GEM_S]).material_override
	var mm_m := _mmi_of(pm, pm._mms[PickupManager.KIND_GEM_M]).material_override
	assert_object(ms).is_not_same(mm_m)
	# the coin keeps its own look
	var coin := _mmi_of(pm, pm._mms[PickupManager.KIND_COIN])
	assert_object(coin.material_override).is_same(PickupManager.coin_material())
	# the shader: lit, mixed, no depth, the stencil read, the charge and the seed from the instance, no textures
	var code: String = (load("res://core/shaders/gem.gdshader") as Shader).code
	assert_str(code).contains("shader_type spatial;")
	assert_str(code).contains("blend_mix")
	assert_str(code).contains("depth_draw_never")
	# (pass 72, lane SPEC, re-pinned: the scenery writes stencil 2 now, so the pickups read 0, nothing painted)
	assert_str(code).contains("stencil_mode read, compare_equal, 0;")
	assert_str(code).contains("INSTANCE_CUSTOM.x")
	assert_str(code).contains("INSTANCE_CUSTOM.y")
	assert_str(code).contains("EMISSION")
	assert_str(code).contains("uniform vec3 albedo : source_color")
	assert_str(code).contains("uniform float rest_emission")
	assert_bool(code.contains("unshaded")).is_false()
	assert_bool(code.contains("sampler2D")).is_false()
	assert_bool(code.contains("next_pass")).is_false()
	# the material recipe stands on its own (Warmup and tools)
	var m := PickupManager.gem_material(Color(0.1, 0.2, 0.3))
	assert_object(m.shader).is_same((_mmi_of(pm, pm._mms[0]).material_override as ShaderMaterial).shader)
	assert_int(m.render_priority).is_equal(PickupManager.PICKUP_PRIORITY)
	# the warm-up draws one of each gem kind charged, so the shader's charged sums compile under the beam
	pm.warm_draw(Vector3(0, -8, 0))
	pm.custom_writes = 0
	pm._render()
	for k in [PickupManager.KIND_GEM_S, PickupManager.KIND_GEM_M, PickupManager.KIND_GEM_L, PickupManager.KIND_VACUUM]:
		assert_int((pm._mms[k] as MultiMesh).visible_instance_count).is_equal(1)
	assert_int((pm._mms[PickupManager.KIND_COIN] as MultiMesh).visible_instance_count).is_equal(1)
	pm.warm_draw(Vector3.INF)
	pm._render()
	assert_int((pm._mms[0] as MultiMesh).visible_instance_count).is_equal(0)

## Pass 60, death wins (the lead's guard): a gem on its way to a hero who went down lies down where it is, nothing is
## collected and no pull starts while he is down, and the pull takes it again once he is up.
func test_a_gem_that_reaches_a_dead_hero_lies_down_and_waits_for_the_revive() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var xp0: float = Run.xp
	var i := _resting(pm, PickupManager.KIND_GEM_M, 1.0)
	_tick(pm, 0.1)
	assert_int(int(pm.flying[i])).override_failure_message("the magnet starts the trip").is_equal(1)
	hero.set("dead", true)
	_tick(pm, 2.0)
	assert_float(Run.xp).override_failure_message("no XP on the corpse").is_equal(xp0)
	assert_int(int(pm.alive[i])).is_equal(1)
	assert_int(int(pm.flying[i])).override_failure_message("it lies down where it reached him").is_equal(0)
	assert_int(int(pm.phase[i])).is_equal(PickupManager.PHASE_GROUND)
	var j := _resting(pm, PickupManager.KIND_GEM_M, 0.8, 0.5)
	_tick(pm, 1.0)
	assert_int(int(pm.flying[j])).override_failure_message("no pull starts while he is down").is_equal(0)
	hero.set("dead", false)
	_tick(pm, 3.0)
	assert_float(Run.xp).override_failure_message("both are collected once he is up").is_greater(xp0)
	assert_int(int(pm.alive[i]) + int(pm.alive[j])).is_equal(0)
