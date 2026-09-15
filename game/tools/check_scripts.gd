## Loads every .gd and .tscn under res:// (except addons) and reports scripts that fail to parse
## or scenes that fail to instantiate. Run: godot --headless --path game --script res://tools/check_scripts.gd
extends SceneTree

var _errors := 0
var _count := 0


func _init() -> void:
	# Autoloads are registered after the SceneTree script is constructed, so defer one frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_walk("res://")
	print("check_scripts: %d files checked, %d errors" % [_count, _errors])
	quit(1 if _errors > 0 else 0)


func _walk(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_walk(path.path_join(sub))
	for f in dir.get_files():
		var p := path.path_join(f)
		if f.ends_with(".gd"):
			_count += 1
			var s = load(p)
			if s == null or not (s is GDScript):
				printerr("PARSE FAIL: ", p)
				_errors += 1
			elif not s.can_instantiate() and not s.is_tool():
				# abstract scripts (SceneTree scripts) cannot instantiate; only report reload errors
				if s.reload() != OK:
					printerr("SCRIPT ERROR: ", p)
					_errors += 1
		elif f.ends_with(".tscn"):
			_count += 1
			var sc = load(p)
			if sc == null or not (sc is PackedScene):
				printerr("SCENE LOAD FAIL: ", p)
				_errors += 1
			else:
				var inst = sc.instantiate()
				if inst == null:
					printerr("SCENE INSTANTIATE FAIL: ", p)
					_errors += 1
				else:
					inst.free()
