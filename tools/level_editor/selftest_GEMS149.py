"""Pass 149, lane EDITOR: the hard currency (the gems) everywhere the Level Editor sets a price or a reward, and the Store tab.

Groups:
  trail   trail_model.js under Node: a node's own `currency` (Trail.currency_of mirrored), its checks (a currency id the
          content lacks is an error), the sums apart per currency (gems never add to coins; a choice once in its
          currency), the CSV's currency column out and back; trail_io: the shape check, the pick lists' currency_info, a
          save that names an unknown currency refused and one in gems written
  wanted  wanted_model.js under Node: a task's `reward_currency` and `reward_fixed` on the poster as WantedBoard.make_contract
          sets them (the contract's `currency`, the fixed amount), currencyOf / taskPay, the checks; wanted_io: the shape
          check, a save in gems written, an unknown currency refused
  outlaws the Outlaws tab's Currency select lists the registry (gold and gems), the availability route takes any id of it,
          a skin's currency select too (pass 111)
  store   store_model.js under Node: the bonus tags (the gems a dollar, the coins a gem), nice() and the coin offer rule
          (COMMON.md decision 2) at every stage x Trail level, against lane STORE's fixture
          game/tests/fixtures/pass149_store_coins.json when it is there (skipped with a note while it is missing), the checks
          on broken copies; the game's store.json clean
  storeio store_io on a temporary content tree: the read (currencies, stages, the Trail's top, the pictures), the file's
          layout kept, unchanged, a save with a backup, keys the page does not know kept, a stale page (409), broken shapes
          and unknown currencies (400), a version 1 file replaced whole, the picture route only under art/
  page    the Store tab, its section, style and scripts on the page; app.js renders, saves and guards it; server.py routes
          /api/store; #store is a route; the scripts parse
Nothing here writes under game/.
"""
import json
import os
import shutil
import subprocess
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
FIXTURE = os.path.join(HERE, "fixtures", "trail_sample.json")
STORE_FIXTURE = os.path.join(GAME, "tests", "fixtures", "pass149_store_coins.json")
_TAG = "GEMS149"

PICKS = {"outlaws": [{"id": "astro", "name": "Astro"}, {"id": "may", "name": "May"}], "skins": [{"id": "may:MAY-S", "name": "May, Carnival"}],
         "weapons": [{"id": "tommy_gun", "name": "Tommy Gun"}], "passives": [{"id": "adrenaline", "name": "Adrenaline", "mark": "item"}, {"id": "aegis", "name": "The Guardian", "mark": "card"}],
         "maps": [{"id": "red_canyon", "name": "Red Canyon", "stages": [{"id": "s1", "name": "Sundown"}, {"id": "dust", "name": "The Dust Bowl"}]}],
         "structures": [{"id": "totem_pole", "name": "Totem Pole"}], "powerups": [{"id": "rage", "name": "Rage"}], "features": ["wanted"],
         "currencies": ["gold", "gems"], "icons": ["might"], "stats": ["might"]}

TRAIL_JS = r"""
const M = require('./trail_model.js');
const fs = require('fs');
const P = JSON.parse(process.argv[3]);
const d = M.normalise(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));
const copy = () => JSON.parse(JSON.stringify(d));
const node = (x, id) => x.nodes.find((n) => n.id === id);
const codes = (x, p) => M.check(x, p === undefined ? P : p).filter((i) => i.code === 'currency' || i.code === 'unknown_id').map((i) => `${i.sev}:${i.code}:${i.id || ''}`);
const out = {};
const t0 = M.totals(d, 500);
const g = copy();
node(g, 'n005').currency = 'gems'; node(g, 'n005').price = 120;            // a plain node priced in gems
node(g, 'n004').currency = 'gems';                                         // an optional one on the curve, in gems
node(g, 'n006').currency = 'gems'; node(g, 'n006').price = 50;             // a choice member in gems (its sibling in gold)
const t1 = M.totals(g, 500);
const lvl = (t, l) => t.levels[l - 1];
out.sums = {
  before: [t0.all, t0.required, t0.optional, Object.keys(t0.other).length, t0.currency],
  after: [t1.all, t1.required, t1.optional, t1.currency],
  gems: t1.other.gems,
  moved: [t0.all - t1.all, M.priceOf(d, node(d, 'n005')) + M.priceOf(d, node(d, 'n004')) + M.priceOf(d, node(d, 'n006'))],
  lv5: [lvl(t0, 5).required, lvl(t1, 5).required, M.priceOf(d, node(d, 'n006')), M.priceOf(d, node(d, 'n007'))],
};
out.cur = [M.currencyOf(g, node(g, 'n005')), M.currencyOf(g, node(g, 'n001')), M.trailCurrency(g), M.currencyOf({ nodes: [] }, { id: 'x' }), M.trailCurrency({})];
const bad = copy(); node(bad, 'n001').currency = 'beans'; node(bad, 'n002').currency = 'Gems!';
out.checks = { ok: codes(g), bad: codes(bad), noPicks: codes(bad, null), errs: M.errorsOf(M.check(g, P)).length };
const csv = M.toCsv(g, { bom: false });
const back = M.fromCsv(csv, g);
const lines = csv.trim().split('\n');
const edited = lines.slice();
const head = lines[0].split(','), ci = head.indexOf('currency');
const cells = edited[1].split(','); cells[ci] = 'GEMS'; edited[1] = cells.join(',');
const noCol = M.fromCsv([lines[0].split(',').filter((c) => c !== 'currency').join(',')].concat(lines.slice(1).map((l) => { const c = l.split(','); c.splice(ci, 1); return c.join(','); })).join('\n'), g);
out.csv = { head: lines[0], ci, n005: lines.find((l) => l.startsWith('n005,')), round: JSON.stringify(back.nodes) === JSON.stringify(g.nodes), problems: back.problems.length,
  upper: M.fromCsv(edited.join('\n'), g).nodes[0].currency, keptWithoutColumn: node({ nodes: noCol.nodes }, 'n005').currency,
  keys: Object.keys(node({ nodes: back.nodes }, 'n006')).join(',') };
console.log(JSON.stringify(out));
"""

WANTED_JS = r"""
const WM = require('./wanted_model.js');
const cfg0 = WM.normalized(JSON.parse(process.argv[2]));
const ctx = { stage: 0, P: 0, map: 'red_canyon', creatures: [], weapons: [], lines: [], passives: [], hero: { id: 'drifter' }, beaten: false, totem_poles: 10, elite_estimate: 0 };
const one = (cfg, type, seed) => WM.makeContract(cfg, type, ctx, WM.mulberry32(seed || 7));
const set = (cfg, type, extra) => { const c = JSON.parse(JSON.stringify(cfg)); Object.assign(c.tasks.find((t) => t.type === type), extra); return WM.normalized(c); };
const plain = one(cfg0, 'kill_total');
const gems = one(set(cfg0, 'kill_total', { reward_currency: 'gems' }), 'kill_total');
const fixed = one(set(cfg0, 'kill_total', { reward_currency: 'gems', reward_fixed: 25 }), 'kill_total');
const fixedGold = one(set(cfg0, 'kill_total', { reward_fixed: 77.5 }), 'kill_total');
const zero = one(set(cfg0, 'kill_total', { reward_fixed: 0 }), 'kill_total');
const boardGems = WM.normalized(Object.assign(JSON.parse(JSON.stringify(cfg0)), { reward: Object.assign({}, cfg0.reward, { currency: 'gems' }) }));
const out = {
  plain: [plain.reward, 'currency' in plain, WM.currencyOf(cfg0, plain)],
  gems: [gems.reward === plain.reward, gems.currency, WM.currencyOf(cfg0, gems), gems.n === plain.n, gems.d === plain.d],
  fixed: [fixed.reward, fixed.currency, fixed.d === plain.d], fixedGold: [fixedGold.reward, 'currency' in fixedGold, WM.currencyOf(cfg0, fixedGold)],
  zero: zero.reward === plain.reward,
  board: [WM.boardCurrency(cfg0), WM.boardCurrency(boardGems), WM.currencyOf(boardGems, plain), WM.currencyOf(boardGems, gems)],
  pay: [WM.taskPay(cfg0, 'kill_total'), WM.taskPay(set(cfg0, 'kill_total', { reward_currency: 'gems', reward_fixed: 25 }), 'kill_total')],
  issues: {
    ok: WM.issues(set(cfg0, 'kill_total', { reward_currency: 'gems', reward_fixed: 25 }), ['gold', 'gems']).errors,
    unknown: WM.issues(set(cfg0, 'kill_total', { reward_currency: 'beans' }), ['gold', 'gems']).errors,
    noList: WM.issues(set(cfg0, 'kill_total', { reward_currency: 'beans' })).errors,
    shape: WM.issues(set(cfg0, 'kill_total', { reward_currency: 'Gems!', reward_fixed: -5 }), ['gold', 'gems']).errors,
    board: WM.issues(WM.normalized(Object.assign(JSON.parse(JSON.stringify(cfg0)), { reward: Object.assign({}, cfg0.reward, { currency: 'beans' }) })), ['gold', 'gems']).errors,
  },
};
console.log(JSON.stringify(out));
"""

STORE_JS = r"""
const M = require('./store_model.js');
const fs = require('fs');
const real = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const fx = process.argv[3] ? JSON.parse(fs.readFileSync(process.argv[3], 'utf8')) : null;
const D = M.normalise(M.DEFAULTS);
const sc = D.coins.scaling;
const offer = (id) => D.coins.offers.find((o) => o.id === id);
const copy = () => JSON.parse(JSON.stringify(D));
const errs = (x, ctx) => M.check(x, ctx === undefined ? { currencies: ['gold', 'gems'], stages: 4 } : ctx).filter((i) => i.sev === 'error').map((i) => i.path);
const warns = (x) => M.check(x, { currencies: ['gold', 'gems'], stages: 4, pictures: [] }).filter((i) => i.sev === 'warn').map((i) => i.path);
const brk = (fn, ctx) => { const x = copy(); fn(x); return errs(x, ctx); };
const out = {};
out.bonus = { gems: M.gemBonus(D), offers: M.offerBonus(D), off: M.gemBonus(Object.assign(copy(), { gems: Object.assign(copy().gems, { show_bonus: false }) })),
  dollars: [M.dollars(99), M.dollars(499), M.dollars(100), M.dollars(0)] };
out.nice = [M.nice(17325, 2), M.nice(1000, 2), M.nice(3150, 2), M.nice(999.5, 2), M.nice(0, 2), M.nice(-5, 2), M.nice(123456, 3), M.nice(7, 2), M.nice(1e6 - 0.0001, 2), M.nice(14999, 1)];
out.rule = {
  common: [M.coinsFor(offer('coins_small'), 1, 0, sc), M.coinsFor(offer('coins_medium'), 1, 10, sc)],
  stages: [0, 1, 2, 3, 4, 9, -1].map((s) => M.coinsFor(offer('coins_small'), s, 0, sc)),
  trail: [0, 9, 10, 19, 20, 35, 83].map((T) => M.coinsFor(offer('coins_large'), 0, T, sc)),
  steps: [M.trailSteps(sc, 9), M.trailSteps(sc, 10), M.trailSteps(sc, 83), M.trailSteps({ trail_step: 0 }, 5)],
  stageMult: [M.stageMult(sc, 2), M.stageMult(sc, 7), M.stageMult({ stage_mult: [] }, 1)],
  monotone: D.coins.offers.every((o) => { let last = 0; for (let s = 0; s < 4; s++) for (const T of [0, 10, 20, 40, 60, 83]) { const c = M.coinsFor(o, s, T, sc); if (T === 0 && c < last) return false; last = T === 0 ? c : last; } return true; }),
  twoFigures: D.coins.offers.every((o) => [0, 1, 2, 3].every((s) => [0, 10, 35, 83].every((T) => { const c = M.coinsFor(o, s, T, sc); return String(c).replace(/0+$/, '').length <= 2; }))),
};
const pv = M.preview(D, [{ name: 'Sundown' }, { name: 'Nightfall' }, { name: 'The Dust Bowl' }, { name: 'Blood Moon' }], M.previewLevels(83));
out.preview = { offers: pv.length, rows: pv[0].rows.length, cols: pv[0].rows[0].cells.length, levels: M.previewLevels(83), short: M.previewLevels(30), first: pv[1].rows[1].cells.map((c) => c.coins), name: pv[0].rows[3].name };
out.checks = {
  clean: errs(D), realErrs: errs(real), realWarns: M.check(real, { currencies: ['gold', 'gems'], stages: 4 }).filter((i) => i.sev === 'warn').map((i) => i.text),
  v1: brk((x) => { x.version = 1; }), cents: brk((x) => { x.gems.packs[0].price_cents = 0; }), text: brk((x) => { x.gems.packs[1].price_text = '$5.99'; }),
  dupe: brk((x) => { x.coins.offers[0].id = 'gems_pile'; }), ribbon: brk((x) => { x.coins.offers[1].ribbon = 'hot'; }), amount: brk((x) => { x.gems.packs[2].amount = 12.5; }),
  cur: brk((x) => { x.revive.currency = 'beans'; x.coins.pay = 'gold'; }), same: brk((x) => { x.coins.pay = 'gold'; }),
  scaling: brk((x) => { x.coins.scaling = { stage_mult: [1, 0], trail_step: -1, trail_per_step: -1, round_sig: 0 }; }),
  revive: brk((x) => { x.revive.price = -1; x.revive.per_run = 1.5; }), noCtx: brk((x) => { x.revive.currency = 'beans'; }, null),
  pic: brk((x) => { x.gems.packs[0].picture = 'art/ui/store/a.png'; }),
  warns: warns((() => { const x = copy(); x.coins.scaling.stage_mult = [1, 3]; x.revive.price = 50; x.revive.per_run = 0; x.gems.packs[0].ribbon = 'best_value'; return x; })()),
};
out.norm = { filled: Object.keys(M.normalise({})).join(','), kept: M.normalise({ version: 2, extra: 1, gems: { packs: [], mine: 2 } }).gems.mine, same: JSON.stringify(M.normalise(real)) === JSON.stringify(real) };
// lane STORE's fixture (tools/dl/p149/STORE/make_fixture.py): `cases` (offers x stages x levels under `scaling`), `edge`
// (the same offers under `scaling_edge`), `nice` [[v, sig, out]], `bonus` [{stage, trail, bonus: {offer: N}}]
if (fx) {
  const offers = new Map((fx.offers || []).map((o) => [o.id, o]));
  const data = { version: 2, coins: { currency: 'gold', pay: 'gems', show_bonus: true, offers: fx.offers || [], scaling: fx.scaling } };
  const run = (list, scaling) => (list || []).map((c) => ({ c, got: M.coinsFor(offers.get(c.offer), c.stage, c.trail, scaling) })).filter((x) => x.got !== x.c.coins).map((x) => Object.assign({ got: x.got }, x.c));
  const bonus = (fx.bonus || []).map((b) => ({ b, got: M.offerBonus(data, b.stage, b.trail) })).filter((x) => JSON.stringify(x.got) !== JSON.stringify(Object.assign({}, ...Object.keys(x.got).map((k) => ({ [k]: x.b.bonus[k] })))) || Object.keys(x.b.bonus).length !== Object.keys(x.got).length).map((x) => ({ at: [x.b.stage, x.b.trail], want: x.b.bonus, got: x.got }));
  const nice = (fx.nice || []).filter(([v, sig, want]) => M.nice(v, sig) !== want).map(([v, sig, want]) => ({ v, sig, want, got: M.nice(v, sig) }));
  out.fixture = { n: [(fx.cases || []).length, (fx.edge || []).length, (fx.nice || []).length, (fx.bonus || []).length], cases: run(fx.cases, fx.scaling).slice(0, 6), edge: run(fx.edge, fx.scaling_edge).slice(0, 6), nice, bonus: bonus.slice(0, 4),
    sameFile: JSON.stringify(fx.offers) === JSON.stringify(real.coins.offers) && JSON.stringify(fx.scaling) === JSON.stringify(real.coins.scaling) };
}
console.log(JSON.stringify(out));
"""


def _node(src, *args):
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8", dir=HERE, prefix="_gems149_") as f:
        f.write(src)
    try:
        p = subprocess.run(["node", f.name] + [str(a) for a in args], capture_output=True, text=True, encoding="utf-8", cwd=HERE, timeout=120)
    finally:
        os.remove(f.name)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-1500:])
    return json.loads(p.stdout)


class _Srv:
    def __init__(self, game):
        import content_io as cio
        self.GAME = game
        self.CONTENT = os.path.join(game, "content")
        self._write_lock = threading.Lock()
        self.backups = []
        self.restore_numbers = cio.restore_numbers

    def rel(self, p):
        return os.path.relpath(p, self.GAME).replace("\\", "/")

    def mtime_of(self, p):
        return round(os.path.getmtime(p), 3)

    def backup(self, name, p):
        self.backups.append(name)
        return "backup/" + name


def _put(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj))


def _read(*p):
    with open(os.path.join(*p), encoding="utf-8", newline="") as f:
        return f.read()


def _tree():
    """A temporary game folder with gold and gems, one map of four stages, a Trail of 83 levels, two store pictures."""
    tmp = tempfile.mkdtemp(prefix="le149_")
    c = os.path.join(tmp, "content")
    _put(os.path.join(c, "currencies", "gold", "gold.json"), {"id": "gold", "name": "Gold", "order": 0, "word": "gold", "icon": "res://art/ui/wanted/coin.png"})
    _put(os.path.join(c, "currencies", "gems", "gems.json"), {"id": "gems", "name": "Gems", "order": 1, "word": "gems", "icon": "res://art/ui/store/gem.png", "shown": "store"})
    _put(os.path.join(c, "maps", "red_canyon", "red_canyon.json"), {"id": "red_canyon", "timeline_data": {"stage_list": [{"id": "s1", "name": "Sundown"}, {"id": "s2", "name": "Nightfall"}, {"id": "dust", "name": "The Dust Bowl"}, {"id": "s3", "name": "Blood Moon"}]}})
    _put(os.path.join(c, "trail", "trail.json"), _read(FIXTURE))
    _put(os.path.join(tmp, "art", "ui", "store", "gem.png"), "png")
    _put(os.path.join(tmp, "art", "ui", "store", "pack_sack.png"), "png")
    _put(os.path.join(tmp, "art", "ui", "store", "notes.txt"), "x")
    _put(os.path.join(tmp, "secret.png"), "no")
    return tmp


# ---------------------------------------------------------------- trail

def _trail_checks(check):
    r = _node(TRAIL_JS, FIXTURE, json.dumps(PICKS))
    s = r["sums"]
    check(s["before"][3] == 0 and s["before"][4] == "gold", "%s trail: a Trail in one currency has nothing summed apart (%s)" % (_TAG, s["before"]))
    check(s["moved"][0] == s["moved"][1] - 0 and s["after"][0] == s["before"][0] - s["moved"][1], "%s trail: the three gem nodes' prices left the coins' total (%s)" % (_TAG, s))
    gm = s["gems"]
    check(gm and gm["nodes"] == 3 and gm["all"] == 120 + gm["all"] - 120 and gm["required"] == 120 + 50 and gm["optional"] == gm["all"] - 170 and gm["with_optional"] == gm["all"],
          "%s trail: the gems summed apart: 3 nodes, required = the plain node + the choice member once, optional apart (%s)" % (_TAG, gm))
    check(s["lv5"][1] == s["lv5"][3], "%s trail: level 5's choice counts its gold member alone in the coins once its sibling is in gems (%s)" % (_TAG, s["lv5"]))
    check(r["cur"] == ["gems", "gold", "gold", "gold", "gold"], "%s trail: currencyOf mirrors Trail.currency_of (own, else the Trail's, gold by default) (%s)" % (_TAG, r["cur"]))
    k = r["checks"]
    check(k["ok"] == [] and k["errs"] == 0, "%s trail: nodes in gems pass the checks (%s)" % (_TAG, k["ok"]))
    check(k["bad"] == ["error:unknown_id:n001", "error:currency:n002"] and k["noPicks"] == ["error:currency:n002"],
          "%s trail: a currency the content lacks is an error, a malformed one too; without the pick lists only the shape (%s | %s)" % (_TAG, k["bad"], k["noPicks"]))
    c = r["csv"]
    check(c["head"] == "id,level,kind,group,from,need,gives_type,gives_what,value,price,price_mult,currency,x,name,note,resolved_price,cumulative" and c["ci"] == 11,
          "%s trail: the CSV has a currency column after price_mult (%s)" % (_TAG, c["head"]))
    check(c["n005"].split(",")[9:12] == ["120", "", "gems"] and c["round"] and c["problems"] == 0, "%s trail: a gem node's row, and the file back unchanged (%s)" % (_TAG, c["n005"]))
    check(c["upper"] == "gems" and c["keptWithoutColumn"] == "gems", "%s trail: a typed GEMS reads gems; a CSV without the column keeps each node's currency" % _TAG)
    check("currency" in c["keys"].split(","), "%s trail: a node's own currency comes back from the CSV (%s)" % (_TAG, c["keys"]))
    # trail_io
    import trail_io as T
    src = json.loads(_read(FIXTURE))
    gem = json.loads(json.dumps(src))
    gem["nodes"][4]["currency"] = "gems"
    check(T.check(gem) == "" and T.check(gem, ["gold", "gems"]) == "", "%s trail io: a node in gems has the shape the game reads" % _TAG)
    beans = json.loads(json.dumps(gem))
    beans["nodes"][4]["currency"] = "beans"
    check("not in content/currencies" in T.check(beans, ["gold", "gems"]) and T.check(beans) == "", "%s trail io: an unknown currency is refused once the registry is known (%s)" % (_TAG, T.check(beans, ["gold", "gems"])))
    check("currency" in T.check(dict(gem, nodes=[dict(gem["nodes"][0], currency=5)])), "%s trail io: a currency that is no id is refused" % _TAG)
    check("not in content/currencies" in T.check(dict(gem, currency="beans"), ["gold", "gems"]), "%s trail io: the Trail's own currency is checked too" % _TAG)
    tmp = _tree()
    try:
        srv = _Srv(tmp)
        d = T.read(srv)
        info = d["picks"]["currency_info"]
        check([x["id"] for x in info] == ["gold", "gems"] and info[1]["icon"] == "/api/currencies/gems/icon" and info[1]["word"] == "gems" and d["picks"]["currencies"] == ["gems", "gold"],
              "%s trail io: the pick lists carry each currency's name, word and icon, in the registry's order (%s)" % (_TAG, info))
        bad = T.save(srv, beans, d["mtime"])
        check(bad.get("status") == 400 and "beans" in bad.get("error", "") and not srv.backups, "%s trail io: a save naming beans is refused (%s)" % (_TAG, bad))
        ok = T.save(srv, gem, d["mtime"])
        after = _read(T.path_of(srv))
        check(ok.get("ok") and '"currency": "gems"' in after and srv.backups == ["trail"], "%s trail io: a node in gems is written (%s)" % (_TAG, ok))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- wanted

def _wanted_checks(check):
    cfg = json.loads(_read(GAME, "content", "wanted", "wanted.json"))
    r = _node(WANTED_JS, json.dumps(cfg))
    check(r["plain"][1] is False and r["plain"][2] == "gold" and r["plain"][0] > 0, "%s wanted: a plain poster pays the formula in the board's gold (%s)" % (_TAG, r["plain"]))
    check(r["gems"] == [True, "gems", "gems", True, True], "%s wanted: reward_currency puts `currency` on the contract and changes nothing else (%s)" % (_TAG, r["gems"]))
    check(r["fixed"] == [25, "gems", True] and r["fixedGold"] == [78, False, "gold"] and r["zero"],
          "%s wanted: reward_fixed replaces the formula (rounded as int(round())); 0 keeps it (%s %s)" % (_TAG, r["fixed"], r["fixedGold"]))
    check(r["board"] == ["gold", "gems", "gems", "gems"], "%s wanted: currencyOf: the poster's own, else the board's (%s)" % (_TAG, r["board"]))
    check(r["pay"][0] == {"currency": "gold", "fixed": 0, "own": False} and r["pay"][1] == {"currency": "gems", "fixed": 25, "own": True}, "%s wanted: taskPay (%s)" % (_TAG, r["pay"]))
    i = r["issues"]
    check(i["ok"] == [] and len(i["unknown"]) == 1 and "beans" in i["unknown"][0] and i["noList"] == [] and len(i["shape"]) == 2 and len(i["board"]) == 1,
          "%s wanted: the checks: gems fine, beans an error once the registry is read, a malformed id and a negative fixed reward, the board's own (%s)" % (_TAG, i))
    import wanted_io as WIO
    gem = json.loads(json.dumps(cfg))
    t = next(x for x in gem["tasks"] if x["type"] == "kill_total")
    t["reward_currency"], t["reward_fixed"] = "gems", 25
    check(WIO.check(gem) == "" and WIO.check(gem, ["gold", "gems"]) == "", "%s wanted io: a task paying 25 gems has the shape the game reads" % _TAG)
    t["reward_currency"] = "beans"
    check("not in content/currencies" in WIO.check(gem, ["gold", "gems"]), "%s wanted io: an unknown task currency is refused (%s)" % (_TAG, WIO.check(gem, ["gold", "gems"])))
    t["reward_currency"], t["reward_fixed"] = "gems", -1
    check("reward_fixed" in WIO.check(gem), "%s wanted io: a negative fixed reward is refused" % _TAG)
    t["reward_fixed"] = 25
    tmp = _tree()
    try:
        srv = _Srv(tmp)
        _put(WIO.path_of(srv), WIO.dump(cfg))
        bad = WIO.save(srv, dict(gem, reward=dict(gem.get("reward") or {}, currency="beans")), None)
        check(bad.get("status") == 400 and "beans" in bad.get("error", ""), "%s wanted io: a save whose board pays beans is refused (%s)" % (_TAG, bad))
        ok = WIO.save(srv, gem, None)
        line = next(ln for ln in _read(WIO.path_of(srv)).split("\n") if '"kill_total"' in ln)
        check(ok.get("ok") and '"reward_currency": "gems"' in line and '"reward_fixed": 25' in line, "%s wanted io: the task paying 25 gems is written on its line (%s)" % (_TAG, ok))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    js = _read(HERE, "wanted.js")
    check("taskPayRows(type, tc)" in js and "reward_currency" in js and "reward_fixed" in js and "curIcon(M.currencyOf(cfg(), c))" in js,
          "%s wanted page: a task's Paid in and Fixed reward rows, the poster's currency icon" % _TAG)


# ---------------------------------------------------------------- outlaws and skins

def _outlaw_checks(check):
    import vocab
    ids = vocab.currency_ids(os.path.join(GAME, "content"))
    check(ids[:2] == ["gold", "gems"], "%s outlaws: the registry the Outlaws and skin selects list holds gold then gems (%s)" % (_TAG, ids))
    af = _read(HERE, "assets_fields.js")
    check("{ key: 'currency_type', label: 'Currency', type: 'select', options: (v) => v.currencies" in af and "v.currencies = sv.currency_records.map" in _read(HERE, "assets.js"),
          "%s outlaws: an Outlaw's Currency select is the registry's list (gold, gems)" % _TAG)
    srv = _read(HERE, "server.py")
    check("cur_ids = VOCAB.currency_ids(CONTENT)" in srv and "if cur is not None and cur not in cur_ids" in srv, "%s outlaws: the availability route takes any currency of the registry" % _TAG)
    import skins_io
    check("currency_type" in skins_io.SKIN_KEYS and "currencyOptions()" in _read(HERE, "skins.js"), "%s outlaws: a skin's currency select lists the registry (pass 111)" % _TAG)


# ---------------------------------------------------------------- store

def _store_checks(check):
    real = os.path.join(GAME, "content", "store", "store.json")
    have_fx = os.path.isfile(STORE_FIXTURE)
    r = _node(STORE_JS, real, STORE_FIXTURE if have_fx else "")
    b = r["bonus"]
    check(b["gems"] == {"gems_handful": 0, "gems_pile": 25, "gems_pouch": 50, "gems_box": 56, "gems_chest": 63, "gems_vault": 75},
          "%s store: the gem packs' bonus tags, gems a whole dollar against the cheapest (%s)" % (_TAG, b["gems"]))
    check(b["offers"] == {"coins_small": 0, "coins_medium": 10, "coins_large": 17} and set(b["off"].values()) == {0} and b["dollars"] == [1, 5, 1, 1],
          "%s store: the offers' tags, coins a gem against the smallest; none when show_bonus is off; whole dollars (%s)" % (_TAG, b["offers"]))
    check(r["nice"] == [17000, 1000, 3200, 1000, 0, 0, 123000, 7, 1000000, 10000], "%s store: nice() to 2 (or 3, 1) significant figures (%s)" % (_TAG, r["nice"]))
    u = r["rule"]
    check(u["common"] == [3000, 17000], "%s store: COMMON.md's two examples: 1,000 x 3 = 3,000; 5,500 x 3 x 1.05 = 17,325 -> 17,000 (%s)" % (_TAG, u["common"]))
    check(u["stages"] == [1000, 3000, 7000, 14000, 14000, 14000, 1000], "%s store: a stage step each stage, the last holding past the list, below 0 as 0 (%s)" % (_TAG, u["stages"]))
    check(u["trail"] == [14000, 14000, 15000, 15000, 15000, 16000, 20000], "%s store: a small step every 10 Trail levels (+5%%), rounded to 2 figures (%s)" % (_TAG, u["trail"]))
    check(u["steps"] == [0, 1, 8, 0] and u["stageMult"] == [7, 14, 1], "%s store: floor(T / step) (a step of 0: no Trail steps); stage_mult clamped (%s %s)" % (_TAG, u["steps"], u["stageMult"]))
    check(u["monotone"] and u["twoFigures"], "%s store: a later stage never gives less; every amount has at most two figures" % _TAG)
    p = r["preview"]
    check(p["offers"] == 3 and p["rows"] == 4 and p["cols"] == 6 and p["levels"] == [0, 10, 20, 40, 60, 83] and p["short"] == [0, 10, 20, 30] and p["name"] == "Blood Moon",
          "%s store: the preview: 3 offers x 4 stages x Trail 0, 10, 20, 40, 60, 83 (the Trail's top) (%s)" % (_TAG, p))
    check(p["first"] == [17000, 17000, 18000, 20000, 21000, 23000], "%s store: the medium offer at Nightfall across the Trail (%s)" % (_TAG, p["first"]))
    k = r["checks"]
    check(k["clean"] == [] and k["realErrs"] == [], "%s store: the defaults and the game's store.json have no error (%s)" % (_TAG, k["realErrs"]))
    check(k["v1"] == ["version"] and k["cents"] == ["gems.packs.0.price_cents", "gems.packs.0.price_text"] and k["text"] == ["gems.packs.1.price_text"] and k["dupe"] == ["coins.offers.0.id"]
          and k["ribbon"] == ["coins.offers.1.ribbon"] and k["amount"] == ["gems.packs.2.amount"], "%s store: version, cents, a price text that misnames, an id twice, a ribbon, an amount (%s)" % (_TAG, k))
    check(sorted(k["cur"]) == ["coins.pay", "revive.currency"] and k["same"] == ["coins.pay"] and k["noCtx"] == [] and k["pic"] == ["gems.packs.0.picture"],
          "%s store: an unknown currency, an offer paying what it gives, no registry = no currency check, a picture that is no res:// path (%s)" % (_TAG, k))
    check(sorted(k["scaling"]) == ["coins.scaling.round_sig", "coins.scaling.stage_mult", "coins.scaling.trail_per_step", "coins.scaling.trail_step"] and sorted(k["revive"]) == ["revive.per_run", "revive.price"],
          "%s store: the scaling's four and the revive's two (%s %s)" % (_TAG, k["scaling"], k["revive"]))
    check("coins.scaling.stage_mult" in k["warns"] and "revive.per_run" in k["warns"] and "gems.packs" in k["warns"] and "gems.packs.0.picture" in k["warns"],
          "%s store: warnings: fewer multipliers than stages, a paid revive never offered, two Best value ribbons, a missing picture (%s)" % (_TAG, k["warns"]))
    n = r["norm"]
    check(n["filled"] == "version,gems,coins,revive" and n["kept"] == 2 and n["same"], "%s store: normalise fills the blocks, keeps a key it does not know, leaves a whole file as it is" % _TAG)
    if not have_fx:
        print("%s: lane STORE's fixture %s is not here yet: the page's rule is not checked against the game's (tell the lead)" % (_TAG, os.path.relpath(STORE_FIXTURE, ROOT)))
    else:
        f = r.get("fixture") or {}
        n = f.get("n") or [0, 0, 0, 0]
        check(n[0] >= 60 and n[1] > 0 and n[2] > 0 and n[3] > 0, "%s store: lane STORE's fixture read (cases, edge, nice, bonus: %s)" % (_TAG, n))
        check(not f.get("cases") and not f.get("edge"), "%s store: the page's rule gives every coin amount of the game's fixture, its edge scaling too (%s %s)" % (_TAG, f.get("cases"), f.get("edge")))
        check(not f.get("nice"), "%s store: nice() as the game rounds (%s)" % (_TAG, f.get("nice")))
        check(not f.get("bonus"), "%s store: the offers' bonus tags at the amounts shown, stage by Trail level (%s)" % (_TAG, f.get("bonus")))
        if not f.get("sameFile"):   # Garry tunes store.json: a note, never a failure
            print("%s: store.json's offers or scaling differ from the fixture's (Garry's tuning?): the fixture still pins the rule" % _TAG)


def _storeio_checks(check):
    import store_io as SI
    real = _read(GAME, "content", "store", "store.json")
    check(SI.dump(json.loads(real)) == real and SI.check(json.loads(real), ["gold", "gems"]) == "", "%s storeio: the game's store.json in its own layout and the shape the game reads" % _TAG)
    tmp = _tree()
    try:
        srv = _Srv(tmp)
        path = SI.path_of(srv)
        none = SI.read(srv)
        check(none["ok"] and none["exists"] is False and none["json"] is None, "%s storeio: no file reads as none" % _TAG)
        _put(path, real)
        d = SI.read(srv)
        check(d["ok"] and d["exists"] and d["file"] == "content/store/store.json" and [c["id"] for c in d["currencies"]] == ["gold", "gems"] and d["currencies"][1]["icon_url"] == "/api/currencies/gems/icon",
              "%s storeio: the file and the currency registry (%s)" % (_TAG, d["currencies"]))
        check([s["name"] for s in d["stages"]] == ["Sundown", "Nightfall", "The Dust Bowl", "Blood Moon"] and d["map"] == "red_canyon" and d["trail_top"] == 18,
              "%s storeio: the first map's stages and the Trail's top level (%s, %s)" % (_TAG, d["stages"], d["trail_top"]))
        check(d["pictures"] == ["res://art/ui/store/gem.png", "res://art/ui/store/pack_sack.png"], "%s storeio: the store's pictures as res:// paths (%s)" % (_TAG, d["pictures"]))
        page = json.loads(real)
        for x in page["coins"]["scaling"]["stage_mult"]:
            pass
        page["coins"]["scaling"]["stage_mult"] = [int(x) for x in page["coins"]["scaling"]["stage_mult"]]   # as the page sends 1.0
        same = SI.save(srv, page, d["mtime"])
        check(same.get("ok") and same.get("unchanged") and not srv.backups and _read(path) == real, "%s storeio: the file sent back as the page holds it changes nothing (%s)" % (_TAG, same))
        disk = json.loads(real)
        disk["note"] = "Garry's"
        disk["coins"]["scaling"]["cap"] = 9
        disk["gems"]["packs"][1]["sale"] = True
        disk["revive"]["sound"] = "x"
        _put(path, json.dumps(disk))
        mt = srv.mtime_of(path)
        new = json.loads(real)
        new["gems"]["packs"][1]["amount"] = 550
        new["coins"]["offers"].append({"id": "coins_huge", "gems": 3000, "coins": 40000, "ribbon": "", "picture": ""})
        res = SI.save(srv, new, mt)
        after = _read(path)
        a = json.loads(after)
        check(res.get("ok") and srv.backups == ["store"] and a["gems"]["packs"][1]["amount"] == 550 and a["coins"]["offers"][-1]["id"] == "coins_huge", "%s storeio: a save, with one backup (%s)" % (_TAG, res))
        check(a.get("note") == "Garry's" and a["coins"]["scaling"].get("cap") == 9 and a["gems"]["packs"][1].get("sale") is True and a["revive"].get("sound") == "x",
              "%s storeio: keys the page does not know are kept (top, scaling, a pack by its id, the revive)" % _TAG)
        check("\r" not in after and after.endswith("}\n") and '"stage_mult": [1.0, 3.0, 7.0, 14.0]' in after and SI.dump(a) == after and after.count("\n      {") == 6 + 4,
              "%s storeio: LF, the floats kept, a pack or an offer a line" % _TAG)
        stale = SI.save(srv, new, 1.0)
        check(stale.get("status") == 409, "%s storeio: a stale page is refused (409)" % _TAG)
        bads = [SI.save(srv, dict(new, version=1), None), SI.save(srv, dict(new, revive=dict(new["revive"], currency="beans")), None),
                SI.save(srv, dict(new, coins=dict(new["coins"], offers=new["coins"]["offers"] + [dict(new["coins"]["offers"][0])])), None),
                SI.save(srv, dict(new, gems=dict(new["gems"], packs=[dict(new["gems"]["packs"][0], amount=0)])), None),
                SI.save(srv, dict(new, coins=dict(new["coins"], scaling=dict(new["coins"]["scaling"], trail_step=-1))), None), SI.save(srv, [], None)]
        check(all(x.get("status") == 400 for x in bads) and _read(path) == after, "%s storeio: version 1, an unknown currency, an id twice, no gems, a negative step, a list are refused and nothing is written (%s)" % (_TAG, [x.get("error") for x in bads]))
        _put(path, json.dumps({"version": 1, "currency": "gold", "show_bonus": True, "packs": [{"id": "pack_handful", "coins": 1000, "price_cents": 99, "price_text": "$0.99"}]}))
        up = SI.save(srv, json.loads(real), None)
        check(up.get("ok") and _read(path) == real, "%s storeio: a version 1 file is replaced whole by version 2 (none of its keys kept)" % _TAG)
        check(SI.picture_file(srv, "res://art/ui/store/gem.png") and SI.picture_file(srv, "res://art/ui/store/nope.png") is None and SI.picture_file(srv, "res://secret.png") is None
              and SI.picture_file(srv, "res://art/../secret.png") is None and SI.picture_file(srv, "res://art/ui/store/notes.txt") is None and SI.picture_file(srv, "C:/x.png") is None,
              "%s storeio: the picture route serves only a picture under art/" % _TAG)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _page_checks(check):
    idx = _read(HERE, "index.html")
    app = _read(HERE, "app.js")
    srv = _read(HERE, "server.py")
    check('data-tab="store"' in idx and 'id="tab-store"' in idx and 'href="store.css"' in idx and idx.index('src="store_model.js"') < idx.index('src="store.js"') < idx.index('src="instructions.js"'),
          "%s page: the Store tab, its section, its style and its two scripts (the model first)" % _TAG)
    check(idx.index('data-tab="trail"') < idx.index('data-tab="store"') < idx.index('data-tab="strings"'), "%s page: the Store tab sits after the Trail" % _TAG)
    check("Store.render(panel)" in app and "await Store.save(); return;" in app and "Store.dirty()" in app, "%s page: app.js renders, saves (Ctrl+S) and guards the tab" % _TAG)
    check("import store_io as STOREIO" in srv and srv.count("STOREIO.api_") == 2 and 'if parts[:1] == ["store"]:' in srv and 'if parts[:2] == ["api", "store"]:' in srv,
          "%s page: server.py routes /api/store (GET and POST)" % _TAG)
    r = _node("const J = require('./jobs_model.js'); console.log(JSON.stringify(['#store', '#trail'].map((h) => J.parseHash(h))));")
    check(r == [{"tab": "store"}, {"tab": "trail"}], "%s page: a reload comes back to the Store tab (%s)" % (_TAG, r))
    for f in ("store.js", "store_model.js", "trail.js", "trail_model.js", "wanted.js", "wanted_model.js", "app.js", "jobs_model.js", "assets_fields.js"):
        p = subprocess.run(["node", "--check", os.path.join(HERE, f)], capture_output=True, text=True)
        check(p.returncode == 0, "%s page: %s parses%s" % (_TAG, f, "" if p.returncode == 0 else ": " + p.stderr[-300:]))


def checks(check, run_node=None, server=None):
    if not shutil.which("node"):
        print("%s: node is not here: the models are not checked" % _TAG)
        groups = [_outlaw_checks]
    else:
        groups = [_trail_checks, _wanted_checks, _outlaw_checks, _store_checks, _storeio_checks, _page_checks]
    for g in groups:
        try:
            g(check)
        except Exception as e:   # noqa: BLE001
            import traceback
            traceback.print_exc()
            check(False, "%s %s: %s: %s" % (_TAG, g.__name__, type(e).__name__, e))


if __name__ == "__main__":
    import sys
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    n = [0, 0]

    def check(ok, msg):
        n[0 if ok else 1] += 1
        if not ok:
            print("FAIL", msg)
    checks(check)
    print("%d passed, %d failed" % tuple(n))
    sys.exit(1 if n[1] else 0)
