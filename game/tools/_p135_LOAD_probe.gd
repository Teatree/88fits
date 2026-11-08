## Pass 135: what a run's first load costs, stage by stage: the strips RunLooks pins (count, pixels as MB at 4 bytes, the
## file size on disk) and the time each takes to load here (decode included), largest first. Windowed or headless:
##   bash tools/godot.sh --audio-driver Dummy --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p135_LOAD_probe.gd
## Reads nothing from the save and writes nothing.
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var reg: Node = root.get_node("Registry")
	var map = reg.map("red_canyon")
	var hero = reg.character("drifter")
	var all_ms := 0.0
	var done := {}
	for stage in range(4):
		var pairs: Array = load("res://core/systems/RunLooks.gd").pairs_for(reg, map, stage)
		var paths: Array = []
		for p: Array in pairs:
			var d = reg.enemy(str(p[0]))
			if d == null:
				continue
			var path: String = d.look_strip_path(str(p[1]))
			if path != "" and not paths.has(path):
				paths.append(path)
		var look = reg.played_look(hero)
		if look and look.strip_path() != "":
			paths.append(look.strip_path())
		var mb := 0.0
		var disk := 0.0
		var ms := 0.0
		var rows: Array = []
		for path: String in paths:
			var t0 := Time.get_ticks_usec()
			var t = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			var dt := (Time.get_ticks_usec() - t0) / 1000.0
			var px: float = float(t.get_width() * t.get_height() * 4) / 1048576.0 if t is Texture2D else 0.0
			var imp := ResourceLoader.get_dependencies(path)
			var f := FileAccess.open(path.replace(".png", ".png"), FileAccess.READ)
			var sz := 0.0
			var remap := ""
			var cf := ConfigFile.new()
			if cf.load(path + ".import") == OK:
				remap = str(cf.get_value("remap", "path", ""))
			if remap != "":
				var g := FileAccess.open(remap, FileAccess.READ)
				if g:
					sz = g.get_length() / 1048576.0
			if not done.has(path):
				mb += px
				disk += sz
				ms += dt
				done[path] = true
				rows.append([dt, px, sz, path.get_file()])
		all_ms += ms
		rows.sort_custom(func(a, b): return a[0] > b[0])
		print("p135_load: stage %d: %d strips new, %.0f MB decoded, %.1f MB on disk, %.0f ms" % [stage, rows.size(), mb, disk, ms])
		for k in range(mini(5, rows.size())):
			print("p135_load:    %.0f ms  %.1f MB  %.1f MB disk  %s" % rows[k])
	print("p135_load: total %.0f ms" % all_ms)
	quit(0)
