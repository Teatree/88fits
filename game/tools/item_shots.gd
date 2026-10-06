## Captures of weapons and creatures in play (pass 53): the debug arena with a build set and a crowd spawned, then PNGs
## at set seconds, so a new evolution's model, a bomblet field, a pod glowing at full pressure or a creature's walk can
## be looked at without a phone. Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/item_shots.gd -- out=<dir> \
##       weapons=hellfire_battery,whirlwind creatures=lesser_scorpion@LS-B,werewolf [seconds=2,4,7] [zoom=0.7]
## weapons=<id,...>: each is a base weapon or an evolution; every non-hidden path mutation of its family is handed over
## first (debug_set_item), the build is this one weapon, a crowd of tough skeletons stands round the hero, and a PNG is
## saved at each of `seconds` (<id>_<n>.png). creatures=<id[@CODE],...>: three of each walk at the hero (god mode),
## one PNG each after a moment (<id>[_CODE].png). zoom= sets the camera's zoom (0.7 = closer than a run's 1.0).
## character=<id> (pass 54) opens the arena on that hero (the Drifter by default): character=solenne for the Sun Scepter.
extends SceneTree

var _out := "user://item_shots"
var _weapons: Array = []
var _creatures: Array = []
var _seconds: Array = [2.0, 4.0, 7.0]
var _zoom := 0.0
var _character := "drifter"
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("weapons="):
			_weapons = Array(a.substr(8).split(",")).filter(func(s: String) -> bool: return s != "")
		elif a.begins_with("creatures="):
			_creatures = Array(a.substr(10).split(",")).filter(func(s: String) -> bool: return s != "")
		elif a.begins_with("seconds="):
			_seconds = Array(a.substr(8).split(",")).map(func(s: String) -> float: return float(s))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("character="):
			# pass 54: the hero the arena opens with (a hero's own weapon is shown on its hero: character=solenne)
			_character = a.substr(10)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("item_shots: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": _character, "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if _zoom > 0.0 and g.camera:
		g.camera.zoom_override = _zoom
	await _wait(2.5)
	for wid in _weapons:
		await _weapon(str(wid))
	for cid in _creatures:
		await _creature(str(cid))
	_save.data = keep
	quit(0)


## The crowd: tough skeletons standing in two packs, ahead of the hero and to his side, so every weapon has something
## in reach (an undying training dummy would take no knockback or death, which is what the captures want to see).
func _crowd() -> void:
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	for k in range(8):
		var a := TAU * float(k) / 8.0
		em.spawn("skeleton", here + Vector3(cos(a), 0, sin(a)) * 4.5, null, 1.0, 40.0)
	for k in range(6):
		em.spawn("skeleton", here + Vector3(-2.0 + float(k) * 0.8, 0, -7.5), null, 1.0, 40.0)
	em._rebuild_grid()


func _weapon(wid: String) -> void:
	var def = _reg.weapon(wid)
	if def == null:
		print("item_shots: no weapon ", wid)
		return
	_run.debug_clear_items()
	# the family's path mutations first: an evolution carries them, a base weapon shows its mutated self
	var family: String = def.evolved_from if def.is_evolution and def.evolved_from != "" else wid
	for m in _reg.mutations_of(family):
		_run.debug_set_item("mutation", m.id, 1)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, def.max_level)
	_run.build_changed.emit()
	_crowd()
	var t := 0.0
	for s in _seconds:
		var ds: float = float(s) - t
		if ds > 0.0:
			await _wait(ds)
		t = float(s)
		await _shot("%s_%02d" % [wid, int(round(t))])


func _creature(spec: String) -> void:
	var parts := spec.split("@")
	var cid: String = parts[0]
	var code: String = parts[1] if parts.size() > 1 else ""
	var def = _reg.enemy(cid)
	if def == null:
		print("item_shots: no creature ", cid)
		return
	_run.debug_clear_items()
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	for k in range(3):
		em.spawn(cid, here + Vector3(-3.0 + float(k) * 3.0, 0, -5.5 - float(k) * 1.2), null, 1.0, 100.0, code)
	em._rebuild_grid()
	await _wait(1.6)
	await _shot(cid + ("_" + code.replace("-", "") if code != "" else ""))
