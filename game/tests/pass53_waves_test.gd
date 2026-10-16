extends GdUnitTestSuite

## Pass 53, lane WD (the wave schema in the game, docs/waves_schema.md): the timeline's `waves` and the roster rows' new
## keys parse; EnemyDef.with_overrides lays every "Stat overrides" key on a copy of a creature that is its own
## EnemyManager type (type_key id[@variant][#hash], cached by Registry.enemy_with); a spawned overridden creature carries
## the overridden numbers; alive_of counts the base, its variants and its copies together, so a row's max_alive holds
## across them; the waves fire their bursts on their clock, stop at their count and their until, respect the cap or not,
## roll one alternative per run, scatter or pack, wear an elite modifier once colour is open and toast once; the events'
## weighted lists, per-run chance and jitter, the [min, max] elite_every interval and the swarm patterns; the stun; the
## bite's cadence from `contact_cd`; Red Canyon's timeline unchanged by all of it.

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
var lines: Array = []
var rings: Array = []
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
func telegraph_line(_a, _b, c, d, _e) -> void:
	lines.append({"length": float(c), "dur": float(d)})
func telegraph_ring(_a, b, c, _d, _e = true) -> void:
	rings.append({"r": float(b), "dur": float(c)})
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func enemy_shot_straight(_a, _b, _c, _d, _e, _f = {}) -> void:
	pass
func enemy_spit(_a, _b, _c, _d, _e, _f = {}) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var hits := 0
var last_outcome := "hit"
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

## an Fx stand-in that counts the stun's motes
const FAKE_FX := """extends Node
var motes := 0
var bursts := 0
func mote(_a, _v, _l, _s, _c) -> void:
	motes += 1
func burst(_a, _c, _s = 1.0) -> void:
	bursts += 1
"""

## the pickups as the director's power-up roll sees them
const FAKE_PICKUPS := """extends Node
var specials: Array = []
func spawn_special(def, at, _quiet = false) -> void:
	specials.append({"id": def.id, "at": at})
func spawn_chest(_at, _boss = false) -> void:
	pass
"""

const DT := 1.0 / 60.0

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at` with a plain map, the real crowd, and a pickups stand-in.
func _world(hero_at := Vector3.ZERO, with_fx := false) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	if with_fx:
		var fx := Node.new()
		fx.set_script(_script(FAKE_FX))
		g.add_child(fx)
		g.fx = fx
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pickups": pk}


## A timeline from `extra` over quiet test defaults: a flat cap of 100, no roster, no events, colour from the start.
func _tl(extra: Dictionary = {}) -> WaveTimeline:
	var base := {"stage_length": 430, "stages": 3, "cap_start": 100, "cap_per_minute": 0, "cap_max": 300, "hard_cap": 300,
		"spawn_interval": 0.5, "roster": [], "events": [], "waves": [], "colour_after_kills": 0, "hell_cap": [0.5, 0.5, 0.5]}
	for k in extra.keys():
		base[k] = extra[k]
	return JsonContent.timeline_from_dict(base)


## A director on `tl` in the world `w`, as the tests drive it by hand (not in the tree: its _process would run the clock).
func _director(w: Dictionary, tl: WaveTimeline) -> WaveDirector:
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = tl
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	return d


## A test creature `id` made from `from`, no variance, with `fields` set; gone after the test.
func _test_def(id: String, from: String, fields: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	for k: String in fields.keys():
		d.set(k, fields[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _alive_indices(em: EnemyManager) -> Array:
	var out: Array = []
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1 and em.state[i] != EnemyManager.STATE_DYING:
			out.append(i)
	return out


func _max_spread(em: EnemyManager, idx: Array) -> float:
	var best := 0.0
	for a in idx:
		for b in idx:
			best = maxf(best, Vector2(em.pos[a].x - em.pos[b].x, em.pos[a].z - em.pos[b].z).length())
	return best


func _modded(em: EnemyManager) -> int:
	var n := 0
	for i in _alive_indices(em):
		if em.elite_idx[i] >= 0:
			n += 1
	return n


## A creature with every block the overrides touch, as a bare def (no Registry).
func _src() -> EnemyDef:
	var d := EnemyDef.new()
	d.id = "w53_src"
	d.hp = 10.0
	d.damage = 3.0
	d.speed = 1.6
	d.size = 1.0
	d.radius = 0.5
	d.contact_cd = 0.6
	d.pack_size = 5
	d.max_alive = 0
	d.cap_share = 0.5
	d.xp_mult = 1.0
	d.ranged = {"cooldown": 2.0, "projectile_speed": 6.0, "range": 8.0, "knockback": 2.0}
	d.charge = {"cooldown": 4.0, "speed": 9.0, "knockback": 5.0}
	d.kamikaze = {"windup": 0.4, "knockback": 3.0}
	d.artillery = {"missile": {"speed": 4.0}}
	d.drops = {"small": 1.0, "gold": 0.02}
	d.elite = {"hp_mult_per_stage": 1.8}
	d.boss = {"cooldown_between": 3.0, "attacks": [{"name": "roll", "speed": 12.0, "knockback": 6.0}, {"name": "burrow"}, {"name": "slam", "knockback": 8.0}]}
	return d


# ---------------------------------------------------------------- the schema

func test_the_schema_parses_waves_and_the_rows_new_keys() -> void:
	var tl := JsonContent.timeline_from_dict({
		"roster": [{"t": 0, "enemy": "skeleton", "weight": 10, "pack": 7, "pattern": "scatter", "variant": "SK-B", "stats": {"hp": 12}}],
		"waves": [{"id": "w1", "name": "Opening", "t": 0, "until": 30, "count": 20, "burst": 5, "every": 2.0, "pattern": "pack",
			"respect_cap": true, "channel": "regular", "elite": "", "toast": "",
			"alts": [{"chance": 0.5, "enemy": "skeleton", "pack": 5, "stats": {"hp": 10}}, {"chance": 0.5, "enemy": "fire_ant"}]}],
		"events": [{"t": 215, "type": "elite_boss", "enemy": ["dune_scorpion", "sun_prophet"], "weights": [2, 1], "chance": 0.5, "t_jitter": 20}]})
	assert_int(tl.waves.size()).is_equal(1)
	var w: Dictionary = tl.waves[0]
	assert_str(str(w["id"])).is_equal("w1")
	assert_int((w["alts"] as Array).size()).is_equal(2)
	var r: Dictionary = tl.roster[0]
	assert_int(int(r["pack"])).is_equal(7)
	assert_str(str(r["pattern"])).is_equal("scatter")
	assert_str(str(r["variant"])).is_equal("SK-B")
	assert_int(int((r["stats"] as Dictionary)["hp"])).is_equal(12)
	assert_array((tl.events[0] as Dictionary)["weights"]).is_equal([2, 1])
	# nothing said: no waves, as every map before this pass
	assert_array(JsonContent.timeline_from_dict({}).waves).is_empty()
	assert_array(WaveTimeline.new().waves).is_empty()
	assert_array(JsonContent.timeline_from_dict({"waves": "nope"}).waves).is_empty()
	# the creature's new fields, from its JSON and by default
	var e := JsonContent.build("enemies", {"id": "w53_json", "contact_cd": 0.3, "pickup_chance_mult": 2.0, "pickup_weights": {"heart": 4}}, "res://content/enemies/skeleton/") as EnemyDef
	assert_float(e.contact_cd).is_equal_approx(0.3, 0.0001)
	assert_float(e.pickup_chance_mult).is_equal_approx(2.0, 0.0001)
	assert_int(int(e.pickup_weights.get("heart", 0))).is_equal(4)
	var plain := JsonContent.build("enemies", {"id": "w53_plain_json"}, "res://content/enemies/skeleton/") as EnemyDef
	assert_float(plain.contact_cd).is_equal_approx(0.6, 0.0001)
	assert_float(plain.pickup_chance_mult).is_equal_approx(1.0, 0.0001)
	assert_bool(plain.pickup_weights.is_empty()).is_true()
	assert_float(EnemyDef.new().contact_cd).is_equal_approx(0.6, 0.0001)


# ---------------------------------------------------------------- with_overrides

func test_with_overrides_lays_every_key_on_a_copy_and_leaves_the_source_alone() -> void:
	var d := _src()
	var s := {"hp": 20, "hp_mult": 1.5, "damage": 4, "damage_mult": 2, "speed": 2.0, "speed_mult": 1.5, "size": 1.2, "radius": 0.7,
		"damage_reduction": 0.95, "contact_cd": 0.4, "attack_rate_mult": 2.0, "projectile_speed_mult": 1.5, "knockback_mult": 2.0,
		"pack": 3, "max_alive": 6, "cap_share": 1.0, "xp_mult": 2.5, "can_be_elite": false, "pickup_chance_mult": 0.5,
		"pickup_weights": {"heart": 6, "nuke": 1}, "drops": {"gold": 0.5, "pickup": {"id": "rage", "chance": 0.1}},
		"elite": {"hp_mult_per_stage": 1.2}, "boss": {"hp_mult_per_stage": 1.4, "attacks": {"burrow": false, "roll": true, "zzz": true}},
		"ranged": {"range": 9.0}, "charge": {"speed": 11.0}}
	var v := d.with_overrides(s)
	assert_object(v).is_not_same(d)
	# direct values, then the multipliers on them
	assert_float(v.hp).is_equal_approx(30.0, 0.001)
	assert_float(v.damage).is_equal_approx(8.0, 0.001)
	assert_float(v.speed).is_equal_approx(3.0, 0.001)
	assert_float(v.size).is_equal_approx(1.2, 0.001)
	assert_float(v.radius).is_equal_approx(0.7, 0.001)
	assert_float(v.damage_reduction).is_equal_approx(0.9, 0.001)   # clamped like the JSON's
	assert_int(v.pack_size).is_equal(3)
	assert_int(v.max_alive).is_equal(6)
	assert_float(v.cap_share).is_equal_approx(1.0, 0.001)
	assert_float(v.xp_mult).is_equal_approx(2.5, 0.001)
	assert_bool(v.can_be_elite).is_false()
	assert_float(v.pickup_chance_mult).is_equal_approx(0.5, 0.001)
	assert_int(int(v.pickup_weights["heart"])).is_equal(6)
	assert_int(int(v.pickup_weights["nuke"])).is_equal(1)
	# attack_rate_mult 2 halves every attack clock, contact_cd after its direct value
	assert_float(v.contact_cd).is_equal_approx(0.2, 0.001)
	assert_float(float(v.ranged["cooldown"])).is_equal_approx(1.0, 0.001)
	assert_float(float(v.charge["cooldown"])).is_equal_approx(2.0, 0.001)
	assert_float(float(v.kamikaze["windup"])).is_equal_approx(0.2, 0.001)
	assert_float(float(v.boss["cooldown_between"])).is_equal_approx(1.5, 0.001)
	# projectile_speed_mult on the shot, the missile and the attacks that have a speed
	assert_float(float(v.ranged["projectile_speed"])).is_equal_approx(9.0, 0.001)
	assert_float(float((v.artillery["missile"] as Dictionary)["speed"])).is_equal_approx(6.0, 0.001)
	# knockback_mult on the blocks and the attacks that have one
	assert_float(float(v.ranged["knockback"])).is_equal_approx(4.0, 0.001)
	assert_float(float(v.charge["knockback"])).is_equal_approx(10.0, 0.001)
	assert_float(float(v.kamikaze["knockback"])).is_equal_approx(6.0, 0.001)
	# the deep merges keep what the override does not name
	assert_float(float(v.ranged["range"])).is_equal_approx(9.0, 0.001)
	assert_float(float(v.charge["speed"])).is_equal_approx(11.0, 0.001)
	assert_float(float(v.drops["small"])).is_equal_approx(1.0, 0.001)
	assert_float(float(v.drops["gold"])).is_equal_approx(0.5, 0.001)
	assert_str(str((v.drops["pickup"] as Dictionary)["id"])).is_equal("rage")
	assert_float(float(v.elite["hp_mult_per_stage"])).is_equal_approx(1.2, 0.001)
	assert_float(float(v.boss["hp_mult_per_stage"])).is_equal_approx(1.4, 0.001)
	# boss.attacks as an on/off map: burrow gone, roll and slam kept, the unknown name adds nothing
	var names: Array = []
	for a in v.boss["attacks"]:
		names.append(str(a["name"]))
	assert_array(names).is_equal(["roll", "slam"])
	assert_float(float((v.boss["attacks"][0] as Dictionary)["speed"])).is_equal_approx(18.0, 0.001)
	assert_float(float((v.boss["attacks"][0] as Dictionary)["knockback"])).is_equal_approx(12.0, 0.001)
	assert_float(float((v.boss["attacks"][1] as Dictionary)["knockback"])).is_equal_approx(16.0, 0.001)
	# the key and the type
	assert_int(v.override_key.length()).is_equal(8)
	assert_str(v.type_key()).is_equal("w53_src#" + v.override_key)
	assert_str(v.id).is_equal("w53_src")
	assert_int(int(v.override_stats["hp"])).is_equal(20)
	# the source is as it was
	assert_float(d.hp).is_equal_approx(10.0, 0.001)
	assert_float(d.contact_cd).is_equal_approx(0.6, 0.001)
	assert_int(d.pack_size).is_equal(5)
	assert_float(float(d.ranged["cooldown"])).is_equal_approx(2.0, 0.001)
	assert_float(float(d.charge["knockback"])).is_equal_approx(5.0, 0.001)
	assert_float(float((d.artillery["missile"] as Dictionary)["speed"])).is_equal_approx(4.0, 0.001)
	assert_int((d.boss["attacks"] as Array).size()).is_equal(3)
	assert_float(float((d.boss["attacks"][0] as Dictionary)["speed"])).is_equal_approx(12.0, 0.001)
	assert_bool(d.drops.has("pickup")).is_false()
	assert_str(d.type_key()).is_equal("w53_src")
	# nothing to lay on: the creature itself
	assert_object(d.with_overrides({})).is_same(d)


func test_the_clock_and_speed_multipliers_reach_the_defaults_a_block_leaves_unsaid() -> void:
	var d := _src()
	d.ranged = {"range": 8.0}
	var v := d.with_overrides({"attack_rate_mult": 2.0, "projectile_speed_mult": 2.0})
	# the code's defaults: a 2.5 s cooldown and a lobbed spit at 6
	assert_float(float(v.ranged["cooldown"])).is_equal_approx(1.25, 0.001)
	assert_float(float(v.ranged["projectile_speed"])).is_equal_approx(12.0, 0.001)
	d.ranged = {"range": 8.0, "straight": true}
	assert_float(float(d.with_overrides({"projectile_speed_mult": 2.0}).ranged["projectile_speed"])).is_equal_approx(24.0, 0.001)
	d.ranged = {"cone_deg": 50.0, "count": 5}
	assert_float(float(d.with_overrides({"projectile_speed_mult": 0.5}).ranged["projectile_speed"])).is_equal_approx(8.0, 0.001)
	# a block the creature has not got stays absent: no cooldown is invented for a creature that never attacks that way
	d.ranged = {}
	d.charge = {}
	d.kamikaze = {}
	d.boss = {}
	var q := d.with_overrides({"attack_rate_mult": 3.0})
	assert_bool(q.ranged.is_empty()).is_true()
	assert_bool(q.charge.is_empty()).is_true()
	assert_bool(q.boss.is_empty()).is_true()
	assert_float(q.contact_cd).is_equal_approx(0.2, 0.001)


func test_equal_override_sets_share_one_key_whatever_their_spelling() -> void:
	assert_str(EnemyDef.override_key_of({"hp": 20})).is_equal(EnemyDef.override_key_of({"hp": 20.0}))
	assert_str(EnemyDef.override_key_of({"a": 1, "b": 2})).is_equal(EnemyDef.override_key_of({"b": 2, "a": 1}))
	assert_str(EnemyDef.override_key_of({"boss": {"attacks": {"x": false, "y": true}}})).is_equal(EnemyDef.override_key_of({"boss": {"attacks": {"y": true, "x": false}}}))
	assert_str(EnemyDef.override_key_of({"hp": 20})).is_not_equal(EnemyDef.override_key_of({"hp": 21}))
	assert_str(EnemyDef.override_key_of({"hp": 20})).is_not_equal(EnemyDef.override_key_of({"damage": 20}))
	assert_int(EnemyDef.override_key_of({"hp": 20}).length()).is_equal(8)
	assert_str(EnemyDef.canonical_json({"b": [1, 2.5, {"z": true, "a": "x"}], "a": 3.0})).is_equal('{"a":3,"b":[1,2.5,{"a":"x","z":true}]}')


func test_the_registry_serves_one_copy_per_variant_and_override_set() -> void:
	var base: EnemyDef = Registry.enemy("skeleton")
	assert_object(Registry.enemy_with("skeleton")).is_same(base)
	assert_object(Registry.enemy_with("skeleton", "", {})).is_same(base)
	assert_object(Registry.enemy_with("w53_nobody", "", {"hp": 1})).is_null()
	var a := Registry.enemy_with("skeleton", "", {"hp": 20})
	var b := Registry.enemy_with("skeleton", "", {"hp": 20.0})
	assert_object(a).is_not_same(base)
	assert_object(b).is_same(a)
	assert_str(a.type_key()).is_equal("skeleton#" + EnemyDef.override_key_of({"hp": 20}))
	assert_float(a.hp).is_equal_approx(20.0, 0.001)
	var c := Registry.enemy_with("skeleton", "", {"hp": 21})
	assert_object(c).is_not_same(a)
	assert_str(c.type_key()).is_not_equal(a.type_key())
	# the variant first, then the overrides
	if base.variants.has("SK-B"):
		var v := Registry.enemy_with("skeleton", "SK-B")
		assert_str(v.type_key()).is_equal("skeleton@SK-B")
		assert_object(Registry.enemy_with("skeleton", "SK-B")).is_same(v)
		var vo := Registry.enemy_with("skeleton", "SK-B", {"hp": 20})
		assert_str(vo.type_key()).is_equal("skeleton@SK-B#" + EnemyDef.override_key_of({"hp": 20}))
		assert_object(vo.sprite).is_same(v.sprite)
		assert_str(vo.variant_code).is_equal("SK-B")
		assert_object(Registry.enemy_with("skeleton", "SK-B", {"hp": 20.0})).is_same(vo)
	# a def swapped under the id is never served a copy of the old one
	var d := _test_def("w53_swap", "skeleton", {"hp": 10.0})
	var first := Registry.enemy_with("w53_swap", "", {"damage": 9})
	assert_float(first.hp).is_equal_approx(10.0, 0.001)
	var d2 := _test_def("w53_swap", "skeleton", {"hp": 40.0})
	var second := Registry.enemy_with("w53_swap", "", {"damage": 9})
	assert_object(second).is_not_same(first)
	assert_float(second.hp).is_equal_approx(40.0, 0.001)
	assert_object(d).is_not_same(d2)


# ---------------------------------------------------------------- the crowd

func test_a_spawned_overridden_creature_carries_the_overridden_numbers() -> void:
	var d := _test_def("w53_plain", "skeleton", {"hp": 10.0, "damage": 3.0, "speed": 1.6, "radius": 0.52, "size": 1.0, "cap_share": 0.5})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	var s := {"hp": 50, "damage": 7, "speed": 3.0, "radius": 0.9, "size": 1.5, "cap_share": 2.0}
	var i := em.spawn(d.id, Vector3.ZERO, null, 1.0, 1.0, "", s)
	assert_int(i).is_greater_equal(0)
	assert_float(em.hp[i]).is_equal_approx(50.0, 0.001)
	assert_float(em.max_hp[i]).is_equal_approx(50.0, 0.001)
	assert_float(em.dmg[i]).is_equal_approx(7.0, 0.001)
	assert_float(em.speed[i]).is_equal_approx(3.0 * Run.move_pace(), 0.001)
	assert_float(em.radius[i]).is_equal_approx(0.9, 0.001)
	assert_float(em.size[i]).is_equal_approx(1.5, 0.001)
	var plain := em.spawn(d.id, Vector3(5, 0, 0))
	assert_float(em.hp[plain]).is_equal_approx(10.0, 0.001)
	assert_float(em.dmg[plain]).is_equal_approx(3.0, 0.001)
	assert_float(em.speed[plain]).is_equal_approx(1.6 * Run.move_pace(), 0.001)
	# two types of one creature, and the type's share is the copy's
	assert_int(em.type_idx[i]).is_not_equal(em.type_idx[plain])
	var tdef: EnemyDef = em.types[em.type_idx[i]]["def"]
	assert_str(tdef.type_key()).is_equal(d.id + "#" + EnemyDef.override_key_of(s))
	assert_str((em.types[em.type_idx[plain]]["def"] as EnemyDef).type_key()).is_equal(d.id)
	assert_float(em.cap_load()).is_equal_approx(2.5, 0.001)
	# the same overrides again land in the same type
	var j := em.spawn(d.id, Vector3(2, 0, 0), null, 1.0, 1.0, "", {"cap_share": 2.0, "size": 1.5, "radius": 0.9, "speed": 3.0, "damage": 7, "hp": 50.0})
	assert_int(em.type_idx[j]).is_equal(em.type_idx[i])
	# the pack and the ring pass them on, and say how many came
	assert_int(em.spawn_pack(d.id, Vector3(10, 0, 0), 3, null, "", s)).is_equal(3)
	assert_int(em.spawn_ring(d.id, 4, Vector3(-10, 0, 0), 3.0, "", s)).is_equal(4)
	assert_int(em.alive_of(d.id)).is_equal(10)
	var same := 0
	for k in _alive_indices(em):
		if em.type_idx[k] == em.type_idx[i]:
			same += 1
	assert_int(same).is_equal(9)


func test_alive_of_counts_every_type_of_a_creature_and_max_alive_holds_across_them() -> void:
	var d := _test_def("w53_count", "skeleton", {"cap_share": 0.5})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl())
	em.spawn(d.id, Vector3(1, 0, 0))
	em.spawn(d.id, Vector3(2, 0, 0))
	em.spawn(d.id, Vector3(3, 0, 0), null, 1.0, 1.0, "", {"hp": 30})
	em.spawn(d.id, Vector3(4, 0, 0), null, 1.0, 1.0, "", {"hp": 30, "cap_share": 1.0})
	assert_int(em.alive_of(d.id)).is_equal(4)
	assert_float(em.load_of(d.id)).is_equal_approx(0.5 + 0.5 + 0.5 + 1.0, 0.001)
	assert_int(em.alive_of("w53_nobody")).is_equal(0)
	assert_float(em.load_of("w53_nobody")).is_equal_approx(0.0, 0.001)
	# a row whose stats cap the creature at three is closed while four of any type live; at five it is open
	assert_array(dir._roster_open([{"t": 0, "enemy": d.id, "weight": 1, "stats": {"max_alive": 3}}])).is_empty()
	assert_int(dir._roster_open([{"t": 0, "enemy": d.id, "weight": 1, "stats": {"max_alive": 5}}]).size()).is_equal(1)
	assert_int(dir._roster_open([{"t": 0, "enemy": d.id, "weight": 1}]).size()).is_equal(1)
	# the hell load counts every type of a hell row's creature too
	assert_float(dir._hell_load([{"t": 0, "enemy": d.id, "weight": 1, "channel": "hell"}])).is_equal_approx(2.5, 0.001)


func test_a_roster_row_spawns_by_its_pack_pattern_variant_and_stats() -> void:
	var d := _test_def("w53_row", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"burst_min": 20, "burst_max": 20}))
	dir._rng.seed = 3
	# pack: all at one point, in the overridden type. A burst draws rows until its load is full (as it always did), so the
	# room handed in is what limits each call here: three load units, three bodies
	var left := dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 3, "stats": {"hp": 44}}], 3.0, 300)
	assert_int(left).is_equal(297)
	var packed := _alive_indices(em)
	assert_int(packed.size()).is_equal(3)
	assert_float(_max_spread(em, packed)).is_less(6.0)
	for i in packed:
		assert_float(em.hp[i]).is_equal_approx(44.0, 0.001)
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	# scatter: each at its own spawn point, far apart
	dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pack": 6, "pattern": "scatter"}], 6.0, 300)
	var scattered := _alive_indices(em)
	assert_int(scattered.size()).is_equal(6)
	assert_float(_max_spread(em, scattered)).is_greater(6.0)
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	# single: one a draw whatever the pack
	dir._burst_from([{"t": 0, "enemy": d.id, "weight": 1, "pattern": "single"}], 0.5, 300)
	assert_int(_alive_indices(em).size()).is_equal(1)
	# a variant on a row lands in the variant's type
	var sk: EnemyDef = Registry.enemy("skeleton")
	if sk.variants.has("SK-B"):
		em.kill_all()
		for k in range(3):
			em._physics_process(2.0)
		# one load unit of room: two skeletons at half a share each
		dir._burst_from([{"t": 0, "enemy": "skeleton", "weight": 1, "pack": 2, "variant": "SK-B"}], 1.0, 300)
		var vi := _alive_indices(em)
		assert_int(vi.size()).is_equal(2)
		assert_str((em.types[em.type_idx[vi[0]]]["def"] as EnemyDef).type_key()).is_equal("skeleton@SK-B")
		assert_int(em.alive_of("skeleton")).is_equal(2)


func test_the_portal_wave_follows_the_rows_pattern() -> void:
	var d := _test_def("w53_portal", "skeleton", {"pack_size": 5})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [{"t": 0, "enemy": d.id, "weight": 1, "pack": 3, "pattern": "scatter"}], "portal_wave": {"count": 6}}))
	dir.phase = WaveDirector.Phase.PORTAL
	Run.elapsed = 10.0
	dir._rng.seed = 5
	assert_int(dir.spawn_portal_wave()).is_equal(6)
	var idx := _alive_indices(em)
	assert_int(idx.size()).is_equal(6)
	assert_float(_max_spread(em, idx)).is_greater(6.0)


# ---------------------------------------------------------------- the waves

func test_a_wave_fires_at_t_then_every_and_stops_at_its_count() -> void:
	var d := _test_def("w53_wave", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"waves": [{"id": "w1", "t": 10, "every": 2.0, "burst": 5, "count": 12, "enemy": d.id, "respect_cap": false}]}))
	Run.elapsed = 9.9
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(0)
	var st := dir.wave_state("w1")
	assert_int(int(st["spawned"])).is_equal(0)
	assert_float(float(st["next_t"])).is_equal_approx(10.0, 0.001)
	assert_str(str((st["alt"] as Dictionary)["enemy"])).is_equal(d.id)
	Run.elapsed = 10.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(5)
	st = dir.wave_state("w1")
	assert_int(int(st["spawned"])).is_equal(5)
	assert_float(float(st["next_t"])).is_equal_approx(12.0, 0.001)
	Run.elapsed = 11.9
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(5)
	Run.elapsed = 12.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(10)
	Run.elapsed = 14.0
	dir._tick_waves()
	# the last burst is cut to what the count still owes, and the wave is spent
	assert_int(em.alive_count()).is_equal(12)
	assert_bool(bool(dir.wave_state("w1")["done"])).is_true()
	Run.elapsed = 30.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(12)
	assert_bool(dir.wave_state("w53_nobody").is_empty()).is_true()


func test_a_wave_ends_at_until_and_a_one_burst_wave_comes_once() -> void:
	var d := _test_def("w53_until", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"waves": [
		{"id": "open", "t": 0, "until": 5, "every": 1.0, "burst": 2, "enemy": d.id, "respect_cap": false},
		{"id": "once", "t": 3, "every": 0, "burst": 4, "enemy": d.id, "respect_cap": false}]}))
	Run.elapsed = 0.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(2)
	Run.elapsed = 3.0
	dir._tick_waves()
	# "open" fired at 0 and now at 3 (its rhythm is 1 s; the clock jumped, so it caught up by one burst and starts again),
	# "once" came once
	assert_bool(bool(dir.wave_state("once")["done"])).is_true()
	assert_int(int(dir.wave_state("once")["spawned"])).is_equal(4)
	Run.elapsed = 4.9
	dir._tick_waves()
	var before := em.alive_count()
	Run.elapsed = 5.0
	dir._tick_waves()
	assert_bool(bool(dir.wave_state("open")["done"])).is_true()
	Run.elapsed = 9.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(before)


func test_a_wave_respects_the_cap_when_asked_and_ignores_it_when_not() -> void:
	var d := _test_def("w53_cap", "skeleton", {"pack_size": 10, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var tl := _tl({"cap_start": 4, "cap_max": 4, "hard_cap": 300, "waves": [{"id": "polite", "t": 0, "every": 1.0, "burst": 10, "enemy": d.id}]})
	var dir := _director(w, tl)
	assert_int(dir.current_cap()).is_equal(4)
	Run.elapsed = 0.0
	dir._tick_waves()
	# four load units of room: four bodies, no more
	assert_int(em.alive_count()).is_equal(4)
	Run.elapsed = 1.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(4)
	assert_int(int(dir.wave_state("polite")["spawned"])).is_equal(4)
	# the burst that found no room waits for the next every, nothing is owed
	assert_float(float(dir.wave_state("polite")["next_t"])).is_equal_approx(2.0, 0.001)
	# a rude wave spawns on top of the cap, up to the hard cap
	var w2 := _world(Vector3.ZERO)
	var em2: EnemyManager = w2["em"]
	var dir2 := _director(w2, _tl({"cap_start": 4, "cap_max": 4, "hard_cap": 7, "waves": [{"id": "rude", "t": 0, "every": 1.0, "burst": 10, "enemy": d.id, "respect_cap": false}]}))
	Run.elapsed = 0.0
	dir2._tick_waves()
	assert_int(em2.alive_count()).is_equal(7)


func test_a_hell_wave_spawns_into_the_hell_channels_room() -> void:
	var d := _test_def("w53_hell", "skeleton", {"pack_size": 10, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	# a cap of 8 and a hell channel of half of it: a hell wave gets four, and the regular room stays whole
	var dir := _director(w, _tl({"cap_start": 8, "cap_max": 8, "hell_cap": [0.5], "waves": [{"id": "h", "t": 0, "every": 1.0, "burst": 10, "channel": "hell", "enemy": d.id}]}))
	Run.elapsed = 0.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(4)
	assert_array(dir._hell_wave_ids()).is_equal([d.id])
	assert_float(dir._channel_room("hell")).is_equal_approx(0.0, 0.001)
	assert_float(dir._channel_room("regular")).is_equal_approx(8.0, 0.001)
	Run.elapsed = 1.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(4)


func test_a_wave_rolls_one_alternative_a_run_by_chance() -> void:
	var a := _test_def("w53_alt_a", "skeleton", {})
	var b := _test_def("w53_alt_b", "skeleton", {})
	var w := _world(Vector3.ZERO)
	var dir := _director(w, _tl({"waves": [{"id": "w1", "t": 0, "burst": 1, "alts": [{"chance": 0.5, "enemy": a.id}, {"chance": 0.5, "enemy": b.id, "pack": 2, "stats": {"hp": 3}}]}]}))
	var seen: Dictionary = {}
	for seed in range(40):
		dir._rng.seed = seed
		dir._roll_waves()
		var alt: Dictionary = dir.wave_state("w1")["alt"]
		seen[str(alt["enemy"])] = true
		if str(alt["enemy"]) == b.id:
			assert_int(int(alt["pack"])).is_equal(2)
	assert_bool(seen.has(a.id)).override_failure_message("the first alternative never came up").is_true()
	assert_bool(seen.has(b.id)).override_failure_message("the second alternative never came up").is_true()
	# a chance of 0 never comes up; the chances are normalised, so 2 and 6 are a quarter and three quarters
	var dir2 := _director(w, _tl({"waves": [{"id": "w1", "t": 0, "burst": 1, "alts": [{"chance": 0.0, "enemy": a.id}, {"chance": 1.0, "enemy": b.id}]}]}))
	for seed in range(20):
		dir2._rng.seed = seed
		dir2._roll_waves()
		assert_str(str((dir2.wave_state("w1")["alt"] as Dictionary)["enemy"])).is_equal(b.id)
	var dir3 := _director(w, _tl({"waves": [{"id": "w1", "t": 0, "burst": 1, "alts": [{"chance": 2, "enemy": a.id}, {"chance": 6, "enemy": b.id}]}]}))
	var a_n := 0
	for seed in range(400):
		dir3._rng.seed = seed
		dir3._roll_waves()
		if str((dir3.wave_state("w1")["alt"] as Dictionary)["enemy"]) == a.id:
			a_n += 1
	assert_int(a_n).is_between(60, 140)
	# a wave without alternatives is its own: its enemy, pack and stats
	var dir4 := _director(w, _tl({"waves": [{"id": "w1", "t": 0, "burst": 1, "enemy": a.id, "pack": 3, "stats": {"hp": 7}}]}))
	var own: Dictionary = dir4.wave_state("w1")["alt"]
	assert_str(str(own["enemy"])).is_equal(a.id)
	assert_int(int(own["pack"])).is_equal(3)
	assert_int(int((own["stats"] as Dictionary)["hp"])).is_equal(7)


func test_a_wave_scatters_or_packs_and_toasts_once() -> void:
	var d := _test_def("w53_pattern", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var dir := _director(w, _tl({"waves": [{"id": "sc", "t": 0, "every": 1.0, "count": 12, "burst": 6, "pattern": "scatter", "enemy": d.id, "toast": "SWARM!", "respect_cap": false}]}))
	dir._rng.seed = 11
	Run.elapsed = 0.0
	dir._tick_waves()
	var idx := _alive_indices(em)
	assert_int(idx.size()).is_equal(6)
	assert_float(_max_spread(em, idx)).is_greater(6.0)
	assert_array(g.toasts).is_equal(["SWARM!"])
	Run.elapsed = 1.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(12)
	# the toast came once, at the first burst
	assert_array(g.toasts).is_equal(["SWARM!"])
	assert_bool(bool(dir.wave_state("sc")["toasted"])).is_true()
	# a pack stands together, in packs of the alt's `pack` when the burst is bigger
	var w2 := _world(Vector3.ZERO)
	var em2: EnemyManager = w2["em"]
	var dir2 := _director(w2, _tl({"waves": [{"id": "pk", "t": 0, "burst": 4, "enemy": d.id, "pack": 4, "respect_cap": false}]}))
	dir2._rng.seed = 11
	Run.elapsed = 0.0
	dir2._tick_waves()
	var idx2 := _alive_indices(em2)
	assert_int(idx2.size()).is_equal(4)
	assert_float(_max_spread(em2, idx2)).is_less(6.0)
	assert_array((w2["g"] as Node).toasts).is_empty()
	# a wave spawns the alt's variant
	var sk: EnemyDef = Registry.enemy("skeleton")
	if sk.variants.has("SK-B"):
		var w3 := _world(Vector3.ZERO)
		var em3: EnemyManager = w3["em"]
		var dir3 := _director(w3, _tl({"waves": [{"id": "v", "t": 0, "burst": 2, "enemy": "skeleton", "variant": "SK-B", "respect_cap": false}]}))
		Run.elapsed = 0.0
		dir3._tick_waves()
		var i3 := _alive_indices(em3)
		assert_int(i3.size()).is_equal(2)
		assert_str((em3.types[em3.type_idx[i3[0]]]["def"] as EnemyDef).type_key()).is_equal("skeleton@SK-B")


func test_a_wave_wears_its_elite_modifier_once_colour_is_open() -> void:
	var d := _test_def("w53_elite", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var mod_id := str(Registry.elites.keys()[0])
	var dir := _director(w, _tl({"colour_after_kills": 50, "waves": [{"id": "e", "t": 0, "every": 1.0, "burst": 2, "enemy": d.id, "elite": mod_id, "respect_cap": false}]}))
	em.colour_after_kills = 50
	Run.kills = 0
	Run.elapsed = 0.0
	dir._tick_waves()
	# plain until the run's fiftieth kill, like the elite events
	assert_int(em.alive_count()).is_equal(2)
	assert_int(_modded(em)).is_equal(0)
	Run.kills = 50
	Run.elapsed = 1.0
	dir._tick_waves()
	assert_int(em.alive_count()).is_equal(4)
	assert_int(_modded(em)).is_equal(2)
	for i in _alive_indices(em):
		if em.elite_idx[i] >= 0:
			assert_str((em.elites[em.elite_idx[i]] as EliteModDef).id).is_equal(mod_id)
	# "random": any one of them
	var w2 := _world(Vector3.ZERO)
	var em2: EnemyManager = w2["em"]
	var dir2 := _director(w2, _tl({"waves": [{"id": "r", "t": 0, "burst": 3, "enemy": d.id, "elite": "random", "respect_cap": false}]}))
	Run.elapsed = 0.0
	dir2._tick_waves()
	assert_int(_modded(em2)).is_equal(3)


# ---------------------------------------------------------------- the events

func test_weighted_lists_pick_by_weight() -> void:
	var w := _world(Vector3.ZERO)
	var dir := _director(w, _tl())
	dir._rng.seed = 1
	for k in range(50):
		assert_str(dir._pick_id(["a", "b"], [1, 0])).is_equal("a")
		assert_str(dir._pick_id(["a", "b"], [0, 1])).is_equal("b")
	var a_n := 0
	for k in range(2000):
		if dir._pick_id(["a", "b"], [3, 1]) == "a":
			a_n += 1
	assert_int(a_n).is_between(1350, 1650)
	# the old calls: a string as it is, a list without weights evenly
	assert_str(dir._pick_id("only")).is_equal("only")
	var seen: Dictionary = {}
	for k in range(200):
		seen[dir._pick_id(["a", "b", "c"])] = true
	assert_int(seen.size()).is_equal(3)
	# a weight missing past the end of the list weighs one
	var c_n := 0
	for k in range(2000):
		if dir._pick_id(["a", "b", "c"], [1, 1]) == "c":
			c_n += 1
	assert_int(c_n).is_between(530, 800)
	# the interval: a number as it is, [min, max] inside the range
	assert_float(dir._interval_of(90.0)).is_equal_approx(90.0, 0.001)
	assert_float(dir._interval_of(null)).is_equal_approx(90.0, 0.001)
	for k in range(100):
		assert_float(dir._interval_of([10, 20])).is_between(10.0, 20.0)


func test_chance_skips_an_event_and_jitter_moves_it_inside_its_range() -> void:
	var d := _test_def("w53_ev", "skeleton", {})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"events": [
		{"t": 50, "type": "swarm", "enemy": d.id, "count": 4, "chance": 0.0},
		{"t": 100, "type": "swarm", "enemy": d.id, "count": 3, "t_jitter": 20},
		{"t": 105, "type": "swarm", "enemy": d.id, "count": 2}]}))
	var moved := false
	for seed in range(12):
		dir._rng.seed = seed
		dir._roll_events()
		assert_int(dir._run_events.size()).is_equal(3)
		var skipped: Dictionary = {}
		var jittered: Dictionary = {}
		for e: Dictionary in dir._run_events:
			if int(e["_i"]) == 0:
				skipped = e
			elif int(e["_i"]) == 1:
				jittered = e
		assert_bool(bool(skipped.get("_skip", false))).is_true()
		assert_bool(bool(jittered.get("_skip", false))).is_false()
		var jt := float(jittered["t"])
		assert_float(jt).is_between(80.0, 120.0)
		if absf(jt - 100.0) > 0.5:
			moved = true
		# the copy is in order of its effective times
		for k in range(1, dir._run_events.size()):
			assert_float(float(dir._run_events[k]["t"])).is_greater_equal(float(dir._run_events[k - 1]["t"]))
	assert_bool(moved).override_failure_message("twelve rolls never moved the jittered event").is_true()
	# and it plays that way: nothing at 60 (the chance-0 swarm is skipped), both swarms by 130
	dir._rng.seed = 4
	dir._roll_events()
	dir._event_i = 0
	Run.elapsed = 60.0
	dir._process_events()
	assert_int(em.alive_count()).is_equal(0)
	assert_int(dir._event_i).is_equal(1)
	Run.elapsed = 130.0
	dir._process_events()
	assert_int(em.alive_count()).is_equal(5)
	assert_int(dir._event_i).is_equal(3)
	# the tools' jump: every event dated before the clock is stepped past
	dir.skip_events_before(79.0)
	assert_int(dir._event_i).is_equal(1)
	dir.skip_events_before(500.0)
	assert_int(dir._event_i).is_equal(3)
	# without chance or jitter the copy is the timeline in the timeline's order
	var plain := _director(w, _tl({"events": [{"t": 10, "type": "swarm", "enemy": d.id, "count": 1}, {"t": 20, "type": "swarm", "enemy": d.id, "count": 1}]}))
	plain._roll_events()
	assert_int(int(plain._run_events[0]["_i"])).is_equal(0)
	assert_int(int(plain._run_events[1]["_i"])).is_equal(1)
	assert_float(float(plain._run_events[1]["t"])).is_equal_approx(20.0, 0.001)
	assert_bool(plain._run_events[0].has("_skip")).is_false()


func test_the_boss_countdown_reads_the_rolled_time() -> void:
	var w := _world(Vector3.ZERO)
	var dir := _director(w, _tl({"events": [{"t": 100, "type": "boss", "enemy": "tumbleweed_king", "t_jitter": 30}, {"t": 300, "type": "boss", "enemy": "gila_grande", "chance": 0.0}]}))
	dir._rng.seed = 2
	dir._roll_events()
	Run.elapsed = 10.0
	var eff := float(dir._run_events[0]["t"])
	assert_float(eff).is_between(70.0, 130.0)
	assert_float(dir.next_boss_in()).is_equal_approx(eff - 10.0, 0.001)
	# past it, the skipped Gila is not counted down to
	Run.elapsed = eff + 1.0
	assert_float(dir.next_boss_in()).is_equal_approx(-1.0, 0.001)


func test_elite_every_draws_a_fresh_interval_inside_min_max() -> void:
	var d := _test_def("w53_ee", "skeleton", {})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var dir := _director(w, _tl({"roster": [{"t": 0, "enemy": d.id, "weight": 1}]}))
	Run.elapsed = 100.0
	dir._run_event({"type": "elite_every", "interval": [10, 20]})
	assert_int(dir._elite_timers.size()).is_equal(1)
	var nexts: Dictionary = {}
	for seed in range(8):
		dir._rng.seed = seed
		Run.elapsed = 100.0 + 50.0 * float(seed)
		dir._elite_timers[0]["next"] = Run.elapsed
		var before := _modded(em)
		dir._process_events()
		var nx := float(dir._elite_timers[0]["next"])
		assert_float(nx - Run.elapsed).is_between(10.0, 20.0)
		nexts[snappedf(nx - Run.elapsed, 0.01)] = true
		assert_int(_modded(em)).is_equal(before + 1)
	assert_int(nexts.size()).is_greater(1)
	# a plain number as before
	var dir2 := _director(w, _tl({"roster": [{"t": 0, "enemy": d.id, "weight": 1}]}))
	Run.elapsed = 0.0
	dir2._run_event({"type": "elite_every", "interval": 129})
	dir2._elite_timers[0]["next"] = 0.0
	dir2._process_events()
	assert_float(float(dir2._elite_timers[0]["next"])).is_equal_approx(129.0, 0.001)


func test_events_pass_stats_variant_weights_and_the_swarm_patterns_on() -> void:
	var d := _test_def("w53_evs", "skeleton", {"pack_size": 5, "cap_share": 1.0})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var dir := _director(w, _tl())
	dir._rng.seed = 9
	# a swarm through the spawn points with overrides on every creature
	dir._run_event({"type": "swarm", "enemy": [d.id, "w53_nobody"], "weights": [1, 0], "count": 6, "pattern": "scatter", "stats": {"hp": 77}})
	var idx := _alive_indices(em)
	assert_int(idx.size()).is_equal(6)
	assert_float(_max_spread(em, idx)).is_greater(6.0)
	for i in idx:
		assert_float(em.hp[i]).is_equal_approx(77.0, 0.001)
	assert_array(g.toasts).is_equal(["SWARM!"])
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 6, "pattern": "pack", "pack": 3})
	idx = _alive_indices(em)
	assert_int(idx.size()).is_equal(6)
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	# the ring as before
	dir._run_event({"type": "swarm", "enemy": d.id, "count": 8})
	idx = _alive_indices(em)
	assert_int(idx.size()).is_equal(8)
	for i in idx:
		assert_float(Vector2(em.pos[i].x, em.pos[i].z).length()).is_between(15.0, 17.0)
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	# an elite_boss and an elite with stats
	dir._run_event({"type": "elite_boss", "enemy": ["dune_scorpion"], "stats": {"hp_mult": 2.0}})
	assert_int(dir.elite_index).is_greater_equal(0)
	var sdef: EnemyDef = em.types[em.type_idx[dir.elite_index]]["def"]
	assert_float(sdef.hp).is_equal_approx(Registry.enemy("dune_scorpion").hp * 2.0, 0.001)
	assert_str(sdef.id).is_equal("dune_scorpion")
	var before := _modded(em)
	dir._run_event({"type": "elite", "enemy": d.id, "mod": str(Registry.elites.keys()[0]), "stats": {"damage": 9}})
	assert_int(_modded(em)).is_equal(before + 1)
	for i in _alive_indices(em):
		if em.elite_idx[i] >= 0:
			assert_int(int((em.types[em.type_idx[i]]["def"] as EnemyDef).override_stats.get("damage", 0))).is_equal(9)
	# a boss with stats, at the flats
	dir._run_event({"type": "boss", "enemy": "tumbleweed_king", "stats": {"boss": {"attacks": {"roll": false}}}})
	assert_int(em.boss_index).is_greater_equal(0)
	assert_int(dir.phase).is_equal(WaveDirector.Phase.BOSS)
	var bdef: EnemyDef = em.types[em.type_idx[em.boss_index]]["def"]
	var names: Array = []
	for a in bdef.boss.get("attacks", []):
		names.append(str(a.get("name", "")))
	assert_bool(names.has("roll")).is_false()
	assert_int(names.size()).is_equal((Registry.enemy("tumbleweed_king").boss["attacks"] as Array).size() - 1)


# ---------------------------------------------------------------- the stun

func test_a_stun_stops_walking_and_attacking_then_lets_go() -> void:
	var d := _test_def("w53_stun", "skeleton", {"brain": "chase"})
	var w := _world(Vector3.ZERO, true)
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var i := em.spawn(d.id, Vector3(6, 0, 0))
	em.state[i] = EnemyManager.STATE_MOVE
	em.stun(i, 1.0)
	assert_bool(em.is_stunned(i)).is_true()
	assert_float(em.stun_t[i]).is_equal_approx(1.0, 0.001)
	assert_object(em.tint_of(i)).is_equal(EnemyManager.STUN_TINT)
	assert_int(g.fx.motes).is_equal(5)
	var p0: Vector3 = em.pos[i]
	for k in range(30):
		em._physics_process(DT)
	# half a second in: not a step, still stunned, the motes came once
	assert_float(em.pos[i].distance_to(p0)).is_less(0.01)
	assert_bool(em.is_stunned(i)).is_true()
	em.stun(i, 0.2)
	assert_int(g.fx.motes).is_equal(5)
	assert_float(em.stun_t[i]).is_greater(0.2)
	for k in range(50):
		em._physics_process(DT)
	assert_bool(em.is_stunned(i)).is_false()
	assert_float(em.pos[i].x).override_failure_message("it never walked on after the stun").is_less(5.9)
	assert_object(em.tint_of(i)).is_not_equal(EnemyManager.STUN_TINT)
	# pass 70 (lane LINES, Slow Burn: "every status the game applies"): stretched by Ducktape's debuff duration now, as a
	# slow is; a caller that passes scaled = false keeps its seconds
	Run.debug_set_item("passive", "ducktape", 4)
	em.refresh_player_stats()
	assert_float(em.debuff_mult()).is_greater(1.0)
	em.stun(i, 1.0)
	assert_float(em.stun_t[i]).is_equal_approx(em.debuff_mult(), 0.001)
	em.stun_t[i] = 0.0
	em.stun(i, 1.0, false)
	assert_float(em.stun_t[i]).is_equal_approx(1.0, 0.001)


func test_a_stun_holds_a_ranged_creatures_shot_and_cancels_a_wind_up() -> void:
	var d := _test_def("w53_kite", "skeleton", {"brain": "kite", "ranged": {"keep_distance": 4.0, "range": 9.0, "cooldown": 2.5, "telegraph": 0.6, "straight": true, "projectile_speed": 12.0}})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var i := em.spawn(d.id, Vector3(6, 0, 0))
	em.state[i] = EnemyManager.STATE_MOVE
	em.cooldown[i] = 0.0
	em.stun(i, 1.0)
	for k in range(30):
		em._physics_process(DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_array(g.lines).is_empty()
	for k in range(50):
		em._physics_process(DT)
	# free again, it winds up its shot
	assert_bool(g.lines.is_empty()).is_false()
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)
	# a stun in the wind-up drops it: the red line never fires
	em.stun(i, 1.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.cooldown[i]).is_greater_equal(1.0)
	# a charger's charge is dropped too
	var c := _test_def("w53_charger", "bull_beetle", {"brain": "charge"})
	var j := em.spawn(c.id, Vector3(0, 0, 10))
	em.state[j] = EnemyManager.STATE_CHARGE
	em.charge_dir[j] = Vector3(0, 0, -1)
	em.timer[j] = 0.5
	em.stun(j, 1.0)
	assert_int(em.state[j]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.cooldown[j]).is_equal_approx(float(c.charge.get("cooldown", 4.0)), 0.001)
	assert_float(em.vel[j].length()).is_equal_approx(0.0, 0.001)
	# a scripted creature's attack is interrupted and its script waits
	var sidx := em.spawn("hammer_giant", Vector3(0, 0, -8))
	em.state[sidx] = EnemyManager.STATE_ATTACK
	em.timer[sidx] = 0.3
	em.atk_i[sidx] = 1
	em.stun(sidx, 1.0)
	assert_int(em.state[sidx]).is_equal(EnemyManager.STATE_MOVE)
	em.atk_t[sidx] = 0.0
	em._update_attacks(sidx, DT, em.player.global_position)
	assert_int(em.state[sidx]).is_equal(EnemyManager.STATE_MOVE)


func test_a_stun_never_touches_a_boss_an_elite_or_an_elite_modded_creature() -> void:
	var d := _test_def("w53_mod", "skeleton", {})
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	var b := em.spawn("tumbleweed_king", Vector3(20, 0, 0))
	em.stun(b, 2.0)
	assert_bool(em.is_stunned(b)).is_false()
	assert_float(em.stun_t[b]).is_equal_approx(0.0, 0.001)
	var e := em.spawn("dune_scorpion", Vector3(-20, 0, 0))
	em.stun(e, 2.0)
	assert_bool(em.is_stunned(e)).is_false()
	var m := em.spawn(d.id, Vector3(0, 0, -20), Registry.elites_list()[0])
	em.stun(m, 2.0)
	assert_bool(em.is_stunned(m)).is_false()
	var plain := em.spawn(d.id, Vector3(0, 0, 20))
	em.stun(plain, 2.0)
	assert_bool(em.is_stunned(plain)).is_true()
	# and nothing on a bad index or a dead one
	em.stun(-1, 1.0)
	em.stun(EnemyManager.MAX, 1.0)
	em.stun(plain, 0.0)
	assert_float(em.stun_t[plain]).is_equal_approx(2.0, 0.001)


# ---------------------------------------------------------------- the bite

func test_contact_cd_sets_the_bites_cadence() -> void:
	var d := _test_def("w53_bite", "skeleton", {"brain": "chase", "contact_cd": 0.6})
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn(d.id, Vector3(0.3, 0, 0))
	em.state[i] = EnemyManager.STATE_MOVE
	em.contact_cd[i] = 0.0
	for k in range(60):
		em._physics_process(DT)
	var slow: int = hero.hits
	assert_int(slow).is_between(2, 3)
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	hero.hits = 0
	var j := em.spawn(d.id, Vector3(0.3, 0, 0), null, 1.0, 1.0, "", {"contact_cd": 0.2})
	em.state[j] = EnemyManager.STATE_MOVE
	em.contact_cd[j] = 0.0
	for k in range(60):
		em._physics_process(DT)
	assert_int(hero.hits).is_between(4, 6)
	assert_int(hero.hits).is_greater(slow)
	# attack_rate_mult reaches the bite too
	em.kill_all()
	for k in range(3):
		em._physics_process(2.0)
	hero.hits = 0
	var q := em.spawn(d.id, Vector3(0.3, 0, 0), null, 1.0, 1.0, "", {"attack_rate_mult": 3.0})
	em.state[q] = EnemyManager.STATE_MOVE
	em.contact_cd[q] = 0.0
	for k in range(60):
		em._physics_process(DT)
	assert_int(hero.hits).is_between(4, 6)


# ---------------------------------------------------------------- the power-up roll

func test_a_creatures_own_pickup_weights_and_chance_rule_its_drops() -> void:
	var w := _world(Vector3.ZERO)
	var pk: Node = w["pickups"]
	var dir := _director(w, Registry.map("red_canyon").timeline)
	assert_float(float(dir.timeline.pickups.get("per_kill", 0.0))).is_greater(0.0)
	var d := _src()
	d.pickup_weights = {"heart": 1}
	d.pickup_chance_mult = 1000.0
	for k in range(5):
		dir.drop_pickup_from(d, Vector3.ZERO, false)
	assert_int(pk.specials.size()).is_equal(5)
	for s in pk.specials:
		assert_str(str(s["id"])).is_equal("heart")
	# a chance of nothing drops nothing, whatever the roster
	d.pickup_chance_mult = 0.0
	for k in range(5):
		dir.drop_pickup_from(d, Vector3.ZERO, false)
	assert_int(pk.specials.size()).is_equal(5)
	# an unknown id in the weights drops nothing either
	d.pickup_chance_mult = 1000.0
	d.pickup_weights = {"w53_no_such_pickup": 1}
	dir.drop_pickup_from(d, Vector3.ZERO, false)
	assert_int(pk.specials.size()).is_equal(5)
	# without weights the timeline's roster, as before
	d.pickup_weights = {}
	dir.drop_pickup_from(d, Vector3.ZERO, false)
	assert_int(pk.specials.size()).is_equal(6)


# ---------------------------------------------------------------- Red Canyon

func test_red_canyon_still_loads_and_its_roster_is_whole() -> void:
	var m: MapDef = Registry.map("red_canyon")
	var tl: WaveTimeline = m.timeline
	assert_object(tl).is_not_null()
	# as many waves as its JSON names (none when this pass shipped; the lead edits the map)
	var json := JsonContent.load_json("res://content/maps/red_canyon/red_canyon.json")
	var tld: Dictionary = json.get("timeline_data", {})
	var jw = tld.get("waves", [])
	assert_int(tl.waves.size()).is_equal((jw as Array).size() if jw is Array else 0)
	assert_bool(tl.roster.size() >= 1).is_true()
	for r in tl.roster:
		# pass 84 (lane SPAWN, re-pinned): a row may name a list or "roster" (the coloured-elite draw)
		var e = r.get("enemy", "")
		if str(e) == WaveTimeline.ROW_ENEMY_ROSTER:
			continue
		for id in (e if e is Array else [e]):
			assert_object(Registry.enemy(str(id))).override_failure_message("roster row names a missing creature: " + str(id)).is_not_null()
	# the director rolls it and ticks it without a word
	var w := _world(Vector3.ZERO)
	var dir := _director(w, tl)
	dir._roll_events()
	dir._roll_waves()
	assert_int(dir._run_events.size()).is_equal(tl.events.size())
	assert_int(dir._waves.size()).is_equal(tl.waves.size())
	Run.elapsed = 1.0
	dir._tick_waves()
	# every creature of the content still spawns as its own single type, and bites every 0.6 s
	for id in ["skeleton", "skeleton_knight", "fire_ant", "dust_mummy"]:
		var e: EnemyDef = Registry.enemy(id)
		assert_str(e.type_key()).is_equal(id)
		assert_float(e.contact_cd).is_equal_approx(0.6, 0.001)
		assert_float(e.pickup_chance_mult).is_equal_approx(1.0, 0.001)
		assert_bool(e.pickup_weights.is_empty()).is_true()
