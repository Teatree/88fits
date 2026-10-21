extends GdUnitTestSuite

## Pass 95, lane ITEMS. The held gun fires from its muzzle as drawn (ProjectileEmitter.shot_origin: the Boomstick, the
## Blunderbuss, Both Barrels' twin barrels; the companions untouched; Garry: "Shot should happen from the shotgun 3d
## object"); the Frisbee's trail per look (`disc.trail` {style, length, width, alpha, colour}: streak, sparks, glow, one
## mesh for every disc, fading out through the glide; Garry: "needs a dim trail behind its flight ... Treat each visual
## update of Frisbee with its own trail effect"); the "Fire forward" debug switch (Settings.fire_forward,
## core/systems/FireForward.gd: the Sabre, Spear, Hammer, Frisbee, Tumbleweed and Basketball fire along the hero's
## facing while no creature stands within 75% of their range; the ball thrown forward drops to the sand when it finds
## nobody to bounce off).

const THRUSTER := preload("res://core/behaviors/Thruster.gd")
const SMASHER := preload("res://core/behaviors/Smasher.gd")
const FRIS := preload("res://core/behaviors/Frisbee.gd")

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var paused := false
var catches := 0
var last_catch := {}
var sands := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_at, _col, _size) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	sands += 1
func fx_poison(_a) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
func ball_caught(_w, ex) -> void:
	catches += 1
	last_catch = ex
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
var still := false
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return still
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	var dd := Vector3(d.x, 0, d.z)
	if dd.length_squared() < 0.0001:
		dd = forward()
	return global_position + Vector3(0, 0.8, 0) + dd.normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0
const FORWARD_IDS := ["sabre", "pike", "hammer", "frisbee", "tumbleweed", "basketball",
	"whirlwind", "thunder_lance", "earthshaker", "flying_saucer", "dust_devil", "slam_dunk"]

var _keep_ff := false


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_keep_ff = Settings.fire_forward
	Settings.fire_forward = false
	Run.heat = 0


func after_test() -> void:
	Settings.fire_forward = _keep_ff
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero (with a hip to his right, as Player.tscn has it), with the real crowd, shots and effects.
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	var hip := Node3D.new()
	hero.add_child(hip)
	hip.position = Vector3(0.55, 0.7, 0)
	hero.set("hip", hip)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	em.screen_filter_on = false
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	return _behaviour(w, ProjectileEmitter.new(), inst) as ProjectileEmitter


## The Frisbee has no class name: typed Node, as pass 69's tests have it, so its own members are reached dynamically.
func _frisbee(w: Dictionary, inst: WeaponInstance) -> Node:
	return _behaviour(w, FRIS.new(), inst)


## A tough, risen creature at `at`.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


func _first_alive(pm: ProjectileManager) -> int:
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1:
			return j
	return -1


func _alive_shots(pm: ProjectileManager) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1:
			out.append(j)
	return out


# ---------------------------------------------------------------- 1. the shot leaves the held gun's muzzle

func test_the_boomstick_fires_every_pellet_from_its_muzzle_as_drawn() -> void:
	var w := _world(Vector3(3, 0, -2))
	var hero: Node3D = w["hero"]
	var pm: ProjectileManager = w["pm"]
	var boom := _emitter(w, _inst("boomstick"))
	_creature(w["em"], hero.global_position + Vector3(0, 0, -4))
	assert_bool(boom._fire()).is_true()
	var dir := Vector3(0, 0, -1)
	var hip: Vector3 = (hero.get("hip") as Node3D).global_position
	# the held gun is posed at the hip, turned to the shot's line, squished by the recoil
	assert_vector(boom._held.global_position).is_equal_approx(hip, Vector3.ONE * 0.001)
	assert_float(boom._held.rotation.y).is_equal_approx(atan2(-dir.x, -dir.z), 0.001)
	assert_float(boom._held.scale.z).is_equal_approx(0.7, 0.001)
	# the muzzle in the gun's own space: the far end of the barrel, on the bore
	var tip: Vector3 = boom.held_tip()
	assert_float(absf(tip.x)).is_less(0.02)
	assert_float(tip.y).is_equal_approx(0.09, 0.03)
	assert_float(tip.z).is_equal_approx(-0.85, 0.03)
	var from: Vector3 = boom._held.global_transform * tip
	# every pellet starts there, not at his chest
	var shots := _alive_shots(pm)
	assert_int(shots.size()).is_equal(5)
	for j in shots:
		assert_vector(pm.pos[j]).is_equal_approx(from, Vector3.ONE * 0.001)
	assert_float(from.distance_to(hero.aim_origin(dir))).is_greater(0.2)
	# ahead of the hip along the shot by the squished barrel's length, at the barrel's height
	assert_float((from - hip).dot(dir)).is_equal_approx(0.85 * 0.7, 0.05)
	assert_float(from.y).is_equal_approx(hip.y + 0.09, 0.03)
	# the sparks, the flash and the smoke sit on the muzzle
	for nm: String in ["Muzzle", "Flash", "Smoke"]:
		var m: Node3D = boom.visual.get_node(nm)
		assert_vector(m.global_position).override_failure_message(nm).is_equal_approx(from, Vector3.ONE * 0.001)


func test_the_muzzle_moves_with_the_gun_its_squish_and_its_turn() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var boom := _emitter(w, _inst("boomstick"))
	var hip: Node3D = hero.get("hip")
	boom._aim_yaw = 0.0
	boom._held.scale = Vector3.ONE
	var a: Vector3 = boom.shot_origin(Vector3(0, 0, -1))
	assert_vector(a).is_equal_approx(hip.global_position + Vector3(0, 0.09, -0.85), Vector3.ONE * 0.03)
	# the hero walks: the gun goes with his hip
	hero.global_position += Vector3(2, 0, 1)
	var b: Vector3 = boom.shot_origin(Vector3(0, 0, -1))
	assert_vector(b - a).is_equal_approx(Vector3(2, 0, 1), Vector3.ONE * 0.001)
	# turned to fire along +x: the muzzle swings round the hip
	boom._aim_yaw = atan2(-1.0, 0.0)
	var c: Vector3 = boom.shot_origin(Vector3(1, 0, 0))
	assert_vector(c).is_equal_approx(hip.global_position + Vector3(0.85, 0.09, 0), Vector3.ONE * 0.03)
	# the recoil squish brings the tip back with the gun
	boom._held.scale = Vector3(1, 1, 0.7)
	var d: Vector3 = boom.shot_origin(Vector3(1, 0, 0))
	assert_vector(d).is_equal_approx(hip.global_position + Vector3(0.85 * 0.7, 0.09, 0), Vector3.ONE * 0.03)
	# a hidden gun: the chest, as before
	boom._held.visible = false
	assert_vector(boom.shot_origin(Vector3(1, 0, 0))).is_equal(hero.aim_origin(Vector3(1, 0, 0)))


func test_both_barrels_puts_the_muzzle_between_the_twin_barrels_and_the_second_barrel_fires_from_it() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var boom := _emitter(w, _inst("boomstick", ["both_barrels"]))
	assert_bool((boom.visual.find_child("BarrelL", true, false) as Node3D).visible).is_true()
	assert_bool((boom.visual.find_child("Barrel", true, false) as Node3D).visible).is_false()
	var tip: Vector3 = boom.held_tip()
	assert_float(absf(tip.x)).is_less(0.01)
	assert_float(tip.z).is_equal_approx(-0.85, 0.03)
	_creature(w["em"], Vector3(0, 0, -4))
	assert_bool(boom._fire()).is_true()
	pm.clear_all()
	# the second barrel (Both Barrels) goes from the muzzle too
	boom._second_barrel()
	assert_int(boom.second_barrels).is_equal(1)
	var from: Vector3 = boom._held.global_transform * boom.held_tip()
	var shots := _alive_shots(pm)
	assert_int(shots.size()).is_greater_equal(5)
	for j in shots:
		assert_vector(pm.pos[j]).is_equal_approx(from, Vector3.ONE * 0.001)


func test_the_blunderbuss_blasts_its_pellets_from_the_bell() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var pm: ProjectileManager = w["pm"]
	var bl := _emitter(w, _inst("blunderbuss"))
	var tip: Vector3 = bl.held_tip()
	assert_float(tip.z).is_less(-0.6)
	assert_float(absf(tip.x)).is_less(0.03)
	_creature(w["em"], Vector3(0, 0, -3))
	assert_bool(bl._fire()).is_true()
	assert_int(bl.blasts).is_equal(1)
	var from: Vector3 = bl._held.global_transform * bl.held_tip()
	var ghosts := 0
	for j in _alive_shots(pm):
		if pm.extra[j].has("ghost"):
			ghosts += 1
			assert_vector(pm.pos[j]).is_equal_approx(from, Vector3.ONE * 0.001)
	assert_int(ghosts).is_greater_equal(3)
	assert_float(from.distance_to(hero.aim_origin(Vector3(0, 0, -1)))).is_greater(0.2)


func test_the_companion_guns_still_fire_from_their_mouths() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var pm: ProjectileManager = w["pm"]
	_creature(w["em"], Vector3(0, 0, -5))
	for id in ["revolver", "tommy_gun"]:
		pm.clear_all()
		var gun := _emitter(w, _inst(id))
		assert_object(gun._familiar).override_failure_message(id).is_not_null()
		assert_bool(gun._fire()).override_failure_message(id).is_true()
		var first := _first_alive(pm)
		assert_int(first).override_failure_message(id).is_greater_equal(0)
		var punchy: bool = gun._fam_base_set and not gun._fam_dict("kick").is_empty()
		var mouth: Vector3 = gun._fam_base if punchy else gun._familiar.global_position
		assert_float(pm.pos[first].distance_to(mouth)).override_failure_message(id).is_equal_approx(0.45, 0.02)
		assert_float(pm.pos[first].distance_to(hero.global_position + Vector3(0, 0.8, 0))).override_failure_message(id).is_greater(0.6)


# ---------------------------------------------------------------- 2. the Frisbee's trail

func test_each_look_carries_its_own_trail_block() -> void:
	var fr: Dictionary = Registry.weapon("frisbee").params["disc"]["trail"]
	assert_str(str(fr["style"])).is_equal("streak")
	var pr: Dictionary = Registry.mutation("poison_razors").params["disc"]["trail"]
	assert_str(str(pr["style"])).is_equal("sparks")
	var fs: Dictionary = Registry.weapon("flying_saucer").params["disc"]["trail"]
	assert_str(str(fs["style"])).is_equal("glow")
	for b: Dictionary in [fr, pr, fs]:
		for k in ["length", "width", "alpha"]:
			assert_bool(b.has(k)).override_failure_message(k).is_true()
	# folded: Poison Razors' sparks over the plain disc; Carry keeps the streak at its bigger size; the saucer's final
	# block keeps its glow
	assert_str(str(_inst("frisbee", ["poison_razors"]).params["disc"]["trail"]["style"])).is_equal("sparks")
	var carry := _inst("frisbee", ["carry"])
	assert_str(str(carry.params["disc"]["trail"]["style"])).is_equal("streak")
	assert_float(float(carry.params["disc"]["size_mult"])).is_equal_approx(1.5, 0.001)
	var saucer := _inst("flying_saucer")
	assert_str(str(saucer.params["disc"]["trail"]["style"])).is_equal("glow")
	assert_str(str(saucer.params["disc"]["look"])).is_equal("saucer")


func test_trail_params_reads_the_block_its_defaults_and_none() -> void:
	var w := _world()
	var b := _frisbee(w, _inst("frisbee"))
	var t: Dictionary = b.trail_params()
	assert_str(str(t["style"])).is_equal("streak")
	assert_float(float(t["length"])).is_equal_approx(0.4, 0.0001)
	assert_float(float(t["width"])).is_equal_approx(1.5, 0.0001)
	assert_float(float(t["alpha"])).is_equal_approx(0.6, 0.0001)
	var want := Color.html("#7CFF00").lerp(Color.WHITE, 0.45)
	assert_float((t["colour"] as Color).r).is_equal_approx(want.r, 0.001)
	assert_float((t["colour"] as Color).g).is_equal_approx(want.g, 0.001)
	# the razors spark, the saucer glows
	var trz: Dictionary = _frisbee(w, _inst("frisbee", ["poison_razors"])).trail_params()
	assert_str(str(trz["style"])).is_equal("sparks")
	assert_float(float(trz["alpha"])).is_equal_approx(0.9, 0.0001)
	var ts: Dictionary = _frisbee(w, _inst("flying_saucer")).trail_params()
	assert_str(str(ts["style"])).is_equal("glow")
	assert_float(float(ts["width"])).is_equal_approx(2.2, 0.0001)
	# the block's own words win; what it leaves out is the style's; an empty block or `true` is the look's own style;
	# none or false is no trail; a style nobody knows reads as the streak
	var disc: Dictionary = b.inst.params["disc"]
	disc["trail"] = {"style": "glow", "length": 1.0, "colour": "#FF0000"}
	t = b.trail_params()
	assert_str(str(t["style"])).is_equal("glow")
	assert_float(float(t["length"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(t["width"])).is_equal_approx(2.2, 0.0001)
	assert_float((t["colour"] as Color).r).is_equal_approx(1.0, 0.001)
	assert_float((t["colour"] as Color).g).is_equal_approx(0.0, 0.001)
	disc["trail"] = {}
	assert_str(str(b.trail_params()["style"])).is_equal("streak")
	disc["trail"] = true
	assert_str(str(b.trail_params()["style"])).is_equal("streak")
	disc["trail"] = {"style": "none"}
	assert_bool(b.trail_params().is_empty()).is_true()
	disc["trail"] = false
	assert_bool(b.trail_params().is_empty()).is_true()
	disc["trail"] = {"style": "what"}
	assert_str(str(b.trail_params()["style"])).is_equal("streak")
	disc.erase("trail")
	assert_str(str(b.trail_params()["style"])).is_equal("streak")
	# the razors' look without a block takes the sparks, the saucer's the glow
	disc["look"] = "razors"
	assert_str(str(b.trail_params()["style"])).is_equal("sparks")
	disc["look"] = "saucer"
	assert_str(str(b.trail_params()["style"])).is_equal("glow")


func test_every_disc_draws_into_one_mesh_and_the_ribbon_fades_through_the_glide() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for style in ["streak", "sparks", "glow"]:
		var b := _frisbee(w, _inst("frisbee"))
		b.inst.params["disc"]["trail"] = {"style": style}
		for k in range(3):
			b._launch(Vector3(1, 0, 0).rotated(Vector3.UP, 0.3 * float(k)), 8.0, 3, 1.0)
		for k in range(12):
			em._rebuild_grid()
			b._tick(DT)
		assert_str(str(b.trail_params()["style"])).is_equal(style)
		assert_int((b._trail_mesh as ImmediateMesh).get_surface_count()).override_failure_message(style).is_equal(1)
		assert_int(b.trail_vertex_count()).override_failure_message(style).is_greater(0)
		assert_int((b.discs as Array).size()).is_equal(3)
	# no trail: nothing drawn
	var none := _frisbee(w, _inst("frisbee"))
	none.inst.params["disc"]["trail"] = false
	none._launch(Vector3(1, 0, 0), 8.0, 1, 1.0)
	for k in range(12):
		none._tick(DT)
	assert_int(none.trail_vertex_count()).is_equal(0)
	# the glide: the whole range flown, the ribbon still shows behind the sinking disc and then ages out
	var g := _frisbee(w, _inst("frisbee"))
	var d: Dictionary = g._launch(Vector3(0, 0, -1), 8.0, 1, 1.0)
	var steps := 0
	while int(d["phase"]) == 0 and steps < 600:
		g._tick(DT)
		steps += 1
	assert_int(int(d["phase"])).is_equal(1)
	assert_int(g.trail_vertex_count()).is_greater(0)
	for k in range(40):
		g._tick(DT)
	assert_int(g.trail_vertex_count()).is_equal(0)


# ---------------------------------------------------------------- 3. "Fire forward"

func test_the_switch_is_off_by_default_saved_and_locked_off_in_prod() -> void:
	var fresh = load("res://core/autoload/Settings.gd").new()
	assert_bool(bool(fresh.fire_forward)).is_false()
	fresh.free()
	assert_bool(Settings.PROD_LOCKED.has("fire_forward")).is_true()
	assert_bool(bool(Settings.PROD_LOCKED["fire_forward"])).is_false()
	Settings.fire_forward = true
	var d: Dictionary = Settings.to_dict()
	assert_bool(bool(d["fire_forward"])).is_true()
	Settings.fire_forward = false
	Settings.from_dict(d)
	assert_bool(Settings.fire_forward).is_true()
	# an older save without the key keeps today's value
	var old := d.duplicate()
	old.erase("fire_forward")
	Settings.fire_forward = false
	Settings.from_dict(old)
	assert_bool(Settings.fire_forward).is_false()
	# the production build holds it off
	Settings.fire_forward = true
	Settings.force_prod(true)
	assert_bool(Settings.fire_forward).is_false()
	Settings.set_value("fire_forward", true)
	assert_bool(Settings.fire_forward).is_false()
	Settings.force_prod(false)
	assert_bool(Settings.is_prod()).is_false()


func test_fire_forward_dir_follows_the_75_percent_rule() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var em: EnemyManager = w["em"]
	hero.set("facing", PI * 0.5)  # he faces -x
	var sabre := _inst("sabre")
	var revolver := _inst("revolver")
	Settings.fire_forward = false
	assert_vector(FireForward.dir(sabre, hero, em, 2.6)).is_equal(Vector3.ZERO)
	Settings.fire_forward = true
	assert_bool(FireForward.on()).is_true()
	assert_bool(FireForward.covers(sabre)).is_true()
	assert_bool(FireForward.covers(revolver)).is_false()
	assert_vector(FireForward.dir(revolver, hero, em, 9.0)).is_equal(Vector3.ZERO)
	assert_vector(FireForward.dir(sabre, hero, em, 2.6)).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
	assert_float(sabre.stat("range", 2.6)).is_equal_approx(2.6, 0.001)
	assert_float(FireForward.near_range(sabre, 2.6)).is_equal_approx(2.6 * 0.75, 0.0001)
	# a creature within 75% of the range (1.95 m) puts the blade back on its aim, wherever it stands
	var near := _creature(em, hero.global_position + Vector3(0, 0, 1.5))
	assert_vector(FireForward.dir(sabre, hero, em, 2.6)).is_equal(Vector3.ZERO)
	# one dying there does not count
	em.state[near] = EnemyManager.STATE_DYING
	assert_vector(FireForward.dir(sabre, hero, em, 2.6)).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
	em.alive[near] = 0
	em._rebuild_grid()
	# one past 75% but within the range: still forward
	_creature(em, hero.global_position + Vector3(2.2, 0, 0))
	assert_vector(FireForward.dir(sabre, hero, em, 2.6)).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
	# what 75% means for the others: the Hammer 3.45 m, the Frisbee 9, the Tumbleweed 12, the ball 6.75
	assert_float(FireForward.near_range(_inst("hammer"), 4.6)).is_equal_approx(3.45, 0.001)
	assert_float(FireForward.near_range(_inst("frisbee"), 12.0)).is_equal_approx(9.0, 0.001)
	assert_float(FireForward.near_range(_inst("tumbleweed"), 16.0)).is_equal_approx(12.0, 0.001)
	assert_float(FireForward.near_range(_inst("basketball"), 9.0)).is_equal_approx(6.75, 0.001)
	assert_float(FireForward.near_range(_inst("pike"), 4.6)).is_equal_approx(3.45, 0.001)


func test_the_content_marks_the_six_weapons_and_their_evolutions() -> void:
	for id: String in FORWARD_IDS:
		assert_bool(bool(Registry.weapon(id).params.get("fire_forward", false))).override_failure_message(id).is_true()
	for id: String in ["revolver", "boomstick", "tommy_gun", "lob_grenade", "sun_scepter", "gravity_gun"]:
		assert_bool(Registry.weapon(id).params.has("fire_forward")).override_failure_message(id).is_false()


func test_the_sabre_and_the_spear_strike_forward_with_nobody_near_and_aim_again_with_one() -> void:
	Settings.fire_forward = true
	for id: String in ["sabre", "pike"]:
		var w := _world()
		var hero: Node3D = w["hero"]
		hero.set("facing", PI * 0.5)
		var b: Thruster = _behaviour(w, THRUSTER.new(), _inst(id)) as Thruster
		assert_bool(b._fire()).override_failure_message(id).is_true()
		assert_vector(b._dir).override_failure_message(id).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
		assert_int(b.target).is_equal(-1)
		assert_int(b.strokes).is_equal(1)
		# a creature within 75% of the range: the usual aim, at it
		var w2 := _world()
		var hero2: Node3D = w2["hero"]
		hero2.set("facing", PI * 0.5)
		var c := _creature(w2["em"], Vector3(0, 0, 1.4))
		var b2: Thruster = _behaviour(w2, THRUSTER.new(), _inst(id)) as Thruster
		assert_bool(b2._fire()).override_failure_message(id).is_true()
		assert_int(b2.target).is_equal(c)
		assert_vector(b2._dir).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.01)
	# the switch off, nobody near: no stroke, as before
	Settings.fire_forward = false
	var w3 := _world()
	var b3: Thruster = _behaviour(w3, THRUSTER.new(), _inst("sabre")) as Thruster
	assert_bool(b3._fire()).is_false()
	assert_int(b3.strokes).is_equal(0)


func test_the_hammer_lands_three_quarters_of_its_reach_ahead_with_nobody_near() -> void:
	Settings.fire_forward = true
	var w := _world()
	var hero: Node3D = w["hero"]
	hero.set("facing", PI * 0.5)
	var b: Smasher = _behaviour(w, SMASHER.new(), _inst("hammer")) as Smasher
	assert_bool(b._fire()).is_true()
	assert_int(b._swings.size()).is_equal(1)
	var sw: Dictionary = b._swings[0]
	var want: Vector3 = hero.global_position + Vector3(-1, 0, 0) * 4.6 * 0.75
	assert_vector(sw["at"]).is_equal_approx(want, Vector3.ONE * 0.01)
	assert_float(float(sw["yaw"])).is_equal_approx(atan2(1.0, 0.0), 0.001)
	# a creature within 3.45 m: the blow goes to the crowd, as before
	var w2 := _world()
	var em2: EnemyManager = w2["em"]
	var c := _creature(em2, Vector3(0, 0, 2.5))
	var b2: Smasher = _behaviour(w2, SMASHER.new(), _inst("hammer")) as Smasher
	assert_bool(b2._fire()).is_true()
	var at: Vector3 = (b2._swings[0] as Dictionary)["at"]
	assert_float(Vector2(at.x, at.z).distance_to(Vector2(em2.pos[c].x, em2.pos[c].z))).is_less(0.01)
	# the switch off, nobody near: no swing
	Settings.fire_forward = false
	var w3 := _world()
	var b3: Smasher = _behaviour(w3, SMASHER.new(), _inst("hammer")) as Smasher
	assert_bool(b3._fire()).is_false()


func test_the_frisbee_flies_forward_with_nobody_near_and_at_a_creature_near() -> void:
	Settings.fire_forward = true
	var w := _world()
	var hero: Node3D = w["hero"]
	hero.set("facing", PI * 0.5)
	var b := _frisbee(w, _inst("frisbee"))
	assert_bool(b._fire()).is_true()
	var d: Dictionary = (b.discs as Array)[0]
	assert_vector(d["dir0"]).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
	# a creature 5 m off to the side (within 9 m): aimed at it
	var w2 := _world()
	var em2: EnemyManager = w2["em"]
	_creature(em2, Vector3(0, 0, 5))
	var b2 := _frisbee(w2, _inst("frisbee"))
	assert_bool(b2._fire()).is_true()
	assert_vector(((b2.discs as Array)[0] as Dictionary)["dir0"]).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.01)
	# one 10 m away (past 9): forward, not at it
	var w3 := _world()
	var hero3: Node3D = w3["hero"]
	hero3.set("facing", PI * 0.5)
	_creature(w3["em"], Vector3(0, 0, 10))
	var b3 := _frisbee(w3, _inst("frisbee"))
	assert_bool(b3._fire()).is_true()
	assert_vector(((b3.discs as Array)[0] as Dictionary)["dir0"]).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)


func test_the_tumbleweed_rolls_forward_with_nobody_near() -> void:
	Settings.fire_forward = true
	var w := _world()
	var hero: Node3D = w["hero"]
	var pm: ProjectileManager = w["pm"]
	hero.set("facing", PI * 0.5)
	var t := _emitter(w, _inst("tumbleweed"))
	assert_bool(t._fire()).is_true()
	var j := _first_alive(pm)
	assert_int(j).is_greater_equal(0)
	assert_vector(pm.vel[j].normalized()).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
	assert_bool(pm.extra[j].has("drop_alone")).is_false()
	# the switch off, nobody in range: no shot (it aims at creatures)
	Settings.fire_forward = false
	pm.clear_all()
	assert_bool(t._fire()).is_false()
	# a creature within 12 m (75% of 16): the usual aim, at it
	_creature(w["em"], Vector3(0, 0, 6))
	Settings.fire_forward = true
	assert_bool(t._fire()).is_true()
	j = _first_alive(pm)
	assert_vector(pm.vel[j].normalized()).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.01)


func test_the_basketball_thrown_forward_drops_to_the_sand_when_it_finds_nobody() -> void:
	Settings.fire_forward = true
	var w := _world()
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var pm: ProjectileManager = w["pm"]
	hero.set("facing", PI * 0.5)
	var ball := _emitter(w, _inst("basketball"))
	assert_bool(ball._fire()).is_true()
	assert_int(ball.throws).is_equal(1)
	var j := _first_alive(pm)
	assert_int(j).is_greater_equal(0)
	assert_bool(pm.extra[j].has("drop_alone")).is_true()
	assert_vector(pm.vel[j].normalized()).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)
	var returned := false
	var dropped := false
	var steps := 0
	while pm.alive[j] == 1 and steps < 400:
		pm._physics_process(DT)
		if pm.ret[j] == 2:
			returned = true
		if pm.extra[j].has("drop_t"):
			dropped = true
		steps += 1
	assert_int(pm.alive[j]).is_equal(0)
	assert_bool(returned).is_false()
	assert_bool(dropped).is_true()
	assert_int(pm.drops).is_equal(1)
	assert_int(int(g.get("catches"))).is_equal(0)
	assert_int(int(g.get("sands"))).is_equal(1)
	assert_int(Run.heat).is_equal(0)
	# it fell soon after its range's end (9 m at 16 m/s), never a 6 s return
	assert_int(steps).is_less(120)


func test_the_basketball_thrown_forward_hops_to_a_creature_within_its_reach_and_comes_home() -> void:
	Settings.fire_forward = true
	var w := _world()
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	hero.set("facing", PI * 0.5)
	# a creature past the range's end (9 m) but within the bounce reach (7 m) of it, and well past 75% of the range
	_creature(em, Vector3(-12.5, 0, 0))
	var ball := _emitter(w, _inst("basketball"))
	assert_bool(ball._fire()).is_true()
	var j := _first_alive(pm)
	assert_bool(pm.extra[j].has("drop_alone")).is_true()
	var steps := 0
	while pm.alive[j] == 1 and steps < 900:
		em._rebuild_grid()
		pm._physics_process(DT)
		steps += 1
	assert_int(pm.ricochets_any).is_greater_equal(1)
	assert_int(pm.drops).is_equal(0)
	assert_int(int(g.get("catches"))).is_equal(1)
	assert_int(int((g.get("last_catch") as Dictionary).get("hits", 0))).is_greater_equal(1)


func test_a_normal_throw_still_comes_home_and_a_creature_near_keeps_the_usual_aim() -> void:
	Settings.fire_forward = false
	var w := _world()
	var g: Node = w["g"]
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var ball := _emitter(w, _inst("basketball"))
	# nobody in range, the switch off: no throw
	assert_bool(ball._fire()).is_false()
	# a creature in range: thrown at it, no drop mark, caught on its way back
	_creature(em, Vector3(0, 0, -5))
	assert_bool(ball._fire()).is_true()
	var j := _first_alive(pm)
	assert_bool(pm.extra[j].has("drop_alone")).is_false()
	var steps := 0
	while pm.alive[j] == 1 and steps < 900:
		em._rebuild_grid()
		pm._physics_process(DT)
		steps += 1
	assert_int(int(g.get("catches"))).is_equal(1)
	assert_int(pm.drops).is_equal(0)
	# the switch on with a creature within 75% of the range (6.75 m): the same usual throw
	Settings.fire_forward = true
	pm.clear_all()
	assert_bool(ball._fire()).is_true()
	j = _first_alive(pm)
	assert_bool(pm.extra[j].has("drop_alone")).is_false()
	assert_vector(pm.vel[j].normalized()).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.01)
