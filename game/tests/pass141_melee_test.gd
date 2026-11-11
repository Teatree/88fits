extends GdUnitTestSuite

## Pass 141, lane MELEE: the Spear's thrust as a flipbook ("burst", the default: six frames,
## core/shaders/melee_burst.gdshader, art/fx/melee/thrust_burst.png; pass 142: our own frames, tools/gen_thrust_fx.py),
## the CC0 procedural cyclic slash ("cyclic") by params.fx_style (pass 142: the pack's "moon" is gone, the Sabre and the
## Whirlwind swing the crescent again). The key and its defaults, the frames timed to the stroke (the big frame with the
## hit, the hit's moment unchanged), the head at the reach as the hit lands, the pools capped, the textures.

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



func _entry_of(fx: MeleeFx, k := 0) -> Dictionary:
	var live: Array = fx._thrusts.filter(func(e: Dictionary) -> bool: return bool(e["live"]))
	return live[k] if k < live.size() else {}


# ---------------------------------------------------------------- the key

func test_the_style_key_and_its_defaults() -> void:
	assert_str(MeleeFx.style_of("stab", "")).is_equal("burst")
	assert_str(MeleeFx.style_of("stab", "burst")).is_equal("burst")
	for st: String in ["lance", "wind", "spearhead"]:
		assert_str(MeleeFx.style_of("stab", st)).is_equal(st)
	assert_str(MeleeFx.style_of("stab", "cyclic")).is_equal("burst")
	for st: String in ["crescent", "cel", "classic", "cyclic"]:
		assert_str(MeleeFx.style_of("slash", st)).is_equal(st)
	# pass 142: the pack's "moon" is no style now (the default stands in)
	assert_str(MeleeFx.style_of("slash", "moon")).is_equal("crescent")
	assert_bool(MeleeFx.SLASH_STYLES.has("moon")).is_false()
	assert_str(MeleeFx.style_of("slash", "burst")).is_equal(str(MeleeFx.SLASH_STYLES[0]))
	# the Spear and the Thunder Lance play the burst; every melee weapon names a style of its own kind
	for id: String in ["pike", "thunder_lance"]:
		var wd = Registry.weapon(id)
		assert_str(MeleeFx.style_of("stab", str(wd.params.get("fx_style", "")))).is_equal("burst")
	# pass 142 (Garry: "Sword, I liked the previous version more. Bring it back"): the Sabre and the Whirlwind play the
	# crescent again; a stab weapon's sweep keeps it too (its tipped point, the Thunder Lance's crackle)
	for id: String in ["sabre", "whirlwind"]:
		var wd = Registry.weapon(id)
		assert_str(str(wd.params.get("fx_style", ""))).is_equal("crescent")
	assert_str(MeleeFx.style_of("slash", str(Registry.weapon("pike").params.get("fx_style", "")))).is_equal("crescent")


# ---------------------------------------------------------------- the flipbook's timing

func test_the_burst_frames_run_with_the_stroke_the_big_one_with_the_hit() -> void:
	var ext := 0.08
	var hold := 0.06
	var fade := 0.22
	# before the dart only the glint
	assert_float(MeleeFx.burst_frame(-0.01, ext, hold, fade)).is_equal(-1.0)
	assert_float(MeleeFx.burst_frame(0.0, ext, hold, fade)).is_equal(0.0)
	# the third frame (index 2, the big burst) arrives as the hit lands
	assert_float(MeleeFx.burst_frame(ext, ext, hold, fade)).is_equal_approx(2.0, 0.001)
	assert_float(MeleeFx.burst_frame(ext * 0.5, ext, hold, fade)).is_equal_approx(1.0, 0.001)
	# the fourth after the hold and BURST_BODY of the fade, the embers to the end, never past the last frame
	assert_float(MeleeFx.burst_frame(ext + hold + fade * MeleeFx.BURST_BODY, ext, hold, fade)).is_equal_approx(3.0, 0.001)
	assert_float(MeleeFx.burst_frame(ext + hold + fade, ext, hold, fade)).is_less(6.0)
	assert_float(MeleeFx.burst_frame(ext + hold + fade, ext, hold, fade)).is_greater(5.9)
	var last := -1.0
	var t := -0.05
	while t < ext + hold + fade + 0.1:
		var f := MeleeFx.burst_frame(t, ext, hold, fade)
		assert_float(f).is_greater_equal(last)
		assert_float(f).is_less(6.0)
		last = f
		t += 0.005


func test_a_burst_darts_to_the_reach_lands_with_the_hit_and_ends_in_its_time() -> void:
	for face: float in [0.0, 1.0]:
		var keep_face := MeleeFx.burst_face
		MeleeFx.burst_face = face
		var w := _world()
		var em: EnemyManager = w["em"]
		_creature(em, Vector3(0, 0, -3.0))
		em._rebuild_grid()
		var b := _thruster(w, "pike")
		assert_bool(b._fire()).is_true()
		var fx := b.effects()
		var e := _entry_of(fx)
		assert_bool(e.is_empty()).is_false()
		var m: ShaderMaterial = e["mat"]
		assert_str(m.shader.resource_path).ends_with("melee_burst.gdshader")
		assert_object(m.get_shader_parameter("frames")).is_not_null()
		assert_float(float(m.get_shader_parameter("face_cam"))).is_equal(face)
		assert_str(str(fx.last_thrust["style"])).is_equal("burst")
		var full := float(e["full"])
		var t := 0.0
		var gathered := false
		while not b._hit_done and t < 1.0:
			b._tick(DT)
			t += DT
			if (e["mi"] as MeshInstance3D).visible and float(m.get_shader_parameter("fr")) < 0.0 and float(m.get_shader_parameter("glint")) > 0.0:
				gathered = true
		assert_bool(gathered).is_true()
		# the head at the reach and the big frame as the hit lands (the hit's own moment: windback + out), the star on it
		var th: Dictionary = b.inst.params.get("thrust", {})
		var hit_at := maxf(float(th.get("windback", Thruster.WINDBACK)), 0.0) + float(th.get("out", 0.12))
		assert_float(t).is_equal_approx(hit_at, DT * 1.5)
		assert_float(float(m.get_shader_parameter("pt"))).is_greater(full * 0.95)
		assert_float(float(m.get_shader_parameter("fr"))).is_between(1.6, 2.4)
		assert_int(fx.impacts_made).is_equal(1)
		b._tick(DT)
		assert_float(float(m.get_shader_parameter("pierce"))).is_greater(0.5)
		var flat := fx.last_flash_at - (w["hero"] as Node3D).global_position
		flat.y = 0.0
		assert_float(flat.length()).is_equal_approx(b._reach(), 0.02)
		# the frames run on to the embers, then it is gone with the stroke
		var most := 0.0
		for k in range(int(0.6 / DT)):
			b._tick(DT)
			if bool(e["live"]):
				most = maxf(most, float(m.get_shader_parameter("fr")))
		assert_float(most).is_greater(5.0)
		assert_bool(bool(e["live"])).is_false()
		assert_int(fx.thrusts_live()).is_equal(0)
		MeleeFx.burst_face = keep_face


func test_a_missed_burst_glints_and_the_old_styles_keep_their_shaders() -> void:
	var w := _world()
	var b := _thruster(w, "pike")
	b._fire()
	var e := _entry_of(b.effects())
	var m: ShaderMaterial = e["mat"]
	_run_for(b, 0.3)
	assert_int(b.effects().glints_made).is_equal(1)
	assert_float(float(m.get_shader_parameter("pierce"))).is_equal(0.0)
	for pair: Array in [["lance", "melee_lance.gdshader"], ["wind", "melee_lance.gdshader"], ["spearhead", "melee_thrust.gdshader"]]:
		var b2 := _thruster(w, "pike")
		b2.inst.params["fx_style"] = pair[0]
		b2._fire()
		var e2 := _entry_of(b2.effects())
		assert_str((e2["mat"] as ShaderMaterial).shader.resource_path).ends_with(str(pair[1]))
		b2.inst.params.erase("fx_style")


# ---------------------------------------------------------------- the swing

func test_the_cyclic_swing_reveals_and_ends_like_the_crescent() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	for st: String in ["cyclic"]:
		var fx := MeleeFx.new()
		(w["g"] as Node).add_child(fx)
		fx.arc(hero, 0.0, 1.3, 3.0, 0.16, 0.12, 1.0, {"style": st})
		var e: Dictionary = fx._arcs[0]
		var m: ShaderMaterial = e["mat"]
		assert_str(m.shader.resource_path).ends_with("melee_swing_fx.gdshader")
		assert_object(m.get_shader_parameter("noise")).is_not_null()
		assert_float(float(m.get_shader_parameter("pull"))).is_equal(MeleeFx.GROUND_PULL)
		var t := 0.0
		while t + DT * 0.5 < 0.16:
			fx.tick(DT)
			t += DT
		assert_float(float(m.get_shader_parameter("head"))).is_greater(0.97)
		var gone_at := -1.0
		while t < 1.0 and gone_at < 0.0:
			fx.tick(DT)
			t += DT
			if not bool(e["live"]):
				gone_at = t
		# at least SLASH_FADE after the sweep, as the crescent
		assert_float(gone_at).is_greater(0.16 + MeleeFx.SLASH_FADE * 0.9)
		assert_float(gone_at).is_less_equal(0.16 + MeleeFx.SLASH_FADE + DT * 2.0)
		fx.queue_free()


func test_the_swing_shader_keeps_the_ground_pull_and_the_burst_draws_over_everything() -> void:
	var sw: String = (load("res://core/shaders/melee_swing_fx.gdshader") as Shader).code
	assert_bool(sw.contains("uniform float pull")).is_true()
	assert_bool(sw.contains("skip_vertex_transform")).is_true()
	assert_bool(sw.contains("depth_test_disabled")).is_false()
	var bu: String = (load("res://core/shaders/melee_burst.gdshader") as Shader).code
	assert_bool(bu.contains("depth_test_disabled")).is_true()
	assert_bool(bu.contains("fog_disabled")).is_true()


# ---------------------------------------------------------------- cheap

func test_the_pools_are_capped_with_every_style_and_one_texture_shared() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var fx := MeleeFx.new()
	(w["g"] as Node).add_child(fx)
	for k in range(40):
		var sl: String = MeleeFx.SLASH_STYLES[k % MeleeFx.SLASH_STYLES.size()]
		var sb: String = MeleeFx.STAB_STYLES[k % MeleeFx.STAB_STYLES.size()]
		fx.arc(hero, 0.0, 1.3, 3.0, 0.16, 0.12, 1.0, {"style": sl})
		fx.thrust(hero, Vector3.FORWARD, 3.5, 0.3, 0.0, 0.08, 0.06, 0.22, {"style": sb})
		fx.land(k % 2 == 0)
		fx.tick(DT * 3.0)
	var sizes := fx.pool_sizes()
	assert_int(sizes.x).is_equal(MeleeFx.ARC_MAX)
	assert_int(sizes.y).is_equal(MeleeFx.THRUST_MAX)
	assert_int(sizes.z).is_less_equal(MeleeFx.FLASH_MAX)
	assert_int(fx.get_child_count()).is_equal(MeleeFx.ARC_MAX + MeleeFx.THRUST_MAX + sizes.z)
	# every burst shares the one texture (no copy a stroke)
	var tex = null
	for e: Dictionary in fx._thrusts:
		var mt: ShaderMaterial = e["mat"]
		if mt.shader.resource_path.ends_with("melee_burst.gdshader"):
			if tex == null:
				tex = mt.get_shader_parameter("frames")
			assert_object(mt.get_shader_parameter("frames")).is_same(tex)
	assert_object(tex).is_not_null()
	fx.queue_free()


func test_the_textures_are_six_frames_and_the_noise() -> void:
	var burst: Texture2D = load(MeleeFx.BURST_TEX)
	assert_object(burst).is_not_null()
	assert_int(burst.get_height() % 6).is_equal(0)
	assert_int(burst.get_width()).is_greater(burst.get_height() / 6)
	# pass 142: the pack's painted swing is out of the game
	assert_bool(ResourceLoader.exists("res://art/fx/melee/slash_moon.png")).is_false()
	var noise: Texture2D = load(MeleeFx.NOISE_TEX)
	assert_object(noise).is_not_null()
	# the burst's tail and head lie inside the frame, the tail first
	assert_float(MeleeFx.BURST_TAIL_U).is_less(MeleeFx.BURST_HEAD_U)
	assert_float(MeleeFx.BURST_HEAD_U).is_less(1.0)
	# the big frame (index 2) is the fullest of the first and the last
	var img := burst.get_image()
	var fh := img.get_height() / 6
	var sums: Array[float] = []
	for k in range(6):
		var s := 0.0
		for y in range(k * fh, (k + 1) * fh, 4):
			for x in range(0, img.get_width(), 4):
				s += img.get_pixel(x, y).r
		sums.append(s)
	assert_float(sums[2]).is_greater(sums[0])
	assert_float(sums[2]).is_greater(sums[5])
