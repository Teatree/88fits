## The Bounty Board (pass 111, lane WANTED; Garry: "Wanted Poster functionality ... extra coin rewards for completing
## harder tasks ... a nice config for me to be able to set it up easily in LevelEditor ... weights of each different task
## ... Always a choice of 3 ... some difficulty score ... scale with Player progression ... Should not show locked items,
## heroes, enemies as a goal ... NOT available for Players who are playing for the first time").
## Pass 112 (Garry: "this should appear at the beginning of a run right after the descend sequence. And make it so it's
## not a full screen, but more like floating posters instead"): once the hero has landed from the spawn beam, `choices`
## Wanted posters float in over the paused run (ui/BountyPosters.gd, Game._offer_bounty) and the player takes one, or none
## (pass 111's full-screen board before the run is gone). Each poster is a task of one type drawn by its `weight`
## among the types that have a target this run; its number is rolled in the stage's range grown with progression, its
## difficulty is where that number fell in the range (the type's `difficulty` [easy end, hard end]), its reward comes
## from the difficulty. The run tracks it (core/systems/WantedRun.gd) and pays it at its end, only when done.
## Everything Garry tunes is content/wanted/wanted.json (the Level Editor's Wanted tab, tools/level_editor/wanted.js,
## whose wanted_model.js mirrors the pure functions here); every rule is in BALANCING.md 54.WANTED and 55.WANTED.
## The pure part (roll, make_contract, difficulty_of, reward_for, scaled_range, eligible_types, type_chances) reads only
## its arguments: a config and a context (context() builds it from the Registry and the save), so the tests and the
## editor roll the same posters from the same facts.
class_name WantedBoard
extends RefCounted

const CONFIG_PATH := "res://content/wanted/wanted.json"
## The save's own key (no other code reads it): {boards: {"map|stage|hero": {"hash", "posters"}}, taken, done, paid}.
const SAVE_KEY := "wanted"
## The source the reward is banked under (Currency.add, Save.add_gold for gold; "bounty" is the Bounty Hunter perk's run
## source).
const GOLD_SOURCE := "wanted_contract"

## The task types: what a poster targets ("" none: the stage, the hero, the chests...), whether it rolls a number from
## `n`, and whether a lower number is the harder one (the boss's seconds). The rest of a type is its JSON entry.
const TYPES := {
	"kill_enemy": {"target": "enemy", "param": true, "down": false},
	"kill_weapon": {"target": "weapon", "param": true, "down": false},
	"kill_specials": {"target": "", "param": true, "down": false},
	"kill_elites": {"target": "", "param": true, "down": false},
	"kill_total": {"target": "", "param": true, "down": false},
	"boss_fast": {"target": "boss", "param": true, "down": true},
	"hp_floor": {"target": "boss", "param": true, "down": false},
	"beat_stage": {"target": "", "param": false, "down": false},
	"hero_level": {"target": "", "param": true, "down": false},
	"max_weapon": {"target": "weapon", "param": false, "down": false},
	"evolve_item": {"target": "evolve", "param": false, "down": false},
	"open_chests": {"target": "", "param": true, "down": false},
	"collect_coins": {"target": "", "param": true, "down": false},
	# pass 113 (lane TASKS): damage with a weapon, HP restored by an item or a source, an item to a level, barrels,
	# Totem gifts, fire or poison damage (BALANCING 56.TASKS)
	"damage_weapon": {"target": "weapon", "param": true, "down": false},
	"heal_item": {"target": "item", "param": true, "down": false},
	"heal_source": {"target": "source", "param": true, "down": false},
	"item_level": {"target": "item", "param": false, "down": false},
	"barrels": {"target": "", "param": true, "down": false},
	"totems": {"target": "", "param": true, "down": false},
	"element_damage": {"target": "element", "param": true, "down": false},
}
## The order the types are listed in (the editor, the tests).
const TYPE_ORDER := ["kill_enemy", "kill_weapon", "kill_specials", "kill_elites", "kill_total", "boss_fast", "hp_floor",
	"beat_stage", "hero_level", "max_weapon", "evolve_item", "open_chests", "collect_coins", "damage_weapon", "heal_item",
	"heal_source", "item_level", "barrels", "totems", "element_damage"]
## Pass 113 (lane TASKS): the types whose number is rolled after the target is drawn, so a target's own factor in the
## type's `target_mult` {id: factor} scales its range (a Cake heals far less than Death; a Healing Well less than Hearts).
const TARGET_FIRST := ["damage_weapon", "heal_item", "heal_source", "element_damage"]
## The elements' names on a poster (its {target}; {element} is the word in lower case).
const ELEMENT_NAMES := {"fire": "Fire", "poison": "Poison"}
## The config's top keys when the file lacks one (a missing key never breaks the board).
const DEFAULTS := {"enabled": true, "choices": 3, "rerolls": 0, "unlock": {"runs": 1}, "creatures_met_only": true,
	"items_seen_only": true, "progress": {"param_growth": 0.15},
	"reward": {"base": 40, "per_point": 60, "progress_growth": 0.5, "stage_mult": [1.0, 1.25, 1.5], "round": 5, "currency": "gold"},
	"tasks": []}
## The board never shows more posters than this (the screen has room for three in a row).
const MAX_CHOICES := 3

static var _cfg: Dictionary = {}
static var _cfg_loaded := false


# ---------------------------------------------------------------- the config

## The config (content/wanted/wanted.json over DEFAULTS), read once; `reload` reads the file again (the tests, a tool).
static func config(reload := false) -> Dictionary:
	if _cfg_loaded and not reload:
		return _cfg
	var d: Dictionary = {}
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			d = parsed
		else:
			push_warning("WantedBoard: %s is not a JSON object; the board uses its defaults" % CONFIG_PATH)
	_cfg = normalized(d)
	_cfg_loaded = true
	return _cfg


## `d` with every top key DEFAULTS has (a sub-dictionary merged key by key).
static func normalized(d: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for k in d.keys():
		if out.get(k) is Dictionary and d[k] is Dictionary:
			(out[k] as Dictionary).merge(d[k], true)
		else:
			out[k] = d[k]
	if not (out.get("tasks") is Array):
		out["tasks"] = []
	return out


## Sets the config the board reads (the tests, the editor's roll in a tool); {} reads the file again.
static func set_config(d: Dictionary) -> void:
	if d.is_empty():
		config(true)
		return
	_cfg = normalized(d)
	_cfg_loaded = true


## The currency the posters pay in (`reward.currency`, gold by default; Currency.of reads an unknown one as gold).
static func currency() -> String:
	return Currency.of(str((config().get("reward", {}) as Dictionary).get("currency", "gold")))


## The JSON entry of task type `type` in `cfg` ({} when it has none).
static func task_cfg(cfg: Dictionary, type: String) -> Dictionary:
	for t in cfg.get("tasks", []):
		if t is Dictionary and str(t.get("type", "")) == type:
			return t
	return {}


# ---------------------------------------------------------------- who sees the board

## The board is on (`enabled`) and this save has finished `unlock.runs` runs (Save.total "runs": every run that reached
## its end, a death too); a first-time player never sees it (Garry: "NOT available for Players who are playing for the
## first time").
static func unlocked(cfg: Dictionary = {}) -> bool:
	var c := cfg if not cfg.is_empty() else config()
	if not bool(c.get("enabled", true)):
		return false
	var need := maxi(int((c.get("unlock", {}) as Dictionary).get("runs", 1)), 1)
	return Save.total("runs") >= need


## Progression (BALANCING 54.WANTED): the stages of map `map_id` this save has beaten (0 to the map's stage count).
static func progress_level(map_id: String) -> int:
	var n := 0
	for b in Save.stages_beaten(map_id):
		if bool(b):
			n += 1
	return n


## Whether a run of stage `stage` on `map_id` with hero `hero_id` is offered the posters: it is unlocked and the stage
## has at least one poster to offer.
static func due(map_id: String, stage: int, hero_id: String) -> bool:
	if not unlocked():
		return false
	var ctx := context(map_id, stage, hero_id)
	return not ctx.is_empty() and not eligible_types(config(), ctx).is_empty()


# ---------------------------------------------------------------- the context: what this run can target

## The facts a roll reads for a run of stage `stage_i` (0-based) on `map_id` with hero `hero_id`, from the Registry and the
## save: {map, stage, stage_name, window [start, end], P, beaten, hero {id, name, start}, boss {id, name, met}, creatures
## [{id, name, seconds, elite, met}], gear [{id, name, met}], elite_boss [{id, name, met}], special_chance [{id, name, met}],
## elite_estimate, weapons [{id, name, start, seen, evolves, max_level}], cards [{id, name, seen, evolves, max_level}]}.
## {} for an unknown map or hero.
static func context(map_id: String, stage_i: int, hero_id: String) -> Dictionary:
	var m: MapDef = Registry.map(map_id)
	var hero: CharacterDef = Registry.character(hero_id)
	if m == null or m.timeline == null or hero == null:
		return {}
	var tl: WaveTimeline = m.timeline
	var k: int = tl.stage_clamp(stage_i)
	var s0: float = tl.stage_start(k)
	var s1: float = tl.stage_end(k)
	var start: WeaponDef = Registry.start_weapon_for(hero)
	var boss_id: String = tl.stage_boss(k)
	var bd: EnemyDef = Registry.enemy(boss_id) if boss_id != "" else null
	var ctx := {"map": map_id, "stage": k, "stage_name": tl.stage_name(k), "window": [s0, s1],
		"P": progress_level(map_id), "beaten": Save.stage_beaten(map_id, k),
		"hero": {"id": hero.id, "name": hero.display_name, "start": start.id if start else ""},
		"boss": {"id": bd.id, "name": bd.display_name, "met": Save.enemy_met(bd.id)} if bd else {}}
	# the creatures on the stage's roster (a row naming one creature, no Elite modifier, not all specials, not a one-off),
	# with the seconds the roster holds them inside the window (overlapping rows counted once)
	var spans: Dictionary = {}
	for r in tl.roster:
		if not (r is Dictionary):
			continue
		var row: Dictionary = r
		if not WaveTimeline.row_single_enemy(row) or WaveTimeline.row_elite(row) != "" or bool(row.get("special", false)) \
				or str(row.get("pace", "")) == "once":
			continue
		var a := maxf(float(row.get("t", 0.0)), s0)
		var until = row.get("until")
		var b := minf(float(until) if until != null else INF, s1)
		if b <= a:
			continue
		var id := str(row.get("enemy", ""))
		if not spans.has(id):
			spans[id] = []
		(spans[id] as Array).append([a, b])
	var creatures: Array = []
	for id: String in spans.keys():
		var def: EnemyDef = Registry.enemy(id)
		if not _creature_ok(def):
			continue
		creatures.append({"id": id, "name": def.display_name, "seconds": union_length(spans[id]),
			"elite": def.archetype == "elite", "met": Save.enemy_met(id), "special": float(def.variance.get("special_chance", 0.0)) > 0.0})
	creatures.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["id"]) < str(y["id"]))
	ctx["creatures"] = creatures
	# the specials' own creatures (the timeline's specials pool: the Rocketeer, the Saiga Sniper...) that reach this stage
	var gear: Array = []
	var sp: Dictionary = tl.specials if tl.specials is Dictionary else {}
	if not sp.is_empty() and s1 > float(sp.get("from", 0.0)):
		for row in sp.get("pool", []):
			if row is Dictionary and int(row.get("stage", 1)) <= k + 1:
				var gd: EnemyDef = Registry.enemy(str(row.get("enemy", "")))
				if _creature_ok(gd):
					gear.append({"id": gd.id, "name": gd.display_name, "met": Save.enemy_met(gd.id)})
	ctx["gear"] = gear
	# the Elites the stage brings: its elite_boss events and its Elite rows' waves inside the window
	var elite_boss: Array = []
	var estimate := 0
	for ev in tl.events:
		if ev is Dictionary and str(ev.get("type", "")) == "elite_boss":
			var t := float(ev.get("t", 0.0))
			if t >= s0 and t < s1:
				estimate += 1
				var ids: Array = ev.get("enemy") if ev.get("enemy") is Array else [str(ev.get("enemy", ""))]
				for eid in ids:
					var ed: EnemyDef = Registry.enemy(str(eid))
					if _creature_ok(ed) and elite_boss.filter(func(x: Dictionary) -> bool: return x["id"] == ed.id).is_empty():
						elite_boss.append({"id": ed.id, "name": ed.display_name, "met": Save.enemy_met(ed.id)})
	for r in tl.roster:
		if r is Dictionary and WaveTimeline.row_elite(r) != "":
			for tk in WaveTimeline.row_wave_times(r, s1):
				if float(tk) >= s0 and float(tk) < s1:
					estimate += maxi(int((r as Dictionary).get("count", 1)), 1)
	ctx["elite_boss"] = elite_boss
	ctx["elite_estimate"] = estimate
	# the weapons this hero may find in this stage (not hidden, unlocked, his or anyone's, open by this stage) and his own
	var weapons: Array = []
	for w: WeaponDef in Registry.base_weapons():
		var own := start != null and w.id == start.id
		if not own:
			if w.hidden or not Registry.is_unlocked("weapon", w.id) or (w.hero != "" and w.hero != hero.id):
				continue
			if w.from_stage > 0 and k + 1 < w.from_stage:
				continue
		var evo: WeaponDef = Registry.weapon(w.evolves_into) if w.evolves_into != "" else null
		weapons.append({"id": w.id, "name": w.display_name, "start": own, "seen": own or Save.seen("weapon", w.id),
			"evolves": evo != null and not Registry.is_hidden(evo), "max_level": maxi(w.max_level, 1)})
	ctx["weapons"] = weapons
	# the cards (line items) the run may be offered, and whether each evolves
	var cards: Array = []
	for p: PassiveDef in Registry.unlocked_passives():
		if not p.is_line() or (p.from_stage > 0 and k + 1 < p.from_stage):
			continue
		var into: PassiveDef = Registry.passive(p.evolves_into) if p.evolves_into != "" else null
		cards.append({"id": p.id, "name": p.display_name, "seen": Save.seen("passive", p.id),
			"evolves": into != null and not into.hidden, "max_level": maxi(p.max_level, 1)})
	ctx["cards"] = cards
	_task_context(ctx, tl, k, weapons, cards)
	return ctx


## Pass 113 (lane TASKS): the facts the new types read, added to `ctx`: passive_items [{id, name, seen, max_level (its
## ladder's top)}], heal_items [{id, name, kind card | passive, seen}] (TaskTally.heal_items, unlocked, open by this
## stage), heal_sources [{kind pickup | structure, id, name}] (a healing power-up the map drops by kills or out of a
## barrel, a healing structure the map places), totem_poles (the fewest Totem Poles the map stands: 0 with none) and
## elements [{id, name}] (fire / poison when an item this hero may find carries it, a weapon's path mutations included).
static func _task_context(ctx: Dictionary, tl: WaveTimeline, k: int, weapons: Array, cards: Array) -> void:
	var items: Array = []
	for p: PassiveDef in Registry.unlocked_passives():
		if not p.is_item() or (p.from_stage > 0 and k + 1 < p.from_stage):
			continue
		items.append({"id": p.id, "name": p.display_name, "seen": Save.seen("passive", p.id), "max_level": p.ladder_top()})
	ctx["passive_items"] = items
	var heals: Array = []
	for p: PassiveDef in TaskTally.heal_items():
		if p.hidden or not Registry.is_unlocked("passive", p.id) or (p.from_stage > 0 and k + 1 < p.from_stage):
			continue
		heals.append({"id": p.id, "name": p.display_name, "kind": "card" if p.is_line() else "passive", "seen": Save.seen("passive", p.id)})
	ctx["heal_items"] = heals
	var sources: Array = []
	var pick_ids: Array = []
	for r in tl.pickups.get("roster", []):
		if r is Dictionary and float((r as Dictionary).get("weight", 0.0)) > 0.0:
			pick_ids.append(str((r as Dictionary).get("id", "")))
	for kind_key in ["brown", "black"]:
		var bk = tl.barrels.get(kind_key) if tl.barrels is Dictionary else null
		if bk is Dictionary and float((bk as Dictionary).get("powerup_chance", 0.0)) > 0.0:
			for r in (bk as Dictionary).get("powerups", []):
				if r is Dictionary and float((r as Dictionary).get("weight", 0.0)) > 0.0:
					pick_ids.append(str((r as Dictionary).get("id", "")))
	for pid in pick_ids:
		var pd: PickupDef = Registry.pickup(str(pid))
		if TaskTally.pickup_heals(pd) and sources.filter(func(x: Dictionary) -> bool: return x["id"] == pd.id and x["kind"] == "pickup").is_empty():
			sources.append({"kind": "pickup", "id": pd.id, "name": pd.display_name})
	var placed: Array = _map_structures(tl)
	var poles := 0
	for sd: StructureDef in placed:
		if TaskTally.structure_heals(sd):
			sources.append({"kind": "structure", "id": sd.id, "name": sd.display_name})
		if sd.effect_kind == "totem":
			var pm := StructureManager.per_map_range(sd)
			poles += maxi(pm.x, 0) if pm.x >= 0 else 1
	ctx["heal_sources"] = sources
	ctx["totem_poles"] = poles
	var els: Array = []
	for el: String in TaskTally.ELEMENTS:
		if _element_reachable(el, weapons, cards, items):
			els.append({"id": el, "name": str(ELEMENT_NAMES.get(el, el.capitalize()))})
	ctx["elements"] = els


## The structures map timeline `tl` places (its `structures.roster`, else every one; never a hidden one), as
## StructureManager.setup draws them.
static func _map_structures(tl: WaveTimeline) -> Array:
	var roster: Array = tl.structures.get("roster", []) if tl.structures is Dictionary else []
	var defs: Array = []
	if tl.structures.is_empty():
		return defs
	if roster.is_empty():
		defs = Registry.structures.values()
	else:
		for id in roster:
			var d: StructureDef = Registry.structure(str(id))
			if d:
				defs.append(d)
	defs = StructureManager.in_play(defs)
	defs.sort_custom(func(a: StructureDef, b: StructureDef) -> bool: return a.id < b.id)
	return defs


## Whether element `el` can come into a run of these weapons (theirs, their evolution's, their path mutations'), cards and
## passive items (Run.element_of reads an item's `element`, else its stats).
static func _element_reachable(el: String, weapons: Array, cards: Array, items: Array) -> bool:
	for w: Dictionary in weapons:
		var wd: WeaponDef = Registry.weapon(str(w["id"]))
		if wd == null:
			continue
		if Run.element_of(wd) == el:
			return true
		for md in Registry.mutations_of(wd.id):
			if md is MutationDef and Run.element_of(md as ContentDef) == el:
				return true
	for list: Array in [cards, items]:
		for x: Dictionary in list:
			var pd: PassiveDef = Registry.passive(str(x["id"]))
			if pd and Run.element_of(pd) == el:
				return true
	return false


## A creature a poster may name: there, not hidden, not retired, not a boss, not a training dummy.
static func _creature_ok(def: EnemyDef) -> bool:
	return def != null and not def.hidden and not def.retired and def.archetype != "boss" and def.brain != "dummy"


## The length of the union of the spans [[a, b], ...] (overlaps counted once).
static func union_length(spans: Array) -> float:
	var s := spans.duplicate()
	s.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var total := 0.0
	var cur_a := -INF
	var cur_b := -INF
	for sp: Array in s:
		var a := float(sp[0])
		var b := float(sp[1])
		if a > cur_b:
			if cur_b > cur_a:
				total += cur_b - cur_a
			cur_a = a
			cur_b = b
		else:
			cur_b = maxf(cur_b, b)
	if cur_b > cur_a:
		total += cur_b - cur_a
	return total


# ---------------------------------------------------------------- the pure part (wanted_model.js mirrors it)

## The candidates of a type in `ctx` under `cfg`'s rules ([] = the type cannot be offered this run).
static func targets_of(cfg: Dictionary, type: String, ctx: Dictionary) -> Array:
	var tc := task_cfg(cfg, type)
	var met_only := bool(cfg.get("creatures_met_only", true))
	var seen_only := bool(cfg.get("items_seen_only", true))
	match type:
		"kill_enemy":
			var min_s := float(tc.get("min_seconds", 40.0))
			return (ctx.get("creatures", []) as Array).filter(func(c: Dictionary) -> bool:
				return not bool(c.get("elite", false)) and float(c.get("seconds", 0.0)) >= min_s and (bool(c.get("met", false)) or not met_only))
		"kill_weapon", "max_weapon":
			return (ctx.get("weapons", []) as Array).filter(func(w: Dictionary) -> bool:
				return bool(w.get("start", false)) or bool(w.get("seen", false)) or not seen_only)
		"evolve_item":
			var out: Array = []
			for w: Dictionary in ctx.get("weapons", []):
				if bool(w.get("start", false)) and bool(w.get("evolves", false)):
					out.append(w.duplicate().merged({"kind": "weapon"}, true))
			for c: Dictionary in ctx.get("cards", []):
				if bool(c.get("evolves", false)) and (bool(c.get("seen", false)) or not seen_only):
					out.append(c.duplicate().merged({"kind": "card"}, true))
			return out
		"boss_fast", "hp_floor":
			var b: Dictionary = ctx.get("boss", {})
			return [b] if str(b.get("id", "")) != "" and (bool(b.get("met", false)) or not met_only) else []
		"kill_elites":
			return [{"id": ""}] if int(ctx.get("elite_estimate", 0)) >= 1 else []
		"beat_stage":
			return [{"id": ""}] if str((ctx.get("boss", {}) as Dictionary).get("id", "")) != "" else []
		# pass 113 (lane TASKS)
		"damage_weapon":
			return (ctx.get("weapons", []) as Array).filter(func(w: Dictionary) -> bool:
				return bool(w.get("start", false)) or bool(w.get("seen", false)) or not seen_only)
		"heal_item":
			return (ctx.get("heal_items", []) as Array).filter(func(x: Dictionary) -> bool:
				return bool(x.get("seen", false)) or not seen_only)
		"heal_source":
			return (ctx.get("heal_sources", []) as Array).duplicate()
		"item_level":
			var min_lv := maxi(int(tc.get("min_level", 2)), 1)
			var out2: Array = []
			for w: Dictionary in ctx.get("weapons", []):
				if (bool(w.get("start", false)) or bool(w.get("seen", false)) or not seen_only) and int(w.get("max_level", 1)) >= min_lv:
					out2.append(w.duplicate().merged({"kind": "weapon"}, true))
			for list_key: String in ["cards", "passive_items"]:
				for x: Dictionary in ctx.get(list_key, []):
					if (bool(x.get("seen", false)) or not seen_only) and int(x.get("max_level", 1)) >= min_lv:
						out2.append(x.duplicate().merged({"kind": "card" if list_key == "cards" else "passive"}, true))
			return out2
		"totems":
			return [{"id": "totem_pole"}] if int(ctx.get("totem_poles", 0)) >= 1 else []
		"element_damage":
			return (ctx.get("elements", []) as Array).duplicate()
	return [{"id": ""}]


## The types that can be offered this run, with their weights: [{type, weight}] in TYPE_ORDER (a type off, weighing
## nothing, unknown or without a target is left out).
static func eligible_types(cfg: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for type: String in TYPE_ORDER:
		var tc := task_cfg(cfg, type)
		if tc.is_empty() or not bool(tc.get("on", true)):
			continue
		var w := float(tc.get("weight", 0.0))
		if w <= 0.0 or targets_of(cfg, type, ctx).is_empty():
			continue
		out.append({"type": type, "weight": w})
	return out


## Each eligible type's chances (the editor's table): {type: {"first": share of the weight (the chance to be the first
## poster), "board": the chance to be one of the `choices` posters}}, the draws without putting back.
static func type_chances(cfg: Dictionary, ctx: Dictionary) -> Dictionary:
	var el := eligible_types(cfg, ctx)
	var n := clampi(int(cfg.get("choices", 3)), 1, MAX_CHOICES)
	var total := 0.0
	for e: Dictionary in el:
		total += float(e["weight"])
	var out: Dictionary = {}
	for e: Dictionary in el:
		out[e["type"]] = {"first": float(e["weight"]) / total if total > 0.0 else 0.0, "board": 0.0}
	_board_chances(el, n, 1.0, out)
	return out


## Every ordered draw of `left` more posters from `pool`, adding each type's chance to be drawn (exact; 13 types and
## three draws are 1,716 paths).
static func _board_chances(pool: Array, left: int, p: float, out: Dictionary) -> void:
	if left <= 0 or pool.is_empty():
		return
	var total := 0.0
	for e: Dictionary in pool:
		total += float(e["weight"])
	if total <= 0.0:
		return
	for i in pool.size():
		var e: Dictionary = pool[i]
		var pi := p * float(e["weight"]) / total
		out[e["type"]]["board"] = float(out[e["type"]]["board"]) + pi
		var rest := pool.duplicate()
		rest.remove_at(i)
		_board_chances(rest, left - 1, pi, out)


## The posters of a board: `choices` types drawn by weight without putting back, each made into a contract.
static func roll(cfg: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool := eligible_types(cfg, ctx)
	var n := clampi(int(cfg.get("choices", 3)), 1, MAX_CHOICES)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for e: Dictionary in pool:
			total += float(e["weight"])
		var r := rng.randf() * total
		var pick := pool.size() - 1
		for i in pool.size():
			r -= float(pool[i]["weight"])
			if r < 0.0:
				pick = i
				break
		var type := str(pool[pick]["type"])
		pool.remove_at(pick)
		var c := make_contract(cfg, type, ctx, rng)
		if not c.is_empty():
			out.append(c)
	return out


## The number range of type `tc` on stage `stage` at progression `p`: its `n` entry for the stage (the last one for a
## later stage), each end times (1 + param_growth x p) (divided by it where a lower number is harder), never past `max`.
static func scaled_range(cfg: Dictionary, type: String, tc: Dictionary, stage: int, p: int) -> Vector2:
	var ns: Array = tc.get("n", []) if tc.get("n") is Array else []
	if ns.is_empty():
		return Vector2.ZERO
	var e = ns[clampi(stage, 0, ns.size() - 1)]
	var lo := 0.0
	var hi := 0.0
	if e is Array and (e as Array).size() >= 2:
		lo = float(e[0])
		hi = float(e[1])
	elif e is float or e is int:
		lo = float(e)
		hi = float(e)
	if hi < lo:
		var sw := lo
		lo = hi
		hi = sw
	var growth := float(tc.get("growth", (cfg.get("progress", {}) as Dictionary).get("param_growth", 0.15)))
	var f := maxf(1.0 + growth * float(maxi(p, 0)), 0.05)
	if bool((TYPES.get(type, {}) as Dictionary).get("down", false)):
		lo /= f
		hi /= f
	else:
		lo *= f
		hi *= f
	if tc.has("max"):
		lo = minf(lo, float(tc["max"]))
		hi = minf(hi, float(tc["max"]))
	return Vector2(lo, hi)


## Pass 113 (lane TASKS): range `r` for target `id`, times the type's `target_mult` factor for it (1 when it has none):
## a TARGET_FIRST type's numbers sized to what that target can give (Cake 0.25 of Death's healing).
static func target_range(tc: Dictionary, r: Vector2, id: String) -> Vector2:
	var tm = tc.get("target_mult")
	if not (tm is Dictionary) or not (tm as Dictionary).has(id):
		return r
	var f := maxf(float((tm as Dictionary)[id]), 0.0)
	return r * f


## A number in range `r` rounded to `step` (at least one step).
static func roll_n(r: Vector2, step: float, rng: RandomNumberGenerator) -> int:
	var v := lerpf(r.x, r.y, rng.randf())
	return snap_n(v, step)


static func snap_n(v: float, step: float) -> int:
	var s := maxf(step, 1.0)
	return maxi(int(round(v / s) * s), int(s))


## The difficulty of number `n` in range `r` for a type running [lo, hi] (BALANCING 54.WANTED): lo at the range's easy
## end, hi at its hard end (the high end, or the low one where a lower number is harder), straight between them; an
## empty range sits in the middle. One decimal.
static func difficulty_of(lo: float, hi: float, n: float, r: Vector2, down: bool) -> float:
	var t := 0.5
	if r.y - r.x > 0.0001:
		t = clampf((n - r.x) / (r.y - r.x), 0.0, 1.0)
		if down:
			t = 1.0 - t
	return snappedf(lo + (hi - lo) * t, 0.1)


## The skulls a difficulty shows: 1 to 5.
static func skulls_of(d: float) -> int:
	return clampi(int(round(d)), 1, 5)


## The coins a poster of difficulty `d` pays on stage `stage` at progression `p` (BALANCING 54.WANTED): (base + per_point
## x d) x (1 + progress_growth x p) x the stage's stage_mult, rounded to `round` (at least one `round`).
static func reward_for(cfg: Dictionary, d: float, p: int, stage: int) -> int:
	var rw: Dictionary = cfg.get("reward", {})
	var sm: Array = rw.get("stage_mult", [1.0]) if rw.get("stage_mult") is Array else [1.0]
	var smult := float(sm[clampi(stage, 0, sm.size() - 1)]) if not sm.is_empty() else 1.0
	var raw := (float(rw.get("base", 40)) + float(rw.get("per_point", 60)) * d) * (1.0 + float(rw.get("progress_growth", 0.5)) * float(maxi(p, 0))) * smult
	var step := maxf(float(rw.get("round", 5)), 1.0)
	return maxi(int(round(raw / step) * step), int(step))


## A target drawn from `list` by weight: `weight_of` gives each one's.
static func _pick(list: Array, weight_of: Callable, rng: RandomNumberGenerator) -> Dictionary:
	if list.is_empty():
		return {}
	var total := 0.0
	for x: Dictionary in list:
		total += maxf(float(weight_of.call(x)), 0.0)
	if total <= 0.0:
		return list[0]
	var r := rng.randf() * total
	for x: Dictionary in list:
		r -= maxf(float(weight_of.call(x)), 0.0)
		if r < 0.0:
			return x
	return list[list.size() - 1]


## "{n}", "{target}", "{stage}", "{boss}", "{hero}", "{time}" filled from `vars`.
static func fill_text(tpl: String, vars: Dictionary) -> String:
	var s := tpl
	for k in vars.keys():
		s = s.replace("{%s}" % k, str(vars[k]))
	return s


## "0:45": seconds as minutes and seconds.
static func clock_of(seconds: float) -> String:
	var t := int(round(maxf(seconds, 0.0)))
	return "%d:%02d" % [t / 60, t % 60]


## One poster of type `type`: {type, target, target_kind, n, d, skulls, reward, name, text, stage, map, hero, P, still
## {kind, id, badge}}; {} when the type has no target here.
static func make_contract(cfg: Dictionary, type: String, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tc := task_cfg(cfg, type)
	var cands := targets_of(cfg, type, ctx)
	if tc.is_empty() or cands.is_empty():
		return {}
	var k := int(ctx.get("stage", 0))
	var p := int(ctx.get("P", 0))
	var hero: Dictionary = ctx.get("hero", {})
	var boss: Dictionary = ctx.get("boss", {})
	var dif: Array = tc.get("difficulty", [1.0, 3.0]) if tc.get("difficulty") is Array else [1.0, 3.0]
	var lo := float(dif[0]) if dif.size() > 0 else 1.0
	var hi := float(dif[1]) if dif.size() > 1 else lo
	var down := bool((TYPES.get(type, {}) as Dictionary).get("down", false))
	var step := float(tc.get("step", 1))
	var r := scaled_range(cfg, type, tc, k, p)
	var c := {"type": type, "target": "", "target_kind": "", "n": 0, "stage": k, "map": str(ctx.get("map", "")),
		"hero": str(hero.get("id", "")), "P": p, "still": {}}
	var vars := {"hero": str(hero.get("name", "")), "stage": str(ctx.get("stage_name", "")), "boss": str(boss.get("name", "")),
		"target": ""}
	var d := lo
	var n := 0
	# (pass 113: a TARGET_FIRST type rolls its number once its target is drawn)
	if bool((TYPES.get(type, {}) as Dictionary).get("param", false)) and not TARGET_FIRST.has(type):
		n = roll_n(r, step, rng)
	match type:
		"kill_enemy":
			var cr := _pick(cands, func(x: Dictionary) -> float: return float(x.get("seconds", 0.0)), rng)
			var cap := snap_n(float(tc.get("per_minute_cap", 30)) * float(cr.get("seconds", 0.0)) / 60.0 - maxf(step, 1.0) * 0.49, step)
			n = mini(n, cap)
			d = difficulty_of(lo, hi, n, r, down)
			c["target"] = str(cr["id"])
			c["target_kind"] = "enemy"
			vars["target"] = str(cr.get("name", cr["id"]))
			c["still"] = {"kind": "enemy", "id": str(cr["id"])}
		"kill_weapon", "max_weapon":
			var sw := float(tc.get("start_weight", 3.0))
			var wp := _pick(cands, func(x: Dictionary) -> float: return sw if bool(x.get("start", false)) else 1.0, rng)
			var bonus := 0.0 if bool(wp.get("start", false)) else float(tc.get("other_bonus", 1.0))
			if type == "max_weapon":
				n = int(wp.get("max_level", 5))
				d = snappedf(lo + bonus, 0.1)
			else:
				d = snappedf(difficulty_of(lo, hi, n, r, down) + bonus, 0.1)
			c["target"] = str(wp["id"])
			c["target_kind"] = "weapon"
			vars["target"] = str(wp.get("name", wp["id"]))
			c["still"] = {"kind": "weapon", "id": str(wp["id"])}
		"evolve_item":
			var sw2 := float(tc.get("start_weight", 1.0))
			var it := _pick(cands, func(x: Dictionary) -> float: return sw2 if str(x.get("kind", "")) == "weapon" else 1.0, rng)
			var is_weapon := str(it.get("kind", "")) == "weapon"
			d = snappedf(hi if is_weapon else lo, 0.1)
			n = 1
			c["target"] = str(it["id"])
			c["target_kind"] = "weapon" if is_weapon else "card"
			vars["target"] = str(it.get("name", it["id"]))
			c["still"] = {"kind": "weapon" if is_weapon else "card", "id": str(it["id"])}
		"kill_specials":
			d = difficulty_of(lo, hi, n, r, down)
			var g := _first_met(ctx.get("gear", []))
			if g.is_empty():
				g = _first_met((ctx.get("creatures", []) as Array).filter(func(x: Dictionary) -> bool: return bool(x.get("special", false))))
			c["still"] = {"kind": "enemy", "id": str(g["id"]), "badge": "gear"} if not g.is_empty() else {"kind": "badge", "id": "gear"}
		"kill_elites":
			n = mini(n, maxi(int(ctx.get("elite_estimate", 1)), 1))
			d = difficulty_of(lo, hi, n, r, down)
			var e := _first_met(ctx.get("elite_boss", []))
			c["still"] = {"kind": "enemy", "id": str(e["id"]), "badge": "crown"} if not e.is_empty() else {"kind": "badge", "id": "crown"}
		"kill_total":
			d = difficulty_of(lo, hi, n, r, down)
			c["still"] = {"kind": "stage", "id": str(ctx.get("map", "")), "stage": k, "badge": "skull"}
		"boss_fast":
			d = difficulty_of(lo, hi, n, r, down)
			c["target"] = str(boss.get("id", ""))
			c["target_kind"] = "boss"
			vars["time"] = clock_of(n)
			c["still"] = {"kind": "enemy", "id": str(boss.get("id", "")), "badge": "skull"}
		"hp_floor":
			d = difficulty_of(lo, hi, n, r, down)
			c["target"] = str(boss.get("id", ""))
			c["target_kind"] = "boss"
			c["still"] = {"kind": "hero", "id": str(hero.get("id", "")), "badge": "heart"}
		"beat_stage":
			d = snappedf(lo if bool(ctx.get("beaten", false)) else hi, 0.1)
			n = 1
			c["still"] = {"kind": "stage", "id": str(ctx.get("map", "")), "stage": k}
		"hero_level":
			d = difficulty_of(lo, hi, n, r, down)
			c["still"] = {"kind": "hero", "id": str(hero.get("id", ""))}
		"open_chests":
			d = difficulty_of(lo, hi, n, r, down)
			c["still"] = {"kind": "art", "id": "chest"}
		"collect_coins":
			d = difficulty_of(lo, hi, n, r, down)
			c["still"] = {"kind": "art", "id": "coin"}
		# pass 113 (lane TASKS): BALANCING 56.TASKS
		"damage_weapon":
			var sw3 := float(tc.get("start_weight", 3.0))
			var wp3 := _pick(cands, func(x: Dictionary) -> float: return sw3 if bool(x.get("start", false)) else 1.0, rng)
			var r3 := target_range(tc, r, str(wp3["id"]))
			n = roll_n(r3, step, rng)
			var bonus3 := 0.0 if bool(wp3.get("start", false)) else float(tc.get("other_bonus", 1.0))
			d = snappedf(difficulty_of(lo, hi, n, r3, down) + bonus3, 0.1)
			c["target"] = str(wp3["id"])
			c["target_kind"] = "weapon"
			vars["target"] = str(wp3.get("name", wp3["id"]))
			c["still"] = {"kind": "weapon", "id": str(wp3["id"])}
		"heal_item", "heal_source", "element_damage":
			var it3 := _pick(cands, func(_x: Dictionary) -> float: return 1.0, rng)
			var id3 := str(it3.get("id", ""))
			var r4 := target_range(tc, r, id3)
			n = roll_n(r4, step, rng)
			d = difficulty_of(lo, hi, n, r4, down)
			c["target"] = id3
			vars["target"] = str(it3.get("name", id3))
			if type == "heal_item":
				c["target_kind"] = str(it3.get("kind", "passive"))
				c["still"] = {"kind": c["target_kind"], "id": id3}
			elif type == "heal_source":
				c["target_kind"] = str(it3.get("kind", "pickup"))
				vars["targets"] = TextGen.plural_name(str(it3.get("name", id3)))
				c["still"] = {"kind": c["target_kind"], "id": id3}
			else:
				c["target_kind"] = "element"
				vars["element"] = id3
				c["still"] = {"kind": "art", "id": id3}
		"item_level":
			var sw4 := float(tc.get("start_weight", 1.0))
			var it4 := _pick(cands, func(x: Dictionary) -> float: return sw4 if bool(x.get("start", false)) else 1.0, rng)
			var top := maxi(int(it4.get("max_level", 1)), 1)
			var low := clampi(int(tc.get("min_level", 2)), 1, top)
			n = mini(low + int(floor(rng.randf() * float(top - low + 1))), top)
			d = difficulty_of(lo, hi, n, Vector2(low, top), false)
			c["target"] = str(it4["id"])
			c["target_kind"] = str(it4.get("kind", "weapon"))
			vars["target"] = str(it4.get("name", it4["id"]))
			c["still"] = {"kind": c["target_kind"], "id": str(it4["id"])}
		"barrels":
			d = difficulty_of(lo, hi, n, r, down)
			c["still"] = {"kind": "art", "id": "barrel"}
		"totems":
			n = mini(n, maxi(int(ctx.get("totem_poles", 1)), 1))
			d = difficulty_of(lo, hi, n, r, down)
			c["target"] = "totem_pole"
			c["target_kind"] = "structure"
			c["still"] = {"kind": "structure", "id": "totem_pole"}
		_:
			return {}
	if not vars.has("time"):
		vars["time"] = clock_of(n)
	vars["n"] = W.num(n) if n >= 1000 else str(n)
	c["n"] = n
	c["d"] = d
	c["skulls"] = skulls_of(d)
	c["reward"] = reward_for(cfg, d, p, k)
	c["name"] = fill_text(str(tc.get("name", "{target}")), vars)
	c["text"] = fill_text(str(tc.get("text", "")), vars)
	return c


## The first met entry of `list` ({} none).
static func _first_met(list: Array) -> Dictionary:
	for x in list:
		if x is Dictionary and bool((x as Dictionary).get("met", false)):
			return x
	return {}


# ---------------------------------------------------------------- the save: a board stays until it is used

## The save's record ({boards, taken, done, paid}), made on first ask.
static func store() -> Dictionary:
	var s = Save.data.get(SAVE_KEY)
	if not (s is Dictionary):
		s = {"boards": {}, "taken": 0, "done": 0, "paid": 0}
		Save.data[SAVE_KEY] = s
	if not ((s as Dictionary).get("boards") is Dictionary):
		(s as Dictionary)["boards"] = {}
	return s


## The posters for a run of `stage` on `map_id` with `hero_id`: the ones rolled for it before (until a choice is made: a
## run left at the posters, the app closed or the run abandoned there, meets the same three again, so a board is not
## re-rolled by leaving it), else a new roll kept in the save. [] for an unknown map or hero.
static func board_for(map_id: String, stage: int, hero_id: String, rng: RandomNumberGenerator = null) -> Array:
	var cfg := config()
	var ctx := context(map_id, stage, hero_id)
	if ctx.is_empty():
		return []
	var key := "%s|%d|%s" % [map_id, int(ctx["stage"]), hero_id]
	var h := str(JSON.stringify(cfg)).hash()
	var boards: Dictionary = store()["boards"]
	var kept = boards.get(key)
	if kept is Dictionary and int((kept as Dictionary).get("hash", 0)) == h and (kept as Dictionary).get("posters") is Array \
			and not ((kept as Dictionary)["posters"] as Array).is_empty():
		return ((kept as Dictionary)["posters"] as Array).duplicate(true)
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var posters := roll(cfg, ctx, r)
	boards[key] = {"hash": h, "posters": posters, "rerolls": int(cfg.get("rerolls", 0))}
	Save.request_save()
	return posters.duplicate(true)


## The re-rolls the board of this key has left (config `rerolls`; 0 by default).
static func rerolls_left(map_id: String, stage: int, hero_id: String) -> int:
	var b = (store()["boards"] as Dictionary).get("%s|%d|%s" % [map_id, stage, hero_id])
	return int((b as Dictionary).get("rerolls", 0)) if b is Dictionary else 0


## A new roll for this key, spending one of its re-rolls; [] (nothing spent) when none is left.
static func reroll(map_id: String, stage: int, hero_id: String) -> Array:
	var key := "%s|%d|%s" % [map_id, stage, hero_id]
	var boards: Dictionary = store()["boards"]
	var b = boards.get(key)
	if not (b is Dictionary) or int((b as Dictionary).get("rerolls", 0)) <= 0:
		return []
	var left := int((b as Dictionary)["rerolls"]) - 1
	boards.erase(key)
	var posters := board_for(map_id, stage, hero_id)
	if boards.get(key) is Dictionary:
		(boards[key] as Dictionary)["rerolls"] = left
	return posters


## The player's choice on the floating posters (a poster, or {} for "No bounty"): every kept board is gone (the next run
## rolls a new one) and a poster taken is counted. Game starts the contract itself (WantedRun.begin).
static func choose(contract: Dictionary) -> void:
	store()["boards"] = {}
	if not contract.is_empty():
		store()["taken"] = int(store().get("taken", 0)) + 1
	Save.request_save()
