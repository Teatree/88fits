## Pass 113, lane TWISTER: a real run's dust devil, headless. The run starts (no arena), its DustDevils clock is moved
## to a second before `first`, and the probe checks that one forms on its own (inside the camera's view, form_dist from
## the hero), that its wind loop plays, what it costs a frame on the script side while it stands (Perf "dustdevil": the
## clock and the dust devil; "tornado": its TornadoFx), that sending it away fades it out and silences it, and that the
## next one is due `every` after the first formed. Exit 0 when all of it held.
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p113_TWISTER_probe.gd
extends SceneTree

var g
var _fails: Array = []


func _initialize() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("p113_probe: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _check(ok: bool, what: String) -> void:
	print("p113_probe: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _main() -> void:
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("director") != null and g.director.running and g.get("player") != null:
			break
	if g == null or g.get("director") == null or not g.director.running:
		print("p113_probe: no run")
		quit(2)
		return
	g.player.god = true
	await _frames(10)
	var dds = g.map.get_node_or_null("DustDevils")
	_check(dds != null, "the map has its DustDevils clock")
	if dds == null:
		quit(1)
		return
	var cfg: Dictionary = dds.cfg
	_check(dds.on and dds.alive().is_empty(), "the clock is on and none stands at the start (clock %.1f s)" % dds.clock)
	_check(is_equal_approx(float(dds.next_at), float(cfg["first"])), "the first is due at %.0f s" % float(dds.next_at))
	dds.clock = float(cfg["first"]) - 1.0
	var formed_at := -1.0
	for k in range(240):
		await process_frame
		if dds.formed > 0:
			formed_at = dds.clock
			break
	_check(dds.formed == 1 and formed_at >= float(cfg["first"]), "one formed on its own at %.2f s of the stage clock" % formed_at)
	if dds.alive().is_empty():
		quit(1)
		return
	var dd = dds.alive()[0]
	var hero: Vector3 = g.player.global_position
	var d := Vector2(dd.global_position.x - hero.x, dd.global_position.z - hero.z).length()
	var cam: Camera3D = g.camera.camera
	var sp := cam.unproject_position(dd.global_position)
	var vp := root.get_viewport().get_visible_rect().size
	_check(d >= (cfg["form_dist"] as Vector2).x - 0.5 and d <= (cfg["form_dist"] as Vector2).y + 0.5, "it formed %.1f m from the hero" % d)
	_check(Rect2(Vector2.ZERO, vp).has_point(sp), "it formed on the screen at %s of %s" % [sp, vp])
	_check(float(dds.next_at) - formed_at >= (cfg["every"] as Vector2).x - 0.05 and float(dds.next_at) - formed_at <= (cfg["every"] as Vector2).y + 0.05,
		"the next is due %.0f s after it" % (float(dds.next_at) - formed_at))
	var audio = root.get_node("Audio")
	await _frames(int(float(cfg["form_seconds"]) * 60.0) + 10)
	_check(dd.catching(), "formed after %.1f s, it grabs" % float(cfg["form_seconds"]))
	_check(audio.loop_playing("wd_dust_devil"), "its wind loop plays")
	# the cost a frame while it stands (the script side; its draws are 4 for the tornado and 1 for the ring)
	var u0 := int(Perf.usec.get("dustdevil", 0))
	var t0 := int(Perf.usec.get("tornado", 0))
	var n := 300
	await _frames(n)
	var dd_ms := float(int(Perf.usec.get("dustdevil", 0)) - u0) / 1000.0 / float(n)
	var fx_ms := float(int(Perf.usec.get("tornado", 0)) - t0) / 1000.0 / float(n)
	print("p113_probe: cost a frame while it stands: dustdevil %.3f ms, tornado %.3f ms, together %.3f ms (%d frames, %d creatures alive)" % [dd_ms, fx_ms, dd_ms + fx_ms, n, int(g.enemies.alive_count()) if g.enemies.has_method("alive_count") else -1])
	_check(dd_ms + fx_ms < 1.0, "it costs under 1 ms a frame on the script side")
	dd.end_now()
	await _frames(int(float(cfg["fade_seconds"]) * 60.0) + 90)
	_check(dds.alive().is_empty(), "sent away, it faded and is gone")
	await _frames(5)
	_check(not audio.loop_playing("wd_dust_devil"), "its wind loop stopped")
	save.data = keep
	print("p113_probe: %s" % ("all held" if _fails.is_empty() else "FAILED: %s" % [_fails]))
	quit(0 if _fails.is_empty() else 1)
