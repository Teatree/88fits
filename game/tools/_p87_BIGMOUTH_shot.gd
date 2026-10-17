## Pass 87 lane BIGMOUTH scratch capture: the Big Mouth frame by frame around a shot (the wind-up, the beam leaving, the
## punch back, the settle, the beam's end), in the debug arena with a pack of tough skeletons up the screen. Windowed,
## fixed 60 fps, bounded waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p87_BIGMOUTH_shot.gd -- out=<dir> [weapon=big_mouth] [muts=mouth_burn,mouth_knock] [level=1] [shots=1] [frames=48] [step=1] [zoom=0.5] [crop=460] [full=0] [tag=bm]
## Writes <out>/<tag>_s<shot>_f<frame>.png (crops round the mouth, or the whole frame with full=1), <out>/<tag>_end_*.png
## around the beam's end and <out>/<tag>_frames.txt (per frame: wind-up, beam, punch, jaw, glow, mouth position).
extends SceneTree

const WATCHDOG_S := 120.0

var _out := "user://p87_bm"
var _weapon := "big_mouth"
var _muts: PackedStringArray = []
var _level := 1
var _shots := 1
var _frames := 48
var _step := 1
var _zoom := 0.5
var _crop := 460
var _full := false
var _tag := "bm"
## where the pack stands for each filmed shot: n (up the screen: the mouth shows its back), s (down: its face), e, w
var _dirs: PackedStringArray = ["n"]
## how far from the hero the pack stands (the weapons pick targets on the screen: keep it in view when zoomed in)
var _dist := 6.0
var _run
var _reg
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("weapon="):
			_weapon = a.substr(7)
		elif a.begins_with("muts="):
			_muts = a.substr(5).split(",", false)
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("shots="):
			_shots = int(a.substr(6))
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("step="):
			_step = maxi(int(a.substr(5)), 1)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("full="):
			_full = a.substr(5) == "1"
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("dist="):
			_dist = float(a.substr(5))
		elif a.begins_with("dirs="):
			_dirs = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p87_bm: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames_wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "big_mouth", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p87_bm: no game scene")
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
	for m in _muts:
		_run.debug_set_item("mutation", str(m), 1)
	var def = _reg.weapon(_weapon)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", _weapon, _level)
	_run.build_changed.emit()
	_pack(_dirs[0])
	await _wait(1.0)
	var b = g._behaviors.get(_weapon)
	if b == null:
		print("p87_bm: no behaviour for ", _weapon)
		quit(1)
		return
	var log := FileAccess.open(_out.path_join(_tag + "_frames.txt"), FileAccess.WRITE)
	for s in range(_shots):
		# no pull while it settles; then the next pull in 3 frames, filmed from 2 frames before it
		b.cooldown_left = 99.0
		var guard := 0
		while (float(b.get("_beam_t")) > 0.0 or float(b.get("_windup_t")) > 0.0) and guard < 600:
			await process_frame
			guard += 1
		# a new pack rises out of the ground first (not a target until it is mostly up)
		var dir: String = _dirs[s % _dirs.size()]
		_pack(dir)
		# the mouth held on the side of the hero it films best from (SW firing south: its face; NE firing east: its side;
		# NNE firing north: its back)
		var orbit_deg: float = {"s": 135.0, "e": 315.0, "n": 290.0, "w": 225.0}.get(dir, 0.0)
		for k in range(100):
			b._orbit = deg_to_rad(orbit_deg)
			await process_frame
		b.cooldown_left = 3.0 / 60.0
		for fr in range(_frames):
			await process_frame
			if fr % _step == 0:
				_shot(b, "%s_s%d_f%02d" % [_tag, s, fr])
			_log(log, b, "s%d f%02d" % [s, fr])
		# the beam's end: frames from just before it stops to the settle after
		b.cooldown_left = 99.0
		guard = 0
		while float(b.get("_beam_t")) > 0.1 and guard < 900:
			await process_frame
			guard += 1
		for fr in range(30):
			await process_frame
			if fr % 3 == 0:
				_shot(b, "%s_end_s%d_f%02d" % [_tag, s, fr])
			_log(log, b, "end s%d f%02d" % [s, fr])
	log.close()
	print("p87_bm: done ", _weapon, " ", _muts, " -> ", _out)
	_save.data = keep
	quit(0)


## A pack of tough skeletons `dist` m from the hero, up the screen (n), down it (s: 2 m at most, the hero stands low on
## the screen), right (e) or left (w), standing still.
func _pack(dir: String) -> void:
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	var fwd := Vector3(0, 0, -1)
	if dir == "s":
		fwd = Vector3(0, 0, 1)
	elif dir == "e":
		fwd = Vector3(1, 0, 0)
	elif dir == "w":
		fwd = Vector3(-1, 0, 0)
	var side := Vector3(-fwd.z, 0, fwd.x)
	for k in range(6):
		var s := -2.0 + 4.0 * float(k) / 5.0
		var i: int = em.spawn("skeleton", here + side * s + fwd * ((minf(_dist, 2.0) if dir == "s" else _dist) + 0.6 * float(k % 2)), null, 1.0, 400.0)
		# they stand where they are put, so they never walk in front of the mouth
		if i >= 0:
			em.speed[i] = 0.0
	em._rebuild_grid()


func _shot(b, name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var fam: Node3D = b.get("_familiar")
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if not _full and fam and cam:
		# round the mouth's orbit place, not the mouth: the punch shows as the mouth moving in the frame
		var base = b.get("_fam_base")
		var sp: Vector2 = cam.unproject_position(base if base is Vector3 and base != Vector3.ZERO else fam.global_position)
		# the camera's canvas may be the project's 1080x1920 drawn into a smaller window
		var vs: Vector2 = root.get_viewport().get_visible_rect().size
		if vs.x > 0.0 and vs.y > 0.0:
			sp *= Vector2(float(img.get_width()) / vs.x, float(img.get_height()) / vs.y)
		var c := mini(_crop, mini(img.get_width(), img.get_height()))
		var x := clampi(int(sp.x) - c / 2, 0, img.get_width() - c)
		var y := clampi(int(sp.y) - c / 2, 0, img.get_height() - c)
		img = img.get_region(Rect2i(x, y, c, c))
	img.save_png(_out.path_join(name + ".png"))


func _log(log: FileAccess, b, label: String) -> void:
	var fam: Node3D = b.get("_familiar")
	var jaw: Node3D = b.get("_jaw")
	var model: Node3D = b.get("_model")
	var extra := ""
	if b.has_method("windup_seconds"):
		extra = " windup_s=%.3f punch=%.3f glow=%.3f" % [b.windup_seconds(), b.punch(), b.glow_level()]
	log.store_line("%s windup_t=%.3f beam_t=%.3f jaw=%.1f rot=%s scale=%s fam=%s%s" % [label, float(b.get("_windup_t")), float(b.get("_beam_t")), rad_to_deg(jaw.rotation.x) if jaw else 0.0, str(model.rotation) if model else "", str(model.scale) if model else "", str(fam.global_position) if fam else "", extra])
