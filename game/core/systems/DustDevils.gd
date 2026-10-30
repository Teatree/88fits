## Pass 113 (lane TWISTER; Garry: "Tornadoes still don't look like tornadoes and are quite confusing. Make them rarer
## too."). The map's dust devils: before pass 113 one circled the flats the whole run; now one comes now and then, forms
## where the player can see it, crosses the view and goes again. This node (made by the map, RedCanyon._build_movers) keeps
## the clock and the rules; each dust devil is a world/features/DustDevil.gd under it wearing a TornadoFx.
##
## The map's `timeline_data.dust_devils` block (DEFAULTS fill every key it leaves out; no block = the defaults):
##   enabled        false = no dust devils on this map.
##   first          seconds of the stage's own clock before the first one may come.
##   every          seconds from one forming to the next forming: a number or [min, max] rolled each time (at least
##                  EVERY_MIN). When one is due while max_alive stand, it comes as soon as one has gone.
##   life           seconds each one lasts, its forming and fading included: a number or [min, max].
##   max_alive      the most at once.
##   radius         metres round its middle that it grabs creatures in; the hero is thrown within radius + HERO_REACH
##                  (the ring drawn on the ground is that reach).
##   speed          metres a second it moves.
##   wander         how it moves: "cross" (across the view on a line that passes `miss` m to one side of where the hero
##                  stood when it formed, swaying a little), "drift" (a slow random wander), "loop" (pass 44's loop round
##                  the flats).
##   miss           metres to the side of the hero a crossing one passes.
##   form_dist      metres from the hero it forms, [min, max]: always inside the camera's view, on open sand.
##   form_seconds   seconds it takes to form: the dust skirt first, then the funnel rising out of it; it grabs nothing
##                  until it has formed.
##   fade_seconds   seconds it takes to go: it stops grabbing, thins away and its dust puffs out.
##   toss           {up, out, cooldown}: the hero's throw (pass 44's: 8 m/s up, 3.6 m/s out, once in 1.2 s).
##   lift           seconds a creature rides it (EnemyManager.lift_radius: spun round it, flung out, hurt on landing).
##   lift_height    metres a creature of size 1 rides up at its highest (x its size; pass 113 and before: 3.2).
##   size           the funnel's size (1 = 7 m tall, 0.6 m across the foot, 2.1 m across the top: pass 113's look); the
##                  dust round its foot follows `radius`.
##   opacity        how solid the funnel and its dust are, 0.5..1 (pass 113: 0.94; the skirt of dust 0.98 of it).
##   warn           true: the first one of a run says "DUST DEVIL" in a toast (never again that run).
## Pass 115 (lane POLISH; Garry: "Tornado should be a bit bigger, last 3 times longer when it does appear, be a bit more
## transparent and lift both enemies and heroes a bit higher"): radius 2.4 -> 3.0 and size 1.25, life [20, 30] ->
## [60, 90], opacity 0.94 -> 0.7, toss.up 8 -> 9.5 m/s (the hero's throw 1.33 -> 1.88 m high under his 24 m/s2),
## lift_height 3.2 -> 4.5 m.
##   in_boss, in_portal, in_endless   whether the clock runs (and they come) in the boss fight, the portal's countdown and
##                  Endless; one standing when its phase ends fades away.
## The clock counts only the seconds of the phases it runs in; the debug arena runs no clock (its WORLD tab calls one in).
class_name DustDevils
extends Node3D

const DEFAULTS := {
	"enabled": true, "first": 90.0, "every": [120.0, 180.0], "life": [60.0, 90.0], "max_alive": 1,
	"radius": 3.0, "speed": 1.4, "wander": "cross", "miss": 3.0, "form_dist": [7.0, 11.0],
	"form_seconds": 2.5, "fade_seconds": 2.0,
	"toss": {"up": 9.5, "out": 3.6, "cooldown": 1.2}, "lift": 1.7, "lift_height": 4.5,
	"size": 1.25, "opacity": 0.7,
	"warn": true, "in_boss": false, "in_portal": false, "in_endless": false,
}
const WANDERS := ["cross", "drift", "loop"]
## The least seconds between two (an `every` under it reads as this).
const EVERY_MIN := 10.0
## A due one that found no spot on the screen tries again this many seconds later.
const RETRY_S := 3.0
## Spots tried for one forming.
const TRIES := 40
## Metres past its grab radius the hero is thrown from (pass 44's 0.5): the ring on the ground is drawn there.
const HERO_REACH := 0.5
## The toast the first one of a run says.
const WARN_TEXT := "DUST DEVIL: keep out of its ring"
const WARN_COLOR := Color(0.96, 0.8, 0.52)
## Its sound (a loop): louder the nearer the nearest one is.
const SOUND := "wd_dust_devil"
const SOUND_NEAR := 6.0
const SOUND_FALLOFF := 1.1
## WaveDirector.Phase's order, read as numbers so nothing here names the director.
const PHASE_NORMAL := 0
const PHASE_BOSS := 1
const PHASE_PORTAL := 2
const PHASE_ENDLESS := 3

var map: Node
var game: Node
var cfg: Dictionary = {}
var on := false
## The clock: seconds of the phases it runs in. next_at: the clock's time the next one is due (INF: none).
var clock := 0.0
var next_at := INF
## This stage: how many formed, how many due turns found no spot.
var formed := 0
var missed := 0
var warned := false
var rng := RandomNumberGenerator.new()
var _set := false
var _loop_on := false


## The block whole (`block` the map's `dust_devils`; null or {} = the defaults), every key filled and in range.
static func config_of(block) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if block is Dictionary:
		for k in (block as Dictionary):
			if k == "toss" and block[k] is Dictionary:
				for tk in (block[k] as Dictionary):
					out["toss"][tk] = block[k][tk]
			else:
				out[k] = block[k]
	out["enabled"] = _bool(out["enabled"])
	out["first"] = maxf(_num(out["first"], 90.0), 0.0)
	var ev := range_of(out["every"], Vector2(120.0, 180.0))
	out["every"] = Vector2(maxf(ev.x, EVERY_MIN), maxf(ev.y, EVERY_MIN))
	var lf := range_of(out["life"], Vector2(60.0, 90.0))
	out["form_seconds"] = maxf(_num(out["form_seconds"], 2.5), 0.1)
	out["fade_seconds"] = maxf(_num(out["fade_seconds"], 2.0), 0.1)
	var least := float(out["form_seconds"]) + float(out["fade_seconds"]) + 1.0
	out["life"] = Vector2(maxf(lf.x, least), maxf(lf.y, least))
	out["max_alive"] = maxi(int(_num(out["max_alive"], 1.0)), 0)
	out["radius"] = maxf(_num(out["radius"], 3.0), 0.2)
	out["speed"] = maxf(_num(out["speed"], 1.4), 0.0)
	out["wander"] = str(out["wander"]) if WANDERS.has(str(out["wander"])) else "cross"
	out["miss"] = _num(out["miss"], 3.0)
	var fd := range_of(out["form_dist"], Vector2(7.0, 11.0))
	out["form_dist"] = Vector2(maxf(fd.x, 0.0), maxf(fd.y, maxf(fd.x, 0.0)))
	var ts: Dictionary = out["toss"] if out["toss"] is Dictionary else {}
	out["toss"] = {"up": maxf(_num(ts.get("up", 9.5), 9.5), 0.0), "out": _num(ts.get("out", 3.6), 3.6),
		"cooldown": maxf(_num(ts.get("cooldown", 1.2), 1.2), 0.0)}
	out["lift"] = maxf(_num(out["lift"], 1.7), 0.0)
	# pass 115 (lane POLISH): how high a creature rides, the funnel's size, how solid it is
	out["lift_height"] = maxf(_num(out["lift_height"], 4.5), 0.0)
	out["size"] = clampf(_num(out["size"], 1.25), 0.25, 4.0)
	out["opacity"] = clampf(_num(out["opacity"], 0.7), 0.5, 1.0)
	for k in ["warn", "in_boss", "in_portal", "in_endless"]:
		out[k] = _bool(out[k])
	return out


## The clock for a stage from the map's block (`seed_v` the run's seed, 0 = random dice).
func setup(block, seed_v: int = 0) -> void:
	_set = true
	cfg = config_of(block)
	on = bool(cfg["enabled"])
	clock = 0.0
	formed = 0
	missed = 0
	if seed_v != 0:
		rng.seed = hash([seed_v, "dust_devils"])
	else:
		rng.randomize()
	next_at = float(cfg["first"]) if on else INF


## Every dust devil standing (not yet gone).
func alive() -> Array:
	var out: Array = []
	for c in get_children():
		if c is DustDevil and not (c as DustDevil).gone:
			out.append(c)
	return out


## Whether the clock runs in the director's `phase` (WaveDirector.Phase as a number).
static func phase_allowed(c: Dictionary, phase: int) -> bool:
	match phase:
		PHASE_BOSS:
			return bool(c.get("in_boss", false))
		PHASE_PORTAL:
			return bool(c.get("in_portal", false))
		PHASE_ENDLESS:
			return bool(c.get("in_endless", false))
	return true


## About how many come in `length` seconds of the clock (the first at `first`, then one every `every` on average): the
## Level Editor shows the same sum.
static func count_in(c: Dictionary, length: float) -> float:
	if not bool(c.get("enabled", false)) or length < float(c["first"]):
		return 0.0
	var ev: Vector2 = c["every"]
	return 1.0 + floorf((length - float(c["first"])) / maxf((ev.x + ev.y) * 0.5, EVERY_MIN))


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	var t0 := Time.get_ticks_usec()
	if game == null:
		return
	if not _set:
		setup(_block(), _run_seed())
	if not bool(game.get("paused")):
		var d = game.get("director")
		var arena := _is_arena()
		if d != null and bool(d.get("running")) and not arena:
			tick(delta, int(d.get("phase")))
	_sound()
	Perf.add("dustdevil", t0)


## One tick of the clock in the director's `phase`.
func tick(delta: float, phase: int) -> void:
	if not on:
		return
	if not phase_allowed(cfg, phase):
		for dd: DustDevil in alive():
			dd.fade_out()
		return
	clock += delta
	if clock < next_at:
		return
	if alive().size() >= int(cfg["max_alive"]):
		return
	var hero := _hero()
	if hero == Vector3.INF:
		return
	var at := find_spot(hero)
	if at == Vector3.INF:
		missed += 1
		next_at = clock + RETRY_S
		return
	spawn(at, _cross_dir(at, hero))
	next_at = clock + roll(cfg["every"], rng)


## One now (the arena's button, tools): at `at` (INF: a spot on the screen by the rules) heading `dir` (zero: by its
## wander). Past max_alive the oldest is sent away. Null when no spot was found.
func call_one(at: Vector3 = Vector3.INF, dir: Vector3 = Vector3.ZERO) -> DustDevil:
	if not _set:
		setup(_block(), _run_seed())
	var hero := _hero()
	if at == Vector3.INF:
		if hero == Vector3.INF:
			return null
		at = find_spot(hero)
		if at == Vector3.INF:
			return null
	var standing := alive()
	if standing.size() >= maxi(int(cfg["max_alive"]), 1):
		(standing[0] as DustDevil).fade_out()
	if dir == Vector3.ZERO:
		dir = _cross_dir(at, hero) if hero != Vector3.INF else Vector3(1, 0, 0)
	return spawn(at, dir)


## Every one standing fades away now.
func send_away() -> void:
	for dd: DustDevil in alive():
		dd.fade_out()


## A dust devil at `at` heading `dir`, with this map's numbers.
func spawn(at: Vector3, dir: Vector3) -> DustDevil:
	var dd := DustDevil.new()
	dd.game = game
	dd.map = map
	dd.setup(cfg, at, dir, roll(cfg["life"], rng), rng.randi())
	add_child(dd)
	formed += 1
	if bool(cfg["warn"]) and not warned:
		warned = true
		var hud = game.get("hud") if game != null else null
		if hud != null and hud.has_method("toast"):
			hud.toast(WARN_TEXT, WARN_COLOR)
	return dd


## A spot for one to form (Vector3.INF when none): form_dist from the hero, inside the camera's view with its whole ring,
## inside the arena, out of the water and off the rocks.
func find_spot(hero: Vector3) -> Vector3:
	var planes := _planes()
	var fd: Vector2 = cfg.get("form_dist", Vector2(7.0, 11.0))
	var keep := float(cfg.get("radius", 2.4)) + HERO_REACH
	for k in range(TRIES):
		var a := rng.randf() * TAU
		var d := rng.randf_range(fd.x, fd.y)
		var p := Vector3(hero.x + cos(a) * d, hero.y, hero.z + sin(a) * d)
		p = spot_ok(p, keep)
		if p == Vector3.INF:
			continue
		if not planes.is_empty() and not inside(planes, p + Vector3(0, 0.5, 0), keep):
			continue
		return p
	return Vector3.INF


## `p` grounded when one may form there (Vector3.INF when not): inside 0.85 of the arena, out of the water, clear of the
## rocks.
func spot_ok(p: Vector3, keep: float) -> Vector3:
	if map == null:
		return Vector3(p.x, 0.0, p.z)
	var q := Vector2(p.x, p.z)
	if q.length() > float(map.get("arena_radius")) * 0.85:
		return Vector3.INF
	if map.has_method("in_water") and map.in_water(Vector3(p.x, 0, p.z)):
		return Vector3.INF
	for o: Vector3 in map.get("obstacles"):
		if q.distance_to(Vector2(o.x, o.y)) < o.z + keep * 0.5:
			return Vector3.INF
	return Vector3(p.x, map.height_at(p.x, p.z), p.z)


## Whether a sphere of `r` at `c` lies wholly inside the view (`planes` facing out).
static func inside(planes: Array, c: Vector3, r: float) -> bool:
	for pl: Plane in planes:
		if pl.distance_to(c) > -r:
			return false
	return true


## The way a crossing one heads: from `at` towards a point `miss` m to one side of the hero, flat.
func _cross_dir(at: Vector3, hero: Vector3) -> Vector3:
	var to := Vector3(hero.x - at.x, 0.0, hero.z - at.z)
	if to.length() < 0.01:
		to = Vector3(1, 0, 0)
	var side := Vector3(-to.z, 0.0, to.x).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
	var aim := Vector3(hero.x, 0.0, hero.z) + side * float(cfg.get("miss", 3.0))
	var d := Vector3(aim.x - at.x, 0.0, aim.z - at.z)
	return d.normalized() if d.length() > 0.01 else to.normalized()


func _hero() -> Vector3:
	if game == null or game.get("player") == null:
		return Vector3.INF
	return (game.player as Node3D).global_position


func _planes() -> Array:
	var rig = game.get("camera") if game != null else null
	var cam: Camera3D = null
	if rig is Camera3D:
		cam = rig
	elif rig is Object and is_instance_valid(rig) and rig.get("camera") is Camera3D:
		cam = rig.get("camera")
	return Array(cam.get_frustum()) if cam != null and cam.is_inside_tree() else []


func _block():
	var run: Node = get_tree().root.get_node_or_null("Run") if is_inside_tree() else null
	var md = run.get("map") if run else null
	var tl = md.timeline if md != null else null
	return tl.get("dust_devils") if tl != null else null


func _run_seed() -> int:
	var run: Node = get_tree().root.get_node_or_null("Run") if is_inside_tree() else null
	return int(run.get("rng_seed")) if run and run.get("rng_seed") != null else 0


func _is_arena() -> bool:
	var run: Node = get_tree().root.get_node_or_null("Run") if is_inside_tree() else null
	return run != null and bool(run.get("arena"))


## The loop while one stands, louder the nearer the nearest, fading with its strength; silent in the sim's fast mode.
func _sound() -> void:
	var audio: Node = get_tree().root.get_node_or_null("Audio") if is_inside_tree() else null
	var run: Node = get_tree().root.get_node_or_null("Run")
	if audio == null or (run != null and bool(run.get("sim_mode"))):
		return
	var best := INF
	var st := 0.0
	var hero := _hero()
	for dd: DustDevil in alive():
		var d := dd.global_position.distance_to(hero) if hero != Vector3.INF else 20.0
		if d < best:
			best = d
			st = dd.strength()
	if best == INF or st <= 0.01:
		if _loop_on:
			audio.stop_loop(SOUND)
			_loop_on = false
		return
	var p = audio.play_loop(SOUND)
	if p == null:
		return
	_loop_on = true
	var row: Dictionary = {}
	var reg: Node = get_tree().root.get_node_or_null("Registry")
	if reg and reg.get("soundmap"):
		row = reg.soundmap.entry(SOUND)
	var att := -clampf((best - SOUND_NEAR) * SOUND_FALLOFF, 0.0, 40.0)
	(p as AudioStreamPlayer).volume_db = float(row.get("volume_db", -14.0)) + att + linear_to_db(maxf(st, 0.02))


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PAUSED:
		if _loop_on and is_inside_tree():
			var audio: Node = get_tree().root.get_node_or_null("Audio")
			if audio:
				audio.stop_loop(SOUND)
		_loop_on = false


static func range_of(v, fallback: Vector2) -> Vector2:
	return BarrelSpawns.range_of(v, fallback)


static func roll(r: Vector2, dice: RandomNumberGenerator) -> float:
	return BarrelSpawns.roll(r, dice)


static func _num(v, fallback: float) -> float:
	return BarrelSpawns._num(v, fallback)


static func _bool(v) -> bool:
	return BarrelSpawns._bool(v)
