## Pass 67, lane M, scratch captures of the hero's gauge under the HUD's slots, in the debug arena as Buck: the charge at
## 60% (paper), full with Ram and three Overdrive gears (gold, the gold ring, the words) over a power-up plate and the
## boss's bar, the frame after a hit took half (the rock-red flash), and the Astro of the same build (no gauge, the column
## where it was). Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p67_gauge_shot.gd -- out=<dir> [inset=130]
extends SceneTree

var _out := "user://p67_gauge"
var _inset := -1
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p67_gauge: ", name)


## The same strip for every shot: three weapons, two lines.
func _build() -> void:
	_run.debug_clear_items()
	for it in [["weapon", "tommy_gun", 3], ["weapon", "molotov", 2], ["weapon", "boomstick", 1], ["passive", "magnet", 2],
			["passive", "energy_shield", 1]]:
		_run.debug_set_item(it[0], it[1], it[2])
	_run.build_changed.emit()


func _main() -> void:
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "tommy_gun", "level": 3, "character": "buck", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(3.2)
	# his own ramp stands still for the captures (the HUD reads Run.momentum, set by hand below)
	g.player.momentum = false
	_build()
	_run.momentum = 0.6
	_run.rebuild_sheets()
	g.hud.toast("Tommy Gun Lv 3")
	await _wait(1.2)
	await _shot("67m-hud-buck-charging")
	# full: Ram live, three Overdrive gears, a power-up plate and the boss's bar under the gauge
	_run.add_perk("ram")
	_run.add_perk("overdrive")
	_run.momentum = 1.0
	_run.overdrive = 3
	_run.rebuild_sheets()
	# a power-up's plate: any timed entry under a pickup's id shows one (HUD.plate_key)
	_run.add_timed_effects("sprint", "Sprint", [], 12.0)
	var king = _reg.enemy("tumbleweed_king")
	if king:
		g.hud.show_boss(king)
		g.hud.set_boss_hp(62, 100)
	g.hud.toast("OVERDRIVE")
	await _wait(1.2)
	await _shot("67m-hud-buck-full")
	# a hit lands: half the charge, the gears gone, the flash and the shake
	_run.momentum = 0.5
	_run.overdrive = 0
	_run.rebuild_sheets()
	await _wait(0.05)
	await _shot("67m-hud-buck-hit")
	g.hud.hide_boss()
	# the same strip on Astro: no gauge, the column at the slots' foot
	g.arena_swap_hero("astro")
	_build()
	await _wait(1.0)
	await _shot("67m-hud-astro")
	_save.data = keep
	quit(0)
