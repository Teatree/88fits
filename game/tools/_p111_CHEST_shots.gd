## Pass 111 (lane CHEST) capture: a map chest laid off the screen with the HUD's CHEST tag pointing at it, the same chest
## once the hero walked up to it, then a power-up (the Nuke, forced) thrown out of it on its hop and lying where it landed.
## The debug arena (no crowd), the hero in god mode; the chest is laid by WorldChests.spawn_now (the run's own rule: off
## the camera's view by the map's margin), so the first shot proves it is not on the screen.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p111_CHEST_shots.gd -- out=<dir>
## A watchdog quits after 120 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

const CROP := 900
var _out := "user://p111_chest"
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	seed(111)
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("p111_chest: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String, at: Vector3 = Vector3.INF) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	if at != Vector3.INF:
		var sp: Vector2 = g.camera.camera.unproject_position(at + Vector3(0, 1.0, 0))
		var w := img.get_width()
		var h := img.get_height()
		var x := clampi(int(sp.x) - CROP / 2, 0, maxi(w - CROP, 0))
		var y := clampi(int(sp.y) - CROP / 2, 0, maxi(h - CROP, 0))
		img.get_region(Rect2i(x, y, mini(CROP, w), mini(CROP, h))).save_png(_out.path_join(name + "_crop.png"))
	print("p111_chest: ", name)


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
	await _frames(20)
	g.enemies.kill_all(false)
	await _frames(30)
	var pm = g.pickups
	var wc = pm.world_chests()
	# the map's own rule: a spot off the camera's view by its margin, 25-45 m out
	var ok: bool = wc.spawn_now(pm)
	await _frames(4)
	if not ok:
		print("p111_chest: no spot found")
		_save.data = keep
		quit(1)
		return
	var c = pm.chests[pm.chests.size() - 1]
	var at: Vector3 = c.global_position
	var hero: Vector3 = g.player.global_position
	var planes: Array = Array(g.camera.camera.get_frustum())
	print("p111_chest: chest at %s, %.1f m from the hero, seen=%s, on_screen(rig)=%s" % [at, Vector2(at.x - hero.x, at.z - hero.z).length(),
		WorldChests.seen(planes, at, 0.0), g.camera.on_screen(at)])
	await _frames(10)
	await _shot("p111-chest-offscreen-pointer")
	# the hero walks up: put him 7 m south of it (the chest up the screen), the camera with him
	var dir := Vector3(0, 0, -1)
	var near := at - dir * 7.0
	near.y = g.map.height_at(near.x, near.z)
	g.player.global_position = near
	if g.camera.has_method("snap_to"):
		g.camera.snap_to(g.player)
	await _frames(40)
	await _shot("p111-chest-found", at)
	# opened (by hand, so the reel's modal does not cover it), the Nuke thrown out of it, frame by frame
	c.opened = true
	c.open_anim()
	var stand := at - dir * 1.0
	stand.y = g.map.height_at(stand.x, stand.z)
	g.player.global_position = stand
	if g.camera.has_method("snap_to"):
		g.camera.snap_to(g.player)
	await _frames(2)
	var p = pm.throw_chest_powerup(at, false, "nuke")
	print("p111_chest: thrown to %s, %.2f m from the chest" % [p._to, Vector2(p._to.x - at.x, p._to.z - at.z).length()])
	var mid: Vector3 = (at + p._to) * 0.5
	for k in [8, 16, 24, 32]:
		await _frames(8)
		await _shot("p111-powerup-hop-%02d" % k, mid)
	await _frames(40)
	await _shot("p111-powerup-landed", mid)
	print("p111_chest: landed=%s taken=%s, %.2f m from the hero" % [not p.flying, p.taken, Vector2(p.global_position.x - stand.x, p.global_position.z - stand.z).length()])
	_save.data = keep
	quit(0)
