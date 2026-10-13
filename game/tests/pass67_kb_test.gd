extends GdUnitTestSuite

## Pass 67, lane K (Garry: "The Hammer Giant should take 1/3 of the knockback it currently does; add a stat for how
## much knockback enemies can resist"). `knockback_resist` (creature JSON, 0..1, default 0; BALANCING §1) is the share
## of every shove from the hero's side a creature shrugs off: a hit's kb_force push, a blast's throw_radius (hostile
## throws too), the pull (Lasso) and Buck's Ram are multiplied by (1 - resist) on top of the mass rule
## (kb_force / max(size, 0.8)) and the boss's own 0.15, which it never replaces. The Hammer Giant carries 0.67 (a third of
## its old push). A roster row overrides it as `stats.knockback_resist`. The Singularity's drag, lifts, bounces, the
## twister's fling and the charger's side-shove are not knockbacks and keep their own rules.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
var hits := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
"""

const DT := 1.0 / 60.0
const SKEL := "res://content/enemies/skeleton/"


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at` with the real crowd.
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


## A creature on the sand, standing still, at its JSON size (no variance), with a roster row's `stats` on it when given
## (the stats make a type of their own, as a row's do in a run: Registry.enemy_with -> EnemyDef.with_overrides).
func _put(em: EnemyManager, id: String, at: Vector3, stats: Dictionary = {}) -> int:
	var i := em.spawn(id, at, null, 1.0, 1.0, "", stats)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.size[i] = Registry.enemy(id).size
	em.radius[i] = Registry.enemy(id).radius
	em.vel[i] = Vector3.ZERO
	em.kb[i] = Vector3.ZERO
	em.squash[i] = 1.0
	return i


# ---------------------------------------------------------------- the field

func test_the_json_key_defaults_to_0_and_is_clamped_to_a_share() -> void:
	var none := JsonContent.build("enemies", {"id": "k67_none", "damage": 4}, SKEL) as EnemyDef
	assert_float(none.knockback_resist).is_equal(0.0)
	var some := JsonContent.build("enemies", {"id": "k67_some", "damage": 4, "knockback_resist": 0.67}, SKEL) as EnemyDef
	assert_float(some.knockback_resist).is_equal_approx(0.67, 0.0001)
	# a share above 1 would flip the push towards the hero, a negative one would pull harder than the hit
	var over := JsonContent.build("enemies", {"id": "k67_over", "knockback_resist": 1.5}, SKEL) as EnemyDef
	assert_float(over.knockback_resist).is_equal(1.0)
	var under := JsonContent.build("enemies", {"id": "k67_under", "knockback_resist": -1}, SKEL) as EnemyDef
	assert_float(under.knockback_resist).is_equal(0.0)
	# it is not the bite's shove on the hero: that one reads as before
	assert_float(some.knockback).is_equal(0.0)
	assert_float(some.hit_knockback()).is_equal_approx(3.4, 0.0001)


func test_the_hammer_giant_shrugs_off_two_thirds() -> void:
	# from the Registry (the .tres import_json wrote; a stale .tres would read 0), not the JSON alone
	var g: EnemyDef = Registry.enemy("hammer_giant")
	assert_float(g.knockback_resist).is_equal_approx(0.67, 0.0001)
	# the shove its bite gives the hero is as it was
	assert_float(g.knockback).is_equal_approx(6.36, 0.0001)
	# written right after the knockback in its JSON, never between the damage and the knockback (pass54_waves_test pins
	# `knockback` right after `damage`)
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/hammer_giant/hammer_giant.json"))
	var keys: Array = j.keys()
	assert_int(keys.find("knockback")).is_equal(keys.find("damage") + 1)
	assert_int(keys.find("knockback_resist")).is_equal(keys.find("knockback") + 1)
	assert_float(float(j["knockback_resist"])).is_equal_approx(0.67, 0.0001)


func test_a_rows_stats_set_the_resist_and_the_copies_keep_it() -> void:
	var d := EnemyDef.new()
	d.id = "k67_src"
	d.knockback_resist = 0.67
	# a row that says nothing of it keeps the creature's own
	assert_float(d.with_overrides({"hp": 5}).knockback_resist).is_equal_approx(0.67, 0.0001)
	assert_float(d.with_overrides({"knockback_resist": 0.25}).knockback_resist).is_equal_approx(0.25, 0.0001)
	# clamped like the JSON's
	assert_float(d.with_overrides({"knockback_resist": 3}).knockback_resist).is_equal(1.0)
	assert_float(d.with_overrides({"knockback_resist": -2}).knockback_resist).is_equal(0.0)
	# the bite's multiplier is another thing and leaves it alone
	assert_float(d.with_overrides({"knockback_mult": 2.0}).knockback_resist).is_equal_approx(0.67, 0.0001)
	# the source keeps its own
	assert_float(d.knockback_resist).is_equal_approx(0.67, 0.0001)
	# another look of the same creature is as heavy
	d.variant = "K-A"
	d.variants = {"K-A": {}, "K-B": {}}
	var look := d.variant_def("K-B")
	assert_object(look).is_not_same(d)
	assert_float(look.knockback_resist).is_equal_approx(0.67, 0.0001)


# ---------------------------------------------------------------- the manager

func test_register_type_keeps_one_share_taken_per_type() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _put(em, "skeleton", Vector3(2, 0, 0))
	var b := _put(em, "goblin", Vector3(-2, 0, 0))
	var c := _put(em, "skeleton", Vector3(0, 0, 2), {"knockback_resist": 0.5})
	var g := _put(em, "hammer_giant", Vector3(0, 0, -6))
	# a row's stats make a type of their own; a second plain skeleton adds none
	var a2 := _put(em, "skeleton", Vector3(3, 0, 0))
	assert_int(em.type_idx[a2]).is_equal(em.type_idx[a])
	assert_int(em.type_idx[c]).is_not_equal(em.type_idx[a])
	assert_int(em._t_kbt.size()).is_equal(em.types.size())
	assert_int(em._t_kbt.size()).is_equal(em._t_ccd.size())
	assert_float(em._t_kbt[em.type_idx[a]]).is_equal_approx(1.0, 0.0001)
	assert_float(em._t_kbt[em.type_idx[b]]).is_equal_approx(1.0, 0.0001)
	assert_float(em._t_kbt[em.type_idx[c]]).is_equal_approx(0.5, 0.0001)
	assert_float(em._t_kbt[em.type_idx[g]]).is_equal_approx(0.33, 0.0001)
	# registering a type it has appends nothing
	var n := em.types.size()
	em.register_type(em.types[em.type_idx[a]]["def"])
	assert_int(em.types.size()).is_equal(n)
	assert_int(em._t_kbt.size()).is_equal(n)


func test_a_hit_pushes_by_the_force_over_the_mass_times_the_share_taken() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var plain := _put(em, "skeleton", Vector3(0, 0, 6))
	var half := _put(em, "skeleton", Vector3(0, 0, 9), {"knockback_resist": 0.5})
	var wall := _put(em, "skeleton", Vector3(0, 0, 12), {"knockback_resist": 1.0})
	em.size[half] = em.size[plain]
	em.size[wall] = em.size[plain]
	var mass := maxf(em.size[plain], 0.8)
	# the health before (a variance special may have rolled on one of them: twice the skeleton's HP), so the hit is
	# measured as what it took, not as what is left
	var hp0: Array = [em.hp[plain], em.hp[half], em.hp[wall]]
	em.damage(plain, 1.0, "", Vector3(1, 0, 0), 5.0)
	em.damage(half, 1.0, "", Vector3(1, 0, 0), 5.0)
	em.damage(wall, 1.0, "", Vector3(1, 0, 0), 5.0)
	# the mass rule as it was (pass47_combat_test), then the share
	# pass 72: times the map's share of the hero's pushes (hero_knockback_mult)
	assert_float(em.kb[plain].length()).is_equal_approx(5.0 / mass * em.hero_knock_mult(), 0.001)
	assert_float(em.kb[half].length()).is_equal_approx(5.0 / mass * 0.5 * em.hero_knock_mult(), 0.001)
	assert_float(em.kb[half].x).is_greater(0.0)
	assert_bool(em.kb[wall].is_zero_approx()).is_true()
	# the hit itself is whole: a resist is not a damage reduction
	assert_float(float(hp0[0]) - em.hp[plain]).is_equal_approx(1.0, 0.001)
	assert_float(float(hp0[1]) - em.hp[half]).is_equal_approx(1.0, 0.001)
	assert_float(float(hp0[2]) - em.hp[wall]).is_equal_approx(1.0, 0.001)


func test_the_giant_takes_a_third_of_its_old_push() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g := _put(em, "hammer_giant", Vector3(0, 0, 6))
	var mass := maxf(em.size[g], 0.8)
	assert_float(mass).is_equal_approx(3.4, 0.0001)
	em.damage(g, 1.0, "", Vector3(1, 0, 0), 10.0)
	# F / 3.4 before (its size was its only weight); 0.67 shrugged off now
	assert_float(em.kb[g].length()).is_equal_approx(10.0 / mass * 0.33 * em.hero_knock_mult(), 0.001)  # pass 72: the map's share of the hero's pushes (hero_knockback_mult)


func test_the_boss_factor_is_its_own_and_composes_with_a_resist() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var plain := _put(em, "goblin", Vector3(0, 0, 6))
	var half := _put(em, "goblin", Vector3(0, 0, 9), {"knockback_resist": 0.5})
	em.size[half] = em.size[plain]
	var mass := maxf(em.size[plain], 0.8)
	# the boss barely budges, as it did (its 0.15; every boss JSON leaves the resist at 0)
	em.boss_index = plain
	em.damage(plain, 1.0, "", Vector3(1, 0, 0), 20.0)
	assert_float(em.kb[plain].length()).is_equal_approx(20.0 / mass * 0.15 * em.hero_knock_mult(), 0.001)  # pass 72: the map's share of the hero's pushes (hero_knockback_mult)
	# a resist on the boss multiplies the 0.15, it never replaces it
	em.boss_index = half
	em.damage(half, 1.0, "", Vector3(1, 0, 0), 20.0)
	assert_float(em.kb[half].length()).is_equal_approx(20.0 / mass * 0.15 * 0.5 * em.hero_knock_mult(), 0.001)
	em.boss_index = -1


func test_a_blast_throws_a_resisting_creature_by_its_share_and_a_wall_not_at_all() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	var plain := _put(em, "goblin", Vector3(1.0, 0, 0))
	var half := _put(em, "goblin", Vector3(-1.0, 0, 0), {"knockback_resist": 0.5})
	var wall := _put(em, "goblin", Vector3(0, 0, 1.0), {"knockback_resist": 1.0})
	for i in [plain, half, wall]:
		em.size[i] = 1.2
	em._rebuild_grid()
	# the blast reaches all three (pass333's throw: the count is what it touched; each is squashed and flashed)
	assert_int(em.throw_radius(Vector3.ZERO, 4.5, 26.0)).is_equal(3)
	# force x the fall-off at 1 m of 4.5 / the mass, as it was; then the share (a hostile rocket's or boulder's throw
	# goes through the same function, so the giant stands through those too)
	var want := 26.0 * (1.0 - 0.5 * (1.0 / 4.5)) / 1.2
	assert_float(em.kb[plain].length()).is_equal_approx(want, 0.01)
	assert_float(em.kb[plain].x).is_greater(0.0)
	assert_float(em.kb[half].length()).is_equal_approx(want * 0.5, 0.01)
	assert_float(em.kb[half].x).is_less(0.0)
	assert_bool(em.kb[wall].is_zero_approx()).is_true()
	assert_float(em.squash[wall]).is_equal_approx(0.6, 0.001)


func test_the_pull_tows_a_resisting_creature_by_its_share() -> void:
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	assert_object(Run.add_weapon(Registry.weapon("branding_iron"), 1)).is_not_null()
	assert_bool(Run.add_mutation("lasso", true)).is_true()
	var pl: float = Run.weapon_instance("branding_iron").stat("pull", 0.0)
	assert_float(pl).is_greater(0.0)
	var plain := _put(em, "skeleton", Vector3(3, 0, 0))
	var half := _put(em, "skeleton", Vector3(-3, 0, 0), {"knockback_resist": 0.5})
	em.damage(plain, 1.0, "branding_iron")
	em.damage(half, 1.0, "branding_iron")
	# towed towards the hero: the whole pull, and half of it
	assert_float(em.kb[plain].x).is_equal_approx(-pl, 0.001)
	assert_float(em.kb[half].x).is_equal_approx(pl * 0.5, 0.001)
	assert_float(em.kb[half].z).is_equal_approx(0.0, 0.001)


func test_the_ram_shoves_a_resisting_creature_by_its_share_and_buck_is_not_touched() -> void:
	Run.end()
	Run.start(Registry.character("buck"), Registry.map("red_canyon"))
	assert_bool(Run.add_perk("ram")).is_true()
	Run.momentum = 1.0
	var shove := Run.perk_param("ram", "shove", 0.0)
	assert_float(shove).is_greater(0.0)
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var hero: Node = w["hero"]
	var r: float = Registry.enemy("skeleton").radius
	# one at each side of him, inside the bite's reach (radius + 0.45), neither about to die of the spikes
	var plain := _put(em, "skeleton", Vector3(r + 0.3, 0, 0))
	var half := _put(em, "skeleton", Vector3(-(r + 0.3), 0, 0), {"knockback_resist": 0.5})
	for i in [plain, half]:
		em.hp[i] = 1000.0
		em.max_hp[i] = 1000.0
		em.contact_cd[i] = 0.0
	em._physics_process(DT)
	# the Ram took both bites' place (he is not touched) and shoved each away from him: the whole shove, and half of it
	assert_int(hero.hits).is_equal(0)
	# pass 72: times the map's share of the hero's pushes (hero_knockback_mult)
	assert_float(em.kb[plain].x).is_equal_approx(shove * em.hero_knock_mult(), 0.001)
	assert_float(em.kb[half].x).is_equal_approx(-shove * 0.5 * em.hero_knock_mult(), 0.001)
	# the spikes are a hit, not a shove: both take the same
	assert_float(em.hp[plain]).is_less(1000.0)
	assert_float(em.hp[half]).is_equal_approx(em.hp[plain], 0.001)


func test_the_singularitys_drag_is_not_a_knockback_and_ignores_the_resist() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	var plain := _put(em, "goblin", Vector3(3.0, 0, 0))
	var wall := _put(em, "goblin", Vector3(-3.0, 0, 0), {"knockback_resist": 1.0})
	em._rebuild_grid()
	em.drag_radius(Vector3.ZERO, 6.0, 4.0, 0.5)
	# both dragged in the same distance: the drag moves the body itself, and keeps its own rule (bosses and Elites a fifth)
	var moved := 3.0 - em.pos[plain].x
	assert_float(moved).is_greater(0.1)
	assert_float(em.pos[wall].x + 3.0).is_equal_approx(moved, 0.001)
