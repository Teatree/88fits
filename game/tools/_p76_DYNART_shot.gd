## Pass 76 (lane DYNART) scratch capture: one dynamite look in game, frame by frame from the throw to the blast, for
## every model of the family: the plain stick (tan), Coffin Nails (red), the Dynamite Bundle (tan), the bundle with Coffin
## Nails (red), Sticky riding a creature (the stick's own paper, its spark alone), Boomtown riding the strongest creature
## (and its small copies, the bomblets), and Boomtown lying where no creature waits. Windowed, fixed 60 fps, bounded
## waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p76_DYNART_shot.gd -- out=<dir> look=B [seq=stick,red,bundle,bundle_red,sticky,evo,evo_lie] [every=3] [frames=200] [zoom=0.6] [level=3]
## Writes <out>/<seq>_f<frame>.png crops (CROP px round the shot), <out>/<seq>_full_f<frame>.png half-size whole frames
## at the throw, the landing and the blast, and <out>/<seq>.txt (per frame: the shot's state and the spark).
extends SceneTree

const WATCHDOG_S := 170.0
const CROP := 520

var _out := "user://p76_dynart"
var _look := "B"
var _seqs: Array = ["stick", "red", "bundle", "bundle_red", "sticky", "evo", "evo_lie"]
var _every := 3
var _frames := 200
var _zoom := 0.6
var _level := 3
var _run
var _save
var _reg
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("look="):
			_look = a.substr(5)
		elif a.begins_with("seq="):
			_seqs = Array(a.substr(4).split(",", false))
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("level="):
			_level = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_dynart: WATCHDOG, quitting")
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
	if not _save.data.get("item_looks") is Dictionary:
		_save.data["item_looks"] = {}
	_save.data["item_looks"]["lob_grenade"] = _look
	if _reg.has_method("apply_item_looks"):
		_reg.apply_item_looks()
	print("p76_dynart: look ", _look, " plays ", _reg.played_item_look("lob_grenade") if _reg.has_method("played_item_look") else "?",
		" weapon '", _reg.weapon("lob_grenade").display_name, "' evo '", _reg.weapon("golden_pineapple").display_name, "'")
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_dynart: no game scene")
		_save.data = keep
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
	print("p76_dynart: done -> ", _out)
	_save.data = keep
	quit(0)


func _film(seq: String) -> void:
	var evo := seq.begins_with("evo")
	var wid := "golden_pineapple" if evo else "lob_grenade"
	_run.debug_clear_items()
	var muts: Array = []
	match seq:
		"red":
			muts = ["frag"]
		"bundle":
			muts = ["new_equipment"]
		"bundle_red":
			muts = ["new_equipment", "frag"]
		"sticky":
			muts = ["sticky"]
		"evo", "evo_lie":
			muts = ["new_equipment", "frag", "sticky"]
	for m: String in muts:
		_run.debug_set_item("mutation", m, 1)
	if evo:
		_run.debug_set_item("evolution", wid, 1)
	else:
		_run.debug_set_item("weapon", wid, _level)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.6)
	var b = g._behaviors.get(wid)
	if b == null:
		print("p76_dynart: no behaviour for ", wid, " in ", seq, "; have ", g._behaviors.keys())
		return
	b.cooldown_left = 99.0
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	pm.clear_all()
	await _frames_wait(30)
	var here: Vector3 = g.player.global_position
	var centre := here + Vector3(0.8, 0, -6.5)
	var n := 3 if seq == "sticky" else 10
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var r := 0.0 if k == 0 else 1.1
		var i: int = em.spawn("skeleton", centre + Vector3(cos(a), 0, sin(a)) * r, null, 1.0, 400.0)
		if i >= 0 and seq != "sticky":
			em.speed[i] = 0.0
	em._rebuild_grid()
	# (pass 73: they rise out of the sand first; a rising one is no target yet)
	await _frames_wait(70)
	var inst = _run.weapon_instance(wid)
	var model_path := str(b.call("model_path")) if b.has_method("model_path") else "?"
	var before := {}
	for j in range(pm.MAX):
		if pm.alive[j] == 1:
			before[j] = true
	b.cooldown_left = 1.0 / 60.0
	var log := FileAccess.open(_out.path_join(seq + ".txt"), FileAccess.WRITE)
	log.store_line("seq %s look %s weapon %s (%s) model %s mutations %s" % [seq, _look, wid, inst.def.display_name if inst else "?", model_path, str(muts)])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var shot := -1
	var last := centre
	var gone_at := -1
	var landed := false
	var killed := false
	for fr in range(_frames):
		await process_frame
		if shot < 0:
			for j in range(pm.MAX):
				if pm.alive[j] == 1 and not before.has(j) and pm.weapon[j] == inst and (pm.extra[j] as Dictionary).has("fz") and not (pm.extra[j] as Dictionary).has("is_bomblet"):
					shot = j
					b.cooldown_left = 99.0
					break
		var state := "-"
		var full := false
		# (a freed slot may be taken by one of the shot's own nails: only a shot with a fuse is ours)
		if shot >= 0 and pm.alive[shot] == 1 and pm.weapon[shot] == inst and (pm.extra[shot] as Dictionary).has("fz") and gone_at < 0:
			last = pm.pos[shot]
			var ex: Dictionary = pm.extra[shot]
			if ex.has("lie_t"):
				state = "lie_t=%.2f" % float(ex["lie_t"])
				if not landed:
					landed = true
					full = true
			elif pm.stuck[shot] >= 0:
				state = "stuck_t=%.2f" % pm.stuck_t[shot]
				if not landed:
					landed = true
					full = true
			else:
				state = "flying vy=%.1f" % pm.vel[shot].y
				# Boomtown lying: the crowd goes as the shot comes down, so nothing is in reach to stick to
				if seq == "evo_lie" and not killed and pm.vel[shot].y < -2.0:
					em.kill_all(false)
					killed = true
			state += " lit=%s sparks=%d" % [str(pm.fuse_lit(shot)) if pm.has_method("fuse_lit") else "?", int(pm.get("sparks_drawn")) if pm.get("sparks_drawn") != null else -1]
		elif shot >= 0 and gone_at < 0:
			gone_at = fr
			state = "BLAST"
			full = true
		elif gone_at >= 0:
			state = "after"
			if fr - gone_at > 36:
				log.store_line("f%03d %s" % [fr, state])
				break
		if fr == 4:
			full = true
		log.store_line("f%03d %s pos=%s" % [fr, state, str(last)])
		var img := root.get_viewport().get_texture().get_image()
		if full:
			var half := img.duplicate() as Image
			half.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
			half.save_png(_out.path_join("%s_full_f%03d.png" % [seq, fr]))
		if fr % _every != 0 and state != "BLAST":
			continue
		if cam:
			var sp: Vector2 = cam.unproject_position(last)
			var x := clampi(int(sp.x) - CROP / 2, 0, img.get_width() - CROP)
			var y := clampi(int(sp.y) - CROP / 2, 0, img.get_height() - CROP)
			img = img.get_region(Rect2i(x, y, CROP, CROP))
		img.save_png(_out.path_join("%s_f%03d.png" % [seq, fr]))
	log.close()
	b.cooldown_left = 99.0
	await _frames_wait(40)
