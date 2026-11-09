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
## Looks only: no dice (randf only for each effect's own seed), nothing that changes a hit. Ticked by its Thruster
## (WeaponBehavior._process: the replay's delta, paused with the game), so a capture can step it by hand.
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

static var _arc_shader: Shader
static var _thrust_shader: Shader
static var _flash_shader: Shader
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


func _init() -> void:
	name = "MeleeFx"


static func _shaders() -> void:
	if _arc_shader == null:
		_arc_shader = load("res://core/shaders/melee_arc.gdshader")
		_thrust_shader = load("res://core/shaders/melee_thrust.gdshader")
		_flash_shader = load("res://core/shaders/melee_flash.gdshader")
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


## A swing: centred on `yaw` (the Thruster's yaw sense), `half_w` radians each side, `reach` deep, revealed from the
## `sign` end (+1 starts at -half_w, the hit test's swing k even) over `sweep` seconds, gone over `fade`. `look`:
## edge, smear, core (Color), edge_w (metres), smear_a, inner (share of the reach the crescent reaches in to), crackle,
## tipped (0..1), ease ("cos": the slice's own, else linear).
func arc(anchor: Node3D, yaw: float, half_w: float, reach: float, sweep: float, fade: float, sign: float, look: Dictionary = {}) -> void:
	if Run.sim_mode or anchor == null:
		return
	_shaders()
	var e := _entry(_arcs, ARC_MAX, _quad_xz, _arc_shader)
	var R := maxf(reach, 0.2) * ARC_PAD
	var m: ShaderMaterial = e["mat"]
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
	m.set_shader_parameter("shade_a", float(look.get("shade_a", 0.4)))
	e["live"] = true
	e["t"] = 0.0
	e["anchor"] = anchor
	e["lift"] = float(look.get("lift", ARC_LIFT))
	e["sweep"] = maxf(sweep, 0.01)
	e["fade"] = maxf(fade, 0.01)
	e["cos"] = str(look.get("ease", "cos")) == "cos"
	e["R"] = R
	var mi: MeshInstance3D = e["mi"]
	mi.visible = true
	mi.scale = Vector3(R, 1.0, R)
	mi.rotation = Vector3(0, yaw, 0)
	_place(e)
	_arc_frame(e)
	arcs_made += 1
	last_arc = {"yaw": yaw, "half_w": half_w, "reach": reach, "sign": sign}


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
	var m: ShaderMaterial = e["mat"]
	m.set_shader_parameter("quad_len", qlen)
	m.set_shader_parameter("quad_half", qw)
	m.set_shader_parameter("s0", back)
	m.set_shader_parameter("streak_w", minf(maxf(TIP_W * tip * 0.95, hw * 0.8), TIP_W * tip * 1.1))
	m.set_shader_parameter("tip_len", tip_len)
	m.set_shader_parameter("tip_w", TIP_W * tip)
	m.set_shader_parameter("glow_col", look.get("glow", Color(0.45, 0.68, 1.0)))
	m.set_shader_parameter("body_col", look.get("body", Color(0.8, 0.92, 1.0)))
	m.set_shader_parameter("core_col", look.get("core", Color.WHITE))
	m.set_shader_parameter("heat", float(look.get("heat", 0.0)))
	m.set_shader_parameter("heat_col", look.get("heat_col", look.get("glow", Color(1.0, 0.35, 0.1))))
	m.set_shader_parameter("crackle", float(look.get("crackle", 0.0)))
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("shade_a", float(look.get("shade_a", 0.3)))
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
	last_thrust = {"dir": d, "length": length, "lane_half": lane_half}


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
	var p := a.global_position + Vector3(0, float(e["lift"]), 0)
	if e.has("dir"):
		p += (e["dir"] as Vector3) * float(e["base"])
	mi.global_position = p


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
	m.set_shader_parameter("fade", f * f)
	if t >= sw + float(e["fade"]):
		e["live"] = false
		(e["mi"] as MeshInstance3D).visible = false


func _thrust_frame(e: Dictionary) -> void:
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
