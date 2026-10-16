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
const ROW_PACES := ["continuous", "waves"]
## A waves row's `every` when it names none (seconds).
const ROW_WAVE_EVERY_DEFAULT := 30.0


## Whether roster row `r` comes as waves (`pace` "waves"); any other value, or none, is continuous.
static func row_paced(r: Dictionary) -> bool:
	return str(r.get("pace", "continuous")) == "waves"


## Whether roster row `r` is in the director's continuous draw: a continuous row, or a waves row that trickles.
static func row_drawn(r: Dictionary) -> bool:
	return not row_paced(r) or bool(r.get("trickle", false))


## A waves row's seconds between waves (`every`, default ROW_WAVE_EVERY_DEFAULT); 0 or less = one wave only.
static func row_wave_every(r: Dictionary) -> float:
	var v = r.get("every", ROW_WAVE_EVERY_DEFAULT)
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
