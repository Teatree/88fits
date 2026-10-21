## The Frisbee (pass 69, lane FRIS; Garry: "Throws a frisbee in curving arcs, can't predict which direction they will go
## on a given throw, but they mostly draw arcs away from the hero towards an enemy with a deviation to the left or right
## (the more projectiles the hero throws the higher the deviation). Frisbee hits through enemies, but has a damage drop
## off like the Revolver, but frisbee never stops"). A self-contained flight: no ProjectileManager shot, no held model.
##
## - aim: the nearest creature within range (aim_index), else where he faces; a volley of `amount` discs fans out
##   `fan_deg` apart round that line;
## - path: each disc leaves its line bend_deg() to a side picked at random per disc and turns back at a steady rate, so
##   it crosses the line at the target's distance (clamped to BEND_MIN_M..range; the whole turn never more than the bend
##   + TURN_EXTRA_DEG); it flies its whole `range` (the stat), then glides down for `glide_seconds` and fades out;
## - hits: every creature within `hit_radius` x the disc's size_mult of it, once a flight, at damage x falloff_mult() (each
##   creature after the first falloff.step less than the one before, never under falloff.floor); poison and fire as the
##   sheet says; a modest knockback along the flight; none while it glides down;
## - `disc {look plain|razors|saucer, size, albedo, emission, energy, spin, trail, size_mult, haze}`: the disc drawn
##   (disc_mesh, built here: lime plastic, the hot-pink "Shredder" with razor blades round the rim, the chrome-and-pink
##   saucer with glowing razors), `size` its radius in metres times size_mult (Carry's x1.5); `trail` (pass 95, lane
##   ITEMS) a block {style streak|sparks|glow|none, length, width, alpha, colour}: the trail behind the disc, one style
##   per look (trail_params);
## - pass 95 (lane ITEMS): "Fire forward" (FireForward.dir, Settings.fire_forward): along the hero's facing while no
##   creature stands within 75% of the range;
## - `carry {chance, drop_hit}` (Carry): the first creature a disc hits may ride it to the end of its flight, held by the
##   Gravity Gun's grip (EnemyManager.grabbable/grab/place_held/release: never a boss, an Elite, an elite-modded or an
##   ungrabbable creature, and nothing hits it while it rides), one a disc; it is set down where the disc comes down and
##   takes drop_hit x the disc's damage there (the Flying Saucer's 1.0);
## - `proc_mult` (Trick Shot): Run.trick_proc_mult reads it for life steal, crit, Cold Snap and Vulture; here for `stun`;
## - `stun {chance, seconds}`: a stun roll on every hit that does not kill (none on the plain disc), chance x proc_mult;
## - `loop {radius, from, to}` (the Flying Saucer): once a flight, at a random point between `from` and `to` of its range,
##   the disc flies one full circle of `radius` m the way it is already turning, then goes on along its arc.
extends WeaponBehavior

const BEND_MIN_M := 3.0
const TURN_EXTRA_DEG := 60.0
## Seconds between the points of a disc's trail (its length in seconds is the trail block's `length`).
const TRAIL_STEP := 0.025
const HIT_SFX_GAP := 0.08
const HAZE_GAP := 0.05
const SEGMENTS := 40
## How far out from the hero a disc starts (clear of his painting)
const START_OUT := 0.7

## Diagnostics and tests: throws made, creatures carried, loops flown, hits landed.
var throws := 0
var carries := 0
var loops := 0
var hits := 0
## The discs in the air: Dictionaries (see _launch).
var discs: Array = []
var _hit_sfx_t := 0.0
var _root: Node3D
var _trail_mesh: ImmediateMesh
var _trail_mi: MeshInstance3D
var _look_key := ""
var _mesh: ArrayMesh
var _mats: Array = []
## The trail as the disc params say (trail_params), {} for none; set with the look.
var _trail: Dictionary = {}
var _trail_begun := false  # a surface is open in _trail_mesh: begun by the first quad, so a frame without one never ends an empty surface


func _uses_projectiles() -> bool:
	return false


func _on_setup() -> void:
	_root = Node3D.new()
	_root.name = "Discs"
	_root.top_level = true
	add_child(_root)
	_trail_mesh = ImmediateMesh.new()
	_trail_mi = MeshInstance3D.new()
	_trail_mi.name = "Trails"
	_trail_mi.mesh = _trail_mesh
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.vertex_color_use_as_albedo = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mi.material_override = tm
	_root.add_child(_trail_mi)


func _exit_tree() -> void:
	# a disc still carrying a creature when the weapon goes (an evolution, the run's end) sets it down
	for d: Dictionary in discs:
		_drop(d, false)


# ---------------------------------------------------------------- numbers

## The bend each disc of a volley of `amount` leaves its line at, in degrees: bend_deg + bend_per_extra for every disc past
## the first (25, 37, 49 ...).
static func bend_deg(amount: int, params: Dictionary) -> float:
	return float(params.get("bend_deg", 25.0)) + float(params.get("bend_per_extra", 12.0)) * float(maxi(amount - 1, 0))


## What the creature a disc hits after cutting `n` others takes, as a share of its damage: falloff.step^n, never under
## falloff.floor (x0.85 a creature, down to x0.25).
static func falloff_mult(n: int, params: Dictionary) -> float:
	var f = params.get("falloff", {})
	var fd: Dictionary = f if f is Dictionary else {}
	var step := clampf(float(fd.get("step", 0.85)), 0.0, 1.0)
	var flo := clampf(float(fd.get("floor", 0.25)), 0.0, 1.0)
	return maxf(pow(step, float(maxi(n, 0))), flo)


## The turn rate (radians a metre) of a disc that leaves its line at `theta` radians and should cross it again `dist`
## metres out on a flight of `range_m`: the circle through both (2 sin(theta) / dist), the distance clamped to
## BEND_MIN_M..range, the whole turn never more than theta + TURN_EXTRA_DEG.
static func turn_rate(theta: float, dist: float, range_m: float) -> float:
	var r := maxf(range_m, 0.5)
	var l := clampf(dist, minf(BEND_MIN_M, r), r)
	return minf(2.0 * sin(absf(theta)) / l, (absf(theta) + deg_to_rad(TURN_EXTRA_DEG)) / r)


func _disc_params() -> Dictionary:
	var d = inst.params.get("disc", {})
	return d if d is Dictionary else {}


## The disc's radius in metres: disc.size x disc.size_mult x the weapon's area (Reach and the like make it bigger).
func disc_radius() -> float:
	var dp := _disc_params()
	return maxf(float(dp.get("size", 0.36)) * float(dp.get("size_mult", 1.0)) * maxf(stat("area", 1.0), 0.2), 0.05)


## How far from its centre a disc cuts: hit_radius x disc.size_mult x the weapon's area.
func hit_radius() -> float:
	var dp := _disc_params()
	return maxf(float(inst.params.get("hit_radius", 0.55)) * float(dp.get("size_mult", 1.0)) * maxf(stat("area", 1.0), 0.2), 0.1)


func _ground(p: Vector3) -> float:
	var m = game.get("map") if game else null
	if m != null and m.has_method("height_at"):
		return float(m.height_at(p.x, p.z))
	return 0.0


# ---------------------------------------------------------------- throwing

func _fire() -> bool:
	if player == null:
		return false
	var em: EnemyManager = game.enemies
	var pp: Vector3 = player.global_position
	var range_m := maxf(stat("range", 12.0), 1.0)
	# pass 95 (lane ITEMS): "Fire forward" (FireForward.dir, Settings.fire_forward): along his facing, the arc crossing its
	# line at the range's end, while no creature stands within 75% of the range; else at the nearest as before
	var fwd: Vector3 = FireForward.dir(inst, player, em, 12.0)
	var tgt: int = -1 if fwd != Vector3.ZERO else (aim_index(pp, range_m) if em else -1)
	var aim: Vector3 = fwd
	var dist := range_m
	if tgt >= 0:
		aim = em.pos[tgt] - pp
		aim.y = 0.0
		dist = aim.length()
	if aim.length_squared() < 0.0001:
		aim = player.forward() if player.has_method("forward") else Vector3.FORWARD
		aim.y = 0.0
	if aim.length_squared() < 0.0001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	_refresh_look()
	var n := maxi(stat_int("amount", 1), 1)
	var fan := deg_to_rad(float(inst.params.get("fan_deg", 16.0)))
	for k in range(n):
		var off := (float(k) - float(n - 1) * 0.5) * fan
		_launch(aim.rotated(Vector3.UP, off), dist, n)
	throws += 1
	sfx("fire", pp)
	return true


## One disc into the air along `dir`, to cross that line again `dist` metres out, one of a volley of `n`.
func _launch(dir: Vector3, dist: float, n: int, side: float = 0.0) -> Dictionary:
	if _mesh == null:
		_refresh_look()
	var pr := inst.params
	var range_m := maxf(stat("range", 12.0), 1.0)
	var theta := deg_to_rad(bend_deg(n, pr))
	var sd := side if side != 0.0 else (-1.0 if randf() < 0.5 else 1.0)
	# it leaves from a point on its aim line START_OUT ahead of him, so it crosses the line again `dist` from him
	var rate := turn_rate(theta, dist - START_OUT, range_m)
	var pp: Vector3 = player.global_position
	var start := pp + dir * START_OUT
	var height := float(pr.get("height", 1.0))
	start.y = _ground(start) + height
	var d := {
		"pos": start, "dir0": dir, "side": sd, "theta": theta, "rate": rate, "s": 0.0, "range": range_m,
		"speed": maxf(stat("speed", 13.0), 1.0), "dmg": stat("damage", 14.0), "kb": stat("knockback", 1.5),
		"height": height, "hit": {}, "n": 0, "carry": -1, "carry_serial": -1, "phase": 0, "glide_t": 0.0,
		"loop_at": -1.0, "loop_t": -1.0, "looped": 0, "loop_c": Vector3.ZERO, "loop_p0": Vector3.ZERO, "loop_sense": 1.0,
		"loop_ang": 0.0, "spin": randf() * TAU, "radius": disc_radius(), "hit_r": hit_radius(),
		"trail": PackedVector3Array(), "tage": PackedFloat32Array(), "tclock": 0.0, "haze_t": 0.0, "node": null,
	}
	var lp = pr.get("loop")
	if lp is Dictionary:
		var a := clampf(float((lp as Dictionary).get("from", 0.3)), 0.0, 1.0)
		var b := clampf(float((lp as Dictionary).get("to", 0.7)), a, 1.0)
		d["loop_at"] = range_m * randf_range(a, b)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	for s in range(mini(_mats.size(), _mesh.get_surface_count())):
		mi.set_surface_override_material(s, _mats[s])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	d["node"] = mi
	discs.append(d)
	_place(d)
	return d


## The way a disc is heading now (on the ground plane).
func heading(d: Dictionary) -> Vector3:
	var a: float = float(d["side"]) * (float(d["theta"]) - float(d["rate"]) * float(d["s"])) + float(d["loop_ang"])
	return (d["dir0"] as Vector3).rotated(Vector3.UP, a)


# ---------------------------------------------------------------- flight

func _tick(delta: float) -> void:
	_hit_sfx_t -= delta
	var k := discs.size() - 1
	while k >= 0:
		var d: Dictionary = discs[k]
		var done := false
		if int(d["phase"]) == 0:
			_fly(d, delta)
		else:
			done = _glide(d, delta)
		if done:
			_drop(d, true)
			var node = d["node"]
			if node != null and is_instance_valid(node):
				(node as Node).queue_free()
			discs.remove_at(k)
		k -= 1
	_draw_trails(delta)


func _fly(d: Dictionary, delta: float) -> void:
	var speed: float = d["speed"]
	var p: Vector3 = d["pos"]
	if float(d["loop_t"]) >= 0.0:
		# the Flying Saucer's loop: one full circle the way it is turning, then on along its arc from where it began
		var lr := _loop_radius()
		var period := TAU * lr / speed
		d["loop_t"] = float(d["loop_t"]) + delta
		var f := clampf(float(d["loop_t"]) / period, 0.0, 1.0)
		var ang: float = float(d["loop_sense"]) * TAU * f
		var c: Vector3 = d["loop_c"]
		p = c + ((d["loop_p0"] as Vector3) - c).rotated(Vector3.UP, ang)
		d["loop_ang"] = ang
		if f >= 1.0:
			d["loop_t"] = -1.0
			d["loop_ang"] = 0.0
			d["looped"] = int(d["looped"]) + 1
			loops += 1
			p = d["loop_p0"]
	else:
		var s0: float = d["s"]
		var s1 := minf(s0 + speed * delta, float(d["range"]))
		var amid: float = float(d["side"]) * (float(d["theta"]) - float(d["rate"]) * (s0 + s1) * 0.5)
		p += (d["dir0"] as Vector3).rotated(Vector3.UP, amid) * (s1 - s0)
		d["s"] = s1
		var la: float = d["loop_at"]
		if la >= 0.0 and int(d["looped"]) == 0 and s0 < la and s1 >= la and s1 < float(d["range"]):
			_begin_loop(d, p)
		if s1 >= float(d["range"]):
			d["phase"] = 1
	p.y = _ground(p) + float(d["height"])
	d["pos"] = p
	_hits(d)
	_carry_follow(d)
	_trail_push(d, delta)
	_haze(d, delta)
	_place(d)


func _loop_radius() -> float:
	var lp = inst.params.get("loop")
	return maxf(float((lp as Dictionary).get("radius", 1.3)) if lp is Dictionary else 1.3, 0.3)


## Into the loop at `p`: the circle's centre on the inside of the turn, so the disc goes round the way it already bends.
func _begin_loop(d: Dictionary, p: Vector3) -> void:
	var h := heading(d)
	# the arc's heading angle falls as s grows when side > 0: it turns the negative way round UP
	var sense := -signf(float(d["side"]))
	if sense == 0.0:
		sense = 1.0
	var r := _loop_radius()
	# a point on a circle round C moving the positive way round UP goes along UP x (P - C): P - C = sense r (-hz, 0, hx)
	d["loop_c"] = p + Vector3(h.z, 0.0, -h.x) * sense * r
	d["loop_p0"] = p
	d["loop_sense"] = sense
	d["loop_t"] = 0.0


## Its whole range flown: it slows, sinks to the sand and fades out over glide_seconds. True when it is gone.
func _glide(d: Dictionary, delta: float) -> bool:
	var g := maxf(float(inst.params.get("glide_seconds", 0.45)), 0.05)
	d["glide_t"] = float(d["glide_t"]) + delta
	var f := clampf(float(d["glide_t"]) / g, 0.0, 1.0)
	var p: Vector3 = d["pos"]
	p += heading(d) * float(d["speed"]) * 0.6 * (1.0 - f) * delta
	p.y = _ground(p) + lerpf(float(d["height"]), 0.12, f * (2.0 - f))
	d["pos"] = p
	var node = d["node"]
	if node != null and is_instance_valid(node):
		(node as GeometryInstance3D).transparency = clampf((f - 0.3) / 0.7, 0.0, 1.0)
	_carry_follow(d)
	_trail_push(d, delta)
	_place(d)
	return f >= 1.0


## Every creature the disc touches now that it has not cut this flight.
func _hits(d: Dictionary) -> void:
	var em: EnemyManager = game.enemies
	if em == null:
		return
	var p: Vector3 = d["pos"]
	var hr: float = d["hit_r"]
	var seen: Dictionary = d["hit"]
	for e in em.indices_in_radius(p, hr + 1.2):
		if em.alive[e] == 0 or em.state[e] == EnemyManager.STATE_DYING or e == int(d["carry"]):
			continue
		var key: int = em.serial[e]
		if seen.has(key):
			continue
		var dx: float = em.pos[e].x - p.x
		var dz: float = em.pos[e].z - p.z
		var reach: float = hr + em.radius[e]
		if dx * dx + dz * dz > reach * reach:
			continue
		seen[key] = true
		_strike(d, e)


func _strike(d: Dictionary, e: int) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var first := int(d["n"]) == 0
	var dmg: float = float(d["dmg"]) * falloff_mult(int(d["n"]), inst.params)
	d["n"] = int(d["n"]) + 1
	hits += 1
	var pdmg := stat("poison_damage", 0.0)
	if pdmg > 0.0:
		em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 4.0))
	var fdmg := stat("fire_damage", 0.0)
	if fdmg > 0.0:
		em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
	var killed := em.damage(e, dmg, wid, heading(d), float(d["kb"]))
	if killed:
		inst.kills += 1
	else:
		_stun_roll(em, e)
		if first:
			_try_carry(d, e)
	if game.has_method("fx_hit"):
		game.fx_hit(em.pos[e] + Vector3(0, 0.5, 0), inst.def)
	if _hit_sfx_t <= 0.0:
		_hit_sfx_t = HIT_SFX_GAP
		sfx("hit", em.pos[e])


## `stun {chance, seconds}`: a stun on a hit that did not kill, the chance x Trick Shot's proc_mult (EnemyManager.stun:
## never a boss or an Elite).
func _stun_roll(em: EnemyManager, i: int) -> void:
	var st = inst.params.get("stun")
	if not st is Dictionary:
		return
	var chance := float((st as Dictionary).get("chance", 0.0)) * maxf(float(inst.params.get("proc_mult", 1.0)), 0.0)
	if chance <= 0.0 or randf() >= chance:
		return
	em.stun(i, float((st as Dictionary).get("seconds", 1.0)))


## Carry: the first creature the disc hits rides it, `carry.chance` of the time, when the Gravity Gun could take it.
func _try_carry(d: Dictionary, e: int) -> void:
	var cr = inst.params.get("carry")
	if not cr is Dictionary or int(d["carry"]) >= 0:
		return
	var ch := float((cr as Dictionary).get("chance", 0.0))
	if ch <= 0.0 or randf() >= ch:
		return
	var em: EnemyManager = game.enemies
	if not em.grabbable(e):
		return
	em.grab(e)
	d["carry"] = e
	d["carry_serial"] = em.serial[e]
	carries += 1


## Whether the creature a disc carries is still the one it took and still in its grip.
func _carrying(d: Dictionary) -> bool:
	var c: int = d["carry"]
	if c < 0:
		return false
	var em: EnemyManager = game.enemies if game != null and is_instance_valid(game) else null
	if em == null or not is_instance_valid(em) or em.alive[c] == 0 or em.serial[c] != int(d["carry_serial"]) or em.held[c] == 0:
		d["carry"] = -1
		return false
	return true


func _carry_follow(d: Dictionary) -> void:
	if not _carrying(d):
		return
	var em: EnemyManager = game.enemies
	var p: Vector3 = d["pos"]
	em.place_held(int(d["carry"]), p + Vector3(0, 0.04, 0))


## The ride is over: the creature is set down where the disc came down, taking `carry.drop_hit` x the disc's damage
## (`hit` false when the weapon itself is going: it is only let go).
func _drop(d: Dictionary, hit: bool) -> void:
	if not _carrying(d):
		return
	var em: EnemyManager = game.enemies
	var c: int = d["carry"]
	d["carry"] = -1
	em.release(c)
	var cr = inst.params.get("carry")
	var dh := float((cr as Dictionary).get("drop_hit", 0.0)) if cr is Dictionary else 0.0
	if hit and dh > 0.0 and em.is_alive(c):
		if em.damage(c, float(d["dmg"]) * dh, inst.def.id, Vector3.ZERO, 0.0):
			inst.kills += 1
	if game.has_method("fx_sand"):
		game.fx_sand(em.pos[c], 0.8)


# ---------------------------------------------------------------- looks

## The disc's transform: flat, spinning round its own axis, banked into its turn.
func _place(d: Dictionary) -> void:
	var node = d["node"]
	if node == null or not is_instance_valid(node):
		return
	var dp := _disc_params()
	d["spin"] = fmod(float(d["spin"]) + float(dp.get("spin", 16.0)) * get_process_delta_time(), TAU)
	var h := heading(d)
	var bank := -0.2 * signf(float(d["side"])) if int(d["phase"]) == 0 else 0.08
	if float(d["loop_t"]) >= 0.0:
		bank = 0.35 * float(d["loop_sense"])
	var axis := h if h.length_squared() > 0.0001 else Vector3.FORWARD
	var b := Basis(axis.normalized(), bank) * Basis(Vector3.UP, float(d["spin"]))
	var r: float = d["radius"]
	(node as Node3D).global_transform = Transform3D(b.scaled(Vector3(r, r, r)), d["pos"])


## The disc's trail points age, the old ones go (after the block's `length`), and a new one is laid every TRAIL_STEP s
## while it flies (none while it glides down: the ribbon fades out behind it).
func _trail_push(d: Dictionary, delta: float) -> void:
	if _trail.is_empty():
		return
	var pts: PackedVector3Array = d["trail"]
	var age: PackedFloat32Array = d["tage"]
	var length: float = float(_trail["length"])
	for k in range(age.size()):
		age[k] += delta
	while not age.is_empty() and age[0] >= length:
		age.remove_at(0)
		pts.remove_at(0)
	d["tclock"] = float(d["tclock"]) - delta
	if float(d["tclock"]) <= 0.0 and int(d["phase"]) == 0:
		d["tclock"] = TRAIL_STEP
		pts.append(d["pos"])
		age.append(0.0)
	d["trail"] = pts
	d["tage"] = age


## The faint green poison haze under the Flying Saucer (`disc.haze`).
func _haze(d: Dictionary, delta: float) -> void:
	if not bool(_disc_params().get("haze", false)) or game.get("fx") == null:
		return
	d["haze_t"] = float(d["haze_t"]) - delta
	if float(d["haze_t"]) > 0.0:
		return
	d["haze_t"] = HAZE_GAP
	var p: Vector3 = d["pos"]
	var a := randf() * TAU
	var r: float = d["radius"]
	game.fx.mote(p + Vector3(cos(a) * r * 0.8, -0.15, sin(a) * r * 0.8), Vector3(cos(a) * 0.4, -0.5, sin(a) * 0.4), 0.55, 0.32 * r / 0.36, Color(0.45, 1.0, 0.35, 0.35))


# ---------------------------------------------------------------- the trail (pass 95, lane ITEMS)
## Pass 95 (Garry: "Frisbee - needs a dim trail behind its flight because it's hard to see it right now. Treat each
## visual update of Frisbee with its own trail effect"): `disc.trail` is a block {style, length, width, alpha, colour}
## (true = the look's own style with its numbers, false = none). `style`: "streak" (the plain disc: one faint pale ribbon
## with a brighter thread down its middle), "sparks" (the razors: two thin bright lines off the rim's edges and short
## sparks flicking out and back), "glow" (the saucer: a wide soft glow with a brighter core); "none" = no trail.
## `length`: seconds the trail lingers (a point every TRAIL_STEP s); `width`: the ribbon's full width in disc radii
## (Carry's bigger disc trails wider; for sparks the sparks' length); `alpha`: at the disc, fading to nothing at the end;
## `colour`: #RRGGBB (empty = the look's glow colour lerped toward white by the style's `white`). Every disc of the weapon
## draws into the one ImmediateMesh "Trails" (one draw call for all of them, however many fly); the ribbon keeps fading
## out behind a disc that glides down. Numbers picked by eye on 1080x1920 captures against the sand.
const TRAIL_STYLES := {
	"streak": {"length": 0.4, "width": 1.5, "alpha": 0.6, "white": 0.45},
	"sparks": {"length": 0.32, "width": 0.6, "alpha": 0.9, "white": 0.3},
	"glow": {"length": 0.48, "width": 2.2, "alpha": 0.45, "white": 0.2},
}
## The style each look wears when its block names none.
const LOOK_STYLE := {"plain": "streak", "razors": "sparks", "saucer": "glow"}


## The trail as the disc params say now: {style, length, width, alpha, colour (a Color)}, or {} for none.
func trail_params() -> Dictionary:
	var dp := _disc_params()
	var trb = dp.get("trail", true)
	if trb is bool and not bool(trb):
		return {}
	var block: Dictionary = trb if trb is Dictionary else {}
	var style := str(block.get("style", LOOK_STYLE.get(str(dp.get("look", "plain")), "streak")))
	if style == "none":
		return {}
	if not TRAIL_STYLES.has(style):
		style = "streak"
	var d: Dictionary = TRAIL_STYLES[style]
	var col: Color = _html(str(dp.get("emission", "#7CFF00")), Color(0.49, 1.0, 0.0)).lerp(Color.WHITE, float(d["white"]))
	if block.has("colour"):
		col = _html(str(block["colour"]), col)
	return {"style": style, "length": maxf(float(block.get("length", d["length"])), 0.05),
		"width": maxf(float(block.get("width", d["width"])), 0.0), "alpha": clampf(float(block.get("alpha", d["alpha"])), 0.0, 1.0),
		"colour": col}


## A colour from its HTML code, `fallback` when the code is not one.
static func _html(code: String, fallback: Color) -> Color:
	return Color.html(code) if Color.html_is_valid(code) else fallback


## Every disc's trail in its style, all into the one mesh.
func _draw_trails(_delta: float) -> void:
	if _trail_mesh == null:
		return
	_trail_mesh.clear_surfaces()
	_trail_begun = false
	if _trail.is_empty():
		return
	var style: String = str(_trail["style"])
	var length: float = float(_trail["length"])
	var alpha: float = float(_trail["alpha"])
	var col: Color = _trail["colour"]
	for d: Dictionary in discs:
		var pts: PackedVector3Array = d["trail"]
		var age: PackedFloat32Array = d["tage"]
		if pts.is_empty():
			continue
		var all := pts.duplicate()
		var ages := age.duplicate()
		if int(d["phase"]) == 0:
			all.append(d["pos"])
			ages.append(0.0)
		if all.size() < 2:
			continue
		var r: float = float(d["radius"])
		var w: float = float(_trail["width"]) * r
		match style:
			"sparks":
				_trail_sparks(all, ages, length, w, r, alpha, col)
			"glow":
				# a wide soft layer under a brighter, whiter core
				_trail_ribbon(all, ages, length, w * 0.5, alpha * 0.4, col)
				_trail_ribbon(all, ages, length, w * 0.17, alpha, col.lerp(Color.WHITE, 0.3))
			_:
				# the streak: the pale ribbon and a thin brighter thread down its middle
				_trail_ribbon(all, ages, length, w * 0.5, alpha, col)
				_trail_ribbon(all, ages, length, w * 0.1, alpha * 0.8, col.lerp(Color.WHITE, 0.5))
	if _trail_begun:
		_trail_mesh.surface_end()
		_trail_begun = false


## One flat strip along the points, `half` wide at the disc, tapering and fading with age to nothing at `length` seconds.
func _trail_ribbon(all: PackedVector3Array, ages: PackedFloat32Array, length: float, half: float, alpha: float, col: Color) -> void:
	for k in range(all.size() - 1):
		var a: Vector3 = all[k]
		var b: Vector3 = all[k + 1]
		var along := b - a
		along.y = 0.0
		if along.length_squared() < 0.000001:
			continue
		var side := Vector3(-along.z, 0.0, along.x).normalized()
		var fa := 1.0 - clampf(ages[k] / length, 0.0, 1.0)
		var fb := 1.0 - clampf(ages[k + 1] / length, 0.0, 1.0)
		_quad(a, b, side, half * fa, half * fb, Color(col.r, col.g, col.b, alpha * fa), Color(col.r, col.g, col.b, alpha * fb))


## The razors' trail: two thin bright lines off the rim's edges (0.9 of the radius out), and every other point a short
## spark (`w` long) flicking out from one edge and back, whiter, fading faster.
func _trail_sparks(all: PackedVector3Array, ages: PackedFloat32Array, length: float, w: float, r: float, alpha: float, col: Color) -> void:
	var thick := maxf(r * 0.07, 0.01)
	var edge := r * 0.9
	var spark := col.lerp(Color.WHITE, 0.6)
	for k in range(all.size() - 1):
		var a: Vector3 = all[k]
		var b: Vector3 = all[k + 1]
		var along := b - a
		along.y = 0.0
		if along.length_squared() < 0.000001:
			continue
		var dirn := along.normalized()
		var side := Vector3(-dirn.z, 0.0, dirn.x)
		var fa := 1.0 - clampf(ages[k] / length, 0.0, 1.0)
		var fb := 1.0 - clampf(ages[k + 1] / length, 0.0, 1.0)
		for s: float in [-1.0, 1.0]:
			_quad(a + side * edge * s, b + side * edge * s, side, thick * fa, thick * fb, Color(col.r, col.g, col.b, alpha * fa), Color(col.r, col.g, col.b, alpha * fb))
		if k % 2 == 0:
			var sgn: float = 1.0 if ((k >> 1) & 1) == 0 else -1.0
			var start := a + side * edge * sgn
			var end := start + side * w * sgn - dirn * w * 0.6
			var sdir := end - start
			var sside := Vector3(-sdir.z, 0.0, sdir.x).normalized()
			_quad(start, end, sside, thick * 0.7 * fa, 0.0, Color(spark.r, spark.g, spark.b, alpha * fa * fa), Color(spark.r, spark.g, spark.b, 0.0))


## A quad from `a` to `b`, `ha` and `hb` out to each side of them, in their colours (two triangles; the material culls
## nothing, so the winding does not matter).
func _quad(a: Vector3, b: Vector3, side: Vector3, ha: float, hb: float, ca: Color, cb: Color) -> void:
	var a0 := a - side * ha
	var a1 := a + side * ha
	var b0 := b - side * hb
	var b1 := b + side * hb
	if not _trail_begun:
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_trail_begun = true
	for v: Array in [[a0, ca], [b0, cb], [a1, ca], [a1, ca], [b0, cb], [b1, cb]]:
		_trail_mesh.surface_set_color(v[1])
		_trail_mesh.surface_add_vertex(v[0])


## How many vertices the trails drew this frame (tests, captures): 0 with no trail.
func trail_vertex_count() -> int:
	if _trail_mesh == null or _trail_mesh.get_surface_count() == 0:
		return 0
	var arrays: Array = _trail_mesh.surface_get_arrays(0)
	if arrays.is_empty() or not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
		return 0
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


## The mesh and materials for the disc as the weapon's params say now (a mutation taken changes them).
func _refresh_look() -> void:
	var dp := _disc_params()
	var key := JSON.stringify(dp)
	if key == _look_key and _mesh != null:
		return
	_look_key = key
	var look := str(dp.get("look", "plain"))
	var albedo := Color(str(dp.get("albedo", "#B8FF2A")))
	var emission := Color(str(dp.get("emission", "#7CFF00")))
	var energy := float(dp.get("energy", 0.8))
	_mesh = disc_mesh(look, albedo)
	_mats = disc_materials(look, emission, energy)
	_trail = trail_params()


func refresh_marks() -> void:
	super.refresh_marks()
	_look_key = ""


# ---------------------------------------------------------------- the disc's mesh

## The disc for `look` ("plain", "razors" or "saucer") in `col`, one unit in radius, flat in the XZ plane: its surfaces in
## the order disc_materials gives their materials. Built here, no model file (Garry: "3d object: none" in his hand; the
## projectile is this disc). tools/_p69_fris_ref.gd renders it for the icons' references.
static func disc_mesh(look: String, col: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	match look:
		"saucer":
			# a chrome saucer: a hot-pink top, a chrome belly, a glass bubble, eight glowing razors round the rim
			# the pink top (its rings as shades of the material's pink), the chrome rim and belly
			var light := Color(1, 1, 1)
			var ring := Color(0.72, 0.72, 0.72)
			var top := [[0.0, 0.17], [0.3, 0.165], [0.42, 0.155], [0.45, 0.152], [0.5, 0.147], [0.53, 0.143], [0.76, 0.1]]
			_add_lathe(mesh, top, [light, light, light, ring, ring, light, light], true)
			var chrome := [[0.76, 0.1], [0.9, 0.065], [0.98, 0.035], [1.04, 0.0], [1.0, -0.045], [0.82, -0.095], [0.55, -0.14],
				[0.25, -0.17], [0.0, -0.18]]
			_add_lathe(mesh, chrome, [Color.WHITE], true)
			_add_blades(mesh, 8, 1.07, 0.3, 0.22, Color(1.0, 0.86, 0.93), Color(0.45, 0.08, 0.3))
			var dome := [[0.0, 0.42], [0.1, 0.41], [0.19, 0.38], [0.26, 0.31], [0.3, 0.23], [0.31, 0.15]]
			_add_lathe(mesh, dome, [Color.WHITE], true)
		_:
			var dark := col.darkened(0.22)
			var under := col.darkened(0.45)
			var prof: Array = []
			var cols: Array = []
			if look == "razors":
				# the "Shredder": a darker middle with a silver band and a black ring round it, a pink rim
				var mid := col.darkened(0.35)
				var silver := Color(0.86, 0.86, 0.92)
				var ink := Color(0.08, 0.04, 0.06)
				prof = [[0.0, 0.12], [0.2, 0.119], [0.26, 0.117], [0.29, 0.116], [0.36, 0.113], [0.39, 0.112], [0.5, 0.106],
					[0.52, 0.105], [0.56, 0.102], [0.58, 0.1]]
				cols = [mid, mid, mid, silver, silver, mid, mid, ink, ink, col]
			else:
				prof = [[0.0, 0.12], [0.3, 0.118], [0.55, 0.105]]
				cols = [col, col, col]
			# the flight rings and the rim, the cup underneath
			prof += [[0.6, 0.098], [0.62, 0.095], [0.66, 0.09], [0.68, 0.087], [0.78, 0.075], [0.8, 0.072], [0.83, 0.068],
				[0.85, 0.065], [0.93, 0.048], [0.985, 0.025], [1.0, -0.01], [0.99, -0.06], [0.965, -0.1], [0.92, -0.1],
				[0.9, -0.06], [0.88, -0.02], [0.6, 0.03], [0.0, 0.05]]
			cols += [col, dark, dark, col, col, dark, dark, col, col, col, col, col, dark, under, under, under, under, under]
			_add_lathe(mesh, prof, cols, true)
			if look == "razors":
				_add_blades(mesh, 8, 1.04, 0.36, 0.24, Color(0.8, 0.82, 0.86), Color(0.16, 0.16, 0.18))
	return mesh


## The materials for disc_mesh(look)'s surfaces: the plastic (its colours are the vertex colours) glowing faintly in
## `emission`, the steel razors; the saucer's pink top, chrome belly, glowing razors and glass bubble.
static func disc_materials(look: String, emission: Color, energy: float) -> Array:
	var out: Array = []
	match look:
		"saucer":
			var top := StandardMaterial3D.new()
			top.albedo_color = emission
			top.vertex_color_use_as_albedo = true
			top.roughness = 0.35
			top.emission_enabled = true
			top.emission = emission
			top.emission_energy_multiplier = energy * 0.12
			out.append(top)
			var chrome := StandardMaterial3D.new()
			chrome.albedo_color = Color(0.86, 0.88, 0.94)
			chrome.metallic = 0.75
			chrome.roughness = 0.18
			chrome.emission_enabled = true
			chrome.emission = Color(0.55, 0.58, 0.66)
			chrome.emission_energy_multiplier = 0.35
			out.append(chrome)
			var glow := StandardMaterial3D.new()
			glow.vertex_color_use_as_albedo = true
			glow.emission_enabled = true
			glow.emission = emission
			glow.emission_energy_multiplier = maxf(energy * 0.9, 0.8)
			out.append(glow)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.7, 0.95, 1.0)
			glass.metallic = 0.2
			glass.roughness = 0.08
			glass.emission_enabled = true
			glass.emission = Color(0.4, 0.85, 1.0)
			glass.emission_energy_multiplier = 0.6
			out.append(glass)
		_:
			var body := StandardMaterial3D.new()
			body.vertex_color_use_as_albedo = true
			body.roughness = 0.42
			body.emission_enabled = true
			body.emission = emission
			body.emission_energy_multiplier = energy * 0.3
			out.append(body)
			if look == "razors":
				var steel := StandardMaterial3D.new()
				steel.vertex_color_use_as_albedo = true
				steel.metallic = 0.6
				steel.roughness = 0.3
				out.append(steel)
	return out


## A surface turned round the Y axis from `prof` ([r, y] pairs from the middle outwards; a profile that comes back under
## the rim faces outwards all the way, as its order says), each ring in its colour (one colour for all when one is given).
static func _add_lathe(mesh: ArrayMesh, prof: Array, cols: Array, smooth: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(SEGMENTS):
		var a0 := TAU * float(j) / float(SEGMENTS)
		var a1 := TAU * float(j + 1) / float(SEGMENTS)
		for k in range(prof.size() - 1):
			var p: Array = prof[k]
			var q: Array = prof[k + 1]
			var cp: Color = cols[mini(k, cols.size() - 1)]
			var cq: Color = cols[mini(k + 1, cols.size() - 1)]
			var v00 := Vector3(cos(a0) * float(p[0]), float(p[1]), sin(a0) * float(p[0]))
			var v01 := Vector3(cos(a1) * float(p[0]), float(p[1]), sin(a1) * float(p[0]))
			var v10 := Vector3(cos(a0) * float(q[0]), float(q[1]), sin(a0) * float(q[0]))
			var v11 := Vector3(cos(a1) * float(q[0]), float(q[1]), sin(a1) * float(q[0]))
			# clockwise seen from outside (Godot's front faces)
			for v: Array in [[v00, cp], [v10, cq], [v01, cp], [v01, cp], [v10, cq], [v11, cq]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	if smooth:
		st.index()
	st.generate_normals()
	st.commit(mesh)


## `n` double-edged razor blades stuck into the rim at `at` from the middle, `length` out and `width` across, each a
## little askew, a dark slot down its middle: one surface, flat-shaded.
static func _add_blades(mesh: ArrayMesh, n: int, at: float, length: float, width: float, steel: Color, slot: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var jitter := [0.06, -0.09, 0.03, 0.1, -0.05, 0.08, -0.1, 0.02, 0.07, -0.04]
	for k in range(n):
		var a := TAU * float(k) / float(n) + float(jitter[k % jitter.size()]) * 0.6
		var u := Vector3(cos(a), 0.0, sin(a))
		var up := Vector3.UP
		var b := Basis(u, float(jitter[(k + 3) % jitter.size()]) * 1.6) * Basis(up, float(jitter[(k + 5) % jitter.size()]) * 1.4)
		var uu := (b * u).normalized()
		var nn := (b * up).normalized()
		var tt := nn.cross(uu).normalized()
		var c := uu * at
		_box(st, c, uu, tt, nn, length * 0.5, width * 0.5, 0.012, steel)
		_box(st, c + nn * 0.013, uu, tt, nn, length * 0.3, width * 0.07, 0.003, slot)
	st.generate_normals()
	st.commit(mesh)


## A box round `c` along the right-handed axes u, t, n (u x t = n) with those half sizes, every face clockwise from outside.
static func _box(st: SurfaceTool, c: Vector3, u: Vector3, t: Vector3, n: Vector3, hu: float, ht: float, hn: float, col: Color) -> void:
	var faces := [[n * hn, u * hu, t * ht], [-n * hn, t * ht, u * hu], [u * hu, t * ht, n * hn], [-u * hu, n * hn, t * ht],
		[t * ht, n * hn, u * hu], [-t * ht, u * hu, n * hn]]
	for f: Array in faces:
		var fc: Vector3 = c + (f[0] as Vector3)
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		# p0..p3 counter-clockwise seen from outside (a x b points out); emitted clockwise
		var p0 := fc - a - b
		var p1 := fc + a - b
		var p2 := fc + a + b
		var p3 := fc - a + b
		for v: Vector3 in [p0, p2, p1, p0, p3, p2]:
			st.set_color(col)
			st.add_vertex(v)
