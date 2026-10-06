## Headless check of pass 43's Stage 3 (run with --script): a run jumped to stage 3 with a stage-3 build; the hell crowd
## spawning on its own cap beside the regular roster (blue slimes, imps, hellhounds, at most three giants), the ground
## gone red, the Brander's ring of fire and brand lines, the giant's slam, the Gila's rumble, then endless waves after
## the boss. Prints what it saw and exits non-zero on a script error or a missing piece.
##
##   godot --headless --path game --script res://tools/hell_check.gd [-- seconds=120]
extends SceneTree

var _t := 0.0
var _seconds := 110.0
var _game: Node
var _run: Node
var _phase := "boot"
var _seen: Dictionary = {}
var _errors: Array = []
var _last_report := -1
var _boss_at := -1.0
var _gila_at := -1.0
var _giant_slams := 0
var _ring_r0 := -1.0   # pass 48: the ring's radius and the play clock 3 s into the fight, to time its closing
var _ring_t0 := 0.0
var _play_t := 0.0     # seconds the game ran unpaused (the ring closes only then)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_seconds = float(a.trim_prefix("seconds="))
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "guitarra", "level": 4, "character": "calavera", "map": "red_canyon"}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	var err := change_scene_to_file("res://game/Game.tscn")
	if err != OK:
		printerr("hell_check: could not load Game.tscn (%d)" % err)
		quit(1)
		return
	process_frame.connect(_tick)


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
	if _game != null and is_instance_valid(_game) and not _game.paused:
		_play_t += dt
	if _game == null:
		_game = current_scene
		if _game == null or not _game.has_method("open_pause"):
			_game = null
			return
		if _game.player:
			_game.player.god = true
	if not is_instance_valid(_game) or current_scene != _game:
		_finish("the game scene went away (%s)" % str(current_scene))
		return
	if _game.player and _game.player.input and not _game.paused:
		var inp = _game.player.input
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_t * 0.7) * 90.0, -80.0 + cos(_t * 0.4) * 60.0)
	# every screen out of the way
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(true)
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.portal_dialog and _game.portal_dialog.visible:
		_seen["portal_final"] = _game.portal_dialog._cont_title.text
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)
		print("hell_check: portal -> stay (%s)" % _seen["portal_final"])
	match _phase:
		"boot":
			if _t > 3.0:
				_phase = "stage3"
				# stage 3, three seconds into it, the director past every earlier event; a stage-3 build (the stage clock is
				# the timeline's: pass 46 stretched Red Canyon's stages from 300 s to 430 s)
				var tl = _game.director.timeline
				var at: float = 2.0 * float(tl.stage_length) + 3.0
				_run.stage = 2
				_run.elapsed = at
				for k in range(tl.events.size()):
					if float(tl.events[k].get("t", 0.0)) < at:
						_game.director._event_i = k + 1
				_game.director.continue_to_next_stage()
				_run.stage = 2
				_run.elapsed = at
				_game.director._apply_mults()
				for k in range(12):
					_run.add_xp(_run.xp_to_next() + 1.0)
				_run.add_or_level_passive("brimstone_brand")
				_run.add_or_level_passive("sinners_greed")
				for pk in ["crescendo", "serenade", "grand_finale"]:
					if _run.has_method("add_perk"):
						_run.add_perk(pk)
					elif not _run.perks.has(pk):
						_run.perks.append(pk)
				_run.rebuild_sheets()
				print("hell_check: jumped to stage 3 (event %d), stage mult %.2f, hell cap %.2f, perks %s" % [_game.director._event_i, _run.stage_mult(), tl.hell_cap_at(2), str(_run.perks)])
		"stage3":
			var em = _game.enemies
			for id in ["blue_slime", "imp", "hellhound", "hammer_giant"]:
				if em.alive_of(id) > 0:
					_seen[id] = maxi(int(_seen.get(id, 0)), em.alive_of(id))
			if em.alive_of("hammer_giant") > 3:
				_errors.append("more than three giants alive")
			if _game.map.get("_hell") != null and float(_game.map._hell) > 0.99:
				_seen["hell_tint"] = true
			# the Gila's rumble, once, from beside the hero
			if _t > 8.0 and _gila_at < 0.0:
				_gila_at = _t
				var i: int = em.spawn("gila_grande", _game.player.global_position + Vector3(6, 0, 0))
				if i >= 0:
					em.atk_t[i] = 0.0
					em.atk_i[i] = 1   # the rumble is its second attack
			if not em._rumbles.is_empty():
				_seen["rumble"] = true
			# a giant right by the hero so its slam runs: one the director brought, walked over, or a new one when there is
			# none (pass 48: a fourth one spawned by hand next to the director's three tripped the three-at-most check)
			if _t > 12.0 and not _seen.has("giant_spawned"):
				_seen["giant_spawned"] = true
				var near_at: Vector3 = _game.player.global_position + Vector3(2.5, 0, 0)
				var gi := -1
				for i in range(em.MAX):
					if em.is_alive(i) and (em.types[em.type_idx[i]]["def"]).id == "hammer_giant":
						gi = i
						break
				if gi >= 0:
					em.pos[gi] = Vector3(near_at.x, _game.map.height_at(near_at.x, near_at.z), near_at.z)
				else:
					em.spawn("hammer_giant", near_at)
			for i in range(em.MAX):
				if em.alive[i] == 1 and (em.types[em.type_idx[i]]["def"]).id == "hammer_giant" and em.state[i] == em.STATE_ATTACK:
					_seen["giant_windup"] = true
			# the boss at 20 s: the ring and the lines
			if _t > 20.0 and _boss_at < 0.0:
				_boss_at = _t
				em.kill_all(true)
				_game.director._run_event({"type": "boss", "enemy": "brander"})
			if _boss_at > 0.0:
				if not _game._ring.is_empty():
					_seen["ring"] = true
					_seen["ring_r"] = snappedf(float(_game._ring["r"]), 0.1)
					# pass 48: the ring closes at the pace knob, (radius - min_radius) / shrink metres a second times the pace
					var rr: float = float(_game._ring["r"])
					if _t > _boss_at + 3.0 and _ring_r0 < 0.0:
						_ring_r0 = rr
						_ring_t0 = _play_t
					elif _ring_r0 > 0.0 and _play_t > _ring_t0 + 6.0 and not _seen.has("ring_rate"):
						var cfg: Dictionary = _game._ring["cfg"]
						var want: float = (float(cfg.get("radius", 21.0)) - float(cfg.get("min_radius", 8.0))) / float(cfg.get("shrink", 42.0)) * float(_run.move_pace())
						var rate: float = (_ring_r0 - rr) / (_play_t - _ring_t0)
						_seen["ring_rate"] = "%.3f m/s (pace %.2f wants %.3f)" % [rate, float(_run.move_pace()), want]
						if absf(rate - want) > want * 0.2:
							_errors.append("the ring closes at %.3f m/s, the pace wants %.3f" % [rate, want])
				if not _game._hell_lines.is_empty():
					_seen["brand_lines"] = true
					# pass 45: the Brander never burns on his own brand lines (he stands at their start and rolls down them).
					# One full tick of every line and the ring, nothing else between the two reads of his HP.
					if em.boss_alive() and not _seen.has("self_burn"):
						var hb: float = em.hp[em.boss_index]
						_game._tick_hell(0.6)
						if em.hp[em.boss_index] < hb - 0.001:
							_errors.append("the Brander burned on his own brand line: %.1f -> %.1f" % [hb, em.hp[em.boss_index]])
						_seen["self_burn"] = em.hp[em.boss_index] < hb - 0.001
				# a hero outside the ring burns (god mode keeps him alive; the log says so)
				if _t > _boss_at + 30.0 and _t < _boss_at + 31.0 and not _game._ring.is_empty():
					var c: Vector3 = _game._ring["center"]
					_game.player.global_position = c + Vector3(float(_game._ring["r"]) + 6.0, 0.5, 0)
				if _t > _boss_at + 34.0 and em.boss_alive():
					em.damage(em.boss_index, 100000.0, "guitarra")
				if _t > _boss_at + 36.0 and not em.boss_alive() and _game._ring.is_empty():
					_seen["ring_gone"] = true
				if _game.portal and is_instance_valid(_game.portal) and _game.portal.armed and not _game.paused:
					_game.player.global_position = _game.portal.global_position + Vector3(0.2, 0.5, 0)
				if _run.endless:
					_seen["endless"] = true
					_seen["wave"] = _run.endless_wave()
					if _t > _boss_at + 44.0:
						# a wave a frame, to see the multiplier climb (a wave is the timeline's endless_wave_seconds)
						_run.elapsed += float(_game.director.timeline.endless_wave_seconds)
						_seen["endless_mult"] = snappedf(_run.stage_mult(), 0.01)
			if _run.endless and _run.endless_wave() >= 4:
				_finish("")
				return
	var sec := int(_t)
	if sec != _last_report and sec % 4 == 0:
		_last_report = sec
		var em2 = _game.enemies
		var up: Array = []
		for k in ["cards", "chest_screen", "resume_gate", "portal_dialog", "stranger_screen", "revive_screen", "structure_shop", "pause_screen"]:
			var c = _game.get(k)
			if c != null and c is CanvasItem and (c as CanvasItem).visible:
				up.append(k)
		print("t=%3ds stage=%d clock=%s alive=%3d hob=%d imp=%d hound=%d giant=%d boss=%s ring=%s lines=%d crescendo=%d mult=%.2f play=%.0fs paused=%s %s" % [sec, _run.stage + 1,
			"%d:%02d" % [int(_run.elapsed) / 60, int(_run.elapsed) % 60], _run.alive, em2.alive_of("blue_slime"), em2.alive_of("imp"), em2.alive_of("hellhound"),
			em2.alive_of("hammer_giant"), str(em2.boss_alive()), str(_game._ring.get("r", "-")), _game._hell_lines.size(), _run.crescendo, _run.stage_mult(),
			_play_t, str(_game.paused), str(up)])
	if _t >= _seconds:
		_finish("timeout in phase " + _phase)


func _finish(why: String) -> void:
	var want := ["blue_slime", "imp", "hellhound", "hammer_giant", "hell_tint", "rumble", "giant_windup", "ring", "ring_rate", "brand_lines", "ring_gone", "endless", "portal_final"]
	var missing: Array = []
	for k in want:
		if not _seen.has(k):
			missing.append(k)
	print("hell_check: seen %s" % str(_seen))
	if why != "":
		print("hell_check: " + why)
	if not missing.is_empty():
		print("hell_check: MISSING %s" % str(missing))
	if not _errors.is_empty():
		print("hell_check: ERRORS %s" % str(_errors))
	var ok := missing.is_empty() and _errors.is_empty() and why == ""
	print("hell_check: %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
