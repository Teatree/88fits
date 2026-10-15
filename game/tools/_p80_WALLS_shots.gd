## Pass 80, lane WALLS: the map's edge as the phone sees it, before and after the sand reaches the wall, the cliffs get
## real rock, the boundary becomes a western sandstone fort wall and the sign stops flickering.
## Windowed, silent, at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p80_WALLS_shots.gd -- out=<dir> [seed=11] [only=rim,wide,cliffs,inspect,sign,hell]
## One real run of Red Canyon (seed 11), the Drifter in god mode, the director stopped, the crowd cleared:
##   rim:     the hero at the north, east, west and south rim and the north-east corner, at the play zoom and pulled out
##   wide:    the hero at the middle, pulled all the way out
##   cliffs:  the north and the east rim pulled out to 2.3 (the cliffs far off)
##   inspect: a free camera (not the game's) close to the wall: its inner face and top, a tower, along the wall, the cliffs
##   sign:    the nearest sign at the play zoom and pulled out, the hero walking past it, 24 frames each, cropped round it
##   hell:    stage 3's red ground at the north rim
## Every wait is bounded and a watchdog quits after 420 s whatever happens. The save is never written (godot.sh keeps the
## PC's aside as well).
extends SceneTree

var _out := "user://p80_walls_shots"
var _only: Array = []
var _seed := 11
var _run
var _save
var g
var _free_cam: Camera3D
var _pal_file := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
		elif a.begins_with("pal="):
			_pal_file = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(420.0, true, false, true).timeout.connect(func() -> void:
		print("p80_walls: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _grab() -> Image:
	await process_frame
	await process_frame
	return root.get_viewport().get_texture().get_image()


func _shot(n: String) -> void:
	var img: Image = await _grab()
	img.save_png(_out.path_join(n + ".png"))
	print("p80_walls: ", n)


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	var dbg_was: bool = st.debug_mode
	st.debug_mode = false
	if _pal_file != "":
		await _palettes()
		st.debug_mode = dbg_was
		_save.data = keep
		print("p80_walls: done")
		quit(0)
		return
	await _start_run()
	if g == null:
		print("p80_walls: no game")
		quit(2)
		return
	if _want("rim"):
		await _rims()
	if _want("wide"):
		await _view("06_wide_middle", Vector3(0, 0, 8), 2.1)
	if _want("cliffs"):
		await _view("07_cliffs_north_far", Vector3(0, 0, -46), 2.3)
		await _view("08_cliffs_east_far", Vector3(48, 0, -6), 2.3)
	if _want("sign"):
		await _sign()
	if _want("inspect"):
		await _inspect()
	if _want("hell"):
		g.map.set_hell(1.0, 0.01)
		await _wait(0.4)
		await _view("12_hell_north", Vector3(0, 0, -50), 1.4)
		g.map.set_hell(0.0, 0.01)
		await _wait(0.2)
	if _only.has("perf"):
		await _perf()
	if _only.has("signdiag"):
		await _sign_diag()
	st.debug_mode = dbg_was
	_save.data = keep
	print("p80_walls: done")
	quit(0)


func _start_run() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false})
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	await _game_ready()
	if g == null:
		return
	await _wait(2.5)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	await _wait(1.0)


func _game_ready() -> void:
	for k in range(900):
		await process_frame
		var c = current_scene
		if c and c.get("enemies") != null and c.get("player") != null and c.player.is_inside_tree() and c.get("director") != null:
			g = c
			return


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _put_hero(p: Vector3) -> void:
	g.player.global_position = _ground(p)
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


## The hero stood at `at`, the camera at `zoom`, a moment to settle, a shot.
func _view(n: String, at: Vector3, zoom: float) -> void:
	g.enemies.kill_all(false)
	g.camera.zoom_override = zoom
	_put_hero(at)
	await _wait(1.2)
	await _shot(n)


func _rims() -> void:
	var spots := [["01_rim_north", Vector3(0, 0, -50)], ["02_rim_east", Vector3(52, 0, -6)], ["03_rim_west", Vector3(-52, 0, -6)],
		["04_rim_south", Vector3(0, 0, 54)], ["05_rim_northeast", Vector3(37, 0, -37)]]
	for s in spots:
		await _view(str(s[0]) + "_play", s[1], 1.15)
		await _view(str(s[0]) + "_far", s[1], 1.8)


## A camera of our own (the game's stays where it is): at `eye`, looking at `look`, a shot, the game's camera back.
func _free_view(n: String, eye: Vector3, look: Vector3, fov := 50.0) -> void:
	if _free_cam == null:
		_free_cam = Camera3D.new()
		_free_cam.far = 400.0
		g.add_child(_free_cam)
	_free_cam.fov = fov
	_free_cam.global_position = eye
	_free_cam.look_at(look, Vector3.UP)
	_free_cam.make_current()
	await _wait(0.3)
	await _shot(n)
	g.camera.camera.make_current()


## The wall up close from inside the arena (a free camera, the hero parked in the middle): the north wall's inner face and
## its top, the same from lower and nearer, a stretch seen along the wall, the north-east wall, and the cliffs over it.
func _inspect() -> void:
	g.enemies.kill_all(false)
	g.camera.zoom_override = 1.0
	_put_hero(Vector3(0, 0, 8))
	await _wait(0.5)
	var r: float = g.map.arena_radius
	var gn: float = g.map.height_at(0, -r + 8.0)
	await _free_view("20_inspect_north_face", Vector3(0, gn + 9.0, -r + 17.0), Vector3(0, gn + 2.0, -r))
	await _free_view("21_inspect_north_low", Vector3(2, gn + 3.5, -r + 9.0), Vector3(0, gn + 2.2, -r))
	await _free_view("22_inspect_along", Vector3(-14, gn + 5.0, -r + 8.0), Vector3(10, gn + 2.0, -r + 1.0))
	var ne := Vector3(cos(-PI * 0.25), 0, sin(-PI * 0.25))
	var gne: float = g.map.height_at(ne.x * (r - 10.0), ne.z * (r - 10.0))
	await _free_view("23_inspect_northeast", ne * (r - 16.0) + Vector3(0, gne + 8.0, 0), ne * r + Vector3(0, gne + 2.0, 0))
	await _free_view("24_inspect_cliffs", Vector3(0, gn + 14.0, -r + 24.0), Vector3(0, gn + 10.0, -r - 18.0))
	await _free_view("25_inspect_top", Vector3(4, gn + 12.0, -r + 6.0), Vector3(0, gn + 1.0, -r - 2.0))


## perf (only when named): the frame at the middle, the north rim at the play zoom and pulled out, the north-east rim
## pulled out: 240 frames each, vsync off, the mean and the worst frame (process), the viewport's GPU and CPU render
## time, draw calls, primitives, the texture and video memory, printed as one line each.
func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for s in [["middle", Vector3(0, 0, 8), 1.15], ["north_play", Vector3(0, 0, -50), 1.15], ["north_far", Vector3(0, 0, -50), 1.8], ["northeast_far", Vector3(37, 0, -37), 1.8]]:
		g.enemies.kill_all(false)
		g.camera.zoom_override = float(s[2])
		_put_hero(s[1])
		for k in range(30):
			await process_frame
		var n := 240
		var sum := {"ms": 0.0, "gpu": 0.0, "cpu": 0.0, "draws": 0.0, "prims": 0.0}
		var worst := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		for k in range(n):
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := float(now - last) / 1000.0
			last = now
			worst = maxf(worst, ms)
			sum["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			sum["cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			sum["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			sum["prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var mean := float(Time.get_ticks_usec() - t0) / 1000.0 / n
		print("p80_walls: perf %s | %.2f ms/frame (worst %.1f) | gpu %.2f ms, render cpu %.2f ms | draw calls %.0f, primitives %.0f | texture mem %.1f MB, video mem %.1f MB" % [
			s[0], mean, worst, sum["gpu"] / n, sum["cpu"] / n, sum["draws"] / n, sum["prims"] / n,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


## signdiag (only when named): does the sign sort its own parts right? Every sign drawn alone (the camera sees only
## its layer), each with the game's depth material (A), then with that material keeping the true depth (squash 1, bias
## 0: B), then not at all (C, the sky behind). A pixel of the sign (B differs from C) where A differs from B is one the
## squashed depth sorts wrong (a z-fight). The game's camera at the play zoom and pulled out, the hero stepped past each
## sign in 10 places; printed per zoom, the worst frame's A, B and the difference saved.
func _sign_diag() -> void:
	var signs = g.get_node_or_null("Signs")
	if signs == null:
		print("p80_walls: no signs")
		return
	var cam: Camera3D = g.camera.camera
	var keep_mask := cam.cull_mask
	var stands: Array = []
	for c in signs.get_children():
		if c.name.begins_with("Sign"):
			stands.append(c)
	var mats: Array = []
	for st in stands:
		for mi in (st as Node).find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = 1 << 19
			for i in (mi as MeshInstance3D).get_surface_override_material_count():
				var m = (mi as MeshInstance3D).get_surface_override_material(i)
				if m is ShaderMaterial and not mats.has(m):
					mats.append(m)
	var orig: Array = []
	for m in mats:
		orig.append([(m as ShaderMaterial).get_shader_parameter("squash"), (m as ShaderMaterial).get_shader_parameter("bias"), (m as ShaderMaterial).get_shader_parameter("squash_h")])
	cam.cull_mask = 1 << 19
	# the UI (the HUD, the XP numbers) hidden: it moves between the three grabs
	var hidden_ui: Array = []
	for cl in g.find_children("*", "CanvasLayer", true, false):
		if (cl as CanvasLayer).visible:
			(cl as CanvasLayer).visible = false
			hidden_ui.append(cl)
	for zoom in [1.0, 1.8]:
		g.camera.zoom_override = zoom
		var bad := 0
		var cover := 0
		var worst := -1
		var worst_imgs: Array = []
		for st in stands:
			var at: Vector3 = (st as Node3D).global_position
			for k in range(10):
				_put_hero(at + Vector3(-2.0 + 0.43 * k, 0, 3.0 + 0.11 * k))
				await process_frame
				var a: Image = await _grab()
				for m in mats:
					(m as ShaderMaterial).set_shader_parameter("squash", 1.0)
					(m as ShaderMaterial).set_shader_parameter("squash_h", 1.0)
					(m as ShaderMaterial).set_shader_parameter("bias", 0.0)
				var b: Image = await _grab()
				for mi in (st as Node).find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).visible = false
				var c: Image = await _grab()
				for mi in (st as Node).find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).visible = true
				for j in mats.size():
					var m: ShaderMaterial = mats[j]
					m.set_shader_parameter("squash", orig[j][0])
					m.set_shader_parameter("bias", orig[j][1])
					m.set_shader_parameter("squash_h", orig[j][2] if orig[j][2] != null else 1.0)
				var n_bad := 0
				var n_cov := 0
				var sp := cam.unproject_position(at + Vector3(0, 2.6, 0))
				var x0 := clampi(int(sp.x) - 260, 0, a.get_width() - 1)
				var x1 := clampi(int(sp.x) + 260, 0, a.get_width())
				var y0 := clampi(int(sp.y) - 420, 0, a.get_height() - 1)
				var y1 := clampi(int(sp.y) + 420, 0, a.get_height())
				for y in range(y0, y1):
					for x in range(x0, x1):
						var pb := b.get_pixel(x, y)
						if _differs(pb, c.get_pixel(x, y)):
							n_cov += 1
							if _differs(a.get_pixel(x, y), pb):
								n_bad += 1
				bad += n_bad
				cover += n_cov
				if n_bad > worst:
					worst = n_bad
					worst_imgs = [a, b]
		var tag := "play" if zoom < 1.5 else "far"
		print("p80_walls: signdiag %s | sign pixels %d, sorted wrong %d (%.2f%%), worst frame %d" % [tag, cover, bad, 100.0 * bad / maxf(cover, 1.0), worst])
		if worst_imgs.size() == 2:
			(worst_imgs[0] as Image).save_png(_out.path_join("sd_%s_A.png" % tag))
			(worst_imgs[1] as Image).save_png(_out.path_join("sd_%s_B.png" % tag))
	cam.cull_mask = keep_mask
	for cl in hidden_ui:
		(cl as CanvasLayer).visible = true


func _differs(p: Color, q: Color) -> bool:
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.08


## The sign nearest the middle: the hero a couple of metres south-east of it, then walking slowly west past it while the
## camera follows; 24 frames at the play zoom and 24 pulled out, each cropped round the sign (500 x 700 canvas px), laid out
## in a sheet so a flicker shows as a frame that differs from its neighbours.
func _sign() -> void:
	var signs = g.get_node_or_null("Signs")
	if signs == null or signs.get("spots") == null or (signs.spots as PackedVector3Array).is_empty():
		print("p80_walls: no signs")
		return
	var best := Vector3.ZERO
	var bd := 1e9
	for p: Vector3 in signs.spots:
		var d := Vector2(p.x, p.z).length()
		if d < bd:
			bd = d
			best = p
	print("p80_walls: sign at ", best)
	for zoom in [1.0, 1.8]:
		g.enemies.kill_all(false)
		g.camera.zoom_override = zoom
		var start := best + Vector3(2.5, 0, 2.2)
		_put_hero(start)
		await _wait(1.0)
		var frames: Array = []
		for k in range(24):
			g.player.global_position = _ground(start + Vector3(-0.21 * k, 0, 0))
			g.player.velocity = Vector3.ZERO
			var img: Image = await _grab()
			var cam: Camera3D = g.camera.camera
			var sp := cam.unproject_position(best + Vector3(0, 2.6, 0))
			var w := 500
			var h := 700
			var x := clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
			var y := clampi(int(sp.y) - h / 2, 0, img.get_height() - h)
			frames.append(img.get_region(Rect2i(x, y, w, h)))
		var sheet := Image.create(500 * 6, 700 * 4, false, Image.FORMAT_RGBA8)
		for k in frames.size():
			sheet.blit_rect(frames[k], Rect2i(0, 0, 500, 700), Vector2i((k % 6) * 500, (k / 6) * 700))
		var n := "10_sign_play" if zoom < 1.5 else "11_sign_far"
		sheet.save_png(_out.path_join(n + "_sheet.png"))
		(frames[0] as Image).save_png(_out.path_join(n + "_f0.png"))
		print("p80_walls: ", n)
	# a free camera 7 m from the post, sliding sideways
	var fr: Array = []
	for k in range(12):
		var eye := best + Vector3(-1.5 + 0.25 * k, 6.5, 6.5)
		if _free_cam == null:
			_free_cam = Camera3D.new()
			_free_cam.far = 400.0
			g.add_child(_free_cam)
		_free_cam.fov = 50.0
		_free_cam.global_position = eye
		_free_cam.look_at(best + Vector3(0, 2.6, 0), Vector3.UP)
		_free_cam.make_current()
		var img: Image = await _grab()
		fr.append(img.get_region(Rect2i(290, 560, 500, 800)))
	g.camera.camera.make_current()
	var sh := Image.create(500 * 6, 800 * 2, false, Image.FORMAT_RGBA8)
	for k in fr.size():
		sh.blit_rect(fr[k], Rect2i(0, 0, 500, 800), Vector2i((k % 6) * 500, (k / 6) * 800))
	sh.save_png(_out.path_join("13_sign_close_sheet.png"))
	print("p80_walls: 13_sign_close")


## pal=<file.json>: colour candidates ({name: {"wall_colors": {...}, "rock_color": "#.."}}), each laid on the map's
## timeline before a run of its own: the north rim at the play zoom and pulled out, the north-east pulled out, the north
## face up close.
func _palettes() -> void:
	var f := FileAccess.open(_pal_file, FileAccess.READ)
	var all = JSON.parse_string(f.get_as_text()) if f else null
	if not all is Dictionary:
		print("p80_walls: no palettes in ", _pal_file)
		return
	var tl = root.get_node("Registry").map("red_canyon").timeline
	for name: String in (all as Dictionary).keys():
		var p: Dictionary = all[name]
		if p.has("rock_color"):
			tl.rock_color = str(p["rock_color"])
		var wc: Dictionary = (tl.wall_colors as Dictionary).duplicate()
		for k in (p.get("wall_colors", {}) as Dictionary).keys():
			wc[k] = p["wall_colors"][k]
		tl.wall_colors = wc
		await _start_run()
		if g == null:
			return
		await _view(name + "_north_play", Vector3(0, 0, -50), 1.15)
		await _view(name + "_north_far", Vector3(0, 0, -50), 1.8)
		await _view(name + "_northeast_far", Vector3(37, 0, -37), 1.8)
		g.camera.zoom_override = 1.0
		_put_hero(Vector3(0, 0, 8))
		await _wait(0.4)
		var r: float = g.map.arena_radius
		var gn: float = g.map.height_at(0, -r + 8.0)
		await _free_view(name + "_face", Vector3(0, gn + 9.0, -r + 17.0), Vector3(0, gn + 2.0, -r))
