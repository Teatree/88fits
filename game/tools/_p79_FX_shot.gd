## Pass 79 (lane FX) scratch capture: the tracers' lines and the bodies a blast throws, frame by frame in the debug
## arena. Sequences:
##   rev     the Revolver's rounds at a row of tough skeletons up the screen (the dark red line, its fade)
##   silver  the same with Silver Bullet (the thicker silver-blue line)
##   tommy   a Tommy Gun burst
##   chicago a Chicago Typewriter burst with Drum Mag
##   dyn     the dynamite thrown at a pack of weak skeletons (the bodies thrown from the blast)
##   keg     a Powder Keg blast in a pack of weak skeletons (Game._powder_keg at the pack's middle)
## Windowed, fixed 60 fps, bounded waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p79_FX_shot.gd -- out=<dir> [seq=rev,silver,tommy,chicago,dyn,keg] [every=2] [frames=90] [zoom=1.0] [crop=0] [hp=0.05]
## Writes <out>/<seq>_f<frame>.png (crop px round the action, 0 = the whole screen) and <out>/<seq>.txt (per frame).
extends SceneTree

const WATCHDOG_S := 200.0

var _out := "user://p79_fx"
var _seqs: Array = ["rev", "silver", "tommy", "chicago", "dyn", "keg"]
var _every := 2
var _frames := 90
var _zoom := 1.0
var _crop := 0
var _hp := 0.05
## ov=<weapon or mutation id>.<param>=<value>|... : params laid over the content in memory for the film (A/B looks)
var _ov := ""
var _run
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("seq="):
			_seqs = Array(a.substr(4).split(",", false))
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("hp="):
			_hp = float(a.substr(3))
		elif a.begins_with("ov="):
			_ov = a.substr(3)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p79_fx: WATCHDOG, quitting")
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
	_lay_overrides()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p79_fx: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(1.0)
	for seq: String in _seqs:
		await _film(seq)
	print("p79_fx: done -> ", _out)
	_save.data = keep
	quit(0)


func _weapon_of(seq: String) -> String:
	match seq:
		"rev", "silver":
			return "revolver"
		"tommy":
			return "tommy_gun"
		"chicago":
			return "chicago_typewriter"
		"dyn":
			return "lob_grenade"
	return ""


func _film(seq: String) -> void:
	g.enemies.kill_all(false)
	_run.debug_clear_items()
	var wid := _weapon_of(seq)
	if wid != "":
		_run.debug_set_item("weapon", wid, 3)
	if seq == "silver":
		_run.add_mutation("silver_bullet", true)
	elif seq == "chicago":
		_run.add_mutation("drum_mag", true)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.6)
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	# nothing of the last sequence left in the air or on the sand (a lying dynamite would blow the next crowd)
	pm.clear_all()
	await _frames_wait(20)
	pm.clear_all()
	var here: Vector3 = g.player.global_position
	var b = g._behaviors.get(wid) if wid != "" else null
	if b:
		b.cooldown_left = 99.0
	var centre := here + Vector3(0.6, 0, -7.0)
	var crowd: Array = []
	if seq in ["rev", "silver", "tommy", "chicago"]:
		for k in range(6):
			var s := -2.5 + 5.0 * float(k) / 5.0
			var i: int = em.spawn("skeleton", here + Vector3(s, 0, -8.0 - 0.7 * float(k % 2)), null, 1.0, 400.0)
			if i >= 0:
				em.speed[i] = 0.0
				crowd.append(i)
		centre = here + Vector3(0, 0, -4.0)
	else:
		var n := 12
		for k in range(n):
			var a := TAU * float(k) / float(n)
			var r := 0.0 if k == 0 else 0.8 + 0.5 * float(k % 3)
			var i: int = em.spawn("skeleton", centre + Vector3(cos(a), 0, sin(a)) * r, null, 1.0, _hp)
			if i >= 0:
				em.speed[i] = 0.0
				crowd.append(i)
	em._rebuild_grid()
	# (they rise out of the sand first; a rising one is no target yet); the weapon held back meanwhile
	for k in range(70):
		var bw = g._behaviors.get(wid) if wid != "" else null
		if bw:
			bw.cooldown_left = 99.0
		await process_frame
	var log := FileAccess.open(_out.path_join(seq + ".txt"), FileAccess.WRITE)
	log.store_line("seq %s weapon %s zoom %.2f" % [seq, wid, _zoom])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var t0_tosses: int = em.corpse_tosses
	var t0_land: int = em.corpse_landings
	# the behaviour as it is now (a rebuild may have made it again)
	b = g._behaviors.get(wid) if wid != "" else null
	if seq == "keg":
		await _frames_wait(4)
		g._powder_keg(centre, 40.0)
	elif b:
		b.cooldown_left = 1.0 / 60.0
	var fired := 0
	for fr in range(_frames):
		await process_frame
		if b and seq in ["rev", "silver"] and fr in [24, 48] and fired < 2:
			b.cooldown_left = 1.0 / 60.0
			fired += 1
		if b and seq in ["tommy", "chicago"] and fr > 40:
			b.cooldown_left = 99.0
		var line := "f%03d segs=%d live=%d tosses=%d landings=%d" % [fr, int(pm.tracer_segments), int(pm.tracer_live()), int(em.corpse_tosses) - t0_tosses, int(em.corpse_landings) - t0_land]
		for i: int in crowd:
			if em.alive[i] == 1 and em.state[i] == em.STATE_DYING:
				line += " | %d dying pos=(%.2f,%.2f) h=%.2f kb=%.2f t=%.2f" % [i, em.pos[i].x, em.pos[i].z, em.lift_h[i], em.kb[i].length(), em.timer[i]]
		log.store_line(line)
		if fr % _every != 0:
			continue
		var img := root.get_viewport().get_texture().get_image()
		if _crop > 0 and cam:
			var sp: Vector2 = cam.unproject_position(centre)
			var x := clampi(int(sp.x) - _crop / 2, 0, img.get_width() - _crop)
			var y := clampi(int(sp.y) - _crop / 2, 0, img.get_height() - _crop)
			img = img.get_region(Rect2i(x, y, _crop, _crop))
		img.save_png(_out.path_join("%s_f%03d.png" % [seq, fr]))
	log.close()
	if b:
		b.cooldown_left = 99.0
	await _frames_wait(30)


func _lay_overrides() -> void:
	if _ov == "":
		return
	var reg = root.get_node("Registry")
	for item: String in _ov.split("|", false):
		var eq := item.find("=")
		var dot := item.find(".")
		if eq < 0 or dot < 0 or dot > eq:
			continue
		var id := item.substr(0, dot)
		var key := item.substr(dot + 1, eq - dot - 1)
		var val: String = item.substr(eq + 1)
		var v: Variant = float(val) if val.is_valid_float() else val
		var d = reg.weapon(id)
		if d == null:
			d = reg.mutation(id)
		if d == null:
			print("p79_fx: no ", id)
			continue
		d.params[key] = v
		print("p79_fx: ", id, ".", key, " = ", v)
