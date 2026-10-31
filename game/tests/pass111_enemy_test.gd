extends GdUnitTestSuite

## Pass 111, lane ENEMY: four creature changes Garry asked for.
## 1. The Cyclopean Mummy faces as its sheet is painted: a look with its own left-heading sets (idle_l, run_l, attack_l,
##    hit_l, run_bl, idle_bl, appended to the strip by tools/add_left_sets.py) shows them while it heads screen-left and
##    its usual sets while it heads right, never mirrored (EnemyManager._lr_strip, _face_bit); every other creature mirrors
##    as before.
## 2. The Spit Cactus throws a big black bomb (ranged.shot "bomb", ranged.bomb) on a higher arc in the same time to the
##    same spot (ProjectileManager.throw_gravity), with a smoke trail off its fuse.
## 3. Far from the hero a regular creature (and a boss) walks faster (timeline_data.far_speed; EnemyManager far speed);
##    never an Elite, a special type, a coloured special; off when disabled.
## 4. The harpooner's chain and hook (HarpoonChain): a fat chain of links, the rear-back wind-up, the hook-in and the reel.

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
func telegraph_ring(at: Vector3, r: float, dur: float, _col: Color, _filled := true) -> void:
	rings.append({"at": at, "r": r, "dur": dur})
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
"""

const FAKE_CAMERA := """extends Node
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "cam": cam}


func _put(em: EnemyManager, id: String, at: Vector3, variant := "") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0, variant)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.intent[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em.flash[i] = 0.0
	em.anim_t[i] = 0.0
	em.away[i] = 0
	em.vspecial[i] = 0
	em.elite_idx[i] = -1
	return i


func _range_of(em: EnemyManager, t: int, strip: int) -> Vector2i:
	return em.strip_frames(t, strip)


func _in(fr: int, r: Vector2i) -> bool:
	return fr >= r.x and fr < r.x + r.y


# ---------------------------------------------------------------- 1. the mummy's left sets

func test_every_mummy_look_carries_its_left_sets_after_its_old_frames() -> void:
	var def: EnemyDef = Registry.enemy("cyclopean_mummy")
	for code in ["CM-A", "CM-B", "CM-C", "CM-D", "CM-E", "CM-F", "CM-G"]:
		var v: EnemyDef = def.variant_def(code)
		assert_bool(v.has_left_sets()).override_failure_message(code).is_true()
		for k in ["idle_l", "run_l", "attack_l", "hit_l", "run_bl", "idle_bl"]:
			assert_int(v.frames_of(k)).override_failure_message("%s %s" % [code, k]).is_equal(v.frames_of(k.replace("_bl", "_b").replace("_l", "")))
		# the old frames stay where they were; the left sets come after the last of them
		assert_int(v.frame_offset("idle_b")).is_equal(36)
		assert_int(v.frame_offset("idle_l")).is_equal(40)
		assert_int(v.frame_offset("run_l")).is_equal(44)
		assert_int(v.frame_offset("run_bl")).is_equal(59)
		assert_int(v.total_frames()).is_equal(75)
	# (pass 116 re-pin: Garry removed the CM-0 placeholder strip)
	# any other creature has none
	assert_bool(Registry.enemy("skeleton").has_left_sets()).is_false()


func test_the_left_sets_are_unmirrored_copies_on_the_sheet() -> void:
	var v: EnemyDef = Registry.enemy("cyclopean_mummy").variant_def("CM-F")
	var tex: Texture2D = LookArt.tex(v.strip_path())
	assert_object(tex).is_not_null()
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var cell := v.frame_px
	var cols := v.strip_cols
	assert_int(img.get_width()).is_equal(cols * cell)
	assert_int(img.get_height()).is_equal(2 * cell)
	var cut := func(k: int) -> Image:
		return img.get_region(Rect2i((k % cols) * cell, (k / cols) * cell, cell, cell))
	for pair in [["run", "run_l"], ["idle", "idle_l"], ["run_b", "run_bl"], ["attack", "attack_l"]]:
		var a: Image = cut.call(v.frame_offset(pair[0]))
		var b: Image = cut.call(v.frame_offset(pair[1]))
		# the same picture (the import may have compressed both alike), never its mirror
		var same := 0
		var mirror := 0
		for y in range(0, cell, 4):
			for x in range(0, cell, 4):
				var pa := a.get_pixel(x, y)
				if pa.a < 0.5:
					continue
				if pa.is_equal_approx(b.get_pixel(x, y)):
					same += 1
				if pa.is_equal_approx(b.get_pixel(cell - 1 - x, y)):
					mirror += 1
		assert_int(same).override_failure_message(str(pair)).is_greater(mirror * 3)


func test_the_mummy_shows_its_left_sets_heading_left_and_is_never_mirrored() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _put(em, "cyclopean_mummy", Vector3(4, 0, 0), "CM-F")
	var t: int = em.type_idx[i]
	assert_int(em._t_lsets[t]).is_equal(1)
	em.vel[i] = Vector3(-1.0, 0, 0)
	# walking: right as painted, left from its own left set, both unmirrored
	for flip in [0, 1]:
		em.flip[i] = flip
		for away in [0, 1]:
			em.away[i] = away
			var d := em.drawn_frame(i)
			var want: int = (EnemyManager.LEFT_OF[5] if flip == 1 else 5) if away == 1 else (EnemyManager.LEFT_OF[0] if flip == 1 else EnemyManager.A_RUN)
			assert_bool(_in(d.x, _range_of(em, t, want))).override_failure_message("flip %d away %d frame %d" % [flip, away, d.x]).is_true()
			assert_int(d.y).is_equal(0)
	# standing: the idle sets the same way
	em.vel[i] = Vector3.ZERO
	em.away[i] = 0
	em.flip[i] = 1
	assert_bool(_in(em.drawn_frame(i).x, _range_of(em, t, EnemyManager.LEFT_OF[EnemyManager.A_IDLE]))).is_true()
	em.flip[i] = 0
	assert_bool(_in(em.drawn_frame(i).x, _range_of(em, t, EnemyManager.A_IDLE))).is_true()
	# a hit: the left hit frame heading left
	em.flash[i] = 0.9
	em.flip[i] = 1
	assert_bool(_in(em.drawn_frame(i).x, _range_of(em, t, EnemyManager.LEFT_OF[EnemyManager.A_HIT]))).is_true()
	assert_int(em.drawn_frame(i).y).is_equal(0)
	em.flash[i] = 0.0
	# dying: one death, as painted both ways
	em.state[i] = EnemyManager.STATE_DYING
	for flip in [0, 1]:
		em.flip[i] = flip
		var d := em.drawn_frame(i)
		assert_bool(_in(d.x, _range_of(em, t, EnemyManager.A_DIE))).is_true()
		assert_int(d.y).is_equal(0)


func test_every_other_creature_still_mirrors_as_before() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var s := _put(em, "skeleton", Vector3(3, 0, 0))
	var t: int = em.type_idx[s]
	assert_int(em._t_lsets[t]).is_equal(0)
	em.vel[s] = Vector3(-1, 0, 0)
	em.flip[s] = 1
	var d := em.drawn_frame(s)
	assert_bool(_in(d.x, _range_of(em, t, EnemyManager.A_RUN))).is_true()
	assert_int(d.y).is_equal(1)
	em.flip[s] = 0
	assert_int(em.drawn_frame(s).y).is_equal(0)
	assert_int(em._lr_strip(s, t, EnemyManager.A_RUN)).is_equal(EnemyManager.A_RUN)
	# (pass 116 re-pin: Garry removed the mummy's CM-0 placeholder strip)
	# the hellhound's inverted front (front_faces "left") is kept: as painted heading left
	var h := _put(em, "hellhound", Vector3(0, 0, 3))
	em.vel[h] = Vector3(-1, 0, 0)
	em.flip[h] = 1
	assert_int(em.drawn_frame(h).y).is_equal(1 if Registry.enemy("hellhound").front_faces == "right" else 0)


# ---------------------------------------------------------------- 2. the bomb

func test_the_cactus_throws_a_big_black_bomb_by_its_own_block() -> void:
	var def: EnemyDef = Registry.enemy("spit_cactus")
	assert_str(str(def.ranged["shot"])).is_equal("bomb")
	assert_bool(EnemyManager.throws_dynamite(def)).is_true()
	var bomb := EnemyManager.throw_block(def)
	assert_str(str(bomb["model"])).contains("enemy_bomb")
	assert_bool(ResourceLoader.exists(str(bomb["model"]))).is_true()
	# it plays the same: speed, fuse, lead, the blast as the dynamite's
	var dy: Dictionary = def.ranged["dynamite"]
	for k in ["speed", "fuse", "out_before", "lead", "lead_max"]:
		assert_float(float(bomb[k])).is_equal(float(dy[k]))
	assert_str(JSON.stringify(bomb["blast"])).is_equal(JSON.stringify(dy["blast"]))
	assert_str(JSON.stringify(bomb["hand"])).is_equal(JSON.stringify(dy["hand"]))
	# bigger: its narrowest side as drawn several times the stick's
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var kb := pm.dynamite_kind(str(bomb["model"]), float(bomb["scale"]), bomb.get("material", {}))
	var ks := pm.dynamite_kind(str(dy["model"]), float(dy["scale"]))
	var sb: Vector3 = pm._kind_box(kb).size * float(pm.kinds[kb]["scale"])
	var ss: Vector3 = pm._kind_box(ks).size * float(pm.kinds[ks]["scale"])
	assert_float(minf(sb.x, minf(sb.y, sb.z))).is_greater(3.0 * minf(ss.x, minf(ss.y, ss.z)))
	assert_float(sb.x).is_greater(0.5)


func test_the_bomb_flies_higher_to_the_same_spot_in_the_same_time() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	w["hero"].global_position = Vector3(40, 0, 40)
	var def: EnemyDef = Registry.enemy("spit_cactus")
	var i := _put(em, "spit_cactus", Vector3(-7, 0, 0))
	var from := Vector3(-7, 1.3, 0)
	var to := Vector3(0, 0, 0)
	var dy: Dictionary = def.ranged["dynamite"]
	var bomb := EnemyManager.throw_block(def)
	var js := pm.hostile_dynamite(from, to, float(dy["speed"]), 8.0, 2.0, dy, em.hit_info(i, "ranged", ["dynamite"]))
	var apex_stick := pm.last_throw_apex
	var ls := pm.landing_of(js)
	var jb := pm.hostile_dynamite(from, to, float(bomb["speed"]), 8.0, 2.0, bomb, em.hit_info(i, "ranged", ["bomb"]))
	var apex_bomb := pm.last_throw_apex
	var lb := pm.landing_of(jb)
	# a clearly higher arc: at least 1.5 m more at the top, about arc_height over the hand
	assert_float(apex_bomb - apex_stick).is_greater(1.5)
	assert_float(apex_bomb - from.y).is_equal_approx(minf(float(bomb["arc_height"]), float(bomb["arc_ratio"]) * 7.0), 0.05)
	# the same spot, the same time in the air (the ring and the fuse play the same)
	assert_float(Vector2(lb.x - ls.x, lb.z - ls.z).length()).is_less(0.35)
	assert_float(absf(lb.w - ls.w)).is_less(0.06)
	# and it really flies there: stepped by the tick, it comes down by the spot
	var s := 0.0
	var top := -INF
	while pm.alive[jb] == 1 and not pm.extra[jb].has("lie_t") and s < 3.0:
		pm._physics_process(DT)
		s += DT
		top = maxf(top, pm.pos[jb].y)
	assert_bool(pm.extra[jb].has("lie_t")).is_true()
	assert_float(Vector2(pm.pos[jb].x, pm.pos[jb].z).length()).is_less(0.6)
	assert_float(top).is_greater(apex_stick + 1.3)


func test_the_gravity_meets_the_apex_and_never_drops_under_the_ticks() -> void:
	for c in [[1.3, 0.0, 0.7, 3.0], [1.3, 0.0, 0.4, 1.2], [0.0, 0.0, 1.0, 2.0], [1.0, 2.0, 0.8, 2.5]]:
		var g := ProjectileManager.throw_gravity(c[0], c[1], c[2], c[3])
		var t: float = c[2]
		var vy: float = ((float(c[1]) - float(c[0])) + 0.5 * g * t * t) / t
		# the asked top exactly, or (when the tick's own gravity already throws it higher) the plain arc, never lower
		if g > 24.0:
			assert_float(vy * vy / (2.0 * g)).override_failure_message(str(c)).is_equal_approx(c[3], 0.01)
		else:
			assert_float(vy * vy / (2.0 * g)).override_failure_message(str(c)).is_greater_equal(float(c[3]) - 0.01)
		assert_float(g).is_greater_equal(24.0)
	# no apex asked: the tick's own
	assert_float(ProjectileManager.throw_gravity(1.3, 0.0, 0.7, 0.0)).is_equal(24.0)
	# a short throw keeps a low arc (arc_ratio of its length)
	assert_float(ProjectileManager.throw_apex({"arc_height": 3.0, "arc_ratio": 0.6}, 2.0)).is_equal_approx(1.2, 0.0001)
	assert_float(ProjectileManager.throw_apex({}, 6.0)).is_equal(0.0)


func test_the_bomb_smokes_and_sparks_along_its_arc() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	w["hero"].global_position = Vector3(40, 0, 40)
	var def: EnemyDef = Registry.enemy("spit_cactus")
	var i := _put(em, "spit_cactus", Vector3(-7, 0, 0))
	var bomb := EnemyManager.throw_block(def)
	var segs0 := pm.tracer_segments
	var j := pm.hostile_dynamite(Vector3(-7, 1.3, 0), Vector3.ZERO, float(bomb["speed"]), 8.0, 2.0, bomb, em.hit_info(i, "ranged", ["bomb"]))
	assert_int(pm.bomb_trails).is_equal(1)
	assert_bool(pm.extra[j].has("bomb_trail")).is_true()
	assert_bool(pm.extra[j].has("tumble_x")).is_true()
	for n in range(20):
		pm._physics_process(DT)
	assert_int(pm.bomb_puffs).is_greater(2)
	assert_int(pm.tracer_segments).is_greater(segs0 + 2)
	# the stick has no trail of its own (the creature's beads as before)
	var js := pm.hostile_dynamite(Vector3(-7, 1.3, 0), Vector3.ZERO, 9.0, 8.0, 2.0, def.ranged["dynamite"], em.hit_info(i, "ranged", ["dynamite"]))
	assert_bool(pm.extra[js].has("bomb_trail")).is_false()


# ---------------------------------------------------------------- 3. far speed

func test_the_map_names_far_speed_and_the_defaults_fill_it() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var own: Dictionary = raw["timeline_data"].get("far_speed", {})
	var cfg := tl.far_speed_cfg()
	for k in WaveTimeline.FAR_SPEED_DEFAULTS:
		var want = own.get(k, WaveTimeline.FAR_SPEED_DEFAULTS[k])
		if want is bool:
			assert_bool(bool(cfg[k])).is_equal(want)
		elif want is String:
			# pass 115 (lane POLISH): the curve's name
			assert_str(str(cfg[k])).is_equal(want)
		else:
			assert_float(float(cfg[k])).is_equal_approx(float(want), 0.0001)
	var empty := WaveTimeline.new()
	assert_bool(bool(empty.far_speed_cfg()["enabled"])).is_true()
	# pass 115 (lane POLISH) re-pinned: x3 (pass 111's x2)
	assert_float(float(empty.far_speed_cfg()["max_mult"])).is_equal(3.0)


func test_the_multiplier_rises_smoothly_past_the_distance() -> void:
	assert_float(EnemyManager.far_speed_mult(5.0, 14.0, 6.0, 2.0)).is_equal(1.0)
	assert_float(EnemyManager.far_speed_mult(14.0, 14.0, 6.0, 2.0)).is_equal(1.0)
	assert_float(EnemyManager.far_speed_mult(17.0, 14.0, 6.0, 2.0)).is_equal_approx(1.5, 0.0001)
	assert_float(EnemyManager.far_speed_mult(20.0, 14.0, 6.0, 2.0)).is_equal_approx(2.0, 0.0001)
	assert_float(EnemyManager.far_speed_mult(60.0, 14.0, 6.0, 2.0)).is_equal_approx(2.0, 0.0001)
	assert_float(EnemyManager.far_speed_mult(14.5, 14.0, 0.0, 3.0)).is_equal(3.0)
	var last := 1.0
	for k in range(60):
		var m := EnemyManager.far_speed_mult(12.0 + 0.2 * float(k), 14.0, 6.0, 2.0)
		assert_float(m).is_greater_equal(last)
		last = m


func test_far_regulars_walk_faster_and_near_ones_do_not() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_far_speed({"enabled": true, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": true})
	var far := _put(em, "skeleton", Vector3(30, 0, 0))
	var near := _put(em, "skeleton", Vector3(0, 0, 6))
	em._rebuild_grid()
	em._steer(far, Vector3.ZERO, DT)
	em._steer(near, Vector3.ZERO, DT)
	assert_float(em.intent[far].length()).is_equal_approx(em.speed[far] * 2.0, 0.01)
	assert_float(em.intent[near].length()).is_equal_approx(em.speed[near], 0.01)
	# off: as it was
	em.set_far_speed({"enabled": false, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": true})
	em._steer(far, Vector3.ZERO, DT)
	assert_float(em.intent[far].length()).is_equal_approx(em.speed[far], 0.01)


func test_never_elites_specials_or_dummies_and_bosses_only_when_asked() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_far_speed({"enabled": true, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": true})
	var reg := _put(em, "skeleton", Vector3(30, 0, 0))
	var elite := _put(em, "stone_golem", Vector3(-30, 0, 0))
	var gear := _put(em, "harpoon_troglodyte", Vector3(0, 0, 30))
	var dummy := _put(em, "training_dummy", Vector3(0, 0, -30))
	var boss := em.spawn_boss("tumbleweed_king", Vector3(30, 0, 30))
	assert_int(boss).is_greater_equal(0)
	assert_float(em.far_speed_k(reg, 30.0)).is_equal_approx(2.0, 0.0001)
	assert_float(em.far_speed_k(elite, 30.0)).is_equal(1.0)
	assert_float(em.far_speed_k(gear, 30.0)).is_equal(1.0)
	assert_float(em.far_speed_k(dummy, 30.0)).is_equal(1.0)
	assert_float(em.far_speed_k(boss, 30.0)).is_equal_approx(2.0, 0.0001)
	# a regular wearing an Elite modifier, or rolled as a coloured special
	em.elite_idx[reg] = 0
	assert_float(em.far_speed_k(reg, 30.0)).is_equal(1.0)
	em.elite_idx[reg] = -1
	em.vspecial[reg] = 1
	assert_float(em.far_speed_k(reg, 30.0)).is_equal(1.0)
	em.vspecial[reg] = 0
	# bosses off
	em.set_far_speed({"enabled": true, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": false})
	assert_float(em.far_speed_k(boss, 30.0)).is_equal(1.0)
	assert_float(em.far_speed_k(reg, 30.0)).is_equal_approx(2.0, 0.0001)


func test_a_charge_keeps_its_own_speed_far_away() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_far_speed({"enabled": true, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": true})
	var b := _put(em, "bull_beetle", Vector3(30, 0, 0))
	var def: EnemyDef = Registry.enemy("bull_beetle")
	em.state[b] = EnemyManager.STATE_CHARGE
	em.timer[b] = 0.5
	em.charge_dir[b] = Vector3(-1, 0, 0)
	em._rebuild_grid()
	em._steer(b, Vector3.ZERO, DT)
	assert_float(em.intent[b].length()).is_equal_approx(float(def.charge.get("speed", 9.0)) * em.pace, 0.01)


# ---------------------------------------------------------------- 4. the harpoon

func test_the_harpooner_has_its_chain_and_hook_block() -> void:
	var def: EnemyDef = Registry.enemy("harpoon_troglodyte")
	var fx: Dictionary = def.ranged.get("harpoon_fx", {})
	assert_bool(fx.is_empty()).is_false()
	var m := HarpoonChain.merged(fx)
	for k in HarpoonChain.DEFAULTS:
		assert_bool(m.has(k)).is_true()
	assert_bool(ResourceLoader.exists(HarpoonChain.HOOK_MODEL)).is_true()
	assert_object(HarpoonChain.hook_mesh()).is_not_instanceof(BoxMesh)
	# the gameplay numbers are Garry's as they were
	assert_float(float(def.ranged["telegraph"])).is_equal(0.8)
	assert_float(float(def.ranged["projectile_speed"])).is_equal(20.0)
	assert_float(float(def.ranged["tether"]["seconds"])).is_equal(5.0)
	# a rear-back lean for it, none for a creature without the block
	assert_float(EnemyManager.rear_numbers(def)[0]).is_greater(0.1)
	assert_float(EnemyManager.rear_numbers(Registry.enemy("skeleton"))[0]).is_equal(0.0)


func test_it_rears_back_away_from_its_aim_through_the_windup() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _put(em, "harpoon_troglodyte", Vector3(0, 0, 0))
	var scr := Vector3(-em._cf_tick.z, 0, em._cf_tick.x)
	em.state[i] = EnemyManager.STATE_WINDUP
	var total: float = em._t_rear[em.type_idx[i] * 2 + 1] / em.pace
	em.timer[i] = total * 0.05
	em.charge_dir[i] = scr
	assert_float(em.charge_pose(i, scr).w).is_greater(0.1)
	em.charge_dir[i] = -scr
	assert_float(em.charge_pose(i, scr).w).is_less(-0.1)
	# just started: hardly any lean yet; crouched a little at the end
	em.timer[i] = total
	assert_float(absf(em.charge_pose(i, scr).w)).is_less(0.01)
	em.timer[i] = 0.0
	assert_float(em.charge_pose(i, scr).z).is_less(1.0)


func test_the_chain_is_a_row_of_links_from_the_hand_to_the_hook() -> void:
	var w := _world()
	var ch := HarpoonChain.new()
	w["pm"].add_child(ch)
	ch.setup(w["g"])
	ch.configure(Registry.enemy("harpoon_troglodyte").ranged["harpoon_fx"])
	ch.draw(Vector3(0, 1.4, 0), Vector3(10, 1.2, 0), 0.03, HarpoonChain.FLY)
	var c: Dictionary = ch.cfg["chain"]
	var pitch: float = float(c["link"]) * (1.0 - float(c["overlap"]))
	assert_int(ch.links_drawn).is_equal(int(10.0 / pitch))
	ch.draw(Vector3.ZERO, Vector3(200, 0, 0), 0.03, HarpoonChain.TAUT)
	assert_int(ch.links_drawn).is_equal(HarpoonChain.MAX_LINKS)
	ch.release()
	assert_int(ch.links_drawn).is_equal(0)


func test_a_hook_in_kicks_the_camera_and_a_miss_reels_the_hook_home() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ch := HarpoonChain.new()
	w["pm"].add_child(ch)
	ch.setup(w["g"])
	var i := _put(em, "harpoon_troglodyte", Vector3(0, 0, 0))
	ch.configure_from(i)
	ch.hooked(Vector3(8, 0.85, 0), ch.hand_of(i, Vector3(8, 0, 0)))
	assert_int(ch.hooks).is_equal(1)
	assert_int(w["cam"].shakes).is_equal(1)
	ch.missed(Vector3(12, 1.2, 0), i)
	assert_bool(ch.reeling()).is_true()
	var reel := float(ch.cfg["miss"]["reel"])
	var s := 0.0
	var drew := false
	while ch.reeling() and s < 3.0:
		ch._process(DT)
		s += DT
		drew = drew or ch.links_drawn > 0
	assert_bool(drew).is_true()
	assert_bool(ch.reeling()).is_false()
	assert_float(s).is_equal_approx(reel, 0.05)
	assert_int(ch.links_drawn).is_equal(0)
