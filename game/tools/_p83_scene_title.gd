## Pass 83 (lane SCENE): the live title captured for the composition, before/after. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p83_scene_title.gd -- out=<dir> [tag=1920] [inset=130] [heroes=drifter,astro]
## Writes <tag>_<hero>.png (the title as the player sees it) and <tag>_<hero>_scene.png (the stage alone, the UI hidden,
## the wash kept off), and <tag>_frame.json (build ms, the stage's frame ms over 120 frames). The save is sandboxed.
## A watchdog quits after 120 s whatever happens.
extends SceneTree

var _out := "user://p83_scene_title"
var _tag := "1920"
var _inset := -1
var _heroes: Array = ["drifter"]
var _save
var _settings
## size=WxH: the window set to that size first (a tall phone's ratio; the OS may cap --resolution at the screen)
var _size := Vector2i.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("heroes="):
			_heroes = Array(a.substr(7).split(","))
		elif a.begins_with("size="):
			var wh := a.substr(5).split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		push_error("p83_scene_title: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p83_scene_title: ", name)


func _main() -> void:
	if _size != Vector2i.ZERO:
		# the phone's stretch (project.godot aspect "expand"; the PC's is "keep", a 9:16 canvas)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.size = _size
		await process_frame
		await process_frame
		print("p83_scene_title: window ", root.size)
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_save.begin_sandbox()
	_settings.menu_style = "live"
	if _inset >= 0:
		_settings.top_inset = _inset
	_save.data["gold"] = 1200
	var stats := {}
	for h in _heroes:
		_save.data["last_character"] = h
		change_scene_to_file("res://ui/TitleScreen.tscn")
		await _wait(1.6)
		var t = current_scene
		await _shot("%s_%s" % [_tag, h])
		# the stage alone
		var hidden: Array = []
		for c in t.get_children():
			if c is CanvasItem and c.name != "TitleStage" and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				hidden.append(c)
		await _shot("%s_%s_scene" % [_tag, h])
		for c in hidden:
			(c as CanvasItem).visible = true
		# where the screen's points fall on the ground, metres from the hero's spot (x right, z towards the camera)
		var stg = t.get_node_or_null("TitleStage")
		if stg and h == _heroes[0]:
			var cam: Camera3D = stg.camera
			var vs: Vector2 = Vector2(stg.viewport.size)
			var grid := {}
			for gy in [0.0, 0.1, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8]:
				var row: Array = []
				for gx in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var sp := Vector2(gx * vs.x, gy * vs.y)
					var o := cam.project_ray_origin(sp)
					var n := cam.project_ray_normal(sp)
					var f: Vector3 = stg.feet()
					var tt := (f.y - o.y) / n.y if absf(n.y) > 0.0001 else 0.0
					var g := o + n * tt
					row.append([snappedf(g.x - f.x, 0.1), snappedf(g.z - f.z, 0.1)])
				grid[str(gy)] = row
			var gf := FileAccess.open(_out.path_join(_tag + "_grid.json"), FileAccess.WRITE)
			gf.store_string(JSON.stringify(grid, "	"))
			gf.close()
			print("p83_scene_title: composed ", stg.composed.size(), " ", stg.composed)
		# the frame cost with the title up (CPU ms a frame over 120 frames)
		var t0 := Time.get_ticks_usec()
		for k in range(120):
			await process_frame
		var stage = t.get_node_or_null("TitleStage")
		stats[h] = {"frame_ms": float(Time.get_ticks_usec() - t0) / 120000.0,
			"build_ms": float(stage.build_ms) if stage else -1.0,
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	var f := FileAccess.open(_out.path_join(_tag + "_frame.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(stats, "\t"))
	f.close()
	print("p83_scene_title: ", stats)
	_save.end_sandbox()
	quit(0)
