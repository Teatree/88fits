extends GdUnitTestSuite

## Pass 81, lane POLISH (Garry, 2026-10-15): the Killer Bees' trails (a researched look, ProjectileManager.BEE_LOOKS in the
## tracers' ring and tracer_line.gdshader, `params.missile.trail_style`, "dash" by default), the Vulture Raider's rocket
## at 85% of the hero's top speed on the ground (ProjectileManager.rocket_clock_pace: the whole creature pace comes out of
## its speed), and the Saiga Sniper that never runs (no flee on hit, flee_range 0) and walks the Spit Cactus's way a bit
## faster, its aim still spoiled by a hit (sniper.spoil_on_hit).

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
var toasts: Array = []
var hints: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func hint_once(a, _b) -> void:
	hints.append(str(a))
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func rocket_out(_i: int) -> bool:
	return false
func on_creature_died_index(_i) -> void:
	pass
"""

## The hero: a top speed like the real one's (his move_speed x the map's move_pace), tunable.
const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
var max_hp := 100.0
var top := 5.0
var hits: Array = []
func take_damage(a: float, f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "from": f, "info": i})
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h: bool = true) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return top * Run.move_pace()
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.level = 1


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
	g.set("player", hero)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.set("projectiles", pm)
	pm.register_kind(BoxMesh.new(), null, 1.0, true)
	return {"g": g, "hero": hero, "em": em, "pm": pm}


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _run(em: EnemyManager, seconds: float, pm: ProjectileManager = null) -> void:
	for k in range(int(ceilf(seconds / DT))):
		em._physics_process(DT)
		if pm:
			pm._physics_process(DT)


func _run_until(em: EnemyManager, cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		em._physics_process(DT)
		t += DT
		if cond.call():
			return t
	return -1.0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _inst(id: String) -> WeaponInstance:
	var wi := WeaponInstance.new(Registry.weapon(id), 1)
	wi.rebuild(Run.player_sheet, [wi])
	return wi


# ---------------------------------------------------------------- 1. the rocket at 85% of the hero

func test_the_raider_names_85_percent_of_the_hero() -> void:
	var ms: Dictionary = Registry.enemy("rocketeer").artillery["missile"]
	assert_float(float(ms["speed_of_hero"])).is_equal_approx(0.85, 0.0001)
	var d := _json("res://content/enemies/rocketeer/rocketeer.json")
	assert_float(float(d["artillery"]["missile"]["speed_of_hero"])).is_equal_approx(0.85, 0.0001)
	# the rest of its behaviour kept: the turn, the slow on every hit (pass 73)
	assert_float(float(ms["turn"])).is_greater(0.0)
	assert_bool(ms.get("hit_slow") is Dictionary and (ms["hit_slow"] as Dictionary).has("mult")).is_true()


func test_the_rocket_flies_at_85_percent_of_the_heros_top_speed_on_the_ground() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	# whatever the map's knobs: the pace knob and the creatures' own speed (Red Canyon 0.9 and 0.9), High Noon off
	for knobs: Array in [[1.0, 1.0], [0.9, 0.9], [0.8, 1.2]]:
		Run.map.timeline.move_pace = float(knobs[0])
		em.creature_speed_mult = float(knobs[1])
		em._physics_process(DT)
		assert_float(em.pace).is_equal_approx(float(knobs[0]) * float(knobs[1]), 0.0001)
		for top: float in [5.0, 6.5]:
			hero.set("top", top)
			# far off, so it never reaches him inside the test
			var k := pm.launch_enemy_rocket(0, 3, Vector3(0, 1, 80), Vector3(0, 0, -1), 4.0, 1.3, 22.0, 1.6, 0.85)
			pm._physics_process(DT)
			var want: float = 0.85 * float(hero.max_speed())
			assert_float(pm.rocket_ground_speed(k)).override_failure_message("%s top %s" % [knobs, top]).is_equal_approx(want, want * 0.01)
			# the ground it covers in a second of play is that share of the ground he covers at his top speed
			var z0: float = pm.pos[k].z
			for n in range(60):
				pm._physics_process(DT)
			assert_float(absf(pm.pos[k].z - z0)).is_equal_approx(want, want * 0.03)
			pm._free(k)
	Run.map.timeline.move_pace = 0.9


func test_high_noon_and_a_hit_still_slow_the_rocket() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	em._physics_process(DT)
	var i := em.spawn("rocketeer", Vector3(30, 0, 0))
	var ms: Dictionary = Registry.enemy("rocketeer").artillery["missile"]
	var k := pm.launch_enemy_rocket(0, i, Vector3(100, 1, 0), Vector3(-1, 0, 0), 4.0, 1.3, 20.0, 1.6, 0.85, {}, ms)
	pm._physics_process(DT)
	var full: float = pm.rocket_ground_speed(k)
	assert_float(full).is_equal_approx(0.85 * float(hero.max_speed()), 0.05)
	em.time_scale = 0.5
	pm._physics_process(DT)
	assert_float(pm.rocket_ground_speed(k)).is_equal_approx(full * 0.5, full * 0.02)
	em.time_scale = 1.0
	em.damage(i, 0.1, "revolver")
	pm._physics_process(DT)
	assert_float(pm.rocket_ground_speed(k)).is_equal_approx(full * float(ms["hit_slow"]["mult"]), full * 0.03)


# ---------------------------------------------------------------- 2. the Saiga Sniper

func test_the_saiga_never_runs_and_is_a_bit_faster_than_the_spit_cactus() -> void:
	var d := _json("res://content/enemies/saiga_sniper/saiga_sniper.json")
	assert_bool(d.has("flee_on_hit")).is_false()
	var def: EnemyDef = Registry.enemy("saiga_sniper")
	assert_bool(def.flee_on_hit.is_empty()).is_true()
	assert_str(def.brain).is_equal("sniper")
	assert_float(float(def.sniper.get("flee_range", 0.0))).is_equal(0.0)
	assert_bool(bool(def.sniper.get("spoil_on_hit", true))).is_true()
	# a bit faster than the cactus: more, but not twice (Garry tunes the number in the Level Editor; read, not pinned)
	var cactus: EnemyDef = Registry.enemy("spit_cactus")
	assert_float(def.speed).is_greater(cactus.speed)
	assert_float(def.speed).is_less(cactus.speed * 2.0)
	# it walks in: its range is inside its spawn's stand-off
	assert_float(float(def.sniper["follow"])).is_less(float(def.sniper["stand_off"]))


func test_the_saiga_walks_in_to_its_range_holds_and_aims() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(12, 0, 0))
	var def: EnemyDef = Registry.enemy("saiga_sniper")
	var sn: Dictionary = def.sniper
	var follow := float(sn["follow"])
	# placed at its stand-off from the hero
	assert_float(_flat(em.pos[i], Vector3.ZERO)).is_equal_approx(float(sn["stand_off"]), 0.05)
	# it walks in towards him at its speed (the pace knob in it), like the Spit Cactus
	var d0 := _flat(em.pos[i], hero.global_position)
	_run(em, 2.0)
	var d1 := _flat(em.pos[i], hero.global_position)
	assert_float(d0 - d1).is_equal_approx(em.speed[i] * 2.0, em.speed[i] * 0.5)
	assert_int(em.sniper_aims).is_equal(0)
	# then it holds inside its range and aims
	var t := _run_until(em, func() -> bool: return em.state[i] == EnemyManager.STATE_WINDUP, 20.0)
	assert_float(t).is_greater(0.0)
	var held := _flat(em.pos[i], hero.global_position)
	assert_float(held).is_between(follow - 1.0, follow + 0.2)
	assert_int(em.sniper_aims).is_equal(1)
	# and it does not come any closer while he stays: it rests where it is between shots
	_run(em, 8.0)
	assert_float(_flat(em.pos[i], hero.global_position)).is_greater(follow - 1.5)


func test_the_saiga_never_backs_off_when_the_hero_walks_up() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(12, 0, 0))
	# the hero walks right up to him (inside where pass 73's flee_range 14 sent him running)
	for d: float in [12.0, 6.0, 2.5]:
		hero.global_position = em.pos[i] + Vector3(-d, 0, 0)
		var at0: Vector3 = em.pos[i]
		var gap0 := _flat(em.pos[i], hero.global_position)
		_run(em, 1.5)
		assert_float(_flat(em.pos[i], hero.global_position)).override_failure_message("at %s m" % d).is_less_equal(gap0 + 0.3)
		assert_float(_flat(em.pos[i], at0)).override_failure_message("at %s m" % d).is_less(0.6)
	assert_bool(em.is_fleeing(i)).is_false()
	assert_int(em.flee_starts).is_equal(0)


func test_a_hit_spoils_the_saigas_aim_and_never_sends_him_running() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(12, 0, 0))
	var t := _run_until(em, func() -> bool: return em.state[i] == EnemyManager.STATE_WINDUP, 20.0)
	assert_float(t).is_greater(0.0)
	_run(em, 0.5)
	var at0: Vector3 = em.pos[i]
	# a poison or fire tick spoils nothing
	em.damage(i, 0.1, "", Vector3.ZERO, 0.0, true)
	assert_int(em.sniper_cancels).is_equal(0)
	em.damage(i, 1.0, "revolver")
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_int(em.sniper_cancels).is_equal(1)
	assert_bool(em.is_fleeing(i)).is_false()
	assert_int(em.flee_starts).is_equal(0)
	_run(em, 1.0)
	# he stays where he was (inside his range he holds), no shot came of it
	assert_float(_flat(em.pos[i], at0)).is_less(0.3)
	assert_int(em.sniper_shots).is_equal(0)
	assert_int((hero.hits as Array).size()).is_equal(0)
	# with spoil_on_hit false the aim goes on
	var d: EnemyDef = Registry.enemy("saiga_sniper").duplicate()
	d.id = "p81_stubborn"
	d.variance = {}
	d.sniper = (d.sniper as Dictionary).duplicate(true)
	d.sniper["spoil_on_hit"] = false
	Registry.enemies[d.id] = d
	var j := em.spawn(d.id, Vector3(-12, 0, 0))
	_run_until(em, func() -> bool: return em.state[j] == EnemyManager.STATE_WINDUP, 20.0)
	_run(em, 0.3)
	em.damage(j, 1.0, "revolver")
	assert_int(em.state[j]).is_equal(EnemyManager.STATE_WINDUP)
	Registry.enemies.erase(d.id)


func test_the_locked_line_still_gives_the_hero_time_at_the_saigas_range() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(12, 0, 0))
	var def: EnemyDef = Registry.enemy("saiga_sniper")
	var sn: Dictionary = def.sniper
	var t_lock := _run_until(em, func() -> bool: return em._snipers.has(i) and int(em._snipers[i]["phase"]) == EnemyManager.SNIPER_LOCK, 25.0)
	assert_float(t_lock).is_greater(0.0)
	# at its range: the hold (lock / pace) is several times what he needs to walk off the line at his top speed
	assert_float(_flat(em.pos[i], hero.global_position)).is_less_equal(float(sn["follow"]) + 0.5)
	var hold := float(sn["lock"]) / em.pace
	var need := (float(sn["beam"]["width"]) * 0.5 + EnemyManager.SNIPER_HERO_R) / float(hero.max_speed())
	assert_float(hold).is_greater(need * 4.0)
	# he steps off sideways at his top speed for a third of the hold: the shot misses
	var ldir: Vector3 = em._snipers[i]["ldir"]
	var side := Vector3(-ldir.z, 0, ldir.x)
	var steps := int(hold / 3.0 / DT)
	for n in range(steps):
		hero.global_position += side * float(hero.max_speed()) * DT
		em._physics_process(DT)
	_run_until(em, func() -> bool: return em.sniper_shots > 0, 3.0)
	assert_int(em.sniper_shots).is_equal(1)
	assert_int((hero.hits as Array).size()).is_equal(0)


# ---------------------------------------------------------------- 3. the bees' trails

func test_the_bees_default_trail_look_is_the_dash_and_the_others_are_one_word_away() -> void:
	assert_str(ProjectileManager.BEE_TRAIL_STYLE).is_equal("dash")
	for id: String in ["hornet_nest", "hive_queen", "killer_swarm"]:
		var d: WeaponDef = Registry.weapon(id)
		assert_object(d).override_failure_message(id).is_not_null()
		var m: Dictionary = d.params["missile"]
		assert_int(int(m["trail"])).override_failure_message(id).is_equal(2)
		assert_str(str(m.get("trail_style", ""))).override_failure_message(id).is_equal("dash")
	# the names: a bee (2) and a red bee (4) wear a look, the rocket's smoke (1) never does, "beads" is pass 49's
	assert_str(ProjectileManager.bee_trail_look(2, "")).is_equal("dash")
	assert_str(ProjectileManager.bee_trail_look(4, "")).is_equal("dash")
	for s: String in ["dash", "buzz", "bumble", "zip"]:
		assert_str(ProjectileManager.bee_trail_look(2, s)).is_equal(s)
	assert_str(ProjectileManager.bee_trail_look(2, "beads")).is_equal("")
	assert_str(ProjectileManager.bee_trail_look(2, "sparkles")).is_equal("dash")
	assert_str(ProjectileManager.bee_trail_look(1, "dash")).is_equal("")
	# the bees' own style ids sit past the guns' tracer styles (one ring, one shader)
	for k: String in ProjectileManager.BEE_STYLE_IDS:
		assert_bool(ProjectileManager.TRACER_STYLE_IDS.values().has(int(ProjectileManager.BEE_STYLE_IDS[k]))).is_false()
	for k: String in ProjectileManager.BEE_LOOKS:
		var lk: Dictionary = ProjectileManager.BEE_LOOKS[k]
		# short (pass 49's beads lived 1.4 s) and readable
		assert_float(float(lk["life"])).override_failure_message(k).is_less_equal(0.5)
		assert_float(float(lk["width"])).override_failure_message(k).is_greater(0.05)


func test_a_bee_lays_dashes_in_the_tracers_ring_and_drops_no_beads() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var hn := _inst("hornet_nest")
	var beads0 := pm.trail_next
	var segs0 := pm.bee_segments
	var k := pm.launch_missile(0, Vector3(0, 1.5, 0), Vector3(1, 0.3, 0), 15.0, 5.0, 0.0, 11.0, hn,
		{"wander": 0.3, "turn": 9.0, "spiral": 12.0, "life": 3.0, "trail": 2, "trail_style": "dash"}, 1.0)
	assert_str(str(pm.extra[k]["bee"])).is_equal("dash")
	for n in range(20):
		pm._physics_process(DT)
	assert_int(pm.bee_segments).is_greater(segs0 + 3)
	assert_int(pm.trail_next).is_equal(beads0)
	var last: int = (pm._ln_next - 1 + ProjectileManager.TRACER_LINE_MAX) % ProjectileManager.TRACER_LINE_MAX
	assert_int(pm.tracer_kind[last]).is_equal(int(ProjectileManager.BEE_STYLE_IDS["dash"]))
	assert_float(pm.tracer_life[last]).is_equal_approx(float(ProjectileManager.BEE_LOOKS["dash"]["life"]), 0.0001)
	# the path's length rides in the hot slot, kept under the wrap
	assert_float(pm.tracer_hot[last]).is_between(0.0, ProjectileManager.BEE_WRAP)
	# a red bee (Pollen) wears the look's red; "beads" brings pass 49's beads back
	var r := pm.launch_missile(0, Vector3(0, 1.5, 0), Vector3(-1, 0.3, 0), 15.0, 5.0, 0.0, 11.0, hn,
		{"wander": 0.3, "turn": 9.0, "spiral": 12.0, "life": 3.0, "trail": 4}, 1.0)
	assert_bool((pm.extra[r]["bee_col"] as Color).is_equal_approx(ProjectileManager.BEE_LOOKS["dash"]["red"])).is_true()
	var b := pm.launch_missile(0, Vector3(0, 1.5, 0), Vector3(0, 0.3, 1), 15.0, 5.0, 0.0, 11.0, hn,
		{"wander": 0.3, "turn": 9.0, "spiral": 12.0, "life": 3.0, "trail": 2, "trail_style": "beads"}, 1.0)
	assert_bool(pm.extra[b].has("bee")).is_false()
	for n in range(10):
		pm._physics_process(DT)
	assert_int(pm.trail_next).is_not_equal(beads0)


func test_the_killer_bees_pod_hands_its_trail_look_to_its_bees() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var c := em.spawn("skeleton", Vector3(5, 0, 0))
	em.hp[c] = 1000.0
	em._rebuild_grid()
	var hn := _inst("hornet_nest")
	hn.params["missile"]["trail_style"] = "buzz"
	var mp := MissilePod.new()
	g.add_child(mp)
	mp.setup(hn, g)
	assert_bool(mp._fire()).is_true()
	for n in range(30):
		mp._tick(DT)
	var seen := 0
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == hn:
			assert_str(str(pm.extra[j].get("bee", ""))).is_equal("buzz")
			seen += 1
	assert_int(seen).is_greater(0)
