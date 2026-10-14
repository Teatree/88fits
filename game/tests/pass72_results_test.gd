## Pass 72, lane RESULTS (Garry: "The Result Screen sequence in general should be more animated"): the run's story
## (RunTimeline: the purse a second, the kills a second with the boss, Elite and special kills and the downs marked, the
## damage a second, every source's first owned or first hit moment, the counted unlocks as the run began), the short
## numbers (999, 1.2k, 20k, 1.2m), the kills chart's marks, the damage sources in the order they joined the run, the
## unlocks brought closer, and the show itself: the first sequence held at the top (gold on the run's own curve, the
## chart, the sources one by one), the second (a pause, the scroll, the unlocks stamped, the bars), a tap hurries, a
## second ends the sequence, the buttons never hurry it.
extends GdUnitTestSuite

const RESULTS := preload("res://ui/ResultsScreen.gd")
const STORY := preload("res://tools/results_story.gd")
const QT := preload("res://core/systems/QuestTracker.gd")

const FAKE_GAME := "extends Node\nvar enemies\nvar player\nvar director\n"
const FAKE_CROWD := "extends Node\nsignal creature_dying(i: int, weapon_id: String)\nvar type_idx := PackedInt32Array()\nvar elite_idx := PackedInt32Array()\nvar vspecial := PackedByteArray()\nvar _t_dummy := PackedByteArray()\nvar types: Array = []\nvar boss_index := -1\n"
const FAKE_HERO := "extends Node\nsignal died\n"
const FAKE_DIRECTOR := "extends Node\nsignal stage_started(stage: int)\n"

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


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _node(src: String) -> Node:
	var n: Node = auto_free(Node.new())
	n.set_script(_script(src))
	return n


# ---------------------------------------------------------------- short numbers

func test_big_numbers_are_shortened_and_never_rounded_up() -> void:
	var cases := {0.0: "0", 7.9: "7", 999.0: "999", 1000.0: "1k", 1250.0: "1.2k", 1999.0: "1.9k", 9999.0: "9.9k",
		20000.0: "20k", 123456.0: "123k", 999999.0: "999k", 1200000.0: "1.2m", 12345678.0: "12m", 2500000000.0: "2.5b"}
	for v in cases:
		assert_str(RESULTS.short_num(float(v))).override_failure_message("%s" % str(v)).is_equal(str(cases[v]))


# ---------------------------------------------------------------- the record

func test_the_story_keeps_the_purse_the_kills_the_marks_and_the_damage_by_the_second() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var tl: RunTimeline = Run.timeline
	# not attached (a tool's or a test's run): the clock stands still
	tl.tick(1.0)
	assert_float(tl.t).is_equal(0.0)
	tl.attached = true
	tl._on_gold(10)
	tl.kill(RunTimeline.KIND_PLAIN)
	tl.kill(RunTimeline.KIND_SPECIAL)
	tl.tick(1.0)
	tl._on_gold(25)
	tl.kill(RunTimeline.KIND_BOSS)
	tl.down()
	Run.damage_by_weapon["revolver"] = 40.0
	tl.tick(1.0)
	tl._on_gold(15)
	tl.tick(0.5)
	assert_float(tl.t).is_equal_approx(2.5, 0.001)
	assert_array(Array(tl.purse)).is_equal([10, 25])
	assert_array(Array(tl.kills)).is_equal([2, 1])
	assert_array(Array(tl.damage)).is_equal([0.0, 40.0])
	assert_int(tl.markers.size()).is_equal(3)
	assert_int(int(tl.markers[0][1])).is_equal(RunTimeline.KIND_SPECIAL)
	assert_int(int(tl.markers[1][1])).is_equal(RunTimeline.KIND_BOSS)
	assert_int(int(tl.markers[2][1])).is_equal(RunTimeline.KIND_DOWN)
	# the revolver first hit in the second second; nothing owned it (no build scan here)
	assert_float(tl.joined("revolver")).is_equal(1.0)
	assert_float(tl.joined("nothing")).is_equal(INF)
	# a curve read back: 0 at the start, the samples between, the end exactly what the run ended on
	assert_float(tl.value_at(tl.purse, 15.0, 0.0)).is_equal(0.0)
	assert_float(tl.value_at(tl.purse, 15.0, 0.4)).is_equal_approx(10.0, 0.01)
	assert_float(tl.value_at(tl.purse, 15.0, 1.0)).is_equal(15.0)
	assert_float(tl.value_at(tl.kills_so_far(), 3.0, 1.0)).is_equal(3.0)
	var slices := tl.kill_slices(5)
	var sum := 0.0
	for v in slices:
		sum += v
	assert_float(sum).is_equal(3.0)


func test_attached_to_a_game_it_hears_the_crowd_the_hero_the_stages_the_purse_and_the_build() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var g := _node(FAKE_GAME)
	var em := _node(FAKE_CROWD)
	var hero := _node(FAKE_HERO)
	var dir := _node(FAKE_DIRECTOR)
	g.set("enemies", em)
	g.set("player", hero)
	g.set("director", dir)
	var plain: EnemyDef = Registry.enemy("skeleton")
	var boss: EnemyDef = null
	var elite: EnemyDef = null
	var gear: EnemyDef = null
	for e: EnemyDef in Registry.enemies.values():
		if boss == null and e.archetype == "boss":
			boss = e
		if elite == null and e.archetype == "elite":
			elite = e
		if gear == null and e.badge_for() == "gear" and e.archetype != "boss" and e.archetype != "elite":
			gear = e
	assert_object(boss).is_not_null()
	assert_object(elite).is_not_null()
	assert_object(gear).is_not_null()
	em.set("types", [{"def": plain}, {"def": boss}, {"def": elite}, {"def": gear}])
	em.set("_t_dummy", PackedByteArray([0, 0, 0, 0]))
	# creatures 0..5: plain, the boss, an Elite, a gear special, a variance special, a plain one wearing an elite modifier
	em.set("type_idx", PackedInt32Array([0, 1, 2, 3, 0, 0]))
	em.set("elite_idx", PackedInt32Array([-1, -1, -1, -1, -1, 0]))
	em.set("vspecial", PackedByteArray([0, 0, 0, 0, 1, 0]))
	em.set("boss_index", 1)
	var tl: RunTimeline = Run.timeline
	Run.add_weapon(Registry.weapon("revolver"), 1)
	tl.attach(g)
	assert_bool(tl.attached).is_true()
	assert_str(tl.start_weapon).is_equal("revolver")
	assert_float(tl.joined("revolver")).is_equal(0.0)
	var want := [RunTimeline.KIND_PLAIN, RunTimeline.KIND_BOSS, RunTimeline.KIND_ELITE, RunTimeline.KIND_SPECIAL,
		RunTimeline.KIND_SPECIAL, RunTimeline.KIND_ELITE]
	for i in want.size():
		assert_int(RunTimeline.kind_of(em, i)).override_failure_message("creature %d" % i).is_equal(int(want[i]))
	for i in want.size():
		em.emit_signal("creature_dying", i, "revolver")
	assert_int(int(tl.kills[0])).is_equal(6)
	assert_int(tl.markers.size()).is_equal(5)
	hero.emit_signal("died")
	assert_int(int(tl.markers[tl.markers.size() - 1][1])).is_equal(RunTimeline.KIND_DOWN)
	tl.tick(3.0)
	dir.emit_signal("stage_started", 1)
	assert_int(tl.stages.size()).is_equal(1)
	assert_float(float(tl.stages[0][0])).is_equal(3.0)
	# the purse follows Run's gold; a weapon owned later joins then
	Run.add_gold(30, "coins")
	tl.tick(1.0)
	assert_int(int(tl.purse[tl.purse.size() - 1])).is_equal(Run.run_gold)
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	assert_float(tl.joined("boomstick")).is_equal(4.0)
	assert_str(tl.start_weapon).is_equal("revolver")
	# a training dummy is no kill of the story
	em.set("_t_dummy", PackedByteArray([1, 0, 0, 0]))
	assert_int(RunTimeline.kind_of(em, 0)).is_equal(-1)


func test_every_run_starts_a_new_story_and_the_game_attaches_and_ticks_it() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var first: RunTimeline = Run.timeline
	first.attached = true
	first.kill(RunTimeline.KIND_PLAIN)
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_object(Run.timeline).is_not_same(first)
	assert_bool(Run.timeline.is_empty()).is_true()
	# Game's two hooks: the attach in _ready (never the arena's) and the tick with the run recorder's
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_int(src.find("if not arena: Run.timeline.attach(self)")).is_greater(-1)
	assert_int(src.find("Run.timeline.tick(delta)")).is_greater(-1)


# ---------------------------------------------------------------- the chart's marks

func test_the_chart_merges_marks_of_a_kind_and_pops_them_as_the_line_reaches_them() -> void:
	var m := [[10.0, RunTimeline.KIND_SPECIAL], [12.0, RunTimeline.KIND_SPECIAL], [60.0, RunTimeline.KIND_ELITE],
		[61.0, RunTimeline.KIND_ELITE], [80.0, RunTimeline.KIND_BOSS], [99.0, RunTimeline.KIND_DOWN]]
	var marks := WKillChart.group_marks(m, 100.0, 0.05)
	assert_int(marks.size()).is_equal(4)
	assert_int(int(marks[0]["n"])).is_equal(2)
	assert_int(int(marks[1]["n"])).is_equal(2)
	# a special's bin is twice another's: 8% apart still one gear, an Elite's two crowns 8% apart are two
	var wide := WKillChart.group_marks([[10.0, RunTimeline.KIND_SPECIAL], [18.0, RunTimeline.KIND_SPECIAL],
		[10.0, RunTimeline.KIND_ELITE], [18.0, RunTimeline.KIND_ELITE]], 100.0, 0.05)
	assert_int(wide.size()).is_equal(3)
	# drawn: each mark pops once as the head passes it, a skip shows them all with no pops
	var tl := RunTimeline.new()
	tl.attached = true
	tl.t = 100.0
	for k in 100:
		tl.kills.append(k % 7)
	tl.markers = m
	var c: WKillChart = auto_free(WKillChart.new().setup(tl, 600.0))
	c.size = Vector2(600, 300)
	add_child(c)
	var heard: Array = []
	c.popped.connect(func(kind): heard.append(kind))
	c.head = 0.5
	assert_array(heard).is_equal([RunTimeline.KIND_SPECIAL])
	c.head = 1.0
	assert_int(heard.size()).is_equal(4)
	c.head = 1.0
	assert_int(heard.size()).is_equal(4)
	var c2: WKillChart = auto_free(WKillChart.new().setup(tl, 600.0))
	add_child(c2)
	var heard2: Array = []
	c2.popped.connect(func(kind): heard2.append(kind))
	c2.finish()
	assert_float(c2.head).is_equal(1.0)
	assert_int(heard2.size()).is_equal(0)
	for mk: Dictionary in c2.marks:
		assert_float(c2._pop_scale(float(mk["at"]))).is_equal(1.0)
	# the four badges are the game's own pictures (none of its fonts has the emoji), the grave new in pass 72
	for kind in [RunTimeline.KIND_SPECIAL, RunTimeline.KIND_ELITE, RunTimeline.KIND_BOSS, RunTimeline.KIND_DOWN]:
		assert_object(c._badge(kind)).override_failure_message(RunTimeline.KIND_NAMES[kind]).is_not_null()


# ---------------------------------------------------------------- the sources' order

func test_the_sources_come_in_the_order_they_joined_the_run_the_starting_weapon_first() -> void:
	var tl := RunTimeline.new()
	tl.start_weapon = "revolver"
	tl.sources = {"revolver": {"owned": 0.0, "hit": 1.0, "curve": PackedFloat32Array()},
		"supply_drop": {"owned": 0.0, "hit": 30.0, "curve": PackedFloat32Array()},
		"boomstick": {"owned": 40.0, "hit": 41.0, "curve": PackedFloat32Array()},
		"burn": {"owned": -1.0, "hit": 90.0, "curve": PackedFloat32Array()},
		"fire": {"owned": -1.0, "hit": 20.0, "curve": PackedFloat32Array()},
		"revive": {"owned": -1.0, "hit": 300.0, "curve": PackedFloat32Array()}}
	var dmg := {"boomstick": 900.0, "revolver": 100.0, "supply_drop": 500.0, "burn": 30.0, "fire": 5.0, "revive": 50.0,
		"mystery_beam": 7.0}
	var order: Array = RESULTS.ordered_sources(dmg, tl)
	var names: Array = order.map(func(s): return str(s["name"]))
	assert_array(names).is_equal(["Revolver", "Supply Drop", "Fire", "Boomstick", "Revive blast", "Mystery Beam"])
	# fire and burn are one source: summed, joined at the first of them
	assert_float(float(order[2]["amount"])).is_equal(35.0)
	assert_float(float(order[2]["at"])).is_equal(20.0)
	# no story (a tool's run): biggest first, as before
	var plain: Array = RESULTS.ordered_sources(dmg, RunTimeline.new()).map(func(s): return str(s["name"]))
	assert_str(str(plain[0])).is_equal("Boomstick")


# ---------------------------------------------------------------- the unlocks brought closer

func test_the_unlocks_brought_closer_are_the_counted_ones_that_grew_nearest_first() -> void:
	Save.data["totals"]["kills"] = 380
	Save.data["totals"]["chests"] = 2
	Save.mark_quest("unlock_turret_buddy")
	var before := {"unlock_adrenaline": 120, "unlock_ironwood": 120, "unlock_rocket_pod": 2, "unlock_turret_buddy": 8}
	var list: Array = RESULTS.progress_list(before)
	var ids: Array = list.map(func(c): return (c["q"] as QuestDef).id)
	# the chests' did not grow, the Turret Buddy's is done (it lands as an unlock): neither is here
	assert_array(ids).is_equal(["unlock_adrenaline", "unlock_ironwood"])
	assert_int(int(list[0]["before"])).is_equal(120)
	assert_int(int(list[0]["after"])).is_equal(380)
	assert_int(int(list[0]["need"])).is_equal(400)
	# the story's snapshot as a run begins: every counted quest not done, with its progress then
	var snap := RunTimeline.quest_progress()
	assert_int(int(snap.get("unlock_adrenaline", -1))).is_equal(380)
	assert_bool(snap.has("unlock_turret_buddy")).is_false()
	assert_bool(snap.has("unlock_pike")).is_false()


# ---------------------------------------------------------------- the show

func _show(died: bool = false) -> Control:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	for pair in [["revolver", 5], ["boomstick", 4], ["molotov", 3], ["big_mouth", 3], ["turret_buddy", 2]]:
		Run.add_weapon(Registry.weapon(str(pair[0])), int(pair[1]))
	Run.end()
	STORY.fill(Run, Save, QT, died)
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


func _rows(r: Control) -> Array:
	return r.find_child("DamageRows", true, false).get_children()


func test_the_first_sequence_holds_the_board_and_tells_the_gold_the_chart_and_the_sources_in_turn() -> void:
	var r := _show()
	await get_tree().process_frame
	assert_int(r.sequence()).is_equal(1)
	assert_str(r.part_name()).is_equal("gold")
	assert_str(r._count.text).is_equal("+0")
	assert_str((r.find_child("Kills", true, false) as WText).text).is_equal("0")
	# every row waits its turn, in the order they joined (re-pinned in pass 74: the starting weapon's row too, until the
	# chart block pops in after the gold; pass74_results_test has the rest)
	var rows := _rows(r)
	assert_int(rows.size()).is_equal(8)
	assert_str(str(rows[0].get_meta("source")["name"])).is_equal("Revolver")
	assert_str(str(rows[1].get_meta("source")["name"])).is_equal("Boomstick")
	for k in range(0, rows.size()):
		assert_float((rows[k] as Control).modulate.a).is_equal(0.0)
	assert_float((rows[0].find_child("Bar", true, false) as WBar).value).is_equal(0.0)
	# the gold follows the run's own purse: a quarter of the way through it shows what he held a quarter into the run
	var tl: RunTimeline = Run.timeline
	r._part_gold(0.25, false)
	var want := int(round(tl.value_at(tl.purse, float(Run.run_gold), 0.25)))
	assert_str(r._count.text).is_equal("+" + W.num(want))
	r._part_gold(1.0, false)
	assert_str(r._count.text).is_equal("+" + W.num(Run.run_gold))
	# the board is held: a finger's drag never reaches the list
	var sc: ScrollContainer = r.scroll
	sc.scroll_vertical = 0
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = sc.get_global_rect().get_center()
	drag.relative = Vector2(0, -300)
	r._input(drag)
	assert_int(sc.scroll_vertical).is_equal(0)
	# the whole show, at normal speed, inside Garry's 10-14 s for a run with no unlock (this one lands one: a little more)
	assert_float(r.show_time()).is_between(10.0, 16.0)
	assert_float(r.show_time() - RESULTS.UNLOCK_TIME).is_less_equal(14.0)
	# a run that lands many unlocks gives each less time, never under UNLOCK_MIN
	assert_float(RESULTS.unlock_time(1)).is_equal(RESULTS.UNLOCK_TIME)
	assert_float(RESULTS.unlock_time(4)).is_equal_approx(1.0, 0.0001)
	assert_float(RESULTS.unlock_time(12)).is_equal(RESULTS.UNLOCK_MIN)


func test_a_tap_hurries_a_second_ends_the_sequence_and_a_button_never_hurries() -> void:
	var r := _show()
	await get_tree().process_frame
	await get_tree().process_frame
	# a finger on PLAY AGAIN: the button's, not the show's
	var again: Control = null
	for n in r.find_children("*", "Control", true, false):
		if n is WButton and (n as WButton).label_text() == "PLAY AGAIN":
			again = n
	assert_object(again).is_not_null()
	var on := InputEventScreenTouch.new()
	on.index = 0
	on.pressed = true
	on.position = again.get_global_rect().get_center()
	r._input(on)
	var off := on.duplicate() as InputEventScreenTouch
	off.pressed = false
	r._input(off)
	assert_float(r.speed()).is_equal(1.0)
	assert_int(r.sequence()).is_equal(1)
	# anywhere else (the board's middle): the first tap hurries, the second ends the first sequence
	var at: Vector2 = r.scroll.get_global_rect().get_center()
	assert_bool(r._on_button(at)).is_false()
	on.position = at
	off.position = at
	r._input(on)
	r._input(off)
	assert_float(r.speed()).is_equal(RESULTS.SPEED_UP)
	r._input(on)
	r._input(off)
	assert_int(r.sequence()).is_equal(2)
	assert_float(r.speed()).is_equal(1.0)
	# every source shown and filled, the chart drawn, the counters at the run's ends
	for row: Control in _rows(r):
		assert_float(row.modulate.a).is_equal(1.0)
		var src: Dictionary = row.get_meta("source")
		assert_str((row.find_child("Amount", true, false) as WText).text).is_equal(W.num(float(src["amount"])))
	assert_float(r._chart.head).is_equal(1.0)
	assert_str((r.find_child("Kills", true, false) as WText).text).is_equal(RESULTS.short_num(Run.kills))
	# the second sequence: a tap hurries, another ends the show; the unlock is stamped, its plate its art
	r.tap()
	assert_float(r.speed()).is_equal(RESULTS.SPEED_UP)
	r.tap()
	assert_int(r.sequence()).is_equal(RESULTS.DONE)
	var unlock: Dictionary = r._unlocks[0]
	assert_bool((unlock["stamp"] as WStamp).visible).is_true()
	assert_str((unlock["stamp"] as WStamp).word).is_equal("UNLOCKED")
	assert_bool((unlock["plate"] as WPlate).locked).is_false()
	assert_float((unlock["panel"] as Control).modulate.a).is_equal(1.0)
	# the bars brought closer stand at where they stand now, this run's part in sage
	assert_int(r._progress.size()).is_greater(0)
	for e: Dictionary in r._progress:
		var bar: WBar = e["bar"]
		assert_float(bar.value).is_equal_approx(float(e["after"]) / float(e["need"]), 0.0001)
		assert_float(bar.gain).is_equal_approx(float(e["after"] - e["before"]) / float(e["need"]), 0.0001)
	# once the show is over the board scrolls under a finger again (ScreenBase's TouchScroll is fed)
	assert_int(r._touch._id).is_equal(-1)
	r._input(on)
	assert_int(r._touch._id).is_equal(0)
	r._input(off)


func test_the_show_plays_by_itself_to_its_end() -> void:
	var r := _show(true)
	await get_tree().process_frame
	var parts: Array = []
	var guard := 0
	while r.sequence() != RESULTS.DONE and guard < 2000:
		r._process(0.05)
		var n: String = r.part_name()
		if n != "" and (parts.is_empty() or parts[parts.size() - 1] != n):
			parts.append(n)
		guard += 1
	assert_int(r.sequence()).is_equal(RESULTS.DONE)
	# re-pinned in pass 74: the chart block's pop, then one chart part for the line, the counters and the sources
	assert_array(parts).is_equal(["gold", "pop", "chart", "pause", "scroll", "unlock", "progress"])
	# the fall's run: two graves on the chart, the revive's blast the last source to join
	var graves := 0
	for mk: Dictionary in r._chart.marks:
		if int(mk["kind"]) == RunTimeline.KIND_DOWN:
			graves += 1
	assert_int(graves).is_equal(2)
	var rows := _rows(r)
	assert_str(str(rows[rows.size() - 1].get_meta("source")["name"])).is_equal("Revive blast")


func test_a_run_with_nothing_unlocked_or_closer_has_no_second_sequence() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 100, "banked": 30, "lost": 0, "strongbox": 0, "prev_best": {}}
	Run.damage_by_weapon = {"gravity_gun": 50.0}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	await get_tree().process_frame
	assert_object(r.find_child("Unlocks", true, false)).is_null()
	r.tap()
	r.tap()
	assert_int(r.sequence()).is_equal(RESULTS.DONE)
	assert_str(r._count.text).is_equal("+30")
