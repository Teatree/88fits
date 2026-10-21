## Pass 95 lane WORLD's capture (scratch, after _p60_pk_shot.gd): the debug arena, 70 gems and 20 coins scattered 3 to
## 18 m round the hero, the Magnet power-up applied (Game.apply_pickup: the timed wide pull), frames through its run
## (`m_NNN` = NNN/100 s after the pickup: the 2D magnet orbiting, its field lines, the ring at the reach, the HUD's
## plate with the seconds), then the hero moved 7 m east with fresh gems round him (`walk_NNN`: the ones now inside come,
## the ones left beyond stay), the last second's blink (`end_950`) and after the time is up (`end_1100`: the icon gone,
## a gem let go at 6 m lying still). Each frame prints the pickups' phases and the magnet's state. Windowed at the
## phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p95_WORLD_shot.gd -- out=<dir>
extends SceneTree

const TIMES := [0.15, 0.5, 1.0, 1.8, 3.0]
const WATCHDOG_S := 60.0

var _out := "user://p95_world"
var _run
var _save
var g
var _frames: Array = []
var _t0 := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec() * 0.001
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_watchdog)


func _watchdog() -> void:
	if Time.get_ticks_msec() * 0.001 - _t0 > WATCHDOG_S:
		printerr("p95_world_shot: watchdog: %d s, quitting" % int(WATCHDOG_S))
		_flush()
		quit(2)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


## Grabs the frame (a GPU read, quick) and prints where the pickups and the magnet are; the PNG is written by _flush.
func _grab(name: String) -> void:
	await process_frame
	_frames.append([name, root.get_viewport().get_texture().get_image()])
	var pm = g.pickups
	var lying := 0
	var waiting := 0
	var rising := 0
	var flying := 0
	for i in range(pm.MAX):
		if pm.alive[i] == 0:
			continue
		if pm.flying[i] == 0:
			lying += 1
		elif pm.phase[i] == pm.PHASE_ARC_WAIT:
			waiting += 1
		elif pm.phase[i] == pm.PHASE_ARC_RISE:
			rising += 1
		else:
			flying += 1
	var mb = pm.magnet_buff
	var where := "none"
	if mb != null and is_instance_valid(mb):
		var hero: Vector3 = g.player.global_position
		var d: Vector3 = mb.global_position - hero
		where = "%.2f m from the hero, %d lines, %d sparks, icon %s" % [Vector2(d.x, d.z).length(), mb.lines_drawn, mb.sparks, "shown" if mb._sprite.visible else "blinked off"]
	print("p95_world_shot: %-9s lying %3d  waiting %3d  rising %3d  flying %3d  pulls %3d  left %.1f s  reach %.1f m  magnet %s" % [name, lying, waiting, rising, flying, pm.magnet_pulls, pm.magnet_left(), pm.magnet_r, where])


func _flush() -> void:
	for f in _frames:
		(f[1] as Image).save_png(_out.path_join(str(f[0]) + ".png"))
	_frames.clear()


func _scatter(pm, here: Vector3, seed_v: int, n_gems: int, n_coins: int, r0: float, r1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for k in range(n_gems + n_coins):
		var kind: int = pm.KIND_COIN if k >= n_gems else (0 if k < n_gems / 2 else (1 if k < n_gems * 5 / 6 else 2))
		var a := rng.randf() * TAU
		var d := rng.randf_range(r0, r1)
		pm.spawn(kind, here + Vector3(cos(a), 0, sin(a)) * d, 0.01)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(2.5)
	var pm = g.pickups
	var here: Vector3 = g.player.global_position
	_scatter(pm, here, 95, 70, 20, 3.0, 18.0)
	await _wait(1.5)
	await _grab("before")
	var reg = root.get_node("Registry")
	var def = reg.pickup("magnet_pulse")
	g.apply_pickup(def, here)
	var t := 0.0
	for s in TIMES:
		var ds: float = float(s) - t
		if ds > 0.0:
			await _wait(ds)
		t = float(s)
		await _grab("m_%03d" % int(round(float(s) * 100.0)))
	_flush()
	# the hero walks: 7 m east with fresh gems round the new spot (the ones now within the reach come, the far ones stay)
	g.player.global_position = here + Vector3(7.0, 0, 0)
	_scatter(pm, g.player.global_position, 96, 30, 8, 4.0, 20.0)
	await _wait(0.6)
	await _grab("walk_060")
	await _wait(1.2)
	await _grab("walk_180")
	_flush()
	# the last second (the icon blinks), then gone: a gem let go at 6 m lies still
	var left: float = pm.magnet_left()
	if left > 1.0:
		await _wait(left - 0.8)
	await _grab("end_950")
	await _wait(1.3)
	pm.spawn(1, g.player.global_position + Vector3(0, 0, 6.0), 0.01)
	await _wait(0.6)
	await _grab("end_1100")
	_flush()
	_save.data = keep
	quit(0)
