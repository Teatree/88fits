## The Watch's Hero Settings pop-up (pass 85, lane TOOLS; Garry: "Add an option to restart a run - Upon clicking that the
## run will open the new 'Hero Settings' pop-up and after choosing all the stats that I want and pressing 'Start Run' the
## game will start with the descending animation and everything with the hero with the Mirror stats that I've chosen.
## When starting the Watch tool now, it will start with this pop-up being open already. It will have the default info
## already filled in there, but I should be able to choose what I need before starting a run."). Every setting a run
## starts with, in the panel's dark tool style: the hero and his look, the map, the seed (random or a number), the speed,
## the time limit, Down!'s answer, the sound, the damage numbers, the unlocks; the bot's preset and each of its options;
## the Upgrade board talent by talent (each rank bought in its form, A or B, as the board itself does) with the presets
## none / a quarter / half / full (the Sim's, from watch.py's setup file) and the PC save's board. "Start Run" hands the
## settings to Watch.gd (signal `started`), which starts the run the way the game does: the hero comes down in the spawn
## beam. Opened mid-run from the header's "Restart run", "Cancel" leaves the run as it was.
## Pass 87 (lane STOOLS; Garry: "Watch Tool should give me a choice to which Stage bot will be playing in"): the Stage
## row under the map: every stage of the map with its name, length and boss; with "Every unlock" on (tool mode) every
## stage may be chosen, off (the save's mode) only the stages the PC save has unlocked (watch.py's setup file:
## save_stages, the save's stages beaten); the row's note says which. The run starts that stage (the launch's `stage`).
## The settings (a Dictionary; defaults_from_args, collect): hero, look ("" = his own), map, stage (1-based), seed, seed_random, speed,
## limit (play seconds, 0 none), death, sound, numbers, unlocks ("all" | "save"), talents (the command line's text,
## "grit:AAB,drive:A" or "none"), board_label, bot ("auto" | "stub"), bot_opts ({preset, and every option that differs
## from the preset's}). Tools only.
extends Control

signal started(settings: Dictionary)
signal cancelled

const PANEL := preload("res://tools/watch/WatchPanel.gd")
const CLOCK := preload("res://tools/watch/WatchClock.gd")
const BOT_PATH := "res://tools/bot/Bot.gd"
const MAX_RANK := 6
## the bot's number options: [key, label, min, max, step, tip]
const BOT_NUMBERS := [["skill", "Skill", 0.0, 1.0, 0.05, "how well he picks cards (1 = always the best score)"],
	["reaction", "Reaction s", 0.0, 3.0, 0.1, "seconds before he answers a danger"],
	["dodge", "Dodge", 0.0, 1.0, 0.05, "how often he steps out of a ring or a line"],
	["daring", "Daring", 0.0, 1.0, 0.05, "how close he lets the crowd come"],
	["stray", "Stray m", 0.0, 200.0, 5.0, "how far he walks for gems"],
	["explore", "Explore", 0.0, 1.0, 0.05, "how much he wants to see the map"]]
## the bot's choice options: [key, label, choices]
const BOT_CHOICES := [["style", "Style", ["balanced", "damage", "safety", "greedy"]], ["boss", "Boss", ["leash", "free"]],
	["cards", "Cards", ["tier", "score"]], ["portal", "Portal", ["endless", "extract"]]]
const BOOL_WORDS := {"totems": "Totem Poles", "barrels": "Barrels", "powerups": "Power-ups", "structures": "Structures",
	"shop": "Shop", "stranger": "Stranger", "specials": "Specials"}
const DEATHS := [["end", "end the run at the first fall"], ["ad", "the ad revive once, then end"], ["keep", "stand up at once, count every fall"]]
const PRESET_ORDER := ["none", "quarter", "half", "full", "save"]
const PRESET_WORDS := {"none": "None", "quarter": "A quarter", "half": "Half", "full": "Full", "save": "My save"}
const FORM_COLS := [Color(0.43, 0.71, 1.0), Color(0.93, 0.66, 0.26)]

var can_cancel := false
## watch.py's setup file: {presets: {name: {id: letters} | null}, labels, save_note, refs}
var doc: Dictionary = {}
## the board being made: talent id -> [form a rank]
var picks: Dictionary = {}

var _reg: Node
var _bot_consts: Dictionary = {}
var _talent_ids: Array = []
var _talent_defs: Dictionary = {}
var _hero_ids: Array = []
var _look_codes: Array = []
var _map_ids: Array = []
var _box: PanelContainer
var _hero: OptionButton
var _look: OptionButton
var _hero_pic: TextureRect
var _hero_note: Label
var _map: OptionButton
## pass 87 (lane STOOLS): the stage the run plays and its words; the stage index (0-based) of each item
var _stage: OptionButton
var _stage_note: Label
var _stage_idx: Array = []
var _seed_random: CheckBox
var _seed: SpinBox
var _speed: OptionButton
var _limit: LineEdit
var _death: OptionButton
var _sound: CheckBox
var _numbers: CheckBox
var _unlocks: CheckBox
var _bot_preset: OptionButton
var _bot_preset_ids: Array = []
var _bot_fields: Dictionary = {}
var _slots: Dictionary = {}
var _board_sum: Label
var _preset_btns: Dictionary = {}
var _cancel_btn: Button
var _start_btn: Button
var _err: Label


# ---------------------------------------------------------------- pure pieces (tests/pass85_tools_test.gd)

## The settings the command line asks for (Watch.gd's args): the pop-up's defaults, and a `--go` run's settings.
static func defaults_from_args(args: Dictionary) -> Dictionary:
	var s := {"hero": str(args.get("hero", "drifter")), "look": str(args.get("look", "")), "map": str(args.get("map", "red_canyon")),
		"stage": maxi(int(args.get("stage", "1")), 1),
		"seed": maxi(int(args.get("seed", "1")), 1), "seed_random": str(args.get("seed_random", "0")) == "1",
		"speed": CLOCK.nearest(float(args.get("speed", "1"))), "limit": maxf(float(args.get("limit", "0")), 0.0),
		"death": str(args.get("death", "end")), "sound": str(args.get("sound", "0")) == "1", "numbers": str(args.get("numbers", "1")) != "0",
		"unlocks": str(args.get("unlocks", "all")), "talents": str(args.get("talents", "none")), "board_label": str(args.get("board_label", "")),
		"bot": "stub" if str(args.get("bot", "auto")) == "stub" else "auto", "bot_opts": {}}
	var o := {}
	for k in args:
		var key := str(k)
		if key.begins_with("bot."):
			o[key.substr(4)] = typed(str(args[k]))
	s["bot_opts"] = o
	return s


## A command line's value typed (as Watch.typed_value): a bool, an int, a float, else the text.
static func typed(v: String) -> Variant:
	var s := v.strip_edges()
	match s.to_lower():
		"true", "on", "yes":
			return true
		"false", "off", "no":
			return false
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	return s


## The board from the command line's text ("grit:AAB,drive:A", "none") or a {id: letters} dictionary: {id: [0|1 a rank]}
## (A = 0, the first form; B = 1). Ranks past MAX_RANK and anything unreadable are left out.
static func picks_from(src) -> Dictionary:
	var out := {}
	var pairs: Array = []
	if src is Dictionary:
		for k in src:
			pairs.append([str(k), str(src[k])])
	else:
		var txt := str(src).strip_edges()
		if txt == "" or txt.to_lower() == "none":
			return out
		for part in txt.split(",", false):
			var bits := part.strip_edges().split(":")
			if bits.size() == 2:
				pairs.append([bits[0].strip_edges(), bits[1].strip_edges()])
	for pr in pairs:
		var arr: Array = []
		for ch in str(pr[1]).to_upper():
			if ch == "A" or ch == "0":
				arr.append(0)
			elif ch == "B" or ch == "1":
				arr.append(1)
		if not arr.is_empty():
			out[str(pr[0])] = arr.slice(0, MAX_RANK)
	return out


## The board as the command line's text, talents in `order` (others after, by id): "grit:AAB,drive:A", "none" when empty.
static func letters_of(p: Dictionary, order: Array = []) -> String:
	var ids: Array = []
	for id in order:
		if p.has(id) and not (p[id] as Array).is_empty():
			ids.append(str(id))
	var rest: Array = []
	for id in p:
		if not ids.has(str(id)) and not (p[id] as Array).is_empty():
			rest.append(str(id))
	rest.sort()
	ids.append_array(rest)
	var parts := PackedStringArray()
	for id in ids:
		var s := ""
		for f in p[id]:
			s += "B" if int(f) == 1 else "A"
		parts.append("%s:%s" % [id, s])
	return ",".join(parts) if not parts.is_empty() else "none"


## Ranks bought on a board.
static func ranks_of(p: Dictionary) -> int:
	var n := 0
	for id in p:
		n += (p[id] as Array).size()
	return n


## Whether two boards are the same (same ranks in the same forms).
static func same_board(a: Dictionary, b: Dictionary) -> bool:
	var ka: Array = []
	for k in a:
		if not (a[k] as Array).is_empty():
			ka.append(str(k))
	var kb: Array = []
	for k in b:
		if not (b[k] as Array).is_empty():
			kb.append(str(k))
	ka.sort()
	kb.sort()
	if ka != kb:
		return false
	for k in ka:
		if (a[k] as Array) != (b[k] as Array):
			return false
	return true


## The preset a board is ("none", "quarter", ..., "save"; "" for a board of its own), from the setup file's presets.
static func preset_of(p: Dictionary, presets: Dictionary) -> String:
	for name in PRESET_ORDER:
		var b = presets.get(name)
		if b is Dictionary and same_board(p, picks_from(b)):
			return name
	return ""


## The board in words for the header: "a quarter (12 of 48 ranks)", "custom (7 of 48 ranks)".
static func board_words(p: Dictionary, presets: Dictionary, labels: Dictionary, n_talents: int) -> String:
	var pre := preset_of(p, presets)
	var name := str(labels.get(pre, PRESET_WORDS.get(pre, pre))) if pre != "" else "custom"
	return "%s (%d of %d ranks)" % [name, ranks_of(p), MAX_RANK * maxi(n_talents, 1)]


## A slot's click on a talent's ranks `arr` (0-based slot `k`): a slot past the ranks bought buys up to it in form A; a
## bought one in A turns to B; one in B is sold with every rank above it. The new ranks.
static func click_slot(arr: Array, k: int) -> Array:
	var out := arr.duplicate()
	if k >= out.size():
		while out.size() <= k:
			out.append(0)
		return out
	if int(out[k]) == 0:
		out[k] = 1
		return out
	return out.slice(0, k)


## The time limit from the box: "5:00", "300", "1:02:00"; "" or anything unreadable is 0 (none).
static func limit_secs(txt: String) -> float:
	var t := txt.strip_edges()
	if t == "":
		return 0.0
	if t.contains(":"):
		var s := 0.0
		for part in t.split(":"):
			if not part.strip_edges().is_valid_int():
				return 0.0
			s = s * 60.0 + float(int(part))
		return s
	return maxf(float(t), 0.0) if t.is_valid_float() else 0.0


static func limit_text(secs: float) -> String:
	if secs <= 0.0:
		return ""
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]


## The bot's options worth passing: the preset, and every option whose value differs from the preset's.
static func bot_diff(preset: String, preset_vals: Dictionary, cur: Dictionary) -> Dictionary:
	var out := {"preset": preset}
	for k in cur:
		if str(k) == "preset":
			continue
		var pv = preset_vals.get(k)
		var v = cur[k]
		if pv == null:
			out[k] = v
		elif (pv is float or pv is int) and (v is float or v is int):
			if absf(float(pv) - float(v)) > 0.0001:
				out[k] = v
		elif str(pv) != str(v):
			out[k] = v
	return out


## The Sim result for the charts' grey line: the first of the setup's refs (newest first) with the run's hero, map and
## board. {path, label} or {}.
static func ref_for(refs: Array, hero: String, map_id: String, p: Dictionary, stage: int = 1) -> Dictionary:
	for r in refs:
		if not (r is Dictionary):
			continue
		# pass 87 (lane STOOLS): a Sim of the same stage (a whole-run Sim from before pass 87 only for stage 1)
		var rs := int(r.get("stage", 0))
		if not (rs == stage or (rs == 0 and stage == 1)):
			continue
		if str(r.get("hero", "")) == hero and str(r.get("map", "red_canyon")) == map_id and same_board(picks_from(str(r.get("talents", "none"))), p):
			return {"path": str(r.get("path", "")), "label": str(r.get("label", ""))}
	return {}


# ---------------------------------------------------------------- the pop-up

## Builds the pop-up over the whole window (dimmed behind) filled with `s` (defaults_from_args' shape); `setup_doc` the
## setup file; `cancel` whether "Cancel" shows (a run is there to go back to).
func open(s: Dictionary, setup_doc: Dictionary, cancel: bool) -> void:
	doc = setup_doc
	can_cancel = cancel
	_reg = get_node_or_null("/root/Registry")
	_load_bot_consts()
	if _box == null:
		_build()
	_fill(s)
	visible = true
	_cancel_btn.visible = can_cancel
	_err.text = ""
	_fit()


func _load_bot_consts() -> void:
	if not _bot_consts.is_empty():
		return
	if ResourceLoader.exists(BOT_PATH):
		var sc = load(BOT_PATH)
		if sc is GDScript:
			_bot_consts = (sc as GDScript).get_script_constant_map()


func _bot_presets() -> Dictionary:
	var p = _bot_consts.get("PRESETS")
	return p if p is Dictionary else {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)


func _build() -> void:
	theme = _theme()
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", _sbox(PANEL.BG, 8, 16, PANEL.ACCENT))
	add_child(_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_box.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var t := Label.new()
	t.text = "Hero Settings"
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", PANEL.ACCENT)
	head.add_child(t)
	var st := Label.new()
	st.text = "   the run the bot plays next: choose, then Start Run"
	st.add_theme_color_override("font_color", PANEL.DIM)
	st.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(st)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_build_run(left)
	_build_bot(left)
	_build_board(right)
	# the foot: what is wrong, Cancel, Start Run
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	col.add_child(foot)
	_err = Label.new()
	_err.add_theme_color_override("font_color", PANEL.BAD)
	_err.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_err)
	_cancel_btn = _button("Cancel", "close this and go on with the run as it was (Esc)", func() -> void:
		visible = false
		cancelled.emit())
	_cancel_btn.custom_minimum_size = Vector2(110, 40)
	foot.add_child(_cancel_btn)
	_start_btn = _button("Start Run", "start a run with these settings: the hero comes down in the spawn beam (Enter)", _on_start)
	_start_btn.custom_minimum_size = Vector2(170, 40)
	_start_btn.add_theme_stylebox_override("normal", _sbox(PANEL.ACCENT, 5, 8, PANEL.ACCENT))
	_start_btn.add_theme_stylebox_override("hover", _sbox(PANEL.ACCENT.lightened(0.15), 5, 8, PANEL.ACCENT))
	_start_btn.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	_start_btn.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.05))
	_start_btn.add_theme_font_size_override("font_size", 18)
	foot.add_child(_start_btn)


func _fit() -> void:
	if _box == null:
		return
	# the window's size (this control fills it; its own size may not be laid out yet when it opens)
	var win := get_viewport_rect().size if is_inside_tree() else size
	var w := maxf(minf(1240.0, win.x - 40.0), 600.0)
	var h := maxf(minf(900.0, win.y - 40.0), 400.0)
	_box.custom_minimum_size = Vector2.ZERO
	_box.size = Vector2(w, h)
	_box.position = ((win - _box.size) * 0.5).round()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ESCAPE and can_cancel:
		visible = false
		cancelled.emit()
		get_viewport().set_input_as_handled()
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		_on_start()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- the run's part

func _build_run(parent: Control) -> void:
	parent.add_child(_section("The run"))
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 12)
	parent.add_child(hero_row)
	_hero_pic = TextureRect.new()
	_hero_pic.custom_minimum_size = Vector2(84, 84)
	_hero_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var pic_box := PanelContainer.new()
	pic_box.add_theme_stylebox_override("panel", _sbox(PANEL.CARD, 6, 4, PANEL.EDGE))
	pic_box.add_child(_hero_pic)
	hero_row.add_child(pic_box)
	var hg := GridContainer.new()
	hg.columns = 2
	hg.add_theme_constant_override("h_separation", 10)
	hg.add_theme_constant_override("v_separation", 6)
	hg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_row.add_child(hg)
	_hero = OptionButton.new()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.item_selected.connect(func(_i: int) -> void: _hero_changed(""))
	_row(hg, "Hero", _hero, "who plays (hidden heroes too)")
	_look = OptionButton.new()
	_look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_look.item_selected.connect(func(_i: int) -> void: _show_hero())
	_row(hg, "Look", _look, "the art he is played in (his JSON's look by default)")
	_hero_note = Label.new()
	_hero_note.add_theme_color_override("font_color", PANEL.DIM)
	_hero_note.add_theme_font_size_override("font_size", 12)
	hg.add_child(Control.new())
	hg.add_child(_hero_note)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	parent.add_child(g)
	_map = OptionButton.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(g, "Map", _map, "the map")
	# pass 87 (lane STOOLS): the stage the run plays (each stage is its own run)
	var stage_box := VBoxContainer.new()
	stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage = OptionButton.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_box.add_child(_stage)
	_stage_note = Label.new()
	_stage_note.add_theme_color_override("font_color", PANEL.DIM)
	_stage_note.add_theme_font_size_override("font_size", 12)
	_stage_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage_box.add_child(_stage_note)
	_row(g, "Stage", stage_box, "the stage the run plays: a fresh hero at its start, its boss at its end, then the portal's countdown and Endless")
	_map.item_selected.connect(func(_i: int) -> void: _fill_stages(_stage_selected() + 1))
	var seed_row := HBoxContainer.new()
	_seed_random = CheckBox.new()
	_seed_random.text = "Random"
	_seed_random.tooltip_text = "a new seed for every start"
	_seed_random.toggled.connect(func(on: bool) -> void: _seed.editable = not on)
	seed_row.add_child(_seed_random)
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 99999
	_seed.step = 1
	_seed.custom_minimum_size = Vector2(120, 0)
	_seed.tooltip_text = "the run's dice: the map, the crowd, the pickups, the bot"
	seed_row.add_child(_seed)
	_row(g, "Seed", seed_row, "")
	_speed = OptionButton.new()
	for s in CLOCK.SPEEDS:
		_speed.add_item(CLOCK.label(float(s)))
	_row(g, "Speed", _speed, "the speed the run starts at (the header's buttons change it later)")
	_limit = LineEdit.new()
	_limit.placeholder_text = "none: until he falls or gets out"
	_limit.tooltip_text = "the run ends after this much play: 5:00, 300 or 1:02:00; empty = none"
	_row(g, "Time limit", _limit, "")
	_death = OptionButton.new()
	for d in DEATHS:
		_death.add_item("%s: %s" % [str(d[0]), str(d[1])])
	_row(g, "Down!", _death, "how the bot answers Down!")
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 14)
	_sound = CheckBox.new()
	_sound.text = "Sound"
	_sound.tooltip_text = "the game's sound (above 1x it is always off); M in the window"
	sw.add_child(_sound)
	_numbers = CheckBox.new()
	_numbers.text = "Damage numbers"
	_numbers.tooltip_text = "the floating damage numbers (above 2x they are always off)"
	sw.add_child(_numbers)
	_unlocks = CheckBox.new()
	_unlocks.text = "Every unlock"
	_unlocks.tooltip_text = "every unlock quest done: the whole content in the card pool, every stage open (off: the Watch save's quests, none; the PC save's stages)"
	_unlocks.toggled.connect(func(_on: bool) -> void: _fill_stages(_stage_selected() + 1))
	sw.add_child(_unlocks)
	_row(g, "", sw, "")


# ---------------------------------------------------------------- the bot's part

func _build_bot(parent: Control) -> void:
	parent.add_child(_section("The bot"))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	parent.add_child(g)
	_bot_preset = OptionButton.new()
	_bot_preset_ids.clear()
	var presets := _bot_presets()
	var names: Array = presets.keys()
	for nm in ["explorer", "expert", "careless", "sim77"]:
		if names.has(nm):
			_bot_preset_ids.append(nm)
	for nm in names:
		if not _bot_preset_ids.has(nm):
			_bot_preset_ids.append(nm)
	for nm in _bot_preset_ids:
		_bot_preset.add_item(str(nm))
	_bot_preset_ids.append("stub")
	_bot_preset.add_item("stand-in (pass 77's rules, BotStub)")
	_bot_preset.item_selected.connect(func(_i: int) -> void: _preset_to_fields())
	_row(g, "Preset", _bot_preset, "the bot's whole set of options (any option below changes it for this run)")
	g.add_child(Control.new())
	g.add_child(Control.new())
	var k := 0
	for spec in BOT_NUMBERS:
		var sb := SpinBox.new()
		sb.min_value = float(spec[2])
		sb.max_value = float(spec[3])
		sb.step = float(spec[4])
		sb.custom_minimum_size = Vector2(100, 0)
		sb.tooltip_text = str(spec[5])
		_bot_fields[str(spec[0])] = sb
		_row(g, str(spec[1]), sb, str(spec[5]))
		k += 1
	for spec in BOT_CHOICES:
		var ob := OptionButton.new()
		for c in spec[2]:
			ob.add_item(str(c))
		_bot_fields[str(spec[0])] = ob
		_row(g, str(spec[1]), ob, "")
	if (BOT_NUMBERS.size() + BOT_CHOICES.size()) % 2 == 1:
		g.add_child(Control.new())
		g.add_child(Control.new())
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	parent.add_child(flow)
	var bools = _bot_consts.get("BOOL_KEYS", BOOL_WORDS.keys())
	for key in bools:
		var cb := CheckBox.new()
		cb.text = str(BOOL_WORDS.get(str(key), str(key).capitalize()))
		cb.tooltip_text = "goes for %s" % cb.text.to_lower()
		_bot_fields[str(key)] = cb
		flow.add_child(cb)


func _preset_to_fields() -> void:
	var i := _bot_preset.selected
	var name: String = _bot_preset_ids[i] if i >= 0 and i < _bot_preset_ids.size() else "explorer"
	var vals: Dictionary = _bot_presets().get(name, {})
	_set_bot_fields(vals)
	for k in _bot_fields:
		var c: Control = _bot_fields[k]
		if c is BaseButton:
			(c as BaseButton).disabled = name == "stub"
		elif c is SpinBox:
			(c as SpinBox).editable = name != "stub"


func _set_bot_fields(vals: Dictionary) -> void:
	for k in vals:
		var c = _bot_fields.get(str(k))
		if c == null:
			continue
		var v = vals[k]
		if c is SpinBox:
			(c as SpinBox).value = float(v)
		elif c is OptionButton:
			var ob := c as OptionButton
			for j in range(ob.item_count):
				if ob.get_item_text(j) == str(v):
					ob.select(j)
		elif c is CheckBox:
			(c as CheckBox).button_pressed = bool(v) if v is bool else str(v).to_lower() in ["1", "true", "on", "yes"]


func _bot_values() -> Dictionary:
	var out := {}
	for k in _bot_fields:
		var c = _bot_fields[k]
		if c is SpinBox:
			out[k] = snappedf((c as SpinBox).value, 0.001)
		elif c is OptionButton:
			out[k] = (c as OptionButton).get_item_text((c as OptionButton).selected)
		elif c is CheckBox:
			out[k] = (c as CheckBox).button_pressed
	return out


# ---------------------------------------------------------------- the Upgrade board

func _build_board(parent: Control) -> void:
	var h := HBoxContainer.new()
	h.add_child(_section("The Upgrade board"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_board_sum = Label.new()
	_board_sum.add_theme_color_override("font_color", PANEL.DIM)
	h.add_child(_board_sum)
	parent.add_child(h)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	parent.add_child(pr)
	for name in PRESET_ORDER:
		var nm := str(name)
		var b := _button(str(PRESET_WORDS[nm]), "", func() -> void: _use_preset(nm))
		b.toggle_mode = true
		_preset_btns[nm] = b
		pr.add_child(b)
	var help := Label.new()
	help.text = "Each slot is a rank: click a free one to buy up to it (form A), click A for B, click B to sell it and the ranks above."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", PANEL.DIM)
	help.add_theme_font_size_override("font_size", 12)
	parent.add_child(help)
	_talent_ids.clear()
	_talent_defs.clear()
	var list: Array = _reg.talents_list() if _reg != null and _reg.has_method("talents_list") else []
	for td in list:
		_talent_ids.append(str(td.id))
		_talent_defs[str(td.id)] = td
	for id in _talent_ids:
		var td = _talent_defs[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(26, 26)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = td.form_icon(0) if td.form_icon(0) != null else td.icon
		row.add_child(ic)
		var nm := VBoxContainer.new()
		nm.add_theme_constant_override("separation", -2)
		nm.custom_minimum_size = Vector2(190, 0)
		row.add_child(nm)
		var l := Label.new()
		l.text = str(td.display_name)
		nm.add_child(l)
		var f := Label.new()
		f.text = "A %s · B %s" % [td.form_name(0), td.form_name(1)]
		f.add_theme_color_override("font_color", PANEL.DIM)
		f.add_theme_font_size_override("font_size", 11)
		f.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		f.custom_minimum_size = Vector2(190, 0)
		nm.add_child(f)
		var slots: Array = []
		for k in range(maxi(int(td.max_rank()), 1)):
			var tid := str(id)
			var kk := k
			var b := _button("", "", func() -> void: _slot_clicked(tid, kk))
			b.custom_minimum_size = Vector2(38, 30)
			slots.append(b)
			row.add_child(b)
		_slots[id] = slots


func _slot_clicked(id: String, k: int) -> void:
	picks[id] = click_slot(picks.get(id, []), k)
	if (picks[id] as Array).is_empty():
		picks.erase(id)
	_show_board()


func _use_preset(name: String) -> void:
	var b = (doc.get("presets", {}) as Dictionary).get(name) if doc.get("presets") is Dictionary else null
	if b is Dictionary:
		picks = picks_from(b)
	elif name == "none":
		picks = {}
	_show_board()


func _show_board() -> void:
	for id in _slots:
		var arr: Array = picks.get(id, [])
		var td = _talent_defs.get(id)
		var slots: Array = _slots[id]
		for k in range(slots.size()):
			var b: Button = slots[k]
			if k < arr.size():
				var f := int(arr[k])
				b.text = "B" if f == 1 else "A"
				b.tooltip_text = "rank %d: %s (click: %s)" % [k + 1, td.form_name(f) if td else "", "sell it and the ranks above" if f == 1 else "the other form"]
				b.add_theme_stylebox_override("normal", _sbox(Color(FORM_COLS[f], 0.85), 4, 4, FORM_COLS[f]))
				b.add_theme_stylebox_override("hover", _sbox(Color(FORM_COLS[f], 1.0), 4, 4, Color.WHITE))
				b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
				b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.1))
			else:
				b.text = "·"
				b.tooltip_text = "rank %d: buy up to here (form A)" % (k + 1)
				b.remove_theme_stylebox_override("normal")
				b.remove_theme_stylebox_override("hover")
				b.remove_theme_color_override("font_color")
				b.remove_theme_color_override("font_hover_color")
	var presets: Dictionary = doc.get("presets", {}) if doc.get("presets") is Dictionary else {}
	var labels: Dictionary = doc.get("labels", {}) if doc.get("labels") is Dictionary else {}
	_board_sum.text = board_words(picks, presets, labels, _talent_ids.size())
	var pre := preset_of(picks, presets)
	for name in _preset_btns:
		var b: Button = _preset_btns[name]
		b.set_pressed_no_signal(name == pre)
		var have = presets.get(name)
		b.disabled = name != "none" and not (have is Dictionary)
		if name == "save":
			b.tooltip_text = "the PC save's Upgrade board (read only)" if have is Dictionary else "no PC save to read: %s" % str(doc.get("save_note", "not given"))
		else:
			b.tooltip_text = "the Sim's %s board" % str(labels.get(name, PRESET_WORDS[name])).to_lower()


# ---------------------------------------------------------------- filling and reading

func _fill(s: Dictionary) -> void:
	# heroes: every one, in their order (hidden ones last, marked)
	_hero.clear()
	_hero_ids.clear()
	var all: Array = []
	if _reg != null:
		all = (_reg.get("characters") as Dictionary).values()
	all.sort_custom(func(a, b) -> bool:
		if bool(a.hidden) != bool(b.hidden):
			return not bool(a.hidden)
		return str(a.id) < str(b.id) if int(a.order) == int(b.order) else int(a.order) < int(b.order))
	for c in all:
		_hero_ids.append(str(c.id))
		_hero.add_item(str(c.display_name) + (" (hidden)" if bool(c.hidden) else ""))
	var hi := _hero_ids.find(str(s.get("hero", "drifter")))
	_hero.select(maxi(hi, 0))
	_hero_changed(str(s.get("look", "")))
	_map.clear()
	_map_ids.clear()
	if _reg != null:
		for m in _reg.sorted_maps():
			_map_ids.append(str(m.id))
			_map.add_item(str(m.display_name) if str(m.display_name) != "" else str(m.id))
	_map.select(maxi(_map_ids.find(str(s.get("map", "red_canyon"))), 0))
	_seed.value = maxi(int(s.get("seed", 1)), 1)
	_seed_random.button_pressed = bool(s.get("seed_random", false))
	_seed.editable = not _seed_random.button_pressed
	var si := CLOCK.SPEEDS.find(CLOCK.nearest(float(s.get("speed", 1.0))))
	_speed.select(maxi(si, 0))
	_limit.text = limit_text(float(s.get("limit", 0.0)))
	var di := 0
	for j in range(DEATHS.size()):
		if str(DEATHS[j][0]) == str(s.get("death", "end")):
			di = j
	_death.select(di)
	_sound.button_pressed = bool(s.get("sound", false))
	_numbers.button_pressed = bool(s.get("numbers", true))
	_unlocks.button_pressed = str(s.get("unlocks", "all")) == "all"
	_fill_stages(int(s.get("stage", 1)))
	# the bot: its preset's values, the options given laid over
	var opts: Dictionary = s.get("bot_opts", {})
	var pre := "stub" if str(s.get("bot", "auto")) == "stub" else str(opts.get("preset", _bot_consts.get("DEFAULT_PRESET", "explorer")))
	_bot_preset.select(maxi(_bot_preset_ids.find(pre), 0))
	_preset_to_fields()
	var over := {}
	for k in opts:
		if str(k) != "preset":
			over[k] = opts[k]
	_set_bot_fields(over)
	picks = picks_from(str(s.get("talents", "none")))
	_show_board()


func _hero_changed(look: String) -> void:
	var c = _hero_def()
	_look.clear()
	_look_codes.clear()
	if c == null:
		return
	var codes: Array = c.variant_codes()
	var own := str(c.variant)
	_look_codes.append("")
	_look.add_item("his own%s" % ((" (%s)" % own) if own != "" else ""))
	for code in codes:
		_look_codes.append(str(code))
		var note := str(c.variant_note(str(code)))
		_look.add_item(str(code) + ((": " + note.substr(0, 40)) if note != "" else ""))
	_look.select(maxi(_look_codes.find(look), 0))
	_show_hero()


func _hero_def():
	var i := _hero.selected
	if _reg == null or i < 0 or i >= _hero_ids.size():
		return null
	return _reg.character(_hero_ids[i])


func _show_hero() -> void:
	var c = _hero_def()
	if c == null:
		_hero_pic.texture = null
		return
	var li := _look.selected
	var code: String = _look_codes[li] if li >= 0 and li < _look_codes.size() else ""
	var d = c.variant_def(code)
	_hero_pic.texture = d.icon if d.icon != null else c.icon
	var bits := PackedStringArray()
	if bool(c.hidden):
		bits.append("hidden")
	var lc := str(d.look_code())
	if lc != "":
		bits.append("plays look " + lc)
	_hero_note.text = " · ".join(bits)


## The settings as chosen (the shape defaults_from_args gives).
func collect() -> Dictionary:
	var hi := _hero.selected
	var li := _look.selected
	var bi := _bot_preset.selected
	var preset: String = _bot_preset_ids[bi] if bi >= 0 and bi < _bot_preset_ids.size() else "explorer"
	var presets: Dictionary = doc.get("presets", {}) if doc.get("presets") is Dictionary else {}
	var labels: Dictionary = doc.get("labels", {}) if doc.get("labels") is Dictionary else {}
	var s := {"hero": _hero_ids[hi] if hi >= 0 and hi < _hero_ids.size() else "drifter",
		"look": _look_codes[li] if li >= 0 and li < _look_codes.size() else "",
		"map": _map_ids[_map.selected] if _map.selected >= 0 and _map.selected < _map_ids.size() else "red_canyon",
		"stage": _stage_selected() + 1,
		"seed": int(_seed.value), "seed_random": _seed_random.button_pressed,
		"speed": float(CLOCK.SPEEDS[maxi(_speed.selected, 0)]), "limit": limit_secs(_limit.text),
		"death": str(DEATHS[maxi(_death.selected, 0)][0]), "sound": _sound.button_pressed, "numbers": _numbers.button_pressed,
		"unlocks": "all" if _unlocks.button_pressed else "save", "talents": letters_of(picks, _talent_ids),
		"board_label": board_words(picks, presets, labels, _talent_ids.size()),
		"bot": "stub" if preset == "stub" else "auto"}
	s["bot_opts"] = {} if preset == "stub" else bot_diff(preset, _bot_presets().get(preset, {}), _bot_values())
	return s


# ---------------------------------------------------------------- the stage row (pass 87, lane STOOLS)

## Whether stage `k` (0-based) may be chosen: every stage in tool mode (`all`), else stage 1 and each one whose stage
## before is beaten in `beaten` (the PC save's flags for the map, as Save.stage_unlocked).
static func stage_open(beaten: Array, k: int, all: bool) -> bool:
	if all or k <= 0:
		return true
	return k - 1 < beaten.size() and bool(beaten[k - 1])


## The stage the row shows (0-based; 0 before it is filled).
func _stage_selected() -> int:
	if _stage == null or _stage.selected < 0 or _stage.selected >= _stage_idx.size():
		return 0
	return int(_stage_idx[_stage.selected])


## The map's stages into the row (its name, length and boss), the locked ones greyed in the save's mode; `want` (1-based)
## chosen when it may be, else the last open stage before it.
func _fill_stages(want: int) -> void:
	if _stage == null:
		return
	_stage.clear()
	_stage_idx.clear()
	var map_id: String = _map_ids[_map.selected] if _map.selected >= 0 and _map.selected < _map_ids.size() else "red_canyon"
	var mdef = _reg.map(map_id) if _reg != null else null
	var tl = mdef.timeline if mdef != null else null
	var n := 1
	if tl != null:
		n = int(tl.call("stage_count")) if tl.has_method("stage_count") else maxi(int(tl.stages), 1)
	var all := _unlocks == null or _unlocks.button_pressed
	var saved: Dictionary = doc.get("save_stages", {}) if doc.get("save_stages") is Dictionary else {}
	var beaten: Array = saved.get(map_id, []) if saved.get(map_id) is Array else []
	var pick := 0
	var opened: Array = []
	for k in range(n):
		var nm := "Stage %d" % (k + 1)
		var words := ""
		if tl != null and tl.has_method("stage_name"):
			nm = str(tl.call("stage_name", k))
			var boss := str(tl.call("stage_boss", k))
			var bdef = _reg.enemy(boss) if _reg != null and boss != "" else null
			var secs := int(round(float(tl.call("stage_len", k))))
			words = " (%d:%02d%s)" % [secs / 60, secs % 60, (", " + (str(bdef.display_name) if bdef != null else boss)) if boss != "" else ""]
		var ok := stage_open(beaten, k, all)
		_stage.add_item("Stage %d%s%s%s" % [k + 1, (" · " + nm) if nm != "Stage %d" % (k + 1) else "", words, "" if ok else " · locked"])
		_stage_idx.append(k)
		_stage.set_item_disabled(_stage.item_count - 1, not ok)
		if ok:
			opened.append(k + 1)
			if k + 1 <= maxi(want, 1):
				pick = k
	_stage.select(pick)
	if all:
		_stage_note.text = "tool mode (Every unlock on): every stage"
	elif str(doc.get("save_stages_note", "")).begins_with("no save"):
		_stage_note.text = "the save's mode: no PC save read, stage 1 only"
	else:
		_stage_note.text = "the save's mode: the stages the PC save has unlocked (%s)" % ", ".join(PackedStringArray(opened.map(func(x) -> String: return str(x))))


func _on_start() -> void:
	if _limit.text.strip_edges() != "" and limit_secs(_limit.text) <= 0.0 and _limit.text.strip_edges() != "0":
		_err.text = "the time limit reads as 5:00, 300 or 1:02:00"
		return
	visible = false
	started.emit(collect())


# ---------------------------------------------------------------- the pieces

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	for cls in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit"]:
		th.set_color("font_color", cls, PANEL.TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	th.set_color("font_disabled_color", "Button", PANEL.DIM)
	th.set_stylebox("normal", "Button", _sbox(Color(0.15, 0.165, 0.2), 4, 6, PANEL.EDGE))
	th.set_stylebox("hover", "Button", _sbox(Color(0.2, 0.22, 0.27), 4, 6, Color(0.35, 0.38, 0.45)))
	th.set_stylebox("pressed", "Button", _sbox(PANEL.ACCENT, 4, 6, PANEL.ACCENT))
	th.set_stylebox("disabled", "Button", _sbox(Color(0.12, 0.13, 0.16), 4, 6, PANEL.EDGE))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for cls in ["OptionButton"]:
		th.set_stylebox("normal", cls, _sbox(Color(0.15, 0.165, 0.2), 4, 8, PANEL.EDGE))
		th.set_stylebox("hover", cls, _sbox(Color(0.2, 0.22, 0.27), 4, 8, Color(0.35, 0.38, 0.45)))
		th.set_stylebox("pressed", cls, _sbox(Color(0.2, 0.22, 0.27), 4, 8, PANEL.ACCENT))
		th.set_stylebox("focus", cls, StyleBoxEmpty.new())
	# the check boxes: a quiet box, the tick says it (not the pressed button's orange)
	for st in ["normal", "pressed", "hover", "hover_pressed"]:
		th.set_stylebox(st, "CheckBox", _sbox(Color(0.12, 0.13, 0.16) if not st.begins_with("hover") else Color(0.17, 0.18, 0.22), 4, 6, PANEL.EDGE))
	th.set_color("font_pressed_color", "CheckBox", PANEL.TEXT)
	th.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	th.set_stylebox("normal", "LineEdit", _sbox(Color(0.06, 0.065, 0.08), 4, 8, PANEL.EDGE))
	th.set_stylebox("focus", "LineEdit", _sbox(Color(0.06, 0.065, 0.08), 4, 8, PANEL.ACCENT))
	th.set_stylebox("read_only", "LineEdit", _sbox(Color(0.1, 0.105, 0.12), 4, 8, PANEL.EDGE))
	th.set_color("font_uneditable_color", "LineEdit", PANEL.DIM)
	th.set_stylebox("panel", "PopupMenu", _sbox(Color(0.12, 0.13, 0.16), 4, 6, PANEL.EDGE))
	th.set_color("font_color", "PopupMenu", PANEL.TEXT)
	th.set_stylebox("panel", "TooltipPanel", _sbox(Color(0.05, 0.05, 0.07), 4, 6, PANEL.EDGE))
	th.set_color("font_color", "TooltipLabel", PANEL.TEXT)
	return th


func _sbox(col: Color, radius: int, pad: int, edge: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad - 2, 0)
	s.content_margin_bottom = maxi(pad - 2, 0)
	if edge.a > 0.0:
		s.border_color = edge
		s.set_border_width_all(1)
	return s


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", PANEL.ACCENT)
	l.add_theme_font_size_override("font_size", 13)
	return l


func _row(g: GridContainer, label: String, ctl: Control, tip: String) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", PANEL.DIM)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	g.add_child(l)
	if tip != "" and ctl.tooltip_text == "":
		ctl.tooltip_text = tip
	g.add_child(ctl)


func _button(text: String, tip: String, cb: Callable) -> Button:
	var bt := Button.new()
	bt.text = text
	bt.tooltip_text = tip
	bt.focus_mode = Control.FOCUS_NONE
	bt.pressed.connect(cb)
	return bt
