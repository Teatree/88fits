## The way back (pass 129, lane TRAIL-UI; Garry: "Clicking on these unlock requirement messages will always transport
## the player to the Trail screen. Coming back from it will cause the player to come back where they were before.").
## A small stack of {scene, state}: `Nav.to_trail(type, id)` from any hub screen remembers that screen and what it showed
## (the screen's own `nav_state() -> Dictionary`, {} without one) and opens the Trail on that thing's node; the Trail's
## Back calls `Nav.back()`, which goes to the remembered scene, and that screen asks `Nav.take(<its scene path>)` in its
## build() for the state to restore (once: {} at any other time). Arriving on the Trail through the tab bar forgets the
## stack (TrailScreen calls `Nav.arrived()`: false there), so Back is the title as on every hub screen.
## What each screen keeps: Outlaws {hero, looks}, the title {hero, sheet}, the Collection {tab, item}, Stages {scroll}.
class_name Nav
extends RefCounted

const TRAIL := "res://ui/TrailScreen.tscn"

static var _stack: Array = []
static var _restore: Dictionary = {}
static var _arriving := false
## A test or a tool: where a scene change goes instead of UiFx.go (a Callable(path: String)).
static var navigate: Callable


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
		return
	var t := _tree()
	if t:
		UiFx.go(t, path)


## Remembers the screen showing now (its scene and its nav_state()) and opens the Trail on the node that gives `type`
## `id` (docs/trail_schema.md rule 7). Nothing happens without a current scene or while the Trail has no node for it
## (false). `from` names the screen to remember in place of the current scene (a test).
static func to_trail(type: String, id: String, from: Node = null) -> bool:
	var t := _tree()
	var cur: Node = from if from else (t.current_scene if t else null)
	if cur == null or not Trail.gated(type, id) or not trail_open():
		return false
	var state: Dictionary = {}
	if cur.has_method("nav_state"):
		var s: Variant = cur.call("nav_state")
		if s is Dictionary:
			state = s
	_stack.append({"scene": str(cur.scene_file_path), "state": state})
	_arriving = true
	var script: Variant = load("res://ui/TrailScreen.gd")
	if script:
		script.call("open_on", type, id)
	_go(TRAIL)
	return true


## Pass 137 (lane TUTOR): whether the Trail is open to the player (Save.trail_open: the first run counted; true without a
## save, as in a tool). Until then to_trail opens nothing (its callers say ui_locked).
static func trail_open() -> bool:
	var save := W.node("Save")
	return save == null or not save.has_method("trail_open") or bool(save.call("trail_open"))


## The Trail asks once, as it is built: true when it was opened by to_trail (its Back is Nav.back); false forgets the
## stack (it was opened by the tab bar or a tool).
static func arrived() -> bool:
	var was := _arriving
	_arriving = false
	if not was:
		_stack.clear()
	return was and not _stack.is_empty()


## Back to the screen remembered last: true when there was one (the caller goes to the title otherwise).
static func back() -> bool:
	if _stack.is_empty():
		return false
	var e: Dictionary = _stack.pop_back()
	var scene := str(e.get("scene", ""))
	if scene == "" or not ResourceLoader.exists(scene):
		return false
	_restore = {"scene": scene, "state": e.get("state", {})}
	_go(scene)
	return true


## The state to restore for the screen whose scene is `scene`, handed out once after Nav.back() went there ({} at any
## other time, and for any other scene).
static func take(scene: String) -> Dictionary:
	if _restore.is_empty() or str(_restore.get("scene", "")) != scene:
		return {}
	var s: Variant = _restore.get("state", {})
	_restore = {}
	return s if s is Dictionary else {}


## How many screens are remembered (tests).
static func depth() -> int:
	return _stack.size()


## Forgets everything (a test, a tool).
static func clear() -> void:
	_stack.clear()
	_restore = {}
	_arriving = false
