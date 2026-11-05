## Pass 126 (lane DRESS): the map's dressing seen by the game's real camera in the debug arena, for one map seed: the line where
## it carries wire, a snapped pole, a leaning pole, the cart and its wheels (with creatures behind it, for their outlines), the
## graves; each in the stages named; then a wide top-down view of the whole map with the line drawn over it (red wired span,
## yellow bare span, white dot a pole, black a missing one, blue the cart and wheels, magenta the graves) and without; and the
## draw calls the dressing adds. Windowed:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --log-file <abs> --script res://tools/_p126_DRESS_shots.gd -- out=<dir> seed=7 [stages=1,2,4] [only=wired,snap,lean,cart,graves,wide]
## Frame cap and watchdog bound it; the save in memory goes back as it was (the arena's sandbox keeps it off the disk).
extends SceneTree

var A: Dictionary = {}
var g = null
var _frames := 0
var _ended := false
var _save = null
var _keep: Dictionary = {}
var _out := ""
var _seed := 7


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(A.get("out", "D:/_projects/88fits/tools/dl/p126/DRESS/shots"))
	_seed = int(A.get("seed", 7))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(float(A.get("watchdog", 280.0)), true, false, true).timeout.connect(_finish.bind(2))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > 30000:
		_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	print("dress_shots: finish ", code)
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(code)


func _wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _only(name: String) -> bool:
	return not A.has("only") or (str(A["only"]).split(",") as PackedStringArray).has(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := _out.path_join("s%d_%s.png" % [_seed, name])
	root.get_texture().get_image().save_png(path)
	print("dress_shots: ", path)


func _go(x: float, z: float) -> void:
	g.player.global_position = Vector3(x, g.map.height_at(x, z) + 0.5, z)
	g.camera.snap_to(g.player)
	await _wait(6)


func _draws() -> int:
	await _wait(4)
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _main() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	var reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	run.forced_map_seed = _seed
	run.launch_override = {"arena": true, "analytics": false}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		print("dress_shots: the arena never came up")
		_finish(1)
		return
	await _wait(20)
	var panel = g.arena_panel
	g.no_random_chests = true
	g.player.god = true
	panel.call("_clear_field")
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	var bn = g.hud.get("_banner") if g.hud else null
	if bn:
		bn.visible = false
	panel.set("_hide_hud", true)
	panel.call("set_clean", true)
	panel.get("_hint").visible = false
	var d = g.map.get("dressing")
	var line = g.map.get_node_or_null("TelephoneLine")
	print("dress_shots: map seed ", run.map_seed, " cart ", d.cart.get("pos", "none"), " flat ", d.cart.get("flat", -1.0), " sites ", d.graves.size(), " poles ", line.standing_count(), " of ", line.poles.size(), " bare ", line.bare_share())
	var tl = run.map.timeline if run.map else null
	var stages: PackedStringArray = str(A.get("stages", "1")).split(",")
	var stage_look = load("res://core/systems/StageLook.gd").call("of", g)
	for s_txt in stages:
		var stage := int(s_txt) - 1
		if tl != null and stage < tl.stage_list.size():
			panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
			stage_look.show_stage(stage, 0.0)
			panel.call("_clear_field")
			if str(tl.stage_list[stage].get("weather", "")) != "" and g.map.has_method("set_weather"):
				g.map.call("set_weather", tl.stage_list[stage].get("weather", {}), 0.01)
		await _wait(6)
		var tag := "st%d" % (stage + 1)
		if _only("wired"):
			for sp: Dictionary in line.spans:
				if bool(sp["wired"]):
					var a: Vector2 = line.poles[sp["a"]]["pos"]
					var b: Vector2 = line.poles[sp["b"]]["pos"]
					var m := a.lerp(b, 0.5)
					await _go(m.x, m.y + 3.0)
					await _shot(tag + "_wired")
					break
		for row: Array in [["snap", "snapped"], ["lean", "leaning"]]:
			if not _only(str(row[0])):
				continue
			for p: Dictionary in line.poles:
				if p["state"] == row[1]:
					var pos: Vector2 = p["pos"]
					await _go(pos.x + 1.2, pos.y + 2.4)
					await _shot(tag + "_" + str(row[0]))
					break
		# the wire's sway: the same spot twice, 0.9 s apart, at wind 1 and at wind 2.5 (lane STAGE's Dust Bowl)
		if _only("sway"):
			for sp: Dictionary in line.spans:
				if bool(sp["wired"]):
					var a2: Vector2 = line.poles[sp["a"]]["pos"]
					var b2: Vector2 = line.poles[sp["b"]]["pos"]
					var m2 := a2.lerp(b2, 0.5)
					await _go(m2.x, m2.y + 3.0)
					for w: float in [1.0, 2.5]:
						line.set_wind(w)
						await _shot(tag + "_sway%.1f_a" % w)
						var t0 := Time.get_ticks_msec()
						while Time.get_ticks_msec() - t0 < 900:
							await process_frame
						await _shot(tag + "_sway%.1f_b" % w)
					line.set_wind(1.0)
					break
		# the hero just south of a whole pole (he draws over its foot and its top) and just north of it (it draws over him)
		if _only("sort"):
			for p: Dictionary in line.poles:
				if p["state"] == "standing":
					var pos: Vector2 = p["pos"]
					await _go(pos.x + 0.1, pos.y + 0.7)
					await _shot(tag + "_sort_south")
					await _go(pos.x + 0.1, pos.y - 0.7)
					await _shot(tag + "_sort_north")
					break
		if _only("cart") and not d.cart.is_empty():
			var cp: Vector2 = d.cart["pos"]
			await _go(cp.x + 1.5, cp.y + 3.2)
			await _shot(tag + "_cart")
			# creatures round and behind the cart: their outline shows only where the cart hides them
			var came: int = panel.call("mass_spawn", [["lesser_scorpion", "", 16]], 16, {"layout": "ring", "clear_r": 2.0, "depth": 5.0, "replace": true, "seed": 3})
			panel.call("set_freeze", 1)
			var em = g.enemies
			var placed := 0
			for i in range(em.pos.size()):
				if placed >= 8 or i >= em.pos.size():
					break
				if em.alive[i]:
					var bx: float = cp.x - 1.8 + float(placed) * 0.5
					var bz: float = cp.y - 0.6 - float(placed % 2) * 0.5
					em.pos[i] = Vector3(bx, g.map.height_at(bx, bz), bz)
					placed += 1
			print("dress_shots: creatures ", came)
			await _wait(8)
			await _shot(tag + "_cart_crowd")
			panel.call("set_freeze", 0)
			panel.call("_clear_field")
			await _wait(4)
		if _only("graves") and not d.graves.is_empty():
			var best: Dictionary = d.graves[0]
			for gr: Dictionary in d.graves:
				if (gr["crosses"] as Array).size() > (best["crosses"] as Array).size():
					best = gr
			var gc: Vector2 = best["center"]
			await _go(gc.x + 1.5, gc.y + 2.8)
			await _shot(tag + "_graves")
	# the draw calls the dressing adds, standing where all of it could be in view
	var mm = g.map.get("props").get_node_or_null("Prop_cart_toppled")
	var dm = d.get_node_or_null("DressMesh")
	var wires = line.get_node_or_null("Wires")
	if not d.cart.is_empty():
		var cp2: Vector2 = d.cart["pos"]
		await _go(cp2.x, cp2.y + 3.0)
	var all_on: int = await _draws()
	if dm:
		dm.visible = false
	var no_mesh: int = await _draws()
	if wires:
		wires.visible = false
	var no_wire: int = await _draws()
	if mm:
		mm.visible = false
	var none: int = await _draws()
	print("dress_shots: draw calls all %d, without the 3D mesh %d, without the wire %d, without the cart %d" % [all_on, no_mesh, no_wire, none])
	if dm:
		dm.visible = true
	if wires:
		wires.visible = true
	if mm:
		mm.visible = true
	if _only("wide"):
		var cam := Camera3D.new()
		g.add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = 140.0
		cam.far = 400.0
		cam.global_position = Vector3(0, 120, 0)
		cam.rotation_degrees = Vector3(-90, 0, 0)
		cam.current = true
		await _wait(4)
		await _shot("wide_plain")
		var over := _overlay(d, line)
		g.add_child(over)
		await _wait(3)
		await _shot("wide")
	_finish(0)


## The debug overlay of the top-down view.
func _overlay(d, line) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var quad := func(a: Vector2, b: Vector2, w: float, c: Color) -> void:
		var n := (b - a).orthogonal().normalized() * w * 0.5
		im.surface_set_color(c)
		for p: Vector2 in [a - n, b - n, b + n, a - n, b + n, a + n]:
			im.surface_add_vertex(Vector3(p.x, 40.0, p.y))
	var dot := func(p: Vector2, r: float, c: Color) -> void:
		quad.call(p - Vector2(r, 0), p + Vector2(r, 0), r * 2.0, c)
	for sp: Dictionary in line.spans:
		var a: Vector2 = line.poles[sp["a"]]["pos"]
		var b: Vector2 = line.poles[sp["b"]]["pos"]
		quad.call(a, b, 0.35, Color.RED if bool(sp["wired"]) else Color.YELLOW)
	for p: Dictionary in line.poles:
		dot.call(p["pos"], 0.7, Color.BLACK if p["state"] == "missing" else (Color.ORANGE if p["state"] == "snapped" else Color.WHITE))
	if not d.cart.is_empty():
		dot.call(d.cart["pos"], 1.2, Color.BLUE)
		for w: Dictionary in d.cart["wheels"]:
			dot.call(w["pos"], 0.6, Color.CYAN)
	for gr: Dictionary in d.graves:
		for c: Dictionary in gr["crosses"]:
			dot.call(c["pos"], 0.5, Color.MAGENTA)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi
