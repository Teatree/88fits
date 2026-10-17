extends GdUnitTestSuite

## Pass 47, the hero lane (C2): the floating numbers read like Megabonk's (Alfa Slab, a thick ink outline, bigger crits)
## and the hero gets his own (damage taken in red, his shield's soak in blue, heals in green with regen and Siesta
## batched every half second, DODGE and BLOCK), Siesta heals only while he stands still, the stillness reaches Run for
## Steady Hand, a smashed barrel starts Barrel Rush when he holds it, Prospector's extra gem drops at its chance, and a
## skip (a level-up's, a path's or a chest's) pays no gold.

## A stand-in for the numbers that only writes down what the hero sent it.
const FAKE_NUMBERS := """extends DamageNumbers
var calls: Array = []
func hero_hurt(amount: float) -> void:
	calls.append(["hurt", amount])
func hero_shield(amount: float) -> void:
	calls.append(["shield", amount])
func hero_heal(amount: float) -> void:
	calls.append(["heal", amount])
func hero_dodge() -> void:
	calls.append(["dodge", 0.0])
func hero_block() -> void:
	calls.append(["block", 0.0])
"""

## A game for the barrels: no effects, no pickups, no camera; it writes down the Barrel Rush bursts it is asked for.
const FAKE_GAME := """extends Node
var fx = null
var pickups = null
var camera = null
var hud = null
var player = null
var paused := false
var rush: Array = []
func barrel_rush_fx(fresh: bool) -> void:
	rush.append(fresh)
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _hero(id: String = "astro") -> Player:
	Run.start(Registry.character(id), Registry.map("red_canyon"))
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character(id))
	p.hp = p.max_hp
	return p


func _fake_numbers() -> DamageNumbers:
	var fake: DamageNumbers = auto_free(_script(FAKE_NUMBERS).new())
	DamageNumbers.I = fake
	return fake


## The numbers on the tree, with a camera over the origin so the hits there are on the screen.
func _numbers() -> DamageNumbers:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.position = Vector3(0, 12, 12)
	cam.look_at(Vector3.ZERO)
	cam.make_current()
	var dn: DamageNumbers = auto_free(DamageNumbers.new())
	add_child(dn)
	return dn


func after_test() -> void:
	DamageNumbers.I = null


# ---------------------------------------------------------------- the numbers' look

func test_the_numbers_read_like_megabonk_s() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	# Bitter 800 since pass 54 (Alfa Slab One before), hits 52 px, crits 78 in WoW's yellow (pass 48; 64 in gold before),
	# ticks 44 in orange and purple (pass 48; green before; pass 54 a tenth up on 48 / 72 / 40), an ink outline (pass 54:
	# thinner, 0.28 of the size), ~0.9 s of life
	assert_object(dn._font).is_same(W.serif(DamageNumbers.WEIGHT))
	assert_int(DamageNumbers.PX).is_equal(52)
	assert_int(DamageNumbers.PX_CRIT).is_equal(78)
	assert_int(DamageNumbers.PX_TICK).is_equal(44)
	assert_float(DamageNumbers.OUTLINE_FRAC).is_between(0.25, 0.32)
	assert_float(DamageNumbers.LIFE).is_equal_approx(0.9, 0.001)
	dn.add(1, Vector3.ZERO, 12.0)
	dn.add(2, Vector3.ZERO, 137.0, true)
	dn.add(3, Vector3.ZERO, 9.0, false, false, true)
	dn.add(4, Vector3.ZERO, 6.0, false, true, false)
	var n: Array = dn.live()
	assert_int(n.size()).is_equal(4)
	assert_int(DamageNumbers.size_of(n[0])).is_equal(52)
	assert_int(DamageNumbers.size_of(n[1])).is_equal(78)
	assert_int(DamageNumbers.size_of(n[2])).is_equal(44)
	assert_int(DamageNumbers.size_of(n[3])).is_equal(44)
	assert_bool(DamageNumbers.colour_of(n[0]) == DamageNumbers.WHITE).is_true()
	assert_bool(DamageNumbers.colour_of(n[1]) == DamageNumbers.CRIT).is_true()
	assert_bool(DamageNumbers.colour_of(n[2]) == DamageNumbers.HOT).is_true()
	assert_bool(DamageNumbers.colour_of(n[3]) == DamageNumbers.POISON).is_true()
	assert_str(DamageNumbers.label_of(n[1])).is_equal("137")
	# neighbours lean apart, so a crowd's numbers spread instead of stacking
	assert_bool(signf((n[0] as DamageNumbers.Num).nudge.x) != signf((n[1] as DamageNumbers.Num).nudge.x)).is_true()
	assert_bool(signf((n[0] as DamageNumbers.Num).drift) == signf((n[0] as DamageNumbers.Num).nudge.x)).is_true()
	# a stronger pop: big at birth, a dip under 1 as it settles, 1 at POP; whole until HOLD of its life, gone at LIFE
	assert_float(DamageNumbers.pop_scale(0.0, false)).is_equal_approx(DamageNumbers.POP_FROM, 0.001)
	assert_float(DamageNumbers.pop_scale(0.0, true)).is_equal_approx(DamageNumbers.POP_FROM_CRIT, 0.001)
	assert_float(DamageNumbers.POP_FROM_CRIT).is_greater(DamageNumbers.POP_FROM)
	assert_float(DamageNumbers.pop_scale(DamageNumbers.POP * 0.75, false)).is_less(1.0)
	assert_float(DamageNumbers.pop_scale(DamageNumbers.POP, false)).is_equal_approx(1.0, 0.0001)
	assert_float(DamageNumbers.alpha_at(DamageNumbers.LIFE * 0.5)).is_equal(1.0)
	assert_float(DamageNumbers.alpha_at(DamageNumbers.LIFE)).is_equal(0.0)
	await get_tree().process_frame


func test_burn_ticks_never_crowd_out_the_hits() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	# a burning crowd: ticks up to TICK_CAP, then they are let go
	for k in range(DamageNumbers.TICK_CAP + 10):
		dn.add(200 + k, Vector3.ZERO, 3.0, false, false, true)
	assert_int(dn.count()).is_equal(DamageNumbers.TICK_CAP)
	# the hits still find room, and push out the oldest when the pool is full
	for k in range(DamageNumbers.CAP):
		dn.add(400 + k, Vector3.ZERO, 9.0)
	assert_int(dn.count()).is_equal(DamageNumbers.CAP)
	var ticks := 0
	for m: DamageNumbers.Num in dn.live():
		if m.kind != DamageNumbers.KIND_HIT:
			ticks += 1
	assert_int(ticks).is_equal(0)
	# the count follows them out: a new tick is welcome again
	dn.add(999, Vector3.ZERO, 3.0, false, true, false)
	assert_int((dn.live().back() as DamageNumbers.Num).who).is_equal(999)
	dn.step(DamageNumbers.LIFE)
	assert_int(dn.count()).is_equal(0)
	assert_int(dn._ticks).is_equal(0)


func test_the_hero_s_numbers_have_their_own_kinds_and_sides() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	dn.hero_hurt(12.4)
	dn.hero_shield(5.0)
	dn.hero_heal(18.0)
	dn.hero_dodge()
	dn.hero_block()
	var n: Array = dn.live()
	assert_int(n.size()).is_equal(5)
	var by := {}
	for m: DamageNumbers.Num in n:
		assert_int(m.who).is_equal(DamageNumbers.HERO)
		by[m.kind] = m
	var hurt: DamageNumbers.Num = by[DamageNumbers.KIND_HURT]
	var shield: DamageNumbers.Num = by[DamageNumbers.KIND_SHIELD]
	var heal: DamageNumbers.Num = by[DamageNumbers.KIND_HEAL]
	var dodge: DamageNumbers.Num = by[DamageNumbers.KIND_DODGE]
	var block: DamageNumbers.Num = by[DamageNumbers.KIND_BLOCK]
	# damage red with a minus, the shield's soak blue, health back green with a plus, the words pale
	assert_str(DamageNumbers.label_of(hurt)).is_equal("−12")
	assert_str(DamageNumbers.label_of(shield)).is_equal("−5")
	assert_str(DamageNumbers.label_of(heal)).is_equal("+18")
	# (pass 87, lane FIXES, re-pinned: an evade reads EVADE in its own lavender, Garry's word)
	assert_str(DamageNumbers.label_of(dodge)).is_equal("EVADE")
	assert_str(DamageNumbers.label_of(block)).is_equal("BLOCK")
	assert_bool(DamageNumbers.colour_of(hurt) == DamageNumbers.RED).is_true()
	assert_bool(DamageNumbers.colour_of(shield) == DamageNumbers.BLUE).is_true()
	assert_bool(DamageNumbers.colour_of(heal) == DamageNumbers.HEAL).is_true()
	assert_bool(DamageNumbers.colour_of(dodge) == DamageNumbers.EVADE).is_true()
	assert_int(DamageNumbers.size_of(hurt)).is_greater(DamageNumbers.size_of(heal))
	# what hit him (or missed) on his left, healing on his right, a word higher than a number born with it
	assert_float(hurt.nudge.x).is_less(0.0)
	assert_float(shield.nudge.x).is_less(0.0)
	assert_float(dodge.nudge.x).is_less(0.0)
	assert_float(heal.nudge.x).is_greater(0.0)
	assert_float(dodge.nudge.y).is_less(hurt.nudge.y)
	await get_tree().process_frame


func test_the_hero_s_numbers_merge_and_obey_the_switch() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	# lifesteal comes back a point at a time: the points within HEAL_MERGE read as one number
	for k in range(5):
		dn.hero_heal(1.0)
		dn.step(0.05)
	assert_int(dn.count()).is_equal(1)
	assert_float((dn.live()[0] as DamageNumbers.Num).amount).is_equal_approx(5.0, 0.001)
	dn.step(DamageNumbers.HEAL_MERGE)
	dn.hero_heal(2.0)
	assert_int(dn.count()).is_equal(2)
	# hits within MERGE are one number, and a merge bumps it
	dn.hero_hurt(3.0)
	dn.hero_hurt(4.0)
	var last: DamageNumbers.Num = dn.live().back()
	assert_float(last.amount).is_equal_approx(7.0, 0.001)
	assert_float(last.bump).is_greater(0.0)
	# a dodge says it once in its window
	dn.hero_dodge()
	dn.hero_dodge()
	var words := 0
	for m: DamageNumbers.Num in dn.live():
		if m.kind == DamageNumbers.KIND_DODGE:
			words += 1
	assert_int(words).is_equal(1)
	# nothing under a half point... and nothing at all with the numbers off or suppressed by a tool
	dn.clear()
	dn.hero_heal(0.0)
	assert_int(dn.count()).is_equal(0)
	dn.suppressed = true
	dn.hero_hurt(5.0)
	dn.add(1, Vector3.ZERO, 5.0)
	assert_int(dn.count()).is_equal(0)
	assert_bool(Settings.damage_numbers).is_true()
	dn.suppressed = false
	# heals have their own switch since pass 47b
	Settings.float_heal = false
	dn.hero_heal(5.0)
	assert_int(dn.count()).is_equal(0)
	Settings.float_heal = true
	Settings.damage_numbers = false
	dn.hero_hurt(5.0)
	assert_int(dn.count()).is_equal(0)
	Settings.damage_numbers = true
	# one life for all: everything is gone after LIFE
	dn.hero_heal(5.0)
	dn.add(1, Vector3.ZERO, 5.0, true)
	dn.step(DamageNumbers.LIFE)
	assert_int(dn.count()).is_equal(0)


# ---------------------------------------------------------------- the hero's hooks

func test_hits_and_heals_on_the_hero_reach_the_numbers() -> void:
	var p := _hero("astro")
	var fake := _fake_numbers()
	var calls: Array = fake.get("calls")
	p.hp = p.max_hp * 0.5
	# a pickup's (or lifesteal's, or the level patch's) heal at once
	p.heal(3.0)
	assert_array(calls.back()).is_equal(["heal", 3.0])
	# a hit: what reached his health, after his damage reduction
	p.invuln = 0.0
	var dr := clampf(p.sheet.get_stat("damage_reduction", 0.0), 0.0, 0.8)
	p.take_damage(10.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_str(str(calls.back()[0])).is_equal("hurt")
	assert_float(float(calls.back()[1])).is_equal_approx(10.0 * (1.0 - dr), 0.001)
	# immune: nothing
	var n := calls.size()
	p.take_damage(10.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_int(calls.size()).is_equal(n)
	# the Energy Shield's soak in blue
	p.invuln = 0.0
	p.shield_pts = 20.0
	p.take_damage(8.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_str(str(calls.back()[0])).is_equal("shield")
	assert_float(float(calls.back()[1])).is_equal_approx(8.0 * (1.0 - dr), 0.001)
	p.shield_pts = 0.0
	# the Shield power-up's BLOCK
	p.invuln = 0.0
	p.shield(1.0)
	p.take_damage(8.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_str(str(calls.back()[0])).is_equal("block")
	p.shield_t = 0.0
	# an evaded hit's DODGE
	Run.player_sheet.add_effects([Effect.make("evade", "add", 1.0, "player")], "test")
	seed(47)
	var dodged := false
	for k in range(30):
		p.invuln = 0.0
		p.take_damage(8.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
		if str(calls.back()[0]) == "dodge":
			dodged = true
			break
	assert_bool(dodged).is_true()
	Run.player_sheet.remove_source("test")
	Run.end()


func test_regen_heals_show_as_one_number_every_half_second() -> void:
	var p := _hero("astro")
	Run.player_sheet.add_effects([Effect.make("regen", "add", 4.0, "player")], "test")
	p.refresh_stats()
	var regen := p.sheet.get_stat("regen", 0.0)
	assert_float(regen).is_greater_equal(4.0)
	var fake := _fake_numbers()
	var calls: Array = fake.get("calls")
	p.hp = p.max_hp * 0.5
	p.regen_hold = 0.0
	var before := p.hp
	for k in range(4):
		p._tick_regen(0.25)
	# a second of regen: the health climbed all along, the numbers came twice, half a second's worth each
	assert_float(p.hp - before).is_equal_approx(regen, 0.001)
	assert_int(calls.size()).is_equal(2)
	for c in calls:
		assert_str(str(c[0])).is_equal("heal")
		assert_float(float(c[1])).is_equal_approx(regen * 0.5, 0.001)
	# a trickle under a point waits for the next batch; a full bar shows what is left from half a point, less goes
	calls.clear()
	p._heal_batch = 0.4
	p._heal_batch_t = 0.0
	p._flush_heal_batch(0.5)
	assert_int(calls.size()).is_equal(0)
	assert_float(p._heal_batch).is_equal_approx(0.4, 0.0001)
	p._heal_batch = 1.2
	p._flush_heal_batch(0.5)
	assert_array(calls.back()).is_equal(["heal", 1.2])
	assert_float(p._heal_batch).is_equal(0.0)
	p.hp = p.max_hp
	p._heal_batch = 0.6
	p._flush_heal_batch(0.5)
	assert_float(float(calls.back()[1])).is_equal_approx(0.6, 0.0001)
	var n := calls.size()
	p._heal_batch = 0.3
	p._flush_heal_batch(0.5)
	assert_int(calls.size()).is_equal(n)
	assert_float(p._heal_batch).is_equal(0.0)
	Run.player_sheet.remove_source("test")
	Run.end()


# ---------------------------------------------------------------- Siesta and Steady Hand

func test_siesta_heals_only_while_he_stands_still() -> void:
	var p := _hero("astro")
	Run.player_sheet.add_effects([Effect.make("still_regen", "add", 4.0, "player")], "test")
	p.refresh_stats()
	p.hp = p.max_hp * 0.5
	# the regen held off, so whatever comes back is Siesta's
	p.regen_hold = 999.0
	# running: no Siesta
	for k in range(4):
		p._tick_still(0.25, Vector3(3, 0, 0), Vector3(0.75, 0, 0), true)
	assert_bool(p.is_still()).is_false()
	var hp0 := p.hp
	p._tick_regen(1.0)
	assert_float(p.hp).is_equal(hp0)
	# no stick and no speed for half a second: still, and 4 HP a second back
	p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, true)
	assert_bool(p.is_still()).is_false()
	p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, true)
	assert_bool(p.is_still()).is_true()
	hp0 = p.hp
	p._tick_regen(1.0)
	assert_float(p.hp - hp0).is_equal_approx(4.0, 0.001)
	# a shove moving him is moving; in the air is not standing
	p._tick_still(0.1, Vector3.ZERO, Vector3(0.2, 0, 0), true)
	assert_bool(p.is_still()).is_false()
	for k in range(3):
		p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, false)
	assert_bool(p.is_still()).is_false()
	# a hit holds it a second (with him still)
	for k in range(3):
		p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, true)
	assert_bool(p.is_still()).is_true()
	p.invuln = 0.0
	p.take_damage(1.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	hp0 = p.hp
	p._tick_regen(0.5)
	assert_float(p.hp).is_equal(hp0)
	p._tick_still(1.0, Vector3.ZERO, Vector3.ZERO, true)
	p._tick_regen(0.5)
	assert_float(p.hp - hp0).is_equal_approx(2.0, 0.001)
	# Unbroken: a hit never holds it
	assert_bool(Run.add_perk("unbroken")).is_true()
	p.invuln = 0.0
	p.take_damage(1.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	hp0 = p.hp
	p._tick_regen(0.5)
	assert_float(p.hp - hp0).is_equal_approx(2.0, 0.001)
	Run.player_sheet.remove_source("test")
	Run.end()


func test_standing_still_reaches_run_for_steady_hand() -> void:
	var p := _hero("astro")
	Run.player_sheet.add_effects([Effect.make("still_might", "add", 0.25, "player")], "test")
	p.refresh_stats()
	# Run hears every tick: 0 until he counts as still, then the seconds since
	p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, true)
	assert_float(p.noted_still).is_equal(0.0)
	for k in range(5):
		p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, true)
	assert_float(p.still_seconds()).is_equal_approx(1.0, 0.0001)
	assert_float(p.noted_still).is_equal_approx(1.0, 0.0001)
	assert_float(Run.still_seconds).is_equal_approx(1.0, 0.0001)
	assert_float(Run.steady_might()).is_equal_approx(0.25, 0.0001)
	# he moves: 0 again
	p._tick_still(0.016, Vector3(4, 0, 0), Vector3(0.06, 0, 0), true)
	assert_float(p.noted_still).is_equal(0.0)
	assert_float(Run.steady_might()).is_equal(0.0)
	# dead or in the spawn beam: not standing still
	for k in range(6):
		p._tick_still(0.25, Vector3.ZERO, Vector3.ZERO, true)
	assert_float(p.noted_still).is_greater(0.0)
	p._stop_still()
	assert_float(p.noted_still).is_equal(0.0)
	assert_bool(p.is_still()).is_false()
	Run.player_sheet.remove_source("test")
	Run.end()


# ---------------------------------------------------------------- Barrel Rush

## One dark barrel at `at`, set up by hand (no map, no meshes but the instance buffers _break writes to).
func _barrels(game: Node, n: int) -> BarrelField:
	var bf: BarrelField = auto_free(BarrelField.new())
	bf.game = game
	for k in range(n):
		bf.pos.append(Vector3(float(k) * 8.0, 0, 0))
		bf.light.append(0)
		bf.alive.append(1)
		bf._index_in.append(k)
	for name in ["_body_dark", "_body_light", "_hoops"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = n
		bf.set(name, mm)
	return bf


func test_a_smashed_barrel_starts_barrel_rush_when_he_holds_it() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	var bf := _barrels(g, 3)
	# without the passive: a barrel is only a barrel
	bf._break(0)
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal(0.0)
	assert_array(g.get("rush")).is_empty()
	# held: the boost starts (gold burst, fresh), the speed goes up on the sheet
	var base_speed := Run.player_sheet.get_stat("move_speed", 0.0)
	Run.player_sheet.add_effects([Effect.make("barrel_speed", "add", 0.3, "player"), Effect.make("barrel_seconds", "add", 4.0, "player")], "test")
	bf._break(1)
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal_approx(4.0, 0.001)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_greater(base_speed)
	assert_array(g.get("rush")).is_equal([true])
	# another barrel while it runs refreshes it (a smaller burst, no fanfare)
	Run.elapsed += 1.5
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal_approx(2.5, 0.001)
	bf._break(2)
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal_approx(4.0, 0.001)
	assert_array(g.get("rush")).is_equal([true, false])
	assert_int(bf.broken).is_equal(3)
	Run.end()


func test_the_rush_trail_grows_while_he_runs_and_fades_after() -> void:
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	assert_bool(fx.rush_trail_live()).is_false()
	for k in range(10):
		fx.rush_trail(Vector3(float(k) * 0.2, 0, 0), 0.025, true)
	assert_bool(fx.rush_trail_live()).is_true()
	# standing: no new points, and the tail is gone after its seconds
	fx.rush_trail(Vector3(2, 0, 0), Fx.RUSH_TRAIL_SECONDS + 0.01, false)
	assert_bool(fx.rush_trail_live()).is_false()


# ---------------------------------------------------------------- Prospector

func test_prospector_drops_an_extra_gem_at_its_chance() -> void:
	var pm: PickupManager = auto_free(PickupManager.new())
	add_child(pm)
	var skel: EnemyDef = Registry.enemy("skeleton")
	var scorp: EnemyDef = Registry.enemy("dune_scorpion")
	# the size it mostly drops: a skeleton's small gem, the scorpion's large one
	assert_int(PickupManager.base_gem_kind(skel)).is_equal(PickupManager.KIND_GEM_S)
	assert_int(PickupManager.base_gem_kind(scorp)).is_equal(PickupManager.KIND_GEM_L)
	# worth what that gem is worth from it
	assert_bool(pm.prospector(scorp, Vector3.ZERO, 2.0, 1.0)).is_true()
	var found := false
	for i in range(PickupManager.MAX):
		if pm.alive[i] == 1 and pm.kind[i] == PickupManager.KIND_GEM_L:
			assert_float(pm.value[i]).is_equal_approx(50.0, 0.001)
			found = true
	assert_bool(found).is_true()
	pm.clear_all()
	# never at 0; a quarter of the kills at 0.25 (seeded)
	assert_bool(pm.prospector(skel, Vector3.ZERO, 1.0, 0.0)).is_false()
	seed(4747)
	var drops := 0
	for k in range(2000):
		if pm.prospector(skel, Vector3.ZERO, 1.0, 0.25):
			drops += 1
		if pm.count > 200:
			pm.clear_all()
	assert_int(drops).is_between(440, 560)


# ---------------------------------------------------------------- skips pay nothing

func test_a_skip_pays_no_gold() -> void:
	# a real run: the level-up's, the path's and the chest's skip go through the Game
	var g: Node = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	# the warm-up under the spawn beam finishes on a timer: let it, so nothing of it outlives the game
	await get_tree().create_timer(0.5).timeout
	Run.skips_left = 2
	var gold := Run.run_gold
	g._on_card_chosen({"skipped": true})
	assert_int(Run.run_gold).is_equal(gold)
	g._on_path_chosen({"skipped": true})
	assert_int(Run.run_gold).is_equal(gold)
	# the chest let go: a skip spent, nothing gained, and the recorder hears it with no gold in it
	var roll := Run.chest_roll(false)
	g.chest_screen.open(roll)
	g._on_chest_closed(false)
	assert_int(Run.run_gold).is_equal(gold)
	assert_int(Run.skips_left).is_equal(1)
	if RunAnalytics.I:
		# Run records the chest let go (a chest event with skip and the skips left, integration), Game the card skips
		var kinds := {}
		var chest_skipped := false
		for e: Dictionary in RunAnalytics.I.events:
			kinds[str(e["kind"])] = true
			if str(e["kind"]) == "skip":
				assert_bool(e.has("gold")).is_false()
			if str(e["kind"]) == "chest" and bool(e.get("skip", false)):
				chest_skipped = true
				assert_bool(e.has("gold")).is_false()
		assert_bool(kinds.has("skip")).is_true()
		assert_bool(chest_skipped).is_true()
	g.set_paused(false)
	Run.end()
