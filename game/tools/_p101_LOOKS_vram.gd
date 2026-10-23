## Pass 101, lane LOOKS: what the GPU holds in pictures at each moment (the pass 100 VRAM probe, extended): at boot, on
## the title, in a stage 1/2/3 run, and in the arena after picking several hero and creature looks. One phase per process
## (each from a fresh boot), written to tools/dl/p101/LOOKS/vram_<tag>_<phase>.txt (a summary line + the folders + the
## biggest pictures) and appended as one JSON line to tools/dl/p101/LOOKS/vram_<tag>.jsonl.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --path game --script res://tools/_p101_LOOKS_vram.gd -- tag=before phase=run1
## phase: boot | title | run1 | run2 | run3 | arena. Windowed only (the headless renderer holds no textures). A watchdog
## quits at 150 s. Boot time = Time.get_ticks_msec() at the first frame (the engine, the autoloads and the Registry's scan).
extends SceneTree

const OUT := "D:/_projects/88fits/tools/dl/p101/LOOKS/"
var _tag := "a"
var _phase := "boot"
var _t := 0.0
var _game: Node
var _seen_t := -1.0
var _out: Array = []
var _boot_ms := 0
var _stage := 1
var _arena_step := 0
var _arena_t := 0.0
var _done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("phase="):
			_phase = a.substr(6)
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_boot_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("Save").call("begin_sandbox")
	root.get_node("Save").data["runs_started"] = 1
	if _phase == "boot":
		_dump("boot (autoloads only)")
		_finish()
		return
	if _phase == "title":
		change_scene_to_file("res://ui/TitleScreen.tscn")
		process_frame.connect(_tick_title)
		return
	var launch := {"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}
	if _phase.begins_with("run"):
		_stage = int(_phase.substr(3))
		launch["stage"] = _stage
	elif _phase == "arena":
		launch["arena"] = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(launch))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick_title() -> void:
	if _done:
		return
	_t += root.get_process_delta_time()
	if _t > 150.0:
		_finish()
	elif _t > 4.0:
		_dump("on the title, 4 s in")
		_finish()


func _tick() -> void:
	if _done:
		return
	_t += root.get_process_delta_time()
	if _t > 150.0:
		_dump("watchdog")
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
	if _phase == "arena":
		_tick_arena()
		return
	if _t - _seen_t > 20.0:
		_dump("in a stage %d run, 20 s in" % _stage)
		_finish()


## The arena: three hero looks shown (the first hero with looks), then three creatures spawned in other looks than they
## play, each a second apart, then the dump.
func _tick_arena() -> void:
	var panel = _game.get("arena_panel")
	if panel == null:
		return
	_arena_t += root.get_process_delta_time()
	if _arena_t < 1.0:
		return
	_arena_t = 0.0
	var reg := root.get_node("Registry")
	if _arena_step == 0:
		_dump("in the arena, nothing picked")
	var hero_steps: Array = []
	for c in reg.sorted_characters():
		if c.variant_codes().size() >= 3:
			for code in c.variant_codes().slice(0, 3):
				hero_steps.append([c.id, str(code)])
			break
	var enemy_steps: Array = []
	for d in reg.enemies.values():
		var codes: Array = d.variant_codes()
		for code in codes:
			if str(code) != d.variant:
				enemy_steps.append([d.id, str(code)])
				break
		if enemy_steps.size() >= 3:
			break
	if _arena_step < hero_steps.size():
		var s: Array = hero_steps[_arena_step]
		if _game.player.character.id != s[0]:
			panel.swap_hero(s[0])
		panel.show_look(s[1])
		_log("picked hero %s look %s" % [s[0], s[1]])
	elif _arena_step < hero_steps.size() + enemy_steps.size():
		var s2: Array = enemy_steps[_arena_step - hero_steps.size()]
		panel.spawn_enemy_n(reg.enemy_with(s2[0], s2[1]), 2)
		_log("spawned %s look %s" % [s2[0], s2[1]])
	else:
		_dump("in the arena after %d hero looks and %d creature looks" % [hero_steps.size(), enemy_steps.size()])
		_finish()
	_arena_step += 1


func _dump(when: String) -> void:
	# every imported picture under res:// that the resource cache holds is a texture the GPU holds (RGBA8, no mipmaps)
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
	var tex_mb: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var vid_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_log("== %s: %d cached pictures, %.0f MB at 4 bytes a pixel; Performance texture memory %.0f MB, video memory %.0f MB; boot %d ms" % [
		when, n, total / 1048576.0, tex_mb, vid_mb, _boot_ms])
	var la = load("res://core/data/LookArt.gd")
	var rl = load("res://core/systems/RunLooks.gd")
	if la and la.get("_held") != null:
		_log("   LookArt holds %d strips (%d pinned), %d disk loads; RunLooks pairs: %s" % [(la.get("_held") as Dictionary).size(), (la.get("_pinned") as Dictionary).size(), int(la.get("loads")), str(rl.get("last_pairs"))])
	var dk := by_dir.keys()
	dk.sort_custom(func(x, y): return by_dir[x] > by_dir[y])
	for k in dk:
		if by_dir[k] > 1048576:
			_log("   %-40s %7.1f MB" % [k, by_dir[k] / 1048576.0])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	var all := FileAccess.open(OUT + "cached_%s_%s.json" % [_tag, _phase], FileAccess.WRITE)
	if all:
		all.store_string(JSON.stringify(rows))
		all.close()
	for r in rows.filter(func(x): return x[0] > 1048576 or str(x[1]).contains("_sprite")):
		_log("   %6.1f MB  %5dx%-5d %s" % [r[0] / 1048576.0, r[2], r[3], r[1]])
	var j := FileAccess.open(OUT + "vram_%s.jsonl" % _tag, FileAccess.READ_WRITE)
	if j == null:
		j = FileAccess.open(OUT + "vram_%s.jsonl" % _tag, FileAccess.WRITE)
	if j:
		j.seek_end()
		j.store_line(JSON.stringify({"tag": _tag, "phase": _phase, "when": when, "pictures": n, "mb_4bpp": snappedf(total / 1048576.0, 0.1),
			"texture_mb": snappedf(tex_mb, 0.1), "video_mb": snappedf(vid_mb, 0.1), "boot_ms": _boot_ms}))
		j.close()


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
	print("p101looks: " + s)
	_out.append(s)


func _finish() -> void:
	if _done:
		return
	_done = true
	var f := FileAccess.open(OUT + "vram_%s_%s.txt" % [_tag, _phase], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
		f.close()
	root.get_node("Save").call("end_sandbox")
	quit(0)
