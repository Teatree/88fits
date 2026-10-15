## Pass 79, lane WORLD: the map's sides as the phone sees them, before and after the rock and wall colours change.
## Windowed, silent, at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p79_WORLD_shots.gd -- out=<dir> [seed=11] [only=rim,wide,totem,crowd,hell]
## One real run of Red Canyon (seed 11), the Drifter in god mode, the director stopped, the crowd cleared:
##   rim:   the hero at the north, east, west and south rim and the north-east corner, at the play zoom and pulled out
##   wide:  the hero at the middle, pulled all the way out (the whole ring of rock and wall round the screen's top)
##   totem: a used (grey) Totem Pole stood on the rock by the north wall
##   crowd: a few creatures on the rock (do they still read on it)
##   hell:  stage 3's red ground at the north and east rim
## pal=<file.json> [pals=a,b]: the colour candidates instead (a JSON {name: {"rock_color": "#..", "wall_colors": {..}}}),
## each laid on the map's timeline before a run of its own, the rim views shot as <name>_<view>.png.
## Every wait is bounded and a watchdog quits after 200 s whatever happens. The save is never written (godot.sh keeps the
## PC's aside as well).
extends SceneTree

var _out := "user://p79_world_shots"
var _only: Array = []
var _seed := 11
var _pal_file := ""
var _pals: Array = []
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
		elif a.begins_with("pal="):
			_pal_file = a.substr(4)
		elif a.begins_with("pals="):
			_pals = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p79_world: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + ".png"))
	print("p79_world: ", n)


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
		print("p79_world: done")
		quit(0)
		return
	await _start_run()
	if _want("rim"):
		await _rims()
	if _want("wide"):
		await _view("06_wide_middle", Vector3(0, 0, 8), 2.1)
	if _want("totem"):
		await _totem()
	if _want("crowd"):
		await _crowd()
	if _want("hell"):
		g.map.set_hell(1.0, 0.01)
		await _wait(0.4)
		await _view("09_hell_north", Vector3(0, 0, -50), 1.4)
		await _view("10_hell_east", Vector3(52, 0, -6), 1.4)
	st.debug_mode = dbg_was
	_save.data = keep
	print("p79_world: done")
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
	await _wait(1.0)


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


## A Totem Pole stood on the rock by the north wall and spent (its grey painting), the hero beside it.
func _totem() -> void:
	var pole = null
	for s in g.structures.items:
		if s.def.id == "totem_pole":
			pole = s
			break
	if pole == null:
		print("p79_world: no pole")
		return
	var at := _ground(Vector3(-4, 0, -55))
	pole.global_position = at
	pole.used = true
	for k in ["pie", "hand", "ring"]:
		var n = pole.get(k)
		if n:
			n.visible = false
	if pole.glow:
		pole.glow.light_energy = 0.0
	var sm = load("res://core/systems/StructureManager.gd")
	var grey = sm.grey_painting(pole.def)
	if pole.visual and pole.visual.has_method("set_texture") and grey != null:
		pole.visual.set_texture(grey)
		pole.visual.set_tint(sm.SPENT_GREY_TINT)
	await _view("07_totem_used_on_rock", Vector3(0, 0, -50), 1.15)


## A few creatures on the rock round the hero at the east rim, held still.
func _crowd() -> void:
	g.camera.zoom_override = 1.15
	var c := Vector3(50, 0, -8)
	_put_hero(c + Vector3(0, 0, 3))
	var ids := ["skeleton", "fire_ant", "skeleton_knight", "dust_mummy", "bull_beetle"]
	for k in range(12):
		var a := float(k) / 12.0 * TAU
		var r := 3.0 + float(k % 3) * 1.6
		g.enemies.spawn(ids[k % ids.size()], _ground(c + Vector3(cos(a) * r, 0, sin(a) * r)), null, 1.0, 200.0)
	await _wait(0.8)
	g.enemies.time_scale = 0.0
	await _wait(0.6)
	await _shot("08_crowd_on_rock")
	g.enemies.time_scale = 1.0
	g.enemies.kill_all(false)
	await _wait(0.5)


## The colour candidates: each laid on the map's timeline, a run of its own, the rim views.
func _palettes() -> void:
	var f := FileAccess.open(_pal_file, FileAccess.READ)
	var all = JSON.parse_string(f.get_as_text()) if f else null
	if not all is Dictionary:
		print("p79_world: no palettes in ", _pal_file)
		return
	var tl = root.get_node("Registry").map("red_canyon").timeline
	for name: String in (all as Dictionary).keys():
		if not _pals.is_empty() and not _pals.has(name):
			continue
		var p: Dictionary = all[name]
		tl.rock_color = str(p.get("rock_color", ""))
		tl.wall_colors = p.get("wall_colors", {})
		await _start_run()
		await _view(name + "_north_play", Vector3(0, 0, -50), 1.15)
		await _view(name + "_northeast_play", Vector3(37, 0, -37), 1.15)
		await _view(name + "_north_far", Vector3(0, 0, -50), 1.8)
		if _pals.size() <= 3:
			await _view(name + "_east_far", Vector3(52, 0, -6), 1.8)
