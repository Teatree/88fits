## Pass 136 (lane HOMING) capture: the aimed Rocket Pod's marks (a volley locked on a crowd ahead, a dry volley), the Zap
## Beam's and the Sun Scepter's burns on the sand, and the Big Mouth pouring down the facing, in the arena. Windowed,
## bounded waits and a watchdog:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game
##       --script res://tools/_p136_HOMING_shots.gd -- out=<dir> [zoom=0.6] [only=rockets,dry,zap,sun,mouth]
## Writes <out>/<name>.png at half size. The PC save is put back as it was.
extends SceneTree

const WATCHDOG_S := 220.0

var _out := "user://p136_homing"
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
		print("p136_homing: WATCHDOG, quitting")
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
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p136_homing: no game scene")
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
	for name: String in ["rockets", "dry", "zap", "sun", "mouth"]:
		if not _only.is_empty() and not _only.has(name):
			continue
		match name:
			"rockets":
				await _shot_rockets()
			"dry":
				await _shot_dry()
			"zap":
				await _shot_zap()
			"sun":
				await _shot_sun()
			"mouth":
				await _shot_mouth()
	print("p136_homing: done -> ", _out)
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
	print("p136_homing: ", name)


func _ahead(d: float, side: float = 0.0) -> Vector3:
	var f: Vector3 = g.player.forward()
	f.y = 0.0
	f = f.normalized()
	return f * d + f.cross(Vector3.UP) * side


func _shot_rockets() -> void:
	var b = await _arm("rocket_pod", 3)
	if b == null:
		return
	await _crowd([_ahead(7.0, -1.5), _ahead(8.0, 1.0), _ahead(9.0, 0.0), _ahead(4.0, 6.0)])
	b.cooldown_left = 1.0 / 60.0
	await _frames(28)
	_save_frame("rockets_locked")
	await _frames(14)
	_save_frame("rockets_locked_late")


func _shot_dry() -> void:
	var b = await _arm("rocket_pod", 3)
	if b == null:
		return
	b.cooldown_left = 1.0 / 60.0
	await _frames(30)
	_save_frame("rockets_dry")


func _shot_zap() -> void:
	var b = await _arm("zap_beam", 3)
	if b == null:
		return
	await _crowd([_ahead(4.0, 2.0), _ahead(-3.0, -2.5)])
	for k in range(4):
		b.cooldown_left = 1.0 / 60.0
		await _frames(8)
	g.enemies.kill_all(false)
	await _frames(4)
	for k in range(4):
		b.cooldown_left = 1.0 / 60.0
		await _frames(8)
	await _frames(6)
	_save_frame("zap_marks")


func _shot_sun() -> void:
	var b = await _arm("sun_scepter", 3)
	if b == null:
		return
	for k in range(4):
		b.cooldown_left = 1.0 / 60.0
		await _frames(40)
	await _frames(10)
	_save_frame("sun_marks")


func _shot_mouth() -> void:
	var b = await _arm("big_mouth", 3)
	if b == null:
		return
	await _crowd([_ahead(5.0, 0.0), _ahead(8.0, 0.3), _ahead(6.0, 3.0)])
	b.cooldown_left = 1.0 / 60.0
	await _frames(50)
	_save_frame("mouth_pour")
