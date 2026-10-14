## Pass 76 (lane UI) scratch capture: the pause menu's Stats tab mid-run, with stats changed since the start by every
## kind of source (the Upgrade board at the start, cards and passive items, a hero level's signature stat, two gifts of
## one Totem spirit and one of another, the Stranger's cut, a timed Berserk), the same build before and after the change.
## Windowed, bounded waits and a watchdog:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p76_UI_stats_shot.gd -- out=<dir> [inset=130] [hero=solenne]
## Writes <out>/stats_<state>.png. The save is put back as it was (the tool runs in the arena's sandbox too).
extends SceneTree

const WATCHDOG_S := 150.0

var _out := "user://p76_ui_stats"
var _inset := -1
var _hero := "solenne"
var _run
var _save
var _reg
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("hero="):
			_hero = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_ui_stats: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("stats_" + name + ".png"))
	print("p76_ui_stats: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	# the Upgrade board as a player halfway up it would have it: three Padding ranks, two Drive ranks of its second form
	# (cooldown), one Stride rank (move speed)
	_save.data["talents"] = {"grit": {"picks": [0, 0, 0], "rank": 3, "form": 0},
		"drive": {"picks": [1, 1], "rank": 2, "form": 1}, "stride": {"picks": [0], "rank": 1, "form": 0}}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "sun_scepter", "level": 3, "character": _hero, "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_ui_stats: no game scene")
		_save.data = keep
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(3.2)
	g.hud._banner.visible = false
	# the start: nothing taken yet (the Upgrade board's ranks are the start)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "sun_scepter", 3)
	_run.build_changed.emit()
	g.open_pause()
	g.pause_screen._tab = 1
	g.pause_screen._refresh()
	await _wait(0.6)
	await _shot("0_start")
	g.close_pause()
	await _wait(0.3)
	# eight minutes in: weapons, cards, passive items, a level's signature stat, totem gifts, the Stranger, a Berserk
	for it in [["weapon", "sun_scepter", 4], ["weapon", "revolver", 3], ["weapon", "molotov", 2],
			["passive", "brawn", 3], ["passive", "haste", 2], ["passive", "stride", 2], ["passive", "vigour", 2],
			["passive", "deadeye", 1], ["passive", "thirst", 1], ["passive", "beer", 2], ["passive", "quickdraw", 1],
			["passive", "magnet", 1]]:
		_run.debug_set_item(it[0], it[1], it[2])
	_run.level = 12
	_run.elapsed = 482.0
	_run.take_totem_boon({"id": "whale", "name": "El-kolie", "animal": "the Whale", "stat": "max_hp", "op": "add", "value": 10.0})
	_run.take_totem_boon({"id": "whale", "name": "El-kolie", "animal": "the Whale", "stat": "max_hp", "op": "add", "value": 12.0})
	_run.take_totem_boon({"id": "wolf", "name": "Le-loo", "animal": "the Wolf", "stat": "move_speed", "op": "mul", "value": 0.05})
	_run.stranger_cost = 0.1
	var rage = _reg.pickup("rage")
	if rage:
		_run.add_timed_effects(rage.id, rage.display_name, rage.effects, 14.0)
	_run.rebuild_sheets()
	g.open_pause()
	g.pause_screen._tab = 1
	g.pause_screen._stat = "max_hp"
	g.pause_screen._refresh()
	await _wait(0.6)
	await _shot("1_max_hp")
	for st in ["cooldown", "move_speed", "haste", "debuff_duration", "might"]:
		g.pause_screen._stat = st
		g.pause_screen._refresh()
		await _wait(0.5)
		await _shot("2_" + st)
	# the list scrolled to its end (the stats that changed outside the core list, Kills)
	g.pause_screen._stat = ""
	g.pause_screen._refresh()
	await _wait(0.5)
	await _shot("3_closed")
	g.pause_screen._scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("4_scrolled")
	g.close_pause()
	await _wait(0.2)
	_save.data = keep
	print("p76_ui_stats: done -> ", _out)
	quit(0)
