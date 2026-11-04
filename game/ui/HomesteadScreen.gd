## Upgrade (Wanted 03/03b; "The Mirror" until pass 44, when Garry asked for a name that says what it is for): the meta
## between runs. Eight talents, each with two mutually exclusive forms and seven ranks (six until pass 123, three until pass 46, Garry: "double
## the number of possible Upgrades for each path"). The board shows each talent's name, its rank notches, the live form
## and what it does, and the next rank's price on a paper tag (brass is the BUY button's alone, pass 46); a tap opens the
## talent's sheet over a sepia dim: the two forms side by side (the live one in ink; switching is free and keeps the
## ranks), what the ranks give now, and the next rank for gold. "Take it all back" asks in a pop-up, then empties the
## board and returns half the coins (Save.REFUND_FRAC). The talents hold for every hero, so the mirror shows none of
## them: something looks back out of the dark glass, two brass eyes (art/ui/wanted/mirror.png replaces the drawn mirror
## when it exists).
## Pass 61 (Garry: "The choices in the Mirror should be shown as little icons. Maybe as a summary also. Each of those
## icons should be distinctly different from their counterpart. So say Grit will have a progress bar filled up with 2
## types of distinct icons representing choices that Player made. Make the UI elements taller to make enough space for
## those icons to make sense as well as the empty bars"): every form has its own painted icon (TalentDef.form_icon); a
## tile's notches became a rank bar of six slots (a bought rank the live form's icon on a raised paper plate, an unbought
## one the HUD's dashed empty slot), a talent with no rank shows both forms' icons small beside its name, the tiles grew
## to hold the bar, the sheet shows the same bar large and the two forms with their icons, and a summary strip over the
## mirror lists every talent with ranks as its live form's icon and "x<rank>".
## Pass 123 (lane UPGRADE), under Royale: the mock 5_Upgrade
## (Garry: "Upgrade board as the mock: no mirror, YOU HOLD and TAKE IT ALL BACK with the refund line in the header, 2x4
## tiles with both options and their effect lines from data, a blue price · CHOOSE opening a pop-up with two green BUY
## buttons"; "the 'Your Upgrades' part ... needs to have enough space for all of them. Also, change the text 'Take it
## all back' to just be 'Reset Upgrades'"; "Filled rank pips show the chosen option's icon"; "Keep the tab bar on all
## four hub screens ... fit the Upgrade board above it"). Under the header (back, UPGRADE, the wallet): YOU HOLD, every
## option held as its icon in a small frame with its rank count on the plaque, two rows of eight (eight talents x two
## options always fit), and RESET UPGRADES (slate) with the refund line under it; the board: the eight talents
## (Registry.talents_list) as 2 x 4 slate tiles, each its name, RANK n / m, option A's row (its icon in a 56 px frame, its
## name, TextGen's line for one rank "per rank"), "or", option B's, the pip track (a bought rank shows the
## icon of the option it was bought in) and a blue "● price · CHOOSE" (the kit's short state when the purse is short,
## MAXED at the top, LOCKED with its quest while the talent is locked); CHOOSE opens the shared modal shell with both options,
## each with its effect, what it holds and a green "● price · BUY" that buys the next rank in that option (Save.buy_talent,
## as the Wanted sheet's Buy0 / Buy1); the docked tab bar (UPGRADE open) at the foot, the board above it on a 1080 x 1920
## canvas (a shorter phone scrolls, a taller one centres the tiles). Every price, refund and rule as before.
extends ScreenBase

const MIRROR_ART := "res://art/ui/wanted/mirror.png"

var _gold: PanelContainer
var _grid: GridContainer
var _refund: WTap
var _sheet_root: Control
var _sheet_def: TalentDef
## The summary strip (pass 61) and the flow its chips (or the empty hint) sit in.
var _summary: PanelContainer
var _summary_flow: HFlowContainer


func header_right() -> Control:
	_gold = WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	return _gold


func board_top() -> float:
	# pass 123: under Royale the YOU HOLD row starts the board (the mock's y 176)
	return R_TOP


func board_bottom() -> float:
	# pass 123: under Royale the refund line sits under RESET UPGRADES at the top, and the tab bar is ScreenBase's
	return R_FOOT


## Pass 123: the mock's 40 px sides under Royale (two 490 px tiles and a 20 px gap); 48 under Wanted.
func board_side() -> float:
	return R_SIDE


## Pass 123: the docked tab bar with UPGRADE open (ScreenBase lays it only under Royale).
func tab_bar() -> String:
	return "upgrade"


func build() -> void:
	# pass 123 (lane UPGRADE): the mock's board under Royale
	_build_royale()
	return


func _refresh() -> void:
	# pass 123 (lane UPGRADE): the Royale board's tiles, YOU HOLD, the refund line and the wallet
	_refresh_royale()
	return


func _amount_of(p: Control) -> WText:
	for n in p.find_children("Amount", "", true, false):
		return n as WText
	return null


## A form's icon on a paper plate `px` square (the bar's bought slot, the choice's, the summary's chip, the pair beside a
## name), or the form's initial when its icon is missing.
static func form_plate(def: TalentDef, form: int, px: float) -> WPlate:
	var p := WPlate.new()
	p.side = px
	p.fill = W.PAPER
	p.radius = 10 if px < 140 else 12
	p.border = 3 if px < 56 else 4
	p.tex = def.form_icon(form)
	if p.tex == null:
		p.glyph = def.form_name(form).left(1)
	p.set_meta("form", form)
	return p


# --- the summary -------------------------------------------------------------------------------------------------------


## What a talent's ranks give together (pass 63): each form's ranks summed, the first form's effects first.
static func held_effects(def: TalentDef) -> Array:
	var out: Array = []
	for form in range(2):
		var n := Save.talent_count(def.id, form)
		if n > 0:
			out.append_array(def.summed_effects(form, n, Save.talent_top(def, form)))
	# pass 115 (lane META): a stat whose starting value the talent owns reads as its whole value ("revive with 60%
	# health", TextGen.SET_TEXT), not as the ranks' step over it
	for k in out.size():
		var e: Effect = out[k]
		if e.op == "add" and def.base_stats.has(e.stat):
			out[k] = Effect.make(e.stat, "set", def.base_of(e.stat, 0.0) + e.value, e.target)
	return out


## The line a talent's ranks read as (pass 115): TextGen's words with the first letter a capital ("Revive with 60%
## health"; "+2 skips, revive with 60% health").
static func held_line(def: TalentDef) -> String:
	var s := TextGen.describe_effects(held_effects(def))
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


## The talents the summary lists: those with at least one rank, in board order.
static func summary_talents() -> Array:
	var out: Array = []
	for def: TalentDef in Registry.talents_list():
		if Save.talent_rank(def.id) > 0:
			out.append(def)
	return out


## The next rank's price: the coin and the number in ink on a paper tag; aged, coin and all, when the purse is short
## (pass 46: the tag was brass, and brass is kept for BUY).
func _price(cost: int, can: bool, cur: String = "gold") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Price"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER if can else W.AGED, 4, 4 if can else 0).pad(22, 12, 22, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pass 111 (lane SKINS): the icon of the talent's currency
	var coin := WCoin.make(32.0, W.BRASS if can else W.AGED, 3.0, Currency.of(cur))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin)
	var t := W.slab_text(W.num(cost), 30, W.INK if can else W.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	h.add_child(t)
	p.add_child(h)
	return p


## A flat tag in slab ("Full", the unlock quest).
func _tag(t: String, fill: Color, shadow: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(fill, 4, shadow).pad(22, 12, 22, 12))
	p.add_child(W.slab_text(t, 26, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	return p


# --- the sheet ---------------------------------------------------------------------------------------------------------

## A talent opened over a sepia dim: its two forms, what the ranks give, the next rank for gold, Close. Pass 123: under
## Royale the CHOOSE pop-up (_open_choice) in the shared modal shell.
func _open(def: TalentDef) -> void:
	_open_choice(def)
	return


func _close(animate: bool) -> void:
	# pass 123: under Royale the open sheet is the CHOOSE pop-up (a WConfirm shell): it leaves as its CLOSE does
	if _choice:
		_close_choice()
		return
	if _sheet_root == null:
		return
	var root := _sheet_root
	_sheet_root = null
	_sheet_def = null
	if not animate:
		root.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.15)
	tw.tween_callback(root.queue_free)


## The question before every rank goes (pass 45): what comes back and what does not, then the refund.
func _take_back() -> void:
	var spent := Save.talent_spent()
	if spent <= 0:
		Audio.play("ui_locked")
		return
	# pass 123 (Garry: "change the text 'Take it all back' to just be 'Reset Upgrades'"): the Royale words, the same
	# refund and the same red confirm
	WConfirm.open(self, "Reset Upgrades?",
		"Every rank on the board goes. %s of the %s gold spent comes back; the rest is gone." % [W.num(Save.talent_refund()), W.num(spent)],
		"Reset", "Keep them", func():
			Save.talent_refund_all()
			Audio.play("ui_buy")
			_refresh())
	return


## The back gesture (or Esc) closes an open talent first.
func on_back() -> void:
	if _sheet_root:
		_close(true)
		return
	go(TITLE)


## The board does not scroll under an open sheet.
func _input(event: InputEvent) -> void:
	if _sheet_root == null:
		super._input(event)


# ---------------------------------------------------------------- pass 88 (lane MIRROR): the Stakes' refund, said once

## The toasts over the mirror while the board's note shows (null without one).
var _note_toasts: WToasts
## Where they sit: over the mirror's glass, under the summary strip.
const NOTE_TOP := 450.0


## Save.board_note's "stakes_refund" (Save._migrate_stakes: an older save's Spite ranks, Thorns and Thirst, paid back in
## full) as two toasts the first time the board opens after it, then forgotten.
func _show_board_note() -> void:
	var n := Save.board_note()
	var words: Array = []
	if str(n.get("kind", "")) == "stakes_refund":
		words.append_array(note_words(n))
		Save.clear_board_note()
	# pass 115 (lane META): Nerve's cheaper ranks and Second Wind's new effect (Save._migrate_nerve), after the Stakes'
	var nn := Save.nerve_note()
	if str(nn.get("kind", "")) == "nerve_refund":
		words.append_array(nerve_words(nn))
		Save.clear_nerve_note()
	if words.is_empty():
		return
	_note_toasts = WToasts.new()
	_note_toasts.name = "NoteToasts"
	_note_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_note_toasts.offset_top = NOTE_TOP
	_note_toasts.offset_bottom = NOTE_TOP + 200.0
	add_child(_note_toasts)
	for t in words:
		_note_toasts.push(t)


## The note's toasts: ["SPITE IS NOW STAKES", "+2,900 GOLD BACK FOR 3 RANKS"].
static func note_words(n: Dictionary) -> Array:
	var ranks := int(n.get("ranks", 0))
	return ["SPITE IS NOW STAKES", "+%s GOLD BACK FOR %d RANK%s" % [W.num(int(n.get("gold", 0))), ranks, "" if ranks == 1 else "S"]]


## The Nerve note's toasts (pass 115): ["NERVE COSTS LESS NOW", "+800 GOLD BACK FOR 3 RANKS"] when gold came back, then
## "SECOND WIND: REVIVE HEALTH" when the save holds a Second Wind rank (its revives became revive health).
static func nerve_words(n: Dictionary) -> Array:
	var out: Array = []
	var ranks := int(n.get("ranks", 0))
	var gold := int(n.get("gold", 0))
	if gold > 0:
		out.append("NERVE COSTS LESS NOW")
		out.append("+%s GOLD BACK FOR %d RANK%s" % [W.num(gold), ranks, "" if ranks == 1 else "S"])
	if int(n.get("second_wind", 0)) > 0:
		out.append("SECOND WIND: REVIVE HEALTH")
	return out


func _process(delta: float) -> void:
	super(delta)
	if _note_toasts:
		_note_toasts.tick(delta)


# ---------------------------------------------------------------- pass 123 (lane UPGRADE): the Royale board

## The Royale layout in canvas px (the mock 5_Upgrade at 1.5x, fitted above the docked tab bar): the YOU HOLD row from
## R_TOP, the board R_SIDE in, the scroll's foot R_FOOT over the tab bar.
const R_TOP := 168.0
const R_FOOT := 12.0
const R_SIDE := 40.0
## YOU HOLD: its label (Rubik 700 R_HOLD_PX, tracked), R_HOLD_GAP to the held options' frames (R_CHIP px, R_CHIP_GAP
## apart, R_CHIPS_A_ROW to a row; the rows grow with what is held, pass 124: no room kept for rows nobody has yet (Garry:
## "a huge empty space at the top"),
## R_CHIP_ROW_GAP between the rows for the count plaque that hangs R_CHIP_HANG px under a frame); RESET UPGRADES R_RESET_H
## tall at R_RESET_PX (Rubik 700 by the Ultra minimum) with the refund line under it (Rubik 500 R_REFUND_PX, the numbers
## gold and bold).
const R_HOLD_PX := 20
const R_HOLD_GAP := 14
const R_CHIP := 64.0
const R_CHIP_GAP := 8
const R_CHIP_ROW_GAP := 20
const R_CHIPS_A_ROW := 6
const R_CHIP_HANG := 15.0
const R_RESET_H := 56.0
const R_RESET_PX := 22
const R_REFUND_PX := 20
const R_REFUND_MIN_PX := 14
## The line YOU HOLD shows while nothing is held: one line in the frames' room, on the first row's middle.
const R_HINT_PX := 18
## The board: 2 x 4 slate tiles at least R_TILE_H tall, R_TILE_GAP_H / R_TILE_GAP_V apart (a tile's 8 px navy base sits
## in the latter), at least R_BOARD_GAP under YOU HOLD.
const R_BOARD_GAP := 14.0
const R_TILE_H := 300.0
const R_TILE_GAP_H := 20
const R_TILE_GAP_V := 16
## Inside a tile: R_TILE_PAD at the sides and the top, R_TILE_FOOT under the CHOOSE button's base; the name (Ultra
## R_NAME_PX) with RANK n / 6 (Rubik 700 R_RANK_PX, .14em) at its right; an option's row: its frame R_FORM px, R_FORM_GAP
## to its words (the name Rubik 700 R_FORM_NAME_PX white, the line Rubik 500 R_FORM_LINE_PX secondary), "or" (Rubik 500
## italic R_OR_PX, muted) between the two rows; the pips R_PIP, R_PIP_GAP apart; CHOOSE R_CHOOSE_H tall (Ultra
## R_CHOOSE_PX).
const R_TILE_PAD := Vector2(20, 10)
const R_TILE_FOOT := 8.0
const R_NAME_PX := 36
const R_RANK_PX := 18
const R_FORM := 50.0
const R_FORM_GAP := 12
const R_FORM_NAME_PX := 22
const R_FORM_NAME_LH := 25.0
const R_FORM_LINE_PX := 20
const R_FORM_LINE_LH := 22.0
## Pass 124 (Garry: "The chosen upgrade icons should be bigger. On the buy pop-up especially"): a tile's pips, and the
## pop-up's much bigger ones.
const R_PIP := Vector2(56, 54)
const R_POP_PIP := Vector2(88, 84)
const R_POP_PIP_GAP := 8.0
const R_PIP_GAP := 6.0
## The gaps down a tile: under the name, over the pips (at least: a tile beside a taller one gives it the rest, so the
## pips and the buttons of a row line up), between the pips and CHOOSE.
const R_HEAD_GAP := 6.0
const R_FORM_ROW_GAP := 8.0
const R_PIPS_GAP := 6.0
const R_CHOOSE_GAP := 10.0
const R_CHOOSE_H := 48.0
const R_CHOOSE_PX := 26
## The CHOOSE pop-up (the shared modal shell, R.MODAL_W wide): the rank star line, the talent's name, its flavour, what
## its ranks hold, its pips, then each option in a solid cell (its frame R_POP_FORM px, its name in Ultra R_POP_NAME_PX,
## its line in Rubik 500 R_POP_LINE_PX, "n owned", and a green "● price · BUY" R_POP_BUY_W x R_POP_BUY_H; the kit's short
## state with "n short" under it when the purse is short); CLOSE in slate.
const R_POP_FORM := 96.0
const R_POP_NAME_PX := 40
const R_POP_LINE_PX := 26
const R_POP_BUY_W := 260.0
const R_POP_BUY_H := 64.0
const R_POP_CLOSE_H := 96.0
const R_POP_CLOSE_PX := 38
## The purse pill in the pop-up's top-right corner (the coin's px).
const R_POP_PURSE_COIN := 28.0
## An empty pip: the mock's see-through black in a 3 px navy edge, a 2 px dashed line 6 px in.
const R_PIP_EDGE := 3
const R_PIP_EMPTY := Color(8 / 255.0, 10 / 255.0, 18 / 255.0, 0.45)
## The dark over the menu backdrop (ScreenBase.backdrop_dim): the mock draws the Upgrade board on its night sky.
const R_DIM := 0.45

## Pass 123: the board was built the Royale way (fixed at build: a theme change reaches the next screen built).
## The CHOOSE pop-up while it shows (a WConfirm shell; `_sheet_root` points at it too, so the Wanted sheet's callers and
## the back gesture keep working), RESET UPGRADES and the refund line's box.
var _choice: WConfirm
var _reset: WButton
var _refund_box: VBoxContainer
## The room the refund line has (RESET UPGRADES' column, from the screen's width at build): a line wider than it is set
## smaller (never under R_REFUND_MIN_PX) rather than pushing the board wider.
var _refund_w := 0.0


func backdrop_dim() -> float:
	return R_DIM


func _build_royale() -> void:
	set_title("Upgrade")
	content.add_theme_constant_override("separation", 0)
	# a taller screen: the board takes the room between YOU HOLD and the tab bar and the tiles sit in its middle (the two
	# spacers share what is left over); a shorter one scrolls as every board does
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_make_hold_row())
	content.add_child(_spacer(R_BOARD_GAP, false))
	_grid = GridContainer.new()
	_grid.name = "Board"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", R_TILE_GAP_H)
	_grid.add_theme_constant_override("v_separation", R_TILE_GAP_V)
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_grid)
	content.add_child(_spacer(0.0, true))
	_refresh_royale()
	_show_board_note()


func _spacer(h: float, grow: bool) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = h
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if grow:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


## The row under the header: YOU HOLD and its frames at the left, RESET UPGRADES and the refund line at the right.
func _make_hold_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "HoldRow"
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := HBoxContainer.new()
	left.name = "Hold"
	left.add_theme_constant_override("separation", R_HOLD_GAP)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab_box := VBoxContainer.new()
	lab_box.add_theme_constant_override("separation", 0)
	lab_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := W.label("You hold", R_HOLD_PX)
	lab.name = "HoldLabel"
	# its middle on the first row's
	lab_box.add_child(_spacer(maxf(roundf((R_CHIP - lab.get_combined_minimum_size().y) * 0.5), 0.0), false))
	lab_box.add_child(lab)
	left.add_child(lab_box)
	_summary_flow = HFlowContainer.new()
	_summary_flow.name = "Chips"
	_summary_flow.add_theme_constant_override("h_separation", R_CHIP_GAP)
	_summary_flow.add_theme_constant_override("v_separation", R_CHIP_ROW_GAP)
	_summary_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_flow.custom_minimum_size = Vector2(R_CHIPS_A_ROW * R_CHIP + (R_CHIPS_A_ROW - 1) * R_CHIP_GAP, R_CHIP)
	# the last row's count plaques hang under it, however many rows there are
	var hang := MarginContainer.new()
	hang.name = "ChipsHang"
	hang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hang.add_theme_constant_override("margin_bottom", int(R_CHIP_HANG))
	hang.add_child(_summary_flow)
	left.add_child(hang)
	row.add_child(left)
	# what is left of the board's width for RESET UPGRADES and its line (the row never grows past the board)
	var vw := get_viewport_rect().size.x if is_inside_tree() else 1080.0
	_refund_w = maxf(vw - 2.0 * R_SIDE - (lab.get_combined_minimum_size().x + R_HOLD_GAP + _summary_flow.custom_minimum_size.x) - 16.0, 160.0)
	var right := VBoxContainer.new()
	right.name = "ResetBox"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the button's coloured and navy base hang 12 px under it
	right.add_theme_constant_override("separation", R.BUTTON_BASE + R.BUTTON_NAVY_BASE + 4)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var e := R.BUTTON_EDGE
	_reset = WButton.make(["RESET UPGRADES"], R_RESET_PX, WButton.SECONDARY, e, R.BUTTON_BASE,
		maxf((R_RESET_H - 2.0 * e - R_RESET_PX) * 0.5, 0.0), 16.0, float(R_RESET_PX), WButton.SLATE)
	_reset.name = "Reset"
	_reset.pressed.connect(_take_back)
	right.add_child(_reset)
	_refund_box = VBoxContainer.new()
	_refund_box.name = "Refund"
	_refund_box.add_theme_constant_override("separation", 0)
	_refund_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_refund_box)
	row.add_child(right)
	return row


## The board again (after a buy or the reset): the tiles, YOU HOLD, the refund line, the wallet, the tab bar's marks.
func _refresh_royale() -> void:
	# pass 123 (Garry: the crumb "disappears once Player had tapped it"): what is affordable now has been seen
	Crumbs.upgrade_mark_seen()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for def: TalentDef in Registry.talents_list():
		_grid.add_child(_tile_royale(def))
	_fill_hold()
	_fill_refund()
	var amount := _amount_of(_gold)
	if amount:
		amount.text = W.num(Save.gold())
	if tab_bar_node and tab_bar_node.has_method("refresh"):
		tab_bar_node.call("refresh")


## YOU HOLD's frames: per talent with ranks, in board order, one frame an option it holds (its icon, the count on the
## plaque; named Chip_<talent>_<form> as the Wanted summary's chips), or the Wanted summary's line while nothing is held.
func _fill_hold() -> void:
	for c in _summary_flow.get_children():
		_summary_flow.remove_child(c)
		c.queue_free()
	for def: TalentDef in summary_talents():
		for form in range(2):
			var n := Save.talent_count(def.id, form)
			if n <= 0:
				continue
			var chip := form_plate(def, form, R_CHIP)
			chip.name = "Chip_%s_%d" % [def.id, form]
			chip.level_plaque = n
			chip.set_meta("count", n)
			_summary_flow.add_child(chip)
	if _summary_flow.get_child_count() == 0:
		var hint := W.serif_text("Nothing bought yet: every rank you buy shows here.", R_HINT_PX, W.INK_SOFT, 400, false,
			HORIZONTAL_ALIGNMENT_LEFT, R_CHIP, false, false)
		hint.name = "Hint"
		var room := _summary_flow.custom_minimum_size.x
		if hint.text_width() > room:
			hint.font_size = maxi(int(floorf(R_HINT_PX * room / hint.text_width())), R_REFUND_MIN_PX)
		_summary_flow.add_child(hint)


## The refund line under RESET UPGRADES (the mock's "150 of the 300 spent comes back · every rank is forgotten", today's
## maths: Save.talent_refund of Save.talent_spent), on two lines; "Nothing to take back" and the button locked while the
## board holds nothing (a tap on it says so, as the Wanted link's does).
func _fill_refund() -> void:
	for c in _refund_box.get_children():
		_refund_box.remove_child(c)
		c.queue_free()
	var spent := Save.talent_spent()
	_reset.locked = spent <= 0
	if spent <= 0:
		_refund_box.add_child(_refund_line([["Nothing to take back", null]]))
		return
	var bold := R.body(R.LABEL_WEIGHT)
	_refund_box.add_child(_refund_line([[W.num(Save.talent_refund()), R.GOLD_TEXT, bold], [" of the ", null],
		[W.num(spent), R.GOLD_TEXT, bold], [" spent comes back", null]]))
	_refund_box.add_child(_refund_line([["every rank is forgotten", null]]))


func _refund_line(runs: Array) -> WText:
	var t := W.text("", R.body(R.BODY_WEIGHT), R_REFUND_PX, R.SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	t.name = "RefundLine"
	t.runs = runs
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# a long purse's numbers: the line set smaller to its column (a run's own size is not used here)
	var w := t.text_width()
	if _refund_w > 0.0 and w > _refund_w:
		t.font_size = maxi(int(floorf(R_REFUND_PX * _refund_w / w)), R_REFUND_MIN_PX)
	return t


## One talent's tile: its name and RANK n / 6, both options (frame, name, line), "or" between, the pips, CHOOSE.
func _tile_royale(def: TalentDef) -> PanelContainer:
	var locked := not Registry.is_unlocked("talent", def.id)
	var picks := Save.talent_picks(def.id)
	var rank := picks.size()
	var tile := PanelContainer.new()
	tile.name = "Talent_" + def.id
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var e := float(R.PANEL_EDGE)
	tile.add_theme_stylebox_override("panel", W.box(W.PAPER, R.PANEL_EDGE, R.PANEL_BASE).pad(R_TILE_PAD.x + e,
		R_TILE_PAD.y + e, R_TILE_PAD.x + e, R_TILE_FOOT + e + float(R.BUTTON_BASE + R.BUTTON_NAVY_BASE)))
	tile.custom_minimum_size.y = R_TILE_H
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.set_meta("rank", rank)
	var v := VBoxContainer.new()
	v.name = "Stack"
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := W.slab_text(def.display_name, R_NAME_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(R_NAME_PX))
	n.name = "Name"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(n)
	var rk := W.label("Rank %d / %d" % [rank, def.max_rank()], R_RANK_PX, W.INK_SOFT, 0.14)
	rk.name = "Rank"
	rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(rk)
	v.add_child(head)
	v.add_child(_spacer(R_HEAD_GAP, false))
	# pass 123 (Garry: "Looks way too busy right now"): two plain rows, bare icons and one short line each, no boxes or
	# "or" between them (the pop-up says what to choose and the whole of each option)
	v.add_child(_form_row(def, 0))
	v.add_child(_spacer(R_FORM_ROW_GAP, false))
	v.add_child(_form_row(def, 1))
	v.add_child(_spacer(R_PIPS_GAP, true))
	if locked:
		var q := Registry.quest_for("talent", def.id)
		var ql := W.serif_text(TextGen.quest_text(q) if q else "Locked", R_FORM_LINE_PX, W.INK_SOFT, 400, false,
			HORIZONTAL_ALIGNMENT_LEFT, R_FORM_LINE_LH, true)
		ql.name = "Quest"
		ql.custom_minimum_size.y = R_PIP.y
		v.add_child(ql)
	else:
		var track := PipTrack.new()
		track.setup(def, picks, R_PIP, R_PIP_GAP)
		v.add_child(track)
	v.add_child(_spacer(R_CHOOSE_GAP, false))
	v.add_child(_choose_row(def, rank, locked))
	return tile


## An option's row on a tile: its icon in a common frame, its name, and TextGen's line for one rank (form_line).
func _form_row(def: TalentDef, form: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Form%d" % form
	row.add_theme_constant_override("separation", R_FORM_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = R_FORM
	var plate := TextureRect.new()
	plate.name = "Frame"
	plate.texture = def.form_icon(form)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate.custom_minimum_size = Vector2(R_FORM, R_FORM)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(plate)
	var words := VBoxContainer.new()
	words.name = "Words"
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := W.text(def.form_name(form), R.body(R.LABEL_WEIGHT), R_FORM_NAME_PX, R.WHITE, HORIZONTAL_ALIGNMENT_LEFT, R_FORM_NAME_LH)
	nm.name = "FormName"
	words.add_child(nm)
	var line := W.serif_text(form_line(def, form).trim_suffix(" per rank"), R_FORM_LINE_PX, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT,
		R_FORM_LINE_LH, true)
	line.name = "Effect"
	words.add_child(line)
	row.add_child(words)
	return row


## A tile's button: the blue "● price · CHOOSE" (the next rank's price, Save.talent_picks' count); short of gold the kit's
## short state (pass 124, Garry: "we just show the grayed button with red text for coins amount"); MAXED at the last rank (a tap still opens
## what the ranks hold); LOCKED while the talent's quest is open (a tap says so). Named "Choose".
func _choose_row(def: TalentDef, rank: int, locked: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ChooseRow"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", R.SHORT_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var e := R.BUTTON_EDGE
	var pad_v := maxf((R_CHOOSE_H - 2.0 * e - R_CHOOSE_PX) * 0.5, 0.0)
	var cost := def.cost_of_rank(rank)
	var short := 0
	var b: WButton
	if locked:
		b = WButton.make(["LOCKED"], R_CHOOSE_PX, WButton.SECONDARY, e, R.BUTTON_BASE, pad_v, 22.0, float(R_CHOOSE_PX), WButton.LOCKED)
		b.locked = true
		b.pressed.connect(func(): Audio.play("ui_locked"))
	elif rank >= def.max_rank() or cost < 0:
		b = WButton.make(["MAXED"], R_CHOOSE_PX, WButton.SECONDARY, e, R.BUTTON_BASE, pad_v, 22.0, float(R_CHOOSE_PX), WButton.LOCKED)
		b.locked = true
		b.pressed.connect(_open.bind(def))
	else:
		var cur := Currency.of(def.currency_type)
		short = maxi(cost - Currency.balance(cur), 0)
		b = WButton.price(cost, "CHOOSE", WButton.BLUE, R_CHOOSE_PX, short, cur, false, R_CHOOSE_H)
		b.pressed.connect(_open.bind(def))
	b.name = "Choose"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	return row


# --- the CHOOSE pop-up --------------------------------------------------------------------------------------------------

## The talent's choice in the shared modal shell (WConfirm.shell): the next rank's number, the name, the flavour, what the
## ranks hold, the pips, both options with their BUY, CLOSE. One BUY buys the next rank in its option, as the Wanted
## sheet's Buy0 / Buy1 do, and the pop-up stays with the rank after (as the sheet did).
func _open_choice(def: TalentDef) -> void:
	if _choice:
		_close_choice()
	_choice = WConfirm.shell(self, {"buttons": [{"id": "cancel", "text": "Close", "role": WButton.SLATE}],
		"button_h": R_POP_CLOSE_H, "button_px": R_POP_CLOSE_PX, "on_answer": _on_choice_answer})
	_choice.name = "Choice"
	_sheet_root = _choice
	_sheet_def = def
	_fill_choice()


## The shell answered (CLOSE, the dim, the back gesture, Esc): nothing open any more.
func _on_choice_answer(_id: String) -> void:
	_choice = null
	_sheet_root = null
	_sheet_def = null


func _close_choice() -> void:
	var c := _choice
	_on_choice_answer("cancel")
	if is_instance_valid(c):
		c.cancel()


## The pop-up's rows again (on opening and after a buy). Its rows sit in one VBox named "Sheet" (as the Wanted sheet).
func _fill_choice() -> void:
	if _choice == null or _sheet_def == null or not is_instance_valid(_choice):
		return
	var def := _sheet_def
	var box := _choice.body_box
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var picks := Save.talent_picks(def.id)
	var rank := picks.size()
	var full := rank >= def.max_rank() or def.cost_of_rank(rank) < 0
	var v := VBoxContainer.new()
	v.name = "Sheet"
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	var star := WConfirm.make_star("Maxed" if full else "Rank %d of %d" % [rank + 1, def.max_rank()])
	star.name = "Star"
	v.add_child(star)
	v.add_child(WConfirm.make_title(def.display_name.to_upper(), 64))
	var flav := W.serif_text(def.flavour, 26, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true)
	flav.name = "Flavour"
	flav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(flav)
	# what the ranks give now (the Wanted sheet's status line: the ranks summed by option, out of how many)
	var now := "No ranks yet"
	if rank > 0:
		now = "Rank %d of %d owned · %s" % [rank, def.max_rank(), TextGen.describe_effects(held_effects(def))]
	var status := W.serif_text(now, 24, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true)
	status.name = "Status"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(status)
	var pips := CenterContainer.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := PipTrack.new()
	track.setup(def, picks, R_POP_PIP, R_POP_PIP_GAP)
	pips.add_child(track)
	v.add_child(pips)
	for form in range(2):
		v.add_child(_choice_row(def, form, rank, full))
	_fill_purse()
	if not full:
		# pass 63's rule in words (Garry's name for the reset)
		var note := W.serif_text("Choose one. It stays; Reset Upgrades is the only way to choose again.", 22, W.INK_SOFT,
			400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true)
		note.name = "ChoiceNote"
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(note)


## The purse in the pop-up's top-right corner, level with its star line (the header's wallet sits under the 80 % dim): a
## black info pill with the coin and the purse, again after every buy. An overlay on the shell's card ("Purse"), so the
## card's rows are laid out as they are.
func _fill_purse() -> void:
	var card := _choice.card
	var over := card.get_node_or_null("Purse") as Control
	if over == null:
		over = Control.new()
		over.name = "Purse"
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(over)
	for c in over.get_children():
		over.remove_child(c)
		c.queue_free()
	var cur := Currency.of(_sheet_def.currency_type) if _sheet_def else "gold"
	var pill := W.pill([{"coin": R_POP_PURSE_COIN, "currency": cur}, W.num(Currency.balance(cur))], R.PILL_PX, R.PILL_H)
	pill.name = "PursePill"
	pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	over.add_child(pill)


## One option in the pop-up, in a solid cell: its frame, its name, its line for one rank, how many it holds, and its
## green BUY for the next rank ("Buy0" / "Buy1"; the kit's short state: grey with the price in red; none at MAXED).
func _choice_row(def: TalentDef, form: int, rank: int, full: bool) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "Offer%d" % form
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_theme_stylebox_override("panel", W.cell_box(Vector2(18, 16)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(row)
	var plate := form_plate(def, form, R_POP_FORM)
	plate.name = "Frame"
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(plate)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 4)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(W.slab_text(def.form_name(form), R_POP_NAME_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(R_POP_NAME_PX)))
	var line := W.serif_text(form_line(def, form), R_POP_LINE_PX, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	line.name = "Effect"
	words.add_child(line)
	var said := W.serif_text(_short_static(def.form_text(form)), 22, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	said.name = "Words"
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(said)
	var held := Save.talent_count(def.id, form)
	if held > 0:
		var owned := W.serif_text("%d owned" % held, 22, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		owned.name = "Owned"
		words.add_child(owned)
	row.add_child(words)
	if not full:
		var cost := def.cost_of_rank(rank)
		var cur := Currency.of(def.currency_type)
		var short := maxi(cost - Currency.balance(cur), 0)
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", R.BUTTON_BASE + R.BUTTON_NAVY_BASE + 2)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b := WButton.price(cost, "BUY", WButton.GREEN, R.PRICE_PX, short, cur, false, R_POP_BUY_H)
		b.name = "Buy%d" % form
		b.custom_minimum_size.x = R_POP_BUY_W
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.pressed.connect(_buy_form.bind(def, form))
		right.add_child(b)
		row.add_child(right)
	return cell


## A BUY in the pop-up: the next rank in `form` for its price (Save.buy_talent: it keeps that form), the board and the
## wallet again, the pop-up again with the rank after; short of gold it only says so (the Wanted sheet's Buy0 / Buy1).
func _buy_form(def: TalentDef, form: int) -> void:
	var cost := def.cost_of_rank(Save.talent_rank(def.id))
	if cost < 0 or not Currency.can_afford(def.currency_type, cost):
		Audio.play("ui_locked")
		return
	if Save.buy_talent(def, form):
		Audio.play("ui_buy")
		_refresh()
		# after the press that asked has finished (its button goes with the rows)
		_fill_choice.call_deferred()
	else:
		Audio.play("ui_locked")


## A form's line for one rank on the Royale board and in its pop-up (pass 123; the task: "its effect line from data:
## TextGen of the form's effects, 'per rank'"): TextGen's words for one rank ("+10% max HP per rank"), effects that share
## a number and their stat's first words said once (Stakes: "+10% enemy HP and attack, +4% enemy speed per rank"); a form
## whose ranks differ (rank_effects) says its next rank's step ("... next rank"); the form's own words when TextGen has
## none for it.
static func form_line(def: TalentDef, form: int) -> String:
	if form < 0 or form >= def.forms.size():
		return ""
	var s := ""
	var rl = (def.forms[form] as Dictionary).get("rank_effects", [])
	if rl is Array and not (rl as Array).is_empty():
		var n := Save.talent_count(def.id, form)
		var step: Array = (rl as Array)[n] if n < (rl as Array).size() and (rl as Array)[n] is Array else []
		s = grouped_text(step)
		if s != "":
			return s + " next rank"
	else:
		s = grouped_text(def.summed_effects(form, 1))
		if s != "":
			return s + " per rank"
	return _short_static(def.form_text(form))


static func _short_static(t: String) -> String:
	return t.strip_edges().trim_suffix(".")


## TextGen.describe_effects of `list`, with effects that share a number and read "<number> <stat name>" joined ("+10%
## enemy HP, +10% enemy attack" -> "+10% enemy HP and attack"); anything else (a rule, a count's singular, a prefix, a
## weapon target) exactly as TextGen says it.
static func grouped_text(list: Array) -> String:
	var parts: Array = []
	for e in list:
		if not (e is Effect):
			continue
		var full := TextGen.describe_effect(e, true)
		if full == "":
			continue
		var num := TextGen.describe_effect(e, false)
		var nm := TextGen.stat_name(e.stat)
		var plain := num != "" and full == num + " " + nm
		if plain and not parts.is_empty() and str((parts.back() as Array)[2]) == "" and str((parts.back() as Array)[0]) == num:
			((parts.back() as Array)[1] as Array).append(nm)
		else:
			parts.append([num, [nm], "" if plain else full])
	var out: Array = []
	for p: Array in parts:
		out.append(str(p[2]) if str(p[2]) != "" else str(p[0]) + " " + joined_names(p[1]))
	return ", ".join(out)


## Stat names said once over their shared first words: ["enemy HP", "enemy attack"] -> "enemy HP and attack",
## ["boss and Elite HP", "boss and Elite attack"] -> "boss and Elite HP and attack"; with no shared words "a and b".
static func joined_names(names: Array) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return str(names[0])
	var first := str(names[0]).split(" ")
	var common := first.size() - 1
	for n in names:
		var w := str(n).split(" ")
		var k := 0
		while k < common and k < w.size() - 1 and w[k] == first[k]:
			k += 1
		common = k
	var tails: Array = []
	for n in names:
		tails.append(" ".join(str(n).split(" ").slice(common)))
	var said := ", ".join(tails.slice(0, tails.size() - 1)) + " and " + str(tails.back())
	return (" ".join(first.slice(0, common)) + " " + said) if common > 0 else said


## The rank track, one pip a rank (pass 123, Royale; the mock's 56 x 44 pips; Garry: "Filled rank pips show the chosen option's
## icon"): a bought rank a small common frame (a navy edge round the common grey, its lip) with the icon of the option it
## was bought in (Save.talent_picks; the option's initial when it has no icon), the rest the mock's empty pips (see-through
## black in a navy edge, a dashed line inside). One Control drawn in one pass, only when built. Named "RankBar"; its meta
## "picks" the options rank by rank.
class PipTrack extends Control:
	var picks: Array = []
	var icons: Array = [null, null]
	var initials: Array = ["", ""]
	var ranks := 6
	var pip := Vector2(56, 44)
	var gap := 8.0
	var _edge: StyleBoxFlat

	func setup(def: TalentDef, p_picks: Array, p_pip: Vector2, p_gap: float) -> void:
		name = "RankBar"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		picks = p_picks.duplicate()
		ranks = def.max_rank()
		pip = p_pip
		gap = p_gap
		for f in range(2):
			icons[f] = def.form_icon(f)
			initials[f] = def.form_name(f).left(1)
		set_meta("picks", picks.duplicate())
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		custom_minimum_size = Vector2(ranks * pip.x + maxi(ranks - 1, 0) * gap, pip.y)
		_edge = StyleBoxFlat.new()
		_edge.draw_center = false
		_edge.set_border_width_all(R_PIP_EDGE)
		_edge.border_color = R.NAVY
		_edge.set_corner_radius_all(R.RADIUS_TAG)
		_edge.anti_aliasing = true

	func pip_rect(k: int) -> Rect2:
		return Rect2(Vector2(k * (pip.x + gap), 0.0), pip)

	func _draw() -> void:
		var ci := get_canvas_item()
		var common: Dictionary = R.RARITY["common"]
		var e := float(R_PIP_EDGE)
		for k in ranks:
			var r := pip_rect(k)
			var face := r.grow(-e)
			if k < picks.size():
				R.flat(R.NAVY, R.RADIUS_TAG).draw(ci, r)
				R.gradient(ci, face, [[0.0, common["light"]], [0.55, common["base"]], [1.0, common["dark"]]])
				R.lip(ci, face, R.FRAME_LIP, 2)
				var f := clampi(int(picks[k]), 0, 1)
				var tex: Texture2D = icons[f]
				var inner := face.grow(-3.0)
				if tex:
					var ts := tex.get_size()
					var kk := minf(inner.size.x / ts.x, inner.size.y / ts.y)
					var sz := ts * kk
					var at := inner.position + (inner.size - sz) * 0.5
					draw_texture_rect(tex, Rect2(at + Vector2(0, 2), sz), false, R.FRAME_ICON_DROP)
					draw_texture_rect(tex, Rect2(at, sz), false)
				else:
					var gpx := int(inner.size.y * 0.7)
					var gf := W.slab_for(gpx)
					var gw := gf.get_string_size(str(initials[f]), HORIZONTAL_ALIGNMENT_LEFT, -1, gpx).x
					var base := inner.get_center().y - gf.get_height(gpx) * 0.5 + gf.get_ascent(gpx)
					draw_string(gf, Vector2(inner.get_center().x - gw * 0.5, base), str(initials[f]), HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, R.NAVY)
			else:
				# pass 123 (Garry: too busy): an empty pip is a plain dark slot, no edge and no dashes
				R.flat(R_PIP_EMPTY, R.RADIUS_TAG).draw(ci, r)
