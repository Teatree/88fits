## Pass 113, lane TWISTER: the tornado's look in the game's own camera and portrait framing. The debug arena, the hero
## in god mode, the crowd held still where a shot wants one; each stage's look shown before its frames.
##   fx     TornadoFx alone beside the hero at the map dust devil's size: rising (strength 0.15, 0.45, 0.75), full,
##          thinning (0.5 falling, 0.2 falling) and the collapse's puff
##   king   TornadoFx at the King's size wrapped round the Tumbleweed King (about three heroes tall round a 5 m boss)
##   devil  the map's dust devil (DustDevils.call_one) forming, full with creatures caught in it, collapsing
## Windowed (a watchdog quits after 240 s; every wait is bounded):
##   bash tools/godot.sh --audio-driver Dummy --resolution 540x1170 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p113_TWISTER_shots.gd -- out=<dir> [what=fx,king,devil] [looks=0,1,2] [perf=1]
extends SceneTree

var _out := "user://p113_twister"
var _what: Array = ["fx", "king", "devil"]
var _looks: Array = [0, 1, 2]
var _perf := false
var _run
var _save
var g
var _here := Vector3.ZERO
var _made: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("what="):
			_what = Array(a.substr(5).split(",", false))
		elif a.begins_with("looks="):
			_looks = []
			for s in a.substr(6).split(",", false):
				_looks.append(int(s))
		elif a == "perf=1":
			_perf = true
	DirAccess.make_dir_recursive_absolute(_out)
	seed(113)
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("p113_twister: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p113_twister: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _frames(150)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _frames(20)
	g.enemies.kill_all(false)
	await _frames(30)
	_here = _ground(g.player.global_position)
	if g.get("hud") and g.hud:
		g.hud.visible = false
	for what in _what:
		match what:
			"fx":
				await _fx()
			"king":
				await _king()
			"devil":
				await _devil()
	_save.data = keep
	quit(0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _look(s: int) -> void:
	load("res://core/systems/StageLook.gd").of(g).show_stage(s, 0.0)


func _fx() -> void:
	var fx = load("res://core/systems/TornadoFx.gd").new()
	g.add_child(fx)
	fx.global_position = _ground(_here + Vector3(2.5, 0, -5.0))
	for s: int in _looks:
		_look(s)
		fx.set_strength(0.0)
		for st: float in [0.15, 0.45, 0.75]:
			fx.set_strength(st)
			await _frames(20)
			await _shot("fx_s%d_rise%02d" % [s + 1, int(st * 100)])
		fx.set_strength(1.0)
		await _frames(40)
		await _shot("fx_s%d_full" % (s + 1))
		await _frames(23)
		await _shot("fx_s%d_full_b" % (s + 1))
		for st: float in [0.5, 0.2]:
			fx.set_strength(st)
			await _frames(20)
			await _shot("fx_s%d_thin%02d" % [s + 1, int(st * 100)])
		fx.burst()
		fx.set_strength(0.0)
		await _frames(18)
		await _shot("fx_s%d_burst" % (s + 1))
		await _frames(60)
	fx.queue_free()
	await _frames(5)


func _king() -> void:
	var at := _ground(_here + Vector3(0, 0, -6.5))
	var i: int = g.enemies.spawn_boss("tumbleweed_king", at)
	if i < 0:
		print("p113_twister: no king")
		return
	await _frames(90)
	var em = g.enemies
	em.speed[i] = 0.0
	em.cooldown[i] = 99.0
	em.atk_t[i] = 99.0
	var fx = load("res://core/systems/TornadoFx.gd").new()
	fx.height = 6.5
	fx.radius_bottom = 2.4
	fx.radius_top = 3.6
	fx.skirt_radius = 3.8
	fx.debris = 32
	fx.debris_size = 1.6
	g.add_child(fx)
	for s: int in _looks:
		_look(s)
		fx.set_strength(0.0)
		for st: float in [0.4, 1.0]:
			fx.set_strength(st)
			for k in range(30):
				fx.global_position = _ground(em.pos[i])
				em.vel[i] = Vector3.ZERO
				await process_frame
			await _shot("king_s%d_%02d" % [s + 1, int(st * 100)])
	fx.queue_free()
	em.kill_all(false)
	await _frames(30)


func _devil() -> void:
	var dds = g.map.get_node_or_null("DustDevils")
	if dds == null:
		print("p113_twister: no DustDevils on the map")
		return
	for s: int in _looks:
		_look(s)
		g.enemies.kill_all(false)
		await _frames(10)
		await _frames(5)
		var calls0 := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var dd = dds.call_one(_ground(_here + Vector3(-3.5, 0, -6.0)), Vector3(1, 0, 0.15))
		if dd == null:
			print("p113_twister: no devil")
			return
		dd.speed = 0.35
		# a crowd it walks into
		for k in range(10):
			var a := float(k) / 10.0 * TAU
			_made.append(g.enemies.spawn("skeleton", _ground(dd.global_position + Vector3(cos(a), 0, sin(a)) * (3.2 + float(k % 3)))))
		await _frames(40)
		await _shot("devil_s%d_forming" % (s + 1))
		var t0 := Time.get_ticks_usec()
		var perf0: int = int(Perf.usec.get("dustdevil", 0))
		var perf_fx0: int = int(Perf.usec.get("tornado", 0))
		await _frames(200)
		await _shot("devil_s%d_full" % (s + 1))
		await _frames(37)
		await _shot("devil_s%d_full_b" % (s + 1))
		if _perf:
			var calls1 := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			print("p113_twister: draw calls %d without, %d with the dust devil and its 10 creatures" % [calls0, calls1])
			var used := int(Perf.usec.get("dustdevil", 0)) - perf0
			var used_fx := int(Perf.usec.get("tornado", 0)) - perf_fx0
			print("p113_twister: script a frame: dustdevil %.3f ms + tornado %.3f ms over %d frames (%.1f s)" % [float(used) / 1000.0 / 237.0, float(used_fx) / 1000.0 / 237.0, 237, float(Time.get_ticks_usec() - t0) / 1e6])
		dd.end_now()
		await _frames(60)
		await _shot("devil_s%d_collapsing" % (s + 1))
		await _frames(120)
		g.enemies.kill_all(false)
		await _frames(10)
