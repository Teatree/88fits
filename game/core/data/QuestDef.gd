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
@export var condition: Dictionary = {}
## {"type": "character|weapon|passive|map|mode", "id": "..."}
@export var unlocks: Dictionary = {}
## Text shown in the collection when locked. Generated when empty.
@export var quest_text: String = ""


func kind() -> String:
	return "quest"
