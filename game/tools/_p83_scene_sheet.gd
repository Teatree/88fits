## Pass 83 (lane SCENE): every painted prop kind (and variant) standing on Red Canyon's sand over its ground shadow, seen
## by the run's camera (pitch 46, fov 55) at its distance and closer. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p83_scene_sheet.gd -- out=<dir> [tag=v1] [ids=a,b] [per_row=5] [noshadow=1]
## Writes <tag>_run.png (22.5 m), <tag>_near.png (11 m), and <tag>_rows.txt (which id stands where). Nothing touches
## the save. A watchdog quits after 90 s.
extends SceneTree

var _out := "user://p83_scene_sheet"
var _tag := "v1"
var _ids: Array = []
var _per_row := 5
var _noshadow := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("ids="):
			_ids = Array(a.substr(4).split(","))
		elif a.begins_with("per_row="):
			_per_row = int(a.substr(8))
		elif a == "noshadow=1":
			_noshadow = true
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		push_error("p83_scene_sheet: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p83_scene_sheet: ", name)


func _main() -> void:
	var run = root.get_node("Run")
	var keep: int = run.map_seed
	run.map_seed = 88
	var world := Node3D.new()
	root.add_child(world)
	var map: Node3D = load("res://world/maps/red_canyon/RedCanyon.tscn").instantiate()
	world.add_child(map)
	run.map_seed = keep
	var props = map.get("props")
	var centre := Vector3(7.5, 0.0, 47.4)
	props.remove_where(func(_r) -> bool: return true)
	var ids: Array = _ids
	if ids.is_empty():
		for id in props.manifest.keys():
			if props.has(id) and not str(id).begins_with("st_"):
				ids.append(str(id))
	var lines: Array = []
	var gap_x := 2.6
	var gap_z := 5.5
	for k in ids.size():
		var col := k % _per_row
		var row := k / _per_row
		var x := centre.x + (float(col) - float(_per_row - 1) * 0.5) * gap_x
		var z := centre.z - float(row) * gap_z
		var g := Vector3(x, map.height_at(x, z), z)
		props.add(ids[k], g, 1.0 if props.height_of(ids[k]) < 3.0 else 0.6, false, 0.0, true)
		lines.append("%d,%d %s" % [row, col, ids[k]])
	if _noshadow:
		for i in props.shadow_count():
			props.hide_shadow(i)
	var f := FileAccess.open(_out.path_join(_tag + "_rows.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 55.0
	cam.far = 300.0
	world.add_child(cam)
	cam.make_current()
	var rows := float((ids.size() + _per_row - 1) / _per_row)
	var focus := Vector3(centre.x, map.height_at(centre.x, centre.z), centre.z - (rows - 1.0) * gap_z * 0.5)
	var p := deg_to_rad(46.0)
	var fwd := Vector3(0.0, -sin(p), -cos(p))
	for pair in [["run", 22.5 + rows * 1.5], ["near", 11.0]]:
		var foc: Vector3 = focus if pair[0] == "run" else Vector3(centre.x, focus.y, centre.z - 1.0)
		cam.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3(0.0, cos(p), -sin(p)), -fwd), foc - fwd * float(pair[1]))
		await _wait(0.4)
		await _shot("%s_%s" % [_tag, pair[0]])
	quit(0)
