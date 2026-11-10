## Pass 140 (lane FIX): the progression plan (BALANCING 81.TRAIL, 81.QUESTS) puts items, four outlaws, a skin and two
## stages behind a Trail node or a task. A test that needs one of them in play opens it in its save the way a player
## would have: the Trail node that gives it bought (Save.trail_buy, at no cost) and its task done (the save's quests_done).
##   const UNLOCKS := preload("res://tests/fixtures/unlocks.gd")
##   UNLOCKS.open("passive", "jade_key")      UNLOCKS.open_all("passive", ["iron_horse", "personal_storm"])
##   UNLOCKS.open_everything()                 every unlock node bought and every task done (no upgrade node: no power)
extends RefCounted

## Registry's type -> the Trail's word for it (a skin is "<outlaw>:<CODE>", a stage "<map>:<stage id>" in both).
const TRAIL_TYPE := {"character": "outlaw"}


## Opens `type` `id` (Registry's types: weapon, passive, character, skin, map; "stage" for a Trail stage).
static func open(type: String, id: String) -> void:
	var tt: String = TRAIL_TYPE.get(type, type)
	var g: Dictionary = Trail.gate(tt, id)
	if not g.is_empty():
		Save.trail_buy(str(g["id"]), 0)
	var q: QuestDef = Registry.quest_for(type, id)
	if q != null and not Save.quest_done(q.id):
		(Save.data["quests_done"] as Array).append(q.id)


## What locks `type` `id` on a new save: "trail" (a Trail node gives it), "task" (a quest unlocks it), "" (open from the start).
static func locked_by(type: String, id: String) -> String:
	if Trail.gated(TRAIL_TYPE.get(type, type), id):
		return "trail"
	return "task" if Registry.quest_for(type, id) != null else ""


static func open_all(type: String, ids: Array) -> void:
	for id in ids:
		open(type, str(id))


## The whole game open, as it was before pass 140's locks: every Trail node that gives a thing (never an upgrade node, so
## the outlaw's numbers stay a fresh save's) bought and every task done.
static func open_everything() -> void:
	for n: Dictionary in Trail.nodes():
		if str((n["gives"] as Dictionary).get("type", "")) != "upgrade":
			Save.trail_buy(str(n["id"]), 0)
	var done: Array = Save.data["quests_done"]
	for qid in Registry.quests.keys():
		if not done.has(str(qid)):
			done.append(str(qid))
