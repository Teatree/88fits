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
## Pass 58: each roster row, wave and event reads it once, at its own start (WaveDirector.fixed_numbers), and its creatures
## keep that value; a row that sets `stats.hp` takes none.
@export var hp_curve: Dictionary = {}
## The same shape for creature damage over the run clock (pass 54; there was no time growth on damage): empty = 1. Read
## at each source's start like hp_curve (pass 58); a row that sets `stats.damage` takes none.
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
## Pass 81 (lane PACE): `pace` "continuous" (the default: the row joins the director's continuous draw into the cap) |
## "waves" (the row's creatures come as waves of `count`, one every `every` s from `t` + `offset`, `respect_cap`, and
## `trickle` to be drawn continuously too; row_paced and the helpers at the end, WaveDirector._tick_row_waves).
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
## A multiplier on EVERY creature's pace (pass 60, Garry: "reduce the movement speed of all enemies by 10%" as "a
## multiplier for all"): every creature, Elite and boss walks, charges, rolls, winds up (1/mult as long) and shoots at
## this multiple; the hero is not affected (he keeps `move_pace`). EnemyManager folds it into its `pace`
## (WaveDirector._apply_mults, the arena too). Red Canyon: 0.9. 1 = as the creatures' data says.
@export var creature_speed_mult: float = 1.0
## Pass 72 (Garry: "Half all the knockback effect, it's too easy to make enemies basically unable to get to you"): a
## multiplier on EVERY push the hero's side gives a creature: a hit's knockback (weapons, mutations, evolutions, lines,
## passives, perks, the ball, the frisbee, thorns, the revive), a blast's throw (the Nuke, Thruster Burst, Grand Finale),
## Buck's Ram, the tornado's toss, the Guitarra chord's bounce and Bucking Bronco's throw distance (EnemyManager.hero_knock_mult).
## Never a creature's push on the hero, a hostile blast's throw of the crowd, knockback_resist, the pull or a stun.
## Red Canyon: 0.5. 1 = as the items' data says. A map that names none plays HERO_KNOCKBACK_DEFAULT (pass 72, lane
## INTEG: the halving is the game's rule, so a map JSON saved without the key, e.g. by an editor page opened before the
## key existed, still halves).
const HERO_KNOCKBACK_DEFAULT := 0.5
@export var hero_knockback_mult: float = HERO_KNOCKBACK_DEFAULT
## Pass 89 (Garry: "make it so the special attacks still knock player back. Like rocketeer rockets, dynamite, boss
## attacks, etc. but less than before. The regular melee attacks shouldn't have a knockback still"): the share of a
## special attack's push that reaches the hero (Player.knock_share: a charge, a blast, a rocket, the dynamite, a boulder,
## a slam, an eruption, a boss's attack, the Sniper's beam, a shot with its own weight); a bite or a plain shot never
## pushes him. 0 = nothing moves him; 1 = as before pass 88. The debug switch Settings.hero_knockback plays every push
## whole. A map that names none plays HERO_SPECIAL_KNOCK_DEFAULT.
const HERO_SPECIAL_KNOCK_DEFAULT := 0.5
@export var hero_special_knock: float = HERO_SPECIAL_KNOCK_DEFAULT
## Pass 69 (lane EN): the map's numbers for a variance special that the creature's own `variance.special` does not name:
## any of {"size", "hp", "damage", "xp", "tint_strength", "glow"} (EnemyDef.special_value: the creature's own, then this,
## then EnemyDef.SPECIAL_DEFAULTS). WaveDirector._apply_mults hands it to EnemyManager.special_defaults. {} = none.
@export var special_defaults: Dictionary = {}
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
## Pass 82 (lane XP): the XP growth type and its numbers (XpCurve): {"type": "quadratic" | "linear" | "exponential" |
## "power" | "table", <type>: {its numbers}}; {} = today's quadratic 15 + 6L + 0.5L^2. Every type times xp_need_mult.
@export var xp_curve: Dictionary = {}
## Pass 79 (lane MUT): whether a mutation level-up counts as a level for what grows with the hero's level (the creatures'
## level factor, his trait, Barrel Rush, Ram, Supply Drop; Run.card_level). False: they count the card levels only, so
## the same minute brings the same scaling as the curve before mutations came as level-ups.
@export var mutation_levels_scale: bool = false


## The pace knob (pass 48, Garry: "everyone 20% slower, with one setting to change it"; Run.move_pace reads it): the hero
## and every creature move at this fraction, a creature's charge and a boss's roll too, and its shots fly on a clock this
## much slower (EnemyManager.hostile_clock); every wind-up, telegraph and warning lasts 1/pace as long, so the slower hero
## still covers the same ground before it lands. Attack cooldowns and spawns do not change. 1 = as before.
@export var move_pace: float = 1.0
## The portal wait's wave (pass 48, read by the director, lane L5): when the boss dies one small wave comes round the hero,
## then nothing spawns until he steps through. Empty = off (portal_cap and portal_spawn_seconds hold, as for other maps).
@export var portal_wave: Dictionary = {}
## Boss HP pegged to the hero's DPS (pass 72, lane BOSS; Garry: "Boss Max HP should scale up the bigger the Player's DPS
## is in that moment. It shouldn't be 1 to 1, so there is still a 'reward' in getting more DPS"): {"enabled", "exponent",
## "window", "min", "max", "ref_dps": {boss id: DPS}}. When a boss arrives its HP is times
## boss_hp_mult(this, his damage a second over the last `window` seconds, the boss's ref_dps) (WaveDirector.boss_dps_scale;
## the debug arena never scales). enabled false = off; a ref_dps of 0 = that boss is never scaled.
## Pass 72, lane INTEG: a key the block leaves out (the whole block too) plays the game's own value, on with the measured
## references (BOSS_HP_SCALING_DEFAULTS, BOSS_REF_DPS_DEFAULTS), so a map JSON saved without the block (an editor page
## opened before it existed) still pegs the bosses; a boss neither the map nor the defaults name is never scaled.
@export var boss_hp_scaling: Dictionary = {}
## What boss_hp_scaling plays for a key it leaves out (the Level Editor's grey numbers).
const BOSS_HP_SCALING_DEFAULTS := {"enabled": true, "exponent": 0.5, "window": 45.0, "min": 0.75, "max": 3.0}
## Pass 73 (lane SNIPER; Garry: "Player Attacks should prioritize Special Enemies, Elites and Bosses once Player is close
## enough to them"): {"enabled", "reach"}. Every weapon that chooses its target takes a special (a coloured variance
## special or a gear-badge creature), an Elite or a boss within min(its own range, `reach` m) first, the nearest of them
## (EnemyManager.priority_target). A key the block leaves out plays TARGET_PRIORITY_DEFAULTS (on, 10 m), so a map saved
## without the block still prioritises; enabled false = off.
@export var target_priority: Dictionary = {}
const TARGET_PRIORITY_DEFAULTS := {"enabled": true, "reach": 10.0}
## The reference DPS of a boss the block's ref_dps does not name (lane BOSS measured them with tools/difficulty_probe.gd:
## the DPS over the 45 s before each boss, Calavera and the Drifter on stage builds; pass 72).
const BOSS_REF_DPS_DEFAULTS := {"tumbleweed_king": 600.0, "gila_grande": 4500.0, "brander": 20000.0}
## Growing out of the ground (pass 73, lane GROUND; Garry: "currently the enemies just kind of appear. Let's make it so
## that they grow out of the ground"): every creature that spawns rises out of the sand over `seconds` (an Elite or a
## boss by its kind over `big_seconds`), at the creatures' pace, the part still under cut by the billboard's ground-clip,
## in a small puff of dust `dust` times its size (0 = none, drawn only on the screen); no weapon chooses it as its target
## until it is `targetable` of the way up (EnemyManager.targetable; area damage still hits it), and it walks, bites and
## attacks only once it is all the way up. {"seconds", "big_seconds", "targetable", "dust"}; a key the block leaves out (the whole block too) plays
## SPAWN_RISE_DEFAULTS (WaveDirector._apply_mults hands them to EnemyManager.set_spawn_rise); seconds 0 = off.
@export var spawn_rise: Dictionary = {}
const SPAWN_RISE_DEFAULTS := {"seconds": 0.45, "big_seconds": 0.9, "targetable": 0.7, "dust": 1.0}
## Pass 80 (lane OASIS; Garry: "make the water slow everyone down when they walk though it, not by a lot, just 10%"): the
## share of the walking speed the water takes from anyone wading in it (the hero, every creature, Elites and bosses);
## never from a push, a knockback or a pull, nor from anyone in the air or under the sand (Player._wade_mult,
## EnemyManager._wade_mult). 0 = off. A map that names none plays WATER_SLOW_DEFAULT (the game's rule).
const WATER_SLOW_DEFAULT := 0.1
@export var water_slow: float = WATER_SLOW_DEFAULT
## Pass 80 (lane OASIS; Garry: "2 oasis at least per level generation in the red canyon, sometimes 3"): {"min", "max",
## "extra_chance", "gap"}: at least `min` oases a run, then one more with `extra_chance` each up to `max`, every two
## lakes' dishes at least `gap` m of open ground apart (RedCanyon._roll_oases). A key left out (the whole block too)
## plays OASES_DEFAULTS.
@export var oases: Dictionary = {}
const OASES_DEFAULTS := {"min": 2, "max": 3, "extra_chance": 0.35, "gap": 10.0}
## Pass 95 (lane WORLD; Garry: "in Vampire Survivors certain enemies despawn if the player walks far enough from them.
## Let's do that as well ... only applies to regular enemies ... the despawning happens out of Player's view ... they
## leave nothing behind"): {"enabled", "distance", "grace", "every", "keep_share"}. Every `every` seconds a regular
## creature (never a boss, an Elite, a special type, a coloured special, a boss's summon while its boss lives, a training
## dummy, one still rising, held or in the air) farther than `distance` m from the hero, off the screen and older than
## `grace` seconds since its spawn vanishes with no death, no blood, no drops and no kill (EnemyManager._tick_despawn);
## the director's live counts drop as for a death, so its row spawns again near the hero. `keep_share` is the share of
## those spared at each check (0 = all of them go). A key left out (the whole block too) plays DESPAWN_DEFAULTS;
## enabled false = off. The debug arena never despawns.
@export var despawn: Dictionary = {}
const DESPAWN_DEFAULTS := {"enabled": true, "distance": 40.0, "grace": 6.0, "every": 0.5, "keep_share": 0.0}
## Pass 111 (lane ENEMY; Garry: "Regular Enemies should walk considerably faster when they are far enough from the
## Player. This is an option that I can control and switch off ... This should also apply to Bosses, but not to Elites or
## Special Enemies"): {"enabled", "distance", "max_mult", "ramp", "bosses"}. A regular creature (and a boss while
## `bosses`) farther than `distance` m (flat) from the hero walks faster, rising smoothly to `max_mult` times its walk
## `ramp` m further out (EnemyManager.far_speed_mult). Never an Elite (by kind or modifier), a special type (the gear
## badge: the Vulture Raider, the harpooner, the Saiga Sniper), a coloured special or a training dummy; never a charge,
## a boss's scripted roll, a flee or a push (only the walk its brain chooses). A key left out (the whole block too) plays
## FAR_SPEED_DEFAULTS; enabled false = off.
@export var far_speed: Dictionary = {}
const FAR_SPEED_DEFAULTS := {"enabled": true, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": true}


## The far-speed block whole, every key filled (pass 111): what EnemyManager.set_far_speed takes.
func far_speed_cfg() -> Dictionary:
	var out := {}
	for k in FAR_SPEED_DEFAULTS:
		var dv = FAR_SPEED_DEFAULTS[k]
		var v = far_speed.get(k, dv)
		if dv is bool:
			out[k] = bool(v) if (v is bool or v is int or v is float) else dv
		else:
			out[k] = float(v) if (v is float or v is int) else float(dv)
	return out
## Pass 112 (lane BARREL; Garry: barrels "should respawn every now and then ... a chance of a power up dropping from
## them ... never spawn where Player can see them"): {"respawn": {...}, "brown": {...}, "black": {...}}: the clock that
## lays barrels again off the screen and what each barrel type holds (core/systems/BarrelSpawns.gd; read as it is, its
## RESPAWN_DEFAULTS and CONTENT_DEFAULTS fill gaps; no block = today's barrels: no respawn, no power-up).
@export var barrels: Dictionary = {}


## One number of despawn (pass 95): the map's, else DESPAWN_DEFAULTS' ("enabled" as 1 / 0).
func despawn_value(key: String) -> float:
	var v = despawn.get(key, DESPAWN_DEFAULTS.get(key, 0.0))
	if v is bool:
		return 1.0 if v else 0.0
	return float(v) if (v is float or v is int) else float(DESPAWN_DEFAULTS.get(key, 0.0))


## The despawn block whole, every key filled (pass 95): what EnemyManager.set_despawn takes.
func despawn_cfg() -> Dictionary:
	var out := {}
	for k in DESPAWN_DEFAULTS:
		out[k] = despawn_value(k)
	out["enabled"] = despawn_value("enabled") > 0.5
	return out


## One number of spawn_rise (pass 73): the map's, else SPAWN_RISE_DEFAULTS'.
func spawn_rise_value(key: String) -> float:
	var v = spawn_rise.get(key, SPAWN_RISE_DEFAULTS.get(key, 0.0))
	return float(v) if (v is float or v is int) else float(SPAWN_RISE_DEFAULTS.get(key, 0.0))


## The map's sides (pass 79, lane WORLD; Garry: "Map the sides are too orange"): the red-rock rim's colour
## ("#RRGGBB"; the rock painting is recoloured to it, its bands and cracks kept as light and dark) and the walls'
## {"near", "far", "farther" (the three rings of cliffs), "stone", "light" (the boundary wall's two courses), "cap",
## "riser", "boulders"}, each "#RRGGBB". The map reads them as it builds (RedCanyon._read_colours); "" or a key left out
## plays the map's own default (RedCanyon.ROCK_COLOR / WALL_COLORS). Pass 80 (lane WALLS): the rock is the ground outside
## the wall only, and the boundary a sandstone fort wall: "stone" its blocks, "light" its dressed trim, "cap" its walk and
## roofs, "riser" its shaded sides, "beams" (was "boulders") its vigas.
@export var rock_color: String = ""
@export var wall_colors: Dictionary = {}
## Pass 82 (lane SAND; Garry: "I want to be able to switch between them easily. Maybe in the LevelEditor"): which sand
## the ground is painted with, an id of RedCanyon.SANDS (its file and scale); "" or an id the map does not know plays
## RedCanyon.SAND_DEFAULT (pass 81's painting, art/env/sand.png).
@export var sand: String = ""


## A colour key's value as a Color (pass 79): "#RRGGBB" (or "RRGGBB", or [r, g, b] 0..1), else `fallback`.
static func color_of(v, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is String and Color.html_is_valid(str(v)):
		return Color.html(str(v))
	return fallback


## The boss HP multiplier for a hero dealing `dps` against the reference `ref` (pass 72): (dps / ref) ^ exponent, held
## between min and max. exponent 0.5: twice the reference DPS makes 1.41 times the HP, so the fight is 29% shorter
## (a stronger hero still wins faster, he does not breeze through); half of it makes 0.71 of the HP (the floor 0.75
## holds), so a weak build is not walled. 1 with scaling off or without a reference; an empty block plays the defaults.
static func boss_hp_mult(cfg: Dictionary, dps: float, ref: float) -> float:
	if not bool(cfg.get("enabled", BOSS_HP_SCALING_DEFAULTS["enabled"])) or ref <= 0.0:
		return 1.0
	var k := float(cfg.get("exponent", BOSS_HP_SCALING_DEFAULTS["exponent"]))
	var lo := float(cfg.get("min", BOSS_HP_SCALING_DEFAULTS["min"]))
	var hi := maxf(float(cfg.get("max", BOSS_HP_SCALING_DEFAULTS["max"])), lo)
	return clampf(pow(maxf(dps, 0.0) / ref, k), lo, hi)


## The reference DPS the map names for boss `id` (boss_hp_scaling.ref_dps), else BOSS_REF_DPS_DEFAULTS', else 0.
func boss_ref_dps(id: String) -> float:
	var r = boss_hp_scaling.get("ref_dps", {})
	if r is Dictionary and (r as Dictionary).has(id):
		return float(r[id])
	return float(BOSS_REF_DPS_DEFAULTS.get(id, 0.0))


## The DPS window's length in seconds (boss_hp_scaling.window, 45 by default).
func boss_dps_window() -> float:
	return float(boss_hp_scaling.get("window", BOSS_HP_SCALING_DEFAULTS["window"]))


## Pass 83 (lane SCALE; Garry: "I want it to take at least 25 seconds of Player's FULL DPS on Tumbleweed king to kill
## it. Then 40s for the next and a full minute to the last one"): boss_hp_scaling.mode "seconds" (the game's default
## now) gives a boss arriving through the director HP = max(its data HP as before, the hero's FULL DPS on it x its
## `seconds`), FULL DPS = HeroPower.full_dps(boss = true): every weapon's damage a second on one target every shot hits,
## crits and Big Game Hunter in (WaveDirector.boss_seconds_target). "dps" plays pass 72's peg to the recent real DPS
## (exponent, window, min, max, ref_dps); those keys do nothing in "seconds". A boss with no `seconds` (0) keeps its
## data HP. The debug arena never scales.
const BOSS_HP_MODE_DEFAULT := "seconds"
const BOSS_SECONDS_DEFAULTS := {"tumbleweed_king": 25.0, "gila_grande": 40.0, "brander": 60.0}


## The mode boss_hp_scaling plays: "seconds" or "dps" (anything else, or none, = BOSS_HP_MODE_DEFAULT).
func boss_hp_mode() -> String:
	var m := str(boss_hp_scaling.get("mode", BOSS_HP_MODE_DEFAULT))
	return m if m == "seconds" or m == "dps" else BOSS_HP_MODE_DEFAULT


## The seconds of full DPS boss `id` should take (boss_hp_scaling.seconds, else BOSS_SECONDS_DEFAULTS', else 0 = never).
func boss_seconds(id: String) -> float:
	var s = boss_hp_scaling.get("seconds", {})
	if s is Dictionary and (s as Dictionary).has(id):
		return maxf(float(s[id]), 0.0)
	return float(BOSS_SECONDS_DEFAULTS.get(id, 0.0))


## The seconds mode's HP: max(the data HP `base`, `full_dps` x `seconds` x (1 - the boss's damage reduction `dr`), so the
## kill takes `seconds` of full DPS after its armour); `base` when seconds or the DPS is 0.
static func boss_seconds_hp(base: float, full_dps: float, seconds: float, dr: float = 0.0) -> float:
	if seconds <= 0.0 or full_dps <= 0.0:
		return base
	return maxf(base, full_dps * (1.0 - clampf(dr, 0.0, 0.95)) * seconds)


## Pass 83 (lane SCALE; Garry: "add a modifier for the enemy HP scaling with the power level of the Player ... the higher
## the Player power level the higher the HP. Default scaling is 1, meaning no scaling at all"): every ordinary creature's
## HP (never a boss nor an Elite by its kind; Elite-modded creatures yes) times power_hp_factor(power_hp_scaling,
## power_hp_max, the hero's power (HeroPower)), read when a roster row, a wave or an event fixes its numbers (with the
## hero-level factor: pass 58's "the same wave does not change on the fly"). 1 = no scaling.
const POWER_HP_SCALING_DEFAULT := 1.0
const POWER_HP_MAX_DEFAULT := 10.0
@export var power_hp_scaling: float = POWER_HP_SCALING_DEFAULT
@export var power_hp_max: float = POWER_HP_MAX_DEFAULT


## HP x power ^ (scaling - 1), held between 1 / ceiling and the ceiling: scaling 1 = x1 at any power; 2 = the HP grows in
## step with the power (power 4: x4); 1.5 = with its square root (power 4: x2); below 1 the creatures soften as he grows.
## Power 1 (a fresh level-1 Drifter) is x1 at any scaling.
static func power_hp_factor(scaling: float, ceiling: float, power: float) -> float:
	if absf(scaling - 1.0) < 0.000001:
		return 1.0
	var hi := maxf(ceiling, 1.0)
	return clampf(pow(maxf(power, 0.01), scaling - 1.0), 1.0 / hi, hi)


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


# ---------------------------------------------------------------- a roster row's own pacing (pass 81, lane PACE)

## Garry (2026-10-15): "Add the ability to control the pacing of the waves. I mean the frequency at which enemy waves
## come." A roster row's `pace`: "continuous" (the default, as every row always was: drawn into the cap by its weight at
## every spawn check) or "waves": its creatures come as waves, wave k at `t` + `offset` + k x `every` while the row is
## open (t <= clock < until), each `count` of them (default the row's `pack`, else the creature's pack size) in the row's
## pattern; `respect_cap` (default true) and `trickle` (default false: not in the continuous draw between its waves).
## The schedule's maths is here (the tests and the editor's etches read the same rule); WaveDirector spawns it.
const ROW_PACES := ["continuous", "waves", "once"]
## A waves row's `every` when it names none (seconds).
const ROW_WAVE_EVERY_DEFAULT := 30.0


## Whether roster row `r` comes as waves (`pace` "waves", or pass 84's "once": one wave); any other value, or none, is
## continuous.
static func row_paced(r: Dictionary) -> bool:
	var p := str(r.get("pace", "continuous"))
	return p == "waves" or p == "once"


## Whether roster row `r` is in the director's continuous draw: a continuous row, or a waves row that trickles.
static func row_drawn(r: Dictionary) -> bool:
	return not row_paced(r) or bool(r.get("trickle", false))


## A waves row's seconds between waves (`every`, default ROW_WAVE_EVERY_DEFAULT); 0 or less = one wave only. Pass 84: a
## "once" row is 0 (its one wave), and `every` [min, max] reads as its middle here (the schedule's expected rhythm: the
## etches, the estimate); the director draws a fresh gap inside it at every wave (row_every_draw).
static func row_wave_every(r: Dictionary) -> float:
	if str(r.get("pace", "")) == "once":
		return 0.0
	var v = r.get("every", ROW_WAVE_EVERY_DEFAULT)
	if v is Array and not (v as Array).is_empty():
		var a: Array = v
		return (float(a[0]) + float(a[a.size() - 1])) * 0.5
	return float(v) if (v is float or v is int) else ROW_WAVE_EVERY_DEFAULT


## The run second of a waves row's first wave: its `t` plus its `offset` (never below 0).
static func row_wave_start(r: Dictionary) -> float:
	return float(r.get("t", 0.0)) + maxf(float(r.get("offset", 0.0)), 0.0)


## The index of the last wave of row `r` due at run second `t` (0 = the first), -1 before the first; a row whose `every`
## is 0 or less has one wave only (index 0). The open window (until) is the caller's: this is the schedule alone.
static func row_wave_index(r: Dictionary, t: float) -> int:
	var start := row_wave_start(r)
	if t < start:
		return -1
	var every := row_wave_every(r)
	if every <= 0.0:
		return 0
	# a hair of slack so a clock that lands exactly on a wave's second counts it (float steps)
	return int(floor((t - start) / every + 1e-6))


## The run second of wave `k` of row `r`.
static func row_wave_time(r: Dictionary, k: int) -> float:
	var every := row_wave_every(r)
	return row_wave_start(r) + (float(k) * every if every > 0.0 else 0.0)


## Every wave second of row `r` from its first up to `end` and before its `until` (the editor's yellow etches read the
## same rule, tools/level_editor/model.js rowWaveTimes), at most `limit` of them; [] for a continuous row. The presence
## gate (a wave due while the row weighs 0 does not come) is WaveDirector's: this is the schedule.
static func row_wave_times(r: Dictionary, end: float, limit: int = 10000) -> Array:
	var out: Array = []
	if not row_paced(r):
		return out
	var until := float(r.get("until", INF)) if r.has("until") and r.get("until") != null else INF
	var every := row_wave_every(r)
	var k := 0
	while k < limit:
		var tk := row_wave_time(r, k)
		if tk >= until or tk > end:
			break
		out.append(tk)
		if every <= 0.0:
			break
		k += 1
	return out


## A waves row's creatures a wave (`count`, default the row's `pack`, else `pack_size`, the creature's after the row's
## overrides), at least 1.
static func row_wave_count(r: Dictionary, pack_size: int) -> int:
	return maxi(int(r.get("count", r.get("pack", pack_size))), 1)


# ---------------------------------------------------------------- one spawning language (pass 84, lane SPAWN)

## Garry (2026-10-16): "there are too many ways of spawning an enemy right now" but "spawning options are important to
## me ... better add too many controls than too few". Every spawn the map makes is a roster row: the swarm, the coloured
## elite and the Elites-every events became rows (tools/migrate_timeline.py, the editor's Model.convertLegacy); an old
## map's events and waves[] still play through their own code. The row keys (docs/waves_schema.md "Pass 84"):
## `pace` "once" (one wave at t + offset), `every` [min, max] (a fresh gap each wave), `enemy` a list (with
## `enemy_weights`) or "roster" (each creature drawn from the mix rows live then by their elite_weight), `elite`
## ("random" | a modifier id: the coloured-elite spawn), `special` (every one its coloured special), `banner` (a toast as
## a wave first brings something), `ring_radius` (pattern ring: the classic even ring of that radius), `chance` and
## `t_jitter` (a once or waves row's roll and shift for the run), `role` and `name` (the editor's; the game ignores them).
## The density floor `floor_curve` [[t, n], ...]: the least creatures alive on the regular channel (WaveDirector
## _floor_fill); [] = none.
@export var floor_curve: Array = []

## The "roster" creature: drawn from the mix rows live at the second (WaveDirector._row_roster_pick).
const ROW_ENEMY_ROSTER := "roster"


## The density floor at run second `t` (sample_points of floor_curve), 0 without one.
func floor_at(t: float) -> float:
	return sample_points(floor_curve, t) if not floor_curve.is_empty() else 0.0


## Whether roster row `r` names one creature by its id (not a list, not "roster").
static func row_single_enemy(r: Dictionary) -> bool:
	var e = r.get("enemy", "")
	return not (e is Array) and str(e) != ROW_ENEMY_ROSTER


## The elite modifier a row's creatures wear: "" none, "random", or a modifier id.
static func row_elite(r: Dictionary) -> String:
	var e = r.get("elite", "")
	return "" if e == null or e is bool else str(e)


## Whether roster row `r` is in the mix (pass 84): a row that names one creature by its id, wears no elite modifier, is
## not all specials and is not a "once" row. Only the mix is read where the director asks "who is on the roster now":
## the portal wave, a coloured Elite's candidates, a "roster" row's draw and the pass 58 join (an event's numbers from
## the row bringing the same creature), so a swarm or an Elite that became a row plays as its event did.
static func row_in_mix(r: Dictionary) -> bool:
	return row_single_enemy(r) and row_elite(r) == "" and not bool(r.get("special", false)) and str(r.get("pace", "")) != "once"


## Whether a paced row runs on a timer (pass 84) instead of the fixed rhythm t + offset + k x every (pass 81): an
## `every` given as [min, max] (a fresh gap each wave) or an elite row (its clock runs faster with Hot Sauce, as the
## elite_every timers did). A timer's next wave is that gap after the wave it fired.
static func row_timer(r: Dictionary) -> bool:
	if not row_paced(r):
		return false
	return r.get("every") is Array or row_elite(r) != ""


## The mix rows of `rows` (row_in_mix).
static func mix_rows(rows: Array) -> Array:
	return rows.filter(func(r) -> bool: return r is Dictionary and row_in_mix(r))


# ---------------------------------------------------------------- stages as their own runs (pass 87, lane SGAME)

## Garry (2026-10-17): "Now Player Unlocks Stages and is only able to enter them after having completed the previous
## one. They differ in how long it takes to complete them as well." The map keeps ONE timeline on the run clock (the
## roster, the events, the curves, as before); each stage is a window of it, in order: {"id", "name", "length" (seconds
## before its boss), "boss" (an enemy id), "description", "difficulty" (the Stages menu's line), "filter" {"color":
## "#RRGGBB", "strength": 0..1} (the world's tint, lane SLOOK), "hell" (stage 3's red ground), "shot" (the menu's
## picture), "endless" (optional: Endless keys for this stage only)}. Stage k's window starts at the sum of the earlier
## lengths (Red Canyon 7:10 / 10:00 / 13:00: 0..430, 430..1030, 1030..1810). A run plays one stage (Run.start_stage):
## its clock starts at the window's start and stops at the window's end, where the stage's boss comes. [] = the fallback
## for a map without the block: `stages` windows of `stage_length` each, named "Stage k", the boss the boss event at the
## window's end, stage 3 and later hell (the pre-87 maps' look). Every index here is 0-based and clamped into the list.
@export var stage_list: Array = []
## The filter a stage plays without one: none.
const STAGE_FILTER_NONE := {"color": "#000000", "strength": 0.0}


## How many stages the map has: stage_list's, else `stages`.
func stage_count() -> int:
	if not stage_list.is_empty():
		return stage_list.size()
	return maxi(stages, 1)


## Stage `i` clamped into the map's stages.
func stage_clamp(i: int) -> int:
	return clampi(i, 0, stage_count() - 1)


## Stage `i`'s own entry as the map has it ({} in the fallback, for i < 0 or for a malformed entry).
func _stage_raw(i: int) -> Dictionary:
	if stage_list.is_empty() or i < 0:
		return {}
	var e = stage_list[stage_clamp(i)]
	return e if e is Dictionary else {}


## Stage `i`'s length in seconds (its window; the boss comes at its end): the entry's `length`, else `stage_length`.
func stage_len(i: int) -> float:
	var e := _stage_raw(i)
	return maxf(float(e.get("length", stage_length)), 1.0)


## The run second stage `i`'s window starts at: the earlier stages' lengths added up.
func stage_start(i: int) -> float:
	var s := 0.0
	for k in range(stage_clamp(i)):
		s += stage_len(k)
	return s


## The run second stage `i`'s window ends at (its boss's second).
func stage_end(i: int) -> float:
	return stage_start(i) + stage_len(stage_clamp(i))


## Stage `i`'s window on the run clock: Vector2(start, end).
func stage_window(i: int) -> Vector2:
	return Vector2(stage_start(i), stage_end(i))


## Every stage's length added up (the last window's end).
func total_length() -> float:
	return stage_end(stage_count() - 1)


## The stage whose window holds run second `t` (a boundary second belongs to the stage it starts; past the last window's
## end, the last stage).
func stage_at(t: float) -> int:
	var n := stage_count()
	var end := 0.0
	for k in range(n):
		end += stage_len(k)
		if t < end:
			return k
	return n - 1


## Stage `i`'s id ("s1"... in the fallback).
func stage_id(i: int) -> String:
	var e := _stage_raw(i)
	var id := str(e.get("id", ""))
	return id if id != "" else "s%d" % (stage_clamp(i) + 1)


## Stage `i`'s name ("Stage k" when the entry names none).
func stage_name(i: int) -> String:
	var e := _stage_raw(i)
	var nm := str(e.get("name", ""))
	return nm if nm != "" else "Stage %d" % (stage_clamp(i) + 1)


## Stage `i`'s boss: the entry's `boss`, else the boss event at its window's end (the last boss event inside the window
## when none sits on the end), else "" (a stage without a boss: its portal opens where the hero stands at its end).
func stage_boss(i: int) -> String:
	var e := _stage_raw(i)
	var b := str(e.get("boss", ""))
	if b != "":
		return b
	var w := stage_window(i)
	var best := ""
	var best_t := -INF
	for ev in events:
		if not (ev is Dictionary) or str(ev.get("type", "")) != "boss" or ev.get("enemy") is Array:
			continue
		var t := float(ev.get("t", 0.0))
		if absf(t - w.y) < 0.5:
			return str(ev.get("enemy", ""))
		if t > w.x and t <= w.y and t > best_t:
			best_t = t
			best = str(ev.get("enemy", ""))
	return best


## The boss stage `i`'s entry names itself ("" in the fallback or when it names none; stage_boss also reads the events).
func stage_boss_named(i: int) -> String:
	return str(_stage_raw(i).get("boss", ""))


## Whether stage `i` plays the hell look (the red ground, pass 43): the entry's `hell`, else stage 3 and later.
func stage_hell(i: int) -> bool:
	var e := _stage_raw(i)
	if e.has("hell"):
		return bool(e["hell"])
	return stage_clamp(i) >= 2


## Stage `i`'s world filter (lane SLOOK draws it): {"color": Color, "strength": float}; strength 0 = none.
func stage_filter(i: int) -> Dictionary:
	var e := _stage_raw(i)
	var f = e.get("filter", STAGE_FILTER_NONE)
	var fd: Dictionary = f if f is Dictionary else STAGE_FILTER_NONE
	return {"color": color_of(fd.get("color", "#000000"), Color.BLACK), "strength": clampf(float(fd.get("strength", 0.0)), 0.0, 1.0)}


## Pass 107 (lane XPT): stage `i`'s XP multiplier on every kill's XP (Garry: Stage 2's "EXP drop is too high ... a
## slightly faster level up progression than Stage 1, but not by much"): the entry's `xp_mult`, default 1 (no change),
## never below 0. Each stage is a fresh level-1 run since pass 87, so a stage whose roster is rich in XP (Nightfall's
## beetles, mummies, giants) levelled a fresh hero far faster than Sundown; this is the stage's own knob for it.
func stage_xp_mult(i: int) -> float:
	var e := _stage_raw(i)
	return maxf(float(e.get("xp_mult", 1.0)), 0.0)


## Stage `i`'s entry with every key filled (the Stages menu, analytics): index, id, name, length, boss, description,
## difficulty, filter {color "#rrggbb", strength}, hell, shot ("" when the entry names none), start, end, xp_mult
## (pass 107).
func stage_entry(i: int) -> Dictionary:
	var e := _stage_raw(i)
	var k := stage_clamp(i)
	var f := stage_filter(k)
	return {"index": k, "id": stage_id(k), "name": stage_name(k), "length": stage_len(k), "boss": stage_boss(k),
		"description": str(e.get("description", "")), "difficulty": str(e.get("difficulty", "")),
		"filter": {"color": "#" + (f["color"] as Color).to_html(false), "strength": float(f["strength"])},
		"hell": stage_hell(k), "shot": str(e.get("shot", "")), "start": stage_start(k), "end": stage_end(k),
		"xp_mult": stage_xp_mult(k)}


# ---------------------------------------------------------------- a stage's boss-fight window (pass 110, lane BOSS)

## Garry (2026-10-28): "I'd like some control over which enemies spawn during the Boss fight. Just add a 2 minute window
## in the Timeline where I can set up the cycle of enemies that will be spawning ... as long as the Boss Fight is
## continuing it will be those enemies at that pace that will be spawning." A stage entry's `boss_fight` block:
##   enabled    false keeps the block but plays the fight as before (default true)
##   length     seconds of one cycle (default BOSS_FIGHT_LENGTH_DEFAULT, at least 1); the cycle loops while the boss lives
##   max_count  the most creatures alive (BODIES, whatever their cap share) while the window spawns: the boss, its
##              summons and what is left of the stage's crowd count too; -1 = no limit but the hard cap (default 40)
##   roster     spawn rows with the roster's keys, every time on the FIGHT clock (0 = the boss arrives): t, until (absent
##              = the cycle's end), the presence keyframes, offset
## WaveDirector plays it through BossFightWindow from the boss's arrival until it dies; without a block (or enabled
## false) the fight keeps boss_cap_frac of the cap and draws the stage's last rows, as before.
const BOSS_FIGHT_LENGTH_DEFAULT := 120.0
const BOSS_FIGHT_MAX_COUNT_DEFAULT := 40


## Stage `i`'s boss-fight window as the map has it, {} when it has none or it is switched off (enabled false).
func boss_fight(i: int) -> Dictionary:
	var bf = _stage_raw(i).get("boss_fight")
	if not (bf is Dictionary) or not bool((bf as Dictionary).get("enabled", true)):
		return {}
	return bf


## Whether stage `i`'s boss fight plays its own window.
func has_boss_fight(i: int) -> bool:
	return not boss_fight(i).is_empty()


## Seconds of one cycle of stage `i`'s window (BOSS_FIGHT_LENGTH_DEFAULT without one), never under 1.
func boss_fight_length(i: int) -> float:
	return maxf(float(boss_fight(i).get("length", BOSS_FIGHT_LENGTH_DEFAULT)), 1.0)


## The most bodies alive while stage `i`'s window spawns (-1 = no limit but the hard cap).
func boss_fight_max_count(i: int) -> int:
	return maxi(int(boss_fight(i).get("max_count", BOSS_FIGHT_MAX_COUNT_DEFAULT)), -1)


## Stage `i`'s window rows (the Dictionaries only), [] without a window.
func boss_fight_rows(i: int) -> Array:
	var ro = boss_fight(i).get("roster", [])
	return (ro as Array).filter(func(r) -> bool: return r is Dictionary) if ro is Array else []


## The rows of `rows` open at fight second `ct` of a cycle (t <= ct < until; no until = open to the cycle's end).
static func boss_fight_open(rows: Array, ct: float) -> Array:
	var out: Array = []
	for r in rows:
		if not (r is Dictionary):
			continue
		if ct < float(r.get("t", 0.0)) or (r.get("until") != null and ct >= float(r["until"])):
			continue
		out.append(r)
	return out


# ---------------------------------------------------------------- Endless after a stage (pass 87, lane SGAME)

## Garry (2026-10-17): "Player kills the boss and the Portal that appears shows a 1 minute timer before the Endless Mode
## will activate ... Endless Mode consists of a huge wave of enemies appearing (with higher speed and HP) and every 10
## seconds the power of the next wave of enemies becomes stronger in both HP, ATK and a lil bit in Speed. Enemies still
## drop EXP, but modest amounts and drop coins very very rarely. The goal of this mode is to kill the Player." The map's
## `endless` block (a stage entry's own `endless` block wins key by key; a key neither names plays ENDLESS_DEFAULTS):
##   portal_seconds  the portal's countdown to Endless, on the run clock (it stands still behind every screen)
##   every           seconds between Endless waves
##   first_wave      creatures in the huge first wave; wave_size + wave_growth x (k - 2) in wave k >= 2
##   cap             the crowd kept up between the waves, x the stage-end cap (load units; 0 = the waves alone)
##   hp, atk, speed  wave 1's multipliers on the creatures (on the stage-end numbers: the late roster's fixed numbers)
##   hp_growth, atk_growth   each wave x (1 + this) on the last: COMPOUNDING (wave k = hp x (1 + hp_growth)^(k - 1))
##   speed_growth, speed_max LINEAR: wave k = speed x (1 + speed_growth x (k - 1)), never past speed_max
##   xp_share        a kill's XP in Endless, a share of what it would drop
##   coin_chance     a creature's coin roll happens only this share of the time (very rarely)
##   roster_window   the "late roster": the mix rows open in the stage's last this-many seconds
##   knock_resist_seconds, knock_resist_max   pass 103 (lane PLAY; Garry: "enemies get more and more knockback
##                   resistance with each minute (by minute 1.5 enemies don't have any knockback from not explosive weapons
##                   at all)"): every creature resists a push from the hero's side LINEARLY from 0 at Endless's start to
##                   knock_resist_max at knock_resist_seconds of Endless, then holds (endless_knock_resist; max 0 = off,
##                   the default, so a map that names neither plays as before); EnemyManager.endless_knock_share
##   knock_resist_exempt_tag      a weapon carrying this tag (WeaponDef.tags, "explosive") pushes as before
##   knock_resist_exempt_sources  hit sources that are blasts without a weapon ("nuke", "revive", "powder_keg", ...):
##                   an Array of ids or one comma-separated String (the Level Editor's text field)
@export var endless: Dictionary = {}
const ENDLESS_DEFAULTS := {"portal_seconds": 60.0, "every": 10.0, "first_wave": 120.0, "wave_size": 30.0,
	"wave_growth": 2.0, "cap": 1.0, "hp": 1.5, "atk": 1.2, "speed": 1.15, "hp_growth": 0.15, "atk_growth": 0.1,
	"speed_growth": 0.02, "speed_max": 1.6, "xp_share": 0.35, "coin_chance": 0.05, "roster_window": 60.0,
	"knock_resist_seconds": 90.0, "knock_resist_max": 0.0}
## pass 103 (lane PLAY): the exempt keys' defaults (not numbers, so not in ENDLESS_DEFAULTS)
const ENDLESS_KNOCK_EXEMPT_TAG := "explosive"
const ENDLESS_KNOCK_EXEMPT_SOURCES := ["nuke", "revive", "powder_keg", "loose_rocket", "blast"]


## One Endless number for stage `i` (-1 = the map's): the stage's own `endless` block, then the map's, then the default.
func endless_value(key: String, i: int = -1) -> float:
	var own = _stage_raw(i).get("endless", {}) if i >= 0 else {}
	if own is Dictionary and (own as Dictionary).has(key):
		return float(own[key])
	if endless.has(key):
		return float(endless[key])
	return float(ENDLESS_DEFAULTS.get(key, 0.0))


## The portal's countdown to Endless after stage `i`'s boss (seconds of the run clock).
func portal_seconds(i: int = -1) -> float:
	return maxf(endless_value("portal_seconds", i), 0.0)


## Endless wave `wave`'s (1-based) multipliers on the creatures after stage `i`: {hp, atk, speed}.
func endless_mults(wave: int, i: int = -1) -> Dictionary:
	var w := float(maxi(wave, 1) - 1)
	var hp := maxf(endless_value("hp", i), 0.0) * pow(maxf(1.0 + endless_value("hp_growth", i), 0.0), w)
	var atk := maxf(endless_value("atk", i), 0.0) * pow(maxf(1.0 + endless_value("atk_growth", i), 0.0), w)
	var sp0 := maxf(endless_value("speed", i), 0.0)
	var sp := minf(sp0 * (1.0 + endless_value("speed_growth", i) * w), maxf(endless_value("speed_max", i), sp0))
	return {"hp": hp, "atk": atk, "speed": sp}


## How many creatures Endless wave `wave` (1-based) brings after stage `i`.
func endless_wave_size(wave: int, i: int = -1) -> int:
	if wave <= 1:
		return maxi(int(endless_value("first_wave", i)), 0)
	return maxi(int(endless_value("wave_size", i) + endless_value("wave_growth", i) * float(wave - 2)), 0)


## The Endless wave (1-based) `seconds` into Endless after stage `i`.
func endless_wave_at(seconds: float, i: int = -1) -> int:
	return int(floor(maxf(seconds, 0.0) / maxf(endless_value("every", i), 1.0))) + 1


## Pass 103 (lane PLAY): the creatures' resistance (0..1) to a non-explosive push from the hero's side `seconds` into
## Endless after stage `i`: knock_resist_max x seconds / knock_resist_seconds, held at knock_resist_max after (0 seconds:
## the whole of it at once).
func endless_knock_resist(seconds: float, i: int = -1) -> float:
	var mx := clampf(endless_value("knock_resist_max", i), 0.0, 1.0)
	if mx <= 0.0:
		return 0.0
	var secs := endless_value("knock_resist_seconds", i)
	if secs <= 0.0:
		return mx
	return mx * clampf(maxf(seconds, 0.0) / secs, 0.0, 1.0)


## One raw (non-number) Endless key for stage `i`: the stage's own block, then the map's, then `fallback`.
func _endless_raw(key: String, i: int, fallback: Variant) -> Variant:
	var own = _stage_raw(i).get("endless", {}) if i >= 0 else {}
	if own is Dictionary and (own as Dictionary).has(key):
		return own[key]
	if endless.has(key):
		return endless[key]
	return fallback


## Pass 103: the weapon tag whose pushes Endless's resistance leaves whole ("explosive").
func endless_knock_exempt_tag(i: int = -1) -> String:
	return str(_endless_raw("knock_resist_exempt_tag", i, ENDLESS_KNOCK_EXEMPT_TAG)).strip_edges()


## Pass 103: the hit sources (ids without a weapon) whose pushes Endless's resistance leaves whole; an Array or a
## comma-separated String in the JSON.
func endless_knock_exempt_sources(i: int = -1) -> PackedStringArray:
	var v: Variant = _endless_raw("knock_resist_exempt_sources", i, ENDLESS_KNOCK_EXEMPT_SOURCES)
	var out := PackedStringArray()
	var parts: Array = v if v is Array else Array(str(v).split(",", false))
	for p in parts:
		var s := str(p).strip_edges()
		if s != "":
			out.append(s)
	return out
