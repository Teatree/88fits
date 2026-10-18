extends GdUnitTestSuite

## Pass 88, lane TWEAKS: no knockback on the hero by default (Settings.hero_knockback, Garry: "Remove the Knockback from
## being hit for Player entirely. Add this option in the Debug version of the Settings menu"), the played looks DM-G and
## FAD-E (approved), the mummy's shadow under its feet and the Red Goblin's body lowered onto its shadow in death.

var _keep_kb := false


func before_test() -> void:
	_keep_kb = Settings.hero_knockback


func after_test() -> void:
	Settings.hero_knockback = _keep_kb


## The real hero, from his scene.
func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	p.global_position = Vector3.ZERO
	p._kb = Vector3.ZERO
	return p


# ---------------------------------------------------------------- 1. the switch

func test_the_switch_is_off_by_default_saved_and_locked_off_in_prod() -> void:
	var fresh = load("res://core/autoload/Settings.gd").new()
	assert_bool(bool(fresh.hero_knockback)).is_false()
	fresh.free()
	assert_bool(Settings.PROD_LOCKED.has("hero_knockback")).is_true()
	assert_bool(bool(Settings.PROD_LOCKED["hero_knockback"])).is_false()
	Settings.hero_knockback = true
	var d: Dictionary = Settings.to_dict()
	assert_bool(bool(d["hero_knockback"])).is_true()
	Settings.hero_knockback = false
	Settings.from_dict(d)
	assert_bool(Settings.hero_knockback).is_true()
	# an older save without the key keeps today's value
	var old := d.duplicate()
	old.erase("hero_knockback")
	Settings.hero_knockback = false
	Settings.from_dict(old)
	assert_bool(Settings.hero_knockback).is_false()


# ---------------------------------------------------------------- 2. off: no regular hit moves him
# (pass 89: the special attacks' pushes came back at the map's share; game/tests/pass89_knock_test.gd pins them)

func test_off_no_regular_hit_knock_moves_him() -> void:
	Settings.hero_knockback = false
	var p := _hero()
	assert_bool(p.hit_knockback_on()).is_false()
	p.hit_knock(Vector3(4, 0, 0))
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	assert_float(p._stick_lock).is_equal(0.0)


func test_off_a_landed_bite_hurts_but_does_not_move_him() -> void:
	Settings.hero_knockback = false
	var p := _hero()
	var hp0 := p.hp
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "a test", "kind": "melee", "knock": 4.0, "fx": ["charge"]})
	assert_float(p.hp).is_less(hp0)
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	var last: Dictionary = p.damage_log[p.damage_log.size() - 1]
	assert_array(last["fx"]).contains(["charge"])


func test_off_his_own_moves_and_the_pulls_still_move_him() -> void:
	Settings.hero_knockback = false
	var p := _hero()
	# his own blast (Astro's thruster burst, the leap pickup)
	p.blast(Vector3(10, 0, 0), 0.0, false)
	assert_float(p._kb.x).is_equal_approx(10.0, 0.0001)
	p._kb = Vector3.ZERO
	# Thruster's lunge
	p.apply_knockback(Vector3(0, 0, 3), false)
	assert_float(p._kb.z).is_equal_approx(3.0, 0.0001)
	p._kb = Vector3.ZERO
	# a silk line's pull is the attack itself, not a knockback
	p.apply_knockback(Vector3(-2, 0, 0))
	assert_float(p._kb.x).is_equal_approx(-2.0, 0.0001)


# ---------------------------------------------------------------- 3. on: today's pushes

func test_on_the_pushes_come_back() -> void:
	Settings.hero_knockback = true
	var p := _hero()
	assert_bool(p.shove(Vector3(6, 0, 0), false)).is_true()
	assert_float(p._kb.x).is_equal_approx(6.0, 0.0001)
	p._kb = Vector3.ZERO
	p.hit_knock(Vector3(4, 0, 0), false)
	assert_float(p._kb.x).is_equal_approx(4.0, 0.0001)
	p._kb = Vector3.ZERO
	p._knock_grace = 0.0
	p.blast(Vector3(0, 0, 9), 5.0)
	assert_float(p._kb.z).is_equal_approx(9.0, 0.0001)
	assert_float(p.velocity.y).is_equal_approx(5.0, 0.0001)
	var hp0 := p.hp
	p.invuln = 0.0
	p._kb = Vector3.ZERO
	p.take_damage(5.0, Vector3(-1, 0, 0), {"by": "a test", "kind": "ranged", "knock": 3.0, "fx": ["knocked back"]})
	assert_float(p.hp).is_less(hp0)
	assert_float(p._kb.x).is_equal_approx(3.0, 0.0001)
	var last: Dictionary = p.damage_log[p.damage_log.size() - 1]
	assert_array(last["fx"]).contains(["knocked back"])


# ---------------------------------------------------------------- 4. the looks and their shadows

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_the_mummy_plays_dm_g_approved_with_its_shadow_under_its_feet() -> void:
	var j := _json("res://content/enemies/dust_mummy/dust_mummy.json")
	assert_str(str(j["variant"])).is_equal("DM-G")
	var v: Dictionary = j["variants"]["DM-G"]
	assert_bool(bool(v.get("fresh", false))).is_false()
	var e: EnemyDef = Registry.enemy("dust_mummy")
	assert_str(e.variant).is_equal("DM-G")
	# the look's own tuning (picked by eye in captures): the painting sunk a little, the blob slid up under the feet
	var sh: Dictionary = e.shadow_tuning()
	assert_float(float(sh.get("drop", 0.0))).is_greater(0.0)
	assert_float(float(sh.get("up", 0.0))).is_greater(0.0)
	var n := EnemyManager.shadow_numbers(e)
	assert_float(n[3]).is_equal_approx(float(sh["drop"]), 0.0001)


func test_the_red_goblins_body_sinks_onto_its_shadow_in_death() -> void:
	var e: EnemyDef = Registry.enemy("red_goblin")
	var dd := EnemyManager.die_drop_of(e)
	assert_float(dd).is_between(0.1, 0.3)
	# the walk is untouched (no plain drop)
	assert_float(EnemyManager.shadow_numbers(e)[3]).is_equal(0.0)
	# clamped like drop
	var fake := EnemyDef.new()
	fake.shadow = {"die_drop": 3.0}
	assert_float(EnemyManager.die_drop_of(fake)).is_equal(0.5)
	fake.shadow = {}
	assert_float(EnemyManager.die_drop_of(fake)).is_equal(0.0)


func test_the_death_sink_eases_in_frame_by_frame() -> void:
	var em: EnemyManager = auto_free(EnemyManager.new())
	add_child(em)
	var t: int = em.register_type(Registry.enemy("red_goblin")) if em.has_method("register_type") else -1
	if t < 0:
		return
	var i := 0
	em.type_idx[i] = t
	em.size[i] = 1.0
	var up := Vector3.UP
	assert_vector(em.die_sink(i, 0.0, 1.0, up)).is_equal(Vector3.ZERO)
	var dd := EnemyManager.die_drop_of(Registry.enemy("red_goblin"))
	assert_float(em.die_sink(i, 1.0, 1.0, up).y).is_equal_approx(dd, 0.0001)
	assert_float(em.die_sink(i, 0.5, 1.0, up).y).is_equal_approx(dd * 0.5, 0.0001)


func test_fadeaway_plays_fad_e_approved() -> void:
	var j := _json("res://content/characters/fadeaway/fadeaway.json")
	assert_str(str(j["variant"])).is_equal("FAD-E")
	assert_bool(bool((j["variants"]["FAD-E"] as Dictionary).get("fresh", false))).is_false()
	var c: CharacterDef = Registry.character("fadeaway")
	assert_str(c.variant).is_equal("FAD-E")
