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
var paused := false
var hud: HUD
var cards: CardScreen
var pause_screen: PauseScreen
var portal_dialog: PortalDialog
var hints: Hints
var debug_panel: DebugPanel
var _pending_levels := 0
var _spit_kind := -1
var _harpoon_kind := -1
var _rocket_kind := -1
var _pellet_kind := -1
var _spike_kind := -1
var _shard_kind := -1
## chests waiting for the reel while one is open (a boss drops two, and both fly in together)
var _chest_queue: Array = []
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


## The debug arena (pass 33.4): the panel over it, whether a level-up shows its cards, and the save as it was when it
## opened (put back when it closes, so nothing done in the arena is kept).
var arena_panel: ArenaPanel = null
var arena_cards := false
var _arena_save: Dictionary = {}


func _ready() -> void:
	var arena: bool = Run.arena_next
	Run.arena_next = false
	# the arena keeps nothing: the save as it is now (before Run.start counts a run) goes back when it closes
	if arena:
		_arena_save = Save.data.duplicate(true)
	var character_id: String = str(Save.data.get("last_character", "astro"))
	var map_id: String = str(Save.data.get("last_map", "red_canyon"))
	var debug_launch := _read_debug_launch()
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
		telegraphs.flash_ring(player.global_position, 0.9, Color(0.85, 0.95, 1.0), 0.25))
	player.shield_hit.connect(func(broke: bool):
		telegraphs.flash_ring(player.global_position, 1.1, Color(0.36, 0.74, 1.0), 0.3)
		if broke:
			fx.burst(player.global_position + Vector3(0, 1.0, 0), Color(0.36, 0.74, 1.0), 1.3)
			Audio.play("ui_pause", player.global_position))
	player.momentum_trail.connect(func(at, back, strength): fx.trail(at, back, strength))
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
	_rocket_kind = projectiles.register_kind(_rocket_mesh(), _rocket_material(), 1.0)
	_pellet_kind = projectiles.register_kind(_pellet_mesh(), _pellet_material(), 1.0)
	_spike_kind = projectiles.register_kind(_spike_mesh(), _spike_material(), 1.0)
	_shard_kind = projectiles.register_kind(_shard_mesh(), _shard_material(), 1.0)
	director = WaveDirector.new()
	director.game = self
	add_child(director)
	# the map's structures, scattered once per run
	structures = StructureManager.new()
	add_child(structures)
	if mapdef and mapdef.timeline and not mapdef.timeline.structures.is_empty():
		structures.setup(self, map, mapdef.timeline.structures)
	# the barrels (pass 44): forty-odd by the run's seed, never behind a painting, broken by walking up to them
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
	Run.level_up.connect(_on_level_up)
	Run.lifesteal_healed.connect(func(n): if player and not player.dead: player.heal(n))
	Run.build_changed.connect(_sync_weapons)
	Run.weapon_evolved.connect(_on_evolved)
	# ui
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
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
	resume_gate = ResumeGate.new()
	resume_gate.hud = hud
	ui.add_child(resume_gate)
	resume_gate.resumed.connect(func():
		set_paused(false)
		if _path_pending:
			call_deferred("present_path_offer")
		# a second of grace after the screens, blinking, so a pick is never claimed straight into a bite
		if player and not player.dead:
			player.invuln = maxf(player.invuln, 1.0))
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
		return
	# starter pick
	var fixed: Array = []
	if not Save.first_run_done() or debug_launch.get("fixed_starter", false):
		fixed = ["peashooter", "boomstick", "orbit_saws"]
	if debug_launch.has("weapon"):
		var w: WeaponDef = Registry.weapon(str(debug_launch["weapon"]))
		if w:
			Run.add_weapon(w, int(debug_launch.get("level", 1)))
			_start_run()
			return
	var offer := CardPool.starter_offer(fixed)
	if offer.is_empty():
		_start_run()
		return
	set_paused(true)
	cards.show_offer(offer, "PICK YOUR STARTER", true, not Save.first_run_done())
	# everything the run can draw, drawn once under the hero while the cards are up, so no first-appearance hitch
	Warmup.run(self)
	cards.chosen.connect(_on_starter_chosen, CONNECT_ONE_SHOT)


func _read_debug_launch() -> Dictionary:
	if not FileAccess.file_exists("user://debug_launch.json"):
		return {}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	DirAccess.remove_absolute("user://debug_launch.json")
	return d if d is Dictionary else {}


func _on_starter_chosen(card: Dictionary) -> void:
	CardPool.apply(card)
	set_paused(false)
	_start_run()


func _start_run() -> void:
	_run_started = true
	_sync_weapons()
	director.start(Run.map)
	if not Run.arena:
		hints.begin()
	hud.refresh_stage()


## The debug arena: the hero with his favourite weapon, god mode on, the director set up but holding its clock and its
## spawns, and the arena panel over the HUD. The save is copied now and put back when the arena closes.
func _start_arena() -> void:
	if _arena_save.is_empty():
		_arena_save = Save.data.duplicate(true)
	var fav: WeaponDef = Registry.weapon(Run.character.favourite_weapon) if Run.character else null
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


## Out of the arena, back to the title, the save as it was (kills, chests, gold and unlocks from the arena all go).
func leave_arena() -> void:
	if _ended:
		return
	_ended = true
	Engine.time_scale = 1.0
	tether_end()
	director.stop()
	if not _arena_save.is_empty():
		Save.data = _arena_save
		Save.save_now()
	Run.end()
	Run.arena = false
	Audio.stop_music()
	set_paused(false)
	UiFx.go(get_tree(), "res://ui/TitleScreen.tscn")


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
	if paused or _ended:
		return
	set_paused(true)
	Audio.play("ui_pause")
	pause_screen.open()


func close_pause() -> void:
	pause_screen.close()
	Audio.play("ui_resume")
	set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if structure_shop and structure_shop.visible:
				structure_shop._finish(false)
			elif pause_screen.visible:
				close_pause()
			elif not cards.visible and not portal_dialog.visible:
				open_pause()
		elif event.keycode == KEY_F1:
			debug_panel.toggle()


func _notification(what: int) -> void:
	# the app really left the screen (a call, the home button): the run waits behind the pause menu
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_log_pause("the app went to the background")
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

func _sync_weapons() -> void:
	var t0 := Time.get_ticks_usec()
	for w in Run.weapons:
		var id: String = w.def.id
		if _behaviors.has(id):
			var b: WeaponBehavior = _behaviors[id]
			# a mutation that swaps the behaviour (Needle Rain, Homing Skulls, Walking Buddy) rebuilds it
			if b.get_script() == _behavior_script(w.behavior()):
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
	push_warning("Unknown weapon behaviour: " + name)
	return null


func _on_evolved(id: String) -> void:
	var def := Registry.weapon(id)
	Audio.play("w_evo_reveal")
	hud.banner("EVOLVED · " + (def.display_name if def else id).to_upper(), UiKit.TYPE_COLORS["evolution"], def.icon if def else null)
	camera.shake(1.2)


# ---------------------------------------------------------------- run flow

func _process(delta: float) -> void:
	if paused or _ended or not _run_started:
		return
	Audio.set_listener(player.global_position)
	if not player.input.lifted_once:
		Run.no_lift_time = Run.elapsed
	if portal and is_instance_valid(portal):
		portal.check_player(player)
	Run.alive = enemies.alive_count()
	for label in Run.tick_timed():
		hud.toast("%s wore off" % label, UiKit.INK3)
	_tick_perks(delta)
	_tick_tether(delta)
	_tick_breadcrumb(delta)
	_tick_water(delta)
	_tick_berserk(delta)
	_tick_hell(delta)
	var t0 := Time.get_ticks_usec()
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
		# the banner carries the item's own icon (pass 44), so the unlock is seen, not only read
		var def: ContentDef = Registry.unlocked_by(q)
		hud.banner("UNLOCKED: " + (def.display_name if def else q.display_name), UiKit.GOOD, def.icon if def else null)
		Audio.play("ui_unlock")


var _dust_t := 0.0


var _supply_t := -1.0
var _thrust_cd := 0.0
var _noon_t := -1.0
var _noon_left := 0.0
var _bounty_kills := 0


## The perks that run every frame: the Drifter's Trail Dust and High Noon, Astro's Supply Drop and Thruster Burst
## (pass 34), each on its own clock.
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
	if not Run.has_perk("trail_dust"):
		return
	if player.velocity.length() < 0.8:
		return
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = Run.perk_param("trail_dust", "every", 0.22)
		spawn_zone(player.global_position - player.forward() * 0.6, Run.perk_param("trail_dust", "radius", 1.1), Run.perk_param("trail_dust", "seconds", 1.0),
			0.0, 0.3, null, Run.perk_param("trail_dust", "slow", 0.25), Color(0.85, 0.72, 0.5, 0.3))


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
	enemies.slow_radius(here, r, Run.perk_param("serenade", "slow", 0.25), _serenade_t + 0.25)


## Supply Drop: a red ring on the sand near her, a pod falling into it, a blast that hurts and throws, and a power-up
## where it landed (a heart when she is below 60%).
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
	var dmg := Run.perk_param("supply_drop", "damage", 30.0) + Run.perk_param("supply_drop", "damage_per_level", 4.0) * float(Run.level)
	enemies.damage_radius(at, r, dmg, "supply_drop", Run.perk_param("supply_drop", "knockback", 14.0))
	fx.explosion(at, 1.4)
	camera.shake(0.6)
	Audio.play("en_rocket_boom", at)
	var id: String = "heart" if player and player.hp < player.max_hp * 0.6 else ["magnet_pulse", "rage", "shield", "sprint"][randi() % 4]
	var pd: PickupDef = Registry.pickup(id)
	if pd:
		pickups.spawn_special(pd, at)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(pod, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tw.tween_callback(pod.queue_free)


## Thruster Burst: when the crowd closes in, the suit fires her clear towards the emptiest ground and throws the ring.
func _tick_thrusters(delta: float) -> void:
	_thrust_cd = maxf(_thrust_cd - delta, 0.0)
	if _thrust_cd > 0.0:
		return
	var here: Vector3 = player.global_position
	if enemies.indices_in_radius(here, Run.perk_param("thruster_burst", "reach", 2.6)).size() < int(Run.perk_param("thruster_burst", "crowd", 6.0)):
		return
	var best := Vector3.FORWARD
	var best_n := 1 << 30
	for k in range(12):
		var ang := TAU * float(k) / 12.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var n: int = enemies.indices_in_radius(here + dir * 5.0, 2.5).size()
		if n < best_n:
			best_n = n
			best = dir
	player.blast(best * Run.perk_param("thruster_burst", "push", 28.0), Run.perk_param("thruster_burst", "lift", 5.0))
	player.invuln = maxf(player.invuln, Run.perk_param("thruster_burst", "invuln", 0.6))
	enemies.throw_radius(here, Run.perk_param("thruster_burst", "throw_radius", 3.2), Run.perk_param("thruster_burst", "throw", 18.0))
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
	if not cards.visible and not portal_dialog.visible and not chest_screen.visible:
		_show_next_level_cards()


var _path_pending := false


## A stage's path slot came due (WaveDirector): the weapon whose path is open goes on the table, all of it. Behind
## another screen it waits for the resume.
func present_path_offer() -> void:
	if Run.arena:
		return
	if _ended:
		return
	if cards.visible or portal_dialog.visible or chest_screen.visible or paused:
		_path_pending = true
		return
	_path_pending = false
	var w := Run.next_path_weapon()
	if w == null:
		return
	var offer := CardPool.path_offer(w)
	if offer.is_empty():
		return
	set_paused(true)
	Audio.play("ui_levelup")
	cards.show_offer(offer, "PATH · %s" % w.def.display_name.to_upper(), false, not Save.hint_seen("paths"), true)
	cards.chosen.connect(_on_path_chosen, CONNECT_ONE_SHOT)


func _on_path_chosen(card: Dictionary) -> void:
	Perf.context = "path chosen"
	if card.get("skipped", false):
		var g := Run.skip_gold()
		Run.add_gold(g)
		hud.toast("Path skipped. +%d gold" % g, UiKit.INK2)
	else:
		var line := CardPool.apply(card)
		hud.toast(line, UiKit.TYPE_COLORS["mutation"])
		# the hero's own option does not spend the stage's pick: the path itself comes straight back
		var def: ContentDef = card["def"]
		if def is MutationDef and (def as MutationDef).is_hero():
			var w := Run.family_instance((def as MutationDef).weapon)
			if w and Run.can_mutate(w) and not Run.open_mutations(w).is_empty():
				cards.show_offer(CardPool.path_offer(w), "PATH · %s" % w.def.display_name.to_upper(), false, false, true)
				cards.chosen.connect(_on_path_chosen, CONNECT_ONE_SHOT)
				return
	Save.mark_hint("paths")
	if _pending_levels > 0:
		await get_tree().create_timer(0.2).timeout
		_show_next_level_cards()
	else:
		resume_gate.open(cards.take_pick())


func _show_next_level_cards() -> void:
	if _pending_levels <= 0 or _ended:
		return
	_pending_levels -= 1
	var n := 3
	if randf() < CardPool.bonus_card_chance():
		n = 4
	var offer := CardPool.level_up_offer(n)
	if offer.is_empty():
		Run.add_gold(10)
		hud.toast("Nothing left to pick. +10 gold", UiKit.INK2)
		return
	set_paused(true)
	cards.show_offer(offer, "LEVEL %d!" % Run.level, false, not Save.hint_seen("cards"))
	cards.chosen.connect(_on_card_chosen, CONNECT_ONE_SHOT)


func _on_card_chosen(card: Dictionary) -> void:
	Perf.context = "card chosen"
	if card.get("skipped", false):
		var g := Run.skip_gold()
		Run.add_gold(g)
		hud.toast("Skipped. +%d gold" % g, UiKit.INK2)
	else:
		var t1 := Time.get_ticks_usec()
		var line := CardPool.apply(card)
		Perf.add("card.apply", t1)
		hud.toast(line, UiKit.ACCENT)
	var t2 := Time.get_ticks_usec()
	Save.mark_hint("cards")
	Perf.add("card.unpause", t2)
	if _pending_levels > 0:
		await get_tree().create_timer(0.2).timeout
		_show_next_level_cards()
	else:
		# still paused: the run resumes on the next tap, not on the pick (the card flies to its slot meanwhile)
		resume_gate.open(cards.take_pick())


func _on_enemy_died(def: EnemyDef, at: Vector3, elite: EliteModDef, _weapon_id: String) -> void:
	# Trigger Happy: every kill takes a slice off every weapon's cooldown
	var cut: float = Run.player_sheet.get_stat("cooldown_on_kill", 0.0)
	if cut > 0.0:
		for b in _behaviors.values():
			b.cooldown_left = maxf(b.cooldown_left - cut, 0.0)
	var xp_scale := def.xp_mult * (4.0 if elite else 1.0)
	pickups.drop_from(def, at, xp_scale, elite != null)
	director.drop_pickup_from(def, at, elite != null)
	# the drop passives (pass 33.2): Cheese (Beef Jerky until pass 44) and Pickpocket roll on every kill for their own small pickups
	for pair in [["heal_drop", "cheese_bite"], ["coin_drop", "coin_bag"]]:
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
	# Brimstone Brand (pass 43, stage 3): a kill may set the sand alight where the body fell, burning the crowd
	var brand: float = Run.player_sheet.get_stat("brand_chance", 0.0)
	if brand > 0.0 and randf() < brand and def.archetype != "boss":
		var bw: WeaponInstance = Run.weapon_instance(_weapon_id) if _weapon_id != "" else null
		var bz := spawn_zone(at, 2.2, 3.0, 6.0 * Run.player_sheet.get_stat("might", 1.0), 0.25, bw, 0.0, Color(1.0, 0.42, 0.1, 0.3))
		bz.flames = true
		fx.ignite(at + Vector3(0, 0.2, 0), 1.4)
	# Grand Finale (pass 43, Calavera): a boss or an Elite going down takes a share of every creature's health with it
	if (def.archetype == "boss" or def.archetype == "elite" or elite != null) and Run.has_perk("grand_finale"):
		var fr := Run.perk_param("grand_finale", "radius", 14.0)
		var frac := Run.perk_param("grand_finale", "frac", 0.35)
		for j in enemies.indices_in_radius(at, fr):
			if j != enemies.boss_index:
				enemies.damage(j, enemies.max_hp[j] * frac, "grand_finale")
		enemies.throw_radius(at, fr, Run.perk_param("grand_finale", "throw", 16.0))
		telegraphs.flash_ring(at, fr, Color(1.0, 0.82, 0.35), 0.6)
		fx.burst(at + Vector3(0, 1.0, 0), Color(1.0, 0.82, 0.35), 4.0)
		hud.toast("GRAND FINALE", Color(1.0, 0.82, 0.35))
		camera.shake(1.2)
	# materials for the homestead: bones from every Elite, relics from every boss; deeper stages and Mira's trait add one
	# the Mirror spends gold, so what the deep parts of a run used to pay in bones and relics they pay in coin:
	# an Elite is worth a purse, a boss a chest of them (Mira's Motherlode adds a half)
	var lode: float = 1.5 if (Run.character and Run.character.specials.has("motherlode")) else 1.0
	if elite != null or def.archetype == "elite":
		var purse := int((90 + 60 * Run.stage) * lode)
		Run.add_gold(purse)
		hud.toast("+%d GOLD" % purse, Color(1.0, 0.85, 0.35))
	if def.archetype == "boss":
		var chest_gold := int((260 + 140 * Run.stage) * lode)
		Run.add_gold(chest_gold)
		hud.toast("+%d GOLD" % chest_gold, Color(1.0, 0.85, 0.35))
	if def.archetype == "boss":
		_end_ring()
		_hell_lines.clear()
		# the reward scales with the boss (drops.coins, drops.chests): the second boss pays for continuing
		for k in range(int(def.drops.get("coins", 12))):
			pickups.spawn(PickupManager.KIND_COIN, at + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)), 5.0)
		for k in range(int(def.drops.get("chests", 1)) - 1):
			pickups.spawn_chest(at + Vector3(-2.0 - 1.6 * k, 0, 1.5))
		hud.toast("A BOSS CHEST: open it to call everything in", Color(1.0, 0.82, 0.35))
		fx.burst(at + Vector3(0, 1, 0), Color(1.0, 0.75, 0.3), 5.0)
		camera.shake(1.5)
		hud.banner("BOSS DOWN", Color(1.0, 0.8, 0.3))
	elif def.archetype == "elite":
		fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.65, 0.3), 3.0)
		camera.shake(0.9)
	else:
		fx.burst(at + Vector3(0, 0.4, 0), Color(0.95, 0.85, 0.7), def.size * 0.6)


## Cactus Coat: whatever hits the hero gets a face full of spines, along with anything else standing close.
func _on_player_hit() -> void:
	# Crescendo (pass 43): a hit ends the song
	Run.reset_crescendo()
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


## The hero finished using a structure (content/structures).
func use_structure(def: StructureDef, at: Vector3) -> void:
	var p: Dictionary = def.params
	Audio.play("pk_chest_open", at)
	fx.burst(at + Vector3(0, 1.0, 0), def.color, 2.0)
	telegraphs.flash_ring(at, def.radius + 0.5, def.color, 0.5)
	camera.shake(0.4)
	match def.effect_kind:
		"bank":
			# the Strongbox: everything in the purse goes to the homestead now, whatever happens to the run
			var carried := Run.run_gold
			if carried > 0:
				Save.add_gold(carried)
				Run.run_gold = 0
				Run.gold_changed.emit(0)
				Run.banked_gold += carried
			hud.toast("BANKED %d GOLD" % carried, Color(1.0, 0.85, 0.35))
			Audio.play("pk_coin", player.global_position)
		"vacuum_all":
			pickups.vacuum_all(true)
			hud.banner(def.display_name.to_upper(), def.color)
		"teleport":
			teleport_hero(def)
		"stranger":
			var offer := Run.stranger_offer()
			if offer.is_empty():
				Run.add_gold(60)
				hud.toast("The Stranger had nothing for you. +60 gold", UiKit.ACCENT)
				return
			var cost := float(offer.get("hp_cost", p.get("hp_cost", 0.15)))
			set_paused(true)
			stranger_screen.open(offer, cost)
			stranger_screen.closed.connect(func(took):
				set_paused(false)
				if took:
					var line := Run.stranger_take(offer, cost)
					player.refresh_stats()
					hud.toast("The deal: %s, for %d%% of your health" % [line, int(round(cost * 100.0))], Color(0.75, 0.6, 1.0))
				else:
					hud.toast("The Stranger is gone. Only his cloak stays.", UiKit.INK2), CONNECT_ONE_SHOT)
		"shop":
			var offer := CardPool.level_up_offer(3)
			if offer.is_empty():
				Run.add_gold(50)
				hud.toast("The shop had nothing left. +50 gold", UiKit.ACCENT)
				return
			set_paused(true)
			structure_shop.open(offer)
			structure_shop.closed.connect(func(bought): set_paused(false); if bought: hud.toast("Bought!", UiKit.ACCENT), CONNECT_ONE_SHOT)
		"heal":
			var amount: float = player.max_hp * float(p.get("fraction", 0.5))
			player.heal(amount)
			hud.toast("+%d HP" % int(round(amount)), UiKit.GOOD)
		"loot":
			var gold := int(p.get("gold", 60))
			Run.add_gold(gold)
			for k in range(int(p.get("gems", 3))):
				pickups.spawn(PickupManager.KIND_GEM_L, at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), 25.0)
			for k in range(int(p.get("coins", 4))):
				pickups.spawn(PickupManager.KIND_COIN, at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), 3.0)
			hud.toast("+%d gold and gems" % gold, UiKit.ACCENT)
		"buff":
			Run.add_timed_effects("structure:" + def.id, def.display_name, def.effects, float(p.get("seconds", 30.0)))
			hud.toast("%s: %s for %d s" % [def.display_name.to_upper(), TextGen.describe_effects(def.effects), int(p.get("seconds", 30.0))], def.color)
		"level_up":
			Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)
			hud.toast("LEVEL UP!", UiKit.XP)
		"dice":
			_roll_dice(def, at)
		_:
			hud.toast(def.display_name, def.color)


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
			player.heal(player.max_hp)
			hud.banner("DICE: FULL HEAL", UiKit.GOOD)
		"gold":
			Run.add_gold(150)
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


## The hero walked into a pickup (content/pickups): heal, timed buff, shield or gem vacuum.
func apply_pickup(def: PickupDef, at: Vector3) -> void:
	# a power-up taken (pass 44: an unlock counts them); the small things underfoot (cheese, coin bags) are not power-ups
	if not bool(def.params.get("small", false)) and not Run.arena:
		Save.add_total("pickups", 1)
	match def.effect_kind:
		"heal":
			var amount: float = player.max_hp * def.value
			player.heal(amount)
			if not bool(def.params.get("quiet", false)):
				hud.toast("+%d HP" % int(round(amount)), UiKit.GOOD)
			Audio.play("pk_heart", at)
		"gold":
			# the coin bag: a handful of coins at once
			Run.add_gold(int(def.value))
			Audio.play("pk_coin", at)
		"buff":
			Run.add_timed_effects(def.id, def.display_name, def.effects, def.duration)
			hud.toast("%s: %s for %d s" % [def.display_name.to_upper(), TextGen.describe_effects(def.effects), int(def.duration)], def.color)
			Audio.play("pk_powerup", at)
		"shield":
			player.shield(def.duration)
			hud.toast("SHIELD for %d s" % int(def.duration), def.color)
			Audio.play("pk_powerup", at)
		"vacuum":
			# everything on the map, the coins and the chests too, as a boss kill does it
			pickups.vacuum_all(true, true)
			hud.toast("MAGNET PULSE", def.color)
		"nuke":
			var np: Dictionary = def.params
			nuke_blast(player.global_position, float(np.get("radius", 16.0)), def.value, float(np.get("knockback", 14.0)))
			hud.toast("NUKE", def.color)
		_:
			Audio.play("pk_powerup", at)
	fx.burst(at + Vector3(0, 0.8, 0), def.color, 1.3)
	telegraphs.flash_ring(at, 2.0, def.color, 0.35)


## A chest on the ground was touched: the game pauses and the reel decides in front of the player.
func open_chest(at: Vector3, boss: bool = false) -> void:
	Audio.play("pk_chest_open", at)
	fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4), 1.5)
	if _ended:
		return
	if chest_screen.visible or (cards and cards.visible):
		# one reel at a time: a boss drops two chests and both fly in together
		_chest_queue.append({"at": at, "boss": boss})
		return
	if boss:
		# the boss's chest: opening it is what calls everything on the map in, and the reel only holds mutations
		pickups.vacuum_all(true, true)
		hud.toast("THE SPOILS COME TO YOU", Color(1.0, 0.82, 0.35))
	var r := Run.chest_roll(boss)
	set_paused(true)
	chest_screen.open(r)


func _on_chest_closed(take: bool) -> void:
	var r := chest_screen.result()
	var line: String
	if take:
		line = Run.chest_take(r)
		Audio.play("ui_buy")
	else:
		line = Run.chest_sell(r, chest_screen.sell_gold())
		Audio.play("pk_coin")
	if str(r.get("type", "")) != "evolution" or not take:
		hud.toast("Chest: " + line, UiKit.ACCENT)
	if not _chest_queue.is_empty():
		var next: Dictionary = _chest_queue.pop_front()
		await get_tree().create_timer(0.25).timeout
		if not _ended:
			if bool(next.get("boss", false)):
				pickups.vacuum_all(true, true)
				hud.toast("THE SPOILS COME TO YOU", Color(1.0, 0.82, 0.35))
			var r2 := Run.chest_roll(bool(next.get("boss", false)))
			chest_screen.open(r2)
			return
	if _pending_levels > 0:
		await get_tree().create_timer(0.2).timeout
		_show_next_level_cards()
	else:
		resume_gate.open(chest_screen.take_pick() if chest_screen.has_method("take_pick") else {})


func _on_portal_ready(at: Vector3) -> void:
	portal = Portal.new()
	add_child(portal)
	portal.global_position = at
	portal.entered.connect(_on_portal_entered)
	hud.toast("PORTAL OPEN: extract or continue", UiKit.GOOD)


func _on_portal_entered() -> void:
	set_paused(true)
	var final_stage: bool = Run.stage + 1 >= Run.map.timeline.stages if Run.map and Run.map.timeline else false
	# pass 43: after the last boss the choice is extract or stay (endless needs no unlock any more)
	portal_dialog.open(Run.stage + 1, true, final_stage)
	portal_dialog.decided.connect(_on_portal_decided, CONNECT_ONE_SHOT)


func _on_portal_decided(extract: bool) -> void:
	if extract:
		Run.extracted = true
		Save.mark_once("extract_%s_%d" % [Run.map.id, Run.stage + 1])
		Save.add_total("extracts", 1)
		Audio.play("wd_extract")
		player.cheer()
		end_run()
	else:
		set_paused(false)
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
## one per Revive shop tier; the count runs out into the results screen.
func _on_player_died() -> void:
	hud.hide_player_bar()
	await get_tree().create_timer(1.2).timeout
	if _ended:
		return
	set_paused(true)
	var chances: int = 1 + Run.player_sheet.get_int("revives", 0) - Run.revives_used
	revive_screen.open(Run.run_gold, chances, player.damage_log_text(), player.damage_log.back() if not player.damage_log.is_empty() else {})


func _on_revive_decided(kind: String) -> void:
	set_paused(false)
	match kind:
		"give_up", "timeout":
			Run.died = true
			end_run()
		_:
			if kind == "gold":
				# a flat price: add_gold would scale it by greed
				Run.run_gold = maxi(Run.run_gold - ReviveScreen.GOLD_COST, 0)
				Run.gold_changed.emit(Run.run_gold)
			if kind != "debug":
				Run.revives_used += 1
			player.revive()
			# he comes back with a bang: a wave a third of the nuke's that clears everything but the big ones
			revive_blast()
			enemies.damage_radius(player.global_position, 6.0, 0.0, "", 12.0)
			telegraphs.flash_ring(player.global_position, 6.0, UiKit.GOOD, 0.6)
			hud.show_player_bar()
			hud.banner("REVIVED" if kind != "debug" else "DEBUG REVIVE", UiKit.GOOD)
			Perf.context = "revived " + kind


func end_run() -> void:
	if Run.arena:
		leave_arena()
		return
	if _ended:
		return
	_ended = true
	tether_end()
	director.stop()
	# the run's gold comes home with the hero (pass 44): a death leaves it in the sand, all but what a Strongbox banked
	# on the way; the results screen says which
	var gold := Run.run_gold if not Run.died else 0
	var map_id := Run.map.id if Run.map else ""
	Run.last_result = {"gold_before": Save.gold(), "banked": gold, "lost": Run.run_gold if Run.died else 0,
		"strongbox": Run.banked_gold, "prev_best": Save.best_run(map_id).duplicate()}
	if gold > 0:
		Save.add_gold(gold)
	Save.record_run(map_id, Run.elapsed, Run.level, Run.stage + 1, Run.kills)
	# after the run is counted, so "play N runs" sees this one
	QuestTracker.check_all(true)
	Save.save_now()
	Run.end()
	Audio.stop_music()
	await get_tree().create_timer(1.2).timeout
	set_paused(false)
	UiFx.go(get_tree(), RESULTS)


func abandon_run() -> void:
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
## (pass 30: a mine crab clears a path through its own pack). `delay` 0 fires at once, anything else draws a red ring.
func elite_explosion(center: Vector3, r: float, damage: float, delay: float, knockback: float = 0.0, friendly_frac: float = 0.2, info: Dictionary = {}) -> void:
	if delay > 0.0:
		telegraphs.ring(center, r, delay, UiKit.DANGER, true)
	var boom := func():
		if _ended:
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
	var t := get_tree().create_timer(delay)
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

## A rocket, not a pill: a body, a nose cone and three fins, all one mesh so it can be a projectile kind.
func _rocket_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
		for v in [p0 + Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_front),
				p0 + Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_front), p0 + Vector3(0, 0, body_front)]:
			st.add_vertex(v)
		# the nose cone
		for v in [p0 + Vector3(0, 0, body_front), p1 + Vector3(0, 0, body_front), Vector3(0, 0, nose)]:
			st.add_vertex(v)
		# the tail cap
		for v in [Vector3(0, 0, body_back), p1 + Vector3(0, 0, body_back), p0 + Vector3(0, 0, body_back)]:
			st.add_vertex(v)
	# three fins at the tail
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


func _rocket_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.1, 0.08)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.25, 0.1)
	m.emission_energy_multiplier = 2.4
	return m


## A rocketeer fired: one slow red rocket that hunts the hero; only its goblin's death ends it early.
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


## A dark scorch on the sand where something went off: it holds a moment, then fades out (a pooled ground mark).
func _scorch(at: Vector3, r: float) -> void:
	telegraphs.scorch(at, r, Color(0.1, 0.06, 0.05, 0.6), Color(0.22, 0.14, 0.1, 0.0), 1.5, 3.0)


## Every creature death, by index (EnemyManager): the rockets of a dead rocketeer go with it, and so does the rope.
func on_creature_died_index(i: int) -> void:
	projectiles.kill_rockets_of(i)
	if tether_i == i:
		tether_end()
	if enemies.bounty_i == i:
		# the bounty is paid: gold and a chest where it fell
		enemies.bounty_i = -1
		var at: Vector3 = enemies.pos[i]
		var gold := int(Run.perk_param("bounty_hunter", "gold", 40.0))
		Run.add_gold(gold)
		pickups.spawn_chest(at)
		fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.82, 0.35), 1.3)
		hud.toast("BOUNTY +%d" % gold, Color(1.0, 0.82, 0.35))
		Audio.play("pk_coin", at)
	_count_bounty()


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
	enemies.damage_radius(at, radius, damage, "nuke", knock)
	# the wave: a fat additive ring growing to the radius over half a second, then fading
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 8
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.75, 0.35, 1.0)
	ring.material_override = mat
	ring.position = at + Vector3(0, 0.6, 0)
	ring.scale = Vector3(0.3, 0.6, 0.3)
	add_child(ring)
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
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(wall, "scale", Vector3(radius, 1.0, radius), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(wmat, "albedo_color:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): ring.queue_free(); wall.queue_free())
	fx.burst(at + Vector3(0, 1.0, 0), Color(1.0, 0.95, 0.8), 6.0)
	fx.burst(at + Vector3(0, 0.6, 0), Color(1.0, 0.55, 0.2), 9.0)
	for k in range(14):
		var a := TAU * float(k) / 14.0
		fx.sand(at + Vector3(cos(a), 0.1, sin(a)) * radius * 0.5, 1.2)
	telegraphs.flash_ring(at, radius, Color(1.0, 0.6, 0.25), 0.6)
	camera.shake(3.0)
	hud.flash(Color(1.0, 0.9, 0.7, 0.85), 0.5)
	Audio.play("en_boss_die", at)


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


func _tick_water(delta: float) -> void:
	if map == null or not map.has_method("in_water") or player == null or player.dead:
		return
	_ripple_t -= delta
	if _ripple_t > 0.0:
		return
	_ripple_t = 0.28
	if map.call("in_water", player.global_position):
		var moving: bool = player.velocity.length() > 0.5
		telegraphs.flash_ring(player.global_position, 0.55 if moving else 0.35, Color(0.9, 0.98, 1.0), 0.45)
		if moving:
			fx.burst(player.global_position + Vector3(0, 0.25, 0), Color(0.85, 0.95, 1.0), 0.5)


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


func fx_fire(at: Vector3, size: float = 1.0) -> void:
	fx.fire(at, size)


func fx_ignite(at: Vector3, size: float = 1.0) -> void:
	fx.ignite(at, size)
	Audio.play("w_ignite", at)


## An elemental bomb landed: a poison cloud or a fire pool that keeps working on whoever stands in it while it lasts.
## `params.slow` slows whoever is inside (the Oil Slick's spills).
func spawn_cloud(at: Vector3, w: WeaponInstance, radius: float, element: String = "poison", params: Dictionary = {}) -> void:
	var c := ElementCloud.new()
	c.slow = float(params.get("slow", 0.0))
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
	fx.drop(at, fall)
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


func hell_line(from: Vector3, dir: Vector3, length: float, life: float, width: float, damage: float, tick: float, info: Dictionary) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var at := Vector3(from.x, map.height_at(from.x, from.z) if map else from.y, from.z)
	_hell_lines.append({"from": at, "dir": d, "len": length, "width": width, "life": life, "damage": damage, "tick": tick, "next": 0.0, "fx_t": 0.0, "info": info})
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
				# the crowd burns on it too, at half
				var steps := int(ceil(ln / 2.0))
				for k in range(steps):
					enemies.damage_radius(from + d * (float(k) + 0.5) * ln / float(steps), float(l["width"]) + 0.6, float(l["damage"]) * 0.5, "", 0.0)
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
	_ring["t"] = float(_ring["t"]) + delta
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
		player.take_damage(player.max_hp * float(cfg.get("burn", 0.07)) * 0.5, c, {"by": "the ring of fire", "kind": "boss", "fx": ["outside the ring"]})
		hud.flash(Color(1.0, 0.35, 0.1, 0.3), 0.3)
	# the crowd burns out there too, so the fight stays inside
	var cb := float(cfg.get("creature_burn", 0.12)) * 0.5
	if cb > 0.0:
		for i in range(EnemyManager.MAX):
			if enemies.alive[i] == 1 and i != enemies.boss_index:
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
