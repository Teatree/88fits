extends GdUnitTestSuite

## Pass 76, lane MOLO (Garry: "Regenerate the Molotov Visuals, the flame looks weird. Make several different versions").
## A fire bottle with `params.wick_flame` burns at its wick (WickFlames): the flame stands on the wick's tip as the shot
## draws it, upright while the bottle tumbles end over end; one MultiMesh draws every flame in the air. The Molotov
## family wears looks A (today's: the placeholder bottle, the old string of tongues), B (torch), C (streamer: the bottle
## base first), D (cartoon), each with the new bottle (Methanol's blue one, the Moonshine's jug); a look's
## `params.pool_flame` burns the pool in its style. A bottle without wick_flame flies as before.

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
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_at, _col, _size) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
func oil_drip(_at, _w, _dp) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
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
const FAMILY := "molotov"
const BOTTLE := "res://content/weapons/molotov/molotov_visual_bottle.tscn"
const BOTTLE_TRAIL := "res://content/weapons/molotov/molotov_visual_bottle_trail.tscn"
const BLUE_BOTTLE := "res://content/mutations/methanol/methanol_visual_bottle.tscn"
const JUG := "res://content/evolutions/moonshine/moonshine_visual_jug.tscn"
const OLD_BOTTLE := "res://content/weapons/molotov/molotov_visual.tscn"
const OLD_METHANOL := "res://content/mutations/methanol/methanol_visual.tscn"
const OLD_JUG := "res://content/evolutions/moonshine/moonshine_visual.tscn"

var _looks_were: Dictionary = {}


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	_play("")
	Run.debug_clear_items()
	Run.end()


## The family wears `code` ("" = the JSON's `variant` again), as the arena's chips do.
func _play(code: String) -> void:
	var il = Save.data.get("item_looks", {})
	if not (il is Dictionary):
		il = {}
	if code == "":
		(il as Dictionary).erase(FAMILY)
	else:
		il[FAMILY] = code
	Save.data["item_looks"] = il
	Registry.apply_item_looks()


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		inst.mutations.append(Registry.mutation(m))
	inst.rebuild(Run.player_sheet, [inst])
	return inst


## A Lobber of `id` (and its mutations) set up in the world, so its visual's kind is registered as in a run.
func _lobber(w: Dictionary, id: String, muts: Array = []) -> Lobber:
	var lb := Lobber.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(_inst(id, muts, 3 if id == "molotov" else 1), w["g"])
	return lb


func _throw(w: Dictionary, lb: Lobber, target := Vector3(8, 0, 0)) -> int:
	var pm: ProjectileManager = w["pm"]
	return pm.lob(lb.shot_kind(), Vector3(0, 1.2, 0), target, 10.0, 8.0, 2.0, lb.inst, 2.0, lb.inst.params.duplicate())


## One physics tick and the draw after it, as a frame does.
func _frame(pm: ProjectileManager) -> void:
	pm._physics_process(DT)
	pm._process(DT)


# ---------------------------------------------------------------- the looks

func test_the_family_has_looks_a_to_d_and_plays_its_variant() -> void:
	assert_array(Registry.item_look_codes(FAMILY)).contains_exactly(["A", "B", "C", "D"])
	var wd: WeaponDef = Registry.weapon(FAMILY)
	assert_str(wd.variant_base).is_equal("A")
	assert_array(["A", "B", "C", "D"]).contains([Registry.played_item_look(FAMILY)])


func test_the_looks_switch_the_model_and_the_flame() -> void:
	var want := {
		"A": [OLD_BOTTLE, OLD_METHANOL, OLD_JUG, ""],
		"B": [BOTTLE, BLUE_BOTTLE, JUG, "torch"],
		"C": [BOTTLE_TRAIL, "res://content/mutations/methanol/methanol_visual_bottle_trail.tscn",
			"res://content/evolutions/moonshine/moonshine_visual_jug_trail.tscn", "streamer"],
		"D": [BOTTLE, BLUE_BOTTLE, JUG, "cartoon"],
	}
	for code: String in want.keys():
		_play(code)
		var row: Array = want[code]
		var wd: WeaponDef = Registry.weapon("molotov")
		var md: MutationDef = Registry.mutation("methanol")
		var ev: WeaponDef = Registry.weapon("moonshine")
		assert_str(wd.visual.resource_path).override_failure_message(code + " molotov").is_equal(str(row[0]))
		assert_str(md.visual.resource_path).override_failure_message(code + " methanol").is_equal(str(row[1]))
		assert_str(ev.visual.resource_path).override_failure_message(code + " moonshine").is_equal(str(row[2]))
		var style := str(row[3])
		for d in [wd.params, ev.params]:
			if style == "":
				assert_bool((d as Dictionary).has("wick_flame")).override_failure_message(code).is_false()
				assert_bool((d as Dictionary).has("pool_flame")).override_failure_message(code).is_false()
			else:
				assert_str(str(((d as Dictionary)["wick_flame"] as Dictionary)["style"])).is_equal(style)
				assert_bool((d as Dictionary).get("pool_flame") is Dictionary).is_true()
		# the rules never change with the look
		assert_float(float(wd.base.get("fire_damage", 0.0))).is_equal(4.0)
		assert_float(float(ev.params["final"]["cloud_seconds"])).is_equal(9.0)


func test_the_moonshine_keeps_its_jug_and_its_own_wick_over_methanols_bottle() -> void:
	_play("B")
	var inst := _inst("moonshine", ["methanol", "accelerant", "oil_slick"])
	assert_object(inst.visual_scene()).is_same(load(JUG))
	var o: Array = (inst.params["wick_flame"] as Dictionary)["offset"]
	assert_float(float(o[1])).is_less(0.22)
	assert_bool(inst.blue_fire()).is_true()
	# the molotov with methanol: the blue bottle, the weapon's own wick
	var m := _inst("molotov", ["methanol"])
	assert_object(m.visual_scene()).is_same(load(BLUE_BOTTLE))
	assert_str(str((m.params["wick_flame"] as Dictionary)["style"])).is_equal("torch")


# ---------------------------------------------------------------- the flame on the wick

func test_the_wick_flame_follows_the_wick_upright_while_the_bottle_tumbles() -> void:
	_play("B")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := _lobber(w, "molotov")
	var cfg: Dictionary = lb.inst.params["wick_flame"]
	var off := WickFlames.offset_of(cfg)
	var j := _throw(w, lb)
	assert_int(j).is_greater_equal(0)
	var min_dot := 1.0
	var max_dot := -1.0
	var n := 0
	while pm.alive[j] == 1 and n < 300:
		_frame(pm)
		n += 1
		if pm.alive[j] == 0:
			break
		var fl: WickFlames = pm._wick
		assert_object(fl).is_not_null()
		assert_bool(fl.wicks.has(j)).is_true()
		# the flame stands where the wick is drawn: the offset turned and scaled with the bottle
		var expect: Vector3 = pm.pos[j] + pm.draw_basis(j) * off
		assert_float((fl.wicks[j] as Vector3).distance_to(expect)).is_less(0.001)
		assert_float((fl.wicks[j] as Vector3).distance_to(pm.wick_world(j))).is_less(0.001)
		# the bottle turns (its long axis swings round) while its flame stays upright
		var bottle_up: Vector3 = pm.draw_basis(j).y.normalized()
		min_dot = minf(min_dot, bottle_up.dot(Vector3.UP))
		max_dot = maxf(max_dot, bottle_up.dot(Vector3.UP))
		assert_float((fl.axes[j] as Vector3).dot(Vector3.UP)).is_greater(0.7)
	assert_int(n).is_greater(10)
	assert_float(max_dot - min_dot).is_greater(1.0)
	# it leaves the hand neck up
	assert_float(max_dot).is_greater(0.9)


func test_the_wick_sits_on_the_bottles_rag() -> void:
	_play("B")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := _lobber(w, "molotov")
	var mesh: Mesh = (pm.kinds[lb.projectile_kind]["mm"] as MultiMesh).mesh
	var top: float = mesh.get_aabb().end.y
	var off := WickFlames.offset_of(lb.inst.params["wick_flame"])
	# on the axis, just under the top of the rag
	assert_float(off.x).is_equal(0.0)
	assert_float(off.z).is_equal(0.0)
	assert_float(off.y).is_less_equal(top)
	assert_float(off.y).is_greater(top - 0.06)


func test_a_tumbling_bottle_turns_end_over_end_at_its_rate() -> void:
	_play("B")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := _lobber(w, "molotov")
	var j := _throw(w, lb)
	_frame(pm)
	assert_float(pm.spin[j]).is_equal_approx(0.0, 0.0001)
	assert_bool((pm.extra[j] as Dictionary).has("roll")).is_true()
	var s0: float = pm.spin[j]
	for k in range(20):
		_frame(pm)
	var rate := float((lb.inst.params["wick_flame"] as Dictionary)["tumble"]) * TAU
	assert_float((pm.spin[j] - s0) / (20.0 * DT)).is_equal_approx(rate, rate * 0.05)


func test_a_bottle_without_wick_flame_burns_as_before() -> void:
	_play("A")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var fx: Fx = w["fx"]
	var lb := _lobber(w, "molotov")
	assert_bool(lb.inst.params.has("wick_flame")).is_false()
	var j := _throw(w, lb)
	for k in range(12):
		_frame(pm)
	# no wick flames at all; the old tongues in Fx's flame pool, and the old spin about the flight line
	assert_object(pm._wick).is_null()
	assert_bool((pm.extra[j] as Dictionary).has("roll")).is_false()
	var flames := 0
	for i in range(fx._n):
		if fx._shard[i] == 2:
			flames += 1
	assert_int(flames).is_greater(0)


func test_methanol_and_the_moonshine_burn_blue_on_the_wick() -> void:
	_play("D")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	for row: Array in [["molotov", []], ["molotov", ["methanol"]], ["moonshine", []]]:
		var lb := _lobber(w, str(row[0]), row[1])
		var j := _throw(w, lb)
		_frame(pm)
		var st: Dictionary = pm._wick._shots[j]
		assert_bool(bool(st["blue"])).is_equal(lb.inst.blue_fire())
		assert_int(int(st["style"])).is_equal(WickFlames.STYLE_CARTOON)
		pm.clear_all()
		lb.queue_free()


func test_the_streamer_draws_a_tail_of_pieces_behind_the_wick() -> void:
	_play("C")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := _lobber(w, "molotov")
	# the streamer's bottle flies base first: its kind turned a quarter, no tumble
	assert_bool(bool(pm.kinds[lb.projectile_kind].get("turned", false))).is_true()
	var j := _throw(w, lb)
	for k in range(12):
		_frame(pm)
	var fl: WickFlames = pm._wick
	assert_int(fl.flames_drawn).is_equal(1)
	assert_int(fl.pieces_drawn).is_greater(3)
	assert_bool((pm.extra[j] as Dictionary).has("roll")).is_false()
	# the wick is behind the bottle, along its flight
	var back: Vector3 = (fl.wicks[j] as Vector3) - pm.pos[j]
	assert_float(back.dot(pm.vel[j].normalized())).is_less(-0.1)


func test_many_bottles_cost_one_draw_call() -> void:
	_play("B")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := _lobber(w, "molotov")
	for k in range(30):
		_throw(w, lb, Vector3(6 + float(k % 6), 0, float(k / 6) * 2.0))
	_frame(pm)
	_frame(pm)
	var fl: WickFlames = pm._wick
	assert_int(fl.flames_drawn).is_equal(30)
	assert_int(fl.find_children("*", "MultiMeshInstance3D", true, false).size()).is_equal(1)


# ---------------------------------------------------------------- the pool

func _pool(w: Dictionary, inst: WeaponInstance) -> ElementCloud:
	var c := ElementCloud.new()
	c.blue = inst.blue_fire()
	c.setup(w["g"], inst, 2.0, 3.0, 4.0, 1, 1.8, "fire", 0.5)
	(w["g"] as Node).add_child(c)
	return c


func test_a_looks_pool_burns_in_its_style_and_todays_in_fx_tongues() -> void:
	_play("B")
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var fx: Fx = w["fx"]
	var b := _pool(w, _inst("molotov"))
	b._process(0.5)
	b._process(0.5)
	assert_object(pm._wick).is_not_null()
	assert_int(pm._wick.ground_flames).is_greater_equal(2)
	var fx_flames := 0
	for i in range(fx._n):
		if fx._shard[i] == 2:
			fx_flames += 1
	assert_int(fx_flames).is_equal(0)
	b.queue_free()
	_play("A")
	var w2 := _world()
	var a := _pool(w2, _inst("molotov"))
	a._process(0.5)
	var fx2: Fx = w2["fx"]
	var n2 := 0
	for i in range(fx2._n):
		if fx2._shard[i] == 2:
			n2 += 1
	assert_int(n2).is_greater_equal(2)
	assert_object((w2["pm"] as ProjectileManager)._wick).is_null()
	a.queue_free()


func test_pool_flames_age_away_and_thin_when_many_burn() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var fl := pm.wick_flames()
	assert_bool(fl.ground_flame(Vector3.ZERO, 1.0, 0.5, "torch", false, true)).is_true()
	assert_int(fl.ground_count()).is_equal(1)
	fl.draw(pm, 0.3)
	assert_int(fl.ground_count()).is_equal(1)
	fl.draw(pm, 0.3)
	assert_int(fl.ground_count()).is_equal(0)
	var stood := 0
	for k in range(WickFlames.GROUND_MAX * 2):
		if fl.ground_flame(Vector3(float(k % 10), 0, 0), 1.0, 5.0, "cartoon", true):
			stood += 1
	assert_int(fl.ground_count()).is_less_equal(WickFlames.GROUND_MAX)
	assert_int(stood).is_less(WickFlames.GROUND_MAX * 2)


# ---------------------------------------------------------------- the warm-up

func test_the_warm_up_draws_every_style_once_and_lets_go() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	assert_object(pm._wick).is_null()
	pm.warm_wick_flames(Vector3(0, -8, 0))
	var fl: WickFlames = pm._wick
	assert_object(fl).is_not_null()
	assert_int(fl._mm.visible_instance_count).is_equal(6)
	pm.warm_wick_flames(Vector3.INF)
	assert_int(fl._mm.visible_instance_count).is_equal(0)
	var mat := (fl.find_children("*", "MultiMeshInstance3D", true, false)[0] as MultiMeshInstance3D).material_override as ShaderMaterial
	assert_str(mat.shader.resource_path).is_equal("res://core/shaders/wick_flame.gdshader")
