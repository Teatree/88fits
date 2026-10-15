## Pass 80 (lane OASIS) probe: rolls Red Canyon's layout for many seeds (the roll only, no terrain) and reports how many
## lakes each has, the share of three, and the closest any two lakes, the river, the flats and the wall come.
##   bash tools/godot.sh --headless --path game --script res://tools/_p80_OASIS_probe.gd -- seeds=2000 out=<file.json>
extends SceneTree

var _n := 1000
var _out := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			_n = int(a.substr(6))
		elif a.begins_with("out="):
			_out = a.substr(4)
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	run.end()
	run.start(reg.character("drifter"), reg.map("red_canyon"))
	var scene: PackedScene = reg.map("red_canyon").scene
	var counts := {}
	var worst_gap := INF
	var worst_river := INF
	var worst_flats := INF
	var worst_wall := INF
	var first_moved := 0
	var t0 := Time.get_ticks_usec()
	var rows: Array = []
	for s in range(1, _n + 1):
		var m = scene.instantiate()
		m.run_seed = s
		m._rng.seed = s
		m._noise.seed = s
		m._noise.frequency = 0.045
		m._noise.fractal_octaves = 3
		m.flats_center = Vector3(0, 0, 8)
		m._roll_layout()
		var lakes: Array = m.lakes()
		counts[lakes.size()] = int(counts.get(lakes.size(), 0)) + 1
		var fc := Vector2(0, 8)
		for i in lakes.size():
			var a: Dictionary = lakes[i]
			var ca: Vector2 = a["center"]
			var ra: float = a["radius"]
			worst_river = minf(worst_river, float(m._river_dist(ca)) - m.river_width * 0.5 - ra)
			worst_flats = minf(worst_flats, ca.distance_to(fc) - m.flats_radius - ra)
			worst_wall = minf(worst_wall, m.arena_radius - ca.length() - ra * 1.6)
			for j in range(i):
				var b: Dictionary = lakes[j]
				var gap: float = ca.distance_to(b["center"]) - (ra + float(b["radius"])) * 1.6
				worst_gap = minf(worst_gap, gap)
		if s <= 40:
			rows.append({"seed": s, "lakes": lakes.map(func(l): return [snappedf(l["center"].x, 0.1), snappedf(l["center"].y, 0.1), snappedf(l["radius"], 0.01)])})
		m.free()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var res := {"seeds": _n, "counts": counts, "share3": float(counts.get(3, 0)) / float(_n), "worst_dish_gap": worst_gap,
		"worst_river_clear": worst_river, "worst_flats_clear": worst_flats, "worst_wall_clear_dish": worst_wall, "ms": ms, "rows": rows}
	print("oasis_probe: ", JSON.stringify(res))
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	quit(0)
