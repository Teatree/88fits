extends GdUnitTestSuite

## Pass 111, lane CHEST (Garry, 2026-10-28: "Chests should respawn every now and then. They should also have a chance of a
## power up dropping from them. The power ups don't immediately get claimed and used by the hero. They jump far enough out
## for it to be a conscious decision for the Player. I should be able to set the frequency and content probabilities of
## both chest types on LevelEditor. Chests never spawn where Player can see them"). Pinned here: the map's own chests
## (WorldChests, the map's timeline_data.world_chests) come on their clock (first, every), never inside the camera's view
## (the chest, its pool and its beam, by an independent unproject test), never more than max_on_map lying, only in the
## phases the block allows, and vanish past their lifetime only off the screen; a chest's power-up (chest_contents) is
## thrown at the configured distance away from the hero, cannot be taken in the air, is not pulled by a magnet or the
## boss chest's vacuum, and lies there for the player to choose; the reel's knobs (new item weight, the boss chest's
## mutation); config off (no blocks) = today's: no map chests, no power-up, the reel's 0.45 and 50 gold.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var director = null
var paused := false
var opened: Array = []
var applied: Array = []
func toast(_t, _c = null) -> void:
	pass
func open_chest(at: Vector3, boss: bool = false) -> void:
	opened.append([at, boss])
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
## in its own 540 x 1200 viewport), a fake director running stage time with its own timeline, no map (the sand flat at
## 0), a real PickupManager. `world`/`contents`: the timeline's world_chests and chest_contents blocks.
func _game(world: Dictionary = {}, contents: Dictionary = {}) -> Dictionary:
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
	tl.world_chests = world
	tl.chest_contents = contents
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
	return {"g": g, "hero": hero, "pm": pm, "cam": cam, "dir": d, "tl": tl}


func _tick(pm: PickupManager, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		pm._physics_process(DT)
		t += DT


func _world(pm: PickupManager) -> Array:
	return pm.chests.filter(func(c) -> bool: return is_instance_valid(c) and c.world and not c.opened)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## An independent look at the screen: any point of the chest (its corners, its pool's rim, its beam to 9 m) that the
## camera projects inside the viewport.
func _on_screen(cam: Camera3D, p: Vector3) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(VP))
	var pts: Array = []
	for k in range(12):
		var a := TAU * float(k) / 12.0
		pts.append(p + Vector3(cos(a) * 2.3, 0.05, sin(a) * 2.3))
	for h in [0.0, 0.8, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0]:
		pts.append(p + Vector3(0, h, 0))
	for q: Vector3 in pts:
		if not cam.is_position_behind(q) and rect.has_point(cam.unproject_position(q)):
			return true
	return false


const ON := {"enabled": true, "first": 10, "every": 20, "max_on_map": 0, "min_dist": 25, "max_dist": 45}


# ---------------------------------------------------------------- 1. config off = today's

func test_config_off_lays_no_chest_and_throws_no_powerup_and_keeps_todays_reel() -> void:
	var w := _game()
	var pm: PickupManager = w["pm"]
	_tick(pm, 200.0)
	assert_int(pm.chests.size()).is_equal(0)
	assert_bool(pm.world_chests().on).is_false()
	assert_object(pm.throw_chest_powerup(Vector3.ZERO, false)).is_null()
	assert_object(pm.throw_chest_powerup(Vector3.ZERO, true)).is_null()
	assert_int(pm.specials.size()).is_equal(0)
	var cfg := WorldChests.cfg_of({})
	assert_bool(cfg["enabled"]).is_false()
	# a block without `enabled` is off too (only enabled true lays chests)
	assert_bool(WorldChests.cfg_of({"first": 5})["enabled"]).is_false()
	for boss in [false, true]:
		var cc := WorldChests.contents_of({}, boss)
		assert_float(cc["powerup_chance"]).is_equal(0.0)
		assert_float(cc["new_item_weight"]).is_equal(Run.CHEST_NEW_MULT)
		assert_int(cc["gold"]).is_equal(50)
	assert_bool(WorldChests.contents_of({}, true)["mutation"]).is_true()
	# a fake game without a director (every older pickups test) never lays one either
	pm.game.director = null
	pm.world = null
	_tick(pm, 5.0)
	assert_object(pm.world).is_null()


# ---------------------------------------------------------------- 2. the clock

func test_world_chests_come_on_their_clock_at_the_configured_distance() -> void:
	var w := _game(ON)
	var pm: PickupManager = w["pm"]
	_tick(pm, 9.9)
	assert_int(_world(pm).size()).is_equal(0)
	_tick(pm, 0.3)
	assert_int(_world(pm).size()).is_equal(1)
	_tick(pm, 19.7)
	assert_int(_world(pm).size()).is_equal(1)
	_tick(pm, 0.3)
	assert_int(_world(pm).size()).is_equal(2)
	_tick(pm, 20.0)
	assert_int(_world(pm).size()).is_equal(3)
	assert_int(pm.world.spawned).is_equal(3)
	for c in _world(pm):
		var d := _flat(c.global_position, Vector3.ZERO)
		# the band, or past it up to 1.5 x max_dist when the band is all on the screen
		assert_float(d).is_between(25.0, 67.5)
		assert_bool(c.boss).is_false()


func test_a_range_every_rolls_between_its_ends_and_max_per_stage_stops_them() -> void:
	var w := _game({"enabled": true, "first": 0, "every": [30, 50], "max_on_map": 0, "max_per_stage": 3})
	var pm: PickupManager = w["pm"]
	var times: Array = []
	var seen := 0
	var t := 0.0
	while t < 300.0:
		pm._physics_process(DT)
		t += DT
		if _world(pm).size() > seen:
			seen = _world(pm).size()
			times.append(t)
	assert_int(times.size()).is_equal(3)
	for k in range(1, times.size()):
		assert_float(float(times[k]) - float(times[k - 1])).is_between(29.9, 50.1)
	assert_float(pm.world.next_at).is_equal(INF)


# ---------------------------------------------------------------- 3. never where the player can see

func test_a_world_chest_never_appears_inside_the_cameras_view() -> void:
	var w := _game({"enabled": true, "min_dist": 10, "max_dist": 30, "max_on_map": 0, "view_margin": 0})
	var pm: PickupManager = w["pm"]
	var cam: Camera3D = w["cam"]
	pm.world_chests()
	var laid := 0
	for k in range(25):
		if pm.world.spawn_now(pm):
			laid += 1
	# a 10-30 m band round a hero whose screen shows ~20 m up and down: many spots are on the screen, none is taken
	assert_int(laid).is_greater_equal(22)
	for c in _world(pm):
		assert_bool(_on_screen(cam, c.global_position)).override_failure_message("a chest at %s shows on the screen" % c.global_position).is_false()
		assert_bool(WorldChests.seen(Array(cam.get_frustum()), c.global_position, 0.0)).is_false()
	# a spot on the screen IS seen (the test is not trivially false)
	assert_bool(WorldChests.seen(Array(cam.get_frustum()), Vector3(0, 0, -6), 0.0)).is_true()
	assert_bool(_on_screen(cam, Vector3(0, 0, -6))).is_true()


func test_the_margin_keeps_a_chest_further_off_the_edge() -> void:
	var w := _game()
	var planes := Array((w["cam"] as Camera3D).get_frustum())
	# walk out to the right until the chest is just off the screen, then a margin of 3 m still calls it seen
	var x := 0.0
	while WorldChests.seen(planes, Vector3(x, 0, 0), 0.0):
		x += 0.25
	assert_bool(WorldChests.seen(planes, Vector3(x, 0, 0), 3.0)).is_true()
	assert_bool(WorldChests.seen(planes, Vector3(x + 6.0, 0, 0), 3.0)).is_false()


# ---------------------------------------------------------------- 4. how many lie, the phases, the lifetime

func test_no_more_than_max_on_map_lie_and_a_full_turn_is_skipped() -> void:
	var w := _game({"enabled": true, "first": 1, "every": 5, "max_on_map": 2})
	var pm: PickupManager = w["pm"]
	_tick(pm, 60.0)
	assert_int(_world(pm).size()).is_equal(2)
	assert_int(pm.world.skipped).is_greater(5)
	# one opened: the next turn lays one again, never a third lying
	var c: Chest = _world(pm)[0]
	c.opened = true
	_tick(pm, 6.0)
	assert_int(_world(pm).size()).is_equal(2)
	# chests the creatures drop never count towards it
	pm.spawn_chest(Vector3(40, 0, 0))
	pm.spawn_chest(Vector3(-40, 0, 0))
	assert_int(pm.world_lying()).is_equal(2)


func test_the_clock_waits_in_the_phases_the_block_leaves_out() -> void:
	var w := _game({"enabled": true, "first": 5, "every": 5, "max_on_map": 0})
	var pm: PickupManager = w["pm"]
	var d: Node = w["dir"]
	# the portal's countdown and Endless: off by default, the clock stands still
	for ph in [WorldChests.PHASE_PORTAL, WorldChests.PHASE_ENDLESS]:
		d.phase = ph
		_tick(pm, 20.0)
		assert_int(_world(pm).size()).is_equal(0)
		assert_float(pm.world.clock).is_equal(0.0)
	# the boss fight: on by default
	d.phase = WorldChests.PHASE_BOSS
	_tick(pm, 5.2)
	assert_int(_world(pm).size()).is_equal(1)
	# a director that stopped (the run ended): nothing
	d.running = false
	_tick(pm, 30.0)
	assert_int(_world(pm).size()).is_equal(1)
	var c := WorldChests.cfg_of({"enabled": true, "in_boss": false, "in_endless": true})
	assert_bool(WorldChests.phase_allowed(c, WorldChests.PHASE_BOSS)).is_false()
	assert_bool(WorldChests.phase_allowed(c, WorldChests.PHASE_ENDLESS)).is_true()
	assert_bool(WorldChests.phase_allowed(c, WorldChests.PHASE_NORMAL)).is_true()


func test_past_its_lifetime_a_world_chest_vanishes_only_off_the_screen() -> void:
	var w := _game({"enabled": true, "first": 9999, "lifetime": 30})
	var pm: PickupManager = w["pm"]
	pm.world_chests()
	var seen_c := pm.spawn_chest(Vector3(0, 0, -5), false, true)
	var off_c := pm.spawn_chest(Vector3(60, 0, 0), false, true)
	var dropped := pm.spawn_chest(Vector3(-60, 0, 0))
	_tick(pm, 29.0)
	assert_int(pm.chests.size()).is_equal(3)
	_tick(pm, 2.5)
	# the one off the screen went, the one on it waits, a dropped chest never goes
	assert_bool(pm.chests.has(off_c)).is_false()
	assert_bool(pm.chests.has(seen_c)).is_true()
	assert_bool(pm.chests.has(dropped)).is_true()
	assert_int(pm.world.expired).is_equal(1)
	# off the screen at last (the hero walked away): it goes at the next look
	seen_c.global_position = Vector3(0, 0, 60)
	_tick(pm, 1.2)
	assert_bool(pm.chests.has(seen_c)).is_false()


func test_the_pointer_names_the_nearest_world_chest_only() -> void:
	var w := _game({"enabled": true, "first": 9999})
	var pm: PickupManager = w["pm"]
	pm.world_chests()
	var far := pm.spawn_chest(Vector3(40, 0, 0), false, true)
	var near := pm.spawn_chest(Vector3(0, 0, 30), true, true)
	pm.spawn_chest(Vector3(3, 0, 0))
	assert_object(pm.pointer_chest()).is_same(near)
	near.opened = true
	assert_object(pm.pointer_chest()).is_same(far)
	pm.world.cfg["pointer"] = false
	assert_object(pm.pointer_chest()).is_null()


# ---------------------------------------------------------------- 5. the power-up out of a chest

const RAGE_6 := {"normal": {"powerup_chance": 1.0, "powerups": [{"id": "rage", "weight": 1}], "throw_distance": 6}}


func test_a_chest_throws_its_powerup_at_the_set_distance_away_from_the_hero() -> void:
	var w := _game({}, RAGE_6)
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var g: Node = w["g"]
	var chest := Vector3(0, 0, -1.0)
	pm.spawn_chest(chest)
	_tick(pm, DT * 2.0)
	# he walked into it: the chest opened and a Rage hopped out
	assert_int((g.opened as Array).size()).is_equal(1)
	assert_int(pm.specials.size()).is_equal(1)
	var p: Powerup = pm.specials[0]
	assert_str(p.def.id).is_equal("rage")
	assert_bool(p.flying).is_true()
	assert_bool(p.no_magnet).is_true()
	assert_float(_flat(p._to, chest)).is_equal_approx(6.0, 0.01)
	# away from him (he stands 1 m south of the chest): it lands at least 5 m from him
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
	assert_float(_flat(p.global_position, p._to)).is_less(0.01)
	# landed: still lying there, his to walk to
	_tick(pm, 3.0)
	assert_bool(p.taken).is_false()
	assert_array(g.applied).is_empty()
	# he walks over: it is his
	hero.global_position = p.global_position + Vector3(0.5, 0, 0)
	_tick(pm, DT)
	assert_array(g.applied).contains(["rage"])


func test_a_thrown_powerup_is_never_pulled_by_a_magnet_or_the_boss_chests_call() -> void:
	var w := _game({}, {"normal": {"powerup_chance": 1.0, "powerups": [{"id": "coin_bag", "weight": 1}], "throw_distance": 5}})
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var p := pm.throw_chest_powerup(Vector3(0, 0, -1), false)
	assert_object(p).is_not_null()
	while p.flying:
		p._process(DT)
	var at := p.global_position
	# the hero 1.8 m off: a coin bag would fly to him inside 1.6 x his magnet (1.5: 2.4 m); one a chest threw stays
	hero.global_position = at + Vector3(1.8, 0, 0)
	pm.vacuum_all(true, true)
	_tick(pm, 2.0)
	assert_bool(p.taken).is_false()
	assert_float(_flat(p.global_position, at)).is_less(0.001)
	# a coin bag the crowd dropped still flies in (the rule is the chest's only)
	var bag := pm.spawn_special(Registry.pickup("coin_bag"), hero.global_position + Vector3(0, 0, 1.8), true)
	_tick(pm, 1.0)
	assert_bool(not is_instance_valid(bag) or bag.taken).is_true()


func test_the_chance_and_each_chest_types_own_block() -> void:
	var w := _game({}, {"normal": {"powerup_chance": 0.0}, "boss": {"powerup_chance": 1.0, "powerups": {"nuke": 1}}})
	var pm: PickupManager = w["pm"]
	for k in range(30):
		assert_object(pm.throw_chest_powerup(Vector3(k * 3.0, 0, -20), false)).is_null()
	var p := pm.throw_chest_powerup(Vector3(0, 0, -20), true)
	assert_str(p.def.id).is_equal("nuke")
	assert_float(_flat(p._to, Vector3(0, 0, -20))).is_between(5.0, 7.0)
	assert_int(pm.chest_powerups).is_equal(1)
	# half the time at 0.5, and an empty list draws from the map's power-up drops roster
	var w2 := _game({}, {"normal": {"powerup_chance": 0.5}})
	var pm2: PickupManager = w2["pm"]
	var got := 0
	var ids := {}
	for k in range(200):
		var q := pm2.throw_chest_powerup(Vector3(float(k % 20) * 4.0 - 40.0, 0, -30.0 - float(k / 20) * 4.0), false)
		if q != null:
			got += 1
			ids[q.def.id] = true
	assert_int(got).is_between(70, 130)
	assert_array(ids.keys()).contains_exactly_in_any_order(["heart", "nuke"])


func test_a_thrown_powerup_lands_on_the_screen_even_when_away_from_him_is_off_it() -> void:
	var w := _game({}, RAGE_6)
	var pm: PickupManager = w["pm"]
	var cam: Camera3D = w["cam"]
	# he walked into the chest from the east: straight away from him (west) is past the narrow portrait screen's side
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(1.0, 0, 0)
	for k in range(12):
		var p := pm.throw_chest_powerup(Vector3.ZERO, false)
		assert_float(_flat(p._to, Vector3.ZERO)).is_equal_approx(6.0, 0.01)
		assert_bool(cam.is_position_behind(p._to)).is_false()
		var sp := cam.unproject_position(p._to)
		assert_bool(Rect2(Vector2.ZERO, Vector2(VP)).has_point(sp)).override_failure_message("landed off the screen at %s" % sp).is_true()
		pm.specials.erase(p)
		p.free()


func test_thrown_powerups_land_apart() -> void:
	var w := _game({}, RAGE_6)
	var pm: PickupManager = w["pm"]
	var lands: Array = []
	for k in range(6):
		lands.append(pm.throw_chest_powerup(Vector3(0, 0, -10), false)._to)
	for a in range(lands.size()):
		for b in range(a + 1, lands.size()):
			assert_float(_flat(lands[a], lands[b])).is_greater_equal(WorldChests.THROW_CLEAR - 0.001)


# ---------------------------------------------------------------- 6. the reel's knobs

func test_the_reels_new_item_weight_and_the_boss_chests_mutation() -> void:
	_game()
	var tl: WaveTimeline = Run.map.timeline
	var keep: Dictionary = tl.chest_contents
	var news := Run.chest_candidates(0.0).filter(func(c) -> bool: return bool(c["is_new"]))
	assert_bool(news.is_empty()).is_false()
	for c in news:
		assert_float(float(c["weight"])).is_equal(0.0)
	var base := Run.chest_candidates()
	var half := Run.chest_candidates(Run.CHEST_NEW_MULT * 0.5)
	for k in range(base.size()):
		if bool(base[k]["is_new"]):
			assert_float(float(half[k]["weight"])).is_equal_approx(float(base[k]["weight"]) * 0.5, 1e-6)
	if not Run.boss_chest_mutations().is_empty():
		tl.chest_contents = {}
		assert_str(str(Run.chest_roll(true)["type"])).is_equal("mutation")
		tl.chest_contents = {"boss": {"mutation": false}}
		for k in range(10):
			assert_str(str(Run.chest_roll(true)["type"])).is_not_equal("mutation")
	tl.chest_contents = keep
