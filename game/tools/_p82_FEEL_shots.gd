## Pass 82 (lane FEEL) scratch capture: the hurt's HP-bar jiggle (the camera left still) and the bodies every weapon's
## kill throws, frame by frame in the debug arena. Sequences:
##   hurt   a 12-point hit on the hero: the bar under him, every frame (cropped round the bar), the camera logged
##   rev    the Revolver at a row of weak goblins up the screen
##   tommy  a Tommy Gun burst at the same row
##   saws   the Orbit Saws through a ring of weak goblins round the hero
##   beam   the Zap Beam at a row
##   laser  the Big Mouth's laser (no knockback at all) at a row
##   dyn    the dynamite thrown at a pack of weak goblins
## Windowed, fixed 60 fps, bounded waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p82_FEEL_shots.gd -- out=<dir> [seq=hurt,rev,...] [every=3] [frames=72] [crop=760]
## Writes <out>/<seq>_f<frame>.png and <out>/<seq>.txt (per frame: the dying bodies' place, height and push; the camera).
extends SceneTree

const WATCHDOG_S := 240.0

var _out := "user://p82_feel"
var _seqs: Array = ["hurt", "rev", "tommy", "saws", "beam", "laser", "dyn"]
var _every := 3
var _frames := 72
var _crop := 760
var _hp := 0.05
var _run
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("seq="):
			_seqs = Array(a.substr(4).split(",", false))
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("hp="):
			_hp = float(a.substr(3))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p82_feel: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames_wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p82_feel: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(1.0)
	for seq: String in _seqs:
		if seq == "hurt":
			await _hurt()
		else:
			await _film(seq)
	print("p82_feel: done -> ", _out)
	_save.data = keep
	quit(0)


# ---------------------------------------------------------------- the hurt

func _hurt() -> void:
	g.enemies.kill_all(false)
	_run.debug_clear_items()
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _frames_wait(30)
	var p = g.player
	var hud = g.hud
	var rig = g.camera
	var log := FileAccess.open(_out.path_join("hurt.txt"), FileAccess.WRITE)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var xf0: Transform3D = cam.global_transform
	for fr in range(-3, 24):
		if fr == 0:
			p.god = false
			p.invuln = 0.0
			p.shield_pts = 0.0
			var tries := 0
			p.take_damage(12.0, p.global_position + Vector3(1, 0, 0), {"by": "test"})
			while p.last_outcome != "hit" and tries < 20:
				p.invuln = 0.0
				p.take_damage(12.0, p.global_position + Vector3(1, 0, 0), {"by": "test"})
				tries += 1
			p.god = true
			log.store_line("hit: outcome %s, hp %.1f / %.1f, amp %.2f px" % [p.last_outcome, p.hp, p.max_hp, float(hud._hp_shake_amp)])
		await process_frame
		var moved: float = cam.global_transform.origin.distance_to(xf0.origin)
		log.store_line("f%03d bar_x %.2f px | shake_t %.3f | camera moved %.4f m | rig _shake %.3f" % [fr, float(hud.hp_shake_x), float(hud._hp_shake_t), moved, float(rig._shake)])
		var img := root.get_viewport().get_texture().get_image()
		if fr == -1 or fr == 6:
			img.save_png(_out.path_join("hurt_full_f%03d.png" % (fr + 3)))
		var c: Vector2 = hud._bar_c
		var w := 420
		var h := 160
		var x := clampi(int(c.x) - w / 2, 0, img.get_width() - w)
		var y := clampi(int(c.y) - 110, 0, img.get_height() - h)
		img.get_region(Rect2i(x, y, w, h)).save_png(_out.path_join("hurt_f%03d.png" % (fr + 3)))
	log.close()


# ---------------------------------------------------------------- the kills

func _weapon_of(seq: String) -> String:
	match seq:
		"rev":
			return "revolver"
		"tommy":
			return "tommy_gun"
		"saws":
			return "orbit_saws"
		"beam":
			return "zap_beam"
		"laser":
			return "big_mouth"
		"dyn":
			return "lob_grenade"
	return ""


func _film(seq: String) -> void:
	# no weapon while the crowd is laid out: it is given once the crowd stands (frame 0 of the film)
	g.enemies.kill_all(false)
	_run.debug_clear_items()
	_run.rebuild_sheets()
	_run.build_changed.emit()
	var wid := _weapon_of(seq)
	await _wait(0.4)
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	pm.clear_all()
	await _frames_wait(20)
	pm.clear_all()
	var here: Vector3 = g.player.global_position
	var centre := here + Vector3(0.0, 0, -6.0)
	var crowd: Array = []
	if seq == "saws":
		for k in range(10):
			var a := TAU * float(k) / 10.0
			var i: int = em.spawn("goblin", here + Vector3(cos(a), 0, sin(a)) * 2.4, null, 1.0, _hp)
			if i >= 0:
				crowd.append(i)
		centre = here
	elif seq == "dyn":
		centre = here + Vector3(0.6, 0, -6.0)
		for k in range(12):
			var a := TAU * float(k) / 12.0
			var r := 0.0 if k == 0 else 0.8 + 0.5 * float(k % 3)
			var i: int = em.spawn("goblin", centre + Vector3(cos(a), 0, sin(a)) * r, null, 1.0, _hp)
			if i >= 0:
				crowd.append(i)
	else:
		for k in range(6):
			var s := -2.5 + 5.0 * float(k) / 5.0
			var i: int = em.spawn("goblin", here + Vector3(s, 0, -5.5 - 0.8 * float(k % 2)), null, 1.0, _hp)
			if i >= 0:
				crowd.append(i)
		centre = here + Vector3(0, 0, -4.5)
	for i: int in crowd:
		em.speed[i] = 0.0
		# up out of the sand at once (a body killed while still rising is not thrown)
		em.rise_t[i] = 1.0
	em._rebuild_grid()
	await _frames_wait(10)
	_run.debug_set_item("weapon", wid, 3)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	var log := FileAccess.open(_out.path_join(seq + ".txt"), FileAccess.WRITE)
	log.store_line("seq %s weapon %s" % [seq, wid])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var t0_tosses: int = em.corpse_tosses
	var t0_land: int = em.corpse_landings
	var b = null
	var top: Dictionary = {}
	var start: Dictionary = {}
	var frames := _frames * 2 if seq == "dyn" else _frames
	for fr in range(frames):
		await process_frame
		if b == null:
			b = g._behaviors.get(wid)
			if b and b.get("cooldown_left") != null:
				b.cooldown_left = 1.0 / 60.0
		if b and seq in ["tommy"] and fr > 40:
			b.cooldown_left = 99.0
		if b and seq == "rev" and fr in [20, 40]:
			b.cooldown_left = 1.0 / 60.0
		var line := "f%03d tosses=%d landings=%d" % [fr, int(em.corpse_tosses) - t0_tosses, int(em.corpse_landings) - t0_land]
		for i: int in crowd:
			if em.alive[i] == 1 and em.state[i] == em.STATE_DYING:
				if not start.has(i):
					start[i] = em.pos[i]
				top[i] = maxf(float(top.get(i, 0.0)), float(em.lift_h[i]))
				line += " | %d dying pos=(%.2f,%.2f) h=%.2f kb=%.2f" % [i, em.pos[i].x, em.pos[i].z, em.lift_h[i], em.kb[i].length()]
		log.store_line(line)
		if fr % (_every * 2 if seq == "dyn" else _every) != 0:
			continue
		var img := root.get_viewport().get_texture().get_image()
		if _crop > 0 and cam:
			var sp: Vector2 = cam.unproject_position(centre)
			var x := clampi(int(sp.x) - _crop / 2, 0, img.get_width() - _crop)
			var y := clampi(int(sp.y) - _crop / 2, 0, img.get_height() - _crop)
			img = img.get_region(Rect2i(x, y, _crop, _crop))
		img.save_png(_out.path_join("%s_f%03d.png" % [seq, fr]))
	# per body: how high it flew and how far it went while it was seen dying
	for i: int in start.keys():
		var p0: Vector3 = start[i]
		var p1: Vector3 = em.pos[i]
		log.store_line("body %d: top %.2f m, went %.2f m" % [i, float(top.get(i, 0.0)), Vector2(p1.x - p0.x, p1.z - p0.z).length()])
	log.close()
	if b and b.get("cooldown_left") != null:
		b.cooldown_left = 99.0
	await _frames_wait(30)
