extends GdUnitTestSuite

## Pass 70, lane LINES (Garry's items 3-8: "Magnet Line Item ... a bit more powerful", "a Line item that adds a knockback
## every level" whose evolution "gets a chance to launch the enemy up and away", "a Debuff Duration Line item", "a Damage
## Reduction Line Item", "Prospector ... a Line Item", "Golden Tooth ... a line item"): Lodestone, Mule Kick, Slow Burn
## and Tin Star new, Prospector and Gold Tooth made lines (ids kept, four levels), and their six evolved lines: Mother
## Lode (every gem on the screen flies in now and then), Bucking Bronco (a knocked plain creature may go up and away),
## Prairie Fire (a burn or poison that ends jumps on), Marshal's Star (a star blocks a whole hit, then recharges), Eureka
## (a kill may burst into a vein of gems) and Gold Rush (gold gained turns into attack damage). Debuff duration now also
## stretches freezes and stuns. The numbers are read off the content, so Garry's tuning never breaks these.

const LINES := {"lodestone": "mother_lode", "mule_kick": "bucking_bronco", "slow_burn": "prairie_fire",
	"tin_star": "marshals_star", "prospector": "eureka", "gold_tooth": "gold_rush"}
## Each line's own stat, op and target (its per-level effect).
const PER_LEVEL := {"lodestone": ["magnet", "mul", "player"], "mule_kick": ["knockback", "mul", "all_weapons"],
	"slow_burn": ["debuff_duration", "mul", "player"], "tin_star": ["damage_reduction", "add", "player"],
	"prospector": ["xp_drop_chance", "add", "player"], "gold_tooth": ["greed", "mul", "player"]}
## Each evolution's twist stat.
const TWIST := {"mother_lode": "gem_sweep_every", "bucking_bronco": "bronco_chance", "prairie_fire": "debuff_jump",
	"marshals_star": "star_block_every", "eureka": "vein_chance", "gold_rush": "gold_might"}

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
func fx_burst(_a, _b, _c) -> void:
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
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var character = null
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h: bool = true) -> void:
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

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.begin_sandbox()
	# nothing unlocked, no Upgrade ranks: the base numbers
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.player_sheet.remove_source("test")
	Run.end()
	Save.end_sandbox()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd, effects, ground marks and pickups.
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
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var pm: PickupManager = PickupManager.new()
	pm.game = g
	g.add_child(pm)
	g.pickups = pm
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": fx, "tg": tg, "pm": pm}


## A tough creature on its feet where it was put, taking every hit whole.
func _creature(em: EnemyManager, at: Vector3, id := "skeleton", hp_mult := 50.0, elite: EliteModDef = null) -> int:
	var i := em.spawn(id, at, elite, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.dr[i] = 0.0
	em._rebuild_grid()
	return i


## The hero carries `value` of `stat` (a test source), and the crowd reads it now.
func _give(em: EnemyManager, stat: String, op: String, value: float) -> void:
	Run.player_sheet.add_effects([Effect.make(stat, op, value, "player")], "test")
	if em:
		em.refresh_player_stats()


## Line `id` maxed and evolved, as a chest's evolution card does it.
func _evolve(id: String) -> void:
	assert_int(Run.debug_set_item("passive", id, 4)).is_equal(4)
	Run.rebuild_sheets()
	assert_bool(Run.evolve_passive(id)).override_failure_message(id + " did not evolve").is_true()


## The per-level effect of line `id` (its only one).
func _per(id: String) -> Effect:
	var effs: Array = Registry.passive(id).effects_at_level(1)
	assert_int(effs.size()).is_equal(1)
	return effs[0]


## The value of stat `stat` in evolution `id`'s one level.
func _evo_value(id: String, stat: String) -> float:
	for e: Effect in Registry.passive(id).effects_at_level(1):
		if e.stat == stat:
			return e.value
	return 0.0


## The real hero (Astro) at full health on the run's sheet.
func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	return p


func _hit(p: Player, amount: float) -> void:
	p.invuln = 0.0
	p.take_damage(amount, p.global_position + Vector3(1, 0, 0), {"by": "test"})


# ---------------------------------------------------------------- the content

func test_six_lines_each_with_four_levels_and_an_evolved_line() -> void:
	for id: String in LINES.keys():
		var p: PassiveDef = Registry.passive(id)
		assert_object(p).override_failure_message("no " + id).is_not_null()
		assert_bool(p.is_line()).override_failure_message(id + " is no line").is_true()
		assert_int(p.max_level).override_failure_message(id + " levels").is_equal(4)
		assert_bool(p.hidden).is_false()
		assert_float(p.weight).is_greater(0.0)
		assert_str(p.evolves_into).is_equal(str(LINES[id]))
		var e := _per(id)
		var want: Array = PER_LEVEL[id]
		assert_str(e.stat).is_equal(str(want[0]))
		assert_str(e.op).is_equal(str(want[1]))
		assert_str(e.target).is_equal(str(want[2]))
		assert_float(e.value).is_greater(0.0)
		var evo: PassiveDef = Registry.passive(p.evolves_into)
		assert_object(evo).is_not_null()
		assert_bool(evo.is_line()).is_true()
		assert_bool(evo.is_evolved()).is_true()
		assert_str(evo.evolves_from).is_equal(id)
		assert_int(evo.max_level).is_equal(1)
		assert_float(evo.weight).is_equal(0.0)
		assert_float(_evo_value(evo.id, str(TWIST[evo.id]))).override_failure_message(evo.id + " twist").is_greater(0.0)
		# a clear step up of its line's own stat over the maxed line (the evolution replaces it)
		var four := float(e.value)
		var lv4 := (pow(1.0 + four, 4.0) - 1.0) if e.op == "mul" else four * 4.0
		assert_float(_evo_value(evo.id, e.stat)).override_failure_message(evo.id + " is no step up").is_greater(lv4)
	# Prospector and Gold Tooth are lines now, not passive items; the old Magnet stays a passive item
	var items: Array = Registry.sorted_passives_only().map(func(d: ContentDef) -> String: return d.id)
	var lines: Array = Registry.sorted_lines().map(func(d: ContentDef) -> String: return d.id)
	for id: String in LINES.keys():
		assert_bool(lines.has(id)).is_true()
		assert_bool(items.has(id)).is_false()
	assert_bool(items.has("magnet")).is_true()


func test_each_line_reaches_the_sheet_level_by_level() -> void:
	for id: String in ["lodestone", "slow_burn", "tin_star", "prospector", "gold_tooth"]:
		var e := _per(id)
		var base: float = Run.player_sheet.get_stat(e.stat, float(StatSheet.PLAYER_DEFAULTS.get(e.stat, 0.0)))
		for lv in range(1, 5):
			assert_bool(Run.add_or_level_passive(id)).override_failure_message("%s level %d" % [id, lv]).is_true()
			var want := base * pow(1.0 + e.value, lv) if e.op == "mul" else base + e.value * lv
			assert_float(Run.player_sheet.get_stat(e.stat)).override_failure_message("%s at %d" % [id, lv]).is_equal_approx(want, 0.0001)
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " past four").is_false()


func test_mule_kick_raises_every_weapons_knockback() -> void:
	var w := Run.add_weapon(Registry.weapon("revolver"), 1)
	assert_object(w).is_not_null()
	var kb0 := w.stat("knockback")
	assert_float(kb0).is_greater(0.0)
	var v := _per("mule_kick").value
	for lv in range(1, 5):
		Run.add_or_level_passive("mule_kick")
		assert_float(w.stat("knockback")).is_equal_approx(kb0 * pow(1.0 + v, lv), 0.0001)
	# the hero's own sheet carries no knockback of its own (the weapons fold it)
	assert_bool(Run.player_sheet.get_stat("knockback", 0.0) == 0.0).is_true()
	_evolve("mule_kick")
	assert_float(w.stat("knockback")).is_equal_approx(kb0 * (1.0 + _evo_value("bucking_bronco", "knockback")), 0.0001)
	assert_float(Run.player_sheet.get_stat("bronco_chance")).is_equal_approx(_evo_value("bucking_bronco", "bronco_chance"), 0.0001)


func test_evolving_swaps_the_line_for_its_evolution() -> void:
	for id: String in LINES.keys():
		_evolve(id)
		var evo := str(LINES[id])
		assert_bool(Run.passives.has(id)).is_false()
		assert_bool(Run.passives.has(evo)).is_true()
		assert_int(Run.held_lines().size()).is_equal(1)
		var twist := str(TWIST[evo])
		assert_float(Run.player_sheet.get_stat(twist)).override_failure_message(twist).is_equal_approx(_evo_value(evo, twist), 0.0001)
		# out again, so the next one has a slot
		Run.debug_set_item("passive", evo, 0)
		assert_float(Run.player_sheet.get_stat(twist)).is_equal(0.0)


# ---------------------------------------------------------------- debuff duration (Slow Burn)

func test_slow_burn_stretches_every_status_the_hero_puts_on() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(4):
		Run.add_or_level_passive("slow_burn")
	em.refresh_player_stats()
	var m := pow(1.0 + _per("slow_burn").value, 4.0)
	assert_float(em.debuff_mult()).is_equal_approx(m, 0.0001)
	var a := _creature(em, Vector3(5, 0, 0))
	var b := _creature(em, Vector3(-5, 0, 0))
	em.poison(a, "x", 2.0, 1, 4.0)
	assert_float(float(em.poison_src[a]["x"]["t"])).is_equal_approx(4.0 * m, 0.001)
	em.ignite(a, "y", 2.0, 3.0, 0.0)
	assert_float(float(em.fire_src[a]["y"]["t"])).is_equal_approx(3.0 * m, 0.001)
	em.slow(a, 0.3, 2.0)
	assert_float(em.slow_t[a]).is_equal_approx(2.0 * m, 0.001)
	# pass 70: a freeze and a stun stretch too (they never did before)
	em.freeze(b, 1.0)
	assert_float(em.freeze_t[b]).is_equal_approx(m, 0.001)
	em.stun(a, 1.0)
	assert_float(em.stun_t[a]).is_equal_approx(m, 0.001)
	# a hero's perk (or a caller that stretched already) passes scaled = false
	em.stun_t[a] = 0.0
	em.stun(a, 1.0, false)
	assert_float(em.stun_t[a]).is_equal_approx(1.0, 0.001)
	em.freeze_t[b] = 0.0
	em.freeze(b, 1.0, false)
	assert_float(em.freeze_t[b]).is_equal_approx(1.0, 0.001)
	# a launch is a throw, not a debuff: its air time is its own
	var c := _creature(em, Vector3(0, 0, 8))
	assert_bool(em.launch(c, 3.0, 0.9, 0.0, "x")).is_true()
	assert_float(em.lift_t[c]).is_equal_approx(0.9, 0.001)


# ---------------------------------------------------------------- Prairie Fire

func test_prairie_fire_hands_an_ending_burn_and_a_dying_poison_on() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_evolve("slow_burn")
	em.refresh_player_stats()
	var hops := int(round(_evo_value("prairie_fire", "debuff_jump")))
	assert_int(hops).is_greater(0)
	var m := em.debuff_mult()
	var a := _creature(em, Vector3(0, 0, 0))
	var b := _creature(em, Vector3(2, 0, 0))
	var far := _creature(em, Vector3(30, 0, 0))
	em.ignite(a, "x", 1.0, 2.0, 0.0)
	# the burn runs out on a: it jumps to b, the nearest, at its full seconds, one hop down
	em._tick_fire(a, 2.0 * m + 0.01)
	assert_bool(em.is_burning(a)).is_false()
	assert_bool((em.fire_src[b] as Dictionary).has("x")).is_true()
	assert_float(float(em.fire_src[b]["x"]["t"])).is_equal_approx(2.0 * m, 0.001)
	assert_int(int(em.fire_src[b]["x"]["hops"])).is_equal(1)
	assert_bool(em.is_burning(far)).is_false()
	assert_int(em.prairie_jumps).is_equal(1)
	# a source that has jumped its last time stays where it ends
	(em.fire_src[b]["x"] as Dictionary)["hops"] = hops
	em._tick_fire(b, 2.0 * m + 0.01)
	assert_bool(em.is_burning(a)).is_false()
	assert_int(em.prairie_jumps).is_equal(1)
	# a poisoned creature that dies hands its poison on
	var c := _creature(em, Vector3(10, 0, 0), "skeleton", 1.0)
	var d := _creature(em, Vector3(11.5, 0, 0))
	em.poison(c, "p", 3.0, 2, 5.0)
	em.damage(c, 100000.0, "x")
	assert_bool(em.is_alive(c) and em.state[c] != EnemyManager.STATE_DYING).is_false()
	assert_bool(em.is_poisoned(d)).is_true()
	assert_float(float(em.poison_src[d]["p"]["t"])).is_equal_approx(5.0 * m, 0.001)
	assert_int(int(em.poison_src[d]["p"]["stacks"])).is_equal(2)
	# never a fire onto the boss
	var e := _creature(em, Vector3(40, 0, 0))
	var boss := _creature(em, Vector3(41, 0, 0))
	em.boss_index = boss
	em.ignite(e, "z", 1.0, 1.0, 0.0)
	em._tick_fire(e, 1.0 * m + 0.01)
	assert_bool(em.is_burning(boss)).is_false()
	em.boss_index = -1


func test_without_prairie_fire_nothing_jumps() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(0, 0, 0))
	var b := _creature(em, Vector3(1, 0, 0))
	em.ignite(a, "x", 1.0, 1.0, 0.0)
	em._tick_fire(a, 1.01)
	assert_bool(em.is_burning(b)).is_false()
	assert_int(em.prairie_jumps).is_equal(0)


# ---------------------------------------------------------------- Bucking Bronco

func test_bucking_bronco_throws_plain_creatures_up_and_away() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_give(em, "bronco_chance", "add", 1.0)
	var a := _creature(em, Vector3(5, 0, 0))
	var x0: float = em.pos[a].x
	em.damage(a, 1.0, "revolver", Vector3(1, 0, 0), 6.0)
	assert_bool(em.is_launched(a)).is_true()
	assert_int(em.bronco_launches).is_equal(1)
	# up and away along the knock, the shove replaced by the flight
	var top := 0.0
	for k in range(int(EnemyManager.BRONCO_AIR / DT) + 10):
		em._physics_process(DT)
		top = maxf(top, em.lift_h[a])
	assert_bool(em.is_launched(a)).is_false()
	assert_float(top).is_greater(EnemyManager.BRONCO_HEIGHT * 0.8)
	# pass 72: the throw's distance at the map's share of the hero's pushes (hero_knockback_mult)
	assert_float(em.pos[a].x - x0).is_greater(EnemyManager.BRONCO_AWAY_MIN * 0.8 * em.hero_knock_mult())
	# no fall damage: it was hit for 1
	assert_float(em.hp[a]).is_greater(em.max_hp[a] - 1.5)
	# a boss, an Elite or an elite-modded creature only takes the knock
	var mod: EliteModDef = Registry.elites_list()[0]
	var b := _creature(em, Vector3(-5, 0, 0), "skeleton", 50.0, mod)
	em.damage(b, 1.0, "revolver", Vector3(-1, 0, 0), 6.0)
	assert_bool(em.is_launched(b)).is_false()
	assert_float(em.kb[b].length()).is_greater(0.5)
	var c := _creature(em, Vector3(0, 0, 9))
	em.boss_index = c
	em.damage(c, 1.0, "revolver", Vector3(0, 0, 1), 6.0)
	assert_bool(em.is_launched(c)).is_false()
	em.boss_index = -1
	# nothing the hero did not send: no weapon id, the revive, a loose rocket
	var d := _creature(em, Vector3(0, 0, -9))
	for wid: String in ["", "revive", "loose_rocket"]:
		em.damage(d, 1.0, wid, Vector3(0, 0, -1), 6.0)
		assert_bool(em.is_launched(d)).override_failure_message("thrown by '%s'" % wid).is_false()
	# a hit without a knock throws nothing
	em.damage(d, 1.0, "revolver")
	assert_bool(em.is_launched(d)).is_false()


func test_bucking_bronco_rolls_its_chance() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_evolve("mule_kick")
	em.refresh_player_stats()
	var ch := _evo_value("bucking_bronco", "bronco_chance")
	var a := _creature(em, Vector3(5, 0, 0))
	assert_bool(em._bronco_kick(a, Vector3(1, 0, 0), 5.0, "revolver", minf(ch + 0.05, 0.999))).is_false()
	assert_bool(em.is_launched(a)).is_false()
	assert_bool(em._bronco_kick(a, Vector3(1, 0, 0), 5.0, "revolver", ch * 0.5)).is_true()
	assert_bool(em.is_launched(a)).is_true()
	# one in the air is not thrown again
	assert_bool(em._bronco_kick(a, Vector3(1, 0, 0), 5.0, "revolver", 0.0)).is_false()
	# the flight's length follows the push, within its bounds
	var e: Dictionary = em._launched[a]
	var dist := (e["drift"] as Vector3).length() * EnemyManager.BRONCO_AIR
	# pass 72: within its bounds times the map's share of the hero's pushes (hero_knockback_mult)
	var hk := em.hero_knock_mult()
	assert_float(dist).is_between(EnemyManager.BRONCO_AWAY_MIN * hk - 0.001, EnemyManager.BRONCO_AWAY_MAX * hk + 0.001)


# ---------------------------------------------------------------- Tin Star, Marshal's Star

func test_tin_star_cuts_the_damage_taken() -> void:
	var p := _hero()
	var per := _per("tin_star").value
	_hit(p, 50.0)
	var lost0 := p.max_hp - p.hp
	assert_float(lost0).is_equal_approx(50.0, 0.01)
	for lv in range(1, 5):
		Run.add_or_level_passive("tin_star")
		p.refresh_stats()
		p.hp = p.max_hp
		_hit(p, 50.0)
		assert_float(p.max_hp - p.hp).override_failure_message("level %d" % lv).is_equal_approx(50.0 * (1.0 - per * lv), 0.01)


func test_marshals_star_blocks_a_whole_hit_then_recharges() -> void:
	var p := _hero()
	assert_object(p.star_guard).is_null()
	_evolve("tin_star")
	p.refresh_stats()
	assert_object(p.star_guard).is_not_null()
	assert_bool(p.star_guard.is_ready()).is_true()
	var dr := _evo_value("marshals_star", "damage_reduction")
	var every := _evo_value("marshals_star", "star_block_every")
	# the first hit: nothing taken, logged as the star's, the blink after a hit
	_hit(p, 40.0)
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)
	assert_str(p.last_outcome).is_equal("shield")
	assert_int(p.star_guard.blocks).is_equal(1)
	assert_float(p.invuln).is_greater(0.0)
	# pass 73 (lane CARDS): the log names the card by its name (The Emperor Risen since the cards)
	assert_bool(p.damage_log_text().contains(Registry.passive("marshals_star").display_name)).is_true()
	# spent: the next one lands, less its damage reduction
	assert_bool(p.star_guard.is_ready()).is_false()
	assert_float(p.star_guard.seconds_left()).is_equal_approx(every, 0.01)
	_hit(p, 40.0)
	assert_float(p.max_hp - p.hp).is_equal_approx(40.0 * (1.0 - dr), 0.01)
	# back after its seconds on the buffs' clock
	Run.elapsed += every + 0.01
	assert_bool(p.star_guard.is_ready()).is_true()
	var hp0 := p.hp
	_hit(p, 40.0)
	assert_float(p.hp).is_equal_approx(hp0, 0.001)
	assert_int(p.star_guard.blocks).is_equal(2)


func test_the_star_waits_on_an_evade_and_the_shield_power_up() -> void:
	var p := _hero()
	_evolve("tin_star")
	p.refresh_stats()
	# the power-up's bubble takes the hit first: the star stays ready
	p.shield(2.0)
	_hit(p, 40.0)
	assert_int(p.star_guard.blocks).is_equal(0)
	assert_bool(p.star_guard.is_ready()).is_true()
	p.shield_t = 0.0
	# a certain evade too
	Run.player_sheet.add_effects([Effect.make("evade", "add", 5.0, "player")], "test")
	p.refresh_stats()
	# evade is capped at 90% (Player.take_damage): a fixed seed whose first roll is under it, so the evade is certain
	# (the lead: the full suite failed this one time in ten)
	seed(1)
	_hit(p, 40.0)
	assert_str(p.last_outcome).is_equal("evaded")
	assert_int(p.star_guard.blocks).is_equal(0)


# ---------------------------------------------------------------- Mother Lode, Eureka

func test_mother_lode_sweeps_the_screens_gems_in_now_and_then() -> void:
	var w := _world()
	var pm: PickupManager = w["pm"]
	var gems: Array = []
	for at: Vector3 in [Vector3(8, 0, 0), Vector3(0, 0, -14), Vector3(-20, 0, 6)]:
		gems.append(pm.spawn(PickupManager.KIND_GEM_S, at, 1.0))
	var coin := pm.spawn(PickupManager.KIND_COIN, Vector3(0, 0, 9), 1.0)
	for k in range(90):
		pm._physics_process(DT)
	for i: int in gems + [coin]:
		assert_int(pm.flying[i]).is_equal(0)
	# no sweep without the item
	for k in range(120):
		pm._tick_gem_sweep(DT, Vector3.ZERO)
	assert_int(pm.gem_sweeps).is_equal(0)
	_evolve("lodestone")
	assert_float(Run.player_sheet.get_stat("magnet")).is_greater(1.5 * pow(1.0 + _per("lodestone").value, 4.0))
	# the first sweep a moment after it is taken: every gem comes, never the coin
	for k in range(int(PickupManager.GEM_SWEEP_FIRST / DT) + 2):
		pm._tick_gem_sweep(DT, Vector3.ZERO)
	assert_int(pm.gem_sweeps).is_equal(1)
	assert_int(pm.gem_sweep_last).is_equal(3)
	for i: int in gems:
		assert_int(pm.flying[i]).is_equal(1)
	assert_int(pm.flying[coin]).is_equal(0)
	# then every `gem_sweep_every` seconds
	var every := _evo_value("mother_lode", "gem_sweep_every")
	for k in range(int(every / DT) - 5):
		pm._tick_gem_sweep(DT, Vector3.ZERO)
	assert_int(pm.gem_sweeps).is_equal(1)
	for k in range(10):
		pm._tick_gem_sweep(DT, Vector3.ZERO)
	assert_int(pm.gem_sweeps).is_equal(2)


func test_eureka_strikes_a_vein_of_gems() -> void:
	var w := _world()
	var pm: PickupManager = w["pm"]
	var skel: EnemyDef = Registry.enemy("skeleton")
	var n0 := pm.count
	assert_bool(pm.vein(skel, Vector3(4, 0, 4), 1.0, 0.0)).is_false()
	assert_int(pm.count).is_equal(n0)
	assert_bool(pm.vein(skel, Vector3(4, 0, 4), 1.0, 1.0)).is_true()
	assert_int(pm.count - n0).is_equal(PickupManager.VEIN_GEMS)
	assert_int(pm.veins).is_equal(1)
	# the gems burst out round the spot and land on the sand
	for k in range(120):
		pm._physics_process(DT)
	var spread := 0.0
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1 and pm.kind[i] <= PickupManager.KIND_GEM_L:
			spread = maxf(spread, Vector2(pm.pos[i].x - 4.0, pm.pos[i].z - 4.0).length())
	assert_float(spread).is_greater(1.0)
	# with Eureka held, Prospector's roll strikes it (its chance from the sheet)
	_evolve("prospector")
	Run.player_sheet.add_effects([Effect.make("vein_chance", "add", 1.0, "player")], "test")
	var v0 := pm.veins
	pm.prospector(skel, Vector3(-4, 0, -4), 1.0, 0.0)
	assert_int(pm.veins).is_equal(v0 + 1)


# ---------------------------------------------------------------- Gold Rush

func test_gold_rush_turns_gold_gained_into_attack_damage() -> void:
	var might0 := Run.player_sheet.get_stat("might")
	# gold before it is held counts for nothing
	Run.add_gold(500, "test")
	_evolve("gold_tooth")
	assert_float(Run.gold_rush_bonus()).is_equal(0.0)
	var greed := Run.player_sheet.get_stat("greed")
	var per := _evo_value("gold_rush", "gold_might")
	Run.add_gold(150, "test")
	var got := int(round(150 * greed))
	assert_int(Run.gold_rush_gold).is_equal(got)
	var want := floorf(float(got) / Run.GOLD_RUSH_PER) * per
	assert_float(Run.gold_rush_bonus()).is_equal_approx(want, 0.0001)
	assert_float(Run.player_sheet.get_stat("might")).is_equal_approx(might0 * (1.0 + want), 0.0001)
	# a weapon's damage follows
	var w := Run.add_weapon(Registry.weapon("revolver"), 1)
	var d0 := w.stat("damage")
	Run.add_gold(int(ceil(Run.GOLD_RUSH_PER * 3.0 / greed)) + 1, "test")
	assert_float(w.stat("damage")).is_greater(d0)
	# spending takes nothing back, and it never passes its cap
	var b := Run.gold_rush_bonus()
	Run.spend_gold(50, "test")
	assert_float(Run.gold_rush_bonus()).is_equal_approx(b, 0.0001)
	Run.add_gold(1000000, "test")
	assert_float(Run.gold_rush_bonus()).is_equal_approx(Run.GOLD_RUSH_CAP, 0.0001)
	# a new run starts from nothing
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_int(Run.gold_rush_gold).is_equal(0)
	assert_float(Run.gold_rush_bonus()).is_equal(0.0)


# ---------------------------------------------------------------- the words

func test_the_cards_say_the_lines_and_their_twists_in_short() -> void:
	assert_str(TextGen.describe_effect(_per("mule_kick"))).is_equal("+25% knockback, all weapons")
	assert_str(TextGen.describe_effect(_per("lodestone"))).is_equal("+40% pickup radius")
	assert_str(TextGen.describe_effect(_per("tin_star"))).is_equal("+5% damage reduction")
	assert_str(TextGen.describe_effect(_per("slow_burn"))).is_equal("+20% debuff duration")
	var words := {
		"mother_lode": "every gem on the screen flies to you every 12 s",
		"bucking_bronco": "+35% chance a knocked-back enemy is launched",
		"prairie_fire": "a burn or poison that ends jumps to the nearest enemy, up to 3 times",
		"marshals_star": "a star blocks a whole hit every 10 s",
		"eureka": "+4% chance a kill bursts into 5 XP gems",
		"gold_rush": "+1% attack damage per 100 gold gained"}
	for id: String in words.keys():
		var d := TextGen.passive_description(Registry.passive(id), 1)
		assert_bool(d.to_lower().contains(str(words[id]).to_lower())).override_failure_message(id + ": " + d).is_true()
	# a rule's number in its unit on a pause row, and its wait shorter is better
	assert_str(TextGen.format_value("star_block_every", 10.0)).is_equal("10 s")
	assert_str(TextGen.format_value("debuff_jump", 3.0)).is_equal("3")
	assert_bool(TextGen.LOWER_BETTER.has("gem_sweep_every")).is_true()
	# the line cards read per level, and the evolution's card all it is
	var ms := TextGen.passive_description(Registry.passive("marshals_star"), 1)
	assert_str(ms).is_equal("+25% damage reduction, a star blocks a whole hit every 10 s.")
	var mk := TextGen.passive_description(Registry.passive("mule_kick"), 2)
	assert_bool(mk.begins_with("+25% knockback, all weapons per level. Level 2:")).override_failure_message(mk).is_true()
	# each new stat has a default and a name
	for st: String in ["bronco_chance", "debuff_jump", "star_block_every", "gem_sweep_every", "vein_chance", "gold_might"]:
		assert_bool(StatSheet.PLAYER_DEFAULTS.has(st)).override_failure_message(st).is_true()
		assert_bool(TextGen.STATS.has(st)).override_failure_message(st).is_true()
