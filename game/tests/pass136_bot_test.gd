extends GdUnitTestSuite

## Pass 136, lane BOT (the proposal's R9, docs/weapons_aim; Garry: "R9 - Yes, and it would be ok if he were especially
## good at it"): the bot learns to aim by moving while every weapon aims where the Outlaw faces (Settings.aim_mode).
## The attack lean (BotLegs.lean_dir), the thickest front (BotLegs.pack_of), R1's small push (BotLegs.push_turn), the
## `aim` dial in the presets, the turn-and-fire beat synced to a weapon's shot, and nothing of it with the switch off.

const BOT := preload("res://tools/bot/Bot.gd")
const LEGS := preload("res://tools/bot/BotLegs.gd")
const SIM := preload("res://tools/sim_run.gd")

var _aim_was = null


func before_test() -> void:
	var st := get_tree().root.get_node_or_null("Settings")
	_aim_was = st.get("aim_mode") if st != null else null


func after_test() -> void:
	var st := get_tree().root.get_node_or_null("Settings")
	if st != null and _aim_was != null:
		st.set("aim_mode", _aim_was)


# ---------------------------------------------------------------- fakes

class FakeInput:
	extends RefCounted
	var wants_move := false
	var origin := Vector2.ZERO
	var touch_pos := Vector2.ZERO


class FakePlayer:
	extends Node3D
	var input := FakeInput.new()
	var hp := 100.0
	var max_hp := 100.0
	var dead := false
	var face := Vector3.FORWARD

	func forward() -> Vector3:
		return face


class FakeDef:
	extends RefCounted
	var id := "goblin"
	var archetype := "swarm"


class FakeEnemies:
	extends RefCounted
	const MAX := 32
	var alive := PackedByteArray()
	var hidden := PackedByteArray()
	var pos := PackedVector3Array()
	var type_idx := PackedInt32Array()
	var types: Array = []

	func _init() -> void:
		alive.resize(MAX)
		hidden.resize(MAX)
		pos.resize(MAX)
		type_idx.resize(MAX)
		types = [{"def": FakeDef.new()}]

	func put(i: int, at: Vector3) -> void:
		alive[i] = 1
		pos[i] = at


class FakeInst:
	extends RefCounted
	var params := {"aim": {"family": "aimed", "cone": 60}}


class FakeWeapon:
	extends RefCounted
	var inst := FakeInst.new()
	var cooldown_left := 0.05

	func stat(name: String, default: float = 0.0) -> float:
		match name:
			"cooldown":
				return 1.0
			"range":
				return 14.0
		return default


class FakeGame:
	extends Node
	var player: FakePlayer
	var map = null
	var enemies := FakeEnemies.new()
	var pickups = null
	var projectiles = null
	var paused := false
	var portal = null
	var _behaviors := {}


func _fake_game() -> FakeGame:
	var g: FakeGame = auto_free(FakeGame.new())
	g.player = FakePlayer.new()
	add_child(g)
	g.add_child(g.player)
	return g


static func _deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))


func _set_aim(on: bool) -> void:
	var st := get_tree().root.get_node_or_null("Settings")
	if st != null:
		st.set("aim_mode", on)


# ---------------------------------------------------------------- the lean's maths

func test_the_lean_brings_the_way_within_the_arc_when_the_crowd_is_far() -> void:
	var p := Vector3(1, 0, 0)
	var k := Vector3(0, 0, 2)   # 90 degrees off the pack, length 2
	var far := LEGS.lean_dir(k, p, 1.0, 20.0, 4.5, 2.6)
	assert_float(absf(_deg(p, far))).is_equal_approx(LEGS.ARC_DEG, 0.01)
	assert_float(far.length()).is_equal_approx(2.0, 0.0001)
	# the side is kept: the way stays on the side it was
	assert_float(_deg(p, far)).is_greater(0.0)
	var other := LEGS.lean_dir(Vector3(0, 0, -2), p, 1.0, 20.0, 4.5, 2.6)
	assert_float(_deg(p, other)).is_less(0.0)
	# half the weight: half way from 90 to the arc
	var half := LEGS.lean_dir(k, p, 0.5, 20.0, 4.5, 2.6)
	assert_float(absf(_deg(p, half))).is_equal_approx(90.0 - 0.5 * (90.0 - LEGS.ARC_DEG), 0.01)


func test_no_lean_inside_the_keep_band_and_a_blend_just_past_it() -> void:
	var p := Vector3(1, 0, 0)
	var back := Vector3(-0.3, 0, 1)   # mostly sideways, a little away (the kite's way in the band)
	# in the band, and just past keep by less than LEAN_FROM: the kite's way whole
	assert_vector(LEGS.lean_dir(back, p, 1.0, 4.0, 4.5, 2.6)).is_equal(back)
	assert_vector(LEGS.lean_dir(back, p, 1.0, 4.5 + LEGS.LEAN_FROM * 0.9, 4.5, 2.6)).is_equal(back)
	# under flee: the escape is whole
	assert_vector(LEGS.lean_dir(back, p, 1.0, 2.0, 4.5, 2.6)).is_equal(back)
	# weight 0, or no pack: the old way
	assert_vector(LEGS.lean_dir(back, p, 0.0, 20.0, 4.5, 2.6)).is_equal(back)
	assert_vector(LEGS.lean_dir(back, Vector3.ZERO, 1.0, 20.0, 4.5, 2.6)).is_equal(back)
	# a way already inside the limit is kept
	var inside := Vector3(1, 0, 0.2)
	assert_vector(LEGS.lean_dir(inside, p, 1.0, 20.0, 4.5, 2.6)).is_equal(inside)
	# half way through the blend the limit is half way from no lean (180) to the arc
	var mid_d := 4.5 + LEGS.LEAN_FROM + LEGS.KEEP_BLEND * 0.5
	var lim := (180.0 + LEGS.ARC_DEG) * 0.5
	var away := Vector3(-1, 0, 0.18)   # about 170 degrees off the pack
	assert_float(absf(_deg(p, LEGS.lean_dir(away, p, 1.0, mid_d, 4.5, 2.6)))).is_equal_approx(lim, 0.01)
	# a sideways way (90) is inside that limit: kept
	assert_vector(LEGS.lean_dir(Vector3(0, 0, 1), p, 1.0, mid_d, 4.5, 2.6)).is_equal(Vector3(0, 0, 1))


func test_the_thickest_front_is_the_heaviest_sixty_degree_window() -> void:
	assert_vector(LEGS.pack_of(PackedVector2Array(), PackedFloat32Array())).is_equal(Vector3.ZERO)
	# three to the east (spread 20 degrees), one heavier-looking pair to the west that weighs less
	var rel := PackedVector2Array([Vector2(5, 0), Vector2(5, 1.0), Vector2(5, -1.0), Vector2(-5, 0), Vector2(-5, 0.5)])
	var w := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0])
	var east := LEGS.pack_of(rel, w)
	assert_float(absf(_deg(Vector3(1, 0, 0), east))).is_less(3.0)
	assert_float(east.length()).is_equal_approx(3.0, 0.001)
	# an Elite to the west (weight x3 and more) wins
	w[3] = 5.0
	var west := LEGS.pack_of(rel, w)
	assert_float(absf(_deg(Vector3(-1, 0, 0), west))).is_less(6.0)


func test_the_small_push_is_past_the_dead_zone_and_under_fifteen_percent() -> void:
	var inp := FakeInput.new()
	LEGS.push_turn(inp, Vector3(0, 0, 1))
	var v := inp.touch_pos - inp.origin
	assert_bool(inp.wants_move).is_true()
	# the fake has no radius_px: a 60 px stick, a 6 px dead zone
	assert_float(v.length()).is_greater(6.0)
	assert_float(v.length() / 60.0).is_less(0.15)
	assert_float(v.normalized().y).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- the dial and the switch

func test_every_preset_carries_the_aim_dial() -> void:
	assert_bool(SIM.BOT_ARGS.has("aim")).is_true()
	for p in BOT.PRESETS:
		assert_bool((BOT.PRESETS[p] as Dictionary).has("aim")).override_failure_message(p).is_true()
	assert_float(float(BOT.PRESETS["sim77"]["aim"])).is_equal(0.0)
	assert_float(float(BOT.PRESETS["careless"]["aim"])).is_less(float(BOT.PRESETS["explorer"]["aim"]))
	assert_float(float(BOT.PRESETS["explorer"]["aim"])).is_less_equal(float(BOT.PRESETS["expert"]["aim"]))
	assert_float(float(BOT.resolve_opts({"aim": 3.0})["aim"])).is_equal(1.0)
	assert_float(float(BOT.resolve_opts({"aim": "0.4"})["aim"])).is_equal_approx(0.4, 0.0001)


func test_with_the_switch_off_the_legs_and_the_stick_are_the_old_ones() -> void:
	_set_aim(false)
	var g := _fake_game()
	for k in range(5):
		g.enemies.put(k, Vector3(5, 0, float(k - 2) * 0.5))
	var w := FakeWeapon.new()
	g._behaviors["revolver"] = w
	var bot = BOT.new(g, {"preset": "expert"})
	bot._aim_pre()
	assert_bool(bot.aim_live).is_false()
	assert_float(bot.legs.aim_w).is_equal(0.0)
	assert_vector(bot.legs.aim_pack).is_equal(Vector3.ZERO)
	g.player.input.touch_pos = Vector2(1, 2)
	bot._aim_after(1.0 / 60.0)
	assert_vector(g.player.input.touch_pos).is_equal(Vector2(1, 2))
	assert_int(bot.aim_beats).is_equal(0)
	assert_dict(bot.aim_tallies()).is_empty()
	# the switch on but the dial at 0 (sim77): nothing either
	_set_aim(true)
	var old = BOT.new(g, {"preset": "sim77"})
	old._aim_pre()
	assert_bool(old.aim_live).is_false()
	assert_float(old.legs.aim_w).is_equal(0.0)


func test_a_beat_turns_him_on_the_spot_to_the_front_as_a_shot_leaves() -> void:
	_set_aim(true)
	var g := _fake_game()
	for k in range(5):
		g.enemies.put(k, Vector3(5, 0, float(k - 2) * 0.5))
	var w := FakeWeapon.new()
	w.cooldown_left = 0.05   # the next shot within BEAT_LEAD
	g._behaviors["revolver"] = w
	g.player.face = Vector3.FORWARD   # facing north, the crowd to the east: outside his cone
	var bot = BOT.new(g, {"preset": "expert"})
	bot._aim_pre()
	assert_bool(bot.aim_live).is_true()
	assert_float(absf(_deg(Vector3(1, 0, 0), bot.legs.aim_pack))).is_less(3.0)
	assert_float(bot.legs.aim_w).is_equal_approx(BOT.LEAN_SHARE, 0.0001)
	bot._aim_after(1.0 / 60.0)
	assert_int(bot.aim_beats).is_equal(1)
	assert_int(bot.aim_synced).is_equal(1)
	assert_str(bot.intent).is_equal("aim")
	var v: Vector2 = g.player.input.touch_pos - g.player.input.origin
	assert_float(v.normalized().x).is_greater(0.99)
	assert_float(v.length() / 60.0).is_less(0.15)
	# the shot left (its clock jumped up): the beat ends and the stick is the legs' again
	w.cooldown_left = 1.0
	g.player.input.touch_pos = Vector2(7, 7)
	bot.intent = "kite"
	bot._aim_after(1.0 / 60.0)
	assert_vector(g.player.input.touch_pos).is_equal(Vector2(7, 7))
	# facing the crowd: no beat needed, the frame counts inside his cone
	g.player.face = Vector3(1, 0, 0)
	w.cooldown_left = 0.05
	bot._beat_last = -100.0
	bot._aim_after(1.0 / 60.0)
	assert_int(bot.aim_beats).is_equal(1)
	var tl: Dictionary = bot.aim_tallies()
	assert_int(int(tl["frames"])).is_equal(3)
	assert_float(float(tl["in_cone"])).is_greater(0.3)


func test_no_beat_while_he_dodges_or_breaks_out() -> void:
	_set_aim(true)
	var g := _fake_game()
	for k in range(5):
		g.enemies.put(k, Vector3(5, 0, float(k - 2) * 0.5))
	var w := FakeWeapon.new()
	g._behaviors["revolver"] = w
	var bot = BOT.new(g, {"preset": "expert"})
	bot._aim_pre()
	for it in ["dodge", "breakout", "portal", "boss_chest"]:
		bot.intent = it
		w.cooldown_left = 0.05
		g.player.input.touch_pos = Vector2(3, 3)
		bot._aim_after(1.0 / 60.0)
		assert_vector(g.player.input.touch_pos).override_failure_message(it).is_equal(Vector2(3, 3))
	assert_int(bot.aim_beats).is_equal(0)
	bot.intent = "kite"
	bot.legs.seen_ring = Vector3(1, 0, 0)
	bot._aim_after(1.0 / 60.0)
	assert_int(bot.aim_beats).is_equal(0)
