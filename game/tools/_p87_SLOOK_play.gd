## Pass 87, lane SLOOK: captures of play in each stage's look. For each stage k: a stage run (the launch's `stage`, a
## fresh Drifter, god mode), a thumb walking him about; at `at` seconds a frame, then the stage's own creatures brought
## round him (stage 3: its hellhounds and imps too, which come late in a real run) with a red danger ring and a disc
## from the creatures' own telegraphs, and a second frame. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p87_SLOOK_play.gd -- out=<dir> [stages=1,2,3] [at=14]
## A watchdog quits after 280 s; every wait is bounded.
extends SceneTree

var _out := "user://p87_slook_play"
var _stages: Array = [1, 2, 3]
var _at := 14.0
var _run
var _save
var g
var _t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("stages="):
			_stages = []
			for s in a.substr(7).split(",", false):
				_stages.append(int(s))
		elif a.begins_with("at="):
			_at = float(a.substr(3))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(280.0, true, false, true).timeout.connect(func() -> void:
		print("p87_slook_play: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p87_slook_play: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	for s: int in _stages:
		await _play(s)
	_save.data = keep
	quit(0)


func _play(s: int) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "map": "red_canyon", "map_seed": 7, "stage": s, "analytics": false}))
	f.close()
	_save.data["runs_started"] = 1
	change_scene_to_file("res://game/Game.tscn")
	g = null
	for k in range(900):
		await process_frame
		var c = current_scene
		if c and c.has_method("open_pause") and c.get("player") != null and c.player.is_inside_tree():
			g = c
			break
	if g == null:
		printerr("p87_slook_play: stage %d did not start" % s)
		return
	g.player.god = true
	_t = 0.0
	var shot1 := false
	while _t < _at + 4.0:
		await process_frame
		_t += root.get_process_delta_time()
		_drive()
		if not shot1 and _t >= _at:
			shot1 = true
			await _shot("play_s%d_a" % s)
			_bring(s)
	await _shot("play_s%d_b" % s)
	print("p87_slook_play: stage %d clock %.0f, stage clock %.0f, alive %d, hell %.2f" % [s, _run.elapsed, _run.stage_clock() if _run.has_method("stage_clock") else -1.0, g.enemies.count_alive, float(g.map.get("_hell"))])


## The thumb and every screen out of the way.
func _drive() -> void:
	if g == null or not is_instance_valid(g):
		return
	if g.player and g.player.input and not g.paused:
		var inp = g.player.input
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_t * 0.6) * 90.0, -60.0 + cos(_t * 0.4) * 50.0)
	if g.cards and g.cards.visible and not g.cards._offer.is_empty() and not g.cards._picking:
		g.cards._pick(g.cards._offer[0])
	if g.get("chest_screen") and g.chest_screen and g.chest_screen.visible and not g.chest_screen._spinning:
		g.chest_screen._finish(true)
	if g.get("resume_gate") and g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()


## The stage's own crowd round the hero (its window's late rows; stage 3's hell channel too) and two telegraphs.
func _bring(s: int) -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids: Array = [["goblin", "skeleton", "lesser_scorpion"], ["werewolf", "skeleton", "fire_ant"], ["hellhound", "imp", "werewolf"]][clampi(s - 1, 0, 2)]
	for k in range(12):
		var a := TAU * float(k) / 12.0
		var p := here + Vector3(cos(a) * 6.5, 0, sin(a) * 6.5 - 1.5)
		em.spawn(str(ids[k % ids.size()]), Vector3(p.x, g.map.height_at(p.x, p.z), p.z))
	var tg = g.telegraphs
	var r := here + Vector3(-2.5, 0, -4.0)
	tg.ring(Vector3(r.x, g.map.height_at(r.x, r.z), r.z), 1.8, 6.0, Color(1.0, 0.22, 0.16), true)
	var q := here + Vector3(3.0, 0, 2.5)
	tg.hold_ring(Vector3(q.x, g.map.height_at(q.x, q.z), q.z), 1.5, Color(1.0, 0.22, 0.1, 0.9))
