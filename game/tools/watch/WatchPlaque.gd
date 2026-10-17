## The bot's goal plaque (pass 85, lane TOOLS; Garry: "Add a plaque somewhere showing bot current goal - running away,
## looking for <>, choosing level, etc. They should switch as the bot changes their goal."): a dark plaque over the top of
## the phone view's bottom, above the speed badge, with the bot's goal in a player's words ("Running away", "Kiting", "Going to
## a Totem Pole", "Grabbing a power-up: Heart", "Hunting a special: Red Goblin", "Picking a level-up", "At the shop" ...)
## and a small line of why (the goal's own reason). It changes with a short fade (FADE_S) when the words change; a word
## held under HOLD_S is not shown (the kite and a dodge flip every few frames: the plaque would flicker). The words come
## from words_of (pure; tests/pass85_tools_test.gd): the run's state, the screen up, the bot's intent, its goal, the hold
## and its legs. Tools only.
extends PanelContainer

const FADE_S := 0.3
const HOLD_S := 0.35
## tones: the colour of the plaque's edge and dot
const TONES := {"danger": Color(0.95, 0.42, 0.36), "screen": Color(0.43, 0.71, 1.0), "goal": Color(0.93, 0.66, 0.26),
	"calm": Color(0.56, 0.6, 0.68), "special": Color(0.95, 0.55, 0.8)}

var shown := ""
var _want := {}
var _want_ms := 0
var _title: Label
var _sub: Label
var _dot: ColorRect
var _style: StyleBoxFlat
var _tw: Tween
var _view_pos := Vector2.ZERO
var _view_size := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.05, 0.055, 0.07, 0.86)
	_style.set_corner_radius_all(7)
	_style.border_color = TONES["calm"]
	_style.set_border_width_all(0)
	_style.border_width_left = 4
	_style.content_margin_left = 12
	_style.content_margin_right = 14
	_style.content_margin_top = 5
	_style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", _style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 9)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var dot_box := CenterContainer.new()
	dot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot_box)
	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(10, 10)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_box.add_child(_dot)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var cap := Label.new()
	cap.text = "BOT"
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color(0.56, 0.6, 0.68))
	v.add_child(cap)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 12)
	_sub.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_sub)
	visible = false


## Where it sits: the phone view's bottom middle, above the speed badge, as wide as it needs up to the view's width less a
## margin.
func place(view_pos: Vector2, view_size: Vector2) -> void:
	_view_pos = view_pos
	_view_size = view_size
	_place()


func _place() -> void:
	if _view_size.x <= 0.0:
		return
	var maxw := _view_size.x - 24.0
	# the labels trim themselves (their own minimum width is next to nothing): each is given its text's width, up to
	# what the view leaves
	var room := maxf(maxw - 50.0, 40.0)
	_title.custom_minimum_size.x = minf(_text_w(_title, 20), room)
	_sub.custom_minimum_size.x = minf(_text_w(_sub, 12), room) if _sub.visible else 0.0
	custom_minimum_size = Vector2(minf(220.0, maxw), 0)
	reset_size()
	size = get_combined_minimum_size()
	# the bottom middle, above the speed badge (the HUD's banners and toasts own the top)
	position = Vector2(_view_pos.x + (_view_size.x - size.x) * 0.5, _view_pos.y + _view_size.y - size.y - 64.0).round()


func _text_w(l: Label, fs: int) -> float:
	var f := l.get_theme_font("font")
	if f == null or l.text == "":
		return 0.0
	return ceilf(f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 2.0


func reset() -> void:
	shown = ""
	_want = {}
	_want_ms = 0
	visible = false


## The words `d` ({text, sub, tone}; text "" hides it): a change waits HOLD_S (wall seconds of frames) before it shows,
## then fades in over FADE_S.
func show_words(d: Dictionary) -> void:
	var txt := str(d.get("text", ""))
	if txt == "":
		visible = false
		shown = ""
		_want = {}
		return
	if txt == shown:
		var sub := str(d.get("sub", ""))
		if sub != _sub.text:
			_sub.text = sub
			_sub.visible = sub != ""
			_place()
		_want = {}
		return
	if str(_want.get("text", "")) != txt:
		_want = d
		_want_ms = Time.get_ticks_msec()
	if shown != "" and float(Time.get_ticks_msec() - _want_ms) < HOLD_S * 1000.0:
		return
	_apply(d)


func _apply(d: Dictionary) -> void:
	shown = str(d.get("text", ""))
	_want = {}
	_title.text = shown
	_sub.text = str(d.get("sub", ""))
	_sub.visible = _sub.text != ""
	var col: Color = TONES.get(str(d.get("tone", "goal")), TONES["goal"])
	_style.border_color = col
	_dot.color = col
	visible = true
	_place()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	modulate.a = 0.2
	_tw = create_tween()
	_tw.set_ignore_time_scale(true)
	_tw.tween_property(self, "modulate:a", 1.0, FADE_S)


# ---------------------------------------------------------------- the words (pure)

## {text, sub, tone} for `info` (Watch.plaque_words): {ended, setup, started, screens ("cards,gate"), path (the cards are
## a mutation offer), spawning, intent (Bot.intent), goal (Bot.goal: what, why, name), hold (the kite holds the goal off),
## nearest (the nearest creature, m), flee_d (the bot's flee distance), bot ("bot" | "stub" | ""), death}.
static func words_of(info: Dictionary) -> Dictionary:
	if bool(info.get("setup", false)):
		return {"text": "Waiting for Start Run", "sub": "Hero Settings: choose the run", "tone": "calm"}
	if bool(info.get("ended", false)):
		return {"text": "Run over", "sub": "", "tone": "calm"}
	if not bool(info.get("started", false)):
		return {"text": "", "sub": "", "tone": "calm"}
	if bool(info.get("spawning", false)):
		return {"text": "Coming down", "sub": "the spawn beam: he lands, then plays", "tone": "calm"}
	var scr: Array = Array(str(info.get("screens", "")).split(",", false))
	if scr.has("revive"):
		return {"text": "Down!", "sub": "answering Down! (%s)" % str(info.get("death", "end")), "tone": "danger"}
	if scr.has("cards"):
		if bool(info.get("path", false)):
			return {"text": "Choosing a mutation", "sub": "the mutation offer at this level-up", "tone": "screen"}
		return {"text": "Picking a level-up", "sub": "three cards: the best by its scores", "tone": "screen"}
	if scr.has("chest"):
		return {"text": "Opening a chest", "sub": "", "tone": "screen"}
	if scr.has("totem"):
		return {"text": "At a Totem Pole", "sub": "choosing a gift", "tone": "screen"}
	if scr.has("shop"):
		return {"text": "At the shop", "sub": "buying what is worth its price", "tone": "screen"}
	if scr.has("stranger"):
		return {"text": "Dealing with the Stranger", "sub": "his ware for HP", "tone": "screen"}
	if scr.has("portal"):
		return {"text": "At the portal", "sub": "", "tone": "screen"}
	if scr.has("pause"):
		return {"text": "Paused", "sub": "the game's own pause screen", "tone": "calm"}
	var intent := str(info.get("intent", ""))
	var goal: Dictionary = info.get("goal", {}) if info.get("goal") is Dictionary else {}
	var why := str(goal.get("why", ""))
	var what := str(goal.get("what", ""))
	var name := str(goal.get("name", ""))
	var fleeing := float(info.get("nearest", INF)) < float(info.get("flee_d", 0.0))
	match intent:
		"":
			return {"text": "Starting", "sub": "", "tone": "calm"}
		"down":
			return {"text": "Down!", "sub": "", "tone": "danger"}
		"dodge":
			return {"text": "Dodging", "sub": "a blast, a big one or a rocket close", "tone": "danger"}
		"kite", "sweep":
			if bool(info.get("hold", false)) and what != "":
				return {"text": "Running away", "sub": "the crowd is on him; then: %s" % goal_text(what, name, why).to_lower(), "tone": "danger"}
			if fleeing:
				return {"text": "Running away", "sub": "a creature too close", "tone": "danger"}
			if intent == "sweep":
				return {"text": "Sweeping up gems", "sub": why if what == "sweep" else "the gems lying round him", "tone": "goal"}
			return {"text": "Kiting", "sub": "keeping the crowd at arm's length", "tone": "calm"}
		"special":
			return {"text": "Hunting a special%s" % ((": " + name) if name != "" else ""), "sub": why, "tone": "special"}
	return {"text": goal_text(intent, name, why), "sub": why, "tone": "goal"}


## A goal's words from its intent / what (Bot's: explore, totem, barrel, powerup, structure:<id>, chest, boss, boss_chest,
## portal, special), its thing's name ("" unknown) and why.
static func goal_text(what: String, name: String, why: String) -> String:
	if what.begins_with("structure:"):
		var sid := what.substr(10)
		match sid:
			"shop":
				return "Going to the shop"
			"hooded_figure", "stranger":
				return "Going to the Stranger"
		return "Going to the %s" % (name if name != "" else sid.replace("_", " ").capitalize())
	match what:
		"explore":
			return "Exploring the map"
		"totem":
			return "Going to a Totem Pole"
		"barrel":
			return "Breaking a barrel"
		"powerup":
			return "Grabbing a power-up%s" % ((": " + name) if name != "" else "")
		"chest":
			return "Going for a chest"
		"boss":
			return "Back to the boss"
		"boss_chest":
			return "Opening the boss's chest"
		"portal":
			return "Heading for the portal"
		"special":
			return "Hunting a special%s" % ((": " + name) if name != "" else "")
		"sweep", "gems":
			return "Sweeping up gems"
	if what == "":
		return why.capitalize() if why != "" else "Playing"
	return what.replace("_", " ").capitalize()
