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
	# pass 54 (re-pinned): Garry's own curve from the Level Editor (2026-10-06), ten points with a rush to 62 at 1:31 and
	# a dip to 36 at 2:53; the opening and the line from the first stage's end are as they were
	assert_int(tl.cap_curve.size()).is_equal(10)
	assert_int(tl.cap_start).is_equal(10)
	assert_int(tl.cap_at(0.0, 0)).is_equal(10)
	# the skeletons count half a slot each, so ten load units are twenty bodies
	assert_int(int(10.0 / Registry.enemy("skeleton").cap_share)).is_equal(20)
	# pass 46: the old minute marks are 86 s apart now (pass 54: on Garry's curve)
	assert_int(tl.cap_at(86.0, 0)).is_equal(29)
	assert_int(tl.cap_at(172.0, 0)).is_equal(38)
	assert_int(tl.cap_at(258.0, 0)).is_equal(48)
	assert_int(tl.cap_at(344.0, 0)).is_equal(58)
	# from the first stage's end (7:10) on it is pass 29's line: 66 -> 108 -> 150
	assert_int(tl.cap_at(430.0, 0)).is_equal(66)
	assert_int(tl.cap_at(645.0, 1)).is_equal(87)
	assert_int(tl.cap_at(860.0, 1)).is_equal(108)
	assert_int(tl.cap_at(1290.0, 2)).is_equal(150)
	assert_int(tl.cap_at(2150.0, 2)).is_equal(150)
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
	assert_int(d.current_cap()).is_equal(66)
	# six in ten of the stage-end cap: int(66 x 0.6)
	d.phase = WaveDirector.Phase.BOSS
	assert_int(d.current_cap()).is_equal(39)
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
	assert_int(d.current_cap()).is_equal(108)
	Run.elapsed = 430.0
	Run.stage = 0
	assert_int(d.current_cap()).is_equal(66)
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
		rows[str(r.get("enemy", ""))] = r
	assert_bool(rows.has("skeleton") and rows.has("skeleton_knight")).is_true()
	assert_float(float(rows["skeleton"].get("t", -1.0))).is_equal_approx(float(rows["skeleton_knight"].get("t", -2.0)), 0.001)
	var from := float(rows["skeleton"].get("t", 0.0))
	for t: float in [from + 1.0, from + 60.0, float(rows["skeleton"].get("until", from + 100.0)) - 1.0]:
		var ratio: float = d._roster_weight(rows["skeleton"], t) / d._roster_weight(rows["skeleton_knight"], t)
		assert_float(ratio).override_failure_message("skeletons per knight at %d s: %.2f" % [int(t), ratio]).is_between(0.95, 3.05)
	# the goblins stay in the content, out of the roster
	assert_bool(rows.has("goblin")).is_false()
	assert_bool(rows.has("goblin_runt")).is_false()


func test_the_boundary_rows_wait_for_their_stage() -> void:
	# the director reads the roster a second early outside the NORMAL phase: the frozen clock sits a hair past 430/860
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var early: Array = []
	for r in tl.roster_at(429.2):
		early.append(str(r.get("enemy", "")))
	var late: Array = []
	for r in tl.roster_at(430.2):
		late.append(str(r.get("enemy", "")))
	assert_bool(early.has("dust_mummy")).is_false()
	assert_bool(late.has("dust_mummy")).is_true()
	# the stage's last rows are open a hair before its end (pass 54: Garry's red goblins close stage 1, 5:00 to 7:10)
	assert_bool(early.has("red_goblin")).is_true()
