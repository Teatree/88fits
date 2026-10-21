extends GdUnitTestSuite

## Pass 95, lane WORLD (Garry: "in Vampire Survivors certain enemies despawn if the player walks far enough from them.
## Let's do that as well. This, of course, only applies to regular enemies, not all of them ... the despawning happens out
## of Player's view. So never when enemies are above him. When enemies despawn they leave nothing behind" and "Magnet -
## should not pull everything. Should just affect a big area and work for a time (like 10s) maybe. For that time there
## should be a 2d magnet icon floating around the Player ... around 2.5 times larger than the Magnet Epic Item"):
## the despawn rule on a laid-out crowd (far + off the screen + old goes; near, on the screen, young, the boss, an
## Elite, a special type, a coloured special, a boss's summon, a held one, a rising one and a training dummy stay; the
## live counts drop; no kill, no death signal), the map key and its defaults, the director's hand-over (never in the
## arena), the Level Editor's rows, the analytics tally; the Magnet power-up (its data, its reach from the card's level
## 1, within the reach pulled and beyond not, never a vacuum gem, the seconds, a second Magnet adding its seconds, the
## icon while it runs and gone after, the HUD's plate key, the bot's price).

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var director = null
var paused := false
var toasts: Array = []
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

const GOALS := preload("res://tools/bot/BotGoals.gd")
const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const MAGNET := "magnet_pulse"
const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.elapsed = 0.0


func after_test() -> void:
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.arena = false
	Run.timed.clear()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## The deaths the crowd announced (enemy_died): a despawn must never be one. (A method rather than a lambda, so the
## suite reads plainly; note gdUnit's command-line run stops the suite at its first failing test.)
var _deaths: Array = []
func _on_died(def: EnemyDef, _pos: Vector3, _elite: EliteModDef, _weapon: String) -> void:
	_deaths.append(def.id)


func _repo_file(rel: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("..").path_join(rel))


## A fake game with a fake hero at the origin, a flat map and a real EnemyManager (as pass84_spawn_test builds it).
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _defaults() -> Dictionary:
	return JsonContent.timeline_from_dict({"stage_length": 430, "stages": 3, "roster": [], "events": [], "waves": []}).despawn_cfg()


func _spawn(em: EnemyManager, id: String, at: Vector3, elite: EliteModDef = null) -> int:
	var i := em.spawn(id, at, elite)
	assert_int(i).override_failure_message("spawn " + id).is_greater_equal(0)
	em.onscreen[i] = 0
	return i


# ---------------------------------------------------------------- the map key

func test_the_map_key_and_its_defaults() -> void:
	assert_dict(WaveTimeline.DESPAWN_DEFAULTS).is_equal({"enabled": true, "distance": 40.0, "grace": 6.0, "every": 0.5, "keep_share": 0.0})
	var d := _defaults()
	assert_bool(bool(d["enabled"])).is_true()
	assert_float(float(d["distance"])).is_equal(40.0)
	assert_float(float(d["grace"])).is_equal(6.0)
	assert_float(float(d["every"])).is_equal(0.5)
	assert_float(float(d["keep_share"])).is_equal(0.0)
	# a map's own numbers over the defaults, key by key; enabled false turns it off
	var tl := JsonContent.timeline_from_dict({"stage_length": 430, "stages": 3, "roster": [], "events": [], "waves": [],
		"despawn": {"distance": 30, "enabled": false, "keep_share": 0.25}})
	assert_float(tl.despawn_value("distance")).is_equal(30.0)
	assert_float(tl.despawn_value("grace")).is_equal(6.0)
	assert_float(tl.despawn_value("keep_share")).is_equal(0.25)
	var c := tl.despawn_cfg()
	assert_bool(bool(c["enabled"])).is_false()
	assert_float(float(c["every"])).is_equal(0.5)
	# the real map: its block (if Garry set one) is numbers, else the game's defaults play
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))
	var block = (doc["timeline_data"] as Dictionary).get("despawn", {})
	var live := Registry.map("red_canyon").timeline.despawn_cfg()
	for k: String in WaveTimeline.DESPAWN_DEFAULTS:
		var want = (block as Dictionary).get(k, WaveTimeline.DESPAWN_DEFAULTS[k]) if block is Dictionary else WaveTimeline.DESPAWN_DEFAULTS[k]
		if k == "enabled":
			assert_bool(bool(live[k])).is_equal(bool(want))
		else:
			assert_float(float(live[k])).override_failure_message(k).is_equal_approx(float(want), 0.0001)


func test_the_director_hands_the_block_over_but_never_in_the_arena() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	assert_bool(em.despawn_enabled()).is_false()
	var dir: WaveDirector = auto_free(WaveDirector.new())
	dir.game = w["g"]
	dir.map = Registry.map("red_canyon")
	dir.timeline = JsonContent.timeline_from_dict({"stage_length": 430, "stages": 3, "roster": [], "events": [], "waves": [], "despawn": {"distance": 33}})
	dir._apply_mults()
	assert_bool(em.despawn_enabled()).is_true()
	assert_float(float(em.despawn_cfg["distance"])).is_equal(33.0)
	assert_float(float(em.despawn_cfg["grace"])).is_equal(6.0)
	# the director's older rule (_cull_behind: anything more than 30 m behind the hero is moved up ahead of him) leaves
	# the regular creatures to the despawn rule and still moves up the ones it never takes (a coloured special here)
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3.ZERO
	var regular := _spawn(em, "red_goblin", Vector3(0, 0, 50))
	var special := _spawn(em, "red_goblin", Vector3(0, 0, 55))
	em.vspecial[special] = 1
	# (the director gave the crowd the map's spawn_rise: both are all the way up for this)
	for i: int in [regular, special]:
		em.rise_t[i] = 1.0
		em.rise_v[i] = 0.0
	assert_bool(em.despawn_kind(regular)).is_true()
	assert_bool(em.despawn_kind(special)).is_false()
	dir._cull_behind()
	assert_vector(em.pos[regular]).is_equal(Vector3(0, 0, 50))
	assert_float(Vector2(em.pos[special].x, em.pos[special].z).length()).is_less(26.0)
	Run.arena = true
	dir._apply_mults()
	assert_bool(em.despawn_enabled()).is_false()
	# off (the arena): the older rule moves the regular one too
	dir._cull_behind()
	assert_float(Vector2(em.pos[regular].x, em.pos[regular].z).length()).is_less(26.0)


func test_the_level_editor_has_the_rows_with_the_games_defaults() -> void:
	var f := _repo_file("tools/level_editor/fields.js")
	assert_bool(f.contains("{ key: 'despawn.enabled', group: 'Scaling', label: 'Despawn far creatures', type: 'bool', def: true,")).is_true()
	assert_bool(f.contains("{ key: 'despawn.distance', group: 'Scaling', label: 'Despawn distance (m)', type: 'number', min: 5, step: 1, def: 40,")).is_true()
	assert_bool(f.contains("{ key: 'despawn.grace', group: 'Scaling', label: 'Despawn grace (s)', type: 'number', min: 0, step: 0.5, def: 6,")).is_true()
	assert_bool(f.contains("{ key: 'despawn.every', group: 'Scaling', label: 'Check every (s)', type: 'number', min: 0.05, step: 0.05, def: 0.5,")).is_true()
	assert_bool(f.contains("{ key: 'despawn.keep_share', group: 'Scaling', label: 'Keep share', type: 'percent', def: 0,")).is_true()
	# no `block:` on them: the settings page skips a block it has no drawer for
	for k: String in ["enabled", "distance", "grace", "every", "keep_share"]:
		var at := f.find("key: 'despawn.%s'" % k)
		var row := f.substr(at, f.find("\n", at) - at)
		assert_bool(row.contains("block:")).override_failure_message(k).is_false()
		assert_bool(row.contains("help: '")).override_failure_message(k).is_true()
	# JsonContent reads the block, the analytics row carries the count
	assert_bool(FileAccess.get_file_as_string("res://core/data/JsonContent.gd").contains("t.get(\"despawn\", {})")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd").contains("_put_map(row, \"despawned\", _despawns, false)")).is_true()


# ---------------------------------------------------------------- the rule on a laid-out crowd

func test_far_offscreen_old_regulars_go_and_everything_else_stays() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3.ZERO
	em.set_despawn(_defaults())
	_deaths.clear()
	em.enemy_died.connect(_on_died)
	# the ones that go: regular creatures 50 m out, off the screen, old enough
	var far_a := _spawn(em, "red_goblin", Vector3(50, 0, 0))
	var far_b := _spawn(em, "blue_slime", Vector3(0, 0, -55))
	# the ones that stay
	var near := _spawn(em, "red_goblin", Vector3(20, 0, 0))                       # within the distance
	var seen := _spawn(em, "red_goblin", Vector3(-50, 0, 0))                      # far, but on the screen
	em.onscreen[seen] = 1
	var boss := em.spawn_boss("tumbleweed_king", Vector3(60, 0, 0))                 # the boss
	em.onscreen[boss] = 0
	var elite: EliteModDef = Registry.elites.values()[0]
	var modded := _spawn(em, "red_goblin", Vector3(0, 0, 60), elite)              # an Elite modifier
	var special := _spawn(em, "rocketeer", Vector3(-60, 0, 0))                    # a special type (the gear badge)
	var coloured := _spawn(em, "red_goblin", Vector3(60, 0, 60))                  # a coloured variance special
	em.vspecial[coloured] = 1
	em.force_plain = true
	var brood := _spawn(em, "red_goblin", Vector3(-60, 0, -60))                   # the boss's summon, its boss alive
	em.force_plain = false
	assert_int(int(em.summoned[brood])).is_equal(1)
	var held := _spawn(em, "red_goblin", Vector3(70, 0, 0))                       # in the Gravity Gun's grip
	em.held[held] = 1
	var rising := _spawn(em, "red_goblin", Vector3(0, 0, 70))                     # still coming up out of the sand
	em.rise_t[rising] = 0.5
	var dummy := _spawn(em, "training_dummy", Vector3(-70, 0, 0))                 # a training dummy
	var alive_before := em.alive_count()
	var kills_before := Run.kills
	# the first check, 7 s in: every one of them is 7 s old
	var went := em._tick_despawn(7.0, hero.global_position)
	assert_int(went).is_equal(2)
	assert_int(int(em.alive[far_a])).is_equal(0)
	assert_int(int(em.alive[far_b])).is_equal(0)
	for i: int in [near, seen, boss, modded, special, coloured, brood, held, rising, dummy]:
		assert_int(int(em.alive[i])).override_failure_message("slot %d should stay" % i).is_equal(1)
	# the live counts dropped as for a death; nothing of a kill happened
	assert_int(em.alive_count()).is_equal(alive_before - 2)
	# (near, seen, modded, coloured, brood, held, rising: seven red goblins stand; far_a went)
	assert_int(em.alive_of("red_goblin")).is_equal(7)
	assert_int(em.alive_of("blue_slime")).is_equal(0)
	assert_int(em.despawned).is_equal(2)
	assert_dict(em.despawned_by).is_equal({"red_goblin": 1, "blue_slime": 1})
	assert_int(Run.kills).is_equal(kills_before)
	assert_array(_deaths).is_empty()
	assert_bool(em.free_list.has(far_a)).is_true()
	# a young one 50 m out, off the screen: safe until the grace has run
	var young := _spawn(em, "red_goblin", Vector3(0, 0, 50))
	assert_int(em._tick_despawn(0.5, hero.global_position)).is_equal(0)
	assert_int(int(em.alive[young])).is_equal(1)
	assert_float(em.age_of(young)).is_equal_approx(0.5, 0.001)
	# a teleport: the hero jumps 45 m; the near one is now far and (off the screen) goes at the next check, the young
	# one too once its grace has run; the boss's brood goes once the boss is gone
	hero.global_position = Vector3(-25, 0, 0)
	em.onscreen[near] = 0
	assert_int(em._tick_despawn(0.5, hero.global_position)).is_equal(1)
	assert_int(int(em.alive[near])).is_equal(0)
	assert_int(int(em.alive[young])).is_equal(1)
	assert_int(em._tick_despawn(6.0, hero.global_position)).is_equal(1)
	assert_int(int(em.alive[young])).is_equal(0)
	em.kill_all()
	assert_int(em.boss_index).is_equal(-1)
	var late := _spawn(em, "red_goblin", Vector3(80, 0, 0))
	em.force_plain = true
	var orphan := _spawn(em, "red_goblin", Vector3(80, 0, 10))
	em.force_plain = false
	assert_int(em._tick_despawn(7.0, hero.global_position)).is_equal(2)
	assert_int(int(em.alive[late])).is_equal(0)
	assert_int(int(em.alive[orphan])).is_equal(0)


func test_the_check_runs_every_so_often_and_the_keep_share_spares() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var cfg := _defaults()
	cfg["every"] = 2.0
	em.set_despawn(cfg)
	var a := _spawn(em, "red_goblin", Vector3(50, 0, 0))
	# the clock runs with every tick; the check waits its interval, so the one at 7 s (first check) goes, then the
	# next spawn is looked at only 2 s later
	assert_int(em._tick_despawn(7.0, hero.global_position)).is_equal(1)
	assert_int(int(em.alive[a])).is_equal(0)
	var b := _spawn(em, "red_goblin", Vector3(50, 0, 0))
	em.spawn_at[b] = 0.0
	assert_int(em._tick_despawn(1.0, hero.global_position)).is_equal(0)
	assert_int(em._tick_despawn(1.0, hero.global_position)).is_equal(1)
	assert_int(int(em.alive[b])).is_equal(0)
	# keep_share 1: every one is spared, every time; 0 again: they go
	cfg["keep_share"] = 1.0
	cfg["every"] = 0.5
	em.set_despawn(cfg)
	var c := _spawn(em, "red_goblin", Vector3(50, 0, 0))
	em.spawn_at[c] = -10.0
	for k in range(5):
		assert_int(em._tick_despawn(0.5, hero.global_position)).is_equal(0)
	assert_int(int(em.alive[c])).is_equal(1)
	cfg["keep_share"] = 0.0
	em.set_despawn(cfg)
	assert_int(em._tick_despawn(0.5, hero.global_position)).is_equal(1)
	# off: nothing ever goes
	em.set_despawn({})
	var d := _spawn(em, "red_goblin", Vector3(50, 0, 0))
	em.spawn_at[d] = -10.0
	assert_int(em._tick_despawn(5.0, hero.global_position)).is_equal(0)
	assert_int(int(em.alive[d])).is_equal(1)
	assert_bool(em.can_despawn(d, hero.global_position)).is_true()


func test_the_analytics_count_the_despawned() -> void:
	var ra: RunAnalytics = auto_free(RunAnalytics.new())
	var def: EnemyDef = Registry.enemy("red_goblin")
	ra.despawned(def)
	ra.despawned(def)
	ra.despawned(Registry.enemy("blue_slime"))
	assert_dict(ra.despawned_by).is_equal({"red_goblin": 2, "blue_slime": 1})
	assert_dict(ra._despawns).is_equal({"red_goblin": 2, "blue_slime": 1})
	# the crowd block carries the manager's counts
	var w := _world()
	var em: EnemyManager = w["em"]
	em.despawned = 3
	ra.game = w["g"]
	var crowd: Dictionary = ra._crowd()
	assert_int(int(crowd.get("despawned", 0))).is_equal(3)
	assert_dict(crowd.get("despawned_by", {})).is_equal({"red_goblin": 2, "blue_slime": 1})


# ---------------------------------------------------------------- the Magnet power-up

## A fake game with a fake hero at the origin, no map (the sand flat at 0) and a real PickupManager in the tree.
func _pickups() -> Dictionary:
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
	return {"g": g, "hero": hero, "pm": pm}


func _tick(pm: PickupManager, seconds: float, step: float = DT) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		pm._physics_process(step)
		t += step


func test_the_magnet_pickup_is_a_timed_wide_pull_in_the_data() -> void:
	var def: PickupDef = Registry.pickup(MAGNET)
	assert_object(def).is_not_null()
	assert_str(def.effect_kind).is_equal("magnet")
	assert_str(def.display_name).is_equal("Magnet")
	assert_float(def.duration).is_equal(10.0)
	assert_float(float(def.params.get("radius_mult", 0.0))).is_equal(2.5)
	assert_float(def.lifetime).is_greater_equal(40.0)
	# the reach: 2.5 x what the Magnet card gives at its level 1 (its xp_pull_radius add), read from the card
	var card: PassiveDef = Registry.passive("magnet")
	var lv1 := 0.0
	for e in card.effects_at_level(1):
		if (e as Effect).stat == "xp_pull_radius" and (e as Effect).op == "add":
			lv1 = (e as Effect).value
	assert_float(lv1).is_greater(0.0)
	assert_float(PickupManager.magnet_item_reach()).is_equal(lv1)
	assert_float(PickupManager.magnet_radius(def)).is_equal_approx(2.5 * lv1, 0.0001)
	# the HUD's plate shows it under its own id with its icon (Run.timed carries it)
	assert_str(HUD.plate_key(MAGNET)).is_equal(MAGNET)
	assert_object(HUD.plate_def(MAGNET)).is_same(def)
	# the bot prices it as it priced the vacuum: by the XP lying
	var c := {"xp_lying": 150.0, "xp_need": 100.0, "hp_frac": 1.0, "crowd": 0.0}
	assert_float(GOALS.powerup_value("magnet", c)).is_equal(GOALS.powerup_value("vacuum", c))
	assert_float(GOALS.powerup_value("magnet", c)).is_greater(GOALS.PU_VACUUM)
	assert_str(GOALS.powerup_why("magnet", c)).is_equal(GOALS.powerup_why("vacuum", c))


func test_within_the_reach_pulled_beyond_not_never_a_vacuum_gem() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var def: PickupDef = Registry.pickup(MAGNET)
	var r := PickupManager.magnet_radius(def)
	assert_float(r).is_greater(6.0)
	# lying on the sand: a gem and a coin inside the reach, a gem beyond it, a vacuum gem inside (3 m and more: past the
	# hero's own 1.5 m magnet)
	var inside := pm.spawn(PickupManager.KIND_GEM_M, Vector3(r * 0.5, 0, 0), 5.0)
	var coin := pm.spawn(PickupManager.KIND_COIN, Vector3(0, 0, r * 0.6), 1.0)
	var beyond := pm.spawn(PickupManager.KIND_GEM_S, Vector3(-r * 1.3, 0, 0), 1.0)
	var vac := pm.spawn(PickupManager.KIND_VACUUM, Vector3(0, 0, -r * 0.4), 1.0)
	_tick(pm, 0.8)
	for i: int in [inside, coin, beyond, vac]:
		assert_int(int(pm.flying[i])).override_failure_message("slot %d should lie still before the magnet" % i).is_equal(0)
		assert_int(int(pm.g_cell[i])).is_greater_equal(0)
	assert_bool(pm.magnet_running()).is_false()
	var secs := pm.magnet_start(def, def.duration)
	assert_float(secs).is_equal_approx(10.0, 0.001)
	assert_bool(pm.magnet_running()).is_true()
	assert_float(pm.magnet_left()).is_equal_approx(10.0, 0.001)
	assert_float(pm.magnet_r).is_equal(r)
	assert_int(pm.magnet_starts).is_equal(1)
	pm._physics_process(DT)
	assert_int(int(pm.flying[inside])).is_equal(1)
	assert_int(int(pm.arced[inside])).is_equal(1)
	assert_int(int(pm.flying[coin])).is_equal(1)
	assert_int(int(pm.flying[beyond])).is_equal(0)
	assert_int(int(pm.flying[vac])).is_equal(0)
	assert_int(pm.magnet_pulls).is_equal(2)
	# the 2D magnet floats round him while it runs, pointing its lines at the ones on their way
	assert_object(pm.magnet_buff).is_not_null()
	assert_bool(pm.magnet_buff.is_inside_tree()).is_true()
	pm._physics_process(DT)
	assert_int(pm.magnet_buff.lines_drawn).is_greater_equal(1)
	var at: Vector3 = pm.magnet_buff.global_position
	assert_float(Vector2(at.x, at.z).length()).is_equal_approx(MagnetBuff.ORBIT_R, 0.01)
	# a gem dropped inside the reach while it runs is taken once it lands: walking about gathers more
	var later := pm.spawn(PickupManager.KIND_GEM_L, Vector3(r * 0.7, 0, r * 0.3), 25.0)
	_tick(pm, 0.8)
	assert_int(int(pm.flying[later])).is_equal(1)
	assert_int(pm.magnet_pulls).is_equal(3)
	# the one beyond the reach comes once the hero walks towards it
	(w["hero"] as Node3D).global_position = Vector3(-r * 0.9, 0, 0)
	pm._physics_process(DT)
	assert_int(int(pm.flying[beyond])).is_equal(1)
	assert_int(int(pm.flying[vac])).is_equal(0)


func test_a_second_magnet_adds_its_seconds_and_the_icon_goes_when_it_ends() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var def: PickupDef = Registry.pickup(MAGNET)
	pm.magnet_start(def, 10.0)
	Run.elapsed = 4.0
	assert_float(pm.magnet_left()).is_equal_approx(6.0, 0.001)
	var secs := pm.magnet_start(def, 10.0)
	assert_float(secs).is_equal_approx(16.0, 0.001)
	assert_float(Run.boost_left(MAGNET)).is_equal_approx(16.0, 0.001)
	assert_int(pm.magnet_starts).is_equal(2)
	# one entry in Run.timed under the pickup's id, no effects (it is the pull, not a stat)
	var n := 0
	for tb in Run.timed:
		if str(tb["id"]) == MAGNET:
			n += 1
			assert_array(tb["effects"]).is_empty()
			assert_str(str(tb["label"])).is_equal("Magnet")
	assert_int(n).is_equal(1)
	pm._physics_process(DT)
	assert_object(pm.magnet_buff).is_not_null()
	# the clock runs out: the buff wears off with the others' toast, the pull stops, the icon is gone
	Run.elapsed = 21.0
	var ended: Array = Run.tick_timed()
	assert_bool(ended.has("Magnet")).is_true()
	assert_bool(pm.magnet_running()).is_false()
	assert_float(pm.magnet_left()).is_equal(0.0)
	pm._physics_process(DT)
	assert_object(pm.magnet_buff).is_null()
	var gem := pm.spawn(PickupManager.KIND_GEM_M, Vector3(6, 0, 0), 5.0)
	_tick(pm, 0.8)
	assert_int(int(pm.flying[gem])).is_equal(0)
