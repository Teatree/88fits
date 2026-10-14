## Pass 74 (lane RESULTS): the Results show filmed frame by frame on its own clock, so every frame is where the show
## stands (the screen's and the chart's processing stopped and stepped by hand; a frame is saved after each step):
## the gold every 0.5 s, the chart block's pop every 0.04 s, the chart part (the line, its marks, the counters and the
## source rows together) every 0.16 s, the second sequence every 0.5 s. Runs: story (tools/results_story.gd's 10:00
## extraction with an unlock and four unlocks brought closer), down (its fall: two graves, the revive's blast), plain (a
## run with no story: the rows biggest first, spread over the chart part). Windowed at the phone's canvas:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p74_RESULTS_shot.gd -- out=<dir> [inset=130] [only=story,down,plain]
## A watchdog quits after WATCHDOG seconds; every wait is bounded. Frames land in <out>/<run>[_inset<N>]/fNNN_<part>_<frac>.png
## with a list of what each shows in frames.txt.
extends SceneTree

const WATCHDOG := 400.0
## Show seconds between two frames, by part.
const STEP := {"": 0.5, "gold": 0.5, "pop": 0.04, "chart": 0.16, "pause": 0.5, "scroll": 0.35, "unlock": 0.3, "progress": 0.3}
## The second sequence is filmed this far at most (show seconds).
const MAX_SHOW := 30.0

var _out := "user://p74_results"
var _only: Array = []
var _inset := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	var secs := _watch_secs()
	create_timer(secs, true, false, true).timeout.connect(func():
		printerr("p74_results_shot: watchdog after %d s" % int(secs))
		Engine.time_scale = 1.0
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


## How long the whole tool may take before the watchdog quits it (real seconds).
func _watch_secs() -> float:
	return WATCHDOG


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _suffix() -> String:
	return "" if _inset < 0 else "_inset%d" % _inset


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	if _want("story"):
		await _story(false)
		await _film("story" + _suffix())
	if _want("down"):
		await _story(true)
		await _film("down" + _suffix())
	if _want("plain"):
		await _plain()
		await _film("plain" + _suffix())
	save.end_sandbox()
	quit(0)


## The Results after the made-up run (a fall or two when `died`).
func _story(died: bool) -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var save = root.get_node("Save")
	run.start(reg.character("drifter"), reg.map("red_canyon"))
	for pair in [["revolver", 5], ["boomstick", 4], ["molotov", 3], ["big_mouth", 3], ["turret_buddy", 2]]:
		run.add_weapon(reg.weapon(str(pair[0])), int(pair[1]))
	run.end()
	# a fresh save (the PC's own may have these unlocks done already; the sandbox puts it back)
	save.set("data", save.call("_default"))
	save.call("_migrate_seen")
	var qt = load("res://core/systems/QuestTracker.gd")
	load("res://tools/results_story.gd").fill(run, save, qt, died)
	_curves(run.timeline, run.damage_by_weapon)
	await _open()


## The made-up run's sources their own damage curves (results_story.gd gives none): each source's damage from the
## moment it joined to the end, shaped like the run's whole damage curve, sampled every RunTimeline.SRC_STEP seconds.
func _curves(tl, table: Dictionary) -> void:
	var step: float = load("res://core/systems/RunTimeline.gd").SRC_STEP
	var dmg: PackedFloat32Array = tl.damage
	var d_at := func(t: float) -> float:
		var k := clampi(int(t) - 1, 0, dmg.size() - 1)
		return 0.0 if t <= 0.0 else float(dmg[k])
	for id in tl.sources:
		var fin := float(table.get(id, 0.0))
		var j: float = tl.joined(str(id))
		if is_inf(j):
			continue
		var d0: float = d_at.call(j)
		var span: float = maxf(float(d_at.call(tl.t)) - d0, 1.0)
		var c := PackedFloat32Array()
		var t := step
		while t < tl.t:
			c.append(0.0 if t < j else fin * clampf((float(d_at.call(t)) - d0) / span, 0.0, 1.0))
			t += step
		tl.sources[id]["curve"] = c


## The Results of a run with no story (a tool's): the damage table by hand, nothing recorded.
func _plain() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var save = root.get_node("Save")
	run.start(reg.character("astro"), reg.map("red_canyon"))
	run.add_weapon(reg.weapon("gravity_gun"), 4)
	run.end()
	save.set("data", save.call("_default"))
	save.call("_migrate_seen")
	save.call("mark_hint", "results")
	run.set("elapsed", 312.0)
	run.set("kills", 420)
	run.set("run_gold", 640)
	run.set("damage_by_weapon", {"gravity_gun": 5200.0, "molotov": 900.0, "burn": 140.0, "supply_drop": 2300.0, "blast": 60.0})
	run.set("last_result", {"gold_before": 1200, "banked": 640, "lost": 0, "strongbox": 0, "prev_best": {}})
	await _open()


func _open() -> void:
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var up = current_scene
		if up and up.has_method("part_name"):
			break
	# the show's clock is stepped by hand from here; the board's own slide-in (real time) settles first
	var rs = current_scene
	rs.set_process(false)
	if rs.get("_chart"):
		rs._chart.set_process(false)
	await _wait(0.45)


## Steps the show and saves a frame after each step until the show is over (or MAX_SHOW show seconds).
func _film(tag: String) -> void:
	var dir := _out.path_join(tag)
	DirAccess.make_dir_recursive_absolute(dir)
	var rs = current_scene
	var lines: Array = []
	var t := 0.0
	var n := 0
	await _frame(rs, dir, n, t, lines)
	while t < MAX_SHOW:
		var part: String = rs.call("part_name")
		if int(rs.call("sequence")) >= 3:
			break
		var dt := float(STEP.get(part, 0.25))
		# never past the start of the next part in one step (so a 0.3 s pop is not crossed by a 0.5 s gold step)
		var parts: Array = rs.get("_parts")
		var i: int = rs.get("_part")
		if i < parts.size():
			var pt: float = rs.get("_pt")
			var left: float = (-pt) if pt < 0.0 else float(parts[i]["dur"]) - pt
			dt = minf(dt, maxf(left, 0.0) + 0.001)
		rs._process(dt)
		if rs.get("_chart"):
			rs._chart._process(dt)
		t += dt
		n += 1
		await _frame(rs, dir, n, t, lines)
	# the end, settled
	await _wait(0.3)
	n += 1
	await _frame(rs, dir, n, t, lines)
	var f := FileAccess.open(dir.path_join("frames.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("p74_results_shot: %s %d frames, show %.2f s (planned %.2f s)" % [tag, n + 1, t, float(rs.call("show_time"))])


func _frame(rs, dir: String, n: int, t: float, lines: Array) -> void:
	await process_frame
	await process_frame
	var part: String = rs.call("part_name")
	var frac: float = rs.call("part_frac")
	var name := "f%03d_%s_%03d" % [n, part if part != "" else "end", int(round(frac * 100.0))]
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	# the chart block's pop: its group while it pops, the panel once it has landed
	var pop = rs.get("_pop_group")
	var pa: float = pop.self_modulate.a if pop else 1.0
	var ps: float = pop.scale.x if pop else 1.0
	var rows: Array = rs.get("_rows")
	var shown := 0
	for e in rows:
		if (e["row"] as Control).modulate.a > 0.01:
			shown += 1
	lines.append("%s t=%.2f seq=%d part=%s %.2f panel a=%.2f s=%.3f rows shown %d/%d kills=%s damage=%s scroll=%d" % [name, t,
		int(rs.call("sequence")), part, frac, pa, ps, shown, rows.size(), rs._kills_num.text, rs._dmg_num.text,
		rs.scroll.scroll_vertical])
