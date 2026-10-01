## Evaluates every unfinished quest against saved totals and the current run. Data-driven:
## a new quest is a JSON file with one of the condition types listed in QuestDef.
class_name QuestTracker
extends RefCounted

static var just_completed: Array = []


static func check_all(in_run: bool) -> Array:
	## Returns the ids completed by this check.
	var done: Array = []
	# nothing done in the debug arena counts (pass 33.4)
	if Run.arena:
		return done
	for q in Registry.quests.values():
		if Save.quest_done(q.id) or not Registry.quest_visible(q):
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
		# pass 44: totals across runs, and a stage reached in one
		"kills_total":
			return Save.total("kills") >= int(c.get("count", 0))
		"runs_total":
			return Save.total("runs") >= int(c.get("count", 0))
		"pickups_total":
			return Save.total("pickups") >= int(c.get("count", 0))
		"gold_total":
			return Save.total("gold_earned") >= int(c.get("count", 0))
		"reach_stage":
			return in_run and Run.stage + 1 >= int(c.get("stage", 1))
	return false


static func progress_text(q: QuestDef) -> String:
	var p := progress(q)
	return "%d / %d" % [p.x, p.y] if p.y > 0 else ""


## How far a counted quest has come: (so far, needed); (0, 0) for one that is done in a single run or has no count.
static func progress(q: QuestDef) -> Vector2i:
	var c := q.condition
	match str(c.get("type", "")):
		"kills_with_weapon":
			return Vector2i(Save.keyed_total("kills_with_weapon", str(c.get("weapon", ""))), int(c.get("count", 0)))
		"kills_of_enemy":
			return Vector2i(Save.keyed_total("kills_of_enemy", str(c.get("enemy", ""))), int(c.get("count", 0)))
		"open_chests":
			return Vector2i(Save.total("chests"), int(c.get("count", 0)))
		"evolve_any":
			return Vector2i(Save.total("evolutions"), int(c.get("count", 1)))
		"kills_total":
			return Vector2i(Save.total("kills"), int(c.get("count", 0)))
		"runs_total":
			return Vector2i(Save.total("runs"), int(c.get("count", 0)))
		"pickups_total":
			return Vector2i(Save.total("pickups"), int(c.get("count", 0)))
		"gold_total":
			return Vector2i(Save.total("gold_earned"), int(c.get("count", 0)))
	return Vector2i.ZERO


## The stage a quest can be done on at the earliest (1-based; 0 = any), read off the map's timeline: a creature's first
## roster row or event, a boss's stage, minutes survived against the stage length. The Collection says it under a lock.
static func stage_hint(q: QuestDef) -> int:
	var c := q.condition
	var map: MapDef = Registry.map(str(c.get("map", "red_canyon")))
	if map == null or map.timeline == null:
		return 0
	var tl: WaveTimeline = map.timeline
	var stage_len: float = maxf(float(tl.stage_length), 1.0)
	match str(c.get("type", "")):
		"kills_of_enemy", "kills_in_run_of_enemy":
			var t: float = first_arrival(tl, str(c.get("enemy", "")))
			return int(floor(t / stage_len)) + 1 if t >= 0.0 else 0
		"kill_boss", "reach_stage":
			return int(c.get("stage", 1))
		"extract_after_stage":
			return int(c.get("stage", 1))
		"survive_minutes", "survive_minutes_no_lift":
			return int(ceil(float(c.get("minutes", 0)) * 60.0 / stage_len))
		"evolve_any":
			return 2
		"reach_level":
			# a level a stage takes, about: twelve by the first portal, two dozen by the second
			var lv := int(c.get("level", 0))
			return 1 if lv <= 12 else (2 if lv <= 24 else 3)
	return 0


## The first second a creature can come: its earliest roster row, event or special in the timeline (-1: never).
static func first_arrival(tl: WaveTimeline, enemy_id: String) -> float:
	var best := -1.0
	for row in tl.roster:
		if row is Dictionary and str(row.get("enemy", "")) == enemy_id:
			var t := float(row.get("t", 0.0))
			best = t if best < 0.0 or t < best else best
	for ev in tl.events:
		if ev is Dictionary:
			var ids: Array = ev.get("enemy", []) if ev.get("enemy") is Array else [str(ev.get("enemy", ""))]
			if ids.has(enemy_id):
				var t := float(ev.get("t", 0.0))
				best = t if best < 0.0 or t < best else best
	var sp: Dictionary = tl.specials if tl.specials is Dictionary else {}
	for row in sp.get("pool", []):
		if row is Dictionary and str(row.get("enemy", "")) == enemy_id:
			var t := float(sp.get("from", 0.0)) + maxf(float(row.get("stage", 1)) - 1.0, 0.0) * float(tl.stage_length)
			best = t if best < 0.0 or t < best else best
	return best
