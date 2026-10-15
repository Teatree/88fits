## Pass 81, lane MAP: the lakes, the sand, the oasis ground and a structure's ring as the phone sees them, before and
## after. Windowed, silent, at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p81_MAP_shots.gd -- out=<dir> [seed=5] [only=lakes,wade,sand,ring,hell]
## One real run of Red Canyon (seed 5 by default), the Drifter in god mode, the director stopped, the crowd cleared:
##   lakes: the hero on the south shore of every lake, the lake ahead of him, at the standing zoom and pulled out
##   wade:  the hero in the first lake, two frames apart (the ripples moving)
##   sand:  the hero on open sand (the spot farthest from the lakes and the river inside 34 m), two zooms + a crop
##   ring:  a Loot Cache and a Healing Well ahead of him, the hero stood in the cache's ring until its pie is part full
##   hell:  stage 3's ground at the first lake
## Every wait is bounded and a watchdog quits after 200 s whatever happens. The save is never written (godot.sh keeps the
## PC's aside as well).
extends SceneTree

var _out := "user://p81_map_shots"
var _only: Array = []
var _seed := 5
var _sand_png := ""
## wp.<uniform>=<v> / tp.<uniform>=<v>: the water's / the terrain's shader uniforms set before the shots (a float, or r,g,b)
var _params: Array = []
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
		elif a.begins_with("sand="):
			_sand_png = a.substr(5)
		elif a.begins_with("wp.") or a.begins_with("tp."):
			_params.append(a)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p81_map: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(n: String, crop := Rect2i()) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + ".png"))
	if crop.size.x > 0:
		var r := crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(_out.path_join(n + "_crop.png"))
	print("p81_map: ", n)


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
	await _start_run()
	if _want("lakes"):
		await _lakes()
	elif _want("lake0"):
		await _lakes(1)
	if _want("wade"):
		await _wade()
	if _want("sand"):
		await _sand()
	if _want("ring"):
		await _ring()
	if _want("hell"):
		g.map.set_hell(1.0, 0.01)
		await _wait(0.4)
		var lk: Dictionary = (g.map.call("lakes") as Array)[0]
		var c: Vector2 = lk["center"]
		await _view("hell_lake0", Vector3(c.x, 0, c.y + float(lk["radius"]) * 1.45), 1.0)
	st.debug_mode = dbg_was
	_save.data = keep
	print("p81_map: done")
	quit(0)


func _start_run() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false})
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	await _game_ready()
	await _wait(2.5)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	# the run's own structures out of the way (a hero stood in a ring for a shot would open its menu)
	for st in g.structures.items:
		st.used = true
		st.visible = false
		for part in [st.ring, st.pie, st.hand]:
			if part:
				part.visible = false
	_apply_looks()
	await _wait(1.0)


## A sand candidate (sand=<png>) and any shader uniforms named on the command line, on the built map's materials.
func _apply_looks() -> void:
	var tm: ShaderMaterial = g.map.get("_terrain_mat")
	var wm: ShaderMaterial = g.map.get("_water_mat")
	if _sand_png != "" and tm:
		var img := Image.load_from_file(_sand_png)
		if img:
			img.generate_mipmaps()
			tm.set_shader_parameter("sand_tex", ImageTexture.create_from_image(img))
			print("p81_map: sand ", _sand_png)
	for a: String in _params:
		var kv := a.substr(3).split("=")
		if kv.size() != 2:
			continue
		var m: ShaderMaterial = wm if a.begins_with("wp.") else tm
		if m == null:
			continue
		var parts := kv[1].split(",")
		var v: Variant = float(kv[1]) if parts.size() == 1 else Color(float(parts[0]), float(parts[1]), float(parts[2]))
		m.set_shader_parameter(kv[0], v)
		print("p81_map: ", a)


func _game_ready() -> void:
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("director") != null:
			return


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _put_hero(p: Vector3) -> void:
	g.player.global_position = _ground(p)
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


## The hero stood at `at`, the camera at `zoom`, a moment to settle, a shot.
func _view(n: String, at: Vector3, zoom: float, crop := Rect2i()) -> void:
	g.enemies.kill_all(false)
	g.camera.zoom_override = zoom
	_put_hero(at)
	await _wait(1.2)
	await _shot(n, crop)


func _lakes(most := 99) -> void:
	var lakes: Array = g.map.call("lakes")
	for k in range(mini(lakes.size(), most)):
		var lk: Dictionary = lakes[k]
		var c: Vector2 = lk["center"]
		var r: float = lk["radius"]
		var at := Vector3(c.x, 0, c.y + r * 1.45)
		await _view("lake%d_z100" % k, at, 1.0, Rect2i(40, 300, 1000, 1000))
		await _view("lake%d_z150" % k, at, 1.5)


func _wade() -> void:
	var lk: Dictionary = (g.map.call("lakes") as Array)[0]
	var c: Vector2 = lk["center"]
	var r: float = lk["radius"]
	g.camera.zoom_override = 0.8
	_put_hero(Vector3(c.x - r * 0.2, 0, c.y + r * 0.45))
	await _wait(1.5)
	await _shot("wade_a", Rect2i(140, 400, 800, 900))
	await _wait(0.4)
	await _shot("wade_b", Rect2i(140, 400, 800, 900))


## The open sand farthest from the lakes and the river within 34 m of the middle (sampled on a 2 m grid).
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
			# away from the start's clearing, where the structures cluster
			d = minf(d, p.distance_to(Vector2(0, 8)) - 10.0)
			if d > best_d:
				best_d = d
				best = Vector3(p.x, 0, p.y)
	print("p81_map: sand spot ", best, " clear by ", best_d)
	return best


func _sand() -> void:
	var at := _sand_spot()
	await _view("sand_z100", at, 1.0, Rect2i(140, 1100, 800, 700))
	await _view("sand_z150", at, 1.5, Rect2i(140, 1100, 800, 700))


func _ring() -> void:
	var at := _sand_spot()
	_put_hero(at)
	var reg = root.get_node("Registry")
	var made: Array = []
	for pair: Array in [["loot_cache", Vector3(-1.5, 0, -5.0)], ["healing_well", Vector3(3.5, 0, -8.5)]]:
		var d = reg.structure(pair[0])
		if d == null or g.structures == null:
			continue
		made.append(g.structures._spawn(d, _ground(at + pair[1])))
	if made.is_empty():
		print("p81_map: no structures")
		return
	g.camera.zoom_override = 0.6
	await _wait(1.0)
	await _shot("ring_idle")
	# the hero steps into the cache's ring and stands there until its pie is a little under half full
	var s = made[0]
	_put_hero(s.global_position + Vector3(0.4, 0, 0.6))
	var waited := 0.0
	while waited < 4.0 and float(s.progress) < 0.4:
		await process_frame
		waited += 1.0 / 60.0
	await _shot("ring_fill40")
	var cam: Camera3D = g.camera.camera
	var sp: Vector2 = cam.unproject_position(s.global_position)
	var crop := Rect2i(int(sp.x) - 330, int(sp.y) - 260, 660, 520)
	var img := root.get_viewport().get_texture().get_image()
	img.get_region(crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(_out.path_join("ring_fill40_crop.png"))
	while waited < 6.0 and float(s.progress) < 0.75:
		await process_frame
		waited += 1.0 / 60.0
	await _shot("ring_fill75")
	img = root.get_viewport().get_texture().get_image()
	img.get_region(crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(_out.path_join("ring_fill75_crop.png"))
	# out again before it fires
	_put_hero(at + Vector3(0, 0, 6))
	await _wait(0.3)
	g.camera.zoom_override = 0.0
