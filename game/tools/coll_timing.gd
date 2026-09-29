## Captures the Collection at 0.3, 0.6, 0.9, 1.5 and 3 s after it opens (pass 34: a blank capture at 0.9 s).
extends SceneTree

var _out := "user://coll_timing"
var _t := 0.0
var _marks := [0.3, 0.6, 0.9, 1.5, 3.0]
var _k := 0
var _started := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	change_scene_to_file("res://ui/CollectionScreen.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	if not _started:
		if current_scene and current_scene.name.contains("Collection"):
			_started = true
			_t = 0.0
		return
	_t += root.get_process_delta_time()
	if _k < _marks.size() and _t >= _marks[_k]:
		var n := 0
		var shown := 0
		for c in current_scene.content.get_children():
			n += 1
			if (c as CanvasItem).modulate.a > 0.9:
				shown += 1
		print("coll_timing: %.2f s  rows %d  opaque %d  fps %.0f" % [_t, n, shown, Engine.get_frames_per_second()])
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("coll_%d.png" % _k))
		_k += 1
	if _k >= _marks.size():
		quit(0)
