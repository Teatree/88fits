extends GdUnitTestSuite

## Pass 53, lane W1: the Rocket Pod, the Turret Buddy and the Zap Beam redone. Their old picks hidden in place and three
## new paths (Heavy Warhead / Cluster Munitions / Pressure Cooker, Last Stand / Buddy Squad / Bunker, Echo Zap / Fork /
## Static Field), the Hellfire Battery and the Iron Bastion in place of the Missile Massacre and the Turret Family, the
## Storm Cloud's final. The rocket flies nose first and hits as big as it looks, a strong blast's extra, the bomblets on
## the sand (a foot pops one, the cap, the chain), the Pressure Cooker's ramp, reset and glow and the battery's double
## volleys, Last Stand's boom as a turret goes, the bastion's focus mark, the echoes on a zapped creature.

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
var toasts: Array = []
var bursts: Array = []
var bolts: Array = []
var zones: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(at, col, size) -> void:
	bursts.append({"at": at, "col": col, "size": size})
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
func fx_lightning(points) -> void:
	bolts.append(points)
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	zones.append(_at)
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
var still := false
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return still
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
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
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0

const HIDE := ["thermobaric", "salvo", "bunker_buster", "dart_buddy", "venom_arc"]
const NEW := ["heavy_warhead", "cluster_munitions", "pressure_cooker", "last_stand", "echo_zap"]
## base weapon -> its path, in element / volume / motion order
const PATHS := {
	"rocket_pod": ["heavy_warhead", "cluster_munitions", "pressure_cooker"],
	"turret_buddy": ["last_stand", "buddy_squad", "bunker"],
	"zap_beam": ["echo_zap", "fork", "static_field"],
}
## base weapon -> [its evolution now, the old one hidden in place]
const EVOS := {"rocket_pod": ["hellfire_battery", "missile_massacre"], "turret_buddy": ["iron_bastion", "turret_family"]}


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd, shots, effects and ground marks.
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


## A tough creature on its feet where it was put, taking every hit whole.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.dr[i] = 0.0
	return i


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _pod(w: Dictionary, inst: WeaponInstance) -> MissilePod:
	var mp := MissilePod.new()
	(w["g"] as Node).add_child(mp)
	mp.setup(inst, w["g"])
	return mp


func _spawner(w: Dictionary, id: String, muts: Array = [], level := 1) -> Spawner:
	var sp := Spawner.new()
	(w["g"] as Node).add_child(sp)
	sp.setup(_inst(id, muts, level), w["g"])
	return sp


func _turret(w: Dictionary, sp: Spawner, at := Vector3.ZERO) -> Turret:
	var t := Turret.new()
	t.setup(sp, sp._proto, sp._turret_mesh, sp._turret_mat)
	(w["g"] as Node).add_child(t)
	t.global_position = at
	t.scale = Vector3.ONE
	return t


## The live shots of weapon `inst`.
func _live_of(pm: ProjectileManager, inst: WeaponInstance) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst:
			out.append(j)
	return out


# ---------------------------------------------------------------- the content

func test_the_old_picks_are_hidden_and_the_new_paths_stand() -> void:
	for id: String in HIDE:
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id + " is gone").is_not_null()
		assert_bool(m.hidden).override_failure_message(id).is_true()
		assert_bool(Registry.mutations_of(m.weapon).has(m)).override_failure_message(id + " is on the path").is_false()
	for base: String in PATHS.keys():
		var path: Array = Registry.mutations_of(base)
		assert_array(path.map(func(m: MutationDef) -> String: return m.id)).override_failure_message(base).is_equal(PATHS[base])
		assert_array(path.map(func(m: MutationDef) -> String: return m.mutation_kind)).override_failure_message(base).is_equal(["element", "volume", "motion"])
	for id: String in NEW:
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id).is_not_null()
		assert_str(m.rarity).override_failure_message(id).is_equal("rare")
		assert_float(m.weight).override_failure_message(id).is_equal(8.0)
		assert_str(m.text).override_failure_message(id + " says nothing").is_not_empty()
		assert_bool(m.params.is_empty()).override_failure_message(id + " has no params").is_false()
		assert_bool(m.hidden or m.is_hero()).override_failure_message(id).is_false()
		assert_str(m.element).override_failure_message(id + " carries an element").is_equal("")
	# the element-slot picks carry no element: a silver emblem, not a flame or a drop
	for id in ["heavy_warhead", "last_stand", "echo_zap"]:
		assert_str(Registry.mutation(id).mutation_kind).override_failure_message(id).is_equal("element")
	# the Hammer's Aftershock (pass 35) is untouched: the brief's id for the zap's pick was its, so the zap's is Echo Zap
	var hammer_as: MutationDef = Registry.mutation("aftershock")
	assert_str(hammer_as.weapon).is_equal("hammer")
	assert_str(hammer_as.mutation_kind).is_equal("motion")
	assert_bool(hammer_as.hidden).is_false()
	assert_bool((hammer_as.params.get("smash", {}) as Dictionary).has("aftershock")).is_true()
	assert_bool(Registry.mutations_of("hammer").has(hammer_as)).is_true()


func test_the_evolutions_are_repointed_and_the_old_ones_hidden() -> void:
	for base: String in EVOS.keys():
		var b: WeaponDef = Registry.weapon(base)
		var new_id: String = EVOS[base][0]
		var old_id: String = EVOS[base][1]
		assert_str(b.evolves_into).override_failure_message(base).is_equal(new_id)
		var evo: WeaponDef = Registry.weapon(new_id)
		assert_object(evo).override_failure_message(new_id).is_not_null()
		assert_bool(evo.is_evolution).is_true()
		assert_str(evo.evolved_from).is_equal(base)
		assert_int(evo.max_level).is_equal(1)
		assert_bool(evo.hidden).is_false()
		assert_bool(Registry.is_hidden(evo)).override_failure_message(new_id + " hidden").is_false()
		assert_str(evo.flavour).override_failure_message(new_id + " has no flavour").is_not_empty()
		assert_str(evo.behavior).is_equal(b.behavior)
		assert_bool(evo.params.has("final")).override_failure_message(new_id + " has no final").is_true()
		var old: WeaponDef = Registry.weapon(old_id)
		assert_object(old).override_failure_message(old_id + " is gone").is_not_null()
		assert_bool(old.hidden).override_failure_message(old_id + " shows").is_true()
		assert_bool(Registry.is_hidden(old)).is_true()
	# the Storm Cloud stays the Zap Beam's evolution: its final lifts Echo Zap's chance, its flavour says so, its visual is
	# untouched (Garry: "don't change the visuals at all")
	assert_str(Registry.weapon("zap_beam").evolves_into).is_equal("storm_cloud")
	var sc: WeaponDef = Registry.weapon("storm_cloud")
	assert_bool(sc.hidden).is_false()
	var fin: Dictionary = sc.params.get("final", {})
	assert_float(float((fin.get("echo_zap", {}) as Dictionary).get("chance", 0.0))).is_equal_approx(0.35, 0.0001)
	assert_str(sc.flavour).contains("35%")
	var vis := FileAccess.get_file_as_string("res://content/evolutions/storm_cloud/storm_cloud_visual.tscn")
	assert_str(vis).contains("radius = 0.9")
	assert_str(vis).contains('[node name="Held" type="MeshInstance3D"')
	assert_str(vis).contains('[node name="Puff3"')
	# the evolution rule: at level 5 with the three new picks, each base evolves into its new form and the carried path
	# with the final folds in
	var rp := Run.add_weapon(Registry.weapon("rocket_pod"), 5)
	for id: String in PATHS["rocket_pod"]:
		assert_bool(Run.add_mutation(id, true)).override_failure_message(id).is_true()
	assert_bool(Run.evolution_ready(rp)).is_true()
	var hb := Run.evolve(rp)
	assert_str(hb.def.id).is_equal("hellfire_battery")
	assert_float(float((hb.params["cluster"] as Dictionary).get("chance", 0.0))).is_equal_approx(1.0, 0.0001)
	assert_int(int((hb.params["cluster"] as Dictionary).get("count", 0))).is_equal(6)
	assert_bool(bool((hb.params["cluster"] as Dictionary).get("chain", false))).is_true()
	assert_int(int((hb.params["cluster"] as Dictionary).get("max", 0))).is_equal(30)
	# the mutation's numbers the final does not name stay (the bomblet's quarter damage, its 0.8 m pop)
	assert_float(float((hb.params["cluster"] as Dictionary).get("damage_frac", 0.0))).is_equal_approx(0.25, 0.0001)
	assert_float(float((hb.params["pressure"] as Dictionary).get("start", 0.0))).is_equal_approx(0.25, 0.0001)
	assert_float(float((hb.params["pressure"] as Dictionary).get("hit_vent", 0.0))).is_equal_approx(0.5, 0.0001)
	assert_float(float(hb.params.get("size_mult", 0.0))).is_equal_approx(1.5, 0.0001)
	assert_int(int((hb.params["overpressure"] as Dictionary).get("every", 0))).is_equal(4)
	assert_bool(bool(hb.params.get("cluster_spin", true))).is_false()
	var tb := Run.add_weapon(Registry.weapon("turret_buddy"), 5)
	for id: String in PATHS["turret_buddy"]:
		assert_bool(Run.add_mutation(id, true)).override_failure_message(id).is_true()
	assert_bool(Run.evolution_ready(tb)).is_true()
	var ib := Run.evolve(tb)
	assert_str(ib.def.id).is_equal("iron_bastion")
	assert_float(float((ib.params["focus"] as Dictionary).get("mult", 0.0))).is_equal_approx(0.2, 0.0001)
	# the bastion's own turret block wins over the carried Bunker's turn and Last Stand's smaller boom
	var tp: Dictionary = ib.params["turret"]
	assert_str(str(tp.get("style", ""))).is_equal("bunker")
	assert_int(int(tp.get("turn", 0))).is_equal(140)
	assert_float(float((tp["boom"] as Dictionary).get("radius", 0.0))).is_equal_approx(4.5, 0.0001)
	assert_float(float((tp["boom"] as Dictionary).get("damage_mult", 0.0))).is_equal_approx(6.0, 0.0001)
	assert_float(float(ib.params.get("max_turrets_mult", 0.0))).is_equal_approx(1.0, 0.0001)
	var zb := Run.add_weapon(Registry.weapon("zap_beam"), 5)
	for id: String in PATHS["zap_beam"]:
		assert_bool(Run.add_mutation(id, true)).override_failure_message(id).is_true()
	assert_bool(Run.evolution_ready(zb)).is_true()
	var scw := Run.evolve(zb)
	assert_str(scw.def.id).is_equal("storm_cloud")
	assert_float(float((scw.params["echo_zap"] as Dictionary).get("chance", 0.0))).is_equal_approx(0.35, 0.0001)
	assert_float(float((scw.params["echo_zap"] as Dictionary).get("gap", 0.0))).is_equal_approx(0.2, 0.0001)


# ---------------------------------------------------------------- the Rocket Pod

func test_heavy_warhead_hits_harder_throws_twice_as_far_and_blasts_bigger() -> void:
	var plain := _inst("rocket_pod")
	var heavy := _inst("rocket_pod", ["heavy_warhead"])
	assert_float(heavy.stat("damage")).is_equal_approx(plain.stat("damage") * 1.4, 0.001)
	assert_float(heavy.stat("knockback")).is_equal_approx(plain.stat("knockback") * 2.0, 0.001)
	assert_float(heavy.stat("area")).is_equal_approx(plain.stat("area") * 1.15, 0.001)
	assert_float(float(heavy.params.get("size_mult", 1.0))).is_equal_approx(1.35, 0.0001)
	assert_float(float((heavy.params["blast_fx"] as Dictionary).get("scale", 1.0))).is_equal_approx(1.5, 0.0001)
	# its rocket is drawn bigger and hits as big as it looks (0.3 m times its size); a plain one is the old 0.3
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var fx: Fx = w["fx"]
	var mp := _pod(w, heavy)
	var i := pm.launch_missile(mp.projectile_kind, Vector3(0, 1.5, 0), Vector3(1, 0, 0), 13.0, heavy.stat("damage"), heavy.stat("area"), 12.0, heavy, {"wander": 0.0, "life": 3.0, "trail": 1}, heavy.stat("knockback"))
	assert_float(pm.psize[i]).is_equal_approx(1.35, 0.0001)
	assert_float(pm.radius[i]).is_equal_approx(0.3 * 1.35, 0.0001)
	var mp0 := _pod(w, plain)
	var j := pm.launch_missile(mp0.projectile_kind, Vector3(0, 1.5, 0), Vector3(1, 0, 0), 13.0, 10.0, 1.5, 12.0, plain, {"wander": 0.0, "life": 3.0, "trail": 1}, 3.0)
	assert_float(pm.radius[j]).is_equal_approx(0.3, 0.0001)
	# the blast reads stronger: the burst, ring and kick at 1.5x the blast (the game's fx_burst), and on top of it the
	# flash and a ring of sparks (Fx.burst_strength: ten more particles than a plain burst)
	var g: Node = w["g"]
	pm.life[i] = 0.001
	var n0: int = fx._n
	pm._physics_process(DT)
	assert_int(pm.alive[i]).is_equal(0)
	var last: Dictionary = g.bursts[g.bursts.size() - 1]
	assert_float(float(last["size"])).is_equal_approx(heavy.stat("area") * 1.5, 0.001)
	assert_int(fx._n - n0).is_greater_equal(10)
	# a plain rocket's blast is the blast's own size, and no extra
	pm.life[j] = 0.001
	n0 = fx._n
	pm._physics_process(DT)
	last = g.bursts[g.bursts.size() - 1]
	assert_float(float(last["size"])).is_equal_approx(1.5, 0.001)
	assert_int(fx._n - n0).is_equal(0)
	# Fx.burst itself takes a strength: a strong one adds the flash, a ball and sparks
	n0 = fx._n
	fx.burst(Vector3.ZERO, Color.WHITE, 1.0)
	assert_int(fx._n - n0).is_equal(2)
	n0 = fx._n
	fx.burst(Vector3.ZERO, Color.WHITE, 1.0, 1.5)
	assert_int(fx._n - n0).is_greater_equal(12)


func test_the_rocket_flies_nose_first() -> void:
	# the visual's Projectile node is turned so its capsule's long axis (Y) lies along -Z; the pod hands that turn to its
	# kind, and the drawn rocket's long axis follows its flight (it was drawn crosswise: the kind had mesh and scale only)
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("rocket_pod")
	var mp := _pod(w, inst)
	var kb := pm.kind_basis(mp.projectile_kind)
	assert_bool((kb * Vector3.UP).is_equal_approx(Vector3(0, 0, -1))).override_failure_message(str(kb)).is_true()
	assert_bool(bool(pm.kinds[mp.projectile_kind]["turned"])).is_true()
	var i := pm.launch_missile(mp.projectile_kind, Vector3(0, 1.5, 0), Vector3(1, 0, 0), 13.0, 10.0, 1.5, 12.0, inst, {"wander": 0.0, "life": 3.0, "trail": 1}, 3.0)
	pm._physics_process(DT)
	pm._render()
	var mm: MultiMesh = pm.kinds[mp.projectile_kind]["mm"]
	assert_int(mm.visible_instance_count).is_equal(1)
	# the basis _render hands the instance (the headless renderer keeps none to read back): the capsule's own long axis
	# (its Y) lies along the flight, and it is drawn at the rocket's size
	var drawn := pm.draw_basis(i)
	var along: float = absf(drawn.y.normalized().dot(pm.vel[i].normalized()))
	assert_float(along).override_failure_message("long axis against the flight: " + str(drawn)).is_greater(0.99)
	assert_float(drawn.y.length()).is_equal_approx(float(pm.kinds[mp.projectile_kind]["scale"]) * pm.psize[i], 0.001)
	# the same shot through a kind that is not turned would fly crosswise: its Y stays across the flight
	var k0 := pm.register_kind(CapsuleMesh.new(), null)
	pm.kind[i] = k0
	var flat := pm.draw_basis(i)
	assert_float(absf(flat.y.normalized().dot(pm.vel[i].normalized()))).is_less(0.1)
	pm.kind[i] = mp.projectile_kind
	# the Hellfire Battery's rocket is turned the same way and bigger, and the bees' capsule too
	for id in ["hellfire_battery", "hornet_nest"]:
		var vis: Node3D = auto_free((Registry.weapon(id).visual as PackedScene).instantiate())
		var proj := vis.get_node("Projectile") as Node3D
		assert_bool((proj.transform.basis.orthonormalized() * Vector3.UP).is_equal_approx(Vector3(0, 0, -1))).override_failure_message(id).is_true()
	var hf: Node3D = auto_free((Registry.weapon("hellfire_battery").visual as PackedScene).instantiate())
	assert_float(((hf.get_node("Projectile") as MeshInstance3D).mesh as CapsuleMesh).radius).is_greater(0.09)
	# a plain kind is not turned, and a kind registered with a basis keeps it
	var k := pm.register_kind(BoxMesh.new(), null)
	assert_bool(bool(pm.kinds[k]["turned"])).is_false()
	var turn := Basis(Vector3.RIGHT, PI * 0.5)
	var k2 := pm.register_kind(BoxMesh.new(), null, 1.0, false, turn)
	assert_bool(pm.kind_basis(k2).is_equal_approx(turn)).is_true()
	assert_bool(bool(pm.kinds[k2]["turned"])).is_true()


func test_cluster_munitions_scatter_bomblets_that_pop_under_a_foot() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("rocket_pod", ["cluster_munitions"])
	var cl: Dictionary = inst.params["cluster"]
	assert_float(float(cl["chance"])).is_equal_approx(0.3, 0.0001)
	assert_int(int(cl["count"])).is_equal(5)
	# every blast clusters here (the chance is data); a rocket's blast where it ends scatters five
	inst.params["cluster"]["chance"] = 1.0
	var mp := _pod(w, inst)
	var field: Bomblets = pm.bomblets
	assert_object(field).is_not_null()
	var i := pm.launch_missile(mp.projectile_kind, Vector3(0, 0.3, 0), Vector3(1, 0, 0), 13.0, 10.0, 1.5, 12.0, inst, {"wander": 0.0, "life": 3.0, "trail": 1}, 3.0)
	pm.life[i] = 0.001
	pm._physics_process(DT)
	assert_int(pm.alive[i]).is_equal(0)
	assert_int(field.count_of(inst)).is_equal(5)
	assert_int(field.scattered).is_equal(5)
	# they hop out of the blast first, within the spread, then lie armed on the sand
	for s: int in field.live():
		assert_bool(field.is_armed(s)).is_false()
	field.step(Bomblets.TOSS + 0.05)
	for s: int in field.live():
		assert_bool(field.is_armed(s)).is_true()
		assert_float(Vector2(field.pos[s].x, field.pos[s].z).length()).is_less_equal(float(cl["spread"]) + 0.001)
		assert_float(field.pos[s].y).is_equal_approx(0.0, 0.001)
	# nobody near: nothing pops
	field.step(DT)
	assert_int(field.pops).is_equal(0)
	# a creature within the trigger pops one: a quarter of the rocket's damage in the pop's radius; the others stay
	var slot: int = field.live()[0]
	var e := _creature(em, field.pos[slot] + Vector3(0.3, 0, 0))
	em._rebuild_grid()
	var hp0: float = em.hp[e]
	for n in range(6):
		field.step(DT)
	assert_int(field.pops).is_greater_equal(1)
	assert_int(field.count_of(inst)).is_less(5)
	assert_float(hp0 - em.hp[e]).is_greater_equal(2.5 - 0.001)
	# the pop is the weapon's: its kills and damage are the Rocket Pod's (the damage went through its id)
	assert_float(fmod(hp0 - em.hp[e], 2.5)).is_equal_approx(0.0, 0.01)
	# a chance of zero scatters nothing
	inst.params["cluster"]["chance"] = 0.0
	var before := field.scattered
	var i2 := pm.launch_missile(mp.projectile_kind, Vector3(30, 0.3, 30), Vector3(1, 0, 0), 13.0, 10.0, 1.5, 12.0, inst, {"wander": 0.0, "life": 3.0, "trail": 1}, 3.0)
	pm.life[i2] = 0.001
	pm._physics_process(DT)
	assert_int(field.scattered).is_equal(before)
	# the bomblets' life: they go by themselves after `life` seconds
	field.step(float(cl["life"]) + 0.1)
	assert_int(field.count_of(inst)).is_equal(0)


func test_bomblets_keep_to_their_cap_and_the_batterys_chain_pops_them_all() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("rocket_pod", ["cluster_munitions"])
	var field: Bomblets = pm.bomblets
	field.game = w["g"]
	var cl: Dictionary = inst.params["cluster"]
	# the cap: at most `max` per weapon, the oldest going quietly
	var first := field.scatter(inst, Vector3(0, 0, 0), 10.0, cl)
	assert_int(first).is_equal(5)
	var oldest: Array = field.live()
	for n in range(3):
		field.scatter(inst, Vector3(0, 0, 0), 10.0, cl)
	assert_int(field.count_of(inst)).is_equal(20)
	field.scatter(inst, Vector3(0, 0, 0), 10.0, cl)
	assert_int(field.count_of(inst)).is_equal(20)
	assert_int(field.pops).is_equal(0)
	for s: int in oldest:
		assert_bool(field.alive[s] == 1 and field.weapon[s] == inst and field.order[s] <= 5).override_failure_message("the oldest stayed").is_false()
	# another weapon's bomblets count apart
	var other := _inst("hellfire_battery", ["heavy_warhead", "cluster_munitions", "pressure_cooker"])
	var cfg: Dictionary = other.params["cluster"]
	assert_int(int(cfg["max"])).is_equal(30)
	field.scatter(other, Vector3(40, 0, 40), 24.0, cfg)
	assert_int(field.count_of(other)).is_equal(6)
	assert_int(field.count_of(inst)).is_equal(20)
	field.clear()
	assert_int(field.count).is_equal(0)
	# the chain: the battery's bomblets within 1.2 m of a pop go too, and theirs after them; six tight ones all go on one
	# foot, every pop a blast of its own
	var tight := cfg.duplicate(true)
	tight["spread"] = 0.5
	assert_int(field.scatter(other, Vector3(10, 0, 10), 24.0, tight)).is_equal(6)
	field.step(Bomblets.TOSS + 0.05)
	var slot: int = field.live()[0]
	var e := _creature(em, field.pos[slot] + Vector3(0.2, 0, 0))
	em._rebuild_grid()
	var hp0: float = em.hp[e]
	for n in range(6):
		field.step(DT)
	assert_int(field.pops).is_equal(6)
	assert_int(field.count_of(other)).is_equal(0)
	assert_float(hp0 - em.hp[e]).is_greater_equal(24.0 * 0.25 - 0.001)
	# without the chain only the one under the foot goes
	var lone := cl.duplicate(true)
	lone["spread"] = 0.5
	field.scatter(inst, Vector3(20, 0, 20), 10.0, lone)
	field.step(Bomblets.TOSS + 0.05)
	var slot2: int = field.live()[0]
	_creature(em, field.pos[slot2] + Vector3(0.2, 0, 0))
	em._rebuild_grid()
	var pops0 := field.pops
	for n in range(6):
		field.step(DT)
	assert_int(field.pops - pops0).is_less(5)
	assert_int(field.count_of(inst)).is_greater(0)


func test_pressure_cooker_builds_attack_speed_standing_still_and_the_pod_glows() -> void:
	# re-pinned in pass 60 (Garry: "while standing still the rate of fire of the Rocket Pod increases, every second, up
	# to +200%. Being hit or moving stops it. Takes like 15 seconds to get to max"): the pressure climbs with stillness
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _inst("rocket_pod", ["pressure_cooker"])
	var mp := _pod(w, inst)
	var cd := inst.stat("cooldown")
	var hero: Node3D = w["hero"]
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
	assert_float(mp.pressure_bonus()).is_equal_approx(0.0, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd, 0.0001)
	# standing still: halfway at 7.5 s, the top (+200%) at 15
	hero.set("still", true)
	for k in range(int(round(7.5 / DT))):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.5, 0.01)
	assert_float(mp.fire_interval()).is_equal_approx(cd / 2.0, 0.02)
	for k in range(int(round(8.0 / DT))):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(1.0, 0.0001)
	assert_float(mp.pressure_bonus()).is_equal_approx(2.0, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd / 3.0, 0.0001)
	# the glow follows the pressure: the pod's body and tube materials, duplicated for this pod, warm to hot orange
	assert_int(mp._heat_mats.size()).is_greater_equal(2)
	mp._tick_heat()
	assert_float(mp.heat_shown()).is_equal_approx(1.0, 0.0001)
	for m: StandardMaterial3D in mp._heat_mats:
		assert_bool(m.emission_enabled).is_true()
		assert_bool(m.emission.is_equal_approx(MissilePod.HEAT_COLOR)).is_true()
		assert_float(m.emission_energy_multiplier).is_equal_approx(MissilePod.HEAT_ENERGY, 0.0001)
	# the pod's own materials, not the scene's: the tips' emissive material is left alone
	var tip := mp.visual.get_node("Familiar/Body/Cluster/Tip1") as MeshInstance3D
	assert_bool(mp._heat_mats.has(tip.material_override)).is_false()
	# a hit on the hero vents half, and the glow follows
	hero.emit_signal("hit")
	assert_float(mp.pressure).is_equal_approx(0.5, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd / 2.0, 0.0001)
	mp._tick_heat()
	assert_float(mp.heat_shown()).is_equal_approx(0.5, 0.0001)
	# a hit the Energy Shield took vents too
	hero.emit_signal("shield_hit", false)
	assert_float(mp.pressure).is_equal_approx(0.25, 0.0001)
	# a step lets it all out (once the hit's hold is over: the knock's own step is not him moving, pass 60)
	hero.set("still", false)
	for k in range(int(MissilePod.VENT_HOLD / DT) + 2):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd, 0.0001)
	# the re-arm after a volley is the pressure's interval, not the sheet's cooldown
	hero.set("still", true)
	mp.pressure = 1.0
	_creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	mp.cooldown_left = 0.0
	mp._process(DT)
	assert_int(mp.bursts).is_equal(1)
	assert_float(mp.cooldown_left).is_equal_approx(cd / 3.0, 0.0001)
	# a pod without the pick is untouched: no pressure, no glow, the sheet's cooldown
	var plain := _pod(w, _inst("rocket_pod"))
	assert_float(plain.pressure_bonus()).is_equal_approx(0.0, 0.0001)
	assert_int(plain._heat_mats.size()).is_equal(0)
	plain.cooldown_left = 0.0
	plain._process(DT)
	assert_float(plain.cooldown_left).is_equal_approx(cd, 0.0001)


func test_the_hellfire_battery_starts_hot_keeps_half_on_a_hit_and_doubles_every_fourth_volley() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _inst("hellfire_battery", ["heavy_warhead", "cluster_munitions", "pressure_cooker"])
	Run.elapsed = 0.0
	Run.held_time = 0.0
	var mp := _pod(w, inst)
	var cd := inst.stat("cooldown")
	assert_float(cd).is_equal_approx(1.6, 0.0001)
	# +25% from the start, +200% at full pressure (pass 60: the Cooker's ceiling and 15 s, the Battery's own +25% start;
	# the pressure is built by standing still, not by going unhit)
	assert_float(mp.pressure_bonus()).is_equal_approx(0.25, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd / 1.25, 0.0001)
	mp.pressure = 1.0
	assert_float(mp.pressure_bonus()).is_equal_approx(2.0, 0.0001)
	# a hit vents half of it
	mp.note_hit()
	assert_float(mp.pressure).is_equal_approx(0.5, 0.0001)
	assert_float(mp.pressure_bonus()).is_equal_approx(0.25 + 1.75 * 0.5, 0.0001)
	# the battery: six tubes and six tips, no quarter turns of the cluster, a vent
	assert_int(mp._tips.size()).is_equal(6)
	assert_bool(mp._cluster_spins).is_false()
	assert_object(mp.visual.get_node_or_null("Familiar/Body/Vent")).is_not_null()
	# six tubes in two rows in the scene; in play MeshMerge draws them as one (they share a material), the tips apart
	var hf_scene := FileAccess.get_file_as_string("res://content/evolutions/hellfire_battery/hellfire_battery_visual.tscn")
	for k in range(1, 7):
		assert_str(hf_scene).contains('[node name="Tube%d" type="MeshInstance3D" parent="Familiar/Body/Cluster"]' % k)
	assert_bool(mp.visual.get_node_or_null("Familiar/Body/Cluster/Merged_Tube1") != null or mp.visual.get_node_or_null("Familiar/Body/Cluster/Tube6") != null).is_true()
	# the plain pod's cluster still turns, with its four tips
	var pod := _pod(w, _inst("rocket_pod"))
	assert_int(pod._tips.size()).is_equal(4)
	assert_bool(pod._cluster_spins).is_true()
	# at full pressure every fourth volley is a double volley
	_creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	mp.pressure = 1.0
	var n := inst.stat_int("amount")
	assert_int(n).is_equal(8)
	var sizes: Array = []
	for k in range(8):
		mp._queue.clear()
		assert_bool(mp._fire()).is_true()
		sizes.append(mp._queue.size())
	assert_array(sizes).is_equal([n, n, n, 2 * n, n, n, n, 2 * n])
	assert_int(mp.doubled).is_equal(2)
	# below the top, never
	Run.elapsed = 65.0
	mp.note_hit()
	mp._queue.clear()
	for k in range(8):
		mp._queue.clear()
		mp._fire()
		assert_int(mp._queue.size()).is_equal(n)
	assert_int(mp.doubled).is_equal(2)


# ---------------------------------------------------------------- the Turret Buddy

func test_last_stand_blows_a_turret_up_as_it_goes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var sp := _spawner(w, "turret_buddy", ["last_stand"])
	var boom: Dictionary = (sp.inst.params["turret"] as Dictionary)["boom"]
	assert_float(float(boom["radius"])).is_equal_approx(3.0, 0.0001)
	var t := _turret(w, sp)
	var near := _creature(em, Vector3(1.5, 0, 0))
	var far := _creature(em, Vector3(6, 0, 0))
	em._rebuild_grid()
	var hp_near: float = em.hp[near]
	var hp_far: float = em.hp[far]
	var bursts0: int = g.bursts.size()
	t.expire()
	assert_int(t.booms).is_equal(1)
	assert_float(hp_near - em.hp[near]).is_equal_approx(sp.stat("damage") * 4.0, 0.001)
	assert_float(hp_far - em.hp[far]).is_equal_approx(0.0, 0.0001)
	assert_int(g.bursts.size()).is_greater(bursts0)
	# only once, however often it is told to go
	t.expire()
	assert_int(t.booms).is_equal(1)
	# a plain buddy just shrinks away
	var plain := _spawner(w, "turret_buddy")
	var t2 := _turret(w, plain)
	hp_near = em.hp[near]
	t2.expire()
	assert_int(t2.booms).is_equal(0)
	assert_float(em.hp[near]).is_equal_approx(hp_near, 0.0001)
	# the oldest making room for a new drop blows too: seven drops on a cap of six, one boom
	var sq := _spawner(w, "turret_buddy", ["last_stand"])
	for n in range(7):
		sq._fire()
	var total := 0
	for c in g.get_children():
		if c is Turret and (c as Turret).owner_behavior == sq:
			total += (c as Turret).booms
	assert_int(total).is_equal(1)


func test_the_iron_bastion_ganging_up_its_model_and_its_boom() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var bare := _inst("iron_bastion")
	assert_int(bare.stat_int("amount")).is_equal(2)
	assert_float(bare.stat("lifetime")).is_equal_approx(30.0, 0.0001)
	assert_int(bare.stat_int("pierce")).is_equal(1)
	var full := _inst("iron_bastion", ["last_stand", "buddy_squad", "bunker"])
	# six standing, whatever Buddy Squad says (the final's max_turrets_mult)
	var sp := _spawner(w, "iron_bastion", ["last_stand", "buddy_squad", "bunker"])
	assert_int(sp.max_turrets()).is_equal(6)
	# the focus: a creature one bastion's round strikes takes +20% from the next for 2 s (the mark)
	var e := _creature(em, Vector3(0, 0, 0))
	em._rebuild_grid()
	var hp0: float = em.hp[e]
	# pass 62: the round pierces, so its first creature takes the pierce drop-off's first_mult (ProjectileManager)
	var dmg := full.stat("damage") * ProjectileManager.falloff_factor(ProjectileManager.weapon_falloff(full), 1)
	var j := pm.fire(sp.projectile_kind, Vector3(-1.5, 0.6, 0), Vector3(18, 0, 0), full.stat("damage"), 1, 0.2, 1.0, full, 7.0)
	var n := 0
	while em.hp[e] >= hp0 - 0.0001 and n < 40:
		pm._physics_process(DT)
		n += 1
	assert_float(hp0 - em.hp[e]).is_equal_approx(dmg, 0.001)
	assert_float(em.mark_t[e]).is_equal_approx(2.0, 0.02)
	assert_float(em.mark_mult[e]).is_equal_approx(1.2, 0.0001)
	# the next round lands for 1.2x
	hp0 = em.hp[e]
	var j2 := pm.fire(sp.projectile_kind, Vector3(-1.5, 0.6, 0), Vector3(18, 0, 0), full.stat("damage"), 1, 0.2, 1.0, full, 7.0)
	n = 0
	while em.hp[e] >= hp0 - 0.0001 and n < 40:
		pm._physics_process(DT)
		n += 1
	assert_float(hp0 - em.hp[e]).is_equal_approx(dmg * 1.2, 0.001)
	assert_int(j).is_greater_equal(0)
	assert_int(j2).is_greater_equal(0)
	# a Turret Buddy's round leaves no mark
	var e2 := _creature(em, Vector3(0, 0, 10))
	em._rebuild_grid()
	var buddy := _spawner(w, "turret_buddy")
	hp0 = em.hp[e2]
	pm.fire(buddy.projectile_kind, Vector3(-1.5, 0.6, 10), Vector3(18, 0, 0), 4.0, 0, 0.2, 1.0, buddy.inst, 4.0)
	n = 0
	while em.hp[e2] >= hp0 - 0.0001 and n < 40:
		pm._physics_process(DT)
		n += 1
	assert_float(em.mark_t[e2]).is_equal_approx(0.0, 0.0001)
	# its boom is the bigger one
	var t := _turret(w, sp, Vector3(20, 0, 20))
	var e3 := _creature(em, Vector3(23.5, 0, 20))
	em._rebuild_grid()
	hp0 = em.hp[e3]
	t.expire()
	assert_int(t.booms).is_equal(1)
	assert_float(hp0 - em.hp[e3]).is_equal_approx(full.stat("damage") * 6.0, 0.001)
	# its own model: the bunker stance made heavy, built by the Blender script, instanced by its visual (the lead's asset
	# import makes the scene's Turret node appear; until then the file and the GLB are what is checked)
	assert_bool(FileAccess.file_exists("res://art/props/iron_bastion.glb")).is_true()
	var vis := FileAccess.get_file_as_string("res://content/evolutions/iron_bastion/iron_bastion_visual.tscn")
	assert_str(vis).contains('path="res://art/props/iron_bastion.glb"')
	assert_str(vis).contains('[node name="Turret" parent="." instance=ExtResource("turret")]')
	var script := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../tools/blender_turret.py"))
	assert_str(script).contains('"bastion": "iron_bastion.glb"')
	assert_str(script).contains("heavy=key == \"bastion\"")
	for nm in ["Base", "BaseTop", "Sandbags", "SandbagsTop", "Tripod", "TripodTop", "Yaw", "Gun", "Barrel", "BarrelL", "BarrelR", "Muzzle"]:
		assert_str(script).override_failure_message(nm).contains('"%s"' % nm)
	# the turret still reads its stance off the params: bunker, twin barrels, the bastion's traverse
	assert_str(t._style).is_equal("bunker")
	assert_int(t._barrels).is_equal(2)
	assert_float(t.turn_rate()).is_equal_approx(140.0, 0.0001)


# ---------------------------------------------------------------- the Zap Beam

func test_echo_zap_lands_three_smaller_zaps_on_the_same_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var inst := _inst("zap_beam", ["echo_zap"])
	var cfg: Dictionary = inst.params["echo_zap"]
	assert_float(float(cfg["chance"])).is_equal_approx(0.2, 0.0001)
	assert_int(int(cfg["count"])).is_equal(3)
	assert_float(float(cfg["damage_frac"])).is_equal_approx(0.4, 0.0001)
	assert_float(float(cfg["gap"])).is_equal_approx(0.25, 0.0001)
	# every hit echoes here (the chance is data)
	inst.params["echo_zap"]["chance"] = 1.0
	var b := Beam.new()
	g.add_child(b)
	b.setup(inst, g)
	var e := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var hp0: float = em.hp[e]
	var dmg := inst.stat("damage")
	assert_bool(b._fire()).is_true()
	assert_float(hp0 - em.hp[e]).is_equal_approx(dmg, 0.001)
	assert_int(b.pending_shocks()).is_equal(3)
	assert_int(b.shocks_landed).is_equal(0)
	# the first a gap later, each for 40% of the hit, with a discharge on the creature: bolts, and a pale blue tint
	var bolts0: int = (w["fx"] as Fx)._live
	b._tick(0.2)
	assert_int(b.shocks_landed).is_equal(0)
	b._tick(0.06)
	assert_int(b.shocks_landed).is_equal(1)
	assert_float(hp0 - em.hp[e]).is_equal_approx(dmg + dmg * 0.4, 0.001)
	assert_int((w["fx"] as Fx)._live - bolts0).is_greater_equal(3)
	assert_float(em.status_t[e]).is_greater(0.0)
	assert_bool(em.status_tint[e].is_equal_approx(Beam.SHOCK_TINT)).is_true()
	b._tick(0.25)
	b._tick(0.25)
	assert_int(b.shocks_landed).is_equal(3)
	assert_int(b.pending_shocks()).is_equal(0)
	assert_float(hp0 - em.hp[e]).is_equal_approx(dmg + 3.0 * dmg * 0.4, 0.001)
	b._tick(0.5)
	assert_int(b.shocks_landed).is_equal(3)
	# a creature that is gone takes its echoes with it: the slot's serial tells the next one apart
	assert_bool(b._fire()).is_true()
	assert_int(b.pending_shocks()).is_equal(3)
	em.serial[e] += 1
	hp0 = em.hp[e]
	b._tick(0.3)
	assert_int(b.pending_shocks()).is_equal(0)
	assert_float(em.hp[e]).is_equal_approx(hp0, 0.0001)
	# a chained hit echoes too: two creatures in reach, both zapped, both queued
	var e2 := _creature(em, Vector3(3, 0, 2))
	em._rebuild_grid()
	em.serial[e] += 1
	assert_bool(b._fire()).is_true()
	assert_int(b.pending_shocks()).is_equal(6)
	assert_int(e2).is_greater_equal(0)
	# a Zap Beam without the pick echoes nothing
	var plain := Beam.new()
	g.add_child(plain)
	plain.setup(_inst("zap_beam"), g)
	assert_bool(plain._fire()).is_true()
	assert_int(plain.pending_shocks()).is_equal(0)
	# the Storm Cloud's chance is 35% with the path on it, and it keeps its cloud
	var sc := Beam.new()
	g.add_child(sc)
	sc.setup(_inst("storm_cloud", ["echo_zap", "fork", "static_field"]), g)
	assert_float(float((sc.inst.params["echo_zap"] as Dictionary)["chance"])).is_equal_approx(0.35, 0.0001)
	assert_object(sc._cloud).is_not_null()
	assert_bool(sc._cloud.visible).is_true()
