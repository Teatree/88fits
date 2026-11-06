extends GdUnitTestSuite

## Pass 128, lane BLOB: far creatures relocate (timeline_data.relocate, core/systems/CrowdRelocate.gd).
## 1. The defaults, a block read from JSON (gaps filled, bad values mended), the map file's own block, and the map's
##    far-speed cap against the Drifter's run.
## 2. Who may relocate: a regular creature; never a coloured special, an Elite (modifier or kind), a special type, a
##    dummy, a boss, a boss's summon, one held, rising, buried, lifted, undying or in an attack; a squad creature only
##    when its row says so or the block's `squads` is true; a row's `relocate: false` switches a regular creature off.
## 3. The far time (every `scan` s, reset within `distance`), the queue (first in first out, index order inside a scan),
##    the hand-over every `every` s, the ones that came near dropped.
## 4. A far creature behind a crowd on one side sinks and rises in the opposite half, inside the ring, the same creature
##    with the same health; nothing is spawned or counted.
## 5. Off without a director, in the arena, with `enabled` false and while a boss barrier stands.
## 6. The same run seed gives the same places; another seed gives others.
## 7. A row's say rides to its creatures (WaveTimeline.row_relocate -> EnemyManager.row_relocate -> reloc_may).

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


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.debug_clear_items()
	Run.end()


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
	return i


## The block the tests play, every key named (the code's defaults with `over` laid on top).
func _cfg(over: Dictionary = {}) -> Dictionary:
	var tl := WaveTimeline.new()
	tl.relocate = over
	return tl.relocate_cfg()


func _raw_tl() -> Dictionary:
	return (JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON)) as Dictionary).get("timeline_data", {})


func _flat(p: Vector3) -> float:
	return Vector2(p.x, p.z).length()


# ---------------------------------------------------------------- 1. the block

func test_the_defaults_fill_an_empty_block() -> void:
	var c := WaveTimeline.new().relocate_cfg()
	assert_bool(bool(c["enabled"])).is_true()
	assert_float(float(c["distance"])).is_equal(16.0)
	assert_float(float(c["seconds"])).is_equal(5.0)
	assert_float(float(c["every"])).is_equal_approx(0.4, 1e-6)
	assert_array(c["ring"]).is_equal([19.0, 24.0])
	assert_int(int(c["sectors"])).is_equal(12)
	assert_float(float(c["sink"])).is_equal_approx(0.35, 1e-6)
	assert_float(float(c["scan"])).is_equal(0.5)
	assert_bool(bool(c["squads"])).is_false()
	# every key of the defaults comes back
	for k in WaveTimeline.RELOCATE_DEFAULTS:
		assert_bool(c.has(k)).is_true()


func test_a_block_read_from_json_keeps_its_numbers_and_mends_bad_ones() -> void:
	var tl := JsonContent.timeline_from_dict({"relocate": {"distance": 20, "ring": [30, 22], "sectors": 0, "squads": true, "seconds": "soon", "sink": -1}})
	var c := tl.relocate_cfg()
	assert_float(float(c["distance"])).is_equal(20.0)
	# the ring is always [near, far]
	assert_array(c["ring"]).is_equal([22.0, 30.0])
	# at least one sector, no negative time, a word falls back to the default
	assert_int(int(c["sectors"])).is_equal(1)
	assert_float(float(c["sink"])).is_equal(0.0)
	assert_float(float(c["seconds"])).is_equal(5.0)
	assert_bool(bool(c["squads"])).is_true()
	# what the block does not name plays the default
	assert_float(float(c["every"])).is_equal_approx(0.4, 1e-6)
	# one number for the ring = that distance
	tl.relocate = {"ring": 21}
	assert_array(tl.relocate_cfg()["ring"]).is_equal([21.0, 21.0])
	# no block at all: the defaults, and something that is not a block is ignored
	assert_bool(bool(JsonContent.timeline_from_dict({}).relocate_cfg()["enabled"])).is_true()
	assert_dict(JsonContent.timeline_from_dict({"relocate": 3}).relocate).is_empty()
	# switched off
	assert_bool(bool(JsonContent.timeline_from_dict({"relocate": {"enabled": false}}).relocate_cfg()["enabled"])).is_false()


func test_the_map_file_names_every_number_and_the_game_reads_them() -> void:
	var raw: Dictionary = _raw_tl().get("relocate", {})
	var c: Dictionary = Registry.map("red_canyon").timeline.relocate_cfg()
	for k in WaveTimeline.RELOCATE_DEFAULTS:
		# written out, so Garry sees every number
		assert_bool(raw.has(k)).is_true()
		if raw[k] is Array:
			assert_float(float(c[k][0])).is_equal_approx(minf(float(raw[k][0]), float(raw[k][1])), 1e-6)
			assert_float(float(c[k][1])).is_equal_approx(maxf(float(raw[k][0]), float(raw[k][1])), 1e-6)
		elif raw[k] is bool:
			assert_bool(bool(c[k])).is_equal(bool(raw[k]))
		else:
			assert_float(float(c[k])).is_equal_approx(float(raw[k]), 1e-6)
	# the ring lies beyond the distance: a relocated creature is still "far", so it comes at him and is not taken again
	# before it has walked in
	assert_float(float(c["ring"][0])).is_greater(float(c["distance"]))


func test_the_far_speed_cap_is_well_above_the_drifters_run() -> void:
	var fs: Dictionary = Registry.map("red_canyon").timeline.far_speed_cfg()
	var raw: Dictionary = _raw_tl().get("far_speed", {})
	assert_float(float(fs["max_mult"])).is_equal_approx(float(raw["max_mult"]), 1e-6)
	assert_float(float(fs["max_speed"])).is_equal_approx(float(raw["max_speed"]), 1e-6)
	var drifter := Run.player_sheet.get_stat("move_speed", 5.0) * Run.move_pace()
	print("pass128 BLOB: the Drifter runs %.2f m/s; far_speed max_mult %.2f, max_speed %.2f m/s (x%.2f his run)" % [
		drifter, float(fs["max_mult"]), float(fs["max_speed"]), float(fs["max_speed"]) / drifter])
	# 0 = no cap at all
	if float(fs["max_speed"]) > 0.0:
		assert_float(float(fs["max_speed"])).is_greater_equal(1.2 * drifter)


# ---------------------------------------------------------------- 2. who

func test_a_regular_creature_may_and_the_marked_ones_never() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg())
	var rl: CrowdRelocate = em.relocate
	assert_object(rl).is_not_null()
	var reg := _put(em, "skeleton", Vector3(30, 0, 0))
	assert_int(em.reloc_may[reg]).is_equal(CrowdRelocate.MAY_DEFAULT)
	assert_bool(rl.eligible(reg)).is_true()
	# a coloured special, an Elite modifier
	em.vspecial[reg] = 1
	assert_bool(rl.eligible(reg)).is_false()
	em.vspecial[reg] = 0
	em.elite_idx[reg] = 0
	assert_bool(rl.eligible(reg)).is_false()
	em.elite_idx[reg] = -1
	# held, undying, rising, sinking, buried, lifted, in an attack
	em.held[reg] = 1
	assert_bool(rl.eligible(reg)).is_false()
	em.held[reg] = 0
	em.undying[reg] = 1
	assert_bool(rl.eligible(reg)).is_false()
	em.undying[reg] = 0
	em.rise_t[reg] = 0.5
	assert_bool(rl.eligible(reg)).is_false()
	em.rise_t[reg] = 1.0
	em.rise_v[reg] = -1.0
	assert_bool(rl.eligible(reg)).is_false()
	em.rise_v[reg] = 0.0
	em.hidden[reg] = 1
	assert_bool(rl.eligible(reg)).is_false()
	em.hidden[reg] = 0
	em.lift_t[reg] = 0.5
	assert_bool(rl.eligible(reg)).is_false()
	em.lift_t[reg] = 0.0
	for st in [EnemyManager.STATE_WINDUP, EnemyManager.STATE_CHARGE, EnemyManager.STATE_ATTACK, EnemyManager.STATE_SPAWN]:
		em.state[reg] = st
		assert_bool(rl.eligible(reg)).is_false()
	em.state[reg] = EnemyManager.STATE_MOVE
	assert_bool(rl.eligible(reg)).is_true()
	# an Elite by its kind, a special type (the gear badge), a training dummy, a boss
	assert_bool(rl.eligible(_put(em, "stone_golem", Vector3(-30, 0, 0)))).is_false()
	assert_bool(rl.eligible(_put(em, "harpoon_troglodyte", Vector3(0, 0, 30)))).is_false()
	assert_bool(rl.eligible(_put(em, "training_dummy", Vector3(0, 0, -30)))).is_false()
	var boss := em.spawn_boss("tumbleweed_king", Vector3(30, 0, 30))
	assert_int(boss).is_greater_equal(0)
	em.state[boss] = EnemyManager.STATE_MOVE
	em.rise_t[boss] = 1.0
	em.rise_v[boss] = 0.0
	assert_bool(rl.eligible(boss)).is_false()
	# a boss's summon while its boss lives
	em.summoned[reg] = 1
	assert_bool(rl.eligible(reg)).is_false()
	em.summoned[reg] = 0
	assert_bool(rl.eligible(reg)).is_true()


func test_a_row_switches_a_creature_off_and_a_squad_on() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg())
	var rl: CrowdRelocate = em.relocate
	# a regular creature whose row says no
	em.row_relocate = 0
	var off := _put(em, "skeleton", Vector3(30, 0, 0))
	em.row_relocate = -1
	assert_int(em.reloc_may[off]).is_equal(CrowdRelocate.MAY_OFF)
	assert_bool(rl.may(off)).is_false()
	assert_bool(rl.eligible(off)).is_false()
	# a squad creature (the Monk): off by default, on when its row says so
	var monk := _put(em, "monk", Vector3(-30, 0, 0))
	assert_int(em._t_squad[em.type_idx[monk]]).is_equal(1)
	assert_int(em.reloc_may[monk]).is_equal(CrowdRelocate.MAY_DEFAULT)
	assert_bool(rl.may(monk)).is_false()
	em.row_relocate = 1
	var monk_on := _put(em, "monk", Vector3(-30, 0, 4))
	em.row_relocate = -1
	assert_int(em.reloc_may[monk_on]).is_equal(CrowdRelocate.MAY_ON)
	assert_bool(rl.may(monk_on)).is_true()
	# the map's `squads` true: every squad creature by default, a row's no still holds
	em.set_relocate(_cfg({"squads": true}))
	assert_bool(rl.may(monk)).is_true()
	assert_bool(rl.may(off)).is_false()
	# a slot's next creature starts clean
	em.reloc_far[off] = 4.0
	em.reloc_queued[off] = 1
	em.despawn(off)
	var again := _put(em, "skeleton", Vector3(30, 0, 0))
	assert_int(again).is_equal(off)
	assert_int(em.reloc_may[again]).is_equal(CrowdRelocate.MAY_DEFAULT)
	assert_float(em.reloc_far[again]).is_equal(0.0)
	assert_int(em.reloc_queued[again]).is_equal(0)


# ---------------------------------------------------------------- 3. the far time and the queue

func test_the_far_time_counts_resets_and_fills_the_queue_in_order() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"seconds": 2.0, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	var ppos := Vector3.ZERO
	var a := _put(em, "skeleton", Vector3(30, 0, 0))
	var b := _put(em, "skeleton", Vector3(0, 0, 30))
	var near := _put(em, "skeleton", Vector3(5, 0, 0))
	var edge := _put(em, "skeleton", Vector3(16.0, 0, 0))
	for k in range(3):
		assert_int(rl.scan_crowd(ppos)).is_equal(0)
	assert_float(em.reloc_far[a]).is_equal_approx(1.5, 1e-5)
	assert_float(em.reloc_far[b]).is_equal_approx(1.5, 1e-5)
	# within the distance (exactly on it too): no far time
	assert_float(em.reloc_far[near]).is_equal(0.0)
	assert_float(em.reloc_far[edge]).is_equal(0.0)
	assert_bool(rl.queue.is_empty()).is_true()
	# one that comes near starts again from 0
	em.pos[b] = Vector3(0, 0, 10)
	rl.scan_crowd(ppos)
	assert_float(em.reloc_far[b]).is_equal(0.0)
	# the 4th scan: `seconds` reached, it joins once
	assert_int(rl.queue.size()).is_equal(1)
	assert_int((rl.queue[0] as Vector2i).x).is_equal(a)
	assert_int(em.reloc_queued[a]).is_equal(1)
	rl.scan_crowd(ppos)
	assert_int(rl.queue.size()).is_equal(1)
	# several in one scan join in index order
	em.pos[b] = Vector3(0, 0, 30)
	em.pos[near] = Vector3(-30, 0, 0)
	em.reloc_far[b] = 1.5
	em.reloc_far[near] = 1.5
	assert_int(rl.scan_crowd(ppos)).is_equal(2)
	assert_int(rl.queue.size()).is_equal(3)
	assert_int((rl.queue[1] as Vector2i).x).is_equal(mini(b, near))
	assert_int((rl.queue[2] as Vector2i).x).is_equal(maxi(b, near))
	# one that cannot go now (held) keeps its far time and is not counted on
	em.held[edge] = 1
	em.pos[edge] = Vector3(40, 0, 0)
	em.reloc_far[edge] = 1.0
	rl.scan_crowd(ppos)
	assert_float(em.reloc_far[edge]).is_equal(1.0)


func test_the_queue_hands_over_its_first_and_drops_the_ones_that_came_near() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"seconds": 1.0, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	var ppos := Vector3.ZERO
	var ids: Array = []
	for k in range(4):
		ids.append(_put(em, "skeleton", Vector3(30, 0, float(k) * 2.0)))
	rl.scan_crowd(ppos)
	rl.scan_crowd(ppos)
	assert_int(rl.queue.size()).is_equal(4)
	var first: int = (rl.queue[0] as Vector2i).x
	var second: int = (rl.queue[1] as Vector2i).x
	var third: int = (rl.queue[2] as Vector2i).x
	var fourth: int = (rl.queue[3] as Vector2i).x
	# the first goes: it stands, sinks, is out of the queue, its far time starts again
	em.vel[first] = Vector3(1, 0, 0)
	em.kb[first] = Vector3(0, 0, 3)
	assert_int(rl.hand_over(ppos)).is_equal(first)
	assert_int(em.state[first]).is_equal(EnemyManager.STATE_SPAWN)
	assert_float(em.rise_v[first]).is_less(0.0)
	assert_float(em.rise_t[first]).is_less(1.0)
	assert_object(em.vel[first]).is_equal(Vector3.ZERO)
	assert_object(em.kb[first]).is_equal(Vector3.ZERO)
	assert_int(em.reloc_queued[first]).is_equal(0)
	assert_float(em.reloc_far[first]).is_equal(0.0)
	assert_int(rl.moving.size()).is_equal(1)
	assert_int(rl.sunk).is_equal(1)
	# the second came near and the third died meanwhile: both are dropped, the fourth goes
	em.pos[second] = Vector3(6, 0, 0)
	em.despawn(third)
	assert_int(rl.hand_over(ppos)).is_equal(fourth)
	assert_int(rl.dropped).is_equal(2)
	assert_bool(rl.queue.is_empty()).is_true()
	assert_int(em.reloc_queued[second]).is_equal(0)
	assert_int(rl.hand_over(ppos)).is_equal(-1)


func test_the_queue_gives_one_creature_every_interval() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"seconds": 0.5, "scan": 0.5, "every": 0.4}))
	var rl: CrowdRelocate = em.relocate
	for k in range(6):
		_put(em, "skeleton", Vector3(30, 0, float(k) * 2.0))
	var went_at: Array = []
	var before := 0
	for t in range(1, 121):
		rl.tick(DT, Vector3.ZERO)
		if rl.sunk > before:
			# never two in one tick
			assert_int(rl.sunk - before).is_equal(1)
			before = rl.sunk
			went_at.append(t)
	# the first scan (tick 1) gives them their half second and queues all six; one goes every 24 ticks (0.4 s)
	assert_int(int(went_at[0])).is_equal(1)
	assert_int(went_at.size()).is_equal(5)
	for k in range(1, went_at.size()):
		assert_int(int(went_at[k]) - int(went_at[k - 1])).is_equal(24)
	# each of the six goes once (a sinking one is not taken again)
	assert_int(rl.queued_total).is_equal(6)


# ---------------------------------------------------------------- 4. the move

func test_a_far_creature_behind_the_crowd_rises_in_the_empty_half() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	em.set_relocate(_cfg({"seconds": 1.0, "scan": 0.25}))
	var rl: CrowdRelocate = em.relocate
	# a crowd in every sector of the +X half, 13 m out (inside the distance: none of them is far)
	for k in range(-6, 7):
		var a := deg_to_rad(float(k) * 14.0)
		_put(em, "skeleton", Vector3(cos(a), 0, sin(a)) * 13.0)
		_put(em, "skeleton", Vector3(cos(a), 0, sin(a)) * 14.5)
	# the trailing one, far behind them on the same side, hurt
	var far := _put(em, "skeleton", Vector3(44, 0, 3))
	em.hp[far] = em.max_hp[far] * 0.4
	var hp0: float = em.hp[far]
	var serial0: int = em.serial[far]
	var alive0 := em.alive_count()
	var kills0 := Run.kills
	var sank := false
	var t := 0
	while rl.relocated == 0 and t < 600:
		em._physics_process(DT)
		t += 1
		if em.rise_v[far] < 0.0:
			sank = true
			# it stands while it sinks
			assert_int(em.state[far]).is_equal(EnemyManager.STATE_SPAWN)
	assert_int(rl.relocated).is_equal(1)
	assert_bool(sank).is_true()
	assert_int(int(rl.last["i"])).is_equal(far)
	# the opposite half, inside the ring, above the sand again
	var p: Vector3 = em.pos[far]
	assert_float(p.x).is_less(0.0)
	assert_float(_flat(p)).is_between(19.0 - 0.01, 24.0 + 0.01)
	assert_int(em.hidden[far]).is_equal(0)
	assert_float(em.rise_v[far]).is_greater(0.0)
	assert_int(em.state[far]).is_equal(EnemyManager.STATE_SPAWN)
	# the same creature: its health, its serial; nothing spawned, nothing killed
	assert_float(em.hp[far]).is_equal(hp0)
	assert_int(em.serial[far]).is_equal(serial0)
	assert_int(em.alive_count()).is_equal(alive0)
	assert_int(Run.kills).is_equal(kills0)
	assert_object(em.vel[far]).is_equal(Vector3.ZERO)
	assert_object(em.kb[far]).is_equal(Vector3.ZERO)
	assert_float(em.reloc_far[far]).is_equal(0.0)
	# it comes up and walks on
	var up := 0
	while em.state[far] != EnemyManager.STATE_MOVE and up < 240:
		em._physics_process(DT)
		up += 1
	assert_int(em.state[far]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.rise_t[far]).is_equal(1.0)
	assert_float(em.hp[far]).is_equal(hp0)


func test_the_emptiest_sector_wins_and_a_placed_one_counts() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"sectors": 4}))
	var rl: CrowdRelocate = em.relocate
	var ppos := Vector3(3, 0, -2)
	# sectors of 90 degrees from +X towards +Z: three hold creatures, the one round -Z (270 degrees) holds none
	_put(em, "skeleton", ppos + Vector3(10, 0, 10))
	_put(em, "skeleton", ppos + Vector3(12, 0, 9))
	_put(em, "skeleton", ppos + Vector3(-10, 0, 10))
	_put(em, "skeleton", ppos + Vector3(-10, 0, -10))
	# one past the ring's reach counts nowhere, a buried one neither
	_put(em, "skeleton", ppos + Vector3(40, 0, -40))
	var buried := _put(em, "skeleton", ppos + Vector3(10, 0, -10))
	em.hidden[buried] = 1
	var counts := rl.sector_counts(ppos)
	assert_array(Array(counts)).is_equal([2, 1, 1, 0])
	assert_int(rl.sector_of(1.0, 0.1)).is_equal(0)
	assert_int(rl.sector_of(-0.1, 1.0)).is_equal(1)
	assert_int(rl.sector_of(-1.0, -0.1)).is_equal(2)
	assert_int(rl.sector_of(0.1, -1.0)).is_equal(3)
	var order := rl.sector_order(counts)
	assert_int(order[0]).is_equal(3)
	assert_int(order[3]).is_equal(0)
	var far := _put(em, "skeleton", ppos + Vector3(-50, 0, 0))
	rl.place(far, ppos)
	var d: Vector3 = em.pos[far] - ppos
	assert_int(rl.sector_of(d.x, d.z)).is_equal(3)
	assert_float(_flat(d)).is_between(19.0 - 0.01, 24.0 + 0.01)
	# with every sector at one or two now, the next goes to one of the three with one
	var next := _put(em, "skeleton", ppos + Vector3(-50, 0, 4))
	rl.place(next, ppos)
	var d2: Vector3 = em.pos[next] - ppos
	assert_int(rl.sector_of(d2.x, d2.z)).is_not_equal(0)
	assert_int(rl.relocated).is_equal(2)
	assert_int(int(rl.relocated_by.get("skeleton", 0))).is_equal(2)


func test_a_point_outside_the_arena_is_never_taken() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg())
	var rl: CrowdRelocate = em.relocate
	# the outlaw by the east wall: the sectors past it are empty, and no place may lie out there
	var ppos := Vector3(em.arena_radius - 6.0, 0, 0)
	for k in range(12):
		var far := _put(em, "skeleton", Vector3(-20, 0, float(k)))
		rl.place(far, ppos)
		assert_float(_flat(em.pos[far])).is_less_equal(em.arena_radius - 2.0 + 0.01)
		assert_float(_flat(em.pos[far] - ppos)).is_greater_equal(19.0 - 0.01)


func test_a_flyer_goes_at_once_and_only_off_the_screen() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	em.set_relocate(_cfg({"seconds": 0.5, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	var crow := _put(em, "carrion_crow", Vector3(30, 0, 0))
	assert_bool((em.types[em.type_idx[crow]]["def"] as EnemyDef).flies).is_true()
	em.onscreen.resize(em.pool_max)
	em.onscreen[crow] = 1
	rl.scan_crowd(Vector3.ZERO)
	assert_int(rl.queue.size()).is_equal(1)
	# seen: it stays where it is
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(-1)
	assert_object(em.pos[crow]).is_equal(Vector3(30, em.pos[crow].y, 0))
	# not seen: moved at once, no sink, no rise
	em.onscreen[crow] = 0
	rl.scan_crowd(Vector3.ZERO)
	assert_int(rl.hand_over(Vector3.ZERO)).is_equal(crow)
	assert_int(rl.relocated).is_equal(1)
	assert_bool(rl.moving.is_empty()).is_true()
	assert_int(em.state[crow]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.rise_t[crow]).is_equal(1.0)
	assert_float(_flat(em.pos[crow])).is_between(19.0 - 0.01, 24.0 + 0.01)


# ---------------------------------------------------------------- 5. off

func test_off_without_a_director_in_the_arena_and_when_disabled() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# a manager nobody configured: no relocation at all
	assert_object(em.relocate).is_null()
	var far := _put(em, "skeleton", Vector3(40, 0, 0))
	for k in range(400):
		em._physics_process(DT)
	assert_object(em.relocate).is_null()
	assert_float(em.pos[far].x).is_greater(24.0)
	# {} and enabled false make nothing
	em.set_relocate({})
	em.set_relocate(_cfg({"enabled": false}))
	assert_object(em.relocate).is_null()
	# the director: the map's block in a run, nothing in the arena
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = Registry.map("red_canyon").timeline.duplicate(true)
	Run.arena = true
	d._apply_mults()
	assert_object(em.relocate).is_null()
	Run.arena = false
	d._apply_mults()
	assert_object(em.relocate).is_not_null()
	assert_bool(em.relocate.on).is_equal(bool(d.timeline.relocate_cfg()["enabled"]))
	assert_float(em.relocate.distance).is_equal_approx(float(d.timeline.relocate_cfg()["distance"]), 1e-6)
	# back in the arena it is switched off, and its clocks do nothing
	Run.arena = true
	d._apply_mults()
	assert_bool(em.relocate.on).is_false()
	em.reloc_far[far] = 0.0
	for k in range(120):
		em.relocate.tick(DT, Vector3.ZERO)
	assert_float(em.reloc_far[far]).is_equal(0.0)
	assert_int(em.relocate.relocated).is_equal(0)


func test_nothing_relocates_while_a_boss_barrier_stands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg({"seconds": 0.5, "scan": 0.5}))
	var rl: CrowdRelocate = em.relocate
	var far := _put(em, "skeleton", Vector3(40, 0, 0))
	em.patterns = BossPatterns.new(em)
	em.patterns.runs[999] = {"wall": {"up": true, "c": Vector3.ZERO, "r": 14.0, "half": 0.5, "hero_limit": 13.0}}
	assert_bool(rl.barrier_stands()).is_true()
	for k in range(180):
		rl.tick(DT, Vector3.ZERO)
	assert_float(em.reloc_far[far]).is_equal(0.0)
	assert_int(rl.sunk).is_equal(0)
	# the barrier falls: the clocks go on
	em.patterns.runs.clear()
	assert_bool(rl.barrier_stands()).is_false()
	for k in range(180):
		rl.tick(DT, Vector3.ZERO)
	assert_int(rl.sunk).is_equal(1)


# ---------------------------------------------------------------- 6. the dice

func _places(seed_value: int) -> Array:
	Dice.reseed(seed_value)
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_relocate(_cfg())
	var rl: CrowdRelocate = em.relocate
	var out: Array = []
	for k in range(10):
		var i := _put(em, "skeleton", Vector3(40, 0, float(k) * 2.0))
		rl.place(i, Vector3.ZERO)
		out.append(em.pos[i])
	return out


func test_the_same_seed_gives_the_same_places() -> void:
	var a := _places(4242)
	var b := _places(4242)
	var c := _places(977)
	assert_int(a.size()).is_equal(10)
	var same := 0
	for k in range(10):
		assert_object(b[k]).is_equal(a[k])
		if (c[k] as Vector3).is_equal_approx(a[k]):
			same += 1
	# another seed, other places
	assert_int(same).is_less(10)
	Dice.reseed(0)


# ---------------------------------------------------------------- 7. the row's key

func test_a_rows_say_as_the_manager_takes_it() -> void:
	assert_int(WaveTimeline.row_relocate({})).is_equal(-1)
	assert_int(WaveTimeline.row_relocate({"enemy": "skeleton"})).is_equal(-1)
	assert_int(WaveTimeline.row_relocate({"relocate": true})).is_equal(1)
	assert_int(WaveTimeline.row_relocate({"relocate": false})).is_equal(0)
	# an elite row and a special row never, whatever the key says
	assert_int(WaveTimeline.row_relocate({"elite": "random", "relocate": true})).is_equal(0)
	assert_int(WaveTimeline.row_relocate({"special": true, "relocate": true})).is_equal(0)
	assert_int(WaveTimeline.row_relocate({"elite": "", "special": false})).is_equal(-1)
	assert_int(WaveTimeline.row_relocate(null)).is_equal(-1)


func _director(w: Dictionary, row: Dictionary) -> WaveDirector:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline.duplicate(true)
	tl.roster = [row]
	tl.events = []
	tl.waves = []
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = tl
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	w["g"].set("director", d)
	d._apply_mults()
	return d


## What the creatures alive carry after a "once" row of three skeletons with `extra` keys has come.
func _row_says(extra: Dictionary) -> Array:
	var w := _world()
	var em: EnemyManager = w["em"]
	var row := {"id": "p128_row", "t": 469, "until": 471, "enemy": "skeleton", "weights": [[469, 8.0], [537, 8.0]],
		"pack": 3, "pattern": "scatter", "pace": "once", "count": 3}
	row.merge(extra, true)
	var d := _director(w, row)
	Run.elapsed = 470.0
	for k in range(3):
		d._process_events()
		d._tick_row_waves()
	var out: Array = []
	for i in range(em.pool_max):
		if em.alive[i] == 1:
			out.append(int(em.reloc_may[i]))
	# the flag never stays up after the row's spawns
	assert_int(em.row_relocate).is_equal(-1)
	return out


func test_a_rows_key_rides_to_its_creatures() -> void:
	var plain := _row_says({})
	assert_int(plain.size()).is_equal(3)
	for m in plain:
		assert_int(m).is_equal(CrowdRelocate.MAY_DEFAULT)
	var off := _row_says({"relocate": false})
	assert_int(off.size()).is_equal(3)
	for m in off:
		assert_int(m).is_equal(CrowdRelocate.MAY_OFF)
	var on := _row_says({"relocate": true})
	assert_int(on.size()).is_equal(3)
	for m in on:
		assert_int(m).is_equal(CrowdRelocate.MAY_ON)
	var special := _row_says({"special": true})
	assert_int(special.size()).is_equal(3)
	for m in special:
		assert_int(m).is_equal(CrowdRelocate.MAY_OFF)


func test_the_plain_rows_spawn_call_carries_the_key_too() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var d := _director(w, {"id": "p128_plain", "t": 0, "until": 9999, "enemy": "skeleton", "weights": [[0, 1.0]]})
	var came := d._spawn_group_row({"enemy": "skeleton", "relocate": false}, "skeleton", 2, "scatter", 1, null, "", {})
	assert_int(came).is_equal(2)
	assert_int(em.row_relocate).is_equal(-1)
	var n := 0
	for i in range(em.pool_max):
		if em.alive[i] == 1:
			n += 1
			assert_int(em.reloc_may[i]).is_equal(CrowdRelocate.MAY_OFF)
	assert_int(n).is_equal(2)
