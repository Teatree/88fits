## Stage clear (Wanted screen 15). Pass 87 (lane SUI; Garry: "Player kills the boss and the Portal that appears shows a 1
## minute timer before the Endless Mode will activate. There is only an Extract button now in the Portal"): one road,
## Extract (safe, the run ends, this run's gold banked, the number big in brass), and under it the clock it races, an
## ink card that is not a road: ENDLESS IN 00:59 counting down (rock in its last ENDLESS_WARN seconds), and what
## Endless is (a huge wave, then a tougher one every few seconds, until the hero falls; the gold comes home either way).
## The count is the game's (Game.portal_seconds_left(), lane SGAME: the portal's timer on the run clock); the dialog only
## shows it. When it runs out with the dialog up, the dialog closes by itself (`expire`, signal `expired`) and Endless
## starts behind it. Before pass 87 the second road was Continue (the next stage) or Stay (hell after the last stage).
## Pass 48 (Garry: a way out of the dialog): NOT YET under the cards, and Esc or the back gesture, close it with no
## decision; the run goes on, the countdown with it (the HUD shows it under the clock), and the portal waits for the hero
## to step out and walk back in.
class_name PortalDialog
extends WModal

## Extract (the only choice since pass 87; `false` is never sent by the dialog any more, tools may still send it).
signal decided(extract: bool)
## The hero is not ready to choose (NOT YET, Esc, the back gesture): the dialog closes with no decision, the run goes
## on (Game unpauses), and the portal arms again once he steps out.
signal declined
## The countdown ran out with the dialog up: it closed itself (pass 87). Game gives the screen's turn back; Endless starts.
signal expired

## The footer: what NOT YET means.
const FOOT := "Not ready? Step out, and walk back in before the clock runs out."
## The countdown turns rock in its last seconds.
const ENDLESS_WARN := 10.0
## Seconds the countdown starts from when no game tells it (a tool or a test opening the dialog on its own).
const DEFAULT_SECONDS := 60.0

var _tag: PanelContainer
var _extract: WTap
var _cards: VBoxContainer
var _foot: WText
var _gold_to: WText
## The Endless card: its panel, title, the count and its lines (pass 87); `_cont_title` keeps the name tools read.
var _endless: PanelContainer
var _cont_title: WText
var _count: WText
var _count_label: WText
var _endless_lines: VBoxContainer
var _not_yet: WButton
## Where the count comes from: a Callable returning seconds (tests and tools), else the game's portal_seconds_left(),
## else a count of its own from DEFAULT_SECONDS.
var seconds_source: Callable
var _own_left := -1.0
var _shown := -1


func _ready() -> void:
	build_dim(W.DIM)
	build_header("", "STAGE 1 CLEAR", "05:00 · 0 kills · Lv 1. Bank it before the horde comes.", 108)
	header.offset_top = 100 + W.safe_top()
	# the BOSS DOWN tag over the title
	_tag = PanelContainer.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tag.add_theme_stylebox_override("panel", W.box(W.INK, 0, 0).pad(30, 8, 30, 8))
	_tag.add_child(W.text("BOSS DOWN", W.slab(W.em(30, 0.08)), 30, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 0.0))
	header.add_child(_tag)
	header.move_child(_tag, 0)
	header.add_theme_constant_override("separation", 8)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 40)
	_cards.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cards.offset_left = 48
	_cards.offset_right = -48
	_cards.offset_top = 470 + W.safe_top()
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	_extract = _road("Extract", "Safe · run ends", W.SAGE, "strongbox", "strongbox\nart")
	_extract.name = "Extract"
	_extract.pressed.connect(func(): visible = false; decided.emit(true))
	var ev: VBoxContainer = _extract.get_meta("body")
	ev.add_child(W.serif_text("This run's gold, banked", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 14)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(56.0, W.BRASS, 4.0)
	g.add_child(coin)
	_gold_to = W.slab_text("0", 96, W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, 96.0)
	g.add_child(_gold_to)
	ev.add_child(g)
	_build_endless()
	# NOT YET (pass 48), centred under the cards
	_not_yet = WButton.make(["NOT YET"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	_not_yet.name = "NotYet"
	_not_yet.custom_minimum_size.x = 420
	_not_yet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_not_yet.pressed.connect(decline)
	_cards.add_child(_not_yet)
	_foot = W.serif_text(FOOT, 28, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.offset_bottom = -80
	_foot.offset_top = -80 - 34
	add_child(_foot)


## The Endless card (pass 87): ink, not a road (nothing to tap): ENDLESS IN over the count on the left, what it is on
## the right; under them the gold line.
func _build_endless() -> void:
	_endless = PanelContainer.new()
	_endless.name = "Endless"
	_endless.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_endless.add_theme_stylebox_override("panel", W.box(W.INK, 6, 0).pad(46, 34, 46, 38))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_endless.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left)
	_cont_title = W.slab_text("Endless", 64, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 64.0)
	_cont_title.name = "Title"
	left.add_child(_cont_title)
	_count_label = W.label("Starts in", 20, W.AGED, 0.15)
	left.add_child(_count_label)
	# the count in a plain holder: the row would reset its swell (a Container resets a child's scale when it sorts)
	var holder := Control.new()
	holder.name = "CountHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(ceilf(W.slab().get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 104).x) + 8.0, 104)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(holder)
	_count = W.slab_text("01:00", 104, W.BRASS, HORIZONTAL_ALIGNMENT_RIGHT, 104.0)
	_count.name = "Count"
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_count)
	_endless_lines = VBoxContainer.new()
	_endless_lines.add_theme_constant_override("separation", 8)
	_endless_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_endless_lines)
	_cards.add_child(_endless)


## Not now: the dialog closes with no decision (`declined`; Game unpauses and the portal re-arms once the hero is out).
func decline() -> void:
	if not visible:
		return
	visible = false
	declined.emit()


## The countdown ran out (the game starting Endless, or the dialog's own count reaching 0): the dialog goes with no
## decision and says so (`expired`).
func expire() -> void:
	if not visible:
		return
	visible = false
	expired.emit()


## The back gesture does what NOT YET does while the dialog is up (in a run it otherwise does nothing).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		decline()


## Esc on a PC, the same.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE) or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		decline()


## The road: a paper card (6 px ink, a 12 px shadow), its name in 64 px slab with a tracked tag on the right, the art
## (a placeholder until painted) and a column of what it means.
func _road(t: String, tag: String, tag_color: Color, slot: String, art_label: String) -> WTap:
	var c := WTap.new()
	var b := W.box(W.PAPER, 6, 12).pad(46, 42, 46, 42)
	c.box = b
	var down := b.pressed()
	down.inner = 6
	c.box_down = down
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tt := W.slab_text(t, 64, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 64.0)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	var tg := W.label(tag, 20, tag_color)
	tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tg)
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := WPlaceholder.make(slot, art_label, Vector2(188, 188))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.set_meta("small", true)
	row.add_child(art)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(body)
	v.add_child(row)
	c.set_meta("title", tt)
	c.set_meta("tag", tg)
	c.set_meta("body", body)
	_cards.add_child(c)
	return c


## A line on the Endless card: a number in slab and what it means in Bitter, on ink.
func _fact(n: String, col: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if n != "":
		var nt := W.slab_text(n, 34, col, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		nt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nt)
	# one line, never wrapped: a wrapped line's height settles a frame late and the card had drawn it over its foot
	var tt := W.serif_text(text, 28, W.PAPER, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tt)
	return h


## Open after stage `stage_cleared` (1-based). The other two arguments are kept for the callers of the two-road dialog
## (pass 43-86); since pass 87 there is no road onward.
func open(stage_cleared: int, _can_continue: bool = false, _final_stage: bool = false) -> void:
	var gold := Run.run_gold
	W.sfx_first(["ui_stage_clear"])   # pass 64: the stage-clear jingle
	header.set_title("STAGE %d CLEAR" % stage_cleared)
	header.set_line("%s · %s kills · %s. Bank it before the horde comes." % [W.mmss(_stage_time()), W.num(Run.kills), W.lv(Run.level)])
	_gold_to.text = W.num(gold)
	# out of the column at once (a second open in the same frame must not lay the new lines out under the old ones)
	for c in _endless_lines.get_children():
		_endless_lines.remove_child(c)
		c.queue_free()
	var every := _endless_every()
	_endless_lines.add_child(_fact("", W.PAPER, "A huge wave, then a tougher one every %s, until you fall." % _secs(every)))
	# pass 70: a death banks the purse too, so the gold is not the stake any more
	_endless_lines.add_child(W.serif_text("The %s gold comes home either way." % W.num(gold), 24, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false))
	_own_left = DEFAULT_SECONDS if _own_left < 0.0 else _own_left
	_shown = -1
	_tick_count()
	modulate.a = 1.0
	enter()


## The seconds left before Endless: the source a tool gave, else the game's portal timer, else the dialog's own count.
func seconds_left() -> float:
	if seconds_source.is_valid():
		return float(seconds_source.call())
	var g := _game()
	if g and g.has_method("portal_seconds_left"):
		return float(g.call("portal_seconds_left"))
	return maxf(_own_left, 0.0)


func _game() -> Node:
	var t := get_tree()
	if t == null:
		return null
	var cs := t.current_scene
	return cs if cs and cs.has_method("portal_seconds_left") else null


## While it is up the dialog keeps the game's countdown running (Game.tick_portal_countdown, lane SGAME: the run is paused
## behind it, every other screen holds the count); at 0 the game starts Endless and closes the dialog itself. A tool's
## pinned count, or no game at all, runs the dialog's own: at 0 it closes by itself (`expire`).
func _process(delta: float) -> void:
	if not visible:
		return
	var g := _game() if not seconds_source.is_valid() else null
	if g and g.has_method("tick_portal_countdown"):
		g.call("tick_portal_countdown", delta)
		if not visible:
			return
	elif not seconds_source.is_valid() and g == null and _own_left > 0.0:
		_own_left = maxf(_own_left - delta, 0.0)
	_tick_count(g == null)


## The count on the card, rock in its last seconds; at 0 with the dialog up and no game to close it, it closes itself
## (`expire`).
func _tick_count(own: bool = true) -> void:
	var left := seconds_left()
	var whole := int(ceil(maxf(left, 0.0)))
	if whole != _shown:
		_shown = whole
		_count.text = W.mmss(float(whole))
		_count.color = W.ROCK if left <= ENDLESS_WARN else W.BRASS
		if whole <= int(ENDLESS_WARN) and whole > 0 and visible:
			_pulse()
	if own and left <= 0.0 and visible and is_inside_tree():
		expire()


## The count's beat in its last seconds: a quick swell and back.
func _pulse() -> void:
	_count.pivot_offset = _count.size * Vector2(1.0, 0.5)
	_count.scale = Vector2.ONE * 1.12
	var tw := _count.create_tween()
	tw.tween_property(_count, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The stage's own clock (the time within the stage since pass 87, Run.stage_clock), as the HUD shows it.
static func _stage_time() -> float:
	return Run.stage_clock()


## Seconds between Endless's waves after this stage (the map's `endless.every`, the stage's own first; lane SGAME).
static func _endless_every() -> float:
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	return tl.endless_value("every", Run.stage) if tl else 10.0


static func _secs(s: float) -> String:
	return ("%d s" % int(round(s))) if absf(s - round(s)) < 0.05 else ("%.1f s" % s)
