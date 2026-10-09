## Renders the "Wanted" screens in the states the handoff's mocks show (design_handoff_88fits_wanted/screens), so each
## can be set beside its PNG (tools/wanted_compare.py). Windowed at the phone's canvas:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/wanted_shots.gd -- out=<dir> [only=hud,levelup] [white=1]
## white=1 hides the world behind a white sheet, as the mocks were drawn (they are transparent where the world is).
## inset=N puts the top inset the UI keeps clear of a camera cutout at N design px (pass 43), as a notched phone would.
## Pass 45 states beyond the mocks: 03c-mirror-talent-full (a FULL sheet, its summed status line), 05b-settings-wipe-confirm
## and 13d-pause-abandon-confirm (the WConfirm pop-ups), 14b-down-hits (pass 46: the last 30 seconds of hits and heals on Down!, under the player's debug mode).
## Pass 47: 02c-title-ironwood (his favourite line on the plaque), 04f/04g/04h the Collection's Lines, Passives and
## Enemies tabs (the danger badges), 06 with the gold popup, 07 with a line, a passive item and a weapon on the cards,
## 07b-level-up-spent (no skips or banishes left), 08b-path-no-skips, 10c-chest-opening (the chest low, its light rising),
## 10d-chest-banished (the reel spun again after a banish), 10e-chest-gold (SKIP and BANISH locked on gold, BANISH
## tapped), 13e-pause-build-passives (the Build tab's lines and passive
## items), 16 with every kind of damage source and 16c scrolled to the last of them.
## Pass 48: 06d-hud-levels (only=hud_levels: plates in their levels' colours, Lv 1 common .. Lv 5 legendary and lines
## to epic, a weapon's mutation dots, the glow of one ready to evolve, an evolution's dark plate, the twelve equal
## see-through slots; the brass line between the groups went in pass 53), 04j/04k the Collection's grid and an item's page with a
## 130 px camera-cutout inset (only=collection_inset: the tabs and the board under the back square), and 15c the stage
## clear with NOT YET held under the roads (only=stageclear).
## Pass 54: 29b-path-reel (only=path: the mutation offer's pre-reel spinning past three weapons; 29c as it lands) before
## 08-path-offer; 13c-pause-options at sound 100 and music 0 (both thumbs whole, the floating text block under them);
## 06e-hud-phoenix (only=phoenix: Phoenix Feather's plate flying off the hero with its embers and its banner).
extends SceneTree

var _out := "user://wanted_shots"
var _only: Array = []
var _white := false
var _inset := -1
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a == "white=1":
			_white = true
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("wanted_shots: ", name)


## A finger laid down or lifted at `at` (canvas px), as touch_audit pushes them (pass 60: the survey's text box).
func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	root.push_input(e, true)


func _main() -> void:
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	# the captures fill the save with the mocks' numbers: the PC's own save goes back as it was at the end
	var kept := FileAccess.get_file_as_string("user://save.json")
	var in_run := ["backdrop", "hud", "hud_boss", "hud_full", "hud_levels", "phoenix", "levelup", "gate", "path", "chest", "chest_boss", "shop", "stranger", "pause", "down", "stageclear", "results"]
	var any_run := false
	for n in in_run:
		if _want(n):
			any_run = true
	if any_run:
		await _in_run()
	var menus := ["title", "mirror", "collection", "collection_inset", "settings", "dev", "consent", "survey"]
	var any_menu := false
	for n in menus:
		if _want(n):
			any_menu = true
	if any_menu:
		await _menus()
	if kept != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	quit()


## The still of the desert behind every menu (art/ui/wanted/menu_backdrop.jpg): the arena with no HUD and no hero.
func _backdrop() -> void:
	var was_white := false
	for c in g.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == g.ui.layer - 1:
			c.visible = false
			was_white = true
	g.ui.visible = false
	# no weapons (their familiars float by the hero), and the camera over the thickest stand of cacti and shrubs
	_run.debug_clear_items()
	_run.build_changed.emit()
	var best := Vector3.ZERO
	var best_n := -1.0
	var placed: Array = g.map.props.placed if g.map and g.map.get("props") else []
	for a in placed:
		var pa: Vector3 = a["pos"]
		if g.map.has_method("in_water") and g.map.in_water(pa):
			continue
		var n := 0.0
		for b in placed:
			var pb: Vector3 = b["pos"]
			if Vector2(pa.x - pb.x, pa.z - pb.z).length() < 8.0:
				n += 2.0 if str(b["id"]).begins_with("saguaro") or str(b["id"]) in ["ocotillo", "yucca", "prickly_pear"] else 1.0
		if n > best_n:
			best_n = n
			best = pa
	if best_n > 0.0:
		g.player.global_position = best + Vector3(0.0, 0.0, 2.5)
		g.player.velocity = Vector3.ZERO
		g.camera.snap_to(g.player)
	g.player.visible = false
	await _wait(1.2)
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := ProjectSettings.globalize_path("res://art/ui/wanted/menu_backdrop.jpg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_jpg(path, 0.85)
	print("wanted_shots: backdrop -> ", path)
	g.ui.visible = true
	g.player.visible = true
	if was_white:
		for c in g.get_children():
			if c is CanvasLayer and (c as CanvasLayer).layer == g.ui.layer - 1:
				c.visible = true


## 19, 19b (pass 60): the play-data card over the title with its plainer words, and the survey card on its text question
## with the box focused by a finger (the brass ring; on the phone the keyboard rises with it and the card lifts clear).
## Both opened by hand: a tool run never sends, so neither comes by itself.
func _cards60() -> void:
	await _scene("res://ui/TitleScreen.tscn")
	# the title's live stage builds its world over the first second and holds the frames the card's entrance waits for:
	# settled first, then the card gets its full fade (a shot at 0.7 s had caught it half faded)
	await _wait(1.2)
	if _want("consent"):
		var consent: Control = load("res://ui/wanted/WConsent.gd").open(current_scene)
		await _wait(1.0)
		await _shot("19-consent")
		consent.queue_free()
		await _wait(0.2)
	if _want("survey"):
		var sv := {"id": "shots", "name": "Shots", "questions": [
			{"id": "s1", "type": "rating", "question": "How much fun was that run?", "description": "", "optional": false, "choices": [], "scale": 5, "lower": "Not fun", "upper": "Loved it"},
			{"id": "s2", "type": "open", "question": "Anything you would change?", "description": "A line or two is plenty.", "optional": true, "choices": [], "scale": 5, "lower": "", "upper": ""}]}
		var card: Control = load("res://ui/wanted/WSurvey.gd").open(current_scene, sv)
		await _wait(0.7)
		await _shot("19b-survey")
		card.call("show_page", 1)
		await _wait(0.4)
		var answer: Control = card.find_child("Answer", true, false)
		if answer:
			var at: Vector2 = answer.get_global_rect().get_center()
			_touch(at, true)
			await process_frame
			_touch(at, false)
			await _wait(0.3)
			print("wanted_shots: survey text box focused = ", card.call("answer_focused"))
		await _shot("19c-survey-text-focused")
		card.queue_free()
		await _wait(0.2)


## A menu screen on its own, settled; with white=1 its backdrop is white like the mocks' (the world still did not load
## in them).
func _scene(path: String) -> void:
	change_scene_to_file(path)
	await _wait(0.9)
	if _white:
		for c in current_scene.get_children():
			if c is ColorRect and (c as ColorRect).color == Color("f3e6c8"):
				(c as ColorRect).color = Color.WHITE
				break
		for c in current_scene.get_children():
			if c is TextureRect and str((c as TextureRect).texture.resource_path).ends_with("menu_backdrop.jpg"):
				c.visible = false


## 01-05, 17: the menus with the mocks' purse and best run.
func _menus() -> void:
	_save.data["gold"] = 104711
	_save.data["best_runs"]["red_canyon"] = {"time": 600.0, "level": 47, "stage": 2}
	if _want("title"):
		_save.data["last_character"] = "drifter"
		await _scene("res://ui/TitleScreen.tscn")
		await _shot("01-title")
		# Astro comes after the Drifter since pass 61 (Garry's order: Drifter, Astro, Calavera, Ironwood, Solenne)
		current_scene._step(1)
		await _wait(0.5)
		await _shot("02-title-astro")
		# pass 43: Calavera, the third hero, with his favourite and his own weapon on the plaque
		var tc = current_scene
		for i in (tc._heroes as Array).size():
			if (tc._heroes[i] as Resource).get("id") == "calavera":
				tc._index = i
				tc._show_hero(1)
		await _wait(0.5)
		await _shot("02b-title-calavera")
		# pass 47: Ironwood, his favourite a line (Brawn) on the plaque and no weapon of his own
		for i in (tc._heroes as Array).size():
			if (tc._heroes[i] as Resource).get("id") == "ironwood":
				tc._index = i
				tc._show_hero(1)
		await _wait(0.5)
		await _shot("02c-title-ironwood")
		# the developer's preview: the hidden heroes ride the carousel, locked (Dad has an unlock quest, with a bar)
		root.get_node("Settings").preview_locked_heroes = true
		await _scene("res://ui/TitleScreen.tscn")
		var t = current_scene
		for i in (t._heroes as Array).size():
			if (t._heroes[i] as Resource).get("id") == "dad":
				t._index = i
				t._show_hero(1)
		await _wait(0.5)
		await _shot("01c-title-locked-hero")
		root.get_node("Settings").preview_locked_heroes = false
	if _want("consent") or _want("survey"):
		await _cards60()
	if _want("mirror"):
		# the mock's board: Grit and Drive at rank 1, the rest untouched; 108,411 in the purse
		_save.data["gold"] = 108411
		_save.data["talents"] = {"grit": {"form": 0, "rank": 1}, "drive": {"form": 1, "rank": 1}}
		_save.data["talent_spent"] = 300
		_save.data["last_character"] = "drifter"
		await _scene("res://ui/HomesteadScreen.tscn")
		await _shot("03-mirror")
		current_scene._open(_reg.talent("grit"))
		await _wait(0.5)
		await _shot("03b-mirror-talent-open")
		# 03c (pass 45): a talent at FULL, its status line the ranks summed on one line, the sheet still 960 wide
		_save.data["talents"]["grit"] = {"form": 1, "rank": 3}
		_save.data["talent_spent"] = 900
		current_scene._refresh()
		current_scene._open(_reg.talent("grit"))
		await _wait(0.5)
		await _shot("03c-mirror-talent-full")
		var sheet: Control = current_scene._sheet_root.find_child("Sheet", true, false)
		print("wanted_shots: 03c the sheet is %d px wide" % int(sheet.size.x))
		current_scene._close(false)
	if _want("collection"):
		_save.data["totals"]["kills"] = 12480
		# a save part of the way through: the unlocks not yet earned show as the mock's locked tiles
		var done: Array = _save.data["quests_done"]
		_save.data["quests_done"] = done.slice(0, done.size() / 2)
		# pass 44: the Collection shows what has been met; this save has met most of it
		for w in _reg.weapons.values():
			_save.mark_seen("weapon", w.id)
		for p in _reg.passives.values():
			_save.mark_seen("passive", p.id)
		for k in _reg.perks.values():
			_save.mark_seen("perk", k.id)
		var n_seen := 0
		for e in _reg.enemies.values():
			n_seen += 1
			if n_seen % 4 != 0:
				_save.mark_seen("enemy", e.id)
		await _scene("res://ui/CollectionScreen.tscn")
		await _shot("04-collection")
		current_scene._open_page(_reg.weapon("boomstick"))
		await _wait(0.5)
		await _shot("04b-collection-weapon-page")
		current_scene._open_page(_reg.enemy("dune_scorpion"))
		await _wait(0.5)
		await _shot("04c-collection-creature-page")
		# 04d (pass 44): a locked item's page, the quest and its progress
		_save.data["quests_done"] = []
		_save.add_keyed_total("kills_of_enemy", "goblin", 61)
		current_scene._open_locked(_reg.weapon("tumbleweed"))
		await _wait(0.5)
		await _shot("04d-collection-locked-page")
		current_scene._show_grid()
		await _wait(0.5)
		await _shot("04e-collection-locked-tiles")
		# pass 47: the Lines, the Passives (their rarity's colour) and the Enemies (the danger badges)
		for pair in [[1, "04f-collection-lines"], [2, "04g-collection-passives"], [4, "04h-collection-enemies"]]:
			current_scene._tab = int(pair[0])
			current_scene._show_grid()
			await _wait(0.5)
			await _shot(str(pair[1]))
		current_scene._open_page(_reg.enemy("brander"))
		await _wait(0.5)
		await _shot("04i-collection-boss-page")
		current_scene._tab = 0
	if _want("collection_inset"):
		# pass 48: a 130 px camera cutout; the tabs and the board sit under the back square, which nothing covers
		for w in _reg.weapons.values():
			_save.mark_seen("weapon", w.id)
		var stc := root.get_node("Settings")
		var was: int = stc.top_inset
		stc.top_inset = 130
		await _scene("res://ui/CollectionScreen.tscn")
		await _shot("04j-collection-inset130")
		current_scene._open_page(_reg.weapon("boomstick"))
		await _wait(0.5)
		await _shot("04k-collection-page-inset130")
		stc.top_inset = was
	if _want("settings"):
		var st := root.get_node("Settings")
		st.camera_mode = 0
		st.stick_size = 1.0
		st.screen_shake = 0.65
		st.sfx_volume = 0.8
		st.music_volume = 0.0
		st.show_hints = true
		await _scene("res://ui/SettingsScreen.tscn")
		await _shot("05-settings")
		# 05b (pass 45): the wipe asks in a pop-up
		current_scene._ask_wipe()
		await _wait(0.6)
		await _shot("05b-settings-wipe-confirm")
		_cancel_confirm(current_scene)
		await _wait(0.3)
	if _want("dev"):
		var st2 := root.get_node("Settings")
		for k in ["debug_panel", "debug_modal_buttons", "free_revive_button", "hit_log", "debug_mode"]:
			st2.set(k, false)
		change_scene_to_file("res://ui/DevMenu.tscn")
		await _wait(0.9)
		await _shot("17-developer-menu")


func _in_run() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "hornet_nest", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	if _white:
		var cl := CanvasLayer.new()
		cl.layer = g.ui.layer - 1
		var wr := ColorRect.new()
		wr.color = Color.WHITE
		wr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cl.add_child(wr)
		g.add_child(cl)
	# the arena opens with its own banner: let it pass
	g.set_paused(false)
	await _wait(3.2)
	if _want("backdrop"):
		await _backdrop()
	if _want("hud"):
		await _hud_basic()
	if _want("hud_boss"):
		await _hud_boss()
	if _want("hud_full"):
		await _hud_full()
	if _want("hud_levels"):
		await _hud_levels()
	if _want("phoenix"):
		await _phoenix()
	if _want("levelup") or _want("gate"):
		await _levelup()
	if _want("path"):
		await _path()
	if _want("chest"):
		await _chest()
	if _want("chest_boss"):
		await _chest_boss()
	if _want("shop"):
		await _shop()
	if _want("stranger"):
		await _stranger()
	if _want("pause"):
		await _pause()
	if _want("down"):
		await _down()
	if _want("stageclear"):
		await _stage_clear()
	if _want("results"):
		await _results()


func _build(items: Array) -> void:
	_run.debug_clear_items()
	for it in items:
		_run.debug_set_item(it[0], it[1], it[2])
	_run.build_changed.emit()


func _hud_common(level: int, xp_frac: float, gold: int, t: float) -> void:
	_run.level = level
	_run.xp = _run.xp_to_next() * xp_frac
	_run.xp_changed.emit(_run.xp, _run.xp_to_next())
	_run.run_gold = gold
	_run.gold_changed.emit(gold)
	_run.elapsed = t
	g.hud.tick(0.0)


func _mut(weapon: String, n: int) -> void:
	var ms: Array = _reg.mutations_of(weapon)
	for i in mini(n, ms.size()):
		_run.debug_set_item("mutation", ms[i].id, 1)


func _hud_basic() -> void:
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["passive", "magnet", 2], ["passive", "energy_shield", 4]])
	_mut("turret_buddy", 2)
	_mut("molotov", 1)
	_run.build_changed.emit()
	_hud_common(3, 0.24, 10, 61.0)
	g.hud.test_arrows = [{"pos": Vector2(1080, 548), "color": Color("6e8b5e"), "side": 1, "text": "PORTAL 80 m"}]
	_stick(Vector2(276, 1456), Vector2(0.4, -0.2))
	g.hud.set_hp(70, 100)
	g.hud.toast("Boomstick Lv 5")
	await _wait(0.7)
	g.hud.toast("+22 HP", Color(0.35, 0.84, 0.42))
	_run.xp_gained.emit(5.0)
	# pass 47: the gold picked up rises from the hero too
	_run.gold_gained.emit(24)
	await _wait(0.45)
	await _shot("06-hud")
	g.hud.test_arrows = []


func _hud_boss() -> void:
	_build([["evolution", "killer_swarm", 8], ["weapon", "turret_buddy", 6], ["weapon", "big_mouth", 7], ["weapon", "molotov", 5],
		["weapon", "boomstick", 2], ["passive", "magnet", 5], ["passive", "field_notes", 3], ["passive", "energy_shield", 4]])
	_hud_common(9, 0.61, 10, 61.0)
	var king = _reg.enemy("tumbleweed_king") if _reg.has_method("enemy") else null
	if king:
		g.hud.show_boss(king)
		g.hud.set_boss_hp(62, 100)
	g.hud.test_arrows = [{"pos": Vector2(0, 668), "color": Color("b4472b"), "side": -1, "text": "BOSS 43 m"},
		{"pos": Vector2(1080, 888), "color": Color("d9662a"), "side": 1, "text": "ELITE"}]
	_stick(Vector2(276, 1456), Vector2(-0.33, 0.4))
	g.hud.set_hp(30, 100)
	var sw = _reg.weapon("killer_swarm")
	g.hud.banner("EVOLVED · KILLER SWARM", Color("d9662a"), sw.icon if sw else null)
	await _wait(0.6)
	await _shot("06b-hud-boss-banner")
	g.hud.test_arrows = []
	g.hud.hide_boss()


## A full build: five weapons (two evolved), five lines (one evolved), a boss up and a toast: every slot of the strip
## filled, and everything under it (the boss plate, the buffs, the toasts) below it.
func _hud_full() -> void:
	# five weapons and five lines on the strip (pass 52; six and six in pass 47); Magnet and Desperado are passive items,
	# never on it. The capture runs as the arena, which would take a sixth line: a real run never holds one
	_build([["evolution", "killer_swarm", 1], ["evolution", "doomstick", 1], ["weapon", "turret_buddy", 4], ["weapon", "big_mouth", 5],
		["weapon", "molotov", 3], ["passive", "magnet", 5], ["passive", "field_notes", 3], ["passive", "deadeye", 2],
		["passive", "aegis", 1], ["passive", "evade", 3], ["passive", "mend", 2], ["passive", "desperado", 2]])
	_hud_common(21, 0.4, 312, 400.0)
	var king = _reg.enemy("tumbleweed_king") if _reg.has_method("enemy") else null
	if king:
		g.hud.show_boss(king)
		g.hud.set_boss_hp(62, 100)
	g.hud.toast("+22 HP", Color("7fe07f"))
	await _wait(0.6)
	await _shot("06c-hud-full-build")
	g.hud.hide_boss()


## 06d (pass 48): the strip by level. Five weapons from Lv 5 (legendary, every mutation held: the glow) down to Lv 1
## (common, none) and an evolution (dark in its brass ring), four lines from Lv 4 (epic) down to Lv 1, the slots
## see-through over the sand (pass 53: the weapons sit at the left edge, the lines at the right, no line between).
func _hud_levels() -> void:
	_clear_ui()
	_build([["weapon", "peashooter", 5], ["weapon", "boomstick", 4], ["weapon", "tommy_gun", 3], ["weapon", "hammer", 2],
		["weapon", "molotov", 1], ["evolution", "hive_queen", 1], ["passive", "brawn", 4], ["passive", "deadeye", 3],
		["passive", "evade", 2], ["passive", "mend", 1]])
	_mut("peashooter", 3)
	_mut("boomstick", 2)
	_mut("tommy_gun", 1)
	_run.build_changed.emit()
	_hud_common(14, 0.5, 240, 420.0)
	await _wait(0.8)
	await _shot("06d-hud-levels")


## 06e (pass 54): Phoenix Feather standing the hero up: its plate flies off him in embers and its banner says so, in its
## colour with its icon.
func _phoenix() -> void:
	_clear_ui()
	_build([["weapon", "boomstick", 3], ["passive", "phoenix_feather", 1]])
	_hud_common(6, 0.3, 40, 200.0)
	await _wait(0.3)
	var f = _reg.passive("phoenix_feather")
	var cam: Camera3D = g.camera.camera
	var at: Vector2 = cam.unproject_position(g.player.global_position + Vector3(0, 1.2, 0))
	g.hud.fly_item(f, at, Color(1.0, 0.55, 0.15))
	g.hud.banner("PHOENIX FEATHER", Color(1.0, 0.55, 0.15), f.icon if f else null)
	await _wait(0.55)
	await _shot("06e-hud-phoenix")
	await _wait(1.6)


## A thumb held on the joystick at `origin`, pushed along `dir` (the HUD draws the ring from the player's input).
func _stick(origin: Vector2, dir: Vector2) -> void:
	var inp = g.player.input
	inp.wants_move = true
	inp.keyboard = false
	inp.origin = origin
	inp.touch_pos = origin + dir * inp.radius_px()
	inp.stick_dir = dir


func _card(type: String, def, from: int, to: int) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _clear_ui() -> void:
	g.hud._banner.visible = false
	g.hud._top.modulate.a = 1.0
	g.hud.test_arrows = []
	g.hud.hide_boss()
	g.player.input.wants_move = false


## Cancels a confirmation pop-up (WConfirm, pass 45) on `host`, by class name: this script compiles before the kit's
## classes can be named.
func _cancel_confirm(host: Node) -> void:
	for n in host.get_children():
		var sc: Script = n.get_script()
		if sc and str(sc.get_global_name()) == "WConfirm" and not bool(n.get("_done")):
			n.call("cancel")


## 07: Level 3, Bristle (a new line with a trade), Desperado (a new passive item, its rarity's plate, held down),
## Boomstick 3 -> 4 (pass 48: five levels, the plate in Lv 4's epic, its mutation dots); Banish spent. 07b (pass 47): no
## skips and no banishes left this stage, SKIP tapped.
func _levelup() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["weapon", "boomstick", 3], ["passive", "magnet", 2]])
	_mut("boomstick", 1)
	_hud_common(3, 0.06, 10, 61.0)
	_run.rerolls_left = 1
	_run.skips_left = 2
	_run.banishes_left = 0
	var offer := [_card("passive", _reg.passive("bristle"), 0, 1), _card("passive", _reg.passive("desperado"), 0, 1),
		_card("weapon", _reg.weapon("boomstick"), 3, 4)]
	g.set_paused(true)
	g.cards.show_offer(offer, "LEVEL 3!", false)
	await _wait(0.9)
	g.cards._cards[1].show_held(true)
	if _want("levelup"):
		await _shot("07-level-up")
		g.cards._cards[1].show_held(false)
		_run.skips_left = 0
		g.cards._refresh_buttons()
		g.cards._skip()
		await _wait(0.3)
		await _shot("07b-level-up-spent")
		_run.skips_left = 2
	if _want("gate"):
		# the pick: Field Notes lands in the passive row and flies there while the dim lifts
		var rect: Rect2 = g.cards._cards[1].get_global_rect()
		g.cards.visible = false
		_run.debug_set_item("passive", "field_notes", 1)
		_run.build_changed.emit()
		_hud_common(4, 0.06, 10, 61.0)
		await _wait(0.1)
		g.resume_gate.open({"def": _reg.passive("field_notes"), "rect": rect})
		await _wait(0.9)
		await _shot("09-gate-tap-to-go")
		g.resume_gate.tap()
	# without the gate the cards stayed up under every later state
	g.cards.visible = false
	g.set_paused(false)


## 08: the Boomstick's paths. 29b / 29c (pass 54): the pre-reel spinning past the three weapons with an open path, then
## landing on the Boomstick, before the head and the cards come.
func _path() -> void:
	_clear_ui()
	_build([["weapon", "boomstick", 3], ["weapon", "peashooter", 2], ["weapon", "molotov", 2]])
	var ms: Array = _reg.mutations_of("boomstick")
	var offer: Array = []
	for m in ms:
		if offer.size() < 3 and not m.is_hero():
			offer.append(_card("mutation", m, 0, 1))
	g.set_paused(true)
	_run.skips_left = 2
	g.cards.show_offer(offer, "PATH · BOOMSTICK", false, true)
	await _wait(0.45)
	await _shot("29b-path-reel")
	var waited := 0.0
	while waited < 3.0 and g.cards._reel != null and not g.cards._reel.is_landed():
		await _wait(0.05)
		waited += 0.05
	await _wait(0.12)
	await _shot("29c-path-reel-landed")
	waited = 0.0
	while waited < 3.0 and g.cards.reel_running():
		await _wait(0.1)
		waited += 0.1
	await _wait(0.9)
	await _shot("08-path-offer")
	# pass 47: the stage's skips spent, SKIP tapped: the line under the head says so
	_run.skips_left = 0
	g.cards._refresh_buttons()
	g.cards._skip()
	await _wait(0.3)
	await _shot("08b-path-no-skips")
	_run.skips_left = 2
	g.cards.visible = false
	g.set_paused(false)


## 10: the reel lands on Orbit Saws, 3 -> 4. 10c (pass 47): the chest opening on the lower third, its light rising into
## the reel; 10d: BANISH tapped, the reel spun again to a new roll.
func _chest() -> void:
	_clear_ui()
	_build([["weapon", "orbit_saws", 3], ["weapon", "boomstick", 2], ["passive", "magnet", 2], ["passive", "evade", 2]])
	_run.skips_left = 2
	_run.banishes_left = 1
	g.set_paused(true)
	var saws = _reg.weapon("orbit_saws")
	var roll := {"type": "weapon", "id": "orbit_saws", "def": saws, "level_from": 3, "level_to": 4, "is_new": false}
	g.chest_screen.open(roll)
	# the lid open, the light climbing towards the reel's row
	g.chest_screen._tw.custom_step(0.86)
	await _wait(0.05)
	await _shot("10c-chest-opening")
	g.chest_screen._tw.set_speed_scale(8.0)
	await _wait(1.6)
	await _shot("10-chest")
	g.chest_screen._banish()
	g.chest_screen._tw.set_speed_scale(6.0)
	await _wait(1.2)
	await _shot("10d-chest-banished")
	# 10e: a purse of gold: SKIP and BANISH locked, TAKE IT
	_run.banishes_left = 1
	g.chest_screen.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	g.chest_screen._tw.set_speed_scale(8.0)
	await _wait(1.6)
	g.chest_screen._banish()
	await _wait(0.2)
	await _shot("10e-chest-gold")
	g.chest_screen.visible = false
	g.set_paused(false)


## 10b: the boss's reel (pass 45): nothing but the paths still open on the weapons held, landing on one of them.
func _chest_boss() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "boomstick", 2], ["passive", "magnet", 2]])
	g.set_paused(true)
	g.chest_screen.open(_run.chest_roll(true))
	g.chest_screen._tw.set_speed_scale(8.0)
	await _wait(1.6)
	await _shot("10b-chest-boss")
	g.chest_screen.visible = false
	g.set_paused(false)


## 11: 24 gold; Adrenaline 10, Thruster Burst 32 (8 short), Evade 16.
func _shop() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["passive", "magnet", 2], ["passive", "energy_shield", 4]])
	_run.run_gold = 24
	g.set_paused(true)
	var offer := [_card("passive", _reg.passive("adrenaline"), 0, 1), _card("perk", _reg.perk("thruster_burst"), 0, 1),
		_card("passive", _reg.passive("evade"), 0, 1)]
	g.structure_shop.open(offer)
	await _wait(0.9)
	await _shot("11-shop")
	g.structure_shop.visible = false
	# 11b (pass 60): a late build of 22 (five weapons, five lines, twelve passive items) in the YOU HOLD tray, which wraps
	# at 60 px, over the three cards priced by stage, kind and rarity; 300 gold, so one card is short. Run with inset=130
	# into another folder for the cutout's version.
	var build: Array = [["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4],
		["weapon", "molotov", 3], ["weapon", "boomstick", 2]]
	var n := 0
	for p in _reg.sorted_lines():
		if n >= 5:
			break
		build.append(["passive", p.id, 2])
		n += 1
	n = 0
	for p in _reg.sorted_passives_only():
		if n >= 12:
			break
		build.append(["passive", p.id, 1])
		n += 1
	_build(build)
	_run.run_gold = 300
	var offer2 := [_card("weapon", _reg.weapon("hornet_nest"), 3, 4), _card("passive", _reg.passive("clover"), 0, 1),
		_card("passive", _reg.passive("desperado"), 0, 1)]
	g.structure_shop.open(offer2)
	await _wait(0.9)
	await _shot("11b-shop-22")
	g.structure_shop.visible = false
	g.set_paused(false)


## 12: Guillotine straight to level 2, for 15 % of max HP.
func _stranger() -> void:
	_clear_ui()
	g.set_paused(true)
	g.stranger_screen.open({"type": "passive", "id": "guillotine", "def": _reg.passive("guillotine"), "level_from": 0, "level_to": 2, "is_new": true}, 0.15)
	await _wait(0.9)
	await _shot("12-stranger")
	g.stranger_screen.visible = false
	g.set_paused(false)


## 13, 13b, 13c: the build with Turret Buddy open, the stats, the options. 13e (pass 47): the Build tab scrolled to its
## lines and passive items (the passive items are on no HUD slot).
func _pause() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["passive", "magnet", 2], ["passive", "energy_shield", 4], ["passive", "clover", 2], ["passive", "desperado", 1],
		["passive", "brimstone_brand", 1], ["passive", "kindling", 2], ["passive", "steady_hand", 1]])
	_mut("turret_buddy", 2)
	_mut("molotov", 1)
	_run.build_changed.emit()
	_hud_common(3, 0.24, 10, 61.0)
	g.open_pause()
	g.pause_screen._expanded = "turret_buddy"
	g.pause_screen._tab = 0
	g.pause_screen._refresh()
	await _wait(0.8)
	await _shot("13-pause-build")
	g.pause_screen._expanded = ""
	g.pause_screen._refresh()
	await _wait(0.5)
	g.pause_screen._scroll.scroll_vertical = 999999
	await _wait(0.3)
	await _shot("13e-pause-build-passives")
	g.pause_screen._tab = 1
	g.pause_screen._refresh()
	await _wait(0.5)
	await _shot("13b-pause-stats")
	# the options: sound at the top (pass 54: its thumb whole at the list's right edge; the mock's was 80), music off, shake on
	var st := root.get_node("Settings")
	st.sfx_volume = 1.0
	st.music_volume = 0.0
	st.screen_shake = 1.0
	g.pause_screen._tab = 2
	g.pause_screen._refresh()
	await _wait(0.5)
	await _shot("13c-pause-options")
	# 13d (pass 45): abandoning asks in a pop-up over the board
	g.pause_screen._ask_abandon()
	await _wait(0.6)
	await _shot("13d-pause-abandon-confirm")
	_cancel_confirm(g.pause_screen)
	await _wait(0.3)
	g.close_pause()


## 14: down to the Tumbleweed King, one chance left, no gold for the paid revive.
func _down() -> void:
	_clear_ui()
	_run.run_gold = 0
	_hud_common(3, 0.2, 0, 61.0)
	_run.kills = 123
	g.set_paused(true)
	g.revive_screen.open(0, 1, "", {"by": "The Tumbleweed King", "kind": "boss"})
	g.revive_screen._held = true
	await _wait(0.8)
	await _shot("14-down")
	# 14b (pass 46): debug mode lists the last 30 seconds of hits and pickup heals on Down!, the killing hit crossed out
	var stx = root.get_node("Settings")
	stx.debug_mode = true
	g.revive_screen.open(0, 1, "", {"by": "The Brander", "kind": "boss", "role": "boss"}, _sample_hits())
	g.revive_screen._held = true
	await _wait(0.8)
	await _shot("14b-down-hits")
	stx.debug_mode = false
	g.revive_screen._open = false
	g.revive_screen.visible = false
	g.set_paused(false)


## 15: stage 1 cleared at 05:00 with 312 gold.
func _stage_clear() -> void:
	_clear_ui()
	_run.run_gold = 312
	_run.kills = 412
	_hud_common(11, 0.2, 312, 300.0)
	g.set_paused(true)
	g.portal_dialog.open(1, true, false)
	await _wait(0.8)
	await _shot("15-stage-clear")
	# 15c (pass 48): NOT YET under a finger
	var nb = g.portal_dialog.find_child("NotYet", true, false)
	if nb:
		nb.show_held(true)
		await _shot("15c-stage-clear-not-yet")
		nb.show_held(false)
	g.portal_dialog.visible = false
	# 15b (pass 43): after the last boss, the second road is Stay
	_run.stage = 2
	_run.elapsed = 900.0
	_run.run_gold = 1840
	g.portal_dialog.open(3, true, true)
	await _wait(0.8)
	await _shot("15b-stage-clear-final")
	g.portal_dialog.visible = false
	_run.stage = 0
	g.set_paused(false)


## 16: extracted at 10:00, stage 2, a new best; damage by four weapons; Orbit Saws unlocked.
func _results() -> void:
	_clear_ui()
	_run.extracted = true
	_run.elapsed = 600.0
	_run.stage = 1
	_run.level = 47
	_run.kills = 1204
	_run.chests_opened = 3
	_run.evolutions = 1
	_run.run_gold = 992
	# pass 47: every kind of source, each row its plate, name and number (the ids Run.add_damage is handed)
	_run.damage_by_weapon = {"killer_swarm": 6540.0, "big_mouth": 3410.0, "turret_buddy": 2560.0, "molotov": 1690.0,
		"revive": 900.0, "blast": 420.0, "loose_rocket": 130.0, "supply_drop": 260.0, "nuke": 210.0, "burn": 160.0,
		"poison": 95.0, "": 12.0, "mystery_beam": 6.0}
	_run.last_result = {"gold_before": 104711, "banked": 1240, "prev_best": {"time": 480.0}}
	var qt = load("res://core/systems/QuestTracker.gd")
	qt.just_completed = ["unlock_turret_buddy"]
	g.set_paused(false)
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _wait(1.6)
	await _shot("16-results")
	# 16c (pass 47): the damage rows scrolled to their end: fire, poison, the unknown "?"
	current_scene.scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("16c-results-sources")
	# 16b (pass 44): the hero stayed down; the gold is left in the sand, all but what a Strongbox banked
	_run.extracted = false
	_run.died = true
	_run.last_result = {"gold_before": 104711, "banked": 0, "lost": 992, "strongbox": 300, "prev_best": {"time": 480.0}}
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _wait(1.6)
	await _shot("16b-results-down")


## Hit-log rows as Player.damage_log keeps them (pass 46): a plain hit, an elite-modded creature in its modifier's colour,
## a ranged special, a pickup heal, an evaded Elite, and the boss's killing slam.
func _sample_hits() -> Array:
	return [
		{"t": 50.2, "by": "Skeleton", "id": "skeleton", "kind": "melee", "role": "", "colour": "", "fx": [], "raw": 6.0, "dealt": 6.0,
			"shield": 0.0, "note": "", "hp": 61.0, "fatal": false},
		{"t": 52.0, "by": "Skeleton Knight", "id": "skeleton_knight", "kind": "melee", "role": "elite", "colour": "#ee4a5c", "fx": [],
			"raw": 14.0, "dealt": 14.0, "shield": 0.0, "note": "", "hp": 47.0, "fatal": false},
		{"t": 53.1, "by": "Cake Slice", "id": "", "kind": "heal", "role": "", "colour": "", "fx": [], "raw": 9.0, "amount": 9.0, "dealt": 0.0,
			"shield": 0.0, "note": "", "hp": 56.0, "fatal": false},
		{"t": 55.4, "by": "Harpoon Troglodyte", "id": "harpoon_troglodyte", "kind": "ranged", "role": "special", "colour": "", "fx": ["hooked"],
			"raw": 12.0, "dealt": 12.0, "shield": 0.0, "note": "", "hp": 44.0, "fatal": false},
		{"t": 57.0, "by": "Stone Golem (Elite)", "id": "stone_golem", "kind": "melee", "role": "elite", "colour": "", "fx": [], "raw": 30.0,
			"dealt": 0.0, "shield": 0.0, "note": "evaded", "hp": 44.0, "fatal": false},
		{"t": 59.6, "by": "The Brander", "id": "brander", "kind": "boss", "role": "boss", "colour": "", "fx": ["slam"], "raw": 60.0,
			"dealt": 44.0, "shield": 0.0, "note": "", "hp": 0.0, "fatal": true},
	]
