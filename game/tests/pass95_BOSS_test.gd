extends GdUnitTestSuite

## Pass 95, lane BOSS (Garry: the King's tumbleweeds "should have a trail behind it. It's not visible right now"; the
## stomp "should have an animation of the king jumping and doing the stomp ... more than one stomp, 3 ... visible wave
## effects"; the Scorpion Elite "a more powerful sniper attack, that comes out of the scorpion's tail ... 3 in a
## sequence 1 after the other"): every tumbleweed shot wears a dust trail (ProjectileManager.TUMBLE_TRAIL, the row's
## `trail`) laid in the tracers' ring as it rolls, with puffs; the King's `stomp` script (EnemyManager._stomp_*): the
## pose held, the hop on lift_h, three landings gap + up + down apart, each a hit in the radius, a special push and a
## wave (Game.stomp_wave), a ring before every landing, the old `slam` untouched; the `tail_sniper` script
## (EnemyManager._tail_*): frozen, the Saiga's lines from the tail, three beams one after the other, each aimed afresh,
## twice the Saiga's damage, a hit of the hero once a beam, the Saiga unchanged; the common key `chance`; the Level
## Editor's tables name both scripts.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var toasts: Array = []
var hints: Array = []
var rings: Array = []
var lines: Array = []
var waves: Array = []
var volleys: Array = []
var shocks := 0
var bursts := 0
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	bursts += 1
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(a, _b) -> void:
	hints.append(str(a))
func telegraph_line(a, b, c, d, _e) -> void:
	lines.append({"from": a, "dir": b, "length": float(c), "dur": float(d)})
func telegraph_ring(a, b, c, _d, e = true) -> void:
	rings.append({"at": a, "r": float(b), "dur": float(c), "filled": bool(e)})
func shockwave(_a, _b) -> void:
	shocks += 1
func stomp_wave(a, b, c = 5.0) -> void:
	waves.append({"at": a, "r": float(b), "size": float(c)})
func tumbleweed_volley(at, first, count, speed, damage, life, knockback, lift, info, trail = {}) -> void:
	volleys.append({"at": at, "first": first, "count": count, "speed": speed, "damage": damage, "life": life, "knockback": knockback, "lift": lift, "info": info, "trail": trail})
func rocket_out(_i: int) -> bool:
	return false
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
var max_hp := 100.0
var last_outcome := "hit"
var hits: Array = []
var pushes: Array = []
var blasts: Array = []
func take_damage(a: float, f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "from": f, "info": i})
func special_push(v: Vector3) -> void:
	pushes.append(v)
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(v: Vector3, up: float = 0.0, _h: bool = true) -> void:
	blasts.append({"v": v, "up": up})
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_FX := """extends Node
var puffs: Array = []
func roll_dust(a, b, c = 1.0) -> void:
	puffs.append({"at": a, "back": b, "size": float(c)})
"""

const DT := 1.0 / 60.0

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.level = 1


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.set("player", hero)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _projectiles(g: Node) -> ProjectileManager:
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.set("projectiles", pm)
	pm.register_kind(BoxMesh.new(), null, 1.0, true)
	return pm


## A test creature `id` made from `from` (its variance off, no looks), with `extra` set on it; gone after the test.
func _test_def(id: String, from: String, extra: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	d.drops = {}
	for k: String in extra.keys():
		d.set(k, extra[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _attack_index(def: EnemyDef, atk_name: String) -> int:
	var attacks: Array = def.boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


func _row(def: EnemyDef, atk_name: String) -> Dictionary:
	var k := _attack_index(def, atk_name)
	return (def.boss["attacks"] as Array)[k] if k >= 0 else {}


## Creature `i` starts the attack at `k` of its list now (its wind-up and marks), as the runner does.
func _begin(em: EnemyManager, i: int, k: int) -> void:
	em.state[i] = EnemyManager.STATE_MOVE
	em.atk_i[i] = k
	em.atk_t[i] = 0.0
	em.hold_t[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)


## ... and fires it (the wind-up over).
func _fire(em: EnemyManager, i: int) -> void:
	em.timer[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)


## Ticks the manager until `cond` holds (at most `limit` seconds); the seconds it took, or -1.
func _run_until(em: EnemyManager, cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		em._physics_process(DT)
		t += DT
		if cond.call():
			return t
	return -1.0


# ---------------------------------------------------------------- 1. the content

func test_the_kings_rows_are_the_stomp_and_the_trail() -> void:
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var names: Array = []
	for a in king.boss.get("attacks", []):
		names.append(str((a as Dictionary).get("name", "")))
	assert_array(names).contains(["roll", "tumbleweed_volley", "spawn_ring", "stomp"])
	assert_array(names).not_contains(["slam"])
	var st := _row(king, "stomp")
	assert_int(int(st.get("stomps", 0))).is_equal(3)
	assert_float(float(st.get("gap", 0.0))).is_equal_approx(0.45, 0.0001)
	var j: Dictionary = st.get("jump", {})
	assert_float(float(j.get("height", 0.0))).is_equal_approx(2.2, 0.0001)
	assert_float(float(j.get("up", 0.0))).is_equal_approx(0.35, 0.0001)
	assert_float(float(j.get("down", 0.0))).is_equal_approx(0.2, 0.0001)
	assert_float(float(st.get("radius", 0.0))).is_equal_approx(6.0, 0.0001)
	# 60% of the old slam's 30 a stomp
	assert_float(float(st.get("damage", 0.0))).is_equal_approx(18.0, 0.0001)
	assert_str(str(st.get("telegraph", ""))).is_equal("ring")
	assert_float(float(st.get("knockback", 0.0))).is_equal_approx(6.0, 0.0001)
	var vo := _row(king, "tumbleweed_volley")
	var trl: Dictionary = vo.get("trail", {})
	assert_bool(trl.is_empty()).is_false()
	for k in ["style", "colour", "width", "life", "puffs", "alpha"]:
		assert_bool(trl.has(k)).override_failure_message("the volley's trail has %s" % k).is_true()
	assert_str(king.doc).contains("stomps")
	# the Scorpion Elite's row
	var sc: EnemyDef = Registry.enemy("dune_scorpion")
	var tl := _row(sc, "tail_sniper")
	assert_bool(tl.is_empty()).is_false()
	assert_int(int(tl.get("count", 0))).is_equal(3)
	assert_float(float(tl.get("gap", 0.0))).is_equal_approx(0.6, 0.0001)
	assert_float(float(tl.get("aim", 0.0))).is_equal_approx(1.0, 0.0001)
	assert_float(float(tl.get("lock", 0.0))).is_equal_approx(0.4, 0.0001)
	assert_str(str(tl.get("damage_from", ""))).is_equal("saiga_sniper")
	assert_float(float(tl.get("damage_mult", 0.0))).is_equal_approx(2.0, 0.0001)
	assert_float(float(tl.get("chance", 0.0))).is_equal_approx(0.7, 0.0001)
	assert_float(float(tl.get("min_range", 0.0))).is_equal_approx(5.0, 0.0001)
	assert_float(float((tl.get("muzzle", {}) as Dictionary).get("up", 0.0))).is_equal_approx(2.0, 0.0001)
	assert_str(sc.doc).contains("beam")
	# Garry's uncommitted health numbers stand (never pinned here: read from the files)
	assert_float(king.hp).is_equal_approx(float(_json("res://content/bosses/tumbleweed_king/tumbleweed_king.json")["hp"]), 0.001)
	assert_float(sc.hp).is_equal_approx(float(_json("res://content/enemies/dune_scorpion/dune_scorpion.json")["hp"]), 0.001)


func test_the_tables_and_the_game_name_the_new_scripts() -> void:
	assert_array(BossAttackDef.SCRIPTS).contains(["stomp", "tail_sniper"])
	var em := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	assert_bool(em.contains('\t\t\t\t"stomp":\n')).is_true()
	assert_bool(em.contains('\t\t\t\t"tail_sniper":\n')).is_true()
	var gm := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(gm.contains("func stomp_wave(center: Vector3, r: float, size: float = 5.0)")).is_true()
	assert_bool(gm.contains("info: Dictionary, trail: Dictionary = {}) -> void:")).is_true()
	var fx := FileAccess.get_file_as_string("res://core/systems/Fx.gd")
	assert_bool(fx.contains("func stomp_dust(at: Vector3, r: float, size: float = 1.0)")).is_true()
	assert_bool(fx.contains("func roll_dust(at: Vector3, back: Vector3, size: float = 1.0)")).is_true()
	# the Level Editor's tables (their agreement with the code is the editor's selftest's)
	var root := ProjectSettings.globalize_path("res://").path_join("../tools/level_editor")
	for f in ["vocab.py", "assets_fields.js", "boss_model.js", "boss_attacks_io.py"]:
		var src := FileAccess.get_file_as_string(root.path_join(f))
		assert_bool(src.contains("stomp") and src.contains("tail_sniper")).override_failure_message("%s names the scripts" % f).is_true()
	assert_bool(FileAccess.get_file_as_string(root.path_join("vocab.py")).contains('"chance": None')).is_true()
	assert_bool(FileAccess.get_file_as_string(root.path_join("enemies.js")).contains("r.type === 'json'")).is_true()


# ---------------------------------------------------------------- 2. the tumbleweed trail

func test_a_tumbleweed_shot_wears_the_dust_trail_and_lays_it_as_it_rolls() -> void:
	var w := _world(Vector3(50, 0, 0))
	var g: Node = w["g"]
	var pm := _projectiles(g)
	var i := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "knockback": 14.0, "lift": 2.5, "info": {}})
	var j := pm.hostile_shot(0, Vector3(0, 0.55, 4), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false, {"shot": "pellet", "info": {}})
	assert_bool(pm.extra[i].has("tumble_trail")).is_true()
	assert_bool(pm.extra[j].has("tumble_trail")).is_false()
	assert_int(pm.tumble_trails).is_equal(1)
	var tt: Dictionary = pm.extra[i]["tumble_trail"]
	assert_bool(bool(tt["on"])).is_true()
	assert_int(int(tt["ts"])).is_equal(int(ProjectileManager.TRACER_STYLE_IDS[ProjectileManager.TUMBLE_TRAIL["style"]]))
	assert_float(float(tt["tw"])).is_equal_approx(float(ProjectileManager.TUMBLE_TRAIL["width"]), 0.0001)
	assert_float(float(tt["tl"])).is_equal_approx(float(ProjectileManager.TUMBLE_TRAIL["life"]), 0.0001)
	assert_float((tt["tc"] as Color).a).is_equal_approx(float(ProjectileManager.TUMBLE_TRAIL["alpha"]), 0.0001)
	# dark: it has to read on the light sand
	var c: Color = tt["tc"]
	assert_float(c.r + c.g + c.b).is_less(1.2)
	var seg0 := pm.tracer_segments
	var t := 0.0
	while t < 0.5:
		pm._physics_process(DT)
		t += DT
	# 4.5 m rolled: a segment every TRACER_SEG_MIN m, laid under the ball (its foot), in the trail's colour and width
	assert_int(pm.tracer_segments - seg0).is_between(10, 16)
	var last := (pm._ln_next - 1 + ProjectileManager.TRACER_LINE_MAX) % ProjectileManager.TRACER_LINE_MAX
	assert_float(pm.tracer_width[last]).is_equal_approx(float(tt["tw"]), 0.0001)
	assert_float(pm.tracer_life[last]).is_equal_approx(float(tt["tl"]), 0.0001)
	assert_float((pm.tracer_col[last] as Color).a).is_equal_approx(c.a, 0.0001)
	assert_int(pm.tracer_kind[last]).is_equal(int(tt["ts"]))
	assert_float((pm.tracer_to[last] as Vector3).y).is_equal_approx(pm.pos[i].y - ProjectileManager.TUMBLE_FOOT, 0.01)
	# the pellet laid nothing: it has no tracer of its own
	var seg1 := pm.tracer_segments
	pm._free(i)
	t = 0.0
	while t < 0.3:
		pm._physics_process(DT)
		t += DT
	assert_int(pm.tracer_segments).is_equal(seg1)


func test_the_rows_trail_overrides_the_default_and_none_keeps_the_old_bead() -> void:
	var w := _world(Vector3(50, 0, 0))
	var g: Node = w["g"]
	var pm := _projectiles(g)
	var i := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "info": {}, "trail": {"style": "streak", "width": 0.3, "colour": "#102030", "alpha": 0.5, "life": 0.4, "puffs": 0.0}})
	var tt: Dictionary = pm.extra[i]["tumble_trail"]
	assert_int(int(tt["ts"])).is_equal(int(ProjectileManager.TRACER_STYLE_IDS["streak"]))
	assert_float(float(tt["tw"])).is_equal_approx(0.3, 0.0001)
	assert_float(float(tt["tl"])).is_equal_approx(0.4, 0.0001)
	assert_float((tt["tc"] as Color).a).is_equal_approx(0.5, 0.0001)
	assert_float((tt["tc"] as Color).b).is_equal_approx(48.0 / 255.0, 0.01)
	assert_float(float(tt["puffs"])).is_equal(0.0)
	var k := pm.hostile_shot(0, Vector3(0, 0.55, 3), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "info": {}, "trail": {"style": "none"}})
	assert_bool(bool((pm.extra[k]["tumble_trail"] as Dictionary)["on"])).is_false()
	pm._free(i)
	var seg0 := pm.tracer_segments
	var beads0 := pm.trail_next
	var t := 0.0
	while t < 0.3:
		pm._physics_process(DT)
		t += DT
	# no ribbon for "none"; the pass 45 bead at its foot still drops
	assert_int(pm.tracer_segments).is_equal(seg0)
	assert_int(pm.trail_next).is_greater(beads0)


func test_the_trail_puffs_dust_at_the_balls_foot() -> void:
	var w := _world(Vector3(50, 0, 0))
	var g: Node = w["g"]
	var fx := Node.new()
	fx.set_script(_script(FAKE_FX))
	g.add_child(fx)
	g.set("fx", fx)
	var pm := _projectiles(g)
	var i := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "info": {}, "trail": {"puffs": 0.1}})
	var t := 0.0
	while t < 0.5:
		pm._physics_process(DT)
		t += DT
	# one every 0.1 s: four or five in half a second, each under the ball, drifting back the way it came
	assert_int(pm.tumble_puffs).is_between(4, 6)
	assert_int((fx.puffs as Array).size()).is_equal(pm.tumble_puffs)
	var p: Dictionary = fx.puffs[fx.puffs.size() - 1]
	assert_float((p["back"] as Vector3).x).is_less(-0.9)
	assert_float((p["at"] as Vector3).y).is_equal_approx(pm.pos[i].y - ProjectileManager.TUMBLE_FOOT, 0.01)


func test_the_runner_hands_the_kings_trail_to_the_volley() -> void:
	var w := _world(Vector3(20, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	var vi := _attack_index(king, "tumbleweed_volley")
	_begin(em, b, vi)
	_fire(em, b)
	assert_int((g.volleys as Array).size()).is_equal(1)
	var v: Dictionary = g.volleys[0]
	var row := _row(king, "tumbleweed_volley")
	assert_int(int(v["count"])).is_equal(int(row["count"]))
	assert_float(float(v["damage"])).is_equal_approx(float(row["damage"]) * em.stage_mult * em.level_dmg_mult, 0.001)
	assert_bool((v["trail"] as Dictionary) == (row["trail"] as Dictionary)).is_true()
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)


# ---------------------------------------------------------------- 3. the stomp

func test_the_stomp_jumps_three_times_and_lands_gap_apart() -> void:
	var w := _world(Vector3(4, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	assert_int(em.boss_index).is_equal(b)
	var si := _attack_index(king, "stomp")
	var row := _row(king, "stomp")
	_begin(em, b, si)
	# the wind-up's ring, as any attack's: the radius, 1.2 s
	assert_int((g.rings as Array).size()).is_equal(1)
	assert_float(float(g.rings[0]["r"])).is_equal_approx(6.0, 0.001)
	assert_float(float(g.rings[0]["dur"])).is_equal_approx(1.2 / em.pace, 0.001)
	_fire(em, b)
	# the run: the pose held (the runner's fire step parked), the first hop's ring runs on from the wind-up's
	assert_bool(em._stomps.has(b)).is_true()
	assert_int(em.stomp_runs).is_equal(1)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	assert_float(em.timer[b]).is_equal(EnemyManager.SNIPER_HELD)
	assert_int((g.rings as Array).size()).is_equal(2)
	assert_float(float(g.rings[1]["dur"])).is_equal_approx(0.55 / em.pace, 0.001)
	var times: Array = []
	var top := 0.0
	var t := 0.0
	var land_squash := 1.0
	while t < 8.0 and em._stomps.has(b):
		em._physics_process(DT)
		t += DT
		top = maxf(top, em.lift_h[b])
		if (hero.hits as Array).size() > times.size():
			times.append(t)
			land_squash = em.squash[b]
			# on the ground as it lands
			assert_float(em.lift_h[b]).is_equal(0.0)
	assert_bool(em._stomps.has(b)).is_false()
	# three stomps, three hits, three waves, gap + up + down (1.0 s) apart
	assert_int(em.stomp_lands).is_equal(3)
	assert_int(em.stomp_hero_hits).is_equal(3)
	assert_int((hero.hits as Array).size()).is_equal(3)
	assert_int((g.waves as Array).size()).is_equal(3)
	assert_float(float(g.waves[0]["r"])).is_equal_approx(6.0, 0.001)
	assert_float(float(g.waves[0]["size"])).is_equal_approx(em.size[b], 0.001)
	# (each phase ends on the first tick at or past its length: up to a tick's slack a phase)
	assert_float(float(times[1]) - float(times[0])).is_equal_approx(EnemyManager.stomp_period(row) / em.pace, 4.0 * DT)
	assert_float(float(times[2]) - float(times[1])).is_equal_approx(EnemyManager.stomp_period(row) / em.pace, 4.0 * DT)
	# the first landing: the hop after the fire step (up + down)
	assert_float(float(times[0])).is_equal_approx(EnemyManager.stomp_hop_seconds(row) / em.pace, 4.0 * DT)
	# the hop reached its height; it lands squashed
	assert_float(top).is_between(2.0, 2.25)
	assert_float(land_squash).is_less(0.7)
	# every hit: 60% of the old slam, a boss's hit that says stomp, a special push of 6 away from him
	for h in hero.hits:
		assert_float(float((h as Dictionary)["amount"])).is_equal_approx(18.0 * em.stage_mult * em.level_dmg_mult, 0.001)
		var info: Dictionary = (h as Dictionary)["info"]
		assert_str(str(info["kind"])).is_equal("boss")
		assert_array(info["fx"]).contains(["stomp"])
	assert_int((hero.pushes as Array).size()).is_equal(3)
	assert_float((hero.pushes[0] as Vector3).length()).is_equal_approx(6.0, 0.001)
	assert_float((hero.pushes[0] as Vector3).x).is_greater(5.9)
	assert_int((hero.blasts as Array).size()).is_equal(0)
	# a ring before every landing: the wind-up's, the first hop's, one after each of the first two landings (gap + hop long)
	assert_int((g.rings as Array).size()).is_equal(4)
	assert_float(float(g.rings[2]["dur"])).is_equal_approx(EnemyManager.stomp_period(row) / em.pace, 0.001)
	# then the cooldown, on the ground, walking again (the runner ticks the cooldown down in the same frame the run ends)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[b]).is_between(float(king.boss["cooldown_between"]) - 2.0 * DT, float(king.boss["cooldown_between"]))
	assert_float(em.lift_h[b]).is_equal(0.0)
	assert_int(g.shocks).is_equal(0)


func test_a_hero_out_of_the_radius_sees_the_waves_and_takes_nothing() -> void:
	var w := _world(Vector3(7.0, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	_begin(em, b, _attack_index(king, "stomp"))
	_fire(em, b)
	var t := 0.0
	while t < 8.0 and em._stomps.has(b):
		em._physics_process(DT)
		t += DT
	assert_int(em.stomp_lands).is_equal(3)
	assert_int((g.waves as Array).size()).is_equal(3)
	assert_int((hero.hits as Array).size()).is_equal(0)
	assert_int(em.stomp_hero_hits).is_equal(0)
	# walking in during the gap: the third one lands on him
	hero.global_position = Vector3(3, 0, 0)
	_begin(em, b, _attack_index(king, "stomp"))
	_fire(em, b)
	t = 0.0
	while t < 8.0 and em._stomps.has(b):
		em._physics_process(DT)
		t += DT
	assert_int((hero.hits as Array).size()).is_equal(3)


func test_the_kings_death_drops_the_run_and_the_old_slam_is_untouched() -> void:
	var w := _world(Vector3(3, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	_begin(em, b, _attack_index(king, "stomp"))
	_fire(em, b)
	em._physics_process(DT)
	em._physics_process(DT)
	assert_float(em.lift_h[b]).is_greater(0.0)
	em.damage(b, 1.0e7, "")
	em._physics_process(DT)
	assert_bool(em._stomps.has(b)).is_false()
	assert_int(em.stomp_lands).is_equal(0)
	# the slam script: one hit, the shockwave, at once (the Hammer Giant's, a custom slam's)
	var d := _test_def("t95_slammer", "tumbleweed_king")
	d.boss = {"attacks": [{"name": "slam", "windup": 1.2, "radius": 6.0, "damage": 30, "telegraph": "ring", "knockback": 6}], "cooldown_between": 2.0, "hp_mult_per_stage": 2.0}
	var s := em.spawn("t95_slammer", Vector3(0, 0, 0))
	hero.hits.clear()
	_begin(em, s, 0)
	_fire(em, s)
	assert_int((hero.hits as Array).size()).is_equal(1)
	assert_float(float((hero.hits[0] as Dictionary)["amount"])).is_equal_approx(30.0 * em.stage_mult * em.level_dmg_mult, 0.001)
	assert_int(g.shocks).is_equal(1)
	assert_int((g.waves as Array).size()).is_equal(0)
	assert_int(em.state[s]).is_equal(EnemyManager.STATE_MOVE)
	assert_bool(em._stomps.has(s)).is_false()


func test_the_stomp_numbers_read_their_row() -> void:
	var row := {"name": "stomp", "stomps": 2, "gap": 0.3, "jump": {"height": 1.0, "up": 0.2, "down": 0.1}}
	var j := EnemyManager.stomp_jump(row)
	assert_float(float(j["height"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(j["up"])).is_equal_approx(0.2, 0.0001)
	assert_float(float(j["down"])).is_equal_approx(0.1, 0.0001)
	assert_float(EnemyManager.stomp_hop_seconds(row)).is_equal_approx(0.3, 0.0001)
	assert_float(EnemyManager.stomp_period(row)).is_equal_approx(0.6, 0.0001)
	# the defaults without a jump: STOMP_JUMP
	var j0 := EnemyManager.stomp_jump({})
	assert_float(float(j0["height"])).is_equal_approx(2.2, 0.0001)
	assert_float(EnemyManager.stomp_period({})).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- 4. the tail sniper

## The Scorpion Elite with its tail sniper always chosen (chance 1: the roll never skips it in a test).
func _scorpion_def() -> EnemyDef:
	var d := _test_def("t95_scorp", "dune_scorpion")
	var attacks: Array = (Registry.enemy("dune_scorpion").boss["attacks"] as Array).duplicate(true)
	for a in attacks:
		if str((a as Dictionary).get("name", "")) == "tail_sniper":
			(a as Dictionary)["chance"] = 1.0
	d.boss = {"attacks": attacks, "cooldown_between": 4.5}
	return d


func test_the_tail_sniper_fires_three_beams_in_a_row_each_aimed_afresh() -> void:
	var w := _world(Vector3(14, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var d := _scorpion_def()
	var i := em.spawn(d.id, Vector3.ZERO)
	var ti := _attack_index(d, "tail_sniper")
	var row := _row(d, "tail_sniper")
	_begin(em, i, ti)
	# telegraph none: no mark; the wind-up is the stop
	assert_int((g.rings as Array).size()).is_equal(0)
	assert_int((g.lines as Array).size()).is_equal(0)
	assert_float(em.timer[i]).is_equal_approx(0.5 / em.pace, 0.001)
	_fire(em, i)
	# frozen, aiming: the Saiga's hold (STATE_WINDUP, the timer parked), the lines drawn by the sniper fx
	assert_bool(em._tails.has(i)).is_true()
	assert_int(em.tail_runs).is_equal(1)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)
	assert_float(em.timer[i]).is_equal(EnemyManager.SNIPER_HELD)
	assert_array(g.hints).contains(["tail_sniper"])
	em._physics_process(DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)
	assert_bool(em._sniper_fx != null and em._sniper_fx.busy()).is_true()
	assert_int(int(em._tails[i]["phase"])).is_equal(EnemyManager.TAIL_AIM)
	var times: Array = []
	var t := DT
	var moved := Vector3.ZERO
	var p0: Vector3 = em.pos[i]
	while t < 12.0 and em._tails.has(i):
		em._physics_process(DT)
		t += DT
		moved = em.pos[i] - p0
		if (hero.hits as Array).size() > times.size():
			times.append(t)
	assert_bool(em._tails.has(i)).is_false()
	# three beams, three hits, (aim + lock + gap) apart, from the tail (up the painting), it never moved
	assert_int(em.tail_shots).is_equal(3)
	assert_int(em.tail_hero_hits).is_equal(3)
	assert_int((hero.hits as Array).size()).is_equal(3)
	var period: float = (float(row["aim"]) + float(row["lock"]) + float(row["gap"])) / em.pace
	assert_float(float(times[1]) - float(times[0])).is_equal_approx(period, 5.0 * DT)
	assert_float(float(times[2]) - float(times[1])).is_equal_approx(period, 5.0 * DT)
	assert_float(float(times[0])).is_equal_approx((float(row["aim"]) + float(row["lock"])) / em.pace, 5.0 * DT)
	assert_float(moved.length()).is_less(0.01)
	var from: Vector3 = em.tail_last["from"]
	assert_float(from.y).is_greater(em.pos[i].y + 1.0)
	# every hit: twice the Saiga's base (the Vulture Raider's rocket x 0.7) x this creature's factors, a special push of 5
	var saiga_base: float = float(Registry.enemy("rocketeer").artillery["missile"]["damage"]) * float(Registry.enemy("saiga_sniper").sniper["beam"]["damage_mult"])
	assert_float(em.sniper_base_damage(Registry.enemy("saiga_sniper"))).is_equal_approx(saiga_base, 0.001)
	var want: float = saiga_base * 2.0 * em.stage_of(i) * em.lvd_of(i) * em.host_of(i)
	assert_float(want).is_equal_approx(em.tail_damage(i, row), 0.001)
	for h in hero.hits:
		assert_float(float((h as Dictionary)["amount"])).is_equal_approx(want, 0.001)
		var info: Dictionary = (h as Dictionary)["info"]
		assert_array(info["fx"]).contains(["tail beam"])
		assert_float(float(info["knock"])).is_equal_approx(float(row["beam"]["knockback"]), 0.001)
		assert_bool(bool(info["special_knock"])).is_true()
		assert_str(str(info["kind"])).is_equal("ranged")
		assert_bool(bool(info["elite"])).is_true()
	assert_float(float(em.tail_last["length"])).is_equal_approx(60.0, 0.001)
	# then the rest: walking again, the boss cooldown, its own charge held a beat
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[i]).is_between(4.5 - 2.0 * DT, 4.5)
	assert_float(em.cooldown[i]).is_greater_equal(EnemyManager.TAIL_CHARGE_REST - 0.001)
	assert_int(em.tail_cancels).is_equal(0)
	# the Saiga's own counters never moved
	assert_int(em.sniper_shots).is_equal(0)
	assert_bool(em._snipers.is_empty()).is_true()


func test_stepping_off_the_locked_line_dodges_that_beam_and_the_next_aims_afresh() -> void:
	var w := _world(Vector3(14, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var d := _scorpion_def()
	var i := em.spawn(d.id, Vector3.ZERO)
	_begin(em, i, _attack_index(d, "tail_sniper"))
	_fire(em, i)
	# the second shot's lock: he steps 3 m off the line, the beam misses; the third aims at where he stands and hits
	var stepped := false
	var t := 0.0
	while t < 12.0 and em._tails.has(i):
		em._physics_process(DT)
		t += DT
		if not stepped and em.tail_shots == 1 and int(em._tails[i]["phase"]) == EnemyManager.TAIL_LOCK:
			hero.global_position = Vector3(14, 0, 3)
			stepped = true
	assert_bool(stepped).is_true()
	assert_int(em.tail_shots).is_equal(3)
	assert_int((hero.hits as Array).size()).is_equal(2)
	var from: Vector3 = em.tail_last["from"]
	var dir: Vector3 = em.tail_last["dir"]
	assert_float(EnemyManager.beam_distance(hero.global_position, from, dir, 60.0)).is_less(0.3)


func test_a_stun_drops_the_tail_run_and_releases_the_pose() -> void:
	var w := _world(Vector3(14, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var d := _scorpion_def()
	var i := em.spawn(d.id, Vector3.ZERO)
	_begin(em, i, _attack_index(d, "tail_sniper"))
	_fire(em, i)
	em._physics_process(DT)
	em.stun_t[i] = 1.0
	em._physics_process(DT)
	assert_bool(em._tails.has(i)).is_false()
	assert_int(em.tail_cancels).is_equal(1)
	assert_int(em.tail_shots).is_equal(0)
	assert_int((hero.hits as Array).size()).is_equal(0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[i]).is_between(4.5 - 2.0 * DT, 4.5)


func test_the_beam_nicks_and_pushes_the_crowd_on_its_line() -> void:
	var w := _world(Vector3(14, 0, 0))
	var em: EnemyManager = w["em"]
	var d := _scorpion_def()
	var i := em.spawn(d.id, Vector3.ZERO)
	# a goblin on the line past the hero, one well off it
	var on := em.spawn("goblin", Vector3(20, 0, 0.2))
	var off := em.spawn("goblin", Vector3(20, 0, 6))
	em.speed[on] = 0.0
	em.speed[off] = 0.0
	var hp_on: float = em.hp[on]
	var hp_off: float = em.hp[off]
	_begin(em, i, _attack_index(d, "tail_sniper"))
	_fire(em, i)
	var t := 0.0
	while t < 4.0 and em.tail_shots < 1:
		em._physics_process(DT)
		t += DT
	assert_int(em.tail_shots).is_equal(1)
	var row := _row(d, "tail_sniper")
	assert_float(hp_on - em.hp[on]).is_equal_approx(minf(em.max_hp[on] * float(row["beam"]["creature_frac"]), float(row["beam"]["creature_max"])), 0.01)
	assert_float(em.hp[off]).is_equal_approx(hp_off, 0.001)
	assert_float((em.kb[on] as Vector3).length()).is_greater(0.0)


func test_chance_skips_an_attack_when_its_roll_misses() -> void:
	var w := _world(Vector3(4, 0, 0))
	var em: EnemyManager = w["em"]
	assert_bool(em._attack_chance_misses({})).is_false()
	assert_bool(em._attack_chance_misses({"chance": 1.0})).is_false()
	assert_bool(em._attack_chance_misses({"chance": 0.0})).is_true()
	var hits := 0
	for k in range(400):
		if em._attack_chance_misses({"chance": 0.7}):
			hits += 1
	# about 30 in 100 skipped
	assert_int(hits).is_between(80, 160)
	# the runner: a slam that never rolls in gives way to the next attack
	var d := _test_def("t95_chancer", "tumbleweed_king")
	d.boss = {"attacks": [{"name": "slam", "windup": 1.0, "radius": 6.0, "damage": 30, "telegraph": "ring", "chance": 0.0},
		{"name": "slam_at", "windup": 1.0, "radius": 2.6, "damage": 18, "telegraph": "ring_at_hero"}], "cooldown_between": 2.0}
	var s := em.spawn("t95_chancer", Vector3.ZERO)
	_begin(em, s, 0)
	# the attack chosen is the second (atk_i points past it)
	assert_int(em.atk_i[s]).is_equal(2)
	# the Scorpion's row is skipped inside 5 m too (min_range), its own numbers
	var sc: EnemyDef = Registry.enemy("dune_scorpion")
	assert_bool(em._attack_out_of_range(_row(sc, "tail_sniper"), 4.0)).is_true()
	assert_bool(em._attack_out_of_range(_row(sc, "tail_sniper"), 6.0)).is_false()
