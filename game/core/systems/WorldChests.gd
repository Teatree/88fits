## Pass 111 (lane CHEST; Garry, 2026-10-28: "Chests should respawn every now and then. They should also have a chance of a
## power up dropping from them. The power ups don't immediately get claimed and used by the hero. They jump far enough
## out for it to be a conscious decision for the Player. I should be able to set the frequency and content probabilities
## of both chest types on LevelEditor. Chests never spawn where Player can see them").
##
## The world chests: on top of the chests the crowd drops (pass 110: specials, Elites, bosses, a regular creature's 1 in
## 5,000), the map lays a chest of its own now and then, the map's `timeline_data.world_chests` block (DEFAULTS fill the
## keys it leaves out; no block = none, as before pass 111):
##   enabled      true = on (left out, or false: none).
##   first        seconds of the stage before the first one is due.
##   every        seconds from one to the next: a number, or [min, max] rolled each time.
##   max_on_map   world chests lying unopened at most (0 = no limit): a turn that finds that many lying is skipped (the
##                next one rolls its wait), so chests left alone never pile up.
##   max_per_stage  world chests a stage at most (0 = no limit).
##   min_dist, max_dist  how far from the hero (flat) it is laid; when every spot of that band is on the screen (the camera
##                pulled far out late in a run) the band past it up to 1.5 x max_dist is tried.
##   boss_chance  the chance a world chest is the boss's chest (violet, a mutation, calls the map in when opened).
##   lifetime     seconds one may lie unopened; past it, it vanishes the first moment it is OFF the screen (never before
##                the player's eyes). 0 = it waits forever.
##   view_margin  metres past the camera's view a spot must keep (the chest, its pool of light and its 9 m beam).
##   in_boss, in_portal, in_endless  whether the clock runs (and chests come) during the boss fight, the portal's
##                countdown and Endless. The clock counts only the seconds of the phases it runs in.
##   pointer      the HUD's edge tag points at the nearest world chest lying off the screen ("CHEST 32 m").
## A spot is never seen: every sphere a chest can draw in (SEEN_SPHERES: the chest with its pool, its beam up to 9 m)
## lies outside the camera's frustum by view_margin; it is inside the map's walkable round (EDGE_SHARE of the arena's
## radius, as the structures), off every rock's painted foot and out of the water (EnemyManager.spawn_clear) by
## WATER_CLEAR, not behind a painting (BarrelField.in_cover), CHEST_CLEAR from any chest and STRUCTURE_CLEAR past every
## structure's ring. The searching is PickupManager's (world_* host methods); this class keeps the clock, the dice and
## the rules, and reads no autoload.
##
## Both chest types' contents, `timeline_data.chest_contents` {"normal": {...}, "boss": {...}} (CONTENT_DEFAULTS fill gaps):
##   powerup_chance  the chance a power-up is thrown out when the chest is opened (on top of what the reel gives).
##   powerups        [{id, weight}, ...]: which power-up (empty = the map's power-up drops roster, `pickups.roster`).
##   throw_distance  metres from the chest it lands: a number or [min, max]. It hops out on a visible arc, lands away
##                   from the hero, cannot be taken in the air, is never pulled by a magnet or a vacuum, and lies there
##                   its own lifetime (content/pickups/<id> `lifetime`), so walking to it is the player's choice.
##   new_item_weight a passive item not held yet weighs this on the reel against an upgrade of what he holds (Run's
##                   CHEST_NEW_MULT 0.45, today's).
##   gold            what the reel pays when nothing can grow (today's 50).
##   mutation        (boss) the boss's chest holds a mutation while one is open (today's); false = it rolls like any.
class_name WorldChests
extends RefCounted

const DEFAULTS := {
	"enabled": false, "first": 60.0, "every": [90.0, 130.0], "max_on_map": 2, "max_per_stage": 0,
	"min_dist": 25.0, "max_dist": 45.0, "boss_chance": 0.0, "lifetime": 150.0, "view_margin": 3.0,
	"in_boss": true, "in_portal": false, "in_endless": false, "pointer": true,
}
const CONTENT_DEFAULTS := {
	"normal": {"powerup_chance": 0.0, "powerups": [], "throw_distance": [5.0, 7.0], "new_item_weight": 0.45, "gold": 50},
	"boss": {"powerup_chance": 0.0, "powerups": [], "throw_distance": [5.0, 7.0], "new_item_weight": 0.45, "gold": 50,
		"mutation": true},
}
## The least seconds between two world chests (an `every` under it reads as this).
const EVERY_MIN := 5.0
## A turn whose search found no spot tries again this many seconds later.
const RETRY_S := 3.0
## How often the lifetime is looked at (seconds).
const CHECK_EVERY := 1.0
## Spots tried in each band (min_dist..max_dist, then max_dist..FAR_BAND x max_dist).
const TRIES := 48
const FAR_BAND := 1.5
## The walkable round, as the structures' returns use it (StructureManager.find_spot: 0.86 of the arena's radius).
const EDGE_SHARE := 0.86
const CHEST_CLEAR := 8.0
const STRUCTURE_CLEAR := 3.0
const WATER_CLEAR := 2.5
const COVER_CLEAR := 1.5
## A thrown power-up keeps this far from a rock's foot, the water and the rim, and this far from another power-up or chest.
const THROW_CLEAR := 1.2
const THROW_TRIES := 16
## Every sphere a chest can draw in, (height over its feet, radius): the chest with its pool of light (4.6 m across) and
## its sunburst, then its beam (Chest.gd: 1.2 m wide, 9 m tall) in three pieces.
const SEEN_SPHERES := [Vector2(0.7, 2.6), Vector2(3.0, 1.0), Vector2(5.5, 1.0), Vector2(8.2, 1.0)]

## WaveDirector.Phase's order (NORMAL, BOSS, PORTAL, ENDLESS), read as numbers so nothing here names the director.
const PHASE_NORMAL := 0
const PHASE_BOSS := 1
const PHASE_PORTAL := 2
const PHASE_ENDLESS := 3

var cfg: Dictionary = {}
var on := false
## The world chests' own clock: seconds of the phases it runs in (in_boss, in_portal, in_endless).
var clock := 0.0
## The clock's time of the next one (INF: none comes any more this stage).
var next_at := INF
## This stage: chests laid, turns skipped because max_on_map lay already, searches that found no spot, chests that
## vanished past their lifetime.
var spawned := 0
var skipped := 0
var missed := 0
var expired := 0
## The world chests' and the chests' power-ups' own dice (seeded from the run's seed in the sim, so they never move the
## run's shared random sequence).
var rng := RandomNumberGenerator.new()
var _check_t := 0.0


## Starts the clock for a stage from the map's `world_chests` block (`seed_v` the run's seed, 0 = random dice).
func setup(block, seed_v: int = 0) -> void:
	cfg = cfg_of(block)
	on = bool(cfg["enabled"])
	clock = 0.0
	spawned = 0
	skipped = 0
	missed = 0
	expired = 0
	_check_t = 0.0
	if seed_v != 0:
		rng.seed = hash([seed_v, "chests"])
	else:
		rng.randomize()
	next_at = float(cfg["first"]) if on else INF


## The block whole, every key filled and in range (no block, or not a block: enabled false).
static func cfg_of(block) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var has := block is Dictionary and not (block as Dictionary).is_empty()
	if has:
		for k in (block as Dictionary):
			out[k] = block[k]
	out["enabled"] = has and _bool(out["enabled"])
	out["first"] = maxf(_num(out["first"], 60.0), 0.0)
	var ev := range_of(out["every"], Vector2(90.0, 130.0))
	out["every"] = Vector2(maxf(ev.x, EVERY_MIN), maxf(ev.y, EVERY_MIN))
	out["max_on_map"] = maxi(int(_num(out["max_on_map"], 2.0)), 0)
	out["max_per_stage"] = maxi(int(_num(out["max_per_stage"], 0.0)), 0)
	out["min_dist"] = maxf(_num(out["min_dist"], 25.0), 0.0)
	out["max_dist"] = maxf(_num(out["max_dist"], 45.0), float(out["min_dist"]))
	out["boss_chance"] = clampf(_num(out["boss_chance"], 0.0), 0.0, 1.0)
	out["lifetime"] = maxf(_num(out["lifetime"], 150.0), 0.0)
	out["view_margin"] = maxf(_num(out["view_margin"], 3.0), 0.0)
	for k in ["in_boss", "in_portal", "in_endless", "pointer"]:
		out[k] = _bool(out[k])
	return out


## One chest type's contents, every key filled and in range (`block` the map's chest_contents).
static func contents_of(block, boss: bool) -> Dictionary:
	var key := "boss" if boss else "normal"
	var out: Dictionary = (CONTENT_DEFAULTS[key] as Dictionary).duplicate(true)
	var own = (block as Dictionary).get(key) if block is Dictionary else null
	if own is Dictionary:
		for k in (own as Dictionary):
			out[k] = own[k]
	out["powerup_chance"] = clampf(_num(out["powerup_chance"], 0.0), 0.0, 1.0)
	out["throw_distance"] = range_of(out["throw_distance"], Vector2(5.0, 7.0))
	var td: Vector2 = out["throw_distance"]
	out["throw_distance"] = Vector2(maxf(td.x, 0.0), maxf(td.y, maxf(td.x, 0.0)))
	out["new_item_weight"] = maxf(_num(out["new_item_weight"], 0.45), 0.0)
	out["gold"] = maxi(int(_num(out["gold"], 50.0)), 0)
	if out.has("mutation"):
		out["mutation"] = _bool(out["mutation"])
	out["powerups"] = weight_list(out["powerups"])
	return out


## A power-up list as [{id, weight}] with every weight above 0: [{id, weight}, ...] or {id: weight}.
static func weight_list(v) -> Array:
	var out: Array = []
	if v is Dictionary:
		for id in (v as Dictionary):
			if str(id) != "" and _num(v[id], 0.0) > 0.0:
				out.append({"id": str(id), "weight": _num(v[id], 0.0)})
	elif v is Array:
		for r in (v as Array):
			if r is Dictionary and str((r as Dictionary).get("id", "")) != "":
				var w := _num((r as Dictionary).get("weight", 1.0), 1.0)
				if w > 0.0:
					out.append({"id": str(r["id"]), "weight": w})
	return out


## An id drawn from [{id, weight}] by weight ("" from an empty list).
static func pick_weighted(list: Array, dice: RandomNumberGenerator) -> String:
	var total := 0.0
	for r: Dictionary in list:
		total += maxf(float(r.get("weight", 0.0)), 0.0)
	if total <= 0.0:
		return ""
	var x := dice.randf() * total
	for r: Dictionary in list:
		x -= maxf(float(r.get("weight", 0.0)), 0.0)
		if x <= 0.0:
			return str(r["id"])
	return str((list[list.size() - 1] as Dictionary)["id"])


## A number or [min, max] (a list of one: that number) as Vector2(min, max); `fallback` for anything else.
static func range_of(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return Vector2(minf(v.x, v.y), maxf(v.x, v.y))
	if v is float or v is int:
		return Vector2(float(v), float(v))
	if v is Array and not (v as Array).is_empty():
		var a := _num(v[0], fallback.x)
		var b := _num(v[(v as Array).size() - 1], a)
		return Vector2(minf(a, b), maxf(a, b))
	return fallback


static func roll(r: Vector2, dice: RandomNumberGenerator) -> float:
	return r.x if r.y <= r.x else dice.randf_range(r.x, r.y)


## Whether the clock runs in the director's `phase` (WaveDirector.Phase as a number).
static func phase_allowed(c: Dictionary, phase: int) -> bool:
	match phase:
		PHASE_BOSS:
			return bool(c.get("in_boss", true))
		PHASE_PORTAL:
			return bool(c.get("in_portal", false))
		PHASE_ENDLESS:
			return bool(c.get("in_endless", false))
	return true


## Whether a chest standing at `p` could show anything inside the camera's frustum (`planes`: Camera3D.get_frustum, facing
## out) grown by `margin` m: any of SEEN_SPHERES reaching in. False with no planes (no camera: nobody sees).
static func seen(planes: Array, p: Vector3, margin: float) -> bool:
	if planes.is_empty():
		return false
	for s: Vector2 in SEEN_SPHERES:
		var c := p + Vector3(0.0, s.x, 0.0)
		var r := s.y + margin
		var inside := true
		for pl: Plane in planes:
			if pl.distance_to(c) > r:
				inside = false
				break
		if inside:
			return true
	return false


## About how many world chests a stage of `length` seconds lays when every turn finds room (the clock's own seconds):
## the first at `first`, then one every `every` on average, at most max_per_stage (the Level Editor shows the same sum).
static func expected_in(c: Dictionary, length: float) -> float:
	if not bool(c.get("enabled", false)) or length < float(c["first"]):
		return 0.0
	var ev: Vector2 = c["every"]
	var mean := maxf((ev.x + ev.y) * 0.5, EVERY_MIN)
	var n := 1.0 + floorf((length - float(c["first"])) / mean)
	var most := int(c.get("max_per_stage", 0))
	return minf(n, float(most)) if most > 0 else n


## One tick of the clock (`host` the PickupManager, `phase` the director's): the lifetime's look every CHECK_EVERY s,
## then, in a phase it runs in, the next chest when it is due.
func tick(host, delta: float, phase: int) -> void:
	if not on:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		expired += int(host.world_expire(float(cfg["lifetime"]), float(cfg["view_margin"])))
	if not phase_allowed(cfg, phase):
		return
	clock += delta
	if clock < next_at:
		return
	var most := int(cfg["max_per_stage"])
	if most > 0 and spawned >= most:
		next_at = INF
		return
	var room := int(cfg["max_on_map"])
	if room > 0 and int(host.world_lying()) >= room:
		skipped += 1
		next_at = clock + roll(cfg["every"], rng)
		return
	if not spawn_now(host):
		missed += 1
		next_at = clock + RETRY_S
		return
	next_at = clock + roll(cfg["every"], rng)


## A world chest now at a spot nobody sees (tools, tests, the due turn). False when no spot was found.
func spawn_now(host) -> bool:
	var at := find_spot(host)
	if at == Vector3.INF:
		return false
	host.spawn_chest(at, rng.randf() < float(cfg.get("boss_chance", 0.0)), true)
	spawned += 1
	return true


## A spot for a world chest (Vector3.INF when none): round the hero in the min_dist..max_dist band, then out to FAR_BAND x
## max_dist, each try asked of the host's rules (world_spot_ok: grounded spot or INF) and kept only off the screen.
func find_spot(host) -> Vector3:
	var hero: Vector3 = host.world_hero()
	if hero == Vector3.INF:
		return Vector3.INF
	var planes: Array = host.world_planes()
	var ctx = host.world_spot_ctx()
	var margin := float(cfg.get("view_margin", 3.0))
	var lo := float(cfg.get("min_dist", 25.0))
	var hi := maxf(float(cfg.get("max_dist", 45.0)), lo)
	for band: Vector2 in [Vector2(lo, hi), Vector2(hi, maxf(hi * FAR_BAND, hi + 1.0))]:
		for k in range(TRIES):
			var a := rng.randf() * TAU
			var d := rng.randf_range(band.x, band.y)
			var q: Vector3 = host.world_spot_ok(Vector3(hero.x + cos(a) * d, hero.y, hero.z + sin(a) * d), ctx)
			if q == Vector3.INF or seen(planes, q, margin):
				continue
			return q
	return Vector3.INF


static func _num(v, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String and (v as String).is_valid_float():
		return (v as String).to_float()
	return fallback


static func _bool(v) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return float(v) != 0.0
	if v is String:
		return (v as String).to_lower() in ["true", "1", "yes", "on"]
	return false
