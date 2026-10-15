## The run. Wires map, player, camera, enemies, projectiles, pickups, weapons, waves, and the in-run UI.
class_name Game
extends Node3D

const PLAYER_SCENE := preload("res://player/Player.tscn")
const RESULTS := "res://ui/ResultsScreen.tscn"

@onready var world: Node3D = $World
@onready var enemies: EnemyManager = $EnemyManager
@onready var projectiles: ProjectileManager = $ProjectileManager
@onready var pickups: PickupManager = $PickupManager
@onready var telegraphs: Telegraphs = $Telegraphs
@onready var fx: Fx = $Fx
@onready var camera: CameraRig = $CameraRig
@onready var weapon_host: Node3D = $WeaponHost
@onready var ui: CanvasLayer = $UI

var player: Player
var map: MapBase
var director: WaveDirector
var portal: Portal
var structures: StructureManager
var barrels: BarrelField
var structure_shop: StructureShop
var chest_screen: ChestScreen
var resume_gate: ResumeGate
var revive_screen: ReviveScreen
var stranger_screen: StrangerScreen
## pass 73 (lane STRUCT): the Totem Pole's gifts (ui/TotemScreen.gd, by path: a new script's class name is unknown
## until the editor imports it)
const TOTEM_SCREEN := preload("res://ui/TotemScreen.gd")
var totem_screen: TOTEM_SCREEN
var paused := false
var hud: HUD
## the floating damage numbers (pass 46, DamageNumbers): on the UI layer under the HUD
var damage_numbers: DamageNumbers
var cards: CardScreen
var pause_screen: PauseScreen
var portal_dialog: PortalDialog
var hints: Hints
var debug_panel: DebugPanel
## level-ups not yet offered: the bank (pass 60: it also holds those that came while the hero was down)
var _pending_levels := 0
var _spit_kind := -1
var _harpoon_kind := -1
var _rocket_kind := -1
var _pellet_kind := -1
var _spike_kind := -1
var _shard_kind := -1
var _tumble_kind := -1
const TUMBLE_R := 0.55   # the King's volley (pass 45): tumbleweeds 1.1 m across
var _breadcrumb_t := 0.0
# the harpoon tether (pass 28; a leash since pass 33.10): the creature holding the rope, seconds left, the rope's length
# (as long as the throw, shortening as the hero walks in), its shortest, and his speed walking straight away from it
var tether_i := -1
var tether_t := 0.0
var tether_len := 4.0
var tether_min := 1.8
var tether_away := 0.7
var _tether_dust := 0.0
var _harpoon_proj := -1
var _harpoon_shooter := -1
var _rope: MeshInstance3D
var _rope_mesh: ImmediateMesh
var _rope_dark: StandardMaterial3D
var _rope_light: StandardMaterial3D
var _behaviors: Dictionary = {}    # weapon id -> WeaponBehavior
var no_random_chests := false      # the capture tool: no kill-dropped chest may open the reel mid-sequence
var _ended := false
var _run_started := false


## The debug arena (pass 33.4): the panel over it, whether a level-up shows its cards; Save.begin_sandbox keeps the save
## off the disk while it is open (pass 45), so nothing done in the arena is kept.
var arena_panel: ArenaPanel = null
var arena_cards := false


func _ready() -> void:
	# a tool's launch file first (pass 66): its `arena` opens the debug arena as the title's ARENA does (the Level
	# Editor's "Test in game" launches the editor binary straight into it, _launch_in_arena)
	var debug_launch := _read_debug_launch()
	# pass 77 (lane SIMRUN): the run sim's fast mode (Run.sim_mode), every run's own (off unless its launch says)
	Run.sim_mode = bool(debug_launch.get("sim_fast", false))
	# and the run's own clock for the rules that count real time (Run.rule_seconds), every run sim's in both its modes
	Run.sim_clock = bool(debug_launch.get("sim_clock", false))
	var arena: bool = Run.arena_next or bool(debug_launch.get("arena", false))
	Run.arena_next = false
	# the arena keeps nothing: the save as it is now (before Run.start counts a run) goes back when it closes
	if arena:
		Save.begin_sandbox()
	var character_id: String = str(Save.data.get("last_character", Save.DEFAULT_HERO))
	var map_id: String = str(Save.data.get("last_map", "red_canyon"))
	if debug_launch.has("character"):
		character_id = str(debug_launch["character"])
	if debug_launch.has("map"):
		map_id = str(debug_launch["map"])
	if debug_launch.has("map_seed"):
		Run.forced_map_seed = int(debug_launch["map_seed"])
	# only a playable hero (the editor's test launch may still name a hidden one)
	var character: CharacterDef = Registry.character(character_id) if debug_launch.has("character") else Registry.playable_character(character_id)
	if character == null and not Registry.characters.is_empty():
		character = Registry.playable_character("astro")
	var mapdef: MapDef = Registry.map(map_id)
	if mapdef == null and not Registry.maps.is_empty():
		mapdef = Registry.sorted_maps()[0]
	Run.start(character, mapdef)
	Run.arena = arena
	# map
	if mapdef and mapdef.scene:
		map = mapdef.scene.instantiate()
	else:
		map = load("res://world/maps/red_canyon/RedCanyon.tscn").instantiate()
	world.add_child(map)
	if map.has_method("bind_game"):
		map.bind_game(self)
	# player
	player = PLAYER_SCENE.instantiate()
	player.setup(character)
	add_child(player)
	player.global_position = map.player_start()
	player.camera_yaw_fn = camera.current_yaw
	camera.snap_to(player)
	player.died.connect(_on_player_died)
	player.damaged.connect(func(hp, mx): if hud: hud.set_hp(hp, mx))
	player.hit.connect(func(): camera.shake(0.9))
	player.hit.connect(_on_player_hit)
	# Evade and the Energy Shield say so where the hero stands
	player.evaded.connect(func():
		fx.burst(player.global_position + Vector3(0, 0.9, 0), Color(0.8, 0.9, 1.0), 0.8)
		telegraphs.flash_ring(player.global_position, 0.9, Color(0.85, 0.95, 1.0), 0.25)
		# pass 67: the weapons that answer an evade (Fadeaway's Free Throw, ProjectileEmitter.on_hero_evaded) are told
		_tell_behaviors("on_hero_evaded"))
	player.shield_hit.connect(func(broke: bool):
		# Skedaddle runs on a hit that lands on the Energy Shield too (pass 48); Hot Streak and Loose Change are his health's
		_skedaddle()
		telegraphs.flash_ring(player.global_position, 1.1, Color(0.36, 0.74, 1.0), 0.3)
		if broke:
			fx.burst(player.global_position + Vector3(0, 1.0, 0), Color(0.36, 0.74, 1.0), 1.3)
			Audio.play("ui_pause", player.global_position))
	player.momentum_trail.connect(func(at, back, strength): fx.trail(at, back, strength))
	# Deep Breath (pass 46, Ironwood): the regen surge shows where he stands
	player.deep_breath.connect(func():
		telegraphs.flash_ring(player.global_position, 1.4, UiKit.GOOD, 0.45)
		fx.burst(player.global_position + Vector3(0, 0.9, 0), UiKit.GOOD, 1.0)
		if hud: hud.toast("DEEP BREATH", UiKit.GOOD)
		Audio.play("pk_heart", player.global_position))
	# pass 69, the new passive items: Hot Springs' heal pulse, Last Stand's slowed time, Counterpunch's armed fist
	player.heal_pulsed.connect(_heal_pulse)
	player.last_stand.connect(_last_stand)
	player.evaded.connect(_counterpunch_fx)
	# systems
	enemies.game = self
	enemies.player = player
	enemies.height_fn = map.height_at
	enemies.obstacles = map.obstacles
	enemies.arena_radius = map.arena_radius
	telegraphs.height_fn = map.height_at
	telegraphs.set_ground(map)
	enemies.enemy_died.connect(_on_enemy_died)
	projectiles.game = self
	pickups.game = self
	_spit_kind = projectiles.register_kind(_spit_mesh(), _spit_material(), 1.0)
	_harpoon_kind = projectiles.register_kind(_harpoon_mesh(), _harpoon_material(), 1.0)
	# custom data: the loose rocket's blink and heat reach its shader per instance (pass 45); white instance colours so its
	# vertex paint reaches the shader (pass 48, paint_white)
	_rocket_kind = projectiles.register_kind(_rocket_mesh(), _rocket_material(), 1.0, true)
	paint_white(projectiles.kinds[_rocket_kind]["mm"])
	_pellet_kind = projectiles.register_kind(_pellet_mesh(), _pellet_material(), 1.0)
	_spike_kind = projectiles.register_kind(_spike_mesh(), _spike_material(), 1.0)
	_shard_kind = projectiles.register_kind(_shard_mesh(), _shard_material(), 1.0)
	# the GLB ball is 0.8 m and register_kind multiplies by CHUNK, so this lands the tumbleweed at TUMBLE_R
	_tumble_kind = projectiles.register_kind(_tumble_mesh(), _tumble_material(), TUMBLE_R / 0.8 / ProjectileManager.CHUNK)
	director = WaveDirector.new()
	director.game = self
	add_child(director)
	# the map's structures, scattered once per run
	structures = StructureManager.new()
	add_child(structures)
	if mapdef and mapdef.timeline and not mapdef.timeline.structures.is_empty():
		structures.setup(self, map, mapdef.timeline.structures)
	# the signposts (pass 54): four to six, their arms pointing at the structures; before the barrels, which keep clear of them
	preload("res://core/systems/SignField.gd").spawn(self, map)
	# the barrels (pass 44): thirty-three by the run's seed, never behind a painting, broken by walking up to them
	barrels = BarrelField.new()
	barrels.name = "Barrels"
	add_child(barrels)
	barrels.setup(self, map)
	director.portal_ready.connect(_on_portal_ready)
	director.boss_started.connect(func(def): if hud: hud.show_boss(def))
	director.stage_started.connect(func(s):
		if hud: hud.refresh_stage()
		# stage 3 is hell: the sand goes a shade redder (pass 43), and stays so through endless
		if map and map.has_method("set_hell"): map.set_hell(1.0 if s >= 2 else 0.0, 3.0))
	director.boss_started.connect(_on_boss_started)
	enemies.boss_hp_changed.connect(func(hp, mx): if hud: hud.set_boss_hp(hp, mx))
	enemies.boss_died.connect(func(_d, _p): if hud: hud.hide_boss())
	# the run's music (pass 64): each stage its own track, the boss's over it while a boss lives
	director.stage_started.connect(func(s): Audio.music_stage(s))
	director.boss_started.connect(func(_def): Audio.music_boss(true, str(mapdef.music.get("boss", "mu_boss")) if mapdef else "mu_boss"))
	enemies.boss_died.connect(func(_d, _p): Audio.music_boss(false))
	Run.level_up.connect(_on_level_up)
	Run.lifesteal_healed.connect(func(n): if player and not player.dead: player.heal(n))
	Run.build_changed.connect(_sync_weapons)
	Run.hero_sheet_changed.connect(_on_hero_sheet_changed)
	Run.weapon_evolved.connect(_on_evolved)
	# the run recorder (pass 45): a row a second for analytics/dashboard.html; the arena never records, and a tool's
	# launch file may say "analytics": false (perf_late's A/B of the recorder's cost)
	if not arena and bool(debug_launch.get("analytics", true)): RunAnalytics.create(self, debug_launch)
	# the run's story for the Results screen (pass 72, RunTimeline): the arena never has one
	if not arena: Run.timeline.attach(self)
	# ui
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	# the damage numbers first: the HUD and every screen draw over them
	damage_numbers = DamageNumbers.new()
	damage_numbers.name = "DamageNumbers"
	damage_numbers.game = self
	damage_numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(damage_numbers)
	hud = HUD.new()
	hud.game = self
	ui.add_child(hud)
	cards = CardScreen.new()
	ui.add_child(cards)
	pause_screen = PauseScreen.new()
	pause_screen.game = self
	ui.add_child(pause_screen)
	portal_dialog = PortalDialog.new()
	ui.add_child(portal_dialog)
	# once for the run (pass 48: it was connected one-shot on every entry, and a "Not yet" left the old one waiting)
	portal_dialog.decided.connect(_on_portal_decided)
	if portal_dialog.has_signal("declined"):
		portal_dialog.declined.connect(_on_portal_declined)
	structure_shop = StructureShop.new()
	ui.add_child(structure_shop)
	chest_screen = ChestScreen.new()
	ui.add_child(chest_screen)
	chest_screen.closed.connect(_on_chest_closed)
	revive_screen = ReviveScreen.new()
	ui.add_child(revive_screen)
	revive_screen.decided.connect(_on_revive_decided)
	stranger_screen = StrangerScreen.new()
	ui.add_child(stranger_screen)
	# pass 73 (lane STRUCT): the Totem Pole's gifts
	totem_screen = TOTEM_SCREEN.new()
	totem_screen.name = "TotemScreen"
	ui.add_child(totem_screen)
	resume_gate = ResumeGate.new()
	resume_gate.hud = hud
	ui.add_child(resume_gate)
	resume_gate.resumed.connect(_after_gate)
	# the one-modal rule's watch (pass 60): in the player's debug mode an error names two screens up at once; on the
	# tree's frame signal, since the screens are up only while the run is paused and Game's own _process is not
	get_tree().process_frame.connect(_check_one_modal)
	hints = Hints.new()
	hints.game = self
	ui.add_child(hints)
	debug_panel = DebugPanel.new()
	debug_panel.game = self
	ui.add_child(debug_panel)
	hud.pause_requested.connect(open_pause)
	# music
	if mapdef:
		var run_music = mapdef.music.get("run", [])
		if run_music is Array:
			Audio.play_music(run_music, 1)
	if Run.arena:
		_start_arena()
		_launch_in_arena(debug_launch)
		return
	# the hero's own gun from the first second (pass 45): no starter pick; a launch file may name another weapon and level
	var start: WeaponDef = null
	var start_level := 1
	if debug_launch.has("weapon"):
		start = Registry.weapon(str(debug_launch["weapon"]))
		start_level = int(debug_launch.get("level", 1))
	if start == null:
		start = Registry.start_weapon_for(character)
	if start:
		if RunAnalytics.I: RunAnalytics.I.via = "starter"
		var inst := Run.add_weapon(start, start_level)
		if inst and Run.character and start.id == Run.character.favourite_weapon:
			CardPool.apply_favourite(inst)
	# the beam (the cinematic) for a real launch; a tool's launch file gets the instant start unless it says "spawn": true
	if bool(debug_launch.get("spawn", debug_launch.is_empty())):
		_spawn_begin()
	else:
		# everything the run can draw, drawn once under the hero, so no first-appearance hitch
		Warmup.run(self)
		_start_run()


func _read_debug_launch() -> Dictionary:
	# pass 77 (lane SIMRUN): a launch set in memory comes first (Run.launch_override, the run sim's), taken once; the
	# file is not touched then (side-by-side processes would race on it)
	if not Run.launch_override.is_empty():
		var lo: Dictionary = Run.launch_override
		Run.launch_override = {}
		return lo
	if not FileAccess.file_exists("user://debug_launch.json"):
		return {}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	DirAccess.remove_absolute("user://debug_launch.json")
	return d if d is Dictionary else {}


## The launch file's arena keys (pass 66, the Level Editor's "Test in game"): `look` draws the hero in that art for this
## visit (Player.show_look; the Save is not touched, as the arena's chips), `spawn_enemy` with `variant` and `count` (3
## when absent) puts that creature near him wearing that look (Registry.enemy_with, ArenaPanel.spawn_enemy_n). A
## hidden hero by `character` works already (above). Every other key keeps its meaning.
func _launch_in_arena(launch: Dictionary) -> void:
	if launch.is_empty():
		return
	if launch.has("look") and player:
		player.show_look(str(launch["look"]))
	if launch.has("spawn_enemy") and arena_panel:
		var id := str(launch["spawn_enemy"])
		var d: EnemyDef = Registry.enemy_with(id, str(launch.get("variant", "")))
		if d:
			arena_panel.spawn_enemy_n(d, int(launch.get("count", 3)))
		else:
			push_warning("debug_launch: no creature '%s' to spawn" % id)


func _start_run() -> void:
	_run_started = true
	_sync_weapons()
	director.start(Run.map)
	if not Run.arena:
		hints.begin()
	hud.refresh_stage()


## The debug arena: the hero with the gun a run starts him with, god mode on, the director set up but holding its clock
## and its spawns, and the arena panel over the HUD. The save is sandboxed now and put back when the arena closes.
func _start_arena() -> void:
	if not Save.sandboxed():
		Save.begin_sandbox()
	# his own gun (pass 46: Ironwood's favourite is a passive, so the favourite weapon no longer says)
	var fav: WeaponDef = Registry.start_weapon_for(Run.character)
	if fav == null:
		fav = Registry.weapon("peashooter")
	if fav:
		Run.add_weapon(fav, 1)
	player.god = true
	Warmup.run(self)
	_start_run()
	director.running = false
	arena_panel = ArenaPanel.new()
	arena_panel.game = self
	ui.add_child(arena_panel)
	hud.banner("DEBUG ARENA", UiKit.INFO)
	# a field of training dummies to hit (pass 48), as many and as tough as the developer menu says, and the Elite dummy
	# and the Boss dummy apart from it (pass 49)
	arena_dummies(Settings.dummy_count, Settings.dummy_hp)


## The debug arena's training dummies (pass 48, content/enemies/training_dummy: the `dummy` brain, never bites, drops
## nothing, counts for no quest): the old field goes, and `count` of them (at least DUMMY_MIN) stand in rows of DUMMY_ROW,
## DUMMY_GAP apart, the nearest row DUMMY_AHEAD north of the hero. `hp` 0 makes them undying (EnemyManager.undying: a hit
## that would kill one fills it up again; every number, flash, status, shove, freeze and grab shows as on a creature);
## any other `hp` is each one's health, and one that dies stands up again on its spot DUMMY_BACK seconds later. Shoved
## off its spot, a dummy walks back (the brain). The arena's CLEAR takes them away for good (EnemyManager.cleared).
## Pass 49 (Garry's arena list): the field patrols while Settings.dummy_patrol says so (EnemyManager.DUMMY_PATROL: left
## and right round each spot); the Elite dummy (the Elites' crown) and the Boss dummy (a skull at a boss's size, but an
## Elite by its kind too, never the run's boss: no bar, no portal) stand apart from it, behind it to the left and to the
## right (DUMMY_SIDE, DUMMY_BEHIND), with a health and a behaviour of their own (Settings.elite_dummy_* and
## boss_dummy_*: stand, patrol, melee, ranged); and attackers are added one at a time from the WORLD tab (add_attacker: a
## melee one that chases and bites, a ranged one that spits like the Spit Cactus), each on a spot of its own by the hero,
## at Settings.attacker_dummy_hp, never touching the field. Every one of them stands up again DUMMY_BACK seconds after it
## falls and pays nothing (_kill_effects), and the first attacking one on the field turns god mode off (_check_attackers).
const DUMMY_ID := "training_dummy"
const ELITE_DUMMY_ID := "training_dummy_elite"
const BOSS_DUMMY_ID := "training_dummy_boss"
## the attackers' creatures by kind (pass 49)
const ATTACKER_IDS := {"melee": "training_dummy_melee", "ranged": "training_dummy_ranged"}
## Settings' behaviour words as EnemyManager's DUMMY_* codes (stand 0, patrol 1, melee 2, ranged 3)
const DUMMY_MODE_CODES := {"stand": 0, "patrol": 1, "melee": 2, "ranged": 3}
const DUMMY_MIN := 10
const DUMMY_ROW := 5
const DUMMY_GAP := 1.6
const DUMMY_AHEAD := 7.0
const DUMMY_BACK := 5.0
## the Elite and the Boss dummy stand DUMMY_BEHIND m north of the field's back row, DUMMY_SIDE m left and right of its
## middle. Not beside the field: on a phone the view is about 5.8 m either side at the field's depth, and the arena's
## column of quick buttons covers the right edge there, so a dummy 6 m to the side was cut off or hidden (pass 49)
const DUMMY_SIDE := 3.0
const DUMMY_BEHIND := 4.5
## an attacker's spot: ATTACKER_RING m from the hero, round his south side first (the field stands north of the spawn) and
## no more than ATTACKER_ARC degrees either side of due south, at least ATTACKER_GAP from every other attacker's spot and
## clear of the field's rows, the Elite's and the Boss's; then rings 2.5 m wider
const ATTACKER_RING := 5.0
const ATTACKER_GAP := 2.6
const ATTACKER_ARC := 100.0
## each dummy: {"at": its spot, "i": its creature index, "serial": that spawn's serial, "dead_t": seconds until it stands
## up again (below zero while it stands), "id": its creature, "role": field | elite | boss | melee | ranged (pass 49),
## "dir": the way its patrol sets off, +1 east, -1 west}. The field, the Elite and the Boss are `_dummies` (arena_dummies
## lays them out); the attackers are `_attackers`, which a new field leaves be.
var _dummies: Array = []
var _attackers: Array = []
var _dummy_hp := 0
## whether a dummy on the field attacks (an attacker, or the Elite or the Boss set to melee or ranged): god mode goes off
## when this turns true (_check_attackers)
var _attacking := false


func arena_dummies(count: int, hp: int) -> void:
	clear_dummies()
	if Registry.enemy(DUMMY_ID) == null or enemies == null:
		return
	_watch_dummies()
	_dummy_hp = maxi(hp, 0)
	var n := maxi(count, DUMMY_MIN)
	var base: Vector3 = player.global_position if player else Vector3.ZERO
	for k in range(n):
		var row := k / DUMMY_ROW
		var in_row := mini(DUMMY_ROW, n - row * DUMMY_ROW)
		var col := k % DUMMY_ROW
		var at := _dummy_ground(base + Vector3((float(col) - float(in_row - 1) * 0.5) * DUMMY_GAP, 0.0, -DUMMY_AHEAD - float(row) * DUMMY_GAP))
		# a patrolling field sets off row against row: the first row east, the second west
		var rec := {"at": at, "i": -1, "serial": -1, "dead_t": -1.0, "id": DUMMY_ID, "role": "field", "dir": 1.0 if row % 2 == 0 else -1.0}
		_dummies.append(rec)
		_stand_dummy(rec)
	# the Elite dummy behind the field on the left and the Boss dummy behind it on the right (pass 49); a patrol of theirs
	# sets off outwards
	var back_z := -DUMMY_AHEAD - floorf(float(n - 1) / float(DUMMY_ROW)) * DUMMY_GAP
	for spec in [[ELITE_DUMMY_ID, "elite", -1.0], [BOSS_DUMMY_ID, "boss", 1.0]]:
		if Registry.enemy(str(spec[0])) == null:
			continue
		var side: float = spec[2]
		var at2 := _dummy_ground(base + Vector3(DUMMY_SIDE * side, 0.0, back_z - DUMMY_BEHIND))
		var rec2 := {"at": at2, "i": -1, "serial": -1, "dead_t": -1.0, "id": str(spec[0]), "role": str(spec[1]), "dir": side}
		_dummies.append(rec2)
		_stand_dummy(rec2)
	_check_attackers()


## A spot on the ground inside the arena's wall (as it is without a map).
func _dummy_ground(at: Vector3) -> Vector3:
	if map:
		at = map.clamp_to_arena(at)
		at.y = map.height_at(at.x, at.z)
	return at


## The dummies' two ears on the crowd, put on once: a fall (it stands up again) and the arena's CLEAR (they stay away).
func _watch_dummies() -> void:
	if not enemies.creature_dying.is_connected(_on_creature_dying):
		enemies.creature_dying.connect(_on_creature_dying)
	if not enemies.cleared.is_connected(_on_field_cleared):
		enemies.cleared.connect(_on_field_cleared)


## Every dummy of the layout off the field now (the arena's reset, a new field): the field, the Elite and the Boss. The
## attackers stay (remove_attackers takes them).
func clear_dummies() -> void:
	_free_dummies(_dummies)


## Every attacker off the field now (pass 49, the WORLD tab's REMOVE ATTACKERS); the field stays.
func remove_attackers() -> void:
	_free_dummies(_attackers)
	_check_attackers()


func _free_dummies(list: Array) -> void:
	for rec in list:
		var i := int(rec["i"])
		if i >= 0 and enemies.alive[i] == 1 and enemies.serial[i] == int(rec["serial"]):
			enemies._free(i)
	list.clear()


## How many dummies of the field stand now (tests, the arena's tools); the Elite and the Boss dummy are dummy_index's,
## the attackers attackers_standing's.
func dummies_standing() -> int:
	var n := 0
	for rec in _dummies:
		if str(rec.get("role", "field")) == "field" and _standing(rec) >= 0:
			n += 1
	return n


## The creature index of the Elite dummy ("elite") or the Boss dummy ("boss") while it stands, else -1 (pass 49).
func dummy_index(role: String) -> int:
	for rec in _dummies:
		if str(rec.get("role", "")) == role:
			return _standing(rec)
	return -1


## How many attackers stand now (pass 49): of one kind ("melee", "ranged"), or all of them ("").
func attackers_standing(kind: String = "") -> int:
	var n := 0
	for rec in _attackers:
		if (kind == "" or str(rec["role"]) == kind) and _standing(rec) >= 0:
			n += 1
	return n


## What creature `i` is in the arena's layout while it stands (pass 49): "field", "elite", "boss", "melee" or "ranged";
## "" for any other creature (tests, the arena's tools).
func dummy_role(i: int) -> String:
	if i < 0:
		return ""
	for rec in _dummies + _attackers:
		if _standing(rec) == i:
			return str(rec.get("role", "field"))
	return ""


## The record's creature while it stands (alive, not falling, still the spawn it made), else -1.
func _standing(rec: Dictionary) -> int:
	var i := int(rec["i"])
	if i >= 0 and enemies.is_alive(i) and enemies.serial[i] == int(rec["serial"]):
		return i
	return -1


func _stand_dummy(rec: Dictionary) -> void:
	var i := enemies.spawn(str(rec.get("id", DUMMY_ID)), rec["at"])
	rec["dead_t"] = -1.0
	if i < 0:
		rec["i"] = -1
		return
	rec["i"] = i
	rec["serial"] = enemies.serial[i]
	_dress_dummy(rec, true)


## A standing dummy's health and behaviour put in place (pass 49: out of _stand_dummy, so a setting changed in the arena
## reaches the ones already standing): its role's health (dummy_hp_of; 0 = undying, its bar then the def's health), its
## role's behaviour (dummy_mode_of), a patrol for an attacker with nothing to hit while the field patrols, and the damage
## that goes with the behaviour, as its JSON says and not scaled by the arena's clock: `damage` on a touch,
## `ranged.damage` on a spit. `fresh`: it has just stood up, so it is whole and its patrol sets off its own way;
## otherwise its health is touched only when the setting changed.
func _dress_dummy(rec: Dictionary, fresh: bool = false) -> void:
	var i := _standing(rec)
	if i < 0:
		return
	var def: EnemyDef = Registry.enemy(str(rec.get("id", DUMMY_ID)))
	if def == null:
		return
	var role := str(rec.get("role", "field"))
	var hp_set := dummy_hp_of(role)
	var hp: float = float(hp_set) if hp_set > 0 else def.hp
	var und := 0 if hp_set > 0 else 1
	if fresh or not is_equal_approx(enemies.max_hp[i], hp) or int(enemies.undying[i]) != und:
		enemies.hp[i] = hp
		enemies.max_hp[i] = hp
	enemies.undying[i] = und
	var mode := dummy_mode_of(role)
	var roam: bool = Settings.dummy_patrol and (role == "melee" or role == "ranged")
	enemies.set_dummy_mode(i, mode, roam, float(rec.get("dir", 1.0)) if fresh else 0.0)
	enemies.dmg[i] = float(def.ranged.get("damage", def.damage)) if mode == EnemyManager.DUMMY_RANGED else def.damage


## The health a dummy of `role` stands up with (pass 49): the field's from arena_dummies, the Elite's, the Boss's and the
## attackers' from the arena's settings; 0 = undying.
func dummy_hp_of(role: String) -> int:
	match role:
		"elite":
			return Settings.elite_dummy_hp
		"boss":
			return Settings.boss_dummy_hp
		"melee", "ranged":
			return Settings.attacker_dummy_hp
	return _dummy_hp


## The behaviour a dummy of `role` has (pass 49, EnemyManager.DUMMY_*): the field stands or patrols (Settings.dummy_patrol),
## the Elite and the Boss do as their settings say, an attacker is melee or ranged by its kind.
func dummy_mode_of(role: String) -> int:
	match role:
		"elite":
			return int(DUMMY_MODE_CODES.get(Settings.elite_dummy_mode, EnemyManager.DUMMY_STAND))
		"boss":
			return int(DUMMY_MODE_CODES.get(Settings.boss_dummy_mode, EnemyManager.DUMMY_STAND))
		"melee":
			return EnemyManager.DUMMY_MELEE
		"ranged":
			return EnemyManager.DUMMY_RANGED
	return EnemyManager.DUMMY_PATROL if Settings.dummy_patrol else EnemyManager.DUMMY_STAND


## The arena's dummy settings changed (pass 49, the WORLD tab): the patrol, the attackers' health and the Elite's and the
## Boss's health and behaviour reach the dummies standing at once (one that has fallen takes them as it stands up); the
## field's health and count wait for RESET DUMMIES (arena_dummies). The first attacking one turns god mode off.
func apply_dummy_settings() -> void:
	for rec in _dummies + _attackers:
		_dress_dummy(rec)
	_check_attackers()


## One more attacking dummy (pass 49, the WORLD tab's + MELEE DUMMY and + RANGED DUMMY): `kind` "melee" (chases the hero
## near its spot and bites) or "ranged" (spits like the Spit Cactus), on a spot of its own by the hero (_attacker_spot).
## The field is left as it is; the first attacker turns god mode off. The creature's index, -1 when none could stand.
func add_attacker(kind: String) -> int:
	var id := str(ATTACKER_IDS.get(kind, ""))
	if id == "" or enemies == null or Registry.enemy(id) == null:
		return -1
	_watch_dummies()
	var rec := {"at": _attacker_spot(), "i": -1, "serial": -1, "dead_t": -1.0, "id": id, "role": kind, "dir": 1.0}
	_attackers.append(rec)
	_stand_dummy(rec)
	_check_attackers()
	return int(rec["i"])


## Where the next attacker stands (pass 49): ATTACKER_RING m from the hero, tried from due south (the field stands north)
## outwards to either side, a step apart that keeps neighbours ATTACKER_GAP apart, to ATTACKER_ARC degrees, then on rings
## 2.5 m wider; the first spot at least ATTACKER_GAP from every other attacker's and clear of the field's rows, the Elite
## and the Boss with their patrol beats. The first three land on a phone's screen with the hero at the spawn.
func _attacker_spot() -> Vector3:
	var base: Vector3 = player.global_position if player else Vector3.ZERO
	for ring in range(4):
		var r := ATTACKER_RING + 2.5 * float(ring)
		var step := 1.1 * 2.0 * asin(minf(ATTACKER_GAP / (2.0 * r), 1.0))
		var k := 0
		while true:
			# due south, then a step to the east, a step to the west, two steps to the east ...
			var a := step * ceilf(float(k) * 0.5) * (1.0 if k % 2 == 1 else -1.0)
			if absf(a) > deg_to_rad(ATTACKER_ARC):
				break
			var at := _dummy_ground(base + Vector3(sin(a), 0.0, cos(a)) * r)
			if _attacker_spot_free(at):
				return at
			k += 1
	return _dummy_ground(base + Vector3(0.0, 0.0, ATTACKER_RING))


func _attacker_spot_free(at: Vector3) -> bool:
	for rec in _attackers:
		var s: Vector3 = rec["at"]
		if Vector2(s.x - at.x, s.z - at.z).length() < ATTACKER_GAP:
			return false
	for rec in _dummies:
		var s2: Vector3 = rec["at"]
		if absf(s2.z - at.z) < ATTACKER_GAP and absf(s2.x - at.x) < EnemyManager.DUMMY_BEAT + ATTACKER_GAP:
			return false
	return true


## How many attacking dummies the layout has (pass 49): the attackers (standing, or about to stand up again), and the
## Elite and the Boss while their behaviour is melee or ranged.
func attackers_on_field() -> int:
	var n := _attackers.size()
	for rec in _dummies:
		var m := dummy_mode_of(str(rec.get("role", "field")))
		if m == EnemyManager.DUMMY_MELEE or m == EnemyManager.DUMMY_RANGED:
			n += 1
	return n


## God mode goes off when the first attacking dummy comes on the field (pass 49, Garry: they "take away HP"), and a toast
## says so; the HERO tab shows it and turns it on again. More attackers after the first leave his choice alone.
func _check_attackers() -> void:
	var now := attackers_on_field() > 0
	if now and not _attacking and player and player.god:
		player.god = false
		if hud:
			hud.toast("GOD MODE OFF: the dummies hit back", UiKit.DANGER)
	_attacking = now


## A creature went down: a dummy of the layout or an attacker stands up again DUMMY_BACK seconds later.
func _on_creature_dying(i: int, _weapon_id: String) -> void:
	for rec in _dummies + _attackers:
		if int(rec["i"]) == i and enemies.serial[i] == int(rec["serial"]):
			rec["dead_t"] = DUMMY_BACK
			return


## The field was cleared without a fight (the arena's CLEAR): the dummies stay away until the next reset, the attackers
## until more are added.
func _on_field_cleared() -> void:
	_dummies.clear()
	_attackers.clear()
	_attacking = false


func _tick_dummies(delta: float) -> void:
	for rec in _dummies + _attackers:
		if float(rec["dead_t"]) >= 0.0:
			rec["dead_t"] = float(rec["dead_t"]) - delta
			if float(rec["dead_t"]) < 0.0:
				_stand_dummy(rec)


## Out of the arena, back to the title, the save as it was (kills, chests, gold and unlocks from the arena all go).
func leave_arena() -> void:
	if _ended:
		return
	_ended = true
	Engine.time_scale = 1.0
	tether_end()
	director.stop()
	Save.end_sandbox()
	Run.end()
	Run.arena = false
	Audio.stop_music()
	set_paused(false)
	UiFx.go(get_tree(), "res://ui/TitleScreen.tscn")


# ---------------------------------------------------------------- the spawn beam (pass 45)

## The landing: a beam of light stands on the spot alone for half a second, the hero comes down it white-hot over a
## second and a half, lands in a ring of dust, the HUD fades in and the clock starts. The tree is not paused (the
## tweens and the warm-up run under it); the stick is locked through `player.input.ui_blocking` and `Player.cinematic`,
## and the camera sits on an anchor at the landing spot, not on the hero 12 m up. Tools get the instant start unless their
## launch file says "spawn": true.
## Pass 64 (Garry: "the hero descending from the sky look janky ... facing us when coming down, but then immediately
## switches back when they land ... a jerky effect ... if the player tries to move or press anything while the sequence
## is happening, it will jerk to the end ... let's try to speed up the sequence"): he faces the camera all the way down
## and after landing until he first moves (Player.face_camera); he comes down on the sand itself (the start spot sat half
## a metre up and he dropped it under gravity, stretched, after the beam let go) on a smootherstep, so he arrives with no
## speed and no acceleration; he touches down with a soft squash (Player.land_settle), a small shake and no blinking; a
## press, a drag or a key after SPAWN_HURRY_AFTER no longer lands him at once but runs the rest of the sequence
## SPAWN_HURRY times as fast (the same easing; the settle after it too), and a finger still down when he lands becomes
## the stick, so the player who tried to move walks off at once.
const SPAWN_HEIGHT := 12.0
const SPAWN_HOLD := 0.5         # the beam alone
const SPAWN_FALL := 1.5         # the descent
const SPAWN_SETTLE := 1.0       # dust settling, the HUD fading in, then the zoom handed back to the camera
const SPAWN_HURRY_AFTER := 0.2  # input before this is the tap that started the run, not a hurry
const SPAWN_HURRY := 3.0        # how much faster the rest of the sequence runs once the player presses or moves
const SPAWN_HURRY_RAMP := 14.0  # the speed-up eases in (rate per second), so the fall quickens rather than jumps
const SPAWN_SQUASH := 0.45      # the landing's squash and spring back, seconds
const SPAWN_LAND_SHAKE := 0.3   # the touchdown's camera shake (1.2 before pass 64 read as a jolt)
const SPAWN_FLASH := 0.35       # how lit the hero is at the top of the beam (1 = white: he vanished in the beam)
const SPAWN_BEAM_BACK := 2.2    # metres the beam stands behind him as the camera sees it (his sprite leans back towards the camera: its top passes 1.7 m back)
var spawning := false
var _spawn_t := 0.0
var _spawn_land := Vector3.ZERO
var _spawn_anchor: Node3D
var _spawn_beam: Node3D
var _spawn_quads: Array = []    # the shine quads (MeshInstance3D): two beams and the pool
var _spawn_spark_t := 0.0
## how fast the sequence runs (1, or SPAWN_HURRY once the player pressed or moved) and the finger held down meanwhile
## (its index, where it went down, where it is now; -1 when none), handed to the stick at the landing
var spawn_rate := 1.0
var _spawn_speed := 1.0         # the rate the clock runs at now, easing towards spawn_rate
var _spawn_touch := -1
var _spawn_touch_from := Vector2.ZERO
var _spawn_touch_at := Vector2.ZERO


func _spawn_begin() -> void:
	_spawn_land = player.global_position
	# on the sand itself: the start spot stands above it, and a hero let go there fell the rest under gravity
	if map and map.has_method("height_at"):
		_spawn_land.y = map.height_at(_spawn_land.x, _spawn_land.z)
	spawn_rate = 1.0
	_spawn_speed = 1.0
	_spawn_touch = -1
	# the warm-up first: its pit is eight metres under wherever the hero stands now
	Warmup.run(self)
	Audio.set_listener(_spawn_land)
	player.input.ui_blocking = true
	player.input.force_release()
	player.cinematic = true
	player.invuln = 0.0
	_spawn_anchor = Node3D.new()
	world.add_child(_spawn_anchor)
	_spawn_anchor.global_position = _spawn_land
	camera.snap_to(_spawn_anchor)
	camera.zoom_override = 1.6
	player.global_position = _spawn_land + Vector3(0, SPAWN_HEIGHT, 0)
	player.visible = false
	player.shadow.visible = false
	# lit but in colour: a white-hot hero inside the white beam read as nothing at all (pass 45 capture)
	player.sprite.set_flash(SPAWN_FLASH)
	player.face_camera()
	# the behaviours tick on game.paused alone: held off, or the saws would orbit 12 m up
	weapon_host.visible = false
	weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	hud.modulate.a = 0.0
	_spawn_beam = Node3D.new()
	world.add_child(_spawn_beam)
	_spawn_beam.global_position = _spawn_land - Vector3(0, 0.45, 0)
	_spawn_quads = [
		Chest.shine_quad(1, Vector2(2.6, 34.0), Color(1.0, 0.9, 0.55), 0.0),
		Chest.shine_quad(1, Vector2(0.9, 34.0), Color(1.0, 1.0, 0.9), 0.0),
		Chest.shine_quad(2, Vector2(5.2, 5.2), Color(1.0, 0.85, 0.45), 0.0)]
	var strengths: Array = [1.1, 1.5, 0.8]
	# the beam stands a step behind the hero as the camera sees it and draws before him, so its glow lights the sand
	# round him instead of washing him out (additive quads drawn over the hero turned him into a white silhouette)
	var away := Vector3(0, 0, -1)
	if camera:
		away = -camera.global_transform.basis.z
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.0001 else Vector3(0, 0, -1)
	for k in _spawn_quads.size():
		var q: MeshInstance3D = _spawn_quads[k]
		_spawn_beam.add_child(q)
		(q.material_override as ShaderMaterial).render_priority = -10
		if k < 2:
			q.position = away * SPAWN_BEAM_BACK
			_spawn_beam_fade(q, away)
		create_tween().tween_method(func(v: float): _spawn_strength(q, v), 0.0, float(strengths[k]), 0.25)
	camera.shake(0.35)
	Audio.play("pl_spawn_beam", _spawn_land)
	spawning = true
	_spawn_t = 0.0
	_spawn_spark_t = 0.0


func _spawn_strength(q: MeshInstance3D, v: float) -> void:
	if is_instance_valid(q):
		(q.material_override as ShaderMaterial).set_shader_parameter("strength", v)


## Pass 69 (lane EN; Garry: "The beam of light that accompanies Player hero when they descend down gets cut off at the
## bottom ... just fade out the effect before it reaches the ground"): a beam quad's light fades in from nothing
## SPAWN_BEAM_FADE_GAP above the highest sand under its width to whole SPAWN_BEAM_FADE higher (shine_aura.gdshader's
## fade_y), so its bright foot never meets the sand (or floats over a dip) in a hard line. `away` is the camera's flat
## forward, the beam's width runs across it.
const SPAWN_BEAM_FADE_GAP := 0.15
const SPAWN_BEAM_FADE := 2.6
func _spawn_beam_fade(q: MeshInstance3D, away: Vector3) -> void:
	var base := q.global_position
	var top := base.y
	if map and map.has_method("height_at"):
		var across := Vector3(-away.z, 0.0, away.x)
		var half: float = (q.mesh as QuadMesh).size.x * 0.5 if q.mesh is QuadMesh else 1.3
		top = -INF
		for s: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var p := base + across * (half * s)
			top = maxf(top, float(map.height_at(p.x, p.z)))
		# the quad's own foot when the sand lies under it (a dip behind the hero)
		top = maxf(top, base.y)
	(q.material_override as ShaderMaterial).set_shader_parameter("fade_y", spawn_beam_fade_y(top))


## The world heights the spawn beam fades over above sand whose highest point under it is `ground_top` (pass 69).
static func spawn_beam_fade_y(ground_top: float) -> Vector2:
	return Vector2(ground_top + SPAWN_BEAM_FADE_GAP, ground_top + SPAWN_BEAM_FADE_GAP + SPAWN_BEAM_FADE)


func _tick_spawn(delta: float) -> void:
	_spawn_speed = move_toward(_spawn_speed, spawn_rate, delta * SPAWN_HURRY_RAMP)
	_spawn_t += delta * _spawn_speed
	_spawn_spark_t -= delta
	if _spawn_spark_t <= 0.0:
		_spawn_spark_t = 0.04
		fx.mote(_spawn_land + Vector3(randf_range(-0.9, 0.9), randf_range(0.2, 6.0), randf_range(-0.9, 0.9)), Vector3(0, 2.5, 0), 0.6, 0.14, Color(1.0, 0.95, 0.7, 0.9))
	if _spawn_t < SPAWN_HOLD:
		return
	var f := clampf((_spawn_t - SPAWN_HOLD) / SPAWN_FALL, 0.0, 1.0)
	var e := spawn_ease(f)
	player.visible = true
	player.global_position = _spawn_land + Vector3(0, SPAWN_HEIGHT * (1.0 - e), 0)
	player.sprite.set_flash(SPAWN_FLASH * (1.0 - e))
	player.sprite.set_squash(1.0 - 0.12 * (1.0 - e), 1.0 + 0.3 * (1.0 - e))
	# the core eases as he comes down, so the landing reads against it
	if _spawn_quads.size() > 1:
		_spawn_strength(_spawn_quads[1], lerpf(1.5, 0.8, e))
	camera.zoom_override = lerpf(1.6, 1.0, e)
	if f >= 1.0:
		_spawn_land_now()


## The fall's curve (pass 64): smootherstep, so he leaves the top and reaches the sand with no speed and no acceleration.
static func spawn_ease(f: float) -> float:
	var x := clampf(f, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## The player pressed, dragged or hit a key during the sequence (pass 64): the rest runs SPAWN_HURRY times as fast.
func spawn_hurry() -> void:
	if spawning and _spawn_t >= SPAWN_HURRY_AFTER:
		spawn_rate = SPAWN_HURRY


func _spawn_land_now() -> void:
	spawning = false
	player.global_position = _spawn_land
	player.velocity = Vector3.ZERO
	player.visible = true
	player.sprite.set_flash(0.0)
	player.sprite.set_squash(1.0, 1.0)
	player.shadow.visible = true
	player.cinematic = false
	player.input.ui_blocking = false
	player.face_camera()
	player.land_settle(SPAWN_SQUASH / spawn_rate)
	player.invuln = 1.0
	player.quiet_invuln = true
	telegraphs.flash_ring(_spawn_land, 2.8, Color(1.0, 0.9, 0.6), 0.5)
	fx.burst(_spawn_land + Vector3(0, 0.9, 0), Color(1.0, 0.95, 0.75), 1.4)
	for k in 5:
		var a := TAU * float(k) / 5.0
		fx.sand(_spawn_land + Vector3(cos(a) * 0.9, 0.1, sin(a) * 0.9), 1.4)
	camera.shake(SPAWN_LAND_SHAKE)
	hud.flash(Color(1.0, 0.95, 0.8, 0.2), 0.35)
	Audio.play("pl_spawn_land", _spawn_land)
	# the beam goes out, the pool last
	var beam: Node3D = _spawn_beam
	var tw := create_tween().set_parallel(true)
	for k in _spawn_quads.size():
		var q: MeshInstance3D = _spawn_quads[k]
		var from: float = (q.material_override as ShaderMaterial).get_shader_parameter("strength")
		tw.tween_method(func(v: float): _spawn_strength(q, v), from, 0.0, 0.8 if k == 2 else 0.45)
	tw.chain().tween_callback(beam.queue_free)
	_spawn_quads = []
	_spawn_beam = null
	weapon_host.visible = true
	weapon_host.process_mode = Node.PROCESS_MODE_INHERIT
	# the anchor sits on his feet, so the camera hands over without a jump; the zoom goes back to the camera's own after
	# the dust settles
	camera.zoom_override = 1.0
	camera.target = player
	_spawn_anchor.queue_free()
	_spawn_anchor = null
	create_tween().tween_property(hud, "modulate:a", 1.0, 0.6 / spawn_rate)
	create_tween().tween_callback(func(): camera.zoom_override = 0.0).set_delay(SPAWN_SETTLE / spawn_rate)
	_spawn_hand_over_finger()
	_start_run()


## A finger that went down during the sequence and is still down becomes the stick (pass 64): he walks off at once.
func _spawn_hand_over_finger() -> void:
	var inp = player.input
	if _spawn_touch < 0 or inp == null or int(inp.active_index) != -1 or not inp._in_thumb_zone(_spawn_touch_from):
		_spawn_touch = -1
		return
	inp.active_index = _spawn_touch
	inp.origin = _spawn_touch_from
	inp.touch_pos = _spawn_touch_at
	inp.wants_move = true
	inp.touch_started.emit(_spawn_touch_from)
	_spawn_touch = -1


# ---------------------------------------------------------------- pause

func set_paused(v: bool) -> void:
	paused = v
	get_tree().paused = v
	Perf.pause()
	if player:
		player.input.ui_blocking = v
		if v:
			player.input.force_release()


func open_pause() -> void:
	if paused or _ended or spawning:
		return
	set_paused(true)
	Audio.play("ui_pause")
	pause_screen.open()


func close_pause() -> void:
	pause_screen.close()
	Audio.play("ui_resume")
	set_paused(false)
	# a screen asked for while the menu was up (pass 60) comes now
	if not _modal_queue.is_empty():
		_open_next_modal_soon(MODAL_BEAT)


# ---------------------------------------------------------------- one screen at a time (pass 60)

## THE RULE (pass 60, Garry: "sometimes I can get both a level up and die. This shouldn't happen ... Some way by which
## we will never run into this situation again"): one screen at a time, and death wins.
## - Every screen that pauses the run (the level-up cards, a mutation offer, a chest's reel, the stage-clear dialog,
##   Down!, the shop, the Stranger) is asked for through _request_modal(kind, opener). One is up at a time (_modal); the
##   rest wait in _modal_queue by priority (Down! > the portal > a boss's chest > a chest > the level cards > a path
##   offer > the shop and the Stranger), oldest first within a priority. When the one up closes, _modal_done() opens the
##   next after a beat, or hands the run back once the queue is empty: through the gate (TAP TO GO, the pick flying to
##   its slot) or straight (_resume_run), with a second of blinking grace either way.
## - Death wins: while the hero is down (player.dead) only Down! may open. A level-up that comes meanwhile is BANKED
##   (_pending_levels counts it; one CARDS request waits for the bank), a chest or a path offer waits in the queue, and
##   they all come one after another once he is up (_revive, REVIVE_BEAT after his blast); staying down (end_run) drops
##   the queue.
## - Nothing hurts the hero while a screen is up: every timer that can land a hit on him (a body going off in
##   elite_explosion, the Down! wait itself) is pause-respecting (create_timer(..., false)), so it waits while the run
##   is paused behind a screen and looks again when it wakes. The pause menu and the gate count as screens here: a
##   request made while one is up waits for close_pause / the tap.
## - A tool or a test that opens a screen by hand (chest_screen.open, cards.show_offer, set_paused) stands outside the
##   rule, as before; the openers mark _modal themselves, so a direct _show_next_level_cards still holds the turn.
##   With Settings.debug_mode on, _check_one_modal prints an error the frame two of these screens are visible.
## pass 73 (lane STRUCT): TOTEM, the Totem Pole's gifts, waits with the shop and the Stranger
enum Modal {NONE, CARDS, PATH, CHEST, PORTAL, REVIVE, SHOP, STRANGER, TOTEM}
const MODAL_PRIORITY := {Modal.REVIVE: 70, Modal.PORTAL: 60, Modal.CHEST: 40, Modal.CARDS: 30, Modal.PATH: 20, Modal.SHOP: 10, Modal.STRANGER: 10, Modal.TOTEM: 10}
## a boss's chest goes before an ordinary one that fell beside it
const BOSS_CHEST_BUMP := 5
## the beat between one screen closing and the next opening (the run paused meanwhile), and the longer one after the
## hero gets up, so his blast reads before the banked screens come
const MODAL_BEAT := 0.2
const REVIVE_BEAT := 0.6
var _modal: Modal = Modal.NONE
## [{kind, priority, seq, opener}], highest priority first, then oldest first
var _modal_queue: Array = []
var _modal_seq := 0
var _modal_next_pending := false
var _two_modals_said := ""


## Asks for a screen. It opens now (the run pauses) when nothing holds the run and the hero stands; else it waits its
## turn. `opener` opens the screen; it may return false when it had nothing to show, and the turn passes on. `bump`
## lifts its priority (a boss's chest); `dedupe` keeps one request of the kind in the queue (the level cards: the bank
## _pending_levels says how many, one request drains it).
func _request_modal(kind: Modal, opener: Callable, bump: int = 0, dedupe: bool = false) -> void:
	if _ended:
		return
	if dedupe:
		for r: Dictionary in _modal_queue:
			if int(r["kind"]) == kind:
				return
	var down: bool = player != null and player.dead
	# a waiting queue (or a hand-over beat) means the newcomer takes its place in line, never the front (the review:
	# a chest touched in the revive beat had opened before the banked cards)
	if _modal_busy() or (down and kind != Modal.REVIVE) or not _modal_queue.is_empty() or _modal_next_pending:
		_modal_seq += 1
		_modal_queue.append({"kind": kind, "priority": int(MODAL_PRIORITY.get(kind, 0)) + bump, "seq": _modal_seq, "opener": opener})
		_modal_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["priority"]) != int(b["priority"]):
				return int(a["priority"]) > int(b["priority"])
			return int(a["seq"]) < int(b["seq"]))
		if not _modal_busy() and not _modal_next_pending:
			_open_next_modal()
		return
	_open_modal(kind, opener)


func _open_modal(kind: Modal, opener: Callable) -> void:
	_modal = kind
	# the opener pauses when it shows something: pausing here first had dropped the thumb (PlayerInput.force_release)
	# for a slot that had nothing to offer
	var r = opener.call()
	if r is bool and not r:
		if paused:
			# between screens (the hand-over left the run paused): the next, or the run goes on
			_modal_done({}, false)
		else:
			# nothing to show, from the running game: the turn passes on and the run is not touched
			_modal = Modal.NONE
			if not _modal_queue.is_empty():
				_open_next_modal_soon(MODAL_BEAT)


## Whether a screen, the gate or the pause menu holds the run now.
func _modal_busy() -> bool:
	if _modal != Modal.NONE:
		return true
	if resume_gate != null and resume_gate.visible:
		return true
	return pause_screen != null and pause_screen.visible


## The screen up has closed: the next in line opens after a beat, or the run goes on, through the gate (`pick` flies to
## its slot) or straight (`through_gate` false). With the hero down only Down! may come next; anything else waits for
## him to get up, and the run runs on so his fall plays out and Down! can come (its wait is pause-respecting).
func _modal_done(pick: Dictionary = {}, through_gate: bool = true) -> void:
	_modal = Modal.NONE
	if _ended:
		return
	var down: bool = player != null and player.dead
	if not _modal_queue.is_empty() and (not down or int(_modal_queue[0]["kind"]) == Modal.REVIVE):
		_open_next_modal_soon(MODAL_BEAT)
		return
	if down:
		set_paused(false)
		return
	if through_gate:
		resume_gate.open(pick)
	else:
		_resume_run()


## The run goes on without the gate: unpaused, a second of blinking grace (a pick is never claimed straight into a
## bite), and the next request if one waits.
func _resume_run() -> void:
	set_paused(false)
	if player and not player.dead:
		player.invuln = maxf(player.invuln, 1.0)
	if not _modal_queue.is_empty():
		_open_next_modal_soon(MODAL_BEAT)


## The gate's tap (TAP TO GO): the run goes on, and the next screen in line (a path offer that came due behind the
## cards) follows after a beat.
func _after_gate() -> void:
	_resume_run()


## The next request opens after `beat` seconds on the real clock (the run may be paused while the screens change hands);
## one such beat at a time.
func _open_next_modal_soon(beat: float) -> void:
	if _modal_next_pending:
		return
	_modal_next_pending = true
	get_tree().create_timer(beat).timeout.connect(func() -> void:
		_modal_next_pending = false
		_open_next_modal())


func _open_next_modal() -> void:
	if _ended or _modal_queue.is_empty() or _modal_busy():
		return
	var down: bool = player != null and player.dead
	if down and int(_modal_queue[0]["kind"]) != Modal.REVIVE:
		return
	var r: Dictionary = _modal_queue.pop_front()
	_open_modal(r["kind"], r["opener"])


## The screens the rule covers that are visible now, by name (tests, the debug watch). WConfirm's question over one of
## them is not a second screen.
func visible_modals() -> Array:
	var out: Array = []
	for pair in [["cards", cards], ["chest", chest_screen], ["portal", portal_dialog], ["revive", revive_screen],
			["shop", structure_shop], ["stranger", stranger_screen], ["totem", totem_screen], ["pause", pause_screen]]:
		var n = pair[1]
		if n != null and is_instance_valid(n) and (n as CanvasItem).visible:
			out.append(pair[0])
	return out


## The queue as kinds, oldest-first within priorities (tests, tools).
func modal_queue_kinds() -> Array:
	var out: Array = []
	for r: Dictionary in _modal_queue:
		out.append(int(r["kind"]))
	return out


func current_modal() -> int:
	return _modal


## A tool's or a test's hand on the screens (touch_audit closes a reel by setting it invisible, wanted_shots opens them
## by hand): the turn and the queue are forgotten, so the next request opens at once; nothing is unpaused here.
func modal_reset() -> void:
	_modal = Modal.NONE
	_modal_queue.clear()


func _check_one_modal() -> void:
	if _ended or not Settings.debug_mode:
		return
	var vis := visible_modals()
	if vis.size() > 1:
		var key := ",".join(vis)
		if key != _two_modals_said:
			_two_modals_said = key
			push_error("two screens up at once: %s (Game's one-screen rule, pass 60)" % key)
	else:
		_two_modals_said = ""


func _unhandled_input(event: InputEvent) -> void:
	if spawning:
		# a press, a drag or a key speeds the rest of the sequence up (pass 64; it used to land him at once); a finger
		# still down at the landing becomes the stick (_spawn_hand_over_finger)
		if event is InputEventScreenTouch:
			if event.pressed:
				_spawn_touch = event.index
				_spawn_touch_from = event.position
				_spawn_touch_at = event.position
				spawn_hurry()
			elif event.index == _spawn_touch:
				_spawn_touch = -1
		elif event is InputEventScreenDrag:
			if event.index == _spawn_touch:
				_spawn_touch_at = event.position
			spawn_hurry()
		elif event.is_pressed() and (event is InputEventMouseButton or event is InputEventKey):
			spawn_hurry()
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if structure_shop and structure_shop.visible:
				structure_shop._finish(false)
			elif pause_screen.visible:
				# the abandon question first (pass 45), then the pause itself
				if not WConfirm.dismiss(pause_screen):
					close_pause()
			elif not cards.visible and not portal_dialog.visible:
				open_pause()
		elif event.keycode == KEY_F1:
			debug_panel.toggle()


func _notification(what: int) -> void:
	# the app really left the screen (a call, the home button): the run waits behind the pause menu
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_log_pause("the app went to the background")
		if RunAnalytics.I and _run_started and not _ended: RunAnalytics.I.checkpoint()
		# the run's tallies reach the disk before Android may kill the backgrounded app (Save flushes on its own too)
		Save.flush()
		if _run_started and not paused and not _ended:
			open_pause()
	# Android's back gesture is a swipe in from a side edge, and a thumb steering near the edge makes one by accident:
	# in a run it does nothing (the pause button is on the screen), it is only logged (pass 33.1: the random pauses)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_log_pause("back gesture, ignored")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_log_pause("the phone took focus, ignored")


## A line in user://pauses.txt for each system event that paused the run or could have (Settings shows the last six),
## so a pause nobody asked for can be traced from the phone.
func _log_pause(reason: String) -> void:
	if not _run_started or _ended:
		return
	var lines: Array = []
	if FileAccess.file_exists("user://pauses.txt"):
		var r := FileAccess.open("user://pauses.txt", FileAccess.READ)
		if r:
			lines = Array(r.get_as_text().strip_edges().split("\n", false))
			r.close()
	lines.append("%s · %s" % [TextGen.time_mmss(Run.elapsed), reason])
	while lines.size() > 6:
		lines.pop_front()
	var w := FileAccess.open("user://pauses.txt", FileAccess.WRITE)
	if w:
		w.store_string("\n".join(lines))
		w.close()


# ---------------------------------------------------------------- weapons

## A level's signature stat rebuilt the hero's sheet alone (pass 61, Run.add_xp): his health and speed follow at once.
func _on_hero_sheet_changed() -> void:
	if player:
		player.refresh_stats()


func _sync_weapons() -> void:
	var t0 := Time.get_ticks_usec()
	for w in Run.weapons:
		var id: String = w.def.id
		if _behaviors.has(id):
			var b: WeaponBehavior = _behaviors[id]
			# a mutation that swaps the behaviour (Needle Rain, Homing Skulls, Walking Buddy) rebuilds it; so does a family
			# look changed under it (pass 76, lane LOOKS: the arena's chips; its visual and model are the look's)
			if b.get_script() == _behavior_script(w.behavior()) and not b.look_stale():
				b.inst = w
				b.refresh_marks()
				continue
			b.queue_free()
			_behaviors.erase(id)
		var b := _make_behavior(w.behavior())
		if b == null:
			continue
		weapon_host.add_child(b)
		b.setup(w, self)
		_behaviors[id] = b
	# remove behaviours for weapons no longer held (evolution replaced them)
	for id in _behaviors.keys():
		if not Run.has_weapon(id):
			_behaviors[id].queue_free()
			_behaviors.erase(id)
	if player:
		player.refresh_stats()
	Perf.add("sync_weapons", t0)


func _behavior_script(name: String) -> Script:
	var b := _make_behavior(name)
	if b == null:
		return null
	var s: Script = b.get_script()
	b.free()
	return s


func _make_behavior(name: String) -> WeaponBehavior:
	match name:
		"ProjectileEmitter":
			return ProjectileEmitter.new()
		"Orbiter":
			return Orbiter.new()
		"Lobber":
			return Lobber.new()
		"LaserBeam":
			return LaserBeam.new()
		"Beam":
			return Beam.new()
		"Spawner":
			return Spawner.new()
		"MineLayer":
			return MineLayer.new()
		"MissilePod":
			return MissilePod.new()
		"Thruster":
			return Thruster.new()
		"Smasher":
			return Smasher.new()
		"GravityGun":
			return GravityGun.new()
		"ConeWave":
			return ConeWave.new()
		"SunScepter":
			# pass 54: Solenne's Sun Scepter and Zenith, pillars of sunlight on what she can see
			return preload("res://core/behaviors/SunScepter.gd").new()
		"Frisbee":
			# pass 69: the Frisbee, a disc in a curving arc through everything (lane FRIS)
			return preload("res://core/behaviors/Frisbee.gd").new()
		"SaltShaker":
			# pass 69: the Salt, patches of salt laid in the hero's wake (lane SALT)
			return preload("res://core/behaviors/SaltShaker.gd").new()
	push_warning("Unknown weapon behaviour: " + name)
	return null


## The basketball is back in his hand (pass 67): ProjectileManager calls this when a shot of a weapon with
## `params.catch` reaches him on its way home, with the shot's extra (its "hits" this trip). The weapon's behaviour
## takes the catch (ProjectileEmitter.on_caught: the cooldown refund, Heat, Slam Dunk's dunk); a ball thrown before its
## weapon evolved finds no behaviour and simply ends.
func ball_caught(w: WeaponInstance, ex: Dictionary) -> void:
	if w == null or w.def == null:
		return
	var b = _behaviors.get(w.def.id)
	if b != null and is_instance_valid(b) and b.has_method("on_caught"):
		b.on_caught(ex)


## Tells every held weapon's behaviour that has `method` (pass 67: on_hero_hit when a hit reaches his health,
## on_hero_evaded when he evades one: the basketball's Heat and Free Throw); the others never need to know.
func _tell_behaviors(method: String) -> void:
	for b in _behaviors.values():
		if is_instance_valid(b) and b.has_method(method):
			b.call(method)


func _on_evolved(id: String) -> void:
	var def := Registry.weapon(id)
	Audio.play("w_evo_reveal")
	hud.banner("EVOLVED · " + (def.display_name if def else id).to_upper(), UiKit.TYPE_COLORS["evolution"], def.icon if def else null)
	camera.shake(1.2)


# ---------------------------------------------------------------- run flow

func _process(delta: float) -> void:
	if spawning:
		_tick_spawn(delta)
		return
	if paused or _ended or not _run_started:
		return
	Audio.set_listener(player.global_position)
	if not player.input.lifted_once:
		Run.no_lift_time = Run.elapsed
	if portal and is_instance_valid(portal):
		portal.check_player(player)
	Run.alive = enemies.alive_count()
	if RunAnalytics.I: RunAnalytics.I.tick(delta)
	Run.timeline.tick(delta)
	for label in Run.tick_timed():
		hud.toast("%s wore off" % label, UiKit.INK3)
	_tick_perks(delta)
	_tick_tether(delta)
	_tick_breadcrumb(delta)
	_drape_hero_shadow()
	_tick_water(delta)
	_tick_berserk(delta)
	_tick_hero_fx(delta)
	_tick_hell(delta)
	if not _dummies.is_empty() or not _attackers.is_empty():
		_tick_dummies(delta)
	var t0 := Time.get_ticks_usec()
	# pass 77 (lane SIMRUN): the run sim's fast mode draws no HUD and shows no hints
	if not Run.sim_mode:
		hud.tick(delta)
		hints.tick(delta)
	Perf.add("hud", t0)
	Perf.frame()
	if int(Run.elapsed) % 5 == 0 and int(Run.elapsed * 10.0) % 50 == 0:
		_check_quests()


var _last_quest_check := -1
func _check_quests() -> void:
	if Run.arena:
		return
	var s := int(Run.elapsed)
	if s == _last_quest_check:
		return
	_last_quest_check = s
	for id in QuestTracker.check_all(true):
		var q: QuestDef = Registry.quests[id]
		if RunAnalytics.I: RunAnalytics.I.event("unlock", str(id))
		# the banner carries the item's own icon (pass 44), so the unlock is seen, not only read; a hero's badge is the
		# one of the look he is played in (pass 68, unlock_banner_def)
		var def: ContentDef = unlock_banner_def(q)
		# pass 69: a hero on sale is not his yet: the banner says so and keeps him unknown; pass 76: only while he is on
		# sale (Registry.hero_state; check_all never returns a hero owned already)
		if def is CharacterDef and Registry.hero_state(def as CharacterDef) == "buyable":
			hud.banner("A NEW HERO IS FOR SALE", UiKit.GOOD, null)
		else:
			hud.banner("UNLOCKED: " + (def.display_name if def else q.display_name), UiKit.GOOD, def.icon if def else null)
		Audio.play("ui_unlock")


## What the run's UNLOCKED banner for quest `q` draws: the item it opens, with its own icon (pass 44), a hero in the look
## he is played in (pass 68, Registry.art_of); null when it opens nothing the Registry has (the banner names the quest).
static func unlock_banner_def(q: QuestDef) -> ContentDef:
	return Registry.art_of(Registry.unlocked_by(q))


var _dust_t := 0.0


var _supply_t := -1.0
var _thrust_cd := 0.0
var _noon_t := -1.0
var _noon_left := 0.0
var _bounty_kills := 0


## The perks that run every frame: the Drifter's Trail Dust and High Noon, Astro's Supply Drop and Thruster Burst
## (pass 34), Fadeaway's Timeout and Buzzer Beater (pass 67), each on its own clock.
func _tick_perks(delta: float) -> void:
	if player == null or player.dead:
		return
	if Run.has_perk("supply_drop"):
		_tick_supply(delta)
	if Run.has_perk("thruster_burst"):
		_tick_thrusters(delta)
	if Run.has_perk("high_noon") or _noon_left > 0.0:
		_tick_high_noon(delta)
	if Run.has_perk("serenade"):
		_tick_serenade(delta)
	# pass 67, Fadeaway: the Timeout that lands beside him on its clock, and every "periodic_buff" perk (Buzzer Beater)
	if Run.has_perk("timeout"):
		_tick_timeout(delta)
	_tick_periodic_buffs(delta)
	# pass 69 (lane HERO): May's Inflatable May (a perk whose special is "decoy")
	_tick_decoy(delta)
	# pass 70 (lane TRAMP): Fadeaway's Hang Time (a perk whose special is "trampoline"; it replaced the Timeout)
	_tick_trampoline(delta)
	if not Run.has_perk("trail_dust"):
		return
	if player.velocity.length() < 0.8:
		return
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = Run.perk_param("trail_dust", "every", 0.22)
		spawn_zone(player.global_position - player.forward() * 0.6, Run.perk_param("trail_dust", "radius", 1.1), Run.perk_param("trail_dust", "seconds", 1.0),
			0.0, 0.3, null, Run.perk_param("trail_dust", "slow", 0.25), Color(0.85, 0.72, 0.5, 0.3))


## Pass 69 (lane HERO): May's Inflatable May, its own node (core/systems/Decoy.gd) made the first time a decoy perk is
## held: the throw, the circle, the fooled creatures and their "?" marks, the pop.
var decoy: Decoy = null


func _tick_decoy(delta: float) -> void:
	if decoy == null:
		if not Decoy.active():
			return
		decoy = Decoy.new()
		decoy.name = "Decoy"
		add_child(decoy)
		decoy.setup(self)
	decoy.tick(delta)


## Pass 70 (lane TRAMP): Hang Time's trampoline, its own node (core/systems/Trampoline.gd, by path so Game never waits on
## the class cache) made the first time a trampoline perk is held: the clock, the drop beside him, the walk-in launch
## (Player.trampoline_launch), the mat's wobble, the fold.
const TRAMPOLINE_SCRIPT := preload("res://core/systems/Trampoline.gd")
var trampoline: Node3D = null


func _tick_trampoline(delta: float) -> void:
	if trampoline == null:
		if not TRAMPOLINE_SCRIPT.active():
			return
		trampoline = TRAMPOLINE_SCRIPT.new()
		trampoline.name = "Trampoline"
		add_child(trampoline)
		trampoline.call("setup", self)
	trampoline.call("tick", delta)


## Serenade (pass 43, Calavera): whatever comes within the song's reach moves slower; a faint gold disc under him says
## how far it carries.
var _serenade_t := 0.0
var _serenade_disc := -1


func _tick_serenade(delta: float) -> void:
	var r := Run.perk_param("serenade", "radius", 4.0)
	var here: Vector3 = player.global_position
	if _serenade_disc < 0:
		_serenade_disc = telegraphs.hold_disc(here, r, Color(1.0, 0.85, 0.4, 0.09))
	telegraphs.move_held(_serenade_disc, Vector3(here.x, map.height_at(here.x, here.z) if map else here.y, here.z))
	_serenade_t -= delta
	if _serenade_t > 0.0:
		return
	_serenade_t = Run.perk_param("serenade", "every", 0.3)
	# a hero's perk: Ducktape (debuff_duration) does not stretch it (pass 47)
	enemies.slow_radius(here, r, Run.perk_param("serenade", "slow", 0.25), _serenade_t + 0.25, false)


## Supply Drop: a red ring on the sand near her, a pod falling into it, a blast that hurts and throws, and a pickup where
## it landed: a heart when she is below `heart_below` (60%) of her health, else one of the perk's `drops` (pass 53: only
## the magnet pulse; Garry: "Supply Drop is insanely powerful, nerf it" and "It feels op, power-ups feel powerful": no
## Berserk, Shield or Sprint from the pod any more, and the blast does half, `damage` 15 + 2 a level).
func _tick_supply(delta: float) -> void:
	if _supply_t < 0.0:
		_supply_t = Run.perk_param("supply_drop", "first", 15.0)
	_supply_t -= delta
	if _supply_t > 0.0:
		return
	_supply_t = Run.perk_param("supply_drop", "every", 40.0)
	var a := randf() * TAU
	var at: Vector3 = player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, 6.0)
	at.y = map.height_at(at.x, at.z) if map else 0.0
	var warn := Run.perk_param("supply_drop", "warn", 1.5)
	var r := Run.perk_param("supply_drop", "radius", 2.6)
	telegraphs.ring(at, r, warn, Color(1.0, 0.22, 0.16))
	hud.toast("SUPPLY DROP", Color(0.55, 0.85, 1.0))
	var pod := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.3
	pod.mesh = cap
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.85, 0.9)
	m.metallic = 0.6
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 0.4
	pod.material_override = m
	add_child(pod)
	pod.global_position = at + Vector3(0, 28.0, 0)
	var tw := create_tween()
	tw.tween_property(pod, "global_position", at + Vector3(0, 0.6, 0), warn).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _supply_land(at, r, pod))


func _supply_land(at: Vector3, r: float, pod: MeshInstance3D) -> void:
	if not is_instance_valid(pod):
		return
	var dmg := Run.perk_param("supply_drop", "damage", 30.0) + Run.perk_param("supply_drop", "damage_per_level", 4.0) * float(Run.card_level())
	enemies.damage_radius(at, r, dmg, "supply_drop", Run.perk_param("supply_drop", "knockback", 14.0))
	fx.explosion(at, 1.4)
	camera.shake(0.6)
	Audio.play("en_rocket_boom", at)
	var id := supply_drop_pick(player.hp if player else 1.0, player.max_hp if player else 1.0)
	var pd: PickupDef = Registry.pickup(id)
	if pd:
		pickups.spawn_special(pd, at)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(pod, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tw.tween_callback(pod.queue_free)


## What the pod leaves (pass 53, data-driven): a heart while the hero's health is under the perk's `heart_below` share of
## her maximum, else one of the perk's `drops` ids at random (supply_drop.json: ["magnet_pulse"]; a perk with no list
## gives the pulse). Static so a test can ask it without a Game.
static func supply_drop_pick(hp: float, max_hp: float) -> String:
	if hp < max_hp * Run.perk_param("supply_drop", "heart_below", 0.6):
		return "heart"
	var drops: Array = []
	for pk in Run.perks:
		var def: PerkDef = Registry.perk(str(pk))
		if def and def.special == "supply_drop" and def.params.get("drops") is Array:
			drops = def.params["drops"]
			break
	if drops.is_empty():
		return "magnet_pulse"
	return str(drops[randi() % drops.size()])


## Thruster Burst: when the crowd closes in, the suit fires her clear towards the emptiest ground and throws the ring.
func _tick_thrusters(delta: float) -> void:
	_thrust_cd = maxf(_thrust_cd - delta, 0.0)
	if _thrust_cd > 0.0:
		return
	var here: Vector3 = player.global_position
	if enemies.indices_in_radius(here, Run.perk_param("thruster_burst", "reach", 2.6)).size() < int(Run.perk_param("thruster_burst", "crowd", 6.0)):
		return
	var best := _emptiest_dir(here, 12)
	# her own thrusters, not a hostile throw: they fire her clear under the Invincibility bubble too (pass 60, lane WP)
	player.blast(best * Run.perk_param("thruster_burst", "push", 28.0), Run.perk_param("thruster_burst", "lift", 5.0), false)
	player.invuln = maxf(player.invuln, Run.perk_param("thruster_burst", "invuln", 0.6))
	enemies.hero_throw_radius(here, Run.perk_param("thruster_burst", "throw_radius", 3.2), Run.perk_param("thruster_burst", "throw", 18.0))
	fx.burst(here + Vector3(0, 0.4, 0), Color(0.55, 0.85, 1.0), 1.4)
	for k in range(6):
		fx.flame(here - best * 0.3 + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)), 0.8, 0.45)
	telegraphs.flash_ring(here, 3.2, Color(0.55, 0.85, 1.0), 0.35)
	camera.shake(0.5)
	Audio.play("pl_jump", here)
	_thrust_cd = Run.perk_param("thruster_burst", "every", 8.0)


## High Noon: every `every` seconds the creatures' clock (and their shots') runs at `slow` for `seconds`.
func _tick_high_noon(delta: float) -> void:
	if _noon_left > 0.0:
		_noon_left -= delta
		if _noon_left <= 0.0:
			enemies.time_scale = 1.0
		return
	if _noon_t < 0.0:
		_noon_t = Run.perk_param("high_noon", "first", 20.0)
	_noon_t -= delta
	if _noon_t > 0.0:
		return
	_noon_t = Run.perk_param("high_noon", "every", 30.0)
	_noon_left = Run.perk_param("high_noon", "seconds", 3.0)
	enemies.time_scale = Run.perk_param("high_noon", "slow", 0.3)
	hud.flash(Color(1.0, 0.78, 0.3, 0.32), _noon_left)
	hud.toast("HIGH NOON", Color(1.0, 0.82, 0.35))
	Audio.play("w_evo_reveal", player.global_position)


## The emptiest of `n` directions round `here` (Thruster Burst's scan, pass 67 factored out for the Timeout's leap): the
## one whose point 5 m out has the fewest creatures within 2.5 m. On a tie the one nearest `prefer` wins (the leap passes
## away from the creatures it leaves, or with none near the way he faces), else the first of them (Thruster Burst).
func _emptiest_dir(here: Vector3, n: int = 12, prefer: Vector3 = Vector3.ZERO) -> Vector3:
	var best := Vector3.FORWARD
	var best_n := 1 << 30
	var best_along := -INF
	var count := maxi(n, 1)
	for k in range(count):
		var ang := TAU * float(k) / float(count)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var c: int = enemies.indices_in_radius(here + dir * 5.0, 2.5).size()
		var along := dir.dot(prefer)
		if c < best_n or (c == best_n and along > best_along):
			best_n = c
			best = dir
			best_along = along
	return best


## Timeout (pass 67, Fadeaway's perk): a Timeout pickup (the perk's `pickup`) lands `side` metres beside him, first after
## `first` seconds, then `every` seconds after the last one was taken or faded: one lies at a time and the clock waits
## while it does, so it can be kept for the Elite or the boss. Stepping on it is the leap (apply_pickup's "leap"). The
## drop is quiet (the pickup's `quiet`: no fanfare, a faint ring in its colour where it lands).
var _timeout_t := -1.0


func _tick_timeout(delta: float) -> void:
	var perk: PerkDef = Registry.perk("timeout")
	var pid: String = str(perk.params.get("pickup", "timeout")) if perk else "timeout"
	if pickups.special_lying(pid):
		_timeout_t = Run.perk_param("timeout", "every", 20.0)
		return
	if _timeout_t < 0.0:
		_timeout_t = Run.perk_param("timeout", "first", 10.0)
	_timeout_t -= delta
	if _timeout_t > 0.0:
		return
	_timeout_t = Run.perk_param("timeout", "every", 20.0)
	var pd: PickupDef = Registry.pickup(pid)
	if pd == null or player == null:
		return
	var at := timeout_spot(player.global_position, player.forward(), Run.perk_param("timeout", "side", 3.0))
	pickups.spawn_special(pd, at, bool(pd.params.get("quiet", true)))
	telegraphs.ring(at, 0.9, 0.6, pd.color)


## Where a Timeout lands (pass 67): `side` metres to his left or right, square to the way he faces (ahead he would take
## it by accident while running, behind lies the crowd chasing him), on the side with fewer creatures within 2.5 m of
## the spot (a toss when even), inside the wall, on the ground.
func timeout_spot(here: Vector3, facing_dir: Vector3, side: float) -> Vector3:
	var f := Vector3(facing_dir.x, 0.0, facing_dir.z)
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	var s := Vector3(-f.z, 0.0, f.x).normalized() * side
	var a := here + s
	var b := here - s
	var na: int = enemies.indices_in_radius(a, 2.5).size()
	var nb: int = enemies.indices_in_radius(b, 2.5).size()
	var at: Vector3 = a if (na < nb or (na == nb and randf() < 0.5)) else b
	if map:
		at = map.clamp_to_arena(at)
		at.y = map.height_at(at.x, at.z)
	return at


## Periodic buffs (pass 67): every held perk whose special is "periodic_buff" (Fadeaway's Buzzer Beater) runs its own
## clock, `first` seconds, then every `every`: its `buff` effects for `seconds` (Run.add_timed_effects under the perk's
## id and name, so the pause sheet lists them by it; quiet: its toast says how long, no "wore off" after), a toast, the
## `ui_buzzer` sound and a gold flash. Any later "every N s, this buff" perk is content only.
var _periodic_t: Dictionary = {}


func _tick_periodic_buffs(delta: float) -> void:
	for pk in Run.perks:
		var def: PerkDef = Registry.perk(str(pk))
		if def == null or def.special != "periodic_buff":
			continue
		var t: float = float(_periodic_t.get(def.id, float(def.params.get("first", def.params.get("every", 30.0))))) - delta
		if t > 0.0:
			_periodic_t[def.id] = t
			continue
		_periodic_t[def.id] = float(def.params.get("every", 30.0))
		_periodic_buff(def)


func _periodic_buff(def: PerkDef) -> void:
	var effects: Array = []
	var raw = def.params.get("buff", [])
	if raw is Array:
		for d in raw:
			if d is Dictionary:
				effects.append(Effect.from_dict(d, "player"))
	if effects.is_empty():
		return
	var secs := float(def.params.get("seconds", 5.0))
	Run.add_timed_effects(def.id, def.display_name, effects, secs, true)
	var gold := Color(1.0, 0.82, 0.35)
	if hud:
		hud.toast("%s: %d s" % [def.display_name.to_upper(), int(round(Run.buff_seconds(secs)))], gold)
		hud.flash(Color(1.0, 0.78, 0.3, 0.25), 0.3)
	if player and telegraphs:
		telegraphs.flash_ring(player.global_position, 2.4, gold, 0.4)
	Audio.play("ui_buzzer")


## Bounty Hunter: a kill counter posts a bounty on a creature near him; killing it pays (on_creature_died_index).
func _count_bounty() -> void:
	if not Run.has_perk("bounty_hunter") or player == null:
		return
	_bounty_kills += 1
	if enemies.bounty_i >= 0 and enemies.is_alive(enemies.bounty_i):
		return
	if _bounty_kills < int(Run.perk_param("bounty_hunter", "every", 60.0)):
		return
	var cands: Array = []
	for i in enemies.indices_in_radius(player.global_position, Run.perk_param("bounty_hunter", "reach", 16.0)):
		var d: EnemyDef = enemies.types[enemies.type_idx[i]]["def"]
		if i != enemies.boss_index and d.archetype != "elite" and d.archetype != "boss" and enemies.is_alive(i):
			cands.append(i)
	if cands.is_empty():
		return
	_bounty_kills = 0
	var b: int = cands[randi() % cands.size()]
	var mult := Run.perk_param("bounty_hunter", "hp_mult", 4.0)
	enemies.hp[b] *= mult
	enemies.max_hp[b] *= mult
	enemies.bounty_i = b
	var bd: EnemyDef = enemies.types[enemies.type_idx[b]]["def"]
	hud.toast("WANTED: " + bd.display_name, Color(1.0, 0.82, 0.35))
	# where it is: a gold ring and a burst on the one wearing the bounty (its warm glow alone is lost in a crowd)
	telegraphs.flash_ring(enemies.pos[b], 1.6, Color(1.0, 0.82, 0.35), 0.8)
	fx.burst(enemies.pos[b] + Vector3(0, 1.0, 0), Color(1.0, 0.82, 0.35), 1.1)
	Audio.play("en_elite_spawn", enemies.pos[b])


func _on_level_up(level: int) -> void:
	Perf.context = "levelup %d" % level
	# the arena levels the hero without the cards unless they are asked for
	var skip_cards: bool = Run.arena and not arena_cards
	if not skip_cards:
		_pending_levels += 1
	Audio.play("ui_levelup")
	# a hero trait: some suits patch themselves on every level (CharacterDef.level_heal, a fraction of max HP)
	if Run.character and Run.character.level_heal > 0.0 and player and not player.dead:
		player.heal(player.max_hp * Run.character.level_heal)
	# Suit Seals: the patch is also a moment of invulnerability
	if Run.has_perk("suit_seals") and player and not player.dead:
		player.invuln = maxf(player.invuln, Run.perk_param("suit_seals", "invuln", 1.5))
	hud.flash_level(level)
	if skip_cards:
		return
	# the cards open now, or wait their turn behind whatever is up, or for him to get up (pass 60: death wins; the bank
	# _pending_levels says how many)
	_request_modal(Modal.CARDS, _show_next_level_cards, 0, true)


## A mutation offer at once (tools: screenshot_run): the weapon whose path is open goes on the table, all of it. Behind
## another screen it waits its turn (pass 60: in the queue). Pass 79 (lane MUT): the director no longer calls it; a slot
## that falls due waits for the hero's next level-up (Run.mutlvl_tick, _mutlvl_open).
func present_path_offer() -> void:
	if Run.arena:
		return
	if _ended:
		return
	_request_modal(Modal.PATH, _open_path_offer)


## The mutation offer itself (the opener): false when no weapon has a pick open.
func _open_path_offer() -> bool:
	var w := Run.next_path_weapon()
	if w == null:
		return false
	var offer := CardPool.path_offer(w)
	if offer.is_empty():
		return false
	_modal = Modal.PATH
	set_paused(true)
	Audio.play("ui_levelup")
	cards.show_offer(offer, "MUTATION · %s" % w.def.display_name.to_upper(), not Save.hint_seen("paths"), true)
	cards.chosen.connect(_on_path_chosen, CONNECT_ONE_SHOT)
	return true


func _on_path_chosen(card: Dictionary) -> void:
	Perf.context = "path chosen"
	if card.get("skipped", false):
		# a skip pays nothing (pass 47): two a stage, shared with the chests (the card screen spends it)
		hud.toast("Mutation skipped", UiKit.INK2)
		if RunAnalytics.I: RunAnalytics.I.event("skip", "path", 0, {"left": Run.skips_left})
	else:
		if RunAnalytics.I: RunAnalytics.I.via = "path"
		var line := CardPool.apply(card)
		hud.toast(line, UiKit.TYPE_COLORS["mutation"])
	Save.mark_hint("paths")
	# a level banked meanwhile takes its turn (pass 60), then the gate
	if _pending_levels > 0:
		_request_modal(Modal.CARDS, _show_next_level_cards, 0, true)
	_modal_done(cards.take_pick())


## The level-up cards for one banked level (the opener): three cards, always (pass 52, Garry: "I get 4 choices for a
## Level Up ... I don't remember asking for that"; luck had added a fourth half its value of the time: it lifts the rarer
## items' odds and nothing else now). A level with nothing left to pick pays 10 gold and the next banked one is tried;
## false when none opened.
func _show_next_level_cards() -> bool:
	if _ended:
		return false
	while _pending_levels > 0:
		_pending_levels -= 1
		# pass 79 (lane MUT): a mutation level-up shows its offer in place of the three cards (Run.mutlvl_take, M2-M3)
		if _mutlvl_open():
			return true
		var offer := CardPool.level_up_offer(3)
		if offer.is_empty():
			Run.add_gold(10, "empty_offer")
			hud.toast("Nothing left to pick. +10 gold", UiKit.INK2)
			continue
		_modal = Modal.CARDS
		set_paused(true)
		cards.show_offer(offer, "LEVEL %d!" % Run.level, not Save.hint_seen("cards"))
		cards.chosen.connect(_on_card_chosen, CONNECT_ONE_SHOT)
		return true
	return false


## Pass 79 (lane MUT): the banked level opening now is a mutation level-up when Run has one claimed (a due offer took
## the level-up, Run.mutlvl_claim): the weapon drawn among those open now goes on the table, the path cards and the reel
## as a slot's offer had them, its title the level's; its pick or skip closes it (_on_path_chosen). False for an
## ordinary level-up (none claimed, or the weapons lost their pick meanwhile: Run.mutlvl_unclaim).
func _mutlvl_open() -> bool:
	var w := Run.mutlvl_take()
	if w == null:
		return false
	var offer := CardPool.path_offer(w)
	if offer.is_empty():
		Run.mutlvl_unclaim()
		return false
	_modal = Modal.PATH
	set_paused(true)
	Audio.play("ui_levelup")
	if "path_level" in cards:
		cards.path_level = Run.level
	cards.show_offer(offer, "LEVEL %d! · MUTATION · %s" % [Run.level, w.def.display_name.to_upper()], not Save.hint_seen("paths"), true)
	cards.chosen.connect(_on_path_chosen, CONNECT_ONE_SHOT)
	return true


func _on_card_chosen(card: Dictionary) -> void:
	Perf.context = "card chosen"
	if card.get("skipped", false):
		# a skip pays nothing (pass 47, Garry: "only two skips per Stage, and those skips work for both Level Ups and
		# Chests"); the card screen spends it
		hud.toast("Skipped", UiKit.INK2)
		if RunAnalytics.I: RunAnalytics.I.event("skip", "", 0, {"left": Run.skips_left})
	else:
		if RunAnalytics.I: RunAnalytics.I.via = "card"
		var t1 := Time.get_ticks_usec()
		var line := CardPool.apply(card)
		Perf.add("card.apply", t1)
		hud.toast(line, UiKit.ACCENT)
	var t2 := Time.get_ticks_usec()
	Save.mark_hint("cards")
	Perf.add("card.unpause", t2)
	# another banked level takes its turn after a beat (pass 60: behind anything of a higher priority that waits, a chest);
	# else, still paused, the run resumes on the next tap, not on the pick (the card flies to its slot meanwhile)
	if _pending_levels > 0:
		_request_modal(Modal.CARDS, _show_next_level_cards, 0, true)
	_modal_done(cards.take_pick())


func _on_enemy_died(def: EnemyDef, at: Vector3, elite: EliteModDef, _weapon_id: String) -> void:
	# Trigger Happy: every kill takes a slice off every weapon's cooldown
	var cut: float = Run.player_sheet.get_stat("cooldown_on_kill", 0.0)
	if cut > 0.0:
		for b in _behaviors.values():
			b.cooldown_left = maxf(b.cooldown_left - cut, 0.0)
	# a training dummy (pass 48, the arena) drops nothing at all: no gem, no power-up, no small pickup, no chest. What a
	# kill sets off (Trigger Happy above, Powder Keg and Brimstone Brand below) still goes, so the items can be tried on it
	if def.brain != "dummy":
		_drop_from_kill(def, at, elite)
	# what the kill sets off and pays, a dummy's too
	_kill_effects(def, at, elite, _weapon_id)


## What a kill drops (out of _on_enemy_died, pass 48, so a training dummy can skip it): its gems at its XP scale,
## Prospector's extra gem, the timeline's power-up roll, the drop passives' small pickups, a chest and its own power-up.
func _drop_from_kill(def: EnemyDef, at: Vector3, elite: EliteModDef) -> void:
	# the creature's own XP scale (pass 47: a variance special's `xp` was never paid), else its type's
	var xp_scale: float = enemies.died_xp_scale if enemies and enemies.died_xp_scale > 0.0 else def.xp_mult * (4.0 if elite else 1.0)
	pickups.drop_from(def, at, xp_scale, elite != null)
	# Prospector (pass 47): a chance of one more XP gem, the size this creature mostly drops
	var xp_chance: float = Run.player_sheet.get_stat("xp_drop_chance", 0.0)
	if xp_chance > 0.0:
		pickups.prospector(def, at, xp_scale, xp_chance)
	director.drop_pickup_from(def, at, elite != null, _salt_luck_at(at))
	# the drop passives (pass 33.2): Cake (Cheese until pass 46, Beef Jerky until pass 44) and Pickpocket roll on every
	# kill for their own small pickups
	for pair in [["heal_drop", "cake_slice"], ["coin_drop", "coin_bag"]]:
		var chance: float = Run.player_sheet.get_stat(str(pair[0]), 0.0)
		if chance > 0.0 and randf() < chance:
			var pd: PickupDef = Registry.pickup(str(pair[1]))
			if pd:
				pickups.spawn_special(pd, at + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), true)
	# chests: every elite variant and the mini-boss, the odd regular creature (drops.chest in its JSON)
	if elite != null or def.archetype == "elite" or (not no_random_chests and randf() < float(def.drops.get("chest", 0.0))):
		pickups.spawn_chest(at)
	# a creature's own power-up (pass 43: the giant drops a Berserk one time in three, drops.pickup {id, chance})
	var own = def.drops.get("pickup", {})
	if own is Dictionary and randf() < float(own.get("chance", 0.0)):
		var od: PickupDef = Registry.pickup(str(own.get("id", "")))
		if od:
			pickups.spawn_special(od, at + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))


## Thing About Luck (pass 69, lane SALT): the factor on the power-up roll for a creature killed at `at`, the highest any
## held weapon's behaviour gives (SaltShaker.powerup_luck_at: salt.luck_mult while it stood in a patch); 1 for none.
func _salt_luck_at(at: Vector3) -> float:
	var m := 1.0
	for b in _behaviors.values():
		if is_instance_valid(b) and b.has_method("powerup_luck_at"):
			m = maxf(m, float(b.powerup_luck_at(at)))
	return m


## The Elite's and the boss's gold (pass 70, Garry: "Make Elites and Bosses give much more Coins"): x5 of pass 44's
## purses (90 + 60 a stage, 260 + 140 a stage), [base, per stage] before Mira's Motherlode; a boss's coins on the sand
## are its drops.coins (x5 in the bosses' JSON), BOSS_COINS when it names none (was 12); an Elite's or a boss's own coin
## (drops.gold) is worth PickupManager.BIG_COIN_MULT times a creature's.
const ELITE_PURSE := [450, 300]
const BOSS_PURSE := [1300, 700]
const BOSS_COINS := 60


## An Elite's purse on stage index `stage` (0 = stage 1), before Motherlode.
static func elite_purse(stage: int) -> int:
	return int(ELITE_PURSE[0]) + int(ELITE_PURSE[1]) * maxi(stage, 0)


## A boss's purse on stage index `stage`, before Motherlode (its coins on the sand come on top).
static func boss_purse(stage: int) -> int:
	return int(BOSS_PURSE[0]) + int(BOSS_PURSE[1]) * maxi(stage, 0)


## What a kill sets off and pays (out of _on_enemy_died, pass 48): Powder Keg, Brimstone Brand, Grand Finale, an Elite's
## purse and a boss's reward, and the burst where it fell. A training dummy sets everything off and pays nothing (pass 49).
func _kill_effects(def: EnemyDef, at: Vector3, elite: EliteModDef, _weapon_id: String) -> void:
	# Powder Keg (pass 48, a passive item): a kill may blow the body up; a keg's own kills never roll again (no chains)
	var keg: float = Run.player_sheet.get_stat("powder_keg_chance", 0.0)
	if keg > 0.0 and _weapon_id != POWDER_KEG and randf() < keg:
		_powder_keg(at, enemies.died_max_hp if enemies and enemies.died_max_hp > 0.0 else def.hp)
	# Brimstone Brand (pass 43, stage 3): a kill may set the sand alight where the body fell, burning the crowd
	var brand: float = Run.player_sheet.get_stat("brand_chance", 0.0)
	if brand > 0.0 and randf() < brand and def.archetype != "boss":
		var bw: WeaponInstance = Run.weapon_instance(_weapon_id) if _weapon_id != "" else null
		var bz := spawn_zone(at, 2.2, 3.0, 6.0 * Run.player_sheet.get_stat("might", 1.0), 0.25, bw, 0.0, Color(1.0, 0.42, 0.1, 0.3))
		bz.flames = true
		fx.ignite(at + Vector3(0, 0.2, 0), 1.4)
	# Gold Dust (pass 54, the Sun Scepter's motion path): a kill by a weapon carrying it, by a pillar or by its burn, drops
	# its coins `chance` of the time (SunScepter.gold_dust_coins); a training dummy pays nothing
	if _weapon_id != "" and def.brain != "dummy":
		for k in range(preload("res://core/behaviors/SunScepter.gd").gold_dust_coins(Run.weapon_instance(_weapon_id))):
			pickups.mark_coin(pickups.spawn(PickupManager.KIND_COIN, at, 1.0 + float(randi() % 2)), "gold_dust")
	# Grand Finale (pass 43, Calavera): a boss or an Elite going down takes a share of every creature's health with it
	if (def.archetype == "boss" or def.archetype == "elite" or elite != null) and Run.has_perk("grand_finale"):
		var fr := Run.perk_param("grand_finale", "radius", 14.0)
		var frac := Run.perk_param("grand_finale", "frac", 0.35)
		for j in enemies.indices_in_radius(at, fr):
			if j != enemies.boss_index:
				enemies.damage(j, enemies.max_hp[j] * frac, "grand_finale")
		enemies.hero_throw_radius(at, fr, Run.perk_param("grand_finale", "throw", 16.0))
		telegraphs.flash_ring(at, fr, Color(1.0, 0.82, 0.35), 0.6)
		fx.burst(at + Vector3(0, 1.0, 0), Color(1.0, 0.82, 0.35), 4.0)
		hud.toast("GRAND FINALE", Color(1.0, 0.82, 0.35))
		camera.shake(1.2)
	# materials for the homestead: bones from every Elite, relics from every boss; deeper stages and Mira's trait add one
	# the Mirror spends gold, so what the deep parts of a run used to pay in bones and relics they pay in coin:
	# an Elite is worth a purse, a boss a chest of them (Mira's Motherlode adds a half). A training dummy pays nothing
	# (pass 49: the arena's Elite dummy and Boss dummy are Elites by their kind)
	var lode: float = 1.5 if (Run.character and Run.character.specials.has("motherlode")) else 1.0
	var pays := def.brain != "dummy"
	if (elite != null or def.archetype == "elite") and pays:
		var purse := int(elite_purse(Run.stage) * lode)
		Run.add_gold(purse, "elite_purse")
		hud.toast("+%d GOLD" % purse, Color(1.0, 0.85, 0.35))
	if def.archetype == "boss" and pays:
		var chest_gold := int(boss_purse(Run.stage) * lode)
		Run.add_gold(chest_gold, "boss_purse")
		hud.toast("+%d GOLD" % chest_gold, Color(1.0, 0.85, 0.35))
	if def.archetype == "boss" and pays:
		_end_ring()
		_hell_lines.clear()
		# the reward scales with the boss (drops.coins, drops.chests): the second boss pays for continuing
		for k in range(int(def.drops.get("coins", BOSS_COINS))):
			pickups.mark_coin(pickups.spawn(PickupManager.KIND_COIN, at + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)), 5.0), "boss_coins")
		for k in range(int(def.drops.get("chests", 1)) - 1):
			pickups.spawn_chest(at + Vector3(-2.0 - 1.6 * k, 0, 1.5))
		hud.toast("A BOSS CHEST: open it to call everything in", Color(1.0, 0.82, 0.35))
		fx.burst(at + Vector3(0, 1, 0), Color(1.0, 0.75, 0.3), 5.0)
		camera.shake(1.5)
		hud.banner("BOSS DOWN", Color(1.0, 0.8, 0.3))
	elif def.archetype == "elite":
		fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.65, 0.3), 3.0)
		camera.shake(0.9)
	# a regular creature's pale puff is gone (pass 58): its splash in its own blood says it died (_death_splash, from
	# on_creature_died_index, which knows the size it was drawn at)


## Powder Keg's blast (pass 48): KEG_FRAC of the dead creature's max HP to everything within KEG_RADIUS of the body, thrown
## with KEG_KNOCK, recorded as the source POWDER_KEG (Results, the run recorder), whose kills never roll a keg again.
const POWDER_KEG := "powder_keg"
const KEG_RADIUS := 2.4
const KEG_FRAC := 0.25
const KEG_KNOCK := 9.0
const KEG_COLOUR := Color(1.0, 0.55, 0.15)


func _powder_keg(at: Vector3, dead_max_hp: float) -> void:
	enemies.damage_radius(at, KEG_RADIUS, dead_max_hp * KEG_FRAC, POWDER_KEG, KEG_KNOCK)
	fx.burst(at + Vector3(0, 0.5, 0), KEG_COLOUR, 1.1)
	if telegraphs and map:
		telegraphs.flash_ring(Vector3(at.x, map.height_at(at.x, at.z) + 0.05, at.z), KEG_RADIUS, KEG_COLOUR, 0.3)
	Audio.play("it_keg_boom", at)


## Skedaddle (pass 48, a passive item): a hit that lands, on his health or on his Energy Shield, sends him running; a small
## red burst when the boost starts or starts again (Run.skedaddle says so), and its red ribbon follows him for as long as
## Run.skedaddle_left() lasts (_tick_speed_fx).
func _skedaddle() -> void:
	if Run.skedaddle() and player and not player.dead:
		fx.speed_burst(player.global_position, Fx.SKEDADDLE_RED, true)


# ---------------------------------------------------------------- pass 69, the new passive items

const HEAL_PULSE_COLOUR := Color(0.78, 0.92, 0.42, 0.5)
const COUNTERPUNCH_COLOUR := Color(1.0, 0.45, 0.18)
var last_stand_fx: LastStandFx


## Hot Springs (pass 69, a passive item): a heal's pulse (Player.heal_pulsed) hurts every creature within
## Player.HEAL_PULSE_RADIUS for `damage`, recorded as the passive's own source; a soft green-gold ring races out, brighter
## for a bigger heal, and a real heal (3 HP or more, never regen's trickle alone) chimes.
func _heal_pulse(damage: float, healed: float) -> void:
	if player == null or player.dead or enemies == null:
		return
	var at: Vector3 = player.global_position
	enemies.damage_radius(at, Player.HEAL_PULSE_RADIUS, damage, "hot_springs")
	if telegraphs:
		var col := HEAL_PULSE_COLOUR
		col.a = clampf(0.22 + healed * 0.03, 0.22, 0.6)
		telegraphs.race_ring(at, Player.HEAL_PULSE_RADIUS, 0.45, col, 0.22)
	if healed >= 3.0:
		Audio.play("it_heal_pulse", at)


## Last Stand (pass 69, a passive item): the hero's last_stand signal (Run.last_stand_check put its damage on the sheet):
## the slowed time and its look (ui/LastStandFx.gd, made once), a toast and the thump.
func _last_stand() -> void:
	if last_stand_fx == null or not is_instance_valid(last_stand_fx):
		last_stand_fx = LastStandFx.new()
		last_stand_fx.name = "LastStandFx"
		last_stand_fx.game = self
		add_child(last_stand_fx)
	last_stand_fx.start()
	if hud:
		hud.toast("LAST STAND", Color(1.0, 0.32, 0.3))
	Audio.play("it_last_stand")


## Counterpunch (pass 69, a passive item): an evade that armed the next attack throws an ember-orange burst and a snap.
func _counterpunch_fx() -> void:
	if player == null or player.dead or not Run.counter_armed:
		return
	fx.speed_burst(player.global_position, COUNTERPUNCH_COLOUR, true)
	Audio.play("it_counterpunch", player.global_position)


## Cactus Coat: whatever hits the hero gets a face full of spines, along with anything else standing close.
func _on_player_hit() -> void:
	# Crescendo (pass 43): a hit ends the song (pass 49: Hot Streak's kills are kept whatever hits him)
	Run.reset_crescendo()
	# pass 67: the weapons that answer a hit on his health (the basketball's Heat cools, ProjectileEmitter.on_hero_hit);
	# player.hit is only a hit that reached it, so an evade or a shield keeps the Heat
	_tell_behaviors("on_hero_hit")
	# Skedaddle (pass 48, a passive item): a hit sends him running
	_skedaddle()
	# Loose Change (pass 48, a passive item): a hit may knock a coin out of him (PickupManager.toss_coin)
	var lc: float = Run.player_sheet.get_stat("coin_on_hit", 0.0)
	if lc > 0.0 and player and pickups and randf() < lc:
		if pickups.toss_coin(player.global_position) >= 0:
			Audio.play("it_coin_drop", player.global_position)
	# Tough Love: a hit makes Dad hit harder and wider for a few seconds
	if Run.has_perk("tough_love"):
		var e1 := Effect.make("might", "mul", Run.perk_param("tough_love", "might", 0.15), "player")
		var e2 := Effect.make("area", "mul", Run.perk_param("tough_love", "area", 0.15), "player")
		Run.add_timed_effects("tough_love", "Tough Love", [e1, e2], Run.perk_param("tough_love", "seconds", 4.0))
		player.refresh_stats()
	var th: float = Run.player_sheet.get_stat("thorns", 0.0)
	if th > 0.0 and player and not player.dead:
		enemies.damage_radius(player.global_position, 2.3, th, "", 6.0)
		fx.burst(player.global_position + Vector3(0, 0.6, 0), Color(0.45, 0.8, 0.35), 1.2)
	# the hit is felt (pass 54, Garry: a hit on his health had only a number and a shake): a red rim round the screen
	# (HUD.vignette, else a faint red flash), sand kicked up at his feet, and a 45 ms hit-stop, the world's clock nearly
	# held and given back on a real-time timer; never in the arena, never while the run is paused, never on top of one
	# already running (the clock below 1 is the sign) and never once he is down
	if hud:
		if hud.has_method("vignette"):
			hud.vignette(Color(0.85, 0.1, 0.08, 0.55), 0.3)
		else:
			hud.flash(Color(0.8, 0.1, 0.1, 0.25), 0.2)
	if player and fx:
		fx.sand(player.global_position, 0.7)
	if not Run.arena and not paused and not get_tree().paused and player and not player.dead and Engine.time_scale >= 0.999:
		Engine.time_scale = 0.08
		get_tree().create_timer(0.045, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


## The hero finished using a structure (content/structures).
func use_structure(def: StructureDef, at: Vector3) -> void:
	var p: Dictionary = def.params
	if RunAnalytics.I: RunAnalytics.I.event("structure", def.id, 0, {"effect": def.effect_kind})
	Audio.play("pk_chest_open", at)
	fx.burst(at + Vector3(0, 1.0, 0), def.color, 2.0)
	telegraphs.flash_ring(at, def.radius + 0.5, def.color, 0.5)
	camera.shake(0.4)
	match def.effect_kind:
		"bank":
			# the Strongbox: everything in the purse goes to the homestead now, whatever happens to the run (a death while
			# its coins are still flying keeps it too)
			var carried := bank_purse()
			# and it is seen (pass 58, Garry: "coins flying out of the player and into the chest ... it should take 3
			# seconds at least. After the coins arrive the chest flies away"): the coins fly from the hero into the box
			# (StructureManager.deposit, CoinStream), pinging as they drop in, the purse on the HUD counting down as they
			# leave him; the box lifts off once the last is in. With nothing carried it flies off at once, as before
			var streamed: bool = structures != null and structures.deposit(at, carried) > 0.0
			if not streamed:
				Run.gold_changed.emit(Run.run_gold)
				Audio.play("pk_coin", player.global_position)
			hud.toast("BANKED %d GOLD" % carried, Color(1.0, 0.85, 0.35))
		"vacuum_all":
			pickups.vacuum_all(true)
			hud.banner(def.display_name.to_upper(), def.color)
		"teleport":
			teleport_hero(def)
		"stranger":
			var offer := Run.stranger_offer()
			if offer.is_empty():
				Run.add_gold(60, "stranger_empty")
				hud.toast("The Stranger had nothing for you. +60 gold", UiKit.ACCENT)
				return
			var cost := float(offer.get("hp_cost", p.get("hp_cost", 0.15)))
			_request_modal(Modal.STRANGER, func() -> bool:
				_modal = Modal.STRANGER
				set_paused(true)
				stranger_screen.open(offer, cost)
				stranger_screen.closed.connect(func(took):
					if RunAnalytics.I: RunAnalytics.I.stranger(offer, cost, player.max_hp, bool(took))
					if took:
						if RunAnalytics.I: RunAnalytics.I.via = "stranger"
						var line := Run.stranger_take(offer, cost)
						player.refresh_stats()
						hud.toast("The deal: %s, for %d%% of your health" % [line, int(round(cost * 100.0))], Color(0.75, 0.6, 1.0))
					else:
						hud.toast("The Stranger is gone. Only his cloak stays.", UiKit.INK2)
					_modal_done({}, false), CONNECT_ONE_SHOT)
				return true)
		"shop":
			var offer := CardPool.level_up_offer(3)
			if offer.is_empty():
				Run.add_gold(50, "shop_empty")
				hud.toast("The shop had nothing left. +50 gold", UiKit.ACCENT)
				return
			_request_modal(Modal.SHOP, func() -> bool:
				_modal = Modal.SHOP
				set_paused(true)
				if RunAnalytics.I: RunAnalytics.I.via = "shop"
				structure_shop.open(offer)
				structure_shop.closed.connect(func(bought):
					if bought:
						hud.toast("Bought!", UiKit.ACCENT)
					_modal_done({}, false), CONNECT_ONE_SHOT)
				return true)
		"heal":
			var amount: float = player.max_hp * float(p.get("fraction", 0.5))
			# named, so the Down! list shows it (pass 46)
			player.heal(amount, def.display_name)
			hud.toast("+%d HP" % int(round(amount)), UiKit.GOOD)
		"loot":
			var gold := int(p.get("gold", 60))
			Run.add_gold(gold, "loot_cache")
			for k in range(int(p.get("gems", 3))):
				pickups.spawn(PickupManager.KIND_GEM_L, at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), 25.0)
			for k in range(int(p.get("coins", 4))):
				pickups.mark_coin(pickups.spawn(PickupManager.KIND_COIN, at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), 3.0), "loot_cache")
			hud.toast("+%d gold and gems" % gold, UiKit.ACCENT)
		"buff":
			Run.add_timed_effects("structure:" + def.id, def.display_name, def.effects, float(p.get("seconds", 30.0)))
			hud.toast("%s: %s for %d s" % [def.display_name.to_upper(), TextGen.describe_effects(def.effects), int(p.get("seconds", 30.0))], def.color)
		"level_up":
			Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)
			hud.toast("LEVEL UP!", UiKit.XP)
		"dice":
			_roll_dice(def, at)
		"totem":
			_use_totem(def)
		_:
			hud.toast(def.display_name, def.color)


## A Totem Pole used (pass 73, lane STRUCT; use_structure's "totem"): its menu of gifts (ui/TotemScreen.gd) through the
## one-screen rule, the offer rolled when the menu opens (core/systems/TotemBoons.gd, the pole's `params.boons`); the
## gift picked stays on the hero for the run (Run.take_totem_boon) and a toast says it. A pole with nothing to offer only
## says its name.
func _use_totem(def: StructureDef) -> void:
	_request_modal(Modal.TOTEM, func() -> bool:
		# (pass 77, lane SIMRUN: a run sim's own dice for the gifts, Run.totem_rng; null in play: random as ever)
		var offer: Array = TOTEM_SCREEN.BOONS.offer(def, Run.totem_rng)
		if offer.is_empty():
			hud.toast(def.display_name, def.color)
			return false
		_modal = Modal.TOTEM
		set_paused(true)
		totem_screen.open(offer, def)
		totem_screen.closed.connect(func(boon: Dictionary) -> void:
			if RunAnalytics.I: RunAnalytics.I.totem_offer(offer, boon)
			if not boon.is_empty():
				var words := Run.take_totem_boon(boon)
				player.refresh_stats()
				var title := TOTEM_SCREEN.BOONS.title(boon)
				hud.toast("%s: %s" % [title.to_upper(), words], def.color)
			_modal_done({}, false), CONNECT_ONE_SHOT)
		return true)


## The Strongbox's purse (use_structure's "bank"; out of it in pass 58, so the deposit's coins can show it leaving): every
## coin the hero carries goes to the save at once and counts as banked. Returns how many.
func bank_purse() -> int:
	var carried := Run.run_gold
	if carried > 0:
		Save.add_gold(carried, "strongbox")
		Run.run_gold = 0
		Run.banked_gold += carried
	return carried


## The Teleport (pass 35): the hero comes out far across the map, where the crowd is thinnest of forty spots tried at
## least `min_distance` of the arena's radius away (the farthest one if none is). A flash where he left and where he
## lands, the camera cut to him, `invuln` seconds of blinking safety; a harpoon's rope does not come along.
func teleport_hero(def: StructureDef) -> void:
	var p: Dictionary = def.params
	var from: Vector3 = player.global_position
	var arena: float = map.arena_radius if map else 60.0
	var min_d: float = arena * float(p.get("min_distance", 0.6))
	var best := Vector3.INF
	var best_n := 1 << 30
	var far := Vector3.INF
	var far_d := -1.0
	for k in range(40):
		var a := randf() * TAU
		var q := Vector3(cos(a), 0.0, sin(a)) * randf_range(arena * 0.1, arena * 0.82)
		var clear := true
		if map:
			for o: Vector3 in map.obstacles:
				if Vector2(q.x - o.x, q.z - o.y).length() < o.z + 1.5:
					clear = false
					break
			if clear and map.has_method("in_water") and map.in_water(q):
				clear = false
		if not clear:
			continue
		var dd := Vector2(q.x - from.x, q.z - from.z).length()
		if dd > far_d:
			far_d = dd
			far = q
		if dd < min_d:
			continue
		var n := enemies.indices_in_radius(q, 9.0).size()
		if n < best_n:
			best_n = n
			best = q
	if best == Vector3.INF:
		best = far
	if best == Vector3.INF:
		return
	best.y = map.height_at(best.x, best.z) if map else from.y
	var col: Color = def.color
	fx.burst(from + Vector3(0, 1.0, 0), col, 1.6)
	telegraphs.flash_ring(from, 2.0, col, 0.45)
	if tether_i >= 0:
		tether_end()
	player.global_position = best
	player.velocity = Vector3.ZERO
	camera.snap_to(player)
	player.invuln = maxf(player.invuln, float(p.get("invuln", 1.2)))
	fx.burst(best + Vector3(0, 1.0, 0), col, 1.8)
	fx.burst(best + Vector3(0, 0.3, 0), Color(1, 1, 1), 1.0)
	telegraphs.flash_ring(best, 2.6, col, 0.5)
	hud.flash(Color(col.r, col.g, col.b, 0.35), 0.4)
	hud.toast("TELEPORTED", col)
	Audio.play("st_teleport", best)


## The dice shrine: one of its outcomes at random, each one honest about what it did.
func _roll_dice(def: StructureDef, at: Vector3) -> void:
	var outcomes: Array = def.params.get("outcomes", ["heal", "gold", "level", "swarm"])
	var pick := str(outcomes[randi() % outcomes.size()])
	match pick:
		"heal":
			player.heal(player.max_hp, def.display_name)
			hud.banner("DICE: FULL HEAL", UiKit.GOOD)
		"gold":
			Run.add_gold(150, "dice")
			hud.banner("DICE: +150 GOLD", UiKit.ACCENT)
		"level":
			Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)
			hud.banner("DICE: LEVEL UP", UiKit.XP)
		"swarm":
			var id: String = Run.map.skins.get("swarmer", Run.map.skins.values()[0]) if Run.map and not Run.map.skins.is_empty() else ""
			if id != "":
				enemies.spawn_ring(id, 14, at, 9.0)
			pickups.spawn_chest(at + Vector3(2.0, 0, 0))
			hud.banner("DICE: AMBUSH, BUT A CHEST", UiKit.DANGER)
		_:
			hud.toast(pick, def.color)


## The hero walked into a pickup (content/pickups): heal, timed buff, shield or gem vacuum (pass 67: or the Timeout's
## leap).
func apply_pickup(def: PickupDef, at: Vector3) -> void:
	if RunAnalytics.I: RunAnalytics.I.event("pickup", def.id, 0, {"small": bool(def.params.get("small", false)), "effect": def.effect_kind})
	# a power-up taken (pass 44: an unlock counts them); the small things underfoot (cake slices, coin bags) are not power-ups
	if not bool(def.params.get("small", false)) and not Run.arena:
		Save.add_total("pickups", 1)
	match def.effect_kind:
		"heal":
			var amount: float = player.max_hp * def.value
			# the Heart, a Cake Slice: named, so the Down! list shows it (pass 46)
			player.heal(amount, def.display_name)
			if not bool(def.params.get("quiet", false)):
				hud.toast("+%d HP" % int(round(amount)), UiKit.GOOD)
			Audio.play("pk_heart", at)
		"gold":
			# the coin bag: a handful of coins at once
			Run.add_gold(int(def.value), def.id)
			Audio.play("pk_coin", at)
		"buff":
			# pass 62: a power-up off the ground lasts the Pocket Watch's longer (Run.powerup_seconds), then buff_seconds
			var pu_s: float = Run.powerup_seconds(def.duration)
			Run.add_timed_effects(def.id, def.display_name, def.effects, pu_s)
			# the seconds as they run on this hero (pass 54: Solenne's buffs last longer, Run.buff_seconds)
			hud.toast("%s: %s for %d s" % [def.display_name.to_upper(), TextGen.describe_effects(def.effects), int(round(Run.buff_seconds(pu_s)))], def.color)
			Audio.play("pk_powerup", at)
			# a power-up that makes him faster (a Sprint, by its effects, pass 48): its blue look runs while it lasts
			if _speeds_up(def) and player:
				if not _speed_buffs.has(def.id):
					_speed_buffs.append(def.id)
				fx.speed_burst(player.global_position, Fx.SPRINT_BLUE)
				telegraphs.flash_ring(player.global_position, 2.8, Fx.SPRINT_BLUE, 0.4)
		"shield":
			var sh_s: float = Run.buff_seconds(Run.powerup_seconds(def.duration))
			player.shield(sh_s)
			hud.toast("SHIELD for %d s" % int(round(sh_s)), def.color)
			Audio.play("pk_powerup", at)
		"vacuum":
			# everything on the map, the coins and the chests too, as a boss kill does it
			pickups.vacuum_all(true, true)
			hud.toast("MAGNET PULSE", def.color)
		"nuke":
			var np: Dictionary = def.params
			nuke_blast(player.global_position, float(np.get("radius", 16.0)), def.value, float(np.get("knockback", 14.0)))
			hud.toast("NUKE", def.color)
		"leap":
			# pass 67, Fadeaway's Timeout: he leaps clear towards the emptiest ground (Thruster Burst's scan, `directions`
			# of them, and its push and lift; his own move, so it carries him under the Invincibility bubble too; of
			# equally empty ways the one most away from the creatures within `slow_radius`, with none there the way he
			# faces), untouchable `invuln` seconds, and those creatures are slowed by `slow` for `slow_seconds`, tinted
			# Curare's dark green meanwhile (a hero's perk: Ducktape does not stretch it)
			var lp: Dictionary = def.params
			var here: Vector3 = player.global_position
			var sr := float(lp.get("slow_radius", 3.5))
			var ss := float(lp.get("slow_seconds", 2.0))
			var ring := enemies.indices_in_radius(here, sr)
			var away := Vector3.ZERO
			for e in ring:
				away += Vector3(here.x - enemies.pos[e].x, 0.0, here.z - enemies.pos[e].z)
			var prefer: Vector3 = away.normalized() if away.length_squared() > 0.0001 else player.forward()
			var dir := _emptiest_dir(here, int(lp.get("directions", 12)), prefer)
			player.blast(dir * float(lp.get("push", 28.0)), float(lp.get("lift", 5.0)), false)
			player.invuln = maxf(player.invuln, float(lp.get("invuln", 0.8)))
			enemies.slow_radius(here, sr, float(lp.get("slow", 0.5)), ss, false)
			for e in ring:
				enemies.set_status_tint(e, ProjectileManager.CURARE_TINT, ss)
			fx.speed_burst(here, Fx.SPRINT_BLUE)
			telegraphs.flash_ring(here, sr, def.color, 0.4)
			camera.shake(0.5)
			Audio.play("pk_timeout", here)
			hud.toast(def.display_name.to_upper(), def.color)
		"pollen":
			# a Pollen flower (pass 48, FlowerField): one dropped as a pickup (the arena's DROPS tab) gives every held Pollen
			# weapon its buff, as the field's own flowers do (FlowerField._pick)
			FlowerField.give_buff(self)
			Audio.play("pk_flower", at)
		_:
			Audio.play("pk_powerup", at)
	fx.burst(at + Vector3(0, 0.8, 0), def.color, 1.3)
	telegraphs.flash_ring(at, 2.0, def.color, 0.35)


## A chest on the ground was touched: the game pauses and the reel decides in front of the player. One reel at a time
## (pass 60: a request each; a boss drops two chests and both fly in together, his first), and none while he is down.
func open_chest(at: Vector3, boss: bool = false) -> void:
	Audio.play("pk_chest_open", at)
	fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4), 1.5)
	if _ended:
		return
	_request_modal(Modal.CHEST, func() -> bool: return _open_chest_now(boss), BOSS_CHEST_BUMP if boss else 0)


## The reel itself (the opener).
func _open_chest_now(boss: bool) -> bool:
	if boss:
		# the boss's chest: opening it is what calls everything on the map in, and the reel only holds mutations
		pickups.vacuum_all(true, true)
		hud.toast("THE SPOILS COME TO YOU", Color(1.0, 0.82, 0.35))
	var r := Run.chest_roll(boss)
	_modal = Modal.CHEST
	set_paused(true)
	if RunAnalytics.I: RunAnalytics.I.via = "boss_chest" if boss else "chest"
	chest_screen.open(r)
	return true


## The reel closed (pass 47): taken, or let go for one of the stage's skips (Run.chest_skip: nothing gained; it was sold
## for gold before). A banish on the reel never closes it: the screen spins again to Run.chest_banish's new roll, and
## Run tells the recorder. With no skip left the chest cannot be let go, so what it holds is taken. The next chest or a
## banked level follows (pass 60: the queue), else the gate.
func _on_chest_closed(take: bool) -> void:
	var r := chest_screen.result()
	var skipped := false
	if not take:
		skipped = Run.chest_skip(r) != ""
	if skipped:
		Audio.play("ui_tap")
		hud.toast("Chest skipped", UiKit.INK2)
	else:
		var line := Run.chest_take(r)
		Audio.play("ui_chest_take")   # pass 67: the poker chip's clack; purchases keep their ka-ching (ui_buy)
		if str(r.get("type", "")) != "evolution":
			hud.toast("Chest: " + line, UiKit.ACCENT)
	if _pending_levels > 0:
		_request_modal(Modal.CARDS, _show_next_level_cards, 0, true)
	_modal_done(chest_screen.take_pick() if chest_screen.has_method("take_pick") else {})


func _on_portal_ready(at: Vector3) -> void:
	portal = Portal.new()
	add_child(portal)
	portal.global_position = at
	portal.entered.connect(_on_portal_entered)
	hud.toast("PORTAL OPEN: extract or continue", UiKit.GOOD)


## The hero walked into the portal: the stage-clear dialog (pass 60: its turn, behind a chest he touched first).
func _on_portal_entered() -> void:
	_request_modal(Modal.PORTAL, _open_portal_dialog)


func _open_portal_dialog() -> bool:
	_modal = Modal.PORTAL
	set_paused(true)
	var final_stage: bool = Run.stage + 1 >= Run.map.timeline.stages if Run.map and Run.map.timeline else false
	# pass 43: after the last boss the choice is extract or stay (endless needs no unlock any more)
	portal_dialog.open(Run.stage + 1, true, final_stage)
	return true


## "Not yet" (pass 48, PortalDialog.declined: the button, or back): the run goes on with the portal where it is, and it
## asks again once the hero has stepped out past Portal.REARM and walks back in (Portal.check_player). A second of grace,
## as after every screen (_resume_run).
func _on_portal_declined() -> void:
	if _ended:
		return
	if portal_dialog.visible:
		portal_dialog.visible = false
	hud.toast("The portal waits", UiKit.GOOD)
	Audio.play("st_portal_wait", portal.global_position if portal and is_instance_valid(portal) else player.global_position)
	if RunAnalytics.I: RunAnalytics.I.event("portal_wait", "", Run.stage + 1)
	_modal_done({}, false)


func _on_portal_decided(extract: bool) -> void:
	if RunAnalytics.I: RunAnalytics.I.event("portal", "", Run.stage + 1, {"extract": extract})
	if extract:
		Run.extracted = true
		Save.mark_once("extract_%s_%d" % [Run.map.id, Run.stage + 1])
		Save.add_total("extracts", 1)
		Audio.play("wd_extract")
		player.cheer()
		end_run()
	else:
		# the run goes on first (the next stage's start plays unpaused), then the next screen in line if one waits
		_modal_done({}, false)
		if portal:
			portal.queue_free()
			portal = null
		director.continue_to_next_stage()
		if Run.endless:
			hud.banner("HELL STAYS", UiKit.ACCENT)
		elif Run.stage + 1 >= 3:
			hud.banner("STAGE %d · HELL" % (Run.stage + 1), UiKit.DANGER)
		else:
			hud.banner("STAGE %d" % (Run.stage + 1), UiKit.ACCENT)


## Down: the death plays out for a moment, then the game pauses behind the revive screen. One chance per run plus
## one per Revive shop tier; the count runs out into the results screen. Phoenix Feather (pass 48) comes first: once a
## run he gets up by himself PHOENIX_DELAY seconds after he falls, with no Down! screen.
const PHOENIX_DELAY := 2.0
const PHOENIX_COLOUR := Color(1.0, 0.55, 0.15)
## Death in the arena (pass 49, Garry: "If Player dies they just respawn without the Revive Effect"): he is up again at
## once, whole (his health and his Energy Shield), on the arena's start spot, blinking for ARENA_RESPAWN_INVULN seconds,
## and a RESPAWNED toast says so; no Down! screen, no revive blast, nothing spent (no revive, no Phoenix Feather). The HERO
## tab's "Go down" asks for the real fall first (`arena_real_down`), so Down! and Phoenix Feather can still be tried.
const ARENA_RESPAWN_INVULN := 2.0
var arena_real_down := false
## how many times the arena has stood him up again (tests, the arena's tools)
var arena_respawns := 0


func _on_player_died() -> void:
	# the arena (pass 49): straight back up on the start spot, unless the HERO tab asked for the real fall
	if Run.arena and not arena_real_down:
		arena_respawn()
		return
	arena_real_down = false
	if RunAnalytics.I: RunAnalytics.I.death()
	hud.hide_player_bar()
	if Run.phoenix_ready():
		Run.use_phoenix()
		# the feather leaves him while he lies there (pass 54): its plate rises off him in embers and its banner (with
		# its icon, in its colour) says what is standing him up; the one held is the spent one (Run.item_spent)
		var feather: ContentDef = Registry.passive("phoenix_feather")
		for pid in Run.passives.keys():
			var pd: ContentDef = Registry.passive(str(pid))
			if pd and Run.item_spent(pd):
				feather = pd
				break
		if feather and camera and camera.camera and player:
			var wp: Vector3 = player.global_position + Vector3(0, 1.2, 0)
			if not camera.camera.is_position_behind(wp):
				hud.fly_item(feather, camera.camera.unproject_position(wp), PHOENIX_COLOUR)
		hud.banner("PHOENIX FEATHER", PHOENIX_COLOUR, feather.icon if feather else null)
		await get_tree().create_timer(PHOENIX_DELAY, false).timeout
		if _ended or player == null:
			return
		_revive("phoenix")
		return
	# the fall plays out, on a pause-respecting clock (pass 60: behind a screen or the pause menu it waits), then Down!
	# asks, in its turn (death wins: it goes first, and nothing else opens while he is down)
	await get_tree().create_timer(1.2, false).timeout
	if _ended or player == null or not player.dead:
		return
	_request_modal(Modal.REVIVE, _open_revive)


## Down! (the opener).
func _open_revive() -> bool:
	_modal = Modal.REVIVE
	set_paused(true)
	var chances: int = 1 + Run.player_sheet.get_int("revives", 0) - Run.revives_used
	# the last 30 s as rows for the list and as text for its copy button (pass 46)
	revive_screen.open(Run.run_gold, chances, player.damage_log_text(), player.damage_log.back() if not player.damage_log.is_empty() else {},
		player.damage_log.duplicate(true))
	return true


func _on_revive_decided(kind: String) -> void:
	_modal = Modal.NONE
	set_paused(false)
	match kind:
		"give_up", "timeout":
			Run.died = true
			end_run()
		_:
			_revive(kind)


## The hero stands up again (pass 48, out of _on_revive_decided): a revive bought on Down! ("gold", an ad), the debug one,
## or Phoenix Feather's ("phoenix"). He comes back at the revive's health with a bang that clears what stands round him;
## a bought one counts against the run's chances, the debug one and Phoenix Feather's (once a run of its own) do not.
func _revive(kind: String) -> void:
	if RunAnalytics.I: RunAnalytics.I.event("revive", kind)
	if kind == "gold":
		# a flat price, spent like the shop's (pass 61: the run recorder counts it under "revive"); never below 0
		Run.spend_gold(mini(ReviveScreen.GOLD_COST, Run.run_gold), "revive")
	if kind != "debug" and kind != "phoenix":
		Run.revives_used += 1
	player.revive()
	# he comes back with a bang: a wave a third of the nuke's that clears everything but the big ones
	revive_blast()
	enemies.damage_radius(player.global_position, 6.0, 0.0, "", 12.0)
	if kind == "phoenix":
		# Phoenix Feather: he rises out of a ring of fire
		var at := player.global_position
		telegraphs.flash_ring(at, 6.0, PHOENIX_COLOUR, 0.6)
		for k in range(14):
			var a := TAU * float(k) / 14.0
			var p := at + Vector3(cos(a), 0, sin(a)) * 2.6
			if map:
				p.y = map.height_at(p.x, p.z)
			fx.flame(p, 1.5, randf_range(0.6, 0.8))
		fx.burst(at + Vector3(0, 1.0, 0), PHOENIX_COLOUR, 2.0)
		Audio.play("it_phoenix", at)
		hud.show_player_bar()
		hud.banner("PHOENIX FEATHER", PHOENIX_COLOUR)
	else:
		telegraphs.flash_ring(player.global_position, 6.0, UiKit.GOOD, 0.6)
		hud.show_player_bar()
		hud.banner("REVIVED" if kind != "debug" else "DEBUG REVIVE", UiKit.GOOD)
	Perf.context = "revived " + kind
	# what came while he was down (pass 60): the banked level-ups, a chest, a path offer, one after another, once his
	# blast has read (he blinks for two seconds, so nothing bites him in the beat)
	if not _modal_queue.is_empty():
		_open_next_modal_soon(REVIVE_BEAT)


## The arena's respawn (pass 49, _on_player_died): up at once, whole, on the start spot, ARENA_RESPAWN_INVULN seconds of
## blinking; no blast (the creatures round him are left as they are), no Down!, no revive or Phoenix Feather spent.
func arena_respawn() -> void:
	if player == null or _ended:
		return
	tether_end()
	player.revive()
	player.hp = player.max_hp
	if player.sheet:
		player.shield_pts = player.sheet.get_stat("shield_max", 0.0)
	player.invuln = ARENA_RESPAWN_INVULN
	player.velocity = Vector3.ZERO
	if map:
		player.global_position = map.player_start()
	player.damaged.emit(player.hp, player.max_hp)
	if camera:
		camera.snap_to(player)
	arena_respawns += 1
	if hud:
		hud.show_player_bar()
		hud.toast("RESPAWNED", UiKit.GOOD)


## The arena's hero swap (pass 55, Garry: "an option in the hero tab of the Arena Debug menu which allows switching
## between heroes on the fly"; ArenaPanel's HERO tab): hero `id` takes over where he stands. His trait replaces the old
## one on the sheet (max health follows: a rise brings the same health with it, a fall keeps the share), the old hero's perks leave with him and the new one's are
## not handed over (ITEMS hands perks out), nor is his start weapon (ITEMS again); the weapons, passives and mutations
## held stay, god mode stays as it was, Buck's momentum, Calavera's Crescendo and Fadeaway's Heat start from nothing. He wears the look
## kept for him (Save.hero_look). Run.character stays the hero's own def: only the Player's strip wears a look. Returns
## whether the hero changed (false for the one playing, an unknown id, or outside the arena).
func arena_swap_hero(id: String) -> bool:
	var def: CharacterDef = Registry.character(id)
	if def == null or player == null or not Run.arena or (Run.character != null and Run.character.id == id):
		return false
	var old: CharacterDef = Run.character
	if old:
		for pk in Run.perks.duplicate():
			var pd: PerkDef = Registry.perk(str(pk))
			if pd and pd.hero == old.id:
				Run.perks.erase(pk)
	# Serenade's gold disc lies under him only while the perk is held
	if not Run.has_perk("serenade") and _serenade_disc >= 0 and telegraphs:
		telegraphs.release(_serenade_disc)
		_serenade_disc = -1
	Run.character = def
	Run.momentum = 0.0
	Run.momentum_def = def.momentum
	Run.crescendo = 0
	# pass 67: Fadeaway's Heat and his perks' clocks start from nothing too (the perks come back through ITEMS)
	Run.heat = 0
	_timeout_t = -1.0
	_periodic_t.clear()
	player.setup(def)
	Run.rebuild_sheets()
	# build_changed brings refresh_stats in a live game (_sync_weapons); once more here does no harm, and a bare one needs it
	player.refresh_stats()
	if hud:
		hud.toast(def.display_name.to_upper(), UiKit.INFO)
	return true


## The run's gold at its end (out of end_run, pass 70): the whole purse goes to the save, as an extraction's always did
## (pass 44), and since pass 70 (Garry: "Make Coins stay if Player dies") a death's and an abandon's too: reason
## "run_bank" for every end (run_end's result says which). Writes Run.last_result for the Results screen ("lost" stays
## in it for older readers and is 0 now); returns what was banked. end_run calls it once (_ended).
static func bank_run_end(map_id: String) -> int:
	var gold := Run.run_gold
	Run.last_result = {"gold_before": Save.gold(), "banked": gold, "lost": 0,
		"strongbox": Run.banked_gold, "prev_best": Save.best_run(map_id).duplicate()}
	if gold > 0:
		Save.add_gold(gold, "run_bank")
	return gold


func end_run() -> void:
	# whatever screens waited their turn are not coming (pass 60)
	_modal_queue.clear()
	_modal = Modal.NONE
	if Run.arena:
		leave_arena()
		return
	if _ended:
		return
	_ended = true
	tether_end()
	director.stop()
	# the run's gold comes home with the hero, whatever the end (pass 70: bank_run_end)
	var map_id := Run.map.id if Run.map else ""
	bank_run_end(map_id)
	Save.record_run(map_id, Run.elapsed, Run.level, Run.stage + 1, Run.kills)
	# after the run is counted, so "play N runs" sees this one
	QuestTracker.check_all(true)
	Save.flush()
	if RunAnalytics.I: RunAnalytics.I.finish()
	Run.end()
	Audio.stop_music()
	await get_tree().create_timer(1.2).timeout
	set_paused(false)
	UiFx.go(get_tree(), RESULTS)


func abandon_run() -> void:
	if RunAnalytics.I: RunAnalytics.I.abandoned = true
	Run.died = true
	end_run()


# ---------------------------------------------------------------- helpers used by systems

func telegraph_sector(center: Vector3, dir: Vector3, r: float, deg: float, dur: float, color: Color) -> void:
	telegraphs.sector(Vector3(center.x, map.height_at(center.x, center.z), center.z) if map else center, dir, r, deg, dur, color)


## A ground patch that keeps working for a while: damage through `w` every `tick`, and a slow (Zone).
func spawn_zone(at: Vector3, radius: float, seconds: float, dps: float, tick: float, w: WeaponInstance, slow: float = 0.0, color: Color = Color(0.4, 0.75, 1.0, 0.4)) -> Zone:
	var z := Zone.new()
	z.setup(self, w, radius, seconds, dps, tick, slow, color)
	z.position = Vector3(at.x, map.height_at(at.x, at.z) if map else at.y, at.z)
	add_child(z)
	return z


## The Singularity's black hole where its shot came down (pass 35, Vortex.gd).
func spawn_vortex(at: Vector3, w: WeaponInstance, radius: float, cfg: Dictionary, shot_damage: float) -> void:
	var v := Vortex.new()
	v.setup(self, w, radius, cfg, shot_damage)
	v.position = Vector3(at.x, map.height_at(at.x, at.z) if map else at.y, at.z)
	add_child(v)


func telegraph_ring(center: Vector3, r: float, dur: float, color: Color, filled := true) -> void:
	telegraphs.ring(center, r, dur, color, filled)


func telegraph_line(from: Vector3, dir: Vector3, length: float, dur: float, color: Color) -> void:
	telegraphs.line(from, dir, length, dur, color)


func shockwave(center: Vector3, r: float) -> void:
	telegraphs.flash_ring(center, r, Color(1.0, 0.6, 0.3), 0.4)
	fx.burst(center + Vector3(0, 0.5, 0), Color(1.0, 0.7, 0.4), r * 0.6)
	camera.shake(1.0)


## A body going off: the hero takes `damage` inside `r`, and so does the crowd, for a fifth of it, thrown outwards
## (pass 30: a mine crab clears a path through its own pack). `delay` 0 fires at once, anything else draws a red ring
## and waits on a pause-respecting clock (pass 60: a blast scheduled before a level-up waits until the cards close, with
## its ring, instead of going off under them while his invulnerability stood still).
func elite_explosion(center: Vector3, r: float, damage: float, delay: float, knockback: float = 0.0, friendly_frac: float = 0.2, info: Dictionary = {}) -> void:
	if delay > 0.0:
		telegraphs.ring(center, r, delay, UiKit.DANGER, true)
	var boom := func():
		if _ended or player == null:
			return
		var d := player.global_position - center
		d.y = 0.0
		if d.length() <= r + 0.4:
			var binfo: Dictionary = info.duplicate(true)
			if knockback > 0.0:
				(binfo.get("fx", []) as Array).append("thrown")
			player.take_damage(damage, center, binfo)
			if knockback > 0.0 and player.has_method("apply_knockback") and d.length_squared() > 0.01:
				player.apply_knockback(d.normalized() * knockback)
		if friendly_frac > 0.0:
			enemies.damage_radius(center, r, damage * friendly_frac, "blast", knockback * 0.8)
		fx.burst(center + Vector3(0, 0.6, 0), UiKit.DANGER, r * 0.7)
		telegraphs.flash_ring(center, r, Color(1.0, 0.55, 0.25), 0.35)
		camera.shake(0.6)
		Audio.play("w_lob_boom", center)
	if delay <= 0.0:
		boom.call()
		return
	var t := get_tree().create_timer(delay, false)
	t.timeout.connect(boom)


func enemy_spit(from: Vector3, target: Vector3, speed: float, damage: float, splash: float, info: Dictionary = {}) -> void:
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var dist: float = max(flat.length(), 0.5)
	var t: float = clamp(dist / max(speed, 1.0), 0.4, 2.0)
	var vy := ((target.y - from.y) + 0.5 * 24.0 * t * t) / t
	projectiles.hostile_shot(_spit_kind, from, flat / t + Vector3(0, vy, 0), damage, splash, t + 0.5, true, {"info": info})


## A straight hostile shot (the slinger's stone, the spider's silk): no arc, at the hero's current position.
func enemy_shot_straight(from: Vector3, target: Vector3, speed: float, damage: float, splash: float, params: Dictionary = {}) -> void:
	var dir := Vector3(target.x - from.x, 0, target.z - from.z)
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	var p := params.duplicate()
	p["origin"] = from
	var kind: int = _spit_kind
	match str(params.get("shot", "")):
		"pellet":
			kind = _pellet_kind
		"spike":
			kind = _spike_kind
		"shard":
			kind = _shard_kind
	if bool(params.get("harpoon", false)):
		kind = _harpoon_kind
	var pi := projectiles.hostile_shot(kind, from, dir.normalized() * speed, damage, splash, float(params.get("life", 1.4)), false, p)
	if bool(params.get("harpoon", false)) and pi >= 0:
		_harpoon_proj = pi
		_harpoon_shooter = int(params.get("shooter", -1))


## The Tumbleweed King's volley (pass 45): `count` tumbleweeds roll out from `at` in every direction, the first down
## `first` (the spokes' phase), at `speed` for `life` seconds (9 m/s x 2.6 s: about 24 m, so he reaches a hero across
## the screen). Each hits the hero once: `damage`, and a throw back of `knockback` with `lift` (Player.blast, past the
## shove's cap). They roll (params.roll = their radius) and raise dust; they are hostile shots, so High Noon slows them.
func tumbleweed_volley(at: Vector3, first: Vector3, count: int, speed: float, damage: float, life: float, knockback: float, lift: float, info: Dictionary) -> void:
	var phase := atan2(first.z, first.x) if first.length_squared() > 0.0001 else 0.0
	var ground: float = map.height_at(at.x, at.z) if map else at.y
	var from := Vector3(at.x, ground + TUMBLE_R, at.z)
	for k in range(count):
		var a := phase + TAU * float(k) / float(maxi(count, 1))
		var dir := Vector3(cos(a), 0, sin(a))
		projectiles.hostile_shot(_tumble_kind, from + dir * 1.2, dir * speed, damage, 0.0, life, false,
			{"shot": "tumbleweed", "roll": TUMBLE_R, "hit_radius": 0.6, "knockback": knockback, "lift": lift, "info": info, "origin": from})
	fx_sand(from + Vector3(0, 0.3, 0), 3.0)
	if camera:
		camera.shake(0.5)
	Audio.play("en_king_volley", at)


# ---------------------------------------------------------------- the harpoon tether

func _harpoon_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.07, 0.07, 1.0)
	return b


func _harpoon_material() -> Material:
	# bright red, lit from inside: the one thing on the line the hero must not be under
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.12, 0.08)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.1)
	m.emission_energy_multiplier = 2.0
	m.metallic = 0.2
	m.roughness = 0.4
	return m


## Lead shot from the dwarf's blunderbuss: a small dark ball, dull, so a cone of five reads as buckshot.
func _pellet_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.13
	s.height = 0.26
	s.radial_segments = 6
	s.rings = 3
	return s


func _pellet_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.2, 0.23)
	m.metallic = 0.7
	m.roughness = 0.35
	return m


## The King's tumbleweed (pass 45) is the desert's own model (art/props/tumbleweed.glb: a 0.8 m wire ball of twigs,
## the one world/features/Tumbleweed.gd rolls); the mesh alone, centred, so a MultiMesh can draw a dozen. A lattice
## sphere stands in without the file.
func _tumble_mesh() -> Mesh:
	if ResourceLoader.exists("res://art/props/tumbleweed.glb"):
		var scene: Node = load("res://art/props/tumbleweed.glb").instantiate()
		var found: Mesh = null
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			found = (n as MeshInstance3D).mesh
			break
		scene.free()
		if found:
			return found
	var s := SphereMesh.new()
	s.radius = 0.8
	s.height = 1.6
	s.radial_segments = 8
	s.rings = 5
	return s


## Jet black (pass 48, Garry): the King's own tumbleweeds are his, not the desert's straw-coloured ones.
const TUMBLE_BLACK := Color(0.035, 0.03, 0.03)


func _tumble_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = TUMBLE_BLACK
	m.roughness = 0.85
	return m


## The Sun Idol's shard: a shaving of lit gold stone, flat and pointed, flying point first along -Z.
func _shard_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.16
	var h := 0.05
	var back := 0.3
	var tip := -0.5
	var quad := [Vector3(-w, -h, back), Vector3(w, -h, back), Vector3(w, h, back), Vector3(-w, h, back)]
	for k in range(4):
		var p0: Vector3 = quad[k]
		var p1: Vector3 = quad[(k + 1) % 4]
		for v in [p0, p1, Vector3(0, 0, tip)]:
			st.add_vertex(v)
		for v in [Vector3(0, 0, back), p1, p0]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _shard_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.82, 0.35)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 2.2
	m.metallic = 0.2
	m.roughness = 0.35
	return m


## The Sun Idol's column: a shaft of gold light that brightens on the spot for `warn` seconds and flashes when it lands.
func light_pillar(at: Vector3, r: float, warn: float) -> void:
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.85
	cm.bottom_radius = r * 0.85
	cm.height = 14.0
	cm.radial_segments = 18
	cm.rings = 1
	col.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.06)
	col.material_override = mat
	col.position = at + Vector3(0, 7.0, 0)
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.5, warn).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.chain().tween_callback(col.queue_free)


## The centipede's spike: a hard black barb that flies point first. Built along -Z (the way a projectile's basis
## points, Basis.looking_at(velocity)); a CylinderMesh stands along Y, which made the barb fly sideways and tumble.
func _spike_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 7
	var r := 0.13
	var back := 0.34
	var tip := -0.44
	for k in range(segs):
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, back)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, back)
		for v in [p0, p1, Vector3(0, 0, tip)]:
			st.add_vertex(v)
		for v in [Vector3(0, 0, back), p1, p0]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _spike_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.1, 0.12)
	m.metallic = 0.3
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = Color(0.7, 0.35, 0.1)
	m.emission_energy_multiplier = 0.5
	return m


# ---------------------------------------------------------------- the rocketeer's rocket

## The Vulture Raider's rocket (pass 48): art/props/enemy_rocket.glb, one mesh painted in vertex colours (a near-black
## body, dark red warhead band and fins, a steel nozzle, a hot orange exhaust cup), its node's turn baked in so the nose
## points down -Z like every projectile; the procedural one below, painted the same, without the file.
const ROCKET_GLB := "res://art/props/enemy_rocket.glb"


func _rocket_mesh() -> Mesh:
	if ResourceLoader.exists(ROCKET_GLB):
		var scene: Node = load(ROCKET_GLB).instantiate()
		var found: Mesh = null
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, 0, mi.transform)
			found = st.commit()
			break
		scene.free()
		if found:
			return found
	return _rocket_mesh_drawn()


## A rocket, not a pill: a body, a nose cone and three fins, all one mesh so it can be a projectile kind, painted in
## vertex colours as the model is (pass 48: the shader paints COLOR and glows only on the hot exhaust).
func _rocket_mesh_drawn() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.05, 0.05, 0.05)
	var band := Color(0.3, 0.05, 0.0)
	var hot := Color(1.0, 0.45, 0.1)
	var segs := 10
	var r := 0.17
	var body_back := 0.42
	var body_front := -0.24
	var nose := -0.62
	for k in range(segs):
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
		# the body, wound so the outside faces out
		st.set_color(body)
		for v in [p0 + Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_front),
				p0 + Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_front), p0 + Vector3(0, 0, body_front)]:
			st.add_vertex(v)
		# the nose cone
		st.set_color(band)
		for v in [p0 + Vector3(0, 0, body_front), p1 + Vector3(0, 0, body_front), Vector3(0, 0, nose)]:
			st.add_vertex(v)
		# the tail cap: the hot exhaust
		st.set_color(hot)
		for v in [Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_back), p0 + Vector3(0, 0, body_back)]:
			st.add_vertex(v)
	# three fins at the tail
	st.set_color(band)
	for k in range(3):
		var a := TAU * float(k) / 3.0
		var out := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0) * 0.02
		var a0 := out * r * 0.9 + Vector3(0, 0, body_back)
		var b0 := out * r * 2.1 + Vector3(0, 0, body_back + 0.1)
		var c0 := out * r * 0.9 + Vector3(0, 0, body_back - 0.28)
		for sgn in [1.0, -1.0]:
			for v in [a0 + side * sgn, b0 + side * sgn, c0 + side * sgn]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A projectile kind's MultiMesh with instance colours on, every one white (pass 48, the vertex-painted rocket). A MultiMesh
## with custom data and no colours hands a spatial shader COLOR = 0 in Godot 4.7 (a capture showed the dark rocket bright
## yellow: no paint, and its exhaust mask everywhere), so the rocket kind carries white colours and COLOR is the paint.
## Call it before anything is drawn: the count is rebuilt.
static func paint_white(mm: MultiMesh) -> void:
	var n := mm.instance_count
	var vis := mm.visible_instance_count
	mm.instance_count = 0
	mm.use_colors = true
	mm.instance_count = n
	mm.visible_instance_count = vis
	for k in range(n):
		mm.set_instance_color(k, Color(1, 1, 1, 1))


## The rocket's paint (its vertex colours) on a shader that lights only the hot exhaust, and turns the whole of it
## white-hot by the instance's heat (pass 45: a loose rocket blinks red and white, then burns white through its climb
## and dive). Pass 48: dark on the sand, no longer a red glow all over.
func _rocket_material() -> Material:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/shaders/rocket.gdshader")
	return m


## A rocketeer fired: one slow rocket that hunts the hero, from his launcher's open end (EnemyManager.muzzle_point); only
## his death ends it early.
## `speed_of_hero` > 0: the rocket flies at that fraction of the hero's top speed, whatever he is carrying (pass 33.2).
func enemy_missile(shooter: int, from: Vector3, speed: float, turn: float, damage: float, area: float, speed_of_hero: float = 0.0, info: Dictionary = {}, blast: Dictionary = {}) -> void:
	var dir := player.global_position + Vector3(0, 0.9, 0) - from
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	projectiles.launch_enemy_rocket(_rocket_kind, shooter, from, dir.normalized(), speed, turn, damage, area, speed_of_hero, info, blast)
	fx.burst(from, Color(1.0, 0.5, 0.2), 1.2)
	hint_once("rocketeer", "ROCKETEER: his rocket hunts you. Follow its smoke line back to him: kill him and it loses you.")


## Whether the rocketeer at creature index `shooter` has his rocket in the air (he reloads only once it is gone).
func rocket_out(shooter: int) -> bool:
	return projectiles != null and projectiles.has_rocket_of(shooter)


## The rocketeer's rocket goes off (pass 33.3). The hero inside `r` takes the rocket's damage as before and is thrown
## hard off his feet (`blast.knockback` away, `blast.lift` up; an evade leaves him standing), and every creature within
## `blast.throw_radius` is thrown clear by `blast.throw`, unhurt. A fireball the whole screen sees, bigger and with a
## hot flash over the screen when it caught the hero, a ring on the ground and a scorch mark that fades.
func rocket_blast(at: Vector3, r: float, damage: float, info: Dictionary, blast: Dictionary) -> void:
	if _ended:
		return
	var ground := Vector3(at.x, map.height_at(at.x, at.z) if map else at.y, at.z)
	var caught := false
	if player and not player.dead:
		var d: Vector3 = player.global_position - at
		d.y = 0.0
		if d.length() <= r + 0.4:
			var binfo: Dictionary = info.duplicate(true)
			if not binfo.has("fx"):
				binfo["fx"] = []
			(binfo["fx"] as Array).append_array(["rocket blast", "thrown"])
			player.take_damage(damage, at, binfo)
			if str(player.get("last_outcome")) != "evaded":
				caught = true
				var away: Vector3 = d if d.length_squared() > 0.01 else -player.forward()
				player.blast(away.normalized() * float(blast.get("knockback", 24.0)), float(blast.get("lift", 6.0)))
	var tr: float = float(blast.get("throw_radius", r * 2.5))
	enemies.throw_radius(ground, tr, float(blast.get("throw", 20.0)))
	fx.explosion(ground, maxf(r, 1.2) * (1.3 if caught else 1.0))
	telegraphs.flash_ring(ground, tr, Color(1.0, 0.55, 0.2), 0.45)
	_scorch(ground, maxf(r, 1.2) * 1.2)
	camera.shake(2.6 if caught else 1.3)
	if caught:
		hud.flash(Color(1.0, 0.45, 0.12, 0.45), 0.4)
	Audio.play("en_rocket_boom", at)


## A loose rocket's warning (pass 45): a red ring on the sand under the crowd it will dive on, blinking with the rocket
## (ProjectileManager._tick_loose_mark owns the alpha and moves it with the crowd; _free releases it).
func loose_mark(at: Vector3, r: float) -> int:
	if telegraphs == null:
		return -1
	return telegraphs.hold_ring(_on_ground(at), r, Color(1.0, 0.22, 0.1, 0.9))


func loose_mark_move(id: int, at: Vector3, alpha: float) -> void:
	if telegraphs == null or id < 0:
		return
	telegraphs.move_held(id, _on_ground(at))
	telegraphs.set_alpha(id, alpha)


func loose_mark_end(id: int) -> void:
	if id >= 0 and is_instance_valid(telegraphs):
		telegraphs.release(id)


func _on_ground(at: Vector3) -> Vector3:
	return Vector3(at.x, map.height_at(at.x, at.z) if map else at.y, at.z)


## A loose rocket comes down on the crowd (pass 45): the pass 33.3 fireball, the crowd thrown by the rocket's own
## `blast.throw` within `blast.throw_radius`, a ring, a scorch and a kick; the hero is never touched (the scratch of
## damage to the crowd is ProjectileManager._explode_loose's).
func loose_rocket_blast(at: Vector3, r: float, blast: Dictionary) -> void:
	if _ended:
		return
	var ground := _on_ground(at)
	var reach: float = maxf(float(blast.get("throw_radius", r * 2.0)), r)
	enemies.throw_radius(ground, reach, float(blast.get("throw", 20.0)))
	fx.explosion(ground, maxf(r, 1.2))
	telegraphs.flash_ring(ground, reach, Color(1.0, 0.55, 0.2), 0.45)
	_scorch(ground, maxf(r, 1.2) * 1.2)
	camera.shake(1.3)
	Audio.play("en_rocket_boom", at)


# ---------------------------------------------------------------- the golem's stone (pass 45)

const STONE := Color(0.5, 0.46, 0.42)
const BOULDER_SCRIPT := preload("res://core/systems/Boulder.gd")
var _stone_mat: StandardMaterial3D
var _stalactite_mesh: Mesh


func stone_material() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_color = STONE
		_stone_mat.roughness = 0.95
	return _stone_mat


## The golem winds up and throws: the rock leaves `from` and comes down at `to` (the ring it marked) `flight` seconds
## later whatever the hero does. The attack's numbers ride along: radius, damage (x `mult`, the stage), knockback, lift,
## creature_frac, throw, throw_radius, size, arc.
func throw_boulder(thrower: int, from: Vector3, to: Vector3, atk: Dictionary, mult: float, info: Dictionary) -> void:
	if _ended:
		return
	var cfg := {"radius": float(atk.get("radius", 4.6)), "damage": float(atk.get("damage", 30)) * mult,
		"knockback": float(atk.get("knockback", 26.0)), "lift": float(atk.get("lift", 6.0)), "creature_frac": float(atk.get("creature_frac", 0.5)),
		"throw": float(atk.get("throw", 22.0)), "throw_radius": float(atk.get("throw_radius", 6.5)), "size": float(atk.get("size", 1.7)), "arc": float(atk.get("arc", 9.0))}
	var ground := Vector3(to.x, map.height_at(to.x, to.z) if map else to.y, to.z)
	# by path, not by class name: a headless run before the next import does not know a new class_name yet
	var b = BOULDER_SCRIPT.new()
	b.setup(self, from, ground, float(atk.get("flight", 1.6)), cfg, info, thrower)
	add_child(b)
	Audio.play("en_golem_throw", from)


## The boulder comes down (rocket_blast's shape in stone): the hero inside `radius` takes `damage` and is thrown with
## `knockback`/`lift` (an evade leaves him standing); the crowd takes `creature_frac` of it and is thrown out to
## `throw_radius` with `throw`, the golem itself never; a burst, stone splinters, sand, a crater mark, a kick, a flash.
func boulder_land(at: Vector3, cfg: Dictionary, info: Dictionary, thrower: int = -1) -> void:
	if _ended:
		return
	var ground := Vector3(at.x, map.height_at(at.x, at.z) if map else at.y, at.z)
	var r: float = float(cfg.get("radius", 4.6))
	var bdmg: float = float(cfg.get("damage", 30.0))
	var caught := false
	if player and not player.dead:
		var d: Vector3 = player.global_position - ground
		d.y = 0.0
		if d.length() <= r + 0.4:
			player.take_damage(bdmg, ground, info.duplicate(true))
			if str(player.get("last_outcome")) != "evaded":
				caught = true
				var away: Vector3 = d if d.length_squared() > 0.01 else -player.forward()
				player.blast(away.normalized() * float(cfg.get("knockback", 26.0)), float(cfg.get("lift", 6.0)))
	var frac: float = float(cfg.get("creature_frac", 0.5))
	if frac > 0.0:
		for j in enemies.indices_in_radius(ground, r):
			if j != thrower:
				enemies.damage(j, bdmg * frac, "blast", enemies.pos[j] - ground, 0.0)
	var tr: float = float(cfg.get("throw_radius", r * 1.4))
	enemies.throw_radius(ground, tr, float(cfg.get("throw", 22.0)), thrower)
	fx.explosion(ground, 1.2 * (1.3 if caught else 1.0))
	fx.splinters(ground, STONE, 22, 0.3)
	for k in range(6):
		var a := TAU * float(k) / 6.0
		fx.sand(ground + Vector3(cos(a), 0.1, sin(a)) * r * 0.5, 1.4)
	telegraphs.flash_ring(ground, tr, Color(0.9, 0.7, 0.45), 0.45)
	_scorch(ground, r * 0.55)
	camera.shake(2.4 if caught else 1.6)
	if caught:
		hud.flash(Color(0.75, 0.6, 0.45, 0.35), 0.3)
	Audio.play("en_boulder_land", ground)


## One stalactite of the swoop: a stone spike drops from `height` metres onto `at` over `fall` seconds, stands in the
## sand a moment and sinks away. The impact itself is stalactite_hit, called by EnemyManager when the spike's clock
## runs out, so the picture and the hit agree.
func stalactite(at: Vector3, fall: float, spike_scale: float = 1.0, height: float = 9.0) -> void:
	if _stalactite_mesh == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.24
		cm.height = 1.5
		cm.radial_segments = 6
		cm.rings = 1
		_stalactite_mesh = cm
	var m := MeshInstance3D.new()
	m.mesh = _stalactite_mesh
	m.material_override = stone_material()
	m.rotation.x = PI                      # the cone's point is +Y; turned over it falls point first
	m.scale = Vector3.ONE * spike_scale
	m.position = at + Vector3(0, height, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var tw := create_tween()
	tw.tween_property(m, "position:y", at.y + 0.55 * spike_scale, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.5)
	tw.tween_property(m, "position:y", at.y - 1.2 * spike_scale, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(m.queue_free)


## A stalactite lands: stone chips, a puff of sand, a small ring and a kick (the throw and the hit are EnemyManager's).
func stalactite_hit(at: Vector3) -> void:
	fx.splinters(at, STONE, 7, 0.16)
	fx.sand(at + Vector3(0, 0.2, 0), 0.8)
	telegraphs.flash_ring(at, 1.0, Color(0.85, 0.7, 0.5), 0.25)
	camera.shake(0.25)
	Audio.play("en_stalactite_hit", at)


## A dark scorch on the sand where something went off: it holds a moment, then fades out (a pooled ground mark).
func _scorch(at: Vector3, r: float) -> void:
	telegraphs.scorch(at, r, Color(0.1, 0.06, 0.05, 0.6), Color(0.22, 0.14, 0.1, 0.0), 1.5, 3.0)


## Every creature death, by index (EnemyManager): its splash (pass 58), the rockets of a dead rocketeer go with it, and
## so does the rope.
func on_creature_died_index(i: int) -> void:
	_death_splash(i)
	projectiles.kill_rockets_of(i)
	if tether_i == i:
		tether_end()
	if enemies.bounty_i == i:
		# the bounty is paid: gold and a chest where it fell
		enemies.bounty_i = -1
		var at: Vector3 = enemies.pos[i]
		var gold := int(Run.perk_param("bounty_hunter", "gold", 40.0))
		Run.add_gold(gold, "bounty")
		pickups.spawn_chest(at)
		fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.82, 0.35), 1.3)
		hud.toast("BOUNTY +%d" % gold, Color(1.0, 0.82, 0.35))
		Audio.play("pk_coin", at)
	_count_bounty()


## The death splash (pass 58, Garry: "Add a red splash VFX effect ... to enemies when they die ... This way it will make
## it easier to tell when an enemy died ... The colour ... is different for different enemies"): Fx.blood in the
## creature's own `blood` (EnemyDef.blood, its JSON, the Level Editor's Creatures tab) at its body, sized by the size it
## was drawn at (variance, an elite modifier, a split, a row's size range; never the def's JSON `size`): EnemyManager's
## size[i], the very value its `died_size` carries while enemy_died is out (this hook runs just after, when died_size is
## back to 0, and has the index), bigger for an Elite, an elite-modded creature and a boss; a creature that dies in the air
## (thrown, lifted, bounced) splashes up there. One buried out of sight (hidden) splashes nothing.
func _death_splash(i: int) -> void:
	if fx == null or enemies == null or i < 0 or i >= enemies.size.size() or enemies.hidden[i] == 1:
		return
	var def: EnemyDef = enemies.types[enemies.type_idx[i]]["def"]
	var big := 0
	if def.archetype == "boss" or i == enemies.boss_index:
		big = 2
	elif def.archetype == "elite" or enemies.elite_idx[i] >= 0:
		big = 1
	fx.blood(enemies.pos[i] + Vector3(0.0, enemies.lift_h[i], 0.0), def.blood, enemies.size[i], big)


# ---------------------------------------------------------------- the eruption's mounds

## The sand swells under an eruption ring for `warn` seconds: a mound rising and cracking, then it bursts (the young
## come up through it, EnemyManager._tick_rains). A 3D thing on the spot, not a puff.
func erupt_mound(at: Vector3, r: float, warn: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r * 0.85
	sm.height = r * 0.85
	sm.radial_segments = 14
	sm.rings = 6
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.42)
	mat.roughness = 1.0
	m.material_override = mat
	m.position = at + Vector3(0, -r * 0.3, 0)
	m.scale = Vector3(0.2, 0.05, 0.2)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	# cracks: a dark ring that widens as the mound rises
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.35
	tm.outer_radius = r * 0.5
	tm.rings = 16
	tm.ring_segments = 5
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.36, 0.22, 0.12)
	rmat.roughness = 1.0
	ring.material_override = rmat
	ring.position = at + Vector3(0, 0.08, 0)
	# lying on the slope it opens in (pass 52), not level through it
	if map:
		ring.basis = MapBase.ground_basis(map.normal_at(at.x, at.z, r * 0.5))
	ring.scale = Vector3(0.3, 0.5, 0.3)
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(1.0, 0.75, 1.0), warn).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "position:y", at.y + r * 0.05, warn).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, "scale", Vector3(1.6, 0.6, 1.6), warn).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		# the burst: the mound pops open and falls away in clods
		fx.burst(at + Vector3(0, 0.3, 0), Color(0.86, 0.7, 0.45), r * 1.6)
		for k in range(8):
			var a := TAU * float(k) / 8.0
			var clod := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.25, 0.18, 0.25) * r
			clod.mesh = cm
			clod.material_override = mat
			clod.position = at + Vector3(cos(a) * r * 0.4, 0.3, sin(a) * r * 0.4)
			clod.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
			add_child(clod)
			var ct := create_tween()
			ct.set_parallel(true)
			ct.tween_property(clod, "position", clod.position + Vector3(cos(a) * r * 1.4, -0.1, sin(a) * r * 1.4), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			ct.tween_property(clod, "position:y", at.y + 1.4, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			ct.chain().tween_property(clod, "position:y", at.y - 0.3, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			ct.chain().tween_callback(clod.queue_free)
		m.queue_free()
		ring.queue_free())


# ---------------------------------------------------------------- the nuke

## The Nuke: a wave from the hero that hits everything within `radius` for `damage` and throws it back, with a ring
## that races out over the sand, a flash and a long shake. Bosses take it too.
func nuke_blast(at: Vector3, radius: float, damage: float, knock: float) -> void:
	if damage > 0.0:
		enemies.damage_radius(at, radius, damage, "nuke", knock)
	else:
		# the revive's ring (pass 48): no damage, so no hit at all (a zero hit still flashed, rolled crits and froze), only
		# the throw
		enemies.hero_throw_radius(at, radius, knock)
	# the wave: a fat band racing out to the radius over half a second, laid on the sand (pass 52: it was a flat torus at
	# the hero's height, and every hill on its way cut through it)
	telegraphs.race_ring(at, radius, 0.55, Color(1.0, 0.75, 0.35, 0.9), 0.3)
	var wall := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 2.4
	cm.radial_segments = 40
	cm.rings = 1
	wall.mesh = cm
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.albedo_color = Color(1.0, 0.55, 0.2, 0.55)
	wall.material_override = wmat
	wall.position = at + Vector3(0, 1.2, 0)
	wall.scale = Vector3(0.3, 1.0, 0.3)
	add_child(wall)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(wall, "scale", Vector3(radius, 1.0, radius), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(wmat, "albedo_color:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): wall.queue_free())
	fx.burst(at + Vector3(0, 1.0, 0), Color(1.0, 0.95, 0.8), 6.0)
	fx.burst(at + Vector3(0, 0.6, 0), Color(1.0, 0.55, 0.2), 9.0)
	for k in range(14):
		var a := TAU * float(k) / 14.0
		fx.sand(at + Vector3(cos(a), 0.1, sin(a)) * radius * 0.5, 1.2)
	telegraphs.flash_ring(at, radius, Color(1.0, 0.6, 0.25), 0.6)
	camera.shake(3.0)
	hud.flash(Color(1.0, 0.9, 0.7, 0.85), 0.5)
	Audio.play("pk_nuke", at)


## Ripples at the hero's feet while he wades (the oasis).
var _ripple_t := 0.0


## The hero comes back: a wave 30% of the nuke's radius that kills the crowd outright (an Elite or a boss only takes
## a share of it) and throws whatever survives.
func revive_blast() -> void:
	var r := 4.8
	var at: Vector3 = player.global_position
	enemies.damage_radius(at, r, 100000.0, "revive", 12.0)
	nuke_blast(at, r, 0.0, 12.0)
	hud.toast("BACK UP", Color(1.0, 0.9, 0.5))


var _berserk_t := 0.0
## Berserk (pass 33): while the hero's weapons run fast, red flames lick up around his feet.
func _tick_berserk(delta: float) -> void:
	if Run.haste <= 1.0 or player == null or player.dead:
		return
	_berserk_t -= delta
	if _berserk_t > 0.0:
		return
	_berserk_t = 0.07
	var a := randf() * TAU
	var at := player.global_position + Vector3(cos(a) * 0.45, 0.05, sin(a) * 0.45)
	fx.flame(at, randf_range(0.9, 1.3), randf_range(0.35, 0.5), Color(1.0, 0.36, 0.1))


## The hero's own buffs where they show: his speed boosts (pass 48, _tick_speed_fx) and Steady Hand's ring at his feet,
## wider and brighter the longer he has stood still (only while he holds it).
func _tick_hero_fx(delta: float) -> void:
	if player == null:
		return
	_tick_speed_fx(delta)
	if player.dead:
		_end_steady_mark()
		return
	_tick_steady(delta)


## Barrel Rush, from BarrelField when a smashed barrel started (`fresh`) or refreshed the boost: a word and a sound when
## it starts (pass 48: the gold burst and ring are gone; the boost shows as its thin ribbon, _tick_speed_fx).
func barrel_rush_fx(fresh: bool) -> void:
	if player == null or player.dead:
		return
	if fresh:
		hud.toast("BARREL RUSH", Fx.RUSH_GOLD)
		Audio.play("pk_powerup", player.global_position)
	_rush_running = true


var _rush_running := false
## The ids of the power-ups that made him faster this run (a Sprint): their look runs while any lasts.
var _speed_buffs: Array = []


## Whether a power-up's buff makes him faster (a positive move_speed effect: the Sprint), read from its data.
static func _speeds_up(def: PickupDef) -> bool:
	for e in def.effects:
		if e is Effect and (e as Effect).stat == "move_speed" and (e as Effect).value > 0.0:
			return true
	return false


## Seconds left of the longest speed power-up he has on (0 when none).
func _speed_buff_left() -> float:
	var left := 0.0
	for id in _speed_buffs:
		left = maxf(left, Run.boost_left(str(id)))
	return left


## Skedaddle's seconds left (Run.skedaddle_left: 0 when it is not running).
func _skedaddle_left() -> float:
	return Run.skedaddle_left()


## His speed boosts, each its own look so two or three read together (pass 48, Garry: "the speed VFX after a barrel looks
## bad, simpler; a different, stronger one for the movement power-up; both must work together"): Barrel Rush is one thin
## faint gold ribbon at his hips, a Sprint a strong blue ribbon higher up with wind streaming past him, Skedaddle a red
## ribbon low down (Fx.speed_trail, Fx.wind). Each ribbon follows him while he runs and shrinks away when he stops or
## the boost ends.
func _tick_speed_fx(delta: float) -> void:
	var up: bool = not player.dead
	var rush_on := _rush_running
	if Engine.get_process_frames() % 6 == 0 or rush_on:
		rush_on = Run.boost_left(Run.BARREL_RUSH) > 0.0
		_rush_running = rush_on
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var moving: bool = up and flat.length() > 0.6
	var feet: Vector3 = player.global_position
	if rush_on or fx.speed_trail_live("gold"):
		fx.speed_trail("gold", feet, delta, rush_on and moving)
	var sprint_on: bool = up and not _speed_buffs.is_empty() and _speed_buff_left() > 0.0
	if sprint_on or fx.speed_trail_live("blue"):
		fx.speed_trail("blue", feet, delta, sprint_on and moving)
	if sprint_on or fx.wind_live():
		fx.wind(feet, flat if moving else player.forward(), delta, sprint_on, moving)
	var red_on: bool = up and _skedaddle_left() > 0.0
	if red_on or fx.speed_trail_live("red"):
		fx.speed_trail("red", feet, delta, red_on and moving)


## Steady Hand's ring (pass 47): a held ground ring under his feet, red-gold, from 0.7 m to 1.2 m and from faint to bright
## as the bonus grows to its top (Run.steady_might, +100%), breathing once it is there; embers rise off it, faster as it
## grows. Gone the moment he moves.
const STEADY_COLOUR := Color(1.0, 0.45, 0.2)
var _steady_mark := -1
var _steady_mote_t := 0.0


func _tick_steady(delta: float) -> void:
	var f := _steady_frac()
	if f <= 0.0:
		_end_steady_mark()
		return
	var here: Vector3 = player.global_position
	var g := Vector3(here.x, map.height_at(here.x, here.z) if map else here.y, here.z)
	var r := lerpf(0.7, 1.2, f)
	if _steady_mark < 0:
		_steady_mark = telegraphs.hold_ring(g, r, Color(STEADY_COLOUR, 1.0))
	telegraphs.move_held(_steady_mark, g, r)
	var pulse := 1.0 if f < 1.0 else 0.82 + 0.18 * sin(float(Time.get_ticks_msec()) * 0.008)
	telegraphs.set_alpha(_steady_mark, lerpf(0.22, 0.7, f) * pulse)
	_steady_mote_t -= delta
	if _steady_mote_t <= 0.0:
		_steady_mote_t = lerpf(0.45, 0.12, f)
		var a := randf() * TAU
		fx.mote(g + Vector3(cos(a) * r * 0.8, 0.12, sin(a) * r * 0.8), Vector3(0, 1.3 + f, 0), 0.6, 0.12 + 0.1 * f, Color(1.0, 0.62, 0.3, 0.9))


## How far Steady Hand has grown, 0 to 1 of its top (Run.STEADY_MAX, +100%); always 0 when he does not hold it (Run only
## counts buckets of the passive's `still_might`).
func _steady_frac() -> float:
	return clampf(Run.steady_might() / Run.STEADY_MAX, 0.0, 1.0)


func _end_steady_mark() -> void:
	if _steady_mark >= 0:
		telegraphs.release(_steady_mark)
		_steady_mark = -1


## The lake (pass 54 for the shadows and the waders): the hero casts no shadow while he stands in the water (its blob lay
## on the lake bed and drew over the water as a dark plate; EnemyManager skips the creatures' the same way), and every
## 0.28 s whoever wades shows it: rings on the water's surface (lifted off the lake bed the marks drape, by the map's
## water_level, 0.3 m without one) round the hero and round up to 12 creatures that move in it, and a little splash.
## Every frame he also sinks into it like the creatures, and his shadow goes wherever the drawn water covers any of it
## (pass 56, _sink_hero).
## The hero's blob on the ground under him (pass 65): the flat quad cut into any slope, so every frame it is laid on the
## ground at his feet (EnemyManager.drape, the creatures' rule), turned with him at Player.shadow_scale; it stays on the
## sand while he jumps (it grows there, as before).
func _drape_hero_shadow() -> void:
	if player == null or map == null or player.shadow == null or player.cinematic:
		return
	var at: Vector3 = player.global_position
	var flat := Basis(Vector3.UP, player.rotation.y) * Basis.from_scale(player.shadow_scale)
	var quad := player.shadow.mesh as QuadMesh
	var ext: float = quad.size.x if quad else 1.4
	player.shadow.global_transform = EnemyManager.drape(Transform3D(flat, Vector3(at.x, 0.0, at.z)), map.height_at, ext)


func _tick_water(delta: float) -> void:
	if map == null or not map.has_method("in_water") or player == null or player.dead:
		return
	var wet: bool = map.call("in_water", player.global_position)
	_sink_hero(wet)
	_ripple_t -= delta
	if _ripple_t > 0.0:
		return
	_ripple_t = 0.28
	var has_level: bool = map.has_method("water_level")
	var level: float = float(map.call("water_level")) if has_level else 0.0
	if wet:
		var moving: bool = player.velocity.length() > 0.5
		var at: Vector3 = player.global_position
		var lift: float = maxf(level - map.height_at(at.x, at.z), 0.0) if has_level else 0.3
		telegraphs.flash_ring(at, 0.55 if moving else 0.35, Color(0.9, 0.98, 1.0), 0.45, lift)
		if moving:
			fx.burst(Vector3(at.x, maxf(at.y, level), at.z) + Vector3(0, 0.25, 0), Color(0.85, 0.95, 1.0), 0.5)
	if enemies == null or not map.has_method("lake_center") or not map.has_method("lake_radius"):
		return
	var lr: float = float(map.call("lake_radius"))
	if lr <= 0.0:
		return
	var lc: Vector2 = map.call("lake_center")
	var n := 0
	for i in enemies.indices_in_radius(Vector3(lc.x, 0.0, lc.y), lr * 1.02):
		if n >= 12:
			break
		if enemies.vel[i].length() <= 0.5 or enemies.lift_h[i] > 0.05:
			continue
		var p: Vector3 = enemies.pos[i]
		var plift: float = maxf(level - map.height_at(p.x, p.z), 0.0) if has_level else 0.3
		telegraphs.flash_ring(p, 0.45 * clampf(enemies.size[i], 0.7, 1.8), Color(0.9, 0.98, 1.0), 0.4, plift)
		fx.burst(Vector3(p.x, maxf(p.y, level), p.z) + Vector3(0, 0.2, 0), Color(0.85, 0.95, 1.0), 0.35)
		n += 1


## How far from the water's disc the hero's second pass keeps it (pass 56, _sink_hero): the disc can cover a hero standing
## up to about a metre outside it (0.85 m at most on ten rolls of Red Canyon: a bank still under the water's surface, seen
## across the water), and a throw moves him well under half a metre a frame.
const WADE_REACH := 2.5
## the map's water_disc, read once per map
var _wade_disc: Dictionary = {}
var _wade_map: Node = null


## The hero wades like the creatures (pass 56, Garry: "Hero for some reason walks on water, they are not submerged at all
## for some reason. Should be submerged like all the enemies"). The oasis is a see-through disc that tints whatever stands
## under its surface, and his second pass (BillboardSprite.enable_over_trails, drawn after it so his speed trails go under
## him) painted his whole figure over it again. While he is within WADE_REACH of the disc's edge that pass and his outline
## get the disc (the map's water_disc) and leave out, pixel by pixel, what the disc covers on his first pass; further off
## he is whole. His blob shadow, drawn after the water too, goes while he wades (`wet`, in_water) and wherever the drawn
## disc covers any of it from the camera (BillboardSprite.water_covers_blob, the creatures' rule in
## EnemyManager.shadow_wet): it lay on the water as a dark plate in the band at the shore. Every frame and at once, so no
## step in or out shows him on the water, cut off on dry sand or with a plate under him for a beat (the ripples above
## keep their own 0.28 s). Purely a look: nothing about play changes.
func _sink_hero(wet := false) -> void:
	var sprite: BillboardSprite = player.sprite
	if sprite == null:
		return
	if _wade_map != map:
		_wade_map = map
		_wade_disc = map.call("water_disc") if map.has_method("water_disc") else {}
	var r: float = float(_wade_disc.get("radius", 0.0))
	var c: Vector2 = _wade_disc.get("center", Vector2.ZERO)
	var at: Vector3 = player.global_position
	var near: bool = r > 0.0 and Vector2(at.x, at.z).distance_to(c) < r + WADE_REACH
	if near:
		sprite.set_water(c, float(_wade_disc["top"]), r, float(_wade_disc.get("thick", 0.0)))
	else:
		sprite.clear_water()
	var shadow: MeshInstance3D = player.shadow
	if shadow == null or player.cinematic:
		# the spawn beam shows and hides it itself
		return
	var under := wet
	if not under and near:
		# the blob: a flat quad (Player.tscn), its half-axes as it is drawn now (it turns with him and grows while he is
		# in the air), seen from the camera that draws him (his viewport's)
		var quad := shadow.mesh as QuadMesh
		var half: Vector2 = quad.size * 0.5 if quad else Vector2(0.7, 0.7)
		var b: Basis = shadow.global_transform.basis
		var vp := player.get_viewport()
		var eye: Camera3D = vp.get_camera_3d() if vp else null
		under = BillboardSprite.water_covers_blob(shadow.global_position, b.x * half.x, b.z * half.y, eye.global_position if eye else Vector3.INF, sprite.water(), float(_wade_disc.get("thick", 0.0)))
	shadow.visible = not under


func _tick_breadcrumb(delta: float) -> void:
	# a line a second into user://breadcrumb.txt: the last thing the run was doing if it dies (Settings shows it)
	_breadcrumb_t -= delta
	if _breadcrumb_t > 0.0:
		return
	_breadcrumb_t = 1.0
	var f := FileAccess.open("user://breadcrumb.txt", FileAccess.WRITE)
	if f:
		f.store_string("%s | stage %d | %s | level %d | alive %d | shots %d | %s" % [TextGen.time_mmss(Run.elapsed), Run.stage + 1, Perf.context, Run.level, enemies.alive_count(), projectiles.count, str(Run.weapons.map(func(w): return w.def.id))])
		f.close()


## A harpoon landed: the hero is tied to the creature that threw it for `cfg.seconds`. The thrower stays where it stood
## (the rope is as long as the throw; it was 4 m and snapped the thrower to him) and reels in whatever slack he gives it.
## Walking towards it is free; walking away runs at `cfg.away_speed` and drags it along (Player.leash_factor). Killing
## it cuts the rope.
func tether_start(shooter: int, cfg: Dictionary) -> void:
	if not enemies.is_alive(shooter) or player == null or player.dead:
		return
	tether_i = shooter
	tether_t = float(cfg.get("seconds", 5.0))
	tether_away = float(cfg.get("away_speed", 0.7))
	tether_min = float(cfg.get("min_length", 1.8))
	var gap: Vector3 = enemies.pos[shooter] - player.global_position
	gap.y = 0.0
	tether_len = maxf(gap.length(), tether_min)
	player.tethered = true
	player.tether_from = enemies.pos[shooter]
	player.tether_away = tether_away
	enemies.tethered_i = shooter
	_harpoon_proj = -1
	_tether_dust = 0.0
	# the hit has to be noticed: red round the screen, a shake, a red burst on him and a ring at his feet, and a word
	camera.shake(1.0)
	hud.flash(Color(0.85, 0.05, 0.03, 0.42), 0.5)
	fx.burst(player.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.18, 0.1), 1.3)
	telegraphs.flash_ring(player.global_position, 1.3, Color(1.0, 0.15, 0.1), 0.45)
	hud.toast("HOOKED!", UiKit.DANGER)
	hint_once("harpoon", "HOOKED: walking away drags it and slows you. Walk to it, or kill it, to get free.")
	Audio.play("en_beetle_charge", player.global_position)


func tether_end() -> void:
	if tether_i >= 0 and player:
		fx.burst(player.global_position + Vector3(0, 1.0, 0), Color(0.9, 0.8, 0.6), 0.8)
	tether_i = -1
	tether_t = 0.0
	if player:
		player.tethered = false
	enemies.tethered_i = -1
	if _rope:
		_rope.visible = false


func _tick_tether(delta: float) -> void:
	if tether_i >= 0:
		tether_t -= delta
		if tether_t <= 0.0 or player.dead or not enemies.is_alive(tether_i):
			tether_end()
			return
		var hp: Vector3 = player.global_position
		var gap: Vector3 = hp - enemies.pos[tether_i]
		gap.y = 0.0
		# the thrower reels in the slack: walk to it and the rope shortens, walk away and it comes with you
		tether_len = maxf(minf(tether_len, gap.length()), tether_min)
		var moved: float = enemies.tether_pull(tether_i, hp, tether_len)
		if moved < 0.0:
			tether_end()
			return
		player.tether_from = enemies.pos[tether_i]
		if moved > 0.002:
			# dragged: sand kicked up round its feet, a puff every 80 ms
			_tether_dust -= delta
			if _tether_dust <= 0.0:
				_tether_dust = 0.08
				fx.drag_dust(enemies.pos[tether_i], gap.normalized() if gap.length_squared() > 0.0001 else Vector3.FORWARD)
		else:
			_tether_dust = 0.0
		# taut while it pulls, a little sag while it holds
		_draw_rope(enemies.pos[tether_i] + Vector3(0, 1.3, 0), hp + Vector3(0, 0.85, 0), 0.015 if moved > 0.002 else 0.06)
	elif _harpoon_proj >= 0:
		# the harpoon in the air: the rope pays out behind it from the thrower
		var p := _harpoon_proj
		if p < projectiles.alive.size() and projectiles.alive[p] == 1 and projectiles.hostile[p] == 1 and projectiles.extra[p].has("harpoon") and enemies.is_alive(_harpoon_shooter):
			_draw_rope(enemies.pos[_harpoon_shooter] + Vector3(0, 1.3, 0), projectiles.pos[p], 0.03)
		else:
			_harpoon_proj = -1
			if _rope:
				_rope.visible = false
	elif _rope and _rope.visible:
		_rope.visible = false


## The rope between two points: a camera-facing ribbon along a sagging curve (`sag` of its length at the middle, at most
## 0.7 m), rebuilt every frame (a few dozen vertices). Pass 33.10: a dark band with the rope over it a hair nearer the
## camera, so it reads as an outlined line on sand and rock alike (the old one was a thin brown strip lost on the sand).
func _draw_rope(a: Vector3, b: Vector3, sag_frac := 0.06) -> void:
	if _rope == null:
		_rope_mesh = ImmediateMesh.new()
		_rope = MeshInstance3D.new()
		_rope.mesh = _rope_mesh
		_rope_dark = StandardMaterial3D.new()
		_rope_dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_rope_dark.albedo_color = Color(0.12, 0.05, 0.04)
		_rope_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rope_light = _rope_dark.duplicate()
		_rope_light.albedo_color = Color(0.93, 0.2, 0.12)
		_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rope)
	_rope.visible = true
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = (cam.global_position - a.lerp(b, 0.5)).normalized() if cam else Vector3.UP
	var n := 12
	var sag: float = minf(a.distance_to(b) * sag_frac, 0.7)
	var pts: Array = []
	for k in range(n + 1):
		var f := float(k) / float(n)
		var p := a.lerp(b, f)
		p.y -= sag * 4.0 * f * (1.0 - f)
		pts.append(p)
	_rope_mesh.clear_surfaces()
	_rope_strip(pts, 0.085, to_cam, Vector3.ZERO, _rope_dark)
	_rope_strip(pts, 0.045, to_cam, to_cam * 0.04, _rope_light)


func _rope_strip(pts: Array, half: float, to_cam: Vector3, nudge: Vector3, mat: Material) -> void:
	_rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, mat)
	for k in range(pts.size()):
		var p: Vector3 = pts[k] + nudge
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(to_cam).normalized() * half
		_rope_mesh.surface_add_vertex(p - side)
		_rope_mesh.surface_add_vertex(p + side)
	_rope_mesh.surface_end()


## A toast that shows once per save, for a creature whose trick is not obvious the first time.
func hint_once(id: String, text: String) -> void:
	if Save.once("hint_" + id):
		return
	Save.mark_once("hint_" + id)
	hud.toast(text, UiKit.ACCENT)


func fx_poison(at: Vector3) -> void:
	fx.poison(at)


## A burning creature's flame; `blue` (pass 48) when its fire is Methanol's or Moonshine's (EnemyManager.fire_blue).
func fx_fire(at: Vector3, size: float = 1.0, blue: bool = false) -> void:
	fx.fire(at, size, blue)


func fx_ignite(at: Vector3, size: float = 1.0, blue: bool = false) -> void:
	fx.ignite(at, size, blue)
	Audio.play("w_ignite", at)


## An elemental bomb landed: a poison cloud or a fire pool that keeps working on whoever stands in it while it lasts.
## `params.slow` slows whoever is inside (the Oil Slick's spills).
func spawn_cloud(at: Vector3, w: WeaponInstance, radius: float, element: String = "poison", params: Dictionary = {}) -> void:
	var c := ElementCloud.new()
	c.slow = float(params.get("slow", 0.0))
	# pass 48: a blue-fire weapon's pool burns blue (WeaponInstance.blue_fire), and the cloud keeps the params it came with
	c.blue = w != null and w.blue_fire()
	c.params = params
	if element == "fire":
		c.setup(self, w, radius, float(w.params.get("cloud_seconds", 3.0)), w.stat("fire_damage", 4.0), 1, w.stat("fire_duration", 1.8), "fire", w.stat("fire_spread", 0.5))
	else:
		c.setup(self, w, radius, float(w.params.get("cloud_seconds", 4.0)), w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
	# position first: _ready drapes the disc over the ground where the node stands, so it must already be there
	c.position = Vector3(at.x, map.height_at(at.x, at.z), at.z)
	add_child(c)


## Oil Slick (pass 33): a drop of burning oil falls from the bottle and spreads where it lands into a small spill that
## burns and slows. The bottle drops one every `every` metres of its flight (ProjectileManager._drip), so the line
## draws itself behind it in the air instead of appearing all at once where it lands.
func oil_drip(at: Vector3, w: WeaponInstance, dp: Dictionary) -> void:
	if map == null:
		return
	var g: float = map.height_at(at.x, at.z)
	var fall: float = sqrt(2.0 * maxf(at.y - g, 0.05) / 24.0)
	fx.drop(at, fall, w != null and w.blue_fire())
	var land := Vector3(at.x, g, at.z)
	var r := float(dp.get("radius", 0.8))
	var slow := float(dp.get("slow", 0.35))
	get_tree().create_timer(fall, false).timeout.connect(func() -> void:
		if not _ended:
			spawn_cloud(land, w, r, "fire", {"slow": slow}))


func fx_hit(at: Vector3, def: WeaponDef) -> void:
	var col := Color(str(def.placeholder.get("color", "#FFE08A")))
	fx.hit(at, col)


func fx_burst(at: Vector3, color: Color, size: float) -> void:
	fx.burst(at, color, size)
	# big bursts also ring the ground and kick the camera
	if size >= 1.4 and telegraphs and map:
		var ground := Vector3(at.x, map.height_at(at.x, at.z) + 0.05, at.z)
		telegraphs.flash_ring(ground, size * 1.15, color, 0.32)
		if camera:
			camera.shake(clampf(size * 0.16, 0.15, 0.8))


func fx_sand(at: Vector3, size: float = 1.0) -> void:
	if fx:
		fx.sand(at, size)


## The Gila's rumble passing (pass 43): a brief orange ring where the sand heaves, so the wave's front reads.
func rumble_mark(at: Vector3, width: float) -> void:
	telegraphs.flash_ring(at, width * 1.1, Color(1.0, 0.6, 0.3), 0.25)
	camera.shake(0.12)


# ---------------------------------------------------------------- hell (pass 43: the Brander)

## Lines of fire the Brander's iron leaves on the sand: {from, dir, len, width, life, damage, tick, next, fx_t, info}. The
## hero on one takes `damage` every `tick` seconds; so does anything else standing in it (at half).
var _hell_lines: Array = []
## The brimstone ring: the fight's arena, closing in. {center, r, t, phase} while the boss with a `ring` lives.
var _ring: Dictionary = {}
var _ring_mark := -1
var _ring_burn_t := 0.0
var _ring_fx_t := 0.0


func hell_line(from: Vector3, dir: Vector3, length: float, life: float, width: float, damage: float, tick: float, info: Dictionary, owner_i: int = -1) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var at := Vector3(from.x, map.height_at(from.x, from.z) if map else from.y, from.z)
	_hell_lines.append({"from": at, "dir": d, "len": length, "width": width, "life": life, "damage": damage, "tick": tick, "next": 0.0, "fx_t": 0.0, "info": info, "owner": owner_i})
	# the mark on the ground for as long as it burns, in fire
	telegraphs.line(at, d, length, life, Color(1.0, 0.45, 0.12, 0.55), width * 2.0)
	for k in range(6):
		fx.ignite(at + d * length * (float(k) + 0.5) / 6.0 + Vector3(0, 0.2, 0), 1.2)
	Audio.play("w_flare_fire", at)


## The boss that draws the ring starts it; the ring dies with the boss (_on_enemy_died).
func _on_boss_started(def: EnemyDef) -> void:
	var cfg = def.boss.get("ring", {})
	if not (cfg is Dictionary) or cfg.is_empty():
		return
	var c: Vector3 = enemies.pos[enemies.boss_index] if enemies.boss_index >= 0 else player.global_position
	_ring = {"center": Vector3(c.x, map.height_at(c.x, c.z) if map else c.y, c.z), "r": float(cfg.get("radius", 21.0)), "t": 0.0, "cfg": cfg}
	_ring_mark = telegraphs.hold_ring(_ring["center"], _ring["r"], Color(1.0, 0.4, 0.1, 0.85))
	hud.toast("THE RING OF FIRE CLOSES IN", Color(1.0, 0.45, 0.15))


func _end_ring() -> void:
	if _ring_mark >= 0:
		telegraphs.release(_ring_mark)
		_ring_mark = -1
	_ring = {}


func _tick_hell(delta: float) -> void:
	if not _hell_lines.is_empty():
		var keep: Array = []
		var here: Vector3 = player.global_position
		for l in _hell_lines:
			l["life"] = float(l["life"]) - delta
			l["next"] = float(l["next"]) - delta
			l["fx_t"] = float(l["fx_t"]) - delta
			var from: Vector3 = l["from"]
			var d: Vector3 = l["dir"]
			var ln: float = float(l["len"])
			if float(l["fx_t"]) <= 0.0:
				l["fx_t"] = 0.09
				for k in range(3):
					var s := randf() * ln
					var side := randf_range(-0.4, 0.4) * float(l["width"])
					fx.flame(from + d * s + Vector3(-d.z, 0, d.x) * side + Vector3(0, 0.05, 0), randf_range(0.8, 1.3), 0.45, Color(1.0, 0.42, 0.1))
			if float(l["next"]) <= 0.0:
				l["next"] = float(l["tick"])
				var rel := here - from
				rel.y = 0.0
				var along := clampf(rel.dot(d), 0.0, ln)
				if (rel - d * along).length() <= float(l["width"]) + 0.3 and not player.dead:
					player.take_damage(float(l["damage"]), from + d * along, l["info"])
				# the crowd burns on it too, at half: never the one that drew it nor any boss (pass 45: the Brander's line
				# starts at his own feet and he rolls down it next, so he burned himself for nine seconds a line); one test
				# per creature against the segment, where the eight overlapping discs hit the ones in the overlaps twice a tick
				var reach := float(l["width"]) + 0.6
				var owner_i := int(l.get("owner", -1))
				for j in enemies.indices_in_radius(from + d * ln * 0.5, ln * 0.5 + reach):
					if j == owner_i or j == enemies.boss_index:
						continue
					var jdef: EnemyDef = enemies.types[enemies.type_idx[j]]["def"]
					if jdef.archetype == "boss":
						continue
					var er: Vector3 = enemies.pos[j] - from
					er.y = 0.0
					var ea := clampf(er.dot(d), 0.0, ln)
					var off := er - d * ea
					if off.length() <= reach:
						enemies.damage(j, float(l["damage"]) * 0.5, "", off, 0.0)
			if float(l["life"]) > 0.0:
				keep.append(l)
		_hell_lines = keep
	if _ring.is_empty():
		return
	if enemies.boss_index < 0 or not enemies.is_alive(enemies.boss_index):
		_end_ring()
		return
	var cfg: Dictionary = _ring["cfg"]
	var r_max := float(cfg.get("radius", 21.0))
	var r_min := float(cfg.get("min_radius", 8.0))
	var shrink := float(cfg.get("shrink", 42.0))
	var hold := float(cfg.get("hold", 8.0))
	# the ring closes at the pace knob (pass 48): the slower hero has as long to keep inside it
	_ring["t"] = float(_ring["t"]) + delta * (enemies.pace if enemies else 1.0)
	var t := fmod(float(_ring["t"]), shrink + hold)
	var r: float = lerpf(r_max, r_min, clampf(t / shrink, 0.0, 1.0))
	_ring["r"] = r
	var c: Vector3 = _ring["center"]
	telegraphs.move_held(_ring_mark, c, r)
	_ring_fx_t -= delta
	if _ring_fx_t <= 0.0:
		_ring_fx_t = 0.05
		for k in range(4):
			var a := randf() * TAU
			var p := c + Vector3(cos(a) * r, 0.05, sin(a) * r)
			p.y = (map.height_at(p.x, p.z) if map else c.y) + 0.05
			fx.flame(p, randf_range(1.0, 1.8), 0.5, Color(1.0, 0.4, 0.1))
	_ring_burn_t -= delta
	if _ring_burn_t > 0.0:
		return
	_ring_burn_t = 0.5
	var here: Vector3 = player.global_position
	var flat := here - c
	flat.y = 0.0
	if flat.length() > r + 0.4 and not player.dead:
		# pass 54: times the creatures' damage multipliers like every hostile hit (EnemyManager.hostile_mult), and no shove
		# ("knock" 0: the hit comes from the ring's middle, so the old shove threw him further out into the fire)
		var burn: float = player.max_hp * float(cfg.get("burn", 0.07)) * 0.5 * enemies.creature_damage_mult * enemies.damage_time_mult
		player.take_damage(burn, c, {"by": "the ring of fire", "kind": "boss", "fx": ["outside the ring"], "knock": 0.0})
		hud.flash(Color(1.0, 0.35, 0.1, 0.3), 0.3)
	# the crowd burns out there too, so the fight stays inside
	var cb := float(cfg.get("creature_burn", 0.12)) * 0.5
	if cb > 0.0:
		for i in range(EnemyManager.MAX):
			if enemies.alive[i] == 1 and i != enemies.boss_index and (enemies.types[enemies.type_idx[i]]["def"] as EnemyDef).archetype != "boss":
				var ep := enemies.pos[i] - c
				ep.y = 0.0
				if ep.length() > r + 0.4:
					enemies.damage(i, enemies.max_hp[i] * cb, "", Vector3.ZERO, 0.0, false, true)


func fx_lightning(points: Array) -> void:
	fx.lightning(points)


func toast(text: String, color: Color = UiKit.INK) -> void:
	if hud:
		hud.toast(text, color)


func _spit_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.28
	s.height = 0.56
	s.radial_segments = 8
	s.rings = 4
	return s


func _spit_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.8, 0.4)
	m.emission_enabled = true
	m.emission = Color(0.3, 0.7, 0.3)
	return m
