extends GdUnitTestSuite

## Pass 69, lane EN (Garry, 2026-10-12: "Let's increase the power of 'Special' enemies a bit. And change the visuals for
## them ... about 3 times more rare ... 1.25 times bigger ... HP x10 ... ATK x2 ... The visual change (the colouring of
## special enemies) should be possible in the Level Editor ... There should be a moment ... where a single 'Special'
## regular Goblin appears at the end of the first wave"; "The beam of light that accompanies Player hero when they
## descend down gets cut off at the bottom ... just fade out the effect before it reaches the ground"). Every creature's
## special numbers; EnemyDef.special_value's fallbacks (the creature's own, the map's special_defaults, the game's);
## the glow read off the creature and drawn as the shader's rim code; the forced special (a swarm event with "special":
## true) spawns once at its second, x10 HP, x2 ATK, x1.25 size, before colour_after_kills, with no SWARM! banner; the
## spawn beam's fade above the sand.

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
var director = null
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
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
	return Vector3.FORWARD
"""

const FAKE_PICKUPS := """extends Node
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(_at, _boss = false) -> void:
	pass
func spawn(_k, _at, _v = 0.0) -> int:
	return -1
"""

## special_chance before pass 69 (the content as it stood); every one is a third of it since pass 69, and a third of that
## again since pass 110 (lane ECON; Garry: "reduce the number of Specials"): a ninth, to 4 decimals.
const OLD_CHANCE := {"armadillo": 0.06, "blue_slime": 0.1, "buckshot_dwarf": 0.05, "bull_beetle": 0.08,
	"dust_mummy": 0.08, "fire_ant": 0.1, "goblin": 0.12, "goblin_runt": 0.1, "hellhound": 0.08, "hobgoblin": 0.1,
	"horned_toad": 0.08, "imp": 0.1, "jackalope": 0.1, "red_goblin": 0.12, "red_goblin_runt": 0.1, "sand_crab": 0.08,
	"sand_lizard": 0.1, "skeleton": 0.12, "skeleton_knight": 0.1, "spit_cactus": 0.1, "tumbleweed_minion": 0.1}

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
	var mb := MapBase.new()
	g.add_child(mb)
	g.set("map", mb)
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.set("pickups", pk)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "map": mb}


## A test creature `id` made from `from` with no size jitter, its variance block `vr`; gone after the test.
func _test_def(id: String, from: String, vr: Dictionary) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = vr
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# ---------------------------------------------------------------- 1. the numbers

func test_every_creature_special_is_rarer_bigger_tougher_and_harder() -> void:
	var seen := 0
	for id: String in OLD_CHANCE.keys():
		var d := _json("res://content/enemies/%s/%s.json" % [id, id])
		var vr: Dictionary = d["variance"]
		assert_float(float(vr["special_chance"])).override_failure_message(id + " chance").is_equal_approx(snappedf(float(OLD_CHANCE[id]) / 9.0, 0.0001), 0.00001)
		var sp: Dictionary = vr["special"]
		# (pass 72, lane SPEC, re-pinned: Garry's "bigger ... higher HP": x1.5 and x15 since pass 72)
		assert_float(float(sp["size"])).override_failure_message(id + " size").is_equal(1.5)
		assert_float(float(sp["hp"])).override_failure_message(id + " hp").is_equal(15.0)
		# (pass 110, lane ECON, re-pinned: Garry's "Increase ATK of Specials quite a bit": x3.5, was x2)
		assert_float(float(sp["damage"])).override_failure_message(id + " damage").is_equal(3.5)
		# the XP stays as it was (3 on every one of them)
		assert_float(float(sp["xp"])).override_failure_message(id + " xp").is_equal(3.0)
		# and the .tres the game plays says the same
		var def: EnemyDef = Registry.enemy(id)
		assert_float(float(def.variance["special_chance"])).is_equal_approx(float(vr["special_chance"]), 0.00001)
		assert_float(float((def.variance["special"] as Dictionary)["hp"])).is_equal(15.0)
		seen += 1
	assert_int(seen).is_equal(21)
	# a creature made since (pass 91: Garry's Cactus Walker, from the Level Editor) with a special chance carries a
	# special block of its own (re-pinned: the table holds pass 69's creatures only)
	for def: EnemyDef in Registry.enemies.values():
		if float(def.variance.get("special_chance", 0.0)) > 0.0 and not OLD_CHANCE.has(def.id):
			assert_bool(def.variance.get("special") is Dictionary).override_failure_message(def.id + " has a special chance and no special block").is_true()
	# the shaman's block (chance 0) carries the new numbers too, for the day it is turned on
	var sh: Dictionary = _json("res://content/enemies/dust_shaman/dust_shaman.json")["variance"]["special"]
	assert_float(float(sh["hp"])).is_equal(15.0)


func test_special_value_falls_back_from_the_creature_to_the_map_to_the_game() -> void:
	# (pass 72, lane SPEC, re-pinned: the game's 1.5 and 15 since pass 72)
	assert_float(EnemyDef.special_value({}, {}, "size")).is_equal(1.5)
	assert_float(EnemyDef.special_value({}, {}, "hp")).is_equal(15.0)
	assert_float(EnemyDef.special_value({}, {}, "damage")).is_equal(2.0)
	assert_float(EnemyDef.special_value({}, {}, "xp")).is_equal(2.0)
	assert_float(EnemyDef.special_value({}, {}, "tint_strength")).is_equal(0.6)
	assert_float(EnemyDef.special_value({}, {}, "glow")).is_equal(0.6)
	assert_float(EnemyDef.special_value({}, {"glow": 0.9, "hp": 7.0}, "glow")).is_equal(0.9)
	assert_float(EnemyDef.special_value({"glow": 0.2}, {"glow": 0.9}, "glow")).is_equal(0.2)
	assert_float(EnemyDef.special_value({"hp": 4}, {"hp": 7.0}, "hp")).is_equal(4.0)
	assert_float(EnemyDef.special_value({}, {"hp": 7.0}, "hp")).is_equal(7.0)


func test_a_special_is_x10_hp_x2_atk_x125_size_and_glows() -> void:
	var vr := {"size": 0.3, "speed": 0.0, "tints": [], "special_chance": 1.0,
		"special": {"size": 1.25, "hp": 10.0, "damage": 2.0, "xp": 3.0, "tint": "#8A1428", "tint_strength": 0.6}}
	var sp := _test_def("p69_sp", "skeleton", vr)
	var plain_vr := vr.duplicate(true)
	plain_vr["special_chance"] = 0.0
	var pl := _test_def("p69_pl", "skeleton", plain_vr)
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 0
	var i := em.spawn(sp.id, Vector3(0, 0, 0))
	var j := em.spawn(pl.id, Vector3(4, 0, 0))
	assert_int(em.vspecial[i]).is_equal(1)
	assert_int(em.vspecial[j]).is_equal(0)
	assert_float(em.max_hp[i] / em.max_hp[j]).is_equal_approx(10.0, 0.0001)
	assert_float(em.dmg[i] / em.dmg[j]).is_equal_approx(2.0, 0.0001)
	# exactly 1.25 times the creature's size and body, whatever the plain ones' spread (0.3 here) rolls
	assert_float(em.size[i] / sp.size).is_equal_approx(1.25, 0.0001)
	assert_float(em.radius[i] / sp.radius).is_equal_approx(1.25, 0.0001)
	assert_float(em.size[j] / pl.size).is_between(0.6999, 1.3001)
	assert_float(em.xp_scale[i] / em.xp_scale[j]).is_equal_approx(3.0, 0.0001)
	# the glow: the game's 0.6 when neither the creature nor the map names one; nobody else glows
	assert_float(em.vglow[i]).is_equal_approx(0.6, 0.0001)
	assert_float(em.vglow[j]).is_equal(0.0)
	# its tint is the special's own, at its strength
	assert_str(Color(em.vtint[i].r, em.vtint[i].g, em.vtint[i].b).to_html(false)).is_equal("8a1428")
	assert_float(em.vtint[i].a).is_equal_approx(0.6, 0.0001)
	# a freed one forgets it
	em._free(i)
	assert_float(em.vglow[i]).is_equal(0.0)


func test_the_glow_is_the_creatures_or_the_maps_and_reaches_the_shader() -> void:
	var own := _test_def("p69_own", "skeleton", {"special_chance": 1.0, "special": {"glow": 0.25, "hp": 10.0, "tint": "#1A4A7A"}})
	var bare := _test_def("p69_bare", "skeleton", {"special_chance": 1.0, "special": {"tint": "#1A4A7A"}})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 0
	em.special_defaults = {"glow": 0.9, "hp": 4.0}
	var a := em.spawn(own.id, Vector3(0, 0, 0))
	var b := em.spawn(bare.id, Vector3(5, 0, 0))
	assert_float(em.vglow[a]).is_equal_approx(0.25, 0.0001)
	assert_float(em.vglow[b]).is_equal_approx(0.9, 0.0001)
	# the map's hp default reaches a creature whose block names none (the test creature's base hp, no jitter, no curve)
	assert_float(em.max_hp[b] / em.max_hp[a]).is_equal_approx(4.0 / 10.0, 0.0001)
	# out of range is clamped
	em.special_defaults = {"glow": 3.0}
	var c := em.spawn(bare.id, Vector3(-5, 0, 0))
	assert_float(em.vglow[c]).is_equal(1.0)
	# the code on the flip channel: 16 levels in steps of 64, above the flip bit and the tether's 2 x 16
	assert_float(EnemyManager.special_glow_code(0.6)).is_equal(64.0 * 10.0)
	assert_float(EnemyManager.special_glow_code(0.0)).is_equal(0.0)
	assert_float(EnemyManager.special_glow_code(1.0)).is_equal(1024.0)
	# what the render writes (the headless renderer keeps no instance data to read back, so the sum is checked as the
	# shader decodes it): flip 1 + the tether's level 9 + the special's 0.6, and each comes back whole
	var y := 1.0 + 2.0 * 9.0 + EnemyManager.special_glow_code(0.6)
	var sg := floorf(y / 64.0)
	var rest := y - sg * 64.0
	assert_float(sg / 16.0).is_equal_approx(0.625, 0.0001)
	assert_float(fmod(rest, 2.0)).is_equal(1.0)
	assert_float(floorf(rest * 0.5)).is_equal(9.0)
	var ems := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	assert_str(ems).contains("if vglow[i] > 0.0 and st != STATE_DYING:")
	assert_str(ems).contains("fy += special_glow_code(vglow[i])")
	# the shaders read it that way (enemy_silhouette's mod(y, 2) is still the flip)
	var src := FileAccess.get_file_as_string("res://core/shaders/enemy_billboard.gdshader")
	assert_str(src).contains("floor(INSTANCE_CUSTOM.y / 64.0)")
	assert_str(src).contains("v_sglow")
	var sil := FileAccess.get_file_as_string("res://core/shaders/enemy_silhouette.gdshader")
	assert_str(sil).contains("mod(INSTANCE_CUSTOM.y, 2.0)")


# ---------------------------------------------------------------- 2. the special Goblin moment

## The map's forced-special events (read from the file: Garry may move it in the Level Editor).
func _special_events() -> Array:
	var tl: Dictionary = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"]
	# pass 84 (lane SPAWN, re-pinned): the special Goblin is a "once" row with `special` now (an old map's event still counts)
	var out: Array = (tl["events"] as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("special", false)))
	out.append_array((tl["roster"] as Array).filter(func(r: Dictionary) -> bool: return bool(r.get("special", false)) and str(r.get("pace", "")) == "once"))
	return out


## The director's events and its rows' waves (an event or a once row), at the clock as it stands.
func _tick(d: WaveDirector) -> void:
	d._process_events()
	d._tick_row_waves()


func test_red_canyon_has_one_special_goblin_at_the_end_of_the_first_wave() -> void:
	var evs := _special_events()
	assert_int(evs.size()).is_equal(1)
	var ev: Dictionary = evs[0]
	assert_bool(str(ev.get("type", "")) == "swarm" or str(ev.get("pace", "")) == "once").is_true()
	assert_str(str(ev["enemy"])).is_equal("red_goblin")
	assert_int(int(ev["count"])).is_equal(1)
	# (pass 72, lane SPEC, re-pinned: Garry rebuilt stage 1 in the Level Editor (the red goblins' row now 2:03-4:05, a
	# scorpion row from 0:00) and kept the special Goblin at 2:00; where it stands is his to drag, so only that it comes
	# in the first stage is pinned, read from the file)
	var tl: Dictionary = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"]
	assert_float(float(ev["t"])).is_greater_equal(0.0)
	assert_float(float(ev["t"])).is_less_equal(float(tl.get("stage_length", 430.0)))
	# the .tres the game plays carries it
	var played: Array = Registry.map("red_canyon").timeline.events.filter(func(e: Dictionary) -> bool: return bool(e.get("special", false)))
	played.append_array(Registry.map("red_canyon").timeline.roster.filter(func(r: Dictionary) -> bool: return bool(r.get("special", false)) and str(r.get("pace", "")) == "once"))
	assert_int(played.size()).is_equal(1)


func test_the_forced_special_spawns_once_at_its_second_x10_x2_x125_without_a_banner() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var real: WaveTimeline = Registry.map("red_canyon").timeline
	var ev: Dictionary = (_special_events()[0] as Dictionary).duplicate(true)
	var at := float(ev["t"])
	var tl: WaveTimeline = real.duplicate(true)
	if ev.has("pace"):
		tl.roster = [ev]
		tl.events = []
	else:
		tl.events = [ev]
	tl.waves = []
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = g
	d.map = Registry.map("red_canyon")
	d.timeline = tl
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	g.set("director", d)
	# colour is a long way off: a forced special comes anyway
	em.colour_after_kills = 50
	Run.kills = 0
	d._apply_mults()
	em.colour_after_kills = 50
	Run.elapsed = at - 1.0
	_tick(d)
	assert_int(em.count_alive).is_equal(0)
	Run.elapsed = at
	d._apply_mults()
	em.colour_after_kills = 50
	_tick(d)
	assert_int(em.count_alive).is_equal(1)
	var i := -1
	for k in range(EnemyManager.MAX):
		if em.alive[k] == 1:
			i = k
	assert_int(em.vspecial[i]).is_equal(1)
	assert_float(em.vglow[i]).is_greater(0.0)
	var def: EnemyDef = em.types[em.type_idx[i]]["def"]
	assert_str(def.id).is_equal("red_goblin")
	# x10 HP and x2 ATK over the same creature's plain numbers (its row's fixed ones, kept in f_*)
	var plain_hp := def.hp * em.f_stage[i] * em.f_hpt[i] * em.f_lvh[i] * em.creature_hp_mult
	var plain_dmg := def.damage * em.f_stage[i] * em.f_lvd[i] * em.creature_damage_mult * em.f_dmt[i]
	# (pass 72, lane SPEC, re-pinned: x15 and x1.5 since pass 72, the creature's own block)
	assert_float(em.max_hp[i] / plain_hp).is_equal_approx(15.0, 0.001)
	# (pass 110, lane ECON, re-pinned: x3.5 ATK, the creature's own block)
	assert_float(em.dmg[i] / plain_dmg).is_equal_approx(3.5, 0.001)
	# exactly x1.25 the creature's size: a special drops the plain ones' spread (red goblins roll 0.8-1.2 of theirs)
	assert_float(float(def.variance.get("size", 0.0))).is_greater(0.0)
	assert_float(em.size[i] / def.size).is_equal_approx(1.5, 0.0001)
	# no SWARM! banner for it; the force is let go
	assert_bool((g.get("toasts") as Array).has("SWARM!")).is_false()
	assert_bool(em.force_special).is_false()
	# once: a second later nothing more comes
	Run.elapsed = at + 1.0
	_tick(d)
	assert_int(em.count_alive).is_equal(1)
	# and the same event without the flag is a plain swarm again: no special, a banner
	var plain_ev := {"t": at, "type": "swarm", "enemy": ev["enemy"], "variant": ev.get("variant", ""), "count": 3,
		"pattern": ev.get("pattern", "in_front")}
	em.kill_all(false)
	d._run_event(plain_ev)
	var specials := 0
	for k in range(EnemyManager.MAX):
		if em.alive[k] == 1 and em.state[k] != EnemyManager.STATE_DYING:
			specials += em.vspecial[k]
	assert_int(specials).is_equal(0)
	assert_bool((g.get("toasts") as Array).has("SWARM!")).is_true()


func test_the_map_special_defaults_reach_the_crowd() -> void:
	var tl := WaveTimeline.new()
	tl.special_defaults = {"glow": 0.8}
	var w := _world()
	var em: EnemyManager = w["em"]
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = tl
	d._apply_mults()
	assert_float(float(em.special_defaults["glow"])).is_equal(0.8)
	# and JsonContent reads the key off the map's timeline_data ({} when absent or not a block)
	assert_float(float(JsonContent.timeline_from_dict({"special_defaults": {"hp": 6}}).special_defaults["hp"])).is_equal(6.0)
	assert_bool(JsonContent.timeline_from_dict({}).special_defaults.is_empty()).is_true()
	assert_bool(JsonContent.timeline_from_dict({"special_defaults": 3}).special_defaults.is_empty()).is_true()


# ---------------------------------------------------------------- 3. the spawn beam

func test_the_spawn_beam_fades_out_above_the_sand() -> void:
	var f := Game.spawn_beam_fade_y(2.0)
	assert_float(f.x).is_equal_approx(2.0 + Game.SPAWN_BEAM_FADE_GAP, 0.0001)
	assert_float(f.y).is_equal_approx(2.0 + Game.SPAWN_BEAM_FADE_GAP + Game.SPAWN_BEAM_FADE, 0.0001)
	assert_float(f.x).is_greater(2.0)
	assert_float(f.y - f.x).is_greater_equal(2.0)
	# the shader fades mode 1 by it, off by default (the chest's beam stands on the chest)
	var src := FileAccess.get_file_as_string("res://core/shaders/shine_aura.gdshader")
	assert_str(src).contains("uniform vec2 fade_y = vec2(0.0, 0.0);")
	assert_str(src).contains("a *= smoothstep(fade_y.x, fade_y.y, v_wy);")
	var q := Chest.shine_quad(1, Vector2(2.6, 34.0), Color(1, 1, 1), 1.0)
	var fy = (q.material_override as ShaderMaterial).get_shader_parameter("fade_y")
	assert_bool(fy == null or (fy as Vector2) == Vector2.ZERO).is_true()
	q.free()
	# the launch sets it on both beam quads (its own hook in _spawn_begin)
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game_src).contains("_spawn_beam_fade(q, away)")
