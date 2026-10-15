## Pass 80 (lane TRAIL): the tracers' looks. Garry: "The revolver trail looks awful, I don't like it at all. Search the
## internet for a better option than this, I want a clear visible trail, but one that doesn't look this bad." Every tracer
## weapon draws one of five styles (`tracer_style`; ProjectileManager.TRACER_STYLE without one): streak, ribbon, wisp,
## toon and pass 79's line; each with its own life, width and hot part unless the weapon says otherwise; the style rides
## in each segment of the one MultiMesh ring (basis z: start birth, style, hot). The research and the pictures:
## tools/dl/p80/TRAIL/.
extends GdUnitTestSuite


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
func fx_poison(_a) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
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
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h: bool = true) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
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
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0
## every weapon and evolution that draws a tracer in play
const TRACER_WEAPONS := ["revolver", "tommy_gun", "chicago_typewriter", "boomstick", "blunderbuss", "turret_buddy", "golden_revolver"]


func before_test() -> void:
	Save.begin_sandbox()
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()
	Save.end_sandbox()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


func _kind(pm: ProjectileManager) -> int:
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	return pm.register_kind(q, StandardMaterial3D.new(), 1.0)


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


## Weapon `id` with its params laid over (a copy of its def: the Registry's stays as it is).
func _inst_with(id: String, over: Dictionary) -> WeaponInstance:
	var d: WeaponDef = Registry.weapon(id).duplicate(true)
	d.params = (Registry.weapon(id).params as Dictionary).duplicate(true)
	for k: String in over:
		d.params[k] = over[k]
	var inst := WeaponInstance.new(d, 1)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


# ---------------------------------------------------------------- the table

func test_the_styles_table_is_whole() -> void:
	var ids: Dictionary = ProjectileManager.TRACER_STYLE_IDS
	assert_bool(ids.has(ProjectileManager.TRACER_STYLE)).is_true()
	for want: String in ["line", "streak", "ribbon", "wisp", "toon"]:
		assert_bool(ids.has(want)).override_failure_message(want).is_true()
	var n := ids.size()
	assert_int(ProjectileManager.TRACER_STYLE_LIFE.size()).is_equal(n)
	assert_int(ProjectileManager.TRACER_STYLE_WIDTH.size()).is_equal(n)
	assert_int(ProjectileManager.TRACER_STYLE_HOT.size()).is_equal(n)
	# ids are 0..n-1, the line pass 79's (its life TRAIL_LIFE, its width TRACER_WIDTH)
	var seen := {}
	for k: String in ids:
		seen[int(ids[k])] = true
	assert_int(seen.size()).is_equal(n)
	for i in range(n):
		assert_bool(seen.has(i)).is_true()
	assert_int(int(ids["line"])).is_equal(0)
	assert_float(ProjectileManager.TRACER_STYLE_LIFE[0]).is_equal_approx(ProjectileManager.TRAIL_LIFE, 0.0001)
	assert_float(ProjectileManager.TRACER_STYLE_WIDTH[0]).is_equal_approx(ProjectileManager.TRACER_WIDTH, 0.0001)
	# the new looks are short (the old line lived 0.9-1.4 s) and readable (wider than the old 4.5 cm hairline)
	for k: String in ["streak", "ribbon", "wisp", "toon"]:
		var i := int(ids[k])
		assert_float(ProjectileManager.TRACER_STYLE_LIFE[i]).override_failure_message(k).is_less_equal(0.6)
		assert_float(ProjectileManager.TRACER_STYLE_WIDTH[i]).override_failure_message(k).is_greater(0.08)
		assert_float(ProjectileManager.TRACER_STYLE_HOT[i]).override_failure_message(k).is_between(0.02, 1.0)


func test_a_weapon_picks_its_style_and_an_unknown_name_falls_back() -> void:
	var default_id := int(ProjectileManager.TRACER_STYLE_IDS[ProjectileManager.TRACER_STYLE])
	assert_int(ProjectileManager.tracer_style_id(null)).is_equal(default_id)
	for k: String in ProjectileManager.TRACER_STYLE_IDS:
		var w := _inst_with("tommy_gun", {"tracer_style": k})
		assert_int(ProjectileManager.tracer_style_id(w)).override_failure_message(k).is_equal(int(ProjectileManager.TRACER_STYLE_IDS[k]))
	assert_int(ProjectileManager.tracer_style_id(_inst_with("tommy_gun", {"tracer_style": "sparkles"}))).is_equal(default_id)
	# a style's own life, width and hot unless the weapon sets them
	var bare := _inst_with("tommy_gun", {"tracer_style": "ribbon"})
	bare.params.erase("tracer_life")
	bare.params.erase("tracer_width")
	bare.params.erase("tracer_hot")
	var ri := int(ProjectileManager.TRACER_STYLE_IDS["ribbon"])
	assert_float(ProjectileManager.tracer_life_of(bare)).is_equal_approx(ProjectileManager.TRACER_STYLE_LIFE[ri], 0.0001)
	assert_float(ProjectileManager.tracer_width_of(bare)).is_equal_approx(ProjectileManager.TRACER_STYLE_WIDTH[ri], 0.0001)
	assert_float(ProjectileManager.tracer_hot_of(bare)).is_equal_approx(ProjectileManager.TRACER_STYLE_HOT[ri], 0.0001)
	var own := _inst_with("tommy_gun", {"tracer_style": "ribbon", "tracer_life": 0.5, "tracer_width": 0.3, "tracer_hot": 7.0})
	assert_float(ProjectileManager.tracer_life_of(own)).is_equal_approx(0.5, 0.0001)
	assert_float(ProjectileManager.tracer_width_of(own)).is_equal_approx(0.3, 0.0001)
	assert_float(ProjectileManager.tracer_hot_of(own)).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- the segments

func test_a_segment_carries_its_style_and_hot_to_the_shader() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var wisp := int(ProjectileManager.TRACER_STYLE_IDS["wisp"])
	pm.tracer_segment(Vector3(0, 1, 0), Vector3(0, 1, -1), Color.RED, 0.15, 0.4, 0.0, null, -1.0, wisp, 0.25)
	var k := pm.tracer_segments - 1
	assert_int(pm.tracer_kind[k]).is_equal(wisp)
	assert_float(pm.tracer_hot[k]).is_equal_approx(0.25, 0.0001)
	# the transform the shader reads (the headless renderer keeps none to read back): basis z = (the start's birth, the
	# style, hot) = MODEL_MATRIX[2], basis y = (the end's birth, life, width) = MODEL_MATRIX[1]
	var t := ProjectileManager.tracer_xform(Vector3(0, 1, 0), Vector3(0, 1, -1), 0.15, 0.4, 2.0, 2.1, wisp, 0.25)
	assert_float(t.basis.z.y).is_equal_approx(float(wisp), 0.0001)
	assert_float(t.basis.z.z).is_equal_approx(0.25, 0.0001)
	assert_float(t.basis.z.x).is_equal_approx(2.0, 0.0001)
	assert_float(t.basis.y.x).is_equal_approx(2.1, 0.0001)
	assert_float(t.basis.y.y).is_equal_approx(0.4, 0.0001)
	assert_float(t.basis.y.z).is_equal_approx(0.15, 0.0001)
	assert_bool(t.basis.x.is_equal_approx(Vector3(0, 0, -1))).is_true()
	assert_bool(t.origin.is_equal_approx(Vector3(0, 1, 0))).is_true()
	# no style given: the default's, with its hot
	pm.tracer_segment(Vector3(0, 1, 0), Vector3(0, 1, -1), Color.RED, 0.15, 0.4)
	var d := int(ProjectileManager.TRACER_STYLE_IDS[ProjectileManager.TRACER_STYLE])
	assert_int(pm.tracer_kind[pm.tracer_segments - 1]).is_equal(d)
	assert_float(pm.tracer_hot[pm.tracer_segments - 1]).is_equal_approx(ProjectileManager.TRACER_STYLE_HOT[d], 0.0001)


func test_the_revolver_draws_the_default_style_in_a_readable_red() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("revolver")
	assert_int(ProjectileManager.tracer_style_id(inst)).is_equal(int(ProjectileManager.TRACER_STYLE_IDS[ProjectileManager.TRACER_STYLE]))
	var j := pm.fire(_kind(pm), Vector3(0, 0.8, -3), Vector3(0, 0, -33), 3.0, 0, 0.14, 0.6, inst, 0.0)
	assert_int(j).is_greater_equal(0)
	for k in range(10):
		pm._physics_process(DT)
	var n := pm.tracer_segments
	assert_int(n).is_greater_equal(6)
	var c: Color = pm.tracer_col[n - 1]
	# red, a little see-through, and not the old near-black hairline: lighter than it and wider
	assert_float(c.r).is_greater(c.g * 3.0)
	assert_float(c.r).is_greater(0.7)
	assert_float(c.a).is_between(0.5, 1.0)
	assert_float(pm.tracer_width[n - 1]).is_greater(0.12)
	assert_float(pm.tracer_life[n - 1]).is_less_equal(0.6)
	assert_int(pm.tracer_kind[n - 1]).is_equal(ProjectileManager.tracer_style_id(inst))
	pm._free(j)


func test_silver_bullet_is_thicker_in_its_silver_blue() -> void:
	var pm: ProjectileManager = auto_free(ProjectileManager.new())
	var plain := _inst("revolver")
	var silver := _inst("revolver", ["silver_bullet"])
	assert_float(ProjectileManager.tracer_width_of(silver)).is_greater(ProjectileManager.tracer_width_of(plain) * 1.3)
	var c := pm._tracer_colour(silver)
	assert_float(c.b).is_greater(c.r)
	assert_float(c.get_luminance()).is_greater(0.6)
	assert_int(ProjectileManager.tracer_style_id(silver)).is_equal(ProjectileManager.tracer_style_id(plain))
	var gold := _inst("golden_revolver")
	assert_float(ProjectileManager.tracer_width_of(gold)).is_equal_approx(ProjectileManager.tracer_width_of(silver), 0.0001)


func test_every_tracer_weapon_draws_the_new_look() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var kd := _kind(pm)
	for id: String in TRACER_WEAPONS:
		var inst := _inst(id)
		assert_bool(bool(inst.params.get("tracer", false))).override_failure_message(id).is_true()
		# none is left on pass 79's line, and none lingers like it did
		assert_int(ProjectileManager.tracer_style_id(inst)).override_failure_message(id).is_not_equal(0)
		assert_float(ProjectileManager.tracer_life_of(inst)).override_failure_message(id).is_less_equal(0.6)
		var n0 := pm.tracer_segments
		var j := pm.fire(kd, Vector3(3, 0.8, 0), Vector3(25, 0, 0), 1.0, 0, 0.1, 0.5, inst, 0.0)
		for k in range(4):
			pm._physics_process(DT)
		pm._free(j)
		assert_int(pm.tracer_segments).override_failure_message(id).is_greater(n0)
		var last := pm.tracer_segments - 1
		assert_int(pm.tracer_kind[last]).override_failure_message(id).is_equal(ProjectileManager.tracer_style_id(inst))
		assert_float(pm.tracer_hot[last]).override_failure_message(id).is_equal_approx(ProjectileManager.tracer_hot_of(inst), 0.0001)
		assert_float(pm.tracer_life[last]).override_failure_message(id).is_equal_approx(ProjectileManager.tracer_life_of(inst), 0.0001)
		assert_float(pm.tracer_width[last]).override_failure_message(id).is_equal_approx(ProjectileManager.tracer_width_of(inst), 0.0001)


func test_a_mutation_can_switch_the_style() -> void:
	# a mutation's params lay over its weapon's, so a style set on one wins (how Garry tries a look on one path)
	var w := _inst_with("revolver", {})
	var md: MutationDef = Registry.mutation("silver_bullet").duplicate(true)
	md.params = (Registry.mutation("silver_bullet").params as Dictionary).duplicate(true)
	md.params["tracer_style"] = "toon"
	w.mutations.append(md)
	w.rebuild(Run.player_sheet, [w])
	assert_int(ProjectileManager.tracer_style_id(w)).is_equal(int(ProjectileManager.TRACER_STYLE_IDS["toon"]))


# ---------------------------------------------------------------- the shader

func test_the_shader_draws_every_style_on_the_compatibility_renderer() -> void:
	var code: String = ProjectileManager.TRACER_SHADER.code
	# the line's knobs stay (pass 79)
	for want: String in ["now", "widen", "rise", "fade_pow", "min_px"]:
		assert_bool(code.contains("uniform float " + want)).override_failure_message("no uniform " + want).is_true()
	# alpha blending: additive washes out on the light sand
	assert_bool(code.contains("blend_mix")).is_true()
	assert_bool(code.contains("blend_add")).is_false()
	# a flat varying drew nothing at all on the Compatibility renderer; a render target's projection has y flipped
	assert_bool(code.contains("varying flat")).is_false()
	assert_bool(code.contains("abs(PROJECTION_MATRIX[1][1])")).is_true()
	# the style and hot come from the segment's basis z
	assert_bool(code.contains("MODEL_MATRIX[2]")).is_true()
	var s: Shader = ProjectileManager.TRACER_SHADER
	assert_int(s.get_shader_uniform_list().size()).is_greater_equal(8)


func test_the_warm_up_lays_one_segment_of_the_default_style() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	pm.warm_draw(Vector3(0, -8, 0))
	assert_int(pm._ln_mm.visible_instance_count).is_greater_equal(1)
	assert_int(pm.tracer_kind[pm.tracer_segments - 1]).is_equal(int(ProjectileManager.TRACER_STYLE_IDS[ProjectileManager.TRACER_STYLE]))
	pm.warm_draw(Vector3.INF)
