## Pass 118 (lane BOSSCHEST): the boss chests proved by eye. In the debug arena: the three boss chests in the world
## beside a purple chest and an ordinary one (the row and each chest close up, at two turns), then each boss's pop-up at
## its beats (the drop, a knock, the crack, the burst, the spew early and late, JACKPOT, CLAIM) with a sample of what that
## boss pays (BossChest.sample_pack: the King after a fast fight, the Gila after a middling one, the Brander after a slow
## one, so the speed gauge shows all three), and the King's payout flying in after CLAIM.
## Windowed:
##   GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/_p118_BOSSCHEST_shots.gd -- out=<dir> [only=world,popup]
## Pass 128: `only=meter [mults=1,1.3,1.6,2,9.9]` = the speed panel at chosen multipliers (asked for by name only).
## The UI review's set (tools/ui_review_capture.sh: `bosschest`) takes the King's beats from here. A watchdog quits after
## 300 s; every wait is bounded. The PC save is put back as it was.
extends SceneTree

const BOSSES := [["tumbleweed_king", 0, 45.0], ["gila_grande", 1, 150.0], ["black_sunday", 2, 250.0], ["brander", 3, 400.0]]
var _out := "user://bosschest_shots"
var _only: Array = []
var _mults: Array = [1.0, 1.3, 1.6, 2.0, 9.9]
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("mults="):
			_mults.clear()
			for s in a.substr(6).split(","):
				_mults.append(float(s))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("bosschest_shots: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(k: String) -> bool:
	return _only.is_empty() or _only.has(k)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String, crops: bool = false) -> void:
	await _frames(3)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	if crops:
		var cam: Camera3D = g.camera.get_viewport().get_camera_3d()
		for c in g.pickups.chests:
			var sp: Vector2 = cam.unproject_position(c.global_position + Vector3(0, 0.6, 0))
			var r := Rect2i(int(sp.x) - 210, int(sp.y) - 330, 420, 480).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			var tag := str(c.boss_id) if str(c.boss_id) != "" else ("purple" if c.boss else "chest")
			img.get_region(r).save_png(_out.path_join("%s_%s.png" % [name, tag]))
	print("bosschest_shots: ", name)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _main() -> void:
	var run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _frames(150)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	g.enemies.kill_all(false)
	await _frames(30)
	var BC = load("res://core/systems/BossChest.gd")
	var BCS = load("res://ui/BossChestScreen.gd")
	var here := _ground(g.player.global_position)
	if _want("world"):
		var xs := [-6.0, -3.0, 0.0, 3.0, 6.0]
		g.pickups.spawn_chest(_ground(here + Vector3(xs[0], 0, -6.0)))
		g.pickups.spawn_chest(_ground(here + Vector3(xs[1], 0, -6.0)), true)
		for k in range(3):
			var bid: String = BOSSES[k][0]
			g.pickups.spawn_boss_chest(_ground(here + Vector3(xs[k + 2], 0, -6.0)), bid, BC.sample_pack(bid, 0, 30.0))
		await _frames(20)
		await _shot("world_row", true)
		await _frames(50)
		await _shot("world_row_turn", true)
		for c in g.pickups.chests:
			c.queue_free()
		g.pickups.chests.clear()
		await _frames(5)
		# each boss's chest alone, as a kill leaves it, under its own stage's look (Sundown, Nightfall's blue, Blood Moon's
		# red: the chests are never tinted, the world is)
		var SL = load("res://core/systems/StageLook.gd")
		for b: Array in BOSSES:
			var bid2: String = b[0]
			SL.of(g).show_stage(int(b[1]), 0.0)
			g.pickups.spawn_boss_chest(_ground(here + Vector3(0.0, 0, -4.5)), bid2, BC.sample_pack(bid2, 0, 30.0))
			await _frames(30)
			await _shot("world_solo_%s" % bid2, true)
			for c in g.pickups.chests:
				c.queue_free()
			g.pickups.chests.clear()
			await _frames(5)
	if _want("world"):
		load("res://core/systems/StageLook.gd").of(g).show_stage(0, 0.0)
		await _frames(5)
	if _want("popup"):
		for b: Array in BOSSES:
			var bid: String = b[0]
			var pack: Dictionary = BC.sample_pack(bid, int(b[1]), float(b[2]))
			g.open_boss_chest(_ground(here + Vector3(0.8, 0, -0.6)), bid, pack)
			await _frames(2)
			var bs = g.boss_chest_screen
			bs.set_process(false)
			await _frames(25)
			var spew: float = float(bs.get("_spew_len"))
			var end_t: float = float(bs.get("_end_t"))
			var beats := [["a_drop", 0.16, 0], ["b_knock", 1.12, 0], ["c_crack", 1.72, 0], ["d_burst", BCS.BURST + 0.12, 20],
				["e_spew_early", BCS.SPEW_AT + spew * 0.32, 0], ["f_spew_late", BCS.SPEW_AT + spew * 0.86, 12],
				["g_jackpot", end_t + BCS.FINALE + 0.1, 22], ["h_claim", end_t + BCS.CLAIM_AFTER + 0.5, 6]]
			for bt: Array in beats:
				bs.seek(float(bt[1]))
				await _frames(int(bt[2]))
				await _shot("popup_%s_%s" % [bid, bt[0]])
			print("bosschest_shots: %s counted %s of %d gold, %d XP (x%.2f, fight %.0f s)" % [bid, str(bs.counters()), int(bs.gold_total),
				int(round(float(bs.xp_total))), float(pack.get("mult", 1.0)), float(pack.get("fight", -1.0))])
			bs.set_process(true)
			bs.claim()
			for k in range(60):
				await process_frame
				if not bs.visible:
					break
			if bid == "tumbleweed_king":
				# the payout bursting out of the chest's spot and flying in
				await _frames(14)
				await _shot("payout_burst")
				await _frames(30)
				await _shot("payout_flying")
			await _frames(90)
			g.modal_reset()
			g.set_paused(false)
			await _frames(10)
	# pass 128 (only=meter, never part of the default set): the speed panel alone at chosen multipliers (mults=1,1.3,1.6,2,9.9),
	# the King's chest at CLAIM with the pack's multiplier set by hand: the whole screen and the panel's crop
	if _only.has("meter"):
		for mv: float in _mults:
			var pack2: Dictionary = BC.sample_pack("tumbleweed_king", 0, 45.0)
			pack2["mult"] = mv
			g.open_boss_chest(_ground(here + Vector3(0.8, 0, -0.6)), "tumbleweed_king", pack2)
			await _frames(2)
			var bs2 = g.boss_chest_screen
			bs2.set_process(false)
			await _frames(25)
			bs2.seek(float(bs2.get("_end_t")) + BCS.CLAIM_AFTER + 0.5)
			await _frames(6)
			var tag := ("%.1f" % mv).replace(".", "_")
			await _shot("meter_x%s" % tag)
			var mr: Rect2 = bs2.get("_meter_rect")
			var img2 := root.get_viewport().get_texture().get_image()
			var cr := Rect2i(Rect2(mr.position - Vector2(24, 24), mr.size + Vector2(48, 60))).intersection(Rect2i(Vector2i.ZERO, img2.get_size()))
			img2.get_region(cr).save_png(_out.path_join("meter_x%s_crop.png" % tag))
			print("bosschest_shots: meter x%.1f bar starts %.1f, the multiplier ends %.1f" % [mv, BCS.meter_bar_x(mv),
				BCS.ROYALE_PAD + BCS.meter_mult_width(mv)])
			bs2.set_process(true)
			bs2.claim()
			for k in range(60):
				await process_frame
				if not bs2.visible:
					break
			await _frames(90)
			g.modal_reset()
			g.set_paused(false)
			await _frames(10)
	_save.data = keep
	print("bosschest_shots: done")
	quit(0)
