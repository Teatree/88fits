## A tornado's look (pass 113, lane TWISTER; Garry: "Tornadoes still don't look like tornadoes and are quite confusing").
## Reusable: the map's dust devils (world/features/DustDevil.gd) and the Tumbleweed King's Royal Dust Devil shell (lane
## BOSS) both wear one. Nothing in it touches the game: it only draws.
##
## The API (fixed for both users):
##   height, radius_bottom, radius_top, color (the dust's colour), spin (turns a second): set before add_child or any
##     time after (the shaders take the new numbers on the next frame);
##   set_strength(f) 0..1: 0 draws nothing, 1 the full tornado. Tween it to form and to collapse: rising, the dust skirt
##     comes first (0 to 0.35) and the funnel grows up out of it (0.2 to 1); falling, the funnel ropes out (narrower, holes
##     opening in the dust) and the skirt goes last;
##   burst(): the collapse's puff (the skirt thrown out and gone, the debris flung out and dropped), about a second;
##     drawn even once the strength is 0.
## Optional knobs: opacity (0.5..1, how solid the funnel is), skirt_radius (the bank of dust round the foot; 0 = 2.6 x
## radius_bottom), lean (the top's share of
## the height it leans, wandering slowly, and against the node's own motion when its parent moves), snake (the share of
## the height its middle waves), debris (how many bits ride it, set before add_child), debris_size.
##
## What draws (four draw calls, nothing rebuilt per frame: every shape is made in the shaders from a few numbers):
##   Funnel  one tube mesh (core/shaders/tornado_funnel.gdshader, layer 0): helical bands of dust climbing round it (dark
##           bands, the dust's colour, pale streaks), shaded round with an inked edge, its far wall in shadow seen
##           through the open top, a hard painted edge, the top breaking up along the bands into the air;
##   Wisps   the same mesh again (layer 1), a looser shell of pale streaks turning faster;
##   Skirt   a ring mesh raised into a churning bank of dust round the foot (tornado_skirt.gdshader);
##   Debris  one MultiMesh of `debris` quads (tornado_debris.gdshader): clods, twigs, chips and a little tumbleweed
##           riding round and up it, solid (they write depth) so the dust sorts round them.
## Every material sits before the stage's filter (StageLook.PRIORITY): an evening or a blood moon tints it like the sand
## it stands on. Only the dense dust writes depth, so the ground marks, shadows and gems drawn after the filter do not show
## through it; the funnel writes the scenery's stencil (4), so a creature inside or behind it (the King in his shell, a
## creature it spins) shows its outline through the dust as one behind a cactus does. Its clock is its own (`_t`, advanced in _process): it stops with the game's pause and follows the arena's
## speed. The meshes are made once and shared by every tornado.
class_name TornadoFx
extends Node3D

const FUNNEL_SHADER := preload("res://core/shaders/tornado_funnel.gdshader")
const SKIRT_SHADER := preload("res://core/shaders/tornado_skirt.gdshader")
const DEBRIS_SHADER := preload("res://core/shaders/tornado_debris.gdshader")
const NOISE := preload("res://art/fx/fire_noise.png")
## Before the stage's filter (-7), after the water (-10): the funnel, the wisps and the skirt sort among themselves by
## SORT (the skirt first, then the funnel, the wisps last).
const PRIORITY := StageLook.PRIORITY - 1
const SORT := {"Skirt": 0.0, "Funnel": 0.5, "Wisps": 1.0}
## The mesh's rings up the funnel and segments round it.
const RINGS := 22
const SEGMENTS := 28
const SKIRT_ROWS := 6
## Seconds the collapse's puff takes.
const BURST_SECONDS := 1.0
## Strength shares: the skirt grows over [0, SKIRT_TO], the funnel rises over [FUNNEL_FROM, 1]; falling, the funnel thins
## over [0, THIN_FROM].
const SKIRT_TO := 0.35
const FUNNEL_FROM := 0.2
const THIN_FROM := 0.85
## Metres of lean per m/s the node moves (the top trails its motion), at most LEAN_MAX x height.
const LEAN_PER_SPEED := 0.35
const LEAN_MAX := 0.25

@export var height := 7.0:
	set(v):
		height = maxf(v, 0.1)
		_dirty = true
@export var radius_bottom := 0.6:
	set(v):
		radius_bottom = maxf(v, 0.01)
		_dirty = true
@export var radius_top := 2.1:
	set(v):
		radius_top = maxf(v, 0.01)
		_dirty = true
@export var color := Color(0.7, 0.52, 0.34):
	set(v):
		color = v
		_dirty = true
@export var spin := 0.9:
	set(v):
		spin = v
		_dirty = true
@export var skirt_radius := 0.0:
	set(v):
		skirt_radius = maxf(v, 0.0)
		_dirty = true
## How solid the funnel is (0.5..1; 0.94 default): lower lets what stands inside it show through more (a boss).
@export var opacity := 0.94:
	set(v):
		opacity = clampf(v, 0.5, 1.0)
		_dirty = true
## How solid the dust skirt round its foot is (0.4..1; 0.92 default, pass 113's). Pass 115 (lane POLISH): the map's dust
## devils thin it with their funnel (DustDevil: opacity x SKIRT_SHARE).
@export var skirt_opacity := 0.92:
	set(v):
		skirt_opacity = clampf(v, 0.4, 1.0)
		_dirty = true
@export var lean := 0.14
@export var snake := 0.085:
	set(v):
		snake = v
		_dirty = true
@export var debris := 28
@export var debris_size := 1.0:
	set(v):
		debris_size = v
		_dirty = true

## 0..1 as last set (set_strength).
var strength := 1.0
## The shares the shaders draw: the funnel risen (grow), its thickness (thin: 1 full, toward 0 roping out), the skirt.
var grow := 1.0
var thin := 1.0
var skirt_amount := 1.0
var collapsing := false
## The collapse's puff: 0 = none, else its progress 0..1.
var burst_t := 0.0

var _t := 0.0
var _dirty := true
var _built := false
var _funnel: MeshInstance3D
var _wisps: MeshInstance3D
var _skirt: MeshInstance3D
var _debris: MultiMeshInstance3D
var _mats: Array = []
var _last_pos := Vector3.INF
var _vel := Vector3.ZERO
var _lean := Vector2.ZERO
var _wander := 0.0

static var _tube: ArrayMesh
static var _ring: ArrayMesh
static var _quad: QuadMesh


func _ready() -> void:
	_build()
	_wander = randf() * 100.0
	_apply_all()


## 0 nothing, 1 the full tornado (see the header): rising forms it from the ground up, falling thins it away.
func set_strength(f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	if f < strength - 0.0001:
		collapsing = true
	elif f > strength + 0.0001:
		collapsing = false
	strength = f
	skirt_amount = _ease(f / SKIRT_TO)
	if f <= 0.0:
		# gone: the next rise forms it afresh
		grow = 0.0
		thin = 1.0
		collapsing = false
	elif collapsing:
		thin = minf(thin, _ease(f / THIN_FROM))
	else:
		grow = maxf(grow, _ease((f - FUNNEL_FROM) / (1.0 - FUNNEL_FROM)))
		thin = maxf(thin, _ease(f / THIN_FROM)) if grow >= 1.0 else 1.0
	_show()
	_apply_live()


## The collapse's puff (BURST_SECONDS): the skirt thrown out and gone, the debris flung out and dropped.
func burst() -> void:
	burst_t = 0.0001
	_show()
	_apply_live()


## Whether anything is drawn now (a strength above 0, or the puff still going).
func drawing() -> bool:
	return strength > 0.0 or burst_t > 0.0


## Seconds its clock has run (the shaders' `t`).
func clock() -> float:
	return _t


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt): the camera and what is on screen follow it
	delta = Lockstep.dt(delta)
	if not _built:
		return
	var t0 := Time.get_ticks_usec()
	_t += delta
	if burst_t > 0.0:
		burst_t += delta / BURST_SECONDS
		if burst_t >= 1.0:
			burst_t = 0.0
			_show()
	# the top trails the node's own motion (under a moving parent too) and wanders a little
	var gp := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var v := (gp - _last_pos) / delta
		if v.length() < 40.0:
			_vel = _vel.lerp(v, clampf(delta * 3.0, 0.0, 1.0))
	_last_pos = gp
	var back := global_transform.basis.inverse() * (-_vel * LEAN_PER_SPEED)
	var idle := Vector2(sin(_t * 0.31 + _wander), cos(_t * 0.23 + _wander * 1.7)) * lean * height
	var want := Vector2(back.x, back.z) + idle
	var most := LEAN_MAX * height
	if want.length() > most:
		want = want.normalized() * most
	_lean = want
	if _dirty:
		_apply_all()
	else:
		_apply_live()
	Perf.add("tornado", t0)


func _show() -> void:
	visible = drawing()


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ---------------------------------------------------------------- the parts

func _build() -> void:
	if _built:
		return
	_built = true
	_make_meshes()
	_skirt = _part("Skirt", _ring, SKIRT_SHADER)
	_funnel = _part("Funnel", _tube, FUNNEL_SHADER)
	_wisps = _part("Wisps", _tube, FUNNEL_SHADER)
	(_wisps.material_override as ShaderMaterial).set_shader_parameter("layer", 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad
	var n := maxi(debris, 0)
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	for k in range(n):
		mm.set_instance_transform(k, Transform3D.IDENTITY)
		# a kind a quarter each, one tumbleweed in eight
		var kind := 3 if k % 8 == 7 else k % 3
		mm.set_instance_custom_data(k, Color(rng.randf(), float(k) / maxf(float(n), 1.0), rng.randf(), (float(kind) + rng.randf() * 0.95) / 4.0))
	_debris = MultiMeshInstance3D.new()
	_debris.name = "Debris"
	_debris.multimesh = mm
	var dm := ShaderMaterial.new()
	dm.shader = DEBRIS_SHADER
	dm.render_priority = PRIORITY
	_debris.material_override = dm
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debris)
	_mats.append(dm)
	_show()


func _part(part_name: String, mesh: Mesh, shader: Shader) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = PRIORITY
	m.set_shader_parameter("noise_tex", NOISE)
	mi.material_override = m
	mi.sorting_offset = float(SORT.get(part_name, 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mats.append(m)
	return mi


## The tube (UV.x round, UV.y up; the outside wound clockwise, Godot's front) and the ring (UV.x round, UV.y out), made
## once and shared. Their vertices are a unit cylinder and a unit disc: the shaders place everything.
static func _make_meshes() -> void:
	if _tube == null:
		_tube = _grid_mesh(RINGS, func(u: float, v: float) -> Vector3: return Vector3(cos(u * TAU), v, sin(u * TAU)))
	if _ring == null:
		_ring = _grid_mesh(SKIRT_ROWS, func(u: float, v: float) -> Vector3: return Vector3(cos(u * TAU) * (0.3 + v), 0.0, sin(u * TAU) * (0.3 + v)))
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)


static func _grid_mesh(rows: int, at: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols := SEGMENTS + 1
	for j in range(rows + 1):
		var v := float(j) / float(rows)
		for i in range(cols):
			var u := float(i) / float(SEGMENTS)
			var p: Vector3 = at.call(u, v)
			verts.append(p)
			uvs.append(Vector2(u, v))
			normals.append(Vector3(cos(u * TAU), 0.0, sin(u * TAU)))
	for j in range(rows):
		for i in range(SEGMENTS):
			var a := j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ---------------------------------------------------------------- the numbers to the shaders

## Every number (the size, the colour, the spin changed) and the box the culling reads.
func _apply_all() -> void:
	if not _built:
		return
	_dirty = false
	var sr := skirt_radius if skirt_radius > 0.0 else radius_bottom * 2.6
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("spin", spin)
		m.set_shader_parameter("height", height)
		m.set_shader_parameter("r_bottom", radius_bottom)
		m.set_shader_parameter("r_top", radius_top)
		m.set_shader_parameter("snake", snake * height)
	(_funnel.material_override as ShaderMaterial).set_shader_parameter("alpha_max", opacity)
	(_wisps.material_override as ShaderMaterial).set_shader_parameter("alpha_max", opacity)
	var sm := _skirt.material_override as ShaderMaterial
	sm.set_shader_parameter("alpha_max", skirt_opacity)
	sm.set_shader_parameter("r_inner", radius_bottom * 0.55)
	sm.set_shader_parameter("r_outer", sr)
	sm.set_shader_parameter("bank", clampf(0.35 + radius_bottom * 0.6, 0.4, 1.6))
	(_debris.material_override as ShaderMaterial).set_shader_parameter("rise", 0.85 / maxf(height, 1.0))
	(_debris.material_override as ShaderMaterial).set_shader_parameter("size", debris_size * clampf(height / 6.5, 0.6, 1.6))
	# the culling box: the widest the flare, the lean, the snake, the wisps and a burst can reach
	var w := maxf(radius_top * 1.45, sr * 2.6) + (LEAN_MAX + snake) * height + 0.5
	var box := AABB(Vector3(-w, -0.5, -w), Vector3(w * 2.0, height * 1.15 + 1.0, w * 2.0))
	for gi: GeometryInstance3D in [_funnel, _wisps, _skirt, _debris]:
		gi.custom_aabb = box
	_apply_live()


## The numbers that change every frame: the clock, the strength's shares, the lean, the puff.
func _apply_live() -> void:
	if not _built:
		return
	var dm := _debris.material_override as ShaderMaterial
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("t", _t)
	for m: ShaderMaterial in [_funnel.material_override, _wisps.material_override, dm]:
		m.set_shader_parameter("grow", grow)
		m.set_shader_parameter("thin", thin)
		m.set_shader_parameter("lean", _lean)
	var sm := _skirt.material_override as ShaderMaterial
	# the puff throws the whole bank out, whatever the strength has fallen to
	sm.set_shader_parameter("amount", maxf(skirt_amount, 1.0 if burst_t > 0.0 else 0.0))
	sm.set_shader_parameter("burst", burst_t)
	dm.set_shader_parameter("amount", minf(grow, thin) if strength > 0.0 else 0.0)
	dm.set_shader_parameter("burst", burst_t)


# ---------------------------------------------------------------- tools

## A small one at full strength, for Warmup (its shaders compile under the spawn beam).
static func warm_instance() -> TornadoFx:
	var fx := TornadoFx.new()
	fx.name = "TornadoWarm"
	fx.height = 1.0
	fx.radius_bottom = 0.2
	fx.radius_top = 0.5
	fx.debris = 4
	return fx


## Every geometry it draws with (tests: the draw order before the stage's filter, nothing drawn at strength 0).
func parts() -> Array:
	return [_skirt, _funnel, _wisps, _debris] if _built else []
