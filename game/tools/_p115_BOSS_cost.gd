## Pass 115 (lane BOSS): what a barrier costs the CPU. Headless: each look's pieces built (BarrierMeshes.parts, once per
## run: the first build), then a barrier of the shipped attack's own radius laid out (BossBarrier.setup) and its per-frame
## work (_process). Prints milliseconds.
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p115_BOSS_cost.gd
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var reg = root.get_node("Registry")
	var meshes = load("res://core/systems/BarrierMeshes.gd")
	var bscript = load("res://core/systems/BossBarrier.gd")
	for pair in [["tumbleweed_fence", "royal_dust_devil"], ["cactus_fence", "venom_monsoon"], ["iron_fence", "hellbrand_mandala"]]:
		var t0 := Time.get_ticks_usec()
		var parts: Dictionary = meshes.parts(pair[0])
		var t1 := Time.get_ticks_usec()
		var tris := 0
		for k in parts.keys():
			tris += int((parts[k] as ArrayMesh).surface_get_array_len(0) / 3)
		var cdef = reg.boss_attack(pair[1])
		var holder := Node3D.new()
		root.add_child(holder)
		var b: Node3D = bscript.new()
		holder.add_child(b)
		var t2 := Time.get_ticks_usec()
		b.call("setup", null, cdef, Vector3.ZERO, cdef.barrier_radius(), Vector3(0, 0, 10))
		var t3 := Time.get_ticks_usec()
		b.call("_process", 0.016)
		var t4 := Time.get_ticks_usec()
		var per_seg := 0
		for k in parts.keys():
			per_seg += 0
		print("p115cost: %s: pieces built %.1f ms (%d triangles in its %d kinds); ring of %.0f m laid out %.1f ms (%d stretches, %d pieces, %d MultiMeshes); a frame %.3f ms"
			% [pair[0], (t1 - t0) / 1000.0, tris, parts.size(), cdef.barrier_radius(), (t3 - t2) / 1000.0, int(b.get("stretches")), int(b.get("pieces")), int(b.get("chunks")), (t4 - t3) / 1000.0])
		holder.queue_free()
	quit(0)
