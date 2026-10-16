## Pass 83 (lane SCENE): the run's camera on the scenery's ground shadows: a barrel, a sign, the structures, a cactus or
## tree stand, a rock field and the hero beside a boulder, each from where a player would see it. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p83_scene_run.gd -- out=<dir> [tag=after] [noshadow=1] [seed=7]
## noshadow=1 hides every scenery shadow (the look before pass 83). The hero is in god mode, the waves stopped and the
## crowd cleared. The save is sandboxed. A watchdog quits after 150 s whatever happens.
extends SceneTree

var _out := "user://p83_scene_run"
var _tag := "after"
var _noshadow := false
var _seed := 7
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a == "noshadow=1":
			_noshadow = true
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		push_error("p83_scene_run: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [_tag, name]))
	print("p83_scene_run: ", name)


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("barrels") != null:
			break
	await _wait(1.5)
	g.player.god = true
	g.director.process_mode = Node.PROCESS_MODE_DISABLED
	g.enemies.kill_all(false)
	if g.hud:
		g.hud.visible = false
	var props = g.map.get("props")
	if _noshadow and props:
		for i in props.shadow_count():
			props.hide_shadow(i)
	print("p83_scene_run: shadows ", props.shadow_count() if props else -1, " props ", props.placed.size() if props else -1)
	var spots: Array = []
	if g.barrels and g.barrels.pos.size() > 0:
		spots.append(["barrel", g.barrels.pos[0]])
		spots.append(["barrel2", g.barrels.pos[1]])
	var signs = g.get_node_or_null("Signs")
	if signs and signs.spots.size() > 0:
		spots.append(["sign", signs.spots[0]])
	var seen := {}
	for s in g.structures.items:
		var id := str(s.def.id)
		if seen.has(id) or seen.size() >= 5:
			continue
		seen[id] = true
		spots.append(["st_" + id, s.global_position])
	for st in g.map.get("_stands"):
		spots.append(["stand_" + str(st["kind"]), Vector3(st["center"].x, 0.0, st["center"].y)])
	var boulder := Vector3.INF
	for row in props.placed:
		if str(row["id"]) == "boulder":
			boulder = row["pos"]
			break
	if boulder != Vector3.INF:
		spots.append(["rocks", boulder])
	for sp in spots:
		var at: Vector3 = sp[1]
		# a step south of it, so it stands up the screen from the hero, beside him
		var hero_at := at + Vector3(1.6, 0.0, 2.6)
		hero_at.y = g.map.height_at(hero_at.x, hero_at.z)
		g.player.global_position = hero_at
		g.player.velocity = Vector3.ZERO
		g.camera.snap_to(g.player)
		g.enemies.kill_all(false)
		await _wait(0.5)
		await _shot(str(sp[0]))
	save.end_sandbox()
	quit(0)
