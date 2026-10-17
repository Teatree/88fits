## Pass 85, lane BANDIT, scratch capture in the debug arena: the Dynamite Bandit (spit_cactus look SC-A) winding up,
## throwing, the stick in flight, lying with its fuse, and the blast, frame by frame. Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p85_bandit_shot.gd -- out=<dir> [variant=SC-A] [side=1]
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds).
extends SceneTree

const WATCHDOG := 90.0
var _out := "user://p85_bandit"
var _variant := "SC-A"
var _side := false
var _run
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("variant="):
			_variant = a.substr(8)
		elif a == "side=1":
			_side = true
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p85_bandit: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	var where := ""
	if g != null and g.get("projectiles"):
		var pm = g.projectiles
		for j in range(pm.MAX):
			if pm.alive[j] == 1 and pm.extra[j] is Dictionary and (pm.extra[j] as Dictionary).has("dynamite"):
				where += " stick %s lie %s" % [str(pm.pos[j]), str((pm.extra[j] as Dictionary).get("lie_t", "-"))]
		where += " hero %s frame %d" % [str(g.player.global_position), Engine.get_process_frames()]
	print("p85_bandit: ", name, where)


var _keep: Dictionary = {}


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
		g.camera.zoom_override = 0.55
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(1.0)
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	var at := here + (Vector3(6.5, 0, 0) if _side else Vector3(0.5, 0, -6.5))
	var i: int = em.spawn("spit_cactus", at, null, 1.0, 200.0, _variant)
	print("p85_bandit: spawned ", i, " variant ", _variant)
	# out of the ground and standing first
	var n := 0
	while em.state[i] != em.STATE_MOVE and n < 400:
		await process_frame
		n += 1
	em.cooldown[i] = 0.4
	await _wait(0.2)
	_save_shot("a00_walk")
	# the wind-up
	n = 0
	while em.state[i] != em.STATE_WINDUP and n < 600:
		await process_frame
		n += 1
	await process_frame
	_save_shot("b00_windup")
	await _wait(0.35)
	_save_shot("b01_windup_mid")
	var thrown0: int = em.dynamite_throws
	n = 0
	while em.dynamite_throws == thrown0 and n < 600:
		await process_frame
		n += 1
	await process_frame
	_save_shot("c00_release")
	# the stick in flight, every 5 frames until it lies down
	var pm = g.projectiles
	var k := 1
	n = 0
	while pm.dynamite_lain == 0 and n < 300:
		await process_frame
		n += 1
		if n % 5 == 0:
			_save_shot("c%02d_flight" % k)
			k += 1
	_save_shot("d00_landed")
	await _wait(0.3)
	_save_shot("d01_fuse_lit")
	await _wait(0.4)
	_save_shot("d02_fuse_out")
	var b0: int = pm.dynamite_blasts
	n = 0
	while pm.dynamite_blasts == b0 and n < 400:
		await process_frame
		n += 1
	await process_frame
	_save_shot("e00_blast")
	for j in range(1, 6):
		await process_frame
		await process_frame
		await process_frame
		_save_shot("e%02d_blast" % j)
	await _wait(0.6)
	_save_shot("f00_after")
	_save.data = _keep
	quit(0)
