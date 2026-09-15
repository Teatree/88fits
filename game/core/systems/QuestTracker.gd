## Evaluates every unfinished quest against saved totals and the current run. Data-driven:
## a new quest is a JSON file with one of the condition types listed in QuestDef.
class_name QuestTracker
extends RefCounted

static var just_completed: Array = []


static func check_all(in_run: bool) -> Array:
	## Returns the ids completed by this check.
	var done: Array = []
	for q in Registry.quests.values():
		if Save.quest_done(q.id):
			continue
		if _satisfied(q, in_run):
			Save.mark_quest(q.id)
			done.append(q.id)
			just_completed.append(q.id)
	if not done.is_empty():
		Save.request_save()
	return done


static func check_run_events() -> Array:
	return check_all(true)


static func _satisfied(q: QuestDef, in_run: bool) -> bool:
	var c := q.condition
	match str(c.get("type", "")):
		"kills_with_weapon":
			return Save.keyed_total("kills_with_weapon", str(c.get("weapon", ""))) >= int(c.get("count", 0))
		"kills_of_enemy":
			return Save.keyed_total("kills_of_enemy", str(c.get("enemy", ""))) >= int(c.get("count", 0))
		"open_chests":
			return Save.total("chests") >= int(c.get("count", 0))
		"evolve_any":
			return Save.total("evolutions") >= int(c.get("count", 1))
		"reach_level":
			return in_run and Run.max_level_reached >= int(c.get("level", 0))
		"survive_minutes":
			return in_run and Run.elapsed >= float(c.get("minutes", 0)) * 60.0
		"survive_minutes_no_lift":
			return in_run and Run.no_lift_time >= float(c.get("minutes", 0)) * 60.0
		"kills_in_run_of_enemy":
			return in_run and int(Run.kills_by_enemy.get(str(c.get("enemy", "")), 0)) >= int(c.get("count", 0))
		"extract_after_stage":
			return Save.once("extract_%s_%d" % [str(c.get("map", "")), int(c.get("stage", 1))])
		"kill_boss":
			return Save.once("boss_%s_%d" % [str(c.get("map", "")), int(c.get("stage", 1))])
	return false


static func progress_text(q: QuestDef) -> String:
	var c := q.condition
	match str(c.get("type", "")):
		"kills_with_weapon":
			return "%d / %d" % [Save.keyed_total("kills_with_weapon", str(c.get("weapon", ""))), int(c.get("count", 0))]
		"kills_of_enemy":
			return "%d / %d" % [Save.keyed_total("kills_of_enemy", str(c.get("enemy", ""))), int(c.get("count", 0))]
		"open_chests":
			return "%d / %d" % [Save.total("chests"), int(c.get("count", 0))]
		"evolve_any":
			return "%d / %d" % [Save.total("evolutions"), int(c.get("count", 1))]
	return ""
