## Renders the "Wanted" screens in the states the handoff's mocks show (design_handoff_88fits_wanted/screens), so each
## can be set beside its PNG (tools/wanted_compare.py). Windowed at the phone's canvas:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/wanted_shots.gd -- out=<dir> [only=hud,levelup] [white=1]
## white=1 hides the world behind a white sheet, as the mocks were drawn (they are transparent where the world is).
## inset=N puts the top inset the UI keeps clear of a camera cutout at N design px (pass 43), as a notched phone would.
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


func _main() -> void:
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	# the captures fill the save with the mocks' numbers: the PC's own save goes back as it was at the end
	var kept := FileAccess.get_file_as_string("user://save.json")
	var in_run := ["backdrop", "hud", "hud_boss", "hud_full", "levelup", "gate", "path", "chest", "shop", "stranger", "pause", "down", "stageclear", "results"]
	var any_run := false
	for n in in_run:
		if _want(n):
			any_run = true
	if any_run:
		await _in_run()
	var menus := ["title", "mirror", "collection", "settings", "dev"]
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
		current_scene._step(-1)
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
	if _want("collection"):
		_save.data["totals"]["kills"] = 12480
		# a save part of the way through: the unlocks not yet earned show as the mock's locked tiles
		var done: Array = _save.data["quests_done"]
		_save.data["quests_done"] = done.slice(0, done.size() / 2)
		# pass 44: the Collection shows what has been met; this save has met most of it
		for w in _reg.weapons.values():
			_save.mark_seen("weapon", w.id)
		for p in _reg.passives.values():
			_save.mark_seen("passive" if not (p is LineDef) else "line", p.id)
		for l in _reg.lines.values():
			_save.mark_seen("line", l.id)
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
	if _want("dev"):
		var st2 := root.get_node("Settings")
		for k in ["debug_panel", "debug_modal_buttons", "free_revive_button", "hit_log"]:
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
	if _want("levelup") or _want("gate"):
		await _levelup()
	if _want("path"):
		await _path()
	if _want("chest"):
		await _chest()
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
		["passive", "magnet", 2], ["line", "energy_shield", 4]])
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
	await _wait(0.45)
	await _shot("06-hud")
	g.hud.test_arrows = []


func _hud_boss() -> void:
	_build([["evolution", "killer_swarm", 8], ["weapon", "turret_buddy", 6], ["weapon", "big_mouth", 7], ["weapon", "molotov", 5],
		["weapon", "boomstick", 2], ["passive", "magnet", 5], ["passive", "field_notes", 3], ["line", "energy_shield", 4]])
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


## A full build: six weapons (two evolved), six passives, four lines (one evolved), a boss up and a toast: the slots
## must wrap into rows and everything under them (the boss plate, the buffs, the toasts) move down.
func _hud_full() -> void:
	_build([["evolution", "killer_swarm", 1], ["evolution", "doomstick", 1], ["weapon", "turret_buddy", 6], ["weapon", "big_mouth", 7],
		["weapon", "molotov", 5], ["weapon", "hammer", 2], ["passive", "magnet", 5], ["passive", "field_notes", 3], ["passive", "deadeye", 2],
		["passive", "guillotine", 1], ["passive", "haste", 4], ["passive", "overkill", 2], ["line", "aegis", 1], ["line", "evade", 3],
		["line", "mend", 2], ["line", "bristle", 1]])
	_hud_common(21, 0.4, 312, 400.0)
	var king = _reg.enemy("tumbleweed_king") if _reg.has_method("enemy") else null
	if king:
		g.hud.show_boss(king)
		g.hud.set_boss_hp(62, 100)
	g.hud.toast("+22 HP", Color("7fe07f"))
	await _wait(0.6)
	await _shot("06c-hud-full-build")
	g.hud.hide_boss()


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


## 07: Level 3, Bristle (a new line), Field Notes (a new passive, held down), Boomstick 5 -> 6; Banish spent.
func _levelup() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["weapon", "boomstick", 5], ["passive", "magnet", 2]])
	_hud_common(3, 0.06, 10, 61.0)
	_run.rerolls_left = 1
	_run.banishes_left = 0
	var offer := [_card("line", _reg.line("bristle"), 0, 1), _card("passive", _reg.passive("field_notes"), 0, 1),
		_card("weapon", _reg.weapon("boomstick"), 5, 6)]
	g.set_paused(true)
	g.cards.show_offer(offer, "LEVEL 3!", false, false)
	await _wait(0.9)
	g.cards._cards[1].show_held(true)
	if _want("levelup"):
		await _shot("07-level-up")
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
	g.set_paused(false)


## 08: the Boomstick's paths.
func _path() -> void:
	_clear_ui()
	_build([["weapon", "boomstick", 3]])
	var ms: Array = _reg.mutations_of("boomstick")
	var offer: Array = []
	for m in ms:
		if offer.size() < 3 and not m.is_hero():
			offer.append(_card("mutation", m, 0, 1))
	g.set_paused(true)
	g.cards.show_offer(offer, "PATH · BOOMSTICK", false, false, true)
	await _wait(0.9)
	await _shot("08-path-offer")
	g.cards.visible = false
	g.set_paused(false)


## 10: the reel lands on Orbit Saws, 3 -> 4.
func _chest() -> void:
	_clear_ui()
	_build([["weapon", "orbit_saws", 3], ["weapon", "boomstick", 2], ["passive", "magnet", 2]])
	g.set_paused(true)
	var saws = _reg.weapon("orbit_saws")
	g.chest_screen.open({"type": "weapon", "id": "orbit_saws", "def": saws, "level_from": 3, "level_to": 4, "is_new": false})
	g.chest_screen._tw.set_speed_scale(8.0)
	await _wait(1.6)
	await _shot("10-chest")
	g.chest_screen.visible = false
	g.set_paused(false)


## 11: 24 gold; Adrenaline 10, Thruster Burst 32 (8 short), Ghost Step 14.
func _shop() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["passive", "magnet", 2], ["line", "energy_shield", 4]])
	_run.run_gold = 24
	g.set_paused(true)
	var offer := [_card("passive", _reg.passive("adrenaline"), 0, 1), _card("perk", _reg.perk("thruster_burst"), 0, 1),
		_card("line", _reg.line("ghost_step") if _reg.line("ghost_step") else _reg.line("evade"), 0, 1)]
	g.structure_shop.open(offer)
	await _wait(0.9)
	await _shot("11-shop")
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


## 13, 13b, 13c: the build with Turret Buddy open, the stats, the options.
func _pause() -> void:
	_clear_ui()
	_build([["weapon", "hornet_nest", 3], ["weapon", "turret_buddy", 3], ["weapon", "big_mouth", 4], ["weapon", "molotov", 3],
		["passive", "magnet", 2], ["line", "energy_shield", 4]])
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
	g.pause_screen._tab = 1
	g.pause_screen._refresh()
	await _wait(0.5)
	await _shot("13b-pause-stats")
	# the mock's options: sound 80, music off, shake on
	var st := root.get_node("Settings")
	st.sfx_volume = 0.8
	st.music_volume = 0.0
	st.screen_shake = 1.0
	g.pause_screen._tab = 2
	g.pause_screen._refresh()
	await _wait(0.5)
	await _shot("13c-pause-options")
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
	_run.damage_by_weapon = {"killer_swarm": 6540.0, "big_mouth": 3410.0, "turret_buddy": 2560.0, "molotov": 1690.0}
	_run.last_result = {"gold_before": 104711, "banked": 1240, "prev_best": {"time": 480.0}}
	var qt = load("res://core/systems/QuestTracker.gd")
	qt.just_completed = ["unlock_turret_buddy"]
	g.set_paused(false)
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _wait(1.6)
	await _shot("16-results")
	# 16b (pass 44): the hero stayed down; the gold is left in the sand, all but what a Strongbox banked
	_run.extracted = false
	_run.died = true
	_run.last_result = {"gold_before": 104711, "banked": 0, "lost": 992, "strongbox": 300, "prev_best": {"time": 480.0}}
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await _wait(1.6)
	await _shot("16b-results-down")
