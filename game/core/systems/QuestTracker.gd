## Evaluates every unfinished quest against saved totals and the current run. Data-driven:
## a new quest is a JSON file with one of the condition types listed in QuestDef.
class_name QuestTracker
extends RefCounted

## The quests a run completed, for the Results screen's "Unlocked this run" (pass 76, lane UI: only a run's own checks
## add to it, the title's quiet one does not, and Run.start empties it, so nothing of an earlier run or of the title shows
## there).
static var just_completed: Array = []


static func check_all(in_run: bool) -> Array:
	## Returns the ids completed by this check that unlock something (pass 76: not one whose hero is already owned).
	var done: Array = []
	# nothing done in the debug arena counts (pass 33.4)
	if Run.arena:
		return done
	var marked := false
	for q in Registry.quests.values():
		if Save.quest_done(q.id) or not Registry.quest_visible(q):
			continue
		if _satisfied(q, in_run):
			# pass 76 (Garry: "Result Screen unlocks are showing heroes that I already unlocked"): a hero already owned
			# (bought, or given by the developer menu) has his quest marked done quietly; asked before the mark, since a
			# free hero is owned once his quest is done
			var quiet := owned_reward(q)
			Save.mark_quest(q.id)
			marked = true
			if quiet:
				continue
			done.append(q.id)
			if in_run:
				just_completed.append(q.id)
	if marked:
		Save.request_save()
	return done


## Whether quest `q` hands over a hero the player owns already (pass 76): a hero on sale (availability "purchase") he has
## bought, or that the developer menu gave him. A free hero is owned exactly when his quest is done (Registry.hero_state),
## so his quest still unlocks him. Its completion is never announced, its progress never shown.
static func owned_reward(q: QuestDef) -> bool:
	if q == null or str(q.unlocks.get("type", "")) != "character":
		return false
	var c: CharacterDef = Registry.character(str(q.unlocks.get("id", "")))
	return c != null and c.availability == "purchase" and Save.owns_hero(c.id)


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
			# pass 87 (lane SGAME): the seconds this run was played (Run.run_time: its stage, its boss, the portal, Endless)
			return in_run and Run.run_time() >= float(c.get("minutes", 0)) * 60.0
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
		# pass 100 (lane QUESTS): levels, upgrades and evolutions in one run, read off the run's build (run_progress)
		"hero_level", "item_level", "evolve_item", "weapon_paths", "items_maxed":
			if not in_run:
				return false
			var rp := run_progress(q)
			return rp.y > 0 and rp.x >= rp.y
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
		# pass 100 (lane QUESTS): done in one run, so their progress is this run's, only while a run is on (the run
		# record's before and after); outside a run they have none, like reach_level
		"hero_level", "item_level", "evolve_item", "weapon_paths", "items_maxed":
			return run_progress(q) if Run.active else Vector2i.ZERO
	return Vector2i.ZERO


## The stage a quest can be done on at the earliest (1-based; 0 = any), read off the map's timeline: a creature's first
## roster row or event, a boss's stage, minutes survived against the stage length. The Collection says it under a lock.
static func stage_hint(q: QuestDef) -> int:
	var c := q.condition
	var map: MapDef = Registry.map(str(c.get("map", "red_canyon")))
	if map == null or map.timeline == null:
		return 0
	var tl: WaveTimeline = map.timeline
	match str(c.get("type", "")):
		"kills_of_enemy", "kills_in_run_of_enemy":
			var t: float = first_arrival(tl, str(c.get("enemy", "")))
			# pass 87 (lane SGAME): the stage whose window holds it
			return tl.stage_at(t) + 1 if t >= 0.0 else 0
		"kill_boss", "reach_stage":
			return int(c.get("stage", 1))
		"extract_after_stage":
			return int(c.get("stage", 1))
		"survive_minutes", "survive_minutes_no_lift":
			# pass 87: the first stage at least that long (a run plays one stage), else the last (its Endless)
			var need: float = float(c.get("minutes", 0)) * 60.0
			for k in range(tl.stage_count()):
				if tl.stage_len(k) >= need:
					return k + 1
			return tl.stage_count()
		"evolve_any":
			return 2
		"reach_level", "hero_level":
			# a level a stage takes, about: twelve by the first portal, two dozen by the second
			var lv := int(c.get("level", 0))
			return 1 if lv <= 12 else (2 if lv <= 24 else 3)
		# pass 100 (lane QUESTS): a weapon's evolution reads like evolve_any (a stage-2 goal); a level, a card's Risen
		# form and a weapon's path are stage-1 goals; the Evolved rung and three or more maxed items stage 2
		"item_level":
			return 2 if str(c.get("rung", "")) == PassiveDef.EVOLVED_RUNG else 1
		"evolve_item":
			return 2 if _evolve_kind(c) == "weapon" else 1
		"weapon_paths":
			return 1
		"items_maxed":
			return 1 if int(c.get("count", 1)) <= 2 else 2
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
			# pass 87 (lane SGAME): from `from` in stage 1, from a later stage's window start (the specials' clock runs there)
			var t := maxf(float(sp.get("from", 0.0)), tl.stage_start(maxi(int(row.get("stage", 1)) - 1, 0)))
			best = t if best < 0.0 or t < best else best
	return best


# ---------------------------------------------------------------- pass 100 (lane QUESTS): the build quests

## The rarity ladder's rungs in order (PassiveDef.LADDER, then Evolved), 1-based ranks for an item_level `rung` (0 for
## a word that is no rung).
static func rung_rank(rung: String) -> int:
	if rung == PassiveDef.EVOLVED_RUNG:
		return PassiveDef.LADDER.size() + 1
	return PassiveDef.LADDER.find(rung) + 1


## How far this run has come on an in-one-run build quest (hero_level, item_level, evolve_item, weapon_paths,
## items_maxed): (so far, needed); (0, 0) when the run cannot move it (another hero) or the condition names nothing.
static func run_progress(q: QuestDef) -> Vector2i:
	var c := q.condition
	match str(c.get("type", "")):
		"hero_level":
			var need := int(c.get("level", 0))
			if Run.character == null or Run.character.id != str(c.get("hero", "")) or need <= 0:
				return Vector2i.ZERO
			return Vector2i(mini(Run.max_level_reached, need), need)
		"item_level":
			var rung := str(c.get("rung", ""))
			if rung != "":
				var target := rung_rank(rung)
				if target <= 0:
					return Vector2i.ZERO
				var best_rank := 0
				for e: Dictionary in held_items("passive", str(c.get("id", ""))):
					if str(e["kind"]) == "passive":
						best_rank = maxi(best_rank, rung_rank(str(e["rung"])))
				return Vector2i(mini(best_rank, target), target)
			var need_lv := int(c.get("level", 0))
			if need_lv <= 0:
				return Vector2i.ZERO
			var best := 0
			for e: Dictionary in held_items(str(c.get("kind", "any")), str(c.get("id", ""))):
				best = maxi(best, int(e["level"]))
			return Vector2i(mini(best, need_lv), need_lv)
		"evolve_item":
			for e: Dictionary in held_items(str(c.get("kind", "any")), str(c.get("id", ""))):
				if bool(e["evolved"]):
					return Vector2i(1, 1)
			return Vector2i(0, 1)
		"weapon_paths":
			var fam := str(c.get("weapon", ""))
			var need_p: int = Registry.mutations_of(fam).size() if fam != "" else 3
			if need_p <= 0:
				return Vector2i.ZERO
			var got := Vector2i(0, need_p)
			for inst: WeaponInstance in Run.weapons:
				if fam != "" and inst.family_id() != fam:
					continue
				var pp := Run.path_progress(inst)
				# the weapon furthest down its path (by share), for "any weapon"
				if pp.y > 0 and pp.x * got.y > got.x * pp.y:
					got = Vector2i(mini(pp.x, pp.y), pp.y)
			return got
		"items_maxed":
			var need_n := int(c.get("count", 1))
			if need_n <= 0:
				return Vector2i.ZERO
			var n := 0
			for e: Dictionary in held_items(str(c.get("kind", "any")), ""):
				if bool(e["maxed"]):
					n += 1
			return Vector2i(mini(n, need_n), need_n)
	return Vector2i.ZERO


## The run's build as the build quests read it: one entry per weapon, card and passive item held, {kind (weapon | card
## | passive), ids (its own id and, for an evolved form, its source's), level, evolved, maxed, rung}. An evolved form
## stands for its source at the source's top level (an evolution never undoes a level reached); a one-shot item (top
## level 1: the Phoenix) is never "maxed". `want_kind` any | weapon | card | passive filters; a non-empty `id` matches by
## id whatever the kind.
static func held_items(want_kind: String, id: String) -> Array:
	var out: Array = []
	for inst: WeaponInstance in Run.weapons:
		var e := {"kind": "weapon", "ids": [inst.def.id], "level": inst.level, "evolved": false, "rung": ""}
		var top := maxi(inst.def.max_level, 1)
		if inst.def.is_evolution:
			var src: WeaponDef = Registry.weapon(inst.def.evolved_from)
			if src:
				top = maxi(src.max_level, 1)
			e["ids"] = [inst.def.evolved_from, inst.def.id]
			e["level"] = maxi(top, inst.level)
			e["evolved"] = true
		e["maxed"] = bool(e["evolved"]) or inst.level >= top
		out.append(e)
	for pid in Run.passives.keys():
		var d: PassiveDef = Registry.passive(str(pid))
		if d == null:
			continue
		var lv := int(Run.passives[pid])
		var e := {"kind": "card" if d.is_line() else "passive", "ids": [d.id], "level": lv, "evolved": false,
			"rung": d.rung_at(lv)}
		var top := d.ladder_top()
		if d.evolves_from != "":
			var src: PassiveDef = Registry.passive(d.evolves_from)
			if src:
				top = src.ladder_top()
			e["ids"] = [d.evolves_from, d.id]
			e["level"] = maxi(top, lv)
			e["evolved"] = true
			e["rung"] = PassiveDef.EVOLVED_RUNG
		elif d.is_item() and d.is_evolved_rung(lv):
			e["evolved"] = true
		e["maxed"] = bool(e["evolved"]) or (lv >= top and top > 1)
		out.append(e)
	if id != "":
		return out.filter(func(x: Dictionary) -> bool: return (x["ids"] as Array).has(id))
	if want_kind == "" or want_kind == "any":
		return out
	return out.filter(func(x: Dictionary) -> bool: return str(x["kind"]) == want_kind)


## The kind of item an evolve_item quest names: its `id`'s, else its `kind` (any when empty).
static func _evolve_kind(c: Dictionary) -> String:
	return item_kind_of(str(c.get("id", "")), str(c.get("kind", "any")))


## weapon | card | passive for an item id (a weapon or its evolution, a card or its Risen form, a passive item);
## `fallback` for an empty or unknown id.
static func item_kind_of(id: String, fallback: String = "any") -> String:
	if id == "":
		return fallback
	if Registry.weapon(id) != null:
		return "weapon"
	var p: PassiveDef = Registry.passive(id)
	if p != null:
		return "card" if p.is_line() else "passive"
	return fallback
