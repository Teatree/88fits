## Pass 119 lane LEGEND_B capture: the Dragon's Breath's mouthful splash, the Undertaker's Shovel's graves and ghosts
## through their phases, Lightning in a Bottle's arcs, the Pocket Bible's HUD plate and block. Windowed, bounded
## (WATCHDOG_S), the save in the sandbox.
## Run: GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p119_LEGEND_B_shots.gd -- out=<dir> [only=breath|graves|arcs|bible]
extends SceneTree

const WATCHDOG_S := 240.0
## Graveyard's phases (its enum, by value)
const CLIMB := 2
const FIGHT := 3
const VANISH := 4
const STONE_DOWN := 5
var _out := "user://p119_legend_b"
var _only := ""
var _save
var _run
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p119_legend_b: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p119_legend_b: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	if _only == "" or _only == "breath":
		await _breath()
	if _only == "" or _only == "graves":
		await _graves()
	if _only == "" or _only == "arcs":
		await _arcs()
	if _only == "" or _only == "bible":
		await _bible()
	quit(0)


## A run of the Drifter with `weapon` and no spawning; the Game scene once it stands.
func _launch(weapon: String) -> Node:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "weapon": weapon, "level": 3, "map": "red_canyon",
		"map_seed": 7, "spawn": false, "analytics": false, "stage": 1}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	var g = current_scene
	if g != null and g.get("player") != null:
		g.player.god = true
	return g


## Skeletons at `spots` round the hero (offsets), up out of the sand.
func _crowd(g: Node, spots: Array, hp_mult: float = 30.0) -> Array:
	var out: Array = []
	var at0: Vector3 = g.player.global_position
	for o: Vector3 in spots:
		var p: Vector3 = at0 + o
		p.y = g.map.height_at(p.x, p.z) if g.map else 0.0
		var i: int = g.enemies.spawn("skeleton", p, null, 1.0, hp_mult)
		if i >= 0:
			out.append(i)
	return out


func _breath() -> void:
	var g = await _launch("dragons_breath")
	if g == null:
		return
	var fb: Node = null
	for n in g.find_children("*", "FireBreath", true, false):
		fb = n
	if fb == null:
		print("p119_legend_b: no FireBreath")
		return
	# no creature near at first, so the breath that is ready at the start is not spent before the capture
	g.player.global_position += Vector3(0, 0, 0)
	await _wait(0.5)
	print("p119_legend_b: breath state before: mouthfuls %d breaths %d burning %s cooldown %.2f" % [fb.mouthfuls, fb.breaths, fb.burning(), fb.cooldown_left])
	await _crowd(g, [Vector3(0, 0, -3.5), Vector3(1.4, 0, -4.2), Vector3(-1.4, 0, -4.0)])
	# the breath that was ready breathes on them; its flames burn out before the next cooldown is cut short
	var g0 := 0
	while g0 < 600 and int(fb.breaths) == 0:
		await process_frame
		g0 += 1
	while g0 < 900 and fb.burning():
		await process_frame
		g0 += 1
	await _wait(1.6)
	fb.cooldown_left = 0.8
	var m0: int = int(fb.mouthfuls)
	var guard := 0
	while guard < 400 and int(fb.mouthfuls) == m0:
		await process_frame
		guard += 1
	print("p119_legend_b: mouthful after %d frames: mouthfuls %d breaths %d burning %s" % [guard, fb.mouthfuls, fb.breaths, fb.burning()])
	for k in range(8):
		await _shot("breath_%d" % k)
		await _wait(0.06)
	print("p119_legend_b: breath after: mouthfuls %d breaths %d burning %s" % [fb.mouthfuls, fb.breaths, fb.burning()])


func _graves() -> void:
	var g = await _launch("revolver")
	if g == null:
		return
	_run.add_or_level_passive("undertakers_shovel")
	await _crowd(g, [Vector3(-6, 0, -7), Vector3(-4, 0, -8), Vector3(5, 0, -7), Vector3(7, 0, -5), Vector3(0, 0, -9),
		Vector3(-8, 0, -2), Vector3(8, 0, -1)], 60.0)
	await _wait(0.6)
	# by name only through the scene (a tool compiles before the autoloads: naming Graveyard here would break it)
	var gy = g._graveyard()
	var here: Vector3 = g.player.global_position
	for o: Vector3 in [Vector3(-2.2, 0, -1.2), Vector3(2.0, 0, -1.6), Vector3(0.2, 0, 1.6)]:
		gy.dig(here + o)
	await _wait(0.12)
	await _shot("graves_a_rising")
	await _wait(0.6)
	await _shot("graves_b_standing")
	# the ghosts climb out 2 s after the dig
	await _wait_phase(gy, CLIMB)
	await _wait(0.3)
	await _shot("graves_c_climbing")
	await _wait_phase(gy, FIGHT)
	await _wait(0.9)
	await _shot("graves_d_fighting")
	await _wait(1.3)
	await _shot("graves_e_fighting")
	await _wait_phase(gy, VANISH)
	await _wait(0.3)
	await _shot("graves_f_vanishing")
	await _wait_phase(gy, STONE_DOWN)
	await _wait(0.3)
	await _shot("graves_g_sinking")
	print("p119_legend_b: graves dug %d raised %d shots %d" % [gy.dug, gy.raised, gy.shots])


func _wait_phase(gy, phase: int) -> void:
	var guard := 0
	while guard < 1500 and not gy.graves.is_empty() and int((gy.graves[0] as Dictionary)["phase"]) < phase:
		await process_frame
		guard += 1


func _arcs() -> void:
	var g = await _launch("revolver")
	if g == null:
		return
	_run.add_or_level_passive("lightning_in_a_bottle")
	# every hit a crit (added after the item: a rebuild of the sheets would drop it)
	_run.player_sheet.add_effects([Effect.make("crit_chance", "add", 1.0, "player")], "capture crits")
	var em = g.enemies
	em.refresh_player_stats()
	# a loose clump 6-8 m ahead (the hero faces north, -Z), the arcs' 5 m reach across it
	var spots: Array = []
	for k in range(10):
		var a := TAU * float(k) / 10.0
		spots.append(Vector3(cos(a) * (1.2 + 0.9 * float(k % 3)), 0, -7.0 + sin(a) * (1.2 + 0.9 * float(k % 3))))
	await _crowd(g, spots, 120.0)
	await _wait(0.9)
	for k in range(3):
		var n0: int = int(em.arcs_thrown)
		var guard := 0
		while guard < 600 and int(em.arcs_thrown) == n0:
			await process_frame
			guard += 1
		await _shot("arcs_%d" % k)
		await _wait(0.25)
	print("p119_legend_b: arcs %d from %d crits" % [em.arcs_thrown, em.arc_crits])


func _bible() -> void:
	var g = await _launch("revolver")
	if g == null:
		return
	_run.add_or_level_passive("pocket_bible")
	await _wait(0.5)
	await _shot("bible_a_ready")
	g.player.god = false
	g.player.invuln = 0.0
	g.player.take_damage(60.0, g.player.global_position + Vector3(1, 0, 0), {"by": "capture", "kind": "melee"})
	await _wait(0.05)
	await _shot("bible_b_blocked")
	await _wait(0.6)
	await _shot("bible_c_spent")
	g.player.god = true
