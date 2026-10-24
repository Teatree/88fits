## The Guitarra's chord (pass 46): a cone of melody, not a shotgun. Every `cooldown` the companion guitar strums at the
## nearest creature within `range` of it, and everything standing in a cone `range` long and TextGen.cone_width wide
## (params.cone.deg, at least `min_deg`, widened by `area`, a full ring at 360) takes `damage` with the weapon's fire or
## poison, and is lifted `cone.lift` metres and set down on the spot it stood after `cone.lift_time` seconds
## (EnemyManager.bounce: no spin, no fall damage), landing with a small shove of `cone.knock`: straight away from the
## guitar, or with `cone.side_random` to one side or the other (Music Slap). Bosses and Elites only take the hit.
## `amount` (Multishot) is echoes: each one past the first sends another wave down the same line ECHO_GAP seconds after
## the last (closer together when the cooldown is shorter, so none is lost) at WeaponInstance.ECHO_FRAC of the damage.
## The visual scene's "Familiar" holds the guitar (art/props/guitarra.glb: Body, Strings and a Soundhole empty at the
## origin, the neck up +Y, the top facing +Z): it floats by the hero like the gun companions (params.familiar) and is
## held the way a player holds a guitar, the top tipped back towards the camera, the neck leaning to the upper left,
## turned a little towards its aim. Every chord rocks the body on a spring, blurs and lights the strings and throws notes
## out of the soundhole down the cone (Fx.note), over a gold wash on the sand (Telegraphs.wash) and a ring at its feet.
## params.cone: deg, min_deg, lift, lift_time, knock, side_random, notes, color [r, g, b];
## params.familiar: radius, height, speed, bob, tilt_back_deg, neck_deg, lean_deg.
## Pass 48, Tinnitus (params.tinnitus {every, damage_mult, knock_mult}): every `every`th hit on the same creature (the
## waves and their echoes all count) deals `damage_mult` times the damage and lands with `knock_mult` times the shove,
## with a small white ring on it. The count follows the creature by its spawn serial (EnemyManager.serial): a slot handed
## to a new creature starts again from nothing.
class_name ConeWave
extends WeaponBehavior

const ECHO_GAP := 0.2
## the hold: tipped back towards the high camera, the neck leaning left of upright, turned towards the aim at most this
const TILT_BACK_DEG := 24.0
const NECK_DEG := 35.0
const LEAN_DEG := 18.0
## the strum's rock: a spring (stiffness, damping) kicked at every chord, an echo's kick a little softer
const ROCK_K := 420.0
const ROCK_D := 9.0
const ROCK_KICK := 9.0
const NOTE_LIFE := 0.6
const GOLD := Color(1.0, 0.82, 0.35)
const RING_WHITE := Color(1.0, 1.0, 1.0)

var _familiar: Node3D
var _strings: MeshInstance3D
var _string_mat: StandardMaterial3D
var _string_rest := Vector3.ONE
var _soundhole: Node3D
var _orbit := 0.0
var _aim := Vector3.FORWARD
var _rock := 0.0
var _rock_v := 0.0
var _shimmer := 0.0
var _echoes: Array = []   # waves still to come: {t, dir, mult}
## waves sent so far and the creatures the last one caught (tests, the arena)
var waves := 0
var last_hits := PackedInt32Array()
## Tinnitus: hits counted per slot, with the serial of the creature they were counted on; rings so far (tests)
var _tin_serial := PackedInt32Array()
var _tin_count := PackedInt32Array()
var rings := 0


func _uses_projectiles() -> bool:
	return false


func _on_setup() -> void:
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar == null:
		_familiar = Node3D.new()
		_familiar.name = "Familiar"
		visual.add_child(_familiar)
	_strings = _familiar.find_child("Strings", true, false) as MeshInstance3D
	if _strings and _strings.mesh:
		_string_rest = _strings.scale
		# the strings' own material, lit from inside on a strum
		var base: Material = _strings.material_override if _strings.material_override else _strings.mesh.surface_get_material(0)
		_string_mat = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()) as StandardMaterial3D
		_string_mat.emission_enabled = true
		_string_mat.emission = Color(1.0, 0.92, 0.65)
		_string_mat.emission_energy_multiplier = 0.0
		_strings.material_override = _string_mat
	_soundhole = _familiar.find_child("Soundhole", true, false) as Node3D
	_orbit = randf() * TAU
	_place(0.0)


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


func _cone(key: String, default: float) -> float:
	var c = inst.params.get("cone", {})
	return float(c.get(key, default)) if c is Dictionary else default


func _cone_flag(key: String) -> bool:
	var c = inst.params.get("cone", {})
	return bool(c.get(key, false)) if c is Dictionary else false


## The cone's colour: the burn's orange or the poison's green when the weapon carries one, else params.cone.color (gold).
func _colour() -> Color:
	if stat("fire_damage", 0.0) > 0.0:
		return Color(1.0, 0.55, 0.2)
	if stat("poison_damage", 0.0) > 0.0:
		return Color(0.5, 1.0, 0.4)
	var cone = inst.params.get("cone", {})
	var c = (cone as Dictionary).get("color") if cone is Dictionary else null
	if c is Array and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return GOLD


## Where the cone starts: the guitar's spot on the ground (the hero's, without one).
func _apex() -> Vector3:
	var p: Vector3 = _familiar.global_position if _familiar and _familiar.is_inside_tree() else player.global_position
	var map = game.get("map")
	p.y = map.height_at(p.x, p.z) if map else player.global_position.y
	return p


## Where the notes come out: the soundhole.
func _hole() -> Vector3:
	if _soundhole and _soundhole.is_inside_tree():
		return _soundhole.global_position
	return _apex() + Vector3(0, 1.4, 0)


func _place(delta: float) -> void:
	if _familiar == null or not _familiar.is_inside_tree():
		return
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.5)
	var bob := _familiar_param("bob", 0.14)
	_orbit += delta * _familiar_param("speed", 1.3)
	var t := Run.rule_seconds()  # pass 77 (lane SIMRUN): real time in play, the run's clock in a run sim
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 3.1) * bob, sin(_orbit) * r)
	# eased follow, as the gun companions: a sprinting hero drags it along a little
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	# held: tipped back to the camera, the neck to the upper left, turned towards the aim; the strum rocks it (Euler YXZ:
	# the neck's lean in the guitar's own plane first, then the tip back, then the turn)
	var lean := clampf(_aim.x, -1.0, 1.0) * deg_to_rad(_familiar_param("lean_deg", LEAN_DEG))
	var tilt := -deg_to_rad(_familiar_param("tilt_back_deg", TILT_BACK_DEG)) - 0.15 * _rock
	var neck := deg_to_rad(_familiar_param("neck_deg", NECK_DEG)) + 0.32 * _rock + sin(t * 2.1) * 0.04
	_familiar.rotation = Vector3(tilt, lean, neck)


func _tick(delta: float) -> void:
	for k in range(_echoes.size() - 1, -1, -1):
		var e: Dictionary = _echoes[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			_echoes.remove_at(k)
			_wave(e["dir"], float(e["mult"]), true)
	# between chords the guitar leans towards the nearest creature, where the next one goes
	var em: EnemyManager = game.enemies
	if em:
		var from := _apex()
		var near := aim_index(from, stat("range", 6.0))
		if near >= 0:
			var to: Vector3 = em.pos[near] - from
			to.y = 0.0
			if to.length_squared() > 0.01:
				_aim = _aim.lerp(to.normalized(), clampf(delta * 8.0, 0.0, 1.0))
				_aim = _aim.normalized() if _aim.length_squared() > 0.0001 else to.normalized()
	# the rock springs back, in small steps so a long frame (a shader compiling) cannot throw the spring loose and spin the
	# guitar round; the strings blur and glow, and settle
	var steps: int = clampi(int(ceil(delta * 60.0)), 1, 8)
	var h: float = delta / float(steps)
	for k in range(steps):
		_rock_v += (-ROCK_K * _rock - ROCK_D * _rock_v) * h
		_rock = clampf(_rock + _rock_v * h, -1.0, 1.0)
	if _strings:
		var t := float(Time.get_ticks_msec()) * 0.001
		var j := _shimmer * _shimmer
		_strings.scale = _string_rest * Vector3(1.0 + 0.12 * j * sin(t * 97.0), 1.0, 1.0 + 0.9 * j * absf(sin(t * 131.0)))
		if _string_mat:
			_string_mat.emission_energy_multiplier = 2.6 * j
	_shimmer = maxf(_shimmer - delta * 3.0, 0.0)
	_place(delta)


func _fire() -> bool:
	var em: EnemyManager = game.enemies
	var from := _apex()
	# pass 73 (lane SNIPER): aim_index, the nearest with a special, an Elite or the boss within reach first
	var t := aim_index(from, stat("range", 6.0))
	if t < 0:
		return false
	var dir: Vector3 = em.pos[t] - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else player.forward()
	_aim = dir
	_wave(dir, 1.0, false)
	var n: int = maxi(stat_int("amount", 1), 1)
	# every echo lands before the next chord: a short cooldown packs them closer instead of losing any
	var gap: float = minf(ECHO_GAP, maxf(stat("cooldown", 1.0), 0.05) / float(n))
	for k in range(1, n):
		_echoes.append({"t": gap * float(k), "dir": dir, "mult": WeaponInstance.ECHO_FRAC})
	return true


func _tinnitus() -> Dictionary:
	var t = inst.params.get("tinnitus")
	return t if t is Dictionary else {}


## Tinnitus: one more hit on creature `i`. True when it is the `every`th on that creature since its count began (the
## count is the creature's, by its serial: a new creature in the slot starts again).
func tinnitus_hit(i: int, every: int) -> bool:
	var em: EnemyManager = game.enemies
	if _tin_count.size() != EnemyManager.MAX:
		_tin_count.resize(EnemyManager.MAX)
		_tin_serial.resize(EnemyManager.MAX)
		_tin_count.fill(0)
		_tin_serial.fill(-1)
	var s: int = em.serial[i]
	if _tin_serial[i] != s:
		_tin_serial[i] = s
		_tin_count[i] = 0
	_tin_count[i] += 1
	if _tin_count[i] >= maxi(every, 1):
		_tin_count[i] = 0
		return true
	return false


## One wave down `dir` at `mult` of the damage: everything in the cone is hit, then bounced on its spot.
func _wave(dir: Vector3, mult: float, echo: bool) -> void:
	var em: EnemyManager = game.enemies
	var from := _apex()
	var reach := stat("range", 6.0)
	var deg := TextGen.cone_width(inst.params, stat("area", 1.0))
	var hits := em.indices_in_cone(from, dir, reach, deg * 0.5)
	var wid := inst.def.id
	var dmg := stat("damage", 12.0) * mult
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var lift := _cone("lift", 0.6)
	var lift_t := _cone("lift_time", 0.45)
	var knock := _cone("knock", 2.5)
	var side := _cone_flag("side_random")
	var tin := _tinnitus()
	var every: int = int(tin.get("every", 3)) if not tin.is_empty() else 0
	var rang: Array = []
	for e in hits:
		if not em.is_alive(e):
			continue
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		var away: Vector3 = em.pos[e] - from
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.0001 else dir
		# Tinnitus: the third hit on it rings, harder and with a bigger shove
		var hit := dmg
		var kmul := 1.0
		if every > 0 and tinnitus_hit(e, every):
			hit *= float(tin.get("damage_mult", 2.0))
			kmul = float(tin.get("knock_mult", 1.5))
			rang.append(em.pos[e] + Vector3(0, em.size[e] * 0.5 + em.lift_h[e], 0))
		if em.damage(e, hit, wid, Vector3.ZERO, 0.0):
			inst.kills += 1
			continue
		# up and down on the spot (a boss or an Elite stays put: bounce says no), landing with the chord's shove, the heavy
		# ones shoved less
		var push := away
		if side:
			push = Vector3(-away.z, 0.0, away.x) * (1.0 if randf() < 0.5 else -1.0)
		# pass 72: at the map's share of the hero's pushes (EnemyManager.hero_knock_mult, Red Canyon 0.5)
		# pass 103: and Endless's knock resistance (EnemyManager.endless_knock_share); the hop stays
		em.bounce(e, lift, lift_t, push * knock * kmul / maxf(em.size[e], 0.8) * em.hero_knock_mult() * em.endless_knock_share(wid))
	waves += 1
	last_hits = hits
	if not rang.is_empty():
		_ring(rang)
	_show(from, dir, reach, deg, mult, echo)


## Tinnitus rang on these creatures (their middles): a small white ring round each on the sand, a white flash on it,
## and the ring's sound once a wave.
func _ring(at: Array) -> void:
	rings += at.size()
	var tg = game.get("telegraphs")
	var fx = game.get("fx")
	var map = game.get("map")
	for p: Vector3 in at:
		if tg and tg.has_method("flash_ring"):
			var g := Vector3(p.x, map.height_at(p.x, p.z) if map else p.y, p.z)
			tg.flash_ring(g, 0.75, RING_WHITE, 0.25)
		if fx and fx.has_method("burst"):
			fx.burst(p, RING_WHITE, 0.3)
	Audio.play("w_tinnitus_ring", at[0])


## The chord seen and heard: the wash on the sand, a ring at the guitar's feet, a puff at the soundhole, notes flying
## out down the cone, the body rocking and the strings ringing.
func _show(from: Vector3, dir: Vector3, reach: float, deg: float, mult: float, echo: bool) -> void:
	var col := _colour()
	var tg = game.get("telegraphs")
	if tg:
		if tg.has_method("wash"):
			tg.wash(from, dir, reach, deg, 0.5, col, 0.42 * mult)
		if not echo and tg.has_method("flash_ring"):
			tg.flash_ring(from, 0.9, col, 0.3)
	var hole := _hole()
	var fx = game.get("fx")
	if fx:
		if fx.has_method("burst"):
			fx.burst(hole, col, 0.32 if echo else 0.45)
		if fx.has_method("note"):
			var n: int = int(round(_cone("notes", 8.0) * (0.6 if echo else 1.0)))
			var half := deg_to_rad(deg) * 0.5
			# with the notes' drag they cover (1 - e^-kT) / k of their speed in their life: fast enough to reach the end
			var span: float = (1.0 - exp(-Fx.NOTE_DRAG * NOTE_LIFE)) / Fx.NOTE_DRAG
			for k in range(n):
				var a: float = randf() * TAU if deg >= 359.0 else randf_range(-half, half) * 0.92
				var d := dir.rotated(Vector3.UP, a)
				var spd: float = reach / span * randf_range(0.75, 1.05)
				fx.note(hole + d * 0.15, d * spd + Vector3(0, randf_range(0.4, 1.4), 0), NOTE_LIFE, randf_range(0.42, 0.6), Color(col.r, col.g, col.b, 1.0))
	_rock_v += ROCK_KICK * (0.55 if echo else 1.0)
	_shimmer = 1.0
	sfx("fire", hole)
