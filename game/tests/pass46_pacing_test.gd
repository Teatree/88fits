extends GdUnitTestSuite

## Pass 46 (pacing): Red Canyon's whole clock stretched by 430/300 (stages of 7:10, every boss exactly at its stage's
## end), colour only after the run's first fifty kills (no variance tint, no special, no elite modifier before them),
## every creature but a boss 1.3 times as tough, one touch never more than 22% of the hero's health, the hit log's role
## and colour, a pin that stops a creature dead, the damage-number hook, the gems' hop out and flight in (XP only on
## arrival), and the Blue Slime SL-C turned to look at the hero.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var toasts := 0
func toast(_t, _c = null) -> void:
	toasts += 1
func fx_burst(_a, _b, _c) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var taken: Array = []
var last_outcome := "hit"
func take_damage(a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	taken.append(a)
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

## a stand-in for the HUD's numbers: it only writes down what it was handed
const FAKE_NUMBERS := """extends DamageNumbers
var calls: Array = []
func add(i: int, at: Vector3, amount: float, crit: bool = false, green: bool = false, hot: bool = false, mini: bool = false) -> void:
	calls.append({"i": i, "at": at, "amount": amount, "crit": crit, "green": green, "hot": hot, "mini": mini})
"""

const DT := 1.0 / 60.0
const K := 430.0 / 300.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _tl() -> WaveTimeline:
	return Registry.map("red_canyon").timeline


## A fake game with a fake hero at the origin (max HP 100), a plain map and a real EnemyManager wired to both.
func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	return {"g": g, "hero": hero, "em": em}


## The world above with a WaveDirector on Red Canyon's timeline.
func _director(w: Dictionary) -> WaveDirector:
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = d.map.timeline
	return d


## A creature on its feet (past the spawn pop), standing where it was put.
func _creature(em: EnemyManager, id: String, at: Vector3, mod: EliteModDef = null) -> int:
	var i := em.spawn(id, at, mod)
	assert_int(i).override_failure_message("could not spawn " + id).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


func _modded(em: EnemyManager) -> int:
	var n := 0
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1 and em.elite_idx[i] >= 0:
			n += 1
	return n


# ---------------------------------------------------------------- the stretch

func test_the_whole_clock_is_stretched_and_the_bosses_end_their_stages() -> void:
	var tl := _tl()
	assert_float(tl.stage_length).is_equal(430.0)
	assert_int(tl.stages).is_equal(3)
	# every boss exactly at a stage's end, one a stage; every mini-boss half way through one
	var boss_ks: Array = []
	var elite_ks: Array = []
	for ev in tl.events:
		var t := float(ev.get("t", 0.0))
		assert_float(fmod(t, 1.0)).override_failure_message("event at %.2f s is not a whole second" % t).is_equal(0.0)
		match str(ev.get("type", "")):
			"boss":
				var k := t / tl.stage_length
				assert_float(k).override_failure_message("a boss at %.1f s is not at a stage's end" % t).is_equal(roundf(k))
				boss_ks.append(int(k))
			"elite_boss":
				elite_ks.append(t / tl.stage_length)
			"elite_every":
				assert_float(float(ev.get("interval", 0.0))).is_equal(129.0)
	assert_array(boss_ks).contains_exactly([1, 2, 3])
	assert_array(elite_ks).contains_exactly([0.5, 1.5, 2.5])
	# each old second is 430/300 of a new one, rounded to the second (pass 62, lane PC, re-pinned: stages 2 and 3 have
	# their own events now; stage 1's keep the stretched seconds, and the bosses and Elites are checked above)
	var old_events := [150, 210, 300]
	# (pass 69, lane EN, re-pinned: the special Goblin's event at 2:00 is not one of the stretched ones)
	var stretched: Array = tl.events.filter(func(e: Dictionary) -> bool: return not bool(e.get("special", false)))
	for k in range(old_events.size()):
		assert_float(float(stretched[k]["t"])).is_equal(roundf(old_events[k] * K))
	for r in tl.roster:
		assert_float(fmod(float(r.get("t", 0.0)), 1.0)).is_equal(0.0)
	# the cap follows the curve at the stage ends (pass 56, re-pinned: Garry draws it in the Level Editor, so the
	# expected values come from his points, sampled by the curve rule, not from pinned numbers)
	for k in [1, 2, 3]:
		var t: float = float(k) * float(tl.stage_length)
		var want := mini(int(WaveTimeline.sample_points(tl.cap_curve, t)), tl.cap_max)
		assert_int(tl.cap_at(t, k - 1)).is_equal(want)
	for p in tl.cap_curve:
		assert_float(fmod(float(p[0]), 1.0)).is_equal(0.0)
	# the rest of the clock: the late weights, the specials, the endless waves, the path slots
	assert_float(tl.weight_late_t).is_equal(2.0 * tl.stage_length)
	assert_float(float(tl.specials.get("from", 0.0))).is_equal(tl.stage_length * 0.5)
	var iv: Array = tl.specials.get("interval", [])
	assert_float(float(iv[0])).is_equal(64.0)
	assert_float(float(iv[iv.size() - 1])).is_equal(86.0)
	assert_float(tl.endless_wave_seconds).is_equal(86.0)
	for s in range(3):
		var times: Array = tl.path_times_at(s)
		var prev := 0.0
		for t in times:
			assert_float(float(t)).is_greater(prev)
			assert_float(float(t)).is_less(tl.stage_length)
			prev = float(t)
	assert_float(float(tl.path_times_at(0)[0])).is_equal(79.0)
	# the health ramp is divided by the same factor, so a stretched moment is as tough as the old one was
	for m in [1.0, 2.0, 3.0]:
		var old: float = pow(1.0 + 0.14 * 5.0 * m, 1.25)
		assert_float(tl.hp_mult_at(tl.stage_length * m)).is_equal_approx(old, old * 0.005)
	# what does not run on the clock stays: the bursts, the drops, the level scaling
	assert_float(tl.spawn_interval).is_equal_approx(0.7, 0.0001)
	assert_float(float(tl.pickups.get("per_kill", 0.0))).is_equal_approx(0.0045, 0.00001)
	assert_float(tl.level_hp_per_level).is_equal_approx(0.05, 0.0001)
	# and the pass's new numbers
	assert_int(tl.colour_after_kills).is_equal(50)
	assert_float(tl.creature_hp_mult).is_equal_approx(1.3, 0.0001)
	assert_float(tl.contact_cap).is_equal_approx(0.22, 0.0001)
	# pass 47: the caps are static, all run (Run.line_cap); five since pass 52
	assert_int(tl.passive_cap_at(0)).is_equal(5)
	assert_int(tl.passive_cap_at(1)).is_equal(5)
	assert_int(tl.passive_cap_at(2)).is_equal(5)


func test_the_endless_clocks_follow_the_stage() -> void:
	var w := _world()
	var d := _director(w)
	Run.stage = 2
	Run.elapsed = 1300.0
	d.continue_to_next_stage()
	assert_bool(Run.endless).is_true()
	assert_float(d._endless_next_boss).is_equal_approx(1300.0 + 430.0, 0.001)
	assert_float(d._endless_next_elite_boss).is_equal_approx(1300.0 + 215.0, 0.001)
	assert_float(d._endless_next_elite).is_equal_approx(1300.0 + 64.5, 0.001)
	Run.endless = false
	Run.stage = 0
	Run.elapsed = 0.0


# ---------------------------------------------------------------- colour after fifty kills

func test_the_director_hands_the_crowd_the_new_numbers() -> void:
	var w := _world()
	var d := _director(w)
	var em: EnemyManager = w["em"]
	d._apply_mults()
	assert_float(em.creature_hp_mult).is_equal_approx(1.3, 0.0001)
	assert_int(em.colour_after_kills).is_equal(50)
	assert_float(em.contact_cap).is_equal_approx(0.22, 0.0001)
	# the arena shows colour from the first spawn (it is there to look at the art)
	Run.arena = true
	d._apply_mults()
	assert_int(em.colour_after_kills).is_equal(0)
	assert_bool(d.colour_open()).is_true()
	Run.arena = false


func test_no_tint_and_no_special_before_fifty_kills() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 50
	Run.kills = 49
	var sizes := {}
	for k in range(150):
		var i := em.spawn("skeleton", Vector3(float(k % 15) * 2.0 - 15.0, 0, float(k / 15) * 2.0 - 10.0))
		assert_float(em.vtint[i].a).override_failure_message("a tint before the fiftieth kill").is_equal(0.0)
		assert_int(em.vspecial[i]).is_equal(0)
		sizes[snappedf(em.size[i], 0.001)] = true
	# the size jitter is not colour: it stays
	assert_int(sizes.size()).is_greater(10)
	em.kill_all(false)
	# the fiftieth kill: every skeleton gets a tint from its palette, and the odd one is a special
	Run.kills = 50
	var tinted := 0
	var specials := 0
	for k in range(150):
		var i := em.spawn("skeleton", Vector3(float(k % 15) * 2.0 - 15.0, 0, float(k / 15) * 2.0 - 10.0))
		if em.vtint[i].a > 0.0:
			tinted += 1
		specials += em.vspecial[i]
	assert_int(tinted).is_equal(150)
	assert_int(specials).is_greater(0)
	assert_int(specials).is_less(60)
	Run.kills = 0


func test_elite_modifiers_wait_for_the_fifty_kills_and_are_not_dropped() -> void:
	var w := _world()
	var d := _director(w)
	var em: EnemyManager = w["em"]
	d._apply_mults()
	d._event_i = d.timeline.events.size()
	Run.elapsed = 301.0
	Run.kills = 10
	d._elite_timers.append({"next": 301.0, "interval": 129.0})
	assert_bool(d.colour_open()).is_false()
	# a direct ask (an "elite" event, the debug button) is held, not spawned
	d._spawn_elite("", "")
	assert_int(d._elite_held.size()).is_equal(1)
	d._process_events()
	assert_int(_modded(em)).is_equal(0)
	# the timer waits a second at a time instead of losing its Elite
	assert_float(float(d._elite_timers[0]["next"])).is_equal_approx(302.0, 0.001)
	Run.elapsed = 301.6
	d._process_events()
	assert_int(_modded(em)).is_equal(0)
	# the fiftieth kill: the timer's Elite comes, and the held one with it
	Run.kills = 50
	Run.elapsed = 302.5
	d._process_events()
	assert_int(_modded(em)).is_equal(2)
	assert_int(d._elite_held.size()).is_equal(0)
	assert_float(float(d._elite_timers[0]["next"])).is_equal_approx(302.5 + 129.0, 0.001)
	# endless holds its own the same way
	em.kill_all(false)
	d._elite_timers.clear()
	Run.endless = true
	Run.kills = 0
	d._endless_next_boss = 1e9
	d._endless_next_elite_boss = 0.0
	d._endless_next_elite = Run.elapsed
	d._process_events()
	assert_int(_modded(em)).is_equal(0)
	assert_float(d._endless_next_elite).is_equal_approx(Run.elapsed + 1.0, 0.001)
	Run.kills = 50
	Run.elapsed += 1.0
	d._process_events()
	assert_int(_modded(em)).is_equal(1)
	assert_float(d._endless_next_elite).is_equal_approx(Run.elapsed + 430.0 * 0.15, 0.001)
	Run.endless = false
	Run.kills = 0
	Run.elapsed = 0.0


# ---------------------------------------------------------------- beefier, but a touch is capped

func test_creatures_and_elites_are_beefier_but_never_a_boss() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 50   # no special: the health is the data's
	Run.kills = 0
	var at := Vector3(5, 0, 5)
	for id in ["skeleton", "rocketeer", "dune_scorpion"]:
		em.creature_hp_mult = 1.0
		var a := _creature(em, id, at)
		var plain: float = em.max_hp[a]
		em.creature_hp_mult = 1.3
		var b := _creature(em, id, at)
		assert_float(em.max_hp[b]).override_failure_message(id + " is not 1.3 times as tough").is_equal_approx(plain * 1.3, 0.01)
		em.kill_all(false)
	# a creature wearing an elite modifier: the same factor under the modifier's own
	var mod: EliteModDef = em.elites[0]
	em.creature_hp_mult = 1.0
	var m1 := _creature(em, "skeleton", at, mod)
	var m_plain: float = em.max_hp[m1]
	em.creature_hp_mult = 1.3
	var m2 := _creature(em, "skeleton", at, mod)
	assert_float(em.max_hp[m2]).is_equal_approx(m_plain * 1.3, 0.01)
	em.kill_all(false)
	# the boss keeps its own health
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var bi := _creature(em, "tumbleweed_king", at)
	assert_int(em.boss_index).is_equal(bi)
	assert_float(em.max_hp[bi]).is_equal_approx(king.hp, 0.01)
	em.kill_all(false)


func test_one_touch_takes_at_most_a_fifth_of_his_health_but_a_boss_hits_whole() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	em.contact_cap = 0.22
	var i := _creature(em, "skeleton", Vector3(0.3, 0, 0))
	em.dmg[i] = 100.0
	em._physics_process(DT)
	assert_int((hero.taken as Array).size()).is_equal(1)
	assert_float(float(hero.taken[0])).is_equal_approx(22.0, 0.001)
	# a small bite is a small bite
	hero.taken.clear()
	em.dmg[i] = 7.0
	em.contact_cd[i] = 0.0
	em._physics_process(DT)
	assert_float(float(hero.taken[0])).is_equal_approx(7.0, 0.001)
	# the boss's weight is its own
	hero.taken.clear()
	em.dmg[i] = 100.0
	em.contact_cd[i] = 0.0
	em.boss_index = i
	em._physics_process(DT)
	assert_float(float(hero.taken[0])).is_equal_approx(100.0, 0.001)
	em.boss_index = -1
	# and with no cap the whole bite lands
	hero.taken.clear()
	em.contact_cap = 0.0
	em.contact_cd[i] = 0.0
	em._physics_process(DT)
	assert_float(float(hero.taken[0])).is_equal_approx(100.0, 0.001)


# ---------------------------------------------------------------- the hit log's role and colour

func test_the_hit_log_says_who_and_in_what_colour() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 50
	Run.kills = 0
	var at := Vector3(4, 0, 4)
	var plain := em.hit_info(_creature(em, "skeleton", at), "melee")
	assert_str(str(plain["role"])).is_equal("")
	assert_str(str(plain["colour"])).is_equal("")
	var boss := em.hit_info(_creature(em, "tumbleweed_king", at), "melee")
	assert_str(str(boss["role"])).is_equal("boss")
	assert_str(str(boss["kind"])).is_equal("boss")
	assert_str(str(boss["colour"])).is_equal("")
	var elite := em.hit_info(_creature(em, "dune_scorpion", at), "melee")
	assert_str(str(elite["role"])).is_equal("elite")
	assert_str(str(elite["colour"])).is_equal("")
	var mod: EliteModDef = em.elites[1]
	var modded := em.hit_info(_creature(em, "skeleton", at, mod), "melee")
	assert_str(str(modded["role"])).is_equal("elite")
	assert_str(str(modded["colour"])).is_equal("#" + mod.outline.to_html(false))
	for id in ["rocketeer", "harpoon_troglodyte"]:
		var sp := em.hit_info(_creature(em, id, at), "ranged")
		assert_str(str(sp["role"])).override_failure_message(id + " is a special").is_equal("special")
		assert_str(str(sp["kind"])).is_equal("ranged")
	em.kill_all(false)
	# a variance special wears its dark tint
	em.colour_after_kills = 0
	var sk: EnemyDef = Registry.enemy("skeleton")
	var want := "#" + Color(str(sk.variance["special"]["tint"])).to_html(false)
	var found := false
	for k in range(300):
		var j := em.spawn("skeleton", at)
		if em.vspecial[j] == 1:
			var info := em.hit_info(j, "melee")
			assert_str(str(info["colour"])).is_equal(want)
			assert_str(str(info["role"])).is_equal("")
			found = true
			break
		em._free(j)
	assert_bool(found).is_true()
	# nobody at all
	var none := em.hit_info(-1, "ranged")
	assert_str(str(none["role"])).is_equal("")
	assert_str(str(none["colour"])).is_equal("")


# ---------------------------------------------------------------- a pin

func test_a_pin_stops_a_creature_where_it_stands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pinned := _creature(em, "skeleton", Vector3(8, 0, 0))
	var slowed := _creature(em, "skeleton", Vector3(-8, 0, 0))
	em.slow(pinned, 1.0, 5.0)
	em.slow(slowed, 0.35, 5.0)
	var p0: Vector3 = em.pos[pinned]
	var s0: Vector3 = em.pos[slowed]
	for k in range(60):
		em._physics_process(DT)
	assert_float(em.pos[pinned].distance_to(p0)).is_less(0.001)
	# a slow is still a slow: it walks on at two thirds
	assert_float(em.pos[slowed].distance_to(s0)).is_greater(0.3)


# ---------------------------------------------------------------- the damage numbers

func test_every_hit_goes_to_the_damage_numbers() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, "skeleton", Vector3(5, 0, 5))
	# nothing up: the hit lands and nothing breaks
	DamageNumbers.I = null
	em.damage(i, 0.5, "")
	var fake: DamageNumbers = auto_free(_script(FAKE_NUMBERS).new())
	DamageNumbers.I = fake
	em.damage(i, 1.0, "")
	em.damage(i, 0.25, "", Vector3.ZERO, 0.0, true)
	em.damage(i, 0.75, "", Vector3.ZERO, 0.0, false, true)
	DamageNumbers.I = null
	var calls: Array = fake.get("calls")
	assert_int(calls.size()).is_equal(3)
	assert_int(int(calls[0]["i"])).is_equal(i)
	assert_float(float(calls[0]["amount"])).is_equal_approx(1.0 * (1.0 - em.dr[i]), 0.0001)
	var at: Vector3 = calls[0]["at"]
	assert_float(at.y).is_equal_approx(em.pos[i].y + em.size[i] * 1.2, 0.001)
	assert_bool(bool(calls[0]["crit"]) or bool(calls[0]["green"]) or bool(calls[0]["hot"])).is_false()
	assert_bool(bool(calls[1]["green"])).is_true()
	assert_bool(bool(calls[2]["hot"])).is_true()


# ---------------------------------------------------------------- the gems

func _pickups() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	return {"g": g, "hero": hero, "pm": pm}


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func test_a_gem_hops_out_then_flies_in_and_pays_only_on_arrival() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	var d0: float = magnet * 0.6
	var i := pm.spawn(PickupManager.KIND_GEM_M, Vector3(d0, 0, 0), 5.0)
	pm.pos[i] = Vector3(d0, PickupManager.REST, 0)
	pm.vel[i] = Vector3.ZERO
	var xp0: float = Run.xp
	var lv0: int = Run.level
	var far := d0
	var top := 0.0
	var phases: Array = []
	var t := 0.0
	while pm.alive[i] == 1 and t < 3.0:
		pm._physics_process(DT)
		t += DT
		if pm.alive[i] == 0:
			break
		if phases.is_empty() or int(phases[phases.size() - 1]) != pm.phase[i]:
			phases.append(int(pm.phase[i]))
		if pm.phase[i] == PickupManager.PHASE_HOP:
			far = maxf(far, _flat(pm.pos[i]))
			top = maxf(top, pm.pos[i].y)
		# nothing is his until it gets there
		assert_float(Run.xp).is_equal(xp0)
		assert_int(Run.level).is_equal(lv0)
	# out, up, then in: the hop went away from him first
	assert_array(phases).contains_exactly([PickupManager.PHASE_HOP, PickupManager.PHASE_FLY])
	assert_float(far).is_greater(d0 + 0.5)
	assert_float(top).is_greater(PickupManager.REST + 0.25)
	assert_int(pm.alive[i]).is_equal(0)
	assert_float(t).is_less(1.2)
	assert_float(Run.xp).is_greater(xp0)


func test_a_flying_gem_is_taken_at_the_new_reach_and_never_sent_back() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	assert_float(PickupManager.COLLECT_R).is_equal_approx(0.45, 0.0001)
	var chest: Vector3 = hero.global_position + Vector3(0, PickupManager.CHEST, 0)
	var i := pm.spawn(PickupManager.KIND_GEM_S, Vector3(9, 0, 9), 1.0)
	# half a metre out, just setting off: still on its way (0.6 m was close enough before)
	pm._start_trip(i, hero.global_position)
	pm.phase[i] = PickupManager.PHASE_FLY
	pm.phase_t[i] = 0.0
	pm.pos[i] = chest + Vector3(0.5, 0, 0)
	pm._physics_process(DT)
	assert_int(pm.alive[i]).is_equal(1)
	# a vacuum or the magnet never sends it back to the start of its trip
	var pt: float = pm.phase_t[i]
	pm.vacuum_all(true)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_FLY)
	assert_float(pm.phase_t[i]).is_equal(pt)
	pm._physics_process(DT)
	assert_int(pm.alive[i]).is_equal(0)
	# a gem far off on the sand sets out when the vacuum calls it: on the magnet arc since pass 60 (re-pinned: it waits
	# its turn, then goes up; the walk-up pull keeps the hop, pass60_pk_test), its line out inside the arc's fan of
	# straight away from him
	var j := pm.spawn(PickupManager.KIND_GEM_S, Vector3(20, 0, 0), 1.0)
	pm.vacuum_all()
	assert_int(pm.flying[j]).is_equal(1)
	assert_int(pm.phase[j]).is_equal(PickupManager.PHASE_ARC_WAIT)
	assert_float(pm.hop_dir[j].x).is_greater(cos(PickupManager.ARC_DRIFT_FAN) - 0.01)
	# (a merge left a gem on its trip alone: the merge is gone since pass 61)
	assert_int(pm.alive[j]).is_equal(1)


func test_a_coin_pays_its_gold_on_arrival() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var d0: float = Run.player_sheet.get_stat("magnet", 1.5) * 0.6
	var i := pm.spawn(PickupManager.KIND_COIN, Vector3(d0, 0, 0), 2.0)
	pm.pos[i] = Vector3(d0, PickupManager.REST, 0)
	pm.vel[i] = Vector3.ZERO
	var g0: int = Run.run_gold
	var t := 0.0
	while pm.alive[i] == 1 and t < 3.0:
		pm._physics_process(DT)
		t += DT
		if pm.alive[i] == 1:
			assert_int(Run.run_gold).is_equal(g0)
	assert_int(pm.alive[i]).is_equal(0)
	assert_int(Run.run_gold).is_greater(g0)


# ---------------------------------------------------------------- the slime

func test_the_slime_plays_sl_c_and_looks_at_the_hero() -> void:
	var def: EnemyDef = Registry.enemy("blue_slime")
	assert_str(def.variant).is_equal("SL-C")
	assert_str(def.sprite_file).is_equal("blue_slime_sprite_c.png")
	# its front painting looks down to the viewer's left; the other paintings keep the default
	assert_str(def.front_faces).is_equal("left")
	assert_str(def.back_faces).is_equal("right")
	assert_str(def.variant_def("SL-A").front_faces).is_equal("right")
	var w := _world()
	var em: EnemyManager = w["em"]
	# one up and to the right of the hero (he is down-left of it), one up and to the left (he is down-right)
	var a := _creature(em, "blue_slime", Vector3(2, 0, -3))
	var b := _creature(em, "blue_slime", Vector3(-2, 0, -3))
	for k in range(6):
		em._physics_process(DT)
	var t: int = em.type_idx[a]
	var sa := em._strip_of(a, t)
	var sb := em._strip_of(b, t)
	assert_int(em.away[a]).is_equal(0)
	# heading down-left it shows the painting as it is, looking left at him; heading down-right, mirrored, looking right
	assert_int(em.flip[a]).is_equal(1)
	assert_float(em._face_bit(em.flip[a], t, sa)).is_equal(0.0)
	assert_int(em.flip[b]).is_equal(0)
	assert_float(em._face_bit(em.flip[b], t, sb)).is_equal(1.0)
	# the back set turns like everything else's
	assert_float(em._face_bit(0, t, 5)).is_equal(0.0)
	assert_float(em._face_bit(1, t, 5)).is_equal(1.0)
