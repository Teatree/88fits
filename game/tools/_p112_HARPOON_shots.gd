## Pass 112 (lane ENEMY): the harpooner's chain breaking, frame by frame, in the debug arena (the hero in god mode, no
## weapons): the harpooner hooks him, the rope holds a moment, then it ends
##   timeout  its time runs out (Game.tether_t set to nothing): the chain snaps, the halves whip and fall, the hook drops
##   death    the harpooner is killed while it holds him: the same break, its hand's half lying where it fell
## and a Nightfall frame of each break. Half-size whole frames (<case>_f<tick>.png) and full-size crops round the break
## (<case>_crop_f<tick>.png).
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p112_HARPOON_shots.gd -- out=<dir> [only=timeout,death]
## A watchdog quits after 200 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://p112_harpoon"
var _only: PackedStringArray = []
var _run
var _save
var g
var _here := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	seed(112)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p112_harpoon: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _on(s: String) -> bool:
	return _only.is_empty() or _only.has(s)


func _frames(n: int) -> void:
	for k in range(n):
		if g != null and g.player:
			g.player.velocity = Vector3.ZERO
		await process_frame


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _shot(name: String, at: Vector3, crop: int) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if crop <= 0:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		img.save_png(_out.path_join("%s.png" % name))
		return
	var sp: Vector2 = g.camera.camera.unproject_position(at)
	var x := clampi(int(sp.x) - crop / 2, 0, maxi(img.get_width() - crop, 0))
	var y := clampi(int(sp.y) - crop / 2, 0, maxi(img.get_height() - crop, 0))
	img.get_region(Rect2i(x, y, mini(crop, img.get_width()), mini(crop, img.get_height()))).save_png(_out.path_join("%s.png" % name))


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
	_here = _ground(g.player.global_position)
	if _on("timeout"):
		await _case("timeout")
	if _on("death"):
		await _case("death")
	_save.data = keep
	quit(0)


func _stage(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)


## A hook-in, the rope held 40 ticks, then the break (`how`): frames of the break every 2 ticks.
func _case(how: String) -> void:
	g.projectiles.clear_all()
	g.enemies.kill_all(false)
	g.camera.zoom_override = 1.2
	await _frames(20)
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	_stage(0)
	var em = g.enemies
	var h: int = em.spawn("harpoon_troglodyte", _ground(_here + Vector3(6.0, 0, -11.0)), null, 1.0, 400.0)
	em.rise_t[h] = 1.0
	em.vspecial[h] = 0
	em.cooldown[h] = 0.0
	em._rebuild_grid()
	var n := 0
	while n < 360 and int(g.tether_i) < 0:
		await _frames(1)
		n += 1
	if int(g.tether_i) < 0:
		print("p112_harpoon: %s never hooked" % how)
		return
	await _frames(40)
	var ch = g.harpoon_chain()
	var mid: Vector3 = (ch.last_a + ch.last_b) * 0.5
	_shot("%s_before" % how, mid, 0)
	var breaks0: int = int(ch.breaks)
	if how == "timeout":
		g.tether_t = 0.0
	else:
		em.damage(h, 1.0e9, "probe")
	var shots := 0
	for k in range(70):
		await _frames(1)
		if k % 2 == 0 and shots < 30:
			_shot("%s_f%02d" % [how, k], mid, 0)
			_shot("%s_crop_f%02d" % [how, k], mid + Vector3(0, 0.5, 0), 720)
			shots += 1
		if k == 6:
			paused = true
			_stage(1)
			await _frames(2)
			_shot("%s_night" % how, mid, 0)
			_stage(0)
			await _frames(2)
			paused = false
		if not ch.breaking() and k > 4:
			break
	print("p112_harpoon: %s breaks %d, links at the end %d" % [how, int(ch.breaks) - breaks0, int(ch.links_drawn)])
