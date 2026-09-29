## Player-facing settings. Persisted inside the save file.
extends Node

signal changed

## 0 = fixed, north always up (the Archero / Survivor.io camera); 1 = follow, the chase camera behind the hero
var camera_mode: int = 0
## Joystick radius multiplier (0.6 small and twitchy .. 1.4 big and precise)
var stick_size: float = 1.0
var screen_shake: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 0.8
var show_hints: bool = true
var debug_panel: bool = false
## Developer menu switches (pass 38, the Wanted UI): the debug hand on the pick screens, the free revive on Down!, and
## the hit log with its copy button on Down!. All off for players.
var debug_modal_buttons: bool = false
var free_revive_button: bool = false
var hit_log: bool = false
## Developer menu: the title's carousel also shows the hidden heroes, locked, to see how a locked hero reads.
var preview_locked_heroes: bool = false


func to_dict() -> Dictionary:
	return {
		"camera_mode": camera_mode, "stick_size": stick_size,
		"screen_shake": screen_shake, "sfx_volume": sfx_volume, "music_volume": music_volume,
		"show_hints": show_hints, "debug_panel": debug_panel,
		"debug_modal_buttons": debug_modal_buttons, "free_revive_button": free_revive_button, "hit_log": hit_log,
		"preview_locked_heroes": preview_locked_heroes,
	}


func from_dict(d: Dictionary) -> void:
	camera_mode = clampi(int(d.get("camera_mode", camera_mode)), 0, 1)
	stick_size = clampf(float(d.get("stick_size", stick_size)), 0.6, 1.4)
	screen_shake = float(d.get("screen_shake", screen_shake))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	music_volume = float(d.get("music_volume", music_volume))
	show_hints = bool(d.get("show_hints", show_hints))
	debug_panel = bool(d.get("debug_panel", debug_panel))
	debug_modal_buttons = bool(d.get("debug_modal_buttons", debug_modal_buttons))
	free_revive_button = bool(d.get("free_revive_button", free_revive_button))
	hit_log = bool(d.get("hit_log", hit_log))
	preview_locked_heroes = bool(d.get("preview_locked_heroes", preview_locked_heroes))
	changed.emit()


func set_value(key: String, value) -> void:
	set(key, value)
	changed.emit()
	Save.request_save()


func camera_name() -> String:
	return ["Fixed · north up", "Follow · behind the hero"][clampi(camera_mode, 0, 1)]
