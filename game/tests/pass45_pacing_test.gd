extends GdUnitTestSuite

## Pass 45 (pacing): the live cap is a curve (twenty fodder bodies at 0:00, the old line from 5:00), the boss fight keeps
## `boss_cap_frac` of it, the portal wait keeps `portal_cap` load for `portal_spawn_seconds` (Red Canyon: the stage-end
## cap for as long as the hero stays out), and the skeletons are the goblins' fodder, knights one to two and a half.
## Pass 46 stretched Red Canyon's clock by 430/300: the curve's points, the stage ends and the rows' times below are the
## stretched ones (7:10 stages), the caps at them the same.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_a_timeline_without_a_curve_keeps_the_line() -> void:
	var tl := WaveTimeline.new()
	tl.cap_start = 25
	tl.cap_per_minute = 8.35
	tl.cap_max = 150
	assert_int(tl.cap_at(0.0, 0)).is_equal(25)
	assert_int(tl.cap_at(300.0, 0)).is_equal(66)
	assert_int(tl.cap_at(3600.0, 2)).is_equal(150)
	# cap_per_stage still adds on top of the line
	tl.cap_per_stage = 5
	assert_int(tl.cap_at(300.0, 1)).is_equal(71)


func test_the_curve_is_flat_outside_its_points() -> void:
	var tl := WaveTimeline.new()
	tl.cap_curve = [[0, 10], [300, 66]]
	tl.cap_max = 150
	assert_int(tl.cap_at(-5.0, 0)).is_equal(10)
	assert_int(tl.cap_at(0.0, 0)).is_equal(10)
	assert_int(tl.cap_at(150.0, 0)).is_equal(38)
	assert_int(tl.cap_at(300.0, 0)).is_equal(66)
	assert_int(tl.cap_at(900.0, 2)).is_equal(66)
	# the .tres round-trips the inner numbers as floats
	tl.cap_curve = [[0.0, 10.0], [300.0, 66.0]]
	assert_int(tl.cap_at(150.0, 0)).is_equal(38)
	# cap_max still clamps the curve
	tl.cap_max = 50
	assert_int(tl.cap_at(300.0, 0)).is_equal(50)


func test_red_canyon_opens_with_twenty_bodies_and_keeps_the_old_line_from_the_first_stage_end() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# pass 54 and 56 (re-pinned): Garry draws the curve in the Level Editor (2026-10-07: seventeen points, rushes and
	# drops), so the test checks the game plays the curve his map file holds instead of pinning his numbers
	_check_curve(tl)
	assert_int(tl.cap_max).is_equal(150)

func test_the_boss_fight_keeps_six_in_ten() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(tl.boss_cap_frac).is_equal_approx(0.6, 0.001)
	# a timeline that says nothing keeps the old 30%
	assert_float(WaveTimeline.new().boss_cap_frac).is_equal_approx(0.3, 0.001)
	assert_float(JsonContent.timeline_from_dict({}).boss_cap_frac).is_equal_approx(0.3, 0.001)
	_start()
	Run.elapsed = tl.stage_length
	Run.stage = 0
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.timeline = tl
	d.phase = WaveDirector.Phase.NORMAL
	# pass 56 (re-pinned): the stage-end cap comes from Garry's curve, whatever he draws; the boss fight keeps six in ten
	var full := d.current_cap()
	assert_int(full).is_equal(tl.cap_at(float(tl.stage_length), 0))
	d.phase = WaveDirector.Phase.BOSS
	assert_int(d.current_cap()).is_equal(int(full * 0.6))
	Run.elapsed = 0.0


func test_red_canyon_keeps_spawning_through_the_portal_wait() -> void:
	# Pass 45, Garry: the game went quiet while the portal waited; he wanted to keep killing and earning XP between stages,
	# so Red Canyon kept the stage-end cap up (portal_cap -1 for -1 s, still in its JSON). Pass 48, Garry: "after the boss
	# dies we spawn a small wave and that's it": its portal_wave (twelve, pass48_world_test) comes as the portal opens and
	# the cap is 0 until the hero steps through, however long he waits
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_int(tl.portal_cap).is_equal(-1)
	assert_float(tl.portal_spawn_seconds).is_less(0.0)
	assert_int(int(tl.portal_wave.get("count", 0))).is_equal(12)
	_start()
	Run.elapsed = 430.0
	Run.stage = 0
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.timeline = tl
	d.phase = WaveDirector.Phase.PORTAL
	d._portal_t = 0.0
	assert_int(d.current_cap()).is_equal(0)
	d._portal_t = 999.0
	assert_int(d.current_cap()).is_equal(0)
	# after the Gila too
	Run.elapsed = 860.0
	Run.stage = 1
	assert_int(d.current_cap()).is_equal(0)
	# without the wave, the old reading: the stage-end cap for as long as the portal waits
	var keep := tl.duplicate() as WaveTimeline
	keep.portal_wave = {}
	d.timeline = keep
	# pass 56 (re-pinned): the stage-end caps come from Garry's curve, whatever he draws in the Level Editor
	assert_int(d.current_cap()).is_equal(keep.cap_at(860.0, 1))
	Run.elapsed = 430.0
	Run.stage = 0
	assert_int(d.current_cap()).is_equal(keep.cap_at(430.0, 0))
	Run.elapsed = 0.0
	Run.stage = 0


func test_a_timeline_may_give_the_portal_a_handful_then_nothing() -> void:
	# the other reading of the wait, as data: ten load for thirty seconds, then quiet until the hero walks through (a
	# timeline without a portal wave: pass 48's wave, when there is one, says nothing more comes)
	var tl: WaveTimeline = (Registry.map("red_canyon").timeline as WaveTimeline).duplicate() as WaveTimeline
	tl.portal_wave = {}
	tl.portal_cap = 10
	tl.portal_spawn_seconds = 30.0
	_start()
	Run.elapsed = 430.0
	Run.stage = 0
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.timeline = tl
	d.phase = WaveDirector.Phase.PORTAL
	d._portal_t = 0.0
	assert_int(d.current_cap()).is_equal(10)
	d._portal_t = 29.9
	assert_int(d.current_cap()).is_equal(10)
	d._portal_t = 30.0
	assert_int(d.current_cap()).is_equal(0)
	# a zero cap spawns nothing from the first second
	tl.portal_cap = 0
	d._portal_t = 0.0
	assert_int(d.current_cap()).is_equal(0)
	# the JSON defaults: ten for thirty seconds
	var fresh := JsonContent.timeline_from_dict({})
	assert_int(fresh.portal_cap).is_equal(10)
	assert_float(fresh.portal_spawn_seconds).is_equal_approx(30.0, 0.001)
	assert_array(fresh.cap_curve).is_empty()
	Run.elapsed = 0.0


func test_the_skeletons_are_the_fodder_and_the_knights_come_with_them() -> void:
	var sk: EnemyDef = Registry.enemy("skeleton")
	var kn: EnemyDef = Registry.enemy("skeleton_knight")
	assert_bool(sk.retired).is_false()
	assert_bool(kn.retired).is_false()
	# the goblins' fodder numbers: half a slot each, five to a pack, the knight a fifth tougher
	assert_float(sk.cap_share).is_equal_approx(0.5, 0.001)
	assert_float(kn.cap_share).is_equal_approx(0.5, 0.001)
	assert_int(sk.pack_size).is_equal(5)
	assert_int(kn.pack_size).is_equal(5)
	# tougher than a plain skeleton (1.2x in pass 45; Garry's own numbers since pass 47: 15 against 10)
	assert_float(kn.hp).is_greater(sk.hp)
	# the roster (pass 54, re-pinned to Garry's own placement in the Level Editor, 2026-10-06): the red goblins open the
	# run, and the skeletons and knights come together from 2:51 (171 s) to 5:00 as tougher copies (row overrides, 20 and
	# 35 HP), one to one (they were 9 : 3 from 0:00 in pass 53); with equal packs and shares every draw spawns the same
	# bodies on average, so the count ratio is the weight ratio
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.timeline = tl
	var rows := {}
	for r in tl.roster:
		# the first row of each (pass 62, lane PC, re-pinned: stages 2 and 3 bring skeletons and knights again in rows of
		# their own; Garry's stage-1 pair is the first of each)
		if not rows.has(str(r.get("enemy", ""))):
			rows[str(r.get("enemy", ""))] = r
	assert_bool(rows.has("skeleton") and rows.has("skeleton_knight")).is_true()
	# pass 72, lane INTEG (re-pinned): Garry's rebuilt stage 1 (2026-10-13) brings the skeletons at 0:53 and the knights
	# half a minute later (1:23), both to 2:03: the knights come with or after the skeletons and while they still walk,
	# and wherever the two rows overlap there are one to three skeletons a knight
	var sk_t := float(rows["skeleton"].get("t", 0.0))
	var kn_t := float(rows["skeleton_knight"].get("t", 0.0))
	var sk_until := float(rows["skeleton"].get("until", sk_t + 100.0))
	var kn_until := float(rows["skeleton_knight"].get("until", kn_t + 100.0))
	assert_float(kn_t).is_greater_equal(sk_t)
	assert_float(kn_t).is_less(sk_until)
	var from := kn_t
	var to := minf(sk_until, kn_until)
	for t: float in [from + 1.0, (from + to) * 0.5, to - 1.0]:
		var ratio: float = d._roster_weight(rows["skeleton"], t) / d._roster_weight(rows["skeleton_knight"], t)
		assert_float(ratio).override_failure_message("skeletons per knight at %d s: %.2f" % [int(t), ratio]).is_between(0.95, 3.05)
	# the goblin stays in the content, out of the roster; the runt is back on Garry's roster since 2026-10-13 (row r2):
	# whichever is on it is in play (pass66_shape_test)
	assert_bool(rows.has("goblin")).is_false()
	assert_object(Registry.enemy("goblin_runt")).is_not_null()
	if rows.has("goblin_runt"):
		assert_bool(Registry.enemy("goblin_runt").retired).is_false()


func test_the_boundary_rows_wait_for_their_stage() -> void:
	# the director reads the roster a second early outside the NORMAL phase: the frozen clock sits a hair past 430/860
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var early: Array = []
	for r in tl.roster_at(429.2):
		early.append(str(r.get("enemy", "")))
	var late: Array = []
	for r in tl.roster_at(430.2):
		late.append(str(r.get("enemy", "")))
	# pass 56 (re-pinned): Garry places the rows in the Level Editor, so the rows checked are whichever start or end on
	# the stage's boundary in his map: one that starts there is not open a hair before it and is a hair after; one that
	# ends there is still open a hair before it
	var starts: Array = []
	var ends: Array = []
	for r in tl.roster:
		if is_equal_approx(float(r.get("t", -1.0)), float(tl.stage_length)):
			starts.append(str(r.get("enemy", "")))
		if r.get("until") != null and is_equal_approx(float(r.get("until")), float(tl.stage_length)):
			ends.append(str(r.get("enemy", "")))
	for id in starts:
		if not ends.has(id):
			assert_bool(early.has(id)).override_failure_message(id + " early").is_false()
		assert_bool(late.has(id)).override_failure_message(id + " late").is_true()
	for id in ends:
		assert_bool(early.has(id)).override_failure_message(id + " before the end").is_true()
	assert_int(starts.size() + ends.size()).is_greater(0)


## The cap curve as the map file holds it (pass 56: Garry draws it in the Level Editor, so the tests read his points
## instead of pinning numbers that change every time he saves).
func _map_cap_curve() -> Array:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	return (d.get("timeline_data", {}) as Dictionary).get("cap_curve", [])


## The game plays that curve: its points as loaded, linear between two points (checked half way), the first point's
## value at 0:00, flat after the last, all clamped by cap_max.
func _check_curve(tl: WaveTimeline) -> void:
	var src: Array = _map_cap_curve()
	assert_int(src.size()).is_greater_equal(2)
	assert_int(tl.cap_curve.size()).is_equal(src.size())
	assert_int(tl.cap_per_stage).is_equal(0)
	assert_int(tl.cap_at(0.0, 0)).is_equal(mini(int(float(src[0][1])), tl.cap_max))
	for k in range(src.size() - 1):
		var a: Array = src[k]
		var b: Array = src[k + 1]
		if float(b[0]) <= float(a[0]):
			continue
		var mid := (float(a[0]) + float(b[0])) * 0.5
		var want := mini(int(lerpf(float(a[1]), float(b[1]), 0.5)), tl.cap_max)
		assert_int(tl.cap_at(mid, mini(int(mid / float(tl.stage_length)), 2))).override_failure_message("at %.1f s" % mid).is_equal(want)
	var last: Array = src[src.size() - 1]
	assert_int(tl.cap_at(float(last[0]) + 600.0, 2)).is_equal(mini(int(float(last[1])), tl.cap_max))
