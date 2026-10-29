## The look of a boss's bullet-heaven pattern round him (pass 113, lane BOSS; content/boss_attacks kind "pattern",
## EnemyManager._pattern_*; the bullets themselves are BossAttackFx's). One of these lives for one pattern, follows the
## boss's feet (follow()) and is told where the attack is (tell / fire / spent, each with its 0..1 progress):
##   - the ground darkening round him (Telegraphs: a dark lobed spill fading in over the tell, a ring at its edge in the
##     banner's colour pulsing), gone through the spent seconds;
##   - his shell while he is guarded (`shell.look`): "tornado" a sand tornado round him (lane TWISTER's TornadoFx, loaded by
##     its path at run time so this never fails to compile without it), "pillar" a pillar of fire (core/shaders/
##     boss_pillar.gdshader), "scales" a glow behind him in the shell's colour (his own rim glow is EnemyManager's);
##     the shell forms through the tell, holds through the bullets and collapses or gutters out as he is spent;
##   - the wind-up looks (`tell.look`): "rear" a glowing throat (an additive glow at shell-height share THROAT_UP of his
##     size) swelling through the tell, "drive" the iron struck into the sand at the tell's last part (a burst, a flash ring,
##     a kick of the camera), "spin" sand thrown round him;
##   - `shell.sigil_radius` > 0: a brand sigil burnt into the sand under him (core/shaders/boss_sigil.gdshader), burning in
##     round the circle through the tell and brightening through the bullets;
##   - spent: stars circling over a spun boss's head ("spin"), smoke off a driven iron ("drive").
## Everything see-through is drawn after the stage filter, so Nightfall and Blood Moon never dim it.
class_name BossPatternFx
extends Node3D

const TORNADO_PATH := "res://core/systems/TornadoFx.gd"
const PILLAR_SHADER := preload("res://core/shaders/boss_pillar.gdshader")
const SIGIL_SHADER := preload("res://core/shaders/boss_sigil.gdshader")
const STAR_SHADER := preload("res://core/shaders/boss_star.gdshader")
## where a rearing boss's throat glows, as a share of his height (the Gila's spew mouth is 0.62; she rears up taller
## through the tell), and how far towards the camera it sits (m) so her painting never covers it
const THROAT_UP := 0.74
const THROAT_OUT := 0.6
## the scales' glow sits this far behind the boss's painting (m, away from the camera) so it rims him instead of washing
## him out
const AURA_BACK := 1.6
## the stars over a spun boss: how many, how far round, how high over his head (m)
const STARS := 5
const STAR_R := 0.9
const STAR_UP := 0.55
## seconds the shell takes to go after the bullets end
const SHELL_OUT := 0.8

var game: Node = null
var cdef: BossAttackDef = null
## the boss's size (his painting's height, m) and body radius (m)
var boss_size := 5.0
var boss_radius := 2.0
## 0 tell, 1 fire, 2 spent
var phase := 0
var _at := Vector3.ZERO
var _dark_id := -1
var _edge_id := -1
var _tornado: Node3D = null
var _pillar: MeshInstance3D = null
var _pillar_mat: ShaderMaterial = null
var _aura: MeshInstance3D = null
var _aura_mat: StandardMaterial3D = null
var _throat: MeshInstance3D = null
var _throat_mat: StandardMaterial3D = null
var _sigil: MeshInstance3D = null
var _sigil_mat: ShaderMaterial = null
var _stars: Array = []
var _star_mat: ShaderMaterial = null
var _struck := false
var _clock := 0.0
var _fx_t := 0.0
var _shell_k := 0.0
## for the tests: what was made
var made: Array = []


## Built for `p_def` round a boss of `size` m and `radius` m standing at `at`.
func setup(p_game: Node, p_def: BossAttackDef, at: Vector3, size: float, radius: float) -> void:
	game = p_game
	cdef = p_def
	boss_size = maxf(size, 1.0)
	boss_radius = maxf(radius, 0.5)
	_at = at
	position = at
	var tg = _telegraphs()
	var rr := maxf(cdef.num("tell", "ring_radius"), 0.0)
	if tg and rr > 0.0:
		var dk := BossAttackDef.color_of(cdef.text("tell", "ring_color"), Color(0.08, 0.04, 0.02))
		var a := clampf(cdef.num("tell", "ring_alpha"), 0.0, 1.0)
		_dark_id = tg.hold_blob(at, rr, randf(), Color(dk.r, dk.g, dk.b, a), Color(dk.r, dk.g, dk.b, a * 0.35))
		tg.set_alpha(_dark_id, 0.0)
		var bc := BossAttackDef.color_of(cdef.text("tell", "banner_color"), Color(0.91, 0.31, 0.16))
		_edge_id = tg.hold_ring(at, rr, Color(bc.r, bc.g, bc.b, 0.0))
		made.append("dark")
	match cdef.text("shell", "look"):
		"tornado":
			_make_tornado()
		"pillar":
			_make_pillar()
		"scales":
			_make_aura()
	if cdef.text("tell", "look") == "rear":
		_make_throat()
	if cdef.num("shell", "sigil_radius") > 0.0:
		_make_sigil(cdef.num("shell", "sigil_radius"))


func _telegraphs():
	return game.get("telegraphs") if game != null else null


func _ground_tex() -> Dictionary:
	var tg = _telegraphs()
	if tg == null or tg.get("_heights") == null:
		return {}
	return {"tex": tg.get("_heights"), "grid_n": int(tg.get("_grid_n")), "half": float(tg.get("_half")), "res": float(tg.get("_res"))}


## The boss's feet now (he may be shoved a little): everything rides with him.
func follow(at: Vector3) -> void:
	_at = at
	position = at
	var tg = _telegraphs()
	if tg:
		if _dark_id >= 0:
			tg.move_held(_dark_id, at)
		if _edge_id >= 0:
			tg.move_held(_edge_id, at)


## The tell at `k` (0..1 of its seconds): the ground darkens, the shell forms, the throat swells, the sigil burns in.
func tell(k: float, delta: float) -> void:
	phase = 0
	_clock += delta
	k = clampf(k, 0.0, 1.0)
	var tg = _telegraphs()
	if tg:
		if _dark_id >= 0:
			tg.set_alpha(_dark_id, smoothstep(0.0, 0.6, k))
		if _edge_id >= 0:
			tg.set_alpha(_edge_id, (0.55 + 0.45 * sin(_clock * 10.0)) * smoothstep(0.0, 0.3, k))
	_set_shell(smoothstep(0.1, 1.0, k))
	if _throat:
		var s := boss_size * (0.16 + 0.26 * k) * (1.0 + 0.12 * sin(_clock * 14.0))
		_throat.scale = Vector3.ONE * s
		_throat_mat.albedo_color = Color(_throat_mat.albedo_color, 0.3 + 0.45 * k)
	if _sigil_mat:
		_sigil_mat.set_shader_parameter("fill", smoothstep(0.05, 0.85, k))
		_sigil_mat.set_shader_parameter("power", 0.25 + 0.35 * k)
	match cdef.text("tell", "look"):
		"spin":
			_fx_t -= delta
			if _fx_t <= 0.0 and game and game.get("fx"):
				_fx_t = 0.07
				var a := randf() * TAU
				var r := boss_radius * (1.0 + 0.4 * randf())
				game.fx.sand(_at + Vector3(cos(a) * r, 0.2, sin(a) * r), 0.9 + k)
		"drive":
			if not _struck and k >= 0.7:
				_struck = true
				_strike()
	if game and game.get("camera") and randf() < delta * 6.0:
		game.camera.shake(0.25 + 0.35 * k)


## The bullets at `k` (0..1 of the duration).
func fire(k: float, delta: float) -> void:
	phase = 1
	_clock += delta
	var tg = _telegraphs()
	if tg:
		if _dark_id >= 0:
			tg.set_alpha(_dark_id, 1.0)
		if _edge_id >= 0:
			tg.set_alpha(_edge_id, 0.45 + 0.25 * sin(_clock * 6.0))
	_set_shell(1.0)
	if _throat:
		_throat.scale = Vector3.ONE * boss_size * 0.36 * (1.0 + 0.1 * sin(_clock * 9.0))
		_throat_mat.albedo_color = Color(_throat_mat.albedo_color, 0.6)
	if _sigil_mat:
		_sigil_mat.set_shader_parameter("fill", 1.0)
		_sigil_mat.set_shader_parameter("power", lerpf(0.6, 1.0, clampf(k, 0.0, 1.0)))


## Spent at `k` (0..1 of its seconds): the shell goes, the dark ground lifts, the stars or the smoke.
func spent(k: float, delta: float) -> void:
	if phase != 2:
		phase = 2
		_spent_begin()
	_clock += delta
	k = clampf(k, 0.0, 1.0)
	var tg = _telegraphs()
	if tg:
		if _dark_id >= 0:
			tg.set_alpha(_dark_id, 1.0 - smoothstep(0.0, 0.8, k))
		if _edge_id >= 0:
			tg.set_alpha(_edge_id, 0.0)
	_shell_k = maxf(_shell_k - delta / SHELL_OUT, 0.0)
	_set_shell(_shell_k)
	if _throat:
		_throat_mat.albedo_color = Color(_throat_mat.albedo_color, maxf(1.0 - k * 3.0, 0.0))
	if _sigil_mat:
		# it cools and burns out round the circle
		_sigil_mat.set_shader_parameter("power", lerpf(0.6, 0.0, k))
		_sigil_mat.set_shader_parameter("fill", 1.0 - smoothstep(0.1, 0.95, k))
		if k >= 0.999:
			_sigil.visible = false
	var head := boss_size * 1.0 + STAR_UP
	for j in range(_stars.size()):
		var st: MeshInstance3D = _stars[j]
		var a := _clock * 3.2 + TAU * float(j) / float(maxi(_stars.size(), 1))
		st.position = Vector3(cos(a) * STAR_R, head + 0.15 * sin(_clock * 6.0 + float(j)), sin(a) * STAR_R * 0.55)
	if _star_mat:
		_star_mat.set_shader_parameter("fade", 1.0 - smoothstep(0.8, 1.0, k))
	if cdef.text("tell", "look") == "drive" and game and game.get("fx"):
		_fx_t -= delta
		if _fx_t <= 0.0 and k < 0.95:
			_fx_t = 0.06
			var at := _at + Vector3(boss_radius * 0.35, boss_size * 0.15, 0.0)
			game.fx.mote(at, Vector3(randf_range(-0.3, 0.3), 1.6 + randf() * 0.8, randf_range(-0.3, 0.3)), 1.4, 0.55 + randf() * 0.3, Color(0.22, 0.2, 0.2, 0.75))


## Everything let go (the pattern is over, cancelled, or the boss died).
func finish() -> void:
	var tg = _telegraphs()
	if tg:
		if _dark_id >= 0:
			tg.release(_dark_id)
		if _edge_id >= 0:
			tg.release(_edge_id)
	_dark_id = -1
	_edge_id = -1
	queue_free()


func _exit_tree() -> void:
	# the music back as it was whatever ended the pattern (the run ending under it, the boss gone)
	var au = get_node_or_null("/root/Audio")
	if au != null and au.has_method("duck_music"):
		au.duck_music(0.0, 0.0)
	var tg = _telegraphs()
	if tg and is_instance_valid(tg):
		if _dark_id >= 0:
			tg.release(_dark_id)
		if _edge_id >= 0:
			tg.release(_edge_id)
	_dark_id = -1
	_edge_id = -1


func _spent_begin() -> void:
	_shell_k = 1.0
	if _tornado and _tornado.has_method("burst"):
		_tornado.call("burst")
	if game and game.get("fx"):
		game.fx.burst(_at + Vector3(0, boss_size * 0.5, 0), BossAttackDef.color_of(cdef.text("shell", "color"), Color(0.8, 0.6, 0.4)), boss_radius * 1.2)
	if cdef.text("tell", "look") == "spin":
		_make_stars()


func _set_shell(k: float) -> void:
	_shell_k = k if phase != 2 else _shell_k
	if _tornado and _tornado.has_method("set_strength"):
		_tornado.call("set_strength", k)
	if _pillar_mat:
		_pillar_mat.set_shader_parameter("strength", k)
		_pillar.visible = k > 0.01
	if _aura:
		_aura.visible = k > 0.01
		_aura_mat.albedo_color = Color(_aura_mat.albedo_color, 0.45 * k * (0.85 + 0.15 * sin(_clock * 5.0)))


func _make_tornado() -> void:
	if not ResourceLoader.exists(TORNADO_PATH):
		return
	var scr = load(TORNADO_PATH)
	if not (scr is Script) or not (scr as Script).can_instantiate():
		return
	var t = (scr as Script).new()
	if not (t is Node3D):
		return
	var h := maxf(cdef.num("shell", "height"), 1.0)
	var r := maxf(cdef.num("shell", "radius"), 0.5)
	t.set("height", h)
	t.set("radius_bottom", r * 0.6)
	t.set("radius_top", r * 1.35)
	t.set("color", BossAttackDef.color_of(cdef.text("shell", "color"), Color(0.78, 0.58, 0.38)))
	t.set("spin", 1.4)
	# pass 113 (the lead): thin enough for the boss to show through (`shell.opacity`, TornadoFx clamps it to 0.5..1)
	t.set("opacity", cdef.num("shell", "opacity"))
	t.name = "Tornado"
	add_child(t)
	_tornado = t
	if _tornado.has_method("set_strength"):
		_tornado.call("set_strength", 0.0)
	made.append("tornado")


func _make_pillar() -> void:
	var h := maxf(cdef.num("shell", "height"), 1.0)
	var r := maxf(cdef.num("shell", "radius"), 0.5)
	var cm := CylinderMesh.new()
	cm.top_radius = r * 1.05
	cm.bottom_radius = r
	cm.height = h
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 28
	cm.rings = 2
	_pillar_mat = ShaderMaterial.new()
	_pillar_mat.shader = PILLAR_SHADER
	_pillar_mat.set_shader_parameter("color", BossAttackDef.color_of(cdef.text("shell", "color"), Color(1.0, 0.42, 0.1)))
	_pillar_mat.set_shader_parameter("strength", 0.0)
	_pillar_mat.set_shader_parameter("height", h)
	_pillar = MeshInstance3D.new()
	_pillar.name = "Pillar"
	_pillar.mesh = cm
	_pillar.material_override = _pillar_mat
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.position = Vector3(0, h * 0.5, 0)
	_pillar.visible = false
	add_child(_pillar)
	made.append("pillar")


## A soft additive glow in `col`, a camera-facing quad of `px` metres (the aura, the throat).
static func glow_quad(col: Color, px: float) -> Array:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# (the game has fog: an additive glow would add the fog's colour all over its quad)
	m.disable_fog = true
	m.albedo_texture = tex
	m.albedo_color = col
	var q := QuadMesh.new()
	q.size = Vector2(px, px)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return [mi, m]


func _make_aura() -> void:
	var col := BossAttackDef.color_of(cdef.text("shell", "color"), Color(0.6, 0.3, 0.9))
	var made_q := glow_quad(Color(col.r, col.g, col.b, 0.0), boss_size * 1.3)
	_aura = made_q[0]
	_aura_mat = made_q[1]
	_aura.name = "Aura"
	# behind his painting (the camera looks north, down -Z): a halo round him, not a wash over him
	_aura.position = Vector3(0, boss_size * 0.5, -AURA_BACK)
	_aura.visible = false
	add_child(_aura)
	made.append("aura")


func _make_throat() -> void:
	var col := BossAttackDef.color_of(cdef.text("projectile", "tint"), Color(0.66, 0.22, 0.95))
	var made_q := glow_quad(Color(col.r, col.g, col.b, 0.35), 1.0)
	_throat = made_q[0]
	_throat_mat = made_q[1]
	_throat.name = "Throat"
	# a touch towards the camera so the painting never covers it
	_throat.position = Vector3(0, boss_size * THROAT_UP, THROAT_OUT)
	_throat.scale = Vector3.ONE * boss_size * 0.18
	add_child(_throat)
	made.append("throat")


func _make_sigil(r: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.0, r * 2.0)
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	_sigil_mat = ShaderMaterial.new()
	_sigil_mat.shader = SIGIL_SHADER
	_sigil_mat.set_shader_parameter("color", BossAttackDef.color_of(cdef.text("shell", "sigil_color"), Color(1.0, 0.42, 0.1)))
	_sigil_mat.set_shader_parameter("radius", r)
	_sigil_mat.set_shader_parameter("fill", 0.0)
	_sigil_mat.set_shader_parameter("power", 0.25)
	var gt := _ground_tex()
	if not gt.is_empty():
		_sigil_mat.set_shader_parameter("heights", gt["tex"])
		_sigil_mat.set_shader_parameter("grid_n", int(gt["grid_n"]))
		_sigil_mat.set_shader_parameter("half_size", float(gt["half"]))
		_sigil_mat.set_shader_parameter("resolution", float(gt["res"]))
	_sigil = MeshInstance3D.new()
	_sigil.name = "Sigil"
	_sigil.mesh = pm
	_sigil.material_override = _sigil_mat
	_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sigil.extra_cull_margin = 4.0
	add_child(_sigil)
	made.append("sigil")


func _make_stars() -> void:
	if not _stars.is_empty():
		return
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = STAR_SHADER
	for j in range(STARS):
		var q := QuadMesh.new()
		q.size = Vector2(0.55, 0.55)
		var mi := MeshInstance3D.new()
		mi.name = "Star%d" % j
		mi.mesh = q
		mi.material_override = _star_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_stars.append(mi)
	made.append("stars")


## The iron driven into the sand (the Brander's tell): a burst of fire at his feet, a flash ring, a kick of the camera.
func _strike() -> void:
	if game == null:
		return
	var col := BossAttackDef.color_of(cdef.text("shell", "sigil_color"), Color(1.0, 0.42, 0.1))
	if game.get("fx"):
		game.fx.burst(_at + Vector3(0, 0.5, 0), col, 2.4)
	var tg = _telegraphs()
	if tg and tg.has_method("flash_ring"):
		tg.flash_ring(_at, maxf(cdef.num("shell", "sigil_radius"), 4.0), col, 0.5)
	if game.get("camera"):
		game.camera.shake(1.3)
