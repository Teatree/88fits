## Pass 111 (lane CHEST) probe: a real stage-1 run (no arena), the hero in god mode, played for `secs` seconds of the
## run's clock: every map chest is checked off the screen the frame it appears (WorldChests.seen against the camera's
## frustum and the rig's own on_screen), the hero is walked onto it (a teleport beside it), the reel is taken, and each
## power-up a chest throws is watched land (its distance from the chest and from the hero, whether it showed on the
## screen, whether anything took it before he walked to it), then he picks it up. Prints the totals.
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p111_CHEST_probe.gd -- secs=400
## A watchdog quits after `wall` seconds (default 420); the PC save is put back as it was.
extends SceneTree

var _secs := 400.0
var _wall := 420.0
var _run
var _save
var g
var _seen_ids := {}
var _thrown := {}
var _lines: Array = []
var _stats := {"world": 0, "world_on_screen": 0, "opened": 0, "thrown": 0, "landed": 0, "landed_on_screen": 0,
	"taken_before_walk": 0, "collected": 0, "min_hero_d": INF, "min_chest_d": INF, "max_chest_d": 0.0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("secs="):
			_secs = float(a.substr(5))
		elif a.begins_with("wall="):
			_wall = float(a.substr(5))
	create_timer(_wall, true, false, true).timeout.connect(func() -> void:
		print("p111_probe: watchdog quit")
		_end(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _end(code: int) -> void:
	print("p111_probe: ", JSON.stringify(_stats))
	if _save:
		_save.end_sandbox()
	quit(code)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	# no hints (nobody reads them; one paused the run at 0:22)
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
	var pm = g.pickups
	var walk_t := 0.0
	var frames := 0
	while frames < int(_secs * 60.0) + 600:
		await process_frame
		frames += 1
		_screens()
		if g.paused:
			if frames % 600 == 0 and g.has_method("visible_modals"):
				print("p111_probe: paused: modal=%d queue=%s up=%s" % [int(g.current_modal()), str(g.modal_queue_kinds()), str(g.visible_modals())])
			continue
		var planes: Array = Array(g.camera.camera.get_frustum())
		for c in pm.chests:
			if is_instance_valid(c) and c.world and not _seen_ids.has(c.get_instance_id()):
				_seen_ids[c.get_instance_id()] = true
				_stats["world"] += 1
				var on: bool = WorldChests.seen(planes, c.global_position, 0.0) or g.camera.on_screen(c.global_position)
				if on:
					_stats["world_on_screen"] += 1
				print("p111_probe: %.1f s map chest %d at %.1f m, on screen %s (lying %d)" % [float(_run.stage_clock()),
					_stats["world"], _flat(c.global_position, g.player.global_position), on, pm.world_lying()])
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
				_stats["min_chest_d"] = minf(_stats["min_chest_d"], dc)
				_stats["max_chest_d"] = maxf(_stats["max_chest_d"], dc)
				_stats["min_hero_d"] = minf(_stats["min_hero_d"], dh)
				if g.camera.on_screen(p.global_position):
					_stats["landed_on_screen"] += 1
				print("p111_probe: a %s landed %.1f m from its chest, %.1f m from the hero, on screen %s" % [p.def.id, dc, dh, g.camera.on_screen(p.global_position)])
			if rec["landed"]:
				rec["t"] = float(rec["t"]) + 1.0 / 60.0
				if p.taken and float(rec["t"]) < 1.0:
					_stats["taken_before_walk"] += 1
				elif float(rec["t"]) >= 1.0 and not p.taken and not rec.has("walked"):
					# a second lying there: he walks over for it
					rec["walked"] = true
					g.player.global_position = p.global_position + Vector3(0.4, 0, 0)
					_stats["collected"] += 1
		# every half second: off to the nearest map chest lying
		walk_t += 1.0 / 60.0
		if walk_t >= 0.5:
			walk_t = 0.0
			var c = pm.pointer_chest()
			if c != null and not _busy_throw(pm):
				var dir := Vector3(0, 0, 1)
				var at: Vector3 = c.global_position + dir * 1.0
				at.y = g.map.height_at(at.x, at.z)
				g.player.global_position = at
				if g.camera.has_method("snap_to"):
					g.camera.snap_to(g.player)
		if pm.world != null and pm.world.clock >= _secs:
			break
	_stats["frames"] = frames
	_stats["stage_clock"] = float(_run.stage_clock())
	_stats["chest_clock"] = pm.world.clock if pm.world else 0.0
	_stats["opened"] = _run.chests_opened
	_stats["spawned_by_clock"] = pm.world.spawned if pm.world else 0
	_stats["skipped"] = pm.world.skipped if pm.world else 0
	_stats["missed"] = pm.world.missed if pm.world else 0
	_stats["expired"] = pm.world.expired if pm.world else 0
	_stats["chest_powerups"] = pm.chest_powerups
	_end(0)


## A thrown power-up not walked to yet (the hero waits for it before the next chest).
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
