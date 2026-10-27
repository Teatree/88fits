## The UI reference's extra captures (2026-10-27): screens tools/wanted_shots.gd does not reach. Windowed, bounded:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/uidoc_shots.gd -- out=<dir>
## drum: the War Drum's moment mid-way (Game._use_drum on the war_drum structure).
extends SceneTree

const WATCHDOG_S := 120.0
var _out := "user://uidoc_shots"
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.trim_prefix("out=")
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > WATCHDOG_S * 1000.0:
		print("uidoc_shots: watchdog")
		_end(2)


func _end(code: int) -> void:
	if FileAccess.file_exists("user://debug_launch.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://debug_launch.json"))
	quit(code)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("uidoc_shots: saved ", name)


func _main() -> void:
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		st.set(k, false)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "map": "red_canyon", "map_seed": 88, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	change_scene_to_file("res://game/Game.tscn")
	var g = null
	for i in range(900):
		await process_frame
		var cs = current_scene
		if cs != null and cs.has_method("open_pause") and cs.get("player") != null:
			g = cs
			break
	if g == null:
		print("uidoc_shots: no game")
		_end(1)
		return
	await _frames(90)
	var def = root.get_node("Registry").structure("war_drum")
	g.call("_use_drum", def)
	await _frames(55)
	await _shot("drum_moment")
	await _frames(40)
	await _shot("drum_moment_late")
	await _frames(120)
	await _shot("drum_boost_hud")
	_end(0)
