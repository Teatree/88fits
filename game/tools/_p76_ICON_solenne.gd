## Pass 76 (lane ICON): Solenne's badge where the game shows it, after SOL-B's own icon (solenne_icon_b.png) left her
## JSON: the title with her shown, the hero drawer (every hero's badge), her hero sheet. She is owned and plays her JSON
## look (SOL-B) in a Save sandbox, so the PC save never changes (tools/godot.sh keeps it aside too). Windowed:
## bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p76_ICON_solenne.gd -- out=<dir>
## Every wait is bounded and a watchdog ends the run after 90 s whatever happens (pass 69: a hung capture held the lock).
extends SceneTree

var _out := "user://p76_icon"
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(90.0, true, false, true).timeout.connect(_watchdog)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watchdog() -> void:
	if not _done:
		print("p76_icon: WATCHDOG: 90 s passed, quitting")
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p76_icon: shot ", name)


func _main() -> void:
	var save = root.get_node("Save")
	var reg = root.get_node("Registry")
	save.begin_sandbox()
	var owned: Array = save.heroes_owned()
	if not owned.has("solenne"):
		owned.append("solenne")
	# her JSON's look (SOL-B), as Garry plays her: no kept look
	if save.data.get("hero_look") is Dictionary:
		(save.data["hero_look"] as Dictionary).erase("solenne")
	save.data["last_character"] = "solenne"
	var c = reg.characters.get("solenne")
	var worn = reg.played_look(c)
	print("p76_icon: solenne plays %s, its icon %s, the hero's icon_file %s" % [str(worn.variant_code) if worn else "?",
		worn.icon.resource_path if worn and worn.icon else "none", c.icon_file])
	for code in (c.variants as Dictionary).keys():
		var v: Dictionary = c.variants[code]
		var t: Texture2D = v.get("icon")
		print("p76_icon:   look %s icon %s" % [code, t.resource_path if t else "none"])
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.6)
	var tc = current_scene
	if tc == null:
		print("p76_icon: no title scene")
		_done = true
		quit(2)
		return
	for i in (tc._heroes as Array).size():
		if (tc._heroes[i] as Resource).get("id") == "solenne":
			tc._index = i
			tc._show_hero(1)
	await _wait(1.0)
	await _shot("01-title-solenne")
	tc.open_drawer()
	await _wait(0.9)
	await _shot("02-hero-drawer")
	tc.close_drawer()
	await _wait(0.6)
	tc.open_sheet()
	await _wait(1.0)
	await _shot("03-hero-sheet")
	_done = true
	quit(0)
