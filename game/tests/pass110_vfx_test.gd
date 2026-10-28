extends GdUnitTestSuite

## Pass 110, lane VFX (Garry's requests of 2026-10-28):
##  A. "Explosions - at some point became quite invisible ... for all the explosive weapons": every blast of the hero's
##     weapons is drawn by Fx's own blast pool (Fx.blast / weapon_blast: a flash, a fireball, smoke, sparks and clods, a
##     shock ring at the real radius, a scorch, a kick only for a big one); nothing in the shared effect pool can crowd it
##     out, and the shared pool keeps a reserve for its `must` effects.
##  B. "when Player hero is facing up, or up-left or up-right the Fire Breath visual renders behind the hero": the
##     breath's particles draw before his second pass in his back views (BreathFlames.set_behind, Player.faces_away).
##  C. "Move the Kill Counter so it's vertically centered to the vertical center of the Item drawer" (HUD._place_kills).

const DT := 1.0 / 60.0
const BREATH_TEST := preload("res://tests/pass95_BREATH_test.gd")

const FAKE_GAME := """extends Node
var map = null
var telegraphs = null
var camera = null
"""

const FAKE_CAMERA := """extends Node
var shakes: Array = []
func shake(a: float) -> void:
	shakes.append(a)
"""

## The breath's fake hero with the back-view question (pass 110): `away` is what Player.faces_away answers.
const FAKE_HERO_AWAY := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var still_unhit := 0.0
var away := false
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0)
func face_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1.45, 0) + d.normalized() * 0.3
func still_unhit_seconds() -> float:
	return still_unhit
func faces_away() -> bool:
	return away
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func after_test() -> void:
	Run.sim_mode = false
	Run.kills = 0
	Run.end()


func _fx() -> Fx:
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	return fx


func _inst(id: String, level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


# ---------------------------------------------------------------- A. the blast

func test_a_full_blast_has_every_piece_and_leaves_the_shared_pool_alone() -> void:
	var fx := _fx()
	var n0 := fx._n
	assert_int(fx.blast(Vector3.ZERO, 2.8)).is_equal(Fx.BLAST_DONE)
	assert_int(fx._n).is_equal(n0)
	assert_int(fx.blast_kind_count(0)).is_equal(1)
	# the ball and its three lumps
	assert_int(fx.blast_kind_count(1)).is_equal(4)
	assert_int(fx.blast_kind_count(2)).is_greater_equal(4)
	assert_int(fx.blast_kind_count(3)).is_greater_equal(10)
	assert_int(fx.blast_kind_count(4)).is_greater_equal(5)
	# the fireball shows about 0.62 of the radius round (its lumpy edge at 0.88 of a 1.4 r wide quad); the ring marks it all
	assert_float(float(fx.last_blast["ball"])).is_equal_approx(2.8 * Fx.BLAST_BALL, 0.001)
	assert_float(Fx.BLAST_BALL * 0.5 * 0.88).is_between(0.55, 0.7)
	# gone within a second and a half: the smoke is the last of it
	for k in range(100):
		fx._process(DT)
	assert_int(fx.blast_count()).is_equal(0)


func test_a_blast_shows_when_the_effect_pool_is_full() -> void:
	var fx := _fx()
	# a late-game crowd holds the shared pool at its cap (perf_late: 394 of 400): the old burst was dropped there
	fx._n = Fx.MAX_P
	var before := fx.blast_count()
	assert_int(fx.blast(Vector3(3, 0, 3), 2.8)).is_equal(Fx.BLAST_DONE)
	assert_int(fx.blast_count() - before).is_greater_equal(25)
	fx._n = 0


func test_must_effects_have_a_reserve_past_the_cap() -> void:
	var fx := _fx()
	fx._n = Fx.MAX_P
	fx._emit(Vector3.ZERO, Vector3.ZERO, 0.3, 0.1, 0.2, 1.0, 0.0, Color.WHITE)
	assert_int(fx._n).is_equal(Fx.MAX_P)
	fx._emit(Vector3.ZERO, Vector3.ZERO, 0.3, 0.1, 0.2, 1.0, 0.0, Color.WHITE, 0.0, false, true)
	assert_int(fx._n).is_equal(Fx.MAX_P + 1)
	fx._n = Fx.POOL_MAX
	fx._emit(Vector3.ZERO, Vector3.ZERO, 0.3, 0.1, 0.2, 1.0, 0.0, Color.WHITE, 0.0, false, true)
	assert_int(fx._n).is_equal(Fx.POOL_MAX)
	# the Nuke's flash may use it (Fx.burst's `must`)
	fx._n = Fx.MAX_P
	fx.burst(Vector3.ZERO, Color.WHITE, 6.0, 1.0, true)
	assert_int(fx._n).is_equal(Fx.MAX_P + 2)
	fx._n = 0


func test_blasts_side_by_side_merge_and_a_swarm_goes_cheap() -> void:
	var fx := _fx()
	assert_int(fx.blast(Vector3.ZERO, 2.0)).is_equal(Fx.BLAST_DONE)
	# a second one on the same spot in the same moment only adds sparks
	var n1 := fx.blast_count()
	assert_int(fx.blast(Vector3(0.5, 0, 0), 2.0)).is_equal(Fx.BLAST_MERGED)
	assert_int(fx.blast_count() - n1).is_equal(3)
	assert_int(fx.blasts_merged).is_equal(1)
	# apart, they are their own
	for k in range(Fx.BLAST_BUSY - 1):
		assert_int(fx.blast(Vector3(5.0 * float(k + 1), 0, 0), 2.0)).is_equal(Fx.BLAST_DONE)
	# past BLAST_BUSY in the moment the rest go off cheap: the flash, the ball and four sparks
	var n2 := fx.blast_count()
	assert_int(fx.blast(Vector3(0, 0, 20), 2.0)).is_equal(Fx.BLAST_CHEAP)
	assert_int(fx.blast_count() - n2).is_equal(6)
	# a moment later, full again
	fx._process(Fx.BLAST_BUSY_SECONDS + 0.05)
	assert_int(fx.blast(Vector3(0, 0, 40), 2.0)).is_equal(Fx.BLAST_DONE)


func test_a_splash_has_no_clods_and_fewer_pieces() -> void:
	var fx := _fx()
	fx.blast(Vector3.ZERO, 2.0, Fx.BLAST_FIRE, Fx.BLAST_SPLASH)
	assert_int(fx.blast_kind_count(4)).is_equal(0)
	assert_int(fx.blast_kind_count(1)).is_equal(1)
	var splash := int(fx.last_blast["pieces"])
	fx._process(1.0)
	fx.blast(Vector3(10, 0, 0), 2.0)
	assert_int(int(fx.last_blast["pieces"])).is_greater(splash)


func test_the_run_sim_draws_no_blast() -> void:
	var fx := _fx()
	Run.sim_mode = true
	assert_int(fx.blast(Vector3.ZERO, 2.0)).is_equal(Fx.BLAST_NONE)
	Run.sim_mode = false
	assert_int(fx.blast_count()).is_equal(0)


func test_weapon_blast_rings_scorches_and_kicks_only_a_big_one() -> void:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var fx := Fx.new()
	g.add_child(fx)
	# the Rocket Pod's pop: a ring and a scorch, no kick
	fx.weapon_blast(Vector3.ZERO, 1.5, Fx.BLAST_ORANGE, Fx.BLAST_FULL, 1.0, g)
	assert_int((cam.get("shakes") as Array).size()).is_equal(0)
	assert_int(fx.blast_scorches).is_equal(1)
	assert_int(tg.live_count()).is_equal(2)
	# a level-5 Dynamite Stick (3.8 m): a kick of (3.8 - 2.2) x 0.3
	fx.weapon_blast(Vector3(20, 0, 0), 3.8, Fx.BLAST_ORANGE, Fx.BLAST_FULL, 1.0, g)
	assert_int((cam.get("shakes") as Array).size()).is_equal(1)
	assert_float(float((cam.get("shakes") as Array)[0])).is_equal_approx(0.48, 0.001)
	assert_float(Fx.blast_kick(3.8)).is_equal_approx(0.48, 0.001)
	assert_float(Fx.blast_kick(2.0)).is_equal(0.0)
	assert_float(Fx.blast_kick(10.0, 3.0)).is_equal(Fx.BLAST_KICK_MAX)
	# another big one in the same moment: no second kick; on the same spot within the second: no second scorch
	fx.weapon_blast(Vector3(40, 0, 0), 3.8, Fx.BLAST_ORANGE, Fx.BLAST_FULL, 1.0, g)
	assert_int((cam.get("shakes") as Array).size()).is_equal(1)
	var scorches := fx.blast_scorches
	fx._process(0.3)
	fx.weapon_blast(Vector3(40.5, 0, 0), 3.8, Fx.BLAST_ORANGE, Fx.BLAST_FULL, 1.0, g)
	assert_int(fx.blast_scorches).is_equal(scorches)
	assert_int((cam.get("shakes") as Array).size()).is_equal(2)
	# a splash (the Molotov, Skull Rain) never kicks nor scorches
	fx._process(1.0)
	scorches = fx.blast_scorches
	fx.weapon_blast(Vector3(80, 0, 0), 3.8, Fx.BLAST_FIRE, Fx.BLAST_SPLASH, 1.0, g)
	assert_int(fx.blast_scorches).is_equal(scorches)
	assert_int((cam.get("shakes") as Array).size()).is_equal(2)


func test_each_weapon_blasts_in_its_own_colour_and_style() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var dyn := _inst("lob_grenade")
	assert_bool(Fx.blast_colour(dyn, dyn.element()).is_equal_approx(Fx.BLAST_ORANGE)).is_true()
	assert_int(Fx.blast_style(dyn)).is_equal(Fx.BLAST_FULL)
	var gold := _inst("golden_pineapple")
	var gc := Fx.blast_colour(gold, gold.element())
	assert_bool(gc.is_equal_approx(Color("#FFC21F"))).is_true()
	assert_float(gc.r).is_greater(gc.b + 0.5)
	assert_int(Fx.blast_style(_inst("rocket_pod"))).is_equal(Fx.BLAST_FULL)
	assert_int(Fx.blast_style(_inst("land_mine"))).is_equal(Fx.BLAST_FULL)
	var mol := _inst("molotov")
	assert_int(Fx.blast_style(mol)).is_equal(Fx.BLAST_SPLASH)
	assert_bool(Fx.blast_colour(null, "poison").is_equal_approx(Fx.BLAST_POISON)).is_true()
	assert_bool(Fx.blast_colour(null, "fire").is_equal_approx(Fx.BLAST_FIRE)).is_true()


func test_the_blast_shader_is_see_through_so_the_stage_filter_never_dims_it() -> void:
	var sh: Shader = load("res://core/shaders/blast_fx.gdshader")
	assert_bool(StageStencil.shader_is_opaque(sh.code)).is_false()
	assert_int(Fx.BLAST_PRIORITY).is_greater(StageLook.PRIORITY)
	assert_int(Fx.BLAST_PRIORITY).is_greater(Fx.BLOOD_PRIORITY)


# ---------------------------------------------------------------- B. the breath behind him

func _breath_world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(BREATH_TEST.FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO_AWAY))
	g.add_child(hero)
	g.player = hero
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
	var i := em.spawn("skeleton", Vector3(0, 0, -2.5), null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	if em.rise_t.size() > i:
		em.rise_t[i] = 1.0
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func test_the_breath_draws_behind_him_in_his_back_views() -> void:
	var w := _breath_world()
	var hero: Node3D = w["hero"]
	var b := FireBreath.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst("dragons_breath", 1), w["g"])
	hero.set("away", true)
	assert_bool(b._fire()).is_true()
	var bf: BreathFlames = b.flames()
	assert_bool(bf.behind).is_true()
	assert_int(bf.draw_priority()).is_equal(BreathFlames.BEHIND_PRIORITY)
	# before his second pass (which paints him over them), after the ground's wash
	assert_int(BreathFlames.BEHIND_PRIORITY).is_less(BillboardSprite.OVER_PRIORITY)
	assert_int(BreathFlames.BEHIND_PRIORITY).is_greater(Telegraphs.PRIO_DISC)
	# he turns to face the camera: over him again, at the view change
	hero.set("away", false)
	b._tick(DT)
	assert_bool(bf.behind).is_false()
	assert_int(bf.draw_priority()).is_equal(0)
	hero.set("away", true)
	b._tick(DT)
	assert_int(bf.draw_priority()).is_equal(BreathFlames.BEHIND_PRIORITY)
	# the core shares the switch
	var cm := (bf.core.mesh as QuadMesh).material as ShaderMaterial
	assert_int(cm.render_priority).is_equal(BreathFlames.BEHIND_PRIORITY)


func test_a_ring_of_fire_stays_over_him() -> void:
	var w := _breath_world()
	var b := FireBreath.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst("dragons_breath", 1), w["g"])
	(w["hero"] as Node3D).set("away", true)
	b._ring = true
	assert_bool(b.flames_behind()).is_false()
	b._ring = false
	assert_bool(b.flames_behind()).is_true()


func test_he_faces_away_in_his_back_and_back_diagonal_views() -> void:
	var p: Player = auto_free(Player.new())
	for v: String in ["", "_bd"]:
		p.set("_view", v)
		assert_bool(p.faces_away()).override_failure_message(v).is_true()
	for v: String in ["_s", "_fd", "_f"]:
		p.set("_view", v)
		assert_bool(p.faces_away()).override_failure_message(v).is_false()


# ---------------------------------------------------------------- C. the kill counter on the drawer's middle

func test_the_kill_counter_sits_on_the_middle_of_the_item_slots() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.kills = 0
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await get_tree().process_frame
	hud._refresh_rows()
	hud._fit_top()
	var kc := hud.kill_counter()
	var mid := kc.position.y + kc.row_height() * 0.5
	assert_float(mid).is_equal_approx(HUD.SLOT_Y + HUD.WEAPON_PX * 0.5, 0.5)
	assert_float(hud.slots_middle_y()).is_equal_approx(HUD.SLOT_Y + HUD.WEAPON_PX * 0.5, 0.5)
	# still centred under the clock, between the weapons and the lines
	var plate: Control = hud._timer_plate
	assert_float(kc.position.x).is_equal_approx(plate.position.x + plate.size.x * 0.5, 0.5)
	assert_float(kc.position.y).is_greater_equal(plate.position.y + plate.size.y)
	# under the Endless WAVE tag it keeps its place, clear of the tag
	hud.test_stage_clock = {"endless": true, "endless_wave": 2, "endless_seconds": 12.0}
	hud._tick_stage_clock()
	var tag: Control = hud._stage_tag
	assert_bool(tag.visible).is_true()
	assert_float(kc.position.y + kc.row_height() * 0.5).is_equal_approx(HUD.SLOT_Y + HUD.WEAPON_PX * 0.5, 0.5)
	assert_float(kc.position.y).is_greater_equal(tag.position.y + tag.size.y + HUD.KILLS_TAG_GAP - 0.01)
	# the portal's ENDLESS IN tag too
	hud.test_stage_clock = {"portal_left": 30.0}
	hud._tick_stage_clock()
	assert_float(kc.position.y + kc.row_height() * 0.5).is_equal_approx(HUD.SLOT_Y + HUD.WEAPON_PX * 0.5, 0.5)
	assert_float(kc.position.y).is_greater_equal(hud._stage_tag.position.y + hud._stage_tag.size.y + HUD.KILLS_TAG_GAP - 0.01)
	hud.test_stage_clock = {}
