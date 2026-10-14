extends GdUnitTestSuite

## Pass 69, lane HERO (Garry: "Clean up everything to do with Mamy. Call her May"; Buck becomes "a slav in full sports
## suit", a Polish Sonic: Jeżyk, "little hedgehog"). May is `may` everywhere (her folder, files, looks MAY-x); her
## favourite is the Tommy Gun and her own Trigger Happy makes it fire without stop, along her facing when nobody is in
## range, each round weaker (ProjectileEmitter params `fire_without_target`, `stream`); her perk Inflatable May throws a
## doll every 30 s that fools the creatures round where it lands for 2 s (core/systems/Decoy.gd, the "decoy" special;
## EnemyManager.fool / decoy_target). Jeżyk (id buck) lands with the Frisbee, loves the Salt, owns Salt Flats; the deer
## looks are shelved, Drum Roll hidden, his charge as it was.

const LAUNCH := "user://debug_launch.json"
const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Run.arena_next = false


func after_test() -> void:
	if Save.sandboxed():
		Save.end_sandbox()
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	Run.arena_next = false
	Run.debug_clear_items()
	Run.end()
	if FileAccess.file_exists(LAUNCH):
		DirAccess.remove_absolute(LAUNCH)


## A real Game in the debug arena with `hero` (a hidden hero by name works there), the field emptied.
func _game(hero := "may") -> Game:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"arena": true, "character": hero, "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	g.clear_dummies()
	var em: EnemyManager = g.enemies
	for i in EnemyManager.MAX:
		if em.alive[i] == 1:
			em._free(i)
	em._rebuild_grid()
	return g


func _done(g: Game) -> void:
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


# ---------------------------------------------------------------- May

func test_may_loads_as_may_with_her_looks_and_no_mamy_is_left() -> void:
	var may: CharacterDef = Registry.character("may")
	assert_object(may).is_not_null()
	assert_object(Registry.character("mamy")).is_null()
	assert_str(may.display_name).is_equal("May")
	assert_str(may.pronoun).is_equal("she")
	# lane ART: the dev look MAY-G, played from pass 69; Garry picks her look in the Level Editor (2026-10-13: MAY-P, the
	# Puppet's): one of her own, its strip on disk
	assert_str(may.variant).starts_with("MAY-")
	assert_bool(may.variants.has(may.variant)).override_failure_message(may.variant).is_true()
	var played: Dictionary = may.variants.get(may.variant, {})
	assert_bool(ResourceLoader.exists("res://content/characters/may/" + str(played.get("sprite_file", may.sprite_file)))).override_failure_message(may.variant + " strip").is_true()
	assert_object(may.sprite).is_not_null()
	# pass 70 (lane LE): Garry had the base MAY-A removed in the Level Editor; MAY-G is her base and her look
	assert_array(may.variant_codes(true)).contains(["MAY-G", "MAY-B", "MAY-C"])
	# Garry's drafts come and go in the Level Editor (MAY-F became MAY-E while pass 69 shipped): only the shape is
	# pinned, every look under a MAY- code and a draft's `from` naming one of hers
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/may/may.json"))
	assert_bool((d["variants"] as Dictionary).has(may.variant)).is_true()
	for code in (d["variants"] as Dictionary).keys():
		var rec = (d["variants"][code] as Dictionary).get("recipe", {})
		if rec is Dictionary and (rec as Dictionary).has("from"):
			assert_str(str(rec["from"])).starts_with("MAY-")
	assert_str(str(d["variant_base"])).starts_with("MAY-")
	assert_bool((d["variants"] as Dictionary).has(str(d["variant_base"]))).is_true()
	for code in may.variants.keys():
		assert_str(str(code)).starts_with("MAY-")
	assert_bool(ResourceLoader.exists("res://content/characters/may/may_sprite_b.png")).is_true()
	assert_bool(ResourceLoader.exists("res://content/characters/may/" + str(d.get("icon", "may_icon.png")))).is_true()
	assert_bool(ResourceLoader.exists("res://content/characters/may/" + str(d.get("sprite", "may_sprite.png")))).is_true()
	assert_bool(DirAccess.dir_exists_absolute("res://content/characters/mamy")).is_false()
	# her trait stays (attack speed), her favourite is the Tommy Gun with a bonus that fits her
	assert_str(may.favourite_weapon).is_equal("tommy_gun")
	assert_float((may.level_trait[0] as Effect).value).is_equal_approx(-0.015, 0.00001)
	assert_str(str(may.favourite_bonus.get("type", ""))).is_equal("effects")
	# no content JSON anywhere names mamy as an id or a hero
	for c: CharacterDef in Registry.characters.values():
		assert_str(c.id).is_not_equal("mamy")
	for m: MutationDef in Registry.mutations.values():
		assert_str(m.hero).is_not_equal("mamy")
	for pk: PerkDef in Registry.perks.values():
		assert_str(pk.hero).is_not_equal("mamy")


func test_mays_kit_her_mutation_on_her_tommy_and_her_decoy_perk() -> void:
	var own: MutationDef = Registry.mutation("trigger_happy")
	assert_object(own).is_not_null()
	assert_str(own.mutation_kind).is_equal("hero")
	assert_str(own.hero).is_equal("may")
	assert_str(own.weapon).is_equal("tommy_gun")
	assert_bool(bool(own.params.get("fire_without_target", false))).is_true()
	assert_bool(bool(own.params.get("stream", false))).is_true()
	var pk: PerkDef = Registry.perk("inflatable_may")
	assert_object(pk).is_not_null()
	assert_str(pk.hero).is_equal("may")
	assert_str(pk.special).is_equal("decoy")
	for key in ["every", "throw_min", "throw_max", "flight", "radius", "duration"]:
		assert_bool(pk.params.has(key)).override_failure_message(key).is_true()
	assert_float(float(pk.params["every"])).is_equal(30.0)
	assert_float(float(pk.params["radius"])).is_equal(6.5)
	assert_float(float(pk.params["duration"])).is_equal(2.0)
	assert_bool(ResourceLoader.exists("res://content/characters/may/may_decoy.png")).is_true()


func test_trigger_happy_takes_a_third_off_every_round_and_fires_two_thirds_more() -> void:
	Run.start(Registry.character("may"), Registry.map("red_canyon"))
	var w := Run.add_weapon(Registry.weapon("tommy_gun"), 1)
	var dmg0 := w.stat("damage")
	var cd0 := w.stat("cooldown")
	assert_bool(Run.add_mutation("trigger_happy", true)).is_true()
	# true multipliers (StatSheet multiplies every mul): x0.65 damage, x0.6 cooldown
	assert_float(w.stat("damage") / dmg0).is_equal_approx(0.65, 0.0001)
	assert_float(w.stat("cooldown") / cd0).is_equal_approx(0.6, 0.0001)
	assert_bool(bool(w.params.get("fire_without_target", false))).is_true()
	# the stream: a burst spread over the whole cooldown (the last round just before the next pull)
	assert_float(ProjectileEmitter.stream_gap(1.4, 6)).is_equal_approx(1.4 * 0.97 / 6.0, 0.00001)
	assert_float(ProjectileEmitter.stream_gap(1.0, 0)).is_equal_approx(0.97, 0.00001)
	assert_float(ProjectileEmitter.stream_gap(1.0, 12) * 11.0).is_less(1.0)


func test_the_tommy_fires_with_nobody_in_range_only_with_trigger_happy() -> void:
	var g := _game("may")
	Run.add_weapon(Registry.weapon("tommy_gun"), 1)
	g._sync_weapons()
	var b: ProjectileEmitter = g._behaviors["tommy_gun"]
	assert_object(b).is_not_null()
	# nobody on the field: the plain Tommy holds its fire
	assert_bool(b._fire()).is_false()
	assert_int(b._burst.size()).is_equal(0)
	assert_bool(Run.add_mutation("trigger_happy", true)).is_true()
	g._sync_weapons()
	b = g._behaviors["tommy_gun"]
	g.player.facing = -PI * 0.5
	var fwd: Vector3 = g.player.forward()
	var shots0: int = g.projectiles.count
	assert_bool(b._fire()).is_true()
	# one round now, the rest streamed over the cooldown, along her facing
	var amount := b.stat_int("amount", 1)
	assert_int(b._burst.size()).is_equal(amount - 1)
	assert_float(b._stream_gap).is_equal_approx(ProjectileEmitter.stream_gap(b.stat("cooldown", 1.0), amount), 0.0001)
	assert_float(b._aim_dir.dot(fwd)).is_greater(0.99)
	assert_bool(b._stream_dir().is_equal_approx(fwd)).is_true()
	assert_int(g.projectiles.count).is_greater(shots0)
	# with a creature in range the stream aims at it
	var em: EnemyManager = g.enemies
	var i := _creature(em, g.player.global_position + Vector3(0, 0, 5.0))
	var to := (em.pos[i] - g.player.global_position)
	to.y = 0.0
	assert_float(b._stream_dir().dot(to.normalized())).is_greater(0.99)
	await _done(g)


# ---------------------------------------------------------------- Inflatable May

func test_the_decoy_cycle_throw_land_fool_inside_only_never_a_boss_then_pop() -> void:
	var g := _game("may")
	var em: EnemyManager = g.enemies
	assert_object(g.decoy).is_null()
	assert_bool(Run.add_perk("inflatable_may")).is_true()
	g._tick_decoy(0.0)
	var dc: Decoy = g.decoy
	assert_object(dc).is_not_null()
	assert_int(dc.phase).is_equal(Decoy.IDLE)
	# the first throw after `first` s
	var first := Decoy.param("first", 6.0)
	for k in range(int((first - 0.2) / 0.1)):
		g._tick_decoy(0.1)
	assert_int(dc.throws).is_equal(0)
	for k in range(4):
		g._tick_decoy(0.1)
	assert_int(dc.throws).is_equal(1)
	assert_int(dc.phase).is_equal(Decoy.FLYING)
	var here: Vector3 = g.player.global_position
	var flat := Vector2(dc.to.x - here.x, dc.to.z - here.z).length()
	assert_float(flat).is_between(3.99, 7.01)
	# not fooling yet while it flies: put a creature by where it will land, one outside the circle, and a boss inside
	var spot: Vector3 = dc.to
	var inside := _creature(em, spot + Vector3(2.0, 0, 0))
	var outside := _creature(em, spot + Vector3(0, 0, 9.0))
	var elite := em.spawn("skeleton", spot + Vector3(0, 0, -2.5), Registry.elites_list()[0] if not Registry.elites_list().is_empty() else null, 1.0, 50.0)
	var boss := em.spawn_boss("tumbleweed_king", spot + Vector3(-2.5, 0, 0))
	em.rise_t[boss] = 1.0
	em.state[boss] = EnemyManager.STATE_MOVE
	# (pass 73, lane GROUND, re-pinned on purpose: a spawn in a real game rises out of the ground first; this one is up)
	em.rise_t[elite] = 1.0
	em.rise_v[elite] = 0.0
	em.state[elite] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	assert_bool(em.decoy_on).is_false()
	assert_bool(em.is_fooled(inside)).is_false()
	# it flies `flight` s, then lands
	var fl := Decoy.param("flight", 0.6)
	g._tick_decoy(fl * 0.5)
	assert_int(dc.phase).is_equal(Decoy.FLYING)
	g._tick_decoy(fl * 0.5 + 0.01)
	# pass 70 (lane TRAMP, re-pinned on purpose): the puck lands short, slides to the spot and the doll inflates out of
	# it; only then does the fooling start
	assert_int(dc.phase).is_equal(Decoy.SLIDING)
	assert_bool(em.decoy_on).is_false()
	g._tick_decoy(Decoy.SLIDE_TIME + 0.01)
	assert_int(dc.phase).is_equal(Decoy.INFLATING)
	assert_bool(em.is_fooled(inside)).is_false()
	g._tick_decoy(Decoy.INFLATE_TIME + 0.01)
	assert_int(dc.phase).is_equal(Decoy.FOOLING)
	assert_bool(em.decoy_on).is_true()
	assert_bool(em.decoy_at.is_equal_approx(spot)).is_true()
	assert_bool(em.is_fooled(inside)).is_true()
	assert_bool(em.is_fooled(elite)).is_true()
	assert_bool(em.is_fooled(outside)).is_false()
	assert_bool(em.is_fooled(boss)).is_false()
	assert_bool(em.foolable(boss)).is_false()
	# a fooled creature's brain steers at the doll, the others at her
	var ppos: Vector3 = g.player.global_position
	var dt: Vector3 = em.decoy_target(inside, ppos)
	assert_float(Vector2(dt.x - spot.x, dt.z - spot.z).length()).is_less(0.001)
	assert_bool(em.decoy_target(outside, ppos).is_equal_approx(ppos)).is_true()
	assert_bool(em.decoy_target(boss, ppos).is_equal_approx(ppos)).is_true()
	# one that walks into the circle while the doll stands is fooled too
	em.pos[outside] = spot + Vector3(0, 0, 3.0)
	em._rebuild_grid()
	g._tick_decoy(Decoy.SCAN_EVERY + 0.01)
	assert_bool(em.is_fooled(outside)).is_true()
	# a "?" over each fooled one
	g._tick_decoy(0.05)
	assert_int(dc.marks_shown).is_equal(em.fooled_indices().size())
	assert_int(dc.marks_shown).is_equal(3)
	# the doll stands `duration` s in all, then pops and they hunt her again
	var dur := Decoy.param("duration", 2.0)
	while dc.t + 0.1 < dur:
		g._tick_decoy(0.1)
	assert_int(dc.phase).is_equal(Decoy.FOOLING)
	g._tick_decoy(0.15)
	assert_int(dc.phase).is_equal(Decoy.IDLE)
	assert_int(dc.pops).is_equal(1)
	assert_bool(em.decoy_on).is_false()
	assert_bool(em.is_fooled(inside)).is_false()
	assert_bool(em.decoy_target(inside, ppos).is_equal_approx(ppos)).is_true()
	assert_int(dc.marks_shown).is_equal(0)
	# the next throw `every` s after the last
	assert_float(dc.clock).is_less_equal(Decoy.param("every", 30.0))
	assert_float(dc.clock).is_greater(Decoy.param("every", 30.0) - fl - Decoy.SLIDE_TIME - Decoy.INFLATE_TIME - dur - 0.5)
	await _done(g)


func test_a_fooled_creature_bites_the_doll_not_her_and_a_new_spawn_in_its_slot_is_not_fooled() -> void:
	var g := _game("may")
	var em: EnemyManager = g.enemies
	var ppos: Vector3 = g.player.global_position
	var i := _creature(em, ppos + Vector3(0.3, 0, 0))
	em.contact_cd[i] = 0.0
	em.decoy_at = ppos + Vector3(20, 0, 0)
	em.decoy_on = true
	assert_bool(em.fool(i)).is_true()
	assert_bool(em.fool(i)).is_false()
	g.player.invuln = 0.0
	var hp0: float = g.player.hp
	var bites0 := em.decoy_bites
	em._physics_process(DT)
	assert_float(g.player.hp).is_equal(hp0)
	assert_int(em.decoy_bites).is_equal(bites0)
	# next to the doll it bites it (nothing happens to anyone)
	em.pos[i] = em.decoy_at + Vector3(0.3, 0, 0)
	em.contact_cd[i] = 0.0
	em._physics_process(DT)
	assert_int(em.decoy_bites).is_equal(bites0 + 1)
	assert_float(g.player.hp).is_equal(hp0)
	# the slot freed and spawned again is a new creature: not fooled
	em._free(i)
	var j := _creature(em, ppos + Vector3(4, 0, 0))
	if j == i:
		assert_bool(em.is_fooled(j)).is_false()
	em.unfool_all()
	assert_bool(em.decoy_on).is_false()
	await _done(g)


func test_no_decoy_node_without_the_perk() -> void:
	var g := _game("drifter")
	for k in range(100):
		g._tick_decoy(0.1)
	assert_object(g.decoy).is_null()
	assert_bool(Decoy.active()).is_false()
	await _done(g)


# ---------------------------------------------------------------- Jeżyk

func test_jezyk_is_buck_renamed_with_the_frisbee_the_salt_and_salt_flats() -> void:
	var j: CharacterDef = Registry.character("buck")
	assert_str(j.display_name).is_equal("Jeżyk")
	assert_str(j.start_weapon).is_equal("frisbee")
	assert_str(j.favourite_weapon).is_equal("salt")
	assert_str(Registry.start_weapon_for(j).id).is_equal("frisbee")
	assert_bool(j.specials.has("momentum")).is_true()
	assert_float(float(j.momentum["ramp_seconds"])).is_equal(10.0)
	assert_float(float(j.momentum["speed_bonus"])).is_equal_approx(0.8, 0.0001)
	# his own mutation is Salt Flats; Drum Roll is hidden, kept
	var sf: MutationDef = Registry.mutation("salt_flats")
	assert_object(sf).is_not_null()
	assert_str(sf.hero).is_equal("buck")
	assert_str(sf.weapon).is_equal("salt")
	assert_bool(Registry.mutation("drum_roll").hidden).is_true()
	var mine: Array = Registry.mutations.values().filter(func(m: MutationDef) -> bool: return m.hero == "buck" and not m.hidden)
	assert_int(mine.size()).is_equal(1)
	assert_str((mine[0] as MutationDef).id).is_equal("salt_flats")
	# the deer looks are shelved (kept), the one in play is never shelved
	assert_bool(j.variant_shelved("BUC-A")).is_true()
	assert_bool(j.variant_shelved("BUC-C")).is_true()
	assert_bool(j.variant_shelved(j.variant)).is_false()


func test_no_word_of_his_mentions_a_deer_any_more() -> void:
	var j: CharacterDef = Registry.character("buck")
	var words: Array = [j.display_name, j.flavour, j.trait_name, j.trait_text]
	for pk: PerkDef in Registry.perks_of("buck"):
		words.append(pk.display_name)
		words.append(pk.text)
		words.append(pk.flavour)
	words.append(Registry.mutation("salt_flats").text)
	for w in words:
		for bad in ["antler", "gazelle", "deer", "Buck"]:
			assert_bool(str(w).contains(bad)).override_failure_message("%s says %s" % [w, bad]).is_false()
	# his top-level art words are the tracksuit now; the deer's live on in the shelved looks' recipes
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/buck/buck.json"))
	assert_str(str(d["art_prompt"])).contains("track jacket")
	assert_bool(str(d["art_prompt"]).contains("antler")).is_false()
	assert_bool(str(d.get("appearance", "")).contains("blue skin")).is_true()
	assert_bool(str(d["variants"]["BUC-B"]["recipe"]["art_prompt"]).contains("antlers")).is_true()
