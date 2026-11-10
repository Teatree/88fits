extends GdUnitTestSuite

## Pass 139, lane SWING (Garry: "The sword swings are constantly clipping through the ground. Either just give them a
## rendering prio or handle the surface topology in some way"): a swing's arc (MeleeFx.arc) lies on the plane fitted to
## the map's height under its crescent, raised by the most any sample stands above that plane, ARC_LIFT over it, and its
## shaders draw it GROUND_PULL metres nearer the camera (the depth test kept, so a creature in front still hides it).
## The thrust and the star keep no depth test. ground_follow off lays it flat at his feet as before.

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
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
"""

const DT := 1.0 / 60.0
const EPS := 0.002

var _aim_was := true
var _follow_was := true


func before_test() -> void:
	_aim_was = Settings.aim_mode
	_follow_was = MeleeFx.ground_follow
	Settings.aim_mode = true
	MeleeFx.ground_follow = true


func after_test() -> void:
	Settings.aim_mode = _aim_was
	MeleeFx.ground_follow = _follow_was


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A 40 m map whose height is f(x, z) at every metre (bilinear between: a plane is exact).
func _map(f: Callable) -> MapBase:
	var m: MapBase = auto_free(MapBase.new())
	m.size_m = 40.0
	m.resolution = 1.0
	m.grid_n = 41
	m.heights.resize(41 * 41)
	for iz in range(41):
		for ix in range(41):
			m.heights[iz * 41 + ix] = float(f.call(float(ix) - 20.0, float(iz) - 20.0))
	return m


func _world(m: MapBase = null) -> Dictionary:
	Run.start(Registry.character("ironwood"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	g.map = m
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
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _arc_live(fx: MeleeFx) -> Dictionary:
	for e: Dictionary in fx._arcs:
		if bool(e["live"]):
			return e
	return {}


## The height of an arc's quad (its plane) over world (x, z).
func _quad_h(e: Dictionary, x: float, z: float) -> float:
	var t: Transform3D = (e["mi"] as MeshInstance3D).global_transform
	var n := t.basis.y.normalized()
	return t.origin.y - (n.x * (x - t.origin.x) + n.z * (z - t.origin.z)) / n.y


## The points MeleeFx samples under an arc (its own rule, ground_fit), as world (x, z).
func _samples(at: Vector3, yaw: float, half_w: float, reach: float) -> Array:
	var out: Array = [Vector2(at.x, at.z)]
	var full := half_w >= PI - 0.01
	for r: float in MeleeFx.GROUND_RADII:
		for k in range(MeleeFx.GROUND_SPOKES):
			var u := float(k) / float(MeleeFx.GROUND_SPOKES) if full else float(k) / float(MeleeFx.GROUND_SPOKES - 1)
			var a := yaw + (TAU * u if full else half_w * (2.0 * u - 1.0))
			out.append(Vector2(at.x - sin(a) * reach * r, at.z - cos(a) * reach * r))
	return out


func _arc_on(w: Dictionary, m: MapBase, at: Vector2, yaw: float, half_w: float, reach: float, look: Dictionary = {}) -> Dictionary:
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(at.x, m.height_at(at.x, at.y), at.y)
	var fx := MeleeFx.new()
	(w["g"] as Node).add_child(fx)
	fx.map = m
	fx.arc(hero, yaw, half_w, reach, 0.16, 0.12, 1.0, look)
	var e := _arc_live(fx)
	assert_bool(e.is_empty()).is_false()
	return {"fx": fx, "e": e}


# ---------------------------------------------------------------- on a slope

func test_on_a_steady_slope_the_arc_tilts_to_it_and_stays_its_lift_above_it() -> void:
	var m := _map(func(x: float, z: float) -> float: return 0.45 * x + 0.15 * z)
	var w := _world(m)
	for style: String in MeleeFx.SLASH_STYLES:
		for yaw: float in [0.0, 1.2, PI, -2.0]:
			var r := _arc_on(w, m, Vector2(2.0, 3.0), yaw, 1.3, 3.2, {"style": style})
			var e: Dictionary = r["e"]
			var up := (e["mi"] as MeshInstance3D).global_transform.basis.y.normalized()
			var want := Vector3(-0.45, 1.0, -0.15).normalized()
			assert_float(up.dot(want)).override_failure_message("%s yaw %.1f: tilt %s" % [style, yaw, str(up)]).is_greater(0.999)
			# every point under the crescent: the quad lies ARC_LIFT over the ground (a plane: exact)
			for p: Vector2 in _samples(Vector3(2.0, 0.0, 3.0), yaw, 1.3, 3.2):
				assert_float(_quad_h(e, p.x, p.y) - m.height_at(p.x, p.y)).is_equal_approx(MeleeFx.ARC_LIFT, 0.01)
			(r["fx"] as Node).queue_free()


func test_on_a_crest_or_a_bank_no_sample_under_the_reach_stands_above_the_quad() -> void:
	var shapes := {
		"crest": func(x: float, z: float) -> float: return 1.5 - 0.05 * ((x - 1.0) * (x - 1.0) + z * z),
		"bank": func(x: float, z: float) -> float: return -2.0 * smoothstep(-3.0, 3.0, -x) + 0.1 * z,
		"dune": func(x: float, z: float) -> float: return 1.2 * sin(x * 0.35) * cos(z * 0.3),
	}
	for name: String in shapes.keys():
		var m := _map(shapes[name])
		var w := _world(m)
		for yaw: float in [0.0, 0.8, 2.4, -1.6]:
			for hw: float in [0.4, 1.3, PI]:
				var r := _arc_on(w, m, Vector2(0.5, -0.5), yaw, hw, 3.5)
				var e: Dictionary = r["e"]
				var hero: Node3D = w["hero"]
				for p: Vector2 in _samples(hero.global_position, yaw, minf(hw, PI), 3.5):
					var gap := _quad_h(e, p.x, p.y) - m.height_at(p.x, p.y)
					assert_float(gap).override_failure_message("%s yaw %.1f half %.1f at %s: %.3f" % [name, yaw, hw, str(p), gap]).is_greater_equal(MeleeFx.ARC_LIFT - EPS)
				# never under his feet
				assert_float(_quad_h(e, hero.global_position.x, hero.global_position.z)).is_greater_equal(hero.global_position.y + MeleeFx.ARC_LIFT - EPS)
				(r["fx"] as Node).queue_free()


func test_the_tilt_is_capped_and_a_flat_map_lays_it_flat() -> void:
	var steep := _map(func(x: float, _z: float) -> float: return 3.0 * x)
	var w := _world(steep)
	var r := _arc_on(w, steep, Vector2(0.0, 0.0), 0.0, 1.3, 3.0)
	var up := ((r["e"] as Dictionary)["mi"] as MeshInstance3D).global_transform.basis.y.normalized()
	assert_float(up.dot(Vector3(-MeleeFx.GROUND_SLOPE_MAX, 1.0, 0.0).normalized())).is_greater(0.999)
	var flat := _map(func(_x: float, _z: float) -> float: return 0.0)
	var w2 := _world(flat)
	var r2 := _arc_on(w2, flat, Vector2(1.0, 1.0), 0.7, 1.3, 3.0)
	var t: Transform3D = ((r2["e"] as Dictionary)["mi"] as MeshInstance3D).global_transform
	assert_float(t.basis.y.normalized().dot(Vector3.UP)).is_greater(0.9999)
	assert_float(t.origin.y).is_equal_approx(MeleeFx.ARC_LIFT, 0.001)
	# its size and turn as before: radius reach x ARC_PAD, its -Z the arc's centre
	assert_float(t.basis.x.length()).is_equal_approx(3.0 * MeleeFx.ARC_PAD, 0.001)
	var c := -t.basis.z.normalized()
	assert_float(Vector2(c.x, c.z).angle_to(Vector2(-sin(0.7), -cos(0.7)))).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------- riding with him

func test_it_refits_only_after_he_moved_and_rides_with_him_and_a_jump() -> void:
	var m := _map(func(x: float, z: float) -> float: return 0.3 * x - 0.2 * z)
	var w := _world(m)
	var r := _arc_on(w, m, Vector2(0.0, 0.0), 0.5, 1.3, 3.0)
	var fx: MeleeFx = r["fx"]
	var e: Dictionary = r["e"]
	var hero: Node3D = w["hero"]
	var n0 := fx.fits_made
	assert_int(n0).is_equal(1)
	hero.global_position = Vector3(0.1, m.height_at(0.1, 0.0), 0.0)
	fx.tick(DT)
	assert_int(fx.fits_made).is_equal(n0)
	var t: Transform3D = (e["mi"] as MeshInstance3D).global_transform
	assert_float(t.origin.x).is_equal_approx(0.1, 0.0001)
	# the old fit, carried along its own plane: still the lift over this plane
	assert_float(_quad_h(e, 1.0, 1.0) - m.height_at(1.0, 1.0)).is_equal_approx(MeleeFx.ARC_LIFT, 0.01)
	hero.global_position = Vector3(1.0, m.height_at(1.0, 0.5), 0.5)
	fx.tick(DT)
	assert_int(fx.fits_made).is_equal(n0 + 1)
	# in the air it goes up with him
	hero.global_position = Vector3(1.0, m.height_at(1.0, 0.5) + 2.0, 0.5)
	fx.tick(DT)
	t = (e["mi"] as MeshInstance3D).global_transform
	assert_float(t.origin.y).is_greater_equal(hero.global_position.y + MeleeFx.ARC_LIFT - EPS)


func test_ground_follow_off_lays_it_flat_at_his_feet_as_before() -> void:
	var m := _map(func(x: float, z: float) -> float: return 0.45 * x + 0.15 * z)
	var w := _world(m)
	MeleeFx.ground_follow = false
	var r := _arc_on(w, m, Vector2(2.0, 3.0), 0.0, 1.3, 3.0)
	var e: Dictionary = r["e"]
	var hero: Node3D = w["hero"]
	var t: Transform3D = (e["mi"] as MeshInstance3D).global_transform
	assert_float(t.basis.y.normalized().dot(Vector3.UP)).is_greater(0.9999)
	assert_float(t.origin.y).is_equal_approx(hero.global_position.y + MeleeFx.ARC_LIFT, 0.0001)
	assert_float(float((e["mat"] as ShaderMaterial).get_shader_parameter("pull"))).is_equal(0.0)
	assert_int((r["fx"] as MeleeFx).fits_made).is_equal(0)


# ---------------------------------------------------------------- the shaders

func test_the_arc_shaders_pull_it_nearer_with_their_depth_test_kept() -> void:
	var m := _map(func(_x: float, _z: float) -> float: return 0.0)
	var w := _world(m)
	for style: String in MeleeFx.SLASH_STYLES:
		var r := _arc_on(w, m, Vector2(0.0, 0.0), 0.0, 1.3, 3.0, {"style": style})
		var mat: ShaderMaterial = (r["e"] as Dictionary)["mat"]
		assert_float(float(mat.get_shader_parameter("pull"))).is_equal(MeleeFx.GROUND_PULL)
		(r["fx"] as Node).queue_free()
	for p: String in ["res://core/shaders/melee_slash.gdshader", "res://core/shaders/melee_arc.gdshader"]:
		var code: String = (load(p) as Shader).code
		assert_bool(code.contains("uniform float pull")).override_failure_message(p).is_true()
		assert_bool(code.contains("skip_vertex_transform")).override_failure_message(p).is_true()
		# a creature or a prop in front still hides it
		assert_bool(code.contains("depth_test_disabled")).override_failure_message(p).is_false()
	# the thrust, the lance and the star never depth-tested (pass 137): they cannot sink
	for p: String in ["res://core/shaders/melee_lance.gdshader", "res://core/shaders/melee_thrust.gdshader", "res://core/shaders/melee_flash.gdshader"]:
		assert_bool((load(p) as Shader).code.contains("depth_test_disabled")).override_failure_message(p).is_true()


func test_the_sabre_and_the_whirlwind_lay_their_arcs_on_the_games_map() -> void:
	var m := _map(func(x: float, z: float) -> float: return -0.4 * x + 0.2 * z)
	var w := _world(m)
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(1.0, m.height_at(1.0, 2.0), 2.0)
	for id: String in ["sabre", "whirlwind"]:
		var inst := WeaponInstance.new(Registry.weapon(id), 1)
		inst.rebuild(Run.player_sheet, [inst])
		var b := Thruster.new()
		(w["g"] as Node).add_child(b)
		b.setup(inst, w["g"])
		b._fire()
		for k in range(int(0.3 / DT)):
			b._tick(DT)
			if b.effects() and b.effects().arcs_live() > 0:
				break
		var fx := b.effects()
		assert_object(fx).override_failure_message(id).is_not_null()
		var e := _arc_live(fx)
		assert_bool(e.is_empty()).override_failure_message(id + ": no arc").is_false()
		var up := (e["mi"] as MeshInstance3D).global_transform.basis.y.normalized()
		assert_float(up.dot(Vector3(0.4, 1.0, -0.2).normalized())).override_failure_message(id).is_greater(0.999)
		assert_int(fx.fits_made).is_greater(0)
		b.queue_free()
