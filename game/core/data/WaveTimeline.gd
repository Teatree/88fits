## The wave director's script for one map. Continuous spawning with a growing live cap,
## a roster that changes over time, and timestamped events.
class_name WaveTimeline
extends Resource

@export var stage_length: float = 300.0
@export var stages: int = 3
## Multipliers per stage applied to enemy hp, damage, gold. Index 0 = stage 1. Endless continues from the last.
@export var stage_mults: Array = [1.0, 1.35, 1.8]
## Endless (pass 43): every `endless_wave_seconds` the creatures get `endless_wave_mult` tougher, compounding (×1.12 a wave). The
## old linear `endless_mult_per_minute` still works for a map that sets it and no wave multiplier.
@export var endless_mult_per_minute: float = 0.0
@export var endless_wave_seconds: float = 60.0
@export var endless_wave_mult: float = 1.0
## The hell channel (pass 43): roster rows with `"channel": "hell"` spawn from their own cap, this fraction of the regular cap
## per stage (index 0 = stage 1), with their own weighted draw, so they never change the regular roster's mix or count.
@export var hell_cap: Array = []
## Extra live cap and extra creature speed for every stage after the first (stage 3 = twice this).
@export var cap_per_stage: int = 0
@export var speed_per_stage: float = 0.0
@export var cap_start: int = 100
@export var cap_per_minute: float = 10.0
@export var cap_max: int = 250
@export var hard_cap: int = 300
## The live cap over the run clock as [[seconds, cap], ...] (pass 45): when set it replaces the cap_start/cap_per_minute
## line, linear between the points, flat before the first and after the last; cap_per_stage and cap_max still apply.
@export var cap_curve: Array = []
## The boss fight's share of the cap (pass 45; the director kept 30% of the crowd while a boss lived).
@export var boss_cap_frac: float = 0.3
## Load units the director keeps up while the portal waits (pass 45): -1 = the frozen stage-end cap, 0 = nothing.
@export var portal_cap: int = 10
## How long after the boss dies the portal cap still spawns; below zero = for as long as the portal waits.
@export var portal_spawn_seconds: float = 30.0
## The specials (pass 33.4: the rocketeer, the harpooner) come on their own clock instead of the roster:
## {"from": seconds into stage 1, "interval": [min, max], "max_alive": n, "pool": [{"enemy", "stage" (1-based, optional)}]}.
## From `from` on, whenever fewer than `max_alive` of them are alive, one arrives after a random interval that starts
## only once the last one is dead.
@export var specials: Dictionary = {}
## HP scaling with elapsed minutes: hp * (1 + hp_growth * t)^hp_power (the old pair; `hp_curve` replaces it when set)
@export var hp_growth: float = 0.08
@export var hp_power: float = 1.2
## The multiplier on creature HP over the run clock as a curve (pass 54, the Level Editor's HP curve):
## {"mode": "points" | "formula", "points": [[t, mult], ...], "formula": {"kind": "linear" | "power" | "exponential",
## "a", "b"}}. `points` is linear between its points and flat outside; `formula` reads m = t / 60 minutes: linear
## 1 + a*m, power (1 + a*m)^b (the hp_growth / hp_power form), exponential (1 + a)^m. Both blocks may be present, `mode`
## picks (absent: points when there are any, else the formula). Empty = the hp_growth / hp_power pair (hp_mult_at).
@export var hp_curve: Dictionary = {}
## The same shape for creature damage over the run clock (pass 54; there was no time growth on damage): empty = 1.
@export var damage_curve: Dictionary = {}
## Creatures grow with the hero: +this much HP and damage per hero level above 1 (pass 29: the crowd kept up with
## the clock but not with the build).
@export var level_hp_per_level: float = 0.0
@export var level_damage_per_level: float = 0.0
## Burst size range when the cap has room.
@export var burst_min: int = 5
@export var burst_max: int = 20
## Seconds between spawn checks.
@export var spawn_interval: float = 0.5
## Roster entries: {"t": seconds, "enemy": "goblin", "weight": 10, "until": optional seconds}. Pass 53 (the wave
## schema, docs/waves_schema.md): a row may add `pack` (how many spawn together, default the creature's pack_size),
## `pattern` ("pack" at one point | "scatter" each at its own spawn point | "single" one a draw; pass 57: "ring" round the
## hero at WaveDirector.RING_RADIUS | "in_front" from the top of the screen), `variant` (an art
## variant code) and `stats` (overrides, EnemyDef.with_overrides). Pass 54: `weights` [[t, w], ...], the row's draw
## weight over the run clock as presence keyframes (linear between, flat outside; WaveDirector._roster_weight), in place
## of `weight` / `weight_late` (a row with those still slides as before); `id` is the editor's label, the game ignores it.
@export var roster: Array = []
## Explicit waves on top of the roster (pass 53): {"id", "name", "t", "until", "count", "burst", "every", "pattern",
## "respect_cap", "channel", "elite", "toast", "alts": [{"chance", "enemy", "variant", "pack", "stats"}]}. From `t` a
## burst of `burst` creatures every `every` seconds until `count` have come (0 = no total) or the clock reaches `until`;
## one alt is rolled per wave per run (a wave without alts carries enemy/variant/pack/stats itself). WaveDirector runs them.
@export var waves: Array = []
## when a roster row's `weight_late` is reached (seconds into the run)
@export var weight_late_t: float = 600.0
## Events: {"t": seconds, "type": "elite|swarm|boss|elite_every", ...}
##  elite {enemy?, mod?}          spawn one elite (random archetype from roster and random mod if omitted)
##  elite_every {interval}        repeat elite spawns every interval seconds from t
##  swarm {enemy, count}          ring of count enemies around the player, ignores cap
##  boss {enemy}                  spawn boss on the flats, slow regular spawns
##  elite_boss {enemy}            a mini-boss creature near the hero, no intro, no phase change; always drops a chest
@export var events: Array = []
## Pickups on the ground: {"first": 50, "interval": 75, "jitter": 20, "roster": [{"id": "heart", "weight": 6}, ...]}
## Empty = none on this map.
@export var pickups: Dictionary = {}
## Structures scattered at run start: {"count": 8, "min_spacing": 16, "roster": [ids, empty = all]}. Empty = none.
@export var structures: Dictionary = {}
## When each stage puts a weapon's whole path on the table (seconds into the stage), per stage; the last list holds
## for later stages. As many slots as the stage's cap and a spare, spread across the stage.
@export var path_times: Array = [[55, 115, 175, 230, 270], [35, 90, 145, 200, 245, 280]]


func path_times_at(stage: int) -> Array:
	if path_times.is_empty():
		return []
	var v = path_times[mini(maxi(stage, 0), path_times.size() - 1)]
	return v if v is Array else []


## How many weapons a run may hold on each stage (the last entry holds for later stages and endless). Pass 47: six all
## run (Garry: "We just give 6 slots for both and keep that static"); Run.weapon_cap() no longer reads it, the HUD's
## padlocks still do until the integration.
@export var weapon_cap: Array = [5, 5, 5]


func weapon_cap_at(stage: int) -> int:
	if weapon_cap.is_empty():
		return 5
	return int(weapon_cap[mini(maxi(stage, 0), weapon_cap.size() - 1)])


## How many lines a run may hold on each stage (pass 46 as the passive cap; the last entry holds for later stages and
## endless). Pass 47: six all run, and only the line items count (Run.line_cap(), passive items have no cap); kept for the
## HUD's padlocks until the integration.
@export var passive_cap: Array = [5, 5, 5]


func passive_cap_at(stage: int) -> int:
	if passive_cap.is_empty():
		return 5
	return int(passive_cap[mini(maxi(stage, 0), passive_cap.size() - 1)])


## Pass 46 (the schema; the lane that reads each one owns its rule, and each is off at its default):
## a kill count after which colour comes in, 0 = off
@export var colour_after_kills: int = 0
## a multiplier on every creature's health, 1 = as the creature's data says
@export var creature_hp_mult: float = 1.0
## A multiplier on EVERY hostile damage (pass 54, Garry: creatures hit 25% harder): bites, shots, spit, artillery
## missiles, kamikaze blasts, death bursts, boss and caster attacks and the Brander's ring. EnemyManager.creature_damage_mult
## carries it (WaveDirector._apply_mults). Red Canyon: 1.25. 1 = as the creature's data says.
@export var creature_damage_mult: float = 1.0
## Where the roster's bursts and the waves come from (pass 54, Garry: 55 / 15 / 15 / 15): {"mode": "sides" | "facing",
## "top", "bottom", "left", "right" (the weights of the four screen sides in camera space, top = up the screen = north
## in the fixed camera), "facing_share" (the old rule's share of spawns ahead of the hero, default 0.7),
## "facing_spread_deg" (within this many degrees of where he faces, default 60)}. "sides" draws a side by weight, then a
## point 19-24 m out within 45 degrees of that side's axis; "facing" (or an empty block) is the old rule, kept
## selectable. Rings, swarms, the portal wave, bosses and Elite bosses are placed as before (WaveDirector._spawn_point).
@export var spawn_sides: Dictionary = {}
## a cap on the contact damage the hero takes, 0 = off
@export var contact_cap: float = 0.0
## The map's pace for the hero's levels (pass 46): every level needs this many times the XP curve's amount
## (Run.xp_to_next). Red Canyon's is 2.0: its stages are 430/300 as long, and kills are limited by the spawns rather
## than the cap, so the longer stage pays more XP; measured with smoke_run perf=1 (pass 46), 2.0 brings the hero to the
## first boss at about level 22 after 7:10 where pass 45's reached level 21 after 5:00, levelling at about 0.7 times the pace.
@export var xp_need_mult: float = 1.0
## The pace knob (pass 48, Garry: "everyone 20% slower, with one setting to change it"; Run.move_pace reads it): the hero
## and every creature move at this fraction, a creature's charge and a boss's roll too, and its shots fly on a clock this
## much slower (EnemyManager.hostile_clock); every wind-up, telegraph and warning lasts 1/pace as long, so the slower hero
## still covers the same ground before it lands. Attack cooldowns and spawns do not change. 1 = as before.
@export var move_pace: float = 1.0
## The portal wait's wave (pass 48, read by the director, lane L5): when the boss dies one small wave comes round the hero,
## then nothing spawns until he steps through. Empty = off (portal_cap and portal_spawn_seconds hold, as for other maps).
@export var portal_wave: Dictionary = {}


func stage_mult(stage_index: int, seconds_into_endless: float = 0.0) -> float:
	if stage_mults.is_empty():
		return 1.0
	if stage_index < stage_mults.size():
		return float(stage_mults[stage_index])
	var last := float(stage_mults[stage_mults.size() - 1])
	if endless_wave_mult > 1.0:
		return last * pow(endless_wave_mult, float(endless_wave(seconds_into_endless)))
	return last * (1.0 + endless_mult_per_minute * seconds_into_endless / 60.0)


## Which endless wave `seconds_into_endless` falls in (0 = the first).
func endless_wave(seconds_into_endless: float) -> int:
	return int(floor(maxf(seconds_into_endless, 0.0) / maxf(endless_wave_seconds, 1.0)))


## The hell channel's cap on `stage_index`, as a fraction of the regular cap (0 = no channel on that stage).
func hell_cap_at(stage_index: int) -> float:
	if hell_cap.is_empty():
		return 0.0
	return float(hell_cap[mini(maxi(stage_index, 0), hell_cap.size() - 1)])


func cap_at(t: float, stage_index: int = 0) -> int:
	var base: float = cap_start + cap_per_minute * (t / 60.0)
	if not cap_curve.is_empty():
		base = _curve_at(t)
	return mini(int(base + cap_per_stage * stage_index), cap_max)


## The cap curve's value at `t` (sample_points).
func _curve_at(t: float) -> float:
	return sample_points(cap_curve, t)


## A point list's value at `t` (pass 54, the cap curve's rule for every curve: the cap, the HP and damage curves, a
## roster row's `weights`): `points` is [[t, value], ...] in time order; linear between two points, flat before the
## first and after the last; 0 for an empty list (the .tres round-trips the inner numbers as floats, so everything is
## cast; a malformed entry is skipped).
static func sample_points(points: Array, t: float) -> float:
	var prev_t := 0.0
	var prev_v := 0.0
	var seen := false
	for p in points:
		if not (p is Array) or (p as Array).size() < 2:
			continue
		var pt := float(p[0])
		var pv := float(p[1])
		if not seen:
			if t <= pt:
				return pv
			seen = true
		elif t <= pt:
			return lerpf(prev_v, pv, (t - prev_t) / maxf(pt - prev_t, 0.001))
		prev_t = pt
		prev_v = pv
	return prev_v


## A curve block's multiplier at `t` (pass 54; the hp_curve / damage_curve shape, see those fields): 1 when the block
## is empty or says nothing usable. `mode` "points" samples `points`; "formula" reads `formula` {kind, a, b} with
## m = t / 60 minutes: linear 1 + a*m, power (1 + a*m)^b, exponential (1 + a)^m (a defaults to 0.0977 and b to 1.25,
## Red Canyon's HP ramp; an unknown kind is 1). Without a `mode` the points are used when there are any, else the formula.
static func curve_mult(c: Dictionary, t: float) -> float:
	if c.is_empty():
		return 1.0
	var pts = c.get("points", [])
	var points: Array = pts if pts is Array else []
	var mode := str(c.get("mode", "points" if not points.is_empty() else "formula"))
	if mode == "points":
		return sample_points(points, t) if not points.is_empty() else 1.0
	if mode != "formula":
		return 1.0
	var fd = c.get("formula", {})
	var f: Dictionary = fd if fd is Dictionary else {}
	var a := float(f.get("a", 0.0977))
	var b := float(f.get("b", 1.25))
	var m := t / 60.0
	match str(f.get("kind", "power")):
		"linear":
			return 1.0 + a * m
		"power":
			return pow(maxf(1.0 + a * m, 0.0), b)
		"exponential":
			return pow(maxf(1.0 + a, 0.0), m)
	return 1.0


func speed_mult(stage_index: int) -> float:
	return 1.0 + speed_per_stage * float(stage_index)


## The creature HP multiplier at `t` seconds of the run clock: the `hp_curve` when the map has one (pass 54), else the
## hp_growth / hp_power ramp.
func hp_mult_at(t: float) -> float:
	if not hp_curve.is_empty():
		return curve_mult(hp_curve, t)
	return pow(1.0 + hp_growth * (t / 60.0), hp_power)


## The creature damage multiplier at `t` seconds of the run clock (pass 54): the `damage_curve`, 1 without one.
func damage_mult_at(t: float) -> float:
	return curve_mult(damage_curve, t) if not damage_curve.is_empty() else 1.0


func roster_at(t: float) -> Array:
	var out: Array = []
	for r in roster:
		var start := float(r.get("t", 0.0))
		var until := float(r.get("until", 1e9))
		if t >= start and t < until:
			out.append(r)
	return out
