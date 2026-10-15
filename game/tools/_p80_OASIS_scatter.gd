## Pass 80 (lane OASIS) probe: builds Red Canyon for seeds from..to and reports each seed's lakes, bush patches, green
## stands and paintings placed, and the fewest patches seen.
##   bash tools/godot.sh --headless --path game --script res://tools/_p80_OASIS_scatter.gd -- from=1 to=60
extends SceneTree

var _from := 1
var _to := 40


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("from="):
			_from = int(a.substr(5))
		elif a.begins_with("to="):
			_to = int(a.substr(3))
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var lo := 99
	var hist := {}
	var by_lakes := {}
	var t_build := 0.0
	for s in range(_from, _to + 1):
		run.forced_map_seed = s
		run.end()
		run.start(reg.character("drifter"), reg.map("red_canyon"))
		var t0 := Time.get_ticks_usec()
		var m: Node3D = (reg.map("red_canyon").scene as PackedScene).instantiate()
		root.add_child(m)
		t_build += (Time.get_ticks_usec() - t0) / 1000.0
		var np: int = (m.call("bush_patches") as Array).size()
		var ns: int = (m.call("green_stands") as Array).size()
		var nl: int = (m.call("lakes") as Array).size()
		var props = m.get("props")
		var placed: int = (props.placed as Array).size() if props else 0
		print("scatter: seed %d lakes %d patches %d stands %d paintings %d" % [s, nl, np, ns, placed])
		lo = mini(lo, np)
		hist[np] = int(hist.get(np, 0)) + 1
		var key := "%d lakes" % nl
		if not by_lakes.has(key):
			by_lakes[key] = []
		(by_lakes[key] as Array).append(np)
		m.free()
	print("scatter: fewest patches %d, histogram %s, by lakes %s, build %.0f ms a map" % [lo, str(hist), str(by_lakes), t_build / float(_to - _from + 1)])
	run.forced_map_seed = 0
	run.end()
	quit(0)
