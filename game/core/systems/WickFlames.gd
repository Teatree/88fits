## Wick flames (pass 76, lane MOLO; Garry: "Regenerate the Molotov Visuals, the flame looks weird. Make several
## different versions"). A thrown bottle with `params.wick_flame {style, offset, size, rate, life, ...}` burns AT ITS WICK:
## the flame is found every tick at `offset` (the wick's tip in the shot model's own space) turned and scaled with the
## shot as ProjectileManager.draw_basis draws it, and it stands upright there (the camera's up, leaning back against the
## flight) while the bottle under it turns end over end (`tumble`). Before it, the flight flame was a dotted string of
## separate tongues dropped every 0.07 s at the bottle's middle and left behind (ProjectileManager's old branch, kept for
## a weapon without wick_flame).
## Styles (core/shaders/wick_flame.gdshader): "torch" a steady licking flame with a soft glow and embers flying off it,
## "streamer" a continuous tapered ribbon of fire the wick leaves in the air behind it (its last `tail` seconds of path,
## rising a little as it cools) under a small flame on the wick, "cartoon" a bold three-layer flame in a dark ink line,
## its tongues jumping on a stepped clock, with inked star sparks popping off. Blue (WeaponInstance.blue_fire: Methanol,
## the Moonshine) burns each in the blue palette.
## Cheap for many bottles: one MultiMesh for every flame, streamer piece, ember and spark in the air (one draw call, one
## shader); a torch or a cartoon flame is one instance a bottle, a streamer about ten. ProjectileManager owns one
## (wick_flames()), ticks it from a lobbed shot's flight and draws it after its own shots; Warmup draws every style once.
## The pool's flames in the same style (`params.pool_flame {style, size}`, ElementCloud._flame_at): ground_flame() stands
## a short-lived flame on the spill in the same MultiMesh (a torch tongue rising out of the spill on a flat foot and eaten
## away as it ages, a cartoon flame popping up and down), in place of Fx's teardrops (which read as water drops in blue).
class_name WickFlames
extends Node3D

const STYLE_TORCH := 0
const STYLE_STREAMER := 1
const STYLE_CARTOON := 2
const STYLE_EMBER := 3
const STYLE_SPARK := 4
const STYLE_GLOW := 5
const STYLES := {"torch": STYLE_TORCH, "streamer": STYLE_STREAMER, "cartoon": STYLE_CARTOON}
## instances: flames and streamer pieces, then embers and sparks, then the pools' flames
const PIECE_MAX := 512
const EMBER_MAX := 192
const GROUND_MAX := 256
## a pool's flames are thinned past this share of GROUND_MAX (a third of them dropped), past BUSY_HIGH two thirds
const BUSY_LOW := 0.4
const BUSY_HIGH := 0.75
## a pool flame grows from this share of its height to all of it over its first GROW share of life; it rises RISE m/s
const GROW_FROM := 0.5
const GROW := 0.35
const RISE := 0.35
## a cartoon pool flame pops up over its first POP share of life and shrinks away over its last
const POP := 0.18
## a pool's flame is drawn this far towards the camera (in front of the creatures standing in it, as Fx's flames are),
## and narrower than a wick's (many stand side by side)
const DEPTH_GROUND := 0.45
const WIDTH_GROUND := {STYLE_TORCH: 0.95, STYLE_CARTOON: 0.9}
## wick positions kept per shot (one a physics tick: 0.4 s at 60)
const HIST := 24
## defaults of the wick_flame keys
const DEF_OFFSET := Vector3(0.0, 0.25, 0.0)
const DEF_SIZE := 0.55
const DEF_RATE := 12.0
const DEF_LIFE := 0.28
const DEF_LEAN := 0.045
const DEF_TAIL := 0.16
const DEF_RISE := 1.4
## how far a style's flame is drawn towards the camera (metres; negative: behind the wick, so the bottle stays in front
## of its own fire), unless the config's `depth` says; embers come forward a little
const DEPTH := {STYLE_TORCH: -0.1, STYLE_STREAMER: 0.0, STYLE_CARTOON: -0.12}
const EMBER_DEPTH := 0.15
## a flame stretches by up to this share as the bottle flies faster (its flat speed against STRETCH_SPEED)
const STRETCH := 0.25
const STRETCH_SPEED := 12.0
## the width of a style's quad against its height
const WIDTH := {STYLE_TORCH: 0.95, STYLE_STREAMER: 0.5, STYLE_CARTOON: 1.0}
## the streamer's small flame on the wick, against the streamer's size
const HEAD := 0.55
## an ember's size against the flame's, a cartoon spark's
const EMBER_SIZE := 0.13
const SPARK_SIZE := 0.24

var _mm: MultiMesh
var _mat: ShaderMaterial
## per projectile slot: {id (the shot's extra.wick_id), hist / hist_t (the wick's last HIST places and when), ember (the
## embers owed), seed, blue, style}
var _shots: Dictionary = {}
## the slots ticked since the last draw
var _list: Array = []
var _listed := PackedByteArray()
var _serial := 0
var _clock := 0.0
var _pf := -1
var _prune := 0
# embers and sparks
var _e_pos := PackedVector3Array()
var _e_vel := PackedVector3Array()
var _e_age := PackedFloat32Array()
var _e_life := PackedFloat32Array()
var _e_size := PackedFloat32Array()
var _e_kind := PackedFloat32Array()   # STYLE_EMBER or STYLE_SPARK, + 8 when blue
var _e_seed := PackedFloat32Array()
var _e_n := 0
# the pools' flames
var _g_pos := PackedVector3Array()
var _g_age := PackedFloat32Array()
var _g_life := PackedFloat32Array()
var _g_h := PackedFloat32Array()
var _g_kind := PackedFloat32Array()   # a style, + 8 when blue
var _g_seed := PackedFloat32Array()
var _g_n := 0
## diagnostics and tests: pool flames stood up (all time), and burning now
var ground_flames := 0
var _warm_at := Vector3.INF
## diagnostics and tests: flames drawn on wicks in the last draw (one a bottle), streamer pieces, embers alive, the wick
## of every shot drawn (slot -> world position), and the style each was drawn in
var flames_drawn := 0
var pieces_drawn := 0
var wicks: Dictionary = {}
var styles_drawn: Dictionary = {}
## the way each shot's flame stood in the last draw (slot -> unit axis, base to tip)
var axes: Dictionary = {}


func _ready() -> void:
	_listed.resize(512)
	_e_pos.resize(EMBER_MAX); _e_vel.resize(EMBER_MAX); _e_age.resize(EMBER_MAX); _e_life.resize(EMBER_MAX)
	_e_size.resize(EMBER_MAX); _e_kind.resize(EMBER_MAX); _e_seed.resize(EMBER_MAX)
	_g_pos.resize(GROUND_MAX); _g_age.resize(GROUND_MAX); _g_life.resize(GROUND_MAX); _g_h.resize(GROUND_MAX)
	_g_kind.resize(GROUND_MAX); _g_seed.resize(GROUND_MAX)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = q
	_mm.instance_count = PIECE_MAX + EMBER_MAX + GROUND_MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://core/shaders/wick_flame.gdshader")
	_mat.set_shader_parameter("noise_tex", load("res://art/fx/fire_noise.png"))
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


## The wick_flame block of `w`'s params ({} without one).
static func config(w: WeaponInstance) -> Dictionary:
	if w == null:
		return {}
	var c = w.params.get("wick_flame")
	return c if c is Dictionary else {}


## The style number of a config ("torch" when it names none or one it does not know).
static func style_of(cfg: Dictionary) -> int:
	return int(STYLES.get(str(cfg.get("style", "torch")), STYLE_TORCH))


## The wick's tip in the shot model's own space (`offset`, [x, y, z] metres).
static func offset_of(cfg: Dictionary) -> Vector3:
	var o = cfg.get("offset")
	if o is Array and (o as Array).size() >= 3:
		return Vector3(float(o[0]), float(o[1]), float(o[2]))
	return DEF_OFFSET


## Where shot `i`'s wick is in the world: its position plus the offset turned and scaled as the shot is drawn.
static func wick_world(pm: Node, i: int, cfg: Dictionary) -> Vector3:
	return pm.pos[i] + pm.draw_basis(i) * offset_of(cfg)


## One physics tick of shot `i` in flight (ProjectileManager._wick_flame_tick): its tumble, the wick's place, embers.
func tick(pm: Node, i: int, w: WeaponInstance, dt: float) -> void:
	var cfg := config(w)
	if cfg.is_empty():
		return
	var pf := Engine.get_physics_frames()
	if pf != _pf:
		_pf = pf
		_clock += dt
	var ex: Dictionary = pm.extra[i]
	var st: Dictionary = _shots.get(i, {})
	if not ex.has("wick_id") or int(st.get("id", -1)) != int(ex["wick_id"]):
		_serial += 1
		ex["wick_id"] = _serial
		st = {"id": _serial, "hist": PackedVector3Array(), "hist_t": PackedFloat32Array(), "ember": randf(), "seed": randf(),
			"blue": w.blue_fire(), "style": style_of(cfg)}
		_shots[i] = st
		# a tumbling bottle leaves the hand neck up (its flame on top) and turns from there
		if float(cfg.get("tumble", 0.0)) > 0.0:
			pm.spin[i] = 0.0
	# end over end (the axis across its flight, ProjectileManager's wheel turn) at `tumble` turns a second, whatever its
	# speed along the arc; without it the shot keeps the old spin about its flight line
	var tb := float(cfg.get("tumble", 0.0))
	if tb > 0.0:
		ex["roll"] = maxf(pm.vel[i].length(), 0.5) / (tb * TAU * maxf(float(pm.psize[i]), 0.05))
	var wick := wick_world(pm, i, cfg)
	var hist: PackedVector3Array = st["hist"]
	var hist_t: PackedFloat32Array = st["hist_t"]
	hist.append(wick)
	hist_t.append(_clock)
	if hist.size() > HIST:
		hist.remove_at(0)
		hist_t.remove_at(0)
	st["hist"] = hist
	st["hist_t"] = hist_t
	# embers (sparks for the cartoon flame) off the flame's top, `rate` a second
	var rate := float(cfg.get("rate", DEF_RATE))
	if rate > 0.0:
		var acc: float = float(st["ember"]) + rate * dt
		var size := float(cfg.get("size", DEF_SIZE)) * maxf(float(pm.psize[i]), 0.05)
		var spark: bool = int(st["style"]) == STYLE_CARTOON
		while acc >= 1.0:
			acc -= 1.0
			_ember(wick + Vector3.UP * size * randf_range(0.25, 0.6), pm.vel[i], cfg, bool(st["blue"]), spark, size)
		st["ember"] = acc
	if i >= _listed.size():
		_listed.resize(i + 1)
	if _listed[i] == 0:
		_listed[i] = 1
		_list.append(i)


func _ember(at: Vector3, vel: Vector3, cfg: Dictionary, blue: bool, spark: bool, size: float) -> void:
	if _e_n >= EMBER_MAX:
		return
	var k := _e_n
	_e_n += 1
	var flat := Vector3(vel.x, 0.0, vel.z)
	# flung off with some of the bottle's own speed, so they scatter round the flame and fall behind it one by one
	# instead of being dropped in a line along its path
	_e_pos[k] = at + Vector3(randf_range(-0.08, 0.08), randf_range(-0.04, 0.04), randf_range(-0.08, 0.08))
	_e_vel[k] = flat * randf_range(0.35, 0.75) + Vector3(randf_range(-1.3, 1.3), randf_range(0.6, 1.8), randf_range(-1.3, 1.3))
	_e_age[k] = 0.0
	_e_life[k] = maxf(float(cfg.get("life", DEF_LIFE)) * randf_range(0.7, 1.25), 0.05)
	_e_size[k] = size * (SPARK_SIZE if spark else EMBER_SIZE) * randf_range(0.75, 1.25)
	_e_kind[k] = float(STYLE_SPARK if spark else STYLE_EMBER) + (8.0 if blue else 0.0)
	_e_seed[k] = randf()


## Every flame on a wick ticked since the last draw, the embers moved by `dt`, all in the one MultiMesh
## (ProjectileManager._process, right after its own shots are drawn, so the flame sits on the bottle drawn this frame).
func draw(pm: Node, dt: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var up := Vector3.UP
	var back := Vector3(0.0, 0.7, 0.7)
	if cam:
		up = cam.global_transform.basis.y
		back = cam.global_transform.basis.z
	var n := 0
	flames_drawn = 0
	pieces_drawn = 0
	wicks.clear()
	styles_drawn.clear()
	axes.clear()
	for i: int in _list:
		_listed[i] = 0
		if i >= pm.alive.size() or pm.alive[i] == 0 or not _shots.has(i):
			continue
		var st: Dictionary = _shots[i]
		var ex: Dictionary = pm.extra[i]
		if int(ex.get("wick_id", -1)) != int(st["id"]):
			continue
		var cfg := config(pm.weapon[i])
		if cfg.is_empty():
			continue
		n = _draw_shot(pm, i, st, cfg, up, back, n)
	_list.clear()
	n = _draw_ground(dt, up, back, n)
	n = _draw_embers(dt, up, back, n)
	if _warm_at != Vector3.INF:
		n = _draw_warm(up, back, n)
	_mm.visible_instance_count = n
	# forget the shots that came down (now and then; their slots may be taken by anything)
	_prune += 1
	if _prune >= 90:
		_prune = 0
		for k in _shots.keys():
			if int(k) >= pm.alive.size() or pm.alive[int(k)] == 0:
				_shots.erase(k)


## One quad standing on `base` along `axis` (base -> tip, its length the height), `width` wide, facing the camera.
func _put(n: int, base: Vector3, axis: Vector3, width: float, back: Vector3, alpha: float, custom: Color) -> int:
	if n >= _mm.instance_count:
		return n
	var h := axis.length()
	if h < 0.0001:
		return n
	var y := axis / h
	var x := y.cross(back)
	if x.length_squared() < 0.000001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	_mm.set_instance_transform(n, Transform3D(Basis(x * width, axis, z), base))
	_mm.set_instance_color(n, Color(1.0, 1.0, 1.0, alpha))
	_mm.set_instance_custom_data(n, custom)
	return n + 1


func _draw_shot(pm: Node, i: int, st: Dictionary, cfg: Dictionary, up: Vector3, back: Vector3, n: int) -> int:
	var hist: PackedVector3Array = st["hist"]
	if hist.is_empty():
		return n
	var wick: Vector3 = hist[hist.size() - 1]
	var style: int = int(st["style"])
	var blue: float = 8.0 if bool(st["blue"]) else 0.0
	var sd: float = float(st["seed"])
	var size := float(cfg.get("size", DEF_SIZE)) * maxf(float(pm.psize[i]), 0.05)
	var v: Vector3 = pm.vel[i]
	var flat := Vector3(v.x, 0.0, v.z)
	# upright (the camera's up, so it shows its full height), leaning back against the flight and a little longer the
	# faster it goes
	var lean := float(cfg.get("lean", DEF_LEAN))
	var axis := (up - flat * lean).normalized()
	var stretch := 1.0 + STRETCH * clampf(flat.length() / STRETCH_SPEED, 0.0, 1.0)
	wicks[i] = wick
	styles_drawn[i] = style
	axes[i] = axis
	flames_drawn += 1
	var at := wick + back * float(cfg.get("depth", DEPTH.get(style, 0.0)))
	if style == STYLE_STREAMER:
		n = _draw_streamer(st, cfg, size, up, back, sd, blue, n)
		var hs := size * HEAD
		return _put(n, at, axis * hs * stretch, hs * float(WIDTH[STYLE_TORCH]), back, 1.0, Color(0.0, sd, 0.0, float(STYLE_TORCH) + blue))
	var w: float = size * float(WIDTH.get(style, 0.8))
	return _put(n, at, axis * size * stretch, w, back, 1.0, Color(0.0, sd, 0.0, float(style) + blue))


## The streamer: pieces along the wick's path over the last `tail` seconds (each point risen by its age, as hot air
## does), tail first so the hotter pieces lie over the cooler ones; u runs 0 at the wick to 1 at the tail's end.
func _draw_streamer(st: Dictionary, cfg: Dictionary, size: float, up: Vector3, back: Vector3, sd: float, blue: float, n: int) -> int:
	var hist: PackedVector3Array = st["hist"]
	var hist_t: PackedFloat32Array = st["hist_t"]
	var tail := maxf(float(cfg.get("tail", DEF_TAIL)), 0.02)
	var rise := float(cfg.get("rise", DEF_RISE))
	var pts := PackedVector3Array()
	var last := hist.size() - 1
	var now: float = hist_t[last]
	for k in range(last, -1, -1):
		var age: float = now - hist_t[k]
		if age > tail + 0.0001:
			break
		pts.append(hist[k] + Vector3.UP * rise * age)
	var m := pts.size() - 1
	if m < 1:
		return n
	var width := size * float(WIDTH[STYLE_STREAMER])
	var du := 1.0 / float(m)
	for k in range(m - 1, -1, -1):
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		# each piece reaches a little past its end, under the next one, so no gap opens at a bend
		var seg := (b - a) * 1.18
		n = _put(n, a, seg, width, back, 1.0, Color(float(k) * du, sd, du * 1.18, float(STYLE_STREAMER) + blue))
		pieces_drawn += 1
	return n


func _draw_embers(dt: float, up: Vector3, back: Vector3, n: int) -> int:
	var k := 0
	while k < _e_n:
		_e_age[k] += dt
		if _e_age[k] >= _e_life[k]:
			_e_n -= 1
			if k != _e_n:
				_e_pos[k] = _e_pos[_e_n]; _e_vel[k] = _e_vel[_e_n]; _e_age[k] = _e_age[_e_n]; _e_life[k] = _e_life[_e_n]
				_e_size[k] = _e_size[_e_n]; _e_kind[k] = _e_kind[_e_n]; _e_seed[k] = _e_seed[_e_n]
			continue
		var spark: bool = int(_e_kind[k]) % 8 == STYLE_SPARK
		_e_vel[k] *= maxf(1.0 - 2.2 * dt, 0.0)
		_e_vel[k].y += (-3.0 if spark else 0.6) * dt
		_e_pos[k] += _e_vel[k] * dt
		var s: float = _e_size[k]
		n = _put(n, _e_pos[k] - up * s * 0.5 + back * EMBER_DEPTH, up * s, s, back, 1.0, Color(_e_age[k] / _e_life[k], _e_seed[k], 0.0, _e_kind[k]))
		k += 1
	return n


## Warm-up (Warmup through ProjectileManager.warm_wick_flames): one small piece of every style at `at` while it is set.
func warm(at: Vector3) -> void:
	_warm_at = at
	if is_inside_tree() and at != Vector3.INF and _mm:
		var n := _draw_warm(Vector3.UP, Vector3.BACK, 0)
		_mm.visible_instance_count = n
	elif _mm and at == Vector3.INF and _list.is_empty() and _e_n == 0:
		_mm.visible_instance_count = 0


func _draw_warm(up: Vector3, back: Vector3, n: int) -> int:
	for s in [STYLE_TORCH, STYLE_STREAMER, STYLE_CARTOON, STYLE_EMBER, STYLE_SPARK, STYLE_GLOW]:
		n = _put(n, _warm_at, up * 0.1, 0.1, back, 0.02, Color(0.0, 0.0, 0.1, float(s)))
	return n


## How many embers and sparks are flying (tests).
func ember_count() -> int:
	return _e_n


## How many pool flames are burning (tests).
func ground_count() -> int:
	return _g_n


## A pool's flame (ElementCloud._flame_at with the weapon's `params.pool_flame`) standing on `at`, `height` metres tall at
## its fullest, gone in `life` seconds, in `style` ("torch" or "cartoon"; "streamer" burns its pool as torches), blue or
## not. Thinned when many burn at once (BUSY_LOW, BUSY_HIGH); `must` never is. Returns whether it was stood up.
func ground_flame(at: Vector3, height: float, life: float, style: String, blue: bool, must := false) -> bool:
	if _g_n >= GROUND_MAX:
		return false
	if not must:
		var busy := float(_g_n) / float(GROUND_MAX)
		if busy > BUSY_HIGH and randf() < 0.66:
			return false
		if busy > BUSY_LOW and randf() < 0.33:
			return false
	var s := STYLE_CARTOON if style == "cartoon" else STYLE_TORCH
	var k := _g_n
	_g_n += 1
	_g_pos[k] = at
	_g_age[k] = 0.0
	_g_life[k] = maxf(life, 0.05)
	_g_h[k] = maxf(height, 0.05)
	_g_kind[k] = float(s) + (8.0 if blue else 0.0)
	_g_seed[k] = randf()
	ground_flames += 1
	return true


func _draw_ground(dt: float, up: Vector3, back: Vector3, n: int) -> int:
	var k := 0
	while k < _g_n:
		_g_age[k] += dt
		if _g_age[k] >= _g_life[k]:
			_g_n -= 1
			if k != _g_n:
				_g_pos[k] = _g_pos[_g_n]; _g_age[k] = _g_age[_g_n]; _g_life[k] = _g_life[_g_n]; _g_h[k] = _g_h[_g_n]
				_g_kind[k] = _g_kind[_g_n]; _g_seed[k] = _g_seed[_g_n]
			continue
		var f: float = _g_age[k] / _g_life[k]
		var style: int = int(_g_kind[k]) % 8
		var h: float = _g_h[k]
		var age := f
		if style == STYLE_CARTOON:
			# a cartoon flame pops up, holds and shrinks away (it is never eaten)
			h *= minf(clampf(f / POP, 0.0, 1.0), clampf((1.0 - f) / POP, 0.0, 1.0))
			age = 0.0
		else:
			var g: float = clampf(f / GROW, 0.0, 1.0)
			h *= lerpf(GROW_FROM, 1.0, 1.0 - (1.0 - g) * (1.0 - g))
		var at: Vector3 = _g_pos[k] + Vector3.UP * RISE * _g_age[k] + back * float(DEPTH_GROUND)
		# z 1: the torch's flat foot (the shader), so it rises out of the spill rather than sitting on it like a drop
		n = _put(n, at, up * h, h * float(WIDTH_GROUND.get(style, 0.8)), back, 1.0, Color(age, _g_seed[k], 1.0, _g_kind[k]))
		k += 1
	return n
