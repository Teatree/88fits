extends GdUnitTestSuite

## Pass 46, the hero lane: Ironwood (good at regen, no more health than anyone, the Spear in his hands, Cake at its top
## level the moment he finds it; pass 47: the pike called the Spear, Brawn at level 2), his perks Unbroken and Deep Breath, the hit invulnerability and the revive's share from
## the sheet, the Down! log's rows (role, colour, pickup heals but never regen) and their plain-word copy text, and the
## Down! screen that lists them newest first with a red X on the hit that ended it.


func _hero(id: String = "ironwood") -> Player:
	Run.start(Registry.character(id), Registry.map("red_canyon"))
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character(id))
	p.hp = p.max_hp
	return p


## Five rows as Player.damage_log keeps them (oldest first): a bite, a heart, a special's harpoon in its colour, an
## evaded Elite, and the boss's slam that ended it.
func _rows() -> Array:
	return [
		{"t": 10.0, "by": "Goblin", "id": "goblin", "kind": "melee", "role": "", "colour": "", "fx": [], "raw": 6.0,
			"dealt": 6.0, "shield": 0.0, "note": "", "hp": 40.0, "fatal": false},
		{"t": 11.0, "by": "Heart", "id": "", "kind": "heal", "role": "", "colour": "", "fx": [], "raw": 20.0, "amount": 20.0,
			"dealt": 0.0, "shield": 0.0, "note": "", "hp": 60.0, "fatal": false},
		{"t": 12.0, "by": "Harpoon Troglodyte", "id": "harpoon_troglodyte", "kind": "ranged", "role": "special",
			"colour": "#2a5a30", "fx": ["hooked"], "raw": 12.0, "dealt": 12.0, "shield": 0.0, "note": "", "hp": 48.0, "fatal": false},
		{"t": 13.0, "by": "Dune Scorpion (Elite)", "id": "dune_scorpion", "kind": "melee", "role": "elite", "colour": "",
			"fx": [], "raw": 30.0, "dealt": 0.0, "shield": 0.0, "note": "evaded", "hp": 48.0, "fatal": false},
		{"t": 14.0, "by": "The Brander", "id": "brander", "kind": "boss", "role": "boss", "colour": "", "fx": ["slam"],
			"raw": 60.0, "dealt": 48.0, "shield": 0.0, "note": "", "hp": 0.0, "fatal": true},
	]


# ---------------------------------------------------------------- Ironwood

func test_ironwood_heals_well_with_no_more_health_than_anyone() -> void:
	var iw: CharacterDef = Registry.character("ironwood")
	assert_object(iw).is_not_null()
	var regen := 0.0
	var delay := 0.0
	for e: Effect in iw.trait_effects:
		assert_str(e.stat).override_failure_message("Ironwood's trait touches max_hp").is_not_equal("max_hp")
		if e.stat == "regen" and e.op == "add":
			regen += e.value
		if e.stat == "regen_delay" and e.op == "add":
			delay += e.value
	assert_float(regen).is_equal_approx(1.2, 0.001)
	assert_float(delay).is_equal_approx(-1.5, 0.001)
	# his trait over the defaults: the regen restarts 1.5 s after a hit, and the health is everyone's
	var sheet := StatSheet.new()
	sheet.scope = "player"
	sheet.set_bases(StatSheet.PLAYER_DEFAULTS)
	sheet.add_effects(iw.trait_effects, "trait")
	assert_float(sheet.get_stat("max_hp")).is_equal(float(StatSheet.PLAYER_DEFAULTS["max_hp"]))
	assert_float(sheet.get_stat("regen")).is_equal_approx(1.2, 0.001)
	assert_float(sheet.get_stat("regen_delay")).is_equal_approx(1.5, 0.001)
	assert_float(iw.level_heal).is_equal(0.0)
	assert_str(iw.trait_name).is_equal("Enduring")
	assert_str(iw.pronoun).is_equal("he")
	# the Spear in his hands (pass 47: the pike, called the Spear), Brawn his favourite at level 2, two perks of his own
	assert_str(iw.start_weapon).is_equal("pike")
	assert_str(iw.favourite_passive).is_equal("brawn")
	assert_str(str(iw.favourite_passive_bonus.get("type", ""))).is_equal("level")
	assert_int(int(iw.favourite_passive_bonus.get("value", 0))).is_equal(2)
	var ids: Array = []
	for pk: PerkDef in Registry.perks_of("ironwood"):
		ids.append(pk.id)
	assert_array(ids).contains_exactly(["deep_breath", "unbroken"])
	var db: PerkDef = Registry.perk("deep_breath")
	assert_float(float(db.params.get("below", 0.0))).is_equal_approx(0.35, 0.001)
	assert_float(float(db.params.get("mult", 0.0))).is_equal_approx(4.0, 0.001)
	assert_float(float(db.params.get("seconds", 0.0))).is_equal_approx(6.0, 0.001)
	assert_float(float(db.params.get("cooldown", 0.0))).is_equal_approx(40.0, 0.001)
	assert_str(Registry.perk("unbroken").special).is_equal("unbroken")


func test_his_brawn_arrives_at_level_two() -> void:
	# pass 47 (Garry: "the favorite item to be the one that's the damage on attack, not the Cake"): Brawn at level 2;
	# Cake is anyone's again
	Run.start(Registry.character("ironwood"), Registry.map("red_canyon"))
	var brawn: PassiveDef = Registry.passive("brawn")
	assert_object(brawn).is_not_null()
	assert_bool(Run.add_or_level_passive("brawn")).is_true()
	assert_int(Run.passive_level("brawn")).is_equal(2)
	assert_bool(Run.add_or_level_passive("cake")).is_true()
	assert_int(Run.passive_level("cake")).is_equal(1)
	# anyone else finds Brawn at level 1
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_or_level_passive("brawn")
	assert_int(Run.passive_level("brawn")).is_equal(1)
	Run.end()


# ---------------------------------------------------------------- his perks

func test_unbroken_keeps_the_regen_running_through_a_hit() -> void:
	var p := _hero()
	p.hp = p.max_hp * 0.6
	p.take_damage(5.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	# without the perk a hit holds the regen (his trait makes it 1.5 s)
	assert_float(p.regen_hold).is_equal_approx(Run.player_sheet.get_stat("regen_delay", 3.0), 0.001)
	assert_float(p.regen_hold).is_greater(0.0)
	assert_bool(Run.add_perk("unbroken")).is_true()
	p.regen_hold = 0.0
	p.invuln = 0.0
	p.take_damage(5.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_float(p.regen_hold).is_equal(0.0)
	# the health climbs straight after the hit
	var regen := Run.player_sheet.get_stat("regen", 0.0)
	var before := p.hp
	p._tick_regen(0.5)
	assert_float(p.hp).is_equal_approx(minf(before + regen * 0.5, p.max_hp), 0.001)
	Run.end()


func test_deep_breath_runs_the_regen_four_times_over_once_every_forty_seconds() -> void:
	var p := _hero()
	assert_bool(Run.add_perk("deep_breath")).is_true()
	var regen := Run.player_sheet.get_stat("regen", 0.0)
	assert_float(regen).is_greater(0.0)
	var fired := [0]
	p.deep_breath.connect(func(): fired[0] += 1)
	# above 35% nothing happens
	p.hp = p.max_hp * 0.5
	p._tick_regen(0.1)
	assert_int(fired[0]).is_equal(0)
	assert_float(p.deep_breath_t).is_equal(0.0)
	# under it: the breath, four times the regen from this tick on
	p.hp = p.max_hp * 0.2
	p.regen_hold = 0.0
	var before := p.hp
	p._tick_regen(1.0)
	assert_int(fired[0]).is_equal(1)
	assert_float(p.hp - before).is_equal_approx(regen * 4.0, 0.001)
	assert_float(p.deep_breath_t).is_equal_approx(6.0, 0.001)
	# it lasts its 6 s, and while he stays low it does not come again before 40 s have passed
	for k in range(39):
		p.hp = p.max_hp * 0.2
		p.regen_hold = 0.0
		var hp0 := p.hp
		p._tick_regen(1.0)
		if k < 5:
			assert_float(p.hp - hp0).override_failure_message("second %d of the breath" % (k + 2)).is_equal_approx(regen * 4.0, 0.001)
		elif k == 5:
			assert_float(p.deep_breath_t).is_equal(0.0)
			assert_float(p.hp - hp0).is_equal_approx(regen, 0.001)
	assert_int(fired[0]).is_equal(1)
	p.hp = p.max_hp * 0.2
	p._tick_regen(1.0)
	assert_int(fired[0]).is_equal(2)
	Run.end()


func test_no_breath_without_the_perk() -> void:
	var p := _hero()
	p.hp = p.max_hp * 0.1
	p._tick_regen(1.0)
	assert_float(p.deep_breath_t).is_equal(0.0)
	Run.end()


# ---------------------------------------------------------------- the sheet's numbers

func test_the_hit_invulnerability_comes_from_the_sheet() -> void:
	var p := _hero("astro")
	p.take_damage(5.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_float(p.invuln).is_equal_approx(0.5, 0.0001)
	Run.player_sheet.add_effects([Effect.make("hit_invuln", "add", 0.25, "player")], "test")
	p.invuln = 0.0
	p.take_damage(5.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_float(p.invuln).is_equal_approx(0.75, 0.0001)
	Run.player_sheet.remove_source("test")
	Run.end()


func test_a_revive_returns_the_sheets_share_of_health() -> void:
	var p := _hero("astro")
	p.take_damage(99999.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_bool(p.dead).is_true()
	p.revive()
	assert_bool(p.dead).is_false()
	var share := Run.player_sheet.get_stat("revive_hp", 0.5)
	assert_float(p.hp).is_equal_approx(clampf(p.max_hp * share, 1.0, p.max_hp), 0.001)
	# Second Wind's ranks raise it
	Run.player_sheet.add_effects([Effect.make("revive_hp", "add", 0.3, "player")], "test")
	p.invuln = 0.0
	p.take_damage(99999.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	p.revive()
	assert_float(p.hp).is_equal_approx(clampf(p.max_hp * (share + 0.3), 1.0, p.max_hp), 0.001)
	Run.player_sheet.remove_source("test")
	Run.end()


# ---------------------------------------------------------------- the log

func test_the_log_keeps_the_role_and_the_colour() -> void:
	var p := _hero("astro")
	p.hp = p.max_hp
	var hits := [
		{"by": "Goblin", "kind": "melee", "id": "goblin", "role": "", "colour": ""},
		{"by": "Dune Scorpion (Elite)", "kind": "melee", "id": "dune_scorpion", "role": "elite", "colour": "#8a4fb0"},
		{"by": "Harpoon Troglodyte", "kind": "ranged", "id": "harpoon_troglodyte", "role": "special", "colour": Color(0.2, 0.6, 0.3)},
		# a boss's attack with no role says so by its kind; an Elite flag without a role is read too
		{"by": "the ring of fire", "kind": "boss"},
		{"by": "Sun Prophet (Elite)", "kind": "ranged", "elite": true},
	]
	for h: Dictionary in hits:
		p.invuln = 0.0
		p.take_damage(2.0, Vector3.ZERO, h)
	var rows: Array = p.damage_log
	assert_int(rows.size()).is_equal(5)
	assert_str(str(rows[0]["role"])).is_equal("")
	assert_str(str(rows[0]["id"])).is_equal("goblin")
	assert_str(str(rows[1]["role"])).is_equal("elite")
	assert_str(str(rows[1]["colour"])).is_equal("#8a4fb0")
	assert_str(str(rows[2]["role"])).is_equal("special")
	assert_str(str(rows[2]["colour"])).is_equal("#" + Color(0.2, 0.6, 0.3).to_html(false))
	assert_str(str(rows[2]["kind"])).is_equal("ranged")
	assert_str(str(rows[3]["role"])).is_equal("boss")
	assert_str(str(rows[3]["colour"])).is_equal("")
	assert_str(str(rows[4]["role"])).is_equal("elite")
	for r: Dictionary in rows:
		for key: String in ["t", "by", "id", "kind", "role", "colour", "fx", "raw", "dealt", "shield", "note", "hp", "fatal"]:
			assert_bool(r.has(key)).override_failure_message("a row has no " + key).is_true()
	# a colour that is not one is dropped
	assert_str(Player.colour_of("not a colour")).is_equal("")
	assert_str(Player.colour_of(null)).is_equal("")
	Run.end()


func test_pickup_heals_are_listed_and_regen_is_not() -> void:
	var p := _hero("astro")
	p.hp = p.max_hp * 0.5
	var n := p.damage_log.size()
	# regen, lifesteal and the level patch name no source: no row
	p.heal(10.0)
	assert_int(p.damage_log.size()).is_equal(n)
	Run.player_sheet.add_effects([Effect.make("regen", "add", 2.0, "player")], "test")
	p.regen_hold = 0.0
	p._tick_regen(1.0)
	Run.player_sheet.remove_source("test")
	assert_int(p.damage_log.size()).is_equal(n)
	# a pickup does
	var before := p.hp
	p.heal(20.0, "Heart")
	assert_int(p.damage_log.size()).is_equal(n + 1)
	var row: Dictionary = p.damage_log.back()
	assert_str(str(row["kind"])).is_equal("heal")
	assert_str(str(row["by"])).is_equal("Heart")
	assert_float(float(row["amount"])).is_equal_approx(p.hp - before, 0.001)
	assert_float(float(row["hp"])).is_equal_approx(p.hp, 0.001)
	assert_bool(bool(row["fatal"])).is_false()
	assert_str(p.damage_log_text()).contains("  heal  Heart  +20 HP, %d left" % roundi(p.hp))
	# one that gave nothing back (full health) is not
	p.hp = p.max_hp
	p.heal(20.0, "Heart")
	assert_int(p.damage_log.size()).is_equal(n + 1)
	# the fatal mark stays on the hit, never on a heal
	p.take_damage(99999.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_bool(bool((p.damage_log.back() as Dictionary)["fatal"])).is_true()
	assert_str(str((p.damage_log.back() as Dictionary)["kind"])).is_equal("melee")
	Run.end()


func test_the_copy_text_is_plain_words() -> void:
	var text := Player.log_text(_rows())
	var lines := text.split("\n")
	assert_int(lines.size()).is_equal(5)
	assert_str(lines[0]).is_equal("FATAL 0:14.0  boss  The Brander  −48 HP, 0 left (damage reduction took 12)  · slam")
	assert_str(lines[1]).is_equal("0:13.0  elite  Dune Scorpion (Elite)  evaded (30)")
	assert_str(lines[2]).is_equal("0:12.0  special, ranged  Harpoon Troglodyte  −12 HP, 48 left  · hooked")
	assert_str(lines[3]).is_equal("0:11.0  heal  Heart  +20 HP, 60 left")
	assert_str(lines[4]).is_equal("0:10.0  melee  Goblin  −6 HP, 40 left")
	for emoji: String in [char(0x1F480), char(0x1F451), char(0x1F3F9), char(0x1F5E1)]:
		assert_str(text).not_contains(emoji)
	assert_str(Player.log_text([])).is_equal("nothing hit you in the last 30 seconds")


# ---------------------------------------------------------------- Down!

func _down() -> ReviveScreen:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var rs := ReviveScreen.new()
	host.add_child(rs)
	return rs


func test_down_lists_the_last_seconds_with_an_x_on_the_hit_that_ended_it() -> void:
	var was_log: bool = Settings.hit_log
	var was_debug: bool = Settings.debug_mode
	Settings.hit_log = true
	Settings.debug_mode = false
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var rows := _rows()
	var rs := _down()
	rs.open(300, 1, "", rows.back(), rows)
	rs._held = true
	assert_bool(rs._log_panel.visible).is_true()
	var list: VBoxContainer = rs.find_child("HitList", true, false)
	assert_int(list.get_child_count()).is_equal(5)
	# newest first: the fatal hit on top, the only one with the X
	var top: Control = list.get_child(0)
	assert_bool(bool(top.get_meta("fatal", false))).is_true()
	assert_object(top.find_child("FatalX", true, false)).is_not_null()
	for k in range(1, 5):
		assert_object(list.get_child(k).find_child("FatalX", true, false)).is_null()
	assert_str((top.find_child("When", true, false) as WText).text).is_equal("0.0 s")
	assert_str((list.get_child(4).find_child("When", true, false) as WText).text).is_equal("−4.0 s")
	# the boss wears the skull, the Elite the crown, the special the gear; a plain bite none
	var skull := ReviveScreen.badge_for({"role": "boss"})
	assert_object(skull).is_not_null()
	assert_object((top.find_child("Badge", true, false) as TextureRect).texture).is_same(skull)
	assert_object((list.get_child(1).find_child("Badge", true, false) as TextureRect).texture).is_same(ReviveScreen.badge_for({"role": "elite"}))
	assert_object((list.get_child(2).find_child("Badge", true, false) as TextureRect).texture).is_same(ReviveScreen.badge_for({"role": "special"}))
	assert_object((list.get_child(4).find_child("Badge", true, false) as TextureRect).texture).is_null()
	assert_object(ReviveScreen.badge_for({"role": "elite"})).is_not_null()
	# the hit's cost in red, the evade in words, the special's name in its colour (lifted to read on the ink), the heal
	# in green with a plus
	var cost: WText = top.find_child("Amount", true, false)
	assert_str(cost.text).is_equal("−48")
	assert_bool(cost.color.is_equal_approx(ReviveScreen.HIT_RED)).is_true()
	assert_str((list.get_child(1).find_child("Amount", true, false) as WText).text).is_equal("evaded")
	var special_name: WText = list.get_child(2).find_child("Name", true, false)
	assert_str(special_name.text).is_equal("Harpoon Troglodyte")
	assert_bool(special_name.color.is_equal_approx(ReviveScreen.readable(Color.html("#2a5a30")))).is_true()
	assert_float(special_name.color.get_luminance()).is_greater_equal(0.44)
	assert_bool((top.find_child("Name", true, false) as WText).color.is_equal_approx(W.PAPER)).is_true()
	var heal: WText = list.get_child(3).find_child("Amount", true, false)
	assert_str(heal.text).is_equal("+20")
	assert_bool(heal.color.is_equal_approx(ReviveScreen.HEAL_GREEN)).is_true()
	# the line under the count names the killer, and the copy button copies the words
	assert_str(str(rs._killer.runs[0][0])).is_equal("The Brander")
	assert_str(rs._log_text).is_equal(Player.log_text(rows))
	# the gold the sand keeps, with its coin
	assert_bool(rs._gold_row.visible).is_true()
	assert_str(rs._gold_line.text).contains("300")
	assert_object(rs._gold_coin.get_parent()).is_same(rs._gold_row)
	rs._decide("debug")
	Settings.hit_log = was_log
	Settings.debug_mode = was_debug
	Run.end()


func test_down_still_takes_an_older_callers_text_and_shows_the_list_only_when_asked() -> void:
	var was_log: bool = Settings.hit_log
	var was_debug: bool = Settings.debug_mode
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var rs := _down()
	# the player's debug mode shows the list too
	Settings.hit_log = false
	Settings.debug_mode = true
	rs.open(200, 1, "an older caller's log")
	rs._held = true
	assert_bool(rs._log_panel.visible).is_true()
	var list: VBoxContainer = rs.find_child("HitList", true, false)
	assert_int(list.get_child_count()).is_equal(1)
	assert_str((list.get_child(0) as WText).text).is_equal("an older caller's log")
	assert_object(list.find_child("FatalX", true, false)).is_null()
	# an older caller's killer line, with its badge by its kind
	rs.open(0, 1, "", {"by": "The Tumbleweed King", "kind": "boss"})
	rs._held = true
	assert_str(str(rs._killer.runs[0][0])).is_equal("The Tumbleweed King")
	assert_object(rs._killer_icon.texture).is_same(ReviveScreen.badge_for({"role": "boss"}))
	assert_bool(rs._gold_row.visible).is_false()
	assert_str((list.get_child(0) as WText).text).is_equal("nothing hit you in the last 30 seconds")
	# neither switch: no list
	Settings.debug_mode = false
	rs.open(0, 1, "", {}, _rows())
	rs._held = true
	assert_bool(rs._log_panel.visible).is_false()
	rs._decide("debug")
	Settings.hit_log = was_log
	Settings.debug_mode = was_debug
	Run.end()


# ---------------------------------------------------------------- the Spear (its weapon lane makes it; last, so the rest
# of the suite runs while it is not there yet)

func test_the_spear_is_his_alone() -> void:
	# pass 47: the thrown spear is kept as the hidden Throwing Spear (still his), and he lands with the pike, which the
	# player knows as the Spear
	var iw: CharacterDef = Registry.character("ironwood")
	var spear: WeaponDef = Registry.weapon("spear")
	assert_object(spear).override_failure_message("content/weapons/spear is not there").is_not_null()
	if spear == null:
		return
	assert_str(spear.hero).is_equal("ironwood")
	assert_bool(Registry.is_hidden(spear)).is_true()
	assert_object(Registry.start_weapon_for(iw)).is_same(Registry.weapon("pike"))
	assert_str(Registry.start_weapon_for(iw).display_name).is_equal("Spear")
