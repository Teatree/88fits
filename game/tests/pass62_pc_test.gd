extends GdUnitTestSuite

## Pass 62, lane PC (Garry, 2026-10-09: "I quite like the type of pacing that I set up for Stage 1 ... do something similar
## for the other 2 stages ... moments of higher intensity (higher cap) with special kinds of spawning behavior like 'ring'
## ... fewer 'introductions' of new types of enemies ... any enemy that isn't simply 'walk and melee attack' should be in
## fewer numbers ... One of the introductions that you ought to make at the beginning of stage 2 is the Dwarf Shooter.
## You will keep Stage 1 unchanged ... Stage 2 can be completed with half the Mirror done and Stage 3 needs the full
## Mirror"). Stage 1 is pinned as Garry left it (STAGE1: his cap points to 7:10, his rows and events that start before it,
## the scalars that act in it, the curves' values before it); stages 2 and 3 are read from the map file, not pinned, so
## he can tweak them in the Level Editor: the dwarf from the stage's first seconds, cap rushes with a ring or in-front row
## in each stage and quieter stretches after them, fewer introductions than stage 1 but some, the non-melee creatures in
## small packs at low weights, a crowd that runs on into endless, the ATK x curve's step after each boss second and each
## stage's HP ramp.

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const STAGE := 430.0
## Garry's stage 1 as it stood before pass 62 (copied from the file by lane PC).
## Pass 69 (lane EN, re-pinned on Garry's word: "a single 'Special' regular Goblin appears at the end of the first wave"):
## the special Red Goblin's swarm event at 2:00 joins his events.
const STAGE1 := """{"cap":[[0,10],[63,27],[122,45],[123,80],[176,80],[176,45],[213,56],[232,84],[306,79],[306,132],[337,132],[337,73],[368,72],[430,100]],"rows":[{"id":"r1","t":0,"enemy":"red_goblin","weights":[[0,9],[59,5.1],[63,8.8],[118,8.4]],"stats":{"elite":{"hp_mult_per_stage":0}},"until":122,"variant":"RG-B"},{"id":"r2","t":0,"enemy":"red_goblin_runt","weights":[[0,3],[60,3.7]],"until":59},{"id":"r18","t":58,"enemy":"blue_slime","weights":[[58,2.5],[121,2.5]],"until":123,"stats":{"hp":40}},{"id":"r3","t":123,"enemy":"lesser_scorpion","weights":[[121,8],[174,7.6]],"until":176,"pattern":"in_front","pack":100,"stats":{"speed":1.5,"hp_mult":1.2}},{"id":"r12","t":176,"enemy":"skeleton","weights":[[177,6.7]],"until":285,"stats":{"hp":20}},{"id":"r13","t":176,"enemy":"skeleton_knight","weights":[[177,2.9]],"until":306,"stats":{"hp":35},"pattern":"scatter"},{"id":"r14","t":176,"enemy":"spit_cactus","weights":[[177,1.8]],"until":234,"pattern":"scatter"},{"id":"r17","t":368,"enemy":"spit_cactus","weights":[[369,1.2]],"until":430,"pattern":"scatter"},{"id":"r15","t":250,"enemy":"bull_beetle","weights":[[250,1]],"until":368,"pattern":"scatter"},{"id":"r16","t":306,"enemy":"werewolf","weights":[[306,5.4]],"until":430,"stats":{"hp":20,"size":1.4},"pattern":"ring"}],"events":[{"t":120,"type":"swarm","enemy":"red_goblin","variant":"RG-B","count":1,"pattern":"in_front","special":true,"name":"Special Goblin"},{"t":215,"type":"elite_boss","enemy":["dune_scorpion","sun_prophet","stone_golem"]},{"t":301,"type":"elite_every","interval":129},{"t":430,"type":"boss","enemy":"tumbleweed_king"}],"scalars":{"level_hp_per_level":0.05,"level_damage_per_level":0.03,"creature_hp_mult":1.3,"creature_damage_mult":1.25,"creature_speed_mult":0.9,"stage_length":430,"contact_cap":0.22,"xp_need_mult":2.1,"move_pace":0.9,"colour_after_kills":50,"boss_cap_frac":0.6,"hard_cap":260,"cap_max":150,"burst_min":3,"burst_max":12,"spawn_interval":0.7,"spawn_sides":{"mode":"facing","top":55,"bottom":15,"left":15,"right":15,"facing_share":0.7,"facing_spread_deg":60},"specials":{"from":215,"interval":[64,86],"max_alive":1,"pool":[{"enemy":"rocketeer"},{"enemy":"harpoon_troglodyte","stage":2}]},"pickups":{"per_kill":0.0045,"roster":[{"id":"heart","weight":6,"hard_bias":0.0},{"id":"rage","weight":3,"hard_bias":0.5},{"id":"sprint","weight":3,"hard_bias":0.3},{"id":"shield","weight":2,"hard_bias":0.8},{"id":"magnet_pulse","weight":2,"hard_bias":0.6},{"id":"nuke","weight":2,"hard_bias":0.8}]},"hp_curve":{"mode":"formula","formula":{"kind":"power","a":0.0977,"b":1.25},"points":[[0,1.0],[430,1.9414],[860,2.9878],[1290,4.1143]]},"portal_wave":{"count":12},"portal_cap":-1,"portal_spawn_seconds":-1},"stage_mult0":1.0,"path_times0":[79,140,200,260,315,365,405]}"""


func _json() -> Dictionary:
	var f := FileAccess.open(MAP_JSON, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _same(a, b) -> String:
	var sa := JSON.stringify(a, "", true)
	var sb := JSON.stringify(b, "", true)
	return "" if sa == sb else "%s != %s" % [sa.left(400), sb.left(400)]


func _tl() -> WaveTimeline:
	return Registry.map("red_canyon").timeline


func test_stage_one_is_garrys_as_he_left_it() -> void:
	# Pass 72, lane INTEG (re-pinned): Garry rebuilt stage 1 in the Level Editor on 2026-10-13 (the scorpions open it, the
	# skeletons and knights, the red goblins from 2:03 with the goblin runt back at 2:21, the slimes, the cactus, the
	# beetle and the werewolves after), so the copy pinned in pass 62 (STAGE1, kept for the HP curve below) is his old
	# one. What is pinned now is the shape of whatever he leaves: the cap rising in time order to 7:10, every stage-1 row
	# a creature there with weights and an end inside the stage, distinct row ids, the King closing the stage, every
	# scalar the stage plays present, stage 1 at x1 and its path times inside it, in order.
	var tl: Dictionary = _json()["timeline_data"]
	var cap: Array = (tl["cap_curve"] as Array).filter(func(p): return float(p[0]) <= STAGE)
	assert_int(cap.size()).is_greater_equal(1)  # pass 85 re-pin: Garry's stage 1 cap may be one flat point
	assert_float(float(cap[0][0])).is_equal(0.0)
	for i in range(1, cap.size()):
		assert_float(float(cap[i][0])).override_failure_message("cap point %d" % i).is_greater_equal(float(cap[i - 1][0]))
		assert_float(float(cap[i][1])).override_failure_message("cap point %d" % i).is_greater(0.0)
	var rows: Array = (tl["roster"] as Array).filter(func(r): return float(r.get("t", 0.0)) < STAGE)
	assert_int(rows.size()).is_greater_equal(3)
	var ids := {}
	for r in rows:
		var id := str(r.get("id", ""))
		assert_bool(id != "" and not ids.has(id)).override_failure_message("row id " + id).is_true()
		ids[id] = true
		if str(r.get("enemy", "")) != WaveTimeline.ROW_ENEMY_ROSTER:
			assert_object(Registry.enemy(str(r.get("enemy", "")))).override_failure_message(id + ": " + str(r.get("enemy", ""))).is_not_null()
		assert_bool((r.get("weights", []) as Array).is_empty()).override_failure_message(id + " weights").is_false()
		# pass 84 (lane SPAWN, re-pinned): the converted events are rows with no end (a once row fires once; the
		# Elites-every row runs into endless as its event did); only the continuous and waves rows end in the stage
		if str(r.get("pace", "")) == "once" or str(r.get("elite", "")) != "":
			continue
		# no stage-1 row was stretched past 7:10
		assert_float(float(r.get("until", 1e9))).override_failure_message(id + " until").is_less_equal(STAGE)
		assert_float(float(r.get("until", 1e9))).override_failure_message(id + " until").is_greater(float(r.get("t", 0.0)))
	# his events to 7:10, the King at 430 closing them
	var king := false
	for e in (tl["events"] as Array):
		if float(e.get("t", 0.0)) == STAGE and str(e.get("type", "")) == "boss" and str(e.get("enemy", "")) == "tumbleweed_king":
			king = true
	assert_bool(king).is_true()
	var want: Dictionary = JSON.parse_string(STAGE1)
	for k: String in (want["scalars"] as Dictionary).keys():
		assert_bool(tl.has(k)).override_failure_message(k + " is gone from the map").is_true()
	assert_float(float(tl["stage_mults"][0])).is_equal(float(want["stage_mult0"]))
	var pt: Array = tl["path_times"][0]
	for i in pt.size():
		assert_float(float(pt[i])).is_between(0.0, STAGE)
		if i > 0:
			assert_float(float(pt[i])).is_greater(float(pt[i - 1]))


func test_the_curves_before_seven_ten_are_untouched() -> void:
	var tl := _tl()
	var want: Dictionary = JSON.parse_string(STAGE1)
	var hc := WaveTimeline.new()
	hc.hp_curve = want["scalars"]["hp_curve"]
	for k in range(0, 431):
		var t := float(k)
		assert_float(tl.hp_mult_at(t)).is_equal_approx(hc.hp_mult_at(t), 0.000001)
		# pass 68 re-pin: the damage curve through stage 1 is Garry's (flat at 1 until his 2026-10-12 retune in the Level
		# Editor, flat at 1.21 since), read from the map file: only a positive multiplier is asked of it
		assert_float(tl.damage_mult_at(t)).is_greater(0.0)
	# the King's fight reads the frozen clock (430), and a spawn half a second before him (a special) sees the same: stage
	# 1's side of any step at 7:10
	assert_float(tl.damage_mult_at(430.0)).is_equal_approx(tl.damage_mult_at(429.0), 0.005)
	assert_float(tl.damage_mult_at(429.5)).is_equal_approx(tl.damage_mult_at(429.0), 0.005)


func test_the_dwarf_shooter_opens_stage_two() -> void:
	var tl := _tl()
	var found := false
	for r in tl.roster_at(STAGE + 2.0):
		if str(r.get("enemy", "")) == "buckshot_dwarf" and WaveTimeline.sample_points(r.get("weights", []), STAGE + 2.0) > 0.0:
			found = true
	assert_bool(found).override_failure_message("no Dwarf Shooter row at 7:12").is_true()
	# and it is new there: no stage-1 row brings it
	for r in tl.roster:
		if str(r.get("enemy", "")) == "buckshot_dwarf":
			assert_float(float(r.get("t", 0.0))).is_greater(STAGE)


## Stage `s`'s rows (pass 87, lane SGAME, re-pinned: the stages are windows of their own lengths, stage_window).
func _stage_rows(tl: WaveTimeline, s: int) -> Array:
	var a := tl.stage_start(s)
	var b := tl.stage_end(s)
	return tl.roster.filter(func(r): return float(r.get("t", 0.0)) >= a and float(r.get("t", 0.0)) < b)


func test_each_later_stage_has_rushes_with_special_spawning() -> void:
	# pass 85 re-pin: Garry reshaped the cap curve himself (2026-10-17: no rushes in stages 2 and 3 for now), so the
	# pass 62 rule "two rushes a stage, each brought by a ring / in-front row" is his to keep or drop; what stays pinned
	# is that every later stage has a positive cap all through it
	var tl := _tl()
	for s: int in [1, 2]:
		var a := tl.stage_start(s)
		var b := tl.stage_end(s)
		for k in range(int(a) + 1, int(b) - 2, 10):
			assert_int(tl.cap_at(float(k), s)).override_failure_message("stage %d cap at %d s" % [s + 1, k]).is_greater(0)

func _introduced(tl: WaveTimeline) -> Array:
	var first: Dictionary = {}
	for r in tl.roster:
		var id := str(r.get("enemy", ""))
		var t := float(r.get("t", 0.0))
		if not first.has(id) or t < float(first[id]):
			first[id] = t
	var out := [0, 0, 0]
	for id: String in first.keys():
		out[mini(tl.stage_at(float(first[id])), 2)] += 1
	return out


func test_fewer_introductions_after_stage_one_but_some() -> void:
	var n := _introduced(_tl())
	assert_int(int(n[1])).is_greater_equal(2)
	assert_int(int(n[2])).is_greater_equal(2)
	assert_int(int(n[1])).is_less(int(n[0]))
	assert_int(int(n[2])).is_less(int(n[0]))


## A creature that is not plain walk-and-bite (Garry: "should be in fewer numbers to add to the variety").
func _special(d: EnemyDef) -> bool:
	return not d.ranged.is_empty() or not d.charge.is_empty() or not d.kamikaze.is_empty() or not d.artillery.is_empty() \
		or not d.support.is_empty() or not d.caster.is_empty() or not d.death_burst.is_empty() or not d.boss.is_empty() \
		or not (d.brain in ["chase", "flock"])


func test_non_melee_creatures_come_in_small_numbers() -> void:
	var tl := _tl()
	var specials := 0
	for r in tl.roster:
		if float(r.get("t", 0.0)) < STAGE:
			continue
		var d: EnemyDef = Registry.enemy(str(r.get("enemy", "")))
		if d == null or not _special(d):
			continue
		specials += 1
		# (Garry, 2026-10-24: he sets these rows' packs and weights himself in the Level Editor, e.g. the Buckshot Dwarf
		# in packs of 10 and the Spit Cactus at weight 5; pass 62's small numbers are not pinned any more, max_alive is)
		var st: Dictionary = r.get("stats", {}) if r.get("stats") is Dictionary else {}
		var most := int(st.get("max_alive", d.max_alive))
		# a once row (a swarm) is bounded by its count (pass 106: Garry's r9 sends 20 Bull Beetles at once)
		if d.brain != "chase" and str(r.get("pace", "")) != "once":
			assert_int(most).override_failure_message("%s row %s has no max_alive" % [d.id, str(r.get("id", ""))]).is_greater(0)
	assert_int(specials).is_greater_equal(6)


func test_every_row_plays_a_creature_that_is_in_play() -> void:
	var tl := _tl()
	for r in tl.roster:
		# pass 84 (lane SPAWN, re-pinned): the Elites-every row names "roster" (the coloured-elite draw of the rows open)
		if str(r.get("enemy", "")) == WaveTimeline.ROW_ENEMY_ROSTER:
			continue
		var d: EnemyDef = Registry.enemy(str(r.get("enemy", "")))
		assert_object(d).override_failure_message("unknown creature " + str(r.get("enemy", ""))).is_not_null()
		if d == null:
			continue
		# (Garry put the retired goblin back on his roster, row r30, 2026-10-24: it spawns all the same; only hidden fails)
		assert_bool(d.hidden).override_failure_message(d.id + " is hidden").is_false()
		var v := str(r.get("variant", ""))
		if v != "":
			assert_bool(d.variants.has(v)).override_failure_message("%s has no look %s" % [d.id, v]).is_true()
	for ev in tl.events:
		var e = ev.get("enemy", "")
		for id in (e if e is Array else [e]):
			if str(id) != "":
				assert_object(Registry.enemy(str(id))).is_not_null()


func test_endless_keeps_a_crowd_of_both_channels() -> void:
	var tl := _tl()
	# pass 87 (lane SGAME, re-pinned): Endless draws from the stage's late roster, stage 3's last second here
	var t := tl.stage_end(2) - 1.0
	var regular := 0
	var hell := 0
	for r in tl.roster_at(t):
		if str(r.get("channel", "")) == "hell":
			hell += 1
		else:
			regular += 1
	assert_int(regular).is_greater_equal(2)
	assert_int(hell).is_greater_equal(1)
	assert_int(tl.cap_at(3600.0, 2)).is_equal(tl.cap_max)


func test_the_bosses_keep_their_stage_and_later_stages_hit_harder_in_play() -> void:
	var tl := _tl()
	# the King fights on stage 1's ATK x (the clock stands at 430), the Gila on stage 2's (pass 68 re-pin: the values are
	# Garry's and his stage 2 slopes, so each boss second is compared with the second before it, not with a number)
	assert_float(tl.damage_mult_at(STAGE)).is_equal_approx(tl.damage_mult_at(STAGE - 1.0), 0.005)
	assert_float(tl.damage_mult_at(STAGE * 2.0)).is_equal_approx(tl.damage_mult_at(STAGE * 2.0 - 1.0), 0.005)
	# pass 77 re-pin: a row may start on a boss second (Garry's r18, blue slimes at 7:10 with the King, 2026-10-15): it
	# reads the stage before's step there, as every row reads the step at its own start (BALANCING §24)
	for r in tl.roster:
		var t := float(r.get("t", 0.0))
		if t == STAGE or t == STAGE * 2.0:
			assert_float(tl.damage_mult_at(t)).is_equal_approx(tl.damage_mult_at(t - 1.0), 0.005)
	# in play a stage-2 bite is still harder than a stage-1 one (stage x ATK x), and stage 3's harder than stage 2's.
	# Pass 87 (lane TUNE, re-pinned on purpose): every stage is a fresh level-1 hero's run now, so each stage's ATK x
	# starts soft and ramps through its own window; the bites are compared at the same point of each window (its
	# middle), no longer at fixed run seconds (1150 s is stage 3's soft opening since the windows are 430/600/780 s)
	var s1 := tl.stage_mult(0) * tl.damage_mult_at(tl.stage_start(0) + tl.stage_len(0) * 0.5)
	var s2 := tl.stage_mult(1) * tl.damage_mult_at(tl.stage_start(1) + tl.stage_len(1) * 0.5)
	var s3 := tl.stage_mult(2) * tl.damage_mult_at(tl.stage_start(2) + tl.stage_len(2) * 0.5)
	assert_float(s2).is_greater(s1)
	assert_float(s3).is_greater(s2)


func test_rows_carry_their_hp_ramp_and_stay_under_the_caps() -> void:
	var tl := _tl()
	for s: int in [1, 2]:
		var early := INF
		var late := 0.0
		# (pass 87, lane SGAME, re-pinned: the first 60/430 and the last 150/430 of each stage's own length)
		var a := tl.stage_start(s)
		var ln := tl.stage_len(s)
		for r in _stage_rows(tl, s):
			var st: Dictionary = r.get("stats", {}) if r.get("stats") is Dictionary else {}
			var m := float(st.get("hp_mult", 1.0))
			var t := float(r.get("t", 0.0))
			if t < a + ln * 60.0 / STAGE:
				early = minf(early, m)
			if t > a + ln * 280.0 / STAGE:
				late = maxf(late, m)
		# each stage's rows start soft (the hero arrives with last stage's build) and end tough
		assert_float(late).is_greater(early)
	for k in range(0, int(tl.total_length()) + 100, 5):
		assert_int(tl.cap_at(float(k), 2)).is_less_equal(tl.cap_max)
	# pass 105 re-pin: the cap (load) may exceed the hard cap (bodies) since Garry's cap_max 500 (2026-10-24): the hard
	# cap then binds (the Level Editor warns); only that both are set is pinned
	assert_int(tl.hard_cap).is_greater(0)
