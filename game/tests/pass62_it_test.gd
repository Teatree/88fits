extends GdUnitTestSuite

## Pass 62, lane IT (Garry's list): the Pocket Watch (a passive item: power-ups picked up off the ground last longer every
## level, and drop a little more often at levels 1, 3 and 5; structures, Pollen and Barrel Rush untouched), the pierce
## drop-off (params.pierce_falloff {step, floor, first_mult} on the Boomstick, Tommy Gun, Revolver, Spear, Turret Buddy and
## their evolutions: the n-th enemy one shot or one thrust strikes takes first_mult x max(step^(n-1), floor); a shot fired
## with no pierce, a ricochet and every blast untouched; Settings.pierce_falloff off = the old numbers exactly) and the
## Spit Cactus's spit (ranged.land_only: no hit in flight, the landing splash in a red ring; 10 % slower; ranged.trail, a
## faint trail of its own; ranged.pulse, a breath and a halo).

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
var rings: Array = []
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
func fx_lightning(_points) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(at: Vector3, r: float, dur: float, _col: Color, _filled := true) -> void:
	rings.append({"at": at, "r": r, "dur": dur})
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
var hits: Array = []
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return true
func take_damage(a: float, _f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "info": i})
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

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const FAKE_PICKUPS := """extends Node
var dropped := 0
func spawn_special(_def, _at, _quiet := false) -> void:
	dropped += 1
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Settings.pierce_falloff = true
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Settings.pierce_falloff = true
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks.
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


## A tough creature standing where it was put.
func _creature(em: EnemyManager, at: Vector3, id := "skeleton", hp_mult := 50.0) -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	return i


func _lost(em: EnemyManager, i: int) -> float:
	return em.max_hp[i] - em.hp[i]


## What a hit of `amount` takes off creature `i` (its damage reduction in).
func _taken(em: EnemyManager, i: int, amount: float) -> float:
	return amount * (1.0 - em.dr[i])


## One round down +X from the hero's side through whatever stands there, flown until it is gone.
func _shoot(w: Dictionary, inst: WeaponInstance, dmg: float, pierce: int) -> void:
	var pm: ProjectileManager = w["pm"]
	var k := pm.register_kind(SphereMesh.new(), null)
	var j := pm.fire(k, Vector3(0.5, 0.8, 0), Vector3(22, 0, 0), dmg, pierce, 0.16, 1.0, inst, 0.0)
	assert_int(j).is_greater_equal(0)
	var s := 0.0
	while pm.alive[j] == 1 and s < 1.5:
		pm._physics_process(DT)
		s += DT


# ---------------------------------------------------------------- 1. the Pocket Watch

func test_the_pocket_watch_is_an_uncommon_passive_item_of_five_levels() -> void:
	var pw := Registry.passive("pocket_watch")
	assert_object(pw).is_not_null()
	assert_bool(pw.is_line()).is_false()
	assert_str(pw.rarity).is_equal("uncommon")
	assert_int(pw.max_level).is_equal(5)
	assert_str(pw.display_name).is_equal("Pocket Watch")
	assert_bool(FileAccess.file_exists("res://content/passives/pocket_watch/pocket_watch_icon.png")).is_true()
	# open from the first run: no quest names it
	assert_bool(Registry.unlocked_passives().has(pw)).is_true()
	# both stats are known to the sheet and named
	assert_float(float(StatSheet.PLAYER_DEFAULTS["powerup_duration"])).is_equal(1.0)
	assert_float(float(StatSheet.PLAYER_DEFAULTS["powerup_chance"])).is_equal(1.0)
	assert_str(TextGen.stat_name("powerup_duration")).is_equal("power-up duration")
	assert_str(TextGen.stat_name("powerup_chance")).is_equal("power-up drop chance")


func test_every_level_lengthens_the_power_ups_and_levels_1_3_5_raise_the_drop_chance() -> void:
	var want_d := [1.0, 1.15, 1.30, 1.45, 1.60, 1.75]
	var want_c := [1.0, 1.04, 1.04, 1.08, 1.08, 1.12]
	for lv in range(0, 6):
		Run.debug_set_item("passive", "pocket_watch", lv)
		assert_float(Run.player_sheet.get_stat("powerup_duration", 0.0)).override_failure_message("duration at %d" % lv).is_equal_approx(want_d[lv], 0.0001)
		assert_float(Run.player_sheet.get_stat("powerup_chance", 0.0)).override_failure_message("chance at %d" % lv).is_equal_approx(want_c[lv], 0.0001)
		assert_float(Run.powerup_seconds(20.0)).is_equal_approx(20.0 * float(want_d[lv]), 0.001)
	# the card's words: level 1 both stats, level 2 the duration only, the changes each step lists
	var pw := Registry.passive("pocket_watch")
	assert_str(TextGen.describe_effects(pw.effects_at_level(1))).is_equal("+15% power-up duration, +4% power-up drop chance")
	assert_str(TextGen.describe_effects(pw.effects_at_level(2))).is_equal("+15% power-up duration")
	var ch := TextGen.passive_changes(pw, 2, 3)
	assert_int(ch.size()).is_equal(2)
	assert_str(str(ch[0]["after"])).is_equal("+45%")
	assert_str(str(ch[1]["before"])).is_equal("+4%")
	assert_str(str(ch[1]["after"])).is_equal("+8%")
	assert_str(TextGen.passive_description(pw, 5)).contains("+75% power-up duration")
	assert_str(TextGen.passive_description(pw, 5)).contains("+12% power-up drop chance")


func test_the_drop_chance_of_a_kill_grows_with_the_watch() -> void:
	var g: Node = auto_free(Node.new())
	g.set_script(_script("extends Node\nvar map\nvar pickups\n"))
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	var map := MapBase.new()
	g.add_child(map)
	g.set("map", map)
	g.set("pickups", pk)
	add_child(g)
	var wd: WaveDirector = auto_free(WaveDirector.new())
	wd.timeline = Registry.map("red_canyon").timeline
	wd.game = g
	# a skeleton made generous (50 x the map's per-kill chance), so 20,000 kills tell 12 % apart from nothing
	var d: EnemyDef = Registry.enemy("skeleton").duplicate()
	d.pickup_chance_mult = 50.0
	d.pickup_weights = {}
	var counts: Array = []
	for lv in [0, 5]:
		Run.debug_set_item("passive", "pocket_watch", lv)
		assert_float(wd.powerup_chance_mult()).is_equal_approx(1.0 if lv == 0 else 1.12, 0.0001)
		pk.set("dropped", 0)
		wd._rng.seed = 62
		for n in range(20000):
			wd.drop_pickup_from(d, Vector3.ZERO, false)
		counts.append(int(pk.get("dropped")))
	var ratio := float(counts[1]) / float(maxi(int(counts[0]), 1))
	assert_float(ratio).override_failure_message("drops %s" % str(counts)).is_between(1.07, 1.17)


## A real Game: Berserk and Sprint and the Shield picked up last 1.75 x at level 5; a structure's buff keeps its seconds.
func test_power_ups_off_the_ground_last_longer_and_a_structure_does_not() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	g.director.stop()
	Run.debug_set_item("passive", "pocket_watch", 5)
	var at: Vector3 = g.player.global_position
	for id in ["rage", "sprint"]:
		var def: PickupDef = Registry.pickup(id)
		g.apply_pickup(def, at)
		var left := -1.0
		for tb: Dictionary in Run.timed:
			if str(tb["id"]) == id:
				left = float(tb["until"]) - Run.buff_clock()
		assert_float(left).override_failure_message(id).is_equal_approx(def.duration * 1.75, 0.05)
	g.apply_pickup(Registry.pickup("shield"), at)
	assert_float(g.player.shield_t).is_equal_approx(Registry.pickup("shield").duration * 1.75, 0.05)
	# the War Drum's buff: its own 30 s, the watch does nothing to it
	var drum: StructureDef = Registry.structure("war_drum")
	g.use_structure(drum, at)
	var dl := -1.0
	for tb: Dictionary in Run.timed:
		if str(tb["id"]) == "structure:war_drum":
			dl = float(tb["until"]) - Run.buff_clock()
	assert_float(dl).is_equal_approx(float(drum.params.get("seconds", 30.0)), 0.05)
	# without the watch a power-up is its own length again
	Run.debug_set_item("passive", "pocket_watch", 0)
	g.apply_pickup(Registry.pickup("sprint"), at)
	for tb: Dictionary in Run.timed:
		if str(tb["id"]) == "sprint":
			assert_float(float(tb["until"]) - Run.buff_clock()).is_equal_approx(Registry.pickup("sprint").duration, 0.05)


# ---------------------------------------------------------------- 2. the pierce drop-off

func test_the_five_weapons_and_their_evolutions_carry_the_drop_off() -> void:
	var want := {"tommy_gun": 1.15, "chicago_typewriter": 1.2, "revolver": 1.15, "golden_revolver": 1.15, "boomstick": 1.1,
		"pike": 1.15, "thunder_lance": 1.2, "turret_buddy": 1.1, "iron_bastion": 1.1}
	for id: String in want.keys():
		var pf = Registry.weapon(id).params.get("pierce_falloff")
		assert_bool(pf is Dictionary).override_failure_message(id).is_true()
		assert_float(float(pf["step"])).is_equal_approx(0.8, 0.0001)
		assert_float(float(pf["floor"])).is_equal_approx(0.4, 0.0001)
		assert_float(float(pf["first_mult"])).override_failure_message(id).is_equal_approx(float(want[id]), 0.0001)
	# the Blunderbuss blasts a cone (its pellets are only seen): nothing to drop off
	assert_bool(Registry.weapon("blunderbuss").params.has("pierce_falloff")).is_false()
	# the factor: first_mult, then step of the one before, never under floor of the first
	var pf0 := {"step": 0.8, "floor": 0.4, "first_mult": 1.15}
	assert_float(ProjectileManager.falloff_factor(pf0, 1)).is_equal_approx(1.15, 0.0001)
	assert_float(ProjectileManager.falloff_factor(pf0, 2)).is_equal_approx(1.15 * 0.8, 0.0001)
	assert_float(ProjectileManager.falloff_factor(pf0, 3)).is_equal_approx(1.15 * 0.64, 0.0001)
	assert_float(ProjectileManager.falloff_factor(pf0, 9)).is_equal_approx(1.15 * 0.4, 0.0001)
	assert_float(ProjectileManager.falloff_factor({}, 3)).is_equal(1.0)


func test_a_tommy_gun_round_through_three_hits_harder_first_then_less_each() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(2, 0, 0))
	var b := _creature(em, Vector3(4, 0, 0))
	var c := _creature(em, Vector3(6, 0, 0))
	var inst := _inst("tommy_gun")
	assert_int(inst.stat_int("pierce", 0)).is_equal(2)
	_shoot(w, inst, 10.0, 2)
	assert_float(_lost(em, a)).is_equal_approx(_taken(em, a, 10.0 * 1.15), 0.001)
	assert_float(_lost(em, b)).is_equal_approx(_taken(em, b, 10.0 * 1.15 * 0.8), 0.001)
	assert_float(_lost(em, c)).is_equal_approx(_taken(em, c, 10.0 * 1.15 * 0.64), 0.001)


func test_two_met_in_one_tick_the_nearer_along_the_flight_takes_the_first_hit() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# the far one spawned first, so the crowd's own order would take it first
	var far := _creature(em, Vector3(3.35, 0, 0.05))
	var near := _creature(em, Vector3(3.0, 0, -0.05))
	_shoot(w, _inst("tommy_gun"), 10.0, 2)
	assert_float(_lost(em, near)).is_equal_approx(_taken(em, near, 11.5), 0.001)
	assert_float(_lost(em, far)).is_equal_approx(_taken(em, far, 11.5 * 0.8), 0.001)


func test_switched_off_every_hit_is_the_old_number() -> void:
	Settings.pierce_falloff = false
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids := [_creature(em, Vector3(2, 0, 0)), _creature(em, Vector3(4, 0, 0)), _creature(em, Vector3(6, 0, 0))]
	_shoot(w, _inst("tommy_gun"), 10.0, 2)
	for i: int in ids:
		assert_float(_lost(em, i)).is_equal_approx(_taken(em, i, 10.0), 0.001)
	# and the Spear's thrust
	var t := _thruster(w, "pike")
	var j := _creature(em, Vector3(-1.5, 0, 0))
	var k := _creature(em, Vector3(-3.0, 0, 0))
	t._dir = Vector3(-1, 0, 0)
	t._active = 1
	assert_bool(t._strike(t.stat("range", 0.0), 0.7, 0.0, 0.0)).is_true()
	assert_float(_lost(em, j)).is_equal_approx(_taken(em, j, t.stat("damage", 0.0)), 0.001)
	assert_float(_lost(em, k)).is_equal_approx(_taken(em, k, t.stat("damage", 0.0)), 0.001)


func test_a_shot_fired_with_no_pierce_and_a_bounced_one_are_untouched() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	# the Boomstick before level 5 does not pierce: one creature, the plain damage, no first_mult
	var bs := _inst("boomstick", [], 1)
	assert_int(bs.stat_int("pierce", 0)).is_equal(0)
	var a := _creature(em, Vector3(3, 0, 0))
	var b := _creature(em, Vector3(5, 0, 0))
	_shoot(w, bs, 10.0, 0)
	assert_float(_lost(em, a)).is_equal_approx(_taken(em, a, 10.0), 0.001)
	assert_float(_lost(em, b)).is_equal(0.0)
	# a shot that bounced (a ricochet, the Golden Revolver's hops) is a new shot: no drop-off on it
	var k := pm.register_kind(SphereMesh.new(), null)
	var j := pm.fire(k, Vector3(10, 0.8, 10), Vector3(22, 0, 0), 10.0, 2, 0.16, 1.0, _inst("golden_revolver"), 0.0)
	assert_bool(pm._falloff_of(j, pm.weapon[j]).is_empty()).is_false()
	pm.extra[j]["bounced"] = true
	assert_bool(pm._falloff_of(j, pm.weapon[j]).is_empty()).is_true()


func test_the_boomstick_at_level_5_and_the_iron_bastion_pierce_once() -> void:
	for id in ["boomstick", "iron_bastion"]:
		var w := _world()
		var em: EnemyManager = w["em"]
		var inst := _inst(id, [], 5 if id == "boomstick" else 1)
		assert_int(inst.stat_int("pierce", 0)).override_failure_message(id).is_equal(1)
		var a := _creature(em, Vector3(2, 0, 0))
		var b := _creature(em, Vector3(4, 0, 0))
		var c := _creature(em, Vector3(6, 0, 0))
		_shoot(w, inst, 10.0, inst.stat_int("pierce", 0))
		assert_float(_lost(em, a)).override_failure_message(id).is_equal_approx(_taken(em, a, 11.0), 0.001)
		assert_float(_lost(em, b)).override_failure_message(id).is_equal_approx(_taken(em, b, 8.8), 0.001)
		assert_float(_lost(em, c)).is_equal(0.0)


func _spawner(w: Dictionary, id: String, muts: Array = [], level := 1) -> Spawner:
	var sp := Spawner.new()
	(w["g"] as Node).add_child(sp)
	sp.setup(_inst(id, muts, level), w["g"])
	return sp


## A real Turret Buddy turret: its round goes through ProjectileManager with the weapon's instance; it does not pierce,
## so the drop-off (on) changes nothing: the first creature takes the turret's plain damage, the one behind nothing.
func test_turret_buddy_rounds_do_not_pierce_so_they_hit_as_before() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var a := _creature(em, Vector3(4, 0, 0))
	var b := _creature(em, Vector3(5.5, 0, 0))
	var sp := _spawner(w, "turret_buddy")
	assert_int(sp.inst.stat_int("pierce", 0)).is_equal(0)
	assert_bool(sp.inst.params.has("pierce_falloff")).is_true()
	var t := Turret.new()
	t.setup(sp, sp._proto, sp._turret_mesh, sp._turret_mat)
	(w["g"] as Node).add_child(t)
	t.global_position = Vector3.ZERO
	t.scale = Vector3.ONE
	var frames := 0
	while t.shots == 0 and frames < 240:
		t._process(DT)
		frames += 1
	assert_int(t.shots).is_equal(1)
	var s := 0.0
	while s < 1.2:
		pm._physics_process(DT)
		s += DT
	var dmg := sp.inst.stat("damage", 0.0)
	assert_float(_lost(em, a) + _lost(em, b)).is_equal_approx(_taken(em, a, dmg), 0.001)
	# and its description says nothing of a drop-off it never has
	assert_str(sp.inst.description()).not_contains("less than the one before")


func _thruster(w: Dictionary, id: String, muts: Array = [], level := 1) -> Thruster:
	var t := Thruster.new()
	(w["g"] as Node).add_child(t)
	t.setup(_inst(id, muts, level), w["g"])
	return t


func test_the_spears_thrust_drops_off_by_distance_along_its_line() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike")
	var reach := t.stat("range", 0.0)
	# the farthest spawned first: the order along the blade decides, not the crowd's
	var c := _creature(em, Vector3(3.6, 0, 0))
	var a := _creature(em, Vector3(1.2, 0, 0))
	var b := _creature(em, Vector3(2.4, 0, 0))
	var off := _creature(em, Vector3(0, 0, 3.0))
	t._dir = Vector3(1, 0, 0)
	t._active = 1
	assert_bool(t._strike(reach, 0.7, 0.0, 0.0)).is_true()
	var d := t.stat("damage", 0.0)
	assert_float(_lost(em, a)).is_equal_approx(_taken(em, a, d * 1.15), 0.001)
	assert_float(_lost(em, b)).is_equal_approx(_taken(em, b, d * 1.15 * 0.8), 0.001)
	assert_float(_lost(em, c)).is_equal_approx(_taken(em, c, d * 1.15 * 0.64), 0.001)
	assert_float(_lost(em, off)).is_equal(0.0)
	# its words say it while it is on, and nothing when it is off
	assert_str(t.inst.description()).contains("The first enemy along the thrust takes 15% more, each one behind it 20% less than the one before.")
	Settings.pierce_falloff = false
	assert_str(t.inst.description()).not_contains("less than the one before")


func test_each_spear_of_a_fan_counts_its_own_line() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike", [], 5)
	assert_int(t.stat_int("amount", 0)).is_equal(2)
	t._dir = Vector3(1, 0, 0)
	t._active = 2
	var fan := deg_to_rad(60.0)
	# one creature down each blade, then one behind on the first (their radius pinned: the variance's size jitter would
	# let a wide one reach both blades)
	var d0 := Vector3(1, 0, 0).rotated(Vector3.UP, -fan * 0.5)
	var d1 := Vector3(1, 0, 0).rotated(Vector3.UP, fan * 0.5)
	var a := _creature(em, d0 * 1.5)
	var b := _creature(em, d1 * 1.5)
	var c := _creature(em, d0 * 3.2)
	for i: int in [a, b, c]:
		em.radius[i] = 0.5
	var ranks := t._thrust_ranks(em.indices_in_radius(Vector3.ZERO, 6.0), t.stat("range", 0.0), 0.7, fan, 0.0)
	assert_int(int(ranks[a])).is_equal(1)
	assert_int(int(ranks[b])).is_equal(1)
	assert_int(int(ranks[c])).is_equal(2)


func test_a_sweep_and_birdshots_lane_are_untouched() -> void:
	# Wide Sweep slices: an area swing, not a pierce; the same with the drop-off on and off
	var lost := []
	for on in [true, false]:
		Settings.pierce_falloff = on
		var w := _world()
		var em: EnemyManager = w["em"]
		var t := _thruster(w, "pike", ["pike_sweep"])
		var a := _creature(em, Vector3(1.5, 0, 0))
		var b := _creature(em, Vector3(3.0, 0, 0))
		t._dir = Vector3(1, 0, 0)
		t._active = 1
		t._cut(atan2(-1.0, 0.0), -0.5, 0.5, t.stat("range", 0.0), 0.7, 1.0)
		lost.append([_lost(em, a), _lost(em, b)])
		assert_str(t.inst.description()).not_contains("less than the one before")
	assert_float(float(lost[0][0])).is_greater(0.0)
	assert_float(float(lost[0][0])).is_equal_approx(float(lost[1][0]), 0.0001)
	assert_float(float(lost[0][1])).is_equal_approx(float(lost[1][1]), 0.0001)
	# Birdshot's lane: a blast, the same on and off
	var lane := []
	for on in [true, false]:
		Settings.pierce_falloff = on
		var w := _world()
		var em: EnemyManager = w["em"]
		var a := _creature(em, Vector3(0, 0, -2.5))
		var b := _creature(em, Vector3(0, 0, -4.5))
		var pe := ProjectileEmitter.new()
		(w["g"] as Node).add_child(pe)
		pe.setup(_inst("boomstick", ["birdshot_lane"], 5), w["g"])
		assert_bool(pe._fire()).is_true()
		for n in range(30):
			pe._tick(DT)
			(w["pm"] as ProjectileManager)._physics_process(DT)
		lane.append([_lost(em, a), _lost(em, b)])
	assert_float(float(lane[0][0])).is_greater(0.0)
	assert_float(float(lane[0][0])).is_equal_approx(float(lane[1][0]), 0.0001)
	assert_float(float(lane[0][1])).is_equal_approx(float(lane[1][1]), 0.0001)


func test_the_words_follow_the_switch() -> void:
	var tg := _inst("tommy_gun")
	assert_str(tg.description()).contains("Pierces 2: the first enemy takes 15% more, each one after it 20% less than the one before.")
	assert_str(tg.description()).not_contains("Pierces 2.")
	assert_str(_inst("iron_bastion").description()).contains("Its rounds pierce 1: the first enemy takes 10% more")
	assert_str(_inst("chicago_typewriter").description()).contains("20% more")
	# no pierce, no words: the Boomstick before level 5, Turret Buddy
	assert_str(_inst("boomstick", [], 1).description()).not_contains("less than the one before")
	assert_str(_inst("boomstick", [], 5).description()).contains("10% more")
	assert_str(_inst("turret_buddy").description()).not_contains("pierce")
	Settings.pierce_falloff = false
	assert_str(tg.description()).not_contains("less than the one before")
	assert_str(tg.description()).contains("Pierces 2.")


func test_the_switch_is_saved_with_the_settings() -> void:
	assert_bool(Settings.to_dict().has("pierce_falloff")).is_true()
	Settings.from_dict({"pierce_falloff": false})
	assert_bool(Settings.pierce_falloff).is_false()
	Settings.from_dict({"pierce_falloff": true})
	assert_bool(Settings.pierce_falloff).is_true()
	# an old save without the key keeps it on
	Settings.pierce_falloff = true
	Settings.from_dict({})
	assert_bool(Settings.pierce_falloff).is_true()


# ---------------------------------------------------------------- 3. the Spit Cactus

## A creature's spit as Game.enemy_spit throws it: a lob from `from` to `target` at `speed`, with its hit info.
func _spit(pm: ProjectileManager, from: Vector3, target: Vector3, speed: float, info: Dictionary, splash := 1.2) -> int:
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var t: float = clampf(maxf(flat.length(), 0.5) / maxf(speed, 1.0), 0.4, 2.0)
	var vy := ((target.y - from.y) + 0.5 * 24.0 * t * t) / t
	var k := pm.register_kind(SphereMesh.new(), null)
	return pm.hostile_shot(k, from, flat / t + Vector3(0, vy, 0), 8.0, splash, t + 0.5, true, {"info": info})


func test_the_cactus_spit_is_slower_land_only_trails_and_breathes_in_its_data() -> void:
	var r: Dictionary = Registry.enemy("spit_cactus").ranged
	assert_float(float(r["projectile_speed"])).is_equal_approx(6.0 * 0.9, 0.0001)
	assert_bool(bool(r.get("land_only", false))).is_true()
	assert_bool(r.get("trail") is Dictionary).is_true()
	assert_bool(r.get("pulse") is Dictionary).is_true()
	# Garry's other numbers kept
	assert_float(float(r["splash"])).is_equal_approx(1.2, 0.0001)
	assert_float(float(r["cooldown"])).is_equal_approx(2.6, 0.0001)
	assert_float(float(r["telegraph"])).is_equal_approx(0.7, 0.0001)


func test_the_cactus_spit_never_hits_in_flight() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	var cactus := _creature(em, Vector3(0, 0, 0), "spit_cactus")
	# the hero right under the spit's climb, a step from the cactus
	hero.global_position = Vector3(0.6, 0, 0)
	var j := _spit(pm, Vector3(0, 0.9, 0), Vector3(6, 0, 0), 5.4, em.hit_info(cactus, "ranged", ["spit"]))
	assert_bool(pm.extra[j].has("land_only")).is_true()
	var s := 0.0
	while pm.alive[j] == 1 and s < 3.0:
		pm._physics_process(DT)
		s += DT
	assert_int((hero.get("hits") as Array).size()).is_equal(0)
	# the same spit from a creature without land_only (no shooter named) hits him on its way up, as every spit did
	var j2 := _spit(pm, Vector3(0, 0.9, 0), Vector3(6, 0, 0), 5.4, {})
	assert_bool(pm.extra[j2].has("land_only")).is_false()
	s = 0.0
	while pm.alive[j2] == 1 and s < 3.0:
		pm._physics_process(DT)
		s += DT
	assert_int((hero.get("hits") as Array).size()).is_equal(1)


func test_the_cactus_spit_hurts_on_landing_inside_its_red_ring_only() -> void:
	# the splash reaches the hero's body touching its ring: within splash 1.2 + 0.4 of where it comes down
	for case in [[0.5, 1], [1.4, 1], [1.85, 0]]:
		var w := _world()
		var em: EnemyManager = w["em"]
		var pm: ProjectileManager = w["pm"]
		var hero: Node3D = w["hero"]
		var g: Node = w["g"]
		var cactus := _creature(em, Vector3(-6, 0, 0), "spit_cactus")
		var target := Vector3(0, 0, 0)
		hero.global_position = target + Vector3(float(case[0]), 0, 0)
		var j := _spit(pm, Vector3(-6, 0.9, 0), target, 5.4, em.hit_info(cactus, "ranged", ["spit"]))
		# the red ring where it comes down: the splash's own radius, for its flight
		var rings: Array = g.get("rings")
		assert_int(rings.size()).is_equal(1)
		assert_float((rings[0]["at"] as Vector3).distance_to(target)).is_less(0.35)
		assert_float(float(rings[0]["r"])).is_equal_approx(1.2, 0.0001)
		var flight: float = float(rings[0]["dur"])
		var s := 0.0
		while pm.alive[j] == 1 and s < 3.0:
			pm._physics_process(DT)
			s += DT
		# the ring lasted the flight (the creatures' clock read the same way)
		assert_float(s * em.hostile_clock()).is_equal_approx(flight * em.hostile_clock(), 0.05)
		assert_int((hero.get("hits") as Array).size()).override_failure_message("hero %.2f m off" % float(case[0])).is_equal(int(case[1]))


func test_the_cactus_spit_has_a_faint_trail_and_breathes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(30, 0, 30)
	var cactus := _creature(em, Vector3(0, 0, 0), "spit_cactus")
	var j := _spit(pm, Vector3(0, 0.9, 0), Vector3(6, 0, 0), 5.4, em.hit_info(cactus, "ranged", ["spit"]))
	var tl: Dictionary = Registry.enemy("spit_cactus").ranged["trail"]
	var lo := 9.0
	var hi := 0.0
	for n in range(30):
		pm._physics_process(DT)
		lo = minf(lo, pm.psize[j])
		hi = maxf(hi, pm.psize[j])
	# beads in its own colour, faint and short-lived
	var last := (pm.trail_next - 1 + ProjectileManager.TRAIL_MAX) % ProjectileManager.TRAIL_MAX
	var c: Color = pm.trail_col[last]
	var want := Color(str(tl["color"]))
	assert_float(c.r).is_equal_approx(want.r, 0.01)
	assert_float(c.g).is_equal_approx(want.g, 0.01)
	assert_float(c.a).is_equal_approx(float(tl["alpha"]), 0.001)
	assert_float(pm.trail_life[last]).is_equal_approx(float(tl["life"]), 0.001)
	# its size breathes either way of its own (0.12 at 3 Hz)
	assert_float(hi).is_greater(1.06)
	assert_float(lo).is_less(0.94)
	# a halo is drawn round it with the trail's beads
	pm._render()
	assert_int(pm._pulse_list.size()).is_equal(1)
	var drawn := pm._draw_pulse_halos(0)
	assert_int(drawn).is_equal(1)
	assert_int(pm._pulse_list.size()).is_equal(0)
