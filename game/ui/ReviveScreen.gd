## Down! (Wanted screen 14): a rock dim; "★ 1 CHANCE LEFT ★ / DOWN!"; a paper disc with the count running out and "get
## up"; who put the hero down; then GET UP · WATCH AN AD (a stand-in: no ads yet), GET UP for 150 gold, STAY DOWN. One
## chance per run plus the Mirror's; the hero comes back at half health. The hit log, its copy button and the free
## revive live in the developer menu (Settings.hit_log, free_revive_button); off, this screen shows neither.
class_name ReviveScreen
extends WModal

signal decided(kind: String)   # "ad" | "gold" | "give_up" | "timeout" | "debug"

const SECONDS := 8.0
const GOLD_COST := 150

var _disc: Control
var _count: WText
var _killer_row: HBoxContainer
var _killer_icon: TextureRect
var _killer: WText
var _stats: WText
var _ad_btn: WButton
var _gold_btn: WButton
var _quit_btn: WButton
var _debug_btn2: WButton
var _log_panel: PanelContainer
var _log: WText
var _log_scroll: ScrollContainer
var _copy_btn: WButton
var _hold_btn: WButton
var _log_text := ""
var _t := 0.0
var _open := false
var _held := false
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
	# the hit log (developer menu): a dark panel under the line, with its copy button and a hold for the count
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", W.box(W.INK, 4, 0).pad(20, 16, 20, 16))
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_log_panel.offset_left = 48
	_log_panel.offset_right = -48
	_log_panel.offset_top = 1170
	_log_panel.offset_bottom = 1440
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
	_log = W.text("", W.mono(500), 22, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 30.0, true)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_scroll.add_child(_log)
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
	_quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quit_btn.pressed.connect(func(): _decide("give_up"))
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


## `gold` is the run's gold, `chances` how many revives are left (0 leaves only staying down), `log_text` the hero's
## last 30 s of hits (Player.damage_log_text), `killer` the last hit ({by, kind}) for the line under the count.
func open(gold: int, chances: int, log_text: String = "", killer: Dictionary = {}) -> void:
	_t = 0.0
	_open = true
	_held = false
	var can := chances > 0
	header.star_line.get_child(1).text = ("%d CHANCE%s LEFT" % [chances, "" if chances == 1 else "S"]) if can else "NO CHANCES LEFT"
	_ad_btn.locked = not can
	_gold_btn.locked = not can or gold < GOLD_COST
	_count.text = str(int(ceil(SECONDS)))
	var by := str(killer.get("by", ""))
	var kind := str(killer.get("kind", ""))
	_killer.text = ("%s put you down." % by) if by != "" else "Something put you down."
	var badge := "res://art/ui/badges/%s.png" % ("skull" if kind == "boss" else "crown")
	_killer_icon.texture = load(badge) if (kind == "boss" or kind == "elite") and ResourceLoader.exists(badge) else null
	_killer_icon.visible = _killer_icon.texture != null
	_stats.text = "%s · %s kills · %s" % [W.mmss(Run.elapsed), W.num(Run.kills), W.lv(Run.level)]
	var s := W.node("Settings")
	_log_panel.visible = s != null and bool(s.get("hit_log"))
	_debug_btn2.visible = s != null and bool(s.get("free_revive_button"))
	_log_text = log_text if log_text != "" else "nothing hit you in the last 30 seconds"
	_log.text = _log_text
	_log_scroll.scroll_vertical = 0
	var vp := get_viewport_rect().size
	_disc.position = Vector2((vp.x - 540.0) * 0.5, 470)
	modulate.a = 1.0
	enter()
	Audio.play("ui_pause")


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


## Touch drags on the log scroll it (a drag that starts on the text never reaches a ScrollContainer on a phone).
func _input(event: InputEvent) -> void:
	if _open and _touch and _log_panel.visible:
		_touch.input(event)


func _process(delta: float) -> void:
	if not _open:
		return
	if _touch:
		_touch.process()
	if not _held:
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


func _decide(kind: String) -> void:
	if not _open:
		return
	_open = false
	if _touch:
		_touch.reset()
	visible = false
	decided.emit(kind)
