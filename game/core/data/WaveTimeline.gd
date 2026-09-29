## The wave director's script for one map. Continuous spawning with a growing live cap,
## a roster that changes over time, and timestamped events.
class_name WaveTimeline
extends Resource

@export var stage_length: float = 300.0
@export var stages: int = 3
## Multipliers per stage applied to enemy hp, damage, gold. Index 0 = stage 1. Endless continues from the last.
@export var stage_mults: Array = [1.0, 1.35, 1.8]
## Extra multiplier per minute in endless mode.
@export var endless_mult_per_minute: float = 0.1
## Extra live cap and extra creature speed for every stage after the first (stage 3 = twice this).
@export var cap_per_stage: int = 0
@export var speed_per_stage: float = 0.0
@export var cap_start: int = 100
@export var cap_per_minute: float = 10.0
@export var cap_max: int = 250
@export var hard_cap: int = 300
## The specials (pass 33.4: the rocketeer, the harpooner) come on their own clock instead of the roster:
## {"from": seconds into stage 1, "interval": [min, max], "max_alive": n, "pool": [{"enemy", "stage" (1-based, optional)}]}.
## From `from` on, whenever fewer than `max_alive` of them are alive, one arrives after a random interval that starts
## only once the last one is dead.
@export var specials: Dictionary = {}
## HP scaling with elapsed minutes: hp * (1 + hp_growth * t)^hp_power
@export var hp_growth: float = 0.08
@export var hp_power: float = 1.2
## Creatures grow with the hero: +this much HP and damage per hero level above 1 (pass 29: the crowd kept up with
## the clock but not with the build).
@export var level_hp_per_level: float = 0.0
@export var level_damage_per_level: float = 0.0
## Burst size range when the cap has room.
@export var burst_min: int = 5
@export var burst_max: int = 20
## Seconds between spawn checks.
@export var spawn_interval: float = 0.5
## Roster entries: {"t": seconds, "enemy": "goblin", "weight": 10, "until": optional seconds}
@export var roster: Array = []
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


## How many weapons a run may hold on each stage (the last entry holds for later stages and endless).
@export var weapon_cap: Array = [4, 5, 6]


func weapon_cap_at(stage: int) -> int:
	if weapon_cap.is_empty():
		return 6
	return int(weapon_cap[mini(maxi(stage, 0), weapon_cap.size() - 1)])


## How many lines a run may open by each stage (pass 34: two for the whole run was too few on stage 1).
@export var line_cap: Array = [2]


func line_cap_at(stage: int) -> int:
	if line_cap.is_empty():
		return 2
	return int(line_cap[mini(maxi(stage, 0), line_cap.size() - 1)])


func stage_mult(stage_index: int, minutes_into_endless: float = 0.0) -> float:
	if stage_mults.is_empty():
		return 1.0
	if stage_index < stage_mults.size():
		return float(stage_mults[stage_index])
	var last := float(stage_mults[stage_mults.size() - 1])
	return last * (1.0 + endless_mult_per_minute * minutes_into_endless)


func cap_at(t: float, stage_index: int = 0) -> int:
	return int(min(cap_start + cap_per_minute * (t / 60.0) + cap_per_stage * stage_index, cap_max))


func speed_mult(stage_index: int) -> float:
	return 1.0 + speed_per_stage * float(stage_index)


func hp_mult_at(t: float) -> float:
	return pow(1.0 + hp_growth * (t / 60.0), hp_power)


func roster_at(t: float) -> Array:
	var out: Array = []
	for r in roster:
		var start := float(r.get("t", 0.0))
		var until := float(r.get("until", 1e9))
		if t >= start and t < until:
			out.append(r)
	return out
