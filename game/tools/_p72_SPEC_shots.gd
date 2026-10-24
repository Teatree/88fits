## Pass 72, lane SPEC: captures and a GPU A/B for the outline rule (a creature is outlined only behind scenery). Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p72_SPEC_shots.gd -- out=<dir> [mode=shots|bench] [frames=240]
## mode=shots: the debug arena, the hero in god mode with no weapon; three set pieces ahead of him: a big saguaro with a
## skeleton half behind it, a big plain creature with a skeleton behind it (and a forced special beside it), a structure
## with a skeleton behind it; specials and plain ones side by side; then a crowd of ~200 round props and structures.
## Each picture twice: "new" (the pass-72 outline, stencil 2 only) and "old" (the outline pass without its stencil test,
## the pre-pass-72 look), whole and cropped round the set pieces.
## mode=bench: the crowd of ~250 round the hero among props, frames timed with the outline pass new / old / off,
## alternating blocks (CPU frame ms, GPU ms where the renderer reports it, draw calls).
## A watchdog quits after 150 s whatever happens; every wait is bounded.
extends SceneTree

var _out := "user://p72_spec_shots"
var _mode := "shots"
var _frames := 240
var _run
var _save
var g
var _old_sil: Shader
var _new_sil: Shader
var _made: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("mode="):
			_mode = a.substr(5)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
	DirAccess.make_dir_recursive_absolute(_out)
	# the watchdog
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("p72_spec: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String, crop := Rect2i()) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	if crop.size.x > 0:
		var r := crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(_out.path_join(name + "_crop.png"))
	print("p72_spec: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	_launch({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7})
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _wait(2.0)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.4)
	g.enemies.kill_all(false)
	await _wait(0.6)
	_prepare_shaders()
	if _mode == "bench":
		await _bench()
	elif _mode == "gems":
		await _gems()
	else:
		await _shots()
	_save.data = keep
	quit(0)


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


## The outline pass as it ships (new) and the same code without its stencil test (old: pass 71's rule).
func _prepare_shaders() -> void:
	_new_sil = load("res://core/shaders/enemy_silhouette.gdshader")
	_old_sil = Shader.new()
	_old_sil.code = _new_sil.code.replace("stencil_mode read, compare_less_or_equal, 4;", "")  # pass 105: the outline reads 4 <= the stencil


func _set_outline(which: String) -> void:
	var em = g.enemies
	for t: Dictionary in em.types:
		var mat: ShaderMaterial = t["mat"]
		var sil := mat.next_pass as ShaderMaterial
		if which == "off":
			if sil:
				mat.set_meta("p72_sil", sil)
				mat.next_pass = null
			continue
		if sil == null and mat.has_meta("p72_sil"):
			sil = mat.get_meta("p72_sil")
			mat.next_pass = sil
		if sil:
			sil.shader = _new_sil if which == "new" else _old_sil


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _freeze() -> void:
	var em = g.enemies
	for i: int in _made:
		if i >= 0 and em.alive[i] == 1:
			em.speed[i] = 0.0
			em.cooldown[i] = 9.0
			em.vel[i] = Vector3.ZERO


func _hold(frames: int) -> void:
	for k in range(frames):
		_freeze()
		await process_frame


func _spawn(id: String, at: Vector3, special := false, code := "") -> int:
	var em = g.enemies
	em.force_special = special
	var i: int = em.spawn(id, _ground(at), null, 1.0, 100.0, code)
	em.force_special = false
	_made.append(i)
	return i


## The set pieces ahead of the hero (-z is up the screen, away from the camera).
func _set_pieces(here: Vector3) -> void:
	var props = g.map.props
	# 1. a big saguaro, a skeleton half behind it (outlined where the cactus hides it)
	props.add("saguaro_big", _ground(here + Vector3(-4.5, 0, -5.0)), 1.0)
	_spawn("skeleton", here + Vector3(-4.2, 0, -6.0))
	# 2. a big plain beetle with a skeleton behind it (no outline over the beetle), a special skeleton beside them
	_spawn("bull_beetle", here + Vector3(0.0, 0, -4.6))
	_spawn("skeleton", here + Vector3(0.3, 0, -5.8))
	_spawn("skeleton", here + Vector3(1.6, 0, -9.0), true)
	# 3. a structure with a skeleton behind it (outlined), a special goblin half behind a big rock
	var sd = root.get_node("Registry").structure("war_drum")
	if sd and g.structures:
		g.structures._spawn(sd, _ground(here + Vector3(4.6, 0, -5.4)))
	_spawn("skeleton", here + Vector3(4.6, 0, -6.6))
	props.add("rock_big", _ground(here + Vector3(-1.8, 0, -10.0)), 1.0)
	_spawn("red_goblin", here + Vector3(-1.8, 0, -10.9), true, "RG-B")
	# 4. a creature behind a creature that is itself behind a cactus (outlined only where the cactus is nearest)
	props.add("saguaro_small", _ground(here + Vector3(-5.5, 0, -10.5)), 1.0)
	_spawn("dust_mummy", here + Vector3(-5.3, 0, -11.3))
	_spawn("skeleton", here + Vector3(-5.0, 0, -12.2))
	# plain ones beside their specials (size 1.5)
	for k in range(3):
		var id: String = ["skeleton", "fire_ant", "blue_slime"][k]
		_spawn(id, here + Vector3(-3.0 + 3.0 * k, 0, -14.5))
		_spawn(id, here + Vector3(-3.0 + 3.0 * k, 0, -16.5), true)


func _crowd(here: Vector3, n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var props = g.map.props
	for k in range(14):
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 16.0)
		props.add(["saguaro_big", "dead_tree", "rock_big", "joshua_tree"][k % 4], _ground(here + Vector3(cos(a) * r, 0, sin(a) * r - 4.0)), 1.0)
	var ids := ["skeleton", "red_goblin", "fire_ant", "blue_slime", "skeleton_knight", "goblin_runt"]
	for k in range(n):
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.5, 15.0)
		_spawn(ids[k % ids.size()], here + Vector3(cos(a) * r, 0, sin(a) * r * 1.3 - 5.0), k % 60 == 0)
	g.enemies._rebuild_grid()


func _shots() -> void:
	var here: Vector3 = g.player.global_position
	_set_pieces(here)
	g.enemies._rebuild_grid()
	# the DEBUG ARENA banner goes after a few seconds
	await _hold(150)
	var crop := Rect2i(90, 250, 900, 1100)
	for z: float in [1.0, 0.6]:
		g.camera.zoom_override = z
		for which: String in ["new", "old"]:
			_set_outline(which)
			await _hold(40)
			await _shot("pieces_z%02d_%s" % [int(round(z * 10.0)), which], crop)
	print("p72_spec: specials alive %d (cap %d), forced ones come past it" % [g.enemies.specials_alive, load("res://core/data/EnemyDef.gd").special_max_alive(g.enemies.special_defaults)])
	# the crowd
	g.enemies.kill_all(false)
	_made.clear()
	await _wait(0.4)
	_crowd(here, 200)
	g.camera.zoom_override = 1.0
	for which: String in ["new", "old"]:
		_set_outline(which)
		await _hold(40)
		await _shot("crowd_%s" % which, crop)
	# the boundary wall: the hero near the south edge, creatures on the inside of it, partly hidden by it
	g.enemies.kill_all(false)
	_made.clear()
	await _wait(0.3)
	var rr: float = float(g.map.get("arena_radius")) if g.map.get("arena_radius") != null else 60.0
	var edge := Vector3(0, 0, rr - 7.0)
	g.player.global_position = _ground(edge)
	await _wait(0.5)
	for k in range(7):
		_spawn("skeleton", Vector3(-6.0 + 2.0 * k, 0, rr - 1.25 - 0.25 * (k % 2)))
	g.enemies._rebuild_grid()
	for which: String in ["new", "old"]:
		_set_outline(which)
		await _hold(40)
		await _shot("wall_%s" % which, Rect2i(0, 1100, 1080, 820))
	# a barrel and a sign, each with a creature tucked behind it
	g.enemies.kill_all(false)
	_made.clear()
	await _wait(0.3)
	var bf = g.get("barrels")
	if bf and (bf.pos as PackedVector3Array).size() > 0:
		var bp: Vector3 = bf.pos[0]
		g.player.global_position = _ground(bp + Vector3(0, 0, 5.0))
		await _wait(0.5)
		_spawn("fire_ant", bp + Vector3(0.15, 0, -0.75))
		_spawn("skeleton", bp + Vector3(-0.5, 0, -0.9))
		g.camera.zoom_override = 0.6
		for which: String in ["new", "old"]:
			_set_outline(which)
			await _hold(40)
			await _shot("barrel_%s" % which, Rect2i(240, 300, 600, 700))
	var sf: Node = null
	for n in g.find_children("*", "", true, false):
		if n.get_script() == load("res://core/systems/SignField.gd"):
			sf = n
			break
	if sf and (sf.spots as PackedVector3Array).size() > 0:
		g.enemies.kill_all(false)
		_made.clear()
		await _wait(0.3)
		var sp: Vector3 = sf.spots[0]
		g.player.global_position = _ground(sp + Vector3(0, 0, 5.0))
		await _wait(0.5)
		_spawn("skeleton", sp + Vector3(0.3, 0, -0.8))
		_spawn("red_goblin", sp + Vector3(-0.9, 0, -0.9))
		g.camera.zoom_override = 0.6
		for which: String in ["new", "old"]:
			_set_outline(which)
			await _hold(40)
			await _shot("sign_%s" % which, Rect2i(240, 300, 600, 700))
	g.camera.zoom_override = 1.0


func _bench() -> void:
	var here: Vector3 = g.player.global_position
	_crowd(here, 250)
	g.camera.zoom_override = 1.0
	var vp: RID = root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var res := {"new": [], "old": [], "off": []}
	await _hold(60)
	for round_ in range(3):
		for which: String in ["new", "old", "off"]:
			_set_outline(which)
			await _hold(20)
			var cpu := 0.0
			var gpu := 0.0
			var draws := 0.0
			var n := _frames / 3
			var t0 := Time.get_ticks_usec()
			for k in range(n):
				_freeze()
				await process_frame
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
				draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / n
			(res[which] as Array).append([wall, cpu / n, gpu / n, draws / n])
	var alive: int = g.enemies.count_alive
	for which: String in ["new", "old", "off"]:
		var rows: Array = res[which]
		var s := [0.0, 0.0, 0.0, 0.0]
		for r: Array in rows:
			for c in range(4):
				s[c] += float(r[c]) / rows.size()
		print("p72_spec bench %s: %d creatures | frame %.3f ms, render cpu %.3f ms, gpu %.3f ms, draw calls %.0f" % [which, alive, s[0], s[1], s[2], s[3]])


## mode=gems: gems and coins lying round a cactus, a structure, a barrel-sized rock and a few creatures, so the eye can
## check they still lie on the sand and under every painting and piece of scenery (they read stencil 0 since pass 72).
func _gems() -> void:
	var here: Vector3 = g.player.global_position
	var props = g.map.props
	props.add("saguaro_big", _ground(here + Vector3(-3.5, 0, -5.0)), 1.0)
	props.add("rock_big", _ground(here + Vector3(0.5, 0, -6.5)), 1.0)
	var sd = root.get_node("Registry").structure("war_drum")
	if sd and g.structures:
		g.structures._spawn(sd, _ground(here + Vector3(4.0, 0, -5.0)))
	_spawn("skeleton", here + Vector3(-1.5, 0, -3.5))
	_spawn("bull_beetle", here + Vector3(2.0, 0, -2.5))
	var pk = g.pickups
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in range(90):
		var p := here + Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-9.0, -1.5))
		var kind: int = [0, 1, 2, 3][k % 4]
		pk.spawn(kind, _ground(p), 1.0 if kind != 3 else 1.0)
	g.camera.zoom_override = 0.7
	await _hold(60)
	await _shot("gems", Rect2i(90, 250, 900, 1100))
