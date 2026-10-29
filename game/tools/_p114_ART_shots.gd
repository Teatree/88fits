## Pass 114 (lane ART): one Spit Cactus look (the Bombmaker SC-B / SC-C, or any code) in the debug arena with the
## training field cleared, the hero in god mode with no weapons (nothing dies), three approaches:
##   front  spawned well above the hero: walks down to him (front walk), winds up, throws (the front half of the throw)
##   away   spawned too close above him: backs off up the screen (the back walk)
##   below  spawned below him in range: winds up and throws up the screen (the back half of the throw)
## Whole frames + a crop round the creature; the drawn frame and mirror bit printed for each shot.
## Windowed at the phone's canvas, fixed ticks:
##   GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/_p114_ART_shots.gd -- out=<dir> variant=SC-B [zoom=0.7] [below_zoom=1.4]
## A watchdog quits after WATCHDOG seconds whatever happens; every wait is bounded. The save's data is put back.
extends SceneTree

const WATCHDOG := 150.0
const CROP := 460
var _out := "user://p114_art"
var _variant := "SC-B"
var _zoom := 0.7
var _below_zoom := 1.4
var _run
var _save
var _keep: Dictionary = {}
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("variant="):
			_variant = a.substr(8)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("below_zoom="):
			_below_zoom = float(a.substr(11))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p114_art: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _frames(n: int) -> void:
	for _k in range(n):
		if g != null and g.player:
			g.player.velocity = Vector3.ZERO
		await process_frame


func _shot(name: String, i: int) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	var em = g.enemies
	if i >= 0 and em.alive[i] == 1:
		var p: Vector2 = g.camera.camera.unproject_position(em.pos[i])
		var x := clampi(int(p.x) - CROP / 2, 0, img.get_width() - CROP)
		var y := clampi(int(p.y) - int(CROP * 0.62), 0, img.get_height() - CROP)
		img.get_region(Rect2i(x, y, CROP, CROP)).save_png(_out.path_join(name + "_crop.png"))
	print("p114_art: ", name, " state ", em.state[i] if i >= 0 else -1, " away ", em.away[i] if i >= 0 else -1,
		" frame ", em.drawn_frame(i) if i >= 0 else Vector2i(-1, -1), " pos ", em.pos[i] if i >= 0 else Vector3.ZERO)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for _k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _frames(150)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _frames(20)
	g.enemies.kill_all(false)
	await _frames(40)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _approach("front", Vector3(0.6, 0, -9.5), true)
	await _clear()
	await _approach("away", Vector3(0.6, 0, -2.6), false)
	await _clear()
	# the view reaches less far below the hero than above him: pull the camera back for the throw from below
	g.camera.zoom_override = _below_zoom
	await _frames(30)
	await _approach("below", Vector3(0.6, 0, 6.2), true)
	_save.data = _keep
	quit(0)


func _clear() -> void:
	g.projectiles.clear_all()
	g.enemies.kill_all(false)
	await _frames(40)


## One cactus spawned at the hero's position + `off`: 12 shots of its walk, then (with `throw`) the wind-up and release.
func _approach(tag: String, off: Vector3, throw: bool) -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var i: int = em.spawn("spit_cactus", here + off, null, 1.0, 200.0, _variant)
	print("p114_art: spawned ", i, " variant ", _variant, " ", tag)
	if i < 0:
		return
	var n := 0
	while em.state[i] != em.STATE_MOVE and n < 400:
		await process_frame
		n += 1
	em.cooldown[i] = 3.0
	for k in range(12):
		await _frames(4)
		_shot("%s_a%02d_walk" % [tag, k], i)
	if not throw:
		return
	em.cooldown[i] = minf(em.cooldown[i], 0.3)
	n = 0
	while em.state[i] != em.STATE_WINDUP and n < 600:
		await process_frame
		n += 1
	await process_frame
	_shot("%s_b00_windup" % tag, i)
	await _frames(18)
	_shot("%s_b01_windup" % tag, i)
	var thrown0: int = em.dynamite_throws
	n = 0
	while em.dynamite_throws == thrown0 and n < 600:
		await process_frame
		n += 1
	await process_frame
	_shot("%s_c00_release" % tag, i)
	for k in range(1, 4):
		await _frames(5)
		_shot("%s_c%02d_release" % [tag, k], i)
	await _frames(40)
	_shot("%s_d00_after" % tag, i)
