extends GdUnitTestSuite

## Pass 112, lane BARREL (Garry, 2026-10-28: "when I was talking about chest appearing and stuff I actually meant barrels.
## Not chests. So apply whatever I said in that prompt to barrels, and revert the chests to be as they were"; the pass 111
## words: "should respawn every now and then. They should also have a chance of a power up dropping from them. The power
## ups don't immediately get claimed and used by the hero. They jump far enough out for it to be a conscious decision for
## the Player. I should be able to set the frequency and content probabilities of both [barrel] types on LevelEditor.
## [They] never spawn where Player can see them"). Pinned here: broken barrels come back on their clock (first, every)
## only while fewer than max_lying stand, never inside the camera's view (an independent unproject test), in a broken
## slot of their kind, a spare instance, or the other kind's slot; only in the phases the block allows; a smashed barrel's
## power-up (its kind's chance, list, throw distance) is thrown away from the hero, cannot be taken in the air, is not
## pulled by a magnet or a vacuum and lies for the player to choose; the contents knobs (gems, coins); no block = today's
## barrels; pass 111's map chests are gone.

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
var paused := false
var applied: Array = []
func toast(_t, _c = null) -> void:
	pass
func apply_pickup(def, at: Vector3) -> void:
	applied.append(def.id)
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func max_speed() -> float:
	return 5.0
"""

const FAKE_RIG := """extends Node
var camera: Camera3D
func shake(_a: float) -> void:
	pass
"""

const FAKE_DIRECTOR := """extends Node
var running := true
var phase := 0
var timeline = null
"""

const DT := 1.0 / 60.0
const VP := Vector2i(540, 1200)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game: the hero at the origin, a portrait camera like the game's over him (46 degrees down, 22.5 m back, fov 55,
## in its own 540 x 1200 viewport), a fake director running stage time with its own timeline (its `barrels` block), no
## map (the sand flat at 0), a real PickupManager and a real BarrelField holding `brown` brown and `black` black barrels
## on a ring 30 m out (none near the hero), each kind's MultiMeshes with BarrelField.SPARE spare instances.
## Pass 116 (lane MAP): `power` power-up barrels too (kind 2), after the black (coins) ones.
func _game(barrels: Dictionary = {}, brown: int = 4, black: int = 2, power: int = 0) -> Dictionary:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
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
	var vp := SubViewport.new()
	vp.size = VP
	g.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)
	var pitch := deg_to_rad(46.0)
	cam.global_position = Vector3(0, sin(pitch) * 22.5, cos(pitch) * 22.5)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	rig.camera = cam
	var tl := WaveTimeline.new()
	tl.barrels = barrels
	tl.pickups = {"per_kill": 0.0045, "roster": [{"id": "heart", "weight": 6}, {"id": "nuke", "weight": 2}]}
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	d.timeline = tl
	g.director = d
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	var bf: BarrelField = auto_free(BarrelField.new())
	bf.game = g
	add_child(bf)
	var n := [brown, black, power]
	var names := [["_body_dark"], ["_body_light"], ["_body_power"]]
	for t in range(3):
		for name in names[t]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.instance_count = int(n[t]) + BarrelField.SPARE
			mm.visible_instance_count = int(n[t])
			bf.set(name, mm)
	var k := 0
	for t in range(3):
		for j in range(int(n[t])):
			var a := TAU * float(k) / float(brown + black + power)
			bf.pos.append(Vector3(cos(a) * 30.0, 0, sin(a) * 30.0))
			bf.light.append(t)
			bf.alive.append(1)
			bf.coins.append(0)
			bf._index_in.append(j)
			bf.shadows.append(-1)
			k += 1
	return {"g": g, "hero": hero, "pm": pm, "bf": bf, "cam": cam, "dir": d, "tl": tl}


func _tick(w: Dictionary, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		(w["bf"] as BarrelField)._physics_process(DT)
		(w["pm"] as PickupManager)._physics_process(DT)
		t += DT


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## An independent look at the screen: any point of the barrel (its foot ring, its top, its shadow's rim) that the camera
## projects inside the viewport.
func _on_screen(cam: Camera3D, p: Vector3) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(VP))
	var pts: Array = [p + Vector3(0, 0.95, 0), p + Vector3(0, 0.45, 0)]
	for k in range(8):
		var a := TAU * float(k) / 8.0
		pts.append(p + Vector3(cos(a) * 0.55, 0.02, sin(a) * 0.55))
	for q: Vector3 in pts:
		if not cam.is_position_behind(q) and rect.has_point(cam.unproject_position(q)):
			return true
	return false


const ON := {"respawn": {"enabled": true, "first": 5, "every": 10, "max_lying": 6, "min_dist": 20, "max_dist": 40}}


# ---------------------------------------------------------------- 1. no block = today's barrels; the chests as they were

func test_no_block_is_todays_barrels_and_pass_111s_map_chests_are_gone() -> void:
	var w := _game()
	var bf: BarrelField = w["bf"]
	bf._break(0)
	_tick(w, 200.0)
	assert_int(bf.alive_count()).is_equal(5)
	assert_bool(bf.respawn_clock().on).is_false()
	assert_int(bf.respawned).is_equal(0)
	assert_int((w["pm"] as PickupManager).specials.size()).is_equal(0)
	var brown := BarrelSpawns.contents_of({}, false)
	var black := BarrelSpawns.contents_of({}, true)
	assert_int(brown["gems_small"]).is_equal(8)
	assert_int(brown["gems_medium"]).is_equal(0)
	assert_object(brown["coins"]).is_equal(Vector2i(0, 0))
	assert_int(black["gems_small"]).is_equal(10)
	assert_int(black["gems_medium"]).is_equal(4)
	assert_object(black["coins"]).is_equal(Vector2i(BarrelField.COIN_MIN, BarrelField.COIN_MAX))
	assert_float(brown["powerup_chance"]).is_equal(0.0)
	assert_float(black["powerup_chance"]).is_equal(0.0)
	# a block without `enabled` lays none
	assert_bool(BarrelSpawns.respawn_of({"respawn": {"first": 5}})["enabled"]).is_false()
	# the map chests of pass 111 are gone: no clock, no thrown power-up from a chest, no CHEST tag
	var pm := PickupManager.new()
	assert_bool(pm.has_method("pointer_chest")).is_false()
	assert_bool(pm.has_method("throw_chest_powerup")).is_false()
	assert_bool(pm.has_method("world_chests")).is_false()
	pm.free()
	var wt := WaveTimeline.new()
	assert_bool("world_chests" in wt).is_false()
	assert_bool("chest_contents" in wt).is_false()
	assert_bool(ResourceLoader.exists("res://core/systems/WorldChests.gd")).is_false()
	assert_bool(FileAccess.get_file_as_string("res://ui/HUD.gd").contains("CHEST")).is_false()
	var map_text := FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json")
	assert_bool(map_text.contains("world_chests") or map_text.contains("chest_contents")).is_false()
	# a game without a director (every older barrel test) never ticks the clock
	w["g"].director = null
	bf.spawns = null
	_tick(w, 2.0)
	assert_object(bf.spawns).is_null()


# ---------------------------------------------------------------- 2. the clock, how many stand, never seen

func test_a_broken_barrel_comes_back_on_the_clock_off_the_screen_and_only_below_max_lying() -> void:
	var w := _game(ON)
	var bf: BarrelField = w["bf"]
	var cam: Camera3D = w["cam"]
	# all six standing: the turns are skipped
	_tick(w, 26.0)
	assert_int(bf.respawned).is_equal(0)
	assert_int(bf.spawns.skipped).is_greater_equal(2)
	# two smashed (far from him, by hand): the next turns stand them up again, one a turn
	var start: Array = Array(bf.pos)
	bf._break(1)
	bf._break(4)
	assert_int(bf.alive_count()).is_equal(4)
	var t0 := bf.spawns.clock
	var due := bf.spawns.next_at
	_tick(w, due - t0 + 0.1)
	assert_int(bf.alive_count()).is_equal(5)
	_tick(w, 10.0)
	assert_int(bf.alive_count()).is_equal(6)
	assert_int(bf.respawned).is_equal(2)
	# each new one (in a broken slot of its kind, else a spare instance) off the screen and 20-60 m from the hero
	var fresh := 0
	for i in range(bf.pos.size()):
		if bf.alive[i] == 1 and not start.has(bf.pos[i]):
			fresh += 1
			assert_bool(_on_screen(cam, bf.pos[i])).override_failure_message("barrel %d shows at %s" % [i, bf.pos[i]]).is_false()
			assert_float(_flat(bf.pos[i], Vector3.ZERO)).is_between(20.0, 60.0)
	assert_int(fresh).is_equal(2)
	# all standing again: no more
	_tick(w, 30.0)
	assert_int(bf.respawned).is_equal(2)


func test_a_respawn_never_appears_inside_the_cameras_view() -> void:
	var w := _game({"respawn": {"enabled": true, "min_dist": 8, "max_dist": 25, "max_lying": 0, "view_margin": 0}}, 2, 1)
	var bf: BarrelField = w["bf"]
	var cam: Camera3D = w["cam"]
	var laid := 0
	for k in range(30):
		if bf.respawn_clock().spawn_now(bf):
			laid += 1
	# an 8-25 m band round a hero whose screen shows ~20 m up and down: many spots are on the screen, none is taken
	assert_int(laid).is_greater_equal(20)
	for i in range(3, bf.pos.size()):
		assert_bool(_on_screen(cam, bf.pos[i])).override_failure_message("barrel %d shows at %s" % [i, bf.pos[i]]).is_false()
		assert_bool(BarrelSpawns.seen(Array(cam.get_frustum()), bf.pos[i], 0.0)).is_false()
	# MIN_GAP between every two standing
	for a in range(bf.pos.size()):
		for b in range(a + 1, bf.pos.size()):
			assert_float(_flat(bf.pos[a], bf.pos[b])).is_greater_equal(BarrelField.MIN_GAP - 0.001)
	# the test is not trivially false: a barrel just ahead of him IS seen
	assert_bool(BarrelSpawns.seen(Array(cam.get_frustum()), Vector3(0, 0, -6), 0.0)).is_true()
	assert_bool(_on_screen(cam, Vector3(0, 0, -6))).is_true()


func test_slots_reuse_a_broken_one_then_a_spare_then_the_other_kind() -> void:
	var w := _game({}, 2, 1)
	var bf: BarrelField = w["bf"]
	bf._break(0)
	assert_bool(bf.respawn_at(Vector3(40, 0, 0), false)).is_true()
	assert_int(bf.pos.size()).is_equal(3)
	assert_object(bf.pos[0]).is_equal(Vector3(40, 0, 0))
	# no broken brown one: a spare instance (the arrays grow, the MultiMesh shows one more)
	var mm: MultiMesh = bf._body_dark
	var shown := mm.visible_instance_count
	assert_bool(bf.respawn_at(Vector3(-40, 0, 0), false)).is_true()
	assert_int(bf.pos.size()).is_equal(4)
	assert_int(mm.visible_instance_count).is_equal(shown + 1)
	assert_int(bf._index_in[3]).is_equal(shown)
	assert_int(bf.light[3]).is_equal(0)
	assert_int(bf.alive[3]).is_equal(1)
	# the spare room used up and a broken black one lying: a brown turn stands the black one up
	mm.visible_instance_count = mm.instance_count
	bf._break(2)
	assert_bool(bf.respawn_at(Vector3(0, 0, 45), false)).is_true()
	assert_int(bf.alive[2]).is_equal(1)
	assert_int(bf.light[2]).is_equal(1)
	# nothing left: no slot
	(bf._body_light as MultiMesh).visible_instance_count = (bf._body_light as MultiMesh).instance_count
	(bf._body_power as MultiMesh).visible_instance_count = (bf._body_power as MultiMesh).instance_count
	assert_bool(bf.respawn_at(Vector3(0, 0, -45), true)).is_false()


func test_the_clock_waits_in_the_phases_the_block_leaves_out() -> void:
	var w := _game({"respawn": {"enabled": true, "first": 5, "every": 5, "max_lying": 0}})
	var bf: BarrelField = w["bf"]
	var d: Node = w["dir"]
	for ph in [BarrelSpawns.PHASE_PORTAL, BarrelSpawns.PHASE_ENDLESS]:
		d.phase = ph
		_tick(w, 20.0)
		assert_int(bf.respawned).is_equal(0)
		assert_float(bf.respawn_clock().clock).is_equal(0.0)
	d.phase = BarrelSpawns.PHASE_BOSS
	_tick(w, 5.2)
	assert_int(bf.respawned).is_equal(1)
	d.running = false
	_tick(w, 30.0)
	assert_int(bf.respawned).is_equal(1)
	var c := BarrelSpawns.respawn_of({"respawn": {"enabled": true, "in_boss": false, "in_endless": true}})
	assert_bool(BarrelSpawns.phase_allowed(c, BarrelSpawns.PHASE_BOSS)).is_false()
	assert_bool(BarrelSpawns.phase_allowed(c, BarrelSpawns.PHASE_ENDLESS)).is_true()


func test_max_per_stage_stops_them_and_a_range_every_rolls_between_its_ends() -> void:
	var w := _game({"respawn": {"enabled": true, "first": 0, "every": [30, 50], "max_lying": 0, "max_per_stage": 3}})
	var bf: BarrelField = w["bf"]
	var times: Array = []
	var seen := 0
	var t := 0.0
	while t < 300.0:
		bf._physics_process(DT)
		t += DT
		if bf.respawned > seen:
			seen = bf.respawned
			times.append(t)
	assert_int(times.size()).is_equal(3)
	for k in range(1, times.size()):
		assert_float(float(times[k]) - float(times[k - 1])).is_between(29.9, 50.1)
	assert_float(bf.spawns.next_at).is_equal(INF)


# ---------------------------------------------------------------- 3. what a barrel holds, the power-up thrown out

## pass 116 (lane MAP): only the power-up barrel throws one
const RAGE_6 := {"powerup": {"powerup_chance": 1.0, "powerups": [{"id": "rage", "weight": 1}], "throw_distance": 6}}


func test_a_smashed_barrel_throws_its_powerup_at_the_set_distance_away_from_the_hero() -> void:
	var w := _game(RAGE_6, 1, 0, 1)
	var bf: BarrelField = w["bf"]
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var g: Node = w["g"]
	# the black barrel stands a step north of him: he walks into it
	bf.pos[1] = Vector3(0, 0, -1.0)
	_tick(w, DT * 2.0)
	assert_int(bf.alive[1]).is_equal(0)
	assert_int(pm.specials.size()).is_equal(1)
	assert_int(bf.powerups_thrown).is_equal(1)
	var p: Powerup = pm.specials[0]
	assert_str(p.def.id).is_equal("rage")
	assert_bool(p.flying).is_true()
	assert_bool(p.no_magnet).is_true()
	assert_float(_flat(p._to, Vector3(0, 0, -1.0))).is_equal_approx(6.0, 0.01)
	assert_float(_flat(p._to, hero.global_position)).is_greater_equal(5.0)
	# in the air it is never his, its clock stands still, it rises on its hop
	var life0 := p.life
	var top := 0.0
	var t := 0.0
	while p.flying and t < 3.0:
		p._process(DT)
		pm._check_specials(hero, DT)
		top = maxf(top, p.global_position.y)
		t += DT
	assert_bool(p.flying).is_false()
	assert_float(top).is_greater(2.0)
	assert_float(t).is_between(0.6, 1.0)
	assert_float(p.life).is_equal(life0)
	# landed: still lying there, his to walk to
	_tick(w, 3.0)
	assert_bool(p.taken).is_false()
	assert_array(g.applied).is_empty()
	hero.global_position = p.global_position + Vector3(0.5, 0, 0)
	_tick(w, DT)
	assert_array(g.applied).contains(["rage"])


func test_a_thrown_powerup_is_never_pulled_by_a_magnet_or_a_vacuum() -> void:
	var w := _game({"powerup": {"powerup_chance": 1.0, "powerups": [{"id": "coin_bag", "weight": 1}], "throw_distance": 5}}, 0, 0, 1)
	var bf: BarrelField = w["bf"]
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	bf._break(0)
	var p: Powerup = pm.specials[0]
	while p.flying:
		p._process(DT)
	var at := p.global_position
	# the hero 1.8 m off: a coin bag would fly to him inside 1.6 x his magnet (1.5: 2.4 m); a thrown one stays
	hero.global_position = at + Vector3(1.8, 0, 0)
	pm.vacuum_all(true, true)
	_tick(w, 2.0)
	assert_bool(p.taken).is_false()
	assert_float(_flat(p.global_position, at)).is_less(0.001)
	# a coin bag the crowd dropped still flies in (the rule is the thrown ones' only)
	var bag := pm.spawn_special(Registry.pickup("coin_bag"), hero.global_position + Vector3(0, 0, 1.8), true)
	_tick(w, 1.0)
	assert_bool(not is_instance_valid(bag) or bag.taken).is_true()


func test_each_kind_has_its_own_chance_and_an_empty_list_draws_the_drops_roster() -> void:
	# pass 116 (lane MAP): the EXP and the EXP + Coins barrels never throw one, whatever the block says
	var w := _game({"exp": {"powerup_chance": 1.0}, "coins": {"powerup_chance": 1.0}}, 15, 15)
	var bf: BarrelField = w["bf"]
	var pm: PickupManager = w["pm"]
	for i in range(30):
		bf._break(i)
	assert_int(pm.specials.size()).is_equal(0)
	var w2 := _game({"powerup": {"powerup_chance": 0.5}}, 0, 0, 160)
	var bf2: BarrelField = w2["bf"]
	var pm2: PickupManager = w2["pm"]
	for i in range(160):
		bf2._break(i)
	assert_int(bf2.powerups_thrown).is_between(50, 110)
	var ids := {}
	for p in pm2.specials:
		ids[p.def.id] = true
	assert_array(ids.keys()).contains_exactly_in_any_order(["heart", "nuke"])


func test_the_contents_knobs_set_its_gems_and_coins() -> void:
	var w := _game({"brown": {"gems_small": 3, "gems_medium": 1, "coins": 2}, "black": {"gems_small": 0, "gems_medium": 0, "coins": 0}}, 1, 1)
	var bf: BarrelField = w["bf"]
	var pm: PickupManager = w["pm"]
	bf._roll_coins()
	assert_int(bf.coins[0]).is_equal(2)
	assert_int(bf.coins[1]).is_equal(0)
	bf._break(0)
	var small := 0
	var medium := 0
	var coins := 0
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1:
			match pm.kind[i]:
				PickupManager.KIND_GEM_S:
					small += 1
				PickupManager.KIND_GEM_M:
					medium += 1
				PickupManager.KIND_COIN:
					coins += 1
	assert_int(small).is_equal(3)
	assert_int(medium).is_equal(1)
	assert_int(coins).is_equal(2)
	# the black one set to nothing bursts into nothing
	bf._break(1)
	var after := 0
	for i in range(pm.alive.size()):
		after += pm.alive[i]
	assert_int(after).is_equal(6)
	# a respawned barrel rolls its coins from its kind's range (extra gold: the debt is the start's only)
	var w2 := _game({"black": {"coins": [4, 4]}}, 1, 1)
	var bf2: BarrelField = w2["bf"]
	bf2._break(1)
	assert_bool(bf2.respawn_at(Vector3(0, 0, 50), true)).is_true()
	assert_int(bf2.coins[1]).is_equal(4)


func test_a_thrown_powerup_lands_on_the_screen_even_when_away_from_him_is_off_it() -> void:
	var w := _game()
	var pm: PickupManager = w["pm"]
	var cam: Camera3D = w["cam"]
	var hero: Node3D = w["hero"]
	# he smashed it from the east: straight away from him (west) is past the narrow portrait screen's side
	hero.global_position = Vector3(1.0, 0, 0)
	var dice := RandomNumberGenerator.new()
	dice.seed = 112
	for k in range(12):
		var p := pm.throw_powerup(Registry.pickup("rage"), Vector3.ZERO, Vector2(6, 6), dice)
		assert_float(_flat(p._to, Vector3.ZERO)).is_equal_approx(6.0, 0.01)
		assert_bool(cam.is_position_behind(p._to)).is_false()
		var sp := cam.unproject_position(p._to)
		assert_bool(Rect2(Vector2.ZERO, Vector2(VP)).has_point(sp)).override_failure_message("landed off the screen at %s" % sp).is_true()
		pm.specials.erase(p)
		p.free()


func test_thrown_powerups_land_apart() -> void:
	var w := _game()
	var pm: PickupManager = w["pm"]
	var dice := RandomNumberGenerator.new()
	var lands: Array = []
	for k in range(6):
		lands.append(pm.throw_powerup(Registry.pickup("rage"), Vector3(0, 0, -10), Vector2(6, 6), dice)._to)
	for a in range(lands.size()):
		for b in range(a + 1, lands.size()):
			assert_float(_flat(lands[a], lands[b])).is_greater_equal(PickupManager.THROW_CLEAR - 0.001)
