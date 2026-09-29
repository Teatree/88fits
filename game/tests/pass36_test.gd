extends GdUnitTestSuite

## Pass 36: fire and poison share a run (the one-element rule is gone), and bombs spread: every bomb weapon, and every
## bomb of a volley, picks a crowd no other bomb is headed for or has just come down on; they double up only when there
## is no other crowd in range.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var telegraphs = null
var fx = null
var map = null
var camera = null
var paused := false
func fx_hit(_a, _b) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func forward() -> Vector3:
	return Vector3(0, 0, -1)
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1, 0) + d * 0.4
"""

const A := Vector3(6.0, 0, 0)
const B := Vector3(-6.0, 0, 0.5)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _setup() -> Node:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
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
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	pm.register_kind(BoxMesh.new(), null, 1.0)
	return g


func _crowd(g: Node, at: Vector3, n: int) -> void:
	var em: EnemyManager = g.enemies
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var i := em.spawn("goblin", at + Vector3(cos(a), 0, sin(a)) * 0.8, null, 1.0, 50.0)
		em.state[i] = EnemyManager.STATE_MOVE


func _bomber(g: Node, id: String, extra_amount: int = 0) -> Lobber:
	var b := Lobber.new()
	b.inst = WeaponInstance.new(Registry.weapon(id), 1)
	if extra_amount > 0:
		b.inst.bonus_effects = [Effect.make("amount", "add", extra_amount)]
	b.inst.rebuild(Run.player_sheet, [])
	b.game = g
	b.player = g.player
	b.projectile_kind = 0
	g.add_child(b)
	return b


func _near(spots: Array, at: Vector3, r: float) -> int:
	var n := 0
	for s: Vector3 in spots:
		if Vector2(s.x - at.x, s.z - at.z).length() < r:
			n += 1
	return n


# ---------------------------------------------------------------- the rule is gone

func test_a_run_holds_fire_and_poison_together() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("molotov"), 1)
	Run.add_weapon(Registry.weapon("skull_rain"), 1)
	assert_str(Run.weapon_instance("molotov").element()).is_equal("fire")
	assert_str(Run.weapon_instance("skull_rain").element()).is_equal("poison")
	# the other element's cards still come
	var seen := {}
	for k in range(200):
		for c in CardPool.level_up_offer(3):
			seen[str(c["id"])] = true
	assert_bool(seen.has("venom")).override_failure_message("no poison card for a fire and poison build").is_true()
	assert_bool(seen.has("kindling")).override_failure_message("no fire card for a fire and poison build").is_true()


# ---------------------------------------------------------------- bombs spread

func test_two_bomb_weapons_pick_two_crowds() -> void:
	var g := _setup()
	_crowd(g, A, 6)
	_crowd(g, B, 5)
	g.enemies._rebuild_grid()
	var grenade := _bomber(g, "lob_grenade")
	var molotov := _bomber(g, "molotov")
	assert_bool(grenade._fire()).is_true()
	assert_bool(molotov._fire()).is_true()
	var spots: Array = g.projectiles.claimed_spots()
	assert_int(spots.size()).is_equal(2)
	# the grenade takes the thicker crowd; the Molotov, seeing it spoken for, the other one
	assert_int(_near(spots, A, 2.0)).is_equal(1)
	assert_int(_near(spots, B, 2.0)).is_equal(1)


func test_one_volley_spreads_over_the_crowds() -> void:
	var g := _setup()
	_crowd(g, A, 6)
	_crowd(g, B, 5)
	g.enemies._rebuild_grid()
	var grenade := _bomber(g, "lob_grenade", 1)
	assert_int(grenade.stat_int("amount", 1)).is_equal(2)
	assert_bool(grenade._fire()).is_true()
	var spots: Array = g.projectiles.claimed_spots()
	assert_int(_near(spots, A, 2.0)).is_equal(1)
	assert_int(_near(spots, B, 2.0)).is_equal(1)


func test_one_crowd_takes_every_bomb() -> void:
	var g := _setup()
	_crowd(g, A, 6)
	g.enemies._rebuild_grid()
	var grenade := _bomber(g, "lob_grenade")
	var molotov := _bomber(g, "molotov")
	assert_bool(grenade._fire()).is_true()
	# nowhere else to go: the Molotov still throws, at the same crowd
	assert_bool(molotov._fire()).is_true()
	assert_int(_near(g.projectiles.claimed_spots(), A, 3.0)).is_equal(2)


func test_a_landing_spot_stays_taken_for_a_moment() -> void:
	var g := _setup()
	var pm: ProjectileManager = g.projectiles
	pm._landed.append({"at": A, "t": ProjectileManager.LANDED_CLAIM})
	assert_int(_near(pm.claimed_spots(), A, 0.5)).is_equal(1)
	pm._physics_process(ProjectileManager.LANDED_CLAIM * 0.5)
	assert_int(_near(pm.claimed_spots(), A, 0.5)).is_equal(1)
	pm._physics_process(ProjectileManager.LANDED_CLAIM)
	assert_int(pm.claimed_spots().size()).is_equal(0)
