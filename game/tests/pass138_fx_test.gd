extends GdUnitTestSuite

## Pass 138, lane FX. (1) Garry, 2026-11-10: "Barrel should flicker white when Player hits ... a similar enemy flicker that
## they get, just colour it white and back with a mask or something": a round that strikes a standing barrel sets its hit
## flash to 1 and it falls at the creatures' rate (EnemyManager: 1.0, minus delta x 6.0) to nothing in a sixth of a second,
## stopped by a pause; a round's break flashes the debris; walking into one flashes nothing; only the barrels' shader reads
## a flash, every scenery prop's compiles without it. (2) "Sun Attack leftover ring is a bit too much ... Maybe a slight
## and quickly dimming flame patch on the ground? The aiming mark is also a bit too much, make it less noticeable, but not
## by a lot": StrikeMarks.sun lays one small held blob (no ring) that dims fast and is gone by SUN_LIFE, a Zenith sweep's
## forty landings lay at most FLAME_FRAME_CAP flame tongues a frame and CAP patches, and the warning ring is a quarter
## fainter in the data.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var hud = null
var director = null
var barrels = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
"""

const FAKE_RIG := """extends Node
func shake(_a: float) -> void:
	pass
"""

const FAKE_DIRECTOR := """extends Node
var timeline = null
"""

const DT := 1.0 / 60.0
const EAST := Vector3(1, 0, 0)

var _was_on := true


func before_test() -> void:
	_was_on = Settings.shoot_barrels
	Settings.shoot_barrels = true
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Settings.shoot_barrels = _was_on


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game with a real BarrelField holding one barrel of kind `t` at (5, 0, 0), its MultiMeshes with custom data as
## the game makes them, real effects, pickups and a debris field.
func _world(t: int = 0) -> Dictionary:
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
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	d.timeline = WaveTimeline.new()
	g.director = d
	var pk := PickupManager.new()
	pk.game = g
	g.add_child(pk)
	g.pickups = pk
	var bf := BarrelField.new()
	bf.game = g
	g.add_child(bf)
	g.barrels = bf
	var names := ["_body_dark", "_body_light", "_body_power"]
	for k in range(3):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.instance_count = 1 + BarrelField.SPARE
		mm.visible_instance_count = 1 if k == t else 0
		bf.set(names[k], mm)
	bf.pos.append(Vector3(5, 0, 0))
	bf.light.append(t)
	bf.alive.append(1)
	bf.coins.append(0)
	bf._index_in.append(0)
	bf.shadows.append(-1)
	var deb := BarrelDebris.new()
	bf.add_child(deb)
	deb.setup(g, null, BarrelField.SPRITES)
	bf.debris = deb
	return {"g": g, "bf": bf, "deb": deb, "tg": tg, "fx": fx}


func _round(bf: BarrelField) -> int:
	return bf.shot_through(Vector3(0, 0.8, 0), Vector3(14, 0.8, 0), 0.3, {})


# ---------------------------------------------------------------- 1. the barrel's white flash

func test_a_shot_hit_flashes_the_barrel_white_and_it_falls_back_in_the_creatures_time() -> void:
	# the creatures' own rate (EnemyManager: flash 1.0, minus delta x 6.0)
	assert_float(BarrelField.FLASH_DECAY).is_equal(6.0)
	var w := _world(1)
	var bf: BarrelField = w["bf"]
	assert_float(bf.flash_of(0)).is_equal(0.0)
	assert_int(_round(bf)).is_equal(1)
	assert_int(bf.alive[0]).is_equal(1)
	assert_float(bf.flash_of(0)).is_equal(1.0)
	var mm: MultiMesh = bf.get("_body_light")
	# a tenth of a second: 0.4 left; a sixth and a frame: none, and the barrel's custom data is back to rest
	for k in range(6):
		bf._process(DT)
	assert_float(bf.flash_of(0)).is_equal_approx(0.4, 0.01)
	for k in range(5):
		bf._process(DT)
	assert_float(bf.flash_of(0)).is_equal(0.0)
	assert_bool(bf._flash.is_empty()).is_true()
	# (the headless renderer keeps no instance data; where it does, y is 0 again and z still the glint clock)
	if mm.instance_count > 0 and mm.get_instance_custom_data(0) != Color(0, 0, 0, 0):
		assert_float(mm.get_instance_custom_data(0).g).is_equal(0.0)
	# every hit flashes again
	_round(bf)
	assert_float(bf.flash_of(0)).is_equal(1.0)


func test_a_pause_holds_the_flash() -> void:
	var w := _world(1)
	var bf: BarrelField = w["bf"]
	_round(bf)
	w["g"].paused = true
	for k in range(30):
		bf._process(DT)
	assert_float(bf.flash_of(0)).is_equal(1.0)
	w["g"].paused = false
	for k in range(12):
		bf._process(DT)
	assert_float(bf.flash_of(0)).is_equal(0.0)


func test_a_breaking_round_flashes_the_debris_and_walking_flashes_nothing() -> void:
	# an EXP barrel breaks on its second round: the first flashes it, the second leaves no flash on it (gone) and the
	# pieces start white
	var w := _world(0)
	var bf: BarrelField = w["bf"]
	var deb: BarrelDebris = w["deb"]
	_round(bf)
	assert_float(bf.flash_of(0)).is_equal(1.0)
	_round(bf)
	assert_int(bf.alive[0]).is_equal(0)
	assert_bool(bf._flash.has(0)).is_false()
	assert_int(deb.live_count()).is_greater(0)
	assert_float(deb.flash_of(0, 0)).is_equal(1.0)
	for k in range(12):
		deb._process(DT)
	assert_float(deb.flash_of(0, 0)).is_equal(0.0)
	# walking into a barrel: it breaks with no flash on it or on its pieces
	var w2 := _world(0)
	var bf2: BarrelField = w2["bf"]
	var deb2: BarrelDebris = w2["deb"]
	bf2._break(0)
	assert_bool(bf2._flash.is_empty()).is_true()
	assert_int(deb2.live_count()).is_greater(0)
	assert_float(deb2.flash_of(0, 0)).is_equal(0.0)


func test_only_the_barrels_shader_reads_a_flash() -> void:
	var barrel := BarrelField.barrel_shader().code
	assert_bool(barrel.contains("#define HIT_FLASH")).is_true()
	# the scenery's shader (PropField's) compiles without it: no flash, the sway in y as before
	var scenery: String = (load("res://core/shaders/prop_billboard.gdshader") as Shader).code
	assert_bool(scenery.contains("#define HIT_FLASH")).is_false()
	assert_bool(scenery.contains("#ifdef HIT_FLASH")).is_true()
	# a scenery prop has no flash to set: PropField has no flash API
	assert_bool((auto_free(PropField.new()) as Node).has_method("flash_hit")).is_false()


# ---------------------------------------------------------------- 2. the sun's flame patch

func test_the_sun_lays_a_small_patch_not_a_ring_and_it_is_gone_by_its_time() -> void:
	var w := _world()
	var tg: Telegraphs = w["tg"]
	StrikeMarks.sun(w["g"], Vector3(2, 0, 2), 1.3)
	var sm := StrikeMarks.of(w["g"])
	assert_object(sm).is_not_null()
	assert_int(sm.count("sun")).is_equal(1)
	var m: Dictionary = sm._marks[0]
	# one held blob (no glow ring), half the strike's radius
	assert_int(int(m["glow"])).is_equal(-1)
	assert_float(float(m["r"])).is_equal_approx(1.3 * StrikeMarks.SUN_PATCH, 0.001)
	var id := int(m["burn"])
	assert_bool(tg._held.has(id)).is_true()
	assert_int(sm.flames_laid).is_equal(StrikeMarks.SUN_FLAMES)
	# it dims fast: under half by 0.4 s, under 15% by 0.8 s
	var a0: float = float(tg._held[id]["a"])
	var t := 0.0
	var a04 := -1.0
	var a08 := -1.0
	while t < StrikeMarks.SUN_LIFE + 0.1:
		sm._process(0.05)
		t += 0.05
		if a04 < 0.0 and t >= 0.4 - 0.001:
			a04 = float(tg._held[id]["a"])
		if a08 < 0.0 and t >= 0.8 - 0.001:
			a08 = float(tg._held[id]["a"])
	assert_float(a0).is_equal(1.0)
	assert_float(a04).is_less(0.5)
	assert_float(a08).is_less(0.15)
	# the second lick of flames came, and the patch is gone
	assert_int(sm.flames_laid).is_equal(StrikeMarks.SUN_FLAMES + StrikeMarks.SUN_LICKS)
	assert_int(sm.count("sun")).is_equal(0)
	assert_bool(tg._held.has(id)).is_false()
	assert_float(StrikeMarks.SUN_LIFE).is_less_equal(1.5)


func test_a_zenith_sweep_is_capped() -> void:
	var w := _world()
	var tg: Telegraphs = w["tg"]
	# forty pillars land in one frame
	for k in range(40):
		StrikeMarks.sun(w["g"], Vector3(float(k % 8) * 1.5, 0, floorf(float(k) / 8.0) * 1.5), 1.0, true)
	var sm := StrikeMarks.of(w["g"])
	assert_int(sm.count("sun")).is_equal(StrikeMarks.CAP)
	assert_int(sm.flames_laid).is_less_equal(StrikeMarks.FLAME_FRAME_CAP)
	tg._advance(DT)
	assert_int(tg.live_count()).is_less_equal(StrikeMarks.CAP)
	# a sweep's patches take no second lick, and all are gone by SUN_LIFE
	var laid0 := sm.flames_laid
	for k in range(int(StrikeMarks.SUN_LIFE / 0.05) + 2):
		sm._process(0.05)
	assert_int(sm.flames_laid).is_equal(laid0)
	assert_int(sm.count()).is_equal(0)


func test_the_warning_ring_is_a_quarter_fainter() -> void:
	# pass 136's 0.35 and 0.4, a quarter less
	var sun: Dictionary = Registry.weapon("sun_scepter").params["sun"]
	assert_float(float(sun["ring_alpha"])).is_equal_approx(0.35 * 0.75, 0.005)
	# Zenith (an evolution: the Registry keeps it with the weapons)
	var zen: WeaponDef = Registry.weapon("zenith")
	assert_object(zen).is_not_null()
	assert_float(float(zen.params["sun"]["ring_alpha"])).is_equal_approx(0.4 * 0.75, 0.005)
