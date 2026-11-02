extends GdUnitTestSuite

## Pass 119, lane LEGEND_A (Garry: the Iron Horse, "our most powerful one yet", foreshadowed, animated start to finish,
## knocking back what it runs over; Personal Storm, clouds rolling in and lightning "with a preference for enemy
## groups", marks that fade; the two "quietly mutually exclusive ... they won't get the other offered to them again
## (anywhere)"). The timers, the damage shares, the knockback, the strike spots' weighting, the exclusion in every offer
## path and the hero never hit.

const DT := 1.0 / 60.0

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var max_hp := 100.0
var hp := 100.0
var hits := 0
var pushes := 0
var fwd := Vector3.FORWARD
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3, _c := true) -> bool:
	pushes += 1
	return true
func apply_knockback(_v: Vector3, _h := true) -> void:
	pushes += 1
func blast(_v: Vector3, _up: float = 0.0, _h := true) -> void:
	pushes += 1
func knock_immune() -> bool:
	return false
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return fwd
"""

const FAKE_FX := """extends Node
var bolts := 0
var puffs := 0
func sand(_a, _b = 1.0) -> void:
	pass
func burst(_a, _b, _c = 1.0, _d = 1.0, _e = false) -> void:
	pass
func hit(_a, _b) -> void:
	pass
func smoke_puff(_a, _b, _c, _d, _e, _f) -> void:
	puffs += 1
func charge_dust(_a, _b, _c, _d = 1.0) -> void:
	pass
func lightning(_p, _c = Color.WHITE, _w = 1.0) -> void:
	bolts += 1
"""

const FAKE_TG := """extends Node
var lines: Array = []
var scorches: Array = []
var rings: Array = []
func line(a, d, l, dur, c, w = 1.2) -> void:
	lines.append({"from": a, "dir": d, "length": float(l), "dur": float(dur)})
func ring(a, r, dur, c, f = false, _y = 0.0) -> void:
	rings.append({"at": a, "r": float(r), "dur": float(dur)})
func flash_ring(_a, _b, _c, _d = 0.35, _e = 0.0) -> void:
	pass
func scorch(a, r, i, o, hold = 1.5, fade = 3.0) -> void:
	scorches.append({"at": a, "r": float(r), "hold": float(hold), "fade": float(fade)})
"""

const FAKE_CAMERA := """extends Node
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func zoom() -> float:
	return 1.0
"""


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	Run.arena = false
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var f := Node.new()
	f.set_script(_script(FAKE_FX))
	g.add_child(f)
	g.fx = f
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var t := Node.new()
	t.set_script(_script(FAKE_TG))
	g.add_child(t)
	g.telegraphs = t
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "tg": t, "fx": f, "cam": cam}


## A creature that will not die of a hit (x `hp_mult` HP) at `at`, the grid rebuilt.
func _spawn(em: EnemyManager, id: String, at: Vector3, hp_mult := 1000.0) -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	em._rebuild_grid()
	return i


func _ids(list: Array) -> Array:
	return list.map(func(x) -> String: return str((x as PassiveDef).id) if x is PassiveDef else str((x as Dictionary).get("id", "")))


# ---------------------------------------------------------------- the items' data and words

func test_both_are_legendary_items_of_two_rungs_weighted_five_that_shut_each_other_out() -> void:
	for id: String in ["iron_horse", "personal_storm"]:
		var d: PassiveDef = Registry.passive(id)
		assert_object(d).is_not_null()
		assert_str(d.rarity).is_equal("legendary")
		assert_bool(d.is_item()).is_true()
		assert_int(d.max_level).is_equal(2)
		assert_str(d.rung_at(2)).is_equal(PassiveDef.EVOLVED_RUNG)
		assert_float(d.weight).is_equal(5.0)
		assert_bool(d.hidden).is_false()
	var ih: PassiveDef = Registry.passive("iron_horse")
	var ps: PassiveDef = Registry.passive("personal_storm")
	assert_array(ih.excludes).contains(["personal_storm"])
	assert_array(ps.excludes).contains(["iron_horse"])
	assert_bool(ih.shuts_out(ps)).is_true()
	assert_bool(ps.shuts_out(ih)).is_true()
	assert_bool(ih.shuts_out(ih)).is_false()
	assert_str(ih.flavour).is_equal("The 4:10 doesn't stop for anybody.")


func test_the_cards_say_the_rules_from_the_numbers() -> void:
	var ih: PassiveDef = Registry.passive("iron_horse")
	var t := TextGen.passive_text(ih)
	assert_str(t).contains("Every 30 s")
	assert_str(t).contains("25% of its max HP")
	assert_str(t).contains("Elites and bosses 5%")
	assert_str(t).contains("thrown aside")
	var evo := TextGen.passive_description(ih, 2)
	assert_str(evo).contains("Evolved")
	assert_str(evo).contains("every 22 s")
	assert_str(evo).contains("a second train crosses it")
	assert_str(evo).not_contains("total")
	var ps: PassiveDef = Registry.passive("personal_storm")
	var s := TextGen.passive_text(ps)
	assert_str(s).contains("Every 45 s")
	assert_str(s).contains("for 8 s")
	assert_str(s).contains("crowd")
	var sevo := TextGen.passive_description(ps, 2)
	assert_str(sevo).contains("every 36 s")
	assert_str(sevo).contains("10 s")


func test_the_cards_name_the_damage_the_run_would_deal() -> void:
	var ih: PassiveDef = Registry.passive("iron_horse")
	var base := roundf(IronHorse.flat_damage())
	assert_str(TextGen.passive_text(ih)).contains("+ %d damage" % int(base))
	Run.player_sheet.add_effect(Effect.make("might", "mul", 1.0, "player"), "test")
	assert_str(TextGen.passive_text(ih)).contains("+ %d damage" % int(roundf(IronHorse.flat_damage())))
	assert_float(roundf(IronHorse.flat_damage())).is_equal_approx(base * 2.0, 1.0)
	var ps: PassiveDef = Registry.passive("personal_storm")
	assert_str(TextGen.passive_text(ps)).contains("%d damage" % int(roundf(PersonalStorm.strike_amount(false))))


func test_the_stats_follow_the_rungs() -> void:
	Run.add_or_level_passive("iron_horse")
	# pass 120 (Garry: "every 30s at the start"): 30, Evolved 22
	assert_float(IronHorse.every()).is_equal(30.0)
	assert_bool(IronHorse.crossing()).is_false()
	Run.add_or_level_passive("iron_horse")
	assert_float(IronHorse.every()).is_equal(22.0)
	assert_bool(IronHorse.crossing()).is_true()
	Run.debug_set_item("passive", "iron_horse", 0)
	Run.add_or_level_passive("personal_storm")
	# pass 120 (Garry: "every 45s instead of every 30s"): 45, Evolved 36
	assert_float(PersonalStorm.every()).is_equal(45.0)
	assert_float(PersonalStorm.seconds()).is_equal(8.0)
	Run.add_or_level_passive("personal_storm")
	assert_float(PersonalStorm.every()).is_equal(36.0)
	assert_float(PersonalStorm.seconds()).is_equal(10.0)


# ---------------------------------------------------------------- the exclusion, in every offer path

func test_with_neither_held_both_can_be_offered() -> void:
	# pass 121 (lane LEGEND): a legendary waits for the stage clock to reach `legendary.from` (pass121_LEGEND_test)
	Run.elapsed = Run.map.timeline.stage_start(Run.stage) + LegendaryHold.from_seconds()
	var ids := _ids(CardPool.offer_passives())
	assert_array(ids).contains(["iron_horse", "personal_storm"])
	var chest := _ids(Run.chest_candidates())
	assert_array(chest).contains(["iron_horse", "personal_storm"])
	assert_bool(Run.shut_out("iron_horse")).is_false()
	assert_bool(Run.shut_out("personal_storm")).is_false()


func _assert_never_offered(held: String, other: String) -> void:
	Run.add_or_level_passive(held)
	assert_bool(Run.shut_out(other)).is_true()
	assert_bool(Run.shut_out(held)).is_false()
	# the pool every level-up, the Shop and the Stranger draw from
	var pool := _ids(CardPool.offer_passives())
	assert_array(pool).not_contains([other])
	assert_array(pool).contains([held])
	# the level-up's (and the Shop's, the first-run Dynamite's) candidates: the held one still levels
	var cands := _ids(CardPool.candidates())
	assert_array(cands).not_contains([other])
	assert_array(cands).contains([held])
	# a chest's
	var chest := _ids(Run.chest_candidates())
	assert_array(chest).not_contains([other])
	# drawn many times: the level-up (the Shop opens the same offer) and the Stranger
	for k in range(150):
		assert_array(_ids(CardPool.level_up_offer(3))).not_contains([other])
		var so := Run.stranger_offer()
		assert_str(str(so.get("id", ""))).is_not_equal(other)
		var cr := Run.chest_roll()
		assert_str(str(cr.get("id", ""))).is_not_equal(other)


func test_holding_the_iron_horse_shuts_the_storm_out_of_every_offer() -> void:
	_assert_never_offered("iron_horse", "personal_storm")


func test_holding_the_storm_shuts_the_iron_horse_out_of_every_offer() -> void:
	_assert_never_offered("personal_storm", "iron_horse")


func test_the_exclusion_says_nothing_and_keeps_the_held_one_levelling() -> void:
	Run.add_or_level_passive("personal_storm")
	var lv := Run.passive_level("personal_storm")
	var cands: Array = CardPool.candidates().filter(func(c: Dictionary) -> bool: return str(c["id"]) == "personal_storm")
	assert_int(cands.size()).is_equal(1)
	assert_int(int(cands[0]["level_from"])).is_equal(lv)
	# no card, toast or text names the shut-out item anywhere in the offer
	for c: Dictionary in CardPool.candidates():
		assert_str(str(c["id"])).is_not_equal("iron_horse")


# ---------------------------------------------------------------- the Iron Horse

func _horse(w: Dictionary) -> IronHorse:
	var ih := IronHorse.new()
	w["g"].add_child(ih)
	ih.setup(w["g"])
	return ih


func test_the_horse_rumbles_after_first_then_whistles_then_comes_every_thirty_seconds() -> void:
	var w := _world()
	Run.add_or_level_passive("iron_horse")
	var ih := _horse(w)
	var t := 0.0
	while ih.rumbles == 0 and t < 30.0:
		ih.tick(DT)
		t += DT
	assert_float(t).is_equal_approx(IronHorse.param("first"), 0.05)
	var t1 := t
	while ih.whistles == 0 and t < 30.0:
		ih.tick(DT)
		t += DT
	assert_float(t - t1).is_equal_approx(IronHorse.param("rumble"), 0.05)
	assert_int(ih.runs.size()).is_equal(1)
	# the rumble shook the camera before the whistle: foreshadowing beyond the sound
	assert_int(int(w["cam"].shakes)).is_greater(10)
	# the track lights up along the line (Telegraphs.line), the way he faces
	assert_int((w["tg"].lines as Array).size()).is_equal(1)
	var ln: Dictionary = w["tg"].lines[0]
	assert_float((ln["dir"] as Vector3).dot(Vector3.FORWARD)).is_greater(0.99)
	while ih.rumbles == 1 and t < 60.0:
		ih.tick(DT)
		t += DT
	assert_float(t - t1).is_equal_approx(30.0, 0.05)


func test_the_evolved_horse_comes_every_fifteen_seconds_with_a_second_train_across() -> void:
	var w := _world()
	Run.add_or_level_passive("iron_horse")
	Run.add_or_level_passive("iron_horse")
	var ih := _horse(w)
	var t := 0.0
	while ih.whistles == 0 and t < 30.0:
		ih.tick(DT)
		t += DT
	assert_int(ih.runs.size()).is_equal(2)
	var a: IronHorse.TrainRun = ih.runs[0]
	var b: IronHorse.TrainRun = ih.runs[1]
	assert_float(absf(a.dir.dot(b.dir))).is_less(0.01)
	# its clock started with the whistle's tick, `cross_delay` s behind the first
	assert_float(a.u - b.u).is_equal_approx(IronHorse.param("cross_delay"), 0.001)
	var t1 := t
	while ih.whistles == 1 and t < 60.0:
		ih.tick(DT)
		t += DT
	assert_float(t - t1).is_equal_approx(22.0, 0.05)


func test_the_train_takes_its_share_of_max_hp_plus_the_flat_part_and_less_from_big_ones() -> void:
	var flat := IronHorse.flat_damage()
	assert_float(flat).is_equal_approx(IronHorse.param("damage") * Run.player_sheet.get_stat("might", 1.0) * Run.stage_mult(), 0.001)
	assert_float(IronHorse.hit_amount(1000.0, false)).is_equal_approx(250.0 + flat, 0.001)
	assert_float(IronHorse.hit_amount(1000.0, true)).is_equal_approx(50.0 + flat, 0.001)
	# might scales the flat part only
	Run.player_sheet.add_effect(Effect.make("might", "mul", 1.0, "player"), "test")
	assert_float(IronHorse.hit_amount(1000.0, false)).is_equal_approx(250.0 + flat * 2.0, 0.01)


func test_the_train_runs_over_what_is_on_the_rails_throws_it_aside_and_never_the_hero() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero = w["hero"]
	Run.add_or_level_passive("iron_horse")
	# on the line ahead (left and right of it), behind him, off the line, and an Elite on it
	var left := _spawn(em, "skeleton", Vector3(-0.6, 0, -6.0))
	var right := _spawn(em, "skeleton", Vector3(0.7, 0, -9.0))
	var behind := _spawn(em, "skeleton", Vector3(0.2, 0, 5.0))
	var off := _spawn(em, "skeleton", Vector3(6.0, 0, -6.0))
	var elite := _spawn(em, "training_dummy_elite", Vector3(0.0, 0, -12.0), 10.0)
	var hp0 := {}
	for i in [left, right, behind, off, elite]:
		hp0[i] = em.hp[i]
	var ih := _horse(w)
	ih.trigger()
	var t := 0.0
	while (ih.busy() or t < 0.5) and t < 12.0:
		em._rebuild_grid()
		ih.tick(DT)
		t += DT
	var by_i := {}
	for h: Dictionary in ih.hit_log:
		by_i[int(h["i"])] = h
	for i in [left, right, behind, elite]:
		assert_bool(by_i.has(i)).override_failure_message("creature %d on the rails was not run over" % i).is_true()
	assert_bool(by_i.has(off)).is_false()
	assert_float(em.hp[off]).is_equal(hp0[off])
	# once a train each
	assert_int(ih.hit_log.size()).is_equal(4)
	# what each took
	assert_float(float(by_i[left]["amount"])).is_equal_approx(IronHorse.hit_amount(em.max_hp[left], false), 0.01)
	assert_float(hp0[left] - em.hp[left]).is_equal_approx(float(by_i[left]["amount"]), 0.5)
	assert_bool(bool(by_i[elite]["big"])).is_true()
	assert_float(float(by_i[elite]["amount"])).is_equal_approx(IronHorse.hit_amount(em.max_hp[elite], true), 0.01)
	assert_float(float(by_i[elite]["force"])).is_less(float(by_i[left]["force"]))
	# thrown aside off the rails (to the side each stood on) and a little forward
	var side := Vector3(1, 0, 0)
	assert_float((by_i[left]["dir"] as Vector3).dot(side)).is_less(-0.5)
	assert_float((by_i[right]["dir"] as Vector3).dot(side)).is_greater(0.5)
	assert_float((by_i[left]["dir"] as Vector3).dot(Vector3.FORWARD)).is_greater(0.1)
	# the hero: never hit, never pushed
	assert_int(int(hero.hits)).is_equal(0)
	assert_int(int(hero.pushes)).is_equal(0)
	# its damage is the Iron Horse's in the run's record
	assert_float(float(Run.damage_by_weapon.get("iron_horse", 0.0))).is_greater(0.0)


func test_the_knock_reaches_the_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Run.add_or_level_passive("iron_horse")
	var i := _spawn(em, "skeleton", Vector3(0.6, 0, -6.0))
	var ih := _horse(w)
	ih.trigger()
	var t := 0.0
	while ih.hit_log.is_empty() and t < 6.0:
		em._rebuild_grid()
		ih.tick(DT)
		t += DT
	assert_bool(ih.hit_log.is_empty()).is_false()
	# the push it took: off the rails to its side
	assert_float(em.kb[i].x).is_greater(1.0)


# ---------------------------------------------------------------- Personal Storm

func _storm(w: Dictionary) -> PersonalStorm:
	var ps := PersonalStorm.new()
	w["g"].add_child(ps)
	ps.setup(w["g"])
	return ps


func test_the_storm_gathers_strikes_for_its_seconds_about_twice_a_second_and_clears() -> void:
	var w := _world()
	Run.add_or_level_passive("personal_storm")
	var ps := _storm(w)
	var t := 0.0
	while ps.storms == 0 and t < 30.0:
		ps.tick(DT)
		t += DT
	assert_float(t).is_equal_approx(PersonalStorm.param("first"), 0.05)
	var t0 := t
	while ps.phase == PersonalStorm.GATHER:
		ps.tick(DT)
		t += DT
	assert_float(t - t0).is_equal_approx(PersonalStorm.param("gather"), 0.05)
	assert_float(ps.cover).is_equal(1.0)
	var t1 := t
	while ps.phase == PersonalStorm.STRIKE:
		ps.tick(DT)
		t += DT
	assert_float(t - t1).is_equal_approx(8.0, 0.05)
	while ps.busy():
		ps.tick(DT)
		t += DT
	var rate := PersonalStorm.param("rate")
	assert_int(ps.strikes).is_between(int(8.0 * rate * 0.7), int(8.0 * rate * 1.3) + 1)
	assert_float(ps.cover).is_equal(0.0)
	# every strike left a scorch that holds and fades over about six seconds
	var sc: Array = w["tg"].scorches
	assert_int(sc.size()).is_equal(ps.strikes)
	assert_float(float(sc[0]["hold"]) + float(sc[0]["fade"])).is_equal_approx(6.0, 0.01)
	# a bolt each, and the hero never hit
	assert_int(int(w["fx"].bolts)).is_greater_equal(ps.strikes)
	assert_int(int(w["hero"].hits)).is_equal(0)
	# the next storm `every` s after this one began
	while ps.storms == 1 and t < 80.0:
		ps.tick(DT)
		t += DT
	assert_float(t - t0).is_equal_approx(45.0, 0.05)


func test_the_strikes_seek_the_crowd_most_of_the_time_and_bare_ground_sometimes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Run.add_or_level_passive("personal_storm")
	var crowd_at := Vector3(5.0, 0, 1.0)
	for k in range(12):
		var a := TAU * float(k) / 12.0
		_spawn(em, "skeleton", crowd_at + Vector3(cos(a), 0, sin(a)) * 0.8)
	for p: Vector3 in [Vector3(-6, 0, 2), Vector3(-3, 0, -7), Vector3(1, 0, 7)]:
		_spawn(em, "skeleton", p)
	var ps := _storm(w)
	ps.center = Vector3.ZERO
	var near := 0
	var crowd := 0
	var n := 400
	for k in range(n):
		ps._recent.clear()
		var pick := ps.pick_spot()
		var at: Vector3 = pick["at"]
		if bool(pick["crowd"]):
			crowd += 1
		if Vector2(at.x - crowd_at.x, at.z - crowd_at.z).length() < 2.0:
			near += 1
		# never on the hero
		assert_float(Vector2(at.x, at.z).length()).is_greater_equal(PersonalStorm.param("hero_clear") - 0.001)
		# inside the storm (a crowd spot may sit its jitter past the rim)
		assert_float(Vector2(at.x, at.z).length()).is_less_equal(PersonalStorm.param("radius") + 0.5)
	var share := PersonalStorm.param("crowd_share")
	assert_float(float(crowd) / n).is_between(share - 0.08, share + 0.08)
	# the 12-body crowd draws most of the crowd strikes, the three loners few
	assert_float(float(near) / n).is_greater(share * 0.6)
	# and the ground away from any creature still gets struck
	assert_int(n - crowd).is_greater(40)


func test_a_new_strike_keeps_apart_from_the_last_ones() -> void:
	var w := _world()
	Run.add_or_level_passive("personal_storm")
	var ps := _storm(w)
	ps.center = Vector3.ZERO
	var close := 0
	for k in range(200):
		var pick := ps.pick_spot()
		var at: Vector3 = pick["at"]
		for q: Vector3 in ps._recent:
			if Vector2(at.x - q.x, at.z - q.z).length() < PersonalStorm.param("apart"):
				close += 1
		ps._recent.push_front(at)
		if ps._recent.size() > PersonalStorm.RECENT:
			ps._recent.resize(PersonalStorm.RECENT)
	# a few tries each: on bare ground nearly never next to the last ones
	assert_int(close).is_less(12)


func test_a_strike_hurts_what_stands_in_it_throws_it_outwards_and_less_for_big_ones() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Run.add_or_level_passive("personal_storm")
	var at := Vector3(4.0, 0, 0)
	var a := _spawn(em, "skeleton", at + Vector3(0.8, 0, 0))
	var b := _spawn(em, "skeleton", at + Vector3(0, 0, -0.9))
	var big := _spawn(em, "training_dummy_elite", at + Vector3(-0.6, 0, 0.3), 10.0)
	var far := _spawn(em, "skeleton", at + Vector3(4.0, 0, 0))
	var hp0 := {}
	for i in [a, b, big, far]:
		hp0[i] = em.hp[i]
	var ps := _storm(w)
	var n := ps.land(at)
	assert_int(n).is_equal(3)
	assert_float(hp0[a] - em.hp[a]).is_equal_approx(PersonalStorm.strike_amount(false), 0.5)
	assert_float(hp0[big] - em.hp[big]).is_equal_approx(PersonalStorm.strike_amount(true), 0.5)
	assert_float(PersonalStorm.strike_amount(true)).is_equal_approx(PersonalStorm.strike_amount(false) * PersonalStorm.param("big_mult"), 0.01)
	assert_float(em.hp[far]).is_equal(hp0[far])
	# outwards from the bolt
	assert_float(em.kb[a].x).is_greater(1.0)
	assert_float(em.kb[b].z).is_less(-1.0)
	assert_float(em.kb[a].length()).is_greater(em.kb[big].length())
	assert_int(int(w["hero"].hits)).is_equal(0)
	assert_int(int(w["hero"].pushes)).is_equal(0)
	assert_float(float(Run.damage_by_weapon.get("personal_storm", 0.0))).is_greater(0.0)


func test_a_strike_never_crits() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Run.add_or_level_passive("personal_storm")
	Run.player_sheet.add_effect(Effect.make("crit_chance", "add", 1.0, "player"), "test")
	var i := _spawn(em, "skeleton", Vector3(3, 0, 0))
	var hp0: float = em.hp[i]
	var ps := _storm(w)
	ps.land(Vector3(3, 0, 0))
	assert_float(hp0 - em.hp[i]).is_equal_approx(PersonalStorm.strike_amount(false), 0.5)


func test_the_storm_picks_the_same_spots_from_the_same_seed() -> void:
	var w := _world()
	Run.add_or_level_passive("personal_storm")
	var keep := Dice.run_seed
	Dice.reseed(4242)
	var a := _storm(w)
	var b := _storm(w)
	var pa: Array = []
	var pb: Array = []
	for k in range(20):
		pa.append(a.pick_spot()["at"])
		pb.append(b.pick_spot()["at"])
	Dice.reseed(keep)
	for k in range(20):
		assert_vector((pa[k] as Vector3)).is_equal_approx(pb[k] as Vector3, Vector3(0.0001, 0.0001, 0.0001))


func test_the_arena_lists_both_items() -> void:
	var listed: Array = Registry.passives.values().filter(func(p: PassiveDef) -> bool: return not W.is_line(p)).map(func(p: PassiveDef) -> String: return p.id)
	assert_array(listed).contains(["iron_horse", "personal_storm"])
