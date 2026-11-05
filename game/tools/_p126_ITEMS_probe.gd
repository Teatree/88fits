## Pass 126 lane ITEMS probe: the Canteen and the Assayer's Scale in a real run on the real map. The Drifter (a god, no
## spawn beam, the save in the sandbox) walks across a real lake and onto dry ground by the stick, without and with the
## Canteen: his speed in and out of the water, the heal after leaving it second by second, going back in, Evolved's +25%
## on a real creature in the lake and on one on the sand, and that a creature still wades. Then the Scale: real level-ups
## and a real chest through the real screens, each SKIP pressed as the button would (CardScreen._skip, ChestScreen._skip),
## the purse and the XP read off Run, a level reached by the pay itself and its cards following, a banish and a reroll on
## the same run; the replay's own recording is on, so the decisions are the recorded ones. Prints one line a fact and
## "p126_items: OK" or the failures. Headless, bounded.
## Run: GODOT_TIMEOUT=300 bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --log-file <f> --script res://tools/_p126_ITEMS_probe.gd
extends SceneTree

const WATCHDOG_S := 200.0
const DT := 1.0 / 60.0

var _save
var _run
var _reg
var _bad: Array = []


func _initialize() -> void:
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p126_items: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for _k in range(n):
		await process_frame


func _phys(n: int) -> void:
	for _k in range(n):
		await physics_frame


func _say(s: String) -> void:
	print("p126_items: " + s)


func _check(ok: bool, what: String) -> void:
	_say(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_bad.append(what)


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "level": 1, "map": "red_canyon", "map_seed": 5, "spawn": false,
		"analytics": false, "stage": 1}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _frames(150)
	var g = current_scene
	if g == null or g.get("player") == null:
		_say("no game")
		quit(2)
		return
	g.player.god = true
	await _canteen(g)
	await _scale(g)
	_say("OK" if _bad.is_empty() else "FAILED: " + "; ".join(_bad))
	quit(0 if _bad.is_empty() else 1)


func _hold(pl, stick: Vector2) -> void:
	pl.input.set_process(false)
	pl.input.wants_move = stick.length() > 0.0
	pl.input.stick_dir = stick


## His mean flat speed over `frames` physics frames from `at`, the stick held along +X.
func _pace(pl, at: Vector3, frames: int) -> float:
	_hold(pl, Vector2.ZERO)
	pl.global_position = at
	pl.velocity = Vector3.ZERO
	pl._kb = Vector3.ZERO
	await _phys(8)
	_hold(pl, Vector2(1, 0))
	await _phys(2)
	var from: Vector3 = pl.global_position
	await _phys(frames)
	var d: Vector3 = pl.global_position - from
	_hold(pl, Vector2.ZERO)
	return Vector2(d.x, d.z).length() / (float(frames) * DT)


func _canteen(g) -> void:
	var pl = g.player
	var em = g.enemies
	# no crowd over the hero while he is measured
	g.director.set_process(false)
	g.director.set_physics_process(false)
	for i in em.pool_max:
		if em.alive[i] == 1:
			em._free(i)
	var lakes: Array = g.map.call("lakes")
	var lake: Dictionary = lakes[0]
	var c: Vector2 = lake["center"]
	var r: float = lake["radius"]
	_say("lake 0 at %s, radius %.1f; the map's water_slow %.2f" % [str(c), r, pl.water_slow()])
	var wet_at := Vector3(c.x - r * 0.4, g.map.height_at(c.x - r * 0.4, c.y) + 0.05, c.y)
	var fc: Vector3 = g.map.flats_center
	var dry_at := Vector3(fc.x - 4.0, g.map.height_at(fc.x - 4.0, fc.z) + 0.05, fc.z)
	var wet0: float = await _pace(pl, wet_at, 12)
	var dry0: float = await _pace(pl, dry_at, 12)
	_say("no item: wet %.2f m/s, dry %.2f m/s (%.2f)" % [wet0, dry0, wet0 / maxf(dry0, 0.01)])
	_check(wet0 / maxf(dry0, 0.01) < 0.95, "without the Canteen water slows him")
	_run.add_or_level_passive("canteen")
	await _frames(2)
	_check(pl.sheet.get_stat("water_walk", 0.0) > 0.0, "the hero's sheet has the Canteen (Game followed the build)")
	var wet1: float = await _pace(pl, wet_at, 12)
	var dry1: float = await _pace(pl, dry_at, 12)
	_say("Canteen: wet %.2f m/s, dry %.2f m/s (%.2f)" % [wet1, dry1, wet1 / maxf(dry1, 0.01)])
	_check(wet1 / maxf(dry1, 0.01) > 0.97, "with the Canteen water does not slow him")
	# walks out of the lake by the stick and on over dry ground; the heal
	pl.god = false
	pl.invuln = 9999.0
	pl.hp = 20.0
	pl.regen_hold = 9999.0
	_hold(pl, Vector2.ZERO)
	pl.global_position = wet_at
	pl.velocity = Vector3.ZERO
	await _phys(10)
	_check(float(_run.canteen_left) == 0.0, "no heal while he stands in the lake")
	_check(pl.hp == 20.0, "health unchanged in the lake (%.1f)" % pl.hp)
	_hold(pl, Vector2(1, 0))
	var steps := 0
	while bool(g.map.call("in_water", pl.global_position)) and steps < 600:
		await physics_frame
		steps += 1
	_say("walked out of the lake in %.1f s, at %s" % [float(steps) * DT, str(pl.global_position)])
	_hold(pl, Vector2.ZERO)
	await physics_frame
	var hp0: float = pl.hp
	_check(float(_run.canteen_left) > 14.5, "the heal started as he left (%.2f s left)" % float(_run.canteen_left))
	var marks: Array = []
	for k in range(5):
		await _phys(60)
		marks.append("%.1f" % pl.hp)
	_say("health each second after leaving: %s (from %.1f; 3 HP a second)" % [", ".join(marks), hp0])
	_check(absf(pl.hp - hp0 - 15.0) < 1.5, "about 15 HP in 5 s (%.1f)" % (pl.hp - hp0))
	var words: Array = load("res://ui/HUD.gd").buff_parts()
	_check(words.has("CANTEEN"), "the HUD's word CANTEEN shows while it runs")
	# back in: stops; out again: the whole time
	pl.global_position = wet_at
	await _phys(3)
	_check(float(_run.canteen_left) == 0.0, "going back in stops it")
	var hp1: float = pl.hp
	await _phys(60)
	_check(pl.hp == hp1, "no heal back in the water")
	pl.global_position = dry_at
	await _phys(2)
	_check(float(_run.canteen_left) > 14.8, "out again: the whole time (%.2f s)" % float(_run.canteen_left))
	_check(float(_run.healed_by_item.get("canteen", 0.0)) >= 15.0, "the heal is credited to the item (%.1f)" % float(_run.healed_by_item.get("canteen", 0.0)))
	pl.invuln = 0.0
	pl.regen_hold = 0.0
	pl.god = true
	# Evolved: a creature in the lake takes +25%, one on the sand does not, and it still wades
	while _run.passive_level("canteen") < 5:
		_run.add_or_level_passive("canteen")
	await _frames(2)
	em.refresh_player_stats()
	var wet_i: int = em.spawn("skeleton", Vector3(c.x, g.map.height_at(c.x, c.y), c.y), null, 1.0, 50.0)
	var dry_i: int = em.spawn("skeleton", dry_at + Vector3(2, 0, 0), null, 1.0, 50.0)
	for i: int in [wet_i, dry_i]:
		em.state[i] = 0
		em.rise_t[i] = 1.0
		em.rise_v[i] = 0.0
		em.dr[i] = 0.0
		em.hp[i] = 100000.0
		em.max_hp[i] = 100000.0
	var h0: float = em.hp[wet_i]
	em.damage(wet_i, 100.0, "revolver", Vector3.ZERO, 0.0, false, false, em.HIT_NO_CRIT)
	var wet_d: float = h0 - em.hp[wet_i]
	h0 = em.hp[dry_i]
	em.damage(dry_i, 100.0, "revolver", Vector3.ZERO, 0.0, false, false, em.HIT_NO_CRIT)
	var dry_d: float = h0 - em.hp[dry_i]
	_say("a 100 hit: %.1f on the creature in the lake, %.1f on the one on the sand" % [wet_d, dry_d])
	_check(absf(wet_d - 125.0) < 0.01 and absf(dry_d - 100.0) < 0.01, "Evolved's +25% only in water")
	await _phys(2)
	_check(absf(em._wade_mult(wet_i) - 0.9) < 0.001, "a creature still wades with the owner about")
	em._free(wet_i)
	em._free(dry_i)


func _scale(g) -> void:
	var pl = g.player
	pl.global_position = g.map.flats_center + Vector3(0, 1, 0)
	_run.add_or_level_passive("assayers_scale")
	await _frames(2)
	_run.skips_left = 4
	_run.rerolls_left = 1
	_run.banishes_left = 1
	var greed: float = _run.player_sheet.get_stat("greed", 1.0)
	# a real level-up: the cards open by themselves, the SKIP pays
	var lv0: int = _run.level
	_run.add_xp(_run.xp_to_next() / _run.player_sheet.get_stat("xp_gain", 1.0))
	await _frames(3)
	_check(g.cards.visible, "a level-up opened the cards")
	var gold0: int = _run.run_gold
	var xp0: float = _run.xp
	var need: float = _run.xp_to_next()
	# a reroll and a banish first, on the same table: nothing paid
	g.cards._reroll()
	_check(_run.run_gold == gold0 and _run.xp == xp0, "a reroll pays nothing")
	g.cards._toggle_banish()
	var may: Array = load("res://core/systems/CardPool.gd").banishable(g.cards._offer)
	if not may.is_empty():
		g.cards._pick(may[0])
		_check(_run.run_gold == gold0 and _run.xp == xp0, "a banish pays nothing")
		await _frames(30)
	else:
		g.cards._toggle_banish()
		_say("nothing on the table could be banished")
	g.cards._skip()
	_say("level-up SKIP: gold +%d, XP +%.2f of %.1f (%.1f%%), level %d -> %d, skips left %d" % [_run.run_gold - gold0, _run.xp - xp0, need, 100.0 * (_run.xp - xp0) / need, lv0, _run.level, _run.skips_left])
	_check(_run.run_gold - gold0 == roundi(25.0 * greed), "the level-up's skip paid 25 coins")
	_check(absf(_run.xp - xp0 - need * 0.05) < 0.001, "and 5% of the next level's XP")
	_check(g.resume_gate.visible, "the gate follows")
	g.resume_gate.tap()
	await _frames(20)
	# a real chest: touched, the reel lands, SKIP
	gold0 = _run.run_gold
	xp0 = _run.xp
	g.open_chest(pl.global_position)
	await _frames(5)
	_check(g.chest_screen.visible, "a chest opened the reel")
	var n := 0
	while g.chest_screen._spinning and n < 900:
		g.chest_screen.hurry()
		await _frames(1)
		n += 1
		if n % 30 == 1:
			g.chest_screen.skip_intro()
	await _frames(5)
	if g.chest_screen.is_gold(g.chest_screen.result()):
		_say("the chest held gold: it cannot be skipped")
		g.chest_screen._finish(true)
	else:
		g.chest_screen._skip()
		await create_timer(0.4, true).timeout
		_say("chest SKIP: gold +%d, XP +%.2f, skips left %d" % [_run.run_gold - gold0, _run.xp - xp0, _run.skips_left])
		_check(_run.run_gold - gold0 == roundi(25.0 * greed), "the chest's skip paid 25 coins")
		_check(absf(_run.xp - xp0 - _run.xp_to_next() * 0.05) < 0.001, "and 5% of the next level's XP")
	await _frames(10)
	if g.resume_gate.visible:
		g.resume_gate.tap()
	await _frames(20)
	# the pay itself reaches the next level: its cards follow, once
	while _run.passive_level("assayers_scale") < 4:
		_run.add_or_level_passive("assayers_scale")
	await _frames(2)
	_run.add_xp(_run.xp_to_next() / _run.player_sheet.get_stat("xp_gain", 1.0))
	await _frames(3)
	_check(g.cards.visible, "the next level's cards")
	_run.xp = _run.xp_to_next() - 0.5
	var lv1: int = _run.level
	var left: int = _run.skips_left
	gold0 = _run.run_gold
	g.cards._skip()
	_say("Evolved SKIP on the brink of a level: gold +%d, level %d -> %d, banked %d, queue %s, skips %d -> %d" % [_run.run_gold - gold0, lv1, _run.level, g._pending_levels, str(g.modal_queue_kinds()), left, _run.skips_left])
	_check(_run.run_gold - gold0 == roundi(90.0 * greed), "the Evolved skip paid 90 coins")
	_check(_run.level == lv1 + 1, "the XP pay levelled him")
	_check(not g.cards.visible and g._pending_levels == 1, "the level is banked behind the closing screen")
	await create_timer(0.5, true).timeout
	_check(g.cards.visible and g._pending_levels == 0, "its cards open after the beat, alone (%s)" % str(g.visible_modals()))
	# with no skip left SKIP refuses and pays nothing
	_run.skips_left = 0
	gold0 = _run.run_gold
	g.cards._skip()
	_check(g.cards.visible and _run.run_gold == gold0, "no skip left: refused, nothing paid")
	g.cards.visible = false
