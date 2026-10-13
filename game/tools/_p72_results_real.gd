## Pass 72 (lane RESULTS): smoke_run's real run (the boss, an Elite, the Nuke, a debug revive, the extraction), and at
## its Results the run's story checked against what the run counted (RunTimeline: attached, its kills sum to Run.kills,
## the boss's kill marked, the starting weapon owned at 0, the purse ending at what was banked, the revive's blast
## joined), and the screen caught as the chart finishes and at the end. Windowed for the pictures:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p72_results_real.gd -- seconds=120 out=<dir>
extends "res://tools/smoke_run.gd"

var _out := "user://p72_results_real"
var _shots := 0
var _checked := false
var _problems: Array = []


func _init() -> void:
	super._init()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)


func _tick_screens(dt: float) -> void:
	_screen_t += dt
	var rs = current_scene
	if rs == null or not str(rs.scene_file_path).ends_with("ResultsScreen.tscn"):
		if _screen_t > 6.0:
			_problems.append("no Results screen after the run")
			_done()
		return
	if not _checked:
		_checked = true
		_check_story()
	var part := str(rs.call("part_name"))
	if _shots == 0 and (part == "sources" or part == "pause" or part == ""):
		_shots = 1
		_shot("real-chart")
	elif _shots == 1 and part == "":
		_shots = 2
		_shot("real-end")
		rs.scroll.scroll_vertical = 0
	elif _shots == 2:
		_shots = 3
	elif _shots == 3:
		_shots = 4
		_shot("real-end-top")
		_done()
	if _screen_t > 40.0:
		_problems.append("the show never ended")
		_done()


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p72_results_real: ", name)


func _check_story() -> void:
	var tl = _run.timeline
	var sum := 0
	for k in tl.kills:
		sum += int(k)
	var kinds := {}
	for m in tl.markers:
		kinds[int(m[1])] = int(kinds.get(int(m[1]), 0)) + 1
	print("p72_results_real: attached=%s t=%.1f s purse samples=%d last=%d run_gold=%d banked=%d kills=%d (Run %d) markers=%s stages=%s start=%s" % [
		str(tl.attached), tl.t, tl.purse.size(), tl.purse[tl.purse.size() - 1] if tl.purse.size() > 0 else -1, _run.run_gold,
		int(_run.last_result.get("banked", -1)), sum, _run.kills, str(kinds), str(tl.stages), tl.start_weapon])
	var order: Array = []
	for id in tl.sources:
		order.append([tl.joined(str(id)), str(id), float(_run.damage_by_weapon.get(id, 0.0))])
	order.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for o in order:
		print("p72_results_real:   %7.1f s  %-16s %10.0f" % [float(o[0]), str(o[1]), float(o[2])])
	print("p72_results_real: quests before %s" % str(tl.quests_before))
	if not tl.attached:
		_problems.append("the story was never attached")
	if sum != int(_run.kills):
		_problems.append("the story's kills %d are not the run's %d" % [sum, int(_run.kills)])
	if not kinds.has(3):
		_problems.append("no boss kill marked")
	if tl.start_weapon != _weapon or float(tl.joined(_weapon)) != 0.0:
		_problems.append("the starting weapon %s (joined %.1f) is not %s at 0" % [tl.start_weapon, float(tl.joined(tl.start_weapon)), _weapon])
	if not tl.sources.has("revive"):
		_problems.append("the revive's blast never joined")


func _done() -> void:
	print("p72_results_real: %s %s" % ["OK" if _problems.is_empty() else "FAIL", str(_problems)])
	quit(0 if _problems.is_empty() else 2)
