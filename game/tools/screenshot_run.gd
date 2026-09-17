## Windowed (not headless) capture tool: opens the game at phone aspect, plays for a few seconds with a
## simulated thumb, and saves screenshots of the run, the card screen, the pause screen and the title.
## godot --path game --script res://tools/screenshot_run.gd -- out=D:/path/dir
extends SceneTree

var _out := "user://shots"
var _t := 0.0
var _game: Node
var _step := 0
var _run: Node
var _map := "dry_gulch"
var _weapon := "boomstick"
var _character := "astro"
var _fire_target := -1
var _fire_next := 0.0
var _fire_n := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.trim_prefix("out=")
		elif a.begins_with("weapon="):
			_weapon = a.trim_prefix("weapon=")
		elif a.begins_with("map="):
			_map = a.trim_prefix("map=")
		elif a.begins_with("character="):
			_character = a.trim_prefix("character=")
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": _weapon, "level": 4, "character": _character, "map": _map}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _shot(name: String) -> void:
	print("screenshot_run: capturing ", name)
	var img := root.get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("screenshot_run: saved ", path)


func _tick() -> void:
	_t += root.get_process_delta_time()
	if _game == null and _step < 7:
		_game = current_scene
		if _game == null or not _game.has_method("open_pause"):
			_game = null
			return
		_game.player.god = true
	if (_step < 7 or _step == 15 or _step == 16) and _game and is_instance_valid(_game) and _game.player and not _game.paused:
		var inp = _game.player.input
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		# up-screen during the crowd shot, screen-right for the props shot (side view), down-screen for the mesa shot (front view)
		var push := Vector2(sin(_t * 0.6) * 90.0, -110.0)
		if _step == 15:
			push = Vector2(110.0, 0.0)
		elif _step == 16:
			push = Vector2(0.0, 110.0)
		inp.touch_pos = inp.origin + push
	# the joystick hero hoovers gems fast: pick cards automatically during the play captures (step 2 is the card shot)
	if _game and is_instance_valid(_game) and _step != 2 and _step < 7 and _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _step == 0 and _t > 1.5 and _game and is_instance_valid(_game) and _game.pickups and _game.pickups.specials.is_empty():
		# a pickup on the ground for the capture (they normally appear after 50 s)
		var reg = root.get_node("Registry")
		var heart = reg.pickup("heart")
		if heart and _game.player:
			_game.pickups.spawn_special(heart, _game.player.global_position + Vector3(2.5, 0, -2.0))
	if _step == 0 and _t > 3.0:
		_game.enemies.spawn_pack("goblin", _game.player.global_position + _game.player.forward() * 8.0, 30)
		_game.enemies.spawn_pack("fire_ant", _game.player.global_position + _game.player.forward() * 5.0, 40)
		_run.add_weapon(root.get_node("Registry").weapon("orbit_saws"), 3)
		_step = 1
	elif _step == 1 and _t > 5.0 and not (_game.cards and _game.cards.visible):
		_shot("01_play")
		# look at the gas station and water tower from the south-west
		_game.player.global_position = Vector3(30, 1, -42)
		_game.player.facing = atan2(-(40 - 30), -(-56 + 42))
		_game.camera.snap_to(_game.player)
		# a ring, a filled disc and a line on the dune slope: the markings must drape over the ground, not cut it
		_game.telegraphs.ring(_game.player.global_position + Vector3(3, 0, 2), 3.5, 3.0, Color(1.0, 0.35, 0.3), true)
		_game.telegraphs.line(_game.player.global_position + Vector3(-4, 0, 3), Vector3(0.3, 0, -1), 9.0, 3.0, Color(1.0, 0.6, 0.2))
		_step = 15
	elif _step == 15 and _t > 5.6:
		_shot("01b_props")
		_game.player.global_position = Vector3(-40, 1, 14)
		_game.player.facing = atan2(-(-46 + 40), -(-4 - 14))
		_game.camera.snap_to(_game.player)
		_step = 16
	elif _step == 16 and _t > 6.2:
		_shot("01c_mesa")
		# stand inside the first structure's ring so the progress pie is half full for the capture
		if _game.structures and not _game.structures.items.is_empty():
			var st = _game.structures.items[0]
			_game.player.global_position = st.global_position + Vector3(1.2, 0.5, 1.0)
			_game.camera.snap_to(_game.player)
		# let go of the stick, or the hero runs out of the ring before the shot
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_game.player.velocity = Vector3.ZERO
		_step = 17
	elif _step == 17 and _t > 7.9:
		_shot("11_structure")
		var reg = root.get_node("Registry")
		if reg.structures.has("shop"):
			_game.use_structure(reg.structure("shop"), _game.player.global_position)
		_step = 18
	elif _step == 18 and _t > 8.5:
		_shot("12_shop")
		if _game.structure_shop and _game.structure_shop.visible:
			_game.structure_shop._finish(false)
		_game.player.global_position = Vector3(0, 1, 8)
		_game.player.facing = 0.0
		_game.camera.snap_to(_game.player)
		_run.add_xp(_run.xp_to_next() + 1.0)
		_step = 2
	elif _step == 2 and _t > 9.2:
		_shot("02_cards")
		if _game.cards.visible and not _game.cards._offer.is_empty():
			_game.cards._pick(_game.cards._offer[0])
		# a chest under the hero: the reel spins for four seconds, the shot is taken once it has landed
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_game.pickups.spawn_chest(_game.player.global_position + Vector3(0.3, 0, 0))
		_step = 20
	elif _step == 20 and _t > 14.6:
		_shot("13_chest")
		if _game.chest_screen and _game.chest_screen.visible:
			_game.chest_screen._finish(true)
		_step = 21
	elif _step == 21 and _t > 15.2:
		# the mini-boss next to the hero, and three spitters whose shots leave their trails
		var reg = root.get_node("Registry")
		var elite_id: String = str(_run.map.skins.get("elite", ""))
		if reg.enemies.has(elite_id):
			var ei: int = _game.enemies.spawn(elite_id, _game.player.global_position + Vector3(5.0, 0, -14.0))
			_game.director.elite_index = ei
		_game.enemies.spawn_pack("spit_cactus", _game.player.global_position + Vector3(-6.0, 0, -7.0), 3)
		_step = 22
	elif _step == 22 and _t > 18.0:
		_shot("14_elite")
		# fire: a tight goblin pack, one lit with a certain spread, weapons off, frames every tenth of a second for a gif
		_game.player.global_position = Vector3(6, 1, 8)
		_game.camera.snap_to(_game.player)
		_game.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
		_game.projectiles.clear_all()
		_game.enemies.kill_all(false)
		var first := -1
		for gx in range(3):
			for gz in range(3):
				var i: int = _game.enemies.spawn("goblin", Vector3(5.0 + gx * 1.0, 0, 2.0 + gz * 0.9))
				if i >= 0:
					_game.enemies.speed[i] = 0.0
					_game.enemies.state[i] = 0
					if first < 0:
						first = i
		_fire_target = first
		_step = 24
	elif _step == 24 and _t > 18.9:
		_game.enemies.ignite(_fire_target, "flare_gun", 4.0, 3.0, 1.0)
		_fire_next = _t
		_fire_n = 0
		_step = 25
	elif _step == 25:
		if _t >= _fire_next and _fire_n < 28:
			_shot("fire_seq_%02d" % _fire_n)
			_fire_n += 1
			_fire_next += 0.1
		elif _fire_n >= 28:
			_game.enemies.kill_all(false)
			# behind a big saguaro: the hero a step north of it (further from the camera) with a goblin pack, for the outline pass
			var props = _game.map.get("props")
			var best := Vector3.INF
			if props:
				for pr in props.placed:
					if str(pr["id"]) == "saguaro_big" and (best == Vector3.INF or (pr["pos"] as Vector3).length() < best.length()):
						best = pr["pos"]
			if best != Vector3.INF:
				_game.player.global_position = best + Vector3(0.4, 0.5, -1.6)
				_game.camera.snap_to(_game.player)
				_game.enemies.spawn_pack("goblin", best + Vector3(-1.5, 0, -2.5), 6)
				for i in range(_game.enemies.MAX):
					if _game.enemies.alive[i] == 1:
						_game.enemies.speed[i] = 0.0
			_step = 26
	elif _step == 26 and _t > 22.4:
		_shot("16_outline")
		_game.weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
		_game.enemies.kill_all(false)
		_step = 3
	elif _step == 3 and _t > 23.8:
		_game.open_pause()
		_step = 4
	elif _step == 4 and _t > 24.4:
		_shot("03_pause_build")
		_game.pause_screen._tab = 1
		_game.pause_screen._refresh()
		_step = 5
	elif _step == 5 and _t > 24.9:
		_shot("04_pause_stats")
		_game.close_pause()
		_game.director._start_boss(_game.director.map.boss if _game.director.map and _game.director.map.boss != "" else "tumbleweed_king")
		# far from the boss first: the HUD's edge pointer shows where it is
		_game.player.global_position = Vector3(6, 1, 46)
		_game.camera.snap_to(_game.player)
		_step = 23
	elif _step == 23 and _t > 26.1:
		_shot("15_boss_arrow")
		_game.player.global_position = Vector3(0, 1, 2)
		_game.camera.snap_to(_game.player)
		_step = 6
	elif _step == 6 and _t > 27.9:
		_shot("05_boss")
		# the dust devil: stand next to it with a goblin pack inside so the lift shows
		var dd: Node3D = null
		for c in _game.map.get_children():
			if c is Node3D and "loop_center" in c:
				dd = c
		if dd:
			dd.speed = 0.0
			_game.player.global_position = dd.global_position + Vector3(0, 1, 7)
			_game.camera.snap_to(_game.player)
			_game.enemies.spawn_pack("goblin", dd.global_position, 10)
		_step = 60
	elif _step == 60 and _t > 29.0:
		_shot("05b_tornado")
		_game = null
		print("screenshot_run: changing to title")
		var err := change_scene_to_file("res://ui/TitleScreen.tscn")
		print("screenshot_run: change_scene returned ", err)
		_step = 7
	elif _step == 7 and _t > 30.0:
		_shot("06_title")
		change_scene_to_file("res://ui/ShopScreen.tscn")
		_step = 8
	elif _step == 8 and _t > 30.8:
		_shot("07_shop")
		change_scene_to_file("res://ui/CollectionScreen.tscn")
		_step = 9
	elif _step == 9 and _t > 31.6:
		_shot("08_collection")
		change_scene_to_file("res://ui/PlaySetup.tscn")
		_step = 10
	elif _step == 10 and _t > 32.4:
		_shot("09_play_setup")
		change_scene_to_file("res://ui/SettingsScreen.tscn")
		_step = 11
	elif _step == 11 and _t > 33.2:
		_shot("10_settings")
		quit(0)
