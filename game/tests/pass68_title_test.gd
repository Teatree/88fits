extends GdUnitTestSuite

## Pass 68, lane T (D9; Garry: a new look comes with its own title cut-out and badge): a hero look may name its own title
## cut-out (`variants[CODE].title`, a file name under res://art/ui/wanted/), JsonContent carries it in every look's entry,
## and the cut-out shown is the one of the look the player plays (Registry.played_look: Save.hero_look, else the JSON's
## `variant`, else the base): the look's own file when it is there, else the hero's hero_<id>.png. A look that names none
## never borrows another look's. The round badge follows the same look on the hero sheet, an unlock's plate on the results,
## the developer's Hidden list and the arena's hero tiles. No new art: the looks here borrow other heroes' cut-outs and
## badges, so the one drawn is told apart by its texture. The hero with one look is built here from Astro's JSON with his
## looks taken off (_one_look), so the suite does not pin Garry's content: it holds when he gives Astro looks.

const SHEET := preload("res://ui/wanted/WHeroSheet.gd")
const RESULTS := preload("res://ui/ResultsScreen.gd")
const DIR := "res://art/ui/wanted/"
const SOL := "res://content/characters/solenne/"
const ASTRO := "res://content/characters/astro/"
const DRIFTER_STRIP := "res://content/characters/drifter/drifter_sprite.png"
const DRIFTER_BADGE := "res://content/characters/drifter/drifter_icon.png"
const ASTRO_BADGE := ASTRO + "astro_icon.png"

var _keep: Dictionary = {}
## Solenne's own def while a test has a stub in her place in the Registry (_swap_in); put back after the test.
var _swapped: CharacterDef = null


func before_test() -> void:
	_keep = {"menu_style": Settings.menu_style, "top_inset": Settings.top_inset, "last": Save.data.get("last_character", "")}
	Settings.top_inset = -1
	Save.data = Save._default()


func after_test() -> void:
	if _swapped:
		Registry.characters["solenne"] = _swapped
		_swapped = null
	CollectionScreen.hidden_only = false
	Save.data = Save._default()
	Save._dirty = false
	Save.data["last_character"] = _keep["last"]
	Settings.menu_style = str(_keep["menu_style"])
	Settings.top_inset = int(_keep["top_inset"])
	Run.arena = false
	Run.end()


## Solenne built from her JSON with four looks: SOL-A the base (the top-level strip) naming the Drifter's cut-out, SOL-B
## a strip of its own naming Astro's and wearing the Drifter's badge, SOL-C a strip naming no cut-out and wearing Astro's
## badge, SOL-D a strip naming a file that is not there. `variant` is the look the JSON plays (SOL-B unless told). Her
## own badge (the base's), the Drifter's and Astro's tell the kept look, the JSON's and a third one apart.
func _built(variant := "SOL-B") -> CharacterDef:
	var d: Dictionary = JsonContent.load_json(SOL + "solenne.json")
	d["variant_base"] = "SOL-A"
	d["variant"] = variant
	d["variants"] = {"SOL-A": {"note": "her own", "title": "hero_drifter.png"},
		"SOL-B": {"sprite": DRIFTER_STRIP, "title": "hero_astro.png", "icon": DRIFTER_BADGE},
		"SOL-C": {"sprite": DRIFTER_STRIP, "icon": ASTRO_BADGE},
		"SOL-D": {"sprite": DRIFTER_STRIP, "title": "hero_nobody_d.png"}}
	var c := JsonContent.build("characters", d, SOL) as CharacterDef
	assert_object(c).is_not_null()
	return c


## A hero with one look: Astro built from his JSON with any looks it lists taken off (Garry may give him looks in the
## Level Editor; the rule is about a hero without any, not about Astro's content).
func _one_look() -> CharacterDef:
	var d: Dictionary = JsonContent.load_json(ASTRO + "astro.json")
	d.erase("variants")
	d.erase("variant")
	d.erase("variant_base")
	var one := JsonContent.build("characters", d, ASTRO) as CharacterDef
	assert_object(one).is_not_null()
	return one


func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Puts `c` in the Registry in Solenne's place for this test (after_test puts her back).
func _swap_in(c: CharacterDef) -> void:
	_swapped = Registry.characters["solenne"]
	Registry.characters["solenne"] = c


# ---------------------------------------------------------------- the data

func test_the_json_carries_each_looks_title() -> void:
	var c := _built()
	assert_str(str(c.variants["SOL-A"]["title"])).is_equal("hero_drifter.png")
	assert_str(str(c.variants["SOL-B"]["title"])).is_equal("hero_astro.png")
	assert_str(str(c.variants["SOL-C"]["title"])).is_equal("")
	assert_str(str(c.variants["SOL-D"]["title"])).is_equal("hero_nobody_d.png")
	# a base the JSON does not list is the top-level strip, and names no cut-out of its own
	var d: Dictionary = JsonContent.load_json(SOL + "solenne.json")
	d["variant_base"] = "SOL-A"
	d["variant"] = "SOL-A"
	d["variants"] = {"SOL-B": {"sprite": DRIFTER_STRIP, "title": "hero_astro.png"}}
	var c2 := JsonContent.build("characters", d, SOL) as CharacterDef
	assert_array(c2.variant_codes()).is_equal(["SOL-A", "SOL-B"])
	assert_str(str(c2.variants["SOL-A"]["title"])).is_equal("")
	assert_str(c2.look_title()).is_equal("")
	# a hero with one look carries no looks at all
	var one := _one_look()
	assert_dict(one.variants).is_empty()
	assert_str(one.look_code()).is_equal("")
	assert_str(one.look_title()).is_equal("")


func test_a_look_with_a_title_resolves_that_path() -> void:
	var c := _built()
	assert_str(c.look_code()).is_equal("SOL-B")
	assert_str(c.look_title()).is_equal("hero_astro.png")
	assert_str(c.title_path()).is_equal(DIR + "hero_astro.png")
	assert_str(c.variant_def("SOL-A").title_path()).is_equal(DIR + "hero_drifter.png")
	# a res:// path is taken as it is
	(c.variants["SOL-C"] as Dictionary)["title"] = DIR + "hero_ironwood.png"
	assert_str(c.variant_def("SOL-C").title_path()).is_equal(DIR + "hero_ironwood.png")
	# the title draws that file in the slot (a res:// slot names its file)
	var slot := WPlaceholder.make(c.title_path(), "x", Vector2(528, 732))
	assert_object(slot.tex).is_same(_tex(DIR + "hero_astro.png"))
	slot.free()
	# and a plain slot still reads res://art/ui/wanted/<slot>.png
	var plain := WPlaceholder.make("hero_astro", "x", Vector2(528, 732))
	assert_object(plain.tex).is_same(_tex(DIR + "hero_astro.png"))
	plain.free()


func test_without_a_title_or_with_a_missing_file_it_falls_back() -> void:
	var c := _built()
	# no title: the hero's own cut-out, not the JSON look's
	assert_str(c.variant_def("SOL-C").title_path()).is_equal(DIR + "hero_solenne.png")
	# a title whose file is not there: the hero's own too
	assert_bool(ResourceLoader.exists(DIR + "hero_nobody_d.png")).is_false()
	assert_str(c.variant_def("SOL-D").title_path()).is_equal(DIR + "hero_solenne.png")
	# a hero with one look: his own
	assert_str(_one_look().title_path()).is_equal(DIR + "hero_astro.png")
	# a hero not painted at all: his own path all the same, and the title draws the striped slot
	var bare := CharacterDef.new()
	bare.id = "nobody"
	assert_str(bare.title_path()).is_equal(DIR + "hero_nobody.png")
	var slot := WPlaceholder.make(bare.title_path(), "x", Vector2(528, 732))
	assert_object(slot.tex).is_null()
	slot.free()


func test_the_chosen_look_wins_over_the_json_variant() -> void:
	var c := _built()
	# nothing kept: the JSON's look (SOL-B)
	assert_str(Registry.played_look(c).look_code()).is_equal("SOL-B")
	assert_str(Registry.played_look(c).title_path()).is_equal(DIR + "hero_astro.png")
	# the look kept for her wins
	Save.set_hero_look("solenne", "SOL-A")
	assert_str(Registry.played_look(c).look_code()).is_equal("SOL-A")
	assert_str(Registry.played_look(c).title_path()).is_equal(DIR + "hero_drifter.png")
	# a kept look naming no cut-out shows her own, never the JSON look's
	Save.set_hero_look("solenne", "SOL-C")
	assert_str(Registry.played_look(c).title_path()).is_equal(DIR + "hero_solenne.png")
	# a kept code she no longer has: the JSON's look again
	Save.set_hero_look("solenne", "SOL-Z")
	assert_str(Registry.played_look(c).look_code()).is_equal("SOL-B")
	assert_str(Registry.played_look(c).title_path()).is_equal(DIR + "hero_astro.png")
	# a JSON look that did not load, nothing kept: the base
	Save.set_hero_look("solenne", "")
	var b := _built("SOL-Q")
	assert_str(Registry.played_look(b).look_code()).is_equal("SOL-A")
	assert_str(Registry.played_look(b).title_path()).is_equal(DIR + "hero_drifter.png")
	# the hero's own def is never changed by it
	assert_str(c.look_code()).is_equal("SOL-B")
	assert_object(Registry.played_look(null)).is_null()


# ---------------------------------------------------------------- the screens

func _title() -> Control:
	Settings.menu_style = "painted"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await _frames(2)
	return t


func test_the_painted_title_draws_the_played_looks_cut_out() -> void:
	var c := _built()
	var t := await _title()
	t._heroes = [c]
	t._index = 0
	t._show_hero(0)
	# the JSON's look names Astro's cut-out
	assert_object(t._art.tex).is_same(_tex(DIR + "hero_astro.png"))
	# the kept look's own
	Save.set_hero_look("solenne", "SOL-A")
	t._show_hero(0)
	assert_object(t._art.tex).is_same(_tex(DIR + "hero_drifter.png"))
	# a kept look whose file is missing: her own hero_solenne.png
	Save.set_hero_look("solenne", "SOL-D")
	t._show_hero(0)
	assert_object(t._art.tex).is_same(_tex(DIR + "hero_solenne.png"))
	# a hero with one look: his own hero_<id>.png, as before
	t._heroes = [_one_look()]
	t._show_hero(0)
	assert_object(t._art.tex).is_same(_tex(DIR + "hero_astro.png"))
	t.visible = false
	await _frames(1)


func _portrait(s: Control) -> Texture2D:
	var frame: Node = s.find_child("Portrait", true, false)
	assert_object(frame).is_not_null()
	return (frame.get_child(0) as TextureRect).texture


func test_the_sheet_shows_the_badge_of_the_played_look() -> void:
	var c := _built()
	var host := Control.new()
	host.size = Vector2(1080, 1920)
	add_child(host)
	auto_free(host)
	# the JSON's look (SOL-B) wears the Drifter's badge
	var s: Control = SHEET.open(host, c, false)
	await _frames(2)
	assert_object(_portrait(s)).is_same(_tex(DRIFTER_BADGE))
	# the sheet's hero stays her own def
	assert_object(s.get("hero")).is_same(c)
	s.close()
	await _frames(1)
	s.free()
	# the kept look (SOL-A, the base) wears her own badge
	Save.set_hero_look("solenne", "SOL-A")
	s = SHEET.open(host, c, false)
	await _frames(2)
	assert_object(_portrait(s)).is_same(_tex(SOL + "solenne_icon.png"))
	s.close()
	await _frames(1)
	s.free()


func test_an_unlock_draws_the_played_looks_badge() -> void:
	var c := _built()
	_swap_in(c)
	var q := QuestDef.new()
	q.unlocks = {"type": "character", "id": "solenne"}
	var rs: Control = auto_free(RESULTS.new())
	# nothing kept: the JSON's look, the Drifter's badge (the results' unlock plate, and the run's UNLOCKED banner:
	# Game._check_quests draws Game.unlock_banner_def)
	var got: ContentDef = rs.call("_reward", q)
	assert_str(got.id).is_equal("solenne")
	assert_object(got.icon).is_same(_tex(DRIFTER_BADGE))
	var banner: ContentDef = Game.unlock_banner_def(q)
	assert_str(banner.id).is_equal("solenne")
	assert_object(banner.icon).is_same(_tex(DRIFTER_BADGE))
	# the kept look's own: her badge, not her def's (the JSON look's, the Drifter's)
	Save.set_hero_look("solenne", "SOL-A")
	got = rs.call("_reward", q)
	assert_object(got.icon).is_same(_tex(SOL + "solenne_icon.png"))
	assert_object(Game.unlock_banner_def(q).icon).is_same(_tex(SOL + "solenne_icon.png"))
	assert_object(c.icon).is_same(_tex(DRIFTER_BADGE))
	# anything but a hero is itself (the banner: the weapon with its own icon), and nothing is nothing
	var w := Registry.weapon("revolver")
	assert_object(Registry.art_of(w)).is_same(w)
	assert_object(Registry.art_of(null)).is_null()
	var qw := QuestDef.new()
	qw.unlocks = {"type": "weapon", "id": "revolver"}
	assert_object(Game.unlock_banner_def(qw)).is_same(w)
	assert_object(Game.unlock_banner_def(QuestDef.new())).is_null()


## The plate of the Collection tile whose name line reads `label` (what clear_content let go of is still in the tree
## until the frame ends, so only what the screen shows now is searched).
func _collection_plate(cs: CollectionScreen, label: String) -> WPlate:
	for top: Node in cs.content.get_children():
		if top.is_queued_for_deletion():
			continue
		for n: Node in top.find_children("*", "", true, false):
			if n is WText and (n as WText).text == label:
				for s: Node in n.get_parent().get_children():
					if s is WPlate:
						return s as WPlate
	return null


## The plate on the card at the top of the page the Collection shows now.
func _page_plate(cs: CollectionScreen) -> WPlate:
	for top: Node in cs.content.get_children():
		if top.is_queued_for_deletion():
			continue
		for n: Node in top.find_children("*", "", true, false):
			if n is WPlate:
				return n as WPlate
	return null


func test_the_hidden_list_draws_the_played_looks_badge() -> void:
	# Solenne out of play (a stub in her place), the look kept for her SOL-A: her own badge, where her def wears the
	# JSON look's (SOL-B, the Drifter's)
	var c := _built()
	c.hidden = true
	_swap_in(c)
	Save.set_hero_look("solenne", "SOL-A")
	CollectionScreen.hidden_only = true
	var cs: CollectionScreen = auto_free(load("res://ui/CollectionScreen.tscn").instantiate())
	add_child(cs)
	await _frames(2)
	assert_bool(CollectionScreen.hidden_items().has(c)).is_true()
	# her tile on the developer's Hidden list
	var plate := _collection_plate(cs, c.display_name)
	assert_object(plate).override_failure_message("no Hidden tile for " + c.display_name).is_not_null()
	assert_object(plate.tex).is_same(_tex(SOL + "solenne_icon.png"))
	# a tap on it opens her page: the card's plate wears the same badge
	var tile := plate.get_parent().get_parent() as WTap
	assert_object(tile).is_not_null()
	tile.pressed.emit()
	await _frames(1)
	assert_object(cs._page).is_same(c)
	var card := _page_plate(cs)
	assert_object(card).is_not_null()
	assert_object(card.tex).is_same(_tex(SOL + "solenne_icon.png"))
	# back to the list (the header's count, kept aside while a page is open, goes back in, so nothing is left orphaned)
	cs._show_grid()
	cs.visible = false
	await _frames(1)


func _tile_badge(panel: ArenaPanel, id: String) -> Texture2D:
	var tile: Node = panel._content.find_child("Hero_" + id, true, false)
	assert_object(tile).override_failure_message("no tile for " + id).is_not_null()
	for r in tile.find_children("*", "TextureRect", true, false):
		if (r as TextureRect).texture:
			return (r as TextureRect).texture
	return null


func test_the_arena_hero_tiles_wear_the_looks_badge() -> void:
	var c := _built()
	_swap_in(c)
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = true
	var game: Game = auto_free(Game.new())
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(Registry.character("astro"))
	add_child(p)
	game.player = p
	var panel: ArenaPanel = auto_free(ArenaPanel.new())
	panel.game = game
	add_child(panel)
	panel.set_process(false)
	panel._tab = "hero"
	panel._refresh()
	# not playing, nothing kept: the JSON's look
	assert_object(_tile_badge(panel, "solenne")).is_same(_tex(DRIFTER_BADGE))
	# the kept look's
	Save.set_hero_look("solenne", "SOL-A")
	panel._refresh()
	assert_object(_tile_badge(panel, "solenne")).is_same(_tex(SOL + "solenne_icon.png"))
	# the hero playing: the look he wears now (the arena's chip, for this visit), SOL-C in Astro's badge: neither the
	# kept look's (SOL-A, her own) nor her def's (the JSON's SOL-B, the Drifter's)
	assert_bool(game.arena_swap_hero("solenne")).is_true()
	p.show_look("SOL-C")
	assert_str(p.look_code()).is_equal("SOL-C")
	panel._refresh()
	assert_object(_tile_badge(panel, "solenne")).is_same(_tex(ASTRO_BADGE))
	await _frames(1)
