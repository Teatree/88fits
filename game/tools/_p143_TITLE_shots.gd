## Pass 143 (lead): the main menu with each new outlaw (the Horseman, The Robot) standing in the look he plays, on a
## sandboxed save (Save.begin_sandbox: nothing reaches the disk). Windowed at the phone's canvas, a watchdog quits a hung run:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##       --script res://tools/_p143_TITLE_shots.gd -- out=<dir> [only=buck,fadeaway]
## -> <out>/<hero>_title.png
extends SceneTree

const WATCHDOG := 150.0

var _out := "user://p143_title"
var _only: Array = ["buck", "fadeaway"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		print("p143_title: WATCHDOG fired, quitting")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var save = root.get_node("Save")
	var reg = root.get_node("Registry")
	save.begin_sandbox()
	for id in _only:
		var hero = reg.character(str(id))
		if hero == null:
			print("p143_title: no outlaw ", id)
			continue
		var d: Dictionary = save.data
		if not (d["heroes_owned"] as Array).has(hero.id):
			(d["heroes_owned"] as Array).append(hero.id)
		d["last_character"] = hero.id
		change_scene_to_file("res://ui/TitleScreen.tscn")
		await _wait(1.6)
		var t = current_scene
		t._index = maxi((t._heroes as Array).find(hero), 0)
		t._show_hero(0)
		t._place()
		await _wait(1.4)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("%s_title.png" % hero.id))
		print("p143_title: ", hero.id)
	print("p143_title: done")
	quit(0)
