## "Aim where you face" (pass 136; Garry's answers on docs/weapons_aim/weapons_aim.html, 2026-11-08: "R1 - Yes ... R6 - Yes,
## but not in a cone, in a circle. R7 - Yes, this is especially important for Rockets ... R9 - Yes ... Make this Aiming
## version a togglable option in the Debug version of Settings as before. But this time make it the default option").
## The one helper every weapon behaviour asks while the switch is on (Settings.aim_mode: on by default; the developer
## Settings' "Aim where you face" row; prod keeps it on). Replaces pass 95's FireForward for the behaviours that move to it.
##
## The rules (BALANCING 77.AIM):
##   R1 the aim line is the Outlaw's facing (Player.forward(); a stick pushed under 15% turns him without walking).
##   R2/R3 an aimed weapon fires down the facing; inside its cone (`params.aim.cone`, full degrees, default 60) the shot
##      turns towards the best target (pick), never more than the half cone; nothing there: straight down the facing.
##   R4 the score: d x (1 + 2 (phi / theta)^2) / w, lowest wins (w = 1, or for a "priority" weapon its max HP over the
##      crowd's mean, 1..PRIORITY_CAP as EnemyManager.priority_index). A special, an Elite or the boss within the map's
##      target_priority reach is taken first when it stands inside `big_cone` (default 1.5 x the cone, 90 full).
##   R5 every weapon fires on its clock even with nothing to hit, unless `params.aim.hold` (seconds it may wait).
##   R6 placed weapons: spots in a CIRCLE round him (Garry), `min_r`..its range: CANDIDATES candidate spots from the aim
##      dice, each scored by what its blast would catch (specials, Elites and the boss x3), the best taken `best_chance` of
##      the time (default 0.6), else one of the others; the spots of one volley keep `apart` x the blast radius apart.
##   R7 the aim wedge on the sand (core/systems/AimWedge.gd) and the placed weapons' own marks.
## Every roll comes from the aim dice (Dice.rng_for("aim"), one stream a run), so replays play the same.
class_name Aim
extends RefCounted

const DEFAULT_CONE := 60.0
const BIG_CONE_MULT := 1.5
const CANDIDATES := 6
const BEST_CHANCE := 0.6
const APART := 1.5
## how many of a spot's CANDIDATES stand on a creature in the ring (circle_spots)
const CROWD_SEEDED := 3
## the weight's cap for a "priority" weapon (EnemyManager.PRIORITY_CAP's value)
const PRIORITY_CAP := 3.0

static var _dice: RandomNumberGenerator = null
static var _dice_seed := -1


## Whether the rule plays (the switch; tools may set Settings.aim_mode off to compare with the old aim).
static func on() -> bool:
	return bool(Settings.get("aim_mode")) if "aim_mode" in Settings else false


## The weapon's aim block (`params.aim`, its evolution's own when evolved) with the defaults filled in; {} when the
## weapon has none (it aims as it always did).
static func cfg(inst: WeaponInstance) -> Dictionary:
	if inst == null:
		return {}
	var a = inst.params.get("aim")
	if not (a is Dictionary):
		return {}
	var out: Dictionary = (a as Dictionary).duplicate()
	out["cone"] = float(out.get("cone", DEFAULT_CONE))
	out["big_cone"] = float(out.get("big_cone", float(out["cone"]) * BIG_CONE_MULT))
	out["hold"] = float(out.get("hold", 0.0))
	out["best_chance"] = float(out.get("best_chance", BEST_CHANCE))
	out["family"] = str(out.get("family", "aimed"))
	return out


## Whether `inst` aims by the new rule now: the switch on and the weapon carrying an aim block whose family is not
## "around" (Orbit Saws, Salt: they do not aim).
static func covers(inst: WeaponInstance) -> bool:
	if not on():
		return false
	var c := cfg(inst)
	return not c.is_empty() and str(c["family"]) != "around"


## The Outlaw's facing on the ground plane, unit length (Vector3.FORWARD for none).
static func facing(player: Node) -> Vector3:
	var f: Vector3 = player.forward() if player != null and player.has_method("forward") else Vector3.FORWARD
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


## The aim dice: one stream a run (Dice.rng_for("aim")), made again when the run's seed changes or at reset() (a run's
## start: Game calls it, so a replay of the same seed rolls the same spots).
static func dice() -> RandomNumberGenerator:
	var s: int = Dice.run_seed
	if _dice == null or s != _dice_seed:
		_dice = Dice.rng_for("aim")
		_dice_seed = s
	return _dice


## A fresh aim stream (a run's start).
static func reset() -> void:
	_dice = null
	_dice_seed = -1
	_dry.clear()


## Dry shots this run by weapon id (lane GUNS): a pull an aimed weapon fired with nothing in its cone (R5). The run record's
## `weapon_dry` (RunAnalytics). Any behaviour calls note_dry(inst) when Aim.covers(inst) and its shot had no target.
static var _dry: Dictionary = {}


static func note_dry(inst: WeaponInstance) -> void:
	if inst != null and inst.def != null:
		_dry[inst.def.id] = int(_dry.get(inst.def.id, 0)) + 1


static func dry_counts() -> Dictionary:
	return _dry.duplicate()


## The angle (radians, 0..PI) between `dir` and the flat way from `from` to `to`.
static func angle_off(from: Vector3, dir: Vector3, to: Vector3) -> float:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length_squared() < 0.0001:
		return 0.0
	return absf(Vector2(dir.x, dir.z).angle_to(Vector2(d.x, d.z)))


## Whether creature `i` stands (alive, not dying, buried or held, risen enough, on the screen unless `any_screen`).
static func standing(em: EnemyManager, i: int, any_screen: bool = false) -> bool:
	if i < 0 or i >= em.alive.size() or em.alive[i] == 0 or em.state[i] == EnemyManager.STATE_DYING:
		return false
	if em.hidden[i] == 1 or em.held[i] == 1:
		return false
	if em.rise_t[i] < em.rise_targetable:
		return false
	if em._screen_only(any_screen) and em.onscreen[i] == 0:
		return false
	return true


## The best target for an aimed shot from `from` along `dir` (R4): within `range_m`, its body touching the cone of full
## angle `cone_deg`; a priority creature (special, Elite, boss) within the map's reach and inside `big_cone_deg` first.
## `strongest` weights by max HP over the crowd's mean (a "priority" weapon). `avoid` leaves out creatures carrying that
## element. Ties break by the lower index. -1 for none. `exclude` (pass 136, lane HOMING: a volley spreading over its
## targets) leaves out those indices.
static func pick(em: EnemyManager, from: Vector3, dir: Vector3, range_m: float, cone_deg: float, strongest: bool = false,
		big_cone_deg: float = -1.0, avoid: String = "", any_screen: bool = false, exclude: Array = []) -> int:
	if em == null or range_m <= 0.0:
		return -1
	var half := deg_to_rad(maxf(cone_deg, 1.0) * 0.5)
	var big_half := deg_to_rad((big_cone_deg if big_cone_deg > 0.0 else cone_deg * BIG_CONE_MULT) * 0.5)
	# the priority creature first, inside the wider cone
	var pt := em.priority_target(from, range_m, any_screen)
	if pt >= 0 and not exclude.has(pt):
		var d := Vector2(em.pos[pt].x - from.x, em.pos[pt].z - from.z).length()
		var slack := atan2(float(em.radius[pt]), maxf(d, 0.1))
		if angle_off(from, dir, em.pos[pt]) <= big_half + slack:
			return pt
	if strongest and em._mean_max_hp <= 0.0:
		em.refresh_crowd_stats()
	var inv_mean := 1.0 / maxf(em._mean_max_hp, 0.001)
	var best := -1
	var best_s := INF
	for i in em.indices_in_radius(from, range_m):
		if not standing(em, i, any_screen) or exclude.has(i):
			continue
		if avoid != "" and em.has_element(i, avoid):
			continue
		var dx: float = em.pos[i].x - from.x
		var dz: float = em.pos[i].z - from.z
		var d := sqrt(dx * dx + dz * dz)
		if d > range_m + float(em.radius[i]):
			continue
		var phi := angle_off(from, dir, em.pos[i])
		# the body touching the cone counts (a big creature at the edge)
		var slack := atan2(float(em.radius[i]), maxf(d, 0.1))
		if phi > half + slack:
			continue
		var p := maxf(phi - slack, 0.0) / half
		var w := 1.0
		if strongest:
			w = clampf(float(em.max_hp[i]) * inv_mean, 1.0, PRIORITY_CAP)
		var s := d * (1.0 + 2.0 * p * p) / w
		if s < best_s or (s == best_s and i < best):
			best_s = s
			best = i
	return best


## R4's score of creature `i` for a shot from `from` along `dir` in a cone of full angle `cone_deg` (its body touching
## the cone counts), INF when it stands outside the cone (lane GUNS: the Gravity Gun ranks its grabs by it; no weight).
static func cone_score(em: EnemyManager, i: int, from: Vector3, dir: Vector3, cone_deg: float) -> float:
	var half := deg_to_rad(maxf(cone_deg, 1.0) * 0.5)
	var d := Vector2(em.pos[i].x - from.x, em.pos[i].z - from.z).length()
	var phi := angle_off(from, dir, em.pos[i])
	var slack := atan2(float(em.radius[i]), maxf(d, 0.1))
	if phi > half + slack:
		return INF
	var p := maxf(phi - slack, 0.0) / half
	return d * (1.0 + 2.0 * p * p)


## `dir` turned towards `to` by at most `max_deg` (flat, unit length): the soft assist (R3).
static func assist(from: Vector3, dir: Vector3, to: Vector3, max_deg: float) -> Vector3:
	var want := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if want.length_squared() < 0.0001:
		return dir
	var a := Vector2(dir.x, dir.z).angle_to(Vector2(want.x, want.z))
	var lim := deg_to_rad(maxf(max_deg, 0.0))
	a = clampf(a, -lim, lim)
	var v := Vector2(dir.x, dir.z).rotated(a)
	return Vector3(v.x, 0.0, v.y).normalized()


## The aimed shot for `inst` from `from`: {dir (flat unit), target (-1 for none)}: the facing turned to the best target in
## the weapon's cone, or the facing itself.
static func shot(inst: WeaponInstance, em: EnemyManager, player: Node, from: Vector3, range_m: float, avoid: String = "") -> Dictionary:
	var c := cfg(inst)
	var f := facing(player)
	var cone := float(c.get("cone", DEFAULT_CONE))
	var strongest := inst != null and inst.def != null and inst.def.targeting == "priority"
	var t := pick(em, from, f, range_m, cone, strongest, float(c.get("big_cone", cone * BIG_CONE_MULT)), avoid)
	if t < 0:
		return {"dir": f, "target": -1}
	var lim := float(c.get("assist", cone * 0.5))
	# a priority creature in the wider cone may pull the shot up to its own half angle
	if em.is_priority(t):
		lim = maxf(lim, float(c.get("big_cone", cone * BIG_CONE_MULT)) * 0.5)
	return {"dir": assist(from, f, em.pos[t], lim), "target": t}


## What a blast of radius `r` at `spot` would catch (R6): creatures within r (their bodies), specials, Elites and the
## boss x3. `avoid` leaves out creatures carrying that element (the Molotov's unburnt, the Skull Rain's unpoisoned).
static func spot_score(em: EnemyManager, spot: Vector3, r: float, avoid: String = "") -> float:
	var s := 0.0
	for i in em.indices_in_radius(spot, r + 1.0):
		if not standing(em, i, true):
			continue
		if avoid != "" and em.has_element(i, avoid):
			continue
		var d := Vector2(em.pos[i].x - spot.x, em.pos[i].z - spot.z).length()
		if d <= r + float(em.radius[i]):
			s += 3.0 if em.is_priority(i) else 1.0
	return s


## `n` spots for a placed weapon round `from` (R6, a circle): each the pick of CANDIDATES candidates in the ring
## `min_r`..`max_r` (even over the area), the best-scoring taken `best_chance` of the time, else one of the others at
## random; spots keep `apart` x `blast_r` from each other and from `taken`. With nothing to catch anywhere they are plain
## random spots in the circle. `ok` (optional Callable(Vector3) -> bool) rejects a candidate (water, rocks).
## `scorer` (lane PLACED; optional Callable(Array of candidate spots) -> Array of floats, one a spot) scores the
## candidates in place of spot_score: the Dynamite's lead prediction (where the crowd will be when the fuse ends), the
## Turret Buddy's crowd within its gun's reach.
static func circle_spots(em: EnemyManager, from: Vector3, min_r: float, max_r: float, n: int, blast_r: float,
		best_chance: float = BEST_CHANCE, avoid: String = "", taken: Array = [], ok: Callable = Callable(),
		scorer: Callable = Callable()) -> Array:
	var g := dice()
	var out: Array = []
	var keep: Array = taken.duplicate()
	var lo := maxf(min_r, 0.0)
	var hi := maxf(max_r, lo + 0.1)
	# pass 136 (lead, after lane GUNS measured a pack caught 1 time in 20 on a 2-10 m ring): up to CROWD_SEEDED of the
	# candidates stand on a creature in the ring (a random one from the dice, nudged up to half a blast), the rest anywhere
	# in it; the best is still taken best_chance of the time, so spots lean to the crowd and stay random
	var crowd: Array = []
	if em != null:
		for i in em.indices_in_radius(from, hi + 0.5):
			if not standing(em, i, true):
				continue
			var cd := Vector2(em.pos[i].x - from.x, em.pos[i].z - from.z).length()
			if cd >= lo and cd <= hi:
				crowd.append(i)
	for k in range(maxi(n, 0)):
		var cands: Array = []
		var tries := 0
		while cands.size() < CANDIDATES and tries < CANDIDATES * 8:
			tries += 1
			var p: Vector3
			if not crowd.is_empty() and cands.size() < CROWD_SEEDED and tries <= CROWD_SEEDED * 3:
				var e: int = crowd[g.randi() % crowd.size()]
				var na := g.randf() * TAU
				var nr := g.randf() * blast_r * 0.5
				p = Vector3(em.pos[e].x + cos(na) * nr, from.y, em.pos[e].z + sin(na) * nr)
				var off := Vector2(p.x - from.x, p.z - from.z)
				if off.length() > hi:
					off = off.normalized() * hi
				elif off.length() < lo:
					off = (off.normalized() if off.length() > 0.001 else Vector2.RIGHT) * lo
				p = Vector3(from.x + off.x, from.y, from.z + off.y)
			else:
				var a := g.randf() * TAU
				# even over the ring's area
				var rr := sqrt(lerpf(lo * lo, hi * hi, g.randf()))
				p = from + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			var clear := true
			for q: Vector3 in keep:
				if Vector2(p.x - q.x, p.z - q.z).length() < blast_r * APART:
					clear = false
					break
			if clear and ok.is_valid() and not bool(ok.call(p)):
				clear = false
			if clear or tries >= CANDIDATES * 6:
				cands.append(p)
		if cands.is_empty():
			break
		var best := 0
		var best_s := -1.0
		var scores: Array = []
		var given: Array = scorer.call(cands) if scorer.is_valid() else []
		for j in cands.size():
			var s: float = float(given[j]) if j < given.size() else (spot_score(em, cands[j], blast_r, avoid) if em != null else 0.0)
			scores.append(s)
			if s > best_s:
				best_s = s
				best = j
		var choice := best
		if cands.size() > 1 and g.randf() >= best_chance:
			choice = (best + 1 + g.randi() % (cands.size() - 1)) % cands.size()
		out.append(cands[choice])
		keep.append(cands[choice])
	return out


## A circle_spots `ok` (lane PLACED) that keeps spots inside the map's arena, `margin` m in from its rim (MapBase's own
## clamp); an empty Callable (every spot ok) without a map.
static func arena_ok(game: Node, margin: float = 1.5) -> Callable:
	var map = game.get("map") if game != null else null
	if map == null or map.get("arena_radius") == null:
		return Callable()
	var r: float = float(map.get("arena_radius")) - margin
	return func(p: Vector3) -> bool: return Vector2(p.x, p.z).length() <= r
