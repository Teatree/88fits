extends GdUnitTestSuite

## Pass 138, lane TEXTS (Garry: "Dynamite stick description has a few texts mushed together, 'It lies where it lands and
## blows {when}.' is not part of it and neither is 'Knocks enemies back.'. Should be that the description is just: 'Lobs
## {amount} {thing} at the densest crowd. Explodes in a {area} m radius.'"; "the Evolution text is huge ... Just give it a
## short description that accurately describes what the Evolution does. At the bottom add a note saying that all the
## previously claimed mutations still apply"; "Don't change any texts associated with the items that I changed"): a
## weapon's description is its own row and nothing glued on, an evolution's is its row and the mutations note on a line
## of its own, and Garry's rows of commit c1d5f178 stay byte for byte.

## Garry's rows (commit c1d5f178 and his four families' rows), byte for byte, typos included.
## Pass 143: the Boomstick and Dragon's Breath families' rows say their damage (Garry: "Boomstick text description
## doesn't mention damage dealt", "Dragon's Breath doesn't mention damage number"): his texts with the damage added.
## Pass 147 (Garry: "Add dmg number for the Basketball Weapon description ... add dmg dealt numbers where missing"): the
## Basketball and Big Mouth families' rows likewise.
const GARRY_ROWS := {
	"weapon.basketball.desc": "Throws a ball at {who} within {range} m for {damage} damage, it bounces to {hops} more {hops?enemy:enemies} close by, then flies back.",
	"weapon.big_mouth.desc": "Shoots a {range} m long beam at the crowd for {seconds} s, dealing {damage} damage a second.",
	"weapon.boomstick.desc": "Fires {amount} {amount?pellet:pellets} in a {cone}° cone where you face for {amount?{damage} damage:{damage} damage each}.",
	"weapon.dragons_breath.desc": "Breathes a {deg}° cone of fire {range} m long for {seconds} s every {cooldown} s, dealing {damage} damage every {every}.",
	"evolution.slam_dunk.desc": "Throws a ball at {who} within {range} m for {damage} damage, it bounces to {hops} more {hops?enemy:enemies} close by, then flies back.",
	"evolution.loudmouth.desc": "Shoots a {range} m long beam at the crowd for {seconds} s, dealing {damage} damage a second.",
	"evolution.fire_eater.desc": "Breathes a {deg}° cone of fire {range} m long for {seconds} s every {cooldown} s, dealing {damage} damage every {every}.",
	"evolution.blunderbuss.desc": "Blasts a {deg}° cone {depth} m deep where you face: everything in it is hit at once for {damage} damage.",
	"evolution.doomstick.desc": "Fires {amount} {amount?pellet:pellets} in a {cone}° cone where you face for {amount?{damage} damage:{damage} damage each}.",
	"gen.weapon.ball.bounces": "Throws a ball at {who} within {range} m for {damage} damage, it bounces to {hops} more {hops?enemy:enemies} close by, then flies back.",
	"gen.weapon.breath.still": "Stand still {seconds} s before a breath: it lasts ×{long}, hits ×{hits}",
	"gen.weapon.laser": "Shoots a {range} m long beam at the crowd for {seconds} s, dealing {damage} damage a second.",
	"gen.weapon.launch": "Each hit has a {pct}% chance to throw the enemy into the air.",
}

## Garry's families' mutation texts (his edits of c1d5f178 and the ones he left), byte for byte.
const GARRY_MUTATIONS := {
	"alley_oop": "Each hit has a 15% chance to throw the creature into the air.",
	"free_throw": "Every hit evade throw a ball.",
	"on_fire": "Enemies catch on fire when hit.",
	"rebound": "The ball hits everything on its way back.",
	"mouth_arch": "The beam pans 15° across while it fires, so it cuts through a crowd.",
	"mouth_burn": "Beams lights enemies on fire for 3 s.",
	"mouth_knock": "Beam knocks the first creature hard.",
	"birdshot_lane": "Shoot tiny pellets that cover a 2.6 m wide lane a quarter longer than the curent range takes. Deals 40% less damage than a full point-blank volley.",
	"both_barrels": "Every third shot fires twice",
	"dragons_breath": "Pellets have a 60% chance of setting enemies on fire.",
	"backdraft": "Breath is wider and knocks enemies harder.",
	"blue_flame": "The breath burns blue: 25% further, −20% damage, burns last 75% longer.",
	"held_breath": "Stand still 2 s before a breath: it lasts twice as long, hits ×1.5 and comes from all sides. A hit breaks the stillness.",
}

## Words of the sentences TextGen used to glue on after a weapon's row (the fuse, the knockback, the pierce drop-off,
## the burn and the poison, the held mutations, the owner, "Evolved:").
const GLUED := ["Knocks enemies back", "lies where it lands", "'s own.", "Evolved: cannot", "Pierces", "pierce ",
	"Poisons:", "Sets on fire", "on fire:", "less than the one before", "pull fires", "ricochets", "mini crits",
	"Every caught ball", "Heat", "chance to throw the enemy", "Every extra projectile", "shoves them",
	"Stand still", "is pinned", "trail of dust that slows what", "guaranteed crit", "The ground splits",
	"bomblets that pop", "builds pressure", "slaps them aside", "echo", "pillars a strike", "drop a coin",
	"Hard black crystals", "power-ups ×", "speed-up at full", "carry the first enemy", "work 25% better", "loops once along"]


func before_test() -> void:
	Loc.load_table()
	Loc.clear_warnings()


## The longest run of a row's words between its {variables} (a selector's parts left out).
func _longest_literal(row: String) -> String:
	var best := ""
	var cur := ""
	var depth := 0
	for ch in row:
		if ch == "{":
			depth += 1
			if depth == 1:
				if cur.length() > best.length():
					best = cur
				cur = ""
		elif ch == "}":
			depth = maxi(depth - 1, 0)
		elif depth == 0:
			cur += ch
	if cur.length() > best.length():
		best = cur
	return best.strip_edges()


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m in muts:
		inst.mutations.append(m)
	inst.rebuild(StatSheet.new(), [inst])
	return inst


func test_dynamite_reads_as_garry_wrote_it() -> void:
	# pass 140 (lane TEXTS): his words, then the damage it deals (his rule: every weapon says its damage), the radius in
	# whole metres (docs/texts/text_rules.md)
	# pass 143 (Garry: "Dynamite description doesn't mention damage deal. Should be 'Lobs 1 stick of dynamite at a crowd for
	# N damage'"): his new sentence, the look's thing "stick of dynamite"
	assert_str(Loc.row_text("weapon.lob_grenade.desc")).is_equal("Lobs {amount} {thing} at a crowd for {damage} damage.")
	var def: WeaponDef = Registry.weapon("lob_grenade")
	var one := _inst("lob_grenade")
	var want := "Lobs 1 %s at a crowd for %d damage." % [TextGen.thing_word(def, 1, "grenade", "grenades"), int(round(one.sheet.get_stat("damage", 25.0)))]
	assert_str(one.description()).is_equal(want)
	assert_str(want).starts_with("Lobs 1 stick of dynamite at a crowd for ")
	# with every path mutation (Sticky, Frag, New Equipment) still the one sentence
	var all := _inst("lob_grenade", Registry.mutations_of("lob_grenade"), def.max_level)
	assert_str(all.description()).starts_with("Lobs 2 ")
	assert_str(all.description()).ends_with(" damage.")
	assert_int(all.description().count(". ")).is_equal(0)
	assert_array(Loc.warnings()).is_empty()


func test_no_weapon_card_has_a_sentence_glued_on() -> void:
	for id: String in Registry.weapons.keys():
		var def: WeaponDef = Registry.weapons[id]
		var fam := def.evolved_from if def.is_evolution and def.evolved_from != "" else def.id
		var states := [_inst(id), _inst(id, [], def.max_level), _inst(id, Registry.mutations_of(fam), def.max_level)]
		for inst: WeaponInstance in states:
			var row := inst.description().get_slice("\n", 0)
			for g: String in GLUED:
				assert_bool(row.contains(g)).override_failure_message("%s: '%s' says '%s'" % [id, row, g]).is_false()
			assert_bool(row.contains("{")).override_failure_message("%s: unfilled '%s'" % [id, row]).is_false()
	assert_array(Loc.warnings()).is_empty()


func test_every_evolution_is_its_row_and_the_note() -> void:
	var n := 0
	for id: String in Registry.weapons.keys():
		var def: WeaponDef = Registry.weapons[id]
		if not def.is_evolution:
			continue
		n += 1
		var note := Loc.t_first(["evolution.%s.note" % id, "gen.evolution.mutations_note"])
		assert_str(TextGen.evolution_note(def)).is_equal(note)
		var key := "evolution.%s.desc" % id
		assert_bool(Loc.has(key)).override_failure_message(key).is_true()
		var head := _longest_literal(Loc.row_text(key))
		var states := [_inst(id), _inst(id, Registry.mutations_of(def.evolved_from))]
		for inst: WeaponInstance in states:
			var lines := inst.description().split("\n")
			assert_int(lines.size()).override_failure_message(id).is_equal(2)
			assert_str(lines[1]).is_equal(note)
		# its own row as it comes (the chest's reveal, the Collection): the row's longest run of words
		assert_str(_inst(id).description().get_slice("\n", 0)).override_failure_message(id).contains(head)
	assert_int(n).is_greater(30)
	# the two notes
	assert_str(Loc.t("gen.evolution.mutations_note")).is_equal("All your mutations still apply.")
	assert_str(TextGen.evolution_note(Registry.weapon("golden_revolver"))).is_equal("All your mutations still apply and get stronger.")
	assert_str(TextGen.evolution_note(Registry.weapon("requiem"))).is_equal("All your mutations still apply.")
	# an evolution keeps its own row whatever its path did to the shape (the Halberd with Pike Sweep)
	var hal := _inst("halberd", Registry.mutations_of("pike"))
	assert_str(hal.description()).contains(_longest_literal(Loc.row_text("evolution.halberd.desc")))
	# a Garry row that cannot be filled under a changed shape falls back to the shape's row (the Doomstick's {cone})
	var doom := _inst("doomstick", Registry.mutations_of("boomstick"))
	assert_str(doom.description()).starts_with("Blasts a ")
	assert_array(Loc.warnings()).is_empty()


func test_garry_rows_stay_byte_for_byte() -> void:
	for k: String in GARRY_ROWS:
		assert_str(Loc.row_text(k)).override_failure_message(k).is_equal(str(GARRY_ROWS[k]))
	for m: String in GARRY_MUTATIONS:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message(m).is_not_null()
		assert_str(md.text).override_failure_message(m).is_equal(str(GARRY_MUTATIONS[m]))


func test_pause_one_line_keeps_the_row_line_only() -> void:
	# the pause screen's Build row takes the first sentence of the row's line (never the note under it)
	var inst := _inst("requiem")
	var first := inst.description().get_slice("\n", 0).split(". ")[0]
	assert_bool(first.contains("\n")).is_false()
	assert_str(first).starts_with("Strums a full ring of melody")
