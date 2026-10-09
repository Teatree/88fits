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
const STAGE1 := """{"cap":[[0,10],[63,27],[122,45],[123,80],[176,80],[176,45],[213,56],[232,84],[306,79],[306,132],[337,132],[337,73],[368,72],[430,100]],"rows":[{"id":"r1","t":0,"enemy":"red_goblin","weights":[[0,9],[59,5.1],[63,8.8],[118,8.4]],"stats":{"elite":{"hp_mult_per_stage":0}},"until":122,"variant":"RG-B"},{"id":"r2","t":0,"enemy":"red_goblin_runt","weights":[[0,3],[60,3.7]],"until":59},{"id":"r18","t":58,"enemy":"blue_slime","weights":[[58,2.5],[121,2.5]],"until":123,"stats":{"hp":40}},{"id":"r3","t":123,"enemy":"lesser_scorpion","weights":[[121,8],[174,7.6]],"until":176,"pattern":"in_front","pack":100,"stats":{"speed":1.5,"hp_mult":1.2}},{"id":"r12","t":176,"enemy":"skeleton","weights":[[177,6.7]],"until":285,"stats":{"hp":20}},{"id":"r13","t":176,"enemy":"skeleton_knight","weights":[[177,2.9]],"until":306,"stats":{"hp":35},"pattern":"scatter"},{"id":"r14","t":176,"enemy":"spit_cactus","weights":[[177,1.8]],"until":234,"pattern":"scatter"},{"id":"r17","t":368,"enemy":"spit_cactus","weights":[[369,1.2]],"until":430,"pattern":"scatter"},{"id":"r15","t":250,"enemy":"bull_beetle","weights":[[250,1]],"until":368,"pattern":"scatter"},{"id":"r16","t":306,"enemy":"werewolf","weights":[[306,5.4]],"until":430,"stats":{"hp":20,"size":1.4},"pattern":"ring"}],"events":[{"t":215,"type":"elite_boss","enemy":["dune_scorpion","sun_prophet","stone_golem"]},{"t":301,"type":"elite_every","interval":129},{"t":430,"type":"boss","enemy":"tumbleweed_king"}],"scalars":{"level_hp_per_level":0.05,"level_damage_per_level":0.03,"creature_hp_mult":1.3,"creature_damage_mult":1.25,"creature_speed_mult":0.9,"stage_length":430,"contact_cap":0.22,"xp_need_mult":2.1,"move_pace":0.9,"colour_after_kills":50,"boss_cap_frac":0.6,"hard_cap":260,"cap_max":150,"burst_min":3,"burst_max":12,"spawn_interval":0.7,"spawn_sides":{"mode":"facing","top":55,"bottom":15,"left":15,"right":15,"facing_share":0.7,"facing_spread_deg":60},"specials":{"from":215,"interval":[64,86],"max_alive":1,"pool":[{"enemy":"rocketeer"},{"enemy":"harpoon_troglodyte","stage":2}]},"pickups":{"per_kill":0.0045,"roster":[{"id":"heart","weight":6,"hard_bias":0.0},{"id":"rage","weight":3,"hard_bias":0.5},{"id":"sprint","weight":3,"hard_bias":0.3},{"id":"shield","weight":2,"hard_bias":0.8},{"id":"magnet_pulse","weight":2,"hard_bias":0.6},{"id":"nuke","weight":2,"hard_bias":0.8}]},"hp_curve":{"mode":"formula","formula":{"kind":"power","a":0.0977,"b":1.25},"points":[[0,1.0],[430,1.9414],[860,2.9878],[1290,4.1143]]},"portal_wave":{"count":12},"portal_cap":-1,"portal_spawn_seconds":-1},"stage_mult0":1.0,"path_times0":[79,140,200,260,315,365,405]}"""


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
	var want: Dictionary = JSON.parse_string(STAGE1)
	var tl: Dictionary = _json()["timeline_data"]
	var cap: Array = []
	var seen := false
	for p in tl["cap_curve"]:
		if float(p[0]) < STAGE or (float(p[0]) == STAGE and not seen):
			cap.append(p)
			seen = seen or float(p[0]) == STAGE
	var why := _same(cap, want["cap"])
	assert_str(why).override_failure_message("cap points to 7:10: " + why).is_empty()
	var rows: Array = (tl["roster"] as Array).filter(func(r): return float(r.get("t", 0.0)) < STAGE)
	why = _same(rows, want["rows"])
	assert_str(why).override_failure_message("stage-1 rows: " + why).is_empty()
	# his events to 7:10, the King at 430 included
	var evs: Array = (tl["events"] as Array).filter(func(e): return float(e.get("t", 0.0)) <= STAGE)
	why = _same(evs, want["events"])
	assert_str(why).override_failure_message("stage-1 events: " + why).is_empty()
	for k: String in (want["scalars"] as Dictionary).keys():
		why = _same(tl[k], want["scalars"][k])
		assert_str(why).override_failure_message(k + ": " + why).is_empty()
	assert_float(float(tl["stage_mults"][0])).is_equal(float(want["stage_mult0"]))
	why = _same(tl["path_times"][0], want["path_times0"])
	assert_str(why).override_failure_message("path_times[0]: " + why).is_empty()
	# no stage-1 row was stretched past 7:10
	for r in rows:
		assert_float(float(r.get("until", 1e9))).is_less_equal(STAGE)


func test_the_curves_before_seven_ten_are_untouched() -> void:
	var tl := _tl()
	var want: Dictionary = JSON.parse_string(STAGE1)
	var hc := WaveTimeline.new()
	hc.hp_curve = want["scalars"]["hp_curve"]
	for k in range(0, 431):
		var t := float(k)
		assert_float(tl.hp_mult_at(t)).is_equal_approx(hc.hp_mult_at(t), 0.000001)
		# the damage curve was flat at 1; it still is up to the King's second (his fight reads the frozen clock, 430)
		assert_float(tl.damage_mult_at(t)).is_equal_approx(1.0, 0.000001)
	# a spawn half a second before the boss (a special) still sees stage 1's value
	assert_float(tl.damage_mult_at(429.5)).is_equal_approx(1.0, 0.000001)


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


func _stage_rows(tl: WaveTimeline, s: int) -> Array:
	var a := STAGE * s
	var b := STAGE * (s + 1)
	return tl.roster.filter(func(r): return float(r.get("t", 0.0)) >= a and float(r.get("t", 0.0)) < b)


func test_each_later_stage_has_rushes_with_special_spawning() -> void:
	var tl := _tl()
	for s: int in [1, 2]:
		var a := STAGE * s
		var b := STAGE * (s + 1)
		var rushes := 0
		for k in range(int(a) + 1, int(b) - 2):
			var before := tl.cap_at(float(k) - 0.5, s)
			var after := tl.cap_at(float(k) + 1.5, s)
			if after >= before * 1.4 and after - before >= 30:
				rushes += 1
				# a ring or in-front row brings the rush
				var special := false
				for r in tl.roster_at(float(k) + 1.5):
					if str(r.get("pattern", "")) in ["ring", "in_front"] and WaveTimeline.sample_points(r.get("weights", []), float(k) + 1.5) > 0.0:
						special = true
				assert_bool(special).override_failure_message("stage %d rush at %d s has no ring / in-front row" % [s + 1, k]).is_true()
		assert_int(rushes).override_failure_message("stage %d has no cap rush" % (s + 1)).is_greater_equal(2)
		# and quieter stretches: the cap drops back after a rush
		var lows := 0
		for k in range(int(a) + 1, int(b) - 2):
			if tl.cap_at(float(k) + 1.5, s) <= tl.cap_at(float(k) - 0.5, s) * 0.7:
				lows += 1
		assert_int(lows).is_greater_equal(2)


func _introduced(tl: WaveTimeline) -> Array:
	var first: Dictionary = {}
	for r in tl.roster:
		var id := str(r.get("enemy", ""))
		var t := float(r.get("t", 0.0))
		if not first.has(id) or t < float(first[id]):
			first[id] = t
	var out := [0, 0, 0]
	for id: String in first.keys():
		out[mini(int(float(first[id]) / STAGE), 2)] += 1
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
		var pack := int(r.get("pack", d.pack_size))
		assert_int(pack).override_failure_message("%s row %s packs %d" % [d.id, str(r.get("id", "")), pack]).is_less_equal(2)
		for p in r.get("weights", []):
			assert_float(float(p[1])).override_failure_message("%s row %s weight %s" % [d.id, str(r.get("id", "")), str(p[1])]).is_less_equal(1.5)
		var st: Dictionary = r.get("stats", {}) if r.get("stats") is Dictionary else {}
		var most := int(st.get("max_alive", d.max_alive))
		if d.brain != "chase":
			assert_int(most).override_failure_message("%s row %s has no max_alive" % [d.id, str(r.get("id", ""))]).is_greater(0)
	assert_int(specials).is_greater_equal(6)


func test_every_row_plays_a_creature_that_is_in_play() -> void:
	var tl := _tl()
	for r in tl.roster:
		var d: EnemyDef = Registry.enemy(str(r.get("enemy", "")))
		assert_object(d).override_failure_message("unknown creature " + str(r.get("enemy", ""))).is_not_null()
		assert_bool(d.retired or d.hidden).override_failure_message(d.id + " is retired or hidden").is_false()
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
	var t := STAGE * 3.0 + 200.0
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
	# the King fights on stage 1's ATK x (the clock stands at 430), the Gila on stage 2's
	assert_float(tl.damage_mult_at(STAGE)).is_equal_approx(1.0, 0.000001)
	assert_float(tl.damage_mult_at(STAGE * 2.0)).is_equal_approx(tl.damage_mult_at(STAGE * 2.0 - 1.0), 0.000001)
	# every stage-2 / stage-3 row starts after its stage's boss second, so it reads its own stage's step
	for r in tl.roster:
		var t := float(r.get("t", 0.0))
		assert_bool(t != STAGE and t != STAGE * 2.0).override_failure_message("row %s starts on a boss second" % str(r.get("id", ""))).is_true()
	# in play a stage-2 bite is still harder than a stage-1 one (stage x ATK x), and stage 3's harder than stage 2's
	var s1 := tl.stage_mult(0) * tl.damage_mult_at(300.0)
	var s2 := tl.stage_mult(1) * tl.damage_mult_at(700.0)
	var s3 := tl.stage_mult(2) * tl.damage_mult_at(1150.0)
	assert_float(s2).is_greater(s1)
	assert_float(s3).is_greater(s2)


func test_rows_carry_their_hp_ramp_and_stay_under_the_caps() -> void:
	var tl := _tl()
	for s: int in [1, 2]:
		var early := INF
		var late := 0.0
		for r in _stage_rows(tl, s):
			var st: Dictionary = r.get("stats", {}) if r.get("stats") is Dictionary else {}
			var m := float(st.get("hp_mult", 1.0))
			var t := float(r.get("t", 0.0))
			if t < STAGE * s + 60.0:
				early = minf(early, m)
			if t > STAGE * s + 280.0:
				late = maxf(late, m)
		# each stage's rows start soft (the hero arrives with last stage's build) and end tough
		assert_float(late).is_greater(early)
	for k in range(0, 1400, 5):
		assert_int(tl.cap_at(float(k), 2)).is_less_equal(tl.cap_max)
	assert_int(tl.hard_cap).is_equal(260)
