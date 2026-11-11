## Pass 141 (lane GRAV) capture: the Gravity Gun's search (frames across one search: the beam reaching down, sweeping
## the sand with its glow and specks, drawing back) and a barrel taken, held, thrown and broken a little in front of the
## Outlaw, in the arena at the game's own zoom, cropped round him. Run with --fixed-fps 60 so frames count time. Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p141_GRAV_shots.gd -- out=<dir>
##       [only=search,barrel] [stages=0,1] [walk=1]
## Writes <out>/<stage>_search_<frame>.png and <out>/<stage>_barrel_<frame>.png (`walk=1`: the barrel sequence with him
## walking). Every wait is bounded (a watchdog quits after WATCHDOG seconds). The save and the settings in memory go back
## as they were (tools/godot.sh keeps the PC's save file aside as well).
extends SceneTree

const WATCHDOG := 200.0
## the crop round the Outlaw (px at 1080x1920) and how far ahead of him its middle sits (m)
const CROP := Vector2i(1000, 1060)
const CROP_AHEAD := 1.6
## the Outlaw's facing (radians; 0 = north, up the screen) and where the barrel stands (m ahead, m to his right)
const FACING := -0.35
const BARREL_AT := Vector2(2.2, 3.9)
## the frames (at 60 a second) after a search starts / after the barrel is taken that are written
const SEARCH_FRAMES := [4, 12, 22, 34, 46, 56]
const BARREL_FRAMES := [6, 16, 28, 38, 46, 52]

var _out := "user://p141_grav"
var _only: PackedStringArray = []
var _stages: Array = [0]
var _walk := false
var _run
var _save
var _settings
var _keep: Dictionary = {}
var _aim := true
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("stages="):
			_stages = Array(a.substr(7).split(",")).map(func(x): return int(x))
		elif a.begins_with("walk="):
			_walk = a.substr(5) == "1"
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _restore() -> void:
	if _save:
		_save.data = _keep
	if _settings:
		_settings.aim_mode = _aim


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p141_grav: watchdog, quitting")
		_restore()
		quit(3)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_keep = _save.data.duplicate(true)
	_aim = bool(_settings.aim_mode)
	_settings.aim_mode = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "gravity_gun", "level": 1, "character": "astro", "map": "red_canyon", "map_seed": 11, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _frames(150)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p141_grav: no game scene")
		_restore()
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _frames(60)
	for st: int in _stages:
		var tag: String = ["sundown", "nightfall", "dust", "bloodmoon"][clampi(st, 0, 3)]
		if st > 0:
			load("res://core/systems/StageLook.gd").call("of", g).show_stage(st, 0.0)
			await _frames(20)
		if _want("search"):
			await _shot_search(tag)
		if _want("barrel"):
			await _shot_barrel(tag)
	print("p141_grav: done -> ", _out)
	_restore()
	quit(0)


## The gun armed alone (level 1), the crowd and the shots cleared, every barrel within 12 m moved far off, the Outlaw
## standing still facing FACING; the gun's clock held far off.
func _arm() -> Node:
	g.enemies.kill_all(false)
	g.projectiles.clear_all()
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "gravity_gun", 1)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _frames(1)
	var b: Node = g._behaviors.get("gravity_gun")
	if b == null:
		return null
	b.cooldown_left = 99.0
	b._search_wait = 99.0
	g.player.facing = FACING
	g.player.velocity = Vector3.ZERO
	var bf = g.barrels
	var here: Vector3 = g.player.global_position
	if bf != null:
		for i in bf.pos.size():
			if bf.alive[i] == 1 and Vector2(bf.pos[i].x - here.x, bf.pos[i].z - here.z).length() < 12.0:
				bf.pos[i] = Vector3(here.x + 60.0 + float(i), bf.pos[i].y, here.z + 60.0)
				bf._draw_barrel(i, bf.pos[i], 0.0)
				bf._grid_dirty = true
	await _frames(40)
	return b


func _shot(name: String, centre: Vector3 = Vector3.INF, size: Vector2i = CROP) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var cam := root.get_viewport().get_camera_3d()
	var at := centre
	if at == Vector3.INF:
		at = g.player.global_position + g.player.forward() * CROP_AHEAD
	var px := cam.unproject_position(at) if cam else Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
	var x := clampi(int(px.x) - size.x / 2, 0, maxi(img.get_width() - size.x, 0))
	var y := clampi(int(px.y) - size.y / 2, 0, maxi(img.get_height() - size.y, 0))
	var sub := img.get_region(Rect2i(x, y, mini(size.x, img.get_width()), mini(size.y, img.get_height())))
	sub.save_png(_out.path_join(name + ".png"))
	print("p141_grav: ", name)


## One search from its first frame: the clock let go with nothing near.
func _shot_search(tag: String) -> void:
	var b: Node = await _arm()
	if b == null:
		print("p141_grav: no gun")
		return
	b._search_wait = 0.0
	b.cooldown_left = 0.0
	var n := 0
	while not b.searching() and n < 60:
		await process_frame
		n += 1
	if not b.searching():
		print("p141_grav: no search")
		return
	var at := 0
	for k: int in SEARCH_FRAMES:
		await _frames(k - at)
		at = k
		_shot("%s_search_%02d" % [tag, k])


## A barrel BARREL_AT from him: the clock let go, frames from the moment it is taken through its break and the loot.
func _shot_barrel(tag: String) -> void:
	var b: Node = await _arm()
	if b == null:
		print("p141_grav: no gun")
		return
	var bf = g.barrels
	var here: Vector3 = g.player.global_position
	var fw: Vector3 = g.player.forward()
	var right := fw.cross(Vector3.UP)
	var spot := here + fw * BARREL_AT.x + right * BARREL_AT.y
	spot.y = g.map.height_at(spot.x, spot.z) if g.map else 0.0
	if bf == null or not bf.respawn_at(spot, 0):
		print("p141_grav: no barrel")
		return
	await _frames(20)
	_shot("%s_barrel_00" % tag)
	var thrown: int = b.barrel_throws
	b.cooldown_left = 0.0
	var n := 0
	while b._bgrip.is_empty() and n < 30:
		await process_frame
		n += 1
	if b._bgrip.is_empty():
		print("p141_grav: barrel not taken")
		return
	if _walk:
		g.player.velocity = fw * 3.0
	var at := 0
	var broke := -1
	for k: int in BARREL_FRAMES:
		while at < k:
			await process_frame
			at += 1
			if _walk:
				g.player.global_position += fw * 3.0 / 60.0
			if broke < 0 and b.barrel_throws > thrown:
				broke = at
		_shot("%s_barrel_%02d" % [tag, k])
	# the frame it breaks, a beat after, and the loot on its way to him
	n = 0
	while broke < 0 and n < 90:
		await process_frame
		at += 1
		n += 1
		if b.barrel_throws > thrown:
			broke = at
	await _frames(2)
	_shot("%s_barrel_break" % tag)
	await _frames(10)
	_shot("%s_barrel_after" % tag)
	g.player.velocity = Vector3.ZERO
	print("p141_grav: barrel broke at frame %d" % broke)
