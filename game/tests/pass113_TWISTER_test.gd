extends GdUnitTestSuite

## Pass 113, lane TWISTER (Garry, 2026-10-28: "Tornadoes still don't look like tornadoes and are quite confusing. Make
## them rarer too."). Pinned here: the map's dust devils come on their clock (none at the start, the first not before
## `first`, the gaps between two formings within `every`, never more than max_alive, each gone after its life), only in
## the phases the block allows, form on the screen, grab nothing while forming or fading, throw the hero as pass 44 did
## and lift the creatures; every part of the look sits before the stage's filter (pass 87's intent); a TornadoFx at
## strength 0 draws nothing, forms from the ground up and thins away; the map builds no always-on dust devil any more.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
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
func hint_once(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var launches: Array = []
func launch(v: Vector3) -> void:
	launches.append(v)
"""

const FAKE_HUD := """extends Node
var toasts: Array = []
func toast(t, _c = null, _i = null) -> void:
	toasts.append(str(t))
"""

const FAKE_RIG := """extends Node
var camera: Camera3D
"""

const FAKE_DIRECTOR := """extends Node
var running := true
var phase := 0
"""

const DT := 1.0 / 30.0
const VP := Vector2i(540, 1200)
const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game: the hero at the origin, the game's portrait camera over him (46 degrees down, 22.5 m back, fov 55, in its
## own 540 x 1200 viewport), a director running stage time, a hud that keeps its toasts, no map (flat sand at 0), and the
## clock with `block`.
func _game(block, with_enemies := false) -> Dictionary:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var hud := Node.new()
	hud.set_script(_script(FAKE_HUD))
	g.add_child(hud)
	g.hud = hud
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
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	g.director = d
	var em: EnemyManager = null
	if with_enemies:
		em = EnemyManager.new()
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
	var dds := DustDevils.new()
	dds.game = g
	g.add_child(dds)
	dds.setup(block, 113)
	return {"g": g, "hero": hero, "hud": hud, "cam": cam, "dir": d, "dds": dds, "em": em}


func _on_screen(cam: Camera3D, p: Vector3) -> bool:
	return not cam.is_position_behind(p) and Rect2(Vector2.ZERO, Vector2(VP)).has_point(cam.unproject_position(p))


# ---------------------------------------------------------------- 1. the numbers

func test_the_defaults_make_them_rare_and_the_block_reads_as_it_is() -> void:
	var c := DustDevils.config_of(null)
	assert_bool(c["enabled"]).is_true()
	assert_float(c["first"]).is_equal(90.0)
	assert_object(c["every"]).is_equal(Vector2(120.0, 180.0))
	assert_object(c["life"]).is_equal(Vector2(20.0, 30.0))
	assert_int(c["max_alive"]).is_equal(1)
	assert_float(c["radius"]).is_equal(2.4)
	assert_str(c["wander"]).is_equal("cross")
	# the hero's throw and the creatures' ride are pass 44's
	assert_float(c["toss"]["up"]).is_equal(8.0)
	assert_float(c["toss"]["out"]).is_equal(3.6)
	assert_float(c["toss"]["cooldown"]).is_equal(1.2)
	assert_float(c["lift"]).is_equal(1.7)
	assert_bool(c["in_boss"]).is_false()
	# gaps under EVERY_MIN, a life shorter than its forming and fading, an unknown wander, a half toss
	var o := DustDevils.config_of({"every": 2, "life": [1, 3], "wander": "zigzag", "toss": {"up": 5}, "max_alive": -2})
	assert_object(o["every"]).is_equal(Vector2(DustDevils.EVERY_MIN, DustDevils.EVERY_MIN))
	assert_float((o["life"] as Vector2).x).is_greater_equal(float(o["form_seconds"]) + float(o["fade_seconds"]))
	assert_str(o["wander"]).is_equal("cross")
	assert_float(o["toss"]["up"]).is_equal(5.0)
	assert_float(o["toss"]["out"]).is_equal(3.6)
	assert_int(o["max_alive"]).is_equal(0)
	assert_bool(DustDevils.config_of({"enabled": false})["enabled"]).is_false()
	# the map's own block is read through WaveTimeline (whatever Garry has set in it)
	var md: MapDef = Registry.map("red_canyon")
	var raw = (JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON)) as Dictionary).get("timeline_data", {}).get("dust_devils", {})
	assert_that(md.timeline.dust_devils).is_equal(raw if raw is Dictionary else {})
	var mc := DustDevils.config_of(md.timeline.dust_devils)
	assert_float((mc["every"] as Vector2).x).is_greater_equal(DustDevils.EVERY_MIN)
	# a stage's count: the first at `first`, then one every `every` on average
	assert_float(DustDevils.count_in(c, 60.0)).is_equal(0.0)
	assert_float(DustDevils.count_in(c, 430.0)).is_equal(3.0)
	assert_float(DustDevils.count_in(DustDevils.config_of({"enabled": false}), 600.0)).is_equal(0.0)


# ---------------------------------------------------------------- 2. the clock

func test_none_at_the_start_the_first_not_before_first_gaps_within_every_each_gone_after_its_life() -> void:
	var w := _game({"first": 20, "every": [30, 40], "life": [12, 14], "max_alive": 1})
	var dds: DustDevils = w["dds"]
	assert_int(dds.alive().size()).is_equal(0)
	var log: Array = []
	var most := 0
	var t := 0.0
	var seen: Dictionary = {}
	while t < 200.0:
		var before := dds.formed
		dds.tick(DT, 0)
		if dds.formed > before:
			var dd: DustDevil = dds.alive()[dds.alive().size() - 1]
			log.append(dds.clock)
			seen[dd] = dds.clock
			# it forms where the player sees it, form_dist from him
			assert_bool(_on_screen(w["cam"], dd.global_position)).is_true()
			var flat := Vector2(dd.global_position.x, dd.global_position.z).length()
			assert_float(flat).is_between(7.0, 11.0)
		for dd: DustDevil in dds.alive():
			dd.step(DT)
			if dd.gone:
				# gone after its life, rolled within [12, 14]
				assert_float(dds.clock - float(seen[dd])).is_between(12.0 - 0.1, 14.0 + 0.1)
		most = maxi(most, dds.alive().size())
		t += DT
	assert_int(log.size()).is_greater_equal(5)
	assert_float(float(log[0])).is_between(20.0, 20.0 + 2.0 * DT)
	for k in range(1, log.size()):
		assert_float(float(log[k]) - float(log[k - 1])).is_between(30.0 - DT, 40.0 + 2.0 * DT)
	assert_int(most).is_equal(1)


func test_never_more_than_max_alive_a_due_one_waits_for_a_slot() -> void:
	var w := _game({"first": 5, "every": 10, "life": 25, "max_alive": 2})
	var dds: DustDevils = w["dds"]
	var most := 0
	var starts: Array = []
	var t := 0.0
	while t < 120.0:
		var before := dds.formed
		dds.tick(DT, 0)
		if dds.formed > before:
			starts.append(dds.clock)
		for dd: DustDevil in dds.alive():
			dd.step(DT)
		most = maxi(most, dds.alive().size())
		t += DT
	assert_int(most).is_equal(2)
	# the third was due at 25 but came only once the first had gone (5 + 25 = 30)
	assert_float(float(starts[2])).is_between(30.0 - DT, 30.0 + 2.0 * DT)


func test_only_in_the_phases_it_runs_in_and_one_standing_fades_when_its_phase_ends() -> void:
	var w := _game({"first": 5, "every": 60, "life": 40})
	var dds: DustDevils = w["dds"]
	# the boss fight (phase 1): no clock, none comes
	var t := 0.0
	while t < 30.0:
		dds.tick(DT, 1)
		t += DT
	assert_float(dds.clock).is_equal(0.0)
	assert_int(dds.formed).is_equal(0)
	# the stage's own time: it comes at 5
	t = 0.0
	while t < 8.0:
		dds.tick(DT, 0)
		for dd: DustDevil in dds.alive():
			dd.step(DT)
		t += DT
	assert_int(dds.alive().size()).is_equal(1)
	var dd: DustDevil = dds.alive()[0]
	assert_bool(dd.catching()).is_true()
	# the boss comes: it fades away (grabbing nothing more) and is gone after its fade
	dds.tick(DT, 1)
	assert_bool(dd.catching()).is_false()
	assert_bool(dd.fading()).is_true()
	t = 0.0
	while t < dd.fade_seconds + 0.2:
		dd.step(DT)
		t += DT
	assert_bool(dd.gone).is_true()
	# disabled: never
	var off := _game({"enabled": false})
	t = 0.0
	while t < 300.0:
		(off["dds"] as DustDevils).tick(0.5, 0)
		t += 0.5
	assert_int((off["dds"] as DustDevils).formed).is_equal(0)


func test_the_first_one_of_a_run_says_so_once() -> void:
	var w := _game({"first": 1, "every": 10, "life": 8})
	var dds: DustDevils = w["dds"]
	var t := 0.0
	while t < 40.0:
		dds.tick(DT, 0)
		for dd: DustDevil in dds.alive():
			dd.step(DT)
		t += DT
	assert_int(dds.formed).is_greater_equal(3)
	assert_array(w["hud"].toasts).is_equal([DustDevils.WARN_TEXT])
	var quiet := _game({"first": 1, "every": 10, "life": 8, "warn": false})
	(quiet["dds"] as DustDevils).tick(2.0, 0)
	assert_int((quiet["dds"] as DustDevils).formed).is_equal(1)
	assert_array(quiet["hud"].toasts).is_empty()


# ---------------------------------------------------------------- 3. what it does

func test_it_forms_then_grabs_then_fades_and_its_look_follows() -> void:
	var w := _game({"first": 9999})
	var dds: DustDevils = w["dds"]
	var dd := dds.call_one(Vector3(0, 0, -8), Vector3(1, 0, 0))
	assert_object(dd).is_not_null()
	var cfg := dds.cfg
	assert_float(dd.life).is_between((cfg["life"] as Vector2).x, (cfg["life"] as Vector2).y)
	# forming: the skirt first, the funnel rising after it; no grab
	dd.step(float(cfg["form_seconds"]) * 0.15)
	assert_bool(dd.catching()).is_false()
	assert_float(dd.fx.skirt_amount).is_greater(0.0)
	assert_float(dd.fx.grow).is_equal(0.0)
	dd.step(float(cfg["form_seconds"]))
	assert_bool(dd.catching()).is_true()
	assert_float(dd.fx.strength).is_equal(1.0)
	assert_float(dd.fx.grow).is_equal(1.0)
	# it moves at its speed
	var at := dd.global_position
	dd.step(1.0)
	assert_float(Vector2(dd.global_position.x - at.x, dd.global_position.z - at.z).length()).is_equal_approx(float(cfg["speed"]), 0.15)
	# fading: no grab, the funnel thins (still risen), the puff, then gone
	dd.fade_out()
	dd.step(0.5)
	assert_bool(dd.catching()).is_false()
	assert_float(dd.fx.thin).is_less(1.0)
	assert_float(dd.fx.grow).is_equal(1.0)
	dd.step(dd.fade_seconds)
	assert_bool(dd.gone).is_true()
	assert_float(dd.fx.burst_t).is_greater(0.0)


func test_the_heros_toss_is_pass_44s_and_creatures_are_lifted() -> void:
	var w := _game({"first": 9999}, true)
	var dds: DustDevils = w["dds"]
	var em: EnemyManager = w["em"]
	var hero = w["hero"]
	var dd := dds.call_one(Vector3(2.0, 0, 0), Vector3(0, 0, 1))
	dd.speed = 0.0
	var i := em.spawn("skeleton", Vector3(2.0, 0, 1.0), null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	# forming: the hero stands in its ring and the creature in its reach, and nothing happens
	dd.step(float(dds.cfg["form_seconds"]) * 0.9)
	assert_array(hero.launches).is_empty()
	assert_float(em.lift_t[i]).is_equal(0.0)
	# formed: thrown up and out (8 up, 3.6 out, away from its middle), once in 1.2 s; the creature lifted
	dd.step(float(dds.cfg["form_seconds"]) * 0.2)
	assert_int(hero.launches.size()).is_equal(1)
	var v: Vector3 = hero.launches[0]
	assert_float(v.y).is_equal(8.0)
	assert_float(Vector2(v.x, v.z).length()).is_equal_approx(3.6, 0.001)
	assert_float(v.x).is_less(0.0)
	assert_float(em.lift_t[i]).is_greater(0.0)
	assert_int(em.lift_mode[i]).is_equal(0)
	dd.step(0.5)
	assert_int(hero.launches.size()).is_equal(1)
	dd.step(0.8)
	assert_int(hero.launches.size()).is_equal(2)
	assert_int(dd.tosses).is_equal(2)
	# out of its ring: no throw
	hero.global_position = Vector3(2.0 + dd.reach() + 0.3, 0, 0)
	dd.step(1.5)
	assert_int(hero.launches.size()).is_equal(2)


func test_the_arena_calls_one_and_sends_it_away() -> void:
	var w := _game({"first": 9999})
	var dds: DustDevils = w["dds"]
	var a := dds.call_one()
	assert_object(a).is_not_null()
	assert_bool(_on_screen(w["cam"], a.global_position)).is_true()
	# max_alive 1: calling another sends the first away
	var b := dds.call_one()
	assert_bool(a.fading()).is_true()
	assert_bool(b.fading()).is_false()
	dds.send_away()
	assert_bool(b.fading()).is_true()


# ---------------------------------------------------------------- 4. the look

## Pass 87's intent: the dust devil comes before the stage's filter (an evening or a blood moon tints it like the sand).
func test_every_part_is_drawn_before_the_stage_filter() -> void:
	var dd := DustDevil.new()
	add_child(dd)
	var parts := dd.find_children("*", "GeometryInstance3D", true, false)
	assert_int(parts.size()).is_greater_equal(5)
	for gi: GeometryInstance3D in parts:
		assert_int((gi.material_override as Material).render_priority).is_less(StageLook.PRIORITY)
		assert_int(gi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# the ring under the tornado, the skirt under the funnel, the wisps last
	var fx: TornadoFx = dd.fx
	assert_int((dd.ring.material_override as Material).render_priority).is_less(TornadoFx.PRIORITY)
	var by: Dictionary = {}
	for gi: GeometryInstance3D in fx.parts():
		by[gi.name] = gi.sorting_offset
	assert_float(float(by["Skirt"])).is_less(float(by["Funnel"]))
	assert_float(float(by["Funnel"])).is_less(float(by["Wisps"]))
	dd.queue_free()


func test_a_tornado_at_strength_0_draws_nothing_forms_from_the_ground_and_thins_away() -> void:
	var fx: TornadoFx = auto_free(TornadoFx.new())
	add_child(fx)
	assert_bool(fx.is_visible_in_tree()).is_true()
	fx.set_strength(0.0)
	assert_bool(fx.is_visible_in_tree()).is_false()
	for gi: GeometryInstance3D in fx.parts():
		assert_bool(gi.is_visible_in_tree()).is_false()
	# rising: the skirt first, then the funnel grows up out of it
	fx.set_strength(0.15)
	assert_bool(fx.is_visible_in_tree()).is_true()
	assert_float(fx.skirt_amount).is_greater(0.0)
	assert_float(fx.grow).is_equal(0.0)
	fx.set_strength(0.6)
	assert_float(fx.grow).is_between(0.1, 0.9)
	assert_float(fx.thin).is_equal(1.0)
	fx.set_strength(1.0)
	assert_float(fx.grow).is_equal(1.0)
	# falling: the funnel stays risen and thins (ropes out); the skirt goes last
	fx.set_strength(0.4)
	assert_bool(fx.collapsing).is_true()
	assert_float(fx.grow).is_equal(1.0)
	assert_float(fx.thin).is_less(1.0)
	assert_float(fx.skirt_amount).is_equal(1.0)
	# the puff is drawn after the strength reaches 0, for BURST_SECONDS
	fx.burst()
	fx.set_strength(0.0)
	assert_bool(fx.is_visible_in_tree()).is_true()
	fx._process(TornadoFx.BURST_SECONDS + 0.05)
	assert_bool(fx.is_visible_in_tree()).is_false()
	# and forms afresh from 0
	fx.set_strength(0.1)
	assert_float(fx.grow).is_equal(0.0)
	# the API: numbers set after add_child reach the shaders
	fx.height = 9.0
	fx.color = Color(0.5, 0.4, 0.3)
	fx._process(0.016)
	var funnel := fx.get_node("Funnel") as MeshInstance3D
	assert_float(float((funnel.material_override as ShaderMaterial).get_shader_parameter("height"))).is_equal(9.0)
	assert_float(funnel.custom_aabb.size.y).is_greater(9.0)


func test_the_map_has_no_always_on_dust_devil_any_more() -> void:
	var src := FileAccess.get_file_as_string("res://world/maps/red_canyon/RedCanyon.gd")
	assert_str(src).contains("DustDevils.new()")
	assert_str(src).not_contains("DustDevil.new()")
	assert_str(src).not_contains("loop_center")
	# without a game (the title) the clock lays none
	var dds := DustDevils.new()
	add_child(dds)
	dds._process(500.0)
	assert_int(dds.alive().size()).is_equal(0)
	dds.queue_free()
