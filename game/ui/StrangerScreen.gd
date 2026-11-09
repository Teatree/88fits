## The Stranger's bargain (Wanted screen 12). A plum-black dim, "★ NO NAME ★ / THE STRANGER", his cut-out holding the
## item out (a placeholder until the art is painted: art/ui/wanted/stranger.png), his one line, and the deal panel: the
## item as a card and, under a rule, THE PRICE: max HP for the rest of the run as a bar losing its end in hatched rock,
## "110 → 94". WALK AWAY or DEAL; either way he is gone afterwards and only his cloak is left on the sand.
## Pass 123 (lane RUN_B), under Royale: the mock 8_Stranger with Garry's
## note ("Stranger as the mock: one deal card, THE PRICE as a bar with the lost part hatched red, WALK AWAY slate, DEAL
## gold"; "Use the style, 'Walk Away' should be red and make the sizes bigger. Also Header text should be white."): the
## gold star line over THE STRANGER in cream Ultra, fitted to the screen (it ran off it at 120 px); his figure and his
## line as today; one slate deal card: the kind "PASSIVE EPIC · STRAIGHT TO LV 2" with the tag right after it, the frame
## (ROYALE_PLATE), the name (ROYALE_NAME_PX), the stars, the full text (ROYALE_EFFECT_PX), a faint rule, THE PRICE in red
## with the max HP "105 → 89" (the white number, the red one) in Ultra ROYALE_NUMS_PX, the bar ROYALE_BAR_H tall with the
## lost part hatched red (WBar's loss), the "No reroll ..." line; WALK AWAY red and DEAL gold, equal halves, ROYALE_BUTTON_H
## tall in Ultra ROYALE_BUTTON_PX (bigger than the mock's 106 / 38, Garry).
class_name StrangerScreen
extends WModal

signal closed(took: bool)

## Pass 123 (lane RUN_B), the Royale sizes: the title's room either side, the deal card's frame, name and text, the
## price's numbers, label and bar, the buttons' height and type.
const ROYALE_TITLE_SIDE := 40.0
const ROYALE_PLATE := 170.0
const ROYALE_NAME_PX := 60
const ROYALE_EFFECT_PX := 30
const ROYALE_NUMS_PX := 40
const ROYALE_LABEL_PX := 22
const ROYALE_BAR_H := 34.0
const ROYALE_NOTE_PX := 24
const ROYALE_BUTTON_H := 132.0
const ROYALE_BUTTON_PX := 48
## the rule between the item and the price: R.WHITE at this alpha, 2 px (the mock's hairline)
const ROYALE_RULE_ALPHA := 0.12

var _portrait: WPlaceholder
var _quote: WText
var _panel: PanelContainer
var _card_host: VBoxContainer
var _price_label: WText
var _price_nums: WText
var _bar: WBar
var _offer: Dictionary = {}
## pass 123: built under Royale (the buttons' height the layout keeps clear of)


func _ready() -> void:
	build_dim(W.DIM_STRANGER)
	build_header(Loc.t("ui.stranger.star"), Loc.t("ui.stranger.title"), "", 120, W.PAPER, 60.0, W.AGED)
	# pass 123: Ultra is wider than Alfa Slab: the title fitted to the screen, in cream (Garry: "Header text should be
	# white"), the star line the kit's gold
	header.set_title_fit(Loc.t("ui.stranger.title"), 120, W.PAPER, get_viewport_rect().size.x - 2.0 * ROYALE_TITLE_SIDE)
	header.set_star(Loc.t("ui.stranger.star"), W.PAPER)
	_portrait = WPlaceholder.make("stranger", "the Stranger, hooded, camera-facing cut-out\n840 × 660 · holding the item out", Vector2(840, 660), true)
	_portrait.position = Vector2(120, 320 + W.safe_top())
	add_child(_portrait)
	_quote = W.serif_text(Loc.t("ui.stranger.quote"), 34, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_quote.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# under a camera cutout the quote and the panel move down with the portrait (pass 60; the header already does)
	_quote.offset_top = 1012 + W.safe_top()
	_quote.offset_bottom = 1012 + 41 + W.safe_top()
	add_child(_quote)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 10).pad(40, 36, 40, 36))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_top = 1100 + W.safe_top()
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	_card_host = VBoxContainer.new()
	_card_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_card_host)
	# the rule and the price
	var rule := ColorRect.new()
	rule.color = Color(R.WHITE, ROYALE_RULE_ALPHA)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	var price := VBoxContainer.new()
	price.add_theme_constant_override("separation", 10)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(price)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price_label = W.label(Loc.t("ui.stranger.price"), ROYALE_LABEL_PX, W.ROCK)
	_price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_price_label)
	# pass 123: the max HP as the mock's numbers: what it is in white, what it will be in red, Ultra with the edge
	_price_nums = W.slab_text("110 → 94", ROYALE_NUMS_PX, W.PAPER, HORIZONTAL_ALIGNMENT_RIGHT, float(ROYALE_NUMS_PX))
	_price_nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_nums.name = "PriceNumbers"
	row.add_child(_price_nums)
	price.add_child(row)
	_bar = WBar.make(0.85, W.SAGE, ROYALE_BAR_H, 4, 0)
	price.add_child(_bar)
	price.add_child(W.serif_text(Loc.t("ui.stranger.note"), ROYALE_NOTE_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var bh := ROYALE_BUTTON_H
	build_buttons(bh)
	var refuse: WButton
	var deal: WButton
	# pass 123 (Garry): WALK AWAY red (he is gone for good), DEAL gold, both bigger than the mock's, equal halves
	var pad := maxf((bh - 2.0 * R.BUTTON_EDGE - float(ROYALE_BUTTON_PX)) * 0.5, 0.0)
	refuse = WButton.make([Loc.t("ui.stranger.walk_away")], ROYALE_BUTTON_PX, WButton.DANGER, R.BUTTON_EDGE, R.BUTTON_BASE, pad, 0.0, float(ROYALE_BUTTON_PX), WButton.RED)
	deal = WButton.make([Loc.t("ui.stranger.deal")], ROYALE_BUTTON_PX, WButton.PRIMARY, R.BUTTON_EDGE, R.BUTTON_BASE, pad, 0.0, float(ROYALE_BUTTON_PX), WButton.GOLD)
	refuse.name = "WalkAway"
	refuse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refuse.pressed.connect(func(): _finish(false))
	buttons.add_child(refuse)
	deal.name = "Deal"
	deal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deal.pressed.connect(func(): _finish(true))
	buttons.add_child(deal)


## `offer` is a card like the reel's ({type, id, def, level_from, level_to, is_new}); `hp_cost` a fraction of max HP.
func open(offer: Dictionary, hp_cost: float) -> void:
	_offer = offer
	for c in _card_host.get_children():
		c.queue_free()
	var def: ContentDef = offer.get("def")
	if def:
		var o := WItem.options(offer, {"bare": true, "rivet": false, "plate_px": 170.0, "seal_px": 92.0, "seal_at": Vector2(0, -10),
			"text_right": 100, "icon_frac": 0.72})
		# pass 123: the mock's sizes, made bigger (Garry); the text runs the card's width (no seal to keep room for)
		o["plate_px"] = ROYALE_PLATE
		o["name_size"] = ROYALE_NAME_PX
		o["effect_size"] = ROYALE_EFFECT_PX
		o["text_right"] = 0
		var lt := int(offer.get("level_to", 1))
		if lt - int(offer.get("level_from", 0)) > 1:
			o["word"] = Loc.t("ui.stranger.straight_to_level", {"kind": W.kind_of(def).to_upper(), "level": str(lt)})
		var card := WCard.make(def, o)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		StructureShop.tag_after_word(card)
		_royale_word(card, str(o.get("word", "")))
		# the mock's frame stands at the card's top, beside the kind's words
		card.plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_card_host.add_child(card)
	var mx := 100.0
	if Run.player_sheet:
		mx = Run.player_sheet.get_stat("max_hp", 100.0)
	var after := int(round(mx * (1.0 - hp_cost)))
	_price_nums.text = "%s → %s" % [W.num(int(round(mx))), W.num(after)]
	# the arrow keeps a face that has it (Ultra and Rubik carry no →: WCard's change rows keep Bitter for it)
	var arrow_font: Font = W._variant(W.SERIF_PATH, 700, 0)
	_price_nums.runs = [[W.num(int(round(mx))), R.CREAM], [" → ", R.CREAM, arrow_font, ROYALE_NUMS_PX],
		[W.num(after), R.role("red")["top"]]]
	_bar.value = 1.0 - hp_cost
	_bar.loss = hp_cost
	modulate.a = 1.0
	_fit_layout()
	enter()
	Audio.play("ui_pause")
	# the card's wrapped text knows its height only once the containers have sorted: fit again then
	await get_tree().process_frame
	if is_instance_valid(self) and visible:
		_fit_layout()


## Pass 76 (the Totem brief's capture showed it): under a camera cutout the deal panel ran under WALK AWAY / DEAL. The
## panel and the quote rise by what would overlap the buttons (a gap of BUTTON_GAP above them) and the portrait shrinks
## by as much (about its top middle), never below PORTRAIT_MIN of its size; on a phone without a cutout nothing moves.
const BUTTON_GAP := 24.0
const PORTRAIT_MIN := 0.6


func _fit_layout() -> void:
	var top := W.safe_top()
	var h := get_viewport_rect().size.y
	var limit := h - 90.0 - (ROYALE_BUTTON_H) - BUTTON_GAP
	var panel_h := maxf(_panel.get_combined_minimum_size().y, _panel.size.y)
	var shift := clampf(1100.0 + top + panel_h - limit, 0.0, 660.0 * (1.0 - PORTRAIT_MIN))
	_panel.offset_top = 1100.0 + top - shift
	_quote.offset_top = 1012.0 + top - shift
	_quote.offset_bottom = 1012.0 + 41.0 + top - shift
	var s := (660.0 - shift) / 660.0
	_portrait.scale = Vector2(s, s)
	_portrait.position = Vector2(120.0 + 840.0 * (1.0 - s) * 0.5, 320.0 + top)


## Pass 123: the deal card's kind as the mock's line under Royale: the kind, a passive item's rarity right after it in its
## light colour (the frame's, WCard.royale_word's rule), then what the deal does (" · STRAIGHT TO LV 2"), so the rarity
## no longer trails the deal's words.
func _royale_word(card: WCard, word: String) -> void:
	var wl := card.find_child("WordLine", true, false)
	if wl == null or wl.get_child_count() == 0 or not (wl.get_child(0) is WText):
		return
	var parts := word.to_upper().split(" · ")
	var runs: Array = [[parts[0], R.SECONDARY]]
	var named := ""
	var rest: Array = []
	for i in range(1, parts.size()):
		if R.RARITY.has(parts[i].to_lower()):
			named = parts[i]
		else:
			rest.append(parts[i])
	if named == "" and card.def and W.kind_of(card.def) == "passive" and card.plate:
		var fr := card.plate.frame_rarity()
		if R.RARITY.has(fr) and fr != "evolved":
			named = fr.to_upper()
	if named != "":
		runs.append([" " + named, R.RARITY[named.to_lower()]["light"]])
	for seg in rest:
		runs.append([" · " + str(seg), R.SECONDARY])
	(wl.get_child(0) as WText).runs = runs


func result() -> Dictionary:
	return _offer


func _finish(took: bool) -> void:
	if not visible:
		return
	RunReplay.note("stranger", {"took": took})
	visible = false
	closed.emit(took)
