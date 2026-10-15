## The bot's legs (pass 80, lane BOT: moved here from tools/sim_pilot.gd, which now only extends this file so the
## difficulty probe and the pass 77 tests steer exactly as before). Pass 62's kiting autopilot: a circle-strafer. It keeps
## the nearest creature about KEEP metres off, drifting round the crowd (a sideways drift that flips every 3 to 7 s), flees
## what is closer than FLEE, closes in when nothing is near, and is pulled back towards the arena's middle near the wall.
## What a player watches for (lane PC: the bot had walked into every telegraphed hit): a hammer giant, a charger, an Elite
## or a boss within 7 m pushes six times as hard, and a hostile rocket within 10 m sends him straight away from it. It
## steers through the hero's PlayerInput (wants_move, origin, touch_pos) as a thumb would, mapped onto the north-up camera.
## `steer` is the probe's autopilot exactly; the run sim's `steer_sweep` leans it towards a pickup worth walking to and
## `steer_to` walks to a goal (a chest, the portal, a totem, a structure).
## The dials (pass 80; their defaults are pass 77's legs exactly): keep_d / flee_d (Bot's `daring`), reaction (seconds
## before a new warning or a big one close is acted on: the danger push is the one seen `reaction` s ago, a warning on
## the sand counts once it is that old), dodge (the share of warnings he sees at all, by a fixed roll per warning).
## Reached only from tools and tests: nothing here names an autoload or a game class (tools compile before autoloads).
extends RefCounted

const KEEP := 4.5
const FLEE := 2.6
## The run sim's walk to a goal: within COMMIT_NEAR metres of it he walks straight in; from COMMIT_FAR on he sidesteps
## a creature nearer than FLEE (GOAL_FLEE of a step) and the big ones and rockets the probe watches for (GOAL_DANGER).
const COMMIT_NEAR := 1.5
const COMMIT_FAR := 7.5
const GOAL_FLEE := 0.7
const GOAL_DANGER := 0.9
## A rock or a wall circle (the map's obstacles) closer than its radius plus OBSTACLE_REACH, ahead of him on the way to
## the goal, turns him along its edge.
const OBSTACLE_REACH := 2.5

## The run sim's sweep (steer_sweep): with the way to the pickup clear (no creature within LANE_HALF m of the line over
## its first LANE_LEN m) he goes for it, LURE_W against the kite's one; with the way blocked only LURE_CLOSE of that;
## with a big one or a rocket close (the probe's danger) not at all. lure_w and lure_close start at these; the run sim
## may set them.
const LURE_W := 2.0
const LURE_CLOSE := 0.3
const LANE_LEN := 4.0
const LANE_HALF := 1.2
## and only while he is well: the lean is whole at HEALTH_FULL of his health or more, none at HEALTH_NONE or less
const HEALTH_FULL := 0.7
const HEALTH_NONE := 0.35
## The run sim's dodge (ring_push): a hostile warning on the sand (Telegraphs' growing ring in the creatures' red: a
## boulder's or a rocket's landing, a slam, a spit's splash, a boss attack) that he stands in, or within RING_MARGIN m
## of, pushes him out from its middle, RING_PUSH against the kite's one at its middle, fading to a third at its edge.
## A red line on the sand (Telegraphs' strip: the King's roll and his volley's spokes, a charge's or a spit's line) pushes
## him straight off its axis the same way, from its start to its end, within half its width (at least LINE_HALF_MIN) plus
## RING_MARGIN.
const RING_MARGIN := 0.8
const RING_PUSH := 4.0
const LINE_HALF_MIN := 0.3

var lure_w := LURE_W
var lure_close := LURE_CLOSE
## the dials (pass 80): the kite's distances, the reaction delay (s), the share of warnings seen and that roll's seed
var keep_d := KEEP
var flee_d := FLEE
var reaction := 0.0
var dodge := 1.0
var dodge_seed := 0
## the last frame's push out of the warnings he stands in (Bot's intent "dodge")
var seen_ring := Vector3.ZERO
## the danger pushes seen, [clock, Vector3], for the reaction delay
var _danger_hist: Array = []
var _react_clock := 0.0
var rng := RandomNumberGenerator.new()
var strafe := 1.0
var strafe_t := 0.0
## what the last kite_dir saw: the nearest creature's distance (INF for none) and the danger push's length
var seen_nearest := INF
var seen_danger := 0.0


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


## The probe's autopilot (pass 62), one frame: `t` is the tool's clock (seconds since it started; the idle wander reads
## it). Nothing when the run is paused or the hero has no input.
func steer(game: Node, dt: float, t: float) -> void:
	var p: Node3D = game.player
	var inp = p.input
	if inp == null or game.paused:
		return
	push(inp, kite_dir(game, dt, t))


## The run sim's sweep (pass 77): the probe's kite with a lean towards `lure` (the spot most worth walking to, the
## caller's pick; Vector3.INF for none): lure_w while the way there is clear (lane_clear), lure_close of that while a
## creature stands in it, none while a big one or a rocket is close (the probe's danger), all of it times his health's
## say (whole from HEALTH_FULL of it, none at HEALTH_NONE): a player gathering his gems where the crowd lets him and
## while he can afford a bite. Without a lure it is `steer`.
func steer_sweep(game: Node, dt: float, t: float, lure: Vector3) -> void:
	var p: Node3D = game.player
	var inp = p.input
	if inp == null or game.paused:
		return
	var dir := kite_dir(game, dt, t)
	if lure != Vector3.INF:
		var me: Vector3 = p.global_position
		var to_l: Vector3 = lure - me
		to_l.y = 0.0
		var w := lure_w
		var mx := float(p.get("max_hp")) if p.get("max_hp") != null else 0.0
		if mx > 0.0:
			w *= clampf((float(p.get("hp")) / mx - HEALTH_NONE) / (HEALTH_FULL - HEALTH_NONE), 0.0, 1.0)
		if seen_danger > 0.4:
			w = 0.0
		elif not lane_clear(game, me, to_l):
			w *= lure_close
		if w > 0.0 and to_l.length() > 0.05 and dir.length() > 0.0001:
			dir = dir.normalized() + to_l.normalized() * w
	# a red ring under him: out of it first
	var rp := ring_push(game, p.global_position, reaction, dodge, dodge_seed)
	seen_ring = rp
	if rp != Vector3.ZERO and dir.length() > 0.0001:
		dir = dir.normalized() + rp
	push(inp, dir)


## The way out of the hostile warnings he stands in (RING_MARGIN of slack round each): the sum of their pushes, zero
## when he stands in none. A warning is a growing ring (Telegraphs' "band", MODE_GROW) or a line (its "strip") still
## winding up, in the creatures' red (r 0.8 or more, g under 0.42, b under 0.5): what a player reads on the sand and
## steps out of.
## Pass 80: a warning younger than `reaction` s, or one his `dodge` roll misses (seen_warning), is not there for him.
static func ring_push(game: Node, me: Vector3, reaction_s: float = 0.0, dodge_share: float = 1.0, roll_seed: int = 0) -> Vector3:
	var tg = game.get("telegraphs")
	if tg == null:
		return Vector3.ZERO
	var items = tg.get("_items")
	if not (items is Array):
		return Vector3.ZERO
	var out := Vector3.ZERO
	for it in items:
		if not (it is Dictionary) or bool(it.get("dead", false)):
			continue
		var pool := str(it.get("pool", ""))
		var strip := pool == "strip"
		if not strip and (pool != "band" or int(it.get("mode", -1)) != 1):
			continue
		if float(it.get("t", 0.0)) >= float(it.get("dur", 0.0)):
			continue
		var col: Color = it.get("col", Color.WHITE)
		if col.r < 0.8 or col.g >= 0.42 or col.b >= 0.5:
			continue
		var at: Vector3 = it.get("at", Vector3.ZERO)
		if (reaction_s > 0.0 or dodge_share < 1.0) and not seen_warning(it, at, reaction_s, dodge_share, roll_seed):
			continue
		if strip:
			out += line_push(it, at, me)
			continue
		var edge := float(it.get("r", 0.0)) + RING_MARGIN
		var d := Vector3(me.x - at.x, 0.0, me.z - at.z)
		var l := d.length()
		if l >= edge:
			continue
		var away := d / l if l > 0.05 else Vector3(1, 0, 0)
		out += away * RING_PUSH * (1.0 - l / edge * (2.0 / 3.0))
	return out


## Whether he sees the warning `it` lying at `at` (pass 80's dials): it has been up `reaction_s` seconds, and its fixed
## roll (its place, length and kind with the bot's seed) falls under `dodge_share`.
static func seen_warning(it: Dictionary, at: Vector3, reaction_s: float, dodge_share: float, roll_seed: int) -> bool:
	if float(it.get("t", 0.0)) < reaction_s:
		return false
	if dodge_share >= 1.0:
		return true
	var key := hash([roll_seed, snappedf(at.x, 0.01), snappedf(at.z, 0.01), snappedf(float(it.get("dur", 0.0)), 0.01), str(it.get("pool", ""))])
	return float(absi(key) % 10000) / 10000.0 < dodge_share


## The danger push as he sees it (pass 80, `reaction`): the one of `reaction` seconds ago (nothing before he has watched
## that long); with no reaction delay the push itself.
func _react(danger: Vector3, dt: float) -> Vector3:
	if reaction <= 0.0:
		return danger
	_react_clock += dt
	_danger_hist.append([_react_clock, danger])
	var cut := _react_clock - reaction
	while _danger_hist.size() > 1 and float(_danger_hist[1][0]) <= cut:
		_danger_hist.pop_front()
	if float(_danger_hist[0][0]) <= cut:
		return _danger_hist[0][1]
	return Vector3.ZERO


## Off a red line (a Telegraphs strip `it` starting at `at`: its `k` holds the direction in r and g, the length in b and
## the width in a) for the hero at `me`: from its start to its end, within half its width (at least LINE_HALF_MIN) plus
## RING_MARGIN of its axis, straight off the axis, RING_PUSH on the axis, a third of that at the edge; zero elsewhere.
static func line_push(it: Dictionary, at: Vector3, me: Vector3) -> Vector3:
	var k: Color = it.get("k", Color(0, 0, 0, 0))
	var dir := Vector3(k.r, 0.0, k.g)
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	dir = dir.normalized()
	var rel := Vector3(me.x - at.x, 0.0, me.z - at.z)
	var along := rel.dot(dir)
	if along < -RING_MARGIN or along > k.b + RING_MARGIN:
		return Vector3.ZERO
	var side := rel - dir * along
	var sd := side.length()
	var edge := maxf(k.a * 0.5, LINE_HALF_MIN) + RING_MARGIN
	if sd >= edge:
		return Vector3.ZERO
	var away := side / sd if sd > 0.05 else Vector3(-dir.z, 0.0, dir.x)
	return away * RING_PUSH * (1.0 - sd / edge * (2.0 / 3.0))


## Whether no creature stands within LANE_HALF m of the way along `to` (flat) over its first LANE_LEN m (or up to the
## spot, if nearer).
static func lane_clear(game: Node, me: Vector3, to: Vector3) -> bool:
	var len := to.length()
	if len < 0.05:
		return true
	var fwd := to / len
	var reach := minf(len, LANE_LEN)
	var em = game.enemies
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var d: Vector3 = em.pos[i] - me
		d.y = 0.0
		var along := d.dot(fwd)
		if along < -0.5 or along > reach + LANE_HALF:
			continue
		var across := (d - fwd * along).length()
		if across < LANE_HALF:
			return false
	return true


## The probe's direction this frame, before push normalizes it (what it saw is kept in seen_nearest, the nearest
## creature's distance, and seen_danger, the big ones' and rockets' push).
func kite_dir(game: Node, dt: float, t: float) -> Vector3:
	var p: Node3D = game.player
	var em = game.enemies
	var me: Vector3 = p.global_position
	var away := Vector3.ZERO
	var nearest := INF
	var toward := Vector3.ZERO
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var d: Vector3 = me - em.pos[i]
		d.y = 0.0
		var l2 := d.length_squared()
		if l2 < nearest:
			nearest = l2
			toward = -d
		if l2 > 100.0 or l2 < 0.0001:
			continue
		away += d / l2
	nearest = sqrt(nearest) if nearest < INF else INF
	var danger := _react(danger_push(game, me), dt)
	away += danger
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = rng.randf_range(3.0, 7.0)
		strafe = -strafe
	var dir := Vector3.ZERO
	if away.length() > 0.0001:
		var a := away.normalized()
		var side := Vector3(-a.z, 0, a.x) * strafe
		if danger.length() > 0.4:
			dir = a + side * 0.25
		elif nearest < flee_d:
			dir = a + side * 0.5
		elif nearest < keep_d:
			dir = side + a * 0.35
		else:
			dir = side - a * 0.4
	elif toward.length() > 0.001:
		dir = toward.normalized()
	else:
		dir = Vector3(sin(t * 0.4), 0, cos(t * 0.4))
	var mb = game.map
	if mb:
		var c: Vector3 = mb.flats_center if mb.get("flats_center") != null else Vector3.ZERO
		var to_c: Vector3 = c - me
		to_c.y = 0.0
		var r: float = mb.arena_radius if mb.get("arena_radius") != null else 60.0
		var k := clampf((to_c.length() - r * 0.45) / (r * 0.4), 0.0, 1.5)
		if to_c.length() > 0.01:
			dir += to_c.normalized() * k * 1.4
	seen_nearest = nearest
	seen_danger = danger.length()
	return dir


## What a player watches for (the probe's): a hammer giant, a charger (the Bull Beetle), an Elite or a boss within 7 m
## pushes away six times as hard as a creature, and a hostile rocket within 10 m sends him straight away from it.
func danger_push(game: Node, me: Vector3) -> Vector3:
	var em = game.enemies
	var danger := Vector3.ZERO
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var def = em.types[em.type_idx[i]]["def"]
		if not (def.id in ["hammer_giant", "bull_beetle"] or def.archetype == "elite" or def.archetype == "boss"):
			continue
		var dd: Vector3 = me - em.pos[i]
		dd.y = 0.0
		var l2 := dd.length_squared()
		if l2 < 49.0 and l2 > 0.0001:
			danger += dd / l2 * 6.0
	var pm = game.projectiles
	if pm:
		for pi in pm.rocket_of.keys():
			var k := int(pi)
			if pm.alive[k] != 1:
				continue
			var dr: Vector3 = me - pm.pos[k]
			dr.y = 0.0
			if dr.length_squared() < 100.0 and dr.length_squared() > 0.0001:
				danger += dr.normalized() * 3.0
	return danger


## The thumb on the stick: `dir` (world, flat) as a drag from the stick's origin (the probe's mapping onto the north-up
## camera: screen up is world -Z).
static func push(inp, dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	inp.wants_move = true
	inp.origin = Vector2(216, 500)
	inp.touch_pos = inp.origin + Vector2(dir.x, dir.z) * 120.0


## The run sim's walk to `goal` (pass 77): straight at it, sidestepping a creature nearer than FLEE and the big ones and
## rockets the probe watches for, the less the nearer the goal is (within COMMIT_NEAR straight in), and round a rock in
## the way. The strafe clock runs on, so the kiting picks up where it left off. Returns the distance to the goal.
func steer_to(game: Node, dt: float, goal: Vector3) -> float:
	var p: Node3D = game.player
	var inp = p.input
	var me: Vector3 = p.global_position
	var to_g: Vector3 = goal - me
	to_g.y = 0.0
	var gd := to_g.length()
	if inp == null or game.paused:
		return gd
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = rng.randf_range(3.0, 7.0)
		strafe = -strafe
	var dir: Vector3 = to_g / gd if gd > 0.01 else Vector3.ZERO
	var commit := clampf((gd - COMMIT_NEAR) / (COMMIT_FAR - COMMIT_NEAR), 0.0, 1.0)
	seen_ring = Vector3.ZERO
	if commit > 0.0:
		var em = game.enemies
		var away := Vector3.ZERO
		var nearest := INF
		for i in range(em.MAX):
			if em.alive[i] != 1:
				continue
			var d: Vector3 = me - em.pos[i]
			d.y = 0.0
			var l2 := d.length_squared()
			nearest = minf(nearest, l2)
			if l2 > 100.0 or l2 < 0.0001:
				continue
			away += d / l2
		if nearest < flee_d * flee_d and away.length() > 0.0001:
			dir += away.normalized() * GOAL_FLEE * commit
		var danger := _react(danger_push(game, me), dt)
		if danger.length() > 0.4:
			dir += danger.normalized() * GOAL_DANGER * commit
		dir += _round_rocks(game, me, to_g / maxf(gd, 0.01), gd)
		seen_ring = ring_push(game, me, reaction, dodge, dodge_seed)
		dir += seen_ring * commit
	push(inp, dir)
	return gd


## A rock (the map's obstacle circles, Vector3(x, z, r)) in the way to the goal: a push along its edge, on the side the
## goal lies, while he is within its radius plus OBSTACLE_REACH and it is ahead of him and nearer than the goal.
static func _round_rocks(game: Node, me: Vector3, fwd: Vector3, gd: float) -> Vector3:
	var mb = game.map
	if mb == null or mb.get("obstacles") == null:
		return Vector3.ZERO
	var out := Vector3.ZERO
	for o in mb.obstacles:
		var ov: Vector3 = o
		var to_o := Vector3(ov.x - me.x, 0.0, ov.y - me.z)
		var dist := to_o.length()
		if dist < 0.01 or dist > ov.z + OBSTACLE_REACH or dist - ov.z > gd:
			continue
		var ahead := to_o.dot(fwd) / dist
		if ahead < 0.3:
			continue
		# the side of the rock the goal lies on: turn that way along its edge
		var side := Vector3(-to_o.z, 0.0, to_o.x) / dist
		if side.dot(fwd) < 0.0:
			side = -side
		var near := clampf(1.0 - (dist - ov.z) / OBSTACLE_REACH, 0.0, 1.0)
		out += side * ahead * near * 1.2
	return out
