extends GdUnitTestSuite
## Pass 140 (lane ECON; Garry on the progression plan: "Yes I am accepting all of the multipliers", "Make it so that players
## are forced to a new save with this particular build", "x25 is a cheat, we don't balance anything around this"):
## BALANCING 81.ECON. The stage's coin factor as a fraction carried from coin to coin (StagePay), the boss purse by stage,
## Wages a stage-minute survived, the posters' stage_mult and counts, and a save from before the epoch set aside.

const DIR := "user://test_saves/p140_econ"
## today's coin factor (the round of reward_mult) times the plan's x1, x1.33, x2, x2.85
const COIN := [1.0, 2.66, 6.0, 8.55]
const PURSE := [325, 750, 1350, 1700]
const WAGE := [30.0, 80.0, 150.0, 240.0]
const COUNT := [1.0, 1.6, 2.2, 3.0]

var _keep := {}


func before_test() -> void:
	_keep = {"x25": Settings.coins_x25, "dir": Save.dir, "check": Save.epoch_check}
	Settings.coins_x25 = false
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	StagePay.reset()


func after_test() -> void:
	Settings.coins_x25 = bool(_keep["x25"])
	Save.epoch_check = bool(_keep["check"])
	Save.dir = str(_keep["dir"])
	Save.data = Save._default()
	Save._dirty = false
	Save.set_aside = ""
	_clear()
	if RunAnalytics.I and not is_instance_valid(RunAnalytics.I):
		RunAnalytics.I = null
	Run.arena = false
	Run.end()
	StagePay.reset()


func _run(stage: int) -> WaveTimeline:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	Run.start_stage(stage)
	return Run.map.timeline


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _write(p: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


func _on_disk(p: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- 1. coins on the sand

func test_the_map_pays_the_plans_coin_factors() -> void:
	var tl := _run(0)
	for k in 4:
		assert_float(tl.stage_coin_mult(k)).override_failure_message("stage %d" % k).is_equal_approx(float(COIN[k]), 0.0001)
		# x1, x1.33, x2, x2.85 of what a coin paid before (the round of reward_mult, at least 1)
		var before := float(maxi(int(round(tl.stage_reward_mult(k))), 1))
		assert_float(tl.stage_coin_mult(k) / before).is_equal_approx(float([1.0, 1.33, 2.0, 2.85][k]), 0.0001)
	# the items keep reading reward_mult (Personal Storm, the Iron Horse): untouched
	assert_float(tl.stage_reward_mult(2)).is_equal(2.75)
	assert_float(tl.stage_reward_mult(3)).is_equal(3.34)
	# a stage without coin_mult pays the old round
	var e: Dictionary = tl.stage_list[1]
	var had = e["coin_mult"]
	e.erase("coin_mult")
	assert_float(tl.stage_coin_mult(1)).is_equal(float(maxi(int(round(tl.stage_reward_mult(1))), 1)))
	e["coin_mult"] = had


func test_a_fractional_factor_pays_fairly_on_average() -> void:
	_run(1)
	assert_float(StagePay.coin_mult()).is_equal_approx(2.66, 0.0001)
	StagePay.reset()
	var total := 0
	for i in 1000:
		var p := PickupManager.coin_pay(1.0)
		assert_bool(p == 2 or p == 3).override_failure_message("coin %d paid %d" % [i, p]).is_true()
		total += p
	assert_int(total).is_between(2659, 2660)


func test_the_same_coins_pay_the_same_from_a_fresh_game() -> void:
	_run(3)
	var totals: Array = []
	var want := 0.0
	for pass_i in 2:
		StagePay.reset()
		var rng := RandomNumberGenerator.new()
		rng.seed = 140
		var t := 0
		want = 0.0
		for i in 400:
			var v := float(1 + rng.randi() % 5)
			want += v * 8.55
			t += PickupManager.coin_pay(v)
		totals.append(t)
	assert_int(int(totals[0])).is_equal(int(totals[1]))
	assert_float(float(totals[0])).is_between(want - 1.0, want)
	# a whole factor pays exactly as before
	_run(2)
	StagePay.reset()
	assert_int(PickupManager.coin_pay(3.0)).is_equal(18)
	_run(0)
	assert_int(PickupManager.coin_pay(4.0)).is_equal(4)


func test_coins_x25_rides_on_top() -> void:
	_run(2)
	Settings.coins_x25 = true
	assert_int(PickupManager.coin_pay(1.0)).is_equal(6 * PickupManager.COIN_X25)
	Settings.coins_x25 = false
	assert_int(PickupManager.coin_pay(1.0)).is_equal(6)


func test_a_new_game_starts_with_no_carried_fraction() -> void:
	StagePay.carry = 0.7
	StagePay.reset()
	assert_float(StagePay.carry).is_equal(0.0)
	var src := FileAccess.get_file_as_string("res://core/systems/PickupManager.gd")
	var ready := src.substr(src.find("func _ready() -> void:"), 200)
	assert_str(ready).contains("StagePay.reset()")
	assert_str(src).contains("v * StagePay.coin_mult()")
	assert_str(src).contains("StagePay.take(float(int(v)), StagePay.coin_mult()) * coins_x()")


# ---------------------------------------------------------------- 2. boss purses

func test_the_boss_purse_by_stage() -> void:
	var tl := _run(0)
	for k in 4:
		assert_int(Game.boss_purse(k)).override_failure_message("stage %d" % k).is_equal(int(PURSE[k]))
		assert_int(Game.boss_purse(k)).is_equal(int(round(Game.boss_purse_line(k) * float([1.0, 1.5, 2.0, 2.0][k]))))
		assert_int(Game.boss_purse(k, tl)).is_equal(int(PURSE[k]))
	# the bosses' own drops are what they were
	assert_int(int(Registry.enemy("tumbleweed_king").drops.get("coins", 0))).is_equal(15)
	assert_int(int(Registry.enemy("gila_grande").drops.get("coins", 0))).is_equal(37)
	# a stage without boss_purse pays the line
	var e: Dictionary = tl.stage_list[2]
	var had = e["boss_purse"]
	e.erase("boss_purse")
	assert_int(Game.boss_purse(2)).is_equal(Game.boss_purse_line(2))
	e["boss_purse"] = had


func test_the_boss_chest_sample_reads_the_stage() -> void:
	var tl := _run(0)
	var def: EnemyDef = Registry.enemy("gila_grande")
	var pack := BossChest.sample_pack("gila_grande", 1, 30.0, tl)
	var want := 750.0 + float(def.drops.get("coins", Game.BOSS_COINS)) * 5.0 * 2.66 + 2.0 * PickupManager.BIG_COIN_MULT * 2.66 * float(def.drops.get("gold", 0.0))
	assert_float(float(pack["gold_base"])).is_equal_approx(want, 0.01)


# ---------------------------------------------------------------- 3. Wages

func test_wages_pay_the_stage_clock_survived() -> void:
	for k in 4:
		var tl := _run(k)
		assert_float(StagePay.wage_rate()).is_equal(float(WAGE[k]))
		Run.elapsed = tl.stage_start(k) + 150.0
		assert_int(StagePay.wages_due()).override_failure_message("stage %d at 2:30" % k).is_equal(int(round(float(WAGE[k]) * 2.5)))
		# the boss came: the clock stands at the stage's length
		Run.elapsed = tl.stage_end(k)
		var whole := int(round(float(WAGE[k]) * tl.stage_len(k) / 60.0))
		assert_int(StagePay.wages_due()).is_equal(whole)
		# Endless adds nothing, nor a clock a tool pushed past the end
		Run.endless = true
		Run.held_time = 400.0
		Run.elapsed = tl.stage_end(k) + 300.0
		assert_int(StagePay.wages_due()).override_failure_message("stage %d in Endless" % k).is_equal(whole)
		Run.end()
	# Sundown 7:10 = 215, Nightfall 10:00 = 800, the Dust Bowl 13:00 = 1950, Blood Moon 16:00 = 3840
	var tl0 := _run(0)
	Run.elapsed = tl0.stage_end(0)
	assert_int(StagePay.wages_due()).is_equal(215)
	Run.arena = true
	assert_int(StagePay.wages_due()).is_equal(0)


func test_wages_bank_with_the_purse_at_every_end() -> void:
	for end in ["death", "extract"]:
		Save.data = Save._default()
		var tl := _run(1)
		Run.elapsed = tl.stage_start(1) + 120.0
		Run.add_gold(100, "coins")
		Run.died = end == "death"
		Run.extracted = end == "extract"
		var before := Save.gold()
		var heard := [0]
		var cb := func(_n: int) -> void: heard[0] += 1
		Run.gold_gained.connect(cb)
		Settings.coins_x25 = true
		var banked := Game.bank_run_end("red_canyon")
		Settings.coins_x25 = false
		Run.gold_gained.disconnect(cb)
		# 2:00 of Nightfall at 80 = 160, never x Coins x25, never heard as gold gained (posters, Gold Rush)
		assert_int(banked).override_failure_message(end).is_equal(260)
		assert_int(Save.gold()).is_equal(before + 260)
		assert_int(int(Run.last_result["wages"])).is_equal(160)
		assert_float(float(Run.last_result["wage_seconds"])).is_equal_approx(120.0, 0.001)
		assert_int(heard[0]).is_equal(0)
		Run.end()


func test_wages_are_a_gold_source_of_their_own() -> void:
	assert_bool(RunAnalytics.GOLD_SOURCES.has("wages")).is_true()
	var tl := _run(0)
	Run.elapsed = tl.stage_start(0) + 60.0
	var ra := RunAnalytics.new()
	var was = RunAnalytics.I
	RunAnalytics.I = ra
	var g0 := Run.run_gold
	assert_int(StagePay.pay_wages()).is_equal(30)
	RunAnalytics.I = was
	assert_int(Run.run_gold - g0).is_equal(30)
	assert_int(int(ra.gold_in_total.get("wages", 0))).is_equal(30)
	assert_int(ra.gold_greed).is_equal(0)
	ra.free()
	# paid straight into the purse: no greed (add_gold), no Coins x25
	var src := FileAccess.get_file_as_string("res://core/systems/StagePay.gd")
	var body := src.substr(src.find("static func pay_wages()"))
	assert_int(body.find("add_gold")).is_equal(-1)
	assert_int(body.find("coins_x")).is_equal(-1)


func test_the_results_say_the_wages() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 100, "banked": 330, "lost": 0, "strongbox": 0, "prev_best": {}, "wages": 300, "wage_seconds": 600.0}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	await get_tree().process_frame
	var line := r.find_child("WagesLine", true, false) as WText
	assert_object(line).is_not_null()
	assert_str(line.text).is_equal("Wages for 10:00: +300")
	r.visible = false
	# none without wages
	Run.last_result = {"gold_before": 100, "banked": 30, "lost": 0, "strongbox": 0, "prev_best": {}}
	var r2: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r2)
	await get_tree().process_frame
	assert_object(r2.find_child("WagesLine", true, false)).is_null()
	r2.visible = false


# ---------------------------------------------------------------- 4. posters

func test_posters_pay_and_ask_more_by_stage() -> void:
	var cfg := WantedBoard.config()
	var sm: Array = (cfg["reward"] as Dictionary)["stage_mult"]
	assert_array(sm).is_equal([1.0, 3.0, 7.0, 14.0])
	for d in [1.0, 2.5, 4.0]:
		var r0 := WantedBoard.reward_for(cfg, d, 0, 0)
		for k in 4:
			assert_float(float(WantedBoard.reward_for(cfg, d, 0, k))).is_between(r0 * float(sm[k]) - 5.0 * float(sm[k]), r0 * float(sm[k]) + 5.0 * float(sm[k]))
	var scaled := ["kill_enemy", "kill_weapon", "kill_specials", "kill_elites", "kill_total", "collect_coins", "damage_weapon",
		"heal_item", "heal_source", "barrels", "element_damage"]
	for tc: Dictionary in cfg["tasks"]:
		var type := str(tc["type"])
		if not scaled.has(type):
			continue
		var ns: Array = tc["n"]
		assert_int(ns.size()).is_equal(4)
		var step := float(tc.get("step", 1))
		for k in range(1, 4):
			var f := float(COUNT[k]) * (float(COIN[k]) if type == "collect_coins" else 1.0)
			for j in 2:
				var want := WantedBoard.snap_n(float(ns[0][j]) * f, step)
				assert_int(int(ns[k][j])).override_failure_message("%s stage %d end %d" % [type, k, j]).is_equal(want)
	# boss_fast keeps its seconds
	assert_str(JSON.stringify(WantedBoard.task_cfg(cfg, "boss_fast")["n"])).is_equal(JSON.stringify([[45.0, 75.0], [60.0, 100.0], [70.0, 115.0], [80.0, 130.0]]))


# ---------------------------------------------------------------- 5. a new save for this build

func test_the_runner_holds_no_save_to_the_epoch_unless_asked() -> void:
	assert_bool(bool(_keep["check"])).is_false()
	assert_int(int(Save._default()["epoch"])).is_equal(Save.EPOCH)
	assert_int(Save.EPOCH).is_equal(140)


func test_an_old_save_is_set_aside_and_a_new_one_starts() -> void:
	Save.flush()
	Save.dir = DIR
	_clear()
	var settings := Settings.to_dict()
	_write(Save.path(), {"version": 5, "gold": 9999, "quests_done": ["unlock_x"], "trail": {"bought": ["n1"], "spent": 40, "had": []},
		"install_id": "id-140", "player_name": "Dusty Coyote 41", "consent": "yes", "survey": {"counted": 7}, "settings": settings,
		"runs_started": 12, "heroes_owned": ["ironwood"]})
	_write(Save.bak_path(), {"version": 5, "gold": 9000})
	Save.epoch_check = true
	Save.load_save()
	# the old files aside, whole
	assert_str(Save.set_aside).is_equal("save_before_p140.json")
	assert_int(int(_on_disk(DIR.path_join("save_before_p140.json"))["gold"])).is_equal(9999)
	assert_int(int(_on_disk(DIR.path_join("save_before_p140.json.bak"))["gold"])).is_equal(9000)
	assert_bool(FileAccess.file_exists(Save.path())).is_false()
	# a new save: START_GOLD, nothing done, nothing bought, the Trail's first steps to come
	assert_int(Save.gold()).is_equal(Save.START_GOLD)
	assert_array(Save.data["quests_done"]).is_empty()
	assert_array(Save.trail_bought()).is_empty()
	assert_int(int(Save.data["runs_started"])).is_equal(0)
	assert_bool(Save.trail_open()).is_false()
	assert_int(int(Save.data["epoch"])).is_equal(Save.EPOCH)
	# the player kept: who they are to PostHog, the play-data answer, the survey record and the settings
	assert_str(Save.install_id()).is_equal("id-140")
	assert_str(Save.player_name()).is_equal("Dusty Coyote 41")
	assert_str(Save.consent()).is_equal("yes")
	assert_int(int(Save.survey_state()["counted"])).is_equal(7)
	assert_dict(Save.data["settings"]).is_equal(JSON.parse_string(JSON.stringify(settings)))
	# written at once with the epoch; the next boot reads it as it is
	assert_bool(Save._dirty).is_true()
	Save.save_now()
	assert_int(int(_on_disk(Save.path())["epoch"])).is_equal(Save.EPOCH)
	Save.load_save()
	assert_str(Save.set_aside).is_equal("")
	assert_int(Save.gold()).is_equal(Save.START_GOLD)
	assert_str(Save.player_name()).is_equal("Dusty Coyote 41")


func test_a_second_old_save_never_overwrites_the_first() -> void:
	Save.flush()
	Save.dir = DIR
	_clear()
	_write(DIR.path_join("save_before_p140.json"), {"version": 5, "gold": 1})
	_write(Save.path(), {"version": 5, "gold": 2})
	Save.epoch_check = true
	Save.load_save()
	assert_str(Save.set_aside).is_equal("save_before_p140-2.json")
	assert_int(int(_on_disk(DIR.path_join("save_before_p140.json"))["gold"])).is_equal(1)
	assert_int(int(_on_disk(DIR.path_join("save_before_p140-2.json"))["gold"])).is_equal(2)
	# the same old save once more (a tool put it back) lands on its own copy, no third file
	var same := FileAccess.get_file_as_string(DIR.path_join("save_before_p140-2.json"))
	var f := FileAccess.open(Save.path(), FileAccess.WRITE)
	f.store_string(same)
	f.close()
	Save.load_save()
	assert_str(Save.set_aside).is_equal("save_before_p140-2.json")
	assert_bool(FileAccess.file_exists(DIR.path_join("save_before_p140-3.json"))).is_false()


func test_a_save_of_this_epoch_loads_as_it_is_and_a_wipe_keeps_the_epoch() -> void:
	Save.flush()
	Save.dir = DIR
	_clear()
	_write(Save.path(), {"version": Save.VERSION, "epoch": Save.EPOCH, "gold": 777, "install_id": "id-x"})
	Save.epoch_check = true
	Save.load_save()
	assert_str(Save.set_aside).is_equal("")
	assert_int(Save.gold()).is_equal(777)
	assert_str(Save.loaded_from).is_equal("save")
	# the developer menu's reset is a new save of this epoch
	Save.wipe()
	assert_int(int(Save.data["epoch"])).is_equal(Save.EPOCH)
	assert_int(int(_on_disk(Save.path())["epoch"])).is_equal(Save.EPOCH)
