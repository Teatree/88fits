extends GdUnitTestSuite

## Pass 88, lane MOUTH (Garry: "The 'Punch' from the laser should happen only once, when the laser shooting starts";
## "The tongue is still there actually. I mean the meaty part behind the mouth ... `Cavity`, `Glow` and `ThroatBack`.
## Make it so these are all hidden, and when the attack is happening there is a mesh that appears that is as big as all
## of those together, and glows bright white as it used to"; "When spinning in an idle fashion is seems to stutter at a
## specific point on the bottom left ... the mouth is always facing the camera when it's spinning in the game ... make
## sure that it's happening like that in the Main Menu"). One punch a beam; the throat is one white Glow, hidden at rest;
## the title's mouth faces the camera tipped back as in play, with no kick and no turn as it circles.

const Stage := preload("res://ui/TitleStage.gd")

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

const DT := 1.0 / 60.0

var _keep_style := ""
var _keep_last := ""


func before_test() -> void:
	_keep_style = Settings.menu_style
	_keep_last = str(Save.data.get("last_character", "astro"))


func after_test() -> void:
	Stage.forget()
	Settings.menu_style = _keep_style
	Save.data["last_character"] = _keep_last


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


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
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 2000.0)
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


# ---------------------------------------------------------------- the model

func test_the_glow_is_one_mesh_as_big_as_the_old_throat_and_the_old_parts_are_gone() -> void:
	for path in ["res://content/weapons/big_mouth/big_mouth_visual.tscn", "res://content/evolutions/loudmouth/loudmouth_visual.tscn"]:
		var n: Node = (load(path) as PackedScene).instantiate()
		var mouth: Node3D = n.get_node("Familiar/Mouth")
		for part in ["Cavity", "ThroatBack", "Flare", "Tongue"]:
			assert_object(mouth.find_child(part, true, false)).override_failure_message(path + ": " + part).is_null()
		var glow := mouth.find_child("Glow", true, false) as MeshInstance3D
		assert_object(glow).is_not_null()
		# on the mouth itself (it stays while the jaw drops), as wide as the bowl was (0.8 m) and as deep (0.29 m to
		# its rim) and tall (0.28 m), behind the lips
		assert_str(str(glow.get_parent().name)).is_equal("Mouth")
		assert_bool(mouth.find_child("Jaw", true, false).is_ancestor_of(glow)).is_false()
		var box: AABB = glow.transform * glow.mesh.get_aabb()
		assert_float(box.size.x).is_between(0.75, 0.85)
		assert_float(box.size.y).is_between(0.25, 0.32)
		assert_float(box.size.z).is_between(0.25, 0.32)
		assert_float(box.position.z).is_greater(0.05)
		n.free()


# ---------------------------------------------------------------- the glow

func test_the_glow_is_hidden_at_rest_white_while_it_pours_and_hidden_again_once_shut() -> void:
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	var lb := _mouth(w)
	_ticks(lb, 0.5)
	assert_bool(lb._glow_core.visible).is_false()
	# the floor of the mouth hides with it at rest (from behind it read as the meaty part)
	assert_bool(lb._floor_mesh.visible).is_false()
	assert_bool(lb._floor_back.visible).is_false()
	assert_bool(lb._fire()).is_true()
	# lit from the wind-up's first frames
	_ticks(lb, 0.05)
	assert_bool(lb._glow_core.visible).is_true()
	assert_float(lb.glow_level()).is_greater(0.45)
	_ticks(lb, lb.windup_seconds() + 0.2)
	assert_int(lb.beams).is_equal(1)
	assert_bool(lb._floor_mesh.visible).is_true()
	assert_bool(lb._floor_back.visible).is_true()
	var c: Color = lb._glow_core_mat.get_shader_parameter("color")
	assert_float(minf(c.r, minf(c.g, c.b))).is_greater(0.85)
	assert_float(float(lb._glow_core_mat.get_shader_parameter("rim"))).is_equal_approx(lb.throat_value("rim"), 0.0001)
	# the beam ends: it dies to the dark while the jaw shuts, then hides
	lb.cooldown_left = 99.0
	_ticks(lb, lb._beam_t + DT)
	_ticks(lb, 1.0)
	assert_bool(lb._glow_core.visible).is_false()
	assert_bool(lb._floor_mesh.visible).is_false()
	assert_float(lb._open).is_less(LaserBeam.GLOW_SHUT_OPEN)
	# out, with the jaw still open: shown in the throat's dark, so the closing mouth never shows the sand
	lb._open = 0.5
	lb._tick_glow(DT, 0.0, false, false)
	assert_bool(lb._glow_core.visible).is_true()
	var d: Color = lb._glow_core_mat.get_shader_parameter("color")
	assert_bool(d.is_equal_approx(LaserBeam.GLOW_DARK)).is_true()
	assert_float(float(lb._glow_core_mat.get_shader_parameter("rim"))).is_equal(0.0)


func test_a_glow_never_shows_through_the_chew_at_rest() -> void:
	# the chew opens the jaw CHEW_DEG at most: under the share the glow waits for
	assert_float(LaserBeam.CHEW_DEG / LaserBeam.JAW_OPEN_DEG).is_less(LaserBeam.GLOW_SHUT_OPEN)
	for k in range(40):
		assert_float(-LaserBeam.chew_angle(float(k) * 0.1)).is_between(0.0, deg_to_rad(LaserBeam.CHEW_DEG) + 0.0001)


# ---------------------------------------------------------------- the punch

func test_the_punch_comes_once_as_the_beam_starts() -> void:
	for id in ["big_mouth", "loudmouth"]:
		assert_float(float(Registry.weapon(id).params["beam"]["punch"]["pulse"])).override_failure_message(id).is_equal(0.0)
	assert_float(float(LaserBeam.PUNCH_DEFAULTS["pulse"])).is_equal(0.0)
	var w := _world()
	_creature(w["em"], Vector3(4, 0, 0))
	var lb := _mouth(w)
	lb.cooldown_left = 0.0
	assert_bool(lb._fire()).is_true()
	_ticks(lb, lb.windup_seconds() + DT * 2.0)
	assert_int(lb.beams).is_equal(1)
	assert_int(lb.punches).is_equal(1)
	# through the whole beam (its pulses puff and ring) no more kicks; the mouth settles while it still pours
	var settled_at := -1.0
	var t := 0.0
	while lb._beam_t > 0.0:
		lb._tick(DT)
		t += DT
		if settled_at < 0.0 and lb._punch_t < 0.0:
			settled_at = t
	assert_int(lb.punches).is_equal(1)
	assert_float(settled_at).is_between(0.0, 0.8)
	# a pull while it pours re-aims it: a fresh beam, no fresh punch
	assert_bool(lb._fire()).is_true()
	_ticks(lb, lb.windup_seconds() + 0.1)
	var p0 := lb.punches
	_ticks(lb, 0.3)
	assert_bool(lb._fire()).is_true()
	assert_int(lb.punches).is_equal(p0)
	# the next beam from a shut mouth punches again
	_ticks(lb, lb._beam_t + 1.0)
	assert_bool(lb._fire()).is_true()
	_ticks(lb, lb.windup_seconds() + DT * 2.0)
	assert_int(lb.punches).is_equal(p0 + 1)


# ---------------------------------------------------------------- the title

func _title() -> Control:
	Settings.menu_style = "live"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


func test_the_title_mouth_faces_the_camera_tipped_back_with_its_glow_hidden_and_turns_smoothly() -> void:
	var t := await _title()
	var stage = t._stage
	stage.show_hero(Registry.character("may"), false, 0)
	var h = stage.hero
	assert_str(h.kind).is_equal("LaserBeam")
	var mouth: Node3D = h._mouth
	assert_object(mouth).is_not_null()
	for part in ["Glow", "Floor", "FloorBack"]:
		assert_bool((mouth.find_child(part, true, false) as Node3D).visible).override_failure_message(part).is_false()
	var cam: Camera3D = stage.camera
	var back := cam.global_transform.basis.z
	back = Vector3(back.x, 0.0, back.z).normalized()
	var last := Vector3.INF
	var last_rot := Vector3.INF
	var steps: Array = []
	# a whole circle and a bit, frame by frame
	var frames := int(ceil(TAU / LaserBeam.ORBIT_DEFAULTS["speed"] / DT)) + 30
	for k in range(frames):
		h._fly(DT)
		var fwd := -mouth.global_transform.basis.z.normalized()
		var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		# facing the camera all the way round, lips tipped up by the run's pitch
		assert_float(flat.dot(back)).override_failure_message("frame %d: not facing the camera" % k).is_greater(0.999)
		assert_float(mouth.rotation.x).is_equal_approx(deg_to_rad(LaserBeam.REST_PITCH_DEG), 0.0001)
		assert_float(h.familiar.rotation.length()).is_equal(0.0)
		if last_rot != Vector3.INF:
			assert_float(absf(mouth.rotation.y - last_rot.y)).is_less(0.0001)
		last_rot = mouth.rotation
		if last != Vector3.INF:
			steps.append(h.fam_pos.distance_to(last))
		last = h.fam_pos
	# the circle runs at an even pace: no step more than half again the mean (a kick or a jump would be)
	var total := 0.0
	var most := 0.0
	for s: float in steps:
		total += s
		most = maxf(most, s)
	var mean := total / float(steps.size())
	assert_float(most).is_less(mean * 1.5)
	# the jaw chews as in play
	assert_float(h._mouth_jaw.rotation.x).is_between(-deg_to_rad(LaserBeam.CHEW_DEG) - 0.0001, 0.0001)
