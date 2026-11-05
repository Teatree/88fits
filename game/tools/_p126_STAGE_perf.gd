## Pass 126 (lane STAGE; Garry: The Dust Bowl's fog "without damping the view distance too much or killing performance"): what a stage's
## weather costs: one process, one map roll, one crowd standing frozen, the same camera; the weather off and on in turns (and each part
## alone), frame time and draw calls over the same number of frames. Windowed, silent, bounded (frame cap and watchdog), the save untouched.
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##        --script res://tools/_p126_STAGE_perf.gd -- [stage=3] [frames=300] [crowd=100]
extends SceneTree

const WATCHDOG_MS := 200000

var g = null
var _t0 := 0
var _frames := 300
var _stage := 2
var _crowd := 100


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"stage": _stage = int(kv[1]) - 1
			"frames": _frames = int(kv[1])
			"crowd": _crowd = int(kv[1])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_t0 = Time.get_ticks_msec()
	var run = root.get_node("Run")
	root.get_node("Save").begin_sandbox()
	run.launch_override = {"arena": true, "analytics": false, "character": "drifter"}
	change_scene_to_file("res://game/Game.tscn")
	var n := 0
	while n < 3000 and Time.get_ticks_msec() - _t0 < WATCHDOG_MS:
		await process_frame
		n += 1
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null and n > 60:
			g = cs
			break
	if g == null:
		printerr("perf: the arena never came up")
		quit(2)
		return
	var tl = run.map.timeline
	var panel = g.arena_panel
	g.player.god = true
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	panel.call("_clear_field")
	panel.call("set_clock", float(tl.stage_start(_stage)) / 60.0 + 0.05)
	var look = load("res://core/systems/StageLook.gd").call("of", g)
	look.show_stage(_stage, 0.0)
	# the crowd round the hero, on the screen, held
	var em = g.enemies
	var hero: Vector3 = g.player.global_position
	for k in range(_crowd):
		var a := float(k) * 2.399
		var r := 4.0 + 12.0 * sqrt(float(k) / float(maxi(_crowd, 1)))
		var id := "straw_man" if k % 2 == 0 else "dust_bunny"
		em.spawn(id, hero + Vector3(cos(a) * r, 0.0, sin(a) * r * 1.4 - 2.0), null, 1.0, 1000.0)
	em.set("crowd_freeze", 1)
	var block: Dictionary = (tl.stage_weather(_stage) as Dictionary).duplicate()
	await _wait(60)
	var cases := [["off", []], ["all", block.keys()], ["off", []], ["fog", ["fog"]], ["haze", ["haze"]], ["gust", ["gust"]], ["wind", ["wind", "wire_sway"]], ["off", []], ["all", block.keys()], ["off", []], ["all", block.keys()]]
	for c: Array in cases:
		var wb := {}
		for key in c[1]:
			wb[key] = block[key]
		g.map.set_weather(wb, 0.0)
		await _wait(30)
		var res: Array = await _measure()
		print("perf: %-5s frame %.2f ms (worst %.2f), %.1f draw calls, %d primitives, %d alive" % [c[0], res[0], res[1], res[2], int(res[3]), int(em.count_alive)])
		if Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
			break
	quit(0)


func _wait(k: int) -> void:
	for i in range(k):
		await process_frame


## Mean frame ms, the worst, mean draw calls, primitives.
func _measure() -> Array:
	var last := Time.get_ticks_usec()
	var sum := 0.0
	var worst := 0.0
	var draws := 0.0
	var prim := 0.0
	for k in range(_frames):
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		sum += ms
		worst = maxf(worst, ms)
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prim = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return [sum / _frames, worst, draws / _frames, prim]
