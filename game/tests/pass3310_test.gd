extends GdUnitTestSuite

## Pass 33.10: the harpoon is a leash. A hit no longer snaps the harpooner to the hero: the rope is as long as the throw,
## the harpooner stands where it threw from (its outline pulsing red) and reels in any slack. Walking towards it is free;
## walking away runs at 70% and drags it along, and while it is dragged it digs in with its wind-up frames.

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
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _setup() -> EnemyManager:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	return em


func test_walking_away_is_slower_walking_towards_is_not() -> void:
	# the thrower lies north (-Z) of the hero, so "away" is south (+Z)
	var away := Vector3(0, 0, 10)
	assert_float(Player.leash_of(Vector3(0, 0, -1), away, 0.7)).is_equal_approx(1.0, 0.0001)
	assert_float(Player.leash_of(Vector3(0, 0, 1), away, 0.7)).is_equal_approx(0.7, 0.0001)
	assert_float(Player.leash_of(Vector3(1, 0, 0), away, 0.7)).is_equal_approx(1.0, 0.0001)
	# a slant away is slowed by the part of the step that pulls on the rope
	assert_float(Player.leash_of(Vector3(1, 0, 1), away, 0.7)).is_equal_approx(1.0 - 0.3 * sqrt(0.5), 0.0001)


func test_the_rope_holds_the_throw_length_and_drags_only_when_taut() -> void:
	var em := _setup()
	var i: int = em.spawn("harpoon_troglodyte", Vector3(0, 0, -15))
	assert_int(i).is_greater_equal(0)
	em.tethered_i = i
	var before: Vector3 = em.pos[i]
	# the hero is 15 m off and the rope is as long as the throw: nothing moves, the harpooner does not jump to him
	assert_float(em.tether_pull(i, Vector3.ZERO, 15.0)).is_equal_approx(0.0, 0.0001)
	assert_float(em.pos[i].distance_to(before)).is_less(0.001)
	assert_float(em.tether_drag_t).is_equal(0.0)
	# he steps a metre further away: it comes a metre with him and digs in with its wind-up frames
	var moved: float = em.tether_pull(i, Vector3(0, 0, 1), 15.0)
	assert_float(moved).is_equal_approx(1.0, 0.01)
	assert_float(em.pos[i].z).is_equal_approx(-14.0, 0.01)
	assert_float(em.tether_drag_t).is_greater(0.0)
	assert_int(em._strip_of(i, em.type_idx[i])).is_equal(EnemyManager.A_ATTACK)


func test_the_holder_glows_and_a_dead_one_lets_go() -> void:
	var em := _setup()
	var i: int = em.spawn("harpoon_troglodyte", Vector3(0, 0, -12))
	em.tethered_i = i
	var lo := 1.0
	var hi := 0.0
	for k in range(40):
		em._glow_clock = float(k) * 0.05
		lo = minf(lo, em.tether_glow())
		hi = maxf(hi, em.tether_glow())
	# a slow pulse between a third and full strength
	assert_float(lo).is_less(0.45)
	assert_float(hi).is_greater(0.95)
	em.state[i] = EnemyManager.STATE_DYING
	assert_float(em.tether_pull(i, Vector3.ZERO, 5.0)).is_equal(-1.0)
