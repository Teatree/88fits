## Pass 85 (lane WORLD): the natural tints, a sheet per page of paintings: the painting untinted (first column, its
## material's rules off) and eight rolls of its kind's rule (the corners of the roll cube and a middle). Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1440x1600 --path D:/_projects/88fits/game --script res://tools/_p85_world_tints.gd -- out=<dir>
## A watchdog quits after 90 s.
extends SceneTree

var _out := "user://p85_tints"
const ROLLS := [Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(0, 1, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(1, 1, 0),
	Vector3(0.5, 0.5, 0.5), Vector3(0.25, 0.75, 0.4)]
const PER_PAGE := 15
const CELL := 1.3


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		push_error("p85 tints: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _code(r: Vector3) -> float:
	var q := Vector3i(roundi(r.x * 11.0), roundi(r.y * 11.0), roundi(r.z * 11.0))
	return float(q.x + 12 * q.y + 144 * q.z)


func _main() -> void:
	var PF = load("res://core/systems/PropField.gd")
	var probe = PF.new()
	probe.setup()
	var ids: Array = []
	for id in probe.manifest.keys():
		if str(id).begins_with("st_") or probe.is_hidden(str(id)) or not probe.has(str(id)):
			continue
		ids.append(str(id))
	probe.free()
	var pages := ceili(float(ids.size()) / PER_PAGE)
	for page in pages:
		var world := Node3D.new()
		root.add_child(world)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.886, 0.745, 0.549)
		world.add_child(env)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = 9 * CELL + 0.2
		world.add_child(cam)
		var vs := Vector2(root.get_viewport().get_visible_rect().size)
		var tall := cam.size * vs.y / vs.x
		cam.position = Vector3(9 * CELL * 0.5, PER_PAGE * CELL - tall * 0.5 + 0.1, 10.0)
		cam.make_current()
		var plain = PF.new()
		world.add_child(plain)
		plain.setup()
		for c in plain.get_children():
			if c is MultiMeshInstance3D and c.material_override is ShaderMaterial:
				(c.material_override as ShaderMaterial).set_shader_parameter("tint_v_0", Vector4(1, 1, 0.5, 0))
				(c.material_override as ShaderMaterial).set_shader_parameter("tint_v_1", Vector4(1, 1, 0.5, 0))
		var pf = PF.new()
		world.add_child(pf)
		pf.setup()
		var some := ids.slice(page * PER_PAGE, (page + 1) * PER_PAGE)
		for row in some.size():
			var id: String = some[row]
			var y := (PER_PAGE - 1 - row) * CELL + 0.1
			var s: float = 1.15 / float(pf.height_of(id))
			plain.add(id, Vector3(CELL * 0.5, y, 0), s, false, 0.0, true)
			for k in ROLLS.size():
				pf.add(id, Vector3(CELL * (k + 1.5), y, 0), s, false, 0.0, true)
				var t: Dictionary = pf._types[id]
				var i: int = int(t["n"]) - 1
				var mm: MultiMesh = t["mm"]
				mm.set_instance_custom_data(i, Color(0, 0, 0, _code(ROLLS[k])))
		for k in 4:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_out.path_join("tints_%d.png" % page))
		var f := FileAccess.open(_out.path_join("tints_%d.txt" % page), FileAccess.WRITE)
		f.store_string("\n".join(some))
		f.close()
		print("p85 tints: page ", page, " ", some)
		world.free()
	quit(0)
