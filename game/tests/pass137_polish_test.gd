## Pass 137, lane POLISH (Garry: "x25 the coin gains temporarily (per coin) ... a flag in the Debug version of the
## Settings"; "Give Player 50 coins at the start"; "Pause Screen during gameplay, x2 the size of the arrow on the Weapon
## buttons"; "Downed Screen - ... Remove the text and center the number"; "All structures 2.5 s to activate instead of 3";
## "The Rocketeer's rocket 10% slower, its turning a bit worse"; "Choosing a weapon task on the Wanted poster slightly
## raises the chance of that weapon being offered (level-up or chest)").
extends GdUnitTestSuite

const DIR := "user://test_saves/pass137_polish"

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
func toast(_t, _c = null) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
"""

var _save_dir := ""
var _save_data: Dictionary = {}
var _settings: Dictionary = {}


func before() -> void:
	Save.flush()
	_save_dir = Save.dir
	_save_data = Save.data.duplicate(true)


func after() -> void:
	Save.dir = _save_dir
	Save.data = _save_data
	Save._dirty = false


func before_test() -> void:
	_settings = Settings.to_dict()
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	WantedRun.current = null
	Settings.force_prod(false)
	Settings.from_dict(_settings)
	Run.arena = false
	Run.end()
	Save.dir = _save_dir
	Save.data = Save._default()
	Save._dirty = false


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _pickups() -> PickupManager:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	return pm


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _clear_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))


# ---------------------------------------------------------------- 1. coins x25 (temporary)

func test_coins_x25_is_a_developer_switch_on_by_default_and_off_in_prod() -> void:
	# on by default, read from a save without the key, written back
	var fresh := Settings.to_dict()
	assert_bool(fresh.has("coins_x25")).is_true()
	Settings.coins_x25 = true
	Settings.from_dict({})
	assert_bool(Settings.coins_x25).is_true()
	Settings.from_dict({"coins_x25": false})
	assert_bool(Settings.coins_x25).is_false()
	assert_bool(bool(Settings.to_dict()["coins_x25"])).is_false()
	# the production build holds it off
	assert_bool(Settings.PROD_LOCKED.has("coins_x25")).is_true()
	assert_bool(bool(Settings.PROD_LOCKED["coins_x25"])).is_false()
	Settings.coins_x25 = true
	Settings.force_prod(true)
	assert_bool(Settings.coins_x25).is_false()
	Settings.set_value("coins_x25", true)
	assert_bool(Settings.coins_x25).is_false()
	Settings.force_prod(false)
	# the developer menu and the Settings' Debug panel carry it; the run record names it
	var dev := FileAccess.get_file_as_string("res://ui/DevMenu.gd")
	assert_str(dev).contains("\"coins_x25\"")
	assert_str(FileAccess.get_file_as_string("res://ui/SettingsScreen.gd")).contains("\"coins_x25\"")
	assert_str(FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")).contains("\"coins_x25\": bool(Settings.get(\"coins_x25\"))")


func test_a_picked_up_coin_pays_x25_while_the_switch_is_on() -> void:
	var pm := _pickups()
	var greed: float = Run.player_sheet.get_stat("greed", 1.0)
	var stage_f: int = maxi(int(round(Run.reward_mult())), 1)
	var at := Vector3(3, 0, 0)
	# on: a coin worth 1 pays 25, one worth 3 pays 75 (x the stage's coin factor, then greed as all gold)
	Settings.coins_x25 = true
	assert_int(PickupManager.coin_pay(1.0)).is_equal(25 * stage_f)
	var g0: int = Run.run_gold
	pm._collect(pm.spawn(PickupManager.KIND_COIN, at, 1.0))
	assert_int(Run.run_gold - g0).is_equal(int(round(25 * stage_f * greed)))
	g0 = Run.run_gold
	pm._collect(pm.spawn(PickupManager.KIND_COIN, at, 3.0), true)
	assert_int(Run.run_gold - g0).is_equal(int(round(75 * stage_f * greed)))
	# off: the coin's own value, as before
	Settings.coins_x25 = false
	assert_int(PickupManager.coin_pay(1.0)).is_equal(stage_f)
	g0 = Run.run_gold
	pm._collect(pm.spawn(PickupManager.KIND_COIN, at, 1.0))
	assert_int(Run.run_gold - g0).is_equal(int(round(stage_f * greed)))
	g0 = Run.run_gold
	pm._collect(pm.spawn(PickupManager.KIND_COIN, at, 3.0), true)
	assert_int(Run.run_gold - g0).is_equal(int(round(3 * stage_f * greed)))


func test_x25_never_touches_a_boss_chest_piece_or_other_gold() -> void:
	var pm := _pickups()
	Settings.coins_x25 = true
	# a boss chest's piece pays exactly what the pop-up counted for it (pass 118: nothing on landing)
	var i := pm.spawn(PickupManager.KIND_COIN, Vector3(2, 0, 0), 4.0)
	pm.exact_pay[i] = {"gold": 0, "xp": 0.0}
	var g0: int = Run.run_gold
	pm._collect(i)
	assert_int(Run.run_gold).is_equal(g0)
	# gold that is not a picked-up coin (an Elite's purse, a chest, the bounty) goes through Run.add_gold untouched
	g0 = Run.run_gold
	Run.add_gold(40, "chest")
	assert_int(Run.run_gold - g0).is_equal(int(round(40 * Run.player_sheet.get_stat("greed", 1.0))))


# ---------------------------------------------------------------- 2. a fresh save starts with 50

func test_a_fresh_save_starts_with_50_gold_and_an_old_one_keeps_its_own() -> void:
	assert_int(Save.START_GOLD).is_equal(50)
	# the defaults a file is read over keep 0: no existing save is given the 50
	assert_int(int(Save._default()["gold"])).is_equal(0)
	_clear_dir()
	Save.dir = DIR
	# no file: a new save
	Save.load_save()
	assert_str(Save.loaded_from).is_equal("new")
	assert_int(Save.gold()).is_equal(50)
	# a file with its own gold keeps it (0 too), and one without the key is not given any
	for g in [0, 7, 1234]:
		var f := FileAccess.open(Save.path(), FileAccess.WRITE)
		f.store_string(JSON.stringify({"version": Save.VERSION, "gold": g, "totals": {"runs": 3}}))
		f.close()
		Save.load_save()
		assert_str(Save.loaded_from).is_equal("save")
		assert_int(Save.gold()).is_equal(g)
	var f2 := FileAccess.open(Save.path(), FileAccess.WRITE)
	f2.store_string(JSON.stringify({"version": Save.VERSION, "totals": {"runs": 3}}))
	f2.close()
	Save.load_save()
	assert_int(Save.gold()).is_equal(0)
	# a wipe is a new save: 50
	Save.data["gold"] = 900
	Save.wipe()
	assert_int(Save.gold()).is_equal(50)
	_clear_dir()


# ---------------------------------------------------------------- 3. the pause screen's arrow x2

func test_the_build_rows_chevron_is_twice_the_size() -> void:
	assert_object(WRow.CHEVRON).is_equal(Vector2(48, 80))
	for open in [false, true]:
		var r: WRow = auto_free(WRow.make(Registry.weapon("revolver"), "a line", null, open))
		assert_object(r.chevron.size).is_equal(Vector2(48, 80))
		assert_int(r.chevron.font_size).is_equal(80)
		var holder := r.chevron.get_parent() as Control
		assert_object(holder.custom_minimum_size).is_equal(Vector2(48, 80))
		if open:
			# turned about its centre, so it stays where it sits
			assert_object(r.chevron.pivot_offset).is_equal(Vector2(24, 40))
			assert_float(r.chevron.rotation).is_equal_approx(PI * 0.5, 0.0001)


# ---------------------------------------------------------------- 4. Down!: the number alone, centred

func test_down_has_no_get_up_words_and_the_count_is_centred_on_the_disc() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var rs: ReviveScreen = auto_free(ReviveScreen.new())
	add_child(rs)
	assert_object(rs.find_child("GetUpWord", true, false)).is_null()
	var disc: Control = rs._disc
	assert_object(disc).is_not_null()
	for c in disc.get_children():
		if c is WText:
			assert_str((c as WText).text.to_lower()).is_not_equal("get up")
	var cnt: WText = rs._count
	assert_float(cnt.position.y + cnt.size.y * 0.5 + ReviveScreen.ROYALE_COUNT_LIFT).is_equal_approx(disc.size.y * 0.5, 0.01)
	assert_float(cnt.position.x + cnt.size.x * 0.5).is_equal_approx(disc.size.x * 0.5, 0.01)


# ---------------------------------------------------------------- 5. every structure 2.5 s

func test_every_structure_takes_two_and_a_half_seconds() -> void:
	var n := 0
	for d: StructureDef in Registry.structures.values():
		n += 1
		assert_float(d.interact_time).override_failure_message(d.id).is_equal_approx(2.5, 0.001)
	assert_int(n).is_greater_equal(9)
	# the JSON says so (the editor's numbers), and a structure that leaves it out takes 2.5 too
	for dir in DirAccess.get_directories_at("res://content/structures"):
		var p := "res://content/structures/%s/%s.json" % [dir, dir]
		if FileAccess.file_exists(p):
			var d := _json(p)
			assert_float(float(d.get("interact_time", 2.5))).override_failure_message(dir).is_equal_approx(2.5, 0.001)
	assert_float(StructureDef.new().interact_time).is_equal_approx(2.5, 0.001)


# ---------------------------------------------------------------- 6. the Rocketeer's rocket

func test_the_rocketeers_rocket_is_ten_percent_slower_and_turns_worse() -> void:
	var ms: Dictionary = Registry.enemy("rocketeer").artillery["missile"]
	# its speed is a share of the Outlaw's top speed: 0.85 x 0.9; the fallback speed x 0.9 too
	assert_float(float(ms["speed_of_hero"])).is_equal_approx(0.765, 0.0001)
	assert_float(float(ms["speed"])).is_equal_approx(3.6, 0.0001)
	# its turn x 0.8 (1.3 rad/s before)
	assert_float(float(ms["turn"])).is_equal_approx(1.04, 0.0001)
	var d := _json("res://content/enemies/rocketeer/rocketeer.json")
	assert_float(float(d["artillery"]["missile"]["speed_of_hero"])).is_equal_approx(0.765, 0.0001)
	assert_float(float(d["artillery"]["missile"]["turn"])).is_equal_approx(1.04, 0.0001)


# ---------------------------------------------------------------- 7. a Wanted weapon task lifts that weapon's cards

func _contract(type: String, target: String) -> WantedRun:
	var w: WantedRun = auto_free(WantedRun.new())
	w.contract = {"type": type, "target": target, "target_kind": "weapon", "n": 1000}
	WantedRun.current = w
	return w


func test_an_open_weapon_task_weighs_its_weapon_x1_5() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	assert_float(float(WantedBoard.config(true).get("weapon_task_weight", 0.0))).is_equal_approx(1.5, 0.0001)
	assert_float(float(_json("res://content/wanted/wanted.json")["weapon_task_weight"])).is_equal_approx(1.5, 0.0001)
	var tommy: WeaponDef = Registry.weapon("tommy_gun")
	var revolver: WeaponDef = Registry.weapon("revolver")
	assert_object(tommy).is_not_null()
	WantedRun.current = null
	var base_new := CardPool.weight_of(tommy, 0)
	var base_held := CardPool.weight_of(revolver, 1)
	var base_other := CardPool.weight_of(revolver, 0)
	# no task: 1.0
	assert_float(WantedRun.task_weapon_mult(tommy)).is_equal(1.0)
	# damage with the Tommy Gun, open: its card x1.5 (new or held), another weapon's untouched
	var w := _contract("damage_weapon", "tommy_gun")
	assert_float(WantedRun.task_weapon_mult(tommy)).is_equal_approx(1.5, 0.0001)
	assert_float(CardPool.weight_of(tommy, 0)).is_equal_approx(base_new * 1.5, 0.0001)
	assert_float(CardPool.weight_of(revolver, 0)).is_equal_approx(base_other, 0.0001)
	# its evolution counts as the family
	if tommy.evolves_into != "":
		assert_float(WantedRun.task_weapon_mult(Registry.weapon(tommy.evolves_into))).is_equal_approx(1.5, 0.0001)
	# the level-up's candidates carry it (the Tommy Gun offered at all on this save)
	var cands := CardPool.candidates()
	for c: Dictionary in cands:
		if str(c["id"]) == "tommy_gun":
			assert_float(float(c["weight"])).is_equal_approx(base_new * 1.5, 0.0001)
	# done or failed: back to 1.0
	w.done = true
	assert_float(WantedRun.task_weapon_mult(tommy)).is_equal(1.0)
	assert_float(CardPool.weight_of(tommy, 0)).is_equal_approx(base_new, 0.0001)
	w.done = false
	w.failed = true
	assert_float(WantedRun.task_weapon_mult(tommy)).is_equal(1.0)
	# a task on a weapon held: the chest's roll weighs its level x1.5 too
	_contract("max_weapon", "revolver")
	Run.add_weapon(revolver, 1)
	var found := false
	for c: Dictionary in Run.chest_candidates():
		if str(c["id"]) == "revolver" and str(c["type"]) == "weapon":
			found = true
			assert_float(float(c["weight"])).is_equal_approx(base_held * 1.5, 0.0001)
	assert_bool(found).is_true()
	# a task that names no weapon (a creature, a Card) lifts nothing
	_contract("kill_enemy", "goblin")
	assert_float(WantedRun.task_weapon_mult(revolver)).is_equal(1.0)
	_contract("item_level", "clover")
	assert_float(WantedRun.task_weapon_mult(revolver)).is_equal(1.0)
	WantedRun.current = null
	assert_float(CardPool.weight_of(revolver, 1)).is_equal_approx(base_held, 0.0001)
