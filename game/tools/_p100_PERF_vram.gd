## Pass 100, lane PERF (assessment only): every texture the GPU holds once a run is going (RenderingServer's
## texture_debug_usage), grouped by folder and by format, the biggest listed; written to tools/dl/p100/PERF/vram_<tag>.txt.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --path game --script res://tools/_p100_PERF_vram.gd -- tag=a
## Windowed only (the headless renderer holds no textures). A watchdog quits at 180 s.
extends SceneTree

var _tag := "a"
var _t := 0.0
var _game: Node
var _seen_t := -1.0
var _out: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			_tag = a.substr(4)
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_dump("boot (autoloads only: the Registry has loaded every content resource)")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	_t += root.get_process_delta_time()
	if _t > 180.0:
		_finish()
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.god = true
		_seen_t = _t
		return
	if _t - _seen_t > 8.0:
		_dump("in a run, 8 s in")
		_finish()


func _dump(when: String) -> void:
	# texture_debug_usage is not bound in 4.7: every imported picture under res:// that the resource cache holds is a
	# texture the GPU holds (a lossy or lossless import uploads RGBA8, 4 bytes a pixel; no mipmaps in this project)
	var files: Array = []
	_walk("res://", files)
	var total := 0
	var by_dir := {}
	var rows: Array = []
	var n := 0
	for p: String in files:
		if not ResourceLoader.has_cached(p):
			continue
		var tex = load(p)
		if not tex is Texture2D:
			continue
		n += 1
		var b: int = (tex as Texture2D).get_width() * (tex as Texture2D).get_height() * 4
		total += b
		var parts := p.substr(6).split("/")
		var dir := "/".join(parts.slice(0, mini(2, parts.size() - 1)))
		by_dir[dir] = int(by_dir.get(dir, 0)) + b
		rows.append([b, p, (tex as Texture2D).get_width(), (tex as Texture2D).get_height()])
	_log("== %s: %d cached pictures, %.0f MB at 4 bytes a pixel; Performance texture memory %.0f MB, video memory %.0f MB" % [
		when, n, total / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	var dk := by_dir.keys()
	dk.sort_custom(func(x, y): return by_dir[x] > by_dir[y])
	for k in dk:
		if by_dir[k] > 1048576:
			_log("   %-40s %7.1f MB" % [k, by_dir[k] / 1048576.0])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	for r in rows.slice(0, 40):
		_log("   %6.1f MB  %5dx%-5d %s" % [r[0] / 1048576.0, r[2], r[3], r[1]])


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub in ["addons", "tests", "export"]:
			continue
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".png.import") or f.ends_with(".jpg.import") or f.ends_with(".webp.import"):
			out.append(dir.path_join(f.trim_suffix(".import")))


func _log(s: String) -> void:
	print("p100vram: " + s)
	_out.append(s)


func _finish() -> void:
	var f := FileAccess.open("D:/_projects/88fits/tools/dl/p100/PERF/vram_%s.txt" % _tag, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
		f.close()
	quit(0)
