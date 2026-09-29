## How long the Collection takes to build (pass 34: its capture came out blank at 0.9 s).
## godot --headless --path game --script res://tools/time_collection.gd
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var reg = root.get_node("Registry")
	var t0 := Time.get_ticks_usec()
	var n := 0
	for d in reg.weapons.values() + reg.passives.values() + reg.mutations.values() + reg.enemies.values():
		if reg.is_hidden(d):
			n += 1
	var t1 := Time.get_ticks_usec()
	var s: PackedScene = load("res://ui/CollectionScreen.tscn")
	var t2 := Time.get_ticks_usec()
	var c: Node = s.instantiate()
	root.add_child(c)
	var t3 := Time.get_ticks_usec()
	print("time_collection: is_hidden over all %d hidden in %.1f ms; load %.1f ms; instantiate + build %.1f ms; rows %d" % [n, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, c.content.get_child_count()])
	quit(0)
