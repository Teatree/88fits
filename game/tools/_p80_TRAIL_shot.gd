## Pass 80 (lane TRAIL) scratch capture: every tracer style on the same shots, frame by frame in the debug arena.
## Sequences: rev (the Revolver at a row of tough skeletons up the screen), silver (with Silver Bullet), tommy (a Tommy Gun
## burst), boom (the Boomstick). For every style in styles= the tracer params of every weapon and mutation are laid over
## in memory (the style; the line keeps the content as it is, the others drop the line's tracer_life and take the widths
## of WIDTHS), then every sequence is filmed.
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p80_TRAIL_shot.gd -- out=<dir> [styles=line,streak,ribbon,wisp,toon] [seq=rev,silver,tommy,boom] [every=2] [frames=60] [crop=800] [col=#hex] [ov=id.key=v|...] [raw=1]
## raw=1 films the content exactly as it is (no style, no widths: the shipped look). Writes <out>/<style>_<seq>_f<frame>.png
## and <out>/<style>_<seq>.txt. Windowed, fixed 60 fps, bounded waits and a watchdog.
extends SceneTree

const WATCHDOG_S := 900.0
## the head widths (m) the candidates are filmed with (the line keeps the content's)
const WIDTHS := {"revolver": 0.2, "silver_bullet": 0.3, "drum_mag": 0.22, "boomstick": 0.12, "blunderbuss": 0.12}

var _out := "user://p80_trail"
var _styles: Array = ["line", "streak", "ribbon", "wisp", "toon"]
var _seqs: Array = ["rev", "silver", "tommy", "boom"]
var _every := 2
var _frames := 60
var _crop := 800
var _col := ""
var _ov := ""
var _raw := false
## shaders=<res path>,... : each run of the styles with that tracer shader in place (files prefixed v<n>_)
var _shaders: Array = []
var _pre := ""
## cols=#hex,... : each run of the styles with the Revolver's tracer in that colour (files prefixed c<n>_)
var _cols: Array = []
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
		elif a.begins_with("styles="):
			_styles = Array(a.substr(7).split(",", false))
		elif a.begins_with("seq="):
			_seqs = Array(a.substr(4).split(",", false))
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("col="):
			_col = a.substr(4)
		elif a.begins_with("ov="):
			_ov = a.substr(3)
		elif a == "raw=1":
			_raw = true
		elif a.begins_with("cols="):
			_cols = Array(a.substr(5).split(",", false))
		elif a.begins_with("shaders="):
			_shaders = Array(a.substr(8).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p80_trail: WATCHDOG, quitting")
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
	_keep_params()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p80_trail: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(1.0)
	var runs: Array = _shaders if not _shaders.is_empty() else [""]
	if not _cols.is_empty():
		runs = _cols
	for n in range(runs.size()):
		if not _cols.is_empty():
			_col = str(runs[n])
			_pre = "c%d_" % n
		elif str(runs[n]) != "":
			g.projectiles._ln_mat.shader = load(str(runs[n]))
			_pre = "v%d_" % n
		for style: String in _styles:
			_lay_style(style)
			for seq: String in _seqs:
				await _film(style, seq)
	print("p80_trail: done -> ", _out)
	_save.data = keep
	quit(0)


func _tracer_defs() -> Array:
	var out: Array = []
	for d in _reg.weapons.values():
		out.append(d)
	for d in _reg.mutations.values():
		out.append(d)
	return out


func _keep_params() -> void:
	for d in _tracer_defs():
		_orig[d] = (d.params as Dictionary).duplicate(true)


func _lay_style(style: String) -> void:
	for d in _tracer_defs():
		d.params = (_orig[d] as Dictionary).duplicate(true)
	if not _raw and style == "line":
		# pass 79's look: the line with the content's own widths and lives
		for d in _tracer_defs():
			for k: String in (d.params as Dictionary).keys():
				if k.begins_with("tracer"):
					d.params["tracer_style"] = "line"
					break
	if not _raw and style != "line":
		for d in _tracer_defs():
			var p: Dictionary = d.params
			var has := false
			for k: String in p.keys():
				if k.begins_with("tracer"):
					has = true
			if not has:
				continue
			p["tracer_style"] = style
			p.erase("tracer_life")
			if WIDTHS.has(d.id):
				p["tracer_width"] = WIDTHS[d.id]
			elif p.has("tracer_width"):
				p.erase("tracer_width")
			if p.get("final") is Dictionary and (p["final"] as Dictionary).has("tracer_width"):
				p["final"]["tracer_width"] = WIDTHS["silver_bullet"]
		if _col != "":
			_reg.weapon("revolver").params["tracer_color"] = _col
	_lay_overrides()


func _weapon_of(seq: String) -> String:
	match seq:
		"rev", "silver":
			return "revolver"
		"tommy":
			return "tommy_gun"
		"boom", "dragon":
			return "boomstick"
		"chicago":
			return "chicago_typewriter"
		"onfire":
			return "basketball"
		"peas":
			return "peashooter"
	return ""


func _film(style: String, seq: String) -> void:
	g.enemies.kill_all(false)
	_run.debug_clear_items()
	var wid := _weapon_of(seq)
	_run.debug_set_item("weapon", wid, 3)
	if seq == "silver":
		_run.add_mutation("silver_bullet", true)
	elif seq == "dragon":
		_run.add_mutation("dragons_breath", true)
	elif seq == "onfire":
		_run.add_mutation("on_fire", true)
	elif seq == "peas":
		_run.add_mutation("toxic_peas", true)
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
	var b = g._behaviors.get(wid)
	if b:
		b.cooldown_left = 99.0
	var crowd: Array = []
	var dist := 4.8 if seq in ["boom", "dragon"] else 8.0
	for k in range(6):
		var s := -2.5 + 5.0 * float(k) / 5.0
		var i: int = em.spawn("skeleton", here + Vector3(s, 0, -dist - 0.7 * float(k % 2)), null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] = 0.0
			crowd.append(i)
	var centre := here + Vector3(0, 0, -4.0)
	em._rebuild_grid()
	for k in range(70):
		var bw = g._behaviors.get(wid)
		if bw:
			bw.cooldown_left = 99.0
		await process_frame
	var log := FileAccess.open(_out.path_join(_pre + "%s_%s.txt" % [style, seq]), FileAccess.WRITE)
	log.store_line("style %s seq %s weapon %s" % [style, seq, wid])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	b = g._behaviors.get(wid)
	if b:
		b.cooldown_left = 1.0 / 60.0
	var fired := 0
	for fr in range(_frames):
		await process_frame
		if b and seq in ["rev", "silver", "boom", "dragon", "onfire", "peas"] and fr in [24, 48] and fired < 2:
			b.cooldown_left = 1.0 / 60.0
			fired += 1
		if b and seq in ["tommy", "chicago"] and fr > 36:
			b.cooldown_left = 99.0
		var line := "f%03d segs=%d live=%d shots=%d" % [fr, int(pm.tracer_segments), int(pm.tracer_live()), int(pm.count)]
		if pm.tracer_segments > 0:
			var k: int = (pm._ln_next - 1 + pm.tracer_from.size()) % pm.tracer_from.size()
			line += " last: style=%d w=%.3f life=%.2f hot=%.2f col=%s" % [pm.tracer_kind[k], pm.tracer_width[k], pm.tracer_life[k], pm.tracer_hot[k], pm.tracer_col[k].to_html()]
		log.store_line(line)
		if fr % _every != 0:
			continue
		var img := root.get_viewport().get_texture().get_image()
		if _crop > 0 and cam:
			var sp: Vector2 = cam.unproject_position(centre)
			var x := clampi(int(sp.x) - _crop / 2, 0, img.get_width() - _crop)
			var y := clampi(int(sp.y) - _crop / 2, 0, img.get_height() - _crop)
			img = img.get_region(Rect2i(x, y, _crop, _crop))
		img.save_png(_out.path_join(_pre + "%s_%s_f%03d.png" % [style, seq, fr]))
	log.close()
	if b:
		b.cooldown_left = 99.0
	await _frames_wait(30)


func _lay_overrides() -> void:
	if _ov == "":
		return
	for item: String in _ov.split("|", false):
		var eq := item.find("=")
		var dot := item.find(".")
		if eq < 0 or dot < 0 or dot > eq:
			continue
		var id := item.substr(0, dot)
		var key := item.substr(dot + 1, eq - dot - 1)
		var val: String = item.substr(eq + 1)
		var v: Variant = float(val) if val.is_valid_float() else val
		var d = _reg.weapon(id)
		if d == null:
			d = _reg.mutation(id)
		if d == null:
			print("p80_trail: no ", id)
			continue
		d.params[key] = v
