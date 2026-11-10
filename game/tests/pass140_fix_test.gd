## Pass 140 (lane FIX): a replay keeps step past the run's end. The Wages (StagePay.pay_wages, BALANCING 81.ECON) are paid
## into the purse inside end_run, before RunReplay.finish takes the run's last check; a replay whose end is not one of the
## run's own events never runs end_run. So the checks compare the purse the play earned: Run.run_gold less StagePay.paid.
extends GdUnitTestSuite

var _x25 := false


func before_test() -> void:
	_x25 = Settings.coins_x25
	Settings.coins_x25 = false
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	StagePay.reset()


func after_test() -> void:
	Settings.coins_x25 = _x25
	Run.end()
	StagePay.reset()
	Save.data = Save._default()
	Save._dirty = false


func _run(stage: int) -> WaveTimeline:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	Run.start_stage(stage)
	return Run.map.timeline


func test_the_wages_paid_are_remembered_until_a_new_game() -> void:
	var tl := _run(0)
	Run.elapsed = tl.stage_start(0) + 120.0
	var before := Run.run_gold
	var w := StagePay.pay_wages()
	assert_int(w).is_greater(0)
	assert_int(StagePay.paid).is_equal(w)
	assert_int(Run.run_gold).is_equal(before + w)
	# a new game's PickupManager resets it with the coins' carried fraction
	StagePay.reset()
	assert_int(StagePay.paid).is_equal(0)


func test_a_replay_check_counts_the_purse_without_the_wages() -> void:
	_run(0)
	Run.run_gold = 40
	var rr := RunReplay.new()
	var c0 := rr.check_values()
	# the run's end: Wages into the purse (the recording's last check sees this, a replay without end_run does not)
	Run.run_gold += 7
	StagePay.paid += 7
	var c1 := rr.check_values()
	assert_int(int(c1["gold"])).is_equal(40)
	assert_int(int(c0["gold"])).is_equal(40)
	assert_str(str(c1["h"])).is_equal(str(c0["h"]))
	# a coin picked up is still the play's: the check sees it
	Run.run_gold += 1
	assert_int(int(rr.check_values()["gold"])).is_equal(41)
	rr.free()
