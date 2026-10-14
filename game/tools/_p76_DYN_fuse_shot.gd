## Pass 76 (lane DYN) scratch capture: the dynamite's fuse in game, frame by frame from the throw to the blast: the shot
## in flight with its spark, the landing, the shot lying on its side with the spark burning, the spark going out half a
## second before the blast (a wisp of smoke), the blast. Sequences: plain (a standing crowd), sticky (Sticky: the spark
## rides a creature), fith (Fire in the Hole over a packed crowd: the mini crits). Windowed, fixed 60 fps, bounded waits
## and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p76_DYN_fuse_shot.gd -- out=<dir> [look=A|B|C|D] [seq=plain,sticky,fith] [every=3] [frames=170] [zoom=0.55] [level=3]
## Writes <out>/<seq>_f<frame>.png crops (CROP px round the shot) and <out>/<seq>.txt (per frame: the shot's state).
extends SceneTree

const WATCHDOG_S := 150.0
const CROP := 560

var _out := "user://p76_dyn"
var _look := ""
var _seqs: Array = ["plain", "sticky", "fith"]
var _every := 3
var _frames := 170
var _zoom := 0.55
var _level := 3
## dyn=b|c|d: lay that dynamite look's models (lane DYNART's GLBs and tips_<l>.json) over the grenade's params in memory
## for the film (the content is not touched); form=stick|bundle, colour=tan|red pick the model
var _dyn := ""
var _form := "stick"
var _colour := "tan"
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
		elif a.begins_with("dyn="):
			_dyn = a.substr(4)
		elif a.begins_with("form="):
			_form = a.substr(5)
		elif a.begins_with("colour="):
			_colour = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_dyn: WATCHDOG, quitting")
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
	if _look != "":
		if not _save.data.get("item_looks") is Dictionary:
			_save.data["item_looks"] = {}
		_save.data["item_looks"]["lob_grenade"] = _look
		if _reg.has_method("apply_item_looks"):
			_reg.apply_item_looks()
	if _dyn != "":
		_lay_models()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_dyn: no game scene")
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
	print("p76_dyn: done -> ", _out)
	_save.data = keep
	quit(0)


func _film(seq: String) -> void:
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "lob_grenade", _level)
	if seq == "sticky":
		_run.add_mutation("sticky", true)
	elif seq == "fith":
		_run.add_mutation("fire_in_the_hole", true)
	_run.rebuild_sheets()
	await _wait(0.6)
	var b = g._behaviors.get("lob_grenade")
	if b == null:
		print("p76_dyn: no lob_grenade behaviour for ", seq)
		return
	b.cooldown_left = 99.0
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	await _frames_wait(30)
	var here: Vector3 = g.player.global_position
	var centre := here + Vector3(0.8, 0, -6.5)
	var n := 10 if seq == "plain" else (3 if seq == "sticky" else 14)
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var r := 0.0 if k == 0 else (1.1 if seq != "fith" else 0.9 + 0.35 * float(k % 3))
		var i: int = em.spawn("skeleton", centre + Vector3(cos(a), 0, sin(a)) * r, null, 1.0, 400.0)
		if i >= 0 and seq != "sticky":
			em.speed[i] = 0.0
	em._rebuild_grid()
	# (pass 73: they rise out of the sand first; a rising one is no target yet)
	await _frames_wait(70)
	var inst = _run.weapon_instance("lob_grenade")
	var before := {}
	for j in range(pm.MAX):
		if pm.alive[j] == 1:
			before[j] = true
	b.cooldown_left = 1.0 / 60.0
	var log := FileAccess.open(_out.path_join(seq + ".txt"), FileAccess.WRITE)
	log.store_line("seq %s look %s level %d crowd %d" % [seq, _look, _level, n])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var shot := -1
	var last := centre
	var gone_at := -1
	for fr in range(_frames):
		await process_frame
		if shot < 0:
			for j in range(pm.MAX):
				if pm.alive[j] == 1 and not before.has(j) and pm.weapon[j] == inst and (pm.extra[j] as Dictionary).has("fz") and not (pm.extra[j] as Dictionary).has("is_bomblet"):
					shot = j
					break
		var state := "-"
		if shot >= 0 and pm.alive[shot] == 1 and pm.weapon[shot] == inst:
			last = pm.pos[shot]
			var ex: Dictionary = pm.extra[shot]
			state = "lie_t=%.2f" % float(ex["lie_t"]) if ex.has("lie_t") else ("stuck_t=%.2f" % pm.stuck_t[shot] if pm.stuck[shot] >= 0 else "flying")
			state += " lit=%s sparks=%d" % [str(pm.fuse_lit(shot)), pm.sparks_drawn]
		elif shot >= 0 and gone_at < 0:
			gone_at = fr
			state = "BLAST"
		elif gone_at >= 0:
			state = "after"
			if fr - gone_at > 24:
				log.store_line("f%03d %s" % [fr, state])
				break
		log.store_line("f%03d %s pos=%s mass_minis=%d fuses_out=%d" % [fr, state, str(last), int(pm.mass_minis), int(pm.fuses_out)])
		if fr % _every != 0 and state != "BLAST":
			continue
		var img := root.get_viewport().get_texture().get_image()
		if cam:
			var sp: Vector2 = cam.unproject_position(last)
			var x := clampi(int(sp.x) - CROP / 2, 0, img.get_width() - CROP)
			var y := clampi(int(sp.y) - CROP / 2, 0, img.get_height() - CROP)
			img = img.get_region(Rect2i(x, y, CROP, CROP))
		img.save_png(_out.path_join("%s_f%03d.png" % [seq, fr]))
	log.close()
	b.cooldown_left = 99.0
	await _frames_wait(30)


## The dynamite look's models over the grenade's (and Boomtown's over the evolution's) params, in memory only.
func _lay_models() -> void:
	var tips_path := ProjectSettings.globalize_path("res://").path_join("../tools/dl/p76/DYNART/tips_%s.json" % _dyn)
	var tips = JSON.parse_string(FileAccess.get_file_as_string(tips_path))
	if not tips is Dictionary:
		print("p76_dyn: no tips at ", tips_path)
		return
	var models := {}
	for form: String in ["stick", "bundle"]:
		var e: Dictionary = {}
		for colour: String in ["tan", "red"]:
			var key := "%s_%s" % [form, colour]
			if (tips as Dictionary).has(key):
				e[colour] = str(tips[key]["glb"])
				e["tip"] = tips[key]["tip"]
		models[form] = e
	var lg = _reg.weapon("lob_grenade")
	lg.params["models"] = models
	lg.params["model_form"] = _form
	lg.params["model_colour"] = _colour
	if (tips as Dictionary).has("evo"):
		var gp = _reg.weapon("golden_pineapple")
		gp.params["model"] = str(tips["evo"]["glb"])
		gp.params["fuse_tip"] = tips["evo"]["tip"]
	print("p76_dyn: laid look ", _dyn, " models: ", models.keys(), " form ", _form, " colour ", _colour)
