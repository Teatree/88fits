## Pass 137, lane RESULTS (Garry: "Result Screen Coin accumulation: the number going up looks jerky ... Make it ramp up
## linearly with higher intensity the higher the amount of Coins is; very animated, the number font increasing in size as
## it gets bigger and then snapping to the original size" and "The addition of the coins from the Wanted poster should be
## very visual as well"): the banked gold counts up in a straight line (equal time, equal coins), longer for more coins
## inside GOLD_MIN_TIME .. GOLD_MAX_TIME, swelling as it climbs and snapping back at the top, ending exactly at what was
## banked; a tap lands it at once; a paid bounty's coins pour into the count, each arrival adding its share, the shares
## summing to the reward exactly.
extends GdUnitTestSuite

const RESULTS := preload("res://ui/ResultsScreen.gd")
const STEP := 0.04

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"inset": Settings.top_inset}
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._migrate_seen()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Settings.top_inset = int(_keep["inset"])
	Save.data = Save._default()
	Save._dirty = false
	Run.end()


## A plain run on the Results: `banked` coins came home onto a purse of 100, with the bounty `rec` ({} for none).
func _screen(banked: int, rec: Dictionary = {}) -> Control:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.end()
	(Save.data["hints_seen"] as Array).append("results")
	Run.damage_by_weapon = {"gravity_gun": 5200.0, "molotov": 900.0}
	Run.last_result = {"gold_before": 100, "banked": banked, "lost": 0, "strongbox": 0, "prev_best": {}, "bounty": rec}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


func _shown(r: Control) -> int:
	return int((r._count as WText).text.trim_prefix("+").replace(",", ""))


## Steps the show by STEP until its part is not `part` any more (bounded), calling `each` after every step.
func _through(r: Control, part: String, each: Callable = Callable()) -> void:
	var guard := 0
	while (r.part_name() == part or r._pt < 0.0) and guard < 3000:
		r._process(STEP)
		if each.is_valid():
			each.call()
		guard += 1


# ---------------------------------------------------------------- 1. the line and its length

func test_the_count_is_a_straight_line_from_nothing_to_the_banked_amount() -> void:
	for n in [7, 150, 2345, 99999]:
		var prev := 0
		var steps: Array = []
		for k in 21:
			var v: int = RESULTS.gold_at(n, float(k) / 20.0)
			assert_int(v).override_failure_message("n %d at %d/20" % [n, k]).is_equal(int(floor(float(n) * float(k) / 20.0 + 0.000001)))
			if k > 0:
				steps.append(v - prev)
			prev = v
		assert_int(prev).is_equal(n)
		# equal steps of time give equal steps of coins (a coin's rounding apart)
		var lo: int = steps.min()
		var hi: int = steps.max()
		assert_int(hi - lo).override_failure_message("n %d steps %s" % [n, str(steps)]).is_less_equal(1)
	assert_int(RESULTS.gold_at(0, 0.5)).is_equal(0)
	assert_int(RESULTS.gold_at(640, 1.0)).is_equal(640)


func test_a_bigger_purse_counts_longer_inside_the_named_bounds() -> void:
	assert_float(RESULTS.gold_time(0)).is_equal(RESULTS.GOLD_MIN_TIME)
	assert_float(RESULTS.gold_time(10)).is_equal(RESULTS.GOLD_MIN_TIME)
	assert_float(RESULTS.gold_time(100)).is_equal_approx(1.39, 0.02)
	assert_float(RESULTS.gold_time(1000)).is_equal_approx(1.99, 0.02)
	assert_float(RESULTS.gold_time(5000)).is_equal(RESULTS.GOLD_MAX_TIME)
	assert_float(RESULTS.gold_time(10000000)).is_equal(RESULTS.GOLD_MAX_TIME)
	var last := 0.0
	for n in [0, 11, 40, 100, 300, 1000, 2500, 4999, 5000, 20000]:
		var t: float = RESULTS.gold_time(n)
		assert_float(t).is_between(0.8, 2.5)
		assert_float(t).override_failure_message("gold_time(%d)" % n).is_greater_equal(last)
		last = t
	# the swell grows with the climb and with the amount, from its size to its named top
	assert_float(RESULTS.gold_swell(640, 0.0)).is_equal(1.0)
	assert_float(RESULTS.gold_swell(0, 1.0)).is_equal(1.0)
	assert_float(RESULTS.gold_swell(20, 1.0)).is_between(RESULTS.GOLD_SWELL_LOW, RESULTS.GOLD_SWELL_HIGH)
	assert_float(RESULTS.gold_swell(9000, 1.0)).is_equal_approx(RESULTS.GOLD_SWELL_HIGH, 0.0001)
	assert_float(RESULTS.gold_swell(640, 0.5)).is_less(RESULTS.gold_swell(640, 0.9))
	# the ticks come faster as it climbs and for a bigger purse
	assert_float(RESULTS.gold_tick_gap(50, 0.0)).is_greater(RESULTS.gold_tick_gap(50, 0.9))
	assert_float(RESULTS.gold_tick_gap(50, 0.2)).is_greater(RESULTS.gold_tick_gap(5000, 0.2))
	# the show's gold part lasts its purse's time
	var r := _screen(640)
	await get_tree().process_frame
	assert_str(str(r._parts[0]["name"])).is_equal("gold")
	assert_float(float(r._parts[0]["dur"])).is_equal_approx(RESULTS.gold_time(640), 0.0001)


# ---------------------------------------------------------------- 2. the count in the show

func test_the_live_count_follows_the_line_swells_and_ends_exactly_at_the_banked_amount() -> void:
	var r := _screen(640)
	await get_tree().process_frame
	var seen: Array = []
	var top := [1.0]
	_through(r, "gold", func():
		if r.part_name() == "gold":
			var v := _shown(r)
			# on the line at the part's clock (rounded down: never ahead of it)
			assert_int(v).is_equal(RESULTS.gold_at(640, r.part_frac()))
			seen.append(v)
			top[0] = maxf(top[0], (r._count as Control).scale.x))
	assert_int(seen.size()).is_greater(10)
	for k in range(1, seen.size()):
		assert_int(int(seen[k])).is_greater_equal(int(seen[k - 1]))
	# it swelled as it climbed (a nudge on top of the swell), then landed exactly
	assert_float(float(top[0])).is_greater(1.25)
	assert_str((r._count as WText).text).is_equal("+640")
	assert_bool(r._snapped).is_true()
	assert_object(r.find_child("CoinSpray", true, false)).is_not_null()
	# the snap takes it back to its size and its gold
	await get_tree().create_timer(0.8).timeout
	assert_float((r._count as Control).scale.x).is_equal_approx(1.0, 0.001)
	assert_bool((r._count as WText).color.is_equal_approx(r._count_base)).is_true()
	assert_str((r._count as WText).text).is_equal("+640")


func test_a_tap_lands_the_count_at_once_at_its_size() -> void:
	var r := _screen(2345)
	await get_tree().process_frame
	r._process(RESULTS.LEAD_IN + 0.6)
	assert_str(r.part_name()).is_equal("gold")
	assert_int(_shown(r)).is_between(1, 2344)
	assert_float((r._count as Control).scale.x).is_greater(1.0)
	r.tap()
	r.tap()
	assert_int(r.sequence()).is_greater_equal(2)
	assert_str((r._count as WText).text).is_equal("+" + W.num(2345))
	assert_float((r._count as Control).scale.x).is_equal(1.0)
	assert_bool((r._count as Control).position.is_zero_approx()).is_true()
	assert_bool((r._count as WText).color.is_equal_approx(r._count_base)).is_true()


func test_an_empty_purse_counts_briefly_and_quietly() -> void:
	var r := _screen(0)
	await get_tree().process_frame
	assert_float(float(r._parts[0]["dur"])).is_equal(RESULTS.GOLD_MIN_TIME)
	_through(r, "gold")
	assert_str((r._count as WText).text).is_equal("+0")
	assert_bool(r._snapped).is_false()
	assert_object(r.find_child("CoinSpray", true, false)).is_null()
	assert_float((r._count as Control).scale.x).is_equal(1.0)


# ---------------------------------------------------------------- 3. the bounty's coins

func test_the_bounty_shares_sum_to_the_reward_exactly() -> void:
	for paid in [1, 7, 240, 1001, 99999]:
		var last := 0
		for k in RESULTS.BOUNTY_FLY + 1:
			var got: int = RESULTS.bounty_got(paid, RESULTS.BOUNTY_FLY, k)
			assert_int(got).is_greater_equal(last)
			last = got
		assert_int(RESULTS.bounty_got(paid, RESULTS.BOUNTY_FLY, 0)).is_equal(0)
		assert_int(last).is_equal(paid)
	# the coins leave one after another and the last is in before the part ends (its snap plays inside it)
	var n := RESULTS.BOUNTY_FLY
	assert_int(RESULTS.bounty_landed(n, 0.0)).is_equal(0)
	assert_int(RESULTS.bounty_landed(n, RESULTS.BOUNTY_FLIGHT * 0.99)).is_equal(0)
	assert_int(RESULTS.bounty_landed(n, RESULTS.BOUNTY_POUR + RESULTS.BOUNTY_FLIGHT - 0.01)).is_equal(n - 1)
	assert_int(RESULTS.bounty_landed(n, RESULTS.BOUNTY_POUR + RESULTS.BOUNTY_FLIGHT)).is_equal(n)
	assert_float(RESULTS.BOUNTY_POUR + RESULTS.BOUNTY_FLIGHT).is_less(0.9)


func test_the_bounty_pours_exactly_its_amount_into_the_count() -> void:
	var r := _screen(50, {"name": "T", "text": "t", "have": 60, "need": 60, "done": true, "paid": 240, "reward": 240})
	await get_tree().process_frame
	var names: Array = r._parts.map(func(p): return str(p["name"]))
	assert_array(names.slice(0, 4)).is_equal(["gold", "bounty", "bounty_pay", "pop"])
	_through(r, "gold")
	_through(r, "bounty")
	assert_str(r.part_name()).is_equal("bounty_pay")
	assert_str((r._count as WText).text).is_equal("+50")
	var seen: Array = []
	var flew := [false]
	var top := [1.0]
	_through(r, "bounty_pay", func():
		if r.part_name() == "bounty_pay":
			seen.append(_shown(r))
			top[0] = maxf(top[0], (r._count as Control).scale.x)
			if r._pour != null and not (r._pour.flying as Array).is_empty():
				flew[0] = true)
	assert_bool(bool(flew[0])).is_true()
	for k in seen.size():
		assert_int(int(seen[k])).is_between(50, 290)
		if k > 0:
			assert_int(int(seen[k])).is_greater_equal(int(seen[k - 1]))
	# each arrival adds a share: the count passes through steps of about a tenth of the reward
	var distinct := {}
	for v in seen:
		distinct[v] = true
	assert_int(distinct.size()).is_greater_equal(RESULTS.BOUNTY_FLY - 1)
	assert_float(float(top[0])).is_greater(1.2)
	assert_str((r._count as WText).text).is_equal("+290")
	assert_str(r._after_line.text).is_equal("%s → %s" % [W.num(100), W.num(390)])
	assert_object(r._pour).is_null()
	assert_bool(bool(r._bounty.get("snapped", false))).is_true()
	await get_tree().create_timer(1.0).timeout
	assert_float((r._count as Control).scale.x).is_equal_approx(1.0, 0.001)
	assert_float(r._after_line.scale.x).is_equal_approx(1.0, 0.001)
	# its gold flash back to the line's own colour
	assert_bool(r._after_line.color.is_equal_approx(r._line_base)).is_true()
	# the reward's own number stays as what it paid
	assert_str((r.bounty_view()["coin_num"] as WText).text).is_equal("+240")


func test_a_skipped_bounty_lands_its_amount_at_once() -> void:
	var r := _screen(50, {"name": "T", "text": "t", "have": 60, "need": 60, "done": true, "paid": 240, "reward": 240})
	await get_tree().process_frame
	_through(r, "gold")
	_through(r, "bounty")
	r._process(RESULTS.BOUNTY_PAY_TIME * 0.4)
	assert_str(r.part_name()).is_equal("bounty_pay")
	r.tap()
	r.tap()
	assert_str((r._count as WText).text).is_equal("+290")
	assert_object(r._pour).is_null()
	assert_float((r._count as Control).scale.x).is_equal(1.0)
	assert_float(r._after_line.scale.x).is_equal(1.0)
	assert_str(r._after_line.text).contains("390")
