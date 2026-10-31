## Pass 112 (lane BARREL; Garry, 2026-10-28, first said of chests in pass 111, then: "when I was talking about chest
## appearing and stuff I actually meant barrels. Not chests. So apply whatever I said in that prompt to barrels": "should
## respawn every now and then. They should also have a chance of a power up dropping from them. The power ups don't
## immediately get claimed and used by the hero. They jump far enough out for it to be a conscious decision for the
## Player. I should be able to set the frequency and content probabilities of both [barrel] types on LevelEditor. [They]
## never spawn where Player can see them").
##
## The map's `timeline_data.barrels` block (no block = today's barrels: no respawns, no power-up, today's contents):
##   respawn       the clock that lays barrels again (RESPAWN_DEFAULTS fill the keys it leaves out; enabled false or
##                 left out: none):
##     enabled        true = on.
##     first          seconds of the stage before the first respawn is due.
##     every          seconds from one to the next: a number, or [min, max] rolled each time.
##     max_lying      barrels standing at most (the map's start barrels count: 35 = only broken ones come back); a turn
##                    that finds that many standing is skipped (the next one rolls its wait). 0 = no limit.
##     max_per_stage  respawns a stage at most (0 = no limit).
##     min_dist, max_dist  how far from the hero (flat) one is laid; when every spot of that band is on the screen the
##                    band past it, up to FAR_BAND x max_dist, is tried.
##     (pass 116: a respawned barrel's kind is drawn by the kinds' `weight`s; the old black_chance is ignored)
##     view_margin    metres past the camera's view the barrel and its shadow must keep when it appears.
##     in_boss, in_portal, in_endless  whether the clock runs (and barrels come back) in the boss fight, the portal's
##                    countdown and Endless; it counts only the seconds of the phases it runs in.
##   exp, coins, powerup (pass 116; pass 112's brown, black)  what each barrel type holds (CONTENT_DEFAULTS fill gaps: today's):
##     powerup_chance  the chance smashing it throws a power-up out, on top of its gems and coins.
##     powerups        [{id, weight}, ...]: which power-up (empty = the map's power-up drops roster, `pickups.roster`).
##     throw_distance  metres from the barrel the power-up lands: a number or [min, max] (PickupManager.throw_powerup:
##                     a visible hop, never taken in the air, never pulled by a magnet, lies its own lifetime).
##     gems_small, gems_medium  the XP gems it bursts into (a medium one is worth 4 small).
##     coins           its coins: a number, or [min, max] rolled per barrel (today: none from a brown one, 1-5 from a
##                     black one). The start barrels' coins are held back from the creatures' first coins of the run
##                     (pass 87, PickupManager.coin_debt); a respawned barrel's are extra.
## A respawn spot is never seen: the barrel and its shadow (SEEN_SPHERES) lie outside the camera's frustum by
## view_margin; the rest of the start's rules hold (BarrelField.spawn_ok: in the arena, off the flats, the rocks and the
## water, out of every painting's cover band and structure ring, MIN_GAP from every standing barrel). The searching is
## BarrelField's (spawn_* host methods); this class keeps the clock, the dice and the rules, and reads no autoload.
class_name BarrelSpawns
extends RefCounted

const RESPAWN_DEFAULTS := {
	"enabled": false, "first": 45.0, "every": [40.0, 60.0], "max_lying": 35, "max_per_stage": 0,
	"min_dist": 20.0, "max_dist": 40.0, "view_margin": 2.0,
	"in_boss": true, "in_portal": false, "in_endless": false,
}
## Pass 116 (lane MAP; Garry: "3 kinds now. One of them produces only power ups. This 3rd barrel is about 60% of the
## amount of the EXP+Coins. Make it so the other barrels don't give any power-up anymore"): three kinds, painted from his
## board (art/sprites/barrels/barrel_<kind>.png): `exp` (brown wood, iron hoops: gems), `coins` (gold hoops and studs: gems
## and coins; pass 87's black barrel), `powerup` (iron hoops, a white stripe: a power-up only, thrown out as pass 112's
## were). `weight` is each kind's share of the start's barrels and of the respawns (powerup 0.6 x coins). Only the powerup
## kind reads powerup_chance / powerups / throw_distance; the other two never throw one. The old keys migrate on read:
## `brown` -> exp, `black` -> coins (their power-up keys ignored; the powerup kind takes the old black list when it has
## none of its own); the old respawn `black_chance` is ignored (the weights decide).
const CONTENT_DEFAULTS := {
	"exp": {"weight": 0.648, "gems_small": 8, "gems_medium": 0, "coins": 0},
	"coins": {"weight": 0.22, "gems_small": 10, "gems_medium": 4, "coins": [1, 5]},
	"powerup": {"weight": 0.132, "powerup_chance": 1.0, "powerups": [], "throw_distance": [5.0, 7.0], "gems_small": 0,
		"gems_medium": 0, "coins": 0},
}
const TYPES := ["exp", "coins", "powerup"]
## Kind numbers (BarrelField.light holds them since pass 116: 0 exp, 1 coins, 2 powerup).
const EXP := 0
const COINS := 1
const POWERUP := 2
## The pass 112 keys each kind reads when its own is missing.
const LEGACY := {"exp": "brown", "coins": "black", "powerup": ""}
## The least seconds between two respawns (an `every` under it reads as this).
const EVERY_MIN := 5.0
## A turn whose search found no spot tries again this many seconds later.
const RETRY_S := 3.0
## Spots tried in each band (min_dist..max_dist, then max_dist..FAR_BAND x max_dist).
const TRIES := 48
const FAR_BAND := 1.5
## The spheres a barrel can draw in, (height over its feet, radius): the 0.9 m barrel (0.31 m round) with its 0.95 m
## shadow.
const SEEN_SPHERES := [Vector2(0.45, 0.75)]

## WaveDirector.Phase's order (NORMAL, BOSS, PORTAL, ENDLESS), read as numbers so nothing here names the director.
const PHASE_NORMAL := 0
const PHASE_BOSS := 1
const PHASE_PORTAL := 2
const PHASE_ENDLESS := 3

var cfg: Dictionary = {}
var on := false
## The respawns' own clock: seconds of the phases it runs in (in_boss, in_portal, in_endless).
var clock := 0.0
## The clock's time of the next respawn (INF: none comes any more this stage).
var next_at := INF
## This stage: barrels laid again, turns skipped because max_lying stood already, searches that found no spot.
var spawned := 0
var skipped := 0
var missed := 0
## The respawns' own dice (seeded from the run's seed in the sim, so they never move the run's shared random sequence).
var rng := RandomNumberGenerator.new()


## Starts the clock for a stage from the map's `barrels` block (`seed_v` the run's seed, 0 = random dice).
func setup(block, seed_v: int = 0) -> void:
	cfg = respawn_of(block)
	on = bool(cfg["enabled"])
	clock = 0.0
	spawned = 0
	skipped = 0
	missed = 0
	if seed_v != 0:
		rng.seed = hash([seed_v, "barrel_spawns"])
	else:
		rng.randomize()
	next_at = float(cfg["first"]) if on else INF


## The respawn block whole (the `barrels` block's `respawn`), every key filled and in range (none: enabled false).
static func respawn_of(block) -> Dictionary:
	var own = (block as Dictionary).get("respawn") if block is Dictionary else null
	var out: Dictionary = RESPAWN_DEFAULTS.duplicate(true)
	var has := own is Dictionary and not (own as Dictionary).is_empty()
	if has:
		for k in (own as Dictionary):
			out[k] = own[k]
	out["enabled"] = has and _bool(out["enabled"])
	out["first"] = maxf(_num(out["first"], 45.0), 0.0)
	var ev := range_of(out["every"], Vector2(40.0, 60.0))
	out["every"] = Vector2(maxf(ev.x, EVERY_MIN), maxf(ev.y, EVERY_MIN))
	out["max_lying"] = maxi(int(_num(out["max_lying"], 35.0)), 0)
	out["max_per_stage"] = maxi(int(_num(out["max_per_stage"], 0.0)), 0)
	out["min_dist"] = maxf(_num(out["min_dist"], 20.0), 0.0)
	out["max_dist"] = maxf(_num(out["max_dist"], 40.0), float(out["min_dist"]))
	out.erase("black_chance")
	out["view_margin"] = maxf(_num(out["view_margin"], 2.0), 0.0)
	for k in ["in_boss", "in_portal", "in_endless"]:
		out[k] = _bool(out[k])
	return out


## A kind as its key: "exp" / "coins" / "powerup", a kind number (EXP, COINS, POWERUP) or pass 112's bool (true = the
## black barrel, now coins).
static func kind_key(kind) -> String:
	if kind is bool:
		return "coins" if kind else "exp"
	if kind is int or kind is float:
		return TYPES[clampi(int(kind), 0, TYPES.size() - 1)]
	var k := str(kind)
	if k == "brown":
		return "exp"
	if k == "black":
		return "coins"
	return k if k in TYPES else "exp"


## One barrel kind's contents (`kind`: see kind_key), every key filled and in range (`block` the map's `barrels`). Only the
## powerup kind keeps a power-up chance; exp and coins read 0 whatever the block says.
static func contents_of(block, kind) -> Dictionary:
	var key := kind_key(kind)
	var out: Dictionary = (CONTENT_DEFAULTS[key] as Dictionary).duplicate(true)
	var b: Dictionary = block if block is Dictionary else {}
	var own = b.get(key)
	if not (own is Dictionary) and str(LEGACY[key]) != "":
		own = b.get(LEGACY[key])
	if own is Dictionary:
		for k in (own as Dictionary):
			out[k] = own[k]
	if key == "powerup":
		if not (own is Dictionary and (own as Dictionary).has("powerups")) and b.get("black") is Dictionary:
			out["powerups"] = (b["black"] as Dictionary).get("powerups", [])
		out["powerup_chance"] = clampf(_num(out["powerup_chance"], 1.0), 0.0, 1.0)
	else:
		out["powerup_chance"] = 0.0
		out["powerups"] = []
		out["throw_distance"] = [5.0, 7.0]
	out["weight"] = maxf(_num(out.get("weight", 0.0), 0.0), 0.0)
	var td := range_of(out["throw_distance"], Vector2(5.0, 7.0))
	out["throw_distance"] = Vector2(maxf(td.x, 0.0), maxf(td.y, maxf(td.x, 0.0)))
	out["gems_small"] = maxi(int(_num(out["gems_small"], 8.0)), 0)
	out["gems_medium"] = maxi(int(_num(out["gems_medium"], 0.0)), 0)
	var co := range_of(out["coins"], Vector2.ZERO)
	out["coins"] = Vector2i(maxi(int(co.x), 0), maxi(int(co.y), maxi(int(co.x), 0)))
	out["powerups"] = weight_list(out["powerups"])
	return out


## Each kind's weight (exp, coins, powerup) in TYPES order, from the map's `barrels` block.
static func kind_weights(block) -> Array:
	var out: Array = []
	for k in TYPES:
		out.append(float(contents_of(block, k)["weight"]))
	return out


## A kind number drawn by the weights (`dice`); exp when every weight is 0.
static func pick_kind(block, dice: RandomNumberGenerator) -> int:
	var w := kind_weights(block)
	var total := 0.0
	for x: float in w:
		total += x
	if total <= 0.0:
		return EXP
	var r := dice.randf() * total
	for i in w.size():
		r -= float(w[i])
		if r < 0.0:
			return i
	return w.size() - 1


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
	if v is Vector2i:
		return Vector2(mini(v.x, v.y), maxi(v.x, v.y))
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


## Whether a barrel standing at `p` could show anything inside the camera's frustum (`planes`: Camera3D.get_frustum,
## facing out) grown by `margin` m. False with no planes (no camera: nobody sees).
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


## About how many turns of the clock fall due in `length` seconds of it (the first at `first`, then one every `every` on
## average, at most max_per_stage): the most respawns that many seconds can bring (the Level Editor shows the same sum).
static func turns_in(c: Dictionary, length: float) -> float:
	if not bool(c.get("enabled", false)) or length < float(c["first"]):
		return 0.0
	var ev: Vector2 = c["every"]
	var mean := maxf((ev.x + ev.y) * 0.5, EVERY_MIN)
	var n := 1.0 + floorf((length - float(c["first"])) / mean)
	var most := int(c.get("max_per_stage", 0))
	return minf(n, float(most)) if most > 0 else n


## One tick of the clock (`host` the BarrelField, `phase` the director's): in a phase it runs in, the next respawn when it
## is due.
func tick(host, delta: float, phase: int) -> void:
	if not on or not phase_allowed(cfg, phase):
		return
	clock += delta
	if clock < next_at:
		return
	var most := int(cfg["max_per_stage"])
	if most > 0 and spawned >= most:
		next_at = INF
		return
	var room := int(cfg["max_lying"])
	if room > 0 and int(host.alive_count()) >= room:
		skipped += 1
		next_at = clock + roll(cfg["every"], rng)
		return
	if not spawn_now(host):
		missed += 1
		next_at = clock + RETRY_S
		return
	next_at = clock + roll(cfg["every"], rng)


## A barrel now at a spot nobody sees (tools, tests, the due turn). False when no spot (or no slot) was found.
func spawn_now(host) -> bool:
	var at := find_spot(host)
	if at == Vector3.INF:
		return false
	if not bool(host.respawn_at(at, pick_kind(host.call("_block") if host.has_method("_block") else {}, rng))):
		return false
	spawned += 1
	return true


## A spot for a barrel (Vector3.INF when none): round the hero in the min_dist..max_dist band, then out to FAR_BAND x
## max_dist, each try asked of the host's rules (spawn_ok: the grounded spot or INF) and kept only off the screen.
func find_spot(host) -> Vector3:
	var hero: Vector3 = host.spawn_hero()
	if hero == Vector3.INF:
		return Vector3.INF
	var planes: Array = host.spawn_planes()
	var ctx = host.spawn_ctx()
	var margin := float(cfg.get("view_margin", 2.0))
	var lo := float(cfg.get("min_dist", 20.0))
	var hi := maxf(float(cfg.get("max_dist", 40.0)), lo)
	for band: Vector2 in [Vector2(lo, hi), Vector2(hi, maxf(hi * FAR_BAND, hi + 1.0))]:
		for k in range(TRIES):
			var a := rng.randf() * TAU
			var d := rng.randf_range(band.x, band.y)
			var q: Vector3 = host.spawn_ok(Vector3(hero.x + cos(a) * d, hero.y, hero.z + sin(a) * d), ctx)
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
