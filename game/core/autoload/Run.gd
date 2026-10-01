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
## gold already sent to the homestead by a Strongbox this run (the results screen says so)
var banked_gold := 0
var kills := 0
var alive := 0
var extracted := false
## What the results screen reads once the run is banked (Game.end_run): gold_before, banked, prev_best.
var last_result: Dictionary = {}
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
var lifesteal_pool := 0.0
## the most of max HP a second lifesteal may heal, whatever the damage
const LIFESTEAL_CAP := 0.04
var _lifesteal_second := 0.0
var _lifesteal_healed_this_second := 0.0
signal lifesteal_healed(amount: float)
## Buck's momentum: 0..1, applied to the sheet as a speed and might bonus (CharacterDef.momentum in the JSON)
var momentum := 0.0
## Berserk: the hero's weapon speed (1 = normal, 2 = twice as fast), cached off the sheet for the behaviours' own clocks
var haste := 1.0
var momentum_def: Dictionary = {}
## Array of WeaponInstance (see core/systems/WeaponInstance.gd)
var weapons: Array = []
## passive id -> level
var passives: Dictionary = {}
## ids banished from this run's pool
var banished: Array = []
## Adrenaline (a passive): kill stacks that lift speed and might, gone ADRENALINE_SECONDS after the last kill
const ADRENALINE_MAX := 20
const ADRENALINE_SECONDS := 4.0
var adrenaline := 0
## Calavera's Crescendo (pass 43): might per kill, up to the perk's cap, until a hit (Game resets it)
var crescendo := 0
var _crescendo_dirty := false
var _crescendo_built := -1.0
var adrenaline_until := 0.0
var _adrenaline_dirty := false
var _adrenaline_built := -1.0
## materials picked up this run (bones from Elites, relics from bosses): banked at the end, half of them on a death
var run_materials: Dictionary = {"bones": 0, "relics": 0}
var harvest: Dictionary = {}          # what the homestead yielded at this run's end (Save.harvest)
## the Stranger's cut: a fraction of max HP given up for his item, for the rest of the run
var stranger_cost := 0.0
var rerolls_left := 0
var skips_left := 0
var banishes_left := 0

const MAX_WEAPONS := 6
const MAX_PASSIVES := 6
## The paths (pass 26): a weapon's mutations open at this level, one pick per weapon per stage; a run opens two lines;
## a weapon evolves at its top level once it carries this many mutations.
const MUTATION_FROM_LEVEL := 1
const MAX_LINES := 2
const EVOLVE_MUTATIONS := 2
var mutations: Dictionary = {}        # weapon family id -> [mutation ids]
var mutation_stage: Dictionary = {}   # weapon family id -> the stage of its last path pick
var mutation_misses: Dictionary = {}  # weapon family id -> offers in a row without one of its open mutations
var lines: Dictionary = {}            # line id -> rank
var perks: Array = []                 # perk ids taken
var perk_gap := 5                     # offers since a perk card was shown (a perk is offered at most once in five)
var path_slot := 0                    # the next path slot of the stage (WaveTimeline.path_times)


## The map's layout roll for this run (Red Canyon reads it): random each run, or `forced_map_seed` when a tool wants
## the same desert every time (the capture tool).
var map_seed := 0
var forced_map_seed := 0


func start(p_character: CharacterDef, p_map: MapDef) -> void:
	active = true
	character = p_character
	map = p_map
	map_seed = forced_map_seed if forced_map_seed != 0 else (randi() % 999983) + 1
	elapsed = 0.0
	stage = 0
	arena = false
	endless = false
	level = 1
	xp = 0.0
	run_gold = 0
	banked_gold = 0
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
	mutations = {}
	mutation_stage = {}
	mutation_misses = {}
	lines = {}
	perks = []
	perk_gap = 5
	path_slot = 0
	banished.clear()
	run_materials = {"bones": 0, "relics": 0}
	stranger_cost = 0.0
	adrenaline = 0
	adrenaline_until = 0.0
	crescendo = 0
	_crescendo_dirty = false
	timed.clear()
	lifesteal_pool = 0.0
	_lifesteal_second = 0.0
	_lifesteal_healed_this_second = 0.0
	momentum = 0.0
	momentum_def = p_character.momentum if p_character else {}
	_build_player_sheet()
	rerolls_left = player_sheet.get_int("rerolls")
	skips_left = 999   # skipping is always allowed; the shop only makes it pay more
	banishes_left = player_sheet.get_int("banishes")
	Save.note_run_started()
	build_changed.emit()


func end() -> void:
	active = false


func _build_player_sheet() -> void:
	player_sheet = StatSheet.new()
	player_sheet.scope = "player"
	player_sheet.set_bases(StatSheet.PLAYER_DEFAULTS)
	if character:
		player_sheet.add_effects(character.trait_effects, character.display_name)
	# the Mirror: the form picked for each talent, as many times as it has ranks
	for tdef: TalentDef in Registry.talents.values():
		var rank := Save.talent_rank(tdef.id)
		if rank > 0:
			var form := Save.talent_form(tdef.id)
			player_sheet.add_effects(tdef.effects_for(form, rank), "%s: %s %d" % [tdef.display_name, tdef.form_name(form), rank])
	for tb in timed:
		player_sheet.add_effects(tb["effects"], tb["source"])
	if momentum > 0.0 and not momentum_def.is_empty():
		var e1 := Effect.new()
		e1.stat = "move_speed"; e1.op = "mul"; e1.value = float(momentum_def.get("speed_bonus", 0.6)) * momentum; e1.target = "player"
		var e2 := Effect.new()
		e2.stat = "might"; e2.op = "mul"; e2.value = float(momentum_def.get("might_bonus", 0.5)) * momentum; e2.target = "player"
		player_sheet.add_effects([e1, e2], "Momentum %d%%" % int(round(momentum * 100.0)))
	if stranger_cost > 0.0:
		var sc := Effect.new()
		sc.stat = "max_hp"; sc.op = "mul"; sc.value = -stranger_cost; sc.target = "player"
		player_sheet.add_effects([sc], "The Stranger's cut")
	_apply_passives_to_sheet()
	# adrenaline reads the per-stack values the passives just put on the sheet, so it goes on last
	if adrenaline > 0:
		var sp: float = player_sheet.get_stat("adrenaline_speed", 0.0) * adrenaline
		var mg: float = player_sheet.get_stat("adrenaline_might", 0.0) * adrenaline
		if sp > 0.0 or mg > 0.0:
			var a1 := Effect.new()
			a1.stat = "move_speed"; a1.op = "mul"; a1.value = sp; a1.target = "player"
			var a2 := Effect.new()
			a2.stat = "might"; a2.op = "mul"; a2.value = mg; a2.target = "player"
			player_sheet.add_effects([a1, a2], "Adrenaline ×%d" % adrenaline)
	if crescendo > 0 and has_perk("crescendo"):
		var c1 := Effect.new()
		c1.stat = "might"; c1.op = "mul"; c1.value = crescendo_might(); c1.target = "player"
		player_sheet.add_effects([c1], "Crescendo +%d%%" % int(round(crescendo_might() * 100.0)))
	haste = player_sheet.get_stat("haste", 1.0)


## What Crescendo adds to might right now (its stacks × the perk's per_kill, capped by its max).
func crescendo_might() -> float:
	return minf(float(crescendo) * perk_param("crescendo", "per_kill", 0.01), perk_param("crescendo", "max", 0.4))


## A hit drops Crescendo to nothing.
func reset_crescendo() -> void:
	if crescendo > 0:
		crescendo = 0
		rebuild_sheets()


func _apply_passives_to_sheet() -> void:
	for pid in passives.keys():
		player_sheet.remove_source("passive:" + pid)
	for pid in passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def:
			player_sheet.add_effects(def.effects_for_level(passives[pid]), "passive:" + pid)
	# the lines, the perks and the mutations that reach the hero (Rattle's slow, Blight's pass-on, Phosphorus's burn)
	for lid in lines.keys():
		player_sheet.remove_source("line:" + lid)
		var ldef: LineDef = Registry.line(lid)
		if ldef:
			player_sheet.add_effects(ldef.effects_for_level(int(lines[lid])), "line:" + lid)
	for pk in perks:
		player_sheet.remove_source("perk:" + pk)
		var pdef: PerkDef = Registry.perk(pk)
		if pdef:
			player_sheet.add_effects(pdef.effects, "perk:" + pk)
	for fam in mutations.keys():
		for mid in mutations[fam]:
			player_sheet.remove_source("mutation:" + mid)
			var mdef: MutationDef = Registry.mutation(mid)
			if mdef:
				player_sheet.add_effects(mdef.player_effects(), "mutation:" + mid)


## How many weapons the run may hold right now: the map's cap for the stage, never past the strip's six slots.
## The debug arena (pass 33.4): set by the title screen before Game loads (arena_next), held through the session.
var arena := false
var arena_next := false


## How many lines this run may have open now: the map's cap for the stage (pass 34), MAX_LINES without a map.
func line_cap() -> int:
	if arena:
		return 99
	if map and map.timeline:
		return map.timeline.line_cap_at(stage)
	return MAX_LINES


func weapon_cap() -> int:
	if arena:
		return MAX_WEAPONS
	if map and map.timeline:
		return mini(map.timeline.weapon_cap_at(stage), MAX_WEAPONS)
	return MAX_WEAPONS


func mutations_held(family: String) -> Array:
	var v = mutations.get(family, [])
	return v if v is Array else []


func mutation_defs(family: String) -> Array:
	var out: Array = []
	for mid in mutations_held(family):
		var m: MutationDef = Registry.mutation(mid)
		if m:
			out.append(m)
	return out


## The held weapon (base or evolved) on this family, or null.
func family_instance(family: String) -> WeaponInstance:
	for w in weapons:
		if w.family_id() == family:
			return w
	return null


## Whether a weapon may take a path pick now: at the opening level, and no pick on this stage yet.
func can_mutate(w: WeaponInstance) -> bool:
	if w == null or w.level < MUTATION_FROM_LEVEL:
		return false
	return int(mutation_stage.get(w.family_id(), -1)) != stage


## The mutation cards a weapon has open right now: its path when a pick is due, plus the hero's own option for it.
func open_mutations(w: WeaponInstance) -> Array:
	var out: Array = []
	var fam := w.family_id()
	if can_mutate(w):
		for m: MutationDef in Registry.mutations_of(fam):
			if not w.has_mutation(m.id):
				out.append(m)
	if character and w.level >= MUTATION_FROM_LEVEL:
		for hm: MutationDef in Registry.hero_mutations(character.id):
			if hm.weapon == fam and not w.has_mutation(hm.id):
				out.append(hm)
	return out


## `force` is the Stranger's loophole: a path pick past the stage's one (still never the same mutation twice).
func add_mutation(id: String, force: bool = false) -> bool:
	var def: MutationDef = Registry.mutation(id)
	if def == null:
		return false
	var inst := family_instance(def.weapon)
	if inst == null or inst.has_mutation(id):
		return false
	if not def.is_hero() and not force and not can_mutate(inst):
		return false
	var held := mutations_held(def.weapon)
	held.append(id)
	mutations[def.weapon] = held
	if not def.is_hero():
		mutation_stage[def.weapon] = stage
	mutation_misses[def.weapon] = 0
	inst.mutations = mutation_defs(def.weapon)
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


func line_rank(id: String) -> int:
	return int(lines.get(id, 0))


func add_or_rank_line(id: String) -> bool:
	var def: LineDef = Registry.line(id)
	if def == null:
		return false
	if lines.has(id):
		if int(lines[id]) >= def.max_level:
			return false
		lines[id] = int(lines[id]) + 1
	else:
		if lines.size() >= line_cap():
			return false
		lines[id] = 1
		Save.mark_seen("line", id)
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


## A maxed line becomes its evolution (pass 33.2): the line's ranks go, the evolved line takes its slot at its one rank.
func evolve_line(src_id: String) -> bool:
	var src: LineDef = Registry.line(src_id)
	if src == null or not lines.has(src_id) or src.evolves_into == "":
		return false
	var evo: LineDef = Registry.line(src.evolves_into)
	if evo == null:
		return false
	lines.erase(src_id)
	player_sheet.remove_source("line:" + src_id)
	lines[evo.id] = 1
	Save.mark_seen("line", evo.id)
	_apply_passives_to_sheet()
	haste = player_sheet.get_stat("haste", 1.0)
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


func add_perk(id: String) -> bool:
	var def: PerkDef = Registry.perk(id)
	if def == null or perks.has(id):
		return false
	perks.append(id)
	Save.mark_seen("perk", id)
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


func has_perk(id: String) -> bool:
	return perks.has(id)


## A perk's tuning number by the mechanism it names, or the default when the hero has no such perk.
func perk_param(special: String, key: String, default: float) -> float:
	for pk in perks:
		var def: PerkDef = Registry.perk(pk)
		if def and def.special == special:
			return float(def.params.get(key, default))
	return default


## Bookkeeping after an offer was shown: the perk gap.
func note_offer(offer: Array) -> void:
	var shown_perk := false
	for c in offer:
		if c["type"] == "perk":
			shown_perk = true
	perk_gap = 0 if shown_perk else perk_gap + 1


## The path slots: a stage puts a weapon's whole path on the table at set seconds (the map's `path_times`). True once
## per slot, the first frame the stage clock passes it.
func path_due(t_in_stage: float) -> bool:
	if map == null or map.timeline == null:
		return false
	var times: Array = map.timeline.path_times_at(stage)
	if path_slot >= times.size():
		return false
	if t_in_stage < float(times[path_slot]):
		return false
	path_slot += 1
	return true


## The weapon whose path goes on the table at a slot: among those with a pick still open this stage, the highest
## level, then the longest held. Null when every path is spent.
func next_path_weapon() -> WeaponInstance:
	var best: WeaponInstance = null
	for w in weapons:
		if not can_mutate(w) or open_mutations(w).is_empty():
			continue
		if best == null or w.level > best.level:
			best = w
	return best


func add_timed_effects(id: String, label: String, effects: Array, seconds: float) -> void:
	var source := "buff:" + id
	for tb in timed:
		if tb["id"] == id:
			tb["until"] = elapsed + seconds
			return
	timed.append({"id": id, "label": label, "effects": effects, "source": source, "until": elapsed + seconds})
	player_sheet.add_effects(effects, source)
	haste = player_sheet.get_stat("haste", 1.0)
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
		haste = player_sheet.get_stat("haste", 1.0)
		for w in weapons:
			w.rebuild(player_sheet, weapons)
		build_changed.emit()
	# adrenaline: stacks fall off together when the streak ends; while it runs the sheet follows at most 4× a second
	if adrenaline > 0 and elapsed >= adrenaline_until:
		adrenaline = 0
		_adrenaline_dirty = true
	if _adrenaline_dirty and (adrenaline == 0 or elapsed >= _adrenaline_built + 0.25):
		_adrenaline_dirty = false
		_adrenaline_built = elapsed
		rebuild_sheets()
	elif _crescendo_dirty and elapsed >= _crescendo_built + 0.3:
		_crescendo_dirty = false
		_crescendo_built = elapsed
		rebuild_sheets()
	return ended


## The debug arena's hand on the build (pass 33.4): the item `id` of `kind` (weapon, evolution, passive, line, perk,
## mutation) at level `n`, 0 taking it away, past the rules the cards keep (not past the slots: six weapons, the
## passive slots). Returns the level it ended at.
func debug_set_item(kind: String, id: String, n: int) -> int:
	match kind:
		"weapon", "evolution":
			var def: WeaponDef = Registry.weapon(id)
			if def == null:
				return 0
			n = clampi(n, 0, def.max_level)
			var w := weapon_instance(id)
			if n == 0:
				if w:
					weapons.erase(w)
			elif w == null:
				if weapons.size() >= MAX_WEAPONS:
					return 0
				w = WeaponInstance.new(def, n)
				w.mutations = mutation_defs(w.family_id())
				weapons.append(w)
			else:
				w.level = n
		"passive":
			var pd: PassiveDef = Registry.passive(id)
			if pd == null:
				return 0
			n = clampi(n, 0, pd.max_level)
			if n == 0:
				passives.erase(id)
			elif passives.has(id) or passives.size() < MAX_PASSIVES:
				passives[id] = n
			else:
				return 0
		"line":
			var ld: LineDef = Registry.line(id)
			if ld == null:
				return 0
			n = clampi(n, 0, ld.max_level)
			if n == 0:
				lines.erase(id)
			else:
				lines[id] = n
		"perk":
			if n <= 0:
				perks.erase(id)
			elif not perks.has(id) and Registry.perk(id) != null:
				perks.append(id)
			n = 1 if perks.has(id) else 0
		"mutation":
			var md: MutationDef = Registry.mutation(id)
			if md == null:
				return 0
			var held := mutations_held(md.weapon)
			if n <= 0:
				held.erase(id)
			elif not held.has(id):
				held.append(id)
			mutations[md.weapon] = held
			var inst := family_instance(md.weapon)
			if inst:
				inst.mutations = mutation_defs(md.weapon)
			n = 1 if held.has(id) else 0
	haste = 1.0
	rebuild_sheets()
	haste = player_sheet.get_stat("haste", 1.0)
	return n


## Every item gone (the arena's clean slate).
func debug_clear_items() -> void:
	weapons.clear()
	passives.clear()
	lines.clear()
	perks.clear()
	mutations.clear()
	rebuild_sheets()


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
	n *= player_sheet.get_stat("xp_gain", 1.0)   # Field Notes
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
	var gained := int(round(n * player_sheet.get_stat("greed", 1.0)))
	run_gold += gained
	# all-time gold earned (pass 44: an unlock counts it), whatever becomes of the purse
	if gained > 0 and not arena:
		Save.add_total("gold_earned", gained)
	gold_changed.emit(run_gold)


func add_kill(enemy_id: String, weapon_id: String) -> void:
	kills += 1
	if player_sheet.get_stat("adrenaline_speed", 0.0) > 0.0 or player_sheet.get_stat("adrenaline_might", 0.0) > 0.0:
		adrenaline = mini(adrenaline + 1, ADRENALINE_MAX)
		adrenaline_until = elapsed + ADRENALINE_SECONDS
		_adrenaline_dirty = true
	if has_perk("crescendo"):
		var cap: int = int(round(perk_param("crescendo", "max", 0.4) / maxf(perk_param("crescendo", "per_kill", 0.01), 0.001)))
		if crescendo < cap:
			crescendo += 1
			_crescendo_dirty = true
	kills_by_enemy[enemy_id] = int(kills_by_enemy.get(enemy_id, 0)) + 1
	if weapon_id != "":
		kills_by_weapon[weapon_id] = int(kills_by_weapon.get(weapon_id, 0)) + 1
	kills_changed.emit(kills)


func add_damage(weapon_id: String, amount: float) -> void:
	damage_by_weapon[weapon_id] = float(damage_by_weapon.get(weapon_id, 0.0)) + amount
	# life steal: a slice of every point of damage comes back as health
	# lifesteal is a trickle, not a tap: at most LIFESTEAL_CAP of max HP a second, however much damage a build pours
	# out (a beam through forty creatures used to refill the bar in one sweep)
	var ls: float = player_sheet.get_stat("lifesteal", 0.0)
	if ls > 0.0:
		var now: float = elapsed
		if now - _lifesteal_second >= 1.0:
			_lifesteal_second = now
			_lifesteal_healed_this_second = 0.0
		var cap: float = player_sheet.get_stat("max_hp", 100.0) * player_sheet.get_stat("lifesteal_cap", LIFESTEAL_CAP)
		var room: float = maxf(cap - _lifesteal_healed_this_second, 0.0)
		if room > 0.0:
			lifesteal_pool += minf(amount * ls, room)
			if lifesteal_pool >= 1.0:
				var heal := floorf(lifesteal_pool)
				lifesteal_pool -= heal
				_lifesteal_healed_this_second += heal
				lifesteal_healed.emit(heal)


# ---------------------------------------------------------------- build

## The element an item carries: its `element` field, else read off its stats (poison_* or fire_*), so a JSON that
## forgets the field is still known for what it is. (Until pass 36 a run held one element only; fire and poison items
## share a run now.)
static func element_of(def: ContentDef) -> String:
	if def == null:
		return ""
	if def.element != "":
		return def.element
	if def is MutationDef or def is LineDef or def is PerkDef:
		return ""
	if def is WeaponDef:
		return WeaponInstance.new(def, 1).element()
	if def is PassiveDef:
		for lv in (def as PassiveDef).levels:
			if not lv is Array:
				continue
			for e in lv:
				var st: String = e.stat if e is Effect else str((e as Dictionary).get("stat", "")) if e is Dictionary else ""
				if st.begins_with("fire_"):
					return "fire"
				if st.begins_with("poison_"):
					return "poison"
	return ""


func add_material(kind: String, n: int) -> void:
	run_materials[kind] = int(run_materials.get(kind, 0)) + n


## The Stranger's item: one rare or epic thing the run can hold, taken far in one stroke. Never common, never rerolled.
func stranger_offer() -> Dictionary:
	var cands: Array = []
	# the loophole: a mutation from a path already spent this stage, the only way past exclusivity, at a higher price
	for w in weapons:
		var fam: String = w.family_id()
		if int(mutation_stage.get(fam, -1)) != stage:
			continue
		for m: MutationDef in Registry.mutations_of(fam):
			if not w.has_mutation(m.id) and not banished.has(m.id):
				cands.append({"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true, "hp_cost": 0.2})
	for w in Registry.unlocked_weapons():
		if w.is_evolution or w.rarity == "common" or banished.has(w.id):
			continue
		var inst := weapon_instance(w.id)
		if inst == null and weapons.size() < weapon_cap():
			cands.append({"type": "weapon", "id": w.id, "def": w, "level_from": 0, "level_to": mini(3, w.max_level), "is_new": true})
		elif inst and inst.level < w.max_level:
			cands.append({"type": "weapon", "id": w.id, "def": w, "level_from": inst.level, "level_to": mini(inst.level + 2, w.max_level), "is_new": false})
	for p in Registry.unlocked_passives():
		if p.rarity == "common" or banished.has(p.id):
			continue
		var lv := int(passives.get(p.id, 0))
		if lv == 0 and passives.size() < MAX_PASSIVES:
			cands.append({"type": "passive", "id": p.id, "def": p, "level_from": 0, "level_to": mini(2, p.max_level), "is_new": true})
		elif lv > 0 and lv < p.max_level:
			cands.append({"type": "passive", "id": p.id, "def": p, "level_from": lv, "level_to": mini(lv + 2, p.max_level), "is_new": false})
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## The deal: the item to its offered level, and the cut off the hero's max HP.
func stranger_take(offer: Dictionary, hp_cost: float) -> String:
	if offer.is_empty():
		return ""
	var def: ContentDef = offer["def"]
	var to := int(offer.get("level_to", 1))
	if offer["type"] == "mutation":
		add_mutation(def.id, true)
		stranger_cost = minf(stranger_cost + hp_cost, 0.6)
		rebuild_sheets()
		return def.display_name
	if offer["type"] == "weapon":
		if weapon_instance(def.id) == null:
			add_weapon(def, 1)
		while weapon_instance(def.id) and weapon_instance(def.id).level < to:
			level_weapon(def.id)
	else:
		while int(passives.get(def.id, 0)) < to:
			add_or_level_passive(def.id)
	stranger_cost = minf(stranger_cost + hp_cost, 0.6)
	rebuild_sheets()
	return "%s Lv %d" % [def.display_name, to]


## Gold for skipping a level-up card: ten, plus fifteen per Skip Bonus tier from the shop.
func skip_gold() -> int:
	return 10 + 15 * player_sheet.get_int("skips")


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
	if weapons.size() >= weapon_cap() and not has_weapon(def.id):
		return null
	var inst := WeaponInstance.new(def, level_override)
	inst.mutations = mutation_defs(inst.family_id())
	weapons.append(inst)
	Save.mark_seen("weapon", def.id)
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
		Save.mark_seen("passive", id)
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


func evolution_ready(w: WeaponInstance) -> bool:
	if w.def.is_evolution or w.def.evolves_into == "":
		return false
	if w.level < w.def.max_level:
		return false
	# the path leads to the evolution: two mutations on the weapon (pass 26); the passive keys are gone
	if mutations_held(w.family_id()).size() < EVOLVE_MUTATIONS:
		return false
	return Registry.weapons.has(w.def.evolves_into)


func evolution_status(w: WeaponInstance) -> String:
	## One line for the pause screen: what is still missing.
	if w.def.is_evolution:
		return "Evolved form of " + str(Registry.weapon(w.def.evolved_from).display_name if Registry.weapon(w.def.evolved_from) else w.def.evolved_from) + "."
	if w.def.evolves_into == "":
		return "Does not evolve."
	var into: WeaponDef = Registry.weapon(w.def.evolves_into)
	var parts: Array = []
	var held := mutations_held(w.family_id()).size()
	parts.append("%d/%d mutations %s" % [held, EVOLVE_MUTATIONS, "✓" if held >= EVOLVE_MUTATIONS else "✗"])
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
	inst.mutations = w.mutations   # the path stays on the evolved form
	if idx >= 0:
		weapons[idx] = inst
	else:
		weapons.append(inst)
	Save.mark_seen("weapon", into.id)
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
func chest_roll(boss: bool = false) -> Dictionary:
	if boss:
		# the boss's chest holds a path pick: any mutation still open on any weapon held, the Stranger's loophole
		var muts: Array = []
		for wi in weapons:
			for m: MutationDef in Registry.mutations_of(wi.family_id()):
				if not wi.has_mutation(m.id) and not banished.has(m.id):
					muts.append({"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true, "boss": true})
			if character:
				for hm: MutationDef in Registry.hero_mutations(character.id):
					if hm.weapon == wi.family_id() and not wi.has_mutation(hm.id):
						muts.append({"type": "mutation", "id": hm.id, "def": hm, "level_from": 0, "level_to": 1, "is_new": true, "boss": true})
		if not muts.is_empty():
			return muts[randi() % muts.size()]
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
		"mutation":
			var md: MutationDef = r.get("def")
			if md and add_mutation(md.id, true):
				return md.display_name
			add_gold(60)
			return "+60 gold"
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
	return map.timeline.stage_mult(stage, endless_seconds())


## Seconds into endless (0 before it).
func endless_seconds() -> float:
	if not endless or map == null or map.timeline == null:
		return 0.0
	return maxf(elapsed - map.timeline.stage_length * map.timeline.stages, 0.0)


## The endless wave the run is in, 1-based (0 outside endless).
func endless_wave() -> int:
	if not endless or map == null or map.timeline == null:
		return 0
	return map.timeline.endless_wave(endless_seconds()) + 1


func summary() -> Dictionary:
	return {
		"time": elapsed, "stage": stage + 1, "level": level, "kills": kills, "gold": run_gold,
		"extracted": extracted, "died": died, "damage_by_weapon": damage_by_weapon.duplicate(),
		"kills_by_weapon": kills_by_weapon.duplicate(), "evolutions": evolutions, "chests": chests_opened,
		"character": character.display_name if character else "", "map": map.display_name if map else "",
	}
