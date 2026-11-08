extends GdUnitTestSuite

## Pass 134, lane RELOC: the far-creature relocation hidden, rarer and fair to burning creatures (Garry, 2026-11-08:
## "make it hidden, when teleporting burning enemies they stop burning (all the damage that they'd get should apply
## immediately instead. If they die they don't teleport) - make it a bit more rare").
## 1. The two keys: the game's defaults (hidden off, chance 1), a block's values mended, Red Canyon's (hidden, 0.6).
## 2. Hidden: one seen at its turn is never moved (passed over, its turn kept), nor is anything without a camera that
##    can say; one off the screen is placed at once (no sink, no rise, no dust), never at a spot that shows; no hidden
##    spot = no move.
## 3. Burning: the rest of the burn is what its ticks would still deal; dealt at once to the burn's weapon as fire damage;
##    a kill is not moved and dies as a death does; a survivor is moved unburnt. Poison rides along.
## 4. Chance: 0 = nobody (the far time starts again), 1 = as before (no roll, pass 128's places), a share in between with
##    the lane's own dice, the same seed the same picks.

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var director = null
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
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(_at, _r, _dur, _col, _filled := true) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return true
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
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0
const FIRE := "molotov"


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.debug_clear_items()
	Run.end()
	Dice.reseed(0)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
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
	em.onscreen.resize(em.pool_max)
	em.onscreen.fill(0)
	return {"g": g, "hero": hero, "em": em}


## A plain creature standing on the sand, walking (no rise, no colour, no modifier).
func _put(em: EnemyManager, id: String, at: Vector3) -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	em.vspecial[i] = 0
	em.elite_idx[i] = -1
	if em.onscreen.size() == em.pool_max:
		em.onscreen[i] = 0
	return i


## The block the tests play, every key named (the code's defaults with `over` laid on top).
func _cfg(over: Dictionary = {}) -> Dictionary:
	var tl := WaveTimeline.new()
	tl.relocate = over
	return tl.relocate_cfg()


func _flat(p: Vector3) -> float:
	return Vector2(p.x, p.z).length()


## Puts creature `i` straight into the queue (as a scan that reached `seconds` would).
func _queue(rl: CrowdRelocate, em: EnemyManager, i: int) -> void:
	em.reloc_far[i] = rl.seconds
	em.reloc_queued[i] = CrowdRelocate.QUEUED
	rl.queue.append(Vector2i(i, em.serial[i]))


# ---------------------------------------------------------------- 1. the keys

func test_the_defaults_and_a_mended_block() -> void:
	var c := WaveTimeline.new().relocate_cfg()
	# the game's own: pass 128's sink and rise, everyone at the first try
	assert_bool(bool(c["hidden"])).is_false()
	assert_float(float(c["chance"])).is_equal(1.0)
	var tl := JsonContent.timeline_from_dict({"relocate": {"hidden": true, "chance": 0.35}})
	assert_bool(bool(tl.relocate_cfg()["hidden"])).is_true()
	assert_float(float(tl.relocate_cfg()["chance"])).is_equal_approx(0.35, 1e-6)
	# a share stays a share; a word is the default
	assert_float(float(_cfg({"chance": 2.5})["chance"])).is_equal(1.0)
	assert_float(float(_cfg({"chance": -1})["chance"])).is_equal(0.0)
	assert_float(float(_cfg({"chance": "often"})["chance"])).is_equal(1.0)
	assert_bool(bool(_cfg({"hidden": "yes"})["hidden"])).is_false()
	# the lane takes them
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"hidden": true, "chance": 0.25}))
	assert_bool(em.relocate.hidden).is_true()
	assert_float(em.relocate.chance).is_equal_approx(0.25, 1e-6)
	em.set_relocate(_cfg())
	assert_bool(em.relocate.hidden).is_false()
	assert_float(em.relocate.chance).is_equal(1.0)


func test_red_canyon_plays_hidden_at_six_in_ten() -> void:
	var raw: Dictionary = ((JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON)) as Dictionary).get("timeline_data", {}) as Dictionary).get("relocate", {})
	assert_bool(raw.get("hidden") is bool and bool(raw["hidden"])).is_true()
	assert_float(float(raw.get("chance", -1.0))).is_equal_approx(0.6, 1e-6)
	var c: Dictionary = Registry.map("red_canyon").timeline.relocate_cfg()
	assert_bool(bool(c["hidden"])).is_true()
	assert_float(float(c["chance"])).is_equal_approx(0.6, 1e-6)


# ---------------------------------------------------------------- 2. hidden

func test_one_on_the_screen_is_passed_over_and_keeps_its_turn() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	em.set_relocate(_cfg({"hidden": true, "chance": 0.5, "seconds": 1.0, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	rl.view_test = func(_p: Vector3, _h: float) -> bool: return false
	var a := _put(em, "skeleton", Vector3(30, 0, 0))
	var at: Vector3 = em.pos[a]
	em.onscreen[a] = 1
	_queue(rl, em, a)
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(-1)
	# not moved, not sinking: passed over, its turn kept
	assert_object(em.pos[a]).is_equal(at)
	assert_int(em.state[a]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.rise_v[a]).is_equal(0.0)
	assert_int(rl.passed_seen).is_equal(1)
	assert_int(rl.relocated).is_equal(0)
	assert_int(em.reloc_queued[a]).is_equal(CrowdRelocate.WON)
	# the next scan takes it back without a new roll
	var missed0 := rl.missed
	assert_int(rl.scan_crowd(Vector3.ZERO)).is_equal(1)
	assert_int(rl.missed).is_equal(missed0)
	# still seen: still passed over, as many times as it takes
	for k in range(5):
		rl.hand_over(Vector3.ZERO)
		rl.scan_crowd(Vector3.ZERO)
	assert_object(em.pos[a]).is_equal(at)
	assert_int(rl.relocated).is_equal(0)
	# its picture showing is as good as its flag
	em.onscreen[a] = 0
	rl.view_test = func(p: Vector3, _h: float) -> bool: return p.x > 25.0
	rl.hand_over(Vector3.ZERO)
	assert_object(em.pos[a]).is_equal(at)
	# coming near spends the turn it won
	em.pos[a] = Vector3(5, 0, 0)
	rl.scan_crowd(Vector3.ZERO)
	rl.hand_over(Vector3.ZERO)
	rl.scan_crowd(Vector3.ZERO)
	assert_int(em.reloc_queued[a]).is_equal(CrowdRelocate.NOT_QUEUED)


func test_off_the_screen_it_is_placed_at_once_never_where_it_shows() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	em.set_relocate(_cfg({"hidden": true, "seconds": 0.5, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	# the "screen": every point with x < 0 shows; the far crowd stands at +X and is not seen
	var asked: Array = []
	rl.view_test = func(p: Vector3, _h: float) -> bool:
		asked.append(p)
		return p.x < 0.0
	var ids: Array = []
	for k in range(12):
		ids.append(_put(em, "skeleton", Vector3(40, 0, float(k) * 2.0 - 11.0)))
	rl.scan_crowd(Vector3.ZERO)
	assert_int(rl.queue.size()).is_equal(12)
	var kills0 := Run.kills
	var alive0 := em.alive_count()
	for k in range(12):
		var i: int = (rl.queue[0] as Vector2i).x
		var hp0: float = em.hp[i]
		assert_int(rl.hand_over(Vector3.ZERO)).is_equal(i)
		# at once: walking, all the way up, nothing sinking, no emerging squash
		assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
		assert_float(em.rise_t[i]).is_equal(1.0)
		assert_float(em.rise_v[i]).is_equal(0.0)
		assert_float(em.squash[i]).is_not_equal(EnemyManager.EMERGE_STRETCH)
		assert_bool(bool(rl.last["hidden"])).is_true()
		# never where it shows, inside the ring, off the screen by the lane's own flag
		assert_float(em.pos[i].x).is_greater_equal(0.0)
		assert_float(_flat(em.pos[i])).is_between(19.0 - 0.01, 24.0 + 0.01)
		assert_int(em.onscreen[i]).is_equal(0)
		assert_float(em.hp[i]).is_equal(hp0)
	assert_int(rl.relocated).is_equal(12)
	assert_int(rl.sunk).is_equal(0)
	assert_bool(rl.moving.is_empty()).is_true()
	assert_int(Run.kills).is_equal(kills0)
	assert_int(em.alive_count()).is_equal(alive0)
	assert_bool(asked.size() > 0).is_true()


func test_no_hidden_spot_means_no_move() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"hidden": true}))
	var rl: CrowdRelocate = em.relocate
	var a := _put(em, "skeleton", Vector3(40, 0, 0))
	var at: Vector3 = em.pos[a]
	# the creature is not seen, but every spot round the outlaw would be
	rl.view_test = func(p: Vector3, _h: float) -> bool: return _flat(p) < 30.0
	_queue(rl, em, a)
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(-1)
	assert_object(em.pos[a]).is_equal(at)
	assert_int(rl.passed_spot).is_equal(1)
	assert_int(em.reloc_queued[a]).is_equal(CrowdRelocate.WON)


func test_nothing_moves_hidden_without_a_camera_that_can_say() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"hidden": true, "seconds": 0.5, "scan": 0.25}))
	var rl: CrowdRelocate = em.relocate
	var a := _put(em, "skeleton", Vector3(40, 0, 0))
	for k in range(240):
		em._physics_process(DT)
	# the stand-in camera says nothing: everything counts as seen
	assert_int(rl.relocated).is_equal(0)
	assert_bool(rl.passed_seen > 0).is_true()
	assert_float(_flat(em.pos[a])).is_greater(30.0)


func test_hidden_off_still_sinks_and_rises() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	em.set_relocate(_cfg({"hidden": false}))
	var rl: CrowdRelocate = em.relocate
	var a := _put(em, "skeleton", Vector3(40, 0, 0))
	_queue(rl, em, a)
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(a)
	assert_float(em.rise_v[a]).is_less(0.0)
	assert_int(rl.sunk).is_equal(1)


# ---------------------------------------------------------------- 3. burning

func test_the_rest_of_a_burn_is_what_its_ticks_would_deal() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for case in [[7.0, 2.9, 13], [12.5, 4.0, 0], [3.0, 1.5, 50], [9.0, 2.2, 31]]:
		var a := _put(em, "skeleton", Vector3(30, 0, 0))
		var b := _put(em, "skeleton", Vector3(-30, 0, 0))
		em.max_hp[a] = 5000.0
		em.hp[a] = 5000.0
		em.max_hp[b] = 5000.0
		em.hp[b] = 5000.0
		em.ignite(a, FIRE, float(case[0]), float(case[1]), 0.0)
		em.ignite(b, FIRE, float(case[0]), float(case[1]), 0.0)
		for k in range(int(case[2])):
			em._tick_fire(a, DT)
			em._tick_fire(b, DT)
		var rest: Array = em.burn_rest(b)
		assert_str(str(rest[1])).is_equal(FIRE)
		# the burn left alone, to its end
		var hp0: float = em.hp[a]
		var guard := 0
		while em.is_burning(a) and guard < 2000:
			em._tick_fire(a, DT)
			guard += 1
		assert_float(float(rest[0])).is_equal_approx(hp0 - em.hp[a], 1e-3)
		assert_float(float(rest[0])).is_greater(0.0)
		em.despawn(a)
		em.despawn(b)
	# nothing to say for one not burning
	var c := _put(em, "skeleton", Vector3(0, 0, 30))
	assert_float(float(em.burn_rest(c)[0])).is_equal(0.0)
	assert_bool(em.burn_out(c)).is_false()


func test_a_burning_survivor_is_moved_unburnt_its_rest_dealt() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"hidden": true}))
	var rl: CrowdRelocate = em.relocate
	rl.view_test = func(_p: Vector3, _h: float) -> bool: return false
	var a := _put(em, "skeleton", Vector3(40, 0, 0))
	em.max_hp[a] = 500.0
	em.hp[a] = 500.0
	em.ignite(a, FIRE, 10.0, 3.0, 0.0)
	em.poison(a, "poison_flask", 2.0, 1, 4.0)
	var rest: float = float(em.burn_rest(a)[0])
	assert_float(rest).is_greater(0.0)
	var dmg0: float = float(Run.damage_by_weapon.get(FIRE, 0.0))
	var fire0: float = float(Run.element_damage.get("fire", 0.0))
	_queue(rl, em, a)
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(a)
	# moved, alive, the burn over, its rest taken at once and credited as fire damage of its weapon
	assert_float(_flat(em.pos[a])).is_between(19.0 - 0.01, 24.0 + 0.01)
	assert_bool(em.is_burning(a)).is_false()
	assert_int(em.fire_blue[a]).is_equal(0)
	assert_float(em.hp[a]).is_equal_approx(500.0 - rest, 1e-3)
	assert_float(float(Run.damage_by_weapon.get(FIRE, 0.0)) - dmg0).is_equal_approx(rest, 1e-3)
	assert_float(float(Run.element_damage.get("fire", 0.0)) - fire0).is_equal_approx(rest, 1e-3)
	assert_int(rl.burnt).is_equal(1)
	assert_int(rl.burn_kills).is_equal(0)
	assert_float(rl.burn_dealt).is_equal_approx(rest, 1e-3)
	# poison is not burning: it rides along
	assert_bool(em.is_poisoned(a)).is_true()
	# no burn left to tick at the new place
	var hp1: float = em.hp[a]
	for k in range(120):
		em._tick_fire(a, DT)
	assert_float(em.hp[a]).is_equal(hp1)


func test_a_burn_that_kills_leaves_it_where_it_stands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"hidden": true}))
	var rl: CrowdRelocate = em.relocate
	rl.view_test = func(_p: Vector3, _h: float) -> bool: return false
	var a := _put(em, "skeleton", Vector3(40, 0, 0))
	var b := _put(em, "skeleton", Vector3(40, 0, 6))
	em.hp[a] = 5.0
	em.ignite(a, FIRE, 10.0, 3.0, 0.0)
	var at: Vector3 = em.pos[a]
	var kills0 := Run.kills
	var fire0: float = float(Run.element_damage.get("fire", 0.0))
	_queue(rl, em, a)
	_queue(rl, em, b)
	# the burning one dies of its rest and stays; the turn goes on to the next one
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(b)
	assert_bool(em.alive[a] == 0 or em.state[a] == EnemyManager.STATE_DYING).is_true()
	assert_float(_flat(em.pos[a])).is_equal_approx(_flat(at), 0.01)
	assert_int(Run.kills).is_equal(kills0 + 1)
	# its weapon's fire damage counts what it still had in it (the death's own rule)
	assert_float(float(Run.element_damage.get("fire", 0.0)) - fire0).is_equal_approx(5.0, 1e-3)
	assert_int(rl.burn_kills).is_equal(1)
	assert_int(rl.relocated).is_equal(1)
	assert_int(int(rl.last["i"])).is_equal(b)


func test_burning_ones_burn_out_with_hidden_off_too() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	em.set_relocate(_cfg({"hidden": false}))
	var rl: CrowdRelocate = em.relocate
	var a := _put(em, "skeleton", Vector3(40, 0, 0))
	em.hp[a] = 2.0
	em.ignite(a, FIRE, 10.0, 3.0, 0.0)
	_queue(rl, em, a)
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(-1)
	assert_int(rl.sunk).is_equal(0)
	assert_int(rl.burn_kills).is_equal(1)


# ---------------------------------------------------------------- 4. chance

func test_chance_nought_moves_nobody_and_one_is_as_before() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"chance": 0.0, "seconds": 1.0, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	var ids: Array = []
	for k in range(6):
		ids.append(_put(em, "skeleton", Vector3(30, 0, float(k) * 2.0)))
	for k in range(20):
		rl.scan_crowd(Vector3.ZERO)
	assert_int(rl.queued_total).is_equal(0)
	# every try missed, so the far time keeps starting again
	assert_int(rl.missed).is_equal(6 * 10)
	for i in ids:
		assert_float(em.reloc_far[i]).is_less(1.0)
	# 1: the first scan past `seconds` takes everyone, no dice rolled
	em.set_relocate(_cfg({"chance": 1.0, "seconds": 1.0, "scan": 0.5}))
	for i in ids:
		em.reloc_far[i] = 0.0
	rl.scan_crowd(Vector3.ZERO)
	assert_int(rl.queue.size()).is_equal(0)
	assert_int(rl.scan_crowd(Vector3.ZERO)).is_equal(6)


func test_chance_one_keeps_pass_128s_dice() -> void:
	var a := _places({})
	var b := _places({"chance": 1.0})
	assert_int(a.size()).is_equal(8)
	for k in range(a.size()):
		assert_object(b[k]).is_equal(a[k])


func _places(over: Dictionary) -> Array:
	Dice.reseed(5150)
	var w := _world()
	var em: EnemyManager = w["em"]
	var o := {"seconds": 0.5, "scan": 0.5, "sink": 0.0}
	o.merge(over, true)
	em.set_relocate(_cfg(o))
	var rl: CrowdRelocate = em.relocate
	for k in range(8):
		_put(em, "skeleton", Vector3(40, 0, float(k) * 2.0))
	rl.scan_crowd(Vector3.ZERO)
	var out: Array = []
	for k in range(8):
		var i := rl.hand_over(Vector3.ZERO)
		out.append(em.pos[i])
	return out


func test_a_share_in_between_waits_longer_on_the_same_dice() -> void:
	var a := _waits(0.6, 77)
	var b := _waits(0.6, 77)
	var c := _waits(1.0, 77)
	# the same seed, the same picks
	assert_array(b).is_equal(a)
	var mean := 0.0
	for v in a:
		mean += float(v)
	mean /= float(a.size())
	# at 1 everyone goes at 5 s; at 0.6 on average 5 / 0.6 = 8.3 s (a loose band for 200 creatures)
	for v in c:
		assert_float(float(v)).is_equal_approx(5.0, 1e-3)
	print("pass134 RELOC: chance 0.6, mean far time before joining %.2f s over %d creatures" % [mean, a.size()])
	assert_float(mean).is_between(7.0, 9.8)


## When each of 200 far creatures joins the queue (seconds 5, scan 0.5), at `p`.
func _waits(p: float, seed_value: int) -> Array:
	Dice.reseed(seed_value)
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"chance": p, "seconds": 5.0, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	var ids: Array = []
	for k in range(200):
		var ang := TAU * float(k) / 200.0
		ids.append(_put(em, "skeleton", Vector3(cos(ang), 0, sin(ang)) * 40.0))
	var at := {}
	var t := 0.0
	for s in range(400):
		t += 0.5
		rl.scan_crowd(Vector3.ZERO)
		for i in ids:
			if not at.has(i) and em.reloc_queued[i] == CrowdRelocate.QUEUED:
				at[i] = t
		if at.size() == ids.size():
			break
	var out: Array = []
	for i in ids:
		out.append(float(at.get(i, -1.0)))
	return out
