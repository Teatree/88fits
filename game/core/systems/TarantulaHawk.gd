## The Tarantula Hawk (pass 48, a mutation of the Killer Bees, the Hornet Nest until pass 49, and of the Hive Queen;
## named for a real desert wasp that hunts prey bigger than itself): it takes the strongest creature near (pick: the
## measure EnemyManager.priority_index uses, past any creature another hawk holds, one hawk per creature by its serial),
## flies to it and stings it `stings` times spread over `seconds`, each sting a bee's damage (EnemyManager.damage with the
## weapon's id). While it holds its prey the prey is slowed by `slow` in its moves and its attacks (EnemyManager.hamper)
## and tinted purple (TINT). It never goes after another (Second Sting is the bees'): when its prey dies, by its sting
## or anything else, it drops and fades; after its last sting it flies off and fades. MissilePod launches it (launch),
## params.hawk {every, stings, seconds, slow}. Its sting is "w_hawk_sting".
## Pass 49 (Garry: "make the projectile look less like a bee and more like a circle (just a bigger one) like all others
## are ... instead of just bouncing on it, they fly around it at similar speeds as all bees ... kind of like in the
## cartoons when a bee attacks someone"): it is one glowing purple ball, RADIUS (two and a half bees) drawn a third
## bigger like every shot (ProjectileManager.CHUNK), with a short tail of purple motes. It buzzes round its prey at the
## bees' speed (the weapon's `speed`, held between SPEED_MIN and SPEED_MAX) on a circle about the creature's size
## across, round its middle, tilted about an axis that keeps turning and bobbing, now and then turning back the other
## way; for every sting it darts in to the body and straight back out to its circle (a burst and the sting sound).
class_name TarantulaHawk
extends Node3D

const GROUP := "tarantula_hawk"
const TINT := Color(0.62, 0.3, 0.95)
## The ball (pass 49): two and a half times a bee's 0.07 m, drawn a third bigger like every shot.
const RADIUS := 0.17
const BALL_COLOR := Color(0.5, 0.2, 0.96)
const GLOW_COLOR := Color(0.44, 0.12, 1.0)
## Metres a second along its circle (and on its way in) when it has no weapon: a bee's. A weapon's own speed is held
## between SPEED_MIN and SPEED_MAX, so a hawk sent while Pollen's buff lasts (x1.5) still draws a circle, not a few
## jumps, on a phone at 30 frames a second.
const SPEED := 15.0
const SPEED_MIN := 11.0
const SPEED_MAX := 18.0
## Its circle: a radius of ORBIT_K x the creature's size + ORBIT_PAD (ORBIT_MIN to ORBIT_MAX metres), centred MID of
## the way up the creature, tilted TILT radians about a level axis that turns TILT_TURN radians a second, bobbing BOB
## metres BOB_HZ times a second.
const ORBIT_K := 0.5
const ORBIT_PAD := 0.15
const ORBIT_MIN := 0.55
const ORBIT_MAX := 2.6
const MID := 0.5
const TILT := 0.42
const TILT_TURN := 1.3
const BOB := 0.12
const BOB_HZ := 2.6
## Now and then it turns back the other way: every SWITCH_MIN to SWITCH_MAX seconds, the turn taking 2 / SWITCH_RATE s.
const SWITCH_MIN := 0.7
const SWITCH_MAX := 1.5
const SWITCH_RATE := 9.0
## A sting: it darts in for DART_IN seconds to INNER metres off the creature's middle, stings, and is back on its circle
## DART_OUT seconds later; its circle turns at DART_SPIN of its speed meanwhile, so it comes straight back out.
const DART_IN := 0.08
const DART_OUT := 0.13
const DART_SPIN := 0.25
const INNER := 0.12
## Its first sting comes this long after it reaches its circle (a turn or so of buzzing first).
const FIRST_STING := 0.3
## It joins its circle once this close to its spot on it; on its circle it never moves more than CATCH_UP times its
## speed (a prey that blinks or is thrown is flown after, not snapped to).
const ARRIVE := 0.3
const CATCH_UP := 2.5
## The tail: a mote every TAIL_EVERY seconds that shrinks and fades over TAIL_LIFE.
const TAIL_EVERY := 0.02
const TAIL_LIFE := 0.14
## How often the hold on its prey (the slow, the tint) is renewed, and for how long each time.
const HOLD_EVERY := 0.25
const HOLD_FOR := 0.5
## Seconds of its last flight off, and of its fall when its prey dies.
const LEAVE := 0.6
const FALL := 0.7
## How long it may fly before it gives up on prey it cannot reach (it went under the sand, out of the arena).
const FLY_MAX := 3.0

enum { FLY_IN, HOLD, LEAVING, FALLING }

var game: Node
var weapon: WeaponInstance
var prey := -1
var prey_serial := -1
var stings := 5
var interval := 0.8
var slow := 0.1
var damage := 5.0
## Metres a second along its circle (the weapon's speed at launch, held to SPEED_MIN..SPEED_MAX).
var speed := SPEED
var stings_done := 0
var state: int = FLY_IN
## Darts begun (one for each sting), and whether one is under way.
var darts := 0
var darting := false
var _t := 0.0           # seconds in the current state
var _since := 0.0       # seconds since the last sting
var _hold_t := 0.0
var _vel := Vector3.ZERO
var _ang := 0.0         # where it is round its prey, radians on its circle
var _spin := 1.0        # which way it turns now, easing between -1 and 1
var _dir := 1.0         # which way it is turning towards
var _switch_t := 1.0    # seconds until it turns back
var _tilt_a := 0.0      # the level axis its circle tilts about, radians round the vertical
var _bob_t := 0.0
var _dart_t := 0.0
var _stung := false     # this dart has stung
var _tail_t := 0.0
var _ball: MeshInstance3D

static var _ball_mesh: SphereMesh
static var _ball_mat: StandardMaterial3D


## A hawk from `from` after creature `p` for weapon `w` (its params.hawk {stings, seconds, slow}); null when `p` is gone.
static func launch(p_game: Node, w: WeaponInstance, from: Vector3, p: int, cfg: Dictionary) -> TarantulaHawk:
	var em: EnemyManager = p_game.enemies
	if p < 0 or em.alive[p] == 0 or em.state[p] == EnemyManager.STATE_DYING:
		return null
	var h := TarantulaHawk.new()
	h.game = p_game
	h.weapon = w
	h.prey = p
	h.prey_serial = em.serial[p]
	h.stings = maxi(int(cfg.get("stings", 5)), 1)
	h.interval = maxf(float(cfg.get("seconds", 4.0)), 0.1) / float(h.stings)
	h.slow = float(cfg.get("slow", 0.1))
	h.damage = w.stat("damage", 5.0) if w else 5.0
	h.speed = clampf(w.stat("speed", SPEED), SPEED_MIN, SPEED_MAX) if w else SPEED
	p_game.add_child(h)
	h.global_position = from
	return h


## The serials of the creatures hawks hold or are flying at (one hawk per creature).
static func held_serials(p_game: Node) -> Dictionary:
	var out := {}
	if p_game == null or not p_game.is_inside_tree():
		return out
	for n in p_game.get_tree().get_nodes_in_group(GROUP):
		var h := n as TarantulaHawk
		if h and not h.is_queued_for_deletion() and (h.state == FLY_IN or h.state == HOLD):
			out[h.prey_serial] = true
	return out


## The creature a new hawk takes: the strongest near `from` within `range_m` by priority_index's measure (distance over
## a weight by max HP, big game at the cap) that no hawk holds yet; -1 for none.
static func pick(em: EnemyManager, from: Vector3, range_m: float, taken: Dictionary) -> int:
	# pass 73 (lane SNIPER): a special, an Elite or the boss within reach first (one hawk per creature still)
	var pt := em.priority_target(from, range_m, true)
	if pt >= 0 and not taken.has(em.serial[pt]):
		return pt
	# it hunts off the screen too (pass 54: the homing weapons are not held to the screen)
	var first := em.priority_index(from, range_m, "", true)
	if first < 0 or not taken.has(em.serial[first]):
		return first
	var mean_v = em.get("_mean_max_hp")
	var mean: float = maxf(float(mean_v) if mean_v != null else 0.0, 0.001)
	var best := -1
	var best_k := INF
	for i in em.indices_in_radius(from, range_m):
		if taken.has(em.serial[i]):
			continue
		var d := em.pos[i] - from
		d.y = 0.0
		var wgt: float = EnemyManager.PRIORITY_CAP if em.is_big_game(i) else clampf(em.max_hp[i] / mean, 1.0, EnemyManager.PRIORITY_CAP)
		var k := d.length_squared() / (wgt * wgt)
		if k < best_k:
			best_k = k
			best = i
	return best


## The ball's mesh: a sphere of RADIUS drawn a third bigger, as ProjectileManager draws every shot (one for every hawk).
static func ball_mesh() -> SphereMesh:
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = RADIUS * ProjectileManager.CHUNK
		_ball_mesh.height = RADIUS * ProjectileManager.CHUNK * 2.0
		_ball_mesh.radial_segments = 12
		_ball_mesh.rings = 6
	return _ball_mesh


## The ball's material, lit and glowing as the bees' is (their visual's albedo with emission), in purple.
static func ball_material() -> StandardMaterial3D:
	if _ball_mat == null:
		_ball_mat = StandardMaterial3D.new()
		_ball_mat.albedo_color = BALL_COLOR
		_ball_mat.roughness = 0.4
		_ball_mat.emission_enabled = true
		_ball_mat.emission = GLOW_COLOR
		_ball_mat.emission_energy_multiplier = 0.9
	return _ball_mat


func _ready() -> void:
	add_to_group(GROUP)
	_build()


## One glowing purple ball (pass 49: the wasp with wings and a banded body read as a bee).
func _build() -> void:
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	_ball.mesh = ball_mesh()
	_ball.material_override = ball_material()
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)


## Whether its prey is still the creature it took, alive and on its feet.
func prey_alive() -> bool:
	var em: EnemyManager = game.enemies if game else null
	if em == null or prey < 0:
		return false
	return em.alive[prey] == 1 and em.serial[prey] == prey_serial and em.state[prey] != EnemyManager.STATE_DYING


## The middle of its prey, where its circle is centred.
func centre() -> Vector3:
	var em: EnemyManager = game.enemies
	return em.pos[prey] + Vector3(0, em.size[prey] * MID + em.lift_h[prey], 0)


## The radius of its circle: about the creature's size across.
func orbit_radius() -> float:
	var em: EnemyManager = game.enemies
	return clampf(em.size[prey] * ORBIT_K + ORBIT_PAD, ORBIT_MIN, ORBIT_MAX)


## Its spot on the circle at angle `a`: the level circle tilted about its turning axis, bobbing.
func _orbit_point(a: float) -> Vector3:
	var r := orbit_radius()
	var v := Vector3(cos(a) * r, 0.0, sin(a) * r)
	v = v.rotated(Vector3(cos(_tilt_a), 0.0, sin(_tilt_a)), TILT)
	return centre() + v + Vector3(0, BOB * sin(_bob_t * TAU * BOB_HZ), 0)


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if game == null or game.paused:
		return
	tick(delta)


## One step of its life (tests call this with their own clock).
func tick(delta: float) -> void:
	_t += delta
	if (state == FLY_IN or state == HOLD) and not prey_alive():
		# its prey is gone: no other, it drops
		_enter(FALLING)
		darting = false
		_vel = Vector3(Dice.r.randf_range(-1.0, 1.0), 1.5, Dice.r.randf_range(-1.0, 1.0))
	match state:
		FLY_IN:
			_fly_in(delta)
		HOLD:
			_hold(delta)
		LEAVING:
			_vel.y += 6.0 * delta
			global_position += _vel * delta
			_fade(_t / LEAVE)
		FALLING:
			_vel.y -= 18.0 * delta
			global_position += _vel * delta
			var ground: float = game.map.height_at(global_position.x, global_position.z) if game.map else -INF
			global_position.y = maxf(global_position.y, ground + 0.1)
			_fade(_t / FALL)
	_tail(delta)


func _enter(s: int) -> void:
	state = s
	_t = 0.0


## Its circle keeps moving: the tilt's axis turns, the bob runs, and now and then it turns back the other way, easing
## through a stop.
func _turn(delta: float) -> void:
	_bob_t += delta
	_tilt_a += TILT_TURN * delta
	_switch_t -= delta
	if _switch_t <= 0.0:
		_switch_t = Dice.r.randf_range(SWITCH_MIN, SWITCH_MAX)
		_dir = -_dir
	_spin = move_toward(_spin, _dir, SWITCH_RATE * delta)
	_ang += speed / orbit_radius() * _spin * (DART_SPIN if darting else 1.0) * delta


## On its way in: it makes for the spot on its circle on the side it comes from, at the bees' speed, weaving a little.
func _fly_in(delta: float) -> void:
	_bob_t += delta
	_tilt_a += TILT_TURN * delta
	var flat := global_position - centre()
	flat.y = 0.0
	if flat.length_squared() > 0.0001:
		_ang = atan2(flat.z, flat.x)
	var to := _orbit_point(_ang) - global_position
	var d := to.length()
	var step := speed * delta
	if d <= maxf(ARRIVE, step):
		_arrive()
		return
	if _t > FLY_MAX:
		_leave()
		return
	var side := to.cross(Vector3.UP).normalized() * sin(_t * 9.0) * 0.35
	global_position += (to / d + side * 0.3).normalized() * step


## On its circle: it buzzes round for FIRST_STING seconds before the first dart, and turns either way.
func _arrive() -> void:
	_enter(HOLD)
	_since = interval - FIRST_STING
	_dir = 1.0 if Dice.r.randf() < 0.5 else -1.0
	_spin = _dir
	_switch_t = Dice.r.randf_range(SWITCH_MIN, SWITCH_MAX)
	_hold_t = 0.0
	global_position = _orbit_point(_ang)
	_floor()


## Round and round its prey, holding it slowed and purple, darting in for each sting; it leaves an `interval` after
## the last one.
func _hold(delta: float) -> void:
	var em: EnemyManager = game.enemies
	_hold_t -= delta
	if _hold_t <= 0.0:
		_hold_t = HOLD_EVERY
		# it holds its prey slowed and purple (renewed, so it ends with the hold)
		em.hamper(prey, slow, HOLD_FOR, false)
		em.set_status_tint(prey, TINT, HOLD_FOR)
	_turn(delta)
	_since += delta
	var ring := _orbit_point(_ang)
	# a dart starts from its circle: while it is still catching up with its prey (it blinked, it was thrown) the sting waits
	var lagging := global_position.distance_to(ring) > speed * CATCH_UP * delta
	if not darting and not lagging and stings_done < stings and _since >= interval - DART_IN:
		darting = true
		_dart_t = 0.0
		_stung = false
		darts += 1
	if darting:
		# in to the body along the line from its middle, a sting, and straight back out to its circle
		_dart_t += delta
		var c := centre()
		var out := ring - c
		var body := c + (out.normalized() * INNER if out.length_squared() > 0.0001 else Vector3.ZERO)
		if _dart_t < DART_IN:
			var f: float = _dart_t / DART_IN
			global_position = ring.lerp(body, f * f)
		else:
			if not _stung:
				_stung = true
				_sting(body)
			var g: float = clampf((_dart_t - DART_IN) / DART_OUT, 0.0, 1.0)
			global_position = body.lerp(ring, 1.0 - (1.0 - g) * (1.0 - g))
			if g >= 1.0:
				darting = false
	else:
		_move_to(ring, delta)
		if stings_done >= stings and _since >= interval:
			_leave()
			return
	_floor()


## To `want`, its spot on its circle this frame; a jump far past a frame's flight (its prey blinked or was thrown) is
## flown at CATCH_UP times its speed instead, so it never snaps across the screen.
func _move_to(want: Vector3, delta: float) -> void:
	var step := want - global_position
	var most := speed * CATCH_UP * delta
	if step.length() > most:
		global_position += step.normalized() * most
	else:
		global_position = want


## Never into the sand under its prey.
func _floor() -> void:
	var em: EnemyManager = game.enemies
	global_position.y = maxf(global_position.y, em.pos[prey].y + RADIUS)


## A sting at `at` (the dart's tip on the body): a bee's damage, a purple burst and the sound.
func _sting(at: Vector3) -> void:
	var em: EnemyManager = game.enemies
	_since = 0.0
	stings_done += 1
	var wid: String = weapon.def.id if weapon else ""
	if em.damage(prey, damage, wid, Vector3.ZERO, 0.0) and weapon:
		weapon.kills += 1
	var fx = game.get("fx")
	if fx:
		fx.burst(at, TINT, 0.45)
	Audio.play("w_hawk_sting", at)


## Done with its prey: it flies off along its circle and up, fading.
func _leave() -> void:
	_enter(LEAVING)
	darting = false
	var tangent := Vector3(-sin(_ang), 0.0, cos(_ang)) * (signf(_spin) if _spin != 0.0 else 1.0)
	_vel = tangent * speed * 0.5 + Vector3(0, 4.0, 0)


func _fade(k: float) -> void:
	var s: float = clampf(1.0 - k, 0.0, 1.0)
	scale = Vector3(s, s, s) if s > 0.001 else Vector3(0.001, 0.001, 0.001)
	if k >= 1.0:
		queue_free()


## The short purple tail: a mote where it is every TAIL_EVERY seconds, shrinking and fading (none once it falls).
func _tail(delta: float) -> void:
	if state == FALLING or game == null:
		return
	_tail_t -= delta
	if _tail_t > 0.0:
		return
	_tail_t = TAIL_EVERY
	var fx = game.get("fx")
	if fx:
		fx.mote(global_position, Vector3.ZERO, TAIL_LIFE, RADIUS * ProjectileManager.CHUNK * 1.7 * scale.x, Color(TINT.r, TINT.g, TINT.b, 0.55))
