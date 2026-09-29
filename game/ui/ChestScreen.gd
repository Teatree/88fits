## The chest (Wanted screen 10), the run's reward moment: the world dims to 85 %, a brass light beam falls from the top,
## "★ LOOT ★ / CHEST" in brass, and a reel of plates runs sideways past the run's items for four seconds, slowing, until
## it lands: the landed plate grows to 420 px with a brass glow and its wax seal pops on with a small overshoot. Under it
## the result (the kind in one word, the name, the stars, one effect line), then SELL (a fifth of its shop price) or
## TAKE IT. A tap during the spin hurries the rest into 0.6 s. The HUD steps aside.
class_name ChestScreen
extends WModal

signal closed(take: bool)

const SPIN := 4.0
const SMALL := 210.0          # a passing plate: 200 inside a 5 px border
const BIG := 436.0            # the landed plate: 420 inside an 8 px border
const STEP := SMALL + 30.0
const CELLS := 28
## Plates after the landing cell: the strip runs on past the landed plate and off the screen's edge, so the reel reads
## as a reel that stopped, not one that ran out.
const TAIL := 4

var _beam: Control
var _reel: Control
var _plates: Array = []       # [WPlate, def]
var _hero: WPlate
var _hero_glow: Control
var _seal: WSeal
var _panel: PanelContainer
var _word: WText
var _name: WText
var _marks_host: CenterContainer
var _effect: WText
var _sell_btn: WButton
var _take_btn: WButton
var _result: Dictionary = {}
var _sell_gold := 0
var _spinning := false
var _reel_x := 0.0
var _last_cell := -1
var _tw: Tween
var _defs: Array = []


func _ready() -> void:
	build_dim(W.DIM_CHEST)
	# the beam: a trapezoid 700 wide at its base, 38 %-62 % at the top, brass fading to nothing, from the top edge
	_beam = Control.new()
	_beam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam.draw.connect(_draw_beam)
	add_child(_beam)
	build_header("Loot", "CHEST", "", 150, W.BRASS)
	_reel = Control.new()
	_reel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reel)
	_hero_glow = Control.new()
	_hero_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_glow.draw.connect(_draw_glow)
	_hero_glow.visible = false
	_reel.add_child(_hero_glow)
	# the result panel: paper, a 6 px border, a 10 px shadow, everything centred
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 10).pad(46, 42, 46, 42))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_top = 940
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	_word = W.label("", 22, W.BRASS_DARK)
	_word.align = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_word)
	_name = W.slab_text("", 84, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 84.0)
	col.add_child(_name)
	_marks_host = CenterContainer.new()
	_marks_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_marks_host)
	_effect = W.serif_text("", 34, W.INK, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true)
	col.add_child(_effect)
	build_buttons(114.0)
	_sell_btn = WButton.make(["SELL ", {"coin": 32}, ["+4", W.BRASS_DARK]], 34, WButton.SECONDARY, 5, 8, 30.0, 0.0)
	_sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_btn.size_flags_stretch_ratio = 1.0
	_sell_btn.pressed.connect(func(): _finish(false))
	buttons.add_child(_sell_btn)
	_take_btn = WButton.make(["TAKE IT"], 44, WButton.PRIMARY, 5, 8, 26.0, 0.0)
	_take_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_take_btn.size_flags_stretch_ratio = 1.4
	_take_btn.pressed.connect(func(): _finish(true))
	buttons.add_child(_take_btn)


func _draw_beam() -> void:
	var w := _beam.size.x
	var cx := w * 0.5
	var h := 1400.0
	var top_l := cx - 350.0 + 700.0 * 0.38
	var top_r := cx - 350.0 + 700.0 * 0.62
	var pts := PackedVector2Array([Vector2(top_l, 0), Vector2(top_r, 0), Vector2(cx + 350.0, h), Vector2(cx - 350.0, h)])
	var c0 := Color(W.BRASS.r, W.BRASS.g, W.BRASS.b, 0.55)
	var c1 := Color(W.BRASS.r, W.BRASS.g, W.BRASS.b, 0.0)
	_beam.draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))


## The landed plate's brass glow (the mock's 90 px glow), drawn as soft concentric rounded boxes, no blur.
func _draw_glow() -> void:
	var r := Rect2(Vector2(90, 90), Vector2(BIG, BIG))
	for i in 12:
		var k := float(i) / 12.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(W.BRASS.r, W.BRASS.g, W.BRASS.b, 0.05)
		sb.set_corner_radius_all(int(24 + 90 * (1.0 - k)))
		_hero_glow.draw_style_box(sb, r.grow(90.0 * (1.0 - k)))


## Opens on a roll from Run.chest_roll and spins the reel; the outcome is fixed before the first frame.
func open(result: Dictionary) -> void:
	_result = result
	_spinning = true
	_last_cell = -1
	_panel.visible = false
	buttons.visible = false
	_hero_glow.visible = false
	var kind := str(result.get("type", "gold"))
	var def: ContentDef = result.get("def")
	_sell_gold = 0
	if def:
		_sell_gold = maxi(int(round(StructureShop.price_of(result) * 0.2)), 1)
	# filler: the run's own items and whatever else is unlocked, so the reel looks like it could land anywhere
	var pool: Array = []
	for w in Registry.unlocked_weapons():
		pool.append(w)
	for p in Registry.unlocked_passives():
		pool.append(p)
	for wi in Run.weapons:
		pool.append(wi.def)
	pool.shuffle()
	_defs.clear()
	for k in range(CELLS - 1):
		_defs.append(pool[k % pool.size()] if not pool.is_empty() else null)
	_defs.append(def)
	for k in range(TAIL):
		_defs.append(pool[(k + 1) % pool.size()] if not pool.is_empty() else null)
	_build_reel(kind)
	_set_reel(0.0)
	modulate.a = 1.0
	enter()
	queue_redraw()
	Audio.play("pk_chest_open")
	# fast at first, crawling at the end, a little bounce back onto the landing cell
	_tw = create_tween()
	var end := float(CELLS - 1) * STEP
	_tw.tween_method(_set_reel, 0.0, end + 34.0, SPIN).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_reel, end + 34.0, end, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(_land)


func _build_reel(_kind: String) -> void:
	for p in _plates:
		(p[0] as Node).queue_free()
	_plates.clear()
	if _hero:
		_hero.queue_free()
		_hero = null
	if _seal:
		_seal.queue_free()
		_seal = null
	for i in _defs.size():
		var d: ContentDef = _defs[i]
		var p := WPlate.new()
		p.side = SMALL
		p.border = 5
		p.radius = 14
		p.icon_frac = 0.72
		if d:
			p.for_def(d, SMALL)
			p.border = 5
			p.radius = 14
		else:
			p.fill = W.BRASS
		_reel.add_child(p)
		_plates.append([p, d])


## The strip slides left: the plate at `x` along it sits in the middle of the screen.
func _set_reel(x: float) -> void:
	_reel_x = x
	var w := get_viewport_rect().size.x
	var cy := 460.0 + BIG * 0.5
	for i in _plates.size():
		var p: WPlate = _plates[i][0]
		var px := w * 0.5 + i * STEP - x
		p.position = Vector2(px - SMALL * 0.5, cy - SMALL * 0.5)
		p.visible = px > -SMALL and px < w + SMALL
		p.modulate.a = 0.45 if absf(px - w * 0.5) > STEP * 0.5 else 1.0
		p.pivot_offset = Vector2(SMALL, SMALL) * 0.5
		p.scale = Vector2.ONE * 0.85
	var cell := int((x + STEP * 0.5) / STEP)
	if cell != _last_cell:
		_last_cell = cell
		Audio.play("ui_tap")


## A tap anywhere while the reel spins hurries what is left of it into 0.6 s.
func _input(event: InputEvent) -> void:
	if not visible or not _spinning or _tw == null or not _tw.is_valid():
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if tap:
		var left := maxf(SPIN + 0.22 - _tw.get_total_elapsed_time(), 0.1)
		_tw.set_speed_scale(maxf(left / 0.6, 1.0))
		Audio.play("ui_tap")


func _land() -> void:
	_spinning = false
	var kind := str(_result.get("type", "gold"))
	var def: ContentDef = _result.get("def")
	var w := get_viewport_rect().size.x
	var land: WPlate = _plates[CELLS - 1][0]
	land.visible = false
	# the landed plate: 420 px in brass (or its kind's colour), a 14 px shadow and the glow
	_hero = WPlate.new()
	if def:
		_hero.for_def(def, BIG)
	else:
		_hero.side = BIG
		_hero.fill = W.BRASS
	_hero.border = 8
	_hero.radius = 24
	_hero.shadow = 14
	_hero.icon_frac = 0.78
	_hero.position = Vector2((w - BIG) * 0.5, 460.0)
	_hero.pivot_offset = Vector2(BIG, BIG) * 0.5
	_reel.add_child(_hero)
	if def == null:
		var coin := WCoin.make(260.0)
		coin.position = Vector2((BIG - 260.0) * 0.5, (BIG - 260.0) * 0.5)
		_hero.add_child(coin)
	_hero_glow.position = _hero.position - Vector2(90, 90)
	_hero_glow.size = Vector2(BIG + 180, BIG + 180)
	_hero_glow.visible = true
	_hero_glow.queue_redraw()
	var tw := create_tween()
	_hero.scale = Vector2.ONE * (SMALL / BIG)
	tw.tween_property(_hero, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if def:
		var r := W.rarity_of(def)
		_seal = WSeal.new().for_rarity(r, 142.0)
		_seal.border = 6
		_seal.ring = 8
		_seal.text_size = 24
		_seal.glow = 40.0
		_seal.position = _hero.position + Vector2(BIG - 142.0 + 30.0, -30.0)
		_seal.pivot_offset = Vector2(71, 71)
		_seal.scale = Vector2.ZERO
		_reel.add_child(_seal)
		var ts := create_tween()
		ts.tween_interval(0.2)
		ts.tween_property(_seal, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ts.tween_property(_seal, "scale", Vector2.ONE, 0.12)
	# the result
	for c in _marks_host.get_children():
		c.queue_free()
	if def:
		if kind == "evolution":
			_word.text = "EVOLUTION"
			_word.color = W.EMBER
			_name.text = def.display_name
			var tmp := WeaponInstance.new(def, 1)
			tmp.rebuild(Run.player_sheet, Run.weapons)
			_effect.text = tmp.description()
		else:
			_word.text = WItem.word(_result)
			_word.color = WItem.word_color(_result)
			_name.text = def.display_name
			_effect.text = WItem.effect(_result)
			var st := WItem.stars(_result)
			if st.size() >= 2:
				_marks_host.add_child(WMarks.new().setup("stars", int(st[0]), int(st[1]), int(st[2]), 34.0))
	else:
		_word.text = "GOLD"
		_word.color = W.BRASS_DARK
		_name.text = "+%s gold" % W.num(int(_result.get("gold", 50)))
		_effect.text = "Straight into the purse."
	_panel.visible = true
	_panel.modulate.a = 0.0
	var tp := create_tween()
	tp.tween_property(_panel, "modulate:a", 1.0, 0.2)
	Audio.play("w_evo_reveal" if kind == "evolution" else "ui_levelup")
	_sell_btn.visible = def != null
	_sell_btn.set_parts(["SELL ", {"coin": 32}, ["+%d" % _sell_gold, W.BRASS_DARK]])
	buttons.visible = true


func sell_gold() -> int:
	return _sell_gold


func result() -> Dictionary:
	return _result


## What the gate flies to the HUD: the landed item and where its plate was (nothing for gold or a sale).
var _pick: Dictionary = {}


func take_pick() -> Dictionary:
	var p := _pick
	_pick = {}
	return p


func _finish(take: bool) -> void:
	if _spinning:
		return
	_spinning = true
	var def: ContentDef = _result.get("def")
	_pick = {"def": def, "rect": _hero.get_global_rect()} if (take and def and _hero) else {}
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func():
		visible = false
		closed.emit(take))
