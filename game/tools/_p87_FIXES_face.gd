## Pass 87, lane FIXES, scratch capture in the debug arena: the Dynamite Bandit (spit_cactus, look SC-A) round the hero
## at the eight compass points, standing, winding up, releasing, walking in and backing off, each phase one 3x3 sheet with
## the hero's cell in the middle (a bandit facing the hero faces the sheet's centre). Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p87_FIXES_face.gd -- out=<dir> [front=right|left|straight] [back=...] [zoom=1.3]
## front= / back= override the look's facing keys before the first spawn (to compare). Every wait is bounded (frame caps
## and a watchdog quitting after WATCHDOG seconds).
extends SceneTree

const WATCHDOG := 120.0
var CELL := Vector2i(300, 340)
var _walk := 4.8
var _stand := 3.0
var _lift := 0.55
var _keep_d := 2.0
var _range := 4.0
var _back_at := 1.2
var _out := "user://p87_face"
var _front := ""
var _back := ""
var _zoom := 0.7
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}
var _hero := Vector3.ZERO
## grid cell (col,row) for each compass point; index k = angle k*45 deg from screen-right, anticlockwise on screen
const CELLS := [Vector2i(2, 1), Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("front="):
			_front = a.substr(6)
		elif a.begins_with("back="):
			_back = a.substr(5)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("walk="):
			_walk = float(a.substr(5))
		elif a.begins_with("stand="):
			_stand = float(a.substr(6))
		elif a.begins_with("keep="):
			_keep_d = float(a.substr(5))
		elif a.begins_with("range="):
			_range = float(a.substr(6))
		elif a.begins_with("back_at="):
			_back_at = float(a.substr(8))
		elif a.begins_with("lift="):
			_lift = float(a.substr(5))
		elif a.begins_with("cell="):
			var wh := a.substr(5).split("x")
			CELL = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if g != null and g.player != null and _hero != Vector3.ZERO:
		# the hero stays put (a blast's push would turn the compass)
		g.player.global_position = _hero
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p87_face: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _sheet(name: String, ids: Array) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var cam: Camera3D = g.camera.camera
	var em = g.enemies
	var sheet := Image.create(CELL.x * 3, CELL.y * 3, false, img.get_format())
	sheet.fill(Color(0.15, 0.15, 0.15))
	var line := name + ":"
	for k in range(ids.size()):
		var i: int = ids[k]
		if i < 0:
			continue
		var c: Vector2i = CELLS[k]
		var mid: Vector2 = cam.unproject_position(em.pos[i] + Vector3(0, em.size[i] * _lift + em.lift_h[i], 0))
		var r := Rect2i(int(mid.x) - CELL.x / 2, int(mid.y) - CELL.y / 2, CELL.x, CELL.y)
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 0 and r.size.y > 0:
			sheet.blit_rect(img, r, Vector2i(c.x * CELL.x, c.y * CELL.y))
		var t: int = em.type_idx[i]
		var strip: int = em._strip_of(i, t)
		line += " [%d: st %d strip %d flip %d away %d face %.0f]" % [k, em.state[i], strip, em.flip[i], em.away[i], em._face_bit(em.flip[i], t, em._face_strip(i, t, strip))]
	# the hero's cell
	var hp: Vector2 = cam.unproject_position(g.player.global_position + Vector3(0, 0.9, 0))
	var hr := Rect2i(int(hp.x) - CELL.x / 2, int(hp.y) - CELL.y / 2, CELL.x, CELL.y).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if hr.size.x > 0:
		sheet.blit_rect(img, hr, Vector2i(CELL.x, CELL.y))
	sheet.resize(CELL.x * 3 * 3 / 2, CELL.y * 3 * 3 / 2, Image.INTERPOLATE_LANCZOS)
	sheet.save_png(_out.path_join(name + ".png"))
	img.save_png(_out.path_join(name + "_full.png"))
	print("p87_face: ", line)


func _ring(dist: float, cd: float) -> Array:
	var em = g.enemies
	var ids: Array = []
	for k in range(8):
		var a := float(k) * PI / 4.0
		# screen-right is +X, screen-up is -Z
		var at := _hero + Vector3(cos(a), 0, -sin(a)) * dist
		var i: int = em.spawn("spit_cactus", at, null, 1.0, 200.0, "SC-A")
		ids.append(i)
		if i >= 0:
			em.cooldown[i] = cd
	var n := 0
	while n < 600:
		var up := true
		for i in ids:
			if i >= 0 and em.state[i] == em.STATE_SPAWN:
				up = false
		if up:
			break
		await process_frame
		n += 1
	return ids


func _clear() -> void:
	var em = g.enemies
	em.kill_all(false)
	await _wait(2.5)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var reg = root.get_node("Registry")
	var def = reg.enemy("spit_cactus")
	if _front != "":
		def.front_faces = _front
	if _back != "":
		def.back_faces = _back
	# closer than in play so the camera can come in (the facing does not read the distance)
	def.ranged["keep_distance"] = _keep_d
	def.ranged["range"] = _range
	print("p87_face: front ", def.front_faces, " back ", def.back_faces, " variant ", def.variant)
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
	await _wait(1.0)
	_hero = g.player.global_position
	# standing at 3 m (between keep_distance and range), no throw yet
	var ids: Array = await _ring(_stand, 999.0)
	await _wait(0.8)
	await _sheet("a_stand", ids)
	# the throw: all at once
	for i in ids:
		if i >= 0:
			em.cooldown[i] = 0.0
	var n := 0
	while n < 300:
		var all := true
		for i in ids:
			if i >= 0 and em.state[i] != em.STATE_WINDUP:
				all = false
		if all:
			break
		await process_frame
		n += 1
	await _wait(0.3)
	await _sheet("b_windup", ids)
	n = 0
	while n < 300:
		var all2 := true
		for i in ids:
			if i >= 0 and em.state[i] != em.STATE_ATTACK:
				all2 = false
		if all2:
			break
		await process_frame
		n += 1
	await process_frame
	await process_frame
	await _sheet("c_release", ids)
	await _clear()
	# walking in from 4.8 m
	ids = await _ring(_walk, 999.0)
	await _wait(0.25)
	await _sheet("d_walk_in", ids)
	await _clear()
	# backing off from 1.2 m
	ids = await _ring(_back_at, 999.0)
	await _wait(0.12)
	await _sheet("e_back_off", ids)
	_save.data = _keep
	quit(0)
