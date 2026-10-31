## Pass 118 (lane ITEMS): every hero's own weapon on other heroes (Garry: "add them all to the pull ... Making it possible
## for other heroes to get those weapons"), the Grindstone's toast and the keys' banking in a live Game. For each hero
## named: the debug arena, the hero in god mode, his items cleared, every other hero's own weapon at level 3 (the
## Revolver, the Gravity Gun, the Guitarra, the Sun Scepter, the Basketball, his own left out), a ring of training
## dummies and goblins kept round him; after `frames` ticks each weapon's damage this run is printed (0 = it never hit).
## The last hero also takes the Grindstone and the Jade Key: a chest is opened through Game.open_chest (the reel taken)
## and a weapon levelled, and the bank and the ground bonus are printed.
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p118_ITEMS_guest_probe.gd \
##       -- heroes=drifter,astro,calavera,ironwood,solenne,fadeaway,buck,may frames=900
## A watchdog quits after 600 s; every wait is bounded. The Save is sandboxed (never written).
extends SceneTree

const HERO_WEAPONS := ["revolver", "gravity_gun", "guitarra", "sun_scepter", "basketball"]
const OWNER := {"revolver": "drifter", "gravity_gun": "astro", "guitarra": "calavera", "sun_scepter": "solenne", "basketball": "fadeaway"}
var _heroes: PackedStringArray = ["drifter", "astro", "fadeaway"]
var _frames_n := 900
var _run
var _reg
var g
var _made: Array = []
var _bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("heroes="):
			_heroes = a.substr(7).split(",", false)
		elif a.begins_with("frames="):
			_frames_n = int(a.substr(7))
	create_timer(600.0, true, false, true).timeout.connect(func() -> void:
		print("p118_guest: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


## The ring kept full: a creature where one died, 4-7 m round the hero.
func _keep_ring(k: int) -> void:
	var em = g.enemies
	_made = _made.filter(func(i: int) -> bool: return i >= 0 and i < em.alive.size() and em.alive[i] == 1)
	while _made.size() < 14:
		var a := float(k * 37 + _made.size() * 53) * 0.4
		var r := 4.0 + float((k + _made.size()) % 4)
		var id := "goblin" if _made.size() % 2 == 0 else "training_dummy"
		var at: Vector3 = g.player.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var i: int = em.spawn(id, _ground(at), null, 1.0, 3.0)
		if i < 0:
			break
		_made.append(i)


func _screens() -> void:
	if g.get("cards") and g.cards and g.cards.visible and not g.cards._offer.is_empty() and not g.cards._picking:
		g.cards._pick(g.cards._offer[0])
	if g.get("chest_screen") and g.chest_screen and g.chest_screen.visible and not g.chest_screen._spinning:
		g.chest_screen._finish(true)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	var save = root.get_node("Save")
	save.begin_sandbox()
	for n in range(_heroes.size()):
		var hid: String = _heroes[n]
		await _hero(hid, n == _heroes.size() - 1)
	print("p118_guest: done, %d problems" % _bad)
	quit(0 if _bad == 0 else 1)


func _hero(hid: String, last: bool) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": hid, "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	g = null
	for k in range(900):
		await process_frame
		var c = current_scene
		if c and c.get("enemies") != null and c.get("player") != null and c.player.is_inside_tree():
			g = c
			break
	if g == null:
		print("p118_guest: %s: the game never came up" % hid)
		_bad += 1
		return
	for k in range(60):
		await process_frame
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	var mine: Array = []
	for wid: String in HERO_WEAPONS:
		if OWNER[wid] == hid:
			continue
		if _run.debug_set_item("weapon", wid, 3) > 0:
			mine.append(wid)
	_run.rebuild_sheets()
	_run.damage_by_weapon.clear()
	g.enemies.kill_all(false)
	_made.clear()
	for k in range(_frames_n):
		_keep_ring(k)
		_screens()
		await process_frame
	var line: Array = []
	for wid: String in mine:
		var d := float(_run.damage_by_weapon.get(wid, 0.0))
		line.append("%s %d" % [wid, int(d)])
		if d <= 0.0:
			_bad += 1
			print("p118_guest: PROBLEM %s on %s dealt no damage" % [wid, hid])
	print("p118_guest: %s (%s) %s" % [hid, str(_run.character.id), ", ".join(PackedStringArray(line))])
	if last:
		await _items_check()


## The Grindstone and the Jade Key in the live game: a chest through Game.open_chest (taken), a level-up, the toast path.
func _items_check() -> void:
	_run.add_or_level_passive("grindstone")
	_run.add_or_level_passive("jade_key")
	var luck0: float = _run.player_sheet.get_stat("luck", 0.0)
	g.open_chest(g.player.global_position + Vector3(1, 0, 0))
	for k in range(240):
		_screens()
		await process_frame
	var luck1: float = _run.player_sheet.get_stat("luck", 0.0)
	print("p118_guest: chest bank %s, luck %.3f -> %.3f" % [str(_run.chest_bank), luck0, luck1])
	if absf(luck1 - luck0 - 0.01) > 0.0001:
		_bad += 1
		print("p118_guest: PROBLEM the chest banked %.4f luck" % (luck1 - luck0))
	var w = _run.weapons[0]
	var lv0: int = w.level
	_run.level_weapon(w.def.id)
	for k in range(30):
		await process_frame
	print("p118_guest: %s Lv %d -> %d, ground %s (%s)" % [w.def.id, lv0, w.level, str(w.ground), w.ground_words()])
	if w.level > lv0 and w.ground.is_empty():
		_bad += 1
		print("p118_guest: PROBLEM nothing was ground in")
