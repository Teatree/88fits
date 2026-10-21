## Pass 95, lane ITEMS, scratch captures in the debug arena at the phone's canvas (1080x1920): the held guns' rounds
## leaving the muzzle as drawn (the Boomstick up the screen and to the side, Both Barrels, Birdshot, the Blunderbuss),
## the companions for comparison (the Revolver, the Tommy Gun, the Chicago Typewriter), the Frisbee's trail in every look
## (plain, Poison Razors, Carry, the Flying Saucer) and "Fire forward" (the Sabre, the Hammer and the Frisbee with
## nobody near). Every wait is bounded (frame caps) and a watchdog quits after WATCHDOG seconds; the switch is put back.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p95_ITEMS_shot.gd -- out=<dir> [only=guns,frisbee,forward]
extends SceneTree

const WATCHDOG := 480.0
var _out := "user://p95_items"
var _only: PackedStringArray = []
var _run
var _reg
var _save
var _settings
var _keep_ff := false
var _keep_save: Dictionary = {}
var g
var _t0 := 0
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_watchdog)


func _watchdog() -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG * 1000.0:
		print("p95_items: WATCHDOG after %.0f s, quitting" % WATCHDOG)
		_restore()
		quit(2)


func _restore() -> void:
	if _settings != null:
		_settings.set("fire_forward", _keep_ff)
	if _save != null and not _keep_save.is_empty():
		_save.data = _keep_save


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _until(pred: Callable, cap: int) -> int:
	var n := 0
	while not pred.call() and n < cap:
		await process_frame
		n += 1
	return n


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p95_items: ", name)


func _frames(name: String, marks: Array) -> void:
	var n := 0
	for pair in marks:
		while n < int(pair[1]):
			await process_frame
			n += 1
		_save_shot(name + "_" + str(pair[0]))


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_keep_ff = bool(_settings.get("fire_forward"))
	_keep_save = _save.data.duplicate(true)
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
	if _on("guns"):
		await _gun("boomstick", 3, [], 4.2, "boomstick", 1)
		await _gun("boomstick", 3, [], 4.0, "boomstick_side", 1, true)
		await _gun("boomstick", 3, ["both_barrels"], 4.2, "both_barrels", 1)
		await _gun("boomstick", 3, ["birdshot"], 4.2, "birdshot", 1)
		await _gun("blunderbuss", 1, [], 4.0, "blunderbuss", 1)
		await _gun("blunderbuss", 1, [], 4.0, "blunderbuss_side", 1, true)
		await _gun("revolver", 3, [], 6.5, "revolver", 1)
		await _gun("tommy_gun", 3, [], 6.5, "tommy", 3)
		await _gun("chicago_typewriter", 1, [], 6.5, "chicago", 3)
	if _on("frisbee"):
		await _disc("frisbee", 3, [], "frisbee_plain")
		await _disc("frisbee", 3, ["poison_razors"], "frisbee_razors")
		await _disc("frisbee", 3, ["carry"], "frisbee_carry")
		await _disc("flying_saucer", 1, [], "flying_saucer")
	if _on("forward"):
		await _forward()
	_done = true
	_restore()
	quit(0)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


## The build: nothing but `wid` at `level` with `muts`, then a pack of tough skeletons `ahead` m up the screen (or to
## the hero's right with `side`); count 0 = nobody.
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


## A gun firing at the pack: a frame once `min_shots` rounds are in the air, then frames 2, 4, 7, 12 and 20 on, and one
## a second later. `side` puts the pack to the hero's right.
func _gun(wid: String, level: int, muts: Array, ahead: float, name: String, min_shots: int, side := false) -> void:
	await _build(wid, level, muts, ahead, 6, side)
	await _wait(0.8)
	var frames: int = await _until(func() -> bool: return g.projectiles.count >= min_shots, 600)
	await process_frame
	var b = g._behaviors.get(wid)
	var origin := "?"
	if b != null and b.has_method("held_tip"):
		var tip: Vector3 = b.held_tip()
		origin = "held tip %s" % str(tip) if tip != Vector3.INF else "no held tip (companion or chest)"
	print("p95_items: ", wid, " ", muts, " ", g.projectiles.count, " shots in the air after ", frames, " frames; ", origin)
	_save_shot(name + "_f00")
	await _frames(name, [["f02", 2], ["f04", 4], ["f07", 7], ["f12", 12], ["f20", 20]])
	await _wait(1.0)
	_save_shot(name + "_late")


## The discs in flight at the pack: a frame once one is in the air, then frames on as the trail grows and the arc bends.
func _disc(wid: String, level: int, muts: Array, name: String) -> void:
	await _build(wid, level, muts, 6.5, 6)
	await _wait(0.8)
	var b = g._behaviors.get(wid)
	if b == null:
		print("p95_items: no behaviour for ", wid)
		return
	var frames: int = await _until(func() -> bool: return not (b.discs as Array).is_empty(), 600)
	await process_frame
	print("p95_items: ", wid, " ", muts, " ", (b.discs as Array).size(), " discs after ", frames, " frames; trail ", str(b.trail_params()))
	_save_shot(name + "_f00")
	await _frames(name, [["f04", 4], ["f10", 10], ["f18", 18], ["f30", 30], ["f45", 45]])


## "Fire forward" with nobody near: the Sabre slashes the air ahead, the Hammer lands 75% of its reach ahead, the
## Frisbee flies straight on.
func _forward() -> void:
	_settings.set("fire_forward", true)
	# the arena's training dummies stand up again after a fall: cleared for good (Game.clear_dummies)
	if g.has_method("clear_dummies"):
		g.clear_dummies()
	await _build("sabre", 3, [], 6.0, 0)
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.5)
	print("p95_items: forward: creatures alive ", em.count if "count" in em else -1)
	var b = g._behaviors.get("sabre")
	var n: int = await _until(func() -> bool: return b != null and b.strokes >= 1, 600)
	print("p95_items: sabre stroke after ", n, " frames; dir ", str(b._dir) if b else "?", " facing ", str(g.player.forward()))
	_save_shot("forward_sabre_f00")
	await _frames("forward_sabre", [["f03", 3], ["f06", 6], ["f10", 10]])
	await _build("hammer", 3, [], 6.0, 0)
	em.kill_all(false)
	await _wait(0.5)
	var h = g._behaviors.get("hammer")
	n = await _until(func() -> bool: return h != null and (h._swings as Array).size() >= 1, 600)
	print("p95_items: hammer swing after ", n, " frames; at ", str((h._swings as Array)[0]["at"]) if h and not (h._swings as Array).is_empty() else "?", " hero ", str(g.player.global_position))
	_save_shot("forward_hammer_f00")
	await _frames("forward_hammer", [["f08", 8], ["f20", 20], ["f36", 36], ["f44", 44], ["f52", 52]])
	await _build("frisbee", 3, [], 6.0, 0)
	em.kill_all(false)
	await _wait(0.5)
	var fr = g._behaviors.get("frisbee")
	n = await _until(func() -> bool: return fr != null and not (fr.discs as Array).is_empty(), 600)
	print("p95_items: frisbee forward after ", n, " frames; dir0 ", str((fr.discs as Array)[0]["dir0"]) if fr and not (fr.discs as Array).is_empty() else "?")
	_save_shot("forward_frisbee_f00")
	await _frames("forward_frisbee", [["f10", 10], ["f25", 25], ["f45", 45]])
	_settings.set("fire_forward", _keep_ff)
