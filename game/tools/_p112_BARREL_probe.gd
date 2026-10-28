## Pass 112 (lane BARREL) probe: a real stage-1 run (no arena), the hero in god mode, played for `secs` seconds of the
## respawn clock: every `every` seconds the hero is put beside the nearest barrel standing and smashes it; every barrel
## that comes back is checked off the screen the frame it appears (BarrelSpawns.seen against the camera's frustum and
## the rig's own on_screen); each power-up a barrel throws is watched land (its distance from the barrel and from the
## hero, whether it showed on the screen, whether anything took it before he walked to it), then he picks it up. Prints
## the totals.
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p112_BARREL_probe.gd -- secs=430 every=12
## A watchdog quits after `wall` seconds (default 420); the PC save is put back as it was.
extends SceneTree

var _secs := 430.0
var _wall := 420.0
var _every := 12.0
var _run
var _save
var g
var _thrown := {}
var _stats := {"smashed": 0, "back": 0, "back_on_screen": 0, "thrown": 0, "landed": 0, "landed_on_screen": 0,
	"taken_before_walk": 0, "collected": 0, "min_hero_d": INF, "min_from_d": INF, "max_from_d": 0.0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("secs="):
			_secs = float(a.substr(5))
		elif a.begins_with("wall="):
			_wall = float(a.substr(5))
		elif a.begins_with("every="):
			_every = float(a.substr(6))
	create_timer(_wall, true, false, true).timeout.connect(func() -> void:
		print("p112_probe: watchdog quit")
		_end(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _end(code: int) -> void:
	print("p112_probe: ", JSON.stringify(_stats))
	if _save:
		_save.end_sandbox()
	quit(code)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	root.get_node("Settings").show_hints = false
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "map": "red_canyon", "map_seed": 11, "stage": 1, "analytics": false, "spawn": true}))
	f.close()
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	g.player.god = true
	var bf = g.barrels
	var pm = g.pickups
	var known := {}
	for i in bf.pos.size():
		known[_key(bf, i)] = true
	var walk_t := 0.0
	var frames := 0
	while frames < int(_secs * 60.0) * 2:
		await process_frame
		frames += 1
		_screens()
		if frames % 600 == 0:
			print("p112_probe: frame %d paused=%s modal=%s up=%s clock=%.1f standing=%d stage=%.1f" % [frames, g.paused,
				str(g.current_modal()) if g.has_method("current_modal") else "?", str(g.visible_modals()) if g.has_method("visible_modals") else "?",
				bf.spawns.clock if bf.spawns else -1.0, bf.alive_count(), float(_run.stage_clock())])
		if g.paused:
			continue
		# a barrel that came back this frame: a slot standing at a spot not seen before
		var planes: Array = Array(g.camera.camera.get_frustum())
		for i in bf.pos.size():
			if bf.alive[i] == 1 and not known.has(_key(bf, i)):
				known[_key(bf, i)] = true
				_stats["back"] += 1
				var on: bool = BarrelSpawns.seen(planes, bf.pos[i], 0.0) or g.camera.on_screen(bf.pos[i])
				if on:
					_stats["back_on_screen"] += 1
				print("p112_probe: %.1f s barrel back (%s) %.1f m off, on screen %s (standing %d)" % [bf.respawn_clock().clock,
					"black" if bf.light[i] == 1 else "brown", _flat(bf.pos[i], g.player.global_position), on, bf.alive_count()])
		for p in pm.specials:
			if not is_instance_valid(p) or not bool(p.get("no_magnet")):
				continue
			var id: int = p.get_instance_id()
			if not _thrown.has(id):
				_thrown[id] = {"from": p._from, "landed": false, "t": 0.0}
				_stats["thrown"] += 1
			var rec: Dictionary = _thrown[id]
			if not rec["landed"] and not p.flying:
				rec["landed"] = true
				_stats["landed"] += 1
				var dc := _flat(p.global_position, rec["from"])
				var dh := _flat(p.global_position, g.player.global_position)
				_stats["min_from_d"] = minf(_stats["min_from_d"], dc)
				_stats["max_from_d"] = maxf(_stats["max_from_d"], dc)
				_stats["min_hero_d"] = minf(_stats["min_hero_d"], dh)
				if g.camera.on_screen(p.global_position):
					_stats["landed_on_screen"] += 1
				print("p112_probe: a %s landed %.1f m from its barrel, %.1f m from the hero, on screen %s" % [p.def.id, dc, dh, g.camera.on_screen(p.global_position)])
			if rec["landed"]:
				rec["t"] = float(rec["t"]) + 1.0 / 60.0
				if p.taken and float(rec["t"]) < 1.0 and not rec.has("walked"):
					_stats["taken_before_walk"] += 1
				elif float(rec["t"]) >= 1.0 and not p.taken and not rec.has("walked"):
					rec["walked"] = true
					g.player.global_position = p.global_position + Vector3(0.4, 0, 0)
					_stats["collected"] += 1
		walk_t += 1.0 / 60.0
		if walk_t >= _every and not _busy_throw(pm):
			walk_t = 0.0
			var best := -1
			var best_d := INF
			for i in bf.pos.size():
				if bf.alive[i] == 1:
					var d := _flat(bf.pos[i], g.player.global_position)
					if d < best_d:
						best_d = d
						best = i
			if best >= 0:
				var at: Vector3 = bf.pos[best] + Vector3(0, 0, 1.0)
				at.y = g.map.height_at(at.x, at.z)
				g.player.global_position = at
				if g.camera.has_method("snap_to"):
					g.camera.snap_to(g.player)
		if bf.respawn_clock().clock >= _secs:
			break
	_stats["smashed"] = bf.broken
	_stats["respawned"] = bf.respawned
	_stats["skipped"] = bf.spawns.skipped if bf.spawns else 0
	_stats["missed"] = bf.spawns.missed if bf.spawns else 0
	_stats["powerups_thrown"] = bf.powerups_thrown
	_stats["standing_end"] = bf.alive_count()
	_stats["clock"] = bf.spawns.clock if bf.spawns else 0.0
	_end(0)


func _key(bf, i: int) -> String:
	return "%d:%.2f,%.2f" % [i, bf.pos[i].x, bf.pos[i].z]


## A thrown power-up not walked to yet (the hero waits for it before the next barrel).
func _busy_throw(pm) -> bool:
	for p in pm.specials:
		if is_instance_valid(p) and bool(p.get("no_magnet")) and not p.taken:
			var rec = _thrown.get(p.get_instance_id())
			if rec == null or not rec.has("walked"):
				return true
	return false


func _screens() -> void:
	if g.cards and g.cards.visible and not g.cards._offer.is_empty() and not g.cards._picking:
		g.cards._pick(g.cards._offer[0])
	var ch = g.get("chest_screen")
	if ch and ch.visible:
		if ch._spinning:
			if ch.intro_playing():
				ch.skip_intro()
			return
		ch._finish(true)
	# pass 112 (lane WANTED): the floating Wanted posters after the landing: take the first
	var bp = g.get("bounty_posters")
	if bp and bp.visible and bp.has_method("is_done") and not bp.is_done():
		bp.choose(0)
	var gate = g.get("resume_gate")
	if gate and gate.visible:
		gate.tap()
	var ts = g.get("totem_screen")
	if ts and ts.visible and not ts._done:
		var tp: Array = ts.planks()
		if not tp.is_empty():
			ts._pick(tp[0])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
