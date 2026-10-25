## Pass 106, lane ENDLESS (scratch): the Desert Spider's looks walking at the hero and dying, in the debug arena, in each
## stage's look (0 Sundown, 1 Nightfall, 2 Blood Moon), cropped round each spider and blown up 2x; an optional shadow
## tuning tried live (EnemyManager.set_shadow_tuning). Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p106_ENDLESS_spider.gd -- out=<dir> [looks=SP-G,SP-H] [stages=0,1] [tune={...}] [zoom=0.5] [id=desert_spider]
## Bounded: a 150 s watchdog and a frame cap; the PC save is put back.
extends SceneTree

const WATCHDOG := 150.0
const TIMES := [0.1, 0.3, 0.5, 0.7, 0.95, 1.12, 1.2, 1.28, 1.36]
var _row_z := 2.5
var _out := "user://p106_spider"
var _id := "desert_spider"
var _looks: Array = ["SP-G", "SP-H"]
var _stages: Array = [0, 1]
var _tune = null
var _zoom := 0.7
var _run
var _save
var g
var _t0 := 0
var _frames := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("id="):
			_id = a.substr(3)
		elif a.begins_with("looks="):
			_looks = Array(a.substr(6).split(","))
		elif a.begins_with("stages="):
			_stages = []
			for s in a.substr(7).split(",", false):
				_stages.append(int(s))
		elif a.begins_with("tune="):
			_tune = JSON.parse_string(a.substr(5))
		elif a.begins_with("z="):
			_row_z = float(a.substr(2))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	_frames += 1
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0) or _frames > 20000:
		print("p106_spider: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String, ids: Array) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var em = g.enemies
	var w := 260
	var h := 260
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
	print("p106_spider: ", name)


func _spawn_row(z: float) -> Array:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids: Array = []
	var n := _looks.size()
	for k in range(n):
		var x := (float(k) - float(n - 1) * 0.5) * 3.0 + 2.0
		var i: int = em.spawn(_id, here + Vector3(x, 0, z), null, 1.0, 400.0, str(_looks[k]))
		ids.append(i)
		if _tune is Dictionary:
			em.set_shadow_tuning(em.type_idx[i], _tune)
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


func _look(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)
	var m = g.map
	if m.get("_hell_tween") and m._hell_tween:
		m._hell_tween.kill()
	if m.has_method("_apply_hell"):
		m._apply_hell(1.0 if sl.hell_of(sl._timeline(), s) else 0.0)


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
	for s: int in _stages:
		_look(s)
		em.kill_all(false)
		await _wait(0.4)
		var ids: Array = await _spawn_row(_row_z)
		await _wait(0.3)
		_shot("s%d_walk" % s, ids)
		# held still for the death: no corpse throw (kill_all without a push), the strip, the hold and the sink at the end
		# (EnemyManager.DIE_TIME 1.4 s, DIE_SINK the last 0.3 s)
		em.kill_all(true)
		var t := 0.0
		for k in range(TIMES.size()):
			await _wait(float(TIMES[k]) - t)
			t = float(TIMES[k])
			_shot("s%d_d%02d" % [s, k], ids)
	_save.data = _keep
	quit(0)
