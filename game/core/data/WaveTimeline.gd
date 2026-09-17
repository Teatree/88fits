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
## HP scaling with elapsed minutes: hp * (1 + hp_growth * t)^hp_power
@export var hp_growth: float = 0.08
@export var hp_power: float = 1.2
## Burst size range when the cap has room.
@export var burst_min: int = 5
@export var burst_max: int = 20
## Seconds between spawn checks.
@export var spawn_interval: float = 0.5
## Roster entries: {"t": seconds, "enemy": "goblin", "weight": 10, "until": optional seconds}
@export var roster: Array = []
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
