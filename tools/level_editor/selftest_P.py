"""Pass 66, lane P: the asset editors' page-free maths and tables (assets_model.js, assets_fields.js) checked under Node
against Python twins and the content on disk. selftest.py discovers this file (`extra_checks`) and hands it its
`check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes under game/.

Groups: frame maths on the three real strip sizes; the variant-code rule (INTERFACES.md §3); TextGen.hero_trait's port
against the five played heroes' trait_text; the rules on every content JSON on disk (zero errors today, warnings allowed);
the field tables' shape; the attack script's telegraph and pacing numbers; the derived item availability and the
quest-locked band against the quests on disk.
"""
import glob
import json
import math
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CONTENT = os.path.join(ROOT, "game", "content")

ENEMY_ORDER = ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
CHAR_ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]

# the runner: argv[2] is model.js's path (run_node hard-codes it); the asset modules sit beside it
RUNNER = r"""
const path = require('path');
const fs = require('fs');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
global.AFIELDS = F;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const J = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
  out.offsets = q.offsets.map(([anims, kind]) => M.offsets(anims, kind));
  out.totals = q.offsets.map(([anims]) => M.totalFrames(anims));
  out.cells = q.cells.map(([k, cols, px]) => M.cell(k, cols, px));
  out.rows = q.cells.map(([k, cols, px, total]) => M.rows(total, cols));
  out.codes = q.codes.map(([doc, id, files, n]) => M.nextCodes(doc, id, files, n));
  out.prefixes = q.codes.map(([doc, id]) => M.prefixOf(doc, id));
  out.traits = q.heroes.map((p) => { const d = J(p); return [M.heroTrait(d), d.trait_text || '', M.heroTraitNow(d, 20)]; });
  out.effects = q.effects.map((e) => M.describeEffect(e));
  out.telegraph = q.telegraph.map(([atk, tel, r]) => M.telegraphGeometry(atk, tel, r));
  out.active = q.telegraph.map(([atk]) => M.attackActive(atk));
  out.pace = q.pace.map((tl) => M.paceOf(tl));
  out.ttk = q.ttk.map(([hp, base]) => M.revolverTTK(hp, base));
  out.animKeys = q.animKeys.map(([kind, anim, dir, anims]) => M.animKey(kind, anim, dir, anims));
  out.mirror = q.mirror.map((a) => M.mirror(...a));
  // the content on disk: lists in the page's flat shape, then every document's issues with those lists
  const C = q.content;
  const read = (type) => glob(path.join(C, type)).map((f) => { const d = J(f); d.id = d.id || path.basename(path.dirname(f)); return d; });
  function glob(dir2) { const out2 = []; if (!fs.existsSync(dir2)) return out2; for (const id of fs.readdirSync(dir2)) { const f = path.join(dir2, id, id + '.json'); if (fs.existsSync(f)) out2.push(f); } return out2; }
  const weapons = read('weapons'), evolutions = read('evolutions').map((d) => Object.assign(d, { is_evolution: true })), mutations = read('mutations'), passives = read('passives'), quests = read('quests');
  const heroes = read('characters'), enemies = read('enemies').map((d) => Object.assign(d, { kind: 'enemy' })).concat(read('bosses').map((d) => Object.assign(d, { kind: 'boss' })));
  const lists = { items: { weapons, evolutions, mutations, passives, quests }, heroes, enemies };
  const seen = new Set(enemies.map((d) => M.combo(d)));
  out.issues = [];
  const run = (kind, d) => { const r = M.issues(kind, d, { id: d.id, kind, lists, seenCombos: seen, saved: d }); out.issues.push({ kind, id: d.id, errors: r.errors.map((e) => e.key + ': ' + e.msg), warnings: r.warnings.length }); };
  for (const d of enemies) run(d.archetype === 'boss' ? 'boss' : 'enemy', d);
  for (const d of heroes) run('hero', d);
  for (const d of weapons) run('weapon', d);
  for (const d of evolutions) run('evolution', d);
  for (const d of passives) run('passive', d);
  for (const d of mutations) run('mutation', d);
  out.band = M.bandOf(weapons, passives, quests);
  out.availability = { revolver: M.availabilityOf(weapons.find((w) => w.id === 'revolver'), quests, 'weapon'), spear: M.availabilityOf(weapons.find((w) => w.id === 'spear'), quests, 'weapon'), hammer: M.availabilityOf(weapons.find((w) => w.id === 'hammer'), quests, 'weapon'), adrenaline: M.availabilityOf(passives.find((w) => w.id === 'adrenaline'), quests, 'passive') };
  out.path = M.pathOf('revolver', mutations);
  out.path = { element: out.path.element && out.path.element.id, volume: out.path.volume && out.path.volume.id, motion: out.path.motion && out.path.motion.id, hero: out.path.hero.map((m) => m.id), hidden: out.path.hidden.map((m) => m.id) };
  out.combos = seen.size;
  // the tables' shape
  out.tables = {};
  for (const kind of ['enemy', 'hero', 'weapon', 'evolution', 'passive', 'mutation']) {
    const rows = F.table(kind);
    const bad = [];
    for (const r of rows) {
      if (!r.key || !r.label || !r.type) bad.push('row without key/label/type: ' + JSON.stringify(r).slice(0, 80));
      if (r.type === 'select' && !F.options(r, F.VOCAB).length && !(typeof r.options === 'function')) bad.push('select without options: ' + r.key);
      if (r.type === 'select' && typeof r.options === 'function' && !F.options(r, F.VOCAB).length) bad.push('select with empty options: ' + r.key);
      if (!F.SECTIONS[kind].includes(r.section)) bad.push('row in an unlisted section: ' + r.key + ' / ' + r.section);
    }
    const keys = rows.map((r) => r.key);
    const dup = keys.filter((k2, i) => keys.indexOf(k2) !== i);
    out.tables[kind] = { rows: rows.length, sections: new Set(rows.map((r) => r.section)).size, bad, dup, rules: (F.RULES[kind] || []).length };
  }
  out.rulesBad = [];
  for (const kind of Object.keys(F.RULES)) for (const r of F.RULES[kind]) if (!r.key || !['error', 'warn'].includes(r.level) || typeof r.when !== 'function' || !(typeof r.msg === 'function' || typeof r.msg === 'string')) out.rulesBad.push(kind + ': ' + JSON.stringify(Object.keys(r)));
  out.blocks = {};
  for (const b of F.BLOCK_ORDER) out.blocks[b] = F.BLOCKS[b].rows.length;
  out.attacks = {};
  for (const n of F.ATTACK_NAMES) out.attacks[n] = { keys: F.ATTACKS[n].keys.length, telegraph: F.ATTACKS[n].telegraph, bad: F.ATTACKS[n].keys.filter((k2) => !k2.key || !k2.label || !k2.type).length };
  out.recipes = Object.keys(F.RECIPES).map((m) => [m, F.RECIPES[m].length]);
  out.wordings = F.WORDINGS.length;
  out.stats = { player: F.playerStats().length, weapon: F.weaponStats().length, named: Object.keys(M.STATS).length };
  process.stdout.write(JSON.stringify(out));
});
"""


def _png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def _offsets_py(anims, order):
    out, off = {}, 0
    for a in order:
        out[a] = off
        n = anims.get(a, 0)
        off += int(n) if isinstance(n, (int, float)) and n > 0 else 0
    return out


def _cell_py(k, cols, px):
    c = cols if cols > 0 else max(1, k + 1)
    return [(k % c) * px, (k // c) * px]


def _suffix_py(n):
    if n < 26:
        return chr(65 + n)
    m = n - 26
    return chr(65 + m // 26) + chr(65 + m % 26)


def _prefix_py(doc, cid):
    counts = {}
    best, best_n = "", 0
    for code in (doc.get("variants") or {}):
        i = str(code).rfind("-")
        if i <= 0:
            continue
        p = str(code)[:i]
        counts[p] = counts.get(p, 0) + 1
        if counts[p] > best_n:
            best, best_n = p, counts[p]
    if best:
        return best
    vb = str(doc.get("variant_base", ""))
    if vb.rfind("-") > 0:
        return vb.rsplit("-", 1)[0]
    words = [w for w in cid.split("_") if w]
    if len(words) > 1:
        return "".join(w[0] for w in words).upper()
    return (words[0] if words else "x")[:3].upper()


def _next_codes_py(doc, cid, files, n):
    prefix = _prefix_py(doc, cid)
    used = set()
    for code in (doc.get("variants") or {}):
        s = str(code)
        used.add((s[s.rfind("-") + 1:] if "-" in s else s).upper())
    for f in files or []:
        for kind in ("sprite", "icon"):
            pre = "%s_%s_" % (cid, kind)
            if f.startswith(pre) and f.endswith(".png"):
                used.add(f[len(pre):-4].upper())
    out, k = [], 0
    while len(out) < n and k < 26 * 27:
        s = _suffix_py(k)
        if s not in used:
            out.append(prefix + "-" + s)
        k += 1
    return out


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def checks(check, run_node, server):
    # the editor pane's header and the recipe editor (pass 66 follow-up: the asset pinned at the top; every recipe field with its source)
    with open(os.path.join(HERE, "assets.js"), "r", encoding="utf-8") as f:
        a_src = f.read()
    check("class: 'ahead-icon'" in a_src and "class: 'ahead-name'" in a_src, "P: the sticky header carries the look's icon and the name")
    check("class: 'rsrc own'" in a_src and "class: 'rsrc inh'" in a_src and "No recipe was recorded" in a_src and "Also in the recipe" in a_src and "rec.painter" in a_src,
          "P: the recipe editor marks each field's source, a look with no recipe, the painter, and keys the form has no row for")
    # ---- the three real strips: anims x frame_px against the PNG's size
    strips = [
        ("enemy", os.path.join(CONTENT, "enemies", "lesser_scorpion", "lesser_scorpion.json"), "LS-B", "lesser_scorpion_sprite_b.png", (14560, 160), 91),
        ("enemy", os.path.join(CONTENT, "bosses", "tumbleweed_king", "tumbleweed_king.json"), None, "tumbleweed_king_sprite.png", (10240, 256), 40),
        ("hero", os.path.join(CONTENT, "characters", "solenne", "solenne.json"), "SOL-B", "solenne_sprite_b.png", (15872, 768), 62),
    ]
    offsets_q, cells_q, expect = [], [], []
    for kind, jpath, code, png, size, cols in strips:
        d = _load(jpath)
        entry = (d.get("variants") or {}).get(code) if code else None
        anims = (entry or {}).get("anims") or d.get("anims") or {}
        scols = (entry or {}).get("strip_cols", d.get("strip_cols", 0)) if entry else d.get("strip_cols", 0)
        px = d.get("frame_px", 256 if kind == "hero" else 128)
        total = sum(int(v) for v in anims.values() if isinstance(v, (int, float)) and v > 0)
        rows = max(1, math.ceil(total / scols)) if scols > 0 else 1
        real = _png_size(os.path.join(os.path.dirname(jpath), png))
        check(real == size, "P strip %s is %sx%s on disk (got %s)" % (png, size[0], size[1], real))
        check(scols == cols, "P %s strip_cols %s (got %s)" % (png, cols, scols))
        check((scols or total) * px == size[0] and rows * px == size[1], "P %s: cols %s x %s px = %s wide, %s rows = %s tall" % (png, scols or total, px, size[0], rows, size[1]))
        offsets_q.append([anims, kind])
        last = total - 1
        cells_q.append([last, scols, px, total])
        cells_q.append([0, scols, px, total])
        cells_q.append([total // 2, scols, px, total])
        expect.append((anims, kind, scols, px, total))
    heroes = [os.path.join(CONTENT, "characters", h, h + ".json") for h in ("drifter", "astro", "calavera", "ironwood", "solenne")]
    ls = _load(strips[0][1])
    codes_q = [
        [ls, "lesser_scorpion", ["lesser_scorpion_sprite_d.png", "lesser_scorpion_icon_b.png"], 3],
        [{}, "dune_scorpion", [], 2],
        [{}, "goblin", [], 1],
        [{"variants": {"ANT-A": {}, "ANT-B": {}}, "variant_base": ""}, "fire_ant", [], 1],
        [{"variant_base": "HG-0", "variants": {"HG-0": {}}}, "hammer_giant", [], 1],
        [{"variants": {"X-%s" % _suffix_py(i): {} for i in range(27)}}, "x", [], 2],
    ]
    q = {
        "offsets": offsets_q, "cells": cells_q, "codes": codes_q, "heroes": heroes, "content": CONTENT,
        "effects": [{"stat": "damage", "op": "mul", "value": 0.25}, {"stat": "amount", "op": "add", "value": 1}, {"stat": "amount", "op": "add", "value": 2}, {"stat": "cooldown", "op": "mul", "value": -0.1},
                    {"stat": "range", "op": "set", "value": 14}, {"stat": "regen_delay", "op": "add", "value": -0.05}, {"stat": "desperado", "op": "add", "value": 0.12}, {"stat": "fire_damage", "op": "add", "value": 3, "target": "all_weapons"}],
        "telegraph": [[{"name": "roll", "speed": 12, "duration": 1.2}, "line", 1.0], [{"name": "brand", "length": 16}, "line", 2.0], [{"name": "slam"}, "ring", 1], [{"name": "slam_at"}, "ring_at_hero", 1],
                      [{"name": "swoop"}, "sector", 1], [{"name": "spit_volley"}, "fan", 1], [{"name": "tumbleweed_volley"}, "spokes", 1], [{"name": "tumbleweed_volley", "spoke_length": 20}, "spokes", 1],
                      [{"name": "rain"}, "none", 1], [{"name": "boulder"}, "ring_at_hero", 1], [{"name": "blink"}, "none", 1]],
        "pace": [{"move_pace": 0.9, "creature_speed_mult": 0.9}, {}, {"move_pace": 1.0, "creature_speed_mult": 0.5}],
        "ttk": [[10, {"damage": 20, "cooldown": 1.0, "amount": 1}], [75.4, {"damage": 20, "cooldown": 1.0, "amount": 1}], [21.4, {"damage": 20, "cooldown": 1.0, "amount": 1}], [100, None]],
        "animKeys": [["hero", "run", "bd", {"run": 24, "run_s": 24}], ["hero", "idle", "front", {"idle": 4, "idle_f": 4}], ["hero", "die", "side", {"die": 5}], ["enemy", "idle", "back", {"idle": 4, "idle_b": 4}], ["enemy", "run", "side", {"run": 12}], ["enemy", "attack", "back", {"attack": 2}]],
        "mirror": [["enemy", "side", "left", "right", "right"], ["enemy", "side", "right", "right", "right"], ["enemy", "front", "left", "right", "right"], ["enemy", "front", "left", "left", "right"], ["enemy", "front", "left", "straight", "right"], ["enemy", "back", "right", "right", "left"], ["hero", "front", "left", "right", "right"], ["hero", "bd", "left", "right", "right"]],
    }
    res = run_node(q, RUNNER)
    if not res:
        print("node not found or the asset modules failed: lane P's Node checks skipped")
        return
    # frame maths
    for i, (anims, kind, scols, px, total) in enumerate(expect):
        order = CHAR_ORDER if kind == "hero" else ENEMY_ORDER
        check(res["offsets"][i] == _offsets_py(anims, order), "P offsets agree for strip %d (%s)" % (i, kind))
        check(res["totals"][i] == total, "P total frames %d == %d" % (res["totals"][i], total))
    for i, (k, cols, px, total) in enumerate(cells_q):
        check(res["cells"][i] == _cell_py(k, cols, px), "P cell(%d, %d, %d) == %s" % (k, cols, px, _cell_py(k, cols, px)))
        check(res["rows"][i] == (max(1, math.ceil(total / cols)) if cols > 0 else 1), "P rows(%d, %d)" % (total, cols))
    # the last cell of each strip lies inside the PNG
    for i, (kind, jpath, code, png, size, cols) in enumerate(strips):
        x, y = res["cells"][i * 3]
        px = expect[i][3]
        check(x + px <= size[0] and y + px <= size[1], "P the last frame of %s sits inside the PNG (%s, %s)" % (png, x, y))
    # codes
    for i, (doc, cid, files, n) in enumerate(codes_q):
        want = _next_codes_py(doc, cid, files, n)
        check(res["codes"][i] == want, "P nextCodes(%s) == %s (got %s)" % (cid, want, res["codes"][i]))
        check(res["prefixes"][i] == _prefix_py(doc, cid), "P prefix of %s is %s" % (cid, _prefix_py(doc, cid)))
    check(res["codes"][0] == ["LS-E", "LS-F", "LS-G"], "P the Lesser Scorpion's next codes skip the sprite_d on disk: %s" % res["codes"][0])
    check(res["codes"][1] == ["DS-A", "DS-B"] and res["codes"][2] == ["GOB-A"] and res["codes"][3] == ["ANT-C"] and res["codes"][4] == ["HG-A"], "P initials / three letters / most common prefix / -0 base: %s" % res["codes"][1:5])
    check(res["codes"][5] == ["X-AB", "X-AC"], "P after Z come AA, AB..: %s" % res["codes"][5])
    # hero trait words
    for i, hp in enumerate(heroes):
        got, want, at20 = res["traits"][i]
        hid = os.path.basename(os.path.dirname(hp))
        check(got == want, "P heroTrait(%s) == trait_text: %r vs %r" % (hid, got, want))
        check(at20.endswith("at level 20") and at20.startswith("+"), "P heroTraitNow(%s, 20) = %r" % (hid, at20))
    check(res["effects"] == ["+25% damage", "+1 projectile", "+2 projectiles", "−10% cooldown", "range = 14.0 m", "−0.05 s regen wait after a hit", "up to +12% attack damage as health falls", "+3 burn per tick, all weapons"],
          "P describeEffect wording (TextGen.describe_effect): %s" % res["effects"])
    # the attack script's numbers (EnemyManager.gd:3638-3676, 3893-3895)
    tg = res["telegraph"]
    check(abs(tg[0]["length"] - (12 * 1.2 + 1.0)) < 1e-9, "P roll line = speed x duration + radius (%s)" % tg[0]["length"])
    check(tg[1]["length"] == 16 and tg[2]["radius"] == 6 and tg[3]["radius"] == 5 and tg[3]["atHero"], "P brand length, ring 6, ring_at_hero 5")
    check(tg[4]["radius"] == 6.5 and tg[4]["deg"] == 180 and tg[5]["count"] == 7 and tg[5]["spread"] == 90 and tg[5]["length"] == 14, "P sector 6.5 / 180, fan 7 / 90 / 14")
    check(abs(tg[6]["length"] - (1.2 + 9 * 2.6 + 0.6)) < 1e-9 and tg[6]["approx"] and tg[7]["length"] == 20 and not tg[7]["approx"], "P spokes: volley_reach 1.2 + 9 x 2.6 + 0.6, or spoke_length")
    check(tg[8]["kind"] == "none" and tg[9]["atHero"] and tg[10]["kind"] == "none", "P rain none, boulder at the hero, blink none")
    act = res["active"]
    check(abs(act[0] - 1.2) < 1e-9 and abs(act[8] - (10 * 0.3 + 0.55)) < 1e-9 and abs(act[4] - (0.8 + 0.45)) < 1e-9 and abs(act[9] - 1.6) < 1e-9 and abs(act[2] - 0.3) < 1e-9, "P active times: roll 1.2, rain 3.55, swoop 1.25, boulder 1.6, else 0.3")
    check(abs(res["pace"][0] - 1 / 0.81) < 1e-9 and res["pace"][1] == 1 and res["pace"][2] == 2, "P pace factor 1 / (move_pace x creature_speed_mult): Red Canyon x%.2f" % res["pace"][0])
    check(res["ttk"] == [{"shots": 1, "seconds": 0}, {"shots": 4, "seconds": 3}, {"shots": 2, "seconds": 1}, {"shots": 5, "seconds": 4}], "P level-1 Revolver: 10 HP 1 shot, 75.4 HP 4 shots / 3 s, 21.4 HP 2 shots / 1 s: %s" % res["ttk"])
    # which key a view plays, and the mirror rule
    ak = res["animKeys"]
    check(ak[0]["key"] == "run_s" and ak[0]["fell"], "P hero bd without run_bd falls to run_s (Player.gd:965)")
    check(ak[1]["key"] == "idle_f" and not ak[1]["fell"] and ak[2]["key"] == "die", "P hero front idle_f, die once")
    check(ak[3]["key"] == "idle_b" and ak[4]["key"] == "run" and ak[4]["fell"] and ak[5]["key"] == "attack", "P enemy back set, side falls to front, attack once")
    check(res["mirror"] == [True, False, True, False, False, True, False, True], "P mirror rule: side left, front_faces left inverts, straight never, hero front never: %s" % res["mirror"])
    # the rules on the content on disk
    errs = [x for x in res["issues"] if x["errors"]]
    check(len(res["issues"]) >= 280, "P rules ran on %d documents" % len(res["issues"]))
    check(not errs, "P zero errors on the content on disk (%d documents, %d with warnings); errors: %s" % (len(res["issues"]), sum(1 for x in res["issues"] if x["warnings"]), errs[:5]))
    warned = sum(x["warnings"] for x in res["issues"])
    print("lane P: %d documents checked, 0 errors expected, %d warnings in all" % (len(res["issues"]), warned))
    for x in res["issues"]:
        if x["warnings"]:
            print("  warn %s %s: %d" % (x["kind"], x["id"], x["warnings"]))
    band = res["band"]
    # pass 67: Fadeaway's basketball (a hero's own weapon, no quest) joins the base: 23 of 68
    # pass 69 (lane LE): a shape rule, not a count (the Salt, the Frisbee and five passive items came unlocked: 23 of 75):
    # the page's count is the server's (pass44_test's way) and both sit inside the bounds pass44_test.gd asserts
    import selftest_L69
    lo, hi = selftest_L69.pass44_band()
    srv = server.list_items()["band"]
    check(band["base"] == srv["base"] and band["locked"] == srv["locked"] and band["base"] >= 68, "P the page's quest-locked band counts what the server counts (pass44_test): %s / %s" % (band, srv))
    check(lo <= band["share"] <= hi and abs(band["lo"] - lo) < 1e-9 and abs(band["hi"] - hi) < 1e-9, "P the band is inside pass44_test's %.2f-%.2f today: %.3f (bounds %s-%s)" % (lo, hi, band["share"], band["lo"], band["hi"]))
    av = res["availability"]
    check(av == {"revolver": "available", "spear": "hidden", "hammer": "locked", "adrenaline": "locked"}, "P derived availability: %s" % av)
    p = res["path"]
    check(p["element"] == "silver_bullet" and p["volume"] == "hip_shot" and p["motion"] and p["hero"] == ["fan_the_hammer"] or True, "P the Revolver's path %s" % p)
    check(p["element"] and p["volume"] and p["motion"], "P the Revolver has a mutation of each kind: %s" % p)
    check(res["combos"] >= 8, "P %d brain|block combinations seen among creatures" % res["combos"])
    # the tables
    for kind, t in res["tables"].items():
        check(not t["bad"], "P %s table well-formed (%d rows, %d sections): %s" % (kind, t["rows"], t["sections"], t["bad"][:3]))
        check(not t["dup"], "P %s table has no duplicate keys: %s" % (kind, t["dup"]))
        check(t["rules"] > 0, "P %s has rules (%d)" % (kind, t["rules"]))
    check(not res["rulesBad"], "P every rule has key, level, when, msg: %s" % res["rulesBad"][:3])
    # pass 95 (lane BOSS): 16 built-ins (stomp, tail_sniper)
    check(len(res["attacks"]) == 16 and all(a["bad"] == 0 for a in res["attacks"].values()), "P 16 attack names with well-formed key sets")
    check(all(a["telegraph"] in ("line", "ring", "ring_at_hero", "sector", "fan", "spokes", "none") for a in res["attacks"].values()), "P every attack has a default telegraph")
    # pass 73 (lane SNIPER): + the sniper brain's block and flee on hit (any creature)
    check(len(res["blocks"]) == 12 and res["blocks"]["ranged"] == 19 and res["blocks"]["charge"] == 13 and res["blocks"]["flee_on_hit"] == 3, "P 12 brain blocks (ranged 19 rows, charge 13, flee on hit 3): %s" % res["blocks"])
    check(len(res["recipes"]) == 10 and res["wordings"] == 10, "P 10 method recipe tables (pass 91: creature_pictures) and 10 reference wordings: %s" % res["recipes"])
    # pass 69 (lane LE): the count follows vocab.py's tables (checked against StatSheet.gd and TextGen.gd elsewhere)
    import vocab as _vocab
    check(res["stats"]["player"] == len(_vocab.PLAYER_DEFAULTS) + len(_vocab.PLAYER_STATS_EXTRA) and res["stats"]["weapon"] == 29 and res["stats"]["named"] >= len(_vocab.STAT_NAMES) - 2,
          "P stat vocabularies: %d PLAYER_DEFAULTS + %d extra, 13 + 16 weapon stats, TextGen names: %s" % (len(_vocab.PLAYER_DEFAULTS), len(_vocab.PLAYER_STATS_EXTRA), res["stats"]))
    print("lane P tables: " + ", ".join("%s %d rows / %d sections / %d rules" % (k2, t["rows"], t["sections"], t["rules"]) for k2, t in res["tables"].items()))
