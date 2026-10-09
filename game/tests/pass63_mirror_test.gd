extends GdUnitTestSuite
## Pass 63 (Garry: "I thought that each Upgrade is a choice ... They shouldn't be able to just switch between what the
## upgrades they chose"): every rank of a talent is bought in one form and keeps it; a talent's ranks are a list of forms.


func before_test() -> void:
	Save.data["talents"] = {}
	Save.data["talent_spent"] = 0


func after_test() -> void:
	Save.data["talents"] = {}
	Save.data["talent_spent"] = 0
	Run.end()


func test_an_old_save_reads_as_its_form_rank_times() -> void:
	Save.data["talents"] = {"grit": {"form": 1, "rank": 3}}
	assert_array(Save.talent_picks("grit")).is_equal([1, 1, 1])
	assert_int(Save.talent_rank("grit")).is_equal(3)
	assert_int(Save.talent_count("grit", 0)).is_equal(0)
	assert_int(Save.talent_count("grit", 1)).is_equal(3)
	assert_int(Save.talent_form("grit")).is_equal(1)


func test_each_rank_keeps_the_form_it_was_bought_in() -> void:
	var grit: TalentDef = Registry.talent("grit")
	Save.add_gold(100000)
	assert_bool(Save.buy_talent(grit, 0)).is_true()
	assert_bool(Save.buy_talent(grit, 1)).is_true()
	assert_bool(Save.buy_talent(grit, 0)).is_true()
	assert_array(Save.talent_picks("grit")).is_equal([0, 1, 0])
	# the price follows the talent's rank, whatever the form
	assert_int(Save.talent_spent()).is_equal(grit.cost_of_rank(0) + grit.cost_of_rank(1) + grit.cost_of_rank(2))
	# nothing switches a bought rank any more
	assert_bool(Save.has_method("set_talent_form")).is_false()


func test_a_full_talent_takes_no_more_ranks() -> void:
	var grit: TalentDef = Registry.talent("grit")
	Save.add_gold(1000000)
	for k in range(grit.max_rank()):
		assert_bool(Save.buy_talent(grit, k % 2)).is_true()
	assert_bool(Save.buy_talent(grit, 0)).is_false()
	assert_int(Save.talent_rank("grit")).is_equal(grit.max_rank())


func test_both_forms_fold_into_the_hero_s_sheet() -> void:
	# two Padding ranks (+10% max HP each) and one Plate rank (+6% damage reduction)
	Save.data["talents"] = {"grit": {"picks": [0, 1, 0]}}
	var c: CharacterDef = Registry.character("drifter")
	var sheet: StatSheet = Run.hero_sheet(c, 1)
	assert_float(sheet.get_stat("max_hp", 0.0)).is_equal_approx(100.0 * 1.1 * 1.1, 0.01)
	assert_float(sheet.get_stat("damage_reduction", 0.0)).is_equal_approx(0.06, 0.0001)


func test_take_it_all_back_empties_every_choice() -> void:
	var grit: TalentDef = Registry.talent("grit")
	Save.add_gold(100000)
	Save.buy_talent(grit, 1)
	Save.buy_talent(grit, 0)
	Save.talent_refund_all()
	assert_array(Save.talent_picks("grit")).is_empty()
