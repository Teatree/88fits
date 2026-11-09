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
## The foot line (pass 137: the string table, key ui.portal.foot).
const FOOT_KEY := "ui.portal.foot"
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
## Pass 123 (lane RUN_A): the theme the dialog was built in (a flip of the debug switch builds it again on the next
## open), and the Royale run pills' row (the time, kills, level and the line, as black pills).
var _pills: HBoxContainer

## Pass 123 (lane RUN_A), the Royale look (the mock 10_Stage_clear; Garry: "Extract and Endless as two slate cards,
## EXTRACT in gold, NOT YET in slate", "Not Yet should be outside the Endless element for sure. Header should be white"):
## the header's top and title size, where the cards start and their gap, the cards' padding, the strongbox's frame, the
## card titles, the count, the buttons' heights.
const ROYALE_HEAD_TOP := 64.0
const ROYALE_TITLE_PX := 100
const ROYALE_PILLS_GAP := 18.0
const ROYALE_CARDS_TOP := 348.0
const ROYALE_CARDS_GAP := 28
const ROYALE_CARD_PAD := Vector2(32, 26)
const ROYALE_CARD_TITLE_PX := 56
const ROYALE_ART_PX := 150.0
const ROYALE_GOLD_PX := 80
const ROYALE_COUNT_PX := 104
const ROYALE_EXTRACT_PX := 40
const ROYALE_EXTRACT_W := 330.0
const ROYALE_NOT_YET_PX := 36


func _ready() -> void:
	_build()


## The dialog's standing parts (pass 123: out of _ready, so a theme flip can build them again).
func _build() -> void:
	_build_royale()
	return


## Pass 123 (lane RUN_A): the stage clear under Royale (the mock 10_Stage_clear): "★ BOSS DOWN ★" in gold over STAGE n
## CLEAR in cream with the navy edge; the run's time, kills, level and its line as black pills; the Extract card (slate:
## its name, the green SAFE · RUN ENDS tag, the strongbox in a gold frame, this run's gold, EXTRACT in gold: the one way
## out); the Endless card (slate: its name over STARTS IN, the count in gold, red in its last seconds, what Endless is,
## the gold line); NOT YET in slate under the cards and outside them (Garry); the walk-away line at the foot. The same
## names: "Extract" (the button now), "Endless", "Title", "Count", "NotYet".
func _build_royale() -> void:
	build_dim(W.DIM)
	build_header(Loc.t("ui.portal.star"), Loc.t("ui.portal.stage_clear", {"stage": "1"}), "", ROYALE_TITLE_PX, W.PAPER, ROYALE_HEAD_TOP)
	header.line.visible = false
	_pills = HBoxContainer.new()
	_pills.name = "RunPills"
	_pills.alignment = BoxContainer.ALIGNMENT_CENTER
	_pills.add_theme_constant_override("separation", 12)
	_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gap := Control.new()
	gap.custom_minimum_size.y = ROYALE_PILLS_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gap)
	header.add_child(_pills)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", ROYALE_CARDS_GAP)
	_cards.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cards.offset_left = 48
	_cards.offset_right = -48
	_cards.offset_top = ROYALE_CARDS_TOP + W.safe_top()
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	# the Extract card: slate, its head (name and tag), the strongbox in a gold frame beside the gold, EXTRACT under it
	var card := PanelContainer.new()
	card.name = "ExtractCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", W.sheet_box(ROYALE_CARD_PAD))
	_cards.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var tt := W.slab_text(Loc.t("ui.portal.extract_title"), ROYALE_CARD_TITLE_PX, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, float(ROYALE_CARD_TITLE_PX))
	tt.name = "ExtractTitle"
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	_tag = _royale_tag(Loc.t("ui.portal.extract_tag"), R.TAG_GREEN)
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_tag)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var art := WPlate.new()
	art.name = "Strongbox"
	art.side = ROYALE_ART_PX
	art.fill = W.RARITY_PLATE["legendary"]
	art.glow_reach = 14.0
	var box_path := WPlaceholder.ART_DIR + "strongbox.png"
	art.tex = load(box_path) as Texture2D if ResourceLoader.exists(box_path) else null
	art.icon_frac_royale = 0.82
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(body)
	body.add_child(W.serif_text(Loc.t("ui.portal.gold_banked"), 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 14)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(WCoin.make(56.0, W.BRASS, 4.0))
	_gold_to = W.slab_text("0", ROYALE_GOLD_PX, W.BRASS, HORIZONTAL_ALIGNMENT_LEFT, float(ROYALE_GOLD_PX))
	g.add_child(_gold_to)
	body.add_child(g)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	var ex := WButton.make([Loc.t("ui.portal.extract")], ROYALE_EXTRACT_PX, WButton.PRIMARY, 4, 8, 22.0, 30.0, float(ROYALE_EXTRACT_PX))
	ex.name = "Extract"
	ex.custom_minimum_size.x = ROYALE_EXTRACT_W
	ex.pressed.connect(extract)
	foot.add_child(ex)
	_extract = ex
	_build_endless_royale()
	# NOT YET: under the cards, outside the Endless card (Garry), as wide as the cards
	_not_yet = WButton.make([Loc.t("ui.portal.not_yet")], ROYALE_NOT_YET_PX, WButton.SECONDARY, 4, 8, 24.0, 0.0)
	_not_yet.name = "NotYet"
	_not_yet.pressed.connect(decline)
	_cards.add_child(_not_yet)
	_foot = W.serif_text(Loc.t(FOOT_KEY), 28, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.offset_bottom = -80
	_foot.offset_top = -80 - 34
	add_child(_foot)


## The Endless card under Royale: slate (not a road: nothing on it to tap), its name over STARTS IN on the left, the
## count on the right, then what Endless is and the gold line.
func _build_endless_royale() -> void:
	_endless = PanelContainer.new()
	_endless.name = "Endless"
	_endless.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_endless.add_theme_stylebox_override("panel", W.sheet_box(ROYALE_CARD_PAD))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
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
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(left)
	_cont_title = W.slab_text(Loc.t("ui.portal.endless_title"), ROYALE_CARD_TITLE_PX, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, float(ROYALE_CARD_TITLE_PX))
	_cont_title.name = "Title"
	left.add_child(_cont_title)
	_count_label = W.label(Loc.t("ui.portal.starts_in"), 20, W.INK_SOFT)
	left.add_child(_count_label)
	var holder := Control.new()
	holder.name = "CountHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(ceilf(R.display().get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1,
		ROYALE_COUNT_PX).x) + 12.0, float(ROYALE_COUNT_PX))
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(holder)
	_count = W.slab_text("01:00", ROYALE_COUNT_PX, W.BRASS, HORIZONTAL_ALIGNMENT_RIGHT, float(ROYALE_COUNT_PX))
	_count.name = "Count"
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_count)
	_endless_lines = VBoxContainer.new()
	_endless_lines.add_theme_constant_override("separation", 8)
	_endless_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_endless_lines)
	_cards.add_child(_endless)


## The kit's tag (pass 123): a word in Rubik 700 capitals, navy on `fill`, 4 px corners, a 3 px navy edge.
static func _royale_tag(t: String, fill: Color) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.name = "Tag"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := W.box(fill, R.TAG_EDGE, 0, R.RADIUS_TAG).pad(12 + R.TAG_EDGE, 4 + R.TAG_EDGE, 12 + R.TAG_EDGE, 4 + R.TAG_EDGE)
	b.border_color = R.NAVY
	b.themed = false
	tag.add_theme_stylebox_override("panel", b)
	tag.add_child(W.text(t.to_upper(), R.body(R.LABEL_WEIGHT, false, W.em(20, 0.1)), 20, R.NAVY, HORIZONTAL_ALIGNMENT_CENTER, 0.0))
	return tag


## Not now: the dialog closes with no decision (`declined`; Game unpauses and the portal re-arms once the hero is out).
## EXTRACT tapped (pass 114: a function of its own, so a replay calls the same): the dialog goes, the run ends banked.
func extract() -> void:
	if not visible:
		return
	RunReplay.note("portal_extract")
	visible = false
	decided.emit(true)


func decline() -> void:
	if not visible:
		return
	RunReplay.note("portal_decline")
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
	header.set_title(Loc.t("ui.portal.stage_clear", {"stage": str(stage_cleared)}))
	header.set_line(Loc.t("ui.portal.line", {"time": W.mmss(_stage_time()), "kills": W.num(Run.kills), "level": W.lv(Run.level)}))
	if _pills:
		# pass 123: the same words as black pills, the dry line hidden (built again each open: once a stage, never a frame)
		header.line.visible = false
		for c in _pills.get_children():
			_pills.remove_child(c)
			c.queue_free()
		for t in [W.mmss(_stage_time()), Loc.t("ui.portal.kills", {"kills": W.num(Run.kills)}), W.lv(Run.level)]:
			_pills.add_child(W.pill([[str(t), null, "bold"]], 24, 44.0))
		_pills.add_child(W.pill(Loc.t("ui.portal.bank_it"), 24, 44.0))
	_gold_to.text = W.num(gold)
	# out of the column at once (a second open in the same frame must not lay the new lines out under the old ones)
	for c in _endless_lines.get_children():
		_endless_lines.remove_child(c)
		c.queue_free()
	var every := _endless_every()
	_endless_lines.add_child(_fact("", W.PAPER, Loc.t("ui.portal.endless_line", {"every": _secs(every)})))
	# pass 70: a death banks the purse too, so the gold is not the stake any more
	_endless_lines.add_child(W.serif_text(Loc.t("ui.portal.gold_home", {"gold": W.num(gold)}), 24, W.INK_SOFT,
		400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false))
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
	# pass 114 (lane REPLAY): the game it sits in first (a replay's or the Watch's game is not the tree's current scene)
	var up := get_parent()
	while up != null:
		if up.has_method("portal_seconds_left"):
			return up
		up = up.get_parent()
	var t := get_tree()
	if t == null:
		return null
	var cs := t.current_scene
	return cs if cs and cs.has_method("portal_seconds_left") else null


## While it is up the dialog keeps the game's countdown running (Game.tick_portal_countdown, lane SGAME: the run is paused
## behind it, every other screen holds the count); at 0 the game starts Endless and closes the dialog itself. A tool's
## pinned count, or no game at all, runs the dialog's own: at 0 it closes by itself (`expire`).
func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
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
		# pass 123: the kit's gold with its bevel, the kit's red in the last seconds
		var warn := left <= ENDLESS_WARN
		_count.color = R.ROLES["red"]["top"] if warn else R.GOLD_TEXT
		_count.bevel = 0
		R.edge(_count, ROYALE_COUNT_PX, not warn)
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
