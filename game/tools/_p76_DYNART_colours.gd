## Pass 76 (lane DYNART) scratch calibration: how a dynamite stick's paper colour reads in the game's light on the sand.
## A row of sticks (the B stick's mesh) lies by the hero in the debug arena, each painted one candidate colour (flat
## albedo, matte), the first in the model's own vertex colours as the Lobber draws it; one frame is saved. Prints the
## first vertex colours the import kept (linear or sRGB?). Windowed, bounded, watchdog:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p76_DYNART_colours.gd -- out=<png> [model=res://art/props/dynamite_b_stick_tan.glb] [cols=C8894A,B8956A,...] [zoom=0.5]
extends SceneTree

const WATCHDOG_S := 60.0

var _out := "user://p76_dynart_colours.png"
var _model := "res://art/props/dynamite_b_stick_tan.glb"
var _cols: Array = ["C8894A", "C49A6C", "BFA07A", "B08A60", "D2B48C", "A9825A", "C22A20", "A8302A"]
var _zoom := 0.5
var _rough := 0.85
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("model="):
			_model = a.substr(6)
		elif a.begins_with("cols="):
			_cols = Array(a.substr(5).split(",", false))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("rough="):
			_rough = float(a.substr(6))
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_dynart_colours: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var run = root.get_node("Run")
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	var g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_dynart_colours: no game scene")
		save.data = keep
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	run.debug_clear_items()
	run.build_changed.emit()
	g.enemies.kill_all(false)
	await _wait(1.0)
	var scn = load(_model)
	var mesh: Mesh = null
	if scn is PackedScene:
		var r: Node = (scn as PackedScene).instantiate()
		for c in r.find_children("*", "MeshInstance3D", true, false):
			mesh = (c as MeshInstance3D).mesh
			break
		r.free()
	if mesh == null:
		print("p76_dynart_colours: no mesh in ", _model)
		save.data = keep
		quit(1)
		return
	var arr := mesh.surface_get_arrays(0)
	var cols = arr[Mesh.ARRAY_COLOR]
	if cols is PackedColorArray and (cols as PackedColorArray).size() > 0:
		var seen := {}
		for c: Color in cols:
			var key := "%.3f,%.3f,%.3f" % [c.r, c.g, c.b]
			if not seen.has(key):
				seen[key] = true
			if seen.size() >= 6:
				break
		print("p76_dynart_colours: vertex colours kept: ", seen.keys())
	var here: Vector3 = g.player.global_position
	var n := _cols.size() + 1
	for k in range(n):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.metallic = 0.0
		mat.roughness = _rough
		if k == 0:
			mat.vertex_color_use_as_albedo = true
		else:
			mat.albedo_color = Color("#" + str(_cols[k - 1]))
		mi.material_override = mat
		g.add_child(mi)
		var x := -2.6 + 5.2 * float(k) / float(n - 1)
		var at := here + Vector3(x, 0, -3.0)
		var y: float = g.map.height_at(at.x, at.z) if g.get("map") and g.map.has_method("height_at") else at.y
		mi.global_position = Vector3(at.x, y + 0.12, at.z)
		mi.scale = Vector3.ONE * 1.35
		mi.rotation = Vector3(0, deg_to_rad(70.0), 0)
	await _wait(0.6)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("p76_dynart_colours: saved ", _out, " cols ", _cols)
	save.data = keep
	quit(0)
