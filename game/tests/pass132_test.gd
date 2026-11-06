## Pass 132 (Garry's requests of 2026-11-06):
##  1. The Revolver's rounds each fly on a line of their own (ProjectileEmitter.burst_fan_angle, params.burst_fan_deg).
##  2. The multi-shot Card (The Hydra) is never offered before the player's first Dynamite pick (FtueDynamite.holds).
##  3. Ironwood is free from the start: two outlaws on a new save.
##  4. A death painting can slide onto its shadow (EnemyDef.shadow "die_slide"); the poncho skeletons use it.
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.arena = false
	Run.banished.clear()
	Run.end()


# ---------------------------------------------------------------- 1. the Revolver's fan

func test_burst_fan_first_round_on_the_aim_then_alternating() -> void:
	var step := deg_to_rad(7.0)
	assert_float(ProjectileEmitter.burst_fan_angle(0, step)).is_equal(0.0)
	assert_float(ProjectileEmitter.burst_fan_angle(1, step)).is_equal_approx(step, 0.0001)
	assert_float(ProjectileEmitter.burst_fan_angle(2, step)).is_equal_approx(-step, 0.0001)
	assert_float(ProjectileEmitter.burst_fan_angle(3, step)).is_equal_approx(2.0 * step, 0.0001)
	assert_float(ProjectileEmitter.burst_fan_angle(4, step)).is_equal_approx(-2.0 * step, 0.0001)


func test_every_round_of_a_pull_has_its_own_line() -> void:
	var seen: Dictionary = {}
	for k in range(9):
		seen[snappedf(ProjectileEmitter.burst_fan_angle(k, 0.1), 0.001)] = true
	assert_int(seen.size()).is_equal(9)


func test_the_revolver_family_carries_the_fan() -> void:
	for id in ["revolver", "golden_revolver"]:
		var w: WeaponDef = Registry.weapon(id)
		assert_object(w).is_not_null()
		assert_bool(bool(w.params.get("burst", false))).is_true()
		assert_float(float(w.params.get("burst_fan_deg", 0.0))).is_greater(0.0)


# ---------------------------------------------------------------- 2. the multi-shot Card waits for the Dynamite

func _ids(list: Array) -> Array:
	var out: Array = []
	for p: PassiveDef in list:
		out.append(p.id)
	return out


func test_hydra_is_held_until_the_first_dynamite_pick() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_bool(FtueDynamite.holds("multishot")).is_true()
	assert_bool(_ids(CardPool.offer_passives()).has("multishot")).is_false()
	for c: Dictionary in CardPool.candidates():
		assert_str(str(c["id"])).is_not_equal("multishot")
	# the pick, in this same run: the Card comes from then on
	FtueDynamite.note_pick({"type": "weapon", "id": FtueDynamite.WEAPON_ID})
	assert_bool(FtueDynamite.holds("multishot")).is_false()
	assert_bool(_ids(CardPool.offer_passives()).has("multishot")).is_true()


func test_only_the_listed_cards_wait_and_never_in_the_arena() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_bool(FtueDynamite.holds("might")).is_false()
	Run.arena = true
	assert_bool(FtueDynamite.holds("multishot")).is_false()


func test_a_held_hydra_keeps_its_levels() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.passives["multishot"] = 1
	assert_bool(_ids(CardPool.offer_passives()).has("multishot")).is_true()


# ---------------------------------------------------------------- 3. Ironwood from the start

func test_two_outlaws_on_a_new_save() -> void:
	var owned: Array = []
	for c: CharacterDef in Registry.characters.values():
		if not c.hidden and Registry.hero_owned(c):
			owned.append(c.id)
	owned.sort()
	assert_array(owned).is_equal(["drifter", "ironwood"])
	assert_str(Registry.character("ironwood").availability).is_equal("available")


# ---------------------------------------------------------------- 4. the death slide

func test_die_slide_reads_from_the_shadow_block() -> void:
	var def := EnemyDef.new()
	assert_float(EnemyManager.die_slide_of(def)).is_equal(0.0)
	def.shadow = {"die_slide": 0.3}
	assert_float(EnemyManager.die_slide_of(def)).is_equal_approx(0.3, 0.0001)
	def.shadow = {"die_slide": 5.0}
	assert_float(EnemyManager.die_slide_of(def)).is_equal(1.0)


func test_the_poncho_skeletons_slide_onto_their_shadow() -> void:
	var f := FileAccess.open("res://content/enemies/skeleton/skeleton.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for code in ["SK-B", "SK-F", "SK-G", "SK-H", "SK-I", "SK-J", "SK-K"]:
		var sh: Dictionary = (d["variants"][code] as Dictionary).get("shadow", {})
		assert_float(float(sh.get("die_slide", 0.0))).is_greater(0.0)
	assert_bool((d["variants"]["SK-A"] as Dictionary).has("shadow")).is_false()
