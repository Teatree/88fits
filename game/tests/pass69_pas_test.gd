## Pass 69, lane PAS (Garry's items 4-9): five new passive items and the Magnet reworked. Counterpunch (an evade arms
## the next attack at double damage and a short attack-speed and move-speed boost), Heavyweight (attack damage per 10 max
## HP), Snake Oil (heals past full into a pink overheal, eaten first by hits, never by regen), Hot Springs (more max HP and
## regen, every heal pulses damage round the hero, one pulse every half second at most), Last Stand (a hit leaving him
## under 30%: half-speed time for 2 s of real time and more damage, a hidden 20 s cooldown, the clock always given back),
## and the Magnet: no pickup radius any more, random pulls of EXP gems only, their wait never named.
extends GdUnitTestSuite

const NEW := ["counterpunch", "heavyweight", "snake_oil", "hot_springs", "last_stand"]
## id -> [rarity, weight, max_level, {stat: its value at the top level}]
const DATA := {
	"counterpunch": ["uncommon", 8.0, 5, {"counter_damage": 1.0, "counter_haste": 0.4, "counter_speed": 0.27, "counter_seconds": 3.0}],
	"heavyweight": ["rare", 7.0, 5, {"heavyweight": 0.02}],
	"snake_oil": ["epic", 5.0, 3, {"overheal": 0.4}],
	"hot_springs": ["epic", 5.0, 3, {"heal_pulse": 4.0, "regen": 1.2}],
	"last_stand": ["epic", 5.0, 3, {"last_stand": 2.0}],
	"magnet": ["epic", 6.0, 5, {"xp_pull_radius": 8.5, "xp_pull_rate": 1.0}],
}

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
var _ended := false
func toast(_t, _c = null) -> void:
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

const DT := 1.0 / 60.0


func before_test() -> void:
	# nothing unlocked, no Mirror ranks: the base numbers
	Save.data = Save._default()


func after_test() -> void:
	Run.player_sheet.remove_source("test")
	Run.set_last_stand(false)
	Engine.time_scale = 1.0
	Run.arena = false
	Run.end()
	DamageNumbers.I = null


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _take(id: String, levels: int) -> void:
	for k in range(levels):
		assert_bool(Run.add_or_level_passive(id)).override_failure_message("%s level %d" % [id, k + 1]).is_true()


## The real hero (Astro) at full health on the run's sheet, never evading unless a test says so.
func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	return p


## A hit of `amount` on `p` with no untouchable time left over from the last.
func _hit(p: Player, amount: float) -> void:
	p.invuln = 0.0
	p.take_damage(amount, p.global_position + Vector3(1, 0, 0), {"by": "test"})


## A fake game round a fake hero at the origin, with the real crowd, effects and pickups.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var pm: PickupManager = PickupManager.new()
	pm.game = g
	g.add_child(pm)
	g.pickups = pm
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": fx, "tg": tg, "pm": pm}


func _creature(em: EnemyManager, at: Vector3, id := "skeleton", hp_mult := 50.0) -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	return i


# ---------------------------------------------------------------- the items

func test_five_new_items_and_the_magnet_with_their_numbers() -> void:
	assert_array(Registry.problems).is_empty()
	for id: String in DATA.keys():
		var p: PassiveDef = Registry.passive(id)
		assert_object(p).override_failure_message(id + " is missing").is_not_null()
		var want: Array = DATA[id]
		assert_str(p.rarity).override_failure_message(id + " rarity").is_equal(str(want[0]))
		assert_float(p.weight).override_failure_message(id + " weight").is_equal(float(want[1]))
		assert_int(p.max_level).override_failure_message(id + " levels").is_equal(int(want[2]))
		# a passive item: no line, no evolution, no quest, offered from stage 1, with its card line and the painter's prompt
		assert_bool(p.is_line()).is_false()
		assert_str(p.evolves_into).is_empty()
		assert_bool(p.hidden).is_false()
		assert_int(p.from_stage).is_less_equal(1)
		assert_object(Registry.quest_for("passive", id)).override_failure_message(id + " is locked").is_null()
		assert_str(p.text).override_failure_message(id + " has no card line").is_not_empty()
		assert_str(p.flavour).is_not_empty()
		assert_object(p.icon).override_failure_message(id + " has no icon").is_not_null()
		var d := JsonContent.load_json("res://content/passives/%s/%s.json" % [id, id])
		assert_str(str(d.get("art_prompt", ""))).override_failure_message(id + " has no art prompt").is_not_empty()
		_start()
		_take(id, p.max_level)
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " past its top").is_false()
		var top: Dictionary = want[3]
		for stat: String in top.keys():
			var base := float(StatSheet.PLAYER_DEFAULTS.get(stat, 0.0))
			if stat == "regen":
				base = Run.hero_sheet(Run.character, Run.level).get_stat("regen", 0.0)
			assert_float(Run.player_sheet.get_stat(stat, 0.0) - base).override_failure_message("%s %s" % [id, stat]).is_equal_approx(float(top[stat]), 0.0001)
		Run.end()
	# the first levels as the brief gives them
	_start()
	var at := {"counterpunch": {"counter_damage": 1.0, "counter_haste": 0.2, "counter_speed": 0.15, "counter_seconds": 2.0},
		"heavyweight": {"heavyweight": 0.01}, "snake_oil": {"overheal": 0.2}, "hot_springs": {"heal_pulse": 4.0},
		"last_stand": {"last_stand": 1.0}, "magnet": {"xp_pull_radius": 5.0, "xp_pull_rate": 0.0}}
	var hp0 := Run.player_sheet.get_stat("max_hp", 100.0)
	for id: String in at.keys():
		Run.add_or_level_passive(id)
		for stat: String in (at[id] as Dictionary).keys():
			assert_float(Run.player_sheet.get_stat(stat, 0.0)).override_failure_message(id + " " + stat).is_equal_approx(float(at[id][stat]), 0.0001)
	# Hot Springs' +20 max HP at level 1, +40 at level 3
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0) - hp0).is_equal_approx(20.0, 0.0001)
	_take("hot_springs", 2)
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0) - hp0).is_equal_approx(40.0, 0.0001)
	# Last Stand x2.5 at level 2
	Run.add_or_level_passive("last_stand")
	assert_float(Run.last_stand_mult()).is_equal_approx(2.5, 0.0001)


func test_the_texts_read_short_and_never_name_the_magnet_s_wait_or_last_stand_s_cooldown() -> void:
	for id: String in DATA.keys():
		var p: PassiveDef = Registry.passive(id)
		var lines: Array = [p.text, TextGen.passive_description(p, 1), TextGen.passive_description(p, p.max_level),
			TextGen.next_level_text(p, 1), TextGen.next_level_text(p, p.max_level)]
		for lv in range(1, p.max_level):
			lines.append(WItem.effect({"def": p, "level_from": lv, "level_to": lv + 1}))
		lines.append(WItem.effect({"def": p, "level_from": 0, "level_to": 1}))
		print("pass69 text  %-13s | %s" % [p.display_name, " | ".join(lines)])
		for s: String in lines:
			assert_bool(s.contains("_")).override_failure_message(id + " shows a raw stat: " + s).is_false()
			var c0 := s.substr(0, 1)
			assert_bool(c0 == c0.to_upper()).override_failure_message(id + " starts small: " + s).is_true()
		assert_int(p.text.length()).override_failure_message(id + " card line is long").is_less_equal(150)
	# the Magnet: radius in metres, "more often" in words, never a second
	var mg: PassiveDef = Registry.passive("magnet")
	assert_str(TextGen.next_level_text(mg, 1)).is_equal("Next level: +1 m EXP pull radius, pulls more often")
	assert_str(WItem.effect({"def": mg, "level_from": 1, "level_to": 2})).is_equal("Next: +1 m EXP pull radius, pulls more often.")
	assert_str(TextGen.passive_description(mg, 5)).is_equal("Level 5: +8.5 m EXP pull radius total.")
	var a_wait := RegEx.create_from_string("\\d(\\.\\d+)?\\s*(s\\b|sec|second)")
	for lv in range(1, 6):
		for s: String in [TextGen.passive_description(mg, lv), TextGen.next_level_text(mg, lv), mg.text,
				WItem.effect({"def": mg, "level_from": lv, "level_to": mini(lv + 1, 5)})]:
			assert_object(a_wait.search(s)).override_failure_message("the Magnet names its wait: " + s).is_null()
	for row: Dictionary in TextGen.passive_changes(mg, 1, 2):
		assert_str(str(row["stat"])).is_equal("xp_pull_radius")
	assert_str(TextGen.describe_effect(Effect.make("xp_pull_rate", "add", 0.25, "player"))).is_equal("pulls more often")
	assert_str(TextGen.describe_effects([Effect.make("xp_pull_rate", "add", 0.0, "player")])).is_empty()
	# Last Stand never names its cooldown
	var ls: PassiveDef = Registry.passive("last_stand")
	for s: String in [ls.text, TextGen.passive_description(ls, 3), TextGen.next_level_text(ls, 1)]:
		assert_bool(s.contains("20 s") or s.contains("cooldown")).override_failure_message("Last Stand names its cooldown: " + s).is_false()
	assert_str(TextGen.passive_description(ls, 3)).is_equal("Level 3: +200% attack damage in Last Stand total.")
	assert_str(TextGen.passive_description(Registry.passive("heavyweight"), 1)).starts_with("+1% attack damage per 10 max HP at level 1")
	assert_str(TextGen.passive_description(Registry.passive("snake_oil"), 2)).is_equal("Level 2: +30% overheal past full health total.")


# ---------------------------------------------------------------- Counterpunch

func test_counterpunch_arms_the_next_attack_once_and_its_boost_times_out() -> void:
	_start()
	var speed := Run.player_sheet.get_stat("move_speed", 0.0)
	var haste := Run.player_sheet.get_stat("haste", 1.0)
	# without the item an evade does nothing
	assert_bool(Run.counterpunch_evaded()).is_false()
	assert_bool(Run.counter_armed).is_false()
	Run.add_or_level_passive("counterpunch")
	assert_bool(Run.counterpunch_evaded()).is_true()
	assert_bool(Run.counter_armed).is_true()
	# the boost: 20% attack speed, 15% move speed for 2 s, quiet
	assert_float(Run.player_sheet.get_stat("haste", 1.0)).is_equal_approx(haste * 1.2, 0.0001)
	assert_float(Run.haste).is_equal_approx(haste * 1.2, 0.0001)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.15, 0.0001)
	assert_float(Run.boost_left(Run.COUNTERPUNCH)).is_equal_approx(2.0, 0.0001)
	# nothing fired yet: no weapon hits double
	assert_float(Run.counterpunch_mult("revolver")).is_equal(1.0)
	# the revolver fires first: its hits are doubled, another weapon's are not, the arm is spent
	Run.counterpunch_fired("revolver")
	assert_bool(Run.counter_armed).is_false()
	assert_float(Run.counterpunch_mult("revolver")).is_equal_approx(2.0, 0.0001)
	assert_float(Run.counterpunch_mult("tommy_gun")).is_equal(1.0)
	# another weapon firing changes nothing; the revolver's next shot is its next attack: no more double
	Run.counterpunch_fired("tommy_gun")
	assert_float(Run.counterpunch_mult("revolver")).is_equal_approx(2.0, 0.0001)
	Run.counterpunch_fired("revolver")
	assert_float(Run.counterpunch_mult("revolver")).is_equal(1.0)
	# an attack whose hits come late: the window closes after COUNTER_HIT_WINDOW of the buffs' clock
	Run.counterpunch_evaded()
	Run.counterpunch_fired("hammer")
	Run.elapsed += Run.COUNTER_HIT_WINDOW * 0.5
	assert_float(Run.counterpunch_mult("hammer")).is_equal_approx(2.0, 0.0001)
	Run.elapsed += Run.COUNTER_HIT_WINDOW
	assert_float(Run.counterpunch_mult("hammer")).is_equal(1.0)
	# the boost runs out without a toast, the numbers back
	Run.elapsed += 2.5
	assert_array(Run.tick_timed()).is_empty()
	assert_float(Run.boost_left(Run.COUNTERPUNCH)).is_equal(0.0)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed, 0.0001)
	assert_float(Run.player_sheet.get_stat("haste", 1.0)).is_equal_approx(haste, 0.0001)
	# levels: longer and stronger, and an evade after a level takes the new numbers
	_take("counterpunch", 4)
	Run.counterpunch_evaded()
	assert_float(Run.boost_left(Run.COUNTERPUNCH)).is_equal_approx(3.0, 0.0001)
	assert_float(Run.player_sheet.get_stat("haste", 1.0)).is_equal_approx(haste * 1.4, 0.0001)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.27, 0.0001)
	assert_int(Run.timed.filter(func(t: Dictionary) -> bool: return t["id"] == Run.COUNTERPUNCH).size()).is_equal(1)


func test_an_evade_on_the_real_hero_arms_it_and_the_crowd_takes_double_from_that_attack() -> void:
	_start()
	Run.add_or_level_passive("counterpunch")
	var p := _hero()
	Run.player_sheet.add_effects([Effect.make("evade", "add", 1.0, "player")], "test")
	# evade is capped at 90%: a few tries
	for k in range(60):
		_hit(p, 1.0)
		if p.last_outcome == "evaded":
			break
	assert_str(p.last_outcome).is_equal("evaded")
	assert_bool(Run.counter_armed).is_true()
	Run.player_sheet.remove_source("test")
	# the hit on a creature: a plain hit, then the counter-attack's
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(2, 0, 0))
	var j := _creature(em, Vector3(-2, 0, 0))
	var h0: float = em.hp[i]
	em.damage(i, 10.0, "revolver")
	var plain: float = h0 - em.hp[i]
	assert_float(plain).is_greater(0.0)
	Run.counterpunch_fired("revolver")
	var h1: float = em.hp[j]
	em.damage(j, 10.0, "revolver")
	assert_float(h1 - em.hp[j]).is_equal_approx(plain * 2.0, 0.001)
	# a poison or fire tick of it is never doubled
	var h2: float = em.hp[j]
	em.damage(j, 10.0, "revolver", Vector3.ZERO, 0.0, true)
	assert_float(h2 - em.hp[j]).is_equal_approx(plain, 0.001)


func test_every_weapon_fire_tells_counterpunch() -> void:
	var src := FileAccess.get_file_as_string("res://core/behaviors/WeaponBehavior.gd")
	assert_bool(src.contains("Run.counterpunch_fired(inst.def.id)")).is_true()


# ---------------------------------------------------------------- Heavyweight

func test_heavyweight_grows_with_max_hp_in_whole_tens() -> void:
	_start()
	var might := Run.player_sheet.get_stat("might", 1.0)
	var mhp := Run.player_sheet.get_stat("max_hp", 100.0)
	Run.add_or_level_passive("heavyweight")
	var steps := floorf(mhp / 10.0 + 0.0001)
	assert_float(Run.heavyweight_might()).is_equal_approx(0.01 * steps, 0.0001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might * (1.0 + 0.01 * steps), 0.0001)
	# more max HP (Vigour), more damage: the source follows
	_take("vigour", 2)
	var mhp2 := Run.player_sheet.get_stat("max_hp", 100.0)
	assert_float(mhp2).is_greater(mhp)
	var steps2 := floorf(mhp2 / 10.0 + 0.0001)
	assert_float(Run.heavyweight_might()).is_equal_approx(0.01 * steps2, 0.0001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might * (1.0 + 0.01 * steps2), 0.0001)
	# one source, named with its bonus, through a rebuild too
	Run.rebuild_sheets()
	var named := 0
	for en: Dictionary in Run.player_sheet.entries:
		if str(en["source"]).begins_with("Heavyweight +"):
			named += 1
	assert_int(named).is_equal(1)
	# level 5: +2% per 10
	_take("heavyweight", 4)
	assert_float(Run.heavyweight_might()).is_equal_approx(0.02 * steps2, 0.0001)
	# only whole tens count: 5 more max HP than a whole ten adds nothing
	var tens := floorf(Run.player_sheet.get_stat("max_hp", 100.0) / 10.0 + 0.0001)
	Run.player_sheet.add_effects([Effect.make("max_hp", "add", tens * 10.0 + 5.0 - Run.player_sheet.get_stat("max_hp", 100.0), "player")], "test")
	Run._apply_heavyweight()
	assert_float(Run.heavyweight_might()).is_equal_approx(0.02 * tens, 0.0001)


# ---------------------------------------------------------------- Snake Oil

func test_snake_oil_heals_past_full_up_to_its_cap_and_hits_take_it_first() -> void:
	_start()
	var p := _hero()
	# without the item a heal stops at full
	p.hp = p.max_hp - 5.0
	p.heal(30.0)
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)
	assert_float(p.overheal).is_equal(0.0)
	Run.add_or_level_passive("snake_oil")
	p.refresh_stats()
	var cap := p.max_hp * 0.2
	assert_float(p.overheal_cap()).is_equal_approx(cap, 0.001)
	# a heal over full: the rest is overheal, never past the cap
	p.hp = p.max_hp - 5.0
	p.heal(10.0)
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)
	assert_float(p.overheal).is_equal_approx(5.0, 0.001)
	p.heal(500.0)
	assert_float(p.overheal).is_equal_approx(cap, 0.001)
	# regen stops at full: it never adds to it, and never takes it away
	p.overheal = 3.0
	p.regen_hold = 0.0
	Run.player_sheet.add_effects([Effect.make("regen", "add", 50.0, "player")], "test")
	for k in range(30):
		p._tick_regen(DT)
	assert_float(p.overheal).is_equal_approx(3.0, 0.001)
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)
	Run.player_sheet.remove_source("test")
	# a hit takes the overheal first, then his health
	p.overheal = cap
	var dr := clampf(Run.player_sheet.get_stat("damage_reduction", 0.0), 0.0, 0.8)
	var full := p.max_hp
	_hit(p, cap * 0.5 / (1.0 - dr))
	assert_str(p.last_outcome).is_equal("hit")
	assert_float(p.overheal).is_equal_approx(cap * 0.5, 0.01)
	assert_float(p.hp).is_equal_approx(full, 0.01)
	_hit(p, (cap * 0.5 + 10.0) / (1.0 - dr))
	assert_float(p.overheal).is_equal_approx(0.0, 0.01)
	assert_float(p.hp).is_equal_approx(full - 10.0, 0.01)
	# levels raise the cap; losing the item drops what is over it
	_take("snake_oil", 2)
	p.refresh_stats()
	assert_float(p.overheal_cap()).is_equal_approx(p.max_hp * 0.4, 0.001)
	p.hp = p.max_hp
	p.heal(500.0)
	assert_float(p.overheal).is_equal_approx(p.max_hp * 0.4, 0.001)
	Run.passives.erase("snake_oil")
	Run.rebuild_sheets()
	p.refresh_stats()
	assert_float(p.overheal).is_equal(0.0)


func test_the_hp_bar_draws_the_overheal_as_a_pink_extension() -> void:
	var src := FileAccess.get_file_as_string("res://ui/HUD.gd")
	assert_bool(src.contains("_over_frac")).is_true()
	assert_bool(src.contains("OVERHEAL_PINK")).is_true()
	var hud_script: GDScript = load("res://ui/HUD.gd")
	assert_bool((hud_script.get_script_constant_map()["OVERHEAL_PINK"] as Color).is_equal_approx(Color("e86aa8"))).is_true()


# ---------------------------------------------------------------- Hot Springs

func test_hot_springs_pulses_on_every_heal_at_most_every_half_second() -> void:
	_start()
	var p := _hero()
	var got: Array = []
	p.heal_pulsed.connect(func(d: float, h: float): got.append([d, h]))
	# without the item nothing pulses
	p.hp = p.max_hp - 20.0
	p.heal(10.0)
	p._tick_heal_pulse(DT)
	assert_int(got.size()).is_equal(0)
	Run.add_or_level_passive("hot_springs")
	p.refresh_stats()
	# a heal of 10: 4 + 2 x 10 = 24
	p.hp = p.max_hp - 30.0
	p.heal(10.0)
	p._tick_heal_pulse(DT)
	assert_int(got.size()).is_equal(1)
	assert_float(float(got[0][0])).is_equal_approx(24.0, 0.001)
	assert_float(float(got[0][1])).is_equal_approx(10.0, 0.001)
	# another heal at once waits for the half second, then goes out with all that came since
	p.heal(3.0)
	p._tick_heal_pulse(0.2)
	p.heal(2.0)
	p._tick_heal_pulse(0.2)
	assert_int(got.size()).is_equal(1)
	p._tick_heal_pulse(0.11)
	assert_int(got.size()).is_equal(2)
	assert_float(float(got[1][0])).is_equal_approx(4.0 + 2.0 * 5.0, 0.001)
	# a big heal is capped at 40
	p.hp = 1.0
	p._pulse_cd = 0.0
	p.heal(100.0)
	p._tick_heal_pulse(DT)
	assert_float(float(got[2][0])).is_equal_approx(40.0, 0.001)
	assert_float(Player.heal_pulse_damage(4.0, 100.0)).is_equal(40.0)
	# regen's ticks count too
	p.hp = p.max_hp - 20.0
	p.regen_hold = 0.0
	p._pulse_cd = 0.0
	p._tick_regen(1.0)
	p._tick_heal_pulse(DT)
	assert_int(got.size()).is_equal(4)
	assert_float(float(got[3][1])).is_greater(0.4)
	# nothing healed (full), nothing sent
	p.hp = p.max_hp
	p._pulse_cd = 0.0
	p.heal(10.0)
	p._tick_heal_pulse(DT)
	assert_int(got.size()).is_equal(4)


func test_a_heal_pulse_hurts_the_creatures_within_three_metres() -> void:
	_start()
	var w := _world()
	var em: EnemyManager = w["em"]
	var near := _creature(em, Vector3(2.0, 0, 0))
	var far := _creature(em, Vector3(6.0, 0, 0))
	var h_near: float = em.hp[near]
	var h_far: float = em.hp[far]
	var gs: GDScript = load("res://game/Game.gd")
	var g = gs.new()
	g.player = _hero()
	g.player.global_position = Vector3.ZERO
	g.enemies = em
	g.telegraphs = w["tg"]
	g._heal_pulse(24.0, 10.0)
	assert_float(h_near - em.hp[near]).is_equal_approx(24.0 * (1.0 - em.dr[near]), 0.01)
	assert_float(em.hp[far]).is_equal(h_far)
	# recorded as the passive's own source
	assert_float(float(Run.damage_by_weapon.get("hot_springs", 0.0))).is_greater(0.0)
	g.free()


# ---------------------------------------------------------------- Last Stand

func test_last_stand_fires_under_thirty_percent_once_in_twenty_seconds() -> void:
	_start()
	var might := Run.player_sheet.get_stat("might", 1.0)
	# without the item: nothing
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_false()
	Run.add_or_level_passive("last_stand")
	# not low enough, or already down: nothing
	assert_bool(Run.last_stand_check(30.0, 100.0)).is_false()
	assert_bool(Run.last_stand_check(0.0, 100.0)).is_false()
	# under 30%: it starts, double damage on the sheet
	assert_bool(Run.last_stand_check(29.0, 100.0)).is_true()
	assert_bool(Run.last_stand_active).is_true()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might * 2.0, 0.0001)
	# kept through a rebuild while it runs
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might * 2.0, 0.0001)
	Run.set_last_stand(false)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might, 0.0001)
	# the hidden cooldown: not again for 20 s of the buffs' clock
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_false()
	Run.elapsed += 19.0
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_false()
	Run.held_time += 1.01
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_true()
	Run.set_last_stand(false)
	# level 3: x3
	_take("last_stand", 2)
	Run.elapsed += 25.0
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_true()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might * 3.0, 0.0001)


func test_a_hit_that_leaves_the_hero_low_tells_the_game_once() -> void:
	_start()
	Run.add_or_level_passive("last_stand")
	var p := _hero()
	var told: Array = []
	p.last_stand.connect(func(): told.append(Run.elapsed))
	var dr := clampf(Run.player_sheet.get_stat("damage_reduction", 0.0), 0.0, 0.8)
	_hit(p, p.max_hp * 0.5 / (1.0 - dr))
	assert_int(told.size()).is_equal(0)
	_hit(p, p.max_hp * 0.25 / (1.0 - dr))
	assert_int(told.size()).is_equal(1)
	assert_bool(Run.last_stand_active).is_true()
	Run.set_last_stand(false)
	_hit(p, 1.0)
	assert_int(told.size()).is_equal(1)


func test_the_slowed_time_runs_two_real_seconds_waits_out_a_pause_and_always_gives_the_clock_back() -> void:
	_start()
	Run.add_or_level_passive("last_stand")
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var fx := LastStandFx.new()
	fx.game = g
	g.add_child(fx)
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_true()
	fx.start()
	assert_float(Engine.time_scale).is_equal_approx(Run.LAST_STAND_SCALE, 0.0001)
	assert_bool(fx.active).is_true()
	fx.tick_real(1.0)
	assert_float(Engine.time_scale).is_equal_approx(0.5, 0.0001)
	assert_float(fx.left).is_equal_approx(1.0, 0.0001)
	# a screen comes up (the card screen, the pause board): the clock is normal and the seconds wait
	g.paused = true
	fx.tick_real(5.0)
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_float(fx.left).is_equal_approx(1.0, 0.0001)
	assert_bool(Run.last_stand_active).is_true()
	g.paused = false
	fx.tick_real(0.5)
	assert_float(Engine.time_scale).is_equal_approx(0.5, 0.0001)
	fx.tick_real(0.6)
	assert_bool(fx.active).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(Run.last_stand_active).is_false()
	# the hero falls in the middle of it: over at once
	Run.elapsed += 30.0
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_true()
	fx.start()
	hero.dead = true
	fx.tick_real(0.1)
	assert_bool(fx.active).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(Run.last_stand_active).is_false()
	# the node going away mid-way gives the clock back too
	hero.dead = false
	Run.elapsed += 30.0
	assert_bool(Run.last_stand_check(10.0, 100.0)).is_true()
	fx.start()
	assert_float(Engine.time_scale).is_equal_approx(0.5, 0.0001)
	g.remove_child(fx)
	fx.free()
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(Run.last_stand_active).is_false()
	# the heartbeat swells and falls back
	assert_float(LastStandFx.beat_at(0.02)).is_greater(0.9)
	assert_float(LastStandFx.beat_at(0.4)).is_less(0.1)


func test_last_stand_looks_like_nothing_high_noon_draws() -> void:
	var sh := FileAccess.get_file_as_string("res://core/shaders/last_stand.gdshader")
	assert_bool(sh.contains("hint_screen_texture")).is_true()
	assert_bool(sh.contains("beat")).is_true()
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game_src.contains("player.last_stand.connect(_last_stand)")).is_true()


# ---------------------------------------------------------------- the Magnet

func test_the_magnet_gives_no_pickup_radius_and_pulls_only_gems_within_its_reach() -> void:
	_start()
	var w := _world()
	var pm: PickupManager = w["pm"]
	var reach := Run.player_sheet.get_stat("magnet", 1.5)
	Run.add_or_level_passive("magnet")
	assert_float(Run.player_sheet.get_stat("magnet", 1.5)).is_equal_approx(reach, 0.0001)
	assert_float(pm.xp_pull_radius()).is_equal_approx(5.0, 0.0001)
	# gems about 3 m and 3.5 m away, one about 9 m, a coin about 4 m (they land a little off where they were let go)
	var a := pm.spawn(PickupManager.KIND_GEM_S, Vector3(3, 0, 0), 1.0)
	var b := pm.spawn(PickupManager.KIND_GEM_L, Vector3(0, 0, 3.5), 25.0)
	var c := pm.spawn(PickupManager.KIND_GEM_M, Vector3(-9, 0, 0), 5.0)
	var coin := pm.spawn(PickupManager.KIND_COIN, Vector3(0, 0, -4), 1.0)
	# let them land and lie in the grid
	for k in range(90):
		pm._physics_process(DT)
	var inside: Array = []
	for i in [a, b, c, coin]:
		assert_int(pm.alive[i]).is_equal(1)
		assert_int(pm.flying[i]).is_equal(0)
		if i != coin and Vector2(pm.pos[i].x, pm.pos[i].z).length() < 5.0:
			inside.append(i)
	assert_int(inside.size()).is_greater_equal(2)
	var n := pm.pull_xp(Vector3.ZERO, pm.xp_pull_radius())
	assert_int(n).is_equal(inside.size())
	for i in [a, b, c]:
		assert_int(pm.flying[i]).is_equal(1 if inside.has(i) else 0)
	assert_int(pm.flying[coin]).is_equal(0)
	# on the magnet arc, the big pull's look
	assert_int(pm.arced[a]).is_equal(1)
	# nothing pulled twice
	assert_int(pm.pull_xp(Vector3.ZERO, 5.0)).is_equal(0)
	# level 5: 8.5 m, and never past it
	_take("magnet", 4)
	assert_float(pm.xp_pull_radius()).is_equal_approx(8.5, 0.0001)
	Run.player_sheet.add_effects([Effect.make("xp_pull_radius", "add", 10.0, "player")], "test")
	assert_float(pm.xp_pull_radius()).is_equal_approx(PickupManager.XP_PULL_MAX_R, 0.0001)
	assert_float(PickupManager.XP_PULL_MAX_R).is_equal(8.5)


func test_the_magnet_s_pulls_come_at_random_waits_faster_with_levels() -> void:
	assert_bool(PickupManager.xp_pull_span(0.0).is_equal_approx(Vector2(3.0, 8.0))).is_true()
	assert_bool(PickupManager.xp_pull_span(1.0).is_equal_approx(Vector2(1.5, 4.0))).is_true()
	_start()
	var w := _world()
	var pm: PickupManager = w["pm"]
	# no item: no pulls ever
	for k in range(60 * 20):
		pm._tick_xp_pulls(DT, Vector3.ZERO)
	assert_int(pm.xp_pulls).is_equal(0)
	Run.add_or_level_passive("magnet")
	var waits: Array = []
	for k in range(300):
		waits.append(pm.xp_pull_wait())
	waits.sort()
	assert_float(float(waits[0])).is_greater_equal(3.0)
	assert_float(float(waits[waits.size() - 1])).is_less_equal(8.0)
	# random: not all the same, and both ends of the span reached roughly
	assert_float(float(waits[waits.size() - 1]) - float(waits[0])).is_greater(3.0)
	# a minute of ticks at level 1: between 7 and 20 pulls
	for k in range(60 * 60):
		pm._tick_xp_pulls(DT, Vector3.ZERO)
	assert_int(pm.xp_pulls).is_between(7, 21)
	_take("magnet", 4)
	for k in range(300):
		var wt := pm.xp_pull_wait()
		assert_float(wt).is_between(1.5, 4.0)
	var pulls0 := pm.xp_pulls
	for k in range(60 * 60):
		pm._tick_xp_pulls(DT, Vector3.ZERO)
	assert_int(pm.xp_pulls - pulls0).is_between(15, 41)
