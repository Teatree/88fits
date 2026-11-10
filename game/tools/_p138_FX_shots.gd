## Pass 138 (lane FX): the barrel's white hit flash (a struck barrel at flash 1, 0.5 and 0 with its knock held; a breaking
## round's white pieces) and the Sun Scepter's new mark (the warning ring at pass 136's alpha and at this pass's, then the
## flame patch 0.1, 0.4, 0.8 and 1.2 s after a pillar lands) on Sundown and Nightfall, in the arena under the aim. Run with
## --fixed-fps 60 so frames count time. Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p138_FX_shots.gd -- out=<dir> [zoom=0.6]
##       [only=barrel,sun]
## Every wait is bounded (a watchdog quits after WATCHDOG seconds). The save and the settings in memory go back as they were.
extends SceneTree

const WATCHDOG := 180.0
var _out := "user://p138_fx"
var _zoom := 0.6
var _only: PackedStringArray = []
var _run
var _save
var _settings
var _keep: Dictionary = {}
var _aim := true
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _restore() -> void:
	if _save:
		_save.data = _keep
	if _settings:
		_settings.aim_mode = _aim


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p138_fx: watchdog, quitting")
		_restore()
		quit(3)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p138_fx: ", name)


func _go(p: Vector3) -> void:
	p.y = g.map.height_at(p.x, p.z)
	g.player.global_position = p
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_keep = _save.data.duplicate(true)
	_aim = bool(_settings.aim_mode)
	_settings.aim_mode = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _frames(150)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p138_fx: no game scene")
		_restore()
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	await _frames(60)
	if _only.is_empty() or _only.has("barrel"):
		await _shot_barrel()
	if _only.is_empty() or _only.has("sun"):
		await _shot_sun(0, "sundown")
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(1, 0.0)
		await _frames(20)
		await _shot_sun(1, "nightfall")
	print("p138_fx: done -> ", _out)
	_restore()
	quit(0)


## A coins barrel (three rounds): the first round's flash held at 1, 0.5 and 0 with its knock; the last round's white pieces.
func _shot_barrel() -> void:
	_run.debug_clear_items()
	_run.rebuild_sheets()
	g.enemies.kill_all(false)
	var bf = g.barrels
	var best := -1
	var best_d := INF
	var here: Vector3 = g.player.global_position
	for i in bf.pos.size():
		if bf.alive[i] != 0 and bf.light[i] == 1:
			var d := Vector2(bf.pos[i].x - here.x, bf.pos[i].z - here.z).length()
			if d < best_d:
				best_d = d
				best = i
	if best < 0:
		print("p138_fx: no coins barrel")
		return
	_go(bf.pos[best] + Vector3(-1.6, 0, 3.2))
	await _frames(40)
	_shot("barrel_0_rest")
	var dir := Vector3(1.0, 0.0, -1.0).normalized()
	bf.set_process(false)
	bf.shot_hit(best, dir, bf.pos[best] - dir * 2.0)
	for st: Array in [[1.0, 0.03, "barrel_1_flash100"], [0.5, 0.09, "barrel_2_flash050"], [0.0, 0.2, "barrel_3_flash000"]]:
		for k in range(3):
			if bf._anims.has(best):
				bf._anims[best]["t"] = float(st[1])
			bf._process(0.0)
			bf._flash[best] = float(st[0])
			bf._set_flash(best, float(st[0]))
			await process_frame
		_shot(str(st[2]))
	bf._flash.erase(best)
	bf._set_flash(best, 0.0)
	bf.set_process(true)
	await _frames(40)
	# the second round knocks, the third breaks: its pieces start white
	bf.shot_hit(best, dir, bf.pos[best] - dir * 2.0)
	await _frames(40)
	bf.shot_hit(best, dir, bf.pos[best] - dir * 2.0)
	await process_frame
	_shot("barrel_4_break_f1")
	await _frames(4)
	_shot("barrel_5_break_f5")
	await _frames(12)
	_shot("barrel_6_break_f17")


## Sun strikes on one still creature up and to the right of the Outlaw (so the spot is the same every time): the warning
## ring at pass 136's alpha and at this pass's, then the patch at 0.1, 0.4, 0.8, 1.2 s after the landing.
func _shot_sun(stage: int, tag: String) -> void:
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "sun_scepter", 1)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _frames(30)
	var b = g._behaviors.get("sun_scepter")
	if b == null:
		print("p138_fx: no sun scepter")
		return
	b.cooldown_left = 99.0
	g.enemies.kill_all(false)
	g.projectiles.clear_all()
	_go(Vector3(2.0 + 4.0 * stage, 0.0, 6.0))
	await _frames(40)
	# one tough creature standing still up and to the right of her, so every pillar comes down on the same spot in view
	var em = g.enemies
	var c: int = em.spawn("skeleton", g.player.global_position + Vector3(2.0, 0.0, -3.0), null, 1.0, 4000.0)
	if c >= 0:
		em.speed[c] = 0.0
	em._rebuild_grid()
	await _frames(70)
	var sun: Dictionary = b.inst.def.params["sun"]
	var now := float(sun.get("ring_alpha", 0.26))
	for pair: Array in [[0.35, "a_warn_p136"], [now, "b_warn_p138"]]:
		sun["ring_alpha"] = float(pair[0])
		b.cooldown_left = 99.0
		await _frames(90)
		b.cooldown_left = 1.0 / 60.0
		var s0: int = int(b.strikes)
		for k in range(30):
			await process_frame
			if int(b.strikes) > s0:
				break
		await _frames(14)
		print("p138_fx: sun strikes ", b.strikes, " (was ", s0, ") dry ", b.dry_strikes, " aim ", _settings.aim_mode)
		_shot("sun_%s_%s" % [tag, str(pair[1])])
	sun["ring_alpha"] = now
	b.cooldown_left = 99.0
	await _frames(100)
	b.cooldown_left = 1.0 / 60.0
	var i0: int = int(b.impacts)
	var s1: int = int(b.strikes)
	for k in range(90):
		await process_frame
		if int(b.strikes) > s1:
			# no next strike while the patch is watched
			b.cooldown_left = 99.0
		if int(b.impacts) > i0:
			break
	print("p138_fx: sun impacts ", b.impacts, " (was ", i0, ")")
	var at := 0
	for want: int in [6, 24, 48, 72]:
		await _frames(want - at)
		at = want
		_shot("sun_%s_c_patch_%03d" % [tag, int(want * 1000 / 60)])
	b.cooldown_left = 99.0
	g.enemies.kill_all(false)
