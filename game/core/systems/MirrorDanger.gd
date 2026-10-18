## The Upgrade board's Stakes (pass 88, lane MIRROR; Garry: "Difficulty - Increases regular enemies movement speed, HP and
## ATK and increases the coins and exp (we don't write that in the description, and it's less than the difficulty
## increase)" and "BOSS - Increases Boss (and Elites) movement speed, HP and ATK and increases the coins and exp").
##
## Two families of player stats, each a sum of the ranks bought (op "add", 0 without any), read here:
##   regular creatures (everything that is not a boss or an Elite by its kind; an elite-modded or special creature is a
##   regular one): danger_hp, danger_attack, danger_speed, danger_bounty;
##   bosses and Elites by their kind (archetype "boss" / "elite"): boss_danger_hp, boss_danger_attack, boss_danger_speed,
##   boss_danger_bounty.
## A creature's factor is 1 + the stat: HP, attack (its contact bite and every hit it throws: EnemyManager.host_of),
## walking speed, and its bounty on its XP (EnemyManager.spawn's XP scale) and its coins (a creature's coin
## PickupManager.drop_from, an Elite's and a boss's purse and a boss's coins in Game._kill_effects). The bounty stats
## are TextGen kind "hidden": never written anywhere.
## Nothing in the arena (Run.arena: the debug arena's spawns are the bare numbers). No autoload is named here (tools
## compile this before they exist): the run is read through the tree.
class_name MirrorDanger
extends RefCounted

const KINDS := ["hp", "attack", "speed", "bounty"]


## Whether `def` is a boss or an Elite by its kind (the Boss form's), else a regular creature (the Difficulty form's).
static func is_big(def: EnemyDef) -> bool:
	return def != null and (def.archetype == "boss" or def.archetype == "elite")


## The stat that names `what` ("hp", "attack", "speed", "bounty") for a regular creature or for a boss / Elite.
static func stat_for(big: bool, what: String) -> String:
	return ("boss_danger_" if big else "danger_") + what


## The run (null without one).
static func _run() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("Run") if ml is SceneTree else null


## The factor on `what` for a regular creature (big = false) or a boss / Elite (big = true): 1 + the hero's stat, never
## below 1; 1 in the arena or without a run.
static func factor(big: bool, what: String) -> float:
	var run := _run()
	if run == null or run.get("arena") == true:
		return 1.0
	var s = run.get("player_sheet")
	if not (s is StatSheet):
		return 1.0
	return 1.0 + maxf((s as StatSheet).get_stat(stat_for(big, what), 0.0), 0.0)


## The factor on `what` for creature kind `def`.
static func factor_of(def: EnemyDef, what: String) -> float:
	return factor(is_big(def), what)


## All eight factors at once, {"hp": [regular, big], ...} (EnemyManager caches them with the hero's other numbers).
static func factors() -> Dictionary:
	var out := {}
	for k: String in KINDS:
		out[k] = [factor(false, k), factor(true, k)]
	return out


## A whole number of coins worth `v` x `mult`, its fraction paid by chance (so +5% of a 2-coin drop is real on
## average: 2.1 drops 2, or 3 one time in ten). `roll` stands in for the dice in tests (-1 = randf()).
static func scaled_count(v: float, mult: float, roll: float = -1.0) -> int:
	var x := maxf(v * mult, 0.0)
	var whole := floorf(x)
	var r := randf() if roll < 0.0 else roll
	return int(whole) + (1 if r < x - whole else 0)
