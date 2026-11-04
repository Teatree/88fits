## Pass 123, lane MAINMENU: the Royale main menu on other screens than the 1080 x 1920 canvas (wanted_shots has that
## one): a taller phone, a wider one, a camera cutout. Windowed, silent, bounded (a frame cap and a watchdog):
## GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x2400 --path game --script res://tools/_p123_MAINMENU_shots.gd -- out=<dir> tag=tall [inset=130] [theme=royale]
## Writes <out>/<tag>.png (the title on the Drifter) and <tag>_locked.png (the first locked hero, the developer's preview
## of the hidden ones). The PC save goes back as it was.
extends SceneTree

var _out := "user://p123_mainmenu"
var _tag := "shot"
var _inset := -1
var _theme := "royale"
var _frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("theme="):
			_theme = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_watchdog)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watchdog() -> void:
	_frames += 1
	if _frames > 3600:
		print("_p123_MAINMENU_shots: watchdog, giving up")
		quit(1)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("_p123_MAINMENU_shots: ", name, " ", root.get_visible_rect().size)


func _main() -> void:
	var st: Node = root.get_node("Settings")
	var save: Node = root.get_node("Save")
	var kept := FileAccess.get_file_as_string("user://save.json")
	# a phone's stretch (the PC keeps the canvas at 1080 x 1920 with bars): the canvas follows the window's shape
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	st.set("ui_theme", _theme)
	if _inset >= 0:
		st.set("top_inset", _inset)
	save.data["gold"] = 104711
	save.data["last_character"] = "drifter"
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.2)
	await _shot(_tag)
	st.set("preview_locked_heroes", true)
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(0.9)
	var t = current_scene
	for i in (t._heroes as Array).size():
		if t._state(t._heroes[i]) == "locked":
			t._index = i
			t._show_hero(0)
			t._place()
			break
	await _wait(0.5)
	await _shot(_tag + "_locked")
	st.set("preview_locked_heroes", false)
	if kept != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	quit()
