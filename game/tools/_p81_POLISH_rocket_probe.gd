## Pass 81 (lane POLISH) probe: in the real game (debug arena, Red Canyon's knobs), a Vulture Raider's rocket's ground
## speed against the hero's top speed. Headless, bounded.
##   godot --headless --fixed-fps 60 --path game --script res://tools/_p81_POLISH_rocket_probe.gd
extends SceneTree

const WATCHDOG_S := 120.0
var _t0 := 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p81_rocket: WATCHDOG")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var run = root.get_node("Run")
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	var g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p81_rocket: no game")
		quit(1)
		return
	g.player.god = true
	g.set_paused(false)
	run.debug_clear_items()
	run.rebuild_sheets()
	run.build_changed.emit()
	await _wait(0.3)
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	var i: int = em.spawn("rocketeer", here + Vector3(0, 0, -20))
	print("p81_rocket: pace %.3f (move_pace %.2f x creature_speed_mult %.2f), time_scale %.2f" % [em.pace, run.move_pace(), em.creature_speed_mult, em.time_scale])
	var k := -1
	for n in range(60 * 12):
		await physics_frame
		for pi in pm.rocket_of.keys():
			if int(pm.rocket_of[pi]) == i and pm.alive[int(pi)] == 1:
				k = int(pi)
		if k >= 0:
			break
	if k < 0:
		print("p81_rocket: no rocket")
		quit(1)
		return
	for n in range(30):
		await physics_frame
	var p0: Vector3 = pm.pos[k]
	var t0 := Time.get_ticks_msec()
	var ticks := 60
	for n in range(ticks):
		await physics_frame
	var p1: Vector3 = pm.pos[k]
	var flown := p0.distance_to(p1)
	var per_s := flown / (float(ticks) / 60.0)
	var top: float = g.player.max_speed()
	print("p81_rocket: hero top %.3f m/s, rocket %.3f m/s over 1 s (%.1f%%), rocket_ground_speed %.3f, speed_of_hero %.2f" % [top, per_s, 100.0 * per_s / top, pm.rocket_ground_speed(k), float(em.types[em.type_idx[i]]["def"].artillery["missile"]["speed_of_hero"])])
	save.data = keep
	quit(0)
