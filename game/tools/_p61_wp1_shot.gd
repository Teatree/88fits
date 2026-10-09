## Pass 61, lane WP1, scratch captures in the debug arena: each of the seven cheap mutation looks (Dragon's Breath, Both
## Barrels, Toxic Peas, Fan the Hammer, Drum Mag, Sticky, Thorny Weed) on its weapon, without and with the mutation, and
## the evolutions that keep them, frame by frame around a shot, from the run camera (zoom 1 = 22.5 m; `zoom=` for a
## closer look). Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path game --script res://tools/_p61_wp1_shot.gd -- out=<dir> [only=boom,pea,tommy,lob,weed,evo,evo0] [zoom=1.0]
extends SceneTree

var _out := "user://p61_wp1"
var _only: PackedStringArray = []
var _zoom := 1.0
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
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p61_wp1: ", name)


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
		g.camera.zoom_override = _zoom
	await _wait(4.0)
	if _on("boom"):
		await _gun("boomstick", 3, [], 4.2, "boom_base", 1, true)
		await _gun("boomstick", 3, ["dragons_breath"], 4.2, "boom_dragon", 1, true)
		await _gun("boomstick", 3, ["both_barrels"], 4.2, "boom_both", 1, true, [0.0, 0.35, 0.7, 1.05, 1.4, 1.75, 2.1, 2.45, 2.8, 3.15, 3.5, 3.85, 4.2])
	if _on("pea"):
		await _gun("peashooter", 3, [], 6.0, "pea_base", 1)
		await _gun("peashooter", 3, ["toxic_peas"], 6.0, "pea_toxic", 1)
		await _gun("peashooter", 3, ["fan_the_hammer"], 6.0, "pea_fan", 1, false, [0.0, 0.03, 0.06, 0.09, 0.12, 0.15, 0.2])
	if _on("tommy"):
		await _gun("tommy_gun", 3, [], 6.5, "tommy_base", 3)
		await _gun("tommy_gun", 3, ["drum_mag"], 6.5, "tommy_drum", 3)
	if _on("lob"):
		await _gun("lob_grenade", 3, [], 7.0, "lob_base", 1, false, [0.0, 0.3, 0.6, 0.9])
		await _gun("lob_grenade", 3, ["sticky"], 7.0, "lob_sticky", 1, false, [0.0, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4])
	if _on("weed"):
		await _gun("tumbleweed", 3, [], 6.0, "weed_base", 1, false, [0.0, 0.3, 0.6, 1.0, 1.5])
		await _gun("tumbleweed", 3, ["thorns"], 6.0, "weed_thorns", 1, false, [0.0, 0.3, 0.6, 1.0, 1.5, 2.2, 3.0])
	if _on("evo"):
		await _gun("blunderbuss", 1, ["dragons_breath", "birdshot_lane", "both_barrels"], 4.0, "evo_blunderbuss", 1, true, [0.0, 0.05, 0.1, 0.2, 0.4, 0.8, 1.2])
		await _gun("pea_cannon", 1, ["big_peas", "bouncing_peas", "toxic_peas", "fan_the_hammer"], 6.0, "evo_peacannon", 1, false, [0.0, 0.05, 0.1, 0.2])
		await _gun("chicago_typewriter", 1, ["drum_mag", "mini_crits", "tommy_sweep"], 6.5, "evo_chicago", 3)
		await _gun("golden_pineapple", 1, ["frag", "new_equipment", "sticky"], 7.0, "evo_pineapple", 1, false, [0.0, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8])
		await _gun("dust_devil", 1, ["boomerang", "dust_wake", "thorns"], 6.0, "evo_dustdevil", 1, false, [0.0, 0.3, 0.6, 1.0, 1.5, 2.2])
	if _on("evo0"):
		# the evolutions without the mutations whose looks they keep (for the before/after)
		await _gun("blunderbuss", 1, ["birdshot_lane"], 4.0, "evo0_blunderbuss", 1, true, [0.0, 0.05, 0.1, 0.2, 0.4])
		await _gun("pea_cannon", 1, ["big_peas", "bouncing_peas"], 6.0, "evo0_peacannon", 1, false, [0.0, 0.05, 0.1, 0.2])
		await _gun("chicago_typewriter", 1, ["mini_crits", "tommy_sweep"], 6.5, "evo0_chicago", 3)
		await _gun("golden_pineapple", 1, ["frag", "new_equipment"], 7.0, "evo0_pineapple", 1, false, [0.0, 0.3, 0.6, 0.9, 1.2])
		await _gun("dust_devil", 1, ["boomerang", "dust_wake"], 6.0, "evo0_dustdevil", 1, false, [0.0, 0.3, 0.6, 1.0])
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
		em.spawn("skeleton", here + at, null, 1.0, 400.0)
	em._rebuild_grid()


## A weapon firing at the pack: a frame once `min_shots` shots are in the air, then frames at `times` seconds on (frame
## counts 2, 4, 7, 12, 20 when none are given), and one a second later.
func _gun(wid: String, level: int, muts: Array, ahead: float, name: String, min_shots: int, side := false, times: Array = []) -> void:
	await _build(wid, level, muts, ahead, 6, side)
	await _wait(0.8)
	# a fresh trigger pull: the behaviour's cooldown jumps back up as it fires (the frame that fired is drawn next)
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
	var more := 0
	while _mine(wid) < min_shots and more < 30:
		await process_frame
		more += 1
	await process_frame
	print("p61_wp1: ", wid, " ", muts, " ", _mine(wid), " shots in the air ", frames, " frames after the build")
	if b and b.get("inst") and b.inst.params.get("tint") is Dictionary:
		var kk: int = b.tint_kind(b.inst.params["tint"]) if b.has_method("tint_kind") else b.shot_kind()
		var mm = g.projectiles.kinds[kk]["mmi"].material_override
		print("   tint ", b.inst.params["tint"], " kind ", kk, " mat ", mm.albedo_color if mm else "per-surface", " muts ", b.inst.mutations.size())
	if times.is_empty():
		_save_shot(name + "_f00")
		var n := 1
		for pair in [["f02", 2], ["f04", 4], ["f07", 7], ["f12", 12], ["f20", 20]]:
			while n <= int(pair[1]):
				await process_frame
				n += 1
			_save_shot(name + "_" + str(pair[0]))
	else:
		# game seconds as frames (run with --fixed-fps 60: a PNG save stalls the clock, not the game)
		var f0 := Engine.get_process_frames()
		for k in range(times.size()):
			var want := int(round(float(times[k]) * 60.0))
			while Engine.get_process_frames() - f0 < want:
				await process_frame
			_save_shot(name + "_t%02d" % k)
	await _wait(1.0)
	_save_shot(name + "_late")


## Shots of weapon `wid` in the air now.
func _mine(wid: String) -> int:
	var pm = g.projectiles
	var n := 0
	for j in range(pm.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] != null and pm.weapon[j].def.id == wid:
			n += 1
	return n
