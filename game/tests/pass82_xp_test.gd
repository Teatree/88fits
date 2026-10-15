extends GdUnitTestSuite

## Pass 82, lane XP (Garry: "EXP requirements ... Say I want to make the EXP requirements exponential instead of linear,
## it doesn't look like I can. I want that section to include types of EXP growth displayed in a dropdown"): the map's
## `xp_curve` picks a growth type (XpCurve: quadratic = today's, linear, exponential, power, table), each times the map's
## xp_need_mult; absent = today's curve to the bit; the guards; the reader; Run.xp_to_next and add_xp follow it; the
## arena keeps the plain curve; the run record names the curve played.

const TODAY_30 := 7322.5   # the XP from level 1 to 30 on 15 + 6L + 0.5L^2, before the multiplier


var _map: MapDef


func before_test() -> void:
	Save.data = Save._default()
	# a copy of Red Canyon, so a curve set here never reaches the Registry's map (other tests read Garry's numbers)
	_map = Registry.map("red_canyon").duplicate(true)
	_map.timeline = Registry.map("red_canyon").timeline.duplicate(true)
	Run.start(Registry.character("astro"), _map)
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Run.arena = false
	Run.end()


func _today(L: int) -> float:
	return 15.0 + 6.0 * L + 0.5 * L * L


# ---------------------------------------------------------------- absent = today's

func test_no_curve_is_todays_curve_to_the_bit() -> void:
	_map.timeline.xp_curve = {}
	var mult := Run.xp_need_mult()
	assert_float(mult).is_equal(maxf(_map.timeline.xp_need_mult, 0.01))
	for L in range(1, 101):
		assert_bool(XpCurve.need({}, L) == _today(L)).override_failure_message("level %d: %f, today's %f" % [L, XpCurve.need({}, L), _today(L)]).is_true()
		assert_bool(Run.xp_to_next(L) == _today(L) * mult).override_failure_message("Run.xp_to_next(%d)" % L).is_true()
	# an explicit quadratic without numbers, an unknown type and a stray key play today's too
	for c: Dictionary in [{"type": "quadratic"}, {"type": "cubic"}, {"type": "quadratic", "quadratic": {}}, {"linear": {"base": 1.0}}]:
		for L: int in [1, 7, 33, 100]:
			assert_bool(XpCurve.need(c, L) == _today(L)).override_failure_message("%s at %d" % [c, L]).is_true()
	assert_str(XpCurve.type_of({})).is_equal("quadratic")
	assert_str(XpCurve.type_of({"type": "cubic"})).is_equal("quadratic")
	# the current level when no level is named
	Run.level = 9
	assert_bool(Run.xp_to_next() == _today(9) * mult).is_true()


# ---------------------------------------------------------------- each type's numbers

func test_each_type_gives_its_formula() -> void:
	# quadratic with its own numbers
	assert_float(XpCurve.need({"type": "quadratic", "quadratic": {"base": 10, "linear": 0, "quad": 1}}, 3)).is_equal_approx(19.0, 1e-9)
	# linear: base + step x (L - 1)
	assert_float(XpCurve.need({"type": "linear"}, 1)).is_equal_approx(21.5, 1e-9)
	assert_float(XpCurve.need({"type": "linear"}, 10)).is_equal_approx(21.5 + 16.5 * 9.0, 1e-9)
	assert_float(XpCurve.need({"type": "linear", "linear": {"base": 10, "step": 5}}, 3)).is_equal_approx(20.0, 1e-9)
	# exponential: base x growth^(L - 1), the cap
	assert_float(XpCurve.need({"type": "exponential"}, 1)).is_equal_approx(40.0, 1e-9)
	assert_float(XpCurve.need({"type": "exponential"}, 3)).is_equal_approx(40.0 * 1.11 * 1.11, 1e-9)
	var capped := {"type": "exponential", "exponential": {"base": 10, "growth": 2, "cap": 50}}
	assert_float(XpCurve.need(capped, 3)).is_equal_approx(40.0, 1e-9)
	assert_float(XpCurve.need(capped, 4)).is_equal_approx(50.0, 1e-9)
	assert_float(XpCurve.need(capped, 40)).is_equal_approx(50.0, 1e-9)
	# power: base x L^power
	assert_float(XpCurve.need({"type": "power", "power": {"base": 2, "power": 2}}, 3)).is_equal_approx(18.0, 1e-9)
	assert_float(XpCurve.need({"type": "power"}, 1)).is_equal_approx(6.5, 1e-9)
	assert_float(XpCurve.need({"type": "power"}, 8)).is_equal_approx(6.5 * pow(8.0, 1.33), 1e-6)
	# table: linear between the listed levels, the first before, the last grown by after_growth past it
	var tbl := {"type": "table", "table": {"points": [[5, 40], [1, 10], [3, 30]], "after_growth": 0.1}}
	var want := {1: 10.0, 2: 20.0, 3: 30.0, 4: 35.0, 5: 40.0, 6: 44.0, 7: 48.4}
	for L: int in want:
		assert_float(XpCurve.need(tbl, L)).override_failure_message("table at %d" % L).is_equal_approx(float(want[L]), 1e-9)
	assert_float(XpCurve.need({"type": "table", "table": {"points": [[3, 30], [6, 60]]}}, 1)).is_equal_approx(30.0, 1e-9)
	# after_growth 0: the last amount repeats
	assert_float(XpCurve.need({"type": "table", "table": {"points": [[1, 10], [2, 12]], "after_growth": 0}}, 50)).is_equal_approx(12.0, 1e-9)
	# the default table is today's curve at its listed levels
	for L: int in [1, 5, 10, 20, 30, 40, 50, 60]:
		assert_float(XpCurve.need({"type": "table"}, L)).is_equal_approx(_today(L), 1e-9)


func test_every_default_lands_near_todays_total_by_level_30() -> void:
	assert_float(XpCurve.total({}, 30)).is_equal_approx(TODAY_30, 1e-6)
	for t: String in XpCurve.TYPES:
		var tot := XpCurve.total({"type": t}, 30)
		assert_float(tot / TODAY_30).override_failure_message("%s: %.0f XP by level 30, today's %.0f" % [t, tot, TODAY_30]).is_between(0.95, 1.05)


func test_the_guards() -> void:
	# a level never needs 0 or less (a zero would level forever), nor infinity
	assert_float(XpCurve.need({"type": "linear", "linear": {"base": 0, "step": 0}}, 5)).is_equal(XpCurve.MIN_NEED)
	assert_float(XpCurve.need({"type": "linear", "linear": {"base": 10, "step": -5}}, 9)).is_equal(XpCurve.MIN_NEED)
	assert_float(XpCurve.need({"type": "exponential", "exponential": {"base": 1e300, "growth": 1e10}}, 50)).is_equal(XpCurve.MAX_NEED)
	assert_float(XpCurve.need({"type": "power", "power": {"base": -3}}, 4)).is_equal(XpCurve.MIN_NEED)
	# a number the block leaves out or holds as something else is the default
	assert_float(XpCurve.need({"type": "exponential", "exponential": {"growth": "fast"}}, 2)).is_equal_approx(40.0 * 1.11, 1e-9)
	assert_dict(XpCurve.params_of({"type": "power", "power": {"base": 3}})).is_equal({"base": 3.0, "power": 1.33})
	# a table without a usable point plays the default table
	assert_float(XpCurve.need({"type": "table", "table": {"points": [["a", 2], [1]]}}, 10)).is_equal_approx(_today(10), 1e-9)
	# a level below 1 reads as level 1 for the new types
	assert_float(XpCurve.need({"type": "linear"}, 0)).is_equal_approx(21.5, 1e-9)


# ---------------------------------------------------------------- the map, the run

func test_the_reader_and_the_multiplier() -> void:
	assert_dict(JsonContent.timeline_from_dict({}).xp_curve).is_empty()
	assert_dict(JsonContent.timeline_from_dict({"xp_curve": "exponential"}).xp_curve).is_empty()
	var c := {"type": "exponential", "exponential": {"base": 30, "growth": 1.2}}
	assert_dict(JsonContent.timeline_from_dict({"xp_curve": c}).xp_curve).is_equal(c)
	# every type times the map's xp_need_mult
	_map.timeline.xp_need_mult = 2.5
	_map.timeline.xp_curve = c
	for L: int in [1, 4, 25]:
		assert_float(Run.xp_to_next(L)).is_equal_approx(30.0 * pow(1.2, L - 1) * 2.5, 1e-6)
	# the arena levels by the button: the plain curve, x1
	Run.arena = true
	assert_float(Run.xp_to_next(5)).is_equal(_today(5))
	assert_dict(Run.xp_curve()).is_empty()


func test_levels_come_by_the_chosen_curve() -> void:
	_map.timeline.xp_need_mult = 1.0
	_map.timeline.xp_curve = {"type": "linear", "linear": {"base": 10, "step": 10}}
	Run.level = 1
	Run.xp = 0.0
	Run.add_xp(9.0 / Run.player_sheet.get_stat("xp_gain", 1.0))
	assert_int(Run.level).is_equal(1)
	Run.add_xp(1.5 / Run.player_sheet.get_stat("xp_gain", 1.0))
	assert_int(Run.level).is_equal(2)
	# level 2 needs 20, level 3 needs 30: 50 more reaches level 4
	Run.add_xp(50.0 / Run.player_sheet.get_stat("xp_gain", 1.0))
	assert_int(Run.level).is_equal(4)
	assert_float(Run.xp).is_equal_approx(0.5, 1e-6)


func test_the_run_record_names_the_curve() -> void:
	var tl := WaveTimeline.new()
	var bare: Dictionary = RunAnalytics.map_settings(tl)["xp_curve"]
	assert_str(str(bare["type"])).is_equal("quadratic")
	assert_float(float(bare["quad"])).is_equal(0.5)
	tl.xp_curve = {"type": "power", "power": {"power": 1.5}}
	var p: Dictionary = RunAnalytics.map_settings(tl)["xp_curve"]
	assert_str(str(p["type"])).is_equal("power")
	assert_float(float(p["power"])).is_equal(1.5)
	assert_float(float(p["base"])).is_equal(6.5)
