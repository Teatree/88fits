extends GdUnitTestSuite

## Pass 122, lane BUGS: two bugs Garry reported on 2026-11-03.
## 1. "It shows the Grindstone icon instead of Phoenix": the fall (Game._on_player_died) took the first held item
##    Run.item_spent said was spent as the feather, and a used Grindstone (pass 121, grind_used) is spent too. Now
##    Run.phoenix_item() is the held item that carries the free revive (Run.carries_phoenix: `phoenix_revive` at level 1),
##    else the Registry's Phoenix Feather; the fall's flying plate and its banner show that one.
## 2. "There doesn't seem to be an exploding effect to the Exploding enemies": Game.elite_explosion drew Fx.burst's pale
##    see-through ball (nothing on Stage 3's red ground). Now the boom is a real blast (Fx.blast in Fx.BLAST_ELITE, its
##    power growing with the radius: Game.elite_blast_power) with a scorch, under a warning ring and a flash ring in
##    Game.ELITE_WARN (hot orange; UiKit.DANGER's red was red on red); the shake and the sound are kept; the sim draws
##    nothing. The path from an Explosive Elite's death reaches it whatever killed it, where the body fell.

const STONE := "grindstone"
const FEATHER := "phoenix_feather"
const RUN_LAUNCH := {"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics": false}
const ARENA_LAUNCH := {"arena": true, "weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "analytics": false}


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	CardPool.rng = null


func after_test() -> void:
	# the arena's games sandbox the save (Game._start_arena); the suites after this one write the real one
	if Save.sandboxed():
		Save.end_sandbox()
	Save._dirty = false
	get_tree().paused = false
	CardPool.rng = null
	Run.sim_mode = false
	Run.arena = false
	Run.end()


func _start(hero: String = "drifter") -> void:
	var c: CharacterDef = Registry.character(hero)
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)


## The Grindstone taken into the run: it works on the hero's weapon at once and reads spent from then on.
func _hold_used_stone() -> void:
	assert_bool(Run.add_or_level_passive(STONE)).is_true()
	assert_bool(Run.grind_used.is_empty()).is_false()
	assert_bool(Run.item_spent(Registry.passive(STONE))).is_true()


# ---------------------------------------------------------------- 1. the feather, not the stone

func test_the_phoenix_item_is_the_feather_not_a_used_grindstone() -> void:
	_start()
	_hold_used_stone()
	Run.add_or_level_passive(FEATHER)
	# the stone was held first: the old loop over Run.passives took it, the first spent item, as the feather
	var keys: Array = Run.passives.keys()
	assert_int(keys.find(STONE)).is_greater_equal(0)
	assert_int(keys.find(STONE)).is_less(keys.find(FEATHER))
	var ph: PassiveDef = Registry.passive(FEATHER)
	assert_object(Run.phoenix_item()).is_same(ph)
	# spent or not, the feather is the feather, and the stone stays spent in its own right
	Run.use_phoenix()
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.item_spent(ph)).is_true()
	assert_object(Run.phoenix_item()).is_same(ph)
	assert_bool(Run.item_spent(Registry.passive(STONE))).is_true()


func test_without_a_feather_held_the_registry_s_feather_stands_in() -> void:
	_start()
	_hold_used_stone()
	var ph: PassiveDef = Registry.passive(FEATHER)
	assert_object(Run.phoenix_item()).is_same(ph)
	assert_object(Run.phoenix_item()).is_not_same(Registry.passive(STONE))
	# the shape: the free revive at level 1, and nothing else carries it
	assert_bool(Run.carries_phoenix(ph)).is_true()
	assert_bool(Run.carries_phoenix(Registry.passive(STONE))).is_false()
	assert_bool(Run.carries_phoenix(Registry.passive("magnet"))).is_false()
	assert_bool(Run.carries_phoenix(Registry.weapon("revolver"))).is_false()
	assert_bool(Run.carries_phoenix(null)).is_false()
	for p: PassiveDef in Registry.passives.values():
		assert_bool(Run.carries_phoenix(p)).override_failure_message(p.id).is_equal(p.id == FEATHER)
	# item_spent's own reading is unchanged: the stone spent, a feather not held (nothing spent) not
	assert_bool(Run.item_spent(ph)).is_false()


func _game(launch: Dictionary) -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(launch))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	return g


func _until(cond: Callable, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if cond.call():
			return true
		await get_tree().create_timer(0.05, true).timeout
		waited += 0.05
	return bool(cond.call())


func test_the_fall_flies_the_feather_s_plate_and_names_it_on_the_banner() -> void:
	var g := await _game(RUN_LAUNCH)
	g.enemies.kill_all(false)
	g.player.god = true
	# the stone taken in a live game plays its show (pass 121), which stops the clock: skipped, and the gate tapped
	_hold_used_stone()
	await _until(func() -> bool: return g.grind_moment != null and bool(g.grind_moment.playing), 2.0)
	if g.grind_moment != null and bool(g.grind_moment.playing):
		g.grind_moment.skip()
	await _until(func() -> bool: return g.resume_gate.visible, 2.0)
	if g.resume_gate.visible:
		g.resume_gate.tap()
	await get_tree().process_frame
	assert_bool(g.paused).is_false()
	assert_bool(get_tree().paused).is_false()
	Run.add_or_level_passive(FEATHER)
	assert_bool(Run.phoenix_ready()).is_true()
	var ph: PassiveDef = Registry.passive(FEATHER)
	var stone: PassiveDef = Registry.passive(STONE)
	assert_object(ph.icon).is_not_same(stone.icon)
	g.player.god = false
	g.player._die()
	await get_tree().process_frame
	# the banner names the feather and wears its icon
	assert_str(g.hud.banner_text()).is_equal("PHOENIX FEATHER")
	assert_object(g.hud._banner._icon.texture).is_same(ph.icon)
	# the plate flying off him is the feather's
	var fly: Node = g.hud.get_node_or_null("FlyItem")
	assert_object(fly).is_not_null()
	var plate: WPlate = fly.get_node("Plate")
	assert_object(plate.tex).is_same(ph.icon)
	assert_object(plate.tex).is_not_same(stone.icon)
	# he gets up by the feather; the stone is left as it was, spent
	await get_tree().create_timer(Game.PHOENIX_DELAY + 0.4).timeout
	assert_bool(g.player.dead).is_false()
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.item_spent(stone)).is_true()


# ---------------------------------------------------------------- 2. the boom

## The debug arena, emptied, the hero safe and his gun silent (the kills below are the test's own, on their frame).
func _arena() -> Game:
	var g := await _game(ARENA_LAUNCH)
	g.no_random_chests = true
	g.player.god = true
	g.enemies.kill_all(false)
	g.enemies.spawn_rise_s = 0.0
	g.enemies.spawn_rise_big_s = 0.0
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	return g


func _ground(g: Game, off: Vector3) -> Vector3:
	var at: Vector3 = g.player.global_position + off
	at.y = g.map.height_at(at.x, at.z)
	return at


func test_the_boom_is_a_real_blast_in_the_hostile_colour_with_a_scorch() -> void:
	var g := await _arena()
	var fx: Fx = g.fx
	var at := _ground(g, Vector3(0, 0, -5))
	var n0: int = fx.blasts
	var marks0: int = g.telegraphs.live_count()
	g.elite_explosion(at, 3.0, 0.0, 0.0)
	assert_int(fx.blasts).is_equal(n0 + 1)
	var lb: Dictionary = fx.last_blast
	assert_bool((lb["col"] as Color).is_equal_approx(Fx.BLAST_ELITE)).is_true()
	assert_bool(Fx.BLAST_ELITE.is_equal_approx(Fx.BLAST_ORANGE)).is_false()
	assert_int(int(lb["style"])).is_equal(Fx.BLAST_FULL)
	assert_float(float(lb["power"])).is_equal_approx(Game.elite_blast_power(3.0), 0.0001)
	assert_float(float(lb["power"])).is_equal_approx(1.5, 0.0001)
	assert_float(float(lb["r"])).is_equal_approx(3.0, 0.0001)
	assert_float((lb["at"] as Vector3).x).is_equal_approx(at.x, 0.001)
	assert_float((lb["at"] as Vector3).z).is_equal_approx(at.z, 0.001)
	# on the ground: the flash ring and the scorch
	assert_int(g.telegraphs.live_count()).is_equal(marks0 + 2)
	# the power grows with the radius, from 1 (a plain blast) to 2 (the Heavy Warhead's)
	assert_float(Game.elite_blast_power(1.8)).is_equal_approx(1.0, 0.0001)
	assert_float(Game.elite_blast_power(2.4)).is_equal_approx(1.2, 0.0001)
	assert_float(Game.elite_blast_power(4.0)).is_equal_approx(2.0, 0.0001)
	assert_float(Game.elite_blast_power(9.0)).is_equal_approx(2.0, 0.0001)


func test_a_delayed_boom_warns_in_hot_orange_then_blasts_and_the_sim_draws_none() -> void:
	var g := await _arena()
	var at := _ground(g, Vector3(0, 0, -5))
	var n0: int = g.fx.blasts
	var marks0: int = g.telegraphs.live_count()
	g.elite_explosion(at, 3.0, 0.0, 0.4)
	# the warning first: a band and its faint disc in ELITE_WARN, for the delay; no blast yet
	assert_int(g.fx.blasts).is_equal(n0)
	var items: Array = g.telegraphs._items
	assert_int(items.size()).is_greater_equal(marks0 + 2)
	for it: Dictionary in items.slice(items.size() - 2):
		var c: Color = it["col"]
		assert_bool(Color(c.r, c.g, c.b).is_equal_approx(Game.ELITE_WARN)).is_true()
		assert_float(float(it["dur"])).is_equal_approx(0.4, 0.0001)
		assert_float(float(it["r"])).is_equal_approx(3.0, 0.0001)
	var warn := Color(Game.ELITE_WARN.r, Game.ELITE_WARN.g, Game.ELITE_WARN.b)
	assert_bool(warn.is_equal_approx(Color(UiKit.DANGER.r, UiKit.DANGER.g, UiKit.DANGER.b))).is_false()
	await get_tree().create_timer(0.7).timeout
	assert_int(g.fx.blasts).is_equal(n0 + 1)
	assert_bool((g.fx.last_blast["col"] as Color).is_equal_approx(Fx.BLAST_ELITE)).is_true()
	# the run sim: the ring and the damage as ever, no blast drawn
	Run.sim_mode = true
	g.elite_explosion(at, 3.0, 0.0, 0.0)
	assert_int(g.fx.blasts).is_equal(n0 + 1)
	Run.sim_mode = false


## An Explosive Elite 6 m up the screen, standing (no rise, no walk); its index.
func _explosive(g: Game) -> int:
	var em: EnemyManager = g.enemies
	var mod: EliteModDef = Registry.elites.get("explosive")
	assert_object(mod).is_not_null()
	assert_str(mod.on_death).is_equal("explode")
	var i: int = em.spawn("skeleton", _ground(g, Vector3(0, 0, -6)), mod)
	assert_int(i).is_greater_equal(0)
	# it wears the modifier (the death reads it off elite_idx), and the despawn rule never takes it
	assert_int(em.elite_idx[i]).is_greater_equal(0)
	assert_object(em.elites[em.elite_idx[i]]).is_same(mod)
	assert_bool(em.despawn_kind(i)).is_false()
	if em.state[i] == EnemyManager.STATE_SPAWN:
		em.state[i] = EnemyManager.STATE_MOVE
		em.timer[i] = 0.0
	em.speed[i] = 0.0
	em._rebuild_grid()
	return i


## The kill `how` deals: the warning ring at once where it fell, the blast after the modifier's telegraph, on that spot.
func _boom_follows(g: Game, i: int, how: Callable) -> void:
	var em: EnemyManager = g.enemies
	var mod: EliteModDef = Registry.elites["explosive"]
	var n0: int = g.fx.blasts
	var marks0: int = g.telegraphs.live_count()
	var where: Vector3 = em.pos[i]
	var serial: int = em.serial[i]
	how.call()
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_bool(em.despawn_kind(i)).is_false()
	assert_int(g.telegraphs.live_count()).is_greater_equal(marks0 + 2)
	assert_int(g.fx.blasts).is_equal(n0)
	var delay: float = float(mod.params.get("telegraph", 0.5)) / maxf(float(em.pace), 0.01)
	await get_tree().create_timer(delay + 0.3).timeout
	assert_int(g.fx.blasts).is_equal(n0 + 1)
	var lb: Dictionary = g.fx.last_blast
	assert_bool((lb["col"] as Color).is_equal_approx(Fx.BLAST_ELITE)).is_true()
	assert_float(float(lb["r"])).is_equal_approx(float(mod.params.get("explode_radius", 3.0)), 0.001)
	var b: Vector3 = lb["at"]
	assert_float(Vector2(b.x - where.x, b.z - where.z).length()).is_less(0.01)
	# the body's follow-through (pass 82) slid it along the hit, still inside the blast (the warning ring's radius)
	if em.alive[i] == 1 and em.serial[i] == serial:
		var drift := Vector2(em.pos[i].x - where.x, em.pos[i].z - where.z).length()
		assert_float(drift).override_failure_message("the body slid %.2f m from its ring" % drift).is_less(float(lb["r"]))


func test_an_explosive_elite_killed_by_a_weapon_reaches_the_boom() -> void:
	var g := await _arena()
	var i := _explosive(g)
	await _boom_follows(g, i, func() -> void:
		assert_bool(g.enemies.damage(i, 1.0e9, "revolver", Vector3(0, 0, -1), 4.0)).is_true())


func test_an_explosive_elite_killed_by_a_blast_reaches_the_boom() -> void:
	var g := await _arena()
	var i := _explosive(g)
	var at: Vector3 = g.enemies.pos[i]
	await _boom_follows(g, i, func() -> void:
		g.enemies.damage_radius(at + Vector3(1.0, 0, 0), 2.5, 1.0e9, "lob_grenade", 12.0, EnemyManager.HIT_BLAST))


func test_an_explosive_elite_killed_by_kill_all_reaches_the_boom() -> void:
	var g := await _arena()
	var i := _explosive(g)
	await _boom_follows(g, i, func() -> void:
		g.enemies.kill_all(true))
