## Red Canyon's walls (pass 80, lane WALLS; Garry: "the textures on the mountains behind the walls look too low res and
## walls don't have any proper textures to begin with. Make the walls look like sandstone castle walls (but western),
## instead of what they are now."): the boundary as a western sandstone fort wall and the cliff rings behind it, both
## with real paintings mapped in world units so nothing stretches. RedCanyon calls these (its `_boundary_wall` and
## `_ridge`); every colour comes from the map's `wall_colors` (RedCanyon.WALL_COLORS by default).
##
## The fort wall stands where the stacked-stone wall stood: a ring `THICK` (1.7 m) thick centred on the arena's edge, its
## foundation sunk SINK under the ground, so play is unchanged (the hero is stopped by RedCanyon's invisible fence 1.1 m
## inside, as before; nothing here collides). Seen from the run's camera (north from the south, about 46 degrees down):
##   the inner face   dressed sandstone blocks (art/env/fort_wall.png, tiled TILE m, courses level in the world), leaning
##                    back BATTER over its height, darker towards its foot (weathering), each stretch a shade apart
##   the cap course   a band of dressed stone CAP_H tall jutting CAP_OUT over the inner face, the wall-walk on top of it
##   the parapet      PARAPET_T thick on the outer edge, PARAPET_H over the walk, with merlons (rounded tops, the Spanish
##                    colonial "almena") every MERLON_W + MERLON_GAP
##   the vigas        round beam ends of dark wood jutting VIGA_OUT from the inner face under the cap course, every
##                    VIGA_EVERY m (one MultiMesh)
##   the towers       a squat tower every TOWER_EVERY_DEG degrees, TOWER_W wide, standing out TOWER_OUT past the outer face
##                    (the inner face flush with the wall's, so the arena's edge is where it was) and TOWER_H over the walk,
##                    its own parapet and merlons, a second row of vigas
## The walk's height follows the ground in steps of STEP (a level wall that steps where the ground climbs), so the
## courses stay level. One mesh, one material (the painting times the vertex colours), plus the vigas: two draw calls.
extends RefCounted

const WALL_TEX := "res://art/env/fort_wall.png"
const CLIFF_TEX := "res://art/env/cliff_rock.png"

const THICK := 1.7
const SINK := 0.8
## the wall-walk's height over the ground at the inner foot; the old stacked-stone wall stood 1.9 to 2.75 m over it
const WALK_H := 2.0
const STEP := 0.25
const BATTER := 0.12
const CAP_H := 0.22
const CAP_OUT := 0.1
const PARAPET_T := 0.55
const PARAPET_H := 0.45
const MERLON_W := 1.0
const MERLON_GAP := 0.7
## a merlon's straight sides, then its rounded top (a half ellipse MERLON_ARC tall)
const MERLON_SIDE := 0.22
const MERLON_ARC := 0.24
const MERLON_ARC_PTS := 8
## metres of wall one tile of the painting covers (across and up)
const TILE := 3.2
const VIGA_EVERY := 1.7
const VIGA_R := 0.1
const VIGA_OUT := 0.45
## the vigas' depth under the walk (their centres)
const VIGA_DOWN := 0.42
const TOWER_EVERY_DEG := 30.0
const TOWER_W := 5.0
const TOWER_OUT := 1.4
const TOWER_H := 1.4
## the weathering: the inner face's foot this much darker than its top, the darkening reaching this high over the ground
const FOOT_DARK := 0.32
const FOOT_RISE := 0.9
## each stretch of wall (a ring segment) a shade lighter or darker than the next, at most this much
const PATCH := 0.07
const BEAM_WOOD := Color(0.36, 0.25, 0.16)

## the cliffs (pass 80): metres of cliff one tile of the rock painting covers, by ring (near, far, farther)
const CLIFF_TILES := [14.0, 20.0, 28.0]
## the cliff face's rows: fractions of the way up where the face is pushed in or out by up to CLIFF_RELIEF m
const CLIFF_ROWS := [0.33, 0.66]
const CLIFF_RELIEF := 0.9


# ---------------------------------------------------------------- the fort wall

## The fort wall round `r` in `segs` stretches, built on `map`'s ground (height_at) in `colours` (stone, light, cap,
## riser, beams), its noise `noise` (the map's, so a seed keeps its wall). Returns the root holding the mesh and the
## vigas; RedCanyon adds the posts and the skulls.
static func fort_wall(map: Node, r: float, segs: int, colours: Dictionary, noise: FastNoiseLite) -> Node3D:
	var root := Node3D.new()
	root.name = "FortWall"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone: Color = colours.get("stone", Color(0.72, 0.6, 0.5))
	var light: Color = colours.get("light", stone.lightened(0.15))
	var cap: Color = colours.get("cap", stone.darkened(0.15))
	var riser: Color = colours.get("riser", stone.darkened(0.3))
	var ri := r - THICK * 0.5
	var ro := r + THICK * 0.5
	var circ := TAU * ri
	var u_tiles := maxf(roundf(circ / TILE), 1.0)
	# the ground along the inner foot, smoothed round the ring, and the walk quantised to STEP over it
	var ground: Array = []
	for k in range(segs):
		var a := TAU * (float(k) + 0.5) / segs
		ground.append(_h(map, cos(a) * (r - 1.0), sin(a) * (r - 1.0)))
	var walk: Array = []
	var foot: Array = []
	for k in range(segs):
		var s := 0.0
		for j in range(-2, 3):
			s += float(ground[(k + j + segs) % segs])
		var g := s / 5.0
		foot.append(g)
		walk.append(snappedf(g + WALK_H, STEP))
	var towers := _tower_angles(segs)
	for k in range(segs):
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var w: float = walk[k]
		var base: float = minf(float(foot[k]), float(ground[k])) - SINK
		var tint := 1.0 + PATCH * noise.get_noise_1d(float(k) * 7.3 + 50.0)
		var sc := _mul(stone, tint)
		var u0 := float(k) / segs * u_tiles
		var u1 := float(k + 1) / segs * u_tiles
		var y_cap := w - CAP_H
		var ri_t := ri + BATTER
		# the inner face, two bands: the weathered foot, then the face up to the cap course
		var y_mid: float = float(foot[k]) + FOOT_RISE
		var dark := _mul(sc, 1.0 - FOOT_DARK)
		var mid_c := sc
		var f_mid := clampf((y_mid - base) / maxf(y_cap - base, 0.01), 0.0, 1.0)
		var rm := ri + BATTER * f_mid
		_quad_uv(st,
			_ring(a0, ri, base), _ring(a1, ri, base), _ring(a1, rm, y_mid), _ring(a0, rm, y_mid),
			Vector2(u0, -base / TILE), Vector2(u1, -base / TILE), Vector2(u1, -y_mid / TILE), Vector2(u0, -y_mid / TILE),
			[dark, dark, mid_c, mid_c])
		_quad_uv(st,
			_ring(a0, rm, y_mid), _ring(a1, rm, y_mid), _ring(a1, ri_t, y_cap), _ring(a0, ri_t, y_cap),
			Vector2(u0, -y_mid / TILE), Vector2(u1, -y_mid / TILE), Vector2(u1, -y_cap / TILE), Vector2(u0, -y_cap / TILE),
			[mid_c, mid_c, sc, sc])
		# the cap course: its underside, its face, then the walk from it to the parapet
		var rc := ri_t - CAP_OUT
		var lc := _mul(light, tint)
		_quad_uv(st, _ring(a0, ri_t, y_cap), _ring(a1, ri_t, y_cap), _ring(a1, rc, y_cap), _ring(a0, rc, y_cap),
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, CAP_OUT / TILE), Vector2(u0, CAP_OUT / TILE), [riser, riser, riser, riser])
		_quad_uv(st, _ring(a0, rc, y_cap), _ring(a1, rc, y_cap), _ring(a1, rc, w), _ring(a0, rc, w),
			Vector2(u0, -y_cap / TILE), Vector2(u1, -y_cap / TILE), Vector2(u1, -w / TILE), Vector2(u0, -w / TILE), [lc, lc, lc, lc])
		var rp := ro - PARAPET_T
		var cc := _mul(cap, tint)
		_quad_top(st, _ring(a0, rc, w), _ring(a1, rc, w), _ring(a1, rp, w), _ring(a0, rp, w), cc)
		# the parapet: its inner face, its top (merlons stand on it), the outer face down to the foundation
		var yp := w + PARAPET_H
		_quad_uv(st, _ring(a0, rp, w), _ring(a1, rp, w), _ring(a1, rp, yp), _ring(a0, rp, yp),
			Vector2(u0, -w / TILE), Vector2(u1, -w / TILE), Vector2(u1, -yp / TILE), Vector2(u0, -yp / TILE), [sc, sc, sc, sc])
		_quad_top(st, _ring(a0, rp, yp), _ring(a1, rp, yp), _ring(a1, ro, yp), _ring(a0, ro, yp), lc)
		var oc := _mul(sc, 0.75)
		var ob := _mul(oc, 1.0 - FOOT_DARK)
		_quad_uv(st, _ring(a0, ro, base), _ring(a1, ro, base), _ring(a1, ro, yp), _ring(a0, ro, yp),
			Vector2(u0, -base / TILE), Vector2(u1, -base / TILE), Vector2(u1, -yp / TILE), Vector2(u0, -yp / TILE), [ob, ob, oc, oc])
		# where the walk steps to the next stretch's height: a riser across the whole thickness, up to the higher parapet
		var wn: float = walk[(k + 1) % segs]
		if absf(wn - w) > 0.01:
			_quad_side(st, a1, rc, ro, base, maxf(w, wn) + PARAPET_H, riser)
	# the merlons along the parapet (skipping the towers, which carry their own)
	var period := MERLON_W + MERLON_GAP
	var n_m := int(roundf(TAU * ro / period))
	for j in range(n_m):
		var am := TAU * (float(j) + 0.5) / n_m
		if _near_tower(am, towers, TOWER_W * 0.5 + MERLON_W, ro):
			continue
		var k := int(floor(am / TAU * segs)) % segs
		var tint := 1.0 + PATCH * noise.get_noise_1d(float(k) * 7.3 + 50.0)
		_merlon(st, am, ro - PARAPET_T, ro, float(walk[k]) + PARAPET_H, MERLON_W, _mul(stone, tint), _mul(light, tint), riser, u_tiles, ri)
	# the towers
	for at: float in towers:
		var k := int(floor(at / TAU * segs)) % segs
		_tower(st, at, ri, ro, float(walk[k]), minf(float(foot[k]), float(ground[k])) - SINK, stone, light, cap, riser, u_tiles)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.mesh = st.commit()
	mi.material_override = wall_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.add_child(_vigas(r, segs, walk, towers, colours.get("beams", BEAM_WOOD)))
	return root


## The fort wall's material: the sandstone painting times the vertex colours (sRGB), mipmapped and anisotropic, both
## faces drawn (the ring's faces run either way past the arena's axis). Unshaded, like the painted scenery round it: the
## sun stands in the north-east, so a shaded wall showed the camera (looking north) its dark side all round the north
## half; the light and shade are painted into the vertex colours instead (tops `light` and `cap`, faces `stone`, the
## sides across the wall `riser`, the outer face and the foot darker), so each key is the colour drawn, times the painting.
static func wall_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	if ResourceLoader.exists(WALL_TEX):
		mat.albedo_texture = load(WALL_TEX)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## The ground under (x, z) on `map` (0 before its terrain is built: a bare map in a test).
static func _h(map: Node, x: float, z: float) -> float:
	return float(map.call("height_at", x, z)) if map != null and map.has_method("height_at") else 0.0


static func _ring(a: float, rr: float, y: float) -> Vector3:
	return Vector3(cos(a) * rr, y, sin(a) * rr)


static func _mul(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


## A quad p0 p1 p2 p3 (two triangles p0 p1 p2, p0 p2 p3) with its UVs and colours.
static func _quad_uv(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t0: Vector2, t1: Vector2, t2: Vector2, t3: Vector2, cols: Array) -> void:
	var ps := [p0, p1, p2, p0, p2, p3]
	var ts := [t0, t1, t2, t0, t2, t3]
	var ix := [0, 1, 2, 0, 2, 3]
	for n in range(6):
		st.set_color(cols[ix[n]])
		st.set_uv(ts[n])
		st.add_vertex(ps[n])


## A flat top: the painting laid on it from above (world x, z over TILE), one colour.
static func _quad_top(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color) -> void:
	_quad_uv(st, p0, p1, p2, p3, Vector2(p0.x, p0.z) / TILE, Vector2(p1.x, p1.z) / TILE, Vector2(p2.x, p2.z) / TILE,
		Vector2(p3.x, p3.z) / TILE, [c, c, c, c])


## A face across the wall at angle `a` from radius r0 to r1 (a riser: the step between two stretches' walks, from the
## foundation `b` up to `hi`, the higher parapet's top).
static func _quad_side(st: SurfaceTool, a: float, r0: float, r1: float, b: float, hi: float, c: Color) -> void:
	_quad_uv(st, _ring(a, r0, b), _ring(a, r1, b), _ring(a, r1, hi), _ring(a, r0, hi),
		Vector2(r0 / TILE, -b / TILE), Vector2(r1 / TILE, -b / TILE), Vector2(r1 / TILE, -hi / TILE), Vector2(r0 / TILE, -hi / TILE), [c, c, c, c])


## A merlon at angle `a` on the parapet from radius r0 to r1, standing on `y0`: straight sides MERLON_SIDE tall, a
## rounded top MERLON_ARC more, `w` wide along the wall. Its faces (front, back), its sides and the arc's top strip.
static func _merlon(st: SurfaceTool, a: float, r0: float, r1: float, y0: float, w: float, c: Color, top_c: Color, side_c: Color, u_tiles: float, ri: float) -> void:
	var tang := Vector3(-sin(a), 0.0, cos(a))
	var outl: Array = []          # (along, up) round the outline, left foot first
	outl.append(Vector2(-w * 0.5, 0.0))
	outl.append(Vector2(-w * 0.5, MERLON_SIDE))
	for n in range(1, MERLON_ARC_PTS):
		var t := PI - PI * float(n) / MERLON_ARC_PTS
		outl.append(Vector2(cos(t) * w * 0.5, MERLON_SIDE + sin(t) * MERLON_ARC))
	outl.append(Vector2(w * 0.5, MERLON_SIDE))
	outl.append(Vector2(w * 0.5, 0.0))
	var u_mid := a / TAU * u_tiles
	var u_per_m := u_tiles / (TAU * ri)
	for face in [[r0, c], [r1, _mul(c, 0.75)]]:
		var rr: float = face[0]
		var col: Color = face[1]
		var mid := Vector3(cos(a) * rr, y0, sin(a) * rr)
		# a fan from the foot's middle (the outline is convex)
		var centre := mid + Vector3(0, (MERLON_SIDE + MERLON_ARC) * 0.4, 0)
		var cu := Vector2(u_mid, -centre.y / TILE)
		for n in range(outl.size()):
			var p: Vector2 = outl[n]
			var q: Vector2 = outl[(n + 1) % outl.size()]
			var pp := mid + tang * p.x + Vector3(0, p.y, 0)
			var qq := mid + tang * q.x + Vector3(0, q.y, 0)
			for v in [[centre, cu], [pp, Vector2(u_mid + p.x * u_per_m, -pp.y / TILE)], [qq, Vector2(u_mid + q.x * u_per_m, -qq.y / TILE)]]:
				st.set_color(col)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	# the sides and the top: a strip round the outline from the inner face to the outer
	var along := 0.0
	for n in range(1, outl.size() - 1):
		var p: Vector2 = outl[n - 1]
		var q: Vector2 = outl[n]
		var seg := p.distance_to(q)
		var col := side_c if n == 1 or n == outl.size() - 1 else top_c
		var a0 := Vector3(cos(a) * r0, y0, sin(a) * r0) + tang * p.x + Vector3(0, p.y, 0)
		var a1 := Vector3(cos(a) * r0, y0, sin(a) * r0) + tang * q.x + Vector3(0, q.y, 0)
		var b0 := Vector3(cos(a) * r1, y0, sin(a) * r1) + tang * p.x + Vector3(0, p.y, 0)
		var b1 := Vector3(cos(a) * r1, y0, sin(a) * r1) + tang * q.x + Vector3(0, q.y, 0)
		_quad_uv(st, a0, a1, b1, b0, Vector2(along / TILE, 0.0), Vector2((along + seg) / TILE, 0.0),
			Vector2((along + seg) / TILE, (r1 - r0) / TILE), Vector2(along / TILE, (r1 - r0) / TILE), [col, col, col, col])
		along += seg
	# the last side (down the right)
	var p2: Vector2 = outl[outl.size() - 2]
	var q2: Vector2 = outl[outl.size() - 1]
	var c0 := Vector3(cos(a) * r0, y0, sin(a) * r0)
	var c1 := Vector3(cos(a) * r1, y0, sin(a) * r1)
	_quad_uv(st, c0 + tang * p2.x + Vector3(0, p2.y, 0), c0 + tang * q2.x + Vector3(0, q2.y, 0), c1 + tang * q2.x + Vector3(0, q2.y, 0), c1 + tang * p2.x + Vector3(0, p2.y, 0),
		Vector2(0, -p2.y / TILE), Vector2(0, -q2.y / TILE), Vector2((r1 - r0) / TILE, -q2.y / TILE), Vector2((r1 - r0) / TILE, -p2.y / TILE), [side_c, side_c, side_c, side_c])


## The towers' angles round the ring: every TOWER_EVERY_DEG degrees, the first half a step past north-east so none
## stands square in front of the camera at the start.
static func _tower_angles(_segs: int) -> Array:
	var out: Array = []
	var n := int(roundf(360.0 / TOWER_EVERY_DEG))
	for k in range(n):
		out.append(TAU * (float(k) + 0.5) / n)
	return out


static func _near_tower(a: float, towers: Array, half_w: float, rr: float) -> bool:
	for t: float in towers:
		if absf(angle_difference(a, t)) * rr < half_w:
			return true
	return false


## A squat tower at angle `at`: a box from the wall's inner face (flush) to TOWER_OUT past the outer face, TOWER_W wide,
## its walk TOWER_H over the wall's, a cap course, a parapet with merlons on its four edges.
static func _tower(st: SurfaceTool, at: float, ri: float, ro: float, walk: float, base: float, stone: Color, light: Color, cap: Color, riser: Color, u_tiles: float) -> void:
	var n := Vector3(cos(at), 0.0, sin(at))
	var t := Vector3(-sin(at), 0.0, cos(at))
	var r0 := ri + BATTER * 0.5
	var r1 := ro + TOWER_OUT
	var hw := TOWER_W * 0.5
	var y_top := walk + TOWER_H
	var y_cap := y_top - CAP_H
	var u_mid := at / TAU * u_tiles
	var u_per_m := u_tiles / (TAU * ri)
	var corner := func(rr: float, along: float, y: float) -> Vector3:
		return n * rr + t * along + Vector3(0, y, 0)
	var sc := _mul(stone, 1.04)
	var dark := _mul(sc, 1.0 - FOOT_DARK)
	var y_mid := base + SINK + FOOT_RISE
	# the inner face (towards the arena): the weathered foot, the face, the cap course jutting out
	var u_l := u_mid - hw * u_per_m
	var u_r := u_mid + hw * u_per_m
	for band in [[base, y_mid, dark, sc], [y_mid, y_cap, sc, sc]]:
		var y0: float = band[0]
		var y1: float = band[1]
		_quad_uv(st, corner.call(r0, -hw, y0), corner.call(r0, hw, y0), corner.call(r0, hw, y1), corner.call(r0, -hw, y1),
			Vector2(u_l, -y0 / TILE), Vector2(u_r, -y0 / TILE), Vector2(u_r, -y1 / TILE), Vector2(u_l, -y1 / TILE), [band[2], band[2], band[3], band[3]])
	var lc := _mul(light, 1.04)
	var rc := r0 - CAP_OUT
	var ho := hw + CAP_OUT
	_quad_uv(st, corner.call(rc, -ho, y_cap), corner.call(rc, ho, y_cap), corner.call(rc, ho, y_top), corner.call(rc, -ho, y_top),
		Vector2(u_l, -y_cap / TILE), Vector2(u_r, -y_cap / TILE), Vector2(u_r, -y_top / TILE), Vector2(u_l, -y_top / TILE), [lc, lc, lc, lc])
	_quad_uv(st, corner.call(r0, -hw, y_cap), corner.call(r0, hw, y_cap), corner.call(rc, ho, y_cap), corner.call(rc, -ho, y_cap),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.03), Vector2(0, 0.03), [riser, riser, riser, riser])
	# the two sides (each from the inner face out past the wall), and the outer face, darker
	for side in [-1.0, 1.0]:
		var s: float = side
		var hs := hw * s
		var c_side := _mul(sc, 0.88)
		_quad_uv(st, corner.call(r0, hs, base), corner.call(r1, hs, base), corner.call(r1, hs, y_cap), corner.call(r0, hs, y_cap),
			Vector2(r0 / TILE, -base / TILE), Vector2(r1 / TILE, -base / TILE), Vector2(r1 / TILE, -y_cap / TILE), Vector2(r0 / TILE, -y_cap / TILE), [_mul(c_side, 1.0 - FOOT_DARK), _mul(c_side, 1.0 - FOOT_DARK), c_side, c_side])
		var hso := ho * s
		_quad_uv(st, corner.call(rc, hso, y_cap), corner.call(r1 + CAP_OUT, hso, y_cap), corner.call(r1 + CAP_OUT, hso, y_top), corner.call(rc, hso, y_top),
			Vector2(rc / TILE, -y_cap / TILE), Vector2((r1 + CAP_OUT) / TILE, -y_cap / TILE), Vector2((r1 + CAP_OUT) / TILE, -y_top / TILE), Vector2(rc / TILE, -y_top / TILE), [lc, lc, lc, lc])
	var oc := _mul(sc, 0.75)
	_quad_uv(st, corner.call(r1, -hw, base), corner.call(r1, hw, base), corner.call(r1, hw, y_cap), corner.call(r1, -hw, y_cap),
		Vector2(u_l, -base / TILE), Vector2(u_r, -base / TILE), Vector2(u_r, -y_cap / TILE), Vector2(u_l, -y_cap / TILE), [oc, oc, oc, oc])
	_quad_uv(st, corner.call(r1 + CAP_OUT, -ho, y_cap), corner.call(r1 + CAP_OUT, ho, y_cap), corner.call(r1 + CAP_OUT, ho, y_top), corner.call(r1 + CAP_OUT, -ho, y_top),
		Vector2(u_l, -y_cap / TILE), Vector2(u_r, -y_cap / TILE), Vector2(u_r, -y_top / TILE), Vector2(u_l, -y_top / TILE), [_mul(lc, 0.8), _mul(lc, 0.8), _mul(lc, 0.8), _mul(lc, 0.8)])
	# the roof, and a parapet ring round its edge with merlons
	var cc := cap
	_quad_top(st, corner.call(rc, -ho, y_top), corner.call(rc, ho, y_top), corner.call(r1 + CAP_OUT, ho, y_top), corner.call(r1 + CAP_OUT, -ho, y_top), cc)
	var pt := 0.4
	var yp := y_top + PARAPET_H * 0.8
	# four parapet walls, each a box: inner edge, outer edge, left, right
	var boxes := [
		[rc, rc + pt, -ho, ho],
		[r1 + CAP_OUT - pt, r1 + CAP_OUT, -ho, ho],
		[rc + pt, r1 + CAP_OUT - pt, -ho, -ho + pt],
		[rc + pt, r1 + CAP_OUT - pt, ho - pt, ho],
	]
	for b in boxes:
		_box_local(st, n, t, b[0], b[1], b[2], b[3], y_top, yp, sc, lc)
	# merlons on the inner edge (the one the camera sees) and the outer edge
	var mw := 0.8
	var count := 3
	for k in range(count):
		var along := -ho + pt + (float(k) + 0.5) * (2.0 * ho - 2.0 * pt) / count
		_merlon_local(st, n, t, rc, rc + pt, along, yp, mw, sc, lc, riser)
		_merlon_local(st, n, t, r1 + CAP_OUT - pt, r1 + CAP_OUT, along, yp, mw, sc, lc, riser)


## A box in a tower's frame (n out, t along): radii r0..r1, along a0..a1, heights y0..y1; its top `top_c`.
static func _box_local(st: SurfaceTool, n: Vector3, t: Vector3, r0: float, r1: float, a0: float, a1: float, y0: float, y1: float, c: Color, top_c: Color) -> void:
	var p := func(rr: float, al: float, y: float) -> Vector3:
		return n * rr + t * al + Vector3(0, y, 0)
	var cs := _mul(c, 0.9)
	# inner, outer, left, right faces, the top
	_quad_uv(st, p.call(r0, a0, y0), p.call(r0, a1, y0), p.call(r0, a1, y1), p.call(r0, a0, y1),
		Vector2(a0 / TILE, -y0 / TILE), Vector2(a1 / TILE, -y0 / TILE), Vector2(a1 / TILE, -y1 / TILE), Vector2(a0 / TILE, -y1 / TILE), [c, c, c, c])
	_quad_uv(st, p.call(r1, a0, y0), p.call(r1, a1, y0), p.call(r1, a1, y1), p.call(r1, a0, y1),
		Vector2(a0 / TILE, -y0 / TILE), Vector2(a1 / TILE, -y0 / TILE), Vector2(a1 / TILE, -y1 / TILE), Vector2(a0 / TILE, -y1 / TILE), [cs, cs, cs, cs])
	_quad_uv(st, p.call(r0, a0, y0), p.call(r1, a0, y0), p.call(r1, a0, y1), p.call(r0, a0, y1),
		Vector2(r0 / TILE, -y0 / TILE), Vector2(r1 / TILE, -y0 / TILE), Vector2(r1 / TILE, -y1 / TILE), Vector2(r0 / TILE, -y1 / TILE), [cs, cs, cs, cs])
	_quad_uv(st, p.call(r0, a1, y0), p.call(r1, a1, y0), p.call(r1, a1, y1), p.call(r0, a1, y1),
		Vector2(r0 / TILE, -y0 / TILE), Vector2(r1 / TILE, -y0 / TILE), Vector2(r1 / TILE, -y1 / TILE), Vector2(r0 / TILE, -y1 / TILE), [cs, cs, cs, cs])
	_quad_top(st, p.call(r0, a0, y1), p.call(r0, a1, y1), p.call(r1, a1, y1), p.call(r1, a0, y1), top_c)


## A merlon in a tower's frame: on radii r0..r1, centred `along`, standing on `y0`, `w` wide.
static func _merlon_local(st: SurfaceTool, n: Vector3, t: Vector3, r0: float, r1: float, along: float, y0: float, w: float, c: Color, top_c: Color, side_c: Color) -> void:
	# reuse the ring merlon by building it at angle 0 in the tower's frame: a merlon whose "angle" points along n
	var outl: Array = []
	outl.append(Vector2(-w * 0.5, 0.0))
	outl.append(Vector2(-w * 0.5, MERLON_SIDE))
	for k in range(1, MERLON_ARC_PTS):
		var a := PI - PI * float(k) / MERLON_ARC_PTS
		outl.append(Vector2(cos(a) * w * 0.5, MERLON_SIDE + sin(a) * MERLON_ARC))
	outl.append(Vector2(w * 0.5, MERLON_SIDE))
	outl.append(Vector2(w * 0.5, 0.0))
	for face in [[r0, c], [r1, _mul(c, 0.8)]]:
		var rr: float = face[0]
		var col: Color = face[1]
		var mid := n * rr + t * along + Vector3(0, y0, 0)
		var centre := mid + Vector3(0, (MERLON_SIDE + MERLON_ARC) * 0.4, 0)
		for k in range(outl.size()):
			var p: Vector2 = outl[k]
			var q: Vector2 = outl[(k + 1) % outl.size()]
			for v in [centre, mid + t * p.x + Vector3(0, p.y, 0), mid + t * q.x + Vector3(0, q.y, 0)]:
				st.set_color(col)
				st.set_uv(Vector2((along + (v as Vector3).dot(t) - mid.dot(t)) / TILE, -(v as Vector3).y / TILE))
				st.add_vertex(v)
	for k in range(outl.size() - 1):
		var p: Vector2 = outl[k]
		var q: Vector2 = outl[k + 1]
		var col := side_c if k == 0 or k == outl.size() - 2 else top_c
		var a0 := n * r0 + t * (along + p.x) + Vector3(0, y0 + p.y, 0)
		var a1 := n * r0 + t * (along + q.x) + Vector3(0, y0 + q.y, 0)
		var b0 := n * r1 + t * (along + p.x) + Vector3(0, y0 + p.y, 0)
		var b1 := n * r1 + t * (along + q.x) + Vector3(0, y0 + q.y, 0)
		_quad_uv(st, a0, a1, b1, b0, Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 0.1), Vector2(0, 0.1), [col, col, col, col])


## The vigas: one MultiMesh of six-sided beam ends jutting VIGA_OUT inwards from the inner face, VIGA_DOWN under the
## walk, every VIGA_EVERY m round the ring (none in front of a tower, a row of their own on each tower's face).
static func _vigas(r: float, segs: int, walk: Array, towers: Array, wood: Color) -> MultiMeshInstance3D:
	var ri := r - THICK * 0.5
	var cm := CylinderMesh.new()
	cm.top_radius = VIGA_R
	cm.bottom_radius = VIGA_R * 1.08
	cm.height = VIGA_OUT + 0.3
	cm.radial_segments = 6
	cm.rings = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = wood
	mat.roughness = 1.0
	# lit, unlike the wall (a round beam end reads by its light and shade)
	cm.material = mat
	var spots: Array = []
	var n := int(roundf(TAU * ri / VIGA_EVERY))
	for k in range(n):
		var a := TAU * (float(k) + 0.25) / n
		if _near_tower(a, towers, TOWER_W * 0.5 + 0.3, ri):
			continue
		var seg := int(floor(a / TAU * segs)) % segs
		spots.append([a, float(walk[seg]) - CAP_H - VIGA_DOWN, ri + BATTER * 0.9])
	for at: float in towers:
		var seg := int(floor(at / TAU * segs)) % segs
		var y := float(walk[seg]) + TOWER_H - CAP_H - VIGA_DOWN
		for j in range(-1, 2):
			var a := at + float(j) * 1.6 / ri
			spots.append([a, y, ri + BATTER * 0.5])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = spots.size()
	for k in range(spots.size()):
		var a: float = spots[k][0]
		var y: float = spots[k][1]
		var face: float = spots[k][2]
		var out := Vector3(cos(a), 0.0, sin(a))
		# the cylinder's axis (its y) laid along the ring's radius, pointing in; its middle half in the wall
		var basis := Basis(Quaternion(Vector3.UP, -out))
		var centre := out * (face - (VIGA_OUT + 0.3) * 0.5 + 0.3) + Vector3(0, y, 0)
		mm.set_instance_transform(k, Transform3D(basis, centre))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Vigas"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# ---------------------------------------------------------------- the cliffs

## A cliff ring's material (pass 80): the rock painting (art/env/cliff_rock.png, grey on average so `tint` is the colour
## drawn) through the ring's own UVs, mipmapped and anisotropic, both faces drawn, no shadows.
static func cliff_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(CLIFF_TEX):
		mat.albedo_texture = load(CLIFF_TEX)
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 1.0
	mat.metallic_specular = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## A ring of cliffs round `r`: the face from 3 m under the ground at the arena's edge up to a jagged top (h + h_var
## noise) 4 m further out, pushed in and out at CLIFF_ROWS so it breaks into ledges, then a top sloping 12 m back and
## 2 m down. UVs in metres over `tile` (across: round the ring, a whole number of tiles; up: the height on the face, the
## distance over the top), so the strata lie level and nothing stretches.
static func ridge(map: Node, arena_radius: float, r: float, h: float, h_var: float, segs: int, mat: Material, noise_off: float, noise: FastNoiseLite, tile: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u_tiles := maxf(roundf(TAU * (r + 2.0) / tile), 1.0)
	# the columns: per angle, the face's points from the foot up (foot, rows..., top), then the back
	var cols: Array = []
	for k2 in range(segs + 1):
		var a := TAU * float(k2 % segs) / segs
		var nh := noise.get_noise_2d(cos(a) * 30.0 + noise_off * 100.0, sin(a) * 30.0)
		var top := h + h_var * nh + h_var * 0.35 * sin(a * 7.0 + noise_off)
		var g := _h(map, cos(a) * minf(r, arena_radius - 1.0), sin(a) * minf(r, arena_radius - 1.0)) - 3.0
		var pts: Array = [Vector3(cos(a) * r, g, sin(a) * r)]
		for f: float in CLIFF_ROWS:
			var rel := noise.get_noise_2d(cos(a) * 55.0 + noise_off * 37.0 + f * 90.0, sin(a) * 55.0 - f * 40.0)
			var rr := r + 4.0 * f + CLIFF_RELIEF * rel
			var yy := lerpf(g, top, f) + 0.6 * noise.get_noise_2d(cos(a) * 70.0 + f * 13.0, sin(a) * 70.0 + noise_off)
			pts.append(Vector3(cos(a) * rr, yy, sin(a) * rr))
		pts.append(Vector3(cos(a) * (r + 4.0), top, sin(a) * (r + 4.0)))
		var back: Vector3 = pts[pts.size() - 1] + Vector3(cos(a), 0, sin(a)) * 12.0 - Vector3(0, 2.0, 0)
		pts.append(back)
		cols.append(pts)
	for k2 in range(segs):
		var u0 := float(k2) / segs * u_tiles
		var u1 := float(k2 + 1) / segs * u_tiles
		var c0: Array = cols[k2]
		var c1: Array = cols[k2 + 1]
		var last := c0.size() - 1
		for j in range(last):
			var p00: Vector3 = c0[j]
			var p10: Vector3 = c1[j]
			var p01: Vector3 = c0[j + 1]
			var p11: Vector3 = c1[j + 1]
			var v00 := -p00.y / tile
			var v10 := -p10.y / tile
			var v01 := -p01.y / tile
			var v11 := -p11.y / tile
			if j == last - 1:
				# over the top: the distance travelled, not the height (the top is nearly flat)
				v01 = v00 - p00.distance_to(p01) / tile
				v11 = v10 - p10.distance_to(p11) / tile
			# seen from the arena: clockwise (the material draws both faces anyway)
			for tri in [[[p00, Vector2(u0, v00)], [p01, Vector2(u0, v01)], [p10, Vector2(u1, v10)]],
					[[p01, Vector2(u0, v01)], [p11, Vector2(u1, v11)], [p10, Vector2(u1, v10)]]]:
				for v in tri:
					st.set_uv(v[1])
					st.add_vertex(v[0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
