## Pass 110 (lane VFX): before/after stills of the hero's explosions and of the Dragon's Breath against the hero.
## The debug arena, the hero in god mode, a small held pack of skeletons 5 m up the screen, then per section:
##   dynamite   the Dynamite Stick (lob_grenade level 5) going off on the pack
##   pod        a Rocket Pod volley (level 5)
##   mine       a Land Mine going off under a skeleton
##   pineapple  the Golden Pineapple (evolution) and its golden bomblets
##   keg        a Powder Keg (Game._powder_keg on the pack)
##   busy       the Dynamite Stick while the effect pool is full of other effects (a late-game crowd: perf_late measured
##              394 of 400 particles), the case the regression hid the blasts in
##   crowd      the Dynamite Stick and the Rocket Pod in a 40-creature crowd at the mid-run camera (zoom 1.5)
##   swarm      the Missile Massacre and the Cluster Bomb in a 60-creature crowd (the merging and the budget at work)
##   breath     the Dragon's Breath breathed up, up-left, up-right, right and down (task B: behind him in the back views)
## For every blast: a run of frames in Sundown after it goes off (+1 .. +40 ticks), and at +6 and +16 the same frame in
## Nightfall and Blood Moon (the tree paused, the stage's look switched). Each shot is cropped round the blast
## (<tag>_<section>_<moment>.png, 760 px square) and the first of a section is also saved whole.
## Windowed, the phone's canvas, fixed ticks:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p110_boom_shots.gd -- out=<dir> [only=dynamite,pod,...] [tag=before] [breath_front=1]
## (breath_front=1: the breath drawn over him in every view, as pass 109 drew it: the before of task B)
## A watchdog quits after 300 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

const CROP := 760
var _out := "user://p110_boom"
var _only: PackedStringArray = []
var _tag := "shot"
var _run
var _reg
var _save
var g
var _here := Vector3.ZERO
var _spot := Vector3.ZERO
var _made: Array = []
var _face := 0.0
var _face_on := false
var _view := ""
var _flip := false
var _busy := false
var _whole_done := {}
## breath_front=1: the fire drawn over him in every view, as pass 109 drew it (the before of task B): the puffs' material
## put back to the see-through queue's 0 each frame (BreathFlames.set_behind keeps its `behind` and leaves it so)
var _breath_front := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a == "breath_front=1":
			_breath_front = true
	DirAccess.make_dir_recursive_absolute(_out)
	seed(110)
	create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("p110_boom: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _on(s: String) -> bool:
	return _only.is_empty() or _only.has(s)


func _frames(n: int) -> void:
	for k in range(n):
		_hold()
		await process_frame


## Every frame: the creatures held where they stand, the hero facing where the section wants him, the effect pool kept
## full of invisible puffs while `_busy` (non-must emits, as a late-game crowd's hits, fire and dust are).
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
		g.player.set("_view", _view)
		g.player.set("_flip", _flip)
	if _breath_front and g._behaviors.has("dragons_breath"):
		var bf = g._behaviors["dragons_breath"].flames()
		if bf:
			for p in [bf.flames, bf.core]:
				((p as CPUParticles3D).mesh as QuadMesh).material.render_priority = 0
	if _busy and g.fx:
		var tries := 0
		while int(g.fx._n) < 385 and tries < 3000:
			tries += 1
			g.fx._emit(Vector3(0, -60.0, 0), Vector3.ZERO, 0.35, 0.1, 0.1, 0.0, 0.0, Color(1, 1, 1), 0.0, false, false)


func _save_shot(name: String, at: Vector3) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if not _whole_done.has(name.get_slice("_", 0)):
		_whole_done[name.get_slice("_", 0)] = true
		img.save_png(_out.path_join("%s_%s_whole.png" % [_tag, name]))
	var sp: Vector2 = g.camera.camera.unproject_position(at + Vector3(0, 0.8, 0))
	var w := img.get_width()
	var h := img.get_height()
	var x := clampi(int(sp.x) - CROP / 2, 0, maxi(w - CROP, 0))
	var y := clampi(int(sp.y) - CROP / 2, 0, maxi(h - CROP, 0))
	var c := img.get_region(Rect2i(x, y, mini(CROP, w), mini(CROP, h)))
	c.save_png(_out.path_join("%s_%s.png" % [_tag, name]))
	print("p110_boom: ", name)


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
	_spot = _ground(_here + Vector3(0, 0, -5.0))
	if _on("dynamite"):
		await _lobbed("dynamite", ["weapon", "lob_grenade", 5])
	if _on("pod"):
		await _lobbed("pod", ["weapon", "rocket_pod", 5], false)
	if _on("pineapple"):
		await _lobbed("pineapple", ["evolution", "golden_pineapple", 1])
	if _on("mine"):
		await _mine()
	if _on("keg"):
		await _keg()
	if _on("busy"):
		_busy = true
		await _lobbed("busy", ["weapon", "lob_grenade", 5])
		_busy = false
	if _on("crowd"):
		await _crowd()
	if _on("swarm"):
		await _swarm()
	if _on("breath"):
		await _breath()
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


func _start(item: Array) -> void:
	_clear()
	_look(0)
	_run.debug_clear_items()
	_run.debug_set_item(str(item[0]), str(item[1]), int(item[2]))
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	for k in range(5):
		_spawn("skeleton", _spot + Vector3(-1.6 + 0.8 * k, 0, 0.35 * float(k % 2)))
	g.enemies._rebuild_grid()
	await _frames(10)


## The shots after a blast at `at` that went off this frame: Sundown frames +1 .. +40, and at +6 and +16 the same
## moment in Nightfall and Blood Moon.
func _seq(name: String, at: Vector3) -> void:
	var t := 0
	for want in [1, 3, 6, 10, 16, 26, 40]:
		await _frames(want - t)
		t = want
		_save_shot("%s_s1_f%02d" % [name, want], at)
		if want == 6 or want == 16:
			paused = true
			for s in [1, 2]:
				_look(s)
				await _frames(2)
				_save_shot("%s_s%d_f%02d" % [name, s + 1, want], at)
			_look(0)
			await _frames(2)
			paused = false


func _where_landed(fallback: Vector3) -> Vector3:
	var l: Array = g.projectiles.get("_landed")
	if l is Array and not l.is_empty() and (l.back() as Dictionary).has("at"):
		return (l.back() as Dictionary)["at"]
	return fallback


# ---------------------------------------------------------------- lobbed and fired blasts

func _lobbed(name: String, item: Array, landed := true) -> void:
	await _start(item)
	var start: int = int(g.projectiles.lobs_exploded)
	var n := 0
	while int(g.projectiles.lobs_exploded) == start and n < 900:
		await _frames(1)
		n += 1
	if n >= 900:
		print("p110_boom: ", name, " never went off")
		return
	print("p110_boom: %s went off after %d frames, fx particles %d" % [name, n, int(g.fx._n)])
	await _seq(name, _where_landed(_spot) if landed else _spot)
	await _frames(30)


func _mine() -> void:
	await _start(["weapon", "land_mine", 5])
	var b = g._behaviors.get("land_mine")
	if b == null:
		print("p110_boom: no land_mine behaviour")
		return
	var n := 0
	while (b.mines() as Array).is_empty() and n < 600:
		await _frames(1)
		n += 1
	var ms: Array = b.mines()
	if ms.is_empty():
		print("p110_boom: no mine laid")
		return
	var mine: Node3D = ms[0]
	n = 0
	while not mine.is_armed() and n < 300:
		await _frames(1)
		n += 1
	# the mine moved under the pack's middle skeleton (held: it stands on it)
	var at := _ground(_spot + Vector3(1.6, 0, -2.0))
	mine.global_position = at
	await _frames(2)
	_spawn("skeleton", at)
	g.enemies._rebuild_grid()
	n = 0
	while is_instance_valid(mine) and int(mine.blasts) == 0 and n < 300:
		await _frames(1)
		n += 1
	print("p110_boom: mine went off after %d frames" % n)
	await _seq("mine", at)
	await _frames(30)


func _keg() -> void:
	await _start(["passive", "magnet", 1])
	await _frames(10)
	g._powder_keg(_spot, 400.0)
	await _seq("keg", _spot)
	await _frames(30)


func _crowd() -> void:
	_clear()
	_look(0)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "lob_grenade", 5)
	_run.debug_set_item("weapon", "rocket_pod", 5)
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	g.camera.zoom_override = 1.5
	var kinds := ["skeleton", "goblin", "bull_beetle", "fire_ant", "lesser_scorpion", "dust_mummy", "red_goblin"]
	for n in range(40):
		var ang := TAU * float(n) / 40.0 + randf_range(-0.2, 0.2)
		var rr := randf_range(3.0, 10.0)
		_spawn(kinds[n % kinds.size()], _here + Vector3(cos(ang) * rr, 0, sin(ang) * rr * 1.3))
	g.enemies._rebuild_grid()
	await _frames(10)
	var start: int = int(g.projectiles.lobs_exploded)
	var n2 := 0
	while int(g.projectiles.lobs_exploded) == start and n2 < 900:
		await _frames(1)
		n2 += 1
	var at := _where_landed(_spot)
	print("p110_boom: crowd blast after %d frames" % n2)
	var t := 0
	for want in [2, 6, 12, 24]:
		await _frames(want - t)
		t = want
		paused = true
		for s in [0, 1, 2]:
			_look(s)
			await _frames(2)
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(_out.path_join("%s_crowd_s%d_f%02d_whole.png" % [_tag, s + 1, want]))
		_look(0)
		await _frames(2)
		paused = false
	print("p110_boom: crowd done at ", at)
	_clear()
	await _frames(20)


## The heaviest case: the Missile Massacre and the Cluster Bomb in a 60-creature crowd at the mid-run camera, four
## whole frames over its first second and a half, with the blast pool's counts (full, merged, cheap) printed.
func _swarm() -> void:
	_clear()
	_look(0)
	_run.debug_clear_items()
	_run.debug_set_item("evolution", "missile_massacre", 1)
	_run.debug_set_item("evolution", "cluster_bomb", 1)
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	g.camera.zoom_override = 1.5
	var kinds := ["skeleton", "goblin", "bull_beetle", "fire_ant", "lesser_scorpion", "dust_mummy", "red_goblin"]
	for n in range(60):
		var ang := TAU * float(n) / 60.0 + randf_range(-0.2, 0.2)
		var rr := randf_range(3.5, 11.0)
		_spawn(kinds[n % kinds.size()], _here + Vector3(cos(ang) * rr, 0, sin(ang) * rr * 1.3))
	g.enemies._rebuild_grid()
	await _frames(10)
	var b0 := [int(g.fx.blasts), int(g.fx.blasts_merged), int(g.fx.blasts_cheap)]
	var start: int = int(g.projectiles.lobs_exploded)
	var n2 := 0
	while int(g.projectiles.lobs_exploded) == start and n2 < 900:
		await _frames(1)
		n2 += 1
	var t := 0
	for want in [8, 24, 50, 90]:
		await _frames(want - t)
		t = want
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("%s_swarm_s1_f%02d_whole.png" % [_tag, want]))
		print("p110_boom: swarm f%d: blast pieces %d, particles %d" % [want, int(g.fx.blast_count()), int(g.fx._n)])
	paused = true
	_look(1)
	await _frames(2)
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("%s_swarm_s2_f%02d_whole.png" % [_tag, t]))
	_look(0)
	await _frames(2)
	paused = false
	print("p110_boom: swarm blasts %d, merged %d, cheap %d in %d frames" % [int(g.fx.blasts) - b0[0], int(g.fx.blasts_merged) - b0[1], int(g.fx.blasts_cheap) - b0[2], t])
	_clear()
	await _frames(20)


# ---------------------------------------------------------------- the Dragon's Breath against the hero (task B)

func _breath() -> void:
	_clear()
	_look(0)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "dragons_breath", 5)
	_run.build_changed.emit()
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	g.camera.zoom_override = 0.55
	await _frames(10)
	var b = g._behaviors.get("dragons_breath")
	if b == null:
		print("p110_boom: no dragons_breath behaviour")
		return
	# facing (forward = (-sin f, 0, -cos f)), the painting's view and its mirror (Player._animate's rule)
	var dirs := [["up", 0.0, "", false], ["upleft", PI * 0.25, "_bd", true], ["upright", -PI * 0.25, "_bd", false],
		["right", -PI * 0.5, "_s", false], ["downright", -PI * 0.75, "_fd", false], ["down", PI, "_f", false]]
	for d: Array in dirs:
		_face = float(d[1])
		_view = str(d[2])
		_flip = bool(d[3])
		_face_on = true
		g.enemies.kill_all(false)
		_made.clear()
		var fwd := Vector3(-sin(_face), 0.0, -cos(_face))
		for k in range(3):
			_spawn("skeleton", g.player.global_position + fwd * (2.2 + 1.0 * float(k)) + Vector3(fwd.z, 0, -fwd.x) * (0.5 * float(k - 1)))
		g.enemies._rebuild_grid()
		await _frames(4)
		# a fresh breath in this direction
		var n := 0
		while b.burning() and n < 600:
			await _frames(1)
			n += 1
		await _frames(36)
		b.cooldown_left = 0.0
		n = 0
		while not b.burning() and n < 900:
			await _frames(1)
			n += 1
		await _frames(30)
		_save_shot("breath_%s" % str(d[0]), g.player.global_position + Vector3(0, 0.6, 0))
	g.camera.zoom_override = 0.0
	_face_on = false
