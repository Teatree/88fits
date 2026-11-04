## The play-data card (pass 59, Garry: the consent card before the first tester who is not him): the first time a build
## that can send starts (a key in game/config/analytics.json, `Analytics.consent_needed()`), the title shows this card
## over an ink dim. It says in plain words what goes and under which name, and asks once: OK or No thanks.
## The answer is kept in the save (`Save.consent()`, through a wipe) and Settings' "Anonymous play data" switch is the
## answer from then on. Until it is answered nothing is sent or written to disk (`Analytics.awaiting_consent`); a tap on
## the dim does nothing (the card wants an answer); the back gesture leaves it unanswered, and it comes again next launch.
## No class_name: open it with preload("res://ui/wanted/WConsent.gd").open(host). Buttons "Decline" and "Accept".
## Pass 123 (lane RUN_C), under Royale (Garry: "Consent and survey pop-ups in the shared pop-up shell, as the
## mock", "White header"): the card is the kit's modal shell (WConfirm's pieces, the mock 10_Consent): the slate panel
## R.MODAL_W wide over the 80 % black dim, "★ A QUICK WORD ★" in gold Ultra, PLAY DATA in cream Ultra 72, the words in
## white Rubik 500 28, no rule, NO THANKS slate · OK gold 106 tall on the card's foot, the card at least CONSENT_MIN_H
## tall with its top R.MODAL_TOP_AT of the room above and below it. The words, the names, the answer and the dim that
## wants an answer are today's; Wanted is built as before.
extends Control

signal answered(yes: bool)

const WIDTH_INSET := 60.0
## The Royale card's least height (the mock's 10_Consent: 624 canvas px).
const CONSENT_MIN_H := 620.0
## The Royale body's margin either side (the shell's 20 for a long line).
const ROYALE_BODY_MARGIN := 20

var card: PanelContainer
var dim: ColorRect
var accept_btn: WButton
var decline_btn: WButton
var _done := false


static func open(host: Control) -> Control:
	var c: Control = load("res://ui/wanted/WConsent.gd").new()
	c.name = "Consent"
	c.call("_build")
	host.add_child(c)
	c.call("_enter")
	return c


## The words on the card (tests read them). Pass 60 (Garry: "make the text simpler please. Don't mention me"): plain
## words, no maker; the player's name stays, so they can find themselves.
static func body_text(player_name: String) -> String:
	return ("The game sends what happens in your runs (the items you pick, where you fall, how smoothly it runs) so it "
		+ "can get better. You appear there only as \"%s\": no account, no location, nothing else about you. "
		+ "Now and then it asks a few quick questions after a run. Both can be turned off in Settings.") % player_name


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wanted_modal")


func _build() -> void:
	_build_royale()
	return


## The Royale card (pass 123): the kit's modal shell, built from WConfirm's pieces so the card keeps its own names, its
## answer and its dim that wants one.
func _build_royale() -> void:
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = W.dim_color("ask")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", WConfirm.card_box())
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var inset := (1080.0 - float(R.MODAL_W)) * 0.5
	card.offset_left = inset
	card.offset_right = -inset
	card.offset_top = 700
	card.custom_minimum_size.y = CONSENT_MIN_H
	add_child(card)
	var v := VBoxContainer.new()
	v.name = "Stack"
	v.add_theme_constant_override("separation", R.MODAL_GAP)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(WConfirm.make_star("A quick word"))
	v.add_child(WConfirm.make_title("PLAY DATA"))
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", ROYALE_BODY_MARGIN)
	m.add_theme_constant_override("margin_right", ROYALE_BODY_MARGIN)
	m.add_child(WConfirm.make_body(body_text(Save.player_name())))
	v.add_child(m)
	# the buttons on the card's foot
	var gap := Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", R.MODAL_BUTTON_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	decline_btn = WConfirm.make_button(["NO THANKS"], WButton.SLATE)
	decline_btn.name = "Decline"
	decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_btn.pressed.connect(func(): answer(false))
	row.add_child(decline_btn)
	accept_btn = WConfirm.make_button(["OK"], WButton.GOLD)
	accept_btn.name = "Accept"
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_btn.pressed.connect(func(): answer(true))
	row.add_child(accept_btn)


## Where the card's top rests once it has laid out `h` tall in a room `vh` tall: the middle under Wanted, the kit's
## R.MODAL_TOP_AT of the room above and below it under Royale (the mock's), never under the camera cutout.
static func rest_top(h: float, vh: float) -> float:
	return maxf((vh - h) * R.MODAL_TOP_AT, W.safe_top() + 20.0)


## WConfirm's entry: the dim fades in, the card slides up 60 px and fades in, centred once its lines have laid out.
func _enter() -> void:
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	card.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _done or not is_inside_tree():
		return
	var h := maxf(card.size.y, card.get_combined_minimum_size().y)
	var y := rest_top(h, get_viewport_rect().size.y)
	card.offset_top = y + 60.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "offset_top", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)


## The answer: kept, handed to Analytics (yes sends what waited, no deletes it), and the card goes.
func answer(yes: bool) -> void:
	if _done:
		return
	_done = true
	Analytics.answer_consent(yes)
	Audio.play("ui_tap")
	answered.emit(yes)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(queue_free)


func is_done() -> bool:
	return _done
