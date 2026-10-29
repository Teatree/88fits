## The shots of the custom boss attacks (pass 72, lane BOSS; content/boss_attacks, BossAttackDef): one MultiMesh per
## look and colour, filled afresh every tick by EnemyManager's custom-attack runner (begin(), put() per shot, finish()),
## so the runner owns every position and clock and this node only draws. The looks are the game's hostile shots built
## the same way (Game.gd's spike, spit, pellet, shard) plus a rock and a ball of fire, in the attack's own colour: the
## base colour darkened for the body and the colour itself glowing (`glow`).
class_name BossAttackFx
extends Node3D

## look|tint|glow -> {"mm": MultiMesh, "mmi": MultiMeshInstance3D, "n": instances written this tick, "xf": Array}
var _pools: Dictionary = {}
var drawn := 0   # instances drawn by the last finish() (tests)

## Pass 113 (lane BOSS): the bullet-heaven looks are paintings drawn in code (core/shaders/boss_bullet.gdshader: a thick
## ink outline, the trail behind along the flight, stencil 3 so no stage filter dims them), one MultiMesh an attack whose
## buffer the pattern runner fills in one go (bb_draw: 16 floats a bullet, the transform then INSTANCE_CUSTOM). The body's
## radius in metres at size 1 by look; the shader's look number.
const BILLBOARD_LOOKS := ["burning_tumbleweed", "venom_blob", "brand_fireball"]
const BB_RADIUS := {"burning_tumbleweed": 0.34, "venom_blob": 0.5, "brand_fireball": 0.4}
const BB_SHADER := preload("res://core/shaders/boss_bullet.gdshader")
## floats a bullet in the buffer: the 3 x 4 transform, then the custom data (no colour)
const BB_STRIDE := 16
## key -> {"mm": MultiMesh, "mmi": MultiMeshInstance3D, "mat": ShaderMaterial}
var _bb: Dictionary = {}
## bullets drawn by the last bb_draw of each key (tests)
var bb_drawn: Dictionary = {}
## the map's height grid for the bullets' shader (set_ground; Telegraphs' texture when the game has one)
var _ground: Dictionary = {}


static func is_billboard(look: String) -> bool:
	return BILLBOARD_LOOKS.has(look)


## A billboard look's body radius at size 1 (m).
static func bb_radius(look: String) -> float:
	return float(BB_RADIUS.get(look, 0.4))


## The map's height grid for the bullets (Telegraphs' texture and numbers); without it a bullet's origin y is its height.
func set_ground(tex: Texture2D, grid_n: int, half_size: float, resolution: float) -> void:
	_ground = {"tex": tex, "grid_n": grid_n, "half": half_size, "res": resolution}
	for key in _bb:
		_ground_to((_bb[key] as Dictionary)["mat"])


func has_ground() -> bool:
	return not _ground.is_empty() and int(_ground.get("grid_n", 0)) >= 2 and _ground.get("tex") != null


func _ground_to(mat: ShaderMaterial) -> void:
	if not has_ground():
		mat.set_shader_parameter("grid_n", 0)
		return
	mat.set_shader_parameter("heights", _ground["tex"])
	mat.set_shader_parameter("grid_n", int(_ground["grid_n"]))
	mat.set_shader_parameter("half_size", float(_ground["half"]))
	mat.set_shader_parameter("resolution", float(_ground["res"]))


## The bullets of one attack this tick: `buf` holds BB_STRIDE floats a bullet (its size / BB_STRIDE is the pool's
## capacity: the runner grows it), the first `n` drawn. `key` names the attack's pool (its look, colour and glow).
func bb_draw(key: String, look: String, tint: Color, glow: float, wobble: float, trail: bool, buf: PackedFloat32Array, n: int) -> void:
	var p: Dictionary = _bb.get(key, {})
	if p.is_empty():
		p = _make_bb(look, tint, glow, wobble, trail)
		_bb[key] = p
	var mm: MultiMesh = p["mm"]
	var cap := int(float(buf.size()) / float(BB_STRIDE))
	if mm.instance_count != cap:
		mm.instance_count = cap
	if cap > 0:
		mm.buffer = buf
	mm.visible_instance_count = clampi(n, 0, cap)
	bb_drawn[key] = clampi(n, 0, cap)


## Nothing more of that attack's bullets drawn.
func bb_clear(key: String) -> void:
	var p: Dictionary = _bb.get(key, {})
	if not p.is_empty():
		(p["mm"] as MultiMesh).visible_instance_count = 0
	bb_drawn[key] = 0


func _make_bb(look: String, tint: Color, glow: float, wobble: float, trail: bool) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	mm.mesh = q
	mm.instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = BB_SHADER
	mat.set_shader_parameter("look", maxi(BILLBOARD_LOOKS.find(look), 0))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("glow", glow)
	mat.set_shader_parameter("wobble", wobble)
	mat.set_shader_parameter("trail", 1.0 if trail else 0.0)
	_ground_to(mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bullets_" + look
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))
	add_child(mmi)
	return {"mm": mm, "mmi": mmi, "mat": mat}


func begin() -> void:
	for key in _pools:
		(_pools[key] as Dictionary)["n"] = 0
		((_pools[key] as Dictionary)["xf"] as Array).clear()


## The pool a look in a colour draws from (the runner keeps it with its shots: no string built per shot per tick).
static func pool_key(look: String, tint: Color, glow: float) -> String:
	return "%s|%s|%.2f" % [look, tint.to_html(false), glow]


## One shot of `look` in `tint` (glowing `glow`) at `xf` (its basis carries its turn and size; -Z is its point); `key` is
## pool_key(look, tint, glow).
func put(key: String, look: String, tint: Color, glow: float, xf: Transform3D) -> void:
	if not _pools.has(key):
		_pools[key] = _make_pool(look, tint, glow)
	var p: Dictionary = _pools[key]
	(p["xf"] as Array).append(xf)


func finish() -> void:
	drawn = 0
	for key in _pools:
		var p: Dictionary = _pools[key]
		var xfs: Array = p["xf"]
		var mm: MultiMesh = p["mm"]
		if mm.instance_count < xfs.size():
			mm.instance_count = maxi(xfs.size(), mm.instance_count * 2)
		mm.visible_instance_count = xfs.size()
		for k in range(xfs.size()):
			mm.set_instance_transform(k, xfs[k])
		drawn += xfs.size()


func _make_pool(look: String, tint: Color, glow: float) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = look_mesh(look)
	mm.instance_count = 64
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = look_material(look, tint, glow)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# drawn wherever they are: the pool's box would otherwise be the first tick's
	mmi.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))
	add_child(mmi)
	return {"mm": mm, "mmi": mmi, "n": 0, "xf": []}


## The mesh of a look, pointing down -Z (the way a shot's basis points), about as big as the game's own shot.
static func look_mesh(look: String) -> Mesh:
	match look:
		"spike":
			# the centipede's barb (Game._spike_mesh): seven sides tapering to a point
			return _cone(7, 0.13, 0.34, -0.44)
		"shard":
			return _cone(4, 0.16, 0.3, -0.5)
		"pellet":
			return _ball(0.13, 6, 3)
		"rock":
			return _ball(0.3, 5, 3)
		"fire":
			return _ball(0.26, 8, 4)
		_:
			# "spit": the Spit Cactus's ball
			return _ball(0.28, 8, 4)


static func _ball(r: float, segs: int, rings: int) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


## A barb: `segs` sides of radius `r` at z = `back`, closing to a point at z = `tip` (clockwise fronts, as Godot wants).
static func _cone(segs: int, r: float, back: float, tip: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(segs):
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, back)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, back)
		for v in [p0, p1, Vector3(0, 0, tip)]:
			st.add_vertex(v)
		for v in [Vector3(0, 0, back), p1, p0]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func look_material(look: String, tint: Color, glow: float) -> Material:
	var m := StandardMaterial3D.new()
	if look == "fire":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = tint.lightened(0.35)
		return m
	# the body a darker shade of the colour, the colour itself glowing (a barb reads dark with a hot edge, as the game's)
	m.albedo_color = tint.darkened(0.45 if look == "spike" or look == "shard" else 0.15)
	m.metallic = 0.3 if look == "spike" or look == "pellet" else 0.0
	m.roughness = 0.5
	m.emission_enabled = glow > 0.0
	m.emission = tint
	m.emission_energy_multiplier = maxf(glow, 0.0)
	return m
