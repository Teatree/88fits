## Pass 70, lane TRAMP, scratch captures in the debug arena with Fadeaway: Hang Time's trampoline (the drop, standing
## beside him, the walk-in jump frame by frame, the landing's dust, the fold) and May's puck (the throw, the slide, the
## doll inflating out of it, the fooling). Windowed at the phone's canvas, a watchdog quits a hung run:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p70_tramp_shot.gd -- out=<dir> [only=tramp,puck] [zoom=1.0]
extends SceneTree

const WATCHDOG := 150.0

var _out := "user://p70_tramp"
var _only: PackedStringArray = []
var _zoom := 0.0
var _east := false
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a == "east=1":
			_east = true
	DirAccess.make_dir_recursive_absolute(_out)
	# a hung capture blocks every lane: whatever happens, out after WATCHDOG seconds of wall time
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		print("p70_tramp: WATCHDOG fired, quitting")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p70_tramp: ", name)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "basketball", "level": 1, "character": "fadeaway", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	await _wait(2.0)
	if _on("tramp"):
		await _tramp()
	if _on("puck"):
		await _puck()
	_save.data = keep
	quit(0)


func _clear() -> void:
	_run.debug_clear_items()
	_run.build_changed.emit()
	g.enemies.kill_all(false)
	await _frames(3)


## The stick held at `stick` (screen right +X, screen down +Z with the fixed camera), the touch code off.
func _stick(stick: Vector2) -> void:
	var inp = g.player.input
	inp.set_process(false)
	inp.wants_move = stick.length() > 0.0
	inp.stick_dir = stick


## Frames until `cond` holds, at most `max_frames`.
func _until(cond: Callable, max_frames: int) -> bool:
	for k in range(max_frames):
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _tramp() -> void:
	await _clear()
	_run.add_perk("hang_time")
	_stick(Vector2.ZERO)
	var pl = g.player
	pl.facing = 0.0
	# a few slow creatures round the spot, for scale
	var em = g.enemies
	var here: Vector3 = pl.global_position
	for k in range(8):
		var a := TAU * float(k) / 8.0 + 0.3
		var i: int = em.spawn("goblin" if k % 2 == 0 else "skeleton", here + Vector3(cos(a), 0, sin(a)) * 8.5, null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] *= 0.2
	em._rebuild_grid()
	await _frames(10)
	g._tick_trampoline(0.0)
	var tr = g.trampoline
	tr.drop_now()
	if _east:
		# the other side of him (east: the sun's side), for the materials' look from there
		tr.at = g.map.clamp_to_arena(pl.global_position + Vector3(3.5, 0, 0))
		tr.at.y = g.map.height_at(tr.at.x, tr.at.z)
	await _frames(13)
	_save_shot("tramp_a_dropping")
	print("   phase ", tr.phase, " at ", tr.at)
	await _frames(40)
	_save_shot("tramp_b_standing")
	# he walks onto it from the side
	var to_it: Vector3 = tr.at - pl.global_position
	to_it.y = 0.0
	_stick(Vector2(to_it.normalized().x, to_it.normalized().z))
	var flew: bool = await _until(func() -> bool: return bool(pl.airborne), 180)
	print("   airborne ", flew, " launches ", tr.launches)
	if not flew:
		_stick(Vector2.ZERO)
		return
	# keep pushing the way he went (the stick at 35% bends nothing), frames of the flight
	var f0 := Engine.get_process_frames()
	for pair in [[2, "tramp_c_launch"], [12, "tramp_d_rising"], [33, "tramp_e_apex"], [50, "tramp_f_falling"]]:
		while Engine.get_process_frames() - f0 < int(pair[0]):
			await process_frame
		_save_shot(str(pair[1]))
		print("   t ", pl._air_t, " h ", pl.air_height(), " dip ", tr.dip, " phase ", tr.phase)
	await _until(func() -> bool: return not bool(pl.airborne), 120)
	_stick(Vector2.ZERO)
	await _frames(4)
	_save_shot("tramp_g_landed")
	await _frames(20)
	_save_shot("tramp_h_after")
	print("   landings ", tr.landings, " folds ", tr.folds, " phase ", tr.phase)


func _puck() -> void:
	await _clear()
	_stick(Vector2.ZERO)
	_run.add_perk("inflatable_may")
	var pl = g.player
	var em = g.enemies
	var here: Vector3 = pl.global_position
	var ids := ["skeleton", "goblin"]
	for k in range(14):
		var a := TAU * float(k) / 14.0
		var i: int = em.spawn(str(ids[k % 2]), here + Vector3(cos(a), 0, sin(a)) * (6.0 + float(k % 3)), null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] *= 0.3
	em._rebuild_grid()
	await _wait(0.8)
	g._tick_decoy(0.0)
	var dc = g.decoy
	dc.throw_now()
	# up the screen and to the right, where the camera sees it whole
	dc.to = g.map.clamp_to_arena(pl.global_position + Vector3(3.6, 0, -3.4))
	dc.to.y = g.map.height_at(dc.to.x, dc.to.z)
	dc.land_at = dc._short_of(dc.from, dc.to)
	var f0 := Engine.get_process_frames()
	for pair in [[12, "puck_a_flight"], [38, "puck_b_landed"], [46, "puck_c_sliding"], [56, "puck_d_inflate_30"],
			[63, "puck_e_inflate_peak"], [70, "puck_f_full"], [100, "puck_g_fooling"]]:
		while Engine.get_process_frames() - f0 < int(pair[0]):
			await process_frame
		_save_shot(str(pair[1]))
		print("   phase ", dc.phase, " t ", dc.t, " fooled ", em.fooled_indices().size())
