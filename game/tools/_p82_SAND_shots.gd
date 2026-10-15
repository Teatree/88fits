## Pass 82, lane SAND: sand candidates side by side in the real game, at the same spots, the same frame. Windowed, silent:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x2400 --path D:/_projects/88fits/game \
##       --script res://tools/_p82_SAND_shots.gd -- out=<dir> list=<txt> [seed=5] [spots=sand,lake,crowd,far] [key=<sand id>]
##       [vp=864x1920]
## vp: the shots come from a second camera (the game camera's place, fov and aspect rule) drawing the same 3D world into
## an 864x1920 SubViewport, the phone's own 3D canvas (1080x2400 at the mobile 0.8 render scale), whatever window the
## desktop allows (a window taller than the screen is cut short by the OS); no HUD. vp=0: the window itself.
## list: one candidate a line, "name path [scale]" (the shader's sand_scale: below 1 = bigger) (path absolute, or res://; "today" loads art/env/sand.png as
## the game imports it). key=<id>: no list; the map is built with timeline sand <id> (Run.map.timeline.sand) and shot as
## it plays (the final check that the key switches the texture).
## One run of Red Canyon (seed 5), the Drifter in god mode, the director stopped, structures hidden. At each spot the hero
## stands, the camera settles, the tree is paused, and every candidate is swapped onto the terrain's sand_tex and shot:
##   sand:  the open sand farthest from the lakes and the river (pass 81's spot), standing zoom
##   lake:  the first lake ahead of the hero (its oasis ground), standing zoom
##   crowd: the open sand with two packs of creatures about the hero (calm under the creatures?)
##   far:   the open sand pulled out (zoom 1.5: the repeat)
## Every wait is bounded and a watchdog quits after 240 s whatever happens. The save is never written.
extends SceneTree

var _out := "user://p82_sand_shots"
var _list := ""
var _key := ""
var _seed := 5
var _spots: Array = ["sand", "lake", "crowd", "far"]
var _cands: Array = []   # [{name, tex, scale}]
var _vp_size := Vector2i(864, 1920)
var _sv: SubViewport
var _cam: Camera3D
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("list="):
			_list = a.substr(5)
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
		elif a.begins_with("spots="):
			_spots = Array(a.substr(6).split(",", false))
		elif a.begins_with("key="):
			_key = a.substr(4)
		elif a.begins_with("vp="):
			var wh := a.substr(3).split("x")
			_vp_size = Vector2i(int(wh[0]), int(wh[1])) if wh.size() == 2 else Vector2i.ZERO
	DirAccess.make_dir_recursive_absolute(_out)
	print("p82_sand: screen ", DisplayServer.screen_get_size(), " usable ", DisplayServer.screen_get_usable_rect(), " window ", DisplayServer.window_get_size(), " scale ", DisplayServer.screen_get_scale())
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("p82_sand: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _load_list() -> void:
	if _list == "":
		return
	var f := FileAccess.open(_list, FileAccess.READ)
	if f == null:
		print("p82_sand: no list ", _list)
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.size() < 2:
			continue
		var tex: Texture2D = null
		if parts[1] == "today":
			tex = load("res://art/env/sand.png")
		elif parts[1].begins_with("res://"):
			tex = load(parts[1])
		else:
			var img := Image.load_from_file(parts[1])
			if img:
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		if tex == null:
			print("p82_sand: cannot load ", parts[1])
			continue
		_cands.append({"name": parts[0], "tex": tex, "scale": float(parts[2]) if parts.size() > 2 else 1.0})
	print("p82_sand: ", _cands.size(), " candidates")


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	var dbg_was: bool = st.debug_mode
	st.debug_mode = false
	_load_list()
	print("p82_sand: window ", DisplayServer.window_get_size(), " viewport ", root.get_visible_rect().size)
	await _start_run()
	if _key != "":
		var tm: ShaderMaterial = g.map.get("_terrain_mat")
		var tex: Texture2D = tm.get_shader_parameter("sand_tex") if tm else null
		print("p82_sand: key ", _key, " -> ", tex.resource_path if tex else "none", " scale ", tm.get_shader_parameter("sand_scale") if tm else 0)
		_cands = [{"name": "key_" + _key, "tex": tex, "scale": float(tm.get_shader_parameter("sand_scale")) if tm else 1.0}]
	var at := _sand_spot()
	for spot: String in _spots:
		match spot:
			"sand":
				await _place(at, 1.0)
				await _shoot_all("sand")
			"far":
				await _place(at, 1.5)
				await _shoot_all("far")
			"lake":
				var lk: Dictionary = (g.map.call("lakes") as Array)[0]
				var c: Vector2 = lk["center"]
				await _place(Vector3(c.x, 0, c.y + float(lk["radius"]) * 1.45), 1.0)
				await _shoot_all("lake")
			"crowd":
				await _place(at, 1.0)
				var p: Vector3 = g.player.global_position
				g.enemies.spawn_pack("goblin", p + Vector3(2.5, 0, -6.0), 7)
				g.enemies.spawn_pack("fire_ant", p + Vector3(-3.0, 0, -3.5), 9)
				g.enemies.spawn_pack("skeleton", p + Vector3(1.0, 0, 4.0), 5)
				await _wait(0.9)
				await _shoot_all("crowd")
	st.debug_mode = dbg_was
	_save.data = keep
	print("p82_sand: done")
	quit(0)


func _start_run() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false}))
	f.close()
	_run.arena_next = false
	if _key != "":
		# the map file's sand key as the Level Editor would write it, on the loaded map's timeline before the map builds
		var md = root.get_node("Registry").map("red_canyon")
		if md and md.timeline:
			md.timeline.set("sand", _key)
	change_scene_to_file("res://game/Game.tscn")
	await _game_ready()
	await _wait(2.5)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	for s in g.structures.items:
		s.used = true
		s.visible = false
		for part in [s.ring, s.pie, s.hand]:
			if part:
				part.visible = false
	await _wait(1.0)
	if _vp_size.x > 0:
		_sv = SubViewport.new()
		_sv.size = _vp_size
		_sv.world_3d = g.camera.camera.get_world_3d()
		_sv.msaa_3d = root.msaa_3d
		_sv.screen_space_aa = root.screen_space_aa
		_sv.use_debanding = root.use_debanding
		_sv.texture_mipmap_bias = root.texture_mipmap_bias
		_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_cam = Camera3D.new()
		_sv.add_child(_cam)
		root.add_child(_sv)
		_cam.current = true


## The second camera where the game's stands (its fov and aspect rule).
func _sync_cam() -> void:
	if _cam == null:
		return
	var gc: Camera3D = g.camera.camera
	_cam.global_transform = gc.global_transform
	_cam.fov = gc.fov
	_cam.keep_aspect = gc.keep_aspect
	_cam.near = gc.near
	_cam.far = gc.far
	_cam.environment = gc.environment
	_cam.attributes = gc.attributes


func _game_ready() -> void:
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("director") != null:
			return


func _place(at: Vector3, zoom: float) -> void:
	paused = false
	g.enemies.kill_all(false)
	g.camera.zoom_override = zoom
	g.player.global_position = Vector3(at.x, g.map.height_at(at.x, at.z), at.z)
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)
	await _wait(1.2)


## The tree paused (the frame held), each candidate on the terrain, a shot each.
func _shoot_all(spot: String) -> void:
	paused = true
	var tm: ShaderMaterial = g.map.get("_terrain_mat")
	var was_tex = tm.get_shader_parameter("sand_tex")
	var was_scale = tm.get_shader_parameter("sand_scale")
	for c: Dictionary in _cands:
		if _key == "":
			tm.set_shader_parameter("sand_tex", c["tex"])
			tm.set_shader_parameter("sand_scale", c["scale"])
		_sync_cam()
		for k in range(3):
			await process_frame
		var img := (_sv.get_texture() if _sv else root.get_viewport().get_texture()).get_image()
		img.save_png(_out.path_join("%s_%s.png" % [spot, c["name"]]))
	tm.set_shader_parameter("sand_tex", was_tex)
	tm.set_shader_parameter("sand_scale", was_scale)
	paused = false
	print("p82_sand: ", spot, " x", _cands.size())


## The open sand farthest from the lakes and the river within 34 m of the middle (pass 81's spot).
func _sand_spot() -> Vector3:
	var best := Vector3(0, 0, 8)
	var best_d := -1.0
	var lakes: Array = g.map.call("lakes")
	var river: Array = g.map.call("river_points")
	for iz in range(-17, 18):
		for ix in range(-17, 18):
			var p := Vector2(ix * 2.0, iz * 2.0)
			if p.length() > 34.0:
				continue
			var d := 1e9
			for lk: Dictionary in lakes:
				d = minf(d, p.distance_to(lk["center"]) - float(lk["radius"]) * 1.6)
			for q in range(river.size() - 1):
				var a: Vector2 = river[q]
				var b: Vector2 = river[q + 1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				d = minf(d, (a + ab * t - p).length() - 6.0)
			d = minf(d, p.distance_to(Vector2(0, 8)) - 10.0)
			if d > best_d:
				best_d = d
				best = Vector3(p.x, 0, p.y)
	return best
