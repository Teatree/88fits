extends GdUnitTestSuite

## Pass 72, lane INTEG: a map JSON that lacks pass 72's timeline keys (Garry's Level Editor page, opened before the
## keys existed, saves timeline_data from its own copy and drops what it never saw) still plays the numbers pass 72 meant:
## the hero's pushes halved (WaveTimeline.HERO_KNOCKBACK_DEFAULT 0.5), the specials' x1.5 size, x15 HP, 35% chest and
## three alive at most (EnemyDef.SPECIAL_DEFAULTS / SPECIAL_MAX_ALIVE), and the bosses' HP pegged to the hero's DPS
## (WaveTimeline.BOSS_HP_SCALING_DEFAULTS on, exponent 0.5, window 45 s, 0.75..3, BOSS_REF_DPS_DEFAULTS King 600, Gila
## 4500, Brander 20000).

var _keep_map: MapDef = null


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	_keep_map = Run.map


func after_test() -> void:
	Run.map = _keep_map
	Run.arena = false
	Run.elapsed = 0.0
	Run.held_time = 0.0
	Run.stage = 0
	Run.dps_reset()
	Run.end()


func _bare() -> WaveTimeline:
	return JsonContent.timeline_from_dict({})


func test_the_hero_knockback_halves_on_a_map_without_the_key() -> void:
	assert_float(WaveTimeline.HERO_KNOCKBACK_DEFAULT).is_equal(0.5)
	assert_float(_bare().hero_knockback_mult).is_equal(0.5)
	assert_float(WaveTimeline.new().hero_knockback_mult).is_equal(0.5)
	# a map that names its own number plays it
	assert_float(JsonContent.timeline_from_dict({"hero_knockback_mult": 0.8}).hero_knockback_mult).is_equal(0.8)
	# and the crowd reads it from the run's map
	var m := MapDef.new()
	m.id = "p72_integ_bare"
	m.timeline = _bare()
	Run.map = m
	var em: EnemyManager = auto_free(EnemyManager.new())
	assert_float(em.hero_knock_mult()).is_equal(0.5)


func test_the_specials_play_pass_72s_numbers_on_a_map_without_special_defaults() -> void:
	var spd: Dictionary = _bare().special_defaults
	assert_bool(spd.is_empty()).is_true()
	assert_float(EnemyDef.special_value({}, spd, "size")).is_equal(1.5)
	assert_float(EnemyDef.special_value({}, spd, "hp")).is_equal(15.0)
	assert_float(EnemyDef.special_value({}, spd, "damage")).is_equal(2.0)
	assert_float(EnemyDef.special_value({}, spd, "chest_chance")).is_equal(0.35)
	assert_int(EnemyDef.special_max_alive(spd)).is_equal(3)


func test_the_bosses_are_pegged_to_dps_on_a_map_without_the_block() -> void:
	var tl := _bare()
	assert_bool(tl.boss_hp_scaling.is_empty()).is_true()
	assert_bool(bool(WaveTimeline.BOSS_HP_SCALING_DEFAULTS["enabled"])).is_true()
	assert_float(tl.boss_ref_dps("tumbleweed_king")).is_equal(600.0)
	assert_float(tl.boss_ref_dps("gila_grande")).is_equal(4500.0)
	assert_float(tl.boss_ref_dps("brander")).is_equal(20000.0)
	assert_float(tl.boss_ref_dps("nobody")).is_equal(0.0)
	assert_float(tl.boss_dps_window()).is_equal(45.0)
	# exponent 0.5, floor 0.75, ceiling 3
	assert_float(WaveTimeline.boss_hp_mult(tl.boss_hp_scaling, 2400.0, 600.0)).is_equal_approx(2.0, 0.0001)
	assert_float(WaveTimeline.boss_hp_mult(tl.boss_hp_scaling, 0.0, 600.0)).is_equal_approx(0.75, 0.0001)
	assert_float(WaveTimeline.boss_hp_mult(tl.boss_hp_scaling, 1.0e9, 600.0)).is_equal_approx(3.0, 0.0001)
	# the director scales the King: 2,400 a second over the window against his 600 is twice the HP (pass 83, lane SCALE:
	# in the pegged mode, named; a map without the block plays the seconds mode now, pass83_scale_test)
	var dir: WaveDirector = auto_free(WaveDirector.new())
	tl.boss_hp_scaling = {"mode": "dps"}
	dir.timeline = tl
	Run.stage = 0
	Run.dps_reset()
	for s in range(45):
		Run.elapsed = 400.0 + float(s)
		Run.add_damage("revolver", 2400.0)
	Run.elapsed = 445.0
	assert_float(dir.boss_dps_scale("tumbleweed_king")).is_equal_approx(2.0, 0.05)
	assert_float(float(dir.last_boss_scale["ref"])).is_equal(600.0)
	# off when the block says so, and never in the arena
	tl.boss_hp_scaling = {"enabled": false}
	assert_float(dir.boss_dps_scale("tumbleweed_king")).is_equal(1.0)
	tl.boss_hp_scaling = {}
	Run.arena = true
	assert_float(dir.boss_dps_scale("tumbleweed_king")).is_equal(1.0)


func test_red_canyons_own_numbers_are_the_ones_it_plays() -> void:
	# whatever the map file says (Garry tunes these in the Level Editor) reaches the imported map; a key it lacks plays the
	# defaults above
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var raw: Dictionary = j["timeline_data"]
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(tl.hero_knockback_mult).is_equal_approx(float(raw.get("hero_knockback_mult", WaveTimeline.HERO_KNOCKBACK_DEFAULT)), 0.0001)
	var spd: Dictionary = raw.get("special_defaults", {})
	assert_float(EnemyDef.special_value({}, tl.special_defaults, "chest_chance")).is_equal_approx(float(spd.get("chest_chance", 0.35)), 0.0001)
	for ev in raw["events"]:
		if str(ev.get("type", "")) == "boss":
			assert_float(tl.boss_ref_dps(str(ev["enemy"]))).override_failure_message(str(ev["enemy"])).is_greater(0.0)
