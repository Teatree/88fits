extends GdUnitTestSuite

## Pass 67, lane C (Polish 2): Fadeaway's kit as content and the Game side. The Basketball's folder, its path (On Fire,
## Full Court Press, Rebound), its evolution (Slam Dunk) and his hero mutation (Free Throw) on it, because his favourite
## is a passive (Evade at level 2); Footwork's words; the Game's hooks into the ball's behaviour (a catch, a hit on his
## health, an evade); the Timeout perk (a pickup landing beside him on a clock, one at a time, the clock starting over
## once it is used) and its leap (thrown clear towards the emptiest ground, untouchable, the crowd he left slowed);
## Buzzer Beater (a periodic buff: after `first`, then every `every`).

const LAUNCH := "user://debug_launch.json"
const STEP := 0.1

const FAKE_BEHAVIOR := """extends Node
var calls: Array = []
func on_hero_hit() -> void:
	calls.append("hit")
func on_hero_evaded() -> void:
	calls.append("evaded")
func on_caught(ex: Dictionary) -> void:
	calls.append(ex)
"""


func before_test() -> void:
	Save.data = Save._default()
	Run.arena_next = false


func after_test() -> void:
	if Save.sandboxed():
		Save.end_sandbox()
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	Run.arena_next = false
	Run.debug_clear_items()
	Run.end()
	if FileAccess.file_exists(LAUNCH):
		DirAccess.remove_absolute(LAUNCH)


## A real Game in the debug arena with Fadeaway (a hidden hero by name works there), the field emptied: no training
## dummy and no creature, so only what a test puts down counts.
func _game() -> Game:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"arena": true, "character": "fadeaway", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	g.clear_dummies()
	var em: EnemyManager = g.enemies
	for i in EnemyManager.MAX:
		if em.alive[i] == 1:
			em._free(i)
	em._rebuild_grid()
	return g


## The Game outlives Warmup's deferred finish (a freed Game would take its callback) before auto_free takes it.
func _done(g: Game) -> void:
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


## A tough creature standing where it was put.
func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	return i


## `secs` of the run clock in STEP steps: the buffs' clock (Run.elapsed, tick_timed) and the perks' ticks.
func _run_for(g: Game, secs: float) -> void:
	var n := int(round(secs / STEP))
	for k in range(n):
		Run.elapsed += STEP
		Run.tick_timed()
		g._tick_perks(STEP)


## The Timeouts lying on the ground now.
func _lying(g: Game, id: String) -> Array:
	var out: Array = []
	for p in g.pickups.specials:
		if is_instance_valid(p) and not p.taken and p.def and p.def.id == id:
			out.append(p)
	return out


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ---------------------------------------------------------------- the content

func test_the_registry_loads_clean_with_fadeaways_kit() -> void:
	assert_array(Registry.problems).is_empty()
	for id in ["basketball", "slam_dunk"]:
		assert_object(Registry.weapon(id)).override_failure_message(id).is_not_null()
	for id in ["on_fire", "full_court_press", "rebound", "free_throw"]:
		assert_object(Registry.mutation(id)).override_failure_message(id).is_not_null()
	for id in ["timeout", "buzzer_beater"]:
		assert_object(Registry.perk(id)).override_failure_message(id).is_not_null()
		assert_str(Registry.perk(id).hero).is_equal("fadeaway")
	assert_object(Registry.pickup("timeout")).is_not_null()
	# every icon painted, the ball's own 3D visual (a Projectile node instancing the GLB, no Held: his art says empty hands)
	for def: ContentDef in [Registry.weapon("basketball"), Registry.weapon("slam_dunk"), Registry.mutation("on_fire"),
			Registry.mutation("full_court_press"), Registry.mutation("rebound"), Registry.mutation("free_throw"),
			Registry.perk("timeout"), Registry.perk("buzzer_beater"), Registry.pickup("timeout"), Registry.character("fadeaway")]:
		assert_object(def.icon).override_failure_message(def.id + " has no icon").is_not_null()
	var ball: WeaponDef = Registry.weapon("basketball")
	assert_object(ball.visual).is_not_null()
	var vis: Node = auto_free(ball.visual.instantiate())
	assert_object(vis.get_node_or_null("Projectile")).is_not_null()
	assert_object(vis.get_node_or_null("Held")).is_null()
	assert_object(WeaponBehavior.projectile_source(vis)).is_not_null()
	# the evolution draws the same ball
	assert_str(Registry.weapon("slam_dunk").visual.resource_path).is_equal(ball.visual.resource_path)
	# every sound it names is in the sound map
	for w: WeaponDef in [ball, Registry.weapon("slam_dunk")]:
		for ev in ["fire", "hit", "catch"]:
			assert_bool(Registry.soundmap.entries.has(str(w.sfx[ev]))).override_failure_message("%s %s" % [w.id, ev]).is_true()
	for id in ["pk_timeout", "ui_buzzer"]:
		assert_bool(Registry.soundmap.entries.has(id)).override_failure_message(id).is_true()
	# the title's cut-out is painted
	assert_bool(ResourceLoader.exists("res://art/ui/wanted/hero_fadeaway.png")).is_true()


func test_the_basketball_is_his_own_one_ball_that_bounces_and_comes_back() -> void:
	var ball: WeaponDef = Registry.weapon("basketball")
	assert_str(ball.hero).is_equal("fadeaway")
	assert_str(ball.behavior).is_equal("ProjectileEmitter")
	assert_int(ball.max_level).is_equal(5)
	assert_str(ball.evolves_with).is_equal("")
	var p: Dictionary = ball.params
	assert_str(str(p.get("amount_mode", ""))).is_equal("bounces")
	assert_bool(bool(p.get("return", false))).is_true()
	assert_bool(bool(p.get("return_on_hit", false))).is_true()
	assert_bool(p.get("ricochet_any") is Dictionary).is_true()
	assert_bool(p.get("catch") is Dictionary).is_true()
	for k in ["refund", "heat_per", "heat_max"]:
		assert_bool((p["catch"] as Dictionary).has(k)).override_failure_message(k).is_true()
	# one ball a throw at level 1; levels add to `amount` (bounces), never a second ball's worth of words in the JSON
	var inst := WeaponInstance.new(ball, 1)
	inst.rebuild(StatSheet.new(), [inst])
	assert_int(inst.stat_int("amount", 0)).is_equal(1)
	# his start weapon, offered to nobody else
	assert_str(Registry.start_weapon_for(Registry.character("fadeaway")).id).is_equal("basketball")


func test_the_basketballs_path_is_whole() -> void:
	var ball: WeaponDef = Registry.weapon("basketball")
	var path: Array = Registry.mutations_of("basketball")
	assert_array(path.map(func(m: MutationDef) -> String: return m.mutation_kind)).is_equal(["element", "volume", "motion"])
	# pass 69 (lane BB, re-pinned on purpose): Alley-Oop took Full Court Press's volume slot (Full Court Press is hidden)
	assert_array(path.map(func(m: MutationDef) -> String: return m.id)).is_equal(["on_fire", "alley_oop", "rebound"])
	for m: MutationDef in path:
		assert_str(m.weapon).is_equal("basketball")
		assert_bool(m.is_hero()).is_false()
		assert_str(m.text).override_failure_message(m.id).is_not_empty()
	assert_str(Registry.mutation("on_fire").element).is_equal("fire")
	# the evolution names it back and is not hidden
	var evo: WeaponDef = Registry.weapon(ball.evolves_into)
	assert_str(evo.id).is_equal("slam_dunk")
	assert_bool(evo.is_evolution).is_true()
	assert_str(evo.evolved_from).is_equal("basketball")
	assert_str(evo.hero).is_equal("fadeaway")
	assert_bool(Registry.is_hidden(evo)).is_false()
	# the hero mutation sits on his start weapon, because his favourite is a passive (Evade, at level 2)
	var c: CharacterDef = Registry.character("fadeaway")
	assert_str(c.favourite_weapon).is_equal("")
	assert_str(c.favourite_passive).is_equal("evade")
	assert_object(Registry.passive("evade")).is_not_null()
	assert_str(str(c.favourite_passive_bonus.get("type", ""))).is_equal("level")
	assert_int(int(c.favourite_passive_bonus.get("value", 0))).is_equal(2)
	var ft: MutationDef = Registry.mutation("free_throw")
	assert_bool(ft.is_hero()).is_true()
	assert_str(ft.hero).is_equal("fadeaway")
	assert_str(ft.weapon).is_equal(Registry.start_weapon_for(c).id)
	assert_bool(ft.params.get("free_throw") is Dictionary).is_true()
	# the evolution keeps the path and has the last word: Rebound's way home, Alley-Oop's launch amplified (pass 69),
	# Slam Dunk's own black ball over On Fire's red and Alley-Oop's blue
	var sd := WeaponInstance.new(evo, 1)
	for m: MutationDef in path:
		sd.mutations.append(m)
	sd.rebuild(StatSheet.new(), [sd])
	assert_int(sd.stat_int("amount", 0)).is_equal(1)
	assert_float(float(sd.params["ricochet_any"]["reach"])).is_equal(float(evo.params["ricochet_any"]["reach"]))
	assert_int(int(sd.params["return_pierce"])).is_equal(80)
	assert_str(str(sd.params["tint"]["body"])).is_equal(str(evo.params["final"]["tint"]["body"]))
	assert_bool(bool(sd.params["catch"].get("heat_keep", false))).is_true()
	assert_bool(sd.params["catch"].get("slam") is Dictionary).is_true()


func test_footwork_reads_from_his_level_trait() -> void:
	var c: CharacterDef = Registry.character("fadeaway")
	assert_int(c.level_trait.size()).is_equal(1)
	assert_str((c.level_trait[0] as Effect).stat).is_equal("evade")
	assert_str(c.trait_name).is_equal("Footwork")
	assert_str(TextGen.hero_trait(c)).is_equal("Gain 0.5% evade chance per level.")
	assert_str(c.trait_text).is_equal(TextGen.hero_trait(c))
	assert_str(c.pronoun).is_equal("he")
	assert_str(TextGen.hero_trait_at(c, 10)).contains("5% evade chance")


func test_the_timeout_pickup_waits_long_enough_and_drops_only_from_the_perk() -> void:
	var pd: PickupDef = Registry.pickup("timeout")
	assert_str(pd.effect_kind).is_equal("leap")
	assert_float(pd.lifetime).is_greater_equal(22.0)
	assert_bool(bool(pd.params.get("small", false))).is_false()
	for k in ["push", "lift", "invuln", "slow", "slow_seconds", "slow_radius", "directions"]:
		assert_bool(pd.params.has(k)).override_failure_message(k).is_true()
	# no map rolls it from kills: only the perk (and the arena's DROPS tab) puts one down
	for m: MapDef in Registry.maps.values():
		if m.timeline == null:
			continue
		for r in m.timeline.pickups.get("roster", []):
			assert_str(str((r as Dictionary).get("id", ""))).override_failure_message(m.id).is_not_equal("timeout")
	assert_str(str(Registry.perk("timeout").params.get("pickup", ""))).is_equal(pd.id)


# ---------------------------------------------------------------- the Game side

func test_the_game_hands_the_catch_the_hit_and_the_evade_to_the_behaviour_that_answers() -> void:
	var g := _game()
	var fake := Node.new()
	var s := GDScript.new()
	s.source_code = FAKE_BEHAVIOR
	s.reload()
	fake.set_script(s)
	g.weapon_host.add_child(fake)
	var d: WeaponDef = Registry.weapon("basketball").duplicate()
	d.id = "p67_fake_ball"
	g._behaviors[d.id] = fake
	var w := WeaponInstance.new(d, 1)
	g.ball_caught(w, {"hits": 2})
	assert_int((fake.get("calls") as Array).size()).is_equal(1)
	assert_int(int((fake.get("calls") as Array)[0]["hits"])).is_equal(2)
	# a catch of a weapon nobody holds any more (thrown before it evolved) just ends
	var gone: WeaponDef = Registry.weapon("basketball").duplicate()
	gone.id = "p67_no_such_behaviour"
	g.ball_caught(WeaponInstance.new(gone, 1), {"hits": 1})
	assert_int((fake.get("calls") as Array).size()).is_equal(1)
	# a hit that reaches his health tells it; a hit on the Energy Shield does not; an evade does
	g.player.hit.emit()
	assert_array(fake.get("calls") as Array).contains(["hit"])
	var n := (fake.get("calls") as Array).size()
	g.player.shield_hit.emit(false)
	assert_int((fake.get("calls") as Array).size()).is_equal(n)
	g.player.evaded.emit()
	assert_array(fake.get("calls") as Array).contains(["evaded"])
	g._behaviors.erase(d.id)
	fake.queue_free()
	await _done(g)


func test_the_leap_throws_him_clear_untouchable_and_slows_the_crowd_he_left() -> void:
	var g := _game()
	var em: EnemyManager = g.enemies
	var here: Vector3 = g.player.global_position
	# the scan with nobody near: the first of twelve (Thruster Burst's own pick), or the way he faces when asked
	assert_bool(g._emptiest_dir(here, 12).is_equal_approx(Vector3(1, 0, 0))).is_true()
	assert_bool(g._emptiest_dir(here, 12, Vector3(-1, 0, 0)).is_equal_approx(Vector3(-1, 0, 0))).is_true()
	# a crowd close on his east side, one creature 6 m north, out of the ring; he faces east, into the crowd
	var near: Array = []
	for k in range(4):
		near.append(_creature(em, here + Vector3(1.2 + 0.5 * float(k), 0, 0.5 * float(k % 2))))
	var far := _creature(em, here + Vector3(0, 0, -6.0))
	g.player.facing = -PI * 0.5
	assert_bool(g.player.forward().is_equal_approx(Vector3(1, 0, 0))).is_true()
	g.player.invuln = 0.0
	g.player._kb = Vector3.ZERO
	g.player.velocity = Vector3.ZERO
	var pd: PickupDef = Registry.pickup("timeout")
	g.apply_pickup(pd, here)
	# thrown with Thruster Burst's push, a hop up: of the empty ways (the scan looks 5 m out, so the ways 30 degrees off the
	# crowd count as empty too) the one most away from the creatures round him, west, though he faced them
	var kb: Vector3 = g.player._kb
	assert_float(kb.length()).is_equal_approx(float(pd.params["push"]), 0.01)
	assert_bool(kb.normalized().is_equal_approx(Vector3(-1, 0, 0))).override_failure_message(str(kb)).is_true()
	assert_float(g.player.velocity.y).is_greater_equal(float(pd.params["lift"]) - 0.01)
	assert_float(g.player.invuln).is_greater_equal(float(pd.params["invuln"]) - 0.0001)
	# every creature within slow_radius of where he stood slowed by `slow` for `slow_seconds` and tinted; the far one not
	for i: int in near:
		assert_float(em.slow_f[i]).is_equal_approx(float(pd.params["slow"]), 0.0001)
		assert_float(em.slow_t[i]).is_equal_approx(float(pd.params["slow_seconds"]), 0.0001)
		assert_float(em.status_t[i]).is_greater(0.0)
	assert_float(em.slow_t[far]).is_equal(0.0)
	await _done(g)


func test_a_timeout_lands_beside_him_one_at_a_time_and_its_clock_starts_over_once_used() -> void:
	var g := _game()
	var em: EnemyManager = g.enemies
	assert_bool(Run.add_perk("timeout")).is_true()
	var perk: PerkDef = Registry.perk("timeout")
	var first := float(perk.params["first"])
	var every := float(perk.params["every"])
	var side := float(perk.params["side"])
	var pid := str(perk.params["pickup"])
	var here: Vector3 = g.player.global_position
	# he faces north (-Z): his right is east, where a crowd stands, so it lands on his left, west
	g.player.facing = 0.0
	for k in range(3):
		_creature(em, here + Vector3(side + 0.4 * float(k), 0, 0.6))
	assert_bool(g.pickups.special_lying(pid)).is_false()
	_run_for(g, first - 0.5)
	assert_int(_lying(g, pid).size()).is_equal(0)
	_run_for(g, 1.0)
	var lying := _lying(g, pid)
	assert_int(lying.size()).is_equal(1)
	assert_bool(g.pickups.special_lying(pid)).is_true()
	var at: Vector3 = (lying[0] as Node3D).global_position
	assert_float(_flat(at).distance_to(_flat(here))).is_equal_approx(side, 0.05)
	assert_float(at.x - here.x).is_less(-side + 0.05)
	# on the ground
	assert_float(at.y).is_equal_approx(g.map.height_at(at.x, at.z), 0.001)
	# never a second while it lies, however long he leaves it
	_run_for(g, every * 3.0)
	assert_int(_lying(g, pid).size()).is_equal(1)
	# he steps on it: the leap, and the clock starts over from then
	g.player.global_position = Vector3(at.x, g.player.global_position.y, at.z)
	g.pickups._check_specials(g.player, 0.0)
	assert_bool(g.pickups.special_lying(pid)).is_false()
	assert_float(g.player.invuln).is_greater(0.0)
	_run_for(g, every - 0.5)
	assert_int(_lying(g, pid).size()).is_equal(0)
	_run_for(g, 1.0)
	assert_int(_lying(g, pid).size()).is_equal(1)
	await _done(g)


func test_buzzer_beater_adds_its_buff_after_first_and_then_every() -> void:
	var g := _game()
	assert_bool(Run.add_perk("buzzer_beater")).is_true()
	var def: PerkDef = Registry.perk("buzzer_beater")
	assert_str(def.special).is_equal("periodic_buff")
	var first := float(def.params["first"])
	var every := float(def.params["every"])
	var secs := float(def.params["seconds"])
	var buff: Array = def.params["buff"]
	var amount0 := Run.player_sheet.get_stat("amount", 0.0)
	_run_for(g, first - 0.5)
	assert_bool(_buff(def.id).is_empty()).is_true()
	_run_for(g, 1.0)
	var tb := _buff(def.id)
	assert_bool(tb.is_empty()).is_false()
	assert_str(str(tb["label"])).is_equal(def.display_name)
	assert_int((tb["effects"] as Array).size()).is_equal(buff.size())
	assert_bool(bool(tb.get("quiet", false))).is_true()
	assert_float(float(tb["until"]) - Run.buff_clock()).is_between(secs - 1.0, secs + 0.01)
	# the buff is on his sheet under its own source, the pause sheet's "Buzzer Beater", and reaches the ball as bounces
	assert_float(Run.player_sheet.get_stat("amount", 0.0)).is_greater(amount0)
	var ball: WeaponInstance = null
	for w: WeaponInstance in Run.weapons:
		if w.def.id == "basketball":
			ball = w
	assert_object(ball).is_not_null()
	assert_int(ball.stat_int("amount", 0)).is_greater(1)
	# gone once its seconds ran out, back `every` seconds after it came
	_run_for(g, secs + 0.3)
	assert_bool(_buff(def.id).is_empty()).is_true()
	assert_float(Run.player_sheet.get_stat("amount", 0.0)).is_equal_approx(amount0, 0.0001)
	_run_for(g, every - secs - 1.5)
	assert_bool(_buff(def.id).is_empty()).is_true()
	_run_for(g, 1.0)
	assert_bool(_buff(def.id).is_empty()).is_false()
	await _done(g)


## The timed buff `id` running now ({} when none).
func _buff(id: String) -> Dictionary:
	for tb: Dictionary in Run.timed:
		if str(tb["id"]) == id and float(tb["until"]) > Run.buff_clock():
			return tb
	return {}
