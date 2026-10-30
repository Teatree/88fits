## The pieces of a boss's barrier (pass 115, lane BOSS; content/boss_attacks `barrier.look`, BossBarrier lays them round the
## ring): small low-poly 3D meshes built here in code from tubes, cones, boxes and balls, coloured by vertex colours (the
## lit pieces: their paint; the glowing pieces: a heat from 0 to 1 that core/shaders/boss_barrier.gdshader turns into the
## barrier's glow colour, white-hot at 1). Built once per look and kept. Every piece stands on its own origin at the sand
## (y 0 = the ground, a stake's foot 0.35 m below it so it never floats on a dune); x runs along the fence, z across it.
##   tumbleweed_fence  the King's: "stake" a rough wooden stake with rope wraps and a sharpened top; "weed" a tumbleweed
##                     (a dark core in a tangle of twigs); "weed_glow" its smouldering embers; "rope" a sagging rope one
##                     metre long along x (stretched stake to stake)
##   cactus_fence      the Gila's: "column" a ribbed organ-pipe cactus column with pale spines; "column_glow" a venom
##                     bloom on its top; "thorns" a clump of long thorns
##   iron_fence        the Brander's: "bar" a black iron bar, hot at its top; "bar_glow" its white-hot spear head; "rail" an
##                     iron rail one metre long along x (stretched post to post), "rail_glow" the red-hot lower one; "post"
##                     a branding iron driven into the sand; "post_glow" its glowing brand (a ring and a cross)
## Godot's front faces are clockwise: _tri takes an outward hint and orders each triangle to face it.
class_name BarrierMeshes
extends RefCounted

## The height every look is made to (m); `barrier.height` scales it.
const DESIGN_H := 1.8
## Each look's stretch (m): one segment of the ring.
const SEG := {"tumbleweed_fence": 1.8, "cactus_fence": 1.3, "iron_fence": 1.7}
## Which pieces glow (drawn with the glow material) and which roll away as the barrier falls apart.
const GLOW_PARTS := ["weed_glow", "column_glow", "bar_glow", "rail_glow", "post_glow"]
const ROLL_PARTS := ["weed", "weed_glow"]

static var _cache: Dictionary = {}


## {piece name: ArrayMesh} of `look` (an empty Dictionary for an unknown look).
static func parts(look: String) -> Dictionary:
	if _cache.has(look):
		return _cache[look]
	var out := {}
	match look:
		"tumbleweed_fence":
			out = {"stake": _stake(), "weed": _weed(), "weed_glow": _embers(), "rope": _rope()}
		"cactus_fence":
			out = {"column": _column(), "column_glow": _bloom(), "thorns": _thorns()}
		"iron_fence":
			out = {"bar": _bar(), "bar_glow": _spear(), "rail": _rail(), "rail_glow": _rail_hot(), "post": _post(), "post_glow": _brand()}
	_cache[look] = out
	return out


# ---------------------------------------------------------------- primitives

static func _c(r: int, g: int, b: int) -> Color:
	return Color8(r, g, b)


## One triangle facing `hint` (Godot: clockwise seen from the front), flat-shaded unless normals are given.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, hint: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(hint) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		var tn := nb
		nb = nc
		nc = tn
	var flat := -(b - a).cross(c - a).normalized()
	st.set_color(ca)
	st.set_normal(na if na != Vector3.ZERO else flat)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_normal(nb if nb != Vector3.ZERO else flat)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_normal(nc if nc != Vector3.ZERO else flat)
	st.add_vertex(c)


## Two unit vectors at right angles to `axis` and to each other.
static func _frame(axis: Vector3) -> Array:
	var ax := axis.normalized()
	var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var u := ax.cross(ref).normalized()
	var v := ax.cross(u).normalized()
	return [u, v]


## A tube from `a` (radius r0) to `b` (radius r1), `sides` round, smooth-shaded, coloured ca at a and cb at b; `caps` closes
## its ends.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, ca: Color, cb: Color, caps := true, twist := 0.0) -> void:
	var f := _frame(b - a)
	var u: Vector3 = f[0]
	var v: Vector3 = f[1]
	var ra: Array = []
	var rb: Array = []
	var na: Array = []
	for j in range(sides):
		var ang := TAU * float(j) / float(sides) + twist
		var d := u * cos(ang) + v * sin(ang)
		ra.append(a + d * r0)
		rb.append(b + d * r1)
		na.append(d)
	for j in range(sides):
		var j2 := (j + 1) % sides
		var mid := ((ra[j] + ra[j2] + rb[j] + rb[j2]) as Vector3) * 0.25
		var hint: Vector3 = mid - (a + b) * 0.5
		_tri(st, ra[j], rb[j], rb[j2], ca, cb, cb, hint, na[j], na[j], na[j2])
		_tri(st, ra[j], rb[j2], ra[j2], ca, cb, ca, hint, na[j], na[j2], na[j2])
	if caps:
		var ax := (b - a).normalized()
		for j in range(sides):
			var j2 := (j + 1) % sides
			_tri(st, a, ra[j], ra[j2], ca, ca, ca, -ax)
			_tri(st, b, rb[j], rb[j2], cb, cb, cb, ax)


## A cone from a base circle at `base` (radius r) to `tip`.
static func _cone(st: SurfaceTool, base: Vector3, tip: Vector3, r: float, sides: int, cbase: Color, ctip: Color, cap := true) -> void:
	var f := _frame(tip - base)
	var u: Vector3 = f[0]
	var v: Vector3 = f[1]
	var ring: Array = []
	for j in range(sides):
		var ang := TAU * float(j) / float(sides)
		ring.append(base + (u * cos(ang) + v * sin(ang)) * r)
	for j in range(sides):
		var j2 := (j + 1) % sides
		var mid := ((ring[j] + ring[j2]) as Vector3) * 0.5
		_tri(st, ring[j], ring[j2], tip, cbase, cbase, ctip, mid - base)
		if cap:
			_tri(st, base, ring[j], ring[j2], cbase, cbase, cbase, base - tip)


## A box `half` round `c`, turned by `basis`, each face its own colour shade (top lighter, bottom darker).
static func _box(st: SurfaceTool, c: Vector3, half: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var axes := [basis.x.normalized(), basis.y.normalized(), basis.z.normalized()]
	var h := [half.x, half.y, half.z]
	for k in range(3):
		for s in [-1.0, 1.0]:
			var n: Vector3 = axes[k] * s
			var a1: Vector3 = axes[(k + 1) % 3] * h[(k + 1) % 3]
			var a2: Vector3 = axes[(k + 2) % 3] * h[(k + 2) % 3]
			var fc: Vector3 = c + n * h[k]
			var shade := col.lightened(0.12) if k == 1 and s > 0.0 else (col.darkened(0.25) if k == 1 else col)
			var p0 := fc - a1 - a2
			var p1 := fc + a1 - a2
			var p2 := fc + a1 + a2
			var p3 := fc - a1 + a2
			_tri(st, p0, p1, p2, shade, shade, shade, n)
			_tri(st, p0, p2, p3, shade, shade, shade, n)


## An icosphere: [vertices on the unit sphere, faces (Vector3i)], subdivided `subdiv` times.
static func _ico(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t),
		Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1),
		Vector3(-t, 0, 1)]
	for k in range(verts.size()):
		verts[k] = (verts[k] as Vector3).normalized()
	var faces: Array = [Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8), Vector3i(3, 9, 4),
		Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9), Vector3i(4, 9, 5), Vector3i(2, 4, 11),
		Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for _s in range(subdiv):
		var mids := {}
		var nf: Array = []
		for f: Vector3i in faces:
			var m := []
			for e in [[f.x, f.y], [f.y, f.z], [f.z, f.x]]:
				var key := "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
				if not mids.has(key):
					verts.append(((verts[e[0]] as Vector3) + (verts[e[1]] as Vector3)).normalized())
					mids[key] = verts.size() - 1
				m.append(mids[key])
			nf.append(Vector3i(f.x, m[0], m[2]))
			nf.append(Vector3i(f.y, m[1], m[0]))
			nf.append(Vector3i(f.z, m[2], m[1]))
			nf.append(Vector3i(m[0], m[1], m[2]))
		faces = nf
	return [verts, faces]


## A lumpy ball of radius `r` round `c` (each vertex moved by up to `jitter` x r along its normal), smooth-shaded.
static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color, subdiv: int, jitter: float, rng: RandomNumberGenerator, scale := Vector3.ONE, col2 := Color(0, 0, 0, 0)) -> void:
	var ico := _ico(subdiv)
	var vs: Array = ico[0]
	var fs: Array = ico[1]
	var pts: Array = []
	var cols: Array = []
	for v: Vector3 in vs:
		var k := 1.0 + (rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0)
		pts.append(c + v * r * k * scale)
		cols.append(col if col2.a <= 0.0 else col.lerp(col2, clampf(0.5 - 0.5 * v.y, 0.0, 1.0)))
	for f: Vector3i in fs:
		var a: Vector3 = pts[f.x]
		var b: Vector3 = pts[f.y]
		var d: Vector3 = pts[f.z]
		var hint := (a + b + d) / 3.0 - c
		_tri(st, a, b, d, cols[f.x], cols[f.y], cols[f.z], hint, (vs[f.x] as Vector3), (vs[f.y] as Vector3), (vs[f.z] as Vector3))


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _end(st: SurfaceTool) -> ArrayMesh:
	return st.commit()


# ---------------------------------------------------------------- the King's tumbleweed fence

static func _stake() -> ArrayMesh:
	var st := _begin()
	var low := _c(84, 56, 32)
	var top := _c(138, 98, 60)
	var foot := Vector3(0, -0.35, 0)
	var head := Vector3(0, 1.6, 0)
	_tube(st, foot, head, 0.085, 0.072, 6, low, top, true, 0.3)
	_cone(st, head, Vector3(0.0, 1.86, 0.0), 0.072, 6, top, _c(112, 78, 46))
	var rope := _c(212, 176, 112)
	var rope_d := _c(168, 132, 80)
	for y: float in [1.28, 0.6]:
		_tube(st, Vector3(0, y, 0), Vector3(0, y + 0.05, 0), 0.098, 0.098, 8, rope_d, rope, true)
		_tube(st, Vector3(0, y + 0.05, 0), Vector3(0, y + 0.1, 0), 0.098, 0.096, 8, rope, rope_d, true)
	return _end(st)


static func _weed() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11501
	var st := _begin()
	var c := Vector3.ZERO
	# the dark core: the weed reads as a mass, not a see-through wire ball, on pale sand
	_ball(st, c, 0.4, _c(70, 44, 22), 1, 0.15, rng, Vector3.ONE, _c(48, 30, 14))
	# the tangle: every edge of a lumpy icosphere a thin twig, light and dark, and some chords across it
	var ico := _ico(1)
	var vs: Array = ico[0]
	var fs: Array = ico[1]
	var pts: Array = []
	for v: Vector3 in vs:
		var lump := v + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		pts.append(c + lump.normalized() * 0.6 * (1.0 + rng.randf_range(-0.2, 0.16)))
	var seen := {}
	var tw := [_c(146, 112, 70), _c(178, 142, 92), _c(112, 82, 50), _c(160, 124, 78), _c(96, 70, 42)]
	var k := 0
	for f: Vector3i in fs:
		for e in [[f.x, f.y], [f.y, f.z], [f.z, f.x]]:
			var key := "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
			if seen.has(key):
				continue
			seen[key] = true
			# a fifth of the lattice left out, so it reads as a tangle and not a cage
			if rng.randf() < 0.2:
				continue
			var col: Color = tw[k % tw.size()]
			k += 1
			# each twig bowed a little off its straight line
			var a0: Vector3 = pts[e[0]]
			var b0: Vector3 = pts[e[1]]
			var mid := (a0 + b0) * 0.5 * rng.randf_range(1.02, 1.12)
			var r0 := rng.randf_range(0.024, 0.04)
			_tube(st, a0, mid, r0, r0 * 0.9, 3, col, col, false, rng.randf() * TAU)
			_tube(st, mid, b0, r0 * 0.9, r0 * 0.75, 3, col, col.darkened(0.15), false, rng.randf() * TAU)
	# twigs across it, through the core: a dense tangle
	for _j in range(26):
		var a: Vector3 = pts[rng.randi() % pts.size()]
		var b: Vector3 = pts[rng.randi() % pts.size()]
		if a.distance_to(b) > 0.45:
			var col2: Color = tw[rng.randi() % tw.size()]
			_tube(st, a, b, 0.022, 0.018, 3, col2, col2.darkened(0.2), false, rng.randf() * TAU)
	return _end(st)


static func _embers() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11502
	var st := _begin()
	for _j in range(10):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var r := rng.randf_range(0.045, 0.075)
		var heat := rng.randf_range(0.55, 1.0)
		_ball(st, d * rng.randf_range(0.5, 0.62), r, Color(heat, heat, heat), 0, 0.2, rng)
	return _end(st)


static func _rope() -> ArrayMesh:
	var st := _begin()
	var a := _c(212, 176, 112)
	var b := _c(160, 124, 74)
	var n := 8
	for j in range(n):
		var x0 := float(j) / float(n)
		var x1 := float(j + 1) / float(n)
		var p0 := Vector3(x0, -0.08 * sin(PI * x0), 0)
		var p1 := Vector3(x1, -0.08 * sin(PI * x1), 0)
		_tube(st, p0, p1, 0.03, 0.03, 5, a if j % 2 == 0 else b, b if j % 2 == 0 else a, false, 0.4 * float(j))
	return _end(st)


# ---------------------------------------------------------------- the Gila's cactus fence

static func _column() -> ArrayMesh:
	var st := _begin()
	var ribs := 6
	var n := ribs * 2
	var rings := [[-0.35, 1.0], [0.0, 1.0], [0.5, 1.02], [1.0, 1.0], [1.45, 0.97], [1.75, 0.92], [1.9, 0.76], [2.0, 0.48]]
	var tip_c := _c(86, 156, 78)
	var groove_c := _c(40, 94, 48)
	var top_c := _c(112, 176, 92)
	var base_c := _c(50, 92, 44)
	var pts: Array = []
	var nrm: Array = []
	var cols: Array = []
	for ring: Array in rings:
		var y: float = ring[0]
		var s: float = ring[1]
		var rp: Array = []
		var rn: Array = []
		var rc: Array = []
		var shade := clampf((y + 0.35) / 2.35, 0.0, 1.0)
		for j in range(n):
			var ang := TAU * float(j) / float(n)
			var rad := (0.24 if j % 2 == 0 else 0.17) * s
			rp.append(Vector3(cos(ang) * rad, y, sin(ang) * rad))
			rn.append(Vector3(cos(ang), 0.25 if y > 1.7 else 0.0, sin(ang)).normalized())
			var base := tip_c if j % 2 == 0 else groove_c
			var col := base_c.lerp(base, smoothstep(0.0, 0.25, shade)).lerp(top_c if j % 2 == 0 else base, smoothstep(0.7, 1.0, shade) * 0.6)
			rc.append(col)
		pts.append(rp)
		nrm.append(rn)
		cols.append(rc)
	for k in range(rings.size() - 1):
		for j in range(n):
			var j2 := (j + 1) % n
			var a: Vector3 = pts[k][j]
			var b: Vector3 = pts[k + 1][j]
			var c2: Vector3 = pts[k + 1][j2]
			var d: Vector3 = pts[k][j2]
			var mid := (a + c2) * 0.5
			var hint := Vector3(mid.x, 0.0, mid.z) + Vector3(0, 0.2 if k >= rings.size() - 3 else 0.0, 0)
			_tri(st, a, b, c2, cols[k][j], cols[k + 1][j], cols[k + 1][j2], hint, nrm[k][j], nrm[k + 1][j], nrm[k + 1][j2])
			_tri(st, a, c2, d, cols[k][j], cols[k + 1][j2], cols[k][j2], hint, nrm[k][j], nrm[k + 1][j2], nrm[k][j2])
	# the dome's cap
	var apex := Vector3(0, 2.06, 0)
	var last: Array = pts[rings.size() - 1]
	for j in range(n):
		var j2 := (j + 1) % n
		_tri(st, last[j], last[j2], apex, cols[rings.size() - 1][j], cols[rings.size() - 1][j2], top_c, Vector3.UP + ((last[j] as Vector3) * 0.5))
	# pale spines along every rib
	var spine := _c(240, 232, 204)
	var spine_t := _c(255, 252, 240)
	for j in range(0, n, 2):
		var ang := TAU * float(j) / float(n)
		var out := Vector3(cos(ang), 0, sin(ang))
		for y: float in [0.25, 0.65, 1.05, 1.42]:
			var at := out * 0.235 + Vector3(0, y, 0)
			_cone(st, at, at + (out + Vector3(0, 0.25, 0)).normalized() * 0.13, 0.02, 3, spine, spine_t, false)
			_cone(st, at + Vector3(0, 0.06, 0), at + Vector3(0, 0.06, 0) + (out + Vector3(0, -0.2, 0) + out.cross(Vector3.UP) * 0.6).normalized() * 0.1, 0.016, 3, spine, spine_t, false)
	return _end(st)


static func _bloom() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11503
	var st := _begin()
	var top := Vector3(0, 2.07, 0)
	for j in range(5):
		var ang := TAU * float(j) / 5.0
		var d := Vector3(cos(ang), 0.55, sin(ang)).normalized()
		_ball(st, top + d * 0.09, 0.07, Color(0.72, 0.72, 0.72), 0, 0.0, rng, Vector3(1.4, 0.6, 1.0))
	_ball(st, top + Vector3(0, 0.05, 0), 0.06, Color(1, 1, 1), 1, 0.0, rng)
	# a drop of venom on the way down one rib
	_ball(st, Vector3(0.24, 1.82, 0.0), 0.04, Color(0.85, 0.85, 0.85), 0, 0.0, rng, Vector3(1, 1.5, 1))
	return _end(st)


static func _thorns() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11504
	var st := _begin()
	var base := _c(196, 178, 140)
	var tip := _c(250, 246, 232)
	var foot := Vector3(0, -0.05, 0)
	_ball(st, Vector3(0, 0.02, 0), 0.12, _c(58, 104, 52), 1, 0.2, rng, Vector3(1.2, 0.6, 1.2))
	for j in range(6):
		var ang := TAU * float(j) / 6.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(ang) * 0.75, rng.randf_range(0.55, 1.1), sin(ang) * 0.75).normalized()
		_cone(st, foot, foot + d * rng.randf_range(0.55, 0.8), 0.035, 4, base, tip, false)
	return _end(st)


# ---------------------------------------------------------------- the Brander's iron fence

static func _bar() -> ArrayMesh:
	var st := _begin()
	var iron := _c(46, 42, 42)
	var warm := _c(128, 52, 26)
	_tube(st, Vector3(0, -0.35, 0), Vector3(0, 1.1, 0), 0.05, 0.05, 4, iron, iron, true, PI * 0.25)
	_tube(st, Vector3(0, 1.1, 0), Vector3(0, 1.5, 0), 0.05, 0.05, 4, iron, warm, true, PI * 0.25)
	for y: float in [0.25, 1.2]:
		_box(st, Vector3(0, y, 0), Vector3(0.068, 0.045, 0.068), _c(58, 52, 50))
	return _end(st)


static func _spear() -> ArrayMesh:
	var st := _begin()
	var a := Color(0.5, 0.5, 0.5)
	var b := Color(0.72, 0.72, 0.72)
	var t := Color(0.96, 0.96, 0.96)
	var base := Vector3(0, 1.48, 0)
	var wide := 1.6
	var tip := Vector3(0, 1.9, 0)
	var corners := [Vector3(0.1, wide, 0), Vector3(0, wide, 0.05), Vector3(-0.1, wide, 0), Vector3(0, wide, -0.05)]
	for j in range(4):
		var c1: Vector3 = corners[j]
		var c2: Vector3 = corners[(j + 1) % 4]
		var mid := (c1 + c2) * 0.5
		_tri(st, base, c1, c2, a, b, b, Vector3(mid.x, -0.3, mid.z))
		_tri(st, c1, c2, tip, b, b, t, Vector3(mid.x, 0.2, mid.z))
	return _end(st)


static func _rail() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(0.5, 0, 0), Vector3(0.5, 0.032, 0.04), _c(40, 36, 36))
	return _end(st)


## The lower rail, red-hot (a glowing piece: its heat 0.45, a dull glow under the white-hot tips).
static func _rail_hot() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(0.5, 0, 0), Vector3(0.5, 0.034, 0.042), Color(0.45, 0.45, 0.45))
	return _end(st)


static func _post() -> ArrayMesh:
	var st := _begin()
	var iron := _c(38, 34, 34)
	var warm := _c(150, 58, 24)
	_tube(st, Vector3(0, -0.35, 0), Vector3(0, 1.35, 0), 0.06, 0.055, 4, iron, iron, true, PI * 0.25)
	_tube(st, Vector3(0, 1.35, 0), Vector3(0, 1.78, 0), 0.055, 0.045, 4, iron, warm, true, PI * 0.25)
	# the grip's wrap low on the shaft and a collar under the brand
	_tube(st, Vector3(0, 0.3, 0), Vector3(0, 0.62, 0), 0.075, 0.075, 6, _c(92, 60, 36), _c(70, 44, 26), true)
	_box(st, Vector3(0, 1.79, 0), Vector3(0.09, 0.03, 0.05), _c(60, 40, 34))
	return _end(st)


static func _brand() -> ArrayMesh:
	var st := _begin()
	var hot := Color(0.95, 0.95, 0.95)
	var warm := Color(0.7, 0.7, 0.7)
	var c := Vector3(0, 2.07, 0)
	var r := 0.25
	var n := 16
	for j in range(n):
		var a0 := TAU * float(j) / float(n)
		var a1 := TAU * float(j + 1) / float(n)
		_tube(st, c + Vector3(cos(a0) * r, sin(a0) * r, 0), c + Vector3(cos(a1) * r, sin(a1) * r, 0), 0.032, 0.032, 4, hot, warm if j % 2 == 0 else hot, false)
	# the cross in the ring and the stem down to the shaft
	_tube(st, c + Vector3(-r, 0, 0), c + Vector3(r, 0, 0), 0.028, 0.028, 4, warm, warm, true)
	_tube(st, c + Vector3(0, -r, 0), c + Vector3(0, r, 0), 0.028, 0.028, 4, hot, hot, true)
	_tube(st, Vector3(0, 1.78, 0), c + Vector3(0, -r, 0), 0.03, 0.03, 4, warm, hot, true)
	return _end(st)
