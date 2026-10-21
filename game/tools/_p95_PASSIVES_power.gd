## Pass 95, lane PASSIVES: the hero's power (core/systems/HeroPower.gd: sqrt of full DPS x effective HP against a fresh
## Drifter = 1.0) with each passive item at its top, before (the committed JSON under tools/dl/p95/PASSIVES/old/) and
## after the rarity ladder, on one fixed build (the Drifter, Revolver 3, Boomstick 2, Brawn 2, hero level 10), plus the
## common items all maxed at once and every item at level 1. Headless; prints a table and writes power.json beside the
## old JSONs. Nothing touches the PC save (Save.begin_sandbox).
##   godot --headless --path game --script res://tools/_p95_PASSIVES_power.gd [-- old=<dir> out=<file>]
extends SceneTree

var _old := "res://../tools/dl/p95/PASSIVES/old"
var _out := "res://../tools/dl/p95/PASSIVES/power.json"
var _run
var _reg
var _save


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("old="):
			_old = a.substr(4)
		elif a.begins_with("out="):
			_out = a.substr(4)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _power() -> Dictionary:
	var hp := load("res://core/systems/HeroPower.gd")
	hp.call("forget")
	return hp.call("measure", _run.weapons, _run.player_sheet)


func _fresh() -> void:
	_run.end()
	_run.start(_reg.character("drifter"), _reg.map("red_canyon"))
	_run.level = 10
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "revolver", 3)
	_run.debug_set_item("weapon", "boomstick", 2)
	_run.debug_set_item("passive", "brawn", 2)
	_run.rebuild_sheets()


## The item's def from the old JSON, built as the game builds it (JsonContent.build), or null.
func _old_def(id: String):
	var path := _old.path_join(id + ".json")
	var jc := load("res://core/data/JsonContent.gd")
	var d: Dictionary = jc.call("load_json", path)
	if d.is_empty():
		return null
	var od = jc.call("build", "passives", d, "res://content/passives/%s/" % id)
	# build() derives max_level from the ladder (pass 95): the old def keeps the JSON's own top (5 / 3 / 4 / 1)
	od.max_level = int(d.get("max_level", 5))
	return od


func _with(id: String, def, level: int) -> Dictionary:
	_fresh()
	var keep = _reg.passives.get(id)
	if def != null:
		_reg.passives[id] = def
	_run.debug_set_item("passive", id, level)
	_run.rebuild_sheets()
	var m := _power()
	if def != null:
		_reg.passives[id] = keep
	return m


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var base := _with("cake", null, 0)
	var rows: Array = []
	var ids: Array = []
	for p in _reg.sorted_passives_only():
		ids.append(p.id)
	print("p95 power: base %.3f (dps %.1f, ehp %.0f)" % [base["power"], base["dps"], base["ehp"]])
	print("| item | rarity | old top | new top | power old | power new | d old | d new |")
	print("|---|---|---|---|---|---|---|---|")
	for id in ids:
		var nd = _reg.passive(id)
		var od = _old_def(id)
		var old_top: int = od.max_level if od else 0
		var m_new := _with(id, null, nd.max_level)
		var m_old := _with(id, od, old_top) if od else base
		var m_new1 := _with(id, null, 1)
		var m_old1 := _with(id, od, 1) if od else base
		var r := {"id": id, "rarity": nd.rarity, "old_top": old_top, "new_top": nd.max_level,
			"power_old": m_old["power"], "power_new": m_new["power"], "power_old_l1": m_old1["power"], "power_new_l1": m_new1["power"],
			"dps_old": m_old["dps"], "dps_new": m_new["dps"], "ehp_old": m_old["ehp"], "ehp_new": m_new["ehp"]}
		rows.append(r)
		print("| %s | %s | %d | %d | %.3f | %.3f | %+.3f | %+.3f |" % [id, nd.rarity, old_top, nd.max_level, m_old["power"], m_new["power"],
			m_old["power"] - base["power"], m_new["power"] - base["power"]])
	# the common items all maxed at once, old and new
	_fresh()
	var commons: Array = []
	for id in ids:
		if _reg.passive(id).rarity == "common":
			commons.append(id)
	for id in commons:
		_run.debug_set_item("passive", id, _reg.passive(id).max_level)
	_run.rebuild_sheets()
	var all_new := _power()
	_fresh()
	var swapped: Dictionary = {}
	for id in commons:
		var od = _old_def(id)
		if od:
			swapped[id] = _reg.passives[id]
			_reg.passives[id] = od
			_run.debug_set_item("passive", id, od.max_level)
	_run.rebuild_sheets()
	var all_old := _power()
	for id in swapped:
		_reg.passives[id] = swapped[id]
	print("p95 power: the common items maxed: old %.3f -> new %.3f (base %.3f)" % [all_old["power"], all_new["power"], base["power"]])
	var out := {"base": base, "rows": rows, "commons_old": all_old, "commons_new": all_new, "commons": commons}
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("p95 power: wrote ", _out)
	_run.end()
	quit()
