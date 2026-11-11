extends GdUnitTestSuite

## Pass 138, lane MELEE: the Sabre's swing and the Spear's thrust in styles (`params.fx_style`, MeleeFx.style_of): the
## swing a bold crescent by default ("cel" and pass 136's "classic" by the key), the thrust a lance of light by default
## ("wind" and pass 137's "spearhead" by the key). Each reveals and ends in its time, the hit's moment unchanged, the
## pools capped whatever the mix.

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

var _aim_was := true
var _ff_was := false


func before_test() -> void:
	_aim_was = Settings.aim_mode
	_ff_was = Settings.fire_forward
	Settings.aim_mode = true


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Settings.fire_forward = _ff_was


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
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	return i


func _thruster(w: Dictionary, id: String, muts: Array = [], level := 1) -> Thruster:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	var b := Thruster.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## Ticks the stroke through (`secs` seconds).
func _run_for(b: Thruster, secs: float) -> void:
	var n := int(secs / DT)
	for k in range(n):
		b._tick(DT)


func _any_blade_shown(b: Thruster) -> bool:
	for bl: Node3D in b._blades:
		if bl.visible:
			return true
	return false


## The angle (degrees) between flat directions.
func _deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))))



func _entry_of(fx: MeleeFx, k := 0) -> Dictionary:
	var live: Array = fx._thrusts.filter(func(e: Dictionary) -> bool: return bool(e["live"]))
	return live[k] if k < live.size() else {}


# ---------------------------------------------------------------- the style key

func test_the_style_key_and_its_defaults() -> void:
	assert_str(MeleeFx.style_of("slash", "")).is_equal("crescent")
	assert_str(MeleeFx.style_of("slash", "cel")).is_equal("cel")
	assert_str(MeleeFx.style_of("slash", "classic")).is_equal("classic")
	assert_str(MeleeFx.style_of("slash", "lance")).is_equal("crescent")
	# pass 141: the default thrust is the pack's burst (pass141_melee_test)
	assert_str(MeleeFx.style_of("stab", "")).is_equal("burst")
	assert_str(MeleeFx.style_of("stab", "wind")).is_equal("wind")
	assert_str(MeleeFx.style_of("stab", "spearhead")).is_equal("spearhead")
	assert_str(MeleeFx.style_of("stab", "cel")).is_equal("burst")
	var w := _world()
	var sb := _thruster(w, "sabre")
	assert_str(str(sb._fx_arc_look()["style"])).is_equal(MeleeFx.style_of("slash", str(sb.inst.params.get("fx_style", ""))))
	var pk := _thruster(w, "pike")
	assert_str(str(pk._fx_thrust_look()["style"])).is_equal(MeleeFx.style_of("stab", str(pk.inst.params.get("fx_style", ""))))
	# a stab weapon's sweep draws a swing's style
	assert_bool(MeleeFx.SLASH_STYLES.has(str(pk._fx_arc_look()["style"]))).is_true()
	# every melee weapon's JSON names a style its stroke knows
	for id: String in ["sabre", "whirlwind", "pike", "thunder_lance"]:
		var wd: WeaponDef = Registry.weapon(id)
		assert_object(wd).is_not_null()
		var st := str(wd.params.get("fx_style", ""))
		var look := str((wd.params.get("aim", {}) as Dictionary).get("look", ""))
		var list: Array = MeleeFx.SLASH_STYLES if look == "slash" else MeleeFx.STAB_STYLES
		assert_bool(list.has(st)).override_failure_message("%s fx_style %s" % [id, st]).is_true()


# ---------------------------------------------------------------- the swing

func _arc_live(fx: MeleeFx) -> Dictionary:
	for e: Dictionary in fx._arcs:
		if bool(e["live"]):
			return e
	return {}


func test_a_swing_reveals_over_its_sweep_and_dissolves_in_its_time() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	for st: String in MeleeFx.SLASH_STYLES:
		var fx := MeleeFx.new()
		(w["g"] as Node).add_child(fx)
		fx.arc(hero, 0.0, 1.3, 3.0, 0.16, 0.12, 1.0, {"style": st})
		var e := _arc_live(fx)
		assert_bool(e.is_empty()).is_false()
		var m: ShaderMaterial = e["mat"]
		var path := m.shader.resource_path
		if st == "classic":
			assert_str(path).ends_with("melee_arc.gdshader")
		elif st == "moon" or st == "cyclic":
			# pass 141: the pack's painted crescent and the cyclic slash share their own shader
			assert_str(path).ends_with("melee_swing_fx.gdshader")
		else:
			assert_str(path).ends_with("melee_slash.gdshader")
			assert_int(int(m.get_shader_parameter("style"))).is_equal(2 if st == "cel" else 1)
		assert_str(str(fx.last_arc["style"])).is_equal(st)
		# the head runs 0 -> 1 over the sweep
		assert_float(float(m.get_shader_parameter("head"))).is_less(0.05)
		var t := 0.0
		while t < 0.16 - DT * 0.5:
			fx.tick(DT)
			t += DT
		assert_float(float(m.get_shader_parameter("head"))).is_greater(0.97)
		assert_bool(bool(e["live"])).is_true()
		# gone by the end of its fade (the new styles at least SLASH_FADE), not before half of it
		var fade := MeleeFx.SLASH_FADE if st != "classic" else 0.12
		var gone_at := -1.0
		for k in range(int(0.6 / DT)):
			fx.tick(DT)
			t += DT
			if not bool(e["live"]) and gone_at < 0.0:
				gone_at = t
		assert_float(gone_at).is_greater(0.16 + fade * 0.5)
		assert_float(gone_at).is_less_equal(0.16 + fade + DT * 2.0)
		assert_int(fx.arcs_live()).is_equal(0)
		fx.queue_free()


func test_the_sabre_draws_its_style_and_the_whirlwind_its_ring() -> void:
	var w := _world()
	var sb := _thruster(w, "sabre")
	sb._fire()
	_run_for(sb, 0.3)
	assert_int(sb.effects().arcs_made).is_greater(0)
	assert_str(str(sb.effects().last_arc["style"])).is_equal(sb._fx_style("slash"))
	var keep = sb.inst.params.get("fx_style")
	sb.inst.params["fx_style"] = "cel"
	_run_for(sb, 2.0)
	sb._fire()
	_run_for(sb, 0.1)
	assert_str(str(sb.effects().last_arc["style"])).is_equal("cel")
	sb.inst.params["fx_style"] = keep
	var ww := _thruster(w, "whirlwind")
	ww._fire()
	_run_for(ww, 0.1)
	assert_float(float(ww.effects().last_arc["half_w"])).is_greater(3.0)


# ---------------------------------------------------------------- the thrust

func test_a_lance_darts_lands_with_the_hit_pierces_and_ends_in_its_time() -> void:
	for st: String in ["lance", "wind"]:
		var w := _world()
		var em: EnemyManager = w["em"]
		_creature(em, Vector3(0, 0, -3.0))
		em._rebuild_grid()
		var b := _thruster(w, "pike")
		var keep = b.inst.params.get("fx_style")
		b.inst.params["fx_style"] = st
		assert_bool(b._fire()).is_true()
		var fx := b.effects()
		var e := _entry_of(fx)
		assert_bool(e.is_empty()).is_false()
		var m: ShaderMaterial = e["mat"]
		assert_str(m.shader.resource_path).ends_with("melee_lance.gdshader")
		assert_int(int(m.get_shader_parameter("style"))).is_equal(2 if st == "wind" else 1)
		var full := float(e["full"])
		var t := 0.0
		var gathered := false
		while not b._hit_done and t < 1.0:
			b._tick(DT)
			t += DT
			if (e["mi"] as MeshInstance3D).visible and float(m.get_shader_parameter("front")) < 0.0:
				gathered = true
		assert_bool(gathered).is_true()
		# the point at the reach as the hit lands, the star and the pierce on it
		assert_float(float(m.get_shader_parameter("pt"))).is_greater(full * 0.95)
		assert_int(fx.impacts_made).is_equal(1)
		b._tick(DT)
		assert_float(float(m.get_shader_parameter("pierce"))).is_greater(0.5)
		# the star stands at the hit's own reach
		var flat := fx.last_flash_at - (w["hero"] as Node3D).global_position
		flat.y = 0.0
		assert_float(flat.length()).is_equal_approx(b._reach(), 0.02)
		# never more than the small overshoot past the reach, then gone with the stroke
		var most := 0.0
		for k in range(int(0.6 / DT)):
			b._tick(DT)
			if bool(e["live"]):
				most = maxf(most, float(m.get_shader_parameter("pt")))
		assert_float(most).is_less_equal(full + 0.11)
		assert_bool(bool(e["live"])).is_false()
		assert_int(fx.thrusts_live()).is_equal(0)
		b.inst.params["fx_style"] = keep


func test_a_miss_has_no_pierce_and_the_spearhead_style_keeps_its_shader() -> void:
	var w := _world()
	var b := _thruster(w, "pike")
	b._fire()
	var e := _entry_of(b.effects())
	var m: ShaderMaterial = e["mat"]
	_run_for(b, 0.3)
	assert_int(b.effects().glints_made).is_equal(1)
	assert_float(float(m.get_shader_parameter("pierce"))).is_equal(0.0)
	var b2 := _thruster(w, "pike")
	var keep = b2.inst.params.get("fx_style")
	b2.inst.params["fx_style"] = "spearhead"
	b2._fire()
	var e2 := _entry_of(b2.effects())
	assert_str((e2["mat"] as ShaderMaterial).shader.resource_path).ends_with("melee_thrust.gdshader")
	b2.inst.params["fx_style"] = keep


# ---------------------------------------------------------------- cheap

func test_the_pools_are_capped_whatever_the_styles() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var fx := MeleeFx.new()
	(w["g"] as Node).add_child(fx)
	for k in range(40):
		var sl: String = MeleeFx.SLASH_STYLES[k % 3]
		var sb: String = MeleeFx.STAB_STYLES[k % 3]
		fx.arc(hero, 0.0, 1.3, 3.0, 0.16, 0.12, 1.0, {"style": sl})
		fx.thrust(hero, Vector3.FORWARD, 3.5, 0.3, 0.0, 0.08, 0.06, 0.22, {"style": sb})
		fx.land(k % 2 == 0)
		fx.tick(DT * 3.0)
	var sizes := fx.pool_sizes()
	assert_int(sizes.x).is_equal(MeleeFx.ARC_MAX)
	assert_int(sizes.y).is_equal(MeleeFx.THRUST_MAX)
	assert_int(sizes.z).is_less_equal(MeleeFx.FLASH_MAX)
	assert_int(fx.get_child_count()).is_equal(MeleeFx.ARC_MAX + MeleeFx.THRUST_MAX + sizes.z)
	fx.queue_free()
