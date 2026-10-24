extends GdUnitTestSuite

## Pass 102, lane HITS (Garry's phone run: a late Endless crowd, nearly all burning and poisoned, the damage numbers at
## their cap, a hit sound for every hit). Only the work and the drawing got cheaper, never a number:
## - the burn's and the poison's clocks (EnemyManager._tick_fire_body, _tick_poison_body) deal exactly what pass 101's
##   did over the same scene with the same seed (pass 101's code is copied below and run side by side);
## - the flames come further apart when more than FIRE_FX_FULL burning creatures are drawn, and none off the screen;
## - a non-killing hit's sound plays at most once every HIT_SOUND_GAP_MS per sound, a crit always;
## - the damage numbers: from CROWD in the air a hit joins its creature's number while it shows whole, a small plain hit
##   or a tick with nothing to join is let go, a crit always shows, and at CAP the oldest number is reused.

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
var flames := 0
var puffs := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_fire(_a, _b = 1.0, _c = false) -> void:
	flames += 1
func fx_poison(_a) -> void:
	puffs += 1
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
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
func heal(_a: float, _s: String = "") -> void:
	pass
"""

const FAKE_PICKUPS := """extends Node
func spawn(_kind: int, _at: Vector3, _v: float) -> int:
	return 0
func spawn_chest(_at: Vector3, _boss: bool = false) -> void:
	pass
func add_attractor(_p: Vector3, _r: float) -> void:
	pass
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	EnemyManager.prof_hits = false
	EnemyManager.hit_sound_gap_ms = EnemyManager.HIT_SOUND_GAP_MS
	EnemyManager.fire_fx_full = EnemyManager.FIRE_FX_FULL
	DamageNumbers.crowd_from = DamageNumbers.CROWD


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
	hero.global_position = Vector3(60, 0, 60)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	em._rebuild_grid()
	return {"g": g, "em": em}


## A packed crowd of `n` skeletons (a grid 0.9 m apart, so fire can spread), some weak enough to die of their burns.
func _crowd(em: EnemyManager, n: int) -> Array:
	em._rng.seed = 4242
	var out: Array = []
	for k in range(n):
		var at := Vector3(float(k % 6) * 0.9, 0.0, float(k / 6) * 0.9)
		var i := em.spawn("skeleton", at, null, 1.0, 3.0 if k % 5 == 0 else 400.0)
		assert_int(i).is_greater_equal(0)
		em.state[i] = EnemyManager.STATE_MOVE
		out.append(i)
	em._rebuild_grid()
	em._rng.seed = 777
	return out


## The scene both ways: burns (one spreading, one blue, two sources on some) and poisons (stacks, two sources), `ticks`
## physics ticks of the clocks, the run's damage by weapon and every creature's HP afterwards.
func _play(old: bool, ticks: int) -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.player_sheet.add_effects([Effect.make("debuff_jump", "add", 1.0, "player")], "test prairie")
	var w := _world()
	var em: EnemyManager = w["em"]
	em.refresh_player_stats()
	var ids := _crowd(em, 30)
	for k in range(ids.size()):
		var i: int = ids[k]
		if k % 3 == 0:
			em.ignite(i, "molotov", 4.0 + k, 2.4 + 0.1 * k, 0.35)
		if k % 4 == 0:
			em.ignite(i, "dragons_breath", 6.0, 1.3, 0.0)
		if k % 2 == 1:
			em.poison(i, "venom", 1.5 + 0.25 * k, 1 + k % 3, 4.0 + 0.2 * k)
		if k % 7 == 0:
			em.poison(i, "poison_razors", 2.0, 2, 3.0)
	for t in range(ticks):
		for i: int in ids:
			if em.alive[i] == 0:
				continue
			if old:
				_old_tick_poison(em, i, DT)
			else:
				em._tick_poison(i, DT)
			if em.alive[i] == 0:
				continue
			if old:
				_old_tick_fire(em, i, DT)
			else:
				em._tick_fire(i, DT)
		# a later burn on top, part way through
		if t == 100:
			for k in range(0, ids.size(), 5):
				em.ignite(ids[k], "molotov", 9.0, 1.8, 0.5)
	var hp: Array = []
	var burning: Array = []
	for i: int in ids:
		hp.append(em.hp[i] if em.alive[i] == 1 else -1.0)
		burning.append((em.fire_src[i] as Dictionary).keys())
	return {"dmg": Run.damage_by_weapon.duplicate(), "hp": hp, "burning": burning, "kills": Run.kills, "rng": em._rng.state}


func test_burn_and_poison_deal_exactly_what_they_did() -> void:
	var a := _play(true, 420)
	var b := _play(false, 420)
	var dmg_a: Dictionary = a["dmg"]
	var dmg_b: Dictionary = b["dmg"]
	assert_array(dmg_b.keys()).contains_exactly_in_any_order(dmg_a.keys())
	var total := 0.0
	for k in dmg_a.keys():
		assert_float(float(dmg_b[k])).override_failure_message("damage of %s" % k).is_equal(float(dmg_a[k]))
		total += float(dmg_a[k])
	# the scene did burn and poison, spread and kill
	assert_float(total).is_greater(1000.0)
	assert_int(int(a["kills"])).is_greater(0)
	assert_int(int(b["kills"])).is_equal(int(a["kills"]))
	assert_array(b["hp"]).is_equal(a["hp"])
	assert_array(b["burning"]).is_equal(a["burning"])
	# the spread rolled the same dice
	assert_int(int(b["rng"])).is_equal(int(a["rng"]))


func test_flames_thin_out_when_many_burn_and_none_off_screen() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g = w["g"]
	var ids := _crowd(em, 12)
	for i: int in ids:
		em.ignite(i, "x", 1.0, 30.0, 0.0)
	# a few burning: every FIRE_PUFF each
	assert_float(em.fire_puff_every()).is_equal(EnemyManager.FIRE_PUFF)
	for t in range(60):
		for i: int in ids:
			em._tick_fire(i, DT)
		em._hits_tick_end()
	var few: int = g.flames
	# 1 s at FIRE_PUFF: about 5-6 flames each
	assert_int(few).is_between(12 * 5, 12 * 7)
	# many burning on the screen: further apart, about the same flames on the screen as FIRE_FX_FULL would make
	em._burn_drawn_last = EnemyManager.FIRE_FX_FULL * 3
	assert_float(em.fire_puff_every()).is_equal_approx(EnemyManager.FIRE_PUFF * 3.0, 0.0001)
	EnemyManager.fire_fx_full = 0
	assert_float(em.fire_puff_every()).is_equal(EnemyManager.FIRE_PUFF)
	EnemyManager.fire_fx_full = EnemyManager.FIRE_FX_FULL
	# off the screen: no flame, no puff, the burn and its damage unchanged
	g.flames = 0
	var i0: int = ids[0]
	em.drawn_vis[i0] = 0
	em.poison(i0, "p", 1.0, 1, 10.0)
	var hp0: float = em.hp[i0]
	for t in range(130):
		em._tick_fire(i0, DT)
		em._tick_poison(i0, DT)
	assert_int(g.flames).is_equal(0)
	assert_int(g.puffs).is_equal(0)
	assert_float(em.hp[i0]).is_less(hp0)
	em.drawn_vis[i0] = 1
	for t in range(130):
		em._tick_poison(i0, DT)
	assert_int(g.puffs).is_greater(0)


func test_hit_sounds_are_limited_and_crits_keep_theirs() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids := _crowd(em, 6)
	var played0 := em.hit_sounds
	for k in range(20):
		em.damage(ids[k % 6], 1.0)
	# within one gap: one sound for the skeletons' shared hit sound, the rest let go
	assert_int(em.hit_sounds - played0).is_equal(1)
	assert_int(em.hit_sounds_gated).is_equal(19)
	# a crit always plays (HIT_CRIT forces it; the weapon id makes it a weapon hit)
	Run.debug_set_item("weapon", "revolver", 1)
	em.damage(ids[0], 1.0, "revolver", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_int(em.hit_sounds - played0).is_equal(2)
	# the old rule (gap 0): every hit
	EnemyManager.hit_sound_gap_ms = 0
	for k in range(5):
		em.damage(ids[1], 1.0)
	assert_int(em.hit_sounds - played0).is_equal(7)
	EnemyManager.hit_sound_gap_ms = EnemyManager.HIT_SOUND_GAP_MS
	# after the gap a hit sounds again
	var until := Time.get_ticks_msec() + EnemyManager.HIT_SOUND_GAP_MS + 5
	while Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	em.damage(ids[2], 1.0)
	assert_int(em.hit_sounds - played0).is_equal(8)


func test_damage_reads_the_hero_s_crit_and_guillotine_as_they_are() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids := _crowd(em, 6)
	Run.debug_set_item("weapon", "revolver", 1)
	var i: int = ids[1]
	em.damage(i, 1.0, "revolver")
	# a crit chance of 1 added by hand (no build_changed, no tick): the next hit crits, for crit_damage x
	Run.player_sheet.add_effects([Effect.make("crit_chance", "set", 1.0, "player")], "test crit")
	var hp0: float = em.hp[i]
	em.damage(i, 10.0, "revolver")
	assert_bool(em.last_crit).is_true()
	assert_float(hp0 - em.hp[i]).is_equal_approx(10.0 * Run.player_sheet.get_stat("crit_damage", 2.0) * (1.0 - em.dr[i]), 0.01)
	# set on the sheet's base by hand (pass 61's way): seen at once too
	Run.player_sheet.remove_source("test crit")
	Run.player_sheet.set_base("crit_chance", 1.0)
	em.damage(i, 1.0, "revolver")
	assert_bool(em.last_crit).is_true()
	Run.player_sheet.set_base("crit_chance", 0.0)
	# taken away again: no crit
	Run.player_sheet.add_effects([Effect.make("crit_chance", "set", 0.0, "player")], "test nocrit")
	em.damage(i, 1.0, "revolver")
	assert_bool(em.last_crit).is_false()
	# Guillotine added by hand finishes a creature under its share
	Run.player_sheet.add_effects([Effect.make("execute_frac", "add", 0.99, "player"), Effect.make("execute_frac", "add", 0.0, "player")], "test guillotine")
	var j: int = ids[2]
	em.hp[j] = em.max_hp[j] * 0.05
	em.damage(j, 0.01, "revolver")
	assert_bool(em.alive[j] == 0 or em.state[j] == EnemyManager.STATE_DYING).is_true()


# ---------------------------------------------------------------- the numbers

func _numbers() -> DamageNumbers:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.position = Vector3(0, 10, 10)
	cam.look_at(Vector3.ZERO)
	cam.make_current()
	var dn: DamageNumbers = auto_free(DamageNumbers.new())
	add_child(dn)
	return dn


func test_a_full_screen_joins_hits_and_lets_small_ones_go() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	for k in range(DamageNumbers.CROWD):
		dn.add(k, Vector3.ZERO, 10.0)
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	dn.step(0.3)
	# past MERGE, but still showing whole: a hit on creature 5 joins its number (no new one)
	dn.add(5, Vector3.ZERO, 7.0)
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	var five: DamageNumbers.Num = dn.live()[5]
	assert_float(five.amount).is_equal_approx(17.0, 0.001)
	assert_float(five.bump).is_equal(1.0)
	assert_int(dn.crowd_merged).is_equal(1)
	# a small plain hit on a creature with no number is let go; a big one shows
	dn.add(100, Vector3.ZERO, 4.0)
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	assert_int(dn.crowd_dropped).is_equal(1)
	# a big one shows, in the oldest one's place: a full screen holds CROWD creature numbers, not CAP
	var oldest: DamageNumbers.Num = dn.live()[0]
	dn.add(101, Vector3.ZERO, 50.0)
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	assert_object(dn.live().back()).is_same(oldest)
	assert_int(oldest.who).is_equal(101)
	# a crit on a creature with a number up joins it and turns it a crit (yellow, big, popping)
	var six: DamageNumbers.Num = _num_of(dn, 6)
	dn.add(6, Vector3.ZERO, 1.0, true)
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	assert_bool(six.crit).is_true()
	assert_float(six.amount).is_equal_approx(11.0, 0.001)
	# a crit, however small, on a creature with none shows (its own number, its hop)
	dn.add(102, Vector3.ZERO, 1.0, true)
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	assert_bool((dn.live().back() as DamageNumbers.Num).crit).is_true()
	assert_int((dn.live().back() as DamageNumbers.Num).who).is_equal(102)
	# fire ticks with no number to join: at most TICK_CAP_CROWD of them
	for k in range(30):
		dn.add(200 + k, Vector3.ZERO, 3.0, false, false, true)
	assert_int(dn._ticks).is_equal(DamageNumbers.TICK_CAP_CROWD)
	# a tick on a creature with a tick number up joins it: a running total
	dn.add(200, Vector3.ZERO, 3.0, false, false, true)
	assert_int(dn._ticks).is_equal(DamageNumbers.TICK_CAP_CROWD)
	# the hero's numbers are never thinned
	var n0 := dn.count()
	dn.hero_hurt(2.0)
	assert_int(dn.count()).is_equal(n0 + 1)


## The newest number on creature `who` (null for none).
func _num_of(dn: DamageNumbers, who: int) -> DamageNumbers.Num:
	for k in range(dn.live().size() - 1, -1, -1):
		var m: DamageNumbers.Num = dn.live()[k]
		if m.who == who:
			return m
	return null


func test_at_the_cap_the_oldest_number_is_reused() -> void:
	Settings.damage_numbers = true
	# pass 101's rule (no full screen) to fill the list to CAP
	DamageNumbers.crowd_from = 1 << 30
	var dn := _numbers()
	for k in range(DamageNumbers.CAP):
		dn.add(k, Vector3.ZERO, 10.0, true)
	assert_int(dn.count()).is_equal(DamageNumbers.CAP)
	var oldest: DamageNumbers.Num = dn.live()[0]
	dn.add(500, Vector3.ZERO, 3.0, true)
	assert_int(dn.count()).is_equal(DamageNumbers.CAP)
	# the same object, filled in again (nothing allocated), at the back
	assert_object(dn.live().back()).is_same(oldest)
	assert_int(oldest.who).is_equal(500)
	assert_float(oldest.age).is_equal(0.0)
	assert_float(oldest.amount).is_equal(3.0)
	# the reused one no longer stands for creature 0: a hit on 0 is a number of its own (a crit, so it shows)
	dn.add(0, Vector3.ZERO, 5.0, true)
	assert_int((dn.live().back() as DamageNumbers.Num).who).is_equal(0)
	# the lookup follows the list out
	dn.step(DamageNumbers.LIFE)
	assert_int(dn.count()).is_equal(0)
	assert_int(dn._newest.size()).is_equal(0)
	DamageNumbers.crowd_from = DamageNumbers.CROWD


func test_below_the_crowd_the_old_merge_window_holds() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	dn.add(3, Vector3.ZERO, 10.0)
	dn.step(DamageNumbers.MERGE + 0.01)
	dn.add(3, Vector3.ZERO, 4.0)
	assert_int(dn.count()).is_equal(2)
	# the switch still empties it
	Settings.damage_numbers = false
	dn.add(4, Vector3.ZERO, 4.0)
	assert_int(dn.count()).is_equal(2)
	Settings.damage_numbers = true


# ---------------------------------------------------------------- pass 101's clocks, as they were (for the comparison)

func _old_tick_fire(em: EnemyManager, i: int, delta: float) -> void:
	var src: Dictionary = em.fire_src[i]
	if src.is_empty():
		return
	var total := 0.0
	var best_id := ""
	var best := 0.0
	var gone := false
	for k in src.keys():
		var e: Dictionary = src[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			em._prairie_jump(i, true, str(k), e)
			src.erase(k)
			gone = true
			continue
		var part: float = float(e["dmg"])
		total += part
		if part > best:
			best = part
			best_id = str(k)
	if src.is_empty():
		em.fire_blue[i] = 0
		return
	if gone and em.fire_blue[i] == 1:
		var still := 0
		for k in src.keys():
			if bool((src[k] as Dictionary).get("blue", false)):
				still = 1
				break
		em.fire_blue[i] = still
	em.fire_puff[i] -= delta
	if em.fire_puff[i] <= 0.0:
		em.fire_puff[i] = 0.18
	em.fire_tick[i] -= delta
	if em.fire_tick[i] <= 0.0:
		em.fire_tick[i] = EnemyManager.FIRE_TICK
		for k in src.keys():
			var e: Dictionary = src[k]
			var chance := float(e["spread"])
			if chance <= 0.0:
				continue
			for j in em.indices_in_radius(em.pos[i], em.radius[i] + 1.2):
				if j == i or j == int(e["from"]) or em.alive[j] == 0 or em.state[j] == EnemyManager.STATE_DYING or j == em.boss_index:
					continue
				var touch: float = em.radius[i] + em.radius[j] + 0.25
				var d := em.pos[j] - em.pos[i]
				d.y = 0.0
				if d.length_squared() > touch * touch:
					continue
				if (em.fire_src[j] as Dictionary).has(k):
					continue
				if em._rng.randf() < chance:
					em.ignite(j, str(k), float(e["dmg"]), float(e["dur"]), float(e["root"]) * EnemyManager.CHILD_SPREAD, i, float(e["root"]))
		em._pstats()
		em.damage(i, (total) * (1.0 + em._fire_vuln) * em._ll_harder, best_id, Vector3.ZERO, 0.0, false, true)


func _old_tick_poison(em: EnemyManager, i: int, delta: float) -> void:
	var src: Dictionary = em.poison_src[i]
	if src.is_empty():
		return
	var total := 0.0
	var best_id := ""
	var best := 0.0
	for k in src.keys():
		var e: Dictionary = src[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			em._prairie_jump(i, false, str(k), e)
			src.erase(k)
			continue
		var part: float = float(e["dmg"]) * int(e["stacks"])
		total += part
		if part > best:
			best = part
			best_id = str(k)
	if src.is_empty():
		return
	em.poison_tick[i] -= delta
	if em.poison_tick[i] <= 0.0:
		em.poison_tick[i] = EnemyManager.POISON_TICK
		em._pstats()
		em.damage(i, total * em._ll_harder, best_id, Vector3.ZERO, 0.0, true)
