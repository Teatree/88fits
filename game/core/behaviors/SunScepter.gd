## The Sun Scepter (pass 54, Solenne's own weapon; Zenith is its evolution). A golden sceptre circles her, tipped back to
## the high camera so its sun faces it, rocking gently, and every `cooldown` seconds calls `amount` pillars of sunlight
## down on creatures she can see. Each pick is drawn from the creatures on the screen (EnemyManager.onscreen, the screen
## grown by a metre; every creature where there is no camera) with a weight of 1 / max(d, PICK_NEAR)^weight_power by its
## distance d from her (Garry: "closer = likelier"), never the same one twice in a strike; with nothing on the screen it
## holds (no strike, no cooldown; params.sun.hold_when_empty false strikes the sand round her instead). A pillar warns for
## `warn` seconds over the spot the creature will reach by then (its velocity led, LEAD_MAX at most): a faint ring on
## the sand under a beam that brightens (SunBeams), then it hits everything within `radius` x area of the spot: damage,
## a shove out from the centre, a burn when the weapon carries fire (Heat Stroke: EnemyManager.ignite takes only
## WeaponInstance.ignite_chance of them), poison likewise; a gold burst and a ring flash, no camera shake.
## params.sun {warn, radius, flash, beam_alpha, ring_alpha, ring_color, glint, hold_when_empty, weight_power, tint, thin}: Flicker
## thins and yellows the pillars. params.zenith {every, frac, radius, max_pillars} (Zenith's `final`): every `every`th
## strike hits every creature on the screen once at `frac` of the damage, a pillar on each of the nearest `max_pillars`;
## the sun head's "Charge" ring grows and lights as the count fills, and the sweep lands with a bigger flash. Gold Dust's
## coins (params.gold_dust) are paid where kills are paid (Game._kill_effects, gold_dust_coins), so its burns' kills count.
## The model (art/props/sun_scepter.glb, tools/blender_scepter.py) is the visual's "Familiar/Scepter": "Staff", "Sun",
## "Charge" and the "Glint" empty; the visual's "Familiar/SunGlow" is a sunburst quad behind the sun (shine_aura mode 0).
## Until the GLB is imported a model of primitives stands in (_fallback_model).
## Pass 55 (Garry: "The attacks should be animated with little more than a glint on the tip, let's do a little shake on
## the whole scepter itself"): every strike called shakes the whole sceptre (shake_at: a few degrees of pitch and roll
## jitter and a kick along the staff, gone in SHAKE_TIME; Zenith's sweep twice as hard) and flares the sunburst
## (flare_at: up in FLARE_UP, down over FLARE_DOWN). params.shine {idle, flare, sweep, pop, charge} sets the sunburst's
## strength at rest, at a strike's flare and at a sweep's, how much it swells, and what Zenith's count adds: the plain
## sceptre has none at rest (its SunGlow hidden, the quad at 45% of its old size: the shine at a smaller scale is the
## glint now), Zenith keeps its constant shine and flares harder. The crossed-bar glint comes only with sun.glint > 0
## (Zenith's). Its mutations show on the sceptre itself (the floating emblems went in pass 60): Heat Stroke's
## `staff_tint` warms the lacquered handle a little, Flicker's `handle_ring` is a ring round the handle that loads round
## and round, Gold Dust shows nothing (_refresh_looks, run from refresh_marks on every build change).
## Pass 61 (Garry: "Make the attack of the scepter visuals a bit stronger. For both the 'projectile' and the scepter
## itself"): the shake is harder (SHAKE_DEG 5 -> 8, SHAKE_KICK 0.05 -> 0.09, SHAKE_TIME 0.25 -> 0.3), the sunburst flares
## higher and swells (params.shine flare/sweep/pop raised in both JSONs, Zenith's still over the plain one's), the sun
## disc itself pulses (its own emissive materials and its scale: PULSE_EMIT, PULSE_SWELL; pulse_at) on every call and,
## at PULSE_LAND of that, as the strike lands, and the call throws a few CALL_SPARKS off the sun. The pillar lands with a
## fatter white core (SunBeams' impact), a white pop and rising motes (Fx.sun_impact), a shock ring racing out over the
## sand (Telegraphs.race_ring, IMPACT_RING x its radius) and a hot glow on the sand that fades (Telegraphs.scorch,
## IMPACT_GLOW); a Zenith sweep's forty landings take fewer motes each (IMPACT_MOTES_SWEEP). All pooled, no nodes, no lights.
class_name SunScepter
extends WeaponBehavior

## SunBeams by its path: a class added since the editor last scanned the project has no global name yet in a headless run
const BEAMS := preload("res://core/systems/SunBeams.gd")

const PICK_NEAR := 1.5
## The most a pillar leads a creature by (a creature thrown by another weapon moves fast for an instant).
const LEAD_MAX := 2.5
## The flare on a strike (pass 55): up in FLARE_UP seconds, down over FLARE_DOWN.
const FLARE_UP := 0.06
const FLARE_DOWN := 0.3
## The sunburst's strengths when the weapon's params.shine leaves one out: at rest (none), at a strike's flare, at
## Zenith's sweep, and what Zenith's full count adds at rest.
const SHINE_IDLE := 0.0
const SHINE_FLARE := 1.1
const SHINE_CHARGE := 0.45
## The shake on a strike (pass 55): this long at power 1 (a sweep's power 2 runs half as long again), this many degrees
## of pitch and roll at its start, jittering at SHAKE_HZ, and a kick of SHAKE_KICK metres up the staff.
const SHAKE_TIME := 0.3
const SHAKE_DEG := 8.0
const SHAKE_HZ := 19.0
const SHAKE_KICK := 0.09
## The sun disc's pulse (pass 61): its emissive materials gain PULSE_EMIT of energy at the pulse's peak, whitening by
## PULSE_WHITE, and it swells by PULSE_SWELL; up in PULSE_UP, down over PULSE_DOWN. A landing pulses it PULSE_LAND as hard.
const PULSE_EMIT := 2.2
const PULSE_WHITE := 0.45
const PULSE_SWELL := 0.22
const PULSE_UP := 0.05
const PULSE_DOWN := 0.32
const PULSE_LAND := 0.6
## Sparks thrown off the sun on a call (pass 61), twice as many on a sweep.
const CALL_SPARKS := 5
## The landing on the sand (pass 61): the shock ring races out to IMPACT_RING x the strike's radius over IMPACT_RING_TIME
## at IMPACT_RING_ALPHA; the hot glow is IMPACT_GLOW x the radius, held IMPACT_GLOW_HOLD and gone over IMPACT_GLOW_FADE;
## IMPACT_MOTES rising motes a strike, IMPACT_MOTES_SWEEP each of a sweep's pillars. A sweep's forty landings take no
## shock ring, a smaller pop (IMPACT_POP_SWEEP) and a fainter glow (IMPACT_GLOW_SWEEP x its alpha): together they would
## white the screen out.
const IMPACT_RING := 1.6
const IMPACT_RING_TIME := 0.38
const IMPACT_RING_ALPHA := 0.75
const IMPACT_RING_COLOR := Color(1.0, 0.86, 0.45)
const IMPACT_GLOW := 0.95
const IMPACT_GLOW_HOLD := 0.12
const IMPACT_GLOW_FADE := 0.6
const IMPACT_GLOW_INNER := Color(1.0, 0.9, 0.55, 0.8)
const IMPACT_GLOW_OUTER := Color(1.0, 0.62, 0.16, 0.0)
const IMPACT_MOTES := 6
const IMPACT_MOTES_SWEEP := 2
const IMPACT_POP_SWEEP := 0.5
## A sweep's pillars land at this share of a strike's pop and impact (SunBeams.begin's `land`).
const SWEEP_LAND := 0.4
const IMPACT_GLOW_SWEEP := 0.5
## A Zenith sweep's shake and flare against a strike's.
const SWEEP_POWER := 2.0
const TILT_DEG := 28.0
## How far the sceptre turns towards the creature it last struck (radians): the sun keeps facing the camera.
const LEAN := 0.45
## Zenith's sweep as the estimate counts it: this many creatures on the screen.
const SWEEP_CATCH := 10.0
## Where the strike lands in the sand round her when there is nothing to see and params.sun.hold_when_empty is false.
const EMPTY_REACH := Vector2(3.0, 7.0)
## Flicker's ring round the handle (pass 55): drawn as this many pieces when it is full, its light this far towards the
## camera so it lies over its own track and the near side of the staff (the staff still hides the far side).
const RING_SEGS := 40
const RING_NUDGE := 0.03
## The ring fills over this share of its period, then holds full and fades over the rest.
const RING_FILL := 0.82

var _familiar: Node3D
var _model: Node3D
var _sun: Node3D
var _charge: Node3D
var _charge_mat: StandardMaterial3D
var _charge_f := 0.0
var _charge_pop := 0.0
var _glint: Node3D
var _glow: MeshInstance3D
var _glow_mat: ShaderMaterial
var _glow_rest := Vector3.ONE
var _glow_boost := 0.0
## The flare's clock since the last strike was called (-1 = none) and its peak strength.
var _flare_t := -1.0
var _flare_peak := SHINE_FLARE
## The shake's clock since the last strike was called (-1 = at rest) and how hard.
var _shake_t := -1.0
var _shake_power := 1.0
## The sun disc's pulse (pass 61): its clock since the last pulse (-1 = at rest), how hard, its emissive materials as
## {mat, energy, color} (copies on the disc's surfaces) and its rest scale.
var _pulse_t := -1.0
var _pulse_peak := 1.0
var _disc: Array = []
var _sun_rest := Vector3.ONE
## Pulses so far and landings marked on the sand (tests).
var pulses := 0
var impacts := 0
## Where the sceptre flies, eased after her; the shake's kick is added on top of it.
var _fly_at := Vector3.INF
var _orbit := 0.0
var _clock := 0.0
var _yaw := 0.0
var _yaw_goal := 0.0
var _beams: BEAMS
var _strikes: Array = []   # {t, warn, at, r, dmg, target, serial, single, ring, pillar, sweep}
## Strikes fired, creatures hit, Zenith's count towards its sweep and its sweeps (tests, the pause screen).
var strikes := 0
var hits := 0
var count := 0
var sweeps := 0
## The mutations on the sceptre itself (pass 55): the staff's lacquered surface and its own material (to put back), the
## tinted copy while Heat Stroke is held, and Flicker's ring with its track and light.
var _looks_key := "-"
var _lacquer_surf := -2
var _lacquer_rest: Material
var _lacquer_base: Material
var _lacquer_tint: StandardMaterial3D
var _ring: Node3D
var _ring_arc: MeshInstance3D
var _ring_mesh: ImmediateMesh
var _ring_p: Dictionary = {}
var _ring_t := 0.0
## How much of the ring is lit now (0..1) and how many pieces its light was drawn in (tests).
var ring_fill := 0.0
var ring_pieces := 0


func _uses_projectiles() -> bool:
	return false


func _on_setup() -> void:
	_beams = BEAMS.new()
	_beams.name = "SunBeams"
	add_child(_beams)
	_familiar = visual.get_node_or_null("Familiar") as Node3D
	if _familiar == null:
		return
	_model = _familiar.get_node_or_null("Scepter") as Node3D
	if _model == null:
		_model = _fallback_model()
		_familiar.add_child(_model)
	_sun = _model.find_child("Sun", true, false) as Node3D
	_setup_disc()
	_charge = _model.find_child("Charge", true, false) as Node3D
	_setup_charge()
	# the crossed bars only where the weapon asks for them (pass 55: Zenith's; the plain sceptre's glint is its flare)
	if float(_sun_p().get("glint", 0.0)) > 0.0:
		_setup_glint()
	_glow = _familiar.get_node_or_null("SunGlow") as MeshInstance3D
	if _glow:
		_glow_rest = _glow.scale
		if _glow.material_override is ShaderMaterial:
			_glow_mat = (_glow.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			_glow.material_override = _glow_mat
	_orbit = randf() * TAU
	_clock = randf() * 10.0
	_place(0.0)
	_tick_glow(0.0)


func _exit_tree() -> void:
	# a pillar still warning when the weapon goes (it evolved) leaves no ring behind on the sand
	if game and game.get("telegraphs"):
		for s: Dictionary in _strikes:
			if int(s["ring"]) >= 0:
				game.telegraphs.release(int(s["ring"]))
	_strikes.clear()


func _sun_p() -> Dictionary:
	var s = inst.params.get("sun", {})
	return s if s is Dictionary else {}


func _zenith() -> Dictionary:
	var z = inst.params.get("zenith")
	return z if z is Dictionary else {}


## params.shine (pass 55): the sunburst's {idle, flare, sweep, pop, charge}.
func _shine() -> Dictionary:
	var s = inst.params.get("shine")
	return s if s is Dictionary else {}


func _fam(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float((f as Dictionary).get(key, default)) if f is Dictionary else default


func _tint() -> Color:
	return Color(str(_sun_p().get("tint", "#FFC64A")))


# ---------------------------------------------------------------- picking

## The weight of a creature `d` metres from her in a pick: the close ones likelier (1 / d^power, flat inside PICK_NEAR).
static func weight_at(d: float, power: float) -> float:
	return 1.0 / pow(maxf(d, PICK_NEAR), power)


## The creatures she can see, as [index, flat distance from her], nearest first: alive, not dying, not buried and not
## held, and on the screen (EnemyManager.onscreen when it is kept; every one without it).
func visible_targets() -> Array:
	var em: EnemyManager = game.enemies
	var out: Array = []
	if em == null or player == null:
		return out
	var hero := player.global_position
	var scr = em.get("onscreen")
	var screen: PackedByteArray = scr if (scr is PackedByteArray and (scr as PackedByteArray).size() == em.pool_max) else PackedByteArray()
	var use_screen := screen.size() == em.pool_max
	for i in range(em.pool_max):
		if em.alive[i] == 0 or em.state[i] == EnemyManager.STATE_DYING or em.hidden[i] == 1 or em.held[i] == 1:
			continue
		if use_screen and screen[i] == 0:
			continue
		out.append([i, Vector2(em.pos[i].x - hero.x, em.pos[i].z - hero.z).length()])
	out.sort_custom(func(a, b) -> bool: return float(a[1]) < float(b[1]))
	return out


## Up to `n` creatures she can see for one strike, drawn one at a time in proportion to weight_at, none twice.
func pick_targets(n: int) -> Array:
	var cands := visible_targets()
	var power := float(_sun_p().get("weight_power", 2.0))
	var weights: Array = []
	for c in cands:
		weights.append(weight_at(float(c[1]), power))
	var out: Array = []
	# pass 73 (lane SNIPER): the first pillar goes to a special, an Elite or the boss she can see within reach
	# (priority_pick, the map's 10 m); the rest are drawn as before, none twice
	var pt: int = priority_pick(player.global_position, stat("range", 10.0)) if n > 0 and player != null else -1
	for j in range(cands.size()):
		if pt >= 0 and int(cands[j][0]) == pt:
			out.append(pt)
			weights[j] = 0.0
			break
	for k in range(mini(n, cands.size()) - out.size()):
		var total := 0.0
		for w in weights:
			total += float(w)
		if total <= 0.0:
			break
		var roll := randf() * total
		var pick := -1
		for j in range(weights.size()):
			if float(weights[j]) <= 0.0:
				continue
			pick = j
			roll -= float(weights[j])
			if roll <= 0.0:
				break
		if pick < 0:
			break
		out.append(int(cands[pick][0]))
		weights[pick] = 0.0
	return out


## Where creature `e` will stand when a strike `warn` seconds away lands: its feet led along its ground velocity (at most
## LEAD_MAX), on the sand.
func _lead(e: int, warn: float) -> Vector3:
	var em: EnemyManager = game.enemies
	var v := Vector3(em.vel[e].x, 0.0, em.vel[e].z) * warn
	if v.length() > LEAD_MAX:
		v = v.normalized() * LEAD_MAX
	return _ground(em.pos[e] + v)


func _ground(p: Vector3) -> Vector3:
	var map = game.get("map")
	if map != null and map.has_method("height_at"):
		return Vector3(p.x, map.height_at(p.x, p.z), p.z)
	return p


# ---------------------------------------------------------------- striking

func _fire() -> bool:
	var zp := _zenith()
	var sweep: bool = not zp.is_empty() and count + 1 >= maxi(int(zp.get("every", 10)), 1)
	var targets: Array = []
	if sweep:
		for c in visible_targets():
			targets.append(int(c[0]))
	else:
		targets = pick_targets(maxi(stat_int("amount", 1), 1))
	var spots: Array = []
	if targets.is_empty():
		if bool(_sun_p().get("hold_when_empty", true)) or sweep:
			# nothing on the screen: it holds, and asks again in a moment (WeaponBehavior)
			return false
		for k in range(maxi(stat_int("amount", 1), 1)):
			var a := randf() * TAU
			var d := randf_range(EMPTY_REACH.x, EMPTY_REACH.y)
			spots.append(_ground(player.global_position + Vector3(cos(a) * d, 0.0, sin(a) * d)))
	strikes += 1
	if not zp.is_empty():
		count = 0 if sweep else count + 1
	var sun := _sun_p()
	var warn: float = maxf(float(sun.get("warn", 0.45)), 0.05)
	var area := stat("area", 1.0)
	var r: float = (float(zp.get("radius", 1.0)) if sweep else float(sun.get("radius", 1.3))) * area
	var tint := _tint()
	var alpha := float(sun.get("beam_alpha", 0.35))
	var ring_a := float(sun.get("ring_alpha", 0.35))
	# the warning ring is the loose rocket's red ring, fainter (Garry: "that red ring, but it's fainter and less intrusive");
	# Zenith's every-tenth sweep keeps the sun's own colour, so forty rings at once do not paint the screen red
	var ring_c := tint if sweep else Color(str(sun.get("ring_color", "#FF381A")))
	var flash := float(sun.get("flash", 1.0)) * (1.25 if sweep else 1.0)
	var thin := float(sun.get("thin", 1.0))
	var dmg := stat("damage", 14.0) * (float(zp.get("frac", 0.8)) if sweep else 1.0)
	var pillars: int = int(zp.get("max_pillars", 40)) if sweep else 1 << 20
	var em: EnemyManager = game.enemies
	var tg = game.get("telegraphs")
	var first := Vector3.INF
	var n: int = maxi(targets.size(), spots.size())
	for k in range(n):
		var e: int = int(targets[k]) if k < targets.size() else -1
		var at: Vector3 = _lead(e, warn) if e >= 0 else spots[k]
		var s := {"t": 0.0, "warn": warn, "at": at, "r": r, "dmg": dmg, "target": e, "serial": em.serial[e] if e >= 0 else -1,
			"single": sweep, "ring": -1, "pillar": k < pillars, "sweep": sweep}
		if k < pillars:
			if tg != null:
				s["ring"] = tg.hold_ring(at, r, Color(ring_c.r, ring_c.g, ring_c.b, ring_a))
			_beams.begin(at, r, warn, tint, alpha, flash, thin, SWEEP_LAND if sweep else 1.0)
		if first == Vector3.INF:
			first = at
		_strikes.append(s)
	_called(sweep)
	_face(first)
	sfx("fire")
	return true


## A strike is called (pass 55): the whole sceptre shakes and its sun flares; a Zenith sweep shakes twice as hard and
## flares at the sweep's strength.
func _called(sweep: bool) -> void:
	_shake_t = 0.0
	_shake_power = SWEEP_POWER if sweep else 1.0
	_flare_t = 0.0
	var sh := _shine()
	var flare := float(sh.get("flare", SHINE_FLARE))
	_flare_peak = float(sh.get("sweep", flare)) if sweep else flare
	_pulse(1.0)
	var fx = game.get("fx") if game else null
	if fx and _familiar and fx.has_method("sun_sparks"):
		fx.sun_sparks(_sun_at(), _tint(), CALL_SPARKS * (2 if sweep else 1))


func _tick(delta: float) -> void:
	_place(delta)
	_tick_strikes(delta)
	if _beams:
		_beams.tick(delta)
	_tick_glow(delta)
	_tick_pulse(delta)
	_tick_ring(delta)


func _tick_strikes(delta: float) -> void:
	if _strikes.is_empty():
		return
	var keep: Array = []
	var landed := false
	var swept := false
	for s: Dictionary in _strikes:
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) >= float(s["warn"]):
			_land(s)
			landed = true
			swept = swept or bool(s["sweep"])
		else:
			keep.append(s)
	_strikes = keep
	if swept:
		# Zenith's tenth: one big flash on the sun head, the count ring popping as it empties
		sweeps += 1
		_charge_pop = 1.0
		_glow_boost = 1.0
		sfx("burst")
		if _familiar and game.get("fx"):
			game.fx.burst(_sun_at(), _tint(), 1.6)
	elif landed:
		sfx("hit")
	if landed:
		_pulse(PULSE_LAND)


## A pillar comes down: what stands in it is hit (a sweep's pillar hits only the creature it was called on, once), and a
## gold burst and a ring flash mark the spot.
func _land(s: Dictionary) -> void:
	var em: EnemyManager = game.enemies
	var tg = game.get("telegraphs")
	if int(s["ring"]) >= 0 and tg != null:
		tg.release(int(s["ring"]))
	var at: Vector3 = s["at"]
	var r: float = float(s["r"])
	var victims: Array = []
	if bool(s["single"]):
		var e: int = int(s["target"])
		if em.is_alive(e) and em.serial[e] == int(s["serial"]) and em.hidden[e] == 0 and em.held[e] == 0:
			victims.append(e)
	else:
		for e in em.indices_in_radius(at, r):
			victims.append(e)
	var wid := inst.def.id
	var knock := stat("knockback", 0.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	for e: int in victims:
		if em.state[e] == EnemyManager.STATE_DYING:
			continue
		var away := Vector3(em.pos[e].x - at.x, 0.0, em.pos[e].z - at.z)
		away = away.normalized() if away.length_squared() > 0.0001 else Vector3.ZERO
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.5))
		hits += 1
		if em.damage(e, float(s["dmg"]), wid, away, knock):
			inst.kills += 1
	if bool(s["pillar"]):
		var tint := _tint()
		var sweep := bool(s.get("sweep", false))
		var fx = game.get("fx")
		if fx:
			fx.burst(at + Vector3(0.0, 0.4, 0.0), tint, 0.8 * r)
			# pass 61: a white pop and motes rising off the spot
			if fx.has_method("sun_impact"):
				fx.sun_impact(at, r, tint, IMPACT_MOTES_SWEEP if sweep else IMPACT_MOTES, not sweep, IMPACT_POP_SWEEP if sweep else 1.0)
		if tg != null:
			tg.flash_ring(at, r, tint, 0.25)
			# pass 61: a shock ring racing out over the sand and the sand glowing hot under the pillar
			if tg.has_method("race_ring") and not sweep:
				var rc := IMPACT_RING_COLOR
				tg.race_ring(at, r * IMPACT_RING, IMPACT_RING_TIME, Color(rc.r, rc.g, rc.b, IMPACT_RING_ALPHA), 0.3)
			if tg.has_method("scorch"):
				var gi := IMPACT_GLOW_INNER
				if sweep:
					gi = Color(gi.r, gi.g, gi.b, gi.a * IMPACT_GLOW_SWEEP)
				tg.scorch(at, r * IMPACT_GLOW, gi, IMPACT_GLOW_OUTER, IMPACT_GLOW_HOLD, IMPACT_GLOW_FADE)
		impacts += 1


## How many coins a kill by `inst` drops (pass 54, Gold Dust: `params.gold_dust {chance, coins}`): its `coins` a `chance`
## of the time, else none. Game._kill_effects pays them.
static func gold_dust_coins(w: WeaponInstance) -> int:
	if w == null:
		return 0
	var gd = w.params.get("gold_dust")
	if not gd is Dictionary:
		return 0
	if randf() >= float((gd as Dictionary).get("chance", 0.3)):
		return 0
	return maxi(int((gd as Dictionary).get("coins", 1)), 0)


# ---------------------------------------------------------------- the companion

func _place(delta: float) -> void:
	if _familiar == null or player == null:
		return
	var r := _fam("radius", 1.25)
	var h := _fam("height", 1.55)
	var bob := _fam("bob", 0.1)
	_orbit += delta * _fam("speed", 1.1)
	# its own clock (pass 55): the bob and the rock pick up where they were after a pause, and a test's frames are its own
	_clock += delta
	var t := _clock
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.4) * bob, sin(_orbit) * r)
	_fly_at = want if (delta <= 0.0 or _fly_at == Vector3.INF) else _fly_at.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	_yaw = lerp_angle(_yaw, _yaw_goal, clampf(delta * 5.0, 0.0, 1.0))
	var sh := Vector3.ZERO
	if _shake_t >= 0.0:
		_shake_t += delta
		sh = shake_at(_shake_t, _shake_power)
		if _shake_t >= shake_time(_shake_power):
			_shake_t = -1.0
	# the sun faces +Z (the camera's side) when not turned: tipped back by tilt_deg its face looks up at the high camera;
	# a strike's shake jitters the pitch and the roll and kicks it up its own staff
	_familiar.rotation = Vector3(-deg_to_rad(_fam("tilt_deg", TILT_DEG)) + sh.x, _yaw, sin(t * 0.7) * 0.25 + sh.y)
	var up := _familiar.global_transform.basis.y.normalized()
	_familiar.global_position = _fly_at + up * sh.z


## How long a strike's shake lasts at `power` (1 a strike, SWEEP_POWER a Zenith sweep).
static func shake_time(power: float) -> float:
	return SHAKE_TIME * (1.0 + 0.5 * maxf(power - 1.0, 0.0))


## The shake `t` seconds after a strike was called (pass 55, Garry: "a little shake on the whole scepter itself"):
## Vector3(pitch, roll, kick), radians and metres up the staff. A fast jitter of SHAKE_DEG x power, quieting as
## (1 - u)^2 over shake_time, and a kick up the staff that peaks early and settles; zero before and after.
static func shake_at(t: float, power: float = 1.0) -> Vector3:
	var dur := shake_time(power)
	if t < 0.0 or t >= dur:
		return Vector3.ZERO
	var u := t / dur
	var env := (1.0 - u) * (1.0 - u)
	var a := deg_to_rad(SHAKE_DEG) * power * env
	var pitch := a * sin(t * TAU * SHAKE_HZ)
	var roll := a * 1.2 * sin(t * TAU * SHAKE_HZ * 0.77 + 1.3)
	var k := u / 0.15 if u < 0.15 else pow(1.0 - (u - 0.15) / 0.85, 2.0)
	return Vector3(pitch, roll, SHAKE_KICK * power * k)


## The flare `t` seconds after a strike was called (pass 55): 0 to 1 over FLARE_UP, back to 0 over FLARE_DOWN, eased.
static func flare_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < FLARE_UP:
		return t / FLARE_UP
	var d := (t - FLARE_UP) / FLARE_DOWN
	return 0.0 if d >= 1.0 else (1.0 - d) * (1.0 - d)


## The sunburst's strength for `shine` (params.shine) with a flare at `f` (0..1) towards `peak`, a sweep's landing flash
## at `boost` (0..1) and Zenith's count at `charge` (0..1). The title's flourish uses it too.
static func glow_strength(shine: Dictionary, f: float, peak: float, boost: float = 0.0, charge: float = 0.0) -> float:
	var idle := float(shine.get("idle", SHINE_IDLE)) + float(shine.get("charge", SHINE_CHARGE)) * charge
	var flare := float(shine.get("flare", SHINE_FLARE))
	var sweep := float(shine.get("sweep", flare))
	return idle + maxf(maxf(peak - idle, 0.0) * f, maxf(sweep - idle, 0.0) * boost)


## The sceptre turns a little towards a strike, by the share of the way across the screen it lies.
func _face(at: Vector3) -> void:
	if _familiar == null or at == Vector3.INF:
		return
	var d := Vector3(at.x - _familiar.global_position.x, 0.0, at.z - _familiar.global_position.z)
	if d.length_squared() > 0.0001:
		_yaw_goal = clampf(d.x / d.length(), -1.0, 1.0) * LEAN


func _sun_at() -> Vector3:
	if _sun:
		return _sun.global_position
	return _familiar.global_position if _familiar else player.global_position + Vector3(0, 1.8, 0)


## The sunburst behind the sun flares on a strike (pass 55: the plain sceptre's is hidden at rest, Zenith's shines all
## the time and flares harder) and swells by shine.pop; Zenith's bars flare with it, and its count ring grows and lights
## towards the tenth strike.
func _tick_glow(delta: float) -> void:
	var f := 0.0
	if _flare_t >= 0.0:
		_flare_t += delta
		f = flare_at(_flare_t)
		if _flare_t >= FLARE_UP + FLARE_DOWN:
			_flare_t = -1.0
	_glow_boost = maxf(_glow_boost - delta * 2.2, 0.0)
	var lit := maxf(f, _glow_boost)
	if _glint:
		var g := float(_sun_p().get("glint", 1.0))
		_glint.scale = Vector3.ONE * maxf(0.15 + 1.1 * lit * g, 0.001)
		_glint.rotation.z += delta * (4.0 if lit > 0.0 else 0.6)
	var zp := _zenith()
	if not zp.is_empty():
		var every: int = maxi(int(zp.get("every", 10)), 2)
		var want := clampf(float(count) / float(every - 1), 0.0, 1.0)
		_charge_f = lerpf(_charge_f, want, clampf(delta * 6.0, 0.0, 1.0))
		_charge_pop = maxf(_charge_pop - delta * 2.5, 0.0)
		if _charge:
			_charge.scale = Vector3.ONE * (0.55 + 0.45 * _charge_f + 0.5 * _charge_pop)
		if _charge_mat:
			_charge_mat.emission_energy_multiplier = 0.15 + 2.4 * _charge_f + 3.0 * _charge_pop
	if _glow:
		var sh := _shine()
		var strength := glow_strength(sh, f, _flare_peak, _glow_boost, _charge_f if not zp.is_empty() else 0.0)
		# nothing to draw at rest on the plain sceptre: the quad is hidden, not drawn at zero
		_glow.visible = strength > 0.004
		# it swells by shine.pop at a strike's flare, more at a sweep's (by its peak over a strike's), twice at the landing
		var swell := f * _flare_peak / maxf(float(sh.get("flare", SHINE_FLARE)), 0.01)
		swell = maxf(swell, 2.0 * _glow_boost)
		_glow.scale = _glow_rest * (1.0 + float(sh.get("pop", 0.0)) * swell)
		if _glow_mat:
			_glow_mat.set_shader_parameter("strength", strength)


## The sunburst's strength now (tests): 0 while it is hidden.
func glow_now() -> float:
	if _glow == null or not _glow.visible or _glow_mat == null:
		return 0.0
	return float(_glow_mat.get_shader_parameter("strength"))


# ---------------------------------------------------------------- the sun disc's pulse (pass 61)

## The disc's emissive surfaces, each on its own copy of its material (the companion glow already made every one under
## the Familiar emit, so the pulse only moves numbers and compiles nothing new); a surface that does not emit is left
## alone.
func _setup_disc() -> void:
	_disc.clear()
	if _sun == null:
		return
	_sun_rest = _sun.scale
	var meshes: Array = _sun.find_children("*", "MeshInstance3D", true, false)
	if _sun is MeshInstance3D:
		meshes.push_front(_sun)
	var done := {}
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		if mi.material_override is BaseMaterial3D:
			var mo := _disc_copy(mi.material_override as BaseMaterial3D, done)
			if mo:
				mi.material_override = mo
			continue
		for k in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(k)
			if src is BaseMaterial3D:
				var m := _disc_copy(src as BaseMaterial3D, done)
				if m:
					mi.set_surface_override_material(k, m)


func _disc_copy(src: BaseMaterial3D, done: Dictionary) -> BaseMaterial3D:
	if not src.emission_enabled:
		return null
	if done.has(src.get_instance_id()):
		return done[src.get_instance_id()]
	var m := src.duplicate() as BaseMaterial3D
	done[src.get_instance_id()] = m
	_disc.append({"mat": m, "energy": m.emission_energy_multiplier, "color": m.emission})
	return m


## The disc's pulse `t` seconds after it was set off: 0 to 1 over PULSE_UP, back to 0 over PULSE_DOWN, eased.
static func pulse_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < PULSE_UP:
		return t / PULSE_UP
	var d := (t - PULSE_UP) / PULSE_DOWN
	return 0.0 if d >= 1.0 else (1.0 - d) * (1.0 - d)


## Sets the disc pulsing at `peak` (1 a call, PULSE_LAND a landing); a stronger pulse already running is kept.
func _pulse(peak: float) -> void:
	var now := pulse_at(_pulse_t) * _pulse_peak if _pulse_t >= 0.0 else 0.0
	if now > peak:
		return
	_pulse_t = 0.0
	_pulse_peak = peak
	pulses += 1


func _tick_pulse(delta: float) -> void:
	if _pulse_t < 0.0:
		return
	_pulse_t += delta
	var p := pulse_at(_pulse_t) * _pulse_peak
	if _pulse_t >= PULSE_UP + PULSE_DOWN:
		_pulse_t = -1.0
		p = 0.0
	_show_pulse(p)


func _show_pulse(p: float) -> void:
	for d: Dictionary in _disc:
		var m: BaseMaterial3D = d["mat"]
		m.emission_energy_multiplier = float(d["energy"]) + PULSE_EMIT * p
		m.emission = (d["color"] as Color).lerp(Color(1.0, 0.97, 0.82), PULSE_WHITE * p)
	if _sun:
		_sun.scale = _sun_rest * (1.0 + PULSE_SWELL * p)


## The disc's pulse now, 0..1 (tests).
func pulse_now() -> float:
	return pulse_at(_pulse_t) * _pulse_peak if _pulse_t >= 0.0 else 0.0


## How bright the disc's first emissive material is now (tests): its energy.
func disc_energy() -> float:
	return float((_disc[0]["mat"] as BaseMaterial3D).emission_energy_multiplier) if not _disc.is_empty() else 0.0


# ---------------------------------------------------------------- its path, on the sceptre itself (pass 55)

## The sceptre's own signs of its path (the floating emblems went in pass 60), on every build
## change (Game._sync_weapons calls this; setup too).
func refresh_marks() -> void:
	super.refresh_marks()
	_refresh_looks()


## Heat Stroke warms the handle and Flicker hangs its ring round it while they are held (their params.staff_tint and
## params.handle_ring, merged into the weapon's params); Gold Dust shows nothing.
func _refresh_looks() -> void:
	if inst == null or _model == null:
		return
	var tint = inst.params.get("staff_tint")
	var ring = inst.params.get("handle_ring")
	var key := JSON.stringify([tint, ring])
	if key == _looks_key:
		return
	_looks_key = key
	_tint_staff(tint if tint is Dictionary else {})
	if ring is Dictionary:
		_build_ring(ring)
	else:
		_free_ring()


func _staff() -> MeshInstance3D:
	return _model.find_child("Staff", true, false) as MeshInstance3D if _model else null


## The staff's lacquered surface, found once with its material as it was: the surface whose material is named for the
## lacquer, else the darkest; -1 when the whole staff wears one material (the stand-in model).
func _find_lacquer(staff: MeshInstance3D) -> void:
	if _lacquer_surf != -2:
		return
	_lacquer_surf = -1
	_lacquer_rest = staff.material_override
	_lacquer_base = staff.material_override
	if _lacquer_rest != null or staff.mesh == null:
		return
	var best := INF
	for k in range(staff.mesh.get_surface_count()):
		var m := staff.get_active_material(k)
		if m == null:
			continue
		var lum := 1.0
		if m is BaseMaterial3D:
			var c := (m as BaseMaterial3D).albedo_color
			lum = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
		if m.resource_name.contains("lacquer"):
			lum = -1.0
		if lum < best:
			best = lum
			_lacquer_surf = k
			_lacquer_rest = staff.get_surface_override_material(k)
			_lacquer_base = m


## Heat Stroke's warmer handle (Garry: "made the handle of the scepter a bit more orange (but not by a lot)"):
## params.staff_tint {color, amount, glow}: the lacquer's colour lerped `amount` towards `color`, and a faint emission of
## that colour at `glow`, not a glow; never the brass bands or the sun. An empty `p` puts the lacquer back.
func _tint_staff(p: Dictionary) -> void:
	var staff := _staff()
	if staff == null:
		return
	_find_lacquer(staff)
	if p.is_empty():
		if _lacquer_tint != null:
			_lacquer_tint = null
			_set_lacquer(staff, _lacquer_rest)
		return
	var col := Color(str(p.get("color", "#D96B1F")))
	var amt := clampf(float(p.get("amount", 0.25)), 0.0, 1.0)
	var m: StandardMaterial3D = (_lacquer_base.duplicate() as StandardMaterial3D) if _lacquer_base is StandardMaterial3D else StandardMaterial3D.new()
	m.albedo_color = m.albedo_color.lerp(Color(col.r, col.g, col.b, m.albedo_color.a), amt)
	var glow := float(p.get("glow", 0.0))
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(col.r, col.g, col.b)
		m.emission_energy_multiplier = glow
	_lacquer_tint = m
	_set_lacquer(staff, m)


func _set_lacquer(staff: MeshInstance3D, m: Material) -> void:
	if _lacquer_surf < 0:
		staff.material_override = m
	else:
		staff.set_surface_override_material(_lacquer_surf, m)


## Whether the handle wears Heat Stroke's warmth now, and the lacquer's colour as drawn (tests).
func staff_tinted() -> bool:
	return _lacquer_tint != null


func lacquer_color() -> Color:
	var staff := _staff()
	if staff == null:
		return Color.BLACK
	_find_lacquer(staff)
	var m: Material = staff.material_override if _lacquer_surf < 0 else staff.get_active_material(_lacquer_surf)
	return (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.BLACK


## Flicker's ring (Garry: "place a floating ring around the handle instead of being on top near the tip. Make it so that
## the handle itself is inside this ring ... and it kind of slowly loads around the handle"): params.handle_ring {at,
## radius, width, track, track_color, color, head_color, period, spin, tilt_deg}: a ring `at` of the way up the staff
## from its foot with the staff through its middle, its plane square to the staff (tipped `tilt_deg` towards the camera's
## side), `radius` in the model's metres; a dark bronze track all the way round (`track_color` at alpha `track`) and a
## gold light `width` metres wide (`color` at its tail, `head_color` at its head) that grows round it over RING_FILL of
## `period` seconds, flashes as it closes, fades and starts again, its start turning at `spin` radians a second. It hangs
## in the model, so it flies, tilts and shakes with the sceptre; its pieces face the camera (drawn in the world each
## frame on Fx's see-through ribbon), so it keeps its width on the phone however it turns.
func _build_ring(p: Dictionary) -> void:
	_free_ring()
	var staff := _staff()
	var foot := -0.42
	var top := 0.17
	if staff and staff.mesh:
		var box: AABB = staff.transform * staff.mesh.get_aabb()
		foot = box.position.y
		top = box.end.y
	_ring = Node3D.new()
	_ring.name = "HandleRing"
	_ring.position = Vector3(0.0, lerpf(foot, top, float(p.get("at", 0.4))), 0.0)
	_ring.rotation.x = deg_to_rad(float(p.get("tilt_deg", 0.0)))
	_model.add_child(_ring)
	_ring_arc = MeshInstance3D.new()
	_ring_arc.name = "Light"
	_ring_mesh = ImmediateMesh.new()
	_ring_arc.mesh = _ring_mesh
	_ring_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_arc.top_level = true
	_ring.add_child(_ring_arc)
	_ring_arc.global_transform = Transform3D.IDENTITY
	_ring_p = p
	_ring_t = 0.0
	_tick_ring(0.0)


func _free_ring() -> void:
	if _ring:
		if _ring.get_parent():
			_ring.get_parent().remove_child(_ring)
		_ring.free()
	_ring = null
	_ring_arc = null
	_ring_mesh = null
	_ring_p = {}
	ring_fill = 0.0
	ring_pieces = 0


## Whether Flicker's ring hangs on the handle now (tests).
func has_ring() -> bool:
	return _ring != null


## How much of Flicker's ring is lit `u` of the way through its period: it grows round over RING_FILL, eased, then
## holds full.
static func ring_fill_at(u: float) -> float:
	u = fposmod(u, 1.0)
	return smoothstep(0.0, RING_FILL, u) if u < RING_FILL else 1.0


## The ring's light `u` of the way through its period: steady while it grows, a flash as it closes, then fading out.
static func ring_light_at(u: float) -> float:
	u = fposmod(u, 1.0)
	if u < RING_FILL:
		return 1.0
	var d := (u - RING_FILL) / (1.0 - RING_FILL)
	return (1.0 + 0.6 * (1.0 - d)) * (1.0 - d)


func _tick_ring(delta: float) -> void:
	if _ring == null or _ring_mesh == null:
		return
	_ring_t += delta
	var p := _ring_p
	var period := maxf(float(p.get("period", 2.5)), 0.2)
	var u := fposmod(_ring_t, period) / period
	ring_fill = ring_fill_at(u)
	var light := ring_light_at(u)
	_ring_mesh.clear_surfaces()
	ring_pieces = 0
	if not _ring.is_inside_tree():
		return
	var xf := _ring.global_transform
	var rad := float(p.get("radius", 0.095))
	var eye := _eye()
	var half := float(p.get("width", 0.045)) * 0.5
	var start := fposmod(_ring_t * float(p.get("spin", 0.6)), TAU)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	# the track: the whole ring in dark bronze, thinner than the light, so the gold reads against it on the sand
	var track := float(p.get("track", 0.85))
	if track > 0.0:
		var tc := Color(str(p.get("track_color", "#5E3F14")))
		tc.a = track
		_ring_strip(verts, cols, xf, rad, start, 1.0, RING_SEGS, half * 0.5, eye, tc, tc)
	var n := int(ceil(ring_fill * float(RING_SEGS)))
	if n >= 1 and light > 0.0:
		# the light deep gold at its tail, bright yellow at its head, whiter in the flash as it closes; fading after
		var flash := clampf(light - 1.0, 0.0, 1.0)
		var tail := Color(str(p.get("color", "#F39A1E"))).lerp(Color.WHITE, 0.6 * flash)
		var head := Color(str(p.get("head_color", "#FFE04A"))).lerp(Color.WHITE, flash)
		tail.a = clampf(light, 0.0, 1.0)
		head.a = clampf(light, 0.0, 1.0)
		_ring_strip(verts, cols, xf, rad, start, ring_fill, n, half, eye, tail, head)
		ring_pieces = n
	if verts.size() < 4:
		return
	# one strip, one draw: the light is drawn after the track, so it lies over it (two see-through surfaces of one mesh
	# are not drawn in a set order)
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, Fx.tint_ribbon_material())
	for k in range(verts.size()):
		_ring_mesh.surface_set_color(cols[k])
		_ring_mesh.surface_add_vertex(verts[k])
	_ring_mesh.surface_end()


## One camera-facing strip round the ring, added to `verts`/`cols` (joined to the strip before it by two repeated
## vertices, whose triangles have no area): from angle `start` over `frac` of the circle in `n` pieces, `half` metres
## each side of the line, its colour running from `c0` at the tail to `c1` at the head. Drawn on Fx's see-through ribbon,
## which keeps its colour on the bright sand where an additive one washes out.
func _ring_strip(verts: PackedVector3Array, cols: PackedColorArray, xf: Transform3D, rad: float, start: float, frac: float,
		n: int, half: float, eye: Vector3, c0: Color, c1: Color) -> void:
	var joined := verts.size() > 0
	for k in range(n + 1):
		var s := float(k) / float(n)
		var a := start + TAU * frac * s
		var wp := xf * Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var tangent := (xf.basis * Vector3(-sin(a), 0.0, cos(a))).normalized()
		var view := eye - wp
		view = view.normalized() if view.length_squared() > 0.0001 else Vector3.UP
		var side := tangent.cross(view)
		side = side.normalized() * half if side.length_squared() > 0.000001 else Vector3.ZERO
		var c := c0.lerp(c1, s * s)
		var at := wp + view * RING_NUDGE
		if joined:
			verts.append(verts[verts.size() - 1])
			cols.append(cols[cols.size() - 1])
			verts.append(at - side)
			cols.append(c)
			joined = false
		verts.append(at - side)
		cols.append(c)
		verts.append(at + side)
		cols.append(c)


## Where the camera is (the ring's pieces face it); without one (a test) the run's camera spot, above and behind her.
func _eye() -> Vector3:
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam:
		return cam.global_position
	var at := _familiar.global_position if _familiar else Vector3.ZERO
	return at + Vector3(0.0, 16.2, 15.6)


func _setup_charge() -> void:
	if _charge == null:
		return
	if _zenith().is_empty():
		_charge.visible = false
		return
	_charge.visible = true
	var mi := _charge as MeshInstance3D
	if mi == null:
		return
	var base: Material = mi.material_override
	if base == null and mi.mesh and mi.mesh.get_surface_count() > 0:
		base = mi.get_surface_override_material(0) if mi.get_surface_override_material(0) else mi.mesh.surface_get_material(0)
	_charge_mat = (base.duplicate() as StandardMaterial3D) if base is StandardMaterial3D else StandardMaterial3D.new()
	_charge_mat.emission_enabled = true
	_charge_mat.emission = Color(1.0, 0.78, 0.3)
	_charge_mat.emission_energy_multiplier = 0.15
	# on its one surface rather than as an override (pass 55): freeing a mesh that carried both a surface material (the
	# companion glow's) and an override logged "Parameter material is null" from the renderer
	if mi.material_override == null and mi.mesh and mi.mesh.get_surface_count() == 1:
		mi.set_surface_override_material(0, _charge_mat)
	else:
		mi.material_override = _charge_mat
	_charge.scale = Vector3.ONE * 0.55


## The glint: two crossed additive bars (the chest's) on the model's "Glint" empty at the sun's upper-right rim.
func _setup_glint() -> void:
	var anchor := _model.find_child("Glint", true, false) as Node3D
	if anchor == null:
		anchor = Node3D.new()
		anchor.name = "Glint"
		anchor.position = Vector3(0.07, 0.37, 0.04)
		_model.add_child(anchor)
	_glint = Node3D.new()
	_glint.name = "Flare"
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 1.0, 0.92)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for k in range(2):
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.5, 0.06) if k == 0 else Vector3(0.5, 0.06, 0.06)
		bar.mesh = bm
		bar.material_override = gm
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glint.add_child(bar)
	_glint.scale = Vector3.ONE * 0.15
	anchor.add_child(_glint)


## The sceptre in primitives, the GLB's parts by name, for as long as art/props/sun_scepter.glb is not imported.
func _fallback_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Scepter"
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color(0.2, 0.09, 0.08)
	lacquer.roughness = 0.3
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.68, 0.12)
	gold.metallic = 0.35
	gold.roughness = 0.35
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.58, 0.08)
	gold.emission_energy_multiplier = 0.6
	var staff := MeshInstance3D.new()
	staff.name = "Staff"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = 0.6
	staff.mesh = cm
	staff.material_override = lacquer
	staff.position = Vector3(0.0, -0.12, 0.0)
	root.add_child(staff)
	var sun := Node3D.new()
	sun.name = "Sun"
	sun.position = Vector3(0.0, 0.3, 0.0)
	root.add_child(sun)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.115
	dm.bottom_radius = 0.115
	dm.height = 0.035
	disc.mesh = dm
	disc.rotation.x = PI * 0.5
	disc.material_override = gold
	sun.add_child(disc)
	for k in range(8):
		var a := TAU * float(k) / 8.0
		var ray := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.045, 0.12, 0.014)
		ray.mesh = rm
		ray.material_override = gold
		ray.position = Vector3(sin(a) * 0.165, cos(a) * 0.165, 0.0)
		ray.rotation.z = -a
		sun.add_child(ray)
	var charge := MeshInstance3D.new()
	charge.name = "Charge"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.142
	tm.outer_radius = 0.162
	charge.mesh = tm
	charge.rotation.x = PI * 0.5
	charge.position = sun.position
	charge.material_override = gold.duplicate()
	root.add_child(charge)
	var glint := Node3D.new()
	glint.name = "Glint"
	glint.position = Vector3(0.07, 0.37, 0.04)
	root.add_child(glint)
	return root
