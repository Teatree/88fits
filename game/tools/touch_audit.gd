## Touch audit (pass 37): drives every screen and overlay with raw finger events, the way the phone sends them
## (InputEventScreenTouch / ScreenDrag; project.godot keeps emulate_mouse_from_touch off, so no mouse event follows), and
## reports every control that does not answer: a button or card whose `pressed` never fires, a slider that does not
## move, a list that does not scroll. Each control's own handlers are unplugged while it is tapped (nothing navigates
## away) and plugged back after. Events go in at canvas coordinates (push_input local), so any window size works; run it
## at the phone's shape too (a Pixel 8 Pro is 1344x2992: 540x1202 keeps the aspect):
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/touch_audit.gd [-- only=settings,pause]
## Screens: title (and its hero swipe), settings, dev (the 2 s hold on the version line, then the developer menu),
## collection, collection_page (a weapon's page, and the Peashooter's with a hero's mutation in its rows), collection_pages
## (every item's page opens whole), mirror, mirror_sheet, spawn (the beam's skip tap, pass 45), then in a run hud, pause,
## cards, debug_hand, resume_gate, chest (pass 46: a tap while the chest opens has to skip to the spin), portal,
## stranger, shop, revive (with the player's debug mode on, so the last hits and their buttons on Down! are tapped; pass
## 46 moved them there from Results), results, arena.
## settings_confirm, mirror_confirm, pause_confirm, revive_confirm and arena_confirm (pass 45): each confirmation pop-up
## (WConfirm) opened as its button would open it, its dim and two buttons tapped, then cancelled for real. The Wanted
## kit's pieces count as cards (WTap) and switches (WSwitch).
## Pass 47: collection_tabs (each of the five tabs opened by a finger, its tiles audited), card_choices (with no skip
## left SKIP stays and says so; BANISH then a card strikes it and spends the stage's banish; SKIP with one closes on
## nothing), path (the mutation offer, its SKIP on the same skips, tapped for real), chest_choices (BANISH spins the
## reel again and the chest stays open, the new landing audited as chest_respin; SKIP with none left stays; SKIP with
## one closes it) and results_rows (every damage row has its plate, a name and a number).
## Pass 48: collection_insets (the Collection's back square answers a finger at five points of it, on the grid and on an
## item's page, with the camera-cutout inset at 0, 80, 130 and 180: the tabs and the board had covered it), dev_dummies
## (the developer menu's two dummy rows step Settings.dummy_hp and dummy_count under a real finger), portal_not_yet (the
## stage clear's NOT YET closes it with no decision, `declined`) and arena_dummies (the WORLD tab's dummy health and
## RESET DUMMIES under real fingers).
## Pass 49: dev_dummies also steps the patrol, the attackers' health and the Elite's and the Boss's health and behaviour
## rows; arena_dummies also turns the patrol on, sets the Elite dummy's health and behaviour (melee turns god mode off),
## adds a melee dummy and removes the attackers, each by a finger on its named row; arena_stack opens a weapon's stack on
## the ITEMS tab by its toggle and audits the rows drawn under it.
## Pass 54: pause_options (the pause Options' floating text: each of the four switches and the size choice under a real
## finger changes its setting, put back after; both volume thumbs sit whole inside the board's clip at the top value and
## at nothing), path_offer (the mutation offer's pre-reel: it runs, a tap skips it to the landing, the cards come and a
## real tap on one picks it) and settings_debug also flips "Ranged weapons aim only on screen" (RangedOnScreen) for real
## when the setting exists. The path state waits for the reel before it audits.
## Pass 76 (lane UI): pause_stats (run with pause: three cells of the pause Stats tab under a real finger, each opening
## its sources under its row in sight, a second tap closing them).
## Pass 55: arena_hero (the arena's HERO tab under real fingers: another hero's tile swaps him in and the first hero's
## brings him back, a look chip draws that look on the hero for the visit, USE FROM NOW ON keeps it; all put back after;
## run on its own with only=arena_hero, which audits the tab's controls first).
## Pass 56: gate_strip (run with cards too): after a real pick, a finger on the HUD's strip (under the clock, at the
## strip's foot, on the pause disc) lets the resume gate go and opens nothing (the same touch had reached the strip,
## which paused the run as it went on), and a finger under the strip lets it go and starts the stick.
## Pass 57: settings_analytics (run with settings: "Anonymous play data" has its line, and two real taps on its switch
## flip Settings.analytics and back; a tool run never sends and never touches the queue file, so the flip is safe) and
## dev_analytics (run with dev: the developer menu's PostHog readout is there and a real tap on Send now reaches
## Analytics.send_now; from a tool it sends nothing and says why).
## Pass 58: card_choices (run with cards) lays out one held card between two new ones for banish by real fingers: BANISH
## turns banish mode on and every control in it answers (cards_banish), the held card refuses, CANCEL turns it off, a new
## card is struck and the table answers again after (cards_after_banish), a table of upgrades only locks BANISH.
## Pass 61: hero_sheet (run with title): the plaque's swipe and tap, the hero's sheet audited, its dim and CLOSE.
## Pass 69: hero_drawer (run with title, or alone with only=hero_drawer): the Hero Collections button opens the drawer
## under a real finger (its glyph turns to the close X), every tile in it answers, a real tap on another hero's tile shows
## him and keeps the drawer open, the tiles scroll sideways when they do not fit, a tap outside the panel closes it and
## changes nothing behind it, the button's X closes it; then hero_buy: a hero on sale with the gold for him, his BUY
## answers, opens the question (audited, cancelled), and a real BUY then the real deed buys him (gold spent once, he is
## owned, PLAY open); a locked hero shows his requirement and a real tap on LOCKED starts nothing. The save's gold and
## bought heroes are put back after.
## Pass 72: results_show (run with results): the Results' animated show under real fingers: every button answers while
## the show plays and a tap on one does not hurry it, a swipe does not move the board (and hurries the show), a tap ends
## the first sequence, a tap hurries the second and another ends it; then the screen is audited as before (the board
## scrolls under a finger again).
## Pass 73 (lane STRUCT): totem: a Totem Pole used in the run opens its menu of gifts through the one-screen rule; every
## plank answers a finger (muted), a real tap on one takes its gift (the menu closes, the gift is on the run, the run goes
## on); then a menu built under a 130 px camera cutout (totem_inset130): its planks answer and a real tap takes one.
## Pass 82 (lane TOTEM, the Spirit Pole): each gift row (segment and tag) is one target; taps off the rows and a finger
## dragged off a gift take nothing; totem_inset200 as well (the screen 70 px lower).
## Pass 76 (lane LOOKS): arena_item_looks (run with arena): a real tap on a weapon family's look chip on ITEMS keeps that
## look on the phone, the family wears it and a held weapon of it is made again in it; JSON gives its own look back.
## Pass 87 (lane SUI, the stages): stages (run alone with only=stages): with Red Canyon's stage 1 beaten a real tap on
## PLAY opens the Stages menu; every card and the back square answer a finger; a real tap on a locked card starts nothing
## and leaves the screen where it is; a real tap on each open card starts its stage (held on the screen); the back square
## goes to the title for real. stages_play: a real tap on stage 2's card starts a run there (Run.stage 1, a fresh hero,
## the HUD's clock at the stage's own 00:00). portal_expire (run with portal): the stage clear's countdown running out
## closes it by itself (`expired`, no decision); endless_banner (run with hud): Endless shows its banner and the clock's
## WAVE tag, and a finger on the tag still pauses (the strip takes it).
## Pass 112 (lane WANTED): wanted (run alone with only=wanted): the floating Wanted posters over a run (the launch's
## `bounty_board`): the three posters and No bounty answer a finger (muted); a real tap on a poster takes it (stamped,
## flown into the HUD's bounty plate, the contract running, the run going on); in a second run a real No bounty blows
## them away (no contract, the run going on). Pass 111's full-screen board before the run is gone.
## Pass 106 (lane DRUM): drum: the War Drum used in the run stops time for its moment; real taps on the drum, the dim and
## the pause disc while it plays are swallowed (nothing opens, the moment plays on, the run stays paused); it ends by
## itself and the run goes on; the HUD shows the boost's plate with its seconds (a finger on it opens nothing).
## Pass 121 (lane GRIND): grind: the Grindstone taken in the run stops time for its show (ui/GrindMoment.gd); a real tap
## on the pause disc while it plays opens nothing and hurries it to the reveal, a second real tap to the stamp, a third
## (after its guard) to the fade; it closes into the gate, a real tap there lets the run go; the weapon went up one
## level, once.
## Pass 123 (lane RUN_C): path_spent (with path): the mutation offer with no skips left, a real tap on its SKIP refused and
## said (the skips pill under Royale); survey_pick (with survey_card): a real tap on a rating lights it alone and unlocks
## NEXT, a real tap on NEXT turns the page.
## Pass 111 (lane SKINS): hero_skins (run with title, or alone with only=hero_skins): the hero sheet of a hero who sells a
## look, owned, its goal done and the gold for it: every control on it answers a finger (muted; a swipe that starts on a
## Looks tile scrolls the sheet and presses nothing), the buy question is audited
## and cancelled, a real tap on the look to buy asks and the real deed buys it (its price spent once, worn, the title's
## hero in it), a real tap on the look every player owns wears it again, a real tap on a locked look buys nothing and
## asks nothing; a hero not owned shows no Looks. The save's gold, heroes, quests and skins are put back after.
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
	# pass 122: up to three tries: a ScrollContainer whose list was just laid out (the developer menu's, one row longer)
	# can take the first ensure_control_visible before its scroll range has grown, leaving the row just under the screen
	var vis := Rect2()
	for _try in range(3):
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
		vis = r.intersection(screen)
		if vis.size.x >= 4.0 and vis.size.y >= 4.0:
			return vis.get_center()
	return Vector2.INF


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


## A confirmation pop-up (WConfirm, pass 45): `ask` opens it on `host` the way the real button does (the audit mutes
## every button it taps, so a muted Abandon or Wipe never opens one by itself); its dim and two buttons are audited
## (muted, like everything), then the paper button is tapped for real and the card has to be gone.
func _confirm_audit(screen: String, host: Node, ask: Callable) -> void:
	ask.call()
	await _wait(0.5)
	var c: Node = null
	for n in host.get_children():
		if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
			c = n
	if c == null:
		_count(screen, false)
		_fail(screen, "the pop-up", "asking did not open it")
		return
	await _audit(screen, c)
	var cancel: Control = c.find_child("Cancel", true, false)
	if cancel and _visible_in_tree(cancel):
		await _tap(cancel.get_global_rect().get_center())
		await _wait(0.4)
	else:
		_fail(screen, "Cancel", "not found")
	var gone := not is_instance_valid(c) or bool(c.get("_done"))
	_count(screen, gone)
	if not gone:
		_fail(screen, "Cancel", "the tap did not close the pop-up")
		c.call("cancel")
	await _wait(0.3)


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
	if _want("title") or _want("hero_sheet"):
		await _hero_sheet()
	if _want("title") or _want("hero_drawer") or _want("hero_buy"):
		await _hero_drawer()
	if _want("title") or _want("hero_skins"):
		await _hero_skins()
	if _want("title") or _want("title_royale"):
		await _title_royale()
	await _screen("settings", "res://ui/SettingsScreen.tscn")
	if _want("settings"):
		await _confirm_audit("settings_confirm", current_scene, func(): current_scene._ask_wipe())
	if _want("settings") or _want("settings_analytics"):
		await _settings_analytics()
	# the play-data card and the survey card on their own names too (pass 60: only=consent_card,survey_card)
	if _want("settings") or _want("settings_analytics") or _want("consent_card") or _want("survey_card"):
		await _cards59()
	# pass 123 (lane RUN_C): the survey's answers under real fingers (the pick lit, NEXT on to the next page)
	if _want("survey_card") or _want("survey_pick"):
		await _survey_pick()
	if _want("dev"):
		await _version_hold()
	await _screen("collection", "res://ui/CollectionScreen.tscn")
	if _want("collection_insets"):
		await _collection_insets()
	if _want("collection_tabs"):
		await _collection_tabs()
	if _want("collection_page"):
		change_scene_to_file("res://ui/CollectionScreen.tscn")
		await _wait(1.2)
		current_scene._open_page(root.get_node("Registry").weapon("boomstick"))
		await _wait(0.6)
		await _audit("collection_page", current_scene)
		# a weapon whose mutations take a fourth, a hero's (pass 46: the Drifter's Fan the Hammer; pass 76: his Fire in the
		# Hole on the grenade, the Peashooter is hidden), in centred rows
		var pea = root.get_node("Registry").weapon("lob_grenade")
		if pea:
			current_scene._open_page(pea)
			await _wait(0.6)
			await _audit("collection_page", current_scene)
	if _want("collection_pages"):
		await _collection_pages()
	if _want("collection_royale"):
		await _collection_royale_audit()
	await _screen("mirror", "res://ui/HomesteadScreen.tscn")
	if _want("mirror"):
		# the refund asks only with ranks on the board: lend the save some spend, in memory, and take it back after
		var save = root.get_node("Save")
		var was: int = int(save.data.get("talent_spent", 0))
		save.data["talent_spent"] = maxi(was, 100)
		current_scene._refresh()
		await _frames(2)
		await _confirm_audit("mirror_confirm", current_scene, func(): current_scene._take_back())
		save.data["talent_spent"] = was
	if _want("mirror_sheet"):
		change_scene_to_file("res://ui/HomesteadScreen.tscn")
		await _wait(1.2)
		var reg = root.get_node("Registry")
		current_scene._open(reg.talents_list()[0])
		await _wait(0.6)
		await _audit("mirror_sheet", current_scene._sheet_root)
	if _want("upgrade_buy"):
		await _upgrade_buy()
	if _want("spawn"):
		await _spawn_skip()
	if _want("stages") or _want("stages_play"):
		await _stages_menu()
	if _want("stages") or _want("stages_start") or _want("settings") or _want("settings_rows"):
		await _stages_settings_p123()
	if _want("wanted"):
		await _bounty_posters()
	if _want("tab_bar") or _want("kit_shell"):
		await _tab_bar_audit()
	if _want("heroes_screen") or _want("hero_details"):
		await _heroes_audit()
	await _in_game()
	_report()


## The landing (pass 45): the run opens with the hero in the beam; pass 64: a tap during it speeds the rest of the
## sequence up (SPAWN_HURRY) instead of landing him at once, he still lands, and that tap does not start the stick.
func _spawn_skip() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "astro", "map": "red_canyon", "map_seed": 5, "spawn": true}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(0.8)
	var g = current_scene
	if g == null or not g.get("spawning"):
		_count("spawn", false)
		_fail("spawn", "the beam", "the run did not open with the spawn beam")
		return
	while g.spawning and g._spawn_t < 1.05:
		await _wait(0.05)
	if not g.spawning:
		_count("spawn", false)
		_fail("spawn", "the beam", "the cinematic ended before the tap")
		return
	await _tap(root.get_visible_rect().get_center())
	var hurried: bool = g.spawning and float(g.spawn_rate) > 1.5
	await _wait(0.6)
	var ok: bool = hurried and not g.spawning and not g.player.input.wants_move
	_count("spawn", ok)
	if not hurried:
		_fail("spawn", "the hurry tap", "the tap did not speed the sequence up (or landed him at once)")
	elif g.spawning:
		_fail("spawn", "the hurry tap", "the sped-up sequence did not land within 0.6 s")
	elif g.player.input.wants_move:
		_fail("spawn", "the hurry tap", "the tap started the stick")


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


## Every tab of the Collection (pass 47: Weapons, Lines, Passives, Perks, Enemies): a finger on the tab opens it, and
## the tiles of every tab but the first (the collection screen audits that one) answer a tap.
func _collection_tabs() -> void:
	change_scene_to_file("res://ui/CollectionScreen.tscn")
	await _wait(1.2)
	var c = current_scene
	for t in c.TABS.size():
		var tab: Control = c._tabs._tabs[t]
		await _tap(tab.get_global_rect().get_center())
		await _wait(0.4)
		var ok: bool = c._tab == t
		_count("collection_tabs", ok)
		if not ok:
			_fail("collection_tabs", str(c.TABS[t]), "a tap on the tab did not open it")
			c._tab = t
			c._show_grid()
			await _wait(0.3)
		if t > 0:
			await _audit("collection_%d" % t, c)


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


## The hero's sheet (pass 61, the CV, ui/wanted/WHeroSheet.gd; run with title, or alone with only=hero_sheet): a sideways
## swipe across the title's plaque changes the hero and opens nothing; a real tap on the plaque opens the sheet of the
## hero shown; every control on it answers a finger (CLOSE, the list scrolls); a tap on the dim outside the card closes
## it, and so does a real tap on CLOSE.
func _hero_sheet() -> void:
	# pass 123 (lane MAINMENU): the Royale title has no plaque (DETAILS opens the sheet there: title_royale)
	print("touch_audit: hero_sheet: the Royale title opens the sheet from DETAILS (title_royale)")
	return


## The hero drawer and buying a hero (pass 69, see the header): real fingers on the Hero Collections button, the
## drawer's tiles, outside it, its close X, then BUY, the question's buttons and LOCKED.
func _hero_drawer() -> void:
	# pass 123 (lane MAINMENU): the Royale title has no drawer; its BUY and LOCKED are audited in title_royale
	print("touch_audit: hero_drawer: the Royale title has no drawer (its BUY and LOCKED: title_royale)")
	return


## The hero sheet's Looks (pass 111, lane SKINS; see the header): real fingers on the tiles, the buy question, the deed,
## wearing the owned look again, a locked look.
func _hero_skins() -> void:
	var save = root.get_node("Save")
	var reg = root.get_node("Registry")
	var kept := {}
	for k in ["gold", "heroes_owned", "quests_done", "skins_owned", "skin_worn", "hero_look", "last_character"]:
		kept[k] = save.data[k].duplicate(true) if (save.data.get(k) is Array or save.data.get(k) is Dictionary) else save.data.get(k)
	# a hero who sells a look (the first in the content), owned for the audit
	var hero = null
	var code := ""
	for c in reg.sorted_characters():
		for k in c.variants.keys():
			if c.sells_skin(str(k)):
				hero = c
				code = str(k)
				break
		if hero:
			break
	if hero == null:
		print("touch_audit: hero_skins: no look is sold, skipped")
		return
	if not save.owns_hero(hero.id):
		save.heroes_owned().append(hero.id)
	(save.data["skins_owned"] as Array).erase(reg.skin_key(hero.id, code))
	save.data["skin_worn"] = {}
	save.data["hero_look"] = {}
	var q = reg.skin_quest(hero, code)
	if q and not save.quest_done(q.id):
		(save.data["quests_done"] as Array).append(q.id)
	var price: int = hero.skin_price(code)
	save.data["gold"] = price + 250
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.4)
	var t = current_scene
	t._index = maxi((t._heroes as Array).find(hero), 0)
	t._show_hero(0)
	t._place()
	await _wait(0.4)
	t.open_sheet()
	await _wait(0.7)
	var sheet: Control = t.find_child("HeroSheet", false, false)
	var looks: Control = sheet.find_child("Looks", true, false) if sheet else null
	_count("hero_skins", looks != null)
	if looks == null:
		_fail("hero_skins", "Looks", "the sheet of %s, who sells %s, has no Looks" % [hero.id, code])
		return
	# the whole sheet: the tiles, CLOSE, and the list scrolled by a swipe that starts on a tile (which must not press it)
	await _audit("hero_skins", sheet)
	await _confirm_audit("hero_skins_confirm", sheet, func(): sheet.call("ask_buy_look", code))
	# a real tap on the look to buy asks, the real deed buys it
	var tile: Control = sheet.find_child("Look_" + code, true, false)
	var at: Vector2 = await _spot(tile)
	var gold0: int = save.gold()
	await _tap(at)
	await _wait(0.5)
	var ask: Node = null
	for n in sheet.get_children():
		if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
			ask = n
	_count("hero_skins", ask != null)
	if ask == null:
		_fail("hero_skins", "Look_" + code, "a real tap on a look to buy did not ask")
	else:
		var deed: Control = ask.find_child("Confirm", true, false)
		await _tap(deed.get_global_rect().get_center())
		await _wait(0.8)
		var worn: bool = reg.played_look(hero).look_code() == code
		var bought: bool = save.owns_skin(reg.skin_key(hero.id, code)) and save.gold() == gold0 - price and worn
		_count("hero_skins", bought)
		if not bought:
			_fail("hero_skins", "Confirm", "the deed did not buy and wear %s (gold %d -> %d, worn %s)" % [code, gold0, save.gold(), str(worn)])
		_count("hero_skins", t._figure != null and is_instance_valid(t._figure))
	# a real tap on the look every player owns wears it again
	var home: Control = sheet.find_child("Look_" + hero.home_look(), true, false)
	if home:
		var at2: Vector2 = await _spot(home)
		await _tap(at2)
		await _wait(0.4)
		var back: bool = reg.played_look(hero).look_code() == hero.home_look()
		_count("hero_skins", back)
		if not back:
			_fail("hero_skins", "Look_" + hero.home_look(), "a real tap did not wear the look every player owns")
	# a locked look: the goal undone, a real tap buys nothing and asks nothing
	(save.data["skins_owned"] as Array).erase(reg.skin_key(hero.id, code))
	if q:
		(save.data["quests_done"] as Array).erase(q.id)
		sheet.call("_fill_looks")
		await _wait(0.3)
		var lt: Control = sheet.find_child("Look_" + code, true, false)
		var g1: int = save.gold()
		var at3: Vector2 = await _spot(lt)
		await _tap(at3)
		await _wait(0.4)
		var asked := false
		for n in sheet.get_children():
			if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
				asked = true
		var nothing: bool = str(lt.get_meta("state")) == "locked" and not asked and save.gold() == g1 and not save.owns_skin(reg.skin_key(hero.id, code))
		_count("hero_skins", nothing)
		if not nothing:
			_fail("hero_skins", "Look_" + code, "a real tap on a locked look bought or asked")
	sheet.call("close")
	await _wait(0.3)
	# a hero not owned shows no Looks
	(save.data["heroes_owned"] as Array).erase(hero.id)
	var s2: Control = load("res://ui/wanted/WHeroSheet.gd").open(t, hero, true)
	await _wait(0.4)
	var none: bool = s2.find_child("Looks", true, false) == null
	_count("hero_skins", none)
	if not none:
		_fail("hero_skins", "Looks", "a hero not owned sells looks")
	s2.call("close")
	await _wait(0.3)
	for k in kept.keys():
		save.data[k] = kept[k]


## Anonymous play data in Settings (pass 57): the line under the switch says something, and a real tap on the switch
## flips Settings.analytics, a second one back; put back after whatever happened.
func _settings_analytics() -> void:
	var st = root.get_node("Settings")
	var keep: bool = bool(st.get("analytics"))
	change_scene_to_file("res://ui/SettingsScreen.tscn")
	await _wait(1.2)
	var line: Control = current_scene.find_child("AnalyticsLine", true, false)
	var has_line: bool = line != null and str(line.get("text")) != ""
	_count("settings_analytics", has_line)
	if not has_line:
		_fail("settings_analytics", "AnalyticsLine", "no line under the switch")
	var sw: Control = current_scene.find_child("AnalyticsSwitch", true, false)
	if sw == null:
		_count("settings_analytics", false)
		_fail("settings_analytics", "AnalyticsSwitch", "the switch is not in Settings")
	else:
		for k in range(2):
			var was: bool = bool(st.get("analytics"))
			var at: Vector2 = await _spot(sw)
			await _tap(at)
			await _wait(0.2)
			var ok: bool = bool(st.get("analytics")) != was
			_count("settings_analytics", ok)
			if not ok:
				_fail("settings_analytics", "AnalyticsSwitch", "a tap did not flip Settings.analytics (it was %s)" % str(was))
	# pass 59: the end-of-run questions' switch flips under a finger too
	var keep_s: bool = bool(st.get("surveys"))
	var ssw: Control = current_scene.find_child("SurveySwitch", true, false)
	if ssw == null:
		_count("settings_analytics", false)
		_fail("settings_analytics", "SurveySwitch", "the switch is not in Settings")
	else:
		var was_s: bool = bool(st.get("surveys"))
		await _tap(await _spot(ssw))
		await _wait(0.2)
		_count("settings_analytics", bool(st.get("surveys")) != was_s)
		if bool(st.get("surveys")) == was_s:
			_fail("settings_analytics", "SurveySwitch", "a tap did not flip Settings.surveys")
	st.set("surveys", keep_s)
	st.set("analytics", keep)
	root.get_node("Save").request_save()
	root.get_node("Save").flush()


## The play-data card and the survey card (pass 59): every button answers a finger (the audit unplugs handlers while it
## taps, so nothing is answered or sent). Opened over the title by hand: a tool run never sends, so neither comes by itself.
## Pass 60 (Garry: "I tap and the ability to type doesn't appear"): the survey carries a text question too, and a finger
## on its box must focus it (the phone's keyboard follows focus), a finger outside must let the focus go.
func _cards59() -> void:
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.2)
	var consent: Control = load("res://ui/wanted/WConsent.gd").open(current_scene)
	await _wait(0.6)
	# pass 123 (lane RUN_C): a cold first title (only=consent_card) can still be fading in after 1.8 s, which hid the card's
	# buttons from the audit (0 found): it waits, at most 3 s more, until OK shows
	var ok_btn: Control = consent.find_child("Accept", true, false)
	var waited := 0.0
	while waited < 3.0 and ok_btn != null and not _visible_in_tree(ok_btn):
		await _wait(0.1)
		waited += 0.1
	await _audit("consent_card", consent)
	consent.queue_free()
	var sv := {"id": "audit", "name": "Audit", "questions": [
		{"id": "a1", "type": "rating", "question": "How much fun?", "description": "", "optional": false, "choices": [], "scale": 5, "lower": "Not fun", "upper": "Loved it"},
		{"id": "a2", "type": "single_choice", "question": "Better?", "description": "", "optional": false, "choices": ["More", "Less"], "scale": 5, "lower": "", "upper": ""},
		{"id": "a3", "type": "open", "question": "Anything else?", "description": "", "optional": true, "choices": [], "scale": 5, "lower": "", "upper": ""}]}
	var card: Control = load("res://ui/wanted/WSurvey.gd").open(current_scene, sv)
	await _wait(0.6)
	await _audit("survey_card", card)
	# the text question: a finger on the box focuses it, one on the dim outside lets it go
	card.call("show_page", 2)
	await _wait(0.3)
	var answer: Control = card.find_child("Answer", true, false)
	if answer == null:
		_count("survey_card", false)
		_fail("survey_card", "Answer", "the text question has no box")
	else:
		await _tap(answer.get_global_rect().get_center())
		await _wait(0.2)
		var focused: bool = bool(card.call("answer_focused"))
		_count("survey_card", focused)
		if not focused:
			_fail("survey_card", "Answer", "a finger on the text box did not focus it (no keyboard on the phone)")
		await _tap(Vector2(root.get_visible_rect().size.x * 0.5, 60.0))
		await _wait(0.2)
		var released: bool = not bool(card.call("answer_focused"))
		_count("survey_card", released)
		if not released:
			_fail("survey_card", "Answer", "a finger outside the text box left it focused (the keyboard would stay up)")
	card.queue_free()
	await _wait(0.2)


## The developer menu's PostHog readout (pass 57) is there, and a real tap on Send now reaches Analytics.send_now (a tool
## run sends nothing: the readout says why, and the tap still counts in manual_sends).
func _dev_analytics() -> void:
	var an: Node = root.get_node_or_null("Analytics")
	var box: Control = current_scene.find_child("Analytics", true, false)
	var ok_box: bool = box != null and box.find_children("*", "Control", true, false).size() > 3
	_count("dev_analytics", ok_box)
	if not ok_box:
		_fail("dev_analytics", "Analytics", "the readout is not in the developer menu")
	var row: Control = current_scene.find_child("AnalyticsSendNow", true, false)
	if row == null or an == null:
		_count("dev_analytics", false)
		_fail("dev_analytics", "AnalyticsSendNow", "the row (or the autoload) is not there")
		return
	var before: int = int(an.get("manual_sends"))
	var at: Vector2 = await _spot(row)
	await _tap(at)
	await _wait(0.4)
	var now: int = int(an.get("manual_sends"))
	_count("dev_analytics", now == before + 1)
	if now != before + 1:
		_fail("dev_analytics", "AnalyticsSendNow", "a tap did not reach Analytics.send_now (%d -> %d)" % [before, now])


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
	await _dev_dummies()
	await _dev_frame_cap()
	await _dev_analytics()
	await _dev_surveys()


## The developer menu's Surveys block (pass 62) under a real finger: the readout is there; Next run asks arms the next
## counted run, Counted runs adds one, Reset asks first (Keep leaves the record, Reset clears it), Show a survey now opens
## the card over the menu (a survey put in for the audit; its NOT NOW closes it) and Fetch now answers in the readout.
## Nothing stays: the survey record, the surveys and their status go back as they were.
func _dev_surveys() -> void:
	var an: Node = root.get_node_or_null("Analytics")
	var sav: Node = root.get_node("Save")
	if an == null or not an.has_method("survey_lines"):
		_count("dev_surveys", false)
		_fail("dev_surveys", "Analytics", "the autoload has no survey tools")
		return
	var keep_state: Dictionary = (sav.call("survey_state") as Dictionary).duplicate(true)
	var keep_surveys: Array = (an.get("surveys") as Array).duplicate(true)
	var keep_status := str(an.get("survey_status"))
	var box: Control = current_scene.find_child("Surveys", true, false)
	var ok_box: bool = box != null and box.find_children("*", "Control", true, false).size() > 3
	_count("dev_surveys", ok_box)
	if not ok_box:
		_fail("dev_surveys", "Surveys", "the readout is not in the developer menu")
	# Next run asks: a tap flips it
	var was_armed: bool = bool(an.call("next_run_armed"))
	if await _dev_tap("SurveyArm"):
		_dev_check(bool(an.call("next_run_armed")) != was_armed, "SurveyArm", "a tap did not arm (or disarm) the next run")
	# Counted runs: a tap adds one
	var c0 := int((sav.call("survey_state") as Dictionary).get("counted", 0))
	if await _dev_tap("SurveyCounted"):
		_dev_check(int((sav.call("survey_state") as Dictionary).get("counted", 0)) == c0 + 1, "SurveyCounted", "a tap did not add a counted run")
	# Reset: it asks; Keep leaves the record, Reset clears it
	var c1 := int((sav.call("survey_state") as Dictionary).get("counted", 0))
	if await _dev_tap("SurveyReset"):
		var conf: Control = _open_confirm_button("cancel_btn")
		_dev_check(conf != null, "SurveyReset", "a tap did not ask first")
		if conf:
			await _tap(await _spot(conf))
			await _wait(0.4)
			_dev_check(int((sav.call("survey_state") as Dictionary).get("counted", 0)) == c1, "SurveyReset", "Keep changed the record")
	if await _dev_tap("SurveyReset"):
		var ok_btn: Control = _open_confirm_button("confirm_btn")
		var asked := ok_btn != null
		if asked:
			await _tap(await _spot(ok_btn))
			await _wait(0.4)
		var st: Dictionary = sav.call("survey_state")
		_dev_check(asked and int(st.get("counted", -1)) == 0 and (st.get("answered", []) as Array).is_empty(), "SurveyReset", "Reset did not clear the record")
	# Show a survey now: the card over the menu; its NOT NOW closes it
	an.set("surveys", [{"id": "audit62", "name": "Audit [run 5]", "questions": [
		{"id": "q", "type": "rating", "question": "How much fun?", "description": "", "optional": false, "choices": [], "scale": 5, "lower": "", "upper": ""}]}])
	if await _dev_tap("SurveyShow"):
		var card: Control = current_scene.get_node_or_null("Survey")
		_dev_check(card != null, "SurveyShow", "a tap did not open the survey card")
		if card:
			var nn: Control = card.find_child("NotNow", true, false)
			await _tap(await _spot(nn))
			await _wait(0.5)
			# closed: done, or already gone after its fade
			_dev_check(not is_instance_valid(card) or bool(card.call("is_done")), "SurveyShow", "NOT NOW on the card did not close it")
	# Fetch now: a tool sends nothing, and the readout says why
	if await _dev_tap("SurveyFetch"):
		_dev_check(str(an.get("survey_status")).begins_with("not fetched") or str(an.get("survey_status")) == "fetching...", "SurveyFetch", "a tap left no word in the readout")
	var st2: Dictionary = sav.call("survey_state")
	st2.clear()
	st2.merge(keep_state, true)
	an.set("surveys", keep_surveys)
	an.set("survey_status", keep_status)
	sav.call("request_save")


## The open question's button (`which`: "cancel_btn" or "confirm_btn") on the developer menu, by the script's class name
## (this script compiles before the kit's classes can be named); a question already answered, still fading, is skipped.
func _open_confirm_button(which: String) -> Control:
	for n in current_scene.get_children():
		var sc: Script = n.get_script()
		if sc and str(sc.get_global_name()) == "WConfirm" and not bool(n.get("_done")):
			return n.get(which)
	return null


## A real tap on the developer menu's row `row_name` (found again: the menu rebuilds its rows); false when it is gone.
func _dev_tap(row_name: String) -> bool:
	await _wait(0.2)
	var row: Control = current_scene.find_child(row_name, true, false)
	if row == null:
		_count("dev_surveys", false)
		_fail("dev_surveys", row_name, "the row is not in the menu")
		return false
	await _tap(await _spot(row))
	await _wait(0.4)
	return true


func _dev_check(ok: bool, what: String, why: String) -> void:
	_count("dev_surveys", ok)
	if not ok:
		_fail("dev_surveys", what, why)


## The developer menu's dummy rows (pass 48) under a real finger: each tap steps its setting on; all put back after.
## Pass 49: the patrol (a flip), the attackers' health, the Elite's and the Boss's health and behaviour (the next of
## Settings.DUMMY_MODES).
func _dev_dummies() -> void:
	var st = root.get_node("Settings")
	var keys := ["dummy_hp", "dummy_count", "dummy_patrol", "attacker_dummy_hp", "elite_dummy_hp", "elite_dummy_mode", "boss_dummy_hp", "boss_dummy_mode"]
	var keep: Dictionary = {}
	for k: String in keys:
		keep[k] = st.get(k)
	var specs := [["DummyHealth", "dummy_hp", st.DUMMY_HP_STEPS], ["DummyCount", "dummy_count", st.DUMMY_COUNT_STEPS],
		["DummyPatrol", "dummy_patrol", null], ["AttackerHealth", "attacker_dummy_hp", st.ATTACKER_HP_STEPS],
		["EliteDummyHealth", "elite_dummy_hp", st.ELITE_DUMMY_HP_STEPS], ["EliteDummyMode", "elite_dummy_mode", null],
		["BossDummyHealth", "boss_dummy_hp", st.BOSS_DUMMY_HP_STEPS], ["BossDummyMode", "boss_dummy_mode", null]]
	for spec in specs:
		var row: Control = current_scene.find_child(str(spec[0]), true, false)
		if row == null:
			_count("dev_dummies", false)
			_fail("dev_dummies", str(spec[0]), "the row is not in the menu")
			continue
		var at: Vector2 = await _spot(row)
		var was = st.get(str(spec[1]))
		await _tap(at)
		await _wait(0.2)
		var now = st.get(str(spec[1]))
		var want = null
		if was is bool:
			want = not was
		elif was is String:
			want = st.next_mode(str(was))
		else:
			want = int(st.next_step(spec[2], int(was)))
		var ok: bool = str(now) != str(was) and str(now) == str(want)
		_count("dev_dummies", ok)
		if not ok:
			_fail("dev_dummies", str(spec[0]), "a tap did not step it on (%s -> %s)" % [str(was), str(now)])
	for k: String in keep.keys():
		st.set(k, keep[k])
	root.get_node("Save").request_save()
	root.get_node("Save").flush()


## Pass 101 (lane FPS): the developer menu's frame-rate row under a real finger: a tap steps Settings.frame_cap round
## 60 -> MAX -> 60 and the engine's cap (Engine.max_fps) follows; the setting goes back as it was.
func _dev_frame_cap() -> void:
	var st = root.get_node("Settings")
	var keep: int = int(st.frame_cap)
	for _k in range(2):
		await _wait(0.2)
		var row: Control = current_scene.find_child("FrameCap", true, false)
		if row == null:
			_count("dev_frame_cap", false)
			_fail("dev_frame_cap", "FrameCap", "the row is not in the menu")
			break
		var was: int = int(st.frame_cap)
		await _tap(await _spot(row))
		await _wait(0.3)
		var now: int = int(st.frame_cap)
		var want: int = int(st.next_frame_cap(was))
		var ok: bool = now == want and now != was and Engine.max_fps == maxi(now, 0)
		_count("dev_frame_cap", ok)
		if not ok:
			_fail("dev_frame_cap", "FrameCap", "a tap did not step the cap (%d -> %d, engine %d)" % [was, now, Engine.max_fps])
	st.frame_cap = keep
	root.get_node("Save").request_save()
	root.get_node("Save").flush()


## The Collection's back square at every camera-cutout inset (pass 48: the tabs and the board slid over it): on the
## grid and on an item's page, a finger at its middle and near each corner has to reach it.
func _collection_insets() -> void:
	var st = root.get_node("Settings")
	var was: int = st.top_inset
	for inset in [0, 80, 130, 180]:
		st.top_inset = inset
		change_scene_to_file("res://ui/CollectionScreen.tscn")
		await _wait(1.2)
		var c = current_scene
		await _back_taps(c, "grid, inset %d" % inset)
		c._open_page(root.get_node("Registry").weapon("boomstick"))
		await _wait(0.5)
		await _back_taps(c, "page, inset %d" % inset)
	st.top_inset = was


func _back_taps(scene: Node, what: String) -> void:
	var b: Control = scene.header.back_button
	var r := b.get_global_rect()
	for f: Vector2 in [Vector2(0.5, 0.5), Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.2, 0.8), Vector2(0.8, 0.8)]:
		var hit := [false]
		var saved := _mute(b.pressed)
		var probe := func(): hit[0] = true
		b.pressed.connect(probe)
		await _tap(r.position + r.size * f)
		if is_instance_valid(b):
			b.pressed.disconnect(probe)
			_unmute(b.pressed, saved)
		_count("collection_insets", hit[0])
		if not hit[0]:
			_fail("collection_insets", "back square (%s)" % what, "a finger at %s of it did not reach it" % str(f))


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
		# the abandon question (pass 45), over the options tab
		g.pause_screen._tab = 2
		g.pause_screen._refresh()
		await _wait(0.4)
		await _confirm_audit("pause_confirm", g.pause_screen, func(): g.pause_screen._ask_abandon())
		g.close_pause()
		await _wait(0.3)
	if _want("pause") or _want("pause_options"):
		await _pause_options(g)
	# pass 76 (lane UI): the Stats tab's cells open and close their sources under a real finger
	if _want("pause") or _want("pause_stats"):
		await _pause_stats(g)
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
		await _card_choices(g)
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
	if _want("cards") or _want("gate_strip"):
		await _gate_strip(g)
	if _want("path") or _want("path_offer"):
		await _path_offer(g)
	if _want("path"):
		await _path_choices(g)
	# pass 123 (lane RUN_C): a spent SKIP refused by a real finger (the skips pill under Royale)
	if _want("path") or _want("path_spent"):
		await _path_spent(g)
	if _want("chest"):
		g.open_chest(g.player.global_position + Vector3(1, 0, 0))
		# the chest opens before the reel (pass 46): a tap while it does goes straight to the spin
		await _wait(0.3)
		var cs = g.chest_screen
		var opening: bool = cs.intro_playing()
		if opening:
			await _tap(root.get_visible_rect().get_center())
			await _wait(0.1)
		var skipped: bool = opening and not cs.intro_playing() and cs._spinning
		_count("chest", skipped)
		if not opening:
			_fail("chest", "the chest", "the reel did not open with the chest")
		elif not skipped:
			_fail("chest", "the tap on the chest", "a tap while it opened did not skip to the spin")
		var waited := 0.0
		while waited < 8.0 and not g.chest_screen.buttons.visible:
			await _wait(0.25)
			waited += 0.25
		await _wait(0.6)
		await _audit("chest", g.chest_screen)
		await _chest_choices(g)
		if g.chest_screen.visible:
			g.chest_screen.visible = false
		# the reel was asked for through Game's one-screen rule (pass 60): a hand-close must give the turn back too
		g.modal_reset()
		g.set_paused(false)
		await _wait(0.3)
	if _want("boss_chest"):
		await _boss_chest(g)
	if _want("portal"):
		g.portal_dialog.open(1, true, false)
		await _wait(0.8)
		await _audit("portal", g.portal_dialog)
		await _portal_not_yet(g)
		g.portal_dialog.visible = false
		g.set_paused(false)
	if _want("portal") or _want("portal_expire"):
		await _portal_expire(g)
	if _want("hud") or _want("endless_banner"):
		await _endless_banner(g)
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
	if _want("totem"):
		await _totem(g)
	if _want("drum"):
		await _drum(g)
	if _want("grind"):
		await _grind(g)
	if _want("revive"):
		# the player's debug mode shows the last hits on Down! (pass 46: they moved there from Results), so its list and
		# buttons are tapped too; put back after and written back, since a save in between keeps the settings it saw
		var st = root.get_node("Settings")
		var was_debug: bool = st.debug_mode
		st.debug_mode = true
		g.set_paused(true)
		g.revive_screen.open(200, 1, g.player.damage_log_text())
		# the 8 s count must not run out into end_run while the screen and its question are audited
		g.revive_screen._held = true
		await _wait(0.8)
		await _audit("revive", g.revive_screen)
		await _confirm_audit("revive_confirm", g.revive_screen, func(): g.revive_screen._ask_give_up())
		g.revive_screen.visible = false
		g.set_paused(false)
		st.debug_mode = was_debug
		root.get_node("Save").request_save()
		root.get_node("Save").flush()
	if _want("results"):
		# a damage row of each kind (pass 47): a weapon, a perk, the revive's blast, explosions, fire, an unknown id
		for pair in [["boomstick", 640.0], ["supply_drop", 90.0], ["revive", 300.0], ["blast", 45.0], ["burn", 30.0], ["", 4.0]]:
			run.damage_by_weapon[pair[0]] = float(run.damage_by_weapon.get(pair[0], 0.0)) + float(pair[1])
		run.died = true
		# pass 72: an unlock to land, so the show has its second sequence whatever the save has done already
		var qt = load("res://core/systems/QuestTracker.gd")
		if not (qt.just_completed as Array).has("unlock_turret_buddy"):
			qt.just_completed.append("unlock_turret_buddy")
		g.end_run()
		# end_run's beat (1.2 s) and the fade to the Results (pass 72: its show starts at once, so no fixed wait)
		var w := 0.0
		while w < 6.0 and not (current_scene and current_scene.name.to_lower().contains("result")):
			await _wait(0.1)
			w += 0.1
		await _wait(0.3)
		if current_scene and current_scene.name.to_lower().contains("result"):
			await _results_show(current_scene)
			await _audit("results", current_scene)
			_results_rows(current_scene)
	if _want("arena") or _want("arena_hero"):
		run.arena_next = true
		change_scene_to_file("res://game/Game.tscn")
		await _wait(3.5)
		var a = current_scene
		if a.get("arena_panel"):
			if _want("arena"):
				await _audit("arena", a.arena_panel)
				a.arena_panel.open()
				await _wait(0.6)
				for t in a.arena_panel.TABS:
					a.arena_panel._tab = t[0]
					a.arena_panel._refresh()
					await _wait(0.5)
					await _audit("arena_" + str(t[0]), a.arena_panel._sheet)
				# a weapon's stack on ITEMS (pass 49), opened by its toggle
				await _arena_items(a.arena_panel)
				# pass 73 (lane CARDS): the cards' look chips on ITEMS
				await _arena_card_looks(a.arena_panel)
				# pass 76 (lane LOOKS): the weapon families' look chips on ITEMS
				await _arena_item_looks(a.arena_panel)
				a.arena_panel._tab = "world"
				a.arena_panel._refresh()
				await _wait(0.4)
				await _arena_dummies(a.arena_panel)
				# pass 110 (lane ARENA): the screenshot controls under real fingers
				await _arena_shots(a.arena_panel)
			# the HERO tab's heroes and looks under real fingers (pass 55); on its own (only=arena_hero) its controls are
			# audited first, as the tab loop above does in a whole run
			if _want("arena_hero"):
				await _arena_hero(a.arena_panel, not _want("arena"))
			if _want("arena"):
				# the leave question (pass 45), over the world tab
				a.arena_panel.open()
				a.arena_panel._tab = "world"
				a.arena_panel._refresh()
				await _wait(0.4)
				await _confirm_audit("arena_confirm", a.arena_panel, func(): a.arena_panel._ask_leave())


## The War Drum's moment and its plate (pass 106, lane DRUM): see the header.
func _drum(g) -> void:
	var d = root.get_node("Registry").structure("war_drum")
	if d == null:
		_count("drum", false)
		_fail("drum", "content/structures/war_drum", "no such structure")
		return
	var run = root.get_node("Run")
	g.use_structure(d, g.player.global_position)
	await _frames(2)
	var dm = g.drum_moment
	var up: bool = dm != null and dm.visible and bool(dm.playing) and g.paused
	_count("drum", up)
	if not up:
		_fail("drum", "the moment", "using the drum did not stop time for its moment")
		return
	var eaten: int = dm.touches_eaten
	var pb: Control = g.hud.get("_pause_btn")
	var spots: Array = [Vector2(540, 900), Vector2(540, 1700), Vector2(100, 300)]
	if pb:
		spots.append(pb.get_global_rect().get_center())
	for at in spots:
		await _tap(at)
	var held: bool = bool(dm.playing) and g.paused and not g.pause_screen.visible and int(dm.touches_eaten) >= eaten + spots.size()
	_count("drum", held)
	if not held:
		_fail("drum", "the moment", "a tap during it was not swallowed (or opened the pause menu, or ended it)")
	var w := 0.0
	while w < 4.0 and bool(dm.playing):
		await _wait(0.1)
		w += 0.1
	await _wait(0.2)
	var after: bool = not bool(dm.playing) and not dm.visible and not g.paused and run.boost_left("structure:war_drum") > 0.0
	_count("drum", after)
	if not after:
		_fail("drum", "the moment", "it did not end by itself into the boost and the running game")
		dm.skip()
		g.modal_reset()
		g.set_paused(false)
		return
	await _wait(0.3)
	var plate: Control = null
	for c in g.hud._buffs.get_children():
		if str(c.get_meta("buff", "")) == "structure:war_drum":
			plate = c
	var shows: bool = plate != null and _visible_in_tree(plate) and int(str(plate.get("level_text"))) > 0
	_count("drum_plate", shows)
	if not shows:
		_fail("drum_plate", "the boost's plate", "no plate with its seconds on the HUD")
		return
	# the plate only shows: a finger on it opens nothing and leaves the run running (as the power-ups' plates)
	await _tap(plate.get_global_rect().get_center())
	await _wait(0.3)
	var calm: bool = not g.paused and not g.pause_screen.visible and g.visible_modals().is_empty()
	_count("drum_plate", calm)
	if not calm:
		_fail("drum_plate", "the boost's plate", "a tap on it opened something or paused the run")
		if g.pause_screen.visible:
			g.close_pause()
	await _wait(0.2)


## The Grindstone's show under real fingers (pass 121, lane GRIND): see the header. The run's Grindstone is taken by the
## tool's hand (as a card would), its weapon the run's first.
func _grind(g) -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	if reg.passive("grindstone") == null or run.weapons.is_empty():
		_count("grind", false)
		_fail("grind", "content/passives/grindstone", "no Grindstone or no weapon in the run")
		return
	if run.passives.has("grindstone"):
		# a run that already holds it (a whole audit's earlier screens): taken out so it can be taken again
		run.passives.erase("grindstone")
		run.grind_used = {}
	var w = run.grind_target()
	if w == null:
		_count("grind", false)
		_fail("grind", "the Grindstone", "no weapon it could work on")
		return
	var id: String = w.def.id
	var lv0: int = w.level
	run.add_or_level_passive("grindstone")
	await _frames(2)
	var gm = g.get("grind_moment")
	var up: bool = gm != null and gm.visible and bool(gm.playing) and g.paused
	_count("grind", up)
	if not up:
		_fail("grind", "the show", "taking the Grindstone did not stop time for its show")
		return
	var pb: Control = g.hud.get("_pause_btn")
	var at: Vector2 = pb.get_global_rect().get_center() if pb else Vector2(540, 900)
	# a tap on the pause disc: swallowed (no pause menu), the show on to its reveal
	await _tap(at)
	var to_reveal: bool = bool(gm.playing) and not g.pause_screen.visible and str(gm.phase()) == "reveal" and int(gm.hurries) == 1
	_count("grind", to_reveal)
	if not to_reveal:
		_fail("grind", "the show", "a tap did not hurry it to the reveal (or opened the pause menu): phase %s" % str(gm.phase()))
	await _tap(Vector2(540, 1500))
	var to_stamp: bool = bool(gm.playing) and bool(gm.stamped)
	_count("grind", to_stamp)
	if not to_stamp:
		_fail("grind", "the show", "a second tap did not hurry it to the stamp")
	await _wait(0.45)
	await _tap(Vector2(540, 1500))
	var w2 := 0.0
	while w2 < 2.0 and bool(gm.playing):
		await _wait(0.05)
		w2 += 0.05
	var gate: bool = not bool(gm.playing) and not gm.visible and g.resume_gate.visible and g.paused
	_count("grind", gate)
	if not gate:
		_fail("grind", "the show", "it did not end into the gate")
		gm.skip()
	await _wait(0.3)
	await _tap(Vector2(540, 1500))
	await _frames(2)
	var w3 = run.weapon_instance(id)
	var lv1: int = w3.level if w3 != null else -1
	var ran: bool = not g.paused and not g.resume_gate.visible and (lv1 == lv0 + 1 or (w3 == null and run.grind_used.get("evolved", false)))
	_count("grind", ran)
	if not ran:
		_fail("grind", "the gate", "the run did not go on, or the weapon did not go up exactly once (%d -> %d)" % [lv0, lv1])
		if g.resume_gate.visible:
			g.resume_gate.tap()
	await _wait(0.2)


## The resume gate under a finger on the HUD's strip (pass 56): after a level-up's pick, a tap under the clock, at the
## strip's foot or on the pause disc lets the run go and does nothing else (the gate let the touch through, the strip
## heard it and the pause menu opened as the run went on); a tap under the strip lets the run go and starts the stick.
## The Totem Pole's gifts (pass 73, lane STRUCT): see the header. The save's run state is the tool's own run.
func _totem(g) -> void:
	var run = root.get_node("Run")
	var d = root.get_node("Registry").structure("totem_pole")
	if d == null:
		_count("totem", false)
		_fail("totem", "content/structures/totem_pole", "no such structure")
		return
	var before: int = run.totem_boons.size()
	g.use_structure(d, g.player.global_position)
	await _wait(0.8)
	# pass 83 (lane TOTEM): and until every gift has landed (bounded): a hit's hit-stop (Engine.time_scale 0.08 set mid
	# frame) makes an unscaled timer run fast, so the 0.8 s above could end 60 ms after the open, the gifts still moving
	for k in range(30):
		if g.totem_screen.planks().all(func(r) -> bool: return bool(r.arrived)):
			break
		await _wait(0.1)
	var ts = g.totem_screen
	_count("totem", ts.visible)
	if not ts.visible:
		_fail("totem", "the menu", "using a pole did not open it")
		return
	await _audit("totem", ts)
	# pass 82 (lane TOTEM, the Spirit Pole): taps anywhere off the gift rows (the dim, the label, the crest, the base, the
	# gaps between rows and beside a nail) take nothing; a finger laid on a gift and dragged off it takes nothing
	var planks: Array = ts.planks()
	for at in [Vector2(900, 200), Vector2(200, 320), Vector2(210, 430), Vector2(210, 1540), Vector2(700, 820),
			Vector2(540, 1800), Vector2(375, 515)]:
		await _tap(at)
	await _wait(0.3)
	var still: bool = ts.visible and run.totem_boons.size() == before
	_count("totem", still)
	if not still:
		_fail("totem", "the dim", "a tap off the gift rows took a gift or closed the menu")
	var from: Vector2 = (planks[0].tag as Control).get_global_rect().get_center()
	await _swipe(from, Vector2(540, 1800), 8)
	await _wait(0.3)
	var kept: bool = ts.visible and run.totem_boons.size() == before and not bool(planks[0].held)
	_count("totem", kept)
	if not kept:
		_fail("totem", "a gift", "a finger dragged off it took it (or left it held)")
	await _tap((planks[0] as Control).get_global_rect().get_center())
	await _wait(0.6)
	var took: bool = not ts.visible and run.totem_boons.size() == before + 1 and not g.paused
	_count("totem", took)
	if not took:
		_fail("totem", "a gift", "a real tap did not take its gift and close the menu")
		ts.visible = false
		g.modal_reset()
		g.set_paused(false)
	# under a camera cutout: a menu built at a 130 px inset (the design's own empty top) and one at 200 (the screen moved
	# down by the 70 px past it), its gifts under real fingers
	var st = root.get_node("Settings")
	var was: int = st.top_inset
	for inset in [130, 200]:
		st.top_inset = inset
		var screen := "totem_inset%d" % inset
		var scr = load("res://ui/TotemScreen.gd").new()
		g.ui.add_child(scr)
		var took2 := [{}]
		scr.closed.connect(func(b: Dictionary) -> void: took2[0] = b)
		g.set_paused(true)
		scr.open(load("res://core/systems/TotemBoons.gd").offer(d), d, 4, 11)
		await _wait(0.8)
		await _audit(screen, scr)
		var pl2: Array = scr.planks()
		var label: Rect2 = (scr.get_node("Label") as Control).get_global_rect()
		var top_ok: bool = label.position.y >= float(inset) and (pl2[0] as Control).get_global_rect().position.y > label.end.y
		_count(screen, top_ok)
		if not top_ok:
			_fail(screen, "the label", "it sits in the cutout or under the first gift")
		await _tap((pl2[2] as Control).get_global_rect().get_center())
		await _wait(0.6)
		var ok2: bool = not scr.visible and str((took2[0] as Dictionary).get("id", "")) == str(pl2[2].boon.get("id", "?"))
		_count(screen, ok2)
		if not ok2:
			_fail(screen, "a gift", "a real tap did not take its gift")
		scr.queue_free()
		g.set_paused(false)
		await _wait(0.3)
	st.top_inset = was


func _gate_strip(g) -> void:
	var vp := root.get_visible_rect().size
	var bh: float = float(g.hud.get("band_h"))
	var spots: Array = [["the strip under the clock", Vector2(vp.x * 0.5, bh * 0.45)],
		["the strip's foot", Vector2(vp.x * 0.5, bh - 6.0)]]
	var pb: Control = g.hud.get("_pause_btn")
	if pb:
		spots.append(["the pause disc", pb.get_global_rect().get_center()])
	spots.append(["under the strip", Vector2(vp.x * 0.5, vp.y * 0.7)])
	for s in spots:
		var what: String = s[0]
		var at: Vector2 = s[1]
		var under: bool = what == "under the strip"
		# a level-up and a pick for real, so the gate opens as in a run
		g._pending_levels += 1
		g._show_next_level_cards()
		await _wait(1.0)
		if g.cards.visible and not g.cards._offer.is_empty():
			g.cards._pick(g.cards._offer[0])
		await _wait(0.6)
		if g.resume_gate == null or not g.resume_gate.visible:
			_count("gate_strip", false)
			_fail("gate_strip", what, "the gate did not open after the pick")
			g.cards.visible = false
			g.set_paused(false)
			continue
		_touch(at, true)
		await _frames(2)
		var gone: bool = not g.resume_gate.visible
		var paused: bool = g.pause_screen.visible
		var stick: bool = g.player.input.wants_move
		_touch(at, false)
		await _frames(2)
		var ok: bool = gone and not paused and stick == under
		_count("gate_strip", ok)
		if not gone:
			_fail("gate_strip", what, "the tap did not let the gate go")
		elif paused:
			_fail("gate_strip", what, "the tap that let the gate go opened the pause menu")
		elif under and not stick:
			_fail("gate_strip", what, "the tap under the strip did not start the stick")
		elif stick and not under:
			_fail("gate_strip", what, "the tap on the strip started the stick")
		# put the run back as it was
		if g.pause_screen.visible:
			g.close_pause()
			await _wait(0.3)
		if g.resume_gate.visible:
			g.resume_gate.tap()
		await _wait(0.3)


## The stage clear's NOT YET (pass 48) under a real finger: the dialog closes, `declined` is heard and nothing is decided.
## Pass 87 (lane SUI): the Stages menu under real fingers (see the header). The save's stages, hero and map go back after.
func _stages_menu() -> void:
	var save = root.get_node("Save")
	var keep_beaten: Dictionary = (save.data.get("stages_beaten", {}) as Dictionary).duplicate(true)
	var keep_map = save.data.get("last_map", "red_canyon")
	save.data["last_map"] = "red_canyon"
	save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.4)
	var play: Control = current_scene.get("_play")
	if play and not bool(play.get("locked")):
		await _tap(play.get_global_rect().get_center())
		await _wait(1.0)
	var on_menu: bool = current_scene != null and current_scene.scene_file_path == "res://ui/StagesScreen.tscn"
	_count("stages", on_menu)
	if not on_menu:
		_fail("stages", "PLAY", "with stage 1 beaten a tap did not open the Stages menu")
		change_scene_to_file("res://ui/StagesScreen.tscn")
		await _wait(1.2)
	var menu = current_scene
	if _want("stages"):
		await _audit("stages", menu)
		var cards: Array = menu.call("cards")
		var opened := 0
		for c: Control in cards:
			var at: Vector2 = await _spot(c)
			if at == Vector2.INF:
				_fail("stages", _name_of(c), "not on screen")
				continue
			var open := bool(c.get_meta("open", false))
			var i := int(c.get_meta("stage", -1))
			menu.set("started", -1)
			menu.set("hold_start", true)
			await _tap(at)
			await _wait(0.5)
			var still: bool = current_scene == menu
			var got := int(menu.get("started"))
			var ok: bool = still and (got == i if open else got == -1)
			_count("stages", ok)
			if not ok:
				_fail("stages", _name_of(c), ("an open card did not start its stage (%d)" % got) if open else "a locked card started something or left the screen")
			if open:
				opened += 1
		if opened != 2:
			_fail("stages", "cards", "stage 1 beaten should open two stages, %d open" % opened)
		menu.set("hold_start", false)
		menu.set("started", -1)
		# the back square for real: the title
		var back: Control = menu.get("header").get("back_button")
		await _tap(back.get_global_rect().get_center())
		await _wait(1.0)
		var home: bool = current_scene != null and current_scene.scene_file_path == "res://ui/TitleScreen.tscn"
		_count("stages", home)
		if not home:
			_fail("stages", "back square", "a tap did not go back to the title")
	if _want("stages_play"):
		if current_scene == null or current_scene.scene_file_path != "res://ui/StagesScreen.tscn":
			change_scene_to_file("res://ui/StagesScreen.tscn")
			await _wait(1.2)
		var c2: Control = null
		for c in current_scene.call("cards"):
			if int(c.get_meta("stage", -1)) == 1:
				c2 = c
		if c2 == null:
			_fail("stages_play", "Stage 2", "no card")
		else:
			var at2: Vector2 = await _spot(c2)
			await _tap(at2)
			var w := 0.0
			while w < 8.0 and not (current_scene and current_scene.scene_file_path == "res://game/Game.tscn" and current_scene.get("hud") != null):
				await _wait(0.2)
				w += 0.2
			await _wait(1.0)
			var run = root.get_node("Run")
			var g = current_scene
			var in_game: bool = g != null and g.scene_file_path == "res://game/Game.tscn"
			var ok2: bool = in_game and int(run.stage) == 1 and int(run.level) == 1
			_count("stages_play", ok2)
			if not ok2:
				_fail("stages_play", "Stage 2", "the run did not start at stage 2 with a fresh hero (in game %s, stage %d, level %d)" % [in_game, int(run.stage) + 1, int(run.level)])
			elif g.get("hud"):
				var clock: String = str(g.hud.get("_timer").text)
				var fresh: bool = clock == "00:00" or clock == "00:01" or clock == "00:02"
				_count("stages_play", fresh)
				if not fresh:
					_fail("stages_play", "HUD clock", "a stage run's clock reads %s, not the stage's own 00:00" % clock)
			if in_game:
				g.player.god = true
				change_scene_to_file("res://ui/TitleScreen.tscn")
				await _wait(1.0)
	save.data["stages_beaten"] = keep_beaten
	save.data["last_map"] = keep_map
	root.get_node("Run").set("stage_next", 0)
	save.request_save()
	save.flush()


## Pass 123 (lane KIT2): tab_bar and kit_shell, on a hub screen made for the audit (a ScreenBase whose tab_bar() opens
## UPGRADE; under Royale it wears the docked tab bar). tab_bar: every tab answers a finger (the audit's taps, handlers
## unplugged), then real taps with the bar's `navigate` stubbed: STORE is refused and goes nowhere, the open tab goes
## nowhere, COLLECTIONS asks for its scene. Under Wanted the screen has no bar (counted as answered). kit_shell: the modal
## shell (WConfirm.shell) with a star line, a corner word, three buttons and a link: its dim, buttons and link answer a
## finger, then a real tap on its blue button answers that button's id and closes it.
func _tab_bar_audit() -> void:
	var src := "extends ScreenBase\nfunc tab_bar() -> String:\n\treturn \"upgrade\"\nfunc on_back() -> void:\n\tpass\n"
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	var hub: Control = gs.new()
	hub.name = "KitHub"
	change_scene_to_node(hub)
	await _wait(1.2)
	var scr: Control = current_scene
	if _want("tab_bar"):
		var bar: Control = scr.get("tab_bar_node")
		if bar == null:
			_count("tab_bar", false)
			_fail("tab_bar", "TabBar", "a hub screen with tab_bar() under Royale has no bar")
		else:
			await _audit("tab_bar", bar)
			var asked: Array = []
			bar.set("navigate", func(p: String) -> void: asked.append(p))
			for id in ["store", "upgrade", "collections"]:
				var t: Control = bar.call("tab", id)
				await _tap(t.get_global_rect().get_center())
				await _wait(0.4)
			var ok: bool = asked == ["res://ui/CollectionScreen.tscn"]
			_count("tab_bar", ok)
			if not ok:
				_fail("tab_bar", "tabs", "a real tap on STORE, UPGRADE (open), COLLECTIONS asked for %s" % str(asked))
	if _want("kit_shell"):
		var said: Array = []
		var cf = load("res://ui/wanted/WConfirm.gd")
		var sh = cf.shell(scr, {"star": "A quick word", "corner": "1 / 2", "title": "How much fun was that run?",
			"title_upper": false, "title_align": "left", "title_px": 44, "link": "Don't ask me again", "keep_open": true,
			"buttons": [{"id": "cancel", "text": "Not now", "role": "slate"}, {"id": "skip", "text": "Skip", "role": "slate"},
				{"id": "next", "text": "Next", "role": "blue"}],
			"on_answer": func(id: String) -> void: said.append(id)})
		await _wait(0.6)
		await _audit("kit_shell", sh)
		said.clear()
		var nb: Control = sh.call("button", "next")
		await _tap(nb.get_global_rect().get_center())
		await _wait(0.3)
		var ok2: bool = said == ["next"] and bool(cf.is_open(scr))
		_count("kit_shell", ok2)
		if not ok2:
			_fail("kit_shell", "Btn_next", "a real tap answered %s (open %s)" % [str(said), str(cf.is_open(scr))])
		await _tap(Vector2(540, 300))
		await _wait(0.3)
		var closed: bool = not bool(cf.is_open(scr))
		_count("kit_shell", closed)
		if not closed:
			_fail("kit_shell", "Dim", "a real tap on the dim did not answer cancel")
			cf.dismiss(scr)


## Pass 112 (lane WANTED): the floating Wanted posters under real fingers (see the header). The save's boards go back.
func _bounty_posters() -> void:
	var save = root.get_node("Save")
	var keep_w = save.data.get("wanted")
	for k in 2:
		var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 5, "bounty_board": true, "analytics": false}))
		f.close()
		change_scene_to_file("res://game/Game.tscn")
		var w := 0.0
		while w < 6.0 and not (current_scene and current_scene.get("bounty_posters") != null and current_scene.bounty_posters.visible):
			await _wait(0.2)
			w += 0.2
		var g = current_scene
		var bp = g.get("bounty_posters") if g else null
		var up: bool = bp != null and bp.visible and bool(g.paused)
		_count("wanted", up)
		if not up:
			_fail("wanted", "posters", "the floating posters did not come over the paused run")
			continue
		g.player.god = true
		await _wait(1.0)
		var cards: Array = bp.cards()
		if cards.size() != 3:
			_fail("wanted", "posters", "%d posters, not three" % cards.size())
		if k == 0:
			await _audit("wanted", bp)
			# a real tap on the second poster takes it
			var at: Vector2 = await _spot(cards[mini(1, cards.size() - 1)])
			await _tap(at)
			await _wait(1.6)
			var wr = g.get_node_or_null("WantedRun")
			var ok: bool = str(bp.chosen) == "taken" and not bp.visible and wr != null and wr.plate() != null 				and is_instance_valid(wr.plate()) and wr.plate().modulate.a > 0.9 and not bool(g.paused)
			_count("wanted", ok)
			if not ok:
				_fail("wanted", "a poster", "a real tap did not take it into the HUD plate and go on (chosen %s, contract %s, paused %s)" % [str(bp.chosen), str(wr != null), str(g.paused)])
		else:
			var nb: Control = bp.find_child("NoBounty", true, false)
			if nb == null:
				_fail("wanted", "No bounty", "not found")
				continue
			await _tap(nb.get_global_rect().get_center())
			await _wait(1.0)
			var none_ok: bool = str(bp.chosen) == "none" and not bp.visible and g.get_node_or_null("WantedRun") == null and not bool(g.paused)
			_count("wanted", none_ok)
			if not none_ok:
				_fail("wanted", "No bounty", "a real tap did not blow the posters away and go on without a contract")
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.0)
	if keep_w == null:
		save.data.erase("wanted")
	else:
		save.data["wanted"] = keep_w
	save.request_save()
	save.flush()


## Pass 87 (lane SUI): the stage clear's countdown runs out with it up: it closes by itself, says `expired`, decides
## nothing and declines nothing.
func _portal_expire(g) -> void:
	var pd = g.portal_dialog
	var left := [1.0]
	pd.seconds_source = func() -> float: return left[0]
	var heard := {"expired": 0, "declined": 0, "decided": 0}
	var on_exp := func(): heard["expired"] += 1
	var on_no := func(): heard["declined"] += 1
	var on_yes := func(_x): heard["decided"] += 1
	# Game's own answers unplugged while the dialog is tried on its own (it was opened here, not through the one-screen rule)
	var saved_exp := _mute(pd.expired)
	var saved_no := _mute(pd.declined)
	var saved_yes := _mute(pd.decided)
	pd.expired.connect(on_exp)
	pd.declined.connect(on_no)
	pd.decided.connect(on_yes)
	g.set_paused(true)
	pd.open(1, true, false)
	await _wait(0.6)
	var counting: String = str(pd.get("_count").text)
	left[0] = 0.0
	await _wait(0.3)
	pd.expired.disconnect(on_exp)
	pd.declined.disconnect(on_no)
	pd.decided.disconnect(on_yes)
	_unmute(pd.expired, saved_exp)
	_unmute(pd.declined, saved_no)
	_unmute(pd.decided, saved_yes)
	pd.seconds_source = Callable()
	var ok: bool = counting == "00:01" and not pd.visible and heard["expired"] == 1 and heard["declined"] == 0 and heard["decided"] == 0
	_count("portal_expire", ok)
	if not ok:
		_fail("portal_expire", "countdown", "showed %s; at 0 visible=%s expired=%d declined=%d decided=%d" % [counting, pd.visible, heard["expired"], heard["declined"], heard["decided"]])
	pd.visible = false
	g.set_paused(false)


## Pass 87 (lane SUI): Endless on the HUD: the ENDLESS banner, the clock's WAVE tag, and the tag lets a finger through to
## the strip (which pauses).
func _endless_banner(g) -> void:
	var hud = g.hud
	hud.set("test_stage_clock", {"endless": true, "endless_wave": 2, "endless_seconds": 12.0})
	hud.tick(0.0)
	await _wait(0.4)
	var said: String = hud.banner_text()
	var tag: String = hud.stage_tag_text()
	var ok: bool = said == "ENDLESS" and tag == "WAVE 2" and hud.clock_mode() == "endless"
	_count("endless_banner", ok)
	if not ok:
		_fail("endless_banner", "banner", "banner '%s', tag '%s', clock %s" % [said, tag, hud.clock_mode()])
	var st: Control = hud.get("_stage_tag")
	if st and st.is_visible_in_tree():
		var asked := [false]
		var saved := _mute(hud.pause_requested)
		var probe := func(): asked[0] = true
		hud.pause_requested.connect(probe)
		await _tap(st.get_global_rect().get_center())
		hud.pause_requested.disconnect(probe)
		_unmute(hud.pause_requested, saved)
		_count("endless_banner", asked[0])
		if not asked[0]:
			_fail("endless_banner", "WAVE tag", "a finger on it did not reach the strip (no pause)")
	hud.set("test_stage_clock", {})
	hud.tick(0.0)
	await _wait(0.2)


func _portal_not_yet(g) -> void:
	var pd = g.portal_dialog
	if not pd.visible:
		pd.open(1, true, false)
		await _wait(0.8)
	var nb: Control = pd.find_child("NotYet", true, false)
	if nb == null:
		_count("portal_not_yet", false)
		_fail("portal_not_yet", "NOT YET", "the button is not on the dialog")
		return
	var heard := [false]
	var chose := [false]
	var on_no := func(): heard[0] = true
	var on_yes := func(_x): chose[0] = true
	pd.declined.connect(on_no)
	pd.decided.connect(on_yes)
	var at: Vector2 = await _spot(nb)
	await _tap(at)
	await _wait(0.3)
	pd.declined.disconnect(on_no)
	pd.decided.disconnect(on_yes)
	var ok: bool = heard[0] and not chose[0] and not pd.visible
	_count("portal_not_yet", ok)
	if not ok:
		_fail("portal_not_yet", "NOT YET", "the tap did not close the dialog without a decision")


## The arena's training dummies (pass 48), on the WORLD tab under real fingers: a health choice sets Settings.dummy_hp
## (put back after) and RESET DUMMIES answers. Pass 49: each control is found in its named row (several rows have a "500"
## now): Patrol On, the Elite dummy's health 10,000 and behaviour Melee (which reach it at once and turn god mode off),
## + MELEE DUMMY (one attacker) and REMOVE ATTACKERS (none); every setting and god mode put back after.
func _arena_dummies(panel) -> void:
	var st = root.get_node("Settings")
	var g = panel.game
	var keep: Dictionary = {}
	for k: String in ["dummy_hp", "dummy_patrol", "elite_dummy_hp", "elite_dummy_mode"]:
		keep[k] = st.get(k)
	var god_was: bool = g.player.god
	# [row, the button's words, the setting, what it holds after the tap]
	for spec in [["DummyHealth", "500", "dummy_hp", 500], ["DummyPatrol", "On", "dummy_patrol", true],
			["EliteDummyHealth", "10,000", "elite_dummy_hp", 10000], ["EliteDummyMode", "Melee", "elite_dummy_mode", "melee"]]:
		var b := _row_button(panel, str(spec[0]), str(spec[1]))
		if b == null:
			_count("arena_dummies", false)
			_fail("arena_dummies", "%s %s" % [str(spec[0]), str(spec[1])], "not on the WORLD tab")
			continue
		await _tap(await _spot(b))
		await _wait(0.3)
		var set_ok: bool = str(st.get(str(spec[2]))) == str(spec[3])
		_count("arena_dummies", set_ok)
		if not set_ok:
			_fail("arena_dummies", "%s %s" % [str(spec[0]), str(spec[1])], "the tap did not set it (%s)" % str(st.get(str(spec[2]))))
	# the Elite dummy took them at once (2 is EnemyManager.DUMMY_MELEE), and god mode went off with the first attacker
	var e: int = int(g.dummy_index("elite"))
	var reached: bool = e >= 0 and int(g.enemies.dummy_mode[e]) == 2 and is_equal_approx(float(g.enemies.max_hp[e]), 10000.0) and not bool(g.player.god)
	_count("arena_dummies", reached)
	if not reached:
		_fail("arena_dummies", "the Elite dummy", "its health and behaviour did not reach it, or god mode stayed on")
	for spec2 in [["AttackerAdd", "+ MELEE DUMMY", 1], ["AttackerRemove", "REMOVE ATTACKERS", 0]]:
		var b2 := _row_button(panel, str(spec2[0]), str(spec2[1]))
		if b2 == null:
			_count("arena_dummies", false)
			_fail("arena_dummies", str(spec2[1]), "not on the WORLD tab")
			continue
		await _tap(await _spot(b2))
		await _wait(0.3)
		var n_ok: bool = int(g.attackers_standing()) == int(spec2[2])
		_count("arena_dummies", n_ok)
		if not n_ok:
			_fail("arena_dummies", str(spec2[1]), "%d attackers after the tap" % int(g.attackers_standing()))
	# the tab was drawn again: the button is a new one
	var reset: Button = null
	for b3 in panel._sheet.find_children("*", "Button", true, false):
		if (b3 as Button).text == "RESET DUMMIES" and _visible_in_tree(b3):
			reset = b3
	if reset == null:
		_count("arena_dummies", false)
		_fail("arena_dummies", "RESET DUMMIES", "not on the WORLD tab")
	else:
		var hit := [false]
		var probe := func(): hit[0] = true
		reset.pressed.connect(probe)
		await _tap(await _spot(reset))
		await _wait(0.3)
		if is_instance_valid(reset):
			reset.pressed.disconnect(probe)
		_count("arena_dummies", hit[0])
		if not hit[0]:
			_fail("arena_dummies", "RESET DUMMIES", "the tap did nothing")
	for k: String in keep.keys():
		st.set(k, keep[k])
	g.apply_dummy_settings()
	g.player.god = god_was


## The arena's HERO tab (pass 55) under real fingers: another hero's tile swaps him in (Run.character, the Player's def
## and the strip he is drawn with) and closes the sheet, the first hero's tile brings him back; a look chip draws that look
## on the hero for this visit only (the kept one unchanged), and USE FROM NOW ON keeps it (Save.hero_look, and in the
## copy the sandbox puts back). Everything is put back after: the kept look, the shown look, the hero. A hero with one
## look gets a stand-in second one in memory for the chips (Solenne's own may not be painted yet), taken away after.
## `audit_tab`: audit the tab's controls first (only=arena_hero; a whole run did it in the tab loop).
func _arena_hero(panel, audit_tab: bool) -> void:
	var g = panel.game
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var save = root.get_node("Save")
	var first = run.character
	if first == null:
		_count("arena_hero", false)
		_fail("arena_hero", "the hero", "no hero playing")
		return
	await _hero_tab(panel)
	if audit_tab:
		await _audit("arena_hero", panel._sheet)
		await _hero_tab(panel)
	# another hero by his tile, and the first one back by his
	var other = null
	for c in reg.sorted_characters():
		if c.id != first.id:
			other = c
			break
	for want in ([other, first] if other else []):
		var tile: Control = panel._content.find_child("Hero_" + str(want.id), true, false)
		if tile == null:
			_count("arena_hero", false)
			_fail("arena_hero", "Hero_" + str(want.id), "no tile on the HERO tab")
			continue
		await _tap(await _spot(tile))
		await _wait(0.3)
		var drawn = (g.player.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite")
		var swapped: bool = run.character != null and run.character.id == want.id and g.player.character == want
		var ok: bool = swapped and g.player.look != null and drawn == g.player.look.sprite and not panel.is_open()
		_count("arena_hero", ok)
		if not ok:
			_fail("arena_hero", "Hero_" + str(want.id), "the tap did not swap him in (%s playing)" % (run.character.id if run.character else "nobody"))
		await _hero_tab(panel)
	# the looks: a hero with two or more, else a stand-in second look on the hero playing
	var hero = null
	for c in reg.sorted_characters():
		if not c.variant_codes().is_empty():
			hero = c
			break
	var stand_in := hero == null
	var keep_variants: Dictionary = first.variants
	var keep_variant: String = first.variant
	if stand_in:
		hero = first
		var art := {"sprite": first.sprite, "sprite_file": first.sprite_file, "anims": first.anims, "fps": first.fps,
			"strip_cols": first.strip_cols, "frame_px": first.frame_px, "icon": first.icon, "note": "stand-in (touch audit)"}
		first.variants = {"AUDIT-A": art, "AUDIT-B": art.duplicate()}
		first.variant = "AUDIT-A"
		g.player.show_look("")
	elif run.character != hero:
		g.arena_swap_hero(hero.id)
	await _hero_tab(panel)
	var kept_raw: String = save.hero_look(hero.id)
	var shown: String = g.player.look_code()
	var pick := ""
	for code in hero.variant_codes():
		if str(code) != shown:
			pick = str(code)
			break
	var chip: Control = panel._content.find_child("Look_" + pick, true, false)
	if chip == null:
		_count("arena_hero", false)
		_fail("arena_hero", "Look_" + pick, "no look chip on the HERO tab")
	else:
		await _tap(await _spot(chip))
		await _wait(0.3)
		var ok2: bool = g.player.look_code() == pick and save.hero_look(hero.id) == kept_raw and not panel.is_open()
		_count("arena_hero", ok2)
		if not ok2:
			_fail("arena_hero", "Look_" + pick, "the tap did not show the look (%s on him)" % g.player.look_code())
		await _hero_tab(panel)
		var keep: Button = panel._content.find_child("KeepLook", true, false)
		if keep == null or keep.disabled or not _visible_in_tree(keep):
			_count("arena_hero", false)
			_fail("arena_hero", "KeepLook", "no USE FROM NOW ON to tap")
		else:
			await _tap(await _spot(keep))
			await _wait(0.3)
			var backup = save.get("_sandbox_backup")
			var in_backup: bool = not save.sandboxed() or (backup is Dictionary and (backup as Dictionary).get("hero_look", {}).get(hero.id, "") == pick)
			var ok3: bool = save.hero_look(hero.id) == pick and in_backup
			_count("arena_hero", ok3)
			if not ok3:
				_fail("arena_hero", "KeepLook", "the tap did not keep %s (kept %s)" % [pick, save.hero_look(hero.id)])
	# all put back
	save.set_hero_look(hero.id, kept_raw)
	g.player.show_look("")
	if stand_in:
		first.variants = keep_variants
		first.variant = keep_variant
	if run.character != first:
		g.arena_swap_hero(first.id)
	g.player.show_look("")
	panel.close()
	await _wait(0.3)


## The arena's sheet open on the HERO tab, drawn again.
func _hero_tab(panel) -> void:
	panel.open()
	panel._tab = "hero"
	panel._refresh()
	await _wait(0.4)


## The button with `text` in the WORLD tab's row called `row_name` (pass 49), else null.
## Pass 110 (lane ARENA): arena_shots (run with arena): the screenshot controls under real fingers. On the SHOTS tab a
## creature's chip picks it and Scatter sets the layout; in the quick column ½ and ¼ and 1x set the game's speed, FREEZE
## freezes the crowd and lets it go, FRAME frames the hero and lets go, HIDE UI hides the HUD and the column, and a tap on
## the invisible top-left corner brings them back. Everything is put back after.
func _arena_shots(panel) -> void:
	var g = panel.game
	panel.open()
	panel._tab = "shots"
	panel._refresh()
	await _wait(0.4)
	var chip: Button = panel._sheet.find_child("Crowd_lesser_scorpion", true, false) as Button
	var had: bool = panel._crowd_pick.has("lesser_scorpion")
	if chip == null:
		_count("arena_shots", false)
		_fail("arena_shots", "Crowd_lesser_scorpion", "no chip on SHOTS")
	else:
		await _tap(await _spot(chip))
		await _wait(0.3)
		var ok_pick: bool = panel._crowd_pick.has("lesser_scorpion") != had
		_count("arena_shots", ok_pick)
		if not ok_pick:
			_fail("arena_shots", "Crowd_lesser_scorpion", "the tap did not pick it")
	var lay := _row_button(panel, "CrowdLayout", "Scatter")
	if lay == null:
		_count("arena_shots", false)
		_fail("arena_shots", "CrowdLayout Scatter", "not on SHOTS")
	else:
		await _tap(await _spot(lay))
		await _wait(0.3)
		_count("arena_shots", str(panel._crowd_layout) == "scatter")
		if str(panel._crowd_layout) != "scatter":
			_fail("arena_shots", "CrowdLayout Scatter", "the layout is %s" % str(panel._crowd_layout))
	panel._crowd_layout = "ring"
	if panel._crowd_pick.has("lesser_scorpion") != had:
		panel.toggle_crowd("lesser_scorpion")
	panel.close()
	await _wait(0.3)
	# the quick column: [button name, what must hold after the tap, its words]
	var checks: Array = [
		["Speed_2", func() -> bool: return is_equal_approx(Engine.time_scale, 0.5), "half speed"],
		["Speed_4", func() -> bool: return is_equal_approx(Engine.time_scale, 0.25), "quarter speed"],
		["Speed_1", func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), "full speed"],
		["FreezeButton", func() -> bool: return int(g.enemies.crowd_freeze) != 0, "frozen"],
		["FreezeButton", func() -> bool: return int(g.enemies.crowd_freeze) == 0, "let go"],
		["FrameButton", func() -> bool: return float(g.camera.frame_hero_y) > 0.0, "framed"],
		["FrameButton", func() -> bool: return float(g.camera.frame_hero_y) < 0.0, "framing off"],
		["HideButton", func() -> bool: return bool(g.hud.clean_hidden) and not panel._col.visible and panel._corner.visible, "hidden"],
	]
	for spec in checks:
		var b: Button = panel._col.find_child(str(spec[0]), true, false) as Button
		if b == null or not _visible_in_tree(b):
			_count("arena_shots", false)
			_fail("arena_shots", str(spec[0]), "not in the quick column")
			continue
		await _tap(await _spot(b))
		await _wait(0.2)
		var ok: bool = (spec[1] as Callable).call()
		_count("arena_shots", ok)
		if not ok:
			_fail("arena_shots", str(spec[0]), "the tap did not leave it %s" % str(spec[2]))
	# the corner brings everything back
	if panel._corner.visible:
		await _tap(await _spot(panel._corner))
		await _wait(0.2)
	var back: bool = not bool(g.hud.clean_hidden) and panel._col.visible and not panel._corner.visible
	_count("arena_shots", back)
	if not back:
		_fail("arena_shots", "ShowControls", "a tap on the top-left corner did not bring the controls back")
	panel.set_speed(1.0)
	panel.set_freeze(0)
	panel.set_framing(false)
	panel.set_clean(false)


func _row_button(panel, row_name: String, text: String) -> Button:
	var row: Node = panel._sheet.find_child(row_name, true, false)
	if row == null:
		return null
	for b in row.find_children("*", "Button", true, false):
		if (b as Button).text == text and _visible_in_tree(b):
			return b as Button
	return null


## The ITEMS tab's stacks (pass 49) under a real finger: a weapon's toggle opens its stack under it, and every row drawn
## there answers like the rest (audited as arena_stack); the stack is shut again after. Pass 76 (lane DYN): the Skull
## Rain's (the Peashooter this used is hidden, its row out of the list).
func _arena_items(panel) -> void:
	panel._tab = "items"
	panel._refresh()
	await _wait(0.4)
	var row: Node = panel._content.find_child("Item_weapon_skull_rain", true, false)
	var tg: Control = row.find_child("Stack", true, false) if row else null
	if tg == null:
		_count("arena_stack", false)
		_fail("arena_stack", "the Skull Rain's stack", "no toggle on its row")
		return
	await _tap(await _spot(tg))
	await _wait(0.4)
	var stack: Array = panel.weapon_stack(root.get_node("Registry").weapon("skull_rain"))
	var found := 0
	for entry in stack:
		var under: Node = panel._content.find_child("Under_%s_%s" % [str(entry[0]), str(entry[1].id)], true, false)
		if under != null:
			found += 1
			await _audit("arena_stack", under)
	var opened: bool = not stack.is_empty() and found == stack.size()
	_count("arena_stack", opened)
	if not opened:
		_fail("arena_stack", "the Skull Rain's stack", "a tap on its toggle opened %d of %d rows" % [found, stack.size()])
	panel._open.erase("stack:skull_rain")
	# pass 51: its INFO under a real finger opens what a player reads about it, the very words item_texts gives
	panel._refresh()
	await _wait(0.3)
	row = panel._content.find_child("Item_weapon_skull_rain", true, false)
	var ib: Control = row.find_child("Info", true, false) if row else null
	if ib == null:
		_count("arena_info", false)
		_fail("arena_info", "the Skull Rain's INFO", "no toggle on its row")
		return
	await _tap(await _spot(ib))
	await _wait(0.4)
	var box: Node = panel._content.find_child("Info_weapon_skull_rain", true, false)
	var want: Array = panel.item_texts("weapon", root.get_node("Registry").weapon("skull_rain"))
	var shown: Label = box.find_child("InfoText0", true, false) if box else null
	var info_ok: bool = shown != null and not want.is_empty() and shown.text == str((want[0] as Array)[1])
	_count("arena_info", info_ok)
	if not info_ok:
		_fail("arena_info", "the Skull Rain's INFO", "a tap did not open its words (%s)" % ("no text" if shown == null else shown.text.left(60)))
	panel._open.erase("info:weapon:skull_rain")


## The cards' look on the arena's ITEMS tab (pass 73, lane CARDS) under a real finger: a tap on a look's chip draws every
## card in it at once (The Sun's icon is that look's) and keeps it on the phone (Save.card_look); JSON gives each card its
## own look back. Skipped (counted as passed) while the cards have one look only.
func _arena_card_looks(panel) -> void:
	var reg := root.get_node("Registry")
	var sv := root.get_node("Save")
	panel._tab = "items"
	panel._refresh()
	await _wait(0.4)
	var row: Node = panel._content.find_child("CardLooks", true, false)
	var codes: Array = reg.card_look_codes()
	if codes.size() < 2:
		_count("arena_card_looks", row == null)
		if row != null:
			_fail("arena_card_looks", "the Card look row", "shown with one look")
		return
	if row == null:
		_count("arena_card_looks", false)
		_fail("arena_card_looks", "the Card look row", "missing with looks %s" % str(codes))
		return
	var want := str(codes[codes.size() - 1])
	var chip: Control = null
	for b in row.get_children():
		if b is Button and (b as Button).text == want:
			chip = b
	if chip == null:
		_count("arena_card_looks", false)
		_fail("arena_card_looks", "the %s chip" % want, "not in the row")
		return
	panel._scroll.ensure_control_visible(chip)
	await _wait(0.2)
	await _tap(await _spot(chip))
	await _wait(0.4)
	var sun = reg.passive("brawn")
	var ok: bool = str(sv.card_look()) == want and sun != null and sun.icon == sun.look_icon(want)
	_count("arena_card_looks", ok)
	if not ok:
		_fail("arena_card_looks", "the %s chip" % want, "a tap left the cards in %s" % str(sv.card_look()))
	# JSON: each card's own look again
	row = panel._content.find_child("CardLooks", true, false)
	var back: Control = null
	if row:
		for b in row.get_children():
			if b is Button and (b as Button).text == "JSON":
				back = b
	if back:
		panel._scroll.ensure_control_visible(back)
		await _wait(0.2)
		await _tap(await _spot(back))
		await _wait(0.4)
	var reset: bool = str(sv.card_look()) == "" and sun != null and sun.icon == sun.look_icon(sun.variant)
	_count("arena_card_looks", reset)
	if not reset:
		_fail("arena_card_looks", "the JSON chip", "a tap left the cards in %s" % str(sv.card_look()))
	sv.set_card_look("")


## The weapon families' looks on the arena's ITEMS tab (pass 76, lane LOOKS) under a real finger: a tap on a look's chip
## keeps it for the family on the phone (Save.item_look), the family wears it at once (the weapon's name and icon are the
## look's) and a held weapon of it is made again in it (Game._sync_weapons: a new behaviour whose look_seen is the new
## look); JSON gives the family its weapon's own look back. While no family has two looks to play, lob_grenade gets a
## stand-in look "Z" in memory (the Revolver's icon) for the audit and loses it after, so the chips are always tried.
func _arena_item_looks(panel) -> void:
	var reg := root.get_node("Registry")
	var sv := root.get_node("Save")
	var run := root.get_node("Run")
	var g = panel.game
	var fams: Array = panel.item_look_weapons()
	var stand_in = null
	var stand_in_was := {}
	if fams.is_empty():
		var lg = reg.weapon("lob_grenade")
		var rv = reg.weapon("revolver")
		if lg == null or rv == null:
			_count("arena_item_looks", false)
			_fail("arena_item_looks", "a family to try", "no lob_grenade or revolver to make a stand-in look from")
			return
		stand_in = lg
		stand_in_was = {"variants": (lg.variants as Dictionary).duplicate(), "variant_base": str(lg.variant_base)}
		if str(lg.variant_base) == "":
			lg.variant_base = "A"
		lg.variants["Z"] = {"name": "Audit Look", "icon": rv.icon, "icon_file": "", "note": "touch audit stand-in"}
		reg.apply_item_looks()
		fams = panel.item_look_weapons()
	if fams.is_empty():
		_count("arena_item_looks", false)
		_fail("arena_item_looks", "the Weapon looks rows", "no family offers two looks")
		return
	var w = fams[0]
	var held_before: bool = run.weapon_instance(w.id) != null
	if not held_before:
		run.debug_set_item("weapon", w.id, 1)
	panel._tab = "items"
	panel._refresh()
	await _wait(0.4)
	# the held weapon's behaviour by its id: once it is made again the old one is freed, and a freed object reads as null
	var b0 = g._behaviors.get(w.id) if g else null
	var b0_id: int = (b0 as Object).get_instance_id() if b0 != null else 0
	var row: Node = panel._content.find_child("ItemLooks_" + str(w.id), true, false)
	if row == null:
		_count("arena_item_looks", false)
		_fail("arena_item_looks", "the %s looks row" % str(w.id), "missing with looks %s" % str(reg.item_look_codes(w.id)))
	else:
		var playing: String = reg.played_item_look(w.id)
		var want := ""
		for c in reg.item_look_codes(w.id):
			if str(c) != playing:
				want = str(c)
		var chip: Control = row.find_child("ItemLook_%s_%s" % [str(w.id), want], true, false)
		if chip == null:
			_count("arena_item_looks", false)
			_fail("arena_item_looks", "the %s chip" % want, "not in the row")
		else:
			await _tap(await _spot(chip))
			await _wait(0.4)
			var worn: bool = str(sv.item_look(w.id)) == want and str(w.look_code()) == want and w.icon == w.look_icon(want)
			_count("arena_item_looks", worn)
			if not worn:
				_fail("arena_item_looks", "the %s chip" % want, "a tap left %s in %s (kept %s)" % [str(w.id), str(w.look_code()), str(sv.item_look(w.id))])
			# the held weapon was made again in the look
			var b1 = g._behaviors.get(w.id) if g else null
			if b0_id != 0:
				var remade: bool = b1 != null and is_instance_valid(b1) and (b1 as Object).get_instance_id() != b0_id and str(b1.look_seen) == str(w.look_worn)
				_count("arena_item_looks", remade)
				if not remade:
					_fail("arena_item_looks", "the held %s" % str(w.id), "its behaviour was not made again in %s" % want)
			# JSON: the weapon's own look again
			row = panel._content.find_child("ItemLooks_" + str(w.id), true, false)
			var back: Control = row.find_child("ItemLook_%s_JSON" % str(w.id), true, false) if row else null
			if back:
				await _tap(await _spot(back))
				await _wait(0.4)
			var reset: bool = str(sv.item_look(w.id)) == "" and str(w.look_code()) == playing
			_count("arena_item_looks", reset)
			if not reset:
				_fail("arena_item_looks", "the JSON chip", "a tap left %s in %s (kept %s)" % [str(w.id), str(w.look_code()), str(sv.item_look(w.id))])
	sv.set_item_look(w.id, "")
	if not held_before:
		run.debug_set_item("weapon", w.id, 0)
	if stand_in != null:
		stand_in.variants = stand_in_was["variants"]
		stand_in.variant_base = stand_in_was["variant_base"]
		stand_in.wear_look("")
		reg.apply_item_looks()
	panel._refresh()
	await _wait(0.2)


## The level-up's choices by real fingers (pass 47: two skips and one banish a stage): SKIP with none left stays open and
## says so; BANISH then a card strikes that card, puts another in its place and spends the banish; SKIP with one left
## closes the screen on nothing and spends it. Pass 58: the banish states on a table laid out for them (_banish_states).
func _card_choices(g) -> void:
	var cards = g.cards
	var run = root.get_node("Run")
	if not cards.visible:
		return
	run.skips_left = 0
	cards._refresh_buttons()
	await _frames(2)
	await _tap(cards._skip_btn.get_global_rect().get_center())
	await _wait(0.2)
	var stayed: bool = cards.visible and str(cards.header.line.text) == "No skips left this stage."
	_count("card_choices", stayed)
	if not stayed:
		_fail("card_choices", "SKIP ×0", "with no skip left the tap did not stay and say so")
	await _banish_states(g)
	run.skips_left = 1
	cards._refresh_buttons()
	await _frames(2)
	await _tap(cards._skip_btn.get_global_rect().get_center())
	await _wait(0.5)
	var skipped: bool = not cards.visible and run.skips_left == 0
	_count("card_choices", skipped)
	if not skipped:
		_fail("card_choices", "SKIP ×1", "the tap did not close the cards on a skip")


## Banish by real fingers (pass 58, Garry: "Banish option should not allow Banishing items that Player already has"), on
## a table of one held card (a level of a weapon the hero has) between two new passive items: BANISH turns banish mode
## on and every control in it answers (cards_banish; a held card is locked but still takes the tap, to say why); a
## finger on the held card is refused (nothing spent, nothing struck, the card and the mode stay); BANISH again (CANCEL)
## turns it off; BANISH and a finger on a new card strike it (the banish spent, another card in its place, the mode off),
## and once the struck card's ghost has gone the table answers again (cards_after_banish); a table of upgrades only locks
## BANISH and its tap says why. The "banish" hint the first banish mode marks is put back as it was.
func _banish_states(g) -> void:
	var cards = g.cards
	var run = root.get_node("Run")
	var save = root.get_node("Save")
	var had_hint: bool = save.hint_seen("banish")
	var table := _banish_table(run, root.get_node("Registry"))
	if table.size() < 3:
		_fail("card_choices", "the banish table", "no weapon to level and two new passive items to lay out")
		return
	run.banishes_left = 1
	cards.show_offer(table, "LEVEL 9!", false)
	await _wait(1.0)
	await _tap(cards._banish_btn.get_global_rect().get_center())
	await _wait(0.4)
	var on: bool = cards.banish_mode()
	_count("card_choices", on)
	if not on:
		_fail("card_choices", "BANISH", "the tap did not turn banish mode on")
		return
	await _audit("cards_banish", cards)
	# the held card: refused
	var before: Array = run.banished.duplicate()
	var held_id := str(table[1]["id"])
	await _tap((cards._cards[1] as Control).get_global_rect().get_center())
	await _wait(0.4)
	var refused: bool = cards.banish_mode() and run.banished == before and run.banishes_left == 1 and str(cards._offer[1]["id"]) == held_id
	_count("card_choices", refused)
	if not refused:
		_fail("card_choices", "a held card in banish mode", "it was not refused (banished %s, left %d)" % [str(run.banished), run.banishes_left])
	# CANCEL
	await _tap(cards._banish_btn.get_global_rect().get_center())
	await _wait(0.3)
	var off: bool = not cards.banish_mode() and run.banishes_left == 1
	_count("card_choices", off)
	if not off:
		_fail("card_choices", "CANCEL", "the tap did not take banish mode back")
	# BANISH, then a new card: struck
	await _tap(cards._banish_btn.get_global_rect().get_center())
	await _wait(0.3)
	var id := str(cards._offer[0]["id"])
	await _tap((cards._cards[0] as Control).get_global_rect().get_center())
	await _wait(0.4)
	var struck: bool = run.banished.has(id) and run.banishes_left == 0 and cards.visible and not cards.banish_mode() \
		and str(cards._offer[0]["id"]) != id
	_count("card_choices", struck)
	if not struck:
		_fail("card_choices", "BANISH, then a new card", "the card was not struck from the run (banished %s, left %d)" % [str(run.banished.has(id)), run.banishes_left])
	# the ghost gone, the replacement dropped in: the table answers again
	await _wait(1.0)
	await _audit("cards_after_banish", cards)
	# upgrades only: BANISH locked, its tap says why, nothing changes
	run.banishes_left = 1
	cards.show_offer([table[1]], "LEVEL 9!", false)
	await _wait(1.0)
	await _tap(cards._banish_btn.get_global_rect().get_center())
	await _wait(0.3)
	var locked: bool = cards._banish_btn.locked and not cards.banish_mode() and run.banishes_left == 1 \
		and str(cards.header.line.text).begins_with("Nothing here can be banished")
	_count("card_choices", locked)
	if not locked:
		_fail("card_choices", "BANISH on upgrades only", "it did not stay locked and say why")
	if not had_hint:
		(save.data["hints_seen"] as Array).erase("banish")


## One held card (a level of the run's first weapon that can still grow) between two new passive items the run may find.
func _banish_table(run, reg) -> Array:
	var news: Array = []
	for p in reg.unlocked_passives():
		if p.is_line() or run.passives.has(p.id) or run.is_favourite(p) or run.banished.has(p.id):
			continue
		news.append({"type": "passive", "id": p.id, "def": p, "level_from": 0, "level_to": 1, "is_new": true, "weight": 1.0})
		if news.size() >= 2:
			break
	var held = null
	for w in run.weapons:
		if w.level < w.def.max_level and not w.def.is_evolution:
			held = {"type": "weapon", "id": w.def.id, "def": w.def, "level_from": w.level, "level_to": w.level + 1, "is_new": false, "weight": 1.0}
			break
	if held == null or news.size() < 2:
		return []
	return [news[0], held, news[1]]


## The mutation offer (pass 47): its buttons answer, and a real SKIP spends one of the stage's skips and closes it.
func _path_choices(g) -> void:
	var run = root.get_node("Run")
	if run.weapons.is_empty():
		return
	var offer: Array = load("res://core/systems/CardPool.gd").path_offer(run.weapons[0])
	if offer.is_empty():
		return
	g.set_paused(true)
	run.skips_left = 1
	g.cards.show_offer(offer, "MUTATION", false, true)
	# the pre-reel first (pass 54): its landing, then the cards
	await _wait_reel(g)
	await _wait(0.5)
	await _audit("path", g.cards)
	await _tap(g.cards._path_skip.get_global_rect().get_center())
	await _wait(0.5)
	var ok: bool = not g.cards.visible and run.skips_left == 0
	_count("path", ok)
	if not ok:
		_fail("path", "SKIP ×1", "the tap did not close the mutation offer on a skip")
	g.cards.visible = false
	g.set_paused(false)
	await _wait(0.3)


## Waits out the mutation offer's pre-reel (pass 54), at most 4 s.
## Pass 118 (lane BOSSCHEST): the boss chest's pop-up, opened through Game's own touch (open_boss_chest) on a pack made
## here: a tap while the chest knocks goes straight to the burst, a tap during the spew hurries it, CLAIM is a touch
## target once the count is done (the audit's muted tap), and its real tap closes the screen and pays out.
func _boss_chest(g) -> void:
	var pack := {"boss": "tumbleweed_king", "stage": 0, "gold": 420, "xp": 1500.0, "gold_base": 280.0, "xp_base": 1000.0,
		"mult": 1.5, "fight": 50.0, "secs": 40.0}
	# the claim pays real gold: the purse goes back as it was after it (pass 118, the lead: with 420 more the Shop's
	# audit afterwards could afford a card, its first tap bought it and closed the Shop, and its other prices "did nothing")
	var run_node = root.get_node("Run")
	var gold0: int = int(run_node.run_gold)
	g.open_boss_chest(g.player.global_position + Vector3(1, 0, 0), "tumbleweed_king", pack)
	await _wait(0.4)
	var bs = g.get("boss_chest_screen")
	if bs == null or not bs.visible:
		_fail("boss_chest", "the boss chest", "its pop-up did not open")
		return
	var burst: float = float(load("res://ui/BossChestScreen.gd").BURST)
	var opening: bool = float(bs.get("_t")) < burst - 0.1
	await _tap(root.get_visible_rect().get_center())
	await _wait(0.1)
	var jumped: bool = float(bs.get("_t")) >= burst - 0.1
	_count("boss_chest", opening and jumped)
	if not opening:
		_fail("boss_chest", "the boss chest", "it was past its opening before the first tap")
	elif not jumped:
		_fail("boss_chest", "the tap on the chest", "a tap while it knocked did not go to the burst")
	await _wait(0.6)
	var sp0: float = float(bs.get("_speed"))
	await _tap(root.get_visible_rect().get_center())
	await _wait(0.1)
	var hurried: bool = float(bs.get("_speed")) > sp0 or bs.is_done()
	_count("boss_chest", hurried)
	if not hurried:
		_fail("boss_chest", "the tap on the spew", "a tap while the coins flew did not hurry the count")
	var waited := 0.0
	while waited < 10.0 and not bs.ready_to_claim():
		await _wait(0.25)
		waited += 0.25
	await _wait(0.5)
	var cn: Array = bs.counters()
	var counted: bool = int(cn[0]) == int(bs.gold_total) and int(cn[1]) == int(round(float(bs.xp_total)))
	_count("boss_chest", counted)
	if not counted:
		_fail("boss_chest", "the counters", "they ended on %s, not on %d gold and %d XP" % [str(cn), int(bs.gold_total), int(round(float(bs.xp_total)))])
	await _audit("boss_chest", bs)
	var at: Vector2 = await _spot(bs._claim_btn)
	if at != Vector2.INF:
		await _tap(at)
	await _wait(0.6)
	_count("boss_chest", not bs.visible)
	if bs.visible:
		_fail("boss_chest", "CLAIM", "its tap did not close the pop-up")
		bs.claim()
		await _wait(0.4)
	# the claim's 1,500 XP banks level-ups whose cards would come up over every screen this audit opens after it (pass
	# 118, the lead: "two screens up at once: cards,shop" and the Shop's and the drum plate's failures): dropped here
	await _wait(0.6)
	g._pending_levels = 0
	g.cards.visible = false
	run_node.run_gold = gold0
	g.modal_reset()
	g.set_paused(false)
	await _wait(0.3)


func _wait_reel(g) -> void:
	var waited := 0.0
	while waited < 4.0 and g.cards.has_method("reel_running") and g.cards.reel_running():
		await _wait(0.1)
		waited += 0.1


## The mutation offer's pre-reel under a real finger (pass 54): it runs, a tap anywhere skips it to the landing, the head
## and the cards come, and a real tap on a card picks it (the offer is shown here, not by the game, so nothing is applied).
func _path_offer(g) -> void:
	var run = root.get_node("Run")
	if run.weapons.is_empty():
		return
	var offer: Array = load("res://core/systems/CardPool.gd").path_offer(run.weapons[0])
	if offer.is_empty():
		return
	g.set_paused(true)
	g.cards.show_offer(offer, "MUTATION", false, true)
	await _wait(0.3)
	var running: bool = g.cards.reel_running()
	_count("path_offer", running)
	if not running:
		_fail("path_offer", "the pre-reel", "the mutation offer opened without its reel")
	else:
		var hidden_cards: bool = not g.cards._list.visible
		_count("path_offer", hidden_cards)
		if not hidden_cards:
			_fail("path_offer", "the cards", "the cards showed while the reel ran")
		await _tap(root.get_visible_rect().get_center())
		await _wait(0.1)
		var landed: bool = g.cards._reel == null or g.cards._reel.is_landed()
		_count("path_offer", landed)
		if not landed:
			_fail("path_offer", "the tap on the reel", "a tap while it ran did not skip to the landing")
	await _wait_reel(g)
	await _wait(0.6)
	var shown: bool = g.cards._list.visible and not g.cards._cards.is_empty()
	_count("path_offer", shown)
	if not shown:
		_fail("path_offer", "the cards", "the cards did not come after the reel")
	else:
		var got := [false]
		var probe := func(_card): got[0] = true
		g.cards.chosen.connect(probe, CONNECT_ONE_SHOT)
		var card: Control = g.cards._cards[0]
		await _tap(card.get_global_rect().get_center())
		await _wait(0.5)
		_count("path_offer", got[0])
		if not got[0]:
			_fail("path_offer", _name_of(card), "a tap on a card after the reel did not pick it")
		if g.cards.chosen.is_connected(probe):
			g.cards.chosen.disconnect(probe)
	g.cards.visible = false
	g.set_paused(false)
	await _wait(0.3)


## The pause Stats tab (pass 76, lane UI) under a real finger: a tap on a stat's cell opens its sources under its row
## (the card in view), a second tap on it closes them; three stats down the grid (the last one low enough to scroll).
func _pause_stats(g) -> void:
	var ps = g.pause_screen
	g.open_pause()
	await _wait(0.4)
	ps._tab = 1
	ps._stat = "max_hp"
	ps._scroll.scroll_vertical = 0
	ps._refresh()
	await _wait(0.5)
	for stat in ["move_speed", "cooldown", "revive_hp"]:
		var cell: Control = ps._content.find_child("Stat_" + stat, true, false)
		if cell == null:
			_count("pause_stats", false)
			_fail("pause_stats", stat, "no cell on the Stats tab")
			continue
		var at: Vector2 = await _spot(cell)
		if at == Vector2.INF:
			_count("pause_stats", false)
			_fail("pause_stats", stat, "its cell is not on the screen")
			continue
		await _tap(at)
		await _wait(0.4)
		var card: Control = ps._content.find_child("Sources", true, false)
		var opened: bool = str(ps._stat) == stat and card != null
		_count("pause_stats", opened)
		if not opened:
			_fail("pause_stats", stat, "a tap did not open its sources")
			continue
		var shown: Rect2 = ps._scroll.get_global_rect().intersection(card.get_global_rect())
		_count("pause_stats", shown.size.y >= minf(card.size.y, ps._scroll.size.y) - 2.0)
		if shown.size.y < minf(card.size.y, ps._scroll.size.y) - 2.0:
			_fail("pause_stats", stat, "its sources opened out of sight (%d of %d px shown)" % [int(shown.size.y), int(card.size.y)])
		cell = ps._content.find_child("Stat_" + stat, true, false)
		at = await _spot(cell)
		await _tap(at)
		await _wait(0.4)
		var closed: bool = str(ps._stat) == "" and ps._content.find_child("Sources", true, false) == null
		_count("pause_stats", closed)
		if not closed:
			_fail("pause_stats", stat, "a second tap did not close its sources")
	print("touch_audit: pause_stats  cells %d" % 3)
	g.close_pause()
	await _wait(0.3)


## The pause Options (pass 54): the floating text's switches and size under a real finger (each put back after), and the
## volume thumbs whole inside the board's list at the top value and at nothing (the list clips; the thumbs hang over
## their rows and past the track's right end).
func _pause_options(g) -> void:
	var st = root.get_node("Settings")
	var ps = g.pause_screen
	g.open_pause()
	ps._tab = 2
	ps._refresh()
	await _wait(0.6)
	for spec in [["DamageNumbers", "damage_numbers"], ["HealNumbers", "float_heal"], ["XpNumbers", "float_xp"], ["CoinNumbers", "float_coins"]]:
		var sw: Control = ps.find_child(spec[0], true, false)
		if sw == null:
			_count("pause_options", false)
			_fail("pause_options", spec[0], "not on the Options tab")
			continue
		var was: bool = bool(st.get(spec[1]))
		var at: Vector2 = await _spot(sw)
		if at == Vector2.INF:
			_count("pause_options", false)
			_fail("pause_options", spec[0], "not on the screen")
			continue
		await _tap(at)
		await _wait(0.15)
		var ok: bool = bool(st.get(spec[1])) != was
		_count("pause_options", ok)
		if not ok:
			_fail("pause_options", spec[0], "a tap did not flip %s" % spec[1])
		st.set(spec[1], was)
		sw.set("on", was)
	var choice: Control = ps.find_child("FloatSize", true, false)
	if choice == null or choice.get_child_count() < 3:
		_count("pause_options", false)
		_fail("pause_options", "FloatSize", "not on the Options tab")
	else:
		var keep: int = int(st.float_size)
		for want in [2, 0]:
			var half: Control = choice.get_child(want)
			var at2: Vector2 = await _spot(half)
			if at2 == Vector2.INF:
				_count("pause_options", false)
				_fail("pause_options", "FloatSize %d" % want, "not on the screen")
				continue
			await _tap(at2)
			await _wait(0.15)
			var ok2: bool = int(st.float_size) == want
			_count("pause_options", ok2)
			if not ok2:
				_fail("pause_options", "FloatSize %d" % want, "a tap did not set the size (%d)" % int(st.float_size))
		st.float_size = keep
	# the thumbs: drawn as WSlider draws them, at the top value and at nothing, inside the list's clip with their shadow
	ps._scroll.scroll_vertical = 0
	await _frames(3)
	var clip: Rect2 = ps._scroll.get_global_rect()
	for row_name in ["SliderRowSound", "SliderRowMusic"]:
		var row: Control = ps.find_child(row_name, true, false)
		var sl: Control = null
		if row:
			for c in row.find_children("*", "Slider", true, false):
				sl = c
		if sl == null:
			_count("pause_options", false)
			_fail("pause_options", row_name, "no slider in the row")
			continue
		for frac in [0.0, 1.0]:
			var track := Rect2(0, (sl.size.y - 26.0 - 8.0) * 0.5, sl.size.x, 34.0)
			var inner := track.grow(-4.0)
			var tx := maxf(inner.position.x + inner.size.x * frac - 40.0, inner.position.x - 4.0)
			var th := Rect2(Vector2(tx, track.position.y - 20.0), Vector2(90, 80)).grow_individual(0, 0, 5, 5)
			var gr := Rect2(sl.get_global_transform() * th.position, th.size)
			var whole := clip.encloses(gr)
			_count("pause_options", whole)
			if not whole:
				_fail("pause_options", "%s thumb at %d" % [row_name, int(frac * 100)], "cut by the list's edge (%s outside %s)" % [str(gr), str(clip)])
	print("touch_audit: pause_options checked")
	# the taps saved what they set: the save gets the settings back as they were
	root.get_node("Save").request_save()
	root.get_node("Save").flush()
	g.close_pause()
	await _wait(0.3)


## The chest's choices by real fingers (pass 47): BANISH spends the stage's banish, spins the reel again to a new roll and
## leaves the chest open (the new landing is audited as chest_respin); SKIP with none left stays and says so; SKIP with
## one closes the chest on nothing. Pass 58: a roll that cannot be banished (Run.banish_refusal: gold, an evolution, a
## level of something the hero has, a path mutation of a weapon he holds) keeps BANISH locked.
func _chest_choices(g) -> void:
	var cs = g.chest_screen
	var run = root.get_node("Run")
	if not cs.visible or not cs.can_banish(cs.result()):
		# a roll that cannot be banished: BANISH stays locked, a tap spins nothing
		if cs.visible:
			var was: int = cs.respins
			await _tap(cs._banish_btn.get_global_rect().get_center())
			await _wait(0.2)
			var held: bool = cs.respins == was and cs.visible
			_count("chest_choices", held)
			if not held:
				_fail("chest_choices", "BANISH (locked)", "a tap on a roll that cannot be banished spun the reel (%s)" \
					% str(cs.banish_refusal(cs.result())))
		return
	run.banishes_left = 1
	cs._refresh_buttons()
	await _frames(2)
	var spins: int = cs.respins
	await _tap(cs._banish_btn.get_global_rect().get_center())
	await _wait(0.2)
	var again: bool = cs.respins == spins + 1 and cs.visible and run.banishes_left == 0
	_count("chest_choices", again)
	if not again:
		_fail("chest_choices", "BANISH ×1", "the tap did not spin the reel again")
		return
	var waited := 0.0
	while waited < 6.0 and not cs.buttons.visible:
		await _wait(0.25)
		waited += 0.25
	if not cs.buttons.visible:
		_count("chest_choices", false)
		_fail("chest_choices", "the second spin", "it did not land")
		return
	await _wait(0.4)
	await _audit("chest_respin", cs)
	if cs.result().get("def") == null:
		return
	run.skips_left = 0
	cs._refresh_buttons()
	await _frames(2)
	await _tap(cs._skip_btn.get_global_rect().get_center())
	await _wait(0.2)
	var stayed: bool = cs.visible and str(cs.header.line.text) == "No skips left this stage."
	_count("chest_choices", stayed)
	if not stayed:
		_fail("chest_choices", "SKIP ×0", "with no skip left the tap did not stay and say so")
	run.skips_left = 1
	cs._refresh_buttons()
	await _frames(2)
	await _tap(cs._skip_btn.get_global_rect().get_center())
	await _wait(0.5)
	var closed: bool = not cs.visible
	_count("chest_choices", closed)
	if not closed:
		_fail("chest_choices", "SKIP ×1", "the tap did not close the chest")
	# the run resumes on the gate's tap
	await _wait(0.3)
	if g.resume_gate and g.resume_gate.visible:
		await _tap(root.get_visible_rect().get_center())
		await _wait(0.3)


## The Results' show (pass 72) under real fingers: the buttons answer while it plays and a tap on one does not hurry
## it; a swipe up the board moves nothing (the board is held while the show plays) and counts as a tap (it hurries); a
## tap then ends the first sequence; in the second a tap hurries and another ends it, and the show is over.
func _results_show(rs: Node) -> void:
	if not rs.has_method("sequence"):
		_fail("results_show", "ResultsScreen", "no show (sequence())")
		return
	var waited := 0.0
	while int(rs.call("sequence")) != 1 and waited < 3.0:
		await _wait(0.1)
		waited += 0.1
	if int(rs.call("sequence")) != 1:
		_fail("results_show", "ResultsScreen", "the first sequence is not playing (%d)" % int(rs.call("sequence")))
		return
	# the buttons, while the show plays
	for b in rs.find_children("*", "Control", true, false):
		var wb := b as Control
		if not _is_kit(wb, "WButton") or not _visible_in_tree(wb):
			continue
		var at: Vector2 = wb.get_global_rect().get_center()
		var hit := [false]
		var saved := _mute(wb.pressed)
		var probe := func(): hit[0] = true
		wb.pressed.connect(probe)
		await _tap(at)
		wb.pressed.disconnect(probe)
		_unmute(wb.pressed, saved)
		var calm: bool = float(rs.call("speed")) == 1.0 and int(rs.call("sequence")) == 1
		_count("results_show", hit[0] and calm)
		if not hit[0]:
			_fail("results_show", _name_of(wb), "tap did nothing while the show played")
		elif not calm:
			_fail("results_show", _name_of(wb), "a tap on a button hurried the show")
	# a swipe up the board: the board stays, the show hurries
	var sc: ScrollContainer = rs.get("scroll")
	var v0 := sc.scroll_vertical
	var rr := sc.get_global_rect()
	var x := rr.position.x + rr.size.x * 0.5
	await _swipe(Vector2(x, rr.position.y + rr.size.y * 0.7), Vector2(x, rr.position.y + rr.size.y * 0.25), 12)
	await _frames(2)
	var held: bool = sc.scroll_vertical == v0 or int(rs.call("sequence")) != 1
	var hurried: bool = float(rs.call("speed")) > 1.0 or int(rs.call("sequence")) != 1
	_count("results_show", held and hurried)
	if not held:
		_fail("results_show", "board", "a swipe moved the board while the show played (%d -> %d)" % [v0, sc.scroll_vertical])
	elif not hurried:
		_fail("results_show", "board", "a finger on the board did not hurry the show")
	# a second tap ends the first sequence
	var mid := Vector2(x, rr.position.y + rr.size.y * 0.5)
	await _tap(mid)
	var ended: bool = int(rs.call("sequence")) >= 2
	_count("results_show", ended)
	if not ended:
		_fail("results_show", "board", "a second tap did not end the first sequence")
	# the second: a tap hurries it, another ends it (a run with nothing unlocked or closer has none: the show is over)
	if int(rs.call("sequence")) == 2:
		await _tap(mid)
		var fast: bool = float(rs.call("speed")) > 1.0 or int(rs.call("sequence")) == 3
		await _tap(mid)
		var over: bool = int(rs.call("sequence")) == 3
		_count("results_show", fast and over)
		if not (fast and over):
			_fail("results_show", "board", "the second sequence did not hurry (%s) or end (%s) under taps" % [str(fast), str(over)])
	var done: bool = int(rs.call("sequence")) == 3
	_count("results_show", done)
	if not done:
		_fail("results_show", "ResultsScreen", "the show is not over after its taps")
	await _wait(0.3)


## Every damage row on the Results (pass 47, Garry: "Each row must have both the icon and the text"): a plate with its
## picture or the "?", a name and a number.
func _results_rows(scene: Node) -> void:
	var rows: Node = scene.find_child("DamageRows", true, false)
	if rows == null:
		return
	for row in rows.get_children():
		var plate: Control = row.get_child(0)
		var pictured: bool = plate.get("tex") != null or str(plate.get("glyph")) == "?"
		var named: bool = row.find_child("Name", true, false) != null and row.find_child("Amount", true, false) != null
		_count("results_rows", pictured and named)
		if not (pictured and named):
			_fail("results_rows", str(row.get_meta("source", {}).get("name", "?")), "a damage row without its plate, name or number")


## Pass 123 (lane STAGES_SETTINGS). stages_start (run with stages): with stage 1 beaten, a real tap on each open card's
## START starts that stage once (held on the screen: `started` is its index and `starts` grew by exactly one, so the card
## under START did not start it again); a locked card has no START (Royale; under Wanted no card has one, counted as
## answered). settings_rows (run with settings): real taps on the size choice's LARGE and SMALL set the floating text's
## size, a real tap on WIPE asks (the pop-up closed again by its own cancel), and under Royale a real tap on the camera's
## FOLLOW sets Follow and one on RESET says DONE. Everything goes back as it was.
func _stages_settings_p123() -> void:
	if _want("stages") or _want("stages_start"):
		var save = root.get_node("Save")
		var keep_beaten: Dictionary = (save.data.get("stages_beaten", {}) as Dictionary).duplicate(true)
		save.data["last_map"] = "red_canyon"
		save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
		change_scene_to_file("res://ui/StagesScreen.tscn")
		await _wait(1.2)
		var menu = current_scene
		var found := 0
		for c: Control in menu.call("cards"):
			var open := bool(c.get_meta("open", false))
			var i := int(c.get_meta("stage", -1))
			var sb: Control = c.find_child("Start", true, false)
			if not open:
				_count("stages_start", sb == null)
				if sb != null:
					_fail("stages_start", _name_of(c), "a locked card has a START")
				continue
			if sb == null:
				_count("stages_start", false)
				_fail("stages_start", _name_of(c), "an open card has no START")
				continue
			found += 1
			var at: Vector2 = await _spot(sb)
			if at == Vector2.INF:
				_fail("stages_start", _name_of(c), "START not on screen")
				continue
			menu.set("started", -1)
			menu.set("hold_start", true)
			var before := int(menu.get("starts"))
			await _tap(at)
			await _wait(0.4)
			var got := int(menu.get("started"))
			var once := int(menu.get("starts")) == before + 1
			var ok: bool = current_scene == menu and got == i and once
			_count("stages_start", ok)
			if not ok:
				_fail("stages_start", "START of stage %d" % (i + 1), "a real tap started %d, %d time(s)" % [got, int(menu.get("starts")) - before])
		if found != 2:
			_fail("stages_start", "cards", "stage 1 beaten should show two STARTs, %d found" % found)
		menu.set("hold_start", false)
		save.data["stages_beaten"] = keep_beaten
	if _want("settings") or _want("settings_rows"):
		var st = root.get_node("Settings")
		var keep_size := int(st.get("float_size"))
		var keep_cam := int(st.get("camera_mode"))
		change_scene_to_file("res://ui/SettingsScreen.tscn")
		await _wait(1.2)
		var s = current_scene
		var size_choice: Control = s.find_child("FloatSize", true, false)
		if size_choice == null:
			_count("settings_rows", false)
			_fail("settings_rows", "FloatSize", "not on the screen")
		else:
			var halves: Array = size_choice.get_children()
			for want in [2, 0]:
				var at2: Vector2 = await _spot(halves[want])
				await _tap(at2)
				await _wait(0.2)
				var ok2: bool = int(st.get("float_size")) == int(want)
				_count("settings_rows", ok2)
				if not ok2:
					_fail("settings_rows", "FloatSize %d" % want, "a real tap did not set the size (%d)" % int(st.get("float_size")))
		var wipe: Control = s.get("_wipe")
		if wipe == null:
			_count("settings_rows", false)
			_fail("settings_rows", "Wipe", "no wipe button")
		else:
			await _tap(await _spot(wipe))
			await _wait(0.5)
			var c: Node = null
			for n in s.get_children():
				if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
					c = n
			_count("settings_rows", c != null)
			if c == null:
				_fail("settings_rows", "Wipe", "a real tap did not ask first")
			else:
				c.call("cancel")
				await _wait(0.3)
		var cam: Control = s.find_child("CameraChoice", true, false)
		if cam == null:
			_count("settings_rows", false)
			_fail("settings_rows", "CameraChoice", "not on the screen")
		else:
			await _tap(await _spot(cam.get_child(1)))
			await _wait(0.2)
			_count("settings_rows", int(st.get("camera_mode")) == 1)
			if int(st.get("camera_mode")) != 1:
				_fail("settings_rows", "CameraChoice FOLLOW", "a real tap did not set Follow")
		var reset: Control = s.find_child("ResetHints", true, false)
		if reset == null:
			_count("settings_rows", false)
			_fail("settings_rows", "ResetHints", "not on the screen")
		else:
			await _tap(await _spot(reset))
			await _wait(0.2)
			var said: String = str(reset.call("label_text"))
			_count("settings_rows", said == "DONE")
			if said != "DONE":
				_fail("settings_rows", "ResetHints", "a real tap did not say DONE (%s)" % said)
		st.set_value("float_size", keep_size)
		st.set_value("camera_mode", keep_cam)


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


## Pass 123 (lane MAINMENU): title_royale (run with title, or alone with only=title_royale; Royale only, nothing under
## Wanted): the Royale main menu (ui/TitleScreen.gd's Royale branch) under real fingers: its pieces are there and Wanted's
## are gone (no plaque, no Hero Collections button); every control answers a finger (muted); real taps on › and ‹ step
## the hero and back, a sideways swipe over him changes him; a real tap on DETAILS opens the shown hero's sheet and a tap
## on the dim closes it; ≡ goes to Settings; START (the map's stage 1 beaten) opens the Stages menu; every tab under a
## finger with the bar's navigate stubbed (STORE and a locked HEROES ask for nothing, BATTLE nothing, the rest their
## scenes); a hero on sale: BUY answers, its question audited and cancelled, a real BUY and the real deed buy him (his
## price spent once, owned, START open, his mask lifting); short of gold a real tap on the grey BUY asks nothing; a locked
## hero shows his requirement, START reads LOCKED and a real tap on it leaves nothing. The save goes back after.
func _title_royale() -> void:
	var save = root.get_node("Save")
	var reg = root.get_node("Registry")
	var kept := {}
	for k in ["gold", "heroes_owned", "quests_done", "stages_beaten", "last_character", "last_map"]:
		var v = save.data.get(k)
		kept[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	var title := "res://ui/TitleScreen.tscn"
	change_scene_to_file(title)
	await _wait(1.4)
	var t = current_scene
	for n in ["MenuButton", "Wallet", "Wordmark", "HeroRow", "Name", "TraitRow", "Start", "TabBar"]:
		var there: bool = t.find_child(n, false, false) != null
		_count("title_royale", there)
		if not there:
			_fail("title_royale", n, "not on the Royale title")
	for n in ["Plaque", "HeroesButton"]:
		var gone: bool = t.find_child(n, false, false) == null
		_count("title_royale", gone)
		if not gone:
			_fail("title_royale", n, "Wanted's piece is on the Royale title")
	await _audit("title_royale", t)
	# › and ‹ for real, then a swipe over the hero
	var n_heroes: int = (t._heroes as Array).size()
	if n_heroes >= 2:
		var i0: int = t._index
		var nxt: Control = t.find_child("Next", true, false)
		await _tap(nxt.get_global_rect().get_center())
		await _wait(0.4)
		var stepped: bool = t._index == posmod(i0 + 1, n_heroes)
		_count("title_royale", stepped)
		if not stepped:
			_fail("title_royale", "Next", "a real tap did not show the next hero")
		var prv: Control = t.find_child("Prev", true, false)
		await _tap(prv.get_global_rect().get_center())
		await _wait(0.4)
		var back: bool = t._index == i0
		_count("title_royale", back)
		if not back:
			_fail("title_royale", "Prev", "a real tap did not show the hero before")
		var y: float = (t.hero_figure_rect() as Rect2).get_center().y
		await _swipe(Vector2(760, y), Vector2(320, y), 10)
		await _wait(0.4)
		var swiped: bool = t._index != i0
		_count("title_royale", swiped)
		if not swiped:
			_fail("title_royale", "the hero", "a sideways swipe over him did not change the hero")
		t._index = i0
		t._show_hero(0)
		t._place()
		await _wait(0.4)
	# DETAILS: the shown hero's sheet, closed by its dim
	var det: Control = t.find_child("Details", true, false)
	await _tap(det.get_global_rect().get_center())
	await _wait(0.7)
	var sheet: Control = t.find_child("HeroSheet", false, false)
	var opened: bool = sheet != null and t.sheet_open() and sheet.get("hero") == t._heroes[t._index]
	_count("title_royale", opened)
	if not opened:
		_fail("title_royale", "Details", "a real tap did not open the shown hero's sheet")
	else:
		await _tap(Vector2(12, sheet.get_global_rect().get_center().y))
		await _wait(0.5)
		var dim_closes: bool = not t.sheet_open()
		_count("title_royale", dim_closes)
		if not dim_closes:
			_fail("title_royale", "the sheet's dim", "a tap outside the card did not close it")
			sheet.call("close")
		await _wait(0.3)
	# the tab bar, its navigate stubbed: STORE (and HEROES while its screen is missing) ask for nothing, BATTLE is this one
	var bar: Control = t.find_child("TabBar", false, false)
	if bar:
		var asked: Array = []
		bar.set("navigate", func(p: String): asked.append(p))
		for id: String in ["store", "heroes", "battle", "upgrade", "collections"]:
			asked.clear()
			var tab: Control = bar.call("tab", id)
			await _tap(tab.get_global_rect().get_center())
			await _wait(0.45)
			var goes: bool = id != "battle" and not bool(bar.call("is_locked", id))
			var ok: bool = (asked.size() == 1 and str(asked[0]) == str(bar.call("scene_of", id))) if goes else asked.is_empty()
			ok = ok and current_scene == t
			_count("title_royale", ok)
			if not ok:
				_fail("title_royale", "Tab_" + id, "a real tap asked for %s (wanted %s)" % [str(asked), str(bar.call("scene_of", id)) if goes else "nothing"])
	# ≡: Settings
	var menu: Control = t.find_child("MenuButton", false, false)
	await _tap(menu.get_global_rect().get_center())
	await _wait(1.3)
	var to_settings: bool = current_scene != null and str(current_scene.scene_file_path) == "res://ui/SettingsScreen.tscn"
	_count("title_royale", to_settings)
	if not to_settings:
		_fail("title_royale", "MenuButton", "a real tap did not open Settings")
	# START with the map's stage 1 beaten: the Stages menu (today's PLAY flow)
	save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	save.data["last_map"] = "red_canyon"
	change_scene_to_file(title)
	await _wait(1.4)
	t = current_scene
	if bool(t._play.locked):
		t._index = 0
		t._show_hero(0)
		t._place()
		await _wait(0.3)
	var start: Control = t.find_child("Start", false, false)
	await _tap(start.get_global_rect().get_center())
	await _wait(1.3)
	var to_stages: bool = current_scene != null and str(current_scene.scene_file_path) == "res://ui/StagesScreen.tscn"
	_count("title_royale", to_stages)
	if not to_stages:
		_fail("title_royale", "Start", "a real tap (stage 1 beaten) did not open the Stages menu")
	# heroes to buy and to unlock: two heroes sold after a quest, made one on sale and one locked
	var cands: Array = []
	for c in reg.sorted_characters():
		if not c.hidden and str(c.availability) == "purchase" and reg.quest_for("character", c.id) != null:
			cands.append(c)
	if cands.size() < 2:
		print("touch_audit: title_royale: fewer than two heroes sold after a quest, buying skipped")
	else:
		var sale = cands[0]
		var lock_h = cands[1]
		(save.data["heroes_owned"] as Array).erase(sale.id)
		(save.data["heroes_owned"] as Array).erase(lock_h.id)
		var qs = reg.quest_for("character", sale.id)
		if not save.quest_done(qs.id):
			(save.data["quests_done"] as Array).append(qs.id)
		(save.data["quests_done"] as Array).erase(reg.quest_for("character", lock_h.id).id)
		save.data["gold"] = int(sale.price) + 100
		change_scene_to_file(title)
		await _wait(1.4)
		t = current_scene
		t._index = (t._heroes as Array).find(sale)
		t._show_hero(0)
		t._place()
		await _wait(0.5)
		var buy: Control = t.find_child("Buy", true, false)
		var seen: bool = buy != null and _visible_in_tree(buy) and bool(t._play.locked)
		_count("title_royale", seen)
		if not seen:
			_fail("title_royale", "Buy", "no BUY over a hero on sale (or START open)")
		else:
			await _audit("title_royale_buy", t.find_child("BuyColumn", false, false))
			await _confirm_audit("title_royale_buy_confirm", t, func(): t.ask_buy())
			var gold0: int = save.gold()
			await _tap(buy.get_global_rect().get_center())
			await _wait(0.5)
			var ask: Node = null
			for n in t.get_children():
				if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
					ask = n
			_count("title_royale", ask != null)
			if ask == null:
				_fail("title_royale", "Buy", "a real tap did not ask")
			else:
				var deed: Control = ask.find_child("Confirm", true, false)
				await _tap(deed.get_global_rect().get_center())
				await _wait(0.9)
				var fig = t.get("_figure")
				var lifted: bool = fig != null and (fig.get("tint") as Color).is_equal_approx(Color.WHITE)
				var bought: bool = save.owns_hero(sale.id) and save.gold() == gold0 - int(sale.price) and not t._play.locked and lifted
				_count("title_royale", bought)
				if not bought:
					_fail("title_royale", "Confirm", "the deed did not buy him (owned %s, gold %d -> %d, START locked %s, mask lifted %s)" % [str(save.owns_hero(sale.id)), gold0, save.gold(), str(t._play.locked), str(lifted)])
			# short of gold: the grey BUY asks nothing
			(save.data["heroes_owned"] as Array).erase(sale.id)
			save.data["gold"] = maxi(int(sale.price) - 50, 0)
			t._heroes = t._roster()
			t._index = (t._heroes as Array).find(sale)
			t._show_hero(0)
			t._place()
			await _wait(0.5)
			var grey: Control = t.find_child("Buy", true, false)
			var g1: int = save.gold()
			await _tap(grey.get_global_rect().get_center())
			await _wait(0.5)
			var asked2 := false
			for n in t.get_children():
				if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
					asked2 = true
			var nothing: bool = bool(grey.get("locked")) and not asked2 and save.gold() == g1 and not save.owns_hero(sale.id)
			_count("title_royale", nothing)
			if not nothing:
				_fail("title_royale", "Buy (short)", "a real tap on the grey BUY asked or bought")
		# a locked hero: his requirement, START LOCKED, a real tap leaves nothing
		t._index = (t._heroes as Array).find(lock_h)
		t._show_hero(0)
		t._place()
		await _wait(0.5)
		var req: Control = t.find_child("Requirement", false, false)
		var shows: bool = req != null and _visible_in_tree(req) and bool(t._play.locked) and t.find_child("Padlock", true, false) != null
		_count("title_royale", shows)
		if not shows:
			_fail("title_royale", "Requirement", "a locked hero shows no requirement or padlock (or START is open)")
		await _tap(t._play.get_global_rect().get_center())
		await _wait(0.7)
		var stayed: bool = current_scene == t
		_count("title_royale", stayed)
		if not stayed:
			_fail("title_royale", "LOCKED", "a real tap on LOCKED left the title")
	for k in kept.keys():
		save.data[k] = kept[k]


## Pass 123 (lane COLLECTION; only=collection_royale): the Collection under real fingers in either theme: every tab opened
## by a tap; a found tile opens its page (under Royale the tab bar stands aside), the back square brings the grid back
## (the bar again); a locked tile opens its requirement page; under Royale a tap on the open COLLECTIONS tab asks for
## nothing (its navigation stubbed) and a swipe on a long page scrolls it inside its sheet.
func _collection_royale_audit() -> void:
	change_scene_to_file("res://ui/CollectionScreen.tscn")
	await _wait(1.2)
	var c = current_scene
	for t in c.TABS.size():
		var tab: Control = c._tabs._tabs[t]
		await _tap(tab.get_global_rect().get_center())
		await _wait(0.3)
		_count("collection_royale", c._tab == t)
		if c._tab != t:
			_fail("collection_royale", str(c.TABS[t]), "a tap on the tab did not open it")
	await _tap((c._tabs._tabs[0] as Control).get_global_rect().get_center())
	await _wait(0.3)
	var grids: Array = c.content.find_children("*", "GridContainer", true, false)
	if grids.is_empty():
		_count("collection_royale", false)
		_fail("collection_royale", "grid", "no grid of tiles")
		return
	var grid: Control = grids[0]
	var items: Array = c._items(0)
	var picks := {"found": -1, "locked": -1}
	for i in mini(items.size(), grid.get_child_count()):
		if picks["found"] < 0 and c._found(items[i]) and not c._locked(items[i]):
			picks["found"] = i
		if picks["locked"] < 0 and c._locked(items[i]):
			picks["locked"] = i
	for kind in ["found", "locked"]:
		var i: int = picks[kind]
		if i < 0:
			continue
		# the grid is built again after every page (back): take the one standing now
		var now: Array = c.content.find_children("*", "GridContainer", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
		if now.is_empty() or (now[0] as Node).get_child_count() <= i:
			_count("collection_royale", false)
			_fail("collection_royale", "%s tile" % kind, "the grid was not built again")
			continue
		var tile: Control = (now[0] as Node).get_child(i)
		var at: Vector2 = await _spot(tile)
		if at == Vector2.INF:
			_count("collection_royale", false)
			_fail("collection_royale", "%s tile" % kind, "could not bring it into view")
			continue
		await _tap(at)
		await _wait(0.3)
		var opened: bool = c._page == items[i]
		# pass 123 (Garry's brief: "Keep the tab bar on all four hub screens"): the bar stays on the page
		if opened:
			opened = (c.tab_bar_node as Control).visible
		_count("collection_royale", opened)
		if not opened:
			_fail("collection_royale", "%s tile '%s'" % [kind, str(items[i].get("id"))], "a tap did not open its page (or the bar went)")
			continue
		if kind == "found":
			# a long page scrolls under a finger inside its sheet
			var inner: Control = c.scroll.get_child(0)
			if inner.size.y > c.scroll.size.y + 40.0:
				var rr: Rect2 = c.scroll.get_global_rect()
				var x := rr.position.x + rr.size.x * 0.5
				await _swipe(Vector2(x, rr.position.y + rr.size.y * 0.75), Vector2(x, rr.position.y + rr.size.y * 0.3), 12)
				await _wait(0.4)
				_count("collection_royale", c.scroll.scroll_vertical > 20)
				if c.scroll.scroll_vertical <= 20:
					_fail("collection_royale", "page", "a swipe did not scroll the page")
		await _tap(c.header.back_button.get_global_rect().get_center())
		await _wait(0.3)
		var back: bool = c._page == null and ((c.tab_bar_node as Control).visible)
		_count("collection_royale", back)
		if not back:
			_fail("collection_royale", "back square", "a tap on it did not bring the grid (and the bar) back")
	if c.tab_bar_node:
		var bar = c.tab_bar_node
		var asked: Array = []
		bar.set("navigate", func(path: String) -> void: asked.append(path))
		var open_tab: Control = bar.call("tab", "collections")
		await _tap(open_tab.get_global_rect().get_center())
		await _wait(0.3)
		var still: bool = asked.is_empty() and current_scene == c
		_count("collection_royale", still)
		if not still:
			_fail("collection_royale", "COLLECTIONS tab", "a tap on the open tab asked for %s" % str(asked))


## Pass 123 (lane HEROES; only=heroes_screen,hero_details): the Heroes screen (ui/HeroesScreen.tscn, the Royale HEROES
## tab; it builds under Wanted too, though nothing there reaches it) and the Hero details pop-up under real fingers.
## heroes_screen: every button, tile and list audited; a real tap on a grid tile shows that hero; SELECT on a hero owned
## makes him the one runs start with; the looks strip (May's looks sold for the audit, so it runs past the screen) moves
## sideways under a sideways swipe and the page does not, a vertical swipe that starts on it moves the page and not the
## strip; a real tap on a look on sale asks and its Cancel closes the question; BUY on a hero on sale asks (audited, then
## cancelled: still on sale), then BUY and the real deed buy him; LOCKED asks nothing. hero_details: DETAILS · ALL STATS
## opens the pop-up by a real tap, it is audited (CLOSE, its list, its looks), a tap on the dim closes it, CLOSE closes
## it. The save's gold, heroes, quests, looks and May's variants go back after.
func _heroes_audit() -> void:
	var path := "res://ui/HeroesScreen.tscn"
	if not ResourceLoader.exists(path):
		_count("heroes_screen", false)
		_fail("heroes_screen", "HeroesScreen.tscn", "missing")
		return
	var save = root.get_node("Save")
	var reg = root.get_node("Registry")
	var kept := {}
	for k in ["gold", "heroes_owned", "quests_done", "skins_owned", "skin_worn", "hero_look", "last_character"]:
		var v = save.data.get(k)
		kept[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	var may = reg.character("may")
	var may_kept: Dictionary = (may.variants as Dictionary).duplicate(true)
	for code in may.variants.keys():
		if str(code) != may.home_look():
			var e: Dictionary = (may.variants[code] as Dictionary).duplicate(true)
			e["shelved"] = false
			e["skin"] = {"purchasable": true, "name": "Look " + str(code), "price": 300, "currency_type": "gold"}
			may.variants[code] = e
	save.data["gold"] = 104711
	save.data["heroes_owned"] = ["astro", "may"]
	save.data["skins_owned"] = []
	save.data["skin_worn"] = {}
	save.data["hero_look"] = {}
	save.data["last_character"] = "drifter"
	change_scene_to_file(path)
	await _wait(1.4)
	var s = current_scene
	var cfx = load("res://ui/wanted/WConfirm.gd")
	if _want("heroes_screen"):
		await _audit("heroes_screen", s)
		# a real tap on Astro's tile shows him; SELECT makes him the hero runs start with
		await _heroes_tap_tile(s, "astro")
		var shown_astro: bool = s.get("shown") != null and str(s.get("shown").id) == "astro"
		_count("heroes_screen", shown_astro)
		if not shown_astro:
			_fail("heroes_screen", "Hero_astro", "a real tap did not show him")
		var sel: Control = s.find_child("Select", true, false)
		await _tap(await _spot(sel))
		await _wait(0.3)
		var picked: bool = str(save.data.get("last_character", "")) == "astro"
		_count("heroes_screen", picked)
		if not picked:
			_fail("heroes_screen", "SELECT", "a real tap did not make Astro the hero runs start with")
		# May's looks (pass 123, the pop-up behind LOOKS): a real tap opens it; a look on sale asks and Cancel brings the looks
		# back with nothing bought; a real tap on Close closes it
		await _heroes_tap_tile(s, "may")
		var lb: Control = s.find_child("LooksBtn", true, false)
		await _tap(await _spot(lb))
		await _wait(0.5)
		var opened: bool = bool(s.call("looks_open"))
		_count("heroes_screen", opened)
		if not opened:
			_fail("heroes_screen", "LooksBtn", "a real tap did not open the looks")
		else:
			var strip: Control = s.get("looks_grid")
			var on_sale: Control = null
			for t in strip.get_children():
				if str(t.get_meta("state", "")) == "buyable" and on_sale == null:
					on_sale = t
			if on_sale:
				var sale_code := str(on_sale.get_meta("look"))
				await _tap(on_sale.get_global_rect().get_center())
				await _wait(0.5)
				var asked: bool = bool(cfx.is_open(s)) and not bool(s.call("looks_open"))
				_count("heroes_screen", asked)
				if not asked:
					_fail("heroes_screen", str(on_sale.name), "a real tap on a look on sale did not ask")
				else:
					var cancel: Control = cfx.current(s).find_child("Cancel", true, false)
					await _tap(cancel.get_global_rect().get_center())
					await _wait(0.5)
					var back: bool = bool(s.call("looks_open")) and not save.owns_skin(reg.skin_key("may", sale_code))
					_count("heroes_screen", back)
					if not back:
						_fail("heroes_screen", "Cancel", "the looks did not come back, or it bought")
			var closer: Control = cfx.current(s).button("cancel") if cfx.is_open(s) else null
			if closer:
				await _tap(closer.get_global_rect().get_center())
				await _wait(0.5)
			var shut: bool = not bool(cfx.is_open(s))
			_count("heroes_screen", shut)
			if not shut:
				_fail("heroes_screen", "Close", "a real tap did not close the looks")
		# BUY: Ironwood on sale; the question audited and cancelled, then the real deed
		var iron = reg.character("ironwood")
		await _heroes_tap_tile(s, "ironwood")
		await _confirm_audit("heroes_buy_confirm", s, func(): s.call("ask_buy"))
		var still: bool = reg.hero_state(iron) == "buyable"
		_count("heroes_screen", still)
		if not still:
			_fail("heroes_screen", "BUY", "Cancel bought him")
		var g0: int = save.gold()
		await _tap(await _spot(s.find_child("Select", true, false)))
		await _wait(0.5)
		var ask = cfx.current(s)
		if ask == null:
			_count("heroes_screen", false)
			_fail("heroes_screen", "BUY", "a real tap did not ask")
		else:
			await _tap((ask.find_child("Confirm", true, false) as Control).get_global_rect().get_center())
			await _wait(0.6)
			var bought: bool = reg.hero_state(iron) == "owned" and save.gold() == g0 - int(iron.price)
			_count("heroes_screen", bought)
			if not bought:
				_fail("heroes_screen", "Confirm", "the deed did not buy Ironwood (gold %d -> %d)" % [g0, save.gold()])
		# LOCKED: Fadeaway (his quest not done) asks nothing
		(save.data["quests_done"] as Array).erase("unlock_fadeaway")
		s.call("refresh")
		await _wait(0.2)
		await _heroes_tap_tile(s, "fadeaway")
		var g1: int = save.gold()
		await _tap(await _spot(s.find_child("Select", true, false)))
		await _wait(0.5)
		var none: bool = not bool(cfx.is_open(s)) and save.gold() == g1 and reg.hero_state(reg.character("fadeaway")) == "locked"
		_count("heroes_screen", none)
		if not none:
			_fail("heroes_screen", "LOCKED", "a real tap on LOCKED asked or bought")
	if _want("hero_details"):
		await _heroes_tap_tile(s, "drifter")
		var det: Control = s.find_child("Details", true, false)
		await _tap(await _spot(det))
		await _wait(0.8)
		var sheet: Control = s.find_child("HeroSheet", false, false)
		var opened: bool = sheet != null and bool(s.call("sheet_open"))
		_count("hero_details", opened)
		if not opened:
			_fail("hero_details", "DETAILS · ALL STATS", "a real tap did not open the pop-up")
		else:
			await _audit("hero_details", sheet)
			await _tap(Vector2(12, 960))
			await _wait(0.4)
			var dim_closes: bool = not bool(s.call("sheet_open"))
			_count("hero_details", dim_closes)
			if not dim_closes:
				_fail("hero_details", "Dim", "a tap outside the card did not close the pop-up")
			# DETAILS again by a real tap, then CLOSE by a real tap
			await _tap(await _spot(s.find_child("Details", true, false)))
			await _wait(0.8)
			sheet = s.get("_sheet")
			var close: Control = sheet.find_child("Close", true, false) if sheet and is_instance_valid(sheet) else null
			var at_close := Vector2.INF
			# (the button is freed with the pop-up: whether there was one is read before the tap)
			var had_close := close != null
			if had_close:
				at_close = close.get_global_rect().get_center()
				await _tap(at_close)
				await _wait(0.4)
			var closed: bool = had_close and not bool(s.call("sheet_open"))
			_count("hero_details", closed)
			if not closed:
				_fail("hero_details", "CLOSE", "a real tap at %s did not close the pop-up (open %s)" % [str(at_close), str(s.call("sheet_open"))])
	may.variants = may_kept
	for k in kept.keys():
		save.data[k] = kept[k]


## A real tap on hero `id`'s tile in the Heroes screen's grid (brought into view first), then the page settles.
func _heroes_tap_tile(s, id: String) -> void:
	var grid: Control = s.find_child("HeroGrid", true, false)
	var t: Control = grid.find_child("Hero_" + id, false, false) if grid else null
	if t == null:
		_fail("heroes_screen", "Hero_" + id, "no tile")
		return
	await _tap(await _spot(t))
	await _wait(0.45)


## Pass 123 (lane UPGRADE): upgrade_buy (run alone with only=upgrade_buy): the Upgrade board under real fingers, the
## save's talents and purse lent in memory and put back after: a tap on Grit's CHOOSE opens its choice; the pop-up's green
## BUY in each option buys the next rank in that option for its price; a tap on the dim closes the choice; RESET UPGRADES
## asks, its KEEP THEM keeps every rank, and asked again its deed takes the board back for half.
func _upgrade_buy() -> void:
	var save = root.get_node("Save")
	var reg = root.get_node("Registry")
	var kept := {}
	for k in ["gold", "talents", "talent_spent", "talent_spent_in"]:
		var v = save.data.get(k)
		kept[k] = v.duplicate(true) if v is Dictionary else v
	var def = reg.talent("grit")
	save.data["talents"] = {}
	save.data["talent_spent"] = 0
	save.data["talent_spent_in"] = {}
	save.data["gold"] = int(def.cost_of_rank(0)) + int(def.cost_of_rank(1)) + 1000
	change_scene_to_file("res://ui/HomesteadScreen.tscn")
	await _wait(1.2)
	var hs = current_scene
	var tile: Control = hs._grid.get_node_or_null("Talent_grit")
	var opener: Control = null
	if tile:
		opener = tile.find_child("Choose", true, false)
	var at := Vector2.INF
	if opener:
		at = await _spot(opener)
	if at != Vector2.INF:
		await _tap(at)
		await _wait(0.6)
	var opened: bool = hs._sheet_root != null and is_instance_valid(hs._sheet_root)
	_count("upgrade_buy", opened)
	if not opened:
		_fail("upgrade_buy", "Grit's CHOOSE", "a real tap did not open its choice")
	else:
		for form in [0, 1]:
			var gold_was := int(save.data["gold"])
			var cost := int(def.cost_of_rank(int(save.talent_rank("grit"))))
			var b: Control = hs._sheet_root.find_child("Buy%d" % form, true, false)
			var at2 := Vector2.INF
			if b:
				at2 = await _spot(b)
			if at2 != Vector2.INF:
				await _tap(at2)
				await _wait(0.4)
			var picks: Array = save.talent_picks("grit")
			var bought: bool = picks.size() == form + 1 and int(picks.back()) == form and int(save.data["gold"]) == gold_was - cost
			_count("upgrade_buy", bought)
			if not bought:
				_fail("upgrade_buy", "Buy%d" % form, "a real tap did not buy rank %d in option %d (picks %s)" % [form + 1, form, str(picks)])
		# the dim above the card closes the choice
		var dim: Control = hs._sheet_root.find_child("Dim", true, false)
		if dim and dim.has_meta("tap_at"):
			await _tap(dim.get_global_transform() * (dim.get_meta("tap_at") as Vector2))
			await _wait(0.5)
		var shut: bool = hs._sheet_root == null
		_count("upgrade_buy", shut)
		if not shut:
			_fail("upgrade_buy", "the choice's dim", "a real tap did not close it")
			hs._close(false)
			await _wait(0.3)
	# RESET UPGRADES asks; KEEP THEM keeps; its deed refunds half
	var reset: Control = hs.get("_reset")
	for deed in [false, true]:
		var back := int(save.talent_refund())
		var gold_was2 := int(save.data["gold"])
		var at3 := Vector2.INF
		if reset:
			at3 = await _spot(reset)
		if at3 != Vector2.INF:
			await _tap(at3)
			await _wait(0.5)
		var ask: Node = null
		for n in hs.get_children():
			if _is_kit(n, "WConfirm") and not bool(n.get("_done")):
				ask = n
		_count("upgrade_buy", ask != null)
		if ask == null:
			_fail("upgrade_buy", "RESET UPGRADES", "a real tap did not ask")
			break
		var btn: Control = ask.find_child("Confirm" if deed else "Cancel", true, false)
		if btn:
			await _tap(btn.get_global_rect().get_center())
			await _wait(0.5)
		var picks2: Array = save.talent_picks("grit")
		var ok2: bool
		if deed:
			ok2 = picks2.is_empty() and int(save.data["gold"]) == gold_was2 + back and int(save.data.get("talent_spent", 0)) == 0
		else:
			ok2 = picks2.size() == 2 and int(save.data["gold"]) == gold_was2
		_count("upgrade_buy", ok2)
		if not ok2:
			_fail("upgrade_buy", "Confirm" if deed else "Cancel", "the board after it: picks %s, gold %d" % [str(picks2), int(save.data["gold"])])
		if is_instance_valid(ask) and not bool(ask.get("_done")):
			ask.call("cancel")
	for k in kept.keys():
		save.data[k] = kept[k]


## Pass 123 (lane RUN_C): the mutation offer with the stage's skips spent: a real finger on its SKIP is refused (the
## screen stays, nothing is spent below none) and the offer says why: under Royale the black pill over the SKIP reads
## "No skips left this stage" (and shakes), under Wanted the line under the head (pass 47).
func _path_spent(g) -> void:
	var run = root.get_node("Run")
	if run.weapons.is_empty():
		return
	var offer: Array = load("res://core/systems/CardPool.gd").path_offer(run.weapons[0])
	if offer.is_empty():
		return
	g.set_paused(true)
	run.skips_left = 0
	g.cards.show_offer(offer, "MUTATION", false, true)
	await _wait_reel(g)
	await _wait(0.5)
	await _tap(g.cards._path_skip.get_global_rect().get_center())
	await _wait(0.3)
	var words: String = str(g.cards.call("skips_pill_text"))
	var ok: bool = g.cards.visible and int(run.skips_left) == 0 and words.begins_with("No skips left this stage")
	_count("path_spent", ok)
	if not ok:
		_fail("path_spent", "SKIP ×0", "a tap on the spent skip closed the offer or did not say why (%s)" % words)
	g.cards.visible = false
	g.set_paused(false)
	run.skips_left = 2
	await _wait(0.3)


## Pass 123 (lane RUN_C): the survey's rating under real fingers: a tap on 4 lights it alone (gold under Royale, brass
## under Wanted) and unlocks NEXT; a tap on NEXT turns to the next page (a page that is not the last sends nothing).
func _survey_pick() -> void:
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.2)
	var host: Control = current_scene as Control
	if host == null:
		host = Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
	var sv := {"id": "audit123", "name": "Audit", "questions": [
		{"id": "b1", "type": "rating", "question": "How much fun?", "description": "", "optional": false, "choices": [], "scale": 5, "lower": "Not fun", "upper": "Loved it"},
		{"id": "b2", "type": "open", "question": "Anything else?", "description": "", "optional": true, "choices": [], "scale": 5, "lower": "", "upper": ""}]}
	var card: Control = load("res://ui/wanted/WSurvey.gd").open(host, sv)
	await _wait(0.6)
	var r4: Control = card.find_child("Rate4", true, false)
	var nxt: Control = card.find_child("Next", true, false)
	if r4 == null or nxt == null:
		_count("survey_pick", false)
		_fail("survey_pick", "Rate4 / Next", "the survey has no rating cells or no NEXT")
		card.queue_free()
		return
	await _tap(r4.get_global_rect().get_center())
	await _wait(0.2)
	var lit: bool = bool(card.call("is_marked", r4)) and not bool(nxt.get("locked"))
	for k in [1, 2, 3, 5]:
		var other: Control = card.find_child("Rate%d" % k, true, false)
		lit = lit and other != null and not bool(card.call("is_marked", other))
	_count("survey_pick", lit)
	if not lit:
		_fail("survey_pick", "4", "a finger on 4 did not light it alone, or NEXT stayed locked")
	await _tap(nxt.get_global_rect().get_center())
	await _wait(0.3)
	var turned: bool = int(card.get("page")) == 1 and card.find_child("Answer", true, false) != null
	_count("survey_pick", turned)
	if not turned:
		_fail("survey_pick", "NEXT", "a finger on NEXT did not turn to the next page")
	card.queue_free()
	if host != current_scene:
		host.queue_free()
	await _wait(0.2)
