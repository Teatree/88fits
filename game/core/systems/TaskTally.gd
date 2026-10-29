## Pass 113 (lane TASKS; Garry: "Add the following task types everywhere in the game where we have tasks: Deal N Damage
## with Weapon, Restore N HP with Item (Life steal, Regen, Stand Still Regen, Crit Restore HP, etc), Restore N HP with
## (Heal Power-up, Structure), Upgrade Item to N Level, Destroy N Barrels, Claim N Totems, Deal N Poison/Fire damage"):
## what a run counts for the new task types, and how it reaches the save. The run's own tallies live in Run (cleared by
## Run.start, like kills_by_weapon): Run.damage_by_weapon (already there), Run.element_damage, Run.healed_by_item,
## Run.healed_by_source, Run.barrels_broken, Run.totems_taken. bank() adds them to the save's totals once, at the run's
## end (Game.end_run), never per hit; QuestTracker adds the part not banked yet while a run is on (run_part), so a quest
## can complete mid-run and its bar moves. Nothing counts in the debug arena, the run sim or a tool's process (counts()).
## Rules: BALANCING.md 56.TASKS.
class_name TaskTally
extends RefCounted

## The hero's stats that heal him, each read by the code that heals (Run.add_damage's life steal, Player._tick_regen's
## regen and Siesta, EnemyManager's Vulture crit heal, Game's Cake Slice drop). An item heals when its levels carry one
## (heal_items): a heal is credited to the items that put the stat on the hero's sheet, by their share of it (shares_of).
const HEAL_STATS := ["lifesteal", "regen", "still_regen", "crit_heal_chance", "heal_drop"]
const ELEMENTS := ["fire", "poison"]
const SOURCE_KINDS := ["pickup", "structure"]
## The save's totals (Save.data.totals): keyed by a weapon family's base id, an item family's base id, "<kind>:<id>" and
## the element; plain counts for barrels and totems.
const SAVE_DAMAGE := "damage_with_weapon"
const SAVE_HEAL_ITEM := "heal_with_item"
const SAVE_HEAL_SOURCE := "heal_with_source"
const SAVE_ELEMENT := "element_damage"
const SAVE_BARRELS := "barrels"
const SAVE_TOTEMS := "totems"

## The tests' switch: a tool's process (headless or a script: gdUnit, smoke_run) banks and counts too.
static var bank_in_tools := false

static var _share_sheet: StatSheet = null
static var _share_version := -1
static var _shares: Dictionary = {}


## Whether this run's tallies may count for quests and reach the save: never in the debug arena, the run sim or a tool's
## process (smoke_run, captures, the Watch) unless the tests ask (bank_in_tools).
static func counts() -> bool:
	if Run.arena or Run.sim_mode:
		return false
	return bank_in_tools or not RunAnalytics.is_tool_process()


# ---------------------------------------------------------------- what is counted, as it happens

## A heal of `got` HP that Player.heal credited to `credit`: "stat:<healing stat>" splits it among the items that give
## that stat (shares_of); "pickup:<id>" or "structure:<id>" is a heal source. Called by Player.heal only.
static func note_heal(credit: String, got: float) -> void:
	if got <= 0.0 or credit == "":
		return
	if credit.begins_with("stat:"):
		_credit_stat(credit.trim_prefix("stat:"), got)
		return
	Run.healed_by_source[credit] = float(Run.healed_by_source.get(credit, 0.0)) + got


## Regen's ticks (Player._tick_regen): `got` HP came back from `regen_rate` (regen, Deep Breath's multiple included) and
## `still_rate` (Siesta) together; each part goes to its stat's items.
static func note_regen(got: float, regen_rate: float, still_rate: float) -> void:
	var total := maxf(regen_rate, 0.0) + maxf(still_rate, 0.0)
	if got <= 0.0 or total <= 0.0:
		return
	if regen_rate > 0.0:
		_credit_stat("regen", got * regen_rate / total)
	if still_rate > 0.0:
		_credit_stat("still_regen", got * still_rate / total)


static func _credit_stat(stat: String, got: float) -> void:
	var sh := shares_of(stat)
	for root in sh.keys():
		Run.healed_by_item[root] = float(Run.healed_by_item.get(root, 0.0)) + got * float(sh[root])


## The items (by their family's base id) that put `stat` on the hero's sheet now, each with its share of the stat: its own
## adds over everything that adds to it (the sheet's base and the other sources too, which get no credit: Ironwood's
## trait, a talent, a totem gift). Only a card's or a passive item's effects count (sources "passive:<id>", "favourite:<id>"),
## its evolved form for its family. Cached until the sheet changes (StatSheet.version).
static func shares_of(stat: String) -> Dictionary:
	var sheet: StatSheet = Run.player_sheet
	if sheet == null:
		return {}
	if sheet != _share_sheet or sheet.version != _share_version:
		_share_sheet = sheet
		_share_version = sheet.version
		_shares = {}
	if _shares.has(stat):
		return _shares[stat]
	var total := maxf(float(sheet.base.get(stat, 0.0)), 0.0)
	var by_root: Dictionary = {}
	for en in sheet.entries:
		var e: Effect = en["effect"]
		if e.stat != stat or e.op != "add" or e.value <= 0.0 or StatSheet.aims_at_weapons(e):
			continue
		total += e.value
		var root := item_of_source(str(en.get("sid", en.get("source", ""))))
		if root != "":
			by_root[root] = float(by_root.get(root, 0.0)) + e.value
	var out: Dictionary = {}
	if total > 0.0:
		for r in by_root.keys():
			out[r] = float(by_root[r]) / total
	_shares[stat] = out
	return out


## The item a sheet source names ("passive:thirst", "favourite:brawn"), as its family's base id; "" for anything else.
static func item_of_source(sid: String) -> String:
	for pre in ["passive:", "favourite:"]:
		if sid.begins_with(pre):
			return passive_root(sid.trim_prefix(pre))
	return ""


## A card's or a passive item's family base: an evolved form's source (Death Risen -> Death), else itself.
static func passive_root(pid: String) -> String:
	var p: PassiveDef = Registry.passive(pid)
	var guard := 0
	while p != null and p.evolves_from != "" and guard < 4:
		var src: PassiveDef = Registry.passive(p.evolves_from)
		if src == null:
			break
		p = src
		guard += 1
	return p.id if p != null else pid


## A weapon family's base id for a weapon, an evolution or a mutation id (Registry.item_family_root); "" for a hit no
## weapon sent (the Nuke, a blast, the revive, Hot Springs' pulse, thorns).
static func weapon_root(id: String) -> String:
	return Registry.item_family_root(id) if id != "" else ""


## The items whose levels (or their evolved form's) give the hero one of HEAL_STATS: the targets a heal_item poster and a
## heal_with_item quest may name, read off the content. Base items only (an evolved form counts for its source).
static func heal_items() -> Array:
	var out: Array = []
	for p: PassiveDef in Registry.passives.values():
		if p.evolves_from != "":
			continue
		if passive_heals(p) or (p.evolves_into != "" and passive_heals(Registry.passive(p.evolves_into))):
			out.append(p)
	out.sort_custom(func(a: PassiveDef, b: PassiveDef) -> bool: return a.id < b.id)
	return out


## Whether a passive's levels carry one of HEAL_STATS on the hero.
static func passive_heals(p: PassiveDef) -> bool:
	if p == null:
		return false
	for lv in p.levels:
		if not (lv is Array):
			continue
		for e in lv:
			if e is Effect and HEAL_STATS.has((e as Effect).stat) and (e as Effect).value > 0.0 and not StatSheet.aims_at_weapons(e):
				return true
	return false


## Whether a power-up heals (a heal pickup that is not one of the small things underfoot: the Heart, not a Cake Slice).
static func pickup_heals(d: PickupDef) -> bool:
	return d != null and d.effect_kind == "heal" and not bool(d.params.get("small", false)) and not bool(d.params.has("credit_stat"))


## Whether a structure heals: the Healing Well's kind, or dice whose outcomes include the full heal.
static func structure_heals(d: StructureDef) -> bool:
	if d == null:
		return false
	if d.effect_kind == "heal":
		return true
	if d.effect_kind == "dice":
		var outs = d.params.get("outcomes", ["heal", "gold", "level", "swarm"])
		return outs is Array and (outs as Array).has("heal")
	return false


# ---------------------------------------------------------------- the save

## The run's tallies into the save's totals, once (Game.end_run, after the purse): rounded to whole points, never from the
## arena, the run sim or a tool. Returns whether it banked.
static func bank() -> bool:
	if Run.tasks_banked or not counts():
		return false
	Run.tasks_banked = true
	var by_root := run_damage_by_root()
	for root in by_root.keys():
		_add_keyed(SAVE_DAMAGE, str(root), float(by_root[root]))
	for root in Run.healed_by_item.keys():
		_add_keyed(SAVE_HEAL_ITEM, str(root), float(Run.healed_by_item[root]))
	for key in Run.healed_by_source.keys():
		_add_keyed(SAVE_HEAL_SOURCE, str(key), float(Run.healed_by_source[key]))
	for el in Run.element_damage.keys():
		_add_keyed(SAVE_ELEMENT, str(el), float(Run.element_damage[el]))
	if Run.barrels_broken > 0:
		Save.add_total(SAVE_BARRELS, Run.barrels_broken)
	if Run.totems_taken > 0:
		Save.add_total(SAVE_TOTEMS, Run.totems_taken)
	return true


static func _add_keyed(key: String, sub: String, v: float) -> void:
	var n := int(round(v))
	if n > 0 and sub != "":
		Save.add_keyed_total(key, sub, n)


## This run's damage by weapon family (the family's base id): Run.damage_by_weapon summed over each family.
static func run_damage_by_root() -> Dictionary:
	var out: Dictionary = {}
	for k in Run.damage_by_weapon.keys():
		var root := weapon_root(str(k))
		if root == "":
			continue
		out[root] = float(out.get(root, 0.0)) + float(Run.damage_by_weapon[k])
	return out


## Whether the run going on adds to the totals now: a run is on, its tallies not banked yet, and they count.
static func run_live() -> bool:
	return Run.active and not Run.tasks_banked and counts()


# ---------------------------------------------------------------- what a condition reads

## How much of task `c` (a quest condition: damage_with_weapon, heal_with_item, heal_with_source, element_damage,
## barrels_total, totems_total) this run has done so far (0 when the run cannot count).
static func run_amount(c: Dictionary) -> float:
	if not Run.active or not counts():
		return 0.0
	match str(c.get("type", "")):
		"damage_with_weapon":
			var root := weapon_root(str(c.get("weapon", "")))
			return float(run_damage_by_root().get(root, 0.0)) if root != "" else 0.0
		"heal_with_item":
			return float(Run.healed_by_item.get(passive_root(str(c.get("item", ""))), 0.0))
		"heal_with_source":
			return _source_sum(Run.healed_by_source, str(c.get("source", "")))
		"element_damage":
			return _element_sum(Run.element_damage, str(c.get("element", "")))
		"barrels_total":
			return float(Run.barrels_broken)
		"totems_total":
			return float(Run.totems_taken)
	return 0.0


## What the save holds for task `c` from runs already banked.
static func saved_amount(c: Dictionary) -> float:
	var totals: Dictionary = Save.data.get("totals", {}) if Save.data.get("totals") is Dictionary else {}
	match str(c.get("type", "")):
		"damage_with_weapon":
			var root := weapon_root(str(c.get("weapon", "")))
			return float(Save.keyed_total(SAVE_DAMAGE, root)) if root != "" else 0.0
		"heal_with_item":
			return float(Save.keyed_total(SAVE_HEAL_ITEM, passive_root(str(c.get("item", "")))))
		"heal_with_source":
			var d = totals.get(SAVE_HEAL_SOURCE, {})
			return _source_sum(d if d is Dictionary else {}, str(c.get("source", "")))
		"element_damage":
			var d2 = totals.get(SAVE_ELEMENT, {})
			return _element_sum(d2 if d2 is Dictionary else {}, str(c.get("element", "")))
		"barrels_total":
			return float(Save.total(SAVE_BARRELS))
		"totems_total":
			return float(Save.total(SAVE_TOTEMS))
	return 0.0


## The amount task `c` stands at: across runs (the save's banked part and the run's part not banked yet), or this run's
## alone when the condition says `in_one_run`.
static func amount(c: Dictionary) -> float:
	if bool(c.get("in_one_run", false)):
		return run_amount(c) if run_live() else 0.0
	return saved_amount(c) + (run_amount(c) if run_live() else 0.0)


## The sum of a {"<kind>:<id>": HP} table for `source`: "pickup:heart" that one, "pickup:" (or "structure:") every source
## of that kind; "" nothing.
static func _source_sum(d: Dictionary, source: String) -> float:
	if source == "" or not source.contains(":"):
		return 0.0
	if not source.ends_with(":"):
		return float(d.get(source, 0.0))
	var s := 0.0
	for k in d.keys():
		if str(k).begins_with(source):
			s += float(d[k])
	return s


## A heal_with_source condition's source split: ["pickup", "heart"], ["structure", ""] (any of the kind); ["", ""] when
## it names none.
static func source_parts(source: String) -> PackedStringArray:
	var i := source.find(":")
	if i <= 0:
		return PackedStringArray(["", ""])
	return PackedStringArray([source.substr(0, i), source.substr(i + 1)])


## The sum of a {element: damage} table for `el` ("" = fire and poison together).
static func _element_sum(d: Dictionary, el: String) -> float:
	if el != "":
		return float(d.get(el, 0.0))
	var s := 0.0
	for k in ELEMENTS:
		s += float(d.get(k, 0.0))
	return s


## The run's task tallies as the run record keeps them (RunAnalytics header `tasks`): damage by weapon family, fire and
## poison damage, HP restored by item and by source, barrels broken, Totem gifts taken; whole points.
static func record() -> Dictionary:
	var dmg := {}
	var by_root := run_damage_by_root()
	for r in by_root.keys():
		dmg[r] = snappedf(float(by_root[r]), 0.1)
	var heal_item := {}
	for r in Run.healed_by_item.keys():
		heal_item[r] = snappedf(float(Run.healed_by_item[r]), 0.1)
	var heal_src := {}
	for k in Run.healed_by_source.keys():
		heal_src[k] = snappedf(float(Run.healed_by_source[k]), 0.1)
	var el := {}
	for k in Run.element_damage.keys():
		el[k] = snappedf(float(Run.element_damage[k]), 0.1)
	return {"damage_by_family": dmg, "element_damage": el, "healed_by_item": heal_item, "healed_by_source": heal_src,
		"barrels": Run.barrels_broken, "totems": Run.totems_taken, "counted": counts()}
