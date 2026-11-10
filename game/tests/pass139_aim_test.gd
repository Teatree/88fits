extends GdUnitTestSuite

## Pass 139, lane AIM (Garry: "Dragon's Breath, Big Mouth. Now that we have a kind of a attack direction indicator, let's
## go ahead and try to use that to indicate when dragon's breath and big mouth will attack next. For big mouth also go
## ahead and make the mouth do a nice wind up before and attack ... we need to make it a slow attack similar to how we
## dealt with the dragon's breath. So more damage but slower"): the aim wedge's tell for both weapons (its charge follows
## the cooldown: 0 as an attack ends, 1 ready and through the wind-up, the share left while it fires), the Big Mouth's
## longer, visible wind-up from its JSON (the beam pours after it), the slower and harder numbers read from the JSON, and
## the probe that measures the Mouth's DPS against pass 138's numbers (tools/dl/p139/AIM/dps.json).

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
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
var fwd := Vector3.FORWARD
var cinematic := false
signal hit
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return fwd
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func kick(_a = 0.0, _b = 0.0) -> void:
	pass
"""

const DT := 1.0 / 60.0
const PROBE_OUT := "res://../tools/dl/p139/AIM/dps.json"
const MOUTH_JSON := "res://content/weapons/big_mouth/big_mouth.json"
const LOUD_JSON := "res://content/evolutions/loudmouth/loudmouth.json"
## pass 138's numbers (history, for the probe's "old" side only): the cooldown, the damage a tick and the wind-up
const OLD := {"big_mouth": {"cooldown": 3.7647, "damage": 9.0}, "loudmouth": {"cooldown": 2.6, "damage": 16.0}}
const OLD_WINDUP := {"seconds": 0.24, "rear": 0.35, "gape": 36.0, "swell": 0.1, "tremble": 0.03}

var _aim_was := true
var _show_was := true


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_aim_was = Settings.aim_mode
	_show_was = Settings.show_aim
	Settings.aim_mode = true
	Settings.show_aim = true
	Aim.reset()


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Settings.show_aim = _show_was
	Run.weapons = []
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


## A tough creature standing where it was put (risen, on the screen).
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	em.rise_t[i] = 1.0
	em.pos[i] = at
	if em.onscreen.size() > i:
		em.onscreen[i] = 1
	em._rebuild_grid()
	return i


func _inst_of(def: WeaponDef, level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(def, level)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


func _mouth(w: Dictionary, id := "big_mouth", level := 1) -> LaserBeam:
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst_of(Registry.weapon(id), level))
	lb._yaw0 = 0.0
	lb._aim_yaw = 0.0
	return lb


func _breath(w: Dictionary) -> FireBreath:
	return _behaviour(w, FireBreath.new(), _inst_of(Registry.weapon("dragons_breath"))) as FireBreath


static func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- the numbers, from the JSON

func test_the_mouths_numbers_and_wind_up_come_from_its_json() -> void:
	var w := _world()
	for path: String in [MOUTH_JSON, LOUD_JSON]:
		var j := _json(path)
		var lb := _mouth(w, str(j["id"]))
		var base: Dictionary = j["base"]
		assert_float(lb.stat("cooldown")).is_equal_approx(float(base["cooldown"]), 0.0001)
		assert_float(lb.stat("damage")).is_equal_approx(float(base["damage"]), 0.0001)
		var wind: Dictionary = j["params"]["beam"]["windup"]
		for k: String in wind.keys():
			assert_float(lb.windup_value(k)).is_equal_approx(float(wind[k]), 0.0001)
		# the brief's shape: a wind-up longer than pass 88's 0.24 s that still reads as one breath, inside the cooldown with
		# the pour (no continuous beam at level 1), and the throat dark as it starts
		assert_float(lb.windup_seconds()).is_between(0.5, 1.0)
		assert_float(lb.windup_seconds() + lb.stat("duration")).is_less(lb.stat("cooldown"))
		assert_float(lb.windup_value("glow_from")).is_less(0.2)
		assert_float(lb.windup_value("inhale")).is_greater(0.0)
	# slower than pass 138 by about twice, and the Dragon's Breath stays the slowest weapon
	var bm := _json(MOUTH_JSON)
	var db := _json("res://content/weapons/dragons_breath/dragons_breath.json")
	assert_float(float(bm["base"]["cooldown"])).is_between(OLD["big_mouth"]["cooldown"] * 1.7, OLD["big_mouth"]["cooldown"] * 2.3)
	assert_float(float(bm["base"]["cooldown"])).is_less(float(db["base"]["cooldown"]))
	# harder a tick
	assert_float(float(bm["base"]["damage"])).is_greater(OLD["big_mouth"]["damage"])


# ---------------------------------------------------------------- the wind-up

func test_the_wind_up_is_a_visible_inhale_and_the_beam_pours_after_it() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -6), 2000.0)
	var lb := _mouth(w)
	lb._tick(DT)
	var rest: Vector3 = lb._familiar.global_position
	var jaw_rest: float = lb._jaw.rotation.x if lb._jaw else 0.0
	var started := -1
	var poured := -1
	var glow_start := -1.0
	var jaw_min := 0.0
	var back_max := 0.0
	for f in range(int(2.0 / DT)):
		lb._process(DT)
		if started < 0 and lb.tell_state() == AimWedge.TELL_WINDUP:
			started = f
			glow_start = lb.glow_level()
		if lb._windup_t > 0.0:
			if lb._jaw:
				jaw_min = minf(jaw_min, lb._jaw.rotation.x)
			# drawn back along the aim (the aim is -Z: back is +Z) and up
			back_max = maxf(back_max, lb._familiar.global_position.z - rest.z)
		if poured < 0 and lb.beams > 0:
			poured = f
	assert_int(started).is_equal(0)
	# the beam pours a wind-up after the pull (a frame or two either way)
	assert_float(float(poured - started)).is_between(lb.windup_seconds() / DT - 2.0, lb.windup_seconds() / DT + 2.0)
	# the throat starts dark and builds; the jaws gape wider than pass 88's 36 degrees; the mouth draws back
	assert_float(glow_start).is_less(0.35)
	if lb._jaw:
		assert_float(jaw_min).is_less(jaw_rest - deg_to_rad(40.0))
	assert_float(back_max).is_greater(lb.windup_value("pull") * 0.5)
	# the inhale drew its motes
	assert_int(lb.inhaled).is_between(int(lb.windup_value("inhale")) - 2, int(lb.windup_value("inhale")) + 1)


func test_pass_88s_wind_up_still_plays_with_the_new_keys_left_out() -> void:
	var w := _world()
	var lb := _mouth(w)
	lb.inst.params["beam"]["windup"] = OLD_WINDUP.duplicate()
	assert_float(lb.windup_value("pull")).is_equal(0.0)
	assert_float(lb.windup_value("glow_from")).is_equal_approx(0.7, 0.0001)
	assert_float(lb.windup_value("build")).is_equal_approx(1.0, 0.0001)
	assert_float(lb.windup_value("inhale")).is_equal(0.0)
	assert_float(lb.windup_value("release")).is_equal(0.0)


# ---------------------------------------------------------------- the tell

func test_the_mouths_tell_charges_with_the_cooldown_and_is_full_for_the_wind_up() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -6), 5000.0)
	var lb := _mouth(w)
	var cd := lb.stat("cooldown")
	var windups: Array = []
	var ends: Array = []
	var last := -1
	var prev_charge := -1.0
	var rising := true
	for f in range(int((2.0 * cd + 1.0) / DT)):
		lb._process(DT)
		var st := lb.tell_state()
		var c := lb.tell_charge()
		if st == AimWedge.TELL_WINDUP:
			assert_float(c).is_equal(1.0)
			if last != AimWedge.TELL_WINDUP:
				windups.append(f)
		elif st == AimWedge.TELL_CHARGE:
			if last == AimWedge.TELL_FIRING:
				ends.append(f)
				# 0 the moment the beam ends
				assert_float(c).is_less(0.02)
				prev_charge = c
			elif prev_charge >= 0.0:
				if c < prev_charge - 0.0001:
					rising = false
				prev_charge = c
		elif st == AimWedge.TELL_FIRING:
			assert_float(c).is_between(0.0, 1.0)
		last = st
	assert_int(windups.size()).is_greater_equal(2)
	assert_int(ends.size()).is_greater_equal(1)
	assert_bool(rising).is_true()
	# the next wind-up a cooldown after the last (the wind-up is inside the cooldown)
	assert_float(float(windups[1] - windups[0])).is_between(cd / DT - 2.0, cd / DT + 2.0)
	# the line runs from the mouth down its aim, its reach the weapon's
	var ln := lb.tell_line()
	assert_float(float(ln["reach"])).is_equal_approx(lb.stat("range"), 0.001)
	assert_float((ln["dir"] as Vector3).dot(Vector3.FORWARD)).is_greater(0.9)


func test_the_breaths_tell_charges_with_its_cooldown() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -3), 5000.0)
	var br := _breath(w)
	var cd := br.stat("cooldown")
	var fired: Array = []
	var last := -1
	var after_end := -1.0
	var mid := -1.0
	var ended := -1
	for f in range(int((cd + 1.5) / DT)):
		br._process(DT)
		var st := br.tell_state()
		if st == AimWedge.TELL_FIRING and last != AimWedge.TELL_FIRING:
			fired.append(f)
		if st == AimWedge.TELL_CHARGE and last == AimWedge.TELL_FIRING:
			ended = f
			after_end = br.tell_charge()
		if ended > 0 and f == ended + int(0.5 * (cd - br.breath_seconds()) / DT):
			mid = br.tell_charge()
		last = st
	assert_int(fired.size()).is_equal(2)
	assert_float(after_end).is_less(0.02)
	assert_float(mid).is_between(0.4, 0.6)
	assert_float(float(fired[1] - fired[0])).is_between(cd / DT - 2.0, cd / DT + 15.0)
	assert_float(br.tell_reach()).is_equal_approx(br.stat("range"), 0.0001)
	assert_float(br.tell_deg()).is_equal_approx(br.cone_deg(), 0.0001)


func test_the_wedge_shows_both_tells_and_follows_its_switches() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -3), 5000.0)
	var lb := _mouth(w)
	var br := _breath(w)
	Run.weapons = [lb.inst, br.inst]
	var wedge := AimWedge.make(w["g"])
	(w["g"] as Node).add_child(wedge)
	wedge._process(DT)
	assert_bool(wedge.visible).is_true()
	assert_object(wedge.breath_source()).is_same(br)
	assert_object(wedge.mouth_source()).is_same(lb)
	# the fan reaches out to the breath's cone; the line lies from the mouth to its reach
	assert_float(wedge.band_reach).is_equal_approx(br.stat("range"), 0.001)
	assert_float(wedge.band_deg).is_equal_approx(br.cone_deg(), 0.001)
	assert_bool(wedge._line.visible).is_true()
	var tr: Transform3D = wedge._line.global_transform
	assert_float(tr.basis.z.length()).is_equal_approx(lb.stat("range"), 0.01)
	var m := lb.muzzle()
	assert_float(Vector2(tr.origin.x - m.x, tr.origin.z - m.z).length()).is_less(0.01)
	# an attack starting flashes its band once
	var f0 := wedge.flashes
	for k in range(int(1.2 / DT)):
		lb._process(DT)
		br._process(DT)
		wedge._process(DT)
	assert_int(wedge.flashes).is_equal(f0 + 2)
	# "Show aim" off: no wedge, no tell
	Settings.show_aim = false
	wedge._process(DT)
	assert_bool(wedge.visible).is_false()
	assert_bool(wedge._line.is_visible_in_tree()).is_false()
	Settings.show_aim = true
	# the aim rule off: no wedge, no tell
	Settings.aim_mode = false
	wedge._recheck()
	wedge._process(DT)
	assert_bool(wedge.visible).is_false()
	assert_object(wedge.mouth_source()).is_null()
	Settings.aim_mode = true
	# the fan without the Breath is pass 136's size; with it, out to the band
	var plain := AimWedge.build_mesh(50.0)
	var wide := AimWedge.build_mesh(50.0, 6.0, 60.0)
	assert_float(plain.get_aabb().position.z).is_greater(-3.1)
	assert_float(wide.get_aabb().position.z).is_less(-5.9)
	assert_int(AimWedge.build_line_mesh().get_surface_count()).is_equal(1)


# ---------------------------------------------------------------- the probe

## A WeaponDef of `id` with pass 138's numbers (OLD, OLD_WINDUP), for the probe's "old" side.
func _old_def(id: String) -> WeaponDef:
	var d: WeaponDef = Registry.weapon(id).duplicate(true)
	d.base = d.base.duplicate(true)
	d.params = d.params.duplicate(true)
	d.base["cooldown"] = OLD[id]["cooldown"]
	d.base["damage"] = OLD[id]["damage"]
	d.params["beam"]["windup"] = OLD_WINDUP.duplicate()
	return d


## The damage a second one weapon deals over `secs` (every frame its whole cycle: the clock, the hold, the wind-up and
## the pour), the Outlaw standing still facing -Z: on one tough creature at the converge spot 6 m ahead (held), or the
## sum over a file of five 3..11 m ahead (file).
func _dps(def: WeaponDef, level: int, layout: String, secs: float) -> float:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids: Array = []
	if layout == "held":
		ids.append(_creature(em, Vector3(0, 0, -6), 20000.0))
	else:
		for k in range(5):
			ids.append(_creature(em, Vector3(0, 0, -3.0 - 2.0 * float(k)), 20000.0))
	var hp0 := 0.0
	for i: int in ids:
		hp0 += em.hp[i]
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst_of(def, level))
	lb._yaw0 = 0.0
	lb._aim_yaw = 0.0
	for f in range(int(secs / DT)):
		lb._process(DT)
	var hp1 := 0.0
	for i: int in ids:
		assert_bool(em.is_alive(i)).is_true()
		hp1 += em.hp[i]
	return (hp0 - hp1) / secs


func test_probe_the_mouths_dps_old_against_new() -> void:
	var out := {}
	var secs := 60.0
	for row: Array in [["big_mouth", 1], ["big_mouth", 3], ["big_mouth", 5], ["loudmouth", 1]]:
		var id: String = row[0]
		var lvl: int = row[1]
		var key := "%s_L%d" % [id, lvl]
		var r := {}
		for layout: String in ["held", "file"]:
			var o := _dps(_old_def(id), lvl, layout, secs)
			var n := _dps(Registry.weapon(id), lvl, layout, secs)
			r[layout] = {"old": snappedf(o, 0.01), "new": snappedf(n, 0.01), "ratio": snappedf(n / maxf(o, 0.001), 0.001)}
			assert_float(o).is_greater(0.0)
			assert_float(n).is_greater(0.0)
		var ni := _inst_of(Registry.weapon(id), lvl)
		var oi := _inst_of(_old_def(id), lvl)
		r["estimate"] = {"old": snappedf(oi.dps_estimate(), 0.01), "new": snappedf(ni.dps_estimate(), 0.01)}
		r["cooldown"] = {"old": snappedf(oi.stat("cooldown"), 0.001), "new": snappedf(ni.stat("cooldown"), 0.001)}
		r["damage"] = {"old": snappedf(oi.stat("damage"), 0.001), "new": snappedf(ni.stat("damage"), 0.001)}
		r["duration"] = snappedf(ni.stat("duration"), 0.001)
		out[key] = r
	out["seconds"] = secs
	out["tool"] = "tests/pass139_aim_test.gd test_probe_the_mouths_dps_old_against_new (fixed 1/60 s steps, aim on)"
	var f := FileAccess.open(ProjectSettings.globalize_path(PROBE_OUT), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
