## The ring breakout (pass 90, lane BOT; Garry: the bot "has a nasty habit of getting overwhelmed with enemies if they
## spawn in a `ring` around him... Maybe he somehow detects that he is surrounded and then just tries to push through in a
## specific direction, taking damage on the way, but managing to push through and escape in the end"). The kite pushes
## away from every creature at once; inside a closing ring those pushes cancel and he strafes on the spot until the ring
## is on him. Two things set a push off (Bot.gd's option `breakout`; numbers measured with the run sim, tools/dl/p90/
## balancing_BOT.md):
##  1. A ring has just come up round him (fresh_ring: the map's ring rows and swarms put a whole pack evenly round the hero
##     at once, at one distance): at least RING_N_MIN creatures first seen in the same moment, within RING_BAND m of one
##     distance, evenly round him (no gap past RING_EVEN_K x the even spacing, RING_GAP_MIN_DEG at least, RING_GAP_MAX_DEG
##     at most; a gap the arena's wall closes is none). He leaves before it closes, through its thinnest side.
##  2. Late: he is shut in (coverage): every creature within RING_R m shuts the ways out past it (the directions where
##     walking would bring him within its bite: its radius + PASS_PAD of its middle), counted over SECTORS directions round
##     him (an open slit narrower than SLIT_DEG counts as shut: no one threads it at a run). Shut in = at least N_MIN
##     creatures there, COVER_MIN of the ways shut, no open gap wider than GAP_MAX_DEG (a gap he can walk through is the
##     kite's), and open ground past the wall he would cross (BEYOND_OPEN: a crowd that fills the screen is the kite's).
## The way (choose_way, over WAYS directions): the thinnest wall, its cost the bites waiting along a lane as wide as a
## bite (each creature within its radius + LANE_PAD of the line, over WALL_LEN m or, for a fresh ring, RING_WALL_PAST m past
## its radius: its weight, its bite against the crowd's mean, an Elite or a boss BIG_W more, times the metres he would walk
## that close to it), plus BEYOND_K of the crowd in the lane past the wall (BEYOND_LEN m: where he lands), the arena's
## edge (EDGE_K a metre past the clamp's ring less EDGE_ROOM) and rocks in the way (ROCK_K), less a lean towards his goal
## (GOAL_K) or, with none, towards the arena's middle (CENTER_K, by how far out he stands).
## The commitment: full stick that way, the kite's push off (the bites taken), only a rock's edge and a red warning nudging
## him (Bot.gd), until he is out by a margin: a fresh ring once none of it has stood ahead of him on his line (AHEAD_HALF m
## either side) for CLEAR_T s; shut in, once he has gone the wall's far edge + CLEAR_MARGIN m; never less than MIN_S s
## (and NEED_MIN m), never more than MAX_S s. No turning back half way (no dithering). Then a cooldown of COOLDOWN_S s.
## Pure maths and a small state: no game class or autoload is named here (tools compile before autoloads); the bodies
## are Vector4(x, z, radius, weight) relative to the hero, x east, z south (the world's), read off the crowd by bodies_of
## with their keys (slot:serial) so who is new is remembered from read to read.
extends RefCounted

const SECTORS := 72
## the crowd read round him (bodies_of); the late breakout's coverage (shut in)
const SCAN_R := 26.0
const RING_R := 9.0
const PASS_PAD := 0.5
const COVER_MIN := 0.9
const SLIT_DEG := 15.0
const GAP_MAX_DEG := 25.0
const N_MIN := 12
## the ways weighed (choose_way)
const WAYS := 32
const LANE_PAD := 0.75
const CHORD_MIN := 0.5
const WALL_LEN := 13.0
const BEYOND_LEN := 10.0
const BEYOND_K := 0.5
const BEYOND_OPEN := 3.0
const BIG_W := 2.0
const W_MIN := 0.5
const W_MAX := 3.0
const EDGE_ROOM := 6.0
const EDGE_K := 1.5
const ROCK_K := 3.0
const ROCK_LOOK := 8.0
const GOAL_K := 1.0
const CENTER_K := 1.5
## the commitment
const CLEAR_MARGIN := 2.5
const NEED_MIN := 4.0
const MIN_S := 0.6
const MAX_S := 3.0
const COOLDOWN_S := 5.0

## a fresh ring (fresh_ring): creatures first seen within FRESH_S s, FRESH_MIN_D..FRESH_MAX_D m off when first seen, at
## one distance (RING_BAND), at least RING_N_MIN evenly round him (RING_EVEN_K, RING_GAP_MIN_DEG, RING_GAP_MAX_DEG; a gap
## whose middle stands within WALL_CLOSE m of the arena's edge is closed); its wall counted RING_WALL_PAST m past its
## radius; reads more than FRESH_GAP_S apart start the memory afresh; a ring crossed is behind him once none of it has
## stood ahead of him within AHEAD_HALF m of his line for CLEAR_T s
const FRESH_S := 0.25
const FRESH_MIN_D := 6.0
const FRESH_MAX_D := 24.0
const RING_N_MIN := 12
const RING_BAND := 1.5
const RING_EVEN_K := 2.5
const RING_GAP_MIN_DEG := 70.0
const RING_GAP_MAX_DEG := 100.0
const WALL_CLOSE := 4.0
const RING_WALL_PAST := 3.0
const FRESH_GAP_S := 0.5
const AHEAD_HALF := 2.5
const CLEAR_T := 0.4
## the late breakout (the crowd shut round him, coverage): on or off
const LATE_ON := true

## the push under way: "ring" (a fresh ring) or "surrounded" (the crowd shut round him), the ring's keys being crossed
var active := false
var kind := ""
var members: Dictionary = {}
var dir := Vector3.ZERO
var t := 0.0
var cooldown := 0.0
var start := Vector3.ZERO
var need := 0.0
## what he saw when it started (a fresh ring {n, gap_deg, r}; shut in: coverage() {n, cover, gap_deg, gap_at}), the way he
## chose (choose_way) and how the last one ended ({why, t, metres, kind}); Bot.gd logs them
var seen: Dictionary = {}
var choice: Dictionary = {}
var ended: Dictionary = {}
## tallies (the run sim's meta.bot.breakout): pushes started, ended out by the margin, ended by the clock, started by a
## fresh ring
var started_n := 0
var out_n := 0
var timeout_n := 0
var rings_n := 0
## the memory of who is new (observe): key -> Vector2(first seen on the push clock, metres off then); the clock and the
## last read's time on it
var _first: Dictionary = {}
var _clock := 0.0
var _last_obs := -1.0
## a fresh ring's crossing: seconds none of it has stood ahead of him; the time since the last read, and between the last two
var _clear_t := 0.0
var _read_dt := 0.0
var _read_dt_last := 0.0
## the late breakout on (LATE_ON; a test may turn it off)
var late_on := LATE_ON
## "started" / "ended" on the frame a push starts or ends (update), else ""
var last_event := ""


## The crowd round `me` as bodies (Vector4: x, z relative, radius, bite weight), every creature alive, not dying, not
## buried, within SCAN_R m. Its weight: its bite (dmg) over the crowd's mean, in [W_MIN, W_MAX], an Elite or a boss
## BIG_W times more. A crowd without the arrays a field lacks counts radius 0.5 and weight 1.
static func bodies_of(em, me: Vector3, reach: float = SCAN_R, keys = null) -> Array:
	var out: Array = []
	if em == null:
		return out
	var alive = em.get("alive")
	var pos = em.get("pos")
	if not (alive is PackedByteArray) or not (pos is PackedVector3Array):
		return out
	var state = em.get("state")
	var hidden = em.get("hidden")
	var rad = em.get("radius")
	var dmg = em.get("dmg")
	var types = em.get("types")
	var tix = em.get("type_idx")
	var serial = em.get("serial")
	var dying := int(em.get("STATE_DYING")) if em.get("STATE_DYING") != null else 3
	var bi := int(em.get("boss_index")) if em.get("boss_index") != null else -1
	var r2 := reach * reach
	var raw: Array = []
	var sum := 0.0
	var n := mini((alive as PackedByteArray).size(), (pos as PackedVector3Array).size())
	for i in range(n):
		if alive[i] != 1:
			continue
		if state is PackedInt32Array and i < (state as PackedInt32Array).size() and int(state[i]) == dying:
			continue
		if hidden is PackedByteArray and i < (hidden as PackedByteArray).size() and hidden[i] == 1:
			continue
		var p: Vector3 = pos[i]
		var dx := p.x - me.x
		var dz := p.z - me.z
		if dx * dx + dz * dz > r2:
			continue
		var r := float(rad[i]) if rad is PackedFloat32Array and i < (rad as PackedFloat32Array).size() else 0.5
		var bite := float(dmg[i]) if dmg is PackedFloat32Array and i < (dmg as PackedFloat32Array).size() else 1.0
		var big := i == bi
		if not big and types is Array and tix is PackedInt32Array and i < (tix as PackedInt32Array).size():
			var ti := int(tix[i])
			if ti >= 0 and ti < (types as Array).size():
				var def = (types[ti] as Dictionary).get("def")
				if def != null and def.get("archetype") != null and str(def.archetype) in ["elite", "boss"]:
					big = true
		raw.append([dx, dz, r, maxf(bite, 0.0), big])
		sum += maxf(bite, 0.0)
		if keys is Array:
			(keys as Array).append("%d:%d" % [i, int(serial[i]) if serial is PackedInt32Array and i < (serial as PackedInt32Array).size() else 0])
	var mean := sum / float(raw.size()) if raw.size() > 0 else 1.0
	for b in raw:
		var w := clampf(float(b[3]) / mean, W_MIN, W_MAX) if mean > 0.0 else 1.0
		if bool(b[4]):
			w *= BIG_W
		out.append(Vector4(float(b[0]), float(b[1]), float(b[2]), w))
	return out


## A direction on the sand as degrees from north (screen up, world -Z), clockwise (90 east).
static func deg_of(v: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)


## The unit flat direction `deg` degrees from north.
static func way_of(deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a), 0.0, -cos(a))


## The compass word for a direction in degrees (north, north-east, ...).
static func compass(deg: float) -> String:
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(fposmod(deg, 360.0) / 45.0)) % 8]


## The ways shut round him by `bodies` within `r_max` m: {n (creatures counted), cover (the share of SECTORS shut),
## gap_deg (the widest run of open directions), gap_at (its middle, degrees)}.
static func coverage(bodies: Array, r_max: float = RING_R) -> Dictionary:
	var shut := PackedByteArray()
	shut.resize(SECTORS)
	shut.fill(0)
	var step := 360.0 / float(SECTORS)
	var n := 0
	for b: Vector4 in bodies:
		var d := Vector2(b.x, b.y).length()
		if d > r_max:
			continue
		n += 1
		var reach := b.z + PASS_PAD
		var half := 90.0 if d <= reach else rad_to_deg(asin(clampf(reach / d, 0.0, 1.0)))
		var at := deg_of(Vector3(b.x, 0.0, b.y))
		var k0 := int(floor((at - half) / step))
		var k1 := int(ceil((at + half) / step))
		for k in range(k0, k1 + 1):
			var mid := (float(k) + 0.5) * step
			if absf(angle_difference(deg_to_rad(mid), deg_to_rad(at))) <= deg_to_rad(half):
				shut[posmod(k, SECTORS)] = 1
	var count := 0
	for k in range(SECTORS):
		count += shut[k]
	if count == 0:
		return {"n": n, "cover": 0.0, "gap_deg": 360.0, "gap_at": 0.0}
	# the open runs round the circle, from a shut sector: the widest is the gap; one narrower than SLIT_DEG is no way out
	# (a slit between two bites he cannot thread at a run) and counts as shut
	var s0 := 0
	while shut[s0] == 0:
		s0 += 1
	var best := 0
	var best_end := s0
	var run := 0
	var slits := 0
	for j in range(1, SECTORS + 1):
		var k := (s0 + j) % SECTORS
		if shut[k] == 0:
			run += 1
			continue
		if run > 0:
			if run > best:
				best = run
				best_end = s0 + j - 1
			if float(run) * step < SLIT_DEG:
				slits += run
		run = 0
	var gap_at := fposmod((float(best_end - best + 1) + float(best) * 0.5) * step, 360.0) if best > 0 else 0.0
	return {"n": n, "cover": float(count + slits) / float(SECTORS), "gap_deg": float(best) * step, "gap_at": gap_at}


## Whether a coverage (coverage()) says he is surrounded: N_MIN creatures, COVER_MIN of the ways shut, no gap past
## GAP_MAX_DEG.
static func surrounded(cov: Dictionary) -> bool:
	return int(cov.get("n", 0)) >= N_MIN and float(cov.get("cover", 0.0)) >= COVER_MIN and float(cov.get("gap_deg", 360.0)) <= GAP_MAX_DEG


## The wall along `way` (unit, flat): Vector3(cost, count, far edge). Every creature within its radius + LANE_PAD (its
## bite, 0.45 m past its radius, and some slack: it moves) of the line over `wall_len` m is in the way; its cost is its
## weight x the metres he would walk that close to it (the chord of the line through that circle, at least CHORD_MIN: a
## big one is a thick wall, one grazed a thin one); far edge: the farthest such creature's far side along the way (m).
static func wall_of(bodies: Array, way: Vector3, wall_len: float = WALL_LEN) -> Vector3:
	var cost := 0.0
	var n := 0
	var far := 0.0
	for b: Vector4 in bodies:
		var along := b.x * way.x + b.y * way.z
		if along < -0.5 or along > wall_len:
			continue
		var across := absf(b.x * way.z - b.y * way.x)
		if across < b.z + LANE_PAD:
			var reach := b.z + LANE_PAD
			cost += b.w * maxf(2.0 * sqrt(maxf(reach * reach - across * across, 0.0)), CHORD_MIN)
			n += 1
			far = maxf(far, along + b.z)
	return Vector3(cost, float(n), far)


## The crowd past the wall along `way`: the bite weights in a lane twice as wide from WALL_LEN to WALL_LEN + BEYOND_LEN m.
static func beyond_of(bodies: Array, way: Vector3, wall_len: float = WALL_LEN) -> float:
	var cost := 0.0
	for b: Vector4 in bodies:
		var along := b.x * way.x + b.y * way.z
		if along <= wall_len or along > wall_len + BEYOND_LEN:
			continue
		if absf(b.x * way.z - b.y * way.x) < b.z + LANE_PAD * 2.0:
			cost += b.w
	return cost


## The arena's edge along `way` from `me` (the hero is clamped to arena_r - 1.5 round the world's origin, MapBase
## .clamp_to_arena): EDGE_K a metre that the spots at 8 and 16 m stand past arena_r - EDGE_ROOM.
static func edge_of(me: Vector3, way: Vector3, arena_r: float) -> float:
	var pen := 0.0
	for k: float in [8.0, 16.0]:
		var p := me + way * k
		pen += maxf(Vector2(p.x, p.z).length() - (arena_r - EDGE_ROOM), 0.0)
	return pen * EDGE_K


## A rock (the map's obstacle circles, Vector3(x, z, r)) within ROCK_LOOK m along `way`: ROCK_K a rock the walk would
## touch (within its radius + 0.6 of the line).
static func rocks_of(me: Vector3, way: Vector3, obstacles: Array) -> float:
	var pen := 0.0
	for o in obstacles:
		if not (o is Vector3):
			continue
		var ov: Vector3 = o
		var rel := Vector3(ov.x - me.x, 0.0, ov.y - me.z)
		var along := rel.dot(way)
		if along < 0.0 or along > ROCK_LOOK + ov.z:
			continue
		var across := (rel - way * along).length()
		if across < ov.z + 0.6:
			pen += ROCK_K
	return pen


## The way out (see the file's head): every one of WAYS directions scored, the cheapest taken. `lean` the flat unit
## direction of his goal (ZERO for none); `wall_len` how far the wall is counted (a fresh ring: past its radius).
## {deg, dir, score, cost, thick, far, beyond, edge, rock, rows: the best three as decision rows [{id, name, score,
## parts}]}.
static func choose_way(bodies: Array, me: Vector3, arena_r: float, obstacles: Array, lean: Vector3, wall_len: float = WALL_LEN) -> Dictionary:
	var to_mid := Vector3(-me.x, 0.0, -me.z)
	var out_share := clampf(to_mid.length() / maxf(arena_r, 1.0), 0.0, 1.0)
	var mid_dir := to_mid.normalized() if to_mid.length() > 0.5 else Vector3.ZERO
	var all: Array = []
	for k in range(WAYS):
		var deg := 360.0 * float(k) / float(WAYS)
		var way := way_of(deg)
		var wall := wall_of(bodies, way, wall_len)
		var bey := beyond_of(bodies, way, wall_len)
		var edge := edge_of(me, way, arena_r)
		var rock := rocks_of(me, way, obstacles)
		var pull := 0.0
		if lean != Vector3.ZERO:
			pull = GOAL_K * way.dot(lean)
		elif mid_dir != Vector3.ZERO:
			pull = CENTER_K * out_share * way.dot(mid_dir)
		var score := wall.x + BEYOND_K * bey + edge + rock - pull
		all.append({"deg": deg, "dir": way, "score": score, "cost": wall.x, "thick": int(wall.y), "far": wall.z, "beyond": bey,
			"edge": edge, "rock": rock, "pull": pull})
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) < float(b["score"]))
	var best: Dictionary = all[0].duplicate()
	var rows: Array = []
	for i in range(mini(3, all.size())):
		var c: Dictionary = all[i]
		rows.append({"id": "way:%d" % roundi(float(c["deg"])), "name": compass(float(c["deg"])), "score": snappedf(-float(c["score"]), 0.1),
			"parts": {"wall": int(c["thick"]), "bites": snappedf(float(c["cost"]), 0.1), "beyond": snappedf(float(c["beyond"]), 0.1),
				"edge": snappedf(float(c["edge"]), 0.1), "rock": snappedf(float(c["rock"]), 0.1), "lean": snappedf(float(c["pull"]), 0.1)}})
	best["rows"] = rows
	return best


## What he remembers of the crowd from read to read (`keys`, one a body: the creature's slot and serial, bodies_of): when
## and how far off he first saw each. A read more than FRESH_GAP_S after the last one starts afresh (nobody is new then:
## the first read of a run, or after a pause in the reading, sees the crowd that was already there).
func observe(bodies: Array, keys: Array) -> void:
	var cont := _clock - _last_obs <= FRESH_GAP_S and _last_obs >= 0.0
	var nf := {}
	for j in range(mini(bodies.size(), keys.size())):
		var key := str(keys[j])
		if _first.has(key):
			nf[key] = _first[key]
		else:
			var b: Vector4 = bodies[j]
			nf[key] = Vector2(_clock if cont else -1000.0, Vector2(b.x, b.y).length())
	_first = nf
	_last_obs = _clock


## A ring that has just come up round him (the map's ring rows and swarms put a whole pack evenly round the hero at
## once, every one at the ring's radius give or take a little): of the creatures first seen in the last FRESH_S s between
## FRESH_MIN_D and FRESH_MAX_D m off, those within RING_BAND m of their middle distance, at least RING_N_MIN of them and
## evenly round him (no gap between two of them wider than RING_EVEN_K x the even spacing, at least RING_GAP_MIN_DEG,
## and never past RING_GAP_MAX_DEG). A burst at the screen's edge is no ring: it comes from a side or two, at many
## distances. A gap the arena's wall closes counts as none (`me` the hero's place, `arena_r` the arena's radius: 0 =
## no wall). {n, gap_deg, r (their mean distance now), keys (theirs), ring (bool)}.
func fresh_ring(bodies: Array, keys: Array, me: Vector3 = Vector3.ZERO, arena_r: float = 0.0) -> Dictionary:
	var ds: Array = []
	var js: Array = []
	for j in range(mini(bodies.size(), keys.size())):
		var f = _first.get(str(keys[j]))
		if not (f is Vector2):
			continue
		var fv: Vector2 = f
		if _clock - fv.x > FRESH_S or fv.y < FRESH_MIN_D or fv.y > FRESH_MAX_D:
			continue
		js.append(j)
		ds.append(fv.y)
	if js.size() < RING_N_MIN:
		return {"n": js.size(), "gap_deg": 360.0, "r": 0.0, "keys": [], "ring": false}
	var sorted_d := ds.duplicate()
	sorted_d.sort()
	var mid := float(sorted_d[sorted_d.size() / 2])
	var angs: Array = []
	var rs := 0.0
	var ks: Array = []
	for m in range(js.size()):
		if absf(float(ds[m]) - mid) > RING_BAND:
			continue
		var b: Vector4 = bodies[int(js[m])]
		angs.append(deg_of(Vector3(b.x, 0.0, b.y)))
		rs += Vector2(b.x, b.y).length()
		ks.append(str(keys[int(js[m])]))
	var n := angs.size()
	if n < 2:
		return {"n": n, "gap_deg": 360.0, "r": 0.0, "keys": ks, "ring": false}
	angs.sort()
	var r_mean := rs / float(n)
	# the gaps between two of them, widest first; a gap the arena's wall closes (its middle, at the ring's distance, past
	# the hero's reach of the wall: the ring's spots there were pressed onto the wall) is no way out
	var gaps: Array = [Vector2(360.0 - float(angs[n - 1]) + float(angs[0]), float(angs[n - 1]))]
	for k in range(1, n):
		gaps.append(Vector2(float(angs[k]) - float(angs[k - 1]), float(angs[k - 1])))
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var gap := 0.0
	for g: Vector2 in gaps:
		var mid_at := me + way_of(g.y + g.x * 0.5) * r_mean
		if arena_r > 0.0 and Vector2(mid_at.x, mid_at.z).length() > arena_r - WALL_CLOSE:
			continue
		gap = g.x
		break
	var allow := minf(maxf(RING_EVEN_K * 360.0 / float(n), RING_GAP_MIN_DEG), RING_GAP_MAX_DEG)
	return {"n": n, "gap_deg": gap, "r": r_mean, "keys": ks, "ring": n >= RING_N_MIN and gap <= allow}


## Whether a ring being crossed still stands in his way: one of `ring` (its keys) ahead of him (along the push) within
## AHEAD_HALF m (+ its radius) of his line.
func ring_ahead(bodies: Array, keys: Array, ring: Dictionary) -> bool:
	for j in range(mini(bodies.size(), keys.size())):
		if not ring.has(str(keys[j])):
			continue
		var b: Vector4 = bodies[j]
		var along := b.x * dir.x + b.y * dir.z
		if along > 0.0 and absf(b.x * dir.z - b.y * dir.x) < AHEAD_HALF + b.z:
			return true
	return false


## One frame (the caller reads the crowd every BREAK_SCAN_EVERY frames and passes the last bodies and their keys): the
## direction to push this frame, Vector3.ZERO when no push is under way. `ctx` {arena_r, obstacles, lean}. A push that
## starts or ends this frame sets `seen`/`choice` (and `kind`: "ring" a fresh ring, "surrounded" the crowd shut round
## him) or `ended`, and says "started"/"ended" in `last_event` for the caller's log. `fresh_read` true when `bodies` is a
## new read (the memory of who is new is kept from reads only).
func update(dt: float, me: Vector3, bodies: Array, ctx: Dictionary, keys: Array = [], fresh_read: bool = true) -> Vector3:
	last_event = ""
	_clock += dt
	_read_dt += dt
	if fresh_read:
		_read_dt_last = _read_dt
		_read_dt = 0.0
	if fresh_read and not keys.is_empty():
		observe(bodies, keys)
	if active:
		t += dt
		var gone := Vector2(me.x - start.x, me.z - start.z).length()
		var out := false
		if kind == "ring":
			# out once none of the ring has stood ahead of him on his line for CLEAR_T s (or he is far enough whatever)
			if fresh_read:
				_clear_t = 0.0 if ring_ahead(bodies, keys, members) else _clear_t + _read_dt_last
			out = t >= MIN_S and gone >= NEED_MIN and (_clear_t >= CLEAR_T or gone >= need)
		else:
			out = t >= MIN_S and gone >= need
		if t >= MAX_S or out:
			var why := "out" if out else "timeout"
			if out:
				out_n += 1
			else:
				timeout_n += 1
			ended = {"why": why, "t": t, "metres": gone, "kind": kind}
			active = false
			members = {}
			cooldown = COOLDOWN_S
			last_event = "ended"
			return Vector3.ZERO
		return dir
	cooldown = maxf(cooldown - dt, 0.0)
	if cooldown > 0.0:
		return Vector3.ZERO
	var arena_r := float(ctx.get("arena_r", 66.0))
	var obstacles: Array = ctx.get("obstacles", []) as Array
	var lean: Vector3 = ctx.get("lean", Vector3.ZERO)
	# a fresh ring: out through it before it closes (the wall counted past its radius)
	if not keys.is_empty():
		var fr := fresh_ring(bodies, keys, me, arena_r)
		if bool(fr["ring"]):
			var c := choose_way(bodies, me, arena_r, obstacles, lean, float(fr["r"]) + RING_WALL_PAST)
			members = {}
			for k in fr["keys"]:
				members[str(k)] = true
			_start("ring", {"n": int(fr["n"]), "gap_deg": float(fr["gap_deg"]), "r": float(fr["r"])}, c, me,
				clampf(float(fr["r"]) + RING_WALL_PAST + CLEAR_MARGIN, NEED_MIN, float(fr["r"]) + RING_WALL_PAST + CLEAR_MARGIN))
			return dir
	if not late_on:
		return Vector3.ZERO
	var cov := coverage(bodies, RING_R)
	if not surrounded(cov):
		return Vector3.ZERO
	var c2 := choose_way(bodies, me, arena_r, obstacles, lean)
	# a ring has open ground past it; a crowd that fills the screen has none (the kite plays that)
	if float(c2["beyond"]) > BEYOND_OPEN:
		return Vector3.ZERO
	members = {}
	_start("surrounded", cov, c2, me, clampf(float(c2["far"]) + CLEAR_MARGIN, NEED_MIN, WALL_LEN + CLEAR_MARGIN))
	return dir


func _start(k: String, what: Dictionary, c: Dictionary, me: Vector3, p_need: float) -> void:
	kind = k
	seen = what
	choice = c
	dir = c["dir"]
	start = me
	need = p_need
	t = 0.0
	_clear_t = 0.0
	active = true
	started_n += 1
	if k == "ring":
		rings_n += 1
	last_event = "started"


## Everything per life cleared (the Watch's revive): no push, no cooldown, nobody new.
func reset() -> void:
	active = false
	dir = Vector3.ZERO
	t = 0.0
	cooldown = 0.0
	members = {}
	_first = {}
	_last_obs = -1.0
	last_event = ""


func tallies() -> Dictionary:
	return {"started": started_n, "rings": rings_n, "out": out_n, "timeout": timeout_n}
