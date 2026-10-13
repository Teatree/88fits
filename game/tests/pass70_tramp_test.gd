extends GdUnitTestSuite

## Pass 70, lane TRAMP (Garry: "Time Out - Name it something else and make it about trampolines ... a 3d trampoline
## spawns. Walking up on the trampoline causes the hero jump quite dramatically up in the direction they've been walking.
## Player can control his flight somewhat ... But not nearly as much as just walking"; "the inflatable version of her
## should inflate from a little hockey puck"). Hang Time (perk `hang_time`, special "trampoline", core/systems/
## Trampoline.gd) replaces the Timeout in Fadeaway's kit; Player.trampoline_launch flies him (airborne, untouchable, the
## stick at air_control); May's decoy comes out of a puck (Decoy.gd: FLYING, SLIDING, INFLATING, then FOOLING).

const LAUNCH := "user://debug_launch.json"
const DT := 1.0 / 60.0
const STEP := 0.1


func before_test() -> void:
	Save.data = Save._default()
	Run.arena_next = false
	Settings.camera_mode = 0


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


## A real Game in the debug arena with `hero`, the field emptied: no dummy, no creature.
func _game(hero := "fadeaway") -> Game:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"arena": true, "character": hero, "map": "red_canyon", "map_seed": 5, "analytics": false}))
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


func _done(g: Game) -> void:
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


## `secs` of the run clock in STEP steps through the perks' tick (synchronous: the hero does not move).
func _run_for(g: Game, secs: float) -> void:
	for k in range(int(round(secs / STEP))):
		Run.elapsed += STEP
		g._tick_perks(STEP)


## The trampoline node, made by holding Hang Time.
func _tramp(g: Game) -> Trampoline:
	assert_bool(Run.add_perk("hang_time")).is_true()
	g._tick_trampoline(0.0)
	var tr := g.trampoline as Trampoline
	assert_object(tr).is_not_null()
	return tr


## One standing now, dropped by hand.
func _standing(g: Game, tr: Trampoline) -> void:
	tr.drop_now()
	assert_int(tr.phase).is_equal(Trampoline.DROPPING)
	g._tick_trampoline(Trampoline.DROP_TIME + 0.01)
	assert_int(tr.phase).is_equal(Trampoline.STANDING)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## A way out from `from` with no rock within reach and well inside the wall, so a flight there meets only the sand.
func _clear_dir(g: Game, from: Vector3, reach: float) -> Vector3:
	for k in range(24):
		var a := TAU * float(k) / 24.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var ok := true
		for s in range(1, 15):
			var p := from + d * (reach * float(s) / 14.0)
			if Vector2(p.x, p.z).length() > g.map.arena_radius - 5.0:
				ok = false
				break
			for o: Vector3 in g.map.obstacles:
				if Vector2(p.x - o.x, p.z - o.y).length() < o.z + 1.5:
					ok = false
					break
			if not ok:
				break
		if ok:
			return d
	return Vector3.FORWARD


## The stick held still at `stick` (screen right +X, screen down +Z with the fixed camera), the touch code off.
func _hold_stick(pl: Player, stick: Vector2) -> void:
	pl.input.set_process(false)
	pl.input.wants_move = stick.length() > 0.0
	pl.input.stick_dir = stick


## Lets him settle on the sand, then flies him along `dir` with the stick at `stick` and the perk's numbers; returns
## the take-off, where he came down, the peak over the take-off and the flight's clock.
func _fly(g: Game, dir: Vector3, stick := Vector2.ZERO) -> Dictionary:
	var pl: Player = g.player
	_hold_stick(pl, Vector2.ZERO)
	for k in range(20):
		await get_tree().physics_frame
	var from := pl.global_position
	_hold_stick(pl, stick)
	assert_bool(pl.trampoline_launch(dir, Trampoline.launch_height(), Trampoline.launch_distance(), Trampoline.air_time(), Trampoline.air_control())).is_true()
	assert_bool(pl.airborne).is_true()
	var peak := 0.0
	var frames := 0
	while pl.airborne and frames < 400:
		await get_tree().physics_frame
		frames += 1
		peak = maxf(peak, pl.global_position.y - from.y)
	_hold_stick(pl, Vector2.ZERO)
	return {"from": from, "to": pl.global_position, "peak": peak, "t": pl._air_t, "frames": frames}


## The flight's time when he comes down `dh` metres over (under, negative) the take-off: the arc's own numbers.
func _air_time_for(dh: float) -> float:
	var h := Trampoline.launch_height()
	var tt := Trampoline.air_time()
	var v0 := 4.0 * h / tt
	var gr := 8.0 * h / (tt * tt)
	return (v0 + sqrt(maxf(v0 * v0 - 2.0 * gr * dh, 0.0))) / gr


# ---------------------------------------------------------------- the content

func test_hang_time_is_fadeaways_and_the_timeout_is_retired_but_kept() -> void:
	assert_array(Registry.problems).is_empty()
	var ht: PerkDef = Registry.perk("hang_time")
	assert_object(ht).is_not_null()
	assert_str(ht.hero).is_equal("fadeaway")
	assert_str(ht.special).is_equal("trampoline")
	assert_bool(ht.hidden).is_false()
	assert_object(ht.icon).is_not_null()
	var ids: Array = Registry.perks_of("fadeaway").map(func(p: PerkDef) -> String: return p.id)
	assert_array(ids).contains(["hang_time", "buzzer_beater"])
	assert_array(ids).not_contains(["timeout"])
	# the Timeout perk and pickup stay in their folders, hidden
	assert_bool(Registry.perk("timeout").hidden).is_true()
	assert_bool(Registry.pickup("timeout").hidden).is_true()
	# every number the perk names is one the code reads, and its words say the ones that matter
	for k in ["every", "first", "side", "lifetime", "radius", "uses", "launch_height", "launch_distance", "air_time", "air_control"]:
		assert_bool(ht.params.has(k)).override_failure_message(k).is_true()
	assert_str(ht.text).contains("%d s" % int(ht.params["every"]))
	assert_str(ht.text).contains("%d m" % int(ht.params["launch_distance"]))
	assert_str(ht.text).contains("%d s" % int(ht.params["lifetime"]))
	# the sounds
	for id in ["pk_trampoline_boing", "pk_trampoline_drop", "pk_decoy_hiss"]:
		assert_bool(Registry.soundmap.entries.has(id)).override_failure_message(id).is_true()
	# the model: three parts, the mat with its dip
	assert_bool(ResourceLoader.exists(Trampoline.MODEL_PATH)).is_true()
	var m: Node = auto_free((load(Trampoline.MODEL_PATH) as PackedScene).instantiate())
	var mat := m.find_child("Mat", true, false) as MeshInstance3D
	assert_object(mat).is_not_null()
	assert_object(m.find_child("Rim", true, false)).is_not_null()
	assert_object(m.find_child("Legs", true, false)).is_not_null()
	assert_int(mat.find_blend_shape_by_name("Dip")).is_greater_equal(0)


func test_no_trampoline_node_without_the_perk() -> void:
	var g := _game("drifter")
	_run_for(g, 30.0)
	assert_object(g.trampoline).is_null()
	assert_bool(Trampoline.active()).is_false()
	await _done(g)


# ---------------------------------------------------------------- the clock

func test_a_trampoline_drops_beside_him_on_its_clock_one_at_a_time() -> void:
	var g := _game()
	var em: EnemyManager = g.enemies
	var tr := _tramp(g)
	var here: Vector3 = g.player.global_position
	# he faces north (-Z): his right is east, where a crowd stands, so it lands on his left, west
	g.player.facing = 0.0
	var side := Trampoline.side()
	for k in range(3):
		_creature(em, here + Vector3(side + 0.4 * float(k), 0, 0.6))
	_run_for(g, Trampoline.first() - 0.5)
	assert_int(tr.drops).is_equal(0)
	_run_for(g, 1.0)
	assert_int(tr.drops).is_equal(1)
	assert_int(tr.phase).is_equal(Trampoline.DROPPING)
	assert_float(_flat(tr.at).distance_to(_flat(here))).is_equal_approx(side, 0.05)
	assert_float(tr.at.x - here.x).is_less(-side + 0.05)
	assert_float(tr.at.y).is_equal_approx(g.map.height_at(tr.at.x, tr.at.z), 0.001)
	# it comes down out of the sky, then stands
	assert_float(tr.model.global_position.y).is_greater(tr.at.y + 1.0)
	_run_for(g, Trampoline.DROP_TIME + 0.1)
	assert_int(tr.phase).is_equal(Trampoline.STANDING)
	assert_float(tr.model.global_position.y).is_equal_approx(tr.at.y, 0.01)
	# one at a time: while it stands no other comes, however long; it folds when its lifetime is up
	_run_for(g, Trampoline.lifetime() - tr.age - 0.5)
	assert_int(tr.drops).is_equal(1)
	assert_int(tr.phase).is_equal(Trampoline.STANDING)
	# its last seconds it blinks
	var shown := 0
	for k in range(4):
		_run_for(g, 0.1)
		shown += 1 if tr.model.visible else 0
	assert_int(shown).is_less(4)
	_run_for(g, 0.3)
	assert_int(tr.phase).is_equal(Trampoline.FOLDING)
	_run_for(g, Trampoline.FOLD_TIME + 0.1)
	assert_int(tr.phase).is_equal(Trampoline.IDLE)
	assert_int(tr.folds).is_equal(1)
	assert_bool(tr.model.visible).is_false()
	assert_int(tr.launches).is_equal(0)
	# the next `every` s after it folded away
	assert_float(tr.clock).is_between(Trampoline.every() - 0.35, Trampoline.every())
	_run_for(g, tr.clock - 0.3)
	assert_int(tr.drops).is_equal(1)
	_run_for(g, 0.6)
	assert_int(tr.drops).is_equal(2)
	await _done(g)


func test_a_trampoline_never_lands_on_a_rock_when_the_other_side_is_clear() -> void:
	var g := _game()
	var tr := _tramp(g)
	var here: Vector3 = g.player.global_position
	var em: EnemyManager = g.enemies
	# a rock (an obstacle circle) right where his right-hand spot would be; facing north, right is east
	var saved: Array = em.obstacles.duplicate()
	em.obstacles = saved + [Vector3(here.x + Trampoline.side(), here.z, 1.0)]
	for k in range(6):
		assert_float(tr.pick_spot(here, Vector3(0, 0, -1), Trampoline.side()).x - here.x).is_less(0.0)
	em.obstacles = saved
	await _done(g)


# ---------------------------------------------------------------- the launch

func test_walking_onto_it_launches_him_but_standing_there_when_it_lands_does_not() -> void:
	var g := _game()
	var pl: Player = g.player
	var tr := _tramp(g)
	tr.drop_now()
	# he stands where it comes down
	pl.global_position = Vector3(tr.at.x, pl.global_position.y, tr.at.z)
	g._tick_trampoline(Trampoline.DROP_TIME + 0.01)
	assert_int(tr.phase).is_equal(Trampoline.STANDING)
	for k in range(10):
		g._tick_trampoline(DT)
	assert_int(tr.launches).is_equal(0)
	assert_bool(pl.airborne).is_false()
	# he steps off...
	pl.global_position = Vector3(tr.at.x + 2.5, pl.global_position.y, tr.at.z)
	g._tick_trampoline(DT)
	assert_int(tr.launches).is_equal(0)
	# ...and walks back on, going west: up and away, west
	pl.velocity = Vector3(-5.0, 0.0, 0.0)
	pl.global_position = Vector3(tr.at.x + Trampoline.radius() - 0.05, pl.global_position.y, tr.at.z)
	g._tick_trampoline(DT)
	assert_int(tr.launches).is_equal(1)
	assert_bool(pl.airborne).is_true()
	assert_float(pl.velocity.y).is_greater(5.0)
	assert_bool(pl._air_v.normalized().is_equal_approx(Vector3(-1, 0, 0))).is_true()
	assert_float(pl._air_v.length()).is_equal_approx(Trampoline.launch_distance() / Trampoline.air_time(), 0.001)
	# the mat takes his weight: a full dip at once, then it rebounds past flat (the GLB's "Dip" blend shape follows)
	assert_float(tr.dip).is_greater(0.9)
	var low := 1.0
	for k in range(int(Trampoline.FOLD_AFTER / DT) - 2):
		g._tick_trampoline(DT)
		low = minf(low, tr.dip)
	assert_float(low).is_less(0.0)
	assert_int(tr._dip_idx).is_greater_equal(0)
	assert_float(tr._mat.get_blend_shape_value(tr._dip_idx)).is_equal_approx(clampf(tr.dip, -0.4, 1.0), 0.001)
	# one use: it folds right after, and stays one at a time
	for k in range(int((Trampoline.FOLD_TIME + 0.2) / DT)):
		g._tick_trampoline(DT)
	assert_int(tr.phase).is_equal(Trampoline.IDLE)
	assert_int(tr.folds).is_equal(1)
	assert_float(tr.clock).is_greater(Trampoline.every() - 1.0)
	pl._air_land()
	await _done(g)


func test_standing_still_he_is_thrown_the_way_he_faces() -> void:
	var g := _game()
	var pl: Player = g.player
	var tr := _tramp(g)
	_standing(g, tr)
	pl.global_position = Vector3(tr.at.x, pl.global_position.y, tr.at.z + 3.0)
	g._tick_trampoline(DT)
	# pushed in (no walking speed) facing east
	pl.velocity = Vector3.ZERO
	pl.facing = -PI * 0.5
	pl.global_position = Vector3(tr.at.x, pl.global_position.y, tr.at.z + 0.5)
	g._tick_trampoline(DT)
	assert_int(tr.launches).is_equal(1)
	assert_bool(pl._air_v.normalized().is_equal_approx(Vector3(1, 0, 0))).is_true()
	pl._air_land()
	await _done(g)


func test_the_arc_goes_about_4_m_up_8_m_along_and_lasts_about_1_1_s() -> void:
	var g := _game()
	var pl: Player = g.player
	Run.add_perk("hang_time")
	var dir := _clear_dir(g, pl.global_position, Trampoline.launch_distance() + 3.0)
	var r: Dictionary = await _fly(g, dir)
	var from: Vector3 = r["from"]
	var to: Vector3 = r["to"]
	assert_bool(pl.airborne).is_false()
	assert_int(int(r["frames"])).is_less(400)
	# the top of the arc over the take-off (a frame's step under the analytic top)
	assert_float(float(r["peak"])).is_between(Trampoline.launch_height() - 0.35, Trampoline.launch_height() + 0.05)
	# the time in the air for the ground where he came down, and the distance with it
	var t_want := _air_time_for(to.y - from.y)
	assert_float(float(r["t"])).is_equal_approx(t_want, 0.06)
	var along := _flat(to - from).dot(_flat(dir))
	assert_float(along).is_equal_approx(Trampoline.launch_distance() / Trampoline.air_time() * t_want, 0.5)
	assert_float(absf(_flat(to - from).cross(_flat(dir)))).is_less(0.3)
	# about the numbers the request names (level ground: 4 m, 8 m, 1.1 s)
	assert_float(Trampoline.launch_height()).is_equal(4.0)
	assert_float(Trampoline.launch_distance()).is_equal(8.0)
	assert_float(Trampoline.air_time()).is_equal_approx(1.1, 0.001)
	assert_float(Trampoline.air_control()).is_equal_approx(0.35, 0.001)
	await _done(g)


func test_in_the_air_the_stick_bends_the_arc_but_never_stops_it() -> void:
	var g := _game()
	var pl: Player = g.player
	Run.add_perk("hang_time")
	var dir := _clear_dir(g, pl.global_position, Trampoline.launch_distance() + 6.0)
	var walk := pl.max_speed()
	# full stick square to the flight: he drifts air_control of a walk aside
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var r: Dictionary = await _fly(g, dir, Vector2(perp.x, perp.z))
	var moved: Vector3 = (r["to"] as Vector3) - (r["from"] as Vector3)
	var aside := _flat(moved).dot(_flat(perp))
	var want := Trampoline.air_control() * walk * float(r["t"])
	assert_float(aside).is_equal_approx(want, maxf(want * 0.2, 0.15))
	# a walk for as long would have carried him much farther: the stick in the air is partial
	assert_float(aside).is_less(walk * float(r["t"]) * 0.5)
	assert_float(_flat(moved).dot(_flat(dir))).is_greater(Trampoline.launch_distance() * 0.8)
	# full stick against the flight: slower, still forward
	var back := _clear_dir(g, pl.global_position, Trampoline.launch_distance() + 3.0)
	var r2: Dictionary = await _fly(g, back, Vector2(-back.x, -back.z))
	var fwd := _flat((r2["to"] as Vector3) - (r2["from"] as Vector3)).dot(_flat(back))
	var t2 := float(r2["t"])
	assert_float(fwd).is_greater(0.5)
	assert_float(fwd).is_equal_approx((Trampoline.launch_distance() / Trampoline.air_time() - Trampoline.air_control() * walk) * t2, 0.6)
	await _done(g)


func test_nothing_reaches_him_in_the_air_and_he_lands_with_a_dust_ring() -> void:
	var g := _game()
	var pl: Player = g.player
	var em: EnemyManager = g.enemies
	var tr := _tramp(g)
	_standing(g, tr)
	_hold_stick(pl, Vector2.ZERO)
	pl.global_position = Vector3(tr.at.x + 3.0, pl.global_position.y, tr.at.z)
	g._tick_trampoline(DT)
	pl.velocity = Vector3(-5.0, 0.0, 0.0)
	pl.global_position = Vector3(tr.at.x + 0.9, pl.global_position.y, tr.at.z)
	g._tick_trampoline(DT)
	assert_bool(pl.airborne).is_true()
	await get_tree().physics_frame
	await get_tree().physics_frame
	pl.invuln = 0.0
	var hp0 := pl.hp
	# a hit, a shove, a knock, a hostile blast, a pull: nothing
	pl.take_damage(40.0, pl.global_position + Vector3(1, 0, 0), {"by": "test"})
	assert_float(pl.hp).is_equal(hp0)
	assert_str(pl.last_outcome).is_equal("immune")
	assert_bool(pl.knock_immune()).is_true()
	var kb0: Vector3 = pl._kb
	assert_bool(pl.shove(Vector3(12, 0, 0))).is_false()
	pl.hit_knock(Vector3(8, 0, 0))
	pl.apply_knockback(Vector3(8, 0, 0))
	var vy: float = pl.velocity.y
	pl.blast(Vector3(10, 0, 0), 9.0)
	assert_bool(pl._kb.is_equal_approx(kb0)).is_true()
	assert_float(pl.velocity.y).is_equal(vy)
	# a creature right under him bites the air
	var i := _creature(em, pl.global_position)
	em.contact_cd[i] = 0.0
	em._physics_process(DT)
	assert_float(pl.hp).is_equal(hp0)
	# the flight runs out: he lands, the trampoline's dust ring and shake follow, he can be hit again
	var frames := 0
	while pl.airborne and frames < 300:
		await get_tree().physics_frame
		frames += 1
	assert_bool(pl.airborne).is_false()
	assert_int(tr.landings).is_equal(1)
	assert_int(pl.air_flights).is_equal(1)
	assert_bool(pl.knock_immune()).is_false()
	await _done(g)


func test_a_pause_freezes_the_flight_and_a_fall_ends_it() -> void:
	var g := _game()
	var pl: Player = g.player
	Run.add_perk("hang_time")
	var dir := _clear_dir(g, pl.global_position, Trampoline.launch_distance() + 3.0)
	_hold_stick(pl, Vector2.ZERO)
	for k in range(10):
		await get_tree().physics_frame
	assert_bool(pl.trampoline_launch(dir, 4.0, 8.0, 1.1, 0.35)).is_true()
	# no second launch while he flies
	assert_bool(pl.trampoline_launch(dir, 4.0, 8.0, 1.1, 0.35)).is_false()
	for k in range(15):
		await get_tree().physics_frame
	# the card screen, the pause: the tree stops, he hangs where he is, still in the air
	g.set_paused(true)
	var held: Vector3 = pl.global_position
	var t_held: float = pl._air_t
	for k in range(20):
		await get_tree().process_frame
	assert_bool(pl.global_position.is_equal_approx(held)).is_true()
	assert_float(pl._air_t).is_equal(t_held)
	assert_bool(pl.airborne).is_true()
	g.set_paused(false)
	var frames := 0
	while pl.airborne and frames < 300:
		await get_tree().physics_frame
		frames += 1
	assert_bool(pl.airborne).is_false()
	assert_bool(pl.is_on_floor()).is_true()
	# falling mid-flight (a debug kill: nothing else reaches him up there) ends the flight; up again (the arena stands
	# him straight back up) he is on the ground and can fly again
	for k in range(5):
		await get_tree().physics_frame
	assert_bool(pl.trampoline_launch(dir * -1.0, 4.0, 8.0, 1.1, 0.35)).is_true()
	await get_tree().physics_frame
	pl.hp = 0.0
	pl._die()
	assert_bool(pl.airborne).is_false()
	if pl.dead:
		pl.revive()
	assert_bool(pl.airborne).is_false()
	for k in range(30):
		await get_tree().physics_frame
	assert_bool(pl.trampoline_launch(dir, 4.0, 8.0, 1.1, 0.35)).is_true()
	pl._air_land()
	await _done(g)


func test_the_camera_rides_a_third_of_the_jump() -> void:
	var g := _game()
	var pl: Player = g.player
	assert_float(pl.camera_y()).is_equal(pl.global_position.y)
	pl._air_from_y = pl.global_position.y
	pl.airborne = true
	pl.global_position.y += 4.0
	assert_float(pl.camera_y()).is_equal_approx(pl._air_from_y + 4.0 * Player.AIR_CAMERA, 0.0001)
	pl.airborne = false
	pl.global_position.y -= 4.0
	await _done(g)


func test_the_arena_swap_folds_it_with_the_perk() -> void:
	var g := _game()
	var tr := _tramp(g)
	_standing(g, tr)
	assert_bool(g.arena_swap_hero("drifter")).is_true()
	g._tick_trampoline(DT)
	assert_int(tr.phase).is_equal(Trampoline.FOLDING)
	for k in range(int((Trampoline.FOLD_TIME + 0.1) / DT)):
		g._tick_trampoline(DT)
	assert_int(tr.phase).is_equal(Trampoline.IDLE)
	_run_for(g, 40.0)
	assert_int(tr.drops).is_equal(1)
	await _done(g)


# ---------------------------------------------------------------- May's puck

func test_the_doll_inflates_out_of_a_puck_before_the_fooling_starts() -> void:
	var g := _game("may")
	var em: EnemyManager = g.enemies
	assert_bool(Run.add_perk("inflatable_may")).is_true()
	g._tick_decoy(0.0)
	var dc: Decoy = g.decoy
	dc.throw_now()
	assert_int(dc.phase).is_equal(Decoy.FLYING)
	# what flies is a small black puck, not the doll
	assert_object(dc.puck).is_not_null()
	assert_bool(dc.puck.visible).is_true()
	assert_bool(dc.doll == null or not dc.doll.visible).is_true()
	var cyl := dc.puck.mesh as CylinderMesh
	assert_float(cyl.top_radius * 2.0).is_equal_approx(0.25, 0.001)
	assert_float((dc.puck.material_override as StandardMaterial3D).albedo_color.v).is_less(0.1)
	# it comes down short of the doll's spot, on the line from her
	var here: Vector3 = g.player.global_position
	assert_float(_flat(dc.land_at).distance_to(_flat(dc.to))).is_equal_approx(Decoy.SLIDE, 0.01)
	assert_float(_flat(dc.land_at).distance_to(_flat(here))).is_less(_flat(dc.to).distance_to(_flat(here)))
	var inside := _creature(em, dc.to + Vector3(2.0, 0, 0))
	g._tick_decoy(Decoy.param("flight", 0.6) + 0.01)
	assert_int(dc.phase).is_equal(Decoy.SLIDING)
	assert_float(_flat(dc.puck.global_position).distance_to(_flat(dc.land_at))).is_less(0.01)
	# it slides to the spot; nobody is fooled yet
	g._tick_decoy(Decoy.SLIDE_TIME * 0.5)
	assert_int(dc.phase).is_equal(Decoy.SLIDING)
	var mid := _flat(dc.puck.global_position)
	assert_float(mid.distance_to(_flat(dc.to))).is_less(Decoy.SLIDE - 0.05)
	assert_float(mid.distance_to(_flat(dc.to))).is_greater(0.01)
	assert_bool(em.decoy_on).is_false()
	g._tick_decoy(Decoy.SLIDE_TIME * 0.5 + 0.01)
	assert_int(dc.phase).is_equal(Decoy.INFLATING)
	assert_float(_flat(dc.puck.global_position).distance_to(_flat(dc.to))).is_less(0.01)
	# the doll blows up out of it: from nothing past full size and back, still nobody fooled
	assert_bool(dc.doll.visible).is_true()
	g._tick_decoy(Decoy.INFLATE_TIME * 0.5)
	assert_int(dc.phase).is_equal(Decoy.INFLATING)
	assert_bool(em.decoy_on).is_false()
	assert_bool(em.is_fooled(inside)).is_false()
	g._tick_decoy(Decoy.INFLATE_TIME * 0.5 + 0.01)
	# full size: the circle and the fooling start, the puck is under her feet no more
	assert_int(dc.phase).is_equal(Decoy.FOOLING)
	assert_int(dc.inflations).is_equal(1)
	assert_bool(em.decoy_on).is_true()
	assert_bool(em.is_fooled(inside)).is_true()
	assert_bool(dc.puck.visible).is_false()
	await _done(g)


func test_the_inflation_curve_overshoots_and_settles() -> void:
	assert_float(Decoy.inflate_scale(0.0)).is_equal(0.0)
	assert_float(Decoy.inflate_scale(Decoy.INFLATE_PEAK_AT)).is_equal_approx(Decoy.INFLATE_PEAK, 0.0001)
	assert_float(Decoy.inflate_scale(1.0)).is_equal_approx(1.0, 0.0001)
	var top := 0.0
	var last := -1.0
	for k in range(101):
		var s := Decoy.inflate_scale(float(k) / 100.0)
		top = maxf(top, s)
		if float(k) / 100.0 <= Decoy.INFLATE_PEAK_AT:
			assert_float(s).is_greater_equal(last)
		last = s
	assert_float(top).is_equal_approx(Decoy.INFLATE_PEAK, 0.0001)
	assert_float(Decoy.INFLATE_TIME).is_equal_approx(0.3, 0.0001)
