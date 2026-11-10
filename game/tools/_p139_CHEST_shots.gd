## Pass 139 (lane CHEST): the mutation chest's landed card with the weapon badge (WWeaponBadge): the Revolver at 0, 1 and
## 2 mutations held, the Boomstick's Birdshot (the longest mutation text), the Drifter's own Fire in the Hole (outside the
## path: no lit rivet) and a plain weapon upgrade (no badge). Prints the card's and the buttons' rects for each.
## Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p139_CHEST_shots.gd -- out=<abs dir> [only=mut0,mut1,mut2,long,hero,weapon]
## A watchdog quits after 180 s; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://p139_chest"
var _only: Array = []
var _run
var _reg
var _kept := ""
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		print("p139_chest: watchdog quit")
		_restore()
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _restore() -> void:
	if _kept != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_kept)
		f.close()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	var cs = g.chest_screen
	var vp: Vector2 = root.get_viewport().get_visible_rect().size
	print("p139_chest: %s vp=%s panel=%s skip=%s banish=%s take=%s badge=%s" % [name, str(vp), str(cs._panel.get_global_rect()),
		str(cs._skip_btn.get_global_rect()), str(cs._banish_btn.get_global_rect()), str(cs._take_btn.get_global_rect()),
		str(cs.weapon_badge().get_global_rect()) if cs.weapon_badge() else "none"])


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	for k in ["debug_panel", "debug_modal_buttons", "free_revive_button", "hit_log", "debug_mode"]:
		root.get_node("Settings").set(k, false)
	_kept = FileAccess.get_file_as_string("user://save.json")
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("chest_screen") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _wait(2.5)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(3.0)
	g.hud._banner.visible = false
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.call("_clear_field")
		for c in g.arena_panel.get_children():
			c.visible = false
		g.arena_panel.visible = false
	if _want("mut0"):
		await _mutation("mut0", [["weapon", "revolver", 3], ["weapon", "boomstick", 2], ["passive", "magnet", 2]], "revolver", 0)
	if _want("mut1"):
		await _mutation("mut1", [["weapon", "revolver", 4], ["weapon", "boomstick", 2], ["passive", "magnet", 2]], "revolver", 1)
	if _want("mut2"):
		await _mutation("mut2", [["weapon", "revolver", 5], ["weapon", "boomstick", 2], ["passive", "magnet", 2]], "revolver", 2)
	if _want("long"):
		await _mutation("long", [["weapon", "revolver", 3], ["weapon", "boomstick", 4], ["passive", "magnet", 2]], "boomstick", 1, "birdshot_lane")
	if _want("hero"):
		await _mutation("hero", [["weapon", "revolver", 3], ["weapon", "lob_grenade", 3], ["passive", "magnet", 2]], "lob_grenade", 1, "fire_in_the_hole")
	if _want("weapon"):
		_build([["weapon", "revolver", 3], ["weapon", "boomstick", 2], ["passive", "magnet", 2]])
		var bs = _reg.weapon("boomstick")
		await _land({"type": "weapon", "id": "boomstick", "def": bs, "level_from": 2, "level_to": 3, "is_new": false})
		await _shot("weapon")
		g.chest_screen.visible = false
	_restore()
	quit(0)


func _build(items: Array) -> void:
	_run.debug_clear_items()
	for it in items:
		_run.debug_set_item(it[0], it[1], it[2])
	_run.build_changed.emit()


## A mutation chest for `weapon` with `n` of its path held, landing on `mid` (else the first path mutation not held).
func _mutation(name: String, items: Array, weapon: String, n: int, mid: String = "") -> void:
	_build(items)
	var path: Array = _reg.mutations_of(weapon)
	var held := 0
	for m in path:
		if held >= n:
			break
		if str(m.id) == mid:
			continue
		_run.debug_set_item("mutation", m.id, 1)
		held += 1
	_run.build_changed.emit()
	var md = _reg.mutation(mid) if mid != "" else null
	if md == null:
		for m in path:
			if not _run.mutations_held(weapon).has(m.id):
				md = m
				break
	if md == null:
		print("p139_chest: %s has no open mutation" % name)
		return
	await _land({"type": "mutation", "id": md.id, "def": md, "level_from": 0, "level_to": 1, "is_new": true, "boss": true})
	await _shot(name)
	g.chest_screen.visible = false


func _land(roll: Dictionary) -> void:
	_run.skips_left = 2
	_run.banishes_left = 1
	g.set_paused(true)
	var cs = g.chest_screen
	cs.open(roll)
	await process_frame
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in range(240):
		await process_frame
		if not cs._spinning:
			break
	# the card's fade and the pulsing rivet part-way up its swell
	await _wait(0.75)
