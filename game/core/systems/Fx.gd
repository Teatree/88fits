## Cheap visual effects. Every burst, puff, spark and flash is one instance in one of two pooled MultiMeshes
## (spheres with alpha, opaque shards), so a hundred deaths a minute cost two draw calls and no nodes.
## Lightning keeps a short-lived ImmediateMesh per strike (rare). Lights are skipped on phones.
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
var _shard := PackedByteArray()   # 1 = box shard pool, 0 = sphere pool
var _n := 0

var _sph_mm: MultiMesh
var _box_mm: MultiMesh
var _live := 0   # nodes still alive (lightning)
const MAX_LIVE := 40


## Whether short-lived point lights are worth it on this device (never on phones: every lit pixel pays for them).
static func want_lights() -> bool:
	return not OS.has_feature("mobile")


func _ready() -> void:
	_pos.resize(MAX_P); _vel.resize(MAX_P); _age.resize(MAX_P); _life.resize(MAX_P)
	_s0.resize(MAX_P); _s1.resize(MAX_P); _a0.resize(MAX_P); _a1.resize(MAX_P); _grav.resize(MAX_P)
	_col.resize(MAX_P); _shard.resize(MAX_P)
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 8
	s.rings = 4
	_sph_mm = _pool(s, true)
	var b := BoxMesh.new()
	b.size = Vector3(0.26, 0.26, 0.26)
	_box_mm = _pool(b, false)


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


func _emit(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, a0: float, a1: float, col: Color, grav := 0.0, shard := false) -> void:
	if _n >= MAX_P:
		return
	var i := _n
	_n += 1
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = s0; _s1[i] = s1; _a0[i] = a0; _a1[i] = a1; _grav[i] = grav
	_col[i] = col; _shard[i] = 1 if shard else 0


func burst(at: Vector3, color: Color, size: float = 1.0) -> void:
	# the coloured cloud that grows and fades, and a hot white core that pops first so the burst has a snap
	_emit(at, Vector3.ZERO, 0.34, 0.2, size * 2.2, 0.9, 0.0, color)
	_emit(at, Vector3.ZERO, 0.16, 0.1, size * 1.1, 0.95, 0.0, Color(1, 1, 1))


## A poison tick: two small green puffs drifting up, so the damage is seen.
func poison(at: Vector3) -> void:
	for k in range(2):
		var p := at + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
		_emit(p, Vector3(0, 2.2, 0), 0.5, 0.22, 0.55, 0.85, 0.0, Color(0.5, 1.0, 0.4))


## A fire tick: flames that lick up fast and shrink to embers, orange with a yellow heart.
func fire(at: Vector3, size: float = 1.0) -> void:
	for k in range(2):
		var p := at + Vector3(randf_range(-0.3, 0.3) * size, randf_range(0.0, 0.4) * size, randf_range(-0.2, 0.2) * size)
		var c := Color(1.0, 0.45 + randf() * 0.25, 0.08) if k == 0 else Color(1.0, 0.9, 0.4)
		_emit(p, Vector3(randf_range(-0.3, 0.3), randf_range(2.4, 3.4), randf_range(-0.3, 0.3)), 0.36, (0.55 if k == 0 else 0.35) * size, 0.08, 0.95, 0.0, c)


## Catching fire: a flare and a ring of sparks.
func ignite(at: Vector3, size: float = 1.0) -> void:
	_emit(at + Vector3(0, 0.4, 0), Vector3.ZERO, 0.22, 0.3, size * 1.6, 0.9, 0.0, Color(1.0, 0.6, 0.2))
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


func lightning(points: Array, color: Color = Color(0.6, 0.85, 1.0)) -> void:
	if points.size() < 2 or _live >= MAX_LIVE:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in range(points.size() - 1):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var segs := 5
		for s in range(segs + 1):
			var p := a.lerp(b, float(s) / segs)
			if s > 0 and s < segs:
				p += Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
			im.surface_add_vertex(p)
	im.surface_end()
	var m := MeshInstance3D.new()
	m.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	add_child(m)
	_live += 1
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	if want_lights():
		var glow := OmniLight3D.new()
		glow.light_color = color
		glow.omni_range = 6.0
		glow.light_energy = 3.0
		glow.position = points[1]
		add_child(glow)
		tw.tween_property(glow, "light_energy", 0.0, 0.18)
		tw.chain().tween_callback(func(): glow.queue_free())
	tw.chain().tween_callback(func(): m.queue_free(); _live -= 1)
	for k in range(points.size()):
		_emit(points[k], Vector3.ZERO, 0.14, 0.3, 0.9, 0.9, 0.0, color)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var i := 0
	var ns := 0
	var nb := 0
	while i < _n:
		_age[i] += delta
		if _age[i] >= _life[i]:
			# swap-remove
			_n -= 1
			if i != _n:
				_pos[i] = _pos[_n]; _vel[i] = _vel[_n]; _age[i] = _age[_n]; _life[i] = _life[_n]
				_s0[i] = _s0[_n]; _s1[i] = _s1[_n]; _a0[i] = _a0[_n]; _a1[i] = _a1[_n]; _grav[i] = _grav[_n]
				_col[i] = _col[_n]; _shard[i] = _shard[_n]
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
		else:
			_sph_mm.set_instance_transform(ns, xf)
			_sph_mm.set_instance_color(ns, c)
			ns += 1
		i += 1
	_sph_mm.visible_instance_count = ns
	_box_mm.visible_instance_count = nb
	Perf.add("fx", t0)
