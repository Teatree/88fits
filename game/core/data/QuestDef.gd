## An unlock quest: a checkable condition and what it unlocks.
class_name QuestDef
extends ContentDef

## Condition types (QuestTracker):
##  kills_with_weapon {weapon, count}   total across runs
##  kills_of_enemy {enemy, count}       total across runs
##  reach_level {level}                 in one run
##  survive_minutes {minutes}           in one run
##  survive_minutes_no_lift {minutes}   in one run without lifting the thumb
##  open_chests {count}                 total
##  evolve_any {count}                  total
##  extract_after_stage {map, stage}    once
##  kill_boss {map, stage}              once
##  kills_in_run_of_enemy {enemy, count} in one run
##  kills_total / runs_total / pickups_total / gold_total {count}   totals across runs (pass 44)
##  reach_stage {stage}                 in one run (pass 44)
## Pass 100 (lane QUESTS, Garry: more requirements about levels, upgrades and evolutions), all in one run, read off the
## run's build as it stands (an evolved form counts its source as maxed, so an evolution never undoes a level reached):
##  hero_level {hero, level}            reach `level` with hero `hero`
##  item_level {kind, id?, level?, rung?}   get an item to `level`: kind weapon | card | passive (a passive item) | any;
##                                      `id` names one (its kind then follows from it). A passive item climbs the rarity
##                                      ladder (PassiveDef.rung_at), so its levels differ by rarity: `rung` (uncommon, rare,
##                                      epic, legendary, evolved) names the rung to reach instead, and counts passive items
##                                      only; `level` on a passive item is its level number
##  evolve_item {id? | kind?}           evolve `id` (a weapon into its evolution at a chest, a card into its Risen card, a
##                                      passive item onto its Evolved rung; the evolved form's id works too), or any item
##                                      of `kind` (weapon | card | passive | any)
##  weapon_paths {weapon?}              carry all of a weapon's path mutations (`weapon` = that family; empty = any)
##  items_maxed {kind, count}           hold `count` items of `kind` at their top level at once (a weapon at its max
##                                      level or evolved, a card at its max level or Risen, a passive item on Evolved)
## Pass 111 (lane SKINS):
##  beat_stage {map, stage, hero?}      in one run of stage `stage` (1-based) on `map`, kill its boss, with hero `hero`
##                                      ("" any hero): "Beat Nightfall with May."
## Pass 113 (lane TASKS; core/systems/TaskTally.gd counts them), totals across runs (banked at each run's end; the run going
## on counts too, so one can complete mid-run), or inside one run with `"in_one_run": true`:
##  damage_with_weapon {weapon, count}  damage dealt by the weapon's family (the weapon and its evolution; never overkill)
##  heal_with_item {item, count}        HP restored by a card or passive item that heals (life steal, regen, Siesta,
##                                      Vulture, Cake Slices: TaskTally.HEAL_STATS), split by each item's share of the stat;
##                                      its evolved form counts for it
##  heal_with_source {source, count}   HP restored by a power-up or a structure: `source` "pickup:heart" (the Heart),
##                                      "structure:healing_well" (the Healing Well); "pickup:" / "structure:" = any of the kind
##  element_damage {element, count}     fire (burns) or poison (poison ticks) damage the hero's side dealt; "" = both
##  barrels_total {count}               barrels broken
##  totems_total {count}                Totem gifts taken
## `item_level` (pass 100) is the "Upgrade an item to level N" task; the Level Editor limits its level to the item's own.
## `unlocks` may also be {"type": "skin", "id": "<hero>:<CODE>"} (a hero's look sold as a skin, Registry.skin_state).
@export var condition: Dictionary = {}
## {"type": "character|weapon|passive|map|mode|skin", "id": "..."} (a skin's id is "<hero>:<CODE>")
@export var unlocks: Dictionary = {}
## Text shown in the collection when locked. Generated when empty.
@export var quest_text: String = ""


func kind() -> String:
	return "quest"
