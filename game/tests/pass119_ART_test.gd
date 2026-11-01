extends GdUnitTestSuite
## Pass 119 (lane ART; Garry: "All Boss Chest sequences need more coins floating and other floating stuff"): the boss
## chest pop-up's party. It is drawn under everything that reads (the title, the speed bonus, the banner, the counters
## and CLAIM), its size follows the speed bonus, it keeps going after the finale until CLAIM, and it changes nothing the
## pop-up counts or pays (the counted pieces are what they were). The white Gila's chest still has its three paintings.

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


func test_the_party_is_drawn_under_what_reads_and_follows_the_bonus() -> void:
	var g := await _game()
	var slow := BossChest.make_pack("gila_grande", 503.0, 1234.5, 400.0, 60.0, BossChest.DEFAULTS, 1)
	g.open_boss_chest(g.player.global_position + Vector3(1, 0, 0), "gila_grande", slow)
	await _frames(1)
	var bs = g.boss_chest_screen
	var party: Control = bs.get("_party")
	assert_object(party).is_not_null()
	# under the title, the meter, the banner, the counters and CLAIM's row
	for name: String in ["_meter", "_banner", "_counters"]:
		assert_int(party.get_index()).override_failure_message(name).is_less((bs.get(name) as Control).get_index())
	assert_int(party.get_index()).is_less(bs.header.get_index())
	assert_int(party.get_index()).is_less(bs.buttons.get_index())
	var fountain: Array = bs.get("_fountain")
	var n_slow := fountain.size()
	assert_int(n_slow).is_equal(BossChestScreen.FOUNTAIN_N + BossChestScreen.FOUNTAIN_LOOP)
	assert_int((bs.get("_drift") as Array).size()).is_equal(BossChestScreen.DRIFT_N)
	assert_int((bs.get("_twinkles") as Array).size()).is_equal(BossChestScreen.TWINKLE_N)
	# a fast kill: the whole bonus, the whole extra fountain (the screen opened again on the fast pack)
	var fast := BossChest.make_pack("gila_grande", 503.0, 1234.5, 10.0, 60.0, BossChest.DEFAULTS, 1)
	bs.open("gila_grande", BossChest.net(fast, 1.0, 1.0))
	assert_int((bs.get("_fountain") as Array).size()).is_equal(n_slow + BossChestScreen.FOUNTAIN_BONUS)
	bs.claim()


func test_the_party_counts_nothing_and_keeps_going_until_claim() -> void:
	var g := await _game()
	var pack := BossChest.make_pack("brander", 900.0, 2000.0, 90.0, 60.0, BossChest.DEFAULTS, 2)
	g.open_boss_chest(g.player.global_position + Vector3(1, 0, 0), "brander", pack)
	await _frames(1)
	var bs = g.boss_chest_screen
	bs.set_process(false)
	var total: Vector2i = bs.pieces()
	# the counted pieces: one coin per UI_GOLD gold and one gem per UI_XP XP, as in pass 118
	var nc := clampi(int(round(float(bs.gold_total) / BossChestScreen.UI_GOLD)), mini(BossChestScreen.UI_MIN, int(bs.gold_total)), BossChestScreen.UI_MAX)
	var ng := clampi(int(round(float(bs.xp_total) / BossChestScreen.UI_XP)), BossChestScreen.UI_MIN, BossChestScreen.UI_MAX)
	assert_int(total.x).is_equal(nc + ng)
	# long after the finale, waiting for CLAIM: the loop's fountain and the drift are still in the air
	bs.finish_now()
	var end_t: float = float(bs.get("_end_t"))
	bs.seek(end_t + 20.0)
	var live := 0
	for f: Array in bs.get("_fountain"):
		if float(f[11]) > 0.0:
			var age := fmod(float(bs.get("_t")) - float(f[0]), float(f[11]))
			if age >= 0.0 and age <= float(f[10]):
				live += 1
	assert_int(live).is_greater(0)
	assert_array(bs.counters()).is_equal([int(bs.gold_total), int(round(float(bs.xp_total)))])
	var g0: int = Run.run_gold
	bs.claim()
	assert_int(Run.run_gold - g0).is_equal(int(bs.gold_total))


func test_the_white_gila_chest_has_its_three_paintings_and_its_model() -> void:
	assert_int(BossChest.paintings("gila_grande").size()).is_equal(3)
	var look := BossChest.look("gila_grande")
	assert_bool(ResourceLoader.exists(str(look.get("model", "")))).is_true()
