## Lane WATCH (pass 80) scratch: parse-check the Watch's scripts only (check_scripts.gd walks everything).
extends SceneTree


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var bad := 0
	for p in ["res://tools/watch/WatchRing.gd", "res://tools/watch/WatchClock.gd", "res://tools/watch/WatchData.gd",
			"res://tools/watch/WatchChart.gd", "res://tools/watch/WatchStrip.gd", "res://tools/watch/WatchPanel.gd",
			"res://tools/watch/BotStub.gd", "res://tools/watch/Watch.gd", "res://tools/watch/watch_main.gd"]:
		var s = load(p)
		if s == null or not (s is GDScript) or (not s.can_instantiate() and s.reload() != OK):
			printerr("PARSE FAIL: ", p)
			bad += 1
		else:
			print("ok: ", p)
	var sc = load("res://tools/watch/Watch.tscn")
	if sc == null:
		printerr("SCENE FAIL")
		bad += 1
	else:
		var i = sc.instantiate()
		print("scene ok: ", i)
		i.free()
	quit(1 if bad > 0 else 0)
