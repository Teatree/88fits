extends GdUnitTestSuite

## Pass 47, lane C1 (Garry's fifth list, the combat side). Ducktape's `debuff_duration` stretches every debuff the hero
## puts on a creature (burn, poison, slows and pins, Cauterize's mark) and nothing else (a knockback, a lift, a bounce,
## a twister, a hero's perk), once: a fire that jumps on and Blight's hand-on are not stretched again. Big Game Hunter's
## `elite_damage` lands on a boss, an Elite and an elite-modded creature only. Hot Sauce's `difficulty` brings more
## coloured creatures (the variance special, the Elite clocks) and pays for them: a gem of extra XP and, for a special,
## now and then a chest, no more than one a gap. The Dune Scorpion plays SC-D with its shadow tuned under its body (and
## its painting sunk onto the ground), the giant HG-A, the minion TM-C. The King's volley spokes reach as far as the
## tumbleweeds roll, and his wind-up plays at the standing pace however the crowd shoves him. Frag's grenade bursts
## into steel spikes that fly out past the blast. The Watchtower is gone, the turret's head turns before it fires, and
## its mutations hang nothing over the hero.

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
var lines: Array = []
var volleys: Array = []
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
func telegraph_line(_a, _b, c, _d, _e) -> void:
	lines.append(float(c))
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func tumbleweed_volley(at, first, count, speed, damage, life, knockback, lift, info) -> void:
	volleys.append({"count": count, "speed": speed, "life": life})
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
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

const FAKE_PICKUPS := """extends Node
var gems: Array = []
var chests := 0
func spawn(kind: int, _at: Vector3, v: float) -> int:
	gems.append({"kind": kind, "v": v})
	return gems.size() - 1
func spawn_chest(_at: Vector3, _boss: bool = false) -> void:
	chests += 1
func add_attractor(_p: Vector3, _r: float) -> void:
	pass
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd, shots, effects and ground marks and a pickup counter.
func _world(hero_at := Vector3(30, 0, 30)) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
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
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam, "pk": pk}


## A creature on its feet where it was put (tough, unless asked otherwise).
func _creature(em: EnemyManager, at: Vector3, id := "skeleton", hp_mult := 50.0, elite: EliteModDef = null) -> int:
	var i := em.spawn(id, at, elite, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


## The hero carries `value` of `stat` (pass 47's new numbers are Lane A's; an effect works before and after they land in
## StatSheet.PLAYER_DEFAULTS).
func _give(em: EnemyManager, stat: String, op: String, value: float) -> void:
	Run.player_sheet.add_effects([Effect.make(stat, op, value, "player")], "test " + stat)
	em.refresh_player_stats()


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


# ---------------------------------------------------------------- Ducktape

func test_ducktape_stretches_burn_poison_slows_pins_and_the_mark() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(0, 0, 0))
	var b := _creature(em, Vector3(6, 0, 0))
	# without it, as written
	em.poison(a, "x", 3.0, 1, 8.0)
	assert_float(float(em.poison_src[a]["x"]["t"])).is_equal_approx(8.0, 0.001)
	_give(em, "debuff_duration", "mul", 0.5)
	assert_float(em.debuff_mult()).is_equal_approx(1.5, 0.001)
	em.poison(b, "x", 3.0, 1, 8.0)
	assert_float(float(em.poison_src[b]["x"]["t"])).is_equal_approx(12.0, 0.001)
	em.ignite(b, "y", 4.0, 2.0, 0.0)
	assert_float(float(em.fire_src[b]["y"]["t"])).is_equal_approx(3.0, 0.001)
	# the item's own seconds are kept for a fire that jumps on (stretched once there, not again)
	assert_float(float(em.fire_src[b]["y"]["dur"])).is_equal_approx(2.0, 0.001)
	em.slow(b, 0.3, 2.0)
	assert_float(em.slow_t[b]).is_equal_approx(3.0, 0.001)
	# a pin is a slow of 1 (the Spear's Pinning Throw)
	em.slow(a, 1.0, 1.2)
	assert_float(em.slow_t[a]).is_equal_approx(1.8, 0.001)
	em._rebuild_grid()
	em.slow_t[a] = 0.0
	em.slow_radius(Vector3.ZERO, 1.0, 0.25, 1.0)
	assert_float(em.slow_t[a]).is_equal_approx(1.5, 0.001)
	# a hero's perk passes scaled = false (Serenade, Trail Dust)
	em.slow_t[a] = 0.0
	em.slow_radius(Vector3.ZERO, 1.0, 0.25, 1.0, false)
	assert_float(em.slow_t[a]).is_equal_approx(1.0, 0.001)


func test_ducktape_stretches_cauterizes_mark() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(0, 0, 0))
	assert_object(Run.add_weapon(Registry.weapon("branding_iron"), 1)).is_not_null()
	assert_bool(Run.add_mutation("cauterize", true)).is_true()
	_give(em, "debuff_duration", "mul", 1.0)
	em.damage(a, 1.0, "branding_iron")
	assert_float(em.mark_t[a]).is_equal_approx(6.0, 0.001)


func test_ducktape_leaves_throws_lifts_bounces_and_twisters_alone() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_give(em, "debuff_duration", "mul", 1.0)
	var a := _creature(em, Vector3(0, 0, 0))
	var b := _creature(em, Vector3(4, 0, 0))
	var c := _creature(em, Vector3(-4, 0, 0))
	assert_bool(em.bounce(a, 1.0, 0.6)).is_true()
	assert_float(em.lift_t[a]).is_equal_approx(0.6, 0.001)
	em.twist(b, 1.5, Vector3.ZERO)
	assert_float(em.spin_t[b]).is_equal_approx(1.5, 0.001)
	em._rebuild_grid()
	em.lift_radius(Vector3(-4, 0, 0), 1.0, 1.6)
	assert_float(em.lift_t[c]).is_equal_approx(1.6, 0.001)
	# a knockback is a push, not a clock
	var d := _creature(em, Vector3(0, 0, 8))
	em.damage(d, 1.0, "", Vector3(1, 0, 0), 5.0)
	assert_float(em.kb[d].length()).is_equal_approx(5.0 / maxf(em.size[d], 0.8), 0.01)


func test_a_weaponless_zone_is_a_perk_and_is_not_stretched() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	_give(em, "debuff_duration", "mul", 1.0)
	var a := _creature(em, Vector3(0, 0, 0))
	var b := _creature(em, Vector3(10, 0, 0))
	em._rebuild_grid()
	var perk := Zone.new()
	perk.setup(g, null, 1.0, 2.0, 0.0, 0.3, 0.25, Color.WHITE)
	g.add_child(perk)
	perk._process(0.01)
	assert_float(em.slow_t[a]).is_equal_approx(0.5, 0.001)
	var weap := Zone.new()
	weap.setup(g, _inst("zap_beam"), 1.0, 2.0, 0.0, 0.3, 0.25, Color.WHITE)
	weap.position = Vector3(10, 0, 0)
	g.add_child(weap)
	weap._process(0.01)
	assert_float(em.slow_t[b]).is_equal_approx(1.0, 0.001)


func test_ducktape_stretches_a_jumping_fire_and_blights_hand_on_once() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_give(em, "debuff_duration", "mul", 0.5)
	var a := _creature(em, Vector3(0, 0, 0))
	var b := _creature(em, Vector3(0.5, 0, 0))
	em._rebuild_grid()
	# a fire that jumps from a to b is the item's 2 s stretched once: 3 s, not 4.5
	em.ignite(a, "x", 1.0, 2.0, 1.0)
	em._tick_fire(a, EnemyManager.FIRE_TICK + 0.01)
	assert_bool((em.fire_src[b] as Dictionary).has("x")).is_true()
	assert_float(float(em.fire_src[b]["x"]["t"])).is_equal_approx(3.0, 0.001)
	# Blight hands on what is left of a poison, not that stretched again
	_give(em, "poison_pass", "add", 1.0)
	var c := _creature(em, Vector3(20, 0, 0), "skeleton", 1.0)
	var d := _creature(em, Vector3(21, 0, 0))
	em._rebuild_grid()
	em.poison(c, "p", 1.0, 1, 4.0)
	var left := float(em.poison_src[c]["p"]["t"])
	assert_float(left).is_equal_approx(6.0, 0.001)
	em.damage(c, 99999.0)
	assert_bool((em.poison_src[d] as Dictionary).has("p")).is_true()
	assert_float(float(em.poison_src[d]["p"]["t"])).is_equal_approx(left, 0.001)


# ---------------------------------------------------------------- Big Game Hunter

func test_big_game_hunter_hits_bosses_elites_and_modded_creatures_harder() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var plain := _creature(em, Vector3(0, 0, 0))
	var mod: EliteModDef = Registry.elites_list()[0]
	var modded := _creature(em, Vector3(4, 0, 0), "skeleton", 50.0, mod)
	var elite := _creature(em, Vector3(8, 0, 0), "dune_scorpion")
	var boss := em.spawn("tumbleweed_king", Vector3(-12, 0, 0))
	em.state[boss] = EnemyManager.STATE_MOVE
	_give(em, "elite_damage", "add", 0.5)
	for i: int in [plain, modded, elite, boss]:
		var before := em.hp[i]
		em.damage(i, 10.0)
		var want := 10.0 * (1.0 - em.dr[i]) * (1.0 if i == plain else 1.5)
		assert_float(before - em.hp[i]).override_failure_message("creature %d took %f" % [i, before - em.hp[i]]).is_equal_approx(want, 0.01)
	assert_bool(em.is_big_game(plain)).is_false()
	assert_bool(em.is_big_game(modded) and em.is_big_game(elite) and em.is_big_game(boss)).is_true()
	# the revive's flat tenth is not the hero's aim
	var e2 := _creature(em, Vector3(12, 0, 0), "dune_scorpion")
	var b2 := em.hp[e2]
	em.damage(e2, 10.0, "revive")
	assert_float(b2 - em.hp[e2]).is_equal_approx(10.0 * (1.0 - em.dr[e2]), 0.01)


# ---------------------------------------------------------------- Hot Sauce

## How many of `n` skeletons roll the variance special with the manager's dice seeded at `seed`.
func _specials(em: EnemyManager, n: int, seed: int) -> int:
	em._rng.seed = seed
	var count := 0
	for k in range(n):
		var i := em.spawn("skeleton", Vector3(float(k % 20) * 2.0, 0, float(k / 20) * 2.0))
		if i >= 0:
			count += em.vspecial[i]
			em._free(i)
	return count


func test_hot_sauce_brings_more_specials() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# colour from the first kill, as a director would set it (pass 71: a crowd without one spawns plain)
	em.colour_after_kills = 0
	var plain := _specials(em, 300, 4747)
	_give(em, "difficulty", "add", 1.0)
	var hot := _specials(em, 300, 4747)
	# the same dice: every special without it is one with it, and the chance is twice as high
	assert_int(hot).is_greater(plain)
	assert_int(hot).is_greater_equal(int(plain * 1.4))


func test_hot_sauce_speeds_the_coloured_elite_clocks() -> void:
	var wd := WaveDirector.new()
	add_child(auto_free(wd))
	wd.timeline = Registry.map("red_canyon").timeline
	assert_float(wd.elite_pace()).is_equal_approx(1.0, 0.0001)
	var every0 := wd._endless_elite_every()
	assert_float(wd.next_elite_at(100.0, 120.0)).is_equal_approx(220.0, 0.001)
	Run.player_sheet.add_effects([Effect.make("difficulty", "add", 1.0, "player")], "test")
	assert_float(wd.elite_pace()).is_equal_approx(1.5, 0.0001)
	assert_float(wd.next_elite_at(100.0, 120.0)).is_equal_approx(180.0, 0.001)
	assert_float(wd._endless_elite_every()).is_equal_approx(every0 / 1.5, 0.001)


func test_hot_sauce_pays_for_colour_and_keeps_the_chests_apart() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pk: Node = w["pk"]
	var def: EnemyDef = Registry.enemy("skeleton")
	var d: Dictionary = def.drops
	var xp: float = def.xp_mult * (float(d.get("small", 0.0)) + 5.0 * float(d.get("medium", 0.0)) + 25.0 * float(d.get("large", 0.0)))
	# no Hot Sauce: a special pays nothing extra
	var s0 := _creature(em, Vector3(0, 0, 0), "skeleton", 1.0)
	em.vspecial[s0] = 1
	em.damage(s0, 99999.0)
	assert_int((pk.gems as Array).size()).is_equal(0)
	assert_int(int(pk.chests)).is_equal(0)
	# difficulty 20: the chest chance is certain, so the gap is what keeps the second one away
	_give(em, "difficulty", "add", 20.0)
	var s1 := _creature(em, Vector3(2, 0, 0), "skeleton", 1.0)
	em.vspecial[s1] = 1
	# the bonus is a share of the creature's own XP (integration: xp_scale, a rolled special's `xp` included), so read it
	# before the creature goes
	var own: float = em.xp_scale[s1] / maxf(def.xp_mult, 0.0001) * xp
	em.damage(s1, 99999.0)
	assert_int((pk.gems as Array).size()).is_equal(1)
	assert_float(float(pk.gems[0]["v"])).is_equal_approx(own * EnemyManager.HOT_XP * 20.0, 0.01)
	assert_int(int(pk.chests)).is_equal(1)
	var s2 := _creature(em, Vector3(4, 0, 0), "skeleton", 1.0)
	em.vspecial[s2] = 1
	em.damage(s2, 99999.0)
	assert_int(int(pk.chests)).is_equal(1)
	# the gap passes on the manager's own clock
	for n in range(int(EnemyManager.HOT_CHEST_GAP / 0.5) + 2):
		em._physics_process(0.5)
	var s3 := _creature(em, Vector3(6, 0, 0), "skeleton", 1.0)
	em.vspecial[s3] = 1
	em.damage(s3, 99999.0)
	assert_int(int(pk.chests)).is_equal(2)
	# an elite-modded one drops its own chest anyway: a gem (worth four times as much), no Hot Sauce chest
	em._hot_chest_cd = 0.0
	var gems := (pk.gems as Array).size()
	var m := _creature(em, Vector3(8, 0, 0), "skeleton", 1.0, Registry.elites_list()[0])
	em.damage(m, 9999999.0)
	assert_int((pk.gems as Array).size()).is_equal(gems + 1)
	assert_float(float(pk.gems[gems]["v"])).is_equal_approx(xp * 4.0 * EnemyManager.HOT_XP * 20.0, 0.05)
	assert_int(int(pk.chests)).is_equal(2)
	# a plain creature and an Elite pay nothing extra (at difficulty 20 every skeleton rolls the special: this one is
	# made plain by hand)
	var p := _creature(em, Vector3(10, 0, 0), "skeleton", 1.0)
	em.vspecial[p] = 0
	em.damage(p, 99999.0)
	var e := _creature(em, Vector3(14, 0, 0), "dune_scorpion", 1.0)
	em.damage(e, 9999999.0)
	assert_int((pk.gems as Array).size()).is_equal(gems + 1)
	assert_int(int(pk.chests)).is_equal(2)


# ---------------------------------------------------------------- Garry's art picks, the scorpion's shadow

func test_the_picked_variants_play() -> void:
	assert_str(Registry.enemy("dune_scorpion").variant).is_equal("SC-D")
	assert_str(Registry.enemy("hammer_giant").variant).is_equal("HG-A")
	assert_str(Registry.enemy("tumbleweed_minion").variant).is_equal("TM-C")


func test_the_scorpions_shadow_sits_under_its_body() -> void:
	var sc: EnemyDef = Registry.enemy("dune_scorpion")
	var tune: Dictionary = sc.shadow_tuning()
	assert_float(float(tune.get("up", 0.0))).is_greater(0.0)
	assert_float(float(tune.get("drop", 0.0))).is_greater(0.0)
	assert_float(float((tune.get("scale", [1, 1]) as Array)[0])).is_greater(1.0)
	# every art variant shares the 3D model's framing, so the tuning holds for them all
	assert_float(float(sc.variant_def("SC-A").shadow_tuning().get("up", 0.0))).is_equal_approx(float(tune["up"]), 0.0001)
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	var s := _creature(em, Vector3(0, 0, 0), "dune_scorpion")
	var k := _creature(em, Vector3(6, 0, 0), "skeleton")
	# the fixed camera: forward north (-Z), right east, the billboards' up 46 degrees back from straight up
	var cf := Vector3(0, 0, -1)
	var cr := Vector3(1, 0, 0)
	var cam_up := Vector3(0, 0.695, -0.719)
	# the scorpion's shadow is moved up the screen (north) and is wider; the skeleton's is at its feet as it was
	var sh_s := em.shadow_xform(s, cf, cr)
	var sh_k := em.shadow_xform(k, cf, cr)
	assert_float(sh_s.origin.z).is_less(em.pos[s].z - 0.3)
	assert_float(sh_s.basis.x.length()).is_greater(em.size[s] * 0.55 * 1.1)
	assert_float(sh_s.basis.z.length()).is_greater(em.size[s] * 0.34 * 1.1)
	assert_float(Vector2(sh_k.origin.x - em.pos[k].x, sh_k.origin.z - em.pos[k].z).length()).is_less(0.001)
	assert_float(sh_k.basis.x.length()).is_equal_approx(em.size[k] * 0.55, 0.001)
	# the painting sinks by its share of the cell, down the billboard's plane; the skeleton's stands where it is
	var sink := em.sprite_sink(s, 1.0, cam_up)
	assert_float(sink.length()).is_equal_approx(float(tune["drop"]) * em.size[s], 0.001)
	assert_float(sink.normalized().dot(cam_up.normalized())).is_greater(0.999)
	assert_float(em.sprite_sink(k, 1.0, cam_up).length()).is_equal(0.0)
	# and the render runs with both (the dummy renderer keeps no instance data to read back)
	em._cf_tick = cf
	em._render()
	assert_int(em._shadow_mm.visible_instance_count).is_equal(2)


func test_a_variant_entry_may_carry_its_own_shadow() -> void:
	# JsonContent copies the block onto the creature and into every variant entry (the entry's own, else the creature's)
	var sa := "res://content/enemies/dune_scorpion/dune_scorpion_sprite_a.png"
	var sb := "res://content/enemies/dune_scorpion/dune_scorpion_sprite_b.png"
	var json := {"id": "sh_beast", "name": "Shadow Beast", "shadow": {"up": 0.2}, "variant": "B",
		"variants": {"A": {"sprite": sa, "shadow": {"up": 0.7, "drop": 0.1}}, "B": {"sprite": sb}}}
	var e: EnemyDef = JsonContent.build("enemies", json, "res://content/enemies/dune_scorpion/")
	# B has none of its own: the creature's
	assert_float(float(e.shadow_tuning().get("up", 0.0))).is_equal_approx(0.2, 0.0001)
	assert_float(float(e.variant_def("B").shadow_tuning().get("up", 0.0))).is_equal_approx(0.2, 0.0001)
	# A's own
	var a := e.variant_def("A")
	assert_float(float(a.shadow_tuning().get("up", 0.0))).is_equal_approx(0.7, 0.0001)
	assert_float(float(a.shadow_tuning().get("drop", 0.0))).is_equal_approx(0.1, 0.0001)
	# an entry handed over with its shadow (JsonContent's way) is taken as it is
	var c := EnemyDef.new()
	c.apply_art({"shadow": {"up": 0.4}})
	assert_float(float(c.shadow_tuning().get("up", 0.0))).is_equal_approx(0.4, 0.0001)
	# and the numbers the render reads: per metre of size, and a scale given as one number
	c.size = 2.0
	c.shadow = {"scale": 1.5, "up": 0.4, "drop": 0.05}
	var n := EnemyManager.shadow_numbers(c)
	assert_float(n[0]).is_equal_approx(1.5, 0.0001)
	assert_float(n[1]).is_equal_approx(1.5, 0.0001)
	assert_float(n[2]).is_equal_approx(0.2, 0.0001)
	assert_float(n[3]).is_equal_approx(0.05, 0.0001)


# ---------------------------------------------------------------- the Tumbleweed King

func _attack_index(boss_id: String, atk_name: String) -> int:
	var attacks: Array = Registry.enemy(boss_id).boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


func test_the_volley_spokes_reach_as_far_as_the_tumbleweeds_roll() -> void:
	var w := _world(Vector3(20, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	var vi := _attack_index("tumbleweed_king", "tumbleweed_volley")
	var row: Dictionary = (Registry.enemy("tumbleweed_king").boss["attacks"] as Array)[vi]
	em.state[b] = EnemyManager.STATE_MOVE
	em.atk_i[b] = vi
	em.atk_t[b] = 0.0
	em._update_attacks(b, DT, g.player.global_position)
	var travel: float = float(row["speed"]) * float(row["life"])
	assert_int((g.lines as Array).size()).is_equal(int(row["count"]))
	for l in g.lines:
		# from the King's centre past the farthest any tumbleweed rolls (they start 1.2 m out)
		assert_float(float(l)).is_greater_equal(travel + 1.2)
	assert_float(travel).is_greater(20.0)


func test_the_kings_wind_up_plays_at_the_standing_pace_in_a_crowd() -> void:
	var w := _world(Vector3(20, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	var ri := _attack_index("tumbleweed_king", "spawn_ring")
	em.state[b] = EnemyManager.STATE_MOVE
	em.atk_i[b] = ri
	em.atk_t[b] = 0.0
	em._update_attacks(b, DT, g.player.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	# a crowd pressed against one side of him, standing still, shoving him every steer tick
	for k in range(10):
		var a := deg_to_rad(-60.0 + 120.0 * float(k) / 9.0)
		var j := _creature(em, Vector3(cos(a), 0, sin(a)) * 1.6)
		em.speed[j] = 0.0
	var a0 := em.anim_t[b]
	var flip0 := em.flip[b]
	var flips := 0
	for n in range(30):
		em._physics_process(DT)
		if em.flip[b] != flip0:
			flips += 1
			flip0 = em.flip[b]
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	# half a second at three frames a second (it ran at nine in a crowd: every steer tick counted as walking)
	assert_float(em.anim_t[b] - a0).is_equal_approx(EnemyManager.ATTACK_FPS * 0.5, 0.1)
	assert_int(flips).is_equal(0)


# ---------------------------------------------------------------- Frag

func test_frag_bursts_into_steel_spikes_that_fly_out_past_the_blast() -> void:
	var w := _world(Vector3(0, 0, 30))
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("lob_grenade", ["frag"])
	var bs: Dictionary = inst.params["burst_spawn"]
	assert_str(str(bs.get("kind", ""))).is_equal("shrapnel")
	# a crowd where it lands, and a ring of creatures past the blast
	var middle: Array = []
	for k in range(5):
		middle.append(_creature(em, Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))))
	var ring: Array = []
	for k in range(24):
		var a := TAU * float(k) / 24.0
		ring.append(_creature(em, Vector3(cos(a), 0, sin(a)) * 4.2))
	em._rebuild_grid()
	var gk := pm.register_kind(BoxMesh.new(), null)
	var area: float = inst.stat("area", 2.5)
	var lobbed := pm.lob(gk, Vector3(0, 1.2, 6), Vector3.ZERO, 9.0, 25.0, area, inst, 7.0, inst.params.duplicate())
	assert_int(lobbed).is_greater_equal(0)
	var spikes: Array = []
	var t := 0.0
	while t < 3.0 and spikes.is_empty():
		pm._physics_process(DT)
		t += DT
		for j in range(ProjectileManager.MAX):
			if pm.alive[j] == 1 and (pm.extra[j] as Dictionary).has("shrapnel"):
				spikes.append(j)
	assert_int(pm.lobs_exploded).is_equal(1)
	# six spikes, drawn as spikes (their own kind), flying flat out without a spin
	assert_int(spikes.size()).is_equal(int(bs.get("count", 6)))
	assert_int(pm.shrapnel_kind()).is_not_equal(gk)
	for j: int in spikes:
		assert_int(pm.kind[j]).is_equal(pm.shrapnel_kind())
		assert_float(pm.spin[j]).is_equal(0.0)
		assert_bool((pm.extra[j] as Dictionary).has("sparks")).is_true()
		# the crowd the blast caught is behind them
		for m: int in middle:
			assert_bool((pm.memo[j] as Dictionary).has(m)).is_true()
	var at0: Array = []
	for j: int in spikes:
		at0.append(pm.pos[j])
	for n in range(6):
		pm._physics_process(DT)
	var flew := 0
	for k in range(spikes.size()):
		var j: int = spikes[k]
		if pm.alive[j] == 1:
			assert_float(pm.spin[j]).is_equal(0.0)
			if Vector2(pm.pos[j].x, pm.pos[j].z).length() > 1.2:
				flew += 1
	assert_int(flew).is_greater_equal(4)
	# and they land on what stood past the blast
	for n in range(40):
		pm._physics_process(DT)
	var hit := 0
	for i: int in ring:
		if em.hp[i] < em.max_hp[i]:
			hit += 1
	assert_int(hit).is_greater_equal(4)


func test_a_cluster_bomblet_throws_half_the_spikes_without_sparks() -> void:
	var w := _world(Vector3(0, 0, 30))
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("lob_grenade", ["frag"])
	var gk := pm.register_kind(BoxMesh.new(), null)
	var params: Dictionary = inst.params.duplicate()
	params["is_bomblet"] = true
	pm.lob(gk, Vector3(0, 1.2, 4), Vector3.ZERO, 9.0, 25.0, 1.4, inst, 7.0, params)
	var spikes: Array = []
	var t := 0.0
	while t < 3.0 and spikes.is_empty():
		pm._physics_process(DT)
		t += DT
		for j in range(ProjectileManager.MAX):
			if pm.alive[j] == 1 and (pm.extra[j] as Dictionary).has("shrapnel"):
				spikes.append(j)
	assert_int(spikes.size()).is_equal(int(inst.params["burst_spawn"]["count"]) / 2)
	for j: int in spikes:
		assert_bool((pm.extra[j] as Dictionary).has("sparks")).is_false()


# ---------------------------------------------------------------- the Turret Buddy

func test_the_watchtower_is_gone_and_the_family_opens_with_all_three() -> void:
	assert_object(Registry.mutation("watchtower")).is_null()
	var path: Array = Registry.mutations_of("turret_buddy")
	assert_int(path.size()).is_equal(3)
	assert_array(path.map(func(m: MutationDef) -> String: return m.mutation_kind)).is_equal(["element", "volume", "motion"])
	var w: WeaponInstance = Run.add_weapon(Registry.weapon("turret_buddy"), Registry.weapon("turret_buddy").max_level)
	assert_object(w).is_not_null()
	assert_bool(Run.evolution_ready(w)).is_false()
	assert_bool(Run.add_mutation("bunker", true)).is_true()
	assert_bool(Run.add_mutation("buddy_squad", true)).is_true()
	# pass 48: two are no longer enough, the family opens with all three (Dart Buddy the third)
	assert_bool(Run.evolution_ready(w)).is_false()
	assert_bool(Run.add_mutation("last_stand", true)).is_true()   # pass 53: Last Stand is the element pick, Dart Buddy hidden
	assert_bool(Run.evolution_ready(w)).is_true()
	assert_str(w.def.evolves_into).is_equal("iron_bastion")   # the Iron Bastion since pass 53 (the Family is hidden)


func _spawner(w: Dictionary, id: String, muts: Array = []) -> Spawner:
	var sp := Spawner.new()
	(w["g"] as Node).add_child(sp)
	sp.setup(_inst(id, muts), w["g"])
	return sp


func _turret(w: Dictionary, sp: Spawner) -> Turret:
	var t := Turret.new()
	t.setup(sp, sp._proto, sp._turret_mesh, sp._turret_mat)
	(w["g"] as Node).add_child(t)
	t.global_position = Vector3.ZERO
	return t


## Seconds until a fresh turret at the origin fires its first round at a creature at `at`.
func _first_shot(at: Vector3, muts: Array = []) -> float:
	var w := _world(Vector3(0, 0, 30))
	var em: EnemyManager = w["em"]
	_creature(em, at)
	em._rebuild_grid()
	var t := _turret(w, _spawner(w, "turret_buddy", muts))
	var s := 0.0
	while t.shots == 0 and s < 4.0:
		t._process(DT)
		s += DT
	return s


func test_the_turret_turns_its_head_before_it_fires() -> void:
	# straight ahead of its head: it fires once it is up
	var ahead := _first_shot(Vector3(0, 0, -5))
	assert_float(ahead).is_less(Turret.POP_IN + 0.1)
	# behind it: half a turn at its traverse first
	var behind := _first_shot(Vector3(0, 0, 5))
	assert_float(behind).is_greater_equal((180.0 - Turret.AIM_TOLERANCE_DEG) / Turret.TURN_DEFAULT - DT)
	assert_float(behind).is_greater(ahead + 0.4)
	# the Bunker turns slower still
	var bunker := _first_shot(Vector3(0, 0, 5), ["bunker"])
	assert_float(bunker).is_greater(behind + 0.3)
	# and while it turns, the barrel is off its target; when it fires, within the tolerance
	var w := _world(Vector3(0, 0, 30))
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(5, 0, 0))
	em._rebuild_grid()
	var t := _turret(w, _spawner(w, "turret_buddy"))
	t._process(DT)
	assert_float(t.aim_error()).is_greater(45.0)
	var s := 0.0
	while t.shots == 0 and s < 2.0:
		t._process(DT)
		s += DT
	assert_float(t.aim_error()).is_less_equal(Turret.AIM_TOLERANCE_DEG + 0.01)
	assert_float(t.turn_rate()).is_equal(Turret.TURN_DEFAULT)


func test_the_turrets_mutations_hang_nothing_over_the_hero() -> void:
	var w := _world()
	var sp := _spawner(w, "turret_buddy", ["bunker", "buddy_squad"])
	# pass 60: no weapon hangs emblems any more (WeaponBehavior.refresh_marks only frees an old "MutationMarks" node)
	assert_object(sp.get_node_or_null("MutationMarks")).is_null()
	assert_bool(bool(Registry.weapon("iron_bastion").params.get("marks", true))).is_false()
	# another weapon hangs none either since pass 60
	var lb := Lobber.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(_inst("lob_grenade", ["frag"]), w["g"])
	assert_object(lb.get_node_or_null("MutationMarks")).is_null()
