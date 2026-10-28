## The run's bounty contract (pass 111, lane WANTED): the poster picked on the Bounty Board (WantedBoard.next), followed
## through the run. Game attaches it once the run has started (attach: never in the debug arena; a tool's launch may name
## a contract with `bounty`, or "roll" for the board's first poster); it counts what the run's own tallies do not
## (specials, Elites, the gold gained, the boss fight's seconds, the lowest health), says DONE or FAILED the moment it
## knows, shows a small plate under the HUD's strip on the right (the target's icon and the progress), a row at the top of
## the pause screen's Build tab, and at the run's end (settle, from Game.end_run) pays the reward into the save (in the
## config's currency, gold by default: Currency.add), only when
## done, whatever the end (a death too, as the purse is), and leaves its record in Run.last_result["bounty"] for the
## Results' BOUNTY row and the run record (RunAnalytics). Rules: BALANCING.md 54.WANTED.
class_name WantedRun
extends Node

## The tracker of the run going on (null: none, or no contract).
static var current: WantedRun = null
## How often the contract is checked, seconds of the run's clock.
const CHECK_EVERY := 0.2
## The HUD plate: its picture, its gap under the strip (or under the boss's bar while a boss lives) and the right margin.
const PLATE_ICON := 52.0
const PLATE_GAP := 12.0
const PLATE_RIGHT := 36.0

var game: Node
var contract: Dictionary = {}
var done := false
var failed := false
var paid := 0
var _specials := 0
var _elites := 0
var _gold := 0
var _min_hp := 1.0
var _boss_t0 := 0.0
## The contract's boss has come (boss_fast: his fight's clock runs from _boss_t0).
var _boss_on := false
var _boss_secs := -1.0
var _tick := 0.0
var _plate: PanelContainer
var _plate_text: WText
var _plate_label: WText
var _family: Array = []


## Starts following the board's pick for this run (Game._ready, after the HUD): the contract WantedBoard.next holds, or
## the launch's `bounty` (a contract, or "roll": the first poster the board would roll). Null with none.
static func attach(g: Node, launch: Dictionary = {}) -> WantedRun:
	var c := WantedBoard.take_next()
	var lb = launch.get("bounty")
	if lb is Dictionary and not (lb as Dictionary).is_empty():
		c = (lb as Dictionary).duplicate(true)
	elif str(lb) == "roll" and Run.map and Run.character:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var posters := WantedBoard.roll(WantedBoard.config(), WantedBoard.context(Run.map.id, Run.stage, Run.character.id), rng)
		c = posters[0] if not posters.is_empty() else {}
	if c.is_empty():
		current = null
		return null
	var w := WantedRun.new()
	w.name = "WantedRun"
	w.game = g
	w.contract = c
	g.add_child(w)
	return w


func _ready() -> void:
	current = self
	_family = _family_ids(str(contract.get("target", "")))
	var em = game.get("enemies")
	if em:
		em.enemy_died.connect(_on_died)
		em.boss_died.connect(_on_boss_died)
	var dr = game.get("director")
	if dr:
		dr.boss_started.connect(_on_boss_started)
	Run.gold_gained.connect(_on_gold)
	if game.get("hud") and not Run.sim_mode:
		_build_plate()
	if RunAnalytics.I:
		RunAnalytics.I.event("bounty_taken", str(contract.get("type", "")), int(contract.get("n", 0)),
			{"target": str(contract.get("target", "")), "reward": int(contract.get("reward", 0)), "d": float(contract.get("d", 0.0))})


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(delta: float) -> void:
	var pl = game.get("player")
	if pl and is_instance_valid(pl):
		var frac: float = 0.0 if bool(pl.get("dead")) else float(pl.get("hp")) / maxf(float(pl.get("max_hp")), 1.0)
		_min_hp = minf(_min_hp, frac)
	_tick -= delta
	if _tick <= 0.0:
		_tick = CHECK_EVERY
		check()
	_place_plate()


# ---------------------------------------------------------------- what the run counts

func _on_died(def: EnemyDef, _pos: Vector3, elite: EliteModDef, _weapon_id: String) -> void:
	if def == null or def.brain == "dummy":
		return
	var em = game.get("enemies")
	if (em and bool(em.get("died_special"))) or def.badge_for() == "gear":
		_specials += 1
	if (elite != null or def.archetype == "elite") and def.archetype != "boss":
		_elites += 1


func _on_gold(n: int) -> void:
	_gold += maxi(n, 0)


func _on_boss_started(def: EnemyDef) -> void:
	if str(contract.get("type", "")) == "boss_fast" and def and def.id == str(contract.get("target", "")) and not _boss_on:
		_boss_on = true
		_boss_t0 = Run.run_time()


func _on_boss_died(def: EnemyDef, _pos: Vector3) -> void:
	if str(contract.get("type", "")) != "boss_fast" or def == null or def.id != str(contract.get("target", "")):
		return
	if not _boss_on or done or failed or _boss_secs >= 0.0:
		return
	_boss_secs = Run.run_time() - _boss_t0
	if _boss_secs <= float(contract.get("n", 0)):
		_finish(true)
	else:
		_finish(false)


## The weapon ids a family's kills count under: the weapon and its evolutions (Registry.item_family).
static func _family_ids(id: String) -> Array:
	var out: Array = [id] if id != "" else []
	for d in Registry.item_family(id):
		if d is WeaponDef and not out.has((d as WeaponDef).id):
			out.append((d as WeaponDef).id)
	return out


## How far the contract has come: (so far, needed). A one-off goal (beat the stage, evolve it, the boss in time, the
## health floor) is (0, 1) until it is done.
func progress() -> Vector2i:
	var n := int(contract.get("n", 0))
	var target := str(contract.get("target", ""))
	match str(contract.get("type", "")):
		"kill_enemy":
			return Vector2i(int(Run.kills_by_enemy.get(target, 0)), n)
		"kill_weapon":
			var k := 0
			for id in _family:
				k += int(Run.kills_by_weapon.get(str(id), 0))
			return Vector2i(k, n)
		"kill_specials":
			return Vector2i(_specials, n)
		"kill_elites":
			return Vector2i(_elites, n)
		"kill_total":
			return Vector2i(Run.kills, n)
		"hero_level":
			return Vector2i(Run.max_level_reached, n)
		"open_chests":
			return Vector2i(Run.chests_opened, n)
		"collect_coins":
			return Vector2i(_gold, n)
		"max_weapon":
			var best := 0
			for e: Dictionary in QuestTracker.held_items("weapon", target):
				best = maxi(best, n if bool(e["maxed"]) else int(e["level"]))
			return Vector2i(mini(best, n), n)
		"evolve_item":
			for e: Dictionary in QuestTracker.held_items("any", target):
				if bool(e["evolved"]):
					return Vector2i(1, 1)
			return Vector2i(0, 1)
		"beat_stage", "hp_floor":
			return Vector2i(1 if Run.stage_beaten and not failed else 0, 1)
		"boss_fast":
			return Vector2i(1 if done else 0, 1)
	return Vector2i(0, 1)


## Looks at the contract now (every CHECK_EVERY seconds and at the end): DONE once it is met, FAILED once it can no longer
## be (the health under the floor before the stage is beaten; the boss alive past its seconds).
func check() -> void:
	if done or failed:
		_refresh_plate()
		return
	var type := str(contract.get("type", ""))
	match type:
		"hp_floor":
			var floor_frac := float(contract.get("n", 0)) / 100.0
			if _min_hp < floor_frac - 0.0001:
				_finish(false)
			elif Run.stage_beaten:
				_finish(true)
		"boss_fast":
			if _boss_on and _boss_secs < 0.0 and Run.run_time() - _boss_t0 > float(contract.get("n", 0)):
				_finish(false)
		"beat_stage":
			if Run.stage_beaten:
				_finish(true)
		_:
			var p := progress()
			if p.y > 0 and p.x >= p.y:
				_finish(true)
	_refresh_plate()


func _finish(ok: bool) -> void:
	if done or failed:
		return
	done = ok
	failed = not ok
	var hud = game.get("hud")
	if RunAnalytics.I:
		RunAnalytics.I.event("bounty_done" if ok else "bounty_failed", str(contract.get("type", "")), int(contract.get("n", 0)),
			{"target": str(contract.get("target", "")), "reward": int(contract.get("reward", 0))})
	if hud and not Run.sim_mode:
		if ok:
			hud.banner("BOUNTY DONE", W.SAGE, WPoster.thumb_texture(contract.get("still", {})))
			hud.toast("BOUNTY +%s GOLD" % W.num(int(contract.get("reward", 0))), W.TOAST_GREEN)
			Audio.play("ui_fanfare")
		else:
			hud.toast("BOUNTY FAILED", W.ROCK)
			Audio.play("ui_buzzer")
	_refresh_plate()


# ---------------------------------------------------------------- the end of the run

## The run's end (Game.end_run, after the purse is banked): a last look, the reward into the save when done (the source
## WantedBoard.GOLD_SOURCE), the record into Run.last_result["bounty"]. {} with no contract.
static func settle() -> Dictionary:
	if current == null or not is_instance_valid(current):
		return {}
	return current._settle()


func _settle() -> Dictionary:
	check()
	if done and paid == 0:
		paid = maxi(int(contract.get("reward", 0)), 0)
		if paid > 0:
			# in the posters' currency (the config's reward.currency, gold by default: Save.add_gold through Currency)
			Currency.add(WantedBoard.currency(), paid, WantedBoard.GOLD_SOURCE, {"type": str(contract.get("type", "")),
				"target": str(contract.get("target", "")), "d": float(contract.get("d", 0.0))})
			var st := WantedBoard.store()
			st["done"] = int(st.get("done", 0)) + 1
			st["paid"] = int(st.get("paid", 0)) + paid
	var rec := record()
	Run.last_result["bounty"] = rec
	return rec


## The contract as the run record keeps it (RunAnalytics `bounty`, the Results' row): type, target, n, d, reward, the
## progression and stage it was rolled at, how far it came, done / failed / paid, its name and task line, its still.
func record() -> Dictionary:
	var p := progress()
	return {"type": str(contract.get("type", "")), "target": str(contract.get("target", "")), "n": int(contract.get("n", 0)),
		"d": float(contract.get("d", 0.0)), "reward": int(contract.get("reward", 0)), "P": int(contract.get("P", 0)),
		"stage": int(contract.get("stage", 0)) + 1, "have": p.x, "need": p.y, "done": done, "failed": failed, "paid": paid,
		"name": str(contract.get("name", "")), "text": str(contract.get("text", "")), "still": contract.get("still", {})}


## The record of the run going on ({} with no contract): RunAnalytics reads it for the run's file.
static func record_now() -> Dictionary:
	if current == null or not is_instance_valid(current):
		return {}
	return current.record()


## The words for how far a contract has come: "34 / 60", "0:32 left", "DONE", "FAILED".
func progress_text() -> String:
	if done:
		return "DONE"
	if failed:
		return "FAILED"
	var type := str(contract.get("type", ""))
	if type == "boss_fast":
		if _boss_on:
			return "%s left" % WantedBoard.clock_of(maxf(float(contract.get("n", 0)) - (Run.run_time() - _boss_t0), 0.0))
		return "%s fight" % WantedBoard.clock_of(float(contract.get("n", 0)))
	if type == "hp_floor":
		return "low %d%%" % int(round(_min_hp * 100.0))
	if type == "beat_stage" or type == "evolve_item":
		return "not yet"
	var p := progress()
	return "%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)]


# ---------------------------------------------------------------- the HUD's plate

func _build_plate() -> void:
	var hud: Control = game.get("hud")
	_plate = PanelContainer.new()
	_plate.name = "BountyPlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 5).pad(10, 6, 16, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(row)
	var pic := TextureRect.new()
	pic.name = "Icon"
	pic.texture = WPoster.thumb_texture(contract.get("still", {}))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(PLATE_ICON, PLATE_ICON)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_plate_label = W.label("Bounty", 16, W.INK_SOFT, 0.2)
	col.add_child(_plate_label)
	_plate_text = W.text("", W.slab(), 28, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 30.0)
	_plate_text.name = "Progress"
	col.add_child(_plate_text)
	hud.add_child(_plate)
	# under the HUD's own pieces (a toast or a banner passing over it stays on top)
	hud.move_child(_plate, 0)
	_refresh_plate()
	_place_plate()


func _refresh_plate() -> void:
	if _plate == null:
		return
	var t := progress_text()
	if _plate_text.text != t:
		_plate_text.text = t
		_plate.reset_size()
	_plate_text.color = W.SAGE if done else (W.ROCK if failed else W.INK)
	_plate.modulate.a = 0.6 if failed else 1.0


## On the right under the strip (HUD.band_h), or under the boss's bar while a boss lives.
func _place_plate() -> void:
	if _plate == null:
		return
	var hud = game.get("hud")
	var vp: Vector2 = _plate.get_viewport_rect().size
	var y := HUD.band_h + PLATE_GAP
	if hud and hud.has_method("boss_plate_bottom"):
		var bb: float = hud.boss_plate_bottom()
		if bb > 0.0:
			y = bb + PLATE_GAP
	var sz := _plate.get_combined_minimum_size()
	_plate.size = sz
	_plate.position = Vector2(vp.x - PLATE_RIGHT - sz.x, y)


## The plate (tests, captures): null without one.
func plate() -> Control:
	return _plate


# ---------------------------------------------------------------- the pause screen and the Results

## The pause screen's row (its Build tab, at the top): the target's picture, the name and the task, the progress. Null
## with no contract.
static func pause_row() -> Control:
	if current == null or not is_instance_valid(current):
		return null
	return row_for(current.record(), current.progress_text())


## A row for a contract record: its picture on an aged plate, the name in slab and the task under it, and on the right
## `right` (the progress, or what it paid).
static func row_for(rec: Dictionary, right: String, right_color: Color = W.INK) -> Control:
	var h := HBoxContainer.new()
	h.name = "BountyRow"
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", W.box(W.AGED, 4, 0, 10).pad(6, 6, 6, 6))
	var pic := TextureRect.new()
	pic.texture = WPoster.thumb_texture(rec.get("still", {}) if rec.get("still") is Dictionary else {})
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(76, 76)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pic)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(W.slab_text(str(rec.get("name", "")).to_upper(), 28, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 32.0))
	col.add_child(W.serif_text(str(rec.get("text", "")), 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	h.add_child(col)
	var r := W.slab_text(right, 30, right_color, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	r.name = "Right"
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(r)
	return h


## The Results' BOUNTY panel for the run's record (Run.last_result["bounty"]): the row, and on its right what it paid
## ("+240", brass) or how far it came ("34 / 60", "FAILED"). Null without a contract.
static func results_panel(rec: Dictionary) -> Control:
	if rec.is_empty():
		return null
	var p := PanelContainer.new()
	p.name = "BountyPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(34, 22, 34, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(W.label("Bounty", 22, W.INK_SOFT))
	var paid_n := int(rec.get("paid", 0))
	var right := ""
	var col := W.INK
	if paid_n > 0:
		right = "+%s" % W.num(paid_n)
		col = W.BRASS_DARK
	elif bool(rec.get("failed", false)):
		right = "FAILED"
		col = W.ROCK
	else:
		right = "%s / %s" % [W.num(mini(int(rec.get("have", 0)), int(rec.get("need", 0)))), W.num(int(rec.get("need", 0)))] \
			if int(rec.get("need", 0)) > 1 else "NOT DONE"
		col = W.INK_SOFT
	v.add_child(row_for(rec, right, col))
	return p
