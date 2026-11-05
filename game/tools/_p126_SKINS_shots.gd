## Pass 126 (lane SKINS): the wave of skins on screen, windowed at 1080x1920, bounded by a watchdog:
##   <hero>_looks.png        the Heroes screen's LOOKS pop-up on a fresh save (the look he wears, the skins with their goals)
##   <hero>_onsale.png       the same with every goal done (the prices with their coins)
##   <hero>_<code>_heroes.png  the Heroes screen with that skin worn
##   <hero>_<code>_title.png   the main menu with that skin worn
##   <hero>_sheet.png        the hero's DETAILS sheet scrolled to its Looks section
## The PC's save goes back at the end (godot.sh keeps it aside too).
##   GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##       --script res://tools/_p126_SKINS_shots.gd -- out=<dir> [only=drifter,astro]
extends SceneTree

var _out := "user://p126_skins"
var _only: Array = []
var _save: Node
var _reg: Node


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	# a capture never holds the Godot lock for ever
	create_timer(540.0, true, false, true).timeout.connect(func():
		print("skins_shots: the watchdog ended it")
		quit(3))
	process_frame.connect(_first, CONNECT_ONE_SHOT)


func _first() -> void:
	_main()


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("skins_shots: ", name)


func _quests_of(c) -> Array:
	var out: Array = []
	for code in c.variants.keys():
		var q = _reg.skin_quest(c, str(code))
		if q != null:
			out.append(q.id)
	return out


func _main() -> void:
	# pass 127 (lane DOCS): no ARENA button on a capture (in memory only)
	root.get_node("Settings").set("debug_mode", false)
	DirAccess.make_dir_recursive_absolute(_out)
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var kept := FileAccess.get_file_as_string("user://save.json")
	_save.data = _save._default()
	_save.data["gold"] = 104711
	var heroes := ["drifter", "astro", "calavera", "ironwood", "solenne", "fadeaway", "buck", "may"]
	_save.data["heroes_owned"] = heroes.duplicate()
	for hid: String in heroes:
		if not _only.is_empty() and not _only.has(hid):
			continue
		var c = _reg.character(hid)
		_save.data["last_character"] = hid
		_save.data["skins_owned"] = []
		_save.data["skin_worn"] = {}
		_save.data["quests_done"] = []
		change_scene_to_file("res://ui/HeroesScreen.tscn")
		await _wait(1.0)
		var host = current_scene
		host.show_hero(c)
		await _wait(0.4)
		host.call("open_looks")
		await _wait(0.7)
		await _shot(hid + "_looks")
		host.call("on_back")
		await _wait(0.3)
		_save.data["quests_done"] = _quests_of(c)
		host.refresh()
		host.show_hero(c)
		await _wait(0.3)
		host.call("open_looks")
		await _wait(0.7)
		await _shot(hid + "_onsale")
		host.call("on_back")
		await _wait(0.3)
		# the details sheet at its Looks section
		var sheet_script: GDScript = load("res://ui/wanted/WHeroSheet.gd")
		var s: Control = sheet_script.open(host, c, false)
		await _wait(0.7)
		var looks: Control = s.find_child("Looks", true, false)
		if looks:
			(s.get("scroll") as ScrollContainer).ensure_control_visible(looks)
			await _wait(0.4)
		await _shot(hid + "_sheet")
		s.call("close")
		await _wait(0.3)
		# each skin worn: the Heroes screen and the main menu
		for code: String in _reg.skins_of(c):
			if code == c.home_look() or not c.sells_skin(code):
				continue
			_save.data["skins_owned"] = [_reg.skin_key(c.id, code)]
			_save.data["skin_worn"] = {hid: code}
			change_scene_to_file("res://ui/HeroesScreen.tscn")
			await _wait(1.0)
			(current_scene).show_hero(c)
			await _wait(0.5)
			await _shot("%s_%s_heroes" % [hid, code])
			change_scene_to_file("res://ui/TitleScreen.tscn")
			await _wait(1.4)
			await _shot("%s_%s_title" % [hid, code])
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	if f:
		f.store_string(kept)
		f.close()
	_save.data = _save._default()
	quit(0)
