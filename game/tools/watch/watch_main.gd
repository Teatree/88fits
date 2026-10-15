## The Watch's entry (pass 80, lane WATCH): a SceneTree script, so the tree's current scene stays empty and the run's
## end can never swap the Watch out (Watch.gd). It compiles before the autoloads exist and names none of them: the
## Watch scene is loaded once the tree runs. tools/watch.py starts it on the Watch's snapshot of game/:
##   Godot --fixed-fps 60 --path tools/dl/watch/snap/game --script res://tools/watch/watch_main.gd -- hero=drifter ...
## (the arguments: Watch.gd and tools/dl/p80/keys_WATCH.md). Tools only.
extends SceneTree


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			args[a.substr(0, i)] = a.substr(i + 1)
		elif a != "":
			args[a] = "1"
	var scene = load("res://tools/watch/Watch.tscn")
	if scene == null:
		printerr("watch: res://tools/watch/Watch.tscn did not load")
		quit(2)
		return
	var w = scene.instantiate()
	w.set("args", args)
	root.add_child(w)
