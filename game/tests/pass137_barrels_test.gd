extends GdUnitTestSuite

## Pass 137, lane BARRELS (Garry, 2026-11-09: "Barrels break from damage: if a shot (projectile) flies through it the
## Barrel gets knocked back the first time and the second time it gets destroyed. Wooden 2 shots, Golden 3, Power-up 5. A
## togglable option in the settings, on by default"; answers: flying rounds only, Wooden = the EXP barrel, Golden = EXP +
## Coins, walking into one still breaks it). Pinned here: 2 / 3 / 5 hits break each kind (the map's `shots` overrides),
## every hit before the last moves it along the round's flight (half, or not at all, when the spot is taken), a real
## ProjectileManager round flies on through a barrel without spending pierce and strikes it once, the switch off does
## nothing, walking into a barrel still breaks it at once whatever its hits, a shot break pays exactly what walking pays,
## the grid finds every barrel a round can reach, and the setting is saved and not held in prod.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var hud = null
var director = null
var barrels = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func apply_pickup(_def, _at: Vector3) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
var hip: Node3D = null
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_RIG := """extends Node
var camera: Camera3D = null
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
"""

const FAKE_DIRECTOR := """extends Node
var running := true
var phase := 0
var timeline = null
"""

const DT := 1.0 / 60.0
const EAST := Vector3(1, 0, 0)

var _was_on := true


func before_test() -> void:
	_was_on = Settings.shoot_barrels
	Settings.shoot_barrels = true
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Settings.shoot_barrels = _was_on


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin (no map: flat sand at 0), with the real crowd, shots, effects and pickups,
## a director whose timeline holds `block` as its `barrels` block, and a real BarrelField with a barrel of kind
## `spots[k].z` standing at (spots[k].x, 0, spots[k].y) for every spot (its MultiMeshes made by hand, as pass 112's test).
func _world(spots: Array, block: Dictionary = {}) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var rig := Node.new()
	rig.set_script(_script(FAKE_RIG))
	g.add_child(rig)
	g.camera = rig
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
	var tl := WaveTimeline.new()
	tl.barrels = block
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	d.timeline = tl
	g.director = d
	var pk := PickupManager.new()
	pk.game = g
	g.add_child(pk)
	g.pickups = pk
	var bf := BarrelField.new()
	bf.game = g
	g.add_child(bf)
	g.barrels = bf
	var n := [0, 0, 0]
	for s: Vector3 in spots:
		n[int(s.z)] += 1
	var names := ["_body_dark", "_body_light", "_body_power"]
	for t in range(3):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = int(n[t]) + BarrelField.SPARE
		mm.visible_instance_count = int(n[t])
		bf.set(names[t], mm)
	var k := [0, 0, 0]
	for s: Vector3 in spots:
		var t := int(s.z)
		bf.pos.append(Vector3(s.x, 0.0, s.y))
		bf.light.append(t)
		bf.alive.append(1)
		bf.coins.append(0)
		bf._index_in.append(k[t])
		bf.shadows.append(-1)
		k[t] += 1
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "pk": pk, "bf": bf, "rig": rig}


## One round of the Outlaw's along +X at body height from x0 to x1 (its own memory, so a fresh round each call).
func _round(bf: BarrelField, x0: float, x1: float, z: float = 0.0, r: float = 0.3) -> int:
	return bf.shot_through(Vector3(x0, 0.8, z), Vector3(x1, 0.8, z), r, {})


func _loot(pk: PickupManager) -> Dictionary:
	var out := {"small": 0, "medium": 0, "coins": 0}
	for i in range(pk.alive.size()):
		if pk.alive[i] == 1:
			match pk.kind[i]:
				PickupManager.KIND_GEM_S:
					out["small"] += 1
				PickupManager.KIND_GEM_M:
					out["medium"] += 1
				PickupManager.KIND_COIN:
					out["coins"] += 1
	return out


# ---------------------------------------------------------------- 1. the hits each kind takes

func test_the_kinds_take_two_three_and_five_shots_and_the_map_may_say_otherwise() -> void:
	var want := [2, 3, 5]
	for t in range(3):
		assert_int(int(BarrelSpawns.contents_of({}, t)["shots"])).is_equal(int(want[t]))
	# the map's block: its own number, at least 1, a whole number
	assert_int(int(BarrelSpawns.contents_of({"exp": {"shots": 4}}, "exp")["shots"])).is_equal(4)
	assert_int(int(BarrelSpawns.contents_of({"coins": {"shots": 0}}, "coins")["shots"])).is_equal(1)
	assert_int(int(BarrelSpawns.contents_of({"powerup": {"shots": 2.7}}, "powerup")["shots"])).is_equal(2)
	# pass 112's black barrel reads as the coins kind
	assert_int(int(BarrelSpawns.contents_of({"black": {"shots": 6}}, "coins")["shots"])).is_equal(6)


func test_two_three_and_five_rounds_break_each_kind_and_every_one_before_knocks_it() -> void:
	var want := [2, 3, 5]
	for t in range(3):
		var w := _world([Vector3(5, 0, t)])
		var bf: BarrelField = w["bf"]
		assert_int(bf.shots_to_break(t)).is_equal(int(want[t]))
		var broken0 := Run.barrels_broken
		for k in range(int(want[t]) - 1):
			var x0 := bf.pos[0].x
			assert_int(_round(bf, 0.0, 14.0)).is_equal(1)
			assert_int(bf.alive[0]).is_equal(1)
			# knocked back along the flight (+X), KNOCK_M
			assert_float(bf.pos[0].x - x0).is_equal_approx(BarrelField.KNOCK_M, 0.001)
			assert_float(bf.pos[0].z).is_equal_approx(0.0, 0.001)
		assert_int(bf.shot_knocks).is_equal(int(want[t]) - 1)
		assert_int(int(bf.shot_hits.get(0, 0))).is_equal(int(want[t]) - 1)
		assert_int(_round(bf, 0.0, 14.0)).is_equal(1)
		assert_int(bf.alive[0]).is_equal(0)
		assert_int(bf.shot_breaks).is_equal(1)
		assert_int(Run.barrels_broken).is_equal(broken0 + 1)
		# broken: its hits forgotten, no more rounds strike it
		assert_bool(bf.shot_hits.has(0)).is_false()
		assert_int(_round(bf, 0.0, 14.0)).is_equal(0)


func test_the_map_block_sets_the_shots() -> void:
	var w := _world([Vector3(5, 0, 0)], {"exp": {"shots": 1}})
	var bf: BarrelField = w["bf"]
	_round(bf, 0.0, 10.0)
	assert_int(bf.alive[0]).is_equal(0)
	assert_int(bf.shot_knocks).is_equal(0)


func test_a_knock_follows_the_flight_and_never_into_another_barrel() -> void:
	# along +Z this time
	var w := _world([Vector3(0, 6, 1)])
	var bf: BarrelField = w["bf"]
	assert_int(bf.shot_through(Vector3(0, 0.8, 0), Vector3(0, 0.8, 12), 0.3, {})).is_equal(1)
	assert_float(bf.pos[0].z).is_equal_approx(6.0 + BarrelField.KNOCK_M, 0.001)
	assert_float(bf.pos[0].x).is_equal_approx(0.0, 0.001)
	# a barrel 1.3 m ahead: the whole knock would touch it, half of it is free
	var w2 := _world([Vector3(5, 0, 1), Vector3(6.3, 0, 0)])
	var bf2: BarrelField = w2["bf"]
	assert_bool(bf2.knock_ok(0, Vector3(5.6, 0, 0))).is_false()
	assert_bool(bf2.knock_ok(0, Vector3(5.3, 0, 0))).is_true()
	bf2.shot_hit(0, EAST, Vector3(4, 0.8, 0))
	assert_float(bf2.pos[0].x).is_equal_approx(5.0 + BarrelField.KNOCK_M * 0.5, 0.001)
	# one 0.9 m ahead: neither is free, it stays (and still counts the hit)
	var w3 := _world([Vector3(5, 0, 1), Vector3(5.9, 0, 0)])
	var bf3: BarrelField = w3["bf"]
	bf3.shot_hit(0, EAST, Vector3(4, 0.8, 0))
	assert_float(bf3.pos[0].x).is_equal_approx(5.0, 0.001)
	assert_int(int(bf3.shot_hits.get(0, 0))).is_equal(1)
	assert_int(bf3.alive[0]).is_equal(1)


func test_the_knock_is_drawn_as_a_slide_that_settles() -> void:
	var w := _world([Vector3(5, 0, 2)])
	var bf: BarrelField = w["bf"]
	_round(bf, 0.0, 10.0)
	assert_bool(bf._anims.has(0)).is_true()
	var t := 0.0
	while t < BarrelField.WOBBLE_S + 0.1:
		bf._process(DT)
		t += DT
	assert_bool(bf._anims.is_empty()).is_true()


# ---------------------------------------------------------------- 2. a real round flies on and strikes once

func test_a_round_flies_on_through_a_barrel_without_spending_pierce_and_strikes_it_once() -> void:
	var w := _world([Vector3(4, 0, 0)])
	var bf: BarrelField = w["bf"]
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var e := em.spawn("skeleton", Vector3(9, 0, 0), null, 1.0, 50.0)
	assert_int(e).is_greater_equal(0)
	em.state[e] = EnemyManager.STATE_MOVE
	em.dr[e] = 0.0
	em._rebuild_grid()
	var hp0: float = em.hp[e]
	var k := pm.register_kind(SphereMesh.new(), null, 1.0)
	var inst := WeaponInstance.new(Registry.weapon("revolver"), 1)
	var i := pm.fire(k, Vector3(0, 0.8, 0), EAST * 20.0, 10.0, 0, 0.3, 1.0, inst, 0.0)
	assert_int(i).is_greater_equal(0)
	var n := 0
	while pm.pos[i].x < 7.0 and n < 60:
		pm._physics_process(DT)
		em.pos[e] = Vector3(9, 0, 0)
		n += 1
	# through the barrel (knocked to 4.6, still in its path), struck once, flying on with its pierce whole
	assert_int(pm.alive[i]).is_equal(1)
	assert_int(pm.pierce[i]).is_equal(0)
	assert_int(int(bf.shot_hits.get(0, 0))).is_equal(1)
	assert_int(bf.shot_knocks).is_equal(1)
	assert_int(bf.alive[0]).is_equal(1)
	assert_float(bf.pos[0].x).is_equal_approx(4.0 + BarrelField.KNOCK_M, 0.001)
	# and on into the creature behind it
	n = 0
	while pm.alive[i] == 1 and n < 60:
		pm._physics_process(DT)
		em.pos[e] = Vector3(9, 0, 0)
		n += 1
	assert_float(em.hp[e]).is_less(hp0)
	assert_int(int(bf.shot_hits.get(0, 0))).is_equal(1)


func test_a_volley_breaks_an_exp_barrel_with_its_second_round() -> void:
	var w := _world([Vector3(4, 0, 0)])
	var bf: BarrelField = w["bf"]
	var pm: ProjectileManager = w["pm"]
	var k := pm.register_kind(SphereMesh.new(), null, 1.0)
	var inst := WeaponInstance.new(Registry.weapon("revolver"), 1)
	pm.fire(k, Vector3(0, 0.8, 0), EAST * 20.0, 10.0, 0, 0.3, 1.0, inst, 0.0)
	pm.fire(k, Vector3(-1, 0.8, 0), EAST * 20.0, 10.0, 0, 0.3, 1.0, inst, 0.0)
	for n in range(45):
		pm._physics_process(DT)
	assert_int(bf.alive[0]).is_equal(0)
	assert_int(bf.shot_knocks).is_equal(1)
	assert_int(bf.shot_breaks).is_equal(1)


func test_a_round_flying_over_a_barrel_misses_it() -> void:
	var w := _world([Vector3(4, 0, 0)])
	var bf: BarrelField = w["bf"]
	assert_int(bf.shot_through(Vector3(0, 2.5, 0), Vector3(8, 2.5, 0), 0.3, {})).is_equal(0)
	# and one passing a metre to the side
	assert_int(_round(bf, 0.0, 8.0, 1.0)).is_equal(0)
	assert_int(_round(bf, 0.0, 8.0, 0.5)).is_equal(1)


# ---------------------------------------------------------------- 3. the switch, walking, the loot

func test_the_switch_off_leaves_barrels_to_walking_alone() -> void:
	var w := _world([Vector3(4, 0, 0)])
	var bf: BarrelField = w["bf"]
	var pm: ProjectileManager = w["pm"]
	Settings.shoot_barrels = false
	assert_bool(bf.shootable()).is_false()
	assert_int(_round(bf, 0.0, 8.0)).is_equal(0)
	var k := pm.register_kind(SphereMesh.new(), null, 1.0)
	var inst := WeaponInstance.new(Registry.weapon("revolver"), 1)
	for j in range(3):
		pm.fire(k, Vector3(-float(j), 0.8, 0), EAST * 20.0, 10.0, 0, 0.3, 1.0, inst, 0.0)
	for n in range(45):
		pm._physics_process(DT)
	assert_int(bf.alive[0]).is_equal(1)
	assert_bool(bf.shot_hits.is_empty()).is_true()
	assert_float(bf.pos[0].x).is_equal(4.0)
	# walking still breaks it
	(w["hero"] as Node3D).global_position = Vector3(4, 0, 0)
	bf._physics_process(DT)
	assert_int(bf.alive[0]).is_equal(0)


func test_walking_into_a_struck_barrel_breaks_it_at_once() -> void:
	var w := _world([Vector3(4, 0, 0), Vector3(-4, 0, 1)])
	var bf: BarrelField = w["bf"]
	_round(bf, 0.0, 8.0, 0.0)
	assert_int(int(bf.shot_hits.get(0, 0))).is_equal(1)
	(w["hero"] as Node3D).global_position = bf.pos[0]
	bf._physics_process(DT)
	assert_int(bf.alive[0]).is_equal(0)
	# a coins barrel never shot: at once too
	(w["hero"] as Node3D).global_position = bf.pos[1]
	bf._physics_process(DT)
	assert_int(bf.alive[1]).is_equal(0)
	assert_int(bf.shot_breaks).is_equal(0)


func test_a_shot_break_pays_what_walking_pays() -> void:
	for t in [0, 1]:
		var walk := _world([Vector3(4, 0, t)])
		var bw: BarrelField = walk["bf"]
		bw.coins[0] = 3
		(walk["hero"] as Node3D).global_position = Vector3(4, 0, 0)
		bw._physics_process(DT)
		assert_int(bw.alive[0]).is_equal(0)
		var shot := _world([Vector3(4, 0, t)])
		var bs: BarrelField = shot["bf"]
		bs.coins[0] = 3
		for k in range(bs.shots_to_break(t)):
			_round(bs, 0.0, 12.0)
		assert_int(bs.alive[0]).is_equal(0)
		var a := _loot(walk["pk"])
		var b := _loot(shot["pk"])
		assert_dict(b).is_equal(a)
		assert_int(int(a["small"])).is_equal(int(BarrelSpawns.contents_of({}, t)["gems_small"]))
		assert_int(bw.coins_dropped).is_equal(bs.coins_dropped)
	# the power-up barrel throws its power-up either way (its own dice: one each)
	var pw := _world([Vector3(4, 0, 2)], {"powerup": {"powerups": [{"id": "heart", "weight": 1}]}})
	var bp: BarrelField = pw["bf"]
	for k in range(5):
		_round(bp, 0.0, 14.0)
	assert_int(bp.alive[0]).is_equal(0)
	assert_int(bp.powerups_thrown).is_equal(1)


# ---------------------------------------------------------------- 4. the grid

func test_the_grid_finds_every_barrel_a_round_can_reach() -> void:
	var spots: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 137
	for k in range(30):
		spots.append(Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), k % 3))
	# two close enough to share cells
	spots.append(Vector3(10, 10, 0))
	spots.append(Vector3(12.5, 10, 0))
	var w := _world(spots)
	var bf: BarrelField = w["bf"]
	assert_bool(bf.shootable()).is_true()
	assert_int(bf.grid_at(10.0, 10.0)).is_not_equal(0)
	# every step up to 1.25 m (75 m/s at 60 ticks) whose round reaches a barrel has a nonzero cell at its midpoint
	var reach := BarrelField.SHOT_R + BarrelField.SHOT_ROUND_MAX
	var missed := 0
	var asked := 0
	for k in range(4000):
		var b: Vector3 = bf.pos[rng.randi_range(0, bf.pos.size() - 1)]
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, reach)
		var d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, 1.25)
		var p0 := b + off - d * rng.randf()
		var p1 := p0 + d
		var mid := (p0 + p1) * 0.5
		asked += 1
		if bf.grid_at(mid.x, mid.z) == 0:
			missed += 1
	assert_int(missed).is_equal(0)
	assert_int(asked).is_equal(4000)
	# far from every barrel: empty
	assert_int(bf.grid_at(500.0, 500.0)).is_equal(0)
	# a broken barrel leaves the grid at the next ask
	var i0: int = bf.grid_at(bf.pos[0].x, bf.pos[0].z)
	assert_int(i0).is_not_equal(0)
	bf._break(0)
	assert_bool(bf.shootable()).is_true()
	assert_int(bf.grid_at(bf.pos[0].x, bf.pos[0].z)).is_not_equal(1)


func test_a_respawned_barrel_is_a_new_barrel_to_an_old_round() -> void:
	var w := _world([Vector3(4, 0, 1)])
	var bf: BarrelField = w["bf"]
	var seen := {}
	assert_int(bf.shot_through(Vector3(0, 0.8, 0), Vector3(8, 0.8, 0), 0.3, seen)).is_equal(1)
	assert_int(bf.shot_through(Vector3(0, 0.8, 0), Vector3(8, 0.8, 0), 0.3, seen)).is_equal(0)
	bf._break(0)
	assert_bool(bf.respawn_at(Vector3(4, 0, 0), "coins")).is_true()
	assert_bool(bf.shot_hits.has(0)).is_false()
	assert_int(bf.shot_through(Vector3(0, 0.8, 0), Vector3(8, 0.8, 0), 0.3, seen)).is_equal(1)


# ---------------------------------------------------------------- 5. the setting

func test_the_setting_is_on_by_default_saved_and_never_held_in_prod() -> void:
	var s: Node = Settings
	assert_bool(s.to_dict().has("shoot_barrels")).is_true()
	assert_bool(Settings.PROD_LOCKED.has("shoot_barrels")).is_false()
	var d: Dictionary = s.to_dict()
	d.erase("shoot_barrels")
	Settings.shoot_barrels = false
	s.from_dict(d)
	# an old save without the key keeps what it had; a fresh Settings starts on
	assert_bool(Settings.shoot_barrels).is_false()
	d["shoot_barrels"] = true
	s.from_dict(d)
	assert_bool(Settings.shoot_barrels).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/autoload/Settings.gd").contains("var shoot_barrels: bool = true")).is_true()
	# the Settings screen has its switch
	var src := FileAccess.get_file_as_string("res://ui/SettingsScreen.gd")
	# (pass 137, lane W2-HUB: the row's words are the string table's ui.settings.shoot_barrels)
	assert_bool(src.contains("[\"ui.settings.shoot_barrels\", \"shoot_barrels\", \"ShootBarrels\"]")).is_true()
	assert_str(Loc.t("ui.settings.shoot_barrels")).is_equal("Shoot barrels")
