## Pass 75 scratch capture: the Revolver's companion gun frame by frame around its shots (the kick, the settle, the
## spin), in the debug arena with a pack of tough skeletons up the screen. Windowed, fixed 60 fps, bounded waits and a
## watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p75_revolver_shot.gd -- out=<dir> [level=1] [shots=4] [frames=40] [force_spin=0] [zoom=0.5]
## Writes <out>/s<shot>_f<frame>.png crops (420 px round the gun) and <out>/frames.txt (per frame: recoil, spin, yaw).
extends SceneTree

const WATCHDOG_S := 90.0
const CROP := 420

var _out := "user://p75_rev"
var _level := 1
var _shots := 4
var _frames := 40
var _force_spin := false
var _zoom := 0.5
var _run
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("shots="):
			_shots = int(a.substr(6))
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("force_spin="):
			_force_spin = a.substr(11) == "1"
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p75_rev: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames_wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": _level, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p75_rev: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(1.0)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "revolver", _level)
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	for k in range(6):
		var s := -2.0 + 4.0 * float(k) / 5.0
		em.spawn("skeleton", here + Vector3(s, 0, -7.0 - 0.6 * float(k % 2)), null, 1.0, 400.0)
	em._rebuild_grid()
	await _wait(1.5)
	var b = g._behaviors.get("revolver")
	if b == null:
		print("p75_rev: no revolver behaviour")
		quit(1)
		return
	var log := FileAccess.open(_out.path_join("frames.txt"), FileAccess.WRITE)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	for s in range(_shots):
		# the next pull in 3 frames; the frames from 2 before it
		b.cooldown_left = 3.0 / 60.0
		if _force_spin and b.has_method("debug_force_spin"):
			b.debug_force_spin()
		for fr in range(_frames):
			await process_frame
			var fam: Node3D = b.get("_familiar")
			var img := root.get_viewport().get_texture().get_image()
			if fam and cam:
				var sp: Vector2 = cam.unproject_position(fam.global_position)
				var x := clampi(int(sp.x) - CROP / 2, 0, img.get_width() - CROP)
				var y := clampi(int(sp.y) - CROP / 2, 0, img.get_height() - CROP)
				img = img.get_region(Rect2i(x, y, CROP, CROP))
			img.save_png(_out.path_join("s%d_f%02d.png" % [s, fr]))
			var spin = b.get("_spin_t")
			log.store_line("s%d f%02d recoil=%.3f spin=%s yaw=%.3f rotx=%.3f scale=%s" % [s, fr, float(b.get("_recoil")), str(spin), float(b.get("_aim_yaw")), fam.rotation.x if fam else 0.0, str(fam.scale) if fam else ""])
		# let it settle between the filmed pulls
		b.cooldown_left = 99.0
		await _frames_wait(20)
	log.close()
	print("p75_rev: done, ", _shots, " shots x ", _frames, " frames -> ", _out)
	_save.data = keep
	quit(0)
