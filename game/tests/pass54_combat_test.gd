extends GdUnitTestSuite

## Pass 54, lane C (combat and pickups): the gem merge that fuses only far gems, cluster by cluster, and gives coins their
## own cap (both gone in pass 61: nothing fuses, the pool grows); the half-size gems and three-quarter coins drawn under every painting (the stencil); the hero's shove on a
## landed hit (Player.hit_knock, a bite's own knockback, 1.6 times for big game, a shield's catch too, never an immune
## hit) and a hostile shot's share of its shooter's; the hostile damage multipliers; the ranged picks that keep to the
## screen (and the homing ones that do not); the waders' missing shadows and the ripples floated onto the water; and the
## perk hooks (Afterglow's bigger heals, Sunburn, Lingering Light).

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var missiles: Array = []
var blasts: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func enemy_missile(_i, _at, _speed, _turn, damage, _area, _soh = 0.0, _info = {}, _ms = {}) -> void:
	missiles.append(damage)
func elite_explosion(_at, _r, damage, _delay = 0.0, _kb = 0.0, _ff = 0.2, _info = {}) -> void:
	blasts.append(damage)
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var taken: Array = []
var infos: Array = []
var last_outcome := "hit"
func take_damage(a: float, _f: Vector3, i: Dictionary = {}) -> void:
	taken.append(a)
	infos.append(i)
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

## a camera rig that can say what is on the screen: a real Camera3D behind it (refresh_onscreen reads `camera`)
const FAKE_RIG := """extends Node
var camera: Camera3D
func on_screen(_p: Vector3, _m: float = 0.0) -> bool:
	return true
func pixels_per_metre() -> float:
	return 90.0
"""

## a map with a lake, as RedCanyon names it
const FAKE_LAKE_MAP := """extends MapBase
func lake_center() -> Vector2:
	return Vector2(10, 0)
func lake_radius() -> float:
	return 4.0
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Settings.ranged_on_screen = true


func after_test() -> void:
	Settings.ranged_on_screen = true
	Run.player_sheet.remove_source("test")
	Run.debug_clear_items()
	Run.end()


## A fake game with a fake hero at the origin (max HP 100), a plain map and a real EnemyManager wired to both.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	# no colour (no variance special) in these numbers
	em.colour_after_kills = 999999
	return {"g": g, "hero": hero, "em": em}


## A creature on its feet (past the spawn pop), standing where it was put.
func _creature(em: EnemyManager, id: String, at: Vector3, mod: EliteModDef = null) -> int:
	var i := em.spawn(id, at, mod)
	assert_int(i).override_failure_message("could not spawn " + id).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


## A PickupManager on the fake game above (its hero at the origin).
func _pickups(w: Dictionary) -> PickupManager:
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = w["g"]
	add_child(pm)
	(w["g"] as Node).set("pickups", pm)
	return pm


## The real hero, from his scene.
func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	p.global_position = Vector3.ZERO
	p._kb = Vector3.ZERO
	return p


func _alive_of(pm: PickupManager, coin: bool) -> Array:
	var out: Array = []
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1 and (pm.kind[i] == PickupManager.KIND_COIN) == coin:
			out.append(i)
	return out


# ---------------------------------------------------------------- 1. the vanishing gems
# Re-pinned in pass 61 (Garry: "The EXP gems still disappear. Now they combine into a big gem. I'd prefer that they don't
# disappear ever"): the merge, the coins' cap and the lost drop of a full pool are gone; nothing fuses and the pool
# doubles when it fills (pass61_pk_test has the rest).

func test_nothing_merges_the_gems_by_the_hero_and_the_far_ones_keep_their_place() -> void:
	var w := _world()
	var pm := _pickups(w)
	var near: Array = []
	for k in range(3):
		var a := TAU * float(k) / 3.0
		near.append(pm.spawn(PickupManager.KIND_GEM_S, Vector3(cos(a) * 2.5, 0, sin(a) * 2.5), 1.0))
	var near_at: Array = []
	for j: int in near:
		near_at.append(pm.pos[j])
	# 320 far gems: past the old MERGE_AT (300) nothing fuses
	for k in range(320):
		pm.spawn(PickupManager.KIND_GEM_S, Vector3(30.0, 0, 0), 1.0)
	for k in range(3):
		var j: int = near[k]
		assert_int(pm.alive[j]).is_equal(1)
		assert_float(pm.value[j]).is_equal(1.0)
		assert_vector(pm.pos[j]).is_equal(near_at[k])
	var far := _alive_of(pm, false)
	assert_int(far.size()).is_equal(323)
	for i: int in far:
		assert_int(pm.kind[i]).is_equal(PickupManager.KIND_GEM_S)
		assert_float(pm.value[i]).is_equal(1.0)


func test_coins_never_fuse_and_keep_their_gold() -> void:
	var w := _world()
	var pm := _pickups(w)
	for k in range(5):
		pm.spawn(PickupManager.KIND_GEM_S, Vector3(-30, 0, 0), 1.0)
	# past the old COIN_CAP (150): every coin keeps its own slot and its own gold
	for k in range(170):
		pm.spawn(PickupManager.KIND_COIN, Vector3(30, 0, 0), 2.0)
	assert_int(pm.count_coins()).is_equal(170)
	assert_int(pm.count_coins()).is_equal(_alive_of(pm, true).size())
	var gold := 0.0
	for i: int in _alive_of(pm, true):
		gold += pm.value[i]
		assert_float(pm.value[i]).is_equal(2.0)
	assert_float(gold).is_equal_approx(340.0, 0.001)
	var gems := _alive_of(pm, false)
	assert_int(gems.size()).is_equal(5)


func test_a_full_pool_grows_and_loses_nothing() -> void:
	var w := _world()
	var pm := _pickups(w)
	for k in range(PickupManager.MAX):
		pm.spawn(PickupManager.KIND_GEM_S, Vector3(1.0, 0, 0), 1.0)
	assert_int(pm.count).is_equal(PickupManager.MAX)
	var j := pm.spawn(PickupManager.KIND_GEM_S, Vector3(1.0, 0, 0), 1.0)
	assert_int(j).is_greater_equal(0)
	assert_int(pm.count).is_equal(PickupManager.MAX + 1)
	assert_int(pm.alive.size()).is_greater(PickupManager.MAX)


# ---------------------------------------------------------------- 2. size and draw order

func test_gems_are_half_size_and_coins_three_quarters() -> void:
	# re-pinned in pass 56 (Garry: "just 5% bigger"): the gems GEM_GROW times pass 54's sizes, drawn as octahedra
	# GEM_LOOK times as large (pass56_pk_test)
	assert_float(PickupManager.GEM_R[0]).is_equal_approx(0.11 * PickupManager.GEM_GROW, 0.0001)
	assert_float(PickupManager.GEM_R[1]).is_equal_approx(0.16 * PickupManager.GEM_GROW, 0.0001)
	assert_float(PickupManager.GEM_R[2]).is_equal_approx(0.225 * PickupManager.GEM_GROW, 0.0001)
	assert_float(PickupManager.COIN_R).is_equal_approx(0.21, 0.0001)
	assert_float(PickupManager.COIN_H).is_equal_approx(0.06, 0.0001)
	assert_float(PickupManager.VACUUM_R).is_equal_approx(0.38, 0.0001)
	assert_float(PickupManager.REST).is_equal_approx(0.22, 0.0001)
	assert_float(PickupManager.BOB).is_equal_approx(0.09, 0.0001)
	var pm := _pickups(_world())
	for k in range(3):
		var m: Mesh = (pm._mms[k] as MultiMesh).mesh
		assert_float(m.get_aabb().size.x).is_equal_approx(PickupManager.gem_radius(k) * 2.0, 0.0001)
	var c: CylinderMesh = (pm._mms[PickupManager.KIND_COIN] as MultiMesh).mesh
	assert_float(c.top_radius).is_equal_approx(0.21, 0.0001)
	assert_float(c.height).is_equal_approx(0.06, 0.0001)
	assert_float(PickupManager.coin_material().get_shader_parameter("radius")).is_equal_approx(0.21, 0.0001)


func test_gems_and_coins_are_drawn_under_every_painting() -> void:
	var pm := _pickups(_world())
	for c in pm.get_children():
		if not (c is MultiMeshInstance3D):
			continue
		# re-pinned in pass 56: the glints draw just after the gems, under the paintings too (pass56_pk_test)
		if (c as MultiMeshInstance3D).multimesh == pm._glint_mm:
			continue
		var mat: Material = (c as MultiMeshInstance3D).material_override
		assert_int(mat.render_priority).is_equal(PickupManager.PICKUP_PRIORITY)
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat
			assert_int(sm.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
			assert_int(sm.depth_draw_mode).is_equal(BaseMaterial3D.DEPTH_DRAW_DISABLED)
			assert_int(sm.stencil_mode).is_equal(BaseMaterial3D.STENCIL_MODE_CUSTOM)
			assert_int(sm.stencil_flags).is_equal(BaseMaterial3D.STENCIL_FLAG_READ)
			assert_int(sm.stencil_compare).is_equal(BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL)
			assert_int(sm.stencil_reference).is_equal(PickupManager.PAINTING_STENCIL)
		elif mat is ShaderMaterial:
			# pass 60: the gems draw through core/shaders/gem.gdshader (the charged look): the same rules in its source
			var gem_code: String = ((mat as ShaderMaterial).shader as Shader).code
			assert_str(gem_code).contains("depth_draw_never")
			assert_str(gem_code).contains("blend_mix")
			assert_str(gem_code).contains("stencil_mode read, compare_not_equal, %d;" % PickupManager.PAINTING_STENCIL)
	var coin: String = PickupManager.coin_material().shader.code
	assert_str(coin).contains("depth_draw_never")
	assert_str(coin).contains("stencil_mode read, compare_not_equal, %d;" % PickupManager.PAINTING_STENCIL)
	# every painting writes the value: the creatures, the hero (structures, the portal, power-ups, flowers) and the props
	for path in ["res://core/shaders/enemy_billboard.gdshader", "res://core/shaders/sprite_billboard.gdshader", "res://core/shaders/prop_billboard.gdshader"]:
		var code: String = (load(path) as Shader).code
		assert_str(code).override_failure_message(path + " writes no stencil").contains("stencil_mode write, compare_always, %d;" % PickupManager.PAINTING_STENCIL)
	# the order among the see-through: shadows, then gems and coins, then the hero's over pass
	assert_int(EnemyManager.SHADOW_PRIORITY).is_less(PickupManager.PICKUP_PRIORITY)
	assert_int(PickupManager.PICKUP_PRIORITY).is_less(BillboardSprite.OVER_PRIORITY)
	# the creatures need no second pass for it: main, then the occluded rim, nothing after
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, "skeleton", Vector3(3, 0, 0))
	var mat0: ShaderMaterial = em.types[0]["mat"]
	assert_object(mat0.next_pass).is_not_null()
	assert_object((mat0.next_pass as ShaderMaterial).next_pass).is_null()
	# the blob shadows draw first among the see-through, so a gem at a creature's feet is not darkened by its shadow
	assert_int(em._shadow_mmi.material_override.render_priority).is_equal(EnemyManager.SHADOW_PRIORITY)


# ---------------------------------------------------------------- 3. the hero's shove

func test_hit_knock_shoves_past_the_grace_caps_and_holds_the_stick() -> void:
	var p := _hero()
	# a shove a moment ago does not stop a landed hit's
	assert_bool(p.shove(Vector3(1, 0, 0))).is_true()
	p._kb = Vector3.ZERO
	p.hit_knock(Vector3(4, 3, 0))
	assert_vector(p._kb).is_equal_approx(Vector3(4, 0, 0), Vector3(0.0001, 0.0001, 0.0001))
	assert_float(p._stick_lock).is_equal_approx(Player.STICK_LOCK, 0.0001)
	# never past HIT_KNOCK_MAX in all
	p.hit_knock(Vector3(20, 0, 0))
	assert_float(p._kb.length()).is_equal_approx(Player.HIT_KNOCK_MAX, 0.0001)
	# a blast flinging him harder keeps its own speed
	p._kb = Vector3(12, 0, 0)
	p.hit_knock(Vector3(0, 0, 5))
	assert_float(p._kb.length()).is_equal_approx(12.0, 0.0001)
	# straight up is nothing; a dead hero is not shoved
	p._kb = Vector3.ZERO
	p.hit_knock(Vector3(0, 5, 0))
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	p.dead = true
	p.hit_knock(Vector3(3, 0, 0))
	assert_vector(p._kb).is_equal(Vector3.ZERO)


func test_a_landed_hit_shoves_by_its_number() -> void:
	var p := _hero()
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 4.0})
	assert_str(p.last_outcome).is_equal("hit")
	assert_vector(p._kb).is_equal_approx(Vector3(4, 0, 0), Vector3(0.0001, 0.0001, 0.0001))
	# a caller naming none: the old fixed shove
	p.invuln = 0.0
	p._kb = Vector3.ZERO
	p.take_damage(5.0, Vector3(0, 0, -2), {})
	assert_vector(p._kb).is_equal_approx(Vector3(0, 0, Player.HIT_KNOCK), Vector3(0.0001, 0.0001, 0.0001))
	# the ring of fire names 0: hurt, not shoved
	p.invuln = 0.0
	p._kb = Vector3.ZERO
	var before := p.hp
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 0.0})
	assert_float(p.hp).is_less(before)
	assert_vector(p._kb).is_equal(Vector3.ZERO)


func test_shield_hits_shove_too_and_immune_ones_do_not() -> void:
	var p := _hero()
	var hp0 := p.hp
	# the Energy Shield takes the hit: no health lost, still shoved
	p.shield_pts = 30.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 3.0})
	assert_str(p.last_outcome).is_equal("shield")
	assert_float(p.hp).is_equal(hp0)
	assert_float(p._kb.x).is_equal_approx(3.0, 0.0001)
	# the Shield power-up's bubble (pass 60, Garry: "Invincibility (shield) Power Up should null out the knockback from
	# enemies"): the hit is taken and nothing shoves him, however many land
	p.shield_pts = 0.0
	p.invuln = 0.0
	p._kb = Vector3.ZERO
	p.shield_t = 5.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 3.0})
	assert_str(p.last_outcome).is_equal("shield")
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 3.0})
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	assert_bool(p.knock_immune()).is_true()
	# an immune hit (the blink after a hit, god mode) never shoves
	p.shield_t = 0.0
	p._kb = Vector3.ZERO
	p.invuln = 1.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 3.0})
	assert_str(p.last_outcome).is_equal("immune")
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	p.invuln = 0.0
	p.god = true
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 3.0})
	assert_str(p.last_outcome).is_equal("immune")
	assert_vector(p._kb).is_equal(Vector3.ZERO)


func test_the_bite_carries_the_creatures_own_knockback() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := _creature(em, "skeleton", Vector3(0.3, 0, 0))
	var def: EnemyDef = Registry.enemy("skeleton")
	em._physics_process(DT)
	assert_int((hero.taken as Array).size()).is_equal(1)
	assert_float(float((hero.infos[0] as Dictionary).get("knock", -1.0))).is_equal_approx(def.hit_knockback(), 0.0001)
	# every creature has a number of its own now, from its data
	assert_float(def.knockback).is_greater(0.0)
	# big game shoves 1.6 times as hard: a boss, an Elite by its kind, a creature wearing an elite modifier
	em.boss_index = i
	assert_float(em.bite_knock(i)).is_equal_approx(def.hit_knockback() * EnemyManager.BIG_KNOCK, 0.0001)
	em.boss_index = -1
	assert_float(em.bite_knock(i)).is_equal_approx(def.hit_knockback(), 0.0001)
	var e := _creature(em, "skeleton", Vector3(-8, 0, 0), Registry.elites_list()[0])
	assert_float(em.bite_knock(e)).is_equal_approx(def.hit_knockback() * 1.6, 0.0001)
	var s := _creature(em, "dune_scorpion", Vector3(8, 0, 8))
	var sdef: EnemyDef = Registry.enemy("dune_scorpion")
	assert_float(em.bite_knock(s)).is_equal_approx(sdef.hit_knockback() * 1.6, 0.0001)
	# no creature, no shove
	assert_float(em.bite_knock(-1)).is_equal(0.0)


func test_a_shot_without_weight_shoves_by_its_shooters_bite() -> void:
	var def: EnemyDef = Registry.enemy("spit_cactus")
	assert_float(ProjectileManager.shot_knock({"id": "spit_cactus"})).is_equal_approx(0.7 * def.hit_knockback(), 0.0001)
	# an unknown shooter leaves the hero's own default
	assert_float(ProjectileManager.shot_knock({})).is_equal(-1.0)
	var info := {"id": "spit_cactus"}
	ProjectileManager.put_shot_knock(info)
	assert_float(float(info["knock"])).is_equal_approx(0.7 * def.hit_knockback(), 0.0001)
	var none := {}
	ProjectileManager.put_shot_knock(none)
	assert_bool(none.has("knock")).is_false()
	# a silk line pulls: no shove
	var silk := {"id": "spit_cactus"}
	ProjectileManager.put_shot_knock(silk, true)
	assert_float(float(silk["knock"])).is_equal(0.0)


# ---------------------------------------------------------------- 4. the hostile multipliers

func test_every_hostile_damage_takes_the_timelines_multipliers() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	# the defaults are 1 (the arena, a tool)
	assert_float(em.creature_damage_mult).is_equal(1.0)
	assert_float(em.damage_time_mult).is_equal(1.0)
	em.creature_damage_mult = 1.25
	em.damage_time_mult = 1.2
	assert_float(em.hostile_mult()).is_equal_approx(1.5, 0.0001)
	# the bite (the spawn's damage)
	var i := _creature(em, "skeleton", Vector3(6, 0, 0))
	assert_float(em.dmg[i]).is_equal_approx(Registry.enemy("skeleton").damage * 1.5, 0.0001)
	# the rocketeer's rocket
	var r := _creature(em, "rocketeer", Vector3(-6, 0, 0))
	var rdef: EnemyDef = Registry.enemy("rocketeer")
	em._fire_artillery(r, rdef, Vector3.ZERO)
	assert_float(float(g.missiles[0])).is_equal_approx(float((rdef.artillery["missile"] as Dictionary)["damage"]) * 1.5, 0.0001)
	# the horned toad's death burst
	var t := _creature(em, "horned_toad", Vector3(0, 0, 9))
	var tdef: EnemyDef = Registry.enemy("horned_toad")
	em._die(t, "")
	assert_float(float(g.blasts[0])).is_equal_approx(float(tdef.death_burst["damage"]) * 1.5, 0.0001)
	# a walking bomb
	var c := _creature(em, "sand_crab", Vector3(0, 0, -9))
	var cdef: EnemyDef = Registry.enemy("sand_crab")
	em._blow_up(c, cdef)
	assert_float(float(g.blasts[1])).is_equal_approx(float(cdef.kamikaze["damage"]) * 1.5, 0.0001)
	# and the bite itself lands at that number
	var hero: Node3D = w["hero"]
	var b := _creature(em, "skeleton", Vector3(0.3, 0, 0))
	em._physics_process(DT)
	assert_bool((hero.taken as Array).has(em.dmg[b])).is_true()


# ---------------------------------------------------------------- 5. on-screen targeting

func test_ranged_picks_keep_to_the_screen_unless_told_otherwise() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, "skeleton", Vector3(4, 0, 0))
	em._rebuild_grid()
	# a fresh spawn counts as on the screen
	assert_int(em.onscreen[i]).is_equal(1)
	assert_int(em.nearest_index(Vector3.ZERO, 20.0)).is_equal(i)
	# everything off the screen: the ranged picks find nothing
	em.onscreen.fill(0)
	assert_int(em.nearest_index(Vector3.ZERO, 20.0)).is_equal(-1)
	assert_int(em.priority_index(Vector3.ZERO, 20.0)).is_equal(-1)
	assert_int(em.random_in_range(Vector3.ZERO, 20.0)).is_equal(-1)
	assert_vector(em.densest_point(Vector3.ZERO, 20.0)).is_equal(Vector3.INF)
	assert_bool(em.screen_ok(i)).is_false()
	# ... while a homing pick (any_screen) still does, and the hit tests are never filtered
	assert_int(em.nearest_index(Vector3.ZERO, 20.0, "", true)).is_equal(i)
	assert_int(em.priority_index(Vector3.ZERO, 20.0, "", true)).is_equal(i)
	assert_int(em.random_in_range(Vector3.ZERO, 20.0, [], "", true)).is_equal(i)
	assert_vector(em.densest_point(Vector3.ZERO, 20.0, "", [], 0.0, true)).is_equal(em.pos[i])
	assert_bool(em.screen_ok(i, true)).is_true()
	assert_bool(em.indices_in_radius(Vector3.ZERO, 20.0).has(i)).is_true()
	# the Settings switch (debug panel) turns the rule off
	Settings.ranged_on_screen = false
	assert_int(em.nearest_index(Vector3.ZERO, 20.0)).is_equal(i)
	Settings.ranged_on_screen = true
	assert_int(em.nearest_index(Vector3.ZERO, 20.0)).is_equal(-1)
	# and so does the tools' own switch
	em.screen_filter_on = false
	assert_int(em.nearest_index(Vector3.ZERO, 20.0)).is_equal(i)


func test_onscreen_follows_the_camera() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var front := _creature(em, "skeleton", Vector3(0, 0, 0))
	var behind := _creature(em, "skeleton", Vector3(0, 0, 60))
	var aside := _creature(em, "skeleton", Vector3(400, 0, 0))
	# no camera that can say (a stand-in, a tool): everything counts as on the screen
	em.onscreen.fill(0)
	em.refresh_onscreen()
	assert_int(em.onscreen[behind]).is_equal(1)
	# a real camera high over the origin looking down at it
	var rig: Node = auto_free(Node.new())
	rig.set_script(_script(FAKE_RIG))
	add_child(rig)
	var cam := Camera3D.new()
	rig.add_child(cam)
	cam.look_at_from_position(Vector3(0, 20, 15), Vector3.ZERO)
	rig.set("camera", cam)
	g.camera = rig
	em.refresh_onscreen()
	assert_int(em.onscreen[front]).is_equal(1)
	assert_int(em.onscreen[behind]).is_equal(0)
	assert_int(em.onscreen[aside]).is_equal(0)
	# by halves: parity 0 refreshes the even slots only
	em.onscreen.fill(1)
	em.refresh_onscreen(0)
	for k: int in [front, behind, aside]:
		if (k & 1) == 1:
			assert_int(em.onscreen[k]).is_equal(1)
	# the rig's own test answers yes without a camera
	var plain := CameraRig.new()
	assert_bool(plain.on_screen(Vector3(9999, 0, 0), 90.0)).is_true()
	assert_float(plain.pixels_per_metre()).is_equal(90.0)
	plain.free()


func test_the_on_screen_setting_is_saved() -> void:
	var d: Dictionary = Settings.to_dict()
	assert_bool(d.has("ranged_on_screen")).is_true()
	assert_bool(bool(d["ranged_on_screen"])).is_true()
	Settings.from_dict({"ranged_on_screen": false})
	assert_bool(Settings.ranged_on_screen).is_false()
	Settings.from_dict({"ranged_on_screen": true})
	assert_bool(Settings.ranged_on_screen).is_true()


# ---------------------------------------------------------------- 6. water

func test_a_wading_creature_casts_no_shadow() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var wet := _creature(em, "skeleton", Vector3(10, 0, 0))
	var dry := _creature(em, "skeleton", Vector3(-10, 0, 0))
	# no lake, never in it
	assert_bool(em.in_lake(em.pos[wet])).is_false()
	em._render()
	assert_int(em._shadow_mm.visible_instance_count).is_equal(2)
	# a lake of 4 m at (10, 0): the edge is the map's in_water edge, 1.02 of the radius
	em.set_lake(Vector2(10, 0), 4.0)
	assert_bool(em.in_lake(em.pos[wet])).is_true()
	assert_bool(em.in_lake(em.pos[dry])).is_false()
	assert_bool(em.in_lake(Vector3(14.05, 0, 0))).is_true()
	assert_bool(em.in_lake(Vector3(14.1, 0, 0))).is_false()
	em._render()
	assert_int(em._shadow_mm.visible_instance_count).is_equal(1)
	# read off the map when it names its lake
	var lm := MapBase.new()
	lm.set_script(_script(FAKE_LAKE_MAP))
	(w["g"] as Node).add_child(lm)
	(w["g"] as Node).set("map", lm)
	em._lake_map = 0
	em._lake_r2 = 0.0
	assert_bool(em._lake_refresh()).is_true()
	assert_bool(em.in_lake(Vector3(10, 0, 1))).is_true()
	assert_bool(em.in_lake(Vector3(0, 0, 0))).is_false()


func test_a_ring_can_float_over_the_water() -> void:
	var tg: Telegraphs = auto_free(Telegraphs.new())
	add_child(tg)
	tg.flash_ring(Vector3(1, 0, 2), 0.45, Color(0.9, 0.98, 1.0), 0.4, 0.3)
	var it: Dictionary = tg._items.back()
	assert_float(float(it.get("lift", 0.0))).is_equal_approx(0.3, 0.0001)
	assert_float(Telegraphs._lift_basis(it).y.y).is_equal_approx(1.3, 0.0001)
	# a mark on the sand keeps the plain basis
	tg.flash_ring(Vector3(1, 0, 2), 0.45, Color(1, 1, 1))
	var plain: Dictionary = tg._items.back()
	assert_bool(plain.has("lift")).is_false()
	assert_bool(Telegraphs._lift_basis(plain) == Basis()).is_true()
	# a filled ring floats its disc too
	tg.ring(Vector3.ZERO, 1.0, 0.5, Color(1, 1, 1), true, 0.25)
	assert_float(float((tg._items.back() as Dictionary).get("lift", 0.0))).is_equal_approx(0.25, 0.0001)
	# the mark shader reads the lift off the basis
	assert_str((load("res://core/shaders/ground_mark.gdshader") as Shader).code).contains("MODEL_MATRIX[1].y - 1.0")


# ---------------------------------------------------------------- 7. the perk hooks

func test_afterglow_makes_every_heal_bigger() -> void:
	var p := _hero()
	p.hp = 10.0
	p.heal(10.0)
	assert_float(p.hp).is_equal_approx(20.0, 0.0001)
	assert_bool(Run.add_perk("afterglow")).is_true()
	p.refresh_stats()
	assert_float(p.heal_mult()).is_equal_approx(1.4, 0.0001)
	p.hp = 10.0
	p.heal(10.0)
	assert_float(p.hp).is_equal_approx(24.0, 0.0001)
	# her regen too
	var e := Effect.new()
	e.stat = "regen"
	e.op = "add"
	e.value = 2.0
	e.target = "player"
	Run.player_sheet.add_effect(e, "test")
	p.hp = 10.0
	p.regen_hold = 0.0
	p._tick_regen(1.0)
	assert_float(p.hp).is_equal_approx(10.0 + 2.0 * 1.4, 0.001)


func test_sunburn_and_lingering_light() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, "skeleton", Vector3(6, 0, 0))
	em.hp[i] = 1000.0
	em.max_hp[i] = 1000.0
	em.dr[i] = 0.0
	em.damage(i, 10.0, "peashooter")
	assert_float(em.hp[i]).is_equal_approx(990.0, 0.001)
	assert_bool(Run.add_perk("sunburn")).is_true()
	# not burning, not poisoned: as before
	em.damage(i, 10.0, "peashooter")
	assert_float(em.hp[i]).is_equal_approx(980.0, 0.001)
	em.poison(i, "peashooter", 1.0, 1, 5.0)
	em.damage(i, 10.0, "peashooter")
	assert_float(em.hp[i]).is_equal_approx(968.0, 0.001)
	# what is not hers (no weapon, the revive's tenth) takes nothing more
	em.damage(i, 10.0, "")
	assert_float(em.hp[i]).is_equal_approx(958.0, 0.001)
	em.damage(i, 10.0, "revive")
	assert_float(em.hp[i]).is_equal_approx(948.0, 0.001)
	# a burning one too
	var f := _creature(em, "skeleton", Vector3(-6, 0, 0))
	em.hp[f] = 1000.0
	em.dr[f] = 0.0
	em.ignite(f, "peashooter", 1.0, 3.0, 0.0)
	em.damage(f, 10.0, "peashooter")
	assert_float(em.hp[f]).is_equal_approx(988.0, 0.001)
	# Lingering Light: burns and poison last 30% longer and tick 30% harder
	var l := _creature(em, "skeleton", Vector3(0, 0, 8))
	em.hp[l] = 1000.0
	em.dr[l] = 0.0
	em.poison(l, "venom", 2.0, 1, 4.0)
	assert_float(float((em.poison_src[l] as Dictionary)["venom"]["t"])).is_equal_approx(4.0, 0.0001)
	Run.perks.erase("sunburn")
	assert_bool(Run.add_perk("lingering_light")).is_true()
	em.poison(l, "venom", 2.0, 1, 4.0)
	assert_float(float((em.poison_src[l] as Dictionary)["venom"]["t"])).is_equal_approx(5.2, 0.0001)
	em.ignite(l, "flame", 1.0, 2.0, 0.0)
	assert_float(float((em.fire_src[l] as Dictionary)["flame"]["t"])).is_equal_approx(2.6, 0.0001)
	var before: float = em.hp[l]
	em.poison_tick[l] = 0.001
	em._tick_poison(l, 0.01)
	assert_float(before - em.hp[l]).is_equal_approx(2.0 * 1.3, 0.001)
