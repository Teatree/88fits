## The pause menu's Stats tab, its data (pass 76, lane UI; Garry: "Stats in pause menu. Mark the stats that were changed
## since the start of the game. Provide some minimal info on which items are doing the stat changes underneath
## somewhere"): which stats the grid lists, which moved since the run began (Run.start_stat) and whether for the better,
## and the open stat's sources in two groups: "At the start" (the base, the hero, his signature stat at level 1, the
## Upgrade board) and "This run" (the signature stat's growth with his level, cards and passive items, perks, mutations,
## Totem gifts, the Stranger's cut, running bonuses, timed buffs with their seconds left). Each source is one row, its
## amounts summed (a "mul" compounded as the sheet folds it), named and drawn by its source id (StatSheet's `sid`), so
## three ranks of one talent or two gifts of one spirit are one row. Effects aimed at weapons are not in the hero's
## numbers, so not among his rows. Reads only.
class_name StatSources
extends RefCounted

const START := "start"
const RUN := "run"
## The order "This run" lists its sources in, by the kind of source id (lower first, the sheet's order within one): the
## hero's own growth, the items taken, the map's gifts, what runs by itself, then what wears off.
const RUN_ORDER := {"trait": 0, "passive": 1, "favourite": 1, "perk": 2, "mutation": 2, "totem": 3, "stranger": 3,
	"momentum": 4, "buff": 6}
## The source ids whose rows belong to the start (a "trait:" one splits: its level-1 step is the start's).
const START_KINDS := ["base", "hero", "talent"]
## The structures whose icons stand for the map's gifts on a row.
const TOTEM_STRUCTURE := "totem_pole"
const STRANGER_STRUCTURE := "hooded_figure"
## core/systems/TotemBoons.gd by path, as Run has it
const TOTEM_BOONS := preload("res://core/systems/TotemBoons.gd")


static func default_of(stat: String) -> float:
	return float(StatSheet.PLAYER_DEFAULTS.get(stat, 0.0))


## The stat on the sheet now.
static func now(sheet: StatSheet, stat: String) -> float:
	return sheet.get_stat(stat, default_of(stat))


## The stat as the run began (Run.start_stat: the snapshot start() took).
static func at_start(stat: String) -> float:
	return Run.start_stat(stat, default_of(stat))


## Whether a stat is said as a number of its own: not a "word" stat (never numbered) nor a "rule" (a sentence).
static func listable(stat: String) -> bool:
	var k := TextGen.stat_kind(stat)
	return k != "word" and k != "rule" and k != "hidden"


## Whether a stat moved since the run began by anything its unit can show.
static func changed(sheet: StatSheet, stat: String) -> bool:
	return TextGen.player_change(stat, at_start(stat), now(sheet, stat)) != ""


## The change since the run began: {"moved", "up" (the number grew), "worse" (TextGen._worse: a cut of a LOWER_BETTER
## stat is better), "text" (unsigned: "20%", "12"), "share" (said as a share of the start), "from", "to"}. Said as a share
## of where it started when every source of the stat multiplies (so "Cooldown ▼15%" reads as its "The Tower −15%" row
## does), else in the value's own unit (a percent stat in points: crit chance 1% -> 9% is "8%").
static func change(sheet: StatSheet, stat: String) -> Dictionary:
	var v0 := at_start(stat)
	var v1 := now(sheet, stat)
	var t := TextGen.player_change(stat, v0, v1)
	var share := t != "" and all_multiply(sheet, stat) and absf(v0) > 0.000001
	if share:
		var s := TextGen.player_share_change(v0, v1)
		if s != "":
			t = s
	return {"moved": t != "", "up": v1 > v0, "worse": t != "" and TextGen._worse(stat, v0, v1), "text": t, "share": share,
		"from": v0, "to": v1}


## Whether every effect on the hero's stat multiplies it (op "mul"), none adding or setting; false with none.
static func all_multiply(sheet: StatSheet, stat: String) -> bool:
	var any := false
	for en in sheet.entries:
		var e: Effect = en["effect"]
		if e.stat != stat or (sheet.scope == "player" and StatSheet.aims_at_weapons(e)):
			continue
		if e.op != "mul":
			return false
		any = true
	return any


## The stats the grid lists, in order: max HP, the core list (`core`: PauseScreen.STATS), the shield while the hero has
## one, then every other stat that moved since the run began, in StatSheet.PLAYER_DEFAULTS' order, then any other the
## sheet names (pass 76: debuff duration, weapon speed, crit damage, healing... were never listed).
static func grid_stats(sheet: StatSheet, core: Array) -> Array:
	var out: Array = ["max_hp"]
	for s in core:
		if not out.has(str(s)):
			out.append(str(s))
	if not out.has("shield_max") and (now(sheet, "shield_max") > 0.0 or changed(sheet, "shield_max")):
		out.append("shield_max")
	var rest: Array = StatSheet.PLAYER_DEFAULTS.keys()
	for s in sheet.stats():
		if not rest.has(s):
			rest.append(s)
	for s in rest:
		var st := str(s)
		if out.has(st) or not listable(st):
			continue
		if changed(sheet, st):
			out.append(st)
	return out


## The open stat's sources: {"start": [row], "run": [row]}, "At the start" opening with the base. A row: {"key", "sid",
## "kind", "name", "icon" (Texture2D or null), "def" (its ContentDef or null), "round" (a hero's badge), "text" (the
## amount: "+10%", "+22"), "value", "op", "worse", "clock" (seconds left of a timed buff, -1 none), "count" (entries
## merged into it)}.
static func rows(sheet: StatSheet, stat: String) -> Dictionary:
	var base_v := float(sheet.base.get(stat, default_of(stat)))
	var start_rows: Array = [{"key": "base", "sid": "base", "kind": "base", "name": "Base", "icon": null, "def": null,
		"round": false, "text": TextGen.player_value(stat, base_v), "value": base_v, "op": "set", "worse": false,
		"clock": -1.0, "count": 1}]
	var run_rows: Array = []
	var acc: Dictionary = {}
	var order: Array = []
	for en in sheet.entries:
		var e: Effect = en["effect"]
		if e.stat != stat or (sheet.scope == "player" and StatSheet.aims_at_weapons(e)):
			continue
		var sid := str(en.get("sid", en["source"]))
		var key := sid + "|" + e.op
		if not acc.has(key):
			acc[key] = {"sid": sid, "op": e.op, "value": 0.0, "count": 0, "source": str(en["source"])}
			order.append(key)
		var a: Dictionary = acc[key]
		match e.op:
			"mul":
				a["value"] = (1.0 + float(a["value"])) * (1.0 + e.value) - 1.0
			"set":
				a["value"] = e.value
			_:
				a["value"] = float(a["value"]) + e.value
		a["count"] = int(a["count"]) + 1
	for key in order:
		var a: Dictionary = acc[key]
		var sid := str(a["sid"])
		var op := str(a["op"])
		var v := float(a["value"])
		if sid.begins_with("trait:"):
			# the signature stat: its level-1 step was there as the run began, the rest came with his levels
			var first := _trait_value(sid.trim_prefix("trait:"), stat, op, 1)
			var r0 := _row(stat, sid, op, first, 1, str(a["source"]))
			if not r0.is_empty():
				start_rows.append(r0)
			var r1 := _row(stat, sid, op, v - first, 1, str(a["source"]))
			if not r1.is_empty():
				r1["key"] = sid + "|" + op + "|growth"
				r1["name"] = "%s · Lv %d" % [str(r1["name"]), Run.card_level()]
				run_rows.append(r1)
			continue
		var r := _row(stat, sid, op, v, int(a["count"]), str(a["source"]))
		if r.is_empty():
			continue
		if START_KINDS.has(str(r["kind"])):
			start_rows.append(r)
		else:
			run_rows.append(r)
	# "This run" by kind, the sheet's order within one (sort_custom is not stable: the index breaks ties)
	var ranked: Array = []
	for k in run_rows.size():
		ranked.append([int(RUN_ORDER.get(str(run_rows[k]["kind"]), 5)), k, run_rows[k]])
	ranked.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	run_rows = ranked.map(func(x: Array) -> Dictionary: return x[2])
	return {START: start_rows, RUN: run_rows}


## The signature stat's value for `stat` and `op` at a level (CharacterDef.level_effects summed).
static func _trait_value(hero_id: String, stat: String, op: String, level: int) -> float:
	var c: CharacterDef = Registry.character(hero_id)
	var v := 0.0
	if c == null:
		return v
	for e in c.level_effects(level):
		var x: Effect = e
		if x.stat == stat and x.op == op:
			v += x.value
	return v


## One row: the source as describe_source names and draws it, the summed amount; {} for an amount of nothing.
static func _row(stat: String, sid: String, op: String, value: float, count: int, source: String) -> Dictionary:
	if op != "set" and absf(value) < 0.000001:
		return {}
	var r := describe_source(sid, source, count)
	var e := Effect.make(stat, op, value, "player")
	r["key"] = sid + "|" + op
	r["sid"] = sid
	r["text"] = TextGen.player_effect(e)
	r["value"] = value
	r["op"] = op
	r["worse"] = op != "set" and TextGen._worse(stat, 0.0, value)
	r["count"] = count
	return r


## A source by its id: {"kind", "name", "icon", "def", "round", "clock"}. Its words (`source`) when the id is unknown
## (a running bonus no item named): "Hot Streak +5%".
static func describe_source(sid: String, source: String = "", count: int = 1) -> Dictionary:
	var out := {"kind": "", "name": source if source != "" else sid, "icon": null, "def": null, "round": false, "clock": -1.0}
	var i := sid.find(":")
	var kind := sid.substr(0, i) if i > 0 else sid
	var id := sid.substr(i + 1) if i > 0 else ""
	out["kind"] = kind if i > 0 or kind == "base" or kind == "stranger" else ""
	match kind:
		"base":
			out["name"] = "Base"
		"hero", "trait", "momentum":
			var c: CharacterDef = Registry.character(id)
			if c:
				var look: CharacterDef = Registry.played_look(c)
				out["def"] = look
				out["icon"] = look.icon if look else c.icon
				out["round"] = true
				if kind == "hero":
					out["name"] = c.display_name
				elif kind == "trait":
					out["name"] = c.trait_name if c.trait_name != "" else c.display_name
		"talent":
			var parts := id.split(":")
			var t: TalentDef = Registry.talent(parts[0])
			if t:
				var form := int(parts[1]) if parts.size() > 1 else 0
				out["name"] = "%s · %s rank %d" % [t.display_name, t.form_name(form), Save.talent_count(t.id, form)]
				out["icon"] = t.form_icon(form) if t.form_icon(form) != null else t.icon
		"passive", "favourite":
			var p: PassiveDef = Registry.passive(id)
			if p:
				out["def"] = p
				out["icon"] = p.icon
				var lv := int(Run.passives.get(id, 0))
				if kind == "favourite":
					out["name"] = "%s · favourite" % p.display_name
				else:
					out["name"] = p.display_name + (" · Lv %d" % lv if p.max_level > 1 and lv > 0 else "")
		"perk":
			var pk: PerkDef = Registry.perk(id)
			if pk:
				out["def"] = pk
				out["icon"] = pk.icon
				out["name"] = pk.display_name
		"mutation":
			var m: MutationDef = Registry.mutation(id)
			if m:
				out["def"] = m
				out["icon"] = m.icon
				out["name"] = m.display_name
		"buff":
			for tb in Run.timed:
				if str(tb.get("source", "")) == sid:
					if str(tb.get("label", "")) != "":
						out["name"] = str(tb["label"])
					out["clock"] = maxf(float(tb.get("until", 0.0)) - Run.buff_clock(), 0.0)
					break
			var d := _buff_def(id)
			if d:
				out["icon"] = d.icon
				if d is PassiveDef or d is PerkDef:
					out["def"] = d
				if out["name"] == sid or str(out["name"]).begins_with("buff:"):
					out["name"] = d.display_name
		"totem":
			for b in Run.totem_boons:
				if b is Dictionary and str((b as Dictionary).get("id", (b as Dictionary).get("stat", ""))) == id:
					out["name"] = TOTEM_BOONS.title(b)
					break
			if count > 1:
				out["name"] = "%s ×%d" % [str(out["name"]), count]
			var tp: StructureDef = Registry.structure(TOTEM_STRUCTURE)
			out["icon"] = tp.icon if tp else null
		"stranger":
			var sf: StructureDef = Registry.structure(STRANGER_STRUCTURE)
			out["icon"] = sf.icon if sf else null
	return out


## What a timed buff's id names (Run.add_timed_effects' ids): a structure ("structure:<id>"), a power-up, a perk (Tough
## Love, a periodic buff) or a passive item (Barrel Rush, Skedaddle, Counterpunch); null when none.
static func _buff_def(id: String) -> ContentDef:
	if id.begins_with("structure:"):
		return Registry.structure(id.trim_prefix("structure:"))
	var d: ContentDef = Registry.pickup(id)
	if d == null:
		d = Registry.perk(id)
	if d == null:
		d = Registry.passive(id)
	return d
