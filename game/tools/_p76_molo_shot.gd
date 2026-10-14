## Pass 76 (lane MOLO) scratch capture: a fire bottle thrown, flying, landing and burning, frame by frame, in the debug
## arena at a pack of tough, still skeletons. Windowed, fixed 60 fps, bounded waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p76_molo_shot.gd --
##     out=<dir> [weapon=molotov] [level=3] [muts=methanol,oil_slick] [look=B] [frames=150] [every=2] [zoom=1.0]
##     [dx=4] [dz=-7] [crop=420] [full=10] [tag=] [shots=1] [params=<json laid over the weapon's params>]
##     [visual=<res:// .tscn the weapon is drawn with>]
## Writes <out>/<tag>s<shot>_f<frame>.png crops round the shot (then round where it landed), half-size full frames every
## `full` captured frames (<out>/<tag>full_s<shot>_f<frame>.png) and <out>/<tag>frames.txt (per frame: the shot's
## position, its spin, whether it is alive, the flames in the effect pool).
extends SceneTree

const WATCHDOG_S := 150.0

var _out := "user://p76_molo"
var _weapon := "molotov"
var _level := 3
var _muts: Array = []
var _look := ""
var _frames := 150
var _every := 2
var _zoom := 1.0
var _dx := 4.0
var _dz := -7.0
var _crop := 420
var _full := 10
var _tag := ""
var _shots := 1
var _params := {}
var _visual := ""
var _run
var _save
var _reg
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("weapon="):
			_weapon = a.substr(7)
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("muts="):
			for m in a.substr(5).split(",", false):
				_muts.append(m)
		elif a.begins_with("look="):
			_look = a.substr(5)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("dx="):
			_dx = float(a.substr(3))
		elif a.begins_with("dz="):
			_dz = float(a.substr(3))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("full="):
			_full = int(a.substr(5))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("shots="):
			_shots = maxi(int(a.substr(6)), 1)
		elif a.begins_with("visual="):
			_visual = a.substr(7)
		elif a.begins_with("params="):
			var p = JSON.parse_string(a.substr(7))
			if p is Dictionary:
				_params = p
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_molo: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames_wait(n: int) -> void:
	for i in range(n):
		await process_frame


## The live lobbed shot of the weapon, -1 when none flies.
func _shot_index(pm) -> int:
	for i in range(pm.alive.size()):
		if pm.alive[i] == 0 or pm.arc[i] != 1 or pm.hostile[i] != 0:
			continue
		var w = pm.weapon[i]
		if w and w.def.id == _weapon and not (pm.extra[i] as Dictionary).has("is_bomblet"):
			return i
	return -1


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	# a look to play (pass 76, LOOKS' engine) or params laid over the weapon's own, for this process only
	var wd = _reg.weapon(_weapon)
	if wd == null:
		print("p76_molo: no weapon ", _weapon)
		quit(1)
		return
	if not _params.is_empty():
		for k in _params.keys():
			wd.params[k] = _params[k]
	if _visual != "":
		wd.visual = load(_visual)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": _weapon, "level": _level, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_molo: no game scene")
		quit(1)
		return
	if _look != "" and _save.data is Dictionary:
		var fam: String = wd.evolved_from if wd.is_evolution and wd.evolved_from != "" else wd.id
		var il = _save.data.get("item_looks", {})
		if not il is Dictionary:
			il = {}
		il[fam] = _look
		_save.data["item_looks"] = il
		if _reg.has_method("apply_item_looks"):
			_reg.apply_item_looks()
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(1.0)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", _weapon, _level)
	for m: String in _muts:
		_run.debug_set_item("mutation", m, 1)
	_run.build_changed.emit()
	await process_frame
	var b = g._behaviors.get(_weapon)
	if b == null:
		print("p76_molo: no behaviour for ", _weapon, "; have ", g._behaviors.keys())
		quit(1)
		return
	# no throw before the filmed one: the pack must not be burning already
	b.cooldown_left = 99.0
	var em = g.enemies
	em.kill_all(false)
	g.projectiles.clear_all()
	for c in g.find_children("*", "ElementCloud", true, false):
		c.queue_free()
	await _frames_wait(40)
	var here: Vector3 = g.player.global_position
	var centre := here + Vector3(_dx, 0, _dz)
	for k in range(7):
		var a := TAU * float(k) / 7.0
		var at := centre + Vector3(cos(a), 0, sin(a)) * (0.9 if k > 0 else 0.0)
		var e: int = em.spawn("skeleton", at, null, 1.0, 400.0)
		if e >= 0:
			em.speed[e] = 0.0
	em._rebuild_grid()
	await _wait(1.0)
	b.cooldown_left = 99.0
	await _frames_wait(10)
	var pm = g.projectiles
	var log := FileAccess.open(_out.path_join(_tag + "frames.txt"), FileAccess.WRITE)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	for s in range(_shots):
		var fired0: int = pm.lobs_fired
		b.cooldown_left = 2.0 / 60.0
		var last := centre
		var shot := -1
		var captured := 0
		for fr in range(_frames):
			await process_frame
			if pm.lobs_fired > fired0:
				b.cooldown_left = 99.0
			var j := _shot_index(pm)
			if j >= 0:
				shot = j
				last = pm.pos[j]
			if fr % _every != 0:
				continue
			var img := root.get_viewport().get_texture().get_image()
			var fname := "%ss%d_f%03d" % [_tag, s, fr]
			if _full > 0 and captured % _full == 0:
				var half := img.duplicate() as Image
				half.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				half.save_png(_out.path_join("%sfull_s%d_f%03d.png" % [_tag, s, fr]))
			if cam:
				var sp: Vector2 = cam.unproject_position(last)
				var x := clampi(int(sp.x) - _crop / 2, 0, img.get_width() - _crop)
				var y := clampi(int(sp.y) - _crop / 2, 0, img.get_height() - _crop)
				img.get_region(Rect2i(x, y, _crop, _crop)).save_png(_out.path_join(fname + ".png"))
			captured += 1
			var fx = g.get("fx")
			var nflames := 0
			if fx and fx.get("_flame_mm"):
				nflames = int(fx._flame_mm.visible_instance_count)
			log.store_line("%s alive=%d pos=%s spin=%.2f flames=%d" % [fname, 1 if j >= 0 else 0, str(last), pm.spin[shot] if shot >= 0 else 0.0, nflames])
		b.cooldown_left = 99.0
		await _frames_wait(20)
	log.close()
	print("p76_molo: done -> ", _out)
	_save.data = keep
	# the game goes before the tree does (a quit mid-frame sometimes crashed on the way out)
	g.queue_free()
	await _frames_wait(3)
	quit(0)
