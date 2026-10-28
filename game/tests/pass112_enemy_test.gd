extends GdUnitTestSuite

## Pass 112, lane ENEMY: three follow-ups Garry asked for.
## 1. The harpooner's chain breaks with a visual when the rope ends any other way than a miss's reel
##    (HarpoonChain.snap_break: sparks and a tink at the break, the halves whip, drop and shrink away, the hook falls).
## 2. The hero's run cycle plays at his walk's share of his full speed (Player.run_rate, BillboardSprite.rate).
## 3. The warm-up loads the creatures' thrown models and draws the chain under the beam, for at least MIN_FRAMES frames.

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
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e := true) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
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
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
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
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "cam": cam, "fx": fx}


func _chain(w: Dictionary) -> HarpoonChain:
	var ch := HarpoonChain.new()
	(w["pm"] as Node).add_child(ch)
	ch.setup(w["g"])
	ch.configure(Registry.enemy("harpoon_troglodyte").ranged["harpoon_fx"])
	return ch


func _harpooner(em: EnemyManager) -> int:
	var i := em.spawn("harpoon_troglodyte", Vector3(0, 0, -10), null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.rise_t[i] = 1.0
	return i


# ---------------------------------------------------------------- 1. the chain breaks

func test_the_harpooners_block_has_its_break_and_the_defaults_fill_it() -> void:
	var m := HarpoonChain.merged(Registry.enemy("harpoon_troglodyte").ranged["harpoon_fx"])
	var b: Dictionary = m["break"]
	for k in ["at", "whip", "seconds", "recoil", "bits", "tink", "sfx"]:
		assert_bool(b.has(k)).override_failure_message(k).is_true()
	assert_float(float(b["seconds"])).is_greater(0.3)
	assert_float(float(b["at"])).is_between(0.1, 0.9)


func test_a_held_chain_snaps_its_halves_fall_and_shrink_away() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ch := _chain(w)
	var i := _harpooner(em)
	var hero := Vector3(0, 0.85, 0)
	var hand := ch.hand_of(i, hero)
	ch.hooked(hero, hand)
	ch.draw(hand, ch.eye_of(hero, hand), 0.06, HarpoonChain.SLACK)
	ch.show_hook(hero, hand)
	var held := ch.links_drawn
	assert_int(held).is_greater(10)
	var fx: Fx = w["fx"]
	var parts0 := int(fx.get("_n"))
	ch.snap_break(i)
	assert_bool(ch.breaking()).is_true()
	assert_int(ch.breaks).is_equal(1)
	# the clank, the tink and the iron bits went out
	assert_int(int(fx.get("_n"))).is_greater(parts0 + 8)
	# the two halves are drawn while they fall, a gap between them where it broke
	ch._process(DT)
	assert_int(ch.links_drawn).is_greater(4)
	assert_int(ch.links_drawn).is_less_equal(held + 2)
	var secs := float(ch.cfg["break"]["seconds"])
	var s := DT
	var shrunk := false
	while ch.breaking() and s < secs + 1.0:
		ch._process(DT)
		s += DT
		if s > secs * 0.8 and ch.breaking():
			shrunk = shrunk or ch._hook_k < 0.6
	assert_bool(ch.breaking()).is_false()
	assert_float(s).is_equal_approx(secs, 0.05)
	assert_bool(shrunk).is_true()
	assert_int(ch.links_drawn).is_equal(0)
	assert_bool(ch._hook.visible).is_false()


func test_the_hook_falls_off_the_hero_to_the_sand() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ch := _chain(w)
	var i := _harpooner(em)
	var hero := Vector3(0, 0.85, 0)
	var hand := ch.hand_of(i, hero)
	ch.draw(hand, ch.eye_of(hero, hand), 0.06, HarpoonChain.SLACK)
	ch.show_hook(hero, hand)
	ch.snap_break(i)
	for k in range(int(float(ch.cfg["break"]["seconds"]) * 0.5 / DT)):
		ch._process(DT)
	# half way through it lies at his feet (no map: the ground is 0)
	assert_float(ch._hook.global_position.y).is_less(0.4)


func test_a_miss_still_reels_home_and_never_breaks() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ch := _chain(w)
	var i := _harpooner(em)
	ch.launch(Vector3(0, 1, -10), Vector3(0, 0, 1))
	ch.draw(ch.hand_of(i, Vector3(0, 1, 5)), Vector3(0, 1, 5), 0.03, HarpoonChain.FLY)
	ch.missed(Vector3(0, 1, 5), i)
	assert_bool(ch.reeling()).is_true()
	# a release while it reels leaves the reel alone
	ch.release()
	assert_bool(ch.reeling()).is_true()
	for k in range(60):
		ch._process(DT)
	assert_bool(ch.reeling()).is_false()
	assert_int(ch.breaks).is_equal(0)


func test_nothing_drawn_means_nothing_to_break() -> void:
	var w := _world()
	var ch := _chain(w)
	ch.snap_break(-1)
	assert_bool(ch.breaking()).is_false()
	assert_int(ch.breaks).is_equal(0)


func test_the_game_snaps_the_chain_when_the_rope_ends_and_hides_it_at_the_runs_end() -> void:
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	var body := src.substr(src.find("func tether_end() -> void:"), 1400)
	assert_str(body).contains("var broke_of := tether_i if (tether_i >= 0 and not _ended) else -1")
	assert_str(body).contains("_chain.snap_break(broke_of)")
	assert_str(body).contains("_chain.release()")


# ---------------------------------------------------------------- 2. the run cycle follows his walk

func test_the_run_rate_is_his_walks_share_of_his_full_speed() -> void:
	assert_float(Player.run_rate(5.0, 5.0)).is_equal(1.0)
	assert_float(Player.run_rate(2.5, 5.0)).is_equal_approx(0.5, 0.0001)
	assert_float(Player.run_rate(0.5, 5.0)).is_equal_approx(float(Player.RUN_ANIM_DEFAULTS["min"]), 0.0001)
	assert_float(Player.run_rate(0.0, 5.0)).is_greater(0.0)
	# never faster than the authored cycle by default (a Sprint keeps the cycle)
	assert_float(Player.run_rate(8.0, 5.0)).is_equal(1.0)
	# a hero's own numbers
	assert_float(Player.run_rate(0.5, 5.0, {"min": 0.6})).is_equal_approx(0.6, 0.0001)
	assert_float(Player.run_rate(8.0, 5.0, {"max": 1.3})).is_equal_approx(1.3, 0.0001)
	# the water's 10% slow and the rope's 70% each slow the cycle as much as the walk
	assert_float(Player.run_rate(5.0 * 0.9, 5.0)).is_equal_approx(0.9, 0.0001)
	assert_float(Player.run_rate(5.0 * 0.7, 5.0)).is_equal_approx(0.7, 0.0001)


func test_the_sprite_plays_its_strip_at_the_rate() -> void:
	var sp := BillboardSprite.new()
	add_child(sp)
	auto_free(sp)
	var tex := ImageTexture.create_from_image(Image.create(64, 8, false, Image.FORMAT_RGBA8))
	sp.setup(tex, {"idle": 2, "run": 6}, ["idle", "run"], 1.9, 0, {"run": 12.0})
	sp.play("run")
	sp._process(0.25)
	var full := sp.frame
	sp.frame = 0.0
	sp.rate = 0.5
	sp._process(0.25)
	assert_float(sp.frame).is_equal_approx(full * 0.5, 0.001)


func test_a_heros_json_may_set_its_own_run_anim() -> void:
	var c: CharacterDef = Registry.character("drifter")
	assert_bool(c.run_anim is Dictionary).is_true()
	var d: CharacterDef = JsonContent._character({"id": "probe_hero", "run_anim": {"min": 0.5}}, "res://content/characters/drifter")
	assert_float(float(d.run_anim.get("min", 0.0))).is_equal(0.5)
	assert_bool(JsonContent._character({"id": "probe_hero2"}, "res://content/characters/drifter").run_anim.is_empty()).is_true()


# ---------------------------------------------------------------- 3. the warm-up

func test_the_warm_up_loads_every_creature_throw_and_draws_some_frames() -> void:
	assert_int(Warmup.MIN_FRAMES).is_greater_equal(4)
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var kinds0 := pm.kinds.size()
	var wu := Warmup.new()
	add_child(wu)
	auto_free(wu)
	wu._warm_creature_shots(pm)
	var cactus: EnemyDef = Registry.enemy("spit_cactus")
	var bomb := EnemyManager.throw_block(cactus)
	var look = bomb.get("material", {})
	var key := "%s|%s|%s" % [str(bomb["model"]), float(bomb.get("scale", 1.0)), look if look is Dictionary else {}]
	assert_bool(pm._dyn_kinds.has(key)).is_true()
	assert_int(pm.kinds.size()).is_greater(kinds0)
	# the first throw finds its kind made: nothing to load then
	var k := pm.kinds.size()
	pm.dynamite_kind(str(bomb["model"]), float(bomb.get("scale", 1.0)), look if look is Dictionary else {})
	assert_int(pm.kinds.size()).is_equal(k)


func test_the_chain_draws_once_under_the_beam_and_goes() -> void:
	var w := _world()
	var ch := _chain(w)
	ch.warm(Vector3(0, -8, 0))
	assert_int(ch.links_drawn).is_greater(2)
	assert_bool(ch._hook.visible).is_true()
	ch.warm(Vector3.INF)
	assert_int(ch.links_drawn).is_equal(0)
	assert_bool(ch._hook.visible).is_false()


func test_the_shots_warm_draw_takes_a_size() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	pm.warm_draw(Vector3(0, 1, 0), 0.03)
	assert_float(pm._warm_scale).is_equal_approx(0.03, 0.0001)
	pm.warm_draw(Vector3.INF)
