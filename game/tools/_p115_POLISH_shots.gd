## Pass 115, lane POLISH: captures of the dust devil (a bigger, longer, thinner tornado that throws higher) and the
## Beehive's Pollen flowers (bigger, gently animated), in the game's own camera and portrait framing. The debug arena, the
## hero in god mode, each stage's look shown before its frames.
##   devil    the map's dust devil (DustDevils.call_one with the map's own numbers): formed with skeletons caught in it,
##            then the hero walked into its ring and thrown (his height and a creature's ride logged), on Sundown and
##            Nightfall (looks=0,1)
##   flowers  three Pollen flowers grown round the hero (the Killer Bees with Pollen held) and three at the field's own
##            distance, on all three stage looks; a few frames apart so the sway and pulse show
## Windowed (a watchdog quits after 300 s; every wait is bounded):
##   bash tools/godot.sh --audio-driver Dummy --resolution 540x1170 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p115_POLISH_shots.gd -- out=<dir> [what=devil,flowers] [looks=0,1,2] [tag=after]
extends SceneTree

var _out := "user://p115_polish"
var _what: Array = ["devil", "flowers"]
var _looks: Array = []
var _tag := "now"
var _run
var _save
var g
var _here := Vector3.ZERO
var _log: FileAccess


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("what="):
			_what = Array(a.substr(5).split(",", false))
		elif a.begins_with("looks="):
			_looks = []
			for s in a.substr(6).split(",", false):
				_looks.append(int(s))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	seed(115)
	create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("p115_polish: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("%s_%s.png" % [_tag, name]))
	print("p115_polish: ", name)


func _note(s: String) -> void:
	print("p115_polish: ", s)
	if _log:
		_log.store_line(s)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	_log = FileAccess.open(_out.path_join("%s_log.txt" % _tag), FileAccess.WRITE)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
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
	_here = _ground(g.player.global_position)
	if g.get("hud") and g.hud:
		g.hud.visible = false
	for what in _what:
		match what:
			"devil":
				await _devil(_looks if not _looks.is_empty() else [0, 1])
			"flowers":
				await _flowers(_looks if not _looks.is_empty() else [0, 1, 2])
	_save.data = keep
	if _log:
		_log.close()
	quit(0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _look(s: int) -> void:
	load("res://core/systems/StageLook.gd").of(g).show_stage(s, 0.0)


func _devil(looks: Array) -> void:
	var dds = g.map.get_node_or_null("DustDevils")
	if dds == null:
		_note("no DustDevils on the map")
		return
	var c: Dictionary = dds.cfg
	_note("devil cfg: life %s radius %s size %s opacity %s toss %s lift %s lift_height %s" % [c.get("life"), c.get("radius"),
		c.get("size", "-"), c.get("opacity", "-"), c.get("toss"), c.get("lift"), c.get("lift_height", "-")])
	for s: int in looks:
		_look(s)
		g.enemies.kill_all(false)
		g.player.global_position = _here + Vector3(0, 0.5, 0)
		await _frames(15)
		var dd = dds.call_one(_ground(_here + Vector3(-3.0, 0, -6.5)), Vector3(1, 0, 0.1))
		if dd == null:
			_note("no devil")
			return
		_note("devil life rolled %.1f s" % dd.life)
		dd.speed = 0.3
		var made: Array = []
		for k in range(10):
			var a := float(k) / 10.0 * TAU
			made.append(g.enemies.spawn("skeleton", _ground(dd.global_position + Vector3(cos(a), 0, sin(a)) * (3.6 + float(k % 3)))))
		await _frames(40)
		await _shot("devil_s%d_forming" % (s + 1))
		await _frames(170)
		await _shot("devil_s%d_full" % (s + 1))
		# the creatures' ride: the highest one up
		var top := 0.0
		for k in range(60):
			await process_frame
			for i: int in made:
				if i >= 0 and g.enemies.alive[i] == 1:
					top = maxf(top, g.enemies.lift_h[i])
			if k == 20:
				await _shot("devil_s%d_lifting" % (s + 1))
		_note("stage %d: a skeleton rode up to %.2f m (size %.2f)" % [s + 1, top, g.enemies.size[made[0]] if made[0] >= 0 else 0.0])
		# the hero walks into its ring and is thrown
		g.enemies.kill_all(false)
		var p0 := _ground(dd.global_position + Vector3(dd.reach() * 0.6, 0, 0.6))
		g.player.global_position = p0 + Vector3(0, 0.05, 0)
		g.player.velocity = Vector3.ZERO
		var y0: float = p0.y
		var peak := 0.0
		var shot_taken := false
		for k in range(90):
			await process_frame
			var h: float = g.player.global_position.y - y0
			if h > peak:
				peak = h
			if not shot_taken and h > 1.0:
				shot_taken = true
				await _shot("devil_s%d_hero_thrown" % (s + 1))
		_note("stage %d: the hero was thrown %.2f m up (tosses %d)" % [s + 1, peak, dd.tosses])
		dd.end_now()
		await _frames(150)
		g.enemies.kill_all(false)
		await _frames(10)


func _flowers(looks: Array) -> void:
	_run.debug_set_item("weapon", "hornet_nest", 5)
	_run.debug_set_item("mutation", "pollen", 1)
	_run.build_changed.emit()
	await _frames(30)
	var ff = load("res://core/systems/FlowerField.gd").ensure(g)
	if ff == null:
		_note("no flower field")
		return
	await _frames(5)
	# none of its own: only the ones placed here
	ff.set("_next", 9999.0)
	for fl in ff.flowers:
		if is_instance_valid(fl["node"]):
			(fl["node"] as Node).queue_free()
	ff.flowers.clear()
	await _frames(5)
	var near := [Vector3(-2.4, 0, -2.6), Vector3(2.6, 0, -3.4), Vector3(0.4, 0, 3.0)]
	# the field's own distances (10-18 m): the ones up the screen are what a player has to spot
	var far := [Vector3(-3.5, 0, -10.0), Vector3(4.0, 0, -12.5), Vector3(-6.0, 0, 9.0)]
	var hp: Vector3 = _ground(g.player.global_position)
	_note("hero at %s (arena start %s)" % [str(hp), str(_here)])
	for p: Vector3 in near + far:
		ff.grow_at(_ground(hp + p), true)
	_note("flowers: %d grown, heights %s" % [ff.flowers.size(), str(ff.flowers.map(func(x) -> float: return snappedf(float(x["size"]), 0.01)))])
	await _frames(60)
	for s: int in looks:
		_look(s)
		await _frames(20)
		for k in range(4):
			await _shot("flowers_s%d_f%d" % [s + 1, k])
			await _frames(14)
	# a close crop round the near ones, frame by frame (the sway and the pulse)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	_look(0)
	await _frames(20)
	for k in range(6):
		await _frames(10)
		var img := root.get_viewport().get_texture().get_image()
		if cam:
			# the camera's coordinates are the viewport's; the picture may be the window's size
			var vr := root.get_viewport().get_visible_rect().size
			var sc := Vector2(float(img.get_width()) / maxf(vr.x, 1.0), float(img.get_height()) / maxf(vr.y, 1.0))
			var sp: Vector2 = cam.unproject_position(g.player.global_position + Vector3(0, 0.4, -1.0)) * sc
			var w := 360
			var x := clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
			var y := clampi(int(sp.y) - w / 2, 0, img.get_height() - w)
			img = img.get_region(Rect2i(x, y, w, w))
		img.save_png(_out.path_join("%s_flowers_crop_f%d.png" % [_tag, k]))
	print("p115_polish: flowers crops")
