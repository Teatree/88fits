extends GdUnitTestSuite

## Pass 35: the art picks (GOB-D, RUN-D, a two-way ANT-A), the Sabre's slice, the Hammer, the Drifter's own Revolver and
## the Golden Revolver's lines of energy, the Gravity Gun (never a boss, an Elite or a special; nothing it holds dies
## until it lands) and its black holes, the Teleport.

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

const FAKE_SINK := """extends Node
func sand(_a, _b = 1.0) -> void:
	pass
func burst(_a, _b, _c = 1.0) -> void:
	pass
func flame(_a, _b, _c = 0.5, _d = Color.WHITE) -> void:
	pass
func mote(_a, _b, _c, _d, _e) -> void:
	pass
func flash_ring(_a, _b, _c, _d = 0.35) -> void:
	pass
func scorch(_a, _b, _c, _d, _e = 1.5, _f = 3.0) -> void:
	pass
func line(_a, _b, _c, _d, _e, _f = 1.2) -> void:
	pass
func shake(_a) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func forward() -> Vector3:
	return Vector3(0, 0, -1)
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1, 0) + d * 0.4
"""


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
	var sink := Node.new()
	sink.set_script(_script(FAKE_SINK))
	g.add_child(sink)
	g.fx = sink
	g.telegraphs = sink
	g.camera = sink
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return g


func _behaviour(b: WeaponBehavior, g: Node, id: String, level: int = 1) -> WeaponBehavior:
	b.inst = WeaponInstance.new(Registry.weapon(id), level)
	b.inst.rebuild(Run.player_sheet, [])
	b.game = g
	b.player = g.player
	g.add_child(b)
	return b


# ---------------------------------------------------------------- the art picks

func test_the_chosen_art_variants_are_in_play() -> void:
	assert_str(Registry.enemy("goblin").variant).is_equal("GOB-D")
	assert_str(Registry.enemy("goblin_runt").variant).is_equal("RUN-D")
	var ant: EnemyDef = Registry.enemy("fire_ant")
	# (Garry picked ANT-E, eight directions, on 2026-10-25: ANT-A is pinned as a look, not as the played one)
	assert_bool(ant.variants.has("ANT-A")).is_true()
	# ANT-A walks up and down only, like every other creature: no side or diagonal sets
	var anims: Dictionary = ant.variants["ANT-A"]["anims"]
	for k in ["run_s", "idle_s", "run_bd", "run_fd"]:
		assert_bool(anims.has(k)).override_failure_message("ANT-A still has " + k).is_false()
	assert_int(int(anims.get("run", 0))).is_greater(0)
	assert_int(int(anims.get("run_b", 0))).is_greater(0)
	assert_bool(ant.variants["ANT-A"]["anims"].has("run_s")).is_false()


# ---------------------------------------------------------------- the Sabre

func test_the_sabre_slices_back_and_forth() -> void:
	var g := _setup()
	var t: Thruster = _behaviour(Thruster.new(), g, "sabre")
	assert_bool(t._slices()).is_true()
	var half := deg_to_rad(float(t.inst.params["thrust"]["slice_deg"])) * 0.5
	# the first swing runs from one end of the arc to the other, the next one back
	assert_float(t._edge(0, 0.0)).is_equal_approx(-half, 0.001)
	assert_float(t._edge(0, 1.0)).is_equal_approx(half, 0.001)
	assert_float(t._edge(1, 0.0)).is_equal_approx(half, 0.001)
	assert_float(t._edge(1, 1.0)).is_equal_approx(-half, 0.001)
	# the Pike still thrusts
	var p: Thruster = _behaviour(Thruster.new(), g, "pike")
	assert_bool(p._slices()).is_false()


func test_a_slice_throws_out_and_along_the_swing() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var i := em.spawn("goblin", Vector3(2.0, 0, 0), null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	var t: Thruster = _behaviour(Thruster.new(), g, "sabre")
	var hp0: float = em.hp[i]
	# the target line points east; the edge sweeps across it (swing 0: the yaw grows)
	var yaw0 := atan2(-1.0, 0.0)
	t._cut(yaw0, -0.3, 0.3, 2.6, 0.7, 1.0)
	assert_float(em.hp[i]).is_less(hp0)
	var k: Vector3 = em.kb[i]
	# away from the hero (east) and along the swing (north, the edge's way at the east) together
	assert_float(k.x).is_greater(0.0)
	assert_float(k.z).is_less(0.0)
	assert_float(absf(k.z)).is_greater(absf(k.x) * 0.5)
	# once a swing: the same cut again does nothing more
	var hp1: float = em.hp[i]
	t._cut(yaw0, -0.3, 0.3, 2.6, 0.7, 1.0)
	assert_float(em.hp[i]).is_equal_approx(hp1, 0.0001)


# ---------------------------------------------------------------- the Hammer

func test_the_hammer_is_a_slower_weaker_pike_with_a_blast() -> void:
	var h: WeaponDef = Registry.weapon("hammer")
	var pk: WeaponDef = Registry.weapon("pike")
	assert_str(h.behavior).is_equal("Smasher")
	assert_float(float(h.base["damage"])).is_less(float(pk.base["damage"]))
	assert_float(float(h.base["cooldown"])).is_greater(float(pk.base["cooldown"]))
	assert_float(float(h.base["range"])).is_equal_approx(float(pk.base["range"]), 0.5)
	# its levels are reach, blast, damage and more hammers
	var stats := {}
	for lv in h.levels:
		for e: Effect in lv:
			stats[e.stat] = true
	for s in ["range", "area", "damage", "amount"]:
		assert_bool(stats.has(s)).override_failure_message("no " + s + " level").is_true()
	assert_str(h.evolves_into).is_equal("earthshaker")


func test_a_hammer_blast_throws_everything_outwards() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var at := Vector3(3.0, 0, 0)
	var ids: Array = []
	for k in range(4):
		var a := TAU * float(k) / 4.0
		var i := em.spawn("goblin", at + Vector3(cos(a), 0, sin(a)) * 0.9, null, 1.0, 50.0)
		em.state[i] = EnemyManager.STATE_MOVE
		ids.append(i)
	em._rebuild_grid()
	var s: Smasher = _behaviour(Smasher.new(), g, "hammer")
	s._impact(at, 1.6)
	for i: int in ids:
		var out: Vector3 = em.pos[i] - at
		out.y = 0.0
		assert_float(em.kb[i].normalized().dot(out.normalized())).override_failure_message("thrown inwards").is_greater(0.95)
		assert_float(em.hp[i]).is_less(em.max_hp[i])


func test_crowd_spots_find_each_crowd() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	for k in range(5):
		em.spawn("goblin", Vector3(3.0 + 0.2 * k, 0, 0), null, 1.0, 50.0)
	for k in range(3):
		em.spawn("goblin", Vector3(-3.0 - 0.2 * k, 0, 0), null, 1.0, 50.0)
	em._rebuild_grid()
	var s: Smasher = _behaviour(Smasher.new(), g, "hammer")
	var spots := s.crowd_spots(3, 5.0, 1.6)
	assert_int(spots.size()).is_equal(3)
	# the thicker crowd first, then the other, then round again
	assert_float((spots[0] as Vector3).x).is_greater(0.0)
	assert_float((spots[1] as Vector3).x).is_less(0.0)
	assert_float((spots[2] as Vector3).x).is_greater(0.0)


# ---------------------------------------------------------------- the Revolver

func test_the_revolver_is_the_drifters_alone() -> void:
	var r: WeaponDef = Registry.weapon("revolver")
	assert_str(r.hero).is_equal("drifter")
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_bool(Registry.unlocked_weapons().map(func(w): return w.id).has("revolver")).is_false()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_bool(Registry.unlocked_weapons().map(func(w): return w.id).has("revolver")).is_true()
	Run.end()


func test_the_revolver_is_a_heavier_faster_tommy_gun() -> void:
	var r: WeaponDef = Registry.weapon("revolver")
	var t: WeaponDef = Registry.weapon("tommy_gun")
	assert_int(int(r.base["amount"])).is_equal(1)
	assert_float(float(r.base["damage"])).is_greater(float(t.base["damage"]) * 4.0)
	assert_float(float(r.base["speed"])).is_equal_approx(float(t.base["speed"]) * 1.5, 0.01)
	assert_float(float(r.params["scatter_deg"])).is_less(3.0)
	# the bullet was the Tommy Gun's, smaller; pass 80 (lane TRAIL) slimmed the Tommy Gun's round to a thin hot tip as long
	# as the Revolver's, the trail behind it being the body: the Revolver's round is the stouter one now, never longer
	var rs: Node = (r.visual as PackedScene).instantiate()
	var ts: Node = (t.visual as PackedScene).instantiate()
	var rb: Vector3 = ((rs.get_node("Projectile") as MeshInstance3D).mesh as BoxMesh).size
	var tb: Vector3 = ((ts.get_node("Projectile") as MeshInstance3D).mesh as BoxMesh).size
	assert_float(rb.z).is_less_equal(tb.z + 0.001)
	assert_float(tb.x).is_less(rb.x)
	assert_object(rs.find_child("Drum", true, false)).override_failure_message("no turning cylinder").is_not_null()
	rs.free()
	ts.free()
	var gr: WeaponDef = Registry.weapon("golden_revolver")
	assert_str(gr.evolved_from).is_equal("revolver")
	assert_bool(gr.params.has("trace")).is_true()


func test_a_golden_line_hurts_what_walks_into_it() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var i := em.spawn("goblin", Vector3(5.0, 0, 0.1), null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	var w := WeaponInstance.new(Registry.weapon("golden_revolver"), 1)
	w.rebuild(Run.player_sheet, [])
	var tr := EnergyTraces.new()
	tr.game = g
	g.add_child(tr)
	var ln := tr.start(Vector3(0, 1, 0), w, 40.0)
	tr.follow(ln, Vector3(10, 1, 0))
	tr.seal(ln)
	var hp0: float = em.hp[i]
	tr._physics_process(0.11)
	assert_float(em.hp[i]).is_less(hp0)
	# a creature well off the line is not touched
	var j := em.spawn("goblin", Vector3(5.0, 0, 4.0), null, 1.0, 50.0)
	em._rebuild_grid()
	var hj: float = em.hp[j]
	tr._physics_process(0.11)
	assert_float(em.hp[j]).is_equal_approx(hj, 0.0001)
	# and the line is gone after its seconds
	for k in range(40):
		tr._physics_process(0.1)
	assert_int(tr.lines.size()).is_equal(0)


# ---------------------------------------------------------------- the Gravity Gun

func test_the_gravity_gun_leaves_bosses_elites_and_specials_alone() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var gob := em.spawn("goblin", Vector3(2, 0, 0))
	assert_bool(em.grabbable(gob)).is_true()
	for id in ["rocketeer", "harpoon_troglodyte", "dune_scorpion"]:
		if Registry.enemy(id) == null:
			continue
		var i := em.spawn(id, Vector3(4, 0, 0))
		assert_bool(em.grabbable(i)).override_failure_message(id + " can be grabbed").is_false()
	var boss := em.spawn("tumbleweed_king", Vector3(-6, 0, 0))
	assert_bool(em.grabbable(boss)).is_false()
	var mods: Array = Registry.elites_list()
	if not mods.is_empty():
		var modded := em.spawn("goblin", Vector3(0, 0, 5), mods[0])
		assert_bool(em.grabbable(modded)).is_false()


func test_nothing_held_dies_until_it_lands() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var i := em.spawn("goblin", Vector3(2, 0, 0))
	em.state[i] = EnemyManager.STATE_MOVE
	em.grab(i)
	em._rebuild_grid()
	assert_bool(em.indices_in_radius(Vector3(2, 0, 0), 1.0).has(i)).is_false()
	assert_bool(em.damage(i, 99999.0, "gravity_gun")).is_false()
	assert_int(em.alive[i]).is_equal(1)
	em.place_held(i, Vector3(3, 2.0, 0))
	assert_float(em.lift_h[i]).is_greater(1.5)
	em.release(i)
	assert_float(em.lift_h[i]).is_equal(0.0)
	assert_bool(em.damage(i, 99999.0, "gravity_gun")).is_true()


func test_a_throw_leads_a_pack_walking_in() -> void:
	# pass 35b: eight goblins seven metres up the screen walking at the hero; the throw must come down where they will
	# be when it lands (ahead of where they stand now), on the pack, not behind it
	var g := _setup()
	var em: EnemyManager = g.enemies
	var ids: Array = []
	for k in range(8):
		var i := em.spawn("goblin", Vector3(randf_range(-1.0, 1.0), 0, -7.0 + randf_range(-1.0, 1.0)), null, 1.0, 50.0)
		em.state[i] = EnemyManager.STATE_MOVE
		em.vel[i] = Vector3(0, 0, 2.5)
		ids.append(i)
	em._rebuild_grid()
	var gun: GravityGun = _behaviour(GravityGun.new(), g, "gravity_gun")
	var at := gun._lead_target(Vector3(0, 1.8, -1.5), Vector3.ZERO, 9.0, {}, [])
	assert_bool(at == Vector3.INF).is_false()
	var mid := Vector3.ZERO
	for i: int in ids:
		mid += em.pos[i]
	mid /= float(ids.size())
	# ahead of the pack's middle, towards the hero it is walking at
	assert_float(at.z).is_greater(mid.z + 0.5)
	# and still on it: where the pack will be, within the blast
	var landed := mid + Vector3(0, 0, 2.5 * 0.45)
	assert_float(Vector2(at.x - landed.x, at.z - landed.z).length()).is_less(gun._blast_r())
	# nobody at all: nowhere to throw
	em.kill_all(false)
	em._rebuild_grid()
	assert_bool(gun._lead_target(Vector3.ZERO, Vector3.ZERO, 9.0, {}, []) == Vector3.INF).is_true()


func test_the_revolvers_stand_upright() -> void:
	for id in ["revolver", "golden_revolver"]:
		var fam: Dictionary = Registry.weapon(id).params.get("familiar", {})
		assert_float(float(fam.get("roll", 0.0))).override_failure_message(id + " is laid on its side").is_equal(0.0)


func test_a_black_hole_drags_the_crowd_in() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var i := em.spawn("goblin", Vector3(2.5, 0, 0))
	em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	var d0: float = em.pos[i].length()
	em.drag_radius(Vector3.ZERO, 3.2, 5.5, 0.2)
	assert_float(em.pos[i].length()).is_less(d0 - 0.3)
	var s: WeaponDef = Registry.weapon("singularity")
	assert_str(s.evolved_from).is_equal("gravity_gun")
	assert_bool((s.params["gravity"] as Dictionary).has("black_hole")).is_true()


# ---------------------------------------------------------------- content

func test_every_new_weapon_has_its_three_paths() -> void:
	for id in ["hammer", "revolver", "gravity_gun"]:
		var kinds: Array = Registry.mutations_of(id).map(func(m: MutationDef) -> String: return m.mutation_kind)
		assert_bool(kinds.slice(0, 3) == ["element", "volume", "motion"]).override_failure_message(id + " " + str(kinds)).is_true()
		var w: WeaponDef = Registry.weapon(id)
		assert_object(Registry.weapon(w.evolves_into)).is_not_null()
		assert_object(w.visual).override_failure_message(id + " has no visual").is_not_null()
	for id in ["hammer", "earthshaker", "gravity_gun", "singularity", "revolver", "golden_revolver"]:
		assert_object(Registry.weapon(id).icon).override_failure_message(id + " has no icon").is_not_null()


func test_the_teleport_is_half_the_magnet() -> void:
	var t: StructureDef = Registry.structure("teleport")
	var m: StructureDef = Registry.structure("uber_magnet")
	assert_object(t).is_not_null()
	assert_str(t.effect_kind).is_equal("teleport")
	assert_float(t.interact_time).is_equal_approx(m.interact_time * 0.5, 0.001)
	assert_bool(t.params.get("portal") is Dictionary).is_true()
	assert_bool(ResourceLoader.exists("res://art/sprites/props/st_teleport.png")).is_true()
	assert_bool(ResourceLoader.exists("res://art/sprites/props/st_teleport_off.png")).is_true()
