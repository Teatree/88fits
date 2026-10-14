## Pass 73, lane GROUND, scratch captures in the debug arena, frame by frame from the run camera:
##   emerge   a ring of creatures growing out of the ground (the ground-clip, the dust), then the Tumbleweed King rising
##   rain     the Gila Grande's cactus rain: every circle lit at once, the crouch, the spew from its mouth, the spikes
##            landing together
##   gila     the Gila's burrow: it sinks out of sight, three seconds of nothing, the warning where the walking hero is
##            heading, the eruption throwing him and the crowd, the Gila rising
##   scorpion the Dune Scorpion's burrow: the visible sink, the ring and the mound, the eruption's weaker throw
## A watchdog quits after WATCHDOG seconds whatever happens. Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p73_ground_shot.gd -- out=<dir> [only=emerge,rain,gila,scorpion]
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p73_ground"
var _only: PackedStringArray = ["emerge", "rain", "gila", "scorpion"]
var _run
var _reg
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	var wd := create_timer(WATCHDOG, true, false, true)
	wd.timeout.connect(func():
		printerr("p73_ground: WATCHDOG fired after %d s" % int(WATCHDOG))
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png(_out.path_join(name + ".png"))
	print("p73_ground: ", name)


## A full-size crop round world point `at` (its screen spot from the run camera), `w` x `h` pixels.
func _crop(name: String, at: Vector3, w: int = 360, h: int = 360) -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam == null:
		return
	var img: Image = root.get_viewport().get_texture().get_image()
	var p := cam.unproject_position(at)
	var x := clampi(int(p.x) - w / 2, 0, maxi(img.get_width() - w, 0))
	var y := clampi(int(p.y) - h / 2, 0, maxi(img.get_height() - h, 0))
	img.get_region(Rect2i(x, y, mini(w, img.get_width()), mini(h, img.get_height()))).save_png(_out.path_join(name + ".png"))
	print("p73_ground: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(2.0)
	_run.debug_clear_items()
	_run.build_changed.emit()
	var tl = _reg.map("red_canyon").timeline
	g.enemies.set_spawn_rise(tl.spawn_rise_value("seconds"), tl.spawn_rise_value("big_seconds"), tl.spawn_rise_value("targetable"), tl.spawn_rise_value("dust"))
	for what in _only:
		match what:
			"emerge":
				await _emerge()
			"rain":
				await _rain()
			"gila":
				await _gila()
			"scorpion":
				await _scorpion()
	_save.data = keep
	print("p73_ground: done in %d s" % int((Time.get_ticks_msec() - _t0) / 1000))
	quit(0)


func _clear() -> void:
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.4)


func _attack_index(em, i: int, name: String) -> int:
	var atks: Array = em.types[em.type_idx[i]]["def"].boss.get("attacks", [])
	for j in range(atks.size()):
		if str((atks[j] as Dictionary).get("name", "")) == name:
			return j
	return 0


## A ring of skeletons and runts growing out of the sand round the hero, then the King rising.
func _emerge() -> void:
	g.camera.zoom_override = 0.9
	await _clear()
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids := ["skeleton", "goblin_runt", "skeleton_knight", "hellhound", "imp", "sand_lizard"]
	for k in range(8):
		var a := TAU * float(k) / 8.0 + 0.3
		var at := here + Vector3(cos(a), 0, sin(a)) * 4.5
		var j: int = em.spawn(ids[k % ids.size()], at)
		if j >= 0:
			em.speed[j] = 0.0
	print("p73_ground: emerge pace %.2f, emerged %d" % [em.pace, em.emerged])
	var a0 := here + Vector3(cos(0.3), 0, sin(0.3)) * 4.5
	for k in range(9):
		_shot("emerge_%02d" % k)
		_crop("emerge_crop_%02d" % k, a0 + Vector3(0, 0.6, 0), 300, 300)
		await _frames(4)
	await _wait(0.5)
	_shot("emerge_up")
	await _clear()
	g.camera.zoom_override = 1.4
	var kat := here + Vector3(0, 0, -5.5)
	var b: int = em.spawn("tumbleweed_king", kat)
	if b >= 0:
		em.atk_t[b] = 99.0
	for k in range(8):
		_shot("king_rise_%02d" % k)
		_crop("king_crop_%02d" % k, kat + Vector3(0, 1.5, 0), 520, 460)
		await _frames(7)
	await _wait(0.4)
	_shot("king_up")
	await _clear()


## The Gila 6 m up the screen, its next attack the cactus rain.
func _rain() -> void:
	g.camera.zoom_override = 1.75
	await _clear()
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var i: int = em.spawn("gila_grande", here + Vector3(0, 0, -6.0))
	if i < 0:
		printerr("p73_ground: no Gila")
		return
	await _wait(1.6)
	em.atk_i[i] = _attack_index(em, i, "cactus_rain")
	em.atk_t[i] = 0.05
	em.hold_t[i] = 0.0
	var waited := 0.0
	while em.state[i] != 4 and waited < 5.0:
		await process_frame
		waited += 1.0 / 60.0
	var wind: float = em.timer[i]
	print("p73_ground: rain wind-up %.2f s (pace %.2f), lit %s" % [wind, em.pace, str(em._custom_lit.has(i))])
	await _frames(3)
	_shot("rain_a_lit")
	await _wait(wind * 0.5)
	_shot("rain_b_mid")
	var cap := 0
	while em.state[i] == 4 and em.timer[i] > 0.12 and cap < 600:
		cap += 1
		await process_frame
	_shot("rain_c_crouch")
	_crop("rain_c_crouch_crop", em.pos[i] + Vector3(0, 2.5, 0), 560, 560)
	cap = 0
	while em.state[i] == 4 and cap < 120:
		cap += 1
		await process_frame
	await _frames(2)
	_shot("rain_d_spew")
	_crop("rain_d_spew_crop", em.pos[i] + Vector3(0, 2.5, 0), 560, 560)
	print("p73_ground: rain spots %d" % int(em.custom_last.get("spots", 0)))
	var l0: int = em.custom_landed
	var k := 0
	cap = 0
	while not em._custom_runs.is_empty() and cap < 240:
		await _frames(6)
		cap += 6
		_shot("rain_e_%02d" % k)
		k += 1
	await _wait(0.3)
	_shot("rain_f_after")
	print("p73_ground: rain landed %d of them" % (em.custom_landed - l0))
	await _clear()


## The Gila's burrow: the hero walks east the whole time; a few creatures round him to be thrown.
func _gila() -> void:
	g.camera.zoom_override = 1.6
	await _clear()
	var em = g.enemies
	var pl = g.player
	# no god mode (a god takes no hit, so nothing throws him): a deep well of health instead
	pl.god = false
	pl.max_hp = 100000.0
	pl.hp = 100000.0
	var here: Vector3 = pl.global_position
	var i: int = em.spawn("gila_grande", here + Vector3(-2.0, 0, -6.0))
	if i < 0:
		printerr("p73_ground: no Gila")
		return
	await _wait(1.6)
	em.atk_i[i] = _attack_index(em, i, "burrow")
	em.atk_t[i] = 0.05
	em.hold_t[i] = 0.0
	var waited := 0.0
	while em.state[i] != 4 and waited < 5.0:
		await process_frame
		waited += 1.0 / 60.0
	print("p73_ground: gila burrow wind-up %.2f s" % em.timer[i])
	for k in range(6):
		_shot("gila_a_sink_%02d" % k)
		await _frames(6)
	# under: the hero sets off east; a crowd waits round the spot the warning picks (out of his thorns' reach)
	var inp = pl.input
	inp.origin = Vector2(216, 500)
	var under := 0
	while em.state[i] == 4 and em.hidden[i] == 0 and under < 180:
		under += 1
		await process_frame
	var shot_hidden := false
	var cap := 0
	while em.state[i] == 4 and em.timer[i] > 0.6 and cap < 600:
		cap += 1
		inp.wants_move = true
		inp.touch_pos = inp.origin + Vector2(70.0, 0.0)
		if not shot_hidden and em.timer[i] < 2.5:
			shot_hidden = true
			_shot("gila_b_hidden")
		await process_frame
	cap = 0
	while em.state[i] == 4 and cap < 240:
		cap += 1
		inp.wants_move = true
		inp.touch_pos = inp.origin + Vector2(70.0, 0.0)
		if em._burrows.has(i) and bool(em._burrows[i]["warned"]) and not FileAccess.file_exists(_out.path_join("gila_c_warn.png")):
			var spot: Vector3 = em.atk_target[i]
			for k in range(6):
				var a := TAU * float(k) / 6.0 + 0.4
				var j: int = em.spawn("skeleton_knight", spot + Vector3(cos(a), 0, sin(a)) * 4.2)
				if j >= 0:
					em.speed[j] = 0.0
					em.rise_t[j] = 1.0
					em.rise_v[j] = 0.0
					em.state[j] = 0
			await _frames(2)
			_shot("gila_c_warn")
		await process_frame
	inp.wants_move = false
	inp.touch_pos = inp.origin
	print("p73_ground: gila erupt %s, hero air %s, thrown %d" % [str(em.last_erupt), str(pl.airborne), em.erupt_thrown])
	for k in range(8):
		_shot("gila_d_erupt_%02d" % k)
		await _frames(6)
	await _wait(0.6)
	_shot("gila_e_after")
	pl.god = true
	await _clear()


## The Dune Scorpion's burrow: it digs in 5 m off, the ring on the hero and the mound, the eruption.
func _scorpion() -> void:
	g.camera.zoom_override = 1.2
	await _clear()
	var em = g.enemies
	var pl = g.player
	pl.god = false
	pl.max_hp = 100000.0
	pl.hp = 100000.0
	var here: Vector3 = pl.global_position
	var i: int = em.spawn("dune_scorpion", here + Vector3(-3.0, 0, -4.0))
	if i < 0:
		printerr("p73_ground: no scorpion")
		return
	em.speed[i] = 0.0
	await _wait(1.5)
	for k in range(4):
		var a := TAU * float(k) / 4.0 + 0.3
		var j: int = em.spawn("skeleton_knight", here + Vector3(cos(a) * 3.4, 0, sin(a) * 3.4))
		if j >= 0:
			em.speed[j] = 0.0
	em.atk_i[i] = _attack_index(em, i, "burrow")
	em.atk_t[i] = 0.05
	em.state[i] = 0
	var waited := 0.0
	while em.state[i] != 4 and waited < 5.0:
		await process_frame
		waited += 1.0 / 60.0
	print("p73_ground: scorpion burrow wind-up %.2f s" % em.timer[i])
	for k in range(6):
		_shot("scorp_a_sink_%02d" % k)
		await _frames(6)
	var cap := 0
	while em.state[i] == 4 and em.timer[i] > 0.1 and cap < 400:
		cap += 1
		await process_frame
	_shot("scorp_b_mound")
	cap = 0
	while em.state[i] == 4 and cap < 60:
		cap += 1
		await process_frame
	print("p73_ground: scorpion erupt %s, hero air %s" % [str(em.last_erupt), str(pl.airborne)])
	for k in range(7):
		_shot("scorp_c_erupt_%02d" % k)
		await _frames(5)
	pl.god = true
	await _clear()
