extends GdUnitTestSuite

## Pass 52 (Garry's ninth list), the lead's parts: three cards at every level-up (luck no longer adds a fourth), five
## weapon slots and five line slots, Hot Streak in fewer words, 5% more XP a level, a 1% crit chance for every hero, a
## coin that stands out of the sand, and the flat things laid on the ground (a power-up's ring, a chest's pool, a black
## hole's disc, the Nuke's wave) lying on its slope instead of half sunk in it.

const SLOPE_X := 0.6
const SLOPE_Z := -0.3


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.base_crit = false
	Run.end()


func _start(hero := "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


## A small map whose ground is one plane rising SLOPE_X a metre along x and SLOPE_Z along z.
func _sloped_map() -> MapBase:
	var m: MapBase = auto_free(MapBase.new())
	m.size_m = 40.0
	m.resolution = 1.0
	m.grid_n = 41
	m.heights.resize(41 * 41)
	for iz in range(41):
		for ix in range(41):
			m.heights[iz * 41 + ix] = 5.0 + SLOPE_X * float(ix - 20) + SLOPE_Z * float(iz - 20)
	return m


# ---------------------------------------------------------------- three cards

func test_a_level_up_always_offers_three_cards_and_luck_only_lifts_rarity() -> void:
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game_src.contains("CardPool.bonus_card_chance")).is_false()
	assert_bool(game_src.contains("var offer := CardPool.level_up_offer(3)")).is_true()
	assert_bool(CardPool.new().has_method("bonus_card_chance")).is_false()
	# luck still makes the rarer items likelier, and the words say no more than that
	_start()
	var rare: PassiveDef = null
	for p: PassiveDef in Registry.passives.values():
		if p.rarity == "rare" and p.weight > 0:
			rare = p
			break
	var w0 := CardPool.weight_of(rare)
	Run.debug_set_item("passive", "clover", 4)
	assert_float(CardPool.weight_of(rare)).is_greater(w0)
	assert_str(Registry.passive("clover").text).not_contains("fourth")
	var fortune: TalentDef = Registry.talents.get("fortune")
	assert_str(str((fortune.forms[0] as Dictionary).get("text", ""))).not_contains("fourth")


# ---------------------------------------------------------------- five and five

func test_five_weapon_slots_and_five_line_slots() -> void:
	assert_int(Run.MAX_WEAPONS).is_equal(5)
	assert_int(Run.MAX_LINES).is_equal(5)
	assert_int(HUD.WEAPON_SLOTS).is_equal(5)
	assert_int(HUD.LINE_SLOTS).is_equal(5)
	_start()
	assert_int(Run.weapon_cap()).is_equal(5)
	assert_int(Run.line_cap()).is_equal(5)
	for id in ["peashooter", "boomstick", "tommy_gun", "hornet_nest", "orbit_saws", "zap_beam"]:
		Run.add_weapon(Registry.weapon(id), 1)
	assert_int(Run.weapons.size()).is_equal(5)
	assert_int(HUD.slot_specs([], Run.weapon_cap(), [], [], Run.line_cap(), []).size()).is_equal(10)
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_array(tl.weapon_cap.map(func(v) -> int: return int(v))).is_equal([5, 5, 5])
	assert_array(tl.passive_cap.map(func(v) -> int: return int(v))).is_equal([5, 5, 5])


# ---------------------------------------------------------------- Hot Streak, XP, crit

func test_hot_streak_says_it_in_fewer_words() -> void:
	var t := Registry.passive("hot_streak").text
	assert_int(t.length()).is_less(120)
	# (pass 95, lane PASSIVES: +7% at level 1 on the rarity ladder)
	assert_str(t).contains("+7% attack damage per 1,000 kills")
	assert_str(t).contains("+100%")
	assert_str(t).contains("rest of the run")
	assert_str(t).not_contains("Getting hit")


func test_every_level_asks_five_percent_more_xp() -> void:
	_start()
	# pass 77 re-pin: the multiplier is Garry's (2.1 in pass 52, 4.1 since his 2026-10-15 edit in the Level Editor), so the
	# test reads the map's number and checks the curve follows it
	var mult := float(Registry.map("red_canyon").timeline.xp_need_mult)
	assert_float(mult).is_greater(0.0)
	for lv: int in [1, 5, 10, 25]:
		# pass 82 re-pin (lane XP): the map's growth type (XpCurve; none = 15 + 6L + 0.5L^2)
		var base: float = XpCurve.need(Registry.map("red_canyon").timeline.xp_curve, lv)
		assert_float(Run.xp_to_next(lv)).is_equal_approx(base * mult, 0.001)


func test_every_hero_has_one_percent_crit_chance() -> void:
	assert_float(float(StatSheet.PLAYER_DEFAULTS["crit_chance"])).is_equal_approx(0.01, 0.0001)
	# the real base (the suites leave it out so exact damage never doubles at random)
	Run.base_crit = true
	for hero in ["astro", "calavera", "ironwood", "solenne"]:
		_start(hero)
		assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).override_failure_message(hero).is_equal_approx(0.01, 0.0001)
	# re-pinned in pass 61: the Drifter's signature stat, 1% a level on top of it (Calavera's 5% is gone), and
	# Deadeye's 8% a level the same
	_start("drifter")
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal_approx(0.02, 0.0001)
	Run.debug_set_item("passive", "deadeye", 1)
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal_approx(0.10, 0.0001)


# ---------------------------------------------------------------- the coin

func test_the_coin_is_drawn_in_its_own_look() -> void:
	var src := FileAccess.get_file_as_string("res://core/shaders/coin.gdshader")
	assert_bool(src.contains("unshaded")).is_true()
	var pm: PickupManager = auto_free(PickupManager.new())
	add_child(pm)
	var coin_mm: MultiMesh = pm._mms[PickupManager.KIND_COIN]
	var mmi: MultiMeshInstance3D = null
	for c in pm.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == coin_mm:
			mmi = c
	assert_object(mmi).is_not_null()
	assert_object(mmi.material_override).is_same(PickupManager.coin_material())
	assert_str(((mmi.material_override as ShaderMaterial).shader as Shader).resource_path).is_equal("res://core/shaders/coin.gdshader")
	# the gems have a look of their own too (re-pinned in pass 60: the charged gem shader, pass60_pk_test)
	var gem_mm: MultiMesh = pm._mms[PickupManager.KIND_GEM_S]
	for c in pm.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == gem_mm:
			assert_bool(c.material_override is ShaderMaterial).is_true()
			assert_str(((c.material_override as ShaderMaterial).shader as Shader).resource_path).is_equal("res://core/shaders/gem.gdshader")


# ---------------------------------------------------------------- on the slope

func test_the_ground_normal_and_a_basis_that_stands_on_it() -> void:
	var m := _sloped_map()
	var n := m.normal_at(2.0, -3.0, 0.8)
	var want := Vector3(-SLOPE_X, 1.0, -SLOPE_Z).normalized()
	assert_float(n.dot(want)).is_greater(0.9999)
	var s := m.slope_at(2.0, -3.0, 0.8)
	assert_float(s.x).is_equal_approx(SLOPE_X, 0.001)
	assert_float(s.y).is_equal_approx(SLOPE_Z, 0.001)
	var b := MapBase.ground_basis(n)
	assert_float(b.y.normalized().dot(want)).is_greater(0.9999)
	assert_bool(MapBase.ground_basis(Vector3.UP).is_equal_approx(Basis())).is_true()


const FAKE_HOLDER := """extends Node3D
var game: Node = null
"""

const FAKE_GAME := """extends Node
var map = null
var telegraphs = null
var paused := false
"""


func _holder(m: MapBase) -> Node3D:
	var g: Node = auto_free(Node.new())
	var gs := GDScript.new()
	gs.source_code = FAKE_GAME
	gs.reload()
	g.set_script(gs)
	add_child(g)
	g.set("map", m)
	var h: Node3D = auto_free(Node3D.new())
	var hs := GDScript.new()
	hs.source_code = FAKE_HOLDER
	hs.reload()
	h.set_script(hs)
	h.set("game", g)
	add_child(h)
	return h


func test_a_power_ups_ring_and_a_chests_pool_lie_on_the_slope() -> void:
	var m := _sloped_map()
	var holder := _holder(m)
	var p := Powerup.new()
	p.setup(Registry.pickup("rage"))
	holder.add_child(p)
	p.global_position = Vector3(1.0, m.height_at(1.0, 2.0), 2.0)
	p._process(0.016)
	var want := Vector3(-SLOPE_X, 1.0, -SLOPE_Z).normalized()
	assert_float(p._ring.global_transform.basis.y.normalized().dot(want)).is_greater(0.999)
	# lifted off the slope along its up, not straight up through it
	assert_float(p._ring.position.normalized().dot(want)).is_greater(0.999)
	var c := Chest.new()
	holder.add_child(c)
	c.global_position = Vector3(-2.0, m.height_at(-2.0, 1.0), 1.0)
	c._process(0.016)
	var slope: Vector2 = (c._pool.material_override as ShaderMaterial).get_shader_parameter("slope")
	assert_float(slope.x).is_equal_approx(SLOPE_X, 0.01)
	assert_float(slope.y).is_equal_approx(SLOPE_Z, 0.01)
	var shine := FileAccess.get_file_as_string("res://core/shaders/shine_aura.gdshader")
	assert_bool(shine.contains("slope.x * px + slope.y * pz")).is_true()


func test_the_nukes_wave_races_out_over_the_sand() -> void:
	var tg: Telegraphs = auto_free(Telegraphs.new())
	add_child(tg)
	tg.race_ring(Vector3.ZERO, 10.0, 0.5, Color(1.0, 0.75, 0.35, 0.9), 0.3)
	var it: Dictionary = tg._items.back()
	assert_int(int(it["mode"])).is_equal(Telegraphs.MODE_RACE)
	tg._advance(0.25)
	var k: Color = it["_k"]
	# half its time: seven eighths of the way out (an ease-out), its band 30% of that wide, fading
	assert_float(k.g).is_equal_approx(10.0 * (1.0 - pow(0.5, 3.0)), 0.01)
	assert_float(k.g - k.r).is_equal_approx(k.g * 0.3, 0.01)
	assert_float(float(it["_a"])).is_less(0.9)
	# the Nuke draws it, and no flat torus of its own
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	var a := src.find("func nuke_blast(")
	var b := src.find("\nfunc ", a + 10)
	var body := src.substr(a, b - a)
	assert_bool(body.contains("telegraphs.race_ring(")).is_true()
	assert_bool(body.contains("TorusMesh")).is_false()
