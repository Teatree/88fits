## Pass 101, lane CROWD: the proof that drawing only the creatures on the screen changes no pixel (Garry was promised "a
## test that renders the same busy frames with every creature drawn and with only the on-screen ones, and compares them
## pixel by pixel; any difference fails"). Windowed. At each capture the frame is drawn three times in a row with
## RenderingServer.force_draw(false, 0.0) (no time passes: TIME, particles and every node stay as they are): every
## creature drawn (EnemyManager.drawn_vis all 1), only the drawn ones (the game's own flags, as its ticks left them), and
## every creature again (the control: it must equal the first). Before the three the camera takes one more step of its
## own update, so it is a frame newer than the flags, as when the game draws. The scenes, one after another:
##   crowd   300 of stage 3's mix, 4..34 m round the hero walking an S (play zoom)
##   zoom    the same at zoom 1.6 and 2.4 (the far zoom)
##   edges   big creatures, Elites (crowns), a gear special and a boss (skull) parked with their feet at offsets across each
##           screen edge, from inside to well outside (the bottom edge: feet below, bodies reaching up into it)
##   walkin  the same creatures walking in across the edges
##   corpses creatures at the edges killed with big hits thrown in and out across them
##   rising  creatures rising out of the sand at the edges (the map's spawn rise, 1.5 s, 2.5 s for big ones)
##   pan     the crowd again with the hero running straight one way (the camera moving)
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p101_CROWD_pixels.gd -- out=D:/_projects/88fits/tools/dl/p101/CROWD/pixels_a [tag=a]
## Writes <out>/pixels.txt (a line a capture: alive, culled, differing pixels against the control) and PNGs: the first
## capture of each scene (all drawn and culled), and any capture that differs with a diff mask. Exit 0 when no capture
## differed and every control matched, 1 otherwise. Bounded: a frame cap (36000) and a 600 s wall watchdog.
extends SceneTree

const MIX := [["skeleton", 4], ["skeleton_knight", 3], ["hellhound", 3], ["imp", 3], ["dust_mummy", 2], ["fire_ant", 2],
	["horned_toad", 2], ["dust_shaman", 1], ["werewolf", 1], ["armadillo", 1], ["buckshot_dwarf", 1], ["hammer_giant", 1],
	["bull_beetle", 1], ["spit_cactus", 1]]
const BIGS := ["hammer_giant", "stone_golem", "bull_beetle", "rocketeer", "dust_mummy", "skeleton_knight", "harpoon_troglodyte", "sun_prophet"]

var _out := "D:/_projects/88fits/tools/dl/p101/CROWD/pixels_a"
var _game: Node
var _run: Node
var _C: Dictionary = {}
var _frames := 0
var _wall0 := 0
var _rng := RandomNumberGenerator.new()
var _pool: Array = []
var _lines: Array = []
var _fails := 0
var _ctrl_fails := 0
var _captures := 0
var _culled_total := 0
var _viol_total := 0
var _feet_total := 0
var _feet_caps := 0
var _scenes: Array = []
var _si := -1
var _sf := 0
var _walk_t := 0.0
var _run_dir := Vector2.ZERO


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	_rng.seed = 101
	for m in MIX:
		for k in range(int(m[1])):
			_pool.append(m[0])
	# [name, frames, capture every, first capture at]
	_scenes = [["crowd", 200, 15, 30], ["zoom16", 120, 15, 30], ["zoom24", 120, 15, 30], ["edges", 120, 10, 20],
		["walkin", 150, 6, 6], ["corpses", 100, 3, 3], ["rising", 170, 5, 2], ["pan", 200, 8, 20]]
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_wall0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(_out)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames > 36000 or Time.get_ticks_msec() - _wall0 > 600000:
		_log("watchdog: stopped at frame %d" % _frames)
		_finish()
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null or g.get("director") == null:
			return
		_game = g
		_game.player.god = true
		_C = _game.enemies.get_script().get_script_constant_map()
		var d = _game.director
		d.running = false
		_run.stage = 2
		_run.elapsed = float(d.timeline.stage_start(2)) + float(d.timeline.stage_len(2)) / 3.0
		d._apply_mults()
		var look = load("res://core/systems/StageLook.gd").of(_game)
		look.stage = -1
		look.show_stage(2, 0.0)
		_run.debug_clear_items()
		_run.rebuild_sheets()
		_game.enemies.kill_all(false)
		_log("setup: window %s, renderer %s" % [str(root.get_visible_rect().size), RenderingServer.get_current_rendering_method()])
		return
	_keep_playing()
	if _si < 0:
		if _frames > 90:
			_next_scene()
		return
	var sc: Array = _scenes[_si]
	_sf += 1
	_scene_frame(str(sc[0]))
	if _sf >= int(sc[3]) and (_sf - int(sc[3])) % int(sc[2]) == 0:
		_capture(str(sc[0]))
	if _sf >= int(sc[1]):
		_next_scene()


func _next_scene() -> void:
	_si += 1
	_sf = 0
	if _si >= _scenes.size():
		_finish()
		return
	var name := str(_scenes[_si][0])
	var em = _game.enemies
	var cam = _game.camera
	cam.zoom_override = 0.0
	_run_dir = Vector2.ZERO
	em.set_spawn_rise(0.0, 0.0, 0.7, 1.0)
	match name:
		"crowd", "pan":
			em.kill_all(false)
			_fill_crowd(300, 4.0, 34.0)
			if name == "pan":
				_run_dir = Vector2(1, -0.6).normalized()
		"zoom16":
			cam.zoom_override = 1.6
		"zoom24":
			cam.zoom_override = 2.4
		"edges", "walkin":
			em.kill_all(false)
			_game.player.global_position = Vector3(0, _game.player.global_position.y, 0)
			cam.snap_to(_game.player)
			_park_edges(name == "edges")
		"corpses":
			em.kill_all(false)
			_park_edges(true)
			_sf = 0
		"rising":
			em.kill_all(false)
			em.set_spawn_rise(1.5, 2.5, 0.7, 1.0)
			_park_edges(true)
	_log("scene %s" % name)


func _keep_playing() -> void:
	_close_modals()
	var inp = _game.player.input
	if inp == null or _game.paused:
		return
	var name := str(_scenes[_si][0]) if _si >= 0 and _si < _scenes.size() else ""
	if name in ["crowd", "zoom16", "zoom24"]:
		_walk_t += 1.0 / 60.0
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_walk_t * 0.5) * 90.0, -110.0 * (1.0 if fmod(_walk_t, 20.0) < 10.0 else -1.0))
	elif name == "pan":
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + _run_dir * 140.0
	else:
		inp.wants_move = false
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])


func _scene_frame(name: String) -> void:
	var em = _game.enemies
	if name == "corpses" and _sf == 2:
		# every one of them killed by a big hit, half thrown out of the screen and half into it
		var hp: Vector3 = _game.player.global_position
		var k := 0
		for i in range(_C["MAX"]):
			if em.alive[i] == 1 and em.state[i] != _C["STATE_DYING"]:
				var d: Vector3 = em.pos[i] - hp
				d.y = 0.0
				var dir := d.normalized() if d.length() > 0.1 else Vector3.RIGHT
				if k % 2 == 1:
					dir = -dir
				em.damage(i, 1.0e9, "", dir, 22.0 + 6.0 * float(k % 3))
				k += 1
	if name == "crowd" or name == "pan":
		var n: int = em.count_alive
		if n < 300:
			_fill_crowd(300 - n, 14.0, 34.0)


func _fill_crowd(n: int, r0: float, r1: float) -> void:
	var em = _game.enemies
	var hp: Vector3 = _game.player.global_position
	for k in range(mini(n, 40)):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r0, r1)
		em.spawn(str(_pool[_rng.randi() % _pool.size()]), hp + Vector3(cos(a) * r, 0, sin(a) * r), null, 1.0, 2.5)


## The ground point under a screen point (pixels), on the map's ground.
func _ground_at(sp: Vector2) -> Vector3:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var o := cam.project_ray_origin(sp)
	var dv := cam.project_ray_normal(sp)
	var h: float = _game.player.global_position.y
	var p := o
	for it in range(4):
		if absf(dv.y) < 0.001:
			break
		var tt := (h - o.y) / dv.y
		p = o + dv * tt
		h = _game.map.height_at(p.x, p.z)
	return Vector3(p.x, h, p.z)


## Big creatures, Elites, a gear special and a boss with their feet at offsets across each screen edge (`still`: they stand).
func _park_edges(still: bool) -> void:
	var em = _game.enemies
	var vr := root.get_visible_rect().size
	var elites: Array = root.get_node("Registry").elites_list()
	var offs := [-0.06, -0.02, 0.0, 0.02, 0.05, 0.1, 0.18, 0.3]
	var k := 0
	for edge in ["bottom", "top", "left", "right"]:
		for oi in range(offs.size()):
			var o: float = offs[oi]
			var along := 0.12 + 0.76 * float(oi) / float(offs.size() - 1)
			var sp := Vector2.ZERO
			match edge:
				"bottom": sp = Vector2(vr.x * along, vr.y * (1.0 + o))
				"top": sp = Vector2(vr.x * along, -vr.y * o)
				"left": sp = Vector2(-vr.x * o * 2.0, vr.y * along)
				"right": sp = Vector2(vr.x * (1.0 + o * 2.0), vr.y * along)
			var at := _ground_at(sp)
			var id: String = BIGS[k % BIGS.size()]
			var el = elites[k % elites.size()] if (k % 3 == 1 and not elites.is_empty()) else null
			var i: int = em.spawn(id, at, el, 1.0, 50.0)
			if i >= 0 and still:
				em.speed[i] = 0.0
			k += 1
	# a boss with its feet below the bottom edge, one in the middle of the left edge
	var b1: int = em.spawn_boss("gila_grande", _ground_at(Vector2(vr.x * 0.5, vr.y * 1.08)))
	var b2: int = em.spawn("tumbleweed_king", _ground_at(Vector2(-vr.x * 0.12, vr.y * 0.5)), null, 1.0, 50.0)
	for b in [b1, b2]:
		if b >= 0 and still:
			em.speed[b] = 0.0
			em.atk_t[b] = 999.0


func _capture(scene: String) -> void:
	var em = _game.enemies
	var cam = _game.camera
	# the camera a frame newer than the flags, as the game draws it
	if cam.has_method("_update"):
		cam._update(root.get_process_delta_time())
	var keep: PackedByteArray = em.drawn_vis.duplicate()
	var alive := 0
	var culled := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and em.hidden[i] == 0:
			alive += 1
			if keep[i] == 0:
				culled += 1
	em.drawn_vis.fill(1)
	em._render()
	var viol := _bounds_violations()
	RenderingServer.force_draw(false, 0.0)
	var a: Image = root.get_texture().get_image()
	em.drawn_vis = keep.duplicate()
	em._render()
	RenderingServer.force_draw(false, 0.0)
	var b: Image = root.get_texture().get_image()
	em.drawn_vis.fill(1)
	em._render()
	RenderingServer.force_draw(false, 0.0)
	var a2: Image = root.get_texture().get_image()
	# the negative control: culled by the weapons' screen flags instead (`onscreen`: the feet a metre past the screen),
	# which must show the bodies it would wrongly drop at the edges (reported, never a failure)
	var feet: PackedByteArray = em.onscreen.duplicate()
	em.drawn_vis = feet
	em._render()
	RenderingServer.force_draw(false, 0.0)
	var f_img: Image = root.get_texture().get_image()
	var feet_diff := _count_diff(a, f_img) if a.get_data() != f_img.get_data() else 0
	_feet_total += feet_diff
	if feet_diff > 0:
		_feet_caps += 1
	em.drawn_vis = keep
	em._render()
	_captures += 1
	_culled_total += culled
	var diff := _count_diff(a, b) if a.get_data() != b.get_data() else 0
	var ctrl := _count_diff(a, a2) if a.get_data() != a2.get_data() else 0
	var tag := "%02d_%s_%03d" % [_si, scene, _sf]
	_viol_total += viol
	_log("%s: alive %d, culled %d, drawn %d | differing pixels %d | control %d | quads outside their bounds %d | (feet rule: %d pixels)" % [tag, alive, culled, alive - culled, diff, ctrl, viol, feet_diff])
	if diff > 0:
		_fails += 1
		a.save_png(_out + "/%s_all.png" % tag)
		b.save_png(_out + "/%s_culled.png" % tag)
		_diff_mask(a, b).save_png(_out + "/%s_diff.png" % tag)
	if ctrl > 0:
		_ctrl_fails += 1
		a2.save_png(_out + "/%s_control.png" % tag)
	var first: bool = _sf == int(_scenes[_si][3])
	if first:
		a.save_png(_out + "/%s_all.png" % tag)
		b.save_png(_out + "/%s_culled.png" % tag)


func _count_diff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return a.get_width() * a.get_height()
	var da := a.get_data()
	var db := b.get_data()
	var step := da.size() / (a.get_width() * a.get_height())
	var n := 0
	var k := 0
	while k < da.size():
		if da[k] != db[k] or da[k + 1] != db[k + 1] or da[k + 2] != db[k + 2]:
			n += 1
		k += step
	return n


func _diff_mask(a: Image, b: Image) -> Image:
	var m := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	m.fill(Color(0, 0, 0))
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				m.set_pixel(x, y, Color(1, 0, 0))
	return m


func _log(s: String) -> void:
	print("p101pixels: " + s)
	_lines.append(s)


func _finish() -> void:
	var ok := _fails == 0 and _ctrl_fails == 0 and _captures > 0 and _viol_total == 0
	_log("negative control (culled by the weapons' feet flags instead): %d of %d captures differ, %d pixels in all" % [_feet_caps, _captures, _feet_total])
	_log("captures %d, culled creatures summed %d, captures differing %d, controls differing %d, quad corners outside their bounds %d -> %s" % [_captures, _culled_total, _fails, _ctrl_fails, _viol_total, "PASS" if ok else "FAIL"])
	var f := FileAccess.open(_out + "/pixels.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(0 if ok else 1)


## The run's own screens closed through their own paths, as smoke_run does (a totem, the Stranger, the shop, a chest, the
## portal), so a walk past a structure never leaves the run paused.
func _close_modals() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(false)
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.get("stranger_screen") and _game.stranger_screen and _game.stranger_screen.visible:
		_game.stranger_screen._finish(false)
	if _game.get("structure_shop") and _game.structure_shop and _game.structure_shop.visible:
		_game.structure_shop._finish(false)
	if _game.get("totem_screen") and _game.totem_screen and _game.totem_screen.visible and not _game.totem_screen._done:
		var tp: Array = _game.totem_screen.planks()
		if not tp.is_empty():
			_game.totem_screen._pick(tp[0])
	if _game.portal_dialog and _game.portal_dialog.visible:
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)


## Every creature's quad as _render just wrote it (every one drawn: instance k of a type is its k-th standing creature in
## index order), its four corners placed as enemy_billboard.gdshader places them with the live camera, against its
## bounds (EnemyManager.vis_bounds): the corners outside them (0 expected).
func _bounds_violations() -> int:
	var em = _game.enemies
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var up: Vector3 = cam.global_transform.basis.y.normalized()
	var right: Vector3 = up.cross(cam.global_transform.basis.z.normalized()).normalized()
	var k_of := {}
	var bad := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 0 or em.hidden[i] == 1:
			continue
		var t: int = em.type_idx[i]
		var k: int = int(k_of.get(t, 0))
		k_of[t] = k + 1
		var mm: MultiMesh = em.types[t]["mm"]
		var xf: Transform3D = mm.get_instance_transform(k)
		var sq: float = maxf(mm.get_instance_custom_data(k).a, 0.2)
		var b: PackedFloat32Array = em.vis_bounds(i, up, em._cf_tick)
		var c := Vector3(b[0], b[1], b[2])
		var w: float = xf.basis.x.length() * (1.0 + (1.0 - sq) * 0.5)
		var h: float = xf.basis.y.length() * sq
		var roll := atan2(xf.basis.x.y, xf.basis.x.x)
		for vx in [-0.5, 0.5]:
			for vy in [0.0, 1.0]:
				var q := Vector2(vx * w, vy * h)
				q = Vector2(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll))
				var p: Vector3 = xf.origin + right * q.x + up * q.y
				if p.distance_to(c) > b[3] + 0.001:
					bad += 1
	return bad
