## Pass 147 (lane ROBOT): the bull basketball player (fadeaway, look FAD-I, wider than the other outlaws by design) on the
## screens that frame an outlaw: the Outlaws screen on him (its page and the picker tray), the main menu on him, and the same
## two on the Drifter for the width beside him. On a sandboxed save that owns every outlaw (nothing reaches the PC's file).
## Windowed, bounded (a watchdog quits after 150 s):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p147_BULL_shots.gd -- out=<abs dir> [heroes=fadeaway,drifter]
## -> <out>/<hero>_heroes.png, <out>/<hero>_title.png
extends SceneTree

var _out := "user://p147_bull_shots"
var _heroes: Array = ["fadeaway", "drifter"]
var _t0 := 0
var _save


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("heroes="):
			_heroes = Array(a.substr(7).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 150000:
		print("p147_bull: watchdog")
		_end(2)


func _end(code: int) -> void:
	if _save:
		_save.end_sandbox()
	quit(code)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p147_bull: shot ", name)


func _settle() -> void:
	await _wait(0.6)
	for k in range(45):
		await process_frame
	await _wait(0.5)


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode", "preview_locked_heroes"]:
		st.set(k, false)
	var reg = root.get_node("Registry")
	var all: Array = reg.heroes_in_menu_order(false).map(func(c) -> String: return c.id)
	for id: String in _heroes:
		_save.data = _save._default()
		_save.data["heroes_owned"] = all.duplicate()
		_save.data["last_character"] = id
		_save.data["gold"] = 2500
		load("res://core/systems/Trail.gd").refresh()
		# the screen opens on him (HeroesScreen.open_on, pass 128: a static the screen reads as it builds)
		load("res://ui/HeroesScreen.gd").set("open_on", id)
		change_scene_to_file("res://ui/HeroesScreen.tscn")
		await _settle()
		var s = current_scene
		print("p147_bull: heroes screen on ", (s.shown.id if s and s.get("shown") else "-"))
		await _shot("%s_heroes" % id)
		change_scene_to_file("res://ui/TitleScreen.tscn")
		await _settle()
		var t = current_scene
		if t and t.get("_heroes") != null:
			var hero = reg.character(id)
			t._index = maxi((t._heroes as Array).find(hero), 0)
			t._show_hero(0)
			t._place()
			await _wait(1.4)
			print("p147_bull: title on ", (t._heroes[t._index]).id)
		await _shot("%s_title" % id)
	print("p147_bull: done")
	_end(0)
