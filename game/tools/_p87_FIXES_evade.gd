## Pass 87, lane FIXES, scratch capture in the debug arena: an evaded hit (EVADE flying out of the hero, the hero
## see-through for a second), frame by frame, with a creature standing behind him so the see-through shows; then an
## evade followed by a trampoline jump, and an evade with the hit blink (Ghost Step's invuln). Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p87_FIXES_evade.gd -- out=<dir>
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds).
extends SceneTree

const WATCHDOG := 90.0
var _out := "user://p87_evade"
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p87_evade: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var cam: Camera3D = g.camera.camera
	var hp: Vector2 = cam.unproject_position(g.player.global_position + Vector3(0, 1.1, 0))
	var r := Rect2i(int(hp.x) - 260, int(hp.y) - 330, 520, 560).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_out.path_join(name + ".png"))
	print("p87_evade: ", name, " ghost_t %.2f fade %.2f visible %s airborne %s" % [g.player.evade_ghost_t, g.player.sprite.fade(), str(g.player.sprite.visible), str(g.player.airborne)])


## Hits him until one is evaded (the sheet's evade is 0.9 here), at most 40 tries.
func _evade_once() -> bool:
	for k in range(40):
		g.player.invuln = 0.0
		g.player.take_damage(5.0, g.player.global_position + Vector3(1, 0, 0), {"by": "Probe", "kind": "melee"})
		if str(g.player.last_outcome) == "evaded":
			return true
	return false


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var settings = root.get_node("Settings")
	settings.damage_numbers = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = 0.55
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(1.0)
	var em = g.enemies
	em.kill_all(false)
	await _wait(1.0)
	var here: Vector3 = g.player.global_position
	# a bandit standing just behind him (up the screen), so the see-through shows the creature through him
	var i: int = em.spawn("spit_cactus", here + Vector3(0.15, 0, -1.2), null, 1.0, 200.0, "SC-A")
	if i >= 0:
		em.cooldown[i] = 999.0
		em.speed[i] = 0.0
		em.contact_cd[i] = 999.0
	var sheet = _run.player_sheet
	sheet.add_effects([Effect.make("evade", "add", 1.0, "player")], "p87_probe")
	await _wait(1.2)
	await _shot("a0_before")
	g.player.god = false
	var ok := _evade_once()
	print("p87_evade: evaded ", ok, " outcome ", g.player.last_outcome, " evade ", g.player.sheet.get_stat("evade", 0.0), " shield_t ", g.player.shield_t)
	await _shot("a1_evade_0s")
	await _wait(0.15)
	await _shot("a2_evade_0.15s")
	await _wait(0.25)
	await _shot("a3_evade_0.4s")
	await _wait(0.35)
	await _shot("a4_evade_0.75s")
	await _wait(0.15)
	await _shot("a5_evade_0.9s")
	await _wait(0.3)
	await _shot("a6_evade_1.2s")
	# two evades in a row: never fainter than the first
	_evade_once()
	await _wait(0.3)
	_evade_once()
	await _shot("b0_twice")
	await _wait(1.3)
	# an evade, then the trampoline
	_evade_once()
	g.player.trampoline_launch(Vector3(1, 0, 0), 3.0, 3.0, 1.1, 0.35)
	await _wait(0.3)
	await _shot("c0_evade_then_jump")
	await _wait(1.5)
	# the blink after a hit with Ghost Step's invuln on an evade
	sheet.add_effects([Effect.make("evade_invuln", "add", 0.6, "player")], "p87_probe2")
	_evade_once()
	await _wait(0.1)
	for k in range(6):
		await _shot("d%d_ghost_step_blink" % k)
		await process_frame
	sheet.remove_source("p87_probe")
	sheet.remove_source("p87_probe2")
	_save.data = _keep
	quit(0)
