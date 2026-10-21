## Pass 95 (lane BREATH): captures of the Dragon's Breath in the debug arena at the phone's canvas: the plain breath
## (frames through its two seconds and the scorch after), Backdraft (bigger, the pack shoved), Blue Flame (blue breath
## and blue burning creatures), Held Breath (the hero stood still: a ring of fire all round him), the Fire Eater (the
## whole path, amplified). Every wait is bounded (frame caps) and a watchdog quits the run at WATCHDOG seconds.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p95_BREATH_shot.gd -- out=<dir> [only=plain,backdraft,blue,held,evo]
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p95_breath"
var _only: PackedStringArray = []
var _run
var _reg
var _save
var g
var _shots := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	create_timer(WATCHDOG, true, false, true).timeout.connect(func() -> void:
		print("p95_breath: WATCHDOG after %d shots" % _shots)
		quit(2))


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	_shots += 1
	print("p95_breath: ", name)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "dragons_breath", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
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
	await _wait(1.5)
	if _on("plain"):
		await _breath("dragons_breath", 1, [], "plain", false)
	if _on("backdraft"):
		await _breath("dragons_breath", 3, ["backdraft"], "backdraft", false)
	if _on("blue"):
		await _breath("dragons_breath", 3, ["blue_flame"], "blue", false)
	if _on("held"):
		await _breath("dragons_breath", 3, ["held_breath"], "held", true)
	if _on("evo"):
		await _breath("fire_eater", 1, ["blue_flame", "held_breath", "backdraft"], "evo", true)
	_save.data = keep
	quit(0)


## The build: nothing but `wid` at `level` with `muts`; a pack of tough skeletons in the cone ahead (up the screen, -Z),
## or all round him for a ring.
func _build(wid: String, level: int, muts: Array, ring: bool) -> void:
	_run.debug_clear_items()
	for m in muts:
		_run.debug_set_item("mutation", str(m), 1)
	var def = _reg.weapon(wid)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, level)
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	# tough enough (x300 HP) to stand through the Fire Eater's whole breath, so the after shot shows them burning
	if ring:
		for k in range(10):
			var a := TAU * float(k) / 10.0
			em.spawn("skeleton", here + Vector3(cos(a) * 3.2, 0, sin(a) * 3.2), null, 1.0, 300.0)
	else:
		for k in range(7):
			var s := -1.0 + 2.0 * float(k) / 6.0
			em.spawn("skeleton", here + Vector3(s * 1.6, 0, -3.0 - 0.9 * absf(s) - 0.5 * float(k % 2)), null, 1.0, 300.0)
	em._rebuild_grid()
	# they stand where they are put (the arena's dummies walk otherwise)
	for i in range(em.MAX):
		if em.alive[i] == 1:
			em.state[i] = em.STATE_MOVE
			em.vel[i] = Vector3.ZERO
			if em.rise_t.size() > i:
				em.rise_t[i] = 1.0


## One breath captured: a frame as it starts, then at 6, 12, 24, 45, 75 and 110 frames on, and one 1.5 s after it
## ends (the scorch, the burning pack). `still` waits for the hero to have stood still 2.5 s first (Held Breath).
func _breath(wid: String, level: int, muts: Array, name: String, still: bool) -> void:
	if still:
		# the hero has not moved since the scene loaded: his still_unhit_seconds grows on its own; BEFORE the build, so
		# the breath the new behaviour fires on its own (its first cooldown is short) is already a held one (with the
		# scene fresh, `only=evo`, the first run caught a plain breath fired while he had stood 1.5 s)
		var sw := 0
		while g.player.still_unhit_seconds() < 2.5 and sw < 240:
			await process_frame
			sw += 1
		print("p95_breath: still_unhit ", g.player.still_unhit_seconds())
	_build(wid, level, muts, still)
	var b = g._behaviors.get(wid)
	if b == null:
		print("p95_breath: no behaviour for ", wid)
		return
	# the breath counted BEFORE the cooldown is armed (the build has no await: nothing fires between the two lines)
	var n0: int = b.breaths
	b.cooldown_left = 0.0
	var frames := 0
	while b.breaths == n0 and frames < 900:
		await process_frame
		frames += 1
	print("p95_breath: ", name, " breath after ", frames, " frames, len ", b.last_len, " ring ", b.is_ring(), " hits ", b.last_hits.size())
	await process_frame
	_save_shot(name + "_f00")
	var k := 0
	for pair in [["f06", 6], ["f12", 12], ["f24", 24], ["f45", 45], ["f75", 75], ["f110", 110]]:
		while k < int(pair[1]):
			await process_frame
			k += 1
		_save_shot(name + "_" + str(pair[0]))
	var waited := 0
	while b.burning() and waited < 600:
		await process_frame
		waited += 1
	await _wait(1.5)
	_save_shot(name + "_after")
