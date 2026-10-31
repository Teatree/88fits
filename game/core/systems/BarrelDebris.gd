## A smashed barrel coming apart (Garry, 2026-10-31: "the breaking isn't clear. It looks like I am just picking the barrels
## up. Let's make the break more obvious looking. Complete with some debris that lingers for a bit"). The barrel's own
## painting is cut where it stood (core/shaders/barrel_piece.gdshader: each piece shows its own rectangle of the picture,
## its edges splintered, facing the camera like the barrel did): the bottom STUMP stays on its spot with a jolt and a tilt,
## the lid and COLS staves above it burst outward and away from the hero, spin, fall, bounce once or twice and settle
## lying on their long side; all of it lies there LINGER seconds and dissolves over FADE.
## One MultiMesh a barrel kind (its picture), a ring of POOL pieces each: a new barrel takes the oldest pieces when the ring
## is full. Looks only: its own dice, nothing a rule reads, nothing in the run sim's fast mode.
class_name BarrelDebris
extends Node3D

const POOL := 72
const COLS := 4
## flying pieces are drawn this much bigger than their cut, so the burst reads from the camera's height
const GROW := 1.15
## the lid: the top LID of the painted barrel (its rim and top), one piece; the stump: its bottom STUMP, which stays
const LID := 0.26
const STUMP := 0.34
const GRAVITY := 17.0
const SPEED := Vector2(1.3, 2.8)     # outward, m/s
const LIFT := Vector2(2.8, 4.6)      # upward, m/s
const AWAY := 1.2                    # extra push away from the hero, m/s
const SPIN := 9.0                    # rad/s at most
const BOUNCE := 0.32
const LINGER := 6.0
const FADE := 0.9
## each painting's barrel inside its square picture (u0, v0, u1, v1; the pixels' bounding box of barrel_exp.png 287 px,
## barrel_coins.png 311 px, barrel_powerup.png 305 px)
const BOX := [Vector4(46.0 / 287.0, 6.0 / 287.0, 241.0 / 287.0, 285.0 / 287.0),
	Vector4(39.0 / 311.0, 6.0 / 311.0, 272.0 / 311.0, 309.0 / 311.0),
	Vector4(44.0 / 305.0, 6.0 / 305.0, 261.0 / 305.0, 303.0 / 305.0)]

var game: Node
var map: MapBase
var _mm: Array = []          # MultiMesh a kind
var _head := PackedInt32Array([0, 0, 0])
# per piece (kind * POOL + slot)
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _ang := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _size := PackedVector2Array()
var _age := PackedFloat32Array()
var _rest := PackedByteArray()   # 0 flying, 1 settling on the ground, 2 lying
var _target := PackedFloat32Array()
var _cut := PackedColorArray()   # which edges are cuts (barrel_piece.gdshader reads COLOR.rgb)
var _live := PackedByteArray()
var _rng := RandomNumberGenerator.new()
var _n_live := 0


func setup(g: Node, m: MapBase, sprites: Array) -> void:
	game = g
	map = m
	_rng.randomize()
	var total := POOL * sprites.size()
	_pos.resize(total); _vel.resize(total); _ang.resize(total); _spin.resize(total); _size.resize(total)
	_age.resize(total); _rest.resize(total); _target.resize(total); _live.resize(total); _cut.resize(total)
	var shader: Shader = load("res://core/shaders/barrel_piece.gdshader")
	for k in sprites.size():
		if not ResourceLoader.exists(sprites[k]):
			_mm.append(null)
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("sprite", load(sprites[k]))
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		# the Compatibility renderer multiplies by the custom data without instance colours (CLAUDE.md, pass 115)
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = POOL
		mm.visible_instance_count = POOL
		for s in POOL:
			mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
			mm.set_instance_color(s, Color.WHITE)
			mm.set_instance_custom_data(s, Color(0, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		SceneryStencil.mark_tree(mmi, SceneryStencil.STRUCTURE)
		add_child(mmi)
		_mm.append(mm)


## Barrel kind `kind` (0 exp, 1 coins, 2 powerup), drawn `quad_m` metres tall with its foot at `at`, bursts; `from` is
## where the hero stood (the pieces fly away from him). Returns how many pieces it made.
func burst(kind: int, at: Vector3, quad_m: float, from: Vector3) -> int:
	if Run.sim_mode or kind < 0 or kind >= _mm.size() or _mm[kind] == null:
		return 0
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var right := Vector3.RIGHT
	var up := Vector3(0, 0.69, 0.72)
	if cam != null:
		right = cam.global_transform.basis.x.normalized()
		up = cam.global_transform.basis.y.normalized()
	var away := Vector3(at.x - from.x, 0.0, at.z - from.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
	var box: Vector4 = BOX[kind]
	var rects: Array = []
	var lid_v := box.y + (box.w - box.y) * LID
	var stump_v := box.w - (box.w - box.y) * STUMP * _rng.randf_range(0.85, 1.1)
	# the stump first (it stays), then the lid, then the staves between, their cuts a little uneven
	rects.append(Vector4(box.x, stump_v, box.z, box.w))
	rects.append(Vector4(box.x, box.y, box.z, lid_v))
	var us := [box.x]
	for c in range(1, COLS):
		us.append(lerpf(box.x, box.z, (float(c) + _rng.randf_range(-0.15, 0.15)) / COLS))
	us.append(box.z)
	for c in COLS:
		rects.append(Vector4(us[c], lid_v, us[c + 1], stump_v))
	var mm: MultiMesh = _mm[kind]
	for rect: Vector4 in rects:
		var slot: int = _head[kind]
		_head[kind] = (slot + 1) % POOL
		var i := kind * POOL + slot
		var uc := (rect.x + rect.z) * 0.5
		var vc := (rect.y + rect.w) * 0.5
		var p := at + right * (uc - 0.5) * quad_m + up * (1.0 - vc) * quad_m
		var out := right * (uc - 0.5) + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3(1, 0, 0)
		var v := out * _rng.randf_range(SPEED.x, SPEED.y) + away * AWAY
		v.y = _rng.randf_range(LIFT.x, LIFT.y) * (1.15 - vc * 0.5)
		var stump: bool = rects.find(rect) == 0
		if stump:
			v = away * 0.25 + Vector3(0, 1.4, 0)
		if _live[i] == 0:
			_n_live += 1
		_live[i] = 1
		_pos[i] = p
		_vel[i] = v
		_ang[i] = 0.0
		_spin[i] = _rng.randf_range(-1.2, 1.2) if stump else _rng.randf_range(-SPIN, SPIN)
		_size[i] = Vector2((rect.z - rect.x) * quad_m, (rect.w - rect.y) * quad_m) * (1.0 if stump else GROW)
		_age[i] = 0.0
		_rest[i] = 0
		mm.set_instance_custom_data(slot, Color(rect.x, rect.y, rect.z, rect.w))
		# the cuts: a stave's top and bottom (and its sides between staves), the lid's bottom, the stump's top
		var top_cut := rect.y > box.y + 0.001
		var bottom_cut := rect.w < box.w - 0.001
		var side_cut := not stump and rect.y > box.y + 0.001
		_cut[i] = Color(1.0 if top_cut else 0.0, 1.0 if bottom_cut else 0.0, 1.0 if side_cut else 0.0, 1.0)
		_draw(kind, slot)
	return rects.size()


func _ground(p: Vector3) -> float:
	return map.height_at(p.x, p.z) if map != null else 0.0


## The angle nearest `a` at which the piece's long side lies flat (a stave on its side, the lid's halves as they are).
func _lying(a: float, size: Vector2) -> float:
	var base := PI * 0.5 if size.y > size.x else 0.0
	return base + roundf((a - base) / PI) * PI


func _process(delta: float) -> void:
	delta = Lockstep.dt(delta)
	if _n_live == 0 or Run.sim_mode or (game != null and bool(game.get("paused"))):
		return
	for k in _mm.size():
		if _mm[k] == null:
			continue
		for s in POOL:
			var i := k * POOL + s
			if _live[i] == 0:
				continue
			_step(i, delta)
			if _live[i] == 0:
				_n_live -= 1
				(_mm[k] as MultiMesh).set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
				continue
			_draw(k, s)


func _step(i: int, delta: float) -> void:
	_age[i] += delta
	var sz := _size[i]
	if _rest[i] < 2:
		var v := _vel[i]
		v.y -= GRAVITY * delta
		var p := _pos[i] + v * delta
		_ang[i] += _spin[i] * delta
		# a piece rests on the sand by about half its short side (the camera looks down at 46 degrees)
		var floor_y := _ground(p) + minf(sz.x, sz.y) * 0.4
		if p.y <= floor_y:
			p.y = floor_y
			if absf(v.y) > 1.6:
				v.y = -v.y * BOUNCE
				v.x *= 0.55
				v.z *= 0.55
				_spin[i] *= 0.5
				_rest[i] = 1
			else:
				v = Vector3.ZERO
				_rest[i] = 2
				_target[i] = _lying(_ang[i], sz)
		_vel[i] = v
		_pos[i] = p
	else:
		# it rolls over onto its long side
		_ang[i] = lerpf(_ang[i], _target[i], minf(1.0, delta * 12.0))
	if _age[i] >= LINGER + FADE:
		_live[i] = 0


func _draw(k: int, s: int) -> void:
	var i := k * POOL + s
	var sz := _size[i]
	var a := _ang[i]
	# column 0 = (cos a, sin a) * width, column 1's length = height (barrel_piece.gdshader reads them as such)
	var b := Basis(Vector3(cos(a) * sz.x, sin(a) * sz.x, 0.0), Vector3(0.0, sz.y, 0.0), Vector3(0, 0, 1))
	var mm: MultiMesh = _mm[k]
	mm.set_instance_transform(s, Transform3D(b, _pos[i]))
	var solid := 1.0 - clampf((_age[i] - LINGER) / FADE, 0.0, 1.0)
	var cut := _cut[i]
	mm.set_instance_color(s, Color(cut.r, cut.g, cut.b, solid))


## Pieces flying or lying now (tests).
func live_count() -> int:
	return _n_live
