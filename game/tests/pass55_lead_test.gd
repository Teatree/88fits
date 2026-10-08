extends GdUnitTestSuite

## Pass 55 (Garry's Solenne list), the lead's part: the tumbleweeds roll like wheels the way they fly (they had spun
## about their flight like drills), the signs point without names (pass54_world_test), and Solenne's four walks are art
## variants in her JSON (SOL-A is pass 54's; B, C and D are walked on drivers fitted to her painting, tools/pose_fit.py).

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
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_lightning(_points) -> void:
	pass
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
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
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


func _shot(w: Dictionary, id: String, v := Vector3(8, 0, 0)) -> int:
	var pm: ProjectileManager = w["pm"]
	var inst := WeaponInstance.new(Registry.weapon(id), 1)
	var k := pm.register_kind(SphereMesh.new(), null)
	return pm.fire(k, Vector3(0, 0.6, 0), v, 5.0, 99, 0.5, 3.0, inst)


func test_the_tumbleweeds_carry_a_rolling_radius() -> void:
	assert_float(float(Registry.weapon("tumbleweed").params.get("roll_radius", 0.0))).is_equal_approx(0.6, 0.001)
	assert_float(float(Registry.weapon("dust_devil").params.get("roll_radius", 0.0))).is_equal_approx(0.75, 0.001)


func test_a_tumbleweed_rolls_like_a_wheel_the_way_it_flies() -> void:
	# Garry (pass 55): "Tumbleweed projectile seems to be spinning in the wrong direction when moving, should be in the
	# direction that it's moving in"
	for v: Vector3 in [Vector3(8, 0, 0), Vector3(0, 0, -6), Vector3(-5, 0, 5)]:
		var w := _world()
		var pm: ProjectileManager = w["pm"]
		var i := _shot(w, "tumbleweed", v)
		assert_bool(pm.extra[i].has("roll")).is_true()
		var s0: float = pm.spin[i]
		for n in 10:
			pm._physics_process(DT)
		var fwd := pm.vel[i].normalized()
		# v / r a second
		var want := pm.vel[i].length() / (0.6 * pm.psize[i]) * 10.0 * DT
		assert_float(pm.spin[i] - s0).is_equal_approx(want, want * 0.05)
		# it turns about the axis across its flight (level, square to it), not about the flight itself
		var b := pm.draw_basis(i).orthonormalized()
		assert_float(absf(b.x.dot(fwd))).override_failure_message(str(v)).is_less(0.01)
		assert_float(absf(b.x.y)).is_less(0.01)
		# and its top goes the way it flies
		pm.spin[i] = 0.0
		var up0 := pm.draw_basis(i).orthonormalized().y
		pm.spin[i] = 0.1
		var up1 := pm.draw_basis(i).orthonormalized().y
		assert_float((up1 - up0).dot(fwd)).override_failure_message(str(v)).is_greater(0.0)


func test_the_dust_devil_rolls_too_and_a_pea_still_tumbles_on_its_flight() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var i := _shot(w, "dust_devil")
	assert_bool(pm.extra[i].has("roll")).is_true()
	var j := _shot(w, "peashooter")
	assert_bool(pm.extra[j].has("roll")).is_false()
	pm._physics_process(DT)
	# a shot without a rolling radius spins about its flight: its look axis stays on the flight
	var b := pm.draw_basis(j).orthonormalized()
	assert_float(absf(b.z.dot(pm.vel[j].normalized()))).is_greater(0.99)


func test_solenne_carries_her_five_walks_as_art_variants() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/solenne/solenne.json"))
	assert_str(str(d.get("variant_base"))).is_equal("SOL-A")
	var v: Dictionary = d.get("variants", {})
	# pass 60: SOL-E, the catwalk again with a tighter prompt and its own seeds
	for code in ["SOL-A", "SOL-B", "SOL-C", "SOL-D", "SOL-E"]:
		assert_bool(v.has(code)).override_failure_message(code).is_true()
		assert_str(str((v[code] as Dictionary).get("note", ""))).is_not_empty()
	assert_str(str(v["SOL-A"]["sprite"])).is_equal("solenne_sprite.png")
	# B to E walk on drivers fitted to her painting, with the side still whose sun disc faces the viewer
	for code in ["SOL-B", "SOL-C", "SOL-D", "SOL-E"]:
		var r: Dictionary = v[code].get("recipe", {})
		var drv: Dictionary = r.get("pose_drivers", {})
		for view in ["back", "bd", "side", "fd", "front"]:
			assert_str(str(drv.get(view, ""))).contains("_fit")
		assert_str(str(drv["back"])).ends_with("_spread")
		assert_str(str((r.get("still_keys", {}) as Dictionary).get("side", ""))).is_equal("solenne_s55_side")
	# every strip a variant names is in the folder
	for code in v.keys():
		var sp := str((v[code] as Dictionary).get("sprite", ""))
		if sp != "":
			assert_bool(FileAccess.file_exists("res://content/characters/solenne/" + sp)).override_failure_message(code + " " + sp).is_true()
