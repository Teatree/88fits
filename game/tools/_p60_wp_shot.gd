## Pass 60, lane WP, scratch captures in the debug arena: the Tommy Gun's rounds and the Boomstick's pellets in the air
## (two frames each), the Rocket Pod with the Pressure Cooker at no pressure and at full (the glow), the Sun Scepter
## with Flicker (the ring kept, no emblem) and a Peashooter carrying its whole path (no emblem). Windowed at the phone's
## canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p60_wp_shot.gd -- out=<dir> [only=tommy,boomstick,chicago,blunderbuss,pod,scepter,pea]
extends SceneTree

var _out := "user://p60_wp"
## the sections to run (only=a,b); empty = all
var _only: PackedStringArray = []
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p60_wp: ", name)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	_save_shot(name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
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
	if g.camera:
		g.camera.zoom_override = 0.62
	await _wait(2.0)
	if _on("tommy"):
		await _gun("tommy_gun", 3, [], 6.5, "tommy", 3)
	if _on("boomstick"):
		await _gun("boomstick", 3, [], 4.2, "boomstick", 1)
		await _gun("boomstick", 3, [], 4.0, "boomstick_side", 1, true)
	# the evolutions share their bases' rounds (the gold tint, the bell)
	if _on("chicago"):
		await _gun("chicago_typewriter", 1, [], 6.5, "chicago", 3)
	if _on("blunderbuss"):
		await _gun("blunderbuss", 1, [], 4.0, "blunderbuss_side", 1, true)
	if _on("pod"):
		await _pod()
	if _on("scepter"):
		await _scepter()
	if _on("pea"):
		await _peashooter()
	_save.data = keep
	quit(0)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


## The build: nothing but `wid` at `level` with `muts`, then a pack of tough skeletons `ahead` m up the screen (or to
## the hero's right with `side`).
func _build(wid: String, level: int, muts: Array, ahead: float, count := 6, side := false) -> void:
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
		var at := Vector3(ahead + 0.6 * float(k % 2), 0, s * 0.6) if side else Vector3(s, 0, -ahead - 0.6 * float(k % 2))
		em.spawn("skeleton", here + at, null, 1.0, 60.0)
	em._rebuild_grid()


## A gun firing at the pack: a frame once `min_shots` rounds are in the air, then frames 2, 4, 7, 12 and 20 frames on
## (the flash, the smoke, the streaks and their beads), and one a second later. `side` puts the pack to the hero's
## right instead of up the screen (the muzzle beside him, not behind his painting).
func _gun(wid: String, level: int, muts: Array, ahead: float, name: String, min_shots: int, side := false) -> void:
	await _build(wid, level, muts, ahead, 6, side)
	# the last build's rounds gone first, or the poll sees them and grabs the old frame
	await _wait(0.8)
	var frames := 0
	while g.projectiles.count < min_shots and frames < 600:
		await process_frame
		frames += 1
	# one more frame: the one that draws them (process_frame wakes before the draw of the tick that fired)
	await process_frame
	print("p60_wp: ", wid, " ", g.projectiles.count, " shots in the air after ", frames, " frames")
	_save_shot(name + "_f00")
	var n := 1
	for pair in [["f02", 2], ["f04", 4], ["f07", 7], ["f12", 12], ["f20", 20]]:
		while n <= int(pair[1]):
			await process_frame
			n += 1
		_save_shot(name + "_" + str(pair[0]))
	await _wait(1.0)
	_save_shot(name + "_late")


## The Rocket Pod with the Pressure Cooker: at no pressure, then at full (the pod's body and tubes glow).
func _pod() -> void:
	await _build("rocket_pod", 3, ["pressure_cooker"], 7.0)
	await _wait(1.2)
	var b = g._behaviors.get("rocket_pod")
	if b == null:
		print("p60_wp: no rocket_pod behaviour")
		return
	b.pressure = 0.0
	await _shot("pod_pressure_0")
	b.pressure = 1.0
	await _wait(0.3)
	print("p60_wp: pod pressure ", b.pressure, " heat ", b.heat_shown(), " interval ", b.fire_interval())
	await _shot("pod_pressure_1")
	await _wait(1.5)
	await _shot("pod_pressure_1_firing")


## The Sun Scepter with Flicker: the ring round the handle, nothing floating over it.
func _scepter() -> void:
	await _build("sun_scepter", 3, ["flicker"], 7.0, 4)
	await _wait(1.6)
	var b = g._behaviors.get("sun_scepter")
	if b:
		print("p60_wp: scepter ring ", b.has_ring(), " marks ", b.get_node_or_null("MutationMarks") != null)
	await _shot("scepter_flicker")
	await _build("sun_scepter", 3, ["flicker", "heat_stroke", "gold_dust"], 7.0, 4)
	await _wait(1.6)
	await _shot("scepter_full_path")


## A Peashooter carrying its whole path: no emblem over the pod or the hero.
func _peashooter() -> void:
	await _build("peashooter", 3, ["toxic_peas", "big_peas", "bouncing_peas"], 6.0)
	await _wait(1.2)
	var marks: Array = g.find_children("MutationMarks", "", true, false)
	print("p60_wp: MutationMarks nodes under the game: ", marks.size())
	await _shot("peashooter_mutated")
