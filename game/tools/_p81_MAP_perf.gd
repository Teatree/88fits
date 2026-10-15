## Pass 81, lane MAP: what the new water, oasis ground and sand cost against pass 80's, in one sitting. A real run of Red
## Canyon (seed 5), the hero on the first lake's south shore at the standing zoom (the water a third of the screen), the
## crowd stopped; then blocks of frames alternating NEW (the water shader, the new terrain shader and sand) and OLD (the
## flat StandardMaterial water, pass 80's terrain shader from old=<file> and sand from sand=<png>), the GPU and CPU render
## time of each frame and the frame's wall time. Windowed; every wait bounded, a watchdog.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path game \
##       --script res://tools/_p81_MAP_perf.gd -- old=<old shader file> sand=<old sand png> [blocks=6] [frames=240] [view=lake|sand]
extends SceneTree

var _old_code := ""
var _old_sand := ""
var _blocks := 6
var _frames := 240
var _view := "lake"
var g
var _vp: RID


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("old="):
			_old_code = FileAccess.get_file_as_string(a.substr(4))
		elif a.begins_with("sand="):
			_old_sand = a.substr(5)
		elif a.begins_with("blocks="):
			_blocks = int(a.substr(7))
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("view="):
			_view = a.substr(5)
	create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("p81_perf: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	root.get_node("Run").arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("director") != null:
			break
	await _wait(2.0)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	for st in g.structures.items:
		st.used = true
		st.visible = false
		for part in [st.ring, st.pie, st.hand]:
			if part:
				part.visible = false
	var lk: Dictionary = (g.map.call("lakes") as Array)[0]
	var c: Vector2 = lk["center"]
	var at := Vector3(c.x, 0, c.y + float(lk["radius"]) * 1.45)
	if _view == "sand":
		at = Vector3(-16, 0, -24)
	g.player.global_position = Vector3(at.x, g.map.height_at(at.x, at.z), at.z)
	g.camera.zoom_override = 1.0
	g.camera.snap_to(g.player)
	await _wait(1.0)
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	# the two looks
	var new_water: Material = g.map.get("_water_mat")
	var tm: ShaderMaterial = g.map.get("_terrain_mat")
	var new_shader: Shader = tm.shader
	var new_sand: Texture2D = tm.get_shader_parameter("sand_tex")
	var old_water := StandardMaterial3D.new()
	old_water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	old_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	old_water.albedo_color = Color(0.07, 0.42, 0.64, 0.82)
	old_water.cull_mode = BaseMaterial3D.CULL_BACK
	old_water.render_priority = -10
	var old_shader := Shader.new()
	old_shader.code = _old_code if _old_code != "" else new_shader.code
	var old_sand: Texture2D = new_sand
	if _old_sand != "":
		var img := Image.load_from_file(_old_sand)
		if img:
			old_sand = ImageTexture.create_from_image(img)
	var lakes: Array = []
	for n in g.map.find_children("Oasis*", "MeshInstance3D", true, false):
		lakes.append(n)
	var sums := {"new": [0.0, 0.0, 0.0, 0], "old": [0.0, 0.0, 0.0, 0]}
	for b in range(_blocks * 2):
		var which := "new" if b % 2 == 0 else "old"
		for n: MeshInstance3D in lakes:
			n.material_override = new_water if which == "new" else old_water
		tm.shader = new_shader if which == "new" else old_shader
		tm.set_shader_parameter("sand_tex", new_sand if which == "new" else old_sand)
		# a few frames to settle (the old shader compiles on its first use)
		for k in range(30):
			await process_frame
		var t0 := Time.get_ticks_usec()
		var gpu := 0.0
		var cpu := 0.0
		for k in range(_frames):
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / _frames
		var s: Array = sums[which]
		s[0] += gpu / _frames
		s[1] += cpu / _frames
		s[2] += wall
		s[3] += 1
		print("p81_perf: block %d %s gpu %.3f ms, render cpu %.3f ms, frame %.3f ms" % [b, which, gpu / _frames, cpu / _frames, wall])
	for which in ["new", "old"]:
		var s: Array = sums[which]
		print("p81_perf: %s mean gpu %.3f ms, render cpu %.3f ms, frame %.3f ms (%d blocks of %d frames, view %s)" % [which, s[0] / s[3], s[1] / s[3], s[2] / s[3], s[3], _frames, _view])
	save.data = keep
	quit(0)
