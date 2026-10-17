extends GdUnitTestSuite

## Pass 87, lane BIGMOUTH (Garry: "Remove the tongue from the Big Mouth 3d Object. But keep a kind of a bright shining
## thing in the back of the Mouth when it's shooting the Laser. Add a bit of a wind-up animation to the Big Mouth as
## it's about to shoot, something short. And a visual 'punch back' when the laser is being shot"). The model has no
## tongue and a dark throat with a core and a flare anchor; the throat glows in the beam's colour, gathering through the
## wind-up and burning while it pours; the wind-up (params.beam.windup) is taken from the cooldown, so the shots keep
## their rhythm; the punch (params.beam.punch) kicks the mouth back along its aim and springs it past rest to settle,
## a smaller one on every pulse; a pull while it still pours pours on at once.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd, effects and ground marks.
func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	# the visual's Projectile node registers a shot kind
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": fx, "tg": tg, "cam": cam}


## A tough creature on its feet where it was put.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 200.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	return i


func _mouth(w: Dictionary, id := "big_mouth", muts: Array = []) -> LaserBeam:
	var inst := WeaponInstance.new(Registry.weapon(id), 1)
	for m: String in muts:
		inst.mutations.append(Registry.mutation(m))
	inst.rebuild(Run.player_sheet, [inst])
	var lb := LaserBeam.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(inst, w["g"])
	return lb


func _ticks(b: LaserBeam, seconds: float) -> void:
	for k in range(int(round(seconds / DT))):
		b._tick(DT)


func _near(a: Color, c: Color, eps := 0.01) -> bool:
	return absf(a.r - c.r) < eps and absf(a.g - c.g) < eps and absf(a.b - c.b) < eps


# ---------------------------------------------------------------- the model

func test_the_mouth_has_no_tongue_and_a_dark_throat_with_a_core() -> void:
	for path in ["res://content/weapons/big_mouth/big_mouth_visual.tscn", "res://content/evolutions/loudmouth/loudmouth_visual.tscn"]:
		var n: Node = (load(path) as PackedScene).instantiate()
		var mouth: Node = n.get_node_or_null("Familiar/Mouth")
		assert_object(mouth).override_failure_message(path + ": no mouth").is_not_null()
		assert_object(mouth.find_child("Tongue", true, false)).override_failure_message(path + ": the tongue is back").is_null()
		for part in ["Cavity", "ThroatBack", "Glow", "Flare", "Floor", "Jaw", "Upper"]:
			assert_object(mouth.find_child(part, true, false)).override_failure_message(path + ": no " + part).is_not_null()
		# the floor goes down with the jaw; the core sits behind the opening's anchor, deeper in the throat
		var jaw: Node = mouth.find_child("Jaw", true, false)
		assert_bool(jaw.is_ancestor_of(mouth.find_child("Floor", true, false))).is_true()
		var core := mouth.find_child("Glow", true, false) as Node3D
		var flare := mouth.find_child("Flare", true, false) as Node3D
		assert_float(core.position.z).is_greater(flare.position.z)
		n.free()


# ---------------------------------------------------------------- the numbers

func test_the_wind_up_punch_and_glow_numbers_come_from_params() -> void:
	var w := _world()
	var lb := _mouth(w)
	# the brief: a short wind-up, 0.15 to 0.3 s
	assert_float(lb.windup_seconds()).is_equal_approx(0.24, 0.0001)
	assert_float(lb.windup_seconds()).is_between(0.15, 0.3)
	assert_float(lb.windup_value("gape")).is_equal_approx(36.0, 0.0001)
	assert_float(lb.windup_value("rear")).is_equal_approx(0.35, 0.0001)
	assert_float(lb.punch_value("back")).is_equal_approx(0.36, 0.0001)
	assert_float(lb.punch_value("climb")).is_equal_approx(0.2, 0.0001)
	assert_float(lb.punch_value("pop")).is_equal_approx(0.2, 0.0001)
	assert_float(lb.punch_value("hz")).is_equal_approx(2.8, 0.0001)
	assert_float(lb.punch_value("decay")).is_equal_approx(7.5, 0.0001)
	assert_float(lb.punch_value("pulse")).is_equal_approx(0.3, 0.0001)
	assert_float(lb.throat_value("size")).is_equal_approx(0.9, 0.0001)
	# the Loudmouth's bigger mouth kicks further; a mutation's beam params leave the blocks alone
	var loud := _mouth(w, "loudmouth", ["mouth_burn", "mouth_knock", "mouth_arch"])
	assert_float(loud.punch_value("back")).is_equal_approx(0.45, 0.0001)
	assert_float(loud.windup_seconds()).is_equal_approx(0.24, 0.0001)
	# a key left out takes the default
	lb.inst.params["beam"]["punch"] = {}
	assert_float(lb.punch_value("back")).is_equal_approx(LaserBeam.PUNCH_DEFAULTS["back"], 0.0001)


# ---------------------------------------------------------------- the wind-up

func test_the_wind_up_gathers_the_glow_then_the_beam_pours() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	var lb := _mouth(w)
	lb._tick(DT)
	assert_float(lb.glow_level()).is_equal(0.0)
	assert_bool(lb._flare.visible).is_false()
	assert_bool(lb._glow_core.visible).is_false()
	assert_bool(lb._fire()).is_true()
	assert_int(lb.beams).is_equal(0)
	# halfway: the glow has gathered some, the core and the flare show, the jaw gapes and the lips rear up
	var frames := 0
	while lb.windup_f() < 0.5 and frames < 60:
		lb._tick(DT)
		frames += 1
	var first_half := frames
	assert_int(lb.beams).is_equal(0)
	var mid := lb.glow_level()
	assert_float(mid).is_between(0.2, 0.6)
	assert_bool(lb._flare.visible).is_true()
	assert_bool(lb._glow_core.visible).is_true()
	assert_float(lb._jaw.rotation.x).is_less(-deg_to_rad(10.0))
	assert_float(lb._model.rotation.x).is_greater(deg_to_rad(32.0) + 0.1)
	# at its end it pours, the glow at full
	frames = 0
	while lb.beams == 0 and frames < 60:
		lb._tick(DT)
		frames += 1
	assert_int(lb.beams).is_equal(1)
	# the whole wind-up took its seconds (a frame or two either way)
	assert_float(float(first_half + frames)).is_between(lb.windup_seconds() / DT - 2.0, lb.windup_seconds() / DT + 2.0)
	lb._tick(DT)
	assert_float(lb.glow_level()).is_greater(0.95)
	assert_float(lb._cavity_mat.emission_energy_multiplier).is_greater(0.5)


func test_the_wind_up_is_taken_from_the_cooldown_so_the_shots_keep_their_rhythm() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0), 2000.0)
	var lb := _mouth(w)
	var cd := lb.stat("cooldown", 1.0)
	var starts: Array = []
	var last := 0
	for f in range(int(ceil((2.0 * cd + 1.0) / DT))):
		lb._process(DT)
		if lb.beams != last:
			last = lb.beams
			starts.append(f)
	assert_int(starts.size()).is_greater_equal(2)
	# the first pours a wind-up after the pull, the next one cooldown later: the period is the cooldown's
	assert_float(float(starts[0])).is_between(lb.windup_seconds() / DT - 2.0, lb.windup_seconds() / DT + 2.0)
	assert_float(float(starts[1] - starts[0])).is_between(cd / DT - 2.0, cd / DT + 2.0)


func test_no_wind_up_pours_on_the_pull() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	var lb := _mouth(w)
	lb.inst.params["beam"]["windup"] = {"seconds": 0.0}
	assert_bool(lb._fire()).is_true()
	assert_int(lb.beams).is_equal(1)
	assert_float(lb._windup_t).is_equal(0.0)


# ---------------------------------------------------------------- the punch

func test_the_beam_punches_the_mouth_back_along_its_aim_and_it_springs_to_rest() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	var lb := _mouth(w)
	assert_bool(lb._fire()).is_true()
	var guard := 0
	while lb.beams == 0 and guard < 60:
		lb._tick(DT)
		guard += 1
	# the frame the beam leaves: kicked back along the aim by `back`, the lips climbed by `climb`, swollen by `pop`
	assert_float(lb.punch()).is_equal_approx(1.0, 0.0001)
	assert_int(lb.punches).is_equal(1)
	var off: Vector3 = lb._familiar.global_position - lb._fam_base
	assert_float(off.length()).is_equal_approx(lb.punch_value("back"), 0.01)
	assert_float(off.normalized().dot(lb._dir())).is_less(-0.99)
	assert_float(lb._model.rotation.x).is_equal_approx(deg_to_rad(32.0) + lb.punch_value("climb"), 0.01)
	assert_float(lb._model.scale.x).is_greater(lb._model_scale * 1.08)
	# the beam starts at the lips where they are now
	assert_float(lb.muzzle().distance_to(lb._familiar.global_position)).is_less(0.0001)
	# it springs past rest (forward of its place) within a quarter second
	var lowest := 1.0
	for k in range(15):
		lb._tick(DT)
		lowest = minf(lowest, lb.punch())
	assert_float(lowest).is_less(-0.1)
	# a pulse kicks again, smaller
	guard = 0
	while lb.punches < 2 and lb._beam_t > 0.0 and guard < 60:
		lb._tick(DT)
		guard += 1
	assert_int(lb.punches).is_equal(2)
	assert_float(lb.punch()).is_between(lb.punch_value("pulse") * 0.9, lb.punch_value("pulse") * 1.5)
	# after the beam: settled where it orbits, dark again
	_ticks(lb, lb.stat("duration", 2.0) + 0.8)
	assert_float(lb._beam_t).is_less_equal(0.0)
	assert_float(lb.punch()).is_equal(0.0)
	assert_float(lb._punch_t).is_equal(-1.0)
	assert_float(lb._familiar.global_position.distance_to(lb._fam_base)).is_less(0.0001)
	assert_float(lb.glow_level()).is_equal(0.0)
	assert_bool(lb._flare.visible).is_false()
	assert_bool(lb._glow_core.visible).is_false()
	assert_float(lb._cavity_mat.emission_energy_multiplier).is_equal(0.0)


func test_a_pull_while_the_beam_still_pours_pours_on_at_once() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	var lb := _mouth(w)
	assert_bool(lb._fire()).is_true()
	_ticks(lb, lb.windup_seconds() + 0.05)
	assert_int(lb.beams).is_equal(1)
	_ticks(lb, 0.5)
	var left := lb._beam_t
	assert_bool(lb._fire()).is_true()
	# no wind-up, a fresh beam and a fresh punch
	assert_float(lb._windup_t).is_equal(0.0)
	assert_int(lb.beams).is_equal(2)
	assert_float(lb._beam_t).is_greater(left)
	assert_float(lb.punch()).is_greater(0.99)


# ---------------------------------------------------------------- the glow's colour and facing

func test_the_throat_glows_the_beams_colour() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	for pair in [[[], Color(1.0, 0.25, 0.7)], [["mouth_burn"], Color(1.0, 0.45, 0.15)], [["mouth_knock"], Color(0.66, 1.0, 0.16)]]:
		var lb := _mouth(w, "big_mouth", pair[0])
		assert_bool(lb._fire()).is_true()
		_ticks(lb, lb.windup_seconds() + 0.1)
		assert_int(lb.beams).is_equal(1)
		var want: Color = pair[1]
		assert_bool(_near(lb._flare_mat.get_shader_parameter("color"), want)).override_failure_message(str(pair[0]) + ": the flare is not the beam's colour").is_true()
		assert_bool(_near(lb._cavity_mat.emission, want)).override_failure_message(str(pair[0]) + ": the throat is not the beam's colour").is_true()
		lb.queue_free()


func test_the_flare_fades_as_the_mouth_turns_its_back_on_the_camera() -> void:
	var w := _world()
	var lb := _mouth(w)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var fwd: Vector3 = -lb._model.global_transform.basis.z.normalized()
	cam.global_position = lb._model.global_position + fwd * 6.0
	assert_float(lb._flare_facing()).is_equal_approx(1.0, 0.0001)
	cam.global_position = lb._model.global_position - fwd * 6.0
	assert_float(lb._flare_facing()).is_equal_approx(0.0, 0.0001)
	cam.queue_free()


func test_a_mouth_model_without_a_throat_still_works() -> void:
	var w := _world()
	var lb := _mouth(w)
	var bare := Node3D.new()
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	bare.add_child(jaw)
	lb.add_child(bare)
	lb._model = bare
	lb._cavity_mat = null
	lb._setup_throat()
	assert_object(lb._glow_core).is_null()
	assert_object(lb._floor_mesh).is_null()
	assert_object(lb._flare.get_parent()).is_same(bare)
	lb._tick_glow(DT, 0.0, true, false)
	assert_float(lb.glow_level()).is_greater(0.4)
