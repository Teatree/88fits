## Pass 74, lane RESULTS (Garry: "The empty chart shouldn't just be sitting there, it should pop-in after the Coin count
## sequence is concluded" and "I wanted the chart, the kill count, the damage dealt and the individual damage sources
## sequence to play together at the same time"): nothing of the chart block shows while the gold counts (its place kept,
## nothing below it moves), the block pops in once the gold is counted (a fade and a small overshoot, as one picture),
## then one chart part plays the line, its marks, both counters and the source rows on one clock: each row comes in as
## the line reaches the moment its source joined the run (a beat apart when several joined together), its bar, number
## and percent at its damage so far, the percent of the run's final total (bars only grow, each ends on its share); a run
## with no story keeps the biggest-first order, its rows spread over the part; taps still hurry and end the sequence.
extends GdUnitTestSuite

const RESULTS := preload("res://ui/ResultsScreen.gd")
const STORY := preload("res://tools/results_story.gd")
const QT := preload("res://core/systems/QuestTracker.gd")
const STEP := 0.04

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"inset": Settings.top_inset}
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._migrate_seen()
	Save._dirty = false
	Run.arena = false
	QT.just_completed.clear()


func after_test() -> void:
	Settings.top_inset = int(_keep["inset"])
	QT.just_completed.clear()
	Save.data = Save._default()
	Save._dirty = false
	Run.end()


## The made-up 10:00 extraction (tools/results_story.gd), its sources given damage curves (the story file has none),
## on the Results.
func _show(died: bool = false) -> Control:
	_story(died)
	return _screen()


func _story(died: bool = false) -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	for pair in [["revolver", 5], ["boomstick", 4], ["molotov", 3], ["big_mouth", 3], ["turret_buddy", 2]]:
		Run.add_weapon(Registry.weapon(str(pair[0])), int(pair[1]))
	Run.end()
	STORY.fill(Run, Save, QT, died)
	_curves(Run.timeline, Run.damage_by_weapon)


func _screen() -> Control:
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


## A run with no story: the damage table by hand, nothing recorded.
func _plain() -> Control:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.end()
	(Save.data["hints_seen"] as Array).append("results")
	Run.damage_by_weapon = {"gravity_gun": 5200.0, "molotov": 900.0, "burn": 140.0, "supply_drop": 2300.0, "blast": 60.0}
	Run.last_result = {"gold_before": 1200, "banked": 640, "lost": 0, "strongbox": 0, "prev_best": {}}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


func _curves(tl: RunTimeline, table: Dictionary) -> void:
	for id in tl.sources:
		var fin := float(table.get(id, 0.0))
		var j := tl.joined(str(id))
		if is_inf(j):
			continue
		var c := PackedFloat32Array()
		var t := RunTimeline.SRC_STEP
		while t < tl.t:
			c.append(0.0 if t < j else fin * clampf((t - j) / maxf(tl.t - j, 1.0), 0.0, 1.0))
			t += RunTimeline.SRC_STEP
		tl.sources[id]["curve"] = c


## Steps the show by STEP until its part is not `part` any more (bounded).
func _through(r: Control, part: String, each: Callable = Callable()) -> void:
	var guard := 0
	while r.part_name() == part and guard < 2000:
		r._process(STEP)
		if each.is_valid():
			each.call()
		guard += 1


func _rows(r: Control) -> Array:
	return r._rows


# ---------------------------------------------------------------- 1. the block waits, then pops

func test_nothing_of_the_chart_block_shows_while_the_gold_counts_and_its_place_is_kept() -> void:
	var r := _show()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(r.part_name()).is_equal("gold")
	# the block's place is kept: the holder as tall as the panel, the rows below it already in their places
	assert_float(r._chart_box.custom_minimum_size.y).is_greater_equal(300.0)
	var rows_y: float = (r.find_child("DamageRows", true, false) as Control).position.y
	var seen := [0]
	_through(r, "gold", func():
		if r.part_name() == "gold":
			seen[0] += 1
			assert_float(r._pop_group.self_modulate.a).is_equal(0.0)
			assert_float(r._perf_label.modulate.a).is_equal(0.0)
			assert_float(r._dmg_label.modulate.a).is_equal(0.0)
			for e: Dictionary in _rows(r):
				assert_float((e["row"] as Control).modulate.a).is_equal(0.0)
			assert_str(r._kills_num.text).is_equal("0"))
	assert_int(seen[0]).is_greater(10)
	# the gold is counted when the pop starts
	assert_str(r.part_name()).is_equal("pop")
	assert_str(r._count.text).is_equal("+" + W.num(Run.run_gold))
	# nothing below the block moved (the whole show long)
	r.skip_all()
	await get_tree().process_frame
	assert_float((r.find_child("DamageRows", true, false) as Control).position.y).is_equal(rows_y)


func test_the_block_pops_in_with_a_fade_and_a_small_overshoot_once_the_gold_is_counted() -> void:
	var r := _show()
	await get_tree().process_frame
	_through(r, "gold")
	assert_str(r.part_name()).is_equal("pop")
	var most := [0.0]
	var faded_by := [-1.0]
	_through(r, "pop", func():
		if r.part_name() == "pop":
			most[0] = maxf(most[0], r._pop_group.scale.x)
			if faded_by[0] < 0.0 and r._pop_group.self_modulate.a >= 1.0:
				faded_by[0] = r.part_frac())
	# a small overshoot past its size, a fade done within its first POP_FADE
	assert_float(most[0]).is_between(1.01, 1.05)
	assert_float(faded_by[0]).is_between(0.0, RESULTS.POP_FADE + 0.15)
	# landed: the panel back in its holder, whole, the pop's picture gone
	assert_str(r.part_name()).is_equal("chart")
	assert_object(r._pop_group).is_null()
	assert_object(r._chart_panel.get_parent()).is_same(r._chart_box)
	assert_float(r._chart_panel.scale.x).is_equal(1.0)
	assert_float(r._chart_panel.modulate.a).is_equal(1.0)
	assert_float(r._perf_label.modulate.a).is_equal(1.0)
	# the starting weapon's row is there as the chart part starts; the others wait
	var rows := _rows(r)
	assert_str(str((rows[0]["row"] as Control).get_meta("source")["name"])).is_equal("Revolver")
	assert_float((rows[0]["row"] as Control).modulate.a).is_equal(1.0)
	for k in range(1, rows.size()):
		assert_float((rows[k]["row"] as Control).modulate.a).is_equal(0.0)


# ---------------------------------------------------------------- 2. one clock for the line, the counters and the rows

func test_the_line_the_counters_and_the_rows_share_one_clock() -> void:
	var r := _show()
	await get_tree().process_frame
	_through(r, "gold")
	_through(r, "pop")
	var tl: RunTimeline = Run.timeline
	var joint: float = r._joint_time
	assert_float(joint).is_equal(RESULTS.JOINT_TIME)
	var checked := [0]
	_through(r, "chart", func():
		if r.part_name() != "chart":
			return
		var clock: float = r.part_frac() * joint
		var x := clampf(clock / RESULTS.JOINT_TIME, 0.0, 1.0)
		checked[0] += 1
		# the line where the clock is
		assert_float(r._chart.head).is_equal_approx(x, 0.0001)
		# the counters at what the run had reached there
		assert_str(r._kills_num.text).is_equal(RESULTS.short_num(tl.value_at(tl.kills_so_far(), float(Run.kills), x)))
		# a row is in once the clock has reached its moment, not before
		for e: Dictionary in _rows(r):
			assert_bool(bool(e["on"])).override_failure_message("%s at %.2f (clock %.2f)" % [str(e["ids"]), float(e["at"]), clock]).is_equal(clock >= float(e["at"])))
	assert_int(checked[0]).is_greater(40)
	# each row's moment is its source's on the line: the Boomstick owned 38 s into the 690 s run
	var rows := _rows(r)
	assert_str(str(rows[1]["ids"][0][0])).is_equal("boomstick")
	assert_float(float(rows[1]["at"])).is_equal_approx(38.0 / 690.0 * RESULTS.JOINT_TIME, 0.001)
	# every row in by the end of the chart part
	for e: Dictionary in rows:
		assert_float((e["row"] as Control).modulate.a).is_equal(1.0)
		assert_bool(bool(e["on"])).is_true()


func test_each_bar_follows_its_damage_so_far_only_grows_and_ends_on_its_share() -> void:
	var r := _show()
	await get_tree().process_frame
	_through(r, "gold")
	_through(r, "pop")
	var tl: RunTimeline = Run.timeline
	var total: float = r._dmg_total
	var last: Dictionary = {}
	_through(r, "chart", func():
		if r.part_name() != "chart":
			return
		var x := clampf(r.part_frac() * float(r._joint_time) / RESULTS.JOINT_TIME, 0.0, 1.0)
		for e: Dictionary in _rows(r):
			var bar: WBar = e["bar"]
			var key := str(e["ids"])
			# only grows
			assert_float(bar.value).is_greater_equal(float(last.get(key, 0.0)) - 0.000001)
			last[key] = bar.value
			if (e["row"] as Control).modulate.a <= 0.0:
				continue
			# its damage so far at the line's moment, against the run's final total
			var so_far := 0.0
			for pair in e["ids"]:
				var v := tl.source_damage_at(str(pair[0]), x * tl.length(), float(pair[1]))
				so_far += v if v >= 0.0 else 0.0
			if so_far > 0.0:
				assert_float(bar.value).is_equal_approx(so_far / total, 0.002)
				assert_str((e["amount"] as WText).text).is_equal(W.num(so_far)))
	# the end: each on its share, its number and its percent whole
	for e: Dictionary in _rows(r):
		var row: Control = e["row"]
		var src: Dictionary = row.get_meta("source")
		var share := float(src["amount"]) / total
		assert_float((e["bar"] as WBar).value).is_equal_approx(share, 0.0001)
		assert_str((e["amount"] as WText).text).is_equal(W.num(float(src["amount"])))
		var pct := roundf(share * 100.0)
		assert_str((e["share"] as WText).text).is_equal("<1%" if pct < 1.0 else "%d%%" % int(pct))


func test_rows_that_joined_together_come_a_beat_apart_and_the_part_waits_for_the_last() -> void:
	# the line's moments, a beat between two that joined together, one never seen at the line's end
	var t := RESULTS.row_times([0.0, 0.0, 0.0, 0.5, 0.5, INF], true, 3.2, 0.12)
	var want := [0.0, 0.12, 0.24, 1.6, 1.72, 3.2]
	for k in want.size():
		assert_float(t[k]).override_failure_message("row %d" % k).is_equal_approx(float(want[k]), 0.0001)
	# no story: spread evenly, still a beat apart when the list is long
	var even := RESULTS.row_times([INF, INF, INF, INF], false, 3.2, 0.12)
	for k in 4:
		assert_float(even[k]).is_equal_approx(0.8 * k, 0.0001)
	var many := RESULTS.row_times(Array(range(40)).map(func(_k): return INF), false, 3.2, 0.12)
	for k in range(1, 40):
		assert_float(many[k] - many[k - 1]).is_greater_equal(0.12 - 0.0001)
	# a run whose last sources joined at its very end: the chart part runs on until the last row has faded in
	_story()
	var late: RunTimeline = Run.timeline
	for id in ["molotov", "big_mouth", "turret_buddy"]:
		late.sources[id]["owned"] = late.t - 0.5
	var r := _screen()
	await get_tree().process_frame
	var lasts: Array = r._rows
	var names: Array = lasts.map(func(e): return str((e["row"] as Control).get_meta("source")["name"]))
	assert_array(names.slice(5)).is_equal(["Big Mouth", "Turret Buddy", "Molotov"])
	var end_at := float(lasts[lasts.size() - 1]["at"])
	assert_float(end_at).is_equal_approx(689.5 / 690.0 * RESULTS.JOINT_TIME + 2.0 * RESULTS.ROW_BEAT, 0.0001)
	assert_float(r._joint_time).is_equal_approx(end_at + RESULTS.ROW_FADE, 0.0001)
	# the line still crosses the run in JOINT_TIME; the last row comes in after it
	_through(r, "gold")
	_through(r, "pop")
	_through(r, "chart", func():
		if r.part_name() == "chart" and r.part_frac() * float(r._joint_time) >= RESULTS.JOINT_TIME:
			assert_float(r._chart.head).is_equal(1.0))
	for e: Dictionary in lasts:
		assert_float((e["row"] as Control).modulate.a).is_equal(1.0)


func test_a_run_with_no_story_keeps_biggest_first_spread_over_the_chart_part() -> void:
	var r := _plain()
	await get_tree().process_frame
	var rows := _rows(r)
	var names: Array = rows.map(func(e): return str((e["row"] as Control).get_meta("source")["name"]))
	assert_array(names).is_equal(["Gravity Gun", "Supply Drop", "Molotov", "Fire", "Explosions"])
	for k in rows.size():
		assert_float(float(rows[k]["at"])).is_equal_approx(RESULTS.JOINT_TIME * float(k) / float(rows.size()), 0.0001)
	# a row grows from its own moment to the end: halfway from it, half its damage
	var e: Dictionary = rows[2]
	var from := float(e["from"])
	var amount := float((e["row"] as Control).get_meta("source")["amount"])
	assert_float(r._row_damage(e, from)).is_equal_approx(0.0, 0.001)
	assert_float(r._row_damage(e, from + (1.0 - from) * 0.5)).is_equal_approx(amount * 0.5, 0.01)
	assert_float(r._row_damage(e, 1.0)).is_equal_approx(amount, 0.0001)
	r.skip_all()
	for row: Dictionary in rows:
		var src: Dictionary = (row["row"] as Control).get_meta("source")
		assert_float((row["bar"] as WBar).value).is_equal_approx(float(src["amount"]) / 8600.0, 0.0001)


# ---------------------------------------------------------------- 3. the show's order, its timings, the taps

func test_the_first_sequence_is_the_gold_the_pop_and_one_chart_part() -> void:
	var r := _show()
	await get_tree().process_frame
	var parts: Array = r._parts.map(func(p): return str(p["name"]))
	assert_array(parts.slice(0, 3)).is_equal(["gold", "pop", "chart"])
	assert_array(r._parts.filter(func(p): return int(p["seq"]) == 1).map(func(p): return str(p["name"]))).is_equal(["gold", "pop", "chart"])
	var first := RESULTS.LEAD_IN + RESULTS.GOLD_TIME + RESULTS.POP_TIME + RESULTS.JOINT_TIME
	var seq1 := RESULTS.LEAD_IN
	for p: Dictionary in r._parts:
		if int(p["seq"]) == 1:
			seq1 += float(p["dur"])
	assert_float(seq1).is_equal_approx(first, 0.0001)
	# about 6.4 s for the first sequence; the whole show of a run with an unlock and four bars about 12 s
	assert_float(seq1).is_between(6.0, 7.0)
	assert_float(r.show_time()).is_between(10.0, 14.0)


func test_a_tap_hurries_the_first_sequence_and_a_second_ends_it_with_everything_in() -> void:
	var r := _show()
	await get_tree().process_frame
	r._process(0.5)
	assert_str(r.part_name()).is_equal("gold")
	r.tap()
	assert_float(r.speed()).is_equal(RESULTS.SPEED_UP)
	assert_float(r._pop_group.self_modulate.a).is_equal(0.0)
	r.tap()
	assert_int(r.sequence()).is_equal(2)
	assert_object(r._pop_group).is_null()
	assert_float(r._chart_panel.modulate.a).is_equal(1.0)
	assert_float(r._chart.head).is_equal(1.0)
	for e: Dictionary in _rows(r):
		assert_float((e["row"] as Control).modulate.a).is_equal(1.0)
		assert_float((e["bar"] as WBar).value).is_equal_approx(float(e["frac"]), 0.0001)


# ---------------------------------------------------------------- 4. the record's damage so far

func test_a_sources_damage_so_far_reads_its_samples() -> void:
	var tl := RunTimeline.new()
	tl.t = 12.0
	tl.sources = {"pea": {"owned": 0.0, "hit": 1.0, "curve": PackedFloat32Array([10.0, 30.0])},
		"none": {"owned": 2.0, "hit": 3.0, "curve": PackedFloat32Array()}}
	# 0 at the start, the samples at 5 s and 10 s, linear between, the run's final at its end
	assert_float(tl.source_damage_at("pea", 0.0, 40.0)).is_equal(0.0)
	assert_float(tl.source_damage_at("pea", 2.5, 40.0)).is_equal_approx(5.0, 0.0001)
	assert_float(tl.source_damage_at("pea", 5.0, 40.0)).is_equal_approx(10.0, 0.0001)
	assert_float(tl.source_damage_at("pea", 7.5, 40.0)).is_equal_approx(20.0, 0.0001)
	assert_float(tl.source_damage_at("pea", 10.0, 40.0)).is_equal_approx(30.0, 0.0001)
	assert_float(tl.source_damage_at("pea", 11.0, 40.0)).is_equal_approx(35.0, 0.0001)
	assert_float(tl.source_damage_at("pea", 12.0, 40.0)).is_equal(40.0)
	# never past what the run counted for it
	assert_float(tl.source_damage_at("pea", 9.0, 20.0)).is_less_equal(20.0)
	# nothing sampled: -1 (the Results spread its damage instead)
	assert_float(tl.source_damage_at("none", 5.0, 40.0)).is_equal(-1.0)
	assert_float(tl.source_damage_at("nobody", 5.0, 40.0)).is_equal(-1.0)
