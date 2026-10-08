## Pass 60 lane PK's capture (scratch, after item_shots.gd): the debug arena, 80 gems of the three kinds scattered 2.5 to
## 8 m round the hero, a PNG of them resting at the run's zoom (`rest`), the same frame in the old colours and glow for
## comparison (`rest_old`), then vacuum_all(true) and frames through the arc (`arc_NNN` = NNN/100 s after the pull),
## `after` once they are all in, and last a few gems let go inside the magnet's reach for the walk-up hop (`hop`). The
## frames are grabbed as images during the sequence and written at the end, because saving a 1080x1920 PNG takes long
## enough that physics fell behind the clock between frames (the first run's 0.9 s and 1.3 s frames showed one moment).
## Each frame prints the gems' phases and their mean and highest height over their rest. Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p60_pk_shot.gd -- out=<dir>
extends SceneTree

const ARC_TIMES := [0.2, 0.45, 0.7, 0.95, 1.2, 1.5, 1.9]

var _out := "user://p60_pk"
var _run
var _save
var g
var _frames: Array = []   # [name, Image], written by _flush


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


## Grabs the frame (a GPU read, quick) and prints where the gems are; the PNG is written by _flush.
func _grab(name: String) -> void:
	await process_frame
	_frames.append([name, root.get_viewport().get_texture().get_image()])
	var pm = g.pickups
	var waiting := 0
	var rising := 0
	var flying := 0
	var n := 0
	var sum_h := 0.0
	var top_h := 0.0
	for i in range(pm.MAX):
		if pm.alive[i] == 0:
			continue
		n += 1
		var h: float = pm.pos[i].y - pm.rest_of(pm.kind[i])
		sum_h += h
		top_h = maxf(top_h, h)
		if pm.flying[i] == 0:
			continue
		if pm.phase[i] == pm.PHASE_ARC_WAIT:
			waiting += 1
		elif pm.phase[i] == pm.PHASE_ARC_RISE:
			rising += 1
		else:
			flying += 1
	var mean_h: float = sum_h / n if n > 0 else 0.0
	print("p60_pk_shot: %-8s alive %3d  waiting %3d  rising %3d  flying %3d  mean height %.2f m  highest %.2f m" % [name, n, waiting, rising, flying, mean_h, top_h])


func _flush() -> void:
	for f in _frames:
		(f[1] as Image).save_png(_out.path_join(str(f[0]) + ".png"))
	_frames.clear()


func _mmi_of(pm, mm) -> MultiMeshInstance3D:
	for c in pm.get_children():
		if c is MultiMeshInstance3D and c.multimesh == mm:
			return c
	return null


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(2.5)
	var pm = g.pickups
	var here: Vector3 = g.player.global_position
	# 80 gems (40 small, 25 medium, 15 large) 2.5 to 8 m out all round, worth next to nothing so no level-up interrupts
	var rng := RandomNumberGenerator.new()
	rng.seed = 60
	for k in range(80):
		var kind: int = 0 if k < 40 else (1 if k < 65 else 2)
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.5, 8.0)
		pm.spawn(kind, here + Vector3(cos(a), 0, sin(a)) * d, 0.01)
	await _wait(1.8)
	await _grab("rest")
	# the old look on the same frame: the pass-46 colours and the 0.6 glow; then the new one back
	var mats: Array = []
	for k in range(3):
		var m: ShaderMaterial = _mmi_of(pm, pm._mms[k]).material_override
		mats.append(m)
		m.set_shader_parameter("albedo", pm.GLINT_COLOURS[k])
		m.set_shader_parameter("rest_emission", 0.6)
	await _grab("rest_old")
	for k in range(3):
		(mats[k] as ShaderMaterial).set_shader_parameter("albedo", pm.COLOURS[k])
		(mats[k] as ShaderMaterial).set_shader_parameter("rest_emission", pm.GEM_EMISSION)
	await _wait(0.2)
	_flush()
	await _wait(0.5)
	# the big pull: frames through the arc, written once they are all in
	pm.vacuum_all(true)
	var t := 0.0
	for s in ARC_TIMES:
		var ds: float = float(s) - t
		if ds > 0.0:
			await _wait(ds)
		t = float(s)
		await _grab("arc_%03d" % int(round(float(s) * 100.0)))
	await _wait(3.0)
	await _grab("after")
	_flush()
	# the walk-up hop: gems let go inside his reach set off on the hop at once
	for k in range(6):
		var a := TAU * float(k) / 6.0
		pm.spawn(1, here + Vector3(cos(a), 0, sin(a)) * 1.1, 0.01)
	await _wait(0.1)
	await _grab("hop")
	_flush()
	_save.data = keep
	quit(0)
