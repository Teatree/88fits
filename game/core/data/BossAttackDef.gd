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
##
## Pass 113 (lane BOSS; Garry: "Each of the Bosses needs a Bullet Heaven type of attack. Those attacks are supposed to be
## rare and powerful. And while the boss is doing them it should be more challenging for Player to damage the boss";
## "Make it so they don't trigger immediately, and are rare, something like once every 45s"; "easy to detect as a Player.
## Big foreshadowing"): kind `pattern`, a bullet-heaven attack (docs/concepts/boss_bullet_heaven.md, option A of each boss).
##  pattern  never in the boss's attack cycle: its own `trigger` schedules it (the first not before `first_after` fight
##          seconds, when his HP falls under `first_at_hp` of his max or at the latest `first_by` seconds in; then again
##          `cooldown` seconds after the last one was completely over; pass 114: each of the three a number or a range
##          [min, max] rolled from the fight's dice), and it starts only between his attacks. A `tell` of `seconds`
##          (the banner word, the ground darkening in a ring round him, the wind-up sound, the music ducking, his own
##          wind-up `look`, the `shell` forming), then `timing.duration` seconds of bullets from the `emitters` (each a
##          spiral, ring, fan, sweep, wall or rose of `projectile` shots flying straight out at their own speed, gone past
##          `projectile.range` m), each bullet hitting the hero once for `hit.hit_frac` of his max HP and gone; the bullets
##          still in the air when it ends burn out over `timing.clear` seconds, harmless. He takes `guard.share` less damage
##          from the tell's start to the bullets' end (grey numbers, a grey bar, his glowing shell), then stands `spent`
##          {seconds} taking `damage_taken` x damage; his cycle resumes after timing.cooldown (0: his cooldown_between).
##          While it runs (tell, bullets, spent) nothing else of his starts and the boss-fight window's rows stand still.
##          EnemyManager's _pattern_* runs it, BossAttackFx draws the bullets (one MultiMesh), BossPatternFx the rest.
class_name BossAttackDef
extends ContentDef

const KINDS := ["rain", "volley", "ring", "slam", "script", "pattern"]
const SHAPES := ["rings", "grid", "spiral", "random"]
## (pass 113: the bullet-heaven looks, camera-facing paintings with a thick ink outline: BossAttackFx.BILLBOARD_LOOKS)
const LOOKS := ["spike", "spit", "pellet", "shard", "rock", "fire", "burning_tumbleweed", "venom_blob", "brand_fireball"]
## Pass 113: a pattern's emitter shapes, where an emitter aims, the boss's wind-up look, his shell while he is guarded.
const EMITTER_SHAPES := ["spiral", "ring", "fan", "sweep", "wall", "rose"]
const EMITTER_AIMS := ["hero", "track", "fixed", "random"]
const TELL_LOOKS := ["none", "spin", "rear", "drive"]
const SHELLS := ["none", "tornado", "scales", "pillar"]
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
		"range": 18.0, "hit_radius": 0.5, "trail": true, "wobble": 0.0},
	"pattern": {"shape": "rings", "center": "boss", "radius_min": 3.0, "radius_max": 16.0, "spacing": 3.2, "count": 0,
		"jitter": 0.2, "gap": 1.0, "turn": true, "order": "out", "spread_deg": 360.0, "aim": "hero", "waves": 1,
		"wave_gap": 0.5, "width": 1.2},
	"landing": {"radius": 0.9, "mode": "stagger"},
	"telegraph": {"kind": "circles", "color": "#ED4A5C", "seconds": 0.9, "all_at_once": false},
	"timing": {"windup": 1.0, "stagger": 1.5, "cooldown": 0.0, "hold": -1.0, "duration": 8.0, "clear": 0.6},
	"sounds": {"windup": "", "fire": "en_boss_attack", "land": ""},
	"spew": {"crouch": 0.35, "burst": 0.12, "mouth": 0.62, "squash": 0.82, "stretch": 1.25},
	"hit": {"hit_frac": 0.12},
	"trigger": {"first_after": 15.0, "first_at_hp": 0.6, "first_by": 45.0, "cooldown": 45.0},
	"guard": {"share": 0.8, "color": "#B9C3CE"},
	"spent": {"seconds": 2.5, "damage_taken": 1.5, "still": true},
	"tell": {"seconds": 2.0, "banner": "", "banner_color": "#E8502A", "ring_radius": 9.0, "ring_color": "#140A06",
		"ring_alpha": 0.5, "duck_db": -14.0, "look": "none"},
	"shell": {"look": "none", "color": "#C9A46A", "height": 7.0, "radius": 3.0, "opacity": 0.94, "sigil_radius": 0.0, "sigil_color": "#FF6A1A"},
}

## Pass 113: one emitter of a pattern (its `emitters` list) with the game's defaults for every key it leaves out (the Level
## Editor's grey numbers; tools/level_editor/boss_model.js EMITTER_DEFAULTS mirrors it, selftest_BOSS113.py checks). Times
## are seconds after the bullets begin (t), shares are of the attack's duration (T):
##   shape        spiral | ring | fan | sweep | wall | rose (EMITTER_SHAPES; see volley())
##   count        bullets a volley (a spiral's or a fan's on each arm; a ring's or a rose's all round; a wall's across)
##   arms         spiral / fan: that many arms evenly round
##   speed        m/s each bullet flies (the hero walks about 5)
##   rate         volleys a second while it is on
##   spin         degrees a second the whole emitter turns (+ = anticlockwise from above)
##   reverse_at   share of T at which the spin turns back the other way (-1 never)
##   spread_deg   a fan's (or a spiral arm's) width when it has more than one bullet
##   sweep_deg, sweep_hz   a sweep's swing: sweep_deg wide in all, sweep_hz full swings (there and back) a second
##   gap          a ring: degrees left open, facing its aim; a wall: metres left open at a random place
##   petals, depth, bloom_hz   a rose: petals round it, how deep the dips between them are (0 a plain ring, 1 the dips
##                stand still), the depth breathing between 0 and `depth` this many times a second (0 = held)
##   turn_every, turn_deg   a jump of turn_deg degrees every turn_every seconds (the mandala's turn)
##   offset_deg   turned this far from its aim
##   aim          hero (the hero's way as the bullets begin) | track (his way at every volley) | fixed (east) | random (a
##                way of its own every volley)
##   start, stop  shares of T it is on between
##   pulse_every, pulse_on, pulse_at   on for pulse_on s of every pulse_every s from pulse_at s (0 = always on)
##   finale_pull, pull_speed   the last finale_pull s of T it fires nothing and every bullet of it still flying turns back
##                towards the boss at pull_speed m/s, gone when it reaches him (the Brander's finale)
##   width        a wall's length across, m
const EMITTER_DEFAULTS := {"shape": "spiral", "count": 1, "arms": 1, "speed": 3.0, "rate": 4.0, "spin": 0.0,
	"reverse_at": -1.0, "spread_deg": 60.0, "sweep_deg": 0.0, "sweep_hz": 0.0, "gap": 0.0, "petals": 5, "depth": 0.7,
	"bloom_hz": 0.0, "turn_every": 0.0, "turn_deg": 0.0, "offset_deg": 0.0, "aim": "hero", "start": 0.0, "stop": 1.0,
	"pulse_every": 0.0, "pulse_on": 0.0, "pulse_at": 0.0, "finale_pull": 0.0, "pull_speed": 7.0, "width": 12.0}

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
## pass 113, kind "pattern": its emitters (EMITTER_DEFAULTS' keys each) and its groups (DEFAULTS: hit, trigger, guard,
## spent, tell, shell)
@export var emitters: Array = []
@export var hit: Dictionary = {}
@export var trigger: Dictionary = {}
@export var guard: Dictionary = {}
@export var spent: Dictionary = {}
@export var tell: Dictionary = {}
@export var shell: Dictionary = {}


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
			var steps := 0
			while steps < 4000:
				steps += 1
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


# ---------------------------------------------------------------- pass 113 (lane BOSS): the bullet-heaven pattern

## The fewest seconds of bullets a pattern plays (a shorter `timing.duration` is raised to it; the Level Editor warns under
## 5, Garry's "some 5+ seconds").
const PATTERN_MIN_DURATION := 0.5
## The hero's body round a bullet's hit radius (as a volley's shots: EnemyManager._tick_custom_volley).
const PATTERN_HERO_R := 0.3


## Whether this is a bullet-heaven pattern (kind "pattern"): never in the attack cycle, its own trigger plays it.
func is_pattern() -> bool:
	return attack_kind == "pattern"


## The pattern's emitters, each with every default filled in (EMITTER_DEFAULTS); entries that are not dictionaries are
## left out.
func emitters_full() -> Array:
	var out: Array = []
	for e in emitters:
		if e is Dictionary:
			out.append(emitter_full(e))
	return out


static func emitter_full(e: Dictionary) -> Dictionary:
	var out: Dictionary = EMITTER_DEFAULTS.duplicate()
	for k in e.keys():
		out[k] = e[k]
	return out


## Seconds of bullets (timing.duration, at least PATTERN_MIN_DURATION).
func pattern_duration() -> float:
	return maxf(num("timing", "duration"), PATTERN_MIN_DURATION)


## The tell's seconds (tell.seconds, never below 0).
func tell_seconds() -> float:
	return maxf(num("tell", "seconds"), 0.0)


## What a hit on the boss is multiplied by while he is guarded (1 - guard.share, the share held to 0..0.95).
func guard_mult() -> float:
	return 1.0 - clampf(num("guard", "share"), 0.0, 0.95)


## What a hit on the spent boss is multiplied by (spent.damage_taken, never below 0).
func spent_mult() -> float:
	return maxf(num("spent", "damage_taken"), 0.0)


## Whether the pattern is due for a boss `fight_t` seconds into his fight with `hp_frac` of his max HP left, having played
## `runs` patterns, the last ending (completely over: the tell, the bullets, their burn-out and his spent seconds) at fight
## second `last_end`: never before trigger.first_after; the first when his HP is at or under first_at_hp or at the latest
## first_by seconds in; the next ones `cooldown` seconds after the last one ended. Pass 114: `rolled` holds this fight's
## rolls of the keys that take a range (roll_triggers; BossPatterns keeps them); a key it lacks plays its range's low end.
func pattern_due(fight_t: float, hp_frac: float, runs: int, last_end: float, rolled: Dictionary = {}) -> bool:
	if fight_t < trigger_value("first_after", rolled):
		return false
	if runs <= 0:
		return hp_frac <= num("trigger", "first_at_hp") or fight_t >= trigger_value("first_by", rolled)
	return fight_t - last_end >= trigger_value("cooldown", rolled)


## Pass 114 (lane EDITOR; Garry: "add the option of randomization for the starting pattern ... make it a range between 10
## and 15 for example. Also ... those cooldowns should be after the attack is actually over"): trigger.first_after,
## first_by and cooldown each take a number (as before) or a range [min, max]. A range is rolled from the fight's own
## seeded dice (BossPatterns, never the global randf: a replay rolls the same): first_after and first_by once per fight,
## the cooldown afresh after each attack (BALANCING 57.EDITOR).
const TRIGGER_RANGES := ["first_after", "first_by", "cooldown"]


## Trigger key `key` as (low, high): a number v is (v, v); [a, b] is sorted; never below 0; anything else (or a list that
## is not two numbers) plays the default.
func trigger_range(key: String) -> Vector2:
	return range_of(val("trigger", key), float((DEFAULTS["trigger"] as Dictionary).get(key, 0.0)))


static func range_of(v: Variant, fallback: float) -> Vector2:
	if v is float or v is int:
		var f := maxf(float(v), 0.0)
		return Vector2(f, f)
	if v is Array:
		var a: Array = v
		if a.size() == 1 and (a[0] is float or a[0] is int):
			var g := maxf(float(a[0]), 0.0)
			return Vector2(g, g)
		if a.size() == 2 and (a[0] is float or a[0] is int) and (a[1] is float or a[1] is int):
			var lo := maxf(float(a[0]), 0.0)
			var hi := maxf(float(a[1]), 0.0)
			return Vector2(minf(lo, hi), maxf(lo, hi))
	var d := maxf(fallback, 0.0)
	return Vector2(d, d)


## Whether trigger key `key` is a range (its low and high ends differ).
func trigger_is_range(key: String) -> bool:
	var r := trigger_range(key)
	return r.y > r.x


## One roll of trigger key `key`: a range rolls uniformly from `rng` (one draw), a number plays as it is (no draw).
func roll_trigger(key: String, rng: RandomNumberGenerator) -> float:
	var r := trigger_range(key)
	if r.y <= r.x or rng == null:
		return r.x
	return rng.randf_range(r.x, r.y)


## A fight's rolls of the three keys, drawn in TRIGGER_RANGES' order from `rng`: {first_after, first_by, cooldown}.
func roll_triggers(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for k: String in TRIGGER_RANGES:
		out[k] = roll_trigger(k, rng)
	return out


## The value trigger key `key` plays now: this fight's roll in `rolled`, else its range's low end (a number: itself).
func trigger_value(key: String, rolled: Dictionary = {}) -> float:
	if rolled.has(key):
		return float(rolled[key])
	return trigger_range(key).x


## Whether emitter `e` (full) fires at `t` seconds into a `dur`-second pattern: between start and stop (shares of dur), in
## the on part of its pulse, and not in its finale pull.
static func emitter_on(e: Dictionary, t: float, dur: float) -> bool:
	if t < float(e["start"]) * dur or t >= float(e["stop"]) * dur:
		return false
	if pulling(e, t, dur):
		return false
	var every := float(e["pulse_every"])
	if every > 0.0:
		var at := float(e["pulse_at"])
		if t < at or fposmod(t - at, every) >= float(e["pulse_on"]):
			return false
	return true


## Whether emitter `e`'s finale pull is on at `t`: the last finale_pull seconds of the `dur`.
static func pulling(e: Dictionary, t: float, dur: float) -> bool:
	var fp := float(e["finale_pull"])
	return fp > 0.0 and t >= dur - fp and t < dur


## Degrees emitter `e` has turned by `t`: its spin (going back the other way after reverse_at x dur), plus a jump of
## turn_deg every turn_every seconds.
static func emitter_turned(e: Dictionary, t: float, dur: float) -> float:
	var spin := float(e["spin"])
	var deg := spin * t
	var ra := float(e["reverse_at"])
	if ra >= 0.0 and t > ra * dur:
		var t_rev := ra * dur
		deg = spin * t_rev - spin * (t - t_rev)
	var te := float(e["turn_every"])
	if te > 0.0:
		deg += floorf(t / te) * float(e["turn_deg"])
	return deg


## The middle of emitter `e`'s volley at `t` (radians, 0 = +X, turning towards +Z): `aim`, its offset, its turn, and a
## sweep's swing (sweep_deg wide in all, sweep_hz swings there and back a second).
static func emitter_angle(e: Dictionary, t: float, dur: float, aim: float) -> float:
	var deg := float(e["offset_deg"]) + emitter_turned(e, t, dur)
	if str(e["shape"]) == "sweep":
		deg += float(e["sweep_deg"]) * 0.5 * sin(TAU * float(e["sweep_hz"]) * t)
	return aim + deg_to_rad(deg)


## One volley of emitter `e` at `t` round `aim` (radians): a flat array of triples [angle (radians), speed (m/s), across
## (m: a wall's bullet starts that far to the side of the centre, at right angles to its flight)]. `hole` (0..1) places a
## wall's opening along it.
##   spiral, fan, sweep  `arms` arms evenly round, each `count` bullets over spread_deg (one bullet: straight down the arm)
##   ring    `count` bullets evenly round, `gap` degrees left open facing the aim
##   rose    `count` bullets evenly round; each flies at speed x (1 - depth + depth x petal), petal = (1 + cos(petals x its
##           angle from the aim)) / 2: a ring that opens into `petals` petals as it grows; the depth breathes with bloom_hz
##   wall    `count` bullets on a line `width` m long across the aim, all flying down the aim, `gap` m of it left open
static func volley(e: Dictionary, t: float, dur: float, aim: float, hole: float = 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var a := emitter_angle(e, t, dur, aim)
	var n := maxi(int(e["count"]), 1)
	var spd := maxf(float(e["speed"]), 0.1)
	match str(e["shape"]):
		"ring":
			var gap := deg_to_rad(clampf(float(e["gap"]), 0.0, 359.0))
			for k in range(n):
				var ak := a + TAU * float(k) / float(n)
				if gap > 0.0:
					ak = a + gap * 0.5 + (TAU - gap) * (float(k) + 0.5) / float(n)
				out.append(ak)
				out.append(spd)
				out.append(0.0)
		"rose":
			var petals := maxf(float(e["petals"]), 1.0)
			var depth := rose_depth(e, t)
			for k in range(n):
				var phi := TAU * float(k) / float(n)
				var petal := 0.5 + 0.5 * cos(petals * phi)
				out.append(a + phi)
				out.append(spd * (1.0 - depth + depth * petal))
				out.append(0.0)
		"wall":
			var w := maxf(float(e["width"]), 0.0)
			var opening := maxf(float(e["gap"]), 0.0)
			var at := (clampf(hole, 0.0, 1.0) - 0.5) * maxf(w - opening, 0.0)
			for k in range(n):
				var across := (-w * 0.5 + w * float(k) / float(n - 1)) if n > 1 else 0.0
				if opening > 0.0 and absf(across - at) < opening * 0.5:
					continue
				out.append(a)
				out.append(spd)
				out.append(across)
		_:
			var arms := maxi(int(e["arms"]), 1)
			var spread := deg_to_rad(clampf(float(e["spread_deg"]), 0.0, 360.0))
			for arm in range(arms):
				var ac := a + TAU * float(arm) / float(arms)
				for k in range(n):
					var ak := ac
					if n > 1:
						if spread >= TAU - 0.001:
							ak = ac + TAU * float(k) / float(n)
						else:
							ak = ac - spread * 0.5 + spread * float(k) / float(n - 1)
					out.append(ak)
					out.append(spd)
					out.append(0.0)
	return out


## A rose's dip depth at `t`: `depth`, breathing between 0 and it bloom_hz times a second when bloom_hz is above 0.
static func rose_depth(e: Dictionary, t: float) -> float:
	var depth := clampf(float(e["depth"]), 0.0, 1.0)
	var bh := float(e["bloom_hz"])
	if bh > 0.0:
		depth *= 0.5 + 0.5 * cos(TAU * bh * t)
	return depth


## The seconds emitter `e` fires its volleys at over a `dur`-second pattern, as the runner steps them at `dt`: the first as
## it comes on, then one every 1 / rate while it stays on (a pulse or a stop holds the clock; coming on again fires at once).
static func emitter_volley_times(e: Dictionary, dur: float, dt: float = 1.0 / 60.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rate := maxf(float(e["rate"]), 0.0)
	var acc := 0.0
	var was := false
	var step := maxf(dt, 0.001)
	# (the k-th step at k x step, as the Level Editor's mirror counts it: no drift from adding)
	var k := 0
	while float(k) * step < dur:
		var t := float(k) * step
		var on := rate > 0.0 and emitter_on(e, t, dur)
		if on:
			acc = 1.0 if not was else acc + step * rate
			while acc >= 1.0:
				acc -= 1.0
				out.append(t)
		was = on
		k += 1
	return out


## The pattern played out without a hero (the Level Editor's numbers and the tests): every bullet flying straight out from
## the centre, gone past projectile.range or at the end (the clear), a finale pull taking its emitter's bullets home.
## Returns {peak (most in the air at once), peak_t, fired (bullets in all), volleys}. Stepped at `dt`.
func simulate(dt: float = 1.0 / 30.0) -> Dictionary:
	var dur := pattern_duration()
	var rng_m := maxf(num("projectile", "range"), 0.5)
	var ems := emitters_full()
	var accs: Array = []
	var was: Array = []
	for _e in ems:
		accs.append(0.0)
		was.append(false)
	# bullets: [x, z, vx, vz, emitter]
	var live: Array = []
	var peak := 0
	var peak_t := 0.0
	var fired := 0
	var volleys := 0
	var step_i := 0
	while float(step_i) * dt < dur:
		var t := float(step_i) * dt
		for k in range(ems.size()):
			var e: Dictionary = ems[k]
			var on := float(e["rate"]) > 0.0 and emitter_on(e, t, dur)
			if on:
				accs[k] = 1.0 if not bool(was[k]) else float(accs[k]) + dt * float(e["rate"])
				while float(accs[k]) >= 1.0:
					accs[k] = float(accs[k]) - 1.0
					var v := volley(e, t, dur, 0.0, 0.5)
					volleys += 1
					for j in range(0, v.size(), 3):
						var dx := cos(v[j])
						var dz := sin(v[j])
						live.append([-dz * v[j + 2], dx * v[j + 2], dx * v[j + 1], dz * v[j + 1], k])
						fired += 1
			was[k] = on
		var keep: Array = []
		for b: Array in live:
			var be: Dictionary = ems[int(b[4])]
			if pulling(be, t, dur):
				var l := Vector2(b[0], b[1]).length()
				var step := maxf(float(be["pull_speed"]), 0.1) * dt
				if l <= step + 0.5:
					continue
				b[0] = float(b[0]) * (1.0 - step / l)
				b[1] = float(b[1]) * (1.0 - step / l)
			else:
				b[0] = float(b[0]) + float(b[2]) * dt
				b[1] = float(b[1]) + float(b[3]) * dt
			if Vector2(b[0], b[1]).length() > rng_m:
				continue
			keep.append(b)
		live = keep
		if live.size() > peak:
			peak = live.size()
			peak_t = t
		step_i += 1
	return {"peak": peak, "peak_t": peak_t, "fired": fired, "volleys": volleys}
