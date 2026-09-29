## Cheap visual effects. Every burst, puff, spark and flash is one instance in one of three pooled MultiMeshes
## (spheres with alpha, opaque shards, flame tongues), so a hundred deaths a minute cost three draw calls and no nodes.
## Lightning bolts are ribbons in two shared ImmediateMeshes, a coloured sheath and a white core (pass 33.8: two nodes,
## two materials and two draw calls per strike before). Lights are skipped on phones.
class_name Fx
extends Node3D

const MAX_P := 400

# per particle
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _a0 := PackedFloat32Array()
var _a1 := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _col := PackedColorArray()
var _shard := PackedByteArray()   # 1 = box shard pool, 0 = sphere pool, 2 = flame pool
var _seed := PackedFloat32Array()  # flames: where each one reads the noise, so no two burn alike
var _n := 0

var _sph_mm: MultiMesh
var _box_mm: MultiMesh
## Flame tongues (pass 33): camera-facing quads drawn by core/shaders/fire_billboard.gdshader
var _flame_mm: MultiMesh
const FLAME_ORANGE := Color(1.0, 0.56, 0.13)
var _live := 0   # bolts still showing
const MAX_LIVE := 40
## live bolts: {sheath: PackedVector3Array, core: PackedVector3Array (triangles, built once), color: Color, t: seconds}
var _bolts: Array = []
var _sheath_mesh: ImmediateMesh
var _core_mesh: ImmediateMesh
var _sheath_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _bolts_drawn := false
const SHEATH_LIFE := 0.32
const CORE_LIFE := 0.26


## Whether short-lived point lights are worth it on this device (never on phones: every lit pixel pays for them).
static func want_lights() -> bool:
	return not OS.has_feature("mobile")


func _ready() -> void:
	_pos.resize(MAX_P); _vel.resize(MAX_P); _age.resize(MAX_P); _life.resize(MAX_P)
	_s0.resize(MAX_P); _s1.resize(MAX_P); _a0.resize(MAX_P); _a1.resize(MAX_P); _grav.resize(MAX_P)
	_col.resize(MAX_P); _shard.resize(MAX_P); _seed.resize(MAX_P)
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 8
	s.rings = 4
	_sph_mm = _pool(s, true)
	var b := BoxMesh.new()
	b.size = Vector3(0.26, 0.26, 0.26)
	_box_mm = _pool(b, false)
	_flame_mm = _flame_pool()
	_build_bolt_meshes()


## The two meshes every bolt is drawn into: see-through, both sides, over everything (as the per-strike ones were).
func _build_bolt_meshes() -> void:
	_sheath_mat = _bolt_material(0)
	_core_mat = _bolt_material(1)
	_sheath_mesh = ImmediateMesh.new()
	_core_mesh = ImmediateMesh.new()
	for pair in [[_sheath_mesh, _sheath_mat], [_core_mesh, _core_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0]
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		mi.top_level = true
		add_child(mi)


func _bolt_material(priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = priority
	return mat


## The flame pool: unit quads that the fire shader turns to the camera and stands on their base.
func _flame_pool() -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = MAX_P
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/fire_billboard.gdshader")
	mat.set_shader_parameter("noise_tex", load("res://art/fx/fire_noise.png"))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


func _pool(mesh: Mesh, alpha: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MAX_P
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


## How much of the effect budget a spawn may use: full while the fight is small, a third of the particles once the
## crowd is at its cap, so a hundred hits a second do not each pay for a puff (the phone's fill rate, not the CPU).
func _busy_skip() -> bool:
	if _n < MAX_P / 3:
		return false
	if _n >= MAX_P * 3 / 4:
		return randf() < 0.66
	return randf() < 0.33


func _emit(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, a0: float, a1: float, col: Color, grav := 0.0, shard := false, must := false) -> void:
	if _n >= MAX_P:
		return
	if not must and _busy_skip():
		return
	var i := _n
	_n += 1
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = s0; _s1[i] = s1; _a0[i] = a0; _a1[i] = a1; _grav[i] = grav
	_col[i] = col; _shard[i] = 1 if shard else 0


## One flame tongue: it grows from `s0` to `s1` metres tall while the shader's noise eats it away with age.
func _emit_flame(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, col: Color, must := false) -> void:
	if _n >= MAX_P:
		return
	if not must and _busy_skip():
		return
	var i := _n
	_n += 1
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = s0; _s1[i] = s1; _a0[i] = col.a; _a1[i] = col.a * 0.85; _grav[i] = 0.0
	_col[i] = col; _shard[i] = 2; _seed[i] = randf()


## A flame standing on `at`, `height` metres tall at its fullest (a burning pool, a Berserk hero).
func flame(at: Vector3, height: float, life: float = 0.55, col: Color = FLAME_ORANGE) -> void:
	_emit_flame(at, Vector3(randf_range(-0.12, 0.12), randf_range(0.5, 0.9), randf_range(-0.12, 0.12)), life, height * 0.5, height, col)


## A drop of burning oil falling from `at` for `fall` seconds (the Oil Slick's leak).
func drop(at: Vector3, fall: float) -> void:
	_emit(at, Vector3(0, -0.5, 0), maxf(fall, 0.05), 0.2, 0.14, 1.0, 1.0, Color(1.0, 0.62, 0.2), 24.0)


func burst(at: Vector3, color: Color, size: float = 1.0) -> void:
	# the coloured cloud that grows and fades, and a hot white core that pops first so the burst has a snap
	_emit(at, Vector3.ZERO, 0.34, 0.2, size * 2.2, 0.9, 0.0, color)
	_emit(at, Vector3.ZERO, 0.16, 0.1, size * 1.1, 0.95, 0.0, Color(1, 1, 1))


## A big explosion (pass 33.3, the rocketeer's rocket), `r` metres: a white flash that pops, orange and red balls
## swelling out of it, a fireball of flame tongues thrown out and up, sparks and grit flung wide, and a beat later dark
## smoke rolling up where it was. None of it is thinned for the budget: it is the one thing on screen that must read.
func explosion(at: Vector3, r: float = 1.6) -> void:
	var c := at + Vector3(0, 0.45, 0)
	_emit(c + Vector3(0, 0.35, 0), Vector3.ZERO, 0.16, 0.5 * r, 2.3 * r, 1.0, 0.0, Color(1.0, 0.97, 0.86), 0.0, false, true)
	for k in range(6):
		var o := Vector3(randf_range(-0.55, 0.55), randf_range(0.1, 0.8), randf_range(-0.55, 0.55)) * r
		var col := Color(1.0, 0.62 + 0.2 * randf(), 0.18) if k % 2 == 0 else Color(1.0, 0.32, 0.08)
		_emit(c + o, o * 1.6 + Vector3(0, 1.4, 0), randf_range(0.38, 0.55), 0.35 * r, randf_range(1.0, 1.4) * r, 0.95, 0.0, col, 0.0, false, true)
	for k in range(14):
		var a := TAU * float(k) / 14.0 + randf() * 0.4
		var out := Vector3(cos(a), 0, sin(a))
		var h: float = randf_range(1.0, 1.7) * r
		_emit_flame(c + out * 0.35 * r, out * randf_range(1.2, 2.8) * r + Vector3(0, randf_range(1.8, 3.6), 0), randf_range(0.45, 0.7), h * 0.45, h, FLAME_ORANGE, true)
	for k in range(18):
		var a2 := randf() * TAU
		var v := Vector3(cos(a2), 0, sin(a2)) * randf_range(4.0, 9.0) + Vector3(0, randf_range(3.0, 7.5), 0)
		_emit(c, v, randf_range(0.45, 0.85), 0.75, 0.15, 1.0, 0.9, Color(1.0, 0.82, 0.35), 14.0, true, true)
	for k in range(8):
		var a3 := randf() * TAU
		var v3 := Vector3(cos(a3), 0, sin(a3)) * randf_range(3.0, 6.5) + Vector3(0, randf_range(4.0, 8.0), 0)
		_emit(at + Vector3(0, 0.2, 0), v3, randf_range(0.6, 0.95), 1.3, 0.8, 1.0, 1.0, Color(0.36, 0.22, 0.14), 20.0, true, true)
	for k in range(5):
		var a4 := TAU * float(k) / 5.0
		sand(at + Vector3(cos(a4), 0.1, sin(a4)) * r * 0.7, 1.3)
	if want_lights():
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.25)
		glow.omni_range = r * 6.0
		glow.light_energy = 6.0
		glow.position = c + Vector3(0, 0.8, 0)
		add_child(glow)
		var tw := create_tween()
		tw.tween_property(glow, "light_energy", 0.0, 0.4)
		tw.tween_callback(glow.queue_free)
	# the smoke comes a beat after the fire, so it rolls up out of the fireball instead of greying it from the start
	get_tree().create_timer(0.12, false).timeout.connect(func() -> void:
		for k in range(8):
			var o2 := Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.1), randf_range(-0.8, 0.8)) * r
			_emit(c + o2, Vector3(o2.x * 0.5, randf_range(1.0, 2.0), o2.z * 0.5), randf_range(1.1, 1.7), 0.45 * r, randf_range(1.3, 1.9) * r, 0.62, 0.0, Color(0.2, 0.18, 0.17), -0.4, false, true))


## Sand thrown up from a point: a low tan puff and a spray of grains that fall back (the eruption, a burrow).
func sand(at: Vector3, size: float = 1.0) -> void:
	_emit(at, Vector3(0, 0.6, 0), 0.4, 0.25 * size, 0.8 * size, 0.7, 0.0, Color(0.9, 0.78, 0.55))
	_emit(at, Vector3(0, 1.2, 0), 0.22, 0.15 * size, 0.5 * size, 0.9, 0.0, Color(1.0, 0.95, 0.8))
	for k in range(10):
		var v := Vector3(randf_range(-2.2, 2.2), randf_range(3.0, 6.0), randf_range(-2.2, 2.2)) * size
		_emit(at, v, randf_range(0.35, 0.6), 0.14 * size, 0.06 * size, 1.0, 0.6, Color(0.8, 0.62, 0.38), 12.0, true)


## Sand kicked up round a creature's feet while it is dragged (pass 33.10: the harpooner on its rope, `pull` the way it is
## hauled): two low puffs spread round the feet and a few grains thrown back against the pull.
func drag_dust(at: Vector3, pull: Vector3) -> void:
	var back := -Vector3(pull.x, 0.0, pull.z)
	for k in range(2):
		var off := Vector3(randf_range(-0.6, 0.6), 0.15, randf_range(-0.4, 0.4))
		_emit(at + off, back * 0.7 + Vector3(0, 0.45, 0), randf_range(0.45, 0.6), 0.35, 1.4, 0.7, 0.0, Color(0.9, 0.76, 0.52))
	if _busy_skip():
		return
	for k in range(3):
		var v := back * randf_range(1.0, 2.2) + Vector3(randf_range(-0.8, 0.8), randf_range(1.5, 3.0), randf_range(-0.8, 0.8))
		_emit(at + Vector3(0, 0.1, 0), v, randf_range(0.3, 0.5), 0.12, 0.05, 1.0, 0.6, Color(0.78, 0.6, 0.36), 10.0, true)


## A mote drifting along `vel` and shrinking as it goes (pass 35: dust drawn into the Singularity's black hole).
func mote(at: Vector3, vel: Vector3, life: float, size: float, col: Color) -> void:
	_emit(at, vel, life, size, size * 0.3, col.a, 0.0, Color(col.r, col.g, col.b))


## The material every swept trail shares (pass 35: the Sabre's crescent, the Hammer's smear, the Gravity Gun's beam, the
## Golden Revolver's lines): additive and vertex-coloured, one instance so its shader compiles once, in the warm-up.
static var _glow_ribbon: StandardMaterial3D


## Its see-through twin (not additive), for a ribbon that must keep its colour on bright sand: the Gravity Gun's beam.
static var _tint_ribbon: StandardMaterial3D


static func tint_ribbon_material() -> StandardMaterial3D:
	if _tint_ribbon == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_tint_ribbon = m
	return _tint_ribbon


static func glow_ribbon_material() -> StandardMaterial3D:
	if _glow_ribbon == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_glow_ribbon = m
	return _glow_ribbon


## A poison tick: two small green puffs drifting up, so the damage is seen.
func poison(at: Vector3) -> void:
	for k in range(2):
		var p := at + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
		_emit(p, Vector3(0, 2.2, 0), 0.5, 0.22, 0.55, 0.85, 0.0, Color(0.5, 1.0, 0.4))


## A burning creature, every 0.18 s: one flame tongue licking up its body (a gold heart, an orange body, a red rim),
## and now and then an ember flying off the top.
func fire(at: Vector3, size: float = 1.0) -> void:
	var p := at + Vector3(randf_range(-0.28, 0.28) * size, randf_range(-0.1, 0.2) * size, randf_range(-0.2, 0.2) * size)
	var h: float = clampf(0.75 + 0.5 * size, 0.8, 2.6) * randf_range(0.85, 1.15)
	_emit_flame(p, Vector3(randf_range(-0.2, 0.2), randf_range(0.8, 1.3), randf_range(-0.2, 0.2)), randf_range(0.45, 0.6), h * 0.5, h, FLAME_ORANGE)
	if randf() < 0.3:
		_emit(p + Vector3(0, h * 0.6, 0), Vector3(randf_range(-0.8, 0.8), randf_range(2.0, 3.0), randf_range(-0.8, 0.8)), 0.4, 0.3, 0.12, 1.0, 0.8, Color(1.0, 0.8, 0.35), 2.0, true)


## Catching fire: three tongues flare up at once, and a ring of sparks.
func ignite(at: Vector3, size: float = 1.0) -> void:
	for k in range(3):
		var p := at + Vector3(randf_range(-0.3, 0.3) * size, -0.15 * size, randf_range(-0.2, 0.2) * size)
		var h: float = clampf(0.9 + 0.55 * size, 1.0, 3.0)
		_emit_flame(p, Vector3(0, 1.4, 0), 0.5, h * 0.4, h, FLAME_ORANGE)
	for k in range(5):
		var a := TAU * k / 5.0 + randf() * 0.5
		_emit(at + Vector3(0, 0.3, 0), Vector3(cos(a) * 2.5, 3.0, sin(a) * 2.5), 0.35, 0.5, 0.05, 1.0, 1.0, Color(1.0, 0.8, 0.3), 12.0, true)


func hit(at: Vector3, color: Color) -> void:
	if randf() > 0.7:
		return
	# two bright shards flung out of the impact, plus a tiny flash
	var c := color.lightened(0.25)
	for k in range(2):
		_emit(at, Vector3(randf_range(-3.6, 3.6), randf_range(2.0, 6.0), randf_range(-3.6, 3.6)), 0.3, 1.0, 0.05, 1.0, 1.0, c, 0.0, true)
	_emit(at, Vector3.ZERO, 0.12, 0.2, 0.7, 0.8, 0.0, Color(1, 1, 1))


## Momentum (Buck): dust kicked up at the heels while it builds, and past half charge warm streaks trailing behind,
## brighter and longer the closer he is to full. `back` points away from where he is running, `strength` is 0..1.
func trail(at: Vector3, back: Vector3, strength: float) -> void:
	var p := at + Vector3(randf_range(-0.25, 0.25), 0.08, randf_range(-0.25, 0.25))
	_emit(p, back * randf_range(1.0, 2.0) + Vector3(0, 0.9, 0), 0.45, 0.22 + 0.3 * strength, 0.8 + strength, 0.5, 0.0, Color(0.9, 0.78, 0.55))
	if strength > 0.5:
		var c := Color(1.0, 0.72 + 0.25 * strength, 0.3)
		var q := at + Vector3(randf_range(-0.2, 0.2), randf_range(0.3, 1.3), randf_range(-0.2, 0.2))
		_emit(q, back * randf_range(3.0, 5.5), 0.28, 0.5 + 0.5 * strength, 0.05, 0.9, 1.0, c, 0.0, true)
	if strength > 0.95:
		# full charge: a white-hot spark now and then, the sign to keep running
		_emit(at + Vector3(0, 0.9, 0), back * 2.0 + Vector3(0, 1.5, 0), 0.22, 0.35, 0.05, 1.0, 1.0, Color(1, 1, 0.9), 0.0, true)


## A spent casing out of the breech: one brass shard flung up and to `side`, dropping under gravity.
func shell(at: Vector3, side: Vector3) -> void:
	_emit(at, side * randf_range(1.2, 2.2) + Vector3(0, randf_range(2.2, 3.2), 0), 0.5, 0.12, 0.1, 1.0, 0.7, Color(0.95, 0.75, 0.3), 12.0, true)


## A jittered bolt through `points` as a camera-facing ribbon: a white-hot core and a wide coloured sheath (a one-pixel
## line was lost on the sand), a flash at every point, gone in a third of a second with a flicker.
func lightning(points: Array, color: Color = Color(0.3, 0.58, 1.0)) -> void:
	if points.size() < 2 or _live >= MAX_LIVE:
		return
	# a zigzag between the points: a bolt, not a line (additive washed to white over the sand, so the sheath is a
	# solid saturated blue and only the core is white)
	var jit: Array = []
	for k in range(points.size() - 1):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var segs := 6
		for s in range(segs + (1 if k == points.size() - 2 else 0)):
			var p := a.lerp(b, float(s) / segs)
			if s > 0 and s < segs:
				var side := 0.55 if s % 2 == 0 else -0.55
				p += Vector3(randf_range(-0.2, 0.2) + side * randf_range(0.5, 1.0), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2) + side * randf_range(0.5, 1.0))
			jit.append(p)
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = (cam.global_position - jit[0]).normalized() if cam else Vector3.UP
	# the sheath fades from 0.85 and the core from 1.0, each on a quadratic ease-in, as their tweens did
	_bolts.append({"sheath": _ribbon_tris(jit, 0.36, to_cam), "core": _ribbon_tris(jit, 0.12, to_cam), "color": color, "t": 0.0})
	_live += 1
	# into the meshes now, so the strike shows this frame (a node added mid-frame did)
	_draw_bolts(0.0)
	if want_lights():
		var glow := OmniLight3D.new()
		glow.light_color = color
		glow.omni_range = 6.0
		glow.light_energy = 3.0
		glow.position = points[1]
		add_child(glow)
		var tw := create_tween()
		tw.tween_interval(0.32)
		tw.tween_property(glow, "light_energy", 0.0, 0.18)
		tw.tween_callback(func(): glow.queue_free())
	# a flash and sparks where it lands, a spark at the source
	_emit(points[0], Vector3.ZERO, 0.14, 0.25, 0.5, 1.0, 0.0, Color(1.0, 1.0, 1.0))
	for k in range(1, points.size()):
		_emit(points[k], Vector3.ZERO, 0.2, 0.35, 0.9, 1.0, 0.0, Color(1.0, 1.0, 1.0))
		_emit(points[k], Vector3.ZERO, 0.28, 0.6, 1.4, 0.6, 0.0, color)
		for s in range(4):
			_emit(points[k], Vector3(randf_range(-3, 3), randf_range(1.5, 4.5), randf_range(-3, 3)), 0.4, 0.16, 0.05, 1.0, 0.0, Color(0.75, 0.88, 1.0), 9.0)


## The same ribbon as triangles (two per step), so many bolts can share one mesh: the strip's own triangles, in order.
func _ribbon_tris(pts: Array, width: float, to_cam: Vector3) -> PackedVector3Array:
	var edge := PackedVector3Array()
	for k in range(pts.size()):
		var p: Vector3 = pts[k]
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(to_cam).normalized() * width * 0.5
		var taper := 1.0 if (k > 0 and k < pts.size() - 1) else 0.35
		edge.append(p - side * taper)
		edge.append(p + side * taper)
	var tris := PackedVector3Array()
	for k in range(edge.size() - 2):
		tris.append(edge[k])
		tris.append(edge[k + 1])
		tris.append(edge[k + 2])
	return tris


## Every live bolt into the two meshes, at this moment's alpha; the finished ones go.
func _draw_bolts(delta: float) -> void:
	if _bolts.is_empty():
		if _bolts_drawn:
			_sheath_mesh.clear_surfaces()
			_core_mesh.clear_surfaces()
			_bolts_drawn = false
		return
	_sheath_mesh.clear_surfaces()
	_core_mesh.clear_surfaces()
	var keep: Array = []
	for b in _bolts:
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) >= SHEATH_LIFE:
			_live -= 1
			continue
		keep.append(b)
	_bolts = keep
	if _bolts.is_empty():
		_bolts_drawn = false
		return
	_sheath_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in _bolts:
		var f: float = float(b["t"]) / SHEATH_LIFE
		var c: Color = b["color"]
		_sheath_mesh.surface_set_color(Color(c.r, c.g, c.b, 0.85 * (1.0 - f * f)))
		for v in (b["sheath"] as PackedVector3Array):
			_sheath_mesh.surface_add_vertex(v)
	_sheath_mesh.surface_end()
	var any_core := false
	for b in _bolts:
		if float(b["t"]) < CORE_LIFE:
			if not any_core:
				_core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				any_core = true
			var g: float = float(b["t"]) / CORE_LIFE
			_core_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0 - g * g))
			for v in (b["core"] as PackedVector3Array):
				_core_mesh.surface_add_vertex(v)
	if any_core:
		_core_mesh.surface_end()
	_bolts_drawn = true


## A camera-facing ribbon along `pts`, `width` metres wide.
func _ribbon(pts: Array, width: float, to_cam: Vector3) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(pts.size()):
		var p: Vector3 = pts[k]
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(to_cam).normalized() * width * 0.5
		# thinner towards the ends
		var taper := 1.0 if (k > 0 and k < pts.size() - 1) else 0.35
		st.add_vertex(p - side * taper)
		st.add_vertex(p + side * taper)
	return st.commit()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_draw_bolts(delta)
	var i := 0
	var ns := 0
	var nb := 0
	var nf := 0
	while i < _n:
		_age[i] += delta
		if _age[i] >= _life[i]:
			# swap-remove
			_n -= 1
			if i != _n:
				_pos[i] = _pos[_n]; _vel[i] = _vel[_n]; _age[i] = _age[_n]; _life[i] = _life[_n]
				_s0[i] = _s0[_n]; _s1[i] = _s1[_n]; _a0[i] = _a0[_n]; _a1[i] = _a1[_n]; _grav[i] = _grav[_n]
				_col[i] = _col[_n]; _shard[i] = _shard[_n]; _seed[i] = _seed[_n]
			continue
		_vel[i].y -= _grav[i] * delta
		_pos[i] += _vel[i] * delta
		var f: float = _age[i] / _life[i]
		# ease-out on growth so bursts snap open, linear fade
		var e: float = 1.0 - (1.0 - f) * (1.0 - f)
		var s: float = lerpf(_s0[i], _s1[i], e)
		var c := _col[i]
		c.a = lerpf(_a0[i], _a1[i], f)
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), _pos[i])
		if _shard[i] == 1:
			xf.basis = xf.basis.rotated(Vector3(0.3, 1, 0.2).normalized(), _age[i] * 9.0)
			_box_mm.set_instance_transform(nb, xf)
			_box_mm.set_instance_color(nb, c)
			nb += 1
		elif _shard[i] == 2:
			# a flame is taller than it is wide; the shader faces it to the camera and eats it away by its age
			_flame_mm.set_instance_transform(nf, Transform3D(Basis().scaled(Vector3(s * 0.75, s, s)), _pos[i]))
			_flame_mm.set_instance_color(nf, c)
			_flame_mm.set_instance_custom_data(nf, Color(f, _seed[i], 0.0, 0.0))
			nf += 1
		else:
			_sph_mm.set_instance_transform(ns, xf)
			_sph_mm.set_instance_color(ns, c)
			ns += 1
		i += 1
	_sph_mm.visible_instance_count = ns
	_box_mm.visible_instance_count = nb
	_flame_mm.visible_instance_count = nf
	Perf.add("fx", t0)
