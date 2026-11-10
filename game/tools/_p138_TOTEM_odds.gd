## Pass 138, lane TOTEM: the Totem Pole's rarity odds measured on the pole's own JSON (TotemBoons.offer, headless):
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p138_TOTEM_odds.gd
##       -- [n=10000] [claims=12] [same=<factor>] [out=<abs json>]
## For every count of gifts taken before the offer (0 .. claims-1), `n` offers: each rarity's share of the gifts, the
## offers with all three of one rarity and with exactly two, the offers holding a Common / an Epic / a Legendary, and the
## mean gift's size against its Rare amount (the old range's middle). `same=` overrides the same-tier factor (1 = rolls
## independent of each other, for comparison). Seeded: the same numbers every run.
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var n := 10000
	var claims := 12
	var same := -1.0
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			n = int(a.substr(2))
		elif a.begins_with("claims="):
			claims = int(a.substr(7))
		elif a.begins_with("same="):
			same = float(a.substr(5))
		elif a.begins_with("out="):
			out = a.substr(4)
	var boons = load("res://core/systems/TotemBoons.gd")
	var def = root.get_node("Registry").structure("totem_pole")
	if same >= 0.0:
		def = def.duplicate(true)
		var p: Dictionary = def.params.duplicate(true)
		var r: Dictionary = (p.get("rarity", {}) as Dictionary).duplicate(true)
		r["same_tier"] = same
		p["rarity"] = r
		def.params = p
	var rare := {}
	for e: Dictionary in boons.pool_of(def):
		rare[str(e["id"])] = absf(float(boons.tier_amounts(e)[2]))
	var rows: Array = []
	print("claim | Common Uncommon Rare Epic Legendary (% of gifts) | all3 two (% of offers) | hasC hasE hasL | mean/Rare")
	for c in range(claims):
		var rng := RandomNumberGenerator.new()
		rng.seed = 138000 + c
		var cnt := [0, 0, 0, 0, 0]
		var s3 := 0
		var s2 := 0
		var hc := 0
		var he := 0
		var hl := 0
		var rel := 0.0
		var gifts := 0
		for k in range(n):
			var offer: Array = boons.offer(def, rng, 0, c)
			var tiers: Array = []
			for b: Dictionary in offer:
				var t := int(b["tier"])
				tiers.append(t)
				cnt[t - 1] += 1
				rel += absf(float(b["value"])) / maxf(float(rare[str(b["id"])]), 0.000001)
				gifts += 1
			var distinct := {}
			for t in tiers:
				distinct[t] = true
			if distinct.size() == 1:
				s3 += 1
			elif distinct.size() == 2:
				s2 += 1
			if tiers.has(1):
				hc += 1
			if tiers.has(4):
				he += 1
			if tiers.has(5):
				hl += 1
		var row := {"claim": c, "mix": cnt.map(func(x) -> float: return snappedf(100.0 * x / float(gifts), 0.1)),
			"all_same": snappedf(100.0 * s3 / float(n), 0.1), "two_same": snappedf(100.0 * s2 / float(n), 0.1),
			"has_common": snappedf(100.0 * hc / float(n), 0.1), "has_epic": snappedf(100.0 * he / float(n), 0.1),
			"has_legendary": snappedf(100.0 * hl / float(n), 0.1), "mean_vs_rare": snappedf(rel / float(gifts), 0.01)}
		rows.append(row)
		print("%2d | %s | %5.1f %5.1f | %5.1f %5.1f %5.1f | %.2f" % [c, " ".join(row["mix"].map(func(x) -> String: return "%5.1f" % x)),
			row["all_same"], row["two_same"], row["has_common"], row["has_epic"], row["has_legendary"], row["mean_vs_rare"]])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"n": n, "same": same, "rows": rows}, "  "))
		f.close()
	print("p138_odds: done")
	quit(0)
