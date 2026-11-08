## Pass 136 (lane PLACED) capture: the Skull Rain's skulls sitting on the sand in their poison clouds (GroundSkulls),
## popping up, sitting, sinking away; Grave Hail's sugar skulls; the placed Dynamite's spots round the Outlaw. In the
## arena, the aim switch on. Windowed, bounded waits and a watchdog:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game
##       --script res://tools/_p136_PLACED_shots.gd -- out=<dir> [zoom=0.6] [only=skull,hail,close]
## Writes <out>/<name>.png at half size. The PC save is put back as it was.
extends SceneTree

const WATCHDOG_S := 220.0

var _out := "user://p136_placed"
var _zoom := 0.6
var _only: Array = []
var _run
var _save
var _settings
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p136_placed: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	var keep: Dictionary = _save.data.duplicate(true)
	_settings.aim_mode = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "calavera", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p136_placed: no game scene")
		_save.data = keep
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	await _wait(1.0)
	for name: String in ["skull", "hail", "close"]:
		if not _only.is_empty() and not _only.has(name):
			continue
		match name:
			"skull":
				await _shot_skull("skull_rain", 5, "skull")
			"hail":
				await _shot_skull("grave_hail", 1, "hail")
			"close":
				if g.camera:
					g.camera.zoom_override = 0.35
				await _shot_skull("skull_rain", 3, "close")
				if g.camera and _zoom > 0.0:
					g.camera.zoom_override = _zoom
	print("p136_placed: done -> ", _out)
	_save.data = keep
	quit(0)


func _arm(id: String, level: int) -> Object:
	_run.debug_clear_items()
	_run.debug_set_item("weapon", id, level)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.5)
	var b = g._behaviors.get(id)
	if b:
		b.cooldown_left = 99.0
	g.enemies.kill_all(false)
	g.projectiles.clear_all()
	await _frames(20)
	return b


## Creatures standing still at `spots` (relative to the Outlaw), risen before the shot.
func _crowd(spots: Array, id := "skeleton") -> Array:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var out: Array = []
	for p: Vector3 in spots:
		var i: int = em.spawn(id, here + p, null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] = 0.0
			out.append(i)
	em._rebuild_grid()
	await _frames(70)
	return out


func _save_frame(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png(_out.path_join(name + ".png"))
	print("p136_placed: ", name)


## Throws a few volleys of `id` (a crowd a little ahead and to the side), then captures the skulls landing, sitting in
## their clouds and sinking away as the clouds end.
func _shot_skull(id: String, level: int, tag: String) -> void:
	var b = await _arm(id, level)
	if b == null:
		print("p136_placed: no behaviour for ", id)
		return
	var spots: Array = []
	for k in range(10):
		spots.append(Vector3(-3.0 + float(k % 5) * 0.8, 0.0, -6.0 + float(k / 5) * 0.8))
	await _crowd(spots)
	var gs = g.get_node_or_null("GroundSkulls")
	var before: int = gs.count() if gs else 0
	for v in range(3):
		b._fire()
		await _frames(12)
	# the first skull down (bounded; the pool is made with the first)
	for k in range(240):
		gs = g.get_node_or_null("GroundSkulls")
		if gs and gs.count() > before:
			break
		await process_frame
	if gs == null:
		print("p136_placed: no skulls")
		return
	await _frames(8)
	_save_frame("%s_land" % tag)
	await _frames(60)
	_save_frame("%s_sit" % tag)
	# the oldest skull sinking: its life under a third of a second (bounded)
	for k in range(600):
		var low := false
		for it: Dictionary in gs._items:
			if float(it["life"]) < 0.3:
				low = true
		if low:
			break
		await process_frame
	_save_frame("%s_sink" % tag)
	for k in range(300):
		if gs.count() == 0:
			break
		await process_frame
	_save_frame("%s_gone" % tag)
	b.cooldown_left = 99.0
