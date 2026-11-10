extends GdUnitTestSuite
## Pass 139 (lead; Garry: "Make it so the x25 coins setting actually increases the rewards from posters and the boss reward
## as well. It should, of course, also switch on and off with the toggle"): BALANCING 80.COINS.

var _x25 := true


func before_test() -> void:
	_x25 = Settings.coins_x25


func after_test() -> void:
	Settings.coins_x25 = _x25
	WantedRun.current = null
	Run.end()


func test_the_factor_follows_the_switch() -> void:
	Settings.coins_x25 = true
	assert_int(PickupManager.coins_x()).is_equal(PickupManager.COIN_X25)
	Settings.coins_x25 = false
	assert_int(PickupManager.coins_x()).is_equal(1)


func test_a_poster_shows_and_pays_x25_while_on() -> void:
	var c := {"type": "kill_total", "n": 10, "target": "", "reward": 200, "d": 2.0, "name": "N", "text": "t", "still": {}}
	Settings.coins_x25 = true
	assert_int(WantedBoard.reward_of(c)).is_equal(5000)
	var p: WPoster = auto_free(WPoster.make(c))
	add_child(p)
	await get_tree().process_frame
	assert_str(str((p.find_child("Amount", true, false) as WText).text)).is_equal(W.num(5000))
	Settings.coins_x25 = false
	assert_int(WantedBoard.reward_of(c)).is_equal(200)
	# the contract itself keeps the plain reward (the switch is read when paying or showing)
	assert_int(int(c["reward"])).is_equal(200)


func test_the_run_pays_the_poster_through_reward_of() -> void:
	var src := FileAccess.get_file_as_string("res://core/systems/WantedRun.gd")
	assert_str(src).contains("paid = WantedBoard.reward_of(contract)")
	assert_str(src).contains("W.num(WantedBoard.reward_of(contract))")
	assert_str(FileAccess.get_file_as_string("res://ui/ResultsScreen.gd")).contains("WantedBoard.reward_of(rec)")


func test_a_boss_chest_carries_x25_while_on() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Settings.coins_x25 = false
	var plain := BossChest.sample_pack("tumbleweed_king", 0, 45.0)
	Settings.coins_x25 = true
	var big := BossChest.sample_pack("tumbleweed_king", 0, 45.0)
	assert_float(float(big["gold_base"])).is_equal_approx(float(plain["gold_base"]) * 25.0, 0.01)
	assert_float(float(big["xp"])).is_equal_approx(float(plain["xp"]), 0.001)
	var g := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(g).contains("var gold := float(c.get(\"gold\", 0.0)) * float(PickupManager.coins_x())")
	assert_str(g).contains("chest_gold *= PickupManager.coins_x()")
