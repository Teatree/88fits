## Pass 112 (lane MONK): the Monk's squad in the debug arena, the hero in god mode with no weapons (nothing dies):
##   north   a squad of 20 coming in from up the screen (facing the camera): walking frames, then its volley: the hands
##           rising, the glow gathering, the spheres leaving and in flight; one of those again in Nightfall
##   south   a squad of 10 below the hero (its back to the camera): its volley from behind
## Windowed, the phone's canvas, fixed ticks:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p112_MONK_shots.gd -- out=<dir> [only=north,south] [look=MK-A] [preview_views=1]
## `look` is the creature look worn (default MK-A when the JSON has it, else its own); preview_views=1 (the default) plays
## the attack strip as front | back halves (attack_views "front_back") for a look whose entry does not say so yet.
## A watchdog quits after 240 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _out := "user://p112_monk"
var _only: PackedStringArray = []
var _look := ""
var _preview_views := true
var _run
var _save
var g
var _here := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("look="):
			_look = a.substr(5)
		elif a == "preview_views=0":
			_preview_views = false
	DirAccess.make_dir_recursive_absolute(_out)
	seed(112)
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("p112_monk: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _on(s: String) -> bool:
	return _only.is_empty() or _only.has(s)


func _frames(n: int) -> void:
	for k in range(n):
		if g != null and g.player:
			g.player.velocity = Vector3.ZERO
		await process_frame


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _shot(name: String, at: Vector3, crop := 0) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if crop <= 0:
		img.save_png(_out.path_join("%s.png" % name))
		return
	var sp: Vector2 = g.camera.camera.unproject_position(at)
	var w := img.get_width()
	var h := img.get_height()
	var x := clampi(int(sp.x) - crop / 2, 0, maxi(w - crop, 0))
	var y := clampi(int(sp.y) - crop / 2, 0, maxi(h - crop, 0))
	img.get_region(Rect2i(x, y, mini(crop, w), mini(crop, h))).save_png(_out.path_join("%s.png" % name))


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
	var def: EnemyDef = root.get_node("Registry").enemy("monk")
	if _look == "" and def.variants.has("MK-A"):
		_look = "MK-A"
	print("p112_monk: look %s" % (_look if _look != "" else def.variant_base))
	if _on("north"):
		await _north()
	if _on("south"):
		await _south()
	_save.data = keep
	quit(0)


func _clear() -> void:
	g.projectiles.clear_all()
	g.enemies.kill_all(false)
	if g.enemies.squads != null and g.enemies.squads.orbs != null:
		g.enemies.squads.orbs.clear()
	await _frames(20)
	_here = _ground(g.player.global_position)
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	_stage(0)


func _stage(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)


## A squad of `n` round `off` from the hero, in the look asked for; the type's attack strip as front | back halves when the
## look does not say so yet (preview_views). Returns the squad.
func _squad(n: int, off: Vector3) -> Dictionary:
	var em = g.enemies
	em.spawn_pack("monk", _ground(_here + off), n, null, _look)
	var sq: Dictionary = {}
	for s in em.squads.list.values():
		sq = s
	var t: int = int(sq["t"])
	if _preview_views and em._t_atkv[t] == 0:
		em._t_atkv[t] = 1
		print("p112_monk: previewing the attack strip as front | back halves (the look's entry has no attack_views yet)")
	return sq


func _attack_shots(sq: Dictionary, name: String, mid: Vector3, night := false) -> void:
	var em = g.enemies
	var cfg: Dictionary = em.squads.cfg_of(int(sq["t"]))
	var rise := float(cfg["rise"])
	var release := float(cfg["release"])
	# the volley soon
	sq["cd"] = minf(float(sq["cd"]), 0.3)
	var n := 0
	while float(sq["atk"]) < 0.0 and n < 900:
		await _frames(1)
		n += 1
	print("p112_monk: %s volley after %d ticks (atk %.2f)" % [name, n, float(sq["atk"])])
	var marks := [["a_rise", rise * 0.5], ["b_up", rise + 0.15], ["c_glow_full", release - 0.06], ["d_released", release + 0.12],
		["e_flight", release + 0.6], ["f_flight", release + 1.4]]
	for m in marks:
		var want: float = m[1]
		var guard := 0
		while float(sq["atk"]) < want and float(sq["atk"]) >= 0.0 and guard < 400:
			await _frames(1)
			guard += 1
		_shot("%s_%s" % [name, m[0]], mid, 0)
		_shot("%s_%s_crop" % [name, m[0]], mid, 900)
		var mem: PackedInt32Array = sq["members"]
		if mem.size() > 0:
			var i: int = mem[0]
			var d: Vector2i = em.drawn_frame(i)
			print("p112_monk: %s %s atk %.2f state %d frame %d view %d away %d glows %d spheres %d" % [name, m[0], float(sq["atk"]),
				em.state[i], d.x, em.view[i], em.away[i], em.squads.glow_pts.size(), em.squads.orbs.count if em.squads.orbs else 0])
		if night and m[0] == "e_flight":
			paused = true
			_stage(1)
			await _frames(2)
			_shot("%s_e_flight_nightfall" % name, mid, 0)
			_stage(0)
			await _frames(2)
			paused = false


func _north() -> void:
	await _clear()
	var em = g.enemies
	var sq := _squad(20, Vector3(0, 0, -17.0))
	# no volley while it walks in
	sq["cd"] = 99.0
	var a0: Vector3 = sq["anchor"]
	for k in range(4):
		await _frames(30 if k > 0 else 40)
		var a: Vector3 = sq["anchor"]
		var mid := a.lerp(_here, 0.35) + Vector3(0, 1.0, 0)
		_shot("north_walk_f%d" % k, mid, 0)
		_shot("north_walk_f%d_crop" % k, a + Vector3(0, 1.0, 0), 900)
		print("p112_monk: north walk %d anchor %s moved %.2f members %d radius %.2f" % [k, a, Vector2(a.x - a0.x, a.z - a0.z).length(),
			(sq["members"] as PackedInt32Array).size(), float(sq["radius"])])
	# into its band, then the volley
	var guard := 0
	while (sq["vel"] as Vector3).length() > 0.05 and guard < 600:
		await _frames(1)
		guard += 1
	var at: Vector3 = sq["anchor"]
	print("p112_monk: north stands at %.2f m from the hero (edge %.2f)" % [Vector2(at.x - _here.x, at.z - _here.z).length(),
		Vector2(at.x - _here.x, at.z - _here.z).length() - float(sq["radius"])])
	await _attack_shots(sq, "north", at.lerp(_here, 0.35) + Vector3(0, 1.0, 0), true)


func _south() -> void:
	await _clear()
	# the camera pulled out a little: the screen shows less below the hero than above him
	g.camera.zoom_override = 1.4
	var sq := _squad(10, Vector3(0, 0, 8.0))
	sq["cd"] = 99.0
	await _frames(60)
	var guard := 0
	while (sq["vel"] as Vector3).length() > 0.05 and guard < 600:
		await _frames(1)
		guard += 1
	var at: Vector3 = sq["anchor"]
	await _attack_shots(sq, "south", at.lerp(_here, 0.35) + Vector3(0, 1.0, 0))
	g.camera.zoom_override = 0.0
