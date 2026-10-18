extends GdUnitTestSuite

## Pass 89: the special attacks push the hero again, less than before; a regular attack never (Garry: "make it so the
## special attacks still knock player back. Like rocketeer rockets, dynamite, boss attacks, etc. but less than before.
## The regular melee attacks shouldn't have a knockback still"). Player.knock_share: the debug switch
## Settings.hero_knockback = every push whole; off, a special attack's at the map's hero_special_knock (0.5), a bite or a
## plain shot not at all.

var _keep_kb := false
var _keep_map: MapDef = null


func before_test() -> void:
	_keep_kb = Settings.hero_knockback
	_keep_map = Run.map
	Settings.hero_knockback = false
	# no map: the game's default share (WaveTimeline.HERO_SPECIAL_KNOCK_DEFAULT)
	Run.map = null


func after_test() -> void:
	Settings.hero_knockback = _keep_kb
	Run.map = _keep_map


func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	p.global_position = Vector3.ZERO
	p._kb = Vector3.ZERO
	p.velocity = Vector3.ZERO
	return p


func test_the_share_special_half_regular_none_switch_whole() -> void:
	var p := _hero()
	assert_float(WaveTimeline.HERO_SPECIAL_KNOCK_DEFAULT).is_equal(0.5)
	assert_float(p.knock_share(true)).is_equal(0.5)
	assert_float(p.knock_share(false)).is_equal(0.0)
	Settings.hero_knockback = true
	assert_float(p.knock_share(true)).is_equal(1.0)
	assert_float(p.knock_share(false)).is_equal(1.0)


func test_the_map_names_the_share() -> void:
	assert_float(JsonContent.timeline_from_dict({}).hero_special_knock).is_equal(0.5)
	assert_float(JsonContent.timeline_from_dict({"hero_special_knock": 0.3}).hero_special_knock).is_equal_approx(0.3, 0.0001)
	assert_float(JsonContent.timeline_from_dict({"hero_special_knock": 3.0}).hero_special_knock).is_equal(1.0)
	var m := MapDef.new()
	m.timeline = JsonContent.timeline_from_dict({"hero_special_knock": 0.25})
	Run.map = m
	var p := _hero()
	assert_float(p.knock_share(true)).is_equal_approx(0.25, 0.0001)
	assert_float(p.knock_share(false)).is_equal(0.0)


func test_what_counts_as_special() -> void:
	assert_bool(Player.is_special_hit({"kind": "boss"})).is_true()
	assert_bool(Player.is_special_hit({"kind": "boss", "special_knock": false})).is_false()
	assert_bool(Player.is_special_hit({"kind": "melee"})).is_false()
	assert_bool(Player.is_special_hit({"kind": "ranged"})).is_false()
	assert_bool(Player.is_special_hit({"kind": "ranged", "special_knock": true})).is_true()
	assert_bool(Player.is_special_hit({})).is_false()


func test_a_special_shove_and_blast_come_at_half() -> void:
	var p := _hero()
	assert_bool(p.shove(Vector3(6, 0, 0), false)).is_true()
	assert_float(p._kb.x).is_equal_approx(3.0, 0.0001)
	p._kb = Vector3.ZERO
	p._knock_grace = 0.0
	# a rocket's throw: the push and the lift at half
	p.blast(Vector3(0, 0, 24), 6.0)
	assert_float(p._kb.z).is_equal_approx(12.0, 0.0001)
	assert_float(p.velocity.y).is_equal_approx(3.0, 0.0001)
	p._kb = Vector3.ZERO
	p.special_push(Vector3(-8, 0, 0))
	assert_float(p._kb.x).is_equal_approx(-4.0, 0.0001)


func test_his_own_blast_and_the_pulls_stay_whole() -> void:
	var p := _hero()
	p.blast(Vector3(10, 0, 0), 0.0, false)
	assert_float(p._kb.x).is_equal_approx(10.0, 0.0001)
	p._kb = Vector3.ZERO
	p.apply_knockback(Vector3(-2, 0, 0))
	assert_float(p._kb.x).is_equal_approx(-2.0, 0.0001)


func test_a_bite_never_moves_him_a_boss_attack_does_at_half() -> void:
	var p := _hero()
	# any creature's bite, a boss's too (EnemyManager's contact hit says special_knock false)
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "Goblin", "kind": "melee", "knock": 4.0})
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	p.invuln = 0.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "Tumbleweed King", "kind": "boss", "knock": 4.0, "special_knock": false})
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	# a plain shot
	p.invuln = 0.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "Spitter", "kind": "ranged", "knock": 2.0})
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	# a boss's attack (the Brander's line, a custom attack) and the Sniper's beam
	p.invuln = 0.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "Brander", "kind": "boss", "knock": 4.0, "fx": ["knocked back"]})
	assert_float(p._kb.x).is_equal_approx(2.0, 0.0001)
	var last: Dictionary = p.damage_log[p.damage_log.size() - 1]
	assert_array(last["fx"]).contains(["knocked back"])
	p._kb = Vector3.ZERO
	p.invuln = 0.0
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "Saiga Sniper", "kind": "ranged", "knock": 5.0, "special_knock": true})
	assert_float(p._kb.x).is_equal_approx(2.5, 0.0001)


func test_the_bubble_still_holds_every_push() -> void:
	var p := _hero()
	p.shield_t = 3.0
	assert_bool(p.shove(Vector3(6, 0, 0), false)).is_false()
	p.blast(Vector3(10, 0, 0), 4.0)
	p.special_push(Vector3(5, 0, 0))
	assert_vector(p._kb).is_equal(Vector3.ZERO)


func test_the_switch_on_plays_every_push_whole() -> void:
	Settings.hero_knockback = true
	var p := _hero()
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "Goblin", "kind": "melee", "knock": 4.0, "special_knock": false})
	assert_float(p._kb.x).is_equal_approx(4.0, 0.0001)
	p._kb = Vector3.ZERO
	p._knock_grace = 0.0
	p.blast(Vector3(0, 0, 24), 6.0)
	assert_float(p._kb.z).is_equal_approx(24.0, 0.0001)
	assert_float(p.velocity.y).is_equal_approx(6.0, 0.0001)


func test_the_game_marks_its_hits() -> void:
	var em := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	# the bite says regular; the Sniper's beam and a custom boss attack say special
	assert_bool(em.contains("binfo[\"special_knock\"] = false")).is_true()
	assert_int(em.count("info[\"special_knock\"] = true")).is_equal(2)
	assert_bool(em.contains("player.special_push(")).is_true()
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game.contains("player.special_push(")).is_true()
