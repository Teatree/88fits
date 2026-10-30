## Pass 115, lane META: the screens the game's new name and Nerve's change show on, windowed at the phone's canvas.
##   GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --script res://tools/_p115_META_shots.gd -- out=D:/_projects/88fits/tools/dl/p115/META/shots
## title_live / title_painted (OUTLAW / SURVIVORS in both menu looks), board (Nerve second, its line in words), board_toasts
## (an older save's refund said once), nerve_sheet (rank 3: a Skip and two Second Winds, both offers), nerve_sheet_full
## (six Second Winds: "revive with 100% health"), hero_sheet_stats (the CV's "Health on revive"), settings (the version
## line). The PC save goes back as it was; a watchdog quits after WATCHDOG seconds whatever happens.
extends SceneTree

const WATCHDOG := 150.0

var _out := "user://p115_meta_shots"
var _save
var _settings
var _reg
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		push_error("_p115_META_shots: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("_p115_META_shots: ", name)


func _scene(path: String) -> void:
	change_scene_to_file(path)
	await _wait(1.0)


func _main() -> void:
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_reg = root.get_node("Registry")
	var kept := FileAccess.get_file_as_string("user://save.json")
	var style: String = _settings.menu_style
	_save.data["gold"] = 108411
	_save.data["last_character"] = "drifter"
	# the title in both looks
	for st in ["live", "painted"]:
		_settings.menu_style = st
		await _scene("res://ui/TitleScreen.tscn")
		await _wait(0.6)
		await _shot("title_" + st)
	_settings.menu_style = style
	# the board: Nerve with a Skip and two Second Winds, Grit and Drive at a rank
	_save.data["talents"] = {"nerve": {"picks": [0, 1, 1]}, "grit": {"picks": [0]}, "drive": {"picks": [1]}}
	_save.data["talent_spent"] = 150 + 600 + 1350 + 450 + 375
	await _scene("res://ui/HomesteadScreen.tscn")
	await _shot("board")
	current_scene._open(_reg.talent("nerve"))
	await _wait(0.6)
	await _shot("nerve_sheet")
	_save.data["talents"]["nerve"] = {"picks": [1, 1, 1, 1, 1, 1]}
	current_scene._close(false)
	current_scene._refresh()
	current_scene._open(_reg.talent("nerve"))
	await _wait(0.6)
	await _shot("nerve_sheet_full")
	# an older save's Nerve ranks, said once when the board opens
	_save.data["talents"] = {"nerve": {"picks": [1, 0, 1]}}
	_save.data["board_note_nerve"] = {"kind": "nerve_refund", "gold": 800, "ranks": 3, "second_wind": 2}
	await _scene("res://ui/HomesteadScreen.tscn")
	await _shot("board_toasts")
	await _wait(1.0)
	await _shot("board_toasts_b")
	await _wait(1.4)
	await _shot("board_toasts_c")
	# the hero's sheet: the stats a run starts with, two Second Wind ranks in (60%)
	_save.data["talents"] = {"nerve": {"picks": [1, 1]}}
	_settings.menu_style = "painted"
	await _scene("res://ui/TitleScreen.tscn")
	var tc = current_scene
	# the plaque's tap
	tc.open_sheet()
	await _wait(0.8)
	var sheet = tc.get("_sheet")
	await _shot("hero_sheet")
	var sc = sheet.get("scroll") if sheet else null
	if sc:
		sc.scroll_vertical = 100000
		await _wait(0.5)
	await _shot("hero_sheet_stats")
	_settings.menu_style = style
	# Settings: the version line at its foot
	await _scene("res://ui/SettingsScreen.tscn")
	await _shot("settings")
	if kept != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	print("_p115_META_shots: done in %.1f s" % ((Time.get_ticks_msec() - _t0) / 1000.0))
	quit()
