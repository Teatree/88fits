## Pass 109 (lane VFX): before/after stills for three looks. The debug arena, the hero in god mode, then:
##   rocket  the Vulture Raider's rocket in flight round the hero at the game's own camera distance (no zoom), the tree
##           paused, each stage's look (Sundown, Nightfall, Blood Moon), two moments a look (a pulsing material)
##   pod     the Rocket Pod (and the Hellfire Battery) firing at a pack, close up (zoom 0.45), a frame every 3 ticks
##           through a volley, then one frame at the game's distance
##   breath  the Dragon's Breath (and Blue Flame) breathed to the hero's right at a pack, frames through the 2 s breath
## Windowed, the phone's canvas, fixed ticks:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p109_vfx_shots.gd -- out=<dir> [only=rocket,pod,breath] [tag=before]
## A watchdog quits after 200 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://p109_vfx"
var _only: PackedStringArray = []
var _tag := "shot"
var _run
var _reg
var _save
var g
var _here := Vector3.ZERO
var _made: Array = []
var _face := 0.0
var _face_on := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	seed(109)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p109_vfx: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _on(s: String) -> bool:
	return _only.is_empty() or _only.has(s)


func _frames(n: int) -> void:
	for k in range(n):
		_hold()
		await process_frame


## Every frame: the creatures held where they stand, the hero facing where the section wants him.
func _hold() -> void:
	if g == null:
		return
	var em = g.enemies
	for i: int in _made:
		if i >= 0 and i < em.alive.size() and em.alive[i] == 1:
			em.speed[i] = 0.0
			em.cooldown[i] = 99.0
			em.vel[i] = Vector3.ZERO
	if _face_on and g.player:
		g.player.facing = _face


func _save_shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("%s_%s.png" % [_tag, name]))
	print("p109_vfx: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
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
	if _on("rocket"):
		await _rocket()
	if _on("pod"):
		await _pod("rocket_pod")
		await _pod("hellfire_battery")
	if _on("breath"):
		await _breath([], "breath")
		await _breath(["blue_flame"], "breath_blue")
	_save.data = keep
	quit(0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _spawn(id: String, at: Vector3) -> int:
	var i: int = g.enemies.spawn(id, _ground(at), null, 1.0, 60.0)
	_made.append(i)
	return i


func _clear() -> void:
	g.projectiles.clear_all()
	g.enemies.kill_all(false)
	_made.clear()
	_face_on = false
	g.camera.zoom_override = 0.0


func _look(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)
	var m = g.map
	if m.get("_hell_tween") and m._hell_tween:
		m._hell_tween.kill()
	if m.has_method("_apply_hell"):
		m._apply_hell(1.0 if sl.hell_of(sl._timeline(), s) else 0.0)


# ---------------------------------------------------------------- the Raider's rocket

func _rocket() -> void:
	_clear()
	_run.debug_clear_items()
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	await _frames(30)
	var here := _here
	# the Raider far off the right edge (his rockets stay his), three rockets crossing the view at the game's distance
	var r := _spawn("rocketeer", here + Vector3(14.0, 0, 0))
	var k: int = int(g._rocket_kind)
	g.projectiles.launch_enemy_rocket(k, r, _ground(here + Vector3(-4.5, 0, 1.5)) + Vector3(0, 1.1, 0), Vector3(1, 0, -0.25).normalized(), 4.0, 0.0, 0.0, 1.0)
	g.projectiles.launch_enemy_rocket(k, r, _ground(here + Vector3(2.5, 0, -5.0)) + Vector3(0, 1.1, 0), Vector3(-0.4, 0, 1).normalized(), 4.0, 0.0, 0.0, 1.0)
	g.projectiles.launch_enemy_rocket(k, r, _ground(here + Vector3(3.5, 0, 4.0)) + Vector3(0, 1.1, 0), Vector3(-1, 0, -0.6).normalized(), 4.0, 0.0, 0.0, 1.0)
	await _frames(24)
	paused = true
	for s in [0, 1, 2]:
		_look(s)
		await _frames(3)
		_save_shot("rocket_s%d_a" % (s + 1))
		await _frames(13)
		_save_shot("rocket_s%d_b" % (s + 1))
	_look(0)
	paused = false
	await _frames(4)
	# the real case: a crowd round him, the camera pulled out as it is mid-run (a levelled, running hero: zoom 1.5), the
	# rockets among the creatures
	_clear()
	g.camera.zoom_override = 1.5
	var kinds := ["skeleton", "goblin", "bull_beetle", "fire_ant", "lesser_scorpion", "dust_mummy", "red_goblin"]
	for n in range(46):
		var ang := TAU * float(n) / 46.0 + randf_range(-0.2, 0.2)
		var rr := randf_range(3.0, 11.0)
		_spawn(kinds[n % kinds.size()], here + Vector3(cos(ang) * rr, 0, sin(ang) * rr * 1.3))
	var r2 := _spawn("rocketeer", here + Vector3(16.0, 0, 0))
	await _frames(20)
	g.projectiles.launch_enemy_rocket(k, r2, _ground(here + Vector3(-6.5, 0, 3.0)) + Vector3(0, 1.0, 0), Vector3(1, 0, -0.3).normalized(), 4.0, 0.0, 0.0, 1.0)
	g.projectiles.launch_enemy_rocket(k, r2, _ground(here + Vector3(4.0, 0, -8.0)) + Vector3(0, 1.0, 0), Vector3(-0.3, 0, 1).normalized(), 4.0, 0.0, 0.0, 1.0)
	g.projectiles.launch_enemy_rocket(k, r2, _ground(here + Vector3(6.0, 0, 6.5)) + Vector3(0, 1.0, 0), Vector3(-1, 0, -0.5).normalized(), 4.0, 0.0, 0.0, 1.0)
	await _frames(24)
	paused = true
	for s in [0, 1, 2]:
		_look(s)
		await _frames(3)
		_save_shot("rocket_crowd_s%d" % (s + 1))
	_look(0)
	paused = false
	await _frames(4)
	_clear()


# ---------------------------------------------------------------- the Rocket Pod

func _pod(wid: String) -> void:
	_clear()
	_run.debug_clear_items()
	var def = _reg.weapon(wid)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, 5 if not def.is_evolution else 1)
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	for k in range(5):
		_spawn("skeleton", _here + Vector3(-3.0 + 1.5 * k, 0, -8.0))
	g.enemies._rebuild_grid()
	g.camera.zoom_override = 0.45
	await _frames(20)
	var b = g._behaviors.get(wid)
	if b == null:
		print("p109_vfx: no behaviour for ", wid)
		return
	# wait for the next volley to start
	var start: int = int(b.bursts)
	var n := 0
	while int(b.bursts) == start and n < 600:
		await _frames(1)
		n += 1
	for f in range(16):
		_save_shot("%s_close_f%02d" % [wid, f * 3])
		await _frames(3)
	g.camera.zoom_override = 0.0
	start = int(b.bursts)
	n = 0
	while int(b.bursts) == start and n < 600:
		await _frames(1)
		n += 1
	await _frames(8)
	_save_shot("%s_game_f08" % wid)


# ---------------------------------------------------------------- the Dragon's Breath

func _breath(muts: Array, name: String) -> void:
	_clear()
	_run.debug_clear_items()
	for m in muts:
		_run.debug_set_item("mutation", str(m), 1)
	_run.debug_set_item("weapon", "dragons_breath", 5)
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	_face = -PI * 0.5  # forward (1, 0, 0): to his right
	_face_on = true
	for k in range(4):
		_spawn("skeleton", _here + Vector3(2.5 + 0.9 * k, 0, -0.8 + 0.55 * k))
	g.enemies._rebuild_grid()
	await _frames(10)
	var b = g._behaviors.get("dragons_breath")
	if b == null:
		print("p109_vfx: no dragons_breath behaviour")
		return
	b.cooldown_left = 0.0
	var n := 0
	while not b.burning() and n < 900:
		await _frames(1)
		n += 1
	print("p109_vfx: breath started after %d frames, %.2f s long" % [n, b.last_len])
	var at := 0
	for want in [4, 12, 30, 60, 90, 116]:
		await _frames(want - at)
		at = want
		_save_shot("%s_t%03d" % [name, want])
	g.camera.zoom_override = 0.5
	await _frames(1)
	if not b.burning():
		b.cooldown_left = 0.0
		n = 0
		while not b.burning() and n < 900:
			await _frames(1)
			n += 1
	await _frames(40)
	_save_shot("%s_close" % name)
	await _frames(150)
	_save_shot("%s_after" % name)
