## Lane ECON (pass 70) scratch capture: the title's Hero Collections button (a square as tall as the plaque, eight
## squares) in both menu looks, a hero on sale, the drawer open (the close X), and the Results after a death (banked).
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p70_econ_title.gd -- out=<dir> [inset=130]
## A watchdog quits after WATCHDOG seconds whatever happens; every wait is bounded.
extends SceneTree

const WATCHDOG := 90.0
var _out := "user://p70_econ"
var _inset := -1
var _save
var _settings
var _run
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		print("_p70_econ_title: WATCHDOG")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("_p70_econ_title: ", name)


func _scene(path: String) -> void:
	change_scene_to_file(path)
	await _wait(1.0)


func _pick(t, id: String) -> void:
	for i in (t._heroes as Array).size():
		if (t._heroes[i] as Resource).get("id") == id:
			t._index = i
			t._show_hero(1)
			t._place()
			return


func _report(t, tag: String) -> void:
	var b: Control = t._drawer_btn
	var p: Control = t._plaque
	print("_p70_econ_title: %s button %s at %s, plaque %s at %s" % [tag, str(b.size), str(b.position), str(p.size), str(p.position)])


func _main() -> void:
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	if _inset >= 0:
		_settings.top_inset = _inset
	_save.data["gold"] = 2400
	_save.data["last_character"] = "drifter"
	var pre := "inset_" if _inset >= 0 else ""
	for style in ["painted", "live"]:
		_settings.menu_style = style
		await _scene("res://ui/TitleScreen.tscn")
		var t = current_scene
		_pick(t, "drifter")
		await _wait(0.6)
		_report(t, style + " drifter")
		await _shot("%stitle_%s_drifter" % [pre, style])
		_pick(t, "fadeaway")
		await _wait(0.6)
		_report(t, style + " fadeaway")
		await _shot("%stitle_%s_fadeaway" % [pre, style])
		_pick(t, "ironwood")
		await _wait(0.6)
		_report(t, style + " ironwood")
		await _shot("%stitle_%s_ironwood" % [pre, style])
		t.open_drawer()
		await _wait(0.7)
		await _shot("%stitle_%s_drawer" % [pre, style])
		t.close_drawer()
		await _wait(0.4)
	# the Results after a death: the purse banked like an extraction
	if _inset < 0:
		_run.start(_reg.character("drifter"), _reg.map("red_canyon"))
		_run.elapsed = 512.0
		_run.kills = 1234
		_run.died = true
		(_save.data["hints_seen"] as Array).erase("results")
		_run.last_result = {"gold_before": 2400, "banked": 1610, "lost": 0, "strongbox": 0, "prev_best": {"time": 480.0}}
		await _scene("res://ui/ResultsScreen.tscn")
		await _wait(1.2)
		await _shot("results_death")
	_save.end_sandbox()
	quit()
