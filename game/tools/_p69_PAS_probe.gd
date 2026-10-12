## Pass 69, lane PAS, a headless probe of the five new passive items and the Magnet in the live game: the debug arena,
## the Drifter with every one of them (and Evade and Thirst so evades and heals come), a crowd kept round him that hits
## for real, gems scattered as he goes, for `seconds` of game time. Prints what each item did and checks the engine's
## clock is back at 1x at the end. Exit 0 when everything ran, 2 when a check failed.
##   godot --headless --fixed-fps 60 --path game --script res://tools/_p69_PAS_probe.gd -- seconds=60
extends SceneTree

var _seconds := 60.0
var g
var _run
var _save
var _reg
var _t := 0.0
var _stands := 0
var _pulses := 0
var _pulse_dmg := 0.0
var _evades := 0
var _arms := 0
var _max_over := 0.0
var _min_scale := 1.0
var _slow_frames := 0
var _deaths := 0
var _bad: Array = []
var _marks := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_seconds = float(a.substr(8))
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	create_timer(600.0, true, false, true).timeout.connect(func():
		print("p69_probe: watchdog quit")
		Engine.time_scale = 1.0
		quit(3))


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(30):
		await process_frame
	g = current_scene
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	for k in range(10):
		await process_frame
	for pair in [["counterpunch", 5], ["heavyweight", 5], ["snake_oil", 3], ["hot_springs", 3], ["last_stand", 3], ["magnet", 5],
			["evade", 4], ["thirst", 4]]:
		_run.debug_set_item("passive", str(pair[0]), int(pair[1]))
	# a weapon that fires now and then (Counterpunch's attack) but kills little: the crowd must reach him
	_run.debug_set_item("weapon", "revolver", 1)
	_run.build_changed.emit()
	await process_frame
	g.player.refresh_stats()
	g.player.hp = g.player.max_hp
	# the arena starts in god mode: off, the hits must land
	g.player.god = false
	g.player.last_stand.connect(func(): _stands += 1)
	g.player.heal_pulsed.connect(func(d: float, _h: float):
		_pulses += 1
		_pulse_dmg += d)
	g.player.evaded.connect(func():
		_evades += 1
		if _run.counter_armed:
			_arms += 1)
	g.player.died.connect(func(): _deaths += 1)
	print("p69_probe: items ", _run.passives, "  might x%.2f (Heavyweight %s)  max HP %.0f  overheal cap %.0f  pull %.1f m" % [
		_run.player_sheet.get_stat("might", 1.0), _run.heavyweight_might(), g.player.max_hp, g.player.overheal_cap(), g.pickups.xp_pull_radius()])
	var spawn_t := 0.0
	var gem_t := 0.0
	while _t < _seconds:
		await process_frame
		var dt := 1.0 / 60.0
		_t += dt * Engine.time_scale
		_min_scale = minf(_min_scale, Engine.time_scale)
		if Engine.time_scale < 0.99:
			_slow_frames += 1
		_max_over = maxf(_max_over, float(g.player.overheal))
		# twice a run he is brought near the line, so the next hit sets Last Stand off (its cooldown allowing)
		var mark := 1 if _t >= 20.0 else 0
		mark += 1 if _t >= 45.0 else 0
		if mark > _marks and not g.player.dead:
			_marks = mark
			g.player.overheal = 0.0
			g.player.hp = g.player.max_hp * 0.31
		spawn_t -= dt
		if spawn_t <= 0.0:
			spawn_t = 1.0
			var here: Vector3 = g.player.global_position
			var n: int = g.enemies.indices_in_radius(here, 8.0).size()
			for k in range(maxi(0, 18 - n)):
				var a := randf() * TAU
				g.enemies.spawn("goblin" if k % 2 else "skeleton", here + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 4.0), null, 1.0, 40.0)
		gem_t -= dt
		if gem_t <= 0.0:
			gem_t = 0.5
			var here2: Vector3 = g.player.global_position
			for k in range(4):
				var a2 := randf() * TAU
				g.pickups.spawn(g.pickups.KIND_GEM_S, here2 + Vector3(cos(a2), 0, sin(a2)) * randf_range(2.0, 9.0), 1.0)
		# a bad card screen or a modal would hold the run: close any by picking nothing (the arena levels by the button)
		if g.paused and g.cards and g.cards.visible:
			g.set_paused(false)
			g.cards.visible = false
	# the last Last Stand runs out (two real seconds at most), then the clock must be 1x
	for k in range(200):
		await process_frame
	print("p69_probe: %.0f s  Last Stand x%d (slowed frames %d, lowest clock %.2f, clock now %.2f, active %s)" % [
		_t, _stands, _slow_frames, _min_scale, Engine.time_scale, _run.last_stand_active])
	print("p69_probe: heal pulses %d (%.0f damage in all)  evades %d (armed Counterpunch %d)  most overheal %.1f of %.1f" % [
		_pulses, _pulse_dmg, _evades, _arms, _max_over, g.player.overheal_cap()])
	print("p69_probe: Magnet pulls %d (last took %d)  deaths %d  damage by source %s" % [g.pickups.xp_pulls, g.pickups.xp_pull_last, _deaths,
		JSON.stringify(_run.damage_by_weapon)])
	if absf(Engine.time_scale - 1.0) > 0.001 or _run.last_stand_active:
		_bad.append("the clock was not given back")
	if g.pickups.xp_pulls < 5:
		_bad.append("too few Magnet pulls")
	if _pulses < 5:
		_bad.append("too few heal pulses")
	if _evades > 0 and _arms == 0:
		_bad.append("evades never armed Counterpunch")
	print("p69_probe: ", "OK" if _bad.is_empty() else "FAILED " + str(_bad))
	Engine.time_scale = 1.0
	_save.data = keep
	quit(0 if _bad.is_empty() else 2)
