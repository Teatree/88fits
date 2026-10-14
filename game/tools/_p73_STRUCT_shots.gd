## Pass 73, lane STRUCT: captures for the Stranger's seam and the Totem Poles. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p73_STRUCT_shots.gd -- out=<dir> [only=stranger,totem,menu,map] [tag=before] [inset=130]
## stranger: the debug arena, the Stranger standing ahead of the hero beside the shop (two zooms, whole and cropped),
##   then his bargain screen (12-stranger as wanted_shots shows it).
## totem: three Totem Poles ahead of the hero beside a shop (the size against another structure), their rings; one is
##   used for real (the hero stood in its circle): the menu (menu_*), then a real pick, the pole grey and still standing.
## menu: the menu alone on a fresh offer, at the run's inset and at inset=130 (a camera cutout).
## map: a real run's scatter (not the arena): every structure's spot, the river, the lake and the signs' arms drawn as a
##   plan (map_plan.png, 1 px = 0.2 m) with the counts printed.
## A watchdog quits after 170 s whatever happens; every wait is bounded.
extends SceneTree

var _out := "user://p73_struct_shots"
var _only: Array = []
var _tag := ""
var _inset := -1
var _run
var _save
var _reg
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(170.0, true, false, true).timeout.connect(func() -> void:
		print("p73_struct: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _name(n: String) -> String:
	return n if _tag == "" else "%s_%s" % [n, _tag]


func _shot(n: String, crop := Rect2i()) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(_name(n) + ".png"))
	if crop.size.x > 0:
		var r := crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(_out.path_join(_name(n) + "_crop.png"))
	print("p73_struct: ", _name(n))


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	var inset_was: int = st.top_inset
	if _inset >= 0:
		st.top_inset = _inset
	if _want("map"):
		await _map_plan()
	if _want("stranger") or _want("totem") or _want("menu"):
		await _arena()
		if _want("stranger"):
			await _stranger()
		if _want("totem"):
			await _totem_world()
		if _want("menu"):
			await _menu()
	st.top_inset = inset_was
	_save.data = keep
	quit(0)


## The debug arena, the hero in god mode with no weapon and nothing around him.
func _arena() -> void:
	_launch({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7})
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _game_ready()
	await _wait(2.0)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.4)
	g.enemies.kill_all(false)
	g.director.stop()
	await _wait(3.0)


func _game_ready() -> void:
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			return


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


var _spawned: Array = []


func _spawn_structure(id: String, at: Vector3):
	var d = _reg.structure(id)
	if d == null or g.structures == null:
		return null
	var s = g.structures._spawn(d, _ground(at))
	_spawned.append(s)
	return s


## Every structure this tool stood up taken away again (its ring, pie and hand hang off the manager, not off it).
func _clear_spawned() -> void:
	for s in _spawned:
		if is_instance_valid(s):
			g.structures.items.erase(s)
			for part in [s.ring, s.pie, s.hand]:
				if part and is_instance_valid(part):
					part.queue_free()
			s.queue_free()
	_spawned.clear()
	await _wait(0.2)


## The Stranger ahead of the hero beside the shop, at the run's zoom and nearer; then his screen.
func _stranger() -> void:
	var here: Vector3 = g.player.global_position
	_spawn_structure("hooded_figure", here + Vector3(-2.2, 0, -6.0))
	_spawn_structure("shop", here + Vector3(3.2, 0, -7.0))
	await _wait(0.5)
	for z: float in [1.0, 0.55]:
		g.camera.zoom_override = z
		await _wait(0.8)
		await _shot("stranger_world_z%d" % int(z * 100), Rect2i(140, 300, 800, 900))
	g.camera.zoom_override = 0.0
	await _wait(0.3)
	g.set_paused(true)
	g.stranger_screen.open({"type": "passive", "id": "guillotine", "def": _reg.passive("guillotine"), "level_from": 0, "level_to": 2, "is_new": true}, 0.15)
	await _wait(0.9)
	await _shot("stranger_screen", Rect2i(0, 200, 1080, 1100))
	g.stranger_screen.visible = false
	g.modal_reset()
	g.set_paused(false)
	await _clear_spawned()
	await _wait(0.3)


## Three poles ahead of the hero and a shop, two zooms; the hero stands in the nearest one's circle until it is used:
## the menu, a real pick, the pole grey.
func _totem_world() -> void:
	var here: Vector3 = g.player.global_position
	var poles: Array = []
	for off: Vector3 in [Vector3(-3.6, 0, -6.5), Vector3(0.4, 0, -9.5), Vector3(3.8, 0, -6.0)]:
		poles.append(_spawn_structure("totem_pole", here + off))
	_spawn_structure("shop", here + Vector3(-1.0, 0, -15.0))
	await _wait(0.6)
	for z: float in [1.0, 0.55]:
		g.camera.zoom_override = z
		await _wait(0.8)
		await _shot("totem_world_z%d" % int(z * 100), Rect2i(90, 250, 900, 1000))
	g.camera.zoom_override = 0.55
	# the hero walks into the first pole's circle and stands there
	var p0: Node3D = poles[0]
	g.player.global_position = _ground(p0.global_position + Vector3(0.3, 0, 0.3))
	g.camera.snap_to(g.player)
	var waited := 0.0
	while waited < 6.0 and not g.totem_screen.visible:
		await _wait(0.25)
		waited += 0.25
	await _wait(0.9)
	await _shot("menu_from_pole")
	# a real tap on the second plank
	var pl: Array = g.totem_screen.planks()
	if pl.size() >= 2:
		var at: Vector2 = (pl[1] as Control).get_global_rect().get_center()
		await _tap(at)
	waited = 0.0
	while waited < 3.0 and g.totem_screen.visible:
		await _wait(0.1)
		waited += 0.1
	await _wait(1.6)
	g.player.global_position = _ground(here)
	g.camera.snap_to(g.player)
	await _wait(1.0)
	await _shot("totem_used_z55", Rect2i(90, 250, 900, 1000))
	g.camera.zoom_override = 0.0
	print("p73_struct: boons now ", _run.totem_boons)


func _tap(at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = true
	root.push_input(e)
	await process_frame
	await process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = at
	u.pressed = false
	root.push_input(u)
	await process_frame


## The menu on a fresh offer of the pole, as it opens in a run.
func _menu() -> void:
	var d = _reg.structure("totem_pole")
	var boons = load("res://core/systems/TotemBoons.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for k in range(2):
		g.set_paused(true)
		g.totem_screen.open(boons.offer(d, rng), d)
		await _wait(1.0)
		await _shot("menu_%d" % k)
		g.totem_screen.visible = false
		g.set_paused(false)
		await _wait(0.2)


## A real run's scatter drawn as a plan: the arena, the river, the lake, every structure (totems turquoise), every sign
## and its arms; the counts printed.
func _map_plan() -> void:
	_launch({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false})
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	await _game_ready()
	await _wait(1.5)
	var sm = g.structures
	var scale := 5.0
	var size := int(ceil((g.map.arena_radius + 4.0) * 2.0 * scale))
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.93, 0.84, 0.68))
	var cx := size * 0.5
	var to_px := func(x: float, z: float) -> Vector2i: return Vector2i(int(cx + x * scale), int(cx + z * scale))
	# the wall
	for k in range(720):
		var a := TAU * k / 720.0
		var p: Vector2i = to_px.call(cos(a) * g.map.arena_radius, sin(a) * g.map.arena_radius)
		_dot(img, p, 2, Color(0.4, 0.25, 0.15))
	# the river and the lake
	if g.map.has_method("river_points"):
		var pts: Array = g.map.river_points()
		for k in range(pts.size() - 1):
			var a2: Vector2 = pts[k]
			var b2: Vector2 = pts[k + 1]
			for s in range(60):
				var q := a2.lerp(b2, s / 60.0)
				_dot(img, to_px.call(q.x, q.y), int(g.map.river_width * 0.5 * scale), Color(0.75, 0.62, 0.45))
	if g.map.has_method("lake_center"):
		var lc: Vector2 = g.map.lake_center()
		_dot(img, to_px.call(lc.x, lc.y), int(g.map.lake_radius() * scale), Color(0.35, 0.6, 0.8))
	var signs = g.get_node_or_null("Signs")
	if signs:
		for rec: Dictionary in signs.arms:
			var at: Vector3 = signs.spots[int(rec["sign"])]
			var s3: Vector3 = (rec["structure"] as Node3D).global_position
			for t in range(40):
				var q3 := at.lerp(s3, t / 40.0 * 0.35)
				_dot(img, to_px.call(q3.x, q3.z), 1, Color(0.2, 0.15, 0.1))
		for at2: Vector3 in signs.spots:
			_dot(img, to_px.call(at2.x, at2.z), 4, Color(0.1, 0.08, 0.06))
	var n_totem := 0
	var n_other := 0
	var nearest := INF
	var poles: Array = []
	for s in sm.items:
		var p3: Vector3 = s.global_position
		var is_t: bool = s.def.id == "totem_pole"
		if is_t:
			n_totem += 1
			poles.append(p3)
		else:
			n_other += 1
		_dot(img, to_px.call(p3.x, p3.z), int(s.def.radius * scale) + 2, Color(0.1, 0.1, 0.1))
		_dot(img, to_px.call(p3.x, p3.z), int(s.def.radius * scale), Color(0.18, 0.71, 0.66) if is_t else s.def.color)
	for a3: Vector3 in poles:
		for b3: Vector3 in poles:
			if a3 != b3:
				nearest = minf(nearest, Vector2(a3.x - b3.x, a3.z - b3.z).length())
	var to_totem := 0
	if signs:
		for rec2: Dictionary in signs.arms:
			if (rec2["structure"] as Node3D).get("def").id == "totem_pole":
				to_totem += 1
	img.save_png(_out.path_join(_name("map_plan") + ".png"))
	print("p73_struct: map plan: %d totems, %d other structures, nearest two totems %.1f m, %d signs, %d arms (%d to totems)" % [
		n_totem, n_other, nearest, signs.spots.size() if signs else 0, signs.arms.size() if signs else 0, to_totem])


func _dot(img: Image, p: Vector2i, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var q := p + Vector2i(x, y)
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					img.set_pixelv(q, col)
