## Ground markings: telegraph rings, filled discs, cones and lines that fade over their duration, blast rings that grow,
## and the spills, zones and scorch marks other systems keep on the ground. Since pass 33.8 none of them is a node or a
## mesh of its own: each is one instance in a MultiMesh of a ready-made shape (a ring band, a disc, a strip, a lobed
## spill), and core/shaders/ground_mark.gdshader lays it over the terrain vertex by vertex from the map's height grid, so
## dunes and the riverbed never cut through it. A blast ring used to be rebuilt from scratch twenty times a second while
## it grew; now it is stretched. One draw call per kind of mark, whatever lands. The game hands in `height_fn`
## (map.height_at) and calls set_ground(map) for the grid; the draped_* builders stay for things drawn once
## (structures).
class_name Telegraphs
extends Node3D

const LIFT := 0.1
const SEGMENTS := 64
const MODE_FADE := 0     # fades to half and blinks in its last 40%
const MODE_GROW := 1     # the same, and the ring grows from 40% to its full radius
const MODE_SCORCH := 2   # holds `hold` seconds, then fades out over the rest of `dur`
const MODE_HELD := 3     # its owner sets the alpha (set_alpha) and takes it away (release)
const MODE_WASH := 4     # sweeps out from the centre over the first half of `dur` and fades away smoothly, no blink
const MODE_RACE := 5     # a wave: a band a share of its radius wide races out from the centre with an ease-out, fading
## Draw order among the marks (all under whatever stands on the ground): scorch, spills, discs, lines, rings.
const PRIO_SCORCH := -5
const PRIO_SPILL := -4
const PRIO_DISC := -3
const PRIO_STRIP := -2
const PRIO_BAND := -1

var height_fn: Callable = Callable()
## live marks: {pool, at, col (linear rgb, a = base alpha), k (the shape's custom data), mode, t, dur, r, a, dead}
var _items: Array = []
var _held: Dictionary = {}     # id -> mark, for marks an owner keeps (spills, zones, billows)
var _next_id := 1
## pool key -> {"mm": MultiMesh, "n": instances written this frame, "mat": its material}
var _pools: Dictionary = {}
var _shader: Shader = preload("res://core/shaders/ground_mark.gdshader")
var _heights: ImageTexture
var _grid_n := 0
var _half := 70.0
var _res := 1.0
var _blob_mesh: Mesh


func _h(x: float, z: float) -> float:
	return float(height_fn.call(x, z)) if height_fn.is_valid() else 0.0


func _v(x: float, z: float) -> Vector3:
	return Vector3(x, _h(x, z) + LIFT, z)


## The map's height grid as a float texture, so the shader drapes the marks exactly as MapBase.height_at would.
func set_ground(map) -> void:
	if map == null or int(map.grid_n) < 2:
		return
	_grid_n = int(map.grid_n)
	_half = float(map.size_m) * 0.5
	_res = float(map.resolution)
	var img := Image.create_from_data(_grid_n, _grid_n, false, Image.FORMAT_RF, (map.heights as PackedFloat32Array).to_byte_array())
	_heights = ImageTexture.create_from_image(img)
	for key in _pools:
		if _pools[key]["mat"] is ShaderMaterial:
			_ground_uniforms(_pools[key]["mat"])


func _ground_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("heights", _heights)
	mat.set_shader_parameter("grid_n", _grid_n if _heights else 0)
	mat.set_shader_parameter("half_size", _half)
	mat.set_shader_parameter("resolution", _res)
	mat.set_shader_parameter("lift", LIFT)


# ---------------------------------------------------------------- what the game calls

## A ring on the ground: a band between r - 0.12 and r that grows from 40% to full over `dur`; `filled` adds a faint disc.
## `y_lift` floats it that many metres over the ground it drapes (pass 54: a wader's ripples lie on the water's surface,
## not on the lake bed under it; the shader reads the lift off the instance's basis, see _lift_basis).
func ring(center: Vector3, r: float, dur: float, color: Color, filled := false, y_lift := 0.0) -> void:
	var it := _add("band", center, color, 0.85, Color(maxf(r * 0.4 - 0.12, 0.05), r * 0.4, 0.0, TAU), MODE_GROW, dur, r)
	if y_lift > 0.0:
		it["lift"] = y_lift
	if filled:
		var d := _add("disc", center, color, 0.25, Color(0.0, r, 0.0, TAU), MODE_FADE, dur, r)
		if y_lift > 0.0:
			d["lift"] = y_lift


func line(from: Vector3, dir: Vector3, length: float, dur: float, color: Color, width := 1.2) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	_add("strip", from, color, 0.6, Color(d.x, d.z, length, width), MODE_FADE, dur, length)


## A wedge on the ground from `center` along `dir`, `deg` wide: the cone a shotgun is about to cover.
func sector(center: Vector3, dir: Vector3, r: float, deg: float, dur: float, color: Color) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var a0 := atan2(d.z, d.x) - deg_to_rad(deg) * 0.5
	_add("disc", center, color, 0.45, Color(0.0, r, a0, deg_to_rad(deg)), MODE_FADE, dur, r)


## A wash of colour over the ground (pass 46, the Guitarra's chord): a wedge `deg` wide along `dir` (360 a disc) that
## sweeps out from `center` to `r` over the first half of `dur` and fades away, at `alpha` at its brightest.
func wash(center: Vector3, dir: Vector3, r: float, deg: float, dur: float, color: Color, alpha := 0.4) -> void:
	var d := Vector3(dir.x, 0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var sweep := deg_to_rad(clampf(deg, 1.0, 360.0))
	var a0 := atan2(d.z, d.x) - sweep * 0.5
	_add("disc", center, color, alpha, Color(0.0, r, a0, sweep), MODE_WASH, dur, r)


func flash_ring(center: Vector3, r: float, color: Color, dur := 0.35, y_lift := 0.0) -> void:
	ring(center, r, dur, color, false, y_lift)


## A mark's instance basis (pass 54): the identity, or for a mark floated `lift` metres over the ground a y scale of
## 1 + lift, which core/shaders/ground_mark.gdshader adds to its height (the marks' shapes ignore the basis otherwise).
static func _lift_basis(it: Dictionary) -> Basis:
	var lift := float(it.get("lift", 0.0))
	return Basis.from_scale(Vector3(1.0, 1.0 + lift, 1.0)) if lift > 0.0 else Basis()


## A wave racing out over the sand (pass 52: the Nuke's and the revive's, which had been a flat torus at the hero's
## height that every hill cut through): a band `width_frac` of its radius wide, out from the centre to `r` over `dur`
## with an ease-out, fading as it goes; draped like every mark. `color`'s alpha is its strength.
func race_ring(center: Vector3, r: float, dur: float, color: Color, width_frac := 0.3) -> void:
	var it := _add("band", center, color, color.a, Color(0.0, 0.05, 0.0, TAU), MODE_RACE, dur, r)
	it["w"] = clampf(width_frac, 0.02, 1.0)


## A dark scorch where something went off: it holds `hold` seconds, then fades out over `fade`.
func scorch(center: Vector3, r: float, inner: Color, outer: Color, hold := 1.5, fade := 3.0) -> void:
	var it := _add(_blob_pool(inner, outer, PRIO_SCORCH), center, Color(1, 1, 1), 1.0, Color(r, randf(), 0.0, 0.0), MODE_SCORCH, hold + fade, r)
	it["hold"] = hold


## A spill its owner keeps on the ground (an ElementCloud's oil or poison): colours run from `inner` at the middle to
## `outer` at the lobed rim, as draped_blob drew them. Returns an id for set_alpha and release.
func hold_blob(center: Vector3, r: float, seed_v: float, inner: Color, outer: Color, prio := PRIO_SPILL) -> int:
	return _hold(_add(_blob_pool(inner, outer, prio), center, Color(1, 1, 1), 1.0, Color(r, seed_v, 0.0, 0.0), MODE_HELD, 0.0, r))


## A flat disc its owner keeps (a Zone), in `color` (sRGB, as a material's albedo). Returns an id.
func hold_disc(center: Vector3, r: float, color: Color) -> int:
	return _hold(_add("disc_zone", center, color, color.a, Color(0.0, r, 0.0, TAU), MODE_HELD, 0.0, r))


## A ring its owner keeps and resizes (the Brander's ring of fire, pass 43), in `color` (sRGB). Returns an id.
func hold_ring(center: Vector3, r: float, color: Color) -> int:
	return _hold(_add("band", center, color, color.a, Color(maxf(r - 0.35, 0.05), r, 0.0, TAU), MODE_HELD, 0.0, r))


## Move a held disc, ring or blob, and resize it (r < 0 keeps its size).
func move_held(id: int, at: Vector3, r: float = -1.0) -> void:
	var it: Dictionary = _held.get(id, {})
	if it.is_empty():
		return
	it["at"] = at
	if r > 0.0:
		it["r"] = r
		var k: Color = it["k"]
		# a band is (inner, outer), a disc (0, r); a blob is (r, seed) (pass 48: a blob used to get the radius in its seed slot)
		if str(it["pool"]).begins_with("blob:"):
			it["k"] = Color(r, k.g, k.b, k.a)
		else:
			it["k"] = Color(maxf(r - 0.35, 0.05) if it["pool"] == "band" else k.r, r, k.b, k.a)


## A see-through sphere its owner moves every frame (the poison cloud's billows), in `color` (sRGB). Returns an id;
## place it with set_puff.
func hold_puff(color: Color) -> int:
	return _hold(_add("puff", Vector3.ZERO, color, color.a, Color(), MODE_HELD, 0.0, 0.0))


func set_puff(id: int, xf: Transform3D, alpha: float) -> void:
	var it: Dictionary = _held.get(id, {})
	if not it.is_empty():
		it["xf"] = xf
		it["a"] = alpha


func set_alpha(id: int, alpha: float) -> void:
	var it: Dictionary = _held.get(id, {})
	if not it.is_empty():
		it["a"] = alpha


func release(id: int) -> void:
	var it: Dictionary = _held.get(id, {})
	if not it.is_empty():
		it["dead"] = true
		_held.erase(id)


## How many marks are on the ground right now (tests, the perf report).
func live_count() -> int:
	var n := 0
	for it in _items:
		if not it["dead"]:
			n += 1
	return n


func _hold(it: Dictionary) -> int:
	var id := _next_id
	_next_id += 1
	_held[id] = it
	return id


## `color` is taken as a material's albedo would be (the Compatibility renderer blends in sRGB, and an instance colour
## lands on screen as the albedo colour did: measured against the old per-mark materials). Spills carry their colours
## in the pool's uniforms and take white.
func _add(pool: String, at: Vector3, color: Color, alpha: float, k: Color, mode: int, dur: float, r: float) -> Dictionary:
	_pool(pool)
	var it := {"pool": pool, "at": at, "col": Color(color.r, color.g, color.b, alpha), "k": k, "mode": mode, "t": 0.0, "dur": dur, "r": r, "a": alpha, "dead": false}
	if pool == "puff":
		it["xf"] = Transform3D(Basis().scaled(Vector3.ZERO), at)
	_items.append(it)
	return it


# ---------------------------------------------------------------- the pools

func _blob_pool(inner: Color, outer: Color, prio: int) -> String:
	var key := "blob:%s|%s|%d" % [inner.to_html(), outer.to_html(), prio]
	if not _pools.has(key):
		var mat := _make_pool(key, _unit_blob(), 2, prio)
		mat.set_shader_parameter("inner_color", inner)
		mat.set_shader_parameter("outer_color", outer)
	return key


func _pool(key: String) -> void:
	if _pools.has(key):
		return
	match key:
		"band":
			_make_pool(key, _unit_polar(1), 0, PRIO_BAND)
		"disc", "disc_zone":
			_make_pool(key, _unit_polar(6), 0, PRIO_DISC)
		"strip":
			_make_pool(key, _unit_strip(), 1, PRIO_STRIP)
		"puff":
			_make_puff_pool()


func _new_mm(mesh: Mesh, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = 32
	mm.visible_instance_count = 0
	return mm


func _add_mmi(mm: MultiMesh, mat: Material, key: String) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Marks_" + key.left(12).replace(":", "_").replace("|", "_")
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


func _make_pool(key: String, mesh: Mesh, shape: int, prio: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = prio
	mat.set_shader_parameter("shape", shape)
	_ground_uniforms(mat)
	var mm := _new_mm(mesh, true)
	_add_mmi(mm, mat, key)
	_pools[key] = {"mm": mm, "n": 0, "mat": mat}
	return mat


## The poison cloud's billows: see-through spheres, drawn like the StandardMaterial3D puffs they replace.
func _make_puff_pool() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	var mm := _new_mm(sm, false)
	_add_mmi(mm, mat, "puff")
	_pools["puff"] = {"mm": mm, "n": 0, "mat": mat}


## A ring band (rows = 1) or a disc with `rows` rings for draping; UV.x runs inner to outer, UV.y round the sweep.
func _unit_polar(rows: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in range(rows):
		var f0 := float(q) / rows
		var f1 := float(q + 1) / rows
		for k in range(SEGMENTS):
			var u0 := float(k) / SEGMENTS
			var u1 := float(k + 1) / SEGMENTS
			_polar_vertex(st, f0, u0)
			_polar_vertex(st, f1, u0)
			_polar_vertex(st, f0, u1)
			_polar_vertex(st, f1, u0)
			_polar_vertex(st, f1, u1)
			_polar_vertex(st, f0, u1)
	return st.commit()


func _polar_vertex(st: SurfaceTool, f: float, u: float) -> void:
	st.set_uv(Vector2(f, u))
	st.add_vertex(Vector3(cos(u * TAU) * f, 0.0, sin(u * TAU) * f))


## A line: 64 steps along (UV.x) so it drapes over the dunes, two edges across (UV.y -0.5 and 0.5).
func _unit_strip() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := SEGMENTS
	for k in range(n):
		var a := float(k) / n
		var b := float(k + 1) / n
		for v in [Vector2(a, -0.5), Vector2(a, 0.5), Vector2(b, -0.5), Vector2(a, 0.5), Vector2(b, 0.5), Vector2(b, -0.5)]:
			st.set_uv(v)
			st.add_vertex(Vector3(v.x, 0.0, v.y))
	return st.commit()


## The spill's shape: 28 steps round, rings at the same fractions as draped_blob; the shader bends the rim.
func _unit_blob() -> Mesh:
	if _blob_mesh:
		return _blob_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	var fr := [0.0, 0.4, 0.68, 0.88, 1.0]
	for q in range(fr.size() - 1):
		var f0: float = fr[q]
		var f1: float = fr[q + 1]
		for k in range(n):
			var u0 := float(k) / n
			var u1 := float(k + 1) / n
			_polar_vertex(st, f0, u0)
			_polar_vertex(st, f1, u0)
			_polar_vertex(st, f0, u1)
			_polar_vertex(st, f1, u0)
			_polar_vertex(st, f1, u1)
			_polar_vertex(st, f0, u1)
	_blob_mesh = st.commit()
	return _blob_mesh


## Warm-up: one of every kind drawn at `at` for the frames the spawn beam covers, so the shader compiles there.
func warm_draw(at: Vector3) -> void:
	ring(at, 1.0, 0.4, Color(1, 1, 1), true)
	line(at, Vector3.FORWARD, 1.0, 0.4, Color(1, 1, 1))
	scorch(at, 1.0, Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 0.2, 0.2)
	var puff := hold_puff(Color(1, 1, 1, 0.2))
	set_puff(puff, Transform3D(Basis(), at), 0.2)
	# nothing may tick before the first frame (the arena's warm-up runs paused): the marks go into their MultiMeshes now
	_advance(0.0)
	_write()
	get_tree().create_timer(0.4, true, false, true).timeout.connect(func() -> void: release(puff))


# ---------------------------------------------------------------- draped meshes (world space, mesh origin at the world origin)

## A ring band draped on the ground, for anyone who keeps their own mesh (structures).
func draped_ring(center: Vector3, r0: float, r1: float) -> Mesh:
	return _ring_mesh(center, r0, r1)


## A draped strip from `from` along `dir`, for anyone who keeps their own mesh.
func draped_strip(from: Vector3, dir: Vector3, length: float, width: float) -> Mesh:
	return _strip_mesh(from, Vector3(dir.x, 0, dir.z).normalized(), length, width)


## A pie slice of a disc, `frac` of the full turn from twelve o'clock, draped on the ground: the progress marker.
func draped_sector(center: Vector3, r: float, frac: float, start_angle: float = -PI * 0.5) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(int(ceil(SEGMENTS * clampf(frac, 0.0, 1.0))), 1)
	var sweep := TAU * clampf(frac, 0.0, 1.0)
	var rings := 4
	for q in range(rings):
		var r0 := r * float(q) / rings
		var r1 := r * float(q + 1) / rings
		for k in range(n):
			var a0 := start_angle + sweep * k / n
			var a1 := start_angle + sweep * (k + 1) / n
			var i0 := _v(center.x + cos(a0) * r0, center.z + sin(a0) * r0)
			var o0 := _v(center.x + cos(a0) * r1, center.z + sin(a0) * r1)
			var i1 := _v(center.x + cos(a1) * r0, center.z + sin(a1) * r0)
			var o1 := _v(center.x + cos(a1) * r1, center.z + sin(a1) * r1)
			for tri in [[i0, o0, i1], [o0, o1, i1], [i0, i1, o0], [o0, i1, o1]]:
				for p in tri:
					st.add_vertex(p)
	return st.commit()

## A spill on the ground (pass 33): a draped disc with a lobed rim whose vertex colour runs from `inner` at the
## middle to `outer` at the edge, so a pool of oil reads as liquid soaking into the sand, not a painted plate.
func draped_blob(center: Vector3, r: float, seed_v: float, inner: Color, outer: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	var fr := [0.0, 0.4, 0.68, 0.88, 1.0]
	var ph1 := seed_v * 17.0
	var ph2 := seed_v * 31.0
	var rim: Array = []
	for k in range(n):
		var a := TAU * k / n
		rim.append(r * (1.0 + 0.13 * sin(a * 3.0 + ph1) + 0.07 * sin(a * 5.0 + ph2)))
	for q in range(fr.size() - 1):
		var f0: float = fr[q]
		var f1: float = fr[q + 1]
		var c0 := inner.lerp(outer, f0 * f0)
		var c1 := inner.lerp(outer, f1 * f1)
		for k in range(n):
			var k1 := (k + 1) % n
			var a0 := TAU * k / n
			var a1 := TAU * k1 / n
			var r0a: float = float(rim[k]) * f0
			var r0b: float = float(rim[k1]) * f0
			var r1a: float = float(rim[k]) * f1
			var r1b: float = float(rim[k1]) * f1
			var i0 := _v(center.x + cos(a0) * r0a, center.z + sin(a0) * r0a)
			var i1 := _v(center.x + cos(a1) * r0b, center.z + sin(a1) * r0b)
			var o0 := _v(center.x + cos(a0) * r1a, center.z + sin(a0) * r1a)
			var o1 := _v(center.x + cos(a1) * r1b, center.z + sin(a1) * r1b)
			st.set_color(c0); st.add_vertex(i0)
			st.set_color(c1); st.add_vertex(o0)
			st.set_color(c0); st.add_vertex(i1)
			st.set_color(c1); st.add_vertex(o0)
			st.set_color(c1); st.add_vertex(o1)
			st.set_color(c0); st.add_vertex(i1)
	return st.commit()


func _ring_mesh(c: Vector3, r0: float, r1: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(SEGMENTS):
		var a0 := TAU * k / SEGMENTS
		var a1 := TAU * (k + 1) / SEGMENTS
		var i0 := _v(c.x + cos(a0) * r0, c.z + sin(a0) * r0)
		var o0 := _v(c.x + cos(a0) * r1, c.z + sin(a0) * r1)
		var i1 := _v(c.x + cos(a1) * r0, c.z + sin(a1) * r0)
		var o1 := _v(c.x + cos(a1) * r1, c.z + sin(a1) * r1)
		# both windings: the marking must read from any camera side and never be culled
		for tri in [[i0, o0, i1], [o0, o1, i1], [i0, i1, o0], [o0, i1, o1]]:
			for p in tri:
				st.add_vertex(p)
	return st.commit()


func _disc_mesh(c: Vector3, r: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	for q in range(rings):
		var r0 := r * float(q) / rings
		var r1 := r * float(q + 1) / rings
		for k in range(SEGMENTS):
			var a0 := TAU * k / SEGMENTS
			var a1 := TAU * (k + 1) / SEGMENTS
			var i0 := _v(c.x + cos(a0) * r0, c.z + sin(a0) * r0)
			var o0 := _v(c.x + cos(a0) * r1, c.z + sin(a0) * r1)
			var i1 := _v(c.x + cos(a1) * r0, c.z + sin(a1) * r0)
			var o1 := _v(c.x + cos(a1) * r1, c.z + sin(a1) * r1)
			for tri in [[i0, o0, i1], [o0, o1, i1], [i0, i1, o0], [o0, i1, o1]]:
				for p in tri:
					st.add_vertex(p)
	return st.commit()


func _strip_mesh(from: Vector3, d: Vector3, length: float, width: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := Vector3(-d.z, 0, d.x) * width * 0.5
	var n := maxi(int(ceil(length / 0.5)), 2)
	for k in range(n):
		var t0 := length * float(k) / n
		var t1 := length * float(k + 1) / n
		var a := from + d * t0
		var b := from + d * t1
		var l0 := _v(a.x - side.x, a.z - side.z)
		var r0 := _v(a.x + side.x, a.z + side.z)
		var l1 := _v(b.x - side.x, b.z - side.z)
		var r1 := _v(b.x + side.x, b.z + side.z)
		for tri in [[l0, r0, l1], [r0, r1, l1], [l0, l1, r0], [r0, l1, r1]]:
			for p in tri:
				st.add_vertex(p)
	return st.commit()


func _mat(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_advance(delta)
	_write()
	Perf.add("telegraphs", t0)


## Ages the timed marks, drops the finished and released ones, and works out each one's alpha and shape this frame.
func _advance(delta: float) -> void:
	var keep: Array = []
	for it in _items:
		if it["dead"]:
			continue
		var mode: int = it["mode"]
		var k: Color = it["k"]
		var alpha: float = it["a"]
		if mode != MODE_HELD:
			it["t"] += delta
			var t: float = it["t"]
			var f: float = clampf(t / maxf(it["dur"], 0.01), 0.0, 1.0)
			if f >= 1.0:
				continue
			if mode == MODE_SCORCH:
				var hold: float = it.get("hold", 0.0)
				alpha = 1.0 - clampf((t - hold) / maxf(float(it["dur"]) - hold, 0.01), 0.0, 1.0)
			elif mode == MODE_RACE:
				# out from the middle fast, slowing as it goes; thinner and fainter at the end
				var out: float = 1.0 - pow(1.0 - f, 3.0)
				var rr: float = maxf(float(it["r"]) * out, 0.1)
				alpha = float(it["a"]) * (1.0 - f * f)
				k = Color(maxf(rr * (1.0 - float(it.get("w", 0.3))), 0.0), rr, k.b, k.a)
			elif mode == MODE_WASH:
				# out from the middle with an ease-out, then gone with an ease-in
				var grow: float = 1.0 - pow(1.0 - minf(f * 2.0, 1.0), 2.0)
				alpha = float(it["a"]) * (1.0 - f * f)
				k = Color(0.0, maxf(float(it["r"]) * (0.25 + 0.75 * grow), 0.05), k.b, k.a)
			else:
				# fades to half over its life and blinks in its last 40%
				alpha = float(it["a"]) * (1.0 - f * 0.5) * (1.0 if int(t * 12.0) % 2 == 0 or f < 0.6 else 0.45)
				if mode == MODE_GROW:
					var r: float = float(it["r"]) * (0.4 + 0.6 * f)
					k = Color(maxf(r - 0.12, 0.05), r, k.b, k.a)
		it["_a"] = alpha
		it["_k"] = k
		keep.append(it)
	_items = keep


## Every live mark into its pool's MultiMesh.
func _write() -> void:
	var counts := {}
	for it in _items:
		counts[it["pool"]] = int(counts.get(it["pool"], 0)) + 1
	# room for everything first (a MultiMesh forgets its instances when it is resized), then write
	for key in counts:
		var mm0: MultiMesh = _pools[key]["mm"]
		if int(counts[key]) > mm0.instance_count:
			mm0.instance_count = maxi(mm0.instance_count * 2, int(counts[key]))
	for key in _pools:
		_pools[key]["n"] = 0
	for it in _items:
		var pool: Dictionary = _pools[it["pool"]]
		var mm: MultiMesh = pool["mm"]
		var n: int = pool["n"]
		var c: Color = it["col"]
		c.a = it["_a"]
		if it["pool"] == "puff":
			mm.set_instance_transform(n, it["xf"])
		else:
			mm.set_instance_transform(n, Transform3D(_lift_basis(it), it["at"]))
			mm.set_instance_custom_data(n, it["_k"])
		mm.set_instance_color(n, c)
		pool["n"] = n + 1
	for key in _pools:
		var pool: Dictionary = _pools[key]
		(pool["mm"] as MultiMesh).visible_instance_count = pool["n"]
