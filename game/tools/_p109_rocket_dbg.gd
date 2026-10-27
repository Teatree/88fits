## Pass 109 (lane VFX), a scratch look at the Raider's rocket alone: its mesh and material (Game._rocket_mesh,
## _rocket_material) in a MultiMesh like the game's, big on a sand-coloured floor, seen from the game's pitch, in a few
## variants (pass=all|body|halo). Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 800x800 --path D:/_projects/88fits/game --script res://tools/_p109_rocket_dbg.gd -- out=<dir>
## A watchdog quits after 60 s.
extends SceneTree

var _out := "user://p109_dbg"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(60.0, true, false, true).timeout.connect(func() -> void: quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var game_script = load("res://game/Game.gd")
	var g = game_script.new()
	var mesh: Mesh = g._rocket_mesh()
	var full: Material = g._rocket_material()
	g.free()
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.8, 0.55)
	env.environment = e
	world.add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.93, 0.8, 0.55)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.material = fm
	floor_mi.mesh = pm
	world.add_child(floor_mi)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 30.0
	cam.global_position = Vector3(0, 4.0, 3.9)
	cam.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 3
	for k in range(3):
		var b := Basis(Vector3.UP, 0.4 + 1.1 * k)
		mm.set_instance_transform(k, Transform3D(b, Vector3(-1.4 + 1.4 * k, 1.0, -0.4 * k)))
		mm.set_instance_color(k, Color.WHITE)
		mm.set_instance_custom_data(k, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	world.add_child(mmi)
	var body := (full as ShaderMaterial).duplicate() as ShaderMaterial
	body.next_pass = null
	var halo_only := (full as ShaderMaterial).duplicate() as ShaderMaterial
	halo_only.next_pass = ((full as ShaderMaterial).next_pass as ShaderMaterial).duplicate()
	(halo_only.next_pass as ShaderMaterial).next_pass = null
	for pair in [["body", body], ["halo", halo_only], ["all", full]]:
		mmi.material_override = pair[1]
		for k in range(6):
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("dbg_%s.png" % pair[0]))
		print("p109_dbg: ", pair[0])
	quit(0)
