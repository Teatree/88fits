## Pass 118 (the lead; Garry: "Chests have a bug where one of the rays of shine shines through the middle of them"): an
## ordinary chest and a purple one in front of the hero, captured with the beam on its old spot (beam_back 0, through the
## chest's middle) and on its new one (Chest.BEAM_BACK), at three turns of the chest.
## Windowed:
##   GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/_p118_chest_beam_shots.gd -- out=<dir>
## A watchdog quits after 150 s; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://chest_beam"
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("chest_beam: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	# each chest close up (300 x 340 px round where it stands on the screen)
	var k := 0
	for c in g.pickups.chests:
		var sp: Vector2 = g.camera.get_viewport().get_camera_3d().unproject_position(c.global_position + Vector3(0, 0.5, 0))
		var r := Rect2i(int(sp.x) - 150, int(sp.y) - 220, 300, 340).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(_out.path_join("%s_c%d.png" % [name, k]))
		k += 1
	print("chest_beam: ", name)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _beams(back_k: float) -> void:
	for c in g.pickups.chests:
		for n in c.get_children():
			if n is MeshInstance3D and n.material_override is ShaderMaterial:
				var m: ShaderMaterial = n.material_override
				if int(m.get_shader_parameter("mode")) == 1:
					m.set_shader_parameter("beam_back", 0.75 * (1.35 if c.boss else 1.0) * back_k)


func _main() -> void:
	var run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	run.arena_next = true
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
	g.enemies.kill_all(false)
	await _frames(30)
	var here := _ground(g.player.global_position)
	g.pickups.spawn_chest(_ground(here + Vector3(-1.8, 0, -4.0)))
	g.pickups.spawn_chest(_ground(here + Vector3(1.8, 0, -4.0)), true)
	await _frames(10)
	for k in 3:
		_beams(0.0)
		await _shot("beam_old_%d" % k)
		_beams(1.0)
		await _shot("beam_new_%d" % k)
		await _frames(40)
	_save.data = keep
	quit(0)
