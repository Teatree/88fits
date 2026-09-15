## Debug helper: builds Dry Gulch headlessly and prints what the terrain material actually holds.
## godot --headless --path game --script res://tools/inspect_terrain.gd
extends SceneTree


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("sand exists: ", ResourceLoader.exists("res://art/env/sand.png"), " cracked exists: ", ResourceLoader.exists("res://art/env/cracked.png"))
	var t = load("res://art/env/sand.png")
	print("sand load: ", t, " size: ", (t.get_size() if t else "n/a"))
	var scene: PackedScene = load("res://world/maps/dry_gulch/DryGulch.tscn")
	var map = scene.instantiate()
	root.add_child(map)
	await process_frame
	var terrain = map.get_node_or_null("Terrain")
	print("terrain node: ", terrain)
	if terrain:
		var m = terrain.material_override
		print("material: ", m)
		if m is ShaderMaterial:
			print("shader: ", m.shader, " sand param: ", m.get_shader_parameter("sand_tex"), " cracked param: ", m.get_shader_parameter("cracked_tex"))
			print("shader code head: ", m.shader.code.substr(0, 120).replace("\n", " | "))
		var mesh: Mesh = terrain.mesh
		if mesh:
			var arrays := mesh.surface_get_arrays(0)
			var cols = arrays[Mesh.ARRAY_COLOR]
			print("vertex colours: ", (cols.size() if cols else 0), " first: ", (cols[0] if cols and cols.size() > 0 else "none"), " mid: ", (cols[cols.size() / 2] if cols and cols.size() > 0 else "none"))
	quit(0)
