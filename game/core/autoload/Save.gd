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
		"shop_tiers": {},
		"quests_done": [],
		"totals": {"kills": 0, "kills_with_weapon": {}, "kills_of_enemy": {}, "chests": 0, "evolutions": 0, "runs": 0, "extracts": 0},
		"once": [],
		"best_runs": {},
		"settings": {},
		"hints_seen": [],
		"last_character": "astro",
		"last_map": "dry_gulch",
		"runs_started": 0,
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
	if not Registry.maps.has(str(data.get("last_map", ""))):
		data["last_map"] = "dry_gulch"
	Settings.from_dict(data.get("settings", {}))


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


# ---------------------------------------------------------------- shop

func tier(upgrade_id: String) -> int:
	return int(data["shop_tiers"].get(upgrade_id, 0))


func buy_tier(def: ShopUpgradeDef) -> bool:
	var t := tier(def.id)
	var cost := def.cost_of_tier(t)
	if cost < 0 or not spend_gold(cost):
		return false
	data["shop_tiers"][def.id] = t + 1
	request_save()
	return true


func refund_all() -> int:
	var refund := 0
	for id in data["shop_tiers"].keys():
		var def: ShopUpgradeDef = Registry.shop.get(id)
		if def == null:
			continue
		for t in range(int(data["shop_tiers"][id])):
			refund += max(def.cost_of_tier(t), 0)
	data["shop_tiers"] = {}
	add_gold(refund)
	return refund


# ---------------------------------------------------------------- quests and totals

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

func record_run(map_id: String, time: float, level: int, stage: int) -> void:
	var best: Dictionary = data["best_runs"].get(map_id, {"time": 0.0, "level": 0, "stage": 0})
	best["time"] = max(float(best.get("time", 0.0)), time)
	best["level"] = max(int(best.get("level", 0)), level)
	best["stage"] = max(int(best.get("stage", 0)), stage)
	data["best_runs"][map_id] = best
	add_total("runs", 1)
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
