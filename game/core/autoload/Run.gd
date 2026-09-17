## The state of the current run, kept in an autoload so every screen (HUD, pause, results) reads one object.
## The Game scene drives it; this holds data and build logic, not nodes.
extends Node

signal level_up(level: int)
signal xp_changed(xp: float, needed: float)
signal xp_gained(amount: float)
signal build_changed
signal gold_changed(run_gold: int)
signal kills_changed(kills: int)
signal stage_changed(stage: int)
signal weapon_evolved(weapon_id: String)

var active := false
var character: CharacterDef
var map: MapDef
var elapsed := 0.0
var stage := 0            # 0-based
var endless := false
var level := 1
var xp := 0.0
var run_gold := 0
var kills := 0
var alive := 0
var extracted := false
var died := false
var revives_used := 0
var thumb_lifted := false
var no_lift_time := 0.0
var max_level_reached := 1
var kills_by_enemy: Dictionary = {}
var kills_by_weapon: Dictionary = {}
var damage_by_weapon: Dictionary = {}
var chests_opened := 0
var evolutions := 0
var bosses_killed := 0

var player_sheet: StatSheet = StatSheet.new()
## Timed buffs from pickups: {"id", "label", "effects", "source", "until"}; re-applied whenever the sheet is rebuilt.
var timed: Array = []
## Array of WeaponInstance (see core/systems/WeaponInstance.gd)
var weapons: Array = []
## passive id -> level
var passives: Dictionary = {}
## ids banished from this run's pool
var banished: Array = []
var rerolls_left := 0
var skips_left := 0
var banishes_left := 0

const MAX_WEAPONS := 6
const MAX_PASSIVES := 6


func start(p_character: CharacterDef, p_map: MapDef) -> void:
	active = true
	character = p_character
	map = p_map
	elapsed = 0.0
	stage = 0
	endless = false
	level = 1
	xp = 0.0
	run_gold = 0
	kills = 0
	alive = 0
	extracted = false
	died = false
	revives_used = 0
	thumb_lifted = false
	no_lift_time = 0.0
	max_level_reached = 1
	kills_by_enemy.clear()
	kills_by_weapon.clear()
	damage_by_weapon.clear()
	chests_opened = 0
	evolutions = 0
	bosses_killed = 0
	weapons.clear()
	passives.clear()
	banished.clear()
	timed.clear()
	_build_player_sheet()
	rerolls_left = player_sheet.get_int("rerolls")
	skips_left = 999 if player_sheet.get_int("skips") > 0 else 0
	banishes_left = player_sheet.get_int("banishes")
	Save.note_run_started()
	build_changed.emit()


func end() -> void:
	active = false


func _build_player_sheet() -> void:
	player_sheet = StatSheet.new()
	player_sheet.set_bases(StatSheet.PLAYER_DEFAULTS)
	if character:
		player_sheet.add_effects(character.trait_effects, character.display_name)
	for def in Registry.shop.values():
		var t := Save.tier(def.id)
		if t > 0:
			player_sheet.add_effects(def.effects_for_tiers(t), "Shop: " + def.display_name + " " + str(t))
	for tb in timed:
		player_sheet.add_effects(tb["effects"], tb["source"])
	_apply_passives_to_sheet()


func _apply_passives_to_sheet() -> void:
	for pid in passives.keys():
		player_sheet.remove_source("passive:" + pid)
	for pid in passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def:
			player_sheet.add_effects(def.effects_for_level(passives[pid]), "passive:" + pid)


## A buff that wears off: applied now, removed by tick_timed() when its time is up. Picking the same one again resets the clock.
func add_timed_effects(id: String, label: String, effects: Array, seconds: float) -> void:
	var source := "buff:" + id
	for tb in timed:
		if tb["id"] == id:
			tb["until"] = elapsed + seconds
			return
	timed.append({"id": id, "label": label, "effects": effects, "source": source, "until": elapsed + seconds})
	player_sheet.add_effects(effects, source)
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


## Called every frame by the game; returns the labels of buffs that just ran out.
func tick_timed() -> Array:
	var ended: Array = []
	var keep: Array = []
	for tb in timed:
		if elapsed >= float(tb["until"]):
			player_sheet.remove_source(str(tb["source"]))
			ended.append(str(tb["label"]))
		else:
			keep.append(tb)
	if not ended.is_empty():
		timed = keep
		for w in weapons:
			w.rebuild(player_sheet, weapons)
		build_changed.emit()
	return ended


func rebuild_sheets() -> void:
	_build_player_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


# ---------------------------------------------------------------- xp

func xp_to_next(l: int = -1) -> float:
	var L := level if l < 0 else l
	return 15.0 + 6.0 * L + 0.5 * L * L


func add_xp(n: float) -> void:
	xp += n
	xp_gained.emit(n)
	xp_changed.emit(xp, xp_to_next())
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_level_reached = max(max_level_reached, level)
		level_up.emit(level)
		xp_changed.emit(xp, xp_to_next())


func spend_gold(n: int) -> bool:
	if run_gold < n:
		return false
	run_gold -= n
	gold_changed.emit(run_gold)
	return true


func add_gold(n: int) -> void:
	run_gold += int(round(n * player_sheet.get_stat("greed", 1.0)))
	gold_changed.emit(run_gold)


func add_kill(enemy_id: String, weapon_id: String) -> void:
	kills += 1
	kills_by_enemy[enemy_id] = int(kills_by_enemy.get(enemy_id, 0)) + 1
	if weapon_id != "":
		kills_by_weapon[weapon_id] = int(kills_by_weapon.get(weapon_id, 0)) + 1
	kills_changed.emit(kills)


func add_damage(weapon_id: String, amount: float) -> void:
	damage_by_weapon[weapon_id] = float(damage_by_weapon.get(weapon_id, 0.0)) + amount


# ---------------------------------------------------------------- build

## The element the build has committed to ("fire", "poison" or ""): fire and poison items never share a run.
func held_element() -> String:
	for w in weapons:
		var e: String = w.element()
		if e != "":
			return e
	for pid in passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def and def.element != "":
			return def.element
	return ""


## Whether an item may be offered to this build: nothing of the other element once one is held.
func element_allowed(def: ContentDef) -> bool:
	var e: String = def.element
	if e == "" and def is WeaponDef:
		e = WeaponInstance.new(def, 1).element()
	if e == "":
		return true
	var held := held_element()
	return held == "" or held == e


func has_weapon(id: String) -> bool:
	for w in weapons:
		if w.def.id == id:
			return true
	return false


func weapon_instance(id: String) -> WeaponInstance:
	for w in weapons:
		if w.def.id == id:
			return w
	return null


func add_weapon(def: WeaponDef, level_override: int = 1) -> WeaponInstance:
	if weapons.size() >= MAX_WEAPONS and not has_weapon(def.id):
		return null
	var inst := WeaponInstance.new(def, level_override)
	weapons.append(inst)
	inst.rebuild(player_sheet, weapons)
	build_changed.emit()
	return inst


func level_weapon(id: String) -> void:
	var w := weapon_instance(id)
	if w and w.level < w.def.max_level:
		w.level += 1
		w.rebuild(player_sheet, weapons)
		build_changed.emit()


func add_or_level_passive(id: String) -> void:
	if passives.has(id):
		var def: PassiveDef = Registry.passive(id)
		if def and passives[id] < def.max_level:
			passives[id] += 1
	else:
		if passives.size() >= MAX_PASSIVES:
			return
		passives[id] = 1
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


func evolution_ready(w: WeaponInstance) -> bool:
	if w.def.is_evolution or w.def.evolves_into == "":
		return false
	if w.level < w.def.max_level:
		return false
	if w.def.evolves_with != "" and not passives.has(w.def.evolves_with):
		return false
	return Registry.weapons.has(w.def.evolves_into)


func evolution_status(w: WeaponInstance) -> String:
	## One line for the pause screen: what is still missing.
	if w.def.is_evolution:
		return "Evolved form of " + str(Registry.weapon(w.def.evolved_from).display_name if Registry.weapon(w.def.evolved_from) else w.def.evolved_from) + "."
	if w.def.evolves_into == "":
		return "Does not evolve."
	var into: WeaponDef = Registry.weapon(w.def.evolves_into)
	var with_def: PassiveDef = Registry.passive(w.def.evolves_with)
	var parts: Array = []
	if with_def:
		parts.append("%s Lv %d %s" % [with_def.display_name, int(passives.get(w.def.evolves_with, 0)), "✓" if passives.has(w.def.evolves_with) else "✗"])
	parts.append("%s Lv %d/%d %s" % [w.def.display_name, w.level, w.def.max_level, "✓" if w.level >= w.def.max_level else "✗"])
	parts.append("then open a chest")
	return "Evolves into %s · %s" % [into.display_name if into else w.def.evolves_into, " · ".join(parts)]


func evolve(w: WeaponInstance) -> WeaponInstance:
	var into: WeaponDef = Registry.weapon(w.def.evolves_into)
	if into == null:
		return null
	var idx := weapons.find(w)
	var inst := WeaponInstance.new(into, 1)
	inst.kills = w.kills
	inst.damage = w.damage
	if idx >= 0:
		weapons[idx] = inst
	else:
		weapons.append(inst)
	inst.rebuild(player_sheet, weapons)
	evolutions += 1
	Save.add_total("evolutions", 1)
	weapon_evolved.emit(into.id)
	build_changed.emit()
	return inst


func any_evolution_ready() -> WeaponInstance:
	for w in weapons:
		if evolution_ready(w):
			return w
	return null


## What a chest holds, decided before the reel spins and applied only by chest_take. A card like CardPool's:
## an evolution when one is ready, else a level for a random owned item that can still grow, else a purse of gold.
func chest_roll() -> Dictionary:
	var w := any_evolution_ready()
	if w:
		var into: WeaponDef = Registry.weapon(w.def.evolves_into)
		return {"type": "evolution", "id": into.id, "def": into, "src_id": w.def.id, "level_from": 0, "level_to": 1, "is_new": true}
	var candidates: Array = []
	for wi in weapons:
		if not wi.def.is_evolution and wi.level < wi.def.max_level:
			candidates.append({"type": "weapon", "id": wi.def.id, "def": wi.def, "level_from": wi.level, "level_to": wi.level + 1, "is_new": false})
	for pid in passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def and passives[pid] < def.max_level:
			candidates.append({"type": "passive", "id": pid, "def": def, "level_from": int(passives[pid]), "level_to": int(passives[pid]) + 1, "is_new": false})
	if candidates.is_empty():
		return {"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false}
	return candidates[randi() % candidates.size()]


## The player took what the chest held. Returns the line for the toast.
func chest_take(r: Dictionary) -> String:
	chests_opened += 1
	Save.add_total("chests", 1)
	match str(r.get("type", "")):
		"evolution":
			var src := weapon_instance(str(r.get("src_id", "")))
			if src:
				var inst := evolve(src)
				return inst.def.display_name if inst else ""
			return ""
		"weapon":
			# the build can have changed under the reel (an evolution replaced the weapon): then gold instead
			if weapon_instance(r["id"]) == null:
				add_gold(int(r.get("gold", 50)))
				return "+%d gold" % int(r.get("gold", 50))
			level_weapon(r["id"])
			return Registry.weapon(r["id"]).display_name + " Lv " + str(weapon_instance(r["id"]).level)
		"passive":
			add_or_level_passive(r["id"])
			return Registry.passive(r["id"]).display_name + " Lv " + str(passives[r["id"]])
		_:
			add_gold(int(r.get("gold", 50)))
			return "+%d gold" % int(r.get("gold", 50))


## The player sold what the chest held instead.
func chest_sell(r: Dictionary, gold: int) -> String:
	chests_opened += 1
	Save.add_total("chests", 1)
	add_gold(gold)
	return "Sold for %d gold" % gold


## Apply a chest at once (tools and tests): the roll, taken.
func open_chest() -> Dictionary:
	var r := chest_roll()
	r["name"] = chest_take(r)
	return r


func stage_mult() -> float:
	if map == null or map.timeline == null:
		return 1.0
	var endless_minutes := 0.0
	if endless:
		endless_minutes = max(0.0, (elapsed - map.timeline.stage_length * map.timeline.stages) / 60.0)
	return map.timeline.stage_mult(stage, endless_minutes)


func summary() -> Dictionary:
	return {
		"time": elapsed, "stage": stage + 1, "level": level, "kills": kills, "gold": run_gold,
		"extracted": extracted, "died": died, "damage_by_weapon": damage_by_weapon.duplicate(),
		"kills_by_weapon": kills_by_weapon.duplicate(), "evolutions": evolutions, "chests": chests_opened,
		"character": character.display_name if character else "", "map": map.display_name if map else "",
	}
