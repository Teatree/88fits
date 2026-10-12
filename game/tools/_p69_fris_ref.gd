## Pass 69, lane FRIS: the Frisbee's three discs (Frisbee.disc_mesh: plain lime, the razor "Shredder", the Flying Saucer)
## rendered three-quarter from above on a see-through film, the references ART paints the icons from:
## tools/dl/frisbee_ref.png, frisbee_razors_ref.png, flying_saucer_ref.png (768 px). Windowed:
##   godot --audio-driver Dummy --resolution 768x768 --path game --script res://tools/_p69_fris_ref.gd [-- out=<dir>]
extends SceneTree

var _out := "D:/_projects/88fits/tools/dl"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	# loaded now, after the autoloads (WeaponBehavior names Run)
	var fr: GDScript = load("res://core/behaviors/Frisbee.gd")
	var jobs := [
		["frisbee_ref", "plain", Color("#B8FF2A"), Color("#7CFF00"), 0.8],
		["frisbee_razors_ref", "razors", Color("#FF3FA4"), Color("#FF1F8A"), 0.7],
		["flying_saucer_ref", "saucer", Color("#E8E8F0"), Color("#FF3FA4"), 1.2],
	]
	for j: Array in jobs:
		await _render(fr, str(j[0]), str(j[1]), j[2], j[3], float(j[4]))
	quit(0)


func _render(fr: GDScript, name: String, look: String, albedo: Color, emission: Color, energy: float) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(768, 768)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.sky = sky
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-55, -35, 0)
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, 150, 0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.6, 3.4), Vector3(0, -0.05, 0), Vector3.UP)
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = fr.disc_mesh(look, albedo)
	mi.mesh = mesh
	var mats: Array = fr.disc_materials(look, emission, energy)
	for s in range(mini(mats.size(), mesh.get_surface_count())):
		mi.set_surface_override_material(s, mats[s])
	mi.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(20.0), deg_to_rad(6.0))
	vp.add_child(mi)
	for k in range(6):
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p69_fris_ref: ", name)
	vp.queue_free()
	await process_frame
