## The floating Wanted posters (pass 112, lane WANTED; Garry: "Wanted Poster - this should appear at the beginning of a
## run right after the descend sequence. And make it so it's not a full screen, but more like floating posters instead.
## Similar logic though."). Once the hero has landed from the spawn beam, Game._offer_bounty asks for this screen through
## the one-screen rule (Modal.BOUNTY): the run pauses under a light dim, and the board's posters (WantedBoard.board_for,
## ui/wanted/WPoster.gd) drop in on strings from the top of the screen and sway gently in mid-air, each hung by its nail.
## A tap on one takes it: it is stamped TAKEN, the others fall away, the HUD comes back and the poster flies into the
## bounty plate on the right under the item row, which pops in as it lands (`taken` first, so Game starts the contract and
## its plate; `closed` once the flight is over, and the run goes on). "No bounty" lets them all blow away (`closed({})`).
## A tool or the bot answers with choose(i) (-1 = No bounty). Rules: BALANCING.md 55.WANTED.
class_name BountyPosters
extends WModal

signal taken(contract: Dictionary)
signal closed(contract: Dictionary)

## The posters' width (the poster's own design is 316 px; three of these and two gaps fit 1080 with room either side).
const POSTER_W := 270.0
const GAP := 30.0
## The nails' height on the screen (under the call to action), and how far the strings rise above the top edge.
const NAIL_Y := 430.0
## The sway: degrees either way, swings a second (each poster its own phase and a slightly different pace), and a bob.
const SWAY_DEG := 2.6
const SWAY_HZ := 0.32
const BOB_PX := 5.0
## The dim: a light one, the run under it seen (the card screens use W.DIM at 0.78).
const DIM_A := 0.34
## The motions, seconds.
const DROP_TIME := 0.55
const DROP_STAGGER := 0.09
const STAMP_TIME := 0.22
const FLY_DELAY := 0.42
const FLY_TIME := 0.42
const BLOW_TIME := 0.5

var game: Node
var posters: Array = []
var _cards: Array = []
var _rest: Array = []       # each card's resting spot (its nail on the screen)
var _phase: Array = []
var _tilt: Array = []
var _strings: Control
var _title: WText
var _hint: WText
var _none: WButton
## The config's re-rolls (WantedBoard.rerolls_left; 0 by default: hidden)
var _reroll: WButton
var _t := 0.0
var _done := false
var _snapped: Dictionary = {}   # cards whose string is cut (taken or blown away)
## What the last choice was ("" none yet, "taken", "none"): tests and tools.
var chosen := ""


func _ready() -> void:
	name = "BountyPosters"
	build_dim(Color(W.DIM.r, W.DIM.g, W.DIM.b, DIM_A))
	_strings = Control.new()
	_strings.name = "Strings"
	_strings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_strings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strings.draw.connect(_draw_strings)
	add_child(_strings)
	var top := W.safe_top()
	_title = W.slab_text("WANTED", 92, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 96.0)
	_title.name = "Title"
	_title.stroke = 7
	_title.shadow = 7
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 170.0 + top
	_title.offset_bottom = 266.0 + top
	add_child(_title)
	_hint = W.serif_text("Take a bounty for this run. Done, it pays when the run ends.", 30, W.PAPER, 600, true, HORIZONTAL_ALIGNMENT_CENTER, 36.0, true)
	_hint.name = "Hint"
	_hint.stroke = 4
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_left = 60
	_hint.offset_right = -60
	_hint.offset_top = 272.0 + top
	_hint.offset_bottom = 316.0 + top
	add_child(_hint)
	_none = WButton.make(["No bounty"], 36, WButton.SECONDARY, 5, 8, 22.0, 34.0)
	_none.name = "NoBounty"
	_none.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_none.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_none.offset_left = -190
	_none.offset_right = 190
	_none.offset_top = -330
	_none.offset_bottom = -230
	_none.pressed.connect(func(): choose(-1))
	add_child(_none)
	_reroll = WButton.make(["Re-roll"], 30, WButton.SECONDARY, 5, 6, 16.0, 26.0)
	_reroll.name = "Reroll"
	_reroll.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_reroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reroll.offset_left = -130
	_reroll.offset_right = 130
	_reroll.offset_top = -440
	_reroll.offset_bottom = -360
	_reroll.pressed.connect(_on_reroll)
	_reroll.visible = false
	add_child(_reroll)


## Shows `p_posters` (contracts) dropping in on their strings.
func open(p_posters: Array) -> void:
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	_rest.clear()
	_phase.clear()
	_tilt.clear()
	_snapped.clear()
	posters = p_posters.duplicate(true)
	_done = false
	chosen = ""
	_t = 0.0
	modulate.a = 1.0
	if not is_in_group("wanted_modal"):
		add_to_group("wanted_modal")
	var n := posters.size()
	var vw := get_viewport_rect().size.x if is_inside_tree() else 1080.0
	var total := POSTER_W * n + GAP * maxf(n - 1, 0)
	var x0 := (vw - total) * 0.5
	var ny := NAIL_Y + W.safe_top()
	for i in n:
		var p := WPoster.make(posters[i], POSTER_W)
		p.name = "Poster%d" % (i + 1)
		var k := POSTER_W / WPoster.W_PX
		# hung by its nail: the pivot at the nail (the poster's top centre, 21 px down)
		p.pivot_offset = Vector2(POSTER_W * 0.5, 21.0 * k)
		var rest := Vector2(x0 + i * (POSTER_W + GAP), ny - p.pivot_offset.y)
		p.position = rest - Vector2(0, 900.0 + 120.0 * i)
		p.pressed.connect(choose.bind(i))
		add_child(p)
		move_child(p, _strings.get_index() + 1 + i)
		_cards.append(p)
		_rest.append(rest)
		_phase.append(randf() * TAU)
		_tilt.append([-3.0, 1.5, 3.5][i % 3] * 0.6)
		var tw := p.create_tween()
		tw.tween_interval(DROP_STAGGER * i)
		tw.tween_property(p, "position", rest, DROP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_none.modulate.a = 1.0
	_reroll.modulate.a = 1.0
	_reroll.visible = _rerolls_left() > 0
	enter([_hint, _none])
	_title.modulate.a = 0.0
	create_tween().tween_property(_title, "modulate:a", 1.0, 0.25)
	Audio.play("ui_card")


func cards() -> Array:
	return _cards


func _rerolls_left() -> int:
	if Run.map == null or Run.character == null:
		return 0
	return WantedBoard.rerolls_left(Run.map.id, Run.stage, Run.character.id)


## The config's re-roll (none by default): three new posters drop in, one re-roll spent.
func _on_reroll() -> void:
	if _done or Run.map == null or Run.character == null:
		return
	var fresh := WantedBoard.reroll(Run.map.id, Run.stage, Run.character.id)
	if fresh.is_empty():
		Audio.play("ui_locked")
		return
	open(fresh)


func is_done() -> bool:
	return _done


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for i in _cards.size():
		var p: WPoster = _cards[i]
		if not is_instance_valid(p) or _snapped.has(i):
			continue
		var sway := sin(_t * TAU * SWAY_HZ * (1.0 + 0.12 * i) + float(_phase[i]))
		p.rotation = deg_to_rad(float(_tilt[i]) + SWAY_DEG * sway)
		# the bob only once it hangs (the drop's tween owns the position before)
		if _t > DROP_STAGGER * i + DROP_TIME:
			p.position.y = (_rest[i] as Vector2).y + BOB_PX * sin(_t * TAU * SWAY_HZ * 0.7 + float(_phase[i]) * 1.3)
	_strings.queue_redraw()


## Each poster's string: from above the screen's top edge down to its nail (cut once it is taken or blown away).
func _draw_strings() -> void:
	for i in _cards.size():
		var p = _cards[i]
		if not is_instance_valid(p) or _snapped.has(i):
			continue
		var nail: Vector2 = (p as Control).position + (p as Control).pivot_offset
		var top := Vector2(nail.x + 6.0 * sin(_t * 0.7 + float(_phase[i])), -10.0)
		_strings.draw_line(top, nail, Color(W.INK, 0.85), 4.0, true)
		_strings.draw_line(top + Vector2(1.5, 0), nail + Vector2(1.5, 0), Color(W.AGED, 0.55), 1.5, true)


## The player's choice (a tap, the bot, a tool): `i` a poster's index, -1 "No bounty". Nothing after the first.
func choose(i: int) -> void:
	if _done or not visible:
		return
	_done = true
	if i < 0 or i >= posters.size():
		chosen = "none"
		_blow_away()
	else:
		chosen = "taken"
		_take(i)


func _take(i: int) -> void:
	var c: Dictionary = posters[i]
	var p: WPoster = _cards[i]
	_snapped[i] = true
	# straight and still, stamped
	var tw0 := p.create_tween()
	tw0.tween_property(p, "rotation", 0.0, 0.12)
	var layer: Control = p.get_node_or_null("Over")
	var st := WStamp.make("TAKEN", W.ROCK, int(52 * POSTER_W / WPoster.W_PX))
	st.name = "Taken"
	(layer if layer else p).add_child(st)
	st.position = Vector2(p.size.x * 0.5 - st.size.x * 0.5, p.size.y * 0.3)
	st.rotation = deg_to_rad(-12.0)
	st.slam(STAMP_TIME)
	W.sfx("ui_stamp")
	# the others fall away
	for j in _cards.size():
		if j != i and is_instance_valid(_cards[j]):
			_fall(_cards[j], j)
	var fade := create_tween().set_parallel(true)
	for c2 in [_title, _hint, _none, _reroll]:
		fade.tween_property(c2, "modulate:a", 0.0, 0.2)
	# Game starts the contract now (its plate waits unseen for the flight)
	taken.emit(c)
	var tw := create_tween()
	tw.tween_interval(FLY_DELAY)
	tw.tween_callback(func(): _fly(p, c))


## The poster flies into the HUD's bounty plate (the HUD back as the dim lifts), the plate pops in as it lands.
func _fly(p: WPoster, c: Dictionary) -> void:
	remove_from_group("wanted_modal")
	if dim:
		create_tween().tween_property(dim, "color:a", 0.0, FLY_TIME)
	var target := Vector2(get_viewport_rect().size.x - 140.0, 300.0)
	var plate: Control = null
	var wr = game.get_node_or_null("WantedRun") if game else null
	if wr and wr.has_method("plate"):
		plate = wr.plate()
	if plate and is_instance_valid(plate):
		target = plate.get_global_rect().get_center()
	p.pivot_offset = p.size * 0.5
	var end_scale := 0.12
	if plate and is_instance_valid(plate) and plate.size.y > 0.0:
		end_scale = clampf(plate.size.y / p.size.y, 0.06, 0.3)
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "position", target - p.size * 0.5, FLY_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "scale", Vector2.ONE * end_scale, FLY_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "rotation", deg_to_rad(-8.0), FLY_TIME)
	tw.chain().tween_callback(func():
		if wr and wr.has_method("pop_plate"):
			wr.pop_plate()
		W.sfx("ui_card_pick")
		_close(c))


## A poster let go: it drops off the screen, turning.
func _fall(p: Control, j: int) -> void:
	_snapped[j] = true
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "position:y", p.position.y + 1500.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "rotation", p.rotation + deg_to_rad(24.0 if j % 2 == 0 else -24.0), 0.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)


## "No bounty": the wind takes them, off to the side with a spin, and the run goes on.
func _blow_away() -> void:
	W.sfx("ui_tap")
	var vw := get_viewport_rect().size.x
	for j in _cards.size():
		var p = _cards[j]
		if not is_instance_valid(p):
			continue
		_snapped[j] = true
		var tw := (p as Control).create_tween().set_parallel(true)
		tw.tween_property(p, "position", (p as Control).position + Vector2(vw + 300.0, -260.0 + 140.0 * j), BLOW_TIME).set_delay(0.05 * j).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "rotation", (p as Control).rotation + deg_to_rad(70.0 + 15.0 * j), BLOW_TIME).set_delay(0.05 * j)
	var fade := create_tween().set_parallel(true)
	for c2 in [_title, _hint, _none, _reroll]:
		fade.tween_property(c2, "modulate:a", 0.0, 0.2)
	if dim:
		fade.tween_property(dim, "color:a", 0.0, BLOW_TIME)
	var tw2 := create_tween()
	tw2.tween_interval(BLOW_TIME + 0.12)
	tw2.tween_callback(func(): _close({}))


func _close(c: Dictionary) -> void:
	visible = false
	if not is_in_group("wanted_modal"):
		add_to_group("wanted_modal")
	for p in _cards:
		if is_instance_valid(p):
			p.queue_free()
	_cards.clear()
	closed.emit(c)
