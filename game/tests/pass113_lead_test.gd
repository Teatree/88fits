## Pass 113 (the lead): the Monk's volley as one cloud (Garry: "these projectiles actually move as a cloud ... where the
## center is aiming, where the hero actually is"), a bit faster, half as far again, its three looks approved and the brown
## one the base; a locked skin's still as a dark silhouette on the hero sheet, and a look's goal met at a boss's fall
## announced in the run (WaveDirector asks the game, which shows the banner).
extends GdUnitTestSuite

const P112 := preload("res://tests/pass112_monk_test.gd")
const Sheet := preload("res://ui/wanted/WHeroSheet.gd")
const DT := 1.0 / 60.0
const HERO := "may"
const QID := "p113_test_skin"

## a fake game that also counts the director's quest checks (WaveDirector._on_boss_died)
const FAKE_GAME_Q := """extends Node
var player: Node3D
var map = null
var enemies = null
var pickups = null
var hud = null
var checks := 0
func check_quests_now() -> void:
	checks += 1
"""

var _keep_variants: Dictionary = {}


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	_keep_variants = Registry.character(HERO).variants.duplicate(true)


func after_test() -> void:
	Registry.character(HERO).variants = _keep_variants
	Registry.quests.erase(QID)
	Run.elapsed = 0.0
	Run.stage = 0
	Run.stage_beaten = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(P112.FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(P112.FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var pk := Node.new()
	pk.set_script(_script(P112.FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _run(em: EnemyManager, n: int) -> void:
	for k in range(n):
		em._physics_process(DT)
		if em.squads != null and em.squads.orbs != null:
			em.squads.orbs._physics_process(DT)


func _band_z(n: int) -> float:
	var r := 0.0
	for p: Vector3 in Squads.formation(n, float(Registry.enemy("monk").squad_cfg()["spacing"])):
		r = maxf(r, Vector2(p.x, p.z).length())
	var cfg := Registry.enemy("monk").squad_cfg()
	return -(r + (float(cfg["keep_distance"]) - 0.5 + float(cfg["range"])) * 0.5)


# ---------------------------------------------------------------- the Monk

func test_the_monk_numbers_faster_and_half_as_far_again_and_a_cloud() -> void:
	var ob: Dictionary = Registry.enemy("monk").squad_cfg()["orb"]
	assert_str(str(ob["aim"])).is_equal("cloud")
	# pass 112: 4 m/s, 17.5 m; "a bit faster", "extend the range of the projectiles by 50%"
	assert_float(float(ob["speed"])).is_greater(4.0)
	assert_float(float(ob["speed"])).is_less_equal(5.0)
	assert_float(float(ob["range"])).is_equal_approx(17.5 * 1.5, 0.0001)


func test_a_volley_flies_as_one_cloud_whose_middle_crosses_the_hero() -> void:
	var w := _world(Vector3(3.0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	# off to one side, so every member's own line to the hero would differ
	em.spawn_pack("monk", Vector3(-4.0, 0, _band_z(20)), 20)
	_run(em, 30)
	var sq: Dictionary = em.squads.list.values()[0]
	sq["cd"] = 0.0
	var fired := false
	for t in range(400):
		_run(em, 1)
		if em.squads.volleys_fired > 0:
			fired = true
			break
	assert_bool(fired).is_true()
	var orbs := em.squads.orbs
	var idx: Array = []
	for i in range(EnergyOrbs.MAX):
		if orbs.alive[i] == 1:
			idx.append(i)
	assert_int(idx.size()).is_equal(20)
	# every sphere on one line
	var d0: Vector3 = orbs.dir[idx[0]]
	var c := Vector3.ZERO
	for i: int in idx:
		assert_float((orbs.dir[i] as Vector3).distance_to(d0)).is_less(0.0001)
		c += orbs.pos[i]
	c /= float(idx.size())
	# the cloud keeps its shape (the formation's spread), its middle on the line to where the hero stood
	var spread := 0.0
	for i: int in idx:
		spread = maxf(spread, Vector2(orbs.pos[i].x - c.x, orbs.pos[i].z - c.z).length())
	assert_float(spread).is_greater(2.0)
	var to_hero := Vector2(hero.global_position.x - c.x, hero.global_position.z - c.z)
	var along := Vector2(d0.x, d0.z)
	var off := absf(to_hero.x * along.y - to_hero.y * along.x)
	assert_float(off).is_less(0.15)
	assert_float(to_hero.dot(along)).is_greater(0.0)


func test_aim_each_still_aims_every_sphere_at_the_hero() -> void:
	var w := _world(Vector3(3.0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	em.spawn_pack("monk", Vector3(-4.0, 0, _band_z(10)), 10)
	_run(em, 30)
	# the type's cached block, its sphere set to aim one by one
	var t := int(em.type_idx[(em.squads.list.values()[0]["members"] as PackedInt32Array)[0]])
	var cfg: Dictionary = em.squads.cfg_of(t)
	(cfg["orb"] as Dictionary)["aim"] = "each"
	em.squads.list.values()[0]["cd"] = 0.0
	for k in range(400):
		_run(em, 1)
		if em.squads.volleys_fired > 0:
			break
	var orbs := em.squads.orbs
	var dirs: Array = []
	for i in range(EnergyOrbs.MAX):
		if orbs.alive[i] == 1:
			var to := Vector2(hero.global_position.x - orbs.pos[i].x, hero.global_position.z - orbs.pos[i].z).normalized()
			assert_float(to.dot(Vector2(orbs.dir[i].x, orbs.dir[i].z))).is_greater(0.999)
			dirs.append(orbs.dir[i])
	assert_int(dirs.size()).is_equal(10)
	assert_float((dirs[0] as Vector3).distance_to(dirs[9])).is_greater(0.01)


func test_the_monk_looks_are_approved_and_the_base_is_the_brown_robe() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/monk/monk.json"))
	assert_str(str(d["variant"])).is_equal("MK-A")
	for code: String in ["MK-A", "MK-B", "MK-C"]:
		assert_bool(bool((d["variants"][code] as Dictionary).get("fresh", false))).is_false()
	# the top-level strip is MK-A's (no placeholder left): its size and layout (its frames may since be touched up by hand:
	# the base strip's death frames were edited on 2026-10-29)
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://content/enemies/monk/monk_sprite_a.png"))
	var base := Image.load_from_file(ProjectSettings.globalize_path("res://content/enemies/monk/monk_sprite.png"))
	assert_object(base).is_not_null()
	assert_that(base.get_size()).is_equal(a.get_size())
	assert_dict(d["anims"]).is_equal(d["variants"]["MK-A"]["anims"])
	assert_int(int(d["strip_cols"])).is_equal(int(d["variants"]["MK-A"]["strip_cols"]))


# ---------------------------------------------------------------- skins

## A look of May's other than the one she plays, sold behind a test goal (pass 111's fixture).
func _sell() -> String:
	var c: CharacterDef = Registry.character(HERO)
	var code := ""
	for k in c.variant_codes():
		if str(k) != c.home_look() and not c.sells_skin(str(k)) and Registry.skin_quest(c, str(k)) == null:
			code = str(k)
			break
	assert_str(code).is_not_empty()
	var e: Dictionary = (c.variants[code] as Dictionary).duplicate(true)
	e["shelved"] = false
	e["skin"] = {"purchasable": true, "name": "Test Look", "price": 500, "currency_type": "gold", "unlock_quest": QID}
	c.variants[code] = e
	var q := QuestDef.new()
	q.id = QID
	q.condition = {"type": "runs_total", "count": 3}
	q.unlocks = {"type": "skin", "id": Registry.skin_key(c.id, code)}
	Registry.quests[QID] = q
	return code


func test_a_locked_look_shows_as_a_dark_silhouette_and_its_colours_once_the_goal_is_met() -> void:
	var code := _sell()
	Save.heroes_owned().append(HERO)
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var s: Control = Sheet.open(host, Registry.character(HERO), false)
	await get_tree().process_frame
	var tile: Control = s.find_child("Look_" + code, true, false)
	assert_str(str(tile.get_meta("state"))).is_equal("locked")
	assert_bool(_silhouetted(tile)).is_true()
	# the look worn shows in its colours
	var home: Control = s.find_child("Look_" + Registry.character(HERO).home_look(), true, false)
	assert_bool(_silhouetted(home)).is_false()
	# the goal met: on sale, in its colours
	Save.mark_quest(QID)
	s.call("_fill_looks")
	tile = s.find_child("Look_" + code, true, false)
	assert_str(str(tile.get_meta("state"))).is_equal("buyable")
	assert_bool(_silhouetted(tile)).is_false()
	# the old tiles freed before the test ends
	await get_tree().process_frame
	await get_tree().process_frame


## Whether a look tile's picture is drawn as a silhouette: its still under the silhouette shader, or its badge a mystery.
func _silhouetted(tile: Control) -> bool:
	var still: TextureRect = tile.find_child("Still", true, false)
	if still:
		return still.material is ShaderMaterial and (still.material as ShaderMaterial).shader == WPlaceholder.SILHOUETTE
	var badge: WPlate = tile.find_child("Badge", true, false)
	return badge != null and badge.mystery


func test_a_fallen_boss_has_the_game_check_and_announce_the_quests() -> void:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME_Q))
	add_child(g)
	var pk := Node.new()
	pk.set_script(_script(P112.FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = g
	d.map = Registry.map("red_canyon")
	d.timeline = d.map.timeline
	g.add_child(d)
	d.phase = WaveDirector.Phase.BOSS
	d._on_boss_died(null, Vector3(30, 0, 0))
	assert_int(int(g.get("checks"))).is_equal(1)
