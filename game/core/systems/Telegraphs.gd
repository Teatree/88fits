## Pooled ground telegraphs: rings, filled discs and lines that fade over their duration. Every marking is a mesh
## draped over the terrain (each vertex sits on the map's height at that point, a few centimetres up), so dunes,
## the riverbed and the meadow's hills never cut through it. The game hands in `height_fn` (map.height_at).
class_name Telegraphs
extends Node3D

const LIFT := 0.1
const SEGMENTS := 64

var height_fn: Callable = Callable()
var _items: Array = []   # {node, t, dur, grow, base_alpha}


func _h(x: float, z: float) -> float:
	return float(height_fn.call(x, z)) if height_fn.is_valid() else 0.0


func _v(x: float, z: float) -> Vector3:
	return Vector3(x, _h(x, z) + LIFT, z)


## A ring on the ground: a band between r - 0.12 and r, draped, drawn with its own vertices so it can grow.
func ring(center: Vector3, r: float, dur: float, color: Color, filled := false) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _ring_mesh(center, maxf(r - 0.12, 0.05), r)
	m.material_override = _mat(color, 0.85)
	add_child(m)
	_items.append({"node": m, "t": 0.0, "dur": dur, "grow": true, "base_alpha": 0.85, "center": center, "r": r})
	if filled:
		var f := MeshInstance3D.new()
		f.mesh = _disc_mesh(center, r)
		f.material_override = _mat(color, 0.25)
		add_child(f)
		_items.append({"node": f, "t": 0.0, "dur": dur, "grow": false, "base_alpha": 0.25})


func line(from: Vector3, dir: Vector3, length: float, dur: float, color: Color, width := 1.2) -> void:
	var m := MeshInstance3D.new()
	var d := Vector3(dir.x, 0, dir.z).normalized()
	m.mesh = _strip_mesh(from, d, length, width)
	m.material_override = _mat(color, 0.6)
	add_child(m)
	_items.append({"node": m, "t": 0.0, "dur": dur, "grow": false, "base_alpha": 0.6})


func flash_ring(center: Vector3, r: float, color: Color, dur := 0.35) -> void:
	ring(center, r, dur, color, false)


# ---------------------------------------------------------------- draped meshes (world space, mesh origin at the world origin)

## A ring band draped on the ground, for anyone who keeps their own mesh (structures).
func draped_ring(center: Vector3, r0: float, r1: float) -> Mesh:
	return _ring_mesh(center, r0, r1)


## A draped strip from `from` along `dir`, for anyone who keeps their own mesh.
func draped_strip(from: Vector3, dir: Vector3, length: float, width: float) -> Mesh:
	return _strip_mesh(from, Vector3(dir.x, 0, dir.z).normalized(), length, width)


## A pie slice of a disc, `frac` of the full turn from twelve o'clock, draped on the ground: the progress marker.
func draped_sector(center: Vector3, r: float, frac: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(int(ceil(SEGMENTS * clampf(frac, 0.0, 1.0))), 1)
	var sweep := TAU * clampf(frac, 0.0, 1.0)
	var rings := 4
	for q in range(rings):
		var r0 := r * float(q) / rings
		var r1 := r * float(q + 1) / rings
		for k in range(n):
			var a0 := -PI * 0.5 + sweep * k / n
			var a1 := -PI * 0.5 + sweep * (k + 1) / n
			var i0 := _v(center.x + cos(a0) * r0, center.z + sin(a0) * r0)
			var o0 := _v(center.x + cos(a0) * r1, center.z + sin(a0) * r1)
			var i1 := _v(center.x + cos(a1) * r0, center.z + sin(a1) * r0)
			var o1 := _v(center.x + cos(a1) * r1, center.z + sin(a1) * r1)
			for tri in [[i0, o0, i1], [o0, o1, i1], [i0, i1, o0], [o0, i1, o1]]:
				for p in tri:
					st.add_vertex(p)
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
	var keep: Array = []
	for it in _items:
		it["t"] += delta
		var n: MeshInstance3D = it["node"]
		var f: float = clamp(it["t"] / max(it["dur"], 0.01), 0.0, 1.0)
		var mat := n.material_override as StandardMaterial3D
		if mat:
			var c := mat.albedo_color
			var base: float = it["base_alpha"]
			# pulse toward the end
			c.a = base * (1.0 - f * 0.5) * (1.0 if int(it["t"] * 12.0) % 2 == 0 or f < 0.6 else 0.45)
			mat.albedo_color = c
		if it["grow"]:
			# the ring grows from 40% to full: rebuilt rather than scaled, so it stays draped on the ground
			var s := 0.4 + 0.6 * f
			var r: float = it["r"]
			n.mesh = _ring_mesh(it["center"], maxf(r * s - 0.12, 0.05), r * s)
		if f >= 1.0:
			n.queue_free()
		else:
			keep.append(it)
	_items = keep
