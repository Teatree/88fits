## Pass 110 (lane ARENA): staged store screenshots (Google Play) from the debug arena, windowed, one PNG a process.
## The arena opens with the hero (and his look), the stage's look (Sundown, Nightfall's blue, Blood Moon's red), the
## creatures picked laid out round him (the arena's SHOTS crowd: ArenaPanel.mass_spawn, ArenaShots), an optional boss,
## the freeze, the screenshot framing (the hero centred above a caption band) and the HUD hidden; the game runs `advance`
## seconds so shots fly and hits land, then the picture is taken.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##        --script res://tools/store_shots.gd -- out=<file.png> [arguments]
## Arguments (all optional):
##   out=<file.png>        where the picture goes (default D:/_projects/88fits/tools/dl/p110/arena/store_shot.png)
##   hero=<id> look=<code> the hero and the look he wears (default the save's last hero, his played look)
##   weapons=<id:lv,...>   the weapons he holds (else his own starting gun); level=<n> his level (cards off)
##   stage=1|2|3           the stage's look (its filter, hell on 3) and the arena clock at its window's start
##   sand=<id>             one of the map's sands; at=<x,z> the hero moved there first (metres)
##   crowd=<id[@code][:n],...>  the creatures: an id, a look code after @, a count after : (then the counts are the crowd;
##                         without counts count= is split evenly); count=<n> (1000); layout=ring|scatter|chunks (ring);
##                         clear=<m> the clear circle round the hero (4); depth=<m> a ring's depth (0 = to the screen's
##                         edges); density=<per m2> a chunk's packing (1.2); rise=1 (grow out of the sand); specials=1;
##                         seed=<n> the layout's dice (1)
##   boss=<id>             a boss as the arena brings one (its bar hidden with the HUD); boss_up=<m> boss_side=<m>
##                         put it that far up the screen (north) and to the right of the hero (else where the arena
##                         puts one: about 12 m up)
##   freeze=walk|pose|off  (walk) the crowd frozen facing the hero, legs going or held
##   band=<0..0.6>         the caption band's share of the height, the hero centred above it (0.3); hero_y=<share> puts
##                         his middle there instead; frame=0 leaves the game's own camera
##   zoom=<x>              the camera's distance against the game's (1 = the game's at level 1; lower is nearer)
##   hide_hud=0            keep the HUD (default hidden; the arena's own buttons always go); numbers=0 hides the damage
##                         numbers too; dummies=1 keeps the
##                         arena's training dummies (else the field is emptied)
##   advance=<s>           game seconds run before the shot (1.0); speed=<x> the game's speed meanwhile (1)
##   fire=0                the hero's weapons hold their fire (no shots, no hits)
##   perf=<frames>         frame times measured over that many frames once the crowd stands (120; 0 = none)
##   watchdog=<s>          the wall-clock limit (150 s), frames=<n> the frame cap (20000): past either it quits with code 2
## Prints "store_shots: saved <path> (WxH)" and "store_shots: perf ..." ; the save in memory goes back as it was (the arena's
## sandbox keeps it off the disk; tools/godot.sh puts the PC save file back too).
## Autoloads and the game's classes are reached through the tree (SceneTree scripts compile before the autoloads exist).
extends SceneTree

const WATCHDOG_S := 150.0
const FRAME_CAP := 20000
const DEFAULT_OUT := "D:/_projects/88fits/tools/dl/p110/arena/store_shot.png"

var A: Dictionary = {}
var g = null
var _frames := 0
var _frame_cap := FRAME_CAP
var _ended := false
var _save = null
var _keep: Dictionary = {}
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_frame_cap = int(A.get("frames", FRAME_CAP))
	_t0 = Time.get_ticks_msec()
	create_timer(float(A.get("watchdog", WATCHDOG_S)), true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > _frame_cap:
		_bail("frame cap %d" % _frame_cap)


func _s(k: String, d: String) -> String:
	return str(A.get(k, d))


func _f(k: String, d: float) -> float:
	return float(A.get(k, d))


func _b(k: String, d: bool) -> bool:
	if not A.has(k):
		return d
	return str(A[k]) in ["1", "true", "yes", "on"]


func _log(s: String) -> void:
	print("store_shots: " + s)


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


## Game seconds `s` run at the game's speed now.
func _game_wait(s: float) -> void:
	var t := 0.0
	var guard := 0
	while t < s and guard < 6000:
		await process_frame
		t += root.get_process_delta_time()
		guard += 1


func _main() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	# no debug surfaces in the picture (in memory only: Settings saves through the Save, which goes back)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	_log("window %s, args %s" % [str(DisplayServer.window_get_size()), str(A)])
	# the arena by the launch the tools hand over in memory (Run.launch_override: no file left behind)
	var launch := {"arena": true, "analytics": false}
	if A.has("hero"):
		launch["character"] = _s("hero", "")
	if A.has("look"):
		launch["look"] = _s("look", "")
	run.launch_override = launch
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
	if not _b("dummies", false):
		panel.call("_clear_field")
	# the stage's look and the arena clock at its window's start
	var stage := int(A.get("stage", 1)) - 1
	var tl = run.map.timeline if run.map else null
	if stage >= 0 and tl != null:
		panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(stage, 0.0)
	if A.has("sand") and g.map and g.map.has_method("set_sand"):
		g.map.call("set_sand", _s("sand", ""))
	if A.has("at"):
		var xz: PackedStringArray = _s("at", "0,0").split(",")
		if xz.size() == 2:
			var x := float(xz[0])
			var z := float(xz[1])
			g.player.global_position = Vector3(x, g.map.height_at(x, z) + 0.5, z)
			g.camera.snap_to(g.player)
	if A.has("weapons"):
		run.debug_clear_items()
		for w in _s("weapons", "").split(","):
			var wl: PackedStringArray = w.split(":")
			if wl.size() >= 1 and wl[0] != "":
				run.debug_set_item("weapon", wl[0], int(wl[1]) if wl.size() > 1 else 5)
	if A.has("level"):
		g.arena_cards = false
		panel.call("_levels", maxi(int(A["level"]) - int(run.level), 0))
	if not _b("fire", true):
		g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	# the camera: the framing and the zoom, then a few frames so the crowd is laid on what the camera sees
	if A.has("zoom"):
		panel.call("set_zoom", _f("zoom", 1.0))
	if _b("frame", true):
		if A.has("hero_y"):
			panel.call("set_band", 1.0 - 2.0 * _f("hero_y", 0.5))
		else:
			panel.call("set_band", _f("band", 0.3))
		panel.call("set_framing", true)
		panel.set("_guide_on", false)
		if A.has("hero_y"):
			g.camera.frame_hero_y = _f("hero_y", 0.5)
	var fz := _s("freeze", "walk")
	panel.call("set_freeze", 1 if fz == "walk" else (2 if fz == "pose" else 0))
	await _frames_wait(4)
	# the crowd
	if A.has("crowd"):
		var entries: Array = []
		var counted := true
		var total := 0
		for part in _s("crowd", "").split(","):
			if part.strip_edges() == "":
				continue
			var n_s := ""
			var head := part
			if part.contains(":"):
				head = part.get_slice(":", 0)
				n_s = part.get_slice(":", 1)
			var id := head.get_slice("@", 0)
			var code := head.get_slice("@", 1) if head.contains("@") else ""
			if reg.enemy(id) == null:
				_log("no creature '%s'" % id)
				continue
			if n_s == "":
				counted = false
				entries.append([id, code])
			else:
				total += int(n_s)
				entries.append([id, code, int(n_s)])
		var n := total if counted and total > 0 else int(A.get("count", 1000))
		if not counted:
			for e in entries:
				(e as Array).resize(2)
		var opts := {"layout": _s("layout", "ring"), "clear_r": _f("clear", 4.0), "depth": _f("depth", 0.0),
			"density": _f("density", 1.2), "rise": _b("rise", false), "specials": _b("specials", false),
			"replace": not _b("dummies", false), "seed": int(A.get("seed", 1))}
		var t_sp := Time.get_ticks_usec()
		var came: int = panel.call("mass_spawn", entries, n, opts)
		_log("crowd: %d of %d came (%s) in %.0f ms; alive %d, pool %d" % [came, n, str(entries), (Time.get_ticks_usec() - t_sp) / 1000.0, int(em.count_alive), int(em.pool_max)])
	if A.has("boss"):
		var bd = reg.enemy(_s("boss", ""))
		if bd:
			panel.set("_count", 1)
			panel.call("spawn_enemy", bd)
			var bi := int(em.boss_index)
			if bi >= 0 and (A.has("boss_up") or A.has("boss_side")):
				var hp: Vector3 = g.player.global_position
				var bx := hp.x + _f("boss_side", 0.0)
				var bz := hp.z - _f("boss_up", 9.0)
				em.pos[bi] = Vector3(bx, g.map.height_at(bx, bz), bz)
			_log("boss %s, index %d" % [bd.id, bi])
		else:
			_log("no boss '%s'" % _s("boss", ""))
	# the frame times with the crowd standing
	var perf_n := int(A.get("perf", 120))
	if perf_n > 0:
		await _frames_wait(5)
		var last := Time.get_ticks_usec()
		var sum := 0.0
		var worst := 0.0
		var proc := 0.0
		var phys := 0.0
		for k in range(perf_n):
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			sum += ms
			worst = maxf(worst, ms)
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_log("perf: %d alive, %d drawn calls, frame %.1f ms average (%.0f fps), worst %.1f ms; process %.1f ms, physics %.1f ms a frame" % [
			int(em.count_alive), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), sum / perf_n,
			1000.0 / maxf(sum / perf_n, 0.001), worst, proc / perf_n, phys / perf_n])
	# the moment: the game runs a little (shots fly, hits land), then the picture
	panel.call("set_speed", _f("speed", 1.0))
	await _game_wait(_f("advance", 1.0))
	# the arena's DEBUG ARENA banner never shows in a picture
	var bn = g.hud.get("_banner") if g.hud else null
	if bn:
		bn.visible = false
	# the arena's own controls always go; the HUD unless hide_hud=0
	panel.set("_hide_hud", _b("hide_hud", true))
	panel.set("_numbers", _b("numbers", true))
	panel.call("set_clean", true)
	panel.get("_hint").visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var out := _s("out", DEFAULT_OUT)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	if err != OK:
		_log("could not save %s (error %d)" % [out, err])
		_finish(1)
		return
	var p: Vector3 = g.player.global_position
	var sp: Vector2 = g.camera.camera.unproject_position(p + Vector3(0, 0.9, 0))
	_log("hero's middle on screen at %.0f, %.0f of %s (%.1f%% from the top)" % [sp.x, sp.y, str(root.get_visible_rect().size), 100.0 * sp.y / maxf(root.get_visible_rect().size.y, 1.0)])
	_log("saved %s (%dx%d) in %.1f s" % [out, img.get_width(), img.get_height(), (Time.get_ticks_msec() - _t0) / 1000.0])
	_finish(0)
