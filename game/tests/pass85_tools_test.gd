extends GdUnitTestSuite

## Pass 85, lane TOOLS (Garry's "Watch" tool requests): the Hero Settings pop-up (its pure pieces, its fields mapping to
## the run's start, Start Run down the spawn beam, a restart that ends the run and starts the chosen one), the bot's goal
## plaque (its words for every intent and screen), the Build's icons, the sound off by default, and the bot's wish for the
## power-ups lying on the field (their worth by kind and moment, seen farther, the taste's floor, the grab).

const WATCH := preload("res://tools/watch/Watch.gd")
const SETUP := preload("res://tools/watch/WatchSetup.gd")
const PLAQUE := preload("res://tools/watch/WatchPlaque.gd")
const PANEL := preload("res://tools/watch/WatchPanel.gd")
const BOT := preload("res://tools/bot/Bot.gd")
const GOALS := preload("res://tools/bot/BotGoals.gd")

const ALL_INTENTS := ["kite", "sweep", "explore", "totem", "barrel", "powerup", "chest", "boss", "boss_chest", "portal", "dodge", "down",
	"special", "structure:shop", "structure:healing_well", "structure:hooded_figure"]


var _scale_mode := 0
var _scale_aspect := 0


func before_test() -> void:
	_scale_mode = get_window().content_scale_mode
	_scale_aspect = get_window().content_scale_aspect


func after_test() -> void:
	get_window().content_scale_mode = _scale_mode
	get_window().content_scale_aspect = _scale_aspect
	Run.launch_override = {}
	Run.sim_mode = false
	Run.seed_dice(0)
	Run.forced_map_seed = 0
	get_tree().paused = false
	Engine.time_scale = 1.0
	RenderingServer.render_loop_enabled = true
	AudioServer.set_bus_mute(0, false)
	if Save.sandboxed():
		Save.end_sandbox()
	RunAnalytics.I = null
	Run.end()


# ---------------------------------------------------------------- the pop-up's pure pieces

func test_the_command_line_fills_the_pop_up() -> void:
	var s := SETUP.defaults_from_args({"hero": "calavera", "seed": "77", "seed_random": "1", "speed": "3", "limit": "300", "death": "keep",
		"trail": "36", "trail_optional": "1", "trail_ids": "n001,n002", "bot.preset": "expert", "bot.skill": "0.6", "bot.totems": "off"})
	assert_str(str(s["hero"])).is_equal("calavera")
	assert_int(int(s["seed"])).is_equal(77)
	assert_bool(bool(s["seed_random"])).is_true()
	assert_float(float(s["speed"])).is_equal(2.0)
	assert_float(float(s["limit"])).is_equal(300.0)
	assert_str(str(s["death"])).is_equal("keep")
	# Garry: "Make Sound Off by default"
	assert_bool(bool(s["sound"])).is_false()
	assert_bool(bool(SETUP.defaults_from_args({"sound": "1"})["sound"])).is_true()
	assert_dict(s["bot_opts"]).is_equal({"preset": "expert", "skill": 0.6, "totems": false})
	# pass 129: the Trail (the Upgrade board's talents= until the board went)
	assert_str(str(s["trail"])).is_equal("36")
	assert_bool(bool(s["trail_optional"])).is_true()
	assert_array(s["trail_ids"]).is_equal(["n001", "n002"])
	assert_str(str(SETUP.defaults_from_args({})["trail"])).is_equal("none")


## Pass 129 (the Upgrade board's letters and slots until the board went): the Trail setting's key and words.
func test_the_trail_setting_its_key_and_its_words() -> void:
	assert_str(SETUP.trail_key("quarter", false)).is_equal("quarter")
	assert_str(SETUP.trail_key("36", true)).is_equal("36+opt")
	assert_str(SETUP.trail_key("", false)).is_equal("none")
	assert_str(SETUP.trail_key("0", true)).is_equal("none")
	assert_str(SETUP.trail_key("save", true)).is_equal("save")
	assert_str(SETUP.trail_words("none", false, 70)).is_equal("none")
	assert_str(SETUP.trail_words("quarter", false, 70)).is_equal("a quarter (Trail Level 18 of 70)")
	assert_str(SETUP.trail_words("half", true, 70)).is_equal("half (Trail Level 35 of 70), optional nodes too")
	assert_str(SETUP.trail_words("36", false, 70)).is_equal("Trail Level 36 of 70")
	assert_str(SETUP.trail_words("save", false, 70, 12)).is_equal("my save (Trail Level 12 of 70)")
	assert_str(SETUP.trail_words("save", false, 70)).is_equal("my save")
	assert_array(SETUP.ids_from("n001, n002,,")).is_equal(["n001", "n002"])
	assert_array(SETUP.ids_from("")).is_empty()


func test_the_limit_the_bot_options_and_the_grey_line() -> void:
	assert_float(SETUP.limit_secs("5:00")).is_equal(300.0)
	assert_float(SETUP.limit_secs("300")).is_equal(300.0)
	assert_float(SETUP.limit_secs("1:02:00")).is_equal(3720.0)
	assert_float(SETUP.limit_secs("")).is_equal(0.0)
	assert_float(SETUP.limit_secs("soon")).is_equal(0.0)
	assert_str(SETUP.limit_text(300.0)).is_equal("5:00")
	assert_str(SETUP.limit_text(0.0)).is_equal("")
	var pre: Dictionary = BOT.PRESETS["explorer"]
	var cur := pre.duplicate()
	cur["skill"] = 0.5
	cur["totems"] = false
	assert_dict(SETUP.bot_diff("explorer", pre, cur)).is_equal({"preset": "explorer", "skill": 0.5, "totems": false})
	assert_dict(SETUP.bot_diff("explorer", pre, pre.duplicate())).is_equal({"preset": "explorer"})
	var refs := [{"hero": "drifter", "map": "red_canyon", "trail_key": "quarter", "path": "a/result.json", "label": "a"},
		{"hero": "drifter", "map": "red_canyon", "trail_key": "none", "path": "b/result.json", "label": "b"}]
	assert_dict(SETUP.ref_for(refs, "drifter", "red_canyon", "none")).is_equal({"path": "b/result.json", "label": "b"})
	assert_dict(SETUP.ref_for(refs, "drifter", "red_canyon", "quarter")).is_equal({"path": "a/result.json", "label": "a"})
	assert_dict(SETUP.ref_for(refs, "drifter", "red_canyon", "36+opt")).is_empty()
	assert_dict(SETUP.ref_for(refs, "calavera", "red_canyon", "none")).is_empty()


# ---------------------------------------------------------------- the pop-up's fields map to the run's start

func test_the_pop_ups_fields_map_to_the_runs_start() -> void:
	var st = auto_free(SETUP.new())
	st.size = Vector2(1600, 1000)
	add_child(st)
	var doc := {"trail": {"levels": 70, "save": null, "save_note": "no save"}, "refs": []}
	st.open(SETUP.defaults_from_args({"hero": "drifter", "seed": "5", "trail": "none", "bot.preset": "explorer"}), doc, false)
	assert_bool(st.visible).is_true()
	# the initial pop-up has no Cancel (no run to go back to)
	assert_bool(st._cancel_btn.visible).is_false()
	# the save's Trail is disabled without a PC save, and a tap on it changes nothing
	assert_bool((st._preset_btns["save"] as Button).disabled).is_true()
	st._use_preset("save")
	assert_str(st.trail).is_equal("none")
	st._hero.select(st._hero_ids.find("calavera"))
	st._hero_changed("")
	st._use_preset("half")
	assert_str(st.trail).is_equal("half")
	assert_float(st._trail_level.value).is_equal(35.0)
	st._level_typed(36)
	st._trail_opt.button_pressed = true
	st._seed_random.button_pressed = false
	st._seed.value = 42
	st._speed.select(4)
	st._limit.text = "2:30"
	st._sound.button_pressed = true
	st._bot_preset.select(st._bot_preset_ids.find("expert"))
	st._preset_to_fields()
	(st._bot_fields["skill"] as SpinBox).value = 0.55
	var got := [{}]
	st.started.connect(func(s: Dictionary) -> void: got[0] = s)
	st._on_start()
	var s: Dictionary = got[0]
	assert_bool(st.visible).is_false()
	assert_str(str(s["hero"])).is_equal("calavera")
	assert_int(int(s["seed"])).is_equal(42)
	assert_bool(bool(s["seed_random"])).is_false()
	assert_float(float(s["speed"])).is_equal(4.0)
	assert_float(float(s["limit"])).is_equal(150.0)
	assert_bool(bool(s["sound"])).is_true()
	# half, then Trail Level 36 typed and the optional nodes ticked: a level of its own
	assert_str(str(s["trail"])).is_equal("36")
	assert_bool(bool(s["trail_optional"])).is_true()
	assert_array(s["trail_ids"]).is_empty()
	assert_str(str(s["trail_label"])).is_equal("Trail Level 36 of 70, optional nodes too")
	assert_dict(s["bot_opts"]).is_equal({"preset": "expert", "skill": 0.55})
	# the Watch takes them: the hero, the seed, the Trail, the speed; the launch comes down the beam
	var w = auto_free(WATCH.new())
	w.take_settings(s)
	assert_str(w.hero).is_equal("calavera")
	assert_int(w.run_seed).is_equal(42)
	assert_float(w.clock.speed).is_equal(4.0)
	assert_float(w.limit).is_equal(150.0)
	assert_bool(w.sound_on).is_true()
	assert_dict(w.bot_opts).is_equal({"preset": "expert", "skill": 0.55})
	assert_str(w.trail_text).is_equal("36")
	assert_bool(w.trail_optional).is_true()
	assert_str(w.trail_words()).is_equal("Trail Level 36 of 70, optional nodes too")
	var lo := WATCH.launch_of("calavera", "red_canyon", 42, true)
	assert_bool(bool(lo["spawn"])).is_true()
	assert_str(str(lo["character"])).is_equal("calavera")
	assert_int(int(lo["map_seed"])).is_equal(42)
	# a random seed is drawn at the start (never 0)
	var s2 := s.duplicate()
	s2["seed_random"] = true
	w.take_settings(s2)
	assert_int(w.run_seed).is_greater(0)


## Start Run, then Restart run mid-run: the run ends (recorded), the chosen one starts down the spawn beam with its
## hero and Trail.
func test_start_and_restart_a_run() -> void:
	var w = WATCH.new()
	w.set("args", {"hero": "drifter", "seed": "11", "trail": "none", "analytics": "memory", "repo": "user://p85_no_such_dir",
		"speed": "1"})
	add_child(w)
	await get_tree().process_frame
	# the pop-up first, nothing played
	assert_bool(w.setup_open()).is_true()
	assert_object(w.game).is_null()
	assert_str(str(w.plaque_words()["text"])).is_equal("Waiting for Start Run")
	var s := SETUP.defaults_from_args({"hero": "drifter", "seed": "11", "trail": "5"})
	w.setup.visible = false
	w._on_setup_started(s)
	assert_object(w.game).is_not_null()
	assert_int(w.runs).is_equal(1)
	for i in range(8):
		await get_tree().process_frame
	# down the spawn beam, as the game starts
	assert_bool(bool(w.game.spawning)).is_true()
	assert_str(str(w.plaque_words()["text"])).is_equal("Coming down")
	# the run's save holds the Trail asked for: every required node up to level 5
	assert_int(Trail.level()).is_equal(5)
	assert_int(int(w.trail_info["level"])).is_equal(5)
	assert_bool(Save.trail_bought().is_empty()).is_false()
	var first = w.game
	# Restart run: the pop-up over the run (paused behind it), with Cancel
	w.open_setup(true)
	assert_bool(w.setup.visible).is_true()
	assert_bool(w.setup.can_cancel).is_true()
	assert_bool(w.clock.paused).is_true()
	var s2 := SETUP.defaults_from_args({"hero": "calavera", "seed": "12", "trail": "none"})
	w.setup.visible = false
	w._on_setup_started(s2)
	var waited := 0
	while w.runs < 2 and waited < 120:
		await get_tree().process_frame
		waited += 1
	assert_int(w.runs).is_equal(2)
	assert_bool(is_instance_valid(first)).is_false()
	assert_str(w.hero).is_equal("calavera")
	assert_bool(w.ended).is_false()
	assert_int(w.data.size()).is_equal(0)
	assert_object(w.game).is_not_null()
	await get_tree().process_frame
	assert_bool(bool(w.game.spawning)).is_true()
	# the second run's own Trail: none
	assert_bool(Save.trail_bought().is_empty()).is_true()
	assert_int(Trail.level()).is_equal(0)
	# the sound stays off unless asked
	assert_bool(w.sound_on).is_false()
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# ---------------------------------------------------------------- the plaque

func test_the_plaque_has_words_for_every_intent_and_screen() -> void:
	var base := {"started": true, "screens": "", "intent": "", "goal": {}, "hold": false, "nearest": 20.0, "flee_d": 2.6}
	for it in ALL_INTENTS:
		var info := base.duplicate()
		info["intent"] = it
		info["goal"] = {"what": it, "why": "because", "name": "Heart" if it == "powerup" else ""}
		var d := PLAQUE.words_of(info)
		assert_str(str(d["text"])).is_not_empty()
		assert_bool(str(d["text"]) != it).is_true()
	var w := func(extra: Dictionary) -> String:
		var info := base.duplicate()
		for k in extra:
			info[k] = extra[k]
		return str(PLAQUE.words_of(info)["text"])
	assert_str(w.call({"intent": "kite"})).is_equal("Kiting")
	assert_str(w.call({"intent": "kite", "nearest": 1.0})).is_equal("Running away")
	assert_str(w.call({"intent": "kite", "hold": true, "goal": {"what": "totem"}})).is_equal("Running away")
	assert_str(w.call({"intent": "dodge"})).is_equal("Dodging")
	assert_str(w.call({"intent": "powerup", "goal": {"what": "powerup", "name": "Heart"}})).is_equal("Grabbing a power-up: Heart")
	assert_str(w.call({"intent": "special", "goal": {"what": "special", "name": "Red Goblin"}})).is_equal("Hunting a special: Red Goblin")
	assert_str(w.call({"intent": "totem", "goal": {"what": "totem"}})).is_equal("Going to a Totem Pole")
	assert_str(w.call({"intent": "explore"})).is_equal("Exploring the map")
	assert_str(w.call({"intent": "structure:shop"})).is_equal("Going to the shop")
	assert_str(w.call({"intent": "structure:healing_well", "goal": {"what": "structure:healing_well", "name": "Healing Well"}})).is_equal("Going to the Healing Well")
	assert_str(w.call({"intent": "chest"})).is_equal("Going for a chest")
	assert_str(w.call({"screens": "cards"})).is_equal("Picking a level-up")
	assert_str(w.call({"screens": "cards", "path": true})).is_equal("Choosing a mutation")
	assert_str(w.call({"screens": "shop"})).is_equal("At the shop")
	assert_str(w.call({"screens": "totem"})).is_equal("At a Totem Pole")
	assert_str(w.call({"screens": "chest"})).is_equal("Opening a chest")
	assert_str(w.call({"screens": "stranger"})).is_equal("Dealing with the Stranger")
	assert_str(w.call({"screens": "revive"})).is_equal("Down!")
	assert_str(w.call({"spawning": true})).is_equal("Coming down")
	assert_str(w.call({"ended": true})).is_equal("Run over")
	assert_str(w.call({"setup": true})).is_equal("Waiting for Start Run")
	assert_str(w.call({"started": false})).is_equal("")


func test_the_plaque_switches_with_a_fade() -> void:
	var p = auto_free(PLAQUE.new())
	add_child(p)
	p.place(Vector2.ZERO, Vector2(500, 1100))
	p.show_words({"text": "Kiting", "sub": "", "tone": "calm"})
	assert_bool(p.visible).is_true()
	assert_str(p.shown).is_equal("Kiting")
	# a new goal waits HOLD_S before it shows (no flicker), then fades in
	p.show_words({"text": "Going for a chest", "sub": "a chest 7 m off", "tone": "goal"})
	assert_str(p.shown).is_equal("Kiting")
	p._want_ms -= int(PLAQUE.HOLD_S * 1000.0) + 10
	p.show_words({"text": "Going for a chest", "sub": "a chest 7 m off", "tone": "goal"})
	assert_str(p.shown).is_equal("Going for a chest")
	assert_float(p.modulate.a).is_less(1.0)
	p.show_words({"text": "", "sub": ""})
	assert_bool(p.visible).is_false()


# ---------------------------------------------------------------- the Build's icons

class FakeW:
	extends Node

	func name_of(id: String) -> String:
		return id.capitalize()

	func passive_def(id: String) -> Resource:
		return Registry.passive(id)


class FakeWi:
	extends RefCounted
	var def: WeaponDef
	var level := 1
	var mutations: Array = []


class FakeRunB:
	extends RefCounted
	var weapons: Array = []
	var passives: Dictionary = {}
	var perks: Array = []


func test_the_build_shows_the_games_icons() -> void:
	var w: FakeW = auto_free(FakeW.new())
	add_child(w)
	var run := FakeRunB.new()
	var wi := FakeWi.new()
	wi.def = Registry.weapon("revolver")
	wi.level = 3
	for m in Registry.mutations.values():
		if str(m.weapon) == "revolver" and m.icon != null:
			wi.mutations.append(m)
			break
	assert_int(wi.mutations.size()).is_equal(1)
	run.weapons.append(wi)
	var pid := ""
	for id in Registry.passives.keys():
		var pd: PassiveDef = Registry.passives[id]
		if not pd.hidden and pd.icon != null:
			pid = str(id)
			break
	run.passives[pid] = 2
	var rows: Array = PANEL.build_rows(w, run)
	assert_str(str(rows[0][0])).is_equal("Weapons")
	var group: Array = rows[0][1][0]
	assert_object(group[0][0]).is_instanceof(Texture2D)
	assert_str(str(group[0][1])).is_equal(str(wi.def.display_name))
	assert_int(int(group[0][2])).is_equal(3)
	for k in range(1, group.size()):
		assert_bool(bool(group[k][3])).is_true()
	var words: Array = []
	for r in rows:
		words.append(str(r[0]))
	assert_array(words).contains(["Weapons", "Cards", "Items"])
	assert_array(words).not_contains(["Evolutions", "Perks"])
	# the panel draws them as chips with the texture
	var panel = auto_free(PANEL.new())
	add_child(panel)
	var chip: Control = panel._chip(group[0][0], "Revolver", 3, false)
	auto_free(chip)
	var texs: Array = chip.find_children("*", "TextureRect", true, false)
	assert_int(texs.size()).is_equal(1)
	assert_object((texs[0] as TextureRect).texture).is_same(group[0][0])
	assert_str(PANEL.build_key(run)).contains("revolver:3")


# ---------------------------------------------------------------- the power-ups (Garry: "it feels like he is ignoring them")

func test_a_power_ups_worth_follows_the_moment() -> void:
	# a heart: by how hurt he is, none while he is well
	assert_float(GOALS.powerup_value("heal", {"hp_frac": 0.95})).is_equal(0.0)
	assert_float(GOALS.powerup_value("heal", {"hp_frac": 0.4})).is_greater(GOALS.powerup_value("heal", {"hp_frac": 0.7}))
	# the vacuum: by the XP lying, capped
	var v0 := GOALS.powerup_value("vacuum", {"xp_lying": 0.0, "xp_need": 100.0})
	var v1 := GOALS.powerup_value("vacuum", {"xp_lying": 150.0, "xp_need": 100.0})
	assert_float(v1).is_greater(v0)
	assert_float(GOALS.powerup_value("vacuum", {"xp_lying": 100000.0, "xp_need": 100.0})).is_equal(GOALS.PU_VACUUM_MAX)
	# buffs, the shield and the nuke: more while he fights
	assert_float(GOALS.powerup_value("buff", {"crowd": 10})).is_greater(GOALS.powerup_value("buff", {"crowd": 0}))
	assert_float(GOALS.powerup_value("nuke", {"crowd": 20})).is_greater(GOALS.powerup_value("nuke", {"crowd": 2}))
	assert_float(GOALS.powerup_value("shield", {"hp_frac": 0.3})).is_greater(GOALS.powerup_value("shield", {"hp_frac": 1.0}))
	# every kind is worth more than pass 80's flat value (the reason he ignored them)
	assert_float(GOALS.powerup_value("buff", {})).is_greater(float(GOALS.V_POWERUP["buff"]))
	assert_float(GOALS.powerup_value("shield", {})).is_greater(float(GOALS.V_POWERUP["shield"]))


class FakeInputP:
	extends RefCounted
	var wants_move := false


class FakePlayerP:
	extends Node3D
	var input := FakeInputP.new()
	var hp := 100.0
	var max_hp := 100.0
	var dead := false


class FakeMapP:
	extends RefCounted
	var flats_center := Vector3.ZERO
	var arena_radius := 66.0


class FakePickupDefP:
	extends RefCounted
	var effect_kind := "buff"
	var display_name := "Rage"


class FakePowerupP:
	extends Node3D
	var def := FakePickupDefP.new()
	var taken := false
	var life := 40.0


class FakePickupsP:
	extends RefCounted
	var specials: Array = []
	var chests: Array = []


class FakeGameP:
	extends Node
	var player: FakePlayerP
	var map := FakeMapP.new()
	var pickups := FakePickupsP.new()


class FakeSheetP:
	extends RefCounted

	func get_stat(_n: String, d: float = 0.0) -> float:
		return d


class FakeRunP:
	extends RefCounted
	var player_sheet := FakeSheetP.new()
	var stage := 0
	var run_gold := 0


func test_power_ups_are_seen_farther_and_wanted() -> void:
	var g: FakeGameP = auto_free(FakeGameP.new())
	g.player = FakePlayerP.new()
	add_child(g)
	g.add_child(g.player)
	var pu := FakePowerupP.new()
	g.add_child(pu)
	# 24 m off: past pass 80's 18 m, inside PU_SEE
	pu.global_position = Vector3(24, 0, 0)
	g.pickups.specials.append(pu)
	var gl = GOALS.new(7)
	gl.setup_map(g.map)
	var view := {"me": Vector3.ZERO, "t": 10.0, "hp_frac": 1.0, "danger": 0.0, "style": "balanced", "opts": BOT.resolve_opts({"preset": "explorer", "explore": 0.0}),
		"boss": Vector3.INF, "leash": true, "lure_s": 0.0, "lure_at": Vector3.INF, "crowd": 6}
	var cands: Array = gl.candidates(g, FakeRunP.new(), view)
	var got := {}
	for c in cands:
		if str(c["kind"]) == "powerup":
			got = c
	assert_dict(got).is_not_empty()
	assert_str(str(got["name"])).is_equal("Rage")
	assert_str(str(got["why"])).contains("6 creatures close")
	# the run's lowest taste and mood still want it: the floor
	gl.taste["powerup"] = GOALS.TASTE_LO
	var low: Array = gl.candidates(g, FakeRunP.new(), view)
	for c in low:
		if str(c["kind"]) == "powerup":
			var floor_u: float = float(c["value"]) * GOALS.PU_TASTE_FLOOR * GOALS.JIT_LO / (1.0 + 24.0 / GOALS.DIST_SCALE)
			assert_float(float(c["u"])).is_greater_equal(floor_u - 0.01)
			assert_float(float(c["u"])).is_greater(BOT.U_MIN)
	# past PU_SEE: no goal
	pu.global_position = Vector3(GOALS.PU_SEE + 2.0, 0, 0)
	var far := false
	for c in gl.candidates(g, FakeRunP.new(), view):
		far = far or str(c["kind"]) == "powerup"
	assert_bool(far).is_false()
	# the grab: within PU_GRAB m of a power-up the crowd no longer holds him off
	assert_float(GOALS.PU_GRAB).is_greater(BOT.HOLD_GRAB)
