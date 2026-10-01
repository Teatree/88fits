## One JSON save file: gold, shop tiers, quests, totals, best runs, settings, hint flags.
extends Node

const PATH := "user://save.json"

signal gold_changed(gold: int)
signal quest_completed(quest_id: String)

var data: Dictionary = {}
var _dirty := false


func _ready() -> void:
	load_save()


func _default() -> Dictionary:
	return {
		"version": 1,
		"gold": 0,
		"talents": {}, "talent_spent": 0,
		"quests_done": [],
		"totals": {"kills": 0, "kills_with_weapon": {}, "kills_of_enemy": {}, "chests": 0, "evolutions": 0, "runs": 0, "extracts": 0,
			"pickups": 0, "gold_earned": 0},
		"once": [],
		"best_runs": {},
		# what the player has met in a run, by kind (pass 44): the Collection shows only these
		"seen": {},
		"settings": {},
		"hints_seen": [],
		"last_character": "astro",
		"last_map": "red_canyon",
		"runs_started": 0,
		"materials": {"bones": 0, "relics": 0},
	}


func load_save() -> void:
	data = _default()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				for k in parsed.keys():
					data[k] = parsed[k]
	# content can disappear between versions (heroes come and go): never point at a missing id
	if not Registry.characters.has(str(data.get("last_character", ""))):
		data["last_character"] = "astro" if Registry.characters.has("astro") else (Registry.sorted_characters()[0].id if not Registry.characters.is_empty() else "astro")
	# Astro became the default hero on 2026-09-14: existing saves switch to him once, then the player's pick sticks
	if Registry.characters.has("astro") and data.has("once") and data["once"] is Array and not data["once"].has("hero_astro"):
		data["once"].append("hero_astro")
		data["last_character"] = "astro"
	# a hero that has been hidden since (pass 33.4) is not played any more
	var lc: CharacterDef = Registry.playable_character(str(data.get("last_character", "astro")))
	if lc:
		data["last_character"] = lc.id
	if not Registry.maps.has(str(data.get("last_map", ""))):
		data["last_map"] = "red_canyon"
	if not (data.get("seen") is Dictionary):
		data["seen"] = {}
	_migrate_seen()
	Settings.from_dict(data.get("settings", {}))


## A save from before pass 44 has no "seen" record: what its totals prove was met counts as seen (the creatures it
## killed, the weapons it killed with), so the Collection does not go blank on an old save.
func _migrate_seen() -> void:
	if once("seen_migrated"):
		return
	for id in data["totals"].get("kills_of_enemy", {}).keys():
		if int(data["totals"]["kills_of_enemy"][id]) > 0:
			mark_seen("enemy", str(id))
	for id in data["totals"].get("kills_with_weapon", {}).keys():
		if int(data["totals"]["kills_with_weapon"][id]) > 0:
			mark_seen("weapon", str(id))
	mark_once("seen_migrated")


func save_now() -> void:
	data["settings"] = Settings.to_dict()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	_dirty = false


func request_save() -> void:
	_dirty = true
	call_deferred("_flush")


func _flush() -> void:
	if _dirty:
		save_now()


func wipe() -> void:
	data = _default()
	save_now()


# ---------------------------------------------------------------- gold

func gold() -> int:
	return int(data.get("gold", 0))


func add_gold(n: int) -> void:
	data["gold"] = gold() + max(n, 0)
	gold_changed.emit(gold())
	request_save()


func spend_gold(n: int) -> bool:
	if gold() < n:
		return false
	data["gold"] = gold() - n
	gold_changed.emit(gold())
	request_save()
	return true


# ---------------------------------------------------------------- the Mirror

## What form of a talent is picked (0 or 1) and how many ranks of it are owned.
func talent_form(id: String) -> int:
	var t = data.get("talents", {}).get(id, {})
	return int(t.get("form", 0)) if t is Dictionary else 0


func talent_rank(id: String) -> int:
	var t = data.get("talents", {}).get(id, {})
	return int(t.get("rank", 0)) if t is Dictionary else 0


## Switching form is free and keeps the ranks: the Mirror is a choice, not a purchase you regret.
func set_talent_form(id: String, form: int) -> void:
	var all: Dictionary = data.get("talents", {})
	var t: Dictionary = all.get(id, {"form": 0, "rank": 0})
	t["form"] = clampi(form, 0, 1)
	all[id] = t
	data["talents"] = all
	request_save()


## Buy the next rank of a talent with gold.
func buy_talent(def: TalentDef) -> bool:
	var rank := talent_rank(def.id)
	if rank >= def.ranks:
		return false
	var cost := def.cost_of_rank(rank)
	if cost < 0 or not spend_gold(cost):
		return false
	var all: Dictionary = data.get("talents", {})
	var t: Dictionary = all.get(def.id, {"form": 0, "rank": 0})
	t["rank"] = rank + 1
	all[def.id] = t
	data["talents"] = all
	data["talent_spent"] = talent_spent() + cost
	request_save()
	return true


func talent_spent() -> int:
	return int(data.get("talent_spent", 0))


## Everything back, for half the gold (pass 44: the refund keeps REFUND_FRAC of what was spent): the board empties and
## half the coins return.
const REFUND_FRAC := 0.5


func talent_refund() -> int:
	return int(floor(talent_spent() * REFUND_FRAC))


func talent_refund_all() -> int:
	var back := talent_refund()
	data["talents"] = {}
	data["talent_spent"] = 0
	add_gold(back)
	request_save()
	return back



# ---------------------------------------------------------------- the homestead

func quest_done(id: String) -> bool:
	return data["quests_done"].has(id)


func mark_quest(id: String) -> void:
	if not quest_done(id):
		data["quests_done"].append(id)
		quest_completed.emit(id)
		request_save()


func total(key: String) -> int:
	return int(data["totals"].get(key, 0))


func add_total(key: String, n: int = 1) -> void:
	data["totals"][key] = total(key) + n


func add_keyed_total(key: String, sub: String, n: int = 1) -> void:
	if not (data["totals"].get(key) is Dictionary):
		data["totals"][key] = {}
	data["totals"][key][sub] = int(data["totals"][key].get(sub, 0)) + n


func keyed_total(key: String, sub: String) -> int:
	var d = data["totals"].get(key, {})
	return int(d.get(sub, 0)) if d is Dictionary else 0


func once(key: String) -> bool:
	return data["once"].has(key)


func mark_once(key: String) -> void:
	if not once(key):
		data["once"].append(key)


# ---------------------------------------------------------------- runs and hints

func record_run(map_id: String, time: float, level: int, stage: int, kills: int = 0) -> void:
	var best: Dictionary = data["best_runs"].get(map_id, {"time": 0.0, "level": 0, "stage": 0, "kills": 0})
	best["time"] = max(float(best.get("time", 0.0)), time)
	best["level"] = max(int(best.get("level", 0)), level)
	best["stage"] = max(int(best.get("stage", 0)), stage)
	best["kills"] = max(int(best.get("kills", 0)), kills)
	data["best_runs"][map_id] = best
	add_total("runs", 1)
	request_save()


# ---------------------------------------------------------------- what has been met (pass 44)

## Whether an item or creature of `kind` ("weapon", "passive", "line", "perk", "enemy") has been met in a run.
func seen(kind: String, id: String) -> bool:
	var s = data.get("seen", {}).get(kind, [])
	return s is Array and s.has(id)


func mark_seen(kind: String, id: String) -> void:
	if id == "" or seen(kind, id):
		return
	if not (data.get("seen") is Dictionary):
		data["seen"] = {}
	if not (data["seen"].get(kind) is Array):
		data["seen"][kind] = []
	data["seen"][kind].append(id)
	request_save()


func best_run(map_id: String) -> Dictionary:
	return data["best_runs"].get(map_id, {})


func hint_seen(id: String) -> bool:
	return data["hints_seen"].has(id)


func mark_hint(id: String) -> void:
	if not hint_seen(id):
		data["hints_seen"].append(id)
		request_save()


func reset_hints() -> void:
	data["hints_seen"] = []
	request_save()


func first_run_done() -> bool:
	return int(data.get("runs_started", 0)) > 0


func note_run_started() -> void:
	data["runs_started"] = int(data.get("runs_started", 0)) + 1
	request_save()
