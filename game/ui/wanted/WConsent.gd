## The play-data card (pass 59, Garry: the consent card before the first tester who is not him): the first time a build
## that can send starts (a key in game/config/analytics.json, `Analytics.consent_needed()`), the title shows this card
## over an ink dim. It says in plain words what goes and under which name, and asks once: OK or No thanks.
## The answer is kept in the save (`Save.consent()`, through a wipe) and Settings' "Anonymous play data" switch is the
## answer from then on. Until it is answered nothing is sent or written to disk (`Analytics.awaiting_consent`); a tap on
## the dim does nothing (the card wants an answer); the back gesture leaves it unanswered, and it comes again next launch.
## No class_name: open it with preload("res://ui/wanted/WConsent.gd").open(host). Buttons "Decline" and "Accept".
extends Control

signal answered(yes: bool)

const WIDTH_INSET := 60.0

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
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = W.DIM_ASK
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(50, 44, 50, 44))
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	card.offset_left = WIDTH_INSET
	card.offset_right = -WIDTH_INSET
	card.offset_top = 700
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(WStarLine.make("A quick word", 24, W.INK_SOFT))
	var t := W.text("PLAY DATA", W.slab(), 64, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 64.0, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(t)
	var b := W.serif_text(body_text(Save.player_name()), 30, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 39.0, true, false)
	b.name = "Body"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	var rule := ColorRect.new()
	rule.color = W.INK
	rule.custom_minimum_size.y = 4
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	decline_btn = WButton.make(["NO THANKS"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	decline_btn.name = "Decline"
	decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_btn.pressed.connect(func(): answer(false))
	row.add_child(decline_btn)
	accept_btn = WButton.make(["OK"], 34, WButton.PRIMARY, 5, 8, 26.0, 0.0)
	accept_btn.name = "Accept"
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_btn.pressed.connect(func(): answer(true))
	row.add_child(accept_btn)


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
	var y := (get_viewport_rect().size.y - h) * 0.5
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
