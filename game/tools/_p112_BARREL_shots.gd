## Pass 112 (lane BARREL) capture: a barrel laid again off the screen (BarrelSpawns.spawn_now, the run's own rule) with the
## hero where he stood, the same barrel once he walked up to it, then a power-up thrown out of it as he smashes it, frame
## by frame, and lying where it landed. The debug arena (no crowd), the hero in god mode; the black kind's power-up chance
## is set to 1 in memory for the shot (the map file is not touched).
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p112_BARREL_shots.gd -- out=<dir>
## A watchdog quits after 120 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

const CROP := 900
var _out := "user://p112_barrel"
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	seed(112)
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("p112_barrel: watchdog quit")
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
		var sp: Vector2 = g.camera.camera.unproject_position(at + Vector3(0, 0.6, 0))
		var w := img.get_width()
		var h := img.get_height()
		var x := clampi(int(sp.x) - CROP / 2, 0, maxi(w - CROP, 0))
		var y := clampi(int(sp.y) - CROP / 2, 0, maxi(h - CROP, 0))
		img.get_region(Rect2i(x, y, mini(CROP, w), mini(CROP, h))).save_png(_out.path_join(name + "_crop.png"))
	print("p112_barrel: ", name)


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
	var bf = g.barrels
	# a black one comes back (the run's spot rule: off the camera's view by its margin, 20-40 m out)
	var clock = bf.respawn_clock()
	var at: Vector3 = clock.find_spot(bf)
	if at == Vector3.INF or not bf.respawn_at(at, true):
		print("p112_barrel: no spot or slot")
		_save.data = keep
		quit(1)
		return
	var hero: Vector3 = g.player.global_position
	var planes: Array = Array(g.camera.camera.get_frustum())
	print("p112_barrel: barrel back at %s, %.1f m from the hero, seen=%s, on_screen(rig)=%s" % [at, Vector2(at.x - hero.x, at.z - hero.z).length(),
		BarrelSpawns.seen(planes, at, 0.0), g.camera.on_screen(at)])
	await _frames(10)
	await _shot("p112-barrel-back-offscreen")
	# he walks up: 7 m south of it (the barrel up the screen), the camera with him
	var near := at + Vector3(0, 0, 7.0)
	near.y = g.map.height_at(near.x, near.z)
	g.player.global_position = near
	if g.camera.has_method("snap_to"):
		g.camera.snap_to(g.player)
	await _frames(40)
	await _shot("p112-barrel-found", at)
	# he smashes it, its power-up chance 1 for the shot (in memory only)
	var tl = g.director.timeline if g.director else _run.map.timeline
	var keep_block: Dictionary = tl.barrels
	var block: Dictionary = keep_block.duplicate(true)
	var black: Dictionary = block.get("black", {})
	black["powerup_chance"] = 1.0
	black["powerups"] = [{"id": "nuke", "weight": 1}]
	block["black"] = black
	tl.barrels = block
	var stand := at + Vector3(0, 0, 1.0)
	stand.y = g.map.height_at(stand.x, stand.z)
	g.player.global_position = stand
	if g.camera.has_method("snap_to"):
		g.camera.snap_to(g.player)
	var pk = g.pickups
	for k in range(30):
		await process_frame
		if pk.specials.size() > 0:
			break
	tl.barrels = keep_block
	var p = null
	for s in pk.specials:
		if is_instance_valid(s) and bool(s.get("no_magnet")):
			p = s
	if p == null:
		print("p112_barrel: no power-up came out")
		_save.data = keep
		quit(1)
		return
	print("p112_barrel: thrown to %s, %.2f m from the barrel" % [p._to, Vector2(p._to.x - at.x, p._to.z - at.z).length()])
	var mid: Vector3 = (at + p._to) * 0.5
	for k in [6, 14, 22, 30]:
		await _frames(8)
		await _shot("p112-powerup-hop-%02d" % k, mid)
	await _frames(40)
	await _shot("p112-powerup-landed", mid)
	print("p112_barrel: landed=%s taken=%s, %.2f m from the hero" % [not p.flying, p.taken, Vector2(p.global_position.x - stand.x, p.global_position.z - stand.z).length()])
	_save.data = keep
	quit(0)
