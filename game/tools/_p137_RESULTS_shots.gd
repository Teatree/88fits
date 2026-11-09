## Pass 137 (lane RESULTS): the Results' gold count and the bounty's pour captured at set moments, the show stepped by
## hand (the screen's own clock off, so a windowed capture's capped frame step does not matter):
## GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##   --log-file <f> --script res://tools/_p137_RESULTS_shots.gd -- out=<abs dir> [only=small,big,bounty]
## small: 35 coins (the count half way, its snap); big: 4,800 coins (30 %, 70 %, 98 % of the climb, the snap, after it);
## bounty: 640 coins and a paid bounty of 1,500 (its coins in flight, near the last, the snap and the purse line's
## flourish). The PC save is kept and put back.
extends SceneTree

const STEP := 1.0 / 60.0

var _out := "user://p137_results"
var _only: Array = []
var _save
var _run
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p137_results: ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_keep = _save.data.duplicate(true)
	# a watchdog: never hold the Godot lock past this
	create_timer(200.0).timeout.connect(func():
		print("p137_results: watchdog")
		_save.data = _keep
		quit(2))
	var reg = root.get_node("Registry")
	if _want("small"):
		var rs = await _open(reg, 35, {})
		await _to(rs, "gold", 0.5)
		await _shot("small_1_half")
		await _to(rs, "gold", 1.0)
		await _shot("small_2_snap")
		await _frames(8)
		await _shot("small_3_after")
	if _want("big"):
		var rs = await _open(reg, 4800, {})
		for fr in [0.3, 0.7, 0.98]:
			await _to(rs, "gold", fr)
			await _shot("big_%02d" % int(fr * 100.0))
		await _to(rs, "gold", 1.0)
		await _shot("big_snap_0")
		await _frames(5)
		await _shot("big_snap_1")
		await _frames(25)
		await _shot("big_snap_2")
	if _want("bounty"):
		var rec := {"name": "Bounty of the West", "text": "Kill 60 Skeletons", "have": 60, "need": 60, "done": true,
			"paid": 1500, "reward": 1500}
		var rs = await _open(reg, 640, rec)
		await _to(rs, "bounty", 1.0)
		await _shot("bounty_0_stamped")
		for fr in [0.2, 0.45, 0.7]:
			await _to(rs, "bounty_pay", fr)
			await _shot("bounty_pay_%02d" % int(fr * 100.0))
		await _to(rs, "bounty_pay", 0.83)
		await _shot("bounty_pay_snap")
		await _frames(6)
		await _shot("bounty_pay_snap_1")
		await _frames(30)
		await _shot("bounty_pay_after")
	_save.data = _keep
	print("p137_results: done")
	quit(0)


## The Results for a plain Drifter run that banked `banked` onto a purse of 1,200, with the bounty `rec`; its own clock off.
func _open(reg, banked: int, rec: Dictionary) -> Node:
	_run.start(reg.character("drifter"), reg.map("red_canyon"))
	_run.end()
	(_save.data["hints_seen"] as Array).append("results")
	_run.damage_by_weapon = {"revolver": 5200.0, "molotov": 900.0}
	_run.last_result = {"gold_before": 1200, "banked": banked, "lost": 0, "strongbox": 0, "prev_best": {}, "bounty": rec}
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _frames(3)
	var rs = current_scene
	rs.set_process(false)
	# the board's slide-in and the backdrop settle (ScreenBase's own _process still runs through the stepped clock)
	await _frames(20)
	return rs


## Steps the show STEP at a time (a frame between steps, so tweens and the coins run) until part `part` is at `frac`
## or past it (bounded).
func _to(rs, part: String, frac: float) -> void:
	var guard := 0
	while guard < 1200:
		var now: String = rs.call("part_name")
		var parts: Array = (rs.get("_parts") as Array).map(func(p): return str(p["name"]))
		var at_part: int = parts.find(part)
		var idx: int = int(rs.get("_part"))
		if now == "" or idx > at_part or (now == part and float(rs.call("part_frac")) >= frac and frac < 1.0):
			return
		rs.call("_process", STEP)
		await process_frame
		guard += 1
