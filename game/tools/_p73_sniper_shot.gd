## Pass 73, lane SNIPER, scratch captures in the debug arena: the Saiga Sniper's telegraph frame by frame (the lines
## gathering and following the hero, the lock and its blinking hold), the beam and its sparks, the creatures on its line
## pushed aside, and the Vulture Raider's rocket shaken and slowed by a hit. Windowed at the phone's canvas, bounded: every
## wait has a frame cap and a watchdog quits after WATCHDOG seconds (a hung capture must not hold the Godot lock):
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p73_sniper_shot.gd -- out=<dir> [only=sniper,rocket] [zoom=1.35] [variant=SS-A]
extends SceneTree

const WATCHDOG := 120.0

var _out := "user://p73_sniper"
var _only: PackedStringArray = []
var _zoom := 1.35
## the sniper's look to play ("" = the one the game plays; SS-A = lane ART's painting)
var _variant := ""
var _run
var _reg
var _save
var g
var _start_ms := 0
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("variant="):
			_variant = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out)
	_start_ms = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if not _done and Time.get_ticks_msec() - _start_ms > int(WATCHDOG * 1000.0):
		_done = true
		push_error("p73_sniper: the watchdog ran out (%d s): quitting" % int(WATCHDOG))
		quit(2)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p73_sniper: ", name)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
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
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(3.0)
	# no weapon: nothing of his spoils the sniper's aim
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.5)
	if _on("sniper"):
		await _sniper()
	if _on("rocket"):
		await _rocket()
	_done = true
	quit(0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z) if g.map else 0.0, p.z)


## The sniper 17 m up the screen and a little right of the hero; frames by his own clock (the aim's and the hold's
## seconds, which run at the pace knob), then by frames from the shot.
func _sniper() -> void:
	var em = g.enemies
	em.kill_all(false)
	await _frames(2)
	var here: Vector3 = g.player.global_position
	var i: int = em.spawn("saiga_sniper", here + Vector3(5, 0, -17), null, 1.0, 1.0, _variant)
	# (he comes in at his stand-off, 26 m: brought into the frame)
	em.pos[i] = _ground(here + Vector3(5, 0, -17))
	em.home[i] = em.pos[i]
	var aim_marks := [0.05, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 1.97]
	var lock_marks := [0.05, 0.45, 0.9]
	var ai := 0
	var li := 0
	var shot_frame := -1
	var after := [0, 2, 4, 6, 9, 18, 36, 60, 84]
	var bi := 0
	var dummies_in := false
	for fr in range(60 * 30):
		await process_frame
		if not em.is_alive(i):
			print("p73_sniper: the sniper died")
			return
		var s: Dictionary = em._snipers.get(i, {})
		var ph := int(s.get("phase", 0))
		var t := float(s.get("t", 0.0))
		if ph == 1:
			# he follows the hero: the hero steps left through the first half of the aim
			if t < 1.0:
				g.player.global_position += Vector3(-0.045, 0, 0)
			if ai < aim_marks.size() and t >= float(aim_marks[ai]):
				_save_shot("sniper_aim_%02d_t%.2f" % [ai, t])
				ai += 1
		elif ph == 2:
			if not dummies_in:
				dummies_in = true
				# tough dummies on the line past the hero, a little either side of it: the beam nicks them and pushes them off
				var from: Vector3 = s["from"]
				var ld: Vector3 = s["ldir"]
				var side := Vector3(-ld.z, 0, ld.x)
				var hero: Vector3 = g.player.global_position
				for k in range(4):
					var at: Vector3 = hero + ld * (5.0 + 3.0 * float(k)) + side * (0.25 if k % 2 == 0 else -0.25)
					var d: int = em.spawn("training_dummy", _ground(at))
					if d >= 0:
						em.pos[d] = _ground(at)
						em.home[d] = em.pos[d]
			if li < lock_marks.size() and t >= float(lock_marks[li]):
				_save_shot("sniper_lock_%02d_t%.2f" % [li, t])
				li += 1
		if shot_frame < 0 and int(em.sniper_shots) > 0:
			shot_frame = fr
		if shot_frame >= 0:
			while bi < after.size() and fr - shot_frame >= int(after[bi]):
				_save_shot("sniper_beam_%02d_f%d" % [bi, fr - shot_frame])
				bi += 1
			if bi >= after.size():
				print("p73_sniper: shot ", em.sniper_last)
				return
	print("p73_sniper: no shot within the frame cap")


## The Vulture Raider brought in 16 m up the screen, his rocket on its way, then a hit on him: frames of the rocket shaking
## and slowing, and of it climbing back to full speed.
func _rocket() -> void:
	var em = g.enemies
	em.kill_all(false)
	await _frames(2)
	var here: Vector3 = g.player.global_position
	var i: int = em.spawn("rocketeer", here + Vector3(-5, 0, -15))
	em.pos[i] = _ground(here + Vector3(-5, 0, -15))
	var pm = g.projectiles
	var k := 0
	while k < 60 * 8 and not pm.has_rocket_of(i):
		await process_frame
		k += 1
	if not pm.has_rocket_of(i):
		print("p73_sniper: no rocket within 8 s")
		return
	await _wait(1.0)
	_save_shot("rocket_00_before")
	em.damage(i, 0.5, "revolver")
	var marks := [0, 2, 4, 7, 11, 16, 21, 40, 90, 150]
	var fr := 0
	var mi := 0
	while mi < marks.size() and fr <= 200:
		if fr >= int(marks[mi]):
			var share := -1.0
			for pi in pm.rocket_of.keys():
				if int(pm.rocket_of[pi]) == i:
					share = pm.rocket_speed_share(int(pi))
			_save_shot("rocket_%02d_hit_f%d_share%.2f" % [mi + 1, fr, share])
			mi += 1
		await process_frame
		fr += 1
