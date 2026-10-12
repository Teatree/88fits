## The Salt weapon's patches on the ground (pass 69, Garry: "Leaves a white half transparent patch in hero's wake, which
## damages enemies as long as they are walking or standing in it"). The SaltShaker behaviour lays them and works out what
## they do; this keeps them and draws them: one MultiMesh of draped discs (core/shaders/salt_patch.gdshader: the terrain
## under them from the map's height grid, a lobed rim, grains of salt on a see-through base) and, for Hiwa Kai, one of
## little hard black crystals lying on them. Two draw calls however many patches lie.
##
## A patch fades in over FADE_IN seconds and out over its last FADE_OUT. At most `cap` patches lie at once: the one past
## the cap sends the oldest still whole into its fade (it is `dying`: it hurts nothing more and leaves in FADE_OUT).
class_name SaltPatches
extends Node3D

const FADE_IN := 0.25
const FADE_OUT := 0.6
const SEGMENTS := 40
const ROWS := 5

## {at: Vector3 (on the ground), r: float, life: float (seconds left), total: float, seed: float, dying: bool,
##  hero_in: bool (the hero stood inside it last frame: Salt Flats), crystals: Array of Transform3D (unit size, scaled
##  by the fade)}
var patches: Array = []
var cap := 40
var color := Color(1, 1, 1)
var alpha := 0.5
var crystal_color := Color(0.04, 0.04, 0.05)
## the ground under a point (map.height_at); 0 without a map (tests)
var height_fn: Callable = Callable()

var _mm: MultiMesh
var _mat: ShaderMaterial
var _cmm: MultiMesh
var _cmat: StandardMaterial3D
## the crystals are written again only when a patch came or went or one carrying crystals is fading (a few hundred
## still transforms are not rewritten every frame)
var _cdirty := true
static var _disc_mesh: Mesh
static var _crystal_mesh: Mesh


## `tg` is the game's Telegraphs (its height grid drapes the patches as it drapes the marks); null leaves them flat.
func setup(tg: Node, p_height: Callable, p_cap: int) -> void:
	height_fn = p_height
	cap = maxi(p_cap, 1)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://core/shaders/salt_patch.gdshader")
	# under the telegraphs' scorch marks and spills: salt is the floor's
	_mat.render_priority = -6
	if tg != null and tg.has_method("_ground_uniforms"):
		tg.call("_ground_uniforms", _mat)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _disc()
	_mm.instance_count = cap * 2
	_mm.visible_instance_count = 0
	_add_mmi(_mm, _mat, "SaltPatches")
	# black glass: a sharp highlight and a pale rim so the facets glint, a faint cool glow so the warm sun never turns
	# them brown
	_cmat = StandardMaterial3D.new()
	_cmat.albedo_color = crystal_color
	_cmat.roughness = 0.3
	_cmat.metallic = 0.0
	_cmat.metallic_specular = 0.45
	_cmat.rim_enabled = true
	_cmat.rim = 0.35
	_cmat.rim_tint = 0.0
	_cmat.emission_enabled = true
	_cmat.emission = Color(0.07, 0.08, 0.11)
	_cmat.emission_energy_multiplier = 1.0
	_cmm = MultiMesh.new()
	_cmm.transform_format = MultiMesh.TRANSFORM_3D
	_cmm.mesh = _crystal()
	_cmm.instance_count = 64
	_cmm.visible_instance_count = 0
	_add_mmi(_cmm, _cmat, "SaltCrystals")


func _add_mmi(mm: MultiMesh, mat: Material, nm: String) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


## The look: the salt's colour and alpha (Sea Salt pink, Hiwa Kai black) and the crystals' colour.
func set_look(col: Color, p_alpha: float, p_crystal: Color = Color(0.04, 0.04, 0.05)) -> void:
	color = col
	alpha = clampf(p_alpha, 0.0, 1.0)
	crystal_color = p_crystal
	if _cmat:
		_cmat.albedo_color = p_crystal


func ground_at(x: float, z: float) -> float:
	return float(height_fn.call(x, z)) if height_fn.is_valid() else 0.0


## A new patch of radius `r` at `at` (on the ground under it) for `seconds`, with `crystal_n` crystals strewn on it;
## `hero_pos` is where the hero stands (a patch laid round his feet counts him inside already: Salt Flats waits for him
## to walk out and back in). Past the cap, the oldest whole patch starts to fade. Returns the patch.
func add(at: Vector3, r: float, seconds: float, hero_pos: Vector3, crystal_n: int = 0) -> Dictionary:
	var p := Vector3(at.x, ground_at(at.x, at.z), at.z)
	var d := {"at": p, "r": r, "life": maxf(seconds, 0.05), "total": maxf(seconds, 0.05), "seed": randf(), "dying": false,
		"hero_in": _inside_xz(p, r, hero_pos), "crystals": []}
	for k in range(maxi(crystal_n, 0)):
		# strewn over the inner 85% of the patch, each turned and tipped its own way, a third of them bigger
		var a := randf() * TAU
		var rr := sqrt(randf()) * r * 0.85
		var cp := p + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		cp.y = ground_at(cp.x, cp.z) + 0.02
		var s := randf_range(0.7, 1.0) * (1.6 if k % 3 == 0 else 1.0)
		var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, randf_range(-0.5, 0.5))
		(d["crystals"] as Array).append(Transform3D(b.scaled(Vector3(s, s, s)), cp))
	patches.append(d)
	_cdirty = true
	# the cap: the oldest still whole fades out (it hurts nothing more)
	var over := live_count() - cap
	for q in patches:
		if over <= 0:
			break
		if not q["dying"]:
			q["dying"] = true
			q["life"] = minf(float(q["life"]), FADE_OUT)
			over -= 1
	return d


## The patches still whole (not fading out for the cap).
func live_count() -> int:
	var n := 0
	for q in patches:
		if not q["dying"]:
			n += 1
	return n


static func _inside_xz(c: Vector3, r: float, p: Vector3) -> bool:
	var dx := p.x - c.x
	var dz := p.z - c.z
	return dx * dx + dz * dz <= r * r


## Whether `p` stands in a patch that still works (not dying, not gone).
func contains(p: Vector3) -> bool:
	for q in patches:
		if not q["dying"] and _inside_xz(q["at"], float(q["r"]), p):
			return true
	return false


## Ages every patch and drops the gone ones.
func advance(delta: float) -> void:
	var keep: Array = []
	for q in patches:
		q["life"] = float(q["life"]) - delta
		if float(q["life"]) > 0.0:
			keep.append(q)
	if keep.size() != patches.size():
		_cdirty = true
	patches = keep


## A patch's fade now: in over FADE_IN, out over its last FADE_OUT.
static func fade_of(q: Dictionary) -> float:
	var age := float(q["total"]) - float(q["life"])
	return clampf(age / FADE_IN, 0.0, 1.0) * clampf(float(q["life"]) / FADE_OUT, 0.0, 1.0)


## Every patch and crystal into the MultiMeshes.
func draw() -> void:
	if _mm == null:
		return
	if patches.size() > _mm.instance_count:
		_mm.instance_count = patches.size() * 2
	var n := 0
	var nc := 0
	for q in patches:
		var f := fade_of(q)
		_mm.set_instance_transform(n, Transform3D(Basis(), q["at"]))
		_mm.set_instance_custom_data(n, Color(float(q["r"]) * (0.85 + 0.15 * minf(f * 2.0, 1.0)), float(q["seed"]), 0.0, 0.0))
		_mm.set_instance_color(n, Color(color.r, color.g, color.b, alpha * f))
		n += 1
		var k := (q["crystals"] as Array).size()
		nc += k
		if k > 0 and f < 1.0:
			_cdirty = true
	_mm.visible_instance_count = n
	if not _cdirty:
		return
	_cdirty = false
	if nc > _cmm.instance_count:
		_cmm.instance_count = nc * 2
	var c := 0
	for q in patches:
		var cr: Array = q["crystals"]
		if cr.is_empty():
			continue
		var f := fade_of(q)
		for xf: Transform3D in cr:
			_cmm.set_instance_transform(c, Transform3D(xf.basis.scaled(Vector3(f, f, f)), xf.origin))
			c += 1
	_cmm.visible_instance_count = c


## A unit disc in ROWS rings of SEGMENTS steps; UV.x runs centre to rim, UV.y round (the shader bends the rim and drapes
## it).
static func _disc() -> Mesh:
	if _disc_mesh:
		return _disc_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in range(ROWS):
		var f0 := float(q) / ROWS
		var f1 := float(q + 1) / ROWS
		for k in range(SEGMENTS):
			var u0 := float(k) / SEGMENTS
			var u1 := float(k + 1) / SEGMENTS
			for v: Vector2 in [Vector2(f0, u0), Vector2(f1, u0), Vector2(f0, u1), Vector2(f1, u0), Vector2(f1, u1), Vector2(f0, u1)]:
				st.set_uv(v)
				st.add_vertex(Vector3(cos(v.y * TAU) * v.x, 0.0, sin(v.y * TAU) * v.x))
	_disc_mesh = st.commit()
	return _disc_mesh


## A little hard crystal: a squat, uneven octahedron about 15 cm across and 15 high, its flat faces catching the light.
static func _crystal() -> Mesh:
	if _crystal_mesh:
		return _crystal_mesh
	var top := Vector3(0.015, 0.12, -0.008)
	var bot := Vector3(0.0, -0.03, 0.0)
	var ring := [Vector3(0.07, 0.03, 0.0), Vector3(0.0, 0.04, 0.062), Vector3(-0.078, 0.028, 0.0), Vector3(0.0, 0.034, -0.066)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(4):
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 4]
		# Godot's front faces are clockwise seen from outside
		for tri: Array in [[top, a, b], [bot, b, a]]:
			var n: Vector3 = ((tri[2] as Vector3) - (tri[0] as Vector3)).cross((tri[1] as Vector3) - (tri[0] as Vector3)).normalized()
			for v: Vector3 in tri:
				st.set_normal(n)
				st.add_vertex(v)
	_crystal_mesh = st.commit()
	return _crystal_mesh
