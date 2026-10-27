## Dragon's Breath (pass 95, lane BREATH; Garry: "Cologne and Lighter ... Player hero 'breathes fire' for a certain amount
## of time in a direction that they are facing. Every enemy affected by the fire catch fire and are dealt damage every
## second that they are standing in that fire. The attack doesn't happen very often, but when it does it lasts for 2
## seconds. This is the slowest weapon in the game, but it deals decent damage"): a cone of fire from the hero's face
## (Player.face_origin: no 3D object, the fire starts about where his face is) along where he faces. Every `cooldown`
## (the slowest in the game) it breathes for `duration` s plus `breath.seconds_per_amount` s for every point of `amount`
## past the first ("increasing projectile count increases the number of seconds that they are firing"), at most
## `breath.max_seconds`. While it burns the cone follows his facing and walks with him; it never aims: it waits up to
## `breath.wait` s for a creature to stand in the cone, then breathes where he faces if anyone is within reach at all.
## Every creature whose body is in the cone (`range` m long, `breath.cone_deg` wide x the `area` stat, 360 a full ring)
## takes `damage` every `breath.tick` s (the first the moment it is in the fire) and is set alight with the weapon's
## fire_damage / fire_duration / fire_spread (EnemyManager.ignite: one that walks out keeps burning).
## The path: Backdraft (motion; `breath.knock`): every tick also shoves the creature straight away from the hero (through
## EnemyManager.damage's push, at the map's hero share) and the fire roars bigger (`breath.look.intensity`). Blue Flame
## (element; `fire_blue`, as the Molotov's Methanol): further, a little weaker, burns longer, the breath and the burning
## creatures blue. Held Breath (volume; `breath.still {seconds, duration_mult, damage_mult, ring}`): an attack that starts
## after the hero has stood completely still, unhit, for `seconds` (Player.still_unhit_seconds: a hit that lands breaks
## the stillness, an attack already burning is never cut) lasts duration_mult times as long, every tick hits damage_mult
## times, and the fire comes from all sides of his face (a full ring). The evolution (the Fire Eater) amplifies all of it
## and carries thorns on the hero (a weapon level effect aimed at "player", Run._apply_weapon_player_effects).
## Cheap, visible: pooled flame billboards streaming down the cone (Fx.breath_jet), a few embers, a wash of light on the
## sand under it (Telegraphs.wash) and a scorch that fades where it burnt; the lighter's pop as it starts; a whoosh loop
## for the duration (Audio.play_loop, `sfx.loop`) over the start sound (`sfx.fire`). Numbers: BALANCING.md §41.
## Pass 109 (lane VFX; Garry: "Doesn't look like anything at the moment ... more like fire and more like breath? Maybe a
## simple cheap 3d particle thing?"): the flames are particles now (core/systems/BreathFlames.gd: soft puffs thrown out of
## his mouth, fast there and slowing down the cone, white-hot to orange to red to smoke, and a bright core at the mouth),
## pointed along his facing every frame of the breath and left to burn out when it ends; Fx.breath_jet is no longer
## called. The wash on the sand and the scorch stay.
class_name FireBreath
extends WeaponBehavior

## params.breath when it leaves a key out.
const DEFAULTS := {"cone_deg": 50.0, "tick": 1.0, "seconds_per_amount": 1.0, "max_seconds": 6.0, "face_up": 1.45,
	"face_forward": 0.3, "wait": 2.0, "knock": 0.0}
## Held Breath's block (params.breath.still) when it leaves a key out.
const STILL_DEFAULTS := {"seconds": 2.0, "duration_mult": 2.0, "damage_mult": 1.5, "ring": true}
## The cone's least width and the width that counts as a full ring.
const MIN_DEG := 15.0
const RING_DEG := 359.0
## The estimate's crowd is WeaponInstance.BREATH_CATCH (HeroPower.crowd_of).
## The look: the wash on the sand redrawn every WASH_EVERY, the scorch left at the end (pass 109: the flames are
## BreathFlames' particles; FX_EVERY and FX_FLAMES were Fx.breath_jet's pace, kept for the tools that read them).
const FX_EVERY := 0.045
const FX_FLAMES := 3
const WASH_EVERY := 0.22
const ORANGE := Color(1.0, 0.56, 0.16)
const BLUE := Color(0.36, 0.6, 1.0)
const LIGHTER := Color(1.0, 0.95, 0.8)

## Seconds left of the breath burning now (0 between breaths) and its whole length.
var _breath_t := 0.0
var _breath_len := 0.0
## This breath: a full ring (Held Breath), its tick multiplier, its clock from 0.
var _ring := false
var _dmg_mult := 1.0
var _clock := 0.0
## When each creature in the fire takes its next tick, by its spawn serial (a slot handed to a new creature starts over).
var _next_tick: Dictionary = {}
## How long the cooldown has been ready with nobody in the cone (the wait before it breathes anyway).
var _ready_for := 0.0
var _fx_t := 0.0
var _wash_t := 0.0
var _loop_on := false
## Pass 109: the breath's particles (made at the first breath, never in a run sim).
var _flames: BreathFlames
## Diagnostics and tests: breaths started, still ones among them, ticks landed, shoves, the creatures the last tick hit.
var breaths := 0
var still_breaths := 0
var ticks := 0
var knocks := 0
var last_hits := PackedInt32Array()
var last_len := 0.0


func _uses_projectiles() -> bool:
	return false


# ---------------------------------------------------------------- params

## params.breath, {} without it.
func breath() -> Dictionary:
	var b = inst.params.get("breath") if inst else null
	return b if b is Dictionary else {}


## A number of params.breath, else DEFAULTS'.
func bval(key: String) -> float:
	return float(breath().get(key, DEFAULTS.get(key, 0.0)))


## Held Breath's block (params.breath.still), {} without the mutation.
func still_block() -> Dictionary:
	var s = breath().get("still")
	return s if s is Dictionary else {}


func still_value(key: String) -> float:
	return float(still_block().get(key, STILL_DEFAULTS.get(key, 0.0)))


## The look's intensity (params.breath.look.intensity; Backdraft 1.5, the Fire Eater more): the flames' size and count.
func intensity() -> float:
	var lk = breath().get("look")
	return maxf(float((lk as Dictionary).get("intensity", 1.0)) if lk is Dictionary else 1.0, 0.1)


## The cone's width now: breath.cone_deg x the area stat, MIN_DEG at least, a full ring at RING_DEG and past it
## (WeaponInstance.breath_cone_deg: the rows and the words say the same).
func cone_deg() -> float:
	return inst.breath_cone_deg()


## How many seconds a breath lasts before Held Breath's doubling: `duration` + seconds_per_amount per point of amount past
## the first, max_seconds at most (WeaponInstance.breath_seconds: the estimate counts the same).
func breath_seconds() -> float:
	return inst.breath_seconds()


## Seconds between ticks on a creature standing in the fire.
func tick_seconds() -> float:
	return maxf(bval("tick"), 0.1)


## Whether this weapon's fire burns blue (Blue Flame, the Fire Eater): WeaponInstance.blue_fire.
func blue() -> bool:
	return inst != null and inst.blue_fire()


func burning() -> bool:
	return _breath_t > 0.0


func is_ring() -> bool:
	return burning() and _ring


# ---------------------------------------------------------------- where

## Where the fire starts: the hero's face (Player.face_origin), else about 1.45 m up and a little forward.
func origin() -> Vector3:
	var d: Vector3 = player.forward()
	if player.has_method("face_origin"):
		return player.face_origin(d)
	return player.global_position + Vector3(0, bval("face_up"), 0) + d * bval("face_forward")


## The breath's direction: where the hero faces, flat.
func dir() -> Vector3:
	var d: Vector3 = player.forward()
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


## The creatures whose bodies stand in the cone (`reach` m from the hero's feet, `deg` wide along `d`; a ring past
## RING_DEG): a creature counts when any of its body (its radius) is inside, so one on the edge still burns. Never a
## dying, hidden or held one.
func indices_in_fire(from: Vector3, d: Vector3, reach: float, deg: float) -> PackedInt32Array:
	var em: EnemyManager = game.enemies
	var out := PackedInt32Array()
	if em == null:
		return out
	var ring := deg >= RING_DEG
	var half := deg_to_rad(clampf(deg, 1.0, 360.0)) * 0.5
	var d2 := Vector2(d.x, d.z).normalized()
	for i in em.indices_in_radius(from, reach + 1.2):
		if not em.is_alive(i) or em.state[i] == EnemyManager.STATE_DYING or em.hidden[i] == 1:
			continue
		var r: float = maxf(em.radius[i], 0.2)
		var v := Vector2(em.pos[i].x - from.x, em.pos[i].z - from.z)
		var dist := v.length()
		if dist - r > reach:
			continue
		if ring or dist <= r:
			out.append(i)
			continue
		# the angle its body subtends widens the cone for it
		var ang := absf(angle_difference(atan2(d2.y, d2.x), atan2(v.y, v.x)))
		if ang <= half + asin(clampf(r / maxf(dist, 0.001), 0.0, 1.0)):
			out.append(i)
	return out


# ---------------------------------------------------------------- firing

## Breathes when a creature stands in the cone; after `wait` s ready with nobody there, when anyone is within reach.
func _fire() -> bool:
	var em: EnemyManager = game.enemies
	if em == null or burning():
		return false
	var reach := stat("range", 5.0)
	var from := player.global_position
	var still := _still_now()
	var ring: bool = still and bool(still_block().get("ring", STILL_DEFAULTS["ring"]))
	var inside := indices_in_fire(from, dir(), reach, 360.0 if ring else cone_deg())
	if inside.is_empty():
		# the wait: the cooldown stays ready while he turns; past it, anyone within reach is reason enough
		if _ready_for < bval("wait") or aim_index(from, reach) < 0:
			return false
	_start(still, ring)
	return true


## Whether Held Breath's stillness holds now: the mutation on, and the hero still and unhit for its seconds.
func _still_now() -> bool:
	if still_block().is_empty() or player == null:
		return false
	var s: float = float(player.still_unhit_seconds()) if player.has_method("still_unhit_seconds") else 0.0
	return s >= still_value("seconds")


## The breath starts: its length (Held Breath doubles it), its tick, its ring; the lighter's pop, the whoosh.
func _start(still: bool, ring: bool) -> void:
	_breath_len = breath_seconds()
	_dmg_mult = 1.0
	_ring = ring
	if still:
		_breath_len *= maxf(still_value("duration_mult"), 0.1)
		_dmg_mult = maxf(still_value("damage_mult"), 0.0)
		still_breaths += 1
	_breath_t = _breath_len
	last_len = _breath_len
	_clock = 0.0
	_next_tick.clear()
	_ready_for = 0.0
	_fx_t = 0.0
	_wash_t = 0.0
	breaths += 1
	var at := origin()
	sfx("fire", at)
	_loop_start()
	_flames_start()
	var fx = game.get("fx")
	if fx and fx.has_method("burst"):
		fx.burst(at + dir() * 0.25, LIGHTER, 0.3)
	# the first tick lands at once
	_burn_tick()


func _tick(delta: float) -> void:
	if not burning():
		# the wait's clock: how long the cooldown has been ready (the base retries a refused fire every 0.15 s, so
		# "ready" is any cooldown that short); a cooldown that still runs resets it
		if cooldown_left <= 0.2:
			_ready_for += delta
		else:
			_ready_for = 0.0
		return
	_breath_t -= delta
	_clock += delta
	# no tick on the breath's last frame: a 2 s breath ticks at 0 and 1 s (WeaponInstance.breath_ticks counts the same)
	if _breath_t > 0.0005:
		_burn_tick()
	_show(delta)
	# the whoosh again after a pause stopped it
	if not _loop_on and _breath_t > 0.0:
		_loop_start()
	if _breath_t <= 0.0:
		_end()


## The breath is over: the whoosh stops, a scorch is left on the sand where it burnt.
func _end() -> void:
	_breath_t = 0.0
	_next_tick.clear()
	_loop_stop()
	if _flames:
		_flames.stop()
	var tg = game.get("telegraphs")
	if tg and tg.has_method("scorch") and not Run.sim_mode:
		var reach := stat("range", 5.0)
		var c: Vector3 = player.global_position + (Vector3.ZERO if _ring else dir() * reach * 0.5)
		var map = game.get("map")
		if map and map.has_method("height_at"):
			c.y = map.height_at(c.x, c.z)
		var col := BLUE if blue() else ORANGE
		tg.scorch(c, (reach * 0.5 if _ring else reach * 0.32) * sqrt(intensity()), Color(col.r * 0.5, col.g * 0.3, col.b * 0.2, 0.5), Color(0.2, 0.08, 0.02, 0.0), 0.6, 2.2)


## Every creature in the fire takes a tick every tick_seconds (the first the moment it is inside), the burn, and Backdraft's
## shove straight away from the hero.
func _burn_tick() -> void:
	var em: EnemyManager = game.enemies
	if em == null:
		return
	var reach := stat("range", 5.0)
	var from := player.global_position
	var hits := indices_in_fire(from, dir(), reach, 360.0 if _ring else cone_deg())
	last_hits = hits
	var wid := inst.def.id
	var dmg := stat("damage", 12.0) * _dmg_mult
	var fdmg := stat("fire_damage", 0.0)
	var knock := bval("knock")
	var every := tick_seconds()
	for e in hits:
		var s: int = em.serial[e]
		var due: float = float(_next_tick[s]) if _next_tick.has(s) else _clock
		if due > _clock:
			continue
		# the cadence is anchored to its entry: a tick that lands a frame late never delays the next (else every tick
		# slips a frame and a 7 s breath loses its last); one back after a long absence starts its clock afresh
		var nxt := due + every
		_next_tick[s] = nxt if nxt > _clock else _clock + every
		ticks += 1
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.3))
		var away: Vector3 = em.pos[e] - from
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.0001 else dir()
		if knock > 0.0:
			knocks += 1
		if em.damage(e, dmg, wid, away, knock):
			inst.kills += 1


# ---------------------------------------------------------------- the look and the sound

## The flames streaming down the cone (pass 109: BreathFlames, pointed from his face along his facing), the wash of light
## on the sand.
func _show(delta: float) -> void:
	if Run.sim_mode:
		return
	var reach := stat("range", 5.0)
	var deg := 360.0 if _ring else cone_deg()
	var d := dir()
	var at := origin()
	var k := intensity()
	# the last tenth of a second thins out, so the breath dies away instead of stopping dead
	var fade := clampf(_breath_t / 0.12, 0.0, 1.0)
	# pass 109: the particles follow his face and his facing (BreathFlames)
	if _flames:
		_flames.follow(at, d)
	_wash_t -= delta
	if _wash_t <= 0.0:
		_wash_t = WASH_EVERY
		var tg = game.get("telegraphs")
		if tg and tg.has_method("wash"):
			var g: Vector3 = player.global_position
			var map = game.get("map")
			if map and map.has_method("height_at"):
				g.y = map.height_at(g.x, g.z)
			var col := BLUE if blue() else ORANGE
			# a ring's wash is a whole disc under him for 4-7 s: dimmer, a glow rather than a plate (the captures)
			tg.wash(g, d, reach, deg, WASH_EVERY * 2.2, col, 0.28 * minf(k, 1.6) * fade * (0.55 if _ring else 1.0))


## Pass 109: the particles start with the breath (made the first time), fitted to its reach, width, colour and look.
func _flames_start() -> void:
	if Run.sim_mode or game == null:
		return
	if _flames == null or not is_instance_valid(_flames):
		_flames = BreathFlames.make(game)
	_flames.start(stat("range", 5.0), 360.0 if _ring else cone_deg(), _ring, blue(), intensity())
	_flames.follow(origin(), dir())


## The particles (tests and the capture; null before the first breath).
func flames() -> BreathFlames:
	return _flames


## The loop id: `sfx.loop` ("" = none).
func loop_id() -> String:
	return str(inst.def.sfx.get("loop", "")) if inst and inst.def else ""


func _loop_start() -> void:
	_loop_on = true
	var id := loop_id()
	if id == "" or Run.sim_mode:
		return
	# the blue flame hisses a little higher, the Fire Eater roars lower
	var pitch := 1.0
	if blue():
		pitch *= 1.12
	if inst.def.is_evolution:
		pitch *= 0.88
	Audio.play_loop(id, pitch)


func _loop_stop() -> void:
	if not _loop_on:
		return
	_loop_on = false
	var id := loop_id()
	if id != "":
		Audio.stop_loop(id)


## The base skips the tick while the game is paused or the hero is down: the whoosh must not go on alone.
func _process(delta: float) -> void:
	super._process(delta)
	if _loop_on and (game == null or player == null or player.dead or game.paused):
		_loop_stop()


func _exit_tree() -> void:
	_loop_stop()
	if _flames and is_instance_valid(_flames):
		_flames.queue_free()
	_flames = null
