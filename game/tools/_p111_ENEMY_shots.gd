## Pass 111 (lane ENEMY): frame sequences of the four creature changes, in the debug arena with the hero in god mode and
## no weapons (nothing dies):
##   mummy    the Cyclopean Mummy (look `look=`, default CM-F) walking left and right, from the front and from behind,
##            beside two skeletons (which still mirror); whole frames + a crop round each creature
##   bomb     the Spit Cactus's bomb: a throw down the screen and one across it (the arc), every 3rd tick from the wind-up
##            to the blast, and the same moments in Nightfall; compare=1 also throws the old dynamite stick (tag "stick")
##   harpoon  the harpooner: the wind-up (rear-back, glint), the launch, the chain in flight, the hook-in and the haul;
##            then a miss (the hero stepped aside after the throw) and the reel home; the same moments in Nightfall
## Windowed, the phone's canvas, fixed ticks:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game \
##       --script res://tools/_p111_ENEMY_shots.gd -- out=<dir> [only=mummy,bomb,harpoon] [look=CM-F] [compare=1]
## A watchdog quits after 280 s whatever happens; every wait is bounded. The PC save is put back as it was.
extends SceneTree

const CROP := 760
var _out := "user://p111_enemy"
var _only: PackedStringArray = []
var _look_code := "CM-F"
var _compare := false
## strip=pulse,trail,spark,rim: a probe of what colours the bomb (its def's blocks changed for this run only)
var _strip: PackedStringArray = []
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
			_look_code = a.substr(5)
		elif a == "compare=1":
			_compare = true
		elif a.begins_with("strip="):
			_strip = a.substr(6).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	seed(111)
	create_timer(280.0, true, false, true).timeout.connect(func() -> void:
		print("p111_enemy: watchdog quit")
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


func _shot(name: String, at: Vector3, crop := CROP, whole := false) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if whole:
		img.save_png(_out.path_join("%s_whole.png" % name))
	if crop <= 0:
		# the whole screen at half size
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
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
	g.enemies.kill_all(false)
	await _frames(30)
	_here = _ground(g.player.global_position)
	if _on("mummy"):
		await _mummy()
	if _on("bomb"):
		if not _strip.is_empty():
			var rg0: Dictionary = _reg_def("spit_cactus").ranged
			var bb: Dictionary = rg0["bomb"]
			if _strip.has("pulse"):
				rg0.erase("pulse")
			if _strip.has("trail"):
				bb.erase("trail")
			if _strip.has("spark"):
				bb["spark"] = {"size": 0.0}
			if _strip.has("rim"):
				bb["material"] = {"roughness": 0.9, "metallic": 0.0, "specular": 0.0}
		await _bomb("bomb", Vector3(0, 0, -7.0))
		await _bomb("bomb_across", Vector3(6.5, 0, -1.0))
		if _compare:
			var rg: Dictionary = g.enemies.types[g.enemies.type_by_id["spit_cactus"]]["def"].ranged
			rg["shot"] = "dynamite"
			await _bomb("stick_across", Vector3(6.5, 0, -1.0))
			rg["shot"] = "bomb"
	if _on("harpoon"):
		await _harpoon()
	_save.data = keep
	quit(0)


func _reg_def(id: String) -> EnemyDef:
	return root.get_node("Registry").enemy(id)


func _clear() -> void:
	g.projectiles.clear_all()
	g.enemies.kill_all(false)
	g.camera.zoom_override = 0.0
	await _frames(20)
	g.player.global_position = _here + Vector3(0, 0.05, 0)
	g.camera.snap_to(g.player)
	_stage(0)


func _stage(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)
	var m = g.map
	if m.get("_hell_tween") and m._hell_tween:
		m._hell_tween.kill()
	if m.has_method("_apply_hell"):
		m._apply_hell(1.0 if sl.hell_of(sl._timeline(), s) else 0.0)


func _put(id: String, off: Vector3, variant := "") -> int:
	var i: int = g.enemies.spawn(id, _ground(_here + off), null, 1.0, 400.0, variant)
	if i >= 0:
		g.enemies.rise_t[i] = 1.0
		g.enemies.vspecial[i] = 0
	return i


# ---------------------------------------------------------------- the mummy

func _mummy() -> void:
	await _clear()
	var em = g.enemies
	# right of him walking left, left of him walking right, below him walking up (from behind) both ways, skeletons above
	var made := {
		"front_left": _put("cyclopean_mummy", Vector3(5.5, 0, -1.0), _look_code),
		"front_right": _put("cyclopean_mummy", Vector3(-5.5, 0, -1.0), _look_code),
		"back_left": _put("cyclopean_mummy", Vector3(4.5, 0, 5.0), _look_code),
		"back_right": _put("cyclopean_mummy", Vector3(-4.5, 0, 5.0), _look_code),
		"skel_left": _put("skeleton", Vector3(5.0, 0, -5.5)),
		"skel_right": _put("skeleton", Vector3(-5.0, 0, -5.5)),
	}
	em._rebuild_grid()
	for k in range(4):
		await _frames(9 if k > 0 else 30)
		for key in made.keys():
			var i: int = made[key]
			if i < 0 or em.alive[i] == 0:
				continue
			var d: Vector2i = em.drawn_frame(i)
			print("p111_enemy: mummy %s f%d frame %d mirrored %d flip %d away %d" % [key, k, d.x, d.y, em.flip[i], em.away[i]])
			_shot("mummy_%s_%s_f%d" % [_look_code, key, k], em.pos[i] + Vector3(0, em.size[i] * 0.5, 0), 360, k == 0 and key == "front_left")


# ---------------------------------------------------------------- the bomb

func _bomb(name: String, off: Vector3) -> void:
	await _clear()
	g.camera.zoom_override = 1.3
	await _frames(10)
	var em = g.enemies
	var pm = g.projectiles
	var c := _put("spit_cactus", off)
	em.cooldown[c] = 0.0
	em._rebuild_grid()
	var mid: Vector3 = _here.lerp(em.pos[c], 0.5) + Vector3(0, 1.5, 0)
	var thrown0: int = int(pm.dynamite_thrown)
	var blasts0: int = int(pm.dynamite_blasts)
	var n := 0
	var shots := 0
	var night_done := false
	while n < 420 and int(pm.dynamite_blasts) == blasts0:
		await _frames(1)
		n += 1
		# from the wind-up on: every 3rd tick
		if em.state[c] == em.STATE_WINDUP or int(pm.dynamite_thrown) > thrown0:
			if n % 3 == 0 and shots < 60:
				_shot("%s_f%03d" % [name, n], mid, 1060, shots == 0)
				shots += 1
			# the bomb at the top of its arc, and lying with its fuse lit, in Nightfall too
			if not night_done and int(pm.dynamite_thrown) > thrown0 and _flying_top(pm):
				night_done = true
				paused = true
				_stage(1)
				await _frames(2)
				_shot("%s_night_top" % name, mid, 1060)
				_stage(0)
				await _frames(2)
				paused = false
	for k in [2, 6, 12, 20]:
		await _frames(2 if k == 2 else 4)
		_shot("%s_blast_f%02d" % [name, k], mid, 1060)
	print("p111_enemy: %s thrown %d, blasts %d after %d ticks, apex %.2f" % [name, int(pm.dynamite_thrown) - thrown0, int(pm.dynamite_blasts) - blasts0, n, float(pm.last_throw_apex)])


## Whether a creature's throw is at the top of its arc this tick.
func _flying_top(pm) -> bool:
	for i in range(pm.MAX):
		if pm.alive[i] == 1 and pm.hostile[i] == 1 and (pm.extra[i] as Dictionary).has("dynamite") and not (pm.extra[i] as Dictionary).has("lie_t"):
			return pm.vel[i].y <= 0.0
	return false


# ---------------------------------------------------------------- the harpoon

func _harpoon() -> void:
	await _clear()
	g.camera.zoom_override = 1.35
	await _frames(10)
	var em = g.enemies
	var h := _put("harpoon_troglodyte", Vector3(7.0, 0, -10.5))
	em.cooldown[h] = 0.0
	em._rebuild_grid()
	var mid: Vector3 = _here.lerp(em.pos[h], 0.5) + Vector3(0, 1.2, 0)
	var n := 0
	var shots := 0
	var started := false
	var hooked_at := -1
	while n < 360:
		await _frames(1)
		n += 1
		if em.state[h] == em.STATE_WINDUP:
			started = true
		var flying: bool = g.get("_harpoon_proj") != null and int(g._harpoon_proj) >= 0
		if started and shots < 70 and ((flying or hooked_at > 0) and n % 2 == 0 or n % 6 == 0):
			_shot("harpoon_hit_f%03d" % n, mid, 0, shots == 0)
			shots += 1
		if hooked_at < 0 and g.tether_i >= 0:
			hooked_at = n
			paused = true
			_stage(1)
			await _frames(2)
			_shot("harpoon_hit_night", mid, 0)
			_stage(0)
			await _frames(2)
			paused = false
		if hooked_at > 0 and n > hooked_at + 50:
			break
	print("p111_enemy: harpoon hooked at tick %d, chain links %d" % [hooked_at, int(g.harpoon_chain().links_drawn)])
	g.tether_end()
	# a miss: the next throw, the hero steps 3 m aside the moment it leaves
	await _clear()
	g.camera.zoom_override = 1.35
	h = _put("harpoon_troglodyte", Vector3(7.0, 0, -10.5))
	em.cooldown[h] = 0.0
	em._rebuild_grid()
	var thrown := false
	n = 0
	shots = 0
	var reels0: int = int(g.harpoon_chain().reels)
	while n < 360:
		await _frames(1)
		n += 1
		if not thrown and g.get("_harpoon_proj") != null and int(g._harpoon_proj) >= 0:
			thrown = true
			g.player.global_position = _ground(_here + Vector3(0, 0, 3.5)) + Vector3(0, 0.05, 0)
		if thrown and n % 2 == 0 and shots < 80:
			_shot("harpoon_miss_f%03d" % n, mid, 0)
			shots += 1
		if thrown and int(g.harpoon_chain().reels) > reels0 and not g.harpoon_chain().reeling():
			break
	print("p111_enemy: harpoon miss reels %d, tether %d" % [int(g.harpoon_chain().reels) - reels0, int(g.tether_i)])
