## Pass 85 (lane WORLD): the live title's presets captured one by one (TitleStage.force_preset), with the UI and the
## stage alone. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p85_world_title.gd -- out=<dir> [presets=0,1,2] [inset=130] [hero=drifter]
## Writes p<k>.png and p<k>_scene.png, and info.json (each preset's name, the sand the stage's map wears, the draw
## calls). The save is sandboxed; a watchdog quits after 150 s.
extends SceneTree

var _out := "user://p85_title"
var _presets: Array = []
var _inset := -1
var _hero := "drifter"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("presets="):
			for p in a.substr(8).split(","):
				_presets.append(int(p))
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("hero="):
			_hero = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		push_error("p85 title: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p85 title: ", name)


func _main() -> void:
	var save = root.get_node("Save")
	var settings = root.get_node("Settings")
	save.begin_sandbox()
	settings.menu_style = "live"
	if _inset >= 0:
		settings.top_inset = _inset
	save.data["gold"] = 1200
	save.data["last_character"] = _hero
	var stage_script = load("res://ui/TitleStage.gd")
	if _presets.is_empty():
		var sc: Dictionary = stage_script.scene_of("red_canyon")
		for k in stage_script.presets_of(sc).size():
			_presets.append(k)
	var info := {}
	for k in _presets:
		stage_script.force_preset = k
		change_scene_to_file("res://ui/TitleScreen.tscn")
		await _wait(1.6)
		var t = current_scene
		await _shot("p%d" % k)
		var hidden: Array = []
		for c in t.get_children():
			if c is CanvasItem and c.name != "TitleStage" and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				hidden.append(c)
		await _shot("p%d_scene" % k)
		for c in hidden:
			(c as CanvasItem).visible = true
		var stg = t.get_node_or_null("TitleStage")
		info[str(k)] = {"name": stg.preset_name if stg else "", "index": stg.preset_index if stg else -1,
			"sand": str(stg.map.get("sand_id")) if stg and stg.map else "",
			"composed": stg.composed.size() if stg else 0,
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	stage_script.force_preset = -1
	var f := FileAccess.open(_out.path_join("info.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	print("p85 title: ", info)
	save.end_sandbox()
	quit(0)
