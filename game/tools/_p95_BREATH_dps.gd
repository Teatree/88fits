## Pass 95 (lane BREATH): the weapons' estimates side by side, for the Dragon's Breath's ladder: every base weapon in
## play at level 1 (bare) and at level 5 with its three path mutations, and every evolution with its family's path, on a
## fresh level-1 Drifter's sheet: the pause screen's dps (WeaponInstance.dps_estimate, the crowd in) and HeroPower's
## single-target dps (the crowd out, the burn or poison for its uptime). Written to `out=` (a file: Godot prints nothing
## to a redirected console on Windows).
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p95_BREATH_dps.gd -- out=tools/dl/p95/BREATH/dps.txt
extends SceneTree

var _out := "user://p95_breath_dps.txt"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var reg = root.get_node("Registry")
	var run = root.get_node("Run")
	var sheet: StatSheet = run.hero_sheet(reg.character("drifter"), 1)
	var lines: Array = []
	lines.append("%-20s %-5s %-6s %-6s %-6s %-7s %-8s %-8s  %s" % ["weapon", "lvl", "cd", "dmg", "range", "burn", "dps", "1-tgt", "path"])
	var rows: Array = []
	for w in reg.base_weapons():
		if w.hidden:
			continue
		rows.append(_row(reg, sheet, w, 1, []))
		var path: Array = reg.mutations_of(w.id).map(func(m): return m.id)
		rows.append(_row(reg, sheet, w, 5, path))
		var ev = reg.weapon(w.evolves_into)
		if ev:
			rows.append(_row(reg, sheet, ev, 1, path))
	for r in rows:
		lines.append(r)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("\n".join(lines))
	quit(0)


func _row(reg, sheet: StatSheet, w, level: int, path: Array) -> String:
	var inst := WeaponInstance.new(w, level)
	for mid in path:
		var m = reg.mutation(mid)
		if m:
			inst.mutations.append(m)
	inst.rebuild(sheet, [inst])
	var burn := ""
	if inst.stat("fire_damage", 0.0) > 0.0:
		burn = "%.0f/%.1fs" % [inst.stat("fire_damage"), inst.stat("fire_duration")]
	elif inst.stat("poison_damage", 0.0) > 0.0:
		burn = "p%.0f" % inst.stat("poison_damage")
	return "%-20s %-5d %-6.2f %-6.1f %-6.1f %-7s %-8.1f %-8.1f  %s" % [w.id, level, inst.stat("cooldown"), inst.stat("damage"), inst.stat("range"), burn, inst.dps_estimate(), HeroPower.weapon_dps(inst), ",".join(path)]
