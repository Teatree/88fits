extends GdUnitTestSuite
## Pass 118 (lane BOSSCHEST; Garry: "Each Boss now drops a unique chest and inside it is a whole bunch of EXP and Gold
## (it's the same gold and EXP that Players already get from killing the boss, now packaged into this chest) ... The
## faster the Boss was killed the more Gold and Exp flies out ... At the end of the sequence Player has to tap a Claim
## button ... Picking up these chests also results in all the of stuff flying in towards the Player."):
## the speed bonus's curve and the map's block, the pack and its net amounts, the pieces' shares, the kill's catch, a
## boss's kill packing its purse, coins and XP into its own chest (not the purple one), the pop-up's count and its CLAIM
## paying exactly the counters, a tool's claim, the purple chest where no boss's kill packed anything.

var _keep := {}


func before_test() -> void:
	_keep = {"debug_mode": Settings.debug_mode, "top_inset": Settings.top_inset}
	Settings.debug_mode = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Settings.debug_mode = bool(_keep["debug_mode"])
	Settings.top_inset = int(_keep["top_inset"])
	Run.forced_map_seed = 0
	Run.arena = false
	Run.sim_mode = false
	Run.end()


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


func _game() -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	g.player.god = true
	return g


# ---------------------------------------------------------------- the rules

func test_the_speed_bonus_is_whole_up_to_fast_times_s_gone_by_slow_times_s_and_a_line_between() -> void:
	var cfg := BossChest.config({"fast": 1.5, "slow": 4.0, "max_mult": 2.0})
	assert_float(BossChest.speed_mult(30.0, 40.0, cfg)).is_equal(2.0)
	assert_float(BossChest.speed_mult(60.0, 40.0, cfg)).is_equal(2.0)
	assert_float(BossChest.speed_mult(110.0, 40.0, cfg)).is_equal_approx(1.5, 0.0001)
	assert_float(BossChest.speed_mult(160.0, 40.0, cfg)).is_equal(1.0)
	assert_float(BossChest.speed_mult(900.0, 40.0, cfg)).is_equal(1.0)
	# no S, or no fight timed: no bonus
	assert_float(BossChest.speed_mult(10.0, 0.0, cfg)).is_equal(1.0)
	assert_float(BossChest.speed_mult(-1.0, 40.0, cfg)).is_equal(1.0)
	# the defaults fill a block's gaps, and nothing below x1
	var c2 := BossChest.config({"max_mult": 3.0})
	assert_float(float(c2["fast"])).is_equal(1.5)
	assert_float(float(c2["slow"])).is_equal(4.0)
	assert_float(float(c2["max_mult"])).is_equal(3.0)
	assert_float(float(BossChest.config({"max_mult": 0.5})["max_mult"])).is_equal(1.0)
	assert_dict(BossChest.config(null)).is_equal(BossChest.DEFAULTS)


func test_the_map_carries_the_block_and_the_game_reads_it() -> void:
	# (read from the map's file, not pinned: Garry tunes it in the Level Editor)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var block: Dictionary = d["timeline_data"].get("boss_chest", {})
	assert_dict(block).is_not_empty()
	var cfg := BossChest.config(Run.map.timeline)
	for k in BossChest.DEFAULTS.keys():
		if block.has(k):
			assert_float(float(cfg[k])).override_failure_message(k).is_equal(maxf(float(block[k]), 1.0) if k == "max_mult" else float(block[k]))


func test_a_pack_is_the_kill_s_pay_times_the_bonus_and_its_net_is_through_greed_and_field_notes() -> void:
	var p := BossChest.make_pack("brander", 1000.0, 2000.0, 30.0, 60.0, BossChest.DEFAULTS, 2)
	assert_float(float(p["mult"])).is_equal(2.0)
	assert_int(int(p["gold"])).is_equal(2000)
	assert_float(float(p["xp"])).is_equal(4000.0)
	assert_str(str(p["boss"])).is_equal("brander")
	var slow := BossChest.make_pack("brander", 1000.0, 2000.0, 999.0, 60.0, BossChest.DEFAULTS, 2)
	assert_int(int(slow["gold"])).is_equal(1000)
	var n := BossChest.net(p, 1.25, 1.1)
	assert_int(int(n["gold_net"])).is_equal(2500)
	assert_float(float(n["xp_net"])).is_equal_approx(4400.0, 0.001)


func test_the_shares_add_up_to_the_totals_exactly() -> void:
	for total: int in [0, 1, 7, 999, 2501]:
		for n: int in [1, 3, 10, 70]:
			var parts := BossChest.split_int(total, n)
			assert_int(parts.size()).is_equal(n)
			var s := 0
			for v in parts:
				s += int(v)
			assert_int(s).is_equal(total)
	var xs := BossChest.split_float(1234.567, 13)
	var sx := 0.0
	for v in xs:
		sx += float(v)
	assert_float(sx).is_equal_approx(1234.567, 0.0001)
	assert_bool(BossChest.piece_counts(0, 0.0) == Vector2i(0, 0)).is_true()
	var pc := BossChest.piece_counts(5000, 90000.0)
	assert_int(pc.x).is_equal(BossChest.PIECES_MAX)
	assert_int(pc.y).is_equal(BossChest.PIECES_MAX)
	# a little gold: never more coins than gold
	assert_int(BossChest.piece_counts(4, 100.0).x).is_equal(4)


func test_each_boss_has_its_chest_s_look() -> void:
	for bid: String in ["tumbleweed_king", "gila_grande", "brander"]:
		var lk := BossChest.look(bid)
		assert_str(str(lk["name"])).is_not_empty()
		assert_bool(ResourceLoader.exists(str(lk["model"]))).override_failure_message(str(lk["model"])).is_true()
		var model: Node3D = (load(str(lk["model"])) as PackedScene).instantiate()
		assert_object(model.find_child("Lid", true, false)).override_failure_message(bid + ": no Lid").is_not_null()
		model.free()
		assert_int(BossChest.paintings(bid).size()).override_failure_message(bid + ": paintings").is_equal(3)


# ---------------------------------------------------------------- the kill

func test_the_kill_s_catch_packs_what_would_have_dropped() -> void:
	var g := await _game()
	var pk: PickupManager = g.pickups
	var n0: int = pk.count
	var old = pk.capture_swap({"gold": 0.0, "xp": 0.0})
	assert_int(pk.spawn(PickupManager.KIND_COIN, Vector3.ZERO, 5.0)).is_equal(-1)
	assert_int(pk.spawn(PickupManager.KIND_GEM_L, Vector3.ZERO, 25.0)).is_equal(-1)
	assert_int(pk.spawn(PickupManager.KIND_GEM_S, Vector3.ZERO, 1.5)).is_equal(-1)
	var c: Dictionary = pk.capture_swap(old)
	assert_int(pk.count).is_equal(n0)
	assert_float(float(c["gold"])).is_equal(5.0 * float(maxi(int(round(Run.stage_mult())), 1)))
	assert_float(float(c["xp"])).is_equal(26.5)
	# off again: spawns land
	assert_int(pk.spawn(PickupManager.KIND_COIN, Vector3.ZERO, 5.0)).is_greater_equal(0)


func test_a_boss_kill_packs_its_purse_coins_and_xp_into_its_own_chest_not_the_purple_one() -> void:
	var g := await _game()
	var em: EnemyManager = g.enemies
	var pk: PickupManager = g.pickups
	g.director._start_boss("tumbleweed_king", g.player.global_position + Vector3(0, 0, -9))
	var bi: int = em.boss_index
	assert_int(bi).is_greater_equal(0)
	var xs: float = em.xp_scale[bi]
	var gold0: int = Run.run_gold
	var def := Registry.enemy("tumbleweed_king")
	# the killing blow once it has risen out of the sand (a 20 s fight)
	var hit := false
	for n in range(300):
		g.director.boss_t0 = Run.rule_seconds() - 20.0
		if em.damage(bi, 1.0e12, ""):
			hit = true
			break
		await _frames(1)
	assert_bool(hit).is_true()
	await _frames(2)
	# nothing paid at the kill: no purse in the gold, no boss coins on the sand
	assert_int(Run.run_gold).is_equal(gold0)
	assert_bool(pk.coin_from.values().has("boss_coins")).is_false()
	var mine: Array = pk.chests.filter(func(c): return is_instance_valid(c) and str(c.boss_id) == "tumbleweed_king")
	var purple: Array = pk.chests.filter(func(c): return is_instance_valid(c) and bool(c.boss))
	assert_int(mine.size()).is_equal(1)
	assert_int(purple.size()).is_equal(0)
	var pack: Dictionary = mine[0].pack
	# its gold: the purse, drops.coins coins of 5 at the stage's coin factor, its own coin (0..4 of them after the
	# Stakes' chance and the barrels' bill)
	var k := float(maxi(int(round(Run.stage_mult())), 1))
	var bounty := MirrorDanger.factor_of(def, "bounty")
	var base := float(int(Game.boss_purse(Run.stage) * bounty)) + float(MirrorDanger.scaled_count(float(def.drops.get("coins", Game.BOSS_COINS)), bounty)) * 5.0 * k
	assert_float(float(pack["gold_base"])).is_between(base, base + 4.0 * k)
	# its XP: its large gem at its XP scale and the stage's shares
	var xp := 25.0 * xs * g.director.xp_share() * g.director.stage_xp_mult()
	assert_float(float(pack["xp_base"])).is_equal_approx(xp, 0.01)
	# the bonus for 20 s against the map's S
	var secs: float = Run.map.timeline.boss_seconds("tumbleweed_king")
	assert_float(float(pack["fight"])).is_between(19.0, 22.0)
	var m := BossChest.speed_mult(float(pack["fight"]), secs, BossChest.config(Run.map.timeline))
	assert_float(float(pack["mult"])).is_equal_approx(m, 0.0001)
	assert_int(int(pack["gold"])).is_equal(int(round(float(pack["gold_base"]) * m)))
	assert_float(float(pack["xp"])).is_equal_approx(float(pack["xp_base"]) * m, 0.001)


func test_a_pack_no_chest_took_gets_its_chest_by_the_frame_s_end() -> void:
	var g := await _game()
	var pk: PickupManager = g.pickups
	g._pack_boss_chest(Registry.enemy("brander"), g.player.global_position, {"gold": 100.0, "xp": 50.0})
	await _frames(1)
	var mine: Array = pk.chests.filter(func(c): return is_instance_valid(c) and str(c.boss_id) == "brander")
	assert_int(mine.size()).is_equal(1)
	assert_dict(g.take_boss_pack()).is_empty()


func test_a_stage_that_ends_with_no_boss_keeps_the_purple_chest() -> void:
	var g := await _game()
	var pk: PickupManager = g.pickups
	g.director.phase = WaveDirector.Phase.BOSS
	g.director._on_boss_died(null, g.player.global_position + Vector3(5, 0, 0))
	var purple: Array = pk.chests.filter(func(c): return is_instance_valid(c) and bool(c.boss))
	assert_int(purple.size()).is_equal(1)
	assert_str(str(purple[0].boss_id)).is_empty()


# ---------------------------------------------------------------- the pop-up and CLAIM

func test_the_pop_up_has_its_turn_and_claim_pays_exactly_its_counters() -> void:
	var g := await _game()
	assert_int(int(Game.MODAL_PRIORITY[Game.Modal.BOSSCHEST])).is_equal(int(Game.MODAL_PRIORITY[Game.Modal.CHEST]) + Game.BOSS_CHEST_BUMP)
	var pack := BossChest.make_pack("gila_grande", 503.0, 1234.5, 30.0, 60.0, BossChest.DEFAULTS, 1)
	g.open_boss_chest(g.player.global_position + Vector3(1, 0, 0), "gila_grande", pack)
	await _frames(1)
	assert_array(g.visible_modals()).is_equal(["boss_chest"])
	assert_int(g.current_modal()).is_equal(Game.Modal.BOSSCHEST)
	assert_bool(g.paused).is_true()
	var bs = g.boss_chest_screen
	var greed: float = Run.player_sheet.get_stat("greed", 1.0)
	var gain: float = Run.player_sheet.get_stat("xp_gain", 1.0)
	var want_gold := int(round(float(pack["gold"]) * greed))
	var want_xp := float(pack["xp"]) * gain
	assert_int(int(bs.gold_total)).is_equal(want_gold)
	assert_float(float(bs.xp_total)).is_equal_approx(want_xp, 0.001)
	# nothing counted before the burst; everything by the end, exactly
	bs.seek(BossChestScreen.BURST - 0.1)
	assert_array(bs.counters()).is_equal([0, 0])
	assert_bool(bs.ready_to_claim()).is_false()
	bs.finish_now()
	assert_array(bs.counters()).is_equal([want_gold, int(round(want_xp))])
	assert_bool(bs.ready_to_claim()).is_true()
	# CLAIM pays exactly the counters in the same call, and gives the turn back at once
	var g0: int = Run.run_gold
	var got := [0.0]
	var cb := func(n: float) -> void: got[0] += n
	Run.xp_gained.connect(cb)
	bs.claim()
	Run.xp_gained.disconnect(cb)
	assert_int(Run.run_gold - g0).is_equal(want_gold)
	assert_float(float(got[0])).is_equal_approx(want_xp, 0.01)
	assert_bool(bs.visible).is_false()
	assert_int(g.current_modal()).is_not_equal(Game.Modal.BOSSCHEST)
	# the payout: pieces at the chest's spot holding the counters' shares, for the show
	var pk: PickupManager = g.pickups
	var sg := 0
	var sx := 0.0
	for i in pk.exact_pay.keys():
		if pk.kind[i] == PickupManager.KIND_COIN:
			sg += int(pk.exact_pay[i])
			assert_str(str(pk.coin_from.get(i, ""))).is_equal("boss_chest")
		else:
			sx += float(pk.exact_pay[i])
	assert_int(sg).is_equal(want_gold)
	assert_float(sx).is_equal_approx(want_xp, 0.001)
	# ... which pay nothing more when they land
	var g1: int = Run.run_gold
	got[0] = 0.0
	Run.xp_gained.connect(cb)
	for i in pk.exact_pay.keys().duplicate():
		pk._collect(i)
	Run.xp_gained.disconnect(cb)
	assert_int(Run.run_gold).is_equal(g1)
	assert_float(float(got[0])).is_equal(0.0)
	assert_dict(pk.exact_pay).is_empty()


func test_the_count_starts_slowly_and_swells_and_a_tap_hurries_it() -> void:
	var g := await _game()
	var bs = g.boss_chest_screen
	var pack := BossChest.net(BossChest.make_pack("brander", 900.0, 3000.0, 50.0, 60.0, BossChest.DEFAULTS, 2), 1.0, 1.0)
	g.set_paused(true)
	bs.open("brander", pack)
	var total: int = (bs.pieces() as Vector2i).x
	assert_int(total).is_greater(40)
	var spew: float = float(bs.get("_spew_len"))
	var t0: float = BossChestScreen.SPEW_AT
	bs.seek(t0 + spew * 0.5 + 0.7)
	var half: int = (bs.pieces() as Vector2i).y
	bs.seek(t0 + spew + 1.2)
	var all: int = (bs.pieces() as Vector2i).y
	# the second half of the spew throws more than the first
	assert_int(all - half).is_greater(half)
	assert_int(all).is_equal(total)
	# the faster kill spews longer
	var slow := BossChest.net(BossChest.make_pack("brander", 900.0, 3000.0, 999.0, 60.0, BossChest.DEFAULTS, 2), 1.0, 1.0)
	bs.open("brander", slow)
	assert_float(float(bs.get("_spew_len"))).is_less(spew)
	# a tap before the burst goes to it; one during the spew speeds the rest
	bs.seek(0.6)
	bs.hurry()
	assert_float(float(bs.get("_t"))).is_greater_equal(BossChestScreen.BURST - 0.06)
	bs.seek(BossChestScreen.SPEW_AT + 0.5)
	bs.hurry()
	assert_float(float(bs.get("_speed"))).is_greater(1.5)
	bs.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_a_tool_s_claim_finishes_the_count_first_and_the_bot_claims() -> void:
	var g := await _game()
	Run.sim_mode = true
	var pack := BossChest.make_pack("tumbleweed_king", 300.0, 800.0, 40.0, 40.0, BossChest.DEFAULTS, 0)
	g.open_boss_chest(g.player.global_position + Vector3(1, 0, 0), "tumbleweed_king", pack)
	await _frames(1)
	var bs = g.boss_chest_screen
	assert_bool(bs.visible).is_true()
	var g0: int = Run.run_gold
	bs.claim()
	assert_array(bs.counters()).is_equal([int(bs.gold_total), int(round(float(bs.xp_total)))])
	assert_int(Run.run_gold - g0).is_equal(int(bs.gold_total))
	assert_bool(bs.visible).is_false()
	assert_int(g.pickups.exact_pay.size()).is_greater(0)
	# a second claim does nothing
	bs.claim()
	assert_int(Run.run_gold - g0).is_equal(int(bs.gold_total))
	# the run sim's bot and the smoke run claim it (their screen loops name it)
	assert_str(FileAccess.get_file_as_string("res://tools/bot/Bot.gd")).contains("boss_chest_screen")
	assert_str(FileAccess.get_file_as_string("res://tools/smoke_run.gd")).contains("boss_chest_screen")
	Run.sim_mode = false
	await _frames(2)
