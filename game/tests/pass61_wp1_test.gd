extends GdUnitTestSuite

## Pass 61, lane WP1 (Garry: "Mutation Visual, implement every Cheap version"): the cheap looks of seven mutations, each
## switched on by the mutation's own params and off without it, and kept by the evolution that keeps the mutation:
## Dragon's Breath (orange pellets in a red glow, a flame tongue at the muzzle, the barrel glowing red after a shot),
## Both Barrels (a second barrel, brass beads counting to the double), Toxic Peas (sickly green peas, in the pod too, and
## a green trail), Fan the Hammer (a glove flicks under the pod on the double volley), Drum Mag (a bigger drum turning
## faster, denser tracer beads), Sticky (a glossy amber grenade and a light blinking faster on what it rides) and Thorny
## Weed (thorns on the weed and thorn specks on the sand, pooled and capped).

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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return true
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
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


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()
	# pass 76 (lane DYNART): a test that wore the grenade look puts its family back in the look it plays
	for d in Registry.item_family("lob_grenade"):
		d.look_worn = "?"
	Registry.apply_item_looks()


## Pass 76 (lane DYNART): the grenade family wears the grenade (look A) whatever look it plays, so the Sticky tests keep
## testing the grenade's glossy amber and its blinking light (the dynamite looks leave the stick its own paper and its
## spark: pass76_dynart_test).
func _wear_grenade() -> void:
	for d in Registry.item_family("lob_grenade"):
		d.wear_look("A")


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero, with the real crowd, shots, effects and ground marks.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	var b := ProjectileEmitter.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## The build change Game._sync_weapons makes: the instance folded again with these mutations, then refresh_marks.
func _rebuild_with(b: WeaponBehavior, muts: Array) -> void:
	b.inst.mutations.clear()
	for m: String in muts:
		b.inst.mutations.append(Registry.mutation(m))
	b.inst.rebuild(Run.player_sheet, [b.inst])
	b.refresh_marks()


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	return i


static func _near(a: Color, b: Color, eps := 0.02) -> bool:
	return absf(a.r - b.r) < eps and absf(a.g - b.g) < eps and absf(a.b - b.b) < eps


## The material kind `k` draws surface `s` with (its override when it has one).
static func _kind_mat(pm: ProjectileManager, k: int, s := 0) -> StandardMaterial3D:
	var over: Material = (pm.kinds[k]["mmi"] as MultiMeshInstance3D).material_override
	if over:
		return over as StandardMaterial3D
	return (pm.kinds[k]["mm"] as MultiMesh).mesh.surface_get_material(s) as StandardMaterial3D


func _shots_of(pm: ProjectileManager, inst: WeaponInstance) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst:
			out.append(j)
	return out


# ---------------------------------------------------------------- Dragon's Breath

func test_dragons_breath_orange_pellets_a_flame_tongue_and_a_red_hot_barrel() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	_creature(w["em"], Vector3(3, 0, 0))
	var pe := _emitter(w, _inst("boomstick", ["dragons_breath"], 3))
	# the pellets: a copy of the cored streak, the core orange, the halo round it a deep red
	var k := pe._kind()
	assert_int(k).is_not_equal(pe.projectile_kind)
	var mesh: Mesh = (pm.kinds[k]["mm"] as MultiMesh).mesh
	assert_int(mesh.get_surface_count()).is_equal(2)
	assert_object((pm.kinds[k]["mmi"] as MultiMeshInstance3D).material_override).is_null()
	assert_bool(_near((mesh.surface_get_material(0) as StandardMaterial3D).albedo_color, Color("#FFA236"))).is_true()
	var halo := mesh.surface_get_material(1) as StandardMaterial3D
	assert_bool(_near(halo.albedo_color, Color("#E8300A"))).is_true()
	assert_float(halo.albedo_color.a).is_equal_approx(0.85, 0.01)
	# the same turn as the plain pellets (nose first) and made once
	assert_bool(bool(pm.kinds[k]["turned"])).is_true()
	assert_int(pe._kind()).is_equal(k)
	# their tracer beads orange (the fire element), longer-lived than the plain spray's
	var tc: Color = pm._tracer_colour(pe.inst)
	assert_bool(tc.r > 0.9 and tc.g < 0.6).is_true()
	assert_float(float(pe.inst.params["tracer_life"])).is_greater(float(Registry.weapon("boomstick").params["tracer_life"]))
	# a shot: the tongue licks out of the muzzle, the barrel glows red-hot and cools in about 0.6 s
	assert_bool(pe._fire()).is_true()
	for j: int in _shots_of(pm, pe.inst):
		assert_int(pm.kind[j]).is_equal(k)
	assert_int(pe.tongues).is_equal(1)
	assert_int((w["fx"] as Fx)._n).is_greater(2)
	pe._tick(DT)
	assert_float(pe.heat_shown()).is_greater(0.9)
	var hot: StandardMaterial3D = pe._heat_mats[0]
	assert_float(hot.emission_energy_multiplier).is_greater(2.0)
	assert_float(hot.emission.r).is_greater(hot.emission.g * 2.0)
	# the barrels are hot, the stock is not
	var barrel := pe.visual.get_node("Held/Barrels/Barrel") as MeshInstance3D
	assert_object(barrel.material_override).is_same(hot)
	for m: MeshInstance3D in pe.visual.get_node("Held").find_children("*", "MeshInstance3D", true, false):
		if not str(m.get_path()).contains("Barrels"):
			assert_bool(pe._heat_mats.has(m.material_override)).override_failure_message(str(m.name) + " heated").is_false()
	pe._tick(0.7)
	assert_float(pe.heat_shown()).is_equal_approx(0.0, 0.001)
	# taken away (the arena), the pellets are plain again and the barrel takes its own material back
	var own_before: Material = pe._look_undo[barrel]["over"]
	_rebuild_with(pe, [])
	assert_int(pe._kind()).is_equal(pe.projectile_kind)
	assert_object(barrel.material_override).is_same(own_before)
	assert_bool(pe._heat_mats.is_empty()).is_true()
	assert_bool(pe._fire()).is_true()
	assert_int(pe.tongues).is_equal(1)


func test_the_plain_boomstick_has_one_barrel_no_beads_no_heat_no_tongue() -> void:
	var w := _world()
	_creature(w["em"], Vector3(3, 0, 0))
	var pe := _emitter(w, _inst("boomstick", [], 3))
	assert_bool((pe.visual.get_node("Held/Barrels/Barrel") as Node3D).visible).is_true()
	assert_bool((pe.visual.get_node("Held/Barrels/BarrelL") as Node3D).visible).is_false()
	assert_bool((pe.visual.get_node("Held/Barrels/BarrelR") as Node3D).visible).is_false()
	assert_bool((pe.visual.get_node("Held/Beads") as Node3D).visible).is_false()
	assert_int(pe.bead_count()).is_equal(0)
	assert_bool(pe._fire()).is_true()
	pe._tick(DT)
	assert_float(pe.heat_shown()).is_equal(0.0)
	assert_int(pe.tongues).is_equal(0)
	assert_int(pe._kind()).is_equal(pe.projectile_kind)


# ---------------------------------------------------------------- Both Barrels

func test_both_barrels_shows_a_second_barrel_and_beads_count_to_the_double() -> void:
	var w := _world()
	_creature(w["em"], Vector3(3, 0, 0))
	var pe := _emitter(w, _inst("boomstick", ["both_barrels"], 3))
	assert_bool((pe.visual.get_node("Held/Barrels/Barrel") as Node3D).visible).is_false()
	assert_bool((pe.visual.get_node("Held/Barrels/BarrelL") as Node3D).visible).is_true()
	assert_bool((pe.visual.get_node("Held/Barrels/BarrelR") as Node3D).visible).is_true()
	assert_bool((pe.visual.get_node("Held/Beads") as Node3D).visible).is_true()
	# three beads for every third pull; the fourth stays hidden
	assert_int(pe.bead_count()).is_equal(3)
	assert_bool((pe.visual.get_node("Held/Beads/Bead4") as Node3D).visible).is_false()
	assert_int(pe.beads_lit()).is_equal(0)
	var bead1 := pe.visual.get_node("Held/Beads/Bead1") as MeshInstance3D
	var dark: Material = bead1.material_override
	pe._fire()
	assert_int(pe.beads_lit()).is_equal(1)
	var lit := bead1.material_override as StandardMaterial3D
	assert_object(lit).is_not_same(dark)
	assert_bool(lit.emission_enabled).is_true()
	assert_float(lit.emission_energy_multiplier).is_greater(1.0)
	pe._fire()
	assert_int(pe.beads_lit()).is_equal(2)
	pe._fire()
	assert_int(pe.beads_lit()).is_equal(3)
	assert_int(pe.second_barrels).is_equal(0)
	# the second barrel goes a beat later and the count starts over
	pe._tick(ProjectileEmitter.DOUBLE_GAP + 0.02)
	assert_int(pe.second_barrels).is_equal(1)
	assert_int(pe.beads_lit()).is_equal(0)
	assert_object(bead1.material_override).is_same(dark)
	pe._fire()
	assert_int(pe.beads_lit()).is_equal(1)
	# taken away: one barrel, no beads
	_rebuild_with(pe, [])
	assert_bool((pe.visual.get_node("Held/Barrels/Barrel") as Node3D).visible).is_true()
	assert_bool((pe.visual.get_node("Held/Barrels/BarrelL") as Node3D).visible).is_false()
	assert_bool((pe.visual.get_node("Held/Beads") as Node3D).visible).is_false()
	assert_int(pe.bead_count()).is_equal(0)


func test_the_blunderbuss_keeps_the_beads_and_the_fire() -> void:
	var w := _world()
	_creature(w["em"], Vector3(3, 0, 0))
	var pe := _emitter(w, _inst("blunderbuss", ["dragons_breath", "birdshot_lane", "both_barrels"]))
	# its own double every second pull: two beads
	assert_int(pe.bead_count()).is_equal(2)
	# the bell and the barrels heat (the bell kept apart from the other gold parts so it glows alone)
	assert_bool(pe._heat_mats.size() >= 2).is_true()
	var bell := pe.visual.get_node("Held/Bell") as MeshInstance3D
	assert_bool(pe._heat_mats.has(bell.material_override)).is_true()
	# the cone's ghost pellets in the orange
	assert_int(pe._kind()).is_not_equal(pe.projectile_kind)
	assert_bool(pe._fire()).is_true()
	assert_int(pe.beads_lit()).is_equal(1)
	assert_int(pe.tongues).is_greater_equal(1)
	var pm: ProjectileManager = w["pm"]
	var ghosts := 0
	for j: int in _shots_of(pm, pe.inst):
		if (pm.extra[j] as Dictionary).has("ghost"):
			ghosts += 1
			assert_int(pm.kind[j]).is_equal(pe._kind())
	assert_int(ghosts).is_greater(0)


# ---------------------------------------------------------------- Toxic Peas

func test_toxic_peas_are_sickly_green_with_a_green_trail_in_the_pod_too() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	_creature(w["em"], Vector3(0, 0, -5))
	var pe := _emitter(w, _inst("peashooter", ["toxic_peas"], 3))
	var k := pe._kind()
	assert_int(k).is_not_equal(pe.projectile_kind)
	assert_bool(_near(_kind_mat(pm, k).albedo_color, Color("#6AB81E"))).is_true()
	# a green trail: tracer beads in the mutation's own green
	assert_bool(bool(pe.inst.params.get("tracer", false))).is_true()
	var tc: Color = pm._tracer_colour(pe.inst)
	assert_bool(_near(tc, Color("#6ED834"))).is_true()
	assert_float(tc.a).is_equal_approx(0.9, 0.001)
	# (pass 79, lane FX: its line in place of the beads)
	var before := pm.tracer_segments
	var j := pm.fire(k, Vector3(0, 1.5, 0), Vector3(0, 0, -14), 1.0, 0, 0.2, 1.0, pe.inst)
	for n in range(3):
		pm._physics_process(DT)
	assert_int(pm.tracer_segments).is_greater(before)
	assert_bool(_near(pm.tracer_col[pm.tracer_segments - 1], Color("#6ED834"))).is_true()
	pm._free(j)
	# the peas waiting in the pod are painted the same
	var peas := pe.visual.get_node("Familiar/Peas")
	var meshes: Array = peas.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_greater(0)
	for m: MeshInstance3D in meshes:
		assert_bool(_near((m.material_override as StandardMaterial3D).albedo_color, Color("#6AB81E"))).is_true()
	# taken away: pastel peas (the scene's (0.58, 0.9, 0.5) under the map's grade since pass 67), no trail
	_rebuild_with(pe, [])
	var g: Dictionary = pe._grade()
	var pastel := WeaponBehavior.grade_color(Color(0.58, 0.9, 0.5), float(g.get("value", 1.0)), float(g.get("saturation", 1.0)))
	for m: MeshInstance3D in peas.find_children("*", "MeshInstance3D", true, false):
		assert_bool(_near((m.material_override as StandardMaterial3D).albedo_color, pastel)).is_true()
	assert_int(pe._kind()).is_equal(pe.projectile_kind)
	assert_bool(bool(pe.inst.params.get("tracer", false))).is_false()


func test_the_pea_cannon_keeps_the_toxic_look_and_the_hand() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var pe := _emitter(w, _inst("pea_cannon", ["big_peas", "bouncing_peas", "toxic_peas", "fan_the_hammer"]))
	assert_bool(bool(pe.inst.params.get("tracer", false))).is_true()
	assert_bool(_near(_kind_mat(pm, pe._kind()).albedo_color, Color("#6AB81E"))).is_true()
	assert_object(pe._flick).is_not_null()
	assert_str(str(pe._flick.name)).is_equal("Hand")


# ---------------------------------------------------------------- Fan the Hammer

func test_fan_the_hammer_flicks_a_glove_under_the_pod_on_the_double_volley() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -5))
	var pe := _emitter(w, _inst("peashooter", ["fan_the_hammer"], 3))
	var hand := pe.visual.get_node("Familiar/Hand") as Node3D
	assert_object(pe._flick).is_same(hand)
	assert_bool(hand.visible).is_false()
	var rest := hand.transform
	assert_bool(pe._fire()).is_true()
	assert_bool(pe.flicking()).is_true()
	assert_int(pe.flicks).is_equal(1)
	# half way: out and swung across
	pe._tick(0.12)
	assert_bool(hand.visible).is_true()
	assert_bool(hand.transform.basis.is_equal_approx(rest.basis)).is_false()
	# the second volley went with it
	assert_int(pe._taps).is_equal(0)
	pe._tick(0.25)
	assert_bool(pe.flicking()).is_false()
	assert_bool(hand.visible).is_false()
	assert_bool(hand.transform.is_equal_approx(rest)).is_true()
	# without the mutation the hand never shows
	var plain := _emitter(w, _inst("peashooter", [], 3))
	assert_object(plain._flick).is_null()
	assert_bool(plain._fire()).is_true()
	plain._tick(0.1)
	assert_bool((plain.visual.get_node("Familiar/Hand") as Node3D).visible).is_false()
	assert_int(plain.flicks).is_equal(0)


# ---------------------------------------------------------------- Drum Mag

func test_drum_mag_a_bigger_drum_turning_faster_and_denser_tracers() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var plain := _emitter(w, _inst("tommy_gun", [], 3))
	var drum := _emitter(w, _inst("tommy_gun", ["drum_mag"], 3))
	assert_object(plain._drum).is_not_null()
	assert_object(drum._drum).is_not_null()
	assert_float(drum._drum.scale.x / plain._drum.scale.x).is_equal_approx(1.5, 0.001)
	# a notch a round: twice the plain gun's turn
	assert_float(float(drum.inst.params["drum_step"])).is_equal_approx(1.0, 0.001)
	assert_float(float(plain.inst.params.get("drum_step", 0.5))).is_equal_approx(0.5, 0.001)
	var b0 := drum._drum.transform.basis
	drum._turn_drum()
	var turned: float = b0.get_rotation_quaternion().angle_to(drum._drum.transform.basis.get_rotation_quaternion())
	assert_float(turned).is_equal_approx(1.0, 0.01)
	# a bolder line where the plain round lays a thin one (pass 79, lane FX: lines in place of pass 61's three beads a drop)
	var t0 := pm.tracer_segments
	var j := pm.fire(plain.projectile_kind, Vector3(0, 1.5, 0), Vector3(22, 0, 0), 1.0, 0, 0.16, 0.5, plain.inst)
	pm._physics_process(DT)
	assert_int(pm.tracer_segments - t0).is_equal(1)
	var thin: float = pm.tracer_width[pm.tracer_segments - 1]
	pm._free(j)
	var t1 := pm.tracer_segments
	var j2 := pm.fire(drum.projectile_kind, Vector3(0, 1.5, 0), Vector3(22, 0, 0), 1.0, 0, 0.16, 0.5, drum.inst)
	pm._physics_process(DT)
	assert_int(pm.tracer_segments - t1).is_equal(1)
	assert_float(pm.tracer_width[pm.tracer_segments - 1]).is_greater(thin)
	# taken away: the drum goes back to its size
	_rebuild_with(drum, [])
	assert_float(drum._drum.scale.x).is_equal_approx(plain._drum.scale.x, 0.0001)


func test_the_chicago_typewriter_keeps_the_big_drum() -> void:
	var w := _world()
	var gold := _emitter(w, _inst("chicago_typewriter", []))
	var big := _emitter(w, _inst("chicago_typewriter", ["drum_mag", "mini_crits", "tommy_sweep"]))
	assert_float(big._drum.scale.x / gold._drum.scale.x).is_equal_approx(1.5, 0.001)
	assert_int(int(big.inst.params.get("tracer_beads", 1))).is_equal(3)


# ---------------------------------------------------------------- Sticky

func test_sticky_glossy_resin_and_a_light_blinking_faster_on_its_ride() -> void:
	_wear_grenade()
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var e := _creature(em, Vector3(6, 0, 0))
	var lb := Lobber.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(_inst("lob_grenade", ["sticky"], 3), w["g"])
	var k := lb.shot_kind()
	assert_int(k).is_not_equal(lb.projectile_kind)
	var resin := _kind_mat(pm, k)
	assert_bool(_near(resin.albedo_color, Color("#D98A12"))).is_true()
	assert_float(resin.roughness).is_less(0.15)
	assert_bool(resin.emission_enabled).is_true()
	# thrown at the creature: it lands, sticks, and its light starts slow
	var j := pm.lob(k, Vector3(0, 1.2, 0), em.pos[e], 9.0, 1.0, 2.5, lb.inst, 1.0, lb.inst.params.duplicate())
	var n := 0
	while pm.stuck[j] < 0 and n < 200:
		pm._physics_process(DT)
		n += 1
	assert_int(pm.stuck[j]).is_equal(e)
	assert_bool((pm.extra[j] as Dictionary).has("blink")).is_true()
	var hz0 := pm.blink_hz(j)
	assert_float(hz0).is_less(4.0)
	pm._render()
	assert_int(pm.blinks_drawn).is_equal(1)
	# it blinks: on and off within the first beats
	var seen_on := false
	var seen_off := false
	for s in range(30):
		pm._physics_process(DT)
		if pm.blink_on(j):
			seen_on = true
		else:
			seen_off = true
	assert_bool(seen_on and seen_off).is_true()
	# faster towards the blast
	for s in range(30):
		pm._physics_process(DT)
	assert_float(pm.blink_hz(j)).is_greater(hz0 * 2.0)
	assert_int(pm.stuck[j]).is_equal(e)
	pm._free(j)
	pm._render()
	assert_int(pm.blinks_drawn).is_equal(0)


func test_a_plain_grenade_has_no_resin_and_no_light() -> void:
	_wear_grenade()
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := Lobber.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(_inst("lob_grenade", [], 3), w["g"])
	assert_int(lb.shot_kind()).is_equal(lb.projectile_kind)
	var j := pm.fire(lb.projectile_kind, Vector3(0, 1, 0), Vector3.ZERO, 1.0, 0, 0.3, 2.0, lb.inst)
	pm.stuck[j] = -1
	assert_bool((pm.extra[j] as Dictionary).has("blink")).is_false()
	pm._free(j)


func test_the_golden_pineapple_stays_gold_under_the_resin() -> void:
	_wear_grenade()
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var lb := Lobber.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(_inst("golden_pineapple", ["frag", "new_equipment", "sticky"]), w["g"])
	var mat := _kind_mat(pm, lb.shot_kind())
	# the model's own gold (vertex colours) under an almost white albedo, its own sheen (a mirror finish reads dark from
	# the camera) with a warm glow, and the light still blinks
	assert_bool(mat.vertex_color_use_as_albedo).is_true()
	assert_float(mat.albedo_color.v).is_greater(0.9)
	assert_float(mat.roughness).is_equal_approx(0.3, 0.001)
	assert_bool(mat.emission_enabled).is_true()
	assert_bool((lb.inst.params.get("look", {}) as Dictionary).has("blink")).is_true()


# ---------------------------------------------------------------- Thorny Weed

func test_thorny_weed_bristles_with_thorns_and_sheds_specks_on_the_sand() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var pe := _emitter(w, _inst("tumbleweed", ["thorns"], 3))
	var tk := pe.tint_kind(pe.inst.params["tint"])
	var k := pe._kind()
	assert_int(k).is_not_equal(tk)
	var base: Mesh = (pm.kinds[tk]["mm"] as MultiMesh).mesh
	var spiked: Mesh = (pm.kinds[k]["mm"] as MultiMesh).mesh
	assert_int(spiked.get_surface_count()).is_equal(base.get_surface_count() + 1)
	# eighteen four-sided thorns
	var arrays: Array = spiked.surface_get_arrays(spiked.get_surface_count() - 1)
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(18 * 4 * 3)
	# they stick out past the tangle
	assert_float(spiked.get_aabb().size.x).is_greater(base.get_aabb().size.x * 1.1)
	# the weed itself keeps the Thorny Weed's colours, drawn the same size and rolling the same way
	assert_bool(_near((spiked.surface_get_material(0) as StandardMaterial3D).albedo_color, Color("#3A2412"))).is_true()
	assert_float(float(pm.kinds[k]["scale"])).is_equal_approx(float(pm.kinds[tk]["scale"]), 0.0001)
	assert_int(pe._kind()).is_equal(k)
	# rolling: thorn specks on the sand along its way
	pm.clear_specks()
	var j := pm.fire(k, Vector3(0, 0.6, 0), Vector3(6, 0, 0), 1.0, 40, 0.7, 3.0, pe.inst)
	assert_bool((pm.extra[j] as Dictionary).has("speck")).is_true()
	for s in range(60):
		pm._physics_process(DT)
	var shed := pm.speck_count()
	assert_int(shed).is_greater_equal(4)
	assert_int(shed).is_less(20)
	pm._free(j)
	# they fade: gone after their life
	pm._tick_specks(4.0)
	assert_int(pm.speck_count()).is_equal(0)
	# pooled and capped: never more than SPECK_MAX however many fall
	for s in range(ProjectileManager.SPECK_MAX * 2):
		pm.drop_speck(Vector3(s * 0.1, 0, 0), 0.0, 0.3, Color(0.2, 0.1, 0.05, 0.9), 3.0)
	assert_int(pm.speck_count()).is_equal(ProjectileManager.SPECK_MAX)
	pm._tick_specks(DT)
	assert_int(pm._speck_mm.visible_instance_count).is_less_equal(ProjectileManager.SPECK_MAX)
	assert_int(pm._speck_mm.instance_count).is_equal(ProjectileManager.SPECK_MAX)


func test_a_plain_weed_has_no_thorns_and_sheds_nothing() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var pe := _emitter(w, _inst("tumbleweed", [], 3))
	assert_int(pe._kind()).is_equal(pe.projectile_kind)
	pm.clear_specks()
	var j := pm.fire(pe._kind(), Vector3(0, 0.6, 0), Vector3(6, 0, 0), 1.0, 40, 0.7, 3.0, pe.inst)
	assert_bool((pm.extra[j] as Dictionary).has("speck")).is_false()
	for s in range(30):
		pm._physics_process(DT)
	assert_int(pm.speck_count()).is_equal(0)
	pm._free(j)


func test_the_dust_devil_keeps_its_thorns_and_stays_black() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var pe := _emitter(w, _inst("dust_devil", ["boomerang", "dust_wake", "thorns"]))
	var k := pe._kind()
	var mesh: Mesh = (pm.kinds[k]["mm"] as MultiMesh).mesh
	assert_int(mesh.get_surface_count()).is_greater(1)
	var weed := mesh.surface_get_material(0) as StandardMaterial3D
	# its own jet black with the rim (the Thorny Weed's brown tint had turned it brown since pass 54)
	assert_float(weed.albedo_color.v).is_less(0.08)
	assert_bool(weed.rim_enabled).is_true()
	assert_bool((pm.extra[pm.fire(k, Vector3.ZERO, Vector3(6, 0, 0), 1.0, 40, 0.7, 1.0, pe.inst)] as Dictionary).has("speck")).is_true()


# ---------------------------------------------------------------- the warm-up and the data

func test_the_warm_up_makes_the_look_kinds_before_the_run() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var wu: Warmup = auto_free(Warmup.new())
	var vis: Node = auto_free(Registry.weapon("tumbleweed").visual.instantiate())
	var src := WeaponBehavior.projectile_source(vis)
	wu._shot_kinds["tumbleweed"] = pm.register_kind(src.mesh, src.material_override, 0.55)
	var before := pm.kinds.size()
	wu._warm_mutation_shots(pm)
	# Thorny Weed's tinted weed and its thorns
	assert_int(pm.kinds.size()).is_equal(before + 2)
	# the warm draw shows one speck and one blinker so their materials compile
	pm.warm_draw(Vector3(0, -8, 0))
	assert_int(pm._speck_mm.visible_instance_count).is_greater_equal(1)
	assert_int(pm._blink_mm.visible_instance_count).is_greater_equal(1)
	pm.warm_draw(Vector3.INF)
	assert_int(pm._blink_mm.visible_instance_count).is_equal(0)


func test_every_look_is_data_in_its_mutation() -> void:
	_wear_grenade()
	var looks := {
		"dragons_breath": ["tint", "look"],
		"both_barrels": ["look"],
		"toxic_peas": ["tint", "tracer", "tracer_color", "look"],
		"fan_the_hammer": ["look"],
		"drum_mag": ["drum_scale", "drum_step", "tracer_beads"],
		"sticky": ["tint", "look"],
		"thorns": ["tint", "look"],
	}
	for id: String in looks.keys():
		var m: MutationDef = Registry.mutation(id)
		for key: String in looks[id]:
			assert_bool(m.params.has(key)).override_failure_message(id + " has no " + key).is_true()
	# the numbers the mutations play by are untouched
	assert_float(float(Registry.mutation("dragons_breath").params["ignite_chance"])).is_equal_approx(0.6, 0.0001)
	assert_int(int(Registry.mutation("both_barrels").params["double_every"])).is_equal(3)
	assert_float(float((Registry.mutation("sticky").params["sticky"] as Dictionary)["seconds"])).is_equal_approx(1.3, 0.0001)
	assert_float(float(Registry.mutation("thorns").params["out_speed_mult"])).is_equal_approx(0.7, 0.0001)
