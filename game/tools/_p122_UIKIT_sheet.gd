## The kit's component sheet (pass 122, lane UIKIT_B): every component of the Wanted kit laid on two 1080 x 1920 pages
## under either theme, so the Royale pieces can be set beside the mock's system sheet
## (.playwright-mcp/rq_after/system_sheet.png; docs/ui_review/royale_picks/img/kit_frames.jpg, kit_buttons.jpg) and the
## Wanted sheet shows today's kit untouched. Windowed, silent:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --script res://tools/_p122_UIKIT_sheet.gd -- out=<png> theme=royale|wanted [page=1|2]
## Without page= both pages are written, "_1" and "_2" put before the ".png". Page 1: the type samples, the buttons of
## every role at 150 / 106 / 64 (a count pill, a pressed one, a locked one), the item frames of every rarity + evolved +
## locked + a level plaque at 200 and at 80 (an empty slot too), a docked tab bar. Page 2: the XP, HP, shield, boss and
## gold bars, a slider and a stepped one, two switches, a segmented control, a modal frame (a cream 72 title, a 28 body
## line, two buttons), the coins, two pointers, a black info plate, a star line, a seal, a stamp, a nail, the notches, a
## placeholder, and three cards (a new passive item, an upgrade with its change rows, one held). The kit's classes are
## loaded by path at run time (a --script compiles before the autoloads exist). Every wait is a fixed count of frames
## and a watchdog quits after WATCHDOG seconds.
## Pass 123 (lane KIT2): page=3, the shared pieces of the remaining screens (the menu header and wallet, the info pills,
## the price buttons, the drawn glyphs, the solid sheet and cells, the modal shell's card, the docked tab bar); without
## page= all three pages are written ("_3" too).
extends SceneTree

const WATCHDOG := 90.0
const BACK_ROYALE := Color("0f1a3a")
const BACK_WANTED := Color("d9c9a4")

var _out := "user://kit_sheet.png"
var _theme := "royale"
var _page := 0
var _started := 0
var W_: GDScript
var R_: GDScript
var _kit: Dictionary = {}
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("theme="):
			_theme = a.substr(6)
		elif a.begins_with("page="):
			_page = int(a.substr(5))
	_started = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_watch)


func _watch() -> void:
	if Time.get_ticks_msec() - _started > WATCHDOG * 1000.0:
		print("kit_sheet: watchdog, quitting")
		quit(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _script(name: String) -> GDScript:
	if not _kit.has(name):
		_kit[name] = load("res://ui/wanted/%s.gd" % name)
	return _kit[name]


func _main() -> void:
	W_ = load("res://ui/wanted/W.gd")
	R_ = load("res://ui/wanted/R.gd")
	_reg = root.get_node("Registry")
	await _frames(2)
	print("kit_sheet: theme ", W_.theme_name())
	var pages: Array = [1, 2, 3] if _page <= 0 else [_page]
	for p in pages:
		var canvas := _canvas()
		root.add_child(canvas)
		if p == 1:
			_page_one(canvas)
		elif p == 3:
			_page_three(canvas)
		else:
			_page_two(canvas)
		await _frames(6)
		var path := _out
		if _page <= 0:
			path = _out.get_basename() + "_%d.png" % p
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(path)
		print("kit_sheet: page %d -> %s" % [p, path])
		canvas.queue_free()
		await _frames(2)
	quit()


func _canvas() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = BACK_ROYALE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(back)
	return c


func _at(c: Control, x: float, y: float, w: float = -1.0, h: float = -1.0) -> Control:
	c.position = Vector2(x, y)
	if w >= 0.0 or h >= 0.0:
		c.size = Vector2(w if w >= 0.0 else c.size.x, h if h >= 0.0 else c.size.y)
	return c


## A label naming a group of pieces (the mock's small caps lines).
func _caption(canvas: Control, t: String, x: float, y: float) -> void:
	var l = W_.label(t, 18, W_.INK_SOFT)
	canvas.add_child(_at(l, x, y))


## A passive item of `rarity` (not hidden, with an icon), or null.
func _passive_of(rarity: String):
	for p in _reg.passives.values():
		if p.rarity == rarity and not p.hidden and not p.is_evolved() and not p.is_line() and p.icon != null:
			return p
	return null


## The frames' side on page 1 and their step: six across the 1080 page (the big rims and plaques hold from 160 px).
const BIG := 164.0
const STEP := 172.0


func _page_one(canvas: Control) -> void:
	var WButton_ := _script("WButton")
	var WPlate_ := _script("WPlate")
	var WTabs_ := _script("WTabs")
	# type samples
	_caption(canvas, "Type · 150 gold number · 60 name · 30 body · labels · tags", 40, 30)
	canvas.add_child(_at(W_.slab_text("1,200", 150, W_.BRASS_DARK), 40, 60))
	canvas.add_child(_at(W_.slab_text("The Drifter", 60, W_.INK), 520, 80))
	canvas.add_child(_at(W_.serif_text("+8 thorns damage a level.", 30, W_.INK), 520, 160))
	canvas.add_child(_at(W_.label("Weapon · a 20 label", 20, W_.INK_SOFT), 520, 212))
	var WCard_ := _script("WCard")
	canvas.add_child(_at(WCard_.tag_pill("NEW", 24), 40, 232))
	canvas.add_child(_at(WCard_.tag_pill("UPGRADE", 24), 150, 232))
	canvas.add_child(_at(WCard_.tag_pill("EVOLUTION", 24), 310, 232))
	# buttons
	_caption(canvas, "Buttons · gold now · green buys · blue opens · red danger", 40, 300)
	var start = WButton_.make(["START"], 48, WButton_.PRIMARY, 4, 8, 47.0, 40.0, 48.0)
	canvas.add_child(_at(start, 40, 334, 460, 150))
	var buy = WButton_.make([{"coin": 44.0, "fill": W_.PAPER}, "300"], 34, WButton_.PRIMARY, 4, 8, 32.0, 30.0, 34.0, "green")
	canvas.add_child(_at(buy, 540, 334, 230, 106))
	var details = WButton_.make(["DETAILS"], 34, WButton_.UPGRADE, 4, 8, 32.0, 30.0, 34.0, "blue")
	canvas.add_child(_at(details, 800, 334, 240, 106))
	var skip = WButton_.make(["SKIP", {"count": 2}], 34, WButton_.SECONDARY, 4, 8, 32.0, 30.0, 34.0)
	canvas.add_child(_at(skip, 540, 462, 230, 106))
	var abandon = WButton_.make(["ABANDON"], 34, WButton_.DANGER, 4, 8, 32.0, 30.0, 34.0)
	canvas.add_child(_at(abandon, 800, 462, 240, 106))
	var pressed = WButton_.make(["PRESSED"], 24, WButton_.PRIMARY, 4, 8, 16.0, 24.0, 24.0)
	pressed.show_held(true)
	canvas.add_child(_at(pressed, 40, 520, 220, 64))
	var locked = WButton_.make(["LOCKED"], 24, WButton_.SECONDARY, 4, 8, 16.0, 24.0, 24.0)
	locked.locked = true
	canvas.add_child(_at(locked, 280, 520, 220, 64))
	var banish = WButton_.make(["BANISH", {"count": 0}], 24, WButton_.SECONDARY, 4, 8, 16.0, 24.0, 24.0)
	canvas.add_child(_at(banish, 40, 600, 220, 64))
	var buy_small = WButton_.make([{"coin": 30.0, "fill": W_.PAPER}, "40"], 24, WButton_.PRIMARY, 4, 8, 16.0, 24.0, 24.0, "green")
	canvas.add_child(_at(buy_small, 280, 600, 220, 64))
	# item frames at 200: every rarity, evolved, locked, a level plaque; then at 80 with an empty slot
	_caption(canvas, "Item frames · rarity rims · legendary bevel · evolved rainbow", 40, 700)
	var defs: Array = []
	for r in ["common", "uncommon", "rare", "epic", "legendary"]:
		defs.append([_passive_of(r), 1, r.to_upper()])
	var evo = null
	for w in _reg.weapons.values():
		if w.is_evolution and w.icon != null and not w.hidden:
			evo = w
			break
	defs.append([evo, 1, "EVOLVED"])
	var x := 40.0
	var y := 740.0
	for d in defs:
		var p = WPlate_.new()
		if d[0] != null:
			p.for_def(d[0], BIG, false, int(d[1]))
		else:
			p.side = BIG
		p.level_plaque = 1 + defs.find(d)
		canvas.add_child(_at(p, x, y))
		var cap = W_.label(str(d[2]), 18, W_.INK_SOFT)
		canvas.add_child(_at(cap, x, y + BIG + 44.0))
		x += STEP
		if x > 900.0:
			x = 40.0
			y += BIG + 96.0
	# the second row: a level-5 weapon (its level's colour), a weapon with mutation dots, a locked item, a mystery plate
	var weapon = _reg.weapon("boomstick")
	var w5 = WPlate_.new().for_def(weapon, BIG, false, 5)
	w5.set_dots(Vector2i(3, 3), false)
	w5.set_kind_mark_for(weapon)
	w5.level_plaque = 5
	canvas.add_child(_at(w5, x, y))
	canvas.add_child(_at(W_.label("WEAPON LV 5", 18, W_.INK_SOFT), x, y + BIG + 44.0))
	x += STEP
	var lk = WPlate_.new().for_def(_passive_of("rare"), BIG, true, 1)
	canvas.add_child(_at(lk, x, y))
	canvas.add_child(_at(W_.label("LOCKED", 18, W_.INK_SOFT), x, y + BIG + 44.0))
	x += STEP
	var my = WPlate_.new().for_def(weapon, BIG, false, 1)
	my.mystery = true
	canvas.add_child(_at(my, x, y))
	canvas.add_child(_at(W_.label("MYSTERY", 18, W_.INK_SOFT), x, y + BIG + 44.0))
	x += STEP
	var ry = WPlate_.new().for_def(_passive_of("legendary"), BIG, false, 1)
	ry.rays = true
	canvas.add_child(_at(ry, x, y))
	canvas.add_child(_at(W_.label("RAYS", 18, W_.INK_SOFT), x, y + BIG + 44.0))
	# at 80: the HUD's sizes, a plain number plaque, an empty slot and a padlocked one
	y += BIG + 106.0
	x = 40.0
	var small_defs: Array = [[_passive_of("common"), 1, 1], [_passive_of("rare"), 1, 2], [_passive_of("epic"), 1, 3],
		[_passive_of("legendary"), 1, 4], [evo, 1, 0], [weapon, 5, 5]]
	for d in small_defs:
		var p = WPlate_.new()
		if d[0] != null:
			p.for_def(d[0], 80.0, false, int(d[1]))
		else:
			p.side = 80.0
		p.level_plaque = int(d[2])
		canvas.add_child(_at(p, x, y))
		x += 110.0
	var slot_a = WPlate_.slot(80.0)
	slot_a.plate_alpha = 0.5
	canvas.add_child(_at(slot_a, x, y))
	x += 110.0
	var slot_b = WPlate_.slot(80.0, true, 2)
	canvas.add_child(_at(slot_b, x, y))
	x += 110.0
	var buff = WPlate_.new().for_def(_reg.passive("magnet") if _reg.passive("magnet") else _passive_of("common"), 72.0)
	buff.fill = W_.SAGE
	buff.level_text = "6"
	canvas.add_child(_at(buff, x, y))
	# the docked tabs
	var ty := y + 150.0
	_caption(canvas, "Docked tabs · the chosen one gold and taller", 40, ty)
	var tabs = WTabs_.make(["BUILD", "STATS", "OPTIONS"], 30)
	canvas.add_child(_at(tabs, 40, ty + 34, 1000, 80))
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", WTabs_.board().pad(30, 30, 30, 30))
	board.add_child(W_.serif_text("The board under the tabs: a slate sheet with the chosen tab open on it.", 28, W_.INK))
	canvas.add_child(_at(board, 40, ty + 34 + 80, 1000, 110))
	tabs.select(1)
	# review fixes: a tight row (the HUD's 72 px slots 8 px apart) whose glows all sit behind their neighbours, and three
	# creature plates (a boss's red ring and skull, an Elite's crown, a special's gold ring and gear) on slate frames
	var ry2 := ty + 34 + 80 + 110 + 30
	_caption(canvas, "Tight row · glows behind neighbours · creatures", 40, ry2)
	var rowy := ry2 + 28.0
	var rx := 40.0
	var row_defs: Array = [[_passive_of("epic"), 1, 2], [_passive_of("legendary"), 1, 3], [_passive_of("epic"), 1, 4], [evo, 1, 0],
		[_passive_of("common"), 1, 1], [weapon, 5, 5], [_passive_of("legendary"), 1, 2]]
	for d in row_defs:
		var p = WPlate_.new()
		if d[0] != null:
			p.for_def(d[0], 72.0, false, int(d[1]))
		else:
			p.side = 72.0
		p.level_plaque = int(d[2])
		canvas.add_child(_at(p, rx, rowy))
		rx += 80.0
	var slot_c = WPlate_.slot(72.0)
	slot_c.plate_alpha = 0.5
	canvas.add_child(_at(slot_c, rx, rowy))
	rx += 80.0
	var cx := 700.0
	for role in ["boss", "elite", "special"]:
		var e = null
		for cand in _reg.enemies.values():
			if cand.icon != null and not cand.hidden and _danger_role(cand) == role:
				e = cand
				break
		var cp = WPlate_.new()
		if e != null:
			cp.for_def(e, 80.0, false, 1)
		else:
			cp.side = 80.0
			cp.fill = W_.INK
		var ring_col = W_.ROCK if role == "boss" else (W_.EMBER if role == "elite" else W_.BRASS)
		var badge_name := "skull" if role == "boss" else ("crown" if role == "elite" else "gear")
		var bpath := "res://art/ui/badges/%s.png" % badge_name
		cp.badge = load(bpath) if ResourceLoader.exists(bpath) else null
		cp.badge_px = 32.0
		cp.ring = 6
		cp.ring_color = ring_col
		cp.base_ring = cp.ring
		canvas.add_child(_at(cp, cx, rowy - 4.0))
		cx += 112.0
	var vline = W_.serif_text("theme=%s · pass 122 UIKIT_B · page 1" % W_.theme_name(), 22, W_.INK_SOFT)
	canvas.add_child(_at(vline, 40, 1880))


## CollectionScreen.danger_role without naming the class (a --script compiles before the game's classes are reachable
## by name; the same rule: a boss, an Elite, a creature whose badge is the gear).
func _danger_role(e) -> String:
	if e.archetype == "boss":
		return "boss"
	if e.archetype == "elite":
		return "elite"
	if e.has_method("badge_for") and e.badge_for() == "gear":
		return "special"
	return ""


func _page_two(canvas: Control) -> void:
	var WBar_ := _script("WBar")
	var WSlider_ := _script("WSlider")
	var WSwitch_ := _script("WSwitch")
	var WChoice_ := _script("WChoice")
	var WCoin_ := _script("WCoin")
	var WPointer_ := _script("WPointer")
	var WStarLine_ := _script("WStarLine")
	var WSeal_ := _script("WSeal")
	var WStamp_ := _script("WStamp")
	var WNail_ := _script("WNail")
	var WNotches_ := _script("WNotches")
	var WPlaceholder_ := _script("WPlaceholder")
	var WCard_ := _script("WCard")
	var WButton_ := _script("WButton")
	# bars
	_caption(canvas, "Bars · XP · HP · shield · boss · gold with a gain", 40, 30)
	var xp = WBar_.make(0.62, W_.EPIC, 22.0, 2, 0)
	canvas.add_child(_at(xp, 40, 64, 1000, 22))
	var hp = WBar_.make(0.7, W_.SAGE, 26.0, 3, 0)
	canvas.add_child(_at(hp, 40, 100, 480, 26))
	var sh = WBar_.make(0.5, W_.RARE, 20.0, 3, 0)
	canvas.add_child(_at(sh, 560, 100, 480, 20))
	var boss = WBar_.make(0.45, W_.ROCK, 30.0, 4, 4)
	boss.text = "GUARDED"
	boss.text_px = 18
	canvas.add_child(_at(boss, 40, 140, 1000, 30))
	var gold = WBar_.make(0.8, W_.BRASS, 26.0, 4, 0)
	gold.gain = 0.25
	canvas.add_child(_at(gold, 40, 184, 480, 26))
	var loss = WBar_.make(0.6, W_.SAGE, 48.0, 4, 0)
	loss.loss = 0.15
	canvas.add_child(_at(loss, 560, 174, 480, 48))
	# slider, switch, segmented
	_caption(canvas, "Sliders · toggles · segmented choice", 40, 250)
	var sl = WSlider_.make(0.65, 0.0, 1.0)
	canvas.add_child(_at(sl, 40, 300, 600, 36))
	var sl2 = WSlider_.make_levels(0.5, 5)
	canvas.add_child(_at(sl2, 40, 370, 600, 36))
	canvas.add_child(_at(WSwitch_.make(true), 700, 290))
	canvas.add_child(_at(WSwitch_.make(false), 860, 290))
	var choice = WChoice_.make([["Fixed", "north up"], ["Follow", "turns"]], 0, 36, 24, 20.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	canvas.add_child(_at(choice, 660, 370, 380, 120))
	# the modal frame
	_caption(canvas, "Modal · star line · cream title · slate and red buttons", 40, 520)
	var modal := PanelContainer.new()
	modal.add_theme_stylebox_override("panel", W_.box(W_.PAPER, 5, 10).pad(40, 30, 40, 30))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 16)
	modal.add_child(mv)
	mv.add_child(WStarLine_.make("Hold on", 24, W_.INK_SOFT))
	mv.add_child(W_.slab_text("ABANDON THE RUN?", 72, W_.INK, HORIZONTAL_ALIGNMENT_CENTER))
	mv.add_child(W_.serif_text("The purse is kept. The stage is not.", 28, W_.INK, 400, false, HORIZONTAL_ALIGNMENT_CENTER))
	var mb := HBoxContainer.new()
	mb.alignment = BoxContainer.ALIGNMENT_CENTER
	mb.add_theme_constant_override("separation", 30)
	mb.add_child(WButton_.make(["KEEP GOING"], 34, WButton_.SECONDARY, 4, 8, 26.0, 40.0, 34.0))
	mb.add_child(WButton_.make(["ABANDON"], 34, WButton_.DANGER, 4, 8, 26.0, 40.0, 34.0))
	mv.add_child(mb)
	canvas.add_child(_at(modal, 45, 554, 990, 330))
	# coins, pointers, the info plate
	_caption(canvas, "Coins · pointers and info plates on black", 40, 920)
	canvas.add_child(_at(WCoin_.make(60.0), 40, 960))
	canvas.add_child(_at(WCoin_.make(34.0), 120, 972))
	canvas.add_child(_at(WCoin_.make(60.0, W_.AGED), 180, 960))
	var pl = WPointer_.new()
	pl.color = W_.ROCK
	pl.text = "BOSS 43 m"
	pl.side = -1
	canvas.add_child(_at(pl, 0, 1040))
	var pr = WPointer_.new()
	pr.color = W_.SAGE
	pr.text = "PORTAL 24 m"
	pr.side = 1
	canvas.add_child(_at(pr, 1080 - pr.size.x, 1040))
	var pe = WPointer_.new()
	pe.color = W_.EMBER
	pe.text = "ELITE"
	pe.side = 1
	canvas.add_child(_at(pe, 1080 - pe.size.x, 1110))
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", W_.plate_box(5, 6).pad(24, 10, 24, 10))
	var pr_row := HBoxContainer.new()
	pr_row.add_theme_constant_override("separation", 12)
	pr_row.add_child(WCoin_.make(32.0))
	pr_row.add_child(W_.text("312", W_.slab(), 30, R_.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	plate.add_child(pr_row)
	canvas.add_child(_at(plate, 300, 960))
	var lv := PanelContainer.new()
	lv.add_theme_stylebox_override("panel", W_.plate_box(5, 6).pad(24, 10, 24, 10))
	lv.add_child(W_.text("LV 14", W_.slab(), 30, R_.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	canvas.add_child(_at(lv, 480, 960))
	var clock := PanelContainer.new()
	clock.add_theme_stylebox_override("panel", W_.plate_box(5, 6).pad(32, 6, 32, 6))
	clock.add_child(W_.text("04:12", W_.slab(), 50, R_.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0.0))
	canvas.add_child(_at(clock, 640, 950))
	# the small pieces
	_caption(canvas, "Star line · seal · stamp · nail · notches · placeholder", 40, 1180)
	canvas.add_child(_at(WStarLine_.make("Level up", 30, W_.PAPER), 40, 1214, 440, 40))
	canvas.add_child(_at(WSeal_.new().for_rarity("epic", 96.0), 520, 1200))
	var st = WStamp_.make("UNLOCKED", W_.SAGE, 30)
	st.rotation = -0.1
	canvas.add_child(_at(st, 660, 1216))
	canvas.add_child(_at(WNail_.new(), 40, 1284))
	canvas.add_child(_at(WNotches_.make("+6", "+12", 2), 90, 1288))
	canvas.add_child(_at(WPlaceholder_.make("", "a picture", Vector2(240, 100)), 400, 1270))
	# cards: a new passive item, an upgrade with a change row (held)
	_caption(canvas, "Cards · a new passive item · an upgrade, held", 40, 1392)
	var pd = _passive_of("epic")
	var pad: Array = [24, 28, 22, 28]
	var c1 = WCard_.make(pd, {"word": "PASSIVE", "word_color": W_.INK_SOFT, "name": pd.display_name, "stars": [4, 1, -1],
		"effect": "+1.6% damage for every 10% of health missing.",
		"rarity": "", "plate_px": 150.0, "icon_frac": 0.68, "level": 1, "tag": "NEW", "effect_size": 26, "name_size": 48,
		"star_px": 34.0, "pad": pad})
	canvas.add_child(_at(c1, 45, 1426, 990, 200))
	var wd = _reg.weapon("boomstick")
	var c2 = WCard_.make(wd, {"word": "WEAPON", "word_color": W_.WEAPON_INK, "name": wd.display_name, "stars": [5, 3, 4],
		"rarity": "", "plate_px": 150.0, "icon_frac": 0.68, "level": 4, "dots": Vector2i(1, 3), "tag": "UPGRADE",
		"changes": [{"stat": "knockback", "name": "Knockback", "before": "8", "after": "10", "worse": false}],
		"change_size": 26, "name_size": 48, "star_px": 34.0, "pad": pad})
	c2.show_held(true)
	canvas.add_child(_at(c2, 45, 1650, 990, 200))
	var vline = W_.serif_text("theme=%s · pass 122 UIKIT_B · page 2" % W_.theme_name(), 22, W_.INK_SOFT)
	canvas.add_child(_at(vline, 40, 1885))


## Page 3 (pass 123, lane KIT2): the pieces the remaining Royale screens share. The menu header (the slate back square,
## the cream name, the wallet), the black info pills, the price buttons (green buys, blue opens, short of gold), the
## drawn glyphs (the ad icon on GET UP, the menu's three bars), the solid sheet with its cells, the modal shell's card
## (WConfirm's pieces), and the docked tab bar at the foot (STORE locked, the open tab gold and taller).
func _page_three(canvas: Control) -> void:
	var WButton_ := _script("WButton")
	var WMenuHeader_ := _script("WMenuHeader")
	var WConfirm_ := _script("WConfirm")
	var green: Color = R_.ROLES["green"]["top"]
	# the header
	var header = WMenuHeader_.make("", WMenuHeader_.gold_plate(108411, 44, 40.0, 5, 4))
	canvas.add_child(header)
	header.set_title("Upgrade")
	_caption(canvas, "Header · slate back · cream name · black wallet", 40, 186)
	# pills
	_caption(canvas, "Pills · black 56% · white Rubik", 40, 230)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 16)
	pills.add_child(W_.pill([["+1%", green, "bold"], " CRIT per Level"]))
	pills.add_child(W_.pill([{"glyph": "clock", "px": 24}, "7:10 to the boss"]))
	pills.add_child(W_.pill("01:01 · STAGE 1"))
	pills.add_child(W_.pill("TRAIT · LONG ROAD", 20, 40.0))
	canvas.add_child(_at(pills, 40, 262))
	# price buttons
	_caption(canvas, "Price · green buys · blue opens · short", 40, 340)
	var prices := HBoxContainer.new()
	prices.add_theme_constant_override("separation", 24)
	var buy = W_.price_row(300, "BUY", "green")
	buy.get_node("Button").custom_minimum_size.x = 260
	prices.add_child(buy)
	var choose = W_.price_row(100, "CHOOSE", "blue")
	choose.get_node("Button").custom_minimum_size.x = 280
	prices.add_child(choose)
	var short = W_.price_row(190, "BUY", "green", 28, 166)
	short.get_node("Button").custom_minimum_size.x = 200
	prices.add_child(short)
	canvas.add_child(_at(prices, 40, 374))
	# glyphs and the buttons that wear them
	_caption(canvas, "Drawn glyphs · ad · lock · clock · menu · play", 40, 478)
	var glyphs := HBoxContainer.new()
	glyphs.add_theme_constant_override("separation", 26)
	var ink: Color = R_.CREAM
	for k in ["ad", "lock", "clock", "menu", "play"]:
		glyphs.add_child(W_.glyph(k, 48.0, ink))
	canvas.add_child(_at(glyphs, 40, 512))
	var getup = WButton_.make(["GET UP · ", {"ad": 46}], 48, WButton_.PRIMARY, 4, 8, 29.0, 30.0, 48.0)
	canvas.add_child(_at(getup, 460, 500, 400, 106))
	var menu = WButton_.make([{"glyph": "menu", "px": 40}], 40, WButton_.SECONDARY, 4, 8, 24.0, 22.0, 40.0)
	canvas.add_child(_at(menu, 880, 500, 96, 96))
	# the solid sheet and its cells
	_caption(canvas, "Solid sheet · solid cells inside", 40, 650)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", W_.sheet_box(Vector2(24, 20)))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 14)
	sheet.add_child(sv)
	sv.add_child(W_.label("Levels", 18, W_.INK_SOFT))
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 12)
	for t in ["A cell", "on the sheet", "solid", "not see-through"]:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", W_.cell_box())
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(W_.serif_text(t, 24, W_.INK))
		cells.add_child(cell)
	sv.add_child(cells)
	canvas.add_child(_at(sheet, 45, 684, 990, 0))
	# the modal shell's card, laid out flat (WConfirm.shell / open put it over the 80 % dim)
	_caption(canvas, "Modal shell · star line · cream title · body · slate and red", 40, 880)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", WConfirm_.card_box())
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", R_.MODAL_GAP)
	card.add_child(cv)
	cv.add_child(WConfirm_.make_star("Hold on"))
	cv.add_child(WConfirm_.make_title("WIPE THE SAVE?"))
	cv.add_child(WConfirm_.make_body("Gold, unlocks, talents, quests and records: everything goes."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", R_.MODAL_BUTTON_GAP)
	for spec in [["KEEP IT", "slate"], ["WIPE", "red"]]:
		var b = WConfirm_.make_button([spec[0]], spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	cv.add_child(row)
	canvas.add_child(_at(card, 45, 914, 990, 0))
	# the docked tab bar at the foot
	_caption(canvas, "Docked tab bar · STORE locked · the open tab gold", 40, 1560)
	var bar = load("res://ui/wanted/WTabBar.gd").make("battle")
	canvas.add_child(bar)
	var vline = W_.serif_text("theme=%s · pass 123 KIT2 · page 3" % W_.theme_name(), 22, W_.INK_SOFT)
	canvas.add_child(_at(vline, 40, 1600))
