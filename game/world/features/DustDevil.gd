## One dust devil (pass 44; pass 113, lane TWISTER: it comes and goes, and looks like a tornado). Made by the map's
## DustDevils clock (core/systems/DustDevils.gd, whose header has every number), it lives `life` seconds:
##   forming  (form_seconds) its dust skirt churns up first, then the funnel rises out of it (TornadoFx's strength 0 to
##            1); its ring on the ground shows faintly the whole time: where it will throw the hero;
##   standing it moves (`wander`), throws the hero up and out when he comes within its ring (pass 44's toss, once in
##            toss.cooldown s) and lifts and spins every creature within `radius` (EnemyManager.lift_radius / swirl);
##            the ring is at full strength;
##   fading   (fade_seconds, the last of its life, or at once when sent away) it grabs nothing more, the ring goes, the
##            funnel thins away and its dust puffs out (TornadoFx.burst); then it is gone.
## Its look is a TornadoFx (core/systems/TornadoFx.gd) and the ring (core/shaders/dust_devil_ring.gdshader, laid over the
## sand from the map's height grid like Telegraphs' marks), both drawn before the stage's filter so a stage's look tints
## them like the sand.
class_name DustDevil
extends Node3D

const RING_SHADER := preload("res://core/shaders/dust_devil_ring.gdshader")
## The look at the map's size (TornadoFx's numbers): funnel height, foot and top radius, the dust's colour, turns a second.
const HEIGHT := 7.0
const R_BOTTOM := 0.6
const R_TOP := 2.1
const COLOR := Color(0.7, 0.52, 0.34)
const SPIN := 0.9
## The ring band's width (m, inside the reach) and its alpha while forming (a warning) and standing.
const RING_BAND := 0.5
const RING_WARN := 0.5
## The share of its fading at which the dust puffs out.
const BURST_AT := 0.55
## How hard a crossing one sways off its line (radians) and how fast; how fast a drifting one turns (rad/s at most).
const SWAY := 0.35
const SWAY_HZ := 0.11
const DRIFT_TURN := 0.6
## The loop's ellipse round the flats (pass 44's): metres across x and z, its middle off the flats' centre.
const LOOP_RX := 18.0
const LOOP_RZ := 10.0
const LOOP_OFFSET := Vector3(6, 0, 4)

var game: Node
var map: Node
var cfg: Dictionary = {}
var radius := 2.4
var speed := 1.4
var wander := "cross"
var life := 25.0
var age := 0.0
var heading := Vector3(1, 0, 0)
var form_seconds := 2.5
var fade_seconds := 2.0
## The age its fading starts (life - fade_seconds, or sooner when sent away).
var fade_at := INF
var gone := false
## Counts for tests and tools: times the hero was thrown, creatures lifted.
var tosses := 0
var lifted := 0
var fx: TornadoFx
var ring: MeshInstance3D
var _player_cd := 0.0
var _burst := false
var _seed := 0
var _loop_t := 0.0
var _turn := 0.0
var _ring_mat: ShaderMaterial
var _ring_alpha := 0.0

static var _ring_mesh: ArrayMesh


## Its numbers (DustDevils.config_of's block), where it forms, the way it heads, how long it lives, its own dice.
func setup(p_cfg: Dictionary, at: Vector3, dir: Vector3, p_life: float, seed_v: int = 0) -> void:
	cfg = p_cfg
	radius = float(cfg.get("radius", 2.4))
	speed = float(cfg.get("speed", 1.4))
	wander = str(cfg.get("wander", "cross"))
	form_seconds = float(cfg.get("form_seconds", 2.5))
	fade_seconds = float(cfg.get("fade_seconds", 2.0))
	life = maxf(p_life, form_seconds + fade_seconds + 0.5)
	fade_at = life - fade_seconds
	_seed = seed_v
	heading = Vector3(dir.x, 0.0, dir.z).normalized() if Vector3(dir.x, 0, dir.z).length() > 0.001 else Vector3(1, 0, 0)
	position = at
	if wander == "loop" and map != null:
		var c: Vector3 = map.get("flats_center") + LOOP_OFFSET
		_loop_t = atan2((at.z - c.z) / LOOP_RZ, (at.x - c.x) / LOOP_RX)


func _ready() -> void:
	if cfg.is_empty():
		cfg = DustDevils.config_of(null)
		radius = float(cfg["radius"])
	fx = TornadoFx.new()
	fx.name = "Tornado"
	fx.height = HEIGHT
	fx.radius_bottom = R_BOTTOM
	fx.radius_top = R_TOP
	fx.color = COLOR
	fx.spin = SPIN
	# the skirt of dust reaches nearly to its grab radius, so the cloud at its foot is what grabs
	fx.skirt_radius = radius * 0.92
	add_child(fx)
	fx.set_strength(0.0)
	ring = MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _ring()
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = RING_SHADER
	_ring_mat.render_priority = TornadoFx.PRIORITY - 1
	_ring_mat.set_shader_parameter("noise_tex", TornadoFx.NOISE)
	_ring_mat.set_shader_parameter("r_out", reach())
	_ring_mat.set_shader_parameter("band", RING_BAND)
	_ring_mat.set_shader_parameter("color", COLOR)
	_ring_mat.set_shader_parameter("alpha", 0.0)
	var tg = game.get("telegraphs") if game != null else null
	if tg != null and tg.has_method("_ground_uniforms"):
		tg._ground_uniforms(_ring_mat)
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var w := reach() + 1.0
	ring.custom_aabb = AABB(Vector3(-w, -2.0, -w), Vector3(w * 2.0, 4.0, w * 2.0))
	ring.sorting_offset = -2.0
	add_child(ring)


## Metres from its middle the hero is thrown within (the ring's outer edge).
func reach() -> float:
	return radius + DustDevils.HERO_REACH


## Its TornadoFx strength now: rising over form_seconds, 1 while it stands, falling over its fading.
func strength() -> float:
	if gone:
		return 0.0
	if age >= fade_at:
		return clampf(1.0 - (age - fade_at) / fade_seconds, 0.0, 1.0)
	return clampf(age / form_seconds, 0.0, 1.0)


## Whether it grabs now: formed and not yet fading.
func catching() -> bool:
	return not gone and age >= form_seconds and age < fade_at


func fading() -> bool:
	return age >= fade_at


## It starts to go now (sent away, its phase over): it grabs nothing more and fades over fade_seconds.
func fade_out() -> void:
	if gone or age >= fade_at:
		return
	# one still forming fades from where it got to
	var s := strength()
	fade_at = age - (1.0 - s) * fade_seconds
	life = fade_at + fade_seconds


## The tools' word for fade_out.
func end_now() -> void:
	fade_out()


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	var t0 := Time.get_ticks_usec()
	if game != null and bool(game.get("paused")):
		return
	step(delta)
	Perf.add("dustdevil", t0)


## One tick: its age, its move, its look, its grabs; gone at the end of its life.
func step(delta: float) -> void:
	if gone:
		return
	age += delta
	_move(delta)
	if fx:
		fx.set_strength(strength())
		if age >= fade_at and not _burst and (age - fade_at) >= fade_seconds * BURST_AT:
			_burst = true
			fx.burst()
	_tick_ring(delta)
	_grab(delta)
	if age >= life:
		gone = true
		if fx and fx.burst_t > 0.0 and is_inside_tree():
			# the puff plays out, then it goes
			Lockstep.after(self, TornadoFx.BURST_SECONDS, false).timeout.connect(queue_free)
		else:
			queue_free()


func _move(delta: float) -> void:
	var p := position
	match wander:
		"loop":
			var c: Vector3 = (map.get("flats_center") if map != null else Vector3.ZERO) + LOOP_OFFSET
			_loop_t += delta * speed / ((LOOP_RX + LOOP_RZ) * 0.5)
			p = c + Vector3(cos(_loop_t) * LOOP_RX, 0, sin(_loop_t * 0.7) * LOOP_RZ)
		"drift":
			var want := sin(age * 0.37 + float(_seed % 97)) * DRIFT_TURN
			_turn = lerpf(_turn, want, clampf(delta, 0.0, 1.0))
			heading = heading.rotated(Vector3.UP, _turn * delta)
			p += heading * speed * delta
		_:
			var sway := sin(age * TAU * SWAY_HZ + float(_seed % 61)) * SWAY
			p += heading.rotated(Vector3.UP, sway) * speed * delta
	# it turns back before the canyon's wall
	if map != null and wander != "loop":
		var r := float(map.get("arena_radius")) * 0.85
		var flat := Vector2(p.x, p.z)
		if flat.length() > r:
			var inward := Vector3(-p.x, 0, -p.z).normalized()
			heading = heading.lerp(inward, clampf(delta * 1.5, 0.0, 1.0)).normalized()
	if map != null:
		p.y = map.height_at(p.x, p.z)
	position = p


func _tick_ring(delta: float) -> void:
	if _ring_mat == null:
		return
	var want := 0.0
	if catching():
		want = 1.0
	elif age < form_seconds:
		want = RING_WARN * clampf(age / (form_seconds * 0.5), 0.0, 1.0)
	_ring_alpha = move_toward(_ring_alpha, want, delta * 3.0)
	ring.visible = _ring_alpha > 0.001
	_ring_mat.set_shader_parameter("alpha", _ring_alpha)
	_ring_mat.set_shader_parameter("t", fx.clock() if fx else age)
	_ring_mat.set_shader_parameter("spin", SPIN)


## The hero thrown up and out once a pass (pass 44's toss); creatures within `radius` lifted and spun. Only while it
## stands; the ones already up keep swirling round it while it fades.
func _grab(delta: float) -> void:
	if game == null:
		return
	var em = game.get("enemies")
	if not catching():
		if em != null and fading():
			em.swirl(global_position, radius, delta)
		return
	_player_cd = maxf(_player_cd - delta, 0.0)
	var pl = game.get("player")
	var toss: Dictionary = cfg.get("toss", {})
	if pl != null and not bool(pl.get("dead")) and float(toss.get("up", 8.0)) > 0.0:
		var d: Vector3 = pl.global_position - global_position
		d.y = 0.0
		if d.length() < reach() and _player_cd <= 0.0 and pl.has_method("launch"):
			var n := d.normalized()
			var out := float(toss.get("out", 3.6))
			pl.launch(Vector3(n.x * out, float(toss.get("up", 8.0)), n.z * out))
			_player_cd = float(toss.get("cooldown", 1.2))
			tosses += 1
	if em != null:
		var secs := float(cfg.get("lift", 1.7))
		if secs > 0.0:
			lifted += int(em.lift_radius(global_position, radius, secs))
		em.swirl(global_position, radius, delta)


## The ring's mesh, made once: a disc from the middle (UV.x 0) to the rim (UV.x 1), UV.y round it; the shader lays it on
## the sand and draws the band at its rim.
static func _ring() -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var seg := 56
	var rows := [0.0, 0.55, 0.75, 0.86, 0.94, 1.0]
	for j in range(rows.size()):
		for i in range(seg + 1):
			var u := float(i) / float(seg)
			verts.append(Vector3(cos(u * TAU) * rows[j], 0.0, sin(u * TAU) * rows[j]))
			uvs.append(Vector2(rows[j], u))
	var cols := seg + 1
	for j in range(rows.size() - 1):
		for i in range(seg):
			var a := j * cols + i
			idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	_ring_mesh = ArrayMesh.new()
	_ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _ring_mesh
