extends GdUnitTestSuite

## Pass 48, Phase 0 (the groundwork the five lanes build on): weapons at five levels with the level-8 power kept at level
## 5, priority targeting in the data, the eighteen hidden mutations and the seventeen that took their slots, Both Barrels
## everyone's, the seven new evolutions (the old ones hidden; Golden Revolver's and Earthshaker's old JSON kept as _v47),
## the four rarity changes, the timeline's pace knob and portal wave, the dummy settings, the new player stats; the run's
## path_progress and its every-mutation evolution rule, the Stranger's levels, Phoenix Feather's once-a-run revive; the
## creatures paced and their shots on hostile_clock, hamper and attack_clock, held status tints, priority_index, the spawn
## serial, damage records capped at what a creature had, mini crits, undying dummies and the dummy brain, blue fire, a
## dying creature telling what it carried; plate colours by level.

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
var lines: Array = []
var ignites: Array = []
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
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, blue = false) -> void:
	ignites.append(bool(blue))
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, c, d, _e) -> void:
	lines.append({"length": float(c), "dur": float(d)})
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
var hits := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
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

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

## a stand-in for the HUD's numbers: it only writes down what it was handed
const FAKE_NUMBERS := """extends DamageNumbers
var calls: Array = []
func add(i: int, at: Vector3, amount: float, crit: bool = false, green: bool = false, hot: bool = false, mini: bool = false) -> void:
	calls.append({"i": i, "amount": amount, "crit": crit, "mini": mini})
"""

const DT := 1.0 / 60.0

## Old level-8 totals of a few weapons as their sheets folded them (from tools/dl/levels_v47.json, the frozen copy
## tools/compress_levels.py made before it rewrote the levels): level 5 keeps every one.
const OLD_L8 := {
	"boomstick": {"amount": 8.0, "damage": 9.36, "cooldown": 1.26, "knockback": 10.0, "pierce": 1.0},
	"peashooter": {"damage": 14.976, "amount": 3.0, "cooldown": 0.81, "pierce": 1.0},
	"tommy_gun": {"amount": 12.0, "damage": 6.09375, "cooldown": 1.232},
	"hammer": {"damage": 31.25, "area": 1.38, "range": 6.348, "amount": 3.0},
	"molotov": {"fire_damage": 5.76, "area": 2.645, "cooldown": 2.112, "fire_spread": 0.6, "fire_duration": 2.4},
	"turret_buddy": {"damage": 8.125, "lifetime": 20.0, "cooldown": 5.0, "amount": 2.0},
	"guitarra": {"damage": 28.4375, "cooldown": 1.1088, "range": 8.0},
	"land_mine": {"damage": 56.875, "cooldown": 1.8785, "area": 2.88, "amount": 2.0},
}

const HIDDEN := ["slug", "birdshot", "bar_fight", "pea_hose", "bone_storm", "homing_skulls", "tracer_rounds", "toxic_toss",
	"ember_chord", "venom_rounds", "six_shooter", "molten_hammer", "hammer_rain", "ember_hornets", "swarm", "napalm_mine",
	"cluster_mines", "incendiary",
	# pass 53 (lane W1): the Rocket Pod's, the Turret Buddy's and the Zap Beam's old picks, hidden in place
	"thermobaric", "salvo", "bunker_buster", "dart_buddy", "venom_arc",
	# pass 53 (lane W2): the Sabre's, the Spear's and the Tumbleweed's old picks, hidden in place
	"flame_blade", "venom_tip", "phalanx", "thorny_weed", "weed_storm"]

## the new mutations: [weapon, the slot (kind) they fill]
const NEW_MUTATIONS := {
	"birdshot_lane": ["boomstick", "volume"], "methanol": ["molotov", "volume"], "big_peas": ["peashooter", "volume"],
	"bouncing_skull": ["skull_rain", "motion"], "curare": ["skull_rain", "volume"], "mini_crits": ["tommy_gun", "element"],
	"repulsor": ["gravity_gun", "element"], "tinnitus": ["guitarra", "element"], "silver_bullet": ["revolver", "element"],
	"hip_shot": ["revolver", "volume"], "thors_wrath": ["hammer", "element"], "giant_slayer": ["hammer", "volume"],
	"pollen": ["hornet_nest", "element"], "tarantula_hawk": ["hornet_nest", "volume"], "wide_reach": ["land_mine", "element"],
	"extra_supply": ["land_mine", "volume"], "new_equipment": ["lob_grenade", "element"],
}

## base weapon -> [its new evolution, the old one now hidden]
const NEW_EVOLUTIONS := {
	"boomstick": ["blunderbuss", "doomstick"], "molotov": ["moonshine", "firestorm"], "peashooter": ["pea_cannon", "bullet_hose"],
	"skull_rain": ["grave_hail", "dia_de_muertos"], "hornet_nest": ["hive_queen", "killer_swarm"],
	"land_mine": ["jackrabbit_mines", "minefield"], "lob_grenade": ["golden_pineapple", "cluster_bomb"],
}

const PRIORITY := ["peashooter", "revolver", "tommy_gun", "tumbleweed", "pike", "sabre", "turret_buddy", "hornet_nest",
	"bullet_hose", "golden_revolver", "chicago_typewriter", "stampede", "halberd", "zweihander", "turret_family",
	"killer_swarm", "pea_cannon", "hive_queen"]

var _added: Array = []
var _pace_keep := 1.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	_pace_keep = Run.map.timeline.move_pace


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	var m: MapDef = Registry.map("red_canyon")
	if m and m.timeline:
		m.timeline.move_pace = _pace_keep
	DamageNumbers.I = null


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd, shots and effects.
func _world(hero_at := Vector3(30, 0, 30)) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


## A creature on its feet where it was put.
func _creature(em: EnemyManager, at: Vector3, id := "skeleton", hp_mult := 50.0) -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


## A test creature (`id`) made from `from` with another brain, no variance, and the given fields; gone after the test.
func _test_def(id: String, from: String, brain: String, fields: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.brain = brain
	d.variance = {}
	for k: String in fields.keys():
		d.set(k, fields[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


# ---------------------------------------------------------------- the content

func test_weapons_have_five_levels_with_the_old_top_power() -> void:
	for w: WeaponDef in Registry.base_weapons():
		assert_int(w.max_level).override_failure_message(w.id).is_equal(5)
		assert_int(w.levels.size()).override_failure_message(w.id).is_equal(5)
		assert_bool((w.levels[0] as Array).is_empty()).override_failure_message(w.id).is_true()
	for id: String in OLD_L8.keys():
		var inst := WeaponInstance.new(Registry.weapon(id), 5)
		inst.rebuild(StatSheet.new(), [inst])
		var want: Dictionary = OLD_L8[id]
		for st: String in want.keys():
			assert_float(inst.stat(st)).override_failure_message("%s %s" % [id, st]).is_equal_approx(float(want[st]), 0.0005)
		# and nothing past five
		assert_int(WeaponInstance.new(Registry.weapon(id), 8).level).is_equal(5)
	# the Loudmouth (an evolution that carried eight levels by mistake) has its one
	var lm: WeaponDef = Registry.weapon("loudmouth")
	assert_int(lm.max_level).is_equal(1)
	assert_int(lm.levels.size()).is_equal(1)
	# the favourites start at level 2 of five (the Drifter's was 3 of eight)
	assert_int(int(Registry.character("drifter").favourite_bonus.get("value", 0))).is_equal(2)
	assert_int(int(Registry.character("calavera").favourite_bonus.get("value", 0))).is_equal(2)


func test_priority_targeting_is_in_the_data_and_the_words() -> void:
	for id: String in PRIORITY:
		assert_str(Registry.weapon(id).targeting).override_failure_message(id).is_equal("priority")
	# the area weapons keep theirs
	assert_str(Registry.weapon("boomstick").targeting).is_equal("forward")
	assert_str(Registry.weapon("hammer").targeting).is_equal("densest")
	for id in ["peashooter", "sabre", "turret_buddy", "hornet_nest"]:
		var inst := WeaponInstance.new(Registry.weapon(id), 1)
		inst.rebuild(StatSheet.new(), [inst])
		assert_str(inst.description()).override_failure_message(id).contains(TextGen.PRIORITY_WHO)
		# its pause rows still build (an unknown targeting reads as nearest everywhere it is read)
		assert_bool(inst.stat_rows().is_empty()).override_failure_message(id).is_false()
	var boom := WeaponInstance.new(Registry.weapon("boomstick"), 1)
	boom.rebuild(StatSheet.new(), [boom])
	assert_str(boom.description()).not_contains(TextGen.PRIORITY_WHO)


func test_hidden_mutations_are_out_of_play_and_kept() -> void:
	for id: String in HIDDEN:
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id + " is gone").is_not_null()
		assert_bool(m.hidden).override_failure_message(id).is_true()
		assert_bool(Registry.mutations_of(m.weapon).has(m)).override_failure_message(id + " is on the path").is_false()
	# never taken by a pick; only by force (the debug hand)
	var boom := Run.add_weapon(Registry.weapon("boomstick"), 3)
	assert_bool(Run.add_mutation("slug")).is_false()
	assert_bool(boom.has_mutation("slug")).is_false()
	assert_bool(Run.add_mutation("slug", true)).is_true()
	Run.stage = 1
	for m: MutationDef in Run.open_mutations(boom):
		assert_bool(m.hidden).override_failure_message(m.id + " offered").is_false()
	for m: MutationDef in Run.boss_chest_mutations():
		assert_bool(m.hidden).override_failure_message(m.id + " in a boss chest").is_false()


func test_every_weapon_in_play_has_one_element_volume_and_motion() -> void:
	for w: WeaponDef in Registry.base_weapons():
		if w.hidden:
			continue
		var kinds: Array = Registry.mutations_of(w.id).map(func(m: MutationDef) -> String: return m.mutation_kind)
		assert_array(kinds).override_failure_message(w.id + " " + str(kinds)).is_equal(["element", "volume", "motion"])
	for id: String in NEW_MUTATIONS.keys():
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id).is_not_null()
		assert_str(m.weapon).override_failure_message(id).is_equal(str(NEW_MUTATIONS[id][0]))
		assert_str(m.mutation_kind).override_failure_message(id).is_equal(str(NEW_MUTATIONS[id][1]))
		assert_str(m.rarity).is_equal("rare")
		assert_float(m.weight).is_equal(8.0)
		assert_str(m.text).override_failure_message(id + " says nothing").is_not_empty()
		assert_bool(m.has_icon()).override_failure_message(id + " has no icon").is_true()
		assert_bool(m.params.is_empty()).override_failure_message(id + " has no params").is_false()
		assert_bool(m.hidden or m.is_hero()).is_false()
	# the numbers the lanes read are data
	assert_bool(bool(Registry.mutation("methanol").params.get("fire_blue", false))).is_true()
	assert_float(float(Registry.mutation("mini_crits").params.get("mini_crit", 0.0))).is_equal_approx(0.25, 0.0001)
	assert_int(Registry.mutation("silver_bullet").effects.size()).is_equal(2)


func test_both_barrels_is_every_heros_motion_pick() -> void:
	var bb: MutationDef = Registry.mutation("both_barrels")
	assert_str(bb.mutation_kind).is_equal("motion")
	assert_bool(bb.is_hero()).is_false()
	assert_int(int(bb.params.get("double_every", 0))).is_equal(3)
	assert_str(bb.text).starts_with("Every third shot fires twice")
	assert_bool(Registry.mutations_of("boomstick").has(bb)).is_true()
	for hero in ["astro", "drifter", "calavera"]:
		Run.start(Registry.character(hero), Registry.map("red_canyon"))
		var w := Run.add_weapon(Registry.weapon("boomstick"), 1)
		var ids: Array = Run.open_mutations(w).map(func(m: MutationDef) -> String: return m.id)
		assert_bool(ids.has("both_barrels")).override_failure_message(hero).is_true()


func test_the_evolution_needs_the_whole_path() -> void:
	# pass 76 (lane DYN): the Drifter's favourite and his own mutation moved to the dynamite (the Lob Grenade and Fire in
	# the Hole; the Peashooter and Fan the Hammer are hidden): the same walk down its path
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var w := Run.add_weapon(Registry.weapon("lob_grenade"), 5)
	assert_bool(Run.path_progress(w) == Vector2i(0, 3)).override_failure_message(str(Run.path_progress(w))).is_true()
	assert_bool(Run.path_progress(null) == Vector2i.ZERO).is_true()
	# the hero's own option is the stage's pick but no step down the path
	assert_bool(Run.add_mutation("fire_in_the_hole")).is_true()
	assert_bool(Run.path_progress(w) == Vector2i(0, 3)).is_true()
	Run.stage = 1
	Run.add_mutation("new_equipment")
	Run.stage = 2
	Run.add_mutation("frag")
	assert_bool(Run.path_progress(w) == Vector2i(2, 3)).is_true()
	assert_bool(Run.evolution_ready(w)).is_false()
	assert_str(Run.evolution_status(w)).contains("2/3 mutations")
	Run.stage = 3
	Run.add_mutation("sticky")
	assert_bool(Run.path_progress(w) == Vector2i(3, 3)).is_true()
	assert_bool(Run.evolution_ready(w)).is_true()
	assert_str(Run.evolution_status(w)).contains("3/3 mutations")
	var r := Run.chest_roll()
	assert_str(str(r["type"])).is_equal("evolution")
	assert_str(str(r["id"])).is_equal("golden_pineapple")
	Run.chest_take(r)
	var evo := Run.weapon_instance("golden_pineapple")
	assert_object(evo).is_not_null()
	assert_str(evo.def.targeting).is_equal("densest")
	assert_int(evo.mutations.size()).is_equal(4)
	# not at the top level: not ready, whatever it carries
	var sab := Run.add_weapon(Registry.weapon("sabre"), 4)
	for id in ["critical_thinking", "flurry", "riposte"]:   # pass 53 (lane W2): Critical Thinking took Flame Blade's slot
		Run.add_mutation(id, true)
	assert_bool(Run.evolution_ready(sab)).is_false()
	Run.level_weapon("sabre")
	assert_bool(Run.evolution_ready(sab)).is_true()


func test_the_new_evolutions_replace_the_old() -> void:
	for base: String in NEW_EVOLUTIONS.keys():
		var b: WeaponDef = Registry.weapon(base)
		var new_id: String = NEW_EVOLUTIONS[base][0]
		var old_id: String = NEW_EVOLUTIONS[base][1]
		assert_str(b.evolves_into).override_failure_message(base).is_equal(new_id)
		var evo: WeaponDef = Registry.weapon(new_id)
		assert_object(evo).override_failure_message(new_id).is_not_null()
		assert_bool(evo.is_evolution).is_true()
		assert_str(evo.evolved_from).is_equal(base)
		assert_int(evo.max_level).is_equal(1)
		# pass 76 (lane DYN): an evolution is out of play exactly when its weapon is (the Peashooter is hidden, so is the
		# Pea Cannon)
		assert_bool(Registry.is_hidden(evo)).override_failure_message(new_id + " hidden").is_equal(b.hidden)
		assert_object(evo.visual).override_failure_message(new_id + " has no visual").is_not_null()
		assert_bool(evo.has_icon()).override_failure_message(new_id + " has no icon").is_true()
		var old: WeaponDef = Registry.weapon(old_id)
		assert_bool(old.hidden).override_failure_message(old_id + " shows").is_true()
		assert_bool(Registry.is_hidden(old)).is_true()
		# it plays as the old one did until its lane rebuilds it
		assert_str(evo.behavior).is_equal(old.behavior)
	# Golden Revolver and Earthshaker keep their ids; their old JSON is kept aside, hidden
	for id in ["golden_revolver", "earthshaker"]:
		var keep: WeaponDef = Registry.weapon(id)
		assert_bool(keep.hidden).is_false()
		var v47: WeaponDef = Registry.weapon(id + "_v47")
		assert_object(v47).is_not_null()
		assert_bool(v47.hidden).is_true()
		assert_str(v47.evolved_from).is_equal(keep.evolved_from)
		assert_object(v47.visual).is_not_null()
		assert_bool(v47.has_icon()).is_true()
	assert_str(Registry.weapon("revolver").evolves_into).is_equal("golden_revolver")
	assert_str(Registry.weapon("hammer").evolves_into).is_equal("earthshaker")
	assert_array(Registry.problems).is_empty()


func test_the_rarity_changes() -> void:
	assert_str(Registry.passive("sinners_greed").rarity).is_equal("epic")
	for id in ["reach", "big_game_hunter", "venom"]:
		assert_str(Registry.passive(id).rarity).override_failure_message(id).is_equal("uncommon")
	# Reach is +8% area a level (+40% at its top, was +50%); pass 95: +10% at level 1, +6% a rung, +10% Evolved
	assert_float(float((Registry.passive("reach").levels[0][0] as Effect).value)).is_equal_approx(0.1, 0.0001)


func test_the_stranger_gives_level_two_or_one_more() -> void:
	Run.add_weapon(Registry.weapon("gravity_gun"), 1)
	var new_found := false
	var held_found := false
	for k in range(400):
		var o := Run.stranger_offer()
		if o.is_empty() or str(o["type"]) != "weapon":
			continue
		var wd: WeaponDef = o["def"]
		if bool(o["is_new"]):
			assert_int(int(o["level_to"])).override_failure_message(wd.id).is_equal(mini(2, wd.max_level))
			new_found = true
		else:
			assert_int(int(o["level_to"])).override_failure_message(wd.id).is_equal(int(o["level_from"]) + 1)
			held_found = true
	assert_bool(new_found).is_true()
	assert_bool(held_found).is_true()


# ---------------------------------------------------------------- the schema

func test_the_timeline_settings_and_stats_schema() -> void:
	var tl := JsonContent.timeline_from_dict({})
	assert_float(tl.move_pace).is_equal(1.0)
	assert_bool(tl.portal_wave.is_empty()).is_true()
	var tl2 := JsonContent.timeline_from_dict({"move_pace": 0.8, "portal_wave": {"count": 12}})
	assert_float(tl2.move_pace).is_equal_approx(0.8, 0.0001)
	assert_int(int(tl2.portal_wave.get("count", 0))).is_equal(12)
	assert_float(WaveTimeline.new().move_pace).is_equal(1.0)
	# the new items' stats sit on the sheet at nothing, each with its name
	for st in ["phoenix_revive", "hurt_speed", "hurt_speed_seconds", "powder_keg_chance", "coin_on_hit", "gas_mask_cap", "kill_might"]:
		assert_bool(StatSheet.PLAYER_DEFAULTS.has(st)).override_failure_message(st).is_true()
		assert_float(float(StatSheet.PLAYER_DEFAULTS[st])).override_failure_message(st).is_equal(0.0)
		assert_bool(TextGen.STATS.has(st)).override_failure_message(st).is_true()
	assert_str(TextGen.stat_kind("phoenix_revive")).is_equal("count")
	assert_str(TextGen.stat_kind("hurt_speed")).is_equal("pct")
	assert_str(TextGen.stat_kind("hurt_speed_seconds")).is_equal("sec")
	assert_str(TextGen.stat_name("coin_on_hit")).is_equal("chance a hit knocks a coin out")
	assert_str(TextGen.stat_name("kill_might")).is_equal("attack damage per 1,000 kills")
	assert_str(TextGen.describe_effect(Effect.make("gas_mask_cap", "add", 0.08, "player"))).starts_with("up to +8%")


func test_the_dummy_settings_round_trip() -> void:
	var keep_n: int = Settings.dummy_count
	var keep_hp: int = Settings.dummy_hp
	assert_int(Settings.dummy_count).is_greater_equal(10)
	Settings.dummy_count = 15
	Settings.dummy_hp = 500
	var d: Dictionary = Settings.to_dict()
	assert_int(int(d["dummy_count"])).is_equal(15)
	assert_int(int(d["dummy_hp"])).is_equal(500)
	# never fewer than ten, never below nothing
	Settings.dummy_count = 3
	assert_int(Settings.dummy_count).is_equal(10)
	Settings.from_dict(d)
	assert_int(Settings.dummy_count).is_equal(15)
	assert_int(Settings.dummy_hp).is_equal(500)
	Settings.from_dict({"dummy_count": 4, "dummy_hp": -2})
	assert_int(Settings.dummy_count).is_equal(10)
	assert_int(Settings.dummy_hp).is_equal(0)
	Settings.dummy_count = keep_n
	Settings.dummy_hp = keep_hp


# ---------------------------------------------------------------- the pace knob

func test_the_pace_knob_slows_the_hero_the_creatures_and_their_wind_ups() -> void:
	var tl: WaveTimeline = Run.map.timeline
	tl.move_pace = 1.0
	assert_float(Run.move_pace()).is_equal(1.0)
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var d := _test_def("p0_charger", "bull_beetle", "charge", {"charge": {"windup": 0.8, "duration": 0.7, "speed": 9.0, "trigger_range": 6.0, "cooldown": 4.0}})
	var a := em.spawn(d.id, Vector3(12, 0, 0))
	var walk: float = em.speed[a]
	tl.move_pace = 0.8
	assert_float(Run.move_pace()).is_equal_approx(0.8, 0.0001)
	var b := em.spawn(d.id, Vector3(-3, 0, 0))
	assert_float(em.speed[b]).is_equal_approx(walk * 0.8, 0.0001)
	# the hero runs at it too
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(Run.character)
	add_child(p)
	assert_float(p.max_speed()).is_equal_approx(Run.player_sheet.get_stat("move_speed", 5.0) * 0.8, 0.0001)
	# a wind-up and its red line last 1/pace
	em.state[b] = EnemyManager.STATE_MOVE
	em.cooldown[b] = 0.0
	em._steer(b, hero.global_position, DT)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_WINDUP)
	assert_float(em.timer[b]).is_equal_approx(0.8 / 0.8, 0.0001)
	var line: Dictionary = (g.get("lines") as Array).back()
	assert_float(float(line["dur"])).is_equal_approx(1.0, 0.0001)
	# the charge runs at 0.8 of its speed for 1/0.8 as long: the same ground as its line
	em.timer[b] = 0.0
	em._steer(b, hero.global_position, DT)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_CHARGE)
	assert_float(em.timer[b]).is_equal_approx(0.7 / 0.8, 0.0001)
	em._steer(b, hero.global_position, DT)
	assert_float(em.vel[b].length()).is_equal_approx(9.0 * 0.8, 0.05)
	# the creatures' shots fly on the paced clock (High Noon's on top), never the creatures' own delta
	em.pace = 0.8
	em.time_scale = 0.5
	assert_float(em.hostile_clock()).is_equal_approx(0.4, 0.0001)
	em.time_scale = 1.0
	var pm: ProjectileManager = w["pm"]
	var kind := pm.register_kind(SphereMesh.new(), StandardMaterial3D.new(), 1.0)
	var s := pm.hostile_shot(kind, Vector3(20, 1, 20), Vector3(10, 0, 0), 5.0, 0.5, 4.0)
	var x0: float = pm.pos[s].x
	pm._physics_process(DT)
	assert_float(pm.pos[s].x - x0).is_equal_approx(10.0 * DT * 0.8, 0.0001)
	# a poison tick keeps its own clock
	var c := _creature(em, Vector3(8, 0, -8))
	em.poison(c, "x", 1.0, 1, 10.0)
	em._physics_process(DT)
	assert_float(em.poison_tick[c]).is_equal_approx(EnemyManager.POISON_TICK - DT, 0.0001)


# ---------------------------------------------------------------- the crowd's new primitives

func test_hamper_slows_moves_and_attacks_and_a_boss_takes_half() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(5, 0, 5))
	assert_float(em.attack_clock(i)).is_equal(1.0)
	em.hamper(i, 0.5, 2.0)
	assert_float(em.attack_clock(i)).is_equal_approx(0.5, 0.0001)
	assert_float(em.slow_f[i]).is_equal_approx(0.5, 0.0001)
	assert_float(em.slow_t[i]).is_equal_approx(2.0, 0.0001)
	em.cooldown[i] = 1.0
	em.contact_cd[i] = 1.0
	em._physics_process(DT)
	assert_float(em.cooldown[i]).is_equal_approx(1.0 - DT * 0.5, 0.0001)
	assert_float(em.contact_cd[i]).is_equal_approx(1.0 - DT * 0.5, 0.0001)
	# a wind-up runs at that pace too
	em.state[i] = EnemyManager.STATE_WINDUP
	em.timer[i] = 1.0
	em._steer(i, Vector3(30, 0, 30), DT)
	assert_float(em.timer[i]).is_equal_approx(1.0 - DT * 0.5, 0.0001)
	# it runs out on the creature's clock
	em.state[i] = EnemyManager.STATE_MOVE
	em.hamper_t[i] = DT * 0.5
	em._physics_process(DT)
	assert_float(em.attack_clock(i)).is_equal(1.0)
	# a boss takes half
	var b := em.spawn("tumbleweed_king", Vector3(-8, 0, -8))
	em.hamper(b, 0.5, 2.0)
	assert_float(em.attack_clock(b)).is_equal_approx(0.75, 0.0001)
	assert_float(em.slow_f[b]).is_equal_approx(0.25, 0.0001)


func test_priority_takes_a_big_creature_further_off_and_aim_index_follows_the_weapon() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var small := _creature(em, Vector3(4, 0, 0), "skeleton", 1.0)
	var big := _creature(em, Vector3(0, 0, 7.2), "skeleton", 10.0)
	for k in range(3):
		_creature(em, Vector3(-40, 0, -10.0 * k), "skeleton", 1.0)
	em._rebuild_grid()
	em.refresh_crowd_stats()
	assert_int(em.nearest_index(Vector3.ZERO, 20.0)).is_equal(small)
	# 1.8 times as far, ten times the health (its weight at the cap, 3): the big one
	assert_int(em.priority_index(Vector3.ZERO, 20.0)).is_equal(big)
	# 3.5 times as far: the small one again
	em.pos[big] = Vector3(0, 0, 14.0)
	em._rebuild_grid()
	assert_int(em.priority_index(Vector3.ZERO, 20.0)).is_equal(small)
	em.pos[big] = Vector3(0, 0, 7.2)
	em._rebuild_grid()
	# a priority weapon aims with it, any other at the nearest
	var b: WeaponBehavior = auto_free(WeaponBehavior.new())
	b.game = w["g"]
	b.inst = WeaponInstance.new(Registry.weapon("peashooter"), 1)
	assert_int(b.aim_index(Vector3.ZERO, 20.0)).is_equal(big)
	b.inst = WeaponInstance.new(Registry.weapon("boomstick"), 1)
	assert_int(b.aim_index(Vector3.ZERO, 20.0)).is_equal(small)
	assert_int(em.priority_index(Vector3(60, 0, 60), 2.0)).is_equal(-1)


func test_every_spawn_has_its_serial() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(4, 0, 4))
	var j := _creature(em, Vector3(-4, 0, 4))
	assert_int(em.serial[j]).is_equal(em.serial[i] + 1)
	# the slot taken again is a new creature
	em._free(i)
	var k := _creature(em, Vector3(4, 0, -4))
	assert_int(k).is_equal(i)
	assert_int(em.serial[k]).is_greater(em.serial[j])


func test_damage_is_recorded_up_to_what_the_creature_had() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(4, 0, 4), "skeleton", 1.0)
	em.hp[i] = 20.0
	em.max_hp[i] = 20.0
	em.dr[i] = 0.0
	Run.damage_by_weapon.clear()
	assert_bool(em.damage(i, 500.0, "p0_gun")).is_true()
	assert_float(float(Run.damage_by_weapon.get("p0_gun", 0.0))).is_equal_approx(20.0, 0.0001)
	# a ring of nothing (the nuke's, the revive's) records nothing
	var j := _creature(em, Vector3(-4, 0, 4))
	em.dr[j] = 0.0
	em.damage(j, 0.0, "nuke")
	assert_bool(Run.damage_by_weapon.has("nuke")).is_false()
	# a hit it lives through is recorded whole
	em.hp[j] = 100.0
	em.damage(j, 30.0, "p0_gun")
	assert_float(float(Run.damage_by_weapon.get("p0_gun", 0.0))).is_equal_approx(50.0, 0.0001)


func test_a_mini_crit_is_half_a_crit_unless_a_full_one_rolls() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(4, 0, 4))
	em.dr[i] = 0.0
	var fake: DamageNumbers = auto_free(_script(FAKE_NUMBERS).new())
	DamageNumbers.I = fake
	var h0: float = em.hp[i]
	em.damage(i, 10.0, "p0_gun", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_MINI)
	# crit damage x2 by default: a mini crit is x1.5
	assert_float(h0 - em.hp[i]).is_equal_approx(15.0, 0.001)
	var calls: Array = fake.get("calls")
	assert_bool(bool(calls.back()["mini"])).is_true()
	assert_bool(bool(calls.back()["crit"])).is_false()
	# no flag, no mini
	h0 = em.hp[i]
	em.damage(i, 10.0, "p0_gun")
	assert_float(h0 - em.hp[i]).is_equal_approx(10.0, 0.001)
	assert_bool(bool(calls.back()["mini"])).is_false()
	# a full crit wins
	Run.player_sheet.add_effects([Effect.make("crit_chance", "add", 1.0, "player")], "p0 crit")
	h0 = em.hp[i]
	em.damage(i, 10.0, "p0_gun", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_MINI)
	assert_float(h0 - em.hp[i]).is_equal_approx(20.0, 0.001)
	assert_bool(bool(calls.back()["crit"])).is_true()
	assert_bool(bool(calls.back()["mini"])).is_false()
	Run.player_sheet.remove_source("p0 crit")
	DamageNumbers.I = null


## (The headless renderer keeps no MultiMesh data, so the tint is read where _render takes it, EnemyManager.tint_of.)
func test_a_held_tint_goes_over_poison_and_frozen_still_wins() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(4, 0, 4))
	em.poison(i, "x", 1.0, 1, 10.0)
	em._render()
	var green := Color(0.45, 1.0, 0.3, 0.8)
	assert_bool(em.tint_of(i).is_equal_approx(green)).is_true()
	var purple := Color(0.6, 0.2, 0.9, 0.9)
	em.set_status_tint(i, purple, 2.0)
	assert_float(em.status_t[i]).is_equal_approx(2.0, 0.0001)
	assert_bool(em.tint_of(i).is_equal_approx(purple)).is_true()
	em.freeze(i, 1.0)
	assert_bool(em.tint_of(i).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0))).is_true()
	em._render()
	# the tint runs out on the creature's clock
	em.freeze_t[i] = 0.0
	em.status_t[i] = DT * 0.5
	em._physics_process(DT)
	assert_float(em.status_t[i]).is_equal(0.0)
	assert_bool(em.tint_of(i).is_equal_approx(green)).is_true()
	# and the poisoned are counted for Gas Mask
	em.refresh_crowd_stats()
	assert_int(Run.poisoned_alive).is_equal(1)


func test_an_undying_dummy_fills_up_and_the_dummy_brain_never_bites() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := _creature(em, Vector3(6, 0, 6), "skeleton", 1.0)
	em.undying[i] = 1
	var mx: float = em.max_hp[i]
	Run.damage_by_weapon.clear()
	assert_bool(em.damage(i, mx * 10.0, "p0_gun")).is_false()
	assert_float(em.hp[i]).is_equal(mx)
	assert_bool(em.is_alive(i)).is_true()
	assert_float(float(Run.damage_by_weapon.get("p0_gun", 0.0))).is_equal_approx(mx, 0.001)
	# its statuses take as on any creature
	em.ignite(i, "p0_gun", 1.0, 3.0, 0.0)
	assert_bool(em.is_burning(i)).is_true()
	# a creature in the hero's reach bites; a dummy there never does
	var d := _test_def("p0_dummy", "skeleton", "dummy")
	assert_float(d.damage).is_greater(0.0)
	var bite := _creature(em, Vector3(0.3, 0, 0), "skeleton", 50.0)
	em.contact_cd[bite] = 0.0
	em._rebuild_grid()
	em._physics_process(DT)
	assert_int(int(hero.get("hits"))).is_greater(0)
	em._free(bite)
	hero.set("hits", 0)
	var dm := em.spawn(d.id, Vector3(0.3, 0, 0))
	em.state[dm] = EnemyManager.STATE_MOVE
	for k in range(30):
		em.contact_cd[dm] = 0.0
		em._physics_process(DT)
	assert_int(int(hero.get("hits"))).is_equal(0)
	# shoved off its spot, it walks back
	var home: Vector3 = em.home[dm]
	em.pos[dm] = home + Vector3(1.5, 0, 0)
	var off := Vector2(em.pos[dm].x - home.x, em.pos[dm].z - home.z).length()
	for k in range(40):
		em._physics_process(DT)
	assert_float(Vector2(em.pos[dm].x - home.x, em.pos[dm].z - home.z).length()).is_less(off - 0.3)


func test_blue_fire_follows_the_weapon_to_the_creature_and_the_flame() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var mol := Run.add_weapon(Registry.weapon("molotov"), 1)
	assert_bool(mol.blue_fire()).is_false()
	var a := _creature(em, Vector3(3, 0, 3))
	em.ignite(a, "molotov", 2.0, 2.0, 0.0)
	assert_int(em.fire_blue[a]).is_equal(0)
	assert_bool(bool((g.get("ignites") as Array).back())).is_false()
	# Methanol's params turn it blue
	assert_bool(Run.add_mutation("methanol", true)).is_true()
	assert_bool(mol.blue_fire()).is_true()
	var b := _creature(em, Vector3(-3, 0, -3))
	em.ignite(b, "molotov", 2.0, 2.0, 0.0)
	assert_int(em.fire_blue[b]).is_equal(1)
	assert_bool(bool((g.get("ignites") as Array).back())).is_true()
	em._render()
	var tb := em.tint_of(b)
	assert_bool(tb.b > 0.9 and tb.r < 0.4).override_failure_message(str(tb)).is_true()
	var ta := em.tint_of(a)
	assert_bool(ta.r > 0.9 and ta.b < 0.1).override_failure_message(str(ta)).is_true()
	# the flame pool keeps the flag per flame (the fire shader reads it as custom data z), through the swap-remove
	var fx: Fx = w["fx"]
	var n0: int = fx._n
	fx.flame(Vector3(1, 0, 0), 1.0, 0.01)
	fx.flame(Vector3(0, 0, 0), 1.0, 0.5, Fx.FLAME_ORANGE, true)
	assert_int(fx._blue[n0]).is_equal(0)
	assert_int(fx._blue[n0 + 1]).is_equal(1)
	assert_bool(fx._col[n0 + 1].is_equal_approx(Color(Fx.FLAME_BLUE.r, Fx.FLAME_BLUE.g, Fx.FLAME_BLUE.b, Fx.FLAME_ORANGE.a))).is_true()
	fx._process(0.05)
	# the short orange one went and the blue one took its slot, flag and all
	assert_int(fx._n).is_equal(n0 + 1)
	assert_int(fx._blue[n0]).is_equal(1)
	assert_int(fx._flame_mm.visible_instance_count).is_equal(1)


func test_a_dying_creature_tells_what_it_carried() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3, 0, 3), "skeleton", 1.0)
	em.poison(i, "p0_gun", 1.0, 1, 5.0)
	var seen := {}
	em.creature_dying.connect(func(j: int, wid: String) -> void:
		seen["i"] = j
		seen["wid"] = wid
		seen["poisoned"] = em.is_poisoned(j)
		seen["dying"] = em.state[j] == EnemyManager.STATE_DYING)
	em.enemy_died.connect(func(_d, _p, _e, _w) -> void:
		seen["max_hp"] = em.died_max_hp)
	em.damage(i, 9999.0, "p0_gun")
	assert_int(int(seen.get("i", -1))).is_equal(i)
	assert_str(str(seen.get("wid", ""))).is_equal("p0_gun")
	assert_bool(bool(seen.get("poisoned", false))).is_true()
	assert_bool(bool(seen.get("dying", false))).is_true()
	assert_float(float(seen.get("max_hp", 0.0))).is_equal_approx(em.max_hp[i], 0.001)
	# cleared once it has told
	assert_bool(em.is_poisoned(i)).is_false()
	assert_float(em.died_max_hp).is_equal(0.0)


# ---------------------------------------------------------------- Phoenix Feather

func test_phoenix_feather_is_one_free_revive_a_run() -> void:
	assert_bool(Run.phoenix_ready()).is_false()
	Run.player_sheet.add_effects([Effect.make("phoenix_revive", "add", 1.0, "player")], "p0 phoenix")
	assert_bool(Run.phoenix_ready()).is_true()
	Run.use_phoenix()
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.phoenix_ready()).is_false()
	# it is not one of Down!'s chances
	assert_int(Run.revives_used).is_equal(0)
	# a new run carries it again
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_bool(Run.phoenix_used).is_false()


# ---------------------------------------------------------------- plates by level

func test_plates_take_their_level_colour() -> void:
	var pea: WeaponDef = Registry.weapon("peashooter")
	assert_bool(W.plate_fill(pea).is_equal_approx(W.RARITY_PLATE["common"])).is_true()
	var tiers := ["common", "common", "uncommon", "rare", "epic", "legendary", "legendary"]
	for lv in range(tiers.size()):
		assert_bool(W.plate_fill(pea, lv).is_equal_approx(W.RARITY_PLATE[tiers[lv]])).override_failure_message("level %d" % lv).is_true()
	# a line the same, up to its fourth level's epic
	var brawn: PassiveDef = Registry.passive("brawn")
	assert_bool(W.plate_fill(brawn, 4).is_equal_approx(W.RARITY_PLATE["epic"])).is_true()
	# evolutions stay dark, passive items their rarity, other kinds their colour, whatever the level
	assert_bool(W.plate_fill(Registry.weapon("pea_cannon"), 1).is_equal_approx(W.EVOLVED_FILL)).is_true()
	assert_bool(W.plate_fill(Registry.passive("juggernaut"), 1).is_equal_approx(W.EVOLVED_FILL)).is_true()
	var greed: PassiveDef = Registry.passive("sinners_greed")
	assert_bool(W.plate_fill(greed, 1).is_equal_approx(W.RARITY_PLATE["epic"])).is_true()
	# pass 95 (lane PASSIVES): a passive item climbs the ladder a level; past its top it is Evolved, dark
	assert_bool(W.plate_fill(greed, 2).is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	assert_bool(W.plate_fill(greed, 5).is_equal_approx(W.EVOLVED_FILL)).is_true()
	assert_bool(W.plate_fill(Registry.mutation("methanol"), 3).is_equal_approx(W.PLUM)).is_true()
	# the plate takes it as its fourth argument; the old calls read the item in general
	var p: WPlate = auto_free(WPlate.new())
	p.for_def(pea, 88.0, false, 3)
	assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE["rare"])).is_true()
	var q: WPlate = auto_free(WPlate.new())
	q.for_def(pea, 88.0)
	assert_bool(q.fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
