extends GdUnitTestSuite

## Pass 140, lane TEXTS (Garry, 2026-11-10: "there is still some inconsistency in how the texts are written ... Try making
## some kind of a set of rules for yourself", docs/texts/text_rules.md): his seven texts as he wrote them, the Gravity
## Gun's blast a whole 2 m in the JSON, every weapon's description says the damage it deals, his own rows untouched, the
## evolution's mutations note in its own face (Rubik Italic, smaller, faded: R.NOTE_*), and the rules the mutation texts
## keep (digits, enemies, no his/her).

const PASS138 := preload("res://tests/pass138_texts_test.gd")

## Garry's four families: their rows and texts are his (pass 138), so the damage rule is a suggestion for him there.
const GARRY_FAMILIES := ["basketball", "big_mouth", "boomstick", "dragons_breath"]

## Number words the rules write as digits ("why write 'two' when you can just write 2").
const NUMBER_WORDS := ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "twice", "double",
	"triple", "half", "third", "fourth", "fifth", "quarter"]


func before_test() -> void:
	Loc.load_table()
	Loc.clear_warnings()


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m in muts:
		inst.mutations.append(m)
	inst.rebuild(StatSheet.new(), [inst])
	return inst


func _family(def: WeaponDef) -> String:
	return def.evolved_from if def.is_evolution and def.evolved_from != "" else def.id


func test_garrys_seven_texts() -> void:
	# 1. the Gravity Gun: his words, then the damage its blast deals (his rule 6: every weapon says its damage)
	var gg := _inst("gravity_gun")
	assert_str(gg.description()).is_equal("Picks up 1 enemy and throws them into a crowd for a 2 m blast that deals 18 damage.")
	assert_str(gg.description()).starts_with("Picks up 1 enemy and throws them into a crowd for a 2 m blast")
	# 2. Juggler, 3. Repulsor, 7. Hip Shot: the mutations' own texts
	assert_str(Registry.mutation("juggler").text).is_equal("Pick up 2 more, but deal −30% damage.")
	assert_str(Registry.mutation("repulsor").text).is_equal("Thrown enemies deal a 40% wider blast and knock back enemies harder.")
	assert_str(Registry.mutation("hip_shot").text).is_equal("Every 5th pull fires 3 shots in a row.")
	# 4. the Singularity: a black hole that deals its damage a second (Vortex: damage x dps_frac)
	var sg := _inst("singularity")
	assert_str(sg.description().get_slice("\n", 0)).is_equal("Creates a Black Hole that drags enemies in and deals 22 damage a second.")
	# 6. the Revolver ("withing" written "within")
	assert_str(_inst("revolver").description()).is_equal("Fires 1 shot at an enemy within 14 m for 20 damage.")
	assert_array(Loc.warnings()).is_empty()


func test_juggler_and_repulsor_numbers_match_their_params() -> void:
	var j: MutationDef = Registry.mutation("juggler")
	var amount := 0.0
	var dmg := 0.0
	for e: Effect in j.effects:
		if e.stat == "amount":
			amount = e.value
		elif e.stat == "damage":
			dmg = e.value
	assert_float(amount).is_equal(2.0)
	assert_float(dmg).is_equal_approx(-0.3, 0.0001)
	var r: MutationDef = Registry.mutation("repulsor")
	assert_float(float((r.params["gravity"] as Dictionary)["throw_mult"])).is_equal_approx(1.4, 0.0001)
	var hs: Dictionary = Registry.mutation("hip_shot").params["hip_shot"]
	assert_int(int(hs["every"])).is_equal(5)
	assert_int(int(hs["volleys"])).is_equal(3)


func test_gravity_gun_blast_is_a_whole_two_metres() -> void:
	var def: WeaponDef = Registry.weapon("gravity_gun")
	assert_float(float((def.params["gravity"] as Dictionary)["blast"])).is_equal(2.0)
	var one := _inst("gravity_gun")
	assert_float(float(TextGen.area_radius(def, one.sheet, one.params)[1])).is_equal_approx(2.0, 0.0001)
	# Repulsor's 40% wider blast reads whole too (2.8 m -> "3 m")
	var rep := _inst("gravity_gun", [Registry.mutation("repulsor")])
	assert_str(rep.description()).contains(" 3 m blast")
	assert_float(float((Registry.weapon("singularity").params["gravity"] as Dictionary)["blast"])).is_equal(2.0)


func test_every_weapon_says_its_damage() -> void:
	var n := 0
	for id: String in Registry.weapons.keys():
		var def: WeaponDef = Registry.weapons[id]
		if GARRY_FAMILIES.has(_family(def)):
			continue
		var inst := _inst(id)
		var row := inst.description().get_slice("\n", 0)
		assert_bool(row.contains(" damage")).override_failure_message("%s: '%s'" % [id, row]).is_true()
		assert_bool(row.contains("{")).override_failure_message("%s: unfilled '%s'" % [id, row]).is_false()
		if not def.is_evolution:
			n += 1
			var want := TextGen._dmg(inst.sheet.get_stat("damage", 0.0))
			assert_bool(row.contains(want + " damage")).override_failure_message("%s: '%s' lacks %s" % [id, row, want]).is_true()
		# whole metres in an item's own description (Garry: "1.9m doesn't read very well")
		var re := RegEx.create_from_string(r"\d\.\d+ m\b")
		assert_object(re.search(row)).override_failure_message("%s: '%s'" % [id, row]).is_null()
	assert_int(n).is_greater(20)
	# with every path mutation the damage is still said, the rows still fill
	for id: String in Registry.weapons.keys():
		var def: WeaponDef = Registry.weapons[id]
		if def.is_evolution or GARRY_FAMILIES.has(id):
			continue
		var all := _inst(id, Registry.mutations_of(id), def.max_level)
		var row2 := all.description().get_slice("\n", 0)
		assert_bool(row2.contains(" damage")).override_failure_message("%s all: '%s'" % [id, row2]).is_true()
	assert_array(Loc.warnings()).is_empty()


func test_garry_rows_and_texts_unchanged() -> void:
	for k: String in PASS138.GARRY_ROWS:
		assert_str(Loc.row_text(k)).override_failure_message(k).is_equal(str(PASS138.GARRY_ROWS[k]))
	for m: String in PASS138.GARRY_MUTATIONS:
		assert_str((Registry.mutation(m) as MutationDef).text).override_failure_message(m).is_equal(str(PASS138.GARRY_MUTATIONS[m]))


func test_mutation_texts_keep_the_rules() -> void:
	var words := RegEx.create_from_string(r"(?i)\b(" + "|".join(NUMBER_WORDS) + r")\b")
	var n := 0
	for id: String in Registry.mutations.keys():
		var md: MutationDef = Registry.mutations[id]
		if GARRY_FAMILIES.has(md.weapon) or md.text == "":
			continue
		n += 1
		var t := md.text
		assert_object(words.search(t)).override_failure_message("%s: '%s'" % [id, t]).is_null()
		assert_bool(t.contains("creature")).override_failure_message("%s: '%s'" % [id, t]).is_false()
		var hh := RegEx.create_from_string(r"\b(his|her)\b")
		assert_object(hh.search(t)).override_failure_message("%s: '%s'" % [id, t]).is_null()
		assert_bool(t.ends_with(".")).override_failure_message("%s: '%s'" % [id, t]).is_true()
	assert_int(n).is_greater(80)


func test_the_note_has_its_own_face() -> void:
	assert_bool(TextGen.is_note(Loc.t("gen.evolution.mutations_note"))).is_true()
	assert_bool(TextGen.is_note(Loc.t("gen.evolution.mutations_note_stronger"))).is_true()
	assert_bool(TextGen.is_note(Loc.row_text("evolution.golden_revolver.note"))).is_true()
	assert_bool(TextGen.is_note("Fires 1 shot.")).is_false()
	var desc := _inst("requiem").description()
	var with_note := W.desc_text(desc, R.DESC_PX)
	var plain := W.desc_text(desc.get_slice("\n", 0), R.DESC_PX)
	assert_int(with_note.note_size).is_equal(int(roundf(R.DESC_PX * R.NOTE_FRAC)))
	assert_int(with_note.note_size).is_less(R.DESC_PX)
	assert_object(with_note.note_font).is_not_null()
	# the face is Rubik Italic (R.body's italic file)
	var base: Font = with_note.note_font
	while base is FontVariation and (base as FontVariation).base_font:
		base = (base as FontVariation).base_font
	assert_str(base.resource_path).contains("Italic")
	assert_float(with_note.note_color.a).is_less(1.0)
	with_note.size = Vector2(600, 0)
	plain.size = Vector2(600, 0)
	with_note._shape()
	assert_object(with_note._note_para).is_not_null()
	# the note is drawn under the body, not as a body line: the text keeps the whole
	assert_str(with_note.text).is_equal(desc)
	assert_float(with_note.get_minimum_size().y).is_greater(plain.get_minimum_size().y)
	# a two-line text whose last line is no note stays one paragraph
	var other := W.desc_text("One.\nTwo.", R.DESC_PX)
	other._shape()
	assert_object(other._note_para).is_null()
	with_note.free()
	plain.free()
	other.free()
	# a note on its own
	var nt := W.note_text("All your mutations still apply.")
	assert_int(nt.font_size).is_equal(int(roundf(R.DESC_PX * R.NOTE_FRAC)))
	nt.free()
