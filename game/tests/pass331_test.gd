extends GdUnitTestSuite

## Pass 33.1: the ranged Elite stands where the screen shows him, the back gesture never pauses a run, a companion
## nothing flies still follows the hero, the Strongbox is painted like every structure.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles: ProjectileManager
var map = null
var enemies = null
var paused := false
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func test_the_prophet_stands_where_the_screen_shows_him() -> void:
	var em: EnemyManager = auto_free(EnemyManager.new())
	add_child(em)
	# off to the side and a little up: pulled in to the screen's width, and eight metres up it (north, the camera's
	# forward with no camera)
	em.pos[0] = Vector3(12.0, 0.0, -2.0)
	var spot: Vector3 = em._screen_spot(0, Vector3.ZERO, 8.0, 3.5)
	assert_float(spot.x).is_equal_approx(3.5, 0.01)
	assert_float(spot.z).is_equal_approx(-8.0, 0.01)
	# already well below the hero: a little below him, not across the whole screen
	em.pos[0] = Vector3(-1.0, 0.0, 9.0)
	spot = em._screen_spot(0, Vector3.ZERO, 8.0, 3.5)
	assert_float(spot.z).is_greater(0.0)
	assert_float(spot.z).is_less_equal(6.0)
	assert_float(spot.x).is_equal_approx(-1.0, 0.01)


func test_the_prophet_casts_from_the_screen() -> void:
	var p: EnemyDef = Registry.enemy("sun_prophet")
	assert_float(float(p.caster.get("attack_range", 0.0))).is_greater(0.0)
	assert_float(float(p.caster.get("attack_range", 99.0))).is_less_equal(13.0)
	var blink := {}
	for atk in p.boss.get("attacks", []):
		if str(atk.get("name", "")) == "blink":
			blink = atk
	assert_str(str(blink.get("to", ""))).is_equal("screen")


func test_a_back_gesture_never_quits_or_pauses_a_run() -> void:
	assert_bool(bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true))).is_false()


func test_a_companion_nobody_flies_follows_the_hero() -> void:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	g.add_child(hero)
	hero.global_position = Vector3(5.0, 0.0, 5.0)
	g.player = hero
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	# the Poison Dart after Needle Rain: a Lobber flying the dart's visual, which carries a Familiar
	var inst := WeaponInstance.new(Registry.weapon("poison_dart"), 3)
	inst.mutations.append(Registry.mutation("needle_rain"))
	inst.rebuild(Run.player_sheet, [inst])
	assert_str(inst.behavior()).is_equal("Lobber")
	var b := Lobber.new()
	g.add_child(b)
	b.setup(inst, g)
	assert_object(b._stray).is_not_null()
	# the hero walks off: the dart follows him instead of staying where it was loaded
	hero.global_position = Vector3(-20.0, 0.0, 12.0)
	for k in range(60):
		b._fly_stray(1.0 / 30.0)
	var d := Vector2(b._stray.global_position.x - hero.global_position.x, b._stray.global_position.z - hero.global_position.z).length()
	assert_float(d).is_less(2.5)


func test_the_poison_puddle_is_see_through() -> void:
	# the puddle is drawn with the spill mesh: vertex colours that fade to nothing at the rim, never a flat plate
	var c := ElementCloud.new()
	assert_float(c._puff_col.a).is_less_equal(0.3)
	c.free()


func test_the_strongbox_is_painted_like_every_structure() -> void:
	var d: StructureDef = Registry.structure("gold_bank")
	assert_str(d.prop).is_equal("")
	assert_str(str(d.params.get("spent", ""))).is_equal("fly_away")
	assert_bool(ResourceLoader.exists("res://art/sprites/props/st_gold_bank.png")).is_true()
