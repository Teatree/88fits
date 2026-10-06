## Down! (Wanted screen 14): a rock dim; "★ 1 CHANCE LEFT ★ / DOWN!"; a paper disc with the count running out and "get
## up"; who put the hero down; then GET UP · WATCH AN AD (a stand-in: no ads yet), GET UP for 150 gold, STAY DOWN (a
## pop-up asks first, the count held meanwhile). One chance per run plus the Upgrade board's; the hero comes back with
## the revive_hp share of his health (half, more with Second Wind). Under the developer menu's hit log or the player's
## debug mode (pass 46: the Results screen no longer shows it) the last 30 seconds are listed under the count, newest
## first: a row a hit or a pickup heal, with its time before the fall, the badge of what did it (a skull for a boss, a
## crown for an Elite, a gear for a special, a bow for a ranged shot, a heart for a heal; a plain bite wears none), the
## creature's name in its own colour, what it cost or gave back, and a drawn red X on the hit that ended it; a copy
## button and a hold for the count beside it. The free revive lives in the developer menu (free_revive_button).
class_name ReviveScreen
extends WModal

signal decided(kind: String)   # "ad" | "gold" | "give_up" | "timeout" | "debug"

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
## Where the list's panel starts; its bottom keeps 24 px above the buttons, so a taller phone shows more rows.
const LOG_TOP := 1210.0

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
var _gold_btn: WButton
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


func _ready() -> void:
	build_dim(W.DIM_DOWN)
	build_header("1 chance left", "DOWN!", "", 170)
	header.line.visible = false
	# the disc: 520 px of paper in a 10 px ink ring with a 14 px shadow, the count in 300 px slab
	_disc = Control.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.size = Vector2(540, 540)
	_disc.draw.connect(func():
		var c := Vector2(270, 270)
		_disc.draw_circle(c + Vector2(14, 14), 270, W.INK, true, -1.0, true)
		_disc.draw_circle(c, 270, W.INK, true, -1.0, true)
		_disc.draw_circle(c, 260, W.PAPER, true, -1.0, true))
	add_child(_disc)
	_count = W.slab_text("8", 300, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 270.0)
	_count.position = Vector2(0, 110)
	_count.size = Vector2(540, 270)
	_disc.add_child(_count)
	var gu := W.serif_text("get up", 30, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	gu.position = Vector2(0, 382)
	gu.size = Vector2(540, 40)
	_disc.add_child(gu)
	# who did it
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	who.offset_top = 1060
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(who)
	_killer_row = HBoxContainer.new()
	_killer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_killer_row.add_theme_constant_override("separation", 16)
	_killer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(_killer_row)
	_killer_icon = TextureRect.new()
	_killer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_killer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_killer_icon.custom_minimum_size = Vector2(44, 44)
	_killer_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_killer_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_killer_row.add_child(_killer_icon)
	_killer = W.slab_text("", 34, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_killer.shadow = 3
	_killer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_killer_row.add_child(_killer)
	_stats = W.serif_text("", 26, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	who.add_child(_stats)
	# what staying down costs (pass 44): the run's gold does not come home with a dead hero; the coin beside it (pass 46)
	_gold_row = HBoxContainer.new()
	_gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gold_row.add_theme_constant_override("separation", 8)
	_gold_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(_gold_row)
	var pre := W.serif_text("Stay down and the", 26, W.PAPER, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	pre.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_row.add_child(pre)
	_gold_coin = WCoin.make(28)
	_gold_row.add_child(_gold_coin)
	_gold_line = W.serif_text("", 26, W.PAPER, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_gold_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_row.add_child(_gold_line)
	# the last 30 seconds: a dark panel under the line, from LOG_TOP down to just above the buttons
	_log_panel = PanelContainer.new()
	_log_panel.name = "HitLog"
	_log_panel.add_theme_stylebox_override("panel", W.box(W.INK, 4, 0).pad(20, 16, 20, 16))
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_panel.offset_left = 48
	_log_panel.offset_right = -48
	_log_panel.offset_top = LOG_TOP
	_log_panel.offset_bottom = -90 - 110 - 24 - 106 - 24
	add_child(_log_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	_log_panel.add_child(lv)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 12)
	lv.add_child(lh)
	var lt := W.text("THE LAST 30 SECONDS · NEWEST FIRST", W.mono(500), 20, W.AGED, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(lt)
	_hold_btn = WButton.make(["hold"], 20, WButton.SECONDARY, 3, 0, 4.0, 12.0)
	_hold_btn.pressed.connect(_toggle_hold)
	lh.add_child(_hold_btn)
	_copy_btn = WButton.make(["copy"], 20, WButton.SECONDARY, 3, 0, 4.0, 12.0)
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
	# the ways up: an ad (full width), gold, or staying down
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 48
	col.offset_right = -48
	col.offset_bottom = -90
	col.offset_top = -90 - 110 - 24 - 106
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_ad_btn = WButton.make(["GET UP · WATCH AN AD"], 44, WButton.PRIMARY, 5, 8, 28.0, 0.0)
	_ad_btn.pressed.connect(func(): _try("ad"))
	col.add_child(_ad_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_gold_btn = WButton.make(["GET UP ", {"coin": 34}, ["%d" % GOLD_COST, null]], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	_gold_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_btn.size_flags_stretch_ratio = 1.4
	_gold_btn.pressed.connect(func(): _try("gold"))
	row.add_child(_gold_btn)
	_quit_btn = WButton.make(["STAY DOWN"], 34, WButton.DANGER, 5, 8, 26.0, 0.0)
	_quit_btn.name = "StayDown"
	_quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quit_btn.pressed.connect(_ask_give_up)
	row.add_child(_quit_btn)
	# the developer's free revive (developer menu: "Free revive button"), top right
	_debug_btn2 = WButton.make(["free revive"], 20, WButton.SECONDARY, 3, 0, 6.0, 12.0)
	_debug_btn2.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_btn2.offset_left = -220
	_debug_btn2.offset_right = -24
	_debug_btn2.offset_top = 24
	_debug_btn2.offset_bottom = 74
	_debug_btn2.modulate.a = 0.7
	_debug_btn2.pressed.connect(func(): _decide("debug"))
	add_child(_debug_btn2)
	# the player's debug mode (pass 44): the count held, top left, beside the free respawn
	_hold_btn2 = WButton.make(["hold time"], 20, WButton.SECONDARY, 3, 0, 6.0, 12.0)
	_hold_btn2.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hold_btn2.offset_left = 24
	_hold_btn2.offset_right = 220
	_hold_btn2.offset_top = 24
	_hold_btn2.offset_bottom = 74
	_hold_btn2.modulate.a = 0.7
	_hold_btn2.pressed.connect(func():
		_toggle_hold()
		_hold_btn2.set_parts(["go on" if _held else "hold time"]))
	add_child(_hold_btn2)


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
	header.star_line.get_child(1).text = ("%d CHANCE%s LEFT" % [chances, "" if chances == 1 else "S"]) if can else "NO CHANCES LEFT"
	_ad_btn.locked = not can
	_gold_btn.locked = not can or gold < GOLD_COST
	_count.text = str(int(ceil(SECONDS)))
	if killer.is_empty():
		killer = fatal_row(rows)
	var by := str(killer.get("by", ""))
	if by != "":
		_killer.runs = [[by, name_colour(killer, W.PAPER)], [" put you down.", null]]
	else:
		_killer.runs = []
		_killer.text = "Something put you down."
	_killer_icon.texture = badge_for(killer) if by != "" else null
	_killer_icon.visible = _killer_icon.texture != null
	_stats.text = "%s · %s kills · %s" % [W.mmss(Run.elapsed), W.num(Run.kills), W.lv(Run.level)]
	_gold_line.text = "%s gold stays in the sand." % W.num(gold)
	_gold_row.visible = gold > 0
	var s := W.node("Settings")
	_log_panel.visible = s != null and (bool(s.get("hit_log")) or bool(s.get("debug_mode")))
	var debug: bool = s != null and (bool(s.get("free_revive_button")) or bool(s.get("debug_mode")))
	_debug_btn2.visible = debug
	_debug_btn2.set_parts(["respawn"])
	_hold_btn2.visible = debug
	_hold_btn2.set_parts(["hold time"])
	_log_text = log_text if log_text != "" else Player.log_text(rows)
	if _log_panel.visible:
		_fill_list(rows)
	_log_scroll.scroll_vertical = 0
	var vp := get_viewport_rect().size
	_disc.position = Vector2((vp.x - 540.0) * 0.5, 470)
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
		var msg := W.text(_log_text, W.mono(500), 22, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 30.0, true)
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
	row.add_theme_stylebox_override("panel", box)
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
	var when := W.text(ago(maxf(t_ref - float(e.get("t", t_ref)), 0.0)), W.mono(500), 22, W.AGED, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
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
		var fx := W.serif_text(", ".join(PackedStringArray(notes)), 20, Color(W.AGED, 0.8), 400, true, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
		fx.name = "Carried"
		who.add_child(fx)
	var what := ""
	var tone := HIT_RED
	match str(e.get("note", "")):
		"evaded":
			what = "evaded"
			tone = W.AGED
		"power-up":
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
	amount.name = "Amount"
	amount.custom_minimum_size.x = 150
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(amount)
	var left := W.text("%d left" % roundi(float(e.get("hp", 0.0))), W.mono(500), 20, Color(W.AGED, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	left.name = "Left"
	left.custom_minimum_size.x = 104
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(left)
	return row


## A revive that is not on offer (spent, or short of gold) says so instead of acting.
func _try(kind: String) -> void:
	var b := _ad_btn if kind == "ad" else _gold_btn
	if b.locked:
		Audio.play("ui_locked")
		return
	_decide(kind)


func _toggle_hold() -> void:
	_held = not _held
	_hold_btn.set_parts(["go on" if _held else "hold"])
	_count.modulate.a = 0.45 if _held else 1.0


func _copy() -> void:
	DisplayServer.clipboard_set("88fits · the last 30 seconds before going down, newest first\n" + _log_text)
	_copy_btn.set_parts(["copied"])
	get_tree().create_timer(1.4, true).timeout.connect(func(): if is_instance_valid(_copy_btn): _copy_btn.set_parts(["copy"]))


## Touch drags on the list scroll it (a drag that starts on a row never reaches a ScrollContainer on a phone).
func _input(event: InputEvent) -> void:
	if _open and _touch and _log_panel.visible and not _asking:
		_touch.input(event)


func _process(delta: float) -> void:
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
		_decide("timeout")


## Staying down ends the run (pass 45): the question, with the count held while it is up.
func _ask_give_up() -> void:
	if not _open or _asking:
		return
	_asking = true
	var gold := Run.run_gold
	WConfirm.open(self, "Stay down?",
		("The run ends here, and the %s gold stays in the sand." % W.num(gold)) if gold > 0 else "The run ends here.",
		"Stay down", "Not yet",
		func():
			_asking = false
			_decide("give_up"),
		func(): _asking = false)


func _decide(kind: String) -> void:
	if not _open:
		return
	_open = false
	if _touch:
		_touch.reset()
	visible = false
	decided.emit(kind)
