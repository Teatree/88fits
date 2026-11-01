## Pass 119 (lane LEGEND_A): a windowed capture series of the Iron Horse's or Personal Storm's whole sequence in the debug
## arena with a crowd, a PNG at each moment, bounded by a watchdog and a frame cap.
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##        --script res://tools/_p119_LEGEND_A_shots.gd -- item=iron_horse|personal_storm level=1|2 out=<dir>
##        [count=140] [layout=scatter|ring] [stage=1|2|3] [face=up|right|left|down] [times=0.3,0.8,...] [tag=x]
## Writes <out>/<tag>_<k>_<t>.png for every time in `times` (game seconds after the trigger) and prints each.
## The hero is a god and his weapons hold their fire, so every hit seen is the item's. The save in memory goes back as it
## was (the arena's sandbox keeps it off the disk; tools/godot.sh puts the PC save file back too).
extends SceneTree

const WATCHDOG_S := 200.0
const FRAME_CAP := 30000

var A: Dictionary = {}
var g = null
var _frames := 0
var _ended := false
var _save = null
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	create_timer(float(A.get("watchdog", WATCHDOG_S)), true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > FRAME_CAP:
		_bail("frame cap")


func _log(s: String) -> void:
	print("p119_shots: " + s)


func _bail(why: String) -> void:
	if _ended:
		return
	_log("stopped: " + why)
	_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	paused = false
	Engine.time_scale = 1.0
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(code)


func _frames_wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _game_wait(s: float) -> void:
	var t := 0.0
	var guard := 0
	while t < s and guard < 6000:
		await process_frame
		t += root.get_process_delta_time()
		guard += 1


## Frame times (ms: mean, worst) and draw calls (mean, most) over `secs` s of frames.
func _measure(secs: float) -> Dictionary:
	var last := Time.get_ticks_usec()
	var t := 0.0
	var n := 0
	var sum := 0.0
	var worst := 0.0
	var dc := 0.0
	var dc_max := 0.0
	while t < secs and n < 2000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		t += root.get_process_delta_time()
		n += 1
		sum += ms
		worst = maxf(worst, ms)
		var d := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		dc += d
		dc_max = maxf(dc_max, d)
	return {"frames": n, "ms": snappedf(sum / maxf(n, 1), 0.01), "worst_ms": snappedf(worst, 0.01), "draws": snappedf(dc / maxf(n, 1), 0.1), "draws_max": dc_max}


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	_log("saved " + path)


func _main() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	run.launch_override = {"arena": true, "analytics": false}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		_log("the arena never came up")
		_finish(1)
		return
	await _frames_wait(20)
	var panel = g.arena_panel
	var em = g.enemies
	g.no_random_chests = true
	g.player.god = true
	panel.call("_clear_field")
	var stage := int(A.get("stage", 1)) - 1
	var tl = run.map.timeline if run.map else null
	if stage >= 0 and tl != null:
		panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(stage, 0.0)
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	# which way he faces: the line runs that way (up the screen by default)
	var face := str(A.get("face", "up"))
	var yaw := {"up": 0.0, "left": PI * 0.5, "down": PI, "right": -PI * 0.5}.get(face, 0.0) as float
	g.player.facing = yaw
	if g.player.has_method("set_facing"):
		g.player.call("set_facing", yaw)
	# the crowd round him
	var n := int(A.get("count", 140))
	var opts := {"layout": str(A.get("layout", "scatter")), "clear_r": float(A.get("clear", 2.5)), "depth": float(A.get("depth", 0.0)),
		"density": float(A.get("density", 0.9)), "rise": false, "specials": false, "replace": true, "seed": int(A.get("seed", 3))}
	var came: int = panel.call("mass_spawn", [["skeleton", ""], ["goblin", ""], ["lesser_scorpion", ""]], n, opts)
	_log("crowd %d" % came)
	if A.has("elite"):
		var ed = root.get_node("Registry").enemy(str(A["elite"]))
		if ed:
			var hp: Vector3 = g.player.global_position
			var ei: int = em.spawn(ed.id, hp + Vector3(0.4, 0, -7.0), null, 1.0, 1.0)
			_log("elite %s at %d" % [ed.id, ei])
	if A.has("cards"):
		# the level-up cards: both items new, and the Iron Horse's step to Evolved (as a held one would show it)
		var out_c := str(A.get("out", "D:/_projects/88fits/tools/dl/p119/LEGEND_A/shots"))
		DirAccess.make_dir_recursive_absolute(out_c)
		var reg = root.get_node("Registry")
		var mk := func(id: String, lf: int, lt: int) -> Dictionary:
			return {"type": "passive", "id": id, "def": reg.passive(id), "level_from": lf, "level_to": lt, "is_new": lf == 0, "weight": 1.0}
		panel.set("_hide_hud", true)
		panel.call("set_clean", true)
		g.set_paused(true)
		g.cards.show_offer([mk.call("iron_horse", 0, 1), mk.call("personal_storm", 0, 1), mk.call("iron_horse", 1, 2)], "LEVEL 3!", false)
		await _game_wait(0.05)
		for k in range(60):
			await process_frame
		await _shot("%s/cards_%s.png" % [out_c, str(A.get("tag", "a"))])
		g.set_paused(false)
		_finish(0)
		return
	# the item, at its level
	var item := str(A.get("item", "iron_horse"))
	run.debug_set_item("passive", item, int(A.get("level", 1)))
	await _frames_wait(6)
	g.player.facing = yaw
	var node = g.get("iron_horse") if item == "iron_horse" else g.get("personal_storm")
	if node == null:
		_log("the item's node never came")
		_finish(1)
		return
	panel.set("_hide_hud", true)
	panel.call("set_clean", true)
	var hint = panel.get("_hint")
	if hint:
		hint.visible = false
	var bn = g.hud.get("_banner") if g.hud else null
	if bn:
		bn.visible = false
	var out := str(A.get("out", "D:/_projects/88fits/tools/dl/p119/LEGEND_A/shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var tag := str(A.get("tag", "%s_l%s_%s" % [item, str(A.get("level", 1)), face]))
	var default_times := "0.3,0.9,1.3,1.6,1.9,2.1,2.25,2.4,2.6,2.85,3.2,3.7,4.4" if item == "iron_horse" else "0.4,0.9,1.5,2.0,2.4,3.0,4.0,5.5,7.5,9.4,10.5,11.4,13.0"
	var times: PackedStringArray = str(A.get("times", default_times)).split(",")
	g.player.facing = yaw
	if A.has("perf"):
		# frame times and draw calls: `perf` s of the plain crowd, then the same with the item's sequence playing
		var secs := float(A["perf"])
		var base := await _measure(secs)
		node.call("trigger")
		var with := await _measure(secs)
		_log("perf plain: %s" % str(base))
		_log("perf with %s: %s" % [item, str(with)])
		_finish(0)
		return
	node.call("trigger")
	var t := 0.0
	var k := 0
	for ts in times:
		var at := float(ts)
		if at > t:
			g.player.facing = yaw
			await _game_wait(at - t)
			t = at
		await _shot("%s/%s_%02d_%04.2f.png" % [out, tag, k, at])
		k += 1
	if node.get("hits") != null:
		_log("hits %d" % int(node.get("hits")))
	if node.get("strikes") != null:
		_log("strikes %d" % int(node.get("strikes")))
	_finish(0)
