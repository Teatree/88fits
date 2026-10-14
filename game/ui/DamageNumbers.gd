## Floating numbers (pass 46, Garry: "Add floating damage indicators to when Player hits an enemy with anything"; pass
## 47: "like in the MMORPGs where damage text appears on the enemy when you hit them (like in Vampire Survivors and
## MegaBonk). Healing should be visible on the Player as well, regen and life steal too. As well as all the others.
## Damage received on hero too.").
## Every hit on a creature goes through EnemyManager.damage, which hands it here (DamageNumbers.I.add, when I is set); a
## hit on a creature within MERGE of the birth of a number of the same kind on it adds to that number, so a shotgun's
## pellets or a beam's ticks read as one. The hero's own numbers come from Player: what a hit took off his health (red),
## what his shield soaked (blue), what came back (green: pickups, lifesteal, the level patch; regen and Siesta batched
## every half second), DODGE and BLOCK. They start at his shoulders and follow him: what hit him (or missed) on his left,
## healing on his right, clear of the HUD's "+N XP" and coin popups that rise from over his head.
## A number pops in big (POP_FROM, a crit POP_FROM_CRIT, back to 1 over POP with a little overshoot), climbs easing out
## while it drifts a little sideways (neighbours lean apart, so a crowd's numbers spread instead of stacking), holds, then
## fades and shrinks over the last part of LIFE: Bitter at weight 800 (pass 54, Garry: a western face but lighter than the
## Alfa Slab One it was, with a thinner outline; the sizes a tenth up, since Bitter is the lighter face) with an ink
## outline and a hard ink shadow, white for a
## hit, orange for a fire tick, purple for a poison tick (pass 48; green before); whole numbers, never under 1. Crits
## read like World of Warcraft's (pass 48): yellow and big (PX_CRIT), popping from POP_FROM_CRIT with an overshoot and a
## quick hop (up HOP_CRIT px and back a third of it in the first HOP_T seconds) before the normal rise; a mini crit (the
## Tommy Gun's Mini Crits, EnemyManager.HIT_MINI) the same in a paler yellow, smaller, a smaller pop and hop. At most
## CAP live: a new one pushes out the oldest. A creature's number keeps to the world point it was hit at, projected
## through the game's camera every frame, so it holds its place while the camera moves; a hit off the screen gets none.
## Frozen while the run is paused, hidden while a Wanted modal is up (as the HUD), none at all with
## Settings.damage_numbers off or `suppressed` (a tool's switch that never reaches the save). A headless run keeps the
## list (the tests read it) and draws nothing. Game puts one on the UI layer, under the HUD.
class_name DamageNumbers
extends Control

const LIFE := 0.9
const MERGE := 0.12
const CAP := 60
## Fire and poison ticks hold at most this many of the CAP (pass 47): a burning crowd's ticks never crowd out the hits
## (a new tick past it is let go).
const TICK_CAP := 30
## A heal on the hero joins the last one born this long ago (lifesteal comes back a point at a time).
const HEAL_MERGE := 0.35
## DODGE and BLOCK say it once in this window, however many hits it was.
const WORD_MERGE := 0.3
## How far a number climbs over its life, in px (the hero's a little further).
const RISE := 84.0
const HERO_RISE := 96.0
## The pop: POP_FROM (a crit POP_FROM_CRIT) times the size back to 1 over POP seconds, overshooting a touch below 1.
const POP := 0.2
const POP_FROM := 1.6
## A crit's pop (pass 48: WoW's): from POP_FROM_CRIT (a mini crit's POP_FROM_MINI) over POP_CRIT, overshooting.
const POP_FROM_CRIT := 2.6
const POP_FROM_MINI := 2.0
const POP_CRIT := 0.25
## A crit's hop: up HOP_CRIT px (a mini crit's HOP_MINI) and back HOP_BACK of it within HOP_T seconds, the normal rise
## after it.
const HOP_T := 0.25
const HOP_CRIT := 60.0
const HOP_MINI := 30.0
const HOP_BACK := 1.0 / 3.0
## A merge bumps the number up by this share for a moment, so the new total is seen.
const BUMP := 0.18
## The spread: a creature's number starts up to SPREAD px to one side (the next one the other side) and drifts up to
## SPREAD_DRIFT px further that way.
const SPREAD := 30.0
const SPREAD_DRIFT := 34.0
## Fully opaque for this share of LIFE, then fading out and shrinking to FADE_SCALE by the end (short, so a fading
## number goes rather than lingering as a grey ghost on the sand).
const HOLD := 0.68
const FADE_SCALE := 0.7
const WHITE := Color("fff8ec")
## A crit's yellow and a mini crit's paler one (pass 48: WoW's; the crit was gold, ffc93c).
const CRIT := Color("ffe23a")
const CRIT_MINI := Color("fff0a0")
const HOT := Color("ff8a2b")
## A poison tick (pass 48: purple, Garry; it was green, 8fe46a).
const POISON := Color("c07bff")
## The hero's colours: damage taken, his shield soaking it, health back, a dodge or a block.
const RED := Color("ff4b3e")
const BLUE := Color("74c6ff")
const HEAL := Color("6cf27a")
const PALE := Color("e8f2ff")
## Type sizes in canvas px: a hit, a crit (bigger), a fire or poison tick (smaller); the hero's hurt, heal and words.
## Pass 54: a tenth up on pass 47's (48, 72, 58, 40, 54, 48, 40) for the lighter face.
const PX := 52
const PX_CRIT := 78
const PX_MINI := 64
const PX_TICK := 44
const PX_HURT := 58
const PX_HEAL := 52
const PX_WORD := 44
## The face's weight (Bitter is variable to 900).
const WEIGHT := 800
## The ink outline as a share of the type size, and the hard shadow under it (it has to hold against the sand and the
## crowd at phone size). Pass 54: thinner (0.5 and (3, 5) round the slab).
const OUTLINE_FRAC := 0.28
const SHADOW := Vector2(2.0, 3.0)
const SHADOW_ALPHA := 0.7
## A number's kind: only the same kind on the same creature merges (a crit joins a plain hit and turns it gold). The
## hero's kinds (pass 47) merge on the hero.
const KIND_HIT := 0
const KIND_HOT := 1
const KIND_GREEN := 2
const KIND_HURT := 3
const KIND_SHIELD := 4
const KIND_HEAL := 5
const KIND_DODGE := 6
const KIND_BLOCK := 7
## `who` on the hero's numbers.
const HERO := -2
## Where over the hero's feet his numbers start, in metres (his shoulders: his sprite stands 1.9 m), how far to the side,
## in px, and how much further out and higher DODGE and BLOCK start, so a word never sits on a number born with it.
const HERO_UP := 1.35
const HERO_SIDE := 84.0
const HERO_WORD_OUT := 24.0
const HERO_WORD_UP := 44.0

static var I: DamageNumbers = null


## One number in the air.
class Num:
	var who := -1
	var kind := 0
	var at := Vector3.ZERO
	var amount := 0.0
	var age := 0.0
	var crit := false
	## a mini crit (pass 48, EnemyManager.HIT_MINI): a paler, smaller crit (a full crit joining it makes it a crit)
	var mini := false
	## px from where it is anchored, so a crowd's numbers do not sit on one another, and the sideways drift over its life
	var nudge := Vector2.ZERO
	var drift := 0.0
	## a crit leans a little; a merge bumps it (1, decaying)
	var tilt := 0.0
	var bump := 0.0
	## the shown text and its width at the type size, made again after a merge
	var text := ""
	var width := 0.0


var game: Node = null
## A tool's off switch (perf_late's numbers=0): no numbers, and Settings (and so the save) never touched.
var suppressed := false
var _live: Array = []   # Num, oldest first
var _settings: Node = null
var _font: Font
var _headless := false
var _dirty := false
var _side := 1.0        # which way the next creature number leans (it alternates)
var _ticks := 0         # fire and poison numbers in the air (TICK_CAP)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _enter_tree() -> void:
	I = self


func _exit_tree() -> void:
	if I == self:
		I = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings = get_node_or_null("/root/Settings")
	_headless = DisplayServer.get_name() == "headless"
	_font = W.serif(WEIGHT)


## Whether numbers show: Settings.damage_numbers (on unless the player switched it off), and not suppressed by a tool.
func enabled() -> bool:
	if suppressed:
		return false
	if _settings == null and is_inside_tree():
		_settings = get_node_or_null("/root/Settings")
	return _settings == null or bool(_settings.get("damage_numbers"))


## A number for creature `i` hit for `amount`, starting at the world point `at` (over the creature); `crit` a critical
## hit, `green` a poison tick (purple since pass 48; the name is the old one), `hot` a fire tick, `mini` a mini crit.
func add(i: int, at: Vector3, amount: float, crit: bool = false, green: bool = false, hot: bool = false, mini: bool = false) -> void:
	if amount <= 0.0 or not enabled():
		return
	var is_mini := mini and not crit
	var kind := KIND_HOT if hot else (KIND_GREEN if green else KIND_HIT)
	if i >= 0 and _merge(i, kind, amount, MERGE, crit, is_mini):
		return
	if kind != KIND_HIT and _ticks >= TICK_CAP:
		return
	var cam := _camera()
	if cam and not _on_screen(cam, at):
		return
	var n := Num.new()
	n.who = i
	n.kind = kind
	n.at = at
	n.amount = amount
	n.crit = crit and kind == KIND_HIT
	n.mini = is_mini and kind == KIND_HIT
	n.tilt = randf_range(-0.14, 0.14) if n.crit else (randf_range(-0.08, 0.08) if n.mini else 0.0)
	# neighbours lean apart: this one to one side, the next to the other, each drifting further out as it climbs
	n.nudge = Vector2(_side * randf_range(SPREAD * 0.2, SPREAD), randf_range(-12.0, 8.0))
	n.drift = _side * randf_range(SPREAD_DRIFT * 0.3, SPREAD_DRIFT)
	_side = -_side
	_push(n)


## The hero lost `amount` health to a hit (after his damage reduction): a red "−N" (pass 47).
func hero_hurt(amount: float) -> void:
	_hero(KIND_HURT, amount, MERGE)


## His shield took `amount` of a hit (the Energy Shield line): a blue "−N".
func hero_shield(amount: float) -> void:
	_hero(KIND_SHIELD, amount, MERGE)


## He got `amount` health back: a green "+N" (pickups, lifesteal and the level patch at once; Player batches regen and
## Siesta every half second). Heals within HEAL_MERGE of each other read as one.
func hero_heal(amount: float) -> void:
	_hero(KIND_HEAL, amount, HEAL_MERGE)


## A hit he evaded: DODGE.
func hero_dodge() -> void:
	_hero(KIND_DODGE, 0.0, WORD_MERGE)


## A hit the Shield power-up stopped: BLOCK.
func hero_block() -> void:
	_hero(KIND_BLOCK, 0.0, WORD_MERGE)


## One of the hero's numbers: merged into the last of its kind born within `window`, else a new one at his shoulder,
## what hit him (or missed) on the left, healing on the right.
func _hero(kind: int, amount: float, window: float) -> void:
	# heals have their own switch (pass 47b); the hits and words go with the damage numbers
	if kind == KIND_HEAL:
		if suppressed or (_settings != null and not bool(_settings.get("float_heal"))):
			return
	elif not enabled():
		return
	var word := kind == KIND_DODGE or kind == KIND_BLOCK
	if not word and amount <= 0.0:
		return
	if _merge(HERO, kind, amount, window, false, false):
		return
	var n := Num.new()
	n.who = HERO
	n.kind = kind
	n.at = _hero_world()
	n.amount = amount
	var side := 1.0 if kind == KIND_HEAL else -1.0
	var out := HERO_SIDE + (HERO_WORD_OUT if word else 0.0)
	n.nudge = Vector2(side * (out + randf_range(-10.0, 10.0)), randf_range(-8.0, 6.0) - (HERO_WORD_UP if word else 0.0))
	n.drift = side * randf_range(8.0, 22.0)
	_push(n)


## Adds `amount` to the newest number of `kind` on `who` born within `window`; false when there is none. A crit joining
## a number makes it a crit; a mini crit joining a plain one makes it a mini crit.
func _merge(who: int, kind: int, amount: float, window: float, crit: bool, mini: bool = false) -> bool:
	# newest first: past the window every older number is older still
	for k in range(_live.size() - 1, -1, -1):
		var m: Num = _live[k]
		if m.age >= window:
			return false
		if m.who == who and m.kind == kind:
			m.amount += amount
			if crit and kind == KIND_HIT:
				m.crit = true
				m.mini = false
			elif mini and kind == KIND_HIT and not m.crit:
				m.mini = true
			m.text = ""
			m.bump = 1.0
			_dirty = true
			return true
	return false


func _push(n: Num) -> void:
	_live.append(n)
	if _is_tick(n):
		_ticks += 1
	if _live.size() > CAP:
		_drop_oldest()
	_dirty = true


func _drop_oldest() -> void:
	var gone: Num = _live.pop_front()
	if _is_tick(gone):
		_ticks -= 1


static func _is_tick(n: Num) -> bool:
	return n.kind == KIND_HOT or n.kind == KIND_GREEN


## The numbers in the air, oldest first (tests and tools read them).
func live() -> Array:
	return _live


func count() -> int:
	return _live.size()


func clear() -> void:
	_live.clear()
	_ticks = 0
	_dirty = true


## A number's colour: orange for fire, purple for poison, yellow for a crit (a paler yellow for a mini crit), else white;
## on the hero red for damage, blue for his shield, green for health back, pale for the words.
static func colour_of(n: Num) -> Color:
	match n.kind:
		KIND_HOT:
			return HOT
		KIND_GREEN:
			return POISON
		KIND_HURT:
			return RED
		KIND_SHIELD:
			return BLUE
		KIND_HEAL:
			return HEAL
		KIND_DODGE, KIND_BLOCK:
			return PALE
	if n.crit:
		return CRIT
	return CRIT_MINI if n.mini else WHITE


## A number's type size: a crit bigger (a mini crit between), a tick smaller; the hero's own sizes.
static func size_of(n: Num) -> int:
	match n.kind:
		KIND_HIT:
			return PX_CRIT if n.crit else (PX_MINI if n.mini else PX)
		KIND_HURT, KIND_SHIELD:
			return PX_HURT
		KIND_HEAL:
			return PX_HEAL
		KIND_DODGE, KIND_BLOCK:
			return PX_WORD
	return PX_TICK


## The text a number shows: whole, never under 1.
static func text_of(amount: float) -> String:
	return W.num(maxi(int(round(amount)), 1))


## What a number reads: the creatures' bare numbers, the hero's with a sign (− for damage and shield, + for health),
## and the words.
static func label_of(n: Num) -> String:
	match n.kind:
		KIND_HURT, KIND_SHIELD:
			return "−" + text_of(n.amount)
		KIND_HEAL:
			return "+" + text_of(n.amount)
		KIND_DODGE:
			return "DODGE"
		KIND_BLOCK:
			return "BLOCK"
	return text_of(n.amount)


## The pop: from POP_FROM times the size to 1 over POP seconds on an ease-out-back, so it dips a touch under 1 and
## settles: a punch, not a slide. A crit pops from POP_FROM_CRIT (a mini crit POP_FROM_MINI) over POP_CRIT, the
## overshoot deeper.
static func pop_scale(age: float, crit: bool, mini: bool = false) -> float:
	var big := crit or mini
	var k := clampf(age / (POP_CRIT if big else POP), 0.0, 1.0)
	var c1 := 2.2 if big else 1.70158
	var e: float = 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
	return lerpf(POP_FROM_CRIT if crit else (POP_FROM_MINI if mini else POP_FROM), 1.0, e)


## A crit's hop at `age`: up to `height` px fast (ease out over the first 45 % of HOP_T), back down HOP_BACK of it by
## HOP_T (smoothstep), held there after; 0 for no height.
static func hop_at(age: float, height: float) -> float:
	if height <= 0.0 or age <= 0.0:
		return 0.0
	var up_t := HOP_T * 0.45
	if age <= up_t:
		var k := age / up_t
		return height * (1.0 - (1.0 - k) * (1.0 - k))
	var settle := height * (1.0 - HOP_BACK)
	if age < HOP_T:
		var k2 := (age - up_t) / (HOP_T - up_t)
		return lerpf(height, settle, k2 * k2 * (3.0 - 2.0 * k2))
	return settle


## How high a number hops: a crit HOP_CRIT, a mini crit HOP_MINI, anything else none.
static func hop_of(n: Num) -> float:
	if n.kind != KIND_HIT:
		return 0.0
	return HOP_CRIT if n.crit else (HOP_MINI if n.mini else 0.0)


## How much of a number shows at `age`: whole until HOLD of its life, then fading to nothing at LIFE.
static func alpha_at(age: float) -> float:
	var f := age / LIFE
	if f <= HOLD:
		return 1.0
	return clampf(1.0 - (f - HOLD) / (1.0 - HOLD), 0.0, 1.0)


## Ages every number by `delta` seconds and lets the spent ones go (the tests call it in place of frames).
func step(delta: float) -> void:
	for n: Num in _live:
		n.age += delta
		if n.bump > 0.0:
			n.bump = maxf(n.bump - delta * 6.0, 0.0)
	# born in order, one life for all, ageing together: the spent ones are at the front
	while not _live.is_empty() and (_live[0] as Num).age >= LIFE:
		_drop_oldest()
		_dirty = true


func _process(delta: float) -> void:
	# pass 77 (lane SIMRUN): the run sim's fast mode shows no numbers (its tool suppresses them as they come, too)
	if Run.sim_mode:
		return
	# a modal that pauses the run (level-up, chest, pause...) hides the numbers, as it does the HUD
	var covered := false
	for m in get_tree().get_nodes_in_group("wanted_modal"):
		if (m as CanvasItem).visible:
			covered = true
			break
	if visible == covered:
		visible = not covered
	if not enabled():
		if not _live.is_empty():
			clear()
	elif not _frozen():
		step(delta)
	if _headless:
		_dirty = false
	elif _dirty or not _live.is_empty():
		_dirty = false
		queue_redraw()


## The run is paused (the tree, or the game's own pause): the numbers hold still.
func _frozen() -> bool:
	if get_tree().paused:
		return true
	return game != null and is_instance_valid(game) and bool(game.get("paused"))


## The game's camera (its rig's Camera3D), else the viewport's.
func _camera() -> Camera3D:
	if not is_inside_tree():
		return null
	if game != null and is_instance_valid(game):
		var rig = game.get("camera")
		if rig is Node and is_instance_valid(rig):
			var c = rig.get("camera")
			if c is Camera3D:
				return c
	return get_viewport().get_camera_3d()


func _on_screen(cam: Camera3D, at: Vector3) -> bool:
	if cam.is_position_behind(at):
		return false
	return get_viewport_rect().grow(80.0).has_point(cam.unproject_position(at))


## Where the hero's numbers start in the world, HERO_UP over his feet (kept at birth, and drawn from when there is no
## camera rig).
func _hero_world() -> Vector3:
	var p = game.get("player") if game != null and is_instance_valid(game) else null
	if p is Node3D and is_instance_valid(p):
		return (p as Node3D).global_position + Vector3(0.0, HERO_UP, 0.0)
	return Vector3.ZERO


## Where the hero's numbers start on the screen this frame: HERO_UP over his feet, from the camera rig's shake-free anchor
## (his feet and the pixels a metre spans there, the spot the HUD draws his bars from), else that point through `cam`;
## Vector2.INF with no hero.
func _hero_anchor(cam: Camera3D) -> Vector2:
	if game == null or not is_instance_valid(game):
		return Vector2.INF
	var p = game.get("player")
	if not (p is Node3D) or not is_instance_valid(p):
		return Vector2.INF
	var rig = game.get("camera")
	if rig is Node and is_instance_valid(rig) and rig.has_method("hero_anchor"):
		var a: Dictionary = rig.hero_anchor()
		return (a["pos"] as Vector2) - Vector2(0.0, HERO_UP * float(a["ppm"]))
	var at: Vector3 = (p as Node3D).global_position + Vector3(0.0, HERO_UP, 0.0)
	return Vector2.INF if cam.is_position_behind(at) else cam.unproject_position(at)


func _draw() -> void:
	if _live.is_empty():
		return
	var cam := _camera()
	if cam == null or _font == null:
		return
	# where each number stands this frame (px, scale, alpha), worked out once for both passes
	var crowd: Array = []
	var hero: Array = []
	var head := Vector2.INF
	var head_done := false
	for n: Num in _live:
		var anchor: Vector2
		if n.who == HERO:
			if not head_done:
				head = _hero_anchor(cam)
				head_done = true
			anchor = head
		if n.who != HERO or not anchor.is_finite():
			if cam.is_position_behind(n.at):
				continue
			anchor = cam.unproject_position(n.at)
		if n.text == "":
			n.text = label_of(n)
			n.width = _font.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_of(n)).x
		var f := clampf(n.age / LIFE, 0.0, 1.0)
		var rise := HERO_RISE if n.who == HERO else RISE
		var up := rise * (1.0 - pow(1.0 - f, 2.6))
		var hop := hop_of(n)
		if hop > 0.0:
			# a crit hops first, then rises as the rest do over what is left of its life
			var f2 := clampf((n.age - HOP_T) / (LIFE - HOP_T), 0.0, 1.0)
			up = hop_at(n.age, hop) + rise * (1.0 - pow(1.0 - f2, 2.6))
		var side := n.drift * (1.0 - pow(1.0 - f, 2.0))
		var s := pop_scale(n.age, n.crit, n.mini) * (1.0 + BUMP * n.bump)
		if f > HOLD:
			s *= lerpf(1.0, FADE_SCALE, (f - HOLD) / (1.0 - HOLD))
		var item := [n, anchor + n.nudge + Vector2(side, -up), s, alpha_at(n.age)]
		if n.who == HERO:
			hero.append(item)
		else:
			crowd.append(item)
	# the crowd's numbers first, the hero's on top of them; each set in two passes (every shadow and ink outline, then
	# every face), the numbers of one type size together: glyphs of one size and pass share a texture, so the canvas
	# draws each pass in a batch or two instead of switching textures three times a number (drawn number by number,
	# the late-game crowd cost 130 more draw calls; pass 47)
	_draw_set(crowd)
	_draw_set(hero)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_set(items: Array) -> void:
	if items.is_empty():
		return
	items.sort_custom(func(x, y): return size_of(x[0]) < size_of(y[0]))
	# the player's size setting (pass 47b: small, normal, large)
	var k := 1.0
	if _settings != null and _settings.has_method("float_scale"):
		k = float(_settings.float_scale())
	for it in items:
		var n: Num = it[0]
		var px := size_of(n)
		var a: float = it[3]
		var s: float = it[2] * k
		draw_set_transform(it[1], n.tilt, Vector2(s, s))
		var base := Vector2(-n.width * 0.5, px * 0.36)
		var ol := int(round(px * OUTLINE_FRAC))
		draw_string_outline(_font, base + SHADOW, n.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, ol, Color(W.INK, a * SHADOW_ALPHA))
		draw_string_outline(_font, base, n.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, ol, Color(W.INK, a))
	for it in items:
		var n: Num = it[0]
		var px := size_of(n)
		var s: float = it[2] * k
		draw_set_transform(it[1], n.tilt, Vector2(s, s))
		draw_string(_font, Vector2(-n.width * 0.5, px * 0.36), n.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, Color(colour_of(n), float(it[3])))
