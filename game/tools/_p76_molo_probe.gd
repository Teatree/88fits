## Pass 76 (lane MOLO) scratch probe: what the bottle and the jug carry once imported (surfaces, vertex colours, the
## visual's materials). Headless:  godot --headless --path game --script res://tools/_p76_molo_probe.gd
extends SceneTree


func _initialize() -> void:
	for path in ["res://content/weapons/molotov/molotov_visual_bottle.tscn", "res://content/evolutions/moonshine/moonshine_visual_jug.tscn"]:
		var vis: Node = (load(path) as PackedScene).instantiate()
		var proj: Node = vis.get_node("Projectile")
		for c in proj.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			print(path, " mesh node ", mi.name, " surfaces ", mi.mesh.get_surface_count(), " xf ", mi.transform)
			for s in range(mi.mesh.get_surface_count()):
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var cols = arr[Mesh.ARRAY_COLOR]
				var n: int = (cols as PackedColorArray).size() if cols != null else 0
				var sample := []
				for k in range(0, n, maxi(n / 4, 1)):
					sample.append(cols[k])
				var ov := mi.get_surface_override_material(s)
				print("  surface ", s, " verts ", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " colours ", n, " ", sample, " override ", ov, " vc ", (ov as StandardMaterial3D).vertex_color_use_as_albedo if ov else "-", " aabb ", mi.mesh.get_aabb())
		vis.free()
	quit(0)
