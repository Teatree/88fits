## Pass 140 (lane TEXTS): the texts on screen after Garry's rules (docs/texts/text_rules.md): a level-up with three new
## weapons (each says its damage), the chest landing on the Singularity and on the Golden Revolver (the mutations note in
## its own face under the evolution's line), a mutation chest on Juggler, and the pause screen's Build tab with the
## Gravity Gun open. Prints each card's text.
## Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p140_TEXTS_shots.gd -- out=<abs dir> [only=levelup,evo,evo2,mut,pause]
## A watchdog quits after 180 s; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://p140_texts"
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
		print("p140_texts: watchdog quit")
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
	print("p140_texts: shot %s" % name)


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
	if _want("levelup"):
		_build([["weapon", "revolver", 2], ["passive", "magnet", 1]])
		_run.rerolls_left = 1
		_run.skips_left = 2
		_run.banishes_left = 0
		var offer := [_card("weapon", _reg.weapon("gravity_gun"), 0, 1), _card("weapon", _reg.weapon("tommy_gun"), 0, 1),
			_card("weapon", _reg.weapon("revolver"), 2, 3)]
		g.set_paused(true)
		g.cards.show_offer(offer, "LEVEL 3!", false)
		await _wait(1.2)
		for c in offer:
			var inst := WeaponInstance.new(c["def"], 1)
			inst.rebuild(_run.player_sheet, [inst])
			print("p140_texts: levelup %s: %s" % [c["id"], inst.description()])
		await _shot("levelup")
		g.cards.visible = false
		g.modal_reset()
		g.set_paused(false)
		await _wait(0.3)
	if _want("evo"):
		await _evolution("evo", "gravity_gun", "singularity")
	if _want("evo2"):
		await _evolution("evo2", "revolver", "golden_revolver")
	if _want("mut"):
		_build([["weapon", "gravity_gun", 3], ["weapon", "revolver", 2], ["passive", "magnet", 2]])
		var md = _reg.mutation("juggler")
		await _land({"type": "mutation", "id": md.id, "def": md, "level_from": 0, "level_to": 1, "is_new": true, "boss": true})
		await _shot("mutation")
		g.chest_screen.visible = false
		g.modal_reset()
		g.set_paused(false)
		await _wait(0.3)
	if _want("pause"):
		_build([["weapon", "gravity_gun", 3], ["weapon", "revolver", 4], ["weapon", "lob_grenade", 2], ["passive", "magnet", 2]])
		_run.debug_set_item("mutation", "repulsor", 1)
		_run.build_changed.emit()
		g.open_pause()
		g.pause_screen._expanded = "gravity_gun"
		g.pause_screen._tab = 0
		g.pause_screen._refresh()
		await _wait(0.8)
		await _shot("pause")
	_restore()
	quit(0)


func _card(type: String, def, from: int, to: int) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _build(items: Array) -> void:
	_run.debug_clear_items()
	for it in items:
		_run.debug_set_item(it[0], it[1], it[2])
	_run.build_changed.emit()


## The chest landing on `into`, the evolution of `weapon` held at level 5 with its three path mutations.
func _evolution(name: String, weapon: String, into: String) -> void:
	_build([["weapon", weapon, 5], ["passive", "magnet", 2]])
	for m in _reg.mutations_of(weapon):
		if not m.is_hero():
			_run.debug_set_item("mutation", m.id, 1)
	_run.build_changed.emit()
	var ev = _reg.weapon(into)
	var tmp := WeaponInstance.new(ev, 1)
	tmp.rebuild(_run.player_sheet, _run.weapons)
	print("p140_texts: %s: %s" % [into, tmp.description().replace("\n", " / ")])
	await _land({"type": "evolution", "id": into, "def": ev, "src_id": weapon, "level_from": 0, "level_to": 1, "is_new": true})
	await _shot(name)
	g.chest_screen.visible = false
	g.modal_reset()
	g.set_paused(false)
	await _wait(0.3)


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
	await _wait(1.2)
