## Pass 128 (lane BLOB; Garry: creatures chasing a faster outlaw "form one big trailing blob"): a regular creature that
## has been far from the outlaw long enough sinks into the ground and comes up where the ring round him has the fewest
## creatures. The map's `timeline_data.relocate` as the director hands it (WaveTimeline.relocate_cfg -> EnemyManager.
## set_relocate -> configure): {enabled, distance, seconds, every, ring [near, far], sectors, sink, scan, squads}.
##
## The rule, every number the map's:
##   - WHO (eligible): a creature the despawn rule may ever take (EnemyManager.despawn_kind: never the boss, an Elite by
##     its kind or its modifier, a coloured special, a special type with the gear badge, a training dummy, a boss's or a
##     caster's summon while a boss lives, one held, roped, in the air, rising, sinking or dying) that walks (STATE_MOVE:
##     never in the middle of an attack), is not buried, and may relocate: its row's say (EnemyManager.reloc_may, set
##     from row_relocate at its spawn: MAY_OFF, MAY_ON), else the default (MAY_DEFAULT): yes, but a squad creature (the
##     Monk) only while `squads` is true. Nothing at all while a boss barrier stands or the crowd is frozen.
##   - FAR TIME: every `scan` s (scan_crowd) a creature that may relocate and stands within `distance` m (flat) of the
##     outlaw has its far time set to 0; an eligible one beyond it gets `scan` more. At `seconds` it joins the queue
##     (first in, first out; within one scan in index order).
##   - THE QUEUE: every `every` s (hand_over) the first creature in the queue that is still alive, still eligible and
##     still beyond `distance` goes; the others before it are dropped (one still far joins again at the next scan).
##   - THE MOVE: it stands and sinks over `sink` s (the spawn rise played backwards: rise_v < 0, a puff of dust when the
##     spot is on the screen), is placed the tick it is under (place), and rises with the map's spawn rise. A flyer
##     (EnemyDef.flies: no ground to sink into) is moved at once, and only while it is off the screen. It keeps its HP,
##     its statuses and its numbers; its velocity, its knockback and its far time are set to 0.
##   - WHERE (pick_spot): the ring round the outlaw is cut into `sectors` equal sectors; every alive, unburied creature
##     within ring[far] + COUNT_PAD m of him counts in its sector (one placed a moment ago stands there already, so it
##     counts); the emptiest sector wins, ties by the lane's own dice; the point is that sector's middle with a jitter
##     inside the sector, `ring` [near, far] m from him, and it must lie inside the arena and clear of every rock's
##     painting and of the water (EnemyManager.spawn_clear, a ring spawn's rule); TRIES dice tries a sector, then the
##     next emptiest; when no sector has a clear point, the emptiest one's middle turned inside the arena.
##   - NOT A SPAWN: no cap, no count, no XP, no kill, no analytics; the creature is the same creature.
## Deterministic (replays): its own dice (Dice.rng_for), clocks counted in physics ticks, the crowd read in index order.
## The compiled crowd needs nothing: it hands every creature that is not walking, is buried, rising or sinking back to
## the script (crowd_core.cpp advance), and this runs before the tick's grid is built.
class_name CrowdRelocate
extends RefCounted

## EnemyManager.reloc_may: the row said no, the row said yes, the row said nothing.
const MAY_OFF := 0
const MAY_ON := 1
const MAY_DEFAULT := 2
## How far past the ring's outer edge (m) a creature still counts in its sector.
const COUNT_PAD := 6.0
## Dice tries for a clear point in one sector before the next emptiest is tried.
const TRIES := 3
## The share of a sector's width the angle's jitter spans (under 1: the point stays inside its sector).
const JITTER := 0.9

var em: EnemyManager
var on := false
var distance := 16.0
var seconds := 5.0
var every := 0.4
var ring_near := 19.0
var ring_far := 24.0
var sectors := 12
var sink := 0.35
var scan := 0.5
var squads := false

## The queue, first in first out: Vector2i(creature, its serial).
var queue: Array = []
## The creatures sinking now (placed the tick they are under): Vector2i(creature, its serial).
var moving: Array = []
## Tests, probes: how many were placed (and per creature id), how many joined the queue, started to sink, were dropped
## from the queue, and the last placement {i, id, from, to, sector, counts}.
var relocated := 0
var relocated_by: Dictionary = {}
var queued_total := 0
var sunk := 0
var dropped := 0
var last: Dictionary = {}
var _scan_left := 0
var _every_left := 0
var _rng: RandomNumberGenerator = null


func _init(p_em: EnemyManager = null) -> void:
	em = p_em


## The map's block (WaveTimeline.relocate_cfg); {} or enabled false = off (one already sinking still comes up).
func configure(cfg: Dictionary) -> void:
	on = cfg != null and bool(cfg.get("enabled", false))
	if not on:
		return
	var d: Dictionary = WaveTimeline.RELOCATE_DEFAULTS
	distance = maxf(float(cfg.get("distance", d["distance"])), 0.0)
	seconds = maxf(float(cfg.get("seconds", d["seconds"])), 0.0)
	every = maxf(float(cfg.get("every", d["every"])), 0.0)
	sink = maxf(float(cfg.get("sink", d["sink"])), 0.0)
	scan = maxf(float(cfg.get("scan", d["scan"])), 0.0)
	sectors = maxi(int(cfg.get("sectors", d["sectors"])), 1)
	squads = bool(cfg.get("squads", d["squads"]))
	var rg = cfg.get("ring", d["ring"])
	var lo := float(d["ring"][0])
	var hi := float(d["ring"][1])
	if rg is Array and (rg as Array).size() >= 1:
		lo = float((rg as Array)[0])
		hi = float((rg as Array)[(rg as Array).size() - 1])
	elif rg is float or rg is int:
		lo = float(rg)
		hi = lo
	ring_near = maxf(minf(lo, hi), 0.0)
	ring_far = maxf(maxf(lo, hi), 0.0)


## The lane's own dice, seeded from the run's seed the first time they are rolled (Dice.rng_for).
func dice() -> RandomNumberGenerator:
	if _rng == null:
		_rng = Dice.rng_for("crowd_relocate")
	return _rng


## One physics tick (EnemyManager._physics_process, with the raw delta, before the grid): the ones under are placed,
## then the two clocks, counted in ticks.
func tick(delta: float, ppos: Vector3) -> void:
	if not moving.is_empty():
		settle(ppos)
	if not on or em.crowd_freeze != 0:
		return
	var step := maxf(delta, 0.001)
	_scan_left -= 1
	if _scan_left <= 0:
		_scan_left = maxi(roundi(scan / step), 1)
		if not barrier_stands():
			scan_crowd(ppos)
	_every_left -= 1
	if _every_left <= 0:
		_every_left = maxi(roundi(every / step), 1)
		if not queue.is_empty() and not barrier_stands():
			hand_over(ppos)


## Whether a boss's barrier stands now (BossPatterns.standing_wall): nothing relocates while it does.
func barrier_stands() -> bool:
	return em.patterns != null and not em.patterns.standing_wall().is_empty()


## Whether creature `i` may relocate at all: its row's say, else the default (a squad creature only with `squads`).
func may(i: int) -> bool:
	if i < 0 or i >= em.reloc_may.size():
		return false
	var m := em.reloc_may[i]
	if m == MAY_DEFAULT:
		return squads or em._t_squad[em.type_idx[i]] == 0
	return m == MAY_ON


## Whether creature `i` could be taken now, whatever its distance and far time (WHO, above).
func eligible(i: int) -> bool:
	if not em.despawn_kind(i) or em.hidden[i] == 1 or em.state[i] != EnemyManager.STATE_MOVE:
		return false
	return may(i)


## One scan of the crowd, the outlaw at `ppos`: the far times, and the ones that reached `seconds` join the queue. How
## many joined.
func scan_crowd(ppos: Vector3) -> int:
	if em.reloc_may.size() != em.pool_max:
		return 0
	var d2 := distance * distance
	var joined := 0
	for i in range(em.pool_max):
		if em.alive[i] == 0 or not may(i):
			continue
		var p: Vector3 = em.pos[i]
		var dx := p.x - ppos.x
		var dz := p.z - ppos.z
		if dx * dx + dz * dz <= d2:
			em.reloc_far[i] = 0.0
			continue
		if not eligible(i):
			continue
		em.reloc_far[i] += scan
		if em.reloc_far[i] >= seconds and em.reloc_queued[i] == 0:
			em.reloc_queued[i] = 1
			queue.append(Vector2i(i, em.serial[i]))
			queued_total += 1
			joined += 1
	return joined


## The queue's turn: its first creature that is still alive, still eligible and still beyond `distance` goes (it starts
## to sink, or is placed at once with a sink of 0 or as a flyer); the others before it are dropped. The creature, or -1.
func hand_over(ppos: Vector3) -> int:
	var d2 := distance * distance
	while not queue.is_empty():
		var q: Vector2i = queue.pop_front()
		var i := q.x
		if i < 0 or i >= em.pool_max or em.alive[i] == 0 or em.serial[i] != q.y:
			dropped += 1
			continue
		em.reloc_queued[i] = 0
		var p: Vector3 = em.pos[i]
		var dx := p.x - ppos.x
		var dz := p.z - ppos.z
		if dx * dx + dz * dz <= d2 or not eligible(i):
			dropped += 1
			continue
		var flyer: bool = (em.types[em.type_idx[i]]["def"] as EnemyDef).flies
		if flyer and em.onscreen.size() == em.pool_max and em.onscreen[i] == 1:
			# a flyer has no ground to sink into: it goes only while nobody sees it
			dropped += 1
			continue
		em.vel[i] = Vector3.ZERO
		em.kb[i] = Vector3.ZERO
		em.reloc_far[i] = 0.0
		if flyer or sink <= 0.0:
			place(i, ppos)
			return i
		# the spawn rise played backwards: it stands (the spawn state bites nobody and starts nothing) and sinks
		em.state[i] = EnemyManager.STATE_SPAWN
		em.timer[i] = sink / maxf(em.pace, 0.05) + 1.0
		em.rise_t[i] = minf(em.rise_t[i], 0.999)
		em.rise_v[i] = -1.0 / sink
		moving.append(Vector2i(i, em.serial[i]))
		sunk += 1
		_dust(i)
		return i
	return -1


## The sinking ones: one that is under (or whose sink something else ended) is placed; one that died or went is forgotten.
func settle(ppos: Vector3) -> void:
	var k := 0
	while k < moving.size():
		var m: Vector2i = moving[k]
		var i := m.x
		if i < 0 or i >= em.pool_max or em.alive[i] == 0 or em.serial[i] != m.y or em.state[i] == EnemyManager.STATE_DYING:
			moving.remove_at(k)
			continue
		if em.hidden[i] == 1 or em.rise_v[i] >= 0.0:
			moving.remove_at(k)
			place(i, ppos)
			continue
		k += 1


## Creature `i` comes up at its new place round the outlaw at `ppos` (pick_spot): rising as a spawn does (at once
## without the map's spawn rise, and for a flyer).
func place(i: int, ppos: Vector3) -> void:
	var def: EnemyDef = em.types[em.type_idx[i]]["def"]
	var from: Vector3 = em.pos[i]
	var spot := pick_spot(ppos, i)
	em.pos[i] = Vector3(spot.x, em._height(spot.x, spot.z), spot.z)
	em.vel[i] = Vector3.ZERO
	em.kb[i] = Vector3.ZERO
	em.hidden[i] = 0
	em.reloc_far[i] = 0.0
	# drawn and on the screen until the next check says otherwise, as a fresh spawn is
	if em.onscreen.size() == em.pool_max:
		em.onscreen[i] = 1
	em._vis_spawn(i)
	var secs: float = em.spawn_rise_s
	if def.flies or secs <= 0.0:
		em.rise_t[i] = 1.0
		em.rise_v[i] = 0.0
		em.state[i] = EnemyManager.STATE_MOVE
		em.timer[i] = 0.0
	else:
		em.rise_t[i] = 0.0
		em.rise_v[i] = 1.0 / secs
		em.squash[i] = EnemyManager.EMERGE_STRETCH
		em.state[i] = EnemyManager.STATE_SPAWN
		em.timer[i] = secs / maxf(em.pace, 0.05) + 0.02
		_dust(i)
	relocated += 1
	relocated_by[def.id] = int(relocated_by.get(def.id, 0)) + 1
	last["i"] = i
	last["id"] = def.id
	last["from"] = from
	last["to"] = em.pos[i]


## A puff of dust at creature `i`'s feet (a spawn's own, Fx.emerge_dust), only where the spot is on the screen.
func _dust(i: int) -> void:
	if em.spawn_rise_dust <= 0.0 or em.game == null or not em._point_on_screen(em.pos[i]):
		return
	var fx = em.game.get("fx")
	if fx != null and fx.has_method("emerge_dust"):
		fx.emerge_dust(em.pos[i], em.size[i] * em.spawn_rise_dust, false)


## Which sector the offset (dx, dz) from the outlaw lies in: 0 starts at +X and they run towards +Z.
func sector_of(dx: float, dz: float) -> int:
	return clampi(int(fposmod(atan2(dz, dx), TAU) / (TAU / float(sectors))), 0, sectors - 1)


## How many alive, unburied creatures stand in each sector within ring[far] + COUNT_PAD m of the outlaw at `ppos`
## (`skip`: the one being placed).
func sector_counts(ppos: Vector3, skip: int = -1) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(sectors)
	var reach := ring_far + COUNT_PAD
	var r2 := reach * reach
	for j in range(em.pool_max):
		if em.alive[j] == 0 or j == skip or em.hidden[j] == 1 or em.state[j] == EnemyManager.STATE_DYING:
			continue
		var p: Vector3 = em.pos[j]
		var dx := p.x - ppos.x
		var dz := p.z - ppos.z
		var dd := dx * dx + dz * dz
		if dd > r2 or dd < 0.0001:
			continue
		counts[sector_of(dx, dz)] += 1
	return counts


## The sectors from the emptiest to the fullest, ties in the order the lane's dice shuffled them.
func sector_order(counts: PackedInt32Array) -> PackedInt32Array:
	var order := PackedInt32Array()
	order.resize(sectors)
	for s in range(sectors):
		order[s] = s
	var rng := dice()
	for a in range(sectors - 1, 0, -1):
		var b := rng.randi() % (a + 1)
		var t := order[a]
		order[a] = order[b]
		order[b] = t
	# a stable insertion sort by the count keeps the shuffle among equals
	for a in range(1, sectors):
		var s := order[a]
		var b := a - 1
		while b >= 0 and counts[order[b]] > counts[s]:
			order[b + 1] = order[b]
			b -= 1
		order[b + 1] = s
	return order


## The point a creature comes up at, the outlaw at `ppos` (WHERE, above); `skip` is the creature itself.
func pick_spot(ppos: Vector3, skip: int = -1) -> Vector3:
	var counts := sector_counts(ppos, skip)
	var order := sector_order(counts)
	var w := TAU / float(sectors)
	var lim := em.arena_radius - 2.0
	var map = em.game.get("map") if em.game != null else null
	var rng := dice()
	last["counts"] = counts
	for s in order:
		for _t in range(TRIES):
			var a := (float(s) + 0.5) * w + (rng.randf() - 0.5) * w * JITTER
			var r := rng.randf_range(ring_near, ring_far)
			var p := Vector3(ppos.x + cos(a) * r, ppos.y, ppos.z + sin(a) * r)
			if Vector2(p.x, p.z).length() <= lim and EnemyManager.spawn_clear(map if map is Node else null, p):
				last["sector"] = s
				return p
	# no sector has a clear point: the emptiest one's middle, turned inside the arena (EnemyManager.point_inside's yaw:
	# 0 = -Z, so the angle t on the ring is the yaw -t - PI / 2)
	var s0 := order[0]
	last["sector"] = s0
	var a0 := (float(s0) + 0.5) * w
	return em._clamp_arena(EnemyManager.point_inside(ppos, -a0 - PI * 0.5, (ring_near + ring_far) * 0.5, lim))
