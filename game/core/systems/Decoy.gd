## Pass 69 (lane HERO): May's Inflatable May, the perk whose `special` is "decoy" (content/perks/inflatable_may). After
## `first` s, then every `every` s, she throws an inflatable double of herself `throw_min`..`throw_max` m away in a random
## direction; it flies `flight` s and lands, and a faint pink circle of `radius` m marks the spot. For `duration` s every
## creature inside the circle (Elites too, never a boss) goes for the doll instead of her: it walks to it and bites it
## (EnemyManager.fool / decoy_target; the bites do nothing), with a pink "?" bobbing over its head. Then the doll pops (a
## pink puff and a squeak) and they hunt her again. Game._tick_decoy makes this node the first time a decoy perk is held.
## Pass 70 (lane TRAMP, Garry: "the inflatable version of her should inflate from a little hockey puck"): what flies is
## a small black puck (PUCK_R, built in code); it comes down SLIDE m short of the doll's spot and slides there in
## SLIDE_TIME s with a hiss, then the doll blows up out of it in INFLATE_TIME s (0 -> INFLATE_PEAK -> 1, a wobble); the
## circle and the fooling start once it stands full size.
class_name Decoy
extends Node3D

const DOLL_PATH := "res://content/characters/may/may_decoy.png"
const MARK_PATH := "res://art/ui/decoy_question.png"
const DOLL_H := 1.9          # metres from the doll's feet to its raised hands
const ARC_H := 2.2           # the throw's height at its top
const MARK_MAX := 128
const MARK_SIZE := 0.8
const MARK_POP := 0.18       # seconds a new "?" takes to pop in
const SCAN_EVERY := 0.15     # how often the circle is searched for creatures walking in
const PINK := Color(1.0, 0.42, 0.75)
# pass 70: the puck it comes out of
const PUCK_R := 0.125        # 0.25 m across
const PUCK_H := 0.07
const SLIDE := 0.5           # it lands this far short of the doll's spot and slides the rest
const SLIDE_TIME := 0.25
const INFLATE_TIME := 0.3    # the doll's scale: 0, INFLATE_PEAK at INFLATE_PEAK_AT of the time, then 1
const INFLATE_PEAK := 1.12
const INFLATE_PEAK_AT := 0.7

# FLYING: the puck in the air; SLIDING: on the sand, sliding to the spot; INFLATING: the doll blowing up out of it
enum { IDLE, FLYING, FOOLING, SLIDING, INFLATING }

var game: Node = null
var phase := IDLE
var clock := -1.0            # seconds until the next throw (-1: not started yet)
var t := 0.0                 # seconds into the flight or the fooling
var from := Vector3.ZERO
var to := Vector3.ZERO
var land_at := Vector3.ZERO  # where the puck comes down (pass 70: SLIDE short of `to`)
var puck: MeshInstance3D = null
var inflations := 0
var doll: BillboardSprite = null
var _doll_lift := 0.0
var _doll_h := DOLL_H
var _ring := -1
var _disc := -1
var _scan := 0.0
var _bites_seen := 0
var _wobble := 0.0
var _land_squash := 0.0
var _mm: MultiMesh = null
var _mark_age: Dictionary = {}   # creature index -> seconds since it was fooled (the "?" pops in)
# for the tests and the captures
var throws := 0
var pops := 0
var fooled_total := 0
var marks_shown := 0


## A perk's decoy number (Run.perk_param by the mechanism), or `default`.
static func param(key: String, default: float) -> float:
	return Run.perk_param("decoy", key, default)


## Whether the hero holds a perk whose special is "decoy".
static func active() -> bool:
	for pk in Run.perks:
		var def: PerkDef = Registry.perk(str(pk))
		if def and def.special == "decoy":
			return true
	return false


func setup(p_game: Node) -> void:
	game = p_game
	_build_marks()


func _enemies() -> EnemyManager:
	return game.get("enemies") as EnemyManager if game else null


func _ground(p: Vector3) -> Vector3:
	var m = game.get("map") if game else null
	if m:
		return Vector3(p.x, m.height_at(p.x, p.z), p.z)
	return p


func tick(delta: float) -> void:
	match phase:
		IDLE:
			if not active():
				clock = -1.0
				return
			if clock < 0.0:
				clock = param("first", 6.0)
			clock -= delta
			if clock <= 0.0:
				throw_now()
		FLYING:
			_tick_flight(delta)
		SLIDING:
			_tick_slide(delta)
		INFLATING:
			_tick_inflate(delta)
		FOOLING:
			_tick_fooling(delta)


## The landing spot: `throw_min`..`throw_max` m from `here` in a random direction, inside the arena; a few tries for one
## off the rocks.
func pick_spot(here: Vector3) -> Vector3:
	var lo := param("throw_min", 4.0)
	var hi := maxf(param("throw_max", 7.0), lo)
	var m = game.get("map") if game else null
	var em := _enemies()
	var best := here
	for k in range(6):
		var a := randf() * TAU
		var p := here + Vector3(cos(a), 0.0, sin(a)) * randf_range(lo, hi)
		if m and m.has_method("clamp_to_arena"):
			p = m.clamp_to_arena(p)
		best = p
		if em == null or not _on_rock(em.obstacles, p):
			break
	return _ground(best)


## Whether `p` lands inside a rock's circle (obstacles are Vector3(x, z, radius)).
static func _on_rock(obstacles: Array, p: Vector3) -> bool:
	for o in obstacles:
		var v: Vector3 = o
		if Vector2(p.x - v.x, p.z - v.y).length() < v.z + 0.5:
			return true
	return false


## Throws the doll now (the clock's moment; the arena and the tests call it directly).
func throw_now() -> void:
	var pl = game.get("player") if game else null
	if pl == null:
		return
	if phase == FOOLING:
		_pop()
	from = (pl as Node3D).global_position
	to = pick_spot(from)
	land_at = _short_of(from, to)
	t = 0.0
	phase = FLYING
	throws += 1
	clock = param("every", 30.0)
	# pass 70: what flies is the puck; the doll comes out of it where it stops
	if doll:
		doll.visible = false
	_show_puck()
	_place_puck(from + Vector3(0.0, 1.0, 0.0))
	Audio.play("w_lob_throw", from)


## Where the puck comes down (pass 70): SLIDE m short of `b` on the line from `a`, on the ground (right at `b` when the
## throw is shorter than the slide).
func _short_of(a: Vector3, b: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() <= SLIDE + 0.1:
		return b
	return _ground(b - d.normalized() * SLIDE)


func _show_puck() -> void:
	if puck == null:
		puck = MeshInstance3D.new()
		puck.name = "Puck"
		var cyl := CylinderMesh.new()
		cyl.top_radius = PUCK_R
		cyl.bottom_radius = PUCK_R
		cyl.height = PUCK_H
		cyl.radial_segments = 24
		cyl.rings = 1
		puck.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.02, 0.02, 0.025)
		m.roughness = 0.35
		m.metallic_specular = 0.6
		# black under the warm haze stays black (pass 70: the fog browned the trampoline's mat)
		m.set("disable_fog", true)
		puck.material_override = m
		puck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puck)
	puck.visible = true
	puck.rotation = Vector3.ZERO


## The puck's middle at `at`'s height plus half its thickness (it lies on the sand).
func _place_puck(at: Vector3) -> void:
	if puck:
		puck.global_position = at + Vector3(0.0, PUCK_H * 0.5, 0.0)


## The doll's size as it blows up, `k` from 0 to 1 of INFLATE_TIME: out of nothing, past full size to INFLATE_PEAK at
## INFLATE_PEAK_AT, settling back to 1.
static func inflate_scale(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	if x < INFLATE_PEAK_AT:
		var u := x / INFLATE_PEAK_AT
		return INFLATE_PEAK * (1.0 - (1.0 - u) * (1.0 - u))
	return lerpf(INFLATE_PEAK, 1.0, smoothstep(0.0, 1.0, (x - INFLATE_PEAK_AT) / (1.0 - INFLATE_PEAK_AT)))


func _show_doll() -> void:
	if doll == null:
		doll = BillboardSprite.new()
		doll.name = "InflatableMay"
		add_child(doll)
		var tex: Texture2D = load(DOLL_PATH) if ResourceLoader.exists(DOLL_PATH) else null
		if tex == null:
			tex = load(MARK_PATH)
		# the painting's opaque box is the doll (a painting with a margin is sized by what is drawn)
		var img := tex.get_image()
		var used := Rect2i(0, 0, tex.get_width(), tex.get_height())
		if img:
			if img.is_compressed():
				img.decompress()
			used = img.get_used_rect()
		var th := float(tex.get_height())
		var uh := float(maxi(used.size.y, 1))
		_doll_h = DOLL_H * th / uh
		_doll_lift = -(th - float(used.end.y)) / th * _doll_h
		doll.setup(tex, {"idle": 1}, ["idle"], _doll_h)
	doll.visible = true
	doll.set_squash(1.0, 1.0)
	doll.set_roll(0.0)
	doll.set_flash(0.0)


func _place_doll(at: Vector3) -> void:
	if doll:
		doll.global_position = at + Vector3(0.0, _doll_lift, 0.0)


func _tick_flight(delta: float) -> void:
	var fl := maxf(param("flight", 0.6), 0.05)
	t += delta
	var k := clampf(t / fl, 0.0, 1.0)
	var p := from.lerp(land_at, k)
	p.y = lerpf(from.y + 1.0, land_at.y, k) + ARC_H * 4.0 * k * (1.0 - k)
	_place_puck(p)
	if puck:
		# spinning flat as a thrown puck does, wobbling a little
		puck.rotation = Vector3(sin(t * 9.0) * 0.3, t * 16.0, cos(t * 7.0) * 0.22)
	if k >= 1.0:
		_puck_down()


## The puck hits the sand (pass 70): a little spray, the hiss starts, it slides to the doll's spot.
func _puck_down() -> void:
	phase = SLIDING
	t = 0.0
	_place_puck(land_at)
	if puck:
		puck.rotation = Vector3(0.0, puck.rotation.y, 0.0)
	var fx = game.get("fx") if game else null
	if fx:
		fx.sand(land_at, 0.35)
	Audio.play("pk_decoy_hiss", land_at)


func _tick_slide(delta: float) -> void:
	t += delta
	var k := clampf(t / SLIDE_TIME, 0.0, 1.0)
	# slowing to a stop
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	_place_puck(_ground(land_at.lerp(to, e)))
	if puck:
		puck.rotation.y += delta * 16.0 * (1.0 - k)
	if k >= 1.0:
		_place_puck(to)
		phase = INFLATING
		t = 0.0
		inflations += 1
		_show_doll()
		doll.set_squash(0.0, 0.0)
		_place_doll(to)


## The doll blows up out of the puck (pass 70): from nothing past full size and back (inflate_scale), wobbling as the
## air goes in; full size, the fooling starts (_land).
func _tick_inflate(delta: float) -> void:
	t += delta
	var k := clampf(t / INFLATE_TIME, 0.0, 1.0)
	var s := inflate_scale(k)
	var wob := sin(k * PI * 5.0) * 0.1 * (1.0 - k)
	if doll:
		doll.set_squash(s * (1.0 + wob), s * (1.0 - wob))
		# the painting's margin under the feet shrinks with it, so the feet stay on the puck
		doll.global_position = to + Vector3(0.0, _doll_lift * s, 0.0)
	if k >= 1.0:
		_land()


func _land() -> void:
	phase = FOOLING
	t = 0.0
	_scan = 0.0
	_wobble = 0.0
	# pass 70: the inflation's overshoot was the landing; a small settle after it
	_land_squash = 0.35
	_mark_age.clear()
	if puck:
		puck.visible = false
	_show_doll()
	_place_doll(to)
	if doll:
		doll.set_roll(0.0)
	var r := param("radius", 6.5)
	var tg = game.get("telegraphs") if game else null
	if tg:
		# a weak circle: a thin pink band and the faintest wash inside it
		_ring = tg.hold_ring(to + Vector3(0, 0.03, 0), r, Color(PINK.r, PINK.g, PINK.b, 0.34))
		_disc = tg.hold_disc(to + Vector3(0, 0.02, 0), r, Color(PINK.r, PINK.g, PINK.b, 0.035))
		tg.flash_ring(to, r, PINK, 0.35)
	var fx = game.get("fx") if game else null
	if fx:
		fx.pop_dust(to, 0.5)
	Audio.play("pk_decoy_land", to)
	var em := _enemies()
	if em:
		em.decoy_at = to
		em.decoy_on = true
		_bites_seen = em.decoy_bites
	_fool_inside()


## Every creature in the circle that is not fooled yet is now (EnemyManager.fool: never a boss).
func _fool_inside() -> void:
	var em := _enemies()
	if em == null:
		return
	var r := param("radius", 6.5)
	for i in em.indices_in_radius(to, r):
		if em.fool(i):
			fooled_total += 1
			_mark_age[i] = 0.0


func _tick_fooling(delta: float) -> void:
	t += delta
	var em := _enemies()
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		_fool_inside()
	if em and em.decoy_bites != _bites_seen:
		_bites_seen = em.decoy_bites
		_wobble = 1.0
	_wobble = maxf(_wobble - delta * 4.0, 0.0)
	_land_squash = maxf(_land_squash - delta * 3.5, 0.0)
	if doll:
		# it settles from the landing's squash, sways on its own and shudders when bitten
		var sway := sin(t * 5.0) * 0.04 + sin(t * 31.0) * 0.08 * _wobble
		var sq := _land_squash * 0.3 * cos(t * 14.0)
		doll.set_squash(1.0 + sq + sway, 1.0 - sq)
		doll.set_flash(0.45 * _wobble)
	_draw_marks(delta)
	if t >= param("duration", 2.0):
		_pop()


## The doll pops: a pink puff, a squeak, the circle gone, everyone back on the hero.
func _pop() -> void:
	var em := _enemies()
	if em:
		em.unfool_all()
	var tg = game.get("telegraphs") if game else null
	if tg:
		if _ring >= 0:
			tg.release(_ring)
		if _disc >= 0:
			tg.release(_disc)
	_ring = -1
	_disc = -1
	var fx = game.get("fx") if game else null
	if fx:
		fx.burst(to + Vector3(0, DOLL_H * 0.5, 0), PINK, 1.3)
		fx.pop_dust(to, 0.6)
	Audio.play("pk_decoy_pop", to)
	if doll:
		doll.visible = false
	if puck:
		puck.visible = false
	_mark_age.clear()
	if _mm:
		_mm.visible_instance_count = 0
	marks_shown = 0
	phase = IDLE
	pops += 1


func fooling() -> bool:
	return phase == FOOLING


# ---------------------------------------------------------------- the "?" marks

func _build_marks() -> void:
	if not ResourceLoader.exists(MARK_PATH):
		return
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_mm.mesh = quad
	_mm.instance_count = MARK_MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DecoyMarks"
	mmi.multimesh = _mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/decoy_mark.gdshader")
	mat.set_shader_parameter("tex", load(MARK_PATH))
	mat.render_priority = 10
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


## One bobbing pink "?" over every fooled creature, from its feet up past the top of its figure.
func _draw_marks(delta: float) -> void:
	var em := _enemies()
	if em == null:
		return
	var n := 0
	for i in em.fooled_indices():
		var age: float = float(_mark_age.get(i, 0.0)) + delta
		_mark_age[i] = age
		if _mm == null or n >= MARK_MAX:
			n += 1
			continue
		var td: Dictionary = em.types[em.type_idx[i]]
		var head: float = float(td.get("head", 0.9))
		var lift: float = em.size[i] * head + 0.3 + MARK_SIZE * 0.5
		if em.badge_of(i) != "":
			# over the crown, the skull or the gear, not on it
			lift += MARK_SIZE * 0.9
		_mm.set_instance_transform(n, Transform3D(Basis(), em.pos[i] + Vector3(0, em.lift_h[i], 0)))
		_mm.set_instance_custom_data(n, Color(lift, MARK_SIZE, float(i) * 1.7, clampf(age / MARK_POP, 0.0, 1.0)))
		n += 1
	marks_shown = n
	if _mm:
		_mm.visible_instance_count = mini(n, MARK_MAX)
