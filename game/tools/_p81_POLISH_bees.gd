## Pass 81 (lane POLISH) scratch capture: the Killer Bees' trail looks, frame by frame in the debug arena.
## For every look in looks= (ProjectileManager.BEE_LOOKS names, or "beads" for pass 49's) the Killer Bees' missile params
## take that trail_style in memory, then every sequence is filmed: row (a row of tough skeletons up the screen), ring
## (skeletons round the hero, so the bees swirl out to every side), red (the row with Pollen's buff on: the red bees).
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p81_POLISH_bees.gd -- out=<dir> [looks=dash,buzz,zip,beads] [seq=row,ring] [every=2] [frames=70] [crop=800] [level=5] [weapon=hornet_nest]
## Writes <out>/<look>_<seq>_f<frame>.png and <out>/<look>_<seq>.txt. Windowed, fixed 60 fps, bounded waits and a watchdog.
extends SceneTree

const WATCHDOG_S := 600.0

var _out := "user://p81_bees"
var _looks: Array = ["dash", "buzz", "zip", "beads"]
var _seqs: Array = ["row", "ring"]
var _every := 2
var _frames := 70
var _crop := 800
var _level := 5
var _weapon := "hornet_nest"
var _run
var _save
var _reg
var g
var _t0 := 0
var _orig := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("looks="):
			_looks = Array(a.substr(6).split(",", false))
		elif a.begins_with("seq="):
			_seqs = Array(a.substr(4).split(",", false))
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("weapon="):
			_weapon = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p81_bees: WATCHDOG, quitting")
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
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	var d = _reg.weapon(_weapon)
	if d == null:
		print("p81_bees: no weapon ", _weapon)
		quit(1)
		return
	_orig = (d.params as Dictionary).duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p81_bees: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(1.0)
	for look: String in _looks:
		var p: Dictionary = _orig.duplicate(true)
		if p.get("missile") is Dictionary:
			p["missile"]["trail_style"] = look
		d.params = p
		for seq: String in _seqs:
			await _film(look, seq)
	d.params = _orig
	print("p81_bees: done -> ", _out)
	_save.data = keep
	quit(0)


func _film(look: String, seq: String) -> void:
	# a Pollen buff a red sequence gave is over before the next sequence
	for tb in _run.timed:
		if str(tb["id"]).begins_with("pollen:"):
			tb["until"] = -1.0
	g.enemies.kill_all(false)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", _weapon, _level)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.5)
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	pm.clear_all()
	await _frames_wait(20)
	pm.clear_all()
	var here: Vector3 = g.player.global_position
	var b = g._behaviors.get(_weapon)
	if b:
		b.cooldown_left = 99.0
	var centre := here + Vector3(0, 0, -3.5)
	if seq == "ring":
		centre = here + Vector3(0, 0, -1.0)
		for k in range(8):
			var a := TAU * float(k) / 8.0 + 0.3
			var i: int = em.spawn("skeleton", here + Vector3(cos(a) * 6.5, 0, sin(a) * 6.5 - 1.0), null, 1.0, 400.0)
			if i >= 0:
				em.speed[i] = 0.0
	else:
		for k in range(6):
			var s := -3.0 + 6.0 * float(k) / 5.0
			var i: int = em.spawn("skeleton", here + Vector3(s, 0, -8.0 - 0.8 * float(k % 2)), null, 1.0, 400.0)
			if i >= 0:
				em.speed[i] = 0.0
	if seq == "red" and b and b.inst:
		# Pollen's buff on: the bees fly red (MissilePod.pollen_on reads the boost)
		_run.add_timed_effects("pollen:" + str(b.inst.def.id), "Pollen", [], 30.0, true)
	em._rebuild_grid()
	for k in range(60):
		var bw = g._behaviors.get(_weapon)
		if bw:
			bw.cooldown_left = 99.0
		await process_frame
	var log := FileAccess.open(_out.path_join("%s_%s.txt" % [look, seq]), FileAccess.WRITE)
	log.store_line("look %s seq %s weapon %s level %d" % [look, seq, _weapon, _level])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	b = g._behaviors.get(_weapon)
	if b:
		b.cooldown_left = 1.0 / 60.0
	var fired := 0
	for fr in range(_frames):
		await process_frame
		if b and fr == 40 and fired < 1:
			b.cooldown_left = 1.0 / 60.0
			fired += 1
		elif b and fr > 0 and fr != 40:
			b.cooldown_left = maxf(b.cooldown_left, 0.5)
		log.store_line("f%03d bee_segs=%d live=%d shots=%d" % [fr, int(pm.bee_segments), int(pm.tracer_live()), int(pm.count)])
		if fr % _every != 0:
			continue
		var img := root.get_viewport().get_texture().get_image()
		if _crop > 0 and cam:
			var sp: Vector2 = cam.unproject_position(centre)
			var x := clampi(int(sp.x) - _crop / 2, 0, img.get_width() - _crop)
			var y := clampi(int(sp.y) - _crop / 2, 0, img.get_height() - _crop)
			img = img.get_region(Rect2i(x, y, _crop, _crop))
		img.save_png(_out.path_join("%s_%s_f%03d.png" % [look, seq, fr]))
	log.close()
	if b:
		b.cooldown_left = 99.0
	await _frames_wait(30)
