## Pass 79, lane MUT: the mutation level-up as the player sees it. Windowed, silent, at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p79_MUT_shots.gd -- out=<dir> [inset=130]
## One run of Red Canyon, the Drifter with the Revolver and the Boomstick in god mode, the director stopped:
##   01_hud_plain        the HUD with nothing due
##   02_hud_mutation     an offer due: the plum LV plate and MUTATION NEXT at the XP rail's end
##   03_levelup_reel     the level-up comes: the mutation offer's reel spinning
##   04_levelup_landed   the reel landed: "Level N! Pick a mutation", the weapon and its path cards
##   05_hud_after        picked: the mark gone
## Every wait is bounded and a watchdog quits after 120 s. The save is never written (godot.sh keeps the PC's aside).
extends SceneTree

var _out := "user://p79_mut_shots"
var _inset := -1
var _suffix := ""
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	if _inset >= 0:
		_suffix = "_inset%d" % _inset
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("p79_mut: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + _suffix + ".png"))
	print("p79_mut: ", n + _suffix)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	var inset_was: int = st.top_inset
	if _inset >= 0:
		st.top_inset = _inset
	var dbg_was: bool = st.debug_mode
	st.debug_mode = false
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false}))
	f.close()
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("director") != null and g.get("hud") != null:
			break
	await _wait(2.0)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	# some XP on the bar so the rail shows its fill
	_run.add_xp(_run.xp_to_next() * 0.55)
	await _wait(1.0)
	await _shot("01_hud_plain")
	_run.mutlvl_due = 1
	_run.mutation_due_changed.emit()
	await _wait(0.5)
	print("p79_mut: mark on = ", g.hud.mutation_mark_on())
	await _shot("02_hud_mutation")
	_run.add_xp(_run.xp_to_next() - _run.xp + 0.01)
	await _wait(0.25)
	await _shot("03_levelup_reel")
	for k in range(240):
		await process_frame
		if not g.cards.reel_running():
			break
	await _wait(1.2)
	await _shot("04_levelup_landed")
	if g.cards.visible and not (g.cards._offer as Array).is_empty():
		g.cards._pick(g.cards._offer[0])
	await _wait(1.0)
	if g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()
	await _wait(1.2)
	print("p79_mut: mark on after = ", g.hud.mutation_mark_on(), " mutation_levels = ", _run.mutation_levels, " level = ", _run.level)
	await _shot("05_hud_after")
	st.top_inset = inset_was
	st.debug_mode = dbg_was
	_save.data = keep
	print("p79_mut: done")
	quit(0)
