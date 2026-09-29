## Touch audit (pass 37): drives every screen and overlay with raw finger events, the way the phone sends them
## (InputEventScreenTouch / ScreenDrag; project.godot keeps emulate_mouse_from_touch off, so no mouse event follows), and
## reports every control that does not answer: a button or card whose `pressed` never fires, a slider that does not
## move, a list that does not scroll. Each control's own handlers are unplugged while it is tapped (nothing navigates
## away) and plugged back after. Events go in at canvas coordinates (push_input local), so any window size works; run it
## at the phone's shape too (a Pixel 8 Pro is 1344x2992: 540x1202 keeps the aspect):
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/touch_audit.gd [-- only=settings,pause]
## Screens: title (and its hero swipe), settings, dev (the 2 s hold on the version line, then the developer menu),
## collection, collection_page, collection_pages (every item's page opens whole), mirror, mirror_sheet, then in a run hud, pause, cards, debug_hand, resume_gate, chest,
## portal, stranger, shop, revive, results, arena. The Wanted kit's pieces count as cards (WTap) and switches (WSwitch).
extends SceneTree

const MAX_PER_KIND := 40     # cards of one screen tapped at most (a long list: a sample, spread over it)

var _only: Array = []
var _fails: Array = []       # [screen, what, why]
var _counts: Dictionary = {} # screen -> {tapped, ok}
var _game = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_only = a.substr(5).split(",")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


# ---------------------------------------------------------------- finger events

func _touch(at: Vector2, pressed: bool, index: int = 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	root.push_input(e, true)


func _drag(at: Vector2, rel: Vector2, index: int = 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	e.relative = rel
	e.velocity = rel * 60.0
	root.push_input(e, true)


func _tap(at: Vector2) -> void:
	_touch(at, true)
	await _frames(2)
	_touch(at, false)
	await _frames(2)


## A finger laid down at `from` and moved to `to` in `steps` drags, then lifted.
func _swipe(from: Vector2, to: Vector2, steps: int = 10) -> void:
	_touch(from, true)
	await _frames(1)
	var prev := from
	for k in range(1, steps + 1):
		var p := from.lerp(to, float(k) / float(steps))
		_drag(p, p - prev)
		prev = p
		await _frames(1)
	_touch(to, false)
	await _frames(2)


# ---------------------------------------------------------------- probing

func _mute(sig: Signal) -> Array:
	var saved: Array = []
	for c in sig.get_connections():
		saved.append(c)
		sig.disconnect(c["callable"])
	return saved


func _unmute(sig: Signal, saved: Array) -> void:
	for c in saved:
		if not sig.is_connected(c["callable"]):
			sig.connect(c["callable"], c["flags"])


func _visible_in_tree(c: Control) -> bool:
	if not c.is_visible_in_tree():
		return false
	var n: Node = c
	while n:
		if n is CanvasItem and (n as CanvasItem).modulate.a < 0.05:
			return false
		n = n.get_parent()
	return c.size.x > 4.0 and c.size.y > 4.0


## Brings `c` into its list's view and returns the middle of the part of it on screen (Vector2.INF when it cannot be).
func _spot(c: Control) -> Vector2:
	var n: Node = c.get_parent()
	while n:
		if n is ScrollContainer:
			(n as ScrollContainer).ensure_control_visible(c)
			break
		n = n.get_parent()
	await _frames(2)
	var r := c.get_global_rect()
	# the part of the canvas the window shows (taller than 1920 on a long phone: the stretch keeps the width)
	var screen := root.get_visible_rect()
	n = c.get_parent()
	while n:
		if n is ScrollContainer:
			screen = screen.intersection((n as ScrollContainer).get_global_rect())
			break
		n = n.get_parent()
	var vis := r.intersection(screen)
	if vis.size.x < 4.0 or vis.size.y < 4.0:
		return Vector2.INF
	return vis.get_center()


func _name_of(c: Control) -> String:
	var t := ""
	if c is Button:
		t = (c as Button).text
	elif c.has_method("label_text"):
		t = c.label_text()
	if t == "":
		for l in c.find_children("*", "Label", true, false):
			t = (l as Label).text
			if t != "":
				break
	if t == "":
		# the Wanted kit's text (WText): its plain text or its runs
		for w in c.find_children("*", "Control", true, false):
			if _is_kit(w, "WText"):
				t = str(w.get("text"))
				if t == "":
					for r in w.get("runs"):
						t += str(r[0])
				if t != "":
					break
	t = t.replace("\n", " ").strip_edges()
	return "%s '%s'" % [c.get_class() if c.get_script() == null else str(c.get_script().get_global_name()), t.left(28)]


func _count(screen: String, ok: bool) -> void:
	var d: Dictionary = _counts.get(screen, {"tapped": 0, "ok": 0})
	d["tapped"] = int(d["tapped"]) + 1
	if ok:
		d["ok"] = int(d["ok"]) + 1
	_counts[screen] = d


func _fail(screen: String, what: String, why: String) -> void:
	_fails.append([screen, what, why])
	print("  FAIL %-12s %-40s %s" % [screen, what, why])


## Every button, card, slider and list under `node`: tap, slide or swipe it and see whether it answered.
func _audit(screen: String, node: Node) -> void:
	await _frames(2)
	var buttons: Array = []
	var cards: Array = []
	var sliders: Array = []
	var scrolls: Array = []
	var switches: Array = []
	for c in node.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not _visible_in_tree(ctl):
			continue
		if ctl is BaseButton:
			if not (ctl as BaseButton).disabled:
				buttons.append(ctl)
		elif ctl is TapCard or _is_kit(ctl, "WTap"):
			cards.append(ctl)
		elif _is_kit(ctl, "WSwitch"):
			switches.append(ctl)
		elif ctl is Slider:
			sliders.append(ctl)
		elif ctl is ScrollContainer:
			scrolls.append(ctl)
	# a long list: a sample spread over it
	if cards.size() > MAX_PER_KIND:
		var step := float(cards.size()) / float(MAX_PER_KIND)
		var pick: Array = []
		for k in range(MAX_PER_KIND):
			pick.append(cards[int(k * step)])
		cards = pick
	for b: BaseButton in buttons:
		if not is_instance_valid(b) or not _visible_in_tree(b):
			continue
		var at: Vector2 = await _spot(b)
		if at == Vector2.INF:
			continue
		var hit := [false]
		var saved := _mute(b.pressed)
		var probe := func(): hit[0] = true
		b.pressed.connect(probe)
		await _tap(at)
		if is_instance_valid(b):
			b.pressed.disconnect(probe)
			_unmute(b.pressed, saved)
		_count(screen, hit[0])
		if not hit[0]:
			_fail(screen, _name_of(b), "tap did nothing")
	for c: Control in cards:
		if not is_instance_valid(c) or not _visible_in_tree(c):
			continue
		var at2: Vector2 = await _spot(c)
		if c.has_meta("tap_at"):
			at2 = c.get_global_transform() * (c.get_meta("tap_at") as Vector2)
		if at2 == Vector2.INF:
			continue
		var hit2 := [false]
		var saved2 := _mute(c.pressed)
		var probe2 := func(): hit2[0] = true
		c.pressed.connect(probe2)
		await _tap(at2)
		if is_instance_valid(c):
			c.pressed.disconnect(probe2)
			_unmute(c.pressed, saved2)
		_count(screen, hit2[0])
		if not hit2[0]:
			_fail(screen, _name_of(c), "tap did nothing")
	for sw: Control in switches:
		if not is_instance_valid(sw) or not _visible_in_tree(sw):
			continue
		var at4: Vector2 = await _spot(sw)
		if at4 == Vector2.INF:
			continue
		var was: bool = sw.get("on")
		var hit4 := [false]
		var saved4 := _mute(sw.toggled)
		var probe4 := func(_on: bool): hit4[0] = true
		sw.toggled.connect(probe4)
		await _tap(at4)
		if is_instance_valid(sw):
			sw.toggled.disconnect(probe4)
			_unmute(sw.toggled, saved4)
			sw.set("on", was)
		_count(screen, hit4[0])
		if not hit4[0]:
			_fail(screen, _name_of(sw), "tap did not flip it")
	for s: Slider in sliders:
		if not is_instance_valid(s):
			continue
		var mid: Vector2 = await _spot(s)
		if mid == Vector2.INF:
			continue
		var r := s.get_global_rect()
		var v0 := s.value
		# from a fifth of the way along to four fifths
		await _swipe(Vector2(r.position.x + r.size.x * 0.2, mid.y), Vector2(r.position.x + r.size.x * 0.8, mid.y))
		var moved := absf(s.value - v0) > 0.0001
		var up := s.value
		# and a single tap near the start
		await _tap(Vector2(r.position.x + r.size.x * 0.1, mid.y))
		var tapped := absf(s.value - up) > 0.0001
		_count(screen, moved)
		if not moved:
			_fail(screen, _name_of(s), "slide did not move it (%.2f)" % v0)
		elif not tapped:
			_fail(screen, _name_of(s), "slid, but a tap on the track did not move it")
		s.value = v0
		# a swipe up or down that starts on the slider is a scroll: the page moves, the knob stays
		var sc2: ScrollContainer = null
		var up_n: Node = s.get_parent()
		while up_n:
			if up_n is ScrollContainer:
				sc2 = up_n
				break
			up_n = up_n.get_parent()
		var inner2: Control = sc2.get_child(0) as Control if sc2 and sc2.get_child_count() > 0 else null
		if sc2 and inner2 and inner2.size.y > sc2.size.y + 40.0:
			var mid2: Vector2 = await _spot(s)
			var sv0 := sc2.scroll_vertical
			var v1 := s.value
			# towards whichever end the page has room to go
			var room_down: float = sc2.get_v_scroll_bar().max_value - sc2.size.y - float(sv0)
			var way := Vector2(0, -240) if room_down > float(sv0) else Vector2(0, 240)
			await _swipe(mid2, mid2 + way, 10)
			await _wait(0.3)
			var scrolled := sc2.scroll_vertical != sv0
			var kept := absf(s.value - v1) < 0.0001
			_count(screen, scrolled and kept)
			if not kept:
				_fail(screen, _name_of(s), "a vertical swipe that started on it moved the knob")
			elif not scrolled:
				_fail(screen, _name_of(s), "a vertical swipe that started on it did not scroll the page")
			s.value = v1
	for sc: ScrollContainer in scrolls:
		if not is_instance_valid(sc):
			continue
		var inner: Control = sc.get_child(0) as Control if sc.get_child_count() > 0 else null
		if inner == null or inner.size.y <= sc.size.y + 40.0:
			continue
		sc.scroll_vertical = 0
		await _frames(2)
		var rr := sc.get_global_rect()
		var x := rr.position.x + rr.size.x * 0.5
		await _swipe(Vector2(x, rr.position.y + rr.size.y * 0.75), Vector2(x, rr.position.y + rr.size.y * 0.3), 12)
		await _wait(0.4)
		var ok := sc.scroll_vertical > 20
		_count(screen, ok)
		if not ok:
			_fail(screen, "ScrollContainer %s" % str(sc.get_path()).get_file(), "swipe did not scroll it")
		sc.scroll_vertical = 0
		await _frames(2)
		# a swipe that starts on a button in the list scrolls the list; it must not press the button
		var under: Control = null
		for b2 in sc.find_children("*", "Control", true, false):
			var bb := b2 as Control
			var tappable := (bb is BaseButton and not (bb as BaseButton).disabled) or bb is TapCard or _is_kit(bb, "WTap")
			if tappable and _visible_in_tree(bb) and sc.get_global_rect().encloses(bb.get_global_rect()):
				under = bb
				break
		if under:
			var hit3 := [false]
			var saved3 := _mute(under.pressed)
			var probe3 := func(): hit3[0] = true
			under.pressed.connect(probe3)
			var c3 := under.get_global_rect().get_center()
			await _swipe(c3, c3 - Vector2(0, 260), 12)
			await _wait(0.3)
			if is_instance_valid(under):
				under.pressed.disconnect(probe3)
				_unmute(under.pressed, saved3)
			_count(screen, not hit3[0])
			if hit3[0]:
				_fail(screen, _name_of(under), "a swipe that started on it pressed it")
			sc.scroll_vertical = 0
	print("touch_audit: %-12s buttons %d, cards %d, switches %d, sliders %d, lists %d" % [screen, buttons.size(), cards.size(), switches.size(), sliders.size(), scrolls.size()])


## A piece of the Wanted kit by its class name (this script compiles before it could name the kit's classes safely).
func _is_kit(c: Object, cls: String) -> bool:
	var sc: Script = c.get_script()
	while sc:
		if str(sc.get_global_name()) == cls:
			return true
		sc = sc.get_base_script()
	return false


# ---------------------------------------------------------------- the screens

func _screen(name: String, path: String) -> void:
	if not _want(name):
		return
	change_scene_to_file(path)
	await _wait(1.4)
	await _audit(name, current_scene)


func _run() -> void:
	root.get_node("Save").data["runs_started"] = maxi(int(root.get_node("Save").data.get("runs_started", 0)), 1)
	await _screen("title", "res://ui/TitleScreen.tscn")
	if _want("title"):
		await _title_swipe()
	await _screen("settings", "res://ui/SettingsScreen.tscn")
	if _want("dev"):
		await _version_hold()
	await _screen("collection", "res://ui/CollectionScreen.tscn")
	if _want("collection_page"):
		change_scene_to_file("res://ui/CollectionScreen.tscn")
		await _wait(1.2)
		current_scene._open_page(root.get_node("Registry").weapon("boomstick"))
		await _wait(0.6)
		await _audit("collection_page", current_scene)
	if _want("collection_pages"):
		await _collection_pages()
	await _screen("mirror", "res://ui/HomesteadScreen.tscn")
	if _want("mirror_sheet"):
		change_scene_to_file("res://ui/HomesteadScreen.tscn")
		await _wait(1.2)
		var reg = root.get_node("Registry")
		current_scene._open(reg.talents_list()[0])
		await _wait(0.6)
		await _audit("mirror_sheet", current_scene._sheet_root)
	await _in_game()
	_report()


## Every page of every Collection tab opens whole (pass 40: the creature page read a field the data class lacked, and
## the script error left the page empty; a muted tap in _audit never opens a page, so nothing caught it).
func _collection_pages() -> void:
	change_scene_to_file("res://ui/CollectionScreen.tscn")
	await _wait(1.2)
	var c = current_scene
	for tab in c.TABS.size():
		c._tab = tab
		c._show_grid()
		await _frames(2)
		for def in c._items(tab):
			c._open_page(def)
			await _frames(2)
			var body: Node = c.content
			var whole: bool = body.get_child_count() >= 1 and body.get_child(0) is PanelContainer
			if def.get_class() == "Resource" and def.get("archetype") != null:
				whole = whole and body.get_child_count() >= 3
			_count("collection_pages", whole)
			if not whole:
				_fail("collection_pages", str(def.get("id")), "the page did not build (see the SCRIPT ERROR above)")


## The title's hero: a finger swiped sideways over the cut-out changes the hero shown.
func _title_swipe() -> void:
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.2)
	var t = current_scene
	if (t._heroes as Array).size() < 2:
		return
	var i0: int = t._index
	var row: Control = t._hero_row
	var y := row.get_global_rect().get_center().y
	await _swipe(Vector2(760, y), Vector2(320, y), 10)
	await _wait(0.3)
	var ok: bool = t._index != i0
	_count("title", ok)
	if not ok:
		_fail("title", "the hero", "a sideways swipe did not change the hero")


## Holding the version line in Settings for 2 s opens the developer menu; then the menu itself is audited.
func _version_hold() -> void:
	change_scene_to_file("res://ui/SettingsScreen.tscn")
	await _wait(1.2)
	var v: Control = current_scene._version
	var at := v.get_global_rect().get_center()
	_touch(at, true)
	await _wait(2.4)
	_touch(at, false)
	await _wait(1.2)
	var ok := current_scene != null and str(current_scene.scene_file_path).ends_with("DevMenu.tscn")
	_count("settings", ok)
	if not ok:
		_fail("settings", "version line", "a 2 s hold did not open the developer menu")
		change_scene_to_file("res://ui/DevMenu.tscn")
		await _wait(1.2)
	await _audit("dev", current_scene)


func _in_game() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "astro", "map": "red_canyon", "map_seed": 5}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(3.0)
	var g = current_scene
	_game = g
	var run = root.get_node("Run")
	g.player.god = true
	# the HUD's pause button: a tap has to open the pause menu
	if _want("hud"):
		var pb: Control = g.hud.get("_pause_btn")
		if pb:
			await _tap(pb.get_global_rect().get_center())
			await _wait(0.3)
			_count("hud", g.pause_screen.visible)
			if not g.pause_screen.visible:
				_fail("hud", "pause button", "tap did not open the pause menu")
			else:
				g.close_pause()
		else:
			_fail("hud", "pause button", "not found")
	if _want("pause"):
		g.open_pause()
		await _wait(0.6)
		for tab in range(3):
			g.pause_screen._tab = tab
			g.pause_screen._refresh()
			await _wait(0.5)
			await _audit("pause_%d" % tab, g.pause_screen)
		g.close_pause()
		await _wait(0.3)
	if _want("cards"):
		g._pending_levels += 1
		g._show_next_level_cards()
		await _wait(1.0)
		await _audit("cards", g.cards)
		if _want("debug_hand"):
			g.cards._open_debug()
			await _wait(0.8)
			await _audit("debug_hand", g.cards._debug)
			g.cards._debug.visible = false
		# pick one for real so the run goes on
		if g.cards.visible and not g.cards._offer.is_empty():
			g.cards._pick(g.cards._offer[0])
		await _wait(0.6)
		if g.resume_gate and g.resume_gate.visible:
			await _tap(root.get_visible_rect().get_center())
			await _wait(0.3)
			_count("resume_gate", not g.resume_gate.visible)
			if g.resume_gate.visible:
				_fail("resume_gate", "the tap to go on", "tap did not close it")
				g.resume_gate.tap()
	if _want("chest"):
		g.open_chest(g.player.global_position + Vector3(1, 0, 0))
		var waited := 0.0
		while waited < 8.0 and not g.chest_screen.buttons.visible:
			await _wait(0.25)
			waited += 0.25
		await _wait(0.6)
		await _audit("chest", g.chest_screen)
		if g.chest_screen.visible:
			g.chest_screen.visible = false
		g.set_paused(false)
		await _wait(0.3)
	if _want("portal"):
		g.portal_dialog.open(1, true, false)
		await _wait(0.8)
		await _audit("portal", g.portal_dialog)
		g.portal_dialog.visible = false
		g.set_paused(false)
	if _want("stranger"):
		var offer: Dictionary = run.stranger_offer()
		if not offer.is_empty():
			g.set_paused(true)
			g.stranger_screen.open(offer, 0.2)
			await _wait(0.8)
			await _audit("stranger", g.stranger_screen)
			g.stranger_screen.visible = false
			g.set_paused(false)
	if _want("shop"):
		g.set_paused(true)
		# CardPool by path: this script compiles before the autoloads it names exist
		g.structure_shop.open(load("res://core/systems/CardPool.gd").level_up_offer(3))
		await _wait(0.8)
		await _audit("shop", g.structure_shop)
		g.structure_shop.visible = false
		g.set_paused(false)
	if _want("revive"):
		g.set_paused(true)
		g.revive_screen.open(200, 1, g.player.damage_log_text())
		await _wait(0.8)
		await _audit("revive", g.revive_screen)
		g.revive_screen.visible = false
		g.set_paused(false)
	if _want("results"):
		run.died = true
		g.end_run()
		await _wait(4.0)
		if current_scene and current_scene.name.to_lower().contains("result"):
			await _audit("results", current_scene)
	if _want("arena"):
		run.arena_next = true
		change_scene_to_file("res://game/Game.tscn")
		await _wait(3.5)
		var a = current_scene
		if a.get("arena_panel"):
			await _audit("arena", a.arena_panel)
			a.arena_panel.open()
			await _wait(0.6)
			for t in a.arena_panel.TABS:
				a.arena_panel._tab = t[0]
				a.arena_panel._refresh()
				await _wait(0.5)
				await _audit("arena_" + str(t[0]), a.arena_panel._sheet)


func _report() -> void:
	print("")
	print("touch_audit: screen        answered / tapped")
	var total := 0
	var good := 0
	for s in _counts.keys():
		var d: Dictionary = _counts[s]
		print("touch_audit:   %-12s %d / %d" % [s, int(d["ok"]), int(d["tapped"])])
		total += int(d["tapped"])
		good += int(d["ok"])
	print("touch_audit: %d of %d controls answered a finger; %d failures" % [good, total, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
