## Down! (Wanted screen 14): a rock dim; "★ 1 CHANCE LEFT ★ / DOWN!"; a paper disc with the count running out (pass 137:
## the number alone, centred; "get up" under it until then); who put the hero down; then GET UP · WATCH AN AD (a
## stand-in: no ads yet) and STAY DOWN (a pop-up asks first,
## the count held meanwhile); pass 77 took "GET UP for 150 gold" off (Garry: "Remove the 'Get up with gold' option"). One chance per run plus the Trail's Extra Life nodes; the hero comes back with
## the revive_hp share of his health (half, more with Second Wind). Under the developer menu's hit log or the player's
## debug mode (pass 46: the Results screen no longer shows it) the last 30 seconds are listed under the count, newest
## first: a row a hit or a pickup heal, with its time before the fall, the badge of what did it (a skull for a boss, a
## crown for an Elite, a gear for a special, a bow for a ranged shot, a heart for a heal; a plain bite wears none), the
## creature's name in its own colour, what it cost or gave back, and a drawn red X on the hit that ended it; a copy
## button and a hold for the count beside it. The free revive lives in the developer menu (free_revive_button).
class_name ReviveScreen
extends WModal

signal decided(kind: String)   # "ad" | "give_up" | "timeout" | "debug" | "replay" (pass 120: a replay's safety net) ("gold" is no longer offered, pass 77)

const SECONDS := 8.0
const GOLD_COST := 150
## The list's colours on its ink panel: a hit's cost, a heal, a shield's share, the X on the hit that ended it.
const HIT_RED := Color("ec6a4c")
const HEAL_GREEN := Color("7fe07f")
const SHIELD_BLUE := Color("8cc4ff")
const X_RED := Color("ff3b2b")
## Which badge a row wears, by its role first (boss, elite, special), then by its kind (ranged, heal):
## art/ui/badges/<name>.png (bow and heart are painted in pass 46; a badge not painted yet shows nothing).
const BADGES := {"boss": "skull", "elite": "crown", "special": "gear", "ranged": "bow", "heal": "heart"}

static var _badges: Dictionary = {}

var _disc: Control
var _count: WText
var _killer_row: HBoxContainer
var _killer_icon: TextureRect
var _killer: WText
var _stats: WText
var _gold_row: HBoxContainer
var _gold_coin: WCoin
var _gold_line: WText
var _hold_btn2: WButton
var _ad_btn: WButton
var _quit_btn: WButton
var _debug_btn2: WButton
var _log_panel: PanelContainer
var _list: VBoxContainer
var _log_scroll: ScrollContainer
var _copy_btn: WButton
var _hold_btn: WButton
var _log_text := ""
var _t := 0.0
var _open := false
var _held := false
var _asking := false   # the stay-down question is up: the count holds, the log does not scroll
var _touch: TouchScroll
## Pass 123 (lane RUN_A): the theme the screen was built in (a flip of the debug switch builds it again on the next
## open), and the Royale pieces: the block under the disc (moved with it), the run pills' row.
var _who: VBoxContainer
var _pills: HBoxContainer

## Pass 123 (lane RUN_A), the Royale look (the mock 10_Down; Garry: "Down! as the mock: red dim, cream countdown disc, who
## put you down, run pills, GET UP in gold, STAY DOWN in red", "Header white", "Keep the GET UP · WATCH AN AD label ...
## instead of text let's use an icon. An icon that's usually used for ads buttons", the hit log debug-only as today):
## the header's top and title size, the disc (its radius with the ring, the ring, the drop under it, the face's light
## and edge colours, the warm glow round it), the count (and "get up" until pass 137), where the disc's centre stands with the hit log
## shown (the mock's) and without it, the gap from the disc to the line under it, the log's top.
const ROYALE_HEAD_TOP := 56.0
const ROYALE_TITLE_PX := 132
const ROYALE_DISC_R := 248.0
const ROYALE_RING := 10.0
const ROYALE_DROP := 12.0
const ROYALE_FACE_LIGHT := Color("fffaea")
const ROYALE_FACE_EDGE := Color("f2dfb4")
const ROYALE_GLOW := Color(1.0, 0.55, 0.25, 0.42)
const ROYALE_GLOW_R := 360.0
const ROYALE_COUNT_PX := 220
## Pass 137 (lane POLISH): how far the count's line sits above the disc's centre so its digits' ink is centred on it
## ("get up" under it is gone). Measured on a 1080 x 1920 capture: the 8's ink spans 720-883 px on a disc centred at 800,
## 1.5 px off, so none.
const ROYALE_COUNT_LIFT := 0.0
const ROYALE_DISC_Y_LOG := 548.0
const ROYALE_DISC_Y := 800.0
const ROYALE_WHO_GAP := 44.0
const ROYALE_LOG_TOP := 1010.0
## The ad icon's height on GET UP (W.glyph "ad", lane KIT2).
const ROYALE_AD_PX := 46.0
## The log's thin line between rows and the fatal row's fill on the slate.
const ROYALE_RULE := Color(1, 1, 1, 0.1)
const ROYALE_FATAL_FILL := Color(0.89, 0.25, 0.18, 0.22)

static var _glow_tex: GradientTexture2D
static var _face_tex: GradientTexture2D
static var _face_pts := PackedVector2Array()
static var _face_uvs := PackedVector2Array()


func _ready() -> void:
	_build()


## The screen's standing parts (pass 123: out of _ready, so a theme flip can build them again).
func _build() -> void:
	_build_royale()
	return


## Pass 123 (lane RUN_A): Down! under Royale (the mock 10_Down): the red dim; "★ 1 CHANCE LEFT ★" in gold over DOWN! in
## cream with the navy edge (Garry: "Header white"); the cream disc in a navy ring on a navy drop, a warm glow round it,
## the count in navy (pass 137: alone, centred); who put the hero down; the run's time, kills and level as black pills; the
## gold line; the hit log (debug only, as today) as a slate panel with its rows on thin lines; GET UP with the drawn ad
## icon in gold ("GET UP · [ad]"), STAY DOWN in red; the developer's buttons as today. The same nodes and names.
func _build_royale() -> void:
	build_dim(W.DIM_DOWN)
	build_header(Loc.t("ui.revive.star"), Loc.t("ui.revive.title"), "", ROYALE_TITLE_PX, W.PAPER, ROYALE_HEAD_TOP)
	header.line.visible = false
	_disc = Control.new()
	_disc.name = "Disc"
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.size = Vector2(540, 540)
	_disc.draw.connect(_draw_royale_disc)
	add_child(_disc)
	# pass 137 (lane POLISH; Garry: "The count down number isn't centered because of the 'Get Up' text. Remove the text and
	# center the number"): no "get up" under it; the count's line centred on the disc's centre (270, 270), less
	# ROYALE_COUNT_LIFT for the font's own ink centre
	_count = W.text("8", R.display(), ROYALE_COUNT_PX, R.NAVY, HORIZONTAL_ALIGNMENT_CENTER, float(ROYALE_COUNT_PX))
	R.no_edge(_count)
	_count.name = "Count"
	_count.position = Vector2(0, 270.0 - float(ROYALE_COUNT_PX) * 0.5 - ROYALE_COUNT_LIFT)
	_count.size = Vector2(540, float(ROYALE_COUNT_PX))
	_disc.add_child(_count)
	# who did it, the run's pills, the gold line: under the disc, moved with it (open)
	_who = VBoxContainer.new()
	_who.name = "Who"
	_who.add_theme_constant_override("separation", 16)
	_who.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_who.offset_top = 1060
	_who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_who)
	_killer_row = HBoxContainer.new()
	_killer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_killer_row.add_theme_constant_override("separation", 16)
	_killer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who.add_child(_killer_row)
	_killer_icon = TextureRect.new()
	_killer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_killer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_killer_icon.custom_minimum_size = Vector2(44, 44)
	_killer_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_killer_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_killer_row.add_child(_killer_icon)
	_killer = W.slab_text("", 34, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_killer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_killer_row.add_child(_killer)
	_pills = HBoxContainer.new()
	_pills.name = "RunPills"
	_pills.alignment = BoxContainer.ALIGNMENT_CENTER
	_pills.add_theme_constant_override("separation", 12)
	_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who.add_child(_pills)
	_gold_row = HBoxContainer.new()
	_gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gold_row.add_theme_constant_override("separation", 8)
	_gold_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who.add_child(_gold_row)
	var pre := W.serif_text(Loc.t("ui.revive.gold_pre"), 26, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	pre.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_row.add_child(pre)
	_gold_coin = WCoin.make(28)
	_gold_row.add_child(_gold_coin)
	_gold_line = W.serif_text("", 26, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_gold_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_row.add_child(_gold_line)
	# the last 30 seconds (debug only): a slate panel from ROYALE_LOG_TOP down to just above the buttons
	_log_panel = PanelContainer.new()
	_log_panel.name = "HitLog"
	_log_panel.add_theme_stylebox_override("panel", W.sheet_box(Vector2(18, 14)))
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_panel.offset_left = 48
	_log_panel.offset_right = -48
	_log_panel.offset_top = ROYALE_LOG_TOP
	_log_panel.offset_bottom = -90 - 110 - 24 - 106 - 24 - R.PANEL_BASE
	add_child(_log_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	_log_panel.add_child(lv)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 12)
	lv.add_child(lh)
	var lt := W.label("The last 30 seconds · newest first", 20, W.INK_SOFT, 0.14)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(lt)
	_hold_btn = WButton.make(["HOLD"], 22, WButton.SECONDARY, 3, 4, 6.0, 16.0)
	_hold_btn.pressed.connect(_toggle_hold)
	lh.add_child(_hold_btn)
	_copy_btn = WButton.make(["COPY"], 22, WButton.SECONDARY, 3, 4, 6.0, 16.0, 0.0, WButton.BLUE)
	_copy_btn.pressed.connect(_copy)
	lh.add_child(_copy_btn)
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(_log_scroll)
	_list = VBoxContainer.new()
	_list.name = "HitList"
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_scroll.add_child(_list)
	_touch = TouchScroll.new(_log_scroll, true)
	# the ways up: an ad (gold, the drawn ad icon in place of the words) or staying down (red)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 48
	col.offset_right = -48
	col.offset_bottom = -90
	col.offset_top = -90 - 110 - 24 - 106
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_ad_btn = WButton.make([Loc.t("ui.revive.get_up") + " ", {"ad": ROYALE_AD_PX}], 48, WButton.PRIMARY, 4, 8, 29.0, 30.0, 48.0)
	_ad_btn.name = "GetUp"
	_ad_btn.pressed.connect(func(): _try("ad"))
	col.add_child(_ad_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_quit_btn = WButton.make([Loc.t("ui.revive.stay_down")], 34, WButton.DANGER, 5, 8, 26.0, 0.0)
	_quit_btn.name = "StayDown"
	_quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quit_btn.pressed.connect(_ask_give_up)
	row.add_child(_quit_btn)
	_build_debug_buttons()


## The developer's buttons (both themes): the free revive top right ("Free revive button"), the count held top left.
func _build_debug_buttons() -> void:
	# pass 124 (Garry: "Revive button disappeared from the down screen in debug mode"): slate at 70% on the dark top of the
	# screen, up where a phone's status bar and cutout sit. A solid green button, under the cutout (open() places it)
	_debug_btn2 = WButton.make(["REVIVE"], 28, WButton.PRIMARY, 3, 4, 10.0, 16.0, 28.0, WButton.GREEN)
	_debug_btn2.name = "DebugRevive"
	_debug_btn2.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_btn2.offset_left = -220
	_debug_btn2.offset_right = -24
	_debug_btn2.pressed.connect(func(): _decide("debug"))
	add_child(_debug_btn2)
	_hold_btn2 = WButton.make(["hold time"], 20, WButton.SECONDARY, 3, 0, 6.0, 12.0)
	_hold_btn2.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hold_btn2.offset_left = 24
	_hold_btn2.offset_right = 220
	_hold_btn2.name = "DebugHold"
	_hold_btn2.pressed.connect(func():
		_toggle_hold()
		_hold_btn2.set_parts(["go on" if _held else "hold time"]))
	add_child(_hold_btn2)


## The Royale disc (pass 123): a warm glow round it, a navy drop under it, the navy ring, the cream face lit from the
## top left. Drawn only when it redraws (no work a frame).
func _draw_royale_disc() -> void:
	var c := Vector2(270, 270)
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, ROYALE_GLOW)
		g.set_color(1, Color(ROYALE_GLOW.r, ROYALE_GLOW.g, ROYALE_GLOW.b, 0.0))
		g.add_point(0.62, Color(ROYALE_GLOW.r, ROYALE_GLOW.g, ROYALE_GLOW.b, ROYALE_GLOW.a * 0.8))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 256
		_glow_tex.height = 256
	_disc.draw_texture_rect(_glow_tex, Rect2(c - Vector2.ONE * ROYALE_GLOW_R, Vector2.ONE * ROYALE_GLOW_R * 2.0), false)
	_disc.draw_circle(c + Vector2(0, ROYALE_DROP), ROYALE_DISC_R, R.NAVY, true, -1.0, true)
	_disc.draw_circle(c, ROYALE_DISC_R, R.NAVY, true, -1.0, true)
	var face := ROYALE_DISC_R - ROYALE_RING
	# the face: a radial gradient, light in the middle to a warmer cream at the ring (the mock's radial fill), as one
	# textured polygon (its points and the gradient made once)
	if _face_tex == null:
		var fg := Gradient.new()
		fg.set_color(0, ROYALE_FACE_LIGHT)
		fg.set_color(1, ROYALE_FACE_EDGE)
		_face_tex = GradientTexture2D.new()
		_face_tex.gradient = fg
		_face_tex.fill = GradientTexture2D.FILL_RADIAL
		_face_tex.fill_from = Vector2(0.5, 0.42)
		_face_tex.fill_to = Vector2(1.0, 0.5)
		_face_tex.width = 128
		_face_tex.height = 128
	if _face_pts.is_empty():
		for k in 72:
			var a := TAU * float(k) / 72.0
			var d := Vector2(cos(a), sin(a))
			_face_pts.append(c + d * face)
			_face_uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	_disc.draw_circle(c, face, ROYALE_FACE_EDGE, true, -1.0, true)
	_disc.draw_colored_polygon(_face_pts, Color.WHITE, _face_uvs, _face_tex)




## A button's word in the theme (capitals under Royale).
func _word(t: String) -> String:
	return t.to_upper()


## `gold` is the run's gold, `chances` how many revives are left (0 leaves only staying down), `killer` the hit that
## ended it ({by, kind, role, colour}) for the line under the count, `rows` the hero's last 30 s (Player.damage_log,
## oldest first) for the list, and `log_text` the same as text for the copy button (Player.damage_log_text). An older
## caller that passes only the text sees it in the panel as it is.
func open(gold: int, chances: int, log_text: String = "", killer: Dictionary = {}, rows: Array = []) -> void:
	_t = 0.0
	_open = true
	_held = false
	_asking = false
	var can := chances > 0
	header.star_line.get_child(1).text = Loc.t("ui.revive.chances_left", {"count": "%d" % chances}) if can else Loc.t("ui.revive.no_chances")
	_ad_btn.locked = not can
	_count.text = str(int(ceil(SECONDS)))
	if killer.is_empty():
		killer = fatal_row(rows)
	var by := str(killer.get("by", ""))
	if by != "":
		_killer.runs = [[by, name_colour(killer, W.PAPER)], [" " + Loc.t("ui.revive.put_you_down"), null]]
	else:
		_killer.runs = []
		_killer.text = Loc.t("ui.revive.something")
	_killer_icon.texture = badge_for(killer) if by != "" else null
	_killer_icon.visible = _killer_icon.texture != null
	if _pills:
		# pass 123: the run's time, kills and level as black pills (built again each open: once a fall, never a frame)
		for c in _pills.get_children():
			_pills.remove_child(c)
			c.queue_free()
		for t in [W.mmss(Run.stage_clock()), Loc.t("ui.revive.kills", {"kills": W.num(Run.kills)}), W.lv(Run.level)]:
			_pills.add_child(W.pill([[str(t), null, "bold"]]))
	else:
		_stats.text = Loc.t("ui.revive.stats", {"time": W.mmss(Run.stage_clock()), "kills": W.num(Run.kills), "level": W.lv(Run.level)})
	_gold_line.text = Loc.t("ui.revive.gold_line", {"gold": W.num(gold)})
	_gold_row.visible = gold > 0
	var s := W.node("Settings")
	_log_panel.visible = s != null and (bool(s.get("hit_log")) or bool(s.get("debug_mode")))
	var debug: bool = s != null and (bool(s.get("free_revive_button")) or bool(s.get("debug_mode")))
	_debug_btn2.visible = debug
	_hold_btn2.visible = debug
	var top := 24.0 + W.safe_top()
	for b: WButton in [_debug_btn2, _hold_btn2]:
		b.offset_top = top
		b.offset_bottom = top + 72.0
	_hold_btn2.set_parts(["hold time"])
	_log_text = log_text if log_text != "" else Player.log_text(rows)
	if _log_panel.visible:
		_fill_list(rows)
	_log_scroll.scroll_vertical = 0
	var vp := get_viewport_rect().size
	_disc.position = Vector2((vp.x - 540.0) * 0.5, 470)
	# pass 123: the disc where the mock has it while the log shows, lower when it does not; the line under it follows
	var cy := (ROYALE_DISC_Y_LOG if _log_panel.visible else ROYALE_DISC_Y) + W.safe_top()
	_disc.position = Vector2((vp.x - 540.0) * 0.5, cy - 270.0)
	_who.offset_top = cy + ROYALE_DISC_R + ROYALE_DROP + ROYALE_WHO_GAP
	modulate.a = 1.0
	enter()
	Audio.play("ui_pause")


## The hit that ended it (the row marked fatal), else the newest hit; {} for none.
static func fatal_row(rows: Array) -> Dictionary:
	var last: Dictionary = {}
	for e: Dictionary in rows:
		if bool(e.get("fatal", false)):
			return e
		if str(e.get("kind", "")) != "heal":
			last = e
	return last


## The badge a row (or the killer line) wears: its role's (a skull for a boss, a crown for an Elite, a gear for a
## special), else a bow for a ranged shot and a heart for a heal; a plain bite wears none. Null while the picture is
## not painted yet.
static func badge_for(row: Dictionary) -> Texture2D:
	var role := str(row.get("role", ""))
	var key := role if BADGES.has(role) else str(row.get("kind", ""))
	if not BADGES.has(key):
		return null
	var file := str(BADGES[key])
	if not _badges.has(file):
		var path := "res://art/ui/badges/%s.png" % file
		_badges[file] = load(path) if ResourceLoader.exists(path) else null
	return _badges[file]


## A row's name colour: the creature's own (an elite modifier's outline, a coloured special's tint), lifted until it
## reads on the dark panel; `plain` when it has none.
static func name_colour(row: Dictionary, plain: Color) -> Color:
	var hex := str(row.get("colour", ""))
	if hex == "" or not Color.html_is_valid(hex):
		return plain
	return readable(Color.html(hex))


## A colour mixed towards white until its luminance reaches `floor_l`, its hue kept (a special's tint is dark).
static func readable(c: Color, floor_l: float = 0.45) -> Color:
	var l := c.get_luminance()
	if l >= floor_l:
		return Color(c.r, c.g, c.b, 1.0)
	var out := c.lerp(Color.WHITE, clampf((floor_l - l) / maxf(1.0 - l, 0.01), 0.0, 1.0))
	out.a = 1.0
	return out


## "−3.2 s" before the fall; the fall itself is "0.0 s".
static func ago(dt: float) -> String:
	return "0.0 s" if dt < 0.05 else "−%.1f s" % dt


## The list, newest first. With no rows it shows the text it was given (an older caller's log), or a line saying
## nothing came near. Old rows go at once (a queued free still counts as a child this frame).
func _fill_list(rows: Array) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if rows.is_empty():
		var msg := W.text(_log_text, R.body(R.BODY_WEIGHT), 22, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 30.0, true)
		msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(msg)
		return
	# the times count back from the fall (the fatal hit), else from the newest row
	var t_ref := float((rows.back() as Dictionary).get("t", 0.0))
	var fatal := fatal_row(rows)
	if bool(fatal.get("fatal", false)):
		t_ref = float(fatal.get("t", t_ref))
	for k in range(rows.size() - 1, -1, -1):
		_list.add_child(_row(rows[k], t_ref))


## One row: the X (the hit that ended it), how long before the fall, the badge, the name in its colour with what the
## hit carried under it, what it cost or gave back, and the health left after it.
func _row(e: Dictionary, t_ref: float) -> PanelContainer:
	var fatal := bool(e.get("fatal", false))
	var heal := str(e.get("kind", "")) == "heal"
	var row := PanelContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("fatal", fatal)
	var box := W.box(Color(W.ROCK, 0.38) if fatal else Color(0, 0, 0, 0), 3 if fatal else 1).pad(8, 8, 12, 8)
	box.border_color = X_RED if fatal else Color(W.AGED, 0.16)
	if not fatal:
		box.sides = [false, false, false, true]
	# pass 123: the rows on thin light lines on the slate, the killing hit on a red band in a red edge (the mock's)
	box = W.box(ROYALE_FATAL_FILL if fatal else Color(0, 0, 0, 0), 3 if fatal else 2, 0, R.RADIUS_TAG if fatal else 0)
	box.pad(8, 10, 12, 10)
	box.border_color = R.TAG_RED if fatal else ROYALE_RULE
	if not fatal:
		box.sides = [false, false, false, true]
	box.themed = false
	row.add_theme_stylebox_override("panel", box)
	# pass 123: the Royale log's faces (Rubik, Ultra for the amount) and colours (the kit's red, green, blue, secondary)
	var mono := R.body(R.BODY_WEIGHT)
	var soft := R.SECONDARY
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	# the X: two strokes of red, drawn (no font has one that reads at this size)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(30, 30)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fatal:
		mark.name = "FatalX"
		mark.draw.connect(func():
			var s := mark.size
			mark.draw_line(Vector2(3, 3), s - Vector2(3, 3), X_RED, 6.0, true)
			mark.draw_line(Vector2(s.x - 3, 3), Vector2(3, s.y - 3), X_RED, 6.0, true))
	h.add_child(mark)
	var when := W.text(ago(maxf(t_ref - float(e.get("t", t_ref)), 0.0)), mono, 22, soft, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	when.name = "When"
	when.custom_minimum_size.x = 100
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(when)
	var badge := TextureRect.new()
	badge.name = "Badge"
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(40, 40)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.texture = badge_for(e)
	h.add_child(badge)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(who)
	var nm := W.serif_text(str(e.get("by", "something")), 26, name_colour(e, W.PAPER), 600, false, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	nm.name = "Name"
	nm.max_lines = 1
	who.add_child(nm)
	var notes: Array = (e.get("fx", []) as Array).duplicate()
	if str(e.get("note", "")) == "broke":
		notes.append("the shield broke")
	if not notes.is_empty():
		var fx := W.serif_text(", ".join(PackedStringArray(notes)), 20, Color(soft, 0.8), 400, true, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
		fx.name = "Carried"
		who.add_child(fx)
	var what := ""
	var tone := HIT_RED
	match str(e.get("note", "")):
		"evaded":
			what = "evaded"
			tone = W.AGED
		"power-up", "bible":
			# pass 119 (lane LEGEND_B): the Pocket Bible's block reads as blocked too
			what = "blocked"
			tone = SHIELD_BLUE
		"shield", "broke":
			what = "−%d shield" % roundi(float(e.get("shield", 0.0)))
			tone = SHIELD_BLUE
		_:
			if heal:
				what = "+%d" % roundi(float(e.get("amount", 0.0)))
				tone = HEAL_GREEN
			else:
				what = "−%d" % roundi(float(e.get("dealt", 0.0)))
	var amount := W.text(what, W.mono(700), 24, tone, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	var rt: Color = R.ROLES["red"]["top"]
	if tone == W.AGED:
		rt = R.SECONDARY
	elif tone == SHIELD_BLUE:
		rt = R.ROLES["blue"]["top"]
	elif tone == HEAL_GREEN:
		rt = R.ROLES["green"]["top"]
	amount = W.text(what, R.display(), 28, rt, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	R.edge(amount, 28)
	amount.name = "Amount"
	amount.custom_minimum_size.x = 150
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(amount)
	var left := W.text("%d left" % roundi(float(e.get("hp", 0.0))), mono, 20, Color(soft, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	left.name = "Left"
	left.custom_minimum_size.x = 104
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(left)
	return row


## A revive that is not on offer (no chance left) says so instead of acting.
func _try(kind: String) -> void:
	if kind != "ad" or _ad_btn.locked:
		Audio.play("ui_locked")
		return
	_decide(kind)


func _toggle_hold() -> void:
	RunReplay.note("revive_hold")
	_held = not _held
	_hold_btn.set_parts([_word("go on" if _held else "hold")])
	_count.modulate.a = 0.45 if _held else 1.0


func _copy() -> void:
	DisplayServer.clipboard_set(W.GAME_NAME + " · the last 30 seconds before going down, newest first\n" + _log_text)
	_copy_btn.set_parts([_word("copied")])
	get_tree().create_timer(1.4, true).timeout.connect(func(): if is_instance_valid(_copy_btn): _copy_btn.set_parts([_word("copy")]))


## Touch drags on the list scroll it (a drag that starts on a row never reaches a ScrollContainer on a phone).
func _input(event: InputEvent) -> void:
	if _open and _touch and _log_panel.visible and not _asking:
		_touch.input(event)


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if not _open:
		return
	if _touch:
		_touch.process()
	if not _held and not _asking:
		_t += delta
	var left: float = maxf(SECONDS - _t, 0.0)
	var n := int(ceil(left))
	if _count.text != str(n):
		_count.text = str(n)
		_count.pivot_offset = _count.size * 0.5
		var tw := create_tween()
		_count.scale = Vector2(1.15, 1.15)
		tw.tween_property(_count, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if n <= 3:
			Audio.play("ui_tap")
	if left <= 0.0:
		# pass 120 (lane REPLAY): in a replay the count ends the run only where the recording ends too (RunReplay.down_ran_out)
		if RunReplay.down_ran_out(self) == "timeout":
			_decide("timeout")


## Staying down ends the run (pass 45): the question, with the count held while it is up.
func _ask_give_up() -> void:
	if not _open or _asking:
		return
	_asking = true
	var gold := Run.run_gold
	WConfirm.open(self, Loc.t("ui.revive.confirm.title"),
		Loc.t("ui.revive.confirm.body_gold", {"gold": W.num(gold)}) if gold > 0 else Loc.t("ui.revive.confirm.body"),
		Loc.t("ui.revive.confirm.yes"), Loc.t("ui.revive.confirm.no"),
		func():
			_asking = false
			_decide("give_up"),
		func(): _asking = false)


func _decide(kind: String) -> void:
	if not _open:
		return
	if kind != "timeout":
		RunReplay.note("revive", {"kind": kind})
	_open = false
	if _touch:
		_touch.reset()
	visible = false
	decided.emit(kind)
