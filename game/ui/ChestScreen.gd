## The chest (Wanted screen 10), the run's reward moment: the world dims to 85 %, "★ LOOT ★ / CHEST" in brass, and the
## chest itself opens first (pass 46, WChest; pass 47, Garry: "on the lower part of the Screen": it drops in on the
## lower third, knocks three times, cracks its lid and throws it open, and its light rises up the screen into the
## reel's row), then sinks away as the reel of plates rises out of that light and runs sideways past the run's items (a
## boss chest, violet, runs past the open paths only) for four seconds, slowing, until it lands: the landed plate grows
## to 420 px with a brass glow. Under it the result (the kind in one word, the name, the stars, one effect line), then
## SKIP ×N, BANISH ×N and TAKE IT (pass 47: no SELL; Garry: "two skips per Stage ... for both Level Ups and Chests",
## banishes the same, one to start with): a skip closes on nothing and the game takes one of the stage's skips
## (Run.chest_skip); a banish strikes the item from the run (Run.chest_banish, which takes the banish and rolls again)
## and the reel spins once more, for about two seconds, to the new roll, the chest staying open. At none left either
## button locks and a tap says so in the header; BANISH also locks on an evolution (banished, the weapon would stay
## unevolved all run) and on gold, and SKIP on gold (it goes straight into the purse). A tap while the chest opens skips
## to the spin; a tap during a spin hurries the rest into 0.6 s. One tween drives the chest and the reel, so either hurry
## moves both. The HUD steps aside.
## Pass 54 (Garry: the boss's chest should say what it is): a chest that rolls a path (the boss's) reads MUTATION CHEST in
## purple under "★ A PATH OPENS ★", its light and its burst violet; an ordinary chest CHEST in brass under "★ LOOT ★".
## The reel's plates and the landed one carry their kind's corner glyph (a revolver since pass 56, a scroll).
## Pass 58: the landed item says UPGRADE, NEW or EVOLUTION in a tag beside its word, an upgrade's new stars pulse and it
## lists what it changes, a row a stat, in place of its effect line (WItem, WCard, as on the level-up's cards); BANISH
## strikes only a new item (Run.banish_refusal: the next level of anything the hero holds and a path mutation of one of
## his weapons lock it) and a tap says why (Garry: "Banish option should not allow Banishing items that Player already
## has"); a turning shine (WShine) stands behind the chest as it opens and behind the landed plate after.
class_name ChestScreen
extends WModal

signal closed(take: bool)

const SPIN := 4.0
## The banish's second spin (pass 47): shorter, the chest already open.
const RESPIN := 2.0
## The reel's row: the landed plate's top on a 1920 screen.
const REEL_Y := 460.0
## The chest's middle as a share of the screen's height (pass 47: the lower third, under the result panel's place).
const CHEST_FRAC := 0.77
## The reel rises this far out of the chest's light as it fades in, over RISE seconds.
const RISE_PX := 420.0
const RISE := 0.3
const SMALL := 210.0          # a passing plate: 200 inside a 5 px border
const BIG := 436.0            # the landed plate: 420 inside an 8 px border
const STEP := SMALL + 30.0
const CELLS := 28
## The result's stars (pass 48, Garry: bigger stars everywhere; 34 before).
const STAR_PX := 48.0
## Plates after the landing cell: the strip runs on past the landed plate and off the screen's edge, so the reel reads
## as a reel that stopped, not one that ran out.
const TAIL := 4
## The chest that opens before the reel, by path: a new class_name is known only once the global class cache is made
## again (the next import), and the chest screen must not wait on that.
const WChestScript := preload("res://ui/wanted/WChest.gd")
## The turning shine behind the chest (pass 58, lane UIA's piece), by path for the same reason.
const WShineScript := preload("res://ui/wanted/WShine.gd")
## The shine (pass 58, Garry: "can you add a kind of animated shine effect behind the Level N header part? ... Do the
## Same for the loot Chest visual of the Chest Opening Screen"): its reach behind the chest and, once the light has
## carried it up, behind the reel's landing cell and the landed plate; how bright it stays while the plates run past it
## (dimmer, so the reel reads) and how far it swells when the reel lands.
const SHINE_CHEST_R := 470.0
const SHINE_PLATE_R := 430.0
const SHINE_LANDED_R := 600.0
const SHINE_SPIN := 0.45
const SHINE_FLARE := 1.12

var _beam: Control
var _shine: WShineScript
var _shine_tw: Tween
var _reel: Control
var _chest: WChestScript
var _plates: Array = []       # [WPlate, def]
var _hero: WPlate
var _hero_glow: Control
var _panel: PanelContainer
var _word: WText
var _name: WText
var _marks_host: CenterContainer
var _effect: WText
## The landed item's word and its tag (pass 58: UPGRADE, NEW or EVOLUTION, WItem.tag), side by side and centred.
var _word_row: HBoxContainer
var _tag: PanelContainer
## The landed favourite's word by the tag (pass 62; its heart rides on the landed plate).
var _fav_word: WText
## The stars of the landed item (null for gold, a mutation or an evolution): an upgrade's new ones pulse (pass 58).
var _marks: WMarks
## An upgrade's change rows in place of the effect line (pass 58), centred CHANGES_W wide.
var _changes_host: CenterContainer
var _changes: VBoxContainer
var _skip_btn: WButton
var _banish_btn: WButton
var _take_btn: WButton
var _result: Dictionary = {}
var _spinning := false
var _reel_x := 0.0
var _last_cell := -1
var _tw: Tween
var _defs: Array = []
## Seconds from a spin's start to its landing (the first spin waits on the chest; a banish's starts at once): a tap
## hurries what is left of it.
var _spin_total := 0.0
## The slot machine's sound (pass 65): lever, spinning loop, the stop's clunk, then the landing's jackpot.
var slot := WSlotSound.new()
## How far the chest's light has risen (0 to 1) and where it rises from (the open chest's mouth).
var _beam_rise := 0.0
var _mouth := Vector2(540, 1400)
## How many times this chest was banished and spun again.
var respins := 0
## The chest open now is the boss's (a path's): the purple header and the violet light (pass 54).
var boss_look := false

## The boss's chest's words and colours (pass 54).
const BOSS_TITLE := "MUTATION CHEST"
const BOSS_STAR := "A path opens"
const BOSS_TITLE_COLOR := W.TOAST_PURPLE
## The violet the boss chest's light and glow take: WChest's violet, lifted towards the toast purple so it shows on the
## dark dim.
const BOSS_LIGHT := Color("9262ca")
## The landed item's tag and change rows (pass 58): the tag's type, the rows' type and the width they are centred in.
const TAG_PX := 30
const CHANGE_PX := 34
## The favourite's heart on the landed 420 px plate (pass 62): a little under a card's share, so it stays a mark.
const FAV_HEART_FRAC := 0.17
const CHANGES_W := 700.0


func _ready() -> void:
	build_dim(W.DIM_CHEST)
	# the shine (pass 58): over the dim, under the chest's light, the reel, the chest and the result; out of sight
	# until a chest lands
	_shine = WShineScript.make(Vector2(540.0, 1400.0), SHINE_CHEST_R) as WShineScript
	_shine.name = "Shine"
	_shine.put(self)
	_shine.visible = false
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
	# over the reel: the plates spin up from behind the sinking chest
	_chest = WChestScript.new()
	_chest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chest.visible = false
	add_child(_chest)
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
	# the word and the tag beside it, centred as one (pass 58)
	_word_row = HBoxContainer.new()
	_word_row.name = "WordRow"
	_word_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_word_row.add_theme_constant_override("separation", 16)
	_word_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_word_row)
	_word = W.label("", 22, W.BRASS_DARK)
	_word.align = HORIZONTAL_ALIGNMENT_CENTER
	_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_word_row.add_child(_word)
	_name = W.slab_text("", 84, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 84.0)
	col.add_child(_name)
	_marks_host = CenterContainer.new()
	_marks_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_marks_host)
	_effect = W.serif_text("", 34, W.INK, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true)
	col.add_child(_effect)
	_changes_host = CenterContainer.new()
	_changes_host.name = "ChangesHost"
	_changes_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_changes_host.visible = false
	col.add_child(_changes_host)
	build_buttons(114.0)
	_skip_btn = WButton.make(["SKIP"], 34, WButton.SECONDARY, 5, 8, 30.0, 0.0)
	_skip_btn.name = "Skip"
	_skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip_btn.pressed.connect(_skip)
	buttons.add_child(_skip_btn)
	_banish_btn = WButton.make(["BANISH"], 34, WButton.SECONDARY, 5, 8, 30.0, 0.0)
	_banish_btn.name = "Banish"
	_banish_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banish_btn.pressed.connect(_banish)
	buttons.add_child(_banish_btn)
	_take_btn = WButton.make(["TAKE IT"], 44, WButton.PRIMARY, 5, 8, 26.0, 0.0)
	_take_btn.name = "Take"
	_take_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_take_btn.size_flags_stretch_ratio = 1.25
	_take_btn.pressed.connect(func(): _finish(true))
	buttons.add_child(_take_btn)


## The chest's light rising up the screen into the reel (pass 47; it fell from the top edge while the chest stood in
## the reel's row): a trapezoid from the open chest's mouth, widening to the top of the reel's row, brass that thins
## as it climbs; `_beam_rise` grows it upwards as the lid opens.
func _draw_beam() -> void:
	if _beam_rise <= 0.0:
		return
	var cx := _mouth.x
	var top := REEL_Y - 160.0
	var y_top := _mouth.y - (_mouth.y - top) * _beam_rise
	var k := (_mouth.y - y_top) / maxf(_mouth.y - top, 1.0)
	var half_top := 150.0 + 230.0 * k
	var pts := PackedVector2Array([Vector2(cx - half_top, y_top), Vector2(cx + half_top, y_top), Vector2(cx + 150.0, _mouth.y),
		Vector2(cx - 150.0, _mouth.y)])
	var lc := light_colour()
	var c_top := Color(lc.r, lc.g, lc.b, 0.0)
	var c_low := Color(lc.r, lc.g, lc.b, 0.5)
	_beam.draw_polygon(pts, PackedColorArray([c_top, c_top, c_low, c_low]))


## The landed plate's brass glow (the mock's 90 px glow), drawn as soft concentric rounded boxes, no blur.
func _draw_glow() -> void:
	var r := Rect2(Vector2(90, 90), Vector2(BIG, BIG))
	var lc := light_colour()
	for i in 12:
		var k := float(i) / 12.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(lc.r, lc.g, lc.b, 0.05)
		sb.set_corner_radius_all(int(24 + 90 * (1.0 - k)))
		_hero_glow.draw_style_box(sb, r.grow(90.0 * (1.0 - k)))


## The chest's light, the landed plate's glow and the burst's rays: brass, violet for the boss's chest (pass 54).
func light_colour() -> Color:
	return BOSS_LIGHT if boss_look else W.BRASS


## The header for the chest about to open (pass 54): MUTATION CHEST in purple under "★ A PATH OPENS ★" for the boss's,
## CHEST in brass under "★ LOOT ★" for any other (one screen serves both, so each chest sets it again).
func style_header(boss: bool) -> void:
	boss_look = boss
	var vp := get_viewport_rect().size
	if boss:
		header.set_title_fit(BOSS_TITLE, 150, BOSS_TITLE_COLOR, vp.x - 96.0)
		header.set_star(BOSS_STAR, BOSS_TITLE_COLOR)
	else:
		header.set_title_fit("CHEST", 150, W.BRASS)
		header.set_star("Loot", W.PAPER)
	_beam.queue_redraw()
	_hero_glow.queue_redraw()


## Opens on a roll from Run.chest_roll: the chest opens, then the reel spins; the outcome is fixed before the first frame.
func open(result: Dictionary) -> void:
	_result = result
	_spinning = true
	respins = 0
	header.set_line("")
	# the reel starts on cell 0 without a tick: the first one sounds as it moves
	_last_cell = 0
	_panel.visible = false
	buttons.visible = false
	_hero_glow.visible = false
	var kind := str(result.get("type", "gold"))
	var def: ContentDef = result.get("def")
	_fill_strip(_pool_for(kind, def), def)
	_build_reel(kind)
	_set_reel(0.0)
	modulate.a = 1.0
	# the chest first (pass 46), on the lower third (pass 47): the reel and the light wait for its lid; the boss's chest
	# is the violet one, its header purple (pass 54)
	var boss := kind == "mutation" or bool(result.get("boss", false))
	style_header(boss)
	var vp := get_viewport_rect().size
	_chest.setup(boss, Vector2(vp.x * 0.5, roundf(vp.y * CHEST_FRAC)), 420.0)
	# the open chest's mouth (WChest stands on its foot, side * 0.3 under its middle; the light leaves 0.42 above that)
	_mouth = Vector2(vp.x * 0.5, _chest.center.y + _chest.side * 0.3 - _chest.side * 0.42)
	_shine_reset(boss)
	_beam_rise = 0.0
	_reel.modulate.a = 0.0
	_reel.position.y = RISE_PX
	_beam.modulate.a = 0.0
	_beam.queue_redraw()
	enter()
	queue_redraw()
	if _tw and _tw.is_valid():
		_tw.kill()
	# one tween for the chest and the reel: the chest's beats over its LIFE, the reel joining at SPIN_AT (fast at first,
	# crawling at the end), a little bounce back onto the landing cell (the lid's sound plays from the chest's beats)
	_tw = create_tween()
	var end := float(CELLS - 1) * STEP
	_tw.tween_method(_intro_at, 0.0, WChestScript.LIFE, WChestScript.LIFE)
	_tw.parallel().tween_method(_set_reel, 0.0, end + 34.0, SPIN).set_delay(WChestScript.SPIN_AT).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_reel, end + 34.0, end, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(_land)
	_spin_total = WChestScript.SPIN_AT + SPIN + 0.22


## The plates a reel runs past for a roll of `kind` landing on `def`.
func _pool_for(kind: String, def: ContentDef) -> Array:
	var pool: Array = []
	if kind == "mutation":
		# the boss's chest (pass 45): the strip runs past the paths still open on the weapons held and nothing else, so
		# every plate is one it could stop on (a reel of weapons and passives that always landed on a mutation read as
		# a rigged wheel). The rolled path goes first so the cycle never puts it beside itself.
		pool = Run.boss_chest_mutations()
		pool.shuffle()
		if def:
			pool.erase(def)
			pool.push_front(def)
	else:
		# filler: the run's own items and whatever else is unlocked, so the reel looks like it could land anywhere
		for w in Registry.unlocked_weapons():
			pool.append(w)
		for p in Registry.unlocked_passives():
			pool.append(p)
		for wi in Run.weapons:
			pool.append(wi.def)
		pool.shuffle()
	return pool


## The chest `t` seconds in, and what waits on it: the light brightens as the lid cracks and rises as it opens, the reel
## rises out of it and fades in from SPIN_AT, and the light goes with the chest as it sinks (no light left without it).
func _intro_at(t: float) -> void:
	_chest.at(t)
	var up := clampf((t - WChestScript.CRACK) / (WChestScript.SPIN_AT - WChestScript.CRACK), 0.0, 1.0)
	var down := clampf((WChestScript.LIFE - t) / (WChestScript.LIFE - WChestScript.SPIN_AT), 0.0, 1.0)
	_beam.modulate.a = minf(up, down)
	var rise := clampf((t - WChestScript.OPEN) / (WChestScript.SPIN_AT + RISE - WChestScript.OPEN), 0.0, 1.0)
	_beam_rise = 1.0 - pow(1.0 - rise, 3.0)
	_beam.queue_redraw()
	var k := clampf((t - WChestScript.SPIN_AT) / RISE, 0.0, 1.0)
	_reel.modulate.a = k
	_reel.position.y = RISE_PX * pow(1.0 - k, 3.0)
	_shine_at(t)


## The shine for a new chest (pass 58): brass and paper, or the boss chest's violet (Garry: the boss chest's in purple);
## at the open chest's mouth, out of sight until the chest lands.
func _shine_reset(boss: bool) -> void:
	if boss:
		_shine.tint(BOSS_LIGHT)
	else:
		_shine.color = W.BRASS
		_shine.color2 = W.PAPER
	_kill_shine_tween()
	_shine.center = _mouth
	_shine.radius = SHINE_CHEST_R
	_shine.strength = 1.0
	_shine.grow = 0.0
	_shine.fade = 0.0
	_shine.visible = true


## The middle of the reel's landing cell, where the landed plate grows.
func landing_center() -> Vector2:
	return Vector2(get_viewport_rect().size.x * 0.5, REEL_Y + BIG * 0.5)


## The shine `t` seconds into the chest's intro (pass 58), on the chest's own clock (a tap that skips or hurries moves it
## too): it grows in behind the chest as the chest lands and knocks, swells as the lid cracks and throws open, then rides
## the light up into the reel's row, narrowing to the landing cell and dimming while the plates run past it.
func _shine_at(t: float) -> void:
	var land := clampf((t - WChestScript.DROP) / (WChestScript.CRACK - WChestScript.DROP), 0.0, 1.0)
	var opened := clampf((t - WChestScript.CRACK) / (WChestScript.OPEN + 0.14 - WChestScript.CRACK), 0.0, 1.0)
	var rise := clampf((t - WChestScript.SPIN_AT) / (WChestScript.LIFE - WChestScript.SPIN_AT), 0.0, 1.0)
	var e_land := 1.0 - pow(1.0 - land, 3.0)
	var e_open := 1.0 - pow(1.0 - opened, 3.0)
	var e_rise := rise * rise * (3.0 - 2.0 * rise)
	# grows to 70 % with the knocks, to full with the lid (a little past it at the throw), the fade the same
	_shine.grow = 0.7 * e_land + 0.3 * e_open + 0.1 * sin(opened * PI)
	_shine.fade = 0.65 * e_land + 0.35 * e_open
	_shine.center = _mouth.lerp(landing_center(), e_rise)
	_shine.radius = lerpf(SHINE_CHEST_R, SHINE_PLATE_R, e_rise)
	_shine.strength = lerpf(1.0, SHINE_SPIN, e_rise)


## The reel landed (pass 58): the shine brightens back to full behind the landed plate, opens out past it (the plate
## would hide a shine its own size) with a swell, and stays there turning for as long as the result is up.
func _shine_flare() -> void:
	_kill_shine_tween()
	_shine.center = landing_center()
	_shine.fade = 1.0
	_shine_tw = create_tween().set_parallel(true)
	_shine_tw.tween_property(_shine, "strength", 1.0, 0.25)
	_shine_tw.tween_property(_shine, "radius", SHINE_LANDED_R, 0.35).from(SHINE_PLATE_R).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shine_tw.tween_property(_shine, "grow", SHINE_FLARE, 0.16).from(1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shine_tw.chain().tween_property(_shine, "grow", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A banish spins the reel again (pass 58): the shine dims and narrows back to the landing cell while the plates run
## past it.
func _shine_dim() -> void:
	_kill_shine_tween()
	_shine.grow = 1.0
	_shine.fade = 1.0
	_shine_tw = create_tween().set_parallel(true)
	_shine_tw.tween_property(_shine, "strength", SHINE_SPIN, 0.2)
	_shine_tw.tween_property(_shine, "radius", SHINE_PLATE_R, 0.2)


func _kill_shine_tween() -> void:
	if _shine_tw and _shine_tw.is_valid():
		_shine_tw.kill()
	_shine_tw = null


## The chest is still opening: the reel has not started.
func intro_playing() -> bool:
	return visible and _spinning and _tw != null and _tw.is_valid() and _chest.before_spin()


## Straight to the spin (a tap, or a tool): the chest's beats jump to the reel's start, its lid open, and it still sinks
## away under the plates.
func skip_intro() -> void:
	if not intro_playing():
		return
	_tw.custom_step(maxf(WChestScript.SPIN_AT - _tw.get_total_elapsed_time(), 0.0))


## The strip's defs: CELLS cells then TAIL more, the landing cell (CELLS - 1) holding `def`, the rest cycling `pool`
## counted from the landing cell, so with `def` first in a pool of two or more the plates either side of where the reel
## stops are never `def` itself (a boss reel of two open paths would otherwise show the same plate twice in a row).
func _fill_strip(pool: Array, def: ContentDef) -> void:
	_defs.clear()
	var n := pool.size()
	for k in range(CELLS + TAIL):
		if k == CELLS - 1:
			_defs.append(def)
		elif n == 0:
			_defs.append(null)
		else:
			_defs.append(pool[posmod(k - (CELLS - 1), n)])


func _build_reel(_kind: String) -> void:
	for p in _plates:
		(p[0] as Node).queue_free()
	_plates.clear()
	if _hero:
		_hero.queue_free()
		_hero = null
	for i in _defs.size():
		var d: ContentDef = _defs[i]
		var p := WPlate.new()
		p.side = SMALL
		p.border = 5
		p.radius = 14
		p.icon_frac = 0.72
		if d:
			# in the colour of the level it would land on (pass 48: the landing cell's is the roll's), a weapon's dots
			p.for_def(d, SMALL, false, int(_result.get("level_to", 1)) if i == CELLS - 1 else reel_level(d))
			p.border = 5
			p.radius = 14
			var pd := WPlate.path_of(d)
			if pd.y > 0:
				p.set_dots(pd)
			# the kind's corner glyph (pass 54): a weapon's revolver (pass 56), a line's scroll
			p.set_kind_mark_for(d)
		else:
			p.fill = W.BRASS
		_reel.add_child(p)
		_plates.append([p, d])


## The level a reel's passing plate shows (pass 48): what it would be if the chest landed on it, the held level one up
## (no higher than its top), 1 for an item not held.
static func reel_level(d: ContentDef) -> int:
	if d is WeaponDef:
		var inst: WeaponInstance = Run.weapon_instance(d.id)
		return mini(inst.level + 1, (d as WeaponDef).max_level) if inst else 1
	if d is PassiveDef:
		var lv := Run.passive_level(d.id)
		return mini(lv + 1, maxi((d as PassiveDef).max_level, 1)) if lv > 0 else 1
	return 1


## The strip slides left: the plate at `x` along it sits in the middle of the screen.
func _set_reel(x: float) -> void:
	_reel_x = x
	var w := get_viewport_rect().size.x
	var cy := REEL_Y + BIG * 0.5
	for i in _plates.size():
		var p: WPlate = _plates[i][0]
		var px := w * 0.5 + i * STEP - x
		p.position = Vector2(px - SMALL * 0.5, cy - SMALL * 0.5)
		p.visible = px > -SMALL and px < w + SMALL
		p.modulate.a = 0.45 if absf(px - w * 0.5) > STEP * 0.5 else 1.0
		p.pivot_offset = Vector2(SMALL, SMALL) * 0.5
		p.scale = Vector2.ONE * 0.85
	if _spinning and x > 0.0:
		slot.begin()
	slot.feed(x)
	var cell := int((x + STEP * 0.5) / STEP)
	if cell != _last_cell:
		_last_cell = cell
		Audio.play("ui_tap")


## A tap anywhere while the chest opens skips to the spin; while the reel spins, it hurries what is left into 0.6 s.
func _input(event: InputEvent) -> void:
	if not visible or not _spinning or _tw == null or not _tw.is_valid():
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if tap:
		if intro_playing():
			skip_intro()
		else:
			var left := maxf(_spin_total - _tw.get_total_elapsed_time(), 0.1)
			_tw.set_speed_scale(maxf(left / 0.6, 1.0))
		Audio.play("ui_tap")


func _land() -> void:
	_spinning = false
	_chest.visible = false
	var kind := str(_result.get("type", "gold"))
	var def: ContentDef = _result.get("def")
	var w := get_viewport_rect().size.x
	var land: WPlate = _plates[CELLS - 1][0]
	land.visible = false
	# the landed plate: 420 px in brass (or its kind's colour), a 14 px shadow and the glow
	_hero = WPlate.new()
	if def:
		# the level the roll lands on (pass 48: its colour), a weapon's mutation dots
		_hero.for_def(def, BIG, false, int(_result.get("level_to", 1)))
		var pd := WPlate.path_of(def)
		if pd.y > 0:
			_hero.set_dots(pd)
		_hero.set_kind_mark_for(def)
	else:
		_hero.side = BIG
		_hero.fill = W.BRASS
	_hero.border = 8
	_hero.radius = 24
	_hero.shadow = 14
	_hero.icon_frac = 0.78
	_hero.position = Vector2((w - BIG) * 0.5, REEL_Y)
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
	# the reveal (pass 44): a sunburst behind the landed plate, stars and paper scraps raining past it
	WCelebrate.burst(self, _hero.position + Vector2(BIG, BIG) * 0.5, 2, 1.0, light_colour())
	_shine_flare()
	# the result
	_show_result(kind, def)
	_panel.visible = true
	_panel.modulate.a = 0.0
	var tp := create_tween()
	tp.tween_property(_panel, "modulate:a", 1.0, 0.2)
	slot.land()
	# pass 67 ("chill with the chest ending sound"): every kind lands on the jackpot; an evolution's mega-win plays once,
	# with its banner and shake, when it is taken (Game._on_evolved)
	Audio.play("ui_jackpot")
	_refresh_buttons()
	buttons.visible = true


## The result panel for the landed roll: the kind's word and its tag (pass 58: UPGRADE, NEW or EVOLUTION, as the
## level-up's cards say it), the name, the stars (an upgrade's new ones pulsing) and either what the upgrade changes, a
## row a stat, or the one effect line (a new item, an evolution, a mutation, gold).
func _show_result(kind: String, def: ContentDef) -> void:
	# out of the tree at once (a node only queued still takes its room for the frame)
	for c in _marks_host.get_children():
		_marks_host.remove_child(c)
		c.queue_free()
	_marks = null
	if _tag:
		_word_row.remove_child(_tag)
		_tag.queue_free()
		_tag = null
	if _fav_word:
		_word_row.remove_child(_fav_word)
		_fav_word.queue_free()
		_fav_word = null
	if _changes:
		_changes_host.remove_child(_changes)
		_changes.queue_free()
		_changes = null
	_changes_host.visible = false
	_effect.visible = true
	if def == null:
		_word.text = "GOLD"
		_word.color = W.BRASS_DARK
		_name.text = "+%s gold" % W.num(int(_result.get("gold", 50)))
		_effect.text = "Straight into the purse."
		return
	_word.text = WItem.word(_result)
	_word.color = WItem.word_color(_result)
	_name.text = def.display_name
	# the hero's favourite (pass 62): FAVOURITE before the tag, a brass heart on the landed plate's corner
	if WItem.favourite(_result):
		_fav_word = WCard.favourite_word(26)
		_word_row.add_child(_fav_word)
		if _hero and _hero.get_node_or_null("FavouriteHeart") == null:
			WCard.add_heart(_hero, FAV_HEART_FRAC)
	var t := WItem.tag(_result)
	if t != "":
		_tag = WCard.tag_pill(t, TAG_PX)
		_word_row.add_child(_tag)
	if kind == "evolution":
		var tmp := WeaponInstance.new(def, 1)
		tmp.rebuild(Run.player_sheet, Run.weapons)
		_effect.text = tmp.description()
		return
	var st := WItem.stars(_result)
	if st.size() >= 2:
		_marks = WMarks.new().setup("stars", int(st[0]), int(st[1]), int(st[2]), STAR_PX)
		_marks.pulse = _marks.has_next()
		_marks_host.add_child(_marks)
	var rows := WItem.changes(_result)
	if rows.is_empty():
		_effect.text = WItem.effect(_result)
		return
	_effect.text = ""
	_effect.visible = false
	_changes = WCard.change_rows(rows, CHANGE_PX)
	_changes.custom_minimum_size.x = CHANGES_W
	_changes_host.add_child(_changes)
	_changes_host.visible = true


## SKIP ×N and BANISH ×N (pass 47): the stage's skips and banishes, locked at none (still tappable, to say why); BANISH
## locked too on what cannot be banished (can_banish), SKIP on gold.
func _refresh_buttons() -> void:
	_skip_btn.set_parts(["SKIP ", ["×%d" % Run.skips_left, W.BRASS_DARK]])
	_skip_btn.locked = Run.skips_left <= 0 or is_gold(_result)
	_banish_btn.set_parts(["BANISH ", ["×%d" % Run.banishes_left, W.BRASS_DARK]])
	_banish_btn.locked = Run.banishes_left <= 0 or not can_banish(_result)


## A chest of gold: nothing to skip or banish, it goes straight into the purse.
static func is_gold(r: Dictionary) -> bool:
	return r.get("def") == null or str(r.get("type", "gold")) == "gold"


## Whether a roll may be banished (pass 47, the lead): not gold, and not an evolution (banished, the weapon would stay
## unevolved all run). Pass 58 (Garry: "Banish option should not allow Banishing items that Player already has, because
## this way they can lock themselves out of progression for those weapons"): the game's one rule, Run.banish_refusal
## (lane UIA's, the level-up's too): never the next level of a weapon, a line or a passive item the hero holds, never an
## evolution, and (pass 60, Garry: "mutations shouldn't be banishable anywhere") never a mutation, the boss chest's hero
## option included; a new passive item can go.
static func can_banish(r: Dictionary) -> bool:
	return banish_refusal(r) == ""


## Why a roll cannot be banished, in plain words for the header line (pass 58); "" when it can be.
static func banish_refusal(r: Dictionary) -> String:
	if is_gold(r):
		return "Gold cannot be banished."
	var def: ContentDef = r.get("def")
	match str(Run.banish_refusal(r)):
		"":
			return ""
		"gold":
			return "Gold cannot be banished."
		"evolution":
			return "An evolution cannot be banished."
		"mutation":
			return "A mutation cannot be banished."
		"held":
			return "You have %s. Only new items can be banished." % def.display_name
	return "Only new items can be banished."


## SKIP: the chest closes on nothing (Game takes one of the stage's skips, Run.chest_skip); with none left, or on gold,
## it stays and says why.
func _skip() -> void:
	if _spinning:
		return
	if is_gold(_result):
		header.set_line("Gold goes straight into the purse.")
		Audio.play("ui_locked")
		return
	if Run.skips_left <= 0:
		header.set_line("No skips left this stage.")
		Audio.play("ui_locked")
		return
	_finish(false)


## BANISH: the item leaves the run (Run.chest_banish takes the banish and rolls the chest again) and the reel spins once
## more, about two seconds, to the new roll; the chest stays open. With none left, on gold, an evolution, any mutation
## (pass 60) or the next level of something held (pass 58, banish_refusal) it stays and says why.
func _banish() -> void:
	if _spinning:
		return
	# gold, an evolution, a mutation or the next level of something held: the header says why (pass 58)
	var why := banish_refusal(_result)
	if why != "":
		header.set_line(why)
		Audio.play("ui_locked")
		return
	var def: ContentDef = _result.get("def")
	if Run.banishes_left <= 0:
		header.set_line("No banishes left this stage.")
		Audio.play("ui_locked")
		return
	var r2 := Run.chest_banish(_result)
	if r2.is_empty():
		header.set_line("No banishes left this stage.")
		Audio.play("ui_locked")
		return
	header.set_line("%s is banished for this run." % def.display_name)
	Audio.play("ui_card_pick")
	respin(r2)


## The reel again, to `result` (a banish): the landed plate, the result and the buttons go, a fresh strip runs RESPIN
## seconds and lands; no chest this time, it is already open.
func respin(result: Dictionary) -> void:
	_result = result
	_spinning = true
	respins += 1
	_last_cell = 0
	_panel.visible = false
	buttons.visible = false
	_hero_glow.visible = false
	_chest.visible = false
	_shine_dim()
	var kind := str(result.get("type", "gold"))
	var def: ContentDef = result.get("def")
	_fill_strip(_pool_for(kind, def), def)
	_build_reel(kind)
	_reel.modulate.a = 1.0
	_reel.position.y = 0.0
	_set_reel(0.0)
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	var end := float(CELLS - 1) * STEP
	_tw.tween_method(_set_reel, 0.0, end + 34.0, RESPIN).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_reel, end + 34.0, end, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(_land)
	_spin_total = RESPIN + 0.22


## The spinning loop never outlives the reel (pass 65): hidden or gone, it stops.
func _notification(what: int) -> void:
	if (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()) or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		if slot:
			slot.cancel()


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
	slot.cancel()
	var def: ContentDef = _result.get("def")
	# the level it lands on goes with it: the gate's flying plate is in that level's colour (pass 48)
	_pick = {"def": def, "rect": _hero.get_global_rect(), "level": int(_result.get("level_to", 0))} if (take and def and _hero) else {}
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func():
		visible = false
		closed.emit(take))
