## Pass 69, lane EN: captures for the eye. Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p69_EN_shots.gd -- out=<dir> mode=specials|beam|beam_off [zoom=1.0]
## mode=specials: the debug arena, the hero in god mode with no weapon, a row of creatures standing still, each plain one
## beside its forced variance special (EnemyManager.force_special), PNGs at the given zoom and closer.
## mode=beam: a real launch with the spawn cinematic (no arena), PNGs at set seconds of the sequence; beam_off = the same
## with the pass-69 fade switched off on the beam quads (the "before").
extends SceneTree

var _out := "user://p69_en_shots"
var _mode := "specials"
var _zoom := 1.0
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("mode="):
			_mode = a.substr(5)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p69_en_shots: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	if _mode == "specials":
		await _specials()
	else:
		await _beam(_mode == "beam_off")
	_save.data = keep
	quit(0)


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _specials() -> void:
	_launch({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7})
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.5)
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.6)
	var here: Vector3 = g.player.global_position
	var ids := [["red_goblin", "RG-B"], ["skeleton", ""], ["blue_slime", ""], ["fire_ant", ""], ["armadillo", ""]]
	var made: Array = []
	for k in range(ids.size()):
		var x := -6.0 + float(k) * 3.0
		var id: String = ids[k][0]
		var code: String = ids[k][1]
		made.append(em.spawn(id, here + Vector3(x, 0, -4.0), null, 1.0, 100.0, code))
		em.force_special = true
		made.append(em.spawn(id, here + Vector3(x, 0, -8.5), null, 1.0, 100.0, code))
		em.force_special = false
	em._rebuild_grid()
	for z: float in [_zoom, 0.6]:
		g.camera.zoom_override = z
		for k in range(40):
			for i: int in made:
				if i >= 0 and em.alive[i] == 1:
					em.speed[i] = 0.0
					em.cooldown[i] = 9.0
			await process_frame
		await _shot("specials_z%02d" % int(round(z * 10.0)))
		await _wait(0.35)
		await _shot("specials_z%02d_b" % int(round(z * 10.0)))


func _beam(off: bool) -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "spawn": true, "analytics": false})
	change_scene_to_file("res://game/Game.tscn")
	# the scene's _ready starts the sequence; wait for it
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("spawning") == true:
			break
	if off:
		for q in g._spawn_quads:
			(q.material_override as ShaderMaterial).set_shader_parameter("fade_y", Vector2.ZERO)
	var marks := [0.35, 0.8, 1.2, 1.6, 1.9]
	var tag := "beam_off" if off else "beam"
	for m: float in marks:
		while g.spawning and float(g._spawn_t) < m:
			await process_frame
		if not g.spawning:
			break
		await _shot("%s_%03d" % [tag, int(round(m * 100.0))])
