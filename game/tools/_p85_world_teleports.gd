## Pass 85 (lane WORLD): the Teleports from above, a few map seeds: each Teleport a magenta disc with its land_clear
## circle (pink) and its kin_spacing half (so two circles never overlap), the other structures yellow, the hero's landings
## from 40 uses white dots (the hero put back at the arena's middle before each). Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p85_world_teleports.gd -- out=<dir> [seeds=3,7,11,19]
## Writes seed_<n>.png and teleports.json (counts, the closest pair, the closest landing to a Teleport). The save is
## sandboxed; a watchdog quits after 240 s.
extends SceneTree

var _out := "user://p85_teleports"
var _seeds: Array = [3, 7, 11, 19]
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("seeds="):
			_seeds = []
			for s in a.substr(6).split(","):
				_seeds.append(int(s))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		push_error("p85 teleports: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _disc(parent: Node, at: Vector3, r: float, col: Color, h: float, ring: bool = false) -> void:
	var mi := MeshInstance3D.new()
	if ring:
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.35
		tm.outer_radius = r
		tm.rings = 48
		mi.mesh = tm
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.1
		mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 10
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = Vector3(at.x, h, at.z)


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	var report := {}
	for sd in _seeds:
		var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": sd, "analytics": false}))
		f.close()
		change_scene_to_file("res://game/Game.tscn")
		g = null
		for k in range(600):
			await process_frame
			g = current_scene
			if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("structures") != null:
				break
		await _wait(1.0)
		g.player.god = true
		g.director.process_mode = Node.PROCESS_MODE_DISABLED
		g.enemies.kill_all(false)
		if g.hud:
			g.hud.visible = false
		var sm = g.structures
		var tps: Array = sm.teleport_spots()
		var tdef = null
		var marks := Node3D.new()
		g.add_child(marks)
		for st in sm.items:
			if st.def.effect_kind == "teleport":
				tdef = st.def
			else:
				_disc(marks, st.global_position, 1.6, Color(1.0, 0.85, 0.2), 30.0)
		var land_clear := float(tdef.params.get("land_clear", 0.0)) if tdef else 0.0
		var kin := float(tdef.params["per_map"].get("kin_spacing", 0.0)) if tdef else 0.0
		for p: Vector3 in tps:
			_disc(marks, p, 2.2, Color(1.0, 0.3, 0.85), 31.0)
			_disc(marks, p, land_clear, Color(1.0, 0.55, 0.9), 30.5, true)
			_disc(marks, p, kin * 0.5, Color(0.6, 0.2, 0.9), 30.4, true)
		var pair := INF
		for i in tps.size():
			for j in range(i + 1, tps.size()):
				pair = minf(pair, Vector2(tps[i].x - tps[j].x, tps[i].z - tps[j].z).length())
		var worst := INF
		var wet := 0
		for k in range(40):
			g.player.global_position = Vector3(0, g.map.height_at(0, 0), 0)
			g.teleport_hero(tdef)
			var q: Vector3 = g.player.global_position
			worst = minf(worst, sm.nearest_distance(q, tps))
			if g.map.has_method("in_water") and g.map.in_water(q):
				wet += 1
			_disc(marks, q, 0.9, Color(1, 1, 1), 31.5)
		g.player.invuln = 0.0
		await _wait(0.3)
		# from above, the whole arena
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = g.map.arena_radius * 2.2
		cam.far = 400.0
		g.add_child(cam)
		cam.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP), Vector3(0, 120, 0))
		cam.make_current()
		for k in 4:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("seed_%d.png" % sd))
		report[str(sd)] = {"teleports": tps.size(), "closest_pair": pair, "closest_landing": worst, "wet_landings": wet,
			"structures": sm.items.size()}
		print("p85 teleports: seed ", sd, " ", report[str(sd)])
	var rf := FileAccess.open(_out.path_join("teleports.json"), FileAccess.WRITE)
	rf.store_string(JSON.stringify(report, "\t"))
	rf.close()
	save.end_sandbox()
	quit(0)
