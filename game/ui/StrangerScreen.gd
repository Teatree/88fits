## The Stranger's bargain (Wanted screen 12). A plum-black dim, "★ NO NAME ★ / THE STRANGER", his cut-out holding the
## item out (a placeholder until the art is painted: art/ui/wanted/stranger.png), his one line, and the deal panel: the
## item as a card and, under a rule, THE PRICE: max HP for the rest of the run as a bar losing its end in hatched rock,
## "110 → 94". WALK AWAY or DEAL; either way he is gone afterwards and only his cloak is left on the sand.
class_name StrangerScreen
extends WModal

signal closed(took: bool)

var _portrait: WPlaceholder
var _quote: WText
var _panel: PanelContainer
var _card_host: VBoxContainer
var _price_label: WText
var _price_nums: WText
var _bar: WBar
var _offer: Dictionary = {}


func _ready() -> void:
	build_dim(W.DIM_STRANGER)
	build_header("No name", "THE STRANGER", "", 120, W.PAPER, 60.0, W.AGED)
	_portrait = WPlaceholder.make("stranger", "the Stranger, hooded, camera-facing cut-out\n840 × 660 · holding the item out", Vector2(840, 660), true)
	_portrait.position = Vector2(120, 320 + W.safe_top())
	add_child(_portrait)
	_quote = W.serif_text("“A piece of you, for a piece of the world.”", 34, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
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
	rule.color = W.INK
	rule.custom_minimum_size = Vector2(0, 4)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	var price := VBoxContainer.new()
	price.add_theme_constant_override("separation", 10)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(price)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price_label = W.label("The price · max HP for the rest of the run", 20, W.ROCK)
	_price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_price_label)
	_price_nums = W.label("110 → 94", 20, W.ROCK)
	row.add_child(_price_nums)
	price.add_child(row)
	_bar = WBar.make(0.85, W.SAGE, 48.0, 4, 0)
	price.add_child(_bar)
	price.add_child(W.serif_text("No reroll. No second offer. He does not haggle.", 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	build_buttons(114.0)
	var refuse := WButton.make(["WALK AWAY"], 34, WButton.SECONDARY, 5, 8, 30.0, 0.0)
	refuse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refuse.pressed.connect(func(): _finish(false))
	buttons.add_child(refuse)
	var deal := WButton.make(["DEAL"], 44, WButton.PRIMARY, 5, 8, 26.0, 0.0)
	deal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deal.size_flags_stretch_ratio = 1.4
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
		var lt := int(offer.get("level_to", 1))
		if lt - int(offer.get("level_from", 0)) > 1:
			o["word"] = "%s · STRAIGHT TO LV %d" % [W.kind_of(def).to_upper(), lt]
		var card := WCard.make(def, o)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_host.add_child(card)
	var mx := 100.0
	if Run.player_sheet:
		mx = Run.player_sheet.get_stat("max_hp", 100.0)
	var after := int(round(mx * (1.0 - hp_cost)))
	_price_nums.text = "%s → %s" % [W.num(int(round(mx))), W.num(after)]
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
	var limit := h - 90.0 - 114.0 - BUTTON_GAP
	var panel_h := maxf(_panel.get_combined_minimum_size().y, _panel.size.y)
	var shift := clampf(1100.0 + top + panel_h - limit, 0.0, 660.0 * (1.0 - PORTRAIT_MIN))
	_panel.offset_top = 1100.0 + top - shift
	_quote.offset_top = 1012.0 + top - shift
	_quote.offset_bottom = 1012.0 + 41.0 + top - shift
	var s := (660.0 - shift) / 660.0
	_portrait.scale = Vector2(s, s)
	_portrait.position = Vector2(120.0 + 840.0 * (1.0 - s) * 0.5, 320.0 + top)


func result() -> Dictionary:
	return _offer


func _finish(took: bool) -> void:
	if not visible:
		return
	visible = false
	closed.emit(took)
