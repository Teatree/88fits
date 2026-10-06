extends GdUnitTestSuite

## Pass 45, the Stone Golem: the third Elite, slow and the toughest, with a smack, a swoop of stalactites over a
## half-disc and a boulder hurled across the map. An attack's `max_range` is skipped while the hero keeps away (where
## `reach` would wait and hold the cycle), the swoop draws a "sector" telegraph and hits a hero inside its wedge once,
## and a throw spares the creature it is told to (the golem under its own stalactites and its own boulder).

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var paused := false
var thrown := 0
var sectors := 0
var rings := 0
var spikes := 0
var spike_hits := 0
func toast(_t, _c = null) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	rings += 1
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	sectors += 1
func throw_boulder(_i, _f, _t, _a, _m, _n) -> void:
	thrown += 1
func stalactite(_a, _b, _c = 1.0) -> void:
	spikes += 1
func stalactite_hit(_a) -> void:
	spike_hits += 1
func fx_burst(_a, _b, _c) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var hits := 0
var blasts := 0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	blasts += 1
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game with a fake hero at the origin and a real EnemyManager wired to both.
func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	return {"g": g, "hero": hero, "em": em}


func _run(em: EnemyManager, hero: Node3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		em._update_boss(DT, hero.global_position)
		t += DT


func _attack_named(d: EnemyDef, name: String) -> Dictionary:
	for atk in d.boss.get("attacks", []):
		if str((atk as Dictionary).get("name", "")) == name:
			return atk
	return {}


# ---------------------------------------------------------------- the data

func test_the_golem_is_the_third_elite_in_the_data() -> void:
	var d: EnemyDef = Registry.enemy("stone_golem")
	assert_object(d).is_not_null()
	assert_str(d.archetype).is_equal("elite")
	assert_str(d.brain).is_equal("chase")
	var sc: EnemyDef = Registry.enemy("dune_scorpion")
	var sp: EnemyDef = Registry.enemy("sun_prophet")
	# the toughest and the slowest of the three
	assert_float(d.hp).is_greater(sc.hp)
	assert_float(d.hp).is_greater(sp.hp)
	assert_float(d.speed).is_less(sc.speed)
	assert_float(d.speed).is_less(sp.speed)
	assert_bool(d.can_be_elite).is_false()
	assert_bool(d.can_be_grabbed).is_false()
	assert_float(float(d.elite.get("hp_mult_per_stage", 0.0))).is_equal(1.8)
	var names: Array = []
	for atk in d.boss.get("attacks", []):
		names.append(str((atk as Dictionary).get("name", "")))
	assert_array(names).contains_exactly(["slam", "swoop", "boulder"])
	var slam := _attack_named(d, "slam")
	var swoop := _attack_named(d, "swoop")
	var boulder := _attack_named(d, "boulder")
	# the two close attacks are gated by max_range (never reach: that would hold the cycle), the boulder by nothing
	assert_bool(slam.has("max_range")).is_true()
	assert_bool(swoop.has("max_range")).is_true()
	assert_bool(slam.has("reach")).is_false()
	assert_bool(swoop.has("reach")).is_false()
	assert_bool(boulder.has("max_range")).is_false()
	assert_bool(boulder.has("min_range")).is_false()
	assert_float(float(slam["max_range"])).is_less(float(swoop["max_range"]))
	assert_str(str(slam.get("telegraph", ""))).is_equal("ring")
	assert_str(str(swoop.get("telegraph", ""))).is_equal("sector")
	assert_str(str(boulder.get("telegraph", ""))).is_equal("ring_at_hero")
	# the swoop's half-disc is as wide as the dwarf's wedge, the boulder's ring the size of the scorpion's burrow
	var dwarf: EnemyDef = Registry.enemy("buckshot_dwarf")
	assert_float(float(swoop["radius"])).is_equal_approx(float(dwarf.ranged.get("range", 5.0)) + 1.5, 0.01)
	assert_float(float(swoop.get("deg", 0.0))).is_equal_approx(180.0, 0.01)
	var burrow := _attack_named(sc, "burrow")
	assert_float(float(boulder["radius"])).is_equal_approx(float(burrow.get("radius", 0.0)), 0.01)
	assert_str(d.badge_for()).is_equal("crown")
	assert_float(float(d.drops.get("chest", 0.0))).is_equal(1.0)
	assert_str(str(d.sfx.get("attack", ""))).is_equal("en_golem_attack")
	for sid in ["en_golem_attack", "en_golem_throw", "en_golem_hit", "en_golem_die", "en_boulder_land", "en_stalactite_hit"]:
		assert_bool(Registry.soundmap.entries.has(sid)).override_failure_message("no sound row for " + sid).is_true()
	# every Elite event of Red Canyon may roll it
	var m: MapDef = Registry.map("red_canyon")
	var events := 0
	for ev in m.timeline.events:
		if str(ev.get("type", "")) == "elite_boss":
			events += 1
			assert_array(ev.get("enemy", [])).contains(["stone_golem"])
	assert_int(events).is_equal(3)


# ---------------------------------------------------------------- the range gate

func test_the_close_attacks_give_way_to_the_boulder_at_range() -> void:
	var w := _world()
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var em: EnemyManager = w["em"]
	var i := em.spawn("stone_golem", Vector3(0, 0, -12))
	assert_int(i).is_greater_equal(0)
	# the hero 12 m off: the smack (3.6) and the swoop (6.0) are skipped, the boulder flies to the ring on his spot
	em.atk_i[i] = 0
	em.atk_t[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	em._update_boss(DT, hero.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int((em.atk_i[i] - 1) % 3).is_equal(2)
	assert_int(g.rings).is_equal(1)
	assert_int(g.sectors).is_equal(0)
	# its 1.1 s wind-up lasts 1/pace (pass 48: Red Canyon's 0.8 makes it 1.375 s)
	_run(em, hero, 1.3 / Run.move_pace())
	assert_int(g.thrown).is_equal(1)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[i]).is_greater(0.0)
	# the hero 1.5 m off: the smack, nothing skipped
	hero.global_position = Vector3(0, 0, -10.5)
	em.atk_i[i] = 0
	em.atk_t[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	em._update_boss(DT, hero.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int((em.atk_i[i] - 1) % 3).is_equal(0)
	# the hero 5 m off: past the smack, inside the swoop
	hero.global_position = Vector3(0, 0, -7)
	em.atk_i[i] = 0
	em.atk_t[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	em._update_boss(DT, hero.global_position)
	assert_int((em.atk_i[i] - 1) % 3).is_equal(1)
	# the helper itself: min_range skips inside, max_range skips beyond, neither skips in between
	assert_bool(em._attack_out_of_range({"max_range": 3.6}, 5.0)).is_true()
	assert_bool(em._attack_out_of_range({"max_range": 3.6}, 2.0)).is_false()
	assert_bool(em._attack_out_of_range({"min_range": 4.0}, 2.0)).is_true()
	assert_bool(em._attack_out_of_range({"min_range": 4.0}, 5.0)).is_false()
	assert_bool(em._attack_out_of_range({}, 50.0)).is_false()


# ---------------------------------------------------------------- the swoop

func test_the_swoop_rains_stalactites_on_its_half_disc_and_hits_once() -> void:
	var w := _world()
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var em: EnemyManager = w["em"]
	var i := em.spawn("stone_golem", Vector3(0, 0, -12))
	assert_int(i).is_greater_equal(0)
	em._rebuild_grid()
	hero.global_position = Vector3(0, 0, -8)
	em.atk_i[i] = 1
	em.atk_t[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	em._update_boss(DT, hero.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int((em.atk_i[i] - 1) % 3).is_equal(1)
	assert_int(g.sectors).is_equal(1)
	# the wind-up ends: the swoop is queued and the golem stands under it (the 1.0 s wind-up and every 0.45 s fall last
	# 1/pace since pass 48: 1.25 s and 0.5625 s at Red Canyon's 0.8)
	var pc := Run.move_pace()
	_run(em, hero, 1.1 / pc)
	assert_int(em._stalactites.size()).is_equal(1)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.hold_t[i]).is_greater(0.0)
	# every stalactite is placed inside the half-disc towards the hero and falls
	_run(em, hero, 2.0 / pc)
	assert_int(g.spikes).is_equal(14)
	assert_int(g.spike_hits).is_equal(14)
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.blasts).is_equal(1)
	assert_int(em._stalactites.size()).is_equal(0)
	# the golem at the apex was never thrown by its own stones
	assert_float(em.kb[i].length()).is_equal(0.0)
	# the swoop is aimed at the hero as it winds up; a hero who then gets behind the golem is outside the wedge: no hit
	var g2: Node = w["g"]
	hero.global_position = em.pos[i] + Vector3(0, 0, 4)
	em.atk_i[i] = 1
	em.atk_t[i] = 0.0
	em.hold_t[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	em._update_boss(DT, hero.global_position)
	assert_int((em.atk_i[i] - 1) % 3).is_equal(1)
	hero.global_position = em.pos[i] + Vector3(0, 0, -4)
	_run(em, hero, 3.5 / pc)
	assert_int(g2.spikes).is_equal(28)
	assert_int(hero.hits).is_equal(1)


# ---------------------------------------------------------------- the throw that spares one

func test_a_throw_spares_the_creature_it_is_told_to() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := em.spawn("goblin", Vector3(1.0, 0, 0))
	var b := em.spawn("goblin", Vector3(-1.0, 0, 0))
	assert_int(a).is_greater_equal(0)
	assert_int(b).is_greater_equal(0)
	em._rebuild_grid()
	var n := em.throw_radius(Vector3.ZERO, 3.0, 10.0, a)
	assert_int(n).is_equal(1)
	assert_float(em.kb[a].length()).is_equal(0.0)
	assert_float(em.kb[b].length()).is_greater(0.0)
	# and without an exception both go
	em.kb[b] = Vector3.ZERO
	assert_int(em.throw_radius(Vector3.ZERO, 3.0, 10.0)).is_equal(2)
	assert_float(em.kb[a].length()).is_greater(0.0)
