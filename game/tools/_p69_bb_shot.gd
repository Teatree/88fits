## Pass 69, lane BB, scratch captures in the debug arena as Fadeaway: the basketball at Heat 0, half and full (the glow,
## the trail, the halo, the beat), the Alley-Oop ball (dark blue) and its launch (creatures thrown up), On Fire's ball,
## and Slam Dunk's black ball cold and hot, frame by frame around a throw, from a close camera (`zoom=`, default 0.5).
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p69_bb_shot.gd -- out=<dir> [only=heat,oop,fire,dunk,launch] [zoom=0.5]
extends SceneTree

var _out := "user://p69_bb"
var _only: PackedStringArray = []
var _zoom := 0.5
var _run
var _reg
var _save
var g
var _heat := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_hold_heat)


## Holds Run.heat where the capture wants it (-1: leave it be), every frame.
func _hold_heat() -> void:
	if _heat >= 0 and _run != null:
		_run.heat = _heat


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p69_bb: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "basketball", "level": 1, "character": "fadeaway", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(4.0)
	if _on("heat"):
		await _throw("basketball", 3, [], 0, "heat0")
		await _throw("basketball", 3, [], 5, "heat5")
		await _throw("basketball", 3, [], 10, "heat10", [0.1, 0.15, 0.2, 0.25, 0.3, 0.4])
	if _on("oop"):
		await _throw("basketball", 3, ["alley_oop"], 0, "oop0")
		await _throw("basketball", 3, ["alley_oop"], 10, "oop10")
	if _on("fire"):
		await _throw("basketball", 3, ["on_fire"], 0, "fire0")
		await _throw("basketball", 3, ["on_fire", "alley_oop"], 6, "fire_oop6")
	if _on("dunk"):
		await _throw("slam_dunk", 1, ["on_fire", "alley_oop", "rebound"], 0, "dunk0")
		await _throw("slam_dunk", 1, ["on_fire", "alley_oop", "rebound"], 10, "dunk10", [0.1, 0.15, 0.2, 0.25, 0.3, 0.4])
	if _on("launch"):
		await _launch_show()
	_heat = -1
	if _save.has_method("end_sandbox"):
		_save.end_sandbox()
	quit(0)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


## The build: nothing but `wid` at `level` with `muts`, then a pack of tough skeletons `ahead` m up the screen.
func _build(wid: String, level: int, muts: Array, ahead: float, count := 5) -> void:
	_run.debug_clear_items()
	for m in muts:
		_run.debug_set_item("mutation", str(m), 1)
	var def = _reg.weapon(wid)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, level)
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	for k in range(count):
		var s := -2.0 + 4.0 * float(k) / maxf(float(count - 1), 1.0)
		em.spawn("skeleton", here + Vector3(s * 0.8, 0, -ahead - 0.8 * float(k % 2)), null, 1.0, 400.0)
	em._rebuild_grid()


## `wid` throwing at the pack at Heat `heat`: frames at `times` seconds after a fresh throw leaves.
func _throw(wid: String, level: int, muts: Array, heat: int, name: String, times: Array = [0.1, 0.2, 0.3, 0.45]) -> void:
	_heat = heat
	await _build(wid, level, muts, 5.0)
	await _wait(0.6)
	var b = g._behaviors.get(wid)
	var frames := 0
	var last: float = b.cooldown_left if b else 0.0
	while frames < 900:
		await process_frame
		frames += 1
		if b and b.cooldown_left > last + 0.05:
			break
		if b:
			last = b.cooldown_left
	print("p69_bb: ", name, " heat ", _run.heat, " level shown ", b.get("heat_level_shown") if b else -1.0)
	var f0 := Engine.get_process_frames()
	for k in range(times.size()):
		var want := int(round(float(times[k]) * 60.0))
		while Engine.get_process_frames() - f0 < want:
			await process_frame
		_save_shot(name + "_t%02d" % k)


## Alley-Oop with a sure launch: the pack thrown up, frames through the flight and the landing.
func _launch_show() -> void:
	_heat = 0
	await _build("basketball", 5, ["alley_oop"], 4.5, 6)
	var b = g._behaviors.get("basketball")
	if b and b.inst.params.get("launch") is Dictionary:
		b.inst.params["launch"]["chance"] = 1.0
	await _wait(0.4)
	var f0 := Engine.get_process_frames()
	for k in range(14):
		var want := int(round(float(k) * 0.12 * 60.0))
		while Engine.get_process_frames() - f0 < want:
			await process_frame
		_save_shot("launch_t%02d" % k)
	print("p69_bb: launches ", g.enemies.launches, " landings ", g.enemies.landings)
