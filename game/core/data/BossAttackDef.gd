## A custom boss attack (pass 72, lane BOSS; Garry: "add the ability to create custom attacks for bosses. Like colouring
## the projectile, deciding the ranges, etc. Like create custom ones that I can name"). A content folder
## content/boss_attacks/<id>/<id>.json, made and edited in the Level Editor's Boss attacks tab, named by id in a boss's
## `boss.attacks` list next to the built-in scripts ({"name": "<id>"}; the entry's own keys override: min_range,
## max_range, reach, windup). EnemyManager runs it (_custom_attack_*), BossAttackFx draws its shots.
##
## `kind` is one of KINDS:
##  rain    projectiles thrown up and out, landing on the points of `pattern` round the boss (or the hero), each landing
##          circle telegraphed `telegraph.seconds` before it lands, staggered over `timing.stagger`; damage only inside a
##          landing circle (`landing.radius`). The Gila Grande's cactus_rain.
##  volley  straight shots out from the boss: `pattern.count` over `pattern.spread_deg` round its aim (`pattern.aim`
##          hero | random | fixed), `pattern.waves` of them `pattern.wave_gap` apart, flying `projectile.speed` for
##          `projectile.range` metres; a shot hits the hero once and is gone; red lines on the ground through the wind-up.
##  ring    rings racing out from the boss (`pattern.count` of them `pattern.wave_gap` apart) to `pattern.radius_max` at
##          `projectile.speed`, `pattern.width` thick; the hero is hit once by each ring that passes over him.
##  slam    a blast of `pattern.radius_max` round the boss (or the hero's spot at the wind-up: `pattern.center` "hero"),
##          telegraphed for the wind-up.
##  script  one of the built-in attacks by name (`script`: rumble, slam, roll, ...) with its own keys in `params`: a named,
##          tuned copy of a built-in.
## Every damage is `damage` times the boss's bite (its JSON `damage`) times the stage, the hero-level and the map's
## hostile factors, as the built-in attacks; knockback (m/s) and lift (m) are the hero's shove / throw.
##
## Pass 73 (lane GROUND; Garry: "each spot where the projectile will fall is highlighted. At once they wait for a little
## bit and then the boss does his animation of all those projectiles flying out of his mouth but they all land around
## the same time"): a rain's `landing.mode` "volley" throws every shot in one spew from the boss's mouth (`spew.mouth` up
## its painting), each leaving within `spew.burst` of the spew and landing within `timing.stagger` of the others (the
## nearest first: volley_times); `telegraph.all_at_once` lights every landing circle `telegraph.seconds` before the spew
## (the wind-up grows to that when it is shorter) and keeps it lit until its shot lands; the boss crouches through the
## last `spew.crouch` seconds of its wind-up (squashed to `spew.squash`) and stretches to `spew.stretch` as it spews.
class_name BossAttackDef
extends ContentDef

const KINDS := ["rain", "volley", "ring", "slam", "script"]
const SHAPES := ["rings", "grid", "spiral", "random"]
const LOOKS := ["spike", "spit", "pellet", "shard", "rock", "fire"]
const ORDERS := ["out", "in", "random", "sweep"]
const AIMS := ["hero", "random", "fixed"]
const CENTERS := ["boss", "hero"]
const TELEGRAPHS := ["circles", "lines", "ring", "none"]
## A rain's landing (pass 73): "stagger" one after another over timing.stagger, thrown from the boss's back (pass 72);
## "volley" all in one spew from its mouth, landing within timing.stagger of each other.
const LANDING_MODES := ["stagger", "volley"]
## The built-in attack names a `script` attack may wrap (EnemyManager's runner; tools/level_editor/vocab.py ATTACKS).
const SCRIPTS := ["roll", "spawn_ring", "slam_at", "blink", "burrow", "rain", "erupt", "spit_volley", "slam", "rumble",
	"brand", "tumbleweed_volley", "swoop", "boulder", "stomp", "tail_sniper"]

## Every group's keys with the game's defaults: what a key the file leaves out plays (the Level Editor's grey numbers;
## tools/level_editor/boss_attacks.js mirrors this table and selftest_BOSS.py checks they agree).
const DEFAULTS := {
	"projectile": {"look": "spike", "tint": "#D0242F", "size": 1.0, "glow": 1.0, "flight": 1.0, "arc": 6.0, "speed": 12.0,
		"range": 18.0, "hit_radius": 0.5, "trail": true},
	"pattern": {"shape": "rings", "center": "boss", "radius_min": 3.0, "radius_max": 16.0, "spacing": 3.2, "count": 0,
		"jitter": 0.2, "gap": 1.0, "turn": true, "order": "out", "spread_deg": 360.0, "aim": "hero", "waves": 1,
		"wave_gap": 0.5, "width": 1.2},
	"landing": {"radius": 0.9, "mode": "stagger"},
	"telegraph": {"kind": "circles", "color": "#ED4A5C", "seconds": 0.9, "all_at_once": false},
	"timing": {"windup": 1.0, "stagger": 1.5, "cooldown": 0.0, "hold": -1.0},
	"sounds": {"windup": "", "fire": "en_boss_attack", "land": ""},
	"spew": {"crouch": 0.35, "burst": 0.12, "mouth": 0.62, "squash": 0.82, "stretch": 1.25},
}

## rain | volley | ring | slam | script (the JSON's `kind`; `kind()` is ContentDef's content kind)
@export var attack_kind: String = "rain"
## What it is, in a line (the Level Editor's list and the hit log's words).
@export var doc: String = ""
@export var projectile: Dictionary = {}
@export var pattern: Dictionary = {}
@export var landing: Dictionary = {}
@export var telegraph: Dictionary = {}
@export var timing: Dictionary = {}
@export var sounds: Dictionary = {}
## pass 73: a volley rain's spew (DEFAULTS.spew: crouch, burst, mouth, squash, stretch)
@export var spew: Dictionary = {}
## times the boss's bite (its JSON `damage`), then the stage, hero-level and hostile factors
@export var damage: float = 0.75
## the hero's shove (m/s) where it hits him, and his throw up (m, 0 = a plain shove)
@export var knockback: float = 4.0
@export var lift: float = 0.0
## kind "script": the built-in attack it runs and that attack's own keys
@export var script_name: String = ""
@export var params: Dictionary = {}


func kind() -> String:
	return "boss_attack"


## A key of a group with the game's default when the file leaves it out (or names a group that is not a Dictionary).
func val(group: String, key: String) -> Variant:
	var g = get(group)
	if g is Dictionary and (g as Dictionary).has(key):
		return (g as Dictionary)[key]
	return (DEFAULTS.get(group, {}) as Dictionary).get(key)


func num(group: String, key: String) -> float:
	var v = val(group, key)
	return float(v) if (v is float or v is int) else 0.0


func text(group: String, key: String) -> String:
	var v = val(group, key)
	return str(v) if v != null else ""


func flag(group: String, key: String) -> bool:
	return bool(val(group, key))


func tint() -> Color:
	return color_of(text("projectile", "tint"), Color(0.82, 0.14, 0.18))


func telegraph_color() -> Color:
	return color_of(text("telegraph", "color"), Color(0.93, 0.29, 0.36))


static func color_of(s: String, fallback: Color) -> Color:
	if s == "" or not Color.html_is_valid(s):
		return fallback
	return Color.html(s)


## The least centre-to-centre distance two landing circles keep: both radii and the free gap between their edges.
func min_distance() -> float:
	return 2.0 * maxf(num("landing", "radius"), 0.0) + maxf(num("pattern", "gap"), 0.0)


## The landing points of a rain as offsets round its centre (x, z), in landing order (`pattern.order`). See points().
func rain_points(rng: RandomNumberGenerator) -> PackedVector2Array:
	return points(pattern_full(), maxf(num("landing", "radius"), 0.0), rng)


## The pattern block with every default filled in.
func pattern_full() -> Dictionary:
	var out: Dictionary = (DEFAULTS["pattern"] as Dictionary).duplicate()
	for k in pattern.keys():
		out[k] = pattern[k]
	return out


## The landing points of a pattern `pat` (DEFAULTS.pattern's keys) for circles of `land_r`, as offsets (x, z) round the
## centre: laid out by `shape` inside the ring radius_min..radius_max about `spacing` apart, each moved by up to
## `jitter` x spacing / 2 (never so far that two could close past the gap), the whole turned at random when `turn`, then
## THE GAP RULE: a point closer than 2 x land_r + gap to one already kept is dropped, so between any two neighbouring
## circles there is always `gap` metres of free sand (the hero's way through). `count` > 0 keeps that many (the first in
## landing order). Ordered by `order`: out (inside first), in (outside first), random, sweep (round by angle).
static func points(pat: Dictionary, land_r: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var spacing := maxf(float(pat.get("spacing", 3.2)), 0.3)
	var gap := maxf(float(pat.get("gap", 1.0)), 0.0)
	var dmin := 2.0 * maxf(land_r, 0.0) + gap
	spacing = maxf(spacing, dmin)
	var rmin := maxf(float(pat.get("radius_min", 3.0)), 0.0)
	var rmax := maxf(float(pat.get("radius_max", 16.0)), rmin)
	# the jitter never closes two layout neighbours past the rule (layouts keep at least `spacing` between them)
	var jit := minf(clampf(float(pat.get("jitter", 0.2)), 0.0, 1.0) * spacing * 0.5, maxf(spacing - dmin, 0.0) * 0.5)
	var turn := rng.randf() * TAU if bool(pat.get("turn", true)) else 0.0
	var raw: Array = []
	match str(pat.get("shape", "rings")):
		"grid":
			# a hex grid: rows `spacing` x 0.866 apart, every other row half a step along
			var dy := spacing * 0.8660254
			var rows := int(ceil(rmax / dy)) + 1
			for ry in range(-rows, rows + 1):
				var y := float(ry) * dy
				var off := spacing * 0.5 if absi(ry) % 2 == 1 else 0.0
				var cols := int(ceil(rmax / spacing)) + 1
				for cx in range(-cols, cols + 1):
					var p := Vector2(float(cx) * spacing + off, y)
					var l := p.length()
					if l >= rmin - 0.001 and l <= rmax + 0.001:
						raw.append(p.rotated(turn))
		"spiral":
			# a sunflower (Vogel) spiral at the density of a hex grid of `spacing`
			var c := spacing * sqrt(0.8660254 / PI)
			var n := int(floor(pow(rmin / c, 2.0)))
			var golden := PI * (3.0 - sqrt(5.0))
			var guard := 0
			while guard < 4000:
				guard += 1
				var r := c * sqrt(float(n) + 0.5)
				if r > rmax:
					break
				if r >= rmin:
					raw.append(Vector2(cos(float(n) * golden + turn), sin(float(n) * golden + turn)) * r)
				n += 1
		"random":
			# darts thrown evenly over the ring's area, each kept only `spacing` x 0.9 clear of the ones before (a Poisson
			# disc); as many as fit
			var want := int((PI * (rmax * rmax - rmin * rmin)) / (0.8660254 * spacing * spacing)) + 1
			var tries := want * 30
			var keep_d := maxf(spacing * 0.9, dmin)
			while tries > 0 and raw.size() < want:
				tries -= 1
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf_range(rmin * rmin, rmax * rmax))
				var p := Vector2(cos(a), sin(a)) * r
				var ok := true
				for q: Vector2 in raw:
					if p.distance_to(q) < keep_d:
						ok = false
						break
				if ok:
					raw.append(p)
		_:
			# "rings": rings `step` apart from radius_min out, each with as many points as fit `spacing` round it, every
			# other ring turned half a step (staggered like a hex grid)
			var step := maxf(spacing * 0.87, dmin + 2.0 * jit)
			var r := rmin
			var k := 0
			if r < 0.001:
				raw.append(Vector2.ZERO)
				r = step
				k = 1
			while r <= rmax + 0.001:
				var n := maxi(int(floor(TAU * r / spacing)), 1)
				var off := (0.5 * TAU / float(n)) if k % 2 == 1 else 0.0
				for j in range(n):
					var a := off + TAU * float(j) / float(n) + turn
					raw.append(Vector2(cos(a), sin(a)) * r)
				r += step
				k += 1
	# the jitter
	if jit > 0.0:
		for idx in range(raw.size()):
			var a := rng.randf() * TAU
			raw[idx] = (raw[idx] as Vector2) + Vector2(cos(a), sin(a)) * rng.randf() * jit
	# the landing order
	var order := str(pat.get("order", "out"))
	var keyed: Array = []
	for p: Vector2 in raw:
		var key := 0.0
		match order:
			"in":
				key = -p.length()
			"random":
				key = rng.randf()
			"sweep":
				key = fposmod(p.angle() - turn, TAU)
			_:
				key = p.length()
		keyed.append([key, p])
	keyed.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	# the gap rule, then the count
	var out := PackedVector2Array()
	var cap := int(pat.get("count", 0))
	for e: Array in keyed:
		var p: Vector2 = e[1]
		var clear := true
		for q: Vector2 in out:
			if p.distance_to(q) < dmin - 0.0001:
				clear = false
				break
		if not clear:
			continue
		out.append(p)
		if cap > 0 and out.size() >= cap:
			break
	return out


## The smallest free gap between two circles of `land_r` on `pts` (edge to edge, metres); INF for fewer than two.
static func smallest_gap(pts: PackedVector2Array, land_r: float) -> float:
	var best := INF
	for a in range(pts.size()):
		for b in range(a + 1, pts.size()):
			best = minf(best, pts[a].distance_to(pts[b]) - 2.0 * land_r)
	return best


## Each point's landing time in the rain's clock (seconds after it fires): its share of `stagger` by its place in the
## landing order (the first at 0, the last at `stagger`), plus the flight. Same order as `pts`.
static func land_times(n: int, stagger: float, flight: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for k in range(n):
		out[k] = maxf(flight, 0.05) + (maxf(stagger, 0.0) * float(k) / float(maxi(n - 1, 1)) if n > 1 else 0.0)
	return out


## Pass 73: whether this rain throws every shot in one spew from the boss's mouth (landing.mode "volley").
func is_volley() -> bool:
	return attack_kind == "rain" and text("landing", "mode") == "volley"


## Pass 73: whether this rain lights every landing circle at once before the spikes leave (telegraph.all_at_once).
func lit_at_once() -> bool:
	return attack_kind == "rain" and flag("telegraph", "all_at_once") and text("telegraph", "kind") != "none"


## The wind-up the runner plays (data seconds, x 1/pace on the map): timing.windup, or for a rain that lights its circles
## all at once at least telegraph.seconds, so the circles can show that long before the spew (pass 73).
func windup_seconds() -> float:
	var w := maxf(num("timing", "windup"), 0.0)
	if attack_kind == "rain" and flag("telegraph", "all_at_once"):
		w = maxf(w, maxf(num("telegraph", "seconds"), 0.0))
	return w


## A volley rain's times (pass 73, lane GROUND): every shot leaves within `burst` seconds of the spew (at random) and flies
## `flight` seconds to the spot nearest the centre, up to `stagger - burst` longer to the farthest (by its distance from
## the centre), so they all land within `stagger` seconds of each other, the nearest first. [departs, lands] in shot-clock
## seconds after the spew, in the order of `pts`.
static func volley_times(pts: PackedVector2Array, flight: float, stagger: float, burst: float, rng: RandomNumberGenerator) -> Array:
	var n := pts.size()
	var dep := PackedFloat32Array()
	dep.resize(n)
	var land := PackedFloat32Array()
	land.resize(n)
	var fl := maxf(flight, 0.05)
	var st := maxf(stagger, 0.0)
	var b := clampf(burst, 0.0, st)
	var dlo := INF
	var dhi := 0.0
	for p: Vector2 in pts:
		dlo = minf(dlo, p.length())
		dhi = maxf(dhi, p.length())
	for k in range(n):
		var dn := (pts[k].length() - dlo) / (dhi - dlo) if dhi - dlo > 0.001 else 0.0
		dep[k] = b * rng.randf()
		land[k] = dep[k] + fl + (st - b) * dn
	return [dep, land]


## The entry the attack runner plays for this attack, from the boss's list entry `entry` ({"name": id, ...overrides}):
## a `script` attack becomes its built-in (`params` with `name` = `script_name`); any other kind keeps its id as the name
## (no built-in matches it, so the runner's fire step hands it to EnemyManager._custom_attack_fire) with "custom" = its
## id, its wind-up (windup_seconds, pass 73) and no built-in telegraph. The entry's own keys (min_range, max_range,
## reach, windup) win.
func runner_entry(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if attack_kind == "script":
		out = params.duplicate(true)
		out["name"] = script_name
	else:
		out = {"name": id, "custom": id, "windup": windup_seconds(), "telegraph": "none"}
	for k in entry.keys():
		if str(k) != "name":
			out[k] = entry[k]
	return out
