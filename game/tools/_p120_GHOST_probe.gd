## Pass 120 lane GHOST probe: what one Undertaker's ghost deals against the hero's full DPS, build by build. For each
## build (a fresh level-1 Drifter, then difficulty_probe's b1/b2/b3 for three heroes) the hero (a god, standing) gets the
## item, a ring of very tough skeletons walks in on him, a grave is dug 3 m in front of him and its ghost plays its whole
## fight; the ghost's damage (the item's source in Run.damage_by_weapon) over its grave_seconds against HeroPower's full
## DPS and power. Headless, bounded, the save in the sandbox.
## Run: GODOT_TIMEOUT=900 bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p120_GHOST_probe.gd [-- only=drifter:b1,...]
extends SceneTree

const DP := preload("res://tools/difficulty_probe.gd")
const WATCHDOG_S := 800.0
const STONE_DOWN := 5
const CASES := [["drifter", ""], ["drifter", "b1"], ["drifter", "b2"], ["drifter", "b3"], ["calavera", "b1"],
	["calavera", "b2"], ["calavera", "b3"], ["buck", "b1"], ["buck", "b2"], ["buck", "b3"]]
var _save
var _run
var _reg
var _only := ""
var _rows: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_only = a.substr(5)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p120_probe: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for _k in range(n):
		await process_frame


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	for c: Array in CASES:
		var key := "%s:%s" % [c[0], c[1]]
		if _only != "" and not (key in _only.split(",")):
			continue
		await _case(str(c[0]), str(c[1]))
	print("p120_probe: TABLE hero build | power | full DPS | bolts | per bolt | ghost DPS (formula) | ghost DPS (measured) | share")
	for r: String in _rows:
		print("p120_probe: ROW " + r)
	quit(0)


func _launch(hero: String) -> Node:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": hero, "level": 1, "map": "red_canyon", "map_seed": 7, "spawn": false,
		"analytics": false, "stage": 1}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _frames(150)
	var g = current_scene
	if g != null and g.get("player") != null:
		g.player.god = true
	return g


func _build(hero: String, build: String) -> void:
	if build == "":
		return
	var b: Dictionary = DP.BUILDS.get(hero, {}).get(build, {})
	_run.debug_clear_items()
	for w: Array in b.get("weapons", []):
		var id: String = w[0]
		var lv: int = int(w[1])
		var def = _reg.weapon(id)
		if def == null:
			continue
		_run.debug_set_item("evolution" if def.is_evolution else "weapon", id, 99 if lv <= 0 else lv)
		var muts: Array = (w[2] as Array).duplicate()
		if def.is_evolution:
			var inst = _run.weapon_instance(id)
			if inst:
				for m in _reg.mutations_of(inst.family_id()):
					if not m.is_hero():
						muts.append(m.id)
		for m: String in muts:
			_run.debug_set_item("mutation", m, 1)
	for p: Array in b.get("passives", []):
		_run.debug_set_item("passive", p[0], int(p[1]))


func _case(hero: String, build: String) -> void:
	var g = await _launch(hero)
	if g == null:
		return
	_build(hero, build)
	_run.add_or_level_passive("undertakers_shovel")
	_run.rebuild_sheets()
	g.player.refresh_stats()
	g.enemies.kill_all(false)
	var hp_class = load("res://core/systems/HeroPower.gd")
	var m: Dictionary = hp_class.measure(_run.weapons, _run.player_sheet)
	var here: Vector3 = g.player.global_position
	for k in range(14):
		var a := TAU * float(k) / 14.0
		var p := here + Vector3(cos(a) * 7.0, 0, -3.0 + sin(a) * 6.0)
		p.y = g.map.height_at(p.x, p.z)
		g.enemies.spawn("skeleton", p, null, 1.0, 100000.0)
	var gy = g._graveyard()
	var d0: float = float(_run.damage_by_weapon.get("undertakers_shovel", 0.0))
	gy.dig(here + Vector3(0, 0, -3.0))
	var guard := 0
	while guard < 1500 and not gy.graves.is_empty() and int((gy.graves[0] as Dictionary)["phase"]) < STONE_DOWN:
		await process_frame
		guard += 1
	await _frames(120)
	var dealt: float = float(_run.damage_by_weapon.get("undertakers_shovel", 0.0)) - d0
	var secs: float = _run.player_sheet.get_stat("grave_seconds", 8.0)
	var p: float = float(m["power"])
	var n: int = gy.bolt_count(p)
	var per: float = gy.bolt_damage(p)
	var formula: float = float(n) * per / gy.num("volley_every")
	var measured := dealt / secs
	var row := "%s %s | %.2f | %.0f | %d | %.1f | %.0f | %.0f | %.1f%%" % [hero, build if build != "" else "fresh", p, float(m["dps"]),
		n, per, formula, measured, 100.0 * measured / maxf(float(m["dps"]), 0.001)]
	_rows.append(row)
	print("p120_probe: " + row + " (volleys %d bolts %d hits %d fizzles %d)" % [gy.volleys, gy.shots, gy.bolts.hits, gy.bolts.fizzles])
