## The look of a boss's barrier (pass 115, lane BOSS; content/boss_attacks `barrier`, BossAttackDef.barrier_on(); Garry:
## "Each boss has their own barrier, but the object should be a 3d object, should appear with animation and should be easy
## to 'read' as a barrier so Player doesn't wonder what this is ... Barrier falls apart and disappears when the attack is
## done"). Only the look: BossPatterns holds the hero inside it (Player.fence_r), keeps the crowd on its side and stops
## the bullets at it, whether this node exists or not.
##
## A ring of `radius` m round `center`, made of stretches (BarrierMeshes.SEG m each) of 3D pieces (BarrierMeshes.parts:
## the King's stakes, tumbleweeds and ropes; the Gila's organ-pipe cactus columns with venom blooms and thorns; the
## Brander's iron bars with white-hot spear heads, rails and branding irons with glowing brands). One MultiMesh per kind of
## piece and per CHUNK_M m of the ring (so the stretches off the screen are culled), drawn with
## core/shaders/boss_barrier.gdshader, which plays the whole animation from two numbers a frame:
##   - the rise (setup, at the tell's start): each stretch comes up out of the sand over rise_s with a small overshoot,
##     the stretch nearest the hero first and the far side last (spread_s), its pieces a beat after its posts; puffs of
##     sand where the hero can see, a thud once;
##   - the fall (fall(), when BossPatterns lets it go): every piece, at its own moment within spread_s, topples over the
##     fence line and sinks, the tumbleweeds rolling away across it with a bounce; puffs of sand, a crash; then it is gone.
## Stretches beyond the map's edge (the arena's radius) are not made: the map's own wall closes the ring there. Its rolls
## (the pieces' turns and sizes, the fall's order) are its own seeded dice, never the run's.
class_name BossBarrier
extends Node3D

const SHADER := preload("res://core/shaders/boss_barrier.gdshader")
## metres of the ring in one MultiMesh (each kind of piece): its own box to cull
const CHUNK_M := 14.0
## how near the hero a stretch must be to throw sand as it rises or falls (m), and every how many stretches
const DUST_NEAR := 20.0
const DUST_EVERY := 2
const RISE_SOUND := "en_boulder_land"
const FALL_SOUND := "st_barrel_break"
## seconds a kind of piece comes up after its stretch's posts
const LATE := {"weed": 0.08, "weed_glow": 0.08, "rope": 0.16, "column_glow": 0.12, "thorns": 0.1, "rail": 0.12, "rail_glow": 0.12, "post_glow": 0.04}
## seconds after the last piece is down before the node goes
const GONE_AFTER := 0.3

var look := ""
var center := Vector3.ZERO
var radius := 10.0
var rise_s := 0.8
var fall_s := 1.0
var spread_s := 0.6
var height_k := 1.0
var depth := 2.6
## seconds since the rise began; since the fall began (-1: standing)
var t := 0.0
var fall_t := -1.0
## for the tests and the captures: stretches made, pieces made, MultiMeshes made
var stretches := 0
var pieces := 0
var chunks := 0

var _game: Node = null
var _mats: Dictionary = {}
## the stretches: [{at (its foot), delay}] and their order by delay (the sand puffs)
var _segs: Array = []
var _order: Array = []
var _dust_i := 0
var _thud := false


## Built for pattern `cdef` round `c` (where the boss stands), `r` m out, rising from the side of `hero_at` first.
func setup(game: Node, cdef: BossAttackDef, c: Vector3, r: float, hero_at: Vector3) -> void:
	_game = game
	look = cdef.text("barrier", "look")
	center = c
	radius = maxf(r, 1.0)
	rise_s = maxf(cdef.num("barrier", "rise_s"), 0.05)
	fall_s = maxf(cdef.num("barrier", "fall_s"), 0.05)
	spread_s = maxf(cdef.num("barrier", "spread_s"), 0.0)
	height_k = maxf(cdef.num("barrier", "height"), 0.3) / BarrierMeshes.DESIGN_H
	depth = 2.3 * height_k + 0.45
	var meshes := BarrierMeshes.parts(look)
	if meshes.is_empty():
		return
	var tint := BossAttackDef.color_of(cdef.text("barrier", "color"), Color(1, 1, 1))
	var gcol := BossAttackDef.color_of(cdef.text("barrier", "glow_color"), Color(1.0, 0.54, 0.12))
	for piece: String in meshes.keys():
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("glow", 1.0 if BarrierMeshes.GLOW_PARTS.has(piece) else 0.0)
		m.set_shader_parameter("glow_color", gcol)
		m.set_shader_parameter("roll", 1.0 if BarrierMeshes.ROLL_PARTS.has(piece) else 0.0)
		m.set_shader_parameter("center", c)
		m.set_shader_parameter("rise_s", rise_s)
		m.set_shader_parameter("fall_s", fall_s)
		m.set_shader_parameter("depth", depth)
		m.set_shader_parameter("t_rise", 0.0)
		m.set_shader_parameter("t_fall", -1.0)
		_mats[piece] = m
	_build(meshes, cdef, hero_at)


func _ground(x: float, z: float) -> float:
	var mp = _game.get("map") if _game != null else null
	if mp != null and mp.has_method("height_at"):
		return float(mp.height_at(x, z))
	return center.y


## Whether a point is on the map (inside its arena's circle, a little past the wall's face).
func _on_map(p: Vector3) -> bool:
	var mp = _game.get("map") if _game != null else null
	if mp == null or mp.get("arena_radius") == null:
		return true
	return Vector2(p.x, p.z).length() <= float(mp.get("arena_radius")) + 0.5


## The ring laid out: the stretches' feet and delays, every piece's place and turn, grouped into MultiMeshes.
func _build(meshes: Dictionary, cdef: BossAttackDef, hero_at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([look, int(round(center.x * 10.0)), int(round(center.z * 10.0)), int(round(radius * 10.0))])
	var seg_len: float = float(BarrierMeshes.SEG.get(look, 1.6)) * height_k
	var n := maxi(8, int(ceil(TAU * radius / seg_len)))
	var ah := atan2(hero_at.z - center.z, hero_at.x - center.x)
	var feet: Array = []
	var on: Array = []
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var p := Vector3(center.x + cos(a) * radius, 0.0, center.z + sin(a) * radius)
		p.y = _ground(p.x, p.z)
		feet.append(p)
		on.append(_on_map(p))
	var thick := clampf(cdef.num("barrier", "thickness") / 0.8, 0.4, 2.0)
	var per_chunk := maxi(1, int(CHUNK_M / maxf(seg_len, 0.1)))
	# piece -> chunk -> [[Transform3D, custom Color]]
	var lists: Dictionary = {}
	for k in range(n):
		if not bool(on[k]):
			continue
		var a := TAU * float(k) / float(n)
		var delay := spread_s * absf(angle_difference(a, ah)) / PI
		var foot: Vector3 = feet[k]
		var nxt: Vector3 = feet[(k + 1) % n]
		var next_on: bool = on[(k + 1) % n]
		var xa := Vector3(nxt.x - foot.x, 0.0, nxt.z - foot.z)
		var chord := xa.length()
		xa = xa / maxf(chord, 0.001)
		var za := xa.cross(Vector3.UP)
		var frame := Basis(xa, Vector3.UP, za)
		_segs.append({"at": foot, "delay": delay})
		stretches += 1
		var chunk := int(float(k) / float(per_chunk))
		# the piece placed just before (a glowing piece that sits on it rises, topples and sinks with it)
		var prev_custom := Color()
		var prev_at := Vector3.INF
		for pl: Array in _layout(k, chord, next_on, rng):
			var piece: String = pl[0]
			if not meshes.has(piece):
				continue
			var xf := Transform3D()
			var custom := Color()
			var fall_d := rng.randf() * spread_s * 0.85
			var sd := rng.randf()
			var late := float(LATE.get(piece, 0.0))
			if pl.size() > 4:
				# a span to the next stretch's post: from (x0, y) here to (0, y) there, each end on its own sand
				var y := float(pl[1]) * height_k
				var from := foot
				from.y = foot.y + y
				var to := nxt
				to.y = nxt.y + y
				var span := to - from
				var bx := span
				var by := (Vector3.UP - span.normalized() * span.normalized().dot(Vector3.UP)).normalized() * height_k
				var bz := span.normalized().cross(by.normalized()) * height_k
				xf = Transform3D(Basis(bx, by, bz), from)
				custom = Color(delay + late, fall_d, sd, y)
			else:
				var lp: Vector3 = pl[1]
				var rot: Basis = pl[2]
				var sc: Vector3 = pl[3]
				var local := Vector3(lp.x, 0.0, lp.z * thick)
				var w := foot + frame * local
				var gy := _ground(w.x, w.z)
				var y2 := lp.y * height_k
				w.y = gy + y2
				xf = Transform3D(frame * rot * Basis.from_scale(sc * height_k), w)
				custom = Color(delay + late + rng.randf_range(0.0, 0.05), fall_d, sd, y2)
				if BarrierMeshes.GLOW_PARTS.has(piece) and prev_at.is_equal_approx(lp):
					# its glow (embers, a bloom, a hot tip, a brand) moves as one with the piece it is on
					custom = prev_custom
				prev_custom = custom
				prev_at = lp
			if not lists.has(piece):
				lists[piece] = {}
			if not (lists[piece] as Dictionary).has(chunk):
				lists[piece][chunk] = []
			(lists[piece][chunk] as Array).append([xf, custom])
	for piece: String in lists.keys():
		for chunk in (lists[piece] as Dictionary).keys():
			var items: Array = lists[piece][chunk]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			# (an instance colour, white: without one the Compatibility renderer multiplied the paint by the custom data)
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = meshes[piece]
			mm.instance_count = items.size()
			for j in range(items.size()):
				mm.set_instance_transform(j, items[j][0])
				mm.set_instance_color(j, Color(1, 1, 1, 1))
				mm.set_instance_custom_data(j, items[j][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d" % [piece, int(chunk)]
			mmi.multimesh = mm
			mmi.material_override = _mats[piece]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# (the shader moves every piece: down under the sand, rolling away)
			mmi.extra_cull_margin = depth + 4.0
			add_child(mmi)
			chunks += 1
			pieces += items.size()
	_order = range(_segs.size())
	_order.sort_custom(func(x, y): return float(_segs[x]["delay"]) < float(_segs[y]["delay"]))


## One stretch's pieces (`k` its index, `chord` its length, `next_on` whether the next stretch is made): [piece, local place
## (x along it, y up, z across), turn, scale] each, or [piece, y, 0, 0, "span"] for a rope or rail to the next post.
func _layout(k: int, chord: float, next_on: bool, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var L := chord
	match look:
		"tumbleweed_fence":
			out.append(["stake", Vector3(0, 0, 0), _tilt(rng, 0.07), Vector3.ONE])
			for wd: Array in [[0.27, 0.55, 1.0], [0.73, 0.55, 1.0], [0.5, 1.2, 0.84]]:
				var rot := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
				var s := float(wd[2]) * rng.randf_range(0.92, 1.1)
				var p := Vector3(float(wd[0]) * L + rng.randf_range(-0.06, 0.06) * L, float(wd[1]), rng.randf_range(-0.1, 0.1))
				out.append(["weed", p, rot, Vector3.ONE * s])
				out.append(["weed_glow", p, rot, Vector3.ONE * s])
			if next_on:
				out.append(["rope", 1.33, 0, 0, "span"])
				out.append(["rope", 0.66, 0, 0, "span"])
		"cactus_fence":
			for x: float in [0.12, 0.5, 0.85]:
				var hs := rng.randf_range(0.82, 1.12)
				var ws := rng.randf_range(0.9, 1.1)
				var rot2 := Basis(Vector3.UP, rng.randf() * TAU) * _tilt(rng, 0.05)
				var p2 := Vector3((x + rng.randf_range(-0.05, 0.05)) * L, 0.0, rng.randf_range(-0.12, 0.12))
				out.append(["column", p2, rot2, Vector3(ws, hs, ws)])
				if rng.randf() < 0.75:
					out.append(["column_glow", p2, rot2, Vector3(ws, hs, ws)])
			for x2: float in [0.31, 0.68]:
				var s2 := rng.randf_range(0.9, 1.25)
				out.append(["thorns", Vector3(x2 * L, 0.0, rng.randf_range(-0.2, 0.2)), Basis(Vector3.UP, rng.randf() * TAU), Vector3.ONE * s2])
		"iron_fence":
			if k % 4 == 0:
				var pr := Basis(Vector3.UP, rng.randf_range(-0.12, 0.12))
				out.append(["post", Vector3.ZERO, pr, Vector3.ONE])
				out.append(["post_glow", Vector3.ZERO, pr, Vector3.ONE])
			else:
				var tb := _tilt(rng, 0.04)
				out.append(["bar", Vector3.ZERO, tb, Vector3.ONE])
				out.append(["bar_glow", Vector3.ZERO, tb, Vector3.ONE])
			for x3: float in [1.0 / 3.0, 2.0 / 3.0]:
				var tb2 := _tilt(rng, 0.04)
				var p3 := Vector3(x3 * L, 0.0, 0.0)
				out.append(["bar", p3, tb2, Vector3.ONE])
				out.append(["bar_glow", p3, tb2, Vector3.ONE])
			if next_on:
				out.append(["rail_glow", 0.25, 0, 0, "span"])
				out.append(["rail", 1.2, 0, 0, "span"])
	return out


## A small random lean (radians up to `amount` each way) about the two flat axes.
func _tilt(rng: RandomNumberGenerator, amount: float) -> Basis:
	return Basis.from_euler(Vector3(rng.randf_range(-amount, amount), rng.randf_range(-0.3, 0.3), rng.randf_range(-amount, amount)))


func _process(delta: float) -> void:
	t += delta
	if fall_t >= 0.0:
		fall_t += delta
	var pulse := 0.86 + 0.14 * sin(t * 3.4)
	for m: ShaderMaterial in _mats.values():
		m.set_shader_parameter("t_rise", t)
		m.set_shader_parameter("t_fall", fall_t)
		m.set_shader_parameter("pulse", pulse)
	_rise_dust()
	if fall_t >= 0.0 and fall_t > fall_s + spread_s + GONE_AFTER:
		queue_free()


func _hero() -> Vector3:
	var pl = _game.get("player") if _game != null else null
	return (pl as Node3D).global_position if pl is Node3D else center


## Sand thrown up by the stretches near the hero as each comes up (every DUST_EVERY one), and one thud at the nearest.
func _rise_dust() -> void:
	if fall_t >= 0.0:
		return
	var fx = _game.get("fx") if _game != null else null
	var hero := _hero()
	while _dust_i < _order.size() and float(_segs[_order[_dust_i]]["delay"]) <= t:
		var si: int = _order[_dust_i]
		_dust_i += 1
		var at: Vector3 = _segs[si]["at"]
		if Vector2(at.x - hero.x, at.z - hero.z).length() > DUST_NEAR:
			continue
		if not _thud:
			_thud = true
			Audio.play(RISE_SOUND, at)
		if fx != null and si % DUST_EVERY == 0:
			fx.pop_dust(at + Vector3(0, 0.1, 0), 1.4 * height_k)


## The barrier falls apart (BossPatterns: the bullets' end, or the end of his dazed seconds, or the pattern called off):
## every piece topples or rolls and sinks within spread_s + fall_s, sand where the hero can see, a crash; then it goes.
func fall() -> void:
	if fall_t >= 0.0:
		return
	fall_t = 0.0
	var fx = _game.get("fx") if _game != null else null
	var hero := _hero()
	var best := INF
	var best_at := Vector3.INF
	var puffs := 0
	for k in range(_segs.size()):
		var at: Vector3 = _segs[k]["at"]
		var d := Vector2(at.x - hero.x, at.z - hero.z).length()
		if d < best:
			best = d
			best_at = at
		if fx != null and d <= DUST_NEAR and k % (DUST_EVERY + 1) == 0 and puffs < 10:
			puffs += 1
			fx.sand(at + Vector3(0, 0.3, 0), 1.1 * height_k)
	if best <= DUST_NEAR * 1.5 and best_at != Vector3.INF:
		Audio.play(FALL_SOUND, best_at)


## Whether it has begun to fall (tests).
func is_falling() -> bool:
	return fall_t >= 0.0


## Warm-up (Warmup): one piece of each look's body and glow drawn once, so the shader's instanced pipeline compiles under
## the spawn beam instead of at a boss's first barrier.
static func warm(parent: Node3D) -> void:
	for piece_look: Array in [["iron_fence", "bar"], ["iron_fence", "bar_glow"]]:
		var meshes := BarrierMeshes.parts(str(piece_look[0]))
		var mesh: Mesh = meshes.get(str(piece_look[1]))
		if mesh == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("glow", 1.0 if BarrierMeshes.GLOW_PARTS.has(str(piece_look[1])) else 0.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		mm.set_instance_custom_data(0, Color(0, 0, 0.5, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		parent.add_child(mmi)
