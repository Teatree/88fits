## Pass 88, lane TWEAKS, scratch capture in the debug arena: a creature's looks walking at the hero from the far side
## (front walk), from the camera's side (back walk) and dying, each cropped round the creature and blown up 2x, with an
## optional shadow tuning tried live (EnemyManager.set_shadow_tuning). Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p88_TWEAKS_shot.gd -- out=<dir> id=dust_mummy looks=DM-G [tune={"up":0.1}] [zoom=0.5]
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds).
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p88_tweaks"
var _id := "dust_mummy"
var _looks: Array = []
var _tune = null
var _zoom := 0.5
var _back_z := 1.6
var _x_off := 3.0
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("id="):
			_id = a.substr(3)
		elif a.begins_with("looks="):
			_looks = Array(a.substr(6).split(","))
		elif a.begins_with("tune="):
			_tune = JSON.parse_string(a.substr(5))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("back_z="):
			_back_z = float(a.substr(7))
		elif a.begins_with("x_off="):
			_x_off = float(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p88_tweaks: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


## The frame cropped round every creature in `ids` (its foot point on the screen), side by side, 2x.
func _shot(name: String, ids: Array) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var em = g.enemies
	var w := 300
	var h := 380
	var sheet := Image.create(w * 2 * ids.size(), h * 2, false, img.get_format())
	for k in range(ids.size()):
		var i: int = ids[k]
		var p: Vector2 = cam.unproject_position(em.pos[i])
		var r := Rect2i(int(p.x) - w / 2, int(p.y) - h + 90, w, h)
		r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var c := img.get_region(r)
		c.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(k * w * 2, 0))
	sheet.save_png(_out.path_join(name + ".png"))
	print("p88_tweaks: ", name)


func _spawn_row(z: float) -> Array:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids: Array = []
	var looks: Array = _looks if not _looks.is_empty() else [""]
	var n := looks.size()
	for k in range(n):
		var x := (float(k) - float(n - 1) * 0.5) * 2.4 + _x_off
		var i: int = em.spawn(_id, here + Vector3(x, 0, z), null, 1.0, 400.0, str(looks[k]))
		ids.append(i)
		if _tune is Dictionary:
			em.set_shadow_tuning(em.type_idx[i], _tune)
	# out of the ground and walking first (bounded)
	var c := 0
	while c < 300:
		var up := true
		for i in ids:
			if em.state[i] != em.STATE_MOVE:
				up = false
		if up:
			break
		await process_frame
		c += 1
	return ids


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(1.0)
	var em = g.enemies
	em.kill_all(false)
	# the far side: they walk down the screen at the hero, their front walk
	var ids: Array = await _spawn_row(-6.0)
	await _wait(0.3)
	for k in range(6):
		_shot("f%02d_front" % k, ids)
		await _wait(0.09)
	# the deaths, from the front row
	em.kill_all(true)
	for k in range(10):
		await _wait(0.1)
		_shot("d%02d_die" % k, ids)
	await _wait(0.6)
	em.kill_all(false)
	await _wait(0.4)
	# the camera's side: they walk up the screen, their back walk
	ids = await _spawn_row(_back_z)
	await _wait(0.3)
	for k in range(6):
		_shot("b%02d_back" % k, ids)
		await _wait(0.09)
	_save.data = _keep
	quit(0)
