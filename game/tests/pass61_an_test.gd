extends GdUnitTestSuite

## Pass 61, lane AN (Garry: "Analytics PostHog Dashboards (!!!) 1. Coin Gains / Spend (During gameplay and not, have all
## the sources)"): every gold call names where the gold came from or went (Run.add_gold / spend_gold, Save.add_gold /
## spend_gold); the run recorder tallies a run's gold by source and by sink, second by second (gold_in / gold_out on the
## rows), into run_summary (gold_by_source, gold_spent_by, m_gold_in, m_gold_out) and run_end (gold_earned, gold_spent,
## gold_banked, gold_lost, gold_before, gold_after: earned - spent = banked + lost); the saved gold's every move goes out
## as one gold_meta (talent buys and refunds, the Strongbox, the banking at the end); the arena sends none.

const AnalyticsScript := preload("res://core/autoload/Analytics.gd")
const DIR := "user://test_saves/pass61_an"
const KEY := "phc_testtesttesttesttest"

const FAKE_GAME := """extends Node
var enemies = null
var director = null
var player = null
var cards = null
"""

var _save_dir := ""
var _keep_q := ""
var _keep_sender: Callable
var _opened := false


func before() -> void:
	Save.flush()
	_save_dir = Save.dir


func after() -> void:
	Save.dir = _save_dir
	Save.load_save()
	_clear()


func before_test() -> void:
	_clear()
	DirAccess.make_dir_recursive_absolute(DIR)
	Save.dir = DIR
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	Settings.analytics = true
	RunAnalytics.I = null


func after_test() -> void:
	_shut()
	get_tree().paused = false
	Settings.analytics = true
	Run.arena = false
	Run.forced_map_seed = 0
	if Save.sandboxed():
		Save.end_sandbox()
	Run.end()


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## The autoload opened like a phone's for this test: its own sender, its queue file in the test folder.
func _open() -> void:
	_keep_q = Analytics.queue_path
	_keep_sender = Analytics.sender
	Analytics.test_mode = true
	Analytics.queue_path = DIR.path_join("autoload_queue.json")
	Analytics.set_config({"key": KEY, "enabled": true})
	Analytics.sender = func(_u: String, _b: String) -> void: pass
	Analytics.queue = []
	Analytics.new_session()
	_opened = true


## ... and shut again.
func _shut() -> void:
	if not _opened:
		return
	_opened = false
	Analytics.queue = []
	Analytics.run_props = {}
	Analytics._in_flight = 0
	Analytics._since_save = 0
	Analytics._retry_at_ms = 0
	Analytics._backoff = 0.0
	Analytics._requesting = false
	Analytics.test_mode = false
	Analytics.queue_path = _keep_q
	Analytics.sender = _keep_sender
	Analytics.load_config()


func _events(name: String) -> Array:
	var out: Array = []
	for e in Analytics.queue:
		if str(e["event"]) == name:
			out.append(e["properties"])
	return out


## A bare recorder on a fake game (no scene), begun.
func _recorder() -> RunAnalytics:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var ra := RunAnalytics.new()
	ra.mirror = false
	g.add_child(ra)
	ra.begin(g)
	return ra


## An {id: amount} map holds exactly these (whatever its order).
func _same(actual: Dictionary, expected: Dictionary) -> void:
	assert_int(actual.size()).override_failure_message("%s != %s" % [str(actual), str(expected)]).is_equal(expected.size())
	for k in expected:
		assert_bool(actual.has(k)).override_failure_message("%s lacks %s" % [str(actual), k]).is_true()
		assert_int(int(actual.get(k, -1))).override_failure_message("%s: %s" % [k, str(actual)]).is_equal(int(expected[k]))


func _drop_record(ra: RunAnalytics) -> void:
	DirAccess.remove_absolute("user://analytics/runs/%s.json" % str(ra.header.get("stamp", "")))


# ---------------------------------------------------------------- 1. every call names its source

## The gdscript files of the game (tests and addons left out).
func _scripts(dir: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or (dir == "res://" and (d == "addons" or d == "tests")):
			continue
		_scripts(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		# a lane's scratch capture (tools/_p61_*.gd) is not the game
		if f.ends_with(".gd") and not f.begins_with("_p"):
			out.append(dir.path_join(f))


## The arguments of the call whose "(" is at `open` in `line`, split at its top-level commas (strings, brackets kept).
static func _args(line: String, open: int) -> Array:
	var out: Array = []
	var depth := 0
	var cur := ""
	var quote := ""
	var i := open + 1
	while i < line.length():
		var ch := line[i]
		if quote != "":
			cur += ch
			if ch == quote:
				quote = ""
		elif ch == "\"" or ch == "'":
			quote = ch
			cur += ch
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
			cur += ch
		elif ch == ")" or ch == "]" or ch == "}":
			if depth == 0:
				out.append(cur.strip_edges())
				return out
			depth -= 1
			cur += ch
		elif ch == "," and depth == 0:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
		i += 1
	out.append(cur.strip_edges())
	return out


func test_every_gold_call_names_its_source() -> void:
	var files: Array = []
	_scripts("res://", files)
	assert_int(files.size()).is_greater(100)
	var calls := 0
	var bad: Array = []
	var meta_ids: Array = RunAnalytics.META_REASONS
	for path: String in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for n in range(lines.size()):
			var line: String = lines[n]
			if line.strip_edges().begins_with("#"):
				continue
			for fn in ["add_gold(", "spend_gold(", "mark_coin("]:
				var at := line.find(fn)
				while at >= 0:
					var before := line.substr(maxi(at - 5, 0), mini(at, 5))
					var prev := line[at - 1] if at > 0 else " "
					var is_def := before == "func "
					var is_name := prev == "_" or (prev >= "a" and prev <= "z") or (prev >= "A" and prev <= "Z") or (prev >= "0" and prev <= "9")
					if not is_def and not is_name:
						var args := _args(line, at + fn.length() - 1)
						var where := "%s:%d" % [path, n + 1]
						calls += 1
						if args.size() < 2 or str(args[1]) == "":
							bad.append(where + " names no source: " + line.strip_edges())
						else:
							var a1 := str(args[1])
							if a1.begins_with("\""):
								var id := a1.trim_prefix("\"").trim_suffix("\"")
								var lead := line.substr(0, at)
								var meta := path.ends_with("/Save.gd") or lead.ends_with("Save.") or lead.ends_with("sv.")
								var ok_ids: Array = meta_ids if meta else (RunAnalytics.GOLD_SINKS if fn == "spend_gold(" else RunAnalytics.GOLD_SOURCES)
								if id == "other" or not ok_ids.has(id):
									bad.append(where + " names '%s', not one of the listed ids" % id)
					at = line.find(fn, at + fn.length())
	# every call site of today (run, save, the coins' origins) and not one on the default
	assert_int(calls).is_greater_equal(25)
	assert_array(bad).override_failure_message("\n".join(PackedStringArray(bad))).is_empty()
	# the coins' own origins are sources the board knows
	for src in ["coins", "loose_change", "gold_dust", "boss_coins", "loot_cache", "blasting_cap", "coin_bag"]:
		assert_bool(RunAnalytics.GOLD_SOURCES.has(src)).override_failure_message(src).is_true()
	# the revive is a spend now (it took the gold straight out of the purse), and the end of a run banks as run_bank
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game_src).contains("Run.spend_gold(mini(ReviveScreen.GOLD_COST, Run.run_gold), \"revive\")")
	assert_str(game_src).contains("Save.add_gold(gold, \"run_bank\")")
	assert_str(game_src).contains("Save.add_gold(carried, \"strongbox\")")
	assert_bool(game_src.contains("Run.run_gold = maxi(Run.run_gold - ReviveScreen.GOLD_COST")).is_false()


# ---------------------------------------------------------------- 2. a run's gold, by source and by sink

func test_the_recorder_tallies_each_second_and_the_rest_goes_into_the_last_row() -> void:
	var ra := _recorder()
	Run.add_gold(12, "coins")
	Run.add_gold(90, "elite_purse")
	Run.add_gold(8, "coins")
	ra.tick(1.0)
	var r1: Dictionary = ra.samples[-1]
	_same(r1["gold_in"], {"coins": 20, "elite_purse": 90})
	assert_bool(r1.has("gold_out")).is_false()
	# a second with nothing: no gold keys on the row
	ra.tick(1.0)
	assert_bool((ra.samples[-1] as Dictionary).has("gold_in")).is_false()
	# a spend, and gold that came while paused (no row yet): finish folds it into the last row
	assert_bool(Run.spend_gold(50, "shop")).is_true()
	Run.add_gold(50, "chest")
	assert_bool(Run.spend_gold(500, "shop")).is_false()
	ra.header["stamp"] = "test-p61-%d" % Time.get_ticks_usec()
	Run.extracted = true
	ra.finish()
	_drop_record(ra)
	var last: Dictionary = ra.samples[-1]
	_same(last["gold_in"], {"chest": 50})
	_same(last["gold_out"], {"shop": 50})
	_same(ra.gold_in_total, {"coins": 20, "elite_purse": 90, "chest": 50})
	_same(ra.gold_out_total, {"shop": 50})
	assert_int(ra.gold_earned()).is_equal(160)
	assert_int(ra.gold_spent()).is_equal(50)
	var s := ra._summary_props()
	_same(s["gold_by_source"], {"elite_purse": 90, "chest": 50, "coins": 20})
	_same(s["gold_spent_by"], {"shop": 50})
	assert_array(s["m_gold_in"]).is_equal([160])
	assert_array(s["m_gold_out"]).is_equal([50])
	assert_int(int(s["gold_greed"])).is_equal(0)


func test_greed_is_counted_inside_its_source_and_on_its_own() -> void:
	var ra := _recorder()
	Run.add_timed_effects("p61_greed", "Greed", [Effect.make("greed", "mul", 0.5, "player")], 30.0, true)
	assert_float(Run.player_sheet.get_stat("greed", 1.0)).is_equal_approx(1.5, 0.0001)
	Run.add_gold(10, "bounty")
	assert_int(Run.run_gold).is_equal(15)
	_same(ra.gold_in_total, {"bounty": 15})
	assert_int(ra.gold_greed).is_equal(5)
	# a spend is never scaled
	Run.spend_gold(15, "revive")
	_same(ra.gold_out_total, {"revive": 15})
	ra.header["stamp"] = "test-p61-%d" % Time.get_ticks_usec()
	ra.finish()
	_drop_record(ra)


func test_the_summary_puts_each_minutes_gold_in_its_bucket() -> void:
	var rows: Array = []
	for t in range(1, 151):
		var r := {"t": float(t), "level": 1, "gold": t}
		if t == 10:
			r["gold_in"] = {"coins": 5, "elite_purse": 90}
		if t == 70:
			r["gold_in"] = {"coins": 7}
			r["gold_out"] = {"shop": 240}
		if t == 130:
			r["gold_out"] = {"revive": 150}
		rows.append(r)
	var s := RunAnalytics.summary(rows)
	assert_array(s["m_gold_in"]).is_equal([95, 7, 0])
	assert_array(s["m_gold_out"]).is_equal([0, 240, 150])
	_same(s["gold_by_source"], {"elite_purse": 90, "coins": 12})
	_same(s["gold_spent_by"], {"shop": 240, "revive": 150})
	# a run with no gold at all: zeros a minute and empty maps (every m_ key stays an array)
	var quiet := RunAnalytics.summary([{"t": 1.0}, {"t": 61.0}])
	assert_array(quiet["m_gold_in"]).is_equal([0, 0])
	assert_dict(quiet["gold_by_source"]).is_empty()
	# folded buckets keep the sums
	var folded := RunAnalytics.fit_summary(rows, 400)
	assert_int(int(folded["minutes"])).is_less(3)
	var total_in := 0
	for v in folded["m_gold_in"]:
		total_in += int(v)
	assert_int(total_in).is_equal(102)


func test_a_death_leaves_the_purse_in_the_sand() -> void:
	var ra := _recorder()
	Run.add_gold(300, "boss_purse")
	Run.spend_gold(100, "shop")
	Run.died = true
	ra.header["stamp"] = "test-p61-%d" % Time.get_ticks_usec()
	Run.last_result = {"banked": 0, "lost": Run.run_gold}
	ra.finish()
	_drop_record(ra)
	var g := ra.gold_end(0)
	assert_int(int(g["gold_earned"])).is_equal(300)
	assert_int(int(g["gold_spent"])).is_equal(100)
	assert_int(int(g["gold_purse"])).is_equal(200)
	assert_int(int(g["gold_lost"])).is_equal(200)
	assert_int(int(g["gold_banked"])).is_equal(0)
	assert_int(int(g["gold_earned"]) - int(g["gold_spent"])).is_equal(int(g["gold_banked"]) + int(g["gold_lost"]))
	# a run the app left without an end (a quit): the purse never came home either
	var rb := _recorder()
	Run.died = false
	Run.run_gold = 0
	Run.add_gold(40, "coins")
	rb.header["result"] = "quit"
	rb.header["gold"] = Run.run_gold
	assert_int(int(rb.gold_end(0)["gold_lost"])).is_equal(40)


## A real run (the Game scene, the recorder on, the client opened like a phone's): coins of three origins, an Elite's
## purse, a chest's gold, debug gold, a shop buy, a revive bought on Down!, a Strongbox, the extraction. The recorder's
## tallies, the run_summary and the run_end the client queues all agree, and the save's two moves are gold_meta events.
func test_a_real_run_counts_every_coin_in_and_out() -> void:
	_open()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	g.player.god = false
	# no crowd (no kill can drop a coin of its own while the test counts them)
	g.director.stop()
	g.enemies.kill_all(false)
	var ra: RunAnalytics = RunAnalytics.I
	assert_object(ra).is_not_null()
	ra.mirror = false
	assert_int(int(ra.header["gold_before"])).is_equal(0)
	assert_int(_events("run_start").size()).is_equal(1)
	var pm: PickupManager = g.pickups
	var at: Vector3 = g.player.global_position + Vector3(6, 0, 0)
	# coins: a creature's, a Gold Dust one, a Loose Change one (the stage multiplies them: x1 on stage 1)
	pm._collect(pm.spawn(PickupManager.KIND_COIN, at, 3.0))
	pm._collect(pm.mark_coin(pm.spawn(PickupManager.KIND_COIN, at, 2.0), "gold_dust"))
	var tossed := pm.toss_coin(at, 10.0)
	assert_str(str(pm.coin_from.get(tossed, ""))).is_equal("loose_change")
	pm._collect(tossed)
	assert_bool(pm.coin_from.has(tossed)).is_false()
	# an Elite's purse (90 on stage 1), a chest's gold, the developer's
	g._kill_effects(Registry.enemy("dune_scorpion"), at, null, "")
	Run.chest_take({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	Run.add_gold(1000, "debug")
	_same(ra.gold_in_total, {"coins": 3, "gold_dust": 2, "loose_change": 10, "elite_purse": 90, "chest": 50, "debug": 1000})
	# the shop: a card bought at its price
	var host := Control.new()
	host.size = Vector2(1080, 1920)
	add_child(host)
	var shop := StructureShop.new()
	host.add_child(shop)
	var offer := CardPool.level_up_offer(3)
	assert_bool(offer.is_empty()).is_false()
	shop.open(offer)
	# a card that changes nothing below (pass 63: a Phoenix Feather bought here revived the hero on its own, so Down!
	# never opened and the test failed now and then)
	var pick := 0
	for k in offer.size():
		var d = offer[k].get("def")
		if d == null or str(d.id) != "phoenix_feather":
			pick = k
			break
	var price := StructureShop.price_of(offer[pick])
	var before_shop := Run.run_gold
	(shop._cards[pick] as WCard).pressed.emit()
	assert_int(Run.run_gold).is_equal(before_shop - price)
	_same(ra.gold_out_total, {"shop": price})
	await get_tree().create_timer(0.3).timeout
	host.queue_free()
	# Down!: up again for 150 gold
	g.player._die()
	await get_tree().create_timer(1.4).timeout
	assert_array(g.visible_modals()).is_equal(["revive"])
	var before_revive := Run.run_gold
	g.revive_screen._decide("gold")
	await get_tree().process_frame
	assert_int(Run.run_gold).is_equal(before_revive - 150)
	_same(ra.gold_out_total, {"shop": price, "revive": 150})
	# a Strongbox banks part of it, then a bounty, then the extraction banks the rest
	var boxed := g.bank_purse()
	assert_int(boxed).is_equal(before_revive - 150)
	var metas := _events("gold_meta")
	assert_int(metas.size()).is_equal(1)
	assert_str(str(metas[0]["reason"])).is_equal("strongbox")
	assert_int(int(metas[0]["delta"])).is_equal(boxed)
	assert_int(int(metas[0]["balance_after"])).is_equal(boxed)
	assert_bool(bool(metas[0]["in_run"])).is_true()
	assert_str(str(metas[0]["run_id"])).is_equal(str(ra.header["run_id"]))
	Run.add_gold(40, "bounty")
	await get_tree().create_timer(1.1).timeout
	# the end as Game.end_run does it for an extraction (its scene change has no place in a test)
	Run.extracted = true
	var purse := Run.run_gold
	Run.last_result = {"gold_before": Save.gold(), "banked": purse, "lost": 0, "strongbox": Run.banked_gold}
	Save.add_gold(purse, "run_bank")
	ra.header["stamp"] = "test-p61-%d" % Time.get_ticks_usec()
	ra.finish()
	_drop_record(ra)
	var earned := 3 + 2 + 10 + 90 + 50 + 1000 + 40
	var spent := price + 150
	assert_int(purse).is_equal(earned - spent - boxed)
	# run_end
	var ends := _events("run_end")
	assert_int(ends.size()).is_equal(1)
	var e: Dictionary = ends[0]
	assert_str(str(e["result"])).is_equal("extract")
	assert_int(int(e["gold_earned"])).is_equal(earned)
	assert_int(int(e["gold_spent"])).is_equal(spent)
	assert_int(int(e["gold_debug"])).is_equal(1000)
	assert_int(int(e["gold_strongbox"])).is_equal(boxed)
	assert_int(int(e["gold_purse"])).is_equal(purse)
	assert_int(int(e["gold_banked"])).is_equal(boxed + purse)
	assert_int(int(e["gold_lost"])).is_equal(0)
	assert_int(int(e["gold_earned"]) - int(e["gold_spent"])).is_equal(int(e["gold_banked"]) + int(e["gold_lost"]))
	assert_int(int(e["gold_before"])).is_equal(0)
	assert_int(int(e["gold_after"])).is_equal(Save.gold())
	assert_int(int(e["gold_after"]) - int(e["gold_before"])).is_equal(int(e["gold_banked"]))
	# run_summary: by source, by sink, a minute's in and out
	var sums := _events("run_summary")
	assert_int(sums.size()).is_equal(1)
	var s: Dictionary = sums[0]
	_same(s["gold_by_source"], {"debug": 1000, "elite_purse": 90, "chest": 50, "bounty": 40, "loose_change": 10, "coins": 3, "gold_dust": 2})
	_same(s["gold_spent_by"], {"shop": price, "revive": 150})
	var m_in := 0
	for v in s["m_gold_in"]:
		m_in += int(v)
	var m_out := 0
	for v in s["m_gold_out"]:
		m_out += int(v)
	assert_int(m_in).is_equal(earned)
	assert_int(m_out).is_equal(spent)
	assert_int((s["m_gold_in"] as Array).size()).is_equal(int(s["minutes"]))
	# and the save's second move: the purse home
	metas = _events("gold_meta")
	assert_int(metas.size()).is_equal(2)
	assert_str(str(metas[1]["reason"])).is_equal("run_bank")
	assert_int(int(metas[1]["delta"])).is_equal(purse)
	assert_int(int(metas[1]["balance_after"])).is_equal(boxed + purse)
	g.set_paused(false)
	g.modal_reset()


# ---------------------------------------------------------------- 3. the saved gold

func test_a_talent_buy_and_a_refund_each_send_one_gold_meta() -> void:
	_open()
	assert_bool(Save.gold_moved.is_connected(Analytics.meta_gold)).is_true()
	Save.add_gold(5000, "debug")
	assert_int(_events("gold_meta").size()).is_equal(1)
	Analytics.queue = []
	var t: TalentDef = Registry.talent("grit")
	var cost := t.cost_of_rank(0)
	assert_bool(Save.buy_talent(t)).is_true()
	var metas := _events("gold_meta")
	assert_int(metas.size()).is_equal(1)
	var m: Dictionary = metas[0]
	assert_int(int(m["delta"])).is_equal(-cost)
	assert_str(str(m["reason"])).is_equal("talent")
	assert_int(int(m["balance_after"])).is_equal(5000 - cost)
	assert_str(str(m["talent"])).is_equal("grit")
	assert_int(int(m["rank"])).is_equal(1)
	assert_int(int(m["form"])).is_equal(Save.talent_form("grit"))
	assert_bool(bool(m["in_run"])).is_false()
	# a second rank: one more, rank 2
	var cost2 := t.cost_of_rank(1)
	assert_bool(Save.buy_talent(t)).is_true()
	metas = _events("gold_meta")
	assert_int(metas.size()).is_equal(2)
	assert_int(int(metas[1]["rank"])).is_equal(2)
	assert_int(int(metas[1]["delta"])).is_equal(-cost2)
	# a buy that fails moves nothing and says nothing
	Analytics.queue = []
	var keep := Save.gold()
	Save.data["gold"] = 0
	assert_bool(Save.buy_talent(t)).is_false()
	assert_int(_events("gold_meta").size()).is_equal(0)
	Save.data["gold"] = keep
	# Take it all back: half of what the ranks cost, one event
	var back := Save.talent_refund_all()
	assert_int(back).is_equal(int(floor((cost + cost2) * Save.REFUND_FRAC)))
	metas = _events("gold_meta")
	assert_int(metas.size()).is_equal(1)
	assert_str(str(metas[0]["reason"])).is_equal("talent_refund")
	assert_int(int(metas[0]["delta"])).is_equal(back)
	assert_int(int(metas[0]["balance_after"])).is_equal(keep + back)
	assert_int(int(metas[0]["ranks"])).is_equal(2)
	assert_int(int(metas[0]["spent"])).is_equal(cost + cost2)
	# a refund of nothing sends nothing
	Analytics.queue = []
	Save.talent_refund_all()
	assert_int(_events("gold_meta").size()).is_equal(0)


func test_nothing_is_sent_from_the_arena_or_its_sandbox() -> void:
	_open()
	Save.add_gold(1000, "debug")
	Analytics.queue = []
	# the arena's sandbox: talent ranks bought there send nothing (and are put back)
	Save.begin_sandbox()
	assert_bool(Save.buy_talent(Registry.talent("grit"))).is_true()
	Save.add_gold(50, "strongbox")
	Save.end_sandbox()
	assert_int(Analytics.queue.size()).is_equal(0)
	assert_int(Save.gold()).is_equal(1000)
	# an arena run: no recorder, no event, whatever the purse does
	Run.arena = true
	Save.add_gold(10, "run_bank")
	Run.add_gold(100, "debug")
	assert_object(RunAnalytics.I).is_null()
	assert_int(Analytics.queue.size()).is_equal(0)
	Run.arena = false
	# and the autoload of a test or a tool, shut, sends nothing either
	_shut()
	Save.add_gold(10, "run_bank")
	assert_int(Analytics.queue.size()).is_equal(0)


func test_a_wipe_sends_the_balance_to_zero() -> void:
	_open()
	Save.add_gold(321, "debug")
	Analytics.queue = []
	Save.wipe()
	var metas := _events("gold_meta")
	assert_int(metas.size()).is_equal(1)
	assert_str(str(metas[0]["reason"])).is_equal("wipe")
	assert_int(int(metas[0]["delta"])).is_equal(-321)
	assert_int(int(metas[0]["balance_after"])).is_equal(0)
