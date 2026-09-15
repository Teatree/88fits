## Dependency-free test runner: runs every `test_*` method in tests/*_test.gd (gdUnit4 suites work too,
## as long as they only use assert_* helpers from this runner or plain asserts).
## godot --headless --path game --script res://tools/run_tests.gd
extends SceneTree

var _fails := 0
var _passes := 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var dir := DirAccess.open("res://tests/")
	if dir:
		for f in dir.get_files():
			if f.ends_with("_test.gd"):
				_run_file("res://tests/" + f)
	print("run_tests: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _run_file(path: String) -> void:
	var script = load(path)
	if script == null:
		printerr("  could not load ", path)
		_fails += 1
		return
	var inst = script.new()
	if inst is Node:
		root.add_child(inst)
	for m in inst.get_method_list():
		var name: String = m["name"]
		if not name.begins_with("test_"):
			continue
		var before := _fails
		if inst.has_method("before_test"):
			inst.before_test()
		inst.call(name)
		if inst.has_method("after_test"):
			inst.after_test()
		if _fails == before:
			_passes += 1
			print("  PASS %s.%s" % [path.get_file(), name])
		else:
			print("  FAIL %s.%s" % [path.get_file(), name])
	if inst is Node:
		inst.queue_free()


static func fail(msg: String) -> void:
	printerr("    assertion failed: " + msg)
	var tree := Engine.get_main_loop()
	if tree is SceneTree and tree.get_script() != null and "_fails" in tree:
		tree._fails += 1
