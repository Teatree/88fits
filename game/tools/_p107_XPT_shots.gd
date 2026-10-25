## Pass 107, lane XPT: the Tumbleweed's shots (and the Dust Devil's) in each stage's look, before (its night_tint taken
## off the weapon) and after. The debug arena, the hero in god mode, training dummies up the screen to roll at; for each
## look the look is shown first, then the weapon fires a while, the tree is paused and the frame saved.
## Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p107_XPT_shots.gd -- out=<dir> [looks=0,1,2] [weapons=tumbleweed,dust_devil]
## A watchdog quits after 300 s whatever happens; every wait is bounded.
extends SceneTree

var _out := "user://p107_xpt"
var _looks: Array = [0, 1, 2]
var _weapons: Array = ["tumbleweed", "dust_devil"]
var _run
var _save
var g
var _made: Array = []
var _here := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("looks="):
			_looks = []
			for s in a.substr(6).split(",", false):
				_looks.append(int(s))
		elif a.begins_with("weapons="):
			_weapons = Array(a.substr(8).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	seed(107)
	create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("p107_xpt: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p107_xpt: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _frames(150)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _frames(20)
	g.enemies.kill_all(false)
	await _frames(30)
	_here = _ground(g.player.global_position)
	for k in range(5):
		_spawn("training_dummy", _here + Vector3(-4.0 + 2.0 * k, 0, -6.0 - 0.8 * (k % 2)))
	await _frames(10)
	var reg = root.get_node("Registry")
	for id: String in _weapons:
		var def = reg.weapon(id)
		if def == null:
			print("p107_xpt: no weapon ", id)
			continue
		var night = def.params.get("night_tint")
		for s: int in _looks:
			for phase in ["before", "after"]:
				if phase == "before":
					def.params.erase("night_tint")
				elif night != null:
					def.params["night_tint"] = night
				_look(s)
				await _fire(id)
				await _shot("%s_s%d_%s" % [id, s + 1, phase])
				paused = false
				g.projectiles.clear_all()
		if night != null:
			def.params["night_tint"] = night
	_save.data = keep
	quit(0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _spawn(id: String, at: Vector3) -> int:
	var i: int = g.enemies.spawn(id, _ground(at))
	_made.append(i)
	return i


func _freeze_creatures() -> void:
	var em = g.enemies
	for i: int in _made:
		if i >= 0 and i < em.alive.size() and em.alive[i] == 1:
			em.speed[i] = 0.0
			em.cooldown[i] = 99.0
			em.vel[i] = Vector3.ZERO


## The weapon alone at level 5 (made again, so the behaviour reads its params afresh), left to fire, then paused.
func _fire(id: String) -> void:
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _frames(5)
	_run.debug_set_item("weapon", id, 5)
	_run.build_changed.emit()
	for k in range(170):
		_freeze_creatures()
		g.player.global_position = _here + Vector3(0, 0.05, 0)
		await process_frame
	paused = true


func _look(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)
	var m = g.map
	if m.get("_hell_tween") and m._hell_tween:
		m._hell_tween.kill()
	if m.has_method("_apply_hell"):
		m._apply_hell(1.0 if sl.hell_of(sl._timeline(), s) else 0.0)
