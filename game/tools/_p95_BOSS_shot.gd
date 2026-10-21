## Pass 95 lane BOSS scratch capture: the King's tumbleweed trail, his jump-and-three-stomps and the Scorpion Elite's tail
## sniper, frame by frame at phone size, in the debug arena (the hero stands, god mode). Windowed, fixed 60 fps, bounded
## waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p95_BOSS_shot.gd -- out=<dir> [only=volley,stomp,tail] [step=3] [zoom=0] [tag=p95] [dist=7]
## Writes <out>/<tag>_<seq>_f<frame>.png (whole frames) and <out>/<tag>_<seq>_frames.txt (per frame: the clock, lift_h,
## squash, the run's phase and counters), then quits. The PC save is kept aside (Save.begin_sandbox) and put back.
extends SceneTree

const WATCHDOG_S := 420.0

var _out := "user://p95_boss"
var _only: PackedStringArray = ["volley", "stomp", "tail"]
var _step := 3
var _zoom := 0.0
var _tag := "p95"
var _dist := 7.0
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
		elif a.begins_with("step="):
			_step = maxi(int(a.substr(5)), 1)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("dist="):
			_dist = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p95_boss: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	if _save.has_method("begin_sandbox"):
		_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p95_boss: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	await _wait(1.0)
	# no weapon firing at the boss: the pictures are the attacks, not the hero's rounds
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.5)
	for seq in _only:
		await _seq(str(seq))
	print("p95_boss: done -> ", _out)
	_save.data = keep
	if _save.has_method("end_sandbox"):
		_save.end_sandbox()
	quit(0)


## The camera's forward on the ground: "up the screen" from the hero.
func _up_screen() -> Vector3:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(0, 0, -1)
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0, 0, -1)


func _attack_index(def, atk_name: String) -> int:
	var attacks: Array = def.boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


## Spawns `id` `dist` m up the screen, waits for it to rise, holds it still; its index.
func _creature(id: String, dist: float) -> int:
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	var at: Vector3 = here + _up_screen() * dist
	var i: int = em.spawn(id, at)
	if i < 0:
		return -1
	em.speed[i] = 0.0
	em._rebuild_grid()
	var guard := 0
	while em.rise_t[i] < 1.0 and guard < 300:
		await process_frame
		guard += 1
	return i


## Forces attack `k` of creature `i` now: the runner starts it on its next tick.
func _force(i: int, k: int) -> void:
	var em = g.enemies
	em.state[i] = em.STATE_MOVE
	em.atk_i[i] = k
	em.atk_t[i] = 0.0
	em.hold_t[i] = 0.0
	em.cooldown[i] = 99.0
	var guard := 0
	while em.state[i] != em.STATE_ATTACK and guard < 120:
		await process_frame
		guard += 1


func _seq(name: String) -> void:
	var em = g.enemies
	var log := FileAccess.open(_out.path_join("%s_%s_frames.txt" % [_tag, name]), FileAccess.WRITE)
	match name:
		"volley":
			var b: int = await _creature("tumbleweed_king", _dist)
			if b < 0:
				return
			var k := _attack_index(_reg.enemy("tumbleweed_king"), "tumbleweed_volley")
			await _force(b, k)
			# the wind-up (0.8 s) then the roll: 3.5 s of frames
			await _film(name, 210, log, b)
		"stomp":
			var b: int = await _creature("tumbleweed_king", _dist)
			if b < 0:
				return
			var k := _attack_index(_reg.enemy("tumbleweed_king"), "stomp")
			await _force(b, k)
			# the wind-up (1.2 s), the three hops and landings (about 2.8 s), the settle
			await _film(name, 290, log, b)
		"tail":
			# farther off: the lines from the tail are long enough to read, the beam crosses the screen
			var s: int = await _creature("dune_scorpion", _dist + 4.0)
			if s < 0:
				return
			var def = em.types[em.type_idx[s]]["def"]
			var k := _attack_index(def, "tail_sniper")
			if k >= 0:
				# always this attack in the capture (its roll never skips it here)
				(def.boss["attacks"] as Array)[k]["chance"] = 1.0
			await _force(s, k)
			# the wind-up (0.5 s), three aims, locks and beams with their gaps (6 s at pace 1; 7.5 s at the arena's 0.8), the sparks
			await _film(name, 600, log, s)
	log.close()


## `n` frames from now, every `step`-th saved; the state logged each frame.
func _film(name: String, n: int, log: FileAccess, i: int) -> void:
	var em = g.enemies
	for fr in range(n):
		await process_frame
		var st := "state=%d lift=%.2f squash=%.2f" % [em.state[i], em.lift_h[i], em.squash[i]]
		if em._stomps.has(i):
			var s: Dictionary = em._stomps[i]
			st += " stomp phase=%d t=%.2f n=%d left=%d" % [int(s["phase"]), float(s["t"]), int(s["n"]), int(s["left"])]
		if em._tails.has(i):
			var s: Dictionary = em._tails[i]
			st += " tail phase=%d t=%.2f shots=%d left=%d" % [int(s["phase"]), float(s["t"]), int(s["shots"]), int(s["left"])]
		st += " lands=%d waves_hits=%d shots=%d tracers=%d puffs=%d" % [em.stomp_lands, em.stomp_hero_hits, em.tail_shots, g.projectiles.tracer_segments, g.projectiles.tumble_puffs]
		log.store_line("%s f%03d %s" % [name, fr, st])
		if fr % _step == 0:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(_out.path_join("%s_%s_f%03d.png" % [_tag, name, fr]))
