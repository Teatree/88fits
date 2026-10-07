extends GdUnitTestSuite

## Pass 58, lane FX (Garry, 2026-10-07: "Add a red splash VFX effect type of thing to enemies when they die ... it will
## make it easier to tell when an enemy died ... The colour of the [pour] is different for different enemies", and
## "There should be an indicator of what happened whenever a player deposits money with the coin-depositing structure
## ... coins flying out of the player and into the chest ... it should take 3 seconds at least. After the coins arrive
## the chest flies away. There should be more coins and they're more intense and move quicker the more coins the player
## deposits. If it's a couple of coins then they should look like a couple of coins"): every creature JSON carries a
## `blood` that reaches its EnemyDef (any colour: Garry picks them in the Level Editor); a death splashes in that colour in
## Fx's own pool (it fills, then empties within a second), bigger for an Elite and a boss but past 2 m only with the root
## of the size, never drawing on the shared random sequence, a hidden one not at all; a crowd dying at once throws fewer
## drops and smaller splats and every splat still shows, while a steady stream keeps them full; the coins of a deposit
## grow with the gold (one a gold for a couple) under a cap, carry exactly the gold between them, all land, and the stream
## lasts at least 3 s, a big one with quicker flights, a single coin one slow toss that lands as it ends; the coins grow
## with the camera's pull-out; the HUD's purse counts down as they leave; the Strongbox lifts off only once the last coin
## is in (at once with nothing to bank); banking moves the gold the moment the box is used.

const COIN_STREAM := preload("res://core/systems/CoinStream.gd")

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var fx = null
var camera = null
var paused := false
var structures = null
var telegraphs = null
var real = null
var used: Array = []
var deposit_gold := 0
var deposit_seconds := 0.0
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func on_creature_died_index(i: int) -> void:
	if real:
		real._death_splash(i)
func use_structure(def, at: Vector3) -> void:
	used.append(def.id)
	if structures:
		deposit_seconds = structures.deposit(at, deposit_gold)
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

## The run's camera, as far as the coins care: how far out it has pulled
const FAKE_RIG := """extends Node3D
var z := 1.0
func zoom() -> float:
	return z
"""

const STEP := 1.0 / 60.0

var _purse: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	_purse.clear()


func after_test() -> void:
	Run.run_gold = 0
	Run.banked_gold = 0
	if Run.gold_changed.is_connected(_on_purse):
		Run.gold_changed.disconnect(_on_purse)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero with the real crowd, the real Fx and a bare real Game (no scene) whose death hook the
## crowd's deaths reach (FAKE_GAME.on_creature_died_index -> Game._death_splash).
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.set("player", hero)
	var mb := MapBase.new()
	g.add_child(mb)
	g.set("map", mb)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	var fx: Fx = Fx.new()
	g.add_child(fx)
	g.set("fx", fx)
	var real: Game = auto_free(Game.new())
	real.enemies = em
	real.fx = fx
	g.set("real", real)
	return {"g": g, "hero": hero, "em": em, "fx": fx, "game": real}


## Fx's clock run on by hand `seconds` (its _process ticks the blood pool's clock).
func _run_fx(fx: Fx, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		fx._process(STEP)
		t += STEP


## The splats showing, as their widths at their fullest, and the drops flying (Fx keeps them: a headless renderer gives
## nothing back from a MultiMesh).
func _splats(fx: Fx) -> Array:
	return fx.blood_splats()


func _drops(fx: Fx) -> int:
	return fx.blood_drops()


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


# ---------------------------------------------------------------- the colours

## Any colour passes (pass 58 review: Garry picks them in the Level Editor's Creatures tab, and a dark red, a dusty tan or
## one red for every creature must never stop ship.sh); only a missing, malformed or unimported one fails.
func test_every_creature_json_has_a_blood_that_reaches_its_def() -> void:
	var n := 0
	for kind in ["enemies", "bosses"]:
		for id in DirAccess.get_directories_at("res://content/" + kind):
			var path := "res://content/%s/%s/%s.json" % [kind, id, id]
			if not FileAccess.file_exists(path):
				continue
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			assert_bool(d.has("blood")).override_failure_message("%s has no blood" % id).is_true()
			var hex := str(d.get("blood", ""))
			assert_bool(hex.length() == 7 and hex.begins_with("#") and Color.html_is_valid(hex)).override_failure_message("%s: %s" % [id, hex]).is_true()
			var c := Color.html(hex)
			var def: EnemyDef = Registry.enemy(id)
			assert_object(def).is_not_null()
			assert_bool(_close(def.blood, c)).override_failure_message("%s: the def has %s, the JSON %s" % [id, def.blood.to_html(false), hex]).is_true()
			n += 1
	# every creature of pass 58 at least (a copied folder adds one)
	assert_int(n).is_greater_equal(38)
	# a creature without one bleeds red
	assert_bool(_close(EnemyDef.new().blood, Color(0.78, 0.05, 0.05))).is_true()


# ---------------------------------------------------------------- the splash

func test_a_death_splashes_in_its_own_colour_and_is_gone_within_a_second() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	_run_fx(fx, 0.6)
	assert_int(fx.blood_count()).is_equal(0)
	var i := em.spawn("skeleton", Vector3(3, 0, -4))
	assert_int(i).is_greater_equal(0)
	em.damage(i, 1.0e9, "")
	var n0 := fx.blood_count()
	assert_int(n0).is_greater(0)
	var want: Color = Registry.enemy("skeleton").blood
	for c: Color in fx.blood_colors():
		assert_bool(_close(c, want)).override_failure_message("a piece in %s" % c.to_html(false)).is_true()
	# one splat at its body, a few drops round it
	assert_int(_splats(fx).size()).is_equal(1)
	assert_int(_drops(fx)).is_equal(Fx.BLOOD_DROPS[0])
	# drawn while it lasts, gone (and no longer drawn) within a second: brief
	assert_int(fx._blood_mm.visible_instance_count).is_greater(0)
	_run_fx(fx, 0.25)
	assert_int(fx.blood_count()).is_greater(0)
	_run_fx(fx, 0.75)
	assert_int(fx.blood_count()).is_equal(0)
	_run_fx(fx, 0.05)
	assert_int(fx._blood_mm.visible_instance_count).is_equal(0)


func test_the_splash_is_sized_by_the_creature_and_bigger_for_an_elite_and_a_boss() -> void:
	var w := _world()
	var fx: Fx = w["fx"]
	_run_fx(fx, 0.6)
	fx.blood(Vector3.ZERO, Color.RED, 1.0, 0)
	var small: float = _splats(fx)[0]
	_run_fx(fx, 1.0)
	fx.blood(Vector3.ZERO, Color.RED, 2.0, 0)
	assert_float(_splats(fx)[0]).is_equal_approx(small * 2.0, 0.001)
	_run_fx(fx, 1.0)
	fx._blood_busy = 0.0
	fx.blood(Vector3.ZERO, Color.RED, 2.0, 1)
	var elite: float = _splats(fx)[0]
	assert_float(elite).is_greater(small * 2.0)
	assert_int(_drops(fx)).is_equal(Fx.BLOOD_DROPS[1])
	_run_fx(fx, 1.0)
	fx.blood(Vector3.ZERO, Color.RED, 2.0, 2)
	# a boss bursts twice, the first splat wider than an Elite's of its size, and throws the most drops
	var boss := _splats(fx)
	assert_int(boss.size()).is_equal(2)
	assert_float(maxf(boss[0], boss[1])).is_greater(elite)
	assert_int(_drops(fx)).is_equal(Fx.BLOOD_DROPS[2])


func test_the_splash_is_sized_by_the_size_the_creature_was_drawn_at_not_its_json() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	_run_fx(fx, 0.6)
	# drawn at 1.7 times its painting's size (as a size-range row or an elite modifier draws one)
	var i := em.spawn("skeleton", Vector3(2, 0, -5), null, 1.7)
	var drawn: float = em.size[i]
	var json: float = Registry.enemy("skeleton").size
	assert_float(absf(drawn - json)).is_greater(0.3)
	em.damage(i, 1.0e9, "")
	assert_int(_splats(fx).size()).is_equal(1)
	assert_float(_splats(fx)[0]).is_equal_approx(Fx.blood_size(drawn) * Fx.BLOOD_SPLAT, 0.001)


func test_a_big_creatures_splash_grows_only_with_the_root_of_its_size() -> void:
	# up to BLOOD_SOFT m the creature's own size, past it the square root: still growing, never more than the size
	assert_float(Fx.blood_size(1.75)).is_equal(1.75)
	assert_float(Fx.blood_size(Fx.BLOOD_SOFT)).is_equal(Fx.BLOOD_SOFT)
	var last := 0.0
	for k in range(1, 90):
		var s := float(k) * 0.1
		var b: float = Fx.blood_size(s)
		assert_float(b).is_greater(last)
		assert_float(b).is_less_equal(s + 0.0001)
		last = b
	var w := _world()
	var fx: Fx = w["fx"]
	_run_fx(fx, 0.6)
	# a boss as big as the Brander (5.2 m): a splat about 2.6 m across, no longer 4.2 m, a third of the screen
	fx.blood(Vector3.ZERO, Color.RED, 5.2, 2)
	var boss: float = maxf(_splats(fx)[0], _splats(fx)[1])
	assert_float(boss).is_less_equal(2.7)
	assert_float(boss).is_greater(2.4)
	_run_fx(fx, 1.0)
	# still the biggest: wider than an Elite as big as the Stone Golem (3.8 m), wider than a skeleton (1.75 m)
	fx.blood(Vector3.ZERO, Color.RED, 3.8, 1)
	var elite: float = _splats(fx)[0]
	assert_float(boss).is_greater(elite)
	_run_fx(fx, 1.0)
	fx.blood(Vector3.ZERO, Color.RED, 1.75, 0)
	assert_float(elite).is_greater(_splats(fx)[0])


func test_an_elite_creature_splashes_big_and_a_hidden_one_not_at_all() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	var game: Game = w["game"]
	_run_fx(fx, 0.6)
	# the Dune Scorpion is an Elite by its kind
	var e := em.spawn("dune_scorpion", Vector3(0, 0, -6))
	game._death_splash(e)
	assert_int(_drops(fx)).is_equal(Fx.BLOOD_DROPS[1])
	assert_bool(_close(fx.blood_colors()[0], Registry.enemy("dune_scorpion").blood)).is_true()
	_run_fx(fx, 1.2)
	# a creature buried out of sight splashes nothing
	var h := em.spawn("skeleton", Vector3(4, 0, -6))
	em.hidden[h] = 1
	game._death_splash(h)
	assert_int(fx.blood_count()).is_equal(0)


func test_a_crowd_dying_at_once_throws_fewer_drops_and_smaller_splats_and_every_splat_shows() -> void:
	var w := _world()
	var fx: Fx = w["fx"]
	_run_fx(fx, 0.6)
	# a lone death: the full splat
	fx.blood(Vector3(-30, 0, 0), Color.RED, 1.75, 0)
	var full: float = _splats(fx)[0]
	assert_float(full).is_equal_approx(1.75 * Fx.BLOOD_SPLAT, 0.001)
	_run_fx(fx, 3.0)
	for k in range(100):
		fx.blood(Vector3(float(k % 10) * 2.0, 0, floorf(float(k) / 10.0) * 2.0), Color.RED, 1.75, 0)
	var splats: Array = _splats(fx)
	assert_int(splats.size()).is_equal(100)
	assert_int(fx.blood_count()).is_less_equal(Fx.BLOOD_MAX)
	# well under a full splash each: the busy thinning
	assert_float(float(_drops(fx))).is_less(100.0 * float(Fx.BLOOD_DROPS[0]) / 3.0)
	# many small pops, not one sheet (pass 58 review): all but the first few smaller, none below BLOOD_BURST_SHRINK of full
	var small := 0
	for v: float in splats:
		assert_float(v).is_greater_equal(full * Fx.BLOOD_BURST_SHRINK - 0.001)
		assert_float(v).is_less_equal(full + 0.001)
		if v < full * 0.6:
			small += 1
	assert_int(small).is_greater(80)
	# and the next moment, calm again, a death throws its full spray and its full splat
	_run_fx(fx, 3.0)
	fx.blood(Vector3.ZERO, Color.RED, 1.75, 0)
	assert_int(_drops(fx)).is_equal(Fx.BLOOD_DROPS[0])
	assert_float(_splats(fx)[0]).is_equal_approx(full, 0.001)


func test_a_steady_stream_of_deaths_keeps_its_splats_full() -> void:
	var w := _world()
	var fx: Fx = w["fx"]
	_run_fx(fx, 0.6)
	var full := 1.75 * Fx.BLOOD_SPLAT
	# thirty deaths a second, two every four frames, for two seconds (a busy late game)
	var least := full
	for step in range(30):
		fx.blood(Vector3(float(step % 6) * 2.0, 0, 0), Color.RED, 1.75, 0)
		fx.blood(Vector3(float(step % 6) * 2.0, 0, 3.0), Color.RED, 1.75, 0)
		for v: float in _splats(fx):
			least = minf(least, v)
		_run_fx(fx, 4.0 * STEP)
	assert_float(least).is_greater_equal(full * 0.9)


func test_the_splash_keeps_the_shared_random_sequence() -> void:
	var w := _world()
	var fx: Fx = w["fx"]
	seed(58)
	var a := randf()
	seed(58)
	fx.blood(Vector3.ZERO, Color.RED, 1.75, 2)
	assert_float(randf()).is_equal(a)


# ---------------------------------------------------------------- the coin stream

func _on_purse(g: int) -> void:
	_purse.append(g)


## A coin stream in the tree (no camera, no game: the plain axes, no sparkles), driven by hand.
func _stream() -> Node3D:
	var cs: Node3D = auto_free(COIN_STREAM.new())
	add_child(cs)
	cs.set_process(false)
	return cs


## Runs the stream on by hand for `seconds`.
func _run_coins(cs: Node3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		cs._process(STEP)
		t += STEP


func test_the_coins_grow_with_the_gold_under_a_cap() -> void:
	assert_int(COIN_STREAM.count_for(0)).is_equal(0)
	assert_int(COIN_STREAM.count_for(-5)).is_equal(0)
	# a couple of coins look like a couple of coins
	for g in range(1, COIN_STREAM.COINS_LITERAL + 1):
		assert_int(COIN_STREAM.count_for(g)).is_equal(g)
	var last := 0
	for g in range(1, 6000, 7):
		var n: int = COIN_STREAM.count_for(g)
		assert_int(n).is_greater_equal(last)
		assert_int(n).is_less_equal(mini(g, COIN_STREAM.COINS_MAX))
		last = n
	assert_int(COIN_STREAM.count_for(40)).is_between(30, 40)
	assert_int(COIN_STREAM.count_for(400)).is_between(70, 100)
	assert_int(COIN_STREAM.count_for(1000000)).is_equal(COIN_STREAM.COINS_MAX)


func test_a_stream_lasts_three_seconds_lands_every_coin_and_carries_exactly_the_gold() -> void:
	for gold in [1, 2, 3, 40, 400, 5000]:
		var cs := _stream()
		var hero := Node3D.new()
		cs.add_child(hero)
		var landed: Array = [0]
		var done: Array = [-1.0]
		var clock: Array = [0.0]
		var dur: float = cs.start(hero, Vector3(2, 1.3, -1.5), gold, func(_l: int, _n: int) -> void: landed[0] += 1,
			func() -> void: done[0] = clock[0])
		assert_float(dur).is_greater_equal(3.0)
		assert_float(dur).is_equal_approx(COIN_STREAM.duration_for(gold), 0.0001)
		var st = cs._streams[0]
		var sum := 0
		for v in st.value:
			sum += v
		assert_int(sum).is_equal(gold)
		assert_int(st.value.size()).is_equal(COIN_STREAM.count_for(gold))
		while clock[0] < 6.0 and done[0] < 0.0:
			cs._process(STEP)
			clock[0] += STEP
		# every coin in, and not before 3 s
		assert_int(landed[0]).is_equal(COIN_STREAM.count_for(gold))
		assert_float(done[0]).is_greater_equal(3.0 - STEP)
		assert_float(done[0]).is_less(dur + 0.1)
		assert_bool(cs.busy()).is_false()
		assert_int(cs._coin_mm.visible_instance_count).is_equal(0)


func test_a_single_coin_is_one_slow_toss_that_lands_as_the_stream_ends() -> void:
	var cs := _stream()
	var landed_at: Array = [-1.0]
	var clock: Array = [0.0]
	var dur: float = cs.start(null, Vector3(2, 1.3, -1.5), 1, func(_l: int, _n: int) -> void: landed_at[0] = clock[0])
	var st = cs._streams[0]
	assert_int(st.flight.size()).is_equal(1)
	# the whole stream long and higher than any coin of a stream (pass 58 review: it landed at 1.35 s and the box waited)
	assert_float(st.launch[0] + st.flight[0]).is_equal_approx(dur, 0.0001)
	assert_float(st.arc[0]).is_greater(COIN_STREAM.ARC_HIGH * 1.15)
	while clock[0] < 6.0 and cs.busy():
		cs._process(STEP)
		clock[0] += STEP
	assert_float(landed_at[0]).is_greater_equal(dur - 2.0 * STEP)
	assert_float(landed_at[0]).is_less(dur + 2.0 * STEP)
	# two coins: the last lands as the stream ends too
	var two := _stream()
	two.start(null, Vector3(2, 1.3, -1.5), 2)
	var s2 = two._streams[0]
	assert_float(s2.launch[1] + s2.flight[1]).is_equal_approx(s2.dur, 0.0001)


func test_the_coins_grow_with_the_cameras_pull_out() -> void:
	var cs := _stream()
	# no run camera (no game): their own size
	assert_float(cs.grow()).is_equal(1.0)
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	cs.game = g
	assert_float(cs.grow()).is_equal(1.0)
	var rig := Node3D.new()
	rig.set_script(_script(FAKE_RIG))
	g.add_child(rig)
	g.set("camera", rig)
	assert_float(cs.grow()).is_equal(1.0)
	# half of how far out it has pulled, as the splash does: 1.25 at 1.5, 1.5 at 2; never smaller
	rig.set("z", 1.5)
	assert_float(cs.grow()).is_equal_approx(1.0 + COIN_STREAM.COIN_ZOOM_KEEP * 0.5, 0.0001)
	rig.set("z", 2.0)
	assert_float(cs.grow()).is_equal_approx(1.5, 0.0001)
	rig.set("z", 0.8)
	assert_float(cs.grow()).is_equal(1.0)
	# a stream runs with it
	cs.start(null, Vector3(2, 1.3, -1.5), 2)
	_run_coins(cs, 1.0)
	assert_int(cs.in_air()).is_greater(0)


func test_a_bigger_deposit_flies_quicker_and_closer_together_and_glints_brighter() -> void:
	var small := _stream()
	small.start(null, Vector3(2, 1.3, -1.5), 3)
	var big := _stream()
	big.start(null, Vector3(2, 1.3, -1.5), 400)
	var a = small._streams[0]
	var b = big._streams[0]
	var fa := 0.0
	for f in a.flight:
		fa += f
	fa /= float(a.flight.size())
	var fb := 0.0
	for f in b.flight:
		fb += f
	fb /= float(b.flight.size())
	assert_float(fb).is_less(fa * 0.7)
	# closer together: the gap between two launches
	assert_float((b.launch[b.launch.size() - 1] - b.launch[0]) / float(b.launch.size() - 1)).is_less((a.launch[2] - a.launch[0]) / 2.0)
	assert_float(COIN_STREAM.intensity_for(400)).is_greater(COIN_STREAM.intensity_for(3))
	assert_float(COIN_STREAM.duration_for(400)).is_greater_equal(COIN_STREAM.duration_for(3))


func test_the_purse_counts_down_as_the_coins_leave() -> void:
	Run.run_gold = 0
	Run.gold_changed.connect(_on_purse)
	var cs := _stream()
	cs.start(null, Vector3(2, 1.3, -1.5), 40)
	# it shows what he carried, then less and less, ending at what he has now
	assert_int(_purse[0]).is_equal(40)
	_run_coins(cs, 5.0)
	assert_int(_purse.size()).is_greater(5)
	for k in range(1, _purse.size()):
		assert_int(_purse[k]).is_less_equal(_purse[k - 1])
	assert_int(_purse[_purse.size() - 1]).is_equal(0)
	# a coin picked up during a stream is put right: what he has plus what has yet to leave
	_purse.clear()
	cs.start(null, Vector3(2, 1.3, -1.5), 40)
	_run_coins(cs, 1.0)
	var left: int = cs.purse_left()
	Run.run_gold = 7
	_run_coins(cs, STEP)
	assert_int(_purse[_purse.size() - 1]).is_equal(7 + cs.purse_left())
	assert_int(cs.purse_left()).is_less_equal(left)


# ---------------------------------------------------------------- the Strongbox

## The real StructureManager holding one Strongbox at `at` (its painting a BillboardSprite), run by a fake game whose
## use_structure deposits `gold` like Game's "bank".
func _strongbox(gold: int) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.set("player", hero)
	var sm := StructureManager.new()
	sm.game = g
	g.add_child(sm)
	g.set("structures", sm)
	g.set("deposit_gold", gold)
	var s := StructureManager.Structure.new()
	s.def = Registry.structure("gold_bank")
	sm.add_child(s)
	s.position = Vector3(1.7, 0, -1.4)
	var bs := BillboardSprite.new()
	s.add_child(bs)
	bs.position.y = 0.04
	s.visual = bs
	s.ring = MeshInstance3D.new()
	s.ring.material_override = StandardMaterial3D.new()
	s.pie = MeshInstance3D.new()
	s.hand = MeshInstance3D.new()
	for m in [s.ring, s.pie, s.hand]:
		s.add_child(m)
	sm.items.append(s)
	sm._make_coin_stream()
	sm.coins.set_process(false)
	return {"g": g, "sm": sm, "s": s, "hero": hero}


func test_the_strongbox_lifts_off_only_after_its_last_coin() -> void:
	var w := _strongbox(40)
	var sm: StructureManager = w["sm"]
	var s = w["s"]
	sm._use(s)
	assert_array(w["g"].used).contains(["gold_bank"])
	assert_float(w["g"].deposit_seconds).is_greater_equal(3.0)
	assert_bool(s.streaming).is_true()
	assert_bool(s.leaving).is_false()
	# not while the coins fly (2.9 s in), the box bouncing as they land
	_run_coins(sm.coins, 2.9)
	assert_bool(s.leaving).is_false()
	assert_bool(s.reacting).is_true()
	# the last coin in, then a beat, then up it goes
	_run_coins(sm.coins, 1.0)
	assert_bool(s.streaming).is_false()
	assert_bool(s.leaving).is_false()
	await get_tree().create_timer(StructureManager.LIFT_BEAT + 0.2).timeout
	assert_bool(s.leaving).is_true()


func test_with_nothing_to_bank_the_strongbox_flies_off_at_once() -> void:
	var w := _strongbox(0)
	var sm: StructureManager = w["sm"]
	var s = w["s"]
	sm._use(s)
	assert_float(w["g"].deposit_seconds).is_equal(0.0)
	assert_bool(s.streaming).is_false()
	assert_bool(s.leaving).is_true()
	assert_bool(sm.coins.busy()).is_false()


func test_banking_moves_the_gold_the_moment_the_box_is_used() -> void:
	var game: Game = auto_free(Game.new())
	Run.run_gold = 40
	Run.banked_gold = 0
	var had: int = Save.gold()
	assert_int(game.bank_purse()).is_equal(40)
	assert_int(Save.gold()).is_equal(had + 40)
	assert_int(Run.run_gold).is_equal(0)
	assert_int(Run.banked_gold).is_equal(40)
	# nothing carried, nothing moves
	assert_int(game.bank_purse()).is_equal(0)
	assert_int(Save.gold()).is_equal(had + 40)
	assert_int(Run.banked_gold).is_equal(40)
