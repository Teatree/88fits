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
extends ScreenBase

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
## Pass 88 (lane STAGEMENU, Garry): the call to action under the header, its size.
const CALL_TO_ACTION := "Choose a Stage"
const CTA_PX := 52
## The difficulty words by level (1 = the first stage's), and what an unmet boss's name says (pass 88).
const DIFFICULTY_WORDS := ["Easy", "Medium", "Hard", "Extremely Hard"]
const BOSS_UNMET := "Boss not encountered yet"

var map_id := ""
var hero: CharacterDef
var _cards: Array = []
## Tests and tools: the stage a tap last started (-1: none), and set to stop a tap from leaving the screen.
var started := -1
var hold_start := false


func build() -> void:
	set_title("Stages")
	map_id = str(Save.data.get("last_map", "red_canyon"))
	if Registry.map(map_id) == null:
		map_id = "red_canyon"
	hero = Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	if hero and header:
		var p := WPlate.new().for_def(Registry.played_look(hero), 100.0)
		p.border = 5
		p.fill = W.AGED
		p.name = "Hero"
		header.set_right(p)
	content.add_theme_constant_override("separation", CARD_GAP)
	var m := Registry.map(map_id)
	var top := W.label("%s · %s" % [m.display_name if m else map_id, hero.display_name if hero else ""], 22, W.INK_SOFT)
	top.custom_minimum_size.y = 24
	# pass 88 (Garry: 'Add a call to Action. "Choose a Stage"'): the screen's call under the map and hero line
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(top)
	var cta := W.slab_text(CALL_TO_ACTION, CTA_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, CTA_PX * 1.1)
	cta.name = "CallToAction"
	head.add_child(cta)
	content.add_child(head)
	var list := entries(m)
	for i in list.size():
		var c := _card(m, list, i)
		_cards.append(c)
		content.add_child(c)
	UiFx.stagger(content, 0.06)


func use_header() -> bool:
	return true


func board_top() -> float:
	return 196.0


func board_bottom() -> float:
	return 36.0


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
	if hold_start:
		return
	Save.data["last_map"] = map_id
	Run.choose_stage(i)
	Save.request_save()
	# the live title's world was kept for the way back: a run builds its own (TitleScreen._leave_for_a_run)
	load("res://ui/TitleStage.gd").forget()
	go("res://game/Game.tscn")


## A refused tap: the card shakes sideways and settles.
func _shake(c: Control) -> void:
	var x := c.position.x
	var tw := c.create_tween()
	var n := 4
	for k in n:
		var s := 1.0 - float(k) / float(n)
		tw.tween_property(c, "position:x", x + (SHAKE_PX * s if k % 2 == 0 else -SHAKE_PX * s), SHAKE_TIME / float(n + 1))
	tw.tween_property(c, "position:x", x, SHAKE_TIME / float(n + 1))


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


## Whether stage `i` (0-based) of the map can be played: the first always, the next once the one before is beaten.
static func unlocked(p_map_id: String, i: int) -> bool:
	return Save.stage_unlocked(p_map_id, i)


## Whether stage `i` of the map has been beaten (its boss killed in a run of it).
static func beaten(p_map_id: String, i: int) -> bool:
	return Save.stage_beaten(p_map_id, i)


## What opens stage `i`: beating the stage before it ("Beat the Tumbleweed King" once he has been met; pass 88: "Beat
## Stage 1" while he has not, or with no boss).
static func requirement(_m: MapDef, list: Array, i: int) -> String:
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
