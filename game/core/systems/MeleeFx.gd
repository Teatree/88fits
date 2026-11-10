## The melee weapons' strokes drawn as effects, not weapons (pass 136, lane MELEE; Garry, pass 134: "Change the sword
## and the spear to be less actual weapons, and more thrusts or swings effects that you see instead of the weapon
## itself"; pass 136: "Spear: Should look very much like a good thrust VFX, look at fighting games for reference").
## A Thruster makes one while its weapon aims by the new rule (Aim.covers) and calls arc() at the start of every swing
## and thrust() at the start of every thrust; the blade models stay hidden then. Three small pools, every entry one quad
## with its own ShaderMaterial (the Compatibility renderer: no per-instance uniforms), reused oldest first:
##   arc    a crescent slash flat just above the sand round the Outlaw (core/shaders/melee_arc.gdshader): revealed by
##          the swing's own ease over `sweep` seconds, then gone over `fade`; it rides with him (the hit test cuts round
##          where he stands each tick).
##   thrust a stab flat at his waist (core/shaders/melee_thrust.gdshader; pass 137, lane SPEAR: a spearhead leads it): the
##          head shows at his hand, darts out to the reach in `ext`, lands with the hit (land(): the impact star, else a
##          glint), snaps back leaving an afterimage, while the streak behind it thins away from the hand over `fade`.
##   flash  the star at the point (core/shaders/melee_flash.gdshader; a hit's has a shock ring and a dark rim).
## Pass 138 (lane MELEE; Garry: "Sword is barely visible, should be wider and more noticeable", "Spear tip looks
## childish"): each stroke has styles, the weapon JSON's `params.fx_style` (the look's `style`, MeleeFx.style_of):
##   a swing  "crescent" (the default: a bold flag-shaped crescent, core/shaders/melee_slash.gdshader style 1), "cel"
##            (the same hard-edged with a thick outline, style 2), "classic" (pass 136's thin arc, melee_arc.gdshader);
##   a thrust "lance" (the default: a spindle of light to a needle point, air rings, a pierce on a hit,
##            core/shaders/melee_lance.gdshader style 1), "wind" (a needle with two wind ribbons and an energy diamond,
##            style 2), "spearhead" (pass 137's drawn head, melee_thrust.gdshader).
## Looks only: no dice (randf only for each effect's own seed), nothing that changes a hit. Ticked by its Thruster
## (WeaponBehavior._process: the replay's delta, paused with the game), so a capture can step it by hand.
## Pass 139 (lane SWING; Garry: "The sword swings are constantly clipping through the ground. Either just give them a
## rendering prio or handle the surface topology in some way"): a swing's arc is laid on the ground under it, not on a
## flat plane at his feet. The map's height_at is sampled under the crescent (his feet and GROUND_SPOKES spokes across
## the arc's angle at the GROUND_RADII shares of its reach), a plane fitted to the samples (least squares, its slope at
## most GROUND_SLOPE_MAX), raised by the most any sample stands above it (a crest under the middle) and ARC_LIFT over
## that; refitted whenever he has moved GROUND_REFIT metres. Its shaders then draw it GROUND_PULL metres nearer the
## camera along the eye's ray (the same pixels, only the depth test sees it nearer: the `pull` uniform), so a bump
## between the samples does not cut it either, while a creature or a prop standing in front of it still hides it. The
## thrust and the star have no depth test already (pass 137), so they never sank. `ground_follow` off (a tool comparing)
## lays it flat at his feet as before.
class_name MeleeFx
extends Node3D

const ARC_MAX := 8
const THRUST_MAX := 6
const FLASH_MAX := 6
## how high over his feet an arc lies, and a thrust
const ARC_LIFT := 0.3
const THRUST_LIFT := 0.62
## the arc's quad reaches past its rim by this share (the glow and the dark line outside the edge)
const ARC_PAD := 1.12
## the thrust's quad is this many times the lane's half width (glow, afterimage, speed lines)
const THRUST_QUAD := 3.0
## pass 137 (lane SPEAR): the spearhead's length and half width (metres, x the look's `tip`), how long it shows pulled
## back at his hand before it darts, how fast it snaps back after the hold, how long its afterimage lingers
const TIP_LEN := 1.0
const TIP_W := 0.25
const THRUST_ANTI := 0.08
const THRUST_SNAP := 0.09
const THRUST_GHOST := 0.16
## pass 138: the styles (the first of each list the default), a new-style swing's dissolve (at least this long), a
## lance's light running on through the point on a hit, its width (x the lane's half width, clamped), its needle
const SLASH_STYLES := ["crescent", "cel", "classic"]
const STAB_STYLES := ["lance", "wind", "spearhead"]
const SLASH_FADE := 0.22
const PIERCE_T := 0.14
const LANCE_W := 0.62
const LANCE_W_MIN := 0.1
const LANCE_W_MAX := 0.32
const NEEDLE := 0.55
## pass 139 (lane SWING): the arc laid on the ground (see the top): its samples, how often it is refitted, its steepest
## tilt (rise per metre), how far nearer the camera its shaders draw it (metres)
const GROUND_SPOKES := 7
const GROUND_RADII := [0.4, 0.75, 1.1]
const GROUND_REFIT := 0.25
const GROUND_SLOPE_MAX := 1.0
const GROUND_PULL := 0.45

## pass 139: off lays every arc flat at his feet as before (tools comparing the two)
static var ground_follow := true

static var _arc_shader: Shader
static var _thrust_shader: Shader
static var _flash_shader: Shader
static var _slash_shader: Shader
static var _lance_shader: Shader
static var _quad_xz: ArrayMesh
static var _quad_strip: ArrayMesh
static var _quad_xy: ArrayMesh

var _arcs: Array = []
var _thrusts: Array = []
var _flashes: Array = []
## counts (tests): arcs, thrusts and flashes begun; the last arc's and thrust's shape
var arcs_made := 0
var thrusts_made := 0
var flashes_made := 0
var last_arc: Dictionary = {}
var last_thrust: Dictionary = {}
## pass 137 (tests): thrusts landed on a hit (the impact star) and on a miss (a glint), where the last star stood
var impacts_made := 0
var glints_made := 0
var last_flash_at := Vector3.ZERO
## pass 139: the ground the arcs are laid on (anything with height_at(x, z)); null asks its Thruster's game for its map
var map: Object = null
## pass 139 (tests): ground fits made
var fits_made := 0


func _init() -> void:
	name = "MeleeFx"


static func _shaders() -> void:
	if _arc_shader == null:
		_arc_shader = load("res://core/shaders/melee_arc.gdshader")
		_thrust_shader = load("res://core/shaders/melee_thrust.gdshader")
		_flash_shader = load("res://core/shaders/melee_flash.gdshader")
		_slash_shader = load("res://core/shaders/melee_slash.gdshader")
		_lance_shader = load("res://core/shaders/melee_lance.gdshader")
	if _quad_xz == null:
		# x -1..1, z -1..1 on the ground plane (the arc)
		_quad_xz = _quad([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])
		# x -1..1, z 0..-1 (the thrust, base at the origin, point down -Z)
		_quad_strip = _quad([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)])
		# x, y -1..1 (the flash, faced to the camera in its shader)
		_quad_xy = _quad([Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(1, -1, 0), Vector3(-1, -1, 0)])


static func _quad(v: Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(v)
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	return m


func _entry(pool: Array, cap: int, mesh: Mesh, shader: Shader) -> Dictionary:
	var e: Dictionary = {}
	if pool.size() < cap:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = shader
		# over the sand marks, under nothing else that is see-through
		m.render_priority = 2 if shader == _flash_shader else 1
		mi.material_override = m
		add_child(mi)
		e = {"mi": mi, "mat": m, "live": false, "t": 0.0}
		pool.append(e)
		return e
	# a free one, else the oldest
	var oldest: Dictionary = pool[0]
	for p: Dictionary in pool:
		if not bool(p["live"]):
			return p
		if float(p["t"]) > float(oldest["t"]):
			oldest = p
	return oldest


## The style a stroke of `kind` ("slash" or "stab") draws in: `st` when it names one of that kind's, else the default.
static func style_of(kind: String, st: String) -> String:
	var list: Array = SLASH_STYLES if kind == "slash" else STAB_STYLES
	return st if list.has(st) else str(list[0])


## A swing: centred on `yaw` (the Thruster's yaw sense), `half_w` radians each side, `reach` deep, revealed from the
## `sign` end (+1 starts at -half_w, the hit test's swing k even) over `sweep` seconds, gone over `fade`. `look`:
## edge, smear, core (Color), edge_w (metres), smear_a, inner (share of the reach the crescent reaches in to), crackle,
## tipped (0..1), ease ("cos": the slice's own, else linear), style (pass 138: style_of("slash", ...)).
func arc(anchor: Node3D, yaw: float, half_w: float, reach: float, sweep: float, fade: float, sign: float, look: Dictionary = {}) -> void:
	if Run.sim_mode or anchor == null:
		return
	_shaders()
	var e := _entry(_arcs, ARC_MAX, _quad_xz, _arc_shader)
	var R := maxf(reach, 0.2) * ARC_PAD
	var m: ShaderMaterial = e["mat"]
	var style := style_of("slash", str(look.get("style", "")))
	var bold := style != "classic"
	var want: Shader = _slash_shader if bold else _arc_shader
	if m.shader != want:
		m.shader = want
	if bold:
		m.set_shader_parameter("style", 2 if style == "cel" else 1)
		m.set_shader_parameter("diss", 0.0)
	m.set_shader_parameter("half_w", clampf(half_w, 0.05, PI))
	m.set_shader_parameter("r_out", 1.0 / ARC_PAD)
	m.set_shader_parameter("r_in", float(look.get("inner", 0.3)) / ARC_PAD)
	m.set_shader_parameter("sweep_sign", 1.0 if sign >= 0.0 else -1.0)
	m.set_shader_parameter("edge_w", float(look.get("edge_w", 0.1)) / R)
	m.set_shader_parameter("smear_a", float(look.get("smear_a", 0.35)))
	m.set_shader_parameter("crackle", float(look.get("crackle", 0.0)))
	m.set_shader_parameter("tipped", float(look.get("tipped", 0.0)))
	m.set_shader_parameter("trail", float(look.get("trail", 1.4)))
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("edge_col", look.get("edge", Color(0.82, 0.92, 1.0)))
	m.set_shader_parameter("smear_col", look.get("smear", Color(0.55, 0.7, 0.95)))
	m.set_shader_parameter("core_col", look.get("core", Color.WHITE))
	m.set_shader_parameter("shade_a", float(look.get("shade_a", 0.8 if bold else 0.4)))
	e["live"] = true
	e["t"] = 0.0
	e["anchor"] = anchor
	e["lift"] = float(look.get("lift", ARC_LIFT))
	e["sweep"] = maxf(sweep, 0.01)
	e["fade"] = maxf(fade, SLASH_FADE if bold else 0.01)
	e["bold"] = bold
	e["style"] = style
	e["cos"] = str(look.get("ease", "cos")) == "cos"
	e["R"] = R
	# pass 139: the shape the ground is sampled under, a fresh fit, the shaders' pull
	e["yaw"] = yaw
	e["half_w"] = clampf(half_w, 0.05, PI)
	e["reach"] = maxf(reach, 0.2)
	e.erase("fit")
	m.set_shader_parameter("pull", GROUND_PULL if ground_follow else 0.0)
	var mi: MeshInstance3D = e["mi"]
	mi.visible = true
	_place(e)
	_arc_frame(e)
	arcs_made += 1
	last_arc = {"yaw": yaw, "half_w": half_w, "reach": reach, "sign": sign, "style": style}


## A thrust down `dir` from `anchor` (his chest's place on the ground plane), its point reaching `length` from him (the
## hit's own reach), the lane `lane_half` wide each side. Pass 137 (lane SPEAR): a spearhead leads it. The head shows
## pulled back at his hand for the last THRUST_ANTI of `delay` (a glint gathering), darts out to the reach in `ext` with a
## hard stop, rides a small overshoot over `hold` (the hit lands as it arrives: land(), else a small glint), then snaps
## back over THRUST_SNAP leaving a glowing afterimage, while the streak behind it thins away from the hand over `fade`.
## `look`: glow, body, core (Color), width (x the lane), lines (speed lines 0..1), flash (Color), flash_size (metres),
## ghost (0..1), heat (0..1: the head glows `heat_col`), crackle (0..1), tip (the head's size, x1).
func thrust(anchor: Node3D, dir: Vector3, length: float, lane_half: float, delay: float, ext: float, hold: float, fade: float, look: Dictionary = {}) -> void:
	if Run.sim_mode or anchor == null:
		return
	_shaders()
	var e := _entry(_thrusts, THRUST_MAX, _quad_strip, _thrust_shader)
	var style := style_of("stab", str(look.get("style", "")))
	var lance := style != "spearhead"
	var m: ShaderMaterial = e["mat"]
	var want: Shader = _lance_shader if lance else _thrust_shader
	if m.shader != want:
		m.shader = want
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var wk := float(look.get("width", 1.0))
	var hw := maxf(lane_half, 0.05) * wk
	var qw := maxf(hw * THRUST_QUAD, 0.75)
	var base := float(look.get("base", 0.45))
	# the point's full reach from the base (the hit's reach from his centre), the quad past it for the overshoot and the
	# glint, and behind the base for the head pulled back at his hand
	var full := maxf(maxf(length, 0.3) - base, 0.4)
	var tip := float(look.get("tip", 1.0)) * (1.0 + 0.25 * (wk - 1.0))
	var tip_len := TIP_LEN * tip
	var back := tip_len * 1.6
	var qlen := back + full + 0.6
	if lance:
		# pass 138: a thrust of light; behind the hand only room for the gathering glint, past the point room for the
		# overshoot and the pierce
		back = 0.3
		tip_len = NEEDLE * tip
		qlen = back + full + 1.1
		var lw := clampf(hw * LANCE_W, LANCE_W_MIN, LANCE_W_MAX)
		qw = maxf(qw, lw * 3.2 + 0.25)
		m.set_shader_parameter("style", 2 if style == "wind" else 1)
		m.set_shader_parameter("full", full)
		m.set_shader_parameter("lance_w", lw)
		m.set_shader_parameter("needle", tip_len)
		m.set_shader_parameter("pierce", 0.0)
		m.set_shader_parameter("ring_t", -1.0)
		m.set_shader_parameter("shade_a", float(look.get("shade_a", 0.7)))
	else:
		m.set_shader_parameter("streak_w", minf(maxf(TIP_W * tip * 0.95, hw * 0.8), TIP_W * tip * 1.1))
		m.set_shader_parameter("tip_len", tip_len)
		m.set_shader_parameter("tip_w", TIP_W * tip)
		m.set_shader_parameter("shade_a", float(look.get("shade_a", 0.3)))
	m.set_shader_parameter("quad_len", qlen)
	m.set_shader_parameter("quad_half", qw)
	m.set_shader_parameter("s0", back)
	m.set_shader_parameter("glow_col", look.get("glow", Color(0.45, 0.68, 1.0)))
	m.set_shader_parameter("body_col", look.get("body", Color(0.8, 0.92, 1.0)))
	m.set_shader_parameter("core_col", look.get("core", Color.WHITE))
	m.set_shader_parameter("heat", float(look.get("heat", 0.0)))
	m.set_shader_parameter("heat_col", look.get("heat_col", look.get("glow", Color(1.0, 0.35, 0.1))))
	m.set_shader_parameter("crackle", float(look.get("crackle", 0.0)))
	m.set_shader_parameter("seed", randf() * 100.0)
	e["lance"] = lance
	e["style"] = style
	e["pierce_at"] = -1.0
	e["live"] = true
	e["t"] = 0.0
	e["anchor"] = anchor
	e["lift"] = float(look.get("lift", THRUST_LIFT))
	e["dir"] = d
	e["base"] = base - back
	e["full"] = full
	e["back"] = back
	e["tip_len"] = tip_len
	e["len"] = maxf(length, 0.3)
	e["delay"] = maxf(delay, 0.0)
	e["ext"] = maxf(ext, 0.01)
	e["hold"] = maxf(hold, 0.0)
	e["fade"] = maxf(fade, 0.01)
	e["lines"] = float(look.get("lines", 1.0))
	e["ghost"] = float(look.get("ghost", 1.0))
	e["flash"] = look.get("flash", look.get("glow", Color(0.45, 0.68, 1.0)))
	e["flash_core"] = look.get("core", Color.WHITE)
	e["flash_size"] = float(look.get("flash_size", 1.0))
	e["flashed"] = false
	e["hit"] = false
	var mi: MeshInstance3D = e["mi"]
	mi.scale = Vector3(qw, 1.0, qlen)
	mi.rotation = Vector3(0, atan2(-d.x, -d.z), 0)
	_place(e)
	_thrust_frame(e)
	thrusts_made += 1
	last_thrust = {"dir": d, "length": length, "lane_half": lane_half, "style": style}


## The stroke's hit moment (its Thruster, right after the strike): every thrust whose head has arrived and not yet landed
## lands now, with the impact star, its shock ring and a dark rim when `hit`, else a small glint.
func land(hit: bool) -> void:
	for e: Dictionary in _thrusts:
		if not bool(e["live"]) or bool(e["flashed"]):
			continue
		if float(e["t"]) - float(e["delay"]) < float(e["ext"]) * 0.5:
			continue
		_land(e, hit)


func _land(e: Dictionary, hit: bool) -> void:
	e["flashed"] = true
	e["hit"] = hit
	var d: Vector3 = e["dir"]
	var at := (e["mi"] as MeshInstance3D).global_position + d * (float(e["full"]) + float(e["back"]))
	if hit:
		flash(at, e["flash"], e["flash_core"], float(e["flash_size"]), 0.2, d, 1.0)
		impacts_made += 1
		# pass 138: a lance's light runs on through the point
		e["pierce_at"] = float(e["t"])
	else:
		flash(at, e["flash"], e["flash_core"], float(e["flash_size"]) * 0.45, 0.14, d, 0.0)
		glints_made += 1
	last_flash_at = at


## A star at `at` (the point), `size` metres, gone over `life`; `dir` lays its long rays along the thrust on screen;
## `ring` (pass 137) adds the hit's shock ring and a dark rim under the rays.
func flash(at: Vector3, col: Color, core: Color, size: float, life: float = 0.16, dir: Vector3 = Vector3.ZERO, ring: float = 0.0) -> void:
	if Run.sim_mode:
		return
	_shaders()
	var e := _entry(_flashes, FLASH_MAX, _quad_xy, _flash_shader)
	var m: ShaderMaterial = e["mat"]
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("core_col", core)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("ring", ring)
	m.set_shader_parameter("ink", ring)
	var rot := 0.0
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and dir.length_squared() > 0.0001:
		var a := cam.unproject_position(at)
		var b := cam.unproject_position(at + dir.normalized())
		# screen y runs down, the quad's up: the angle on screen, flipped
		rot = -atan2(b.y - a.y, b.x - a.x)
	m.set_shader_parameter("rot", rot)
	m.set_shader_parameter("t", 0.0)
	e["live"] = true
	e["t"] = 0.0
	e["life"] = maxf(life, 0.02)
	var mi: MeshInstance3D = e["mi"]
	mi.visible = true
	mi.global_position = at
	flashes_made += 1


func _place(e: Dictionary) -> void:
	var a: Node3D = e.get("anchor")
	if a == null or not is_instance_valid(a):
		return
	var mi: MeshInstance3D = e["mi"]
	if e.has("R"):
		_lay_arc(e, a.global_position)
		return
	var p := a.global_position + Vector3(0, float(e["lift"]), 0)
	if e.has("dir"):
		p += (e["dir"] as Vector3) * float(e["base"])
	mi.global_position = p


## Pass 139 (lane SWING): an arc's quad laid on the ground under it at `at` (his feet): the fitted plane (refitted once
## he has moved GROUND_REFIT metres), never under his feet (a jump carries it up with him), ARC_LIFT over it; flat at
## his feet + ARC_LIFT with ground_follow off or no map.
func _lay_arc(e: Dictionary, at: Vector3) -> void:
	var mi: MeshInstance3D = e["mi"]
	var rr := float(e["R"])
	var b3 := Basis(Vector3.UP, float(e["yaw"])) * Basis.from_scale(Vector3(rr, 1.0, rr))
	var y := at.y
	var m := _ground() if ground_follow else null
	if m != null:
		var o: Vector2 = e.get("fit_o", Vector2.INF)
		if not e.has("fit") or Vector2(at.x, at.z).distance_to(o) > GROUND_REFIT:
			e["fit"] = ground_fit(m, at, float(e["yaw"]), float(e["half_w"]), float(e["reach"]))
			e["fit_o"] = Vector2(at.x, at.z)
			o = e["fit_o"]
		var f: Vector3 = e["fit"]
		y = maxf(f.x + f.y * (at.x - o.x) + f.z * (at.z - o.y), at.y)
		b3 = MapBase.ground_basis(Vector3(-f.y, 1.0, -f.z)) * b3
	mi.global_transform = Transform3D(b3, Vector3(at.x, y + float(e["lift"]), at.z))


## The map the arcs lie on: `map` when set, else its Thruster's game's.
func _ground() -> Object:
	if map != null and is_instance_valid(map):
		return map if map.has_method("height_at") else null
	var b := get_parent()
	var g = b.get("game") if b != null else null
	var gm = g.get("map") if g is Object and is_instance_valid(g) else null
	if gm is Object and is_instance_valid(gm) and gm.has_method("height_at"):
		map = gm
		return gm
	return null


## Pass 139: the plane under a crescent centred on `yaw` (the arc's -Z turned by it), `half_w` each side, `reach` deep,
## round `at`: x = its height at `at` raised by the most any sample stands above it, y and z its rise per metre along x
## and z (each at most GROUND_SLOPE_MAX). The samples: `at` and GROUND_SPOKES spokes across the angle (round the whole
## circle when it is one) at each of the GROUND_RADII shares of the reach.
func ground_fit(m: Object, at: Vector3, yaw: float, half_w: float, reach: float) -> Vector3:
	fits_made += 1
	var pts: Array[Vector3] = [Vector3(0.0, float(m.height_at(at.x, at.z)), 0.0)]
	var full := half_w >= PI - 0.01
	for r: float in GROUND_RADII:
		for k in range(GROUND_SPOKES):
			var u := float(k) / float(GROUND_SPOKES) if full else float(k) / float(GROUND_SPOKES - 1)
			var a := yaw + (TAU * u if full else half_w * (2.0 * u - 1.0))
			var dx := -sin(a) * reach * r
			var dz := -cos(a) * reach * r
			pts.append(Vector3(dx, float(m.height_at(at.x + dx, at.z + dz)), dz))
	# least squares h = h0 + gx dx + gz dz
	var n := float(pts.size())
	var sx := 0.0
	var sz := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sh := 0.0
	var shx := 0.0
	var shz := 0.0
	for p: Vector3 in pts:
		sx += p.x
		sz += p.z
		sxx += p.x * p.x
		szz += p.z * p.z
		sxz += p.x * p.z
		sh += p.y
		shx += p.y * p.x
		shz += p.y * p.z
	var mat := Basis(Vector3(n, sx, sz), Vector3(sx, sxx, sxz), Vector3(sz, sxz, szz))
	var sol := Vector3(sh / n, 0.0, 0.0)
	if absf(mat.determinant()) > 0.0001:
		sol = mat.inverse() * Vector3(sh, shx, shz)
	var gx := clampf(sol.y, -GROUND_SLOPE_MAX, GROUND_SLOPE_MAX)
	var gz := clampf(sol.z, -GROUND_SLOPE_MAX, GROUND_SLOPE_MAX)
	var h0 := sol.x
	if gx != sol.y or gz != sol.z:
		# a clamped slope: the height refitted to it
		h0 = 0.0
		for p: Vector3 in pts:
			h0 += p.y - gx * p.x - gz * p.z
		h0 /= n
	var over := 0.0
	for p: Vector3 in pts:
		over = maxf(over, p.y - (h0 + gx * p.x + gz * p.z))
	return Vector3(h0 + over, gx, gz)


## Every live effect a frame on.
func tick(delta: float) -> void:
	for e: Dictionary in _arcs:
		if bool(e["live"]):
			e["t"] = float(e["t"]) + delta
			_place(e)
			_arc_frame(e)
	for e: Dictionary in _thrusts:
		if bool(e["live"]):
			e["t"] = float(e["t"]) + delta
			_place(e)
			_thrust_frame(e)
	for e: Dictionary in _flashes:
		if bool(e["live"]):
			e["t"] = float(e["t"]) + delta
			var u := float(e["t"]) / float(e["life"])
			if u >= 1.0:
				e["live"] = false
				(e["mi"] as MeshInstance3D).visible = false
			else:
				(e["mat"] as ShaderMaterial).set_shader_parameter("t", u)


func _arc_frame(e: Dictionary) -> void:
	var t := float(e["t"])
	var sw := float(e["sweep"])
	var u := clampf(t / sw, 0.0, 1.0)
	var head := (0.5 - 0.5 * cos(PI * u)) if bool(e["cos"]) else u
	var f := 1.0 - clampf((t - sw) / float(e["fade"]), 0.0, 1.0)
	var m: ShaderMaterial = e["mat"]
	m.set_shader_parameter("head", head)
	if bool(e.get("bold", false)):
		# pass 138: the crescent erodes over the fade (`diss`), its strength going only in the second half
		m.set_shader_parameter("diss", 1.0 - f)
		m.set_shader_parameter("fade", smoothstep(0.0, 0.5, f))
	else:
		m.set_shader_parameter("fade", f * f)
	if t >= sw + float(e["fade"]):
		e["live"] = false
		(e["mi"] as MeshInstance3D).visible = false


func _thrust_frame(e: Dictionary) -> void:
	if bool(e.get("lance", false)):
		_lance_frame(e)
		return
	var t := float(e["t"]) - float(e["delay"])
	var mi: MeshInstance3D = e["mi"]
	var anti := minf(THRUST_ANTI, float(e["delay"]))
	if t < -anti:
		mi.visible = false
		return
	mi.visible = true
	var ext := float(e["ext"])
	var hold := float(e["hold"])
	var fd := float(e["fade"])
	var full := float(e["full"])
	var tl := float(e["tip_len"])
	var m: ShaderMaterial = e["mat"]
	# the head pulled back: its point just in front of his hand
	var pulled := tl * 0.55
	var pt := full
	var pt_a := 1.0
	var tail := 0.0
	var thin := 0.0
	var fade := 1.0
	var lines := float(e["lines"])
	var ghost := 0.0
	var glint := 0.0
	var streak := true
	if t < 0.0:
		# the wind-up: the head at his hand, a glint gathering at its point, no streak yet
		var w := 1.0 + t / maxf(anti, 0.001)
		pt = pulled - 0.12 * w
		pt_a = smoothstep(0.0, 0.5, w)
		glint = w * 0.8
		lines = 0.0
		streak = false
	elif t < ext:
		# the dart: a fast start, a hard stop at the reach
		var q := t / ext
		pt = lerpf(pulled - 0.12, full, 1.0 - pow(1.0 - q, 4.0))
	elif t < ext + hold:
		# the overshoot and settle, the landing's glint
		var h := (t - ext) / maxf(hold, 0.001)
		pt = full + 0.1 * sin(PI * h) * (1.0 - h)
		lines *= 1.0 - h
		glint = 1.0 - h
	else:
		# the snap back (the head) and the fade (the streak, from the hand to the point)
		var r := clampf((t - ext - hold) / THRUST_SNAP, 0.0, 1.0)
		pt = lerpf(full, pulled, r * r)
		pt_a = 1.0 - smoothstep(0.35, 1.0, r)
		ghost = float(e["ghost"]) * (1.0 - clampf((t - ext - hold) / THRUST_GHOST, 0.0, 1.0))
		var f := clampf((t - ext - hold) / fd, 0.0, 1.0)
		lines = 0.0
		tail = pow(f, 0.7)
		thin = f
		fade = 1.0 - f * f
	# the streak's front sits under the head's widest, and stays at the reach once it got there
	var front := (pt if t < ext else full) - tl * 0.45
	if not bool(e["flashed"]) and t >= ext + 0.02:
		_land(e, false)
	m.set_shader_parameter("pt", pt)
	m.set_shader_parameter("pt_a", pt_a)
	m.set_shader_parameter("front", front if streak else -1.0)
	m.set_shader_parameter("tail", tail)
	m.set_shader_parameter("thin", thin)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("lines", lines)
	m.set_shader_parameter("ghost", ghost)
	m.set_shader_parameter("ghost_pt", full)
	m.set_shader_parameter("glint", glint)
	if t >= ext + hold + maxf(fd, THRUST_SNAP):
		e["live"] = false
		mi.visible = false


## Pass 138: a thrust of light (the "lance" and "wind" styles). A glint gathers at his hand for the last THRUST_ANTI of
## the delay, the point darts out to the reach in `ext` with a hard stop (the light drawn from the hand to it, air rings
## left behind), rides a 0.1 m overshoot over `hold` (the hit lands as it arrives: land(), a pierce on a hit, else a
## glint), then the light goes from the hand towards the point, thinning, over `fade`; the point stays at the reach.
func _lance_frame(e: Dictionary) -> void:
	var t := float(e["t"]) - float(e["delay"])
	var mi: MeshInstance3D = e["mi"]
	var anti := minf(THRUST_ANTI, float(e["delay"]))
	if t < -anti:
		mi.visible = false
		return
	mi.visible = true
	var ext := float(e["ext"])
	var hold := float(e["hold"])
	var fd := float(e["fade"])
	var full := float(e["full"])
	var m: ShaderMaterial = e["mat"]
	var start := 0.12
	var pt := full
	var front := full
	var tail := 0.0
	var thin := 0.0
	var fade := 1.0
	var lines := float(e["lines"])
	var glint := 0.0
	if t < 0.0:
		# the gathering: a glint at his hand, nothing drawn yet
		var w := 1.0 + t / maxf(anti, 0.001)
		pt = start
		front = -1.0
		glint = w * 0.8
		lines = 0.0
	elif t < ext:
		# the dart: a fast start, a hard stop at the reach
		var q := t / ext
		pt = lerpf(start, full, 1.0 - pow(1.0 - q, 4.0))
		front = pt
	elif t < ext + hold:
		# the overshoot and settle, the landing's glint
		var h := (t - ext) / maxf(hold, 0.001)
		pt = full + 0.1 * sin(PI * h) * (1.0 - h)
		front = pt
		lines *= 1.0 - h
		glint = 1.0 - h
	else:
		# the light goes from the hand towards the point, thinning
		var f := clampf((t - ext - hold) / fd, 0.0, 1.0)
		front = full
		lines = 0.0
		tail = pow(f, 0.7)
		thin = f
		fade = 1.0 - f * f
	if not bool(e["flashed"]) and t >= ext + 0.02:
		_land(e, false)
	var pierce := 0.0
	var pa := float(e.get("pierce_at", -1.0))
	if pa >= 0.0:
		pierce = 1.0 - clampf((float(e["t"]) - pa) / PIERCE_T, 0.0, 1.0)
	m.set_shader_parameter("pt", pt)
	m.set_shader_parameter("pt_a", 1.0)
	m.set_shader_parameter("front", front)
	m.set_shader_parameter("tail", tail)
	m.set_shader_parameter("thin", thin)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("lines", lines)
	m.set_shader_parameter("glint", glint)
	m.set_shader_parameter("ring_t", t if t >= 0.0 else -1.0)
	m.set_shader_parameter("pierce", pierce)
	if t >= ext + hold + fd:
		e["live"] = false
		mi.visible = false


## How many arcs, thrusts and flashes are showing (tests).
func arcs_live() -> int:
	return _arcs.filter(func(e: Dictionary) -> bool: return bool(e["live"])).size()


func thrusts_live() -> int:
	return _thrusts.filter(func(e: Dictionary) -> bool: return bool(e["live"])).size()


func flashes_live() -> int:
	return _flashes.filter(func(e: Dictionary) -> bool: return bool(e["live"])).size()


## The pools' sizes (tests: capped).
func pool_sizes() -> Vector3i:
	return Vector3i(_arcs.size(), _thrusts.size(), _flashes.size())


## Everything off at once (the switch turned off mid-stroke, a tool).
func clear() -> void:
	for pool: Array in [_arcs, _thrusts, _flashes]:
		for e: Dictionary in pool:
			e["live"] = false
			(e["mi"] as MeshInstance3D).visible = false
