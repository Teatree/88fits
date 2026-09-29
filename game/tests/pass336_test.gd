extends GdUnitTestSuite

## Pass 33.6: the crown only over the two Elites, the Dune Scorpion's scripted attacks finish (its burrow came up
## nowhere and it stayed buried), and the hero's bars drawn by the HUD at his spot on screen, sized with the zoom.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var projectiles = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
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
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func test_the_scorpion_comes_up_from_its_burrow() -> void:
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
	var i := em.spawn("dune_scorpion", Vector3(0, 0, -12))
	assert_int(i).is_greater_equal(0)
	# the burrow is its first attack: straight into it
	em.atk_i[i] = 0
	em.atk_t[i] = 0.0
	em.state[i] = EnemyManager.STATE_MOVE
	em._update_boss(1.0 / 60.0, hero.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int(em.hidden[i]).is_equal(1)
	# the wind-up runs out and it bursts up where the ring was, where it can be hit again
	var t := 0.0
	while t < 3.0 and em.hidden[i] == 1:
		em._update_boss(1.0 / 60.0, hero.global_position)
		t += 1.0 / 60.0
	assert_int(em.hidden[i]).is_equal(0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_bool(em.damage(i, 1.0, "")).is_false()
	assert_float(em.hp[i]).is_less(em.max_hp[i])
	# and a buried scripted creature outside its attack is brought up whatever took it there
	em.hidden[i] = 1
	em.state[i] = EnemyManager.STATE_WINDUP
	em._update_boss(1.0 / 60.0, hero.global_position)
	assert_int(em.hidden[i]).is_equal(0)


func test_the_heros_bars_sit_under_him_and_shrink_with_the_zoom() -> void:
	# the anchor: the rig bolted north-up over a hero at the origin, projected without the shake
	var rig: CameraRig = auto_free(CameraRig.new())
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	var hero: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(hero)
	rig.snap_to(hero)
	var a1: Dictionary = rig.hero_anchor()
	var vp := rig.get_viewport().get_visible_rect().size
	# the hero sits in the middle of the screen across and in its lower half
	assert_float((a1["pos"] as Vector2).x).is_equal_approx(vp.x * 0.5, 1.0)
	assert_float((a1["pos"] as Vector2).y).is_greater(vp.y * 0.5)
	# the shake moves the camera, not the anchor
	rig.shake(3.0)
	rig._update(1.0 / 60.0)
	var a2: Dictionary = rig.hero_anchor()
	assert_float(((a2["pos"] as Vector2) - (a1["pos"] as Vector2)).length()).is_less(1.0)
	# zoomed out, the bars get smaller with the hero
	rig.zoom_override = 2.5
	rig._update(1.0)
	var a3: Dictionary = rig.hero_anchor()
	assert_float(float(a3["ppm"])).is_less(float(a1["ppm"]) * 0.5)
