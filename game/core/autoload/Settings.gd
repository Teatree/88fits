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
## The numbers that float up off a creature when it is hit (pass 46, ui/DamageNumbers.gd); on unless switched off.
var damage_numbers: bool = true
## The other floating text (pass 47b, Garry: a switch for each kind and three sizes): heals over the hero, the "+N XP"
## and the "+N" coins rising off him; `float_size` 0 small, 1 normal, 2 large scales all of it, damage included.
var float_heal: bool = true
var float_xp: bool = true
var float_coins: bool = true
var float_size: int = 1
const FLOAT_SCALES := [0.75, 1.0, 1.3]
var debug_panel: bool = false
## Developer menu switches (pass 38, the Wanted UI): the debug hand on the pick screens, the free revive on Down!, and
## the hit log with its copy button on Down! (pass 46: no longer on Results). All off for players.
var debug_modal_buttons: bool = false
var free_revive_button: bool = false
var hit_log: bool = false
## Developer menu: the title's carousel also shows the hidden heroes, locked, to see how a locked hero reads.
var preview_locked_heroes: bool = false
## The top inset the UI keeps clear of a camera cutout, in design px: -1 = what the phone reports (W.safe_top).
var top_inset: int = -1
## The title's look (pass 52, Garry: "a button in the Settings that's only available if the Debug mode is on ... switching
## between those 2 Main Menu versions"): "painted", the hero's painted cut-out over the still of the desert, or "live",
## the level itself behind the title with the hero standing in it as a run draws him and his weapon circling him
## (ui/TitleStage.gd). Settings shows the choice only while debug_mode is on; the title reads it each time it is built.
## "live" is the default since pass 53 (Garry: "By default set the Main Menu to be the new one - the one with the live
## heroes"); a save from before it carries "painted" written by to_dict, so Save's version 5 migration sets it to live
## once, and anything but the two names reads as live.
const MENU_STYLES := ["painted", "live"]
const MENU_STYLE_DEFAULT := "live"
var menu_style: String = MENU_STYLE_DEFAULT:
	set(v):
		menu_style = str(v) if MENU_STYLES.has(str(v)) else MENU_STYLE_DEFAULT
## The player's own debug switch (pass 44): ten taps on the first-play hints switch in Settings flip it (and ten more
## on the next visit flip it back). On: the arena on the title, the debug hand on the pick screens, holding the
## clock, a free respawn and the last hits on Down! (pass 46: the hits moved there from the Results screen).
var debug_mode: bool = false
## Ranged weapons aim only at what is on the screen (pass 54, Garry: "+1 m margin"; homing weapons, the Rocket Pod, the
## Killer Bees, the Tarantula Hawk and the seekers, still hunt anywhere): EnemyManager's target picks skip a creature off
## the screen while this is on. Settings shows the switch only in debug mode (the Debug panel); on for everyone.
var ranged_on_screen: bool = true
## The pierce drop-off (pass 62, Garry: "add an option to toggle this on and off in the Debug version of the Settings"):
## on, a weapon with `params.pierce_falloff` (the Boomstick, Tommy Gun, Revolver, Spear, Turret Buddy and their
## evolutions) hits its first enemy x first_mult and each it pierces after x step of the one before
## (ProjectileManager.falloff_factor, the Spear's thrust too); off, exactly the old numbers. Settings shows the switch
## only in debug mode (the Debug panel) and in the developer menu; on for everyone.
var pierce_falloff: bool = true
## The debug arena's training dummies (pass 48, the developer menu and the arena's WORLD tab; lane L5 lays them out):
## how many stand in the field (never fewer than 10), and their health: 0 = undying (a hit refills them), else that much
## HP, and one that dies comes back.
var dummy_count: int = 10:
	set(v):
		dummy_count = maxi(v, 10)
var dummy_hp: int = 0:
	set(v):
		dummy_hp = maxi(v, 0)
## The steps the developer menu and the arena's WORLD tab offer for them (pass 48): health 0 (undying) .. 10000, count
## 10 .. 30.
const DUMMY_HP_STEPS := [0, 100, 500, 2000, 10000]
const DUMMY_COUNT_STEPS := [10, 15, 20, 30]
## Pass 49, the arena's dummies grow (Garry's list; Game lays them out, the WORLD tab and the developer menu set these):
## the field patrols (`dummy_patrol`: each field dummy walks left and right round its spot, and an attacker with nothing
## to hit does too); the attackers added from the WORLD tab have their own health (`attacker_dummy_hp`, 0 = undying);
## the Elite dummy and the Boss dummy that stand apart from the field have a health each (0 = undying) and a behaviour
## each, one of DUMMY_MODES (stand, patrol, melee: chases and bites, ranged: spits like the Spit Cactus).
var dummy_patrol: bool = false
var attacker_dummy_hp: int = 0:
	set(v):
		attacker_dummy_hp = maxi(v, 0)
var elite_dummy_hp: int = 2000:
	set(v):
		elite_dummy_hp = maxi(v, 0)
var boss_dummy_hp: int = 10000:
	set(v):
		boss_dummy_hp = maxi(v, 0)
var elite_dummy_mode: String = "stand":
	set(v):
		elite_dummy_mode = str(v) if DUMMY_MODES.has(str(v)) else "stand"
var boss_dummy_mode: String = "stand":
	set(v):
		boss_dummy_mode = str(v) if DUMMY_MODES.has(str(v)) else "stand"
const ATTACKER_HP_STEPS := [0, 100, 500, 2000]
const ELITE_DUMMY_HP_STEPS := [0, 500, 2000, 10000, 50000]
const BOSS_DUMMY_HP_STEPS := [0, 2000, 10000, 50000, 200000]
const DUMMY_MODES := ["stand", "patrol", "melee", "ranged"]
## Anonymous play data (pass 57, core/autoload/Analytics.gd): what a run picks, where it falls and how the phone keeps up
## goes to PostHog under a random install id. On by default; it sends only when game/config/analytics.json holds a key
## (an empty key file means nothing is sent or kept, whatever this says). Off stops it and deletes what waits to be sent.
## Pass 59: the play-data card (ui/wanted/WConsent.gd) sets it the first time; the switch is the answer from then on.
var analytics: bool = true
## A couple of questions on the Results screen now and then (pass 59, PostHog Surveys through Analytics): "Questions after
## a run" in Settings, or "Don't ask me again" on the card.
var surveys: bool = true


func to_dict() -> Dictionary:
	return {
		"camera_mode": camera_mode, "stick_size": stick_size,
		"screen_shake": screen_shake, "sfx_volume": sfx_volume, "music_volume": music_volume,
		"show_hints": show_hints, "damage_numbers": damage_numbers, "debug_panel": debug_panel,
		"float_heal": float_heal, "float_xp": float_xp, "float_coins": float_coins, "float_size": float_size,
		"debug_modal_buttons": debug_modal_buttons, "free_revive_button": free_revive_button, "hit_log": hit_log,
		"preview_locked_heroes": preview_locked_heroes, "top_inset": top_inset, "debug_mode": debug_mode,
		"menu_style": menu_style, "ranged_on_screen": ranged_on_screen, "pierce_falloff": pierce_falloff,
		"dummy_count": dummy_count, "dummy_hp": dummy_hp,
		"dummy_patrol": dummy_patrol, "attacker_dummy_hp": attacker_dummy_hp,
		"elite_dummy_hp": elite_dummy_hp, "elite_dummy_mode": elite_dummy_mode,
		"boss_dummy_hp": boss_dummy_hp, "boss_dummy_mode": boss_dummy_mode,
		"analytics": analytics, "surveys": surveys,
	}


func from_dict(d: Dictionary) -> void:
	camera_mode = clampi(int(d.get("camera_mode", camera_mode)), 0, 1)
	stick_size = clampf(float(d.get("stick_size", stick_size)), 0.6, 1.4)
	screen_shake = float(d.get("screen_shake", screen_shake))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	music_volume = float(d.get("music_volume", music_volume))
	show_hints = bool(d.get("show_hints", show_hints))
	damage_numbers = bool(d.get("damage_numbers", damage_numbers))
	float_heal = bool(d.get("float_heal", float_heal))
	float_xp = bool(d.get("float_xp", float_xp))
	float_coins = bool(d.get("float_coins", float_coins))
	float_size = clampi(int(d.get("float_size", float_size)), 0, 2)
	debug_panel = bool(d.get("debug_panel", debug_panel))
	debug_modal_buttons = bool(d.get("debug_modal_buttons", debug_modal_buttons))
	free_revive_button = bool(d.get("free_revive_button", free_revive_button))
	hit_log = bool(d.get("hit_log", hit_log))
	preview_locked_heroes = bool(d.get("preview_locked_heroes", preview_locked_heroes))
	top_inset = int(d.get("top_inset", top_inset))
	debug_mode = bool(d.get("debug_mode", debug_mode))
	menu_style = str(d.get("menu_style", menu_style))
	ranged_on_screen = bool(d.get("ranged_on_screen", ranged_on_screen))
	pierce_falloff = bool(d.get("pierce_falloff", pierce_falloff))
	dummy_count = int(d.get("dummy_count", dummy_count))
	dummy_hp = int(d.get("dummy_hp", dummy_hp))
	dummy_patrol = bool(d.get("dummy_patrol", dummy_patrol))
	attacker_dummy_hp = int(d.get("attacker_dummy_hp", attacker_dummy_hp))
	elite_dummy_hp = int(d.get("elite_dummy_hp", elite_dummy_hp))
	elite_dummy_mode = str(d.get("elite_dummy_mode", elite_dummy_mode))
	boss_dummy_hp = int(d.get("boss_dummy_hp", boss_dummy_hp))
	boss_dummy_mode = str(d.get("boss_dummy_mode", boss_dummy_mode))
	analytics = bool(d.get("analytics", analytics))
	surveys = bool(d.get("surveys", surveys))
	changed.emit()


func set_value(key: String, value) -> void:
	set(key, value)
	changed.emit()
	Save.request_save()


## The step after `current` in `steps` (round to the first; a value between steps goes to the next one up).
func next_step(steps: Array, current: int) -> int:
	for s in steps:
		if int(s) > current:
			return int(s)
	return int(steps[0])


## The dummies' health in words: UNDYING for 0, else "500 HP" ("10,000 HP": pass 49, the Boss dummy goes to 200,000).
func dummy_hp_label(hp: int) -> String:
	return "UNDYING" if hp <= 0 else "%s HP" % thousands(hp)


## A whole number with its thousands marked: 2000 -> "2,000".
func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The behaviour after `current` in DUMMY_MODES, round to the first (the developer menu's tap, pass 49).
func next_mode(current: String) -> String:
	var k := DUMMY_MODES.find(current)
	return str(DUMMY_MODES[(k + 1) % DUMMY_MODES.size()])


## How big the floating text is drawn: 0.75, 1 or 1.3 (float_size).
func float_scale() -> float:
	return float(FLOAT_SCALES[clampi(float_size, 0, 2)])


func camera_name() -> String:
	return ["Fixed · north up", "Follow · behind the hero"][clampi(camera_mode, 0, 1)]
