## Renders the "Wanted" screens in the states the handoff's mocks show (design_handoff_88fits_wanted/screens), so each
## can be set beside its PNG (tools/wanted_compare.py). Windowed at the phone's canvas:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/wanted_shots.gd -- out=<dir> [only=hud,levelup] [white=1]
## white=1 hides the world behind a white sheet, as the mocks were drawn (they are transparent where the world is).
## inset=N puts the top inset the UI keeps clear of a camera cutout at N design px (pass 43), as a notched phone would.
## Pass 45 states beyond the mocks: 05b-settings-wipe-confirm
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
## Pass 87 (lane SUI, the stages): 18-stages (the Stages menu: stage 1 beaten, stage 2 open, stage 3 locked), 18b scrolled
## to its foot, 18c every stage beaten (only=stages; run with inset=130 too); 15 is the stage clear with its one road and
## the countdown to Endless (15b its last seconds in rock, 15c NOT YET held); 06f-hud-portal (the clock showing the
## portal's count, ENDLESS IN under it) and 06g-hud-endless (Endless's time on ink, WAVE 3 under it, the ENDLESS banner)
## (only=hud_stage).
extends SceneTree

var _out := "user://wanted_shots"
var _only: Array = []
var _white := false
var _inset := -1
## slot_rarity=1 (pass 122, lane UIHUD): the Royale HUD's slots in their level / rarity colours (Settings.hud_slot_rarity;
## off, the default, is the plain common frame on every slot).
var _slot_rarity := false
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
		elif a == "slot_rarity=1":
			_slot_rarity = true
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
	if _slot_rarity:
		# pass 122 (lane UIHUD): the Royale slots in their colours (in memory only; the save goes back at the end)
		root.get_node("Settings").set("hud_slot_rarity", true)
		print("wanted_shots: slot_rarity ", root.get_node("Settings").get("hud_slot_rarity"))
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	# pass 127 (lane DOCS): no debug surfaces on a capture, whatever the PC's save holds (in memory only)
	for k in ["debug_panel", "debug_modal_buttons", "free_revive_button", "hit_log", "debug_mode"]:
		root.get_node("Settings").set(k, false)
	# the captures fill the save with the mocks' numbers: the PC's own save goes back as it was at the end
	var kept := FileAccess.get_file_as_string("user://save.json")
	var in_run := ["hud", "hud_boss", "hud_full", "hud_levels", "hud_mutation", "phoenix", "levelup", "gate", "path", "chest", "chest_boss", "shop", "stranger", "pause", "down", "stageclear", "results", "hud_stage", "hud_kills"]
	# pass 123 (lane RUN_B): the shop's held card, the Totem gifts, the boss's own chest (BossChestScreen)
	in_run.append_array(["shop_held", "totem", "bosschest"])
	# pass 123 (lane RUN_C): the War Drum's moment and the Grindstone's show, frozen on their beats
	in_run.append_array(["drum", "grind"])
	var any_run := false
	for n in in_run:
		if _want(n):
			any_run = true
	if any_run:
		await _in_run()
	var menus := ["title", "trail", "collection", "collection_inset", "settings", "dev", "consent", "survey", "stages", "heroes", "collection_more", "kit2"]
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
		# pass 123 (lane RUN_C): 19d, a rating picked (the mock's 10_Survey: the pick lit, NEXT on)
		var r4: Control = card.find_child("Rate4", true, false)
		if r4:
			r4.emit_signal("pressed")
			await _wait(0.3)
			await _shot("19d-survey-picked")
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


## 18 (pass 87): the Stages menu for the Drifter on Red Canyon: stage 1 beaten (its stamp), stage 2 open, stage 3
## locked (its requirement); 18b scrolled to its foot; 18c every stage beaten. The save's stages go back after.
func _stages() -> void:
	var keep: Dictionary = (_save.data.get("stages_beaten", {}) as Dictionary).duplicate(true)
	_save.data["last_character"] = "drifter"
	_save.data["last_map"] = "red_canyon"
	_save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	# pass 88 (lane STAGEMENU): the bosses met so far: the King only (the Gila and the Brander hidden)
	var keep_seen = _save.data.get("seen", {}).duplicate(true) if _save.data.get("seen") is Dictionary else {}
	var keep_kills = _save.data["totals"].get("kills_of_enemy", {}).duplicate(true) if _save.data.get("totals") is Dictionary else {}
	if _save.data.get("totals") is Dictionary:
		_save.data["totals"]["kills_of_enemy"] = {}
	_save.data["seen"] = {"enemy": ["tumbleweed_king"]}
	await _scene("res://ui/StagesScreen.tscn")
	await _wait(0.6)
	await _shot("18-stages")
	current_scene.scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("18b-stages-scrolled")
	_save.data["stages_beaten"] = {"red_canyon": [true, true, true, true]}
	_save.data["seen"] = {"enemy": ["tumbleweed_king", "gila_grande", "brander"]}
	await _scene("res://ui/StagesScreen.tscn")
	await _wait(0.6)
	await _shot("18c-stages-all-beaten")
	# pass 123 (lane STAGES_SETTINGS): 18d a first visit (nothing beaten or met, no best run: the run line is the map's
	# name alone), 18e under a 130 px camera cutout with the first card's START held
	var keep_best = _save.data["best_runs"].get("red_canyon", {}) if _save.data.get("best_runs") is Dictionary else {}
	_save.data["stages_beaten"] = {"red_canyon": [false, false, false]}
	_save.data["seen"] = {"enemy": []}
	if _save.data.get("best_runs") is Dictionary:
		_save.data["best_runs"].erase("red_canyon")
	await _scene("res://ui/StagesScreen.tscn")
	await _wait(0.6)
	await _shot("18d-stages-first-visit")
	if _save.data.get("best_runs") is Dictionary and not (keep_best as Dictionary).is_empty():
		_save.data["best_runs"]["red_canyon"] = keep_best
	_save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	_save.data["seen"] = {"enemy": ["tumbleweed_king"]}
	var stc18 := root.get_node("Settings")
	var was18: int = stc18.top_inset
	stc18.top_inset = 130
	await _scene("res://ui/StagesScreen.tscn")
	await _wait(0.6)
	var c18: Array = current_scene.cards() if current_scene.has_method("cards") else []
	if not c18.is_empty():
		var sb18: Node = (c18[0] as Node).find_child("Start", true, false)
		if sb18 and sb18.has_method("show_held"):
			sb18.call("show_held", true)
	await _wait(0.2)
	await _shot("18e-stages-inset130-held")
	stc18.top_inset = was18
	_save.data["stages_beaten"] = keep
	_save.data["seen"] = keep_seen
	if _save.data.get("totals") is Dictionary:
		_save.data["totals"]["kills_of_enemy"] = keep_kills


## 01-05, 17: the menus with the mocks' purse and best run.
func _menus() -> void:
	_save.data["gold"] = 104711
	_save.data["best_runs"]["red_canyon"] = {"time": 600.0, "level": 47, "stage": 2}
	if _want("title"):
		_save.data["last_character"] = "drifter"
		await _scene("res://ui/TitleScreen.tscn")
		await _shot("01-title")
		# Astro comes after the Drifter since pass 61 (Garry's order: Drifter, Astro, Calavera, Ironwood, Solenne)
		await _wait(0.8)
		await _shot("01b-title-rest")
		current_scene._step(1)
		await _wait(0.28)
		await _shot("02r-title-swap")
		await _wait(1.0)
		await _shot("02-title-astro")
		# pass 43: Calavera, the third hero, with his favourite and his own weapon on the plaque
		var tc = current_scene
		for i in (tc._heroes as Array).size():
			if (tc._heroes[i] as Resource).get("id") == "calavera":
				tc._index = i
				tc._show_hero(1)
		await _wait(1.0)
		await _shot("02b-title-calavera")
		# pass 47: Ironwood, his favourite a line (Brawn) on the plaque and no weapon of his own
		for i in (tc._heroes as Array).size():
			if (tc._heroes[i] as Resource).get("id") == "ironwood":
				tc._index = i
				tc._show_hero(1)
		await _wait(1.0)
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
		await _title_buy()
	if _want("consent") or _want("survey"):
		await _cards60()
	if _want("stages"):
		await _stages()
	if _want("trail"):
		# the Trail a quarter of the way along, 108,411 in the purse (pass 129; the Upgrade board's 03-mirror states until
		# then; the Trail's own states: tools/_p129_TRAIL_shots.gd)
		_save.data["gold"] = 108411
		_save.data["last_character"] = "drifter"
		load("res://tools/trail_arg.gd").apply(_save, "quarter")
		await _scene("res://ui/TrailScreen.tscn")
		await _shot("03-trail")
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
	if _want("collection_more"):
		await _collection_more()
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
		# pass 123 (lane STAGES_SETTINGS): 05c the foot (play data, the wipe, the version line); 05d the Debug panel of
		# the player's debug mode (the UI theme row), scrolled to it
		current_scene.scroll.scroll_vertical = 999999
		await _wait(0.4)
		await _shot("05c-settings-foot")
		var dbg_was: bool = st.debug_mode
		st.debug_mode = true
		await _scene("res://ui/SettingsScreen.tscn")
		var dp: Control = current_scene.find_child("DebugPanel", true, false)
		if dp:
			var sc: ScrollContainer = current_scene.scroll
			sc.scroll_vertical = int(dp.get_global_rect().position.y - sc.get_global_rect().position.y - 40.0)
		await _wait(0.4)
		await _shot("05d-settings-debug")
		st.debug_mode = dbg_was
	if _want("dev"):
		var st2 := root.get_node("Settings")
		for k in ["debug_panel", "debug_modal_buttons", "free_revive_button", "hit_log", "debug_mode"]:
			st2.set(k, false)
		change_scene_to_file("res://ui/DevMenu.tscn")
		await _wait(0.9)
		await _shot("17-developer-menu")
	if _want("kit2"):
		await _kit2()
	if _want("heroes"):
		await _heroes_shots()


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
	# pass 127 (lane DOCS): a capture shows the game, not the arena: no banner, no quick buttons, real creatures for the dummies
	g.hud._banner.visible = false
	g.hud._banner_text = ""
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.call("_clear_field")
		for c in g.arena_panel.get_children():
			c.visible = false
		g.arena_panel.visible = false
	_crowd()
	if _want("hud"):
		await _hud_basic()
	if _want("hud_boss"):
		await _hud_boss()
	if _want("hud_full"):
		await _hud_full()
	if _want("hud_levels"):
		await _hud_levels()
	if _want("hud_mutation"):
		await _hud_mutation()
	if _want("phoenix"):
		await _phoenix()
	if _want("levelup") or _want("gate"):
		await _levelup()
	if _want("path"):
		await _path()
	# pass 123 (lane RUN_C): 30 / 30b the War Drum's moment, 31 .. 31c the Grindstone's show
	if _want("drum"):
		await _drum_moment()
	if _want("grind"):
		await _grind_moment()
	if _want("chest"):
		await _chest()
	if _want("chest_boss"):
		await _chest_boss()
	if _want("shop"):
		await _shop()
	if _want("stranger"):
		await _stranger()
	if _want("shop_held"):
		await _shop_held()
	if _want("totem"):
		await _totem()
	if _want("bosschest"):
		await _bosschest()
	if _want("pause"):
		await _pause()
	if _want("down"):
		await _down()
	if _want("hud_stage"):
		await _hud_stage()
	if _want("hud_kills"):
		await _hud_kills()
	if _want("stageclear"):
		await _stage_clear()
	if _want("results"):
		await _results()


## Pass 127 (lane DOCS): creatures standing still up the screen where the arena's dummies stood, tough enough to last the captures.
func _crowd() -> void:
	var at: Vector3 = g.player.global_position
	var rows := [["goblin", 7, -5.5], ["skeleton", 6, -7.5], ["fire_ant", 7, -9.5], ["lesser_scorpion", 5, -11.5]]
	for row in rows:
		for k in int(row[1]):
			var off := Vector3((k - int(row[1]) / 2.0) * 1.15 + randf_range(-0.2, 0.2), 0, float(row[2]) + randf_range(-0.5, 0.5))
			var i: int = g.enemies.spawn(str(row[0]), at + off, null, 1.0, 1.0)
			if i >= 0:
				g.enemies.speed[i] = 0.0
				g.enemies.hp[i] = 200000.0


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


## 06e (pass 79, lane MUT): a mutation offer due, so the next level-up is a mutation level-up: the LV plate in the kit's
## mutation plum and MUTATION NEXT at the XP rail's end (HUD._refresh_mut_mark).
func _hud_mutation() -> void:
	_build([["weapon", "hornet_nest", 3], ["weapon", "boomstick", 2], ["weapon", "molotov", 3], ["passive", "magnet", 2]])
	_mut("hornet_nest", 1)
	_run.build_changed.emit()
	_hud_common(12, 0.7, 120, 300.0)
	_run.mutlvl_due = 1
	_run.mutation_due_changed.emit()
	g.hud.set_hp(80, 100)
	await _wait(0.5)
	await _shot("06e-hud-mutation-next")
	_run.mutlvl_due = 0
	_run.mutation_due_changed.emit()


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
	# 10f (pass 122, lane UICHEST): the reel running, its tiles passing the landing cell (the kit's frames under Royale)
	g.chest_screen._tw.custom_step(1.1)
	await _wait(0.05)
	await _shot("10f-chest-reel")
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
		# pass 123 (lane KIT2): no one-shot item (`single`, the Grindstone since pass 121): handed over here it did its deed,
		# and its show (GrindMoment) stayed up over every later capture (12-stranger, 13-pause-build ...)
		if bool(p.get("single")):
			continue
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


## 11c (pass 123, lane RUN_B): the 300-gold shop of 11b with its first affordable card held down (the press look: the
## Royale gold edge, glow and rays), the short card beside it as it stands.
func _shop_held() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["passive", "magnet", 2], ["passive", "energy_shield", 4]])
	_run.run_gold = 300
	g.set_paused(true)
	var offer := [_card("weapon", _reg.weapon("hornet_nest"), 3, 4), _card("passive", _reg.passive("clover"), 0, 1),
		_card("passive", _reg.passive("desperado"), 0, 1)]
	g.structure_shop.open(offer)
	await _wait(0.9)
	var shop = g.structure_shop
	for i in range(mini(shop._cards.size(), offer.size())):
		if shop.price_of(offer[i]) <= int(_run.run_gold):
			shop._cards[i].show_held(true)
			break
	await _wait(0.3)
	await _shot("11c-shop-held")
	g.structure_shop.visible = false
	g.set_paused(false)


## 30, 30b (pass 123, lane RUN_B): the Totem gifts with the mock's offer from the pole's own pool (Le-loo +2 %, Kuuma
## +1 %, Chet-woot +2 %: the mock's 8_Totem), "TOTEM 1 OF 10"; 30b the middle gift held. 30c: a pole the map's count
## does not know ("4TH TOTEM").
func _totem() -> void:
	_clear_ui()
	var d = _reg.structure("totem_pole")
	if d == null:
		print("wanted_shots: no totem_pole structure")
		return
	var boons = load("res://core/systems/TotemBoons.gd")
	var pool: Array = boons.pool_of(d)
	var want := {"wolf": 0.02, "bullhead": 0.01, "bear": 0.02}
	var offer: Array = []
	for id in ["wolf", "bullhead", "bear"]:
		for e: Dictionary in pool:
			if str(e.get("id", "")) == id:
				var b: Dictionary = {"id": id, "name": str(e.get("name", "")), "animal": str(e.get("animal", "")),
					"stat": str(e.get("stat", "")), "op": str(e.get("op", "add")), "value": float(want[id]),
					"min": float(e.get("min", 0.0)), "max": float(e.get("max", 0.0))}
				b["quality"] = boons.quality(float(b["value"]), float(b["min"]), float(b["max"]))
				offer.append(b)
	g.set_paused(true)
	var ts = g.totem_screen
	ts.open(offer, d, 1, 10)
	await _wait(1.0)
	await _shot("30-totem")
	var rows: Array = ts.planks()
	if rows.size() >= 2:
		rows[1].show_held(true)
		await _wait(0.3)
		await _shot("30b-totem-held")
		rows[1].show_held(false)
	ts._hide()
	ts.open(offer, d, 4, 0)
	await _wait(1.0)
	await _shot("30c-totem-4th")
	ts._hide()
	g.set_paused(false)


## 31, 31b, 31c (pass 123, lane RUN_B): the boss's own chest (BossChestScreen, pass 118) for the King after a 45 s fight
## (BossChest.sample_pack, the speed bonus near its top): the spew under way (BIG WIN!), JACKPOT!, CLAIM up; a slower
## Gila (31d, CLAIM) for a small bonus.
func _bosschest() -> void:
	_clear_ui()
	var BC = load("res://core/systems/BossChest.gd")
	var BCS = load("res://ui/BossChestScreen.gd")
	for b: Array in [["tumbleweed_king", 0, 45.0, ["31-bosschest-spew", "31b-bosschest-jackpot", "31c-bosschest-claim"]],
			["gila_grande", 1, 240.0, ["", "", "31d-bosschest-gila-claim"]]]:
		var pack: Dictionary = BC.sample_pack(str(b[0]), int(b[1]), float(b[2]))
		if pack.is_empty():
			continue
		g.open_boss_chest(g.player.global_position + Vector3(0.8, 0, -0.6), str(b[0]), pack)
		await process_frame
		await process_frame
		var bs = g.boss_chest_screen
		if bs == null or not bs.visible:
			print("wanted_shots: the boss chest did not open")
			continue
		bs.set_process(false)
		var spew: float = float(bs.get("_spew_len"))
		var names: Array = b[3]
		if str(names[0]) != "":
			bs.seek(BCS.SPEW_AT + spew * 0.55)
			await _wait(0.2)
			await _shot(str(names[0]))
		var end_t: float = float(bs.get("_end_t"))
		if str(names[1]) != "":
			bs.seek(end_t + BCS.FINALE + 0.1)
			await _wait(0.2)
			await _shot(str(names[1]))
		bs.seek(end_t + BCS.CLAIM_AFTER + 0.6)
		await _wait(0.3)
		await _shot(str(names[2]))
		bs.set_process(true)
		bs.claim()
		await _wait(0.5)
		g.modal_reset()
		g.set_paused(false)
		await _wait(0.3)


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
	# 14c/14d (pass 123, lane RUN_A): Down! as a player sees it (no hit log, no developer buttons: both switches off, put
	# back after), with gold to bank, then with no chance left (GET UP locked)
	var was_log: bool = bool(stx.get("hit_log"))
	var was_free: bool = bool(stx.get("free_revive_button"))
	stx.set("hit_log", false)
	stx.set("free_revive_button", false)
	_run.run_gold = 86
	g.revive_screen.open(86, 1, "", {"by": "Skeleton Knight", "kind": "melee", "role": "elite", "colour": "#ee4a5c"})
	g.revive_screen._held = true
	await _wait(0.8)
	await _shot("14c-down-plain")
	g.revive_screen.open(86, 0, "", {"by": "The Tumbleweed King", "kind": "boss", "role": "boss"})
	g.revive_screen._held = true
	await _wait(0.8)
	await _shot("14d-down-no-chance")
	stx.set("hit_log", was_log)
	stx.set("free_revive_button", was_free)
	_run.run_gold = 0
	g.revive_screen._open = false
	g.revive_screen.visible = false
	g.set_paused(false)


## 15: stage 1 cleared at 05:00 with 312 gold.
func _stage_clear() -> void:
	_clear_ui()
	_run.run_gold = 312
	_run.kills = 412
	_hud_common(11, 0.2, 312, 430.0)
	g.set_paused(true)
	# pass 87: one road and the countdown to Endless (the count pinned: the arena has no portal timer)
	var pd = g.portal_dialog
	pd.seconds_source = func() -> float: return 59.0
	pd.open(1, true, false)
	await _wait(0.8)
	await _shot("15-stage-clear")
	# 15c (pass 48): NOT YET under a finger
	var nb = pd.find_child("NotYet", true, false)
	if nb:
		nb.show_held(true)
		await _shot("15c-stage-clear-not-yet")
		nb.show_held(false)
	# 15b (pass 87): its last seconds, the count in rock
	pd.seconds_source = func() -> float: return 7.0
	await _wait(0.5)
	await _shot("15b-stage-clear-last-seconds")
	pd.visible = false
	pd.seconds_source = Callable()
	g.set_paused(false)


## 06f/06g (pass 87): the clock plate while the portal counts down to Endless (rock, ENDLESS IN under it), then in
## Endless (ink, its time survived, WAVE 3 under it, the ENDLESS banner).
func _hud_stage() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 4], ["weapon", "boomstick", 3], ["weapon", "molotov", 3], ["passive", "magnet", 3]])
	_hud_common(14, 0.4, 268, 430.0)
	g.hud.test_arrows = [{"pos": Vector2(1080, 748), "color": Color("6e8b5e"), "side": 1, "text": "PORTAL 24 m"}]
	g.hud.test_stage_clock = {"portal_left": 42.0, "endless": false}
	g.hud.tick(0.0)
	await _wait(0.4)
	await _shot("06f-hud-portal")
	g.hud.test_arrows = []
	g.hud.test_stage_clock = {"endless": true, "endless_wave": 3, "endless_seconds": 31.0}
	g.hud.tick(0.0)
	await _wait(0.5)
	await _shot("06g-hud-endless")
	g.hud.test_stage_clock = {}
	g.hud.tick(0.0)
	g.hud._banner.visible = false


## 06h/06i/06j (pass 109): the kill counter under the clock (WKillCount): at rest after a slow minute (1,234 kills), at
## the peak of a hot ding after kills poured in at 40 a second, and under the Endless tag. The run is paused for each
## shot so the ding is frozen where it is wanted (the counter is ticked by hand).
func _hud_kills() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "boomstick", 2], ["weapon", "molotov", 3], ["passive", "magnet", 2]])
	_hud_common(6, 0.5, 86, 140.0)
	var kc = g.hud.kill_counter()
	g.set_paused(true)
	_run.kills = 1234
	kc.tick(0.0, 1234)
	kc.rate = 0.0
	kc.tick(5.0, 1234)
	g.hud.tick(0.0)
	await _wait(0.3)
	await _shot("06h-hud-kills-rest")
	# hot: 40 kills a second for two seconds, then the frame a ding lands
	for i in 120:
		_run.kills += 1 if i % 3 != 0 else 0
		kc.tick(1.0 / 60.0, _run.kills)
	kc.set("_since", 1.0)
	_run.kills += 2
	kc.tick(0.0, _run.kills)
	await _shot("06i-hud-kills-hot")
	g.hud.test_stage_clock = {"endless": true, "endless_wave": 2, "endless_seconds": 12.0}
	g.hud.tick(0.0)
	kc.rate = 0.0
	kc.tick(5.0, _run.kills)
	await _wait(0.3)
	await _shot("06j-hud-kills-endless")
	g.hud.test_stage_clock = {}
	g.hud.tick(0.0)
	g.hud._banner.visible = false
	g.set_paused(false)


## 16: extracted at 10:00, stage 2, a new best; damage by every kind of source; Turret Buddy unlocked. Pass 72: the
## Results tell the run as a show (tools/results_story.gd's made-up run): 16 is its end at the top, 16c the end scrolled
## down to the unlocks, 16d the kills chart half drawn, 16e an unlock's stamp landing, 16b the run that ended in a fall
## (its graves on the chart) at its end.
func _results() -> void:
	_clear_ui()
	_run.level = 47
	var qt = load("res://core/systems/QuestTracker.gd")
	var story = load("res://tools/results_story.gd")
	story.fill(_run, _save, qt, false)
	# pass 47: every kind of source, each row its plate, name and number (the ids Run.add_damage is handed)
	for pair in [["supply_drop", 260.0], ["nuke", 210.0], ["poison", 95.0], ["", 12.0], ["mystery_beam", 6.0]]:
		_run.damage_by_weapon[pair[0]] = float(pair[1])
	g.set_paused(false)
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _show_at("chart", 0.5)
	await _shot("16d-results-chart")
	await _show_at("unlock", 0.55)
	await _shot("16e-results-unlock")
	current_scene.skip_all()
	# the stamp's burst has gone by (WCelebrate.LIFE)
	await _wait(2.0)
	current_scene.scroll.scroll_vertical = 0
	await _wait(0.3)
	await _shot("16-results")
	current_scene.scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("16c-results-sources")
	# 16b (pass 44): the hero stayed down; since pass 70 a death banks the purse like an extraction (Game.bank_run_end)
	story.fill(_run, _save, qt, true)
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _wait(0.5)
	current_scene.skip_all()
	await _wait(0.6)
	current_scene.scroll.scroll_vertical = 0
	await _wait(0.3)
	await _shot("16b-results-down")


## Waits (at most 25 s) until the Results' show has come `frac` of the way through its part `part`, or past it.
func _show_at(part: String, frac: float) -> void:
	var order := ["gold", "breath", "chart", "sources", "pause", "scroll", "unlock", "progress", ""]
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var rs = current_scene
		if rs and rs.has_method("part_name"):
			var now: String = rs.call("part_name")
			if (now == part and float(rs.call("part_frac")) >= frac) or now == "" or order.find(now) > order.find(part):
				return
		await process_frame


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


## k2a..k2e (pass 123, lane KIT2): the kit's shared pieces on a hub screen made for the capture: a ScreenBase with the
## Upgrade tab open in the docked tab bar, the wallet, and a solid sheet holding pills, price buttons and solid cells
## (k2a); then the modal shell (WConfirm.shell) as the survey (k2b: a star line with its corner word, a left title, a
## rating row, NOT NOW and a blue NEXT, the link under the card), the Hero details (k2c: a tall card, the corner word,
## CLOSE) and the play-data card (k2d: the game's own words, NO THANKS and a gold OK). Every word and number is the
## game's (k2e, the Upgrade board's choice, left with the board in pass 129).
func _kit2() -> void:
	_save.data["gold"] = 108411
	_save.data["last_character"] = "drifter"
	var src := "extends ScreenBase
func tab_bar() -> String:
	return \"upgrade\"
"
	src += "func header_right() -> Control:
	return WMenuHeader.gold_plate(108411, 44, 40.0, 5, 4)
"
	src += "func on_back() -> void:
	pass
"
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	var scr: Control = gs.new()
	scr.name = "KitHub"
	change_scene_to_node(scr)
	await _wait(0.9)
	var hub = current_scene
	var W_: GDScript = load("res://ui/wanted/W.gd")
	var R_: GDScript = load("res://ui/wanted/R.gd")
	hub.set_title("Trail")
	var sheet: PanelContainer = hub.solid_sheet(Vector2(24, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	sheet.add_child(v)
	var drifter = _reg.character("drifter")
	v.add_child(W_.label("Pills", 18, W_.INK_SOFT))
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 14)
	var rc = _reg.map("red_canyon")
	var stage_list: Array = rc.timeline.stage_list if rc and rc.timeline else []
	var boss_at := float((stage_list[0] as Dictionary).get("length", 430.0)) if not stage_list.is_empty() else 430.0
	pills.add_child(W_.pill([{"glyph": "clock", "px": 24}, "%s to the boss" % W_.mmss(boss_at)]))
	pills.add_child(W_.pill(drifter.display_name if drifter else "The Drifter"))
	v.add_child(pills)
	v.add_child(W_.label("Prices", 18, W_.INK_SOFT))
	var cost := 100
	var prices := HBoxContainer.new()
	prices.add_theme_constant_override("separation", 20)
	prices.add_child(W_.price_row(cost, "CHOOSE", "blue"))
	prices.add_child(W_.price_row(cost, "BUY", "green"))
	prices.add_child(W_.price_row(cost * 9, "BUY", "green", 28, cost * 9 - 300))
	v.add_child(prices)
	v.add_child(W_.label("Cells", 18, W_.INK_SOFT))
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 12)
	var bs = _reg.weapon("boomstick")
	for k in 3:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", W_.cell_box())
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(W_.serif_text("Level %d" % (k + 2) if bs else "", 24, W_.INK))
		cells.add_child(cell)
	v.add_child(cells)
	hub.content.add_child(sheet)
	await _wait(0.6)
	await _shot("k2a-hub-tabbar")
	# k2b: the survey's shape
	var WConfirm_: GDScript = load("res://ui/wanted/WConfirm.gd")
	var sv = WConfirm_.shell(hub, {"star": "A quick word", "corner": "1 / 2", "title": "How much fun was that run?",
		"title_px": 44, "title_align": "left", "title_upper": false, "min_h": 620, "keep_open": true,
		"button_h": 96, "button_px": 34, "link": "Don't ask me again",
		"buttons": [{"id": "cancel", "text": "Not now", "role": "slate"}, {"id": "next", "text": "Next", "role": "blue"}]})
	var rate := HBoxContainer.new()
	rate.add_theme_constant_override("separation", 14)
	for k in 5:
		var b = WConfirm_.make_button([str(k + 1)], "gold" if k == 3 else "slate", 96.0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rate.add_child(b)
	sv.body_box.add_child(rate)
	var ends := HBoxContainer.new()
	var lo = W_.serif_text("Not fun", 20, W_.INK_SOFT, 400, true)
	lo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(lo)
	ends.add_child(W_.serif_text("Loved it", 20, W_.INK_SOFT, 400, true))
	sv.body_box.add_child(ends)
	await _wait(0.6)
	await _shot("k2b-shell-survey")
	sv.cancel()
	await _wait(0.4)
	# k2c: the Hero details' shape (a tall card, the corner word, CLOSE)
	var hd = WConfirm_.shell(hub, {"title": drifter.display_name if drifter else "", "title_px": 56, "title_align": "left",
		"corner": "Details", "min_h": 1080, "button_h": 96, "button_px": 40,
		"buttons": [{"id": "cancel", "text": "Close", "role": "slate"}]})
	var hp := HBoxContainer.new()
	hp.add_theme_constant_override("separation", 12)
	hp.add_child(W_.pill("TRAIT", 20, 40.0))
	hp.add_child(W_.pill(drifter.flavour if drifter and str(drifter.get("flavour")) != "" else "", 22, 40.0))
	hd.body_box.add_child(hp)
	await _wait(0.6)
	await _shot("k2c-shell-details")
	hd.cancel()
	await _wait(0.4)
	# k2d: the play-data card's shape, its own words
	var consent: GDScript = load("res://ui/wanted/WConsent.gd")
	var cd = WConfirm_.shell(hub, {"star": "A quick word", "title": "Play data", "body": consent.body_text(_save.player_name()),
		"min_h": 620, "dim_cancels": false,
		"buttons": [{"id": "cancel", "text": "No thanks", "role": "slate"}, {"id": "confirm", "text": "OK", "role": "gold"}]})
	await _wait(0.6)
	await _shot("k2d-shell-consent")
	cd.cancel()
	await _wait(0.4)
	print("wanted_shots: kit2 theme ", "royale", " tab bar ", hub.tab_bar_node != null, " R ", R_ != null)


## 30 / 30b (pass 123, lane RUN_C): the War Drum's moment frozen on its beats (its clock stepped by hand at 60 fps): the
## first slap (the drum squashed on its stand, its waves and slap lines, the title thumping) and the big slap with the
## boost in words; then it ends and the boost it left is taken back, so no later state wears its plate.
func _drum_moment() -> void:
	_clear_ui()
	var d = _reg.structure("war_drum")
	if d == null:
		print("wanted_shots: no war_drum structure")
		return
	g.set_paused(false)
	g.use_structure(d, g.player.global_position)
	var guard := 0
	while guard < 90 and (g.get("drum_moment") == null or not bool(g.drum_moment.playing)):
		await process_frame
		guard += 1
	var dm = g.get("drum_moment")
	if dm == null or not bool(dm.playing):
		print("wanted_shots: the drum's moment did not open")
		return
	dm.set_process(false)
	for pair in [[0.4, "30-drum-slap"], [1.7, "30b-drum-words"]]:
		var n := 0
		while bool(dm.playing) and float(dm.t) < float(pair[0]) and n < 600:
			dm.call("_process", 1.0 / 60.0)
			n += 1
		await _shot(str(pair[1]))
	dm.set_process(true)
	dm.skip()
	await _wait(0.2)
	for tb in _run.timed:
		if str(tb["id"]).begins_with("structure:"):
			tb["until"] = 0.0
	g.set_paused(false)
	await _wait(0.3)
	# and its toast ("WAR DRUM: 15 s"), which would stand over the next states
	_clear_toasts()


## The HUD's toasts gone at once (pass 123, lane RUN_C: the drum's and the Grindstone's stood over the next captures):
## each shown one aged past its fade (WToasts frees it on its next tick) and hidden now, the queue emptied.
func _clear_toasts() -> void:
	var t = g.hud.get("_toasts")
	if t == null:
		return
	for s in t.get("_shown"):
		s[1] = 1000.0
		if is_instance_valid(s[0]):
			(s[0] as CanvasItem).modulate.a = 0.0
	(t.get("_queue") as Array).clear()


## 31 .. 31c (pass 123, lane RUN_C): the Grindstone's show frozen on its beats (its clock stopped and stepped with seek,
## as tools/_p121_GRIND_shots.gd does): the grind with its sparks and the level stamped (the Boomstick 2 -> 3, the
## weakest beside the Revolver at 3), then an evolution's burst (the Revolver at 5 with its three mutations into the
## Golden Revolver). The gate is tapped away and the Grindstone taken back after each, so no later state wears it (the
## pass 121 artefact lane KIT2 removed from the shop's build).
func _grind_moment() -> void:
	_clear_ui()
	if _reg.passive("grindstone") == null:
		print("wanted_shots: no grindstone")
		return
	for tag in ["level", "evolve"]:
		g.set_paused(false)
		if tag == "level":
			_build([["weapon", "revolver", 3], ["weapon", "boomstick", 2]])
		else:
			_build([["weapon", "revolver", 5]])
			for m in _reg.mutations_of("revolver"):
				_run.add_mutation(m.id, true)
		_hud_common(6, 0.3, 40, 95.0)
		_run.passives.erase("grindstone")
		_run.grind_used = {}
		await _wait(0.4)
		_run.add_or_level_passive("grindstone")
		var guard := 0
		while guard < 120 and (g.get("grind_moment") == null or not bool(g.grind_moment.playing)):
			await process_frame
			guard += 1
		var gm = g.get("grind_moment")
		if gm == null or not bool(gm.playing):
			print("wanted_shots: the Grindstone's show did not open (%s)" % tag)
			continue
		gm.set_process(false)
		_clear_toasts()
		var beats: Array = [[0.75, "31-grind-sparks"], [2.3, "31b-grind-level"]] if tag == "level" else [[2.75, "31c-grind-evolved"]]
		for pair in beats:
			gm.seek(float(pair[0]))
			await _shot(str(pair[1]))
		gm.set_process(true)
		gm.skip()
		await process_frame
		await _wait(0.2)
		if g.resume_gate.visible:
			g.resume_gate.tap()
		await _wait(0.3)
	_run.passives.erase("grindstone")
	_run.grind_used = {}
	_run.build_changed.emit()
	g.set_paused(false)
	await _wait(0.2)
	_clear_toasts()


## 40-41 (pass 123, lane HEROES; only=heroes): the Heroes screen (ui/HeroesScreen.tscn, the Royale HEROES tab) and the
## Hero details pop-up (ui/wanted/WHeroSheet.gd). The save: the Drifter owned and picked, Ironwood and Astro on sale (no
## quest), Calavera's quest done (on sale), the rest locked; 104,711 gold. Under Royale: 40-heroes (the Drifter, the
## mock's 5_Heroes), 40b-heroes-onsale (Ironwood: BUY), 40c-heroes-locked (Fadeaway: LOCKED and his quest),
## 40d-heroes-short (Astro with 600 gold: the grey price and what it is short), 40e-heroes-buy-confirm (Ironwood's BUY
## asked), 40f-heroes-looks (Fadeaway owned, Purple Reign on sale in the strip), 40g-heroes-scrolled (the page at its
## foot: the grid over the tab bar); 41-hero-details (DETAILS · ALL STATS, the mock's 5_Hero_details), 41b-hero-details-items
## (scrolled to the items), 41c-hero-details-looks (Fadeaway's, at its foot), 41d-hero-details-onsale and
## 41e-hero-details-locked (a hero not owned). Pass 126 (lane UI): 40g is the page at its foot under the locked picker, 40i the
## Buy this look? question with its coin, 40j the picker with the hidden heroes previewed (a third row: its own thumb, scrolled).
## Under Wanted nothing reaches the screen: 40-heroes is today's way to the
## heroes (the title, its hero drawer open), 40b/40c the title showing that hero, and the 41 states today's sheet over the
## title. The save's heroes, quests, looks and gold go back after.
func _heroes_shots() -> void:
	var keep := {}
	for k in ["gold", "heroes_owned", "quests_done", "skins_owned", "skin_worn", "hero_look", "last_character"]:
		var v = _save.data.get(k)
		keep[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	var W_: GDScript = load("res://ui/wanted/W.gd")
	var path := "res://ui/HeroesScreen.tscn"
	var on_screen: bool = ResourceLoader.exists(path)
	_save.data["gold"] = 104711
	_save.data["last_character"] = "drifter"
	_save.data["hero_look"] = {}
	_save.data["skin_worn"] = {}
	_save.data["skins_owned"] = []
	_save.data["heroes_owned"] = ["drifter"]
	var done: Array = (_save.data.get("quests_done", []) as Array).duplicate()
	if not done.has("unlock_calavera"):
		done.append("unlock_calavera")
	for q in ["unlock_solenne", "unlock_fadeaway", "unlock_buck", "unlock_may", "skin_fadeaway_fad_b"]:
		done.erase(q)
	_save.data["quests_done"] = done
	var host = null
	if on_screen:
		await _scene(path)
		await _wait(0.8)
		host = current_scene
		await _shot("40-heroes")
		host.show_hero(_reg.character("ironwood"))
		await _wait(0.5)
		await _shot("40b-heroes-onsale")
		host.show_hero(_reg.character("fadeaway"))
		await _wait(0.5)
		await _shot("40c-heroes-locked")
		_save.data["gold"] = 600
		host.refresh()
		host.show_hero(_reg.character("astro"))
		await _wait(0.5)
		await _shot("40d-heroes-short")
		_save.data["gold"] = 104711
		host.refresh()
		host.show_hero(_reg.character("ironwood"))
		await _wait(0.3)
		host.ask_buy()
		await _wait(0.7)
		await _shot("40e-heroes-buy-confirm")
		_cancel_confirm(host)
		await _wait(0.4)
	else:
		await _scene("res://ui/TitleScreen.tscn")
		await _wait(0.8)
		host = current_scene
		if host.has_method("open_drawer"):
			host.open_drawer()
			await _wait(0.6)
			await _shot("40-heroes")
			host.close_drawer()
			await _wait(0.4)
		for pair in [["ironwood", "40b-heroes-onsale"], ["fadeaway", "40c-heroes-locked"]]:
			_heroes_title_to(host, str(pair[0]))
			await _wait(0.7)
			await _shot(str(pair[1]))
		_heroes_title_to(host, "drifter")
		await _wait(0.5)
	var sheet_script: GDScript = load("res://ui/wanted/WHeroSheet.gd")
	var dr = _reg.character("drifter")
	var s: Control = sheet_script.open(host, dr, false)
	await _wait(0.8)
	await _shot("41-hero-details")
	var items: Control = s.find_child("Items", true, false)
	if items:
		(s.get("scroll") as ScrollContainer).ensure_control_visible(items)
		await _wait(0.4)
		await _shot("41b-hero-details-items")
	s.call("close")
	await _wait(0.4)
	for st in [["ironwood", "41d-hero-details-onsale"], ["fadeaway", "41e-hero-details-locked"]]:
		var c = _reg.character(str(st[0]))
		var s2: Control = sheet_script.open(host, c, _reg.hero_state(c) != "owned")
		await _wait(0.8)
		await _shot(str(st[1]))
		s2.call("close")
		await _wait(0.4)
	# Fadeaway owned, his Purple Reign's goal done: the look on sale in the strip and on his sheet
	var fad = _reg.character("fadeaway")
	(_save.data["heroes_owned"] as Array).append("fadeaway")
	for q in ["unlock_fadeaway", "skin_fadeaway_fad_b"]:
		if not (_save.data["quests_done"] as Array).has(q):
			(_save.data["quests_done"] as Array).append(q)
	if on_screen:
		host.refresh()
		host.show_hero(fad)
		await _wait(0.6)
		await _shot("40f-heroes-looks")
		# pass 123: the looks' pop-up behind the LOOKS button
		if host.has_method("open_looks"):
			host.call("open_looks")
			await _wait(0.6)
			await _shot("40h-heroes-looks-popup")
			host.call("on_back")
			await _wait(0.4)
		# pass 126: the look's question, its deed wearing the coin; then short of it: the tile's grey price with the amount in red
		if host.has_method("ask_buy_look"):
			host.call("ask_buy_look", "FAD-B")
			await _wait(0.7)
			await _shot("40i-heroes-buy-look-confirm")
			_cancel_confirm(host)
			await _wait(0.2)
			if host.has_method("looks_open") and bool(host.call("looks_open")):
				host.call("on_back")
			await _wait(0.4)
			_save.data["gold"] = 600
			host.refresh()
			host.call("open_looks")
			await _wait(0.6)
			await _shot("40l-heroes-looks-short")
			host.call("on_back")
			await _wait(0.4)
			_save.data["gold"] = 104711
			host.refresh()
		host.show_hero(dr)
		await _wait(0.4)
		var sc: ScrollContainer = host.get("scroll")
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		await _wait(0.5)
		await _shot("40g-heroes-scrolled")
		sc.scroll_vertical = 0
		# pass 126: a roster past two rows moves in its own list
		var settings := root.get_node("Settings")
		settings.preview_locked_heroes = true
		host.refresh()
		await _wait(0.3)
		var gs: ScrollContainer = host.get("grid_scroll")
		if gs:
			await _shot("40j-heroes-picker-more")
			gs.scroll_vertical = int(gs.get_v_scroll_bar().max_value)
			await _wait(0.3)
			await _shot("40k-heroes-picker-scrolled")
		settings.preview_locked_heroes = false
		host.refresh()
		await _wait(0.2)
	var s3: Control = sheet_script.open(host, fad, false)
	await _wait(0.8)
	var looks: Control = s3.find_child("Looks", true, false)
	if looks:
		var sc3: ScrollContainer = s3.get("scroll")
		sc3.scroll_vertical = int(sc3.get_v_scroll_bar().max_value)
		await _wait(0.4)
	await _shot("41c-hero-details-looks")
	s3.call("close")
	await _wait(0.4)
	for k in keep.keys():
		_save.data[k] = keep[k]


## The title showing hero `id` (wanted_shots' Wanted pictures of the Heroes states).
func _heroes_title_to(t, id: String) -> void:
	for i in (t._heroes as Array).size():
		if (t._heroes[i] as Resource).get("id") == id:
			t._index = i
			t._show_hero(1)
			t._place()
			return


## 01d-01f (pass 123, lane MAINMENU): a hero on sale on the title (Calavera: his unlock quest done, not owned): his BUY
## with the purse holding his price (01d), the purse short of it (01e, the grey price and "n short"), and the buy
## question (01f). Under Royale the green price · BUY over his black figure and the shared confirm's buy; under Wanted
## today's BUY and card. The save's heroes, quests and gold go back after.
func _title_buy() -> void:
	var hero = _reg.character("calavera")
	if hero == null:
		return
	var keep_owned: Array = (_save.data.get("heroes_owned", []) as Array).duplicate()
	var keep_quests: Array = (_save.data.get("quests_done", []) as Array).duplicate()
	var keep_gold = _save.data.get("gold", 0)
	var keep_last = _save.data.get("last_character", "")
	(_save.data["heroes_owned"] as Array).erase(hero.id)
	var q = _reg.quest_for("character", hero.id)
	if q and not _save.quest_done(q.id):
		(_save.data["quests_done"] as Array).append(q.id)
	await _scene("res://ui/TitleScreen.tscn")
	var t = current_scene
	t._index = maxi((t._heroes as Array).find(hero), 0)
	t._show_hero(1)
	t._place()
	await _wait(0.5)
	await _shot("01d-title-buyable")
	_save.data["gold"] = maxi(int(hero.price) - 166, 0)
	t._refresh_gold()
	t._show_hero(0)
	t._place()
	await _wait(0.4)
	await _shot("01e-title-buy-short")
	_save.data["gold"] = keep_gold
	t._refresh_gold()
	t._show_hero(0)
	t._place()
	t.ask_buy()
	await _wait(0.7)
	await _shot("01f-title-buy-ask")
	_save.data["heroes_owned"] = keep_owned
	_save.data["quests_done"] = keep_quests
	_save.data["gold"] = keep_gold
	_save.data["last_character"] = keep_last


## 04l..04q (pass 123, lane COLLECTION; only=collection_more): the pages and states the Royale Collection rebuilt that
## 04..04k do not show: a passive item on the rarity ladder (its rung cells), a Card with its evolution, a hero's perk, a
## weapon's page scrolled to its evolution card, the grid scrolled to its foot (the sheet's foot, the kills pill, the tab
## bar), and the developer's hidden list. The save's seen lists go back after.
func _collection_more() -> void:
	var keep_seen = _save.data.get("seen", {}).duplicate(true) if _save.data.get("seen") is Dictionary else {}
	_save.data["totals"]["kills"] = 12480
	for w in _reg.weapons.values():
		_save.mark_seen("weapon", w.id)
	for p in _reg.passives.values():
		_save.mark_seen("passive", p.id)
	for k in _reg.perks.values():
		_save.mark_seen("perk", k.id)
	await _scene("res://ui/CollectionScreen.tscn")
	var c = current_scene
	var item = null
	for p in _reg.sorted_passives_only():
		if p.on_ladder() and (item == null or str(p.rarity) == "rare"):
			item = p
			if str(p.rarity) == "rare":
				break
	if item:
		c._open_page(item)
		await _wait(0.5)
		await _shot("04l-collection-passive-page")
	var card = _reg.passive("brawn")
	if card:
		c._open_page(card)
		await _wait(0.5)
		await _shot("04m-collection-card-page")
	var perks: Array = _reg.perks.values()
	if not perks.is_empty():
		c._open_page(perks[0])
		await _wait(0.5)
		await _shot("04n-collection-perk-page")
	c._open_page(_reg.weapon("boomstick"))
	await _wait(0.5)
	c.scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("04o-collection-weapon-page-foot")
	c._show_grid()
	await _wait(0.5)
	c.scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("04p-collection-grid-foot")
	c.scroll.scroll_vertical = 0
	var cs: GDScript = load("res://ui/CollectionScreen.gd")
	cs.set("hidden_only", true)
	await _scene("res://ui/CollectionScreen.tscn")
	await _shot("04q-collection-hidden")
	cs.set("hidden_only", false)
	_save.data["seen"] = keep_seen
