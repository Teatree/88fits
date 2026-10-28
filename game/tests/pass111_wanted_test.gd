## Pass 111, lane WANTED: the Bounty Board (core/systems/WantedBoard.gd, core/systems/WantedRun.gd (pass 112: the posters
## float over the run, ui/BountyPosters.gd, pass112_wanted_test.gd),
## ui/wanted/WPoster.gd; content/wanted/wanted.json; BALANCING.md 54.WANTED). Garry: "Wanted Poster functionality ... extra
## coin rewards for completing harder tasks ... the weights of each different task probability. Always a choice of 3 ...
## some difficulty score ... scale with Player progression. Should not show locked items, heroes, enemies as a goal ...
## NOT available for Players who are playing for the first time."
##  1. the config has every task type, and a first-time player never sees the board;
##  2. nothing locked, hidden or never met is ever a poster's target;
##  3. the types are drawn by their weights; the editor's chances are exact;
##  4. the numbers grow with progression, the difficulty follows the number, the reward follows both;
##  5. every task type is completed (or failed) by what the run does;
##  6. the reward is paid only when the contract is done, once, at the run's end;
##  7. a board stays the same until a choice is made; a choice forgets it;
##  8. the poster, the pause row and the Results' panel; the real run attaches and settles it.
extends GdUnitTestSuite

const MAP := "red_canyon"


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	WantedBoard.set_config({})


func after_test() -> void:
	WantedBoard.set_config({})
	WantedRun.current = null
	Run.arena = false
	Run.stage_beaten = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map(MAP))
	Run.start_stage(0)


## A tracker on a stand-in game (no enemies, no director, no HUD: the handlers are called by hand).
func _tracker(c: Dictionary) -> WantedRun:
	var fake: Node = auto_free(Node.new())
	add_child(fake)
	var w := WantedRun.new()
	w.game = fake
	w.contract = c
	fake.add_child(w)
	return w


## Every creature, item and boss met and seen (a long-time player's save).
func _meet_everything() -> void:
	for id in Registry.enemies.keys():
		Save.mark_seen("enemy", str(id))
	for id in Registry.weapons.keys():
		Save.mark_seen("weapon", str(id))
	for id in Registry.passives.keys():
		Save.mark_seen("passive", str(id))


# ---------------------------------------------------------------- 1. the config and who sees the board

func test_the_config_has_every_type() -> void:
	var cfg := WantedBoard.config(true)
	assert_bool(bool(cfg["enabled"])).is_true()
	assert_int(int(cfg["choices"])).is_equal(3)
	assert_int(int(cfg["rerolls"])).is_equal(0)
	assert_int(int((cfg["unlock"] as Dictionary)["runs"])).is_greater_equal(1)
	for type: String in WantedBoard.TYPE_ORDER:
		var tc := WantedBoard.task_cfg(cfg, type)
		assert_bool(tc.is_empty()).override_failure_message("no entry for " + type).is_false()
		assert_float(float(tc.get("weight", 0))).override_failure_message(type).is_greater(0.0)
		var dif: Array = tc.get("difficulty", [])
		assert_int(dif.size()).override_failure_message(type).is_equal(2)
		assert_str(str(tc.get("text", ""))).override_failure_message(type).is_not_empty()
		if bool(WantedBoard.TYPES[type]["param"]):
			var ns: Array = tc.get("n", [])
			assert_bool(ns.is_empty()).override_failure_message(type + " rolls a number but has no n").is_false()
	# the type table and the order list name the same types
	assert_int(WantedBoard.TYPE_ORDER.size()).is_equal(WantedBoard.TYPES.size())


func test_a_first_time_player_gets_no_board() -> void:
	Save.data["last_character"] = "drifter"
	Save.data["last_map"] = MAP
	Run.choose_stage(0)
	assert_int(Save.total("runs")).is_equal(0)
	assert_bool(WantedBoard.unlocked()).is_false()
	assert_bool(WantedBoard.due(MAP, 0, "drifter")).is_false()
	# one finished run opens it
	Save.add_total("runs", 1)
	assert_bool(WantedBoard.unlocked()).is_true()
	assert_bool(WantedBoard.due(MAP, 0, "drifter")).is_true()
	# a config that asks for three runs waits for them; one switched off never shows
	var cfg := WantedBoard.config().duplicate(true)
	cfg["unlock"] = {"runs": 3}
	WantedBoard.set_config(cfg)
	assert_bool(WantedBoard.unlocked()).is_false()
	Save.add_total("runs", 2)
	assert_bool(WantedBoard.unlocked()).is_true()
	cfg["enabled"] = false
	WantedBoard.set_config(cfg)
	assert_bool(WantedBoard.unlocked()).is_false()
	assert_bool(WantedBoard.due(MAP, 0, "drifter")).is_false()


# ---------------------------------------------------------------- 2. nothing locked, hidden or unmet

func test_unmet_creatures_and_unseen_items_are_never_targets() -> void:
	Save.add_total("runs", 1)
	var cfg := WantedBoard.config()
	var ctx := WantedBoard.context(MAP, 0, "drifter")
	assert_bool(ctx.is_empty()).is_false()
	# a fresh save has met nobody and seen nothing but the hero's own gun
	assert_array(WantedBoard.targets_of(cfg, "kill_enemy", ctx)).is_empty()
	assert_array(WantedBoard.targets_of(cfg, "boss_fast", ctx)).is_empty()
	assert_array(WantedBoard.targets_of(cfg, "hp_floor", ctx)).is_empty()
	var ws := WantedBoard.targets_of(cfg, "kill_weapon", ctx)
	assert_int(ws.size()).is_equal(1)
	assert_str(str(ws[0]["id"])).is_equal(Registry.start_weapon_for(Registry.character("drifter")).id)
	for k in 200:
		for c: Dictionary in WantedBoard.roll(cfg, ctx, _rng(k)):
			var still: Dictionary = c["still"]
			if str(still.get("kind", "")) == "enemy":
				assert_bool(Save.enemy_met(str(still["id"]))).override_failure_message("unmet still " + str(still["id"])).is_true()
			assert_bool(["kill_enemy", "boss_fast", "hp_floor"].has(c["type"])).override_failure_message(str(c["type"])).is_false()


func test_locked_and_hidden_things_never_come_even_when_met() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config()
	var seen_types := {}
	for stage in 3:
		var ctx := WantedBoard.context(MAP, stage, "drifter")
		for k in 150:
			for c: Dictionary in WantedBoard.roll(cfg, ctx, _rng(stage * 1000 + k)):
				seen_types[c["type"]] = true
				var id := str(c["target"])
				match str(c["target_kind"]):
					"enemy", "boss":
						var d: EnemyDef = Registry.enemy(id)
						assert_object(d).is_not_null()
						assert_bool(d.hidden or d.retired).override_failure_message(id).is_false()
						assert_bool(Save.enemy_met(id)).override_failure_message(id).is_true()
					"weapon":
						var w: WeaponDef = Registry.weapon(id)
						assert_object(w).is_not_null()
						var own := w.id == Registry.start_weapon_for(Registry.character("drifter")).id
						assert_bool(own or (not w.hidden and Registry.is_unlocked("weapon", id))).override_failure_message("locked or hidden " + id).is_true()
						assert_bool(w.hero == "" or w.hero == "drifter").override_failure_message("another hero's gun " + id).is_true()
					"card":
						var p: PassiveDef = Registry.passive(id)
						assert_object(p).is_not_null()
						assert_bool(p.hidden or not Registry.is_unlocked("passive", id)).override_failure_message("locked card " + id).is_false()
				# a hero on a poster is the run's own (owned: he was chosen to play)
				var still: Dictionary = c["still"]
				if str(still.get("kind", "")) == "hero":
					assert_str(str(still["id"])).is_equal("drifter")
	# met everything: every type turns up somewhere
	for type: String in WantedBoard.TYPE_ORDER:
		assert_bool(seen_types.has(type)).override_failure_message("never rolled: " + type).is_true()


func test_a_quest_locked_weapon_is_never_a_target() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var locked: Array = []
	for w: WeaponDef in Registry.base_weapons():
		if not w.hidden and not Registry.is_unlocked("weapon", w.id):
			locked.append(w.id)
	var ctx := WantedBoard.context(MAP, 2, "drifter")
	var start_id := Registry.start_weapon_for(Registry.character("drifter")).id
	for w: Dictionary in ctx["weapons"]:
		if str(w["id"]) != start_id:
			assert_bool(locked.has(w["id"])).override_failure_message("locked weapon offered: " + str(w["id"])).is_false()


# ---------------------------------------------------------------- 3. the weights

func _ctx_plain() -> Dictionary:
	return {"map": MAP, "stage": 0, "stage_name": "Sundown", "P": 0, "beaten": false,
		"hero": {"id": "drifter", "name": "The Drifter", "start": "revolver"}, "boss": {}, "creatures": [], "gear": [],
		"elite_boss": [], "elite_estimate": 0, "weapons": [], "cards": []}


func test_the_types_come_by_their_weights() -> void:
	var cfg := {"choices": 1, "tasks": [
		{"type": "kill_total", "weight": 1, "difficulty": [1, 2], "n": [[100, 200]], "step": 10, "text": "a"},
		{"type": "open_chests", "weight": 2, "difficulty": [1, 2], "n": [[4, 8]], "step": 1, "text": "b"},
		{"type": "collect_coins", "weight": 7, "difficulty": [1, 2], "n": [[100, 300]], "step": 25, "text": "c"},
		{"type": "hero_level", "on": false, "weight": 50, "difficulty": [1, 2], "n": [[10, 20]], "step": 1, "text": "d"}]}
	cfg = WantedBoard.normalized(cfg)
	var ctx := _ctx_plain()
	var count := {"kill_total": 0, "open_chests": 0, "collect_coins": 0, "hero_level": 0}
	var rng := _rng(111)
	var n := 6000
	for k in n:
		var b := WantedBoard.roll(cfg, ctx, rng)
		assert_int(b.size()).is_equal(1)
		count[b[0]["type"]] += 1
	assert_int(int(count["hero_level"])).is_equal(0)
	assert_float(float(count["kill_total"]) / n).is_equal_approx(0.1, 0.02)
	assert_float(float(count["open_chests"]) / n).is_equal_approx(0.2, 0.025)
	assert_float(float(count["collect_coins"]) / n).is_equal_approx(0.7, 0.025)
	# the editor's chances: the first poster's share of the weight; with one poster, the board's chance is the same
	var ch := WantedBoard.type_chances(cfg, ctx)
	assert_float(float(ch["collect_coins"]["first"])).is_equal_approx(0.7, 0.0001)
	assert_float(float(ch["kill_total"]["board"])).is_equal_approx(0.1, 0.0001)
	assert_bool(ch.has("hero_level")).is_false()


func test_three_posters_are_three_types_and_the_board_chances_add_up() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config()
	var ctx := WantedBoard.context(MAP, 1, "drifter")
	var el := WantedBoard.eligible_types(cfg, ctx)
	assert_int(el.size()).is_greater_equal(3)
	var hits := {}
	var rng := _rng(7)
	var n := 3000
	for k in n:
		var b := WantedBoard.roll(cfg, ctx, rng)
		assert_int(b.size()).is_equal(3)
		var types := {}
		for c: Dictionary in b:
			types[c["type"]] = true
			hits[c["type"]] = int(hits.get(c["type"], 0)) + 1
		assert_int(types.size()).is_equal(3)
	var ch := WantedBoard.type_chances(cfg, ctx)
	var total := 0.0
	for t in ch.keys():
		total += float(ch[t]["board"])
		# the exact chance against the rolls
		assert_float(float(hits.get(t, 0)) / n).override_failure_message(str(t)).is_equal_approx(float(ch[t]["board"]), 0.035)
	assert_float(total).is_equal_approx(3.0, 0.0001)


# ---------------------------------------------------------------- 4. numbers, difficulty, reward

func test_the_reward_follows_difficulty_progression_and_stage() -> void:
	var cfg := WantedBoard.config()
	# (base 40 + 60 a point) x (1 + 0.5 x P) x the stage's [1, 1.25, 1.5], to 5 (wanted_model.js pins the same numbers)
	assert_int(WantedBoard.reward_for(cfg, 1.0, 0, 0)).is_equal(100)
	assert_int(WantedBoard.reward_for(cfg, 3.0, 0, 0)).is_equal(220)
	assert_int(WantedBoard.reward_for(cfg, 2.5, 2, 1)).is_equal(475)
	assert_int(WantedBoard.reward_for(cfg, 4.5, 3, 2)).is_equal(1165)
	assert_int(WantedBoard.reward_for(cfg, 1.3, 1, 0)).is_equal(175)
	var last := 0
	for d in [1.0, 1.5, 2.0, 3.0, 4.0, 5.0]:
		var r := WantedBoard.reward_for(cfg, d, 0, 0)
		assert_int(r).is_greater(last)
		assert_int(r % 5).is_equal(0)
		last = r
	for p in 3:
		assert_int(WantedBoard.reward_for(cfg, 2.0, p + 1, 0)).is_greater(WantedBoard.reward_for(cfg, 2.0, p, 0))
		assert_int(WantedBoard.reward_for(cfg, 2.0, 0, p if p < 2 else 2)).is_less_equal(WantedBoard.reward_for(cfg, 2.0, 0, mini(p + 1, 2)))


func test_the_numbers_grow_with_progression_and_the_difficulty_follows_them() -> void:
	var cfg := WantedBoard.config()
	var kt := WantedBoard.task_cfg(cfg, "kill_total")
	var r0 := WantedBoard.scaled_range(cfg, "kill_total", kt, 0, 0)
	var r3 := WantedBoard.scaled_range(cfg, "kill_total", kt, 0, 3)
	assert_float(r3.x).is_greater(r0.x)
	assert_float(r3.y).is_greater(r0.y)
	# a later stage asks more
	assert_float(WantedBoard.scaled_range(cfg, "kill_total", kt, 2, 0).y).is_greater(r0.y)
	# where a lower number is harder (the boss's seconds) progression shortens it
	var bf := WantedBoard.task_cfg(cfg, "boss_fast")
	assert_float(WantedBoard.scaled_range(cfg, "boss_fast", bf, 0, 3).x).is_less(WantedBoard.scaled_range(cfg, "boss_fast", bf, 0, 0).x)
	# the health floor never passes its max
	var hf := WantedBoard.task_cfg(cfg, "hp_floor")
	assert_float(WantedBoard.scaled_range(cfg, "hp_floor", hf, 0, 30).y).is_less_equal(float(hf["max"]))
	# the difficulty: the easy end at the easy end of the range, the hard end at the hard end
	var r := Vector2(100, 200)
	assert_float(WantedBoard.difficulty_of(1.0, 3.0, 100, r, false)).is_equal(1.0)
	assert_float(WantedBoard.difficulty_of(1.0, 3.0, 200, r, false)).is_equal(3.0)
	assert_float(WantedBoard.difficulty_of(1.0, 3.0, 150, r, false)).is_equal(2.0)
	assert_float(WantedBoard.difficulty_of(1.0, 3.0, 100, r, true)).is_equal(3.0)
	assert_float(WantedBoard.difficulty_of(1.0, 3.0, 40, r, false)).is_equal(1.0)
	assert_float(WantedBoard.difficulty_of(2.0, 4.0, 5, Vector2(5, 5), false)).is_equal(3.0)
	assert_int(WantedBoard.skulls_of(0.4)).is_equal(1)
	assert_int(WantedBoard.skulls_of(2.6)).is_equal(3)
	assert_int(WantedBoard.skulls_of(9.0)).is_equal(5)
	# a rolled poster pays what its difficulty says
	Save.add_total("runs", 1)
	_meet_everything()
	var ctx := WantedBoard.context(MAP, 0, "drifter")
	for k in 60:
		for c: Dictionary in WantedBoard.roll(cfg, ctx, _rng(500 + k)):
			assert_int(int(c["reward"])).is_equal(WantedBoard.reward_for(cfg, float(c["d"]), int(c["P"]), int(c["stage"])))
			assert_int(int(c["skulls"])).is_equal(WantedBoard.skulls_of(float(c["d"])))


func test_a_creature_is_never_asked_for_more_than_its_time_on_the_roster_allows() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config()
	var cap := float(WantedBoard.task_cfg(cfg, "kill_enemy")["per_minute_cap"])
	for stage in 3:
		var ctx := WantedBoard.context(MAP, stage, "drifter")
		var secs := {}
		for cr: Dictionary in ctx["creatures"]:
			secs[cr["id"]] = float(cr["seconds"])
		for k in 120:
			var c := WantedBoard.make_contract(cfg, "kill_enemy", ctx, _rng(stage * 77 + k))
			if c.is_empty():
				continue
			assert_float(float(c["n"])).override_failure_message(str(c["target"])).is_less_equal(maxf(cap * float(secs[c["target"]]) / 60.0, 5.0))
	# the Elites asked for never pass what the stage brings
	for stage in 3:
		var ctx2 := WantedBoard.context(MAP, stage, "drifter")
		for k in 40:
			var e := WantedBoard.make_contract(cfg, "kill_elites", ctx2, _rng(k))
			if not e.is_empty():
				assert_int(int(e["n"])).is_less_equal(maxi(int(ctx2["elite_estimate"]), 1))


# ---------------------------------------------------------------- 5. every type is done by the run

func _c(type: String, n: int, target: String = "") -> Dictionary:
	return {"type": type, "n": n, "target": target, "reward": 200, "d": 2.0, "name": type, "text": "t", "still": {}}


func test_every_type_is_completed_by_what_the_run_does() -> void:
	_start("drifter")
	# kill N of a creature
	var w := _tracker(_c("kill_enemy", 3, "skeleton"))
	w.check()
	assert_bool(w.done).is_false()
	Run.kills_by_enemy["skeleton"] = 3
	w.check()
	assert_bool(w.done).is_true()
	# kill N with a weapon: its evolution's kills count too
	var rev: WeaponDef = Registry.weapon("revolver")
	w = _tracker(_c("kill_weapon", 10, "revolver"))
	Run.kills_by_weapon["revolver"] = 6
	w.check()
	assert_bool(w.done).is_false()
	if rev.evolves_into != "":
		Run.kills_by_weapon[rev.evolves_into] = 4
	else:
		Run.kills_by_weapon["revolver"] = 10
	w.check()
	assert_bool(w.done).is_true()
	# specials and Elites, counted as they die
	w = _tracker(_c("kill_specials", 2))
	var gear: EnemyDef = null
	for d: EnemyDef in Registry.enemies.values():
		if d.badge_for() == "gear" and not d.hidden:
			gear = d
			break
	assert_object(gear).is_not_null()
	w._on_died(gear, Vector3.ZERO, null, "")
	w.check()
	assert_bool(w.done).is_false()
	w._on_died(gear, Vector3.ZERO, null, "")
	w.check()
	assert_bool(w.done).is_true()
	w = _tracker(_c("kill_elites", 2))
	w._on_died(Registry.enemy("dune_scorpion"), Vector3.ZERO, null, "")
	w._on_died(Registry.enemy("goblin"), Vector3.ZERO, Registry.elites.values()[0], "")
	w._on_died(Registry.enemy("goblin"), Vector3.ZERO, null, "")
	w.check()
	assert_bool(w.done).is_true()
	assert_int(w.progress().x).is_equal(2)
	# kills in all
	w = _tracker(_c("kill_total", 50))
	Run.kills = 50
	w.check()
	assert_bool(w.done).is_true()
	# a hero level
	w = _tracker(_c("hero_level", 12))
	Run.max_level_reached = 11
	w.check()
	assert_bool(w.done).is_false()
	Run.max_level_reached = 12
	w.check()
	assert_bool(w.done).is_true()
	# chests and gold
	w = _tracker(_c("open_chests", 4))
	Run.chests_opened = 4
	w.check()
	assert_bool(w.done).is_true()
	w = _tracker(_c("collect_coins", 100))
	Run.add_gold(60, "coins")
	w.check()
	assert_bool(w.done).is_false()
	Run.add_gold(40, "coins")
	w.check()
	assert_bool(w.done).is_true()
	# a weapon to its top level
	w = _tracker(_c("max_weapon", rev.max_level, "revolver"))
	var inst := Run.add_weapon(rev, 1)
	w.check()
	assert_bool(w.done).is_false()
	inst.level = rev.max_level
	w.check()
	assert_bool(w.done).is_true()
	# a card evolved (its evolved form held)
	var line: PassiveDef = null
	for p: PassiveDef in Registry.sorted_lines():
		if p.evolves_into != "" and Registry.passive(p.evolves_into) != null:
			line = p
			break
	assert_object(line).is_not_null()
	w = _tracker(_c("evolve_item", 1, line.id))
	Run.passives[line.id] = 1
	w.check()
	assert_bool(w.done).is_false()
	Run.passives.erase(line.id)
	Run.passives[line.evolves_into] = 1
	w.check()
	assert_bool(w.done).is_true()


func test_the_stage_the_boss_and_the_health_floor() -> void:
	_start("drifter")
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	# beat the stage
	var w := _tracker(_c("beat_stage", 1))
	w.check()
	assert_bool(w.done).is_false()
	Run.stage_beaten = true
	w.check()
	assert_bool(w.done).is_true()
	Run.stage_beaten = false
	# the health floor: kept above it to the boss's death
	w = _tracker(_c("hp_floor", 50, "tumbleweed_king"))
	w._min_hp = 0.55
	w.check()
	assert_bool(w.done or w.failed).is_false()
	Run.stage_beaten = true
	w.check()
	assert_bool(w.done).is_true()
	Run.stage_beaten = false
	# ... and failed the moment it drops under, even if the stage is beaten after
	w = _tracker(_c("hp_floor", 50, "tumbleweed_king"))
	w._min_hp = 0.49
	w.check()
	assert_bool(w.failed).is_true()
	Run.stage_beaten = true
	w.check()
	assert_bool(w.done).is_false()
	Run.stage_beaten = false
	# the boss in time: done when he dies inside the seconds
	w = _tracker(_c("boss_fast", 60, "tumbleweed_king"))
	w._on_boss_started(king)
	w._on_boss_died(king, Vector3.ZERO)
	assert_bool(w.done).is_true()
	# ... failed once his seconds run out with him alive
	w = _tracker(_c("boss_fast", 60, "tumbleweed_king"))
	w._on_boss_started(king)
	w._boss_t0 = Run.run_time() - 61.0
	w.check()
	assert_bool(w.failed).is_true()
	# ... and another boss's death counts for nothing
	w = _tracker(_c("boss_fast", 60, "tumbleweed_king"))
	w._on_boss_started(Registry.enemy("gila_grande"))
	w._on_boss_died(Registry.enemy("gila_grande"), Vector3.ZERO)
	assert_bool(w.done or w.failed).is_false()


# ---------------------------------------------------------------- 6. paid only when done

func test_the_reward_is_paid_only_when_done_and_once() -> void:
	_start("drifter")
	Run.last_result = {}
	var before := Save.gold()
	var w := _tracker(_c("kill_total", 10))
	WantedRun.current = w
	var rec := WantedRun.settle()
	assert_int(int(rec["paid"])).is_equal(0)
	assert_bool(bool(rec["done"])).is_false()
	assert_int(Save.gold()).is_equal(before)
	assert_int(int((Run.last_result["bounty"] as Dictionary)["paid"])).is_equal(0)
	Run.kills = 10
	var moved: Array = []
	var cb := func(delta: int, reason: String, _balance: int, _extra: Dictionary) -> void: moved.append([delta, reason])
	Save.gold_moved.connect(cb)
	rec = WantedRun.settle()
	Save.gold_moved.disconnect(cb)
	assert_bool(bool(rec["done"])).is_true()
	assert_int(int(rec["paid"])).is_equal(200)
	assert_int(Save.gold()).is_equal(before + 200)
	assert_array(moved).is_equal([[200, WantedBoard.GOLD_SOURCE]])
	assert_int(int(WantedBoard.store()["done"])).is_equal(1)
	assert_int(int(WantedBoard.store()["paid"])).is_equal(200)
	# never twice
	WantedRun.settle()
	assert_int(Save.gold()).is_equal(before + 200)
	# a failed contract pays nothing
	var f := _tracker(_c("hp_floor", 50, "tumbleweed_king"))
	f._min_hp = 0.1
	WantedRun.current = f
	var g0 := Save.gold()
	rec = WantedRun.settle()
	assert_bool(bool(rec["failed"])).is_true()
	assert_int(int(rec["paid"])).is_equal(0)
	assert_int(Save.gold()).is_equal(g0)
	# no contract: nothing settles
	WantedRun.current = null
	assert_bool(WantedRun.settle().is_empty()).is_true()


# ---------------------------------------------------------------- 7. a board stays until a choice

func test_a_board_stays_the_same_until_a_choice_is_made() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var a := WantedBoard.board_for(MAP, 0, "drifter", _rng(1))
	var b := WantedBoard.board_for(MAP, 0, "drifter", _rng(2))
	assert_int(a.size()).is_equal(3)
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(b))
	# another hero or stage is a board of its own
	var other := WantedBoard.board_for(MAP, 1, "drifter", _rng(3))
	assert_int(other.size()).is_equal(3)
	# a choice forgets every kept board and counts a poster taken; "No bounty" counts nothing
	WantedBoard.choose(a[1])
	assert_bool((WantedBoard.store()["boards"] as Dictionary).is_empty()).is_true()
	assert_int(int(WantedBoard.store()["taken"])).is_equal(1)
	WantedBoard.board_for(MAP, 0, "drifter", _rng(4))
	WantedBoard.choose({})
	assert_bool((WantedBoard.store()["boards"] as Dictionary).is_empty()).is_true()
	assert_int(int(WantedBoard.store()["taken"])).is_equal(1)
	# a new board after the choice is a new roll (kept again)
	var c := WantedBoard.board_for(MAP, 0, "drifter", _rng(99))
	assert_int(c.size()).is_equal(3)
	assert_bool((WantedBoard.store()["boards"] as Dictionary).has("%s|0|drifter" % MAP)).is_true()
	# no re-rolls by default
	assert_int(WantedBoard.rerolls_left(MAP, 0, "drifter")).is_equal(0)
	assert_array(WantedBoard.reroll(MAP, 0, "drifter")).is_empty()


func test_rerolls_when_the_config_gives_some() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config().duplicate(true)
	cfg["rerolls"] = 1
	WantedBoard.set_config(cfg)
	WantedBoard.board_for(MAP, 0, "drifter", _rng(5))
	assert_int(WantedBoard.rerolls_left(MAP, 0, "drifter")).is_equal(1)
	var fresh := WantedBoard.reroll(MAP, 0, "drifter")
	assert_int(fresh.size()).is_equal(3)
	assert_int(WantedBoard.rerolls_left(MAP, 0, "drifter")).is_equal(0)
	assert_array(WantedBoard.reroll(MAP, 0, "drifter")).is_empty()


# ---------------------------------------------------------------- 8. the pictures and the screens

func test_the_poster_shows_its_contract_with_real_art() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config()
	var ctx := WantedBoard.context(MAP, 0, "drifter")
	var seen_kinds := {}
	for type: String in WantedBoard.TYPE_ORDER:
		var c := WantedBoard.make_contract(cfg, type, ctx, _rng(3))
		if c.is_empty():
			continue
		var p: WPoster = auto_free(WPoster.make(c))
		add_child(p)
		await get_tree().process_frame
		var still := WPoster.still_texture(c["still"])
		assert_object(still).override_failure_message("no picture for " + type).is_not_null()
		seen_kinds[str((c["still"] as Dictionary).get("kind", ""))] = true
		assert_str(str((p.find_child("Name", true, false) as WText).text)).is_equal(str(c["name"]).to_upper())
		assert_str(str((p.find_child("Task", true, false) as WText).text)).is_equal(str(c["text"]))
		assert_str(str((p.find_child("Amount", true, false) as WText).text)).is_equal(W.num(int(c["reward"])))
		var lit := 0
		for s in (p.find_child("Skulls", true, false) as Control).get_children():
			if bool(s.get_meta("lit", false)):
				lit += 1
		assert_int(lit).is_equal(int(c["skulls"]))
	# a creature's front still, a weapon's icon, the hero's cut-out, the stage's picture, the chest and the coin
	for k in ["enemy", "weapon", "hero", "stage", "art"]:
		assert_bool(seen_kinds.has(k)).override_failure_message("no poster drew a " + k).is_true()
	# the front still is the first cell of the played look's strip
	var sk: EnemyDef = Registry.enemy("skeleton")
	var fs := WPoster.front_still(sk)
	assert_object(fs).is_not_null()
	assert_float((fs as AtlasTexture).region.position.x).is_equal(0.0)
	assert_float((fs as AtlasTexture).region.size.x).is_less(float(sk.sprite.get_width()))


func test_the_pause_row_and_the_results_panel() -> void:
	_start("drifter")
	var w := _tracker(_c("kill_total", 60))
	WantedRun.current = w
	Run.kills = 34
	w.check()
	assert_str(w.progress_text()).is_equal("34 / 60")
	var row: Control = auto_free(WantedRun.pause_row())
	assert_object(row).is_not_null()
	assert_str(str((row.find_child("Right", true, false) as WText).text)).is_equal("34 / 60")
	var paid: Control = auto_free(WantedRun.results_panel({"name": "x", "text": "y", "paid": 240, "done": true, "have": 60, "need": 60}))
	assert_str(str((paid.find_child("Right", true, false) as WText).text)).is_equal("+240")
	var lost: Control = auto_free(WantedRun.results_panel({"name": "x", "text": "y", "paid": 0, "failed": true}))
	assert_str(str((lost.find_child("Right", true, false) as WText).text)).is_equal("FAILED")
	var short: Control = auto_free(WantedRun.results_panel({"name": "x", "text": "y", "paid": 0, "have": 34, "need": 60}))
	assert_str(str((short.find_child("Right", true, false) as WText).text)).is_equal("34 / 60")
	assert_object(WantedRun.results_panel({})).is_null()


func test_a_real_run_attaches_the_pick_shows_the_plate_and_settles() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": MAP, "map_seed": 11, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.4).timeout
	# pass 112: the contract the floating posters hand over (Game._on_bounty_taken)
	g._on_bounty_taken({"type": "kill_total", "n": 1, "target": "", "reward": 150, "d": 1.0, "skulls": 1, "name": "Sundown",
		"text": "Kill 1 creatures", "stage": 0, "map": MAP, "hero": "drifter", "P": 0, "still": {"kind": "art", "id": "chest"}})
	assert_object(WantedRun.current).is_not_null()
	WantedRun.current.pop_plate()
	assert_object(WantedRun.current.plate()).is_not_null()
	assert_bool(WantedRun.current.plate().get_parent() == g.hud).is_true()
	g.director.stop()
	Run.kills = 1
	WantedRun.current.check()
	assert_bool(WantedRun.current.done).is_true()
	var before := Save.gold()
	Run.last_result = {}
	var rec := WantedRun.settle()
	assert_int(int(rec["paid"])).is_equal(150)
	assert_int(Save.gold()).is_equal(before + 150)
	assert_int(int((Run.last_result["bounty"] as Dictionary)["paid"])).is_equal(150)
