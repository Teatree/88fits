## The Stages menu (pass 87, lane SUI; Garry: "After Player had completed the 1st Stage ... A new menu unlocks, which will
## pop-up whenever Player presses Play in the Main Menu"). Once stage 1 of the map is beaten, PLAY on the title opens it
## (TitleScreen._on_play, StagesScreen.opens_for); before that PLAY starts stage 1 as it always did.
## One card per stage of the map's `stage_list` (WaveTimeline), in order: the stage's picture (art/ui/stages/<map>_s<k>.jpg,
## lane SLOOK's capture of the stage in its own look; striped until it exists) with STAGE k over its top-left corner and
## the stage's name over its foot, then the difficulty line in the stage's colour (sage the first, rock the last and
## every hell stage, brass between), the description, and its facts: the time to its boss and the boss. A stage beaten
## wears a sage BEATEN stamp. Pass 88 (lane STAGEMENU, Garry): "Choose a Stage" under the header; the line is
## "Difficulty: Easy" (Medium, Hard, Extremely Hard: difficulty_word); the boss a silhouette named "Boss not encountered
## yet" until met (boss_met), and a locked stage asks to "Beat Stage k" until then. A locked stage: the picture darkened
## with a padlock, the card aged, and what opens it ("Beat the Tumbleweed King"); a tap says no (the locked sound, a shake) and
## starts nothing. A tap on an open one starts that stage as a fresh run with the hero chosen on the title (Run's stage
## launch, lane SGAME). The header: the back square (back to the title, as Esc and the back gesture do), "Stages", the
## chosen hero's badge on the right.
## Pass 123 (lane STAGES_SETTINGS), under Royale: the mock
## 7_Stages (Garry: "Stages as the mock: slate cards, a gold START on each open card, the locked card saying what opens
## it; times and bosses from data"). Under the header the map and hero label and, on a black pill, the map's best run
## (Garry: "Move the run-history line (map, best time, level, stage, kills) to the Stages screen's header": the title's
## words from the same data, run_bits). One slate card a stage, 990 wide: the stage's painting as a 200 px band (a
## locked stage's greyed and darkened, LOCKED and "Beat Stage 2 to open it" over it; a beaten one a green BEATEN tag
## turned -6 degrees), the name in cream Ultra 44 with a gold STAGE k tag, the difficulty as a tag (green / gold / red by
## today's tone, today's word) before the description, then the facts: a black pill "◷ 7:10 to the boss", the boss in a
## 48 px frame with his name in gold (italic "Boss not encountered yet" by today's rule), and a gold START on each open
## card. START and a tap anywhere else on an open card start the stage as today; a locked card says no as today.
extends ScreenBase

## Pass 123 (lane STAGES_SETTINGS), the Royale layout (the mock 7_Stages in canvas px): the label's top, the cards' side
## margin (990 wide) and gap, the card's painting band, the inside's padding (left, top, right, bottom), the type sizes,
## the boss frame, START, the locked band's grey and dark, the BEATEN tag's turn.
const R_TOP := 170.0
const R_SIDE := 45.0
const R_GAP := 30
const R_HEAD_GAP := 12
const R_BAND_H := 200.0
const R_PAD := [24, 16, 22, 22]
const R_ROW_GAP := 20
const R_NAME_PX := 44
const R_TAG_PX := 18
const R_DESC_PX := 24
const R_FACT_PX := 24
const R_FACT_H := 44.0
const R_BOSS_PX := 48.0
const R_BOSS_NAME_PX := 24
const R_UNMET_PX := 22
const R_START := Vector2(220, 72)
const R_START_PX := 32
const R_LOCKED_PX := 40
const R_LOCKED_Y := 60.0
const R_LOCK_LINE_PX := 24
const R_LOCK_LINE_Y := 112.0
const R_LOCK_SAT := 0.3
const R_LOCK_BRIGHT := 0.55
const R_BEATEN_DEG := -6.0
const R_BEATEN_AT := Vector2(22, 18)
const R_LABEL_PX := 18
const R_RUN_PX := 24
const R_RUN_H := 44.0
const R_BADGE_PX := 96.0
## The locked band's words: "LOCKED", then what opens it ("Beat Stage 2" + this).
const R_LOCKED_WORD := "LOCKED"
const R_OPENS := " to open it"

## The picture's box inside a card (the card is the board's width, 984 px, less its 6 px borders): 972 x PIC_H (2.6 : 1,
## lane SLOOK's 1248 x 480 captures), the picture covering it (another shape is cropped about its middle).
const PIC_H := 374.0
const CARD_BORDER := 6
const CARD_SHADOW := 10
const CARD_GAP := 28
## The text block under the picture: its padding, the difficulty line, the description and the facts row.
const PAD := Vector2(34, 22)
const NAME_PX := 60
const DIFF_PX := 24
const DESC_PX := 27
const FACT_PX := 26
const BOSS_PX := 60.0
## A locked card's picture under an ink wash this strong.
const LOCK_WASH := 0.62
## A refused tap: the card shakes this far, this long.
const SHAKE_PX := 14.0
const SHAKE_TIME := 0.32
## The art the stage pictures are looked for in when a stage names none (`shot`).
const SHOT_PATH := "res://art/ui/stages/%s_s%d.jpg"
## The difficulty words by level (1 = the first stage's), and what an unmet boss's name says (pass 88).
const DIFFICULTY_WORDS := ["Easy", "Medium", "Hard", "Extremely Hard"]
const BOSS_UNMET := "Boss not encountered yet"

var map_id := ""
var hero: CharacterDef
var _cards: Array = []
## Tests and tools: the stage a tap last started (-1: none), and set to stop a tap from leaving the screen.
var started := -1
var hold_start := false
## Pass 123 (tests and the touch audit): how many times start() began a stage on this screen (one tap, one start).
var starts := 0
## The Royale band's grey for a locked stage (one material for every locked band).
static var _lock_mat: ShaderMaterial


func build() -> void:
	_build_royale()
	# pass 136 (lane LOAD): the strips of the stage a tap is most likely to start load on the loader threads meanwhile
	get_tree().create_timer(PREFETCH_AFTER).timeout.connect(func() -> void:
		if is_inside_tree() and get_tree().get_first_node_in_group(&"run_curtain") == null:
			RunLooks.prefetch_next(get_tree(), likely_stage(map_id), "", map_id))
	return


func use_header() -> bool:
	return true


func board_top() -> float:
	return R_TOP


func board_bottom() -> float:
	return 36.0


func board_side() -> float:
	return R_SIDE


## The cards in order (tests and tools).
func cards() -> Array:
	return _cards


## One stage's card: a WTap whose box is the paper card; locked, it is aged and refuses.
func _card(m: MapDef, list: Array, i: int) -> WTap:
	var e: Dictionary = list[i]
	var open := unlocked(map_id, i)
	var c := WTap.new()
	c.name = "Stage%d" % (i + 1)
	c.set_meta("stage", i)
	c.set_meta("open", open)
	var b := W.box(W.PAPER, CARD_BORDER, CARD_SHADOW).pad(CARD_BORDER, CARD_BORDER, CARD_BORDER, CARD_BORDER)
	c.box = b
	var down := b.pressed()
	down.inner = 6
	c.box_down = down
	# locked: the aged card, whole (its words must read); the picture says it with its wash and padlock
	c.locked_alpha = 1.0
	c.locked = not open
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	v.add_child(_picture(e, i, open))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(PAD.x))
	pad.add_theme_constant_override("margin_right", int(PAD.x))
	pad.add_theme_constant_override("margin_top", int(PAD.y))
	pad.add_theme_constant_override("margin_bottom", int(PAD.y))
	pad.add_child(body)
	v.add_child(pad)
	if open:
		var diff := difficulty_text(e, i)
		if diff != "":
			var d := W.text(diff, W.serif(700, false, W.em(DIFF_PX, 0.04)), DIFF_PX, tone(list, i), HORIZONTAL_ALIGNMENT_LEFT, DIFF_PX * 1.25, true)
			d.name = "Difficulty"
			body.add_child(d)
	else:
		var req := HBoxContainer.new()
		req.name = "Requirement"
		req.add_theme_constant_override("separation", 12)
		req.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lab := W.label("To unlock", 20, W.ROCK, 0.15)
		lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		req.add_child(lab)
		var rt := W.serif_text(requirement(m, list, i), 28, W.INK, 600, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		rt.name = "Text"
		rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		req.add_child(rt)
		body.add_child(req)
	var desc := str(e.get("description", ""))
	if desc != "":
		var dt := W.serif_text(desc, DESC_PX, W.INK_SOFT if open else Color(W.INK_SOFT, 0.8), 400, false, HORIZONTAL_ALIGNMENT_LEFT, DESC_PX * 1.3, true)
		dt.name = "Description"
		body.add_child(dt)
	body.add_child(_facts(e, open))
	c.pressed.connect(_on_card.bind(c))
	return c


## The picture: the capture covering 972 x PIC_H (striped until it exists), STAGE k over its top-left corner, the name
## over its foot in paper with an ink outline, BEATEN stamped top-right, or a locked stage's wash and padlock.
func _picture(e: Dictionary, i: int, open: bool) -> Control:
	var host := Control.new()
	host.name = "Picture"
	host.custom_minimum_size = Vector2(0, PIC_H)
	host.clip_contents = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := shot_path(map_id, i, e)
	if path != "" and ResourceLoader.exists(path):
		var t := TextureRect.new()
		t.name = "Shot"
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(t)
	else:
		var ph := WPlaceholder.make("", "stage %d picture" % (i + 1), Vector2(972, PIC_H))
		ph.name = "Shot"
		ph.centered = true
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ph.custom_minimum_size = Vector2.ZERO
		host.add_child(ph)
	# a soft ink foot under the name so it reads on any picture
	var foot := TextureRect.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(W.INK, 0.0))
	g.set_color(1, Color(W.INK, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	foot.texture = gt
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foot.stretch_mode = TextureRect.STRETCH_SCALE
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -130
	host.add_child(foot)
	if not open:
		var wash := ColorRect.new()
		wash.name = "LockWash"
		wash.color = Color(W.INK, LOCK_WASH)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(wash)
		var lock := _padlock()
		lock.name = "Padlock"
		host.add_child(lock)
		lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		lock.offset_left = -50
		lock.offset_right = 50
		lock.offset_top = -78
		lock.offset_bottom = 40
	# STAGE k, an ink tag on the top-left corner
	var tag := PanelContainer.new()
	tag.name = "Tag"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", W.box(W.INK, 0, 0).pad(22, 6, 22, 8))
	tag.add_child(W.text("STAGE %d" % (i + 1), W.slab(W.em(26, 0.08)), 26, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 30.0))
	tag.position = Vector2(0, 0)
	host.add_child(tag)
	# the name over the picture's foot
	var nm := W.slab_text(str(e.get("name", "Stage %d" % (i + 1))), NAME_PX, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, NAME_PX * 1.1)
	nm.name = "Name"
	nm.stroke = 6
	nm.shadow = 5
	nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nm.offset_left = PAD.x
	nm.offset_right = -PAD.x
	nm.offset_top = -18 - NAME_PX * 1.1
	nm.offset_bottom = -18
	host.add_child(nm)
	if open and beaten(map_id, i):
		var st := WStamp.make("BEATEN", W.SAGE, 30)
		st.name = "Beaten"
		host.add_child(st)
		var keep := func():
			st.size = st.stamp_size()
			st.pivot_offset = st.size * 0.5
			st.rotation = deg_to_rad(-8.0)
			st.position = Vector2(host.size.x - st.size.x - 26.0, 22.0)
		host.resized.connect(keep)
		keep.call()
		# the stamp's own paper behind its ink, so it reads on the picture
		st.draw.connect(func(): st.draw_rect(Rect2(Vector2(4, 4), st.size - Vector2(8, 8)), Color(W.PAPER, 0.88)))
		st.move_to_front()
	return host


## The facts row: the time to the boss, then the boss's plate and name (a locked stage's too: its words name it).
func _facts(e: Dictionary, open: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Facts"
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var length := float(e.get("length", 0.0))
	if length > 0.0:
		var clock := W.slab_text(clock_text(length), FACT_PX + 6, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		clock.name = "Length"
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(clock)
		var to := W.serif_text("to the boss", FACT_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		to.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(to)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	var bd: EnemyDef = Registry.enemy(str(e.get("boss", ""))) if str(e.get("boss", "")) != "" else null
	if bd:
		# pass 88 (Garry): the boss stays hidden (the Collection's silhouette) until the player has met him once
		var met := boss_met(bd.id)
		var p := WPlate.new().for_def(bd, BOSS_PX, not met)
		p.name = "BossPlate"
		p.border = 4
		p.fill = W.AGED
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.set_meta("met", met)
		h.add_child(p)
		var bn := W.slab_text(bd.display_name if met else BOSS_UNMET, FACT_PX + 4, (W.ROCK if open else W.INK_SOFT) if met else W.COMMON, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		bn.name = "Boss"
		bn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bn)
	return h


## A padlock (the title's, smaller): an ink shackle over a brass body with a keyhole.
func _padlock() -> Control:
	var l := Control.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(100, 118)
	l.draw.connect(func():
		var c := Vector2(50, 0)
		l.draw_arc(c + Vector2(0, 50), 28.0, PI, TAU, 32, W.INK, 22.0, true)
		l.draw_arc(c + Vector2(0, 50), 28.0, PI, TAU, 32, W.AGED, 10.0, true)
		var sb := StyleBoxFlat.new()
		sb.bg_color = W.BRASS
		sb.border_color = W.INK
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(12)
		sb.anti_aliasing = true
		l.draw_style_box(sb, Rect2(Vector2(4, 48), Vector2(92, 70)))
		l.draw_circle(c + Vector2(0, 74), 9.0, W.INK, true, -1.0, true)
		l.draw_rect(Rect2(c + Vector2(-4, 78), Vector2(8, 22)), W.INK))
	return l


func _on_card(c: WTap) -> void:
	var i := int(c.get_meta("stage", 0))
	if not bool(c.get_meta("open", false)):
		# pass 129 (lane TRAIL-UI): a stage only a Trail node still locks: the tap opens the Trail on its node
		var tkey := Trail.stage_key(map_id, i)
		if (i == 0 or Save.stage_beaten(map_id, i - 1)) and not Trail.has("stage", tkey) and Nav.to_trail("stage", tkey):
			return
		Audio.play("ui_locked")
		_shake(c)
		return
	start(i)


## Starts stage `i` (0-based) of the map with the chosen hero: a fresh run (Run.choose_stage, lane SGAME: Game starts
## that stage at its window's start, level 1, the start weapon).
func start(i: int) -> void:
	if not unlocked(map_id, i):
		return
	started = i
	starts += 1
	if hold_start:
		return
	Save.data["last_map"] = map_id
	Run.choose_stage(i)
	Save.request_save()
	# the live title's world was kept for the way back: a run builds its own (TitleScreen._leave_for_a_run)
	load("res://ui/TitleStage.gd").forget()
	# pass 120 (lane STARTGO): the revolver wipe and the loading screen into the run (ui/RunCurtain.gd)
	UiFx.go_run(get_tree())


## A refused tap: the card shakes sideways and settles.
func _shake(c: Control) -> void:
	var x := c.position.x
	var tw := c.create_tween()
	var n := 4
	for k in n:
		var s := 1.0 - float(k) / float(n)
		tw.tween_property(c, "position:x", x + (SHAKE_PX * s if k % 2 == 0 else -SHAKE_PX * s), SHAKE_TIME / float(n + 1))
	tw.tween_property(c, "position:x", x, SHAKE_TIME / float(n + 1))


# ---------------------------------------------------------------- Royale (pass 123, lane STAGES_SETTINGS)

## The Royale screen (the mock 7_Stages): the header's badge, the label and the run line, a slate card a stage.
func _build_royale() -> void:
	set_title("Stages")
	map_id = str(Save.data.get("last_map", "red_canyon"))
	if Registry.map(map_id) == null:
		map_id = "red_canyon"
	hero = Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	if hero and header:
		var p := WPlate.new().for_def(Registry.played_look(hero), R_BADGE_PX)
		p.fill = W.AGED
		p.name = "Hero"
		header.set_right(p)
	content.add_theme_constant_override("separation", R_GAP)
	var m := Registry.map(map_id)
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", R_HEAD_GAP)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := W.label("%s · %s" % [m.display_name if m else map_id, hero.display_name if hero else ""], R_LABEL_PX)
	top.name = "Top"
	head.add_child(top)
	# the title's run-history line, moved here (Garry's brief): the best run on this map, or nothing before one is played
	var bits := run_bits(map_id)
	if not bits.is_empty():
		var pill := W.pill(_run_parts(bits), R_RUN_PX, R_RUN_H)
		pill.name = "RunLine"
		pill.set_meta("text", " · ".join(bits))
		pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		head.add_child(pill)
	content.add_child(head)
	var list := entries(m)
	for i in list.size():
		var c := _card_royale(m, list, i)
		_cards.append(c)
		content.add_child(c)
	UiFx.stagger(content, 0.06)


## The run line's parts on the pill: the numbers in Rubik 700 ("best **10:00** · **Lv 47** · stage **2** · **4,864**
## kills"), the rest Rubik 500.
func _run_parts(bits: Array) -> Array:
	var out: Array = []
	for k in bits.size():
		if k > 0:
			out.append(" · ")
		var s := str(bits[k])
		var at := -1
		for j in s.length():
			if s[j] >= "0" and s[j] <= "9":
				at = j
				break
		if at < 0:
			out.append(s)
			continue
		var stop := at
		while stop < s.length() and (s[stop] >= "0" and s[stop] <= "9" or s[stop] == ":" or s[stop] == ","):
			stop += 1
		# "Lv 47" is bold whole (a level reads as one word), "best 10:00" and "4,864 kills" bold their number
		var from := 0 if s.begins_with("Lv") else at
		if from > 0:
			out.append(s.substr(0, from))
		out.append([s.substr(from, stop - from), null, "bold"])
		if stop < s.length():
			out.append(s.substr(stop))
	return out


## One stage's Royale card: the slate panel (a WTap: a tap on an open card starts it, as today), its painting band,
## then the name row, the difficulty row and the facts row with START. A locked card keeps the slate (its band says it)
## and refuses a tap with today's sound and shake.
func _card_royale(m: MapDef, list: Array, i: int) -> WTap:
	var e: Dictionary = list[i]
	var open := unlocked(map_id, i)
	var c := WTap.new()
	c.name = "Stage%d" % (i + 1)
	c.set_meta("stage", i)
	c.set_meta("open", open)
	var edge := R.PANEL_EDGE
	var b := W.box(W.PAPER, edge, R.PANEL_BASE).pad(edge, edge, edge, edge)
	b.role = "panel"
	c.box = b
	if open:
		# a finger on an open card: the gold inner edge (the level-up cards' press feedback), the card stays put
		var down := b.copy()
		down.inner = 5
		c.box_down = down
	else:
		c.box_down = b
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	v.add_child(_band_royale(m, list, i, open))
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(R_PAD[0]))
	pad.add_theme_constant_override("margin_top", int(R_PAD[1]))
	pad.add_theme_constant_override("margin_right", int(R_PAD[2]))
	pad.add_theme_constant_override("margin_bottom", int(R_PAD[3]))
	v.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", R_ROW_GAP)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(body)
	# the name and its STAGE k tag
	var nr := HBoxContainer.new()
	nr.name = "NameRow"
	nr.add_theme_constant_override("separation", 14)
	nr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := W.slab_text(str(e.get("name", "Stage %d" % (i + 1))).to_upper(), R_NAME_PX, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, float(R_NAME_PX))
	nm.name = "Name"
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nr.add_child(nm)
	var st := tag("STAGE %d" % (i + 1), "gold")
	st.name = "Tag"
	nr.add_child(st)
	body.add_child(nr)
	# the difficulty tag (today's word, today's tone) and the description beside it
	var dr := HBoxContainer.new()
	dr.name = "DifficultyRow"
	dr.add_theme_constant_override("separation", 10)
	dr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dt := tag(difficulty_word(e, i).to_upper(), tone_role(list, i))
	dt.name = "Difficulty"
	dt.set_meta("text", difficulty_text(e, i))
	dt.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dr.add_child(dt)
	var desc := str(e.get("description", ""))
	if desc != "":
		var ds := W.serif_text(desc, R_DESC_PX, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, R_DESC_PX * 1.3, true)
		ds.name = "Description"
		ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dr.add_child(ds)
	body.add_child(dr)
	body.add_child(_facts_royale(e, i, open))
	c.pressed.connect(_on_card.bind(c))
	return c


## The painting band (the mock's 200 px): the stage's capture covering it (striped until it exists); a locked stage's
## greyed and darkened under LOCKED and what opens it; a beaten one's green BEATEN tag top-right, turned -6 degrees.
func _band_royale(m: MapDef, list: Array, i: int, open: bool) -> Control:
	var e: Dictionary = list[i]
	var host := Control.new()
	host.name = "Picture"
	host.custom_minimum_size = Vector2(0, R_BAND_H)
	host.clip_contents = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := shot_path(map_id, i, e)
	if path != "" and ResourceLoader.exists(path):
		var t := TextureRect.new()
		t.name = "Shot"
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not open:
			t.material = lock_material()
		host.add_child(t)
	else:
		var ph := WPlaceholder.make("", "stage %d picture" % (i + 1), Vector2(982, R_BAND_H))
		ph.name = "Shot"
		ph.centered = true
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ph.custom_minimum_size = Vector2.ZERO
		host.add_child(ph)
		if not open:
			var wash := ColorRect.new()
			wash.color = Color(0, 0, 0, 1.0 - R_LOCK_BRIGHT)
			wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			host.add_child(wash)
	if not open:
		var lw := W.slab_text(R_LOCKED_WORD, R_LOCKED_PX, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, float(R_LOCKED_PX))
		lw.name = "Locked"
		# the mock's 2 px stroke and drop on this word (lighter than R.edge's 40 px default)
		lw.stroke = 1
		lw.shadow = 2
		lw.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		lw.offset_top = R_LOCKED_Y
		lw.offset_bottom = R_LOCKED_Y + R_LOCKED_PX
		host.add_child(lw)
		# pass 129 (lane TRAIL-UI): the Trail's line carries a chevron (the card's tap opens the Trail)
		var req_words := requirement(m, list, i) + R_OPENS
		if req_words.begins_with("Reach Trail Level") and R.body().has_char(0x203A):
			req_words += " ›"
		var req := W.serif_text(req_words, R_LOCK_LINE_PX, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
		req.name = "Requirement"
		req.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		req.offset_top = R_LOCK_LINE_Y
		req.offset_bottom = R_LOCK_LINE_Y + R_LOCK_LINE_PX * 1.3
		host.add_child(req)
	elif beaten(map_id, i):
		var bt := tag("BEATEN", "green")
		bt.name = "Beaten"
		host.add_child(bt)
		var keep := func():
			bt.size = bt.get_combined_minimum_size()
			bt.pivot_offset = bt.size * 0.5
			bt.rotation = deg_to_rad(R_BEATEN_DEG)
			bt.position = Vector2(host.size.x - bt.size.x - R_BEATEN_AT.x, R_BEATEN_AT.y)
		host.resized.connect(keep)
		keep.call()
	return host


## The facts row: the time to the boss on a black pill, the boss in his frame and his name (gold once met; italic
## "Boss not encountered yet" until then, today's rule), and on an open card START at the right.
func _facts_royale(e: Dictionary, i: int, open: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Facts"
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var length := float(e.get("length", 0.0))
	if length > 0.0:
		var pill := W.pill([{"glyph": "clock", "px": 22}, [clock_text(length), null, "bold"], " to the boss"], R_FACT_PX, R_FACT_H)
		pill.name = "Length"
		pill.set_meta("text", clock_text(length))
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pill)
	var bd: EnemyDef = Registry.enemy(str(e.get("boss", ""))) if str(e.get("boss", "")) != "" else null
	if bd:
		var met := boss_met(bd.id)
		var p := WPlate.new().for_def(bd, R_BOSS_PX, not met)
		p.name = "BossPlate"
		p.fill = W.AGED
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.set_meta("met", met)
		h.add_child(p)
		var bn: WText
		if met:
			bn = W.serif_text(bd.display_name, R_BOSS_NAME_PX, R.GOLD_TEXT if open else R.SECONDARY, 600, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
		else:
			bn = W.serif_text(BOSS_UNMET, R_UNMET_PX, R.SECONDARY, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
		bn.name = "Boss"
		bn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bn)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	if open:
		var sb := WButton.make(["START"], R_START_PX, WButton.PRIMARY, R.BUTTON_EDGE, R.BUTTON_BASE, 0.0, 0.0, float(R_START_PX), WButton.GOLD)
		sb.name = "Start"
		sb.custom_minimum_size = R_START
		sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sb.set_meta("stage", i)
		# START takes its own touch (STOP): the card under it does not start the stage a second time
		sb.ready.connect(func(): sb.mouse_filter = Control.MOUSE_FILTER_STOP)
		sb.pressed.connect(func(): start(i))
		h.add_child(sb)
	return h


## A Royale tag (the mock's 18 px tags: STAGE k gold, BEATEN and EASY green, MEDIUM gold, HARD red): WCard.tag_pill's
## box (a 3 px navy edge, 4 px corners) in the role's colour, the word in Rubik 700 (Garry: no Ultra under 28 px), navy on
## gold and green, white on red.
static func tag(t: String, role: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	var fill := R.TAG_GOLD
	var ink := R.NAVY
	match role:
		"green":
			fill = R.TAG_GREEN
		"red":
			fill = R.TAG_RED
			ink = R.WHITE
	sb.bg_color = fill
	sb.border_color = R.NAVY
	sb.set_border_width_all(R.TAG_EDGE)
	sb.set_corner_radius_all(R.RADIUS_TAG)
	sb.anti_aliasing = true
	sb.content_margin_left = 12.0 + R.TAG_EDGE
	sb.content_margin_right = 12.0 + R.TAG_EDGE
	sb.content_margin_top = 5.0 + R.TAG_EDGE
	sb.content_margin_bottom = 5.0 + R.TAG_EDGE
	p.add_theme_stylebox_override("panel", sb)
	p.set_meta("role", role)
	var w := W.text(t, R.body(R.LABEL_WEIGHT, false, W.em(R_TAG_PX, 0.06)), R_TAG_PX, ink, HORIZONTAL_ALIGNMENT_LEFT, roundf(R_TAG_PX * 1.1))
	w.name = "Word"
	p.add_child(w)
	return p


## The difficulty tag's role: green for the first stage, red for the last and every hell stage, gold between (today's
## tone: sage, rock, brass).
static func tone_role(list: Array, i: int) -> String:
	var c := tone(list, i)
	if c == W.ROCK:
		return "red"
	if c == W.SAGE:
		return "green"
	return "gold"


## A locked band's grey: the painting at R_LOCK_SAT saturation and R_LOCK_BRIGHT brightness (the mock's
## saturate(.3) brightness(.55)); one material for every band.
static func lock_material() -> ShaderMaterial:
	if _lock_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float sat = 0.3;\nuniform float bright = 0.55;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat l = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(vec3(l), c.rgb, sat) * bright, c.a);\n}\n"
		_lock_mat = ShaderMaterial.new()
		_lock_mat.shader = sh
		_lock_mat.set_shader_parameter("sat", R_LOCK_SAT)
		_lock_mat.set_shader_parameter("bright", R_LOCK_BRIGHT)
	return _lock_mat


## The title's run-history line for the map (TitleScreen._refresh_map's words from the same data, Save.best_run): its
## best run's time, level, stage and kills ("best 16:35", "Lv 32", "stage 3", "4,864 kills"), or nothing before a run.
## The map's own name leads the title's line; here the label above the pill names the map.
static func run_bits(p_map_id: String) -> Array:
	var bits: Array = []
	var best := Save.best_run(p_map_id)
	if best.is_empty() or float(best.get("time", 0.0)) <= 0.0:
		return bits
	bits.append("best " + W.mmss(float(best.get("time", 0.0))))
	bits.append(W.lv(int(best.get("level", 0))))
	bits.append("stage %d" % int(best.get("stage", 1)))
	if int(best.get("kills", 0)) > 0:
		bits.append("%s kills" % W.num(int(best.get("kills", 0))))
	return bits


## The title's whole line: "Red Canyon · best 16:35 · Lv 32 · stage 3 · 4,864 kills" (the map's name alone before a run).
static func run_line(p_map_id: String) -> String:
	var m := Registry.map(p_map_id)
	var bits: Array = [m.display_name if m else p_map_id]
	bits.append_array(run_bits(p_map_id))
	return " · ".join(bits)


# ---------------------------------------------------------------- the stages of a map (lane SGAME's model)

## Whether PLAY on the title opens this menu for `p_map_id`: the map has more than one stage and its first is beaten
## (Save.stages_menu_open; Garry: "opens on every Play").
static func opens_for(p_map_id: String) -> bool:
	var m := Registry.map(p_map_id)
	if m == null or m.timeline == null:
		return false
	return m.timeline.stage_count() > 1 and Save.stages_menu_open(p_map_id)


## The map's stages in order, each WaveTimeline.stage_entry (every key filled: index, id, name, length, boss,
## description, difficulty, filter, hell, shot, start, end; a map without `stage_list` has its `stages` of `stage_length`).
static func entries(m: MapDef) -> Array:
	var out: Array = []
	if m == null or m.timeline == null:
		return out
	var tl: WaveTimeline = m.timeline
	for k in tl.stage_count():
		out.append(tl.stage_entry(k))
	return out


## Pass 136 (lane LOAD): the stage a tap here is most likely to start (its strips are asked for ahead): the furthest one
## open. PREFETCH_AFTER s after the menu is built.
const PREFETCH_AFTER := 0.6


static func likely_stage(p_map_id: String) -> int:
	var m := Registry.map(p_map_id)
	if m == null or m.timeline == null:
		return 0
	var best := 0
	for k in m.timeline.stage_count():
		if unlocked(p_map_id, k):
			best = k
	return best


## Whether stage `i` (0-based) of the map can be played: the first always, the next once the one before is beaten.
static func unlocked(p_map_id: String, i: int) -> bool:
	return Save.stage_unlocked(p_map_id, i)


## Whether stage `i` of the map has been beaten (its boss killed in a run of it).
static func beaten(p_map_id: String, i: int) -> bool:
	return Save.stage_beaten(p_map_id, i)


## What opens stage `i`: beating the stage before it ("Beat the Tumbleweed King" once he has been met; pass 88: "Beat
## Stage 1" while he has not, or with no boss).
## Pass 129 (lane TRAILCORE): when the stage before it is beaten (or it is the first) and a Trail node is what still
## locks it, the Trail's line: "Reach Trail Level N".
static func requirement(_m: MapDef, list: Array, i: int) -> String:
	if _m != null and i >= 0 and i < list.size() and (i == 0 or Save.stage_beaten(_m.id, i - 1)):
		var tkey := "%s:%s" % [_m.id, str((list[i] as Dictionary).get("id", ""))]
		if not Trail.has("stage", tkey):
			return Trail.requirement_text("stage", tkey)
	if i <= 0 or i - 1 >= list.size():
		return ""
	var prev: Dictionary = list[i - 1]
	var bd: EnemyDef = Registry.enemy(str(prev.get("boss", ""))) if str(prev.get("boss", "")) != "" else null
	if bd and boss_met(bd.id):
		return "Beat %s" % _the(bd.display_name)
	return "Beat Stage %d" % i


## Pass 88 (lane STAGEMENU): a boss is shown once the player has met him (Save.enemy_met: on the sand in a run once, or
## killed: the Collection's rule).
static func boss_met(id: String) -> bool:
	return Save.enemy_met(id)


## The difficulty line (pass 88, Garry: 'Just write "Difficulty: Easy" "Medium" "Hard" "Extremely Hard"'): "Difficulty: "
## and the entry's `difficulty` (a word, or a level 1..4), else the word for the stage's place (the first Easy, then
## Medium, Hard, Extremely Hard and on).
static func difficulty_text(e: Dictionary, i: int) -> String:
	return "Difficulty: " + difficulty_word(e, i)


static func difficulty_word(e: Dictionary, i: int) -> String:
	var own := str(e.get("difficulty", "")).strip_edges()
	if own.is_valid_int():
		return level_word(int(own) - 1)
	if own.to_lower().begins_with("difficulty:"):
		own = own.substr(11).strip_edges()
	if own != "":
		return own
	return level_word(i)


## The difficulty word of level `k` (0 = Easy; past the last, Extremely Hard).
static func level_word(k: int) -> String:
	return DIFFICULTY_WORDS[clampi(k, 0, DIFFICULTY_WORDS.size() - 1)]


## "the Tumbleweed King", "the Brander": a boss's name after "Beat", its own "The" in lower case.
static func _the(n: String) -> String:
	return ("the " + n.substr(4)) if n.to_lower().begins_with("the ") else "the " + n


## The stage's picture: its own `shot`, else art/ui/stages/<map>_s<k>.jpg.
static func shot_path(p_map_id: String, i: int, e: Dictionary) -> String:
	var own := str(e.get("shot", ""))
	if own != "" and ResourceLoader.exists(own):
		return own
	return SHOT_PATH % [p_map_id, i + 1]


## The difficulty line's colour: sage for the first stage, rock for the last and every hell stage, brass between.
static func tone(list: Array, i: int) -> Color:
	var e: Dictionary = list[i] if i < list.size() else {}
	if bool(e.get("hell", false)) or (i == list.size() - 1 and list.size() > 1):
		return W.ROCK
	if i == 0:
		return W.SAGE
	return W.BRASS_DARK


## "7:10" (minutes and seconds, no leading zero).
static func clock_text(seconds: float) -> String:
	var t := int(round(maxf(seconds, 0.0)))
	return "%d:%02d" % [t / 60, t % 60]
