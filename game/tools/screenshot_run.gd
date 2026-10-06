## Windowed (not headless) capture tool: opens the game at phone aspect, plays for a few seconds with a
## simulated thumb, and saves screenshots of the run, the card screen, the pause screen and the title.
## godot --path game --script res://tools/screenshot_run.gd -- out=D:/path/dir
extends SceneTree

var _out := "user://shots"
var _t := 0.0
var _game: Node
var _step := 0
var _after_chest := 0.0   # when the tap-to-continue gate may be shot (the chest closes a beat after its reel lands)
var _run: Node
var _map := "red_canyon"
var _weapon := "boomstick"
var _character := "astro"
var _momentum_shot := false
var _rocket_shot := false
var _blade_shot := false
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
	f.store_string(JSON.stringify({"weapon": _weapon, "level": 4, "character": _character, "map": _map, "map_seed": 88}))
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
		if _game and "no_random_chests" in _game:
			_game.no_random_chests = true
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
	if _game and is_instance_valid(_game) and _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible and _step != 27:
		_game.resume_gate.tap()
	# the joystick hero hoovers gems fast: pick cards automatically during the play captures (step 2 is the card shot)
	if _game and is_instance_valid(_game) and _step != 2 and _step < 7 and _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _step == 0 and _t > 1.5 and _game and is_instance_valid(_game) and _game.pickups and _game.pickups.specials.is_empty():
		# a pickup on the ground for the capture (they normally appear after 50 s)
		var reg = root.get_node("Registry")
		var heart = reg.pickup("heart")
		if heart and _game.player:
			_game.pickups.spawn_special(heart, _game.player.global_position + Vector3(2.5, 0, -2.0))
	if _step == 0 and _t > 1.7 and _weapon == "rocket_pod" and not _rocket_shot and not (_game.cards and _game.cards.visible):
		# a volley over open sand before the crowd arrives: the missiles are locking on with their smoke behind them
		_rocket_shot = true
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(2.0, 0, -11.5), 6)
		_step = 221
	elif _step == 221 and _t > 1.9:
		# a physics step later the pack is in the grid, so the pod has something to aim at
		if _game._behaviors.has("rocket_pod"):
			_game._behaviors["rocket_pod"]._fire()
		_step = 222
	elif _step == 222 and _t > 2.5:
		_shot("22_rockets")
		# the pod close up (pass 28): the camera pulled in once the volley's smoke has cleared, mid-reload, so the
		# empty tubes, the tips popping back and the turned cluster show; the tips' state is printed for the record
		_game.camera.fixed_distance = 10.0
		_game.camera.snap_to(_game.player)
		# the missiles and their smoke go, the pack too, and the pod holds its next volley, so the reload is what shows
		_game.projectiles.clear_all()
		_game.enemies.kill_all(false)
		if _game._behaviors.has("rocket_pod"):
			_game._behaviors["rocket_pod"].cooldown_left = 99.0
			# the pod to the hero's right, not behind his head
			_game._behaviors["rocket_pod"]._orbit = 0.0
		_step = 2221
	elif _step == 2221 and _t > 3.1:
		if _game._behaviors.has("rocket_pod"):
			var pod = _game._behaviors["rocket_pod"]
			var vis: Array = []
			for tip in pod._tips:
				vis.append(tip.visible)
			print("screenshot_run: pod tips ", vis, " spin ", pod._spin_target, " empty ", pod._empty.size())
		_shot("22b_pod")
		if _game._behaviors.has("rocket_pod"):
			_game._behaviors["rocket_pod"].cooldown_left = 0.5
		_game.camera.fixed_distance = 22.5
		_game.camera.snap_to(_game.player)
		_step = 223
	elif _step == 223 and _t > 4.1:
		# the Zap Beam (pass 27): a chain over a tight pack, the ribbon caught a frame after the strike
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		_run.add_weapon(root.get_node("Registry").weapon("zap_beam"), 3)
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(3.0, 0, -3.0), 5)
		_step = 224
	elif _step == 224 and _t > 4.3:
		if _game._behaviors.has("zap_beam"):
			_game._behaviors["zap_beam"].cooldown_left = 0.0
			_game._behaviors["zap_beam"]._fire()
		_step = 225
	elif _step == 225 and _t > 4.38:
		_shot("35_zap")
		_step = 0
	elif _step == 0 and _t > 1.7 and _weapon == "sabre" and not _blade_shot and not (_game.cards and _game.cards.visible):
		# a blade mid-thrust: a small pack right in reach, the stroke fired a physics step later so the pack is in the grid
		_blade_shot = true
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(0.8, 0, -2.4), 4)
		_step = 271
	elif _step == 271 and _t > 1.9:
		if _game._behaviors.has("sabre"):
			_game._behaviors["sabre"]._fire()
		_step = 272
	elif _step == 272 and _t > 2.05:
		_shot("27_blade")
		_step = 0
	elif _step == 0 and _t > 1.6 and _character == "buck" and not _momentum_shot and not (_game.cards and _game.cards.visible):
		# Buck at full momentum running north with a pack behind him, before the crowd arrives: the trail and the
		# companion gun firing back at them are both in the shot
		_momentum_shot = true
		_game.player._momentum_t = 12.0
		_game.player.input.wants_move = true
		_game.player.input.stick_dir = Vector2(0, -1)
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(1.0, 0, 7.0), 6)
		_step = 19
	elif _step == 19 and _t > 2.5:
		_shot("19_momentum")
		_step = 191
	elif _step == 191 and _t > 2.9:
		# the gun's aim: one skeleton frozen due east at six metres, the tracers show which end the rounds leave
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		_game.player.input.wants_move = false
		var gi: int = _game.enemies.spawn("goblin", _game.player.global_position + Vector3(5.0, 0, -1.0), null, 1.0, 40.0)
		if gi >= 0:
			_game.enemies.speed[gi] = 0.0
			_game.enemies.state[gi] = 0
		print("screenshot_run: tommy target ", gi, " alive ", _game.enemies.alive_count())
		_step = 1911
	elif _step == 1911 and _t > 4.5:
		# pull the trigger now, and take the frame 80 ms later: a level-1 burst is four rounds over 0.2 s, and by 0.22 s every
		# round had hit and the knockback had pushed the target off the screen
		if _game._behaviors.has("tommy_gun"):
			_game._behaviors["tommy_gun"].cooldown_left = 0.0
			var fired: bool = _game._behaviors["tommy_gun"]._fire()
			print("screenshot_run: tommy fired ", fired, " burst left ", _game._behaviors["tommy_gun"]._burst.size(), " alive ", _game.enemies.alive_count(), " hero ", _game.player.global_position)
		else:
			print("screenshot_run: no tommy behaviour; have ", _game._behaviors.keys())
		_step = 19111
	elif _step == 19111 and _t > 4.6:
		_shot("20_tommy")
		# the shield: the sphere over the hero
		_game.player.shield(6.0)
		_step = 1912
	elif _step == 1912 and _t > 5.0:
		_shot("33_shield")
		_step = 0
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_step = 0
	elif _step == 0 and _t > 3.0:
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
		# the north rim, the stone boundary wall a few metres ahead, and the mountains behind it
		var wz: float = -(_game.map.arena_radius - 7.0)
		_game.player.global_position = Vector3(0, _game.map.height_at(0, wz) + 0.5, wz)
		_game.player.facing = 0.0
		_game.camera.snap_to(_game.player)
		_step = 16
	elif _step == 16 and _t > 6.2:
		_shot("01c_mesa")
		# the oasis (pass 28): from its south shore, facing the water and the palms
		if _game.map.has_method("lake_center"):
			var lc: Vector2 = _game.map.call("lake_center")
			var lr: float = _game.map.call("lake_radius")
			var oz: float = lc.y + lr - 2.5
			_game.player.global_position = Vector3(lc.x + 2.5, _game.map.height_at(lc.x + 2.5, oz) + 0.5, oz)
			_game.player.facing = 0.0
			_game.camera.snap_to(_game.player)
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_step = 161
	elif _step == 161 and _t > 7.0:
		_shot("36_oasis")
		# stand inside the first structure's ring so the progress pie is half full for the capture
		if _game.structures and not _game.structures.items.is_empty():
			var st = _capture_structure()
			_game.player.global_position = st.global_position + Vector3(1.2, 0.5, 1.0)
			_game.camera.snap_to(_game.player)
		# let go of the stick, or the hero runs out of the ring before the shot
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_game.player.velocity = Vector3.ZERO
		_step = 17
	elif _step == 17 and _t > 8.7:
		_shot("11_structure")
		# the spent painting: fill the structure's wedge by hand and let it switch off
		if _game.structures and not _game.structures.items.is_empty():
			var st0 = _capture_structure()
			if not st0.used:
				st0.progress = 1.0
				_game.structures._use(st0)
		_step = 171
	elif _step == 171 and _t > 9.1:
		_shot("11b_structure_spent")
		# the Stranger on the sand, then his bargain
		var stranger = _find_structure("hooded_figure")
		if stranger:
			_game.player.global_position = stranger.global_position + Vector3(1.6, 0.5, 2.2)
			_game.camera.snap_to(_game.player)
		_step = 172
	elif _step == 172 and _t > 9.7:
		_shot("25_stranger")
		var regs = root.get_node("Registry")
		if regs.structures.has("hooded_figure"):
			_game.use_structure(regs.structure("hooded_figure"), _game.player.global_position)
		_step = 173
	elif _step == 173 and _t > 10.4:
		_shot("26_stranger_deal")
		if _game.stranger_screen and _game.stranger_screen.visible:
			_game.stranger_screen._finish(false)
		var reg = root.get_node("Registry")
		if reg.structures.has("shop"):
			_game.use_structure(reg.structure("shop"), _game.player.global_position)
		_step = 18
	elif _step == 18 and _t > 11.4:
		_shot("12_shop")
		if _game.structure_shop and _game.structure_shop.visible:
			_game.structure_shop._finish(false)
		_game.player.global_position = Vector3(0, 1, 8)
		_game.player.facing = 0.0
		_game.camera.snap_to(_game.player)
		# the drop chest itself, on the sand next to the hero, before the level-up
		_game.pickups.spawn_chest(_game.player.global_position + Vector3(2.4, 0, 1.2))
		_step = 181
	elif _step == 181 and _t > 11.9:
		_shot("24_chest")
		# no chest may open under the hero before the level-up cards (kills drop them now), or the reel steals the shot
		for c in _game.pickups.chests:
			if is_instance_valid(c):
				c.queue_free()
		_game.pickups.chests.clear()
		_run.add_xp(_run.xp_to_next() + 1.0)
		_step = 2
	elif _step == 2 and _t > 12.1:
		_shot("02_cards")
		if _game.cards.visible and not _game.cards._offer.is_empty():
			_game.cards._pick(_game.cards._offer[0])
		# a chest under the hero: the reel spins for four seconds, the shot is taken once it has landed
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_game.pickups.spawn_chest(_game.player.global_position + Vector3(0.3, 0, 0))
		_step = 20
	elif _step == 20 and _t > 17.1 and not (_game.chest_screen and _game.chest_screen.visible and _game.chest_screen._spinning):
		# pass 46: the chest opens before the reel spins, so the reel lands later than it did; wait for it to land
		_shot("13_chest")
		if _game.chest_screen and _game.chest_screen.visible:
			_game.chest_screen._finish(true)
		_after_chest = _t + 0.8
		_step = 27
	elif _step == 27 and _t > maxf(17.9, _after_chest):
		_shot("17_tap_to_continue")
		_game.resume_gate.tap()
		_step = 21
	elif _step == 21 and _t > 17.7:
		# a level-up from the kills so far would cover the shot: take the first card and tap through
		if _game.cards.visible and not _game.cards._offer.is_empty():
			_game.cards._pick(_game.cards._offer[0])
			_game.resume_gate.tap()
		# the mini-boss next to the hero, and three spitters whose shots leave their trails
		var reg = root.get_node("Registry")
		var elite_id: String = str(_run.map.skins.get("elite", ""))
		if reg.enemies.has(elite_id):
			var ei: int = _game.enemies.spawn(elite_id, _game.player.global_position + Vector3(5.0, 0, -14.0))
			_game.director.elite_index = ei
		_game.enemies.spawn_pack("spit_cactus", _game.player.global_position + Vector3(-6.0, 0, -7.0), 3)
		_step = 22
	elif _step == 22 and _t > 20.5:
		_shot("14_elite")
		# the other Elite: the Sun Prophet alone north of the hero, caught mid-attack a couple of seconds in; the hero's
		# weapons held, or a poison tick washes him green in the frame
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		_game.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
		if root.get_node("Registry").enemies.has("sun_prophet"):
			var di: int = _game.enemies.spawn("sun_prophet", _game.player.global_position + Vector3(1.5, 0, -8.0))
			_game.director.elite_index = di
		_step = 2210
	elif _step == 2210 and _t > 22.9:
		# the spikes: the volley is forced to start now, so the frame a beat later has the five spikes in the air
		# down the lines the fan drew (waiting for the creature's own clock caught the wind-up every time)
		var ei2: int = _game.director.elite_index
		if ei2 >= 0:
			_game.enemies.atk_i[ei2] = 0
			_game.enemies.atk_t[ei2] = 0.0
			_game.enemies.hold_t[ei2] = 0.0
			_game.enemies.state[ei2] = 0
		_step = 22102
	elif _step == 22102 and _t > 24.05:
		_shot("28_centipede")
		_step = 22101
	elif _step == 22101 and _t > 28.6:
		print("screenshot_run: centipede rains ", _game.enemies._rains.size(), " telegraphs ", _game.telegraphs.get_child_count(), " alive ", _game.enemies.alive_count(), " hold ", (_game.enemies.hold_t[_game.director.elite_index] if _game.director.elite_index >= 0 else -1.0), " state ", (_game.enemies.state[_game.director.elite_index] if _game.director.elite_index >= 0 else -1))
		_shot("28b_erupt")
		_game.weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
		# the mutations: a Hornet Nest at level 3 puts its three on the path table
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		# the real path table: a slot come due for the highest open path among the weapons held (Game.present_path_offer)
		_run.add_weapon(root.get_node("Registry").weapon("hornet_nest"), 3)
		_game.present_path_offer()
		_step = 2211
	elif _step == 2211 and _t > 29.5:
		_shot("29_mutation")
		if _game.cards.visible and not _game.cards._offer.is_empty():
			_game.cards._pick(_game.cards._offer[0])
		_step = 22111
	elif _step == 22111 and _t > 30.0:
		# the pick lands a beat later and opens the gate; tap it now, and make sure the clock runs again
		_game.resume_gate.tap()
		_game.set_paused(false)
		_step = 2212
	elif _step == 2212 and _t > 30.4:
		# the strip: a mutated weapon's dots and the padlocked slots
		_shot("31_paths_hud")
		# two dwarves close by, caught in their wind-up: the red wedges on the sand
		# tough enough to outlive the hero's weapons for the shot, and wound up on cue so the wedges are on the sand at 25.9
		for dp in [Vector3(-3.4, 0, -3.0), Vector3(3.6, 0, -2.2)]:
			var di2: int = _game.enemies.spawn("buckshot_dwarf", _game.player.global_position + dp, null, 1.0, 80.0)
			if di2 >= 0:
				_game.enemies.cooldown[di2] = 1.4
		_step = 2213
	elif _step == 2213 and _t > 32.4:
		_shot("30_dwarf")
		_game.enemies.kill_all(false)
		# the armadillo pack (pass 33.2): eight waddling in from the north-east, the weapons held so they arrive whole
		_game.projectiles.clear_all()
		_game.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
		_game.enemies.spawn_pack("armadillo", _game.player.global_position + Vector3(3.5, 0, -5.0), 8)
		_step = 2214
	elif _step == 2214 and _t > 33.4:
		_shot("37_armadillo")
		_game.enemies.kill_all(false)
		# the skeletons (shelved in pass 33.5, kept for the record): the plain one and the knight close up, weapons held
		_game.camera.fixed_distance = 11.0
		_game.camera.snap_to(_game.player)
		_game.enemies.spawn_pack("skeleton", _game.player.global_position + Vector3(2.6, 0, -4.2), 5)
		_game.enemies.spawn_pack("skeleton_knight", _game.player.global_position + Vector3(-2.8, 0, -3.4), 4)
		_step = 22141
	elif _step == 22141 and _t > 33.95:
		_shot("55_skeletons")
		# and they fall apart: every one struck down at once, the pickups held so no gem levels the hero over the frames
		_game.pickups.process_mode = Node.PROCESS_MODE_DISABLED
		for i in range(_game.enemies.MAX):
			if _game.enemies.alive[i] == 1:
				_game.enemies.damage(i, 100000.0, "")
		_step = 22143
	elif _step == 22143 and _t > 34.17:
		_shot("56_collapse")
		_step = 22144
	elif _step == 22144 and _t > 34.6:
		_shot("56b_bones")
		_game.pickups.process_mode = Node.PROCESS_MODE_INHERIT
		_game.camera.fixed_distance = 22.5
		_game.camera.snap_to(_game.player)
		_game.enemies.kill_all(false)
		_step = 22142
	elif _step == 22142 and _t > 34.28:
		# the harpooner: one troglodyte seven metres north with its throw ready and forty times its HP so the weapons
		# (back on) do not kill it before the rope holds; the hero walks away so the rope goes taut
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		var hi: int = _game.enemies.spawn("harpoon_troglodyte", _game.player.global_position + Vector3(0.5, 0, -13.0), null, 1.0, 40.0)
		if hi >= 0:
			_game.enemies.cooldown[hi] = 0.0
		_step = 2215
	elif _step == 2215 and _t > 36.6:
		# the harpoon is in the air or just landed: walk south so the rope pulls
		_game.player.input.wants_move = true
		_game.player.input.stick_dir = Vector2(0, 1)
		_step = 2216
	elif _step == 2216 and _t > 37.9:
		print("screenshot_run: tether ", _game.tether_i, " t ", _game.tether_t, " harpoon ", _game._harpoon_proj)
		_shot("38_harpoon")
		_game.player.input.wants_move = false
		_game.player.input.stick_dir = Vector2.ZERO
		_game.tether_end()
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		# the rocketeer (pass 29): the rocketeer sat down far to the north; he fires and his red rocket comes
		var ri: int = _game.enemies.spawn("rocketeer", _game.player.global_position + Vector3(2.0, 0, -18.0))
		if ri >= 0:
			# his brain stands him off at 28 m, past the top of the screen: for the figure he is pulled into shot
			var rp: Vector3 = _game.player.global_position + Vector3(1.6, 0, -11.5)
			_game.enemies.pos[ri] = Vector3(rp.x, _game.map.height_at(rp.x, rp.z), rp.z)
		_step = 2217
	elif _step == 2217 and _t > 41.2:
		# the rocket a second into its flight (it keeps to 90% of a standing hero's top speed, so by 43 s it has landed)
		print("screenshot_run: rockets ", _game.projectiles.rocket_of.size())
		_shot("39_rocketeer")
		# the rocket's blast (pass 33.3): a ring of skeletons round the hero first (a frame for the crowd's grid), then
		# the rocket put on his chest; the next frame is the fireball, the one after the hero thrown and the ring scattered
		for k in range(8):
			var ang: float = TAU * float(k) / 8.0
			var si: int = _game.enemies.spawn("goblin", _game.player.global_position + Vector3(cos(ang), 0, sin(ang)) * 2.6)
			if si >= 0:
				_game.enemies.speed[si] = 0.0
		_game.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
		_step = 22170
	elif _step == 22170 and _t > 41.3:
		var at_chest: Vector3 = _game.player.global_position + Vector3(0.2, 0.9, -0.3)
		if _game.projectiles.rocket_of.is_empty():
			# no rocket up (it landed early): the blast itself, with the rocketeer's numbers
			var art: Dictionary = root.get_node("Registry").enemy("rocketeer").artillery
			_game.rocket_blast(at_chest, float(art.get("missile", {}).get("area", 1.6)), 22.0, {"by": "Rocketeer", "kind": "ranged", "fx": ["rocket"]}, art.get("missile", {}))
		for rk in _game.projectiles.rocket_of.keys():
			_game.projectiles.pos[int(rk)] = at_chest
		_step = 22171
	elif _step == 22171 and _t > 41.42:
		_shot("53_rocket_blast")
		_step = 22172
	elif _step == 22172 and _t > 41.95:
		_shot("53b_rocket_thrown")
		# the badges (pass 33.3): a crown over an Elite skeleton and over the Dune Scorpion, gears over the harpooner and
		# the rocketeer; everyone held still with the weapons off
		_game.projectiles.clear_all()
		_game.enemies.kill_all(false)
		var reg3 = root.get_node("Registry")
		var hp3: Vector3 = _game.player.global_position
		var e1: int = _game.enemies.spawn("goblin", hp3 + Vector3(-2.2, 0, -2.6), reg3.elites.get("shielded"))
		var e2: int = _game.enemies.spawn("dune_scorpion", hp3 + Vector3(4.2, 0, -5.5))
		var e3: int = _game.enemies.spawn("harpoon_troglodyte", hp3 + Vector3(-3.6, 0, -8.5))
		var e4: int = _game.enemies.spawn("rocketeer", hp3 + Vector3(2.0, 0, -11.0))
		for ei in [e1, e2, e3, e4]:
			if ei >= 0:
				_game.enemies.speed[ei] = 0.0
				_game.enemies.cooldown[ei] = 30.0
				_game.enemies.atk_t[ei] = 30.0
		if e4 >= 0:
			_game.enemies.pos[e4] = Vector3(hp3.x + 2.0, _game.map.height_at(hp3.x + 2.0, hp3.z - 11.0), hp3.z - 11.0)
			# neither ready (0) nor fired (2): he holds his fire for the frame
			_game.enemies.atk_i[e4] = 1
		_game.enemies.spawn_pack("goblin", hp3 + Vector3(0.5, 0, 4.0), 5)
		_step = 22173
	elif _step == 22173 and _t > 42.8:
		_shot("52_badges")
		_game.weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
		_game.projectiles.clear_all()
		_game.enemies.kill_all(false)
		_step = 22174
	elif _step == 22174 and _t > 45.4:
		# the nuke: a pack around the hero, the pickup applied, the wave caught a quarter second out
		_game.projectiles.clear_all()
		_game.enemies.kill_all(false)
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(4.0, 0, -4.0), 10)
		_game.enemies.spawn_pack("fire_ant", _game.player.global_position + Vector3(-5.0, 0, 3.0), 12)
		_step = 2218
	elif _step == 2218 and _t > 45.9:
		_game.apply_pickup(root.get_node("Registry").pickup("nuke"), _game.player.global_position)
		_step = 2219
	elif _step == 2219 and _t > 46.1:
		_shot("40_nuke")
		# the turret: a plain turret placed, then the bunker (its motion pick, forced) placed beside it (pass 47: the
		# Watchtower mutation is gone)
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		_run.add_weapon(root.get_node("Registry").weapon("turret_buddy"), 3)
		_step = 2220
	elif _step == 2220 and _t > 46.5:
		if _game._behaviors.has("turret_buddy"):
			_game._behaviors["turret_buddy"]._fire()
		_run.add_mutation("bunker", true)
		_step = 22201
	elif _step == 22201 and _t > 46.9:
		if _game._behaviors.has("turret_buddy"):
			_game._behaviors["turret_buddy"]._fire()
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(0.0, 0, -6.0), 5)
		_step = 22202
	elif _step == 22202 and _t > 47.9:
		_shot("41_turrets")
		# the boss chest (pass 30): the purple one on the sand beside the hero, a plain one next to it for scale
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		_game.pickups.spawn_chest(_game.player.global_position + Vector3(2.6, 0, -1.2), true)
		_game.pickups.spawn_chest(_game.player.global_position + Vector3(-2.4, 0, -1.0))
		_step = 22203
	elif _step == 22203 and _t > 48.7:
		_shot("43_bosschest")
		for c in _game.pickups.chests:
			if is_instance_valid(c):
				c.queue_free()
		_game.pickups.chests.clear()
		# the laser: the Big Mouth at level 4 with two files of creatures to burn through (the run is at its weapon
		# cap by now, so the capture drops the starter to make room); the weapons run again, or the beam never ticks
		_game.weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
		while _run.weapons.size() >= _run.weapon_cap():
			_run.weapons.remove_at(0)
		_run.build_changed.emit()
		_run.add_weapon(root.get_node("Registry").weapon("big_mouth"), 4)
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(0.5, 0, -5.0), 4)
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(1.0, 0, -9.0), 4)
		_step = 22204
	elif _step == 22204 and _t > 49.3:
		if _game._behaviors.has("big_mouth"):
			_game._behaviors["big_mouth"].cooldown_left = 0.0
			_game._behaviors["big_mouth"]._fire()
		_step = 22205
	elif _step == 22205 and _t > 49.7:
		print("screenshot_run: laser beam ", (_game._behaviors["big_mouth"]._beam_t if _game._behaviors.has("big_mouth") else -1.0))
		_shot("44_laser")
		# the Strongbox (pass 33): the chest on its balloon beside the hero, the weapons held so nothing interrupts
		_game.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
		_game.projectiles.clear_all()
		_game.enemies.kill_all(false)
		var bank = _find_structure("gold_bank")
		if bank:
			_game.player.global_position = bank.global_position + Vector3(0.6, 0.5, 4.2)
			_game.player.velocity = Vector3.ZERO
			_game.camera.snap_to(_game.player)
		_step = 3301
	elif _step == 3301 and _t > 50.5:
		_shot("45_strongbox")
		# banked: the balloon lifts the box off and away; the next shot a few seconds into the climb
		var bank2 = _find_structure("gold_bank")
		if bank2 and not bank2.used:
			bank2.progress = 1.0
			_game.structures._use(bank2)
		_step = 3302
	elif _step == 3302 and _t > 53.7:
		_shot("45b_strongbox_away")
		# the Oil Slick (pass 33): a Molotov with the path thrown at a pack eight metres north; drops fall from the bottle
		# along the throw and each one lands as a small burning spill
		_game.player.global_position = Vector3(6, 1, 8)
		_game.player.facing = 0.0
		_game.camera.snap_to(_game.player)
		while _run.weapons.size() >= _run.weapon_cap():
			_run.weapons.remove_at(0)
		_run.build_changed.emit()
		_run.add_weapon(root.get_node("Registry").weapon("molotov"), 3)
		_run.add_mutation("oil_slick", true)
		for k in range(6):
			var gi2: int = _game.enemies.spawn("goblin", _game.player.global_position + Vector3(-1.2 + k * 0.5, 0, -8.5 + (k % 2) * 0.8), null, 1.0, 30.0)
			if gi2 >= 0:
				_game.enemies.speed[gi2] = 0.0
		_step = 3303
	elif _step == 3303 and _t > 54.2:
		if _game._behaviors.has("molotov"):
			_game._behaviors["molotov"]._fire()
		else:
			print("screenshot_run: no molotov behaviour; have ", _game._behaviors.keys())
		_step = 3304
	elif _step == 3304 and _t > 54.85:
		_shot("46_oil_slick")
		_step = 3305
	elif _step == 3305 and _t > 56:
		_shot("46b_fire_pool")
		# Berserk: the pickup taken, red flames round the hero's feet
		_game.apply_pickup(root.get_node("Registry").pickup("rage"), _game.player.global_position)
		_step = 3306
	elif _step == 3306 and _t > 56.6:
		_shot("47_berserk")
		# Berserk off again, so the fire gif is only the skeletons' fire
		for tb in _run.timed:
			tb["until"] = 0.0
		# the Energy Shield (pass 33.2): three levels, a moment to charge, then a skeleton's bite on it
		_game.enemies.kill_all(false)
		_game.projectiles.clear_all()
		# the capture's own card picks may have filled the passive slots: the last one taken makes room for the frame
		if not _run.passives.has("energy_shield") and _run.passives.size() >= 6:
			_run.passives.erase(_run.passives.keys()[_run.passives.size() - 1])
		_run.debug_set_item("passive", "energy_shield", 3)
		_game.camera.fixed_distance = 10.0
		_game.camera.snap_to(_game.player)
		_step = 3401
	elif _step == 3401 and _t > 59.3:
		_game.player.invuln = 0.0
		_game.player.take_damage(9.0, _game.player.global_position + Vector3(1, 0, 0), {"by": "Goblin", "kind": "melee"})
		_step = 3402
	elif _step == 3402 and _t > 59.5:
		_shot("48_energy_shield")
		# a maxed passive's evolution on the level-up table: the fourth level, then an offer that holds the Aegis card
		_run.debug_set_item("passive", "energy_shield", 4)
		var evo_offer: Array = []
		# CardPool uses the Run autoload, so it is loaded here rather than named (tools compile before autoloads)
		var card_pool = load("res://core/systems/CardPool.gd")
		for k in range(80):
			var o: Array = card_pool.level_up_offer(4)
			for c in o:
				if bool(c.get("evolve", false)):
					evo_offer = o
			if not evo_offer.is_empty():
				break
		if not evo_offer.is_empty():
			_game.set_paused(true)
			_game.cards.show_offer(evo_offer, "LEVEL %d!" % _run.level, false)
		_step = 3403
	elif _step == 3403 and _t > 60.3:
		_shot("49_passive_evolution")
		if _game.cards.visible:
			for c in _game.cards._offer:
				if bool(c.get("evolve", false)):
					_game.cards._pick(c)
		_step = 3404
	elif _step == 3404 and _t > 60.9:
		_game.resume_gate.tap()
		_game.set_paused(false)
		# the drop passives' pickups on the sand: a slice of cake and a coin bag
		var reg2 = root.get_node("Registry")
		_game.pickups.spawn_special(reg2.pickup("cake_slice"), _game.player.global_position + Vector3(1.8, 0, -1.2), true)
		_game.pickups.spawn_special(reg2.pickup("coin_bag"), _game.player.global_position + Vector3(-1.8, 0, -1.0), true)
		_step = 3405
	elif _step == 3405 and _t > 61.7:
		_shot("50_drops")
		# far zoom (pass 33.2): the camera held at 2.5x with a crowd around, so the creatures' marks show
		_game.camera.fixed_distance = 22.5
		_game.camera.zoom_override = 2.5
		_game.camera.snap_to(_game.player)
		_game.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
		_game.enemies.spawn_pack("goblin", _game.player.global_position + Vector3(6.0, 0, -9.0), 12)
		_game.enemies.spawn_pack("fire_ant", _game.player.global_position + Vector3(-7.0, 0, -4.0), 16)
		_game.enemies.spawn_pack("armadillo", _game.player.global_position + Vector3(2.0, 0, 8.0), 6)
		_step = 3406
	elif _step == 3406 and _t > 63.1:
		_shot("51_far_zoom")
		_game.camera.zoom_override = 0.0
		_game.weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
		_game.enemies.kill_all(false)
		# every path slot of the stage spent: from here on no path offer lands on a frame
		_run.path_slot = 99
		# fire: a tight skeleton pack, one lit with a certain spread, weapons off, frames every tenth of a second for a gif
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
	elif _step == 24 and _t > 65.7:
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
			# behind a big saguaro: the hero a step north of it (further from the camera) with a skeleton pack, for the outline pass
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
	elif _step == 26 and _t > 69.2:
		_shot("16_outline")
		# the skeletons fall apart: every body plays its death for the next capture
		_game.player.global_position += Vector3(2.5, 0, 3.0)
		_game.camera.snap_to(_game.player)
		for i in range(_game.enemies.MAX):
			if _game.enemies.alive[i] == 1:
				_game.enemies.damage(i, 100000.0, "boomstick")
		_step = 28
	elif _step == 28 and _t > 69.7:
		_shot("18_death")
		_game.weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
		_game.enemies.kill_all(false)
		# the hero goes down: the revive screen opens 1.2 s later (paused), is captured, and the debug door brings him back
		_game.player.god = false
		_game.player.invuln = 0.0
		_game.player.shield_t = 0.0
		var hp0: Vector3 = _game.player.global_position + Vector3(1, 0, 0)
		for hit in [[6.0, {"by": "Goblin", "kind": "melee", "fx": []}], [9.0, {"by": "Buckshot Dwarf", "kind": "ranged", "fx": ["buckshot", "knocked back"]}],
				[15.0, {"by": "Sun Prophet (Elite)", "kind": "ranged", "fx": ["pillar of light"]}], [12.0, {"by": "Bull Beetle", "kind": "melee", "fx": ["charge", "knocked back"]}]]:
			_game.player.invuln = 0.0
			_game.player.take_damage(float(hit[0]), hp0, hit[1])
		_game.player.invuln = 0.0
		_game.player.shield_pts = 0.0
		_game.player.take_damage(100000.0, hp0, {"by": "Tumbleweed King", "kind": "boss", "fx": ["slam", "knocked back"]})
		_step = 281
	elif _step == 281 and _t > 71.3:
		_shot("21_revive")
		if _game.revive_screen and _game.revive_screen.visible:
			_game.revive_screen._decide("debug")
		_game.player.god = true
		_step = 3
	elif _step == 3 and _t > 72.2:
		_game.open_pause()
		_step = 4
	elif _step == 4 and _t > 72.8:
		_shot("03_pause_build")
		_game.pause_screen._tab = 1
		_game.pause_screen._refresh()
		_step = 5
	elif _step == 5 and _t > 73.3:
		_shot("04_pause_stats")
		_game.close_pause()
		_game.director._start_boss(_game.director.map.boss if _game.director.map and _game.director.map.boss != "" else "tumbleweed_king")
		# far from the boss first: the HUD's edge pointer shows where it is
		_game.player.global_position = Vector3(6, 1, 46)
		_game.camera.snap_to(_game.player)
		_step = 23
	elif _step == 23 and _t > 74.5:
		_shot("15_boss_arrow")
		_game.player.global_position = Vector3(0, 1, 2)
		_game.camera.snap_to(_game.player)
		_step = 6
	elif _step == 6 and _t > 76.3:
		_shot("05_boss")
		# the portal (pass 33.3): the boss gone, its portal where it stood, the hero far off with the green marker on it
		var bpos: Vector3 = _game.enemies.pos[_game.enemies.boss_index] if _game.enemies.boss_index >= 0 else Vector3(0, 0, -10)
		_game.enemies.kill_all(false)
		_game.hud.hide_boss()
		_game._on_portal_ready(bpos)
		_game.player.global_position = Vector3(6, 1, 46)
		_game.camera.snap_to(_game.player)
		_step = 62
	elif _step == 62 and _t > 77.2:
		_shot("54_portal_arrow")
		if _game.portal:
			_game.portal.queue_free()
			_game.portal = null
		_game.director._start_boss("gila_grande")
		_game.player.global_position = Vector3(0, 1, 2)
		_game.camera.snap_to(_game.player)
		_step = 61
	elif _step == 61 and _t > 78.9:
		_shot("23_gila")
		# the dust devil: stand next to it with a skeleton pack inside so the lift shows
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
	elif _step == 60 and _t > 80.3:
		_shot("05b_tornado")
		_game = null
		print("screenshot_run: changing to title")
		var err := change_scene_to_file("res://ui/TitleScreen.tscn")
		print("screenshot_run: change_scene returned ", err)
		_step = 7
	elif _step == 7 and _t > 82.4:
		_shot("06_title")
		change_scene_to_file("res://ui/HomesteadScreen.tscn")
		_step = 8
	elif _step == 8 and _t > 83.2:
		# the Mirror: a full purse and a couple of ranks bought, so the board shows a live build
		var sv = root.get_node("Save")
		sv.add_gold(4000)
		for tid in ["grit", "drive"]:
			var td = root.get_node("Registry").talent(tid)
			if td:
				sv.buy_talent(td)
		sv.set_talent_form("drive", 1)
		if current_scene and current_scene.has_method("_refresh"):
			current_scene._refresh()
		# the board rebuilds its rows next frame: the shot waits for them
		_step = 801
	elif _step == 801 and _t > 83.7:
		_shot("07_homestead")
		change_scene_to_file("res://ui/CollectionScreen.tscn")
		_step = 9
	elif _step == 9 and _t > 84.6:
		_shot("08_collection")
		# play setup lives on the title since the Wanted UI (pass 38): the hero picker, swiped once
		change_scene_to_file("res://ui/TitleScreen.tscn")
		_step = 10
	elif _step == 10 and _t > 85.4:
		_shot("09_play_setup")
		change_scene_to_file("res://ui/SettingsScreen.tscn")
		_step = 11
	elif _step == 11 and _t > 86.2:
		_shot("10_settings")
		# the debug arena (pass 33.4): the panel's tabs over an empty field, then a crowd from the roster at 8:00
		_run.arena_next = true
		change_scene_to_file("res://game/Game.tscn")
		_step = 90
	elif _step == 90 and _t > 89.2:
		var ag = current_scene
		if ag and ag.get("arena_panel"):
			ag.arena_panel.open()
		_step = 91
	elif _step == 91 and _t > 89.8:
		_shot("57_arena_enemy")
		var ap = current_scene.arena_panel
		ap._tab = "items"
		ap._open["Weapons"] = true
		ap._refresh()
		_step = 92
	elif _step == 92 and _t > 90.3:
		_shot("57b_arena_items")
		current_scene.arena_panel._tab = "waves"
		current_scene.arena_panel._refresh()
		_step = 93
	elif _step == 93 and _t > 90.8:
		_shot("57c_arena_waves")
		current_scene.arena_panel.set_clock(8.0)
		current_scene.arena_panel.crowd(160)
		_step = 94
	elif _step == 94 and _t > 93.3:
		_shot("57d_arena_crowd")
		current_scene.leave_arena()
		_step = 95
	elif _step == 95 and _t > 94.3:
		quit(0)


## The structure the captures stand at: one whose use neither opens an overlay (the shop) nor levels the hero
## (beacon, magnet), so the spent painting is what the next shot shows.
func _find_structure(id: String):
	for st in _game.structures.items:
		if st.def.id == id:
			return st
	return null


func _capture_structure():
	for want in ["healing_well", "war_drum", "loot_cache", "dice_shrine", "uber_magnet", "beacon"]:
		for st in _game.structures.items:
			if st.def.id == want:
				return st
	return _game.structures.items[0]
