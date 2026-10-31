## Pass 116, lane MAP: the three painted barrels (EXP, EXP + Coins, Power-up) side by side in front of the hero in each
## stage's look (Sundown, Nightfall, Blood Moon), like Garry's comparison board, then one breaking (a few frames of its
## burst) and a close-up. The debug arena, the hero in god mode, the crowd cleared.
## Windowed:
##   GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/_p116_MAP_barrels.gd -- out=<dir>
## A watchdog quits after 180 s; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://p116_map"
var _run
var _save
var g
var _here := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		print("p116_map: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p116_map: ", name)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _frames(150)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _frames(20)
	g.enemies.kill_all(false)
	await _frames(30)
	await _lay_out()
	for s in [0, 1, 2]:
		_look(s)
		await _frames(2)
		await _shot("barrels_stage%d" % (s + 1))
	_look(0)
	# one breaking: the hero steps up to the middle (EXP + Coins) one; the camera kept where it was
	g.player.global_position = _ground(_here + Vector3(0, 0, -3.5)) + Vector3(0, 0.05, 0)
	for k in 4:
		await _frames(1 if k == 0 else 5)
		await _shot("barrel_break_%d" % k)
	_save.data = keep
	quit(0)


## The three kinds three metres above the hero on the screen, 2.4 m apart (left to right: EXP, EXP + Coins, Power-up);
## every other barrel moved far off.
func _lay_out() -> void:
	var bf = g.barrels
	_here = _ground(g.player.global_position)
	var picked := [-1, -1, -1]
	for i in range(bf.pos.size()):
		var t: int = bf.light[i]
		if bf.alive[i] == 1 and picked[t] < 0:
			picked[t] = i
	print("p116_map: kinds at ", picked, " counts ", _counts(bf))
	for t in 3:
		var i: int = picked[t]
		if i < 0:
			continue
		var at := _ground(_here + Vector3(-2.4 + 2.4 * t, 0, -4.5))
		bf.pos[i] = at
		bf._mm_of(t).set_instance_transform(bf._index_in[i], bf.instance_transform(i))
		var props = g.map.get("props")
		if props and i < bf.shadows.size() and bf.shadows[i] >= 0:
			props.move_shadow(bf.shadows[i], at)
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	if g.camera:
		g.camera.snap_to(g.player)
	await _frames(20)
	# the hero stands still and nothing walks into the barrels
	g.enemies.kill_all(false)


func _counts(bf) -> Array:
	var n := [0, 0, 0]
	for i in range(bf.pos.size()):
		n[bf.light[i]] += 1
	return n


func _look(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)
	var m = g.map
	if m.get("_hell_tween") and m._hell_tween:
		m._hell_tween.kill()
	if m.has_method("_apply_hell"):
		m._apply_hell(1.0 if sl.hell_of(sl._timeline(), s) else 0.0)
