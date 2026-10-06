## First-play hints (design bible section 11; the Wanted handoff's first run): three lines in the HUD's toast slot over
## the first 30 s, "Drag anywhere to walk" until the hero moves, "He shoots by himself" (the hero's own pronoun) for a
## few seconds after, "The purple is XP" until the first gem. Each appears once and is remembered (the save's hint ids
## are the old ones, so a player who saw the old hints is not shown these again); the switch in Settings turns them off.
## The level-up card frame carries the fourth ("the plate's colour says what it is", CardScreen; the rarity seals went in pass 43).
class_name Hints
extends Control

## How long "shoots by himself" stays up once the hero is walking.
const SHOOT_HOLD := 5.0
## "The purple is XP" gives up after this long if no gem has been picked up.
const XP_HOLD := 12.0

var game: Node
var _step := ""
var _t := 0.0
var _pause_toast_done := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func begin() -> void:
	if not Settings.show_hints or game == null:
		return
	if not Save.hint_seen("hold"):
		_show("hold", "Drag anywhere to walk")
		game.player.moved_first.connect(func(): _done("hold"), CONNECT_ONE_SHOT)
	elif not Save.hint_seen("slide"):
		_show("slide", _shoots())
	elif not Save.hint_seen("gems"):
		_show("gems", "The purple is XP")


## "He shoots by himself", in the hero's words.
func _shoots() -> String:
	var p := Run.character.pronoun if Run.character else "they"
	match p:
		"he":
			return "He shoots by himself"
		"she":
			return "She shoots by herself"
	return "They shoot by themselves"


func _show(step: String, text: String) -> void:
	_step = step
	_t = 0.0
	if game and game.hud:
		game.hud.hint(text)


func _done(step: String) -> void:
	if _step != step:
		return
	Save.mark_hint(step)
	_step = ""
	if game and game.hud:
		game.hud.clear_hint()
	match step:
		"hold":
			if not Save.hint_seen("slide"):
				_show("slide", _shoots())
		"slide":
			if not Save.hint_seen("gems"):
				_show("gems", "The purple is XP")


func tick(delta: float) -> void:
	if game == null or not Settings.show_hints:
		return
	_t += delta
	match _step:
		"slide":
			if _t > SHOOT_HOLD:
				_done("slide")
		"gems":
			if Run.xp > 0.0 or Run.level > 1 or _t > XP_HOLD:
				_done("gems")
		"":
			if not _pause_toast_done and Run.elapsed >= 90.0 and not Save.hint_seen("pause"):
				_pause_toast_done = true
				Save.mark_hint("pause")
				game.toast("Tap the pause disc for your build", W.PAPER)
