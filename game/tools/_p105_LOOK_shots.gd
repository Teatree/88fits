## Pass 105, lane LOOK: what the stage filters do to the structures, the barrels, the chests, the weapons' 3D models,
## the hero's shots and the creatures' shots. The debug arena, the hero in god mode beside a barrel, a set piece round
## him (the Shop, a Totem Pole and a Teleport, a plain and a boss chest, training dummies to shoot at, a skeleton half
## behind a structure and one behind a barrel for their outlines), then:
##   mode=static  (the Sundown pixel check): no weapon, the tree paused after a fixed settle (run with --fixed-fps 60;
##                what still moves between two runs, shader TIME and the creatures' frames, is masked out by the compare)
##   mode=weapons (default): two builds in turn (A: Revolver, Tommy Gun, Orbit Saws, Land Mine, Turret Buddy;
##                B: Grenade family, Frisbee, Basketball, Rocket Pod, Salt), each left to fire, then the creatures' shots
##                thrown across the view (spit, pellet, spike, shard, harpoon, dynamite, the King's tumbleweeds, a Raider's
##                rocket), the tree paused, and the same frozen frame in each stage's look (StageLook.show_stage)
## Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p105_LOOK_shots.gd -- out=<dir> [mode=static|weapons] [looks=0,1,2] [ab=1]
## ab=1: after each build's shots, the frozen frame's draw calls in each look and once more with the pass's stencil marks
## taken off (what the marking costs in draws; the marks stay off until the game's sweep puts them back).
## A watchdog quits after 240 s whatever happens; every wait is bounded.
extends SceneTree

var _out := "user://p105_look"
var _mode := "weapons"
var _looks: Array = [0, 1, 2]
var _run
var _save
var g
var _made: Array = []
var _here := Vector3.ZERO
var _ab := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("mode="):
			_mode = a.substr(5)
		elif a == "ab=1":
			_ab = true
		elif a.begins_with("looks="):
			_looks = []
			for s in a.substr(6).split(",", false):
				_looks.append(int(s))
	DirAccess.make_dir_recursive_absolute(_out)
	seed(105)
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("p105_look: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p105_look: ", name)


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
	_place_hero()
	await _frames(10)
	_set_piece()
	await _frames(30)
	if _mode == "static":
		await _static()
	else:
		await _weapons("a", ["revolver", "tommy_gun", "orbit_saws", "land_mine", "turret_buddy"])
		await _weapons("b", ["lob_grenade", "frisbee", "basketball", "rocket_pod", "salt"])
	_save.data = keep
	quit(0)


## The hero three metres below (on the screen) the barrel nearest his start.
func _place_hero() -> void:
	var bf = g.barrels
	var start: Vector3 = g.player.global_position
	var best := -1
	var bd := INF
	for i in range(bf.pos.size()):
		var d: float = (bf.pos[i] - start).length()
		if bf.alive[i] == 1 and d < bd:
			bd = d
			best = i
	var at: Vector3 = start
	if best >= 0:
		at = bf.pos[best] + Vector3(-1.2, 0, 3.4)
	_here = _ground(at)
	print("p105_look: map_seed %s start %s barrel %d at %s" % [_run.map_seed, start, best, at])
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	if g.camera:
		g.camera.snap_to(g.player)


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


## Round the hero (-z is up the screen).
func _set_piece() -> void:
	var reg = root.get_node("Registry")
	var here := _here
	for sid in ["shop", "totem_pole", "teleport"]:
		var sd = reg.structure(sid)
		if sd == null or g.structures == null:
			continue
		var off: Vector3 = {"shop": Vector3(-4.2, 0, -7.5), "totem_pole": Vector3(3.6, 0, -8.5), "teleport": Vector3(4.4, 0, -2.5)}[sid]
		g.structures._spawn(sd, _ground(here + off))
	# a skeleton half behind the Shop (its outline), training dummies to shoot at
	_spawn("skeleton", here + Vector3(-3.6, 0, -8.6))
	for k in range(4):
		_spawn("training_dummy", here + Vector3(-3.0 + 2.0 * k, 0, -4.5 - 0.6 * (k % 2)))
	# the chests: a plain one and the boss's
	g.pickups.spawn_chest(_ground(here + Vector3(-3.0, 0, 2.6)))
	g.pickups.spawn_chest(_ground(here + Vector3(2.6, 0, 3.0)), true)
	# gems near the hero (they must still lie under the paintings and the shots)
	for k in range(5):
		g.pickups.spawn(k % 3, _ground(here + Vector3(-1.8 + 0.8 * k, 0, 1.4)), 1.0)
	_freeze_creatures()


func _static() -> void:
	for k in range(90):
		_freeze_creatures()
		await process_frame
	paused = true
	for s: int in _looks:
		_look(s)
		await _shot("static_s%d" % (s + 1))
	paused = false


func _weapons(tag: String, ids: Array) -> void:
	_run.debug_clear_items()
	for id: String in ids:
		_run.debug_set_item("weapon", id, 5)
	_run.build_changed.emit()
	for k in range(150):
		_freeze_creatures()
		await process_frame
	_enemy_shots()
	for k in range(14):
		_freeze_creatures()
		await process_frame
	paused = true
	_audit(tag)
	for s: int in _looks:
		_look(s)
		await _shot("%s_s%d" % [tag, s + 1])
	if _ab:
		await _draw_ab(tag)
	paused = false
	g.projectiles.clear_all()


## The creatures' shots, thrown across the view from its left edge.
func _enemy_shots() -> void:
	var here := _here
	var left := here + Vector3(-7.0, 0.9, 0)
	var kinds := [["spit", -1.5], ["pellet", -0.6], ["spike", 0.3], ["shard", 1.2], ["harpoon", 2.1]]
	for kv: Array in kinds:
		var from: Vector3 = left + Vector3(0, 0, float(kv[1]))
		var p := {"life": 3.0}
		if kv[0] == "harpoon":
			p["harpoon"] = true
		elif kv[0] != "spit":
			p["shot"] = kv[0]
		g.enemy_shot_straight(from, from + Vector3(12, 0, 0), 14.0, 0.0, 0.0, p)
	g.projectiles.hostile_dynamite(_ground(here + Vector3(-6.0, 0, -2.4)) + Vector3(0, 1.0, 0), _ground(here + Vector3(1.0, 0, -2.0)), 8.0, 0.0, 1.5, {})
	if g.has_method("tumbleweed_volley"):
		g.tumbleweed_volley(_ground(here + Vector3(5.5, 0, -1.0)), Vector3(-1, 0, 0), 3, 6.0, 0.0, 3.0, 0.0, 0.0, {})
	var r := _spawn("rocketeer", here + Vector3(5.5, 0, 1.0))
	if r >= 0 and g.get("_rocket_kind") != null and int(g._rocket_kind) >= 0:
		g.projectiles.launch_enemy_rocket(int(g._rocket_kind), r, _ground(here + Vector3(4.6, 0, 0.8)) + Vector3(0, 1.2, 0), Vector3(-1, 0, 0.1).normalized(), 4.0, 0.0, 0.0, 1.0)
	# a stalactite (the Gila's swoop) falling beside him
	if g.has_method("stalactite"):
		g.stalactite(_ground(here + Vector3(2.4, 0, 1.6)), 0.6, 1.0, 4.0)


func _look(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)
	# the hell ground at once (show_stage's fade is a tween, and the tree is paused)
	var m = g.map
	if m.get("_hell_tween") and m._hell_tween:
		m._hell_tween.kill()
	if m.has_method("_apply_hell"):
		m._apply_hell(1.0 if sl.hell_of(sl._timeline(), s) else 0.0)


## Every visible opaque mesh under the game that writes no stencil (the filter darkens it as sand): printed with its
## path, so a shot or a weapon's model the marking missed shows up (the map's own ground things are expected).
func _audit(tag: String) -> void:
	var SS = load("res://core/systems/StageStencil.gd")
	var seen := {}
	for gi in g.find_children("*", "GeometryInstance3D", true, false):
		if not (gi is MeshInstance3D or gi is MultiMeshInstance3D) or not (gi as Node3D).is_visible_in_tree():
			continue
		var mats: Array = []
		if gi.material_override:
			mats.append(gi.material_override)
		elif gi is MeshInstance3D and gi.mesh:
			for k in range(gi.mesh.get_surface_count()):
				mats.append(gi.get_active_material(k))
		elif gi is MultiMeshInstance3D and gi.multimesh and gi.multimesh.mesh:
			if gi.multimesh.visible_instance_count == 0:
				continue
			for k in range(gi.multimesh.mesh.get_surface_count()):
				mats.append(gi.multimesh.mesh.surface_get_material(k))
		for m in mats:
			if m != null and SS.is_opaque(m) and SS.written(m) == -1:
				var path := str(g.get_path_to(gi))
				var key: String = path.get_slice("/", 0) + "/" + path.get_slice("/", 1) + " " + gi.get_class()
				seen[key] = int(seen.get(key, 0)) + 1
	for k in seen:
		print("p105_look audit %s: unmarked %s x%d" % [tag, k, seen[k]])


func _draws() -> Array:
	var out: Array = []
	for k in range(6):
		await process_frame
		out.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return out


## The same frozen frame's draw calls with every look, then (stage 1's look) with the pass's stencil marks taken off every
## material again: what the marking itself costs in draws.
func _draw_ab(tag: String) -> void:
	for s: int in _looks:
		_look(s)
		print("p105_look draws %s s%d: %s" % [tag, s + 1, str(await _draws())])
	_look(0)
	var n := 0
	for gi in g.find_children("*", "GeometryInstance3D", true, false):
		var mats: Array = []
		if gi.material_override:
			mats.append(gi.material_override)
		if gi is MeshInstance3D and gi.mesh:
			for k in range(gi.mesh.get_surface_count()):
				mats.append(gi.get_active_material(k))
		if gi is MultiMeshInstance3D and gi.multimesh and gi.multimesh.mesh:
			for k in range(gi.multimesh.mesh.get_surface_count()):
				mats.append(gi.multimesh.mesh.surface_get_material(k))
		for m in mats:
			if m is BaseMaterial3D and m.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM and m.stencil_reference in [2, 3]:
				m.stencil_mode = BaseMaterial3D.STENCIL_MODE_DISABLED
				n += 1
			elif m is ShaderMaterial and m.shader and (m.shader.code.contains("stencil_mode write, compare_always, 2;") or m.shader.code.contains("stencil_mode write, compare_always, 3;")):
				var sh := Shader.new()
				sh.code = m.shader.code.replace("\nstencil_mode write, compare_always, 2;", "").replace("\nstencil_mode write, compare_always, 3;", "")
				m.shader = sh
				n += 1
	print("p105_look draws %s s1 unmarked (%d materials): %s" % [tag, n, str(await _draws())])
