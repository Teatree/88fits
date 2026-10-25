extends GdUnitTestSuite

## Pass 107 (fix): a boss always comes, even with the creature pool full. The map's hard_cap (500) is above
## EnemyManager.MAX (320), so a late stage-3 crowd fills every slot, and a cleared field's bodies keep their slots while
## their deaths play; spawn() then returned -1 for the boss while the director had already gone into its boss phase
## (the clock stopped, the ring up), and the stage never reached its portal (hell_check: the Brander "gone at once", no
## portal, no Endless). EnemyManager.spawn_boss now makes a slot first (_room_for_boss): the dying body nearest its end,
## else the regular creature farthest from the hero.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var telegraphs = null
var fx = null
var map = null
var camera = null
var paused := false
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = false) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(_d: Vector3) -> Vector3:
	return global_position
"""

const FAKE_RIG := """extends Node
func zoom() -> float:
	return 1.0
func current_yaw() -> float:
	return 0.0
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _manager() -> EnemyManager:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var rig := Node.new()
	rig.set_script(_script(FAKE_RIG))
	g.add_child(rig)
	g.camera = rig
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	return em


## Every slot taken by a plain, settled goblin (no special, up out of the ground), `k` m east of the hero for slot k.
func _fill(em: EnemyManager) -> void:
	var k := 0
	while not em.free_list.is_empty():
		var i := em.spawn("goblin", Vector3(1.0 + float(k) * 0.1, 0, 0))
		assert_int(i).is_greater_equal(0)
		em.vspecial[i] = 0
		em.rise_t[i] = 1.0
		em.rise_v[i] = 0.0
		k += 1
	assert_int(em.free_list.size()).is_equal(0)


func test_the_boss_comes_when_the_pool_is_full_of_bodies() -> void:
	var em := _manager()
	_fill(em)
	em.kill_all(true)
	# kill_all's deaths keep their slots while they play; the one nearest its end gives its slot
	assert_int(em.free_list.size()).is_equal(0)
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1 and em.state[i] == EnemyManager.STATE_DYING:
			em.timer[i] = 0.5
	var soonest := 11
	assert_int(em.state[soonest]).is_equal(EnemyManager.STATE_DYING)
	em.timer[soonest] = 0.01
	var b := em.spawn_boss("brander", Vector3(5, 0, 5))
	assert_int(b).is_equal(soonest)
	assert_int(em.boss_index).is_equal(b)
	assert_bool(em.boss_alive()).is_true()
	assert_str((em.types[em.type_idx[b]]["def"] as EnemyDef).id).is_equal("brander")


func test_the_boss_comes_when_the_pool_is_full_of_live_creatures() -> void:
	var em := _manager()
	_fill(em)
	# the farthest from the hero gives way
	var far := 7
	em.pos[far] = Vector3(120, 0, 0)
	var before := em.alive_count()
	var b := em.spawn_boss("brander", Vector3(5, 0, 5))
	assert_int(b).is_equal(far)
	assert_int(em.boss_index).is_equal(b)
	assert_int(em.despawned).is_equal(1)
	assert_int(em.alive_count()).is_equal(before)


func test_a_boss_with_room_takes_nothing_away() -> void:
	var em := _manager()
	var i := em.spawn("goblin", Vector3(3, 0, 0))
	var b := em.spawn_boss("brander", Vector3(5, 0, 5))
	assert_int(b).is_greater_equal(0)
	assert_int(em.alive[i]).is_equal(1)
	assert_int(em.despawned).is_equal(0)
