## Pass 130 (Garry: "give me an assessment as to whether or not I had tanked our performance"): what the scenery costs,
## counted over many map seeds per stage: the paintings a run really draws (each one is one MultiMesh, so one draw call a
## frame, wherever the camera looks), the instances, the textures the PropField loaded and their bytes on the GPU, and
## what a map build takes. Run it before and after adding paintings. Headless:
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p130_ENV_probe.gd -- seeds=30 [looks=1]
## looks=1 also prints, per stage, how many runs each painting appeared in and how many of it a run holds.
## Touches no save. A watchdog quits it after 500 s.
extends SceneTree


func _initialize() -> void:
	create_timer(500.0, true, false, true).timeout.connect(func() -> void:
		push_error("probe: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var n := 30
	var show_looks := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			n = int(a.substr(6))
		elif a == "looks=1":
			show_looks = true
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var def = reg.call("map", "red_canyon")
	var keep_seed: int = run.map_seed
	var keep_map = run.map
	var keep_stage: int = run.stage
	run.map = def
	var tl = def.timeline
	var stages: int = (tl.stage_list as Array).size() if tl and tl.get("stage_list") is Array else 1
	for st in stages:
		run.stage = st
		var used := 0
		var inst := 0
		var loaded := 0
		var bytes := 0
		var ms := 0
		var per := {}
		for k in n:
			run.map_seed = 1000 + k * 37
			var t0 := Time.get_ticks_msec()
			var m: Node3D = (def.scene as PackedScene).instantiate()
			root.add_child(m)
			ms += Time.get_ticks_msec() - t0
			var props = m.get("props")
			var types: Dictionary = props.get("_types")
			for id: String in types.keys():
				if id.begins_with("st_"):
					continue
				loaded += 1
				var c: int = int(types[id]["n"])
				var mmi := props.get_node_or_null("Prop_" + id) as MultiMeshInstance3D
				if mmi:
					var tex := (mmi.material_override as ShaderMaterial).get_shader_parameter("sprite") as Texture2D
					if tex:
						bytes += tex.get_width() * tex.get_height() * 4 * (4 if tex.get_image() != null and tex.get_image().has_mipmaps() else 3) / 3
				if c > 0:
					used += 1
					inst += c
					if not per.has(id):
						per[id] = [0, 0]
					per[id][0] += 1
					per[id][1] += c
			root.remove_child(m)
			m.free()
		print("env_probe: stage %d %-6s | paintings drawn a run %.1f | instances %.0f | scenery textures loaded %.0f, %.1f MB | map build %.0f ms"
				% [st + 1, str(tl.call("stage_id", st)), float(used) / n, float(inst) / n, float(loaded) / n, float(bytes) / n / 1048576.0, float(ms) / n])
		if show_looks:
			var ids := per.keys()
			ids.sort()
			for id: String in ids:
				print("env_probe:    %-18s in %3d of %d runs, %.1f a run it is in" % [id, per[id][0], n, float(per[id][1]) / float(per[id][0])])
	run.map_seed = keep_seed
	run.map = keep_map
	run.stage = keep_stage
	quit(0)
