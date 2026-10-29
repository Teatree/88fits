## The Saiga Sniper's telegraph and shot (pass 73, lane SNIPER; Garry: "red lines 'gather' from the side of the cone of the
## aiming shot of the sniper, they 'gather' into the point where the Player hero is, more lines come in progressively
## quicker, until they stop (the line stops following the Player whereas before it was following him all along), pause
## for 1 second and a beam of laser light passes through. after it reddish sparks are left shimmering for a brief second
## or 2 as they fade away").
##
## EnemyManager's sniper brain owns every clock and hands this node what to draw each tick: begin(), then aim() or lock()
## for each sniper aiming; beam() starts a shot, which then plays on this node's own clock (the flash of the beam, then
## its sparks), so it outlives the sniper that fired it. Everything is a camera-facing ribbon or quad in two
## ImmediateMeshes rebuilt every frame while anything shows: a soft red glow (added on) under the lines, the beam's core
## and the sparks' hearts (blended), both drawn over everything (no depth test) so a dune never hides the warning. A line
## runs along the sand at a height easing from the muzzle's to the hero's chest (CHEST) at the aim's distance and staying
## there past it, so the 60 m beam follows the ground over the dunes instead of sinking into them.
##
## The gathering (line_plan): `n` lines over the aim, the k-th appearing at (aim - SWEEP_MIN) x (k / n)^GATHER_POW (closer
## and closer together) on alternate sides of a cone `cone_deg` wide round the aim, and sweeping in to the hero over
## SWEEP_MAX down to SWEEP_MIN seconds (each faster than the one before); one that arrives joins the line on the hero,
## which grows brighter with every one. The lock: one solid line, blinking faster and faster (LOCK_BLINK_HZ) through the
## hold, the beam's whole path faint ahead of it. The beam: a white-hot core `width` wide in a red glow GLOW_WIDTH x as
## wide, BEAM_FLASH of the `seconds` at full and the rest fading; then SPARKS_PER_M sparks a metre along it drift up,
## shimmer (each its own phase) and fade over `sparks` seconds.
class_name SniperFx
extends Node3D

## the hero's chest over his feet: where the lines meet him and the beam runs on at
const CHEST := 1.0
## how far past the hero a gathering line reaches (m)
const OVERSHOOT := 2.5
## the gathering: the first lines sweep in over SWEEP_MAX s, the last over SWEEP_MIN; the spacing shrinks by this power
const SWEEP_MAX := 0.8
const SWEEP_MIN := 0.2
const GATHER_POW := 0.6
## line widths (m): a gathering line, the line on the hero, the locked line
const LINE_W := 0.1
const CENTRE_W := 0.13
const LOCK_W := 0.17
## a ribbon's glow is this many times its width
const LINE_GLOW := 3.2
## the locked line blinks from LOCK_BLINK_HZ.x to .y through the hold
const LOCK_BLINK_HZ := Vector2(3.0, 11.0)
## the beam: its glow this many times its core's width; at full for this share of its seconds, then fading
const GLOW_WIDTH := 3.6
const BEAM_FLASH := 0.45
## sparks along the beam: how many a metre, their sizes (m), their rise (m/s), how fast they shimmer (rad/s)
const SPARKS_PER_M := 2.4
const SPARK_SIZE := Vector2(0.12, 0.24)
## the beam's path glows red after the flash, fading out with the sparks: its alpha at the start and its width (x the beam's)
const AFTERGLOW_A := 0.42
const AFTERGLOW_W := 1.8
const SPARK_RISE := Vector2(0.15, 0.9)
const SPARK_SHIMMER := 26.0
## a ribbon's step along the sand (m)
const STEP := 1.5
## a deep red: blended over the bright sand it stays red (added on, a red glow only washed the sand paler)
const RED := Color(0.93, 0.06, 0.04)
const HOT := Color(1.0, 0.93, 0.9)
const SPARK_COLS := [Color(1.0, 0.16, 0.06), Color(1.0, 0.38, 0.1), Color(0.95, 0.08, 0.22)]

var height_fn: Callable = Callable()
## the creatures' clock (High Noon slows the shot's show as it slows the creatures; EnemyManager sets it every tick)
var time_scale := 1.0
## this tick's aims: {mode "aim"|"lock", from, dir, d, t, total, lines, length, width}
var _aims: Array = []
## shots in the air: {from, dir, length, width, d, h0, t, dur}
var _beams: Array = []
## {p, v, t, life, size, ph, col}
var _sparks: Array = []
var _glow_mesh: ImmediateMesh
var _line_mesh: ImmediateMesh
var _cam_pos := Vector3(0, 30, 30)
var _cam_right := Vector3.RIGHT
var _cam_up := Vector3.UP
var _rng := RandomNumberGenerator.new()
## the meshes hold last frame's triangles (cleared before the next draw)
var _drawn_any := false
## diagnostics and tests: what the last frame drew
var drawn_lines := 0
var drawn_beams := 0
var drawn_sparks := 0


func _ready() -> void:
	_rng.randomize()
	_glow_mesh = ImmediateMesh.new()
	_line_mesh = ImmediateMesh.new()
	# both blended: on the sand a glow added on read pale yellow, not red (the first capture)
	_add_mesh("SniperGlow", _glow_mesh, _material(false, 3))
	_add_mesh("SniperLines", _line_mesh, _material(false, 4))


func _add_mesh(nm: String, mesh: ImmediateMesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 80, 400))
	mi.top_level = true
	add_child(mi)


static func _material(additive: bool, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priority
	return m


# ---------------------------------------------------------------- what the sniper brain calls

## The lines of one aim (see the header): [{a0 (radians, signed by the side it starts on), t0, dur}], every one landing
## by the end of the aim.
static func line_plan(n: int, aim_s: float, cone_deg: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	n = maxi(n, 1)
	var half := deg_to_rad(maxf(cone_deg, 1.0)) * 0.5
	var span := maxf(aim_s - SWEEP_MIN, 0.05)
	for k in range(n):
		var t0 := span * pow(float(k) / float(n), GATHER_POW)
		var dur := lerpf(SWEEP_MAX, SWEEP_MIN, float(k) / float(maxi(n - 1, 1)))
		dur = clampf(minf(dur, aim_s - t0), 0.05, SWEEP_MAX)
		var side := 1.0 if k % 2 == 0 else -1.0
		out.append({"a0": side * half * rng.randf_range(0.75, 1.0), "t0": t0, "dur": dur})
	return out


## How far line `l` of a plan has come at `t`: 0 not yet shown, (0, 1) sweeping, 1 arrived.
static func line_progress(l: Dictionary, t: float) -> float:
	var t0 := float(l["t0"])
	if t < t0:
		return 0.0
	return clampf((t - t0) / maxf(float(l["dur"]), 0.01), 0.0, 1.0)


## The angle off the aim line `l` shows at progress `u` (0 < u < 1): its start angle, eased in to nothing.
static func line_angle(l: Dictionary, u: float) -> float:
	return float(l["a0"]) * (1.0 - smoothstep(0.0, 1.0, u))


func begin() -> void:
	_aims.clear()


## One sniper aiming: the lines of `lines` at `t` of `total` seconds from the muzzle `from` round the line to `to` (the
## point the aim follows: the hero's feet).
func aim(from: Vector3, to: Vector3, t: float, total: float, lines: Array) -> void:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := d.length()
	if dist < 0.1:
		return
	_aims.append({"mode": "aim", "from": from, "dir": d / dist, "d": dist, "t": t, "total": total, "lines": lines})


## One sniper's locked line: from `from` along `dir` (flat, unit), meeting the hero's spot at `d`, `t` of `total` seconds
## into the hold; `length` and `width` the beam's to come.
func lock(from: Vector3, dir: Vector3, d: float, t: float, total: float, length: float, width: float) -> void:
	_aims.append({"mode": "lock", "from": from, "dir": dir, "d": d, "t": t, "total": total, "length": length, "width": width})


## The shot: the beam from `from` along `dir` (flat, unit) for `length` m, `width` wide, its height easing to the chest
## at `d` (the locked spot); it shows `seconds`, then `sparks` seconds of sparks fade along it.
func beam(from: Vector3, dir: Vector3, length: float, width: float, d: float, seconds: float, sparks: float) -> void:
	var b := {"from": from, "dir": dir, "length": length, "width": width, "d": maxf(d, 0.1), "h0": from.y - _h(from.x, from.z),
		"t": 0.0, "dur": maxf(seconds, 0.02), "fade": maxf(sparks, 0.0)}
	_beams.append(b)
	var n := int(length * SPARKS_PER_M)
	var side := Vector3(-dir.z, 0.0, dir.x)
	for k in range(n):
		var s := _rng.randf_range(0.0, length)
		var p := _path_point(b, s) + side * _rng.randf_range(-0.35, 0.35) * width * 2.0 + Vector3(0, _rng.randf_range(-0.25, 0.25), 0)
		var v := side * _rng.randf_range(-0.5, 0.5) + Vector3(0, _rng.randf_range(SPARK_RISE.x, SPARK_RISE.y), 0) + dir * _rng.randf_range(-0.3, 0.6)
		_sparks.append({"p": p, "v": v, "t": -_rng.randf_range(0.0, 0.12), "life": maxf(sparks, 0.1) * _rng.randf_range(0.55, 1.0),
			"size": _rng.randf_range(SPARK_SIZE.x, SPARK_SIZE.y), "ph": _rng.randf() * TAU, "col": SPARK_COLS[k % SPARK_COLS.size()]})


## Anything left to show (the tests; the brain's tick skips its hand-over while nothing does).
func busy() -> bool:
	return not _aims.is_empty() or not _beams.is_empty() or not _sparks.is_empty()


# ---------------------------------------------------------------- the drawing

func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt): the camera and what is on screen follow it
	delta = Lockstep.dt(delta)
	var dt := delta * time_scale
	for b: Dictionary in _beams:
		b["t"] = float(b["t"]) + dt
	_beams = _beams.filter(func(b: Dictionary) -> bool: return float(b["t"]) < float(b["dur"]) + float(b.get("fade", 0.0)))
	for sp: Dictionary in _sparks:
		sp["t"] = float(sp["t"]) + dt
		if float(sp["t"]) > 0.0:
			sp["p"] = (sp["p"] as Vector3) + (sp["v"] as Vector3) * dt
			sp["v"] = (sp["v"] as Vector3) * (1.0 - minf(dt * 1.5, 0.5))
	_sparks = _sparks.filter(func(sp: Dictionary) -> bool: return float(sp["t"]) < float(sp["life"]))
	redraw()


## Rebuilds the two meshes from what shows now (every frame from _process; a capture or a test may call it).
func redraw() -> void:
	drawn_lines = 0
	drawn_beams = _beams.size()
	drawn_sparks = 0
	if _glow_mesh == null:
		return
	if _drawn_any:
		_glow_mesh.clear_surfaces()
		_line_mesh.clear_surfaces()
		_drawn_any = false
	if not busy():
		return
	var cam: Camera3D = null
	var vp := get_viewport()
	if vp:
		cam = vp.get_camera_3d()
	if cam:
		_cam_pos = cam.global_position
		_cam_right = cam.global_transform.basis.x
		_cam_up = cam.global_transform.basis.y
	_glow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_drawn_any = true
	for a: Dictionary in _aims:
		if str(a["mode"]) == "aim":
			_draw_aim(a)
		else:
			_draw_lock(a)
	for b: Dictionary in _beams:
		_draw_beam(b)
	for sp: Dictionary in _sparks:
		_draw_spark(sp)
	# a surface needs a triangle: an empty one is an error
	_quad(_glow_mesh, Vector3(0, -50, 0), Vector3(0.001, 0, 0), Vector3(0, 0.001, 0), Color(0, 0, 0, 0))
	_quad(_line_mesh, Vector3(0, -50, 0), Vector3(0.001, 0, 0), Vector3(0, 0.001, 0), Color(0, 0, 0, 0))
	_glow_mesh.surface_end()
	_line_mesh.surface_end()


func _draw_aim(a: Dictionary) -> void:
	var from: Vector3 = a["from"]
	var dir: Vector3 = a["dir"]
	var d := float(a["d"])
	var t := float(a["t"])
	var total := maxf(float(a["total"]), 0.01)
	var lines: Array = a["lines"]
	var path := {"from": from, "dir": dir, "d": d, "h0": from.y - _h(from.x, from.z)}
	var arrived := 0
	for l: Dictionary in lines:
		var u := line_progress(l, t)
		if u >= 1.0:
			arrived += 1
			continue
		if u <= 0.0:
			continue
		var ang := line_angle(l, u)
		var ld := dir.rotated(Vector3.UP, ang)
		var lp := {"from": from, "dir": ld, "d": d, "h0": path["h0"]}
		# in faint at the cone's side, brighter as it closes on him
		var al := lerpf(0.3, 0.95, smoothstep(0.0, 1.0, u)) * smoothstep(0.0, 0.12, u)
		_ribbon(lp, 0.0, d + OVERSHOOT, LINE_W, Color(RED, al), Color(RED, al * 0.25))
		drawn_lines += 1
	# the line on the hero: every line that has arrived makes it brighter; the scope glints harder as the aim runs on
	var k := float(arrived) / float(maxi(lines.size(), 1))
	if arrived > 0:
		_ribbon(path, 0.0, d + OVERSHOOT, CENTRE_W, Color(RED, 0.25 + 0.7 * k), Color(RED, 0.1 + 0.3 * k))
		drawn_lines += 1
	_glint(from, 0.18 + 0.32 * (t / total), 0.55 + 0.45 * sin(t * 18.0))


func _draw_lock(a: Dictionary) -> void:
	var from: Vector3 = a["from"]
	var dir: Vector3 = a["dir"]
	var d := float(a["d"])
	var t := float(a["t"])
	var total := maxf(float(a["total"]), 0.01)
	var f := clampf(t / total, 0.0, 1.0)
	var path := {"from": from, "dir": dir, "d": d, "h0": from.y - _h(from.x, from.z)}
	# blinking faster and faster towards the shot (the phase is the integral of the rising rate)
	var hz0 := LOCK_BLINK_HZ.x
	var hz1 := LOCK_BLINK_HZ.y
	var phase := TAU * (hz0 * t + (hz1 - hz0) * t * f * 0.5)
	var blink := 0.6 + 0.4 * (0.5 + 0.5 * cos(phase))
	_ribbon(path, 0.0, d + OVERSHOOT, LOCK_W, Color(RED, blink), Color(RED, blink * 0.8))
	# the rest of the beam's path, faint
	var length := float(a.get("length", 60.0))
	if length > d + OVERSHOOT:
		_ribbon(path, d + OVERSHOOT, length, LOCK_W * 0.6, Color(RED, 0.35 * blink), Color(RED, 0.0))
	drawn_lines += 1
	_glint(from, 0.5 + 0.15 * f, blink)


func _draw_beam(b: Dictionary) -> void:
	var t := float(b["t"])
	var dur := float(b["dur"])
	if t >= dur:
		# the afterglow: the path stays red, fading out with the sparks
		var fade := maxf(float(b.get("fade", 0.0)), 0.01)
		var ag := AFTERGLOW_A * (1.0 - smoothstep(0.0, 1.0, (t - dur) / fade))
		if ag > 0.005:
			_ribbon(b, 0.0, float(b["length"]), float(b["width"]) * AFTERGLOW_W, Color(RED, ag), Color(RED, ag * 0.6), _glow_mesh, 0.0)
		return
	var f := clampf(t / dur, 0.0, 1.0)
	var a := 1.0 if f < BEAM_FLASH else 1.0 - smoothstep(BEAM_FLASH, 1.0, f)
	var w := float(b["width"])
	var length := float(b["length"])
	# the glow, then the white-hot core (a little thinner as it fades)
	_ribbon(b, 0.0, length, w * GLOW_WIDTH, Color(RED, 0.75 * a), Color(RED, 0.45 * a), _glow_mesh, 0.0)
	_ribbon(b, 0.0, length, w * lerpf(0.7, 0.4, f), Color(HOT, a), Color(HOT, a * 0.85), _line_mesh, 0.0)
	_glint(b["from"], 0.9 * (1.0 - f) + 0.3, a)


func _draw_spark(sp: Dictionary) -> void:
	var t := float(sp["t"])
	if t <= 0.0:
		return
	var f := t / maxf(float(sp["life"]), 0.01)
	var sh := 0.55 + 0.45 * sin(t * SPARK_SHIMMER + float(sp["ph"]))
	var a := (1.0 - f * f) * sh
	var s := float(sp["size"]) * (1.0 - 0.5 * f)
	var col: Color = sp["col"]
	var p: Vector3 = sp["p"]
	# a soft red halo and a hot heart, both fading to nothing at their edges (no hard squares)
	_soft(_glow_mesh, p, _cam_right * s * 2.2, _cam_up * s * 2.2, Color(col, a * 0.6))
	_soft(_line_mesh, p, _cam_right * s, _cam_up * s, Color(col.lerp(HOT, 0.2), a))
	drawn_sparks += 1


## The scope's glint: a small soft star at the muzzle, `s` m across at alpha `a` (a red halo, a white heart, two rays).
func _glint(at: Vector3, s: float, a: float) -> void:
	_soft(_glow_mesh, at, _cam_right * s, _cam_up * s, Color(RED, 0.55 * a))
	_soft(_line_mesh, at, _cam_right * s * 0.35, _cam_up * s * 0.35, Color(HOT, a))
	_soft(_line_mesh, at, _cam_right * s * 1.3, _cam_up * s * 0.07, Color(HOT, 0.85 * a))
	_soft(_line_mesh, at, _cam_right * s * 0.07, _cam_up * s * 1.3, Color(HOT, 0.85 * a))


## A soft diamond: `c` at its middle, nothing at its four points (at +- `rx`, at +- `uy`).
func _soft(m: ImmediateMesh, at: Vector3, rx: Vector3, uy: Vector3, c: Color) -> void:
	var e := Color(c, 0.0)
	_tri(m, at, c, at + rx, e, at + uy, e)
	_tri(m, at, c, at + uy, e, at - rx, e)
	_tri(m, at, c, at - rx, e, at - uy, e)
	_tri(m, at, c, at - uy, e, at + rx, e)


## A point `s` m along a path (see the header): on the sand at the path's height there.
func _path_point(path: Dictionary, s: float) -> Vector3:
	var from: Vector3 = path["from"]
	var dir: Vector3 = path["dir"]
	var x := from.x + dir.x * s
	var z := from.z + dir.z * s
	var hh := lerpf(float(path["h0"]), CHEST, clampf(s / maxf(float(path["d"]), 0.1), 0.0, 1.0))
	return Vector3(x, _h(x, z) + hh, z)


## A ribbon `w` wide along a path from `s0` to `s1` m, turned to the camera, `c0` at its start and `c1` at its end, with
## its glow LINE_GLOW x as wide in the glow mesh (`glow_k` of its alpha; 0 = none) unless `mesh` is the glow mesh itself.
func _ribbon(path: Dictionary, s0: float, s1: float, w: float, c0: Color, c1: Color, mesh: ImmediateMesh = null, glow_k: float = 0.45) -> void:
	if s1 <= s0:
		return
	var m: ImmediateMesh = mesh if mesh != null else _line_mesh
	var n := maxi(int(ceilf((s1 - s0) / STEP)), 1)
	var prev := _path_point(path, s0)
	for k in range(1, n + 1):
		var s := s0 + (s1 - s0) * float(k) / float(n)
		var p := _path_point(path, s)
		var ca := c0.lerp(c1, float(k - 1) / float(n))
		var cb := c0.lerp(c1, float(k) / float(n))
		var seg := p - prev
		var mid := (p + prev) * 0.5
		var side := seg.cross(_cam_pos - mid)
		side = side.normalized() if side.length_squared() > 0.000001 else _cam_right
		_band(m, prev, p, side * w * 0.5, ca, cb)
		if glow_k > 0.0 and m != _glow_mesh:
			_band(_glow_mesh, prev, p, side * w * 0.5 * LINE_GLOW, Color(ca, ca.a * glow_k), Color(cb, cb.a * glow_k))
		prev = p


func _band(m: ImmediateMesh, p0: Vector3, p1: Vector3, side: Vector3, c0: Color, c1: Color) -> void:
	# a band feathered at its edges: the middle at full, the edges see-through
	var e0 := Color(c0, 0.0)
	var e1 := Color(c1, 0.0)
	_tri(m, p0 - side, e0, p0, c0, p1, c1)
	_tri(m, p0 - side, e0, p1, c1, p1 - side, e1)
	_tri(m, p0, c0, p0 + side, e0, p1 + side, e1)
	_tri(m, p0, c0, p1 + side, e1, p1, c1)


func _quad(m: ImmediateMesh, at: Vector3, rx: Vector3, uy: Vector3, c: Color) -> void:
	_tri(m, at - rx - uy, c, at + rx - uy, c, at + rx + uy, c)
	_tri(m, at - rx - uy, c, at + rx + uy, c, at - rx + uy, c)


static func _tri(m: ImmediateMesh, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	m.surface_set_color(ca)
	m.surface_add_vertex(a)
	m.surface_set_color(cb)
	m.surface_add_vertex(b)
	m.surface_set_color(cc)
	m.surface_add_vertex(c)


func _h(x: float, z: float) -> float:
	return float(height_fn.call(x, z)) if height_fn.is_valid() else 0.0
