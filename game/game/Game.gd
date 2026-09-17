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
var structure_shop: StructureShop
var chest_screen: ChestScreen
var paused := false
var hud: HUD
var cards: CardScreen
var pause_screen: PauseScreen
var portal_dialog: PortalDialog
var hints: Hints
var debug_panel: DebugPanel
var _pending_levels := 0
var _spit_kind := -1
var _behaviors: Dictionary = {}    # weapon id -> WeaponBehavior
var _ended := false
var _run_started := false


func _ready() -> void:
	var character_id: String = str(Save.data.get("last_character", "astro"))
	var map_id: String = str(Save.data.get("last_map", "dry_gulch"))
	var debug_launch := _read_debug_launch()
	if debug_launch.has("character"):
		character_id = str(debug_launch["character"])
	if debug_launch.has("map"):
		map_id = str(debug_launch["map"])
	var character: CharacterDef = Registry.character(character_id)
	if character == null and not Registry.characters.is_empty():
		character = Registry.sorted_characters()[0]
	var mapdef: MapDef = Registry.map(map_id)
	if mapdef == null and not Registry.maps.is_empty():
		mapdef = Registry.sorted_maps()[0]
	Run.start(character, mapdef)
	# map
	if mapdef and mapdef.scene:
		map = mapdef.scene.instantiate()
	else:
		map = load("res://world/maps/dry_gulch/DryGulch.tscn").instantiate()
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
	# systems
	enemies.game = self
	enemies.player = player
	enemies.height_fn = map.height_at
	enemies.obstacles = map.obstacles
	enemies.arena_radius = map.arena_radius
	telegraphs.height_fn = map.height_at
	enemies.enemy_died.connect(_on_enemy_died)
	projectiles.game = self
	pickups.game = self
	_spit_kind = projectiles.register_kind(_spit_mesh(), _spit_material(), 1.0)
	director = WaveDirector.new()
	director.game = self
	add_child(director)
	# the map's structures, scattered once per run
	structures = StructureManager.new()
	add_child(structures)
	if mapdef and mapdef.timeline and not mapdef.timeline.structures.is_empty():
		structures.setup(self, map, mapdef.timeline.structures)
	director.portal_ready.connect(_on_portal_ready)
	director.boss_started.connect(func(def): if hud: hud.show_boss(def))
	director.stage_started.connect(func(s): if hud: hud.refresh_stage())
	enemies.boss_hp_changed.connect(func(hp, mx): if hud: hud.set_boss_hp(hp, mx))
	enemies.boss_died.connect(func(_d, _p): if hud: hud.hide_boss())
	Run.level_up.connect(_on_level_up)
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
	hints.begin()
	hud.refresh_stage()


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
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _run_started and not paused and not _ended:
			open_pause()


# ---------------------------------------------------------------- weapons

func _sync_weapons() -> void:
	var t0 := Time.get_ticks_usec()
	for w in Run.weapons:
		var id: String = w.def.id
		if _behaviors.has(id):
			var b: WeaponBehavior = _behaviors[id]
			b.inst = w
			continue
		var b := _make_behavior(w.def.behavior)
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


func _make_behavior(name: String) -> WeaponBehavior:
	match name:
		"ProjectileEmitter":
			return ProjectileEmitter.new()
		"Orbiter":
			return Orbiter.new()
		"Lobber":
			return Lobber.new()
		"Beam":
			return Beam.new()
		"Spawner":
			return Spawner.new()
	push_warning("Unknown weapon behaviour: " + name)
	return null


func _on_evolved(id: String) -> void:
	var def := Registry.weapon(id)
	Audio.play("w_evo_reveal")
	hud.banner("EVOLVED: " + (def.display_name if def else id), UiKit.TYPE_COLORS["evolution"])
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
	var t0 := Time.get_ticks_usec()
	hud.tick(delta)
	hints.tick(delta)
	Perf.add("hud", t0)
	Perf.frame()
	if int(Run.elapsed) % 5 == 0 and int(Run.elapsed * 10.0) % 50 == 0:
		_check_quests()


var _last_quest_check := -1
func _check_quests() -> void:
	var s := int(Run.elapsed)
	if s == _last_quest_check:
		return
	_last_quest_check = s
	for id in QuestTracker.check_all(true):
		var q: QuestDef = Registry.quests[id]
		hud.banner("UNLOCKED: " + q.display_name, UiKit.GOOD)
		Audio.play("ui_unlock")


func _on_level_up(level: int) -> void:
	Perf.context = "levelup %d" % level
	_pending_levels += 1
	Audio.play("ui_levelup")
	hud.flash_level(level)
	if not cards.visible and not portal_dialog.visible and not chest_screen.visible:
		_show_next_level_cards()


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
		Run.add_gold(10)
		hud.toast("Skipped. +10 gold", UiKit.INK2)
	else:
		var t1 := Time.get_ticks_usec()
		var line := CardPool.apply(card)
		Perf.add("card.apply", t1)
		hud.toast(line, UiKit.ACCENT)
	var t2 := Time.get_ticks_usec()
	Save.mark_hint("cards")
	set_paused(false)
	Perf.add("card.unpause", t2)
	if _pending_levels > 0:
		await get_tree().create_timer(0.2).timeout
		_show_next_level_cards()


func _on_enemy_died(def: EnemyDef, at: Vector3, elite: EliteModDef, _weapon_id: String) -> void:
	var xp_scale := def.xp_mult * (4.0 if elite else 1.0)
	pickups.drop_from(def, at, xp_scale, elite != null)
	# chests: every elite variant and the mini-boss, the odd regular creature (drops.chest in its JSON)
	if elite != null or def.archetype == "elite" or randf() < float(def.drops.get("chest", 0.0)):
		pickups.spawn_chest(at)
	if def.archetype == "boss":
		for k in range(12):
			pickups.spawn(PickupManager.KIND_COIN, at + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 5.0)
		fx.burst(at + Vector3(0, 1, 0), Color(1.0, 0.75, 0.3), 5.0)
		camera.shake(1.5)
	elif def.archetype == "elite":
		fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.65, 0.3), 3.0)
		camera.shake(0.9)
	else:
		fx.burst(at + Vector3(0, 0.4, 0), Color(0.95, 0.85, 0.7), def.size * 0.6)


## The hero finished using a structure (content/structures).
func use_structure(def: StructureDef, at: Vector3) -> void:
	var p: Dictionary = def.params
	Audio.play("pk_chest_open", at)
	fx.burst(at + Vector3(0, 1.0, 0), def.color, 2.0)
	telegraphs.flash_ring(at, def.radius + 0.5, def.color, 0.5)
	camera.shake(0.4)
	match def.effect_kind:
		"vacuum_all":
			pickups.vacuum_all(true)
			hud.banner(def.display_name.to_upper(), def.color)
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
	match def.effect_kind:
		"heal":
			var amount: float = player.max_hp * def.value
			player.heal(amount)
			hud.toast("+%d HP" % int(round(amount)), UiKit.GOOD)
			Audio.play("pk_heart", at)
		"buff":
			Run.add_timed_effects(def.id, def.display_name, def.effects, def.duration)
			hud.toast("%s: %s for %d s" % [def.display_name.to_upper(), TextGen.describe_effects(def.effects), int(def.duration)], def.color)
			Audio.play("pk_powerup", at)
		"shield":
			player.shield(def.duration)
			hud.toast("SHIELD for %d s" % int(def.duration), def.color)
			Audio.play("pk_powerup", at)
		"vacuum":
			pickups.vacuum_all()
			hud.toast("MAGNET PULSE", def.color)
		_:
			Audio.play("pk_powerup", at)
	fx.burst(at + Vector3(0, 0.8, 0), def.color, 1.3)
	telegraphs.flash_ring(at, 2.0, def.color, 0.35)


## A chest on the ground was touched: the game pauses and the reel decides in front of the player.
func open_chest(at: Vector3) -> void:
	Audio.play("pk_chest_open", at)
	fx.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4), 1.5)
	if _ended:
		return
	var r := Run.chest_roll()
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
	set_paused(false)
	if _pending_levels > 0:
		await get_tree().create_timer(0.2).timeout
		_show_next_level_cards()


func _on_portal_ready(at: Vector3) -> void:
	portal = Portal.new()
	add_child(portal)
	portal.global_position = at
	portal.entered.connect(_on_portal_entered)
	hud.toast("PORTAL OPEN: extract or continue", UiKit.GOOD)


func _on_portal_entered() -> void:
	set_paused(true)
	var final_stage: bool = Run.stage + 1 >= Run.map.timeline.stages if Run.map and Run.map.timeline else false
	var can_continue := true
	if final_stage and not Registry.is_unlocked("mode", "endless"):
		can_continue = false
	portal_dialog.open(Run.stage + 1, can_continue, final_stage)
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
		hud.banner("STAGE %d" % (Run.stage + 1) if not Run.endless else "ENDLESS", UiKit.ACCENT)


func _on_player_died() -> void:
	hud.hide_player_bar()
	var revives := Run.player_sheet.get_int("revives", 0)
	if Run.revives_used < revives:
		Run.revives_used += 1
		await get_tree().create_timer(1.0).timeout
		if _ended:
			return
		player.revive()
		enemies.damage_radius(player.global_position, 6.0, 0.0, "", 12.0)
		telegraphs.flash_ring(player.global_position, 6.0, UiKit.GOOD, 0.6)
		hud.banner("REVIVED", UiKit.GOOD)
		return
	Run.died = true
	end_run()


func end_run() -> void:
	if _ended:
		return
	_ended = true
	director.stop()
	QuestTracker.check_all(true)
	var gold := Run.run_gold
	if Run.extracted:
		gold = int(round(gold * 1.25))
	Save.add_gold(gold)
	Save.record_run(Run.map.id if Run.map else "", Run.elapsed, Run.level, Run.stage + 1)
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

func telegraph_ring(center: Vector3, r: float, dur: float, color: Color, filled := true) -> void:
	telegraphs.ring(center, r, dur, color, filled)


func telegraph_line(from: Vector3, dir: Vector3, length: float, dur: float, color: Color) -> void:
	telegraphs.line(from, dir, length, dur, color)


func shockwave(center: Vector3, r: float) -> void:
	telegraphs.flash_ring(center, r, Color(1.0, 0.6, 0.3), 0.4)
	fx.burst(center + Vector3(0, 0.5, 0), Color(1.0, 0.7, 0.4), r * 0.6)
	camera.shake(1.0)


func elite_explosion(center: Vector3, r: float, damage: float, delay: float) -> void:
	telegraphs.ring(center, r, delay, UiKit.DANGER, true)
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func():
		if _ended:
			return
		var d := player.global_position - center
		d.y = 0.0
		if d.length() <= r + 0.4:
			player.take_damage(damage, center)
		fx.burst(center + Vector3(0, 0.6, 0), UiKit.DANGER, r * 0.7)
		camera.shake(0.6)
		Audio.play("w_lob_boom", center))


func enemy_spit(from: Vector3, target: Vector3, speed: float, damage: float, splash: float) -> void:
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var dist: float = max(flat.length(), 0.5)
	var t: float = clamp(dist / max(speed, 1.0), 0.4, 2.0)
	var vy := ((target.y - from.y) + 0.5 * 24.0 * t * t) / t
	projectiles.hostile_shot(_spit_kind, from, flat / t + Vector3(0, vy, 0), damage, splash, t + 0.5, true)


func fx_poison(at: Vector3) -> void:
	fx.poison(at)


func fx_fire(at: Vector3, size: float = 1.0) -> void:
	fx.fire(at, size)


func fx_ignite(at: Vector3, size: float = 1.0) -> void:
	fx.ignite(at, size)
	Audio.play("w_ignite", at)


## An elemental bomb landed: a poison cloud or a fire pool that keeps working on whoever stands in it while it lasts.
func spawn_cloud(at: Vector3, w: WeaponInstance, radius: float, element: String = "poison") -> void:
	var c := ElementCloud.new()
	if element == "fire":
		c.setup(self, w, radius, float(w.def.params.get("cloud_seconds", 3.0)), w.stat("fire_damage", 4.0), 1, w.stat("fire_duration", 1.8), "fire", w.stat("fire_spread", 0.5))
	else:
		c.setup(self, w, radius, float(w.def.params.get("cloud_seconds", 4.0)), w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
	add_child(c)
	c.global_position = at


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
